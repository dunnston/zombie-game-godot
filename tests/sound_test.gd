extends "res://tests/test_case.gd"
## Noise: heard inside its radius, gives a destination, never aggro.

var sim: GameSim


func before_each() -> void:
	sim = new_sim()


func after_each() -> void:
	# A static that leaked true would make every later file emit noise events.
	Sound.debug = false


func _horde(base: Vector2, offsets: Array) -> Array[EnemySim]:
	var out: Array[EnemySim] = []
	for o: Vector2 in offsets:
		out.append(sim.enemies.spawn("walker", base + o))
	return out


func test_a_sound_is_heard_inside_its_radius_and_nowhere_else() -> void:
	var base := Vector2(5000, 5000)
	var horde := _horde(base, [Vector2.ZERO, Vector2(100, 0), Vector2(400, 0), Vector2(900, 0)])
	var heard := Sound.make_noise(sim, base.x, base.y, 500.0)
	eq(heard, 3, "three inside 500px, one outside")
	ok(horde[0].has_noise and horde[0].noise_at == base, "the destination is the point of the whole thing")
	ok(horde[0].alert_t > 0.0, "and a window in which to act on it")
	ok(not horde[3].has_noise, "the one that heard nothing has nowhere to go")
	eq(horde[3].alert_t, 0.0)


func test_a_sound_makes_them_investigate_not_hunt() -> void:
	# The whole mechanic, and it shipped broken twice in the prototype: a
	# noise that set aggro sent zombies at the nearest player, not the bang.
	var base := Vector2(5000, 5000)
	var e := _horde(base, [Vector2(100, 0)])[0]
	Sound.make_noise(sim, base.x, base.y, 500.0)
	ok(not e.aggro, "a noise must not aggro — it must give a destination")
	# And it must not clear an existing hunt either.
	e.aggro = true
	Sound.make_noise(sim, base.x, base.y, 500.0)
	ok(e.aggro, "a noise never cancels a hunt in progress")


func test_a_noise_at_the_origin_is_still_a_noise() -> void:
	_horde(Vector2(10, 10), [Vector2.ZERO])
	Sound.make_noise(sim, 0.0, 200.0, 500.0)
	ok(sim.enemies.list[0].has_noise, "x = 0 is a real corner of the map")
	eq(sim.enemies.list[0].noise_at, Vector2(0, 200))


func test_being_quiet_makes_you_quieter_whatever_the_source() -> void:
	var base := Vector2(5000, 5000)
	_horde(base, [Vector2(300, 0)])
	var p := sim.players[0]
	p.noise_mul = 1.0
	eq(Sound.make_noise(sim, base.x, base.y, 400.0, p), 1)
	p.noise_mul = 0.5
	eq(Sound.make_noise(sim, base.x, base.y, 400.0, p), 0, "half as loud does not reach as far")


func test_the_noise_table_ranks_the_way_the_trade_off_needs() -> void:
	var N := Config.NOISE
	var W := Config.WEAPONS
	ok(Sound.weapon_radius(W.axe) * N.chop_mul < N.build,
		"an axe is quieter than a hammer")
	ok(N.build < N.generator, "a running generator carries further")
	ok(N.generator < N.turret, "a turret is the loudest thing you own")
	ok(W.pistol.noise > N.build)
	ok(W.rifle.noise > W.smg.noise, "a rifle is louder than an SMG")
	for id in W:
		if W[id].kind == "gun":
			ok(W[id].noise > 0.0, "%s is a firearm and must make a sound" % id)


func test_a_bow_is_quiet_and_a_gun_is_not() -> void:
	var W := Config.WEAPONS
	var bow: Dictionary = W.bow
	eq(bow.kind, "gun", "the bow rides the whole firearm path")
	eq(bow.ammo, "arrow")
	ok(Config.RES.has("arrow"))
	for id in W:
		var w: Dictionary = W[id]
		if w.kind != "gun" or w.get("bow", false):
			continue
		ok(bow.noise * 3.0 < w.noise, "a bow (%d) must be far quieter than a %s (%d)" % [bow.noise, id, w.noise])
		ok(bow.threat < w.threat, "and draw less Threat than a %s" % id)


func test_they_walk_toward_the_bang() -> void:
	# Measured with a control: "moved toward the noise" means nothing until
	# you know how far they wander on their own.
	var plot := tile_centre(clear_plot(14))
	var bang := plot + Vector2(-380, 0)
	var e := sim.enemies.spawn("walker", plot)
	# Nobody to sense, but close enough not to be culled.
	sim.players[0].pos = plot + Vector2(0, 1500)
	sim.players[0].intent.aim = sim.players[0].pos + Vector2.RIGHT
	var before := e.pos.distance_to(bang)
	Sound.make_noise(sim, bang.x, bang.y, 500.0)
	run(sim, 4.0)
	var closed := before - e.pos.distance_to(bang)

	var control := new_sim()
	control.players[0].pos = plot + Vector2(0, 1500)
	control.players[0].intent.aim = control.players[0].pos + Vector2.RIGHT
	var c := control.enemies.spawn("walker", plot)
	run(control, 4.0)
	var drifted := before - c.pos.distance_to(bang)
	print("noise: closed %.0f px toward the bang in 4s; control drifted %.0f" % [closed, drifted])
	ok(closed > 80.0, "walked %.0f px toward the noise" % closed)
	ok(closed > drifted + 40.0, "and clearly more than the control (%.0f)" % drifted)


