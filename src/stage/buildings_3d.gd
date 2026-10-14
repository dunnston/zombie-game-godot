class_name Buildings3D
extends Node3D
## The town's buildings on the 3D stage, dressed with the building kit
## (`tools/build_kit.py` → `assets/models/buildings/kit.glb`): a plaster
## core on every wall tile, a siding panel, a window or a reveal on each
## outward face, a corner board at each corner, a canopy over each doorway,
## all as one MultiMesh per piece; and a gable roof per building, built here
## from its rectangle, which comes off while the local player is inside.
## `BuildingPlan` decides what goes where; this puts it there.
##
## Rebuilt whole when a wall breaks: a few thousand instances, well under a
## frame, and it happens a few times a night.

const KIT := "res://assets/models/buildings/kit.glb"
## The height the kit was modelled at; pieces are scaled to `STAGE3D.wall_h`.
const KIT_H := 2.2
const PITCH := 30.0
const OVERHANG := 0.45
const ROOF_T := 0.12
const PIECES := ["core", "facade", "facade_window", "jamb", "corner_board", "porch_roof"]

var plan := BuildingPlan.new()
var local: PlayerSim
var _meshes := {}      # piece -> Mesh, materials swapped for FacadeArt's
var _mmi := {}         # piece -> MultiMeshInstance3D
var _roofs: Array[MeshInstance3D] = []
var _local_tile := Vector2i(-1, -1)
var _flip := false


func build(world: World) -> void:
	for n in _mmi.values():
		n.queue_free()
	_mmi.clear()
	for r in _roofs:
		r.queue_free()
	_roofs.clear()
	plan.build(world)
	if _meshes.is_empty():
		_load_kit()
	if _meshes.is_empty():
		return
	var hs := float(Config.STAGE3D.wall_h) / KIT_H
	var by_piece := {}
	for p in PIECES:
		by_piece[p] = []
	for c in plan.cores:
		var t: Vector2i = c.tile
		by_piece["core"].append([Transform3D(Basis().scaled(Vector3(1, hs, 1)), Vector3(t.x + 0.5, 0, t.y + 0.5)), c.rect])
	for f in plan.faces:
		var at := Vector2(f.tile) + Vector2(0.5, 0.5) + Vector2(BuildingPlan.DIRS[f.dir]) * 0.5
		by_piece[f.kind].append([_face_xf(at, f.dir, hs), f.rect])
	for c in plan.corners:
		by_piece["corner_board"].append([Transform3D(Basis().scaled(Vector3(1, hs, 1)), Vector3(c.at.x, 0, c.at.y)), c.rect])
	for p in plan.porches:
		var xf := _face_xf(p.at, p.dir, hs)
		# The canopy is modelled over a 2 m doorway; a wider one stretches it.
		xf.basis = xf.basis * Basis().scaled(Vector3(float(p.width) / 2.0, 1, 1))
		by_piece["porch_roof"].append([xf, p.rect])
	for p in PIECES:
		_place(p, by_piece[p])
	for ri in range(plan.rects.size()):
		_roofs.append(_roof(plan.rects[ri], plan.styles[ri]))
	_local_tile = Vector2i(-1, -1)
	frame()


## The roof over the local player comes off, and goes back when they leave.
func frame() -> void:
	if local == null or _roofs.is_empty():
		return
	var t := Vector2i(int(local.pos.x / Config.TILE), int(local.pos.y / Config.TILE))
	if t == _local_tile:
		return
	_local_tile = t
	var inside := plan.inside(t)
	for ri in range(_roofs.size()):
		_roofs[ri].visible = ri != inside


## Whether building `ri`'s roof is drawn (the smoke asks).
func roof_visible(ri: int) -> bool:
	return ri >= 0 and ri < _roofs.size() and _roofs[ri].visible


## A piece modelled facing south, stood at `at` (tiles, the face's centre
## on the ground) and turned to face `dir`.
static func _face_xf(at: Vector2, dir: int, hs: float) -> Transform3D:
	var yaw := dir * PI / 2.0
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1, hs, 1)), Vector3(at.x, 0, at.y))


func _place(piece: String, items: Array) -> void:
	if items.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _meshes[piece]
	mm.instance_count = items.size()
	for i in range(items.size()):
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_custom_data(i, FacadeArt.custom_for(plan.styles[items[i][1]]))
	# As `Terrain3D`: the bounds are the town's, or the walls vanish when the
	# unit piece at the origin leaves the view.
	var W := float(Config.WORLD_TILES)
	mm.custom_aabb = AABB(Vector3(-1, 0, -1), Vector3(W + 2, 6, W + 2))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	_mmi[piece] = mmi


