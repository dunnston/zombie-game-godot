extends "res://tests/test_case.gd"
## Crafting: what the tables say, what the bench gates, what the hammer
## lifts, and where the output goes when there is nowhere to put it.

var sim: GameSim
var p: PlayerSim
var plot: Vector2i


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = clear_plot(8)
	p.pos = tile_centre(plot)
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0


func _stock(n := 200) -> void:
	for id in ["wood", "stone", "sticks", "fiber", "scrap", "cloth", "elec", "parts", "mil", "med"]:
		p.bag.add(id, n)


func _recipe(id: String) -> Dictionary:
	for r in Config.RECIPES:
		if r.id == id:
			return r
	return {}


# ------------------------------------------------------------------ tables --

func test_every_recipe_makes_something_that_exists() -> void:
	var ids := {}
	for r in Config.RECIPES:
		ok(not ids.has(r.id), "duplicate recipe id %s" % r.id)
		ids[r.id] = true
		ok(r.bench >= 0 and r.bench <= 2, r.id)
		ok(not r.cost.is_empty(), "%s costs nothing" % r.id)
		for c in r.cost:
			has(Config.RES, c, "%s: %s" % [r.id, c])
			gt(r.cost[c], 0, r.id)
		if r.has("tool"):
			has(Config.WEAPONS, r.tool, r.id)
		var give: Dictionary = r.give
		if give.has("weapon"):
			has(Config.WEAPONS, give.weapon, r.id)
		elif give.has("gear"):
			has(Config.GEAR, give.gear, r.id)
		elif give.has("item"):
			has(Config.CONSUMABLES, give.item, r.id)
			gt(give.n, 0, r.id)
		elif give.has("res"):
			for id in give.res:
				has(Config.RES, id, r.id)
		else:
			ok(false, "%s gives nothing" % r.id)


func test_the_hammer_never_reaches_a_gun() -> void:
	for r in Config.RECIPES:
		if r.get("hammer", false):
			ok(r.bench <= 1, "%s is hammer-liftable and above bench 1" % r.id)
			if r.give.has("weapon"):
				ok(Config.WEAPONS[r.give.weapon].kind != "gun", "%s is a gun" % r.id)


# ------------------------------------------------------------------ benches --

func test_by_hand_you_can_make_the_first_tools_and_nothing_else() -> void:
	var names := {}
	for r in Crafting.visible_recipes(p, 0):
		names[r.id] = true
	ok(names.has("axe"), "a hatchet")
	ok(names.has("bow"), "and a bow")
	ok(not names.has("pistol"), "but not a pistol")
	ok(not names.has("rifle"), "and certainly not a rifle")


func test_a_stone_hammer_lifts_the_simple_bench_work_and_no_more() -> void:
	var before := Crafting.visible_recipes(p, 0).size()
	p.bag.add("hammer", 1)
	var after: Array = Crafting.visible_recipes(p, 0)
	gt(after.size(), before, "the hammer showed some bench-1 work")
	for r in after:
		if r.bench > 0:
			ok(r.get("hammer", false), "%s appeared without being hammer work" % r.id)
	# And it really can be made, not merely shown.
	_stock()
	ok(Crafting.status(sim, p, _recipe("pipe"), 0).ok, "a pipe on a flat rock")
	ok(not Crafting.status(sim, p, _recipe("pistol"), 0).ok, "but never a pistol")


func test_a_workbench_you_stand_beside_is_what_counts() -> void:
	_stock()
	eq(Crafting.bench_tier_at(sim, p), 0, "in a field, by hand")
	sim.structs.place(sim, "workbench", plot.x + 2, plot.y, p)
	eq(Crafting.bench_tier_at(sim, p), 1, "beside it, a bench")
	p.pos = tile_centre(Vector2i(plot.x + 7, plot.y))
	eq(Crafting.bench_tier_at(sim, p), 0, "walk away and it is a field again")


func test_cordage_needs_a_blade() -> void:
	_stock()
	var r := _recipe("cordage")
	eq(Crafting.status(sim, p, r, 0).reason, "Needs a Stone Knife")
	p.bag.add("knife", 1)
	ok(Crafting.status(sim, p, r, 0).ok, "with a knife in the pack, yes")


# ---------------------------------------------------------------- crafting --

func test_crafting_a_hatchet_spends_the_materials_and_hands_it_over() -> void:
	_stock(10)
	var before_sticks := p.count_res("sticks")
	ok(Crafting.craft(sim, p, _recipe("axe"), 0))
	eq(p.count_res("sticks"), before_sticks - 3)
	eq(p.count_res("stone"), 7)
	eq(p.count_res("fiber"), 6)
	eq(p.count_carried("axe"), 1, "and it is to hand")
	gt(p.xp, 0)


func test_you_cannot_craft_what_you_cannot_pay_for() -> void:
	var r := _recipe("axe")
	eq(Crafting.status(sim, p, r, 0).reason, "Missing materials")
	ok(not Crafting.craft(sim, p, r, 0))
	eq(p.count_carried("axe"), 0)


func test_a_gun_needs_the_bench_it_says_it_needs() -> void:
	_stock()
	eq(Crafting.status(sim, p, _recipe("pistol"), 0).reason, "Needs a Workbench")
	eq(Crafting.status(sim, p, _recipe("rifle"), 1).reason, "Needs Workbench II")
	ok(Crafting.status(sim, p, _recipe("rifle"), 2).ok)


func test_the_stash_pays_for_a_craft_at_the_bench() -> void:
	_stock(0)
	sim.stash = Slots.new(Config.STASH_SLOTS)
	sim.stash.add("sticks", 20)
	sim.stash.add("stone", 20)
	sim.stash.add("fiber", 20)
	ok(Crafting.craft(sim, p, _recipe("axe"), 0), "paid out of the stash")
	eq(sim.stash.count("sticks"), 17)
	eq(p.count_carried("axe"), 1)


func test_an_output_with_nowhere_to_go_lands_at_your_feet() -> void:
	_stock()
	# Fill every slot with something that cannot merge with arrows.
	for i in range(p.bag.size()):
		if p.bag.at(i).is_empty():
			p.bag.slots[i] = {"id": "stone", "n": 50}
	p.hotbar.clear_all()
	for i in range(p.hotbar.size()):
		p.hotbar.slots[i] = {"id": "stone", "n": 50}
	p.carry_cap = p.carried_weight()          # and no weight left either
	var before := sim.pickups.size()
	# The cost is spent from what is already in the pack, so the craft goes
	# ahead — and the output must not evaporate.
	Crafting.craft(sim, p, _recipe("arrow"), 0)
	gt(sim.pickups.size(), before, "the arrows are on the ground")


func test_crafting_raises_threat_and_counts() -> void:
	_stock()
	var before := sim.threat.value
	var bandages := p.count_carried("bandage")
	Crafting.craft(sim, p, _recipe("bandage"), 0)
	near(sim.threat.value, before + Config.THREAT.per_craft, 0.001)
	eq(sim.stats.crafted, 1)
	eq(p.count_carried("bandage"), bandages + 2, "the two you started with, plus two")
