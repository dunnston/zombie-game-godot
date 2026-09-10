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
			# A cost is anything that stacks. It used to be "anything in RES",
			# and then processing brain matter arrived: the Serum is paid for
			# in a consumable, which `can_afford` and `spend` handle already
			# because both of them only ever ask a `Slots` for a count.
			ok(Items.has(c) and Items.stack_limit(c) > 1,
				"%s: %s is not something you can pay with" % [r.id, c])
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


# ------------------------------------------------------------------ benches --

## The owner's list, 2026-09-10: the C menu is what you need before you have
## a base, and everything else is made at the bench.
const BY_HAND := ["axe", "bandage", "hammer", "knife", "pick", "torch"]


func test_by_hand_is_exactly_the_six_basics() -> void:
	var names: Array = []
	for r in Crafting.visible_recipes(p, 0):
		names.append(String(r.id))
	names.sort()
	eq(names, BY_HAND, "the C menu")
	# And the table says so, not just the list: nothing else is bench 0
	# unless a station gates it.
	for r in Config.RECIPES:
		if int(r.bench) == 0 and String(r.get("station", "")).is_empty():
			ok(BY_HAND.has(String(r.id)), "%s is by hand" % r.id)


func test_the_bow_and_the_first_clothes_are_bench_work() -> void:
	_stock()
	for id in ["scythe", "cordage", "bow", "arrow", "compost", "workGloves", "denimPants"]:
		eq(Crafting.status(sim, p, _recipe(id), 0).reason, "Needs a Workbench", id)


func test_a_stone_hammer_is_a_weapon_not_a_workbench() -> void:
	_stock()
	p.bag.add("hammer", 1)
	eq(Crafting.visible_recipes(p, 0).size(), BY_HAND.size(), "the hammer shows nothing extra")
	eq(Crafting.status(sim, p, _recipe("pipe"), 0).reason, "Needs a Workbench", "a pipe needs the bench")
	ok(Crafting.status(sim, p, _recipe("pipe"), 1).ok, "and at the bench it is fine")


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
	eq(Crafting.status(sim, p, r, 1).reason, "Needs a Stone Knife")
	p.bag.add("knife", 1)
	ok(Crafting.status(sim, p, r, 1).ok, "with a knife in the pack, yes")


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
	Crafting.craft(sim, p, _recipe("arrow"), 1)
	gt(sim.pickups.size(), before, "the arrows are on the ground")


func test_crafting_raises_threat_and_counts() -> void:
	_stock()
	var before := sim.threat.value
	var bandages := p.count_carried("bandage")
	Crafting.craft(sim, p, _recipe("bandage"), 0)
	near(sim.threat.value, before + Config.THREAT.per_craft, 0.001)
	eq(sim.stats.crafted, 1)
	eq(p.count_carried("bandage"), bandages + 2, "the two you started with, plus two")


# ------------------------------------------------ the Codex review, PR #5 --

func test_you_cannot_craft_a_rifle_you_cannot_lift() -> void:
	# Materials in the stash, so affording it is not the question — and a
	# free slot, so slot space is not the question either.
	sim.stash = Slots.new(Config.STASH_SLOTS)
	for id in ["scrap", "parts", "mil"]:
		sim.stash.add(id, 200)
	p.bag.clear_all()
	p.hotbar.clear_all()
	p.carry_cap = 200.0
	p.bag.add_capped("stone", 400, p.pack_allowance())
	ok(p.bag.first_empty() >= 0, "there is a slot free")
	near(p.carried_weight(), 199.5, 0.01)
	var r := _recipe("rifle")
	eq(Crafting.status(sim, p, r, 2).reason, "Too heavy to carry")
	ok(not Crafting.craft(sim, p, r, 2))
	eq(p.count_carried("rifle"), 0)
	eq(sim.stash.count("scrap"), 200, "and it cost nothing")
	# Put something down and it goes through.
	p.bag.take("stone", 20)
	ok(Crafting.craft(sim, p, r, 2))
	eq(p.count_carried("rifle"), 1)
	ok(not p.overloaded())
