class_name NetGuest
extends RefCounted
## The guest session. This machine does not run the world; it keeps a
## *mirror* of the one the host describes and sends back what its player
## wants to do.
##
## The mirror is an ordinary `GameSim` — built through the same load path a
## save uses, then never ticked. Snapshots land in its entity lists and
## events land in its `events`, so every view draws it exactly as it draws
## the host's. Own movement is predicted with the same `PlayerSim.move()`
## the host runs, then pulled toward the host's answer. Everything else eases
## toward its last reported place. Anything that changes shared state goes to
## the host as a command (`Actions`) and comes back as a diff.

var link: NetLink
var sim: GameSim = null
var me: PlayerSim = null
var identity := ""
var my_name := ""
var host_name := ""
## "connecting", "joined", "rejected", "lost".
var status := "connecting"
var reason := ""
var seq := 0
var last_snap_seq := -1
var wait_t := 0.0
## The host's answer for where I am, reconciled in `tick`.
var _auth := Vector2.INF
## Everything that eases: {obj, pos, angle} rebuilt by each snapshot.
var _targets: Array[Dictionary] = []
var _was_dead := false
var _was_down := false
var _level := 0
var _rng := Rng.new(0xC11E47)
## Set when a world diff changed something the renderers cache (a prop
## felled); the scene clears it after rebuilding them.
var world_dirty := false
var stats := {"sent": 0, "received": 0, "snaps": 0}
## Tests only: a world to mirror into instead of generating one per join.
static var reuse_world: World = null


## `into` is the GameSim the mirror is built in — the scene's own, so every
## view keeps the reference it already holds. Null makes a fresh one.
var _into: GameSim = null


func _init(link_: NetLink, identity_: String, name_: String, pw_hash := "", into: GameSim = null) -> void:
	link = link_
	identity = identity_
	my_name = name_
	_into = into
	_send(NetProtocol.RELIABLE, NetProtocol.msg_hello(identity, name_, pw_hash))


func joined() -> bool:
	return status == "joined" and sim != null and me != null


func _send(channel: int, m: Dictionary) -> void:
	var bytes := NetProtocol.encode(m)
	stats.sent += bytes.size()
	link.send(channel, bytes)


func send_cmd(name_: String, args: Dictionary) -> void:
	_send(NetProtocol.RELIABLE, NetProtocol.msg_cmd(name_, args))


## Leaving on purpose. The mirror is a stale copy of somebody else's world
## and must never carry on as a solo game, nor be saved.
func leave() -> void:
	if link.is_open():
		_send(NetProtocol.RELIABLE, NetProtocol.msg_bye())
	link.close()
	if status == "joined" or status == "connecting":
		status = "lost"
		reason = "left"


# --------------------------------------------------------------- incoming --

func poll() -> void:
	# What arrived is read before the line's state is judged: a refusal is
	# followed by the host hanging up, and the reason must not be lost to
	# the hang-up.
	_read()
	if not link.is_open() and status != "rejected" and status != "lost":
		status = "lost"
		reason = "the host closed the connection" if reason.is_empty() else reason


func _read() -> void:
	for m in link.receive():
		var bytes: PackedByteArray = m[1]
		stats.received += bytes.size()
		var msg := NetProtocol.decode(bytes)
		if msg.is_empty():
			continue
		var t := String(msg.t)
		if status == "connecting":
			if t == "welcome":
				_welcome(msg)
			elif t == "reject":
				status = "rejected"
				reason = String(msg.get("reason", "refused"))
				link.close()
			continue
		if status != "joined":
			continue
		match t:
			"snap":
				_on_snapshot(msg)
			"ev":
				_on_event(msg.get("e", {}))
			"inv":
				NetProtocol.apply_inventory(me, msg.get("rec", {}))
			"stores":
				_on_stores(msg.get("list", []))
			"world":
				_on_world(msg)
			"bye":
				status = "lost"
				reason = "the host ended the game"
				link.close()


