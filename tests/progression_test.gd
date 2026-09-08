extends "res://tests/test_case.gd"
## Levels, attributes and perks: the curve, what a point buys, and the one
## rule the whole design rests on — that `recompute_stats` is a pure function
## of the build and the only thing that writes a modifier.

var sim: GameSim
var p: PlayerSim


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]


## Every derived stat, as one comparable snapshot.
func _snapshot(q: PlayerSim) -> Dictionary:
	var out := {}
	for key in Config.STAT_BASE:
		out[key] = q.get(key)
	return out


# ------------------------------------------------------------------ tables --

func test_the_stat_base_names_real_fields() -> void:
	# STAT_BASE is applied with set(), which is silent about a typo. If a key
	# here does not exist on PlayerSim the modifier it stands for would simply
	# never arrive, and nothing else in the suite would notice.
	for key in Config.STAT_BASE:
		var before = p.get(key)
		ok(before != null, "PlayerSim has no property '%s'" % key)
		ok(typeof(before) == typeof(Config.STAT_BASE[key]),
			"'%s' is %s on the player but %s in STAT_BASE" % [key, type_string(typeof(before)), type_string(typeof(Config.STAT_BASE[key]))])


func test_every_perk_is_well_formed_and_does_something() -> void:
	var ids := {}
	for k in Config.PERKS:
		ok(not ids.has(k.id), "duplicate perk id %s" % k.id)
		ids[k.id] = true
		ok(Config.ATTRS.has(k.attr), "%s hangs off no attribute" % k.id)
		ok(int(k.req) >= Config.ATTR_MIN and int(k.req) <= Config.ATTR_MAX, k.id)
		ok(int(k.max) >= 1, k.id)
		ok(not String(k.name).is_empty() and not String(k.desc).is_empty(), k.id)

		# The table is data and the effect is a match on the id, so the two can
		# drift apart silently. Buying a rank has to move *something*.
		var q := PlayerSim.new()
		q.attrs[k.attr] = Config.ATTR_MAX
		var before := _snapshot(q)
		q.perks[k.id] = 1
		Perks.recompute_stats(q)
		ok(_snapshot(q) != before, "%s changes no stat — is there a branch for it in _apply_perk?" % k.id)
	# Four Strength, four Perception, five Constitution, four Charisma, six
	# Intelligence, five Luck. (port-inventory.md says "27" in its prose and
	# then lists 28; the prototype's table is the authority and has 28.)
	eq(ids.size(), 28, "the whole tree")


func test_the_xp_curve_matches_the_prototype() -> void:
	eq(Config.xp_for_level(1), 55)
	eq(Config.xp_for_level(2), 100)
	eq(Config.xp_for_level(5), 1224)
	eq(Config.xp_for_level(10), 7919)
	eq(Config.xp_for_level(20), 45583)
	# It has to keep biting: each level costs more than the one before.
	for l in range(2, 30):
		gt(Config.xp_for_level(l), Config.xp_for_level(l - 1), "level %d" % l)


func test_every_fifth_level_pays_two_points() -> void:
	for l in range(2, 31):
		eq(Config.points_for_level(l), 2 if l % 5 == 0 else 1, "level %d" % l)


# ------------------------------------------------------------------ levelling --

func test_a_fresh_survivor_starts_at_level_one_with_nothing_spent() -> void:
	eq(p.level, 1)
	eq(p.skill_points, 0)
	eq(p.xp_next, Config.xp_for_level(1))
	for id in Config.ATTR_IDS:
		eq(int(p.attrs[id]), Config.ATTR_START, id)
	eq(p.perks.size(), 0)


func test_one_grant_can_cross_several_levels() -> void:
	# A first raid payout is worth more than the first few levels put together,
	# so the level-up has to be a loop and not an if.
	Progression.add_xp(sim, p, 2000.0)
	eq(p.level, 5, "55 + 100 + 284 + 649 is inside 2000 x 1.07; the next 1224 is not")
	# Four levels: one point each, and the fifth level pays double.
	eq(p.skill_points, 5)
	eq(Progression.lifetime_points(p), 5)
	eq(Progression.spent_points(p), 0)
	ok(p.xp >= 0.0 and p.xp < float(p.xp_next), "and the remainder carries")
	eq(events_of(sim, "level_up").size(), 1, "four levels at once is one announcement")


