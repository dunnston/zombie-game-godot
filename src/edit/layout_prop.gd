@tool
class_name LayoutProp
extends Node3D
## A piece of a layout in the Godot editor (2026-10-14): drag one from
## `scenes/layouts/palette/` into a `LayoutScene`, or add this node and
## pick its `kind`. It draws itself as the game will — the same models,
## fitted the same way (`PropModels`, `StaticModel`) — over a footprint on
## the floor with a bar on the side it faces. Move it and it snaps to whole
## tiles; turn it and it snaps to quarter turns. `LayoutScene` reads its
## tile, size and facing when it exports. Nothing here is saved but the
## kind and the variant: the models are rebuilt whenever the scene opens.

## How thin a wall-hung piece's footprint reads on the floor.
const FOOT_H := 0.02
const FOOT_COLOR := Color(0.2, 0.6, 1.0, 0.35)
const FACE_COLOR := Color(1.0, 0.85, 0.2, 0.8)
const CONTAINER_COLOR := Color(1.0, 0.5, 0.2, 0.35)

var kind := "sofa":
	set(v):
		kind = v
		_rebuild()
var variant := 0:
	set(v):
		variant = posmod(int(v), 4)
		_rebuild()

var _built := ""
var _snapping := false


static func kinds() -> PackedStringArray:
	var out := PackedStringArray()
	for k in PropModels.THINGS:
		out.append(String(k))
	for k in Config.CONTAINERS:
		if not out.has(String(k)):
			out.append(String(k))
	out.sort()
	return out


## The kinds Furnish hangs on walls: what a layout stores as kind "wall".
static func hung() -> PackedStringArray:
	var out := PackedStringArray()
	for table in [Config.ROOMS, Config.DECOR]:
		for recipe in table.values():
			_hung_in(recipe, out)
	return out


static func _hung_in(recipe: Array, out: PackedStringArray) -> void:
	for e in recipe:
		if e.has("one_of"):
			_hung_in(e.one_of, out)
		elif e.get("wall", false) and not out.has(String(e.what)):
			out.append(String(e.what))


func _get_property_list() -> Array[Dictionary]:
	return [
		{"name": "kind", "type": TYPE_STRING, "hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(kinds()), "usage": PROPERTY_USAGE_DEFAULT},
		{"name": "variant", "type": TYPE_INT, "hint": PROPERTY_HINT_RANGE, "hint_string": "0,3", "usage": PROPERTY_USAGE_DEFAULT},
	]


func _ready() -> void:
	set_notify_transform(true)
	_rebuild()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and not _snapping:
		snap()


func is_container() -> bool:
	return Config.CONTAINERS.has(kind)


func is_hung() -> bool:
	return kind in hung()


## Tiles across the face and deep (`Layout.size_of`).
func size() -> Vector2i:
	return Layout.size_of(kind, kind if is_container() else "")


## Quarter turns from south, from the node's turn.
func facing() -> int:
	return posmod(roundi(rotation.y / (PI / 2.0)), 4)


## The tiles covered when facing `d`: width along x for south and north.
func footprint(d: int = facing()) -> Vector2i:
	var s := size()
	return s if d % 2 == 0 else Vector2i(s.y, s.x)


## The top-left tile of the footprint, in the scene's tiles.
func tile() -> Vector2i:
	var f := footprint()
	return Vector2i(roundi(position.x - f.x / 2.0), roundi(position.z - f.y / 2.0))


## Puts the piece square on whole tiles, facing a quarter turn.
func snap() -> void:
	_snapping = true
	var d := facing()
	rotation = Vector3(0.0, d * PI / 2.0, 0.0)
	var f := footprint(d)
	position = Vector3(floorf(position.x - f.x / 2.0 + 0.5) + f.x / 2.0, 0.0, floorf(position.z - f.y / 2.0 + 0.5) + f.y / 2.0)
	_snapping = false


## Stands the piece on a tile, facing `d`, as `LayoutScene` loads a row.
func place(top_left: Vector2i, d: int) -> void:
	_snapping = true
	rotation = Vector3(0.0, d * PI / 2.0, 0.0)
	var f := footprint(d)
	position = Vector3(top_left.x + f.x / 2.0, 0.0, top_left.y + f.y / 2.0)
	_snapping = false


## The row entry `LayoutScene` writes for this piece, with its tile
## relative to `origin`. Hung pieces and containers say so; a piece on
## the grass outside says "yard".
func entry(origin: Vector2i, outside: bool) -> Dictionary:
	var s := size()
	var t := tile() - origin
	var e := {"x": t.x, "y": t.y, "w": s.x, "h": s.y, "d": facing()}
	if is_container():
		e["container"] = kind
	else:
		e["what"] = kind
		if is_hung():
			e["kind"] = "wall"
		elif outside:
			e["kind"] = "yard"
		if not _solid_by_default():
			e["solid"] = false
	return e


## Rugs, plants, towels, a basket: Furnish stands these as not solid.
func _solid_by_default() -> bool:
	for table in [Config.ROOMS, Config.DECOR, Config.YARD]:
		for recipe in table.values():
			var found := _solid_in(recipe)
			if found != -1:
				return found == 1
	return true


func _solid_in(recipe: Array) -> int:
	for e in recipe:
		if e.has("one_of"):
			var r := _solid_in(e.one_of)
			if r != -1:
				return r
		elif String(e.get("what", "")) == kind:
			return 1 if bool(e.get("solid", true)) else 0
	return -1


func _rebuild() -> void:
	if not is_inside_tree():
		return
	var key := "%s#%d" % [kind, variant]
	if key == _built:
		return
	_built = key
	for c in get_children():
		if c.name.begins_with("_"):
			remove_child(c)
			c.queue_free()
	var p := {"kind": "furniture", "what": kind, "si": variant}
	var parts: Array = PropModels.for_container({"kind": kind, "si": variant}) if is_container() else PropModels.for_prop(p)
	var drawn := false
	for part in parts:
		var model := StaticModel.parts(part.path)
		if model.is_empty():
			continue
		var local := Props3D._local(model.bounds, part)
		for m in model.meshes:
			var mi := MeshInstance3D.new()
			mi.name = "_model"
			mi.mesh = m.mesh
			mi.transform = local * m.xf
			add_child(mi)
			drawn = true
	if not drawn:
		var mi := MeshInstance3D.new()
		mi.name = "_standin"
		var s := size()
		mi.mesh = Props3D._mesh_for("container" if is_container() else "furniture", {"w": s.x, "h": s.y})
		add_child(mi)
	_footprint()


## The footprint on the floor and a bar along the side the piece faces
## (south at rest, +z).
func _footprint() -> void:
	var s := size()
	var foot := MeshInstance3D.new()
	foot.name = "_foot"
	var box := BoxMesh.new()
	box.size = Vector3(s.x - 0.04, FOOT_H, s.y - 0.04)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = CONTAINER_COLOR if is_container() else FOOT_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = mat
	foot.mesh = box
	foot.position = Vector3(0.0, FOOT_H / 2.0, 0.0)
	add_child(foot)
	var face := MeshInstance3D.new()
	face.name = "_face"
	var bar := BoxMesh.new()
	bar.size = Vector3(s.x - 0.04, FOOT_H * 2.0, 0.08)
	var fm := StandardMaterial3D.new()
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color = FACE_COLOR
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar.material = fm
	face.mesh = bar
	face.position = Vector3(0.0, FOOT_H, s.y / 2.0 - 0.04)
	add_child(face)
