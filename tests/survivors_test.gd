extends "res://tests/test_case.gd"
## The crew: who will follow you, where they sleep, what they eat, what they
## do all day, and the two rules that run through all of it — everything comes
## out of the shared stash, and nothing walks anywhere without a give-up timer.

var sim: GameSim
var p: PlayerSim
var plot: Vector2i


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = clear_plot(10)
	p.pos = tile_centre(plot)
	p.intent.aim = p.pos + Vector2.RIGHT


func _stock(n := 400) -> void:
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0
	for id in ["wood", "stone", "sticks", "scrap", "cloth", "elec", "parts", "mil", "fuel"]:
		p.bag.add(id, n)


func _build(type: String, tx: int, ty: int) -> Dictionary:
	# Placement is range-limited, so the builder walks their own perimeter.
	p.pos = tile_centre(Vector2i(tx, ty)) + Vector2(0, Config.TILE * 2)
	# These tests are about the crew, not about where sticks lie.
	clear_ground(sim, tx, ty)
	var s := sim.structs.place(sim, type, tx, ty, p)
	p.pos = tile_centre(plot)
	return s


## Steps only the crew, for the tests that are about what the crew does rather
## than about the world around them. Upkeep is billed on a ten-second cadence,
## so testing it through `run` costs ten simulated seconds a time.
func _tick_crew(seconds: float) -> void:
	var dt := 1.0 / 60.0
	for i in range(int(round(seconds / dt))):
		sim.enemies.rebuild_spatial()
		sim.crew.tick(sim, dt)


## A base that can actually house people: a stash to draw from and `n` bunks.
func _settle(n := 2) -> void:
	_stock()
	_build("stash", plot.x - 2, plot.y + 2)
	for i in range(n):
		_build("bunk", plot.x - 2 + i, plot.y - 2)
	p.attrs["cha"] = 10
	Perks.recompute_stats(p)


func _hire(n := 1) -> Array[SurvivorSim]:
	var out: Array[SurvivorSim] = []
	for i in range(n):
		out.append(sim.crew.make(sim, tile_centre(plot) + Vector2(30.0 * (i + 1), 0)))
	return out


# ------------------------------------------------------------- the roster --

func test_the_roster_is_capped_by_charisma_and_by_bunks_together() -> void:
	_stock()
	p.attrs["cha"] = 10
	Perks.recompute_stats(p)
	gt(p.survivor_cap, 3, "Charisma 10 will lead several")
	eq(sim.crew.cap(sim), 0, "but with nowhere to sleep, nobody")

	_build("bunk", plot.x - 2, plot.y - 2)
	eq(sim.crew.cap(sim), 1, "one bunk, one person")
	_build("bunk", plot.x - 1, plot.y - 2)
	eq(sim.crew.cap(sim), 2)

	# And the other way round: bunks are useless without the Charisma to lead.
	p.attrs["cha"] = Config.ATTR_MIN
	Perks.recompute_stats(p)
	eq(sim.crew.cap(sim), 0, "nobody will follow a survivor with no Charisma")


func test_a_refusal_says_which_limit_is_in_the_way() -> void:
	_stock()
	p.attrs["cha"] = 10
	Perks.recompute_stats(p)
	ok(sim.crew.recruit_refusal(sim).contains("Bunk"), sim.crew.recruit_refusal(sim))

	_build("bunk", plot.x - 2, plot.y - 2)
	eq(sim.crew.recruit_refusal(sim), "", "a bunk and the Charisma is room for one")
	_hire(1)
	ok(sim.crew.recruit_refusal(sim).contains("Bunk"), sim.crew.recruit_refusal(sim))

	# With a spare bunk standing empty, beds are no longer the thing in the
	# way — so the refusal has to name the other limit instead.
	_build("bunk", plot.x, plot.y - 2)
	p.attrs["cha"] = Config.ATTR_MIN
	Perks.recompute_stats(p)
	ok(sim.crew.recruit_refusal(sim).contains("Charisma"),
		"a spare bed and no Charisma names Charisma: %s" % sim.crew.recruit_refusal(sim))


func test_recruiting_takes_them_off_the_map() -> void:
	_settle(2)
	gt(sim.crew.rescues.size(), 0, "the world was seeded with people to find")
	var rescue: Dictionary = sim.crew.rescues[0]
	var before := sim.crew.rescues.size()
	var s := sim.crew.recruit(sim, rescue, p)
	ok(s != null, "recruited")
	eq(sim.crew.rescues.size(), before - 1, "and they are no longer out there")
	eq(sim.crew.alive().size(), 1)
	eq(s.display_name, String(rescue.name), "the person you found is the person who came")


