class_name LightView
extends Node2D
## The dark, and everything that punches a hole in it.
##
## The prototype painted a translucent rectangle over the finished frame. This
## uses what Godot actually has: a `CanvasModulate` that multiplies the whole
## canvas down, and real `PointLight2D`s that add light back. The difference
## matters — a torch now genuinely lights the ground around it rather than
## cutting a circle out of an overlay, and two torches overlap correctly.
##
## Lights are pooled and reassigned every frame rather than created and freed,
## because a hundred and forty fires flickering in and out would otherwise be a
## hundred and forty node allocations a second.

const POINT_TEX := 256          # radial light texture, pixels across
const CONE_TEX := 256

static var _point: Texture2D
static var _cone: Texture2D

var sim: GameSim
var modulate_node: CanvasModulate
var _pool: Array[PointLight2D] = []
var _used := 0
## Muzzle flashes are events, not states: each one is a light with a life.
var _flashes: Array[Dictionary] = []


func _init(sim_: GameSim) -> void:
	sim = sim_
	# Above the world so its lights are not sorted behind anything, but the
	# lights themselves are what draw — this node never paints.
	z_index = 0


func _ready() -> void:
	modulate_node = CanvasModulate.new()
	modulate_node.color = Color.WHITE
	add_child(modulate_node)


func on_event(ev: Dictionary) -> void:
	match ev.t:
		"muzzle":
			# The bow has no flash, and neither does a turret's own barrel at
			# this size — only what the player fires lights the ground.
			if String(ev.get("w", "")) == "bow":
				return
			_flashes.append({"pos": Vector2(ev.x, ev.y), "t": 0.0, "life": 0.06,
				"radius": 190.0, "color": Color("#ffe0a8")})
		"ignite":
			pass


# ------------------------------------------------------------------ update --

func tick() -> void:
	var alpha: float = float(sim.clock.darkness().alpha)
	# One coloured multiply is the whole night.
	#
	# This was two nodes: a grey `CanvasModulate` for `1 - alpha` and an
	# additive `DirectionalLight2D` for `color * alpha`, on the reasoning that
	# the overlay the prototype painted is a multiply *and* an add, and a
	# CanvasModulate can only multiply. The add was supposed to be the term
	# that tints a black pixel.
	#
	# It never was. Godot's canvas shader saves `base_color` *before* the
	# canvas modulate and every light pass multiplies by it —
	# `light_color.rgb *= base_color.rgb` — so an additive light over black
	# ground adds nothing, and over lit ground it adds `tint * alpha * pixel`.
	# That is a multiply wearing an add's clothes, and it left a floor under
	# how dark night could get: at the old #161436 and #070c1c the map still
	# came through at a seventh of daylight, which is exactly the "never got so
	# dark that I couldn't see" the owner reported with a torch equipped.
	#
	# So it is one multiply, `lerp(WHITE, tint, alpha)` — identical arithmetic
	# to what the two nodes actually produced, one node instead of two, no
	# whole-screen light pass per frame, and the darkness now lives entirely
	# in `Config.DARKNESS_KEYS` where it can be read off. Real lights still
	# add on top, because they multiply that same unmodulated `base_color`:
	# a torch at midnight brings its circle back to nearly full brightness.
	# The arithmetic itself is `DayNight.canvas_tint_at`, so the fast suite can
	# assert on how dark the picture is without standing up a viewport.
	modulate_node.color = sim.clock.canvas_tint()

	_used = 0
	# Nothing needs lighting in broad daylight, and a hundred idle lights are
	# still a hundred draws.
	if alpha > 0.02:
		_carried_lights()
		_floodlights()
		_fires()
	_muzzle_flashes()
	for i in range(_used, _pool.size()):
		_pool[i].visible = false


func _carried_lights() -> void:
	for p in sim.players:
		if p.dead or p.away or not p.lit:
			continue
		var g := Equipment.equipped_light(p)
		if g.is_empty():
			continue
		var l: Dictionary = g.light
		_take(p.pos, float(l.radius), Color(String(l.warm)), float(l.strength))
		# A flashlight is a cone as well as a puddle — that is the whole
		# difference between it and the torch, and why it is worth batteries.
		if l.has("cone_len"):
			_take_cone(p.pos, p.angle, float(l.cone_len), float(l.cone_spread),
				Color(String(l.warm)), float(l.cone_strength))


func _floodlights() -> void:
	for s in sim.structs.list:
		if s.destroyed or s.type != "floodlight" or not s.powered or not s.on:
			continue
		_take(s.pos, float(s.def.light_radius), Color("#dff0ff"), 0.9)


