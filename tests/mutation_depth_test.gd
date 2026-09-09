extends "res://tests/test_case.gd"
## Phase 6b: the chemistry, the food table and the Lurch.
##
## Split from `mutation_test.gd` rather than piled onto it — that file is
## about the meter itself, and this one is about the three systems built on
## top of it. Both are about the same rule: everything reaches the player
## through `recompute_stats`, and everything that writes the meter goes
## through `Mutation`.

var sim: GameSim
var p: PlayerSim


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]


func _stats(q: PlayerSim) -> Dictionary:
	var out := {}
	for key in Config.STAT_BASE:
		out[key] = q.get(key)
	return out


# ----------------------------------------------------------- the chemistry --

func test_the_deep_doses_need_the_station_and_nothing_else_does() -> void:
	var stationed := 0
	for r in Config.RECIPES:
		var st := String(r.get("station", ""))
		if st.is_empty():
			continue
		stationed += 1
		ok(Crafting.STATIONS.has(st), "%s wants a '%s', which no structure offers" % [r.id, st])
		# A station recipe must not also be reachable by upgrading a bench:
		# the two gates are independent, and a `bench` above 0 here would read
		# as "keep upgrading" to anybody who found it.
		eq(int(r.bench), 0, "%s is gated on a bench as well as a station" % r.id)
	gt(stationed, 1, "a station with one recipe is a decoration")


func test_a_refined_dose_is_out_of_reach_until_you_build_the_bench() -> void:
	var r := {}
	for rec in Config.RECIPES:
		if String(rec.id) == "suppressant":
			r = rec
	ok(not r.is_empty(), "there is no Refined Suppressant recipe")

	# Everything in the pack, standing at the best workbench there is: still no.
	p.bag = Slots.new(240)
	p.carry_cap = 100000.0
	for id in r.cost:
		p.bag.add(id, int(r.cost[id]) * 4)
	var st := Crafting.status(sim, p, r, 2)
	ok(not st.ok, "Workbench II handed out the chemistry")
	ok(st.reason.contains("Chemistry"), st.reason)
	ok(not Crafting.visible_recipes(p, 2).has(r), "it is listed at a bench it cannot be made at")

	# And with the station beside you, yes.
	var tile := clear_plot(3)
	for id in ["scrap", "elec", "parts", "med", "wood"]:
		p.bag.add(id, 400)
	sim.structs.bench_tier = 2
	p.pos = tile_centre(tile) + Vector2(0, Config.TILE * 2)
	sim.structs.place(sim, "chemStation", tile.x, tile.y, p)
	ok(not sim.structs.at_tile(tile.x, tile.y).is_empty(), "the station would not go up")
	ok(Crafting.stations_at(sim, p).has("chem"), "standing at the station, the station is not there")
	ok(Crafting.status(sim, p, r, 0).ok, Crafting.status(sim, p, r, 0).reason)
	ok(Crafting.visible_recipes(p, 0, Crafting.stations_at(sim, p)).has(r), "at the station it is still not listed")

	# Walk away and it is out of reach again. The check asks the world, not
	# the screen, which is what makes it hold for a guest's command too.
	p.pos += Vector2(Config.BUILD.bench_range * 3.0, 0)
	ok(not Crafting.status(sim, p, r, 0).ok, "the station followed the player home")


func test_the_doses_climb_and_only_the_last_one_gambles() -> void:
	var seen: Array[float] = []
	for id in Config.CONSUMABLES:
		if Mutation.is_suppressant(id):
			seen.append(float(Config.CONSUMABLES[id].mut))
	seen.sort()
	# Five: two you can find on a body — raw and mutated tissue — and three
	# a base makes out of them.
	eq(seen.size(), 5, "the chain is raw, mutated, stabilized, refined, experimental")
	near(seen[0], 10.0, 0.001)
	near(seen[seen.size() - 1], 75.0, 0.001)
	var risky := 0
	for id in Config.CONSUMABLES:
		if Config.CONSUMABLES[id].has("risk"):
			risky += 1
			ok(Config.EFFECTS.has(Config.CONSUMABLES[id].risk.effect), id)
			ok(float(Config.CONSUMABLES[id].mut) >= 75.0, "%s gambles for a small dose" % id)
	eq(risky, 1)


