class_name InventoryScreen
extends Control
## The pack: what you are carrying, what you are wearing, and what is on your
## hotbar. Everything moves by dragging; ctrl+click drops; shift+click splits
## a stack in half. Nothing equips itself.
##
## Drawn immediate-mode against a computed cell list, the same way the HUD is,
## so the hit test and the drawing can never describe different rectangles:
## `_cells()` is the single source of both. Phase 3c hangs crafting off the
## tab strip at the top.

const CELL := 44.0
const GAP := 4.0
const BAG_COLS := 6

var sim: GameSim
var player: PlayerSim
var drag := {}                   # {from: {kind, index/slot}, id, n} while held
var hover := {}
var mouse := Vector2.ZERO


func _init(sim_: GameSim) -> void:
	sim = sim_
	player = sim_.players[0]
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func toggle() -> void:
	visible = not visible
	if not visible:
		_cancel_drag()


# ------------------------------------------------------------------ layout --

## The panel rectangle, centred and clamped to the window.
func _panel() -> Rect2:
	var vp := get_viewport_rect().size
	var w := minf(760.0, vp.x - 40.0)
	var h := minf(470.0, vp.y - 40.0)
	return Rect2(Vector2((vp.x - w) / 2.0, (vp.y - h) / 2.0), Vector2(w, h))


## Every clickable cell: the body slots, the pack grid and the hotbar. The
## drawing walks this list and so does the hit test.
func _cells() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var panel := _panel()
	var x0 := panel.position.x + 24.0
	var y0 := panel.position.y + 76.0

	for i in range(Config.GEAR_SLOTS.size()):
		var slot: String = Config.GEAR_SLOTS[i]
		out.append({"kind": "equip", "slot": slot, "index": -1,
			"rect": Rect2(x0, y0 + i * (CELL + GAP), CELL, CELL)})

	var gx := x0 + CELL + 96.0
	for i in range(player.bag.size()):
		var col := i % BAG_COLS
		var row := i / BAG_COLS
		out.append({"kind": "bag", "slot": "", "index": i,
			"rect": Rect2(gx + col * (CELL + GAP), y0 + row * (CELL + GAP), CELL, CELL)})

	var hy := panel.position.y + panel.size.y - CELL - 26.0
	var hx := gx
	for i in range(player.hotbar.size()):
		out.append({"kind": "hotbar", "slot": "", "index": i,
			"rect": Rect2(hx + i * (CELL + GAP), hy, CELL, CELL)})
	return out


## The middle of one cell, for the smoke run to click on. Reads the same
## layout the player sees, so a click in the test lands where a click by hand
## would.
func cell_centre(kind: String, index: int, slot := "") -> Vector2:
	for c in _cells():
		if c.kind == kind and (c.index == index or (kind == "equip" and c.slot == slot)):
			return c.rect.get_center()
	return Vector2.ZERO


func _cell_at(pos: Vector2) -> Dictionary:
	for c in _cells():
		if c.rect.has_point(pos):
			return c
	return {}


## What is in a cell, as {id, n}.
func _stack_in(cell: Dictionary) -> Dictionary:
	match cell.kind:
		"bag": return player.bag.at(cell.index)
		"hotbar": return player.hotbar.at(cell.index)
		"equip":
			var id: String = player.equip.get(cell.slot, "")
			return {"id": id, "n": 1} if not id.is_empty() else {}
	return {}


# ------------------------------------------------------------------- input --

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		mouse = event.position
		hover = _cell_at(mouse)
		queue_redraw()
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	mouse = mb.position
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_press(_cell_at(mouse), mb)
		else:
			_release(_cell_at(mouse))
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_quick_move(_cell_at(mouse))
	queue_redraw()


func _press(cell: Dictionary, mb: InputEventMouseButton) -> void:
	if cell.is_empty():
		return
	var stack := _stack_in(cell)
	if stack.is_empty():
		return
	# Ctrl+click drops, shift+click splits: both are decisions about the stack
	# you already clicked, so neither starts a drag.
	if mb.ctrl_pressed:
		if cell.kind == "equip":
			Equipment.drop_equipped(sim, player, cell.slot)
		else:
			Equipment.drop_stack(sim, player, cell.kind, cell.index, true)
		return
	if mb.shift_pressed and cell.kind != "equip":
		var cont := Equipment.container(player, cell.kind)
		var free := cont.first_empty()
		if free >= 0:
			Equipment.split_stack(player, cell.kind, cell.index, free)
		return
	drag = {"from": cell, "id": stack.id, "n": stack.n}


