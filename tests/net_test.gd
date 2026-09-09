extends TestCase
## Co-op over a loopback: a host session and a guest session joined by two
## in-memory queues, stepped in lockstep. Everything the wire promises is
## asserted on outcomes — where the players ended up, what is in the pack —
## never on which message was sent.

const DT := 1.0 / 60.0

## One world for every guest mirror in this file: generating one per join is
## a third of a second, and a mirror only reads it.
static var _guest_world: World


func before_each() -> void:
	if _guest_world == null:
		_guest_world = World.new()
	NetGuest.reuse_world = _guest_world


func after_each() -> void:
	NetGuest.reuse_world = null


## A hosted game with one guest connected through a loopback pair. Returns
## {host, guest, sim, hp (host's player), gp (guest's player on the host)}.
func _table(pw := "", loss := 0.0, reorder := 0.0, identity := "guest-a", name_ := "Bex") -> Dictionary:
	var sim := TestCase.new_sim()
	var host := NetHost.new(sim, "Ryan", NetProtocol.hash_password(pw))
	var ends: Array = NetLink.Loopback.pair(loss, reorder)
	host.attach(ends[0])
	var guest := NetGuest.new(ends[1], identity, name_, NetProtocol.hash_password(pw))
	var t := {"host": host, "guest": guest, "sim": sim, "hp": sim.players[0], "gp": null}
	_pump(t, 0.1)
	t.gp = sim.player_by_identity(identity)
	return t


## Steps both ends at 60Hz the way the scene does: the guest sends and
## predicts, the host reads, ticks, snapshots, relays, and the frame's events
## are cleared.
func _pump(t: Dictionary, seconds: float, idle := false) -> void:
	for i in range(int(round(seconds / DT))):
		_step(t, idle)


func _step(t: Dictionary, idle := false) -> void:
	var guest: NetGuest = t.guest
	var host: NetHost = t.host
	guest.poll()
	guest.tick(DT, idle)
	host.poll()
	host.sim.tick(DT)
	host.after_tick(DT)
	host.sim.events.clear()
	host.on_events_cleared()


func _guest_events(t: Dictionary, kind: String) -> Array:
	var out := []
	for ev in (t.guest as NetGuest).sim.events:
		if ev.t == kind:
			out.append(ev)
	return out


# ---------------------------------------------------------------- intents --

func test_intent_survives_the_wire() -> void:
	var it := Intent.new()
	it.mx = -1.0
	it.my = 0.5
	it.aim = Vector2(1234.4, 567.6)
	it.sprint = true
	it.fire = true
	it.fire_pressed = true
	it.interact = true
	it.interact_held = true
	it.light = true
	it.slot = 3
	it.wheel = -1
	it.build_action = "place"
	it.build_type = "woodWall"
	it.build_tile = Vector2i(150, 151)
	var back := NetProtocol.unpack_intent(NetProtocol.decode(NetProtocol.encode(NetProtocol.msg_intent(7, it))).i, Intent.new())
	eq(back.mx, -1.0)
	eq(back.my, 0.5)
	eq(back.aim, Vector2(1234, 568))
	ok(back.sprint and back.fire and back.fire_pressed and back.interact and back.interact_held and back.light)
	ok(not back.sneak and not back.reload and not back.use)
	eq(back.slot, 3)
	eq(back.wheel, -1)
	eq(back.build_action, "place")
	eq(back.build_type, "woodWall")
	eq(back.build_tile, Vector2i(150, 151))


func test_merge_keeps_an_edge_until_a_step_sees_it() -> void:
	var it := Intent.new()
	var pressed := Intent.new()
	pressed.fire_pressed = true
	pressed.slot = 2
	pressed.mx = 1.0
	NetProtocol.merge_intent(it, NetProtocol.pack_intent(pressed))
	var released := Intent.new()
	released.mx = 0.0
	NetProtocol.merge_intent(it, NetProtocol.pack_intent(released))
	ok(it.fire_pressed, "the press survived a later packet without it")
	eq(it.slot, 2)
	eq(it.mx, 0.0, "held state is the newest packet's")
	# A late packet: only its edges are taken, never its held state.
	var late := Intent.new()
	late.mx = 1.0
	late.reload = true
	NetProtocol.merge_late_intent(it, NetProtocol.pack_intent(late))
	ok(it.reload)
	eq(it.mx, 0.0)


