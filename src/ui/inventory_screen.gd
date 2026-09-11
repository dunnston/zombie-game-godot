class_name InventoryScreen
extends UiScreen
## The pack: what you are carrying, what you are wearing, what is on your
## hotbar, what you can make, who you lead, and what is in the chest you are
## standing at. Everything moves by dragging; ctrl+click drops; shift+click
## splits; right-click does the obvious thing. Nothing equips itself.
##
## One Control with modes, because they are one screen. **pack**, **craft**,
## **char** and **crew** are tabs of it. **store**, **bed**, **bench**,
## **door** and **leave** are the same frame opened on one thing in the world,
## and close themselves when you walk away from it.
##
## Built from Control nodes in the shared frame (`Chrome`). A screen is a set
## of *sections*, each rebuilt only when its signature — a string of what it
## shows — changes, and otherwise refreshed in place. Rebuilds happen in
## `refresh()`, never inside a button's own callback, so a button is never
## freed while it is still emitting. Every state change goes through
## `Actions` (invariant 8): on a guest, a click here is a command to the host.

signal navigate(to: String)

## Modes that are one panel opened on one thing, rather than tabs of the pack.
const SINGLE := ["store", "bed", "bench", "door", "leave"]
const PACK_COLS := 10
const STORE_COLS := 8
const SIDE_COLS := 6
const HAUL_COLS := 5

var sim: GameSim
var player: PlayerSim

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
## The tile of the Raised Bed being worked, or (-1, -1).
var bed_tile := Vector2i(-1, -1)
## The tile of the workbench or station being used, or (-1, -1).
var bench_tile := Vector2i(-1, -1)

var drag := {}                   # {from: cell, id, n} while held
var hover := {}                  # the cell under the mouse
## The cell the detail panel describes: the last one clicked, or moved to
## with the arrow keys.
var sel_cell := {}
## The little menu a plain click on something usable opens beside its cell —
## EAT, DRINK or USE, and DROP. {cell, id}.
var pop := {}

# Crafting and the bench.
var craft_cat := ""              # "mend", "upgrade" or a category
var craft_sel := ""              # the selected row's key
var craft_search := ""
var craft_filter := false
var craft_qty := 1
# The character sheet.
var char_attr := "str"
var char_perk := -1
# The roster.
var crew_sel := 0
var crew_job := ""

var _frame_sig := ""
var _slots: Array[UiSlot] = []
var _search: LineEdit = null
var _float: Control
var _tooltip: PanelContainer = null
var _tip_sig := ""
var _drag_view: UiSlot
var _pop_layer: Control = null
## The panels a dragged stack can land on. Let go anywhere else and it is
## dropped on the ground — the same gesture as dragging it off the panel.
var _drop_zones: Array[Control] = []
## The ids the rail offers, in order, for Tab to step through.
var _rail_ids: Array = []
## The grid the arrow keys move through, and its column count.
var _nav_keys: Array = []
var _nav_grid: GridContainer = null

var _craft := CraftPage.new()
var _char := CharPage.new()
var _crew := CrewPage.new()


func _init(sim_: GameSim = null) -> void:
	sim = sim_
	if sim_ != null:
		player = sim_.players[0]
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Ui.theme()
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


## The boot of a car, in the same two-panel screen a chest uses.
func open_boot(car_id: int) -> void:
	store_car = car_id
	store_tile = Vector2i(-1, -1)
	mode = "store"
	visible = true


## A Raised Bed that is not ready. A ripe one never gets this far: the key
## harvests it where you stand.
func open_bed(tile: Vector2i) -> void:
	bed_tile = tile
	store_tile = Vector2i(-1, -1)
	store_car = 0
	mode = "bed"
	visible = true


## A workbench or a Chemistry Station: its work, with the upgrade on a button
## rather than on the key.
func open_bench(tile: Vector2i) -> void:
	bench_tile = tile
	store_tile = Vector2i(-1, -1)
	store_car = 0
	bed_tile = Vector2i(-1, -1)
	pop = {}
	craft_cat = ""
	craft_sel = ""
	mode = "bench"
	visible = true


## An instance's door: the rules, what you are carrying, and ENTER. The pack is
## on screen on purpose — what you bring is the whole of the decision (§6.6).
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


## Switches tab, the way clicking the tab does.
func set_mode(m: String) -> void:
	mode = m
	pop = {}
	_cancel_drag()


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


## The bed being worked, or empty when there is none in reach.
func bed() -> Dictionary:
	return {} if bed_tile.x < 0 else Farming.reachable_bed(sim, player, bed_tile.x, bed_tile.y)


## The container being looked into, or null when there is none in reach.
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
## PR #25). A station is not a rung of the ladder, so it is 0.
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


## Called every frame by the scene: a screen that belongs to a thing closes
## when you walk away from it.
func tick() -> void:
	if not visible:
		return
	var gone := false
	match mode:
		"store": gone = store() == null
		"bed": gone = bed().is_empty()
		"bench": gone = bench_struct().is_empty()
		# A door panel belongs to the door: step away from it, or through it,
		# and the question is no longer being asked.
		"door": gone = sim.instance != null or Instance.feature_near(sim, player, ["instance_door"]).is_empty()
		"leave": gone = sim.instance == null or Instance.feature_near(sim, player, ["leave"]).is_empty()
	if gone:
		visible = false
		_cancel_drag()


# ---------------------------------------------------------------- building --

## What the frame is: the mode and the few facts that change its shape. Any
## change rebuilds everything; everything else is sections.
func _frame_signature() -> String:
	var sig := mode + "|" + KeyBinds.primary_label("inventory")
	match mode:
		"pack":
			sig += "|%d|%d|%s" % [player.bag.size(), player.hotbar.size(), str(sim.instance != null)]
		"store":
			var s := store()
			sig += "|%d|%d|%s" % [s.size() if s != null else 0, store_car, str(store_tile)]
		"bench":
			var b := bench_struct()
			sig += "|%s|%d|%s" % [str(bench_tile), int(b.get("tier", 0)), bench_station()]
		"door":
			sig += "|" + door_kind
	return sig


func refresh() -> void:
	if not visible or sim == null:
		return
	var fs := _frame_signature()
	if fs != _frame_sig:
		_frame_sig = fs
		_build_frame()
	run_sections()
	_update_slots()
	_update_float()


