class_name Survivors
extends RefCounted
## The people you rescued: who will follow you, where they sleep, what they do
## all day, and what it costs to keep them.
##
## Two rules run through everything here.
##
## **They eat and shoot out of the shared stash, never your pack.** That is
## what makes stocking the base a decision rather than a formality, and it is
## why a crew with a full player inventory beside them can still starve.
##
## **There is no pathfinding.** Invariant 6 is written about enemies and it is
## the same rule again: every walk to a container or a wall carries a give-up
## timer, and a target that stops getting closer is abandoned for another.
## Without it one shelf behind a locked gate holds a scavenger against it for
## the rest of the run.

const S := Config.SURVIVOR

var list: Array[SurvivorSim] = []
## Survivors still out there to be found: {pos, name, level}.
var rescues: Array[Dictionary] = []
var seq := 0

## Rations owed but not paid. Capped, so a long trip away is recoverable
## rather than a death spiral.
var debt := 0.0
var _upkeep_t := 0.0
var _ration_warned := -999.0
var _ammo_warned := -999.0
var _stash_warned := -999.0

var _scratch: Array[EnemySim] = []


func reset() -> void:
	list.clear()
	rescues.clear()
	seq = 0
	debt = 0.0
	_upkeep_t = 0.0
	_ration_warned = -999.0
	_ammo_warned = -999.0
	_stash_warned = -999.0


func alive() -> Array[SurvivorSim]:
	var out: Array[SurvivorSim] = []
	for s in list:
		if not s.dead:
			out.append(s)
	return out


# ---------------------------------------------------------------- the roster --

## Two independent limits, and the caller reports whichever is actually
## binding: Charisma is how many will follow you, bunks are how many you can
## house. Being told "no room" without being told which kind is useless.
func limits(sim: GameSim) -> Dictionary:
	var owner := sim.host()
	var charisma: int = maxi(0, roundi(owner.survivor_cap)) if owner != null else 0
	var bunks := 0
	for st in sim.structs.list:
		if st.destroyed:
			continue
		bunks += int(st.def.get("houses", 0))
	return {"charisma": charisma, "bunks": bunks, "cap": mini(charisma, bunks)}


func cap(sim: GameSim) -> int:
	return int(limits(sim).cap)


## Watchtowers with nobody posted on them.
func free_towers(sim: GameSim) -> Array[Dictionary]:
	var taken := {}
	for s in alive():
		if not s.tower.is_empty():
			taken[s.tower.get("tx", -1) * 100000 + s.tower.get("ty", -1)] = true
	var out: Array[Dictionary] = []
	for st in sim.structs.list:
		if st.destroyed or String(st.def.get("post", "")) != "sniper":
			continue
		if taken.has(st.tx * 100000 + st.ty):
			continue
		out.append(st)
	return out


func assign_job(sim: GameSim, s: SurvivorSim, job: String) -> bool:
	if not Config.JOBS.has(job) or s.dead:
		return false
	if job == "sniper":
		var tower := s.tower if not s.tower.is_empty() and not s.tower.destroyed else {}
		if tower.is_empty():
			var free := free_towers(sim)
			tower = free[0] if not free.is_empty() else {}
		if tower.is_empty():
			sim.notify("No free Watchtower to post them on", "#c96a5a")
			return false
		s.tower = tower
	else:
		s.tower = {}
	s.job = job
	s.job_t = 0.0
	# A haul came out of a real container, so reassignment must not delete it:
	# hand it in if a stash is close, otherwise put it on the ground.
	if not s.carrying.is_empty() or not s.carry_items.is_empty():
		var stash := _nearest_stash(sim, s.pos)
		if not stash.is_empty() and s.pos.distance_squared_to(stash.pos) < 260.0 * 260.0:
			_deliver(sim, s, stash)
		else:
			_drop_cargo(sim, s)
	# Jobs target different kinds of object, so a target left over from the
	# previous job is not merely stale, it is the wrong shape entirely.
	s.run_target = {}
	s.unreachable.clear()
	sim.notify("%s is now on %s duty" % [s.display_name, Config.JOBS[job].name], Config.JOBS[job].color)
	return true


