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
		var why := sim.crew.recruit_refusal(sim, p)
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

	# Doors that answer the key instead of letting you through: an instance's
	# way in, and inside one the way out, the chained gym and the exit. Ahead
	# of containers, because a cabinet by the door is not why you walked here.
	var door := _door_target(sim, p)
	if not door.is_empty():
		return door

	var best := {}
	var best_d := reach2
	for c in sim.world.containers:
		if c.looted:
			continue
		var d: float = p.pos.distance_squared_to(Vector2(c.x, c.y))
		if d < best_d and _in_sight(sim, p, Vector2(c.x, c.y)):
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
		elif s.type == "workbench" or s.def.has("station"):
			# E opens the bench; it never spends anything. Upgrading is a button
			# inside, with its price on it, rather than the key you press to look.
			entry = {"kind": "bench", "ref": s, "label": "Use %s" % ("Workbench II" if s.type == "workbench" and s.tier >= 2 else s.def.name)}
		elif s.type == "gate":
			entry = {"kind": "gate", "ref": s, "label": "Close gate" if s.open else "Open gate"}
		elif s.type == "generator":
			entry = {"kind": "generator", "ref": s,
				"label": "Switch off  (%d/%d fuel)" % [roundi(s.fuel), roundi(s.def.fuel_max)] if Structures.generator_running(s)
					else "Refuel and start  (%d/%d)" % [roundi(s.fuel), roundi(s.def.fuel_max)]}
		elif Farming.is_bed(s):
			# One key, two jobs, and switching to the useful one takes
			# priority — the same shape `use_generator` already has. A ripe
			# bed harvests where you stand; anything else opens the panel,
			# and `Farming.prompt` is what says which so the two cannot
			# disagree.
			entry = {"kind": "bed", "ref": s, "label": Farming.prompt(s)}
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


## The instance door within reach, and what it has to say for itself. An
## opened chained door and an exit the boss still guards say nothing.
static func _door_target(sim: GameSim, p: PlayerSim) -> Dictionary:
	var f := Instance.feature_near(sim, p, ["instance_door", "leave", "chained", "exit", "breaker"])
	if f.is_empty():
		return {}
	var inst := sim.instance
	var cleared := inst != null and inst.state == "cleared"
	match String(f.kind):
		"instance_door":
			return {"kind": "instance_door", "ref": f, "label": Instance.door_label(sim, p, f)}
		"leave":
			return {"kind": "leave", "ref": f, "label": "Walk out with everything you found" if cleared
				else "Leave — and lose everything you found in here"}
		"chained":
			if f.open:
				return {}
			var has_key: bool = inst != null and inst.keys.get(String(f.key), false)
			return {"kind": "chained", "ref": f, "label": "Unlock the gym" if has_key
				else "Chained shut — the key is somewhere in the school"}
		"exit":
			if not cleared:
				return {}
			return {"kind": "exit", "ref": f, "label": "Walk out with everything you found"}
		"breaker":
			# Only while there is a dark to undo: a switch that always offers
			# itself would outrank the locker beside it for nothing.
			if inst == null or not inst.dark:
				return {}
			return {"kind": "breaker", "ref": f, "label": "Throw the breaker — lights back on"}
	return {}


## Can `p` actually reach `at`, or is there a wall in the way? Reach was
## distance alone, which let a player stand outside a house and empty the
## cabinet on the other side of its wall.
##
## Only tiles *between* the two count. Both ends are excluded on purpose: the
## player is standing in their own tile whatever it holds, and a cabinet is
## itself a solid tile, so a line drawn to its centre would always report a
## wall and nothing would ever be searchable.
##
## Sight uses the rule bullets use, so a fence you can shoot over is a fence you
## can lean across, and a river is not a wall (invariant 3).
static func _in_sight(sim: GameSim, p: PlayerSim, at: Vector2) -> bool:
	var from_t := Vector2i(floori(p.pos.x / Config.TILE), floori(p.pos.y / Config.TILE))
	var to_t := Vector2i(floori(at.x / Config.TILE), floori(at.y / Config.TILE))
	# Anything on the next tile is simply within arm's reach: there is no room
	# for a wall to be *between* two touching tiles, so no line is drawn. This
	# is not a nicety — furniture is placed against walls, and six containers
	# on the default map stand in alcoves whose only standable spot is a
	# diagonal neighbour. Without this they became impossible to open.
	if absi(from_t.x - to_t.x) <= 1 and absi(from_t.y - to_t.y) <= 1:
		return true
	var d := at - p.pos
	var n := maxi(2, ceili(d.length() / 8.0))
	for i in range(1, n):
		var s := p.pos + d * (float(i) / n)
		var t := Vector2i(floori(s.x / Config.TILE), floori(s.y / Config.TILE))
		if t == from_t or t == to_t:
			continue
		if sim.world.bullet_blocks_px(s.x, s.y):
			return false
	return true


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
			if d < best_d and _in_sight(sim, p, Vector2(prop.x, prop.y)):
				best_d = d
				best = prop
	return best


