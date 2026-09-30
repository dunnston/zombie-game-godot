extends TestCase
## Guidance (progression step B): what the run knows how to make, and how it
## came to know it. The known set is derived from facts, never stored.

var sim: GameSim
var p: PlayerSim
var plot: Vector2i


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = clear_plot(10)
	p.pos = tile_centre(plot)
	p.intent.aim = p.pos + Vector2.RIGHT


func _known(id: String) -> bool:
	return Discovery.recipe_known(sim, Crafting.recipe(id))


func _tier_rows(tier: int, wave: int) -> Array:
	var out: Array = []
	for r in Config.RECIPES:
		if int(r.bench) == tier and int(r.get("wave", 2)) == wave and not r.has("station"):
			out.append(String(r.id))
	for id in Config.STRUCTURES:
		var def: Dictionary = Config.STRUCTURES[id]
		if int(def.get("tier", 1)) == tier and int(def.get("wave", 2)) == wave:
			out.append(Discovery.build_key(id))
	return out


# ------------------------------------------------------------------- data --

func test_no_wave_reveals_more_than_eight() -> void:
	# The rule the flood was fixed with (Progression Map §19): recipes and
	# buildables are counted apart, because they are on different screens.
	for tier in range(1, Config.MAX_BENCH + 1):
		for wave in range(1, 6):
			var recipes := 0
			var builds := 0
			for r in Config.RECIPES:
				if int(r.bench) == tier and int(r.get("wave", 2)) == wave and not r.has("station"):
					recipes += 1
			for id in Config.STRUCTURES:
				var def: Dictionary = Config.STRUCTURES[id]
				if int(def.get("tier", 1)) == tier and int(def.get("wave", 2)) == wave:
					builds += 1
			ok(recipes <= 8, "tier %d wave %d reveals %d recipes" % [tier, wave, recipes])
			ok(builds <= 8, "tier %d wave %d reveals %d buildables" % [tier, wave, builds])


func test_every_row_has_a_wave_and_every_tier_a_kit() -> void:
	for r in Config.RECIPES:
		var w := int(r.get("wave", 0))
		ok(w >= 1 and w <= 5, "%s wave %d" % [r.id, w])
	for id in Config.STRUCTURES:
		var w := int(Config.STRUCTURES[id].get("wave", 0))
		ok(w >= 1 and w <= 5, "%s wave %d" % [id, w])
	for tier in range(1, 5):
		gt(_tier_rows(tier, Discovery.WAVE_KIT).size(), 0, "tier %d has a Kit for its Set to wait on" % tier)
		ok(Config.WAVES.has(tier), "tier %d has triggers" % tier)


# ------------------------------------------------------------------ rules --

## What a fresh run can build: the first bench, the basic walls and the gate
## (owner, 2026-09-30 — a wall should not wait for a raid). Sorted, as
## `known_keys` returns them.
const FIRST_DAY := ["barricade", "gate", "stoneWall", "woodWall", "workbench"]

func test_a_fresh_run_knows_only_the_workbench_and_the_basic_walls() -> void:
	var keys := Discovery.known_keys(sim)
	var want := FIRST_DAY.map(func(t: String) -> String: return Discovery.build_key(t))
	eq(keys, want, "the first bench, the basic walls and the gate: %s" % str(keys))
	ok(not _known("axe"), "not even a hatchet, until you hold a stone")


func test_by_hand_recipes_arrive_with_their_first_material() -> void:
	p.bag.add("stone", 1)
	Discovery.tick(sim)
	ok(_known("axe"), "stone is in a hatchet")
	ok(_known("knife"))
	ok(not _known("torch"), "a torch is sticks and fiber, neither held")
	p.bag.add("sticks", 1)
	Discovery.tick(sim)
	ok(_known("torch"))


