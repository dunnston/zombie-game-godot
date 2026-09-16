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


# ------------------------------------------------------------------- time --

## Ticks the player as the game would, `seconds` at 60Hz.
func _run(seconds: float) -> void:
	for i in range(int(round(seconds / (1.0 / 60.0)))):
		p.tick(sim, 1.0 / 60.0)


func test_a_craft_takes_time_and_nothing_is_spent_until_it_is_done() -> void:
	_stock(10)
	ok(Crafting.start(sim, p, _recipe("axe"), 0))
	eq(String(p.crafting.id), "axe")
	_run(Config.PLAYER.craft_time * 0.5)
	eq(p.count_carried("axe"), 0, "not yet")
	eq(p.count_res("sticks"), 10, "and not paid for yet")
	gt(float(p.crafting.t), 0.0, "the bar is filling")
	_run(Config.PLAYER.craft_time * 0.5 + 0.05)
	eq(p.count_carried("axe"), 1, "made")
	eq(p.count_res("sticks"), 7, "and paid for")
	ok(p.crafting.is_empty(), "and the bar is gone")


func test_one_thing_at_a_time() -> void:
	_stock()
	ok(Crafting.start(sim, p, _recipe("axe"), 0))
	ok(not Crafting.start(sim, p, _recipe("axe"), 0), "a second press does not start a second")
	_run(Config.PLAYER.craft_time + 0.05)
	eq(p.count_carried("axe"), 1, "and does not make two")


func test_a_batch_makes_each_in_turn() -> void:
	_stock()
	ok(Crafting.start(sim, p, _recipe("bandage"), 0, 3))
	var before := p.count_carried("bandage")
	_run(Config.PLAYER.craft_time + 0.05)
	eq(p.count_carried("bandage"), before + 2, "one bill's worth")
	eq(int(p.crafting.left), 2)
	_run(Config.PLAYER.craft_time * 2.0 + 0.05)
	eq(p.count_carried("bandage"), before + 6, "all three")
	ok(p.crafting.is_empty())


func test_a_batch_stops_when_the_materials_run_out() -> void:
	p.bag.add("sticks", 6)
	p.bag.add("stone", 7)
	p.bag.add("fiber", 8)
	ok(Crafting.start(sim, p, _recipe("axe"), 0, 5))
	_run(Config.PLAYER.craft_time * 5.0)
	eq(p.count_carried("axe"), 2, "two bills' worth, and no more")
	ok(p.crafting.is_empty(), "stopped, not stuck")


func test_a_hit_stops_it_and_costs_nothing() -> void:
	_stock(10)
	ok(Crafting.start(sim, p, _recipe("axe"), 0))
	_run(Config.PLAYER.craft_time * 0.5)
	Damage.damage_player(sim, p, 5.0, p.pos + Vector2(30, 0))
	ok(p.crafting.is_empty(), "interrupted")
	var said := false
	for ev in sim.events:
		if ev.t == "craft_stopped" and int(ev.by) == p.seat:
			said = true
	ok(said, "and the craft screen is told why")
	_run(Config.PLAYER.craft_time)
	eq(p.count_carried("axe"), 0)
	eq(p.count_res("sticks"), 10, "nothing spent")


func test_cancel_costs_nothing() -> void:
	_stock(10)
	ok(Crafting.start(sim, p, _recipe("axe"), 0))
	_run(0.5)
	ok(Crafting.cancel(sim, p))
	_run(Config.PLAYER.craft_time)
	eq(p.count_carried("axe"), 0)
	eq(p.count_res("sticks"), 10)


func test_walking_away_from_the_bench_stops_bench_work() -> void:
	_stock()
	p.bag.add("knife", 1)
	sim.structs.place(sim, "workbench", plot.x + 2, plot.y, p)
	eq(Crafting.bench_tier_at(sim, p), 1, "beside the bench")
	var fiber := p.count_res("fiber")
	ok(Crafting.start(sim, p, _recipe("cordage"), 1))
	_run(0.3)
	p.pos = tile_centre(Vector2i(plot.x + 7, plot.y))
	_run(0.1)
	ok(p.crafting.is_empty(), "walked off, stopped")
	_run(Config.PLAYER.craft_time)
	eq(p.count_res("fiber"), fiber, "and nothing was spent")


func test_by_hand_work_carries_on_while_you_walk() -> void:
	_stock(10)
	ok(Crafting.start(sim, p, _recipe("axe"), 0))
	p.intent.mx = 1.0
	_run(Config.PLAYER.craft_time + 0.05)
	eq(p.count_carried("axe"), 1, "made on the move")


