class_name MenuScreen
extends Control
## The title screen, the pause menu, and the controls list — one Control,
## because they are three pages of the same book and every one of them is a
## list of rows you click.
##
## Drawn immediate-mode against a computed row list, the same way the HUD and
## the pack screen are, so what looks clickable and what *is* clickable come
## from one place (`_rows()`).
##
## It owns no game state. It emits `chose` with an action id and the scene
## decides what that means — which is what lets the same CONTROLS page serve
## the title screen, where there is no simulation at all, and the pause menu,
## where there is one running behind it.

signal chose(what: String, arg: int)

enum Page { TITLE, PAUSE, LOAD, CONTROLS, NEW_GAME }

var page: int = Page.TITLE
## Where CONTROLS should go back to. The page is shared; its exit is not.
var came_from: int = Page.TITLE
var mouse := Vector2.ZERO
## The action waiting for a key press, or "".
var rebinding := ""
var scroll := 0
## Set by the scene: a pause menu is drawn over a live game, a title screen
## over nothing.
var over_game := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


## Redrawn every frame while it is up. A Control keeps whatever it last
## painted, so changing `page` without invalidating it leaves the old page on
## screen with the new one underneath — and the rows are live anyway: a save
## summary changes as the game runs behind a pause menu.
##
## This is the third time this codebase has met the stale-Control bug (the
## build bar in 3b, the pack screen in 3c). Redrawing while visible is the
## version of the fix that cannot be forgotten at a new call site.
func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


func open(to: int) -> void:
	page = to
	scroll = 0
	rebinding = ""
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
	rebinding = ""


# ------------------------------------------------------------------ layout --

func _panel() -> Rect2:
	var vp := get_viewport_rect().size
	var w := minf(560.0 if page != Page.CONTROLS else 720.0, vp.x - 40.0)
	var h := minf(520.0, vp.y - 40.0)
	return Rect2(Vector2((vp.x - w) / 2.0, (vp.y - h) / 2.0), Vector2(w, h))


## Every clickable row: {id, label, note, rect, enabled, arg}.
func _rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var panel := _panel()
	var x := panel.position.x + 32.0
	var w := panel.size.x - 64.0
	var y := panel.position.y + 96.0

	match page:
		Page.TITLE:
			var latest := Saves.latest()
			out.append({"id": "continue", "label": "CONTINUE", "arg": int(latest.get("slot", -1)),
				"note": "%s  ·  %s" % [latest.get("name", ""), Saves.summary_line(latest)] if not latest.is_empty() else "No saved game",
				"enabled": not latest.is_empty()})
			out.append({"id": "new", "label": "NEW GAME", "arg": 0,
				"note": "A fresh town, a steel pipe, and nothing else",
				"enabled": Saves.first_free() >= 0})
			out.append({"id": "load_page", "label": "LOAD GAME", "arg": 0,
				"note": "%d saved" % Saves.list().size(), "enabled": Saves.has_any()})
			out.append({"id": "controls_page", "label": "CONTROLS", "arg": 0, "note": "", "enabled": true})
			out.append(_sound_row())
			out.append({"id": "quit", "label": "QUIT", "arg": 0, "note": "", "enabled": true})
		Page.PAUSE:
			out.append({"id": "resume", "label": "RESUME", "arg": 0, "note": "", "enabled": true})
			out.append({"id": "save", "label": "SAVE", "arg": 0, "note": "", "enabled": true})
			out.append({"id": "controls_page", "label": "CONTROLS", "arg": 0, "note": "", "enabled": true})
			out.append(_sound_row())
			out.append({"id": "quit_to_title", "label": "SAVE AND QUIT TO TITLE", "arg": 0,
				"note": "Writes the game down first", "enabled": true})
		Page.NEW_GAME:
			var free := Saves.first_free()
			out.append({"id": "new_confirm", "label": "START", "arg": free,
				"note": "Into slot %d" % free if free >= 0 else "Every slot is full — delete one first",
				"enabled": free >= 0})
			out.append({"id": "back", "label": "BACK", "arg": 0, "note": "", "enabled": true})
		Page.LOAD:
			for s in Saves.list():
				out.append({"id": "load", "label": String(s.get("name", "Game")), "arg": int(s.slot),
					"note": "%s  ·  %s" % [Saves.summary_line(s), Saves.when_label(float(s.get("updated", 0.0)))],
					"enabled": true})
				out.append({"id": "delete", "label": "DELETE", "arg": int(s.slot),
					"note": "", "enabled": true, "small": true})
			out.append({"id": "back", "label": "BACK", "arg": 0, "note": "", "enabled": true})
		Page.CONTROLS:
			for row in KeyBinds.ACTIONS:
				out.append({"id": "bind", "label": String(row.name), "arg": 0,
					"action": String(row.id), "note": "", "enabled": true})

	# The way out never scrolls. A page whose BACK button is below the fold is
	# a page you can get stuck on, and CONTROLS has twenty-three rows.
	var pinned: Array[Dictionary] = []
	if page == Page.CONTROLS:
		pinned.append({"id": "reset", "label": "RESET TO DEFAULTS", "arg": 0, "note": "", "enabled": true})
		pinned.append({"id": "back", "label": "BACK", "arg": 0, "note": "", "enabled": true})
	elif page == Page.LOAD or page == Page.NEW_GAME:
		pinned.append({"id": "back", "label": "BACK", "arg": 0, "note": "", "enabled": true})

	# Lay the scrolling rows out. CONTROLS is the only page long enough to
	# need it, but scrolling every page costs nothing and surprises nobody.
	var rh := 30.0 if page == Page.CONTROLS else 46.0
	var foot: float = 16.0 + pinned.size() * 34.0
	var visible_rows := int((panel.size.y - 130.0 - foot) / rh)
	scroll = clampi(scroll, 0, maxi(0, out.size() - visible_rows))
	var laid: Array[Dictionary] = []
	for i in range(scroll, mini(out.size(), scroll + visible_rows)):
		var r: Dictionary = out[i]
		var rw: float = w * (0.28 if r.get("small", false) else 1.0)
		var rx: float = x + (w - rw) if r.get("small", false) else x
		r["rect"] = Rect2(rx, y + (i - scroll) * rh, rw, rh - 6.0)
		laid.append(r)

	var fy := panel.position.y + panel.size.y - foot
	for i in range(pinned.size()):
		var r: Dictionary = pinned[i]
		r["rect"] = Rect2(x, fy + i * 34.0, w, 28.0)
		laid.append(r)
	return laid


