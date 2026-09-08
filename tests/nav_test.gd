extends "res://tests/test_case.gd"
## Navigation: the flow field, and what it buys over straight steering.


func test_the_field_builds_fast_enough_to_rebuild_as_you_walk() -> void:
	var nf := NavField.new()
	nf.build(world(), Vector2i(160, 160), Config.NAV.radius_tiles)
	print("nav: %dx%d field built in %.1f ms" % [nf.size, nf.size, nf.build_ms])
	ok(nf.build_ms < 12.0, "built in %.1f ms" % nf.build_ms)
	eq(nf.dist_at_tile(160, 160), 0, "the target is at distance zero")
	eq(nf.dist_at_tile(150, 150), -1, "a wall tile is unreachable")
	ok(nf.dist_at_tile(125, 160) >= 35, "the highway west is reachable: %d" % nf.dist_at_tile(125, 160))
	eq(nf.dist_at_tile(0, 0), -1, "outside the window")


func test_the_field_never_cuts_a_corner() -> void:
	# Two blocked tiles touching at a corner must not be squeezed between.
	var nf := NavField.new()
	nf.build(world(), Vector2i(160, 160), Config.NAV.radius_tiles)
	var W := Config.WORLD_TILES
	var w := world()
	var bad := 0
	for ty in range(nf.y0 + 2, nf.y0 + nf.size - 2):
		for tx in range(nf.x0 + 2, nf.x0 + nf.size - 2):
			if nf.dist_at_tile(tx, ty) <= 0:
				continue
			var d := nf.step_dir(Vector2(tx * 32 + 16, ty * 32 + 16))
			if d == Vector2.ZERO:
				continue
			var sx := signi(roundi(d.x))
			var sy := signi(roundi(d.y))
			if sx != 0 and sy != 0:
				if w.blocked[ty * W + tx + sx] or w.blocked[(ty + sy) * W + tx]:
					bad += 1
	eq(bad, 0, "diagonal steps that clip a blocked tile")


## The camp shack: the player inside, a walker outside with a wall between.
## With the field the walker finds the door; steering straight, it presses
## on the wall. Measured both ways so the assertion means something.
func _shack_chase(nav: bool) -> Dictionary:
	var sim := new_sim()
	sim.nav_enabled = nav
	var p := sim.players[0]
	# The camp shack floor (see world_test landmarks); its door is random.
	p.pos = tile_centre(Vector2i(154, 153))
	p.intent.aim = p.pos + Vector2.RIGHT
	p.god_mode = true
	# Outside, the far side of the shack from the door, whichever wall that
	# is: try each side and keep the first that is open ground.
	var e: EnemySim = null
	for off: Vector2i in [Vector2i(-4, 0), Vector2i(4, 0), Vector2i(0, -4), Vector2i(0, 4)]:
		var t := Vector2i(154, 153) + off
		if not sim.world.is_blocked_tile(t.x, t.y) and not sim.world.has_line_of_sight(tile_centre(t), p.pos):
			e = sim.enemies.spawn("walker", tile_centre(t), true)
			break
	if e == null:
		return {}
	e.alert_t = 999.0
	var start := e.pos.distance_to(p.pos)
	var best := start
	var trace := PackedStringArray()
	for i in range(20 * 60):
		sim.tick(1.0 / 60.0)
		best = minf(best, e.pos.distance_to(p.pos))
		if i % 60 == 0:
			var nf := sim.nav_for(p)
			var fd := nf.dist_at_tile(floori(e.pos.x / 32), floori(e.pos.y / 32)) if nf != null else -9
			trace.append("%.0f@(%d,%d)f%d" % [e.pos.distance_to(p.pos), int(e.pos.x / 32), int(e.pos.y / 32), fd])
		if best < 48.0:
			break
	print("nav trace (%s): %s" % ["field" if nav else "straight", " ".join(trace)])
	return {"start": start, "best": best, "t": sim.time, "hits": sim.stats.damage_taken}


func test_a_walker_finds_the_door() -> void:
	var with := _shack_chase(true)
	ok(not with.is_empty(), "found a wall of the shack to stand behind")
	if with.is_empty():
		return
	var without := _shack_chase(false)
	print("nav: with the field the walker closed from %.0f to %.0f px in %.1fs; straight steering got to %.0f px" % [with.start, with.best, with.t, without.best])
	ok(with.best < 48.0, "with the field it reached the player (%.0f px)" % with.best)
	ok(with.t < 20.0, "in %.1fs" % with.t)
	ok(without.best > with.best, "straight steering did worse (%.0f px)" % without.best)


func test_the_field_follows_the_player() -> void:
	var sim := new_sim()
	var p := sim.players[0]
	p.pos = tile_centre(Vector2i(160, 160))
	var a := sim.nav_for(p)
	eq(a.target, Vector2i(160, 160))
	p.pos = tile_centre(Vector2i(161, 160))
	ok(sim.nav_for(p) == a, "one tile over is close enough for a moment")
	p.pos = tile_centre(Vector2i(163, 160))
	var b := sim.nav_for(p)
	eq(b.target, Vector2i(163, 160), "three tiles over rebuilds")
	sim.world_version += 1
	var c := sim.nav_for(p)
	eq(c.version, sim.world_version, "a changed world rebuilds")
