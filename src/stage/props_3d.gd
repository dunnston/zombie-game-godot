class_name Props3D
extends Node3D
## The world's props on the 3D stage — trees, scenery, litter, wrecks,
## furniture, containers — as the owner's models (`PropModels`), batched:
## one MultiMesh per model per 32-tile chunk, built once from the sim.
## Chunking is what lets the camera cull a forest it cannot see and the
## renderer pick a lower level of detail for the far side of town; eleven
## thousand props become a few hundred draw calls. A felled tree or an
## emptied container changes its instance rather than the batch: the lists
## are walked for `gone` and `looted` a few times a second, which is cheaper
## than being told and never misses a survivor's search.
##
## Anything without a model — a kind with no row, or a file this checkout
## does not have — draws as a stand-in shape in the 2D palette, as every
## prop did before the models arrived.

const REFRESH := 0.25
const CHUNK := 32
## A searched container's tint.
const LOOTED := Color(0.5, 0.5, 0.5)

var sim: GameSim
## key -> {mmi, mm, props: Array, state: PackedByteArray, local: Transform3D, model: bool}
var _batches := {}
var _since := 0.0


func _init(sim_: GameSim) -> void:
	sim = sim_


func rebuild() -> void:
	for b in _batches.values():
		b.mmi.queue_free()
	_batches.clear()
	var lists := {}
	for p in sim.world.props:
		# A wreck spans two tiles and carries `tiles` for it; it is still a
		# prop (solid, harvestable for Sheet Metal) and is drawn here. Cars
		# are not in this list at all: `Vehicles3D` draws `sim.cars`.
		if p.get("gone", false):
			continue
		_collect(lists, p, PropModels.for_prop(p))
	for c in sim.world.containers:
		_collect(lists, c, PropModels.for_container(c))
	for key in lists:
		_build(key, lists[key])
	_since = 0.0


## Files a prop under one batch per part that draws it, or under its
## kind's stand-in when nothing does.
func _collect(lists: Dictionary, p: Dictionary, parts: Array) -> void:
	var drawn := false
	var chunk := int(p.y / Config.TILE) / CHUNK * (Config.WORLD_TILES / CHUNK) + int(p.x / Config.TILE) / CHUNK
	for part in parts:
		var model := StaticModel.parts(part.path)
		if model.is_empty():
			continue
		var local := _local(model.bounds, part)
		for mi in range(model.meshes.size()):
			var key := "%s#%d#%d#%s#%s" % [part.path, mi, chunk, part.box, part.at]
			if not lists.has(key):
				lists[key] = {"mesh": model.meshes[mi].mesh, "local": local * model.meshes[mi].xf, "props": [], "model": true, "chunk": chunk}
			lists[key].props.append(p)
			drawn = true
	if drawn:
		return
	var kind := _kind_of(p)
	var key := "stand-in:" + kind
	if not lists.has(key):
		lists[key] = {"mesh": _mesh_for(kind, p), "local": Transform3D.IDENTITY, "props": [], "model": false, "chunk": -1}
	lists[key].props.append(p)


## A part's place inside its prop's footprint: fitted to its box, turned
## by its own correction, moved by its offset.
static func _local(bounds: AABB, part: Dictionary) -> Transform3D:
	var fit := StaticModel.transform_for(bounds, part.box)
	var turn := Transform3D(Basis(Vector3.UP, float(part.yaw)), Vector3.ZERO)
	return Transform3D(Basis.IDENTITY, part.at) * turn * fit


func frame(dt: float) -> void:
	_since += dt
	if _since < REFRESH:
		return
	_since = 0.0
	for key in _batches:
		var b: Dictionary = _batches[key]
		var props: Array = b.props
		var state: PackedByteArray = b.state
		for i in range(props.size()):
			var p: Dictionary = props[i]
			var now := _state_of(p)
			if now == state[i]:
				continue
			state[i] = now
			_set_instance(b, i, p, now)


