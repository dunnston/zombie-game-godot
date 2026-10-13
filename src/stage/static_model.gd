class_name StaticModel
extends RefCounted
## A static GLB from the owner's pipeline, fitted to a footprint. A Meshy
## export is about a unit across and centred on the origin, so every piece
## is measured by its mesh bounds, scaled so its longer side fills the
## tiles it stands on, and lifted so its base is on the ground. The code
## never needs to know the export's scale, which is the point.


## Instantiates `path` under `parent`, fitted to `size` metres (x, z).
## Returns the instanced root, or null when the file is not there.
static func fit(path: String, size: Vector2) -> Node3D:
	var ps := Models.scene(path)
	if ps == null:
		return null
	var inst := ps.instantiate() as Node3D
	if inst == null:
		return null
	var box := bounds(inst)
	if box.size.x <= 0.0 or box.size.z <= 0.0:
		return inst
	# The longer side of the footprint fits the longer side of the mesh, so a
	# long bed laid across two tiles is twice as long and not twice as wide.
	var fit_x := size.x / box.size.x
	var fit_z := size.y / box.size.z
	var s := minf(fit_x, fit_z)
	if box.size.x > box.size.z * 1.3 and size.x < size.y:
		# The model lies the other way to the footprint: turn it.
		inst.rotation.y = PI / 2.0
		s = minf(size.y / box.size.x, size.x / box.size.z)
	var centre := box.get_center()
	var holder := Node3D.new()
	holder.add_child(inst)
	inst.scale = Vector3(s, s, s)
	# The offset is in the holder's space: turned with the model, scaled with it, and never scaled twice.
	inst.position = Basis(Vector3.UP, inst.rotation.y) * Vector3(-centre.x * s, -box.position.y * s, -centre.z * s)
	return holder


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
