class_name StaticModel
extends RefCounted
## A static GLB from the owner's pipeline, fitted to the space it stands
## in. A Meshy export is about a unit across and centred on the origin, so
## every piece is measured by its mesh bounds, scaled so it fits inside a
## box (its footprint on the ground and how tall it may be), and lifted so
## its base is on the ground. The code never needs to know the export's
## scale, which is the point. `transform_for` is the whole of the maths and
## is pure; `parts` hands the meshes to a MultiMesh; `fit` stands one copy
## up as nodes.


## Instantiates `path` under a holder, fitted to `size` metres (x, z) with
## no limit on height. Returns the holder, or null when the file is not there.
static func fit(path: String, size: Vector2) -> Node3D:
	return fit_box(path, Vector3(size.x, INF, size.y))


## Instantiates `path` under a holder, fitted inside `box` metres (x, up,
## z). Returns the holder, or null when the file is not there.
static func fit_box(path: String, box: Vector3) -> Node3D:
	var ps := Models.scene(path)
	if ps == null:
		return null
	var inst := ps.instantiate() as Node3D
	if inst == null:
		return null
	var holder := Node3D.new()
	holder.add_child(inst)
	inst.transform = transform_for(bounds(inst), box)
	return holder


## The transform that puts a mesh with `bounds` inside `box`: scaled by the
## tightest of the three sides (a side of `box` that is 0 or INF does not
## count), its base on the ground and its footprint centred on the origin.
## A mesh whose long side runs across the box's long side is turned a
## quarter first, so a bed modelled along x lies along the two tiles it
## was given along z. A bound without size gives the identity.
static func transform_for(bounds: AABB, box: Vector3) -> Transform3D:
	var bx := bounds.size.x
	var by := bounds.size.y
	var bz := bounds.size.z
	if bx <= 0.0 or bz <= 0.0:
		return Transform3D.IDENTITY
	var yaw := 0.0
	var long_x := bx > bz * 1.25
	var long_z := bz > bx * 1.25
	if _limits(box.x) and _limits(box.z) and ((long_x and box.x < box.z) or (long_z and box.z < box.x)):
		yaw = PI / 2.0
		var t := bx
		bx = bz
		bz = t
	var s := INF
	if _limits(box.x):
		s = minf(s, box.x / bx)
	if _limits(box.z):
		s = minf(s, box.z / bz)
	if _limits(box.y) and by > 0.0:
		s = minf(s, box.y / by)
	if s == INF:
		s = 1.0
	var centre := bounds.get_center()
	var rot := Basis(Vector3.UP, yaw)
	var shift := rot * (Vector3(-centre.x, -bounds.position.y, -centre.z) * s)
	return Transform3D(rot * Basis().scaled(Vector3(s, s, s)), shift)


static func _limits(v: float) -> bool:
	return v > 0.0 and v != INF


static var _parts := {}


## The meshes of the model at `path` with their transforms relative to its
## root, and their merged bounds: `{"bounds": AABB, "meshes": [{mesh, xf}]}`.
## Loaded once, so a town of oaks instantiates the oak once. Empty when the
## file is not there. The materials are set to take an instance colour, which
## is how a searched cabinet goes dark in a batch.
static func parts(path: String) -> Dictionary:
	if _parts.has(path):
		return _parts[path]
	var out := {}
	var ps := Models.scene(path)
	if ps != null:
		var inst := ps.instantiate() as Node3D
		if inst != null:
			var meshes := []
			for m in _meshes(inst):
				var mi := m as MeshInstance3D
				if mi.mesh == null:
					continue
				_take_colour(mi.mesh)
				meshes.append({"mesh": mi.mesh, "xf": _relative(inst, mi)})
			if not meshes.is_empty():
				out = {"bounds": bounds(inst), "meshes": meshes}
			inst.free()
	_parts[path] = out
	return out


static func _take_colour(mesh: Mesh) -> void:
	for s in range(mesh.get_surface_count()):
		var mat := mesh.surface_get_material(s)
		if mat is BaseMaterial3D and not (mat as BaseMaterial3D).vertex_color_use_as_albedo:
			(mat as BaseMaterial3D).vertex_color_use_as_albedo = true


## The merged bounds of every mesh under `n`, in `n`'s own space.
static func bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in _meshes(n):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var local := mi.get_aabb()
		var rel := n.global_transform.affine_inverse() * mi.global_transform if n.is_inside_tree() else _relative(n, mi)
		var b := rel * local
		out = b if first else out.merge(b)
		first = false
	return out


static func _relative(root: Node3D, m: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = m
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for k in n.get_children():
		out.append_array(_meshes(k))
	return out
