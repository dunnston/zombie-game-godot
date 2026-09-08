class_name BuildBar
extends Control
## Build mode: the bar of cards along the bottom, what is selected, and the
## tile under the cursor. Owns the mouse while it is open.
##
## It writes nothing to the world directly. A click sets a pending action
## which `fill_intent` copies into the player's `Intent`, so building goes
## through the same door as movement and fighting (invariant 1) and a guest's
## build command will run identical code.

const CARD_MAX := 92.0
const CARD_MIN := 72.0
const GAP := 5.0
const TOOLS := ["repair", "repair_all", "demolish"]
const TOOL_NAMES := {"repair": "REPAIR", "repair_all": "REPAIR ALL", "demolish": "DEMOLISH"}

var sim: GameSim
var player: PlayerSim
var open := false
var selected := 0
var hover_tile := Vector2i.ZERO
var check := {"ok": false, "reason": ""}
var pending := {}
var mouse := Vector2.ZERO


func _init(sim_: GameSim) -> void:
	sim = sim_
	player = sim_.players[0]
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func cards() -> Array:
	var out: Array = []
	out.append_array(Config.BUILD_ORDER)
	out.append_array(TOOLS)
	return out


func selected_card() -> String:
	var c := cards()
	return c[clampi(selected, 0, c.size() - 1)]


func toggle() -> void:
	open = not open
	pending = {}


## How `n` cards lay out in a `width`px window. Cards shrink to the floor and
## then the bar wraps onto more rows — it never drops a card. Pure, so the
## rule can be tested: the two that used to fall off the end of the
## prototype's bar were REPAIR and DEMOLISH.
static func layout(width: float, n: int) -> Dictionary:
	var cols := maxi(1, mini(n, floori((width - 20.0 + GAP) / (CARD_MIN + GAP))))
	var rows := ceili(float(n) / cols)
	var cw := maxf(CARD_MIN, minf(CARD_MAX, floorf((width - 20.0 - (cols - 1) * GAP) / cols)))
	return {"cols": cols, "rows": rows, "cw": cw, "gap": GAP}


func _card_rects() -> Array[Rect2]:
	var vp := get_viewport_rect().size
	var n := cards().size()
	var l := layout(vp.x, n)
	var h := 46.0
	var total_h: float = l.rows * (h + GAP)
	var out: Array[Rect2] = []
	for i in range(n):
		var col: int = i % int(l.cols)
		var row: int = i / int(l.cols)
		var row_n: int = mini(int(l.cols), n - row * int(l.cols))
		var row_w: float = row_n * l.cw + (row_n - 1) * GAP
		var x: float = (vp.x - row_w) / 2.0 + col * (l.cw + GAP)
		# Above the hotbar, not on top of it: build mode does not replace the
		# HUD, and you still need to see what you are holding.
		var y: float = vp.y - total_h - 76.0 + row * (h + GAP)
		out.append(Rect2(x, y, float(l.cw), h))
	return out


# ------------------------------------------------------------------- input --

## Called by the scene each frame with the world position of the cursor.
func update_hover(world_pos: Vector2) -> void:
	if not open:
		return
	hover_tile = Vector2i(floori(world_pos.x / Config.TILE), floori(world_pos.y / Config.TILE))
	var card := selected_card()
	if TOOLS.has(card):
		var s := sim.structs.at_tile(hover_tile.x, hover_tile.y)
		if card == "repair_all":
			var plan := sim.structs.plan_repair_all(sim, player)
			check = {"ok": plan.repairable > 0,
				"reason": "%d piece%s  ·  %s" % [plan.repairable, "" if plan.repairable == 1 else "s", Structures.cost_label(plan.cost)] if plan.repairable > 0 else "Nothing in range to repair"}
		elif s.is_empty():
			check = {"ok": false, "reason": "Nothing there"}
		elif card == "repair":
			check = {"ok": Structures.is_damaged(s),
				"reason": Structures.cost_label(Structures.repair_cost(s)) if Structures.is_damaged(s) else "Already intact"}
		else:
			check = {"ok": true, "reason": "Salvage %s" % s.def.name}
	else:
		check = sim.structs.can_place(sim, card, hover_tile.x, hover_tile.y, player)


## Drains whatever the last click asked for into the intent. Edges only: one
## click, one action, exactly as the keyboard edges work.
func fill_intent(intent: Intent) -> void:
	if pending.is_empty():
		return
	intent.build_action = pending.action
	intent.build_type = pending.get("type", "")
	intent.build_tile = pending.get("tile", Vector2i.ZERO)
	pending = {}


## The scene routes clicks here while build mode owns the mouse. Returns true
## when the click was consumed.
func click(at: Vector2) -> bool:
	if not open:
		return false
	mouse = at
	var rects := _card_rects()
	for i in range(rects.size()):
		if rects[i].has_point(at):
			selected = i
			return true
	var card := selected_card()
	if card == "repair_all":
		pending = {"action": "repair_all"}
	elif card == "repair":
		pending = {"action": "repair", "tile": hover_tile}
	elif card == "demolish":
		pending = {"action": "demolish", "tile": hover_tile}
	else:
		pending = {"action": "place", "type": card, "tile": hover_tile}
	return true


func cycle(dir: int) -> void:
	var n := cards().size()
	selected = ((selected + dir) % n + n) % n


# ----------------------------------------------------------------- drawing --

func _draw() -> void:
	if not open:
		return
	var font := ThemeDB.fallback_font
	var vp := get_viewport_rect().size
	var rects := _card_rects()
	var all := cards()

	draw_string(font, Vector2(0, rects[0].position.y - 26), "BUILD MODE  —  click to place, B to leave, wheel to change",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 12, Color("#d8e8c0"))
	if not check.reason.is_empty():
		draw_string(font, Vector2(0, rects[0].position.y - 10), check.reason, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 11,
			Color("#9fd07a") if check.ok else Color("#c96a5a"))

	for i in range(all.size()):
		var id: String = all[i]
		var r: Rect2 = rects[i]
		var is_tool := TOOLS.has(id)
		var def: Dictionary = Config.STRUCTURES.get(id, {})
		var locked := not is_tool and not sim.structs.is_unlocked(id)
		var afford := is_tool or player.can_afford(sim, def.cost)
		draw_rect(r, Color("#14161a", 0.92 if i == selected else 0.72))
		draw_rect(r, Color("#d8e8c0") if i == selected else Color("#3a4048"), false, 2.0 if i == selected else 1.0)
		var name_col := Color("#ebe6d6")
		if locked or not afford:
			name_col = Color("#7a7f76")
		var label: String = TOOL_NAMES.get(id, def.get("name", id))
		_fit(font, label, r.position + Vector2(0, 16), r.size.x, 11, name_col)
		if is_tool:
			continue
		_fit(font, Structures.cost_label(def.cost), r.position + Vector2(0, 30), r.size.x, 9,
			Color("#c9a227") if afford else Color("#c96a5a"))
		draw_string(font, r.position + Vector2(0, 42), "LOCKED" if locked else "%d hp" % int(def.hp),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 9, Color("#c96a5a") if locked else Color(1, 1, 1, 0.4))


## Draws centred text, shrinking the type until it fits the card rather than
## clipping it: "Supply Stas" and "SCRP 45 · PAR" tell you nothing.
func _fit(font: Font, text: String, at: Vector2, width: float, size: int, color: Color) -> void:
	var s := size
	while s > 7 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > width - 6.0:
		s -= 1
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, s, color)
