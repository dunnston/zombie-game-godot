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

## Every one-step boolean edge, named once. The wire enumerates these in three
## places — packing, merging a late packet, merging a fresh one — and it used
## to do it by hand: adding `suppress` for the Mutation dose meant a guest's G
## press was packed, sent, and then quietly dropped by both merges, so brain
## matter worked in solo and did nothing in co-op (Codex review, PR #20).
## Anything added here is carried by all of them.
const EDGES := ["fire_pressed", "reload", "interact", "use", "suppress", "eat", "light", "dash"]

# edges — true for exactly one simulation step
var fire_pressed := false    # a fresh click: an empty gun reloads on this, not on the hold
var interact := false
var reload := false
var use := false             # Q: use whatever healing is to hand
var suppress := false        # G: take whatever brain matter is to hand
var eat := false             # F: eat or drink whatever would do something
var light := false           # T: strike or douse the off-hand light
var dash := false            # Space: a short burst with i-frames in it
var slot := -1               # 0-5 selects a hotbar slot; -1 means no change
var build_action := ""       # "place" / "repair" / "repair_all" / "demolish"
var build_type := ""         # which structure, for "place"
var build_tile := Vector2i.ZERO
var wheel := 0               # +1 / -1 cycles the hotbar


func clear_edges() -> void:
	for e in EDGES:
		set(e, false)
	slot = -1
	wheel = 0
	build_action = ""
	build_type = ""
