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
	"inventory": [KEY_TAB],
	"crafting": [KEY_C],
	"build": [KEY_B],
	"map": [KEY_M],
	"pause": [KEY_ESCAPE],
}
const MOUSE := {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT}


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
