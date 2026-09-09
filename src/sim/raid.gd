class_name Raid
extends RefCounted
## A raid: waves of raiders converge on the base — the nearest structure,
## once Phase 3 has structures; until then, on you — until every raider is
## dead, or nothing has happened for long enough that the horde gives up.

const R := Config.RAID

var index := 0
var spec: Dictionary
var centre := Vector2.ZERO
var has_base := false
var phase := "warning"
var timer := 0.0
var wave := 0
var spawned := 0
var killed := 0
var to_spawn := 0
var spawn_timer := 0.0
var total := 0
var elapsed := 0.0
var stall_check := R.stall_interval
var progress_check := 1.0
var retarget := 0.0
var idle := 0
var last_sig := ""
var inter_wave := R.inter_wave
var rng := Rng.new(0xF00DBEEF)
var ended := false
var repelled := false


static func start(sim: GameSim) -> Raid:
	var raid := Raid.new()
	raid.index = sim.raids_done
	raid.spec = Config.raid_spec(raid.index)
	var c := sim.base_centre()
	raid.centre = c.pos
	raid.has_base = c.has_base
	raid.timer = R.warning_time
	for w in range(raid.spec.waves):
		raid.total += raid.spec.base + raid.spec.growth * w
	sim.raid = raid
	sim.emit({"t": "raid_warn"})
	sim.notify("%s INCOMING — %ds" % [raid.spec.name, int(R.warning_time)], "#e05a4a", true)
	sim.notify("They are heading for your base" if c.has_base else "They are coming for you", "#d98a4a", true)
	return raid


func _pick_type() -> String:
	var r := rng.next()
	var acc := 0.0
	for t in spec.mix:
		acc += spec.mix[t]
		if r <= acc:
			return t
	return "walker"


func _start_wave(sim: GameSim) -> void:
	wave += 1
	to_spawn = spec.base + spec.growth * (wave - 1)
	spawn_timer = 0.0
	sim.notify("WAVE %d / %d" % [wave, spec.waves], "#e05a4a", true)
	sim.emit({"t": "raid_wave", "wave": wave})
	sim.emit({"t": "shake", "amount": 5.0})


func alive_count(sim: GameSim) -> int:
	var n := 0
	for e in sim.enemies.list:
		if e.raid and not e.dead:
			n += 1
	return n


func tick(sim: GameSim, dt: float) -> void:
	if phase == "warning":
		timer -= dt
		var c := sim.base_centre()
		centre = c.pos
		has_base = c.has_base
		if timer <= 0.0:
			phase = "active"
			_start_wave(sim)
		return

	# ------------------------------------------------------------- spawning --
	if to_spawn > 0:
		spawn_timer -= dt
		if spawn_timer <= 0.0 and sim.enemies.list.size() < Config.SPAWN.max_enemies:
			spawn_timer = R.spawn_interval
			# If everyone has wandered off, spawn around whoever is nearest
			# the base so the raid still finds someone to fight.
			var near := sim.nearest_player(centre)
			var anchor := centre
			if near != null and (not has_base or near.pos.distance_squared_to(centre) > R.anchor_on_player_beyond * R.anchor_on_player_beyond):
				anchor = near.pos
			# Close enough to arrive in seconds, far enough to stay off screen.
			# The body is picked first so the spot can be checked against it: a
			# tile centre is not room for a behemoth beside a wall.
			var type := _pick_type()
			var spot := sim.world.find_open_spot(rng, anchor, R.ring_min, R.ring_max, 40, Config.ENEMIES[type].r)
			if spot != Vector2.INF:
				var e := sim.enemies.spawn(type, spot, true, true, 1.0 + index * R.hp_per_index)
				if e != null:
					e.objective = sim.structs.raid_target(spot)
					spawned += 1
					to_spawn -= 1

	# Keep objectives fresh as walls fall: a raider whose wall is rubble
	# picks the next nearest rather than standing in the gap it made.
	retarget -= dt
	if retarget <= 0.0:
		retarget = 1.5
		for e in sim.enemies.list:
			if not e.raid or e.dead:
				continue
			if e.objective.is_empty() or e.objective.destroyed:
				e.objective = sim.structs.raid_target(e.pos)

	# Until Phase 3 there is no base, and a raid aimed at a person has to
	# follow them: the AI already chases the live player, so a frozen centre
	# would have the spawn anchor and the stall check below measuring a fight
	# that has since moved, and warp legitimate pursuers away from it.
	if not has_base:
		var live := sim.nearest_player(centre)
		if live != null:
			centre = live.pos

	# Anti-stall: a raider hung up on terrain would leave the raid
	# unwinnable. One that stops closing on the base is moved to a fresh lane.
	stall_check -= dt
	if stall_check <= 0.0:
		stall_check = R.stall_interval
		for e in sim.enemies.list:
			if not e.raid or e.dead:
				continue
			var d := e.pos.distance_to(centre)
			if e.last_raid_dist < 0.0:
				e.last_raid_dist = d
				e.raid_stall = 0.0
				continue
			# Only stalled if both far away and not getting closer.
			if d > R.stall_radius and d > e.last_raid_dist - R.stall_closing:
				e.raid_stall += R.stall_interval
			else:
				e.raid_stall = 0.0
			e.last_raid_dist = d
			if e.raid_stall >= R.stall_limit:
				var spot := sim.world.find_open_spot(rng, centre, R.relocate_min, R.relocate_max, 40, e.r)
				if spot != Vector2.INF:
					e.pos = spot
					e.last_pos = spot
					e.vel = Vector2.ZERO
					e.raid_stall = 0.0
					e.last_raid_dist = spot.distance_to(centre)
					e.objective = sim.structs.raid_target(spot)
					e.aggro = true

	# Break-off: watch actual progress — kills, structure damage (Phase 3),
	# damage to the player — and if none of it moves for long enough the
	# horde gives up and drifts away. "Kill them all" is unsatisfiable when
	# the last few are wedged in the ruins.
	progress_check -= dt
	if progress_check <= 0.0:
		progress_check = 1.0
		var player_hp := 0.0
		var players_down := 0
		for p in sim.present_players():
			player_hp += p.hp
			if p.dead:
				players_down += 1
		var sig := "%d|%d|%d|%d" % [killed, roundi(sim.structure_hp_total()), roundi(player_hp), players_down]
		idle = idle + 1 if sig == last_sig else 0
		last_sig = sig
	if idle >= R.breakoff_time:
		_scatter(sim, "The horde loses interest and drifts away" if has_base else "Nothing left to take — the horde scatters")
		return

	# Hard backstop: no raid may outlast this, whatever goes wrong.
	elapsed += dt
	if elapsed > R.max_seconds:
		_scatter(sim, "The horde breaks off and scatters")
		return

	# ------------------------------------------------------------ wave / end --
	if to_spawn <= 0 and alive_count(sim) == 0:
		if wave < spec.waves:
			inter_wave -= dt
			if inter_wave <= 0.0:
				inter_wave = R.inter_wave
				_start_wave(sim)
		else:
			_finish(sim, true)