# ----------------------------------------------------------- the weapon --

func test_every_weapon_can_be_heard() -> void:
	# The trap this guards is a new row in the content editor with no noise
	# of its own. Silent-by-accident is indistinguishable from a stealth
	# weapon until a horde walks past a running chainsaw.
	for id in Config.WEAPONS:
		var w: Dictionary = Config.WEAPONS[id]
		gt(Sound.weapon_radius(w), 0.0, "%s must carry a noise" % id)
	eq(Sound.weapon_radius({}), Config.NOISE.melee,
		"and a row with none falls back rather than going silent")


func test_melee_is_the_quiet_way_and_the_chainsaw_is_the_price_of_the_shortcut() -> void:
	var W := Config.WEAPONS
	var loudest_melee := 0.0
	var loudest_id := ""
	var softest_gun := INF
	for id in W:
		var w: Dictionary = W[id]
		if w.kind == "melee":
			if id != "chainsaw" and w.noise > loudest_melee:
				loudest_melee = w.noise
				loudest_id = id
		elif not w.get("bow", false):
			softest_gun = minf(softest_gun, w.noise)
	ok(loudest_melee < softest_gun,
		"the loudest melee (%s, %d) must still beat the softest firearm (%d)"
			% [loudest_id, loudest_melee, softest_gun])
	ok(W.chainsaw.noise > softest_gun,
		"except the chainsaw, which is a motor and is meant to cost you")
	ok(W.fists.noise < W.sledge.noise, "and mass is what makes the noise")


func test_landing_a_swing_is_what_they_hear() -> void:
	# The hole this fills: melee_attack emitted no noise at all, so a
	# sledgehammer to the head was silent and stealth was free.
	var plot := tile_centre(clear_plot(14))
	var p := sim.players[0]
	p.pos = plot
	p.angle = 0.0
	var target := sim.enemies.spawn("walker", plot + Vector2(30, 0))
	p.intent.aim = target.pos
	# The tick is what puts it in the spatial hash melee_targets searches;
	# without it the swing finds nothing and this tests the whiff instead.
	sim.tick(1.0 / 60.0)
	var w: Dictionary = Config.WEAPONS.sledge
	# Well inside the sledge's radius, well outside the arc of the swing —
	# and spawned after the tick, so nothing it did on its own explains this.
	var listener := sim.enemies.spawn("walker", plot + Vector2(0, w.noise - 20.0))

	ok(Combat.melee_attack(sim, p, w), "the sledge swung")
	ok(listener.has_noise, "a hit that far away is still heard")
	eq(listener.noise_at, p.pos, "and the thing to walk at is the swinger")
	ok(not listener.aggro, "heard, not hunted — a noise never sets aggro")


func test_a_whiff_carries_less_than_a_hit() -> void:
	var plot := tile_centre(clear_plot(14))
	var p := sim.players[0]
	var w: Dictionary = Config.WEAPONS.sledge
	# Between the two radii: this one hears the hit and not the swish.
	var between: float = w.noise * ((Config.NOISE.whiff_mul + 1.0) * 0.5)
	ok(between > w.noise * Config.NOISE.whiff_mul and between < w.noise,
		"the listener sits between a whiff and a hit")

	p.pos = plot
	p.angle = 0.0
	p.intent.aim = plot + Vector2(100, 0)
	var far := sim.enemies.spawn("walker", plot + Vector2(0, between))
	ok(Combat.melee_attack(sim, p, w), "swung at nothing")
	ok(not far.has_noise, "a swing through air does not carry like a landed one")

	var near_by := sim.enemies.spawn("walker", plot + Vector2(0, w.noise * 0.2))
	ok(Combat.melee_attack(sim, p, w), "swung at nothing again")
	ok(near_by.has_noise, "but it is not silent either — whiffing can still draw")


func test_it_is_the_tool_that_is_loud_not_the_job() -> void:
	# A chainsaw and a stone axe felling the same tree used to wake exactly
	# the same zombies: chopping was one flat number. Pillar 6 — the better
	# tool should make the world worse. Both of these can fell a tree, which
	# is the point: same job, same tree, different price in attention.
	var quiet := _chop_heard("axe")
	var loud := _chop_heard("chainsaw")
	gt(loud, quiet, "a chainsaw (%d heard) pulls more than a stone axe (%d)"
		% [loud, quiet])
	eq(quiet, 0, "and the stone axe reaches nobody in that ring")