func _welcome(m: Dictionary) -> void:
	var fresh := _into if _into != null else GameSim.new()
	var r := SaveGame.apply(fresh, m.get("world", {}), reuse_world)
	if not r.ok:
		status = "rejected"
		reason = NetProtocol.OUT_OF_DATE + " (" + r.reason + ")"
		link.close()
		return
	sim = fresh
	sim.view_radius = Config.NET.guest_view_radius
	host_name = String(m.get("host", "Host"))
	_apply_roster(m.get("roster", []))
	me = sim.player_by_seat(int(m.get("seat", -1)))
	if me == null:
		status = "rejected"
		reason = "the host did not include your character"
		link.close()
		return
	me.away = false
	me.god_mode = false
	# Somebody else's horde: the payload carries none, and the first snapshot
	# fills the list in.
	sim.enemies.list.clear()
	sim.events.clear()
	_was_dead = me.dead
	_was_down = me.downed
	_level = me.level
	status = "joined"
	sim.notify("Joined %s's game" % host_name, "#9fd0ff", true)


## Keeps the mirror's players lined up with the host's roster: seats, names,
## who is away. A seat the mirror has never seen becomes a player.
func _apply_roster(roster: Array) -> void:
	for r in roster:
		if not (r is Dictionary):
			continue
		var seat := int(r.get("n", -1))
		var p := sim.player_by_seat(seat)
		if p == null:
			p = PlayerSim.new()
			p.seat = seat
			var anchor := me if me != null else sim.host()
			p.pos = anchor.pos if anchor != null else Vector2.ZERO
			p.prev_pos = p.pos
			sim.players.append(p)
		p.display_name = String(r.get("name", p.display_name))
		p.identity = String(r.get("id", ""))
		p.away = bool(r.get("aw", false))


func _on_event(ev: Dictionary) -> void:
	if ev.is_empty() or not ev.has("t"):
		return
	var t := String(ev.t)
	match t:
		"shot":
			_spawn_tracer(ev)
		"kill":
			# The host's list of corpses is not sent; one arrives here per kill.
			sim.enemies.corpses.append({"x": float(ev.x), "y": float(ev.y), "angle": _rng.frange(0.0, TAU),
				"type": String(ev.get("type", "walker")), "t": 0.0, "life": 45.0})
			if sim.enemies.corpses.size() > 90:
				sim.enemies.corpses.pop_front()
	sim.events.append(ev)


## A round the host fired, drawn here for the picture only: the host decides
## every hit. Pellets two through eight carry no weapon; they fly like the
## first one.
func _spawn_tracer(ev: Dictionary) -> void:
	var w: Dictionary = Config.WEAPONS.get(String(ev.get("w", "")), {})
	var speed: float = float(w.get("speed", 1000.0))
	var life: float = float(w.get("life", 0.5))
	var color := "#c8a878" if w.get("bow", false) else ("#ffd08a" if String(w.get("id", "")) == "shotgun" else "#ffe6a8")
	var at := Vector2(float(ev.x), float(ev.y))
	sim.bullets.append({"pos": at, "prev": at, "vel": Vector2.from_angle(float(ev.a)) * speed,
		"dmg": 0.0, "life": life, "knock": 0.0, "pierce": 0, "hits": [], "owner": "remote",
		"crit": false, "w": String(ev.get("w", "")), "color": color})


func _on_stores(list: Array) -> void:
	for rec in list:
		if not (rec is Dictionary):
			continue
		var slots: Array = rec.get("slots", [])
		var car := int(rec.get("car", 0))
		if car > 0:
			var v := sim.cars.by_id(car)
			if not v.is_empty():
				v.trunk.from_record(slots)
			continue
		var tx := int(rec.get("tx", -1))
		if tx < 0:
			if sim.stash == null:
				sim.stash = Slots.new(Config.STASH_SLOTS)
			sim.stash.from_record(slots)
			continue
		var s := sim.structs.at_tile(tx, int(rec.get("ty", -1)))
		if not s.is_empty() and s.store != null:
			s.store.from_record(slots)


