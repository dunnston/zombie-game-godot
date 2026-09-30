extends "res://tests/test_case.gd"
## The Butcher and his barn (progression step E): the first dungeon, the
## first boss, and the key to Workbench II.

var sim: GameSim
var p: PlayerSim
var inst: Instance
var butcher: EnemySim
var brain: Boss
var B: Dictionary
const DT := 1.0 / 60.0


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	var f := Instance.door_for(sim, "barn")
	ok(not f.is_empty(), "the barn has a door on the farm")
	p.pos = f.stand
	ok(Instance.enter(sim, p, "barn"), "the door opens")
	inst = sim.instance
	butcher = inst.boss
	brain = butcher.brain
	B = Config.BOSSES[butcher.type]
	for i in range(sim.enemies.list.size() - 1, -1, -1):
		if sim.enemies.list[i] != butcher:
			sim.enemies.list.remove_at(i)
	_put(Vector2(0, 220))


func _put(off: Vector2) -> void:
	p.pos = butcher.pos + off
	p.prev_pos = p.pos
	p.vel = Vector2.ZERO
	p.hp = p.max_hp
	p.invuln = 0.0


func _until(pred: Callable, cap := 5.0) -> bool:
	for i in range(int(cap / DT)):
		if pred.call():
			return true
		sim.tick(DT)
	return pred.call()


# ------------------------------------------------------------------ the barn --

func test_the_barn_stands_on_the_farm_and_the_town_still_loads_old_saves() -> void:
	var w := world()
	var d: Dictionary = Config.INSTANCES.barn
	var shell: Rect2i = d.shell
	eq(w.tile(shell.position.x, shell.position.y), Config.T.WALL, "a wall at the corner")
	eq(w.tile(shell.position.x + 5, shell.position.y + 5), Config.T.ROOF, "roof inside")
	eq(String(w.location_at_px((shell.position.x + 30) * 32, (shell.position.y + 5) * 32).get("id", "")), "farms", "on the farm")
	# No spawn tile under it: a respawn must not land on a roof.
	for t in w.spawn_tiles:
		ok(not shell.merge(d.lot).has_point(t), "spawn tile %s is under the barn" % t)
	# The town as it was after the School alone is still this town.
	eq(w.past_fingerprints.size(), 2, "one fingerprint per stamp, in order")
	ok(w.accepts_fingerprint(w.past_fingerprints[0]), "a School-era save loads")
	ok(w.accepts_fingerprint(w.base_fingerprint), "and one from before the School")
	ok(w.accepts_fingerprint(w.fingerprint()))
	ok(not w.accepts_fingerprint(12345))


func test_the_inside_is_a_yard_a_floor_three_stalls_and_the_killing_floor() -> void:
	eq(inst.kind, "barn")
	var w := sim.world
	ok(w.arena.size.x > 20 and w.arena.size.y > 15, "a room to fight in")
	eq(w.add_spots.size(), 4, "four pens")
	ok(w.entry_spot.distance_to(Instance.door_for(sim, "barn").get("stand", w.entry_spot)) >= 0.0)
	# No key anywhere: the way to the back is open.
	var chained := 0
	for f in w.features:
		if String(f.kind) == "chained":
			chained += 1
	eq(chained, 0, "nothing to find first")
	ok(w.containers.size() >= 4, "some farm stock: %d" % w.containers.size())
	ok(w.enemy_spots.size() >= 6, "and a crowd in the stalls and on the floor: %d" % w.enemy_spots.size())
	eq(String(butcher.type), "butcher")
	near(butcher.max_hp, 700.0, 1e-6, "half the Coach")


# ----------------------------------------------------------------- the fight --

func test_the_hook_drags_you_in_from_its_lane_and_a_step_aside_is_enough() -> void:
	var m: Dictionary = B.moves.hook
	_put(Vector2(0, 300))
	brain.force(sim, butcher, p, "hook")
	eq(brain.state, "tell")
	eq(events_of(sim, "boss_tell").back().move, "hook")
	run(sim, float(m.tell) + 0.05)
	var d := p.pos.distance_to(butcher.pos)
	ok(d < 120.0, "dragged to %.0f px in front of him" % d)
	ok(p.hp < p.max_hp, "and cut on the way")
	ok(events_of(sim, "boss_hook").back().caught)
	# Out of the lane before it lands: nothing.
	ok(_until(func() -> bool: return brain.state == "fight", 3.0))
	_put(Vector2(0, 300))
	brain.force(sim, butcher, p, "hook")
	p.pos += Vector2(float(m.width) + p.r + 30.0, 0.0)
	p.prev_pos = p.pos
	run(sim, float(m.tell) + 0.05)
	ok(p.pos.distance_to(butcher.pos) > 250.0, "still where you stepped to")
	near(p.hp, p.max_hp, 1e-6, "and untouched")
	ok(not events_of(sim, "boss_hook").back().caught)


