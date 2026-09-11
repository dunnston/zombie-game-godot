extends "res://tests/test_case.gd"
## Weapon levels (PR E; the owner's call of 2026-09-10): up to 6, each level
## more damage and more uses, at the bench that makes the weapon, and capped
## at 3 until the School's boss has let some Precision Parts out — the gate is
## the material, never a flag. Every assertion is on an outcome: what a hit
## does, what is left in the pack, where the level went.

var sim: GameSim
var p: PlayerSim
const BENCH := 2


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	p.pos = tile_centre(clear_plot(6))
	# Room to spare, so a weapon added later is never the thing that did not
	# fit — a full bag here once made a level-2 Machete silently not exist.
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0
	for id in ["wood", "stone", "sticks", "scrap", "cloth", "elec", "parts", "mil", "fuel", "fiber"]:
		p.bag.add(id, 200)
	for id in ["scrap", "parts"]:
		eq(p.bag.count(id), 200, "the stock is all there")


func _hold(id: String, lv := 1) -> Dictionary:
	p.hotbar.clear_all()
	p.hotbar.add(id, 1, -1, lv)
	p.slot = 0
	return Config.WEAPONS[id]


func _non_crit_shot_dmg() -> float:
	var w := _hold_keep()
	for i in range(40):
		sim.bullets.clear()
		p.mag[w.id] = 12
		Combat.fire_gun(sim, p, w)
		var b: Dictionary = sim.bullets[0]
		if not b.crit:
			return float(b.dmg)
	return -1.0


func _hold_keep() -> Dictionary:
	return Config.WEAPONS[p.hotbar.id_at(0)]


# ------------------------------------------------------------ what a level is --

func test_a_level_is_more_damage_on_the_shot() -> void:
	_hold("pistol")
	var base := _non_crit_shot_dmg()
	_hold("pistol", 4)
	var up := _non_crit_shot_dmg()
	gt(base, 0.0)
	near(up / base, Upgrade.dmg_mul(4), 1e-4, "level 4 hits %.0f%% harder" % ((Upgrade.dmg_mul(4) - 1.0) * 100.0))


func test_a_level_is_more_damage_on_the_swing() -> void:
	var dmg_at := func(lv: int) -> float:
		for i in range(40):
			_hold("pipe", lv)
			var e := sim.enemies.spawn("brute", p.pos + Vector2(30, 0), true)
			sim.enemies.rebuild_spatial()
			p.angle = 0.0
			sim.events.clear()
			Combat.melee_attack(sim, p, Config.WEAPONS.pipe)
			for ev in events_of(sim, "hit"):
				if not ev.crit:
					sim.enemies.list.erase(e)
					return float(ev.dmg)
			sim.enemies.list.erase(e)
		return -1.0
	var one: float = dmg_at.call(1)
	var three: float = dmg_at.call(3)
	gt(one, 0.0)
	near(three / one, Upgrade.dmg_mul(3), 1e-4)


func test_a_level_is_more_uses() -> void:
	_hold("machete", 4)
	eq(Wear.max_at(p.hotbar, 0), roundi(Wear.max_of("machete") * Upgrade.dur_mul(4)))
	eq(Wear.left(p.hotbar, 0), Wear.max_at(p.hotbar, 0), "an unset condition is whole for its level")


# ------------------------------------------------------------ the bench --

func test_upgrading_costs_a_share_of_the_recipe_and_makes_it_whole() -> void:
	_hold("machete")
	p.hotbar.set_wear_at(0, Wear.max_of("machete") / 2)
	var cost := Upgrade.cost(p.hotbar, 0)
	ok(not cost.is_empty())
	ok(not cost.has("precision"), "levels 2 and 3 are ordinary materials")
	var before := {}
	for id in cost:
		before[id] = p.bag.count(id)
	ok(Upgrade.upgrade(sim, p, "hotbar", 0, BENCH))
	eq(Upgrade.level(p.hotbar, 0), 2)
	eq(Wear.left(p.hotbar, 0), Wear.max_at(p.hotbar, 0), "a new level comes back whole")
	for id in cost:
		eq(p.bag.count(id), int(before[id]) - int(cost[id]), "paid %d %s" % [cost[id], id])


func test_the_ceiling_is_three_until_there_are_precision_parts() -> void:
	_hold("machete", 3)
	var st := Upgrade.status(sim, p, "hotbar", 0, BENCH)
	ok(not st.ok)
	ok(String(st.reason).contains("Precision Parts"), st.reason)
	ok(not Upgrade.upgrade(sim, p, "hotbar", 0, BENCH))
	eq(Upgrade.level(p.hotbar, 0), 3, "three, and no further")
	p.bag.add("precision", int(Config.UPGRADE.precision[4]))
	ok(Upgrade.upgrade(sim, p, "hotbar", 0, BENCH), "with the School's parts, four")
	eq(Upgrade.level(p.hotbar, 0), 4)
	eq(p.bag.count("precision"), 0, "and they went into it")


