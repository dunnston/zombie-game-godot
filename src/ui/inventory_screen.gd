class_name InventoryScreen
extends Control
## The pack: what you are carrying, what you are wearing, what is on your
## hotbar, what you can make, and what is in the chest you are standing at.
## Everything moves by dragging; ctrl+click drops; shift+click splits.
## Nothing equips itself.
##
## Drawn immediate-mode against a computed cell list, the same way the HUD
## is, so the hit test and the drawing can never describe different
## rectangles: `_cells()` is the single source of both.
##
## Four modes share one panel, because they are one panel. **PACK** is what
## you carry. **CRAFT** is the recipe list for whatever bench you happen to
## be standing beside — in here rather than in a screen of its own, which is
## the playtest finding: a separate crafting menu made you forget what you
## were carrying. **CHAR** is the same argument again: what a skill point
## buys is a decision about what you are carrying and fighting with, so it
## belongs beside them. **STORE** swaps the body slots for a container's
## contents.

const CELL := 44.0
const GAP := 4.0
const BAG_COLS := 6
const STORE_COLS := 6
const ROW := 22.0                # a recipe row in the craft list

var sim: GameSim
var player: PlayerSim
var drag := {}                   # {from: cell, id, n} while held
var hover := {}
var mouse := Vector2.ZERO

## "pack", "craft", "char", "crew" or "store".
var mode := "pack"
## The tile of the container being looked into, or (-1, -1). A tile rather
## than the container itself, so the reach check happens every frame and
## walking away closes the screen.
var store_tile := Vector2i(-1, -1)
var craft_top := 0               # first visible recipe row
var char_top := 0                # first visible perk row
## Which attribute's tree the character sheet is showing.
var char_attr := "str"
## Which crew member the roster has selected, by id.
var crew_sel := 0
var crew_top := 0                # first visible roster row


func _init(sim_: GameSim) -> void:
	sim = sim_
	player = sim_.players[0]
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func toggle() -> void:
	visible = not visible
	if visible:
		if mode == "store":
			mode = "pack"
		store_tile = Vector2i(-1, -1)
	else:
		_cancel_drag()


## Walking up to a chest and pressing E opens it here.
func open_store(tile: Vector2i) -> void:
	store_tile = tile
	mode = "store"
	visible = true


## The container being looked into, or null when there is none in reach —
## which is also how the screen knows to close itself.
func store() -> Slots:
	if store_tile.x < 0:
		return null
	return sim.structs.reachable_store(player, store_tile.x, store_tile.y)


## The bench the player can craft at from where they stand.
func bench() -> int:
	return Crafting.bench_tier_at(sim, player)


func recipes() -> Array:
	return Crafting.visible_recipes(player, bench())


## Called every frame by the scene: a store screen closes when you walk away
## from the thing you opened.
func tick() -> void:
	if visible and mode == "store" and store() == null:
		visible = false
		_cancel_drag()


# ------------------------------------------------------------------ layout --

func _panel() -> Rect2:
	var vp := get_viewport_rect().size
	var w := minf(760.0, vp.x - 40.0)
	var h := minf(470.0, vp.y - 40.0)
	return Rect2(Vector2((vp.x - w) / 2.0, (vp.y - h) / 2.0), Vector2(w, h))


func _tabs() -> Array[Dictionary]:
	var panel := _panel()
	var out: Array[Dictionary] = []
	var names := ["pack", "craft", "char", "crew"] if mode != "store" else ["store"]
	var x := panel.position.x + 24.0
	for name in names:
		out.append({"mode": name, "rect": Rect2(x, panel.position.y + 14.0, 84.0, 24.0)})
		x += 90.0
	return out


