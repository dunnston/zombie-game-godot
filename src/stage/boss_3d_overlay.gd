class_name Boss3DOverlay
extends BossView
## `BossView`'s telegraphs over the 3D stage: the same events, the same
## clocks, the shapes laid on the ground as the camera sees them. A
## telegraph is a promise about where something will land (§8.4), so the
## ring and the lane are projected point by point and not drawn flat on
## the screen where they would lie about the ground.

var stage: Stage3D


func _init(sim_: GameSim, stage_: Stage3D) -> void:
	super(sim_)
	stage = stage_


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var red := Color(0.95, 0.3, 0.2)
	for tl in tells:
		var k := clampf(float(tl.t) / float(tl.dur), 0.0, 1.0)
		var at: Vector2 = tl.at
		var to: Vector2 = tl.to
		var d := (to - at).normalized() if (to - at).length_squared() > 1.0 else Vector2.RIGHT
		match String(tl.move):
			"slam":
				_disc(at, tl.r, Color(red, 0.10))
				_ring(at, tl.r, Color(red, 0.85), 3.0)
				_disc(at, tl.r * k, Color(red, 0.26))
			"charge":
				_lane(at, at + d * float(tl.dist), 28.0, Color(red, 0.16))
				_lane(at, at + d * float(tl.dist) * k, 28.0, Color(red, 0.32))
				var end := at + d * float(tl.dist)
				draw_line(stage.to_screen(end + d.orthogonal() * 28.0), stage.to_screen(end - d.orthogonal() * 28.0), Color(red, 0.85), 3.0)
			"hook":
				var wide: float = float(tl.width)
				var end := at + d * float(tl.dist)
				_lane(at, end, wide, Color(red, 0.14))
				_lane(end, end - d * float(tl.dist) * k, wide, Color(red, 0.34))
				draw_circle(stage.to_screen(end), stage.screen_radius(end, 7.0), Color(red, 0.9))
			"dodgeball":
				var n: int = tl.n
				for i in range(n):
					var off: float = 0.0 if n <= 1 else (i - (n - 1) / 2.0) * float(tl.fan) / (n - 1)
					var ray := d.rotated(off)
					draw_line(stage.to_screen(at + ray * 30.0), stage.to_screen(at + ray * (60.0 + 200.0 * k)), Color(red, 0.55), 3.0)
			"whistle":
				_ring(at, 30.0 + 70.0 * k, Color("#ffe08a", 1.0 - k), 3.0)
				draw_string(font, stage.to_screen_h(at, 2.6) + Vector2(-8, 0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("#ffe08a"))
	for e in sim.enemies.list:
		if e.dead or not e.def.get("boss", false):
			continue
		var c := Util.render_pos(e.prev_pos, e.pos)
		var ph: int = phase_of.get(e.id, 0)
		if ph > 0:
			var col: Color = PHASE_COLOR[mini(ph, PHASE_COLOR.size()) - 1]
			_ring(c, e.r + 8.0 + sin(e.anim * 3.0) * 2.0, Color(col, 0.8), 3.0)
		for s in stuns:
			if int(s.id) == e.id:
				var head := stage.to_screen_h(c, 2.4)
				for j in range(3):
					var a := float(s.t) * 4.0 + j * TAU / 3.0
					draw_circle(head + Vector2(cos(a) * 18.0, sin(a) * 5.0), 3.0, Color("#ffe08a"))


func _points(at: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(40):
		pts.append(stage.to_screen(at + Vector2.from_angle(TAU * i / 40.0) * r))
	return pts


func _ring(at: Vector2, r: float, color: Color, width: float) -> void:
	var pts := _points(at, r)
	pts.append(pts[0])
	draw_polyline(pts, color, width)


func _disc(at: Vector2, r: float, color: Color) -> void:
	if r <= 0.5:
		return
	draw_colored_polygon(_points(at, r), color)


func _lane(from: Vector2, to: Vector2, half_w: float, color: Color) -> void:
	if from.distance_squared_to(to) < 1.0:
		return
	var side := (to - from).normalized().orthogonal() * half_w
	draw_colored_polygon(PackedVector2Array([
		stage.to_screen(from + side), stage.to_screen(to + side),
		stage.to_screen(to - side), stage.to_screen(from - side)]), color)