func _on_world(d: Dictionary) -> void:
	for rec in d.get("structs", []):
		_upsert_structure(rec)
	for g in d.get("gone", []):
		var s := sim.structs.at_tile(int(g[0]), int(g[1]))
		if not s.is_empty():
			_remove_structure(s)
	if d.has("looted"):
		var by_tile := {}
		for c in sim.world.containers:
			by_tile["%d,%d" % [c.tx, c.ty]] = c
		for key in d.looted:
			var c: Dictionary = by_tile.get(String(key), {})
			if not c.is_empty():
				c.looted = true
	for key in d.get("chopped", []):
		var parts: PackedStringArray = String(key).split(",")
		if parts.size() != 2:
			continue
		var prop := sim.world.prop_at_tile(int(parts[0]), int(parts[1]))
		if not prop.is_empty():
			sim.world.remove_prop(prop)
			world_dirty = true
	if d.has("discovered"):
		for l in sim.world.locations:
			if String(l.id) in d.discovered:
				l.discovered = true
	if d.has("rescues"):
		sim.crew.rescues.clear()
		for r in d.rescues:
			sim.crew.rescues.append({"pos": Vector2(float(r[0]), float(r[1])), "name": String(r[2]), "level": int(r[3])})
	if d.has("roster"):
		_apply_roster(d.roster)
	if d.has("bench"):
		sim.structs.bench_tier = int(d.bench)


func _upsert_structure(rec: Dictionary) -> void:
	var type := String(rec.get("tp", ""))
	if not Config.STRUCTURES.has(type):
		return
	var tx := int(rec.get("tx", -1))
	var ty := int(rec.get("ty", -1))
	var s := sim.structs.at_tile(tx, ty)
	if not s.is_empty() and s.type != type:
		_remove_structure(s)
		s = {}
	if s.is_empty():
		s = sim.structs.make(sim, type, tx, ty)
	s.max_hp = float(rec.get("mh", s.max_hp))
	s.hp = minf(float(rec.get("hp", s.max_hp)), s.max_hp)
	s.open = bool(rec.get("op", false))
	s.tier = int(rec.get("tr", 1))
	s.fuel = float(rec.get("fu", 0.0))
	s.ammo = int(rec.get("am", 0))
	s.on = bool(rec.get("on", true))
	s.active = bool(rec.get("ac", false))
	s.running = bool(rec.get("rn", false))
	s.powered = bool(rec.get("pw", false))
	s.starved = bool(rec.get("st", false))
	s.aim = float(rec.get("aim", 0.0))
	s.arm = String(rec.get("arm", ""))
	s.seed = String(rec.get("sd", ""))
	s.fert = String(rec.get("ft", ""))
	s.water = float(rec.get("wt", 0.0))
	s.grow = float(rec.get("gr", 0.0))
	if bool(rec.get("fl", false)):
		s.flash = 0.12


## Gone from the host's map. Not `destroy`: that spills the store and shakes
## the screen, and the host already did both and sent the events.
func _remove_structure(s: Dictionary) -> void:
	s.destroyed = true
	sim.structs._unlink(s)
	sim.world_version += 1


# -------------------------------------------------------------- snapshots --

