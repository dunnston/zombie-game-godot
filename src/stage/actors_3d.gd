class_name Actors3D
extends Node3D
## Every player and enemy on the 3D stage, one `ActorModel` each, created
## and freed as the sim's lists change and told what to be every frame from
## the same fields the 2D views read: where it is drawn (interpolated), what
## it faces, what it is doing. A dead enemy's body stays where it fell for
## as long as the 2D corpse did, then fades; so does a player's, for the
## horde to bend over.

## How long a body lies there: `Damage` gives a corpse 45 s, and a model
## has no record to read it from, so the number is here too.
const CORPSE_LIFE := 45.0
const CORPSE_FADE := 6.0
const STEPS_PER_SEC := 60.0
## The dash is 0.18 s of movement; the hop drawn over it takes this long,
## so it reads as a jump rather than a flicker.
const JUMP_TIME := 0.7
## How much faster than it was animated a cycle may play before the feet
## blur: a walk is a walk even on a body that covers 5 m/s.
const WALK_PACE := 1.8
const RUN_PACE := 2.2
## A sneak on the move is the walk, slower than the clip: the body is at half
## speed and should look it.
const SNEAK_PACE := 0.9

var sim: GameSim
var local: PlayerSim
var _players := {}     # seat -> ActorModel
var _enemies := {}     # enemy id -> ActorModel
var _corpses := {}     # enemy id, or "p<seat>" -> {node, t}
## What each body was doing last frame, for the edges that start a one-shot:
## a dash's first step, a round leaving the barrel, a weapon changing hands,
## a swing beginning. Seat -> {dash, shot, held, fam, dead, at, yaw};
## enemy id -> {wind, swings}.
var _pmem := {}
var _emem := {}

## A boss's body does what its script does, learned from the script's events
## and never from the script: a guest's copy of a boss has no script (the
## 2026-09-10 decision that has `BossView` draw from events). Enemy id ->
## {state, dur, t}: the clip for the move and how long the sim gives it.
var _cues := {}
## Bosses that have shown signs of life. One that has not lies on the gym
## floor. Any cue counts (Codex, PR #74): a guest outside the interest radius
## when the wake was relayed still sees the tells, and a boss mid-fight must
## never lie back down between them.
var _awake := {}

## A boss move -> the clip its telegraph plays. The clip's `strike` is fitted
## to the tell, so the blow lands on screen when it lands in the sim.
const MOVE_CLIP := {"slam": "slam", "charge": "charge_wind", "dodgeball": "throw",
	"whistle": "whistle", "hook": "attack"}


func _init(sim_: GameSim) -> void:
	sim = sim_


func frame(dt: float) -> void:
	_frame_players(dt)
	_frame_enemies(dt)
	_frame_corpses(dt)


## Everything, for a new world: the models are rebuilt from the lists.
func rebuild() -> void:
	for n in _players.values():
		n.queue_free()
	for n in _enemies.values():
		n.queue_free()
	for c in _corpses.values():
		c.node.queue_free()
	_players.clear()
	_enemies.clear()
	_corpses.clear()
	_pmem.clear()
	_emem.clear()
	_cues.clear()
	_awake.clear()


## Takes one event and returns the state it cues, or "", so a test can assert
## on the decision (the shape `BossView.on_event` has).
func on_event(ev: Dictionary) -> String:
	match String(ev.t):
		"boss_wake":
			return _cue(int(ev.id), "wake", 1.2)
		"boss_tell":
			return _cue(int(ev.id), String(MOVE_CLIP.get(String(ev.move), "attack")), float(ev.dur))
		"boss_stunned":
			return _cue(int(ev.id), "stun", float(ev.dur))
		"boss_phase":
			return _cue(int(ev.id), "roar", _transition_of(int(ev.id)))
	return ""


func _cue(id: int, state: String, dur: float) -> String:
	_awake[id] = true
	_cues[id] = {"state": state, "dur": maxf(0.05, dur), "t": 0.0, "fresh": true}
	return state


## How long a boss's phase change holds it, from its table; 1.2 s for one the
## sim no longer lists.
func _transition_of(id: int) -> float:
	for e in sim.enemies.list:
		if e.id == id:
			return float(Config.BOSSES.get(e.type, {}).get("transition", 1.2))
	return 1.2


