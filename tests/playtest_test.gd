extends "res://tests/test_case.gd"
## The owner's first playtest, 2026-09-10: nine notes, each held to what the
## game now decides. Every assertion is on the decision — the refusal, the
## event, the tier — not on the function that fed it.

var sim: GameSim
var p: PlayerSim
var plot: Vector2i
var _planted: Array = []


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = clear_plot(6)
	p.pos = tile_centre(plot)
	p.intent.aim = p.pos + Vector2.RIGHT
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0
	for id in ["wood", "stone", "sticks", "scrap", "cloth", "elec", "parts", "mil", "med"]:
		p.bag.add(id, 400)


## The world is shared by every test, so anything planted here is taken back
## out — including its line in `chopped`, which removing it wrote.
func after_each() -> void:
	var W := Config.WORLD_TILES
	for prop in _planted:
		var ti: int = int(prop.ty) * W + int(prop.tx)
		sim.world.props.erase(prop)
		sim.world.prop_grid.erase(ti)
		sim.world.chopped.erase(ti)
	_planted.clear()


## A loose stone on a tile, shaped the way the generator shapes one.
func _plant_stone(t: Vector2i) -> Dictionary:
	var W := Config.WORLD_TILES
	var prop := {
		"kind": "litter", "res": "stone", "si": 0, "rot": 0.0, "tx": t.x, "ty": t.y,
		"x": (t.x + 0.5) * Config.TILE, "y": (t.y + 0.5) * Config.TILE,
		"harvest": "litter_stone", "hand": true, "solid": false, "flash": 0.0,
		"hp": 1.0, "max_hp": 1.0,
	}
	sim.world.props.append(prop)
	sim.world.prop_grid[t.y * W + t.x] = prop
	_planted.append(prop)
	return prop


## A tile beside the player with nothing on it, so a placement test fails on
## the rule it is about and not on litter the generator happened to drop.
func _free_tile() -> Vector2i:
	for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(2, 2)]:
		var t: Vector2i = plot + d
		if sim.world.prop_at_tile(t.x, t.y).is_empty():
			return t
	return plot + Vector2i(2, 0)


## A litter-free tile touching the player's, for a bench they will use.
func _free_beside() -> Vector2i:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t: Vector2i = plot + d
		if sim.world.prop_at_tile(t.x, t.y).is_empty():
			return t
	return plot + Vector2i(1, 0)


# ------------------------------------------------------ 2. build on litter --

func test_you_cannot_build_on_a_loose_stone() -> void:
	var t := _free_tile()
	_plant_stone(t)
	var check := sim.structs.can_place(sim, "woodWall", t.x, t.y, p)
	ok(not check.ok, "a wall on a loose stone")
	eq(check.reason, "Pick up the stone first")
	ok(sim.structs.place(sim, "woodWall", t.x, t.y, p).is_empty(), "and place refuses it too")


func test_picking_it_up_clears_the_way() -> void:
	var t := _free_tile()
	var prop := _plant_stone(t)
	ok(Interact.gather_prop(sim, p, prop))
	ok(sim.structs.can_place(sim, "woodWall", t.x, t.y, p).ok, "the ground is clear now")


func test_a_piece_on_litter_from_an_old_save_clears_it_for_good() -> void:
	# `make` is the load path. A save written before the refusal existed can
	# hold a wall on a stone; loading it must not bring the stone back.
	var t := _free_tile()
	var prop := _plant_stone(t)
	sim.structs.make(sim, "woodWall", t.x, t.y)
	ok(sim.world.prop_at_tile(t.x, t.y).is_empty(), "nothing is left on the tile")
	ok(prop.get("gone", false), "the renderer is told it is gone")
	has(sim.world.chopped_keys(), "%d,%d" % [t.x, t.y], "and the save remembers")


# ---------------------------------------------------------- 5. the bench --

func _press_interact() -> void:
	sim.events.clear()
	p.intent.interact = true
	Interact.tick(sim, p, 1.0 / 60.0)
	p.intent.interact = false


func test_e_at_a_workbench_opens_it_and_spends_nothing() -> void:
	var t := _free_beside()
	var bench := sim.structs.place(sim, "workbench", t.x, t.y, p)
	ok(not bench.is_empty(), "the bench went up")
	eq(String(Interact.best_target(sim, p).get("label", "")), "Use Workbench", "the prompt")
	var scrap := p.count_res("scrap")
	_press_interact()
	var opened := events_of(sim, "open_bench")
	eq(opened.size(), 1, "E opened the bench")
	if opened.size() == 1:
		eq(Vector2i(int(opened[0].tx), int(opened[0].ty)), t, "the bench you are at")
		eq(int(opened[0].seat), p.seat, "for you and nobody else")
	eq(int(bench.tier), 1, "and did not upgrade it")
	eq(p.count_res("scrap"), scrap, "or spend anything")


func test_the_upgrade_button_upgrades_the_bench_you_are_at() -> void:
	var t := _free_beside()
	var bench := sim.structs.place(sim, "workbench", t.x, t.y, p)
	# Through `execute`, the path a guest's press takes on the host.
	ok(Actions.execute(sim, p, "upgrade_bench", {"tx": t.x, "ty": t.y}))
	eq(int(bench.tier), 2)
	eq(sim.structs.bench_tier, 2)
	eq(String(Interact.best_target(sim, p).get("label", "")), "Use Workbench II")


