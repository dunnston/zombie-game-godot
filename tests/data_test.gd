extends "res://tests/test_case.gd"
## Content tables that live in `data/*.json`. The files are the merge layer
## between two people editing content, so the properties that make git able
## to merge them are asserted here, not hoped for.


func _files() -> Array[String]:
	var out: Array[String] = []
	for name in DirAccess.get_files_at(DataTable.DIR):
		if name.ends_with(".json"):
			out.append(DataTable.DIR + name)
	return out


func _doc(table: String) -> Dictionary:
	return DataTable.decode(FileAccess.get_file_as_string(DataTable.DIR + table + ".json")).doc


## Line numbers of every line that differs, so a failure names the place.
func _changed_lines(a: String, b: String) -> Array:
	var la := a.split("\n")
	var lb := b.split("\n")
	var out := []
	for i in maxi(la.size(), lb.size()):
		if i >= la.size() or i >= lb.size() or la[i] != lb[i]:
			out.append(i + 1)
	return out


func test_every_data_file_decodes_cleanly_and_is_canonical() -> void:
	gt(_files().size(), 0, "there is at least one data file")
	for path in _files():
		var text := FileAccess.get_file_as_string(path)
		var got := DataTable.decode(text)
		eq(got.errors, [], path)
		var diff := _changed_lines(text, DataTable.encode(got.doc))
		eq(diff, [], "%s differs from its canonical form at these lines: write it with DataTable.encode" % path)


func test_a_one_field_edit_is_a_one_line_diff() -> void:
	var text := FileAccess.get_file_as_string(DataTable.DIR + "weapons.json")
	var doc := _doc("weapons")
	for row: Dictionary in doc.rows:
		if row.id == "pistol":
			row.dmg = 28.5
	eq(_changed_lines(text, DataTable.encode(doc)).size(), 1, "one number moved, one line moved")

	# Adding an optional key to one row is one inserted line, not a reflow.
	# Dot syntax on purpose: it makes a StringName key, which a plain sort
	# puts after every String key. (A key that sorts *last* in its row also
	# puts a comma on the line above — that is JSON, not the encoder.)
	for added: Array in [["fists", "dur", 500, "\"dur\": 500,"], ["pipe", "chop_mul", 1.1, "\"chop_mul\": 1.1,"]]:
		doc = _doc("weapons")
		for row: Dictionary in doc.rows:
			if row.id == added[0]:
				if added[1] == "dur":
					row.dur = added[2]
				else:
					row.chop_mul = added[2]
		var before := text.split("\n")
		var after := DataTable.encode(doc).split("\n")
		eq(after.size(), before.size() + 1, added[0])
		var first := _changed_lines(text, DataTable.encode(doc))[0] as int
		eq(after[first - 1].strip_edges(), added[3], "the new key lands in sorted position")
		eq(after.slice(0, first - 1), before.slice(0, first - 1), "everything before it is untouched")
		eq(after.slice(first), before.slice(first - 1), "and so is everything after it")


func test_numbers_come_back_as_the_type_the_field_declares() -> void:
	# JSON has one number type and Godot parses every one of them as a float.
	var W := Config.WEAPONS
	eq(typeof(W.pistol.mag), TYPE_INT, "a magazine is a count")
	eq(typeof(W.pistol.dur), TYPE_INT)
	eq(typeof(W.shotgun.pellets), TYPE_INT)
	eq(typeof(W.fists.dmg), TYPE_FLOAT, "9.0 stays a float, so dmg / 2 is still 4.5")
	eq(typeof(W.axe.tool), TYPE_BOOL)
	eq(typeof(W.bow.ammo), TYPE_STRING)


func test_rows_are_sparse_ordered_and_read_only_like_the_literal_was() -> void:
	var W := Config.WEAPONS
	ok(not W.fists.has("dur"), "fists never wear: absence still means never")
	ok(not W.pipe.has("bleed") and not W.machete.has("stagger"), "no weapon was given the other's key")
	var ids := []
	for row: Dictionary in _doc("weapons").rows:
		ids.append(row.id)
	eq(W.keys(), ids, "the table iterates in file order, which the RNG draws against")
	eq(W.keys().slice(0, 3), ["fists", "pipe", "machete"])
	ok(W.is_read_only() and W.pistol.is_read_only(), "a const was read-only all the way down, and so is this")
	for id: String in W:
		eq(W[id].id, id)


