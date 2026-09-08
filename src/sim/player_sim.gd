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
var search_mul := 1.0
var armor_dr := 0.0
var lit := false                 # carrying a lit light: noticed further out
var carry_cap: float = Config.PLAYER.carry_cap
var pickup_range: float = Config.PLAYER.pickup_range

var xp := 0

# One addressable list for everything carried, so it can all be moved,
# dropped and looked at the same way. Capacity is by weight, not slot count,
# but the grids are finite too: hoarding thirty kinds of thing still costs.
## Built in _init rather than here: a member initializer runs while the class
## is still loading, and reaching for another class_name at that moment is
## how you get "nonexistent function 'new'".
var bag: Slots
var hotbar: Slots
var equip := {"head": "", "body": "", "hands": "", "legs": "", "feet": "", "offhand": ""}
var start_weapon: String = Config.START_KIT.weapon
var slot := 0
var mag := {}                    # weapon id -> rounds loaded

# The off-hand light. The charge lives here rather than in the slot, because
# a slot is only {id, n}; Equipment keeps the two in step.
var light_on := false
var light_fuel := 0.0
var light_id := ""
## Burn left per light id, so swapping between two lights and back does not
## refill either one.
var light_charge := {}

## The tile of the bedroll this player respawns at, or (-1, -1) for "wherever
## is safe". Only the newest bedroll is yours (Phase 3b).
var spawn_tile := Vector2i(-1, -1)

var attack_cd := 0.0
var reloading := {}              # {w, t, dur, shell} or empty
var using := {}                  # {id, t, dur} or empty
var searching := {}              # {container, t, dur} or empty
var swing := {}                  # {t, dur, angle, arc, range} for the view
var recoil := 0.0
var recoil_dir := 1.0
var winded_told_at := -99.0
var needs_hint_at := -99.0

var intent := Intent.new()


func _init() -> void:
	bag = Slots.new(Config.PLAYER.inv_slots)
	hotbar = Slots.new(Config.PLAYER.hotbar_slots)


# -------------------------------------------------------------- resources --
#
# The pack is where supplies live: ammunition, materials, everything a rule
# spends. These three keep the names Phase 2 used and answer for the pack, so
# reloading and building need not know the inventory was rebuilt underneath
# them. `count_carried` is the wider question — the hotbar counts too — and
# only the things you hold in your hand ask it.

func count_res(id: String) -> int:
	return bag.count(id)


func add_res(id: String, n: int) -> int:
	return bag.add(id, n)


## Takes up to `n`, returns how many were taken.
func take_res(id: String, n: int) -> int:
	return bag.take(id, n)


func count_carried(id: String) -> int:
	return bag.count(id) + hotbar.count(id)


## Spends from the hotbar first, so the stack you can see going down is the
## one you were watching.
func take_carried(id: String, n: int) -> int:
	var got := hotbar.take(id, n)
	if got < n:
		got += bag.take(id, n - got)
	return got


func carries(id: String) -> bool:
	return count_carried(id) > 0


func carried_weight() -> float:
	return bag.weight() + hotbar.weight()


## How much weight the pack may still take. The budget covers pack and hotbar
## together, because that is what the weight bar shows — check against
## anything narrower and loot keeps fitting after the bar has passed 100%.
func pack_allowance() -> float:
	return carry_cap - hotbar.weight()


func overloaded() -> bool:
	return carried_weight() > carry_cap


## What a bill costs after this player's building or crafting perks
## (Phase 4 — for now the multiplier is 1).
static func scaled_cost(cost: Dictionary, mul := 1.0) -> Dictionary:
	var out := {}
	for id in cost:
		out[id] = ceili(cost[id] * mul)
	return out


## What is available to spend: the pack, plus the base's shared stash. A
## wall you are building beside your stash may be paid for out of it.
func total_res(sim: GameSim, id: String) -> int:
	var n := bag.count(id)
	if sim != null and sim.stash != null:
		n += sim.stash.count(id)
	return n