func _load_kit() -> void:
	var ps := Models.scene(KIT)
	if ps == null:
		push_warning("Buildings3D: no kit at %s; the town's walls are not drawn" % KIT)
		return
	var root := ps.instantiate()
	for p in PIECES:
		var n := root.find_child(p, true, false) as MeshInstance3D
		if n == null or n.mesh == null:
			push_warning("Buildings3D: the kit has no piece '%s'" % p)
			continue
		var mesh: Mesh = n.mesh
		for s in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(s)
			if mat != null:
				mesh.surface_set_material(s, FacadeArt.instanced(mat.resource_name))
		_meshes[p] = mesh
	root.free()


## A gable roof over a building: two shingled slabs ridged along the longer
## side, overhanging the walls, fascia in trim, the gable ends in siding.
func _roof(r: Rect2i, style: int) -> MeshInstance3D:
	var wall_h := float(Config.STAGE3D.wall_h)
	var tan_p := tan(deg_to_rad(PITCH))
	var x0 := float(r.position.x)
	var z0 := float(r.position.y)
	var w := float(r.size.x)
	var h := float(r.size.y)
	var along_x := w >= h
	# In roof space: `u` runs along the ridge, `v` across it.
	var u0 := (x0 if along_x else z0) - OVERHANG
	var u1 := u0 + (w if along_x else h) + 2.0 * OVERHANG
	var span := (h if along_x else w)
	var vc := (z0 if along_x else x0) + span / 2.0
	var half := span / 2.0
	var y_ridge := wall_h + half * tan_p
	var y_eave := wall_h - OVERHANG * tan_p
	var shingle := SurfaceTool.new()
	shingle.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trim := SurfaceTool.new()
	trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var siding := SurfaceTool.new()
	siding.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Swapping the axes mirrors the winding: every face below is written
	# for a ridge along x and turned inside out for one along z.
	_flip = not along_x
	for side: float in [-1.0, 1.0]:
		var v_out := vc + side * (half + OVERHANG)
		# The slab's top, from ridge to eave, and its bottom ROOF_T below.
		var a := _pt(along_x, u0, vc, y_ridge)
		var b := _pt(along_x, u1, vc, y_ridge)
		var c := _pt(along_x, u1, v_out, y_eave)
		var d := _pt(along_x, u0, v_out, y_eave)
		var slope := half + OVERHANG
		var run := sqrt(slope * slope + (y_ridge - y_eave) * (y_ridge - y_eave))
		if side > 0:
			_quad(shingle, a, b, c, d, [Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, run), Vector2(u0, run)])
		else:
			_quad(shingle, b, a, d, c, [Vector2(u1, 0), Vector2(u0, 0), Vector2(u0, run), Vector2(u1, run)])
		var down := Vector3(0, -ROOF_T, 0)
		# Eave fascia and the two rake ends.
		if side > 0:
			_quad(trim, d, c, c + down, d + down, null)
			_quad(trim, a, d, d + down, a + down, null)
			_quad(trim, c, b, b + down, c + down, null)
		else:
			_quad(trim, c, d, d + down, c + down, null)
			_quad(trim, d, a, a + down, d + down, null)
			_quad(trim, b, c, c + down, b + down, null)
	# Gable ends at the wall line, a hair proud of the corner boards' plane.
	var ga := (x0 if along_x else z0) - 0.02
	var gb := ga + (w if along_x else h) + 0.04
	var vl := vc - half
	var vr := vc + half
	var e0 := _pt(along_x, ga, vl, wall_h)
	var e1 := _pt(along_x, ga, vr, wall_h)
	var e2 := _pt(along_x, ga, vc, y_ridge)
	var f0 := _pt(along_x, gb, vl, wall_h)
	var f1 := _pt(along_x, gb, vr, wall_h)
	var f2 := _pt(along_x, gb, vc, y_ridge)
	var tri_uv := [Vector2(0, 0), Vector2(span, 0), Vector2(half, y_ridge - wall_h)]
	_tri(siding, e1, e0, e2, tri_uv)
	_tri(siding, f0, f1, f2, tri_uv)
	var mesh := ArrayMesh.new()
	var parts := {"shingle": shingle, "trim": trim, "siding": siding}
	for name: String in parts:
		var st: SurfaceTool = parts[name]
		st.generate_normals()
		st.set_material(FacadeArt.styled(name, style))
		st.commit(mesh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	return mi


## Roof space to the stage: `u` along the ridge, `v` across it.
static func _pt(along_x: bool, u: float, v: float, y: float) -> Vector3:
	return Vector3(u, y, v) if along_x else Vector3(v, y, u)


## A quad a, b, c, d clockwise seen from outside (Godot's front face), with
## UVs in metres.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv) -> void:
	var uvs: Array = uv if uv != null else [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	_tri(st, a, b, c, [uvs[0], uvs[1], uvs[2]])
	_tri(st, a, c, d, [uvs[0], uvs[2], uvs[3]])


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, uv: Array) -> void:
	if _flip:
		var t := b
		b = c
		c = t
		uv = [uv[0], uv[2], uv[1]]
	st.set_uv(uv[0])
	st.add_vertex(a)
	st.set_uv(uv[1])
	st.add_vertex(b)
	st.set_uv(uv[2])
	st.add_vertex(c)
