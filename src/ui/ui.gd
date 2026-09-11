class_name Ui
extends RefCounted
## The look of the game, in one place: every colour, face, size and border the
## screens use, the `Theme` built from them, and the handful of builders every
## screen assembles itself out of. The design is `DEADLINE UI redesign/` (the
## handoff's README is the spec); this file is its tokens.
##
## One source, like `config.gd` is for tunables. The Theme is built from these
## constants at boot rather than kept as a `.tres` beside them, because two
## copies of a colour is how a hover state ends up a shade off on one screen.
##
## Rules the builders enforce so no screen has to remember them:
## - Nothing below 12px. Display and label text is upper case with tracking;
##   body copy never is. Numbers are always mono, so columns line up.
## - Borders grow inward: every state of a component has the same content
##   margins, so hover and selection never move anything.
## - A label keeps its natural width, except one told to `expand`: that one
##   trims with an ellipsis rather than growing its container, which is what
##   keeps a long item name from pushing a column — and with it the screen —
##   past the edge of the window. (Trimming every label made every one that
##   was not expanding collapse to nothing: its minimum width is the ellipsis.)

# ------------------------------------------------------------------ colour --

const VOID := Color("#0b0d10")          # screen dim, meter tracks
const BASE := Color("#101318")          # sub-bars, footers, tooltips
const PANEL := Color("#14161a")         # panel body
const RAISED := Color("#1b1f26")        # headers, cards, inputs
const HOVER := Color("#242a32")         # hover, active tab
const SELECTED := Color("#2b3340")      # selected row or card
const LINE_SOFT := Color("#2a3038")     # dividers, disabled borders
const LINE := Color("#3a4048")          # every normal border
const LINE_STRONG := Color("#5a6470")   # hover border, tooltip edge
const TEXT_HIGH := Color("#ebe6d6")
const TEXT_BODY := Color("#c7c2b4")
const TEXT_DIM := Color("#8a8f84")
const TEXT_OFF := Color("#6a6f68")
const TEXT_FAINT := Color("#565b56")
const ACCENT := Color("#c9a227")        # the action you can take
const ACCENT_HI := Color("#e0c24a")     # hover, focus, selection
const ACCENT_PRESS := Color("#a8861c")
const OK := Color("#9fd07a")            # a condition met
const OK_DIM := Color("#6e9a52")
const SHORT := Color("#c96a5a")         # a condition unmet
const DANGER := Color("#c8423a")        # health, damage
const DOWN := Color("#e05a4a")
const LOCKED := Color("#8a949e")        # gated somewhere else
const XP := Color("#9fd0ff")
const MUTATION := Color("#b06ad0")
const WORN := Color("#d9c46a")
const WAIT := Color("#ffe08a")          # awaiting a key; points to spend
const LIGHT := Color("#e0913a")         # a light burning down
const NIGHT := Color("#8f9ad0")
const TAB := Color("#181b20")
const TAB_HOVER := Color("#1f242b")
const SLOT := Color("#1e222a")
const SLOT_EMPTY := Color("#171a1f")
const INK := Color("#14161a")           # text on an amber fill
const DIM_CARD := Color("#16191e")
const LOCK_CARD := Color("#13151a")
## Over a live game the screen behind a panel is dimmed, not hidden: the world
## is still running and it should look like it.
const SCRIM := Color(0.043, 0.051, 0.063, 0.72)
const HUD_FILL := Color(0.043, 0.051, 0.063, 0.82)

## Tinted fills for the strips and badges that carry a state.
const OK_FILL := Color("#1d2a1a")
const SHORT_FILL := Color("#241a1a")
const SHORT_EDGE := Color("#3a2a2c")
const LOCK_FILL := Color("#191c22")
const ACCENT_FILL := Color("#241f14")

