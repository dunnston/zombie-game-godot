extends "res://tests/test_case.gd"
## The Notion bug queue, round one. Each test is the reproduction that was
## written before the fix, kept so the bug cannot come back.

var sim: GameSim
var p: PlayerSim


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]


func _unlocked_car() -> Dictionary:
	for car in sim.cars.list:
		if not car.destroyed:
			car.locked = false
			car.fuel = 40.0
			return car
	return {}


## DL-45: a tap of E beside a car drives it. `interact_held` is already true on
## the frame `interact` fires — that is what local_input.gd writes — so reading
## it there made the boot the only reachable answer.
func test_tap_of_e_drives_the_car() -> void:
	var v := _unlocked_car()
	ok(not v.is_empty(), "found a car")
	if v.is_empty():
		return
	p.pos = v.pos
	sim.events.clear()
	p.intent.interact = true
	p.intent.interact_held = true
	Interact.tick(sim, p, 1.0 / 60.0)
	eq(p.driving_id, 0, "the press frame alone decides nothing")

	# Let go on the next frame: that is a tap, and a tap drives.
	p.intent.interact = false
	p.intent.interact_held = false
	Interact.tick(sim, p, 1.0 / 60.0)
	eq(p.driving_id, int(v.id), "letting go drove the car")
	for e in sim.events:
		ok(String(e.get("t", "")) != "open_boot", "no boot was opened by a tap")


## The other half: keeping E down past the threshold opens the boot and does
## not drive.
func test_holding_e_opens_the_boot() -> void:
	var v := _unlocked_car()
	if v.is_empty():
		return
	p.pos = v.pos
	sim.events.clear()
	p.intent.interact = true
	p.intent.interact_held = true
	Interact.tick(sim, p, 1.0 / 60.0)
	var opened := false
	var guard := 0
	while not opened and guard < 240:
		guard += 1
		p.intent.interact = false
		p.intent.interact_held = true
		Interact.tick(sim, p, 1.0 / 60.0)
		for e in sim.events:
			if String(e.get("t", "")) == "open_boot":
				opened = true
	ok(opened, "holding E opened the boot")
	eq(p.driving_id, 0, "holding E did not also drive off")


## DL-45 body: a wall between you and a cabinet means you cannot search it.
func test_no_looting_through_a_wall() -> void:
	var checked := 0
	for c in sim.world.containers:
		if c.looted or checked >= 8:
			continue
		var at := Vector2(c.x, c.y)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var wx: int = int(c.x / Config.TILE) + d.x
			var wy: int = int(c.y / Config.TILE) + d.y
			if not sim.world.in_bounds(wx, wy):
				continue
			if sim.world.tiles[wy * sim.world.W + wx] != Config.T.WALL:
				continue
			# Stand on the far side of that wall, still inside interact range.
			p.pos = at + Vector2(d) * Config.TILE * 1.6
			if p.pos.distance_to(at) > Config.PLAYER.interact_range:
				continue
			checked += 1
			var t := Interact.best_target(sim, p)
			ok(String(t.get("kind", "")) != "container",
				"a wall at %d,%d hides the %s behind it" % [wx, wy, c.label])
			break
	ok(checked > 0, "found at least one container with a wall beside it")


## Standing in the open beside a cabinet still offers it — the sight test must
## not cost the player the ordinary case.
func test_open_ground_still_searches() -> void:
	var offered := false
	for c in sim.world.containers:
		if c.looted:
			continue
		var at := Vector2(c.x, c.y)
		for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			var stand := at + d * Config.TILE
			if sim.world.is_blocked_px(stand.x, stand.y):
				continue
			p.pos = stand
			var t := Interact.best_target(sim, p)
			if String(t.get("kind", "")) == "container":
				offered = true
				break
		if offered:
			break
	ok(offered, "a cabinet you are standing beside is still searchable")


## DL-42: nature litter belongs on nature. Building floors and roads stay clear.
func test_litter_stays_on_nature() -> void:
	var bad := 0
	var samples: Array[String] = []
	for prop in sim.world.props:
		if not String(prop.get("harvest", "")).begins_with("litter_"):
			continue
		var t: int = sim.world.tiles[int(prop.ty) * sim.world.W + int(prop.tx)]
		if Config.LITTER_SURFACES.has(t):
			continue
		bad += 1
		if samples.size() < 5:
			samples.append("%d,%d tile=%d" % [int(prop.tx), int(prop.ty), t])
	ok(bad == 0, "no litter off nature ground (%d found: %s)" % [bad, ", ".join(samples)])


## The camp still has enough to make the first tool: the surface policy must
## not have starved the starter cache.
func test_camp_still_stocked() -> void:
	var camp: Dictionary = sim.world.locations[0]
	var r: Rect2i = camp.rect
	var cx := roundi(r.position.x + r.size.x / 2.0)
	var cy := roundi(r.position.y + r.size.y / 2.0)
	var have := {"sticks": 0, "fiber": 0, "stone": 0}
	for y in range(cy - 12, cy + 13):
		for x in range(cx - 12, cx + 13):
			if not sim.world.in_bounds(x, y):
				continue
			var prop: Dictionary = sim.world.prop_at_tile(x, y)
			if prop.is_empty() or not prop.get("hand", false):
				continue
			var res := String(prop.get("res", ""))
			if have.has(res):
				have[res] += 1
	for res in have:
		ok(have[res] > 0, "camp has %s within a short walk (%d)" % [res, have[res]])


