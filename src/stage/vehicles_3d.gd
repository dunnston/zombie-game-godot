class_name Vehicles3D
extends Node3D
## Cars, parked and driven, on the 3D stage: a shell and a roof in the car's
## paint, keyed by the car's id, facing where the sim says. A wreck goes
## dark. The words and bars over a car are the overlay's. Headlights are
## `Lights3D`'s, because they are lights.

const HALF_LEN := 26.0
const HALF_W := 13.0

var sim: GameSim
var _nodes := {}   # car id -> {node, shell, roof}


func _init(sim_: GameSim) -> void:
	sim = sim_


func rebuild() -> void:
	for e in _nodes.values():
		e.node.queue_free()
	_nodes.clear()


func frame() -> void:
	var seen := {}
	for v in sim.cars.list:
		seen[v.id] = true
		var e: Dictionary = _nodes.get(v.id, {})
		if e.is_empty():
			e = _make(v)
			_nodes[v.id] = e
		var node: Node3D = e.node
		node.position = Units.to3(Util.render_pos(v.prev_pos, v.pos))
		node.rotation.y = Units.yaw(float(v.angle))
		var body := Color(["#6b5a4a", "#4a5a6b", "#5a6b4a", "#6b4a5a"][int(v.si) % 4])
		if v.destroyed:
			body = Color("#3a352e")
		elif v.flash > 0.0:
			body = body.lerp(Color.WHITE, 0.6)
		(e.shell.material_override as StandardMaterial3D).albedo_color = body
		(e.roof.material_override as StandardMaterial3D).albedo_color = body.darkened(0.25)
	for id in _nodes.keys():
		if not seen.has(id):
			_nodes[id].node.queue_free()
			_nodes.erase(id)


func _make(_v: Dictionary) -> Dictionary:
	var node := Node3D.new()
	add_child(node)
	# The sim's car points along +x at angle 0 and the model's forward is +z,
	# so the long axis lies along z here and `Units.yaw` does the rest.
	var shell := _box(node, Vector3(Units.m(HALF_W) * 2.0, 0.55, Units.m(HALF_LEN) * 2.0), Vector3(0, 0.3, 0))
	var roof := _box(node, Vector3(Units.m(HALF_W) * 1.4, 0.4, Units.m(HALF_LEN)), Vector3(0, 0.75, -0.1))
	return {"node": node, "shell": shell, "roof": roof}


func _box(parent: Node3D, size: Vector3, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = at
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.5
	mi.material_override = mat
	parent.add_child(mi)
	return mi