func _build_frame() -> void:
	_sections.clear()
	_refreshers.clear()
	_slots.clear()
	_buttons.clear()
	_named.clear()
	_drop_zones.clear()
	_rail_ids.clear()
	_nav_keys.clear()
	_nav_grid = null
	_search = null
	_tooltip = null
	_tip_sig = ""
	_pop_layer = null
	Ui.clear(self)
	var col := Chrome.root(self)
	match mode:
		"pack": _build_pack(col)
		"craft", "bench": _craft.build(self, col)
		"char": _char.build(self, col)
		"crew": _crew.build(self, col)
		"store": _build_store(col)
		"bed": _build_bed(col)
		"door": _build_door(col)
		"leave": _build_leave(col)
	_float = Control.new()
	_float.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_float)
	_drag_view = UiSlot.new({}, Ui.SLOT_SIZE)
	_drag_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_view.visible = false
	_float.add_child(_drag_view)


## Drops lookups — the cells too — into a section that is about to be rebuilt.
func _forget(box: Node) -> void:
	super(box)
	for i in range(_slots.size() - 1, -1, -1):
		if not is_instance_valid(_slots[i]) or box.is_ancestor_of(_slots[i]):
			_slots.remove_at(i)


## A button that does `id` through `_press_button`, findable by id.
func btn(id: String, text: String, variation := "Secondary") -> Button:
	var b := Ui.button(text, variation, func() -> void: _press_button(id))
	_buttons[id] = b
	return b


## A cell. Its input comes back through `_slot_input`.
func slot(info: Dictionary, px := Ui.SLOT_SIZE) -> UiSlot:
	var s := UiSlot.new(info, px)
	s.gui_input.connect(func(ev: InputEvent) -> void: _slot_input(s, ev))
	s.mouse_entered.connect(func() -> void: hover = s.info)
	s.mouse_exited.connect(func() -> void:
		if hover == s.info:
			hover = {})
	_slots.append(s)
	return s