## Every clickable cell. In PACK and CRAFT the left column is the body; in
## STORE it is the container's grid.
func _cells() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var panel := _panel()
	var x0 := panel.position.x + 24.0
	var y0 := panel.position.y + 76.0
	var gx := x0 + CELL + 96.0

	if mode == "store":
		var s := store()
		var n := s.size() if s != null else 0
		gx = x0 + STORE_COLS * (CELL + GAP) + 26.0
		for i in range(n):
			out.append({"kind": "store", "slot": "", "index": i,
				"rect": Rect2(x0 + (i % STORE_COLS) * (CELL + GAP), y0 + (i / STORE_COLS) * (CELL + GAP), CELL, CELL)})
	elif mode == "pack":
		for i in range(Config.GEAR_SLOTS.size()):
			var slot: String = Config.GEAR_SLOTS[i]
			out.append({"kind": "equip", "slot": slot, "index": -1,
				"rect": Rect2(x0, y0 + i * (CELL + GAP), CELL, CELL)})

	# The pack grid moves right in store mode but is otherwise the same grid.
	if mode != "craft" and mode != "char" and mode != "crew":
		for i in range(player.bag.size()):
			out.append({"kind": "bag", "slot": "", "index": i,
				"rect": Rect2(gx + (i % BAG_COLS) * (CELL + GAP), y0 + (i / BAG_COLS) * (CELL + GAP), CELL, CELL)})

	var hy := panel.position.y + panel.size.y - CELL - 26.0
	for i in range(player.hotbar.size()):
		out.append({"kind": "hotbar", "slot": "", "index": i,
			"rect": Rect2(gx + i * (CELL + GAP), hy, CELL, CELL)})
	return out


## The recipe rows on screen, as {recipe, rect}.
func _recipe_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if mode != "craft":
		return out
	var panel := _panel()
	var list := recipes()
	var top := panel.position.y + 76.0
	var visible_rows := int((panel.size.y - 130.0) / ROW)
	craft_top = clampi(craft_top, 0, maxi(0, list.size() - visible_rows))
	for i in range(craft_top, mini(list.size(), craft_top + visible_rows)):
		out.append({"recipe": list[i],
			"rect": Rect2(panel.position.x + 24.0, top + (i - craft_top) * ROW, panel.size.x - 48.0, ROW - 2.0)})
	return out


## The character sheet's clickable rows: the six attributes down the left,
## and the perk tree of whichever attribute is selected down the right.
##
## Attribute rows carry `attr`; perk rows carry `perk`. Both are drawn and hit
## tested off this one list, so what looks clickable is clickable.
func _char_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if mode != "char":
		return out
	var panel := _panel()
	var x0 := panel.position.x + 24.0
	var top := panel.position.y + 92.0
	# Wide enough for the longest per-rank line ("+12 health · +10 stamina ·
	# +1.2 stam/s") without clipping it, which is the whole reason the column
	# is here — a stat line you cannot read is not a stat line.
	var col_w := 300.0

	for i in range(Config.ATTR_IDS.size()):
		var id: String = Config.ATTR_IDS[i]
		out.append({"attr": id, "perk": "",
			"rect": Rect2(x0, top + i * 40.0, col_w, 36.0)})

	var list := Perks.perks_for(char_attr)
	var px := x0 + col_w + 22.0
	var pw := panel.position.x + panel.size.x - 24.0 - px
	var rows := int((panel.size.y - 150.0) / 38.0)
	char_top = clampi(char_top, 0, maxi(0, list.size() - rows))
	for i in range(char_top, mini(list.size(), char_top + rows)):
		out.append({"attr": "", "perk": String(list[i].id),
			"rect": Rect2(px, top + (i - char_top) * 38.0, pw, 34.0)})
	return out


## The middle of one cell, for the smoke run to click on.
func cell_centre(kind: String, index: int, slot := "") -> Vector2:
	for c in _cells():
		if c.kind == kind and (c.index == index or (kind == "equip" and c.slot == slot)):
			return c.rect.get_center()
	return Vector2.ZERO


## The middle of a named recipe's row, likewise.
func recipe_centre(id: String) -> Vector2:
	for r in _recipe_rows():
		if r.recipe.id == id:
			return r.rect.get_center()
	return Vector2.ZERO


## The middle of an attribute or perk row on the character sheet, likewise.
func char_row_centre(attr := "", perk := "") -> Vector2:
	for r in _char_rows():
		if (not attr.is_empty() and r.attr == attr) or (not perk.is_empty() and r.perk == perk):
			return r.rect.get_center()
	return Vector2.ZERO


func _cell_at(pos: Vector2) -> Dictionary:
	for c in _cells():
		if c.rect.has_point(pos):
			return c
	return {}


