class_name PlayerSim
extends RefCounted
## One player's simulation state: position, stamina, aim, what they hold
## and what they are doing with it. No nodes, no Input; only Intent.

var seat := 0
var display_name := "Survivor"
## Who this character belongs to, across sessions. The host's own is ""; a
## guest's is the id their machine made up the first time it joined anything,
## so the host's save can hand the same character back next week (Phase 5).
var identity := ""
## Parked: the guest who owns this character is not connected. An away player
## is not ticked, not drawn, not targeted and not counted. Their character
## stays in the world's save so they get it back.
var away := false

var pos := Vector2.ZERO
## Where `pos` was at the top of this tick. Presentation only: the views lerp
## between the two so movement is smooth on a monitor faster than 60Hz.
var prev_pos := Vector2.ZERO
var vel := Vector2.ZERO
var r: float = Config.PLAYER.r
var angle := 0.0

# What a point has been spent on. These two dictionaries and the worn gear
# are the *whole* build: every number below them is derived from these by
# `Perks.recompute_stats` and by nothing else (invariant 4), which is why a
# save stores only these and re-derives the rest.
var level := 1
var xp := 0.0
var xp_next: int = Config.xp_for_level(1)
var skill_points := 0
## Built in _init, for the same reason `bag` is: a member initializer runs
## while the class is still loading and cannot reach another class_name.
var attrs := {}
var perks := {}                  # perk id -> rank

# Derived stats. Every one of these is overwritten wholesale by
# `Perks.recompute_stats` from `Config.STAT_BASE`, so the values here are
# only what a PlayerSim holds between `new()` and the first recompute —
# `_init` runs one immediately. Do not tune anything here; tune STAT_BASE.
var hp := 112.0
var max_hp := 112.0
var dead := false
var respawn_t := 0.0
## Downed, not dead (co-op only): on the ground for `downed_time`, and a
## teammate holding E beside you gets you back up. Nobody comes: you die as
## you always did. Alone there is no one to come, so alone you just die.
var downed := false
var down_t := 0.0
## The teammate you are getting up: {seat, t, dur}. A held channel like
## searching — let go, or step away, and it stops.
var reviving := {}
var invuln := 0.0
var hurt_flash := 0.0
var last_hurt := 99.0
var god_mode := false

## The main status. You were bitten before the game started and there is no
## cure; brain matter is what holds it back. `mut_band` is the derived half —
## which of `Config.MUTATION.bands` this value falls in — and it is what
## `recompute_stats` reads, so the meter can drift without touching a stat.
## Everything that writes either of these goes through `Mutation`.
var mutation := 0.0
var mut_band := 0
## The Lurch: seconds left of your legs not being yours, and seconds until the
## next one. Both are ticked by `Mutation` and read by nobody else.
var lurch_t := 0.0
var lurch_cd := 0.0
## Buffs and debuffs, id -> seconds left. Applied inside the recompute like
## everything else that modifies a stat (invariant 4).
var effects := {}

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
## Added to the weapon's own `crit_mul`, so what a critical costs the thing it
## lands on is part weapon and part you. Luck writes it; so does a Surge.
var crit_dmg := 0.03
var free_shot_chance := 0.0
var noise_mul := 1.0
var threat_mul := 1.0
## How far a zombie senses you, how hard a hit rocks you, and how fast the
## change takes hold. Written by the recompute from the Mutation band and by
## nothing else.
var sense_mul := 1.0
var stagger_mul := 1.0
var mut_rate_mul := 1.0
var chop_mul := 1.06
var chop_stam_mul := 1.0
var loot_mul := 1.0
var rare_loot_mul := 1.05
var double_drop_chance := 0.0
var heal_mul := 1.0
var heal_speed_mul := 1.0
var search_mul := 0.95
var build_cost_mul := 0.97
var struct_hp_mul := 1.0
var turret_mul := 1.05
var craft_yield_mul := 1.0
var xp_mul := 1.07
var radar_mul := 1.0
var armor_dr := 0.0
var lit := false                 # carrying a lit light: noticed further out
var carry_cap: float = Config.PLAYER.carry_cap + 25.0
var pickup_range: float = Config.PLAYER.pickup_range + 3.0

# Read by Phase 4c's survivors, produced here so no perk is inert.
var survivor_cap := 1
var survivor_dmg_mul := 1.06
var survivor_hp_mul := 1.0
var survivor_xp_mul := 1.0
var upkeep_mul := 1.0

# Perk flags and their state. `adrenaline_active` is recomputed every tick
# from health, and `second_wind_cd` is the only piece of build state that
# ticks down — so it is saved, unlike everything else derived.
var adrenaline := false
var adrenaline_active := false
var second_wind := false
var second_wind_cd := 0.0
var hotwire := false
var hotwire_speed_mul := 1.0

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
## Condition is deliberately NOT here: it lives on the slot, so it travels
## with the weapon into a chest or another player's pack. See `Wear`.

