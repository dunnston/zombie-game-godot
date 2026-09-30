extends TestCase
## The workbench ladder (progression step C): five tiers, and a tier is the
## whole of what a chapter unlocks — recipes, buildables, the raid ceiling,
## the weapon level cap and the crew's jobs.

var sim: GameSim
var p: PlayerSim
var plot: Vector2i


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = clear_plot(10)
	p.pos = tile_centre(plot)


func _stock(n := 400) -> void:
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0
	for id in ["wood", "stone", "sticks", "scrap", "cloth", "elec", "parts", "mil", "fuel", "steelBar"]:
		p.bag.add(id, n)


func _bench() -> Dictionary:
	_stock()
	p.pos = tile_centre(Vector2i(plot.x + 2, plot.y)) + Vector2(0, Config.TILE * 2)
	clear_ground(sim, plot.x + 2, plot.y)
	return sim.structs.place(sim, "workbench", plot.x + 2, plot.y, p)


# ------------------------------------------------------------------ the table --

func test_the_ladder_is_one_number_per_thing_per_tier() -> void:
	for t in range(1, Config.MAX_BENCH + 1):
		var spec: Dictionary = Config.BENCH_TIERS[t]
		ok(not String(spec.name).is_empty(), "tier %d has a name" % t)
		if t > 1:
			ok(not spec.cost.is_empty(), "tier %d has an upgrade cost" % t)
			for id in spec.cost:
				ok(Config.RES.has(id), "tier %d costs %s, which stacks" % [t, id])
			var prev: Dictionary = Config.BENCH_TIERS[t - 1]
			ok(int(spec.raid_cap) >= int(prev.raid_cap), "the raid ceiling never falls")
			ok(int(spec.level_cap) >= int(prev.level_cap), "the level cap never falls")
		ok(int(spec.raid_cap) < Config.RAIDS.size(), "tier %d's raid cap names a raid" % t)
		for job in spec.jobs:
			ok(Config.JOBS.has(job), "tier %d unlocks a job that exists: %s" % [t, job])
	eq(int(Config.BENCH_TIERS[Config.MAX_BENCH].raid_cap), Config.RAIDS.size() - 1, "the top tier sends every raid")
	# Every job is somewhere on the ladder, once.
	var seen := {}
	for t in range(1, Config.MAX_BENCH + 1):
		for job in Config.BENCH_TIERS[t].jobs:
			ok(not seen.has(job), "%s is unlocked twice" % job)
			seen[job] = true
	for job in Config.JOB_IDS:
		ok(seen.has(job), "%s is on the ladder" % job)


func test_every_recipe_and_buildable_sits_on_a_rung() -> void:
	var per_tier := {}
	for r in Config.RECIPES:
		ok(int(r.bench) >= 0 and int(r.bench) <= Config.MAX_BENCH, "%s at bench %d" % [r.id, r.bench])
		per_tier[int(r.bench)] = int(per_tier.get(int(r.bench), 0)) + 1
	for id in Config.STRUCTURES:
		var t := int(Config.STRUCTURES[id].get("tier", 1))
		ok(t >= 1 and t <= Config.MAX_BENCH, "%s at tier %d" % [id, t])
	# The chapters each have work at their bench: nothing above tier 4 yet,
	# and that is step J's to fill.
	for t in range(1, 5):
		gt(int(per_tier.get(t, 0)), 0, "there is something to make at %s" % Config.bench_name(t))
	# The sets the chapters were missing exist now.
	for id in ["riotHelm", "tacGloves", "combatBoots", "milHelm", "armGuards", "milGreaves", "milBoots", "marksmanRifle", "maul", "katana"]:
		ok(not Crafting.recipe(id).is_empty(), "%s has a recipe" % id)
	eq(int(Crafting.recipe("riotHelm").bench), 2)
	eq(int(Crafting.recipe("milHelm").bench), 4)


func test_bench_names_are_the_ladders() -> void:
	eq(Config.bench_name(0), "By hand")
	eq(Config.bench_name(1), "Workbench")
	eq(Config.bench_name(2), "Workbench II")
	eq(Config.bench_name(5), "Workbench V")
	eq(Config.bench_name(99), "Workbench V", "clamped, never a crash")
	# What a bench wears in the world (Codex, PR #64): the numeral off its
	# own name, so two upgraded benches in one base can be told apart.
	eq(Config.bench_numeral(1), "")
	eq(Config.bench_numeral(2), "II")
	eq(Config.bench_numeral(3), "III")
	eq(Config.bench_numeral(5), "V")


# ---------------------------------------------------------------- climbing --

func test_the_bench_climbs_every_rung_and_pays_for_each() -> void:
	var bench := _bench()
	eq(sim.structs.bench_tier, 1)
	for t in range(2, Config.MAX_BENCH + 1):
		var cost: Dictionary = Config.BENCH_TIERS[t].cost
		var before := {}
		for id in cost:
			before[id] = p.count_res(id)
		ok(sim.structs.upgrade_bench(sim, bench, p), "up to %s" % Config.bench_name(t))
		eq(int(bench.tier), t)
		eq(sim.structs.bench_tier, t)
		for id in cost:
			eq(p.count_res(id), int(before[id]) - int(cost[id]), "%s paid for in %s" % [Config.bench_name(t), id])
	eq(sim.structs.bench_upgrade_refusal(sim, bench, p), "Already at the top")
	ok(not sim.structs.upgrade_bench(sim, bench, p), "and no further")


