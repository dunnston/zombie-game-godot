extends TestCase
## Chapter 2's material (progression step D): the Hacksaw, the wrecks it cuts,
## the Forge, Steel Bar, and the three chore items Workbench II unlocks.

var sim: GameSim
var p: PlayerSim
var plot: Vector2i


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = clear_plot(10)
	p.pos = tile_centre(plot)
	p.intent.aim = p.pos + Vector2.RIGHT


func _hold(id: String, wear := -1) -> void:
	p.hotbar.clear_all()
	p.hotbar.add(id, 1, wear)
	p.slot = 0


func _stock(n := 200) -> void:
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0
	for id in ["wood", "stone", "sticks", "scrap", "cloth", "fiber", "sheetMetal", "steelBar", "fuel"]:
		p.bag.add(id, n)


## A wreck with open ground on its south side, in a private world.
func _wreck() -> Dictionary:
	var w := World.new()
	sim.world = w
	for pr in w.props:
		if pr.kind != "wreck":
			continue
		var below := Vector2i(int(pr.tx), int(pr.ty) + 2)
		if not w.is_blocked_tile(below.x, below.y) and not w.is_blocked_tile(below.x + 1, below.y):
			return pr
	return {}


# ------------------------------------------------------------------ the data --

func test_the_chapter_is_priced_in_steel() -> void:
	ok(Config.RES.has("sheetMetal"))
	ok(Config.RES.has("steelBar"))
	for id in ["machete", "fireaxe", "steelpick", "pistol", "riotHelm", "heavyVest", "tacGloves", "paddedLegs", "combatBoots", "packFrame", "oilLantern", "repairKit"]:
		var r := Crafting.recipe(id)
		ok(not r.is_empty(), id)
		eq(int(r.bench), 2, "%s is chapter 2" % id)
		ok(r.cost.has("steelBar"), "%s is priced in Steel Bar" % id)
	var bar := Crafting.recipe("steelBar")
	eq(String(bar.station), "forge", "a bar is Forge work")
	eq(int(bar.bench), 0, "and no workbench tier hands it out")
	eq(String(Config.STRUCTURES.forge.station), "forge")
	eq(int(Config.STRUCTURES.forge.tier), 2)
	ok(Config.WEAPONS.hacksaw.get("hacksaw", false), "the Hacksaw carries its own tool flag")
	eq(Config.WAVES[2].kit.held, ["steelBar"], "chapter 2's Kit arrives with the first bar")


# ---------------------------------------------------------------- the wreck --

func test_a_wreck_is_sheet_metal_behind_the_hacksaw() -> void:
	var wreck := _wreck()
	ok(not wreck.is_empty(), "found a wreck with open ground south of it")
	if wreck.is_empty():
		return
	var w := sim.world
	var W := Config.WORLD_TILES
	var left: int = int(wreck.ty) * W + int(wreck.tx)
	eq(w.blocked[left], 1, "a wreck blocks its left tile")
	eq(w.blocked[left + 1], 1, "and its right")
	eq(w.prop_at_tile(int(wreck.tx) + 1, int(wreck.ty)), wreck, "and is on the grid under both")
	p.pos = Vector2(wreck.x, wreck.y + 44)
	p.intent.aim = Vector2(wreck.x, wreck.y)
	# A hatchet bounces: the wreck asks for a Hacksaw.
	_hold("axe")
	p.intent.fire = true
	run(sim, 1.5)
	eq(w.blocked[left], 1, "the hatchet did nothing to it")
	eq(p.count_res("sheetMetal"), 0)
	ok(events_of(sim, "bounce").size() > 0, "and bounced")
	# The Hacksaw cuts it up: 900 hit points at 14 a swing, so it takes a while.
	_hold("hacksaw")
	p.stam = p.max_stam
	for i in range(40):
		p.stam = p.max_stam
		run(sim, 1.0)
		if w.blocked[left] == 0:
			break
	eq(w.blocked[left], 0, "cut up: the left tile is open")
	eq(w.blocked[left + 1], 0, "and the right")
	ok(w.prop_at_tile(int(wreck.tx), int(wreck.ty)).is_empty(), "and it is off the grid")
	ok(w.prop_at_tile(int(wreck.tx) + 1, int(wreck.ty)).is_empty())
	ok(wreck.get("gone", false), "and not drawn")
	ok(p.count_res("sheetMetal") >= 4, "Sheet Metal +%d" % p.count_res("sheetMetal"))
	ok(p.count_res("scrap") >= 2, "and the scrap that came off it")
	has(w.chopped_keys(), "%d,%d" % [int(wreck.tx), int(wreck.ty)], "the anchor is what the save keeps")
	eq(w.chopped_keys().count("%d,%d" % [int(wreck.tx) + 1, int(wreck.ty)]), 0, "and only the anchor")


