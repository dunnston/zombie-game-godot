extends "res://tests/test_case.gd"
## The content editor's server logic, driven without a socket. Every write
## goes to a private copy under user://, never to data/ — a test that edited
## the real weapon table would be a very quiet disaster.

const DIR := "user://edit_api_test/"

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
	api.token = "secret"


func after_each() -> void:
	DirAccess.remove_absolute(DIR + "weapons.json")


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
	eq(j.tables[4].editable, false, "RECIPES is still a literal")
	ok(j.tables[4].value.size() > 10, "and is served whole, read-only")
	eq(j.problems, [], "nothing in today's content points at something missing")


func test_only_the_three_page_files_are_served() -> void:
	var page := api.handle("GET", "/", {}, "")
	eq(page.status, 200)
	var html := (page.body as PackedByteArray).get_string_from_utf8()
	ok(html.contains("content=\"secret\""), "the page carries this run's token")
	ok(not html.contains("__EDIT_TOKEN__"))
	eq(api.handle("GET", "/app.js", {}, "").status, 200)
	for path: String in ["/../project.godot", "/tools/editor/edit_api.gd", "/data/weapons.json", "/app.js/../../project.godot"]:
		eq(api.handle("GET", path, {}, "").status, 404, path)


func test_a_foreign_host_is_refused() -> void:
	api.allowed_hosts = ["127.0.0.1:8765"]
	eq(api.handle("GET", "/", {"host": "evil.example:8765"}, "").status, 403, "DNS rebinding gets nothing")
	eq(api.handle("GET", "/", {}, "").status, 403)
	eq(api.handle("GET", "/", {"host": "127.0.0.1:8765"}, "").status, 200)


func test_line_diff_counts_changed_lines() -> void:
	eq(EditApi.line_diff("a\nb\nc", "a\nB\nc"), {"added": 1, "removed": 1})
	eq(EditApi.line_diff("a\nb", "a\nx\nb"), {"added": 1, "removed": 0})