static func _state_of(p: Dictionary) -> int:
	if p.get("gone", false):
		return 2
	if p.get("looted", false):
		return 1
	return 0


static func _kind_of(p: Dictionary) -> String:
	if p.has("looted"):
		return "container"
	return String(p.get("kind", "litter"))


func _build(key: String, list: Dictionary) -> void:
	var props: Array = list.props
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = list.mesh
	mm.instance_count = props.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	var state := PackedByteArray()
	state.resize(props.size())
	var b := {"mmi": mmi, "mm": mm, "props": props, "state": state, "local": list.local, "model": list.model}
	_batches[key] = b
	for i in range(props.size()):
		var p: Dictionary = props[i]
		var now := _state_of(p)
		state[i] = now
		_set_instance(b, i, p, now)
	# The bounds are the chunk's with room for what overhangs it, or the
	# town's for a stand-in batch: the renderer culls by them, and a unit
	# piece at the origin would vanish when the origin leaves the view.
	var W := float(Config.WORLD_TILES)
	if int(list.chunk) >= 0:
		var per := Config.WORLD_TILES / CHUNK
		var cx := float(int(list.chunk) % per * CHUNK)
		var cz := float(int(list.chunk) / per * CHUNK)
		mm.custom_aabb = AABB(Vector3(cx - 3.0, -1.0, cz - 3.0), Vector3(CHUNK + 6.0, 8.0, CHUNK + 6.0))
	else:
		mm.custom_aabb = AABB(Vector3(0, 0, 0), Vector3(W, 6.0, W))


func _set_instance(b: Dictionary, i: int, p: Dictionary, now: int) -> void:
	var mm: MultiMesh = b.mm
	if now == 2:
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -2, 0)))
		return
	var at := Units.to3(Vector2(p.x, p.y))
	var place := Transform3D(Basis(Vector3.UP, yaw_of(p)), at)
	if p.get("kind", "") == "wall":
		# Hung on the inner face of its wall tile's panel: the siding on an
		# outer wall sits at the tile's outer edge, a divider through its
		# middle (`BuildingPlan`).
		place.origin += place.basis * Vector3(0, 0, -0.25 if p.get("outer", true) else -0.08)
	mm.set_instance_transform(i, place * b.local)
	var col := Color.WHITE
	if b.model:
		if now == 1:
			col = LOOTED
	elif p.has("looted"):
		col = Color(PropRenderer.CONTAINER_PAINT.get(p.sprite, "#888888"))
		if now == 1:
			col = col.darkened(0.45)
	elif p.get("kind", "") == "tree":
		col = PropRenderer.CANOPY[int(p.get("si", 0)) % PropRenderer.CANOPY.size()]
	# An instance colour is read as linear by the shader; the palette is sRGB.
	mm.set_instance_color(i, col.srgb_to_linear())


## What grows or lies about gets a twist per variant, so a row of oaks is
## not one oak; what was parked or built stands square to its tiles.
const TWISTED := ["tree", "pine", "bush", "thicket", "rock", "boulder", "stump", "log", "corn", "litter", "reed"]


## Which way a prop faces: `dir` in quarter turns from south (furniture,
## containers, what the generator stood against a wall), else its 2D
## rotation, which turns the other way on a canvas.
static func yaw_of(p: Dictionary) -> float:
	if p.has("dir"):
		return int(p.dir) * PI / 2.0
	var yaw := -float(p.get("rot", 0.0))
	if p.has("si") and String(p.get("kind", "")) in TWISTED:
		yaw += float(int(p.si)) * 0.7
	return yaw


