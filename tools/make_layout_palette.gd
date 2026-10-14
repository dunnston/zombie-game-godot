extends SceneTree
## Makes what the layout editor needs on disk (`scenes/layouts/`), run
## headless by `tools\make_layout_palette.cmd`:
##
## - `tiles.tres`, the GridMap library `LayoutScene` paints with;
## - `palette/<place>/<kind>.tscn`, one scene per piece the game can stand
##   in a house or a yard (`PropModels.THINGS`, `Config.CONTAINERS`), sorted
##   the way the catalog is, to drag into a layout scene;
## - `_template.tscn`, an empty layout to duplicate;
## - a scene per row already in `data/layouts.json`, so what the importer
##   made can be opened and moved about.
##
## Run it again after a new kind of prop joins `PropModels`.

const DIR := "res://scenes/layouts/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "palette"))
	var err := ResourceSaver.save(LayoutScene.library(), DIR + "tiles.tres")
	print("tiles.tres: %s" % error_string(err))
	var n := 0
	for kind in LayoutProp.kinds():
		var path := _palette_path(kind)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		var p := LayoutProp.new()
		p.name = kind
		p.kind = kind
		var ps := PackedScene.new()
		ps.pack(p)
		if ResourceSaver.save(ps, path) == OK:
			n += 1
		p.free()
	print("palette: %d pieces" % n)
	_save_scene(_scene("_template"), DIR + "_template.tscn")
	for id in Config.LAYOUTS:
		var s := _scene(String(id))
		root.add_child(s)
		s.layout_id = String(id)
		s.fill(Config.LAYOUTS[id])
		_save_scene(s, DIR + "%s.tscn" % id)
		root.remove_child(s)
		s.free()
	quit()


## Where a kind's palette scene goes: the folder its model lives in
## (furniture, kitchen, bathroom, yard…), or "other" for a stand-in.
static func _palette_path(kind: String) -> String:
	var parts: Array = PropModels.for_container({"kind": kind}) if Config.CONTAINERS.has(kind) else PropModels.for_prop({"kind": "furniture", "what": kind})
	var place := "other"
	if not parts.is_empty():
		place = String(parts[0].path).trim_prefix(PropModels.P).get_base_dir()
	return DIR + "palette/%s/%s.tscn" % [place, kind]


static func _scene(id: String) -> LayoutScene:
	var s := LayoutScene.new()
	s.name = id
	s.layout_id = id if id != "_template" else ""
	var g := GridMap.new()
	g.name = "Tiles"
	g.cell_size = Vector3.ONE
	g.mesh_library = load(DIR + "tiles.tres")
	s.add_child(g)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	sun.shadow_enabled = true
	s.add_child(sun)
	return s


static func _save_scene(s: LayoutScene, path: String) -> void:
	for c in s.get_children():
		c.owner = s
		if c is LayoutProp:
			# Its models are rebuilt on open; only the node itself is saved.
			for m in c.get_children():
				m.owner = null
	var ps := PackedScene.new()
	ps.pack(s)
	print("%s: %s" % [path.get_file(), error_string(ResourceSaver.save(ps, path))])
