class_name Hud
extends Control
## The in-game overlay: where you are and how dangerous it is, health and
## stamina, what you are holding and how much is left, the Threat meter,
## the raid banner and the notices. Drawn in CSS-style pixels on a
## CanvasLayer. Reads the sim; changes nothing.

const TIER_COLORS := [Color.WHITE, Color("#9fd07a"), Color("#e0c24a"), Color("#e07a3a"), Color("#d4403a")]

var sim: GameSim
var notices: Array[Dictionary] = []
var hurt := 0.0


func _init(sim_: GameSim) -> void:
	sim = sim_
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func on_event(ev: Dictionary) -> void:
	match ev.t:
		"notify":
			notices.append({"text": ev.text, "color": Color(ev.color), "life": 5.5 if ev.important else 3.5, "max": 5.5 if ev.important else 3.5, "big": ev.important})
			if notices.size() > 6:
				notices.pop_front()
		"player_hit":
			hurt = clampf(ev.dmg / 45.0, 0.18, 0.7)
		"player_died":
			hurt = 0.9


func tick(dt: float) -> void:
	hurt = maxf(0.0, hurt - dt * 1.6)
	for i in range(notices.size() - 1, -1, -1):
		notices[i].life -= dt
		if notices[i].life <= 0.0:
			notices.remove_at(i)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var p := sim.players[0]
	var vp := get_viewport_rect().size

	# Hurt vignette.
	if hurt > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vp), Color("#8c1a1a", hurt * 0.45))

	# Where you are.
	var loc := sim.world.location_at_px(p.pos.x, p.pos.y)
	var label: String = loc.name if not loc.is_empty() else "THE OUTSKIRTS"
	var tier := sim.world.danger_at_px(p.pos.x, p.pos.y)
	draw_string(font, Vector2(1, 33), label, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 20, Color(0, 0, 0, 0.7))
	draw_string(font, Vector2(0, 32), label, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 20, Color("#ebe6d6"))
	draw_string(font, Vector2(0, 52), "danger " + "◆".repeat(tier), HORIZONTAL_ALIGNMENT_CENTER, vp.x, 13, TIER_COLORS[tier])

	# The raid banner.
	var raid := sim.raid
	if raid != null:
		var y := 70.0
		if raid.phase == "warning":
			var text := "%s INCOMING — %ds" % [raid.spec.name, ceili(raid.timer)]
			draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 18, Color("#e05a4a"))
		else:
			var text := "%s — WAVE %d/%d — %d left" % [raid.spec.name, raid.wave, raid.spec.waves, raid.total - raid.killed]
			draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 18, Color("#e05a4a"))

	# Bars, bottom left.
	var x := 20.0
	var y := vp.y - 62.0
	var w := 220.0
	draw_rect(Rect2(x, y, w, 14), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(x, y, w * clampf(p.hp / p.max_hp, 0, 1), 14), Color("#c8423a"))
	draw_string(font, Vector2(x + 6, y + 11), "HP %d" % roundi(p.hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	y += 20
	draw_rect(Rect2(x, y, w, 14), Color(0, 0, 0, 0.55))
	var stam_col := Color("#8a8a7a") if p.winded else Color("#e0c24a")
	draw_rect(Rect2(x, y, w * clampf(p.stam / p.max_stam, 0, 1), 14), stam_col)
	draw_string(font, Vector2(x + 6, y + 11), "STAMINA" + ("  —  WINDED" if p.winded else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

	# Threat meter, top right.
	var tx := vp.x - 240.0
	var ty := 24.0
	draw_string(font, Vector2(tx, ty), "THREAT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ebe6d6"))
	draw_rect(Rect2(tx + 52, ty - 10, 168, 12), Color(0, 0, 0, 0.55))
	var tcol := Color(sim.threat.color())
	draw_rect(Rect2(tx + 52, ty - 10, 168 * clampf(sim.threat.value / Config.THREAT.max, 0, 1), 12), tcol)
	for warn: float in Config.THREAT.warn_at:
		var wx := tx + 52 + 168 * warn / Config.THREAT.max
		draw_line(Vector2(wx, ty - 10), Vector2(wx, ty + 2), Color(1, 1, 1, 0.4), 1.0)
	draw_string(font, Vector2(tx + 52, ty + 14), sim.threat.label(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tcol)

	# The hotbar: what you hold and what is in it.
	var slot_w := 74.0
	var sx := vp.x / 2.0 - slot_w * p.loadout.size() / 2.0
	var sy := vp.y - 58.0
	for i in range(p.loadout.size()):
		var wpn: Dictionary = Config.WEAPONS[p.loadout[i]]
		var r := Rect2(sx + i * slot_w, sy, slot_w - 4, 44)
		draw_rect(r, Color(0, 0, 0, 0.6 if i == p.slot else 0.4))
		draw_rect(r, Color(wpn.get("color", "#888888")) if i == p.slot else Color(1, 1, 1, 0.15), false, 2.0 if i == p.slot else 1.0)
		draw_string(font, Vector2(r.position.x + 4, r.position.y + 12), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.5))
		draw_string(font, Vector2(r.position.x, r.position.y + 25), wpn.name, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 10, Color.WHITE)
		if wpn.kind == "gun":
			var ammo := "%d / %d" % [p.mag.get(wpn.id, 0), p.count_res(wpn.ammo)]
			draw_string(font, Vector2(r.position.x, r.position.y + 39), ammo, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 10, Color("#ffe6a8"))
		elif wpn.get("tool", false):
			draw_string(font, Vector2(r.position.x, r.position.y + 39), "tool", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 9, Color(1, 1, 1, 0.5))
	# Reload and healing.
	if not p.reloading.is_empty():
		draw_string(font, Vector2(0, sy - 8), "RELOADING", HORIZONTAL_ALIGNMENT_CENTER, vp.x, 11, Color("#ffe6a8"))
	var meds := "Q  bandage x%d  medkit x%d" % [p.count_res("bandage"), p.count_res("medkit")]
	draw_string(font, Vector2(sx + slot_w * p.loadout.size() + 8, sy + 30), meds, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.6))

	# Notices, left of centre, newest at the bottom.
	var ny := vp.y * 0.42
	for n in notices:
		var k: float = clampf(n.life / minf(1.0, n.max), 0.0, 1.0)
		var col: Color = n.color
		col.a = k
		var size := 15 if n.big else 12
		draw_string(font, Vector2(21, ny + 1), n.text, HORIZONTAL_ALIGNMENT_LEFT, vp.x - 40, size, Color(0, 0, 0, k * 0.8))
		draw_string(font, Vector2(20, ny), n.text, HORIZONTAL_ALIGNMENT_LEFT, vp.x - 40, size, col)
		ny += size + 6

	if p.dead:
		draw_string(font, Vector2(0, vp.y / 2.0 - 10), "YOU DIED", HORIZONTAL_ALIGNMENT_CENTER, vp.x, 34, Color("#e05a4a"))
		draw_string(font, Vector2(0, vp.y / 2.0 + 16), "respawning in %.1f" % maxf(0.0, p.respawn_t), HORIZONTAL_ALIGNMENT_CENTER, vp.x, 13, Color("#ebe6d6"))

	# Debug corner.
	var dbg := "%d fps   tile %d,%d   enemies %d   kills %d" % [Engine.get_frames_per_second(), int(p.pos.x / 32), int(p.pos.y / 32), sim.enemies.alive_count(), sim.stats.kills]
	draw_string(font, Vector2(vp.x - 340, vp.y - 12), dbg, HORIZONTAL_ALIGNMENT_RIGHT, 330, 11, Color(1, 1, 1, 0.5))
