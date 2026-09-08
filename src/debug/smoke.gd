extends Node
## Smoke-test autoload. Inert unless the game is launched with `-- --smoke`.
##
## In smoke mode it runs a scripted session: waits for the game to settle,
## then at each checkpoint writes a viewport PNG and a JSON snapshot of
## whatever the current scene reports from `smoke_state()`. Output goes to
## `--smoke-out=<dir>` (default user://smoke). Quits with 0 on success.
##
## This is the Godot equivalent of the prototype's browser smoke suite:
## drive the real game through its real input path, then look at the result.

var enabled := false
var out_dir := "user://smoke"
var _checkpoints := 0
var _log: Array[String] = []

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
	await _frames(10)
	await checkpoint("boot")
	_finish(0)

## Scripted input: press an action for `frames` process frames.
func hold(action: String, frames: int) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)

func tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func checkpoint(name: String) -> void:
	await RenderingServer.frame_post_draw
	var idx := "%02d_%s" % [_checkpoints, name]
	_checkpoints += 1
	var img := get_viewport().get_texture().get_image()
	var png := out_dir.path_join(idx + ".png")
	var err := img.save_png(png)
	var state := {}
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("smoke_state"):
		state = scene.smoke_state()
	state["_frame"] = Engine.get_process_frames()
	state["_fps"] = Engine.get_frames_per_second()
	var f := FileAccess.open(out_dir.path_join(idx + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(state, "  "))
	f.close()
	_log.append("%s png=%s state=%s" % [idx, error_string(err), JSON.stringify(state)])
	print("SMOKE " + _log.back())

func _finish(code: int) -> void:
	print("SMOKE done checkpoints=%d exit=%d" % [_checkpoints, code])
	get_tree().quit(code)