func _release(cell: Dictionary) -> void:
	if drag.is_empty():
		return
	var from: Dictionary = drag.from
	drag = {}
	if cell.is_empty():
		# Released outside the grids: that is a drop, the same gesture as
		# dragging something out of the panel in the prototype.
		if not _panel().has_point(mouse):
			if from.kind == "equip":
				Equipment.drop_equipped(sim, player, from.slot)
			else:
				Equipment.drop_stack(sim, player, from.kind, from.index, true)
		return
	if cell.kind == from.kind and cell.index == from.index and cell.slot == from.slot:
		return
	if from.kind == "equip" and cell.kind == "equip":
		return
	if from.kind == "equip":
		Equipment.unequip_to(player, from.slot, cell.kind, cell.index)
	elif cell.kind == "equip":
		Equipment.equip_from_slot(player, from.kind, from.index, cell.slot)
	else:
		Equipment.move_stack(player, from.kind, from.index, cell.kind, cell.index)


## Right-click: the obvious thing for what is under the cursor. Gear in the
## pack goes on; gear on the body comes off; anything else swaps between the
## pack and the hotbar.
func _quick_move(cell: Dictionary) -> void:
	if cell.is_empty():
		return
	var stack := _stack_in(cell)
	if stack.is_empty():
		return
	if cell.kind == "equip":
		Equipment.unequip(sim, player, cell.slot)
		return
	if not Items.gear_slot(stack.id).is_empty() and cell.kind == "bag":
		Equipment.equip_from_bag(sim, player, cell.index)
		return
	var to := "hotbar" if cell.kind == "bag" else "bag"
	var target := Equipment.container(player, to)
	var free := target.first_empty()
	if free < 0:
		sim.notify("No room", "#c96a5a")
		return
	Equipment.move_stack(player, cell.kind, cell.index, to, free)


func _cancel_drag() -> void:
	drag = {}


# ----------------------------------------------------------------- drawing --

