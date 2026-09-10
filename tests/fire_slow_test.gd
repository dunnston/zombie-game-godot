extends "res://tests/test_case.gd"
## The fire tests that cost real simulation time. Spread is a 16% roll every
## 0.6s, so proving it happens means running the same treeline on several RNG
## streams — fifty-odd seconds of simulated burning, which is more than the
## ten-second loop should carry. `tools\test.cmd --all` runs it.

var sim: GameSim
var p: PlayerSim
var plot: Vector2i

## Its own world, for the reason `fire_test.gd` has one: these tests plant
## scenery and then burn it away, and the shared world is shared.
static var _fire_world: World


static func fire_world() -> World:
	if _fire_world == null:
		_fire_world = World.new()
	return _fire_world


func before_each() -> void:
	sim = GameSim.new()
	sim.start(fire_world(), 1)
	sim.enemies.list.clear()
	sim.events.clear()
	p = sim.players[0]
	plot = clear_plot(10)
	p.pos = tile_centre(plot)


func _plant(kind: String, tx: int, ty: int) -> Dictionary:
	var prop := {"kind": kind, "tx": tx, "ty": ty,
		"x": tx * Config.TILE + 16.0, "y": ty * Config.TILE + 16.0,
		"hp": 40.0, "solid": false}
	sim.world.props.append(prop)
	sim.world.prop_grid[ty * Config.WORLD_TILES + tx] = prop
	return prop


func _tick_fire(seconds: float) -> void:
	var dt := 1.0 / 60.0
	for i in range(int(round(seconds / dt))):
		sim.enemies.rebuild_spatial()
		sim.fire.tick(sim, dt)


## Enough of everything to build whatever a test asks for.
func _stock(n := 400) -> void:
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0
	for id in ["wood", "stone", "sticks", "scrap", "cloth", "elec", "parts", "mil", "fuel"]:
		p.bag.add(id, n)


## Fire spreads to scenery, and scenery on fire relights whoever is standing
## in it. A test about the *timer* has to be run somewhere with nothing to
## catch, or it is really a test about re-ignition.
func _clear_flammables_around(at: Vector2, radius: float) -> void:
	var span := ceili(radius / Config.TILE)
	var tx := floori(at.x / Config.TILE)
	var ty := floori(at.y / Config.TILE)
	for j in range(-span, span + 1):
		for i in range(-span, span + 1):
			var prop := sim.world.prop_at_tile(tx + i, ty + j)
			if Fire.is_flammable(prop):
				sim.world.remove_prop(prop)


func test_lighting_an_enemy_sets_a_timer_that_runs_out() -> void:
	var at := tile_centre(plot + Vector2i(3, 0))
	_clear_flammables_around(at, 200.0)
	var e := sim.enemies.spawn("brute", at)
	ok(sim.fire.ignite(e))
	near(e.burn_t, Config.FIRE.burn_time, 1e-9)
	var hp_before := e.hp
	_tick_fire(1.0)
	ok(e.hp < hp_before, "it is burning: %.0f -> %.0f" % [hp_before, e.hp])
	_tick_fire(Config.FIRE.burn_time + 1.0)
	ok(e.burn_t <= 0.0, "and with nothing to relight it, the fire goes out")
	ok(not e.dead, "a brute survives one burn: 9 dps for 6.5s against 300 hp")


func test_a_burn_does_not_keep_re_alerting_what_it_is_burning() -> void:
	# A burn ticks several times a second. If each tick re-alerted, a burning
	# walker would stand still being startled instead of walking at you.
	var e := sim.enemies.spawn("walker", tile_centre(plot + Vector2i(6, 0)))
	e.aggro = false
	e.alert_t = 0.0
	sim.fire.ignite(e)
	# Step fire alone, so nothing else can alert it.
	_tick_fire(0.5)
	ok(not e.aggro, "the fire did not make it notice anything")


func test_a_burning_prop_burns_away_and_stays_gone() -> void:
	var prop := _plant("tree", plot.x + 2, plot.y)
	ok(sim.fire.ignite_prop(sim, prop))
	eq(sim.fire.list.size(), 1)
	ok(not sim.world.prop_at_tile(plot.x + 2, plot.y).is_empty(), "still standing while it burns")

	_tick_fire(Config.FIRE.prop_life * 1.3 + 0.5)
	eq(sim.fire.list.size(), 0, "burnt out")
	ok(sim.world.prop_at_tile(plot.x + 2, plot.y).is_empty(), "and gone")
	# It left by the same door chopping uses, so a save knows about it.
	var key := (plot.y * Config.WORLD_TILES + plot.x + 2)
	ok(sim.world.chopped.has(key), "a burnt tree is in the run's chopped keys")


func test_the_same_prop_cannot_be_lit_twice() -> void:
	var prop := _plant("pine", plot.x + 2, plot.y)
	ok(sim.fire.ignite_prop(sim, prop))
	ok(not sim.fire.ignite_prop(sim, prop), "already alight")
	eq(sim.fire.list.size(), 1)


