class_name Fx3DOverlay
extends FxView
## `FxView`'s particles, tracers and swing arcs, drawn over the 3D stage.
## The events, the particle clocks and the shapes are the parent's; only
## the drawing changes, because a world point is now wherever the camera
## puts it. Sizes scale with how big a world pixel is on screen there, so
## a damage number over a far walker is smaller than one over a near one.

var stage: Stage3D


func _init(sim_: GameSim, stage_: Stage3D) -> void:
	super(sim_)
	stage = stage_


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for b in sim.bullets:
		var pos: Vector2 = b.pos
		var vel: Vector2 = b.vel
		var col := Color(b.color)
		var sp := stage.to_screen_h(pos, 1.0)
		if vel.length_squared() < 500.0 * 500.0:
			var r := stage.screen_radius(pos, 7.0)
			draw_circle(sp, r, col)
			draw_circle(sp, r, col.darkened(0.4), false, 1.5)
			continue
		var tail := stage.to_screen_h(pos - vel * 0.018, 1.0)
		draw_line(tail, sp, Color(col, 0.35), 3.0)
		draw_line(tail, sp, col, 1.5)
	for p in sim.players:
		if p.swing.is_empty():
			continue
		var s: Dictionary = p.swing
		var k: float = 1.0 - s.t / s.dur
		_arc(p.pos, s.range - 4.0, s.angle - s.arc / 2.0, s.angle + s.arc / 2.0, Color(1, 1, 1, 0.55 * k), 4.0 * k + 1.0)
	for q in particles:
		var k: float = clampf(q.life / q.max, 0.0, 1.0)
		var scale := stage.screen_radius(q.pos, 1.0)
		match q.kind:
			"dot":
				var c: Color = q.color
				c.a = k
				draw_circle(stage.to_screen_h(q.pos, 0.6), q.size * scale, c)
			"text":
				var c: Color = q.color
				c.a = minf(1.0, k * 2.0)
				var at := stage.to_screen_h(q.pos, 1.6)
				var size: int = maxi(8, roundi(q.size * 1.5))
				draw_string(font, at + Vector2(1, 1), q.text, HORIZONTAL_ALIGNMENT_CENTER, -1, size, Color(0, 0, 0, c.a * 0.8))
				draw_string(font, at, q.text, HORIZONTAL_ALIGNMENT_CENTER, -1, size, c)
			"flash":
				var at := stage.to_screen_h(q.pos, 1.1)
				var dir := Vector2.from_angle(q.a)
				var sc: float = q.scale * scale
				draw_circle(at, 5.0 * sc, Color(1, 0.95, 0.7, 0.9 * k))
				draw_line(at, at + dir * 18.0 * sc, Color(1, 0.85, 0.4, 0.8 * k), 4.0 * q.scale)
			"ring":
				var r: float = lerpf(q.r1, q.r0, k)
				var c: Color = q.color
				c.a = k
				_arc(q.pos, r, 0.0, TAU, c, 2.5)


## An arc on the ground, as the camera sees it: the points projected one by
## one, so a ring lies flat rather than standing up on the screen.
func _arc(at: Vector2, r: float, a0: float, a1: float, color: Color, width: float) -> void:
	var pts := PackedVector2Array()
	var n := 28
	for i in range(n + 1):
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(stage.to_screen(at + Vector2.from_angle(a) * r))
	draw_polyline(pts, color, width)
