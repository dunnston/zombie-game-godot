extends "res://tests/test_case.gd"
## Building: what may be placed and what may not, walls as the second
## collision source, what a horde does to them, power, turrets, traps,
## repair and salvage. Every assertion is an outcome: the field goes round
## it, the brute gets through it, the turret kills.

var sim: GameSim
var p: PlayerSim
var plot: Vector2i


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = clear_plot(10)
	p.pos = tile_centre(plot)
	p.intent.aim = p.pos + Vector2.RIGHT


## Enough of everything to build whatever a test asks for. A grid this size
## is not a thing the game hands out — thirty slots of stone is the real
## limit — but a placement test should fail on the rule it is testing and
## not on running out of pockets.
func _stock(n := 400) -> void:
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0
	for id in ["wood", "stone", "sticks", "scrap", "cloth", "elec", "parts", "mil", "fuel", "ammoP"]:
		p.bag.add(id, n)


func _build(type: String, tx: int, ty: int) -> Dictionary:
	return sim.structs.place(sim, type, tx, ty, p)


# -------------------------------------------------------------- placement --

func test_a_wall_costs_what_the_table_says() -> void:
	_stock()
	var before := p.count_res("wood")
	var s := _build("woodWall", plot.x + 2, plot.y)
	ok(not s.is_empty(), "the wall went up")
	eq(p.count_res("wood"), before - 16, "16 wood, as the table says")
	eq(s.hp, 340.0)
	ok(sim.structs.solid_at(plot.x + 2, plot.y), "and it blocks the tile")


func test_you_cannot_build_without_the_materials() -> void:
	var check := sim.structs.can_place(sim, "woodWall", plot.x + 2, plot.y, p)
	ok(not check.ok)
	eq(check.reason, "Not enough materials")
	eq(sim.structs.count(), 0)


func test_every_refusal_says_which_one() -> void:
	_stock()
	# On top of yourself.
	var here := Vector2i(floori(p.pos.x / 32), floori(p.pos.y / 32))
	eq(sim.structs.can_place(sim, "woodWall", here.x, here.y, p).reason, "You are standing there")
	# Out of reach.
	eq(sim.structs.can_place(sim, "woodWall", plot.x + 8, plot.y, p).reason, "Too far")
	# On terrain that is already solid.
	var wall_tile := _find_blocked_tile()
	if wall_tile.x >= 0:
		eq(sim.structs.can_place(sim, "woodWall", wall_tile.x, wall_tile.y, p).reason, "Blocked")
	# On top of another piece.
	_build("woodWall", plot.x + 2, plot.y)
	eq(sim.structs.can_place(sim, "woodWall", plot.x + 2, plot.y, p).reason, "Occupied")
	# On an enemy.
	var e := sim.enemies.spawn("walker", tile_centre(Vector2i(plot.x + 3, plot.y)))
	eq(sim.structs.can_place(sim, "woodWall", plot.x + 3, plot.y, p).reason, "Enemy in the way")
	e.dead = true
	# Tier 2 without the bench.
	eq(sim.structs.can_place(sim, "metalWall", plot.x + 4, plot.y, p).reason, "Needs Workbench II")


func _find_blocked_tile() -> Vector2i:
	for r in range(1, 12):
		for j in range(-r, r + 1):
			for i in range(-r, r + 1):
				var t := Vector2i(plot.x + i, plot.y + j)
				if sim.world.is_blocked_tile(t.x, t.y):
					return t
	return Vector2i(-1, -1)


func test_loot_is_never_buried() -> void:
	_stock()
	var c: Dictionary = sim.world.containers[0]
	p.pos = Vector2(c.x, c.y + 40)
	# A container blocks its own tile, so the terrain check refuses it: the
	# outcome is what matters, not which rule said no.
	ok(not sim.structs.can_place(sim, "woodWall", c.tx, c.ty, p).ok)
	ok(sim.structs.at_tile(c.tx, c.ty).is_empty())


func test_the_upgraded_bench_unlocks_steel() -> void:
	_stock()
	var bench := _build("workbench", plot.x + 2, plot.y)
	eq(sim.structs.bench_tier, 1)
	ok(not sim.structs.is_unlocked("metalWall"), "steel is still locked")
	ok(sim.structs.upgrade_bench(sim, bench, p))
	eq(sim.structs.bench_tier, 2)
	ok(sim.structs.is_unlocked("metalWall"), "and now it is not")


