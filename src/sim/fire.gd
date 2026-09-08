class_name Fire
extends RefCounted
## Fire: what a fire arrow leaves behind.
##
## A crowd weapon with a real cost. It clears a horde, it can take the
## treeline you were going to chop, and it burns whoever is standing in it —
## you included.
##
## **Nothing here can reach a player structure.** There is no path from any
## function below to `sim.structs`, and that is a decision rather than an
## oversight: losing your base to your own tower would be the kind of surprise
## that ends a run. `fire_test.gd` asserts it stays that way.
##
## A burnt prop leaves through `World.remove_prop`, the same door chopping
## uses, so it lands in the run's `chopped` keys and a burnt treeline is still
## burnt after a save and load.

const F := Config.FIRE

## Burning scenery: {prop, pos, t, life, spread_t}.
var list: Array[Dictionary] = []
var warned := false

## Whether any enemy might be alight. Burning is rare and the enemy list is
## long, so without this every tick of every run pays for a full scan to
## discover that nothing is on fire. Set when something is lit and cleared by
## the first scan that finds nothing still burning.
var _any_burning := false


## A new or loaded world has nothing alight in it.
func reset() -> void:
	list.clear()
	warned = false
	_any_burning = false


# --------------------------------------------------------------- ignition --

## Sets an enemy alight, or refreshes one that is already burning.
func ignite(e: EnemySim) -> bool:
	if e == null or e.dead:
		return false
	var fresh := e.burn_t <= 0.0
	e.burn_t = F.burn_time
	if fresh:
		e.burn_spread_t = F.spread_every
	_any_burning = true
	return true


## Sets a piece of scenery alight. Refuses anything that does not burn and
## anything past the cap — a refused ignition is how this stays affordable.
func ignite_prop(sim: GameSim, prop: Dictionary) -> bool:
	if not is_flammable(prop) or prop.get("burning", false):
		return false
	if list.size() >= int(F.max_fires):
		return false
	prop.burning = true
	list.append({
		"prop": prop,
		"pos": Vector2(prop.x, prop.y),
		"t": 0.0,
		"life": F.prop_life * sim.rng.frange(0.8, 1.2),
		"spread_t": F.spread_every,
	})
	sim.emit({"t": "ignite", "x": prop.x, "y": prop.y})
	return true


static func is_flammable(prop: Dictionary) -> bool:
	return not prop.is_empty() and String(prop.get("kind", "")) in Config.FLAMMABLE


# ------------------------------------------------------------------- step --

func tick(sim: GameSim, dt: float) -> void:
	_burn_enemies(sim, dt)
	_burn_props(sim, dt)
	_check_wildfire(sim)


func _burn_enemies(sim: GameSim, dt: float) -> void:
	if not _any_burning:
		return
	var still := false
	for e in sim.enemies.list:
		if e.dead or e.burn_t <= 0.0:
			continue
		still = true
		e.burn_t -= dt
		# `no_alert` so a burn does not re-startle the enemy sixty times a
		# second, and `no_fx` so it does not emit a hit event that often — the
		# effects view answers each one with seven blood particles and a
		# damage number. A burning enemy is drawn from `burn_t` by EnemyView.
		Damage.damage_enemy(sim, e, F.burn_dps * dt, e.pos, 0.0, false, "fire", true, true)
		if e.dead:
			continue
		e.burn_spread_t -= dt
		if e.burn_spread_t > 0.0:
			continue
		e.burn_spread_t = F.spread_every
		_spread_from(sim, e.pos, F.to_enemy_radius, F.to_enemy_chance,
			F.to_prop_radius, F.to_prop_chance, e)
	# Nothing left alight, so stop paying for the scan until something is lit
	# again. `_spread_from` above may have set it back to true.
	if not still:
		_any_burning = false


func _burn_props(sim: GameSim, dt: float) -> void:
	for i in range(list.size() - 1, -1, -1):
		var f: Dictionary = list[i]
		f.t += dt
		_hurt_anything_standing_in(sim, f, dt)

		f.spread_t -= dt
		if f.spread_t <= 0.0:
			f.spread_t = F.spread_every
			_spread_from(sim, f.pos, 0.0, 0.0, F.prop_spread_radius, F.prop_spread_chance, null)

		if f.t < f.life:
			continue
		# Burnt out. The prop leaves by the same door chopping uses, so the
		# run's `chopped` keys stay consistent and a burnt treeline is still
		# burnt when the game is loaded again.
		list.remove_at(i)
		var prop: Dictionary = f.prop
		if not prop.is_empty() and not prop.get("burned_away", false):
			prop.burned_away = true
			prop.burning = false
			sim.world.remove_prop(prop)
			sim.world_version += 1
		sim.emit({"t": "burnt_out", "x": f.pos.x, "y": f.pos.y})


## Fire burns whoever is standing in it. That includes you.
func _hurt_anything_standing_in(sim: GameSim, f: Dictionary, dt: float) -> void:
	var r: float = F.prop_hurt_radius
	var r2 := r * r
	var dmg: float = F.prop_dps * dt
	sim.enemies.hash.query(f.pos.x, f.pos.y, r, sim.enemies._scratch)
	for e: EnemySim in sim.enemies._scratch:
		if e.dead or e.burn_t > 0.0:
			continue
		if e.pos.distance_squared_to(f.pos) < r2:
			ignite(e)
	for q in sim.players:
		if q.dead:
			continue
		if q.pos.distance_squared_to(f.pos) < r2:
			Damage.burn_player(sim, q, dmg, f.pos)


## One spread roll from a point.
##
## Note what is missing: nothing here touches `sim.structs`. Player-built
## walls, chests, bunks and workbenches cannot catch, by choice.
func _spread_from(sim: GameSim, at: Vector2, e_radius: float, e_chance: float,
		p_radius: float, p_chance: float, self_e: EnemySim) -> void:
	if e_radius > 0.0:
		sim.enemies.hash.query(at.x, at.y, e_radius, sim.enemies._scratch)
		for o: EnemySim in sim.enemies._scratch:
			if o == self_e or o.dead or o.burn_t > 0.0:
				continue
			if o.pos.distance_squared_to(at) > e_radius * e_radius:
				continue
			if sim.rng.chance(e_chance):
				ignite(o)
	if p_radius <= 0.0 or list.size() >= int(F.max_fires):
		return
	var span := ceili(p_radius / Config.TILE)
	var tx := floori(at.x / Config.TILE)
	var ty := floori(at.y / Config.TILE)
	for j in range(-span, span + 1):
		for i in range(-span, span + 1):
			var prop := sim.world.prop_at_tile(tx + i, ty + j)
			if not is_flammable(prop) or prop.get("burning", false):
				continue
			if Vector2(prop.x, prop.y).distance_squared_to(at) > p_radius * p_radius:
				continue
			if sim.rng.chance(p_chance):
				ignite_prop(sim, prop)


## Says so, once, when a fire you started is getting away from you.
func _check_wildfire(sim: GameSim) -> void:
	if list.size() < int(F.wildfire_warn_at):
		if list.is_empty():
			warned = false
		return
	if warned:
		return
	warned = true
	sim.notify("That fire is spreading", "#ff9a3a", true)
