class_name NetHost
extends RefCounted
## The host session. This machine runs the simulation exactly as it does in
## solo; on top of that it lets guests in, feeds their intent into their
## players, and tells everyone what happened.
##
## Nothing here touches the sim's rules. A guest's intent lands in
## `p.intent` and the ordinary `tick()` acts on it; snapshots are read from
## the sim after it. No node, no socket of its own: links are handed in
## (`attach`), so the tests and the smoke run drive it over a loopback and
## the game over an `EnetHub`.

var sim: GameSim
var host_name := "Host"
var pw_hash := ""
## Every connection, admitted or not: {link, player, seq, last_in, quiet,
## inv_hash, pending_snap}.
var guests: Array[Dictionary] = []
var step := 0
var seq := 0
var sync_t := 0.0
## What the last world diff described, so the next one can say only what
## changed: structures by tile key, stores by name, and the counts of the
## append-only lists.
var _struct_seen := {}
var _store_hash := ""
var _looted_seen := {}
var _chopped_sent := 0
var _discovered_seen := {}
var _rescues_hash := ""
var _roster_hash := ""
## Events the view has already been shown are still in `sim.events` until
## the frame ends; this is how far down that list the last relay got.
var _ev_mark := 0
var stats := {"sent": 0, "received": 0, "snaps": 0}


func _init(sim_: GameSim, name_ := "Host", pw_hash_ := "") -> void:
	sim = sim_
	host_name = name_
	pw_hash = pw_hash_
	if not sim.players.is_empty():
		sim.players[0].display_name = host_name
	_reset_diffs()


## A new world under the same session: NEW GAME or a load while hosting.
## Everything the diffs remembered is about a world that no longer exists.
func _reset_diffs() -> void:
	_struct_seen.clear()
	_store_hash = ""
	_looted_seen.clear()
	_chopped_sent = 0
	_discovered_seen.clear()
	_rescues_hash = ""
	_roster_hash = ""
	_ev_mark = 0


## A ready connection, before its hello. The broker or the hub hands these in.
func attach(link: NetLink) -> Dictionary:
	var g := {"link": link, "player": null, "seq": -1, "last_in": -1.0, "quiet": true, "inv_hash": ""}
	guests.append(g)
	return g


func connected_count() -> int:
	var n := 0
	for g in guests:
		if g.player != null:
			n += 1
	return n


## Names, for the pause menu.
func guest_names() -> Array[String]:
	var out: Array[String] = []
	for g in guests:
		out.append(String(g.player.display_name) if g.player != null else "(connecting…)")
	return out


# --------------------------------------------------------------- incoming --

## Reads every link. Call once per step, before the sim ticks, so a guest's
## intent is what this step acts on.
func poll() -> void:
	for i in range(guests.size() - 1, -1, -1):
		var g := guests[i]
		var link: NetLink = g.link
		for m in link.receive():
			var bytes: PackedByteArray = m[1]
			stats.received += bytes.size()
			var msg := NetProtocol.decode(bytes)
			if msg.is_empty():
				continue
			if int(m[0]) == NetProtocol.STATE:
				_on_state(g, msg)
			else:
				_on_reliable(g, msg)
		# After what it said, not before: a `bye` and the hang-up that
		# follows it arrive together, and "left" is the truer word.
		if guests.has(g) and not link.is_open():
			_drop(g, "lost connection")


func _on_reliable(g: Dictionary, m: Dictionary) -> void:
	var t := String(m.t)
	if t == "hello":
		_admit(g, m)
		return
	if g.player == null:
		return                          # nothing else before hello
	if t == "cmd":
		var p: PlayerSim = g.player
		Actions.execute(sim, p, String(m.get("c", "")), m.get("a", {}) if m.get("a") is Dictionary else {})
		# Straight away rather than at the next sync tick: the thing you just
		# dragged should land where you dropped it, not half a second later.
		_send_inventory(g, false)
		_sync_stores()
	elif t == "bye":
		_drop(g, "left")


func _on_state(g: Dictionary, m: Dictionary) -> void:
	if g.player == null or String(m.t) != "in":
		return
	var p: PlayerSim = g.player
	var q := int(m.get("q", 0))
	var packed = m.get("i", {})
	if not (packed is Dictionary):
		return
	# Out of order on the unreliable channel: an older packet must not undo a
	# newer one, but its edges are still real presses.
	if q < int(g.seq):
		NetProtocol.merge_late_intent(p.intent, packed)
		return
	g.seq = q
	g.last_in = sim.time
	g.quiet = false
	NetProtocol.merge_intent(p.intent, packed)


## A guest whose packets stop — paused, minimised, line dying — must not keep
## doing whatever it last said.
func _expire_silent_intents() -> void:
	for g in guests:
		if g.player == null or g.quiet or float(g.last_in) < 0.0:
			continue
		if sim.time - float(g.last_in) > Config.NET.intent_timeout:
			NetProtocol.clear_intent((g.player as PlayerSim).intent)
			g.quiet = true


