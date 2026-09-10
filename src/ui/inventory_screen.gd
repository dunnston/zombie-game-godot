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
## contents, and **BED** swaps them for a Raised Bed's seed slot, fertilizer
## slot and water meter — for the same reason again: what you plant is a
## decision about what you are carrying.

const CELL := 44.0
const GAP := 4.0
const BAG_COLS := 6
const STORE_COLS := 6
const HAUL_COLS := 4
const ROW := 22.0                # a recipe row in the craft list
## Modes that are one panel opened on one thing, rather than tabs of the pack.
const SINGLE := ["store", "bed", "bench", "door", "leave"]

var sim: GameSim
var player: PlayerSim
var drag := {}                   # {from: cell, id, n} while held
var hover := {}
var mouse := Vector2.ZERO

## "pack", "craft", "char", "crew", "store", "bed", "bench", or an instance's
## "door" and "leave".
var mode := "pack"
## The instance whose door is open, for the ENTER button.
var door_kind := ""
## The tile of the container being looked into, or (-1, -1). A tile rather
## than the container itself, so the reach check happens every frame and
## walking away closes the screen.
var store_tile := Vector2i(-1, -1)
## The car whose boot is open, or 0. A car is not on a tile, so it needs its
## own handle — and the reach check has to follow it, because it moves.
var store_car := 0
## The tile of the Raised Bed being worked, or (-1, -1). A tile for the same
## reason a chest is one: the reach is checked every frame and walking away
## closes the screen.
var bed_tile := Vector2i(-1, -1)
## The tile of the workbench or station being used, or (-1, -1). E opens
## BENCH mode on it; C is CRAFT, which is always by hand. A tile for the same
## reason a chest is one: walking away closes the screen.
var bench_tile := Vector2i(-1, -1)
## The little menu a plain click on something usable opens beside its cell —
## EAT, DRINK or USE, and DROP. {cell, id, rows: [{act, label, rect}]}.
var pop := {}
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
	pop = {}
	if visible:
		if mode in SINGLE:
			mode = "pack"
		store_tile = Vector2i(-1, -1)
		store_car = 0
		bed_tile = Vector2i(-1, -1)
		bench_tile = Vector2i(-1, -1)
	else:
		_cancel_drag()


## Walking up to a chest and pressing E opens it here.
func open_store(tile: Vector2i) -> void:
	store_tile = tile
	store_car = 0
	mode = "store"
	visible = true


## The boot of a car, in the same two-panel screen a chest uses. The boot is a
## `Slots` for exactly this reason: one storage screen, not two.
func open_boot(car_id: int) -> void:
	store_car = car_id
	store_tile = Vector2i(-1, -1)
	mode = "store"
	visible = true


## Walking up to a Raised Bed that is not ready and pressing E opens it here.
## A ripe one never gets this far: the key harvests it where you stand.
func open_bed(tile: Vector2i) -> void:
	bed_tile = tile
	store_tile = Vector2i(-1, -1)
	store_car = 0
	mode = "bed"
	visible = true


## Walking up to a workbench or a Chemistry Station and pressing E opens its
## recipe list here, with the upgrade on a button rather than on the key.
func open_bench(tile: Vector2i) -> void:
	bench_tile = tile
	store_tile = Vector2i(-1, -1)
	store_car = 0
	bed_tile = Vector2i(-1, -1)
	craft_top = 0
	pop = {}
	mode = "bench"
	visible = true


## An instance's door: the rules, what you are carrying, and ENTER. The pack is
## on screen on purpose — what you bring is the whole of the decision (§6.6),
## and it is made here, once, with the things themselves in front of you.
func open_door(kind: String) -> void:
	door_kind = kind
	store_tile = Vector2i(-1, -1)
	store_car = 0
	bed_tile = Vector2i(-1, -1)
	bench_tile = Vector2i(-1, -1)
	pop = {}
	mode = "door"
	visible = true


## The way out of an instance before the boss is down: exactly what walking out
## now costs, and LEAVE. Nothing is ever forfeited on the key alone.
func open_leave() -> void:
	store_tile = Vector2i(-1, -1)
	store_car = 0
	bed_tile = Vector2i(-1, -1)
	bench_tile = Vector2i(-1, -1)
	pop = {}
	mode = "leave"
	visible = true


## The bench being used, or empty when it is gone or out of reach — which is
## also how the screen knows to close itself.
func bench_struct() -> Dictionary:
	if bench_tile.x < 0:
		return {}
	var s := sim.structs.at_tile(bench_tile.x, bench_tile.y)
	if s.is_empty() or s.destroyed:
		return {}
	var r: float = Config.BUILD.bench_range
	return s if player.pos.distance_squared_to(s.pos) <= r * r else {}


## The bed being worked, or empty when there is none in reach — which is also
## how the screen knows to close itself.
func bed() -> Dictionary:
	return {} if bed_tile.x < 0 else Farming.reachable_bed(sim, player, bed_tile.x, bed_tile.y)


