extends "res://tests/test_case.gd"
## Saving and loading. The assertion that matters is the round trip: play a
## little, save, load into a fresh simulation, and find the same game.

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


# ------------------------------------------------------------ fingerprint --

func test_the_fingerprint_describes_the_generator_not_the_run() -> void:
	gt(world().fingerprint(), 0)
	# A private world, because this test fells a tree in it: the shared one
	# is read by every other file and must not carry the mark.
	var other := World.new(11)
	ne(other.fingerprint(), world().fingerprint(), "a different seed fingerprints differently")
	# The fingerprint is taken once, at generation. Felling a tree clears a
	# collision byte and drops a prop, and a fingerprint that moved with them
	# would refuse the save it was written for.
	var before := other.fingerprint()
	var tree := {}
	for pr in other.props:
		if pr.get("harvest", "") == "wood":
			tree = pr
			break
	ok(not tree.is_empty(), "the world has a tree in it")
	other.remove_prop(tree)
	eq(other.fingerprint(), before, "still the same map, as far as a save is concerned")


func test_a_save_from_a_different_generator_is_refused_with_a_reason() -> void:
	var data := SaveGame.to_dict(sim)
	data.fingerprint = 12345
	var r := SaveGame.apply(GameSim.new(), data)
	ok(not r.ok)
	ok(r.reason.contains("fingerprint"), r.reason)


func test_a_save_from_another_version_is_refused_by_name() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveGame.DIR))
	var f := FileAccess.open(SaveGame.slot_path(9), FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 99}))
	f.close()
	var r := SaveGame.read_slot(9)
	ok(not r.ok)
	ok(r.reason.contains("99") and r.reason.contains(str(SaveGame.VERSION)), r.reason)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.slot_path(9)))


func test_an_empty_slot_says_so() -> void:
	var r := SaveGame.read_slot(8)
	ok(not r.ok)
	ok(r.reason.contains("empty"), r.reason)


# ------------------------------------------------------------ round trips --
