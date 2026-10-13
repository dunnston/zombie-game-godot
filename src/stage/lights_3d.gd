class_name Lights3D
extends Node3D
## The day, the dark, and everything that punches a hole in it, on the 3D
## stage. The sun is a DirectionalLight3D and the sky's ambient a
## WorldEnvironment, both following `sim.clock.canvas_tint()` exactly as
## the 2D CanvasModulate does, so the night is as black here as there.
## Torches, fires and floodlights are a pool of OmniLight3Ds reassigned
## every frame, the flashlight a SpotLight3D, a muzzle flash an omni with a
## life — the same sources `LightView` reads, at the same radii
## (`GEAR.light`), a metre and a bit off the ground.

var sim: GameSim
var sun: DirectionalLight3D
var env: WorldEnvironment
var _pool: Array[OmniLight3D] = []
var _used := 0
var _cones: Array[SpotLight3D] = []
var _cones_used := 0
var _flashes: Array[Dictionary] = []


func _init(sim_: GameSim) -> void:
	sim = sim_
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, 28.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	sun.light_energy = 1.1
	add_child(sun)
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#2f3137")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)


func on_event(ev: Dictionary) -> void:
	if ev.t == "muzzle":
		if String(ev.get("w", "")) == "bow":
			return
		_flashes.append({"pos": Vector2(ev.x, ev.y), "t": 0.0, "life": 0.06, "radius": 190.0, "color": Color("#ffe0a8")})


func tick(dt: float) -> void:
	var tint := sim.clock.canvas_tint()
	var alpha: float = float(sim.clock.darkness().alpha)
	# The 2D night is one multiply by the tint: the sun and the ambient
	# together are that multiply here.
	sun.light_color = tint
	sun.light_energy = 1.1 * (1.0 - 0.85 * alpha)
	env.environment.ambient_light_color = tint
	env.environment.ambient_light_energy = 0.55 * (1.0 - 0.6 * alpha)
	_used = 0
	_cones_used = 0
	if alpha > 0.02:
		_carried()
		_floodlights()
		_fires()
		_headlights()
	_muzzle(dt)
	for i in range(_used, _pool.size()):
		_pool[i].visible = false
	for i in range(_cones_used, _cones.size()):
		_cones[i].visible = false


func _carried() -> void:
	for p in sim.players:
		if p.dead or p.away or not p.lit:
			continue
		var g := Equipment.equipped_light(p)
		if g.is_empty():
			continue
		var l: Dictionary = g.light
		# Over the head rather than in the chest: a light inside the body lights
		# nothing of it, and the torch has to show who is carrying it.
		_take(p.pos, float(l.radius), Color(String(l.warm)), float(l.strength), 2.4)
		if l.has("cone_len"):
			_take_cone(p.pos, p.angle, float(l.cone_len), float(l.cone_spread), Color(String(l.warm)), float(l.cone_strength))


func _floodlights() -> void:
	for s in sim.structs.list:
		if s.destroyed or s.type != "floodlight" or not s.powered or not s.on:
			continue
		_take(s.pos, float(s.def.light_radius), Color("#dff0ff"), 0.9, 2.4)


func _fires() -> void:
	for f in sim.fire.list:
		var k: float = 1.0 - clampf(f.t / maxf(0.001, f.life), 0.0, 1.0)
		_take(f.pos, 120.0 + 40.0 * k, Color("#ff9a3a"), 0.55 + 0.35 * k, 0.6)


func _headlights() -> void:
	for v in sim.cars.list:
		if v.destroyed or not v.engine_on:
			continue
		_take_cone(v.pos + Vector2.from_angle(float(v.angle)) * 26.0, float(v.angle), 260.0, 0.9, Color("#ffe6a8"), 0.9)


func _muzzle(dt: float) -> void:
	for i in range(_flashes.size() - 1, -1, -1):
		var fl: Dictionary = _flashes[i]
		fl.t += dt
		if fl.t >= fl.life:
			_flashes.remove_at(i)
			continue
		var k: float = 1.0 - fl.t / fl.life
		_take(fl.pos, float(fl.radius) * k, fl.color, k * 2.0)


func _take(at: Vector2, radius_px: float, color: Color, energy: float, h := -1.0) -> void:
	if _used >= _pool.size():
		var l := OmniLight3D.new()
		l.shadow_enabled = false
		l.omni_attenuation = 1.4
		add_child(l)
		_pool.append(l)
	var light := _pool[_used]
	_used += 1
	light.position = Units.to3(at, float(Config.STAGE3D.light_h) if h < 0.0 else h)
	light.omni_range = Units.m(radius_px)
	light.light_color = color
	light.light_energy = energy * 2.2
	light.visible = true


func _take_cone(at: Vector2, angle: float, length_px: float, spread: float, color: Color, energy: float) -> void:
	if _cones_used >= _cones.size():
		var l := SpotLight3D.new()
		l.shadow_enabled = false
		add_child(l)
		_cones.append(l)
	var light := _cones[_cones_used]
	_cones_used += 1
	light.position = Units.to3(at, float(Config.STAGE3D.light_h))
	# Pointed along the facing and a little down, so the cone lands on the
	# ground ahead rather than lighting the air.
	light.rotation = Vector3(0.0, Units.yaw(angle), 0.0)
	light.rotate_object_local(Vector3.RIGHT, deg_to_rad(-18.0))
	# A SpotLight3D shines down its -Z; a model's forward is +Z.
	light.rotate_object_local(Vector3.UP, PI)
	light.spot_range = Units.m(length_px)
	light.spot_angle = rad_to_deg(spread) * 0.5 if spread > 0.0 else 25.0
	light.light_color = color
	light.light_energy = energy * 3.0
	light.visible = true