func refresh_all(sim: GameSim) -> void:
	var owner := sim.host()
	for s in list:
		s.refresh(owner)


# ------------------------------------------------------------- recruiting --

## Scatters unrescued survivors around the town. Drawn from a stream of its
## own so that finding them cannot shift the world's or the spawner's numbers.
func seed_rescues(world: World, count: int = Config.RESCUE_COUNT) -> int:
	rescues.clear()
	var r := Rng.new((world.world_seed ^ 0x51F7) & 0x7FFFFFFF)
	# Prefer buildings: someone holed up indoors reads better than one stood in
	# a field.
	var candidates := world.containers
	if candidates.is_empty():
		return 0
	var guard := 0
	while rescues.size() < count and guard < count * 60:
		guard += 1
		var c: Dictionary = candidates[r.irange(0, candidates.size() - 1)]
		var at := Vector2(c.x + r.frange(-48.0, 48.0), c.y + r.frange(-48.0, 48.0))
		var tx := floori(at.x / Config.TILE)
		var ty := floori(at.y / Config.TILE)
		if tx < 2 or ty < 2 or tx >= Config.WORLD_TILES - 2 or ty >= Config.WORLD_TILES - 2:
			continue
		if world.is_blocked_tile(tx, ty):
			continue
		var too_close := false
		for other in rescues:
			if other.pos.distance_squared_to(at) < Config.RESCUE_SPACING * Config.RESCUE_SPACING:
				too_close = true
				break
		if too_close:
			continue
		rescues.append({
			"pos": at,
			"name": Config.SURVIVOR_NAMES[r.irange(0, Config.SURVIVOR_NAMES.size() - 1)],
			"level": 1 + r.irange(0, 1),
		})
	return rescues.size()


## Why this rescue cannot be taken in, in the player's terms, or "" if they
## can. Named separately from `recruit` so the interact prompt can show the
## reason before the player walks all the way over.
func recruit_refusal(sim: GameSim) -> String:
	var lim := limits(sim)
	var have := alive().size()
	if have < int(lim.cap):
		return ""
	if int(lim.bunks) <= have:
		return "Nowhere for them to sleep — build a Bunk first" if int(lim.bunks) == 0 \
			else "Every Bunk is taken (%d). Build another." % int(lim.bunks)
	if int(lim.charisma) <= have:
		return "Nobody will follow you yet — raise Charisma" if int(lim.charisma) == 0 \
			else "Only %d will follow you. Raise Charisma." % int(lim.charisma)
	return "No room"


func recruit(sim: GameSim, rescue: Dictionary, p: PlayerSim) -> SurvivorSim:
	var why := recruit_refusal(sim)
	if not why.is_empty():
		sim.notify(why, "#c96a5a", true)
		return null
	var s := make(sim, rescue.pos, String(rescue.name), int(rescue.level))
	rescues.erase(rescue)
	sim.emit({"t": "recruited", "x": s.pos.x, "y": s.pos.y, "name": s.display_name})
	sim.notify("%s joined you — they will hold the base" % s.display_name, "#b7e08a", true)
	Progression.add_xp(sim, p, 60, "RESCUE")
	return s


func make(sim: GameSim, at: Vector2, name_: String = "", level_: int = 1) -> SurvivorSim:
	seq += 1
	var nm := name_
	if nm.is_empty():
		nm = Config.SURVIVOR_NAMES[sim.rng.irange(0, Config.SURVIVOR_NAMES.size() - 1)]
	var s := SurvivorSim.new(at, nm, level_)
	s.id = seq
	s.cd = sim.rng.frange(0.0, 0.6)
	s.anim = sim.rng.frange(0.0, TAU)
	s.tint = Config.SURVIVOR_TINTS[sim.rng.irange(0, Config.SURVIVOR_TINTS.size() - 1)]
	s.refresh(sim.host())
	s.hp = s.max_hp
	list.append(s)
	return s


