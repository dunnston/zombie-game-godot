class_name BuildBar
extends UiScreen
## Build mode. `B` opens the build menu — the same three columns as crafting,
## so the two screens are learned once: categories, a grid of cards, and the
## selected piece's detail with PLACE. Choosing a piece collapses the menu to
## a slim bar above the hotbar so you can see the street, with the bill, the
## piece's place in its category, and — when it cannot go where you are
## pointing — `Structures.can_place`'s reason. Tab brings the menu back; B
## leaves.
##
## It writes nothing to the world directly. A click sets a pending action
## which `fill_intent` copies into the player's `Intent`, so building goes
## through the same door as movement and fighting (invariant 1) and a guest's
## build command runs identical code.

signal navigate(to: String)

const TOOLS := ["repair", "repair_all", "demolish"]
const TOOL_NAMES := {"repair": "REPAIR", "repair_all": "REPAIR ALL", "demolish": "DEMOLISH"}
const CATS := ["Walls", "Storage", "Defence", "Power", "Living", "Crafting stations"]

var sim: GameSim
var player: PlayerSim
var open := false
## The full menu is up (rather than the slim placement bar).
var menu := false
var selected := 0
var hover_tile := Vector2i.ZERO
var check := {"ok": false, "reason": ""}
var pending := {}
var mouse := Vector2.ZERO
var build_cat := "Walls"
var build_filter := false
var build_search := ""

var _search: LineEdit = null
var _mode_sig := ""
var _bar: Control = null
var _nav_grid: GridContainer = null


func _init(sim_: GameSim = null) -> void:
	sim = sim_
	if sim_ != null:
		player = sim_.players[0]
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Ui.theme()
	visible = false


func cards() -> Array:
	var out: Array = []
	out.append_array(Config.BUILD_ORDER)
	out.append_array(TOOLS)
	return out


func selected_card() -> String:
	var c := cards()
	return c[clampi(selected, 0, c.size() - 1)]


## B: into build mode on the menu, or out of it altogether.
func toggle() -> void:
	open = not open
	menu = open
	# `visible` as well as the flag: a Control keeps what it drew last, and
	# the scene stops refreshing a closed bar.
	visible = open
	pending = {}


## Whether the slim placement bar is up, so a click in the world places.
func placing() -> bool:
	return open and not menu


## Chooses a card. A tool goes straight to the street — there is nothing to
## read about a hammer; a piece shows its detail and waits for PLACE.
func select_card(id: String) -> void:
	var i := cards().find(id)
	if i < 0:
		return
	selected = i
	if TOOLS.has(id):
		menu = false
	else:
		build_cat = category_of(id)


func place_mode() -> void:
	if open:
		menu = false


func show_menu() -> void:
	if open:
		menu = true


## Keeps the selection on the page the menu is showing: a search or the
## filter that hides the selected piece moves the selection to the first one
## still shown, the way crafting does — otherwise PLACE would build something
## that is not on the screen (Codex, PR #37).
func reconcile() -> void:
	var id := selected_card()
	if TOOLS.has(id):
		return
	var list := _shown()
	if not list.is_empty() and not list.has(id):
		selected = cards().find(list[0])


## Whether PLACE, or Enter, would take the selection into the street: a piece
## that is unlocked and on the page. With the filter hiding everything, that
## is nothing — an unaffordable piece is not placeable by being remembered.
func placeable() -> bool:
	var id := selected_card()
	return not card_info(id).locked and _shown().has(id)


## Which rail category a piece is filed under, from what it does — derived,
## so a new piece in `STRUCTURES` needs no second field kept in step.
static func category_of(id: String) -> String:
	var d: Dictionary = Config.STRUCTURES.get(id, {})
	if d.get("wall", false) or d.get("gate", false):
		return "Walls"
	if d.has("store"):
		return "Storage"
	if d.get("trap", false) or float(d.get("dmg", 0.0)) > 0.0 or d.get("post", false):
		return "Defence"
	if d.has("fuel_max") or d.has("light_radius") or d.has("power_radius"):
		return "Power"
	if d.has("station") or id == "workbench":
		return "Crafting stations"
	return "Living"


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
				"reason": Structures.cost_label(Structures.repair_cost(s, player.build_cost_mul)) if Structures.is_damaged(s) else "Already intact"}
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


