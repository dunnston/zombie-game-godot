class_name DisplayPrefs
extends RefCounted
## Fullscreen or windowed, remembered per machine the way the key bindings
## are: it belongs to the screen in front of you, not to the world you saved.

## A `static var` for the same reason `KeyBinds.STORE` is one: `user://` is
## shared with the real game, and a smoke run must not change this machine.
static var STORE := "user://display.json"


static func fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


static func set_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	var f := FileAccess.open(STORE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"fullscreen": on}))
		f.close()


## Applied once at boot. A missing or unreadable file means the default.
static func apply() -> void:
	if not FileAccess.file_exists(STORE):
		return
	var f := FileAccess.open(STORE, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) == TYPE_DICTIONARY and bool(data.get("fullscreen", false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