## The generalisation of the test above, and the one that would have caught
## the bug it was written for: `suppress` was packed and sent, and then both
## merges dropped it, so a guest's brain matter did nothing while solo worked
## (Codex review, PR #20). Every edge, every leg of the journey, so the next
## one added is covered before it is written.
func test_every_edge_survives_packing_and_both_merges() -> void:
	for field in Intent.EDGES:
		var pressed := Intent.new()
		pressed.set(field, true)
		ok(NetProtocol.has_edges(pressed), "%s does not count as an edge" % field)

		# Packed and unpacked: it arrives.
		var back := NetProtocol.unpack_intent(NetProtocol.pack_intent(pressed), Intent.new())
		ok(back.get(field), "%s did not survive the wire" % field)
		# And with_edges false is the STATE packet, which carries none of them.
		var held := NetProtocol.unpack_intent(NetProtocol.pack_intent(pressed, false), Intent.new())
		ok(not held.get(field), "%s rode a STATE packet that is supposed to be edge-free" % field)

		# The host's fresh merge: an edge already standing outlives a packet
		# that does not carry it.
		var it := Intent.new()
		NetProtocol.merge_intent(it, NetProtocol.pack_intent(pressed))
		ok(it.get(field), "merge_intent lost %s on the way in" % field)
		NetProtocol.merge_intent(it, NetProtocol.pack_intent(Intent.new()))
		ok(it.get(field), "merge_intent dropped %s before a step could see it" % field)

		# And the reliable path, which is the one a guest's press actually
		# takes: `NetGuest` sends edges as their own message.
		var late := Intent.new()
		NetProtocol.merge_late_intent(late, NetProtocol.pack_intent(pressed))
		ok(late.get(field), "merge_late_intent dropped %s — a guest pressing it does nothing" % field)

		# Nothing else came along for the ride.
		for other in Intent.EDGES:
			if other != field:
				ok(not late.get(other), "%s arrived when only %s was pressed" % [other, field])


func test_clearing_edges_clears_all_of_them() -> void:
	var it := Intent.new()
	for field in Intent.EDGES:
		it.set(field, true)
	it.slot = 3
	it.wheel = 1
	it.build_action = "place"
	it.clear_edges()
	for field in Intent.EDGES:
		ok(not it.get(field), "%s survived clear_edges — it would fire twice" % field)
	eq(it.slot, -1)
	eq(it.wheel, 0)
	eq(it.build_action, "")


func test_password_is_hashed_and_a_blank_one_is_no_password() -> void:
	eq(NetProtocol.hash_password(""), "")
	eq(NetProtocol.hash_password("  "), "")
	ne(NetProtocol.hash_password("hunter2"), "hunter2")
	eq(NetProtocol.hash_password("hunter2"), NetProtocol.hash_password("hunter2"))
	var hello := NetProtocol.msg_hello("id", "Bex", NetProtocol.hash_password("wrong"))
	eq(NetProtocol.join_refusal(hello, NetProtocol.hash_password("hunter2")), "wrong password")
	eq(NetProtocol.join_refusal(hello, ""), "")
	eq(NetProtocol.join_refusal({"t": "hello"}, ""), NetProtocol.OUT_OF_DATE, "a hello with no numbers is refused")
	var stale := NetProtocol.msg_hello("id", "Bex", "")
	stale.sv = SaveGame.VERSION - 1
	eq(NetProtocol.join_refusal(stale, ""), NetProtocol.OUT_OF_DATE)


# ---------------------------------------------------------------- joining --

func test_a_guest_joins_through_the_save_path_and_gets_a_seat() -> void:
	var sim := TestCase.new_sim()
	var hp: PlayerSim = sim.players[0]
	hp.bag.add("wood", 100)
	var tx := floori(hp.pos.x / Config.TILE) + 2
	var ty := floori(hp.pos.y / Config.TILE)
	var wall := sim.structs.place(sim, "woodWall", tx, ty, hp)
	ok(not wall.is_empty(), "the host built a wall before anyone arrived")
	var host := NetHost.new(sim, "Ryan")
	var ends: Array = NetLink.Loopback.pair()
	host.attach(ends[0])
	var guest := NetGuest.new(ends[1], "guest-a", "Bex")
	var t := {"host": host, "guest": guest, "sim": sim}
	_pump(t, 0.1)
	ok(guest.joined(), "joined: %s %s" % [guest.status, guest.reason])
	eq(guest.me.seat, 1)
	eq(guest.me.display_name, "Bex")
	eq(guest.host_name, "Ryan")
	eq(guest.sim.world.fingerprint(), sim.world.fingerprint())
	ok(guest.sim.structs.at_tile(tx, ty).get("type", "") == "woodWall", "the wall came with the world")
	eq(guest.sim.players.size(), 2)
	eq(guest.sim.players[0].display_name, "Ryan", "the roster names the host")
	ok(guest.me.hotbar.count("pipe") > 0, "the guest's own pack arrived")
	eq(host.connected_count(), 1)
	var gp := sim.player_by_identity("guest-a")
	ne(gp, null)
	eq(gp.seat, 1)
	ok(not gp.away)