# --------------------------------------------------------------- collision --

func test_a_wall_stops_a_player_walking_into_it() -> void:
	_stock()
	_build("woodWall", plot.x + 2, plot.y)
	p.pos = tile_centre(Vector2i(plot.x, plot.y))
	p.intent.mx = 1.0
	for i in range(120):
		sim.tick(1.0 / 60.0)
	ok(p.pos.x < (plot.x + 2) * 32, "stopped short of the wall at %.0f" % p.pos.x)


func test_a_wall_makes_the_flow_field_go_round() -> void:
	_stock()
	# A three-tile wall across the approach, with a way round the end.
	for dy in range(-1, 2):
		_build("woodWall", plot.x + 2, plot.y + dy)
	var nf := sim.nav_for(p)
	var through: int = nf.distance_at(Vector2i(plot.x + 2, plot.y))
	var beside: int = nf.distance_at(Vector2i(plot.x + 3, plot.y))
	eq(through, -1, "the wall tile itself is not walkable")
	gt(beside, 3, "and the way in from behind it is %d tiles, not the 3 a straight line would be" % beside)


func test_you_can_shoot_over_your_own_barricade() -> void:
	_stock()
	_build("woodWall", plot.x + 2, plot.y)
	var a := tile_centre(Vector2i(plot.x, plot.y))
	var b := tile_centre(Vector2i(plot.x + 4, plot.y))
	ok(not sim.world.has_line_of_sight(a, b, 12.0, sim.structs), "a wall blocks sight")
	ok(sim.world.has_terrain_line_of_sight(a, b), "but not a bullet — invariant 3")


func test_a_gate_is_solid_shut_and_open_when_open() -> void:
	_stock()
	var gate := _build("gate", plot.x + 2, plot.y)
	ok(sim.structs.solid_at(plot.x + 2, plot.y))
	sim.structs.toggle_gate(sim, gate)
	ok(not sim.structs.solid_at(plot.x + 2, plot.y), "an open gate is a doorway")


# ------------------------------------------------------------------ raids --

func test_a_horde_breaks_on_the_wall_between_it_and_you() -> void:
	_stock()
	_build("woodWall", plot.x + 2, plot.y)
	var wall := sim.structs.at_tile(plot.x + 2, plot.y)
	var before: float = wall.hp
	var e := sim.enemies.spawn("brute", tile_centre(Vector2i(plot.x + 4, plot.y)), true)
	e.aggro = true
	for i in range(60 * 14):
		sim.tick(1.0 / 60.0)
		if wall.destroyed:
			break
	ok(wall.hp < before, "the brute hit the wall (%.0f of %.0f left)" % [wall.hp, before])
	ok(wall.destroyed, "and eventually came through it")


func test_a_walker_barely_scratches_what_a_brute_breaks() -> void:
	_stock()
	_build("woodWall", plot.x + 2, plot.y)
	var wall := sim.structs.at_tile(plot.x + 2, plot.y)
	var e := sim.enemies.spawn("walker", tile_centre(Vector2i(plot.x + 4, plot.y)), true)
	e.aggro = true
	for i in range(60 * 6):
		sim.tick(1.0 / 60.0)
	var walker_dealt: float = wall.max_hp - wall.hp
	gt(walker_dealt, 0.0, "a walker does chew on it: %.0f in six seconds" % walker_dealt)
	ok(not wall.destroyed, "but it is not what breaches a wall")


func test_a_raid_aims_at_the_base_not_at_you() -> void:
	_stock()
	var bench := _build("workbench", plot.x + 3, plot.y + 3)
	var c := sim.base_centre()
	ok(c.has_base, "a base exists")
	ok(c.pos.distance_to(bench.pos) < 32.0, "and the raid centre is it")
	# Walk a long way off; the raid still comes to the base.
	p.pos = tile_centre(Vector2i(plot.x + 40, plot.y + 40))
	var raid := Raid.start(sim)
	ok(raid.has_base)
	ok(raid.centre.distance_to(bench.pos) < 32.0, "the horde is going to the workbench")


