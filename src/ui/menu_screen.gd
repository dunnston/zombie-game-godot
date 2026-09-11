class_name MenuScreen
extends UiScreen
## The title screen with its save slots, the pause menu, the settings (the
## key bindings, sound and the window), and the small pages in between: new
## game, load, multiplayer, host and join. One Control, because they are
## pages of the same book and every one of them is a list of rows you click.
##
## `_rows()` is the single source of what is on a page and what each row does;
## the page is built from it and rebuilt whenever it changes. It owns no game
## state: it emits `chose` with an action id and the scene decides what that
## means — which is what lets the same settings page serve the title screen,
## where there is no simulation at all, and the pause menu over a live one.

signal chose(what: String, arg: int)

enum Page { TITLE, PAUSE, LOAD, CONTROLS, NEW_GAME, MULTIPLAYER, JOIN, HOST }

var page: int = Page.TITLE
## Where CONTROLS should go back to. The page is shared; its exit is not.
var came_from: int = Page.TITLE
## The action waiting for a key press, or "".
var rebinding := ""
## Set by the scene: a pause menu is drawn over a live game, a title screen
## over nothing.
var over_game := false
## The settings page's own tab: "controls", "sound" or "display".
var settings_tab := "controls"
## The row the arrow keys are on, by index into the enabled rows.
var sel := 0

## What the scene knows about the connection, refreshed every frame it is up:
## role ("solo", "host", "guest", "joining"), a status line, the last error,
## the guests' names and the port.
var net := {"role": "solo", "status": "", "error": "", "guests": [], "port": 0,
	"door": "", "public": "", "lan": [], "code": "", "room": ""}
## What the HOST and JOIN pages type into.
var fields := {"address": "", "name": "", "password": ""}
## The field being typed into, or "".
var editing := ""
## What START HOSTING should host: -2 the game running behind the pause menu,
## -3 a new game, or a slot number to load first.
var host_arg := -2
## Where JOIN and HOST go back to.
var came_from_net: int = Page.MULTIPLAYER
## Set by the scene while paused: where you are and when, and the slot this
## game writes to — the pause menu's own subtitle and SAVE line.
var status_line := ""
var slot := -1

var _sig := ""
var _fields_ui := {}
var _dlg_sc: ScrollContainer = null
var _dlg_list: Control = null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Ui.theme()


## Rebuilt when what it shows changes, and refreshed every frame it is up: a
## save summary changes as the game runs behind a pause menu.
func _process(_dt: float) -> void:
	if visible:
		refresh()
		_fit_dialog()


func open(to: int) -> void:
	page = to
	rebinding = ""
	editing = ""
	sel = 0
	if to == Page.CONTROLS:
		settings_tab = "controls"
	visible = true
	refresh()


func close() -> void:
	visible = false
	rebinding = ""
	editing = ""


func _row(id: String, label: String, note := "", enabled := true, arg := 0) -> Dictionary:
	return {"id": id, "label": label, "arg": arg, "note": note, "enabled": enabled}


## A line you type into. `field` is the key in `fields`.
func _text_row(field: String, label: String, note := "") -> Dictionary:
	return {"id": "text", "label": label, "arg": 0, "note": note, "enabled": true, "field": field}


