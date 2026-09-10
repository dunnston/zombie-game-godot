class_name Boss
extends RefCounted
## A phase boss's script (`tasks/instanced-dungeons.md` §8): pick a move off
## cooldown, telegraph it, do it, recover — and change the pattern when its
## health crosses a threshold. The data is `Config.BOSSES`, keyed by the
## enemy's type; this is the one small loop that reads it.
##
## It owns the boss's step only while something scripted is happening: asleep
## before anybody comes into its room, a telegraph, a charge, a stun, a phase
## change. Between moves `tick` returns false and the boss chases and bites
## like anything else — one AI loop, with a script on top where one is wanted.
##
## Every move lands through `Damage.damage_player`, and every telegraph is an
## event, so a guest's screen draws exactly what the host's does without
## knowing anything in here.

var def: Dictionary
## The room it will not leave, in pixels.
var arena := Rect2()
## Where the whistle's team comes in.
var add_spots: Array[Vector2] = []
var base_speed := 0.0

var phase := 0
## asleep / fight / tell / charge / stunned / recover / shift
var state := "asleep"
var move := ""
## Seconds left in the current state.
var t := 0.0
## Seconds until the next move may start.
var cd := 0.0
## Where a move was aimed, locked when its telegraph began: the telegraph is a
## promise about where the thing will land, so it cannot follow you.
var aim := Vector2.ZERO
var dir := Vector2.RIGHT
var travelled := 0.0
var struck: Array = []


func _init(e: EnemySim, def_: Dictionary, arena_tiles: Rect2i, spots: Array[Vector2]) -> void:
	def = def_
	var tile := float(Config.TILE)
	arena = Rect2(Vector2(arena_tiles.position) * tile, Vector2(arena_tiles.size) * tile)
	add_spots = spots
	base_speed = e.speed


## Which phase a boss at `frac` of its health is in: the last threshold it has
## gone under.
static func phase_for(def_: Dictionary, frac: float) -> int:
	var phases: Array = def_.phases
	var want := 0
	for i in range(1, phases.size()):
		if frac <= float(phases[i].at):
			want = i
	return want


## True while this owns the boss's step; false hands it to the ordinary AI.
func tick(sim: GameSim, e: EnemySim, p: PlayerSim, dt: float) -> bool:
	if state == "asleep":
		# Somebody in the room, or somebody hurting it from the doorway — a
		# boss that slept through being shot would be a target, not a fight.
		if e.hp < e.max_hp or _someone_in(sim):
			_wake(sim, e)
		else:
			e.vel = Vector2.ZERO
			return true
	_keep_in(e)
	var want := phase_for(def, e.hp / maxf(1.0, e.max_hp))
	if want > phase and state != "shift":
		_shift(sim, e, want)
		return true
	match state:
		"shift":
			t -= dt
			e.shield_t = maxf(0.0, t)
			e.vel = Vector2.ZERO
			if t <= 0.0:
				state = "fight"
				cd = 0.8
			return true
		"fight":
			cd -= dt
			if cd <= 0.0 and p != null and _someone_in(sim):
				_start(sim, e, p, _pick(sim))
				return true
			return false
		"tell":
			t -= dt
			e.vel *= exp(-12.0 * dt)
			e.angle = (aim - e.pos).angle()
			if t <= 0.0:
				_act(sim, e)
			return true
		"charge":
			_charge_step(sim, e, dt)
			return true
		"stunned", "recover":
			t -= dt
			e.vel *= exp(-9.0 * dt)
			if t <= 0.0:
				state = "fight"
				cd = _cooldown(sim)
			return true
	return false


## Starts a move now, whatever the cooldown says. The smoke run photographs
## each telegraph through this, and the dev menu can too.
func force(sim: GameSim, e: EnemySim, p: PlayerSim, id: String) -> void:
	if state == "asleep":
		_wake(sim, e)
	_start(sim, e, p, id)