## The six attributes' own colours, which the character sheet keys everything
## on. Not in `Config.ATTRS` because they are the design's, not the game's.
const ATTR_COLORS := {"str": "#d9765a", "per": "#6fb0c4", "con": "#7ec46a",
	"cha": "#c48fd0", "int": "#d0c46a", "lck": "#d0a05a"}

## Danger tiers 1-4, as the map and the HUD both draw them.
const TIER_COLORS := [Color("#8fae6a"), Color("#8fae6a"), Color("#d9c46a"), Color("#d98a4a"), Color("#e05a4a")]

## The standard gaps. Screen margins 24, grid gaps 20, rows 8.
const MARGIN := 24
const GAP := 20
const ROW_GAP := 8
const RAIL_W := 272
const DETAIL_W := 460
const SLOT_SIZE := 56
const SLOT_GAP := 4

# ------------------------------------------------------------------- fonts --

const FONT_FILES := {
	"display": {500: "res://art/fonts/Oswald-Variable.ttf", 600: "res://art/fonts/Oswald-Variable.ttf"},
	"ui": {400: "res://art/fonts/Barlow-Regular.ttf", 500: "res://art/fonts/Barlow-Medium.ttf",
		600: "res://art/fonts/Barlow-SemiBold.ttf"},
	"mono": {400: "res://art/fonts/IBMPlexMono-Regular.ttf", 500: "res://art/fonts/IBMPlexMono-Medium.ttf"},
}

## Every text style the game uses: face, weight, size, tracking in em, colour,
## and whether it is set in capitals. A `Label` names one of these as its
## `theme_type_variation`; nothing sets a size or a tracking by hand.
const TEXT := {
	"Hero": ["display", 600, 96, 0.2, TEXT_HIGH, true],
	"ScreenTitle": ["display", 600, 34, 0.06, TEXT_HIGH, true],
	"PanelTitle": ["display", 600, 26, 0.05, TEXT_HIGH, true],
	"MenuItem": ["display", 600, 22, 0.08, TEXT_HIGH, true],
	"Wordmark": ["display", 600, 22, 0.16, TEXT_HIGH, true],
	"SectionHead": ["display", 500, 20, 0.08, TEXT_HIGH, true],
	"Name18": ["display", 500, 18, 0.05, TEXT_HIGH, true],
	"ItemName": ["display", 500, 17, 0.03, TEXT_HIGH, true],
	"Location": ["display", 600, 26, 0.12, TEXT_HIGH, true],
	"Body": ["ui", 400, 15, 0.0, TEXT_BODY, false],
	"Row": ["ui", 500, 15, 0.0, TEXT_HIGH, false],
	"Row14": ["ui", 500, 14, 0.0, TEXT_BODY, false],
	"Body14": ["ui", 400, 14, 0.0, TEXT_BODY, false],
	"Small": ["ui", 400, 13, 0.0, TEXT_DIM, false],
	"Caps": ["ui", 600, 12, 0.12, TEXT_DIM, true],
	"Caps13": ["ui", 600, 13, 0.1, TEXT_BODY, true],
	"Caps14": ["ui", 600, 14, 0.1, TEXT_BODY, true],
	"Mono12": ["mono", 500, 12, 0.0, TEXT_DIM, false],
	"Mono": ["mono", 500, 13, 0.0, TEXT_BODY, false],
	"Mono14": ["mono", 500, 14, 0.0, TEXT_BODY, false],
	"Mono15": ["mono", 500, 15, 0.0, TEXT_BODY, false],
	"Mono18": ["mono", 500, 18, 0.0, TEXT_HIGH, false],
	"Mono20": ["mono", 500, 20, 0.0, TEXT_HIGH, false],
	"Mono22": ["mono", 500, 22, 0.0, TEXT_HIGH, false],
}

static var _fonts := {}
static var _theme: Theme = null