## Every row on the page, in order: {id, label, note, enabled, arg, and for
## some `tag` (the mono readout on the right), `action` or `field`}.
func _rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match page:
		Page.TITLE:
			var latest := Saves.latest()
			var r := {"id": "continue", "label": "CONTINUE", "arg": int(latest.get("slot", -1)),
				"note": "%s  ·  %s" % [latest.get("name", ""), Saves.summary_line(latest)] if not latest.is_empty() else "No saved game",
				"enabled": not latest.is_empty()}
			if not latest.is_empty():
				r["tag"] = "SLOT %d" % (int(latest.slot) + 1)
			out.append(r)
			var free := Saves.first_free()
			out.append({"id": "new", "label": "NEW GAME", "arg": 0,
				"note": "A fresh town, a steel pipe, and nothing else" + ("  ·  into slot %d" % (free + 1) if free >= 0 else ""),
				"enabled": free >= 0})
			if free < 0:
				out[1].note = "Every slot is full"
			out.append({"id": "load_page", "label": "LOAD GAME", "arg": 0, "note": "",
				"tag": "%d SAVED" % Saves.list().size(), "enabled": Saves.has_any()})
			out.append(_row("multiplayer_page", "MULTIPLAYER", "Host a game for friends, or join one  ·  up to four in one town"))
			out.append({"id": "controls_page", "label": "CONTROLS", "arg": 0, "note": "", "enabled": true, "small": true})
			out.append(_sound_row(true))
			out.append({"id": "quit", "label": "QUIT", "arg": 0, "note": "", "enabled": true, "small": true})
		Page.PAUSE:
			var role := String(net.role)
			out.append({"id": "resume", "label": "RESUME", "arg": 0, "note": "", "enabled": true, "tag": "ESC"})
			if role == "guest":
				# A guest's world is the host's to save. Nothing here writes.
				out.append(_row("host_page", "PLAYING IN %s'S GAME" % String(net.status).to_upper(), "", false))
			else:
				var r := {"id": "save", "label": "SAVE", "arg": 0, "enabled": true,
					"tag": ("SLOT %d  ·  %s" % [slot + 1, KeyBinds.primary_label("quick_save")]) if slot >= 0 and slot < Saves.MAX_SLOTS else KeyBinds.primary_label("quick_save"),
					"note": _last_written()}
				out.append(r)
				if role == "host":
					var n: int = (net.guests as Array).size()
					var hr := _row("host_page", "HOSTING  ·  %d CONNECTED" % n,
						", ".join(net.guests) + ("  ·  room code %s" % String(net.code) if not String(net.code).is_empty() else "") if n > 0 else "Nobody has joined yet")
					hr["tag"] = "UDP %d" % int(net.port)
					hr["tag_color"] = Ui.XP
					out.append(hr)
				else:
					out.append(_row("host_page", "HOST THIS GAME", "Let friends join the world you are in"))
			out.append({"id": "controls_page", "label": "CONTROLS", "arg": 0, "note": "", "enabled": true,
				"tag": "%d KEYS" % KeyBinds.ACTIONS.size()})
			out.append(_sound_row())
			if role == "guest":
				out.append(_row("leave_game", "LEAVE GAME", "Your character stays in the host's save"))
			else:
				out.append({"id": "quit_to_title", "label": "SAVE AND QUIT TO TITLE", "arg": 0,
					"note": "Writes the game down first" + ("  ·  ends the session for everyone" if role == "host" else ""), "enabled": true})
		Page.MULTIPLAYER:
			var latest := Saves.latest()
			out.append(_row("host_slot", "HOST — CONTINUE", "%s  ·  %s" % [latest.get("name", ""), Saves.summary_line(latest)] if not latest.is_empty() else "No saved game",
				not latest.is_empty(), int(latest.get("slot", -1))))
			out.append(_row("host_new", "HOST — NEW GAME", "A fresh town, in slot %d" % (Saves.first_free() + 1) if Saves.first_free() >= 0 else "Every slot is full",
				Saves.first_free() >= 0, Saves.first_free()))
			out.append(_row("join_page", "JOIN A GAME", "Dial a friend who is hosting"))
		Page.HOST:
			if String(net.role) == "host":
				var n: int = (net.guests as Array).size()
				out.append(_row("info", "HOSTING ON UDP PORT %d" % int(net.port),
					"%d connected: %s" % [n, ", ".join(net.guests)] if n > 0 else "Nobody has joined yet", false))
				# The room code, when the broker road is switched on: the thing
				# to read out over voice chat.
				if not String(net.code).is_empty():
					out.append(_row("copy_code", "ROOM CODE:  %s" % String(net.code), String(net.room) + "  ·  click to copy"))
				elif not String(net.room).is_empty():
					out.append(_row("info", "ROOM", String(net.room), false))
				# The internet door: what the router said, and the address to hand
				# out if it said yes. The LAN address is always there.
				var pub := String(net.public)
				if not pub.is_empty():
					out.append(_row("copy_address", "INTERNET:  %s" % pub, String(net.door) + "  ·  click to copy"))
				elif not String(net.door).is_empty():
					out.append(_row("info", "INTERNET", String(net.door), false))
				var lan: Array = net.lan
				if not lan.is_empty():
					out.append(_row("copy_address" if pub.is_empty() else "info", "THIS NETWORK:  %s" % ", ".join(lan),
						"Friends on the same LAN or VPN type one of these" + ("  ·  click to copy" if pub.is_empty() else ""), pub.is_empty()))
				out.append(_row("host_stop", "STOP HOSTING", "Guests are dropped; their characters stay in the save"))
			else:
				out.append(_text_row("name", "YOUR NAME", "What the others see over your head"))
				out.append(_text_row("password", "PASSWORD", "Optional. Guests must type the same one"))
				out.append(_row("host_start", "START HOSTING", "Listens on UDP port %d and asks your router to open it to the internet" % int(net.port), true, host_arg))
				if not String(net.error).is_empty():
					out.append(_row("info", String(net.error), "", false))
		Page.JOIN:
			var busy := String(net.role) == "joining"
			out.append(_text_row("address", "HOST ADDRESS", "IP or hostname, with :port if it is not %d — or a six-letter room code" % int(net.port)))
			out.append(_text_row("name", "YOUR NAME", ""))
			out.append(_text_row("password", "PASSWORD", "If the host set one"))
			if busy:
				out.append(_row("join_cancel", "CANCEL", String(net.status)))
			else:
				out.append(_row("join_start", "JOIN", String(net.status), not String(fields.address).strip_edges().is_empty()))
			if not String(net.error).is_empty():
				out.append(_row("info", String(net.error), "", false))
		Page.NEW_GAME:
			var free := Saves.first_free()
			out.append({"id": "new_confirm", "label": "START", "arg": free,
				"note": "Into slot %d" % (free + 1) if free >= 0 else "Every slot is full — delete one first",
				"enabled": free >= 0})
		Page.LOAD:
			for s in Saves.list():
				out.append({"id": "load", "label": String(s.get("name", "Game")), "arg": int(s.slot),
					"note": "%s  ·  %s" % [Saves.summary_line(s), Saves.when_label(float(s.get("updated", 0.0)))],
					"enabled": true, "tag": "SLOT %d" % (int(s.slot) + 1)})
				out.append({"id": "delete", "label": "DELETE", "arg": int(s.slot), "note": "", "enabled": true, "small": true})
		Page.CONTROLS:
			match settings_tab:
				"controls":
					for row in KeyBinds.ACTIONS:
						out.append({"id": "bind", "label": String(row.name), "arg": 0,
							"action": String(row.id), "group": String(row.group), "note": "", "enabled": true})
					out.append(_row("reset", "RESET TO DEFAULTS"))
				"sound":
					out.append(_sound_row())
				"display":
					out.append({"id": "fullscreen", "label": "WINDOW", "arg": 0, "enabled": true,
						"note": "Fullscreen fills the monitor; the game scales to any window without cropping",
						"tag": "FULLSCREEN" if DisplayPrefs.fullscreen() else "WINDOWED"})
	# The way out, last, on every page that is not the front door or the
	# pause menu itself.
	if page in [Page.CONTROLS, Page.LOAD, Page.NEW_GAME, Page.MULTIPLAYER, Page.JOIN, Page.HOST]:
		out.append({"id": "back", "label": "BACK", "arg": 0, "note": "", "enabled": true, "pinned": true})
	return out