func test_xp_is_multiplied_on_the_way_in() -> void:
	var fresh := PlayerSim.new()
	fresh.attrs["int"] = 2
	Perks.recompute_stats(fresh)
	near(fresh.xp_mul, 1.07, 1e-9, "Intelligence 2 is one rank over the baseline")
	# Under the first level's threshold, so what lands stays on the bar.
	Progression.add_xp(null, fresh, 40.0)
	near(fresh.xp, 42.8, 1e-9)
	eq(fresh.level, 1)

	var clever := PlayerSim.new()
	clever.attrs["int"] = 3
	clever.perks["fastLearner"] = 3
	Perks.recompute_stats(clever)
	near(clever.xp_mul, 1.0 + 0.07 * 2.0 + 0.22 * 3.0, 1e-9)


func test_levelling_never_takes_the_points_away_again() -> void:
	Progression.add_xp(sim, p, 5000.0)
	var earned := p.skill_points
	gt(earned, 0)
	# Spending and then earning more must not reset the pool.
	ok(Progression.raise_attribute(sim, p, "str"))
	eq(p.skill_points, earned - 1)
	Progression.add_xp(sim, p, 50000.0)
	eq(Progression.spent_points(p), 1, "one point spent, however many arrive after")


# ------------------------------------------------------- the recompute is pure --

func test_recompute_is_idempotent() -> void:
	p.attrs["str"] = 6
	p.attrs["lck"] = 4
	p.perks["packMule"] = 2
	p.perks["luckyStrike"] = 3
	Perks.recompute_stats(p)
	var once := _snapshot(p)
	Perks.recompute_stats(p)
	Perks.recompute_stats(p)
	eq(str(_snapshot(p)), str(once), "three passes and one pass agree")


func test_taking_a_build_apart_gives_the_baseline_back() -> void:
	var baseline := _snapshot(p)
	p.attrs["str"] = 9
	p.perks["heavyHitter"] = 3
	p.perks["packMule"] = 3
	Perks.recompute_stats(p)
	ne(str(_snapshot(p)), str(baseline), "the build did something")

	p.attrs["str"] = Config.ATTR_START
	p.perks.clear()
	Perks.recompute_stats(p)
	eq(str(_snapshot(p)), str(baseline), "and nothing of it was left behind")


func test_gear_is_the_only_source_of_damage_reduction() -> void:
	near(p.armor_dr, 0.0, 1e-9)
	p.equip["body"] = "heavyVest"
	Perks.recompute_stats(p)
	gt(p.armor_dr, 0.0, "worn armour arrives through the recompute")
	p.equip["body"] = ""
	Perks.recompute_stats(p)
	near(p.armor_dr, 0.0, 1e-9, "and leaves through it")


func test_damage_reduction_is_capped_however_much_is_worn() -> void:
	for slot in Config.ARMOR_SLOTS:
		for id in Config.GEAR:
			var g: Dictionary = Config.GEAR[id]
			if g.get("slot", "") == slot and g.get("dr", 0.0) > 0.0:
				p.equip[slot] = id
	Perks.recompute_stats(p)
	ok(p.armor_dr <= Config.MAX_GEAR_DR + 1e-9, "no amount of scavenging is immunity")


func test_a_starting_survivor_is_one_rank_above_the_baseline() -> void:
	# The numbers Phases 1-3 were balanced against, now produced rather than
	# written down. Anything here that moves has moved the whole game.
	near(p.max_hp, 112.0, 1e-9)
	near(p.max_stam, 110.0, 1e-9)
	near(p.stam_regen, 21.2, 1e-9)
	near(p.melee_mul, 1.09, 1e-9)
	near(p.spread_mul, 0.96, 1e-9)
	near(p.crit_chance, 0.08, 1e-9)
	near(p.carry_cap, 225.0, 1e-9)
	near(p.pickup_range, 49.0, 1e-9)
	near(p.chop_mul, 1.06, 1e-9)
	near(p.search_mul, 0.95, 1e-9)
	near(p.xp_mul, 1.07, 1e-9)
	eq(p.survivor_cap, 1, "Charisma 2 houses one")
	eq(p.hp, p.max_hp, "and wakes up whole")
	eq(p.stam, p.max_stam)