func _on_snapshot(m: Dictionary) -> void:
	var q := int(m.get("q", 0))
	if q < last_snap_seq:
		return                                  # late packet
	last_snap_seq = q
	stats.snaps += 1
	_targets.clear()

	# The clock and the meters. `time` only snaps when it has drifted: the
	# views animate off it, and stepping it at 20Hz would judder every pulse.
	var tm := float(m.get("tm", sim.time))
	if absf(tm - sim.time) > 0.5:
		sim.time = tm
	sim.clock.day = int(m.get("day", sim.clock.day))
	sim.clock.t = float(m.get("dt", sim.clock.t))
	sim.clock.phase = String(DayNight.phase_at(sim.clock.t).id)
	sim.threat.value = float(m.get("th", 0.0))
	sim.threat.tier = Threat.tier_of(sim.threat.value)
	sim.raids_done = int(m.get("rd", 0))
	sim.structs.bench_tier = int(m.get("bt", sim.structs.bench_tier))
	sim.stats.kills = int(m.get("kills", 0))
	var raid: Dictionary = m.get("raid", {})
	if raid.is_empty():
		sim.raid = null
	else:
		if sim.raid == null:
			sim.raid = Raid.new()
		sim.raid.phase = String(raid.get("ph", "warning"))
		sim.raid.wave = int(raid.get("w", 0))
		sim.raid.spec = {"name": String(raid.get("nm", "RAID")), "waves": int(raid.get("ws", 1))}
		sim.raid.killed = int(raid.get("k", 0))
		sim.raid.total = int(raid.get("tot", 0))
		sim.raid.timer = float(raid.get("tmr", 0.0))
		sim.raid.centre = Vector2(float(raid.get("cx", 0)), float(raid.get("cy", 0)))
		sim.raid.has_base = bool(raid.get("hb", false))
		sim.raid.human = bool(raid.get("hu", false))

	for pr in m.get("pl", []):
		_apply_player(pr)
	_apply_enemies(m.get("en", PackedFloat32Array()))
	_apply_pickups(m.get("pk", PackedFloat32Array()))
	_apply_vehicles(m.get("vh", PackedFloat32Array()))
	_apply_fires(m.get("fr", PackedFloat32Array()))
	_apply_survivors(m.get("sv", []))
	sim.backpacks.clear()
	for b in m.get("bp", []):
		sim.backpacks.append({"pos": Vector2(float(b[1]), float(b[2])), "held": {}, "mag": {}, "wear": {}, "t": 0.0, "seat": int(b[0])})