func _wake(sim: GameSim, e: EnemySim) -> void:
	state = "fight"
	cd = 1.2
	e.aggro = true
	e.alert_t = 999.0
	sim.emit({"t": "boss_wake", "id": e.id, "x": e.pos.x, "y": e.pos.y})
	var line := String(def.get("wake", ""))
	if not line.is_empty():
		sim.notify(line, "#e05a4a", true)


func _someone_in(sim: GameSim) -> bool:
	for q in sim.players:
		if not q.dead and not q.away and not q.downed and arena.has_point(q.pos):
			return true
	return false


## To the edge of its room and no further.
func _keep_in(e: EnemySim) -> void:
	e.pos = _clamped(e, e.pos)


func _clamped(e: EnemySim, at: Vector2) -> Vector2:
	var lo := arena.position + Vector2(e.r, e.r)
	var hi := arena.end - Vector2(e.r, e.r)
	return Vector2(clampf(at.x, lo.x, hi.x), clampf(at.y, lo.y, hi.y))


func _pick(sim: GameSim) -> String:
	var pool: Array = []
	for id in def.phases[phase].moves:
		# A whistle with the team already out would be a telegraph for nothing.
		if String(id) == "whistle" and _adds_alive(sim) >= int(def.moves.whistle.cap):
			continue
		pool.append(String(id))
	return String(pool[sim.rng.irange(0, pool.size() - 1)]) if not pool.is_empty() else "slam"


func _cooldown(sim: GameSim) -> float:
	var r: Array = def.phases[phase].cd
	return sim.rng.frange(float(r[0]), float(r[1]))


func _start(sim: GameSim, e: EnemySim, p: PlayerSim, id: String) -> void:
	var m: Dictionary = def.moves[id]
	move = id
	state = "tell"
	t = float(m.tell)
	aim = p.pos
	e.windup = 0.0
	e.pending_struct = {}
	e.vel = Vector2.ZERO
	var ev := {"t": "boss_tell", "id": e.id, "move": id, "x": e.pos.x, "y": e.pos.y,
		"tx": aim.x, "ty": aim.y, "dur": t}
	match id:
		"slam":
			ev["r"] = float(m.radius)
		"charge":
			ev["dist"] = float(m.dist)
		"dodgeball":
			ev["fan"] = float(m.fan)
			ev["n"] = int(m.count)
	sim.emit(ev)


func _act(sim: GameSim, e: EnemySim) -> void:
	var m: Dictionary = def.moves[move]
	match move:
		"slam":
			for q in sim.players:
				if q.dead or q.away or q.downed:
					continue
				if q.pos.distance_to(e.pos) <= float(m.radius) + q.r:
					Damage.damage_player(sim, q, float(m.dmg), e.pos, String(e.def.name))
			sim.emit({"t": "boss_slam", "x": e.pos.x, "y": e.pos.y, "r": float(m.radius)})
			sim.emit({"t": "shake", "amount": 9.0})
			_recover(m)
		"charge":
			var to := aim - e.pos
			dir = to.normalized() if to.length_squared() > 1.0 else Vector2.from_angle(e.angle)
			travelled = 0.0
			struck.clear()
			state = "charge"
			sim.emit({"t": "boss_charge", "x": e.pos.x, "y": e.pos.y})
		"dodgeball":
			_throw(sim, e, m)
			_recover(m)
		"whistle":
			_whistle(sim, e, int(m.adds), int(m.cap))
			_recover(m)


func _recover(m: Dictionary) -> void:
	state = "recover"
	t = float(m.recover)