# ------------------------------------------------------------------ spending --

func test_a_perk_whose_system_is_not_built_yet_cannot_take_your_point() -> void:
	# Sixth Sense wants a minimap and Hotwire wants cars; neither exists yet.
	# They stay in the tree so it matches the spec and can be planned around,
	# but a point must never buy nothing.
	var waiting := 0
	for k in Config.PERKS:
		if String(k.get("needs", "")).is_empty():
			continue
		waiting += 1
		p.skill_points = 20
		p.attrs[k.attr] = Config.ATTR_MAX
		var st := Perks.perk_status(p, k)
		ok(not st.ok, k.id)
		ok(st.reason.begins_with("Waiting on"), "%s says %s" % [k.id, st.reason])
		ok(not Progression.buy_perk(sim, p, String(k.id)), k.id)
		eq(p.skill_points, 20, "%s refused and charged nothing" % k.id)
		eq(int(p.perks.get(k.id, 0)), 0)
	gt(waiting, 0, "there is at least one perk waiting on a later phase")


func test_a_perk_gated_above_your_rank_is_refused_with_a_reason() -> void:
	p.skill_points = 5
	# Demolisher needs Strength 5 and everyone starts at 2.
	var st := Perks.perk_status(p, Perks.perk_by_id("demolisher"))
	ok(not st.ok)
	ok(st.locked, "locked is a plan, not a wait")
	eq(st.reason, "Needs STR 5")

	ok(not Progression.buy_perk(sim, p, "demolisher"))
	eq(p.skill_points, 5, "a refusal costs nothing")
	eq(int(p.perks.get("demolisher", 0)), 0)

	p.attrs["str"] = 5
	ok(Progression.buy_perk(sim, p, "demolisher"), "and at rank 5 it is yours")
	eq(p.skill_points, 4)


func test_a_perk_stops_at_its_maximum() -> void:
	p.skill_points = 20
	p.attrs["con"] = 4
	for i in range(4):
		ok(Progression.buy_perk(sim, p, "thickSkin"), "rank %d" % (i + 1))
	eq(int(p.perks.thickSkin), 4)
	var st := Perks.perk_status(p, Perks.perk_by_id("thickSkin"))
	ok(not st.ok)
	ok(not st.locked, "not locked — finished")
	eq(st.reason, "Fully learned")
	ok(not Progression.buy_perk(sim, p, "thickSkin"))
	eq(p.skill_points, 16, "four bought, the fifth refused")


func test_an_attribute_stops_at_ten() -> void:
	p.skill_points = 50
	for i in range(8):
		ok(Progression.raise_attribute(sim, p, "per"), "rank %d" % (i + 3))
	eq(int(p.attrs.per), Config.ATTR_MAX)
	var check := Perks.can_raise_attr(p, "per")
	ok(not check.ok)
	eq(check.reason, "Already at maximum")
	eq(p.skill_points, 42)


func test_no_points_is_a_different_refusal_from_no_rank() -> void:
	p.skill_points = 0
	eq(Perks.can_raise_attr(p, "str").reason, "No skill points")
	# Pack Mule needs Strength 2, which is where everyone starts, so the only
	# thing standing in the way is the empty pocket.
	var st := Perks.perk_status(p, Perks.perk_by_id("packMule"))
	eq(st.reason, "No skill points")
	ok(not st.locked)


func test_raising_constitution_hands_the_health_over() -> void:
	p.skill_points = 4
	p.hp = 50.0
	p.stam = 20.0
	var hp_before := p.max_hp
	ok(Progression.raise_attribute(sim, p, "con"))
	near(p.max_hp, hp_before + 12.0, 1e-9)
	near(p.hp, 62.0, 1e-9, "the gain is handed over, not left as headroom")
	near(p.stam, 30.0, 1e-9)

	# Thick Skin is the same rule through the other door.
	ok(Progression.buy_perk(sim, p, "thickSkin"))
	near(p.hp, 92.0, 1e-9)
	ok(p.hp <= p.max_hp)