## One face at one weight, with tracking in whole pixels. Cached: a screen asks
## for the same dozen fonts thousands of times.
static func font(face: String, weight: int, tracking_px := 0) -> FontVariation:
	var key := "%s%d:%d" % [face, weight, tracking_px]
	if _fonts.has(key):
		return _fonts[key]
	var fv := FontVariation.new()
	fv.base_font = load(String(FONT_FILES[face][weight]))
	if face == "display":
		# Oswald ships as one variable font; the weight is an axis on it.
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): weight}
	fv.spacing_glyph = tracking_px
	_fonts[key] = fv
	return fv


## The font and size of a named style, for the few things that draw their own
## text (slots, meters, the map).
static func style_font(style: String) -> FontVariation:
	var t: Array = TEXT[style]
	return font(t[0], t[1], roundi(float(t[3]) * float(t[2])))


static func style_size(style: String) -> int:
	return int(TEXT[style][2])


# -------------------------------------------------------------- styleboxes --

## A flat box: fill, a border of one width and colour, a corner radius, and
## content margins. `anti_aliasing` is off so a 1px border stays 1px.
static func box(bg: Color, border := Color(0, 0, 0, 0), width := 0, radius := 0,
		pad_x := 0, pad_y := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = false
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	return s


## The same box with a border on some sides only: the bars that sit on an edge.
static func edge(bg: Color, border: Color, left := 0, top := 0, right := 0, bottom := 0,
		pad_x := 0, pad_y := 0) -> StyleBoxFlat:
	var s := box(bg, border, 0, 0, pad_x, pad_y)
	s.border_width_left = left
	s.border_width_top = top
	s.border_width_right = right
	s.border_width_bottom = bottom
	return s


## A state colour laid over the panel at about 14%, the fill of a badge.
static func tint(c: Color, amount := 0.14) -> Color:
	return PANEL.lerp(Color(c, 1.0), amount)


# ------------------------------------------------------------------- theme --

static func theme() -> Theme:
	if _theme == null:
		_theme = build_theme()
	return _theme


static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font("ui", 400)
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT_BODY)

	for name: String in TEXT:
		var st: Array = TEXT[name]
		t.set_type_variation(name, "Label")
		t.set_font("font", name, font(st[0], st[1], roundi(float(st[3]) * float(st[2]))))
		t.set_font_size("font_size", name, int(st[2]))
		t.set_color("font_color", name, st[4])

	# Buttons: four boxes each, differing only in fill and border. Focus is
	# never drawn by the engine: every button is FOCUS_NONE (Space is the dash,
	# and a focused button would take it), and keyboard selection is drawn as
	# the selected state instead, so the two can never stack.
	_button(t, "Primary", "display", 600, 22, 0.1,
		[box(ACCENT, ACCENT_HI, 1, 2, 16, 0), box(ACCENT_HI, ACCENT_HI, 1, 2, 16, 0),
		box(ACCENT_PRESS, ACCENT_HI, 1, 2, 16, 0), box(LINE_SOFT, LINE_SOFT, 1, 2, 16, 0)],
		INK, INK, TEXT_OFF)
	_button(t, "Secondary", "ui", 600, 13, 0.1,
		[box(RAISED, LINE, 1, 2, 16, 0), box(HOVER, LINE_STRONG, 1, 2, 16, 0),
		box(SELECTED, ACCENT, 1, 2, 16, 0), box(PANEL, LINE_SOFT, 1, 2, 16, 0)],
		TEXT_BODY, TEXT_HIGH, TEXT_OFF)
	_button(t, "SecondaryOn", "ui", 600, 13, 0.1,
		[box(HOVER, ACCENT, 1, 2, 16, 0), box(HOVER, ACCENT_HI, 1, 2, 16, 0),
		box(SELECTED, ACCENT_HI, 1, 2, 16, 0), box(PANEL, LINE_SOFT, 1, 2, 16, 0)],
		TEXT_HIGH, TEXT_HIGH, TEXT_OFF)
	_button(t, "PrimarySmall", "display", 600, 15, 0.1,
		[box(ACCENT, ACCENT_HI, 1, 2, 12, 0), box(ACCENT_HI, ACCENT_HI, 1, 2, 12, 0),
		box(ACCENT_PRESS, ACCENT_HI, 1, 2, 12, 0), box(LINE_SOFT, LINE_SOFT, 1, 2, 12, 0)],
		INK, INK, TEXT_OFF)
	_button(t, "SecondarySmall", "display", 600, 15, 0.1,
		[box(RAISED, LINE, 1, 2, 12, 0), box(HOVER, LINE_STRONG, 1, 2, 12, 0),
		box(SELECTED, ACCENT, 1, 2, 12, 0), box(PANEL, LINE_SOFT, 1, 2, 12, 0)],
		TEXT_BODY, TEXT_HIGH, TEXT_OFF)
	var clear := Color(0, 0, 0, 0)
	_button(t, "TopTab", "ui", 600, 13, 0.12,
		[edge(TAB, clear, 0, 0, 0, 2, 26, 0), edge(TAB_HOVER, clear, 0, 0, 0, 2, 26, 0),
		edge(HOVER, ACCENT, 0, 0, 0, 2, 26, 0), edge(TAB, clear, 0, 0, 0, 2, 26, 0)],
		TEXT_DIM, TEXT_BODY, Color("#565b56"))
	_button(t, "TopTabOn", "ui", 600, 13, 0.12,
		[edge(HOVER, ACCENT, 0, 0, 0, 2, 26, 0), edge(HOVER, ACCENT, 0, 0, 0, 2, 26, 0),
		edge(HOVER, ACCENT, 0, 0, 0, 2, 26, 0), edge(HOVER, ACCENT, 0, 0, 0, 2, 26, 0)],
		TEXT_HIGH, TEXT_HIGH, TEXT_HIGH)
	# Rows: transparent until they are pointed at, then the hover box; the
	# selected one is its own variation rather than a toggle, so a click never
	# flips it by itself.
	_button(t, "RailRow", "ui", 500, 15, 0.0,
		[box(clear, clear, 1, 2, 12, 0), box(HOVER, LINE, 1, 2, 12, 0),
		box(SELECTED, ACCENT, 1, 2, 12, 0), box(clear, clear, 1, 2, 12, 0)],
		TEXT_BODY, TEXT_HIGH, TEXT_OFF)
	_button(t, "RailRowOn", "ui", 500, 15, 0.0,
		[box(SELECTED, ACCENT, 1, 2, 12, 0), box(SELECTED, ACCENT_HI, 1, 2, 12, 0),
		box(SELECTED, ACCENT_HI, 1, 2, 12, 0), box(SELECTED, ACCENT, 1, 2, 12, 0)],
		TEXT_HIGH, TEXT_HIGH, TEXT_HIGH)
	_button(t, "Card", "ui", 500, 15, 0.0,
		[box(RAISED, LINE, 1, 3, 2, 2), box(HOVER, LINE_STRONG, 1, 3, 2, 2),
		box(HOVER, LINE_STRONG, 1, 3, 2, 2), box(RAISED, LINE, 1, 3, 2, 2)],
		TEXT_HIGH, TEXT_HIGH, TEXT_HIGH)
	_button(t, "CardOn", "ui", 500, 15, 0.0,
		[box(HOVER, ACCENT_HI, 2, 3, 2, 2), box(HOVER, ACCENT_HI, 2, 3, 2, 2),
		box(HOVER, ACCENT_HI, 2, 3, 2, 2), box(HOVER, ACCENT_HI, 2, 3, 2, 2)],
		TEXT_HIGH, TEXT_HIGH, TEXT_HIGH)
	_button(t, "CardDim", "ui", 500, 15, 0.0,
		[box(DIM_CARD, LINE_SOFT, 1, 3, 2, 2), box(RAISED, LINE, 1, 3, 2, 2),
		box(RAISED, LINE, 1, 3, 2, 2), box(DIM_CARD, LINE_SOFT, 1, 3, 2, 2)],
		TEXT_DIM, TEXT_DIM, TEXT_DIM)
	_button(t, "CardLocked", "ui", 500, 15, 0.0,
		[box(LOCK_CARD, LINE_SOFT, 1, 3, 2, 2), box(DIM_CARD, LINE, 1, 3, 2, 2),
		box(DIM_CARD, LINE, 1, 3, 2, 2), box(LOCK_CARD, LINE_SOFT, 1, 3, 2, 2)],
		TEXT_OFF, TEXT_OFF, TEXT_OFF)
	_button(t, "MenuRow", "ui", 500, 15, 0.0,
		[box(TAB, LINE, 1, 2, 18, 14), box(HOVER, LINE_STRONG, 1, 2, 18, 14),
		box(SELECTED, ACCENT, 1, 2, 18, 14), box(PANEL, LINE_SOFT, 1, 2, 18, 14)],
		TEXT_BODY, TEXT_HIGH, TEXT_OFF)
	_button(t, "MenuRowOn", "ui", 500, 15, 0.0,
		[box(HOVER, ACCENT, 2, 2, 18, 14), box(HOVER, ACCENT_HI, 2, 2, 18, 14),
		box(SELECTED, ACCENT_HI, 2, 2, 18, 14), box(HOVER, ACCENT, 2, 2, 18, 14)],
		TEXT_HIGH, TEXT_HIGH, TEXT_HIGH)
	_button(t, "Pop", "ui", 600, 13, 0.1,
		[box(Color("#1c2026"), Color("#4a525c"), 1, 2, 12, 0), box(Color("#2c333c"), OK, 1, 2, 12, 0),
		box(SELECTED, OK, 1, 2, 12, 0), box(PANEL, LINE_SOFT, 1, 2, 12, 0)],
		TEXT_BODY, TEXT_HIGH, TEXT_OFF)
	_button(t, "Danger", "ui", 600, 12, 0.1,
		[box(TAB, LINE_SOFT, 1, 2, 16, 0), box(RAISED, SHORT, 1, 2, 16, 0),
		box(SHORT_FILL, SHORT, 1, 2, 16, 0), box(PANEL, LINE_SOFT, 1, 2, 16, 0)],
		Color("#8a6a5a"), SHORT, TEXT_OFF)

	# Containers. Content margins live here so every panel pads the same.
	_panel(t, "Pane", box(PANEL, LINE, 1, 3))
	_panel(t, "PanelHead", edge(RAISED, LINE, 0, 0, 0, 1, 14, 12))
	_panel(t, "PanelHeadWide", edge(RAISED, LINE, 0, 0, 0, 1, 20, 20))
	_panel(t, "Inset", box(BASE, LINE_SOFT, 1, 3, 14, 14))
	_panel(t, "Well", box(RAISED, LINE_SOFT, 1, 0, 12, 10))
	_panel(t, "TopBar", edge(PANEL, LINE, 0, 0, 0, 1))
	_panel(t, "SubBar", edge(BASE, LINE_SOFT, 0, 0, 0, 1, 24, 0))
	_panel(t, "Footer", edge(BASE, LINE_SOFT, 0, 1, 0, 0, 24, 0))
	_panel(t, "Tooltip", box(BASE, LINE_STRONG, 1, 3, 14, 12))
	_panel(t, "HudCard", box(HUD_FILL, LINE, 1, 3, 14, 12))
	_panel(t, "HudLine", box(HUD_FILL, LINE, 1, 0, 14, 7))
	_panel(t, "Keycap", box(RAISED, LINE, 1, 2, 12, 7))
	_panel(t, "Chip", box(RAISED, LINE, 1, 2, 12, 6))
	_panel(t, "Dialog", box(PANEL, LINE, 2, 3))

	var field := box(VOID, LINE, 1, 2, 12, 0)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), ACCENT_HI, 1, 2, 12, 0))
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_font("font", "LineEdit", font("ui", 400))
	t.set_font_size("font_size", "LineEdit", 15)
	t.set_color("font_color", "LineEdit", TEXT_BODY)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_OFF)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))

	# Thin scroll bars in the line colour: a list that scrolls should say so
	# without a chunky desktop widget in the middle of a survival screen.
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 3, 3))
		t.set_stylebox("grabber", bar, box(LINE, Color(0, 0, 0, 0), 0, 0, 3, 3))
		t.set_stylebox("grabber_highlight", bar, box(LINE_STRONG, Color(0, 0, 0, 0), 0, 0, 3, 3))
		t.set_stylebox("grabber_pressed", bar, box(LINE_STRONG, Color(0, 0, 0, 0), 0, 0, 3, 3))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	return t


