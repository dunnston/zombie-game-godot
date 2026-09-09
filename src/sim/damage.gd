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
## `hit_kind` is for the ears alone: a pipe connecting and a bullet landing
## are different sounds, and the hit event is the only place that knows which
## one happened. Nothing in the simulation reads it.
static func damage_enemy(sim: GameSim, e: EnemySim, dmg: float, from: Vector2, knock := 0.0, crit := false, source: Variant = null, no_alert := false, no_fx := false, hit_kind := "bullet") -> float:
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
		sim.emit({"t": "hit", "x": e.pos.x, "y": e.pos.y, "dx": dir.x, "dy": dir.y, "dmg": dmg, "crit": crit, "r": e.r, "kind": hit_kind})

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
		# A survivor's kill pays the survivor too, which is how a guard you
		# leave standing at the gate gets better at standing at the gate. The
		# tag carries their id: `survivor:3`.
		var tag := String(source) if source is String else ""
		if tag.begins_with("survivor:"):
			var sid := int(tag.substr(9))
			for s in sim.crew.list:
				if s.id == sid:
					s.kills += 1
					sim.crew.award_xp(sim, s, xp)
					break
		for p in sim.present_players():
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


## `bite` says the blow came from something with teeth — the one caller that
## passes it is a zombie's melee. It is what the Mutation meter listens for:
## a bullet or a fall can be heavy, but only a bite is a bite.
static func damage_player(sim: GameSim, p: PlayerSim, amount: float, from: Vector2, label := "", bite := false) -> float:
	if p == null or p.dead or p.downed or p.away or p.invuln > 0.0 or p.god_mode:
		return 0.0
	var dealt := maxf(1.0, amount * (1.0 - p.armor_dr))
	p.hp -= dealt
	p.invuln = Config.PLAYER.invuln_after_hit
	# Further along, you feel it less: the flash, the shove and the shake all
	# come off `stagger_mul`, which is 1.0 until the change takes hold.
	p.hurt_flash = 0.35 * p.stagger_mul
	p.last_hurt = 0.0
	# Being hit interrupts healing: no free patching mid-fight.
	p.using = {}
	sim.stats.damage_taken += dealt

	var dv := p.pos - from
	var len := dv.length()
	var dir := dv / len if len > 0.0 else Vector2.RIGHT
	p.vel += dir * 90.0 * p.stagger_mul
	sim.emit({"t": "player_hit", "seat": p.seat, "x": p.pos.x, "y": p.pos.y, "dx": dir.x, "dy": dir.y, "dmg": dealt, "label": label})
	# Before Second Wind and before falling: a bite that fills the meter turns
	# you, and turning is its own death rather than one Second Wind can catch.
	Mutation.on_damage(sim, p, dealt, bite)
	if p.dead:
		return dealt

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
		_fall(sim, p)
	return dealt


## Out of health. With a teammate standing, that is going down; alone it is
## death. One place decides, so fire and a bite agree.
static func _fall(sim: GameSim, p: PlayerSim) -> void:
	if sim.has_teammate_for(p):
		down_player(sim, p)
	else:
		kill_player(sim, p)


## Downed, not dead (Phase 5). Thirty seconds on the ground; a teammate
## holding E beside you brings you back at a fraction of your health. The
## horde loses interest in you — `nearest_player` skips the downed — which is
## what makes the walk back for them a decision rather than a sacrifice.
static func down_player(sim: GameSim, p: PlayerSim) -> void:
	if p.dead or p.downed:
		return
	p.downed = true
	p.hp = 0.0
	p.down_t = Config.PLAYER.downed_time
	# The body being overwhelmed. Before the rest of the bookkeeping, because
	# it can finish the meter and turn you where you lie.
	Mutation.on_down(sim, p)
	if p.dead:
		return
	p.vel = Vector2.ZERO
	p.reloading = {}
	p.using = {}
	p.swing = {}
	p.searching = {}
	p.reviving = {}
	if p.driving_id > 0:
		sim.cars.exit(sim, p)
	sim.emit({"t": "player_down", "seat": p.seat, "x": p.pos.x, "y": p.pos.y})
	sim.notify("%s IS DOWN — somebody get them up" % p.display_name.to_upper(), "#e05a4a", true)


## The bleed-out clock. Runs from the downed player's own tick.
static func tick_downed(sim: GameSim, p: PlayerSim, dt: float) -> void:
	p.down_t -= dt
	if p.down_t <= 0.0:
		p.downed = false
		kill_player(sim, p)


## A teammate finished getting `p` up.
static func revive_player(sim: GameSim, p: PlayerSim, by: PlayerSim) -> bool:
	if not p.downed or p.dead:
		return false
	p.downed = false
	p.down_t = 0.0
	p.hp = maxf(1.0, roundf(p.max_hp * Config.PLAYER.revive_hp_frac))
	p.invuln = maxf(p.invuln, 1.2)
	sim.emit({"t": "player_up", "seat": p.seat, "x": p.pos.x, "y": p.pos.y})
	sim.notify("%s is back on their feet" % p.display_name, "#b7e08a", true)
	if by != null:
		Progression.add_xp(sim, by, 20, "REVIVE")
	return true


## Running out of health with nobody to help is the death it always was:
## three seconds, then a respawn on safe ground. Bleeding out ends here too.
## `cause` is what the banner says. There is one other death in the game now —
## the Mutation meter reaching the top — and it deserves its own word without
## a second way to die growing beside this one.
static func kill_player(sim: GameSim, p: PlayerSim, cause := "died") -> void:
	if p.dead:
		return
	p.dead = true
	p.downed = false
	p.hp = 0.0
	p.respawn_t = Config.PLAYER.respawn_time
	p.reloading = {}
	p.using = {}
	p.swing = {}
	p.searching = {}
	p.reviving = {}
	sim.stats.deaths += 1
	sim.emit({"t": "player_died", "seat": p.seat, "x": p.pos.x, "y": p.pos.y, "cause": cause})
	# Everything you were carrying stays where you fell, in a pack you can
	# walk back to. You keep the starting weapon, so a respawn is never
	# completely toothless.
	var pack := Loot.drop_backpack(sim, p)
	var head := "YOU TURNED" if cause == "turned" else "YOU DIED"
	var col := "#b07ad0" if cause == "turned" else "#e05a4a"
	sim.notify(head if pack.is_empty() else head + " — your pack is where you fell", col, true)


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
	if p == null or p.dead or p.downed or p.away or p.god_mode or amount <= 0.0:
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
		_fall(sim, p)
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
	p.downed = false
	p.invuln = 2.2
	p.reloading = {}
	p.using = {}
	# Whatever was working through you is not: a bad brain does not follow you
	# past your own death. The Mutation meter does — that is the point of it.
	if not p.effects.is_empty():
		p.effects.clear()
		Equipment.recompute_stats(p)
		p.hp = p.max_hp
		p.stam = p.max_stam
	p.slot = clampi(p.slot, 0, maxi(0, p.hotbar.size() - 1))
	sim.emit({"t": "respawn", "seat": p.seat, "x": p.pos.x, "y": p.pos.y})
	sim.notify("You wake up at your bedroll" if at_bedroll else "Respawned somewhere in the wild", "#9fd0ff", true)
