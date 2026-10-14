extends "res://tests/test_case.gd"
## The layout editor (2026-10-14, `LayoutScene`, `LayoutProp`): a scene
## filled from a row gives the row back, a dragged piece snaps to whole
## tiles and quarter turns, a piece on the grass is a yard piece, and the
## export writes what the game then stamps.

const T = Config.T


func _scene(id := "") -> LayoutScene:
	var s := LayoutScene.new()
	s.layout_id = id
	tree.root.add_child(s)
	return s


func _done(s: LayoutScene) -> void:
	tree.root.remove_child(s)
	s.free()


func _things(row: Dictionary) -> Array:
	var out := []
	for t in row.things:
		var d: Dictionary = t.duplicate()
		d.erase("solid")
		# Canonical text, so the order keys were added in does not matter.
		out.append(DataTable.encode(d))
	out.sort()
	return out


func test_a_scene_filled_from_a_row_gives_the_row_back() -> void:
	for id in Config.LAYOUTS:
		var row: Dictionary = Config.LAYOUTS[id]
		var s := _scene(id)
		s.fill(row)
		eq(s.props().size(), row.things.size(), id)
		var back := s.row()
		eq(back.map, row.map, "%s: the map round-trips" % id)
		eq(back.use, row.use)
		eq(back.floor, row.floor)
		eq(_things(back), _things(row), "%s: every thing round-trips" % id)
		eq(Array(Layout.problems(back)), [], id)
		_done(s)


func test_a_piece_snaps_to_whole_tiles_and_quarter_turns() -> void:
	var s := _scene("snap")
	var p := LayoutProp.new()
	p.kind = "sofa"
	s.add_child(p)
	eq(p.size(), Vector2i(2, 1), "a sofa is two tiles across")
	p.position = Vector3(3.3, 0.7, 2.6)
	p.rotation = Vector3(0.0, 1.4, 0.0)
	p.snap()
	eq(p.facing(), 1, "1.4 rad is nearest a quarter turn east")
	near(p.rotation.y, PI / 2.0)
	eq(p.position.y, 0.0, "on the floor")
	eq(p.footprint(), Vector2i(1, 2), "facing east it is one across and two deep")
	eq(p.tile(), Vector2i(3, 2))
	near(p.position.x, 3.5)
	near(p.position.z, 3.0)
	# Placed by tile, it reads back the same tile.
	p.place(Vector2i(5, 7), 2)
	eq(p.tile(), Vector2i(5, 7))
	eq(p.facing(), 2)
	var fridge := LayoutProp.new()
	fridge.kind = "fridge"
	s.add_child(fridge)
	ok(fridge.is_container())
	eq(fridge.entry(Vector2i.ZERO, false).container, "fridge")
	var pic := LayoutProp.new()
	pic.kind = "painting"
	s.add_child(pic)
	ok(pic.is_hung())
	eq(pic.entry(Vector2i.ZERO, false).kind, "wall")
	var rug := LayoutProp.new()
	rug.kind = "rug"
	s.add_child(rug)
	eq(rug.entry(Vector2i.ZERO, false).get("solid", true), false, "a rug is not solid")
	_done(s)


func test_a_piece_on_the_grass_is_a_yard_piece_and_the_map_grows_to_it() -> void:
	var s := _scene("yard")
	var g := s.tiles()
	for y in range(5):
		for x in range(7):
			var edge := x == 0 or y == 0 or x == 6 or y == 4
			g.set_cell_item(Vector3i(x, 0, y), 0 if edge else 1)
	g.set_cell_item(Vector3i(3, 0, 4), 2)
	var swing := LayoutProp.new()
	swing.kind = "swing_set"
	s.add_child(swing)
	swing.place(Vector2i(1, 7), 0)
	var row := s.row()
	eq(row.map.size(), 8, "the map grew south to take the swing set in")
	eq(row.map[0], "#######")
	eq(row.map[4], "###+###")
	eq(row.map[7], "       ")
	eq(row.things.size(), 1)
	eq(row.things[0].kind, "yard")
	eq(row.things[0].y, 7)
	eq(Array(Layout.problems(row)), [])
	_done(s)


func test_export_writes_the_row_the_game_stamps() -> void:
	var s := _scene("test_export")
	var g := s.tiles()
	for y in range(5):
		for x in range(7):
			var edge := x == 0 or y == 0 or x == 6 or y == 4
			g.set_cell_item(Vector3i(x, 0, y), 0 if edge else 1)
	g.set_cell_item(Vector3i(3, 0, 4), 2)
	var bed := LayoutProp.new()
	bed.kind = "bed_single"
	s.add_child(bed)
	bed.place(Vector2i(1, 1), 0)
	var was := FileAccess.get_file_as_string(LayoutFile.PATH)
	s.export_row()
	ok(s.report.contains("playable"), s.report)
	ok(Config.LAYOUTS.has("test_export"), "the game sees the row at once")
	var world := World.new(3, "lab:test_export")
	var beds := world.props.filter(func(p: Dictionary) -> bool: return p.get("what", "") == "bed_single")
	eq(beds.size(), 1)
	eq(Vector2i(int(beds[0].tx), int(beds[0].ty)) - world.buildings[0].rect.position, Vector2i(1, 1))
	# Put the table back as it was.
	var f := FileAccess.open(LayoutFile.PATH, FileAccess.WRITE)
	f.store_string(was)
	f.close()
	LayoutFile.refresh()
	ok(not Config.LAYOUTS.has("test_export"))
	_done(s)


## The scenes on disk (`scenes/layouts/<id>.tscn`, made by
## `tools/make_layout_palette`) open as layout scenes and describe the
## rows they were made from; every palette scene is a piece the game knows.
func test_the_saved_scenes_open_and_match_their_rows() -> void:
	for id in Config.LAYOUTS:
		var path := "res://scenes/layouts/%s.tscn" % id
		ok(ResourceLoader.exists(path), path)
		if not ResourceLoader.exists(path):
			continue
		var s := (load(path) as PackedScene).instantiate() as LayoutScene
		ok(s != null, "%s is a LayoutScene" % path)
		tree.root.add_child(s)
		eq(s.layout_id, id)
		var back := s.row()
		eq(back.map, Config.LAYOUTS[id].map, "%s: the saved scene paints the row's map" % id)
		eq(_things(back), _things(Config.LAYOUTS[id]), "%s: and stands its things" % id)
		_done(s)
	var template := (load("res://scenes/layouts/_template.tscn") as PackedScene).instantiate() as LayoutScene
	ok(template != null, "the template is a LayoutScene")
	ok(template.get_node_or_null("Tiles") is GridMap, "with tiles to paint")
	template.free()
	var n := 0
	for place in DirAccess.get_directories_at("res://scenes/layouts/palette"):
		for f in DirAccess.get_files_at("res://scenes/layouts/palette/" + place):
			if not f.ends_with(".tscn"):
				continue
			var p := (load("res://scenes/layouts/palette/%s/%s" % [place, f]) as PackedScene).instantiate() as LayoutProp
			ok(p != null and p.kind == f.get_basename(), "palette/%s/%s is a %s" % [place, f, f.get_basename()])
			ok(p.kind in LayoutProp.kinds(), "%s is a kind the game stands" % p.kind)
			p.free()
			n += 1
	eq(n, LayoutProp.kinds().size(), "one palette scene per kind")
