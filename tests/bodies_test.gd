extends "res://tests/test_case.gd"
## Bodies are solid to each other (owner, 2026-10-13: zombies walked through
## the player and bit from inside). A zombie stops at you, you stop at a
## zombie, a roll goes through, and one held off at arm's length still bites.
## Each test plants what it measures on open ground and steps the real sim.

const DT := 1.0 / 60.0

var sim: GameSim
var p: PlayerSim
var plot: Vector2


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = tile_centre(clear_plot(12))
	p.pos = plot
	p.prev_pos = plot
	p.vel = Vector2.ZERO
	p.intent.aim = plot + Vector2.RIGHT * 100.0


## A walker that stands where it is put: no wander, no chase, just a body.
func _post(at: Vector2) -> EnemySim:
	var e := sim.enemies.spawn("walker", at)
	e.speed = 0.0
	e.aggro = false
	return e


func _touching(e: EnemySim) -> float:
	return e.r + p.r


func test_a_zombie_inside_you_is_set_back_to_touching() -> void:
	var e := _post(plot + Vector2(4.0, 0.0))
	sim.tick(DT)
	near(e.pos.distance_to(p.pos), _touching(e), 0.5, "parted to the sum of the radii")
	ok(e.pos.x > p.pos.x, "on the side it was on")


func test_you_stop_at_a_zombie_instead_of_walking_through_it() -> void:
	var e := _post(plot + Vector2(60.0, 0.0))
	p.intent.mx = 1.0
	run(sim, 1.5)
	ok(p.pos.x < e.pos.x, "still on the near side of it after 1.5 s of walking east")
	near(p.pos.distance_to(e.pos), _touching(e), 1.0, "pressed against it, not inside it")
	near(e.pos.x, plot.x + 60.0, 1.0, "and it was not shoved along by you")


func test_a_roll_goes_through_the_horde() -> void:
	var e := _post(plot + Vector2(50.0, 0.0))
	p.intent.mx = 1.0
	p.intent.dash = true
	sim.tick(DT)
	gt(p.dash_t, 0.0, "the roll began")
	p.intent.dash = false
	run(sim, float(Config.DASH.time) + 0.1)
	ok(p.pos.x > e.pos.x + _touching(e) * 0.5, "came out the far side: you at %.0f, it at %.0f" % [p.pos.x, e.pos.x])


func test_a_zombie_held_off_still_bites_and_does_not_fidget() -> void:
	var e := sim.enemies.spawn("walker", plot + Vector2(120.0, 0.0), true)
	run(sim, 2.0)
	var want := _touching(e)
	# Two seconds on, it is at arm's length and stays there: the stuck
	# rescue must not read "held off" as "wedged" and sidestep every 0.7 s.
	var worst := 0.0
	for i in int(2.0 / DT):
		sim.tick(DT)
		worst = maxf(worst, e.pos.distance_to(p.pos))
	ok(worst < want + 8.0, "never further than %.1f px from touching (%.1f)" % [8.0, worst - want])
	ok(p.hp < p.max_hp, "and it reached you: hp %.0f" % p.hp)


func test_the_dead_and_the_ranges_targets_are_nothing_to_walk_into() -> void:
	var e := _post(plot + Vector2(40.0, 0.0))
	e.dead = true
	p.intent.mx = 1.0
	run(sim, 1.0)
	ok(p.pos.x > plot.x + 40.0 + _touching(e), "walked over the corpse")
	p.pos = plot
	p.prev_pos = plot
	p.vel = Vector2.ZERO
	var t := _post(plot + Vector2(40.0, 0.0))
	t.passive = true
	t.post = t.pos
	run(sim, 1.0)
	ok(p.pos.x > plot.x + 40.0 + _touching(t), "and through a target on its post")
