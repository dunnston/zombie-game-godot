extends SceneTree
## Loads every script under src/ and scenes/ headless and reports the ones
## that fail to parse. The unit tests never load a Control, so a parse error
## in a screen only shows when the game boots (PROJECT.md §8); this is the
## cheap check for a session that cannot run the smoke.
##
##   godot --headless --path . -s tools/parse_check.gd
##
## `scenes/main.gd` always fails here: it names the `Smoke` autoload, and a
## `-s` run has no autoloads. Anything else failing is real.

func _init() -> void:
	var bad := 0
	var n := 0
	for path in _scripts("res://src") + _scripts("res://scenes"):
		n += 1
		var s: Variant = load(path)
		if s == null or not (s as Script).can_instantiate():
			printerr("PARSE FAIL " + path)
			bad += 1
	print("parse check: %d scripts, %d failed" % [n, bad])
	quit(1 if bad > 0 else 0)


func _scripts(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var path := dir.path_join(name)
		if d.current_is_dir():
			out.append_array(_scripts(path))
		elif name.ends_with(".gd"):
			out.append(path)
		name = d.get_next()
	return out
