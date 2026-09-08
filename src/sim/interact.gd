class_name Interact
extends RefCounted
## What the interact key is offering, and what happens when it is pressed.
##
## One function decides the target so the prompt on screen and the thing the
## key actually does can never disagree. Searching is a held channel: let go,
## or drift out of reach, and it stops.


## The pile, container or piece of scenery `p` would act on, or empty.
##
## Ranking is by distance among the things that compete, with two exceptions.
## Your own dropped pack outranks everything — you came back for it. Gathering
## is offered last and only when nothing else wants the key: litter is
## everywhere by design, so ranking a twig by distance would let it beat the
## container you walked across the room to open.
static func best_target(sim: GameSim, p: PlayerSim) -> Dictionary:
	var reach: float = Config.PLAYER.interact_range
	var reach2 := reach * reach

	var best_pack := {}
	var pack_d := reach2
	for b in sim.backpacks:
		var d: float = p.pos.distance_squared_to(b.pos)
		if d < pack_d:
			pack_d = d
			best_pack = {"kind": "backpack", "ref": b, "label": "Recover your pack"}
	if not best_pack.is_empty():
		return best_pack

	var best := {}
	var best_d := reach2
	for c in sim.world.containers:
		if c.looted:
			continue
		var d: float = p.pos.distance_squared_to(Vector2(c.x, c.y))
		if d < best_d:
			best_d = d
			best = {"kind": "container", "ref": c, "label": "Search " + c.label}
	if not best.is_empty():
		return best

	var prop := _nearest_hand_prop(sim, p, reach)
	if not prop.is_empty():
		var rule: Dictionary = Config.HARVEST.get(prop.harvest, {})
		return {"kind": "gather", "ref": prop, "label": "Gather " + rule.get("label", "SCRAPS").capitalize()}
	return {}


## Hand-gatherable scenery whose tile is within reach: litter, bushes, loose
## rocks. The big scenery is gated behind a tool and answers a swing, not a key.
static func _nearest_hand_prop(sim: GameSim, p: PlayerSim, reach: float) -> Dictionary:
	var tx := floori(p.pos.x / Config.TILE)
	var ty := floori(p.pos.y / Config.TILE)
	var span := ceili(reach / Config.TILE)
	var best := {}
	var best_d := reach * reach
	for y in range(ty - span, ty + span + 1):
		for x in range(tx - span, tx + span + 1):
			var prop := sim.world.prop_at_tile(x, y)
			if prop.is_empty() or not prop.get("hand", false):
				continue
			var d: float = p.pos.distance_squared_to(Vector2(prop.x, prop.y))
			if d < best_d:
				best_d = d
				best = prop
	return best


# -------------------------------------------------------------------- step --

static func tick(sim: GameSim, p: PlayerSim, dt: float) -> void:
	if p.dead:
		p.searching = {}
		return
	var it := p.intent

	if not p.searching.is_empty():
		var c: Dictionary = p.searching.container
		var reach: float = Config.PLAYER.interact_range
		var gone: bool = c.looted or p.pos.distance_squared_to(Vector2(c.x, c.y)) > reach * reach
		# The 0.12s grace is for the press itself: `interact_held` is not true
		# on the frame the tap is consumed by a single physics step.
		if gone or (not it.interact_held and p.searching.t > 0.12):
			p.searching = {}
			return
		p.searching.t += dt
		if p.searching.t >= p.searching.dur:
			_finish_search(sim, p)
		return

	if not it.interact:
		return
	var target := best_target(sim, p)
	if target.is_empty():
		return
	match target.kind:
		"backpack":
			Loot.collect_backpack(sim, p, target.ref)
		"container":
			var c: Dictionary = target.ref
			var rolls := (float(c.rolls[0]) + float(c.rolls[1])) / 2.0
			var dur: float = Config.PLAYER.search_time * p.search_mul * (0.7 + rolls * 0.18)
			p.searching = {"container": c, "t": 0.0, "dur": dur}
		"gather":
			gather_prop(sim, p, target.ref)


static func _finish_search(sim: GameSim, p: PlayerSim) -> void:
	var c: Dictionary = p.searching.container
	p.searching = {}
	if c.looted:
		return
	c.looted = true
	sim.stats.looted = sim.stats.get("looted", 0) + 1

	var at := Vector2(c.x, c.y)
	var result := Loot.grant_loot(sim, p, Loot.roll_container(sim, c, p.loot_mul), at)
	sim.emit({"t": "loot", "x": at.x, "y": at.y, "lines": result.lines, "major": result.major})
	p.xp += 6 + int(c.rolls[1]) * 3
	sim.threat.add(sim, Config.THREAT.per_loot, p)


## Litter, a bush, a loose rock: taken by hand, no tool, no swing.
static func gather_prop(sim: GameSim, p: PlayerSim, prop: Dictionary) -> bool:
	var rule: Dictionary = Config.HARVEST.get(prop.harvest, {})
	if rule.is_empty():
		return false
	var n: int = maxi(1, rule.min + roundi(sim.rng.next() * (rule.max - rule.min) * p.loot_mul))
	sim.world.remove_prop(prop)
	Loot.give_res_or_drop(sim, p, rule.res, n, p.pos)
	sim.emit({"t": "harvest", "x": prop.x, "y": prop.y, "res": rule.res, "n": n, "label": rule.label})
	if rule.has("bonus") and sim.rng.chance(0.5):
		var bonus: int = rule.bonus_min + roundi(sim.rng.next() * (rule.bonus_max - rule.bonus_min))
		Loot.give_res_or_drop(sim, p, rule.bonus, bonus, p.pos)
	p.xp += rule.get("xp", 1)
	return true
