extends "res://tests/test_case.gd"
## Cars: the three ways into a locked one, arcade handling, fuel, what a car
## does to a crowd, the boot, and the tiles a parked one blocks.

var sim: GameSim
var p: PlayerSim

## A world of its own. Driving a car writes to `world.blocked` — releasing the
## tiles it was parked on is the whole point — so these tests would leave the
## shared world full of holes for every file that runs after them.
static var _car_world: World


static func car_world() -> World:
	if _car_world == null:
		_car_world = World.new()
	return _car_world


func before_each() -> void:
	sim = GameSim.new()
	sim.start(car_world(), 1)
	sim.enemies.list.clear()
	sim.events.clear()
	p = sim.players[0]


## Cars claim and release tiles in the shared `blocked` bitmap, which is the
## whole point of them — but it means one test parking somewhere leaves a wall
## there for the next. Every car gives its tiles back at the end of each test.
func after_each() -> void:
	for v in sim.cars.list:
		sim.cars.release_tiles(sim, v)


## A car with a full tank and its doors open, moved somewhere clear so the
## handling tests are about handling rather than about scenery.
func _open_car() -> Dictionary:
	var plot := clear_plot(10)
	var v: Dictionary = sim.cars.list[0]
	sim.cars.release_tiles(sim, v)
	v.pos = tile_centre(plot)
	v.angle = 0.0
	v.speed = 0.0
	v.locked = false
	v.hotwired = false
	v.fuel = Config.CAR.fuel_max
	v.hp = v.max_hp
	v.destroyed = false
	p.pos = v.pos
	return v


## Drives for `seconds` with the given intent, stepping only the cars.
func _drive(v: Dictionary, seconds: float, forward := 0.0, turn := 0.0, brake := false) -> void:
	var dt := 1.0 / 60.0
	for i in range(int(round(seconds / dt))):
		p.intent.my = forward
		p.intent.mx = turn
		p.intent.sprint = brake
		sim.enemies.rebuild_spatial()
		sim.cars.tick(sim, dt)
		# The player rides along in their own tick, not the car's.
		p.tick(sim, dt)
	p.intent.my = 0.0
	p.intent.mx = 0.0
	p.intent.sprint = false


# ------------------------------------------------------------- the fleet --

func test_the_town_is_full_of_cars() -> void:
	gt(sim.cars.list.size(), 20, "%d cars" % sim.cars.list.size())
	var locked := 0
	for v in sim.cars.list:
		locked += 1 if v.locked else 0
	var frac := float(locked) / sim.cars.list.size()
	# 62% is the spec; the roll is per car, so allow for the sample size.
	ok(frac > 0.4 and frac < 0.85, "%d of %d locked (%.2f)" % [locked, sim.cars.list.size(), frac])


func test_most_abandoned_cars_are_nearly_dry() -> void:
	var full := 0
	for v in sim.cars.list:
		if v.fuel > 10.0:
			full += 1
	var frac := float(full) / sim.cars.list.size()
	ok(frac < 0.5, "a full tank is a find, not the default (%d of %d)" % [full, sim.cars.list.size()])


func test_the_fleet_is_the_same_from_the_same_seed() -> void:
	# Cars are rolled off the world's own per-spawn seeds, so how many you
	# break into cannot shift them.
	var other := GameSim.new()
	other.start(car_world(), 999)
	eq(other.cars.list.size(), sim.cars.list.size())
	for i in range(sim.cars.list.size()):
		eq(other.cars.list[i].locked, sim.cars.list[i].locked, "car %d" % i)
		near(other.cars.list[i].fuel, sim.cars.list[i].fuel, 1e-6, "car %d" % i)


# ------------------------------------------------------------- the locks --

func test_a_key_is_hidden_near_every_locked_car() -> void:
	var keyed := 0
	var found := {}
	for c in sim.world.containers:
		for e in c.get("extra", []):
			if String(e.id).begins_with("key:"):
				found[String(e.id).substr(4)] = c
	for v in sim.cars.list:
		if not v.locked or String(v.key_id).is_empty():
			continue
		keyed += 1
		ok(found.has(v.key_id), "car %d has a key out there" % v.id)
		if found.has(v.key_id):
			var c: Dictionary = found[v.key_id]
			ok(Vector2(c.x, c.y).distance_to(v.pos) <= Config.CAR.key_range + 1.0,
				"and it is somewhere near the car")
	gt(keyed, 0, "some cars are locked and keyed")


func test_a_key_opens_the_car_it_belongs_to_and_is_spent() -> void:
	var v := {}
	for car in sim.cars.list:
		if car.locked and not String(car.key_id).is_empty():
			v = car
			break
	ok(not v.is_empty())
	p.car_keys.append(String(v.key_id))
	ok(sim.cars.has_key_for(p, v))
	ok(sim.cars.try_unlock(sim, p, v))
	ok(not v.locked)
	ok(not p.car_keys.has(v.key_id), "the key is used up on the car it opened")


