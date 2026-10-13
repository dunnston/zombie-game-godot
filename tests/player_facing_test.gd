extends "res://tests/test_case.gd"
## Where the body looks (`PlayerSim.face`, owner 2026-10-13 after V Rising):
## where your feet take you, at the cursor when you stand still, and at the
## cursor while you attack and for a moment after. Driven through Intent
## exactly as the game drives it.

const DT := 1.0 / 60.0

var sim: GameSim
var p: PlayerSim
var plot: Vector2


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = tile_centre(clear_plot(12))
	p.pos = plot
	p.intent.aim = plot + Vector2.RIGHT * 1e4
	sim.give_test_kit(p)


func _run(seconds: float) -> void:
	for i in range(int(round(seconds / DT))):
		p.tick(sim, DT)
		p.intent.clear_edges()


func _faces(expected: float, msg: String) -> void:
	near(angle_difference(p.angle, expected), 0.0, 0.05, msg + " (faced %.2f, wanted %.2f)" % [p.angle, expected])


func test_walking_you_look_where_you_walk_not_at_the_mouse() -> void:
	# The cursor west of you; the keys walk you east.
	p.intent.aim = plot + Vector2.LEFT * 1e4
	p.intent.mx = 1.0
	_run(0.5)
	_faces(0.0, "walking east with the cursor behind you, you look east")
	ok(p.pos.x > plot.x + 50.0, "and you did walk east")
	# A diagonal looks along the diagonal.
	p.intent.mx = 0.0
	p.intent.my = -1.0
	_run(0.2)
	_faces(-PI / 2.0, "walking north, you look north")


func test_standing_still_you_look_at_the_mouse() -> void:
	p.intent.aim = plot + Vector2.LEFT * 1e4
	p.intent.mx = 1.0
	_run(0.3)
	_faces(0.0, "walking east")
	p.intent.mx = 0.0
	_run(0.1)
	_faces(PI, "stopped, you look at the cursor to the west")
	# The mouse moving while you stand is followed at once.
	p.intent.aim = p.pos + Vector2.DOWN * 1e4
	_run(DT)
	_faces(PI / 2.0, "and follows the mouse as it moves")


func test_an_attack_turns_you_to_the_mouse_and_the_shot_goes_there() -> void:
	# Walking east, the cursor north: a click turns you north and the round
	# leaves to the north, not along your feet.
	p.select_slot(p.hotbar_index("pistol"))
	p.attack_cd = 0.0
	p.intent.aim = plot + Vector2.UP * 1e4
	p.intent.mx = 1.0
	_run(0.3)
	_faces(0.0, "walking east before the click")
	var aim_angle := (p.intent.aim - p.pos).angle()
	p.intent.fire = true
	p.intent.fire_pressed = true
	p.tick(sim, DT)
	p.intent.clear_edges()
	var flashes := events_of(sim, "muzzle")
	eq(flashes.size(), 1, "one round fired")
	near(angle_difference(float(flashes[0].a), aim_angle), 0.0, 0.05, "the round left toward the cursor, not along the feet")
	p.intent.fire = false
	_faces(aim_angle, "the body turned to the cursor for the shot")


func test_the_mouse_keeps_your_eyes_for_a_moment_after_the_last_swing() -> void:
	p.select_slot(p.hotbar_index("pipe"))
	p.attack_cd = 0.0
	p.intent.aim = plot + Vector2.UP * 1e4
	p.intent.mx = 1.0
	_run(0.2)
	p.intent.fire_pressed = true
	p.intent.fire = true
	_run(DT)
	p.intent.fire = false
	ok(not p.swing.is_empty(), "a swing began")
	_faces(-PI / 2.0, "swinging north")
	# The swing itself holds the eyes, and `face_hold` runs on past its end.
	_run(float(p.swing.dur))
	ok(p.swing.is_empty(), "the swing is over")
	_faces(-PI / 2.0, "still looking at the cursor the moment the swing ends")
	_run(float(Config.PLAYER.face_hold) + 2.0 * DT)
	_faces(0.0, "and back to the feet once the hold runs out")


func test_a_roll_looks_where_it_goes_even_with_the_keys_let_go() -> void:
	p.intent.aim = plot + Vector2.RIGHT * 1e4
	p.intent.my = -1.0
	_run(0.2)
	_faces(-PI / 2.0, "walking north")
	p.intent.dash = true
	p.tick(sim, DT)
	p.intent.clear_edges()
	ok(p.dash_t > 0.0, "the roll began")
	p.intent.my = 0.0
	_run(DT)
	ok(p.dash_t > 0.0, "still rolling")
	_faces(-PI / 2.0, "a roll north with the keys released still looks north")


func test_rooted_you_look_at_the_mouse_whatever_the_keys_say() -> void:
	p.intent.aim = plot + Vector2.LEFT * 1e4
	p.intent.mx = 1.0
	_run(0.2)
	_faces(0.0, "walking east")
	# Healing roots you: the keys are held but you are standing.
	p.using = {"id": "bandage", "t": 0.0, "dur": 10.0}
	_run(0.1)
	_faces(PI, "rooted, you look at the cursor")