## Down the lane it telegraphed, hitting each person in it once. Into a wall —
## or the edge of its room — it stands there dazed: the opening the whole move
## exists to give you.
func _charge_step(sim: GameSim, e: EnemySim, dt: float) -> void:
	var m: Dictionary = def.moves.charge
	var step := float(m.speed) * dt
	var was := e.pos
	e.pos = _clamped(e, sim.world.move_circle(e.pos, dir * step, e.r, sim.structs))
	var moved := e.pos.distance_to(was)
	travelled += moved
	e.angle = dir.angle()
	for q in sim.players:
		if q.dead or q.away or q.downed or struck.has(q):
			continue
		if q.pos.distance_to(e.pos) <= e.r + q.r + 4.0:
			struck.append(q)
			Damage.damage_player(sim, q, float(m.dmg), e.pos - dir * 10.0, String(e.def.name))
	if moved < step * 0.5:
		state = "stunned"
		t = float(m.stun)
		sim.emit({"t": "boss_stunned", "id": e.id, "x": e.pos.x, "y": e.pos.y, "dur": t})
		sim.emit({"t": "shake", "amount": 7.0})
	elif travelled >= float(m.dist):
		_recover(m)


## A fan of slow balls at where you were standing. Hostile rounds, so
## `Combat` sends each to whoever it reaches and nothing else changes.
func _throw(sim: GameSim, e: EnemySim, m: Dictionary) -> void:
	var base := (aim - e.pos).angle()
	var n := int(m.count)
	var fan := float(m.fan)
	for i in range(n):
		var a := base + (0.0 if n <= 1 else (i - (n - 1) / 2.0) * fan / (n - 1))
		var b := Combat.spawn_bullet(sim, e.pos + Vector2.from_angle(a) * (e.r + 8.0), a, float(m.speed),
			float(m.dmg), float(m.range) / float(m.speed), 0.0, 0, e, false, "", String(m.get("color", "#e8703a")))
		b.hostile = true
	sim.emit({"t": "boss_throw", "x": e.pos.x, "y": e.pos.y})


## The team, in from the corners of the room, and never more of them than the
## cap — the fight is the boss, not a horde.
func _whistle(sim: GameSim, e: EnemySim, adds: int, cap: int) -> void:
	var n := mini(adds, cap - _adds_alive(sim))
	var first := sim.rng.irange(0, maxi(0, add_spots.size() - 1))
	for i in range(maxi(0, n)):
		if add_spots.is_empty():
			break
		var at: Vector2 = add_spots[(first + i) % add_spots.size()]
		var q := sim.enemies.spawn("runner" if sim.rng.chance(0.35) else "walker", at, true)
		if q != null:
			q.minion = true
	sim.emit({"t": "boss_whistle", "x": e.pos.x, "y": e.pos.y})


func _adds_alive(sim: GameSim) -> int:
	var n := 0
	for q in sim.enemies.list:
		if q.minion and not q.dead:
			n += 1
	return n


## Under a threshold: the pattern changes, and says so. Every phase passed on
## the way runs what it opens with, so a burst that takes it from two-thirds
## to a fifth still kills the lights. Then half a second — more — where it is
## untouchable and doing nothing, because a phase change that is not obvious
## reads as inconsistent AI rather than a fight (§8.4).
func _shift(sim: GameSim, e: EnemySim, want: int) -> void:
	while phase < want:
		phase += 1
		for action in def.phases[phase].get("enter", []):
			match String(action):
				"lights_out":
					if sim.instance != null:
						sim.instance.lights_out(sim)
				"whistle":
					_whistle(sim, e, int(def.moves.whistle.adds), int(def.moves.whistle.cap))
	state = "shift"
	t = float(def.transition)
	e.shield_t = t
	e.windup = 0.0
	e.vel = Vector2.ZERO
	e.speed = base_speed * float(def.phases[phase].get("speed_mul", 1.0))
	sim.emit({"t": "boss_phase", "id": e.id, "phase": phase, "x": e.pos.x, "y": e.pos.y})
	sim.emit({"t": "shake", "amount": 12.0})
	var name := String(def.phases[phase].get("name", ""))
	if not name.is_empty():
		sim.notify(name, "#e05a4a", true)