## The container being looked into, or null when there is none in reach —
## which is also how the screen knows to close itself.
func store() -> Slots:
	if store_car > 0:
		var v := sim.cars.by_id(store_car)
		if v.is_empty():
			return null
		var r: float = Config.CAR.enter_range
		return v.trunk if player.pos.distance_squared_to(v.pos) <= r * r else null
	if store_tile.x < 0:
		return null
	return sim.structs.reachable_store(player, store_tile.x, store_tile.y)


## The bench this screen crafts at: by hand on the C tab wherever you are
## standing, and in BENCH mode the tier of the bench that was *opened* — not
## of whatever else stands in reach, or a Chemistry Station beside a
## workbench would list the workbench's recipes under its own title (Codex,
## PR #25). A station is not a rung of the ladder, so it is 0. The host
## re-derives it from where the player is either way.
func bench() -> int:
	if mode != "bench":
		return 0
	var s := bench_struct()
	return int(s.tier) if s.get("type", "") == "workbench" else 0


## The station the opened structure is, or "" for a workbench or none.
func bench_station() -> String:
	return String(bench_struct().get("def", {}).get("station", "")) if mode == "bench" else ""


func recipes() -> Array:
	if mode != "bench":
		return Crafting.visible_recipes(player, 0)
	var st := bench_station()
	if st.is_empty():
		return Crafting.visible_recipes(player, bench())
	# A station lists its own work and nothing else: the hand basics are on C.
	return Crafting.visible_recipes(player, 0, {st: true}).filter(
		func(r: Dictionary) -> bool: return String(r.get("station", "")) == st)


## Called every frame by the scene: a store screen closes when you walk away
## from the thing you opened.
func tick() -> void:
	if visible and mode == "store" and store() == null:
		visible = false
		_cancel_drag()
	if visible and mode == "bed" and bed().is_empty():
		visible = false
		_cancel_drag()
	if visible and mode == "bench" and bench_struct().is_empty():
		visible = false
		_cancel_drag()
	# A door panel belongs to the door: step away from it, or through it, and
	# the question is no longer being asked.
	if visible and mode == "door" and (sim.instance != null or Instance.feature_near(sim, player, ["instance_door"]).is_empty()):
		visible = false
		_cancel_drag()
	if visible and mode == "leave" and (sim.instance == null or Instance.feature_near(sim, player, ["leave"]).is_empty()):
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
	var names := ["pack", "craft", "char", "crew"]
	if mode in SINGLE:
		names = [mode]
	var x := panel.position.x + 24.0
	for name in names:
		var label := String(name).to_upper()
		var w := 84.0
		if name == "door":
			label = Instance.title(door_kind).to_upper()
			w = 260.0
		elif name == "leave":
			label = "WALK OUT"
			w = 140.0
		elif name == "bench":
			var s := bench_struct()
			label = "WORKBENCH II" if s.get("type", "") == "workbench" and int(s.get("tier", 1)) >= 2 \
				else String(s.get("def", {}).get("name", "Workbench")).to_upper()
			w = 190.0
		out.append({"mode": name, "label": label, "rect": Rect2(x, panel.position.y + 14.0, w, 24.0)})
		x += w + 6.0
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
	elif mode == "bed":
		# Two cells, typed: the seed slot takes seed and the fertilizer slot
		# takes fertilizer, and nothing else goes in either. The gauges below
		# them are drawn, not clicked.
		gx = x0 + CELL + 96.0
		out.append({"kind": "seed", "slot": "seed", "index": -1, "rect": Rect2(x0, y0, CELL, CELL)})
		out.append({"kind": "fert", "slot": "fert", "index": -1, "rect": Rect2(x0, y0 + CELL + GAP, CELL, CELL)})
	elif mode == "door" or mode == "leave":
		# The rules down the left, and what you are carrying beside them.
		gx = x0 + 330.0
	elif mode == "pack":
		for i in range(Config.GEAR_SLOTS.size()):
			var slot: String = Config.GEAR_SLOTS[i]
			out.append({"kind": "equip", "slot": slot, "index": -1,
				"rect": Rect2(x0, y0 + i * (CELL + GAP), CELL, CELL)})

	# The pack grid moves right in store mode but is otherwise the same grid.
	if mode != "craft" and mode != "bench" and mode != "char" and mode != "crew":
		for i in range(player.bag.size()):
			out.append({"kind": "bag", "slot": "", "index": i,
				"rect": Rect2(gx + (i % BAG_COLS) * (CELL + GAP), y0 + (i / BAG_COLS) * (CELL + GAP), CELL, CELL)})

	# Inside an instance, the haul beside the pack: what you are trying to carry
	# out, on its own budget, and nowhere else.
	if mode == "pack" and sim.instance != null:
		var hx := _haul_x()
		for i in range(player.haul.size()):
			out.append({"kind": "haul", "slot": "", "index": i,
				"rect": Rect2(hx + (i % HAUL_COLS) * (CELL + GAP), y0 + (i / HAUL_COLS) * (CELL + GAP), CELL, CELL)})

	var hy := panel.position.y + panel.size.y - CELL - 26.0
	for i in range(player.hotbar.size()):
		out.append({"kind": "hotbar", "slot": "", "index": i,
			"rect": Rect2(gx + i * (CELL + GAP), hy, CELL, CELL)})
	return out


