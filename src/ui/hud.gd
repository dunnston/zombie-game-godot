class_name Hud
extends Control
## The in-game overlay: where you are and how dangerous it is, health and
## stamina, what you are holding and how much is left, the Threat meter,
## the raid banner and the notices. Drawn in CSS-style pixels on a
## CanvasLayer. Reads the sim; changes nothing.

const TIER_COLORS := [Color.WHITE, Color("#9fd07a"), Color("#e0c24a"), Color("#e07a3a"), Color("#d4403a")]

var sim: GameSim
## Whose bars these are: the local player, whatever seat they hold.
var player: PlayerSim = null
## What the scene knows about the connection, for the corner line.
var net_line := ""
var notices: Array[Dictionary] = []
var hurt := 0.0
## What the death screen calls it. Turning is a death with its own word.
var death_cause := "died"


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
			death_cause = String(ev.get("cause", "died"))


func tick(dt: float) -> void:
	hurt = maxf(0.0, hurt - dt * 1.6)
	for i in range(notices.size() - 1, -1, -1):
		notices[i].life -= dt
		if notices[i].life <= 0.0:
			notices.remove_at(i)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var p: PlayerSim = player if player != null else sim.players[0]
	var vp := get_viewport_rect().size

	# Hurt vignette.
	if hurt > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vp), Color("#8c1a1a", hurt * 0.45))

	# The change, on the screen itself. It starts at the top band and grows
	# with how far into it you are, and it *breathes* — a still tint reads as
	# a bug, a slow pulse reads as something inside you. A Lurch is the same
	# colour turned all the way up, so the moment your legs stop being yours
	# looks like the thing that took them.
	var feral_at := float(Config.MUTATION.bands[Config.MUTATION.bands.size() - 1].at)
	var over := clampf((p.mutation - feral_at) / maxf(1.0, float(Config.MUTATION.max) - feral_at), 0.0, 1.0)
	if over > 0.0 or p.lurch_t > 0.0:
		var pulse := 0.62 + 0.38 * sin(sim.time * 2.4)
		var a := 0.06 + 0.14 * over * pulse
		if p.lurch_t > 0.0:
			a = 0.34
		draw_rect(Rect2(Vector2.ZERO, vp), Color("#b07ad0", a))
		if p.lurch_t > 0.0:
			draw_string(font, Vector2(0, vp.y * 0.34), "SOMETHING ELSE IS DRIVING",
				HORIZONTAL_ALIGNMENT_CENTER, vp.x, 26, Color("#e0c0ff"))

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
		# The living get their own colour. A horde and a raiding party want
		# completely different answers, and the banner is where you find out
		# which one is coming.
		var rcol := Color("#d0a06a") if raid.human else Color("#e05a4a")
		if raid.phase == "warning":
			var text := "%s INCOMING — %ds" % [raid.spec.name, ceili(raid.timer)]
			draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 18, rcol)
		else:
			var text := "%s — WAVE %d/%d — %d left" % [raid.spec.name, raid.wave, raid.spec.waves, raid.total - raid.killed]
			draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 18, rcol)

	# Bars, bottom left. The block grows upward from the hotbar row, so adding
	# one does not push the others into it.
	var x := 20.0
	var y := vp.y - 92.0
	var w := 220.0
	draw_rect(Rect2(x, y, w, 14), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(x, y, w * clampf(p.hp / p.max_hp, 0, 1), 14), Color("#c8423a"))
	draw_string(font, Vector2(x + 6, y + 11), "HP %d" % roundi(p.hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	y += 20
	draw_rect(Rect2(x, y, w, 14), Color(0, 0, 0, 0.55))
	var stam_col := Color("#8a8a7a") if p.winded else Color("#e0c24a")
	draw_rect(Rect2(x, y, w * clampf(p.stam / p.max_stam, 0, 1), 14), stam_col)
	draw_string(font, Vector2(x + 6, y + 11), "STAMINA" + ("  —  WINDED" if p.winded else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

	# Mutation. The main status: how far along the change is, and which band
	# you are in — which is what is actually moving your numbers. Human at the
	# left end, gone at the right, and the fill takes the band's colour so a
	# glance is enough.
	y += 20
	var band := Mutation.band_of(p)
	var mcol := Color(String(band.color))
	draw_rect(Rect2(x, y, w, 14), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(x, y, w * Mutation.fraction(p), 14), mcol)
	for b in Config.MUTATION.bands:
		var bx := x + w * float(b.at) / float(Config.MUTATION.max)
		if bx > x:
			draw_line(Vector2(bx, y), Vector2(bx, y + 14), Color(1, 1, 1, 0.35), 1.0)
	draw_string(font, Vector2(x + 6, y + 11), "MUTATION  %s" % String(band.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	draw_string(font, Vector2(x, y + 11), "%d%%" % roundi(p.mutation), HORIZONTAL_ALIGNMENT_RIGHT, w - 6, 11, Color.WHITE)
	# What is working through you, if anything: a meal, a Surge, or a raw
	# brain still being regretted. Above the block rather than beside it —
	# to the right is the weight bar, and two readouts sharing a line is how
	# you get "Fed 300s" written through "221 / 225".
	if not p.effects.is_empty():
		var chips := PackedStringArray()
		for id in p.effects:
			chips.append("%s %ds" % [String(Config.EFFECTS[id].name), ceili(float(p.effects[id]))])
		draw_string(font, Vector2(x, vp.y - 96.0), "  ·  ".join(chips), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.7))

	# Level and progress to the next one, under the other two bars. A point
	# waiting to be spent says so here, because the character sheet is behind
	# a key you have to remember to press.
	y += 20
	draw_rect(Rect2(x, y, w, 8), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(x, y, w * clampf(p.xp / maxf(1.0, float(p.xp_next)), 0, 1), 8), Color("#9fd0ff"))
	draw_string(font, Vector2(x + 6, y + 7), "LV %d" % p.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)
	if p.skill_points > 0:
		draw_string(font, Vector2(x, y + 7), "%d POINT%s  ·  %s" % [p.skill_points, "" if p.skill_points == 1 else "S", KeyBinds.primary_label("character")],
			HORIZONTAL_ALIGNMENT_RIGHT, w - 6, 9, Color("#ffe08a"))

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

	# The clock, under the Threat meter. Night is the other thing driving how
	# dangerous the next few minutes are, so the two belong together.
	var dark: float = float(sim.clock.darkness().alpha)
	var pcol := Color("#d0c46a")
	if sim.clock.phase == "dusk":
		pcol = Color("#d98a4a")
	elif sim.clock.phase == "night":
		pcol = Color("#8f9ad0")
	draw_string(font, Vector2(tx, ty + 34), "DAY %d" % sim.clock.day, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ebe6d6"))
	draw_string(font, Vector2(tx + 52, ty + 34), "%s  %s" % [sim.clock.clock_string(), sim.clock.phase_name()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, pcol)
	# A thin bar of the day, so you can see how long is left of the light.
	var cb := Rect2(tx + 52, ty + 40, 168, 4)
	draw_rect(cb, Color(0, 0, 0, 0.55))
	draw_rect(Rect2(cb.position, Vector2(cb.size.x * sim.clock.t, cb.size.y)), pcol)
	# Readable, and specific about the next step: the first playtest found a
	# faint "T for a light" easy to miss, and a torch in the pack is not a
	# torch in the off-hand. A light in the off-hand now strikes itself, so
	# there are only three ways to be in the dark unlit, and the hint names
	# whichever one it is.
	var lamp: Dictionary = Equipment.equipped_light(p)
	if sim.clock.is_dark() and not p.lit:
		var key := KeyBinds.primary_label("light")
		# Short: this column is 220px wide and the first cut ran off the screen.
		# Nothing worn; worn but put out on purpose; or worn and flat, which
		# only a flashlight can be — a spent torch is gone. Which of the last
		# two is read off the fuel rather than `light_doused`, because fuel is
		# in the per-frame snapshot and a guest's copy of the flag is not.
		var hint := "dark — wear a Torch in your off-hand"
		if not lamp.is_empty():
			hint = "dark — %s to light it again" % key if p.light_fuel > 0.0 \
				else "%s is flat — %s loads a battery" % [String(lamp.name), key]
		draw_string(font, Vector2(tx, ty + 58), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.95, 0.75, 0.4, 0.6 + 0.4 * dark))
	elif p.lit and not lamp.is_empty():
		# What is left of it. A torch that burns out in the middle of a field is
		# the difference between a bad night and an unfair one, so the burn-down
		# is on the screen rather than a surprise.
		var burn: float = maxf(1.0, float(lamp.get("burn", 1.0)))
		var left: float = clampf(p.light_fuel / burn, 0.0, 1.0)
		draw_string(font, Vector2(tx, ty + 58), "%s  %ds" % [String(lamp.name), roundi(p.light_fuel)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#e0913a"))
		var lb := Rect2(tx + 96, ty + 50, 124, 4)
		draw_rect(lb, Color(0, 0, 0, 0.55))
		draw_rect(Rect2(lb.position, Vector2(lb.size.x * left, lb.size.y)),
			Color("#e0913a") if left > 0.25 else Color("#c96a5a"))

	# The hotbar: six slots, and the selected one is what you are holding.
	var slot_w := 74.0
	var n_slots := p.hotbar.size()
	var sx := vp.x / 2.0 - slot_w * n_slots / 2.0
	var sy := vp.y - 58.0
	for i in range(n_slots):
		var stack := p.hotbar.at(i)
		var id: String = stack.get("id", "")
		var r := Rect2(sx + i * slot_w, sy, slot_w - 4, 44)
		draw_rect(r, Color(0, 0, 0, 0.6 if i == p.slot else 0.4))
		var edge := Color(Items.color_of(id)) if not id.is_empty() else Color("#888888")
		draw_rect(r, edge if i == p.slot else Color(1, 1, 1, 0.15), false, 2.0 if i == p.slot else 1.0)
		draw_string(font, Vector2(r.position.x + 4, r.position.y + 12), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.5))
		if id.is_empty():
			continue
		draw_string(font, Vector2(r.position.x, r.position.y + 25), Items.name_of(id), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 10, Color.WHITE)
		# Real art sits in the corner when the item has some; without it the
		# slot is exactly what it always was.
		var tex := Items.icon_of(id)
		if tex != null:
			draw_texture_rect(tex, Items.art_rect(tex, Rect2(r.position.x + r.size.x - 21, r.position.y + 2, 18, 18)), false)
		# A sliver of condition along the bottom of the slot, and only once
		# there is something to say. A weapon must never break as a surprise:
		# this is the warning the notifications punctuate, not replace.
		if Wear.is_worn(p.hotbar, i):
			var frac := Wear.frac(p.hotbar, i)
			var wb := Rect2(r.position.x + 4, r.position.y + r.size.y - 4, r.size.x - 8, 3)
			draw_rect(wb, Color(0, 0, 0, 0.55))
			var wcol := Color("#9fd07a")
			if frac <= Config.WEAR.spent_at:
				wcol = Color("#c96a5a")
			elif frac <= Config.WEAR.worn_at:
				wcol = Color("#d9c46a")
			draw_rect(Rect2(wb.position, Vector2(wb.size.x * frac, wb.size.y)), wcol)
		var wpn: Dictionary = Config.WEAPONS.get(id, {})
		if Wear.is_broken(p.hotbar, i):
			draw_string(font, Vector2(r.position.x, r.position.y + 39), "BROKEN", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 10, Color("#c96a5a"))
		elif wpn.get("kind", "") == "gun":
			var ammo := "%d / %d" % [p.mag.get(id, 0), p.count_res(wpn.ammo)]
			draw_string(font, Vector2(r.position.x, r.position.y + 39), ammo, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 10, Color("#ffe6a8"))
		elif wpn.get("tool", false):
			draw_string(font, Vector2(r.position.x, r.position.y + 39), "tool", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 9, Color(1, 1, 1, 0.5))
		elif stack.n > 1:
			draw_string(font, Vector2(r.position.x, r.position.y + 39), "x%d" % stack.n, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 10, Color(1, 1, 1, 0.7))
	# Reload and healing.
	if not p.reloading.is_empty():
		draw_string(font, Vector2(0, sy - 8), "RELOADING", HORIZONTAL_ALIGNMENT_CENTER, vp.x, 11, Color("#ffe6a8"))
	var meds := "%s  bandage x%d  medkit x%d" % [KeyBinds.primary_label("use_heal"), p.count_carried("bandage"), p.count_carried("medkit")]
	draw_string(font, Vector2(sx + slot_w * n_slots + 8, sy + 30), meds, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.6))
	# What you have to hold the change back with, on the same shelf as the
	# medical supplies: it is the other thing you go looking for.
	var doses := 0
	for id in Config.CONSUMABLES:
		if Mutation.is_suppressant(id):
			doses += p.count_carried(id)
	draw_string(font, Vector2(sx + slot_w * n_slots + 8, sy + 42),
		"%s  brain matter x%d" % [KeyBinds.primary_label("use_suppress"), doses],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#c07f9a", 0.75))

	# Carry weight, beside the hotbar. Grey is fine, amber is nearly full,
	# red means you are over and it is costing you.
	var carried := p.carried_weight()
	var frac := clampf(carried / p.carry_cap, 0.0, 1.0)
	var wx := sx - 132.0
	draw_rect(Rect2(wx, sy + 18, 120, 10), Color(0, 0, 0, 0.55))
	var wcol := Color("#8a8f84")
	if p.overloaded():
		wcol = Color("#c96a5a")
	elif frac > 0.85:
		wcol = Color("#d9c46a")
	draw_rect(Rect2(wx, sy + 18, 120 * frac, 10), wcol)
	draw_string(font, Vector2(wx, sy + 14), "%d / %d" % [roundi(carried), roundi(p.carry_cap)], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, wcol)

	# What the interact key is offering, and the search channel. Every key
	# named here comes from `KeyBinds`, so rebinding changes what the game
	# tells you to press.
	var target := Interact.best_target(sim, p)
	if p.driving_id > 0:
		# At the wheel, driving is all there is — so the prompt is the controls
		# rather than whatever happens to be within reach of the car.
		draw_string(font, Vector2(0, sy - 70), "%s / %s  drive  ·  %s / %s  steer  ·  %s  get out" % [
			KeyBinds.primary_label("move_up"), KeyBinds.primary_label("move_down"),
			KeyBinds.primary_label("move_left"), KeyBinds.primary_label("move_right"),
			KeyBinds.primary_label("interact")],
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 12, Color("#d8e8c0"))
	elif not p.searching.is_empty():
		var c: Dictionary = p.searching.container
		var k := clampf(p.searching.t / p.searching.dur, 0.0, 1.0)
		draw_string(font, Vector2(0, sy - 70), "Searching %s" % c.label, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 12, Color("#ebe6d6"))
		draw_rect(Rect2(vp.x / 2.0 - 60, sy - 62, 120, 6), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(vp.x / 2.0 - 60, sy - 62, 120 * k, 6), Color("#c9a227"))
	elif not p.reviving.is_empty():
		var k := clampf(p.reviving.t / p.reviving.dur, 0.0, 1.0)
		var who := sim.player_by_seat(int(p.reviving.seat))
		draw_string(font, Vector2(0, sy - 70), "Getting %s up" % (who.display_name if who != null else "them"),
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 12, Color("#ebe6d6"))
		draw_rect(Rect2(vp.x / 2.0 - 60, sy - 62, 120, 6), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(vp.x / 2.0 - 60, sy - 62, 120 * k, 6), Color("#9fd0ff"))
	elif not target.is_empty():
		draw_string(font, Vector2(0, sy - 70), "%s  %s" % [KeyBinds.primary_label("interact"), target.label], HORIZONTAL_ALIGNMENT_CENTER, vp.x, 12, Color("#d8e8c0"))

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
		var turned := death_cause == "turned"
		draw_string(font, Vector2(0, vp.y / 2.0 - 10), "YOU TURNED" if turned else "YOU DIED",
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 34, Color("#b07ad0") if turned else Color("#e05a4a"))
		draw_string(font, Vector2(0, vp.y / 2.0 + 16), "respawning in %.1f" % maxf(0.0, p.respawn_t), HORIZONTAL_ALIGNMENT_CENTER, vp.x, 13, Color("#ebe6d6"))
	elif p.downed:
		draw_rect(Rect2(Vector2.ZERO, vp), Color("#3a0a0a", 0.35))
		draw_string(font, Vector2(0, vp.y / 2.0 - 10), "YOU ARE DOWN", HORIZONTAL_ALIGNMENT_CENTER, vp.x, 34, Color("#e05a4a"))
		draw_string(font, Vector2(0, vp.y / 2.0 + 16), "a teammate can get you up  ·  %.0fs" % maxf(0.0, p.down_t),
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 13, Color("#ebe6d6"))

	# The others at the table, under your own bars: name and a sliver of
	# health, so you know who needs you before they say so.
	var ry := vp.y - 92.0 - 18.0
	for q in sim.players:
		if q == p or q.away:
			continue
		var col := Color(Config.PLAYER.colors[q.seat % Config.PLAYER.colors.size()])
		var state := "DOWN" if q.downed else ("DEAD" if q.dead else "")
		draw_rect(Rect2(20.0, ry - 9.0, 120.0, 4.0), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(20.0, ry - 9.0, 120.0 * clampf(q.hp / maxf(1.0, q.max_hp), 0.0, 1.0), 4.0),
			Color("#e05a4a") if q.downed else Color("#c8423a"))
		draw_string(font, Vector2(20.0, ry - 12.0), "%s  %s" % [q.display_name, state], HORIZONTAL_ALIGNMENT_LEFT, 220.0, 10,
			Color("#e05a4a") if q.downed else col)
		ry -= 20.0
	if not net_line.is_empty():
		draw_string(font, Vector2(vp.x - 350, vp.y - Config.MAP.corner - 52.0), net_line,
			HORIZONTAL_ALIGNMENT_RIGHT, 334, 10, Color("#9fd0ff", 0.7))

	# Debug readout. Above the minimap rather than in the corner: the corner is
	# a real piece of UI now, and a developer line does not outrank it.
	var dbg := "%d fps   tile %d,%d   enemies %d   kills %d" % [Engine.get_frames_per_second(), int(p.pos.x / 32), int(p.pos.y / 32), sim.enemies.alive_count(), sim.stats.kills]
	draw_string(font, Vector2(vp.x - 350, vp.y - Config.MAP.corner - 38.0), dbg,
		HORIZONTAL_ALIGNMENT_RIGHT, 334, 11, Color(1, 1, 1, 0.5))