func test_experimental_always_pays_and_sometimes_charges() -> void:
	var surges := 0
	var fevers := 0
	for i in range(200):
		p.effects.clear()
		p.mutation = 90.0
		p.mut_band = Mutation.band_index(p.mutation)
		Mutation.take_dose(sim, p, "experimental")
		if p.effects.has("surge"):
			surges += 1
		if p.effects.has("fever"):
			fevers += 1
	eq(surges, 200, "the Surge is the reason to take one, and it did not always land")
	gt(fevers, 20, "200 doses and it never bit back")
	ok(fevers < 120, "%d of 200 doses gave a Fever, which is not a one-in-four risk" % fevers)


func test_a_fever_turns_you_faster() -> void:
	# The risk sits on the same axis as the reward. That is what stops the
	# Experimental dose being a free win.
	var clean := Mutation.rate_multiplier(sim, p)
	Mutation.give_effect(sim, p, "fever")
	gt(Mutation.rate_multiplier(sim, p), clean, "a Fever does not turn you faster")


func test_a_surge_wears_off_and_leaves_nothing_behind() -> void:
	var clean := _stats(p)
	Mutation.give_effect(sim, p, "surge")
	gt(p.melee_mul, clean.melee_mul)
	p.effects["surge"] = 0.05
	Mutation.tick_effects(sim, p, 0.1)
	eq(_stats(p), clean, "the Surge wore off and left a modifier behind")


# --------------------------------------------------------- food and drink --

func test_food_is_a_buff_and_never_a_requirement() -> void:
	var foods := 0
	for id in Config.CONSUMABLES:
		var c: Dictionary = Config.CONSUMABLES[id]
		if not c.get("food", false):
			continue
		foods += 1
		ok(Config.EFFECTS.has(String(c.get("effect", ""))), "%s feeds you nothing" % id)
		ok(Config.EFFECTS[c.effect].get("good", false), "%s is food and its effect is a debuff" % id)
		ok(float(c.get("mut", 0.0)) <= 0.0, "%s is food that suppresses Mutation" % id)
	gt(foods, 6, "a full table is more than a handful")
	# The pillar, asserted. There is no hunger meter under any of this and
	# there never will be: a field named for one would be the first sign.
	for field in ["hunger", "thirst", "fatigue"]:
		eq(p.get(field), null, "a %s field appeared on the player" % field)


func test_every_food_is_findable() -> void:
	# A buff nobody can find is a table entry. Every one of them has to be in
	# a loot table somewhere or craftable from something that is.
	var sources := {}
	for table in Config.LOOT:
		for entry in Config.LOOT[table]:
			sources[String(entry.id)] = true
	for r in Config.RECIPES:
		if r.give.has("item"):
			sources["item:" + String(r.give.item)] = true
	for id in Config.CONSUMABLES:
		if Config.CONSUMABLES[id].get("food", false):
			ok(sources.has("item:" + id), "%s exists and nothing in the world has one" % id)


func test_the_quick_key_eats_the_commonest_thing_that_would_help() -> void:
	p.bag.add("candyBar", 2)           # rank 0
	p.bag.add("mre", 2)                # rank 5, and worth keeping
	p.intent.eat = true
	sim.tick(1.0 / 60.0)
	eq(String(p.using.id), "candyBar", "it went for the Field Ration first")
	run(sim, float(Config.CONSUMABLES.candyBar.time) + 0.2)
	ok(p.effects.has("wired"))
	eq(p.count_carried("candyBar"), 1)
	eq(p.count_carried("mre"), 2, "it spent the ration as well")

	# The buff is already running, so the next tap reaches past it rather than
	# spending a second one on top.
	p.intent.eat = true
	sim.tick(1.0 / 60.0)
	eq(String(p.using.id), "mre", "it ate a second candy bar on top of the first")