func _stack_in(cell: Dictionary) -> Dictionary:
	match cell.kind:
		"bag": return player.bag.at(cell.index)
		"hotbar": return player.hotbar.at(cell.index)
		"store":
			var s := store()
			return s.at(cell.index) if s != null else {}
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
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
		if mode == "char":
			char_top += 1
		elif mode == "crew":
			crew_top += 1
		else:
			craft_top += 1
	elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
		if mode == "char":
			char_top = maxi(0, char_top - 1)
		elif mode == "crew":
			crew_top = maxi(0, crew_top - 1)
		else:
			craft_top = maxi(0, craft_top - 1)
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			if not _click_chrome(mouse):
				_press(_cell_at(mouse), mb)
		else:
			_release(_cell_at(mouse))
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_quick_move(_cell_at(mouse))
	queue_redraw()


## Tabs, buttons and recipe rows: everything on the panel that is not a cell.
func _click_chrome(at: Vector2) -> bool:
	for t in _tabs():
		if t.rect.has_point(at):
			mode = t.mode
			_cancel_drag()
			return true
	for b in _buttons():
		if b.rect.has_point(at):
			_press_button(b.id)
			return true
	for r in _recipe_rows():
		if r.rect.has_point(at):
			Crafting.craft(sim, player, r.recipe, bench())
			return true
	for r in _crew_rows():
		if not r.rect.has_point(at):
			continue
		if int(r.who) != 0:
			crew_sel = int(r.who)
		else:
			var who := _selected_survivor()
			if who != null:
				sim.crew.assign_job(sim, who, String(r.job))
		return true
	for r in _char_rows():
		if not r.rect.has_point(at):
			continue
		if not String(r.attr).is_empty():
			# Clicking an attribute you are not looking at selects it; clicking
			# the one you are looking at spends a point on it. One click never
			# does both, so browsing the tree can never cost you a point.
			if char_attr != r.attr:
				char_attr = r.attr
				char_top = 0
			else:
				Progression.raise_attribute(sim, player, String(r.attr))
		else:
			Progression.buy_perk(sim, player, String(r.perk))
		return true
	return false


func _buttons() -> Array[Dictionary]:
	var panel := _panel()
	var out: Array[Dictionary] = []
	var y := panel.position.y + panel.size.y - 26.0 - CELL - 34.0
	if mode == "store":
		out.append({"id": "deposit", "label": "DEPOSIT ALL", "rect": Rect2(panel.position.x + 24.0, y, 120.0, 24.0)})
		out.append({"id": "withdraw", "label": "TAKE SUPPLIES", "rect": Rect2(panel.position.x + 152.0, y, 130.0, 24.0)})
	elif mode == "pack":
		out.append({"id": "equip_best", "label": "EQUIP BEST", "rect": Rect2(panel.position.x + 24.0, y, 120.0, 24.0)})
	return out


func _press_button(id: String) -> void:
	match id:
		"deposit":
			sim.structs.deposit_all(sim, player, store())
		"withdraw":
			sim.structs.withdraw_supplies(sim, player, store())
		"equip_best":
			Equipment.equip_best(sim, player)


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
			Equipment.drop_stack(sim, player, cell.kind, cell.index, true, store_tile)
		return
	if mb.shift_pressed and cell.kind != "equip":
		var cont := Equipment.container(player, cell.kind, store())
		var free := cont.first_empty()
		if free >= 0:
			cont.split(cell.index, free)
		return
	drag = {"from": cell, "id": stack.id, "n": stack.n}


func _release(cell: Dictionary) -> void:
	if drag.is_empty():
		return
	var from: Dictionary = drag.from
	drag = {}
	if cell.is_empty():
		# Released outside the grids: that is a drop, the same gesture as
		# dragging something out of the panel.
		if not _panel().has_point(mouse):
			if from.kind == "equip":
				Equipment.drop_equipped(sim, player, from.slot)
			else:
				Equipment.drop_stack(sim, player, from.kind, from.index, true, store_tile)
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
		Equipment.move_stack(sim, player, from.kind, from.index, cell.kind, cell.index, store_tile)


