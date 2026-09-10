extends "res://tests/test_case.gd"
## The content editor's server logic, driven without a socket. Every write
## goes to a private copy under user://, never to data/ — a test that edited
## the real weapon table would be a very quiet disaster.

const DIR := "user://edit_api_test/"
const ART := "user://edit_api_art/"

var api: EditApi
var original := ""


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	original = FileAccess.get_file_as_string(DataTable.DIR + "weapons.json")
	var f := FileAccess.open(DIR + "weapons.json", FileAccess.WRITE)
	f.store_string(original)
	f.close()
	api = EditApi.new()
	api.data_dir = DIR
	api.art_dir = ART
	api.token = "secret"


func after_each() -> void:
	DirAccess.remove_absolute(DIR + "weapons.json")
	if DirAccess.dir_exists_absolute(ART):
		for f in DirAccess.get_files_at(ART):
			DirAccess.remove_absolute(ART + f)


func _png(w: int, h: int) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	return img.save_png_to_buffer()


func _art_put(file: String, bytes: PackedByteArray, token := "secret") -> Dictionary:
	return api.handle("PUT", "/api/art/" + file, {"x-edit-token": token}, "", bytes)


func test_an_icon_is_uploaded_served_and_listed() -> void:
	var png := _png(32, 16)
	var res := _art_put("pistol.png", png)
	eq(res.status, 200, str(_body(res)))
	eq(_body(res).width, 32.0)
	eq(FileAccess.get_file_as_bytes(ART + "pistol.png"), png, "the bytes land as sent")
	var got := api.handle("GET", "/art/items/pistol.png?v=123", {}, "")
	eq(got.status, 200)
	eq(got.body, png)
	has(_body(api.handle("GET", "/api/tables", {}, "")).art, "pistol", "and the page learns it exists")
	eq(_art_put("pistol_ground.png", png).status, 200, "a ground sprite is named after the item too")


func test_art_for_a_planned_item_is_allowed_before_the_item_exists() -> void:
	# The catalog is not in the test's data dir, so plant a one-row copy.
	var f := FileAccess.open(DIR + "catalog.json", FileAccess.WRITE)
	f.store_string('{"fields": {"name": {"type": "string"}}, "rows": [{"id": "katana", "name": "Katana"}]}')
	f.close()
	eq(_art_put("katana.png", _png(8, 8)).status, 200)
	DirAccess.remove_absolute(DIR + "catalog.json")


func test_art_must_be_a_real_png_for_a_real_item() -> void:
	has(_body(_art_put("nosuch.png", _png(8, 8))).errors, "There is no item called 'nosuch' to give art to.")
	has(_body(_art_put("pistol.png", "not an image at all".to_utf8_buffer())).errors, "That is not a PNG file.")
	eq(_art_put("pistol.png", _png(3000, 4)).status, 422, "nor a 3000 px strip")
	eq(_art_put("pistol.png", _png(8, 8), "guess").status, 403, "and never without the token")
	for bad: String in ["../pistol.png", "pistol.jpg", "pis tol.png", "..%2Fpistol.png"]:
		eq(_art_put(bad, _png(8, 8)).status, 404, bad)
	ok(DirAccess.get_files_at(ART).is_empty(), "nothing was written by any of it")


func test_art_can_be_removed() -> void:
	_art_put("pistol.png", _png(8, 8))
	var res := api.handle("DELETE", "/api/art/pistol.png", {"x-edit-token": "secret"}, "")
	eq(res.status, 200)
	ok(not FileAccess.file_exists(ART + "pistol.png"))
	eq(api.handle("DELETE", "/api/art/pistol.png", {"x-edit-token": "secret"}, "").status, 404, "twice is a 404")
	eq(api.handle("DELETE", "/api/table/WEAPONS", {"x-edit-token": "secret"}, "").status, 405, "a data file is never deleted")


func _doc() -> Dictionary:
	return DataTable.decode(original).doc


func _row(doc: Dictionary, id: String) -> Dictionary:
	for r: Dictionary in doc.rows:
		if r.id == id:
			return r
	return {}


func _put(doc: Dictionary, token := "secret") -> Dictionary:
	return api.handle("PUT", "/api/table/WEAPONS", {"x-edit-token": token}, JSON.stringify(doc))


func _body(res: Dictionary) -> Variant:
	return JSON.parse_string((res.body as PackedByteArray).get_string_from_utf8())


func _on_disk() -> String:
	return FileAccess.get_file_as_string(DIR + "weapons.json")


func test_a_valid_edit_is_saved_canonically_as_a_one_line_change() -> void:
	var doc := _doc()
	_row(doc, "pistol").dmg = 28.5
	var res := _put(doc)
	eq(res.status, 200, str(_body(res)))
	eq(_body(res).diff, {"added": 1.0, "removed": 1.0})
	var text := _on_disk()
	ok(text.contains("\"dmg\": 28.5,"))
	eq(DataTable.encode(DataTable.decode(text).doc), text, "written by the one serializer")
	var changed := 0
	var a := original.split("\n")
	var b := text.split("\n")
	eq(a.size(), b.size())
	for i in a.size():
		if a[i] != b[i]:
			changed += 1
	eq(changed, 1, "one number moved, one line moved")


