class_name Stage3D
extends Stage
## The same town, standing up (2026-10-13, `tasks/3d-conversion.md`). The
## sim's pixels become metres through `Units`; the terrain, the people and
## the pieces are 3D nodes under one root; every word and bar is drawn on
## a canvas layer over them at the point the camera gives. The camera is a
## perspective camera pitched down, south of the player looking north, so
## north is up on screen as it has always been.
##
## Nothing here reads the sim that the 2D views did not read, and nothing
## here changes it: `Stage` is a view, and the one way in is still Intent.

var world3: Node3D
var terrain: Terrain3D
var actors: Actors3D
var structures: Structures3D
var props: Props3D
var pickups: Pickups3D
var vehicles: Vehicles3D
var survivors: Survivors3D
var doors: Doors3D
var lights: Lights3D
var camera: Camera3D

var overlay: CanvasLayer
var fx: Fx3DOverlay
var boss: Boss3DOverlay
var labels: Labels3D

## Where the camera looks, in sim pixels, and how far back it stands.
var focus := Vector2.ZERO
var _dist := 30.0
## Labels are drawn for everything within this many pixels of the focus.
var label_reach := 1400.0
var _shake_rng := RandomNumberGenerator.new()
var _pitch := 0.0


func _init(sim_: GameSim) -> void:
	sim = sim_
	var C := Config.CAMERA3D
	_pitch = deg_to_rad(float(C.pitch))
	_dist = float(C.distance)

	world3 = Node3D.new()
	add_child(world3)
	lights = Lights3D.new(sim)
	world3.add_child(lights)
	terrain = Terrain3D.new()
	world3.add_child(terrain)
	props = Props3D.new(sim)
	world3.add_child(props)
	doors = Doors3D.new(sim)
	world3.add_child(doors)
	structures = Structures3D.new(sim)
	world3.add_child(structures)
	pickups = Pickups3D.new(sim)
	world3.add_child(pickups)
	vehicles = Vehicles3D.new(sim)
	world3.add_child(vehicles)
	survivors = Survivors3D.new(sim)
	world3.add_child(survivors)
	actors = Actors3D.new(sim)
	world3.add_child(actors)

	camera = Camera3D.new()
	camera.fov = float(C.fov)
	camera.near = 0.5
	camera.far = 400.0
	world3.add_child(camera)

	# Over the world, under the HUD: the stage is main's first child and the
	# HUD's layer shares this layer's index, so tree order keeps the HUD up.
	overlay = CanvasLayer.new()
	add_child(overlay)
	fx = Fx3DOverlay.new(sim, self)
	overlay.add_child(fx)
	boss = Boss3DOverlay.new(sim, self)
	overlay.add_child(boss)
	labels = Labels3D.new(sim, self)
	overlay.add_child(labels)


func build() -> void:
	terrain.build(sim.world)
	props.rebuild()
	doors.rebuild()
	camera.make_current()
	snap(sim.players[0].pos)
	sim.view_radius = view_radius()


func rebuild() -> void:
	terrain.build(sim.world)
	props.rebuild()
	doors.rebuild()
	actors.rebuild()
	structures.rebuild()
	vehicles.rebuild()
	survivors.rebuild()


func rebuild_props() -> void:
	props.rebuild()


func repaint(tx: int, ty: int) -> void:
	terrain.repaint(sim.world, tx, ty)


func set_local(p: PlayerSim) -> void:
	local = p
	actors.local = p
	labels.local = p


func attach_build_bar(bar: BuildBar) -> void:
	structures.build_bar = bar
	labels.build_bar = bar


func on_event(ev: Dictionary) -> void:
	if ev.t == "wall_broken":
		repaint(int(ev.tx), int(ev.ty))
	fx.on_event(ev)
	boss.on_event(ev)
	lights.on_event(ev)


func tick(dt: float) -> void:
	fx.tick(dt)
	boss.tick(dt)
	lights.tick(dt)
	actors.frame(dt)
	props.frame(dt)
	structures.frame()
	pickups.frame()
	vehicles.frame()
	survivors.frame()
	doors.frame()


func frame() -> void:
	fx.queue_redraw()
	boss.queue_redraw()
	labels.queue_redraw()


func snap(pos: Vector2) -> void:
	focus = pos
	_place_camera()


func follow(dt: float, p: PlayerSim, boss_: EnemySim, shake: float) -> void:
	var f := frame_for(p, cursor_world(), boss_)
	focus = focus.lerp(f.focus, Util.smooth(Config.CAMERA.follow, dt))
	var want := float(Config.CAMERA3D.distance) / float(f.zoom_mul)
	_dist = lerpf(_dist, want, Util.smooth(5.0, dt))
	_place_camera()
	if shake > 0.0:
		var k := Units.m(shake) * 0.5
		camera.h_offset = _shake_rng.randf_range(-k, k)
		camera.v_offset = _shake_rng.randf_range(-k, k)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func _place_camera() -> void:
	var f := Units.to3(focus)
	camera.position = f + Vector3(0.0, _dist * sin(_pitch), _dist * cos(_pitch))
	camera.look_at(f, Vector3.UP)


## The ground under the mouse: the camera's ray through the cursor meets
## the plane the town lies on. Pointed at the sky, it is the far ground.
func cursor_world() -> Vector2:
	var m := get_viewport().get_mouse_position()
	var o := camera.project_ray_origin(m)
	var n := camera.project_ray_normal(m)
	var t := 300.0
	if n.y < -1e-4:
		t = -o.y / n.y
	return Units.to2(o + n * t)


func to_screen(world: Vector2) -> Vector2:
	return camera.unproject_position(Units.to3(world))


## A world point `h` metres off the ground, on the screen.
func to_screen_h(world: Vector2, h: float) -> Vector2:
	return camera.unproject_position(Units.to3(world, h))


## How long `r_px` sim pixels are on screen at `world`: what a 2D size
## becomes under this camera, there.
func screen_radius(world: Vector2, r_px: float) -> float:
	return to_screen(world).distance_to(to_screen(world + Vector2(r_px, 0.0)))


## Half the screen's diagonal in world pixels, measured where the camera's
## corner rays meet the ground. The spawn ring sits beyond it.
func view_radius() -> float:
	var vp := get_viewport().get_visible_rect().size
	var far := 0.0
	for corner: Vector2 in [Vector2.ZERO, Vector2(vp.x, 0), Vector2(0, vp.y), vp]:
		var o := camera.project_ray_origin(corner)
		var n := camera.project_ray_normal(corner)
		var t := _dist * 3.0
		if n.y < -1e-4:
			t = minf(-o.y / n.y, _dist * 3.0)
		far = maxf(far, Units.to2(o + n * t).distance_to(focus))
	label_reach = far + 200.0
	return far
