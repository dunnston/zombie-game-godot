class_name CraftPage
extends RefCounted
## Crafting (C, by hand) and the bench (E at a workbench or station): one
## three-column screen. A rail of categories on the left, a grid of cards in
## the middle, and the selected thing's detail on the right with the one
## primary action. The build menu is the same layout, so it is learned once.
##
## The rows are the single source of what is shown and what is clickable: a
## row is a recipe to make, a weapon to MEND, or a weapon to UPGRADE, and each
## carries the category the rail files it under. Every refusal on screen is
## the sim's own string (`Crafting.status`, `Wear.repair_status`,
## `Upgrade.status`), never a grey with no reason.

## The owner's categories, in the order the design lists them.
const CATS := ["Weapons", "Tools", "Clothing/Armor", "Ammo", "Medical", "Food", "Consumables", "Materials", "Special", "Misc"]

var _grid: GridContainer = null


## What a recipe makes, as an item id: the weapon, the gear, the item, or the
## first resource of a bill that pays out several.
static func made_id(r: Dictionary) -> String:
	var g: Dictionary = r.give
	for k in ["weapon", "gear", "item"]:
		if g.has(k):
			return String(g[k])
	if g.has("res"):
		for id in g.res:
			return String(id)
	return ""


## Which category a recipe is filed under, from what it makes — derived rather
## than stored, so a new recipe needs no second field kept in step.
static func category_of(r: Dictionary) -> String:
	var id := made_id(r)
	match Items.kind_of(id):
		"weapon":
			return "Weapons"
		"gear":
			var g: Dictionary = Config.GEAR.get(id, {})
			return "Tools" if g.get("light", false) or float(g.get("dr", 0.0)) <= 0.0 else "Clothing/Armor"
		"res":
			return "Ammo" if id in Config.AMMO_IDS else "Materials"
		"consumable":
			var c: Dictionary = Config.CONSUMABLES.get(id, {})
			if c.get("food", false):
				return "Food"
			if c.get("tool", false):
				return "Tools"
			if float(c.get("heal", 0.0)) > 0.0 and not Mutation.is_suppressant(id):
				return "Medical"
			return "Consumables"
	return "Misc"


## Every row this screen could show, before the category, search and filter.
func all_rows(s: InventoryScreen) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# Mending and levelling are a workbench's jobs, or your hands'; a station
	# mends nothing.
	if s.bench_station().is_empty():
		for row in Wear.worn_carried(s.player):
			out.append({"key": "repair:%s:%s:%d" % [row.id, row.c, row.i], "repair": row, "cat": "mend"})
		for row in Upgrade.upgradeable_carried(s.player):
			out.append({"key": "upgrade:%s:%s:%d" % [row.id, row.c, row.i], "upgrade": row, "cat": "upgrade"})
	for r in s.recipes():
		out.append({"key": "recipe:" + String(r.id), "recipe": r, "cat": category_of(r)})
	return out


func status_of(s: InventoryScreen, row: Dictionary) -> Dictionary:
	if row.has("repair"):
		return Wear.repair_status(s.sim, s.player, String(row.repair.c), int(row.repair.i), s.bench())
	if row.has("upgrade"):
		return Upgrade.status(s.sim, s.player, String(row.upgrade.c), int(row.upgrade.i), s.bench())
	return Crafting.status(s.sim, s.player, row.recipe, s.bench())


func name_of(row: Dictionary) -> String:
	if row.has("repair"):
		return Items.name_of(String(row.repair.id))
	if row.has("upgrade"):
		return Items.name_of(String(row.upgrade.id))
	return String(row.recipe.name)


## The rows on the page: the current category's, or — while searching — every
## row whose name matches; then only what can be made now, if F is on.
func visible_rows(s: InventoryScreen) -> Array[Dictionary]:
	var all := all_rows(s)
	_default_cat(s, all)
	var q := s.craft_search.strip_edges().to_lower()
	var out: Array[Dictionary] = []
	for row in all:
		if q.is_empty():
			if String(row.cat) != s.craft_cat:
				continue
		elif not name_of(row).to_lower().contains(q):
			continue
		if s.craft_filter and not status_of(s, row).ok:
			continue
		out.append(row)
	return out


## The category a screen opens on: the mending if there is any — a broken axe
## is why you walked to the bench — else the first that has something in it.
func _default_cat(s: InventoryScreen, all: Array) -> void:
	var cats := {}
	for row in all:
		cats[String(row.cat)] = true
	if cats.has(s.craft_cat):
		return
	# Mending first only when there is mending this bench can actually do;
	# levelling is never where a screen opens, because it is never why you came.
	var can_mend := false
	for row in all:
		if row.has("repair") and status_of(s, row).ok:
			can_mend = true
	var order: Array = (["mend"] if can_mend else []) + CATS + ["mend", "upgrade"]
	for c in order:
		if cats.has(c):
			s.craft_cat = c
			return
	s.craft_cat = "Weapons"


func _have(s: InventoryScreen) -> Callable:
	return func(id: String) -> int: return s.player.total_res(s.sim, id)


