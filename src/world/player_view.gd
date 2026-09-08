class_name PlayerView
extends Node2D
## Draws one player from their sim state: a seat-coloured ground ring for
## readability in a crowd, a body, a head, and the weapon pointing at the aim.

var p: PlayerSim


func _init(player: PlayerSim) -> void:
	p = player


func _draw() -> void:
	# Interpolated, not raw: the sim steps at 60Hz and this draws at the
	# monitor's rate. See Util.render_pos.
	var c := Util.render_pos(p.prev_pos, p.pos)
	var ring := Color(Config.PLAYER.colors[p.seat])
	if p.dead:
		var pool := Color("#4a1010", 0.6)
		draw_circle(c, 22, pool)
		draw_line(c + Vector2(-9, -9), c + Vector2(9, 9), Color("#d9b48f"), 3.0)
		draw_line(c + Vector2(9, -9), c + Vector2(-9, 9), Color("#d9b48f"), 3.0)
		return
	# Invulnerable after a hit: blink.
	if p.invuln > 0.0 and int(p.invuln * 20.0) % 2 == 0:
		modulate.a = 0.55
	else:
		modulate.a = 1.0
	draw_arc(c + Vector2(0, 8), 15, 0, TAU, 28, ring, 2.0)
	draw_circle(c + Vector2(2, 3), 13, Color(0, 0, 0, 0.25))
	var body := Color("#6c7a4b")
	if p.hurt_flash > 0.0:
		body = body.lerp(Color("#c04040"), p.hurt_flash * 2.0)
	if p.sneaking:
		body = body.darkened(0.25)
	draw_circle(c, 13, body)
	draw_circle(c, 13, Color("#3f4830"), false, 2.0)
	draw_circle(c + Vector2(0, -3), 6, Color("#d9b48f"))
	var dir := Vector2.from_angle(p.angle)
	var w := p.weapon()
	var wcol := Color(w.get("color", "#2b2b2b"))
	if w.kind == "gun":
		draw_line(c + dir * 6, c + dir * 26, wcol.darkened(0.3), 5.0)
		draw_line(c + dir * 6, c + dir * 26, wcol, 3.0)
	else:
		var swung := 0.0
		if not p.swing.is_empty():
			swung = (p.swing.t / p.swing.dur - 0.5) * p.swing.arc
		var d := Vector2.from_angle(p.angle + swung)
		draw_line(c + d * 8, c + d * 24, wcol.darkened(0.3), 4.0)
		draw_line(c + d * 8, c + d * 24, wcol, 2.5)
	if not p.reloading.is_empty():
		var k: float = clampf(p.reloading.t / p.reloading.dur, 0.0, 1.0)
		draw_rect(Rect2(c.x - 14, c.y - 26, 28, 4), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(c.x - 14, c.y - 26, 28 * k, 4), Color("#ffe6a8"))
	if not p.using.is_empty():
		var k: float = clampf(p.using.t / p.using.dur, 0.0, 1.0)
		draw_rect(Rect2(c.x - 14, c.y - 26, 28, 4), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(c.x - 14, c.y - 26, 28 * k, 4), Color("#7ce08a"))
	if p.sprinting:
		var back := -dir
		for k: float in [-4.0, 0.0, 4.0]:
			var o := back.orthogonal() * k
			draw_line(c + back * 14 + o, c + back * 24 + o, Color(1, 1, 1, 0.25), 1.5)
