extends "res://tests/test_case.gd"
## The props on the 3D stage (2026-10-14): the view table names only
## files the catalog has, a model fits the box it is given, and the batch
## builder files every prop under a model or a stand-in.

const README := "res://assets/models/props/README.md"


## Every `<folder>/<file>.glb` the catalog lists, from its folder sections.
static func _catalog() -> Dictionary:
	var out := {}
	var f := FileAccess.open(README, FileAccess.READ)
	var folder := ""
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("## `") and line.ends_with("/`"):
			folder = line.substr(4, line.length() - 6)
		elif folder != "" and line.begins_with("| `") and line.find(".glb`") > 0:
			var name := line.substr(3, line.find("`", 3) - 3)
			out[folder + "/" + name] = true
	return out


func test_every_model_the_tables_name_is_in_the_catalog() -> void:
	var catalog := _catalog()
	ok(catalog.size() > 240, "the catalog lists %d files" % catalog.size())
	var paths := PropModels.every_path()
	ok(paths.size() > 150, "the tables use %d files" % paths.size())
	for p in paths:
		var rel := p.trim_prefix(PropModels.P)
		ok(catalog.has(rel), "the table names a file the catalog does not have: %s" % rel)


func test_a_model_is_fitted_inside_its_box_with_its_base_on_the_ground() -> void:
	# A unit-normalised export: 0.6 wide, 0.95 tall, 0.95 deep, centred.
	var bounds := AABB(Vector3(-0.3, -0.2, -0.475), Vector3(0.6, 0.95, 0.95))
	var xf := StaticModel.transform_for(bounds, Vector3(1.0, 0.8, 2.0))
	var fitted := xf * bounds
	# Height is the tightest side: 0.8 / 0.95.
	near(fitted.size.y, 0.8, 1e-4, "scaled to the height cap")
	near(fitted.size.x, 0.6 * 0.8 / 0.95, 1e-4)
	near(fitted.position.y, 0.0, 1e-4, "base on the ground")
	near(fitted.get_center().x, 0.0, 1e-4, "centred across")
	near(fitted.get_center().z, 0.0, 1e-4, "centred front to back")


func test_a_mesh_lying_the_wrong_way_turns_to_its_tiles() -> void:
	# Long along x, given a footprint long along z: turned a quarter.
	var bounds := AABB(Vector3(-0.475, 0.0, -0.2), Vector3(0.95, 0.3, 0.4))
	var xf := StaticModel.transform_for(bounds, Vector3(1.0, INF, 2.0))
	var fitted := xf * bounds
	near(fitted.size.z, 2.0, 1e-4, "its long side now runs along z")
	near(fitted.size.x, 0.4 * 2.0 / 0.95, 1e-4)
	# INF is no limit; a degenerate bound is left alone.
	eq(StaticModel.transform_for(AABB(), Vector3(1, 1, 1)), Transform3D.IDENTITY)


func test_kinds_and_containers_resolve_to_their_variants() -> void:
	var oak := PropModels.for_prop({"kind": "tree", "si": 1})
	eq(oak.size(), 1)
	ok(String(oak[0].path).ends_with("nature/oak_2.glb"), "the second oak: %s" % oak[0].path)
	var wrap := PropModels.for_prop({"kind": "tree", "si": 5})
	ok(String(wrap[0].path).ends_with("nature/oak_2.glb"), "variants wrap")
	eq(PropModels.for_prop({"kind": "hay", "si": 0}).size(), 0, "hay has no model yet: the stand-in")
	ok(String(PropModels.for_prop({"kind": "litter", "res": "sticks", "si": 0})[0].path).ends_with("stick_bundle.glb"))
	ok(String(PropModels.for_prop({"kind": "furniture", "what": "toilet", "si": 2})[0].path).ends_with("toilet_rusty_2.glb"))
	var desk := PropModels.for_container({"kind": "desk", "sprite": "desk"})
	eq(desk.size(), 3, "a desk is the desk, a monitor and a chair")
	ok(String(PropModels.for_container({"kind": "fridge", "sprite": "fridge"})[0].path).ends_with("refrigerator.glb"))
	ok(String(PropModels.for_container({"kind": "nurseCabinet", "sprite": "medcab"})[0].path).ends_with("cabinet_white.glb"))
	# A kind with no row falls back to its sprite.
	ok(String(PropModels.for_container({"kind": "somethingNew", "sprite": "milcrate"})[0].path).ends_with("crate_wooden.glb"))
	eq(PropModels.for_container({"kind": "somethingNew", "sprite": "nothing"}).size(), 0)
	for si in range(4):
		eq(PropModels.for_car(si).size(), 1, "car %d has a model" % si)


func test_the_batch_builder_files_a_prop_under_its_model_or_a_stand_in() -> void:
	var sim := new_sim()
	var props := Props3D.new(sim)
	var lists := {}
	var oak := {"kind": "tree", "si": 0, "x": 100.0, "y": 100.0}
	var hay := {"kind": "hay", "si": 0, "x": 100.0, "y": 100.0}
	props._collect(lists, hay, PropModels.for_prop(hay))
	ok(lists.has("stand-in:hay"), "hay goes to its stand-in batch")
	props._collect(lists, oak, PropModels.for_prop(oak))
	var oak_keys := lists.keys().filter(func(k: String) -> bool: return k.find("oak.glb") >= 0)
	var have_file := ResourceLoader.exists(PropModels.P + "nature/oak.glb")
	if have_file:
		eq(oak_keys.size(), 1, "with the file, the oak is a model batch for its chunk")
		ok(lists[oak_keys[0]].model, "...marked as a model")
		eq(lists[oak_keys[0]].chunk, 0, "chunk 0 for a prop near the origin")
	else:
		ok(lists.has("stand-in:tree"), "without the file, the oak is the stand-in tree")
	props.free()