# The off-hand light. The charge lives here rather than in the slot, because
# a slot is only {id, n}; Equipment keeps the two in step.
var light_on := false
var light_fuel := 0.0
var light_id := ""
## You put it out on purpose. An equipped light strikes itself when the dark
## arrives, so without this the next frame would undo every deliberate
## dousing — and going dark to lose something following you is a real move.
## Daybreak clears it, so tomorrow night lights itself again.
var light_doused := false
## Burn left per light id, so swapping between two lights and back does not
## refill either one.
var light_charge := {}

## The tile of the bedroll this player respawns at, or (-1, -1) for "wherever
## is safe". Only the newest bedroll is yours (Phase 3b).
var spawn_tile := Vector2i(-1, -1)

var attack_cd := 0.0
var reloading := {}              # {w, t, dur, shell} or empty
## The car this player is at the wheel of, or 0. An id rather than a
## reference, so a save stores it and a wrecked car cannot leave a dangling
## one behind.
var driving_id := 0
## Keys found in containers, by the id printed on them.
var car_keys: Array[String] = []

var using := {}                  # {id, t, dur} or empty
var searching := {}              # {container, t, dur} or empty
## Tap E to drive, hold it for the boot. Both answer the same key, so the
## choice cannot be made on the press frame — `interact_held` is already true
## then, which is what made tap-to-drive unreachable. {car, t, dur} or empty.
var car_hold := {}
var swing := {}                  # {t, dur, angle, arc, range} for the view
var recoil := 0.0
var recoil_dir := 1.0
var winded_told_at := -99.0
var needs_hint_at := -99.0
var broken_told_at := -99.0

var intent := Intent.new()


func _init() -> void:
	bag = Slots.new(Config.PLAYER.inv_slots)
	hotbar = Slots.new(Config.PLAYER.hotbar_slots)
	attrs = Perks.starting_attrs()
	# So the literals above are never what anything reads: a fresh survivor's
	# stats come from the same pass that a fully built one's do.
	Perks.recompute_stats(self)
	hp = max_hp
	stam = max_stam


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
	if not start_use(sim, pick):
		return false
	# Field Medic is a healing perk, so it shortens a bandage and not a meal:
	# the multiplier is applied here rather than inside the shared channel.
	using.dur *= heal_speed_mul
	return true


# ------------------------------------------------------------- suppressing --

## Take something for the Mutation meter. The same held channel healing uses,
## so being hit interrupts a dose exactly as it interrupts a bandage — and so
## a guest's press travels as intent rather than as a command.
func use_suppressant(sim: GameSim) -> bool:
	if not using.is_empty() or dead:
		return false
	if mutation <= 0.0:
		sim.notify("Nothing to suppress", "#8a8f84")
		return false
	var pick := Mutation.pick_suppressant(self)
	if pick.is_empty():
		sim.notify("No brain matter", "#c96a5a")
		return false
	return start_use(sim, pick)


## Eat or drink something, for the buff. There is no hunger meter under this
## and there never will be (pillar 1) — so the rule for what a tap of the key
## reaches for is "the commonest thing that would actually do something":
## lowest `rank` first, and never a second helping of a buff already running.
func use_food(sim: GameSim) -> bool:
	if not using.is_empty() or dead:
		return false
	var pick := ""
	var pick_rank := INF
	for id in Config.CONSUMABLES:
		var c: Dictionary = Config.CONSUMABLES[id]
		if not c.get("food", false) or count_carried(id) <= 0:
			continue
		if effects.has(String(c.get("effect", ""))):
			continue                     # already running: do not waste it
		if float(c.get("rank", 0)) < pick_rank:
			pick_rank = float(c.get("rank", 0))
			pick = id
	if pick.is_empty():
		# Two different refusals, because they mean opposite things: nothing
		# to eat is a supply problem, everything already running is not.
		var carried := false
		for id in Config.CONSUMABLES:
			if Config.CONSUMABLES[id].get("food", false) and count_carried(id) > 0:
				carried = true
				break
		sim.notify("Nothing left to eat" if not carried else "Everything you are carrying is already working", "#8a8f84")
		return false
	return start_use(sim, pick)


## One consumable, through the one channel. Everything that consumes anything
## ends up here — the two quick keys, and the pack screen's right-click — so
## being hit interrupts all of it the same way, and a guest's use is the same
## code path as the host's.
func start_use(sim: GameSim, id: String) -> bool:
	if not using.is_empty() or dead:
		return false
	var c: Dictionary = Config.CONSUMABLES.get(id, {})
	if c.is_empty() or c.get("tool", false) or count_carried(id) <= 0:
		return false
	# A bandage at full health is the one refusal worth explaining; the rest
	# of the table always does something.
	if float(c.get("heal", 0.0)) > 0.0 and not c.has("effect") and float(c.get("mut", 0.0)) <= 0.0 and hp >= max_hp:
		sim.notify("Already at full health", "#8a8f84")
		return false
	using = {"id": id, "t": 0.0, "dur": float(c.time)}
	return true


