class_name SurvivorView
extends Node2D
## Your people, and the ones still out there.
##
## Drawn like the enemies are — a body, arms toward what they are aiming at,
## and a job badge — but readably *not* enemies: everyone wears a pale ground
## ring in their job's colour, because the one thing that must never happen is
## shooting one of your own in a crowd (pillar 4).

const R := Config.SURVIVOR.r

var sim: GameSim


func _init(sim_: GameSim) -> void:
	sim = sim_
	z_index = 3


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

	# Rescues first, so a person you have taken in draws over the marker.
	for rescue in sim.crew.rescues:
		var at: Vector2 = rescue.pos
		if at.x < tl.x or at.x > br.x or at.y < tl.y or at.y > br.y:
			continue
		_draw_rescue(font, at, String(rescue.name))

	for s in sim.crew.list:
		if s.dead or s.pos.x < tl.x or s.pos.x > br.x or s.pos.y < tl.y or s.pos.y > br.y:
			continue
		_draw_survivor(font, s)


## Somebody holed up waiting. Deliberately a soft pulse rather than a marker:
## it should read as a person from a distance, not as a quest icon.
func _draw_rescue(font: Font, at: Vector2, who: String) -> void:
	var pulse := 0.5 + 0.5 * sin(sim.time * 2.4)
	draw_circle(at, 16.0 + 4.0 * pulse, Color("#b7e08a", 0.10 + 0.10 * pulse))
	draw_arc(at, 15.0, 0.0, TAU, 22, Color("#b7e08a", 0.55), 1.5)
	draw_circle(at + Vector2(2, 3), R * 0.8, Color(0, 0, 0, 0.25))
	draw_circle(at, R * 0.8, Color("#6a7a5a"))
	draw_string(font, at + Vector2(-40, -22), who, HORIZONTAL_ALIGNMENT_CENTER, 80, 10, Color("#b7e08a"))


func _draw_survivor(font: Font, s: SurvivorSim) -> void:
	var c := Util.render_pos(s.prev_pos, s.pos)
	var job: Dictionary = Config.JOBS.get(s.job, Config.JOBS.guard)
	var ring := Color(String(job.color))

	draw_circle(c + Vector2(3, 4), R, Color(0, 0, 0, 0.22))
	# The ground ring is the readability rule: one of yours, at a glance, in a
	# crowd. Downed reads differently again — flat, dim, and urgent.
	if s.downed:
		draw_circle(c, R + 9.0, Color("#e05a4a", 0.16))
		draw_arc(c, R + 8.0, 0.0, TAU * clampf(s.down_t / Config.SURVIVOR.revive_time, 0.0, 1.0), 24,
			Color("#e05a4a"), 2.0)
		draw_circle(c, R * 0.9, Color("#6a5550"))
		draw_string(font, c + Vector2(-50, -20), "%s — help" % s.display_name,
			HORIZONTAL_ALIGNMENT_CENTER, 100, 10, Color("#e05a4a"))
		return

	draw_arc(c, R + 5.0, 0.0, TAU, 22, Color(ring, 0.7), 1.5)

	var body := Color(s.tint)
	if s.flash > 0.0:
		body = body.lerp(Color.WHITE, 0.7)
	if s.hungry:
		body = body.lerp(Color("#8a7a4a"), 0.35)

	var dir := Vector2.from_angle(s.angle)
	var side := dir.orthogonal()
	# Arms toward whatever they are aiming at, so you can read what they have
	# seen before you can see it yourself.
	for k: float in [-1.0, 1.0]:
		var a := c + side * (R * 0.55 * k)
		var tip := c + dir * (R + 7.0) + side * (R * 0.3 * k)
		draw_line(a, tip, body.darkened(0.35), 3.0)
	draw_circle(c, R, body)
	draw_circle(c + dir * 3.0, R * 0.55, body.lightened(0.18))

	# Health, but only once it matters — a full bar over everyone is noise.
	if s.hp < s.max_hp:
		var w := 24.0
		var bar := Rect2(c.x - w / 2.0, c.y - R - 9.0, w, 3.0)
		draw_rect(bar, Color(0, 0, 0, 0.55))
		draw_rect(Rect2(bar.position, Vector2(w * clampf(s.hp / s.max_hp, 0.0, 1.0), bar.size.y)),
			Color("#7ec46a"))

	var tag := String(job.short)
	if s.posted:
		tag += "*"                            # up the tower, not walking to it
	if s.out_of_ammo:
		tag += " !"
	draw_string(font, c + Vector2(-30, R + 14.0), tag, HORIZONTAL_ALIGNMENT_CENTER, 60, 9, Color(ring, 0.8))
	if not s.carrying.is_empty() or not s.carry_items.is_empty():
		draw_string(font, c + Vector2(-30, R + 24.0), "hauling", HORIZONTAL_ALIGNMENT_CENTER, 60, 8,
			Color("#e8c86a", 0.7))
