class_name PlayerView
extends Node2D
## Draws one player from their sim state: a seat-coloured ground ring for
## readability in a crowd, a body, a head, and the weapon pointing at the aim.

var p: PlayerSim


func _init(player: PlayerSim) -> void:
	p = player


func _draw() -> void:
	var c := p.pos
	var ring := Color(Config.PLAYER.colors[p.seat])
	draw_arc(c + Vector2(0, 8), 15, 0, TAU, 28, ring, 2.0)
	draw_circle(c + Vector2(2, 3), 13, Color(0, 0, 0, 0.25))
	draw_circle(c, 13, Color("#6c7a4b"))
	draw_circle(c, 13, Color("#3f4830"), false, 2.0)
	draw_circle(c + Vector2(0, -3), 6, Color("#d9b48f"))
	var dir := Vector2.from_angle(p.angle)
	draw_line(c + dir * 8, c + dir * 24, Color("#2b2b2b"), 4.0)
	if p.sprinting:
		var back := -dir
		for k: float in [-4.0, 0.0, 4.0]:
			var o := back.orthogonal() * k
			draw_line(c + back * 14 + o, c + back * 24 + o, Color(1, 1, 1, 0.25), 1.5)