## Where the haul grid starts: to the right of the pack grid in PACK mode.
func _haul_x() -> float:
	var x0 := _panel().position.x + 24.0
	return x0 + CELL + 96.0 + BAG_COLS * (CELL + GAP) + 18.0


## The recipe rows on screen, as {recipe, rect}.
## The craft list: everything worn that you are carrying, then everything the
## bench can make. Repairs go on top because they are the shorter list and
## the more urgent one — a broken axe is why you walked to the bench.
##
## A row carries `repair` (a weapon id) or `recipe` (a row from `RECIPES`),
## never both, and both are drawn and hit-tested off this one list so what
## looks clickable is clickable.
func _craft_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if mode != "craft" and mode != "bench":
		return out
	var panel := _panel()
	var list: Array = []
	# Mending is a workbench's job (or your hands'); a station mends nothing.
	if bench_station().is_empty():
		for row in Wear.worn_carried(player):
			list.append({"repair": row})
		# Then every weapon a bench could take further: the level beside the
		# mending, because both are the bench that made it doing more work.
		for row in Upgrade.upgradeable_carried(player):
			list.append({"upgrade": row})
	for r in recipes():
		list.append({"recipe": r})
	var top := panel.position.y + 76.0
	var visible_rows := int((panel.size.y - 130.0) / ROW)
	craft_top = clampi(craft_top, 0, maxi(0, list.size() - visible_rows))
	for i in range(craft_top, mini(list.size(), craft_top + visible_rows)):
		var row: Dictionary = list[i].duplicate()
		row["rect"] = Rect2(panel.position.x + 24.0, top + (i - craft_top) * ROW, panel.size.x - 48.0, ROW - 2.0)
		out.append(row)
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
	for r in _craft_rows():
		if r.has("recipe") and r.recipe.id == id:
			return r.rect.get_center()
	return Vector2.ZERO


## The middle of a weapon's MEND row, for the smoke run's cursor.
func repair_centre(id: String) -> Vector2:
	for r in _craft_rows():
		if r.has("repair") and String(r.repair.id) == id:
			return r.rect.get_center()
	return Vector2.ZERO


## The middle of a weapon's UPGRADE row, likewise.
func upgrade_centre(id: String) -> Vector2:
	for r in _craft_rows():
		if r.has("upgrade") and String(r.upgrade.id) == id:
			return r.rect.get_center()
	return Vector2.ZERO


## The middle of a panel button, for the smoke run's cursor.
func button_centre(id: String) -> Vector2:
	for b in _buttons():
		if b.id == id:
			return b.rect.get_center()
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
		"haul": return player.haul.at(cell.index)
		"store":
			var s := store()
			return s.at(cell.index) if s != null else {}
		"equip":
			var id: String = player.equip.get(cell.slot, "")
			return {"id": id, "n": 1} if not id.is_empty() else {}
		"seed", "fert":
			var s := bed()
			if s.is_empty():
				return {}
			var id := String(s.seed if cell.kind == "seed" else s.fert)
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
	# The click menu owns the next press, wherever it lands: on a row it does
	# that row, anywhere else it just closes. Either way nothing else happens,
	# so dismissing it can never also drag or drop something.
	if not pop.is_empty() and mb.pressed:
		var act := ""
		for row in pop.rows:
			if row.rect.has_point(mouse) and mb.button_index == MOUSE_BUTTON_LEFT:
				act = String(row.act)
		_pop_do(act)
		queue_redraw()
		return
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
	for r in _craft_rows():
		if r.rect.has_point(at):
			if r.has("repair"):
				Actions.repair_weapon(sim, player, String(r.repair.c), int(r.repair.i), bench())
			elif r.has("upgrade"):
				Actions.upgrade_weapon(sim, player, String(r.upgrade.c), int(r.upgrade.i), bench())
			else:
				Actions.craft(sim, player, r.recipe, bench())
			return true
	for r in _crew_rows():
		if not r.rect.has_point(at):
			continue
		if int(r.who) != 0:
			crew_sel = int(r.who)
		else:
			var who := _selected_survivor()
			if who != null:
				Actions.assign_job(sim, who, String(r.job))
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
				Actions.raise_attribute(sim, player, String(r.attr))
		else:
			Actions.buy_perk(sim, player, String(r.perk))
		return true
	return false


