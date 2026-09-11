class_name Chrome
extends RefCounted
## The frame every full screen sits in: a 64px top bar, an optional 60px
## sub-bar, a 24px-padded body and a 44px footer of key hints. Built once
## here so the Pack, the bench, the build menu and the map are one screen
## learned once rather than five.
##
## Every piece stretches with the window and nothing in it has a fixed width
## wider than its column, so the frame fits any window the design resolution
## fits — which, with `canvas_items` + `expand`, is every window.

## The screens the top bar can switch between, in the order the design shows
## them. BUILD only appears on the build menu's own bar, as in the mockups.
const TABS := [["pack", "Pack"], ["craft", "Craft"], ["char", "Character"], ["crew", "Crew"], ["map", "Map"]]
const TABS_BUILD := [["pack", "Pack"], ["craft", "Craft"], ["build", "Build"], ["char", "Character"], ["crew", "Crew"], ["map", "Map"]]


## The full-screen root: the design's opaque ground — a gentle vertical fade
## from #0e1116 to #0b0d10, or a flat `bg` where a screen has its own — then a
## column of bar, sub-bar, body and footer. Full screens cover the world, as
## the mockups draw them; only the pause menu is a scrim over it.
static func root(owner: Control, bg: Variant = null) -> VBoxContainer:
	var ground: Control
	if bg == null:
		var t := TextureRect.new()
		var grad := GradientTexture2D.new()
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
		g.colors = PackedColorArray([Color("#0e1116"), Color("#0a0c0f"), Color("#0b0d10")])
		grad.gradient = g
		grad.fill_from = Vector2(0, 0)
		grad.fill_to = Vector2(0, 1)
		t.texture = grad
		t.stretch_mode = TextureRect.STRETCH_SCALE
		ground = t
	else:
		var r := ColorRect.new()
		r.color = bg
		ground = r
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_STOP
	owner.add_child(ground)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner.add_child(col)
	return col


## The tabbed top bar: wordmark, the screen tabs, then whatever readouts the
## screen puts on the right, ending in its close key.
static func tab_bar(active: String, tabs: Array, right: Array, on_tab: Callable) -> PanelContainer:
	var row := Ui.hbox(0)
	var mark := Ui.pad(Ui.label("Deadline", "Wordmark"), 24, 0, 24, 0)
	mark.custom_minimum_size.y = 63
	row.add_child(mark)
	row.add_child(Ui.rule(true, 63.0))
	for t in tabs:
		var id := String(t[0])
		var b := Ui.button(String(t[1]).to_upper(), "TopTabOn" if id == active else "TopTab",
			func() -> void: on_tab.call(id))
		b.custom_minimum_size.y = 63
		b.set_meta("tab", id)
		b.add_to_group("screen_tabs")
		row.add_child(b)
		row.add_child(Ui.rule(true, 63.0))
	row.add_child(Ui.spacer())
	row.add_child(_right(right))
	var bar := Ui.panel("TopBar", row)
	bar.custom_minimum_size.y = 64
	return bar


## The titled top bar for a screen that belongs to one thing in the world —
## a chest, a bench, a bed — which has no tabs: wordmark, a rule, the thing's
## name, an optional context chip, then the right-hand readouts.
static func title_bar(title: String, context: Control, right: Array) -> PanelContainer:
	var row := Ui.hbox(20)
	row.add_child(Ui.label("Deadline", "Wordmark"))
	row.add_child(Ui.rule(true, 32.0))
	row.add_child(Ui.label(title, "SectionHead"))
	if context != null:
		row.add_child(context)
	row.add_child(Ui.spacer())
	for c in right:
		row.add_child(c)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	var bar := Ui.panel("TopBar", Ui.pad(row, 24, 0, 24, 0))
	bar.custom_minimum_size.y = 64
	for c in row.get_children():
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return bar


static func _right(items: Array) -> MarginContainer:
	var r := Ui.hbox(24)
	for c in items:
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(c)
	return Ui.pad(r, 24, 0, 24, 0)


## The 60px strip under the bar: the screen's title, its context, search and
## filters. Taller (76) where it carries a row of stats.
static func sub_bar(items: Array, height := 60) -> PanelContainer:
	var row := Ui.hbox(20)
	for c in items:
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(c)
	var bar := Ui.panel("SubBar", row)
	bar.custom_minimum_size.y = height
	return bar


## The body: 24px in from every edge, children laid out left to right with
## the standard 20px gap. It takes all the height the bars leave.
static func body(sep := Ui.GAP) -> HBoxContainer:
	var row := Ui.hbox(sep)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return row


static func body_margin(content: Control) -> MarginContainer:
	var m := Ui.pad(content, Ui.MARGIN)
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return m


## The footer of key hints: `[[key, text], ...]`, then a note on the right.
static func footer(hints: Array, note := "") -> PanelContainer:
	var row := Ui.hbox(28)
	for h in hints:
		row.add_child(Ui.hint(String(h[0]), String(h[1])))
	row.add_child(Ui.spacer())
	if not note.is_empty():
		row.add_child(Ui.label(note, "Small", Ui.TEXT_OFF))
	for c in row.get_children():
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bar := Ui.panel("Footer", row)
	bar.custom_minimum_size.y = 44
	return bar