# ------------------------------------------------------------------ upkeep --

## The pantry is the stash, exactly like the ammunition they shoot. Rations in
## your own pack are no use to anyone until you drop them off.
func rations_held(sim: GameSim) -> int:
	return sim.stash.count("rations") if sim.stash != null else 0


func tick_upkeep(sim: GameSim, dt: float) -> void:
	var crew := alive()
	if crew.is_empty():
		_upkeep_t = 0.0
		return
	_upkeep_t += dt
	if _upkeep_t < S.upkeep_every:
		return
	var minutes: float = _upkeep_t / 60.0
	_upkeep_t = 0.0

	# Charge this tick's upkeep *plus* whatever is outstanding, so restocking
	# the pantry actually clears a shortage. Billing only the current tick
	# would leave any accrued debt permanent and the crew starving for ever.
	var owner := sim.host()
	var upkeep_mul: float = owner.upkeep_mul if owner != null else 1.0
	var need: float = crew.size() * S.upkeep_per_min * minutes * upkeep_mul
	var owed := need + debt
	var paid := 0
	if sim.stash != null:
		paid = sim.stash.take("rations", ceili(owed))
	debt = maxf(0.0, owed - paid)

	if debt > 1.0:
		# Hungry survivors are slower, shoot less often, and slowly starve
		# rather than vanishing.
		for s in crew:
			s.hungry = true
			s.hp = maxf(1.0, s.hp - 2.0)
		if sim.time - _ration_warned > S.warn_every:
			_ration_warned = sim.time
			sim.notify("Your people are out of Rations — stock the stash", "#e05a4a", true)
		debt = minf(debt, S.debt_cap)
	else:
		for s in crew:
			s.hungry = false


# ------------------------------------------------------------------ damage --

func damage(sim: GameSim, s: SurvivorSim, amount: float, from: Vector2) -> float:
	if s.dead or s.downed:
		return 0.0
	s.hp -= amount
	s.flash = 0.12
	var dir := (s.pos - from).normalized() if s.pos.distance_squared_to(from) > 0.01 else Vector2.RIGHT
	sim.emit({"t": "survivor_hit", "x": s.pos.x, "y": s.pos.y, "dx": dir.x, "dy": dir.y, "dmg": amount})
	if s.hp <= 0.0:
		s.hp = 0.0
		s.downed = true
		s.down_t = S.revive_time
		sim.notify("%s is down — get to them" % s.display_name, "#e05a4a", true)
		sim.emit({"t": "survivor_down", "x": s.pos.x, "y": s.pos.y, "name": s.display_name})
	return amount


## Fire and other damage over time, which must not read as a discrete hit.
func burn(sim: GameSim, s: SurvivorSim, amount: float) -> float:
	if s.dead or s.downed:
		return 0.0
	s.hp -= amount
	s.flash = maxf(s.flash, 0.1)
	if s.hp <= 0.0:
		s.hp = 0.0
		s.downed = true
		s.down_t = S.revive_time
		sim.notify("%s is down — get to them" % s.display_name, "#e05a4a", true)
		sim.emit({"t": "survivor_down", "x": s.pos.x, "y": s.pos.y, "name": s.display_name})
	return amount


func _kill(sim: GameSim, s: SurvivorSim) -> void:
	# Whatever they were carrying came out of a real container, so it falls
	# where they do rather than leaving with them.
	_drop_cargo(sim, s)
	s.dead = true
	s.downed = false
	sim.notify("%s is gone. Level %d." % [s.display_name, s.level], "#e05a4a", true)
	sim.emit({"t": "survivor_died", "x": s.pos.x, "y": s.pos.y, "name": s.display_name})
	sim.emit({"t": "shake", "amount": 6.0})