func test_a_pick_is_a_gamble_that_costs_the_tool() -> void:
	var v := _open_car()
	v.locked = true
	p.bag.add("lockpick", 20)
	var opened := 0
	var picks := p.count_carried("lockpick")
	for i in range(20):
		if not v.locked:
			break
		sim.cars.try_unlock(sim, p, v)
		if not v.locked:
			opened += 1
	ok(p.count_carried("lockpick") < picks, "every attempt costs a pick")
	ok(opened > 0, "and enough of them get in")


func test_perception_moves_the_odds_without_settling_them() -> void:
	p.attrs["per"] = Config.ATTR_MIN
	Perks.recompute_stats(p)
	var low := Vehicles.pick_chance(p)
	p.attrs["per"] = Config.ATTR_MAX
	Perks.recompute_stats(p)
	var high := Vehicles.pick_chance(p)
	gt(high, low, "Perception helps")
	ok(low >= Config.CAR.pick_min, "never hopeless")
	ok(high <= Config.CAR.pick_max, "never certain")


func test_a_snapped_pick_is_heard() -> void:
	var v := _open_car()
	v.locked = true
	p.bag.add("lockpick", 40)
	p.attrs["per"] = Config.ATTR_MIN     # the worst odds we can arrange
	Perks.recompute_stats(p)
	var before := sim.threat.value
	var snapped := false
	for i in range(40):
		sim.events.clear()
		if not v.locked:
			v.locked = true              # relock and try again
		sim.cars.try_unlock(sim, p, v)
		if events_of(sim, "pick_snap").size() > 0:
			snapped = true
			break
	ok(snapped, "a pick snapped eventually")
	gt(sim.threat.value, before, "and something heard it")


func test_hotwire_is_the_third_way_in_and_takes_time() -> void:
	var v := _open_car()
	v.locked = true
	p.bag.clear_all()
	p.hotbar.clear_all()
	p.attrs["int"] = 5
	p.perks["hotwire"] = 1
	Perks.recompute_stats(p)
	ok(p.hotwire, "the perk is no longer refused for want of cars")

	ok(not sim.cars.try_unlock(sim, p, v), "it does not open instantly")
	ok(not p.using.is_empty(), "it starts a held action")
	eq(String(p.using.id), "hotwire")
	near(p.using.dur, Config.CAR.hotwire_time, 0.001)

	sim.cars.finish_hotwire(sim, p, v)
	ok(v.hotwired)
	ok(not v.locked, "and the car is yours")


func test_hotwire_rank_two_is_twice_as_fast() -> void:
	p.attrs["int"] = 5
	p.perks["hotwire"] = 1
	Perks.recompute_stats(p)
	var slow := Config.CAR.hotwire_time * p.hotwire_speed_mul
	p.perks["hotwire"] = 2
	Perks.recompute_stats(p)
	var fast := Config.CAR.hotwire_time * p.hotwire_speed_mul
	near(fast, slow * 0.5, 0.001)


func test_a_locked_car_with_nothing_to_open_it_says_so() -> void:
	var v := _open_car()
	v.locked = true
	p.bag.clear_all()
	p.hotbar.clear_all()
	ok(not sim.cars.try_unlock(sim, p, v))
	ok(v.locked)
	ok(sim.cars.prompt(p, v).contains("Locked"), sim.cars.prompt(p, v))


# ---------------------------------------------------------------- driving --

func test_getting_in_and_out() -> void:
	var v := _open_car()
	ok(sim.cars.enter(sim, p, v))
	eq(p.driving_id, int(v.id))
	ok(v.engine_on)
	eq(sim.cars.driven_by(p), v)

	ok(sim.cars.exit(sim, p))
	eq(p.driving_id, 0)
	ok(not v.engine_on)
	ok(not sim.world.is_blocked_px(p.pos.x, p.pos.y, sim.structs), "you step out onto open ground")


func test_one_seat_per_car() -> void:
	var v := _open_car()
	ok(sim.cars.enter(sim, p, v))
	var other := PlayerSim.new()
	other.seat = 1
	other.pos = v.pos
	sim.players.append(other)
	ok(not sim.cars.enter(sim, other, v), "somebody is already driving it")
	eq(other.driving_id, 0)


func test_a_car_accelerates_steers_and_brakes() -> void:
	var v := _open_car()
	sim.cars.enter(sim, p, v)
	var from: Vector2 = v.pos
	_drive(v, 1.5, -1.0)
	gt(v.speed, 50.0, "it got going: %.0f" % v.speed)
	gt(v.pos.distance_to(from), 40.0, "and went somewhere")

	var angle_before: float = v.angle
	_drive(v, 1.0, -1.0, 1.0)
	ok(absf(v.angle - angle_before) > 0.2, "and it turns while moving")

	_drive(v, 2.0, 0.0, 0.0, true)
	near(v.speed, 0.0, 5.0, "the brake stops it")