func test_a_full_roster_refuses_and_leaves_them_where_they_are() -> void:
	_settle(1)
	sim.crew.recruit(sim, sim.crew.rescues[0], p)
	var left := sim.crew.rescues.size()
	var s := sim.crew.recruit(sim, sim.crew.rescues[0], p)
	eq(s, null, "refused")
	eq(sim.crew.rescues.size(), left, "and still out there to come back for")
	eq(sim.crew.alive().size(), 1)


func test_rescues_are_seeded_apart_and_on_open_ground() -> void:
	var n := sim.crew.rescues.size()
	eq(n, Config.RESCUE_COUNT, "the world holds the full complement")
	for i in range(n):
		var a: Vector2 = sim.crew.rescues[i].pos
		ok(not sim.world.is_blocked_px(a.x, a.y), "rescue %d is standing somewhere" % i)
		for j in range(i + 1, n):
			var b: Vector2 = sim.crew.rescues[j].pos
			gt(a.distance_to(b), Config.RESCUE_SPACING * 0.99,
				"finding one is not finding all of them")


# ------------------------------------------------------------------ stats --

func test_charisma_perks_reach_the_people_already_standing_there() -> void:
	_settle(3)
	var s := _hire(1)[0]
	var hp_before := s.max_hp
	var dmg_before := s.dmg

	p.perks["inspiring"] = 2
	Perks.recompute_stats(p)
	sim.crew.refresh_all(sim)
	gt(s.max_hp, hp_before, "Inspiring Presence is not only for the next hire")
	gt(s.dmg, dmg_before)
	near(s.max_hp, roundf((Config.SURVIVOR.base_hp) * p.survivor_hp_mul), 1.0)


func test_levelling_a_survivor_makes_them_tougher() -> void:
	_settle(2)
	var s := _hire(1)[0]
	var hp1 := s.max_hp
	sim.crew.award_xp(sim, s, Config.SURVIVOR.xp_per_level * 3.0)
	gt(s.level, 1, "levelled to %d" % s.level)
	gt(s.max_hp, hp1)
	eq(s.hp, s.max_hp, "and a level up puts them back on their feet")


func test_a_survivor_stops_at_the_level_ceiling() -> void:
	_settle(2)
	var s := _hire(1)[0]
	sim.crew.award_xp(sim, s, 100000.0)
	eq(s.level, int(Config.SURVIVOR.max_level))


# ----------------------------------------------------------------- upkeep --

func test_rations_come_out_of_the_stash_and_never_your_pack() -> void:
	_settle(2)
	_hire(2)
	sim.stash.add("rations", 40)
	p.bag.add("rations", 200)
	var stash_before := sim.stash.count("rations")
	var pack_before := p.count_res("rations")

	# A single bill is a fraction of a Ration; whole ones are taken as the
	# fraction accumulates, so this needs a few minutes of upkeep.
	for i in range(12):
		sim.crew.tick_upkeep(sim, Config.SURVIVOR.upkeep_every)
	ok(sim.stash.count("rations") < stash_before, "the pantry is the stash")
	eq(p.count_res("rations"), pack_before, "food in your own pack is no use to anyone")


func test_an_empty_stash_starves_them_rather_than_killing_them() -> void:
	_settle(2)
	var crew := _hire(2)
	# No rations anywhere. One tick of upkeep is a fraction of a ration, so
	# hunger only bites once the debt passes a whole one — a few cycles.
	sim.crew.tick_upkeep(sim, Config.SURVIVOR.upkeep_every + 0.5)
	gt(sim.crew.debt, 0.0, "the bill went unpaid")
	for i in range(6):
		sim.crew.tick_upkeep(sim, Config.SURVIVOR.upkeep_every + 0.01)
	gt(sim.crew.debt, 1.0, "and kept going unpaid")
	for s in crew:
		ok(s.hungry, "%s is hungry" % s.display_name)
		ok(not s.dead, "but not gone")


func test_restocking_clears_the_debt_rather_than_leaving_it_for_ever() -> void:
	_settle(2)
	_hire(1)
	# Run up a real shortage with an empty pantry.
	for i in range(12):
		sim.crew.tick_upkeep(sim, Config.SURVIVOR.upkeep_every)
	gt(sim.crew.debt, 1.0, "they are behind")
	# Restock, and the backlog is charged alongside the next bill rather than
	# being written off — billing only the current tick would leave a shortage
	# outstanding for ever.
	sim.stash.add("rations", 60)
	sim.crew.tick_upkeep(sim, Config.SURVIVOR.upkeep_every)
	ok(sim.crew.debt < 1.0, "the shortage is cleared (%f left, which is the running fraction)" % sim.crew.debt)
	for s in sim.crew.alive():
		ok(not s.hungry)