func revive(sim: GameSim, s: SurvivorSim, p: PlayerSim) -> bool:
	if not s.downed or s.dead:
		return false
	var held := func(id: String) -> int:
		return p.bag.count(id) + p.hotbar.count(id)
	var spend := func(id: String, n: int) -> void:
		var got := p.bag.take(id, n)
		if got < n:
			p.hotbar.take(id, n - got)
	if held.call("medkit") >= 1:
		spend.call("medkit", 1)
	elif held.call("bandage") >= 2:
		spend.call("bandage", 2)
	else:
		sim.notify("Need a medkit, or two bandages", "#c96a5a")
		return false
	s.downed = false
	s.hp = roundf(s.max_hp * S.revive_hp_frac)
	sim.notify("%s is back on their feet" % s.display_name, "#b7e08a")
	sim.emit({"t": "survivor_up", "x": s.pos.x, "y": s.pos.y, "name": s.display_name})
	Progression.add_xp(sim, p, 20, "REVIVE")
	return true


func award_xp(sim: GameSim, s: SurvivorSim, amount: float) -> void:
	var owner := sim.host()
	s.xp += amount * (owner.survivor_xp_mul if owner != null else 1.0)
	while s.level < int(S.max_level) and s.xp >= s.xp_to_next():
		s.xp -= s.xp_to_next()
		s.level += 1
		s.refresh(owner)
		s.hp = s.max_hp
		sim.emit({"t": "survivor_level", "x": s.pos.x, "y": s.pos.y, "name": s.display_name, "level": s.level})


# -------------------------------------------------------------------- step --

func tick(sim: GameSim, dt: float) -> void:
	tick_upkeep(sim, dt)
	if list.is_empty():
		return
	var owner := sim.host()
	var base := sim.base_centre()

	for i in range(list.size() - 1, -1, -1):
		var s := list[i]
		if s.dead:
			list.remove_at(i)
			continue
		s.prev_pos = s.pos
		s.flash = maxf(0.0, s.flash - dt)
		s.cd = maxf(0.0, s.cd - dt)
		s.anim += dt * 5.0

		if s.downed:
			s.down_t -= dt
			if s.down_t <= 0.0:
				_kill(sim, s)
			continue

		s.pos = sim.world.unstick(s.pos, s.r, sim.structs)

		# A sniper whose tower has been destroyed falls back to guarding.
		if s.job == "sniper" and (s.tower.is_empty() or s.tower.destroyed):
			s.tower = {}
			s.job = "guard"

		var post := _post_for(s, owner, base)
		_tick_one(sim, s, dt, post, base)


## Where this person is meant to be, given their job. With no base yet the crew
## shadows whoever they follow.
func _post_for(s: SurvivorSim, owner: PlayerSim, base: Dictionary) -> Vector2:
	if s.job == "sniper" and not s.tower.is_empty():
		return s.tower.pos
	if base.has_base or owner == null:
		return base.pos
	return owner.pos


