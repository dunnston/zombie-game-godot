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

	# People come before things. A survivor bleeding out has eight seconds and
	# a container does not, so neither a shelf nor a gate — nor a car — may
	# ever be what the key offers while someone is down beside you. Somebody
	# who parked next to the person they are trying to save should not have to
	# walk away from the car first.
	var best_person := {}
	var person_d := reach2
	# A teammate first of all: they have thirty seconds, and they are the
	# other half of the game.
	for q in sim.players:
		if q == p or q.away or q.dead or not q.downed:
			continue
		var d: float = p.pos.distance_squared_to(q.pos)
		if d < person_d:
			person_d = d
			best_person = {"kind": "revive_player", "ref": q,
				"label": "Get %s up  (hold — %.0fs left)" % [q.display_name, maxf(0.0, q.down_t)]}
	for s in sim.crew.list:
		if s.dead or not s.downed:
			continue
		var d: float = p.pos.distance_squared_to(s.pos)
		if d < person_d:
			person_d = d
			best_person = {"kind": "revive", "ref": s,
				"label": "Help %s up  (%.0fs)" % [s.display_name, maxf(0.0, s.down_t)]}
	for rescue in sim.crew.rescues:
		var d: float = p.pos.distance_squared_to(rescue.pos)
		if d >= person_d:
			continue
		var why := sim.crew.recruit_refusal(sim)
		person_d = d
		best_person = {"kind": "recruit", "ref": rescue,
			"label": "Take %s in  (level %d)" % [rescue.name, int(rescue.level)] if why.is_empty() else why}
	if not best_person.is_empty():
		return best_person

	# Then a car, ahead of containers: getting in is the thing you walked over
	# here to do, and a shelf beside it can wait. Hold E for the boot.
	var car := sim.cars.nearest(p.pos)
	if not car.is_empty():
		return {"kind": "vehicle", "ref": car, "label": sim.cars.prompt(p, car)}

	var best := {}
	var best_d := reach2
	for c in sim.world.containers:
		if c.looted:
			continue
		var d: float = p.pos.distance_squared_to(Vector2(c.x, c.y))
		if d < best_d:
			best_d = d
			best = {"kind": "container", "ref": c, "label": "Search " + c.label}

	# Anything the player built, and what it has to say for itself. A piece
	# with nothing else to offer offers its repair, with the bill, so nobody
	# is surprised by what it costs.
	for s in sim.structs.list:
		if s.destroyed:
			continue
		var d: float = p.pos.distance_squared_to(s.pos)
		if d >= best_d:
			continue
		var entry := {}
		if s.store != null:
			entry = {"kind": "store", "ref": s, "label": "Open %s  (%d/%d)" % [s.def.name, s.store.used(), s.store.size()]}
		elif s.type == "workbench":
			entry = {"kind": "bench", "ref": s, "label": "Workbench II" if s.tier >= 2 else "Upgrade Workbench  ·  %s" % Structures.cost_label(Config.BENCH_UPGRADE_COST)}
		elif s.type == "gate":
			entry = {"kind": "gate", "ref": s, "label": "Close gate" if s.open else "Open gate"}
		elif s.type == "generator":
			entry = {"kind": "generator", "ref": s,
				"label": "Switch off  (%d/%d fuel)" % [roundi(s.fuel), roundi(s.def.fuel_max)] if Structures.generator_running(s)
					else "Refuel and start  (%d/%d)" % [roundi(s.fuel), roundi(s.def.fuel_max)]}
		elif s.type == "bedroll":
			entry = {"kind": "bedroll", "ref": s,
				"label": "Respawn point (active)" if p.spawn_tile == Vector2i(s.tx, s.ty) else "Set as respawn point"}
		elif Structures.is_damaged(s):
			entry = {"kind": "repair", "ref": s,
				"label": "Repair %s  (%d%%)  ·  %s" % [s.def.name, roundi(s.hp / s.max_hp * 100.0), Structures.cost_label(Structures.repair_cost(s, p.build_cost_mul))]}
		if entry.is_empty():
			continue
		# A piece that answers E for something else still says it is hurt.
		if entry.kind != "repair" and Structures.is_damaged(s):
			entry.label += "  ·  %d%% — B to repair" % roundi(s.hp / s.max_hp * 100.0)
		best_d = d
		best = entry
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
		p.reviving = {}
		return
	var it := p.intent

	# Getting somebody up is a held channel like searching is: two and a half
	# seconds beside them with the key down. They can be dragged out from
	# under you — by dying, or by somebody else finishing first.
	if not p.reviving.is_empty():
		var q := sim.player_by_seat(int(p.reviving.seat))
		var reach: float = Config.PLAYER.interact_range
		var gone: bool = q == null or not q.downed or q.dead or q.away \
			or p.pos.distance_squared_to(q.pos) > reach * reach
		if gone or (not it.interact_held and p.reviving.t > 0.12):
			p.reviving = {}
			return
		p.reviving.t += dt
		if p.reviving.t >= p.reviving.dur:
			p.reviving = {}
			Damage.revive_player(sim, q, p)
		return

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
		"revive":
			sim.crew.revive(sim, target.ref, p)
		"revive_player":
			var q: PlayerSim = target.ref
			p.reviving = {"seat": q.seat, "t": 0.0, "dur": Config.PLAYER.revive_time}
		"recruit":
			sim.crew.recruit(sim, target.ref, p)
		"vehicle":
			var v: Dictionary = target.ref
			if v.destroyed:
				sim.cars.salvage(sim, v, p)
			elif it.interact_held:
				# Hold for the boot, tap to drive — the same tap/hold split a
				# container already uses, so it is a habit rather than a rule.
				sim.emit({"t": "open_boot", "seat": p.seat, "id": int(v.id)})
			else:
				sim.cars.enter(sim, p, v)
		"gate":
			sim.structs.toggle_gate(sim, target.ref)
		"generator":
			sim.structs.use_generator(sim, target.ref, p)
		"bench":
			sim.structs.upgrade_bench(sim, target.ref, p)
		"repair":
			sim.structs.repair(sim, target.ref, p)
		"bedroll":
			var s: Dictionary = target.ref
			p.spawn_tile = Vector2i(s.tx, s.ty)
			sim.structs.refresh_bedrolls(sim)
			sim.notify("Respawn point set", "#b7e08a")
		"store":
			# The sim does not know about screens: it says a container was
			# opened and the presentation decides what that looks like.
			var s: Dictionary = target.ref
			sim.emit({"t": "open_store", "seat": p.seat, "tx": s.tx, "ty": s.ty})


static func _finish_search(sim: GameSim, p: PlayerSim) -> void:
	var c: Dictionary = p.searching.container
	p.searching = {}
	if c.looted:
		return
	c.looted = true
	sim.stats.looted = sim.stats.get("looted", 0) + 1

	var at := Vector2(c.x, c.y)
	var result := Loot.grant_loot(sim, p, Loot.roll_container(sim, c, p.loot_mul, p.rare_loot_mul, p.double_drop_chance), at)
	sim.emit({"t": "loot", "x": at.x, "y": at.y, "lines": result.lines, "major": result.major})
	Progression.add_xp(sim, p, 6 + int(c.rolls[1]) * 3, "LOOT")
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
	Progression.add_xp(sim, p, rule.get("xp", 1), rule.label)
	return true