# -------------------------------------------------------------------- step --

static func tick(sim: GameSim, p: PlayerSim, dt: float) -> void:
	if p.dead:
		p.searching = {}
		p.reviving = {}
		p.car_hold = {}
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

	# A car answers the same key twice: a tap drives, a hold opens the boot.
	# The press frame cannot tell them apart — `interact_held` is already true
	# on it — so the decision waits out `boot_hold` instead. Letting go first
	# is the tap, and that is the common case, so it is the one that drives.
	if not p.car_hold.is_empty():
		var v: Dictionary = p.car_hold.car
		var range_: float = Config.CAR.enter_range
		if v.destroyed or p.pos.distance_squared_to(v.pos) > range_ * range_:
			p.car_hold = {}
			return
		p.car_hold.t += dt
		if not it.interact_held:
			p.car_hold = {}
			sim.cars.enter(sim, p, v)
			return
		if p.car_hold.t >= p.car_hold.dur:
			p.car_hold = {}
			# The sim does not know about screens: it says the boot was opened
			# and the presentation decides what that looks like.
			sim.emit({"t": "open_boot", "seat": p.seat, "id": int(v.id)})
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
			else:
				# Hold for the boot, tap to drive — the same tap/hold split a
				# container already uses, so it is a habit rather than a rule.
				# Opening the channel is all the press frame may decide.
				p.car_hold = {"car": v, "t": 0.0, "dur": Config.PLAYER.boot_hold}
		"gate":
			sim.structs.toggle_gate(sim, target.ref)
		"generator":
			sim.structs.use_generator(sim, target.ref, p)
		"bench":
			# The sim does not know about screens: it says a bench was opened
			# and the presentation decides what that looks like.
			var s: Dictionary = target.ref
			sim.emit({"t": "open_bench", "seat": p.seat, "tx": s.tx, "ty": s.ty})
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
		"bed":
			var s: Dictionary = target.ref
			if Farming.ready(s):
				Farming.harvest(sim, p, s)
			else:
				sim.emit({"t": "open_bed", "seat": p.seat, "tx": s.tx, "ty": s.ty})
		"instance_door":
			var f: Dictionary = target.ref
			var why := Instance.refusal(sim, p, String(f.id))
			if not why.is_empty():
				sim.notify(why, "#c96a5a")
			else:
				# The sim does not know about screens: it says the door was
				# offered and the presentation asks whether you mean it.
				sim.emit({"t": "open_instance", "seat": p.seat, "kind": String(f.id)})
		"leave":
			# Nothing to lose once the boss is down, so nothing to confirm.
			# Taken at the end of this step, not now: this is the middle of a
			# player's tick (`Instance.leaving`).
			if sim.instance != null and sim.instance.state == "cleared":
				sim.instance.leaving = "extracted"
			else:
				sim.emit({"t": "open_leave", "seat": p.seat})
		"chained":
			if sim.instance != null:
				sim.instance.unlock(sim, target.ref)
		"exit":
			if sim.instance != null:
				sim.instance.leaving = "extracted"
		"breaker":
			if sim.instance != null:
				sim.instance.lights_on(sim)


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
	# The key an instance hid in this one: a fact the party learns, not an item.
	if c.has("key") and sim.instance != null:
		sim.instance.found_key(sim, String(c.key))
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
