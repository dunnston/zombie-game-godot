class_name Pickups3D
extends Node3D
## Piles on the ground and the packs the dead leave behind, on the 3D stage.
## A pool of small boxes, one per pickup each frame: the list is short and
## its order is nobody's business, so node `i` simply shows pickup `i`.
## Coloured by what they are, bobbing as they always did; the names and
## counts over them are the overlay's.

var sim: GameSim
var _pool: Array[MeshInstance3D] = []
var _packs: Array[MeshInstance3D] = []


func _init(sim_: GameSim) -> void:
	sim = sim_


func frame() -> void:
	var n := sim.pickups.size()
	while _pool.size() < n:
		_pool.append(_box(Vector3(0.28, 0.2, 0.28)))
	for i in range(_pool.size()):
		var node := _pool[i]
		if i >= n:
			node.visible = false
			continue
		var it: Dictionary = sim.pickups[i]
		var bob := sin(it.t * 3.4 + it.bob) * 0.06
		node.visible = true
		node.position = Units.to3(it.pos, 0.12 + bob)
		node.rotation.y = it.t * 0.8
		(node.material_override as StandardMaterial3D).albedo_color = Color(Items.color_of(it.id))
	var m := sim.backpacks.size()
	while _packs.size() < m:
		var b := _box(Vector3(0.5, 0.45, 0.35))
		(b.material_override as StandardMaterial3D).albedo_color = Color("#6b4a2f")
		_packs.append(b)
	for i in range(_packs.size()):
		var node := _packs[i]
		if i >= m:
			node.visible = false
			continue
		node.visible = true
		node.position = Units.to3(sim.backpacks[i].pos, 0.23)


func _box(size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.8
	mi.material_override = mat
	add_child(mi)
	return mi