func test_refusals_say_why() -> void:
	# Wrong password.
	var t := _table("hunter2")
	ok(t.guest.joined())
	var sim: GameSim = t.sim
	var ends: Array = NetLink.Loopback.pair()
	(t.host as NetHost).attach(ends[0])
	var bad := NetGuest.new(ends[1], "guest-b", "Cole", NetProtocol.hash_password("nope"))
	var t2 := {"host": t.host, "guest": bad, "sim": sim}
	_pump(t2, 0.1)
	eq(bad.status, "rejected")
	eq(bad.reason, "wrong password")
	eq(sim.players.size(), 2, "a refused guest never got a seat")
	# Already connected from another machine.
	ends = NetLink.Loopback.pair()
	(t.host as NetHost).attach(ends[0])
	var twin := NetGuest.new(ends[1], "guest-a", "Bex", NetProtocol.hash_password("hunter2"))
	_pump({"host": t.host, "guest": twin, "sim": sim}, 0.1)
	eq(twin.status, "rejected")
	eq(twin.reason, "that player is already connected")
	# Full: seats 2 and 3, then a fifth.
	for who in ["guest-c", "guest-d"]:
		ends = NetLink.Loopback.pair()
		(t.host as NetHost).attach(ends[0])
		var g := NetGuest.new(ends[1], who, "", NetProtocol.hash_password("hunter2"))
		_pump({"host": t.host, "guest": g, "sim": sim}, 0.1)
		ok(g.joined(), who)
	ends = NetLink.Loopback.pair()
	(t.host as NetHost).attach(ends[0])
	var fifth := NetGuest.new(ends[1], "guest-e", "", NetProtocol.hash_password("hunter2"))
	_pump({"host": t.host, "guest": fifth, "sim": sim}, 0.1)
	eq(fifth.status, "rejected")
	eq(fifth.reason, "that game is full")
	eq(sim.present_players().size(), 4)


func test_leaving_parks_and_coming_back_is_the_same_character() -> void:
	var t := _table()
	var gp: PlayerSim = t.gp
	gp.level = 5
	gp.bag.add("scrap", 33)
	(t.guest as NetGuest).leave()
	_pump(t, 0.1)
	ok(gp.away, "the character is parked")
	eq((t.host as NetHost).connected_count(), 0)
	eq(t.sim.players.size(), 2, "parked, not deleted")
	# The same identity walks back in and gets the same character.
	var ends: Array = NetLink.Loopback.pair()
	(t.host as NetHost).attach(ends[0])
	var again := NetGuest.new(ends[1], "guest-a", "Bex II")
	var t2 := {"host": t.host, "guest": again, "sim": t.sim}
	_pump(t2, 0.1)
	ok(again.joined())
	eq(again.me.seat, 1)
	eq(again.me.level, 5)
	eq(again.me.bag.count("scrap"), 33)
	eq(gp.display_name, "Bex II")
	ok(not gp.away)
	eq(t.sim.players.size(), 2)


# ---------------------------------------------------------------- walking --

