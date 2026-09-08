class_name Enemies
extends RefCounted
## Enemy spawning and AI. Owned by GameSim.
##
## Steering: walk toward the target — along the flow field when hunting a
## player, straight otherwise — and if the direct line is blocked, fan out
## to the nearest clear heading. Anything that walks to a target has
## give-up logic: aggro expires unless real sensing renews it, a noise
## destination is dropped on arrival, and a raider that stops closing on
## the base is relocated (raid.gd).

const S := Config.SPAWN
const PROBE_ANGLES := [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.3, -2.3]

var list: Array[EnemySim] = []
var corpses: Array[Dictionary] = []
var hash := SpatialHash.new()
var rng := Rng.new(0xBADDCAFE)
var seq := 0
var spawn_accum := 0.0

var _scratch: Array = []


# ---------------------------------------------------------------- spawning --

func spawn(type: String, at: Vector2, aggro := false, raid := false, hp_mul := 1.0) -> EnemySim:
	if not Config.ENEMIES.has(type):
		return null
	seq += 1
	var e := EnemySim.new(type, at, hp_mul)
	e.id = seq
	e.angle = rng.frange(0.0, TAU)
	e.aggro = aggro
	e.alert_t = 999.0 if aggro else 0.0
	e.atk_cd = rng.frange(0.0, 0.5)
	e.anim = rng.frange(0.0, TAU)
	e.wander_a = rng.frange(0.0, TAU)
	e.raid = raid
	e.growl_t = rng.frange(2.0, 12.0)
	list.append(e)
	return e


func pick_type(tier: int) -> String:
	var table: Array = S.mix[clampi(tier, 1, 4)]
	var r := rng.next()
	var acc := 0.0
	for row: Array in table:
		acc += row[1]
		if r <= acc:
			return row[0]
	return "walker"


func count_near(at: Vector2, r: float) -> int:
	var r2 := r * r
	var n := 0
	for e in list:
		if not e.dead and e.pos.distance_squared_to(at) < r2:
			n += 1
	return n


func alive_count() -> int:
	var n := 0
	for e in list:
		if not e.dead:
			n += 1
	return n


## Pre-populates the districts around a point so arriving somewhere feels
## alive.
func seed_area(sim: GameSim, at: Vector2, radius: float, count: int, min_r := 420.0) -> void:
	for i in range(count):
		var a := rng.frange(0.0, TAU)
		var r := rng.frange(min_r, radius)
		var p := at + Vector2(cos(a), sin(a)) * r
		if sim.world.is_blocked_px(p.x, p.y):
			continue
		spawn(pick_type(sim.world.danger_at_px(p.x, p.y)), p)


## Keeps a standing population around every living player. Each is the
## centre of their own ring, so someone on ground they cleared gets their
## lull whatever a teammate is stirring up across town.
func tick_spawning(sim: GameSim, dt: float) -> void:
	var players := sim.living_players()
	if players.is_empty():
		return
	spawn_accum += dt
	if spawn_accum < S.interval:
		return
	spawn_accum = 0.0

	# Cull the dead, and anything everyone has walked far away from.
	var cull2: float = S.cull * S.cull
	for i in range(list.size() - 1, -1, -1):
		var e := list[i]
		if e.dead:
			list.remove_at(i)
			continue
		if e.raid:
			continue
		var near_someone := false
		for p in players:
			if e.pos.distance_squared_to(p.pos) <= cull2:
				near_someone = true
				break
		if not near_someone:
			list.remove_at(i)

	if sim.raid != null:
		return                          # raids control their own spawning

	var night := sim.night_factors()
	for p in players:
		if list.size() >= S.max_enemies:
			return
		var tier := sim.world.danger_at_px(p.pos.x, p.pos.y)
		var near := count_near(p.pos, S.count_radius)
		var want: float = S.density[clampi(tier, 1, 4)] * night.density * sim.quiet.density_mul(p.pos.x, p.pos.y)
		if near >= want:
			continue
		# Ground you have thoroughly cleared buys an actual lull, not just a
		# thinner stream. Tested at the player, not the spawn ring: the ring
		# sits ~1000px out, beyond the patch a burst of kills quietens.
		if sim.quiet.suppressed(p.pos.x, p.pos.y):
			continue
		var ring: float = maxf(S.ring_min, sim.view_radius + 180.0)
		var spot := sim.world.find_open_spot(rng, p.pos, ring, ring + S.ring_width)
		if spot == Vector2.INF:
			continue
		if sim.quiet.suppressed(spot.x, spot.y):
			continue
		var spot_tier := sim.world.danger_at_px(spot.x, spot.y)
		spawn(pick_type(maxi(tier, spot_tier)), spot)