func test_below_half_the_pens_open() -> void:
	eq(Boss.phase_for(B, 1.0), 0)
	eq(Boss.phase_for(B, 0.49), 1)
	butcher.hp = butcher.max_hp * 0.45
	run(sim, float(B.transition) + 0.2)
	ok(_until(func() -> bool: return sim.enemies.list.size() > 1, 4.0), "adds came out of the pens")
	ok(sim.enemies.list.size() <= 1 + int(B.moves.whistle.cap))


# ------------------------------------------------------------------ the prize --

func test_the_first_kill_gives_the_saw_and_the_cleaver_and_the_second_does_not() -> void:
	Damage.kill_enemy(sim, butcher, p)
	var ids := {}
	for pile in sim.pickups:
		ids[String(pile.get("id", ""))] = int(ids.get(String(pile.get("id", "")), 0)) + int(pile.get("n", 0))
	eq(int(ids.get("butcherSaw", 0)), 1, "the Saw, always: %s" % str(ids))
	eq(int(ids.get("cleaver", 0)), 1, "and the Cleaver, on the first kill")
	# Pick the Saw up: the run holds it, whatever happens to the object.
	p.pos = butcher.pos
	run(sim, 0.5)
	ok(Instance.held_count(p, "butcherSaw") > 0 or p.haul.count("butcherSaw") > 0, "picked up into the haul")
	ok(Discovery.has_key(sim, "butcherSaw"), "and the run knows it")
	has(Discovery.known_keys(sim), "key:butcherSaw", "which a guest is told too")
	p.haul.clear_all()
	ok(Discovery.has_key(sim, "butcherSaw"), "losing the object loses nothing")
	# A second Butcher, another day: no second Saw, no second Cleaver.
	sim.pickups.clear()
	var again := sim.enemies.spawn("butcher", butcher.pos)
	Damage.kill_enemy(sim, again, p)
	var second := {}
	for pile in sim.pickups:
		second[String(pile.get("id", ""))] = true
	ok(not second.has("butcherSaw"), "no second Saw: %s" % str(second.keys()))
	ok(not second.has("cleaver"))


func test_the_saw_is_workbench_two_and_the_locked_row_says_where() -> void:
	var spec: Dictionary = Config.BENCH_TIERS[2]
	eq(String(spec.key), "butcherSaw")
	ok(not String(spec.hint).is_empty(), "the locked row has somewhere to point")
	ok(Config.CONSUMABLES.butcherSaw.get("tool", false), "the Saw is never used up")
	eq(float(Config.CONSUMABLES.butcherSaw.wt), 0.0, "and weighs nothing")
	# Outside, at a bench: refused by name until the Saw has been held.
	Instance.leave(sim, "left")
	var plot := clear_plot(8)
	p.pos = tile_centre(Vector2i(plot.x + 2, plot.y)) + Vector2(0, Config.TILE * 2)
	clear_ground(sim, plot.x + 2, plot.y)
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0
	for id in ["wood", "scrap", "cloth"]:
		p.bag.add(id, 200)
	var bench := sim.structs.place(sim, "workbench", plot.x + 2, plot.y, p)
	eq(sim.structs.bench_upgrade_refusal(sim, bench, p), "Needs the Butcher's Saw")
	sim.known.held["butcherSaw"] = true
	sim.known.dirty = true
	eq(sim.structs.bench_upgrade_refusal(sim, bench, p), "")
	ok(sim.structs.upgrade_bench(sim, bench, p))


func test_the_door_says_what_to_bring() -> void:
	var rec: Array = Config.INSTANCES.barn.recommends
	eq(rec.size(), 3)
	eq(Instance.arena_name(sim), "the killing floor")