func _last_written() -> String:
	for s in Saves.list():
		if int(s.slot) == slot:
			return "Last written %s" % Saves.when_label(float(s.get("updated", 0.0)))
	return "Not saved yet"


## The sound toggle, on the title screen, the pause menu and the settings — it
## is the same setting, and it belongs wherever you are when it annoys you.
func _sound_row(small := false) -> Dictionary:
	var on := not Sfx.muted()
	return {"id": "mute", "label": "SOUND", "arg": 0, "note": "", "enabled": true, "small": small,
		"tag": "ON" if on else "OFF", "tag_color": Ui.OK if on else Ui.TEXT_DIM}


# ------------------------------------------------------------------- input --

## Waiting for a key: the next one pressed becomes the binding. `_input` rather
## than `_gui_input` deliberately: a Control only sees keys while it holds
## focus, and the smoke once missed exactly this by calling the handler
## instead of pressing the key. Escape is the scene's (it calls `back()`).
func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	var key := event as InputEventKey
	if not editing.is_empty():
		if key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER or key.physical_keycode == KEY_TAB:
			_end_edit()
			get_viewport().set_input_as_handled()
		return
	if not rebinding.is_empty():
		if key.echo:
			return
		var k: int = key.physical_keycode
		if k != KEY_ESCAPE and KeyBinds.rebind(rebinding, k):
			rebinding = ""
		refresh()
		get_viewport().set_input_as_handled()
		return
	# The arrow keys walk the rows and Enter presses one. The world is not
	# running while a menu is up, so nothing else wants them.
	var enabled := _enabled_rows()
	match key.physical_keycode:
		KEY_UP, KEY_DOWN:
			if not enabled.is_empty():
				sel = clampi(sel + (1 if key.physical_keycode == KEY_DOWN else -1), 0, enabled.size() - 1)
		KEY_ENTER, KEY_KP_ENTER:
			if key.echo or enabled.is_empty():
				return
			_press(enabled[clampi(sel, 0, enabled.size() - 1)])
		_:
			return
	get_viewport().set_input_as_handled()