## A stand-in shape per kind, in metres, base at the origin. Surfaces carry
## their own colour; the instance colour multiplies it (white for most).
## Furniture and the like take their footprint from the prop.
static func _mesh_for(kind: String, p: Dictionary = {}) -> Mesh:
	var m := ArrayMesh.new()
	match kind:
		"tree":
			_add(m, _cyl(0.1, 0.9), Vector3(0, 0.45, 0), Color("#4a3722"))
			_add(m, _sphere(0.75), Vector3(0, 1.45, 0), Color.WHITE)
		"pine":
			_add(m, _cyl(0.08, 0.6), Vector3(0, 0.3, 0), Color("#3a2c1c"))
			_add(m, _cone(0.65, 1.9), Vector3(0, 1.45, 0), Color("#24472a"))
		"bush":
			_add(m, _sphere(0.32), Vector3(0, 0.3, 0), Color("#3f6b2f"))
		"thicket":
			_add(m, _sphere(0.45), Vector3(0, 0.38, 0), Color("#2c4a24"))
		"rock":
			_add(m, _box(Vector3(0.45, 0.28, 0.4)), Vector3(0, 0.14, 0), Color("#6f6b62"))
		"boulder":
			_add(m, _sphere(0.5), Vector3(0, 0.4, 0), Color("#5d5952"))
		"stump":
			_add(m, _cyl(0.3, 0.5), Vector3(0, 0.25, 0), Color("#5a4330"))
		"log":
			_add(m, _box(Vector3(0.9, 0.3, 0.3)), Vector3(0, 0.15, 0), Color("#5a4330"))
		"reed":
			_add(m, _box(Vector3(0.25, 0.6, 0.12)), Vector3(0, 0.3, 0), Color("#5e8a3a"))
		"corn":
			_add(m, _box(Vector3(0.2, 1.5, 0.2)), Vector3(0, 0.75, 0), Color("#8aa03a"))
		"hay":
			_add(m, _box(Vector3(0.85, 0.6, 0.65)), Vector3(0, 0.3, 0), Color("#b8983f"))
		"silo":
			_add(m, _cyl(0.9, 3.0), Vector3(0, 1.5, 0), Color("#8c8c86"))
		"tractor":
			_add(m, _box(Vector3(1.8, 0.7, 0.9)), Vector3(0, 0.35, 0), Color("#8a2f2f"))
			_add(m, _box(Vector3(0.8, 0.8, 0.8)), Vector3(-0.3, 1.1, 0), Color("#3a2e28"))
		"wreck":
			_add(m, _box(Vector3(1.9, 0.5, 0.75)), Vector3(0, 0.25, 0), Color("#4f4a45"))
			_add(m, _box(Vector3(0.85, 0.35, 0.65)), Vector3(0.1, 0.65, 0), Color("#3a2e28"))
		"container":
			_add(m, _box(Vector3(0.72, 0.72, 0.72)), Vector3(0, 0.36, 0), Color.WHITE)
		"wall":
			_add(m, _box(Vector3(0.6, 0.5, 0.06)), Vector3(0, 1.4, 0), Color("#6a4a2e"))
		"furniture", "yard", "street", "decor":
			var w := float(p.get("w", 1)) - 0.15
			var d := float(p.get("h", 1)) - 0.15
			var h := 0.7 if kind == "furniture" else 1.0
			_add(m, _box(Vector3(w, h, d)), Vector3(0, h / 2.0, 0), Color("#7a6248") if kind == "furniture" else Color("#5f6b5a"))
		_:
			_add(m, _box(Vector3(0.3, 0.08, 0.3)), Vector3(0, 0.04, 0), Color("#7d7a70"))
	return m


static func _add(m: ArrayMesh, prim: PrimitiveMesh, at: Vector3, color: Color) -> void:
	var arrays := prim.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(verts.size()):
		verts[i] += at
	arrays[Mesh.ARRAY_VERTEX] = verts
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	m.surface_set_material(m.get_surface_count() - 1, mat)


static func _cyl(r: float, h: float) -> PrimitiveMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	return c


static func _cone(r: float, h: float) -> PrimitiveMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	return c


static func _sphere(r: float) -> PrimitiveMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 8
	s.rings = 5
	return s


static func _box(size: Vector3) -> PrimitiveMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
