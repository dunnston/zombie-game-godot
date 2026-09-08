class_name Damage
## Central damage resolution for enemies and players, so combat and enemies
## never need to know about each other. Every function takes the acting
## player where there is one (invariant 8): kill XP, threat and quiet all
## belong to whoever did it.


## `source` is the PlayerSim for a player's own hit, or a tag ("turret",
## "trap") for anything automated.
##
## `no_alert` and `no_fx` are both for damage over time, and they are separate
## because they solve separate problems. A burn ticks sixty times a second:
## `no_alert` stops it re-startling the enemy on every tick, and `no_fx` stops
## it emitting a `hit` event on every tick — which the effects view answers
## with seven blood particles and a damage number, so one enemy surviving a
## 6.5-second burn would otherwise leave three thousand particles behind it
## and a burning horde would drop the frame rate through the floor.
static func damage_enemy(sim: GameSim, e: EnemySim, dmg: float, from: Vector2, knock := 0.0, crit := false, source: Variant = null, no_alert := false, no_fx := false) -> float:
	if e.dead or dmg <= 0.0:
		return 0.0
	e.hp -= dmg
	e.flash = 0.11
	if not no_alert:
		e.aggro = true
		e.alert_t = 6.0
	sim.stats.damage_dealt += dmg

	var dv := e.pos - from
	var len := dv.length()
	var dir := dv / len if len > 0.0 else Vector2.RIGHT
	if knock > 0.0:
		e.vel += dir * knock * (1.0 - e.knock_resist)
	if not no_fx:
		sim.emit({"t": "hit", "x": e.pos.x, "y": e.pos.y, "dx": dir.x, "dy": dir.y, "dmg": dmg, "crit": crit, "r": e.r})

	if e.hp <= 0.0:
		kill_enemy(sim, e, source)
	return dmg


static func kill_enemy(sim: GameSim, e: EnemySim, source: Variant = null) -> void:
	if e.dead:
		return
	e.dead = true
	sim.stats.kills += 1
	sim.enemies.corpses.append({"x": e.pos.x, "y": e.pos.y, "angle": e.angle, "type": e.type, "t": 0.0, "life": 45.0})
	if sim.enemies.corpses.size() > 90:
		sim.enemies.corpses.pop_front()
	sim.emit({"t": "kill", "x": e.pos.x, "y": e.pos.y, "type": e.type, "boss": e.def.get("boss", false)})
	# A body is worth searching. Small drops, but enough of them to keep a
	# gun fed between containers.
	Loot.enemy_drop(sim, e, source if source is PlayerSim else null)

	# Kill XP to the killer; automated kills pay everyone present. In solo
	# both rules are the same rule.
	# The raid bonus is for putting down raiders. An ambient walker that
	# happened to be standing there when the horde arrived is not worth more
	# for it — same `e.raid` flag the progress and quiet rules below use.
	var xp: int = e.def.xp
	if sim.raid != null and e.raid:
		xp = roundi(xp * Config.RAID.kill_xp_mul)
	if source is PlayerSim:
		Progression.add_xp(sim, source, xp, "KILL")
	else:
		for p in sim.players:
			Progression.add_xp(sim, p, xp, "KILL")
	if sim.raid == null:
		sim.threat.add(sim, Config.THREAT.kill_walk * e.def.threat, source if source is PlayerSim else null)
	# Only raiders count toward the raid; ambient kills mid-raid are not
	# progress and must not buy a share of the payout.
	if sim.raid != null and e.raid:
		sim.raid.killed += 1
	# Clearing ground buys a breather there. Raid kills do not: a raid is a
	# bounded event, and surviving one should not hand you a free lull.
	if not e.raid:
		sim.quiet.add_quiet(e.pos.x, e.pos.y)


static func damage_player(sim: GameSim, p: PlayerSim, amount: float, from: Vector2, label := "") -> float:
	if p == null or p.dead or p.invuln > 0.0 or p.god_mode:
		return 0.0
	var dealt := maxf(1.0, amount * (1.0 - p.armor_dr))
	p.hp -= dealt
	p.invuln = Config.PLAYER.invuln_after_hit
	p.hurt_flash = 0.35
	p.last_hurt = 0.0
	# Being hit interrupts healing: no free patching mid-fight.
	p.using = {}
	sim.stats.damage_taken += dealt

	var dv := p.pos - from
	var len := dv.length()
	var dir := dv / len if len > 0.0 else Vector2.RIGHT
	p.vel += dir * 90.0
	sim.emit({"t": "player_hit", "seat": p.seat, "x": p.pos.x, "y": p.pos.y, "dx": dir.x, "dy": dir.y, "dmg": dealt, "label": label})

	# Second Wind catches the blow that would have killed you, once every two
	# minutes. It is checked here rather than in kill_player so that the
	# other ways to die — and a later co-op down — are not silently immortal.
	if p.hp <= 0.0 and p.second_wind and p.second_wind_cd <= 0.0:
		p.hp = 1.0
		p.second_wind_cd = Config.SECOND_WIND_CD
		p.invuln = maxf(p.invuln, Config.PLAYER.invuln_after_hit)
		sim.notify("SECOND WIND", "#ffe08a", true)
		sim.emit({"t": "second_wind", "x": p.pos.x, "y": p.pos.y})
		return dealt
	if p.hp <= 0.0:
		kill_player(sim, p)
	return dealt


