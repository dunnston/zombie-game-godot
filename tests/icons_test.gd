extends "res://tests/test_case.gd"
## Items can take real art later with nothing but a file (`art/items/`).
## These hold that seam: no file means the placeholder, a file is found by
## name, the ground sprite is optional, and a misnamed file is caught.

const DIR := "user://icons_test/"

var project_dir := ""


func before_each() -> void:
	project_dir = Items.ART_DIR
	Items.ART_DIR = DIR
	Items.clear_art_cache()
	DirAccess.make_dir_recursive_absolute(DIR)


func after_each() -> void:
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)
	Items.ART_DIR = project_dir
	Items.clear_art_cache()


func _png(name: String, w: int, h: int) -> void:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	img.save_png(DIR + name + ".png")


func test_an_item_with_no_file_is_drawn_as_before() -> void:
	eq(Items.icon_of("pistol"), null)
	eq(Items.icon_of("pistol", "ground"), null)


func test_a_file_named_after_the_item_is_its_icon_everywhere() -> void:
	_png("pistol", 8, 4)
	var t := Items.icon_of("pistol")
	ok(t != null, "found by name")
	eq(t.get_size(), Vector2(8, 4))
	eq(Items.icon_of("pistol", "ground"), t, "the ground falls back to the icon")


func test_a_ground_sprite_changes_the_ground_and_nothing_else() -> void:
	_png("pistol", 8, 8)
	_png("pistol_ground", 16, 4)
	eq(Items.icon_of("pistol", "ground").get_size(), Vector2(16, 4))
	eq(Items.icon_of("pistol").get_size(), Vector2(8, 8), "the pack keeps the icon")


func test_art_keeps_its_shape_inside_a_slot() -> void:
	var tex := ImageTexture.create_from_image(Image.create(20, 10, false, Image.FORMAT_RGBA8))
	eq(Items.art_rect(tex, Rect2(0, 0, 40, 40)), Rect2(0, 10, 40, 20), "wide art is letterboxed, not stretched")


func test_every_file_in_the_art_folder_is_named_after_an_item() -> void:
	# The folder the game really reads. A typo would otherwise ship a picture
	# that no item ever shows. A planned item in the catalog may have art
	# before it exists; the editor allows exactly the same names.
	var planned := {}
	for r: Variant in DataTable.decode(FileAccess.get_file_as_string(DataTable.DIR + "catalog.json")).doc.get("rows", []):
		planned[String(r.get("id", ""))] = true
	for f: String in DirAccess.get_files_at(project_dir):
		if not f.ends_with(".png"):
			continue
		var id := f.get_basename().trim_suffix("_ground")
		ok(Items.has(id) or planned.has(id), "art/items/%s is named after no item" % f)


# -------------------------------------------------------------- structures --
# Buildables are not items, so their menu art has its own folder with the
# same rules: found by name, absent means the colour, a stray name is caught.

func test_a_structure_with_no_file_keeps_its_colour() -> void:
	var was := Structures.ART_DIR
	Structures.ART_DIR = DIR
	Structures.clear_art_cache()
	eq(Structures.icon_of("woodWall"), null)
	var tile := UiSwatch.of_structure("woodWall", Color.RED, 56, true, 34)
	eq(tile.tex, null, "the tile draws its colour")
	_png("woodWall", 8, 8)
	Structures.clear_art_cache()
	ok(Structures.icon_of("woodWall") != null, "found by name")
	var art := UiSwatch.of_structure("woodWall", Color.RED, 56, true, 34)
	eq(art.tex, Structures.icon_of("woodWall"), "the tile draws the art")
	tile.free()
	art.free()
	Structures.ART_DIR = was
	Structures.clear_art_cache()


func test_every_file_in_the_structure_art_folder_is_named_after_a_structure() -> void:
	for f: String in DirAccess.get_files_at(Structures.ART_DIR):
		if f.ends_with(".png"):
			ok(Config.STRUCTURES.has(f.get_basename()), "art/structures/%s is named after no structure" % f)


# ------------------------------------------------------------ the street --
# How a piece looks built, `art/world/`: the same seam again, plus a second
# look for a piece that has one (an open gate, a turret's head).

func test_a_piece_with_no_picture_is_drawn_in_code() -> void:
	var was := Structures.WORLD_ART_DIR
	Structures.WORLD_ART_DIR = DIR
	Structures.clear_art_cache()
	var gate := {"type": "gate", "open": false}
	eq(StructureView.picture_of(gate), null, "no file, no picture")
	_png("gate", 8, 8)
	Structures.clear_art_cache()
	ok(StructureView.picture_of(gate) != null, "found by name")
	gate.open = true
	eq(StructureView.picture_of(gate), null, "an open gate is never drawn shut")
	_png("gate_open", 8, 8)
	Structures.clear_art_cache()
	ok(StructureView.picture_of(gate) != null, "and has its own picture")
	ne(StructureView.picture_of(gate), Structures.world_art_of("gate"))
	Structures.WORLD_ART_DIR = was
	Structures.clear_art_cache()


func test_a_picture_covers_its_whole_footprint() -> void:
	eq(StructureView.footprint_rect({"type": "longBed", "tx": 3, "ty": 4, "rot": 0}), Rect2(96, 128, 64, 32))
	eq(StructureView.footprint_rect({"type": "longBed", "tx": 3, "ty": 4, "rot": 1}), Rect2(96, 128, 32, 64))
	eq(StructureView.footprint_rect({"type": "woodWall", "tx": 3, "ty": 4}), Rect2(96, 128, 32, 32))


func test_every_file_in_the_street_art_folder_is_named_after_a_structure() -> void:
	var found := 0
	for f: String in DirAccess.get_files_at(Structures.WORLD_ART_DIR):
		if not f.ends_with(".png"):
			continue
		found += 1
		var name := f.get_basename()
		var parts := name.split("_")
		var named: bool = Config.STRUCTURES.has(name) or (parts.size() == 2 and Config.STRUCTURES.has(parts[0])
			and parts[1] in Structures.WORLD_STATES.get(parts[0], []))
		ok(named, "art/world/%s is named after no structure or state" % f)
	gt(found, 0, "the folder the game reads is where this looked")
