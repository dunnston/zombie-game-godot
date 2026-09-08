class_name EnemyView
extends Node2D
## Draws every enemy and corpse from the sim. Readability first: each tier
## is a different size and colour, a wind-up raises the arms so a bite is
## telegraphed, and a hurt one flashes and shows a bar.

const SHADOW := Color(0, 0, 0, 0.25)

var sim: GameSim


func _init(sim_: GameSim) -> void:
	sim = sim_


func _draw() -> void:
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var tl := inv * Vector2.ZERO - Vector2(64, 64)
	var br := inv * get_viewport_rect().size + Vector2(64, 64)

	for c in sim.enemies.corpses:
		if c.x < tl.x or c.x > br.x or c.y < tl.y or c.y > br.y:
			continue
		var def: Dictionary = Config.ENEMIES[c.type]
		var fade: float = clampf(1.0 - c.t / c.life, 0.0, 1.0)
		var col := Color(def.dark)
		col.a = 0.75 * fade
		draw_set_transform(Vector2(c.x, c.y), c.angle, Vector2(1.5, 0.8))
		draw_circle(Vector2.ZERO, def.r, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var pool := Color("#4a1010")
		pool.a = 0.35 * fade
		draw_circle(Vector2(c.x, c.y), def.r * 1.3, pool)

	var list: Array[EnemySim] = []
	for e in sim.enemies.list:
		if e.dead or e.pos.x < tl.x or e.pos.x > br.x or e.pos.y < tl.y or e.pos.y > br.y:
			continue
		list.append(e)
	list.sort_custom(func(a: EnemySim, b: EnemySim) -> bool: return a.pos.y < b.pos.y)
	for e in list:
		_draw_enemy(e)


func _draw_enemy(e: EnemySim) -> void:
	var c := Util.render_pos(e.prev_pos, e.pos)
	var body := Color(e.def.body)
	var dark := Color(e.def.dark)
	if e.flash > 0.0:
		body = body.lerp(Color.WHITE, 0.7)
	# Alight. Read straight off the burn timer rather than from events: a burn
	# ticks sixty times a second and one particle per tick is thousands of
	# them per corpse, which is exactly what the damage path no longer emits.
	if e.burn_t > 0.0:
		body = body.lerp(Color("#ff7a2a"), 0.45 + 0.2 * sin(e.anim * 3.0))
		dark = dark.lerp(Color("#8a2a10"), 0.5)
	var dir := Vector2.from_angle(e.angle)
	var side := dir.orthogonal()
	var bob := sin(e.anim) * 1.5

	draw_circle(c + Vector2(3, 4), e.r, SHADOW)
	# Arms: out in front, raised wide during the wind-up.
	var reach := e.r + (10.0 if e.windup > 0.0 else 6.0)
	var spread := 0.55 if e.windup > 0.0 else 0.35
	for s: float in [-1.0, 1.0]:
		var a := c + side * (e.r * 0.6 * s)
		var tip := c + (dir.rotated(spread * s)) * reach + side * (e.r * 0.3 * s)
		draw_line(a, tip, dark, 3.0)
		draw_circle(tip, 2.5, body)
	draw_circle(c, e.r, body)
	draw_circle(c, e.r, dark, false, 2.0)
	# Head, leaning toward where it faces.
	draw_circle(c + dir * (e.r * 0.35) + Vector2(0, bob - 2.0), e.r * 0.5, body.lightened(0.12))
	draw_circle(c + dir * (e.r * 0.35) + Vector2(0, bob - 2.0), e.r * 0.5, dark, false, 1.5)
	if e.raid:
		draw_circle(c + Vector2(0, -e.r - 6), 2.0, Color("#e05a4a"))
	if e.hp < e.max_hp:
		var w := e.r * 2.0
		var y := c.y - e.r - 8.0
		draw_rect(Rect2(c.x - w / 2.0, y, w, 3), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(c.x - w / 2.0, y, w * clampf(e.hp / e.max_hp, 0.0, 1.0), 3), Color("#c8423a"))