func _draw() -> void:
	if not visible:
		return
	var font := ThemeDB.fallback_font
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.45))

	var panel := _panel()
	draw_rect(panel, Color("#14161a", 0.96))
	draw_rect(panel, Color("#3a4048"), false, 2.0)
	draw_string(font, panel.position + Vector2(24, 32), "PACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#ebe6d6"))

	# The weight bar counts pack and hotbar together, because that is the
	# budget every capacity check nets off.
	var carried := player.carried_weight()
	var frac := clampf(carried / player.carry_cap, 0.0, 1.0)
	var bar := Rect2(panel.position.x + panel.size.x - 260.0, panel.position.y + 20.0, 236.0, 14.0)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	var wcol := Color("#8a8f84")
	if player.overloaded():
		wcol = Color("#c96a5a")
	elif frac > 0.85:
		wcol = Color("#d9c46a")
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), wcol)
	draw_string(font, bar.position + Vector2(0, -4), "WEIGHT  %.0f / %.0f" % [carried, player.carry_cap],
		HORIZONTAL_ALIGNMENT_RIGHT, bar.size.x, 11, wcol)

	var dr := player.armor_dr
	draw_string(font, panel.position + Vector2(24, 60), "ARMOUR  %d%%" % roundi(dr * 100.0),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#9fd07a") if dr > 0.0 else Color("#8a8f84"))

	for cell in _cells():
		_draw_cell(font, cell)

	draw_string(font, Vector2(panel.position.x + 24, panel.position.y + panel.size.y - 8),
		"drag to move  ·  right-click to equip or stow  ·  ctrl+click to drop  ·  shift+click to split",
		HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 40, 10, Color(1, 1, 1, 0.4))

	# The dragged stack rides the cursor, and the tooltip only shows when
	# nothing is in hand.
	if not drag.is_empty():
		var r := Rect2(mouse - Vector2(CELL, CELL) / 2.0, Vector2(CELL, CELL))
		draw_rect(r, Color(Items.color_of(drag.id), 0.8))
		draw_string(font, r.position + Vector2(0, CELL - 6), _short(drag.id), HORIZONTAL_ALIGNMENT_CENTER, CELL, 9, Color.BLACK)
	elif not hover.is_empty():
		_draw_tooltip(font, _stack_in(hover))


func _draw_cell(font: Font, cell: Dictionary) -> void:
	var r: Rect2 = cell.rect
	var stack := _stack_in(cell)
	var held: bool = cell.kind == "hotbar" and cell.index == player.slot
	draw_rect(r, Color("#1e222a", 0.9))
	var edge := Color("#3a4048")
	if held:
		edge = Color("#d8e8c0")
	elif not hover.is_empty() and hover.kind == cell.kind and hover.index == cell.index and hover.slot == cell.slot:
		edge = Color("#8a949e")
	draw_rect(r, edge, false, 2.0 if held else 1.0)

	if cell.kind == "equip":
		draw_string(font, r.position + Vector2(-92, 26), Config.GEAR_SLOT_NAMES[cell.slot],
			HORIZONTAL_ALIGNMENT_RIGHT, 86, 11, Color(1, 1, 1, 0.55))
	elif cell.kind == "hotbar":
		draw_string(font, r.position + Vector2(3, 11), str(cell.index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.4))

	if stack.is_empty():
		return
	var id: String = stack.id
	# The swatch stops short of the bottom so the name has a strip of its own
	# rather than being printed over the colour and clipped by the border.
	draw_rect(Rect2(r.position + Vector2(5, 5), r.size - Vector2(10, 19)), Color(Items.color_of(id)))
	draw_string(font, r.position + Vector2(0, r.size.y - 4), _short(id), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 9, Color("#d5d0c4"))
	if stack.n > 1:
		var label := str(stack.n)
		draw_string(font, r.position + Vector2(-4, 17), label, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x, 11, Color(0, 0, 0, 0.85))
		draw_string(font, r.position + Vector2(-5, 16), label, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x, 11, Color.WHITE)


## A cell is 44px wide, which is about seven characters. Resources already
## carry a four-letter short; everything else goes by the last word of its
## name, which is the part that identifies it — Steel Pipe is a PIPE, a
## Padded Vest is a VEST.
func _short(id: String) -> String:
	if Config.RES.has(id):
		return Config.RES[id].short
	var words := Items.name_of(id).split(" ", false)
	return String(words[words.size() - 1]).left(7).to_upper()


func _draw_tooltip(font: Font, stack: Dictionary) -> void:
	if stack.is_empty():
		return
	var id: String = stack.id
	var lines: Array[String] = [Items.name_of(id)]
	var kind := Items.kind_of(id)
	lines.append("%s  ·  %.1f each" % [kind, Items.weight_of(id)])
	if kind == "gear":
		var g: Dictionary = Config.GEAR[id]
		if g.dr > 0.0:
			lines.append("%s  ·  %d%% damage reduction" % [Config.GEAR_SLOT_NAMES[g.slot], roundi(float(g.dr) * 100.0)])
		else:
			lines.append("%s  ·  %ds of light" % [Config.GEAR_SLOT_NAMES[g.slot], roundi(float(g.burn))])
	elif kind == "weapon":
		var w: Dictionary = Config.WEAPONS[id]
		lines.append("%.0f damage  ·  %s" % [w.dmg, w.kind])
	elif kind == "consumable" and float(Config.CONSUMABLES[id].heal) > 0.0:
		lines.append("heals %d" % roundi(float(Config.CONSUMABLES[id].heal)))

	var w := 220.0
	var h := 18.0 * lines.size() + 10.0
	var at := mouse + Vector2(16, 12)
	var vp := get_viewport_rect().size
	at.x = minf(at.x, vp.x - w - 8.0)
	at.y = minf(at.y, vp.y - h - 8.0)
	draw_rect(Rect2(at, Vector2(w, h)), Color("#0d0f12", 0.96))
	draw_rect(Rect2(at, Vector2(w, h)), Color("#3a4048"), false, 1.0)
	var y := at.y + 16.0
	for i in range(lines.size()):
		draw_string(font, Vector2(at.x + 8, y), lines[i], HORIZONTAL_ALIGNMENT_LEFT, w - 16,
			12 if i == 0 else 10, Color("#ebe6d6") if i == 0 else Color(1, 1, 1, 0.65))
		y += 18.0