func test_a_full_survivor_stays_full_and_never_overflows() -> void:
	p.skill_points = 2
	ok(Progression.raise_attribute(sim, p, "con"))
	eq(p.hp, p.max_hp, "already full, still full")
	eq(p.stam, p.max_stam)


# ---------------------------------------------------------- what perks do --

func test_pack_mule_and_strength_both_reach_the_pack() -> void:
	p.skill_points = 10
	var base := p.carry_cap
	ok(Progression.buy_perk(sim, p, "packMule"))
	near(p.carry_cap, base + 70.0, 1e-9)
	ok(Progression.buy_perk(sim, p, "packMule"))
	near(p.carry_cap, base + 140.0, 1e-9, "rank 2 is 70 x 2, not 70 + 70 twice over")
	ok(Progression.raise_attribute(sim, p, "str"))
	near(p.carry_cap, base + 140.0 + 25.0, 1e-9)


func test_engineer_makes_a_wall_cheaper_to_put_up() -> void:
	var plot := clear_plot(6)
	p.pos = tile_centre(plot)
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0
	p.bag.add("wood", 200)

	var list_price: int = Config.STRUCTURES.woodWall.cost.wood
	p.attrs["int"] = Config.ATTR_MIN          # no discount at all
	Perks.recompute_stats(p)
	var before := p.count_res("wood")
	ok(not sim.structs.place(sim, "woodWall", plot.x + 2, plot.y, p).is_empty())
	eq(before - p.count_res("wood"), list_price, "the list price with nothing invested")

	p.attrs["int"] = 3
	p.perks["engineer"] = 3
	Perks.recompute_stats(p)
	before = p.count_res("wood")
	ok(not sim.structs.place(sim, "woodWall", plot.x + 3, plot.y, p).is_empty())
	var paid := before - p.count_res("wood")
	ok(paid < list_price, "Engineer 3 pays %d of %d" % [paid, list_price])
	eq(paid, ceili(list_price * p.build_cost_mul), "and pays exactly what it was quoted")


func test_the_build_card_quotes_what_placing_it_will_charge() -> void:
	# The bill a prompt prints and the bill it charges have to be the same
	# number. The repair prompt learned this; the build cards had not, so a
	# player with Engineer saw a red "WOOD 16" and then built for eleven.
	p.attrs["int"] = 8
	p.perks["engineer"] = 3
	Perks.recompute_stats(p)
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0

	var list_price: int = Config.STRUCTURES.woodWall.cost.wood
	var quoted: int = sim.structs.cost_of("woodWall", p).wood
	ok(quoted < list_price, "Engineer quotes %d against a list price of %d" % [quoted, list_price])

	# Exactly the quoted price in the pack. The card is what the player reads
	# before clicking, so it is the thing that has to agree.
	p.bag.add("wood", quoted)
	var bar := BuildBar.new(sim)
	var card := bar.card_info("woodWall")
	eq(int(card.cost.wood), quoted, "the card prints the discounted bill")
	ok(card.afford, "and does not call it unaffordable when it is affordable")

	var plot := clear_plot(6)
	p.pos = tile_centre(plot)
	var s := sim.structs.place(sim, "woodWall", plot.x + 2, plot.y, p)
	ok(not s.is_empty(), "and placing it succeeds")
	eq(p.count_res("wood"), 0, "having charged exactly what it quoted")
	eq(int(card.hp), int(s.max_hp), "and the strength it promised is what went up")
	bar.free()