func _finish_use(sim: GameSim) -> void:
	# Hotwiring is a held action like healing is, so it rides the same timer —
	# and is interrupted the same way, by being hit.
	if String(using.id) == "hotwire":
		sim.cars.finish_hotwire(sim, self, sim.cars.by_id(int(using.vehicle)))
		using = {}
		return
	if String(using.id) == "pick":
		sim.cars.finish_pick(sim, self, sim.cars.by_id(int(using.vehicle)))
		using = {}
		return
	var id := String(using.id)
	var c: Dictionary = Config.CONSUMABLES[id]
	if take_carried(id, 1) > 0:
		# One item can do more than one of these — a Hot Meal both patches you
		# up and steadies your hands — so these are three questions, not a
		# match with three branches.
		if float(c.get("heal", 0.0)) > 0.0:
			Damage.heal_player(sim, self, float(c.heal))
		if Mutation.is_suppressant(id):
			Mutation.take_dose(sim, self, id)
		elif c.has("effect"):
			Mutation.give_effect(sim, self, String(c.effect), float(c.get("effect_mul", 1.0)))
			sim.emit({"t": "ate", "seat": seat, "x": pos.x, "y": pos.y, "id": id})
	using = {}


# ------------------------------------------------------------------- step --

## One simulation step, driven entirely by `intent`. Nothing in here knows
## whether the intent came from this keyboard or from a wire.
func tick(sim: GameSim, dt: float) -> void:
	var it := intent
	var world := sim.world
	# Where the view should draw from until the next step lands.
	prev_pos = pos
	if away:
		return
	last_hurt += dt

	if dead:
		respawn_t -= dt
		if respawn_t <= 0.0:
			Damage.respawn_player(sim, self)
		return

	# The change, and the clocks on whatever you have taken. Above the downed
	# branch on purpose: bleeding out on the ground is exactly when it gets on
	# with it.
	Mutation.tick(sim, self, dt)
	if dead:
		return                          # turning is a death, and it happens here

	# The light, above the downed and driving branches on purpose: it is a
	# clock, not an action. Everything it does — striking itself when the dark
	# comes, spending `burn`, going out at dawn, burning away — is the world
	# happening to you, and none of it stops because you are bleeding out or
	# behind a wheel. Down here with the rest of the tick it would have meant
	# a torch carried into a car never lit, and a lit one hanging in the air
	# for free: visible (`LightView` draws a downed player's light, and a
	# driver's follows the car), burning no fuel and never doused by the dawn.
	# Pressing T stays at the bottom with the other input, because striking a
	# torch *is* an action and you cannot do it from the floor.
	Equipment.update_light(sim, self, dt)

	# ...and if it is driving, everything below this reads its intent, not
	# yours. Rewritten once here rather than guarded in twenty branches.
	if lurch_t > 0.0 and not downed:
		Mutation.hijack_intent(sim, self)

	if downed:
		# Bleeding out. Nothing else happens to you: you cannot move, swing,
		# reload or search, and being hit again does nothing — the clock is
		# the threat now. `Damage.tick_downed` is where the clock runs out.
		vel = Vector2.ZERO
		swing = {}
		reloading = {}
		using = {}
		searching = {}
		reviving = {}
		car_hold = {}
		Damage.tick_downed(sim, self, dt)
		return

	# Adrenaline is a state, not a modifier: it comes and goes with the health
	# bar, so it is read fresh each tick rather than baked into the recompute.
	adrenaline_active = adrenaline and hp < max_hp * Config.ADRENALINE_HP_FRAC
	second_wind_cd = maxf(0.0, second_wind_cd - dt)

	# Behind the wheel, the car is what moves and `Vehicles` is what reads the
	# intent. Nothing below this applies: no walking, no swinging, no
	# reloading, and no shooting out of the window. The whole body of the tick
	# is skipped rather than each part being guarded, so there is one place to
	# look for "what can you do while driving" and the answer is "drive".
	if driving_id > 0:
		var car := sim.cars.by_id(driving_id)
		if car.is_empty():
			driving_id = 0                # it was wrecked out from under us
		else:
			# The car sets `pos` and `angle` at the end of its own tick, which
			# runs after this one — copying them here would draw the driver a
			# frame behind the car they are sitting in.
			invuln = maxf(0.0, invuln - dt)
			hurt_flash = maxf(0.0, hurt_flash - dt)
			if it.interact:
				sim.cars.exit(sim, self)
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

	# Healing roots you in place, and so does getting somebody up.
	var rooted := not using.is_empty() or not reviving.is_empty()
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
		if it.suppress:
			use_suppressant(sim)
		if it.eat:
			use_food(sim)

	if it.light:
		Equipment.toggle_light(sim, self)
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
	if adrenaline_active:
		speed *= Config.ADRENALINE_SPEED
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