func rebuild_spatial() -> void:
	hash.clear()
	for e in list:
		if not e.dead:
			hash.insert(e)


# ---------------------------------------------------------------------- AI --

## Is the straight line along `angle` clear for `len` px, at the body's width?
static func clear_ahead(world: World, pos: Vector2, angle: float, len: float, r: float) -> bool:
	var steps := maxi(2, ceili(len / 14.0))
	var dir := Vector2.from_angle(angle)
	var side := dir.orthogonal() * r * 0.7
	for i in range(1, steps + 1):
		var p := pos + dir * ((float(i) / steps) * len)
		if world.is_blocked_px(p.x + side.x, p.y + side.y):
			return false
		if world.is_blocked_px(p.x - side.x, p.y - side.y):
			return false
	return true


static func steer(world: World, e: EnemySim, want: float) -> float:
	var probe := 34.0 + e.r
	for off: float in PROBE_ANGLES:
		var a := want + off
		if clear_ahead(world, e.pos, a, probe, e.r):
			return a
	return want


static func angle_delta(a: float, b: float) -> float:
	var d := fmod(b - a, TAU)
	if d > PI:
		d -= TAU
	if d <= -PI:
		d += TAU
	return d


func tick_ai(sim: GameSim, dt: float) -> void:
	var world := sim.world
	var night := sim.night_factors()
	var quarter_speed_dt := 0.25 * dt

	for e in list:
		if e.dead:
			continue

		# The person this one would go for: the nearest who is up and about.
		var p := sim.nearest_player(e.pos)

		e.flash = maxf(0.0, e.flash - dt)
		e.atk_cd = maxf(0.0, e.atk_cd - dt)
		e.slow_t = maxf(0.0, e.slow_t - dt)
		e.alert_t = maxf(0.0, e.alert_t - dt)
		e.anim += dt * (2.0 + e.speed * 0.03)
		e.growl_t -= dt
		if e.growl_t <= 0.0:
			e.growl_t = rng.frange(4.0, 16.0)
			if p != null and e.pos.distance_squared_to(p.pos) < 620.0 * 620.0:
				sim.emit({"t": "growl", "x": e.pos.x, "y": e.pos.y})

		# ---------------------------------------------------------- targeting --
		var d_player2 := INF if p == null else e.pos.distance_squared_to(p.pos)
		# Crouching halves what they notice; carrying a light (Phase 3) does
		# the opposite.
		var sense_r: float = e.sense * (S.sneak_sense_mul if p != null and p.sneaking else 1.0) * night.sense
		if p != null and p.lit:
			sense_r += S.light_sense_bonus

		# Only a player this enemy can sense RIGHT NOW refreshes the chase.
		# Reading `aggro or senses` here let an aggro'd enemy renew its own
		# timer forever, and the expiry below never fired.
		var senses := p != null and d_player2 < sense_r * sense_r
		if senses and (d_player2 < 120.0 * 120.0 or world.has_line_of_sight(e.pos, p.pos)):
			e.aggro = true
			e.alert_t = maxf(e.alert_t, 4.0)
		if p == null:
			e.aggro = false
		elif e.aggro and not senses and e.alert_t <= 0.0 and not e.raid:
			e.aggro = false          # losing you makes them investigate, not peaceful

		var tgt := Vector2.ZERO
		var hunting := false         # walking at a player: use the flow field
		if e.raid and sim.raid != null:
			# Raiders push for the base — the nearest structure, in Phase 3 —
			# and happily eat the player en route.
			if p != null:
				tgt = p.pos
				hunting = true
			else:
				tgt = sim.raid.centre
		elif e.aggro and p != null:
			tgt = p.pos
			hunting = true
		elif e.alert_t > 0.0 and e.has_noise:
			tgt = e.noise_at
			# Arriving is the end of it: standing on the spot forever is how a
			# horde ends up milling around a wall.
			if e.pos.distance_squared_to(tgt) < 48.0 * 48.0:
				e.alert_t = 0.0
				e.has_noise = false
		else:
			e.wander_t -= dt
			if e.wander_t <= 0.0:
				e.wander_t = rng.frange(1.6, 4.2)
				e.wander_a += rng.frange(-1.6, 1.6)
			tgt = e.pos + Vector2.from_angle(e.wander_a) * 80.0

		var want_angle := (tgt - e.pos).angle()

		# ---------------------------------------------------------- attacking --
		if e.windup > 0.0:
			e.windup -= dt
			if e.windup <= 0.0:
				# Land the blow if the victim is still there.
				if p != null and d_player2 < (e.atk_range + p.r + 6.0) * (e.atk_range + p.r + 6.0):
					Damage.damage_player(sim, p, e.dmg, e.pos, e.def.name)
			e.last_pos = e.pos
			continue                                 # committed to the swing

		var player_in_reach := p != null and d_player2 < (e.atk_range + p.r) * (e.atk_range + p.r)
		if player_in_reach and e.atk_cd <= 0.0:
			e.atk_cd = e.atk_cd_base
			e.windup = 0.24
			e.angle = (p.pos - e.pos).angle()
			continue

		# ----------------------------------------------------------- movement --
		var head := want_angle
		if hunting and p != null:
			# Close, with a body-width run straight at them: go direct.
			# Otherwise the field knows the way round the building. A sight
			# line is not enough — through a doorway it is exactly what makes
			# a walker flip between the two and circle the house twice.
			var direct := d_player2 < 200.0 * 200.0 and clear_ahead(world, e.pos, want_angle, sqrt(d_player2), e.r)
			if not direct:
				var nf := sim.nav_for(p)
				if nf != null:
					var d := nf.step_dir(e.pos)
					if d != Vector2.ZERO:
						head = d.angle()
		var move_angle := steer(world, e, head)
		e.angle += clampf(angle_delta(e.angle, move_angle), -9.0 * dt, 9.0 * dt)

		var speed: float = e.speed * night.speed
		if e.slow_t > 0.0:
			speed *= 0.45
		if not e.aggro and not e.raid:
			speed *= 0.45
		# Runners lunge in bursts rather than sprinting flat out.
		if e.type == "runner" and e.aggro:
			speed *= 1.0 + sin(e.anim * 1.7) * 0.18

		e.vel += Vector2.from_angle(move_angle) * speed * 8.0 * dt

		# Separation keeps a horde a crowd rather than one stacked blob.
		hash.query(e.pos.x, e.pos.y, e.r * 3.0, _scratch)
		for o: EnemySim in _scratch:
			if o == e or o.dead:
				continue
			var dv := e.pos - o.pos
			var d2 := dv.length_squared()
			var want := e.r + o.r
			if d2 < want * want and d2 > 0.01:
				var d := sqrt(d2)
				var push := (want - d) / want
				e.vel += (dv / d) * push * 220.0 * dt * 4.0

		e.vel *= exp(-7.5 * dt)
		var vlen := e.vel.length()
		var cap := speed * 1.55
		if vlen > cap:
			e.vel *= cap / vlen

		e.pos = world.move_circle(e.pos, e.vel * dt, e.r)

		# -------------------------------------------------------- stuck rescue --
		# Moving at under a quarter of its own pace while it means to be
		# somewhere counts as stuck. (The prototype compared against a fixed
		# 1.1px per step, which a walking brute never exceeded.)
		var moved := e.pos.distance_to(e.last_pos)
		if (e.aggro or e.raid) and moved < speed * quarter_speed_dt:
			e.stuck_t += dt
			if e.stuck_t > 0.7:
				# Phase 3: punch whatever player-built thing is adjacent.
				# Otherwise sidestep.
				e.pos = world.unstick(e.pos, e.r)
				e.wander_a = want_angle + (1.4 if rng.chance(0.5) else -1.4)
				e.vel += Vector2.from_angle(e.wander_a) * 160.0
				e.stuck_t = 0.0
		else:
			e.stuck_t = 0.0
		e.last_pos = e.pos
