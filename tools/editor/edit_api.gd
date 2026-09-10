class_name EditApi
extends RefCounted
## The content editor's request handling, kept apart from the socket so the
## tests can drive it headless. `tools/edit_server.gd` owns the socket and
## hands each complete request to `handle`.
##
## What it enforces is why the tool exists: a save is refused unless the file
## decodes cleanly, the field list is unchanged, every `ref` resolves, and no
## other table is left pointing at something that is gone — a recipe that
## makes a weapon nobody defined, a cost in a resource that does not exist, a
## loot roll for an item that was deleted. Nothing but `DataTable.encode`
## ever writes the file.
##
## A table with a file in `data/` is editable. The rest are served read-only
## from the `config.gd` literal until they migrate, so the editor can browse
## and cross-reference all of it now.

## CATALOG is the one table the game never reads: the owner's view of every
## item — category, subcategory, planned or in game — that used to live in
## Notion's Items table. The rest are `config.gd` tables by their own names.
const TABLES := ["WEAPONS", "RES", "CONSUMABLES", "GEAR", "RECIPES", "STRUCTURES", "LOOT", "CONTAINERS", "ENEMIES", "CROPS", "CATALOG"]
## Read-only context the cross-references and the checks need.
const CONSTS := ["AMMO_IDS", "WEAR", "HARVEST", "FURNISHING", "BENCH_UPGRADE_COST", "BRAIN_DROPS"]
## The tables an item can be defined in, for "is this catalog entry real?".
const ITEM_TABLES := ["WEAPONS", "GEAR", "CONSUMABLES", "RES", "STRUCTURES"]
const ART_DIR := "res://art/items/"
const WEB_DIR := "res://tools/editor/"
const STATIC := {
	"/": ["index.html", "text/html; charset=utf-8"],
	"/app.js": ["app.js", "text/javascript; charset=utf-8"],
	"/app.css": ["app.css", "text/css; charset=utf-8"],
}

## An uploaded image must be a PNG, and a sensible one.
const PNG_MAGIC := [137, 80, 78, 71, 13, 10, 26, 10]
const MAX_ART_BYTES := 4 * 1024 * 1024
const MAX_ART_SIDE := 2048

## Tests point these somewhere under user:// so a run never edits real content.
var data_dir := DataTable.DIR
var art_dir := ART_DIR
## Required on every write. The page gets it inside index.html, which another
## origin cannot read.
var token := ""
## `Host` headers the server answers to. Empty means any, for the tests; the
## server always fills it, which is what stops DNS rebinding.
var allowed_hosts: Array = []
var _config: Dictionary


func _init() -> void:
	_config = (load("res://src/config.gd") as GDScript).get_script_constant_map()


## -> {"status": int, "type": String, "body": PackedByteArray}
## `raw` is the body as bytes, for an image upload; `body` is the same as text.
func handle(method: String, path: String, headers: Dictionary, body: String, raw := PackedByteArray()) -> Dictionary:
	if not allowed_hosts.is_empty() and not String(headers.get("host", "")) in allowed_hosts:
		return _text(403, "Unknown host.")
	path = path.get_slice("?", 0)
	if method == "GET":
		if STATIC.has(path):
			return _static(path)
		if path.begins_with("/art/items/"):
			return _art(path.substr(11))
		if path == "/api/tables":
			return _json(200, tables())
		return _text(404, "Not found.")
	if not method in ["PUT", "POST", "DELETE"]:
		return _text(405, "Method not allowed.")
	if token.is_empty() or String(headers.get("x-edit-token", "")) != token:
		return _text(403, "Missing or wrong edit token. Reload the page.")
	if path.begins_with("/api/art/"):
		return _write_art(method, path.substr(9), raw)
	if method == "DELETE":
		return _text(405, "Method not allowed.")
	var parts := path.split("/", false)
	var route := "%s %s" % [method, parts[1] if parts.size() == 3 and parts[0] == "api" else ""]
	if not route in ["PUT table", "POST validate"]:
		return _text(404, "Not found.")
	var table := parts[2]
	if not table in TABLES or not FileAccess.file_exists(_path(table)):
		return _json(404, {"errors": ["%s is not a data file yet: it still lives in config.gd." % table]})
	var errors := check(table, body)
	if not errors.is_empty():
		return _json(422, {"errors": errors})
	if route == "POST validate":
		return _json(200, {"errors": []})
	var before := FileAccess.get_file_as_string(_path(table))
	var text := DataTable.encode(DataTable.decode(body).doc)
	var f := FileAccess.open(_path(table), FileAccess.WRITE)
	if f == null:
		return _json(500, {"errors": ["Could not write %s." % _path(table)]})
	f.store_string(text)
	f.close()
	return _json(200, {"errors": [], "file": _rel(table), "diff": line_diff(before, text)})