## Fells one tree with `id` and returns how many of a ring of eight, standing
## 150 to 570 px away, heard it.
func _chop_heard(id: String) -> int:
	var s := new_sim()
	var w := World.new()
	s.world = w
	var tree := {}
	for pr in w.props:
		if pr.kind == "tree" and w.danger_at_px(pr.x, pr.y) <= 2:
			tree = pr
			break
	if tree.is_empty():
		return -1
	var at := Vector2(tree.x, tree.y)
	var p := s.players[0]
	p.pos = at - Vector2(40, 0)
	p.angle = 0.0
	p.intent.aim = at
	var ring: Array[EnemySim] = []
	for step in 8:
		ring.append(s.enemies.spawn("walker", at + Vector2(0, 150.0 + step * 60.0)))
	var weapon: Dictionary = Config.WEAPONS[id]
	ok(Combat.chop_prop(s, p, weapon, weapon.dmg), "%s bit into the tree" % id)
	var heard := 0
	for e in ring:
		if e.has_noise:
			heard += 1
	return heard


func test_being_quiet_quietens_the_swing_too() -> void:
	# The chokepoint holding: one perk, every source, melee included.
	var plot := tile_centre(clear_plot(14))
	var p := sim.players[0]
	p.pos = plot
	p.angle = 0.0
	var target := sim.enemies.spawn("walker", plot + Vector2(30, 0))
	p.intent.aim = target.pos
	sim.tick(1.0 / 60.0)
	var w: Dictionary = Config.WEAPONS.sledge
	var listener := sim.enemies.spawn("walker", plot + Vector2(0, w.noise - 20.0))

	p.noise_mul = 0.5
	ok(Combat.melee_attack(sim, p, w), "the sledge swung")
	ok(not listener.has_noise, "half as loud does not reach as far, swinging too")


# ------------------------------------------------------------- the lens --

func test_the_lens_is_silent_until_somebody_opens_it() -> void:
	# Every positioned event is relayed to every guest reliably, and a noise
	# fires on every swing and every round of automatic fire. Off means off.
	var base := Vector2(5000, 5000)
	_horde(base, [Vector2.ZERO])
	Sound.make_noise(sim, base.x, base.y, 500.0, null, "gun")
	eq(events_of(sim, "noise").size(), 0, "nothing is emitted while it is off")

	Sound.debug = true
	Sound.make_noise(sim, base.x, base.y, 500.0, null, "gun")
	eq(events_of(sim, "noise").size(), 1, "and one event per noise while it is on")


func test_the_lens_reports_what_actually_reached() -> void:
	# The radius drawn has to be the one after noise_mul, not the one asked
	# for: a circle showing the unscaled reach would make a stealth perk look
	# broken while it was working.
	Sound.debug = true
	var base := Vector2(5000, 5000)
	_horde(base, [Vector2(100, 0), Vector2(300, 0)])
	var p := sim.players[0]
	p.noise_mul = 0.5
	var heard := Sound.make_noise(sim, base.x, base.y, 400.0, p, "gun")
	var ev: Dictionary = events_of(sim, "noise")[0]
	near(float(ev.r), 200.0, 1e-6, "the drawn radius is the scaled one")
	eq(int(ev.heard), heard, "and it says how many actually heard it")
	eq(Vector2(ev.x, ev.y), base, "centred on the noise, not on the player")


func test_a_hit_and_a_whiff_are_told_apart() -> void:
	# The whole point of the overlay: one swing at a zombie and one at air
	# must be distinguishable on screen, in both colour and size.
	Sound.debug = true
	var plot := tile_centre(clear_plot(14))
	var p := sim.players[0]
	p.pos = plot
	p.angle = 0.0
	var w: Dictionary = Config.WEAPONS.sledge

	p.intent.aim = plot + Vector2(100, 0)
	ok(Combat.melee_attack(sim, p, w), "swung at nothing")
	var miss: Dictionary = events_of(sim, "noise")[0]
	eq(String(miss.src), "whiff")

	var target := sim.enemies.spawn("walker", plot + Vector2(30, 0))
	p.intent.aim = target.pos
	sim.tick(1.0 / 60.0)
	sim.events.clear()
	ok(Combat.melee_attack(sim, p, w), "and then at something")
	var land: Dictionary = events_of(sim, "noise")[0]
	eq(String(land.src), "hit")
	gt(float(land.r), float(miss.r), "landing it draws the bigger circle")


func test_the_tool_reports_itself_as_work() -> void:
	Sound.debug = true
	var s := new_sim()
	var w := World.new()
	s.world = w
	var tree := {}
	for pr in w.props:
		if pr.kind == "tree" and w.danger_at_px(pr.x, pr.y) <= 2:
			tree = pr
			break
	ok(not tree.is_empty(), "found a tree")
	var p := s.players[0]
	p.pos = Vector2(tree.x - 40.0, tree.y)
	p.angle = 0.0
	p.intent.aim = Vector2(tree.x, tree.y)
	var axe: Dictionary = Config.WEAPONS.axe
	ok(Combat.chop_prop(s, p, axe, axe.dmg), "the axe bit in")
	var ev: Dictionary = events_of(s, "noise")[0]
	eq(String(ev.src), "work")
	near(float(ev.r), axe.noise * Config.NOISE.chop_mul, 1e-4)
	eq(Vector2(ev.x, ev.y), Vector2(tree.x, tree.y), "drawn on the tree, not the swinger")