func _buttons() -> Array[Dictionary]:
	var panel := _panel()
	var out: Array[Dictionary] = []
	var y := panel.position.y + panel.size.y - 26.0 - CELL - 34.0
	if mode == "store":
		out.append({"id": "deposit", "label": "DEPOSIT ALL", "rect": Rect2(panel.position.x + 24.0, y, 120.0, 24.0)})
		out.append({"id": "withdraw", "label": "TAKE SUPPLIES", "rect": Rect2(panel.position.x + 152.0, y, 130.0, 24.0)})
		# Refuelling belongs on the boot screen: it is the other thing you
		# stopped the car to do, and it needs somewhere to live.
		if store_car > 0:
			out.append({"id": "refuel", "label": "REFUEL", "rect": Rect2(panel.position.x + 290.0, y, 90.0, 24.0)})
	elif mode == "bed":
		out.append({"id": "water", "label": "WATER", "rect": Rect2(panel.position.x + 24.0, y, 100.0, 24.0)})
		# HARVEST is only offered when there is something to harvest. A button
		# that is always there and usually refuses teaches nothing.
		if Farming.ready(bed()):
			out.append({"id": "harvest", "label": "HARVEST", "rect": Rect2(panel.position.x + 132.0, y, 110.0, 24.0)})
	elif mode == "pack":
		out.append({"id": "equip_best", "label": "EQUIP BEST", "rect": Rect2(panel.position.x + 24.0, y, 120.0, 24.0)})
	elif mode == "door":
		out.append({"id": "enter", "label": "ENTER", "rect": Rect2(panel.position.x + 24.0, y, 120.0, 24.0)})
		out.append({"id": "close", "label": "NOT YET", "rect": Rect2(panel.position.x + 152.0, y, 110.0, 24.0)})
	elif mode == "leave":
		out.append({"id": "leave", "label": "LEAVE WITHOUT IT", "rect": Rect2(panel.position.x + 24.0, y, 170.0, 24.0)})
		out.append({"id": "close", "label": "STAY", "rect": Rect2(panel.position.x + 202.0, y, 90.0, 24.0)})
	elif mode == "bench":
		# The upgrade lives here, priced, rather than on E: the key you press
		# to look at a bench must never be the key that spends on it.
		var s := bench_struct()
		if s.get("type", "") == "workbench" and int(s.get("tier", 1)) < 2:
			var w := 300.0
			out.append({"id": "upgrade", "label": "UPGRADE  ·  %s" % Structures.cost_label(Config.BENCH_UPGRADE_COST),
				"rect": Rect2(panel.position.x + panel.size.x - 24.0 - w, panel.position.y + 44.0, w, 22.0)})
	return out


func _press_button(id: String) -> void:
	match id:
		"deposit":
			Actions.deposit_all(sim, player, store_tile, store_car)
		"withdraw":
			Actions.withdraw_supplies(sim, player, store_tile, store_car)
		"refuel":
			Actions.refuel(sim, player, store_car)
		"water":
			Actions.water_bed(sim, player, bed_tile)
		"harvest":
			Actions.harvest(sim, player, bed_tile)
		"equip_best":
			Actions.equip_best(sim, player)
		"upgrade":
			Actions.upgrade_bench(sim, player, bench_tile)
		"enter":
			Actions.enter_instance(sim, player, door_kind)
			visible = false
		"leave":
			Actions.leave_instance(sim, player)
			visible = false
		"close":
			visible = false


func _press(cell: Dictionary, mb: InputEventMouseButton) -> void:
	if cell.is_empty():
		return
	# What is in the ground stays in the ground. Nothing is dragged, dropped
	# or split out of a bed's two slots: the seed comes back at harvest and
	# the fertilizer is spent on the crop, and letting either be pulled out
	# again would make planting free.
	if cell.kind == "seed" or cell.kind == "fert":
		return
	var stack := _stack_in(cell)
	if stack.is_empty():
		return
	# Ctrl+click drops, shift+click splits: both are decisions about the stack
	# you already clicked, so neither starts a drag.
	if mb.ctrl_pressed:
		if cell.kind == "equip":
			Actions.drop_equipped(sim, player, cell.slot)
		else:
			Actions.drop_stack(sim, player, cell.kind, cell.index, true, store_tile, store_car)
		return
	if mb.shift_pressed and cell.kind != "equip":
		var cont := Equipment.container(player, cell.kind, store())
		var free := cont.first_empty() if cont != null else -1
		if free >= 0:
			Actions.split_stack(sim, player, cell.kind, cell.index, free, store_tile, store_car)
		return
	drag = {"from": cell, "id": stack.id, "n": stack.n}


func _release(cell: Dictionary) -> void:
	if drag.is_empty():
		return
	var from: Dictionary = drag.from
	var drag_id := String(drag.id)
	drag = {}
	if cell.is_empty():
		# Released outside the grids: that is a drop, the same gesture as
		# dragging something out of the panel.
		if not _panel().has_point(mouse):
			if from.kind == "equip":
				Actions.drop_equipped(sim, player, from.slot)
			else:
				Actions.drop_stack(sim, player, from.kind, from.index, true, store_tile, store_car)
		return
	if cell.kind == from.kind and cell.index == from.index and cell.slot == from.slot:
		# Pressed and let go on the same cell: a click, not a drag. On
		# something you can eat or use, that opens the menu that says so.
		_open_pop(cell)
		return
	# A bed's slots are typed: dragging a Machete at the seed cell is refused
	# with a reason rather than silently doing nothing, because a refusal you
	# cannot see reads as a broken screen.
	if cell.kind == "seed" or cell.kind == "fert":
		_put_in_bed(String(cell.kind), drag_id)
		return
	if from.kind == "equip" and cell.kind == "equip":
		return
	if from.kind == "equip":
		Actions.unequip_to(sim, player, from.slot, cell.kind, cell.index)
	elif cell.kind == "equip":
		Actions.equip_from_slot(sim, player, from.kind, from.index, cell.slot)
	else:
		Actions.move_stack(sim, player, from.kind, from.index, cell.kind, cell.index, store_tile, store_car)