## The body of a player, for a test to read what it decided.
func player_node(seat: int) -> ActorModel:
	return _players.get(seat)


## The body of an enemy, for a test to read what it decided.
func enemy_node(id: int) -> ActorModel:
	return _enemies.get(id)


# ---------------------------------------------------------------- players --

func _frame_players(dt: float) -> void:
	var seen := {}
	for p in sim.players:
		seen[p.seat] = true
		var node: ActorModel = _players.get(p.seat)
		if node == null:
			node = ActorModel.new()
			node.setup(Models.PLAYER, Config.PLAYER.r, 1.7, Color("#6c7a4b"))
			node.add_ring(Color(Config.PLAYER.colors[p.seat % Config.PLAYER.colors.size()]))
			add_child(node)
			_players[p.seat] = node
			_pmem[p.seat] = {"dash": 0.0, "shot": -1.0, "held": p.held_id(),
				"fam": Models.family_of(p.weapon()), "dead": p.dead, "at": Vector3.ZERO, "yaw": 0.0}
		_update_player(node, p, dt)
	for seat in _players.keys():
		if not seen.has(seat):
			_players[seat].queue_free()
			_players.erase(seat)
			_pmem.erase(seat)


func _update_player(node: ActorModel, p: PlayerSim, _dt: float) -> void:
	var m: Dictionary = _pmem[p.seat]
	if p.away:
		node.visible = false
		return
	# Invulnerable after a hit: blink, per player, as the 2D body does.
	node.visible = not (p.invuln > 0.0 and int(p.invuln * 20.0) % 2 == 0)
	var at := Util.render_pos(p.prev_pos, p.pos)
	node.position = Units.to3(at)
	node.face(p.angle)
	var w := p.weapon()
	var fam := Models.family_of(w)
	node.hold(Color(w.get("color", "#2b2b2b")), 0.62 if w.kind == "gun" else 0.5)

	# The edges, read every frame whatever else happens so none is left
	# pending from before a death.
	var jumped := p.dash_t > float(m.dash)
	m.dash = p.dash_t
	var fired := not p.shot.is_empty() and (float(m.shot) < 0.0 or float(p.shot.t) < float(m.shot))
	m.shot = float(p.shot.t) if not p.shot.is_empty() else -1.0
	var held := p.held_id()
	var changed := held != String(m.held)
	var was_fam := String(m.fam)
	m.held = held
	m.fam = fam

	if p.dead:
		node.play("die")
		node.lie_down(true)
		node.tint(Color.TRANSPARENT)
		m.dead = true
		m.at = node.position
		m.yaw = node.rotation.y
		return
	if m.dead:
		# Up again, somewhere else: the body stays where it fell, for the
		# zombies that stopped to eat it and for finding the pack.
		m.dead = false
		_leave_body(p.seat, m.at, float(m.yaw))
	node.lie_down(false)
	if p.downed:
		node.play("downed")
		return
	var speed := Units.m((p.pos - p.prev_pos).length()) * STEPS_PER_SEC
	var moving := speed > 0.3
	if jumped or (node.state == "jump" and node.busy()):
		node.play("jump", _fit(node, "jump", JUMP_TIME), jumped, 0.1)
	elif not p.swing.is_empty():
		node.play("attack", _fit(node, "attack", float(p.swing.dur)), false, 0.1, fam)
	elif fired:
		# Every gun kicks like the rifle; the bow has its own release.
		node.play("shoot", _fit(node, "shoot", maxf(0.25, float(p.shot.dur)), fam), true, 0.05, fam)
	elif not p.reloading.is_empty() and node.has_clip("reload", fam):
		# The bow's reload is its draw. A gun has no clip for it yet, and
		# walks or stands through it rather than freezing.
		node.play("reload", _fit(node, "reload", float(p.reloading.dur), fam), false, 0.1, fam)
	elif changed and node.has_clip("equip", fam):
		node.play("equip", _fit(node, "equip", 0.6, fam), true, 0.1, fam)
	elif changed and node.has_clip("disarm", was_fam):
		node.play("disarm", _fit(node, "disarm", 0.6, was_fam), true, 0.1, was_fam)
	elif node.busy():
		pass
	elif p.sneaking:
		# Ctrl: down on one knee while still. There is no crouched walk in
		# the exports, so a sneak on the move is the walk at its half pace.
		if moving:
			node.play("walk", _pace(node, "walk", speed, fam, SNEAK_PACE), false, 0.2, fam)
		else:
			node.play("crouch", 1.0, false, 0.3, fam)
	elif moving:
		# What the sim calls it, not how fast it goes: a walk here covers
		# 5 m/s, which paced to the ground would run the stroll at 3.5x.
		if p.sprinting:
			node.play("run", _pace(node, "run", speed, fam, RUN_PACE), false, 0.2, fam)
		else:
			node.play("walk", _pace(node, "walk", speed, fam, WALK_PACE), false, 0.2, fam)
	else:
		node.play("idle", 1.0, false, 0.3, fam)
	if p.hurt_flash > 0.0:
		node.tint(Color(1, 0.3, 0.2, 0.6 * clampf(p.hurt_flash * 2.0, 0.0, 1.0)))
	else:
		node.tint(Color.TRANSPARENT)


