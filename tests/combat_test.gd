extends "res://tests/test_case.gd"
## Combat: melee, harvesting and its stamina rules, guns, bullets vs
## terrain, damage and death. Every kill here is the player's.

var sim: GameSim
var p: PlayerSim
var plot: Vector2


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = tile_centre(clear_plot(12))
	p.pos = plot
	p.intent.aim = plot + Vector2.RIGHT
	sim.give_test_kit(p)


func _hold(id: String) -> void:
	p.select_slot(p.hotbar_index(id))
	p.attack_cd = 0.0


func test_every_weapon_is_internally_consistent() -> void:
	for id in Config.WEAPONS:
		var w: Dictionary = Config.WEAPONS[id]
		eq(w.id, id)
		ok(w.dmg > 0 and w.cd > 0, id)
		if w.kind == "gun":
			ok(w.mag >= 1 and w.reload > 0 and Config.RES.has(w.ammo) and w.speed > 0 and w.life > 0, id)
		else:
			ok(w.range > 0 and w.arc > 0, id)
	# Tiers improve on damage per second.
	var dps := func(id: String) -> float: return Config.WEAPONS[id].dmg / Config.WEAPONS[id].cd
	ok(dps.call("pipe") > dps.call("fists") and dps.call("machete") > dps.call("pipe"))
	ok(dps.call("smg") > dps.call("pistol") and dps.call("carbine") > dps.call("smg"), "the bench tiers climb")
	ok(Config.WEAPONS.rifle.dmg > Config.WEAPONS.carbine.dmg * 2, "the rifle trades rate for the one-shot")
	# Every hand tool is a poor weapon.
	for id in ["axe", "pick", "knife", "scythe", "hammer"]:
		ok(dps.call(id) < dps.call("machete"), "%s must be worse than a machete" % id)


func test_a_pipe_kills_a_walker() -> void:
	_hold("pipe")
	var e := sim.enemies.spawn("walker", plot + Vector2(30, 0))
	p.intent.fire = true
	run(sim, 3.0)
	ok(e.dead, "walker at %.0f hp after three seconds of swinging" % e.hp)
	eq(sim.stats.kills, 1)
	ok(p.xp >= Config.ENEMIES.walker.xp, "the killer earns the xp")
	ok(events_of(sim, "hit").size() >= 3, "several hits landed")
	ok(p.stam > p.max_stam - 20.0, "fighting barely costs stamina: %.0f" % p.stam)


func test_the_arc_is_an_arc() -> void:
	_hold("pipe")
	var behind := sim.enemies.spawn("walker", plot + Vector2(-30, 0))
	behind.aggro = false
	p.intent.fire = true
	run(sim, 0.5)
	near(behind.hp, behind.max_hp, 1e-6, "a walker behind you is not in the swing")


func test_a_swing_does_not_reach_through_a_wall() -> void:
	# Collision holds two bodies 66px apart across a one-tile wall, and the
	# pipe's threshold is 73px, so distance alone would let the swing land.
	var pw := World.new()
	sim.world = pw
	var w: Dictionary = Config.WEAPONS.pipe
	sim.enemies.spawn("walker", plot + Vector2(66, 0))
	sim.enemies.rebuild_spatial()
	p.angle = 0.0
	eq(Combat.melee_targets(sim, p, w).size(), 1, "66px is inside the pipe's reach")
	var bi := int(plot.y / 32) * Config.WORLD_TILES + int(plot.x / 32) + 1
	pw.blocked[bi] = 1
	pw.tiles[bi] = Config.T.WALL
	eq(Combat.melee_targets(sim, p, w).size(), 0, "a wall between you takes the swing")
	# Knee-high things go the other way, exactly as they do for bullets.
	pw.tiles[bi] = Config.T.FENCE
	eq(Combat.melee_targets(sim, p, w).size(), 1, "a fence is swung over")


func test_fighting_is_never_refused_and_work_is() -> void:
	_hold("axe")
	p.winded = true
	p.stam = 0.0
	var e := sim.enemies.spawn("walker", plot + Vector2(30, 0))
	p.intent.fire = true
	run(sim, 0.6)
	ok(e.hp < e.max_hp, "winded, you can still hit what is in front of you")