func test_salvage_refunds_what_you_paid_not_the_list_price() -> void:
	# Without this, Engineer 3 builds at 0.47 and salvages at 0.55, and a wall
	# put up and taken down again is free material.
	var plot := clear_plot(6)
	p.pos = tile_centre(plot)
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0
	p.bag.add("wood", 400)
	p.attrs["int"] = 10
	p.perks["engineer"] = 3
	Perks.recompute_stats(p)
	ok(p.build_cost_mul < 0.5, "a deep Engineer build: %f" % p.build_cost_mul)

	# A refund goes to the stash, and to the ground when there is none — so
	# counting the pack alone would miss the whole exploit.
	var total := func() -> int:
		var n: int = p.count_res("wood")
		if sim.stash != null:
			n += sim.stash.count("wood")
		for it in sim.pickups:
			if it.id == "wood":
				n += it.n
		return n

	var before: int = total.call()
	# The same tile every time, so placement range is never what is being
	# tested — only the arithmetic of paying and being paid back.
	for i in range(12):
		var s := sim.structs.place(sim, "woodWall", plot.x + 2, plot.y, p)
		ok(not s.is_empty(), "wall %d went up" % i)
		sim.structs.demolish(sim, s, p)
	var after: int = total.call()
	ok(after <= before, "twelve build-and-salvage cycles are not a wood mine (%d -> %d)" % [before, after])


func test_fortifier_is_the_hosts_business_and_not_the_builders() -> void:
	var plot := clear_plot(6)
	p.pos = tile_centre(plot)
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0
	p.bag.add("wood", 400)

	var plain := sim.structs.place(sim, "woodWall", plot.x + 2, plot.y, p)
	p.perks["fortifier"] = 3
	Perks.recompute_stats(p)
	var tough := sim.structs.place(sim, "woodWall", plot.x + 3, plot.y, p)
	gt(tough.max_hp, plain.max_hp, "the same wall, built by a stronger host")
	near(tough.max_hp, roundf(Config.STRUCTURES.woodWall.hp * (1.0 + 0.45 * 3.0)), 1e-9)
	eq(tough.hp, tough.max_hp, "and it starts intact")


func test_adrenaline_comes_and_goes_with_the_health_bar() -> void:
	p.perks["adrenaline"] = 1
	Perks.recompute_stats(p)
	ok(p.adrenaline)
	ok(not p.adrenaline_active, "at full health it is dormant")

	p.hp = p.max_hp * 0.2
	sim.tick(1.0 / 60.0)
	ok(p.adrenaline_active, "and wakes up when you are nearly down")

	p.hp = p.max_hp
	sim.tick(1.0 / 60.0)
	ok(not p.adrenaline_active, "healing puts it away again")


func test_second_wind_catches_one_killing_blow_then_waits() -> void:
	p.perks["secondWind"] = 1
	Perks.recompute_stats(p)
	p.hp = 10.0
	Damage.damage_player(sim, p, 9999.0, p.pos + Vector2(10, 0))
	ok(not p.dead, "the blow that would have killed you did not")
	near(p.hp, 1.0, 1e-9)
	near(p.second_wind_cd, Config.SECOND_WIND_CD, 1e-9)
	eq(events_of(sim, "second_wind").size(), 1)

	# The second one inside two minutes is a death.
	p.invuln = 0.0
	Damage.damage_player(sim, p, 9999.0, p.pos + Vector2(10, 0))
	ok(p.dead, "it does not save you twice in two minutes")


func test_second_wind_recharges() -> void:
	p.perks["secondWind"] = 1
	Perks.recompute_stats(p)
	p.second_wind_cd = 0.5
	run(sim, 1.0)
	near(p.second_wind_cd, 0.0, 1e-9)
	p.hp = 5.0
	p.invuln = 0.0
	Damage.damage_player(sim, p, 9999.0, p.pos + Vector2(10, 0))
	ok(not p.dead, "and catches the next one")