func _cost_of(s: InventoryScreen, row: Dictionary) -> Dictionary:
	if row.has("repair"):
		return Wear.repair_cost(Wear.container_for(s.player, String(row.repair.c)), int(row.repair.i))
	if row.has("upgrade"):
		return Upgrade.cost(Wear.container_for(s.player, String(row.upgrade.c)), int(row.upgrade.i))
	return row.recipe.cost


func _selected(s: InventoryScreen, rows: Array) -> Dictionary:
	for row in rows:
		if String(row.key) == s.craft_sel:
			return row
	if not rows.is_empty():
		s.craft_sel = String(rows[0].key)
		return rows[0]
	return {}


## How many a bill can be paid for, from the pack and the stash together.
func max_qty(s: InventoryScreen, cost: Dictionary) -> int:
	var n := 99
	for id: String in cost:
		var need := int(cost[id])
		if need > 0:
			n = mini(n, s.player.total_res(s.sim, id) / need)
	return maxi(0, n)


# ------------------------------------------------------------------ frame --

func build(s: InventoryScreen, col: VBoxContainer) -> void:
	var bench_mode := s.mode == "bench"
	var w: Array = Chrome.weight_block(s.player, 220)
	s.refresher(w[1])
	var bs := s.bench_struct()
	if bench_mode:
		var is_wb := String(bs.get("type", "")) == "workbench"
		var tier := int(bs.get("tier", 1))
		var right: Array = []
		# The upgrade lives here, priced, rather than on E: the key you press
		# to look at a bench must never be the key that spends on it.
		if is_wb and tier < 2:
			var face := Ui.hbox(14, [Ui.label("Upgrade to Workbench II", "Caps13", Ui.ACCENT_HI), Ui.rule(true, 18, Ui.LINE),
				Ui.label(Structures.cost_label(Config.BENCH_UPGRADE_COST), "Mono", Ui.TEXT_DIM)])
			for c in face.get_children():
				(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var up := Ui.face_button("SecondaryOn", Ui.pad(face, 16, 0, 16, 0), func() -> void: s._press_button("upgrade"))
			up.custom_minimum_size.y = 40
			s.reg_button("upgrade", up)
			right.append(up)
		right.append(Ui.keycap("ESC", "Close"))
		var chip: Control = null
		if is_wb:
			var pips := UiPips.new(3)
			pips.set_filled(tier + 1)
			pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			chip = Ui.boxed(Ui.box(Color("#1a2028"), Ui.LINE, 1, 0, 10, 4), Ui.hbox(8, [pips, Ui.label("TIER %d" % tier, "Mono12", Ui.TEXT_BODY)]))
		col.add_child(Chrome.title_bar("Workbench II" if is_wb and tier >= 2 else String(bs.get("def", {}).get("name", "Workbench")),
			chip, right))
	else:
		col.add_child(s.tab_bar([w[0]]))

	var hits := Ui.label("", "Mono12", Ui.TEXT_OFF)
	var field := LineEdit.new()
	field.text = s.craft_search
	field.text_changed.connect(func(t: String) -> void:
		s.craft_search = t
		s.craft_sel = "")
	s._search = field
	var count := Ui.label("", "Mono", Ui.TEXT_DIM)
	var filter_box := Ui.hbox(0)
	s.section(filter_box, func() -> String: return str(s.craft_filter), func(box: Container) -> void:
		box.add_child(Chrome.filter_chip("Can make now", s.craft_filter, "F", func() -> void: s.craft_filter = not s.craft_filter)))
	s.refresher(func() -> void:
		var shown := visible_rows(s).size()
		Ui.set_text(count, "%d / %d recipes" % [shown, Config.RECIPES.size()])
		Ui.set_text(hits, "%d hits" % shown if not s.craft_search.is_empty() else ""))
	var sub: Array
	if bench_mode:
		var st := s.bench_station()
		var note := "Mending and levelling happen at the bench that made it." if st.is_empty() else "A station makes its own work and nothing else."
		sub = [Ui.label("Bench work", "PanelTitle"), Ui.label(note, "Body14", Ui.TEXT_DIM), Ui.spacer(),
			Chrome.search_box(field, hits, 320), filter_box, count]
	else:
		sub = [Ui.label("Crafting", "PanelTitle"), Chrome.bench_chip("At", "By hand", 0), Ui.spacer(),
			Chrome.search_box(field, hits), filter_box, count]
	col.add_child(Chrome.sub_bar(sub))

	var body := Chrome.body()
	col.add_child(Chrome.body_margin(body))
	var rail := Ui.vbox(16)
	s.section(rail, func() -> String: return _rail_sig(s), func(box: Container) -> void: _build_rail(s, box))
	var rs := Ui.scroller(rail)
	rs.custom_minimum_size.x = Ui.RAIL_W
	rs.size_flags_horizontal = Control.SIZE_FILL
	body.add_child(rs)

	var centre := Ui.vbox(14)
	Ui.expand(centre, true, true)
	s.section(centre, func() -> String: return _centre_sig(s), func(box: Container) -> void: _build_centre(s, box))
	body.add_child(centre)

	var detail := Ui.vbox(0)
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var dp := Ui.panel("Pane", detail)
	dp.custom_minimum_size.x = Ui.DETAIL_W
	dp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.section(detail, func() -> String: return _detail_sig(s), func(box: Container) -> void: _build_detail(s, box))
	body.add_child(dp)

	var hints := [["↑↓←→", "Move"], ["TAB", "Next category"], ["ENTER", "Craft" if not bench_mode else "Do it"],
		["SHIFT+ENTER", "Craft 5" if not bench_mode else "×5 / mend all"], ["/", "Search"], ["F", "Can make now"]]
	col.add_child(Chrome.footer(hints, "Walk away and this screen closes itself" if bench_mode else "Threat rises a little with every craft"))


# -------------------------------------------------------------------- rail --

func _rail_sig(s: InventoryScreen) -> String:
	var all := all_rows(s)
	_default_cat(s, all)
	var counts := {}
	for row in all:
		counts[row.cat] = int(counts.get(row.cat, 0)) + 1
	var have := ""
	for id in _on_hand_ids(s):
		have += "%s%d," % [id, s.player.total_res(s.sim, id)]
	return "%s|%s|%s|%s|%d" % [s.craft_cat, str(counts), have, s.craft_search.is_empty(), s.bench()]


func _build_rail(s: InventoryScreen, box: Container) -> void:
	var all := all_rows(s)
	var counts := {}
	for row in all:
		counts[row.cat] = int(counts.get(row.cat, 0)) + 1
	s._rail_ids.clear()
	var searching := not s.craft_search.is_empty()
	var rows: Array = []
	var pick := func(id: String) -> void:
		s.craft_cat = id
		s.craft_sel = ""
		s.craft_search = ""
		if s._search != null:
			s._search.text = ""
	for id in ["mend", "upgrade"]:
		if counts.has(id):
			rows.append(Chrome.rail_row("Mend" if id == "mend" else "Upgrade", str(counts[id]), id == s.craft_cat and not searching,
				pick.bind(id)))
			s._rail_ids.append(id)
	if not rows.is_empty():
		rows.append(Ui.pad(Ui.rule(), 10, 6, 10, 6))
	for c in CATS:
		var n := int(counts.get(c, 0))
		var b := Chrome.rail_row(c, str(n), c == s.craft_cat and not searching, pick.bind(c), n == 0)
		b.disabled = n == 0
		rows.append(b)
		if n > 0:
			s._rail_ids.append(c)
	box.add_child(Chrome.rail_group("At this bench" if s.mode == "bench" else "Categories", rows))

	# The benches: where the rest of the list is made. A station is a
	# separate gate, not a rung of the ladder, so it is its own colour.
	var bench_rows: Array = []
	var tally := {0: 0, 1: 0, 2: 0}
	var stations := {}
	for r in Config.RECIPES:
		var st := String(r.get("station", ""))
		if st.is_empty():
			tally[int(r.bench)] = int(tally.get(int(r.bench), 0)) + 1
		else:
			stations[st] = int(stations.get(st, 0)) + 1
	var here := s.bench()
	var here_st := s.bench_station()
	var names := {0: "By hand", 1: "Workbench", 2: "Workbench II"}
	for t in [0, 1, 2]:
		var reach: bool = (here_st.is_empty() and t <= here) if s.mode == "bench" else t == 0
		bench_rows.append(Chrome.rail_row(String(names[t]) + ("  ·  anywhere" if t == 0 and s.mode == "bench" else ""),
			str(tally[t]), false, Callable(), false, Ui.OK if reach else Ui.SHORT, null, 38))
	for st: String in stations:
		var at := here_st == st
		bench_rows.append(Chrome.rail_row(Crafting.station_name(st), "HERE" if at else str(stations[st]) if s.mode != "bench" else "NOT HERE",
			false, Callable(), false, Ui.MUTATION, Ui.OK if at else Ui.LOCKED, 38))
	for b in bench_rows:
		(b as Button).mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(Chrome.rail_group("Other benches" if s.mode == "bench" else "Bench", bench_rows))
	box.add_child(Ui.spacer())
	var hand: Array = []
	for id in _on_hand_ids(s):
		hand.append([id, s.player.total_res(s.sim, id)])
	box.add_child(Chrome.on_hand(hand))


## The materials worth showing on hand: whatever the selected row costs
## first (coral when you have none), then the most plentiful of the rest.
func _on_hand_ids(s: InventoryScreen) -> Array:
	var out: Array = []
	var sel := _selected(s, visible_rows(s))
	if not sel.is_empty():
		for id in _cost_of(s, sel):
			out.append(id)
	var rest: Array = []
	for id in Config.RES:
		if not out.has(id) and s.player.total_res(s.sim, id) > 0:
			rest.append(id)
	rest.sort_custom(func(a: String, b: String) -> bool: return s.player.total_res(s.sim, a) > s.player.total_res(s.sim, b))
	for id in rest:
		if out.size() >= 8:
			break
		out.append(id)
	return out


# ------------------------------------------------------------------ centre --

func _centre_sig(s: InventoryScreen) -> String:
	var rows := visible_rows(s)
	var sig := "%s|%s|%s|%s|" % [s.craft_cat, s.craft_search, str(s.craft_filter), s.craft_sel]
	for row in rows:
		var st := status_of(s, row)
		sig += "%s:%s:%s:%s," % [row.key, str(st.ok), String(st.reason), str(_cost_of(s, row))]
		if row.has("repair"):
			sig += "%.2f" % Wear.frac(Wear.container_for(s.player, String(row.repair.c)), int(row.repair.i))
		if row.has("upgrade"):
			sig += str(Upgrade.level(Wear.container_for(s.player, String(row.upgrade.c)), int(row.upgrade.i)))
	for id in Config.RES:
		sig += str(s.player.total_res(s.sim, id)) + ","
	return sig


func _build_centre(s: InventoryScreen, box: Container) -> void:
	var rows := visible_rows(s)
	var sel := _selected(s, rows)
	s._nav_keys.clear()
	for row in rows:
		s._nav_keys.append(String(row.key))
	var title := "Results" if not s.craft_search.is_empty() else ("Mend" if s.craft_cat == "mend" else ("Upgrade" if s.craft_cat == "upgrade" else s.craft_cat))
	var ok := 0
	var short := 0
	var locked := 0
	for row in rows:
		var st := status_of(s, row)
		if st.ok:
			ok += 1
		elif String(st.reason) == "Missing materials":
			short += 1
		else:
			locked += 1
	var summary := "%d can be made now  ·  %d short of materials  ·  %d need something else" % [ok, short, locked]
	if s.craft_cat == "mend":
		summary = "A broken weapon does nothing until it is mended."
	elif s.craft_cat == "upgrade":
		summary = "Levels 4 and up are gated on Precision Parts, which only come out of an instance."
	var head := Ui.hbox(12, [Ui.label(title, "SectionHead"), Ui.expand(Ui.label(summary, "Body14", Ui.TEXT_DIM))])
	box.add_child(head)
	if rows.is_empty():
		var why := "Nothing can be made now — turn off the filter (F) to see what is missing." if s.craft_filter \
			else ("No matches." if not s.craft_search.is_empty() else "Nothing here.")
		box.add_child(Ui.panel("Inset", Ui.para(why, "Body14", Ui.TEXT_DIM)))
		return
	var listing: Control
	if s.craft_cat in ["mend", "upgrade"] and s.craft_search.is_empty():
		var list := Ui.vbox(8)
		for row in rows:
			list.add_child(_mend_row(s, row, String(row.key) == String(sel.get("key", ""))) if row.has("repair") \
				else _upgrade_row(s, row, String(row.key) == String(sel.get("key", ""))))
		_grid = null
		s._nav_grid = null
		listing = list
	else:
		var g := GridContainer.new()
		g.columns = 5
		g.add_theme_constant_override("h_separation", Ui.GAP)
		g.add_theme_constant_override("v_separation", Ui.GAP)
		for row in rows:
			g.add_child(_card(s, row, String(row.key) == String(sel.get("key", ""))))
		_grid = g
		s._nav_grid = g
		listing = g
	var sc := Ui.scroller(listing)
	# Five across at the design width, fewer or more as the column changes: the
	# cards stretch to fill it rather than leaving a ragged edge.
	sc.resized.connect(func() -> void:
		if is_instance_valid(listing) and listing is GridContainer:
			(listing as GridContainer).columns = maxi(1, floori((sc.size.x + Ui.GAP) / (184.0 + Ui.GAP))))
	box.add_child(sc)


## One recipe card: the icon tile, the name and class, the bill as chips, and
## a 26px strip that says CAN CRAFT, SHORT n of something, or which bench.
func _card(s: InventoryScreen, row: Dictionary, on: bool) -> Button:
	var r: Dictionary = row.recipe
	var id := made_id(r)
	var st := Crafting.status(s.sim, s.player, r, s.bench())
	var gate := Crafting.bench_reason(s.sim, s.player, r, s.bench())
	var is_locked := not gate.is_empty()
	var short: bool = not st.ok and not is_locked
	var tile := UiSwatch.new(id, 56, true, 32)
	tile.frame_color = Ui.LINE_STRONG if on else (Ui.LINE_SOFT if is_locked or short else Ui.LINE)
	tile.alpha = 0.45 if is_locked or short else 1.0
	var name_l := Ui.label(String(r.name), "ItemName", Ui.TEXT_OFF if is_locked else (Ui.TEXT_DIM if short else Ui.TEXT_HIGH))
	var cls := Ui.label(Ui.kind_line(id), "Small", Ui.TEXT_FAINT if is_locked else Ui.TEXT_DIM)
	var top := Ui.hbox(12, [tile, Ui.expand(Ui.vbox(5, [name_l, cls]))])
	var bill: Control
	if is_locked:
		bill = Ui.label(Structures.cost_label(r.cost), "Mono12", Ui.TEXT_FAINT)
	else:
		bill = Ui.cost_chips(r.cost, _have(s) if short else Callable(), "Mono12", short)
	var text := "Can craft"
	var col := Ui.OK
	var fill := Ui.OK_FILL
	var xp_col := Ui.OK_DIM
	if is_locked:
		col = Ui.LOCKED
		fill = Ui.LOCK_FILL
		xp_col = Ui.TEXT_FAINT
		text = "Workbench II" if int(r.bench) >= 2 and gate.begins_with("Needs Work") else \
			("Workbench" if gate == "Needs a Workbench" else gate.trim_prefix("Needs "))
		if String(r.get("station", "")) != "" and gate.begins_with("Needs a "):
			text = Crafting.station_name(String(r.station))
	elif short:
		col = Ui.SHORT
		fill = Ui.SHORT_FILL
		xp_col = Ui.TEXT_OFF
		text = String(st.reason)
		if text == "Missing materials":
			for m: String in r.cost:
				var have := s.player.total_res(s.sim, m)
				if have < int(r.cost[m]):
					text = "Short %d %s" % [int(r.cost[m]) - have, Items.name_of(m).to_lower()]
					break
	var strip := Ui.boxed(Ui.edge(fill, Ui.LINE_SOFT if (is_locked or short) else Ui.LINE, 0, 1, 0, 0, 12, 0),
		Ui.hbox(8, [Ui.expand(Ui.label(text, "Caps", col)), Ui.label("+%d XP" % int(r.xp), "Mono12", xp_col)]))
	strip.custom_minimum_size.y = 26
	var face := Ui.vbox(0, [Ui.pad(top, 13, 13, 13, 8), Ui.pad(bill, 13, 0, 13, 10), Ui.spacer(), strip])
	var variation := "CardOn" if on else ("CardLocked" if is_locked else ("CardDim" if short else "Card"))
	var key := String(row.key)
	var b := Ui.face_button(variation, face, func() -> void: s.craft_sel = key)
	b.custom_minimum_size = Vector2(170, 174)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.reg_row("recipe:" + String(r.id), b)
	return b


## A MEND row: the weapon, how worn, the bill, and MEND or the reason not.
func _mend_row(s: InventoryScreen, row: Dictionary, on: bool) -> Control:
	var at: Dictionary = row.repair
	var cont := Wear.container_for(s.player, String(at.c))
	var frac := Wear.frac(cont, int(at.i))
	var broken := Wear.is_broken(cont, int(at.i))
	var st := Wear.repair_status(s.sim, s.player, String(at.c), int(at.i), s.bench())
	var col := Ui.wear_color(frac)
	var tile := UiSwatch.new(String(at.id), 52, true, 32)
	tile.frame_color = Ui.LINE_STRONG if on else Ui.LINE
	var info := Ui.vbox(4, [Ui.label(Items.name_of(String(at.id)), "ItemName"),
		Ui.label("%s  ·  %d%%" % ["Broken" if broken else "Worn", roundi(frac * 100.0)], "Small", col)])
	info.custom_minimum_size.x = 230
	var m := UiMeter.new(10, col)
	m.frac = frac
	m.custom_minimum_size.x = 180
	var action := _action_or_reason(s, "repair:" + String(at.id), "Mend", st, row, on)
	var line := Ui.hbox(16, [tile, info, m, Ui.spacer(), Ui.cost_chips(Wear.repair_cost(cont, int(at.i)), _have(s), "Mono14", false, false), action])
	for c in line.get_children():
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var key := String(row.key)
	var b := Ui.face_button("RailRowOn" if on else "Card", Ui.pad(line, 16, 0, 16, 0), func() -> void: s.craft_sel = key)
	b.custom_minimum_size.y = 72
	return b


## An UPGRADE row: the weapon, the level it goes to, six rank pips, the bill,
## and UPGRADE or the reason not — NEEDS PRECISION PARTS is a plan.
func _upgrade_row(s: InventoryScreen, row: Dictionary, on: bool) -> Control:
	var up: Dictionary = row.upgrade
	var cont := Wear.container_for(s.player, String(up.c))
	var lv := Upgrade.level(cont, int(up.i))
	var st := Upgrade.status(s.sim, s.player, String(up.c), int(up.i), s.bench())
	var tile := UiSwatch.new(String(up.id), 44, true, 26)
	tile.alpha = 1.0 if st.ok else 0.5
	var info := Ui.vbox(4, [Ui.label(Items.name_of(String(up.id)), "ItemName", Ui.TEXT_HIGH if st.ok else Ui.TEXT_DIM),
		Ui.label("Level %d → %d" % [lv, lv + 1], "Small", Ui.TEXT_DIM if st.ok else Ui.TEXT_OFF)])
	info.custom_minimum_size.x = 230
	var pips := UiPips.new(int(Config.UPGRADE.max), Vector2(14, 6), Ui.ACCENT_HI if st.ok else Color("#8a6a20"), Ui.LINE if st.ok else Ui.LINE_SOFT, 4)
	pips.set_filled(lv)
	var action := _action_or_reason(s, "upgrade:" + String(up.id), "Upgrade", st, row, on)
	var line := Ui.hbox(16, [tile, info, pips, Ui.spacer(), Ui.cost_chips(Upgrade.cost(cont, int(up.i)), _have(s), "Mono14", false, false), action])
	for c in line.get_children():
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var key := String(row.key)
	var b := Ui.face_button("RailRowOn" if on else ("Card" if st.ok else "CardDim"), Ui.pad(line, 16, 0, 16, 0),
		func() -> void: s.craft_sel = key)
	b.custom_minimum_size.y = 64
	return b


## The row's own button when it can be done, or a coral box with the sim's
## reason when it cannot.
func _action_or_reason(s: InventoryScreen, key: String, verb: String, st: Dictionary, row: Dictionary, on: bool) -> Control:
	if st.ok:
		var b := Ui.button(verb.to_upper(), "PrimarySmall" if on else "SecondarySmall", func() -> void: _do(s, row))
		b.custom_minimum_size = Vector2(120, 40)
		s.reg_row(key, b)
		return b
	var box := Ui.boxed(Ui.box(Ui.SHORT_FILL, Ui.SHORT_EDGE, 1, 0, 12, 0), Ui.label(String(st.reason), "Caps", Ui.SHORT))
	(box.get_child(0) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(200, 36)
	(box.get_child(0) as Label).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.reg_row(key, box)
	return box


# ------------------------------------------------------------------ detail --

func _detail_sig(s: InventoryScreen) -> String:
	var sel := _selected(s, visible_rows(s))
	if sel.is_empty():
		return "none"
	var st := status_of(s, sel)
	var have := ""
	for id in _cost_of(s, sel):
		have += str(s.player.total_res(s.sim, id)) + ","
	return "%s|%s|%s|%d|%s|%s" % [sel.key, str(st.ok), String(st.reason), s.craft_qty, have, str(_cost_of(s, sel))]


func _build_detail(s: InventoryScreen, box: Container) -> void:
	var sel := _selected(s, visible_rows(s))
	if sel.is_empty():
		box.add_child(Ui.pad(Ui.para("Choose something on the left.", "Body14", Ui.TEXT_DIM), 20))
		return
	var id := ""
	var title := name_of(sel)
	var cls := ""
	var st := status_of(s, sel)
	var badges: Array = []
	var desc := ""
	var stats: Array = []
	if sel.has("recipe"):
		id = made_id(sel.recipe)
		cls = Ui.kind_line(id)
		badges.append(["Can craft" if st.ok else String(st.reason), Ui.OK if st.ok else Ui.SHORT])
		var b := int(sel.recipe.bench)
		if String(sel.recipe.get("station", "")) != "":
			badges.append(["Chemistry" if String(sel.recipe.station) == "chem" else Crafting.station_name(String(sel.recipe.station)), Ui.MUTATION])
		elif b > 0:
			badges.append(["Bench %d" % b, Ui.ACCENT_HI])
		stats = _stats_for(id)
	else:
		var r: Dictionary = sel.repair if sel.has("repair") else sel.upgrade
		id = String(r.id)
		cls = Ui.kind_line(id)
		var cont := Wear.container_for(s.player, String(r.c))
		var lv := Upgrade.level(cont, int(r.i))
		if sel.has("repair"):
			var broken := Wear.is_broken(cont, int(r.i))
			badges.append(["Broken" if broken else "Worn", Ui.SHORT if broken else Ui.WORN])
			desc = "A broken tool does nothing at all — it will not harvest, cut or fight. Mending returns it to full condition for a fraction of what it cost to make."
		else:
			desc = "Every level is more damage and more uses. Levels 4 to 6 cost Precision Parts, which only come out of the School."
			var w: Dictionary = Config.WEAPONS.get(id, {})
			stats = [["Damage", "%.0f → %.0f" % [float(w.get("dmg", 0)) * Upgrade.dmg_mul(lv), float(w.get("dmg", 0)) * Upgrade.dmg_mul(lv + 1)]],
				["Uses", "%d → %d" % [roundi(Wear.max_of(id) * Upgrade.dur_mul(lv)), roundi(Wear.max_of(id) * Upgrade.dur_mul(lv + 1))]],
				["Level", "%d → %d" % [lv, lv + 1]]]
		badges.append(["L%d" % lv, Ui.TEXT_BODY, true])

	var art := UiSwatch.new(id, 96, true, 60)
	art.frame_color = Ui.LINE_STRONG
	var bx := Ui.hbox(6)
	for b in badges:
		bx.add_child(Ui.badge(String(b[0]), b[1], bool(b[2]) if b.size() > 2 else false))
	box.add_child(Ui.panel("PanelHeadWide", Ui.hbox(16, [art, Ui.expand(Ui.vbox(7, [Ui.label(title, "PanelTitle"), Ui.label(cls, "Caps"), bx]))])))

	var mid := Ui.vbox(0)
	if not desc.is_empty():
		mid.add_child(_section_pad(Ui.para(desc, "Body")))
	if sel.has("repair"):
		var r: Dictionary = sel.repair
		var cont := Wear.container_for(s.player, String(r.c))
		var frac := Wear.frac(cont, int(r.i))
		var m := UiMeter.new(14, Ui.wear_color(frac))
		m.frac = frac
		mid.add_child(_section_pad(Ui.vbox(8, [Ui.label("Condition", "Caps"), m,
			Ui.hbox(8, [Ui.expand(Ui.label("Now", "Small")), Ui.label("%d%%%s" % [roundi(frac * 100.0), "  ·  broken" if Wear.is_broken(cont, int(r.i)) else ""], "Mono", Ui.wear_color(frac))]),
			Ui.hbox(8, [Ui.expand(Ui.label("After mending", "Small")), Ui.label("100%", "Mono", Ui.OK)])])))
	if not stats.is_empty():
		var g := GridContainer.new()
		g.columns = 3
		g.add_theme_constant_override("h_separation", 12)
		g.add_theme_constant_override("v_separation", 12)
		for sc in stats:
			var cell := Ui.stat_cell(String(sc[0]), String(sc[1]), sc[2] if sc.size() > 2 else null)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			g.add_child(cell)
		mid.add_child(_section_pad(Ui.vbox(12, [Ui.label("Stats", "Caps"), g])))

	# The bill as have/need lines, for the quantity chosen.
	var cost := _cost_of(s, sel)
	var qty := s.craft_qty if sel.has("recipe") else 1
	var lines := Ui.vbox(8)
	var short := 0
	for m: String in cost:
		var have := s.player.total_res(s.sim, m)
		var need := int(cost[m]) * qty
		if have < need:
			short += 1
		lines.add_child(Ui.req_line(m, have, need))
	var mat_head := Ui.hbox(8, [Ui.expand(Ui.label("Materials", "Caps")),
		Ui.label("ALL PRESENT" if short == 0 else "%d SHORT" % short, "Mono12", Ui.OK_DIM if short == 0 else Ui.SHORT)])
	var mat := Ui.vbox(12, [mat_head, lines])
	for line in _requirement_lines(s, sel):
		mat.add_child(line)
	mid.add_child(_section_pad(mat))
	var ms := Ui.scroller(mid)
	box.add_child(ms)

	box.add_child(_action_block(s, sel, st))


func _section_pad(c: Control) -> PanelContainer:
	return Ui.boxed(Ui.edge(Color(0, 0, 0, 0), Ui.LINE_SOFT, 0, 0, 0, 1, 20, 16), c)


## The stat cells for what a recipe makes: a weapon's six numbers, a piece of
## gear's two, a consumable's effect.
func _stats_for(id: String) -> Array:
	match Items.kind_of(id):
		"weapon":
			var w: Dictionary = Config.WEAPONS[id]
			return [["Damage", "%.0f" % float(w.dmg)], ["Swing", "%.2fs" % float(w.get("cd", 0.0))],
				["Reach", "%d" % int(w.get("range", 0))],
				["Bleed", ("%s/s" % str(w.bleed)) if float(w.get("bleed", 0.0)) > 0.0 else "—", Ui.DANGER if float(w.get("bleed", 0.0)) > 0.0 else null],
				["Crit", "%d%%" % roundi(float(w.get("crit", 0.0)) * 100.0)],
				["Durability", str(Wear.max_of(id)) if Wear.wears(id) else "—"]]
		"gear":
			var g: Dictionary = Config.GEAR[id]
			return [["Slot", String(Config.GEAR_SLOT_NAMES.get(String(g.slot), g.slot))],
				["Reduces", "%d%%" % roundi(float(g.get("dr", 0.0)) * 100.0)] if float(g.get("dr", 0.0)) > 0.0 else ["Light", "%ds" % roundi(float(g.get("burn", 0.0)))],
				["Weight", "%.1f" % Items.weight_of(id)]]
		"consumable":
			var c: Dictionary = Config.CONSUMABLES[id]
			var out: Array = []
			if float(c.get("heal", 0.0)) > 0.0:
				out.append(["Heals", "%d" % roundi(float(c.heal))])
			if float(c.get("mut", 0.0)) > 0.0:
				out.append(["Mutation", "−%d" % roundi(float(c.mut)), Ui.MUTATION])
			if c.has("effect"):
				out.append(["Effect", String(Config.EFFECTS[c.effect].name)])
			out.append(["Weight", "%.1f" % Items.weight_of(id)])
			return out
	return [["Stack", str(Items.stack_limit(id))], ["Weight", "%.1f" % Items.weight_of(id)]]


## The bench and tool lines under a bill.
func _requirement_lines(s: InventoryScreen, sel: Dictionary) -> Array:
	var out: Array = []
	if sel.has("recipe"):
		var r: Dictionary = sel.recipe
		var station := String(r.get("station", ""))
		if not station.is_empty():
			var here := not s.sim.structs.near_station(s.player.pos, station).is_empty()
			out.append(Ui.requires_line(Crafting.station_name(station), "STANDING AT ONE" if here else "NOT HERE", here))
		elif int(r.bench) > 0:
			var ok := s.bench() >= int(r.bench)
			out.append(Ui.requires_line("Workbench II" if int(r.bench) >= 2 else "Workbench", "STANDING AT ONE" if ok else "GO TO ONE", ok))
		else:
			out.append(Ui.requires_line("Nothing — made by hand", "ANYWHERE", true))
		if r.has("tool"):
			var has := Crafting.has_tool(s.player, String(r.tool))
			out.append(Ui.requires_line("%s in your pack" % Config.WEAPONS[r.tool].name, "CARRIED" if has else "NOT CARRIED", has))
	elif sel.has("repair") or sel.has("upgrade"):
		var st := status_of(s, sel)
		var why := String(st.reason)
		var gated := why.begins_with("Needs a Workbench") or why.begins_with("Needs Workbench") or why.begins_with("Needs a ")
		out.append(Ui.requires_line("the bench that made it", ("TIER %d IS ENOUGH" % maxi(1, s.bench())) if not gated else why.to_upper(),
			not gated, "Mended at" if sel.has("repair") else "Levelled at"))
	return out


## The foot of the detail panel: the quantity stepper and the one primary
## button, disabled with the sim's reason beside it when it cannot be done.
func _action_block(s: InventoryScreen, sel: Dictionary, st: Dictionary) -> PanelContainer:
	var verb := "Craft"
	if sel.has("repair"):
		verb = "Mend"
	elif sel.has("upgrade"):
		verb = "Upgrade"
	var col := Ui.vbox(12)
	var face := Ui.hbox(12, [Ui.label(verb.to_upper(), "MenuItem", Ui.INK if st.ok else Ui.TEXT_OFF)])
	if st.ok:
		face.add_child(Ui.label("ENTER", "Mono", Color(Ui.INK, 0.7)))
	else:
		face.add_child(Ui.label(String(st.reason), "Caps", Ui.SHORT))
	face.alignment = BoxContainer.ALIGNMENT_CENTER
	for c in face.get_children():
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var primary := Ui.face_button("Primary", face, func() -> void: s._press_button("craft"))
	primary.custom_minimum_size.y = 56
	primary.disabled = not st.ok
	Ui.expand(primary)
	s.reg_button("craft", primary)
	var row := Ui.hbox(12)
	var cost := _cost_of(s, sel)
	var most := max_qty(s, cost)
	if sel.has("recipe"):
		s.craft_qty = clampi(s.craft_qty, 1, maxi(1, most))
		var minus := Ui.button("−", "Secondary", func() -> void: s.craft_qty = maxi(1, s.craft_qty - 1))
		var plus := Ui.button("+", "Secondary", func() -> void: s.craft_qty = mini(maxi(1, most), s.craft_qty + 1))
		for b in [minus, plus]:
			(b as Button).custom_minimum_size = Vector2(44, 56)
		var q := Ui.label(str(s.craft_qty), "Mono22")
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.custom_minimum_size.x = 56
		q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(Ui.boxed(Ui.box(Ui.RAISED, Ui.LINE, 1, 2), Ui.hbox(0, [minus, q, plus])))
	row.add_child(primary)
	col.add_child(row)
	var note := "Instant  ·  materials are the whole cost"
	var right := ""
	if sel.has("recipe"):
		right = "+%d XP  ·  %d max" % [int(sel.recipe.xp) * s.craft_qty, most]
	elif sel.has("repair"):
		note = "Instant  ·  condition is the whole cost"
		right = "MEND ALL  ·  SHIFT+ENTER"
	col.add_child(Ui.hbox(8, [Ui.expand(Ui.label(note, "Small")), Ui.label(right, "Mono", Ui.TEXT_BODY)]))
	return Ui.boxed(Ui.edge(Ui.BASE, Ui.LINE, 0, 1, 0, 0, 20, 20), col)


# ------------------------------------------------------------------- acting --

func _do(s: InventoryScreen, row: Dictionary, times := 1) -> void:
	if row.has("repair"):
		Actions.repair_weapon(s.sim, s.player, String(row.repair.c), int(row.repair.i), s.bench())
	elif row.has("upgrade"):
		Actions.upgrade_weapon(s.sim, s.player, String(row.upgrade.c), int(row.upgrade.i), s.bench())
	else:
		# One at a time, asking again before each: the bill, the room and the
		# weight all move as the batch comes out.
		for i in range(times):
			if not Crafting.status(s.sim, s.player, row.recipe, s.bench()).ok and i > 0:
				break
			if not Actions.craft(s.sim, s.player, row.recipe, s.bench()):
				break


func press(s: InventoryScreen, id: String) -> void:
	if id == "craft":
		var sel := _selected(s, visible_rows(s))
		if not sel.is_empty():
			_do(s, sel, s.craft_qty)


func commit(s: InventoryScreen, shift: bool) -> void:
	var sel := _selected(s, visible_rows(s))
	if sel.is_empty():
		return
	if shift and sel.has("repair"):
		# Mend all: every worn thing this bench can mend, cheapest first is
		# not a promise — the order is the order they are carried in.
		for row in all_rows(s):
			if row.has("repair") and status_of(s, row).ok:
				_do(s, row)
		return
	_do(s, sel, 5 if shift and sel.has("recipe") else (s.craft_qty if sel.has("recipe") else 1))


func nav(s: InventoryScreen, dx: int, dy: int) -> void:
	if s._nav_keys.is_empty():
		return
	var cols := 1
	if s._nav_grid != null and is_instance_valid(s._nav_grid):
		cols = s._nav_grid.columns
	var i := s._nav_keys.find(s.craft_sel)
	if i < 0:
		i = 0
	else:
		i = clampi(i + dx + dy * cols, 0, s._nav_keys.size() - 1) if cols > 1 else clampi(i + dy + dx, 0, s._nav_keys.size() - 1)
	s.craft_sel = String(s._nav_keys[i])
	s.craft_qty = 1
