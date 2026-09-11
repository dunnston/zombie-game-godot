class_name LocalInput
## The one place the keyboard and mouse are read for the simulation. Fills
## the local player's Intent once per physics step. Edge inputs use
## is_action_just_pressed, which is per-physics-frame here, so a tap is
## consumed by exactly one simulation step.

## The keys a full screen takes for itself while it is up: they move the
## selection there, so they must not also walk you across the street.
const NAV_KEYS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]


## `ui_capture` is true while a panel owns the mouse. Movement still answers
## the keyboard — you can back away from a horde with your pack open — but
## nothing that aims, fires or reaches into the world does.
##
## `screen_nav` is true while a full screen is up: the arrow keys are its
## selection, so movement comes from the other keys bound to it (WASD by
## default). `typing` is true while a search field has the caret: every
## letter is the field's, so nothing walks, sprints or dashes at all.
static func gather(intent: Intent, node: Node2D, ui_capture := false, screen_nav := false, typing := false) -> void:
	var v := Vector2.ZERO
	if typing:
		v = Vector2.ZERO
	elif screen_nav:
		v = Vector2(_held("move_right") - _held("move_left"), _held("move_down") - _held("move_up")).limit_length(1.0)
	else:
		v = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	intent.mx = v.x
	intent.my = v.y
	intent.sprint = Input.is_action_pressed("sprint") and not typing
	intent.sneak = Input.is_action_pressed("sneak") and not typing
	# Movement, so it answers with a panel open like the keys above: getting
	# out of the way is not something a pack screen should stop.
	if Input.is_action_just_pressed("dash") and not typing:
		intent.dash = true
	if ui_capture:
		intent.fire = false
		intent.interact_held = false
		return
	intent.fire = Input.is_action_pressed("fire")
	intent.interact_held = Input.is_action_pressed("interact")
	intent.aim = node.get_global_mouse_position()
	if Input.is_action_just_pressed("fire"):
		intent.fire_pressed = true
	if Input.is_action_just_pressed("interact"):
		intent.interact = true
	if Input.is_action_just_pressed("reload"):
		intent.reload = true
	if Input.is_action_just_pressed("use_heal"):
		intent.use = true
	if Input.is_action_just_pressed("use_suppress"):
		intent.suppress = true
	if Input.is_action_just_pressed("use_food"):
		intent.eat = true
	if Input.is_action_just_pressed("light"):
		intent.light = true
	for i in range(6):
		if Input.is_action_just_pressed("slot%d" % (i + 1)):
			intent.slot = i
	if Input.is_action_just_pressed("wheel_down"):
		intent.wheel = 1
	elif Input.is_action_just_pressed("wheel_up"):
		intent.wheel = -1


## 1 when any key bound to `action` other than the arrows is held. A binding
## that is only an arrow key walks nowhere while a screen is up, which is the
## price of the arrows being the screen's.
static func _held(action: String) -> float:
	for code in KeyBinds.codes_for(action):
		if int(code) in NAV_KEYS:
			continue
		if Input.is_physical_key_pressed(int(code)):
			return 1.0
	# The smoke run presses actions rather than keys, and a screen being up
	# must not stop that reaching the player.
	return Input.get_action_strength(action) if _only_arrows_or_scripted(action) else 0.0


static func _only_arrows_or_scripted(action: String) -> bool:
	for code in KeyBinds.codes_for(action):
		if Input.is_physical_key_pressed(int(code)):
			return false
	return Input.is_action_pressed(action) and not _arrow_down(action)


static func _arrow_down(action: String) -> bool:
	for code in KeyBinds.codes_for(action):
		if int(code) in NAV_KEYS and Input.is_physical_key_pressed(int(code)):
			return true
	return false