func _apply_player(pr: Dictionary) -> void:
	var n: PackedFloat32Array = pr.get("n", PackedFloat32Array())
	var strs: PackedStringArray = pr.get("s", PackedStringArray())
	if n.size() < NetProtocol.PL_STRIDE or strs.size() < 3:
		return
	var p := sim.player_by_seat(int(n[NetProtocol.PL_SEAT]))
	if p == null:
		return
	var f := int(n[NetProtocol.PL_FLAGS])
	# The meter first, because a band change rebuilds this player's stats and
	# the numbers the host is sending — health, its ceiling — have to be what
	# survives that. The band is what makes a guest at FERAL predict its own
	# footsteps at the speed the host is actually giving it.
	p.mutation = n[NetProtocol.PL_MUT]
	Mutation.sync_band(p)
	Mutation.unpack_effects(p, strs[3] if strs.size() > 3 else "")
	p.hp = n[NetProtocol.PL_HP]
	p.max_hp = n[NetProtocol.PL_MAX_HP]
	p.stam = n[NetProtocol.PL_STAM]
	p.max_stam = n[NetProtocol.PL_MAX_STAM]
	p.dead = bool(f & NetProtocol.PF_DEAD)
	p.downed = bool(f & NetProtocol.PF_DOWNED)
	p.away = bool(f & NetProtocol.PF_AWAY)
	p.winded = bool(f & NetProtocol.PF_WINDED)
	p.lit = bool(f & NetProtocol.PF_LIT)
	p.light_on = p.lit
	p.down_t = n[NetProtocol.PL_DOWN_T]
	p.respawn_t = n[NetProtocol.PL_RESPAWN_T]
	p.driving_id = int(n[NetProtocol.PL_DRIVING])
	p.level = int(n[NetProtocol.PL_LEVEL])
	p.xp = n[NetProtocol.PL_XP]
	p.xp_next = int(n[NetProtocol.PL_XP_NEXT])
	p.skill_points = int(n[NetProtocol.PL_SKILL])
	p.invuln = 0.1 if f & NetProtocol.PF_INVULN else 0.0
	# Mid-Lurch the host is driving this body. Kept as a real number rather
	# than a bool so the views and the prediction check below read the same
	# field they do in solo.
	p.lurch_t = 0.2 if f & NetProtocol.PF_LURCH else 0.0
	p.hurt_flash = maxf(p.hurt_flash, 0.2) if f & NetProtocol.PF_HURT else 0.0
	p.light_fuel = n[NetProtocol.PL_LIGHT_FUEL]
	var held := strs[0]
	# Whatever channel is running, as one bar. These are read by the views
	# and by nothing else on a guest, so the dictionaries only need the
	# fields the views look at.
	var ch := n[NetProtocol.PL_CHANNEL]
	var ck := strs[2]
	p.searching = {"container": _nearest_container_label(p), "t": ch, "dur": 1.0} if ck == "s" else {}
	p.using = {"id": "bandage", "t": ch, "dur": 1.0} if ck == "u" else {}
	p.reviving = {"seat": -1, "t": ch, "dur": 1.0} if ck == "r" else {}
	p.reloading = {"w": held, "t": ch, "dur": 1.0, "shell": false} if ck == "l" else {}
	var at := Vector2(n[NetProtocol.PL_X], n[NetProtocol.PL_Y])
	var angle := n[NetProtocol.PL_ANGLE]
	var slot := int(n[NetProtocol.PL_SLOT])
	if p == me:
		_auth = at
		if p.slot != slot:
			p.slot = slot
		if p.downed and not _was_down:
			sim.notify("YOU ARE DOWN — a teammate can get you up", "#e05a4a", true)
		if p.dead and not _was_dead:
			sim.notify("YOU DIED — your pack is where you fell", "#e05a4a", true)
		if not p.dead and _was_dead:
			sim.notify("Respawned", "#9fd0ff", true)
		if p.level > _level and _level > 0:
			sim.notify("LEVEL %d — %d skill point%s to spend" % [p.level, p.skill_points, "" if p.skill_points == 1 else "s"], "#ffe08a", true)
		_was_down = p.downed
		_was_dead = p.dead
		_level = p.level
		# No prediction while dead, down, driving or lurching: the host owns
		# you. A guest predicting its own footsteps through a Lurch would
		# fight the host for a second and a half and lose, visibly.
		if p.dead or p.downed or p.driving_id > 0 or p.lurch_t > 0.0:
			p.prev_pos = at
			p.pos = at
			p.angle = angle
		return
	# Everyone else: what they hold, so the right weapon is drawn, and the
	# off-hand, so their torch lights your screen too.
	p.slot = slot
	if p.slot >= 0 and p.slot < p.hotbar.size():
		p.hotbar.slots[p.slot] = {"id": held, "n": 1} if not held.is_empty() else {}
	p.equip["offhand"] = strs[1]
	p.sneaking = bool(f & NetProtocol.PF_SNEAK)
	p.sprinting = bool(f & NetProtocol.PF_SPRINT)
	if f & NetProtocol.PF_SWING:
		if p.swing.is_empty():
			var w := p.weapon()
			p.swing = {"t": 0.0, "dur": 0.2, "angle": angle, "arc": float(w.get("arc", 1.0)), "range": float(w.get("range", 40.0)) + p.r}
	else:
		p.swing = {}
	if at.distance_squared_to(p.pos) > 400.0 * 400.0 or p.away:
		p.pos = at
		p.prev_pos = at
	_targets.append({"obj": p, "pos": at, "angle": angle})


func _nearest_container_label(p: PlayerSim) -> Dictionary:
	var best := {"label": "…"}
	var bd := INF
	for c in sim.world.containers:
		var d: float = p.pos.distance_squared_to(Vector2(c.x, c.y))
		if d < bd:
			bd = d
			best = c
	return best