func test_a_cut_wreck_stays_cut_through_a_save() -> void:
	var wreck := _wreck()
	if wreck.is_empty():
		return
	var key := Vector2i(int(wreck.tx), int(wreck.ty))
	sim.world.remove_prop(wreck)
	var payload := SaveGame.to_dict(sim)
	# A save replays what was cut against a world rebuilt from the seed; the
	# private world above shares the seed, so the wreck is there to replay.
	var fresh := new_sim()
	fresh.world = World.new()
	var r := SaveGame.apply(fresh, payload)
	ok(r.ok, r.reason)
	ok(fresh.world.prop_at_tile(key.x, key.y).is_empty(), "gone on the way back")
	eq(fresh.world.blocked[key.y * Config.WORLD_TILES + key.x + 1], 0, "both tiles open")


func test_there_are_wrecks_enough_for_a_chapter() -> void:
	# The Progression Map's budget: about eighty bars a chapter, four players.
	var n := 0
	for pr in sim.world.props:
		if pr.kind == "wreck":
			n += 1
	gt(n, 60, "%d wrecks" % n)


# ---------------------------------------------------------------- the forge --

func test_a_bar_is_forge_work() -> void:
	_stock()
	var bar := Crafting.recipe("steelBar")
	eq(Crafting.status(sim, p, bar, 5).reason, "Needs a Forge", "no workbench tier hands it out")
	clear_ground(sim, plot.x + 2, plot.y)
	p.pos = tile_centre(Vector2i(plot.x + 2, plot.y)) + Vector2(0, Config.TILE * 2)
	sim.structs.bench_tier = 2
	ok(not sim.structs.place(sim, "forge", plot.x + 2, plot.y, p).is_empty(), "the Forge went up")
	ok(Crafting.stations_at(sim, p).has("forge"), "standing at it")
	var metal := p.count_res("sheetMetal")
	var bars := p.count_res("steelBar")
	ok(Crafting.craft(sim, p, bar, 0))
	eq(p.count_res("sheetMetal"), metal - 1)
	eq(p.count_res("steelBar"), bars + 1, "one in, one out")
	ok(Crafting.visible_recipes(p, 0, {"forge": true}, sim).has(bar), "listed at the Forge")


# ------------------------------------------------------------ chore items --

func test_the_pack_frame_is_carried_once_and_kept() -> void:
	var before := p.carry_cap
	near(before, 100.0, 1e-9, "the strict start's pack")
	p.bag.add("packFrame", 2)
	ok(p.start_use(sim, "packFrame"))
	run(sim, 1.5)
	eq(p.pack_tier, 1)
	near(p.carry_cap, before + float(Config.PACK_TIERS[1]), 1e-9, "160")
	eq(p.count_carried("packFrame"), 1, "one was spent")
	ok(not p.start_use(sim, "packFrame"), "a second one does nothing, and is not spent")
	eq(p.count_carried("packFrame"), 1)
	# The tier is the build, and comes back the same way: through the recompute.
	Equipment.recompute_stats(p)
	near(p.carry_cap, before + float(Config.PACK_TIERS[1]), 1e-9)
	var payload := SaveGame.to_dict(sim)
	var fresh := new_sim()
	ok(SaveGame.apply(fresh, payload).ok)
	eq(fresh.players[0].pack_tier, 1)
	near(fresh.players[0].carry_cap, before + float(Config.PACK_TIERS[1]), 1e-9, "and a save keeps the pack")


func test_the_repair_kit_mends_the_held_weapon_by_half() -> void:
	_hold("machete", 10)
	p.bag.add("repairKit", 1)
	ok(p.start_use(sim, "repairKit"))
	run(sim, 2.5)
	eq(p.count_carried("repairKit"), 0, "spent")
	eq(Wear.left(p.hotbar, 0), mini(Wear.max_of("machete"), 10 + ceili(Wear.max_of("machete") * 0.5)), "half a life back")
	# Never past whole, and never spent on something whole.
	_hold("machete")
	p.bag.add("repairKit", 1)
	ok(not p.start_use(sim, "repairKit"), "nothing to mend")
	eq(p.count_carried("repairKit"), 1)


func test_the_oil_lantern_burns_fuel_for_nights() -> void:
	var g: Dictionary = Config.GEAR.oilLantern
	eq(String(g.battery), "fuel", "refilled from Fuel")
	ok(float(g.burn) >= 4.0 * Config.DAY_LENGTH * 0.5, "a fill is nights of light, not one")
	eq(String(g.slot), "offhand")
	ok(g.has("light"))
	# And the prompts say Fuel, not battery (Codex, PR #66).
	eq(Equipment.refill_name(g), "Fuel")
	eq(Equipment.refill_name(Config.GEAR.flashlight), "Batteries")


func test_the_range_holds_and_baselines_the_pack_tier() -> void:
	# A Pack Frame fitted in the range must not leave with you, and your own
	# comes back when you do (Codex, PR #66).
	p.pack_tier = 1
	var held := TargetRange.hold(p)
	TargetRange.baseline(p)
	eq(p.pack_tier, 0, "the range is the strict start's pack")
	p.pack_tier = 2
	TargetRange.give_back(p, held)
	eq(p.pack_tier, 1, "and your own pack comes back, not the range's")
	for k in TargetRange.HELD_KEYS:
		ok(held.has(k), "%s is held" % k)
