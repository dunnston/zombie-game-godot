extends "res://tests/test_case.gd"
## The 3D stage's bodies: every clip a table names is in its library, the
## clips carry what the stage fits them by, and a boss's body follows its
## events rather than its script (a guest's boss has no script).


func _tables() -> Dictionary:
	var out := {"player": Models.PLAYER}
	for kind in Models.ENEMY_MODELS:
		out[kind] = Models.ENEMY_MODELS[kind]
	return out


func test_every_clip_a_table_names_is_in_its_library() -> void:
	for who in _tables():
		var table: Dictionary = _tables()[who]
		var lib := Models.library(String(table.lib))
		ok(lib != null, "%s has a library" % who)
		if lib == null:
			continue
		for state in table.clips:
			# A state names one clip, or the several the body takes turns with.
			var named: Variant = table.clips[state]
			var clips: Array = named if named is Array else [named]
			for clip_ in clips:
				var clip := String(clip_)
				ok(lib.has_animation(clip), "%s: state %s wants clip '%s'" % [who, state, clip])
				if not lib.has_animation(clip):
					continue
				var a := lib.get_animation(clip)
				gt(a.length, 0.1, "%s/%s is a clip" % [who, clip])
				if state in Models.LOOPING:
					eq(a.loop_mode, Animation.LOOP_LINEAR, "%s/%s loops" % [who, state])


func test_cycles_say_how_fast_they_were_animated() -> void:
	# The stage paces a walk against its clip's own speed; a cycle with none
	# would run at one fixed rate whatever the body does.
	for who in _tables():
		var table: Dictionary = _tables()[who]
		var lib := Models.library(String(table.lib))
		if lib == null:
			continue
		for state in ["walk", "run", "crawl"]:
			if not table.clips.has(state):
				continue
			var a := lib.get_animation(String(table.clips[state]))
			gt(float(a.get_meta("speed", 0.0)), 0.2, "%s/%s moves" % [who, state])
		ok(float(lib.get_animation(String(table.clips.idle)).get_meta("speed", 1.0)) < 0.01, "%s idles in place" % who)


func test_the_coachs_moves_strike_inside_their_clips() -> void:
	var lib := Models.library(String(Models.ENEMY_MODELS.coach.lib))
	for state in ["slam", "throw", "whistle", "charge_wind"]:
		var a := lib.get_animation(String(Models.ENEMY_MODELS.coach.clips[state]))
		var strike := float(a.get_meta("strike", 0.0))
		gt(strike, 0.0, "%s has a strike" % state)
		gt(a.length, strike, "%s strikes before it ends" % state)
	# And a telegraph fitted to the floor (`min_tell`) is never faster than a
	# strike can be followed: the stage clamps the rate to 4x.
	var min_tell := float(Config.BOSSES.coach.min_tell)
	for state in ["slam", "throw", "whistle"]:
		var a := lib.get_animation(String(Models.ENEMY_MODELS.coach.clips[state]))
		ok(float(a.get_meta("strike")) / min_tell <= 4.0, "%s keeps up with a %.1fs tell" % [state, min_tell])


func test_a_boss_body_is_cued_by_its_events() -> void:
	var sim := new_sim()
	var a := Actors3D.new(sim)
	eq(a.on_event({"t": "boss_wake", "id": 7, "x": 0.0, "y": 0.0}), "wake")
	eq(a.on_event({"t": "boss_tell", "id": 7, "move": "slam", "dur": 1.0}), "slam")
	eq(a.on_event({"t": "boss_tell", "id": 7, "move": "charge", "dur": 0.8}), "charge_wind")
	eq(a.on_event({"t": "boss_tell", "id": 7, "move": "dodgeball", "dur": 0.7}), "throw")
	eq(a.on_event({"t": "boss_tell", "id": 7, "move": "whistle", "dur": 0.9}), "whistle")
	eq(a.on_event({"t": "boss_tell", "id": 7, "move": "hook", "dur": 0.8}), "attack", "the Butcher's hook is a swing")
	eq(a.on_event({"t": "boss_stunned", "id": 7, "dur": 1.6}), "stun")
	eq(a.on_event({"t": "boss_phase", "id": 7, "phase": 1}), "roar")
	eq(a.on_event({"t": "shot", "x": 0.0, "y": 0.0}), "", "anything else is not its business")
	a.free()


func test_the_roar_is_the_phase_changes_length() -> void:
	# A phase change is `transition` seconds in which the boss does nothing;
	# the roar is fitted to it, so it must be read off the right boss.
	var sim := new_sim()
	var coach := sim.enemies.spawn("coach", tile_centre(clear_plot(12)))
	var a := Actors3D.new(sim)
	a.on_event({"t": "boss_phase", "id": coach.id, "phase": 1})
	near(float(a._cues[coach.id].dur), float(Config.BOSSES.coach.transition), 1e-6)
	a.free()
