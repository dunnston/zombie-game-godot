class_name PlayerSim
extends RefCounted
## One player's simulation state: position, stamina, aim, what they hold
## and what they are doing with it. No nodes, no Input; only Intent.

var seat := 0
var display_name := "Survivor"

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var r: float = Config.PLAYER.r
var angle := 0.0

# Starting stats. Every attribute begins at rank 2 and rank 1 is the
# baseline, so a new survivor already carries one rank of each: 112 HP,
# 110 stamina, +9% melee, +6% chop, 8% crit. recompute_stats() (Phase 4)
# will produce all of these from attributes and perks; nothing mutates
# them on purchase.
var hp := 112.0
var max_hp := 112.0
var dead := false
var respawn_t := 0.0
var invuln := 0.0
var hurt_flash := 0.0
var last_hurt := 99.0
var god_mode := false

var max_stam := 110.0
var stam := 110.0
var stam_regen := 21.2
var stam_lock := 0.0
var winded := false
var sprinting := false
var sneaking := false
var speed_mul := 1.0
var melee_mul := 1.09
var gun_mul := 1.0
var spread_mul := 0.96
var range_mul := 1.0
var fire_rate_mul := 1.0
var reload_mul := 1.0
var crit_chance := 0.08
var free_shot_chance := 0.0
var noise_mul := 1.0
var threat_mul := 1.0
var chop_mul := 1.0
var chop_stam_mul := 1.0
var loot_mul := 1.0
var heal_mul := 1.0
var heal_speed_mul := 1.0
var armor_dr := 0.0
var lit := false                 # carrying a lit torch (Phase 3): seen further

var xp := 0

# What is held and carried. Phase 3 replaces the loadout with the hotbar
# and `res` with the slot grid; the resource API stays.
var loadout: Array[String] = []
var slot := 0
var res := {}                    # id -> count
var mag := {}                    # weapon id -> rounds loaded

var attack_cd := 0.0
var reloading := {}              # {w, t, dur, shell} or empty
var using := {}                  # {id, t, dur} or empty
var swing := {}                  # {t, dur, angle, arc, range} for the view
var recoil := 0.0
var recoil_dir := 1.0
var winded_told_at := -99.0
var needs_hint_at := -99.0

var intent := Intent.new()


# -------------------------------------------------------------- resources --

func count_res(id: String) -> int:
	return res.get(id, 0)


func add_res(id: String, n: int) -> void:
	res[id] = res.get(id, 0) + n


## Takes up to `n`, returns how many were taken.
func take_res(id: String, n: int) -> int:
	var have: int = res.get(id, 0)
	var take := mini(have, n)
	if take > 0:
		res[id] = have - take
	return take


# ---------------------------------------------------------------- weapons --

## What the player is swinging or firing. Empty hands means fists.
func weapon() -> Dictionary:
	if slot >= 0 and slot < loadout.size() and Config.WEAPONS.has(loadout[slot]):
		return Config.WEAPONS[loadout[slot]]
	return Config.WEAPONS.fists


func select_slot(i: int) -> void:
	if i < 0 or i >= loadout.size() or i == slot:
		return
	slot = i
	reloading = {}
	attack_cd = maxf(attack_cd, 0.14)


func cycle_slot(dir: int) -> void:
	var n := loadout.size()
	if n == 0:
		return
	select_slot(((slot + dir) % n + n) % n)


# ---------------------------------------------------------------- healing --

## Spend the smaller item unless the wound is big enough for a medkit.
func use_healing(sim: GameSim) -> bool:
	if not using.is_empty() or dead:
		return false
	if hp >= max_hp:
		sim.notify("Already at full health", "#8a8f84")
		return false
	var missing := max_hp - hp
	var pick := ""
	if missing > 45.0 and count_res("medkit") > 0:
		pick = "medkit"
	elif count_res("bandage") > 0:
		pick = "bandage"
	elif count_res("medkit") > 0:
		pick = "medkit"
	if pick.is_empty():
		sim.notify("No medical supplies", "#c96a5a")
		return false
	var c: Dictionary = Config.CONSUMABLES[pick]
	using = {"id": pick, "t": 0.0, "dur": c.time * heal_speed_mul}
	return true