## Right-click: the obvious thing for what is under the cursor. Gear in the
## pack goes on, gear on the body comes off, and anything else moves to the
## other side of the screen — pack to hotbar, or pack to chest and back.
func _quick_move(cell: Dictionary) -> void:
	if cell.is_empty():
		return
	var stack := _stack_in(cell)
	if stack.is_empty():
		return
	if cell.kind == "equip":
		Equipment.unequip(sim, player, cell.slot)
		return
	if mode != "store" and not Items.gear_slot(stack.id).is_empty() and cell.kind == "bag":
		Equipment.equip_from_bag(sim, player, cell.index)
		return
	var to := ""
	if mode == "store":
		to = "bag" if cell.kind == "store" else "store"
	else:
		to = "hotbar" if cell.kind == "bag" else "bag"
	var target := Equipment.container(player, to, store())
	if target == null:
		return
	# Prefer merging onto a part-used stack of the same thing.
	var free := -1
	for i in range(target.size()):
		var s := target.at(i)
		if not s.is_empty() and s.id == stack.id and s.n < Items.stack_limit(stack.id):
			free = i
			break
	if free < 0:
		free = target.first_empty()
	if free < 0:
		sim.notify("No room", "#c96a5a")
		return
	Equipment.move_stack(sim, player, cell.kind, cell.index, to, free, store_tile)


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

	for t in _tabs():
		var on: bool = t.mode == mode
		draw_rect(t.rect, Color("#242a32") if on else Color("#181b20"))
		draw_rect(t.rect, Color("#d8e8c0") if on else Color("#3a4048"), false, 1.0)
		draw_string(font, t.rect.position + Vector2(0, 17), t.mode.to_upper(), HORIZONTAL_ALIGNMENT_CENTER,
			t.rect.size.x, 13, Color("#ebe6d6") if on else Color("#8a8f84"))

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

	match mode:
		"craft":
			_draw_craft(font, panel)
		"char":
			_draw_char(font, panel)
		"crew":
			_draw_crew(font, panel)
		"store":
			var s := store()
			draw_string(font, panel.position + Vector2(24, 60),
				"%d / %d slots" % [s.used() if s != null else 0, s.size() if s != null else 0],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8a8f84"))
		_:
			var dr := player.armor_dr
			draw_string(font, panel.position + Vector2(24, 60), "ARMOUR  %d%%" % roundi(dr * 100.0),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#9fd07a") if dr > 0.0 else Color("#8a8f84"))

	for cell in _cells():
		_draw_cell(font, cell)
	for b in _buttons():
		var hot: bool = b.rect.has_point(mouse)
		draw_rect(b.rect, Color("#242a32") if hot else Color("#181b20"))
		draw_rect(b.rect, Color("#8a949e") if hot else Color("#3a4048"), false, 1.0)
		draw_string(font, b.rect.position + Vector2(0, 16), b.label, HORIZONTAL_ALIGNMENT_CENTER, b.rect.size.x, 11, Color("#d5d0c4"))

	# The dragging hint is about the grids, and the character sheet has none —
	# it prints its own line instead, and two of them overlap.
	if mode != "char" and mode != "crew":
		draw_string(font, Vector2(panel.position.x + 24, panel.position.y + panel.size.y - 8),
			"drag to move  ·  right-click to equip or stow  ·  ctrl+click to drop  ·  shift+click to split",
			HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 40, 10, Color(1, 1, 1, 0.4))

	if not drag.is_empty():
		var r := Rect2(mouse - Vector2(CELL, CELL) / 2.0, Vector2(CELL, CELL))
		draw_rect(r, Color(Items.color_of(drag.id), 0.8))
		draw_string(font, r.position + Vector2(0, CELL - 6), _short(drag.id), HORIZONTAL_ALIGNMENT_CENTER, CELL, 9, Color.BLACK)
	elif not hover.is_empty():
		_draw_tooltip(font, _stack_in(hover))


func _draw_craft(font: Font, panel: Rect2) -> void:
	var b := bench()
	var where := "By hand"
	if b >= 2:
		where = "At Workbench II"
	elif b == 1:
		where = "At a Workbench"
	if b == 0 and Crafting.has_tool(player, "hammer"):
		where += "  ·  Stone Hammer in your pack"
	draw_string(font, panel.position + Vector2(24, 60), where, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8a8f84"))

	for row in _recipe_rows():
		var r: Dictionary = row.recipe
		var rect: Rect2 = row.rect
		var st := Crafting.status(sim, player, r, b)
		var hot: bool = rect.has_point(mouse)
		if hot:
			draw_rect(rect, Color("#242a32"))
		draw_string(font, rect.position + Vector2(6, 15), r.name, HORIZONTAL_ALIGNMENT_LEFT, 220, 12,
			Color("#ebe6d6") if st.ok else Color("#7a7f76"))
		draw_string(font, rect.position + Vector2(230, 15), Structures.cost_label(r.cost), HORIZONTAL_ALIGNMENT_LEFT, 260, 11,
			Color("#c9a227") if st.ok else Color("#8a6a5a"))
		if not st.ok:
			draw_string(font, rect.position + Vector2(0, 15), st.reason, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8, 11, Color("#c96a5a"))
		else:
			draw_string(font, rect.position + Vector2(0, 15), "CRAFT", HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8, 11, Color("#9fd07a"))


## The character sheet. Attributes down the left with their per-rank line,
## the selected attribute's perks down the right. Nothing is merely greyed
## out: a row you cannot buy says why, because "needs STR 5" is a plan and
## "no skill points" is a wait, and those are different problems.
func _draw_char(font: Font, panel: Rect2) -> void:
	var points := player.skill_points
	var head := "LEVEL %d" % player.level
	draw_string(font, panel.position + Vector2(24, 60), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ebe6d6"))

	# The XP bar sits under the heading so the next level is always in view.
	var bar := Rect2(panel.position.x + 92.0, panel.position.y + 50.0, 200.0, 10.0)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	var frac := clampf(player.xp / maxf(1.0, float(player.xp_next)), 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color("#9fd0ff"))
	draw_string(font, bar.position + Vector2(bar.size.x + 8, 9), "%d / %d XP" % [roundi(player.xp), player.xp_next],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#8a8f84"))

	var pts_col := Color("#ffe08a") if points > 0 else Color("#8a8f84")
	draw_string(font, Vector2(panel.position.x, panel.position.y + 60),
		"%d POINT%s TO SPEND" % [points, "" if points == 1 else "S"],
		HORIZONTAL_ALIGNMENT_RIGHT, panel.size.x - 24.0, 12, pts_col)

	for row in _char_rows():
		var rect: Rect2 = row.rect
		var hot: bool = rect.has_point(mouse)
		if not String(row.attr).is_empty():
			_draw_attr_row(font, rect, String(row.attr), hot)
		else:
			_draw_perk_row(font, rect, Perks.perk_by_id(String(row.perk)), hot)

	draw_string(font, Vector2(panel.position.x + 24, panel.position.y + panel.size.y - 8),
		"click an attribute to open its tree  ·  click it again to raise it  ·  %d of %d points spent" %
			[Progression.spent_points(player), Progression.lifetime_points(player)],
		HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 40, 10, Color(1, 1, 1, 0.4))


func _draw_attr_row(font: Font, rect: Rect2, id: String, hot: bool) -> void:
	var a: Dictionary = Config.ATTRS[id]
	var rank: int = int(player.attrs.get(id, Config.ATTR_START))
	var selected := char_attr == id
	var check := Perks.can_raise_attr(player, id)
	draw_rect(rect, Color("#242a32") if selected else (Color("#1c2028") if hot else Color("#181b20")))
	draw_rect(rect, Color(a.color) if selected else Color("#3a4048"), false, 1.0)

	# Rank on the left, what a rank is worth on the right, and the flavour
	# underneath on a line of its own so neither has to be cut short.
	draw_string(font, rect.position + Vector2(8, 15), "%s  %d" % [a.abbr, rank], HORIZONTAL_ALIGNMENT_LEFT, 60, 13, Color(a.color))
	draw_string(font, rect.position + Vector2(0, 15), a.per_rank, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8, 9, Color("#8a8f84"))
	draw_string(font, rect.position + Vector2(8, 28), a.blurb, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 90, 9, Color(1, 1, 1, 0.3))
	if selected:
		draw_string(font, rect.position + Vector2(0, 29), "SPEND A POINT" if check.ok else check.reason,
			HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8, 9,
			Color("#9fd07a") if check.ok else Color("#7a7f76"))


func _draw_perk_row(font: Font, rect: Rect2, perk: Dictionary, hot: bool) -> void:
	if perk.is_empty():
		return
	var st := Perks.perk_status(player, perk)
	var rank: int = int(st.rank)
	if hot and st.ok:
		draw_rect(rect, Color("#242a32"))
	draw_rect(rect, Color("#3a4048"), false, 1.0)

	var name_col := Color("#ebe6d6")
	if st.locked:
		name_col = Color("#6a6f68")
	elif rank >= int(perk.max):
		name_col = Color("#9fd07a")
	var label: String = perk.name
	if int(perk.max) > 1:
		label += "  %d/%d" % [rank, int(perk.max)]
	draw_string(font, rect.position + Vector2(8, 15), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 100, 12, name_col)
	draw_string(font, rect.position + Vector2(8, 28), perk.desc, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 9,
		Color(1, 1, 1, 0.2 if st.locked else 0.38))
	draw_string(font, rect.position + Vector2(0, 15), "BUY" if st.ok else st.reason,
		HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8, 10,
		Color("#9fd07a") if st.ok else (Color("#c9a227") if st.locked else Color("#7a7f76")))


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


## The roster: one row per person on the left, the four jobs on the right for
## whoever is selected. Same shape as the character sheet, and for the same
## reason — the decision is "what is this person for", and it belongs beside
## the pack you would be stocking for them.
func _crew_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if mode != "crew":
		return out
	var panel := _panel()
	var x0 := panel.position.x + 24.0
	var top := panel.position.y + 96.0
	var col_w := 300.0

	var crew := sim.crew.alive()
	var rows := int((panel.size.y - 160.0) / 34.0)
	crew_top = clampi(crew_top, 0, maxi(0, crew.size() - rows))
	for i in range(crew_top, mini(crew.size(), crew_top + rows)):
		out.append({"who": crew[i].id, "job": "",
			"rect": Rect2(x0, top + (i - crew_top) * 34.0, col_w, 30.0)})

	# The job column only exists once somebody is selected: four buttons with
	# nobody to apply them to would be four ways to be told no.
	if _selected_survivor() != null:
		var px := x0 + col_w + 22.0
		var pw := panel.position.x + panel.size.x - 24.0 - px
		for i in range(Config.JOB_IDS.size()):
			out.append({"who": 0, "job": String(Config.JOB_IDS[i]),
				"rect": Rect2(px, top + i * 42.0, pw, 38.0)})
	return out


func _selected_survivor() -> SurvivorSim:
	var crew := sim.crew.alive()
	if crew.is_empty():
		return null
	for s in crew:
		if s.id == crew_sel:
			return s
	crew_sel = crew[0].id
	return crew[0]


func _draw_crew(font: Font, panel: Rect2) -> void:
	var lim := sim.crew.limits(sim)
	var crew := sim.crew.alive()

	# The two limits, and which one is actually in the way. Being told "full"
	# without being told which kind of full is useless.
	var binding := "bunks" if int(lim.bunks) <= int(lim.charisma) else "Charisma"
	draw_string(font, panel.position + Vector2(24, 60),
		"%d / %d" % [crew.size(), int(lim.cap)], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ebe6d6"))
	draw_string(font, panel.position + Vector2(70, 60),
		"Charisma %d · Bunks %d — %s is the limit" % [int(lim.charisma), int(lim.bunks), binding],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#8a8f84"))

	# Rations are the upkeep, and they come out of the stash and nowhere else.
	var rations := sim.crew.rations_held(sim)
	var per_min: float = crew.size() * Config.SURVIVOR.upkeep_per_min * (player.upkeep_mul)
	var rcol := Color("#8a8f84")
	if sim.crew.debt > 1.0:
		rcol = Color("#e05a4a")
	elif per_min > 0.0 and rations < per_min * 3.0:
		rcol = Color("#d9c46a")
	var supply := "%d Rations in the stash" % rations
	if per_min > 0.0:
		supply += "  ·  %.1f/min  ·  about %d min left" % [per_min, int(rations / maxf(0.01, per_min))]
	if sim.crew.debt > 1.0:
		supply = "OUT OF RATIONS — they are starving"
	draw_string(font, Vector2(panel.position.x, panel.position.y + 60), supply,
		HORIZONTAL_ALIGNMENT_RIGHT, panel.size.x - 24.0, 11, rcol)

	if crew.is_empty():
		var found := sim.crew.rescues.size()
		draw_string(font, panel.position + Vector2(24, 120),
			"Nobody yet. There are %d people out there to find — look inside buildings." % found,
			HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 48.0, 12, Color("#8a8f84"))
		draw_string(font, panel.position + Vector2(24, 142),
			"You will need a Bunk for each of them, and the Charisma to lead them.",
			HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 48.0, 11, Color(1, 1, 1, 0.35))
		return

	var sel := _selected_survivor()
	for row in _crew_rows():
		var rect: Rect2 = row.rect
		var hot: bool = rect.has_point(mouse)
		if int(row.who) != 0:
			_draw_crew_row(font, rect, int(row.who), hot)
		else:
			_draw_job_row(font, rect, String(row.job), sel, hot)

	draw_string(font, Vector2(panel.position.x + 24, panel.position.y + panel.size.y - 8),
		"click a name to select  ·  click a job to reassign  ·  they eat and shoot from the stash, never your pack",
		HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 40, 10, Color(1, 1, 1, 0.4))


func _draw_crew_row(font: Font, rect: Rect2, id: int, hot: bool) -> void:
	var s: SurvivorSim = null
	for o in sim.crew.alive():
		if o.id == id:
			s = o
			break
	if s == null:
		return
	var job: Dictionary = Config.JOBS.get(s.job, Config.JOBS.guard)
	var selected := s.id == crew_sel
	draw_rect(rect, Color("#242a32") if selected else (Color("#1c2028") if hot else Color("#181b20")))
	draw_rect(rect, Color(String(job.color)) if selected else Color("#3a4048"), false, 1.0)

	var name_col := Color("#ebe6d6")
	if s.downed:
		name_col = Color("#e05a4a")
	elif s.hungry:
		name_col = Color("#d9c46a")
	draw_string(font, rect.position + Vector2(8, 14), s.display_name, HORIZONTAL_ALIGNMENT_LEFT, 90, 12, name_col)
	draw_string(font, rect.position + Vector2(96, 14), "LV %d" % s.level, HORIZONTAL_ALIGNMENT_LEFT, 44, 10, Color("#8a8f84"))
	draw_string(font, rect.position + Vector2(0, 14), String(job.short) + ("*" if s.posted else ""),
		HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8, 11, Color(String(job.color)))

	# Health as a thin bar under the name, plus whatever is wrong with them.
	var bar := Rect2(rect.position.x + 8, rect.position.y + 20, 130.0, 4.0)
	draw_rect(bar, Color(0, 0, 0, 0.55))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(s.hp / maxf(1.0, s.max_hp), 0.0, 1.0), bar.size.y)),
		Color("#c8423a") if s.hp < s.max_hp * 0.35 else Color("#7ec46a"))
	var note := ""
	if s.downed:
		note = "DOWN — %.0fs" % maxf(0.0, s.down_t)
	elif s.hungry:
		note = "hungry"
	elif s.out_of_ammo:
		note = "no ammo in the stash"
	elif not s.carrying.is_empty() or not s.carry_items.is_empty():
		note = "hauling home"
	if not note.is_empty():
		draw_string(font, rect.position + Vector2(146, 24), note, HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x - 154, 9, Color("#e05a4a") if s.downed else Color(1, 1, 1, 0.4))
	draw_string(font, rect.position + Vector2(0, 25), "%d kills" % s.kills,
		HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8, 9, Color(1, 1, 1, 0.3))


func _draw_job_row(font: Font, rect: Rect2, id: String, s: SurvivorSim, hot: bool) -> void:
	if s == null:
		return
	var job: Dictionary = Config.JOBS[id]
	var current := s.job == id
	# Sniper is the only job that can be refused, and it says why up front
	# rather than after the click.
	var blocked := ""
	if id == "sniper" and not current and sim.crew.free_towers(sim).is_empty():
		blocked = "No free Watchtower"

	draw_rect(rect, Color("#242a32") if current else (Color("#1c2028") if hot and blocked.is_empty() else Color("#181b20")))
	draw_rect(rect, Color(String(job.color)) if current else Color("#3a4048"), false, 1.0)
	var col := Color(String(job.color))
	if not blocked.is_empty():
		col = Color("#6a6f68")
	draw_string(font, rect.position + Vector2(8, 16), String(job.name), HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 100, 12, col)
	draw_string(font, rect.position + Vector2(8, 30), String(job.desc), HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 16, 9, Color(1, 1, 1, 0.2 if not blocked.is_empty() else 0.38))
	var right := "ON DUTY" if current else ("ASSIGN" if blocked.is_empty() else blocked)
	draw_string(font, rect.position + Vector2(0, 16), right, HORIZONTAL_ALIGNMENT_RIGHT,
		rect.size.x - 8, 10, Color("#9fd07a") if current else (Color("#c9a227") if blocked.is_empty() else Color("#7a7f76")))