func test_the_guest_walks_and_both_ends_agree_where_it_is() -> void:
	var t := _table()
	var guest: NetGuest = t.guest
	var gp: PlayerSim = t.gp
	# Put both copies on open ground so the walk is not into a wall.
	var plot := TestCase.tile_centre(TestCase.clear_plot(6))
	gp.pos = plot
	guest.me.pos = plot
	var start := gp.pos
	guest.me.intent.mx = 1.0
	guest.me.intent.aim = plot + Vector2(100, 0)
	_pump(t, 2.0)
	gt(gp.pos.x - start.x, 250.0, "the host walked the guest's player east")
	ok(guest.me.pos.distance_to(gp.pos) < Config.NET.snap_over, "prediction within a snap of the host: %.1f px" % guest.me.pos.distance_to(gp.pos))
	ok(guest.me.pos.distance_to(gp.pos) < 12.0, "and in fact close: %.1f px" % guest.me.pos.distance_to(gp.pos))
	# The guest's stamina and health are the host's.
	gp.hp = 50.0
	_pump(t, 0.1)
	near(guest.me.hp, 50.0, 0.2)


func test_a_silent_guest_holds_nothing() -> void:
	var t := _table()
	var gp: PlayerSim = t.gp
	var plot := TestCase.tile_centre(TestCase.clear_plot(6))
	gp.pos = plot
	(t.guest as NetGuest).me.pos = plot
	(t.guest as NetGuest).me.intent.mx = 1.0
	_pump(t, 0.5)
	ok(gp.vel.length() > 100.0, "walking")
	# The guest's process dies: no more packets, but the host keeps ticking.
	var host: NetHost = t.host
	var at := gp.pos
	for i in range(60):
		host.poll()
		host.sim.tick(DT)
		host.after_tick(DT)
		host.sim.events.clear()
		host.on_events_cleared()
	eq(gp.intent.mx, 0.0, "intent expired")
	ok(gp.pos.distance_to(at) < 0.6 * Config.PLAYER.speed, "stopped well inside the second: moved %.0f px" % gp.pos.distance_to(at))
	# A paused guest says so every step rather than going quiet.
	(t.guest as NetGuest).me.intent.mx = 1.0
	_pump(t, 0.2, true)
	eq(gp.intent.mx, 0.0, "idle intent is holding nothing")


func test_a_lossy_unordered_channel_still_converges() -> void:
	var t := _table("", 0.3, 0.3)
	var guest: NetGuest = t.guest
	var gp: PlayerSim = t.gp
	ok(guest.joined(), "the handshake is on the reliable channel")
	var plot := TestCase.tile_centre(TestCase.clear_plot(6))
	gp.pos = plot
	guest.me.pos = plot
	guest.me.intent.mx = 1.0
	guest.me.intent.aim = plot + Vector2(100, 0)
	_pump(t, 2.0)
	gt(gp.pos.x - plot.x, 200.0, "walked despite 30% loss")
	ok(guest.me.pos.distance_to(gp.pos) < Config.NET.snap_over, "converged: %.1f px" % guest.me.pos.distance_to(gp.pos))
	# A single press lands, exactly once, however lossy the state channel:
	# edges travel reliably. No retry here — one press, one outcome.
	guest.me.intent.slot = 4
	_step(t)
	_pump(t, 0.1)
	eq(gp.slot, 4, "the one slot press got through")
	# A one-step action is not doubled either: a wall is placed once.
	var plot2 := TestCase.clear_plot(6)
	gp.pos = TestCase.tile_centre(plot2)
	guest.me.pos = gp.pos
	gp.bag.add("wood", 40)
	var before: int = t.sim.structs.count()
	guest.me.intent.build_action = "place"
	guest.me.intent.build_type = "woodWall"
	guest.me.intent.build_tile = plot2 + Vector2i(2, 0)
	_step(t)
	_pump(t, 0.2)
	eq(t.sim.structs.count(), before + 1, "placed exactly once")


# -------------------------------------------------------------- snapshots --

func test_a_snapshot_describes_what_is_near_the_guest() -> void:
	var t := _table()
	var sim: GameSim = t.sim
	var gp: PlayerSim = t.gp
	var plot := TestCase.tile_centre(TestCase.clear_plot(6))
	gp.pos = plot
	(t.guest as NetGuest).me.pos = plot
	var near_e := sim.enemies.spawn("walker", plot + Vector2(200, 0))
	var far_e := sim.enemies.spawn("brute", plot + Vector2(Config.NET.interest_radius + 400.0, 0))
	near_e.aggro = false
	far_e.aggro = false
	Loot.spawn_pickup(sim, plot + Vector2(0, 120), "res", "wood", 7)
	_pump(t, 0.2)
	var g: GameSim = (t.guest as NetGuest).sim
	eq(g.enemies.list.size(), 1, "one enemy in range, one out")
	eq(g.enemies.list[0].type, "walker")
	eq(g.enemies.list[0].id, near_e.id)
	ok(g.enemies.list[0].pos.distance_to(near_e.pos) < 40.0, "eased onto it: %.0f" % g.enemies.list[0].pos.distance_to(near_e.pos))
	eq(g.pickups.size(), 1)
	eq(g.pickups[0].id, "wood")
	eq(g.pickups[0].n, 7)
	eq(g.clock.day, sim.clock.day)
	near(g.threat.value, sim.threat.value, 0.2)
	# Killed on the host: gone from the mirror, and a corpse where it fell.
	Damage.kill_enemy(sim, near_e, t.hp)
	_pump(t, 0.2)
	eq(g.enemies.list.size(), 0)
	ok(g.enemies.corpses.size() >= 1, "the kill event left a corpse")


