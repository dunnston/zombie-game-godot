class_name LocalInput
## The one place the keyboard and mouse are read for the simulation. Fills
## the local player's Intent once per physics step. Edge inputs use
## is_action_just_pressed, which is per-physics-frame here, so a tap is
## consumed by exactly one simulation step.


static func gather(intent: Intent, node: Node2D) -> void:
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	intent.mx = v.x
	intent.my = v.y
	intent.sprint = Input.is_action_pressed("sprint")
	intent.sneak = Input.is_action_pressed("sneak")
	intent.fire = Input.is_action_pressed("fire")
	intent.aim = node.get_global_mouse_position()
	if Input.is_action_just_pressed("interact"):
		intent.interact = true
	if Input.is_action_just_pressed("reload"):
		intent.reload = true