func test_the_ceiling_refuses_rather_than_slowing_down() -> void:
	# The forest is thousands of pines; a fire that could take all of them at
	# once would take the frame rate with it.
	var lit := 0
	for i in range(int(Config.FIRE.max_fires) + 40):
		var prop := _plant("pine", plot.x - 40 + i, plot.y + 30)
		if sim.fire.ignite_prop(sim, prop):
			lit += 1
	eq(lit, int(Config.FIRE.max_fires), "lit up to the cap")
	eq(sim.fire.list.size(), int(Config.FIRE.max_fires), "and no further")


# ------------------------------------------------------------------ spread --

func test_a_burning_enemy_can_light_the_one_beside_it() -> void:
	var a := sim.enemies.spawn("walker", tile_centre(plot + Vector2i(3, 0)))
	var others: Array[EnemySim] = []
	for i in range(6):
		var e := sim.enemies.spawn("walker", a.pos + Vector2(6.0 * i - 15.0, 8.0))
		others.append(e)
	for e in others:
		e.hp = 9999.0
	a.hp = 9999.0
	sim.fire.ignite(a)
	_tick_fire(Config.FIRE.burn_time)
	var caught := 0
	for e in others:
		if e.burn_t > 0.0:
			caught += 1
	gt(caught, 0, "%d of six caught" % caught)


func test_standing_in_a_fire_hurts_the_player_too() -> void:
	var prop := _plant("bush", plot.x + 1, plot.y)
	p.pos = Vector2(prop.x, prop.y)
	sim.fire.ignite_prop(sim, prop)
	var before := p.hp
	_tick_fire(1.5)
	ok(p.hp < before, "fire does not care whose it is: %.0f -> %.0f" % [before, p.hp])


func test_standing_clear_of_it_does_not() -> void:
	var prop := _plant("bush", plot.x + 1, plot.y)
	p.pos = Vector2(prop.x, prop.y) + Vector2(Config.FIRE.prop_hurt_radius * 3.0, 0)
	sim.fire.ignite_prop(sim, prop)
	var before := p.hp
	_tick_fire(1.5)
	eq(p.hp, before, "out of the fire is out of the fire")


# ------------------------------------------------ the thing it must not do --

func test_fire_never_touches_anything_the_player_built() -> void:
	# This is a design decision, not an oversight: losing your base to your
	# own tower would be the kind of surprise that ends a run. If a path from
	# fire to `structs` is ever added, this is what should stop it.
	_stock()
	var built: Array[Dictionary] = []
	for i in range(-2, 3):
		for j in range(-2, 3):
			var s := sim.structs.place(sim, "woodWall", plot.x + i, plot.y + j + 6, p)
			if not s.is_empty():
				built.append(s)
	gt(built.size(), 8, "a compound to burn down")
	var hp_before := sim.structs.hp_total()
	var count_before := sim.structs.count()

	# Ring it with burning scenery and let it rage.
	for i in range(-3, 4):
		var prop := _plant("pine", plot.x + i, plot.y + 3)
		sim.fire.ignite_prop(sim, prop)
	for i in range(-3, 4):
		var prop := _plant("pine", plot.x + i, plot.y + 9)
		sim.fire.ignite_prop(sim, prop)
	gt(sim.fire.list.size(), 6, "plenty alight")
	# Six spread cycles at 0.6s each, and ten times the hurt cadence. If a
	# path from fire to `structs` existed, it would have fired many times over.
	_tick_fire(4.0)

	near(sim.structs.hp_total(), hp_before, 0.001, "not one point of structure damage")
	eq(sim.structs.count(), count_before, "and nothing lost")


func test_a_wall_does_not_appear_in_the_fire_list() -> void:
	_stock()
	clear_ground(sim, plot.x + 2, plot.y)
	var wall := sim.structs.place(sim, "woodWall", plot.x + 2, plot.y, p)
	ok(not wall.is_empty())
	# The structure dictionary has no `kind`, so it can never read as flammable.
	ok(not Fire.is_flammable(wall), "a wall is not scenery")


# ------------------------------------------------------------------ notices --

func test_a_fire_getting_away_from_you_says_so_once() -> void:
	for i in range(int(Config.FIRE.wildfire_warn_at) + 5):
		var prop := _plant("pine", plot.x - 30 + i, plot.y + 20)
		sim.fire.ignite_prop(sim, prop)
	sim.events.clear()
	sim.fire.tick(sim, 1.0 / 60.0)
	var said := 0
	for e in events_of(sim, "notify"):
		if e.text.contains("spreading"):
			said += 1
	eq(said, 1, "warned once")
	sim.events.clear()
	for i in range(60):
		sim.fire.tick(sim, 1.0 / 60.0)
	var again := 0
	for e in events_of(sim, "notify"):
		if e.text.contains("spreading"):
			again += 1
	eq(again, 0, "and not again while it is still burning")


