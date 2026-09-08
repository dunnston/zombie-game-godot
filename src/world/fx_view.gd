class_name FxView
extends Node2D
## Tracers, blood, sparks, muzzle flashes, damage numbers, the swing arc.
## Fed by the sim's events each frame; keeps its own short-lived particles.
## Cosmetic only: nothing here changes game state.

var sim: GameSim
var particles: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()


func _init(sim_: GameSim) -> void:
	sim = sim_


func on_event(ev: Dictionary) -> void:
	match ev.t:
		"hit":
			_blood(Vector2(ev.x, ev.y), Vector2(ev.dx, ev.dy), 12 if ev.crit else 7)
			_text(Vector2(ev.x, ev.y - ev.r), str(roundi(ev.dmg)), Color("#ffe08a") if ev.crit else Color.WHITE, 15 if ev.crit else 12)
		"kill":
			_blood(Vector2(ev.x, ev.y), Vector2.ZERO, 16)
		"player_hit":
			_blood(Vector2(ev.x, ev.y), Vector2(ev.dx, ev.dy), 6, Color("#a02020"))
			_text(Vector2(ev.x, ev.y - 26), "-%d" % roundi(ev.dmg), Color("#ff8a7a"), 13)
		"player_died":
			_blood(Vector2(ev.x, ev.y), Vector2.ZERO, 26, Color("#a02020"))
		"bullet_wall":
			_sparks(Vector2(ev.x, ev.y), Vector2(ev.dx, ev.dy).normalized(), 4)
		"muzzle":
			var scale := 1.9 if ev.w == "shotgun" else (1.5 if ev.w == "rifle" else 1.0)
			particles.append({"kind": "flash", "pos": Vector2(ev.x, ev.y), "a": ev.a, "life": 0.06, "max": 0.06, "scale": scale})
		"chop", "bounce":
			_debris(Vector2(ev.x, ev.y), 4, Color("#4a3a22"))
		"harvest":
			_debris(Vector2(ev.x, ev.y), 14, Color("#3f5226") if ev.res == "wood" else Color("#6a6660"))
			_text(Vector2(ev.x, ev.y - 20), "%s +%d" % [ev.label, ev.n], Color(Config.RES[ev.res].color), 12, 1.0)
		"float":
			_text(Vector2(ev.x, ev.y), ev.text, Color(ev.color), 12, 0.7)
		"ring":
			particles.append({"kind": "ring", "pos": Vector2(ev.x, ev.y), "life": 0.45, "max": 0.45,
				"r0": float(ev.r0), "r1": float(ev.r1), "color": Color(ev.color)})
		"loot":
			# What came out of the container, stacked upward so the whole
			# haul is readable in one glance.
			var ly: float = ev.y - 12.0
			for line in ev.lines:
				_text(Vector2(ev.x, ly), line.text, Color(line.color), 12, 1.1)
				ly -= 15.0
			particles.append({"kind": "ring", "pos": Vector2(ev.x, ev.y), "life": 0.4, "max": 0.4,
				"r0": 4.0, "r1": 34.0, "color": Color("#ffe08a") if ev.major else Color("#c9a227")})
		"picked_up":
			particles.append({"kind": "ring", "pos": Vector2(ev.x, ev.y), "life": 0.22, "max": 0.22,
				"r0": 2.0, "r1": 14.0, "color": Color("#d8e8c0")})
		"heal":
			_text(Vector2(ev.x, ev.y - 24), "+%d" % roundi(ev.amount), Color("#7ce08a"), 13)
			particles.append({"kind": "ring", "pos": Vector2(ev.x, ev.y), "life": 0.4, "max": 0.4, "r0": 6.0, "r1": 40.0, "color": Color("#7ce08a")})
		"respawn":
			particles.append({"kind": "ring", "pos": Vector2(ev.x, ev.y), "life": 0.6, "max": 0.6, "r0": 6.0, "r1": 90.0, "color": Color("#9fd0ff")})
		"raid_end":
			for p in sim.players:
				particles.append({"kind": "ring", "pos": p.pos, "life": 0.9, "max": 0.9, "r0": 10.0, "r1": 200.0, "color": Color("#b7e08a") if ev.repelled else Color("#d9c46a")})