func test_a_snapshot_of_a_horde_fits_the_budget() -> void:
	var sim := TestCase.new_sim()
	var hp: PlayerSim = sim.players[0]
	for i in range(60):
		sim.enemies.spawn("walker" if i % 3 else "runner", hp.pos + Vector2(200 + i * 9, (i % 7) * 40))
	for i in range(20):
		Loot.spawn_pickup(sim, hp.pos + Vector2(i * 10, 300), "res", "wood", 3)
	var bytes := NetProtocol.encode(NetProtocol.pack_snapshot(sim, hp, 1))
	ok(bytes.size() < 3000, "60 enemies and 20 piles in %d bytes" % bytes.size())
	var back := NetProtocol.decode(bytes)
	eq(back.t, "snap")
	eq((back.en as PackedFloat32Array).size(), 60 * NetProtocol.EN_STRIDE)


# --------------------------------------------------------------- commands --

func test_a_command_runs_on_the_host_and_the_pack_comes_back() -> void:
	var t := _table()
	var guest: NetGuest = t.guest
	var gp: PlayerSim = t.gp
	gp.bag.add("wood", 40)
	gp.bag.add("stone", 40)
	gp.bag.add("fiber", 40)
	gp.bag.add("sticks", 40)
	_pump(t, 0.6)
	eq(guest.me.bag.count("wood"), 40, "the sync tick delivered the pack")
	var recipe := {}
	for r in Config.RECIPES:
		if r.id == "axe":
			recipe = r
	ok(not recipe.is_empty())
	var st := Crafting.status(t.sim, gp, recipe, 0)
	ok(st.ok, "the host can make it: %s" % st.reason)
	# Through the seam, as the guest's pack screen would.
	Actions.guest = guest
	Actions.craft(guest.sim, guest.me, recipe, 0)
	Actions.guest = null
	_pump(t, 0.1)
	ok(gp.carries("axe"), "the host crafted it for the guest")
	ok(guest.me.carries("axe"), "and the guest's pack shows it: %s" % str(guest.me.bag.entries()))


func test_building_travels_as_intent_and_comes_back_as_the_world() -> void:
	var t := _table()
	var guest: NetGuest = t.guest
	var gp: PlayerSim = t.gp
	var plot := TestCase.clear_plot(6)
	gp.pos = TestCase.tile_centre(plot)
	guest.me.pos = gp.pos
	gp.bag.add("wood", 40)
	var before: int = t.sim.structs.count()
	guest.me.intent.build_action = "place"
	guest.me.intent.build_type = "woodWall"
	guest.me.intent.build_tile = plot + Vector2i(2, 0)
	_step(t)
	eq(t.sim.structs.count(), before + 1, "the host placed it")
	_pump(t, 0.6)
	var mirror := guest.sim.structs.at_tile(plot.x + 2, plot.y)
	eq(mirror.get("type", ""), "woodWall", "the wall reached the mirror")
	# Hit it on the host: the damage shows up; salvage it: it goes.
	var s: Dictionary = t.sim.structs.at_tile(plot.x + 2, plot.y)
	t.sim.structs.damage(t.sim, s, 10.0)
	_pump(t, 0.6)
	ok(guest.sim.structs.at_tile(plot.x + 2, plot.y).hp < s.max_hp, "damage mirrored")
	t.sim.structs.demolish(t.sim, s, gp)
	_pump(t, 0.6)
	ok(guest.sim.structs.at_tile(plot.x + 2, plot.y).is_empty(), "gone from the mirror")


