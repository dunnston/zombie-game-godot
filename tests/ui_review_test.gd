extends "res://tests/test_case.gd"
## Codex on PR #37: four places the redesigned screens showed something other
## than what the game had become. Each test asks the screen's own source of
## truth — the selection PLACE acts on, the signature a section rebuilds on,
## the rule the hotbar draws by — rather than a picture.

var sim: GameSim
var p: PlayerSim


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]


func _survivor() -> SurvivorSim:
	var c := sim.crew.make(sim, p.pos + Vector2(40, 0), "Hal")
	if not sim.crew.alive().has(c):
		sim.crew.list.append(c)
	return c


# ------------------------------------------------------------ build menu --

func test_a_search_that_hides_the_selected_piece_moves_the_selection() -> void:
	var bar := BuildBar.new(sim)
	bar.toggle()
	bar.select_card("woodWall")
	bar.build_search = "stone"
	bar.reconcile()
	ok(not bar._shown().is_empty(), "a search for stone finds something")
	ok(bar.selected_card() != "woodWall", "the hidden Wood Wall is no longer what PLACE would build")
	has(bar._shown(), bar.selected_card(), "the selection is one of the pieces on the page")
	bar.free()


func test_can_build_now_leaves_nothing_to_place_when_nothing_is_affordable() -> void:
	p.bag.clear_all()
	p.hotbar.clear_all()
	sim.stash = null
	var bar := BuildBar.new(sim)
	bar.toggle()
	bar.select_card("woodWall")
	bar.build_filter = true
	bar.reconcile()
	eq(bar._shown().size(), 0, "nothing is affordable with an empty pack")
	ok(not bar.placeable(), "so a piece the filter hid cannot be taken into the street")
	bar.free()


# ------------------------------------------------------------------- crew --

func test_the_crew_detail_rebuilds_when_the_selected_survivor_is_hurt() -> void:
	var s := InventoryScreen.new(sim)
	var c := _survivor()
	s.crew_sel = c.id
	var page := CrewPage.new()
	var before := page._detail_sig(s)
	c.hp -= 20.0
	ok(page._detail_sig(s) != before, "the detail's HP badge follows the survivor's health")
	s.free()


func test_the_ration_warning_rebuilds_as_the_count_falls() -> void:
	sim.stash = Slots.new(Config.STASH_SLOTS)
	sim.stash.add("rations", 2)
	_survivor()
	var s := InventoryScreen.new(sim)
	var page := CrewPage.new()
	ok(not String(page._ration_state(s)[0]).is_empty(), "two rations for one mouth is short")
	var before := page._ration_sig(s)
	sim.stash.take("rations", 1)
	ok(not String(page._ration_state(s)[0]).is_empty(), "and one is still short")
	ok(page._ration_sig(s) != before, "but the warning's count moves with it")
	s.free()


# -------------------------------------------------------------------- hud --

func test_a_worn_tool_shows_its_condition_on_the_hotbar() -> void:
	ok(Config.WEAPONS.axe.get("tool", false), "the Hatchet is a tool")
	p.hotbar.slots[0] = {"id": "axe", "n": 1}
	p.hotbar.set_wear_at(0, maxi(1, Wear.max_of("axe") / 5))
	ok(Wear.is_worn(p.hotbar, 0) and not Wear.is_broken(p.hotbar, 0), "a fifth left is worn, not broken")
	ok(Hud.HotSlot.shows_sliver(p, 0), "the hotbar says how worn it is, as it did before the redesign")
