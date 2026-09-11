class_name NetProtocol
extends RefCounted
## What goes over the wire, and the small pure helpers around it. No sockets,
## no nodes, no game state of its own: this file is what the tests check the
## shapes against, and both ends of a connection read it.
##
## Two channels. RELIABLE is ordered: the join handshake, commands from a
## guest, events and world diffs from the host. STATE is unordered and
## unacknowledged: a guest's intent every step, the host's snapshot at 20Hz.
##
## Messages are Dictionaries with a `t`, encoded with `var_to_bytes` (never
## the `_with_objects` variant: nothing off the wire may instantiate a
## class). The per-entity halves of a snapshot are flat
## `PackedFloat32Array`s with a fixed stride, because a Dictionary per enemy
## costs a type header per field and a horde at 20Hz adds up.

## Bumped whenever anything in here changes shape. A guest whose number
## differs is refused before it can misread a byte.
## 6: PR D and PR C — the `map` message, the snapshot's `mp` tag, the per-guest
## `inst` record in the world diff, the haul on the inventory record, and shots
## that carry their speed, life and colour. 5 was the dash.
## 7: PR E (Codex, PR #34) — the `upgrade_weapon` command, a weapon's level
## on the inventory record, and new ids in the sorted pickup index table. A
## build before it would take the command and do nothing, and read the new
## ids as other items.
const PROTOCOL := 7

const RELIABLE := 1
const STATE := 2

const OUT_OF_DATE := "your game is a different version to the host's — update, then rejoin"

## Snapshot entity strides. Every record is `stride` floats; the order is the
## order the packers write them, documented on each.
const EN_STRIDE := 9      # id, type, x, y, angle, hp, max_hp, flags, r
const VH_STRIDE := 9      # id, x, y, angle, speed, hp, fuel, flags, si
const FR_STRIDE := 3      # x, y, fraction left
const PK_STRIDE := 6      # uid, x, y, kind, item, n  (kind and item are indexes)

## Enemy flags.
const EF_FLASH := 1
const EF_AGGRO := 2
const EF_RAID := 4
const EF_BURN := 8
const EF_WINDUP := 16
const EF_STAGGER := 32
const EF_BLEED := 64

## Vehicle flags.
const VF_DESTROYED := 1
const VF_ENGINE := 2
const VF_LOCKED := 4
const VF_HOTWIRED := 8
const VF_FLASH := 16

## Player flags (players are Dictionaries: few of them, many strings).
const PF_DEAD := 1
const PF_DOWNED := 2
const PF_SNEAK := 4
const PF_SPRINT := 8
const PF_SWING := 16
const PF_RELOAD := 32
const PF_LIT := 64
const PF_AWAY := 128
const PF_WINDED := 256
const PF_INVULN := 512
const PF_HURT := 1024
## Mid-Lurch: the host is driving this body, so a guest stops predicting it.
const PF_LURCH := 2048
## Mid-dash, so everyone else's screen draws the burst. The dasher's own guest
## predicts it and does not need telling.
const PF_DASH := 4096

static var _enemy_types: PackedStringArray = PackedStringArray()
static var _item_ids: PackedStringArray = PackedStringArray()
static var _item_index := {}


## The enemy type list, in a fixed order both ends derive from Config.
static func enemy_types() -> PackedStringArray:
	if _enemy_types.is_empty():
		var keys := Config.ENEMIES.keys()
		keys.sort()
		_enemy_types = PackedStringArray(keys)
	return _enemy_types


## Every item id, in a fixed order, so a pickup can name its contents as an
## index in a float array rather than as a string.
static func item_ids() -> PackedStringArray:
	if _item_ids.is_empty():
		var keys: Array = []
		for k in Config.RES:
			keys.append(String(k))
		for k in Config.WEAPONS:
			keys.append(String(k))
		for k in Config.GEAR:
			keys.append(String(k))
		for k in Config.CONSUMABLES:
			keys.append(String(k))
		keys.sort()
		_item_ids = PackedStringArray(keys)
		for i in range(_item_ids.size()):
			_item_index[_item_ids[i]] = i
	return _item_ids