func test_design_notes_travel_with_the_data_and_the_game_never_sees_them() -> void:
	var doc := _doc("weapons")
	ok(String(doc.get("notes", "")).contains("Blunt things stagger, edged things bleed, and fists do neither."),
		"the table's reasoning moved with it")
	for id: String in Config.WEAPONS:
		ok(not Config.WEAPONS[id].has("notes"), "%s: notes are for people" % id)

	var text := '{"fields": {"dmg": {"type": "float"}}, "notes": "why", "rows": [{"id": "a", "dmg": 1, "notes": "Cordage: only with a blade"}]}'
	var got := DataTable.decode(text)
	eq(got.errors, [])
	ok(DataTable.encode(got.doc).contains("\"notes\": \"Cordage: only with a blade\""), "row notes survive a rewrite")
	eq(DataTable.rows(got.doc).a, {"id": "a", "dmg": 1.0})


func test_a_typo_a_wrong_type_or_a_duplicate_is_refused() -> void:
	var fields := '"fields": {"dmg": {"type": "float"}, "mag": {"type": "int"}, "tool": {"type": "bool"}}'
	var cases := {
		'"rows": [{"id": "a", "dmgg": 1.0}]': "a.dmgg is not a declared field",
		'"rows": [{"id": "a", "mag": 1.5}]': "a.mag: expected int, got 1.5",
		'"rows": [{"id": "a", "mag": "12"}]': "a.mag: expected int, got \"12\"",
		'"rows": [{"id": "a", "tool": 1}]': "a.tool: expected bool, got 1.0",
		'"rows": [{"id": "a"}, {"id": "a"}]': "id 'a' appears twice",
		'"rows": [{"dmg": 1.0}]': "row 0 has no id",
	}
	for rows: String in cases:
		var got := DataTable.decode("{%s, %s}" % [fields, rows])
		has(got.errors, cases[rows], rows)
	has(DataTable.decode('{"fields": {"id": {"type": "string"}}, "rows": []}').errors,
		"field 'id' is reserved and must not be declared")
	has(DataTable.decode('{"fields": {"x": {"type": "number"}}, "rows": []}').errors,
		"field 'x' needs a type: int, float, bool, string, or map<…> / list<…> of one, or object / list<object>")
	has(DataTable.decode('{"fields": {"x": {"type": "int", "refs": "RES"}}, "rows": []}').errors,
		"field 'x' has an unknown setting 'refs'", "a misspelt setting is refused, not ignored")


func test_each_shape_reaches_the_game_as_its_literal_did() -> void:
	var fields := '"fields": {"n": {"type": "int"}}'
	var rows := '"rows": [{"id": "b", "n": 2}, {"id": "a", "n": 1}]'
	var by_id: Variant = DataTable.rows(DataTable.decode("{%s, %s}" % [fields, rows]).doc)
	eq(by_id, {"b": {"id": "b", "n": 2}, "a": {"id": "a", "n": 1}}, "id -> row, keeping the id")
	eq(by_id.keys(), ["b", "a"], "in file order")
	var bare: Variant = DataTable.rows(DataTable.decode('{%s, %s, "shape": "by_id_bare"}' % [fields, rows]).doc)
	eq(bare, {"b": {"n": 2}, "a": {"n": 1}}, "id -> row without it, as RES was written")
	var list: Variant = DataTable.rows(DataTable.decode('{%s, %s, "shape": "list"}' % [fields, rows]).doc)
	eq(typeof(list), TYPE_ARRAY, "a list, as RECIPES was")
	eq(list[0], {"id": "b", "n": 2})
	var groups := '{"fields": {"entries": {"type": "list<object>", "fields": {"w": {"type": "int"}}}}, "rows": [{"id": "shelf", "entries": [{"w": 3}, {"w": 1}]}], "shape": "groups"}'
	eq(DataTable.rows(DataTable.decode(groups).doc), {"shelf": [{"w": 3}, {"w": 1}]}, "id -> list, as LOOT was")
	has(DataTable.decode('{%s, %s, "shape": "heap"}' % [fields, rows]).errors, "unknown shape 'heap': one of by_id, by_id_bare, list, groups")
	has(DataTable.decode('{%s, %s, "shape": "groups"}' % [fields, rows]).errors, "a groups table needs an 'entries' field of type list<object>")