static func _button(t: Theme, name: String, face: String, weight: int, size: int, track: float,
		boxes: Array, col: Color, hot: Color, off: Color) -> void:
	t.set_type_variation(name, "Button")
	t.set_stylebox("normal", name, boxes[0])
	t.set_stylebox("hover", name, boxes[1])
	t.set_stylebox("pressed", name, boxes[2])
	t.set_stylebox("hover_pressed", name, boxes[2])
	t.set_stylebox("disabled", name, boxes[3])
	t.set_stylebox("focus", name, StyleBoxEmpty.new())
	t.set_font("font", name, font(face, weight, roundi(track * size)))
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, col)
	t.set_color("font_hover_color", name, hot)
	t.set_color("font_pressed_color", name, hot)
	t.set_color("font_hover_pressed_color", name, hot)
	t.set_color("font_focus_color", name, col)
	t.set_color("font_disabled_color", name, off)


static func _panel(t: Theme, name: String, sb: StyleBox) -> void:
	t.set_type_variation(name, "PanelContainer")
	t.set_stylebox("panel", name, sb)


# ---------------------------------------------------------------- builders --

## A line of text in a named style. Single line, trimmed with an ellipsis when
## there is not room, never taking the mouse.
static func label(text: String, style := "Body", color: Variant = null) -> Label:
	var l := Label.new()
	l.theme_type_variation = style
	l.text = text
	l.uppercase = bool(TEXT[style][5])
	if color != null:
		l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A paragraph: wraps at the width it is given and grows downward.