func _enabled_rows() -> Array:
	return _rows().filter(func(r: Dictionary) -> bool: return bool(r.enabled) and String(r.id) != "info")


## One step out: an active rebind, then a field being typed in, then a
## subpage, then the pause menu itself. False when there is nothing left to
## back out of, which is the title screen — Escape there means nothing rather
## than quitting the game by accident.
func back() -> bool:
	if not rebinding.is_empty():
		rebinding = ""
		return true
	if not editing.is_empty():
		_end_edit()
		return true
	match page:
		Page.CONTROLS:
			open(came_from)
			return true
		Page.LOAD, Page.NEW_GAME, Page.MULTIPLAYER:
			open(Page.PAUSE if over_game else Page.TITLE)
			return true
		Page.JOIN, Page.HOST:
			open(came_from_net)
			return true
		Page.PAUSE:
			if over_game:
				close()
				return true
	return false


func _end_edit() -> void:
	var f: LineEdit = _fields_ui.get(editing, null)
	editing = ""
	if f != null and is_instance_valid(f):
		f.release_focus()


func _press(r: Dictionary) -> void:
	match String(r.id):
		"bind":
			rebinding = String(r.action)
		"reset":
			KeyBinds.reset_all()
		"mute":
			# A setting, not a key: whether your speakers are on is not
			# something you should have to remember a letter for.
			Sfx.set_muted(not Sfx.muted())
		"fullscreen":
			DisplayPrefs.set_fullscreen(not DisplayPrefs.fullscreen())
		"controls_page":
			came_from = page
			open(Page.CONTROLS)
		"load_page":
			open(Page.LOAD)
		"new":
			open(Page.NEW_GAME)
		"text":
			var f: LineEdit = _fields_ui.get(String(r.field), null)
			if f != null:
				f.grab_focus()
			editing = String(r.field)
		"info":
			pass
		"multiplayer_page":
			open(Page.MULTIPLAYER)
		"join_page":
			came_from_net = page
			open(Page.JOIN)
		"host_page", "host_slot", "host_new":
			# Which game to host is decided here; the scene only hears START
			# HOSTING, with that as its argument.
			host_arg = -2 if String(r.id) == "host_page" else (-3 if String(r.id) == "host_new" else int(r.arg))
			came_from_net = page
			open(Page.HOST)
		"back":
			if page == Page.JOIN or page == Page.HOST:
				open(came_from_net)
			else:
				open(came_from if page == Page.CONTROLS else (Page.PAUSE if over_game else Page.TITLE))
		_:
			chose.emit(String(r.id), int(r.arg))


# ---------------------------------------------------------------- building --

func _signature() -> String:
	var sig := "%d|%s|%s|%s|%s|%d|%s|%s|" % [page, str(over_game), settings_tab, rebinding, editing, sel, status_line, str(DisplayPrefs.fullscreen())]
	for r in _rows():
		sig += "%s:%s:%s:%s:%s," % [r.id, r.label, r.get("note", ""), str(r.enabled), r.get("tag", "")]
	if page == Page.TITLE:
		for s in Saves.list():
			sig += str(s)
	if page == Page.CONTROLS:
		for row in KeyBinds.ACTIONS:
			sig += KeyBinds.label_for(String(row.id)) + str(KeyBinds.conflicts_for(String(row.id)))
	return sig


func refresh() -> void:
	var s := _signature()
	if s == _sig:
		return
	_sig = s
	var focus := editing
	reset_screen()
	_fields_ui.clear()
	_dlg_sc = null
	_dlg_list = null
	match page:
		Page.TITLE: _build_title()
		Page.CONTROLS: _build_settings()
		_: _build_dialog()
	# A rebuild must not take the caret out of the field being typed in.
	if not focus.is_empty() and _fields_ui.has(focus):
		(_fields_ui[focus] as LineEdit).grab_focus()
		(_fields_ui[focus] as LineEdit).caret_column = String(fields[focus]).length()


