class_name Combat
## Projectiles, melee swings, guns and reloads.
##
## Bullets are blocked by terrain and pass over player structures (Phase 3):
## top-down, your barricades are chest height, and a base you cannot shoot
## out of punishes you for building it. Water and fences go the other way.

const P := Config.PLAYER
const HARVEST := Config.HARVEST

static var _scratch: Array = []


# ------------------------------------------------------------------ bullets --

## `owner` is the PlayerSim that fired, or a tag string for anything
## automated. Everything else is the weapon row's numbers, already scaled.
static func spawn_bullet(sim: GameSim, at: Vector2, angle: float, speed: float, dmg: float, life: float, knock := 0.0, pierce := 0, owner: Variant = null, crit := false, weapon := "", color := "#ffe6a8") -> Dictionary:
	var b := {
		"pos": at, "prev": at,
		"vel": Vector2.from_angle(angle) * speed,
		"dmg": dmg, "life": life, "knock": knock, "pierce": pierce,
		"hits": [], "owner": owner, "crit": crit, "w": weapon, "color": color,
	}
	sim.bullets.append(b)
	# Speed, life and colour ride the event so a guest's tracer is the round
	# the host fired — a boss's slow ball as much as a rifle's streak — rather
	# than whatever its weapon row would guess.
	sim.emit({"t": "shot", "x": at.x, "y": at.y, "a": angle, "w": weapon, "sp": speed, "lf": life, "c": color})
	return b


static func tick_bullets(sim: GameSim, dt: float) -> void:
	var world := sim.world
	var hash := sim.enemies.hash
	for i in range(sim.bullets.size() - 1, -1, -1):
		var b: Dictionary = sim.bullets[i]
		b.life -= dt
		if b.life <= 0.0:
			sim.bullets.remove_at(i)
			continue
		b.prev = b.pos
		# Substep so a fast round cannot tunnel through a one-tile wall.
		var vel: Vector2 = b.vel
		var dist := vel.length() * dt
		var steps := maxi(1, ceili(dist / 12.0))
		var step := vel * dt / steps
		var done := false
		for s in range(steps):
			b.pos += step
			var pos: Vector2 = b.pos
			if world.bullet_blocks_px(pos.x, pos.y):
				sim.emit({"t": "bullet_wall", "x": pos.x, "y": pos.y, "dx": -vel.x, "dy": -vel.y})
				done = true
				break
			# A round fired *by* something looks for people, not for enemies.
			# One branch rather than a second bullet list: everything else
			# about a bullet — the substep, terrain, the trail — is the same
			# whoever pulled the trigger.
			if b.get("hostile", false):
				if _hit_someone(sim, b, pos):
					done = true
					break
				continue
			hash.query(pos.x, pos.y, 26.0, _scratch)
			for e: EnemySim in _scratch:
				if e.dead or b.hits.has(e):
					continue
				var rr := e.r + 2.2
				if pos.distance_squared_to(e.pos) > rr * rr:
					continue
				Damage.damage_enemy(sim, e, b.dmg, b.prev, b.knock, b.crit, b.owner)
				# A round that carries one. Pierce keeps it at full strength
				# for the body behind: a rifle bullet through two walkers
				# rocks both, and the per-enemy immunity is what stops that
				# being a problem.
				Damage.stagger_enemy(sim, e, b.get("stagger", 0.0), b.crit)
				if b.pierce > 0:
					b.pierce -= 1
					b.dmg *= 0.75
					b.hits.append(e)
				else:
					done = true
				break
			if done:
				break
		if done:
			sim.bullets.remove_at(i)