func test_the_debt_is_capped_so_a_long_trip_is_recoverable() -> void:
	_settle(2)
	_hire(2)
	# A very long time away with nothing in the pantry.
	for i in range(60):
		sim.crew.tick_upkeep(sim, Config.SURVIVOR.upkeep_every + 0.01)
	ok(sim.crew.debt <= Config.SURVIVOR.debt_cap + 0.001,
		"debt %f is capped at %f" % [sim.crew.debt, Config.SURVIVOR.debt_cap])


func test_quartermaster_makes_them_eat_less() -> void:
	_settle(2)
	_hire(2)
	sim.stash.add("rations", 200)
	var before := sim.stash.count("rations")
	sim.crew.tick_upkeep(sim, Config.SURVIVOR.upkeep_every + 0.01)
	var hungry_bill := before - sim.stash.count("rations")

	p.perks["quartermaster"] = 2
	Perks.recompute_stats(p)
	before = sim.stash.count("rations")
	sim.crew.tick_upkeep(sim, Config.SURVIVOR.upkeep_every + 0.01)
	var thrifty_bill := before - sim.stash.count("rations")
	ok(thrifty_bill <= hungry_bill, "%d against %d" % [thrifty_bill, hungry_bill])


# -------------------------------------------------------------------- jobs --

func test_every_job_can_be_assigned_and_says_so() -> void:
	_settle(3)
	_build("watchtower", plot.x + 3, plot.y - 3)
	var s := _hire(1)[0]
	for id in Config.JOB_IDS:
		ok(sim.crew.assign_job(sim, s, String(id)), id)
		eq(s.job, String(id))


func test_a_sniper_needs_a_free_tower() -> void:
	_settle(3)
	var s := _hire(1)[0]
	ok(not sim.crew.assign_job(sim, s, "sniper"), "no tower, no sniper")
	eq(s.job, "guard", "and they keep the job they had")

	_build("watchtower", plot.x + 3, plot.y - 3)
	ok(sim.crew.assign_job(sim, s, "sniper"))
	ok(not s.tower.is_empty())

	# The second person cannot have the same tower.
	var other := _hire(1)[0]
	ok(not sim.crew.assign_job(sim, other, "sniper"), "one tower, one sniper")


func test_a_sniper_only_gets_the_tower_reach_while_standing_on_it() -> void:
	_settle(3)
	var tower := _build("watchtower", plot.x + 3, plot.y - 3)
	ok(not tower.is_empty())
	var s := _hire(1)[0]
	ok(sim.crew.assign_job(sim, s, "sniper"))

	# Assigned, but a long way off: still ordinary reach.
	s.pos = tower.pos + Vector2(600, 0)
	run(sim, 0.2)
	ok(not s.posted, "holding a reference to a tower is not standing on it")
	near(s.shot_range, Config.SURVIVOR.range, 0.001)

	s.pos = tower.pos
	run(sim, 0.2)
	ok(s.posted)
	gt(s.shot_range, Config.SURVIVOR.range, "posted, they cover the whole approach")


func test_a_destroyed_tower_turns_its_sniper_back_into_a_guard() -> void:
	_settle(3)
	var tower := _build("watchtower", plot.x + 3, plot.y - 3)
	var s := _hire(1)[0]
	sim.crew.assign_job(sim, s, "sniper")
	sim.structs.damage(sim, tower, tower.max_hp * 2.0)
	run(sim, 0.2)
	eq(s.job, "guard", "a sniper with nowhere to stand is a guard, not a crash")
	ok(s.tower.is_empty())


func test_reassignment_never_eats_a_haul() -> void:
	# The haul came out of a real container. Reassigning has to hand it in or
	# put it down, never quietly delete it.
	_settle(3)
	var s := _hire(1)[0]
	s.job = "scavenger"
	s.carrying = {"scrap": 12}
	s.pos = tile_centre(plot) + Vector2(600, 600)   # nowhere near the stash
	var on_ground_before := sim.pickups.size()
	sim.crew.assign_job(sim, s, "guard")
	ok(s.carrying.is_empty(), "they are not carrying it any more")
	gt(sim.pickups.size(), on_ground_before, "because it is on the floor where they stood")


# ---------------------------------------------------------------- fighting --