func _apply_enemies(en: PackedFloat32Array) -> void:
	var by_id := {}
	for e in sim.enemies.list:
		by_id[e.id] = e
	var seen := {}
	var types := NetProtocol.enemy_types()
	var S := NetProtocol.EN_STRIDE
	var i := 0
	while i + S <= en.size():
		var id := int(en[i])
		var ti := int(en[i + 1])
		var at := Vector2(en[i + 2], en[i + 3])
		var e: EnemySim = by_id.get(id, null)
		if e == null and ti >= 0 and ti < types.size():
			e = EnemySim.new(types[ti], at)
			e.id = id
			e.anim = _rng.frange(0.0, TAU)
			sim.enemies.list.append(e)
			by_id[id] = e
		if e != null:
			seen[id] = true
			var f := int(en[i + 7])
			e.hp = en[i + 5]
			e.max_hp = en[i + 6]
			e.r = en[i + 8]
			e.aggro = bool(f & NetProtocol.EF_AGGRO)
			e.raid = bool(f & NetProtocol.EF_RAID)
			e.burn_t = 1.0 if f & NetProtocol.EF_BURN else 0.0
			e.windup = 0.3 if f & NetProtocol.EF_WINDUP else 0.0
			# A nominal clock each, the same trick the burn above uses: the
			# host owns the real one, and all the view asks is whether it is
			# above zero.
			e.stagger_t = 0.3 if f & NetProtocol.EF_STAGGER else 0.0
			e.bleed_t = 1.0 if f & NetProtocol.EF_BLEED else 0.0
			if f & NetProtocol.EF_FLASH:
				e.flash = 0.11
			if at.distance_squared_to(e.pos) > 300.0 * 300.0:
				e.pos = at
				e.prev_pos = at
			_targets.append({"obj": e, "pos": at, "angle": en[i + 4]})
		i += S
	for j in range(sim.enemies.list.size() - 1, -1, -1):
		if not seen.has(sim.enemies.list[j].id):
			sim.enemies.list.remove_at(j)


func _apply_pickups(pk: PackedFloat32Array) -> void:
	var by_uid := {}
	for it in sim.pickups:
		by_uid[int(it.uid)] = it
	var seen := {}
	var ids := NetProtocol.item_ids()
	var S := NetProtocol.PK_STRIDE
	var i := 0
	while i + S <= pk.size():
		var uid := int(pk[i])
		var at := Vector2(pk[i + 1], pk[i + 2])
		var kind_i := int(pk[i + 3])
		var item_i := int(pk[i + 4])
		var it: Dictionary = by_uid.get(uid, {})
		if it.is_empty() and kind_i >= 0 and item_i >= 0 and item_i < ids.size():
			it = {"uid": uid, "pos": at, "kind": NetProtocol.PICKUP_KINDS[kind_i], "id": ids[item_i],
				"n": int(pk[i + 5]), "vel": Vector2.ZERO, "t": 0.0, "bob": _rng.frange(0.0, TAU),
				"life": 600.0, "inert_for": null}
			sim.pickups.append(it)
			by_uid[uid] = it
		if not it.is_empty():
			seen[uid] = true
			it.n = int(pk[i + 5])
			_targets.append({"obj": it, "pos": at, "angle": INF})
		i += S
	for j in range(sim.pickups.size() - 1, -1, -1):
		if not seen.has(int(sim.pickups[j].uid)):
			sim.pickups.remove_at(j)


func _apply_vehicles(vh: PackedFloat32Array) -> void:
	var S := NetProtocol.VH_STRIDE
	var i := 0
	while i + S <= vh.size():
		var v := sim.cars.by_id(int(vh[i]))
		if not v.is_empty():
			var at := Vector2(vh[i + 1], vh[i + 2])
			var f := int(vh[i + 7])
			var was_on: bool = v.engine_on
			v.speed = vh[i + 4]
			v.hp = vh[i + 5]
			v.fuel = vh[i + 6]
			v.destroyed = bool(f & NetProtocol.VF_DESTROYED)
			v.engine_on = bool(f & NetProtocol.VF_ENGINE)
			v.locked = bool(f & NetProtocol.VF_LOCKED)
			v.hotwired = bool(f & NetProtocol.VF_HOTWIRED)
			if f & NetProtocol.VF_FLASH:
				v.flash = 0.1
			# A car with its engine on has released its tiles on the host; a
			# parked one blocks them. The mirror's collision has to agree, or
			# a guest's own prediction walks through a parked car.
			if v.engine_on and not was_on:
				sim.cars.release_tiles(sim, v)
			if not v.engine_on and was_on:
				v.pos = at
				v.prev_pos = at
				v.angle = vh[i + 3]
				sim.cars.occupy_tiles(sim, v)
			if at.distance_squared_to(v.pos) > 200.0 * 200.0:
				v.pos = at
				v.prev_pos = at
				v.angle = vh[i + 3]
			if v.engine_on:
				_targets.append({"obj": v, "pos": at, "angle": vh[i + 3]})
		i += S


