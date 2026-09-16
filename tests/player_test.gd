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


func test_sprinting_to_zero_winds_you() -> void:
	# The old floor gated sprinting at "stamina above 1" so the bar hovered
	# just above empty and running could never wind you. It runs flat now.
	var p := _player_at_tile(6, 133)
	p.intent.mx = 1.0
	p.intent.sprint = true
	_run(p, 5.0)
	near(p.stam, 0.0, 0.001, "five seconds of sprinting empties the bar")
	ok(p.winded, "sprinting to zero winds you")
	ok(p.swing_rate_mul > 1.0, "and a winded swing is slower: %.2f" % p.swing_rate_mul)


func test_the_winded_clock_runs_out_and_the_bar_crawls_while_it_does() -> void:
	# The debuff is a clock, not a lock — but recovery crawls while it runs
	# (owner, 2026-09-15), so the three seconds end with a little back rather
	# than most of the bar, and the rest comes at the normal rate afterwards.
	var p := _player_at_tile(6, 133)
	p.stam = 0.0
	_run(p, DT)
	ok(p.winded, "empty stamina should latch winded")
	near(p.winded_t, Config.WINDED.dur, 0.05, "the clock starts at dur")
	_run(p, 2.0)
	ok(p.winded, "still winded at %.1f" % p.stam)
	var slow := p.stam_regen * float(Config.WINDED.regen_mul)
	ok(p.stam > 0.0 and p.stam < slow * 2.0 + 1.0,
		"the refill crawls while winded: %.1f after two seconds" % p.stam)
	_run(p, 1.2)
	ok(not p.winded, "three seconds of standing still clears it")
	near(p.swing_rate_mul, 1.0, 0.001, "and the swing is quick again")
	var after := p.stam
	_run(p, 1.0)
	ok(p.stam - after > slow * 2.0, "and recovery is back to full speed: +%.1f in a second" % (p.stam - after))


func test_sprinting_while_winded_is_refused_so_walking_it_off_works() -> void:
	# It used to be charged for, which restarted the clock every step: anyone
	# walking home with the key held stayed winded for ever (owner, 2026-09-15).
	var p := _player_at_tile(6, 133)
	p.stam = 0.0
	_run(p, DT)
	ok(p.winded, "winded")
	var was := p.pos.x
	p.intent.mx = 1.0
	p.intent.sprint = true
	_run(p, 1.0)
	ok(not p.sprinting, "the sprint key did something while winded")
	ok(p.winded_t < float(Config.WINDED.dur) - 0.5, "the clock did not run down: %.2f" % p.winded_t)
	ok(p.stam > 0.0, "and the walk threw the refill away: %.2f" % p.stam)
	var walked := p.pos.x - was
	ok(walked > 150.0 and walked < 190.0, "walked %.0f px — that is not a walking pace" % walked)
	_run(p, 2.5)
	ok(not p.winded, "the debuff never ended while walking with the key held")


func test_overburdened_winds_you_until_the_weight_comes_off() -> void:
	# The cap is soft: you can pick it all up, and carrying it is the cost.
	var p := _player_at_tile(6, 133)
	Stamina.refill(p)
	p.bag.add("stone", 400)
	ok(p.overloaded(), "400 stone is not over the cap: %.0f / %.0f" % [p.carried_weight(), p.carry_cap])
	_run(p, DT)
	ok(p.winded, "carrying too much did not wind you")
	p.intent.mx = 1.0
	p.intent.sprint = true
	_run(p, 2.0)
	ok(not p.sprinting, "sprinted while overburdened")
	ok(p.winded, "the debuff ended while the weight was still on")
	eq(p._dash_refusal(false), "Too heavy to dash — drop something", "the dash said something else")
	p.bag.take("stone", 400)
	ok(not p.overloaded(), "the stone is still on the bill")
	p.intent.sprint = false
	_run(p, float(Config.WINDED.dur) + 0.2)
	ok(not p.winded, "dropping the weight did not start the clock")


func test_the_soft_cap_lets_you_load_past_it_and_stops_at_the_ceiling() -> void:
	# Through the pickup path, which is what the cap is really about: a find
	# one unit over the cap used to stay on the ground.
	var p := _player_at_tile(6, 133)
	near(p.carry_limit(), p.carry_cap * float(Config.PLAYER.overload_mul), 0.001, "the ceiling is the cap times overload_mul")
	for i in range(40):
		Loot.give_entry(sim, p, {"id": "stone", "n": 50})
	ok(p.overloaded(), "the pickup path refused everything past the cap: %.0f" % p.carried_weight())
	ok(p.carried_weight() <= p.carry_limit() + 1e-6,
		"loaded past the ceiling: %.0f of %.0f" % [p.carried_weight(), p.carry_limit()])


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
