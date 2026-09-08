class_name Intent
extends RefCounted
## What a player wants this step, as data. The simulation reads only this;
## the keyboard is read in one place (LocalInput) and a remote player's
## intent arriving over a wire drives identical code.

# held
var mx := 0.0
var my := 0.0
var aim := Vector2.ZERO      # world position
var sprint := false
var sneak := false
var fire := false
var interact_held := false   # searching a container is a channel, not a tap

# edges — true for exactly one simulation step
var fire_pressed := false    # a fresh click: an empty gun reloads on this, not on the hold
var interact := false
var reload := false
var use := false             # Q: use whatever healing is to hand
var light := false           # T: strike or douse the off-hand light
var slot := -1               # 0-5 selects a hotbar slot; -1 means no change
var wheel := 0               # +1 / -1 cycles the hotbar


func clear_edges() -> void:
	fire_pressed = false
	interact = false
	reload = false
	use = false
	light = false
	slot = -1
	wheel = 0