func test_a_tree_is_six_hatchet_swings_and_a_bar_is_three_trees() -> void:
	# The gathering tier is priced in swings, measured before changed.
	var axe: Dictionary = Config.WEAPONS.axe
	var per_swing: float = axe.dmg * p.melee_mul * Combat.chop_multiplier(axe, p, Config.HARVEST.wood)
	var swings := ceili(470.0 / per_swing)
	eq(swings, 6, "a tree is %d hatchet swings at starting stats" % swings)
	var trees := p.max_stam / (swings * Combat.chop_stam_cost(p))
	ok(trees >= 2.5 and trees < 4.0, "a full bar is %.2f trees" % trees)
	var refill: float = Config.PLAYER.stam_chop_delay + p.max_stam / p.stam_regen
	ok(refill > 4.0 and refill < 12.0, "%.1fs to get back to full" % refill)
	var fireaxe: Dictionary = Config.WEAPONS.fireaxe
	var metal := ceili(470.0 / (fireaxe.dmg * p.melee_mul * Combat.chop_multiplier(fireaxe, p, Config.HARVEST.wood)))
	ok(metal < swings, "a Fire Axe fells in %d" % metal)


func test_felling_a_tree_frees_the_tile_and_pays_wood() -> void:
	# A private world: this test changes it.
	var w := World.new()
	sim.world = w
	var tree := {}
	for pr in w.props:
		if pr.kind == "tree" and w.danger_at_px(pr.x, pr.y) <= 2:
			var t := Vector2i(pr.tx - 2, pr.ty)
			if not w.is_blocked_tile(t.x, t.y) and not w.is_blocked_tile(t.x + 1, t.y):
				tree = pr
				break
	ok(not tree.is_empty(), "found a tree with open ground west of it")
	if tree.is_empty():
		return
	p.pos = Vector2(tree.x - 40, tree.y)
	p.intent.aim = Vector2(tree.x, tree.y)
	_hold("axe")
	p.intent.fire = true
	var ti: int = tree.ty * Config.WORLD_TILES + tree.tx
	ok(w.blocked[ti] == 1, "a tree blocks")
	# Six swings at 0.52s land by 2.6s; the chop delay then holds recovery.
	run(sim, 3.0)
	eq(w.blocked[ti], 0, "felled: the tile is open")
	ok(w.prop_at_tile(tree.tx, tree.ty).is_empty(), "and the prop is gone")
	ok(p.count_res("wood") >= 6, "wood +%d" % p.count_res("wood"))
	ok(p.stam < p.max_stam - 30.0, "and it cost real stamina: %.0f" % p.stam)
	ok(sim.world_version > 0, "the flow fields were told")
	ok(events_of(sim, "harvest").size() == 1)


func test_a_pipe_bounces_off_a_tree() -> void:
	var w := World.new()
	sim.world = w
	var tree := {}
	for pr in w.props:
		if pr.kind == "tree" and not w.is_blocked_tile(pr.tx - 2, pr.ty) and not w.is_blocked_tile(pr.tx - 1, pr.ty):
			tree = pr
			break
	p.pos = Vector2(tree.x - 40, tree.y)
	p.intent.aim = Vector2(tree.x, tree.y)
	_hold("pipe")
	p.intent.fire = true
	run(sim, 2.0)
	near(tree.hp, tree.max_hp, 1e-6, "no axe, no wood")
	ok(not events_of(sim, "notify").is_empty(), "and it says so")
	near(p.stam, p.max_stam, 1.0, "a swing that moves nothing costs nothing")


func test_refused_work_winds_you_and_the_pipe_never_is() -> void:
	var w := World.new()
	sim.world = w
	var tree := {}
	for pr in w.props:
		if pr.kind == "tree" and not w.is_blocked_tile(pr.tx - 2, pr.ty) and not w.is_blocked_tile(pr.tx - 1, pr.ty):
			tree = pr
			break
	p.pos = Vector2(tree.x - 40, tree.y)
	p.intent.aim = Vector2(tree.x, tree.y)
	_hold("axe")
	p.stam = 3.0
	p.intent.fire = true
	run(sim, 0.2)
	ok(p.winded, "turned down for work: winded")
	ok(not events_of(sim, "deny").is_empty())