func _finish_use(sim: GameSim) -> void:
	var c: Dictionary = Config.CONSUMABLES[using.id]
	if take_res(using.id, 1) > 0:
		Damage.heal_player(sim, self, c.heal)
	using = {}


# ------------------------------------------------------------------- step --

## One simulation step, driven entirely by `intent`. Nothing in here knows
## whether the intent came from this keyboard or from a wire.
func tick(sim: GameSim, dt: float) -> void:
	var it := intent
	var world := sim.world
	last_hurt += dt

	if dead:
		respawn_t -= dt
		if respawn_t <= 0.0:
			Damage.respawn_player(sim, self)
		return

	pos = world.unstick(pos, r)
	invuln = maxf(0.0, invuln - dt)
	hurt_flash = maxf(0.0, hurt_flash - dt)
	attack_cd = maxf(0.0, attack_cd - dt)
	recoil *= exp(-9.0 * dt)

	if not swing.is_empty():
		swing.t += dt
		if swing.t >= swing.dur:
			swing = {}

	# Aim, with the recoil kick on top.
	angle = atan2(it.aim.y - pos.y, it.aim.x - pos.x) + recoil * recoil_dir
	if recoil < 0.001:
		recoil_dir = 1.0 if sim.rng.chance(0.5) else -1.0

	# Healing roots you in place.
	var rooted := not using.is_empty()
	move(world, dt, rooted)

	if not using.is_empty():
		using.t += dt
		if using.t >= using.dur:
			_finish_use(sim)

	Combat.tick_reload(sim, self, dt)
	if not rooted:
		var w := weapon()
		if it.reload:
			Combat.start_reload(sim, self, w)

		if it.fire and attack_cd <= 0.0:
			if w.kind == "melee":
				# A refused swing (too winded to harvest) takes a short beat
				# rather than the full cooldown.
				attack_cd = w.cd if Combat.melee_attack(sim, self, w) else 0.3
			elif not reloading.is_empty() and not reloading.shell:
				pass                         # hold fire while a magazine swap finishes
			else:
				if not reloading.is_empty() and reloading.shell:
					reloading = {}           # pump-action interrupt
				if mag.get(w.id, 0) > 0:
					attack_cd = w.cd * fire_rate_mul
					Combat.fire_gun(sim, self, w)
				elif it.fire_pressed or w.get("bow", false):
					# One click, one magazine: holding the trigger on an empty
					# gun does not keep asking. A bow is the other thing: its
					# magazine of one is the nock, so holding keeps drawing.
					Combat.start_reload(sim, self, w)

		if it.slot >= 0:
			select_slot(it.slot)
		if it.wheel != 0:
			cycle_slot(it.wheel)
		if it.use:
			use_healing(sim)


## Stamina, speed and the actual step, from the movement half of the intent.
## Separate from tick so a guest can run exactly this to predict itself.
func move(world: World, dt: float, rooted := false) -> void:
	var it := intent
	var P := Config.PLAYER
	var moving := it.mx != 0.0 or it.my != 0.0

	sneaking = it.sneak
	sprinting = not sneaking and it.sprint and moving and stam > 1.0

	if sprinting:
		stam = maxf(0.0, stam - P.stam_drain * dt)
		stam_lock = P.stam_regen_delay
		if stam <= 0.0:
			sprinting = false
	else:
		stam_lock = maxf(0.0, stam_lock - dt)
		if stam_lock <= 0.0:
			stam = minf(max_stam, stam + stam_regen * dt)

	# Winded latches on running yourself flat and clears at half. The other
	# edge — a harvest swing turned down — is in Combat.melee_attack, the only
	# place that knows a swing was work. Clearing lives here, in the function
	# a guest also runs, so host and guest agree about when you may work.
	if stam <= 0.0:
		winded = true
	elif winded and stam >= max_stam * P.stam_winded_recovery:
		winded = false

	var speed: float = P.speed * speed_mul
	if sprinting:
		speed *= P.sprint_mul
	if sneaking:
		speed *= 0.5
	if rooted:
		speed = 0.0

	var k := Util.smooth(18.0, dt)
	vel.x += (it.mx * speed - vel.x) * k
	vel.y += (it.my * speed - vel.y) * k
	if not moving:
		vel *= exp(-11.0 * dt)
	pos = world.move_circle(pos, vel * dt, r)