func _admit(g: Dictionary, m: Dictionary) -> void:
	var link: NetLink = g.link
	var why := NetProtocol.join_refusal(m, pw_hash)
	if why.is_empty() and sim.world == null:
		why = "the host has not started a game yet"
	var identity := String(m.get("id", ""))
	var name_ := String(m.get("name", "")).strip_edges().left(16)
	var p: PlayerSim = null
	if why.is_empty():
		# The same person back again, or someone new. A second copy of the
		# host's own machine carries the host's identity: that is a new
		# player, not the host.
		if identity.is_empty():
			why = "that game client sent no identity"
		else:
			if sim.players[0].identity == identity:
				identity += "#2"
			p = sim.player_by_identity(identity)
			if p != null and not p.away:
				why = "that player is already connected"
			elif p == null:
				if sim.present_players().size() >= Config.NET.max_players:
					why = "that game is full"
				else:
					p = sim.join_player(identity, name_)
					if p == null:
						why = "that game is full"
			else:
				sim.unpark_player(p, name_)
	if not why.is_empty():
		_send(g, NetProtocol.RELIABLE, NetProtocol.msg_reject(why))
		link.close()
		guests.erase(g)
		return
	g.player = p
	g.last_in = sim.time
	g.quiet = false
	# They join through the same load path a save uses: the whole world, as
	# a payload, then the roster and their own pack.
	_send(g, NetProtocol.RELIABLE, NetProtocol.msg_welcome(p.seat, SaveGame.to_dict(sim), NetProtocol.pack_roster(sim), host_name))
	_send_inventory(g, true)
	_roster_hash = ""                   # everyone hears about the new seat
	_send_world_diff(g, true)


func _drop(g: Dictionary, why: String) -> void:
	if not guests.has(g):
		return
	guests.erase(g)
	var p: PlayerSim = g.player
	if p != null:
		sim.park_player(p)
		sim.notify("%s %s" % [p.display_name, why], "#8a8f84", false)
		_roster_hash = ""
	(g.link as NetLink).close()


## Closes every connection. `bye` first, so a guest hears it was the host
## leaving rather than the line dying.
func stop() -> void:
	for g in guests.duplicate():
		if g.player != null:
			_send(g, NetProtocol.RELIABLE, NetProtocol.msg_bye())
			sim.park_player(g.player)
		(g.link as NetLink).close()
	guests.clear()


# --------------------------------------------------------------- outgoing --

func _send(g: Dictionary, channel: int, m: Dictionary) -> void:
	var bytes := NetProtocol.encode(m)
	stats.sent += bytes.size()
	(g.link as NetLink).send(channel, bytes)


## Called by the scene after every simulation step while hosting.
func after_tick(dt: float) -> void:
	step += 1
	_expire_silent_intents()

	if step % int(Config.NET.snap_every) == 0:
		seq += 1
		for g in guests:
			if g.player != null:
				_send(g, NetProtocol.STATE, NetProtocol.pack_snapshot(sim, g.player, seq))
		stats.snaps += 1

	sync_t += dt
	if sync_t >= Config.NET.sync_interval:
		sync_t = 0.0
		for g in guests:
			_send_inventory(g, false)
		_sync_stores()
		for g in guests:
			_send_world_diff(g, false)

	_relay_events()


## The scene clears `sim.events` at the end of the frame; from then on the
## list starts over.
func on_events_cleared() -> void:
	_ev_mark = 0


## Every event since the last relay, to every guest that can see it: an event
## with a position within the interest radius, one with no position at all
## (the day turning, a raid warning), or one addressed to a seat. The guest's
## own views answer them exactly as the host's do.
func _relay_events() -> void:
	if guests.is_empty():
		_ev_mark = sim.events.size()
		return
	var R: float = Config.NET.interest_radius
	var r2 := R * R
	for i in range(_ev_mark, sim.events.size()):
		var ev: Dictionary = sim.events[i]
		var t := String(ev.t)
		if t == "open_store" or t == "open_boot":
			# A screen opening for whoever pressed E: `open_store` names the
			# seat; `open_boot` is fixed up below by who is near the car.
			pass
		for g in guests:
			var p: PlayerSim = g.player
			if p == null:
				continue
			if ev.has("seat") and int(ev.seat) != p.seat and t != "player_hit" and t != "player_died" \
					and t != "player_down" and t != "player_up" and t != "respawn":
				continue
			if t == "open_boot":
				var v := sim.cars.by_id(int(ev.id))
				var r: float = Config.CAR.enter_range
				if v.is_empty() or p.pos.distance_squared_to(v.pos) > r * r or p.driving_id > 0:
					continue
			if ev.has("x") and p.pos.distance_squared_to(Vector2(ev.x, ev.y)) > r2:
				continue
			_send(g, NetProtocol.RELIABLE, {"t": "ev", "e": ev})
	_ev_mark = sim.events.size()