## Whoever a hostile round has just reached: a player first, then one of your
## people. Their bullets do not hit each other — there is no friendly fire
## between raiders, and adding it would mostly mean watching a crew shoot
## itself apart behind a wall.
static func _hit_someone(sim: GameSim, b: Dictionary, pos: Vector2) -> bool:
	for p in sim.players:
		if p.dead or p.away or p.downed:
			continue
		var rr := p.r + 2.2
		if pos.distance_squared_to(p.pos) > rr * rr:
			continue
		var who := b.owner as EnemySim
		Damage.damage_player(sim, p, b.dmg, b.prev, String(who.def.name) if who != null else "Gunfire")
		return true
	for s in sim.crew.list:
		if s.dead:
			continue
		var sr: float = Config.SURVIVOR.r + 2.2
		if pos.distance_squared_to(s.pos) > sr * sr:
			continue
		sim.crew.damage(sim, s, b.dmg, b.prev)
		return true
	return false


# --------------------------------------------------------------------- crit --

## How often a hit with `w` lands as a critical, and how hard it lands when it
## does. **These two are the only place either question is answered**, which is
## the point of them: before, `melee_attack` rolled `crit_chance + 0.06` at
## 1.9x and `fire_gun` rolled `crit_chance` at 1.8x, so a Stone Knife and a
## Sledgehammer critted identically and no piece of content could say otherwise.
##
## The player's half — Luck, Lucky Strike, gloves, the Mutation band, whatever
## is still on the effect clock — arrives already summed and already capped by
## `recompute_stats`, which is invariant 4 doing its job. All that is left here
## is the weapon in the hand.
static func crit_chance(p: PlayerSim, w: Dictionary) -> float:
	return clampf(p.crit_chance + float(w.get("crit", 0.0)), 0.0, Config.MAX_CRIT)


## The weapon's own multiplier, plus whatever the player carries as `crit_dmg`.
## Additive rather than multiplied so a buff reads as what it says: Surge is
## "+0.3 on a critical", not "+30% of whatever you happen to be holding".
static func crit_mul(p: PlayerSim, w: Dictionary) -> float:
	return float(w.get("crit_mul", Config.CRIT_MUL_DEFAULT)) + p.crit_dmg


# -------------------------------------------------------------------- melee --

## Everything a swing of `w` would connect with, nearest first.
static func melee_targets(sim: GameSim, p: PlayerSim, w: Dictionary) -> Array[EnemySim]:
	var reach: float = w.range + p.r
	var half_arc: float = w.arc / 2.0
	var max_targets := 6 if w.arc > 1.4 else 3
	var out: Array[EnemySim] = []
	sim.enemies.hash.query(p.pos.x, p.pos.y, reach + 24.0, _scratch)
	for e: EnemySim in _scratch:
		if e.dead:
			continue
		var d2 := e.pos.distance_squared_to(p.pos)
		if d2 >= (reach + e.r) * (reach + e.r):
			continue
		var a := Enemies.angle_delta(p.angle, (e.pos - p.pos).angle())
		if absf(a) >= half_arc + e.r / reach:
			continue
		# A swing has to reach it. Collision keeps two bodies 32px apart
		# across a one-tile wall, which a scythe's 73px of reach clears
		# comfortably. Same rule bullets use, so water and fences are swung
		# over and only what stops a round stops a blade.
		if not sim.world.has_terrain_line_of_sight(p.pos, e.pos):
			continue
		out.append(e)
	out.sort_custom(func(a: EnemySim, b: EnemySim) -> bool:
		return a.pos.distance_squared_to(p.pos) < b.pos.distance_squared_to(p.pos))
	if out.size() > max_targets:
		out.resize(max_targets)
	return out


