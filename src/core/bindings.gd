class_name KeyBinds
extends Node
## The keyboard. Registers the default actions at boot and then lays the
## player's own choices from `user://binds.json` over them. Everything the sim
## reads goes through Intent, so these action names are the only thing any
## input code knows — which is what makes rebinding a one-file concern.

const KEYS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"sneak": [KEY_CTRL],
	"interact": [KEY_E],
	"reload": [KEY_R],
	"use_heal": [KEY_Q],
	"use_suppress": [KEY_G],
	"use_food": [KEY_F],
	"light": [KEY_T],
	"slot1": [KEY_1], "slot2": [KEY_2], "slot3": [KEY_3],
	"slot4": [KEY_4], "slot5": [KEY_5], "slot6": [KEY_6],
	"inventory": [KEY_TAB],
	"crafting": [KEY_C],
	"character": [KEY_K],
	"build": [KEY_B],
	"map": [KEY_M],
	"dev_menu": [KEY_F1],
	"quick_save": [KEY_F5],
	"quick_load": [KEY_F9],
	"pause": [KEY_ESCAPE],
}
const MOUSE := {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT, "wheel_up": MOUSE_BUTTON_WHEEL_UP, "wheel_down": MOUSE_BUTTON_WHEEL_DOWN}


func _init() -> void:
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for action in MOUSE:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE[action]
		InputMap.action_add_event(action, ev)
	# Then the player's own choices over the top.
	load_binds()

## What the CONTROLS screen lists, in the order it lists them. A key that is
## not here cannot be rebound — the mouse buttons and Escape are fixed, because
## a player who rebinds their way out of the pause menu has no way back.
const GROUPS := ["Move", "Fight", "Use", "Screens"]
const ACTIONS := [
	{"id": "move_up", "name": "Forward", "group": "Move"},
	{"id": "move_down", "name": "Back", "group": "Move"},
	{"id": "move_left", "name": "Left", "group": "Move"},
	{"id": "move_right", "name": "Right", "group": "Move"},
	{"id": "sprint", "name": "Sprint", "group": "Move"},
	{"id": "sneak", "name": "Sneak", "group": "Move"},
	{"id": "reload", "name": "Reload", "group": "Fight"},
	{"id": "slot1", "name": "Slot 1", "group": "Fight"},
	{"id": "slot2", "name": "Slot 2", "group": "Fight"},
	{"id": "slot3", "name": "Slot 3", "group": "Fight"},
	{"id": "slot4", "name": "Slot 4", "group": "Fight"},
	{"id": "slot5", "name": "Slot 5", "group": "Fight"},
	{"id": "slot6", "name": "Slot 6", "group": "Fight"},
	{"id": "interact", "name": "Use / search", "group": "Use"},
	{"id": "use_heal", "name": "Heal", "group": "Use"},
	{"id": "use_suppress", "name": "Suppress mutation", "group": "Use"},
	{"id": "use_food", "name": "Eat or drink", "group": "Use"},
	{"id": "light", "name": "Torch", "group": "Use"},
	{"id": "inventory", "name": "Pack", "group": "Screens"},
	{"id": "crafting", "name": "Crafting", "group": "Screens"},
	{"id": "character", "name": "Character", "group": "Screens"},
	{"id": "build", "name": "Build mode", "group": "Screens"},
	{"id": "map", "name": "Map", "group": "Screens"},
	{"id": "quick_save", "name": "Quick save", "group": "Screens"},
	{"id": "quick_load", "name": "Quick load", "group": "Screens"},
]

## Never rebindable. Escape is how you get out of everything, including a
## screen you opened by accident with a key you have just reassigned.
const RESERVED := [KEY_ESCAPE]

## Where the binds are written. A `static var` rather than a `const` for one
## reason: `user://` is shared with the real game, so a headless run that reset
## the bindings would erase the controls of whoever is sitting at this machine.
## The tests point this somewhere else for the duration.
static var STORE := "user://binds.json"

## action id -> Array of physical keycodes. Empty means "the default".
##
## Static because there is exactly one keyboard: the autoload registers the
## defaults at boot and the menu rebinds them, and both are talking about the
## same hardware. It also means the headless tests can reach this without an
## autoload, which a `-s` script run does not have.
static var custom := {}


## What is actually bound to an action now.
static func codes_for(id: String) -> Array:
	if custom.has(id):
		return custom[id]
	return KEYS.get(id, [])


## Rebinds an action to a single key, replacing whatever it had. Conflicts are
## reported, never refused: two things on one key is a choice the player is
## allowed to make and be told about.
static func rebind(id: String, code: int) -> bool:
	if not KEYS.has(id) or code in RESERVED:
		return false
	custom[id] = [code]
	_apply(id)
	save()
	return true


## Every other action already using this key.
static func conflicts_for(id: String) -> Array[String]:
	var mine := codes_for(id)
	var out: Array[String] = []
	if mine.is_empty():
		return out
	for row in ACTIONS:
		var other := String(row.id)
		if other == id:
			continue
		for c in codes_for(other):
			if c in mine:
				out.append(other)
				break
	return out


static func is_default(id: String) -> bool:
	return not custom.has(id)


static func reset_all() -> void:
	custom.clear()
	for id in KEYS:
		_apply(id)
	save()


## Rewrites one action's events in the InputMap from `codes_for`.
static func _apply(id: String) -> void:
	if not InputMap.has_action(id):
		InputMap.add_action(id)
	InputMap.action_erase_events(id)
	for k in codes_for(id):
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(id, ev)


static func save() -> bool:
	var f := FileAccess.open(STORE, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(custom))
	f.close()
	return true


## Bindings are per machine, not per save: they belong to the keyboard in
## front of you, not to the world you are playing.
static func load_binds() -> void:
	custom.clear()
	if not FileAccess.file_exists(STORE):
		return
	var f := FileAccess.open(STORE, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	for id in data:
		if not KEYS.has(id):
			continue                 # an action that no longer exists
		var codes: Array = []
		for c in data[id]:
			var k := int(c)
			if k not in RESERVED:
				codes.append(k)
		if not codes.is_empty():
			custom[id] = codes
	for id in KEYS:
		_apply(id)


## "W", "Space", "Left Shift" — what the row shows and what a prompt says.
static func key_label(code: int) -> String:
	match code:
		KEY_SHIFT: return "Shift"
		KEY_CTRL: return "Ctrl"
		KEY_ALT: return "Alt"
		KEY_SPACE: return "Space"
		KEY_TAB: return "Tab"
		KEY_ESCAPE: return "Esc"
		KEY_ENTER: return "Enter"
		KEY_UP: return "Up"
		KEY_DOWN: return "Down"
		KEY_LEFT: return "Left"
		KEY_RIGHT: return "Right"
	var s := OS.get_keycode_string(code)
	return s if not s.is_empty() else "?"


static func label_for(id: String) -> String:
	var parts: Array[String] = []
	for c in codes_for(id):
		parts.append(key_label(c))
	return " / ".join(parts) if not parts.is_empty() else "—"


## The first key bound to an action, for an on-screen hint. Every prompt is
## built from this rather than from a hardcoded letter, so rebinding actually
## changes what the game tells you to press.
static func primary_label(id: String) -> String:
	var codes := codes_for(id)
	return key_label(codes[0]) if not codes.is_empty() else "—"