func test_it_goes_no_further_than_six() -> void:
	_hold("machete", 6)
	eq(String(Upgrade.status(sim, p, "hotbar", 0, BENCH).reason), "As good as it gets")


func test_upgraded_at_the_bench_that_makes_it() -> void:
	_hold("machete")
	var r := Wear.recipe_for("machete")
	gt(int(r.bench), 0, "a Machete is bench work")
	var st := Upgrade.status(sim, p, "hotbar", 0, 0)
	ok(not st.ok, "not by hand: %s" % st.reason)
	eq(String(st.reason), Crafting.bench_reason(sim, p, r, 0), "the recipe's own gate, the one mending uses")
	ok(Upgrade.status(sim, p, "hotbar", 0, BENCH).ok)


func test_a_weapon_nothing_makes_is_upgraded_nowhere() -> void:
	_hold("varsityBat")
	eq(String(Upgrade.status(sim, p, "hotbar", 0, BENCH).reason), "Nothing here can upgrade it")
	for row in Upgrade.upgradeable_carried(p):
		ne(String(row.id), "varsityBat", "and it is not offered")


# ------------------------------------------------------- where the level goes --

func test_the_level_goes_wherever_the_weapon_goes() -> void:
	_hold("machete", 5)
	p.hotbar.set_wear_at(0, 100)
	# Onto the ground and back.
	ok(Equipment.drop_stack(sim, p, "hotbar", 0))
	var pile: Dictionary = sim.pickups.back()
	eq(int(pile.get("lv", 0)), 5, "the pile is a level-5 Machete")
	pile.inert_for = null
	pile.pos = p.pos
	run(sim, 0.3)
	var got := -1
	for cont: Slots in [p.hotbar, p.bag]:
		for i in range(cont.size()):
			if cont.id_at(i) == "machete":
				got = Upgrade.level(cont, i)
	eq(got, 5, "and it is still one when you pick it up")
	# Through a save's record.
	var rec := p.hotbar.to_record() + p.bag.to_record()
	var s := Slots.new(60)
	s.from_record(p.bag.to_record())
	var t := Slots.new(6)
	t.from_record(p.hotbar.to_record())
	var after := maxi(Upgrade.level(s, _index(s, "machete")), Upgrade.level(t, _index(t, "machete")))
	eq(after, 5, "through the record a save and the wire both use")
	ok(not rec.is_empty())


func test_dying_can_never_level_anything_up() -> void:
	p.hotbar.clear_all()
	p.hotbar.add("machete", 1, -1, 5)
	p.bag.add("machete", 1, -1, 2)
	var pack := Loot.drop_backpack(sim, p)
	eq(int(pack.lv.machete), 2, "two Machetes come back as the lower of the two")


static func _index(s: Slots, id: String) -> int:
	for i in range(s.size()):
		if s.id_at(i) == id:
			return i
	return 0


# ---------------------------------------------------- the School and the boss --

func test_precision_parts_only_come_out_of_the_school() -> void:
	# The whole of the gate: nothing in the town has any, so the only way to
	# level 4 is through the School's haul, which only leaves past the boss.
	var w := world()
	for c in w.containers:
		for e in Config.LOOT.get(String(c.table), []):
			ne(String(e.id), "precision", "%s in the town has Precision Parts" % c.kind)
	var coach: Dictionary = Config.ENEMIES[String(Config.INSTANCES.school.boss)]
	var always := false
	for e in Config.LOOT[String(coach.loot_table)]:
		if String(e.id) == "precision" and int(e.w) >= 100:
			always = true
	ok(always, "and the boss always has some")


func test_the_boss_drops_are_chances_each_rolled_on_its_own() -> void:
	var coach_type := String(Config.INSTANCES.school.boss)
	var table: Array = Config.LOOT[String(Config.ENEMIES[coach_type].loot_table)]
	var odds := {}
	for e in table:
		odds[String(e.id)] = float(e.w)
	var seen := {}
	var n := 400
	for i in range(n):
		sim.pickups.clear()
		var e := sim.enemies.spawn(coach_type, p.pos, false)
		Loot._roll_enemy_drop(sim, e)
		var here := {}
		for it in sim.pickups:
			here[Loot.pickup_entry_id(it)] = true
		for id in here:
			seen[id] = int(seen.get(id, 0)) + 1
		sim.enemies.list.erase(e)
	eq(int(seen.get("precision", 0)), n, "the parts every time")
	var bat := float(seen.get("weapon:varsityBat", 0)) / n * 100.0
	ok(absf(bat - float(odds["weapon:varsityBat"])) < 8.0, "the bat about %d%% of the time: %.1f%%" % [odds["weapon:varsityBat"], bat])
	var gun := float(seen.get("weapon:sixShooter", 0)) / n * 100.0
	ok(absf(gun - float(odds["weapon:sixShooter"])) < 7.0, "the revolver about %d%% of the time: %.1f%%" % [odds["weapon:sixShooter"], gun])
