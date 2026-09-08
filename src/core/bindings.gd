extends Node
## Registers the default input actions at boot. Rebinding (Phase 4) will lay
## the player's choices from user:// over these. Everything the sim reads
## goes through Intent, so these names are the only thing input code knows.

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
	"light": [KEY_T],
	"slot1": [KEY_1], "slot2": [KEY_2], "slot3": [KEY_3],
	"slot4": [KEY_4], "slot5": [KEY_5], "slot6": [KEY_6],
	"inventory": [KEY_TAB],
	"crafting": [KEY_C],
	"build": [KEY_B],
	"map": [KEY_M],
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