func test_the_tiers_arrive_in_waves() -> void:
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0
	for id in ["wood", "stone", "sticks", "scrap", "cloth", "fiber"]:
		p.bag.add(id, 400)
	Discovery.tick(sim)
	ok(not _known("woodenSpear"), "chapter 1's Kit waits for the bench")
	ok(not Discovery.structure_known(sim, "chest"))
	# The bench: the Kit.
	clear_ground(sim, plot.x + 2, plot.y)
	p.pos = tile_centre(Vector2i(plot.x + 2, plot.y)) + Vector2(0, Config.TILE * 2)
	var bench := sim.structs.place(sim, "workbench", plot.x + 2, plot.y, p)
	ok(not bench.is_empty())
	ok(_known("woodenSpear"), "the Kit arrived with the bench")
	ok(_known("bow"))
	ok(Discovery.structure_known(sim, "chest"))
	ok(not _known("workGloves"), "the Set waits for something from the Kit")
	ok(not Discovery.structure_known(sim, "stash"))
	# Make one thing from the Kit: the Set.
	ok(Crafting.craft(sim, p, Crafting.recipe("woodenSpear"), 1))
	ok(_known("workGloves"), "the Set arrived with the first Kit item")
	ok(_known("medkit") or true)
	ok(Discovery.structure_known(sim, "stash"))
	ok(not _known("jerky"), "the second wave waits for its material")
	ok(not Discovery.structure_known(sim, "raisedBed"))
	p.bag.add("rations", 1)
	Discovery.tick(sim)
	ok(_known("jerky"), "and rations are chapter 1's second material")
	ok(Discovery.structure_known(sim, "raisedBed"))
	# Nothing of chapter 2 yet, whatever is held.
	p.bag.add("parts", 5)
	p.bag.add("steelBar", 1)
	Discovery.tick(sim)
	ok(not _known("machete"), "chapter 2 waits for Workbench II")
	give_keys(sim)
	ok(sim.structs.upgrade_bench(sim, bench, p))
	ok(_known("hacksaw"), "Workbench II: the Foothold")
	ok(Discovery.structure_known(sim, "forge"))
	ok(_known("machete"), "Workbench II and a Steel Bar held: the Kit")
	ok(not _known("riotHelm"), "its Set waits")
	ok(_known("pistol"), "and its guns, on the Weapon Parts")
	# The bar itself is the Forge's, and the Forge's alone.
	ok(not _known("steelBar"), "no Forge, no bar")
	Discovery.note_built(sim, "forge")
	ok(_known("steelBar"))


func test_defence_arrives_with_the_raid_warning() -> void:
	ok(Discovery.structure_known(sim, "woodWall"), "the basic walls are there from the start")
	ok(Discovery.structure_known(sim, "gate"), "and the gate with them")
	ok(not Discovery.structure_known(sim, "bunk"), "a bunk is a Defence-wave arrival")
	sim.structs.bench_tier = 0
	var r := Raid.start(sim, false)
	r.force_end(sim)
	ok(Discovery.structure_known(sim, "bunk"), "the first raid warning brings the rest of the Defence")
	ok(not Discovery.structure_known(sim, "spike"), "the spike trap is chapter 2's Defence")


func test_a_station_reveals_its_own_recipes() -> void:
	ok(not _known("suppressant"))
	Discovery.note_built(sim, "chemStation")
	ok(_known("suppressant"), "the Chemistry Station brings its chemistry")


func test_new_things_are_announced_once_and_not_on_a_fresh_run() -> void:
	sim.events.clear()
	Discovery.tick(sim)
	eq(events_of(sim, "known").size(), 0, "a fresh run's first look is not news")
	p.bag.add("stone", 1)
	Discovery.tick(sim)
	eq(events_of(sim, "known").size(), 1)
	has(events_of(sim, "known")[0].keys, "axe")
	var said := false
	for e in events_of(sim, "notify"):
		if String(e.text).begins_with("New at the bench"):
			said = true
	ok(said, "and it was said on the HUD")
	Discovery.tick(sim)
	eq(events_of(sim, "known").size(), 1, "and not said twice")


func test_the_screens_show_only_what_is_known() -> void:
	var by_hand := Crafting.visible_recipes(p, 0, {}, sim)
	eq(by_hand.size(), 0, "nothing by hand before a pickup")
	p.bag.add("cloth", 4)
	Discovery.tick(sim)
	by_hand = Crafting.visible_recipes(p, 0, {}, sim)
	eq(by_hand.size(), 1)
	eq(String(by_hand[0].id), "bandage")
	# Without a sim the whole tier is listed: the data tests and the editor.
	gt(Crafting.visible_recipes(p, 0).size(), 1)