## Burning scenery, for drawing only. `t` counts up to `life`, as the light
## view expects; the host owns the spread and the damage.
func _apply_fires(fr: PackedFloat32Array) -> void:
	sim.fire.list.clear()
	var S := NetProtocol.FR_STRIDE
	var i := 0
	while i + S <= fr.size():
		sim.fire.list.append({"prop": {}, "pos": Vector2(fr[i], fr[i + 1]), "t": 1.0 - fr[i + 2], "life": 1.0, "spread_t": 0.0})
		i += S


func _apply_survivors(sv: Array) -> void:
	var by_id := {}
	for s in sim.crew.list:
		by_id[s.id] = s
	var seen := {}
	for r in sv:
		if not (r is Dictionary):
			continue
		var id := int(r.get("id", -1))
		var at := Vector2(float(r.x), float(r.y))
		var s: SurvivorSim = by_id.get(id, null)
		if s == null:
			s = SurvivorSim.new(at, String(r.get("nm", "Survivor")), int(r.get("lv", 1)))
			s.id = id
			sim.crew.list.append(s)
			by_id[id] = s
		seen[id] = true
		s.display_name = String(r.get("nm", s.display_name))
		s.level = int(r.get("lv", s.level))
		s.hp = float(r.get("hp", s.hp))
		s.max_hp = float(r.get("mh", s.max_hp))
		s.downed = bool(r.get("dn", false))
		s.down_t = float(r.get("dt", 0.0))
		s.job = String(r.get("j", s.job))
		s.hungry = bool(r.get("hg", false))
		s.out_of_ammo = bool(r.get("oa", false))
		s.posted = bool(r.get("ps", false))
		s.tint = String(r.get("tn", s.tint))
		s.flash = 0.1 if bool(r.get("fl", false)) else 0.0
		s.carrying = {"x": 1} if bool(r.get("cg", false)) else {}
		var tx := int(r.get("tx", -1))
		s.tower = sim.structs.at_tile(tx, int(r.get("ty", -1))) if tx >= 0 else {}
		if at.distance_squared_to(s.pos) > 300.0 * 300.0:
			s.pos = at
			s.prev_pos = at
		_targets.append({"obj": s, "pos": at, "angle": float(r.get("a", s.angle))})
	for j in range(sim.crew.list.size() - 1, -1, -1):
		if not seen.has(sim.crew.list[j].id):
			sim.crew.list.remove_at(j)


# ------------------------------------------------------------- per step --

## One fixed step on a guest: send intent, predict self, ease everyone else.
## `me.intent` has been filled by the keyboard (or by nobody, while a menu is
## up: then `idle` sends "holding nothing", because silence would leave the
## last intent standing until the host's timeout and a paused player must
## stop the instant they pause).
func tick(dt: float, idle := false) -> void:
	if not joined():
		wait_t += dt
		if status == "connecting" and wait_t > Config.NET.hello_timeout:
			status = "lost"
			reason = "the host did not answer"
			link.close()
		return
	sim.time += dt
	if idle:
		NetProtocol.clear_intent(me.intent)
	seq += 1
	# Held state every step on the unreliable channel; a press, on the step
	# it happens, on the reliable one — a dropped datagram must not swallow
	# a gate toggle, and a duplicated one must not toggle it twice.
	if NetProtocol.has_edges(me.intent):
		_send(NetProtocol.RELIABLE, NetProtocol.msg_edges(seq, me.intent))
	_send(NetProtocol.STATE, NetProtocol.msg_intent(seq, me.intent, false))
	me.prev_pos = me.pos
	_predict_self(dt)
	# Edges were sent once; the host consumes them after one step and so
	# does the mirror.
	me.intent.clear_edges()
	_ease(dt)
	_advance_cosmetics(dt)


