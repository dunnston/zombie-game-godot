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

# edges — true for exactly one simulation step
var interact := false
var reload := false


func clear_edges() -> void:
	interact = false
	reload = false