## Alone, running out of health is the death it always was: three seconds,
## then a respawn on safe ground. Downed-not-dead arrives with co-op.
static func kill_player(sim: GameSim, p: PlayerSim) -> void:
	if p.dead:
		return
	p.dead = true
	p.hp = 0.0
	p.respawn_t = Config.PLAYER.respawn_time
	p.reloading = {}
	p.using = {}
	p.swing = {}
	p.searching = {}
	sim.stats.deaths += 1
	sim.emit({"t": "player_died", "seat": p.seat, "x": p.pos.x, "y": p.pos.y})
	# Everything you were carrying stays where you fell, in a pack you can
	# walk back to. You keep the starting weapon, so a respawn is never
	# completely toothless.
	var pack := Loot.drop_backpack(sim, p)
	sim.notify("YOU DIED" if pack.is_empty() else "YOU DIED — your pack is where you fell", "#e05a4a", true)


## Damage over time on a player: fire, and whatever else ticks every frame.
##
## It cannot go through `damage_player`, which is built for discrete hits and
## does two things that are wrong here. It floors every accepted hit at 1,
## which would turn 16 dps into 60 — and it grants `invuln_after_hit`, which
## would make standing in a fire the safest place in the game, because those
## same i-frames are what stop a zombie hitting you. Fire is a cost, not a
## shield.
##
## So this applies the exact amount, respects armour, and touches neither the
## invulnerability window nor the healing interrupt.
static func burn_player(sim: GameSim, p: PlayerSim, amount: float, from: Vector2) -> float:
	if p == null or p.dead or p.god_mode or amount <= 0.0:
		return 0.0
	var dealt := amount * (1.0 - p.armor_dr)
	p.hp -= dealt
	p.last_hurt = 0.0
	sim.stats.damage_taken += dealt
	# One flash per burn tick would strobe; the view reads `hurt_flash` as a
	# level, so nudging it keeps the player tinted while they stand in it.
	p.hurt_flash = maxf(p.hurt_flash, 0.18)

	if p.hp <= 0.0 and p.second_wind and p.second_wind_cd <= 0.0:
		p.hp = 1.0
		p.second_wind_cd = Config.SECOND_WIND_CD
		sim.notify("SECOND WIND", "#ffe08a", true)
		sim.emit({"t": "second_wind", "x": p.pos.x, "y": p.pos.y})
		return dealt
	if p.hp <= 0.0:
		sim.emit({"t": "player_hit", "seat": p.seat, "x": p.pos.x, "y": p.pos.y,
			"dx": 0.0, "dy": -1.0, "dmg": dealt, "label": "fire"})
		kill_player(sim, p)
	return dealt


static func heal_player(sim: GameSim, p: PlayerSim, amount: float) -> float:
	var before := p.hp
	p.hp = minf(p.max_hp, p.hp + amount * p.heal_mul)
	var gained := p.hp - before
	if gained > 0.0:
		sim.emit({"t": "heal", "x": p.pos.x, "y": p.pos.y, "amount": gained})
	return gained


static func respawn_player(sim: GameSim, p: PlayerSim) -> void:
	# A bedroll is a respawn point: waking up beside your own base is the
	# whole reason to have built one.
	var at_bedroll := false
	if p.spawn_tile.x >= 0:
		var bed := sim.structs.at_tile(p.spawn_tile.x, p.spawn_tile.y)
		if not bed.is_empty() and bed.type == "bedroll":
			p.pos = sim.world.unstick(bed.pos + Vector2(0, Config.TILE), p.r, sim.structs)
			at_bedroll = true
		else:
			p.spawn_tile = Vector2i(-1, -1)
	var spot := p.pos if at_bedroll else sim.pick_random_spawn(Vector2.INF, 0.0, 520.0)
	p.pos = spot
	p.vel = Vector2.ZERO
	p.hp = p.max_hp
	p.stam = p.max_stam
	p.winded = false
	p.dead = false
	p.invuln = 2.2
	p.reloading = {}
	p.using = {}
	p.slot = clampi(p.slot, 0, maxi(0, p.hotbar.size() - 1))
	sim.emit({"t": "respawn", "seat": p.seat, "x": p.pos.x, "y": p.pos.y})
	sim.notify("You wake up at your bedroll" if at_bedroll else "Respawned somewhere in the wild", "#9fd0ff", true)