## One seed or one dose of fertilizer into the bed, or the reason it will not
## go. Both go through `Actions`, so on a guest this is a command to the host
## and the range and cost checks are the ones solo uses (invariant 8).
func _put_in_bed(slot: String, id: String) -> void:
	if bed().is_empty():
		return
	if not Farming.accepts(slot, id):
		sim.notify("%s is not %s" % [Items.name_of(id), "a seed" if slot == "seed" else "fertilizer"], "#c96a5a")
		return
	if slot == "seed":
		Actions.plant(sim, player, bed_tile, id)
	else:
		Actions.fertilize(sim, player, bed_tile, id)


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
		Actions.unequip(sim, player, cell.slot)
		return
	# Standing at a bed, the obvious thing to do with a seed is plant it —
	# and with a bag of compost, dig it in. Nothing else about right-click
	# changes, so eating and equipping still work at the allotment.
	if mode == "bed":
		if cell.kind == "seed" or cell.kind == "fert":
			return
		if Config.CROPS.has(stack.id):
			_put_in_bed("seed", String(stack.id))
			return
		if Config.FERTILIZER.has(stack.id):
			_put_in_bed("fert", String(stack.id))
			return
	# Right-click means "do the obvious thing with this". For gear that is
	# wearing it; for a meal, a bandage or a dose it is taking it. Moving one
	# to the hotbar is still a drag — the same gesture everything else moves
	# by — and inside a store the obvious thing is still to move it across.
	# Out of the haul, the obvious thing is into the pack — where a find can be
	# used. Nothing is eaten or worn straight out of what you are carrying out.
	if mode != "store" and cell.kind != "haul" and Items.kind_of(stack.id) == "consumable" \
		and not Config.CONSUMABLES[stack.id].get("tool", false):
		Actions.use_slot(sim, player, cell.kind, cell.index)
		return
	if mode != "store" and not Items.gear_slot(stack.id).is_empty() and cell.kind == "bag":
		Actions.equip_from_bag(sim, player, cell.index)
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
	Actions.move_stack(sim, player, cell.kind, cell.index, to, free, store_tile, store_car)


func _cancel_drag() -> void:
	drag = {}


## What using `id` is called on the click menu, or "" when it is not
## something you use: EAT, DRINK or USE. A lockpick or Neural Tissue is
## carried for something else, and so is anything that is not a consumable.
static func use_verb(id: String) -> String:
	if Items.kind_of(id) != "consumable":
		return ""
	var c: Dictionary = Config.CONSUMABLES.get(id, {})
	if c.is_empty() or c.get("tool", false):
		return ""
	return String(c.get("verb", "EAT" if c.get("food", false) else "USE"))


## Opens the click menu beside a pack or hotbar cell holding something usable.
func _open_pop(cell: Dictionary) -> void:
	pop = {}
	if cell.kind != "bag" and cell.kind != "hotbar":
		return
	var id := String(_stack_in(cell).get("id", ""))
	var verb := use_verb(id)
	if verb.is_empty():
		return
	var at: Vector2 = cell.rect.position + Vector2(cell.rect.size.x + 2.0, 0.0)
	var rows: Array = []
	var i := 0
	for r in [["use", verb], ["drop", "DROP"]]:
		rows.append({"act": r[0], "label": r[1], "rect": Rect2(at + Vector2(0.0, i * 24.0), Vector2(78.0, 22.0))})
		i += 1
	pop = {"cell": cell, "id": id, "rows": rows}


