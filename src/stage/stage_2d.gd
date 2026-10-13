class_name Stage2D
extends Stage
## The game as it always was: the tile layers, the canvas-drawn views, the
## 2D lights and a Camera2D. Everything here used to be built inline by
## `scenes/main.gd`; it moved behind the `Stage` seam on 2026-10-13 so a 3D
## stage could stand in the same place. Nothing about how it draws changed.
##
## The views stay public: the smoke's debug legs look at `noise_lens` and
## `lights` directly, and they are allowed to, because those legs only run
## on this stage.

var terrain: TerrainRenderer
var props_below: PropRenderer
var props_above: PropRenderer
var enemy_view: EnemyView
var pickup_view: PickupView
var structure_view: StructureView
var instance_view: InstanceView
var boss_view: BossView
var fx: FxView
var noise_lens: NoiseLensView
var lights: LightView
var survivor_view: SurvivorView
var vehicle_view: VehicleView
var player_view: PlayerView
var camera: Camera2D

## The zoom the window's height asks for; the arena multiplies it.
var _zoom := 1.0
var _shake_rng := RandomNumberGenerator.new()


func _init(sim_: GameSim) -> void:
	sim = sim_
	terrain = TerrainRenderer.new()
	add_child(terrain)
	props_below = PropRenderer.new(sim, false)
	add_child(props_below)
	pickup_view = PickupView.new(sim)
	add_child(pickup_view)
	structure_view = StructureView.new(sim)
	add_child(structure_view)
	instance_view = InstanceView.new(sim)
	add_child(instance_view)
	enemy_view = EnemyView.new(sim)
	add_child(enemy_view)
	boss_view = BossView.new(sim)
	add_child(boss_view)
	vehicle_view = VehicleView.new(sim)
	add_child(vehicle_view)
	survivor_view = SurvivorView.new(sim)
	add_child(survivor_view)
	player_view = PlayerView.new(sim)
	add_child(player_view)
	props_above = PropRenderer.new(sim, true)
	add_child(props_above)
	fx = FxView.new(sim)
	add_child(fx)
	# Last of the world nodes: its CanvasModulate darkens the whole canvas and
	# its lights add back on top of that.
	lights = LightView.new(sim)
	add_child(lights)

	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = Config.WORLD_SIZE
	camera.limit_bottom = Config.WORLD_SIZE
	add_child(camera)

	# The noise lens sits over the world on a layer of its own that follows the
	# camera: the night's CanvasModulate tints only the canvas it is on, so a
	# ring drawn down there went black with everything else. The stage is
	# added before the HUD's layer, which shares this layer's index, so the
	# HUD still draws on top.
	var lens_layer := CanvasLayer.new()
	lens_layer.follow_viewport_enabled = true
	add_child(lens_layer)
	noise_lens = NoiseLensView.new()
	lens_layer.add_child(noise_lens)


func build() -> void:
	terrain.build(sim.world)
	var C := Config.CAMERA
	var vp := get_viewport().get_visible_rect().size
	var z := clampf(vp.y / C.view_height, C.min_zoom, C.max_zoom)
	camera.zoom = Vector2(z, z)
	_zoom = z
	camera.position = sim.players[0].pos
	camera.make_current()
	sim.view_radius = view_radius()


func rebuild() -> void:
	# The world is a new object. The terrain layers and the prop renderers
	# both cached the old one — the props by bucketing its dictionaries, so
	# without this the view goes on drawing a container the restored world
	# says is still full.
	terrain.build(sim.world)
	rebuild_props()


func rebuild_props() -> void:
	props_below.rebuild()
	props_above.rebuild()


func repaint(tx: int, ty: int) -> void:
	terrain.repaint(sim.world, tx, ty)


func set_local(p: PlayerSim) -> void:
	local = p
	player_view.local = p
	structure_view.player = p
	props_below.player = p
	props_above.player = p


func attach_build_bar(bar: BuildBar) -> void:
	structure_view.build_bar = bar


func on_event(ev: Dictionary) -> void:
	if ev.t == "wall_broken":
		# One tile of the town is rubble now. Repainted where it stands —
		# rebuilding the terrain layers is 80ms and a horde breaks several.
		repaint(int(ev.tx), int(ev.ty))
	fx.on_event(ev)
	noise_lens.on_event(ev)
	boss_view.on_event(ev)
	lights.on_event(ev)


func tick(dt: float) -> void:
	fx.tick(dt)
	noise_lens.tick(dt)
	boss_view.tick(dt)
	lights.tick()


func frame() -> void:
	props_below.queue_redraw()
	props_above.queue_redraw()
	pickup_view.queue_redraw()
	structure_view.queue_redraw()
	instance_view.queue_redraw()
	enemy_view.queue_redraw()
	boss_view.queue_redraw()
	player_view.queue_redraw()
	fx.queue_redraw()
	noise_lens.queue_redraw()


func snap(pos: Vector2) -> void:
	camera.position = pos


func follow(dt: float, p: PlayerSim, boss: EnemySim, shake: float) -> void:
	var f := frame_for(p, cursor_world(), boss)
	var want: float = _zoom * float(f.zoom_mul)
	camera.position = camera.position.lerp(f.focus, Util.smooth(Config.CAMERA.follow, dt))
	camera.zoom = camera.zoom.lerp(Vector2(want, want), Util.smooth(5.0, dt))
	if shake > 0.0:
		camera.offset = Vector2(_shake_rng.randf_range(-shake, shake), _shake_rng.randf_range(-shake, shake))
	else:
		camera.offset = Vector2.ZERO


func cursor_world() -> Vector2:
	return camera.get_global_mouse_position()


func to_screen(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


func view_radius() -> float:
	return get_viewport().get_visible_rect().size.length() / 2.0 / _zoom