func test_a_raider_walks_at_the_nearest_piece() -> void:
	_stock()
	_build("woodWall", plot.x + 2, plot.y)
	_build("workbench", plot.x + 6, plot.y)
	var from := tile_centre(Vector2i(plot.x - 4, plot.y))
	var target := sim.structs.raid_target(from)
	eq(target.type, "woodWall", "the perimeter, not the prize")


# ------------------------------------------------------------------ power --

func test_a_turret_needs_a_running_generator() -> void:
	_stock()
	var bench := _build("workbench", plot.x + 3, plot.y + 3)
	sim.structs.upgrade_bench(sim, bench, p)
	var gen := _build("generator", plot.x + 1, plot.y + 1)
	var turret := _build("turret", plot.x + 2, plot.y + 1)
	ok(not turret.is_empty(), "the turret went up")
	sim.tick(1.0 / 60.0)
	ok(not turret.powered, "with no fuel in the generator it is dead")
	ok(sim.structs.use_generator(sim, gen, p), "fuelled and started")
	sim.tick(1.0 / 60.0)
	ok(turret.powered, "now it has power")

	# And it shoots. Its ammunition comes out of the stash.
	sim.stash = Slots.new(Config.STASH_SLOTS)
	sim.stash.add("ammoP", 200)
	var e := sim.enemies.spawn("walker", turret.pos + Vector2(200, 0))
	for i in range(60 * 20):
		sim.tick(1.0 / 60.0)
		if e.dead:
			break
	ok(e.dead, "the turret killed a walker at 200px")
	ok(sim.stash.count("ammoP") < 200, "out of the stash: %d rounds left" % sim.stash.count("ammoP"))


func test_a_generator_burns_its_fuel_and_stops() -> void:
	_stock()
	var bench := _build("workbench", plot.x + 3, plot.y + 3)
	sim.structs.upgrade_bench(sim, bench, p)
	var gen := _build("generator", plot.x + 1, plot.y + 1)
	sim.structs.use_generator(sim, gen, p)
	near(gen.fuel, 100.0, 0.01, "a full tank")
	run(sim, 60.0)
	near(gen.fuel, 79.0, 1.5, "0.35 a second for a minute")
	ok(sim.threat.value > 0.0, "and it has been shouting the whole time")
	sim.structs.use_generator(sim, gen, p)
	ok(not Structures.generator_running(gen), "switching off always works")


func test_a_spike_trap_chews_what_stands_on_it() -> void:
	_stock()
	var trap := _build("spike", plot.x + 2, plot.y)
	ok(not sim.structs.solid_at(plot.x + 2, plot.y), "a trap is walked over, not into")
	var e := sim.enemies.spawn("walker", trap.pos)
	var hp := e.hp
	run(sim, 3.0)
	ok(e.hp < hp, "it took %.0f damage standing on the spikes" % (hp - e.hp))
	ok(trap.hp < trap.max_hp, "and the trap wore down doing it")


# ----------------------------------------------------------------- repair --

func test_repair_costs_a_share_of_the_build_price() -> void:
	_stock()
	var wall := _build("woodWall", plot.x + 2, plot.y)
	sim.structs.damage(sim, wall, wall.max_hp * 0.5)
	var cost := Structures.repair_cost(wall)
	eq(cost.wood, 4, "half the damage on a 16-wood wall at 45%")
	var before := p.count_res("wood")
	ok(sim.structs.repair(sim, wall, p))
	eq(wall.hp, wall.max_hp, "back to full")
	eq(p.count_res("wood"), before - 4)


func test_a_scratch_still_costs_one_of_the_main_material() -> void:
	_stock()
	var wall := _build("metalWall", plot.x + 2, plot.y) if false else _build("woodWall", plot.x + 2, plot.y)
	sim.structs.damage(sim, wall, 1.0)
	var cost := Structures.repair_cost(wall)
	eq(cost.wood, 1, "never free")


func test_repair_all_is_the_plan_it_printed() -> void:
	_stock(60)
	for i in range(4):
		var w := _build("woodWall", plot.x + 2, plot.y - 1 + i)
		sim.structs.damage(sim, w, w.max_hp * 0.5)
	# Four walls at 4 wood each, with only 10 wood in the pack: two get done
	# and the plan says so before the button is pressed.
	p.bag.clear_all()
	p.bag.add("wood", 10)
	var plan := sim.structs.plan_repair_all(sim, p)
	eq(plan.pieces.size(), 4)
	eq(plan.repairable, 2, "10 wood pays for two")
	eq(plan.skipped, 2)
	eq(sim.structs.repair_all(sim, p), 2, "and the sweep does exactly that")
	eq(p.count_res("wood"), 2)