func _tick_one(sim: GameSim, s: SurvivorSim, dt: float, post: Vector2, base: Dictionary) -> void:
	# Manning a tower means standing on it. Holding a reference to a structure
	# on the other side of the base is not the same as being up it, and a
	# looser test here is how a sniper ends up firing tower ballistics from
	# halfway across the compound.
	s.posted = s.job == "sniper" and not s.tower.is_empty() \
		and s.pos.distance_squared_to(s.tower.pos) < Config.POST_RADIUS * Config.POST_RADIUS
	var arm := Structures.armament_of(s.tower) if s.posted else {}
	var range_: float = float(arm.range) if not arm.is_empty() else float(S.range)
	var dmg_mul: float = float(arm.dmg) if not arm.is_empty() else 1.0

	# ---------------------------------------------------------- targeting --
	var best: EnemySim = null
	var best_d := range_ * range_
	sim.enemies.hash.query(s.pos.x, s.pos.y, range_, _scratch)
	for e: EnemySim in _scratch:
		if e.dead:
			continue
		var d := s.pos.distance_squared_to(e.pos)
		if d < best_d and sim.world.has_terrain_line_of_sight(s.pos, e.pos):
			best_d = d
			best = e
	s.target = best
	s.shot_range = range_
	s.shot_dmg_mul = dmg_mul

	# ----------------------------------------------------------- job work --
	# The non-combat jobs only get on with it when nothing is shooting at them.
	var under_threat := best != null and best_d < pow(float(S.range) * 0.8, 2.0)
	var job_to := Vector2.INF
	if not under_threat:
		if s.job == "scavenger":
			job_to = _scavenger_step(sim, s, dt, base)
		elif s.job == "builder":
			job_to = _builder_step(sim, s, dt, base)

	# -------------------------------------------------------------- move --
	var want := post
	var climbing := s.job == "sniper" and not s.tower.is_empty() and not s.posted
	if climbing:
		# Get to the tower first. Stopping to shoot on the way is how a sniper
		# never arrives.
		want = s.tower.pos
		_turn(s, dt, best.pos if best != null else want, 8.0 if best != null else 6.0)
	elif best != null and (s.job == "guard" or s.job == "sniper" or under_threat):
		# Hold position and shoot; close only if the target is drifting away,
		# and a posted sniper never leaves their tower at all.
		if s.job != "sniper" and sqrt(best_d) > float(S.range) * 0.8:
			want = best.pos
		else:
			want = s.pos
		_turn(s, dt, best.pos, 8.0)
	elif job_to != Vector2.INF:
		want = job_to
		if s.pos.distance_to(want) > 20.0:
			_turn(s, dt, want, 6.0)
	else:
		var dp := s.pos.distance_to(post)
		want = post if dp > float(S.guard_radius) else s.pos
		if dp > 24.0:
			_turn(s, dt, post, 6.0)

	var to := want - s.pos
	var dist := to.length()
	if dist > 12.0:
		var sp: float = float(S.speed) * (float(S.hungry_speed) if s.hungry else 1.0)
		s.vel += (to / dist * sp - s.vel) * minf(1.0, 10.0 * dt)
	else:
		s.vel *= exp(-9.0 * dt)

	# Spread out, so a crew does not stack into one silhouette.
	for o in list:
		if o == s or o.dead:
			continue
		var away := s.pos - o.pos
		var d2 := away.length_squared()
		var wantd: float = float(S.r) * 2.4
		if d2 < wantd * wantd and d2 > 0.01:
			s.vel += away / sqrt(d2) * 640.0 * dt

	s.pos = sim.world.move_circle(s.pos, s.vel * dt, s.r, sim.structs)

	# -------------------------------------------------------------- fire --
	if best != null and s.cd <= 0.0:
		_shoot(sim, s, arm, best)


func _turn(s: SurvivorSim, dt: float, at: Vector2, rate: float) -> void:
	var want := (at - s.pos).angle()
	s.angle += clampf(Enemies.angle_delta(s.angle, want), -rate * dt, rate * dt)