func _is_sel(r: Dictionary) -> bool:
	var enabled := _enabled_rows()
	return not enabled.is_empty() and sel < enabled.size() and enabled[sel] == r


## One menu row: its label in the display face, a mono tag on the right, the
## note under it, and the selected look when the keyboard is on it.
func _menu_row(r: Dictionary, big := false) -> Button:
	var label_style := "PanelTitle" if big else "MenuItem"
	var enabled := bool(r.enabled)
	var top := Ui.hbox(14, [Ui.expand(Ui.label(String(r.label), label_style, Ui.TEXT_HIGH if enabled else Ui.TEXT_OFF))])
	if r.has("tag"):
		var tc: Color = r.get("tag_color", Ui.ACCENT_HI if _is_sel(r) else Ui.TEXT_DIM)
		top.add_child(Ui.label(String(r.tag), "Mono", tc))
		(top.get_child(1) as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var col := Ui.vbox(5, [top])
	var note := String(r.get("note", ""))
	if not note.is_empty():
		col.add_child(Ui.label(note, "Body14" if big else "Small", Ui.TEXT_BODY if big and enabled else Color(1, 1, 1, 0.35 if enabled else 0.22)))
	# The face covers the whole button, so it carries the row's padding itself.
	var b := Ui.face_button("MenuRowOn" if _is_sel(r) else "MenuRow",
		Ui.pad(col, 20 if big else 18, 16 if big else 14), func() -> void: _press(r))
	b.disabled = not enabled
	b.mouse_entered.connect(func() -> void:
		var en := _enabled_rows()
		var i := en.find(r)
		if i >= 0 and i != sel:
			sel = i)
	reg_row("%s:%d:%s" % [r.id, int(r.arg), String(r.get("action", ""))], b)
	return b


## The front door: the wordmark, the menu column and the save slots.
func _build_title() -> void:
	var bg := TextureRect.new()
	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color("#161b15"))
	g.set_color(1, Color("#07080a"))
	grad.gradient = g
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(0, 1)
	bg.texture = grad
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var tag := Ui.hbox(16, [Ui.rect(Ui.ACCENT, 120, 2), Ui.label("A town, a pipe, and whatever you can carry", "Body", Ui.TEXT_BODY)])
	(tag.get_child(0) as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(tag.get_child(1) as Label).add_theme_font_size_override("font_size", 18)
	var hero := Ui.vbox(14, [Ui.label("Deadline", "Hero"), tag])

	var rows := _rows()
	var col := Ui.vbox(10)
	var smalls := Ui.hbox(10)
	for r in rows:
		if r.get("small", false):
			var b := _menu_row(r)
			Ui.expand(b)
			if String(r.id) == "quit":
				b.size_flags_horizontal = Control.SIZE_FILL
				b.custom_minimum_size.x = 150
			smalls.add_child(b)
		else:
			col.add_child(_menu_row(r, true))
	col.add_child(smalls)
	col.custom_minimum_size.x = 560

	var slots := Ui.vbox(10)
	var by_slot := {}
	for s in Saves.list():
		by_slot[int(s.slot)] = s
	var newest := int(Saves.latest().get("slot", -1))
	for n in range(Saves.MAX_SLOTS):
		slots.add_child(_slot_row(n, by_slot.get(n, {}), n == newest))
	var panel := Ui.boxed(Ui.box(Color(Ui.BASE, 0.92), Ui.LINE, 1, 3), Ui.vbox(0, [
		Ui.panel("PanelHead", Ui.hbox(12, [Ui.expand(Ui.label("Save slots", "Caps")),
			Ui.label("%d slots  ·  the newest is what CONTINUE opens" % Saves.MAX_SLOTS, "Small")])),
		Ui.expand(Ui.scroller(Ui.pad(slots, 14)), true, true)]))
	panel.custom_minimum_size.x = 720
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var middle := Ui.hbox(Ui.GAP, [Ui.vbox(0, [col]), Ui.spacer(), panel])
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var foot := Ui.hbox(24, [Ui.label("GODOT 4.7.2  ·  SAVES IN user://", "Mono12", Ui.TEXT_OFF),
		Ui.label("Esc does nothing here — nothing quits by accident", "Small", Ui.TEXT_OFF), Ui.spacer(),
		Ui.hint("↑↓", "Move"), Ui.hint("ENTER", "Choose")])
	var page_col := Ui.vbox(0, [hero, Ui.fixed(0, 96), middle, Ui.fixed(0, 32), foot])
	var m := Ui.pad(page_col, 96, 120, 96, 40)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)