## A player's body, left lying where they died, on the corpse clock.
func _leave_body(seat: int, at: Vector3, yaw: float) -> void:
	var key := "p%d" % seat
	if _corpses.has(key):
		_corpses[key].node.queue_free()
	var body := ActorModel.new()
	body.setup(Models.PLAYER, Config.PLAYER.r, 1.7, Color("#6c7a4b"))
	add_child(body)
	body.position = at
	body.rotation.y = yaw
	body.hold_end("die")
	body.lie_down(true)
	_corpses[key] = {"node": body, "t": 0.0}


# ---------------------------------------------------------------- enemies --

func _frame_enemies(dt: float) -> void:
	var seen := {}
	for e in sim.enemies.list:
		if e.dead:
			continue
		seen[e.id] = true
		var node: ActorModel = _enemies.get(e.id)
		if node == null:
			node = ActorModel.new()
			var table: Dictionary = Models.ENEMY_MODELS.get(e.type, {})
			node.setup(table, e.r, _height_for(e), Color(e.def.body))
			add_child(node)
			_enemies[e.id] = node
			# Swings start counting from the id, so a crowd that winds up
			# together does not all lead with the same one.
			_emem[e.id] = {"wind": e.windup, "swings": e.id}
		_update_enemy(node, e, dt)
	for id in _enemies.keys():
		if not seen.has(id):
			# Gone from the list: it died (or was culled far away). The body
			# stays and plays its fall; a culled one is simply removed.
			var node: ActorModel = _enemies[id]
			_enemies.erase(id)
			_emem.erase(id)
			if _died_here(node):
				# One of its deaths, by its id: half the horde falls one way.
				node.play("die_low" if node.crawling else "die", 1.0, true, 0.2, "", int(id))
				node.lie_down(true)
				node.tint(Color.TRANSPARENT)
				_corpses[id] = {"node": node, "t": 0.0}
			else:
				node.queue_free()


## A body that vanished near a fresh corpse died; one that vanished with
## no corpse under it was culled by the spawner, and leaves no body.
func _died_here(node: ActorModel) -> bool:
	var at := Units.to2(node.position)
	for c in sim.enemies.corpses:
		if c.t < 0.5 and Vector2(c.x, c.y).distance_to(at) < 48.0:
			return true
	return false