func test_eating_nothing_is_a_notice_and_not_a_crash() -> void:
	p.bag.clear_all()
	p.hotbar.clear_all()
	ok(not p.use_food(sim))
	ok(not p.use_suppressant(sim))
	ok(not p.start_use(sim, "cannedFood"), "it ate something it was not carrying")


func test_a_meal_can_heal_and_buff_at_once() -> void:
	p.hp = p.max_hp - 40.0
	var hurt := p.hp
	p.bag.add("hotMeal", 1)
	ok(p.start_use(sim, "hotMeal"))
	run(sim, float(Config.CONSUMABLES.hotMeal.time) + 0.2)
	gt(p.hp, hurt, "the meal did not heal")
	ok(p.effects.has("steady"), "the meal did not steady you")


func test_the_pack_uses_what_it_is_holding() -> void:
	# Right-click in the pack goes through `Actions`, so a guest's click is
	# the same command the host would have run.
	p.bag.clear_all()
	p.bag.add("water", 1)
	ok(Actions.use_slot(sim, p, "bag", 0))
	run(sim, float(Config.CONSUMABLES.water.time) + 0.2)
	ok(p.effects.has("hydrated"))
	eq(p.count_carried("water"), 0)


func test_hydration_slows_the_change() -> void:
	var dry := Mutation.rate_multiplier(sim, p)
	Mutation.give_effect(sim, p, "hydrated")
	ok(Mutation.rate_multiplier(sim, p) < dry, "water does nothing for the meter")


# ---------------------------------------------------------------- the lurch --

func test_a_human_never_lurches() -> void:
	for i in range(600):
		Mutation.tick_lurch(sim, p, 0.5)
	near(p.lurch_t, 0.0, 0.001, "a HUMAN player lost control of their legs")


func test_feral_eventually_loses_the_legs_but_not_for_long() -> void:
	Mutation.add(sim, p, 80.0)
	var fired := 0
	for i in range(4000):
		Mutation.tick_lurch(sim, p, 0.1)
		if p.lurch_t > 0.0:
			fired += 1
	gt(fired, 0, "four hundred seconds at FERAL and never a Lurch")
	# ...and it is a moment, not a state.
	ok(float(fired) / 4000.0 < 0.1, "the Lurch was running %d percent of the time" % roundi(fired / 40.0))


func test_coming_back_down_gives_the_legs_back_and_disarms_it() -> void:
	Mutation.add(sim, p, 80.0)
	Mutation.tick_lurch(sim, p, 0.1)
	gt(p.lurch_cd, 0.0, "the clock never armed")
	Mutation.suppress(sim, p, 80.0)
	Mutation.tick_lurch(sim, p, 0.1)
	near(p.lurch_cd, 0.0, 0.001, "the clock kept running for a human")
	near(p.lurch_t, 0.0, 0.001)


func test_a_lurch_takes_the_intent_off_you() -> void:
	Mutation.add(sim, p, 80.0)
	sim.enemies.spawn("walker", p.pos + Vector2(200, 0))
	p.lurch_t = 1.5
	p.intent.mx = -1.0                 # running away
	p.intent.fire = true
	p.intent.suppress = true
	Mutation.hijack_intent(sim, p)
	gt(p.intent.mx, 0.0, "it let you run away from the thing it wants")
	ok(not p.intent.fire, "it let you keep shooting")
	ok(not p.intent.suppress, "it let you take a dose mid-Lurch")

	# And through a whole tick, the body actually goes that way.
	var before := p.pos.x
	p.intent.mx = -1.0
	run(sim, 0.5)
	gt(p.pos.x, before, "the Lurch did not carry the body toward the walker")


func test_the_lurch_crosses_the_wire() -> void:
	p.lurch_t = 1.0
	var packed := NetProtocol.pack_player(p)
	ok(int(packed.n[NetProtocol.PL_FLAGS]) & NetProtocol.PF_LURCH, "a guest cannot tell it is happening")
	p.lurch_t = 0.0
	packed = NetProtocol.pack_player(p)
	ok(not (int(packed.n[NetProtocol.PL_FLAGS]) & NetProtocol.PF_LURCH))