## A 272px rail column that scrolls when it has more in it than the window is
## tall, so a long list of categories can never push the footer off screen.
static func rail(children: Array, width := Ui.RAIL_W) -> ScrollContainer:
	var col := Ui.vbox(16, children)
	var s := Ui.scroller(col)
	s.custom_minimum_size.x = width
	s.size_flags_horizontal = Control.SIZE_FILL
	return s


## A panel with a caps heading, holding rail rows.
static func rail_group(title: String, rows: Array, right: Control = null) -> PanelContainer:
	var list := Ui.vbox(2, rows)
	var col := Ui.vbox(0, [Ui.head(title, right), Ui.pad(list, 6)])
	return Ui.panel("Pane", col)


## One rail row: a name on the left, a mono count or status on the right, and
## the selected look when `on`. `dot` puts a small colour square before the
## name, the way the bench group marks which benches you are at.
static func rail_row(text: String, count: String, on: bool, pressed: Callable, dim := false,
		dot: Variant = null, count_color: Variant = null, height := 40) -> Button:
	var name_l := Ui.label(text, "Row" if on else "Row", Ui.TEXT_HIGH if on else (Ui.TEXT_DIM if dim else Ui.TEXT_BODY))
	var left := Ui.hbox(9)
	if dot != null:
		var d := Ui.rect(dot, 8, 8)
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		left.add_child(d)
	left.add_child(name_l)
	var cc: Color = (Ui.ACCENT_HI if on else Ui.TEXT_DIM) if count_color == null else count_color
	var row := Ui.hbox(8, [Ui.expand(left), Ui.label(count, "Mono" if count.is_valid_int() else "Mono12", cc)])
	var b := Ui.face_button("RailRowOn" if on else "RailRow", Ui.pad(row, 12, 0, 12, 0), pressed)
	b.custom_minimum_size.y = height
	if dim:
		b.modulate.a = 0.45
	return b


## The "On hand" block at the foot of a rail: materials in two columns.
static func on_hand(rows: Array) -> PanelContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for r in rows:
		var id := String(r[0])
		var n := int(r[1])
		var cell := Ui.hbox(8, [UiSwatch.new(id, 10), Ui.expand(Ui.label(Items.name_of(id), "Small", Ui.TEXT_BODY)),
			Ui.label(str(n), "Mono", Ui.SHORT if n <= 0 else Ui.TEXT_HIGH)])
		cell.custom_minimum_size.x = 104
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
	return Ui.panel("Inset", Ui.vbox(10, [Ui.label("On hand", "Caps"), grid]))


## The search field: `/` in mono, the text, and a hit count on the right.
static func search_box(field: LineEdit, hits: Label, width := 360) -> PanelContainer:
	field.flat = true
	field.placeholder_text = "search"
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	field.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var row := Ui.hbox(10, [Ui.label("/", "Mono", Ui.TEXT_OFF), field, hits])
	var p := Ui.boxed(Ui.box(Ui.VOID, Ui.LINE, 1, 2, 12, 0), row)
	p.custom_minimum_size = Vector2(width, 36)
	return p


## The "can make now" style filter chip: a 14px tick box, the label and the key.
static func filter_chip(text: String, on: bool, key: String, pressed: Callable) -> Button:
	var tick := Ui.boxed(Ui.box(Ui.ACCENT if on else Color(0, 0, 0, 0), Ui.ACCENT if on else Ui.LINE_STRONG, 1, 0),
		Ui.label("✓" if on else "", "Caps", Ui.INK))
	tick.custom_minimum_size = Vector2(14, 14)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := Ui.hbox(10, [tick, Ui.label(text, "Caps", Ui.TEXT_HIGH if on else Ui.TEXT_BODY), Ui.label(key, "Mono12")])
	var b := Ui.face_button("SecondaryOn" if on else "Secondary", Ui.pad(row, 14, 0, 14, 0), pressed)
	b.custom_minimum_size.y = 36
	return b


## The bench context chip: `AT  Workbench  ■■□  TIER 1`.
static func bench_chip(prefix: String, name: String, tier: int, tiers := 2) -> PanelContainer:
	var row := Ui.hbox(10, [Ui.label(prefix, "Caps"), Ui.label(name, "Row14", Ui.TEXT_HIGH)])
	if tier > 0:
		var pips := UiPips.new(tiers + 1)
		pips.set_filled(tier + 1)
		pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pips)
		row.add_child(Ui.label("TIER %d" % tier, "Mono12", Ui.TEXT_OFF))
	return Ui.panel("Chip", row)


## A weight meter with its caption: WEIGHT and `271 / 300`, amber over 85%
## and coral when overloaded — the budget every capacity check nets off.
static func weight_block(p: PlayerSim, width := 260) -> Array:
	var value := Ui.label("", "Mono12")
	var meter := UiMeter.new(8)
	var top := Ui.hbox(8, [Ui.expand(Ui.label("Weight", "Caps")), value])
	var block := Ui.vbox(5, [top, meter])
	block.custom_minimum_size.x = width
	var refresh := func() -> void:
		var carried := p.carried_weight()
		var f := clampf(carried / maxf(1.0, p.carry_cap), 0.0, 1.0)
		var c := Ui.TEXT_DIM
		if p.overloaded():
			c = Ui.SHORT
		elif f > 0.85:
			c = Ui.ACCENT_HI
		meter.set_value(f, c)
		Ui.set_text(value, "%d / %d" % [roundi(carried), roundi(p.carry_cap)])
		Ui.set_color(value, c if c != Ui.TEXT_DIM else Ui.TEXT_BODY)
	refresh.call()
	return [block, refresh]