func test_a_pistol_kills_a_walker_and_a_rifle_needs_one_round() -> void:
	_hold("pistol")
	var e := sim.enemies.spawn("walker", plot + Vector2(200, 0))
	p.intent.fire = true
	run(sim, 2.0)
	ok(e.dead, "walker at %.0f hp" % e.hp)
	ok(p.mag.pistol < 12, "rounds came out of the magazine: %d left" % p.mag.pistol)
	ok(sim.threat.value > 0.0, "gunfire raises Threat: %.1f" % sim.threat.value)

	_hold("rifle")
	p.intent.fire = false
	var f := sim.enemies.spawn("walker", plot + Vector2(300, 0))
	run(sim, 0.1)
	p.intent.fire = true
	p.intent.fire_pressed = true
	run(sim, 1.0)
	ok(f.dead, "one rifle round drops a walker (hp %.0f)" % f.hp)


func test_one_bullet_does_what_several_arrows_do() -> void:
	var walker: float = Config.ENEMIES.walker.hp
	var shots := func(id: String) -> int: return ceili(walker / Config.WEAPONS[id].dmg)
	ok(shots.call("bow") >= 3, "a walker takes at least three arrows")
	eq(shots.call("rifle"), 1, "a rifle round drops a walker outright")
	ok(shots.call("bow") > shots.call("pistol"))
	var dps := func(id: String) -> float: return Config.WEAPONS[id].dmg / Config.WEAPONS[id].cd
	ok(dps.call("bow") < dps.call("pistol") * 0.4, "a bow is much slower as well as weaker")


func test_the_bow_keeps_drawing_while_held() -> void:
	_hold("bow")
	var e := sim.enemies.spawn("brute", plot + Vector2(150, 0))
	e.aggro = false
	p.intent.fire = true
	run(sim, 6.0)
	var shots := events_of(sim, "shot").size()
	ok(shots >= 4, "%d arrows loosed in six seconds of holding the button" % shots)
	ok(p.count_res("arrow") < 29, "arrows came out of the quiver")
	ok(e.hp < e.max_hp - 40.0, "and hit: brute at %.0f" % e.hp)


func test_one_click_one_magazine() -> void:
	_hold("pistol")
	p.mag.pistol = 0
	p.intent.fire = true               # held, never freshly pressed
	run(sim, 2.0)
	eq(p.mag.pistol, 0, "holding the trigger on an empty gun does not reload")
	p.intent.fire_pressed = true
	run(sim, 1.0 / 60.0)
	ok(not p.reloading.is_empty(), "a fresh click starts the reload")
	p.intent.fire = false
	run(sim, 1.5)
	eq(p.mag.pistol, 12, "and the magazine fills")


func test_the_shotgun_loads_a_shell_at_a_time_and_fires_a_spread() -> void:
	_hold("shotgun")
	p.mag.shotgun = 0
	p.intent.reload = true
	run(sim, 1.0 / 60.0)
	run(sim, 0.6)
	eq(p.mag.shotgun, 1, "one shell after one reload step")
	run(sim, 3.0)
	eq(p.mag.shotgun, 6, "full after a few")
	p.intent.fire = true
	p.intent.fire_pressed = true
	run(sim, 1.0 / 60.0)
	eq(events_of(sim, "shot").size(), 8, "eight pellets, one shot")
	eq(events_of(sim, "muzzle").size(), 1)


