class_name RangePanel
extends Control
## The Target Range's damage panel (`tasks/target-range.md`, PR C): top right,
## under the Threat card, and only while you are in the range. What it says is
## `DamageLog`'s; this only draws it.
##
## Hand-drawn, like the dev menu: it is a developer's readout, not a screen a
## player ever sees, and a column of numbers wants fixed tab stops.

const W := 380.0
const PAD := 14.0
const ROW := 19.0
## How many of each half fit before the oldest is left off.
const DEALT_ROWS := 6
const TAKEN_ROWS := 8

var sim: GameSim
var hud: Hud
var damage := DamageLog.new()


func _init(sim_: GameSim, hud_: Hud) -> void:
	sim = sim_
	hud = hud_
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, 0)
	visible = false


static func now() -> float:
	return Time.get_ticks_usec() / 1_000_000.0


func on_event(ev: Dictionary) -> void:
	if hud.player == null:
		return
	damage.seat = hud.player.seat
	damage.feed(ev, now())


func _process(_dt: float) -> void:
	var inside := TargetRange.is_range(sim)
	if inside != visible:
		visible = inside
		damage.clear()
	if not visible:
		return
	var h := PAD * 2.0 + ROW * (3.5 + mini(damage.dealt.size(), DEALT_ROWS) + mini(damage.taken.size(), TAKEN_ROWS) + 2.5)
	if absf(custom_minimum_size.y - h) > 0.5:
		custom_minimum_size = Vector2(W, h)
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var caps := Ui.font("ui", 600, 1)
	var body := Ui.font("ui", 500)
	var mono := Ui.font("mono", 500)
	Ui.box(Ui.HUD_FILL, Ui.LINE, 1, 3).draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	var x := PAD
	var y := PAD + 12.0
	var t := now()
	var p := hud.player

	# What is in your hand, and whether it is wearing.
	var held := p.held_id() if p != null else ""
	var weapon := "Fists" if held.is_empty() or not Config.WEAPONS.has(held) else String(Config.WEAPONS[held].name)
	if p != null and Config.WEAPONS.has(held) and held != "fists":
		weapon += "  L%d" % maxi(1, p.hotbar.level_at(p.slot))
	draw_string(caps, Vector2(x, y), "DAMAGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ui.ACCENT_HI)
	draw_string(body, Vector2(x + 70.0, y), weapon, HORIZONTAL_ALIGNMENT_LEFT, W - 200.0, 13, Ui.TEXT_BODY)
	var wear: bool = sim.instance != null and sim.instance.range_wear
	draw_string(mono, Vector2(W - PAD, y), "WEAR %s" % ("ON" if wear else "OFF"), HORIZONTAL_ALIGNMENT_RIGHT, -1, 12,
		Ui.DOWN if wear else Ui.TEXT_DIM)
	y += ROW * 1.5

	# Dealt: one row per body hit this session.
	var live := t - damage.dealt_last_t <= float(Config.RANGE.session_gap)
	draw_string(caps, Vector2(x, y), "DEALT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.TEXT_DIM)
	draw_string(mono, Vector2(W - PAD, y), "HITS  LAST  TOTAL   DPS   TTK", HORIZONTAL_ALIGNMENT_RIGHT, -1, 11, Ui.TEXT_DIM)
	y += ROW
	if damage.dealt.is_empty():
		draw_string(body, Vector2(x, y), "Hit something", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ui.TEXT_DIM)
		y += ROW
	for i in range(maxi(0, damage.dealt.size() - DEALT_ROWS), damage.dealt.size()):
		var r: Dictionary = damage.dealt[i]
		var col := Ui.TEXT_BODY if live else Ui.TEXT_DIM
		var name_ := String(Config.ENEMIES.get(String(r.type), {}).get("name", r.type))
		draw_string(body, Vector2(x, y), name_, HORIZONTAL_ALIGNMENT_LEFT, 110.0, 13, col)
		var d := DamageLog.dps(r, t if live else damage.dealt_last_t)
		var ttk := "%.2fs" % float(r.ttk) if float(r.ttk) >= 0.0 else "%d%%" % roundi(100.0 * float(r.hp) / maxf(1.0, float(r.max)))
		var line := "%4d %5.0f %6.0f %5s %5s" % [int(r.hits), float(r.last), float(r.total),
			"-" if d < 0.0 else "%.0f" % d, ttk]
		draw_string(mono, Vector2(W - PAD, y), line, HORIZONTAL_ALIGNMENT_RIGHT, -1, 12, col)
		y += ROW

	# Taken: every hit this session, and what the armour took off them.
	y += ROW * 0.5
	var tot := damage.taken_totals()
	draw_string(caps, Vector2(x, y), "TAKEN", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.TEXT_DIM)
	if int(tot.hits) > 0:
		var cut := 1.0 - float(tot.dmg) / maxf(0.001, float(tot.raw))
		draw_string(mono, Vector2(W - PAD, y), "%d hits  %.0f -> %.0f  (-%d%%)" % [int(tot.hits), float(tot.raw), float(tot.dmg), roundi(cut * 100.0)],
			HORIZONTAL_ALIGNMENT_RIGHT, -1, 12, Ui.TEXT_BODY)
	y += ROW
	if damage.taken.is_empty():
		draw_string(body, Vector2(x, y), "Nothing yet", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ui.TEXT_DIM)
	for i in range(maxi(0, damage.taken.size() - TAKEN_ROWS), damage.taken.size()):
		var h: Dictionary = damage.taken[i]
		draw_string(body, Vector2(x, y), String(h.label).capitalize(), HORIZONTAL_ALIGNMENT_LEFT, 150.0, 13, Ui.TEXT_BODY)
		draw_string(mono, Vector2(W - PAD, y), "raw %5.1f  took %5.1f" % [float(h.raw), float(h.dmg)],
			HORIZONTAL_ALIGNMENT_RIGHT, -1, 12, Color("#ff8a7a"))
		y += ROW
