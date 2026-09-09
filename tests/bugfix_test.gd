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
