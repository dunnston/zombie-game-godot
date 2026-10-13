class_name Props3D
extends Node3D
## The world's props on the 3D stage — trees, scenery, litter, wrecks,
## containers — as one MultiMesh per kind of shape, built once from the sim.
## Eleven thousand dictionaries become a dozen draw calls. A felled tree or
## an emptied container changes its instance rather than the batch: the
## lists are walked for `gone` and `looted` a few times a second, which is
## cheaper than being told and never misses a survivor's search.
##
## Shapes are stand-ins in the 2D palette until the owner's models arrive:
## a trunk and a canopy, a cone for a pine, a box for a crate.

const REFRESH := 0.25

var sim: GameSim
var _kinds := {}      # kind -> {mmi, mm, props: Array, state: PackedByteArray}
var _since := 0.0


func _init(sim_: GameSim) -> void:
	sim = sim_


func rebuild() -> void:
	for k in _kinds.values():
		k.mmi.queue_free()
	_kinds.clear()
	var lists := {}
	for p in sim.world.props:
		if p.has("tiles") or p.get("gone", false):
			# A car is `Vehicles3D`'s, as the 2D stage leaves it to VehicleView.
			continue
		var kind := _kind_of(p)
		if not lists.has(kind):
			lists[kind] = []
		lists[kind].append(p)
	for c in sim.world.containers:
		if not lists.has("container"):
			lists["container"] = []
		lists["container"].append(c)
	for kind in lists:
		_build_kind(kind, lists[kind])
	_since = 0.0


func frame(dt: float) -> void:
	_since += dt
	if _since < REFRESH:
		return
	_since = 0.0
	for kind in _kinds:
		var k: Dictionary = _kinds[kind]
		var props: Array = k.props
		var state: PackedByteArray = k.state
		for i in range(props.size()):
			var p: Dictionary = props[i]
			var now := 0
			if p.get("gone", false):
				now = 2
			elif p.get("looted", false):
				now = 1
			if now == state[i]:
				continue
			state[i] = now
			_set_instance(k, i, p, now)


static func _kind_of(p: Dictionary) -> String:
	if p.has("looted"):
		return "container"
	return String(p.get("kind", "litter"))


func _build_kind(kind: String, props: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _mesh_for(kind)
	mm.instance_count = props.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	var state := PackedByteArray()
	state.resize(props.size())
	var k := {"mmi": mmi, "mm": mm, "props": props, "state": state}
	_kinds[kind] = k
	for i in range(props.size()):
		var p: Dictionary = props[i]
		var now := 2 if p.get("gone", false) else (1 if p.get("looted", false) else 0)
		state[i] = now
		_set_instance(k, i, p, now)
	var W := float(Config.WORLD_TILES)
	mm.custom_aabb = AABB(Vector3(0, 0, 0), Vector3(W, 6.0, W))


func _set_instance(k: Dictionary, i: int, p: Dictionary, now: int) -> void:
	var mm: MultiMesh = k.mm
	if now == 2:
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -2, 0)))
		return
	var at := Units.to3(Vector2(p.x, p.y))
	var yaw := float(p.get("rot", 0.0))
	if p.has("si"):
		yaw += float(int(p.si)) * 0.7
	mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), at))
	var col := Color.WHITE
	if p.has("looted"):
		col = Color(PropRenderer.CONTAINER_PAINT.get(p.sprite, "#888888"))
		if now == 1:
			col = col.darkened(0.45)
	elif p.get("kind", "") == "tree":
		col = PropRenderer.CANOPY[int(p.get("si", 0)) % PropRenderer.CANOPY.size()]
	# An instance colour is read as linear by the shader; the palette is sRGB.
	mm.set_instance_color(i, col.srgb_to_linear())


## A stand-in shape per kind, in metres, base at the origin. Surfaces carry
## their own colour; the instance colour multiplies it (white for most).
static func _mesh_for(kind: String) -> Mesh:
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
		"reed":
			_add(m, _box(Vector3(0.25, 0.6, 0.12)), Vector3(0, 0.3, 0), Color("#5e8a3a"))
		"hay":
			_add(m, _box(Vector3(0.85, 0.6, 0.65)), Vector3(0, 0.3, 0), Color("#b8983f"))
		"silo":
			_add(m, _cyl(0.9, 3.0), Vector3(0, 1.5, 0), Color("#8c8c86"))
		"wreck":
			_add(m, _box(Vector3(1.9, 0.5, 0.75)), Vector3(0, 0.25, 0), Color("#4f4a45"))
			_add(m, _box(Vector3(0.85, 0.35, 0.65)), Vector3(0.1, 0.65, 0), Color("#3a2e28"))
		"container":
			_add(m, _box(Vector3(0.72, 0.72, 0.72)), Vector3(0, 0.36, 0), Color.WHITE)
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