func test_a_stationary_car_cannot_spin_on_the_spot() -> void:
	var v := _open_car()
	sim.cars.enter(sim, p, v)
	var angle_before: float = v.angle
	_drive(v, 2.0, 0.0, 1.0)
	near(v.angle, angle_before, 0.001, "steering only bites when you are moving")


func test_a_car_with_no_fuel_does_not_move() -> void:
	var v := _open_car()
	v.fuel = 0.0
	sim.cars.enter(sim, p, v)
	var from: Vector2 = v.pos
	_drive(v, 2.0, -1.0)
	near(v.pos.distance_to(from), 0.0, 0.001)
	near(v.speed, 0.0, 0.001)


func test_driving_burns_fuel() -> void:
	var v := _open_car()
	sim.cars.enter(sim, p, v)
	var before: float = v.fuel
	_drive(v, 3.0, -1.0)
	ok(v.fuel < before, "%.1f -> %.1f" % [before, v.fuel])


func test_an_engine_is_heard_and_raises_threat() -> void:
	var v := _open_car()
	sim.cars.enter(sim, p, v)
	var before := sim.threat.value
	_drive(v, 3.0, -1.0)
	gt(sim.threat.value, before, "a car is not free travel — pillar 6")


func test_driving_is_all_you_can_do_at_the_wheel() -> void:
	# No walking, no swinging, no shooting out of the window.
	var v := _open_car()
	sim.cars.enter(sim, p, v)
	var e := sim.enemies.spawn("walker", v.pos + Vector2(60, 0))
	e.hp = 9999.0
	p.intent.fire = true
	p.intent.aim = e.pos
	run(sim, 1.0)
	p.intent.fire = false
	eq(sim.bullets.size(), 0, "the trigger does nothing while driving")
	near(e.hp, 9999.0, 0.001)


func test_the_player_rides_with_the_car() -> void:
	var v := _open_car()
	sim.cars.enter(sim, p, v)
	_drive(v, 1.5, -1.0)
	near(p.pos.distance_to(v.pos), 0.0, 0.001, "you are where the car is")


# --------------------------------------------------------------- roadkill --

func test_running_something_over_hurts_it_and_the_car() -> void:
	var v := _open_car()
	sim.cars.enter(sim, p, v)
	_drive(v, 2.0, -1.0)
	gt(v.speed, Config.CAR.ram_speed, "up to speed")

	var e := sim.enemies.spawn("walker", v.pos + Vector2.from_angle(v.angle) * 40.0)
	e.hp = 9999.0
	var car_hp: float = v.hp
	_drive(v, 0.6, -1.0)
	ok(e.hp < 9999.0, "the walker took it")
	ok(v.hp < car_hp, "and so did the car")


func test_a_roadkill_is_the_drivers() -> void:
	var v := _open_car()
	sim.cars.enter(sim, p, v)
	_drive(v, 2.0, -1.0)
	var xp_before := p.xp
	var e := sim.enemies.spawn("walker", v.pos + Vector2.from_angle(v.angle) * 40.0)
	_drive(v, 1.0, -1.0)
	if e.dead:
		gt(p.xp, xp_before, "their XP, their Luck on the drop")


func test_wrecking_a_car_puts_the_driver_out_rather_than_stranding_them() -> void:
	# `driven_by` filters out destroyed cars, so resolving through it after
	# marking one destroyed would leave `driving_id` set and the player unable
	# to walk, fight or get out.
	var v := _open_car()
	sim.cars.enter(sim, p, v)
	sim.cars.damage(sim, v, v.max_hp * 2.0, "crash")
	ok(v.destroyed)
	eq(p.driving_id, 0, "they are out")
	run(sim, 0.5)
	ok(not p.dead, "and can walk away from it")


func test_a_wreck_spills_its_boot_rather_than_taking_it_with_it() -> void:
	var v := _open_car()
	v.trunk = {"scrap": 40, "wood": 20}
	var before := sim.pickups.size()
	sim.cars.damage(sim, v, v.max_hp * 2.0)
	ok(v.destroyed)
	gt(sim.pickups.size(), before, "it is on the road")
	ok(v.trunk.is_empty())


func test_a_wreck_can_be_stripped_for_parts() -> void:
	var v := _open_car()
	sim.cars.damage(sim, v, v.max_hp * 2.0)
	var n := sim.cars.list.size()
	var ground := sim.pickups.size()
	ok(sim.cars.salvage(sim, v, p))
	eq(sim.cars.list.size(), n - 1, "the wreck is gone")
	gt(sim.pickups.size(), ground, "and left something behind")