func test_a_new_run_has_nothing_alight() -> void:
	var prop := _plant("pine", plot.x + 2, plot.y)
	sim.fire.ignite_prop(sim, prop)
	gt(sim.fire.list.size(), 0)
	sim.start(fire_world(), 1)
	eq(sim.fire.list.size(), 0, "start() clears the fires, like the raid and the bullets")
	ok(not sim.fire.warned)

func test_fire_spreads_along_a_treeline() -> void:
	# Spread is a 16% roll every 0.6s, so any single run is a coin toss and a
	# fixed seed makes it a coin toss that always lands the same way. Run the
	# same treeline on several streams and assert on the behaviour instead.
	var spread_in := 0
	for trial in range(6):
		sim = GameSim.new()
		sim.start(fire_world(), 100 + trial)
		sim.enemies.list.clear()
		# A fresh row per trial: a burnt prop is gone from the world for good.
		var row := plot.y + 20 + trial * 2
		var line: Array[Dictionary] = []
		for i in range(8):
			line.append(_plant("pine", plot.x + i, row))
		ok(sim.fire.ignite_prop(sim, line[0]), "trial %d lit" % trial)
		_tick_fire(9.0)
		var caught := 0
		for prop in line:
			if prop.get("burning", false) or prop.get("burned_away", false):
				caught += 1
		if caught > 1:
			spread_in += 1
	gt(spread_in, 3, "fire took more than one tree in %d of six treelines" % spread_in)

# ------------------------------------------------------ what a burn costs --

func test_a_burn_does_not_spray_blood_sixty_times_a_second() -> void:
	# `Damage.damage_enemy` emits a `hit` for the effects view to answer with
	# seven blood particles and a damage number. A burn ticks every frame, so
	# without `no_fx` one enemy surviving 6.5s of fire would leave three
	# thousand particles behind it and a burning horde would drop the frame
	# rate through the floor.
	var e := sim.enemies.spawn("brute", tile_centre(plot + Vector2i(3, 0)))
	e.hp = 99999.0
	sim.fire.ignite(e)
	sim.events.clear()
	_tick_fire(2.0)
	eq(events_of(sim, "hit").size(), 0, "a burn is not a hit, cosmetically")
	ok(e.hp < 99999.0, "but it is still doing damage")


func test_standing_in_a_fire_does_not_make_you_invulnerable() -> void:
	# `damage_player` grants invuln_after_hit on every accepted hit, which is
	# what stops a zombie hitting you twice in a frame. Routing fire through
	# it would make a bonfire the safest place in the game.
	var prop := _plant("bush", plot.x + 1, plot.y)
	p.pos = Vector2(prop.x, prop.y)
	sim.fire.ignite_prop(sim, prop)
	_tick_fire(1.0)
	near(p.invuln, 0.0, 1e-9, "fire grants no i-frames")

	# And a zombie can still reach you while you stand in it.
	p.invuln = 0.0
	var before := p.hp
	var dealt := Damage.damage_player(sim, p, 20.0, p.pos + Vector2(20, 0))
	gt(dealt, 0.0, "the bite landed")
	ok(p.hp < before)


func test_fire_deals_the_dps_it_advertises() -> void:
	# Through `damage_player` every tick would be floored at 1 damage, turning
	# 16 dps into 60 — and gated by i-frames, turning it into about 3.
	var prop := _plant("bush", plot.x + 3, plot.y)
	p.pos = Vector2(prop.x, prop.y)
	p.hp = p.max_hp
	sim.fire.ignite_prop(sim, prop)
	var before := p.hp
	_tick_fire(1.0)
	var lost := before - p.hp
	near(lost, Config.FIRE.prop_dps, 1.0, "one second in a fire costs about its dps")


func test_hay_and_reeds_are_declared_flammable_but_cannot_be_reached() -> void:
	# Honest documentation of a known gap rather than a claim the game does
	# not deliver. Fire finds scenery by tile, and the generator appends hay
	# and reeds to `props` without a `prop_grid` entry — so they are in
	# `Config.FLAMMABLE` and can never catch. The prototype has exactly the
	# same gap. If this test starts failing, someone has indexed them, and
	# `Config.FLAMMABLE`'s comment plus this test should go.
	for kind in ["hay", "reed"]:
		var total := 0
		var reachable := 0
		for prop in sim.world.props:
			if String(prop.get("kind", "")) != kind:
				continue
			total += 1
			if prop.has("tx") and sim.world.prop_at_tile(int(prop.tx), int(prop.ty)) == prop:
				reachable += 1
		gt(total, 0, "the generator makes %s at all" % kind)
		eq(reachable, 0, "%s is flammable on paper and unreachable in fact" % kind)