static func item_index(id: String) -> int:
	item_ids()
	return int(_item_index.get(id, -1))


const PICKUP_KINDS := ["res", "item", "weapon", "gear"]


# ------------------------------------------------------------------ bytes --

## Above this many bytes a packet is zstd-compressed. ENet's MTU is 1392;
## a packet under it is one datagram, and an unreliable one over it is
## several that all have to arrive. Compression is cheap and the wire is
## the expensive thing.
const COMPRESS_OVER := 900
const RAW := 0
const ZSTD := 1


static func encode(m: Dictionary) -> PackedByteArray:
	var body := var_to_bytes(m)
	var out := PackedByteArray()
	if body.size() <= COMPRESS_OVER:
		out.append(RAW)
		out.append_array(body)
		return out
	out.resize(5)
	out[0] = ZSTD
	out.encode_u32(1, body.size())
	out.append_array(body.compress(FileAccess.COMPRESSION_ZSTD))
	return out


## A Dictionary or empty. Anything else off the wire — a truncated packet, a
## string, an object, a size that lies — is empty, never an error.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 2:
		return {}
	var body: PackedByteArray
	if bytes[0] == RAW:
		body = bytes.slice(1)
	elif bytes[0] == ZSTD and bytes.size() > 5:
		var size := bytes.decode_u32(1)
		if size <= 0 or size > 16 * 1024 * 1024:
			return {}
		body = bytes.slice(5).decompress(size, FileAccess.COMPRESSION_ZSTD)
	else:
		return {}
	var v = bytes_to_var(body)
	if typeof(v) != TYPE_DICTIONARY or not v.has("t"):
		return {}
	return v


# --------------------------------------------------------------- identity --

## A guest is the same person next week. The id lives on their machine.
static func random_id() -> String:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return "%08x-%08x-%08x" % [r.randi(), r.randi(), Time.get_unix_time_from_system()]


## Hashed on the guest, compared by the host. The wire never carries the
## password itself.
static func hash_password(pw: String) -> String:
	if pw.strip_edges().is_empty():
		return ""
	return ("deadline:" + pw).sha256_text()


## Why this guest may not join, or "" if they may. Pure, so the tests can
## drive every branch without a socket. A hello carrying no numbers at all is
## a client older than this check existed, which is exactly what it exists to
## catch — so a missing field is a refusal, not a pass.
static func join_refusal(hello: Dictionary, pw_hash: String) -> String:
	if int(hello.get("p", -1)) != PROTOCOL:
		return OUT_OF_DATE
	if int(hello.get("sv", -1)) != SaveGame.VERSION:
		return OUT_OF_DATE
	if not pw_hash.is_empty() and String(hello.get("pw", "")) != pw_hash:
		return "wrong password"
	return ""


# --------------------------------------------------------------- messages --

static func msg_hello(identity: String, name_: String, pw_hash: String) -> Dictionary:
	return {"t": "hello", "p": PROTOCOL, "sv": SaveGame.VERSION, "id": identity, "name": name_, "pw": pw_hash}


static func msg_welcome(seat: int, world: Dictionary, roster: Array, host_name: String) -> Dictionary:
	return {"t": "welcome", "seat": seat, "world": world, "roster": roster, "host": host_name}


static func msg_reject(reason: String) -> Dictionary:
	return {"t": "reject", "reason": reason}


## `with_edges` false strips the one-step presses: the STATE channel may
## drop a packet, and a press that was dropped never happened, so edges
## travel on RELIABLE (see `msg_edges`) and held state every step here.
static func msg_intent(seq: int, it: Intent, with_edges := true) -> Dictionary:
	return {"t": "in", "q": seq, "i": pack_intent(it, with_edges)}


