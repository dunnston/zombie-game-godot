class_name Doors3D
extends Node3D
## The doors that answer E instead of letting you through, on the 3D stage:
## an instance's way in, the way out, the chained gym, the exit, the
## breaker. Flat slabs in the 2D colours over the tiles the terrain put
## under them, rebuilt from `sim.world.features` whenever the world is, and
## recoloured each frame for the few that change (a chain comes off, the
## exit opens). Titles and chains are the overlay's. The Target Range's
## floor paint is not drawn here yet (`tasks/3d-conversion.md`).

var sim: GameSim
var _slabs := []   # {feature, mesh, mat}


func _init(sim_: GameSim) -> void:
	sim = sim_


func rebuild() -> void:
	for s in _slabs:
		s.mesh.queue_free()
	_slabs.clear()
	for f in sim.world.features:
		var r := InstanceView._rect(f)
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		var size := Vector2(Units.m(r.size.x), Units.m(r.size.y))
		var h := 0.12
		if String(f.kind) == "breaker":
			size = Vector2(0.6, 0.3)
			h = 0.9
		box.size = Vector3(size.x, h, size.y)
		mi.mesh = box
		var centre := Units.to3(r.get_center(), h / 2.0)
		if String(f.kind) == "breaker":
			centre = Units.to3(Vector2(float(f.x), float(f.y)), h / 2.0)
		mi.position = centre
		var mat := StandardMaterial3D.new()
		mat.roughness = 0.8
		mi.material_override = mat
		add_child(mi)
		_slabs.append({"feature": f, "mesh": mi, "mat": mat})
	frame()


func frame() -> void:
	var inst := sim.instance
	for s in _slabs:
		var f: Dictionary = s.feature
		var col := Color("#5a3d28")
		match String(f.kind):
			"instance_door":
				col = Color("#5a3d28")
			"leave", "range_exit":
				col = Color("#2f4a3a")
			"chained":
				s.mesh.visible = not f.open
				col = Color("#4a3a2a")
			"breaker":
				col = Color("#e05a4a") if (inst != null and inst.dark) else Color("#3a3f44")
			"exit":
				col = Color("#2f6a3a") if (inst != null and inst.state == "cleared") else Color("#26262a")
		(s.mat as StandardMaterial3D).albedo_color = col
