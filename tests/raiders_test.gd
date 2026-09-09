extends "res://tests/test_case.gd"
## The living: a faction that comes for a base whose owner has gone too far.
##
## They run on the same AI, the same raid and the same loot code everything
## else does — the point of these tests is the three things that are actually
## new, and the one rule that must never bend: **killing people is never a way
## to hold the Mutation meter down.**

var sim: GameSim
var p: PlayerSim


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]


# ------------------------------------------------------------------ tables --

func test_the_living_are_marked_and_carry_no_brains() -> void:
	var humans := 0
	for id in Config.ENEMIES:
		if not Config.ENEMIES[id].get("human", false):
			continue
		humans += 1
		var d: Dictionary = Config.ENEMIES[id]
		ok(not Config.BRAIN_DROPS.has(id), "%s is a person and drops brain matter" % id)
		has(Config.LOOT, String(d.get("loot_table", "")), "%s has no body loot" % id)
		if d.has("gun"):
			var g: Dictionary = d.gun
			gt(float(g.range), float(d.atk_range), "%s's gun does not outrange its fists" % id)
			gt(float(g.range), float(g.standoff), "%s stands off further than it can shoot" % id)
			gt(float(g.dmg), 0.0, id)
	gt(humans, 2, "a faction of one is a reskin")


func test_a_human_raid_is_smaller_than_a_horde() -> void:
	# Being outnumbered by things that shoot back is not the fantasy.
	for spec in Config.HUMAN_RAIDS:
		var total := 0
		for w in range(int(spec.waves)):
			total += int(spec.base) + int(spec.growth) * w
		ok(total <= 20, "%s fields %d people" % [spec.name, total])
		ok(not spec.reward.is_empty(), "%s pays nothing" % spec.name)
		for t in spec.mix:
			has(Config.ENEMIES, t, String(spec.name))
			ok(Config.ENEMIES[t].get("human", false), "%s fields %s, which is not a person" % [spec.name, t])


# ------------------------------------------------------------ who arrives --

func test_the_living_come_for_what_you_are_becoming() -> void:
	# HUMAN: never. This is the rule the whole faction hangs off — walk around
	# as a person and the only thing that raids you is the horde.
	eq(p.mut_band, 0)
	for i in range(200):
		ok(not Raid.humans_come_for(sim), "a human raid was rolled against a human")

	# FERAL: often, but never always. Both branches have to be reachable or
	# the horde stops existing at the top band.
	Mutation.add(sim, p, 80.0)
	var came := 0
	for i in range(400):
		if Raid.humans_come_for(sim):
			came += 1
	gt(came, 40, "the living never came for a Feral player in 400 rolls")
	ok(came < 400, "the horde stopped existing")


func test_the_two_raid_tracks_count_separately() -> void:
	sim.raids_done = 3
	var horde := Raid.start(sim, false)
	eq(String(horde.spec.name), String(Config.raid_spec(3).name))
	horde.force_end(sim)
	eq(sim.raids_done, 4, "the horde track did not advance")
	eq(sim.human_raids_done, 0, "a horde advanced the human track")

	var crew := Raid.start(sim, true)
	ok(crew.human)
	# Four hordes deep, the first human raid is still the first human raid.
	eq(String(crew.spec.name), String(Config.HUMAN_RAIDS[0].name))
	crew.force_end(sim)
	eq(sim.human_raids_done, 1)
	eq(sim.raids_done, 4, "a human raid advanced the horde track")


func test_a_human_raid_is_scaled_by_human_raids() -> void:
	# `index` is two things at once: which spec to field, and how much health
	# every raider gets (`hp_per_index`). Read off the wrong counter, a crew
	# arrives tougher for hordes it had nothing to do with, and never gets
	# tougher for beating *you*. (Codex review, PR #21.)
	sim.raids_done = 6
	var first := Raid.start(sim, true)
	eq(first.index, 0, "the living arrived scaled by six hordes they were not at")
	first.force_end(sim)
	var second := Raid.start(sim, true)
	eq(second.index, 1, "surviving a human raid did not make the next one harder")
	second.force_end(sim)
	# And the horde track is still its own.
	eq(Raid.start(sim, false).index, 6)


