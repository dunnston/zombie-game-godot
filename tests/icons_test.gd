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
	# that no item ever shows.
	for f: String in DirAccess.get_files_at(project_dir):
		if not f.ends_with(".png"):
			continue
		var id := f.get_basename().trim_suffix("_ground")
		ok(Items.has(id), "art/items/%s is named after no item" % f)