func test_craft_time_is_one_number_and_a_stat_shortens_it() -> void:
	near(Crafting.duration(p), Config.PLAYER.craft_time, 0.001)
	p.craft_time_mul = 0.5
	near(Crafting.duration(p), Config.PLAYER.craft_time * 0.5, 0.001)


# ------------------------------------------------ the Codex review, PR #5 --

func test_you_cannot_craft_a_rifle_you_cannot_lift() -> void:
	# Materials in the stash, so affording it is not the question — and a
	# free slot, so slot space is not the question either.
	sim.stash = Slots.new(Config.STASH_SLOTS)
	for id in ["scrap", "parts", "mil"]:
		sim.stash.add(id, 200)
	p.bag.clear_all()
	p.hotbar.clear_all()
	p.carry_cap = 200.0                                  # ceiling 300
	p.bag.add_capped("stone", 400, p.pack_allowance())
	ok(p.bag.first_empty() >= 0, "there is a slot free")
	near(p.carried_weight(), 300.0, 0.01, "loaded to the ceiling")
	var r := _recipe("rifle")
	eq(Crafting.status(sim, p, r, 2).reason, "Too heavy to carry")
	ok(not Crafting.craft(sim, p, r, 2))
	eq(p.count_carried("rifle"), 0)
	eq(sim.stash.count("scrap"), 200, "and it cost nothing")
	# Put something down and it goes through.
	p.bag.take("stone", 20)
	ok(Crafting.craft(sim, p, r, 2))
	eq(p.count_carried("rifle"), 1)
	ok(p.carried_weight() <= p.carry_limit(), "carrying %.1f" % p.carried_weight())


# ------------------------------------------------------------- the Recycler --

func _recycler() -> Dictionary:
	# A bench to stand at. Placed through the sim so the tile and the reach are
	# the real ones.
	p.bag.add("scrap", 200)
	p.bag.add("wood", 200)
	p.bag.add("parts", 20)
	sim.structs.bench_tier = 2
	var t := Vector2i(floori(p.pos.x / Config.TILE) + 1, floori(p.pos.y / Config.TILE))
	clear_ground(sim, t.x, t.y)
	return sim.structs.place(sim, "recycler", t.x, t.y, p)


func test_a_recycler_gives_back_what_notion_says_it_breaks_into() -> void:
	var bench := _recycler()
	ok(not bench.is_empty(), "the Recycler went down")
	ok(not Recycle.bench_near(sim, p).is_empty(), "and you are standing at it")
	p.bag.clear_all()
	p.bag.add("machete", 1)
	var before := p.count_res("scrap")
	var gave := Recycle.recycle(sim, p, "bag", 0)
	eq(gave, {"scrap": 12}, "a Machete is twelve scrap on the Items table")
	eq(p.count_res("scrap"), before + 12, "and that is what landed in the pack")
	eq(p.bag.count("machete"), 0, "the machete is gone")


func test_a_worn_tool_gives_back_what_is_left_of_it() -> void:
	_recycler()
	p.bag.clear_all()
	p.bag.add("machete", 1)
	# Half worn: half the steel, and never nothing.
	p.bag.set_wear_at(0, maxi(1, Wear.max_at(p.bag, 0) / 2))
	var gave := Recycle.recycle(sim, p, "bag", 0)
	eq(gave, {"scrap": 6}, "half a Machete is half the scrap, got %s" % str(gave))
	var at := p.bag.first_empty()
	p.bag.add("knife", 1)
	p.bag.set_wear_at(at, 0)
	var broken := Recycle.recycle(sim, p, "bag", at)
	eq(broken, {"stone": 1}, "a broken thing is still worth its biggest material once")


func test_the_recycler_refuses_what_it_cannot_break_and_where_it_is_not() -> void:
	p.bag.clear_all()
	p.bag.add("machete", 1)
	eq(Recycle.recycle(sim, p, "bag", 0), {}, "recycled with no bench in sight")
	eq(p.bag.count("machete"), 1, "and it was taken anyway")
	_recycler()
	p.bag.clear_all()
	p.bag.add("wood", 20)
	eq(Recycle.recycle(sim, p, "bag", 0), {}, "wood is already a material")
	eq(p.bag.count("wood"), 20)


func test_every_recycle_row_names_something_in_the_game() -> void:
	for id: String in Config.RECYCLE:
		ok(Items.has(id), "%s is in the recycle table and nowhere else" % id)
		var gives: Dictionary = Config.RECYCLE[id].gives
		ok(not gives.is_empty(), "%s breaks down into nothing" % id)
		for res_id: String in gives:
			ok(Config.RES.has(res_id), "%s gives '%s', which is not a material" % [id, res_id])
			gt(int(gives[res_id]), 0, "%s gives %s of %s" % [id, gives[res_id], res_id])