# ------------------------------------------------------------------- input --

## Waiting for a key: the next one pressed becomes the binding.
##
## This is `_input` rather than `_gui_input` deliberately. `_gui_input` only
## receives key events when the Control has keyboard focus, and this one is
## drawn immediate-mode with `FOCUS_NONE` — so the rebind row lit up, waited,
## and never saw the key. The smoke missed it by calling `_gui_input` directly,
## which is the same mistake as the 4c review: a test that calls the function
## instead of pressing the key.
##
## Escape is not handled here. It is the one key with a single owner (the
## scene's pause poll, which calls `back()`), so that "get me out of here"
## cannot mean two things on one frame.
func _input(event: InputEvent) -> void:
	if not visible or rebinding.is_empty():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = (event as InputEventKey).physical_keycode
	if k != KEY_ESCAPE and KeyBinds.rebind(rebinding, k):
		rebinding = ""
	queue_redraw()
	get_viewport().set_input_as_handled()


## One step out: an active rebind, then a subpage, then the pause menu itself.
## Returns false when there is nothing left to back out of, which is the title
## screen — Escape there means nothing rather than quitting the game by
## accident. This is what Escape does while the menu is up, and it lives here
## because the menu is what knows which page it is on.
func back() -> bool:
	if not rebinding.is_empty():
		rebinding = ""
		queue_redraw()
		return true
	match page:
		Page.CONTROLS:
			open(came_from)
			return true
		Page.LOAD, Page.NEW_GAME:
			open(Page.PAUSE if over_game else Page.TITLE)
			return true
		Page.PAUSE:
			if over_game:
				close()
				return true
	return false


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseMotion:
		mouse = event.position
		queue_redraw()
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	mouse = mb.position
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
		scroll += 1
		queue_redraw()
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
		scroll = maxi(0, scroll - 1)
		queue_redraw()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return

	for r in _rows():
		if not r.rect.has_point(mouse) or not r.enabled:
			continue
		_press(r)
		queue_redraw()
		accept_event()
		return


## The sound toggle, on both the title screen and the pause menu — it is the
## same setting, and it belongs wherever you happen to be when it annoys you.
func _sound_row() -> Dictionary:
	return {"id": "mute", "label": "SOUND: OFF" if Sfx.muted() else "SOUND: ON",
		"arg": 0, "note": "", "enabled": true}


