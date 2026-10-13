extends "res://tests/test_case.gd"
## The pixel-to-metre seam (`Units`): round trips, and a yaw that faces the
## compass the way the sim does.


func test_a_tile_is_a_metre_and_the_south_axis_is_z() -> void:
	var p := Units.to3(Vector2(32, 64))
	near(p.x, 1.0)
	near(p.y, 0.0)
	near(p.z, 2.0)
	near(Units.to3(Vector2(0, 0), 1.7).y, 1.7, 1e-6, "height rides on y")
	near(Units.m(Config.PLAYER.r), 13.0 / 32.0)


func test_to2_undoes_to3_and_drops_the_height() -> void:
	var v := Vector2(4496.0, 5200.0)
	var back := Units.to2(Units.to3(v, 3.0))
	near(back.x, v.x, 1e-3)
	near(back.y, v.y, 1e-3)


func test_yaw_points_a_plus_z_model_along_the_sim_angle() -> void:
	# A glTF character faces +Z. Turn it by the yaw and it must face the
	# sim's direction on the ground: east, south, west, north.
	for a: float in [0.0, PI / 2.0, PI, -PI / 2.0, 0.7]:
		var want := Vector3(cos(a), 0.0, sin(a))
		var faced := Vector3(0, 0, 1).rotated(Vector3.UP, Units.yaw(a))
		near(faced.x, want.x, 1e-6, "x at angle %s" % a)
		near(faced.z, want.z, 1e-6, "z at angle %s" % a)
		near(angle_difference(Units.angle_of(Units.yaw(a)), a), 0.0, 1e-6, "angle_of undoes yaw")