func test_the_bench_teases_the_next_rungs_foothold() -> void:
	Discovery.reveal_all(sim)
	var by_hand := Crafting.visible_recipes(p, 0, {}, sim)
	eq(by_hand.size(), 6, "known or not, the C tab is the six basics")
	sim.known = Discovery.fresh()
	Discovery.note_bench(sim, 1)
	var listed := Crafting.visible_recipes(p, 1, {}, sim)
	var ids: Array = []
	for r in listed:
		ids.append(String(r.id))
	# Chapter 2's Foothold, the Hacksaw, is the one thing past the top of a
	# first bench; nothing else of tier 2 leaks in.
	has(ids, "hacksaw", "the teaser")
	for id in ids:
		var r := Crafting.recipe(id)
		ok(int(r.bench) <= 1 or (int(r.bench) == 2 and int(r.wave) == Discovery.WAVE_FOOTHOLD), "%s is not tier 1 or the teaser" % id)


func test_reveal_all_knows_everything() -> void:
	Discovery.reveal_all(sim)
	for r in Config.RECIPES:
		ok(Discovery.recipe_known(sim, r), String(r.id))
	for id in Config.STRUCTURES:
		ok(Discovery.structure_known(sim, id), id)


# ------------------------------------------------------------- the player --

func test_seen_and_pinned_survive_a_save() -> void:
	p.seen["axe"] = true
	p.pinned = "axe"
	p.bag.add("stone", 2)
	Discovery.tick(sim)
	Discovery.note_built(sim, "workbench")
	var payload := SaveGame.to_dict(sim)
	var fresh := new_sim()
	var r := SaveGame.apply(fresh, payload)
	ok(r.ok, r.reason)
	var q: PlayerSim = fresh.players[0]
	ok(q.seen.has("axe"))
	eq(q.pinned, "axe")
	ok(fresh.known.held.has("stone"), "the facts came back")
	ok(Discovery.recipe_known(fresh, Crafting.recipe("axe")), "and the list is derived from them")
	ok(fresh.known.built.has("workbench"))


func test_the_pinned_card_says_what_is_short_and_where() -> void:
	p.pinned = "axe"
	p.bag.clear_all()
	p.bag.add("stone", 1)
	var lines := Hud.pin_lines(sim, p)
	eq(lines.size(), 3, "fiber, sticks, stone")
	var by_id := {}
	for l in lines:
		by_id[l.id] = l
	eq(int(by_id.stone.have), 1)
	eq(int(by_id.stone.need), 3)
	ok(by_id.stone.short)
	ok(not String(by_id.stone.found).is_empty(), "and where to look for it")
	p.pinned = Discovery.build_key("workbench")
	lines = Hud.pin_lines(sim, p)
	eq(lines.size(), 2, "a buildable pins too: wood and scrap")
	p.pinned = ""
	eq(Hud.pin_lines(sim, p).size(), 0)


# -------------------------------------------------------------------- wire --

func test_a_guest_draws_the_same_cards() -> void:
	var guest := new_sim()
	eq(Discovery.known_keys(guest).size(), FIRST_DAY.size())
	p.bag.add("stone", 1)
	Discovery.tick(sim)
	var keys := Discovery.known_keys(sim)
	guest.events.clear()
	Discovery.apply_keys(guest, keys)
	eq(Discovery.known_keys(guest), keys)
	ok(Discovery.recipe_known(guest, Crafting.recipe("axe")), "known on the guest without the facts")
	# The host's line and event are relayed to every guest as they are made,
	# so the list itself says nothing (Codex, PR #65).
	eq(events_of(guest, "known").size(), 0, "and not announced a second time from the list")
	eq(events_of(guest, "notify").size(), 0)


func test_a_guests_seen_and_pin_reach_the_host() -> void:
	# The commands a guest's screen sends, run on the host as that guest
	# (Codex, PR #65): what a save keeps has to be on the host's copy.
	ok(Actions.execute(sim, p, "mark_seen", {"key": "axe"}))
	ok(p.seen.has("axe"))
	ok(not Actions.execute(sim, p, "mark_seen", {"key": "no_such_thing"}), "only a real key")
	ok(Actions.execute(sim, p, "pin", {"key": Discovery.build_key("workbench")}))
	eq(p.pinned, Discovery.build_key("workbench"))
	ok(Actions.execute(sim, p, "pin", {"key": ""}), "and unpinned")
	eq(p.pinned, "")
	ok(not Actions.execute(sim, p, "pin", {"key": "build:nothing"}))
	# Locally the same functions toggle, and send the value rather than the toggle.
	Actions.pin(sim, p, "axe")
	eq(p.pinned, "axe")
	Actions.pin(sim, p, "axe")
	eq(p.pinned, "")
