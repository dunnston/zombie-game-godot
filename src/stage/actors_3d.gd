class_name Actors3D
extends Node3D
## Every player and enemy on the 3D stage, one `ActorModel` each, created
## and freed as the sim's lists change and told what to be every frame from
## the same fields the 2D views read: where it is drawn (interpolated), what
## it faces, what it is doing. A dead enemy's body stays where it fell for
## as long as the 2D corpse did, then fades.

## How long a body lies there: `Damage` gives a corpse 45 s, and a model
## has no record to read it from, so the number is here too.
const CORPSE_LIFE := 45.0
const CORPSE_FADE := 6.0
const STEPS_PER_SEC := 60.0

var sim: GameSim
var local: PlayerSim
var _players := {}     # seat -> ActorModel
var _enemies := {}     # enemy id -> ActorModel
var _corpses := {}     # enemy id -> {node, t}

## A boss's body does what its script does, learned from the script's events
## and never from the script: a guest's copy of a boss has no script (the
## 2026-09-10 decision that has `BossView` draw from events). Enemy id ->
## {state, dur, t}: the clip for the move and how long the sim gives it.
var _cues := {}
## Bosses that have woken. One that has not lies on the gym floor.
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
	_cues.clear()
	_awake.clear()


## Takes one event and returns the state it cues, or "", so a test can assert
## on the decision (the shape `BossView.on_event` has).
func on_event(ev: Dictionary) -> String:
	match String(ev.t):
		"boss_wake":
			_awake[int(ev.id)] = true
			return _cue(int(ev.id), "wake", 1.2)
		"boss_tell":
			return _cue(int(ev.id), String(MOVE_CLIP.get(String(ev.move), "attack")), float(ev.dur))
		"boss_stunned":
			return _cue(int(ev.id), "stun", float(ev.dur))
		"boss_phase":
			_awake[int(ev.id)] = true
			return _cue(int(ev.id), "roar", _transition_of(int(ev.id)))
	return ""


func _cue(id: int, state: String, dur: float) -> String:
	_cues[id] = {"state": state, "dur": maxf(0.05, dur), "t": 0.0, "fresh": true}
	return state


## How long a boss's phase change holds it, from its table; 1.2 s for one the
## sim no longer lists.
func _transition_of(id: int) -> float:
	for e in sim.enemies.list:
		if e.id == id:
			return float(Config.BOSSES.get(e.type, {}).get("transition", 1.2))
	return 1.2


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
		_update_player(node, p, dt)
	for seat in _players.keys():
		if not seen.has(seat):
			_players[seat].queue_free()
			_players.erase(seat)


func _update_player(node: ActorModel, p: PlayerSim, _dt: float) -> void:
	if p.away:
		node.visible = false
		return
	# Invulnerable after a hit: blink, per player, as the 2D body does.
	node.visible = not (p.invuln > 0.0 and int(p.invuln * 20.0) % 2 == 0)
	var at := Util.render_pos(p.prev_pos, p.pos)
	node.position = Units.to3(at)
	node.face(p.angle)
	var w := p.weapon()
	node.hold(Color(w.get("color", "#2b2b2b")), 0.62 if w.kind == "gun" else 0.5)
	if p.dead:
		node.play("die")
		node.lie_down(true)
		node.tint(Color.TRANSPARENT)
		return
	node.lie_down(false)
	if p.downed:
		node.play("downed")
		return
	var speed := Units.m((p.pos - p.prev_pos).length()) * STEPS_PER_SEC
	if p.dash_t > 0.0:
		node.play("dash", _fit(node, "dash", float(Config.DASH.time) * 2.0))
	elif not p.swing.is_empty():
		node.play("attack", _fit(node, "attack", float(p.swing.dur)))
	elif not p.reloading.is_empty():
		node.play("reload", _fit(node, "reload", float(p.reloading.dur)))
	elif node.busy():
		pass
	elif speed > 0.3:
		if p.sneaking:
			node.play("sneak", _pace(node, "walk", speed))
		elif speed > 3.0:
			node.play("run", _pace(node, "run", speed))
		else:
			node.play("walk", _pace(node, "walk", speed))
	else:
		node.play("idle")
	if p.hurt_flash > 0.0:
		node.tint(Color(1, 0.3, 0.2, 0.6 * clampf(p.hurt_flash * 2.0, 0.0, 1.0)))
	else:
		node.tint(Color.TRANSPARENT)


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
		_update_enemy(node, e, dt)
	for id in _enemies.keys():
		if not seen.has(id):
			# Gone from the list: it died (or was culled far away). The body
			# stays and plays its fall; a culled one is simply removed.
			var node: ActorModel = _enemies[id]
			_enemies.erase(id)
			if _died_here(node):
				node.play("die_low" if node.crawling else "die", 1.0, true)
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
	var down := e.crawl_t > 0.0
	node.crawling = down or e.getup_t > 0.0
	# On the ground, the bite is a low one; getting up it does nothing and the
	# clip is stretched to take exactly as long as the sim holds it there.
	var swing := "bite_low" if down else "attack"
	if e.getup_t > 0.0:
		node.play("getup", _fit(node, "getup", float(Config.CRAWL.getup)))
	elif e.stagger_t > 0.0 and node.state != "hurt":
		node.play("hurt", _fit(node, "hurt", maxf(e.stagger_t, 0.4)), true)
	elif e.windup > 0.0 and node.state != swing:
		node.play(swing, _fit(node, swing, maxf(0.3, float(e.windup) * 1.6)), true)
	elif node.busy():
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
static func _fit(node: ActorModel, s: String, seconds: float) -> float:
	var len := node.clip_length(s)
	if len <= 0.0 or seconds <= 0.0:
		return 1.0
	return clampf(len / seconds, 0.5, 4.0)


## Playback speed so the feet keep up with the ground: the clip for `state`
## was animated at some metres per second (it says so) and the body moves at
## `speed`.
static func _pace(node: ActorModel, state: String, speed: float) -> float:
	var natural := node.clip_speed(state)
	if natural <= 0.0:
		natural = 1.4
	return clampf(speed / natural, 0.6, 2.2)


## A capsule's height from its radius: a brute is as tall as it is wide-ish.
static func _height_for(e: EnemySim) -> float:
	return clampf(Units.m(e.r) * 4.2, 1.2, 2.6)