func test_a_human_raid_fields_people() -> void:
	Mutation.add(sim, p, 80.0)
	var raid := Raid.start(sim, true)
	run(sim, Config.RAID.warning_time + 6.0)
	var people := 0
	var dead_things := 0
	for e in sim.enemies.list:
		if e.raid:
			if e.def.get("human", false):
				people += 1
			else:
				dead_things += 1
	gt(people, 0, "a raiding party arrived with nobody in it")
	eq(dead_things, 0, "the horde came along to a human raid")


# --------------------------------------------------------------- shooting --

func test_they_shoot_back() -> void:
	var e := sim.enemies.spawn("raider", p.pos + Vector2(260, 0), true)
	var hp := p.hp
	run(sim, 4.0)
	ok(p.hp < hp, "four seconds in a raider's line of fire cost nothing")


func test_their_rounds_hit_people_and_not_the_horde() -> void:
	var walker := sim.enemies.spawn("walker", p.pos + Vector2(120, 0))
	walker.hp = 999.0                       # so a stray round would show
	var before := walker.hp
	var e := sim.enemies.spawn("raider", p.pos + Vector2(300, 0), true)
	p.god_mode = true                       # this is about the walker
	run(sim, 5.0)
	near(walker.hp, before, 0.001, "a raider shot the horde — there is no enemy-vs-enemy targeting")


func test_a_rifleman_keeps_its_distance() -> void:
	var e := sim.enemies.spawn("raider", p.pos + Vector2(320, 0), true)
	p.god_mode = true
	run(sim, 6.0)
	var d := e.pos.distance_to(p.pos)
	var standoff := float(Config.ENEMIES.raider.gun.standoff)
	gt(d, standoff * 0.5, "the Raider closed to %.0f — it is fighting like a walker" % d)
	ok(d < float(Config.ENEMIES.raider.gun.range), "it wandered out of its own range")


func test_gunfire_brings_the_dead() -> void:
	# The one honest piece of three-way fighting: their rifles are as loud as
	# yours, and the horde does not care who fired.
	var walker := sim.enemies.spawn("walker", p.pos + Vector2(0, 360))
	walker.aggro = false
	walker.alert_t = 0.0
	sim.enemies.spawn("raider", p.pos + Vector2(300, 0), true)
	run(sim, 4.0)
	ok(walker.has_noise or walker.alert_t > 0.0, "a firefight next door went unheard")


func test_the_living_cannot_infect_you() -> void:
	# The line the whole faction rests on. A Looter punching you is a punch:
	# it hurts, and it is not a bite. The melee landing path is shared with
	# the dead, so this is one flag away from being wrong in a way nobody
	# would notice until the meter moved. (Codex review, PR #21.)
	var e := sim.enemies.spawn("looter", p.pos + Vector2(20, 0), true)
	var before := p.mutation
	for i in range(200):
		p.invuln = 0.0
		Damage.damage_player(sim, p, e.dmg, e.pos, e.def.name, not e.def.get("human", false))
		p.hp = p.max_hp
	near(p.mutation, before, 0.001, "a Looter's fists spread the infection")

	# And through the real AI, standing on top of the player for long enough
	# to land plenty of them.
	p.mutation = 0.0
	p.mut_band = 0
	p.god_mode = false
	var start := p.mutation
	for i in range(600):
		e.pos = p.pos + Vector2(16, 0)
		p.hp = p.max_hp
		sim.tick(1.0 / 60.0)
	# The ambient climb is real but tiny; a bite would be twelve points.
	ok(p.mutation - start < 5.0, "ten seconds of being punched moved the meter %.1f" % (p.mutation - start))


