class_name Stage
extends Node
## What draws the world. `scenes/main.gd` owns the simulation, the wire, the
## menus and the screens; a Stage owns everything that turns the sim into
## pixels and the one camera that looks at it. Main never learns how: it asks
## the stage to build, to follow the player, where the cursor is in the
## world and where a world point is on screen, and hands it every event.
##
## Two stages exist (2026-10-13, `tasks/3d-conversion.md`): `Stage2D`, the
## game as it always was, and `Stage3D`, the same town standing up.
## `Config.STAGE` says which; `--stage=2d` / `--stage=3d` on the command line
## overrides it, which is how the smoke keeps running the stage its
## checkpoints were written for. The sim, the UI and the wire are the same
## under either, which is the whole point of the seam.
##
## Every method here is the interface. The base does nothing; a stage that
## forgets one gets the base's nothing, which is what `stage_test` is for.

var sim: GameSim
## Whose screen this is. Drawn last, never under a teammate, and the one the
## camera follows.
var local: PlayerSim


## Which stage the game runs: the command line's word, else `Config.STAGE`.
static func pick() -> String:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--stage="):
			return String(a).trim_prefix("--stage=")
	return Config.STAGE


## Everything the world needs drawn, built once from the sim. Called after
## the stage is in the tree. Sets `sim.view_radius` from what it can see.
func build() -> void:
	pass


## The world is a new object (a load, NEW GAME, an instance door): every view
## that cached it rebuilds. The UI half of that lives in main.
func rebuild() -> void:
	pass


## The props changed under a guest, or the smoke planted a treeline: only
## the prop views rebuild, the terrain stays.
func rebuild_props() -> void:
	pass


## One tile of the town changed (a house wall broken open): redrawn where it
## stands rather than rebuilding a hundred thousand cells.
func repaint(_tx: int, _ty: int) -> void:
	pass


## Which player this machine's screen belongs to.
func set_local(p: PlayerSim) -> void:
	local = p


## The build bar draws its ghost through the stage, so the stage has to know
## it. Main hands it over once the screens exist.
func attach_build_bar(_bar: BuildBar) -> void:
	pass


## One sim event, for every view that answers events. Main drains the list
## and calls this for each; the screens get the same event from main.
func on_event(_ev: Dictionary) -> void:
	pass


## Once a frame, before drawing: particles age, lights move, telegraphs run.
func tick(_dt: float) -> void:
	pass


## Once a frame, after `tick`: every view that draws from the sim redraws.
func frame() -> void:
	pass


## The camera lands on `pos` this instant. A load, a respawn, the smoke's
## teleports: anything where a lerp from the old place would be wrong.
func snap(_pos: Vector2) -> void:
	pass


## The camera follows `p` this frame, leading toward the cursor, pulling out
## for a boss's room and framing `boss` when there is one, shaken by `shake`.
func follow(_dt: float, _p: PlayerSim, _boss: EnemySim, _shake: float) -> void:
	pass


## Where the mouse points in the world, in sim pixels. The aim, the build
## ghost and the move-to-cursor heading all come from here.
func cursor_world() -> Vector2:
	return Vector2.ZERO


## Where a world point sits on the canvas: the inverse of `cursor_world`,
## before the window's own stretch (`Viewport.get_final_transform`).
func to_screen(_world: Vector2) -> Vector2:
	return Vector2.ZERO


## Half the screen's diagonal in world pixels: the spawn ring sits beyond it.
func view_radius() -> float:
	return 0.0


## Where the camera wants to be, shared by every stage: the drawn position
## led toward the cursor, pulled out and toward the boss inside an arena.
## Returns `{focus: Vector2, zoom_mul: float}`; a 2D stage reads the multiplier
## as zoom, a 3D one as distance.
func frame_for(p: PlayerSim, cursor: Vector2, boss: EnemySim) -> Dictionary:
	var C := Config.CAMERA
	# The camera follows where the player is *drawn*, not where the last
	# physics step left them — otherwise the world judders under a smooth
	# player instead of the player juddering across a smooth world.
	var at := Util.render_pos(p.prev_pos, p.pos)
	var lead := Vector2(
		clampf((cursor.x - at.x) * C.lead, -C.lead_max, C.lead_max),
		clampf((cursor.y - at.y) * C.lead, -C.lead_max, C.lead_max))
	# A boss's room is a fight you have to see the whole of — a slam whose
	# edge is off screen is not a mechanic (§8.4) — so the camera pulls out
	# while you are in it, and frames the fight rather than you: pulled toward
	# the boss, because with it at the far end of the gym and the camera on
	# you, the top of its ring was under the HUD. It eases back when you leave.
	var focus := at + lead
	var zoom_mul := 1.0
	var ar: Rect2i = sim.world.arena
	if ar.size.x > 0 and Rect2(Vector2(ar.position) * Config.TILE, Vector2(ar.size) * Config.TILE).has_point(at):
		zoom_mul = float(C.arena_zoom)
		if boss != null:
			focus += (boss.pos - at) * float(C.arena_frame)
	return {"focus": focus, "zoom_mul": zoom_mul}
