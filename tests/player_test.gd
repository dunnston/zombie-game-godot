extends "res://tests/test_case.gd"
## Movement, collision and stamina, driven through Intent exactly as the
## game drives them.

const DT := 1.0 / 60.0

var sim: GameSim


func before_each() -> void:
	sim = new_sim()


func _player_at_tile(tx: int, ty: int) -> PlayerSim:
	var p := sim.players[0]
	p.pos = Vector2(tx * 32 + 16, ty * 32 + 16)
	p.intent.aim = p.pos + Vector2.RIGHT
	return p


func _run(p: PlayerSim, seconds: float) -> void:
	for i in range(int(seconds / DT)):
		p.tick(sim, DT)


## A wall tile with a clear run of open ground to its left, so a walk east
## must end pressed against it. Found rather than hard-coded, because door
## positions are random.
func _wall_with_open_west() -> Vector2i:
	var w := world()
	for y in range(100, 220):
		for x in range(100, 220):
			if w.tile(x, y) != Config.T.WALL:
				continue
			var clear := true
			for dx in range(1, 6):
				if w.blocked[y * Config.WORLD_TILES + x - dx]:
					clear = false
					break
			if clear:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_walks_at_speed_in_the_open() -> void:
	# A tilled field: walkable, and nothing grows on it.
	var p := _player_at_tile(6, 133)
	p.intent.mx = 1.0
	_run(p, 1.0)
	var dx := p.pos.x - (6 * 32 + 16)
	ok(dx > 150.0 and dx < 176.0, "walked %.1f px in a second" % dx)
	ok(absf(p.pos.y - (133 * 32 + 16)) < 0.01, "drifted vertically")


func test_sprint_is_faster() -> void:
	var p := _player_at_tile(6, 133)
	p.intent.mx = 1.0
	p.intent.sprint = true
	_run(p, 1.0)
	var dx := p.pos.x - (6 * 32 + 16)
	ok(dx > 240.0, "sprinted %.1f px in a second" % dx)


func test_stops_at_a_wall() -> void:
	var wall := _wall_with_open_west()
	ok(wall.x >= 0, "no wall with open ground west of it found")
	var p := _player_at_tile(wall.x - 4, wall.y)
	p.intent.mx = 1.0
	_run(p, 2.0)
	var face := wall.x * 32
	ok(p.pos.x <= face - p.r + 0.001, "went into the wall: x=%.1f face=%d" % [p.pos.x, face])
	ok(p.pos.x > face - p.r - 2.0, "stopped short of the wall: x=%.1f face=%d" % [p.pos.x, face])


func test_sprint_hovers_above_empty() -> void:
	# The prototype gates sprinting at "stamina above 1", so a held sprint
	# key never runs the bar to zero: it hovers just above empty and the
	# player jogs. Only work (a refused harvest swing) winds you.
	var p := _player_at_tile(6, 133)
	p.intent.mx = 1.0
	p.intent.sprint = true
	_run(p, 5.0)
	ok(p.stam < 2.0, "stamina after five seconds of sprinting: %.2f" % p.stam)
	ok(not p.winded, "sprinting alone must not wind you")


func test_winded_latch_clears_at_half() -> void:
	# Work drains to zero; the latch then holds until stamina is back to
	# half of 110, not one swing of recovery.
	var p := _player_at_tile(6, 133)
	p.stam = 0.0
	p.stam_lock = Config.PLAYER.stam_chop_delay
	_run(p, DT)
	ok(p.winded, "empty stamina should latch winded")
	_run(p, 1.0)
	near(p.stam, 0.0, 0.001, "the chop delay holds recovery for 1.1s")
	_run(p, 0.5)
	ok(p.stam > 5.0 and p.stam < 10.0, "stamina once recovery starts: %.1f" % p.stam)
	ok(p.winded, "still winded at %.1f" % p.stam)
	_run(p, 2.0)
	ok(p.winded, "still winded below half at %.1f" % p.stam)
	_run(p, 1.2)
	ok(not p.winded, "recovered at %.1f" % p.stam)
	ok(p.stam >= 55.0, "stamina %.1f" % p.stam)


func test_sneak_halves_speed() -> void:
	var p := _player_at_tile(6, 133)
	p.intent.mx = 1.0
	p.intent.sneak = true
	_run(p, 1.0)
	var dx := p.pos.x - (6 * 32 + 16)
	ok(dx > 70.0 and dx < 90.0, "sneaked %.1f px in a second" % dx)


func test_starts_by_the_camp_with_the_kit() -> void:
	var p := sim.players[0]
	var camp := Vector2(160 * 32, 160 * 32)
	ok(p.pos.distance_to(camp) <= 30 * 32 + 32, "spawned %.0f px from the camp" % p.pos.distance_to(camp))
	eq(p.weapon().id, "pipe", "holding the pipe")
	eq(p.hotbar.size(), 6, "six hotbar slots")
	eq(p.bag.size(), 30, "thirty pack slots")
	eq(p.count_carried("bandage"), 2, "and two bandages")
	eq(p.hotbar.used(), 2, "nothing else — the rest is out there")
	eq(p.bag.used(), 0, "the pack starts empty")