# -------------------------------------------------------------- the boot --

func test_the_boot_takes_materials_and_not_your_rifle() -> void:
	var v := _open_car()
	p.bag.clear_all()
	p.carry_cap = 1000000.0
	p.bag.add("scrap", 120)
	p.bag.add("rifle", 1)
	sim.cars.stow(sim, v, p)
	eq(int(v.trunk.get("scrap", 0)), 120, "the haul goes in")
	eq(p.count_carried("rifle"), 1, "the rifle stays with you")
	eq(p.count_res("scrap"), 0)


func test_the_boot_has_a_limit() -> void:
	var v := _open_car()
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0
	for id in ["scrap", "wood", "stone", "cloth", "fiber", "sticks"]:
		p.bag.add(id, 200)
	sim.cars.stow(sim, v, p)
	ok(Vehicles.trunk_load(v) <= int(Config.CAR.trunk_cap),
		"%d of %d" % [Vehicles.trunk_load(v), int(Config.CAR.trunk_cap)])


func test_what_goes_in_comes_back_out() -> void:
	var v := _open_car()
	p.bag.clear_all()
	p.carry_cap = 1000000.0
	p.bag.add("scrap", 60)
	sim.cars.stow(sim, v, p)
	eq(p.count_res("scrap"), 0)
	sim.cars.unload(sim, v, p)
	eq(p.count_res("scrap"), 60)
	ok(v.trunk.is_empty())


func test_refuelling_takes_from_the_pack_then_the_stash() -> void:
	var v := _open_car()
	v.fuel = 0.0
	p.bag.clear_all()
	p.carry_cap = 1000000.0
	p.bag.add("fuel", 10)
	ok(sim.cars.refuel(sim, v, p))
	near(v.fuel, 10.0, 0.001)
	eq(p.count_res("fuel"), 0)


# ------------------------------------------------------- the parked tiles --

func test_a_parked_car_blocks_and_a_driven_one_does_not() -> void:
	# Parked somewhere this test owns, so it is not at the mercy of where an
	# earlier one left a car.
	var v := _open_car()
	sim.cars.occupy_tiles(sim, v)
	gt(v.tiles.size(), 0, "parked, it claims ground")
	var t: Vector2i = v.tiles[0]
	ok(sim.world.is_blocked_tile(t.x, t.y), "and blocks it")

	sim.cars.enter(sim, p, v)
	ok(not sim.world.is_blocked_tile(t.x, t.y), "driving frees the road")
	eq(v.tiles.size(), 0)

	sim.cars.exit(sim, p)
	gt(v.tiles.size(), 0, "parking claims new ground")


func test_parking_never_claims_a_tile_something_else_owns() -> void:
	# Releasing a claimed tile sets it clear, so claiming one a wall already
	# owns would punch a hole in the wall the next time the car moved.
	var plot := clear_plot(10)
	var v := _open_car()
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0
	p.bag.add("wood", 200)
	p.pos = tile_centre(plot)
	var wall := sim.structs.place(sim, "woodWall", plot.x + 1, plot.y, p)
	ok(not wall.is_empty())

	v.pos = tile_centre(Vector2i(plot.x + 1, plot.y))
	sim.cars.occupy_tiles(sim, v)
	for t: Vector2i in v.tiles:
		ne(t, Vector2i(plot.x + 1, plot.y), "it did not claim the wall's tile")


# ----------------------------------------------------------------- the save --

func test_a_run_of_cars_survives_a_save() -> void:
	var v := _open_car()
	v.trunk = {"scrap": 30}
	v.fuel = 12.5
	v.locked = false
	v.hotwired = true
	var d := SaveGame.to_dict(sim)
	gt(int(d.cars.size()), 0)
	var rec := {}
	for row in d.cars:
		if int(row.id) == int(v.id):
			rec = row
			break
	ok(not rec.is_empty())
	near(float(rec.fuel), 12.5, 0.001)
	ok(bool(rec.hotwired))
	eq(int(rec.trunk.scrap), 30)
	# `si` comes back from the generator, so a save has no business storing it.
	ok(not rec.has("si"), "what the seed makes is not what a save carries")


func test_a_car_key_is_learned_rather_than_carried() -> void:
	# Weightless, slotless, undroppable: a key you could leave in a chest would
	# make "whose car is this?" unanswerable again.
	var v := {}
	for car in sim.cars.list:
		if car.locked and not String(car.key_id).is_empty():
			v = car
			break
	ok(not v.is_empty())
	var weight := p.carried_weight()
	Loot.give_entry(sim, p, {"id": "key:" + String(v.key_id), "n": 1})
	ok(p.car_keys.has(v.key_id))
	near(p.carried_weight(), weight, 0.001, "it weighs nothing")
	eq(p.bag.count("key:" + String(v.key_id)), 0, "and takes no slot")
