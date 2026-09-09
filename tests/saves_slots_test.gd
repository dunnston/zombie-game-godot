extends "res://tests/test_case.gd"
## Save slots and rebindable keys: the index that lets a title screen list four
## saves without parsing four worlds, and the keyboard that belongs to the
## machine rather than to the save.

var sim: GameSim
var p: PlayerSim

## Slots the tests own, deliberately outside `Saves.MAX_SLOTS`. `user://` is
## shared with the real game, so a test writing to slot 3 would overwrite a
## player's third save — and `first_free` will never hand these out.
const T0 := 90
const T1 := 91
const T2 := 92


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	_wipe()


func after_each() -> void:
	_wipe()
	KeyBinds.reset_all()


## Leaves no slot of ours behind: these write real files under `user://`, and
## a test that leaves one changes what the next one lists.
func _wipe() -> void:
	for n in [T0, T1, T2]:
		Saves.delete(n)


## Only the slots this file owns. `user://` is shared with the real game and
## with the other save tests, so asserting on the whole list would depend on
## what somebody else left behind — and wiping it would eat a real save.
func _mine() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in Saves.list():
		if int(s.slot) in [T0, T1, T2]:
			out.append(s)
	return out


# ------------------------------------------------------------- the index --

func test_a_slot_with_nothing_in_it_is_not_listed() -> void:
	eq(_mine().size(), 0)
	for n in [T0, T1, T2]:
		ok(not FileAccess.file_exists(SaveGame.slot_path(n)))


func test_saving_writes_a_summary_worth_choosing_between() -> void:
	sim.clock.day = 4
	sim.stats.kills = 37
	p.level = 6
	sim.time = 930.0
	ok(Saves.save_to(sim, T0, "Test Run").ok)

	var all := _mine()
	eq(all.size(), 1)
	var s: Dictionary = all[0]
	eq(String(s.name), "Test Run")
	eq(int(s.day), 4)
	eq(int(s.level), 6)
	eq(int(s.kills), 37)
	eq(int(s.slot), T0)
	eq(int(s.version), SaveGame.VERSION)
	gt(float(s.updated), 0.0)
	# The whole point of the index: this did not come from parsing the world.
	ok(Saves.summary_line(s).contains("Day 4"), Saves.summary_line(s))
	ok(Saves.summary_line(s).contains("37 kills"), Saves.summary_line(s))
	ok(Saves.summary_line({"kills": 1}).contains("1 kill  "), "one kill, not one kills")


func test_slots_are_listed_newest_first() -> void:
	Saves.save_to(sim, T0, "First")
	# `updated` is a wall-clock second, so nudge the older one back rather than
	# sleeping through a real one.
	var idx := Saves.read_index()
	idx.slots[str(T0)]["updated"] = Time.get_unix_time_from_system() - 500.0
	Saves.write_index(idx)
	Saves.save_to(sim, T1, "Second")

	var all := _mine()
	eq(all.size(), 2)
	eq(String(all[0].name), "Second", "most recently played first")
	eq(String(all[1].name), "First")


func test_continue_opens_the_one_you_last_chose_not_the_one_last_written() -> void:
	Saves.save_to(sim, T0, "Chosen")
	Saves.save_to(sim, T1, "Written later")
	eq(int(Saves.latest().slot), T1, "with no choice made, the newest")

	# Loading marks a slot current before it saves, so coming straight back
	# returns to the game that was picked.
	Saves.mark_current(T0)
	eq(int(Saves.latest().slot), T0)
	eq(String(Saves.latest().name), "Chosen")


func test_a_slot_whose_file_is_gone_is_not_offered() -> void:
	Saves.save_to(sim, T0, "Doomed")
	eq(_mine().size(), 1)
	# Deleted from outside the game: the index still mentions it, and the list
	# must not offer something that cannot be opened.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.slot_path(T0)))
	eq(_mine().size(), 0, "the file is the source of whether it exists")


func test_deleting_takes_the_file_and_the_entry() -> void:
	Saves.save_to(sim, T0, "Gone")
	ok(FileAccess.file_exists(SaveGame.slot_path(T0)))
	Saves.mark_current(T0)
	ok(Saves.delete(T0))
	ok(not FileAccess.file_exists(SaveGame.slot_path(T0)))
	eq(_mine().size(), 0)
	ne(int(Saves.read_index().get("current", -1)), T0, "and CONTINUE no longer points at it")


func test_a_free_slot_is_one_with_no_file_in_it() -> void:
	var first := Saves.first_free()
	if first < 0:
		ok(true, "every slot is taken on this machine, which is a valid answer")
		return
	ok(not FileAccess.file_exists(SaveGame.slot_path(first)),
		"a free slot has nothing in it")
	# Filling one of ours moves the answer past it.
	Saves.save_to(sim, T0, "Taken")
	ne(Saves.first_free(), T0, "T0 is not free any more")


func test_names_do_not_collide() -> void:
	var a := Saves.default_name()
	Saves.save_to(sim, T0, a)
	var b := Saves.default_name()
	ne(b, a, "%s and %s" % [a, b])
	Saves.save_to(sim, T1, b)
	ne(Saves.default_name(), b)