func _shoot(sim: GameSim, s: SurvivorSim, arm: Dictionary, best: EnemySim) -> void:
	var aim_err: float = (0.04 if not arm.is_empty() else 0.10) - minf(0.03, s.level * 0.004)
	var a := s.angle + sim.rng.frange(-aim_err, aim_err)
	s.cd = float(S.fire_cd) * (float(arm.cd) if not arm.is_empty() else 1.0) \
		* (float(S.hungry_cd) if s.hungry else 1.0)

	# Everyone shoots out of the shared stash, which is what makes arming your
	# people a real decision. A tower spends whatever its armament takes; a
	# survivor on the ground still spends 9mm.
	var cost: Dictionary = arm.ammo if not arm.is_empty() else {"ammoP": 1}
	if not _pay_ammo(sim, cost):
		s.cd = 1.2
		s.out_of_ammo = true
		if sim.time - _ammo_warned > 40.0:
			_ammo_warned = sim.time
			var names: Array[String] = []
			for id in cost:
				names.append(String(Config.RES.get(id, {}).get("name", id)))
			sim.notify("Your people are out of %s — stock the stash" % " and ".join(names), "#d9c46a")
		return
	s.out_of_ammo = false

	Combat.spawn_bullet(sim, s.pos + Vector2.from_angle(a) * 16.0, a,
		float(arm.speed) if not arm.is_empty() else 1150.0,
		s.dmg * s.shot_dmg_mul,
		float(arm.life) if not arm.is_empty() else 0.5,
		float(arm.knock) if not arm.is_empty() else 45.0,
		int(arm.get("pierce", 0)) if not arm.is_empty() else 0,
		null, false, "survivor:%d" % s.id,
		String(arm.color) if not arm.is_empty() else "#cfe8b0")
	sim.emit({"t": "muzzle", "x": s.pos.x + cos(a) * 18.0, "y": s.pos.y + sin(a) * 18.0,
		"a": a, "w": "survivor"})
	# The whole trade: a tower of arrows is a secret, a cannon is an
	# announcement, and the horde comes to the tower rather than to you.
	Sound.make_noise(sim, s.pos.x, s.pos.y,
		float(arm.noise) if not arm.is_empty() else 400.0, sim.host())


func _pay_ammo(sim: GameSim, cost: Dictionary) -> bool:
	if sim.stash == null:
		return false
	for id in cost:
		if sim.stash.count(id) < int(cost[id]):
			return false
	for id in cost:
		sim.stash.take(id, int(cost[id]))
	return true


# ---------------------------------------------------------------- the jobs --
#
# Both return where this person should walk, or `Vector2.INF` for "nowhere in
# particular — go back to your post". Both are written around the same
# constraint: there is no pathfinding, so a target that stops getting closer is
# abandoned rather than leaned on for the rest of the run.


## The give-up timer both jobs share. True when this target should be written
## off. `away` is the current squared distance to it.
func _gave_up(s: SurvivorSim, dt: float, away: float, limit: float) -> bool:
	s.reach_t += dt
	if s.reach_t <= limit:
		return false
	if s.last_reach_d - away > Config.SURVIVOR_PROGRESS:
		# Still closing, just slowly. Reset the clock and keep at it.
		s.last_reach_d = away
		s.reach_t = 0.0
		return false
	return true


