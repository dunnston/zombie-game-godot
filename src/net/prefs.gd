class_name NetPrefs
extends RefCounted
## What this machine remembers about playing with other people: who it is
## (the identity the host's save keeps a character under), what it is called,
## and the last address it dialled. Per machine, like the key bindings, and
## for the same reason — none of it belongs to any one save.

static var STORE := "user://net.json"


static func load() -> Dictionary:
	var d := {"identity": "", "name": "", "address": "", "password": ""}
	if FileAccess.file_exists(STORE):
		var f := FileAccess.open(STORE, FileAccess.READ)
		if f != null:
			var v = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(v) == TYPE_DICTIONARY:
				for k in d:
					d[k] = String(v.get(k, d[k]))
	if String(d.identity).is_empty():
		d.identity = NetProtocol.random_id()
		save(d)
	return d


static func save(d: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STORE.get_base_dir()))
	var f := FileAccess.open(STORE, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d))
	f.close()
	return true