## The presses alone, for the reliable channel. Sent only on a step that
## has one, and merged by the host as edges only — the held state in it is
## a copy the STATE packet already carries.
static func msg_edges(seq: int, it: Intent) -> Dictionary:
	return {"t": "edges", "q": seq, "i": pack_intent(it, true)}


static func has_edges(it: Intent) -> bool:
	for e in Intent.EDGES:
		if it.get(e):
			return true
	return it.slot >= 0 or it.wheel != 0 or not it.build_action.is_empty()


static func msg_cmd(name_: String, args: Dictionary) -> Dictionary:
	return {"t": "cmd", "c": name_, "a": args}


static func msg_bye() -> Dictionary:
	return {"t": "bye"}


# ---------------------------------------------------------------- intents --

## Held state and edges into one small record. Edges are what the sim reads
## for exactly one step, so they are the fields a lost packet must not lose.
static func pack_intent(it: Intent, with_edges := true) -> Dictionary:
	var f := 0
	if it.sprint: f |= 1
	if it.sneak: f |= 2
	if it.fire: f |= 4
	if it.interact_held: f |= 64
	if with_edges:
		if it.fire_pressed: f |= 8
		if it.reload: f |= 16
		if it.interact: f |= 32
		if it.use: f |= 128
		if it.light: f |= 256
		if it.suppress: f |= 512
		if it.eat: f |= 1024
		if it.dash: f |= 2048
	var out := {"mx": snappedf(it.mx, 0.01), "my": snappedf(it.my, 0.01),
		"ax": roundi(it.aim.x), "ay": roundi(it.aim.y), "f": f,
		"s": it.slot if with_edges else -1, "w": it.wheel if with_edges else 0}
	if with_edges and not it.build_action.is_empty():
		out["b"] = [it.build_action, it.build_type, it.build_tile.x, it.build_tile.y]
	return out


## Fills `into` from a packed record, wholesale.
static func unpack_intent(p: Dictionary, into: Intent) -> Intent:
	into.mx = clampf(float(p.get("mx", 0.0)), -1.0, 1.0)
	into.my = clampf(float(p.get("my", 0.0)), -1.0, 1.0)
	into.aim = Vector2(float(p.get("ax", 0)), float(p.get("ay", 0)))
	var f := int(p.get("f", 0))
	into.sprint = bool(f & 1)
	into.sneak = bool(f & 2)
	into.fire = bool(f & 4)
	into.fire_pressed = bool(f & 8)
	into.reload = bool(f & 16)
	into.interact = bool(f & 32)
	into.interact_held = bool(f & 64)
	into.use = bool(f & 128)
	into.light = bool(f & 256)
	into.suppress = bool(f & 512)
	into.eat = bool(f & 1024)
	into.dash = bool(f & 2048)
	into.slot = clampi(int(p.get("s", -1)), -1, Config.PLAYER.hotbar_slots - 1)
	into.wheel = clampi(int(p.get("w", 0)), -1, 1)
	into.build_action = ""
	into.build_type = ""
	var b = p.get("b", null)
	if b is Array and b.size() == 4:
		into.build_action = String(b[0])
		into.build_type = String(b[1])
		into.build_tile = Vector2i(int(b[2]), int(b[3]))
	return into


## Edge flags arriving in a packet must survive until a simulation step has
## seen them, even if a later packet without the edge lands first. Merging
## ORs the edges and takes the held state from the newest packet.
static func merge_intent(into: Intent, fresh: Dictionary) -> void:
	# Held over the unpack, which overwrites everything: an edge that was
	# already standing must survive a packet that does not carry it. Driven by
	# `Intent.EDGES` rather than by a list here, so the next edge added to the
	# game cannot be dropped by this function the way `suppress` was.
	var held := {}
	for e in Intent.EDGES:
		held[e] = into.get(e)
	var sl := into.slot
	var wh := into.wheel
	var ba := into.build_action
	var bt := into.build_type
	var bl := into.build_tile
	unpack_intent(fresh, into)
	for e in Intent.EDGES:
		into.set(e, into.get(e) or held[e])
	if into.slot < 0:
		into.slot = sl
	if into.wheel == 0:
		into.wheel = wh
	if into.build_action.is_empty() and not ba.is_empty():
		into.build_action = ba
		into.build_type = bt
		into.build_tile = bl