func _fires() -> void:
	for f in sim.fire.list:
		# A fire dims as it dies, which is what makes a burning treeline read
		# as going out rather than blinking off.
		var k: float = 1.0 - clampf(f.t / maxf(0.001, f.life), 0.0, 1.0)
		_take(f.pos, 120.0 + 40.0 * k, Color("#ff9a3a"), 0.55 + 0.35 * k)


func _muzzle_flashes() -> void:
	for i in range(_flashes.size() - 1, -1, -1):
		var fl: Dictionary = _flashes[i]
		fl.t += get_process_delta_time()
		if fl.t >= fl.life:
			_flashes.remove_at(i)
			continue
		var k: float = 1.0 - fl.t / fl.life
		_take(fl.pos, float(fl.radius) * k, fl.color, k)


# -------------------------------------------------------------- the pool --

func _take(at: Vector2, radius: float, color: Color, energy: float) -> void:
	var l := _next()
	l.texture = _point_texture()
	l.position = at
	l.rotation = 0.0
	l.color = color
	l.energy = energy
	# The texture is POINT_TEX across and stands for a diameter of `radius`
	# either side of the centre.
	l.texture_scale = radius * 2.0 / float(POINT_TEX)
	l.visible = true


func _take_cone(at: Vector2, angle: float, length: float, spread: float, color: Color, energy: float) -> void:
	var l := _next()
	l.texture = _cone_texture()
	l.position = at
	l.rotation = angle
	l.color = color
	l.energy = energy
	l.texture_scale = length * 2.0 / float(CONE_TEX)
	l.visible = true
	# Unused for now, but the spread is baked into the texture rather than the
	# node, so a wider cone would be a second texture and not a squashed one.
	var _unused := spread


func _next() -> PointLight2D:
	if _used >= _pool.size():
		var l := PointLight2D.new()
		l.blend_mode = Light2D.BLEND_MODE_ADD
		l.shadow_enabled = false
		add_child(l)
		_pool.append(l)
	var out := _pool[_used]
	_used += 1
	return out


# ----------------------------------------------------------- the textures --

## A radial falloff, generated once: `(1 - d^2)^2`, flat at the centre and
## flat again where it reaches zero.
##
## It was `(1 - d)^2` — bright core, quick fade — chosen against a linear
## ramp because a linear ramp reads as a flat disc with a hard rim. Squared
## distance-from-centre solves the rim without the collapse: `(1 - d)^2` is
## already down to a quarter at half the radius, so a 300px torch was a 75px
## puddle inside a wide grey haze, and against a night that is now genuinely
## black that haze banded into visible contour rings. This curve holds 0.71
## at 40% of the radius and 0.41 at 60%, and its slope is zero at both ends,
## so there is no rim at the outside and no hotspot at the middle — a torch
## you can walk by, still vague at the edge.
static func _point_texture() -> Texture2D:
	if _point != null:
		return _point
	var img := Image.create(POINT_TEX, POINT_TEX, false, Image.FORMAT_RGBA8)
	var c := POINT_TEX / 2.0
	for y in range(POINT_TEX):
		for x in range(POINT_TEX):
			var d := Vector2(x - c + 0.5, y - c + 0.5).length() / c
			var a := clampf(1.0 - d * d, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_point = ImageTexture.create_from_image(img)
	return _point


## A wedge pointing along +X, so the node's rotation is the aim. A beam holds
## its brightness down most of its length and dies at the tip — `1 - d^2`
## along it, which is 0.75 at half its reach where the old `1 - d` was 0.5 —
## and fades across its width as `(1 - off^2)^2`, squared so the sides of the
## beam are soft rather than a visible wedge with edges. That reach and that
## softness are the whole difference between the flashlight and the torch,
## and what the batteries buy.
static func _cone_texture() -> Texture2D:
	if _cone != null:
		return _cone
	var img := Image.create(CONE_TEX, CONE_TEX, false, Image.FORMAT_RGBA8)
	var c := CONE_TEX / 2.0
	var spread := 0.34
	for y in range(CONE_TEX):
		for x in range(CONE_TEX):
			var dx := x - c + 0.5
			var dy := y - c + 0.5
			var d := Vector2(dx, dy).length() / c
			var a := 0.0
			if dx > 0.0 and d <= 1.0:
				var off := absf(atan2(dy, dx)) / spread
				if off < 1.0:
					var across := clampf(1.0 - off * off, 0.0, 1.0)
					a = clampf(1.0 - d * d, 0.0, 1.0) * across * across
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_cone = ImageTexture.create_from_image(img)
	return _cone
