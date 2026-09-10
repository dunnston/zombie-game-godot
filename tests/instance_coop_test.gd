extends TestCase
## Going into the School together (PR D), over a loopback: a host and a guest
## joined by two in-memory queues and stepped in lockstep, the way
## `net_test.gd` does it. Asserted on outcomes — which map the guest's mirror
## is on, where the guest is standing, what is in their pack.

const DT := 1.0 / 60.0

static var _guest_world: World


func before_each() -> void:
	if _guest_world == null:
		_guest_world = World.new()
	NetGuest.reuse_world = _guest_world


func after_each() -> void:
	NetGuest.reuse_world = null
	Actions.guest = null


func _table(identity := "guest-a", name_ := "Bex") -> Dictionary:
	var sim := TestCase.new_sim()
	var host := NetHost.new(sim, "Ryan", NetProtocol.hash_password(""))
	var ends: Array = NetLink.Loopback.pair(0.0, 0.0)
	host.attach(ends[0])
	var guest := NetGuest.new(ends[1], identity, name_, NetProtocol.hash_password(""))
	var t := {"host": host, "guest": guest, "sim": sim, "hp": sim.players[0], "gp": null}
	_pump(t, 0.1)
	t.gp = sim.player_by_identity(identity)
	(t.hp as PlayerSim).god_mode = true
	(t.gp as PlayerSim).god_mode = true
	return t


func _pump(t: Dictionary, seconds: float) -> void:
	for i in range(int(round(seconds / DT))):
		var guest: NetGuest = t.guest
		var host: NetHost = t.host
		guest.poll()
		guest.tick(DT)
		host.poll()
		host.sim.tick(DT)
		host.after_tick(DT)
		host.sim.events.clear()
		host.on_events_cleared()


## Both at the School's door, on the host.
func _at_door(t: Dictionary) -> void:
	var sim: GameSim = t.sim
	var f := Instance.door_for(sim, "school")
	for q: PlayerSim in [t.hp, t.gp]:
		q.pos = f.stand + (Vector2(0, 20) if q == t.gp else Vector2.ZERO)
		q.prev_pos = q.pos
	(t.guest as NetGuest).me.pos = (t.gp as PlayerSim).pos
	_pump(t, 0.2)


func _enter(t: Dictionary) -> Instance:
	_at_door(t)
	ok(Instance.enter(t.sim, t.hp, "school"), "the door opens for the two of you")
	_pump(t, 0.5)
	return (t.sim as GameSim).instance


# ------------------------------------------------------------------ in --

func test_the_guest_follows_the_host_into_the_same_school() -> void:
	var t := _table()
	var inst := _enter(t)
	var gs: GameSim = (t.guest as NetGuest).sim
	ok(gs.instance != null, "the guest's mirror went in too")
	eq(gs.world.layout, "school")
	eq(gs.world.fingerprint(), (t.sim as GameSim).world.fingerprint(), "the same building, room for room, from the seed")
	eq(gs.instance.run_seed, inst.run_seed)
	var me: PlayerSim = (t.guest as NetGuest).me
	ok(me.pos.distance_to(gs.world.entry_spot) < 64.0, "and they are standing in the foyer")
	gt(gs.enemies.list.size(), 0, "with the dead the host can see")


func test_a_guest_can_open_the_door_for_both_of_them() -> void:
	# Through `Actions`, the way the guest's own ENTER button goes.
	var t := _table()
	_at_door(t)
	Actions.guest = t.guest
	var g: NetGuest = t.guest
	Actions.enter_instance(g.sim, g.me, "school")
	_pump(t, 0.5)
	ok((t.sim as GameSim).instance != null, "the host ran the guest's ENTER")
	ok(g.sim.instance != null)
	ok((t.hp as PlayerSim).pos.distance_to((t.sim as GameSim).world.entry_spot) < 64.0,
		"and took the host in with them, into the foyer")


func test_the_gym_key_and_the_open_door_reach_the_guest() -> void:
	var t := _table()
	var inst := _enter(t)
	var sim: GameSim = t.sim
	var chained := {}
	for f in sim.world.features:
		if String(f.kind) == "chained":
			chained = f
	inst.found_key(sim, "gym")
	ok(inst.unlock(sim, chained))
	_pump(t, 0.7)
	var gs: GameSim = (t.guest as NetGuest).sim
	ok(gs.instance.keys.get("gym", false), "the guest knows about the key")
	var tile: Vector2i = chained.tiles[0]
	ok(not gs.world.is_blocked_tile(tile.x, tile.y), "and can walk through the door the host opened")


func test_what_a_guest_finds_is_in_their_haul_on_their_screen() -> void:
	var t := _table()
	_enter(t)
	Loot.give_entry(t.sim, t.gp, {"id": "scrap", "n": 7})
	_pump(t, 0.7)
	var me: PlayerSim = (t.guest as NetGuest).me
	eq(me.haul.count("scrap"), 7)
	eq(int((t.guest as NetGuest).sim.instance.gained.get(me.seat, {}).get("scrap", 0)), 7,
		"and the tally their way-out panel reads")


func test_somebody_joining_mid_run_is_told_the_party_is_inside() -> void:
	var t := _table()
	_enter(t)
	var ends: Array = NetLink.Loopback.pair(0.0, 0.0)
	(t.host as NetHost).attach(ends[0])
	var late := NetGuest.new(ends[1], "guest-late", "Cole", NetProtocol.hash_password(""))
	for i in range(12):
		late.poll()
		late.tick(DT)
		(t.host as NetHost).poll()
		(t.host as NetHost).after_tick(DT)
	late.poll()
	eq(late.status, "rejected")
	ok(late.reason.contains("inside Pine Hollow High"), late.reason)


func test_a_snapshot_of_the_other_map_is_dropped() -> void:
	var t := _table()
	var inst := _enter(t)
	var g: NetGuest = t.guest
	var at := g.me.pos
	var seq := g.last_snap_seq
	var snap := NetProtocol.pack_snapshot(t.sim, t.gp, seq + 1)
	snap.mp = inst.run_seed + 1
	(t.gp as PlayerSim).pos = at + Vector2(900, 0)
	g._on_snapshot(snap)
	eq(g.last_snap_seq, seq, "not taken")
	ok(g.me.pos.distance_to(at) < 1.0, "and nobody moved")


# ----------------------------------------------------------------- out --

func test_the_guest_comes_out_with_the_party_and_the_door_is_chained_on_both() -> void:
	var t := _table()
	var inst := _enter(t)
	Loot.give_entry(t.sim, t.gp, {"id": "scrap", "n": 5})
	Damage.kill_enemy(t.sim, inst.boss, t.hp)
	_pump(t, 0.2)
	Instance.leave(t.sim, "extracted")
	_pump(t, 0.7)
	var g: NetGuest = t.guest
	eq(g.sim.instance, null, "the mirror is back in the town")
	eq(g.sim.world.layout, "town")
	eq(int(g.sim.cleared.get("school", -1)), (t.sim as GameSim).clock.day, "and knows the School is done for the day")
	var door: Vector2 = Instance.door_for(g.sim, "school").stand
	ok(g.me.pos.distance_to(door) < 64.0, "standing at the door")
	eq(g.me.count_carried("scrap"), 5, "with what they found")
	eq(g.me.haul.used(), 0)
