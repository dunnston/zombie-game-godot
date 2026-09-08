extends "res://tests/test_case.gd"
## The save round trips: play a little, save, load into a fresh simulation,
## and find the same game.
##
## `_slow_test.gd`, because loading regenerates a 320-tile world — that is
## the point of the format, and it is 350ms a time. `tools\test --all` runs
## these, once per branch beside the smoke run.

var sim: GameSim
var p: PlayerSim
var plot: Vector2i


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = clear_plot(8)
	p.pos = tile_centre(plot)
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0


## A private world so a save test can loot containers and fell trees without
## the shared one carrying the marks into another file.
static var _priv: World

func _own_sim() -> GameSim:
	if _priv == null:
		_priv = World.new()
	for c in _priv.containers:
		c.looted = false
	var s := GameSim.new()
	s.start(_priv, 3)
	s.enemies.list.clear()
	s.events.clear()
	return s


# ------------------------------------------------------------ round trips --

func test_what_you_carried_comes_back() -> void:
	p.bag.add("scrap", 44)
	p.bag.add("milVest", 1)
	p.hotbar.clear_all()
	p.hotbar.add("rifle", 1)
	p.hotbar.add("bandage", 3)
	p.mag["rifle"] = 5
	p.slot = 1
	p.xp = 320
	p.hp = 71.0
	Equipment.equip_best(sim, p)
	gt(p.armor_dr, 0.0)

	var out := GameSim.new()
	var r := SaveGame.apply(out, SaveGame.to_dict(sim))
	ok(r.ok, r.reason)
	var q: PlayerSim = out.players[0]
	eq(q.bag.count("scrap"), 44)
	eq(q.count_carried("rifle"), 1)
	eq(q.count_carried("bandage"), 3)
	eq(q.mag.rifle, 5, "with what was in the magazine")
	eq(q.slot, 1, "holding what you were holding")
	eq(q.xp, 320)
	near(q.hp, 71.0, 0.01)
	eq(q.equip.body, "milVest", "still wearing it")
	near(q.armor_dr, p.armor_dr, 0.001, "and it still protects — recompute ran")
	near(q.pos.distance_to(p.pos), 0.0, 0.01)


func test_a_looted_container_is_still_looted_and_a_felled_tree_still_down() -> void:
	var s := _own_sim()
	var q := s.players[0]
	# Loot one container and fell one tree, by tile.
	var c: Dictionary = s.world.containers[7]
	c.looted = true
	var tree := {}
	for pr in s.world.props:
		if pr.get("harvest", "") == "wood":
			tree = pr
			break
	ok(not tree.is_empty(), "the world has a tree in it")
	var tree_tile := Vector2i(tree.tx, tree.ty)
	s.world.remove_prop(tree)

	var out := GameSim.new()
	var rr := SaveGame.apply(out, SaveGame.to_dict(s))
	ok(rr.ok, rr.reason)
	# The reloaded world is a fresh generation, so identity has to survive
	# by tile — this is invariant 7, and it is the whole point of the format.
	var same := out.world.containers[7]
	eq(same.tx, c.tx, "the seventh container is in the same place")
	ok(same.looted, "and it is still empty")
	ok(out.world.prop_at_tile(tree_tile.x, tree_tile.y).is_empty(), "the tree is still felled")
	var still_full := 0
	for o in out.world.containers:
		if not o.looted:
			still_full += 1
	eq(still_full, out.world.containers.size() - 1, "and nothing else was marked")