## An older packet arriving after a newer one — the state channel is
## unordered. Nothing it says about held state is still true, but its edges
## were real presses that no other packet carries. Only those are taken.
static func merge_late_intent(into: Intent, fresh: Dictionary) -> void:
	var late := unpack_intent(fresh, Intent.new())
	for e in Intent.EDGES:
		into.set(e, into.get(e) or late.get(e))
	if into.slot < 0 and late.slot >= 0:
		into.slot = late.slot
	if into.wheel == 0:
		into.wheel = late.wheel
	if into.build_action.is_empty() and not late.build_action.is_empty():
		into.build_action = late.build_action
		into.build_type = late.build_type
		into.build_tile = late.build_tile


## "Holding nothing": what a silent guest is taken to mean, and what a paused
## one sends on purpose.
static func clear_intent(it: Intent) -> void:
	it.mx = 0.0
	it.my = 0.0
	it.sprint = false
	it.sneak = false
	it.fire = false
	it.interact_held = false
	it.clear_edges()


# -------------------------------------------------------------- snapshots --

static func r1(v: float) -> float:
	return snappedf(v, 0.1)


## Everything a guest needs to draw a player and, for its own, to know how it
## is doing. The numbers as a flat float array (`PL_*` are the indexes) and
## the three strings beside them: a Dictionary per player was five hundred
## bytes, and two of those put a snapshot over the MTU on its own.
const PL_SEAT := 0
const PL_X := 1
const PL_Y := 2
const PL_ANGLE := 3
const PL_HP := 4
const PL_MAX_HP := 5
const PL_STAM := 6
const PL_MAX_STAM := 7
const PL_SLOT := 8
const PL_FLAGS := 9
const PL_DOWN_T := 10
const PL_RESPAWN_T := 11
const PL_DRIVING := 12
const PL_LEVEL := 13
const PL_XP := 14
const PL_XP_NEXT := 15
const PL_SKILL := 16
const PL_CHANNEL := 17
const PL_LIGHT_FUEL := 18
const PL_MUT := 19
const PL_STRIDE := 20


static func pack_player(p: PlayerSim) -> Dictionary:
	var f := 0
	if p.dead: f |= PF_DEAD
	if p.downed: f |= PF_DOWNED
	if p.sneaking: f |= PF_SNEAK
	if p.sprinting: f |= PF_SPRINT
	if not p.swing.is_empty(): f |= PF_SWING
	if not p.reloading.is_empty(): f |= PF_RELOAD
	if p.lit: f |= PF_LIT
	if p.away: f |= PF_AWAY
	if p.winded: f |= PF_WINDED
	if p.invuln > 0.0: f |= PF_INVULN
	if p.hurt_flash > 0.0: f |= PF_HURT
	if p.lurch_t > 0.0: f |= PF_LURCH
	if p.dash_t > 0.0: f |= PF_DASH
	# Whatever channel is running, as a fraction: searching, healing, getting
	# somebody up, reloading. One bar on screen, whichever it is.
	var ch := -1.0
	var ck := ""
	if not p.searching.is_empty():
		ch = p.searching.t / p.searching.dur
		ck = "s"
	elif not p.using.is_empty():
		ch = p.using.t / p.using.dur
		ck = "u"
	elif not p.reviving.is_empty():
		ch = p.reviving.t / p.reviving.dur
		ck = "r"
	elif not p.reloading.is_empty():
		ch = p.reloading.t / p.reloading.dur
		ck = "l"
	var n := PackedFloat32Array([
		float(p.seat), r1(p.pos.x), r1(p.pos.y), snappedf(p.angle, 0.01),
		r1(p.hp), p.max_hp, r1(p.stam), p.max_stam,
		float(p.slot), float(f), r1(p.down_t), r1(p.respawn_t), float(p.driving_id),
		float(p.level), float(roundi(p.xp)), float(p.xp_next), float(p.skill_points),
		snappedf(ch, 0.01), r1(p.light_fuel), r1(p.mutation),
	])
	# The fourth string is the effect clocks, "nausea:12.3" — a handful of
	# short-lived ids that a guest needs for its own bars and its own stats,
	# and far too few to be worth a stride of their own.
	return {"n": n, "s": PackedStringArray([p.held_id(), String(p.equip.get("offhand", "")), ck, Mutation.pack_effects(p)])}