func _blood(at: Vector2, dir: Vector2, n: int, color := Color("#7a1a1a")) -> void:
	for i in range(n):
		var a := rng.randf_range(0.0, TAU)
		var sp := rng.randf_range(30.0, 140.0)
		var v := Vector2.from_angle(a) * sp + dir * 60.0
		particles.append({"kind": "dot", "pos": at, "vel": v, "life": rng.randf_range(0.25, 0.5), "max": 0.5, "color": color, "size": rng.randf_range(1.5, 3.5), "drag": 6.0})


func _sparks(at: Vector2, dir: Vector2, n: int) -> void:
	for i in range(n):
		var v := (dir + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))).normalized() * rng.randf_range(120.0, 260.0)
		particles.append({"kind": "dot", "pos": at, "vel": v, "life": 0.18, "max": 0.18, "color": Color("#cfd6dd"), "size": 1.5, "drag": 4.0})


func _debris(at: Vector2, n: int, color: Color) -> void:
	for i in range(n):
		var v := Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(40.0, 120.0)
		particles.append({"kind": "dot", "pos": at, "vel": v, "life": 0.4, "max": 0.4, "color": color, "size": 2.0, "drag": 5.0})


func _text(at: Vector2, text: String, color: Color, size: int, life := 0.7) -> void:
	particles.append({"kind": "text", "pos": at + Vector2(rng.randf_range(-4, 4), 0), "vel": Vector2(0, -40), "life": life, "max": life, "text": text, "color": color, "size": size})


func tick(dt: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var q := particles[i]
		q.life -= dt
		if q.life <= 0.0:
			particles.remove_at(i)
			continue
		if q.has("vel"):
			q.pos += q.vel * dt
			if q.has("drag"):
				q.vel *= exp(-q.drag * dt)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	# Tracers.
	for b in sim.bullets:
		var pos: Vector2 = b.pos
		var vel: Vector2 = b.vel
		var col := Color(b.color)
		var tail := pos - vel * 0.018
		draw_line(tail, pos, Color(col, 0.35), 3.0)
		draw_line(tail, pos, col, 1.5)
	# The swing arc.
	for p in sim.players:
		if p.swing.is_empty():
			continue
		var s: Dictionary = p.swing
		var k: float = 1.0 - s.t / s.dur
		var col := Color(1, 1, 1, 0.55 * k)
		draw_arc(p.pos, s.range - 4.0, s.angle - s.arc / 2.0, s.angle + s.arc / 2.0, 14, col, 4.0 * k + 1.0)
	for q in particles:
		var k: float = clampf(q.life / q.max, 0.0, 1.0)
		match q.kind:
			"dot":
				var c: Color = q.color
				c.a = k
				draw_circle(q.pos, q.size, c)
			"text":
				var c: Color = q.color
				c.a = minf(1.0, k * 2.0)
				draw_string(font, q.pos + Vector2(1, 1), q.text, HORIZONTAL_ALIGNMENT_CENTER, -1, q.size, Color(0, 0, 0, c.a * 0.8))
				draw_string(font, q.pos, q.text, HORIZONTAL_ALIGNMENT_CENTER, -1, q.size, c)
			"flash":
				var dir := Vector2.from_angle(q.a)
				var sc: float = q.scale
				draw_circle(q.pos, 5.0 * sc, Color(1, 0.95, 0.7, 0.9 * k))
				draw_line(q.pos, q.pos + dir * 18.0 * sc, Color(1, 0.85, 0.4, 0.8 * k), 4.0 * sc)
				draw_line(q.pos, q.pos + dir.rotated(0.5) * 9.0 * sc, Color(1, 0.85, 0.4, 0.6 * k), 2.0)
				draw_line(q.pos, q.pos + dir.rotated(-0.5) * 9.0 * sc, Color(1, 0.85, 0.4, 0.6 * k), 2.0)
			"ring":
				var r: float = lerpf(q.r1, q.r0, k)
				var c: Color = q.color
				c.a = k
				draw_arc(q.pos, r, 0.0, TAU, 40, c, 2.5)
