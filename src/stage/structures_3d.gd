class_name Structures3D
extends Node3D
## Everything the player has built, on the 3D stage, plus the build-mode
## ghost. A piece with a model in `Models.STRUCTURE_MODELS` is that model
## fitted to its tiles; one without is a box in `StructureView.COLORS` at a
## height from `HEIGHTS`. Damage darkens a box and a hit lights it, as the
## street always did; the bars and the words over a piece are the overlay's.
##
## Diffed against `sim.structs.list` every frame, keyed by tile: a few
## hundred dictionary reads, which is cheaper than being told.

## Metres tall, by type; `wall` pieces take `wall`, the rest `default`.
const HEIGHTS := {
	"wall": 2.0, "gate": 1.9, "gate_open": 0.25, "spike": 0.3, "bedroll": 0.18,
	"floodlight": 2.6, "watchtower": 3.4, "turret": 1.0, "generator": 1.0,
	"raisedBed": 0.35, "longBed": 0.35, "default": 0.9,
}

var sim: GameSim
var build_bar: BuildBar
var _nodes := {}        # Vector2i tile -> {node, mesh, type, open, mat}
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D


func _init(sim_: GameSim) -> void:
	sim = sim_
	_ghost = MeshInstance3D.new()
	_ghost.mesh = BoxMesh.new()
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = _ghost_mat
	_ghost.visible = false
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)


func rebuild() -> void:
	for e in _nodes.values():
		e.node.queue_free()
	_nodes.clear()


func frame() -> void:
	var seen := {}
	for s in sim.structs.list:
		if s.destroyed:
			continue
		var key := Vector2i(s.tx, s.ty)
		seen[key] = true
		var open: bool = s.type == "gate" and s.open
		var e: Dictionary = _nodes.get(key, {})
		if e.is_empty() or e.type != s.type or e.open != open or int(e.rot) != int(s.get("rot", 0)):
			if not e.is_empty():
				e.node.queue_free()
			e = _make(s, open)
			_nodes[key] = e
		_update(e, s)
	for key in _nodes.keys():
		if not seen.has(key):
			_nodes[key].node.queue_free()
			_nodes.erase(key)
	_frame_ghost()


func _make(s: Dictionary, open: bool) -> Dictionary:
	var rot := int(s.get("rot", 0))
	var f := Structures.footprint(s.type, rot)
	var size := Vector2(f.x, f.y)
	var centre := Vector3(s.tx + size.x / 2.0, 0.0, s.ty + size.y / 2.0)
	var node := Node3D.new()
	node.position = centre
	add_child(node)
	var e := {"node": node, "type": s.type, "open": open, "rot": rot, "mesh": null, "mat": null, "model": null}
	var path := String(Models.STRUCTURE_MODELS.get(s.type, ""))
	var model: Node3D = StaticModel.fit(path, size) if not open else null
	if model != null:
		node.add_child(model)
		e.model = model
		return e
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	var h := _height(s, open)
	box.size = Vector3(size.x - 0.06, h, size.y - 0.06)
	mesh.mesh = box
	mesh.position.y = h / 2.0
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.9
	mesh.material_override = mat
	node.add_child(mesh)
	e.mesh = mesh
	e.mat = mat
	return e


func _height(s: Dictionary, open: bool) -> float:
	if open:
		return float(HEIGHTS.gate_open)
	if s.def.get("wall", false):
		return float(HEIGHTS.wall)
	return float(HEIGHTS.get(s.type, HEIGHTS.default))


func _update(e: Dictionary, s: Dictionary) -> void:
	var frac: float = s.hp / s.max_hp
	var dark := (1.0 - frac) * StructureView.DAMAGE_DARKEN
	if e.type == "turret":
		(e.node as Node3D).rotation.y = Units.yaw(float(s.aim))
	if e.mat != null:
		var body := Color(StructureView.COLORS.get(s.type, "#8a8f84")).lerp(StructureView.DAMAGE_TINT, dark)
		if s.flash > 0.0:
			body = body.lerp(Color.WHITE, 0.6)
		if e.type == "turret" and not s.powered:
			body = body.darkened(0.4)
		(e.mat as StandardMaterial3D).albedo_color = body


func _frame_ghost() -> void:
	if build_bar == null or not build_bar.placing():
		_ghost.visible = false
		return
	var t := build_bar.hover_tile
	var card := build_bar.selected_card()
	var rot := build_bar.rot_for(card)
	var f := Vector2i.ONE
	if Config.STRUCTURES.has(card):
		f = Structures.footprint(card, rot)
	var h := 0.6
	if Config.STRUCTURES.has(card):
		var def: Dictionary = Config.STRUCTURES[card]
		h = float(HEIGHTS.wall) if def.get("wall", false) else float(HEIGHTS.get(card, HEIGHTS.default))
	var box := _ghost.mesh as BoxMesh
	box.size = Vector3(f.x, h, f.y)
	_ghost.position = Vector3(t.x + f.x / 2.0, h / 2.0, t.y + f.y / 2.0)
	var ok: bool = build_bar.check.ok
	_ghost_mat.albedo_color = Color("#9fd07a", 0.35) if ok else Color("#c8423a", 0.35)
	_ghost.visible = true