## Every reason `body` may not replace `table`, or nothing.
func check(table: String, body: String) -> Array:
	var got := DataTable.decode(body)
	if not got.errors.is_empty():
		return got.errors
	var current: Dictionary = DataTable.decode(FileAccess.get_file_as_string(_path(table))).doc
	if DataTable.encode({"f": got.doc.get("fields", {})}) != DataTable.encode({"f": current.get("fields", {})}):
		return ["The field list belongs to the code: adding, removing or retyping a field is a change to the systems that read it, so it is made in a commit, not here."]
	return integrity(world({table: got.doc}))


## Every table as the game would see it, with `overrides` standing in for
## their files. -> {"sets": name -> rows or literal, "docs": name -> document}
func world(overrides: Dictionary = {}) -> Dictionary:
	var sets := {}
	var docs := {}
	for name: String in TABLES:
		if overrides.has(name):
			docs[name] = overrides[name]
		elif FileAccess.file_exists(_path(name)):
			docs[name] = DataTable.decode(FileAccess.get_file_as_string(_path(name))).doc
		sets[name] = DataTable.rows(docs[name]) if docs.has(name) else _config.get(name, {})
	for name: String in CONSTS:
		sets[name] = _config.get(name)
	return {"sets": sets, "docs": docs}


## Every cross-table reference in the content, checked both ways: a data
## file's declared refs, and the grammar the literals still carry — recipe
## costs and outputs, structure costs, loot ids, container tables, ammo.
## Deleting or renaming a row something else points at fails here.
func integrity(w: Dictionary) -> Array:
	var s: Dictionary = w.sets
	var errors := []
	for name: String in w.docs:
		for e: String in DataTable.check_refs(w.docs[name], s):
			errors.append("%s %s" % [name, e])
	# A cost is anything that stacks: a resource, or a consumable such as brain
	# matter or a potato. The same rule `crafting_test` holds the game to.
	var payable := func(k: Variant) -> bool: return s.RES.has(k) or s.CONSUMABLES.has(k)
	for r: Variant in _list(s.RECIPES):
		var rid := String(r.get("id", "?"))
		for k: Variant in r.get("cost", {}):
			if not payable.call(k):
				errors.append("RECIPES %s costs '%s', which is not a resource or a consumable" % [rid, k])
		var give: Dictionary = r.get("give", {})
		for kind: Array in [["weapon", "WEAPONS"], ["gear", "GEAR"], ["item", "CONSUMABLES"]]:
			if give.has(kind[0]) and not s[kind[1]].has(give[kind[0]]):
				errors.append("RECIPES %s makes %s '%s', which is not in %s" % [rid, kind[0], give[kind[0]], kind[1]])
		for k: Variant in give.get("res", {}):
			if not s.RES.has(k):
				errors.append("RECIPES %s makes '%s', which is not a resource" % [rid, k])
		if r.has("tool") and not s.WEAPONS.has(r.tool):
			errors.append("RECIPES %s needs tool '%s', which is not a weapon" % [rid, r.tool])
	for sid: Variant in s.STRUCTURES:
		for k: Variant in s.STRUCTURES[sid].get("cost", {}):
			if not payable.call(k):
				errors.append("STRUCTURES %s costs '%s', which is not a resource or a consumable" % [sid, k])
	for table: Variant in s.LOOT:
		for e: Variant in s.LOOT[table]:
			var why := _loot_miss(String(e.get("id", "")), s)
			if not why.is_empty():
				errors.append("LOOT %s rolls '%s', %s" % [table, e.get("id", ""), why])
	for cid: Variant in s.CONTAINERS:
		if not s.LOOT.has(s.CONTAINERS[cid].get("table", "")):
			errors.append("CONTAINERS %s uses loot table '%s', which does not exist" % [cid, s.CONTAINERS[cid].get("table", "")])
	for a: Variant in s.AMMO_IDS:
		if not s.RES.has(a):
			errors.append("AMMO_IDS lists '%s', which is not a resource" % a)
	# A catalog entry that says "in game" has to be somewhere in the game;
	# a planned one has, by definition, nowhere to be yet.
	for r: Variant in w.docs.get("CATALOG", {}).get("rows", []):
		if String(r.get("status", "")) != "in game":
			continue
		var found := false
		for t: String in ITEM_TABLES:
			found = found or s[t].has(r.get("id", ""))
		if not found:
			errors.append("CATALOG %s is marked in game, but no item or structure has that id" % r.get("id", "?"))
	return errors