func test_gunsmith_pays_out_in_ammunition_only() -> void:
	var plot := clear_plot(6)
	p.pos = tile_centre(plot)
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0

	var ammo_recipe := {}
	var other_recipe := {}
	for r in Config.RECIPES:
		if not r.give.has("res"):
			continue
		var only_ammo := true
		var any_ammo := false
		for id in r.give.res:
			if id in Config.AMMO_IDS:
				any_ammo = true
			else:
				only_ammo = false
		if any_ammo and only_ammo and ammo_recipe.is_empty():
			ammo_recipe = r
		elif not any_ammo and other_recipe.is_empty():
			other_recipe = r
	ok(not ammo_recipe.is_empty(), "there is a recipe that makes ammunition")

	p.perks["gunsmith"] = 2
	Perks.recompute_stats(p)
	near(p.craft_yield_mul, 1.0 + 0.6 * 2.0, 1e-9)
	# After the recompute, which would otherwise hand the cap straight back.
	p.carry_cap = 1000000.0

	for id in ammo_recipe.cost:
		p.bag.add(id, 900)
	var ammo_id: String = ammo_recipe.give.res.keys()[0]
	var want: int = ammo_recipe.give.res[ammo_id]
	var before := p.count_res(ammo_id)
	ok(Crafting.craft(sim, p, ammo_recipe, 2), ammo_recipe.id)
	eq(p.count_res(ammo_id) - before, roundi(want * p.craft_yield_mul), "a bigger batch")


func test_low_profile_reaches_threat_and_noise_together() -> void:
	p.perks["lowProfile"] = 2
	Perks.recompute_stats(p)
	near(p.threat_mul, 0.49, 1e-9)
	near(p.noise_mul, 0.49, 1e-9)

	var before := sim.threat.value
	sim.threat.add(sim, 10.0, p)
	near(sim.threat.value - before, 4.9, 1e-6, "Threat arrives already quietened")


func test_luck_reweights_a_loot_table_toward_its_rare_entries() -> void:
	# Scavenger's Luck changes the odds, not the amounts — that is Scrounger's
	# job — so the test is a distribution, not a single roll.
	var table_id := ""
	for id in Config.LOOT:
		for e in Config.LOOT[id]:
			if e.id == "parts":
				table_id = id
				break
		if not table_id.is_empty():
			break
	ok(not table_id.is_empty(), "some table pays out weapon parts")

	var container := {"table": table_id, "rolls": [3, 3]}
	var plain := 0
	var lucky := 0
	for i in range(400):
		for e in Loot.roll_container(sim, container, 1.0, 1.0, 0.0):
			if e.id == "parts":
				plain += e.n
		for e in Loot.roll_container(sim, container, 1.0, 1.9, 0.0):
			if e.id == "parts":
				lucky += e.n
	gt(lucky, plain, "a luckier survivor sees the scarce entry more often (%d vs %d)" % [lucky, plain])


func test_fortune_can_pay_a_container_out_twice() -> void:
	var container := {"table": "shelf", "rolls": [2, 2]}
	var certain := 0
	var never := 0
	for i in range(200):
		for e in Loot.roll_container(sim, container, 1.0, 1.0, 1.0):
			certain += e.n
		for e in Loot.roll_container(sim, container, 1.0, 1.0, 0.0):
			never += e.n
	gt(certain, never, "doubled rolls pay more (%d vs %d)" % [certain, never])


# ---------------------------------------------------------------- the save --

func test_a_build_survives_a_save_and_is_re_derived_not_stored() -> void:
	p.skill_points = 12
	p.attrs["con"] = 6
	p.attrs["str"] = 4
	p.perks["thickSkin"] = 2
	p.perks["packMule"] = 1
	p.level = 7
	p.xp = 40.0
	p.xp_next = Config.xp_for_level(7)
	p.second_wind_cd = 33.0
	Perks.recompute_stats(p)
	p.hp = p.max_hp
	var built := _snapshot(p)

	var rec: Dictionary = SaveGame.to_dict(sim).players[0]
	for key in Config.STAT_BASE:
		ok(not rec.has(key), "'%s' is derived and has no business in a save" % key)
	eq(int(rec.level), 7)
	eq(int(rec.skill_points), 12)

	# Rebuild a player the way the loader does and check the stats came back.
	var q := PlayerSim.new()
	for k in rec.attrs:
		q.attrs[k] = int(rec.attrs[k])
	for k in rec.perks:
		q.perks[k] = int(rec.perks[k])
	Equipment.recompute_stats(q)
	eq(str(_snapshot(q)), str(built), "the same build produces the same survivor")