func test_nobody_upgrades_a_bench_from_across_town() -> void:
	var t := _free_beside()
	var bench := sim.structs.place(sim, "workbench", t.x, t.y, p)
	p.pos = tile_centre(plot + Vector2i(0, 6))
	ok(not Actions.execute(sim, p, "upgrade_bench", {"tx": t.x, "ty": t.y}), "out of reach")
	eq(int(bench.tier), 1)
	p.pos = tile_centre(plot)
	ok(not Actions.execute(sim, p, "upgrade_bench", {"tx": plot.x + 3, "ty": plot.y}), "no bench on that tile")


func test_e_at_a_chemistry_station_opens_it_too() -> void:
	# Its recipes are only on the bench screen now, so E has to reach it.
	sim.structs.bench_tier = 2
	var t := _free_beside()
	ok(not sim.structs.place(sim, "chemStation", t.x, t.y, p).is_empty())
	eq(String(Interact.best_target(sim, p).get("label", "")), "Use Chemistry Station")
	_press_interact()
	eq(events_of(sim, "open_bench").size(), 1)


func test_a_bench_screen_lists_the_bench_you_opened_and_no_other() -> void:
	# Codex, PR #25: with a workbench and a Chemistry Station both in reach,
	# each screen listed the other's recipes, because the list was built from
	# everything nearby rather than from the structure that was opened.
	sim.structs.bench_tier = 2
	var wt := _free_beside()
	var bench := sim.structs.place(sim, "workbench", wt.x, wt.y, p)
	var ct := Vector2i(-1, -1)
	for d in [Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
		var t: Vector2i = plot + d
		if t != wt and sim.world.prop_at_tile(t.x, t.y).is_empty() \
				and not sim.structs.place(sim, "chemStation", t.x, t.y, p).is_empty():
			ct = t
			break
	ok(not bench.is_empty() and ct.x >= 0, "both went up")
	var screen := InventoryScreen.new(sim)
	screen.player = p

	screen.open_bench(ct)
	var at_chem: Array = screen.recipes()
	gt(at_chem.size(), 0, "the station lists its work")
	for r in at_chem:
		eq(String(r.get("station", "")), "chem", "%s at the Chemistry Station" % r.id)
	eq(screen.bench(), 0, "a station is not a rung of the ladder")

	screen.open_bench(wt)
	var ids: Array = []
	for r in screen.recipes():
		ok(String(r.get("station", "")).is_empty(), "%s at the workbench" % r.id)
		ids.append(String(r.id))
	has(ids, "pistol", "the workbench lists its own tier")
	ok(not ids.has("rifle"), "and only its own: this one is not upgraded")
	eq(screen.bench(), 1)
	screen.free()


# ----------------------------------------------------- 7. click food to eat --

func test_the_click_menu_says_what_using_it_is() -> void:
	eq(InventoryScreen.use_verb("hotMeal"), "EAT", "food is eaten")
	eq(InventoryScreen.use_verb("water"), "DRINK", "water is drunk")
	eq(InventoryScreen.use_verb("brainRaw"), "EAT", "and so, grimly, is brain matter")
	eq(InventoryScreen.use_verb("bandage"), "USE", "a bandage is used")
	eq(InventoryScreen.use_verb("lockpick"), "", "a lockpick is not for using here")
	eq(InventoryScreen.use_verb("axe"), "", "nor is a hatchet")
	eq(InventoryScreen.use_verb("wood"), "", "nor wood")


# --------------------------------------------------- 3. night, but darker --

func test_deep_night_is_near_black() -> void:
	gt(float(DayNight.darkness_at(0.82).alpha), 0.95, "the small hours")


func test_a_darker_night_changed_nothing_but_what_you_see() -> void:
	# `k` — the dark as the spawner, the senses, Threat and Mutation read it —
	# at every key of the curve, as it was before the curve was deepened.
	var was := {0.0: 0.775, 0.10: 0.275, 0.16: 0.0, 0.66: 0.375, 0.74: 0.775, 0.82: 1.0, 0.96: 0.975}
	for t in was:
		var k := clampf(float(DayNight.darkness_at(float(t)).alpha) / Config.DARKNESS_FULL, 0.0, 1.0)
		near(k, float(was[t]), 0.002, "k at %.2f" % float(t))
	# And the hint's threshold moved with it.
	near(Config.DARK_ENOUGH / Config.DARKNESS_FULL, 0.35 / 0.8, 0.002)


# ------------------------------------------------------ 1. mutation, slower --

func test_mutation_left_alone_takes_about_an_hour() -> void:
	var minutes: float = float(Config.MUTATION.max) / Mutation.rate_per_sec() / 60.0
	ok(minutes >= 60.0 and minutes <= 75.0, "%.0f minutes to turn, untouched" % minutes)
	near(float(Config.MUTATION.bite_chance) * float(Config.MUTATION.per_bite),
		0.14 * 12.0 / 2.8, 0.01, "a bite is worth well under half what it was")