func _press(r: Dictionary) -> void:
	match String(r.id):
		"bind":
			rebinding = String(r.action)
		"reset":
			KeyBinds.reset_all()
		"mute":
			# A setting, not a key: whether your speakers are on is not something
			# you should have to remember a letter for.
			Sfx.set_muted(not Sfx.muted())
		"controls_page":
			came_from = page
			open(Page.CONTROLS)
		"load_page":
			open(Page.LOAD)
		"new":
			open(Page.NEW_GAME)
		"back":
			open(came_from if page == Page.CONTROLS else (Page.PAUSE if over_game else Page.TITLE))
		_:
			chose.emit(String(r.id), int(r.arg))


# ----------------------------------------------------------------- drawing --

func _draw() -> void:
	if not visible:
		return
	var font := ThemeDB.fallback_font
	var vp := get_viewport_rect().size
	# Over a live game this is a scrim; over nothing it is the whole screen.
	draw_rect(Rect2(Vector2.ZERO, vp), Color("#0b0d10", 0.72 if over_game else 1.0))

	var panel := _panel()
	draw_rect(panel, Color("#14161a", 0.98))
	draw_rect(panel, Color("#3a4048"), false, 2.0)

	var title := "DEADLINE"
	var sub := "a town, a pipe, and whatever you can carry"
	match page:
		Page.PAUSE:
			title = "PAUSED"
			sub = ""
		Page.LOAD:
			title = "LOAD GAME"
			sub = "click a save to open it"
		Page.CONTROLS:
			title = "CONTROLS"
			sub = "click a row, then press a key  ·  Esc cancels  ·  mouse and Esc are fixed"
		Page.NEW_GAME:
			title = "NEW GAME"
			sub = "the world is the same town every time; what you do in it is not"
	draw_string(font, panel.position + Vector2(32, 46), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("#d8e8c0"))
	if not sub.is_empty():
		draw_string(font, panel.position + Vector2(32, 68), sub, HORIZONTAL_ALIGNMENT_LEFT,
			panel.size.x - 64, 11, Color(1, 1, 1, 0.35))

	for r in _rows():
		if String(r.id) == "bind":
			_draw_bind_row(font, r)
		else:
			_draw_row(font, r)


func _draw_row(font: Font, r: Dictionary) -> void:
	var rect: Rect2 = r.rect
	var hot: bool = rect.has_point(mouse) and r.enabled
	draw_rect(rect, Color("#242a32") if hot else Color("#181b20"))
	draw_rect(rect, Color("#d8e8c0") if hot else Color("#3a4048"), false, 1.0)
	var col := Color("#ebe6d6") if r.enabled else Color("#6a6f68")
	if String(r.id) == "delete":
		col = Color("#c96a5a") if hot else Color("#8a6a5a")
	draw_string(font, rect.position + Vector2(12, 20), String(r.label), HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 24, 14, col)
	var note := String(r.get("note", ""))
	if not note.is_empty():
		draw_string(font, rect.position + Vector2(12, 34), note, HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x - 24, 10, Color(1, 1, 1, 0.3 if r.enabled else 0.18))


func _draw_bind_row(font: Font, r: Dictionary) -> void:
	var rect: Rect2 = r.rect
	var id := String(r.action)
	var hot: bool = rect.has_point(mouse)
	var waiting := rebinding == id
	draw_rect(rect, Color("#2a3038") if waiting else (Color("#242a32") if hot else Color("#181b20")))
	draw_rect(rect, Color("#d8e8c0") if waiting or hot else Color("#3a4048"), false, 1.0)
	draw_string(font, rect.position + Vector2(12, 16), String(r.label), HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 200, 12, Color("#ebe6d6"))

	# Conflicts are shown, not refused: two things on one key is the player's
	# choice to make, and theirs to notice.
	var clash := KeyBinds.conflicts_for(id)
	var right := "press a key…" if waiting else KeyBinds.label_for(id)
	var rcol := Color("#ffe08a") if waiting else (Color("#c96a5a") if not clash.is_empty() else Color("#9fd0ff"))
	draw_string(font, rect.position + Vector2(0, 16), right, HORIZONTAL_ALIGNMENT_RIGHT,
		rect.size.x - 12, 12, rcol)
	if not clash.is_empty() and not waiting:
		draw_string(font, rect.position + Vector2(0, 27), "also " + ", ".join(clash),
			HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 12, 9, Color("#c96a5a", 0.7))
	elif not KeyBinds.is_default(id) and not waiting:
		draw_string(font, rect.position + Vector2(0, 27), "changed", HORIZONTAL_ALIGNMENT_RIGHT,
			rect.size.x - 12, 9, Color(1, 1, 1, 0.25))