func test_bullets_stop_at_walls_and_fly_over_water() -> void:
	var w := world()
	# The river at (67, 20): shoot across it. A wall: the camp shack corner.
	var river := tile_centre(Vector2i(67, 20))
	ok(w.tile(67, 20) == Config.T.WATER)
	ok(not w.bullet_blocks_px(river.x, river.y), "water does not stop a round")
	ok(w.is_blocked_px(river.x, river.y), "but it stops a foot")
	var wall := tile_centre(Vector2i(150, 150))
	ok(w.bullet_blocks_px(wall.x, wall.y), "a wall stops both")
	# And a fence.
	var fence := Vector2.INF
	for i in range(Config.WORLD_TILES * Config.WORLD_TILES):
		if w.tiles[i] == Config.T.FENCE:
			fence = tile_centre(Vector2i(i % Config.WORLD_TILES, i / Config.WORLD_TILES))
			break
	ok(fence != Vector2.INF and not w.bullet_blocks_px(fence.x, fence.y) and w.is_blocked_px(fence.x, fence.y), "a fence is knee high")

	# In the sim: a walker behind a wall tile takes nothing.
	var e := sim.enemies.spawn("walker", plot + Vector2(300, 0))
	e.aggro = false
	_hold("rifle")
	# Stand the player such that the shot crosses a wall: build one by
	# blocking a tile in a private world copy.
	var pw := World.new()
	sim.world = pw
	var bi := int(plot.y / 32) * Config.WORLD_TILES + int(plot.x / 32) + 4
	pw.blocked[bi] = 1
	pw.tiles[bi] = Config.T.WALL
	p.intent.fire = true
	p.intent.fire_pressed = true
	run(sim, 1.0)
	near(e.hp, e.max_hp, 1e-6, "the wall took every round")
	ok(not events_of(sim, "bullet_wall").is_empty())


func test_pierce_carries_through() -> void:
	_hold("rifle")
	var a := sim.enemies.spawn("walker", plot + Vector2(120, 0))
	var b := sim.enemies.spawn("walker", plot + Vector2(180, 0))
	var c := sim.enemies.spawn("walker", plot + Vector2(240, 0))
	for e in [a, b, c]:
		e.aggro = false
	p.intent.fire = true
	p.intent.fire_pressed = true
	run(sim, 1.0 / 60.0)
	run(sim, 0.5)
	ok(a.dead and b.dead, "the first two go down")
	ok(c.hp < c.max_hp, "the third is hit for less (%.0f)" % (c.max_hp - c.hp))


func test_knockback_respects_resistance() -> void:
	var w := sim.enemies.spawn("walker", plot + Vector2(100, 0))
	var b := sim.enemies.spawn("brute", plot + Vector2(100, 200))
	Damage.damage_enemy(sim, w, 1.0, plot, 200.0)
	Damage.damage_enemy(sim, b, 1.0, plot + Vector2(0, 200), 200.0)
	ok(w.vel.length() > b.vel.length() * 3.0, "walker %.0f vs brute %.0f" % [w.vel.length(), b.vel.length()])


func test_being_hit_hurts_once_then_grants_a_moment() -> void:
	Damage.damage_player(sim, p, 20.0, plot + Vector2(20, 0))
	near(p.hp, p.max_hp - 20.0, 1e-6)
	Damage.damage_player(sim, p, 20.0, plot + Vector2(20, 0))
	near(p.hp, p.max_hp - 20.0, 1e-6, "invulnerable for a moment after a hit")
	run(sim, 0.5)
	Damage.damage_player(sim, p, 20.0, plot + Vector2(20, 0))
	near(p.hp, p.max_hp - 40.0, 1e-6)


func test_death_and_respawn_on_safe_ground() -> void:
	var here := p.pos
	Damage.damage_player(sim, p, 1000.0, plot + Vector2(20, 0))
	ok(p.dead)
	eq(sim.stats.deaths, 1)
	run(sim, Config.PLAYER.respawn_time + 0.1)
	ok(not p.dead, "back")
	near(p.hp, p.max_hp, 1e-6)
	eq(sim.world.danger_at_px(p.pos.x, p.pos.y), 1, "on tier-1 ground")
	ok(not sim.world.is_blocked_px(p.pos.x, p.pos.y))
	ok(p.invuln > 0.0, "with a grace period")