## One melee swing. Returns true if it happened. This is the only place that
## knows whether a swing was a fight or a job: the arc is searched for
## enemies first, and only an empty arc falls through to the scenery.
##
## Every swing costs, and nothing is ever refused for want of puff — a swing
## at nothing costs a fight's worth, a harvest costs `Stamina.chop_cost` and
## rests longer afterwards. Running the bar flat does not stop you working: it
## makes the swing slow (`swing_rate_mul`), which is what makes three trees a
## decision now that refusing them no longer does.
static func melee_attack(sim: GameSim, p: PlayerSim, w: Dictionary) -> bool:
	if refuse_broken(sim, p, w):
		return false
	var reach: float = w.range + p.r
	var dmg: float = w.dmg * p.melee_mul * Upgrade.held_mul(p) * (Config.ADRENALINE_MELEE if p.adrenaline_active else 1.0)
	var hits := melee_targets(sim, p, w)

	# The animation stretches with the cooldown, or a winded swing would snap
	# at full speed and only the gap after it would grow, which reads as lag
	# rather than as fatigue.
	p.swing = {"t": 0.0, "dur": minf(0.26, w.cd * 0.75) * p.swing_rate_mul,
		"angle": p.angle, "arc": w.arc, "range": reach}
	sim.emit({"t": "swing", "seat": p.seat, "x": p.pos.x, "y": p.pos.y, "a": p.angle})

	if not hits.is_empty():
		Stamina.spend(p, Stamina.swing_cost(p, w))
		sim.emit({"t": "shake", "amount": w.get("shake", 1.6)})
		var chance := crit_chance(p, w)
		var mul := crit_mul(p, w)
		var stagger: float = w.get("stagger", 0.0)
		var bleed: float = w.get("bleed", 0.0)
		for e in hits:
			var crit := sim.rng.chance(chance)
			Damage.damage_enemy(sim, e, dmg * (mul if crit else 1.0), p.pos, w.knock, crit, p, false, false, "melee")
			# Both after the damage, and both refused on a corpse by their own
			# `dead` check, so neither is spent on something this swing has
			# already put down. No weapon carries both — blunt things stagger
			# and edged things bleed — but nothing here has to know that.
			Damage.stagger_enemy(sim, e, stagger, crit)
			Damage.bleed_enemy(e, bleed, p)
		Wear.use_held(sim, p, 1)
	elif chop_prop(sim, p, w, dmg):
		Stamina.spend(p, Stamina.chop_cost(p, w), P.stam_chop_delay)
		# Work is what actually blunts a tool, so it costs more than a fight.
		Wear.use_held(sim, p, int(Config.WEAR.chop_mul))
	else:
		# A swing at nothing, or one that bounced off a tree for want of an
		# axe, still cost you the swing. It moved no material, so it is
		# charged at the fighting rate rather than the working one.
		Stamina.spend(p, Stamina.swing_cost(p, w))
	return true


## The tile a swing would land on, if it holds scenery this weapon could
## actually harvest. Swinging a pipe at a tree should say "you need a
## hatchet", not "you are too tired".
static func prop_in_front(sim: GameSim, p: PlayerSim, w: Dictionary) -> Dictionary:
	var reach: float = w.range + p.r
	var at := p.pos + Vector2.from_angle(p.angle) * reach * 0.7
	var prop := sim.world.prop_at_tile(floori(at.x / Config.TILE), floori(at.y / Config.TILE))
	if prop.is_empty():
		return {}
	# Defensive: everything on the prop grid today is harvestable, but the
	# grid is what fire walks to find scenery, and the moment anything without
	# a `harvest` is indexed there this is the line that would have crashed.
	var rule: Dictionary = HARVEST.get(prop.get("harvest", ""), {})
	if rule.is_empty() or (rule.has("needs") and not w.get(rule.needs, false)):
		return {}
	return prop


## How much harder than a punch this weapon hits scenery: a tool is built
## for it, and the tool made for this material is better again.
static func chop_multiplier(w: Dictionary, p: PlayerSim, rule: Dictionary) -> float:
	var boosted: bool = rule.has("boost") and w.get(rule.boost, false)
	var base: float = w.get("chop_mul", 1.0)
	return base * (1.6 if boosted else 1.0) * p.chop_mul


