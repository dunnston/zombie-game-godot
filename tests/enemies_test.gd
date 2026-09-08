extends "res://tests/test_case.gd"
## Enemies: sensing, the chase, aggro expiry, the spawner and the cull.
## Every test plants what it measures on open ground and steps the real sim.

var sim: GameSim
var p: PlayerSim
var plot: Vector2


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = tile_centre(clear_plot(12))
	p.pos = plot
	p.intent.aim = plot + Vector2.RIGHT


func test_enemy_tiers_escalate() -> void:
	var E := Config.ENEMIES
	ok(E.walker.hp < E.runner.hp * 2 and E.runner.speed > E.walker.speed * 2, "a runner is fast and fragile")
	ok(E.brute.hp > E.walker.hp * 4 and E.brute.struct_mul > E.walker.struct_mul * 3, "a brute is what breaches a wall")
	ok(E.behemoth.hp > E.brute.hp * 3 and E.behemoth.get("boss", false), "the behemoth is a boss")
	ok(E.walker.threat < E.runner.threat and E.runner.threat < E.brute.threat and E.brute.threat < E.behemoth.threat)


func test_a_walker_in_sight_hunts_you_down() -> void:
	var e := sim.enemies.spawn("walker", plot + Vector2(250, 0))
	run(sim, 0.5)
	ok(e.aggro, "250px away in the open: seen")
	run(sim, 6.0)
	ok(e.pos.distance_to(p.pos) < 60.0, "closed to %.0f px" % e.pos.distance_to(p.pos))
	ok(p.hp < p.max_hp, "and bit: hp %.0f" % p.hp)
	ok(sim.stats.damage_taken > 0.0)


func test_sneaking_halves_what_they_notice() -> void:
	var e := sim.enemies.spawn("walker", plot + Vector2(250, 0))
	p.intent.sneak = true
	run(sim, 1.0)
	ok(not e.aggro, "crouched at 250px, outside a walker's halved 330 sense")
	p.intent.sneak = false
	run(sim, 0.5)
	ok(e.aggro, "standing up is being seen")


func test_aggro_expires_and_only_real_sensing_renews_it() -> void:
	var e := sim.enemies.spawn("walker", plot + Vector2(200, 0))
	run(sim, 0.5)
	ok(e.aggro)
	# Whisked far away: the walker should investigate for a few seconds,
	# then forget. Once-noticed must not mean hunted forever.
	p.pos = plot + Vector2(0, 2000)
	p.intent.aim = p.pos + Vector2.RIGHT
	run(sim, 1.0)
	ok(e.aggro, "still alert for a moment after losing you")
	run(sim, 5.0)
	ok(not e.aggro, "gave up the hunt")


func test_an_unaggroed_walker_shambles_at_half_pace() -> void:
	# Nobody to see; four seconds of wandering must not cover what four
	# seconds of chasing would.
	p.pos = plot + Vector2(0, 1500)
	p.intent.aim = p.pos + Vector2.RIGHT
	var e := sim.enemies.spawn("walker", plot)
	run(sim, 4.0)
	var d := e.pos.distance_to(plot)
	ok(d < 60.0 * 4.0 * 0.7, "wandered %.0f px in 4s" % d)


func test_the_spawner_keeps_a_standing_population() -> void:
	# Tier 1 is deliberately thin: four near a stationary player.
	sim.view_radius = 600.0
	run(sim, 20.0)
	var near := sim.enemies.count_near(p.pos, Config.SPAWN.count_radius)
	var total := sim.enemies.alive_count()
	print("spawner: %d within %.0f px, %d alive after 20s in tier %d" % [near, Config.SPAWN.count_radius, total, sim.world.danger_at_px(p.pos.x, p.pos.y)])
	ok(near >= 1, "something arrived")
	ok(total <= Config.SPAWN.density[1] + 1, "a still player in tier 1 should not accumulate a crowd: %d" % total)
	for e in sim.enemies.list:
		ok(e.pos.distance_to(p.pos) >= 700.0 or e.aggro, "spawned off screen (%.0f px)" % e.pos.distance_to(p.pos))


