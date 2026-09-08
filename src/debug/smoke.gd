extends Node
## Smoke-test autoload. Inert unless the game is launched with `-- --smoke`.
##
## In smoke mode it waits for the game to settle, then hands control to the
## current scene's `smoke_run(smoke)` (or takes one "boot" checkpoint if the
## scene has none). The scene drives the real input path with `hold`/`tap`,
## calls `checkpoint(name)` to write a viewport PNG plus a JSON dump of its
## `smoke_state()`, and `fail(msg)` for anything wrong. Output goes to
## `--smoke-out=<dir>` (default user://smoke). Exit code 1 on any failure.
##
## This is the Godot equivalent of the prototype's browser smoke suite:
## drive the real game through its real input path, then look at the result.

var enabled := false
var out_dir := "user://smoke"
var failures := 0

var _checkpoints := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--smoke":
			enabled = true
		elif a.begins_with("--smoke-out="):
			out_dir = a.trim_prefix("--smoke-out=")
	if not enabled:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	_run.call_deferred()


func _run() -> void:
	await frames(10)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("smoke_run"):
		await scene.smoke_run(self)
	else:
		# A scene whose script failed to compile has no methods at all, and
		# that must not pass as "nothing to check".
		fail("the main scene has no smoke_run (did its script fail to compile?)")
		await checkpoint("boot")
	_finish()


## Scripted input: press an action for `n` process frames.
func hold(action: String, n: int) -> void:
	Input.action_press(action)
	await frames(n)
	Input.action_release(action)


func tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame


func frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func fail(msg: String) -> void:
	failures += 1
	printerr("SMOKE FAIL " + msg)


func checkpoint(name: String) -> void:
	await RenderingServer.frame_post_draw
	var idx := "%02d_%s" % [_checkpoints, name]
	_checkpoints += 1
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out_dir.path_join(idx + ".png"))
	var state := {}
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("smoke_state"):
		state = scene.smoke_state()
	state["_frame"] = Engine.get_process_frames()
	state["_fps"] = Engine.get_frames_per_second()
	var f := FileAccess.open(out_dir.path_join(idx + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(state, "  "))
	f.close()
	print("SMOKE %s png=%s state=%s" % [idx, error_string(err), JSON.stringify(state)])


func _finish() -> void:
	var code := 1 if failures > 0 else 0
	print("SMOKE done checkpoints=%d failures=%d exit=%d" % [_checkpoints, failures, code])
	get_tree().quit(code)