## Melee against harvestable scenery. Returns true only when the swing bit:
## a swing at nothing, or one that bounced off a tree for want of an axe,
## is charged as an ordinary swing because it moved no material.
static func chop_prop(sim: GameSim, p: PlayerSim, w: Dictionary, dmg: float) -> bool:
	var reach: float = w.range + p.r
	var at := p.pos + Vector2.from_angle(p.angle) * reach * 0.7
	var prop := sim.world.prop_at_tile(floori(at.x / Config.TILE), floori(at.y / Config.TILE))
	if prop.is_empty():
		return false
	var harvest := String(prop.get("harvest", ""))
	if harvest.is_empty():
		return false                 # scenery with nothing to give is not a chop
	var rule: Dictionary = HARVEST.get(harvest, HARVEST.wood)

	if rule.has("needs") and not w.get(rule.needs, false):
		if sim.time - p.needs_hint_at > 6.0:
			p.needs_hint_at = sim.time
			sim.notify(Config.NEEDS_HINT[rule.needs], "#d9c46a", true)
		sim.emit({"t": "bounce", "x": prop.x, "y": prop.y})
		return false

	var boosted: bool = rule.has("boost") and w.get(rule.boost, false)
	prop.hp -= dmg * chop_multiplier(w, p, rule)
	prop.flash = 0.12
	sim.emit({"t": "chop", "x": prop.x, "y": prop.y})
	# Work is audible: the other half of felling a tree in the open.
	Sound.make_noise(sim, prop.x, prop.y, Config.NOISE.chop, p)
	sim.emit({"t": "shake", "amount": 1.2})

	if prop.hp <= 0.0:
		var n: int = rule.min + roundi(sim.rng.next() * (rule.max - rule.min) * p.loot_mul)
		if boosted:
			n = roundi(n * w.get("tool_mul", 2.0))
		sim.world.remove_prop(prop)
		if prop.solid:
			sim.world_version += 1       # the flow fields have a new way through
		Loot.give_res_or_drop(sim, p, rule.res, n, p.pos)
		sim.emit({"t": "harvest", "x": prop.x, "y": prop.y, "res": rule.res, "n": n, "label": rule.label})
		if rule.has("bonus") and sim.rng.chance(0.8):
			var bonus: int = rule.bonus_min + roundi(sim.rng.next() * (rule.bonus_max - rule.bonus_min))
			Loot.give_res_or_drop(sim, p, rule.bonus, bonus, p.pos)
		Progression.add_xp(sim, p, rule.get("xp", 2), rule.label)
	return true


# --------------------------------------------------------------------- guns --

## A broken weapon does nothing at all until it is mended. It keeps its slot
## rather than crumbling away, because it is the thing you carry back to the
## bench — and because a weapon that vanished at zero would make "repair it"
## a promise the game could not keep.
##
## It refuses rather than degrading: one rule, visible on the hotbar long
## before it fires, instead of a weapon that has been quietly getting worse.
static func refuse_broken(sim: GameSim, p: PlayerSim, w: Dictionary) -> bool:
	if not Wear.held_broken(p):
		return false
	if sim.time - p.broken_told_at > 3.0:
		p.broken_told_at = sim.time
		sim.notify("%s is broken — mend it at the bench that made it" % w.name, "#c96a5a", true)
	sim.emit({"t": "deny", "x": p.pos.x, "y": p.pos.y})
	return true