func can_afford(sim: GameSim, cost: Dictionary, mul := 1.0) -> bool:
	for id in cost:
		if total_res(sim, id) < ceili(cost[id] * mul):
			return false
	return true


## Spends from the pack first, then the stash. Assumes `can_afford` passed.
func spend(sim: GameSim, cost: Dictionary, mul := 1.0) -> void:
	for id in cost:
		var need := ceili(cost[id] * mul)
		need -= bag.take(id, need)
		if need > 0 and sim != null and sim.stash != null:
			sim.stash.take(id, need)


# ---------------------------------------------------------------- weapons --

## The item id in the selected hotbar slot, or "" for empty hands.
func held_id() -> String:
	return hotbar.id_at(slot)


## What the player is swinging or firing. An empty slot, or one holding
## something that is not a weapon, means fists — you can still punch.
func weapon() -> Dictionary:
	var id := held_id()
	if Config.WEAPONS.has(id):
		return Config.WEAPONS[id]
	return Config.WEAPONS.fists


## Which hotbar slot holds `id`, or -1. The tests and the smoke run reach for
## a named weapon; the player reaches for a number.
func hotbar_index(id: String) -> int:
	for i in range(hotbar.size()):
		if hotbar.id_at(i) == id:
			return i
	return -1


func select_slot(i: int) -> void:
	if i < 0 or i >= hotbar.size() or i == slot:
		return
	slot = i
	reloading = {}
	attack_cd = maxf(attack_cd, 0.14)


func cycle_slot(dir: int) -> void:
	var n := hotbar.size()
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
	if missing > 45.0 and count_carried("medkit") > 0:
		pick = "medkit"
	elif count_carried("bandage") > 0:
		pick = "bandage"
	elif count_carried("medkit") > 0:
		pick = "medkit"
	if pick.is_empty():
		sim.notify("No medical supplies", "#c96a5a")
		return false
	var c: Dictionary = Config.CONSUMABLES[pick]
	using = {"id": pick, "t": 0.0, "dur": c.time * heal_speed_mul}
	return true


func _finish_use(sim: GameSim) -> void:
	var c: Dictionary = Config.CONSUMABLES[using.id]
	if take_carried(using.id, 1) > 0:
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

	pos = world.unstick(pos, r, sim.structs)
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
	move(world, dt, rooted, sim.structs)

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
				# Pump-action interrupt: pulling the trigger part way through
				# a shell-at-a-time reload sends what is already in the tube.
				# Only when there IS one — an empty shotgun with the trigger
				# held would otherwise cancel its own reload every frame and
				# never refill at all. (Found by the compound raid harness:
				# a defender holding fire killed nothing for two minutes.)
				if not reloading.is_empty() and reloading.shell and mag.get(w.id, 0) > 0:
					reloading = {}
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

	if it.light:
		Equipment.toggle_light(sim, self)
	Equipment.update_light(sim, self, dt)
	Interact.tick(sim, self, dt)
	if not it.build_action.is_empty():
		_build(sim, it)


## Building reaches the sim the same way everything else does: as an intent
## edge, so a guest's build command runs this identical code.
func _build(sim: GameSim, it: Intent) -> void:
	var t := it.build_tile
	match it.build_action:
		"place":
			sim.structs.place(sim, it.build_type, t.x, t.y, self)
		"repair":
			var s := sim.structs.at_tile(t.x, t.y)
			if not s.is_empty():
				sim.structs.repair(sim, s, self)
		"repair_all":
			sim.structs.repair_all(sim, self)
		"demolish":
			var s := sim.structs.at_tile(t.x, t.y)
			if not s.is_empty():
				sim.structs.demolish(sim, s, self)


## Stamina, speed and the actual step, from the movement half of the intent.
## Separate from tick so a guest can run exactly this to predict itself.
func move(world: World, dt: float, rooted := false, structs: Structures = null) -> void:
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
	pos = world.move_circle(pos, vel * dt, r, structs)