func test_their_guns_are_heard() -> void:
	# Every pellet carried an empty weapon id, which `SfxView` reads as
	# "pellet two through eight" and drops — so raiders shot at you in
	# complete silence. (Codex review, PR #21.)
	# The bank has to exist or `SfxView` falls back to the pistol for every
	# cue it cannot find — which would make this test pass on a bug.
	Sfx.build()
	var sfx := SfxView.new(sim)
	sfx.player = p
	sim.enemies.spawn("raider", p.pos + Vector2(280, 0), true)
	run(sim, 2.5)
	var heard := ""
	var pellets := 0
	for ev in sim.events:
		if String(ev.t) != "shot":
			continue
		var cue := sfx.on_event(ev)
		if cue.is_empty():
			pellets += 1
		else:
			heard = cue
	ok(not heard.is_empty(), "a Raider fired and nothing made a sound")
	eq(heard, "rifle", "the Raider's rifle sounds like a %s" % heard)

	# A shotgun is one bang, not five: only the first pellet carries the id.
	sim.events.clear()
	var sim2 := new_sim()
	sim2.players[0].god_mode = true
	sim2.enemies.spawn("enforcer", sim2.players[0].pos + Vector2(150, 0), true)
	run(sim2, 2.5)
	var bangs := 0
	var quiet := 0
	var sfx2 := SfxView.new(sim2)
	sfx2.player = sim2.players[0]
	for ev in sim2.events:
		if String(ev.t) != "shot":
			continue
		if sfx2.on_event(ev).is_empty():
			quiet += 1
		else:
			bangs += 1
	gt(bangs, 0, "the Enforcer's shotgun made no noise at all")
	gt(quiet, bangs, "every pellet of the shell made its own bang")


# --------------------------------------------------------------- stealing --

func test_a_looter_empties_what_it_can_reach_and_runs() -> void:
	var tile := clear_plot(0)
	p.bag = Slots.new(60)
	p.carry_cap = 100000.0
	for id in ["wood", "scrap"]:
		p.bag.add(id, 400)
	p.pos = tile_centre(tile) + Vector2(0, Config.TILE * 2)
	sim.structs.place(sim, "stash", tile.x, tile.y, p)
	var box := sim.structs.at_tile(tile.x, tile.y)
	ok(not box.is_empty(), "the test needs a stash to rob")
	box.store.add("scrap", 40)
	box.store.add("ammoP", 30)
	var before: int = box.store.used()
	gt(before, 0)

	var e := sim.enemies.spawn("looter", box.pos + Vector2(20, 0), true)
	run(sim, 1.0)
	ok(box.store.used() < before, "the Looter stood in the stash and took nothing")
	ok(not e.cargo.is_empty(), "it took things that went nowhere")
	gt(e.flee_t, 0.0, "it robbed you and stayed for the fight")


func test_putting_a_looter_down_gets_it_back() -> void:
	var e := sim.enemies.spawn("looter", p.pos + Vector2(60, 0), true)
	e.cargo = {"scrap": 12}
	e.flee_t = 5.0
	var piles := sim.pickups.size()
	Damage.kill_enemy(sim, e, p)
	gt(sim.pickups.size(), piles, "the Looter died with your scrap and it vanished")
	var got := 0
	for it in sim.pickups:
		if String(it.id) == "scrap":
			got += int(it.n)
	eq(got, 12, "what came back is not what was taken")


func test_a_looter_that_gets_away_takes_it_with_it() -> void:
	var e := sim.enemies.spawn("looter", p.pos + Vector2(200, 0), true)
	e.cargo = {"scrap": 12}
	e.flee_t = 0.6
	var piles := sim.pickups.size()
	run(sim, 1.2)
	ok(e.dead, "it never got away")
	eq(sim.pickups.size(), piles, "it got away and dropped the loot anyway")


func test_a_body_is_worth_searching() -> void:
	var piles := sim.pickups.size()
	for i in range(20):
		Damage.kill_enemy(sim, sim.enemies.spawn("raider", p.pos + Vector2(300, 0)), p)
	gt(sim.pickups.size(), piles + 10, "twenty raiders left almost nothing behind")
	for it in sim.pickups:
		ok(not Mutation.is_suppressant(String(it.id)), "a person dropped brain matter")


# ------------------------------------------------------------- the living --

func test_nobody_will_go_anywhere_with_something_feral() -> void:
	eq(sim.crew.recruit_refusal(sim, p), sim.crew.recruit_refusal(sim),
		"a HUMAN player is refused for a different reason to the roster's own")
	Mutation.add(sim, p, 80.0)
	var why := sim.crew.recruit_refusal(sim, p)
	ok(why.contains("back away"), "a Feral player was offered a recruit: %s" % why)
	# And it is the *first* answer: no number of Bunks argues with it.
	var tile := clear_plot(1)
	sim.structs.place(sim, "bunk", tile.x, tile.y, p)
	ok(sim.crew.recruit_refusal(sim, p).contains("back away"), "a Bunk talked them round")