static func para(text: String, style := "Body", color: Variant = null) -> Label:
	var l := label(text, style, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	l.clip_text = false
	l.custom_minimum_size.x = 40
	return l


static func set_color(l: Label, c: Color) -> void:
	l.add_theme_color_override("font_color", c)


static func hbox(sep := 8, children: Array = []) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in children:
		b.add_child(c)
	return b


static func vbox(sep := 8, children: Array = []) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in children:
		b.add_child(c)
	return b


static func pad(child: Control, left: int, top := -1, right := -1, bottom := -1) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", left if top < 0 else top)
	m.add_theme_constant_override("margin_right", left if right < 0 else right)
	m.add_theme_constant_override("margin_bottom", (left if top < 0 else top) if bottom < 0 else bottom)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if child != null:
		m.add_child(child)
	return m


static func panel(variation: String, child: Control = null) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if child != null:
		p.add_child(child)
	return p


## A panel with a box of its own rather than a themed one: the one-off fills
## the state strips and badges are.
static func boxed(sb: StyleBox, child: Control = null) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if child != null:
		p.add_child(child)
	return p


static func spacer(expand := true) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func fixed(w: float, h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func rect(color: Color, w := 0.0, h := 0.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(w, h)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A 1px divider, horizontal unless `vertical`.
static func rule(vertical := false, length := 0.0, color := LINE_SOFT) -> ColorRect:
	return rect(color, 1.0, length) if vertical else rect(color, length, 1.0)


## Takes the space its row or column leaves. A single-line label that expands
## also trims, so it can give that space back rather than push past the edge.
static func expand(c: Control, horizontal := true, vertical := false) -> Control:
	if horizontal:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if c is Label and (c as Label).autowrap_mode == TextServer.AUTOWRAP_OFF:
			(c as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			(c as Label).clip_text = true
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## A button that never takes keyboard focus. Space is the dash and Enter is
## the screen's own commit, and a focused engine button would take both.
static func button(text: String, variation: String, pressed: Callable = Callable()) -> Button:
	var b := Button.new()
	b.theme_type_variation = variation
	# Every button label is set in capitals, as the design has them.
	b.text = text.to_upper()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if pressed.is_valid():
		b.pressed.connect(pressed)
	return b


## A button whose face is built from children rather than its own text.
static func face_button(variation: String, content: Control, pressed: Callable = Callable()) -> Button:
	var b := FaceButton.new()
	b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if pressed.is_valid():
		b.pressed.connect(pressed)
	b.face = content
	b.add_child(content)
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.minimum_size_changed.connect(b.fit)
	b.ready.connect(b.fit)
	return b


## A Button whose face is a tree of Controls. A Button does not size itself to
## its children — and its minimum size is computed natively, so a script
## `_get_minimum_size` is never asked — so this one keeps its
## `custom_minimum_size` at its face's minimum, recomputed every time the face
## changes. Recomputed from the floor rather than only grown, so a wrapped
## paragraph that gets the width to lie flatter lets the button shrink back;
## the floor is whatever size the caller set (a 40px rail row, a 174px card).
class FaceButton extends Button:
	var face: Control = null
	var floor_size := Vector2(-1, -1)

	func fit() -> void:
		if face == null or not is_instance_valid(face):
			return
		if floor_size.x < 0.0:
			floor_size = custom_minimum_size
		var want := floor_size.max(face.get_combined_minimum_size())
		if want != custom_minimum_size:
			custom_minimum_size = want


## A key and what it does: `ESC Close`, `TAB Next category`. The key is always
## the binding's own label, never a hard-coded letter.
static func hint(key: String, text: String) -> HBoxContainer:
	return hbox(8, [label(key, "Mono12", TEXT_OFF), label(text, "Small")])


## The boxed version for a top bar's right-hand end.
static func keycap(key: String, text: String) -> PanelContainer:
	return panel("Keycap", hbox(8, [label(key, "Mono12", TEXT_DIM), label(text, "Caps", TEXT_BODY)]))


## A small state label: fill at ~14% of the colour, border at ~55%.
static func badge(text: String, c: Color, mono := false) -> PanelContainer:
	var sb := box(tint(c), PANEL.lerp(c, 0.55), 1, 2, 8, 3)
	return boxed(sb, label(text, "Mono12" if mono else "Caps", c))


## A caption over a value: the stat blocks on sub-bars and detail panels.
static func stat(caption: String, value: String, value_style := "Mono18", c: Variant = null) -> VBoxContainer:
	return vbox(3, [label(caption, "Caps"), label(value, value_style, c)])


## The same, in the boxed cell the detail panels use.
static func stat_cell(caption: String, value: String, c: Variant = null) -> PanelContainer:
	return panel("Well", vbox(4, [label(caption, "Caps"), label(value, "Mono20", c)]))


## A section heading inside a panel.
static func head(text: String, right: Control = null) -> PanelContainer:
	var row := hbox(12, [expand(label(text, "Caps"))])
	if right != null:
		row.add_child(right)
	return panel("PanelHead", row)


## The mono readout of a bill: one swatch and count per material, green when
## you have it and coral when you do not (or plain when `have` is empty).
## `wrap` lets the chips flow onto a second line inside a card; a row wants
## them on one line, because a flow container is only as wide as its widest
## chip and would otherwise stack them into a column.
static func cost_chips(cost: Dictionary, have: Callable = Callable(), style := "Mono12", dim := false, wrap := true) -> Container:
	var flow: Container
	if wrap:
		var f := HFlowContainer.new()
		f.add_theme_constant_override("h_separation", 10)
		f.add_theme_constant_override("v_separation", 4)
		flow = f
	else:
		flow = hbox(10)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for id: String in cost:
		var need := int(cost[id])
		var txt := str(need)
		var c := TEXT_BODY if not dim else TEXT_DIM
		if have.is_valid():
			var h: int = have.call(id)
			if h < need:
				txt = "%d/%d" % [h, need]
				c = SHORT
			else:
				c = OK if not dim else TEXT_DIM
		var sw := UiSwatch.new(id, 8 if style == "Mono12" else 11)
		sw.alpha = 0.6 if dim else 1.0
		flow.add_child(hbox(5, [sw, label(txt, style, c)]))
	return flow


## A have/need line: swatch, name, `have / need` in mono, and a tick or a
## cross. Short rows sit on a coral-tinted box so a glance finds them.
static func req_line(id: String, have: int, need: int) -> PanelContainer:
	var met := have >= need
	var sb := box(RAISED if met else Color("#1a1518"), LINE_SOFT if met else SHORT_EDGE, 1, 0, 12, 0)
	var row := hbox(12, [UiSwatch.new(id, 18), expand(label(Items.name_of(id), "Row")),
		label("%d / %d" % [have, need], "Mono15", OK if met else SHORT),
		label("✓" if met else "✕", "Caps14", OK if met else SHORT)])
	var p := boxed(sb, row)
	p.custom_minimum_size.y = 40
	return p


## The bench or tool line under a bill: a tick, what is required, and a
## right-aligned status in mono (`STANDING AT ONE`, `NOT CARRIED`).
static func requires_line(what: String, status: String, ok: bool, verb := "Requires") -> PanelContainer:
	var row := hbox(10, [label("✓" if ok else "✕", "Caps13", OK if ok else SHORT),
		label(verb, "Row14"), expand(label(what, "Row14", TEXT_HIGH)),
		label(status, "Mono12", OK_DIM if ok else SHORT)])
	return boxed(box(BASE, LINE_SOFT, 1, 0, 12, 10), row)


## A vertical scroll area that fills what it is given and never reports a
## minimum height of its own — which is what lets a long list sit inside a
## fixed screen without pushing anything past the bottom of the window.
static func scroller(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.follow_focus = false
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


## Frees every child now rather than at the end of the frame, so a rebuilt
## list never has last frame's rows standing under this frame's for a tick.
static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


## The class line under an item's name: what kind of thing it is, in the
## words a player would use rather than the registry's.
static func kind_line(id: String) -> String:
	match Items.kind_of(id):
		"weapon":
			var w: Dictionary = Config.WEAPONS.get(id, {})
			var k := "Ranged" if String(w.get("kind", "")) in ["gun", "bow"] else "Melee"
			return k + ("  ·  Tool" if w.get("tool", false) else "")
		"gear":
			var g: Dictionary = Config.GEAR.get(id, {})
			return String(Config.GEAR_SLOT_NAMES.get(String(g.get("slot", "")), "Gear"))
		"consumable":
			var c: Dictionary = Config.CONSUMABLES.get(id, {})
			if c.get("food", false):
				return "Food"
			if float(c.get("heal", 0.0)) > 0.0:
				return "Medical"
			if c.get("tool", false):
				return "Tool"
			return "Consumable"
		"res":
			return "Ammo" if id in Config.AMMO_IDS else "Material"
	return ""


## The colour a condition sliver is drawn in: green, amber once worn, coral
## once nearly spent — on the same thresholds the notices use.
static func wear_color(frac: float) -> Color:
	if frac <= float(Config.WEAR.spent_at):
		return SHORT
	if frac <= float(Config.WEAR.worn_at):
		return WORN
	return OK


## Whether a label's text changed; setting a Label's text re-shapes it, and a
## HUD sets two hundred of them a frame.
static func set_text(l: Label, text: String) -> void:
	if l.text != text:
		l.text = text