func test_a_bandage_heals_over_time_and_roots_you() -> void:
	# A small wound takes the bandage; a medkit is saved for a big one.
	p.hp = 80.0
	p.intent.use = true
	p.intent.mx = 1.0
	run(sim, 1.0 / 60.0)
	ok(not p.using.is_empty() and p.using.id == "bandage", "patching up with a bandage")
	run(sim, 0.5)
	# One frame of momentum before the channel takes hold, then nothing.
	ok(p.pos.distance_to(plot) < 5.0, "rooted while it happens (moved %.1f)" % p.pos.distance_to(plot))
	run(sim, 0.6)
	near(p.hp, 108.0, 1e-6, "bandage +28")
	eq(p.count_res("bandage"), 3)
	ok(p.using.is_empty())
	p.hp = 30.0
	p.intent.use = true
	run(sim, 1.0 / 60.0)
	eq(p.using.id, "medkit", "a big wound is worth the medkit")


# ------------------------------------------------------------------- crit --

func test_crit_comes_off_the_weapon_you_are_holding() -> void:
	# What this replaced: `crit_chance + 0.06` at 1.9x for every melee weapon
	# in the game and `crit_chance` at 1.8x for every gun, so a Stone Knife
	# and a Sledgehammer critted identically.
	var knife: Dictionary = Config.WEAPONS.knife
	var sledge: Dictionary = Config.WEAPONS.sledge
	near(Combat.crit_chance(p, knife), p.crit_chance + knife.crit, 1e-9)
	near(Combat.crit_mul(p, sledge), sledge.crit_mul + p.crit_dmg, 1e-9)
	ok(Combat.crit_chance(p, knife) > Combat.crit_chance(p, sledge), "a knife finds the gap more often")
	ok(Combat.crit_mul(p, sledge) > Combat.crit_mul(p, knife), "and the sledgehammer costs more when it does")
	ok(Combat.crit_chance(p, Config.WEAPONS.rifle) > Combat.crit_chance(p, Config.WEAPONS.shotgun),
		"a rifle is aimed and a shotgun is pointed")
	near(Combat.crit_chance(p, Config.WEAPONS.fists), p.crit_chance, 1e-9, "fists add nothing")


func test_every_weapon_says_what_a_critical_is_worth() -> void:
	for id in Config.WEAPONS:
		var w: Dictionary = Config.WEAPONS[id]
		ok(w.has("crit") and w.has("crit_mul"), "%s does not say" % id)
		ok(float(w.crit) >= 0.0 and float(w.crit) < 0.4, "%s crit chance is out of range" % id)
		gt(float(w.crit_mul), 1.0, "%s criticals must be worth having" % id)


func test_gloves_and_chemistry_move_it_and_the_cap_holds() -> void:
	var w: Dictionary = Config.WEAPONS.machete
	var bare := Combat.crit_chance(p, w)
	p.equip["hands"] = "tacGloves"
	Equipment.recompute_stats(p)
	near(Combat.crit_chance(p, w), bare + Config.GEAR.tacGloves.crit, 1e-9, "the hands are the slot that helps")

	var gloved := Combat.crit_chance(p, w)
	var mul := Combat.crit_mul(p, w)
	p.effects["surge"] = 60.0
	Equipment.recompute_stats(p)
	gt(Combat.crit_chance(p, w), gloved, "a Surge sharpens you")
	gt(Combat.crit_mul(p, w), mul, "and makes a critical cost more")

	p.effects.erase("surge")
	p.effects["drunk"] = 60.0
	Equipment.recompute_stats(p)
	ok(Combat.crit_chance(p, w) < gloved, "and you could not hit a wall")

	# The cap is headroom, not a wall a real build hits: a maxed Luck ladder
	# stays well under it, and only something absurd is clamped.
	p.effects.clear()
	p.attrs["lck"] = Config.ATTR_MAX
	p.perks["luckyStrike"] = 3
	Equipment.recompute_stats(p)
	ok(Combat.crit_chance(p, w) < Config.MAX_CRIT, "the best build in the game is under the cap")
	near(Combat.crit_chance(p, {"crit": 5.0}), Config.MAX_CRIT, 1e-9, "and nothing gets past it")