func test_demolishing_a_full_chest_never_eats_what_is_in_it() -> void:
	_stock()
	var chest := _build("chest", plot.x + 2, plot.y)
	chest.store.add("mil", 30)
	chest.store.add("rifle", 1)
	var before := sim.pickups.size()
	ok(sim.structs.demolish(sim, chest, p))
	var on_ground := 0
	for it in sim.pickups:
		if it.id == "mil" or it.id == "rifle":
			on_ground += it.n
	eq(on_ground, 31, "everything inside is on the ground")
	gt(sim.pickups.size(), before)
	ok(sim.structs.at_tile(plot.x + 2, plot.y).is_empty(), "and the chest is gone")


func test_a_destroyed_chest_spills_too() -> void:
	_stock()
	var chest := _build("chest", plot.x + 2, plot.y)
	chest.store.add("scrap", 40)
	sim.structs.damage(sim, chest, 9999.0)
	ok(chest.destroyed)
	var on_ground := 0
	for it in sim.pickups:
		if it.id == "scrap":
			on_ground += it.n
	eq(on_ground, 40)


func test_only_the_last_stash_standing_spills() -> void:
	_stock()
	var a := _build("stash", plot.x + 2, plot.y)
	var b := _build("stash", plot.x + 3, plot.y)
	sim.stash.add("wood", 30)
	sim.structs.damage(sim, a, 9999.0)
	eq(sim.stash.count("wood"), 30, "the pile is still there while a door into it stands")
	sim.structs.damage(sim, b, 9999.0)
	eq(sim.stash.count("wood"), 0, "the last one spills it")


# ---------------------------------------------------------------- the base --

func test_a_bedroll_is_where_you_wake_up() -> void:
	_stock()
	var bed := _build("bedroll", plot.x + 2, plot.y)
	eq(p.spawn_tile, Vector2i(plot.x + 2, plot.y))
	p.pos = tile_centre(Vector2i(plot.x + 60, plot.y + 60))
	Damage.kill_player(sim, p)
	run(sim, Config.PLAYER.respawn_time + 0.2)
	ok(not p.dead)
	ok(p.pos.distance_to(bed.pos) < 100.0, "woke up %.0f px from the bedroll" % p.pos.distance_to(bed.pos))


func test_losing_the_bedroll_loses_the_respawn() -> void:
	_stock()
	var bed := _build("bedroll", plot.x + 2, plot.y)
	sim.structs.damage(sim, bed, 9999.0)
	eq(p.spawn_tile, Vector2i(-1, -1), "no bedroll, no respawn point")


func test_a_base_quietens_the_ground_around_it() -> void:
	_stock()
	var before := sim.quiet.density_mul(p.pos.x, p.pos.y, sim.structs)
	_build("workbench", plot.x + 2, plot.y)
	var after := sim.quiet.density_mul(p.pos.x, p.pos.y, sim.structs)
	ok(after < before, "the spawner wants %.2f of what it wanted (%.2f)" % [after, before])


func test_the_stash_pays_for_what_you_build_beside_it() -> void:
	_stock()
	_build("stash", plot.x + 2, plot.y)
	sim.stash.add("wood", 100)
	p.bag.clear_all()
	p.carry_cap = 100000.0
	ok(p.can_afford(sim, {"wood": 16}), "the stash counts toward the bill")
	var s := _build("woodWall", plot.x + 4, plot.y)
	ok(not s.is_empty())
	eq(sim.stash.count("wood"), 84, "and it was paid out of the stash")


func test_deposit_all_leaves_your_weapons_alone() -> void:
	_stock(20)
	var stash := _build("stash", plot.x + 2, plot.y)
	p.bag.add("rifle", 1)
	p.bag.add("bandage", 9)
	sim.structs.deposit_all(sim, p, stash.store)
	eq(p.bag.count("rifle"), 1, "the rifle stays on you")
	eq(p.bag.count("bandage"), 4, "and a working supply of bandages")
	eq(p.count_res("wood"), 0, "the haul went in")
	eq(sim.stash.count("wood"), 20)
	eq(sim.stash.count("bandage"), 5)