func test_objects_are_typed_all_the_way_down() -> void:
	var fields := '"fields": {"give": {"type": "object", "fields": {"weapon": {"type": "string", "ref": "WEAPONS"}, "n": {"type": "int"}, "res": {"type": "map<int>"}}}, "entries": {"type": "list<object>", "fields": {"w": {"type": "int"}}}}'
	var got := DataTable.decode('{%s, "rows": [{"id": "a", "give": {"weapon": "pistol", "n": 2.0, "res": {"scrap": 3.0}}, "entries": [{"w": 4}]}]}' % fields)
	eq(got.errors, [])
	var a: Dictionary = DataTable.rows(got.doc).a
	eq(typeof(a.give.n), TYPE_INT, "a count inside an object is still a count")
	eq(typeof(a.give.res.scrap), TYPE_INT, "and inside a map inside an object")
	ok(a.give.is_read_only() and a.entries[0].is_read_only(), "read-only all the way down")
	var bad: Array = DataTable.decode('{%s, "rows": [{"id": "a", "give": {"wepon": "x"}, "entries": [{"w": 4}, {"w": 1.5}]}]}' % fields).errors
	has(bad, "a.give.wepon is not a declared field", "a typo one level down is still a typo")
	has(bad, "a.entries[1].w: expected int, got 1.5", "and an error names the exact place")
	var refs := DataTable.check_refs(DataTable.decode('{%s, "rows": [{"id": "a", "give": {"weapon": "nope"}}]}' % fields).doc, {"WEAPONS": {"pistol": {}}})
	eq(refs, ["a.give.weapon: 'nope' is not in WEAPONS"], "refs are checked inside objects too")
	has(DataTable.decode('{"fields": {"o": {"type": "object"}}, "rows": []}').errors, "field 'o' is an object and needs 'fields'")


func test_one_of_refuses_a_value_outside_the_list() -> void:
	var text := '{"fields": {"status": {"type": "string", "one_of": ["in game", "planned"]}}, "rows": [{"id": "a", "status": "planned"}]}'
	eq(DataTable.decode(text).errors, [])
	has(DataTable.decode(text.replace("\"planned\"}", "\"plannd\"}")).errors, "a.status: 'plannd' is not one of in game, planned",
		"a typo does not quietly become a new status")


func test_maps_and_lists_are_typed_all_the_way_in() -> void:
	var text := '{"fields": {"cost": {"type": "map<int>", "key_ref": "RES"}, "rolls": {"type": "list<int>"}}, "rows": [{"id": "a", "cost": {"wood": 4.0}, "rolls": [1, 2]}]}'
	var got := DataTable.decode(text)
	eq(got.errors, [])
	var a: Dictionary = DataTable.rows(got.doc).a
	eq(typeof(a.cost.wood), TYPE_INT, "a count inside a map is still a count")
	eq(typeof(a.rolls[1]), TYPE_INT)
	has(DataTable.decode(text.replace("4.0", "\"four\"")).errors, "a.cost: expected map<int>, got {\"wood\":\"four\"}")
	has(DataTable.decode(text.replace("[1, 2]", "[1, 2.5]")).errors, "a.rolls: expected list<int>, got [1.0,2.5]")


func test_every_ref_in_every_data_file_resolves() -> void:
	# A ref may name any data file's table — the catalog names CATEGORIES,
	# which the game never reads — or a list const such as AMMO_IDS.
	var sets := {"AMMO_IDS": Config.AMMO_IDS}
	for path in _files():
		sets[path.get_file().get_basename().to_upper()] = DataTable.rows(DataTable.decode(FileAccess.get_file_as_string(path)).doc)
	for path in _files():
		eq(DataTable.check_refs(DataTable.decode(FileAccess.get_file_as_string(path)).doc, sets), [], path)


func test_a_ref_that_does_not_resolve_is_refused() -> void:
	var doc: Dictionary = DataTable.decode('{"fields": {"ammo": {"type": "string", "ref": "AMMO_IDS"}, "cost": {"type": "map<int>", "key_ref": "RES"}}, "rows": [{"id": "gun", "ammo": "ammoX", "cost": {"wood": 1, "unobtanium": 2}}]}').doc
	var sets := {"AMMO_IDS": ["ammoP"], "RES": {"wood": {}}}
	var errors := DataTable.check_refs(doc, sets)
	has(errors, "gun.ammo: 'ammoX' is not in AMMO_IDS")
	has(errors, "gun.cost: 'unobtanium' is not in RES")
	eq(errors.size(), 2, "and wood is fine")
	has(DataTable.check_refs(doc, {"RES": {"wood": {}}}), "field 'ammo' refers to 'AMMO_IDS', which is not a table",
		"a set that is missing is an error, not a pass")


func test_an_int_written_as_a_float_loads_but_is_not_canonical() -> void:
	var text := '{"fields": {"mag": {"type": "int"}}, "rows": [{"id": "a", "mag": 12.0}]}'
	var got := DataTable.decode(text)
	eq(got.errors, [])
	eq(typeof(DataTable.rows(got.doc).a.mag), TYPE_INT)
	ok(DataTable.encode(got.doc).contains("\"mag\": 12\n"), "rewritten as the int it is")


func test_floats_have_one_written_form() -> void:
	eq(DataTable.float_text(9.0), "9.0")
	eq(DataTable.float_text(0.075), "0.075")
	eq(DataTable.float_text(1150.0), "1150.0")
	eq(DataTable.float_text(0.000001), "0.000001", "never an exponent")