## What the page loads: every table, editable or not, and the context.
func tables() -> Dictionary:
	var dirty := _git_dirty()
	var out := []
	for name: String in TABLES:
		if FileAccess.file_exists(_path(name)):
			var got := DataTable.decode(FileAccess.get_file_as_string(_path(name)))
			out.append({"name": name, "editable": true, "file": _rel(name), "doc": got.doc,
				"errors": got.errors, "dirty": dirty.has(_rel(name))})
		else:
			out.append({"name": name, "editable": false, "value": _config.get(name)})
	var consts := {}
	for name: String in CONSTS:
		consts[name] = _config.get(name)
	var art := []
	if DirAccess.dir_exists_absolute(art_dir):
		for f: String in DirAccess.get_files_at(art_dir):
			if f.ends_with(".png"):
				art.append(f.get_basename())
	return {"tables": out, "consts": consts, "art": art, "problems": integrity(world())}


## "+added -removed" lines, counted as multisets — close enough to tell a
## one-line edit from a rewrite without shipping a diff algorithm.
static func line_diff(before: String, after: String) -> Dictionary:
	var count := {}
	for l: String in before.split("\n"):
		count[l] = int(count.get(l, 0)) + 1
	var added := 0
	for l: String in after.split("\n"):
		if int(count.get(l, 0)) > 0:
			count[l] = int(count[l]) - 1
		else:
			added += 1
	var removed := 0
	for l: Variant in count:
		removed += int(count[l])
	return {"added": added, "removed": removed}


func _loot_miss(id: String, s: Dictionary) -> String:
	for kind: Array in [["weapon:", "WEAPONS"], ["gear:", "GEAR"], ["armor:", "GEAR"], ["item:", "CONSUMABLES"]]:
		if id.begins_with(kind[0]):
			return "" if s[kind[1]].has(id.substr(String(kind[0]).length())) else "which is not in %s" % kind[1]
	if id.begins_with("key:"):
		return ""
	return "" if s.RES.has(id) else "which is not a resource"


func _list(v: Variant) -> Array:
	return v if typeof(v) == TYPE_ARRAY else (v.values() if typeof(v) == TYPE_DICTIONARY else [])


func _git_dirty() -> Array:
	if data_dir != DataTable.DIR:
		return []
	var out := []
	if OS.execute("git", ["status", "--porcelain", "--", "data"], out) != 0 or out.is_empty():
		return []
	var files := []
	for line: String in String(out[0]).split("\n", false):
		files.append(line.substr(3).strip_edges())
	return files


func _path(table: String) -> String:
	return data_dir + table.to_lower() + ".json"