## Scavengers walk to a nearby unlooted container, work it, and carry the haul
## back to the stash. Slower and less thorough than you are, which is the
## point: they turn time into materials while you do something else.
func _scavenger_step(sim: GameSim, s: SurvivorSim, dt: float, base: Dictionary) -> Vector2:
	var stash := _nearest_stash(sim, s.pos)

	# Carrying a haul? Take it home.
	if not s.carrying.is_empty() or not s.carry_items.is_empty():
		if stash.is_empty():
			# The stash was destroyed while they walked back. Put the haul on
			# the ground rather than deleting it.
			_drop_cargo(sim, s)
			return Vector2.INF
		var home := s.pos.distance_squared_to(stash.pos)
		if home < Config.SCAVENGE.deliver_range * Config.SCAVENGE.deliver_range:
			_deliver(sim, s, stash)
			s.run_target = {}
			s.home_t = 0.0
			s.last_home_d = INF
			return Vector2.INF
		# The return leg needs the same recovery as the outbound one: a stash
		# behind a shut gate would otherwise hold a loaded carrier against the
		# wall for ever, and every future haul with them.
		s.home_t += dt
		if s.home_t > Config.SCAVENGE.give_up_after:
			if s.last_home_d - home > Config.SURVIVOR_PROGRESS:
				s.last_home_d = home
				s.home_t = 0.0
			else:
				sim.notify("%s could not reach the stash and put the haul down" % s.display_name, "#d9c46a")
				_drop_cargo(sim, s)
				s.home_t = 0.0
				s.last_home_d = INF
				return Vector2.INF
		return stash.pos

	# Nowhere to put anything: do not strip the neighbourhood for nothing.
	if stash.is_empty():
		if sim.time - _stash_warned > S.warn_every:
			_stash_warned = sim.time
			sim.notify("Your scavengers need a Supply Stash to deliver to", "#d9c46a")
		return Vector2.INF

	if s.run_target.is_empty() or not s.run_target.has("table") or s.run_target.looted:
		s.run_target = _pick_container(sim, s, base)
		s.job_t = 0.0
		s.reach_t = 0.0
		s.last_reach_d = INF
		if s.run_target.is_empty():
			return Vector2.INF

	var c := s.run_target
	var away := s.pos.distance_squared_to(Vector2(c.x, c.y))
	if away > Config.SCAVENGE.reach * Config.SCAVENGE.reach:
		if _gave_up(s, dt, away, Config.SCAVENGE.give_up_after):
			s.unreachable[int(c.tx) * 100000 + int(c.ty)] = true
			s.run_target = {}
			s.reach_t = 0.0
			s.last_reach_d = INF
			return Vector2.INF
		return Vector2(c.x, c.y)

	# In reach: work it.
	s.reach_t = 0.0
	s.last_reach_d = INF
	s.job_t += dt
	if s.job_t < Config.SCAVENGE.search_time:
		return s.pos
	s.job_t = 0.0
	c.looted = true
	sim.stats.looted = sim.stats.get("looted", 0) + 1
	var haul := {}
	var gear: Array[Dictionary] = []
	for e in Loot.roll_container(sim, c):
		# Materials go in the pack; weapons, armour and medicine are carried
		# home too and left beside the stash. Nothing a container held is
		# destroyed just because a survivor opened it rather than the player.
		if Config.RES.has(e.id):
			haul[e.id] = int(haul.get(e.id, 0)) + int(e.n)
		else:
			gear.append(e)
	if haul.is_empty() and gear.is_empty():
		haul = Config.SCAVENGE.empty_haul.duplicate()
	s.carrying = haul
	s.carry_items = gear
	s.run_target = {}
	sim.emit({"t": "scavenged", "x": c.x, "y": c.y})
	return s.pos


## Do not send two people to the same shelf, skip anything this person has
## already failed to reach, and — because there is no pathfinding — prefer a
## container with a clear line from the base, since those are the ones they can
## actually walk to. Anything behind a wall is tried only if nothing open is
## left, and the give-up timer drops it quickly if it turns out to be sealed.
func _pick_container(sim: GameSim, s: SurvivorSim, base: Dictionary) -> Dictionary:
	var origin: Vector2 = base.pos if base.has_base else s.pos
	var claimed := {}
	for o in alive():
		if o != s and not o.run_target.is_empty() and o.run_target.has("table"):
			claimed[int(o.run_target.tx) * 100000 + int(o.run_target.ty)] = true

	var best := {}
	var best_d: float = Config.SCAVENGE.radius * Config.SCAVENGE.radius
	var fallback := {}
	var fallback_d: float = best_d
	for c in sim.world.containers:
		if c.looted:
			continue
		var key: int = int(c.tx) * 100000 + int(c.ty)
		if claimed.has(key) or s.unreachable.has(key):
			continue
		var at := Vector2(c.x, c.y)
		var d: float = origin.distance_squared_to(at)
		if d >= fallback_d and d >= best_d:
			continue
		if d < best_d and sim.world.has_terrain_line_of_sight(origin, at):
			best_d = d
			best = c
		elif d < fallback_d:
			fallback_d = d
			fallback = c
	if best.is_empty():
		best = fallback
	# Everything in range has defeated them: forget the grudges and retry.
	if best.is_empty() and not s.unreachable.is_empty():
		s.unreachable.clear()
	return best