## REPAIR is the one tool you may hold: sweeping the cursor along a battered
## wall and fixing it as you go is the point of it, and the sweep stops itself
## — a piece just repaired is no longer damaged, so `check.ok` goes false.
func sweeps() -> bool:
	return selected_card() == "repair"


## The scene routes world clicks here while placing. Returns true when the
## click was consumed. A click on the slim bar itself places nothing.
func click(at: Vector2) -> bool:
	if not placing():
		return false
	mouse = at
	if _bar != null and is_instance_valid(_bar) and _bar.get_global_rect().has_point(at):
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


## The wheel, while placing: the next piece in the same category, or the next
## tool — the choice you are making is which wall, not which of twenty.
func cycle(dir: int) -> void:
	var card := selected_card()
	var group: Array = TOOLS if TOOLS.has(card) else _in_cat(category_of(card))
	if group.is_empty():
		return
	var i := group.find(card)
	var n := group.size()
	selected = cards().find(group[((i + dir) % n + n) % n])


func _in_cat(cat: String) -> Array:
	var out: Array = []
	for id in Config.BUILD_ORDER:
		if category_of(id) == cat:
			out.append(id)
	return out


func typing() -> bool:
	return visible and menu and _search != null and is_instance_valid(_search) and _search.has_focus()


func takes_tab() -> bool:
	return open


## Tab: in the menu, the next category; while placing, the menu back.
func tab(back := false) -> void:
	if not menu:
		menu = true
		return
	var cats: Array = []
	for c in CATS:
		if not _in_cat(c).is_empty():
			cats.append(c)
	var i := cats.find(build_cat)
	build_cat = String(cats[(i + (-1 if back else 1) + cats.size()) % cats.size()])
	var first: Array = _in_cat(build_cat)
	if not first.is_empty():
		selected = cards().find(first[0])


func back() -> bool:
	if typing():
		_search.release_focus()
		return true
	return false


func _input(event: InputEvent) -> void:
	if not visible or not menu or not (event is InputEventKey) or not event.pressed:
		return
	var k := event as InputEventKey
	if typing():
		if k.physical_keycode == KEY_ENTER or k.physical_keycode == KEY_KP_ENTER:
			_search.release_focus()
			get_viewport().set_input_as_handled()
		return
	match k.physical_keycode:
		KEY_LEFT: _nav(-1, 0)
		KEY_RIGHT: _nav(1, 0)
		KEY_UP: _nav(0, -1)
		KEY_DOWN: _nav(0, 1)
		KEY_ENTER, KEY_KP_ENTER:
			if not k.echo and placeable():
				place_mode()
		KEY_SLASH:
			if _search != null:
				_search.grab_focus()
		KEY_F:
			if k.echo:
				return
			build_filter = not build_filter
		_:
			return
	get_viewport().set_input_as_handled()


func _nav(dx: int, dy: int) -> void:
	var list := _shown()
	if list.is_empty():
		return
	var cols := _nav_grid.columns if _nav_grid != null and is_instance_valid(_nav_grid) else 5
	var i := list.find(selected_card())
	i = 0 if i < 0 else clampi(i + dx + dy * cols, 0, list.size() - 1)
	selected = cards().find(list[i])


## What one card says: the bill, whether it can be paid, and what it will
## build. Every number here is the one `Structures.place` will act on, or the
## card promises something the click does not do — a player with Engineer
## would see a red "WOOD 16" and then put the wall up for eleven.
func card_info(id: String) -> Dictionary:
	if TOOLS.has(id):
		return {"tool": true, "cost": {}, "afford": true, "locked": false, "hp": 0,
			"label": TOOL_NAMES.get(id, id)}
	var def: Dictionary = Config.STRUCTURES.get(id, {})
	var owner := sim.host()
	return {
		"tool": false,
		"cost": sim.structs.cost_of(id, player),
		"afford": player.can_afford(sim, def.cost, player.build_cost_mul),
		"locked": not sim.structs.is_unlocked(id),
		"hp": roundi(def.hp * (owner.struct_hp_mul if owner != null else 1.0)),
		"label": def.get("name", id),
	}


