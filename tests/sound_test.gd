extends "res://tests/test_case.gd"
## Noise: heard inside its radius, gives a destination, never aggro.

var sim: GameSim


func before_each() -> void:
	sim = new_sim()


func _horde(base: Vector2, offsets: Array) -> Array[EnemySim]:
	var out: Array[EnemySim] = []
	for o: Vector2 in offsets:
		out.append(sim.enemies.spawn("walker", base + o))
	return out


func test_a_sound_is_heard_inside_its_radius_and_nowhere_else() -> void:
	var base := Vector2(5000, 5000)
	var horde := _horde(base, [Vector2.ZERO, Vector2(100, 0), Vector2(400, 0), Vector2(900, 0)])
	var heard := Sound.make_noise(sim, base.x, base.y, 500.0)
	eq(heard, 3, "three inside 500px, one outside")
	ok(horde[0].has_noise and horde[0].noise_at == base, "the destination is the point of the whole thing")
	ok(horde[0].alert_t > 0.0, "and a window in which to act on it")
	ok(not horde[3].has_noise, "the one that heard nothing has nowhere to go")
	eq(horde[3].alert_t, 0.0)


func test_a_sound_makes_them_investigate_not_hunt() -> void:
	# The whole mechanic, and it shipped broken twice in the prototype: a
	# noise that set aggro sent zombies at the nearest player, not the bang.
	var base := Vector2(5000, 5000)
	var e := _horde(base, [Vector2(100, 0)])[0]
	Sound.make_noise(sim, base.x, base.y, 500.0)
	ok(not e.aggro, "a noise must not aggro — it must give a destination")
	# And it must not clear an existing hunt either.
	e.aggro = true
	Sound.make_noise(sim, base.x, base.y, 500.0)
	ok(e.aggro, "a noise never cancels a hunt in progress")


func test_a_noise_at_the_origin_is_still_a_noise() -> void:
	_horde(Vector2(10, 10), [Vector2.ZERO])
	Sound.make_noise(sim, 0.0, 200.0, 500.0)
	ok(sim.enemies.list[0].has_noise, "x = 0 is a real corner of the map")
	eq(sim.enemies.list[0].noise_at, Vector2(0, 200))


func test_being_quiet_makes_you_quieter_whatever_the_source() -> void:
	var base := Vector2(5000, 5000)
	_horde(base, [Vector2(300, 0)])
	var p := sim.players[0]
	p.noise_mul = 1.0
	eq(Sound.make_noise(sim, base.x, base.y, 400.0, p), 1)
	p.noise_mul = 0.5
	eq(Sound.make_noise(sim, base.x, base.y, 400.0, p), 0, "half as loud does not reach as far")


func test_the_noise_table_ranks_the_way_the_trade_off_needs() -> void:
	var N := Config.NOISE
	var W := Config.WEAPONS
	ok(N.chop < N.build, "an axe is quieter than a hammer")
	ok(N.build < N.generator, "a running generator carries further")
	ok(N.generator < N.turret, "a turret is the loudest thing you own")
	ok(W.pistol.noise > N.build)
	ok(W.rifle.noise > W.smg.noise, "a rifle is louder than an SMG")
	for id in W:
		if W[id].kind == "gun":
			ok(W[id].noise > 0.0, "%s is a firearm and must make a sound" % id)


func test_a_bow_is_quiet_and_a_gun_is_not() -> void:
	var W := Config.WEAPONS
	var bow: Dictionary = W.bow
	eq(bow.kind, "gun", "the bow rides the whole firearm path")
	eq(bow.ammo, "arrow")
	ok(Config.RES.has("arrow"))
	for id in W:
		var w: Dictionary = W[id]
		if w.kind != "gun" or w.get("bow", false):
			continue
		ok(bow.noise * 3.0 < w.noise, "a bow (%d) must be far quieter than a %s (%d)" % [bow.noise, id, w.noise])
		ok(bow.threat < w.threat, "and draw less Threat than a %s" % id)


func test_they_walk_toward_the_bang() -> void:
	# Measured with a control: "moved toward the noise" means nothing until
	# you know how far they wander on their own.
	var plot := tile_centre(clear_plot(14))
	var bang := plot + Vector2(-380, 0)
	var e := sim.enemies.spawn("walker", plot)
	# Nobody to sense, but close enough not to be culled.
	sim.players[0].pos = plot + Vector2(0, 1500)
	sim.players[0].intent.aim = sim.players[0].pos + Vector2.RIGHT
	var before := e.pos.distance_to(bang)
	Sound.make_noise(sim, bang.x, bang.y, 500.0)
	run(sim, 4.0)
	var closed := before - e.pos.distance_to(bang)

	var control := new_sim()
	control.players[0].pos = plot + Vector2(0, 1500)
	control.players[0].intent.aim = control.players[0].pos + Vector2.RIGHT
	var c := control.enemies.spawn("walker", plot)
	run(control, 4.0)
	var drifted := before - c.pos.distance_to(bang)
	print("noise: closed %.0f px toward the bang in 4s; control drifted %.0f" % [closed, drifted])
	ok(closed > 80.0, "walked %.0f px toward the noise" % closed)
	ok(closed > drifted + 40.0, "and clearly more than the control (%.0f)" % drifted)
