class_name VehicleView
extends Node2D
## Cars, parked and driven. The generator already draws the *scenery* version
## of a car through the prop renderer; this replaces it, because a car is a
## thing that moves now and props do not.

const C := Config.CAR

var sim: GameSim


func _init(sim_: GameSim) -> void:
	sim = sim_
	z_index = 2


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var vp := get_viewport_rect().size
	var cam := get_viewport().get_camera_2d()
	var centre: Vector2 = cam.position if cam != null else Vector2.ZERO
	var margin := vp.length()
	var tl := centre - Vector2(margin, margin)
	var br := centre + Vector2(margin, margin)

	for v in sim.cars.list:
		if v.pos.x < tl.x or v.pos.x > br.x or v.pos.y < tl.y or v.pos.y > br.y:
			continue
		_draw_car(font, v)


func _draw_car(font: Font, v: Dictionary) -> void:
	var c: Vector2 = Util.render_pos(v.prev_pos, v.pos)
	var dir := Vector2.from_angle(v.angle)
	var side := dir.orthogonal()
	var half_len := 26.0
	var half_w := 13.0

	var body := Color(["#6b5a4a", "#4a5a6b", "#5a6b4a", "#6b4a5a"][int(v.si) % 4])
	if v.destroyed:
		body = Color("#3a352e")
	elif v.flash > 0.0:
		body = body.lerp(Color.WHITE, 0.6)

	# Shadow, then the shell as a rotated quad.
	_quad(c + Vector2(3, 4), dir, side, half_len, half_w, Color(0, 0, 0, 0.22))
	_quad(c, dir, side, half_len, half_w, body)
	# Roof, slightly inset, so the direction it faces is readable at a glance.
	_quad(c - dir * 2.0, dir, side, half_len * 0.5, half_w * 0.7, body.darkened(0.25))

	if v.destroyed:
		draw_string(font, c + Vector2(-40, -half_w - 8), "WRECK", HORIZONTAL_ALIGNMENT_CENTER, 80, 9,
			Color("#8a8f84"))
		return

	# Headlights, but only when they would show — an engine off in daylight
	# should not paint two yellow smears on the road.
	if v.engine_on and float(sim.clock.darkness().alpha) > 0.05:
		for k: float in [-1.0, 1.0]:
			var at := c + dir * half_len + side * (half_w * 0.55 * k)
			draw_circle(at, 3.0, Color("#ffe6a8"))

	if v.locked and not v.hotwired:
		draw_string(font, c + Vector2(-40, -half_w - 8), "LOCKED", HORIZONTAL_ALIGNMENT_CENTER, 80, 9,
			Color("#c96a5a", 0.8))
	elif v.fuel <= 0.5:
		draw_string(font, c + Vector2(-40, -half_w - 8), "EMPTY", HORIZONTAL_ALIGNMENT_CENTER, 80, 9,
			Color("#d9c46a", 0.7))

	# Fuel and damage, only once either matters.
	if v.engine_on:
		var bar := Rect2(c.x - 20.0, c.y + half_w + 6.0, 40.0, 3.0)
		draw_rect(bar, Color(0, 0, 0, 0.55))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(v.fuel / C.fuel_max, 0.0, 1.0), bar.size.y)),
			Color("#d2762c"))
	if v.hp < v.max_hp:
		var hb := Rect2(c.x - 20.0, c.y - half_w - 6.0, 40.0, 3.0)
		draw_rect(hb, Color(0, 0, 0, 0.55))
		draw_rect(Rect2(hb.position, Vector2(hb.size.x * clampf(v.hp / v.max_hp, 0.0, 1.0), hb.size.y)),
			Color("#7ec46a"))


func _quad(c: Vector2, dir: Vector2, side: Vector2, hl: float, hw: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		c + dir * hl + side * hw,
		c + dir * hl - side * hw,
		c - dir * hl - side * hw,
		c - dir * hl + side * hw,
	]), col)