func test_an_upgrade_is_refused_with_its_bill_named() -> void:
	var bench := _bench()
	p.bag.clear_all()
	var why := sim.structs.bench_upgrade_refusal(sim, bench, p)
	ok(why.begins_with("Need "), why)
	ok(not sim.structs.upgrade_bench(sim, bench, p))
	eq(int(bench.tier), 1, "nothing changed")


func test_a_buildable_says_which_bench_it_needs() -> void:
	_stock()
	eq(sim.structs.can_place(sim, "reinforcedWall", plot.x + 4, plot.y, p).reason, "Needs Workbench II")
	eq(sim.structs.can_place(sim, "metalWall", plot.x + 4, plot.y, p).reason, "Needs Workbench III")
	eq(sim.structs.can_place(sim, "turret", plot.x + 4, plot.y, p).reason, "Needs Workbench III")
	sim.structs.bench_tier = 2
	ok(sim.structs.is_unlocked("reinforcedWall"))
	ok(not sim.structs.is_unlocked("metalWall"))
	eq(sim.structs.can_place(sim, "metalWall", plot.x + 4, plot.y, p).reason, "Needs Workbench III")


func test_a_recipe_says_which_bench_it_needs() -> void:
	_stock()
	var machete := Wear.recipe_for("machete")
	eq(Crafting.status(sim, p, machete, 1).reason, "Needs Workbench II")
	ok(Crafting.status(sim, p, machete, 2).ok)
	var smg := Wear.recipe_for("smg")
	eq(Crafting.status(sim, p, smg, 2).reason, "Needs Workbench III")
	var carbine := Wear.recipe_for("carbine")
	eq(Crafting.status(sim, p, carbine, 3).reason, "Needs Workbench IV")
	ok(Crafting.status(sim, p, carbine, 4).ok)


# ------------------------------------------------------------ the ceilings --

func test_the_raid_ceiling_follows_the_bench() -> void:
	# Four hordes survived, and the world still sends what the bench allows:
	# the player chooses when it gets harder.
	sim.raids_done = 4
	sim.structs.bench_tier = 0
	var r := Raid.start(sim, false)
	eq(r.index, 0, "no bench: the first raid, however many have been beaten")
	r.force_end(sim)
	eq(sim.raids_done, 5, "the count still climbs")
	sim.structs.bench_tier = 2
	r = Raid.start(sim, false)
	eq(r.index, 1, "Workbench II sends the second")
	r.force_end(sim)
	sim.structs.bench_tier = 3
	r = Raid.start(sim, false)
	eq(r.index, 2, "Workbench III the third")
	r.force_end(sim)
	sim.structs.bench_tier = Config.MAX_BENCH
	sim.raids_done = 7
	r = Raid.start(sim, false)
	eq(r.index, 7, "the top of the ladder holds nothing back, scaling included")
	r.force_end(sim)
	# A raid count below the ceiling is still its own number.
	sim.raids_done = 1
	sim.structs.bench_tier = Config.MAX_BENCH
	r = Raid.start(sim, false)
	eq(r.index, 1)
	r.force_end(sim)


func test_a_weapon_levels_only_as_far_as_the_bench_allows() -> void:
	_stock()
	p.hotbar.clear_all()
	p.hotbar.add("pipe", 1)
	eq(Config.level_cap(1), 2)
	eq(Config.level_cap(2), 4)
	eq(Config.level_cap(3), 6)
	eq(Config.level_cap(5), int(Config.UPGRADE.max), "the ladder can promise no more than the table pays for")
	ok(Upgrade.status(sim, p, "hotbar", 0, 1).ok, "level 2 at the first bench")
	ok(Actions.upgrade_weapon(sim, p, "hotbar", 0, 1))
	eq(Upgrade.level(p.hotbar, 0), 2)
	var st := Upgrade.status(sim, p, "hotbar", 0, 1)
	ok(not st.ok)
	eq(st.reason, "Needs Workbench II for level 3")
	ok(not Actions.upgrade_weapon(sim, p, "hotbar", 0, 1))
	eq(Upgrade.level(p.hotbar, 0), 2, "and it stayed")
	ok(Actions.upgrade_weapon(sim, p, "hotbar", 0, 2), "at Workbench II, yes")
	eq(Upgrade.level(p.hotbar, 0), 3)


func test_a_job_needs_its_bench() -> void:
	eq(Config.job_bench("guard"), 1)
	eq(Config.job_bench("scavenger"), 2)
	eq(Config.job_bench("sniper"), 2)
	eq(Config.job_bench("builder"), 3)
	var s := SurvivorSim.new(p.pos, "Test", 1)
	sim.crew.list.append(s)
	sim.structs.bench_tier = 1
	eq(sim.crew.job_refusal(sim, s, "guard"), "")
	eq(sim.crew.job_refusal(sim, s, "scavenger"), "Needs Workbench II")
	eq(sim.crew.job_refusal(sim, s, "builder"), "Needs Workbench III")
	ok(not sim.crew.assign_job(sim, s, "scavenger"))
	eq(s.job, "guard", "still a guard")
	sim.structs.bench_tier = 2
	ok(sim.crew.assign_job(sim, s, "scavenger"))
	eq(s.job, "scavenger")
	eq(sim.crew.job_refusal(sim, s, "builder"), "Needs Workbench III", "and the next rung is still the next rung")
	eq(sim.crew.job_refusal(sim, s, "scavenger"), "", "the job they hold is never refused")