func test_the_spawner_respects_a_lull() -> void:
	sim.view_radius = 600.0
	for i in range(6):
		sim.quiet.add_quiet(p.pos.x, p.pos.y)
	run(sim, 10.0)
	eq(sim.enemies.alive_count(), 0, "nothing walks into ground you just cleared")


func test_far_enemies_are_culled() -> void:
	sim.enemies.spawn("walker", plot + Vector2(3000, 0))
	var kept := sim.enemies.spawn("walker", plot + Vector2(400, 0))
	run(sim, 1.0)
	var far := 0
	for e in sim.enemies.list:
		if e.pos.distance_to(plot) > Config.SPAWN.cull:
			far += 1
	eq(far, 0, "nothing further than the cull radius survives a spawn tick")
	ok(sim.enemies.list.has(kept), "the near one stays")


func test_a_horde_spreads_out_rather_than_stacking() -> void:
	# Eight dropped on one spot with nobody to chase: separation alone has
	# to make a crowd of them.
	p.pos = plot + Vector2(0, 1500)
	p.intent.aim = p.pos + Vector2.RIGHT
	for i in range(8):
		sim.enemies.spawn("walker", plot)
	run(sim, 2.0)
	var overlapping := 0
	for a in sim.enemies.list:
		for b in sim.enemies.list:
			if a != b and a.pos.distance_to(b.pos) < (a.r + b.r) * 0.6:
				overlapping += 1
	eq(overlapping, 0, "pairs sitting inside each other")


# ------------------------------------------------ the Codex review, PR #6 --

func test_a_wall_between_you_ends_the_chase() -> void:
	# Inside a walker's 330px sense radius, outside the 120px it notices
	# without looking, and with a wall across the line. The refresh and the
	# expiry have to agree about what "senses" means, or hiding does nothing.
	var plot := clear_plot(10)
	var p := sim.players[0]
	p.pos = tile_centre(plot)
	for id in ["wood"]:
		p.bag.add(id, 400)
	p.carry_cap = 100000.0
	for dy in range(-3, 4):
		sim.structs.place(sim, "woodWall", plot.x + 3, plot.y + dy, p)

	var e := sim.enemies.spawn("walker", tile_centre(Vector2i(plot.x + 6, plot.y)))
	e.aggro = true
	e.alert_t = 0.5                      # it saw you a moment ago
	var d := e.pos.distance_to(p.pos)
	ok(d > 120.0 and d < e.sense, "%0.f px away: in range, out of reach" % d)
	ok(not sim.world.has_line_of_sight(e.pos, p.pos, 12.0, sim.structs), "and it cannot see you")
	run(sim, 2.0)
	ok(not e.aggro, "it gave up rather than tracking you through the wall")


func test_without_the_wall_it_keeps_coming() -> void:
	var plot := clear_plot(10)
	var p := sim.players[0]
	p.pos = tile_centre(plot)
	var e := sim.enemies.spawn("walker", tile_centre(Vector2i(plot.x + 6, plot.y)))
	e.aggro = true
	e.alert_t = 0.5
	run(sim, 2.0)
	ok(e.aggro, "in the open it can still see you, so the chase stands")


func test_nothing_spawns_inside_a_wall() -> void:
	# Every ambient spawn, over a lot of them, has room for its own body.
	var p := sim.players[0]
	p.pos = tile_centre(clear_plot(4))
	sim.view_radius = 600.0
	var embedded := 0
	for i in range(400):
		sim.enemies.spawn_accum = 999.0
		sim.enemies.tick_spawning(sim, 1.0 / 60.0)
		for e in sim.enemies.list:
			if sim.world.circle_hits_solid(e.pos.x, e.pos.y, e.r, sim.structs):
				embedded += 1
		sim.enemies.list.clear()
	eq(embedded, 0, "%d spawns started inside geometry" % embedded)