func _send_inventory(g: Dictionary, force: bool) -> void:
	var p: PlayerSim = g.player
	if p == null:
		return
	var rec := NetProtocol.pack_inventory(p)
	var text := var_to_str(rec)
	if not force and text == String(g.inv_hash):
		return
	g.inv_hash = text
	_send(g, NetProtocol.RELIABLE, {"t": "inv", "rec": rec})


## Storage, diffed and sent only when it changed. Every container in the base
## is one entry — the shared stash under `-1,-1`, each chest or locker under
## its tile — and every boot under its car id. Sent whole rather than as
## deltas because a container is small and changes rarely, and a missed
## delta would leave a guest looking at a chest that does not match what is
## in it. A joining guest gets the stores in the payload, so this only ever
## sends a change.
func _sync_stores() -> void:
	var list: Array = []
	if sim.stash != null:
		list.append({"tx": -1, "ty": -1, "car": 0, "slots": sim.stash.to_record()})
	for s in sim.structs.list:
		if s.destroyed or s.store == null or s.type == "stash":
			continue
		list.append({"tx": s.tx, "ty": s.ty, "car": 0, "slots": s.store.to_record()})
	for v in sim.cars.list:
		if v.destroyed or v.trunk.used() == 0:
			continue
		list.append({"tx": -1, "ty": -1, "car": int(v.id), "slots": v.trunk.to_record()})
	var text := var_to_str(list)
	if text == _store_hash:
		return
	_store_hash = text
	for g in guests:
		if g.player != null:
			_send(g, NetProtocol.RELIABLE, {"t": "stores", "list": list})


## What changed in the world that a snapshot does not carry: structures
## (placed, hit, repaired, opened, powered, gone), containers emptied, props
## felled or burned, districts found, people still waiting to be found, and
## who is at the table. Everything is keyed the way the save keys it, by tile
## and by id, never by index (invariant 7).
##
## Measured against what was last *sent to everyone*, so a guest that just
## joined gets `force` — the full picture — and everyone else gets the diff.
func _send_world_diff(g: Dictionary, force: bool) -> void:
	if g.player == null:
		return
	var d := {"t": "world"}

	var structs: Array = []
	var gone: Array = []
	var now := {}
	for s in sim.structs.list:
		if s.destroyed:
			continue
		var key := "%d,%d" % [s.tx, s.ty]
		var rec := NetProtocol.pack_structure(s)
		now[key] = rec
		if force or var_to_str(_struct_seen.get(key, {})) != var_to_str(rec):
			structs.append(rec)
	for key in _struct_seen:
		if not now.has(key):
			var parts: PackedStringArray = String(key).split(",")
			gone.append([int(parts[0]), int(parts[1])])
	if not structs.is_empty():
		d["structs"] = structs
	if not gone.is_empty() and not force:
		d["gone"] = gone

	var looted: Array = []
	for c in sim.world.containers:
		if not c.looted:
			continue
		var key := "%d,%d" % [c.tx, c.ty]
		if force or not _looted_seen.has(key):
			looted.append(key)
	if not looted.is_empty():
		d["looted"] = looted

	var chopped := sim.world.chopped_keys()
	if force:
		d["chopped"] = chopped
	elif chopped.size() > _chopped_sent:
		d["chopped"] = chopped.slice(_chopped_sent)

	var found: Array = []
	for l in sim.world.locations:
		if l.discovered and (force or not _discovered_seen.has(String(l.id))):
			found.append(String(l.id))
	if not found.is_empty():
		d["discovered"] = found

	var rescues: Array = []
	for r in sim.crew.rescues:
		rescues.append([r.pos.x, r.pos.y, String(r.name), int(r.level)])
	var rtext := var_to_str(rescues)
	if force or rtext != _rescues_hash:
		d["rescues"] = rescues

	var roster := NetProtocol.pack_roster(sim)
	var rostext := var_to_str(roster)
	if force or rostext != _roster_hash:
		d["roster"] = roster

	d["bench"] = sim.structs.bench_tier
	if d.size() > 2 or force:
		_send(g, NetProtocol.RELIABLE, d)

	# Only once everyone has been told does the baseline move. A forced send
	# (one new guest) must not swallow the diff the others were owed.
	if force:
		return
	if g == _last_guest():
		_struct_seen = now
		for key in looted:
			_looted_seen[key] = true
		_chopped_sent = chopped.size()
		for id in found:
			_discovered_seen[id] = true
		_rescues_hash = rtext
		_roster_hash = rostext


func _last_guest() -> Dictionary:
	for i in range(guests.size() - 1, -1, -1):
		if guests[i].player != null:
			return guests[i]
	return {}