static func fire_gun(sim: GameSim, p: PlayerSim, w: Dictionary) -> bool:
	if refuse_broken(sim, p, w):
		return false
	var mag: int = p.mag.get(w.id, 0)
	if mag <= 0:
		sim.emit({"t": "dryfire", "x": p.pos.x, "y": p.pos.y})
		start_reload(sim, p, w)
		return false
	# Ammo Cache (Phase 4 luck perk) sometimes gives the round back.
	if not (p.free_shot_chance > 0.0 and sim.rng.chance(p.free_shot_chance)):
		p.mag[w.id] = mag - 1

	var spread: float = w.spread * p.spread_mul
	var muzzle := p.pos + Vector2.from_angle(p.angle) * (p.r + 12.0)
	var pellets: int = w.get("pellets", 1)
	var color := "#c8a878" if w.get("bow", false) else ("#ffd08a" if w.id == "shotgun" else "#ffe6a8")
	var chance := crit_chance(p, w)
	var mul := crit_mul(p, w)
	var stagger: float = w.get("stagger", 0.0)
	for i in range(pellets):
		var a: float = p.angle + (sim.rng.next() - 0.5) * spread * 2.0
		var crit := sim.rng.chance(chance)
		var b := spawn_bullet(sim, muzzle, a,
			w.speed * (0.92 + sim.rng.next() * 0.16),
			w.dmg * p.gun_mul * Upgrade.held_mul(p) * (mul if crit else 1.0),
			w.life * p.range_mul, w.knock, w.get("pierce", 0), p, crit,
			w.id if i == 0 else "", color)   # one sound per shot, not per pellet
		# Written onto the round rather than passed in: `spawn_bullet` has
		# twelve parameters already, and this way every other source of a
		# bullet — a turret, a raider's rifle, the cosmetic tracer a guest
		# draws — carries no stagger by simply not having the key.
		#
		# All eight shotgun pellets carry it, and only the first to connect
		# does anything: the immunity window in `stagger_enemy` is what turns
		# a spread into one shove instead of eight.
		if stagger > 0.0:
			b.stagger = stagger

	# No flash from a bow: a muzzle flash is a light source at night, and a
	# bow that lit up the treeline would give away the one thing it is for.
	if not w.get("bow", false):
		sim.emit({"t": "muzzle", "x": muzzle.x, "y": muzzle.y, "a": p.angle, "w": w.id})
	sim.emit({"t": "shake", "amount": w.get("shake", 1.0)})
	# Recoil kick, so rapid fire visibly pushes the aim around.
	p.recoil = minf(0.16, p.recoil + spread * 1.4 + 0.012)
	p.vel -= Vector2.from_angle(p.angle) * (90.0 if w.id == "shotgun" else 22.0)

	sim.threat.add(sim, Config.THREAT.per_gunshot * w.threat, p)
	Sound.make_noise(sim, p.pos.x, p.pos.y, w.noise, p)
	Wear.use_held(sim, p, 1)
	return true


static func start_reload(sim: GameSim, p: PlayerSim, w: Dictionary) -> bool:
	if not w.has("ammo") or not p.reloading.is_empty():
		return false
	if p.mag.get(w.id, 0) >= w.mag:
		return false
	if p.count_res(w.ammo) <= 0:
		sim.notify("Out of %s" % Config.RES[w.ammo].name.to_lower(), "#c96a5a")
		sim.emit({"t": "dryfire", "x": p.pos.x, "y": p.pos.y})
		return false
	p.reloading = {"w": w.id, "t": 0.0, "dur": w.reload * p.reload_mul, "shell": w.get("shell_reload", false)}
	sim.emit({"t": "reload", "seat": p.seat})
	return true


static func _finish_reload_step(sim: GameSim, p: PlayerSim, w: Dictionary) -> void:
	if p.count_res(w.ammo) <= 0:
		p.reloading = {}
		return
	if w.get("shell_reload", false):
		# Shotguns load one shell at a time and can be interrupted by firing.
		p.take_res(w.ammo, 1)
		p.mag[w.id] = p.mag.get(w.id, 0) + 1
		if p.mag[w.id] >= w.mag or p.count_res(w.ammo) <= 0:
			p.reloading = {}
			sim.emit({"t": "reload_done", "seat": p.seat})
		else:
			p.reloading.t = 0.0
	else:
		var need: int = w.mag - p.mag.get(w.id, 0)
		p.mag[w.id] = p.mag.get(w.id, 0) + p.take_res(w.ammo, need)
		p.reloading = {}
		sim.emit({"t": "reload_done", "seat": p.seat})


static func tick_reload(sim: GameSim, p: PlayerSim, dt: float) -> void:
	if p.reloading.is_empty():
		return
	var w: Dictionary = Config.WEAPONS.get(p.reloading.w, {})
	if w.is_empty() or p.weapon().id != w.id:
		p.reloading = {}
		return
	p.reloading.t += dt
	if p.reloading.t >= p.reloading.dur:
		_finish_reload_step(sim, p, w)
