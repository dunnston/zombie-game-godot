extends "res://tests/test_case.gd"
## The quiet field: kills buy local, temporary calm; the spawner reads it.

const Q := Config.QUIET


func test_a_kill_quietens_where_it_fell() -> void:
	var q := QuietField.new()
	var at := Vector2(4000, 4000)
	q.add_quiet(at.x, at.y)
	ok(q.quiet_at(at.x, at.y) > 0.5, "quiet at the kill: %.2f" % q.quiet_at(at.x, at.y))
	eq(q.quiet_at(at.x + 2000, at.y), 0.0, "and none two thousand pixels away")


func test_the_read_is_smooth_across_cells() -> void:
	# Reading the containing cell made the same kills worth forty seconds
	# of calm or none depending on where in a 256px square you stood.
	var q := QuietField.new()
	q.add_quiet(4000, 4000, 3.0)
	var worst := 0.0
	for x in range(3600, 4400, 8):
		var a := q.quiet_at(x, 4000)
		var b := q.quiet_at(x + 8, 4000)
		worst = maxf(worst, absf(a - b))
	ok(worst < 0.12, "largest jump over 8px: %.3f" % worst)


func test_five_kills_buy_a_lull_and_two_do_not() -> void:
	# Calibrated in the prototype: about one approaching group buys the lull,
	# wherever in the cell it fell.
	for off: Vector2 in [Vector2.ZERO, Vector2(128, 128), Vector2(30, 200), Vector2(255, 1)]:
		var q := QuietField.new()
		var at := Vector2(4096, 4096) + off
		for i in range(2):
			q.add_quiet(at.x, at.y)
		ok(not q.suppressed(at.x, at.y), "two kills at %s read %.2f: no lull yet" % [off, q.total_quiet_at(at.x, at.y)])
		for i in range(3):
			q.add_quiet(at.x, at.y)
		ok(q.suppressed(at.x, at.y), "five kills at %s read %.2f: a lull" % [off, q.total_quiet_at(at.x, at.y)])


func test_quiet_thins_the_crowd_and_never_empties_it() -> void:
	var q := QuietField.new()
	near(q.density_mul(1000, 1000), 1.0, 1e-6, "untouched ground wants the full crowd")
	for i in range(40):
		q.add_quiet(4096, 4096)
	near(q.density_mul(4096, 4096), Q.floor, 1e-6, "a killing field still gets %d%%" % int(Q.floor * 100))


func test_quiet_decays_in_a_few_minutes() -> void:
	var q := QuietField.new()
	for i in range(20):
		q.add_quiet(4096, 4096)
	ok(q.suppressed(4096, 4096))
	for i in range(int(120 / (1.0 / 60.0))):
		q.tick(1.0 / 60.0)
	ok(q.quiet_at(4096, 4096) < Q.max - 2.0, "two minutes in: %.2f" % q.quiet_at(4096, 4096))
	for i in range(int(180 / (1.0 / 60.0))):
		q.tick(1.0 / 60.0)
	near(q.quiet_at(4096, 4096), 0.0, 1e-4, "five minutes bleeds a full ceiling off")


func test_kills_feed_the_field_and_raid_kills_do_not() -> void:
	var sim := new_sim()
	var at := tile_centre(clear_plot(4))
	var e := sim.enemies.spawn("walker", at)
	Damage.damage_enemy(sim, e, 1000.0, at, 0.0, false, sim.players[0])
	ok(e.dead)
	ok(sim.quiet.quiet_at(at.x, at.y) > 0.5, "an ambient kill deposits quiet")
	var before := sim.quiet.quiet_at(at.x, at.y)
	var r := sim.enemies.spawn("walker", at, true, true)
	Damage.damage_enemy(sim, r, 1000.0, at, 0.0, false, sim.players[0])
	near(sim.quiet.quiet_at(at.x, at.y), before, 1e-6, "a raider's death buys nothing")
	eq(sim.stats.kills, 2)