func _rel(table: String) -> String:
	return "data/%s.json" % table.to_lower()


func _static(path: String) -> Dictionary:
	var spec: Array = STATIC[path]
	var text := FileAccess.get_file_as_string(WEB_DIR + String(spec[0]))
	if path == "/":
		text = text.replace("__EDIT_TOKEN__", token)
	return {"status": 200, "type": spec[1], "body": text.to_utf8_buffer()}


## Upload (PUT) or remove (DELETE) `art/items/<id>.png` or `<id>_ground.png`.
## The name must be an item that exists — in a table, or planned in the
## catalog — and the bytes a real PNG of a sane size: the game will draw
## whatever lands in this folder.
func _write_art(method: String, file: String, raw: PackedByteArray) -> Dictionary:
	var m := RegEx.create_from_string("^([A-Za-z0-9_]+)\\.png$").search(file)
	if m == null:
		return _json(404, {"errors": ["Art files are named <item id>.png or <item id>_ground.png."]})
	var id := m.get_string(1).trim_suffix("_ground")
	if not _art_ids().has(id):
		return _json(404, {"errors": ["There is no item called '%s' to give art to." % id]})
	var path := art_dir + file
	var rel := "art/items/" + file
	if method == "DELETE":
		if not FileAccess.file_exists(path):
			return _json(404, {"errors": ["%s does not exist." % rel]})
		DirAccess.remove_absolute(path)
		if FileAccess.file_exists(path + ".import"):
			DirAccess.remove_absolute(path + ".import")
		return _json(200, {"errors": [], "file": rel, "removed": true})
	if method != "PUT":
		return _text(405, "Method not allowed.")
	if raw.size() > MAX_ART_BYTES:
		return _json(413, {"errors": ["That image is over %d MB." % (MAX_ART_BYTES / 1024 / 1024)]})
	if raw.size() < 8 or Array(raw.slice(0, 8)) != PNG_MAGIC:
		return _json(422, {"errors": ["That is not a PNG file."]})
	var img := Image.new()
	if img.load_png_from_buffer(raw) != OK:
		return _json(422, {"errors": ["That PNG could not be read."]})
	if img.get_width() > MAX_ART_SIDE or img.get_height() > MAX_ART_SIDE:
		return _json(422, {"errors": ["That image is %dx%d; keep it to %d px a side." % [img.get_width(), img.get_height(), MAX_ART_SIDE]]})
	DirAccess.make_dir_recursive_absolute(art_dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return _json(500, {"errors": ["Could not write %s." % rel]})
	f.store_buffer(raw)
	f.close()
	return _json(200, {"errors": [], "file": rel, "width": img.get_width(), "height": img.get_height()})


## Every id art may be named after: the items in the game, and the planned
## ones in the catalog, so art can arrive before the item does.
func _art_ids() -> Dictionary:
	var w := world()
	var ids := {}
	for t: String in ["WEAPONS", "GEAR", "CONSUMABLES", "RES"]:
		for k: Variant in w.sets[t]:
			ids[String(k)] = true
	for r: Variant in w.docs.get("CATALOG", {}).get("rows", []):
		ids[String(r.get("id", ""))] = true
	return ids


## An item's art, by file name only: `pistol.png`, never a path.
func _art(file: String) -> Dictionary:
	if RegEx.create_from_string("^[A-Za-z0-9_]+\\.png$").search(file) == null:
		return _text(404, "Not found.")
	var bytes := FileAccess.get_file_as_bytes(art_dir + file)
	if bytes.is_empty():
		return _text(404, "No art yet.")
	return {"status": 200, "type": "image/png", "body": bytes}


func _json(status: int, data: Variant) -> Dictionary:
	return {"status": status, "type": "application/json; charset=utf-8", "body": JSON.stringify(data).to_utf8_buffer()}


func _text(status: int, msg: String) -> Dictionary:
	return {"status": status, "type": "text/plain; charset=utf-8", "body": msg.to_utf8_buffer()}
