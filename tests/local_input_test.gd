extends "res://tests/test_case.gd"
## Move-toward-cursor: the move keys turned so Forward points at the mouse. The
## turning is the input layer's; what reaches the sim is a world direction.


func _near_vec(actual: Vector2, expected: Vector2, msg := "") -> void:
	near(actual.x, expected.x, 1e-4, msg + " (x of %s)" % actual)
	near(actual.y, expected.y, 1e-4, msg + " (y of %s)" % actual)


func test_facing_up_the_screen_the_keys_are_the_compass() -> void:
	# The heading a fresh game starts with, so nothing moves differently before
	# the mouse does.
	var up := -PI / 2.0
	_near_vec(LocalInput.steer(Vector2(0, -1), up), Vector2(0, -1), "Forward")
	_near_vec(LocalInput.steer(Vector2(1, 0), up), Vector2(1, 0), "Right")


func test_forward_walks_at_the_cursor_and_back_walks_away() -> void:
	var east := LocalInput.aim_heading(Vector2(100, 100), Vector2(400, 100), 0.0)
	_near_vec(LocalInput.steer(Vector2(0, -1), east), Vector2(1, 0), "Forward, cursor east")
	_near_vec(LocalInput.steer(Vector2(0, 1), east), Vector2(-1, 0), "Back, cursor east")


func test_left_and_right_strafe_around_the_cursor() -> void:
	# Looking down the screen your right hand is on the screen's left.
	var south := LocalInput.aim_heading(Vector2.ZERO, Vector2(0, 300), 0.0)
	_near_vec(LocalInput.steer(Vector2(1, 0), south), Vector2(-1, 0), "Right, cursor south")
	_near_vec(LocalInput.steer(Vector2(-1, 0), south), Vector2(1, 0), "Left, cursor south")
	var east := 0.0
	_near_vec(LocalInput.steer(Vector2(1, 0), east), Vector2(0, 1), "Right, cursor east")


func test_a_diagonal_stays_walking_speed() -> void:
	# The keys arrive already limited to length one; turning them must not
	# make a diagonal faster or slower.
	var diag := Vector2(1, -1).normalized()
	near(LocalInput.steer(diag, 0.7).length(), 1.0, 1e-5)
	# `PlayerSim.move` asks `mx != 0.0 or my != 0.0` to decide you are standing.
	var still := LocalInput.steer(Vector2.ZERO, 0.7)
	ok(still.x == 0.0 and still.y == 0.0, "and no keys is no movement, whatever the heading")


func test_a_cursor_on_top_of_you_keeps_the_heading_you_had() -> void:
	# That close, a pixel of mouse is a half turn: walking over the cursor
	# would otherwise spin you on the spot.
	var dz := float(Config.PLAYER.cursor_deadzone)
	var prev := 1.25
	near(LocalInput.aim_heading(Vector2(50, 50), Vector2(50, 50), prev), prev, 1e-6, "on you")
	near(LocalInput.aim_heading(Vector2(50, 50), Vector2(50 + dz * 0.5, 50), prev), prev, 1e-6, "inside the deadzone")
	near(LocalInput.aim_heading(Vector2(50, 50), Vector2(50 + dz * 2.0, 50), prev), 0.0, 1e-6, "outside it, the cursor wins")