# ------------------------------------------------------------- dev menu --

## DL-56. The menu is a developer tool, but the thing it does — hand you an
## item, put an enemy in front of you, move you across the map — is game state,
## so it is tested like anything else that touches game state.

func _dev() -> DevScreen:
	var d := DevScreen.new(sim)
	d.player = p
	return d


func test_the_dev_catalogue_covers_the_game() -> void:
	var d := _dev()
	var kinds := {}
	for row in d._all:
		kinds[String(row.kind)] = int(kinds.get(String(row.kind), 0)) + 1
	eq(int(kinds.get("give", 0)), Items.registry().size(), "every carryable item is listed")
	eq(int(kinds.get("enemy", 0)), Config.ENEMIES.size(), "every enemy is listed")
	eq(int(kinds.get("goto", 0)), sim.world.locations.size(), "every district is listed")
	gt(int(kinds.get("verb", 0)), 0, "and there are verbs")
	d.free()


func test_the_filter_narrows_by_name_and_by_id() -> void:
	var d := _dev()
	var all := d._shown.size()
	d.filter = "bandage"
	d._refilter()
	gt(d._shown.size(), 0, "bandage matches something")
	ok(d._shown.size() < all, "and not everything")
	for row in d._shown:
		var hay := (String(row.label) + String(row.id)).to_lower()
		ok(hay.contains("bandage"), "%s matched 'bandage'" % String(row.label))
	d.filter = "zzzznothing"
	d._refilter()
	eq(d._shown.size(), 0, "a miss shows an empty list, not the whole catalogue")
	d.free()


func test_giving_an_item_puts_it_in_the_pack() -> void:
	var d := _dev()
	var before := p.count_carried("bandage")
	d.apply({"kind": "give", "id": "bandage"}, 3)
	eq(p.count_carried("bandage"), before + 3, "three bandages arrived")
	d.free()


func test_spawning_an_enemy_puts_one_in_the_world() -> void:
	var d := _dev()
	var before := sim.enemies.list.size()
	d.apply({"kind": "enemy", "id": "walker"}, 2)
	eq(sim.enemies.list.size(), before + 2, "two walkers arrived")
	for e in sim.enemies.list:
		ok(not sim.world.circle_hits_solid(e.pos.x, e.pos.y, e.r, sim.structs),
			"a spawned walker is not inside a wall")
	d.free()


func test_going_to_a_district_lands_you_in_it() -> void:
	var d := _dev()
	var target := ""
	for l in sim.world.locations:
		if String(l.id) != String(sim.world.locations[0].id):
			target = String(l.id)
			break
	d.apply({"kind": "goto", "id": target})
	var here := sim.world.location_at_px(p.pos.x, p.pos.y)
	eq(String(here.get("id", "")), target, "the player is standing in %s" % target)
	ok(not sim.world.circle_hits_solid(p.pos.x, p.pos.y, p.r, sim.structs), "and not inside a wall")
	d.free()


func test_the_verbs_do_what_they_say() -> void:
	var d := _dev()
	p.hp = 1.0
	p.stam = 0.0
	d.apply({"kind": "verb", "id": "heal"})
	d.apply({"kind": "verb", "id": "stamina"})
	eq(p.hp, p.max_hp, "healed")
	eq(p.stam, p.max_stam, "stamina back")

	# Fifty of everything overflows the pack on purpose: what will not fit is
	# dropped at your feet rather than lost, so every resource is accounted for
	# one way or the other.
	d.apply({"kind": "verb", "id": "res"})
	for rid in Config.RES:
		var on_ground := 0
		for it in sim.pickups:
			if String(it.id) == rid:
				on_ground += int(it.n)
		gt(p.count_carried(rid) + on_ground, 0, "has some %s, carried or at his feet" % rid)

	sim.enemies.spawn("walker", p.pos + Vector2(200, 0))
	d.apply({"kind": "verb", "id": "clear"})
	for e in sim.enemies.list:
		ok(e.dead, "everything loaded is dead")

	sim.threat.value = 40.0
	d.apply({"kind": "verb", "id": "quiet"})
	eq(sim.threat.value, 0.0, "threat cleared")
	d.free()


## A release build has no dev menu at all, so nothing about it can be reached
## by accident. The gate is in main.gd; this pins the shape it depends on.
func test_the_dev_menu_is_not_a_rebindable_action() -> void:
	for a in KeyBinds.ACTIONS:
		ne(String(a.id), "dev_menu", "the dev key is not offered on the controls screen")
	ok(KeyBinds.KEYS.has("dev_menu"), "but it is bound")
