extends "res://tests/test_case.gd"
## Threat and raids, and the harness that plays one through.

var sim: GameSim
var p: PlayerSim
var plot: Vector2


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = tile_centre(clear_plot(12))
	p.pos = plot
	p.intent.aim = plot + Vector2.RIGHT
	sim.give_test_kit(p)
	sim.view_radius = 600.0


func test_raids_escalate_and_keep_scaling_past_the_list() -> void:
	var R := Config.RAIDS
	for i in range(1, R.size()):
		ok(R[i].base > R[i - 1].base and R[i].xp > R[i - 1].xp, "raid %d is bigger than raid %d" % [i + 1, i])
	var s := Config.raid_spec(5)
	eq(s.name, "BEHEMOTH SIEGE +1")
	eq(s.base, 27)
	eq(s.growth, 8)
	eq(s.xp, roundi(800 * 1.35))
	eq(s.reward.scrap, roundi(110 * 1.3))
	eq(Config.raid_spec(1).name, "RUNNING HORDE", "the index is zero-based")
	# The anti-stall warp has to reach a raider wedged where it spawned, and
	# must never reach into a fight you are watching.
	var C := Config.RAID
	ok(C.stall_radius < C.ring_min, "a raider stuck at spawn is still rescued")
	ok(C.stall_radius > Config.CAMERA.view_height / 2.0, "nothing on your screen is warped away")


func test_threat_thresholds_are_ordered_and_reachable() -> void:
	var T := Config.THREAT
	ok(T.warn_at[0] < T.warn_at[1] and T.warn_at[1] < T.warn_at[2] and T.warn_at[2] < T.max)
	ok(T.post_raid_reset < T.warn_at[0])
	# A scavenging run must out-pace decay or the meter never moves.
	ok(T.per_loot > T.decay_per_sec * 2.0)


func test_threat_gains_decays_and_pins_at_full() -> void:
	sim.threat.add(sim, 30.0, p)
	near(sim.threat.value, 30.0, 1e-6)
	eq(sim.threat.tier, 0)
	run(sim, 10.0)
	near(sim.threat.value, 30.0 - 1.2, 0.05, "decays 0.12/s")
	sim.threat.add(sim, 60.0, p)
	eq(sim.threat.label(), "HIGH")
	ok(not events_of(sim, "notify").is_empty(), "and warns")
	sim.threat.add(sim, 500.0, p)
	near(sim.threat.value, 100.0, 1e-6, "capped")
	# Pinned: it must not decay below the threshold before the raid fires.
	sim.tick(1.0 / 60.0)
	ok(sim.raid != null, "a raid starts at full Threat")
	eq(sim.raid.phase, "warning")


func test_a_raid_warns_then_sends_waves_at_you() -> void:
	sim.threat.value = 100.0
	sim.tick(1.0 / 60.0)
	ok(sim.raid != null)
	var warn := events_of(sim, "notify")
	ok(warn.size() >= 2 and warn[0].text.contains("INCOMING"), warn[0].text)
	run(sim, Config.RAID.warning_time + 0.5)
	eq(sim.raid.phase, "active")
	eq(sim.raid.wave, 1)
	run(sim, 3.0)
	var raiders := 0
	for e in sim.enemies.list:
		if e.raid:
			raiders += 1
			ok(e.aggro, "raiders arrive hunting")
			ok(e.pos.distance_to(plot) < Config.RAID.ring_max + 200.0, "spawned on the ring")
	eq(raiders, Config.RAIDS[0].base, "wave one of the first raid is eight walkers")
	eq(sim.raid.total, 8 + 11, "two waves, 8 then 11")
	ok(sim.threat.value >= 100.0, "Threat holds during the raid")


func test_an_ignored_horde_loses_interest() -> void:
	# God mode and no fighting: nothing changes, so the horde breaks off,
	# pays nothing, and Threat resets. Hiding must not beat defending.
	p.god_mode = true
	sim.threat.value = 100.0
	run(sim, Config.RAID.warning_time + 1.0)
	var t0 := sim.time
	for i in range(120 * 60):
		sim.tick(1.0 / 60.0)
		if sim.raid == null:
			break
	ok(sim.raid == null, "the raid ended")
	ok(sim.time - t0 < 60.0, "in %.0fs, not the 300s backstop" % (sim.time - t0))
	eq(sim.raids_done, 1)
	near(sim.threat.value, Config.THREAT.post_raid_reset, 1e-6)
	eq(p.count_res("scrap"), 0, "no salvage for hiding")
	eq(p.xp, 0, "and no xp either: the payout is the share you put down")
	var ends := events_of(sim, "raid_end")
	ok(ends.size() == 1 and not ends[0].repelled and ends[0].share == 0.0)


func test_a_raid_without_a_base_follows_you() -> void:
	# Until Phase 3 the raid is aimed at a person. The AI chases the live
	# player, so the centre the anti-stall check measures against has to be
	# the same one — otherwise pursuit reads as a stall.
	sim.threat.value = 100.0
	run(sim, Config.RAID.warning_time + 0.5)
	var r := sim.raid
	ok(r != null and not r.has_base and r.phase == "active")
	near(r.centre.distance_to(p.pos), 0.0, 1.0, "it starts on you")
	p.pos = plot + Vector2(600, 0)
	run(sim, 0.2)
	near(r.centre.distance_to(p.pos), 0.0, 5.0, "and it comes with you")


func test_the_raid_xp_bonus_is_only_for_raiders() -> void:
	sim.threat.value = 100.0
	run(sim, Config.RAID.warning_time + 0.5)
	ok(sim.raid != null and sim.raid.phase == "active")
	var walker: int = Config.ENEMIES.walker.xp

	var ambient := sim.enemies.spawn("walker", plot + Vector2(200, 0))
	var before := p.xp
	Damage.kill_enemy(sim, ambient, p)
	eq(p.xp - before, walker, "an ambient kill mid-raid is worth what it always was")
	eq(sim.raid.killed, 0, "and is not raid progress")

	var raider := sim.enemies.spawn("walker", plot + Vector2(200, 0), true, true)
	before = p.xp
	Damage.kill_enemy(sim, raider, p)
	eq(p.xp - before, roundi(walker * Config.RAID.kill_xp_mul), "a raider pays the bonus")
	eq(sim.raid.killed, 1)


func test_harness_the_first_raid_is_repelled_by_a_rifle() -> void:
	var r := play_raid(sim, p, 0)
	print("raid harness [0 SCATTERED HORDE]: %.0fs, %d kills, repelled=%s, scrap +%d" % [r.seconds, r.kills, r.repelled, r.reward])
	ok(r.done, "the raid completed")
	ok(r.repelled, "and was repelled")
	eq(r.kills, 8 + 11, "every raider died")
	ok(r.seconds < 120.0, "in %.0fs" % r.seconds)
	eq(r.reward, 30, "the salvage was paid")


