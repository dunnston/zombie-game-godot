class_name Hud
extends Control
## The in-game overlay. Phase 1: where you are, how dangerous it is, health
## and stamina. Drawn in CSS-style pixels on a CanvasLayer.

const TIER_COLORS := [Color.WHITE, Color("#9fd07a"), Color("#e0c24a"), Color("#e07a3a"), Color("#d4403a")]

var sim: GameSim


func _init(sim_: GameSim) -> void:
	sim = sim_
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var p := sim.players[0]
	var vp := get_viewport_rect().size

	# Where you are.
	var loc := sim.world.location_at_px(p.pos.x, p.pos.y)
	var label: String = loc.name if not loc.is_empty() else "THE OUTSKIRTS"
	var tier := sim.world.danger_at_px(p.pos.x, p.pos.y)
	draw_string(font, Vector2(1, 33), label, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 20, Color(0, 0, 0, 0.7))
	draw_string(font, Vector2(0, 32), label, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 20, Color("#ebe6d6"))
	draw_string(font, Vector2(0, 52), "danger " + "◆".repeat(tier), HORIZONTAL_ALIGNMENT_CENTER, vp.x, 13, TIER_COLORS[tier])

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

	# Debug corner.
	var dbg := "%d fps   tile %d,%d" % [Engine.get_frames_per_second(), int(p.pos.x / 32), int(p.pos.y / 32)]
	draw_string(font, Vector2(vp.x - 240, vp.y - 12), dbg, HORIZONTAL_ALIGNMENT_RIGHT, 230, 11, Color(1, 1, 1, 0.5))