## Own movement with the host's code, then a lean toward the host's answer:
## a snap past `snap_over`, a lerp inside it. Nothing here deals damage or
## spends anything.
func _predict_self(dt: float) -> void:
	if me.dead or me.downed or me.away:
		return
	if me.driving_id > 0:
		var v := sim.cars.by_id(me.driving_id)
		if not v.is_empty():
			me.pos = v.pos
			me.angle = v.angle
		return
	me.last_hurt += dt
	me.attack_cd = maxf(0.0, me.attack_cd - dt)
	me.invuln = maxf(0.0, me.invuln - dt)
	me.hurt_flash = maxf(0.0, me.hurt_flash - dt)
	me.angle = atan2(me.intent.aim.y - me.pos.y, me.intent.aim.x - me.pos.x)
	# The hotbar answers at once; the host's echo agrees a round trip later.
	if me.intent.slot >= 0:
		me.select_slot(me.intent.slot)
	if me.intent.wheel != 0:
		me.cycle_slot(me.intent.wheel)
	_predict_swing(dt)
	var rooted := not me.using.is_empty() or not me.reviving.is_empty()
	me.move(sim.world, dt, rooted, sim.structs)
	if _auth != Vector2.INF:
		var err := _auth.distance_to(me.pos)
		if err > Config.NET.snap_over:
			me.pos = _auth
		elif err > 0.5:
			me.pos = me.pos.lerp(_auth, Util.smooth(Config.NET.lerp_rate, dt))


## A guest swings its own weapon locally, for the picture only. Waiting for
## the host to say so would arrive late at 20Hz and stutter; the host still
## decides every hit.
func _predict_swing(dt: float) -> void:
	if not me.swing.is_empty():
		me.swing.t += dt
		if me.swing.t >= me.swing.dur:
			me.swing = {}
	var w := me.weapon()
	if w.kind != "melee" or not me.intent.fire or me.attack_cd > 0.0:
		return
	me.swing = {"t": 0.0, "dur": minf(0.26, w.cd * 0.75), "angle": me.angle, "arc": w.arc, "range": w.range + me.r}
	me.attack_cd = w.cd


## Everyone and everything else eases toward its last reported place.
func _ease(dt: float) -> void:
	var k := Util.smooth(Config.NET.ease_rate, dt)
	for t in _targets:
		var o = t.obj
		if o is PlayerSim or o is EnemySim or o is SurvivorSim:
			o.prev_pos = o.pos
			o.pos = o.pos.lerp(t.pos, k)
			if t.angle != INF:
				o.angle += Enemies.angle_delta(o.angle, t.angle) * k
		else:
			o.prev_pos = o.pos if o.has("prev_pos") else o.pos
			o.pos = o.pos.lerp(t.pos, k)
			if t.angle != INF and o.has("angle"):
				o.angle += Enemies.angle_delta(o.angle, t.angle) * k


## Timers the views read that the host does not send every frame: flashes
## fading, walk cycles, bobbing loot, ageing corpses, tracers flying.
func _advance_cosmetics(dt: float) -> void:
	for p in sim.players:
		if p == me:
			continue
		p.invuln = maxf(0.0, p.invuln - dt * 0.5)
		p.hurt_flash = maxf(0.0, p.hurt_flash - dt)
		if not p.swing.is_empty():
			p.swing.t += dt
			if p.swing.t >= p.swing.dur:
				p.swing.t = 0.0
	for e in sim.enemies.list:
		e.flash = maxf(0.0, e.flash - dt)
		e.anim += dt * (2.0 + e.speed * 0.03)
	for s in sim.crew.list:
		s.anim += dt * 5.0
		s.flash = maxf(0.0, s.flash - dt)
	for it in sim.pickups:
		it.t += dt
	for v in sim.cars.list:
		v.flash = maxf(0.0, v.flash - dt)
	for c in sim.enemies.corpses:
		c.t += dt
	while not sim.enemies.corpses.is_empty() and sim.enemies.corpses[0].t > sim.enemies.corpses[0].life:
		sim.enemies.corpses.pop_front()
	for i in range(sim.bullets.size() - 1, -1, -1):
		var b: Dictionary = sim.bullets[i]
		b.life -= dt
		b.prev = b.pos
		b.pos += b.vel * dt
		if b.life <= 0.0 or sim.world.bullet_blocks_px(b.pos.x, b.pos.y):
			sim.bullets.remove_at(i)