func test_a_base_comes_back_standing() -> void:
	for id in ["wood", "stone", "sticks", "scrap", "cloth", "elec", "parts"]:
		p.bag.add(id, 400)
	var wall := sim.structs.place(sim, "woodWall", plot.x + 2, plot.y, p)
	var gate := sim.structs.place(sim, "gate", plot.x + 3, plot.y, p)
	var chest := sim.structs.place(sim, "chest", plot.x + 2, plot.y + 1, p)
	var stash := sim.structs.place(sim, "stash", plot.x + 3, plot.y + 1, p)
	var bench := sim.structs.place(sim, "workbench", plot.x + 2, plot.y + 2, p)
	sim.structs.upgrade_bench(sim, bench, p)
	sim.structs.damage(sim, wall, 100.0)
	sim.structs.toggle_gate(sim, gate)
	chest.store.add("mil", 12)
	sim.stash.add("ammoP", 90)
	sim.threat.value = 42.0
	sim.raids_done = 2

	var out := GameSim.new()
	ok(SaveGame.apply(out, SaveGame.to_dict(sim)).ok)
	eq(out.structs.count(), 5, "every piece is back")
	var w2 := out.structs.at_tile(plot.x + 2, plot.y)
	near(w2.hp, wall.hp, 0.01, "with the damage it had taken")
	ok(out.structs.at_tile(plot.x + 3, plot.y).open, "the gate is still open")
	ok(not out.structs.solid_at(plot.x + 3, plot.y), "and still a doorway")
	eq(out.structs.at_tile(plot.x + 2, plot.y + 1).store.count("mil"), 12, "the chest kept its contents")
	eq(out.stash.count("ammoP"), 90, "and the stash kept the pile")
	eq(out.structs.bench_tier, 2, "Workbench II is still Workbench II")
	near(out.threat.value, 42.0, 0.01)
	eq(out.raids_done, 2)


func test_a_bedroll_is_still_where_you_wake_up() -> void:
	for id in ["wood", "cloth"]:
		p.bag.add(id, 100)
	sim.structs.place(sim, "bedroll", plot.x + 2, plot.y, p)
	eq(p.spawn_tile, Vector2i(plot.x + 2, plot.y))
	var out := GameSim.new()
	ok(SaveGame.apply(out, SaveGame.to_dict(sim)).ok)
	eq(out.players[0].spawn_tile, Vector2i(plot.x + 2, plot.y))
	ok(out.structs.at_tile(plot.x + 2, plot.y).active, "and it is marked as the active one")


func test_the_pack_you_died_with_survives_a_save() -> void:
	sim.give_test_kit(p)
	Damage.kill_player(sim, p)
	eq(sim.backpacks.size(), 1)
	var out := GameSim.new()
	ok(SaveGame.apply(out, SaveGame.to_dict(sim)).ok)
	eq(out.backpacks.size(), 1, "still where you fell")
	has(out.backpacks[0].held, "ammoP")


func test_a_file_round_trips_through_the_disk() -> void:
	p.bag.add("wood", 33)
	ok(SaveGame.save_to(sim, 7).ok)
	var out := GameSim.new()
	var r := SaveGame.load_from(out, 7)
	ok(r.ok, r.reason)
	eq(out.players[0].bag.count("wood"), 33)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.slot_path(7)))


# ------------------------------------------------ the Codex review, PR #5 --

func test_loading_ends_the_raid_you_loaded_out_of() -> void:
	# Save quietly, let a raid start, then load the quiet save into the same
	# live simulation. The raid must not carry over and go on spawning waves
	# into the restored snapshot.
	var data := SaveGame.to_dict(sim)
	sim.raids_done = 0
	sim.threat.value = 100.0
	sim.tick(1.0 / 60.0)
	ok(sim.raid != null, "a raid is under way")
	sim.raid.timer = 0.05
	run(sim, 3.0)
	gt(sim.enemies.alive_count(), 0, "with raiders on the ground")

	ok(SaveGame.apply(sim, data).ok)
	ok(sim.raid == null, "the raid did not survive the load")
	eq(sim.enemies.alive_count(), 0, "and neither did its horde")
	run(sim, 2.0)
	ok(sim.raid == null, "and it does not restart itself")


func test_loading_clears_what_was_in_the_air() -> void:
	sim.give_test_kit(p)
	var data := SaveGame.to_dict(sim)
	p.select_slot(p.hotbar_index("rifle"))
	p.intent.aim = p.pos + Vector2(400, 0)
	Combat.fire_gun(sim, p, p.weapon())
	gt(sim.bullets.size(), 0, "a round is in flight")
	sim.threat.value = 55.0
	sim.stats.kills = 9
	ok(SaveGame.apply(sim, data).ok)
	eq(sim.bullets.size(), 0, "it is not still coming for the restored player")
	near(sim.threat.value, 0.0, 0.01, "and Threat is the saved game's, not the run's")
	eq(sim.stats.kills, 0)