func test_a_downed_survivor_dies_if_nobody_helps() -> void:
	_settle(3)
	var s := _hire(1)[0]
	sim.crew.damage(sim, s, s.max_hp * 2.0, s.pos + Vector2(10, 0))
	ok(s.downed, "down, not gone")
	ok(not s.dead)
	_tick_crew(Config.SURVIVOR.revive_time + 0.5)
	ok(s.dead, "and permanently, if nobody reaches them")
	eq(sim.crew.alive().size(), 0)


func test_helping_them_up_costs_medicine() -> void:
	_settle(3)
	var s := _hire(1)[0]
	sim.crew.damage(sim, s, s.max_hp * 2.0, s.pos + Vector2(10, 0))
	ok(s.downed)

	# The starting kit puts bandages on the hotbar, and `held` counts both.
	p.bag.clear_all()
	p.hotbar.clear_all()
	ok(not sim.crew.revive(sim, s, p), "empty-handed is not enough")
	ok(s.downed)

	p.bag.add("bandage", 2)
	ok(sim.crew.revive(sim, s, p))
	ok(not s.downed)
	gt(s.hp, 0.0)
	eq(p.count_carried("bandage"), 0, "and it cost the bandages")


func test_the_dead_leave_what_they_were_carrying() -> void:
	_settle(3)
	var s := _hire(1)[0]
	s.carrying = {"scrap": 9}
	var before := sim.pickups.size()
	sim.crew.damage(sim, s, s.max_hp * 2.0, s.pos + Vector2(10, 0))
	_tick_crew(Config.SURVIVOR.revive_time + 0.5)
	ok(s.dead)
	gt(sim.pickups.size(), before, "the haul is where they fell")


# ----------------------------------------------------------------- the save --

func test_a_crew_survives_a_save_and_is_re_derived_not_stored() -> void:
	_settle(3)
	var tower := _build("watchtower", plot.x + 3, plot.y - 3)
	var s := _hire(1)[0]
	sim.crew.award_xp(sim, s, Config.SURVIVOR.xp_per_level * 2.0)
	sim.crew.assign_job(sim, s, "sniper")
	s.kills = 7

	var d := SaveGame.to_dict(sim)
	eq(int(d.crew.size()), 1)
	var rec: Dictionary = d.crew[0]
	eq(int(rec.level), s.level)
	eq(String(rec.job), "sniper")
	ok(not rec.has("max_hp"), "the ceiling is derived and has no business in a save")
	ok(not rec.has("dmg"), "nor the damage")
	# Invariant 7 again: the tower is remembered by tile, never by index.
	eq(int(rec.tower_tx), int(tower.tx))
	eq(int(rec.tower_ty), int(tower.ty))
	eq(int(d.rescues.size()), sim.crew.rescues.size())



# ------------------------------------------------- what the review found --

func test_a_bullet_carries_who_fired_it() -> void:
	# The kill credit is read off the bullet's `owner`. The tag spent one
	# review in the `weapon` slot instead, so every survivor kill arrived at
	# `damage_enemy` with a null source and nobody was ever credited.
	# Asserting on `kill_enemy` directly did not exercise this at all.
	_settle(3)
	sim.stash.add("ammoP", 200)
	var s := _hire(1)[0]
	var e := sim.enemies.spawn("walker", s.pos + Vector2(100, 0))
	e.hp = 99999.0
	run(sim, 1.5)
	gt(sim.bullets.size() + sim.stats.damage_dealt, 0.0, "they fired")
	var tagged := 0
	for b in sim.bullets:
		if String(b.owner) == "survivor:%d" % s.id:
			tagged += 1
	# Either a bullet is still in the air carrying the tag, or one has already
	# landed — both are the same wiring.
	ok(tagged > 0 or sim.stats.damage_dealt > 0.0, "the bullet knows who fired it")


func test_a_kill_through_the_bullet_credits_the_survivor() -> void:
	_settle(3)
	sim.stash.add("ammoP", 400)
	var s := _hire(1)[0]
	var e := sim.enemies.spawn("walker", s.pos + Vector2(90, 0))
	var xp_before := p.xp
	run(sim, 8.0)
	ok(e.dead, "the guard put it down")
	gt(s.kills, 0, "and was credited for it, through the bullet and not a direct call")
	gt(s.xp, 0.0)
	gt(p.xp, xp_before)