## A grid of cells over one container kind.
func grid(kind: String, n: int, cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", Ui.SLOT_GAP)
	g.add_theme_constant_override("v_separation", Ui.SLOT_GAP)
	for i in range(n):
		g.add_child(slot({"kind": kind, "slot": "", "index": i}))
	return g


func drop_zone(c: Control) -> Control:
	_drop_zones.append(c)
	return c


func close_key() -> String:
	match mode:
		"pack": return KeyBinds.primary_label("inventory")
		"craft": return KeyBinds.primary_label("crafting")
		"char": return KeyBinds.primary_label("character")
	return "ESC"


func tab_bar(right: Array) -> PanelContainer:
	var items := right.duplicate()
	items.append(Ui.keycap(close_key(), "Close"))
	return Chrome.tab_bar(mode, Chrome.TABS, items, func(id: String) -> void: navigate.emit(id))


# ------------------------------------------------------------------ pack --

func _build_pack(col: VBoxContainer) -> void:
	var w: Array = Chrome.weight_block(player)
	refresher(w[1])
	col.add_child(tab_bar([w[0]]))
	var body := Chrome.body()
	col.add_child(Chrome.body_margin(body))

	# The body: what you wear, what you carry, and what the selected thing is.
	var armour := Ui.label("", "Mono12", Ui.OK)
	refresher(func() -> void:
		var dr := player.armor_dr
		Ui.set_text(armour, "ARMOUR %d%%" % roundi(dr * 100.0))
		Ui.set_color(armour, Ui.OK if dr > 0.0 else Ui.TEXT_DIM))
	var worn := Ui.vbox(8)
	for i in range(Config.GEAR_SLOTS.size()):
		var gs: String = Config.GEAR_SLOTS[i]
		var cap := Ui.label(String(Config.GEAR_SLOT_NAMES[gs]), "Row14", Color(1, 1, 1, 0.55))
		cap.custom_minimum_size.x = 76
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var nm := Ui.label("", "Row14", Ui.TEXT_HIGH)
		var sub := Ui.label("", "Mono12")
		var txt := Ui.vbox(2, [nm, sub])
		txt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		worn.add_child(Ui.hbox(12, [cap, slot({"kind": "equip", "slot": gs, "index": -1}), Ui.expand(txt)]))
		refresher(func() -> void:
			var id: String = player.equip.get(gs, "")
			if id.is_empty():
				Ui.set_text(nm, "Empty")
				Ui.set_color(nm, Ui.TEXT_OFF)
				Ui.set_text(sub, "DR —")
				Ui.set_color(sub, Ui.TEXT_FAINT)
				return
			var g: Dictionary = Config.GEAR.get(id, {})
			Ui.set_text(nm, Items.name_of(id))
			Ui.set_color(nm, Ui.TEXT_HIGH)
			if g.get("light", false) or float(g.get("dr", 0.0)) <= 0.0:
				var lit: bool = player.lit and Equipment.equipped_light(player).get("id", "") == id
				Ui.set_text(sub, ("LIT  ·  %ds" % roundi(player.light_fuel)) if lit else "%ds OF LIGHT" % roundi(float(g.get("burn", 0.0))))
				Ui.set_color(sub, Ui.LIGHT if lit else Ui.TEXT_DIM)
			else:
				var s := "DR %d%%" % roundi(float(g.dr) * 100.0)
				if float(g.get("crit", 0.0)) > 0.0:
					s += "  ·  CRIT %d%%" % roundi(float(g.crit) * 100.0)
				Ui.set_text(sub, s)
				Ui.set_color(sub, Ui.TEXT_DIM))
	var best := btn("equip_best", "Equip best")
	best.custom_minimum_size.y = 40
	var worn_panel := drop_zone(Ui.panel("Pane", Ui.vbox(0, [Ui.head("Worn", armour), Ui.pad(worn, 14),
		Ui.pad(best, 14, 0, 14, 14)])))

	var kinds := Ui.vbox(8)
	var kind_rows := {}
	for k in [["res", "Materials"], ["gear", "Weapons & gear"], ["consumable", "Medical & food"]]:
		var v := Ui.label("", "Mono", Ui.TEXT_HIGH)
		kind_rows[k[0]] = v
		kinds.add_child(Ui.hbox(8, [Ui.expand(Ui.label(String(k[1]), "Small", Ui.TEXT_BODY)), v]))
	refresher(func() -> void:
		var w_ := {"res": 0.0, "gear": 0.0, "consumable": 0.0}
		for cont in [player.bag, player.hotbar]:
			for i in range(cont.size()):
				var id: String = cont.id_at(i)
				if id.is_empty():
					continue
				var k := Items.kind_of(id)
				k = "gear" if k == "weapon" else k
				if w_.has(k):
					w_[k] += Items.weight_of(id) * int(cont.at(i).n)
		for k in kind_rows:
			Ui.set_text(kind_rows[k], "%.0f" % w_[k]))
	var left := Ui.vbox(16, [worn_panel, Ui.spacer(), Ui.panel("Inset", Ui.vbox(8, [Ui.label("Carried by kind", "Caps"), kinds]))])
	left.custom_minimum_size.x = 300
	body.add_child(Chrome.rail([left], 300))

	var count := Ui.label("", "Mono", Ui.TEXT_DIM)
	refresher(func() -> void: Ui.set_text(count, "%d / %d SLOTS" % [player.bag.used(), player.bag.size()]))
	var pack_head := Ui.panel("PanelHead", Ui.hbox(12, [Ui.expand(Ui.label("Pack", "SectionHead")), count]))
	var bag := grid("bag", player.bag.size(), PACK_COLS)
	_nav_grid = bag
	var hint := Ui.para("Drag to move  ·  click food to eat  ·  right-click to equip, stow or use  ·  ctrl+click to drop  ·  shift+click to split",
		"Small", Color(1, 1, 1, 0.4))
	var pack_panel := drop_zone(Ui.panel("Pane", Ui.vbox(0, [pack_head, Ui.pad(bag, 16), Ui.pad(hint, 16, 0, 16, 14)])))
	var hot := drop_zone(Ui.panel("Pane", Ui.vbox(0, [Ui.head("Hotbar"), Ui.pad(grid("hotbar", player.hotbar.size(), player.hotbar.size()), 16)])))
	var centre := Ui.vbox(16, [pack_panel, hot])
	# Inside an instance, the haul: what you are trying to carry out, on its own
	# budget, and nowhere else.
	if sim.instance != null:
		var hl := Ui.label("", "Mono12", Color("#d8c98a"))
		refresher(func() -> void:
			Ui.set_text(hl, "%.0f / %.0f  ·  OUT ONLY PAST THE BOSS" % [Instance.haul_load(sim, player), float(Config.INSTANCE.haul_cap)]))
		centre.add_child(drop_zone(Ui.panel("Pane", Ui.vbox(0, [Ui.head("Haul", hl),
			Ui.pad(grid("haul", player.haul.size(), HAUL_COLS * 2), 16)]))))
	body.add_child(Ui.expand(Ui.scroller(centre)))

	var detail := Ui.vbox(16)
	section(detail, _detail_sig, _build_detail)
	var ds := Ui.scroller(detail)
	ds.custom_minimum_size.x = 420
	ds.size_flags_horizontal = Control.SIZE_FILL
	body.add_child(drop_zone(ds))


## What the detail panel describes: the cell under the mouse, or the one last
## clicked, or the hotbar slot in hand.
func _detail_cell() -> Dictionary:
	for c in [hover, sel_cell]:
		if not (c as Dictionary).is_empty() and not _stack_in(c).is_empty():
			return c
	return {"kind": "hotbar", "slot": "", "index": player.slot}


func _detail_sig() -> String:
	var c := _detail_cell()
	var s := _stack_in(c)
	return "%s|%s|%d|%d|%d" % [str(c), String(s.get("id", "")), int(s.get("n", 0)), int(s.get("wear", -1)), int(s.get("lv", 0))]


func _build_detail(box: Container) -> void:
	var c := _detail_cell()
	var s := _stack_in(c)
	if s.is_empty():
		box.add_child(Ui.panel("Inset", Ui.para("Point at something to see what it is.", "Body14", Ui.TEXT_DIM)))
		return
	var id := String(s.id)
	var facts := item_facts(s)
	var art := UiSwatch.new(id, 88, true, 56)
	art.frame_color = Ui.LINE_STRONG
	var badges := Ui.hbox(6)
	for b in facts.badges:
		badges.add_child(Ui.badge(String(b[0]), b[1], bool(b[2]) if b.size() > 2 else false))
	var head := Ui.panel("PanelHeadWide", Ui.hbox(16, [art, Ui.expand(Ui.vbox(6, [Ui.label(Items.name_of(id), "PanelTitle"),
		Ui.label(String(facts.kind), "Caps"), badges]))]))
	var rows := Ui.vbox(10)
	var n := int(s.get("n", 1))
	rows.add_child(_fact_row("Carried", "%d / %d" % [n, Items.stack_limit(id)]))
	rows.add_child(_fact_row("Weight here", "%.1f" % (Items.weight_of(id) * n)))
	for r in facts.rows:
		rows.add_child(_fact_row(String(r[0]), String(r[1]), r[2] if r.size() > 2 else null))
	if not String(facts.note).is_empty():
		rows.add_child(Ui.rule())
		rows.add_child(Ui.para(String(facts.note), "Body14", Ui.TEXT_DIM))
	box.add_child(Ui.panel("Pane", Ui.vbox(0, [head, Ui.pad(rows, 20, 16, 20, 16)])))


func _fact_row(k: String, v: String, c: Variant = null) -> HBoxContainer:
	return Ui.hbox(8, [Ui.expand(Ui.label(k, "Body14")), Ui.label(v, "Mono14", Ui.TEXT_HIGH if c == null else c)])


## Everything worth saying about a stack, for the tooltip and the detail panel
## alike: {kind, rows: [[label, value, colour?]], badges: [[text, colour]], note}.
func item_facts(stack: Dictionary) -> Dictionary:
	var id := String(stack.id)
	var kind := Items.kind_of(id)
	var rows: Array = []
	var badges: Array = []
	var note := ""
	var line := Ui.kind_line(id)
	if kind == "gear":
		var g: Dictionary = Config.GEAR[id]
		if float(g.dr) > 0.0:
			rows.append(["Damage reduction", "%d%%" % roundi(float(g.dr) * 100.0)])
		else:
			rows.append(["Light", "%ds" % roundi(float(g.get("burn", 0.0)))])
		if float(g.get("crit", 0.0)) > 0.0:
			rows.append(["Crit", "+%d%%" % roundi(float(g.crit) * 100.0)])
	elif kind == "weapon":
		var w: Dictionary = Config.WEAPONS[id]
		var lv := Upgrade.level_in(stack)
		rows.append(["Damage", "%.0f" % (float(w.dmg) * Upgrade.dmg_mul(lv))])
		if float(w.get("bleed", 0.0)) > 0.0:
			rows.append(["Bleed", "%s / s" % str(w.bleed), Ui.DANGER])
		if lv > 1:
			badges.append(["L%d" % lv, Ui.WAIT, true])
			rows.append(["Level", "%d  ·  +%d%% damage, +%d%% uses" % [lv, roundi((Upgrade.dmg_mul(lv) - 1.0) * 100.0),
				roundi((Upgrade.dur_mul(lv) - 1.0) * 100.0)]])
		if Wear.wears(id):
			if Wear.broken_in(stack):
				badges.append(["Broken", Ui.SHORT])
				note = "Broken — mend it at the bench that made it."
			else:
				var f := float(Wear.left_in(stack)) / maxf(1.0, float(Wear.max_in(stack)))
				rows.append(["Condition", "%d / %d" % [Wear.left_in(stack), Wear.max_in(stack)], Ui.wear_color(f)])
		if Wear.recipe_for(id).is_empty():
			note = "Found, not made  ·  nothing mends or upgrades it."
	elif kind == "consumable":
		var c: Dictionary = Config.CONSUMABLES[id]
		if float(c.get("heal", 0.0)) > 0.0:
			rows.append(["Heals", "%d" % roundi(float(c.heal))])
		if Mutation.is_suppressant(id):
			rows.append(["Mutation", "−%d  ·  %s" % [roundi(float(c.mut)), KeyBinds.primary_label("use_suppress")], Ui.MUTATION])
		if c.has("effect"):
			rows.append(["Effect", String(Config.EFFECTS[c.effect].name)])
		var verb := use_verb(id)
		if not verb.is_empty():
			badges.append([verb, Ui.OK])
	elif kind == "res":
		if id in Config.AMMO_IDS:
			badges.append(["Ammo", Ui.ACCENT_HI])
	if Config.CROPS.has(id):
		badges.append(["Seed", Ui.OK])
	if Config.FERTILIZER.has(id):
		badges.append(["Fertilizer", Ui.MUTATION])
		note = String(Config.FERTILIZER[id].get("desc", note))
	badges.append(["%.1f each" % Items.weight_of(id), Ui.TEXT_BODY, true])
	return {"kind": line, "rows": rows, "badges": badges, "note": note}


# ----------------------------------------------------------------- store --

func _store_title() -> String:
	if store_car > 0:
		return "Car boot"
	var s := sim.structs.at_tile(store_tile.x, store_tile.y)
	return String(s.get("def", {}).get("name", "Storage"))


## The right-hand panel every single-thing screen shares: your pack and your
## hotbar, so you can move things across without opening anything else.
func _pack_side(title := "Your pack", foot: Control = null) -> PanelContainer:
	var count := Ui.label("", "Mono", Ui.TEXT_DIM)
	refresher(func() -> void: Ui.set_text(count, "%d / %d SLOTS" % [player.bag.used(), player.bag.size()]))
	var col := Ui.vbox(0, [Ui.panel("PanelHead", Ui.hbox(12, [Ui.expand(Ui.label(title, "SectionHead")), count])),
		Ui.pad(grid("bag", player.bag.size(), SIDE_COLS), 16),
		Ui.pad(Ui.vbox(10, [Ui.label("Hotbar", "Caps"), grid("hotbar", player.hotbar.size(), player.hotbar.size())]), 16, 0, 16, 16)])
	col.add_child(Ui.spacer())
	if foot != null:
		var f := Ui.boxed(Ui.edge(Color(0, 0, 0, 0), Ui.LINE_SOFT, 0, 1, 0, 0, 16, 16), foot)
		col.add_child(f)
	var p := drop_zone(Ui.panel("Pane", col))
	p.custom_minimum_size.x = 700
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return p


func _build_store(col: VBoxContainer) -> void:
	var w: Array = Chrome.weight_block(player)
	refresher(w[1])
	var chip: Control = null
	var is_stash := store_car == 0 and sim.stash != null and store() == sim.stash
	if is_stash:
		chip = Ui.boxed(Ui.box(Color("#1a2028"), Ui.LINE, 1, 0, 10, 4), Ui.label("SHARED  ·  CREW FEEDS FROM THIS", "Mono12", Ui.TEXT_BODY))
	col.add_child(Chrome.title_bar(_store_title(), chip, [w[0], Ui.keycap("ESC", "Close")]))
	var body := Chrome.body()
	col.add_child(Chrome.body_margin(body))

	var s := store()
	var count := Ui.label("", "Mono", Ui.TEXT_DIM)
	refresher(func() -> void:
		var st := store()
		if st == null:
			return
		var txt := "%d / %d SLOTS" % [st.used(), st.size()]
		if store_car > 0:
			var v := sim.cars.by_id(store_car)
			if not v.is_empty():
				txt = "BOOT %d / %d  ·  FUEL %d / %d" % [Vehicles.trunk_load(v), int(Config.CAR.trunk_cap),
					roundi(v.fuel), int(Config.CAR.fuel_max)]
		Ui.set_text(count, txt))
	var buttons := Ui.hbox(12, [btn("deposit", "Deposit all materials"), btn("withdraw", "Take supplies")])
	# Refuelling belongs on the boot screen: it is the other thing you stopped
	# the car to do, and it needs somewhere to live.
	if store_car > 0:
		buttons.add_child(btn("refuel", "Refuel"))
	for b in buttons.get_children():
		(b as Control).custom_minimum_size.y = 44
	buttons.add_child(Ui.spacer())
	buttons.add_child(Ui.hint("RMB", "move one across"))
	var store_grid := grid("store", s.size() if s != null else 0, STORE_COLS)
	var left := drop_zone(Ui.panel("Pane", Ui.vbox(0, [
		Ui.panel("PanelHead", Ui.hbox(12, [Ui.expand(Ui.label(_store_title(), "SectionHead")), count])),
		Ui.expand(Ui.scroller(Ui.pad(store_grid, 16)), true, true),
		Ui.boxed(Ui.edge(Color(0, 0, 0, 0), Ui.LINE_SOFT, 0, 1, 0, 0, 16, 16), buttons)])))
	Ui.expand(left, true, true)
	body.add_child(left)

	# The pantry: the crew eats and shoots out of the stash and never out of
	# your pack, which is what makes stocking it a decision.
	var pantry: Control = null
	if sim.stash != null:
		var rl := Ui.label("", "Mono14")
		var al := Ui.label("", "Mono14")
		pantry = Ui.vbox(10, [Ui.hbox(8, [Ui.expand(Ui.label("Rations in the stash", "Body14")), rl]),
			Ui.hbox(8, [Ui.expand(Ui.label("9mm in the stash", "Body14")), al]),
			Ui.para("Your people eat and shoot out of this pile, never out of your pack.", "Small", Color(1, 1, 1, 0.4))])
		refresher(func() -> void:
			var r := sim.crew.rations_held(sim)
			var owed := sim.crew.debt
			Ui.set_text(rl, "%d%s" % [r, "  ·  CREW OWES %d" % ceili(owed) if owed >= 1.0 else ""])
			Ui.set_color(rl, Ui.SHORT if owed >= 1.0 or (r < 3 and not sim.crew.alive().is_empty()) else Ui.OK)
			var a := sim.stash.count("ammoP") if sim.stash != null else 0
			Ui.set_text(al, str(a))
			Ui.set_color(al, Ui.OK if a > 0 else Ui.TEXT_DIM))
	body.add_child(_pack_side("Your pack", pantry))


# ------------------------------------------------------------------- bed --

func _build_bed(col: VBoxContainer) -> void:
	col.add_child(Chrome.title_bar("Raised bed", null, [Ui.keycap("ESC", "Close")]))
	var body := Chrome.body()
	col.add_child(Chrome.body_margin(body))
	var cells := Ui.vbox(8)
	for k in [["seed", "Seed"], ["fert", "Feed"]]:
		var cap := Ui.label(String(k[1]), "Row14", Color(1, 1, 1, 0.55))
		cap.custom_minimum_size.x = 76
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var nm := Ui.label("", "Row14", Ui.TEXT_HIGH)
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var kind := String(k[0])
		cells.add_child(Ui.hbox(12, [cap, slot({"kind": kind, "slot": kind, "index": -1}), Ui.expand(nm)]))
		refresher(func() -> void:
			var st := _stack_in({"kind": kind, "slot": kind, "index": -1})
			Ui.set_text(nm, Items.name_of(String(st.id)) if not st.is_empty() else "Empty")
			Ui.set_color(nm, Ui.TEXT_HIGH if not st.is_empty() else Ui.TEXT_OFF))

	# Water: amber when low and grey when out — never red. Running dry costs
	# time and never the crop, and colouring it like damage would be the screen
	# telling a lie about the rules (pillar 1).
	var wv := Ui.label("", "Mono")
	var wm := UiMeter.new(14)
	var wl := Ui.label("", "Small")
	var gname := Ui.label("", "Caps")
	var gv := Ui.label("", "Mono", Ui.OK)
	var gm := UiMeter.new(14)
	var band := Ui.label("", "Row14")
	var left_l := Ui.label("", "Mono")
	var fert := Ui.label("", "Caps", Ui.MUTATION)
	var fert_d := Ui.para("", "Small", Color(1, 1, 1, 0.45))
	refresher(func() -> void:
		var s := bed()
		if s.is_empty():
			return
		var wf := Farming.water_frac(s)
		var wcol := Color("#6ad0c4") if wf > 0.25 else (Ui.WORN if wf > 0.0 else Color("#8a7f6a"))
		Ui.set_text(wv, "%d%%" % roundi(wf * 100.0))
		Ui.set_color(wv, wcol)
		wm.set_value(wf, wcol)
		Ui.set_text(wl, ("Dry in %d hours" % roundi(wf * float(Config.FARM.dry_days) * 24.0)) if wf > 0.0 else "DRY — nothing is growing")
		Ui.set_color(wl, wcol)
		if not Farming.planted(s):
			Ui.set_text(gname, "Nothing planted")
			Ui.set_text(gv, "")
			gm.set_value(0.0)
			Ui.set_text(band, "Drag a seed into the slot, or right-click one in your pack.")
			Ui.set_text(left_l, "")
		else:
			var crop := Farming.crop_of(s)
			var p := Farming.progress(s)
			Ui.set_text(gname, Farming.stage_name(s))
			Ui.set_text(gv, "%d%%" % roundi(p * 100.0))
			gm.set_value(p, Ui.OK if p >= 1.0 else Color("#7a9a52"))
			# What this bed will actually pay, fertilizer included, so feeding
			# it visibly moves the number you are about to be paid.
			var ym: float = float(Farming.fert_of(s).get("yield_mul", 1.0))
			Ui.set_text(band, "%d–%d %s" % [maxi(1, floori(int(crop.min) * ym)), maxi(1, floori(int(crop.max) * ym)),
				Items.name_of(String(crop.crop))])
			var days := maxf(0.0, Farming.grow_time(s) - float(s.grow)) / Config.DAY_LENGTH
			Ui.set_text(left_l, "READY" if p >= 1.0 else ("%.1f DAYS LEFT" % days if wf > 0.0 else "STALLED"))
			Ui.set_color(left_l, Ui.OK if p >= 1.0 else (Ui.TEXT_BODY if wf > 0.0 else Ui.WORN))
		var f := Farming.fert_of(s)
		fert.visible = not f.is_empty()
		fert_d.visible = not f.is_empty()
		if not f.is_empty():
			Ui.set_text(fert, Items.name_of(String(s.fert)))
			Ui.set_text(fert_d, String(f.desc)))
	var buttons := Ui.hbox(12, [btn("water", "Water")])
	var harvest := btn("harvest", "Harvest", "Primary")
	buttons.add_child(harvest)
	for b in buttons.get_children():
		(b as Control).custom_minimum_size.y = 44
	# HARVEST is only offered when there is something to harvest. A button
	# that is always there and usually refuses teaches nothing.
	refresher(func() -> void: harvest.visible = Farming.ready(bed()))
	var gauges := Ui.vbox(10, [Ui.hbox(8, [Ui.expand(Ui.label("Water", "Caps")), wv]), wm, wl, Ui.fixed(0, 10),
		Ui.hbox(8, [Ui.expand(gname), gv]), gm, Ui.hbox(8, [Ui.expand(band), left_l]), Ui.fixed(0, 6), fert, fert_d])
	var note := Ui.para("Drag a seed or a bag of feed into a slot  ·  right-click does the same  ·  a dry bed stalls, it never dies",
		"Small", Color(1, 1, 1, 0.4))
	var panel := drop_zone(Ui.panel("Pane", Ui.vbox(0, [Ui.head("The bed"),
		Ui.pad(Ui.vbox(20, [cells, gauges, buttons, note]), 20)])))
	panel.custom_minimum_size.x = 560
	body.add_child(Ui.scroller(panel))
	body.add_child(_pack_side())


# ------------------------------------------------------------- the School --

func _build_door(col: VBoxContainer) -> void:
	col.add_child(Chrome.title_bar(Instance.title(door_kind), Ui.badge("Instance", Ui.XP), [Ui.keycap("ESC", "Not yet")]))
	var body := Chrome.body()
	col.add_child(Chrome.body_margin(body))
	var rules := Ui.vbox(14)
	section(rules, func() -> String: return Instance.refusal(sim, player, door_kind), func(box: Container) -> void:
		var why := Instance.refusal(sim, player, door_kind)
		var lines := [
			["What you are carrying is all you will have in there.", Ui.TEXT_HIGH],
			["No building, and no stash.", Color("#d8c98a")],
			["What you find goes in the HAUL — %d units, and it weighs nothing in a fight." % int(Config.INSTANCE.haul_cap), Ui.TEXT_HIGH],
			["Only the boss lets it out. Walk out early, or die, and it keeps everything you found.", Color("#e0a070")],
			["What you brought is yours whatever happens.", Ui.OK],
			["Clear it and the doors are chained until tomorrow.", Ui.TEXT_DIM],
		]
		if not why.is_empty():
			lines = [[why, Ui.SHORT]]
		for l in lines:
			var bar := Ui.rect(l[1], 4, 18)
			var t := Ui.expand(Ui.para(String(l[0]), "Body", l[1]))
			box.add_child(Ui.hbox(12, [bar, t])))
	var enter := btn("enter", "Enter", "Primary")
	enter.custom_minimum_size.y = 56
	refresher(func() -> void: enter.disabled = not Instance.refusal(sim, player, door_kind).is_empty())
	var no := btn("close", "Not yet")
	no.custom_minimum_size.y = 56
	var panel := drop_zone(Ui.panel("Pane", Ui.vbox(0, [Ui.head("The rules in there"), Ui.pad(rules, 20),
		Ui.spacer(), Ui.pad(Ui.hbox(12, [Ui.expand(enter), no]), 20)])))
	panel.custom_minimum_size.x = 560
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	body.add_child(_pack_side("What you are bringing"))


func _build_leave(col: VBoxContainer) -> void:
	col.add_child(Chrome.title_bar("Walk out", null, [Ui.keycap("ESC", "Stay")]))
	var body := Chrome.body()
	col.add_child(Chrome.body_margin(body))
	var lines := Ui.vbox(16)
	section(lines, func() -> String: return _leave_text() + Instance.leave_refusal(sim, player), func(box: Container) -> void:
		var inst := sim.instance
		if inst == null:
			return
		box.add_child(Ui.para("Walk out now and %s keeps everything you found." % Instance.title(inst.kind), "Row", Color("#e0a070")))
		box.add_child(Ui.para(_leave_text(), "Body", Ui.TEXT_HIGH))
		box.add_child(Ui.para("Put down what is in the gym and all of it comes with you.", "Body", Ui.OK))
		# With company, walking out takes everyone: say who it is waiting for.
		var why := Instance.leave_refusal(sim, player)
		if not why.is_empty():
			box.add_child(Ui.para(why, "Body", Ui.SHORT)))
	var go := btn("leave", "Leave without it", "Primary")
	go.custom_minimum_size.y = 56
	refresher(func() -> void: go.disabled = not Instance.leave_refusal(sim, player).is_empty())
	var stay := btn("close", "Stay")
	stay.custom_minimum_size.y = 56
	var panel := drop_zone(Ui.panel("Pane", Ui.vbox(0, [Ui.head("What walking out costs"), Ui.pad(lines, 20),
		Ui.spacer(), Ui.pad(Ui.hbox(12, [Ui.expand(go), stay]), 20)])))
	panel.custom_minimum_size.x = 560
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	body.add_child(_pack_side())


## What walking out now costs, item by item: everything found in here,
## wherever it is now — the haul or your pack.
func _leave_text() -> String:
	var inst := sim.instance
	if inst == null:
		return ""
	var found: Dictionary = inst.gained.get(player.seat, {})
	var parts: Array[String] = []
	for id: String in found:
		var n := mini(int(found[id]), Instance.held_count(player, id))
		if n > 0:
			parts.append("%d %s" % [n, Items.name_of(id)])
	return "Nothing yet — you have not found anything." if parts.is_empty() else "You would lose: " + ",  ".join(parts)


# ----------------------------------------------------------------- lookups --

## The middle of one cell, for the smoke run to click on.
func cell_centre(kind: String, index: int, slot_name := "") -> Vector2:
	for s in _slots:
		if is_instance_valid(s) and s.info.kind == kind and (s.info.index == index or (kind == "equip" and s.info.slot == slot_name)):
			return s.get_global_rect().get_center()
	return Vector2.ZERO


## The middle of a recipe's card. `reveal` first to be sure it is on screen.
func recipe_centre(id: String) -> Vector2:
	return _centre("recipe:" + id)


## The middle of a weapon's MEND button, for the smoke run's cursor.
func repair_centre(id: String) -> Vector2:
	return _centre("repair:" + id)


## The middle of a weapon's UPGRADE button, likewise.
func upgrade_centre(id: String) -> Vector2:
	return _centre("upgrade:" + id)


## The middle of an attribute or perk row on the character sheet.
func char_row_centre(attr := "", perk := "") -> Vector2:
	return _centre("attr:" + attr) if not attr.is_empty() else _centre("perk:" + perk)


## Brings a recipe onto the page: its category, no search, no filter. The
## smoke run asks for a row by name and has to be able to see it.
func reveal(id: String) -> void:
	for row in _craft.all_rows(self):
		if row.has("recipe") and String(row.recipe.id) == id:
			craft_cat = String(row.cat)
			craft_search = ""
			craft_filter = false
			if _search != null:
				_search.text = ""
			return


## The rows the craft screen is showing: the list the cards are built from.
func _craft_rows() -> Array[Dictionary]:
	return _craft.visible_rows(self)


## Kept for the smoke run's chest leg, which asks where the panel is.
func _cell_at(pos: Vector2) -> Dictionary:
	for s in _slots:
		if is_instance_valid(s) and s.is_visible_in_tree() and s.get_global_rect().has_point(pos):
			return s.info
	return {}


func _stack_in(cell: Dictionary) -> Dictionary:
	if cell.is_empty():
		return {}
	match cell.kind:
		"bag": return player.bag.at(cell.index)
		"hotbar": return player.hotbar.at(cell.index)
		"haul": return player.haul.at(cell.index)
		"store":
			var s := store()
			return s.at(cell.index) if s != null and cell.index < s.size() else {}
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


func _container(kind: String) -> Slots:
	match kind:
		"bag": return player.bag
		"hotbar": return player.hotbar
		"haul": return player.haul
		"store": return store()
	return null


# ----------------------------------------------------------------- per frame --

func _update_slots() -> void:
	for s in _slots:
		if not is_instance_valid(s):
			continue
		var info: Dictionary = s.info
		var st := _stack_in(info)
		var sel: bool = (info.kind == "hotbar" and info.index == player.slot) or (not sel_cell.is_empty() and sel_cell == info)
		var w := -1.0
		var dim := false
		var cont := _container(String(info.kind))
		if cont != null and not st.is_empty() and info.index >= 0 and info.index < cont.size():
			if Wear.is_worn(cont, info.index):
				w = Wear.frac(cont, info.index)
			dim = Wear.is_broken(cont, info.index)
		var num := str(int(info.index) + 1) if info.kind == "hotbar" else ""
		s.show_stack(st, sel, w, num, dim)


func _update_float() -> void:
	var mouse := get_global_mouse_position()
	_drag_view.visible = not drag.is_empty()
	if _drag_view.visible:
		_drag_view.show_stack({"id": drag.id, "n": drag.n})
		_drag_view.position = mouse - _drag_view.size / 2.0
		_drag_view.modulate.a = 0.85
	# The tooltip is drawn last and never over the click menu or a drag.
	var st := _stack_in(hover) if drag.is_empty() and pop.is_empty() else {}
	var sig := "" if st.is_empty() else str(hover) + str(st)
	if sig != _tip_sig:
		_tip_sig = sig
		if _tooltip != null:
			_tooltip.queue_free()
			_tooltip = null
		if not st.is_empty():
			_tooltip = _make_tooltip(st)
			_float.add_child(_tooltip)
	if _tooltip != null:
		var vp := get_viewport_rect().size
		var at := mouse + Vector2(16, 12)
		var sz := _tooltip.get_combined_minimum_size()
		at.x = minf(at.x, vp.x - sz.x - 8.0)
		at.y = minf(at.y, vp.y - sz.y - 8.0)
		_tooltip.position = at
		_tooltip.size = sz


## Max width 320: title and weight, the kind in caps, a rule, the stat rows,
## and the flavour last.
func _make_tooltip(st: Dictionary) -> PanelContainer:
	var id := String(st.id)
	var f := item_facts(st)
	var col := Ui.vbox(4, [Ui.hbox(12, [Ui.expand(Ui.label(Items.name_of(id), "ItemName")),
		Ui.label("%.1f" % Items.weight_of(id), "Mono12")]), Ui.label(String(f.kind), "Caps"), Ui.fixed(0, 4), Ui.rule(), Ui.fixed(0, 4)])
	for r in f.rows:
		col.add_child(Ui.hbox(8, [Ui.expand(Ui.label(String(r[0]), "Small", Ui.TEXT_BODY)),
			Ui.label(String(r[1]), "Mono", r[2] if r.size() > 2 else Ui.TEXT_HIGH)]))
	if not String(f.note).is_empty():
		col.add_child(Ui.fixed(0, 4))
		col.add_child(Ui.para(String(f.note), "Small"))
	var p := Ui.panel("Tooltip", col)
	p.custom_minimum_size.x = 260
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.custom_minimum_size.x = 232
	return p


# ------------------------------------------------------------------- input --

func _slot_input(s: UiSlot, event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	s.accept_event()
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_press(s.info, mb)
		else:
			_release(_cell_at(get_global_mouse_position()))
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_quick_move(s.info)


## Keys the screen answers while it is up. The arrow keys move the selection,
## Enter commits, `/` searches and F filters; Tab and Escape are the scene's,
## because those are polled actions that other screens also answer.
func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	var k := event as InputEventKey
	if _search != null and _search.has_focus():
		if k.physical_keycode == KEY_ENTER or k.physical_keycode == KEY_KP_ENTER:
			_search.release_focus()
			get_viewport().set_input_as_handled()
		return
	match k.physical_keycode:
		KEY_UP: _nav(0, -1)
		KEY_DOWN: _nav(0, 1)
		KEY_LEFT: _nav(-1, 0)
		KEY_RIGHT: _nav(1, 0)
		KEY_ENTER, KEY_KP_ENTER:
			if k.echo:
				return
			_commit(k.shift_pressed)
		KEY_SLASH:
			if _search == null:
				return
			_search.grab_focus()
		KEY_F:
			if k.echo or not (mode == "craft" or mode == "bench"):
				return
			craft_filter = not craft_filter
		_:
			return
	get_viewport().set_input_as_handled()


## Whether the screen is typing: the scene must not read letters as keys.
func typing() -> bool:
	return visible and _search != null and is_instance_valid(_search) and _search.has_focus()


## Tab steps the rail on the screens that have one, rather than closing them.
func takes_tab() -> bool:
	return visible and not _rail_ids.is_empty()


func next_category(back := false) -> void:
	if _rail_ids.is_empty():
		return
	var i := _rail_ids.find(craft_cat)
	i = (i + (-1 if back else 1) + _rail_ids.size()) % _rail_ids.size()
	craft_cat = String(_rail_ids[i])
	craft_sel = ""
	craft_search = ""
	if _search != null:
		_search.text = ""


## One step out, innermost first: the click menu, then the search field, then
## — returning false — the screen itself.
func back() -> bool:
	if not pop.is_empty():
		_close_pop()
		return true
	if typing():
		_search.release_focus()
		return true
	return false


func _nav(dx: int, dy: int) -> void:
	match mode:
		"craft", "bench": _craft.nav(self, dx, dy)
		"char": _char.nav(self, dx, dy)
		"crew": _crew.nav(self, dx, dy)
		"pack":
			var n := player.bag.size()
			var i: int = int(sel_cell.index) if sel_cell.get("kind", "") == "bag" else -1
			i = clampi(i + dx + dy * PACK_COLS, 0, n - 1) if i >= 0 else 0
			sel_cell = {"kind": "bag", "slot": "", "index": i}


func _commit(shift: bool) -> void:
	match mode:
		"craft", "bench": _craft.commit(self, shift)
		"char": _char.commit(self, shift)
		"crew": _crew.commit(self)
		"pack":
			if not sel_cell.is_empty():
				_quick_move(sel_cell)
		"door": _press_button("enter")


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
			if Actions.enter_instance(sim, player, door_kind):
				visible = false
		"leave":
			Actions.leave_instance(sim, player)
			visible = false
		"close":
			visible = false
		_:
			if mode == "craft" or mode == "bench":
				_craft.press(self, id)
			elif mode == "char":
				_char.press(self, id)
			elif mode == "crew":
				_crew.press(self, id)


func _press(cell: Dictionary, mb: InputEventMouseButton) -> void:
	if cell.is_empty():
		return
	sel_cell = cell
	# What is in the ground stays in the ground. Nothing is dragged, dropped or
	# split out of a bed's two slots: the seed comes back at harvest and the
	# fertilizer is spent on the crop.
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
		# Let go off every panel: that is a drop, the same gesture as dragging
		# something off the screen.
		var at := get_global_mouse_position()
		for z in _drop_zones:
			if is_instance_valid(z) and z.is_visible_in_tree() and z.get_global_rect().has_point(at):
				return
		if from.kind == "equip":
			Actions.drop_equipped(sim, player, from.slot)
		else:
			Actions.drop_stack(sim, player, from.kind, from.index, true, store_tile, store_car)
		return
	if cell.kind == from.kind and cell.index == from.index and cell.slot == from.slot:
		# Pressed and let go on the same cell: a click, not a drag. On something
		# you can eat or use, that opens the menu that says so.
		_open_pop(cell)
		return
	# A bed's slots are typed: a Machete at the seed cell is refused with a
	# reason rather than silently doing nothing.
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
## go. Both through `Actions`, so the range and cost checks are the host's.
func _put_in_bed(slot_kind: String, id: String) -> void:
	if bed().is_empty():
		return
	if not Farming.accepts(slot_kind, id):
		sim.notify("%s is not %s" % [Items.name_of(id), "a seed" if slot_kind == "seed" else "fertilizer"], "#c96a5a")
		return
	if slot_kind == "seed":
		Actions.plant(sim, player, bed_tile, id)
	else:
		Actions.fertilize(sim, player, bed_tile, id)


## Right-click: the obvious thing for what is under the cursor. Gear in the
## pack goes on, gear on the body comes off, food is eaten, and anything else
## moves to the other side of the screen — pack to hotbar, or pack to chest.
func _quick_move(cell: Dictionary) -> void:
	if cell.is_empty():
		return
	var stack := _stack_in(cell)
	if stack.is_empty():
		return
	if cell.kind == "equip":
		Actions.unequip(sim, player, cell.slot)
		return
	# Standing at a bed, the obvious thing to do with a seed is plant it — and
	# with a bag of compost, dig it in.
	if mode == "bed":
		if cell.kind == "seed" or cell.kind == "fert":
			return
		if Config.CROPS.has(stack.id):
			_put_in_bed("seed", String(stack.id))
			return
		if Config.FERTILIZER.has(stack.id):
			_put_in_bed("fert", String(stack.id))
			return
	# Out of the haul, the obvious thing is into the pack, where a find can be
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


## What using `id` is called on the click menu, or "" when it is not something
## you use: EAT, DRINK or USE.
static func use_verb(id: String) -> String:
	if Items.kind_of(id) != "consumable":
		return ""
	var c: Dictionary = Config.CONSUMABLES.get(id, {})
	if c.is_empty() or c.get("tool", false):
		return ""
	return String(c.get("verb", "EAT" if c.get("food", false) else "USE"))


## The click menu beside a pack or hotbar cell holding something usable. It
## owns the next press wherever it lands: on a row it does that row, anywhere
## else it just closes, so dismissing it can never also drag something.
func _open_pop(cell: Dictionary) -> void:
	_close_pop()
	if cell.kind != "bag" and cell.kind != "hotbar":
		return
	var id := String(_stack_in(cell).get("id", ""))
	var verb := use_verb(id)
	if verb.is_empty():
		return
	pop = {"cell": cell, "id": id}
	_pop_layer = Control.new()
	_pop_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pop_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_pop_layer.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close_pop())
	_float.add_child(_pop_layer)
	var box := Ui.vbox(6)
	for r in [["use", verb], ["drop", "Drop"]]:
		var act := String(r[0])
		var b := Ui.button(String(r[1]).to_upper(), "Pop", func() -> void: _pop_do(act))
		b.custom_minimum_size = Vector2(120, 36)
		box.add_child(b)
		_buttons["pop_" + act] = b
	_pop_layer.add_child(box)
	var at := cell_centre(String(cell.kind), int(cell.index))
	box.position = at + Vector2(Ui.SLOT_SIZE / 2.0 + 4, -Ui.SLOT_SIZE / 2.0)
	var vp := get_viewport_rect().size
	box.position.x = minf(box.position.x, vp.x - 128)
	box.position.y = clampf(box.position.y, 0.0, vp.y - 80)


func _close_pop() -> void:
	pop = {}
	if _pop_layer != null and is_instance_valid(_pop_layer):
		_pop_layer.queue_free()
	_pop_layer = null


## Does what the menu row says — if the cell still holds what it was opened
## on — and closes the menu.
func _pop_do(act: String) -> void:
	var cell: Dictionary = pop.get("cell", {})
	var id := String(pop.get("id", ""))
	_close_pop()
	if act.is_empty() or cell.is_empty() or String(_stack_in(cell).get("id", "")) != id:
		return
	if act == "use":
		Actions.use_slot(sim, player, cell.kind, cell.index)
	elif act == "drop":
		Actions.drop_stack(sim, player, cell.kind, cell.index, true, store_tile, store_car)