## Does what the menu row says — if the cell still holds what it was opened
## on — and closes the menu. Through `Actions`, so on a guest it is a command
## to the host like every other pack gesture (invariant 8).
func _pop_do(act: String) -> void:
	var cell: Dictionary = pop.get("cell", {})
	var id := String(pop.get("id", ""))
	pop = {}
	if act.is_empty() or cell.is_empty() or String(_stack_in(cell).get("id", "")) != id:
		return
	if act == "use":
		Actions.use_slot(sim, player, cell.kind, cell.index)
	elif act == "drop":
		Actions.drop_stack(sim, player, cell.kind, cell.index, true, store_tile, store_car)


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
		draw_string(font, t.rect.position + Vector2(0, 17), t.label, HORIZONTAL_ALIGNMENT_CENTER,
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
		"craft", "bench":
			_draw_craft(font, panel)
		"char":
			_draw_char(font, panel)
		"crew":
			_draw_crew(font, panel)
		"bed":
			_draw_bed(font, panel)
		"door":
			_draw_door(font, panel)
		"leave":
			_draw_leave(font, panel)
		"store":
			var s := store()
			var label := "%d / %d slots" % [s.used() if s != null else 0, s.size() if s != null else 0]
			if store_car > 0:
				var v := sim.cars.by_id(store_car)
				if not v.is_empty():
					label = "Boot  %d / %d units  ·  fuel %d / %d" % [
						Vehicles.trunk_load(v), int(Config.CAR.trunk_cap),
						roundi(v.fuel), int(Config.CAR.fuel_max)]
			draw_string(font, panel.position + Vector2(24, 60), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8a8f84"))
		_:
			var dr := player.armor_dr
			draw_string(font, panel.position + Vector2(24, 60), "ARMOUR  %d%%" % roundi(dr * 100.0),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#9fd07a") if dr > 0.0 else Color("#8a8f84"))
			if mode == "pack" and sim.instance != null:
				draw_string(font, Vector2(_haul_x(), panel.position.y + 60), "HAUL  %.0f / %.0f  ·  out only past the boss" % [
					player.haul.weight(), float(Config.INSTANCE.haul_cap)],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#d8c98a"))

	for cell in _cells():
		_draw_cell(font, cell)
	for b in _buttons():
		var hot: bool = b.rect.has_point(mouse)
		draw_rect(b.rect, Color("#242a32") if hot else Color("#181b20"))
		draw_rect(b.rect, Color("#8a949e") if hot else Color("#3a4048"), false, 1.0)
		draw_string(font, b.rect.position + Vector2(0, 16), b.label, HORIZONTAL_ALIGNMENT_CENTER, b.rect.size.x, 11, Color("#d5d0c4"))

	# The dragging hint is about the grids, and the character sheet has none —
	# it prints its own line instead, and two of them overlap.
	if mode == "bed":
		draw_string(font, Vector2(panel.position.x + 24, panel.position.y + panel.size.y - 8),
			"drag a seed or a bag of feed into a slot  ·  right-click does the same  ·  a dry bed stalls, it never dies",
			HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 40, 10, Color(1, 1, 1, 0.4))
	elif mode != "char" and mode != "crew":
		draw_string(font, Vector2(panel.position.x + 24, panel.position.y + panel.size.y - 8),
			"drag to move  ·  click food to eat  ·  right-click to equip, stow or use  ·  ctrl+click to drop  ·  shift+click to split",
			HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 40, 10, Color(1, 1, 1, 0.4))

	if not pop.is_empty():
		# Drawn last and instead of the tooltip, so nothing sits over it.
		for row in pop.rows:
			var hot: bool = row.rect.has_point(mouse)
			draw_rect(row.rect, Color("#2c333c") if hot else Color("#1c2026"))
			draw_rect(row.rect, Color("#9fd07a") if hot else Color("#4a525c"), false, 1.0)
			draw_string(font, row.rect.position + Vector2(0, 15), row.label, HORIZONTAL_ALIGNMENT_CENTER,
				row.rect.size.x, 11, Color("#ebe6d6"))
	elif not drag.is_empty():
		var r := Rect2(mouse - Vector2(CELL, CELL) / 2.0, Vector2(CELL, CELL))
		var drag_tex := Items.icon_of(drag.id)
		if drag_tex != null:
			draw_texture_rect(drag_tex, Items.art_rect(drag_tex, r), false, Color(1, 1, 1, 0.8))
		else:
			draw_rect(r, Color(Items.color_of(drag.id), 0.8))
		draw_string(font, r.position + Vector2(0, CELL - 6), _short(drag.id), HORIZONTAL_ALIGNMENT_CENTER, CELL, 9, Color.BLACK)
	elif not hover.is_empty():
		_draw_tooltip(font, _stack_in(hover))


## The door's rules, down the left beside your pack. Six lines, because that is
## the whole of what is different in there, and each is a rule you will meet.
func _draw_door(font: Font, panel: Rect2) -> void:
	var x := panel.position.x + 24.0
	var y := panel.position.y + 80.0
	var why := Instance.refusal(sim, player, door_kind)
	var lines := [
		["What you are carrying is all you will have in there.", "#ebe6d6"],
		["No building, and no stash.", "#d8c98a"],
		["What you find goes in the HAUL — %d units, and it weighs nothing in a fight." % int(Config.INSTANCE.haul_cap), "#ebe6d6"],
		["Only the boss lets it out. Walk out early, or die, and it keeps everything you found.", "#e0a070"],
		["What you brought is yours whatever happens.", "#9fd07a"],
		["Clear it and the doors are chained until tomorrow.", "#8a8f84"],
	]
	if not why.is_empty():
		lines = [[why, "#c96a5a"]]
	for l in lines:
		draw_multiline_string(font, Vector2(x, y), String(l[0]), HORIZONTAL_ALIGNMENT_LEFT, 290.0, 12, -1, Color(String(l[1])))
		y += 46.0


## What walking out now costs, item by item: everything found in here, wherever
## it is now — the haul or your pack.
func _draw_leave(font: Font, panel: Rect2) -> void:
	var x := panel.position.x + 24.0
	var y := panel.position.y + 80.0
	var inst := sim.instance
	if inst == null:
		return
	draw_multiline_string(font, Vector2(x, y), "Walk out now and %s keeps everything you found." % Instance.title(inst.kind),
		HORIZONTAL_ALIGNMENT_LEFT, 290.0, 13, -1, Color("#e0a070"))
	y += 48.0
	var found: Dictionary = inst.gained.get(player.seat, {})
	var parts: Array[String] = []
	for id: String in found:
		var n := mini(int(found[id]), Instance.held_count(player, id))
		if n > 0:
			parts.append("%d %s" % [n, Items.name_of(id)])
	var lose := "Nothing yet — you have not found anything." if parts.is_empty() else "You would lose: " + ",  ".join(parts)
	draw_multiline_string(font, Vector2(x, y), lose, HORIZONTAL_ALIGNMENT_LEFT, 290.0, 12, -1, Color("#ebe6d6"))
	y += 96.0
	draw_multiline_string(font, Vector2(x, y), "Put down what is in the gym and all of it comes with you.",
		HORIZONTAL_ALIGNMENT_LEFT, 290.0, 12, -1, Color("#9fd07a"))
	# With company, walking out takes everyone: say who it is waiting for.
	var why := Instance.leave_refusal(sim, player)
	if not why.is_empty():
		draw_multiline_string(font, Vector2(x, y + 48.0), why, HORIZONTAL_ALIGNMENT_LEFT, 290.0, 12, -1, Color("#c96a5a"))


## The Raised Bed's two gauges. The water meter is the thing the owner asked
## for and it says two numbers on purpose: how full it is, and roughly how
## long that lasts — a percentage alone tells you nothing about whether to
## walk back tonight or tomorrow.
##
## Nothing here is a warning. A dry bed is drawn amber rather than red because
## running dry costs you time and never the crop, and colouring it like damage
## would be the screen telling a lie about the rules (pillar 1).
func _draw_bed(font: Font, panel: Rect2) -> void:
	var s := bed()
	if s.is_empty():
		return
	var x := panel.position.x + 24.0
	var top := panel.position.y + 60.0
	draw_string(font, Vector2(x, top), "RAISED BED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8a8f84"))

	# The two labels beside the typed cells, in the place PACK puts the body
	# slot names, so the shape of the screen stays the shape of the screen.
	var y0 := panel.position.y + 76.0
	draw_string(font, Vector2(x - 92.0, y0 + 26.0), "Seed", HORIZONTAL_ALIGNMENT_RIGHT, 86, 11, Color(1, 1, 1, 0.55))
	draw_string(font, Vector2(x - 92.0, y0 + CELL + GAP + 26.0), "Feed", HORIZONTAL_ALIGNMENT_RIGHT, 86, 11,
		Color(1, 1, 1, 0.55))

	# The gauges live in the empty column to the right of the pack grid.
	# Running them across the panel from the left put both bars straight
	# through the pack, which read as a glitch rather than as a meter.
	var gx := x + CELL + 96.0
	var rx := gx + BAG_COLS * (CELL + GAP) + 22.0
	var gw := panel.position.x + panel.size.x - 24.0 - rx
	var gy := y0 + 12.0

	# Water. Amber when it is low and grey when it is out — never red. Running
	# dry costs time and never the crop, and colouring it like damage would be
	# the screen telling a lie about the rules.
	var wf := Farming.water_frac(s)
	var hours := wf * float(Config.FARM.dry_days) * 24.0
	var wcol := Color("#6ad0c4") if wf > 0.25 else (Color("#d9c46a") if wf > 0.0 else Color("#8a7f6a"))
	draw_string(font, Vector2(rx, gy), "WATER", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8a8f84"))
	draw_string(font, Vector2(rx, gy), "%d%%" % roundi(wf * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, gw, 11, wcol)
	draw_rect(Rect2(rx, gy + 6.0, gw, 14.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(rx, gy + 6.0, gw * wf, 14.0), wcol)
	draw_string(font, Vector2(rx, gy + 34.0),
		"dry in %d hours" % roundi(hours) if wf > 0.0 else "DRY — nothing is growing",
		HORIZONTAL_ALIGNMENT_LEFT, gw, 10, wcol)

	# Growth. Empty soil says what it is for rather than showing a bar at zero.
	gy += 56.0
	if not Farming.planted(s):
		draw_string(font, Vector2(rx, gy), "NOTHING PLANTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8a8f84"))
		draw_multiline_string(font, Vector2(rx, gy + 20.0), "Drag a seed into the slot, or right-click one in your pack.",
			HORIZONTAL_ALIGNMENT_LEFT, gw, 10, 3, Color(1, 1, 1, 0.45))
		return
	var crop := Farming.crop_of(s)
	var p := Farming.progress(s)
	var left := maxf(0.0, Farming.grow_time(s) - float(s.grow)) / Config.DAY_LENGTH
	draw_string(font, Vector2(rx, gy), Farming.stage_name(s).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8a8f84"))
	draw_string(font, Vector2(rx, gy), "%d%%" % roundi(p * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, gw, 11, Color("#9fd07a"))
	draw_rect(Rect2(rx, gy + 6.0, gw, 14.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(rx, gy + 6.0, gw * p, 14.0), Color("#9fd07a") if p >= 1.0 else Color("#7a9a52"))
	# The band shown is what this bed will actually give, fertilizer included,
	# so feeding it visibly moves the number you are about to be paid.
	var ym: float = float(Farming.fert_of(s).get("yield_mul", 1.0))
	draw_string(font, Vector2(rx, gy + 34.0), "%d-%d %s" % [
		maxi(1, floori(int(crop.min) * ym)), maxi(1, floori(int(crop.max) * ym)),
		Items.name_of(String(crop.crop))], HORIZONTAL_ALIGNMENT_LEFT, gw, 11, Color("#d5d0c4"))
	draw_string(font, Vector2(rx, gy + 34.0),
		"ready" if p >= 1.0 else ("%.1f days left" % left if wf > 0.0 else "stalled"),
		HORIZONTAL_ALIGNMENT_RIGHT, gw, 11, Color("#9fd07a") if p >= 1.0 else (
			Color("#d5d0c4") if wf > 0.0 else Color("#d9c46a")))

	var f := Farming.fert_of(s)
	if not f.is_empty():
		draw_string(font, Vector2(rx, gy + 60.0), Items.name_of(String(s.fert)).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, gw, 11, Color("#b06ad0"))
		draw_multiline_string(font, Vector2(rx, gy + 78.0), String(f.desc),
			HORIZONTAL_ALIGNMENT_LEFT, gw, 10, 3, Color(1, 1, 1, 0.45))


func _draw_craft(font: Font, panel: Rect2) -> void:
	var b := bench()
	var where := "By hand  ·  everything else is made at a workbench"
	if mode == "bench":
		var st := bench_station()
		where = ("At the " + Crafting.station_name(st)) if not st.is_empty() \
			else ("At Workbench II" if b >= 2 else "At a Workbench")
	draw_string(font, panel.position + Vector2(24, 60), where, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8a8f84"))

	for row in _craft_rows():
		var rect: Rect2 = row.rect
		var name_ := ""
		var cost := {}
		var st := {}
		var verb := "CRAFT"
		if row.has("repair"):
			var at: Dictionary = row.repair
			var cont := Wear.container_for(player, String(at.c))
			# "MEND", not "REPAIR": REPAIR is the build bar's word for a wall,
			# and two different jobs sharing one verb is how a player learns
			# the wrong thing about which tool does what.
			verb = "MEND"
			# The percentage is also what tells two Machetes apart, now that
			# they can be worn differently and each gets its own row.
			name_ = "%s  ·  %d%%" % [Config.WEAPONS[at.id].name, roundi(Wear.frac(cont, int(at.i)) * 100.0)]
			cost = Wear.repair_cost(cont, int(at.i))
			st = Wear.repair_status(sim, player, String(at.c), int(at.i), b)
		elif row.has("upgrade"):
			var up: Dictionary = row.upgrade
			var ucont := Wear.container_for(player, String(up.c))
			var lv := Upgrade.level(ucont, int(up.i))
			verb = "UPGRADE"
			name_ = "%s  ·  level %d → %d" % [Config.WEAPONS[up.id].name, lv, lv + 1]
			cost = Upgrade.cost(ucont, int(up.i))
			st = Upgrade.status(sim, player, String(up.c), int(up.i), b)
		else:
			var r: Dictionary = row.recipe
			name_ = r.name
			cost = r.cost
			st = Crafting.status(sim, player, r, b)
		if rect.has_point(mouse):
			draw_rect(rect, Color("#242a32"))
		draw_string(font, rect.position + Vector2(6, 15), name_, HORIZONTAL_ALIGNMENT_LEFT, 220, 12,
			Color("#ebe6d6") if st.ok else Color("#7a7f76"))
		draw_string(font, rect.position + Vector2(230, 15), Structures.cost_label(cost), HORIZONTAL_ALIGNMENT_LEFT, 260, 11,
			Color("#c9a227") if st.ok else Color("#8a6a5a"))
		if not st.ok:
			draw_string(font, rect.position + Vector2(0, 15), st.reason, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8, 11, Color("#c96a5a"))
		else:
			draw_string(font, rect.position + Vector2(0, 15), verb, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8, 11, Color("#9fd07a"))


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
	var swatch := Rect2(r.position + Vector2(5, 5), r.size - Vector2(10, 19))
	var tex := Items.icon_of(id)
	if tex != null:
		draw_texture_rect(tex, Items.art_rect(tex, swatch), false)
	else:
		draw_rect(swatch, Color(Items.color_of(id)))
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
		var lv := Upgrade.level_in(stack)
		lines.append("%.0f damage  ·  %s" % [float(w.dmg) * Upgrade.dmg_mul(lv), w.kind])
		if lv > 1:
			lines.append("level %d  ·  +%d%% damage, +%d%% uses" % [lv,
				roundi((Upgrade.dmg_mul(lv) - 1.0) * 100.0), roundi((Upgrade.dur_mul(lv) - 1.0) * 100.0)])
		if Wear.recipe_for(id).is_empty():
			lines.append("found, not made  ·  nothing mends or upgrades it")
		# Off the stack itself, so the tooltip describes the weapon under the
		# cursor rather than some other one of the same name.
		if Wear.wears(id):
			if Wear.broken_in(stack):
				lines.append("BROKEN  ·  mend it at the bench that made it")
			else:
				lines.append("condition %d / %d" % [Wear.left_in(stack), Wear.max_in(stack)])
	elif kind == "consumable":
		var c: Dictionary = Config.CONSUMABLES[id]
		if float(c.heal) > 0.0:
			lines.append("heals %d" % roundi(float(c.heal)))
		if Mutation.is_suppressant(id):
			lines.append("−%d Mutation  ·  %s" % [roundi(float(c.mut)), KeyBinds.primary_label("use_suppress")])
			if c.has("effect"):
				lines.append("side effect: %s" % String(Config.EFFECTS[c.effect].name))

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