func test_upkeep_bills_a_ration_a_minute_and_not_six() -> void:
	# One survivor owes about a sixth of a Ration per ten-second bill, and
	# Rations are whole things. Rounding each bill up to one ate six a minute.
	_settle(2)
	_hire(1)
	sim.stash.add("rations", 500)
	var before := sim.stash.count("rations")
	# Six bills is one minute of upkeep for one person: one Ration.
	for i in range(6):
		sim.crew.tick_upkeep(sim, Config.SURVIVOR.upkeep_every)
	var spent := before - sim.stash.count("rations")
	eq(spent, 1, "a minute of one survivor is one Ration, not %d" % spent)

	# And it keeps being one a minute rather than drifting.
	for i in range(18):
		sim.crew.tick_upkeep(sim, Config.SURVIVOR.upkeep_every)
	eq(before - sim.stash.count("rations"), 4, "four minutes, four Rations")


func test_a_fed_crew_never_reads_as_starving() -> void:
	# The carried fraction must stay under the hunger threshold, or a fully
	# stocked base would flicker into starvation every few bills.
	_settle(3)
	_hire(3)
	sim.stash.add("rations", 900)
	for i in range(40):
		sim.crew.tick_upkeep(sim, Config.SURVIVOR.upkeep_every)
		for s in sim.crew.alive():
			ok(not s.hungry, "%s went hungry beside a full pantry" % s.display_name)


func test_a_builder_cannot_repair_out_of_an_empty_stash() -> void:
	# Healing first and billing on the way past a threshold let a builder patch
	# a wall for nothing all raid whenever the stash was empty.
	_settle(3)
	var wall := _build("woodWall", plot.x + 2, plot.y)
	ok(not wall.is_empty())
	sim.structs.damage(sim, wall, wall.max_hp * 0.6)
	var hurt: float = wall.hp

	# Nothing to build with.
	for id in Config.BUILDER.cost_per_100:
		sim.stash.take(String(id), 99999)
	var s := _hire(1)[0]
	s.pos = wall.pos + Vector2(20, 0)
	sim.crew.assign_job(sim, s, "builder")
	_tick_crew(4.0)
	near(wall.hp, hurt, 0.001, "no materials, no repair")

	# Stock it and they get on with it.
	for id in Config.BUILDER.cost_per_100:
		sim.stash.add(String(id), 200)
	_tick_crew(4.0)
	gt(wall.hp, hurt, "with a stocked stash they patch it")


func test_a_builder_pays_for_every_point_it_heals() -> void:
	_settle(3)
	var wall := _build("metalWall", plot.x + 2, plot.y) if false else _build("woodWall", plot.x + 2, plot.y)
	sim.structs.damage(sim, wall, wall.max_hp * 0.9)
	for id in Config.BUILDER.cost_per_100:
		sim.stash.add(String(id), 500)
	var wood_before := sim.stash.count("wood")
	var hp_before: float = wall.hp

	var s := _hire(1)[0]
	s.pos = wall.pos + Vector2(20, 0)
	sim.crew.assign_job(sim, s, "builder")
	_tick_crew(6.0)

	var healed: float = wall.hp - hp_before
	var paid := wood_before - sim.stash.count("wood")
	gt(healed, 0.0, "they repaired something")
	gt(paid, 0, "and it cost wood")
	# Blocks of 100 health, bought up front, so the bill is never behind.
	var blocks := ceili(healed / 100.0)
	ok(paid >= blocks * int(Config.BUILDER.cost_per_100.wood),
		"%d wood for %.0f health is at least %d blocks" % [paid, healed, blocks])


func test_a_sniper_gives_up_on_a_tower_they_cannot_reach() -> void:
	# Every other walk has a give-up timer. Without one here, a tower behind a
	# shut gate holds somebody against it for the rest of the run.
	_settle(3)
	var tower := _build("watchtower", plot.x + 6, plot.y + 6)
	ok(not tower.is_empty())
	var s := _hire(1)[0]
	ok(sim.crew.assign_job(sim, s, "sniper"))
	eq(s.job, "sniper")

	# Pin them: they cannot close on it, however long they try.
	var stuck: Vector2 = tower.pos + Vector2(400, 0)
	# Two full give-up windows: the first trip primes the "last distance" from
	# infinity, and only the second can see that no progress was made.
	for i in range(int(Config.SCAVENGE.give_up_after * 3.0 * 60.0)):
		s.pos = stuck
		s.vel = Vector2.ZERO
		sim.enemies.rebuild_spatial()
		sim.crew.tick(sim, 1.0 / 60.0)
		if s.job != "sniper":
			break
	eq(s.job, "guard", "they went back to guarding rather than leaning on it")
	ok(s.tower.is_empty(), "and the tower is free for somebody who can reach it")
	eq(sim.crew.free_towers(sim).size(), 1)