## Builders walk to the most damaged structure in range and patch it up, taking
## materials from the stash as they go. During a raid this is the difference
## between a wall that holds and one that does not.
func _builder_step(sim: GameSim, s: SurvivorSim, dt: float, base: Dictionary) -> Vector2:
	var target := s.run_target
	if target.is_empty() or not target.has("def") or target.destroyed or target.hp >= target.max_hp:
		target = {}
		# Searched from their settlement, not from wherever this person is
		# standing: a builder who wandered should still know the wall is broken
		# and walk back to it, rather than losing sight of the job.
		var origin: Vector2 = base.pos if base.has_base else s.pos
		var worst := 1.0
		for st in sim.structs.list:
			if st.destroyed or st.hp >= st.max_hp:
				continue
			if s.unreachable.has(int(st.tx) * 100000 + int(st.ty)):
				continue
			if origin.distance_squared_to(st.pos) > Config.BUILDER.radius * Config.BUILDER.radius:
				continue
			var frac: float = st.hp / st.max_hp
			if frac < worst:
				worst = frac
				target = st
		if target.is_empty() and not s.unreachable.is_empty():
			s.unreachable.clear()
		s.run_target = target
		s.reach_t = 0.0
		s.last_reach_d = INF
	if target.is_empty():
		return Vector2.INF

	var away := s.pos.distance_squared_to(target.pos)
	if away > Config.BUILDER.reach * Config.BUILDER.reach:
		if _gave_up(s, dt, away, Config.BUILDER.give_up_after):
			s.unreachable[int(target.tx) * 100000 + int(target.ty)] = true
			s.run_target = {}
			s.reach_t = 0.0
			s.last_reach_d = INF
			return Vector2.INF
		return target.pos
	s.reach_t = 0.0
	s.last_reach_d = INF

	# In reach: patch it, paying out of the stash as they go. No stash, no
	# materials, no repair — the same rule as the rations and the ammunition.
	# The bill is per 100 points of health, which is well under one unit per
	# tick, so it accrues and is charged whenever it crosses a whole unit.
	var heal: float = Config.BUILDER.repair_per_sec * dt
	if sim.stash != null:
		s.job_t += heal
		while s.job_t >= 100.0:
			s.job_t -= 100.0
			for id in Config.BUILDER.cost_per_100:
				sim.stash.take(id, int(Config.BUILDER.cost_per_100[id]))
	target.hp = minf(target.max_hp, target.hp + heal)
	if target.hp >= target.max_hp:
		sim.emit({"t": "repaired", "x": target.pos.x, "y": target.pos.y})
		s.run_target = {}
	return s.pos


# ------------------------------------------------------------------ cargo --

func _nearest_stash(sim: GameSim, at: Vector2) -> Dictionary:
	return sim.structs.nearest(at, 1000000.0, func(st: Dictionary) -> bool: return st.type == "stash")


func _deliver(sim: GameSim, s: SurvivorSim, stash: Dictionary) -> void:
	if s.carrying.is_empty() and s.carry_items.is_empty():
		return
	# `stash_or_drop` is the same door crafting overflow and raid payouts use,
	# so a full pile puts the rest on the ground rather than eating it.
	for id in s.carrying:
		var n := int(s.carrying[id])
		if n > 0:
			Loot.stash_or_drop(sim, id, n, s.pos)
	for e in s.carry_items:
		Loot.stash_or_drop(sim, String(e.id), int(e.n), s.pos)
	sim.emit({"t": "delivered", "x": s.pos.x, "y": s.pos.y, "name": s.display_name})
	s.carrying = {}
	s.carry_items.clear()


## Everything a survivor is carrying, on the ground where they stand. Used when
## they die, when a stash cannot be reached, and when a job is reassigned
## mid-run: it came out of a real container and must never simply vanish.
func _drop_cargo(sim: GameSim, s: SurvivorSim) -> void:
	for id in s.carrying:
		var n := int(s.carrying[id])
		if n > 0:
			Loot.spawn_entry_pickup(sim, s.pos, Loot.item_entry_id(id), n)
	for e in s.carry_items:
		Loot.spawn_entry_pickup(sim, s.pos, String(e.id), int(e.n))
	s.carrying = {}
	s.carry_items.clear()