## The pieces on the page: the category's, or every match while searching,
## then only the affordable ones with F on.
func _shown() -> Array:
	var q := build_search.strip_edges().to_lower()
	var out: Array = []
	for id in Config.BUILD_ORDER:
		var def: Dictionary = Config.STRUCTURES[id]
		if q.is_empty():
			if category_of(id) != build_cat:
				continue
		elif not String(def.name).to_lower().contains(q):
			continue
		if build_filter:
			var info := card_info(id)
			if info.locked or not info.afford:
				continue
		out.append(id)
	return out


func _have() -> Callable:
	return func(m: String) -> int: return player.total_res(sim, m)


## The middle of a card or a button, for the smoke run.
func card_centre(id: String) -> Vector2:
	return _centre("card:" + id)


# ---------------------------------------------------------------- refresh --

func refresh() -> void:
	if not visible or sim == null:
		return
	var sig := "%s|%s" % [str(menu), KeyBinds.primary_label("build")]
	if sig != _mode_sig:
		_mode_sig = sig
		reset_screen()
		_search = null
		_bar = null
		_nav_grid = null
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if menu:
			_build_menu()
		else:
			_build_bar()
	if menu:
		reconcile()
	run_sections()


# ------------------------------------------------------------------- menu --

func _build_menu() -> void:
	var col := Chrome.root(self)
	var key := KeyBinds.primary_label("build")
	var tl := Ui.label("", "Caps13")
	var clock := Ui.label("", "Mono", Ui.TEXT_HIGH)
	var phase := Ui.label("", "Caps", Ui.NIGHT)
	refresher(func() -> void:
		Ui.set_text(tl, sim.threat.label())
		Ui.set_color(tl, Color(sim.threat.color()))
		Ui.set_text(clock, "DAY %d  ·  %s" % [sim.clock.day, sim.clock.clock_string()])
		Ui.set_text(phase, sim.clock.phase_name()))
	var threat := Ui.vbox(3, [Ui.label("Threat", "Caps"), tl])
	var when := Ui.vbox(3, [clock, phase])
	for l in [tl, clock, phase]:
		(l as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(Chrome.tab_bar("build", Chrome.TABS_BUILD, [threat, Ui.rule(true, 32), when, Ui.keycap(key, "Leave")],
		func(id: String) -> void: navigate.emit(id)))

	var base := Ui.label("", "Row14", Ui.TEXT_HIGH)
	var pieces := Ui.label("", "Mono12", Ui.TEXT_OFF)
	refresher(func() -> void:
		var n := 0
		for s in sim.structs.list:
			if not s.destroyed:
				n += 1
		var bc: Dictionary = sim.structs.base_centre()
		var loc := sim.world.location_at_px(bc.pos.x, bc.pos.y) if bc.has_base else {}
		Ui.set_text(base, String(loc.name) if not loc.is_empty() else ("None yet" if not bc.has_base else "The Outskirts"))
		Ui.set_text(pieces, "%d PIECES" % n))
	var chip := Ui.panel("Chip", Ui.hbox(10, [Ui.label("Base", "Caps"), base, pieces]))
	var field := LineEdit.new()
	field.text = build_search
	field.placeholder_text = "search structures"
	field.text_changed.connect(func(t: String) -> void: build_search = t)
	_search = field
	var hits := Ui.label("", "Mono12", Ui.TEXT_OFF)
	var count := Ui.label("", "Mono", Ui.TEXT_DIM)
	refresher(func() -> void: Ui.set_text(count, "%d / %d structures" % [_shown().size(), Config.BUILD_ORDER.size()]))
	var fbox := Ui.hbox(0)
	section(fbox, func() -> String: return str(build_filter), func(box: Container) -> void:
		box.add_child(Chrome.filter_chip("Can build now", build_filter, "F", func() -> void: build_filter = not build_filter)))
	col.add_child(Chrome.sub_bar([Ui.label("Building", "PanelTitle"), chip, Ui.spacer(), Chrome.search_box(field, hits), fbox, count]))

	var body := Chrome.body()
	col.add_child(Chrome.body_margin(body))
	var rail := Ui.vbox(16)
	section(rail, _rail_sig, _build_rail)
	var rs := Ui.scroller(rail)
	rs.custom_minimum_size.x = Ui.RAIL_W
	rs.size_flags_horizontal = Control.SIZE_FILL
	body.add_child(rs)
	var centre := Ui.vbox(14)
	Ui.expand(centre, true, true)
	section(centre, _centre_sig, _build_centre)
	body.add_child(centre)
	var detail := Ui.vbox(0)
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var dp := Ui.panel("Pane", detail)
	dp.custom_minimum_size.x = Ui.DETAIL_W
	section(detail, _detail_sig, _build_detail)
	body.add_child(dp)
	col.add_child(Chrome.footer([["↑↓←→", "Move"], ["TAB", "Next category"], ["ENTER", "Take it into placement"],
		["/", "Search"], ["F", "Can build now"], [key, "Leave build mode"]]))


func _rail_sig() -> String:
	var have := ""
	for id in Config.RES:
		have += str(player.total_res(sim, id)) + ","
	return "%s|%s|%d|%s" % [build_cat, build_search.is_empty(), sim.structs.plan_repair_all(sim, player).repairable, have]


func _build_rail(box: Container) -> void:
	var rows: Array = []
	for c in CATS:
		var n := _in_cat(c).size()
		var cat := String(c)
		var b := Chrome.rail_row(c, str(n), c == build_cat and build_search.is_empty(), func() -> void:
			build_cat = cat
			build_search = ""
			if _search != null:
				_search.text = ""
			var first: Array = _in_cat(cat)
			if not first.is_empty():
				selected = cards().find(first[0]), n == 0)
		b.disabled = n == 0
		rows.append(b)
	box.add_child(Chrome.rail_group("Categories", rows))
	var plan := sim.structs.plan_repair_all(sim, player)
	var tools: Array = [
		Chrome.rail_row("Repair", "HOLD TO SWEEP", false, func() -> void: select_card("repair"), false, null, Ui.TEXT_OFF),
		Chrome.rail_row("Repair all", ("%d PIECES" % plan.repairable) if plan.repairable > 0 else "NOTHING", false,
			func() -> void: select_card("repair_all"), false, null, Ui.OK if plan.repairable > 0 else Ui.TEXT_OFF),
		Chrome.rail_row("Demolish", "SALVAGE", false, func() -> void: select_card("demolish"), false, null, Ui.TEXT_OFF)]
	((tools[2] as Button).get_child(0).get_child(0).get_child(0).get_child(0) as Label).add_theme_color_override("font_color", Ui.SHORT)
	for i in range(TOOLS.size()):
		reg_row("card:" + String(TOOLS[i]), tools[i])
	box.add_child(Chrome.rail_group("Tools", tools))
	box.add_child(Ui.spacer())
	var hand: Array = []
	var sel := selected_card()
	var cost: Dictionary = card_info(sel).cost
	for m in cost:
		hand.append([m, player.total_res(sim, m)])
	var rest: Array = []
	for m in Config.RES:
		if not cost.has(m) and player.total_res(sim, m) > 0:
			rest.append(m)
	rest.sort_custom(func(a: String, b: String) -> bool: return player.total_res(sim, a) > player.total_res(sim, b))
	for m in rest:
		if hand.size() >= 6:
			break
		hand.append([m, player.total_res(sim, m)])
	box.add_child(Chrome.on_hand(hand))


func _centre_sig() -> String:
	var sig := "%s|%s|%s|%d|" % [build_cat, build_search, str(build_filter), selected]
	for id in _shown():
		var info := card_info(id)
		sig += "%s%s%s%s," % [id, str(info.afford), str(info.locked), str(info.cost)]
	for m in Config.RES:
		sig += str(player.total_res(sim, m))
	return sig


func _build_centre(box: Container) -> void:
	var list := _shown()
	var ok := 0
	var short := 0
	var locked := 0
	for id in list:
		var info := card_info(id)
		if info.locked:
			locked += 1
		elif info.afford:
			ok += 1
		else:
			short += 1
	var title := "Results" if not build_search.is_empty() else build_cat
	box.add_child(Ui.hbox(12, [Ui.label(title, "SectionHead"), Ui.expand(Ui.label(
		"%d can be built now  ·  %d short of materials  ·  %d need Workbench II" % [ok, short, locked], "Body14", Ui.TEXT_DIM))]))
	if list.is_empty():
		box.add_child(Ui.panel("Inset", Ui.para("Nothing here.", "Body14", Ui.TEXT_DIM)))
		return
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", Ui.GAP)
	g.add_theme_constant_override("v_separation", Ui.GAP)
	for id in list:
		g.add_child(_card(String(id)))
	_nav_grid = g
	var sc := Ui.scroller(g)
	sc.resized.connect(func() -> void:
		if is_instance_valid(g):
			g.columns = maxi(1, floori((sc.size.x + Ui.GAP) / (184.0 + Ui.GAP))))
	box.add_child(sc)


func _swatch_color(id: String) -> Color:
	return Color(String(StructureView.COLORS.get(id, "#8a8f84")))


func _card(id: String) -> Button:
	var info := card_info(id)
	var def: Dictionary = Config.STRUCTURES[id]
	var on := selected_card() == id
	var locked: bool = info.locked
	var short: bool = not locked and not info.afford
	var tile := UiSwatch.of_color(_swatch_color(id), 56, true, 34)
	tile.frame_color = Ui.LINE_STRONG if on else (Ui.LINE_SOFT if locked else Ui.LINE)
	tile.alpha = 0.45 if locked else 1.0
	var top := Ui.hbox(12, [tile, Ui.expand(Ui.vbox(5, [Ui.label(String(def.name), "ItemName", Ui.TEXT_OFF if locked else Ui.TEXT_HIGH),
		Ui.label(category_of(id).trim_suffix("s") if category_of(id) != "Crafting stations" else "Station", "Small",
			Ui.TEXT_FAINT if locked else Ui.TEXT_DIM)]))])
	var bill: Control
	if locked:
		bill = Ui.label("%s  ·  %d HP" % [Structures.cost_label(info.cost), int(info.hp)], "Mono12", Ui.TEXT_FAINT)
	else:
		var chips := Ui.cost_chips(info.cost, _have() if short else Callable(), "Mono12")
		chips.add_child(Ui.label("·  %d HP" % int(info.hp), "Mono12", Ui.TEXT_DIM))
		bill = chips
	var text := "Can build"
	var col := Ui.OK
	var fill := Ui.OK_FILL
	var tcol := Ui.OK_DIM
	if locked:
		text = "Workbench II"
		col = Ui.LOCKED
		fill = Ui.LOCK_FILL
		tcol = Ui.TEXT_FAINT
	elif short:
		col = Ui.SHORT
		fill = Ui.SHORT_FILL
		tcol = Ui.TEXT_OFF
		for m: String in info.cost:
			var have := player.total_res(sim, m)
			if have < int(info.cost[m]):
				text = "Short %d %s" % [int(info.cost[m]) - have, Items.name_of(m).to_lower()]
				break
	var strip := Ui.boxed(Ui.edge(fill, Ui.LINE_SOFT if (locked or short) else Ui.LINE, 0, 1, 0, 0, 12, 0),
		Ui.hbox(8, [Ui.expand(Ui.label(text, "Caps", col)), Ui.label("THREAT %.1f" % float(def.get("threat", 0.0)), "Mono12", tcol)]))
	strip.custom_minimum_size.y = 26
	var face := Ui.vbox(0, [Ui.pad(top, 13, 13, 13, 8), Ui.pad(bill, 13, 0, 13, 10), Ui.spacer(), strip])
	var cid := id
	var b := Ui.face_button("CardOn" if on else ("CardLocked" if locked else "Card"), face, func() -> void: select_card(cid))
	b.custom_minimum_size = Vector2(170, 174)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A double-click takes it straight into the street.
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.double_click and not card_info(cid).locked:
			select_card(cid)
			place_mode())
	reg_row("card:" + id, b)
	return b