## Ends a raid the player did not finish: the horde wanders off rather than
## being killed to the last. A full payout for a raid that flattened your
## base would make hiding better than defending.
func _scatter(sim: GameSim, message: String) -> void:
	sim.notify(message, "#d9c46a", true)
	for i in range(sim.enemies.list.size() - 1, -1, -1):
		if sim.enemies.list[i].raid:
			sim.enemies.list.remove_at(i)
	_finish(sim, false)


func _finish(sim: GameSim, repelled_: bool) -> void:
	# Paid on the share of the horde actually put down.
	var share := 1.0 if repelled_ else clampf(float(killed) / maxf(1.0, total), 0.0, 1.0)
	ended = true
	repelled = repelled_
	sim.raid = null
	sim.raids_done += 1
	sim.threat.reset_after_raid()

	# Salvage is the base's payout, so it goes into the base's stash where
	# there is one and falls through to the ground when that is full. With no
	# stash it lands in the nearest player's pockets — through the capped
	# path, so a payout to a full pack lands at their feet rather than
	# pushing them over the carry cap or vanishing into a full grid.
	var reward := {}
	var payee := sim.nearest_player(centre)
	for id in spec.reward:
		var n := floori(spec.reward[id] * share)
		if n <= 0:
			continue
		reward[id] = n
		if sim.stash != null:
			Loot.stash_or_drop(sim, id, n, centre)
		elif payee != null:
			Loot.give_res_or_drop(sim, payee, id, n, payee.pos)
	# XP is paid on the same share as the salvage. A floor here would pay
	# half the raid's XP for walking away from it without a single kill.
	for p in sim.present_players():
		Progression.add_xp(sim, p, spec.xp * share, "RAID")
	for e in sim.enemies.list:
		if e.raid:
			e.raid = false

	sim.emit({"t": "raid_end", "repelled": repelled_, "share": share})
	var tint := "#b7e08a" if repelled_ else "#d9c46a"
	sim.notify("%s %s" % [spec.name, "REPELLED" if repelled_ else "OVER"], tint, true)
	var parts: Array[String] = []
	for id in reward:
		parts.append("%s +%d" % [id, reward[id]])
	sim.notify("Salvage — " + "  ".join(parts) if not parts.is_empty() else "No salvage worth taking", tint, true)


## Debug and testing: ends a raid instantly as a win.
func force_end(sim: GameSim) -> void:
	for i in range(sim.enemies.list.size() - 1, -1, -1):
		if sim.enemies.list[i].raid:
			sim.enemies.list.remove_at(i)
	to_spawn = 0
	wave = spec.waves
	_finish(sim, true)