func test_a_saved_slot_round_trips_through_the_payload() -> void:
	# The index is a summary; the payload is the game. Both have to survive.
	sim.clock.day = 3
	p.level = 5
	ok(Saves.save_to(sim, T0, "Round trip").ok)

	var fresh := new_sim()
	var r := SaveGame.load_from(fresh, T0)
	ok(r.ok, r.reason)
	eq(fresh.clock.day, 3)
	eq(fresh.players[0].level, 5)


# ------------------------------------------------------------- the labels --

func test_playtime_reads_as_time() -> void:
	eq(Saves.playtime_label(0.0), "0s")
	eq(Saves.playtime_label(42.0), "42s")
	eq(Saves.playtime_label(600.0), "10m")
	eq(Saves.playtime_label(7500.0), "2h 5m")


func test_when_reads_as_how_long_ago() -> void:
	eq(Saves.when_label(0.0), "never")
	var now := Time.get_unix_time_from_system()
	eq(Saves.when_label(now), "just now")
	ok(Saves.when_label(now - 600.0).contains("minutes"), Saves.when_label(now - 600.0))
	ok(Saves.when_label(now - 7200.0).contains("hour"), Saves.when_label(now - 7200.0))
	ok(Saves.when_label(now - 200000.0).contains("day"), Saves.when_label(now - 200000.0))


# ------------------------------------------------------------- the binds --

func test_every_listed_action_is_a_real_one() -> void:
	# The CONTROLS list is data; the actions are what the game reads. A row for
	# something that does not exist would be a key you could bind to nothing.
	for row in KeyBinds.ACTIONS:
		ok(KeyBinds.KEYS.has(String(row.id)), "no such action: %s" % row.id)
		ok(InputMap.has_action(String(row.id)), "not registered: %s" % row.id)
		ok(String(row.group) in KeyBinds.GROUPS, "%s is in no group" % row.id)
		ok(not String(row.name).is_empty(), row.id)


func test_rebinding_moves_the_key_and_the_input_map_with_it() -> void:
	var before := KeyBinds.codes_for("interact")
	ok(KeyBinds.is_default("interact"))
	ok(KeyBinds.rebind("interact", KEY_F))
	eq(KeyBinds.codes_for("interact"), [KEY_F])
	ok(not KeyBinds.is_default("interact"))
	eq(KeyBinds.label_for("interact"), "F")

	# The InputMap is what the game actually reads, so the rebind has to reach
	# it, not just the table.
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F
	ok(InputMap.event_is_action(ev, "interact"), "F now does it")
	var old := InputEventKey.new()
	old.physical_keycode = before[0]
	ok(not InputMap.event_is_action(old, "interact"), "and the old key does not")


func test_escape_can_never_be_rebound_onto() -> void:
	# Escape is how you get out of everything, including a screen you opened
	# by accident with a key you have just reassigned.
	ok(not KeyBinds.rebind("interact", KEY_ESCAPE))
	ok(KeyBinds.is_default("interact"), "and nothing changed")


func test_a_conflict_is_reported_rather_than_refused() -> void:
	# Two things on one key is a choice the player is allowed to make. It has
	# to be visible, not impossible.
	ok(KeyBinds.rebind("interact", KEY_J))
	ok(KeyBinds.rebind("reload", KEY_J))
	ok(KeyBinds.conflicts_for("interact").has("reload"))
	ok(KeyBinds.conflicts_for("reload").has("interact"))
	eq(KeyBinds.conflicts_for("light").size(), 0, "and nothing else is dragged into it")


func test_resetting_puts_every_key_back() -> void:
	var before := KeyBinds.codes_for("build")
	KeyBinds.rebind("build", KEY_G)
	KeyBinds.rebind("map", KEY_H)
	KeyBinds.reset_all()
	eq(KeyBinds.codes_for("build"), before)
	ok(KeyBinds.is_default("build"))
	ok(KeyBinds.is_default("map"))


func test_binds_survive_a_reload_from_disk() -> void:
	# Per machine, not per save: they belong to the keyboard in front of you.
	KeyBinds.rebind("crafting", KEY_Y)
	KeyBinds.load_binds()
	eq(KeyBinds.codes_for("crafting"), [KEY_Y])
	ok(not KeyBinds.is_default("crafting"))


func test_a_binding_for_an_action_that_no_longer_exists_is_dropped() -> void:
	# An old binds file naming something this build removed must not crash the
	# boot, and must not register a phantom action.
	var f := FileAccess.open(KeyBinds.STORE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"a_removed_action": [KEY_Z], "map": [KEY_N]}))
	f.close()
	KeyBinds.load_binds()
	ok(not KeyBinds.custom.has("a_removed_action"))
	eq(KeyBinds.codes_for("map"), [KEY_N], "and the real one still took")


func test_prompts_are_built_from_the_bindings() -> void:
	# Every on-screen hint reads the binding rather than a hardcoded letter,
	# so rebinding changes what the game tells you to press.
	eq(KeyBinds.primary_label("interact"), "E")
	KeyBinds.rebind("interact", KEY_F)
	eq(KeyBinds.primary_label("interact"), "F")