func _update_enemy(node: ActorModel, e: EnemySim, dt: float) -> void:
	node.visible = true
	node.position = Units.to3(Util.render_pos(e.prev_pos, e.pos))
	node.face(e.angle)
	var speed := Units.m((e.pos - e.prev_pos).length()) * STEPS_PER_SEC
	if e.def.get("boss", false) and _boss_body(node, e, speed, dt):
		_tint_enemy(node, e)
		return
	var m: Dictionary = _emem[e.id]
	# A swing begins when the windup appears; each one is the next of the
	# body's swings, so a walker takes turns between its swipe and its bite.
	var swinging := e.windup > 0.0 and float(m.wind) <= 0.0
	m.wind = e.windup
	if swinging:
		m.swings = int(m.swings) + 1
	var down := e.crawl_t > 0.0
	node.crawling = down or e.getup_t > 0.0
	# On the ground, the bite is a low one; getting up it does nothing and the
	# clip is stretched to take exactly as long as the sim holds it there.
	var swing := "bite_low" if down else "attack"
	if e.getup_t > 0.0:
		node.play("getup", _fit(node, "getup", float(Config.CRAWL.getup)))
	elif e.stagger_t > 0.0 and node.state != "hurt":
		node.play("hurt", _fit(node, "hurt", maxf(e.stagger_t, 0.4)), true)
	elif e.feed_t > 0.0:
		# Over a body: bends down, feeds, stands back up, in the time the sim
		# holds it there.
		node.play("eat", _fit(node, "eat", float(Config.FEED.time)))
	elif swinging:
		node.play(swing, _fit(node, swing, maxf(0.3, float(e.windup) * 1.6), "", int(m.swings)), true, 0.2, "", int(m.swings))
	elif node.busy() and node.state != "eat":
		# A meal is the sim's clock, not the clip's: hit, it looks up at once
		# (`feed_t` is zero) rather than finishing its five seconds bent over
		# a body it is already walking away from (Codex, PR #75).
		pass
	elif down:
		node.play("crawl", _pace(node, "crawl", speed))
	elif speed > 0.3:
		if speed > float(node.table.get("run_over", 3.0)):
			node.play("run", _pace(node, "run", speed))
		else:
			node.play("walk", _pace(node, "walk", speed))
	else:
		node.play("idle")
	_tint_enemy(node, e)


## A boss's scripted moments: the cue its last event set, played so the clip's
## strike falls when the tell runs out, and before its first event the floor.
## True while one of those owns the body; between them the boss walks and
## bites like anything else.
func _boss_body(node: ActorModel, e: EnemySim, speed: float, dt: float) -> bool:
	var cue: Dictionary = _cues.get(e.id, {})
	if not cue.is_empty():
		cue.t += dt
		if cue.t >= cue.dur:
			_cues.erase(e.id)
			# Whatever is left of the clip (a slam's landing) runs at its own
			# pace, so a slow-fitted tell does not leave a slow-motion recovery.
			node.play(cue.state, 1.0)
			return false
		if cue.fresh:
			cue.fresh = false
			var strike := node.clip_strike(cue.state)
			var rate := 1.0
			if strike > 0.0:
				rate = clampf(strike / cue.dur, 0.4, 4.0)
			elif not (cue.state in Models.LOOPING):
				rate = _fit(node, cue.state, cue.dur)
			node.play(cue.state, rate, true)
		return true
	if not _awake.has(e.id) and e.hp >= e.max_hp and speed < 0.3:
		node.play("asleep")
		return true
	return false


func _tint_enemy(node: ActorModel, e: EnemySim) -> void:
	if e.flash > 0.0:
		node.tint(Color(1, 1, 1, 0.7))
	elif e.burn_t > 0.0:
		node.tint(Color(1, 0.45, 0.1, 0.45 + 0.2 * sin(e.anim * 3.0)))
	elif e.bleed_t > 0.0:
		node.tint(Color(0.6, 0.05, 0.05, 0.35))
	else:
		node.tint(Color.TRANSPARENT)


func _frame_corpses(dt: float) -> void:
	for id in _corpses.keys():
		var c: Dictionary = _corpses[id]
		c.t += dt
		var node: ActorModel = c.node
		if c.t >= CORPSE_LIFE:
			node.queue_free()
			_corpses.erase(id)
			continue
		node.fade(clampf((c.t - (CORPSE_LIFE - CORPSE_FADE)) / CORPSE_FADE, 0.0, 1.0))


# ---------------------------------------------------------------- helpers --

## Playback speed so a clip runs in `seconds`.
static func _fit(node: ActorModel, s: String, seconds: float, family := "", variant := 0) -> float:
	var len := node.clip_length(s, family, variant)
	if len <= 0.0 or seconds <= 0.0:
		return 1.0
	return clampf(len / seconds, 0.5, 4.0)


## Playback speed so the feet keep up with the ground, up to `cap`: the clip
## for `state` was animated at some metres per second (it says so) and the
## body moves at `speed`.
static func _pace(node: ActorModel, state: String, speed: float, family := "", cap := 2.2) -> float:
	var natural := node.clip_speed(state, family)
	if natural <= 0.0:
		natural = 1.4
	return clampf(speed / natural, 0.6, cap)


## A capsule's height from its radius: a brute is as tall as it is wide-ish.
static func _height_for(e: EnemySim) -> float:
	return clampf(Units.m(e.r) * 4.2, 1.2, 2.6)