func test_the_stash_and_a_searched_container_are_shared() -> void:
	var t := _table()
	var guest: NetGuest = t.guest
	var gp: PlayerSim = t.gp
	var hp: PlayerSim = t.hp
	var plot := TestCase.clear_plot(6)
	hp.pos = TestCase.tile_centre(plot)
	gp.pos = hp.pos + Vector2(0, 40)
	guest.me.pos = gp.pos
	hp.bag.add("wood", 100)
	hp.bag.add("scrap", 100)
	var stash: Dictionary = t.sim.structs.place(t.sim, "stash", plot.x + 1, plot.y - 1, hp)
	ok(not stash.is_empty())
	gp.bag.add("scrap", 12)
	_pump(t, 0.6)
	Actions.guest = guest
	Actions.deposit_all(guest.sim, guest.me, Vector2i(plot.x + 1, plot.y - 1), 0)
	Actions.guest = null
	_pump(t, 0.1)
	eq(t.sim.stash.count("scrap"), 12, "deposited on the host")
	ne(guest.sim.stash, null)
	eq(guest.sim.stash.count("scrap"), 12, "and the mirror's stash agrees")
	eq(guest.me.bag.count("scrap"), 0)
	# The host searches a container: the mirror marks it looted.
	var box := {}
	for c in t.sim.world.containers:
		if not c.looted:
			box = c
			break
	box.looted = true
	_pump(t, 0.6)
	var by_tile := {}
	for c in guest.sim.world.containers:
		by_tile["%d,%d" % [c.tx, c.ty]] = c
	ok(by_tile["%d,%d" % [box.tx, box.ty]].looted, "the mirror's container is empty too")
	# A boot: filled, seen by the guest; emptied, cleared on the guest too.
	var car: Dictionary = t.sim.cars.list[0]
	car.trunk.add("scrap", 5)
	_pump(t, 0.6)
	eq(guest.sim.cars.by_id(int(car.id)).trunk.count("scrap"), 5, "the boot's contents reached the mirror")
	car.trunk.take("scrap", 5)
	_pump(t, 0.6)
	eq(guest.sim.cars.by_id(int(car.id)).trunk.count("scrap"), 0, "and so did its emptying")


func test_events_reach_the_guest_that_can_see_them() -> void:
	var t := _table()
	var guest: NetGuest = t.guest
	var hp: PlayerSim = t.hp
	var gp: PlayerSim = t.gp
	var plot := TestCase.tile_centre(TestCase.clear_plot(6))
	hp.pos = plot
	gp.pos = plot + Vector2(60, 0)
	guest.me.pos = gp.pos
	t.sim.give_test_kit(hp)
	hp.select_slot(hp.hotbar_index("pistol"))
	hp.intent.aim = plot + Vector2(300, 0)
	hp.intent.fire = true
	hp.intent.fire_pressed = true
	_pump(t, 0.3)
	hp.intent.fire = false
	_pump(t, 0.05)
	ok(_guest_events(t, "shot").size() >= 1, "the shot was heard")
	ok(_guest_events(t, "muzzle").size() >= 1, "and seen")
	ok(guest.sim.bullets.size() >= 1 or _guest_events(t, "shot").size() >= 1, "a tracer was drawn")
	# World news with no position reaches everyone; a scream across town does not.
	t.sim.notify("A storm is coming", "#fff", true)
	t.sim.emit({"t": "growl", "x": plot.x + 5000.0, "y": plot.y})
	_step(t)
	ok(_guest_events(t, "notify").size() >= 1)
	eq(_guest_events(t, "growl").size(), 0, "too far to hear")
	# A boot opening is the presser's screen and nobody else's.
	t.sim.emit({"t": "open_boot", "seat": hp.seat, "id": 1})
	t.sim.emit({"t": "open_boot", "seat": gp.seat, "id": 1})
	_pump(t, 0.05)
	var boots := _guest_events(t, "open_boot")
	eq(boots.size(), 1, "only the guest's own boot event reached it")
	if boots.size() == 1:
		eq(int(boots[0].seat), gp.seat)


