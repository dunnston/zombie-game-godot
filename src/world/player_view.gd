class_name PlayerView
extends Node2D
## Draws every player from their sim state: a seat-coloured ground ring for
## readability in a crowd, a body, a head, and the weapon pointing at the
## aim. Everyone else's name floats over them, because in co-op the one thing
## you must be able to do at a glance is tell your friend from the horde.

var sim: GameSim
## Whose screen this is. Drawn last, so you are never under a teammate.
var local: PlayerSim


func _init(sim_: GameSim, local_: PlayerSim = null) -> void:
	sim = sim_
	local = local_ if local_ != null else (sim_.players[0] if not sim_.players.is_empty() else null)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for p in sim.players:
		if p.away or p == local:
			continue
		_draw_player(font, p, false)
	if local != null and not local.away:
		_draw_player(font, local, true)


func _draw_player(font: Font, p: PlayerSim, is_local: bool) -> void:
	# Interpolated, not raw: the sim steps at 60Hz and this draws at the
	# monitor's rate. See Util.render_pos.
	var c := Util.render_pos(p.prev_pos, p.pos)
	var ring := Color(Config.PLAYER.colors[p.seat % Config.PLAYER.colors.size()])
	if p.dead:
		var pool := Color("#4a1010", 0.6)
		draw_circle(c, 22, pool)
		draw_line(c + Vector2(-9, -9), c + Vector2(9, 9), Color("#d9b48f"), 3.0)
		draw_line(c + Vector2(9, -9), c + Vector2(-9, 9), Color("#d9b48f"), 3.0)
		return
	if p.downed:
		# Flat, dim and urgent, the way a downed survivor reads: a ring that
		# counts down what is left of them.
		draw_circle(c, 24.0, Color("#e05a4a", 0.16))
		draw_arc(c, 22.0, 0.0, TAU * clampf(p.down_t / Config.PLAYER.downed_time, 0.0, 1.0), 28, Color("#e05a4a"), 2.5)
		draw_set_transform(c, 0.0, Vector2(1.5, 0.75))
		draw_circle(Vector2.ZERO, 13, Color("#5a4a3a"))
		draw_circle(Vector2.ZERO, 13, Color("#3f3025"), false, 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(c + Vector2(14, -2), 6, Color("#d9b48f"))
		var who := "YOU" if is_local else p.display_name
		draw_string(font, c + Vector2(-60, -30), "%s — DOWN" % who, HORIZONTAL_ALIGNMENT_CENTER, 120, 10, Color("#e05a4a"))
		return
	# Invulnerable after a hit: blink. Per player, not per node, so a
	# teammate's i-frames do not flicker you.
	var alpha := 1.0
	if p.invuln > 0.0 and int(p.invuln * 20.0) % 2 == 0:
		alpha = 0.55
	draw_arc(c + Vector2(0, 8), 15, 0, TAU, 28, Color(ring, alpha), 2.0)
	draw_circle(c + Vector2(2, 3), 13, Color(0, 0, 0, 0.25 * alpha))
	var body := Color("#6c7a4b")
	# What you are becoming, on the body itself. The tint follows the meter
	# rather than the band, so the change creeps rather than switching on —
	# but the band's colour is what it creeps toward, so the sprite and the
	# bar always agree about what you are.
	var mut := Mutation.fraction(p)
	if mut > 0.0:
		body = body.lerp(Color(String(Mutation.band_of(p).color)), mut * 0.55)
	if p.hurt_flash > 0.0:
		body = body.lerp(Color("#c04040"), p.hurt_flash * 2.0)
	if p.sneaking:
		body = body.darkened(0.25)
	body.a = alpha
	draw_circle(c, 13, body)
	draw_circle(c, 13, Color("#3f4830", alpha), false, 2.0)
	# The head goes with it, a little further: it is the readable half at a
	# glance in a crowd of four.
	draw_circle(c + Vector2(0, -3), 6, Color(Color("#d9b48f").lerp(Color(String(Mutation.band_of(p).color)), mut * 0.7), alpha))
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
	if not p.reviving.is_empty():
		var k: float = clampf(p.reviving.t / p.reviving.dur, 0.0, 1.0)
		draw_rect(Rect2(c.x - 14, c.y - 26, 28, 4), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(c.x - 14, c.y - 26, 28 * k, 4), Color("#9fd0ff"))
	if p.dash_t > 0.0:
		# Three fading after-images back along the burst, so a dodge reads in
		# a crowd as a dodge and not as a teleport. A remote player's
		# direction is not on the wire; the step it just took is.
		var along := p.dash_dir if p.dash_dir != Vector2.ZERO else (p.pos - p.prev_pos).normalized()
		if along != Vector2.ZERO:
			for i in range(1, 4):
				draw_circle(c - along * 16.0 * i, 13.0 - i * 2.0, Color(ring, 0.28 - i * 0.07))
	if p.sprinting:
		var back := -dir
		for k: float in [-4.0, 0.0, 4.0]:
			var o := back.orthogonal() * k
			draw_line(c + back * 14 + o, c + back * 24 + o, Color(1, 1, 1, 0.25), 1.5)
	if not is_local:
		# A name over everyone who is not you, in their ring colour, plus a
		# sliver of health once it matters.
		draw_string(font, c + Vector2(-50, -30), p.display_name, HORIZONTAL_ALIGNMENT_CENTER, 100, 10, ring)
		if p.hp < p.max_hp:
			var bar := Rect2(c.x - 14, c.y - 24, 28, 3)
			draw_rect(bar, Color(0, 0, 0, 0.55))
			draw_rect(Rect2(bar.position, Vector2(28 * clampf(p.hp / p.max_hp, 0.0, 1.0), 3)), Color("#c8423a"))