func _detail_sig() -> String:
	var id := selected_card()
	var info := card_info(id)
	var have := ""
	for m in info.cost:
		have += str(player.total_res(sim, m)) + ","
	return "%s|%s|%s|%s|%s" % [id, str(info.afford), str(info.locked), have, str(_shown().has(id))]


func _build_detail(box: Container) -> void:
	if _shown().is_empty():
		box.add_child(Ui.pad(Ui.para("Nothing matches — clear the search or the filter to choose a piece.", "Body14", Ui.TEXT_DIM), 20))
		return
	var id := selected_card()
	if TOOLS.has(id):
		id = String(_in_cat(build_cat)[0]) if not _in_cat(build_cat).is_empty() else String(Config.BUILD_ORDER[0])
	var info := card_info(id)
	var def: Dictionary = Config.STRUCTURES[id]
	var art := UiSwatch.of_color(_swatch_color(id), 96, true, 60)
	art.frame_color = Ui.LINE_STRONG
	var solid := bool(def.get("solid", true))
	var badges := Ui.hbox(6, [Ui.badge("Workbench II" if info.locked else ("Can build" if info.afford else "Missing materials"),
		Ui.LOCKED if info.locked else (Ui.OK if info.afford else Ui.SHORT)), Ui.badge("%d HP" % int(info.hp), Ui.TEXT_BODY, true)])
	box.add_child(Ui.panel("PanelHeadWide", Ui.hbox(16, [art, Ui.expand(Ui.vbox(7, [Ui.label(String(def.name), "PanelTitle"),
		Ui.label("%s  ·  %s  ·  1 tile" % [category_of(id), "solid" if solid else "walk-through"], "Caps"), badges]))])))
	var mid := Ui.vbox(0)
	if def.has("desc"):
		mid.add_child(_pad(Ui.para(String(def.desc), "Body")))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	for st in [["Health", str(int(info.hp)), null], ["Threat", "+%.1f" % float(def.get("threat", 0.0)), Ui.LIGHT],
			["Solid", "Feet only" if solid else "No", null]]:
		var cell := Ui.stat_cell(String(st[0]), String(st[1]), st[2])
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(cell)
	mid.add_child(_pad(Ui.vbox(12, [Ui.label("Stats", "Caps"), g])))
	var lines := Ui.vbox(8)
	var short := 0
	for m: String in info.cost:
		var have := player.total_res(sim, m)
		if have < int(info.cost[m]):
			short += 1
		lines.add_child(Ui.req_line(m, have, int(info.cost[m])))
	var need := Ui.requires_line("No bench — build anywhere", "", true) if int(def.get("tier", 1)) <= 1 \
		else Ui.requires_line("Workbench II", "UPGRADED" if not info.locked else "UPGRADE A WORKBENCH", not info.locked)
	mid.add_child(_pad(Ui.vbox(12, [Ui.hbox(8, [Ui.expand(Ui.label("Materials", "Caps")),
		Ui.label("ALL PRESENT" if short == 0 else "%d SHORT" % short, "Mono12", Ui.OK_DIM if short == 0 else Ui.SHORT)]), lines, need])))
	box.add_child(Ui.scroller(mid))

	var face := Ui.hbox(12, [Ui.label("PLACE", "MenuItem", Ui.INK if not info.locked else Ui.TEXT_OFF),
		Ui.label("ENTER" if not info.locked else "NEEDS WORKBENCH II", "Mono" if not info.locked else "Caps", Color(Ui.INK, 0.7) if not info.locked else Ui.SHORT)])
	face.alignment = BoxContainer.ALIGNMENT_CENTER
	for c in face.get_children():
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sid := id
	var place := Ui.face_button("Primary", face, func() -> void:
		select_card(sid)
		place_mode())
	place.custom_minimum_size.y = 56
	place.disabled = not placeable()
	reg_button("place", place)
	box.add_child(Ui.boxed(Ui.edge(Ui.BASE, Ui.LINE, 0, 1, 0, 0, 20, 20), Ui.vbox(12, [place,
		Ui.label("Choosing a piece collapses this menu so you can see the street.", "Small")])))