func test_the_host_save_carries_the_guest_home() -> void:
	var t := _table()
	var gp: PlayerSim = t.gp
	gp.level = 7
	var r := SaveGame.save_to(t.sim, 91)
	ok(r.ok, r.reason)
	var sim2 := GameSim.new()
	var loaded := SaveGame.load_from(sim2, 91)
	ok(loaded.ok, loaded.reason)
	Saves.delete(91)
	var back := sim2.player_by_identity("guest-a")
	ne(back, null)
	eq(back.level, 7)
	ok(back.away, "not here until they connect")
	# They connect to the loaded game and get it back.
	var host2 := NetHost.new(sim2, "Ryan")
	var ends: Array = NetLink.Loopback.pair()
	host2.attach(ends[0])
	var g2 := NetGuest.new(ends[1], "guest-a", "Bex")
	_pump({"host": host2, "guest": g2, "sim": sim2}, 0.1)
	ok(g2.joined())
	eq(g2.me.level, 7)
	eq(g2.me.seat, 1)
	ok(not back.away)


func test_down_and_revive_over_the_wire() -> void:
	var t := _table()
	var guest: NetGuest = t.guest
	var hp: PlayerSim = t.hp
	var gp: PlayerSim = t.gp
	var plot := TestCase.tile_centre(TestCase.clear_plot(6))
	hp.pos = plot
	gp.pos = plot + Vector2(40, 0)
	guest.me.pos = gp.pos
	hp.invuln = 0.0
	Damage.damage_player(t.sim, hp, 9999.0, plot)
	ok(hp.downed, "the host went down because a guest was standing")
	_pump(t, 0.2)
	ok(guest.sim.players[0].downed, "the mirror shows it")
	# The guest holds E beside them.
	guest.me.intent.interact = true
	guest.me.intent.interact_held = true
	_step(t)
	for i in range(int(Config.PLAYER.revive_time * 60) + 10):
		guest.me.intent.interact_held = true
		_step(t)
	ok(not hp.downed, "up again")
	ok(not hp.dead)
	_pump(t, 0.2)
	ok(not guest.sim.players[0].downed)
	ok(_guest_events(t, "player_up").size() >= 1)


# ------------------------------------------------------------------- enet --

## The same handshake over a real UDP socket on this machine. ENet needs a
## few round trips to connect, so this test pumps both hubs against the
## clock rather than against the simulation; a second is plenty on localhost.
func test_enet_on_localhost() -> void:
	var port := 27400 + (Time.get_ticks_msec() % 100)
	var hh := EnetHub.new()
	var err := hh.host(port, 3)
	eq(err, "", err)
	if not err.is_empty():
		return
	var gh := EnetHub.new()
	err = gh.join("127.0.0.1", port)
	eq(err, "", err)
	var t0 := Time.get_ticks_msec()
	while (not gh.connected() or gh.host_link() == null or hh.joined.is_empty()) and Time.get_ticks_msec() - t0 < 3000:
		hh.poll()
		gh.poll()
		OS.delay_msec(2)
	ok(gh.connected(), "the dial landed")
	eq(hh.joined.size(), 1, "the host saw one peer")
	if not gh.connected() or hh.joined.is_empty():
		hh.close()
		gh.close()
		return
	var sim := TestCase.new_sim()
	var host := NetHost.new(sim, "Ryan")
	host.attach(hh.links[hh.joined[0]])
	var guest := NetGuest.new(gh.host_link(), "guest-udp", "Dee")
	t0 = Time.get_ticks_msec()
	var t := {"host": host, "guest": guest, "sim": sim}
	while not guest.joined() and guest.status == "connecting" and Time.get_ticks_msec() - t0 < 3000:
		hh.poll()
		gh.poll()
		_step(t)
		OS.delay_msec(1)
	ok(guest.joined(), "joined over UDP: %s %s" % [guest.status, guest.reason])
	if guest.joined():
		var gp := sim.player_by_identity("guest-udp")
		var plot := TestCase.tile_centre(TestCase.clear_plot(6))
		gp.pos = plot
		guest.me.pos = plot
		guest.me.intent.mx = 1.0
		for i in range(60):
			hh.poll()
			gh.poll()
			_step(t)
			OS.delay_msec(1)
		gt(gp.pos.x - plot.x, 60.0, "walked over the socket")
		ok(guest.me.pos.distance_to(gp.pos) < Config.NET.snap_over)
		guest.leave()
		for i in range(30):
			hh.poll()
			gh.poll()
			_step(t)
			OS.delay_msec(1)
		ok(gp.away, "bye parked the character")
	hh.close()
	gh.close()