func test_a_write_without_the_token_is_refused() -> void:
	var doc := _doc()
	_row(doc, "pistol").dmg = 99.0
	eq(_put(doc, "guess").status, 403)
	eq(api.handle("PUT", "/api/table/WEAPONS", {}, JSON.stringify(doc)).status, 403, "or with none at all")
	eq(_on_disk(), original)


func test_an_ammo_that_does_not_exist_is_refused() -> void:
	var doc := _doc()
	_row(doc, "pistol").ammo = "ammoX"
	var res := _put(doc)
	eq(res.status, 422)
	has(_body(res).errors, "WEAPONS pistol.ammo: 'ammoX' is not in AMMO_IDS")
	eq(_on_disk(), original, "nothing is written")


func test_a_value_of_the_wrong_type_is_refused_by_name() -> void:
	var doc := _doc()
	_row(doc, "pistol").mag = 12.5
	has(_body(_put(doc)).errors, "pistol.mag: expected int, got 12.5")


func test_deleting_a_weapon_something_else_names_is_refused() -> void:
	var doc := _doc()
	doc.rows.erase(_row(doc, "pistol"))
	var res := _put(doc)
	eq(res.status, 422)
	has(_body(res).errors, "RECIPES pistol makes weapon 'pistol', which is not in WEAPONS",
		"a recipe would be left making nothing")
	eq(_on_disk(), original)


func test_renaming_a_weapon_is_refused_while_the_old_name_is_used() -> void:
	var doc := _doc()
	_row(doc, "knife").id = "stoneKnife"
	var errors: Array = _body(_put(doc)).errors
	has(errors, "RECIPES knife makes weapon 'knife', which is not in WEAPONS")
	has(errors, "RECIPES cordage needs tool 'knife', which is not a weapon", "and the recipe that needs one to cut with")


func test_the_field_list_cannot_be_changed_from_the_editor() -> void:
	var doc := _doc()
	doc.fields["cleave"] = {"type": "int"}
	var res := _put(doc)
	eq(res.status, 422)
	ok(String(_body(res).errors[0]).begins_with("The field list belongs to the code"))


func test_validate_checks_without_writing() -> void:
	var doc := _doc()
	_row(doc, "pistol").dmg = 30.0
	var res := api.handle("POST", "/api/validate/WEAPONS", {"x-edit-token": "secret"}, JSON.stringify(doc))
	eq(res.status, 200)
	eq(_body(res).errors, [])
	eq(_on_disk(), original)


func test_a_table_still_in_config_cannot_be_written() -> void:
	var res := api.handle("PUT", "/api/table/RECIPES", {"x-edit-token": "secret"}, "{}")
	eq(res.status, 404)
	eq(api.handle("PUT", "/api/table/PLAYER", {"x-edit-token": "secret"}, "{}").status, 404, "nor anything that is not a content table")


func test_every_content_table_is_served_and_the_content_is_consistent() -> void:
	var res := api.handle("GET", "/api/tables", {}, "")
	eq(res.status, 200)
	var j: Dictionary = _body(res)
	var names := []
	for t: Dictionary in j.tables:
		names.append(t.name)
	eq(names, EditApi.TABLES)
	eq(j.tables[0].editable, true, "WEAPONS is a data file")
	eq(j.tables[4].editable, false, "RECIPES has no copy in the test's data dir")
	ok(j.tables[4].doc.rows.size() > 10, "so it is read from data/ and served whole, read-only")
	eq(j.problems, [], "nothing in today's content points at something missing")


func test_only_the_three_page_files_are_served() -> void:
	var page := api.handle("GET", "/", {}, "")
	eq(page.status, 200)
	var html := (page.body as PackedByteArray).get_string_from_utf8()
	ok(html.contains("content=\"secret\""), "the page carries this run's token")
	ok(not html.contains("__EDIT_TOKEN__"))
	eq(api.handle("GET", "/app.js", {}, "").status, 200)
	for path: String in ["/../project.godot", "/tools/editor/edit_api.gd", "/data/weapons.json", "/app.js/../../project.godot",
			"/art/items/../../project.godot", "/art/items/README.md", "/art/items/nothing.png"]:
		eq(api.handle("GET", path, {}, "").status, 404, path)


func test_a_foreign_host_is_refused() -> void:
	api.allowed_hosts = ["127.0.0.1:8765"]
	eq(api.handle("GET", "/", {"host": "evil.example:8765"}, "").status, 403, "DNS rebinding gets nothing")
	eq(api.handle("GET", "/", {}, "").status, 403)
	eq(api.handle("GET", "/", {"host": "127.0.0.1:8765"}, "").status, 200)


func test_line_diff_counts_changed_lines() -> void:
	eq(EditApi.line_diff("a\nb\nc", "a\nB\nc"), {"added": 1, "removed": 1})
	eq(EditApi.line_diff("a\nb", "a\nx\nb"), {"added": 1, "removed": 0})