func _slot_row(n: int, s: Dictionary, newest: bool) -> Control:
	var empty := s.is_empty()
	var tile := Ui.boxed(Ui.box(Ui.VOID, Ui.LINE_STRONG if newest else Ui.LINE, 1, 0),
		Ui.vbox(2, [Ui.label("SLOT", "Mono12", Ui.TEXT_OFF if empty else Ui.TEXT_DIM), Ui.label(str(n + 1), "Mono22",
			Ui.TEXT_OFF if empty else (Ui.ACCENT_HI if newest else Ui.TEXT_BODY))]))
	tile.custom_minimum_size = Vector2(64, 64)
	for l in tile.get_child(0).get_children():
		(l as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	(tile.get_child(0) as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	if empty:
		var info := Ui.vbox(5, [Ui.label("Empty", "SectionHead", Ui.TEXT_DIM), Ui.label("NEW GAME will write here", "Body14", Ui.TEXT_OFF)])
		var row := Ui.hbox(18, [tile, Ui.expand(info)])
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return Ui.boxed(Ui.box(Ui.BASE, Ui.LINE_SOFT, 1, 2, 18, 14), row)
	var info := Ui.vbox(5, [Ui.label(String(s.get("name", "Game")), "SectionHead", Ui.TEXT_HIGH if newest else Ui.TEXT_BODY),
		Ui.label(Saves.summary_line(s), "Body14", Ui.TEXT_BODY if newest else Ui.TEXT_DIM),
		Ui.label(("Saved " + Saves.when_label(float(s.get("updated", 0.0)))).to_upper(), "Mono12", Ui.TEXT_DIM if newest else Ui.TEXT_OFF)])
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var del_r := {"id": "delete", "label": "DELETE", "arg": n, "note": "", "enabled": true}
	var del := Ui.button("DELETE", "Danger", func() -> void: _press(del_r))
	del.custom_minimum_size = Vector2(0, 34)
	del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reg_row("delete:%d:" % n, del)
	var face := Ui.hbox(18, [tile, Ui.expand(info), del])
	var load_r := {"id": "load", "label": String(s.get("name", "Game")), "arg": n, "note": "", "enabled": true}
	var b := Ui.face_button("MenuRowOn" if newest else "MenuRow", Ui.pad(face, 18, 14), func() -> void: _press(load_r))
	reg_row("load:%d:" % n, b)
	return b


## The pause menu and the small pages: a 720px panel, a title and a line under
## it, the rows, and BACK at the foot.
func _build_dialog() -> void:
	var bg := ColorRect.new()
	bg.color = Ui.SCRIM if over_game else Ui.VOID
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var title := "Deadline"
	var sub := "A town, a pipe, and whatever you can carry"
	match page:
		Page.PAUSE:
			title = "Paused"
			sub = status_line
		Page.LOAD:
			title = "Load game"
			sub = "Click a save to open it"
		Page.NEW_GAME:
			title = "New game"
			sub = "The world is the same town every time; what you do in it is not"
		Page.MULTIPLAYER:
			title = "Multiplayer"
			sub = "Up to four in one town  ·  the host runs the world and keeps the save"
		Page.HOST:
			title = "Host a game"
			sub = "Friends dial your address  ·  click a line to type into it"
		Page.JOIN:
			title = "Join a game"
			sub = "Click a line to type into it  ·  Enter to finish"
	var head := Ui.vbox(8, [Ui.label(title, "ScreenTitle")])
	if not sub.is_empty():
		head.add_child(Ui.label(sub, "Body14", Ui.TEXT_DIM))
	var list := Ui.vbox(10)
	var pinned: Array = []
	var rows := _rows()
	var i := 0
	while i < rows.size():
		var r: Dictionary = rows[i]
		if r.get("pinned", false):
			pinned.append(r)
		elif String(r.id) == "text":
			list.add_child(_text_line(r))
		elif String(r.id) == "load" and i + 1 < rows.size() and String(rows[i + 1].id) == "delete":
			var del_r: Dictionary = rows[i + 1]
			var del := Ui.button("DELETE", "Danger", func() -> void: _press(del_r))
			del.custom_minimum_size.x = 110
			reg_row("delete:%d:" % int(del_r.arg), del)
			list.add_child(Ui.hbox(10, [Ui.expand(_menu_row(r)), del]))
			i += 1
		else:
			list.add_child(_menu_row(r, page == Page.PAUSE and String(r.id) == "resume"))
		i += 1
	var body := Ui.vbox(0, [Ui.boxed(Ui.edge(Color(0, 0, 0, 0), Ui.LINE_SOFT, 0, 0, 0, 1, 28, 22), head)])
	var sc := Ui.scroller(Ui.pad(list, 20))
	body.add_child(sc)
	for r in pinned:
		var back_b := Ui.button(String(r.label), "Secondary", func() -> void: _press(r))
		back_b.custom_minimum_size.y = 44
		reg_row("back:0:", back_b)
		body.add_child(Ui.pad(back_b, 20, 0, 20, 20))
	var dialog := Ui.panel("Dialog", body)
	dialog.custom_minimum_size.x = 720
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(dialog)
	add_child(centre)
	_dlg_sc = sc
	_dlg_list = sc.get_child(0) as Control
	_fit_dialog()


## As tall as its rows, and never taller than the window leaves room for: past
## that the list scrolls and BACK stays where it is. Measured every frame,
## because the rows only know their real height once they have been laid out.
func _fit_dialog() -> void:
	if _dlg_sc == null or not is_instance_valid(_dlg_sc) or not is_instance_valid(_dlg_list):
		return
	var h := minf(_dlg_list.get_combined_minimum_size().y, get_viewport_rect().size.y - 260.0)
	if not is_equal_approx(_dlg_sc.custom_minimum_size.y, h):
		_dlg_sc.custom_minimum_size.y = h


func _text_line(r: Dictionary) -> Control:
	var field := String(r.field)
	var le := LineEdit.new()
	le.text = String(fields.get(field, ""))
	le.secret = field == "password"
	le.placeholder_text = "click to type"
	le.custom_minimum_size = Vector2(300, 36)
	le.text_changed.connect(func(t: String) -> void: fields[field] = t)
	le.focus_entered.connect(func() -> void: editing = field)
	le.focus_exited.connect(func() -> void:
		if editing == field:
			editing = "")
	le.add_theme_color_override("font_color", Ui.XP)
	_fields_ui[field] = le
	var info := Ui.vbox(4, [Ui.label(String(r.label), "Caps14", Ui.TEXT_HIGH)])
	if not String(r.get("note", "")).is_empty():
		info.add_child(Ui.label(String(r.note), "Small"))
	var row := Ui.hbox(16, [Ui.expand(info), le])
	le.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var p := Ui.boxed(Ui.box(Ui.TAB, Ui.ACCENT_HI if editing == field else Ui.LINE, 1, 2, 18, 12), row)
	reg_row("text:0:" + field, p)
	return p


# ---------------------------------------------------------------- settings --

func _build_settings() -> void:
	var col := Chrome.root(self)
	col.add_child(Chrome.title_bar("Settings", null, [Ui.keycap("ESC", "Back")]))
	var body := Chrome.body()
	col.add_child(Chrome.body_margin(body))

	var pages: Array = []
	for t in [["controls", "Controls", str(KeyBinds.ACTIONS.size())], ["sound", "Sound", "ON" if not Sfx.muted() else "OFF"],
			["display", "Display", "FULL" if DisplayPrefs.fullscreen() else "WINDOW"]]:
		var tid := String(t[0])
		pages.append(Chrome.rail_row(String(t[1]), String(t[2]), settings_tab == tid, func() -> void:
			settings_tab = tid
			sel = 0
			rebinding = ""))
	var fixed := Ui.vbox(8, [Ui.label("Fixed keys", "Caps")])
	for k in [["Fire", "Left mouse"], ["Aim", "Right mouse"], ["Pause", "Esc"]]:
		fixed.add_child(Ui.hbox(8, [Ui.expand(Ui.label(String(k[0]), "Small", Ui.TEXT_BODY)), Ui.label(String(k[1]), "Mono")]))
	fixed.add_child(Ui.para("Esc is never rebindable — it is how you get out of a screen you opened by accident.", "Small", Color(1, 1, 1, 0.4)))
	body.add_child(Chrome.rail([Chrome.rail_group("Pages", pages), Ui.spacer(), Ui.panel("Inset", fixed)]))

	var rows := _rows()
	var changed := 0
	for row in KeyBinds.ACTIONS:
		if not KeyBinds.is_default(String(row.id)):
			changed += 1
	var title: String = {"controls": "Controls", "sound": "Sound", "display": "Display"}[settings_tab]
	var note: String = {"controls": "Click a row, then press a key  ·  conflicts are shown, not refused",
		"sound": "Every sound in the game is synthesised at boot", "display": "The window, and how it fills the screen"}[settings_tab]
	var head := Ui.panel("PanelHead", Ui.hbox(14, [Ui.label(title, "SectionHead"), Ui.expand(Ui.label(note, "Small")),
		Ui.label("%d CHANGED" % changed if settings_tab == "controls" else "", "Mono", Ui.TEXT_DIM)]))
	var content: Control
	if settings_tab == "controls":
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 24)
		grid.add_theme_constant_override("v_separation", 16)
		for group in KeyBinds.GROUPS:
			var g := Ui.vbox(6, [Ui.label(group, "Caps")])
			for r in rows:
				if String(r.id) == "bind" and String(r.group) == group:
					g.add_child(_bind_row(r))
			g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(g)
		content = grid
	else:
		var list := Ui.vbox(10)
		for r in rows:
			if not r.get("pinned", false):
				list.add_child(_menu_row(r))
		content = list
	var foot := Ui.hbox(12)
	for r in rows:
		if String(r.id) == "reset":
			var b := Ui.button("Reset to defaults", "Secondary", func() -> void: _press(r))
			b.custom_minimum_size.y = 44
			reg_row("reset:0:", b)
			foot.add_child(b)
		elif r.get("pinned", false):
			var b := Ui.button("Back", "Primary", func() -> void: _press(r))
			b.add_theme_font_size_override("font_size", 16)
			b.custom_minimum_size = Vector2(120, 44)
			reg_row("back:0:", b)
			foot.add_child(b)
	foot.add_child(Ui.spacer())
	if settings_tab == "controls":
		foot.add_child(Ui.label("Two keys on one action is your choice to make — the row says so in coral", "Small", Ui.TEXT_OFF))
		(foot.get_child(foot.get_child_count() - 1) as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var main_panel := Ui.panel("Pane", Ui.vbox(0, [head, Ui.expand(Ui.scroller(Ui.pad(content, 16)), true, true),
		Ui.boxed(Ui.edge(Color(0, 0, 0, 0), Ui.LINE_SOFT, 0, 1, 0, 0, 16, 16), foot)]))
	Ui.expand(main_panel, true, true)
	body.add_child(main_panel)


## One binding: the action, the key in mono on the right, and the state —
## waiting for a key, clashing with another action, or changed from default.
func _bind_row(r: Dictionary) -> Button:
	var id := String(r.action)
	var waiting := rebinding == id
	var clash := KeyBinds.conflicts_for(id)
	var key := "press a key…" if waiting else KeyBinds.label_for(id)
	var kc := Ui.WAIT if waiting else (Ui.SHORT if not clash.is_empty() else Ui.XP)
	var right := Ui.vbox(0, [Ui.label(key, "Mono", kc)])
	(right.get_child(0) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if not clash.is_empty() and not waiting:
		var names := PackedStringArray()
		for c in clash:
			for a in KeyBinds.ACTIONS:
				if String(a.id) == c:
					names.append(String(a.name))
		var l := Ui.label("also " + ", ".join(names), "Mono12", Color(Ui.SHORT, 0.7))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(l)
	elif not KeyBinds.is_default(id) and not waiting:
		var l := Ui.label("changed", "Mono12", Color(1, 1, 1, 0.25))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(l)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_l := Ui.label(String(r.label), "Row14", Ui.TEXT_HIGH if waiting else Ui.TEXT_BODY)
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := Ui.hbox(12, [Ui.expand(name_l), right])
	var b := Ui.face_button("MenuRow", Ui.pad(row, 14, 6, 14, 6), func() -> void: _press(r))
	b.custom_minimum_size.y = 38
	var edge := Ui.ACCENT_HI if waiting else (Color("#7a3f36") if not clash.is_empty() else (Ui.ACCENT if _is_sel(r) else Ui.LINE))
	var fill := Ui.LINE_SOFT if waiting else Ui.TAB
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var hot: bool = st != "normal" and not waiting
		b.add_theme_stylebox_override(st, Ui.box(Ui.HOVER if hot else fill,
			(Ui.LINE_STRONG if clash.is_empty() and not _is_sel(r) else edge) if hot else edge, 2 if _is_sel(r) or waiting else 1, 2))
	reg_row("bind:0:" + id, b)
	return b