func _pad(c: Control) -> PanelContainer:
	return Ui.boxed(Ui.edge(Color(0, 0, 0, 0), Ui.LINE_SOFT, 0, 0, 0, 1, 20, 16), c)


# ------------------------------------------------------------- placement --

## The slim bar: the piece and its place in its category, the bill, whether
## it can go where you are pointing and why not, and the keys.
func _build_bar() -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var row := Ui.hbox(0)
	var bar := Ui.boxed(Ui.box(Color(Ui.BASE, 0.94), Ui.LINE, 1, 3), row)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_top -= 108
	bar.offset_bottom -= 108
	_bar = bar
	var cells := Ui.hbox(0)
	row.add_child(cells)
	section(cells, func() -> String: return "%d|%s" % [selected, str(card_info(selected_card()))], _build_bar_cells)


func _build_bar_cells(box: Container) -> void:
	var id := selected_card()
	var info := card_info(id)
	var tool: bool = info.tool
	var name_ := String(info.label) if tool else String(Config.STRUCTURES[id].name)
	var where := "Tool" if tool else "%s  ·  %d of %d" % [category_of(id), _in_cat(category_of(id)).find(id) + 1, _in_cat(category_of(id)).size()]
	var art: Control = UiSwatch.of_color(_swatch_color(id) if not tool else Ui.LINE_STRONG, 44, true, 28)
	var first := Ui.hbox(14, [art, Ui.vbox(3, [Ui.label(name_, "Name18"), Ui.label(where, "Caps")])])
	box.add_child(_cell(first, 18))
	if not tool:
		var chips := Ui.hbox(16)
		for m: String in info.cost:
			var ok := player.total_res(sim, m) >= int(info.cost[m])
			chips.add_child(Ui.hbox(6, [UiSwatch.new(m, 11), Ui.label(str(int(info.cost[m])), "Mono15", Ui.OK if ok else Ui.SHORT)]))
		chips.add_child(Ui.rule(true, 24))
		chips.add_child(Ui.label("%d HP" % int(info.hp), "Mono15"))
		for c in chips.get_children():
			(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(_cell(chips, 18))
	# Whether it goes here, and why not. Refreshed every frame, because the
	# cursor moves and the answer with it.
	var mark := Ui.label("", "Caps14")
	mark.custom_minimum_size.x = 18
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var head := Ui.label("", "Caps")
	var why := Ui.label("", "Body14")
	why.custom_minimum_size.x = 300
	var status := _cell(Ui.hbox(12, [mark, Ui.vbox(2, [head, why])]), 20)
	status.custom_minimum_size.x = 380
	box.add_child(status)
	refresher(func() -> void:
		var ok: bool = check.ok
		status.add_theme_stylebox_override("panel", Ui.edge(Ui.OK_FILL if ok else Ui.SHORT_FILL, Ui.LINE_SOFT, 0, 0, 1, 0, 20, 0))
		Ui.set_text(mark, "✓" if ok else "✕")
		Ui.set_color(mark, Ui.OK if ok else Ui.SHORT)
		var verb := "Click to place"
		match id:
			"repair": verb = "Click or hold to repair"
			"repair_all": verb = "Click to repair everything in range"
			"demolish": verb = "Click to demolish"
		Ui.set_text(head, verb if ok else ("Nothing to do here" if tool else "Cannot place here"))
		Ui.set_color(head, Ui.OK if ok else Ui.SHORT)
		Ui.set_text(why, String(check.reason) if not String(check.reason).is_empty() else "Within reach of where you stand"))
	var keys := Ui.hbox(18, [Ui.hint("LMB", "Hold to sweep" if id == "repair" else "Place" if not tool else "Use"), Ui.hint("WHEEL", "Change piece"),
		Ui.hint("TAB", "Full menu"), Ui.hint(KeyBinds.primary_label("build"), "Leave")])
	box.add_child(_cell(keys, 20, false))


func _cell(c: Control, pad_x: int, rule := true) -> PanelContainer:
	for x in c.get_children():
		if x is Control:
			(x as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var p := Ui.boxed(Ui.edge(Color(0, 0, 0, 0), Ui.LINE_SOFT, 0, 0, 1 if rule else 0, 0, pad_x, 0), c)
	p.custom_minimum_size.y = 74
	return p