static func pack_enemies(sim: GameSim, centre: Vector2, radius: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var r2 := radius * radius
	var types := enemy_types()
	for e in sim.enemies.list:
		if e.dead or e.pos.distance_squared_to(centre) > r2:
			continue
		var f := 0
		if e.flash > 0.0: f |= EF_FLASH
		if e.aggro: f |= EF_AGGRO
		if e.raid: f |= EF_RAID
		if e.burn_t > 0.0: f |= EF_BURN
		if e.windup > 0.0: f |= EF_WINDUP
		# Both cosmetic on the far end — a guest never ticks either clock, it
		# only needs to know that the thing in front of it is reeling and
		# that it is losing blood, so one bit each is the whole cost.
		if e.stagger_t > 0.0: f |= EF_STAGGER
		if e.bleed_t > 0.0: f |= EF_BLEED
		out.append(float(e.id))
		out.append(float(types.find(e.type)))
		out.append(r1(e.pos.x))
		out.append(r1(e.pos.y))
		out.append(snappedf(e.angle, 0.01))
		out.append(r1(e.hp))
		out.append(e.max_hp)
		out.append(float(f))
		out.append(e.r)
	return out


static func pack_pickups(sim: GameSim, centre: Vector2, radius: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var r2 := radius * radius
	for it in sim.pickups:
		if it.pos.distance_squared_to(centre) > r2:
			continue
		out.append(float(it.uid))
		out.append(r1(it.pos.x))
		out.append(r1(it.pos.y))
		out.append(float(PICKUP_KINDS.find(String(it.kind))))
		out.append(float(item_index(String(it.id))))
		out.append(float(it.n))
	return out


static func pack_vehicles(sim: GameSim, centre: Vector2, radius: float, driving_id: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var r2 := radius * radius
	for v in sim.cars.list:
		if int(v.id) != driving_id and v.pos.distance_squared_to(centre) > r2:
			continue
		var f := 0
		if v.destroyed: f |= VF_DESTROYED
		if v.engine_on: f |= VF_ENGINE
		if v.locked: f |= VF_LOCKED
		if v.hotwired: f |= VF_HOTWIRED
		if v.flash > 0.0: f |= VF_FLASH
		out.append(float(v.id))
		out.append(r1(v.pos.x))
		out.append(r1(v.pos.y))
		out.append(snappedf(v.angle, 0.01))
		out.append(r1(v.speed))
		out.append(r1(v.hp))
		out.append(r1(v.fuel))
		out.append(float(f))
		out.append(float(v.si))
	return out


static func pack_fires(sim: GameSim, centre: Vector2, radius: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var r2 := radius * radius
	for f in sim.fire.list:
		if f.pos.distance_squared_to(centre) > r2:
			continue
		out.append(r1(f.pos.x))
		out.append(r1(f.pos.y))
		out.append(snappedf(clampf(1.0 - f.t / maxf(0.001, f.life), 0.0, 1.0), 0.01))
	return out


## Every survivor, wherever they are: there are at most a handful, and a
## scavenger across town is worth knowing about.
static func pack_survivor(s: SurvivorSim) -> Dictionary:
	return {
		"id": s.id, "x": r1(s.pos.x), "y": r1(s.pos.y), "a": snappedf(s.angle, 0.01),
		"hp": r1(s.hp), "mh": s.max_hp, "dn": s.downed, "dt": r1(s.down_t),
		"j": s.job, "nm": s.display_name, "lv": s.level, "hg": s.hungry, "oa": s.out_of_ammo,
		"tx": int(s.tower.tx) if not s.tower.is_empty() else -1,
		"ty": int(s.tower.ty) if not s.tower.is_empty() else -1,
		"ps": s.posted, "tn": s.tint, "fl": s.flash > 0.0,
		"cg": not s.carrying.is_empty() or not s.carry_items.is_empty(),
	}


## The per-guest world picture: everything near them, and every player.
static func pack_snapshot(sim: GameSim, for_player: PlayerSim, seq: int) -> Dictionary:
	var c := for_player.pos
	var R: float = Config.NET.interest_radius
	var players: Array = []
	for p in sim.players:
		players.append(pack_player(p))
	var survivors: Array = []
	for s in sim.crew.list:
		if not s.dead:
			survivors.append(pack_survivor(s))
	var packs: Array = []
	for b in sim.backpacks:
		packs.append([int(b.seat), roundi(b.pos.x), roundi(b.pos.y)])
	var raid := {}
	if sim.raid != null:
		raid = {"ph": sim.raid.phase, "w": sim.raid.wave, "ws": int(sim.raid.spec.waves), "k": sim.raid.killed,
			"tot": sim.raid.total, "tmr": r1(sim.raid.timer), "nm": String(sim.raid.spec.name),
			"cx": roundi(sim.raid.centre.x), "cy": roundi(sim.raid.centre.y), "hb": sim.raid.has_base,
			"hu": sim.raid.human}
	return {
		"t": "snap", "q": seq,
		# Which map this is a picture of: the run's seed, or 0 for the town. A
		# guest drops a snapshot of the map it is not on (`NetGuest`).
		"mp": sim.instance.run_seed if sim.instance != null else 0,
		"tm": snappedf(sim.time, 0.01), "day": sim.clock.day, "dt": snappedf(sim.clock.t, 0.0001),
		"th": r1(sim.threat.value), "rd": sim.raids_done, "bt": sim.structs.bench_tier,
		"kills": int(sim.stats.kills), "raid": raid,
		"pl": players, "sv": survivors, "bp": packs,
		"en": pack_enemies(sim, c, R), "pk": pack_pickups(sim, c, R),
		"vh": pack_vehicles(sim, c, R, for_player.driving_id), "fr": pack_fires(sim, c, R),
	}


# ------------------------------------------------------------ world diffs --

## A structure as the wire describes it: the save's fields plus the ones
## that change on their own (a generator running, a turret aiming).
static func pack_structure(s: Dictionary) -> Dictionary:
	return {"tp": s.type, "tx": s.tx, "ty": s.ty, "hp": r1(s.hp), "mh": s.max_hp, "op": s.open,
		"tr": s.tier, "fu": r1(s.fuel), "am": s.ammo, "on": s.on, "ac": s.active, "rn": s.running,
		"pw": s.powered, "st": s.starved, "aim": snappedf(s.aim, 0.05), "arm": s.arm, "fl": s.flash > 0.0,
		# A Raised Bed. The stage is not sent: a guest derives it from `gr` the
		# same way the host does, so the two cannot disagree about what is in
		# the ground.
		#
		# These two are the only fields on the wire that are deliberately
		# *coarse*. The world diff re-sends a structure whose record has
		# changed, and a growing bed's water and growth move every frame — at
		# full precision a garden would re-send itself twice a second for
		# ever. Floored rather than rounded, so a guest is always a little
		# behind the host and never ahead: a guest that reached "ready" first
		# would offer a harvest the host then refuses. See `Config.FARM`.
		"sd": s.seed, "ft": s.fert,
		"wt": _floor_to(s.water, Config.FARM.wire_water_step),
		"gr": _floor_to(s.grow, Config.FARM.wire_grow_step)}


static func _floor_to(v: float, step: float) -> float:
	return floorf(v / step) * step


## Everything a guest needs that a snapshot does not carry: names and seats.
static func pack_roster(sim: GameSim) -> Array:
	var out: Array = []
	for p in sim.players:
		out.append({"n": p.seat, "id": p.identity, "name": p.display_name, "aw": p.away})
	return out


## A player's own inventory and build, as the save writes it. The one place a
## guest ever learns what is in its pack.
static func pack_inventory(p: PlayerSim) -> Dictionary:
	return {
		"bag": p.bag.to_record(), "hotbar": p.hotbar.to_record(), "haul": p.haul.to_record(), "equip": p.equip.duplicate(),
		"mag": p.mag.duplicate(), "car_keys": p.car_keys.duplicate(), "attrs": p.attrs.duplicate(),
		"perks": p.perks.duplicate(), "sk": p.skill_points, "slot": p.slot,
		"light_on": p.light_on, "light_fuel": p.light_fuel, "light_id": p.light_id,
		"light_doused": p.light_doused, "light_charge": p.light_charge.duplicate(), "spawn_tx": p.spawn_tile.x, "spawn_ty": p.spawn_tile.y,
		"lv": p.level, "xp": p.xp, "xn": p.xp_next, "swc": p.second_wind_cd,
	}


## Applies `pack_inventory` to a guest's own player. Position and the like
## are the snapshot's business; this is the pack, the body slots and the
## build, and the recompute that follows any change to them.
static func apply_inventory(p: PlayerSim, rec: Dictionary) -> void:
	# Condition rides inside these two records, as the fourth field on a slot:
	# it is part of what the pack *is*, and the pack diff already goes the
	# moment anything a guest carries changes.
	p.bag.from_record(rec.get("bag", []))
	p.hotbar.from_record(rec.get("hotbar", []))
	p.haul.from_record(rec.get("haul", []))
	for k in p.equip:
		p.equip[k] = String(rec.get("equip", {}).get(k, ""))
	p.mag.clear()
	for k in rec.get("mag", {}):
		p.mag[String(k)] = int(rec.mag[k])
	p.car_keys.clear()
	for k in rec.get("car_keys", []):
		p.car_keys.append(String(k))
	for k in rec.get("attrs", {}):
		p.attrs[String(k)] = int(rec.attrs[k])
	p.perks.clear()
	for k in rec.get("perks", {}):
		p.perks[String(k)] = int(rec.perks[k])
	p.skill_points = int(rec.get("sk", 0))
	p.slot = int(rec.get("slot", 0))
	p.light_on = bool(rec.get("light_on", false))
	p.light_fuel = float(rec.get("light_fuel", 0.0))
	p.light_id = String(rec.get("light_id", ""))
	p.light_doused = bool(rec.get("light_doused", false))
	p.light_charge.clear()
	for k in rec.get("light_charge", {}):
		p.light_charge[String(k)] = float(rec.light_charge[k])
	p.spawn_tile = Vector2i(int(rec.get("spawn_tx", -1)), int(rec.get("spawn_ty", -1)))
	p.level = int(rec.get("lv", p.level))
	p.xp = float(rec.get("xp", p.xp))
	p.xp_next = int(rec.get("xn", p.xp_next))
	p.second_wind_cd = float(rec.get("swc", 0.0))
	var hp := p.hp
	var st := p.stam
	Equipment.recompute_stats(p)
	p.hp = minf(hp, p.max_hp)
	p.stam = minf(st, p.max_stam)
	p.lit = p.light_on
