class_name Survivors3D
extends Node3D
## Your people, and the ones still out there, on the 3D stage. A survivor is
## an `ActorModel` capsule in their tint (the owner's survivor models go in
## `Models` when they exist) wearing the job's ring, because the one thing
## that must never happen is shooting one of your own in a crowd (pillar 4).
## A rescue waiting to be found is a dimmer capsule with a pulsing ring.
## Tags, bars and names are the overlay's.

var sim: GameSim
var _nodes := {}            # SurvivorSim -> ActorModel
var _rescues: Array[ActorModel] = []


func _init(sim_: GameSim) -> void:
	sim = sim_


func rebuild() -> void:
	for n in _nodes.values():
		n.queue_free()
	_nodes.clear()
	for n in _rescues:
		n.queue_free()
	_rescues.clear()


func frame() -> void:
	var R := float(Config.SURVIVOR.r)
	var seen := {}
	for s in sim.crew.list:
		if s.dead:
			continue
		seen[s] = true
		var node: ActorModel = _nodes.get(s)
		if node == null:
			node = ActorModel.new()
			node.setup({}, R, 1.65, Color(s.tint))
			var job: Dictionary = Config.JOBS.get(s.job, Config.JOBS.guard)
			node.add_ring(Color(String(job.color), 0.7))
			add_child(node)
			_nodes[s] = node
		node.position = Units.to3(Util.render_pos(s.prev_pos, s.pos))
		node.face(float(s.angle))
		node.lie_down(s.downed)
		if s.flash > 0.0:
			node.tint(Color(1, 1, 1, 0.7))
		elif s.hungry:
			node.tint(Color(0.55, 0.45, 0.2, 0.3))
		else:
			node.tint(Color.TRANSPARENT)
		if node.ring != null:
			var job: Dictionary = Config.JOBS.get(s.job, Config.JOBS.guard)
			(node.ring.material_override as StandardMaterial3D).albedo_color = Color("#e05a4a") if s.downed else Color(String(job.color), 0.7)
	for s in _nodes.keys():
		if not seen.has(s):
			_nodes[s].queue_free()
			_nodes.erase(s)
	var n := sim.crew.rescues.size()
	while _rescues.size() < n:
		var node := ActorModel.new()
		node.setup({}, R * 0.8, 1.5, Color("#6a7a5a"))
		node.add_ring(Color("#b7e08a", 0.55), 1.6)
		add_child(node)
		_rescues.append(node)
	var pulse := 0.5 + 0.5 * sin(sim.time * 2.4)
	for i in range(_rescues.size()):
		var node := _rescues[i]
		if i >= n:
			node.visible = false
			continue
		node.visible = true
		node.position = Units.to3(sim.crew.rescues[i].pos)
		(node.ring.material_override as StandardMaterial3D).albedo_color = Color("#b7e08a", 0.25 + 0.35 * pulse)
