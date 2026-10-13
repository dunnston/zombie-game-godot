extends "res://tests/test_case.gd"
## The meal (`Config.FEED`): a zombie in reach of a player who just died
## stops over the body for a while, facing it, and a hit breaks it off.
## Humans, bosses and anything on the ground do not stop.

var sim: GameSim
var p: PlayerSim
var plot: Vector2


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = tile_centre(clear_plot(12))
	p.pos = plot
	p.prev_pos = plot
	p.intent.aim = plot + Vector2.RIGHT


func _plant(type: String, offset: Vector2) -> EnemySim:
	var e := sim.enemies.spawn(type, plot + offset, true)
	e.alert_t = 999.0
	sim.tick(1.0 / 60.0)
	return e


func test_a_zombie_in_reach_stops_to_eat_and_one_further_off_does_not() -> void:
	var near_ := _plant("walker", Vector2(30, 0))
	var far := _plant("walker", Vector2(300, 0))
	Damage.kill_player(sim, p)
	# Not up again before the meal is over: a respawn elsewhere leaves the
	# walker alone on the street, where the spawner culls it.
	p.respawn_t = 60.0
	near(near_.feed_t, float(Config.FEED.time), 1e-6, "the one beside you feeds")
	eq(far.feed_t, 0.0, "the one down the street does not")
	var at := near_.pos
	run(sim, 1.0)
	ok(near_.pos.distance_to(at) < 4.0, "and goes nowhere while it does (moved %.1f px)" % near_.pos.distance_to(at))
	near(near_.feed_t, float(Config.FEED.time) - 1.0, 0.05, "the clock runs")
	ok(absf(angle_difference(near_.angle, (plot - near_.pos).angle())) < 0.05, "facing the body")
	run(sim, float(Config.FEED.time))
	eq(near_.feed_t, 0.0, "then the meal is over")


func test_a_hit_breaks_the_meal() -> void:
	var w := _plant("walker", Vector2(30, 0))
	Damage.kill_player(sim, p)
	gt(w.feed_t, 0.0)
	Damage.damage_enemy(sim, w, 1.0, plot)
	eq(w.feed_t, 0.0, "hit, it looks up")


func test_humans_bosses_and_crawlers_do_not_stop() -> void:
	var looter := _plant("looter", Vector2(30, 0))
	var coach := _plant("coach", Vector2(-30, 0))
	var crawler := _plant("walker", Vector2(0, 30))
	Damage.knock_down(crawler, 60.0)
	Damage.kill_player(sim, p)
	eq(looter.feed_t, 0.0, "a looter is not hungry")
	eq(coach.feed_t, 0.0, "a boss has a script")
	eq(crawler.feed_t, 0.0, "a crawler cannot bend down")


func test_the_meal_is_on_the_wire() -> void:
	var w := _plant("walker", Vector2(30, 0))
	var rec := NetProtocol.pack_enemies(sim, plot, 500.0)
	var i := 0
	var found := false
	while i < rec.size():
		if int(rec[i]) == w.id:
			found = int(rec[i + 7]) & NetProtocol.EF_FEED != 0
		i += NetProtocol.EN_STRIDE
	ok(not found, "upright before")
	Damage.kill_player(sim, p)
	rec = NetProtocol.pack_enemies(sim, plot, 500.0)
	i = 0
	while i < rec.size():
		if int(rec[i]) == w.id:
			found = int(rec[i + 7]) & NetProtocol.EF_FEED != 0
		i += NetProtocol.EN_STRIDE
	ok(found, "bent over after")
