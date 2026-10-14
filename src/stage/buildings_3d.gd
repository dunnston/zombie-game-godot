class_name Buildings3D
extends Node3D
## The town's buildings on the 3D stage, dressed with the building parts
## (`tools/build_kit.py` → `assets/models/buildings/parts.glb`): one
## MultiMesh per part for the whole town, placed where `BuildingPlan` says,
## and a gable roof per building built here from its rectangle, which comes
## off while the local player is inside. Yards and partitions get walls and
## no roof: nothing is ever drawn over another building.
##
## Rebuilt whole when a wall breaks: a few thousand instances, well under a
## frame, and it happens a few times a night.

const KIT := "res://assets/models/buildings/parts.glb"
## The height the parts were modelled at; pieces are scaled to `STAGE3D.wall_h`.
const KIT_H := 3.0
const PITCH := 30.0
const OVERHANG := 0.45
const ROOF_T := 0.12
## A siding board's height on the gable ends, as the parts have it.
const BOARD := 0.25
const PARTS := ["wall_1m", "wall_window_2m", "window_single", "wall_doorway_2m", "door_open", "porch_roof_2m", "corner_post", "wall_interior_1m", "wall_interior_post", "wall_interior_arm", "wall_interior_arm_long"]

var plan := BuildingPlan.new()
var local: PlayerSim
var _meshes := {}      # part -> Mesh, materials swapped for FacadeArt's
var _mmi := {}         # part -> MultiMeshInstance3D
var _roofs := {}       # rect index -> MeshInstance3D
var _local_tile := Vector2i(-1, -1)
var _flip := false


func build(world: World) -> void:
	for n in _mmi.values():
		n.queue_free()
	_mmi.clear()
	for r in _roofs.values():
		r.queue_free()
	_roofs.clear()
	plan.build(world)
	if _meshes.is_empty():
		_meshes = load_parts(PARTS)
	if _meshes.is_empty():
		return
	var hs := float(Config.STAGE3D.wall_h) / KIT_H
	var by_part := {}
	for p in plan.parts:
		if not by_part.has(p.part):
			by_part[p.part] = []
		by_part[p.part].append([part_xf(p.at, p.dir, hs, p.sx), p.rect])
	for part in by_part:
		_place(part, by_part[part])
	for ri in plan.roofed():
		_roofs[ri] = _roof(plan.rects[ri], plan.styles[ri])
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
	for ri in _roofs:
		_roofs[ri].visible = ri != inside


## Whether building `ri`'s roof is drawn (the smoke asks). A building
## without one answers false.
func roof_visible(ri: int) -> bool:
	return _roofs.has(ri) and _roofs[ri].visible


## A part modelled facing south, stood with its origin at `at` (tiles) and
## turned to face `dir`, `hs` tall and `sx` wide.
static func part_xf(at: Vector2, dir: int, hs: float, sx := 1.0) -> Transform3D:
	var yaw := dir * PI / 2.0
	var b := Basis(Vector3.UP, yaw) * Basis().scaled(Vector3(sx, hs, 1.0))
	return Transform3D(b, Vector3(at.x, 0.0, at.y))


## The parts' meshes by name, materials swapped for the stage's. Shared by
## everything that lays parts out.
static func load_parts(names: Array) -> Dictionary:
	var out := {}
	var ps := Models.scene(KIT)
	if ps == null:
		push_warning("Buildings3D: no parts at %s; the town's walls are not drawn" % KIT)
		return out
	var root := ps.instantiate()
	for p in names:
		var n := root.find_child(p, true, false) as MeshInstance3D
		if n == null or n.mesh == null:
			push_warning("Buildings3D: the parts have no '%s'" % p)
			continue
		var mesh: Mesh = n.mesh
		for s in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(s)
			if mat != null and not (mat is ShaderMaterial):
				mesh.surface_set_material(s, FacadeArt.instanced(mat.resource_name))
		out[p] = mesh
	root.free()
	return out


func _place(part: String, items: Array) -> void:
	if items.is_empty() or not _meshes.has(part):
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _meshes[part]
	mm.instance_count = items.size()
	for i in range(items.size()):
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_custom_data(i, FacadeArt.custom_for(plan.styles[items[i][1]]))
	# As `Terrain3D`: the bounds are the town's, or the walls vanish when the
	# unit piece at the origin leaves the view.
	var W := float(Config.WORLD_TILES)
	mm.custom_aabb = AABB(Vector3(-2, 0, -2), Vector3(W + 4, 8, W + 4))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	_mmi[part] = mmi


## A gable roof over a building: two shingled slabs ridged along the longer
## side, overhanging the walls, fascia in trim, the gable ends closed with
## lapped siding boards like the parts'.
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
		var a := _pt(along_x, u0, vc, y_ridge)
		var b := _pt(along_x, u1, vc, y_ridge)
		var c := _pt(along_x, u1, v_out, y_eave)
		var d := _pt(along_x, u0, v_out, y_eave)
		if side > 0:
			_quad(shingle, a, b, c, d)
		else:
			_quad(shingle, b, a, d, c)
		# Shingle courses: a thin strip every half metre down the slope.
		var slope := half + OVERHANG
		var s := 0.3
		while s < slope - 0.1:
			var f0 := s / slope
			var f1 := (s + 0.05) / slope
			var up := Vector3(0, 0.025, 0)
			var p0 := a.lerp(d, f0) + up
			var p1 := b.lerp(c, f0) + up
			var p2 := b.lerp(c, f1) + up
			var p3 := a.lerp(d, f1) + up
			if side > 0:
				_quad(shingle, p0, p1, p2, p3)
			else:
				_quad(shingle, p1, p0, p3, p2)
			s += 0.5
		var down := Vector3(0, -ROOF_T, 0)
		if side > 0:
			_quad(trim, d, c, c + down, d + down)
			_quad(trim, a, d, d + down, a + down)
			_quad(trim, c, b, b + down, c + down)
		else:
			_quad(trim, c, d, d + down, c + down)
			_quad(trim, d, a, a + down, d + down)
			_quad(trim, b, c, c + down, b + down)
	# Gable ends at the wall line: boards shortened row by row, each a
	# little proud at its foot, as the parts' siding is.
	var rise := y_ridge - wall_h
	for end: int in [0, 1]:
		var g := ((x0 if along_x else z0) - 0.02) if end == 0 else ((x0 if along_x else z0) + (w if along_x else h) + 0.02)
		var y := wall_h
		while y < y_ridge - 0.01:
			var top := minf(y + BOARD, y_ridge)
			var hw := half * (1.0 - ((y + top) / 2.0 - wall_h) / rise)
			if hw < 0.05:
				break
			var out := -0.045 if end == 0 else 0.045
			var b0 := _pt(along_x, g + out, vc - hw, y)
			var b1 := _pt(along_x, g + out, vc + hw, y)
			var b2 := _pt(along_x, g, vc + hw, top)
			var b3 := _pt(along_x, g, vc - hw, top)
			if end == 0:
				_quad(siding, b1, b0, b3, b2)
			else:
				_quad(siding, b0, b1, b2, b3)
			y = top
	var mesh := ArrayMesh.new()
	var mats := {"roof": shingle, "trim": trim, "siding": siding}
	for name: String in mats:
		var st: SurfaceTool = mats[name]
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


## A quad a, b, c, d clockwise seen from outside (Godot's front face).
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if _flip:
		var t := b
		b = c
		c = t
	st.set_uv(Vector2.ZERO)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
