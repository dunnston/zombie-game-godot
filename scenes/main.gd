extends Node2D
## The root scene. Builds the simulation and the nodes that draw it, gathers
## the local player's intent every physics step, ticks the sim, drains its
## events into the effects and the HUD, and moves the camera. Nothing here
## changes game state except through Intent.

const WORLD_SEED := 20240917

var sim: GameSim
var terrain: TerrainRenderer
var props_below: PropRenderer
var props_above: PropRenderer
var enemy_view: EnemyView
var pickup_view: PickupView
var structure_view: StructureView
var fx: FxView
var player_view: PlayerView
var camera: Camera2D
var hud: Hud
var inventory: InventoryScreen
var build_bar: BuildBar
var shake := 0.0
var _shake_rng := RandomNumberGenerator.new()


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	sim = GameSim.new()
	sim.new_game(WORLD_SEED)
	var t1 := Time.get_ticks_msec()

	terrain = TerrainRenderer.new()
	add_child(terrain)
	terrain.build(sim.world)
	var t2 := Time.get_ticks_msec()

	props_below = PropRenderer.new(sim, false)
	add_child(props_below)
	pickup_view = PickupView.new(sim)
	add_child(pickup_view)
	structure_view = StructureView.new(sim)
	add_child(structure_view)
	enemy_view = EnemyView.new(sim)
	add_child(enemy_view)
	player_view = PlayerView.new(sim.players[0])
	add_child(player_view)
	props_above = PropRenderer.new(sim, true)
	add_child(props_above)
	fx = FxView.new(sim)
	add_child(fx)

	camera = Camera2D.new()
	var C := Config.CAMERA
	var vp := get_viewport_rect().size
	var z := clampf(vp.y / C.view_height, C.min_zoom, C.max_zoom)
	camera.zoom = Vector2(z, z)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = Config.WORLD_SIZE
	camera.limit_bottom = Config.WORLD_SIZE
	camera.position = sim.players[0].pos
	add_child(camera)
	camera.make_current()
	# Half the screen's diagonal in world pixels: the spawn ring sits beyond it.
	sim.view_radius = vp.length() / 2.0 / z

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new(sim)
	layer.add_child(hud)
	inventory = InventoryScreen.new(sim)
	layer.add_child(inventory)
	build_bar = BuildBar.new(sim)
	layer.add_child(build_bar)
	structure_view.build_bar = build_bar
	print("boot: world %d ms, terrain %d ms, props %d, containers %d" % [t1 - t0, t2 - t1, sim.world.props.size(), sim.world.containers.size()])


func _physics_process(dt: float) -> void:
	# Polled rather than handled as an event, like every other key here: the
	# smoke run presses actions through `Input`, which sets the action state
	# without ever synthesising an InputEvent.
	if Input.is_action_just_pressed("inventory"):
		inventory.toggle()
		if inventory.visible and build_bar.open:
			build_bar.toggle()
	elif Input.is_action_just_pressed("build") and not inventory.visible:
		build_bar.toggle()
	elif Input.is_action_just_pressed("pause"):
		if inventory.visible:
			inventory.toggle()
		elif build_bar.open:
			build_bar.toggle()

	var intent := sim.players[0].intent
	# An open panel owns the mouse: you can still walk, but a click belongs to
	# the screen you are looking at rather than to the gun in your hand.
	LocalInput.gather(intent, self, inventory.visible or build_bar.open)
	if build_bar.open:
		build_bar.update_hover(get_global_mouse_position())
		if Input.is_action_just_pressed("fire"):
			build_bar.click(get_viewport().get_mouse_position())
		if Input.is_action_just_pressed("wheel_down"):
			build_bar.cycle(1)
		elif Input.is_action_just_pressed("wheel_up"):
			build_bar.cycle(-1)
		build_bar.fill_intent(intent)
	sim.tick(dt)


func _process(dt: float) -> void:
	for ev in sim.events:
		if ev.t == "shake":
			shake = maxf(shake, ev.amount)
		fx.on_event(ev)
		hud.on_event(ev)
	sim.events.clear()
	fx.tick(dt)
	hud.tick(dt)
	shake = maxf(0.0, shake - dt * 22.0)
	_update_camera(dt)
	props_below.queue_redraw()
	props_above.queue_redraw()
	pickup_view.queue_redraw()
	structure_view.queue_redraw()
	if build_bar.open:
		build_bar.queue_redraw()
	if inventory.visible:
		inventory.queue_redraw()
	enemy_view.queue_redraw()
	player_view.queue_redraw()
	fx.queue_redraw()
	hud.queue_redraw()


## Leads toward the cursor so you can see what you are aiming at.
func _update_camera(dt: float) -> void:
	var p := sim.players[0]
	var C := Config.CAMERA
	var mouse := get_global_mouse_position()
	var lead := Vector2(
		clampf((mouse.x - p.pos.x) * C.lead, -C.lead_max, C.lead_max),
		clampf((mouse.y - p.pos.y) * C.lead, -C.lead_max, C.lead_max))
	camera.position = camera.position.lerp(p.pos + lead, Util.smooth(C.follow, dt))
	if shake > 0.0:
		camera.offset = Vector2(_shake_rng.randf_range(-shake, shake), _shake_rng.randf_range(-shake, shake))
	else:
		camera.offset = Vector2.ZERO


# ------------------------------------------------------------------ smoke --

func smoke_state() -> Dictionary:
	var p := sim.players[0]
	var loc := sim.world.location_at_px(p.pos.x, p.pos.y)
	return {
		"x": p.pos.x, "y": p.pos.y, "tx": int(p.pos.x / 32), "ty": int(p.pos.y / 32),
		"location": loc.get("id", "outskirts"), "stam": p.stam, "hp": p.hp, "winded": p.winded,
		"weapon": p.weapon().id, "enemies": sim.enemies.alive_count(), "kills": sim.stats.kills,
		"threat": sim.threat.value, "raid": sim.raid != null,
		"bag": p.bag.used(), "weight": roundi(p.carried_weight()), "dr": p.armor_dr,
		"pickups": sim.pickups.size(), "looted": sim.stats.looted,
	}


func smoke_teleport(tx: int, ty: int) -> void:
	var p := sim.players[0]
	p.pos = sim.world.unstick(Vector2(tx * 32 + 16, ty * 32 + 16), p.r)
	p.vel = Vector2.ZERO
	camera.position = p.pos


## Points the mouse at a world position, so aim goes through the real path.
func smoke_aim(world_pos: Vector2) -> void:
	var screen := get_viewport().get_canvas_transform() * world_pos
	Input.warp_mouse(screen)


## A click at a screen position, fed through the real input pipeline so it
## reaches the panel's own hit test rather than a back door.
##
## The cursor is warped first: a panel that reads `_gui_input` gets the
## position off the event, but build mode polls `get_mouse_position()` the
## way the rest of this scene polls its keys, and those two have to agree.
## The button is held for several frames so a physics step is guaranteed to
## see the press — process and physics both run at 60Hz, and a one-frame tap
## lands between them about half the time.
func smoke_click(at: Vector2, ctrl := false) -> void:
	Input.warp_mouse(at)
	await get_tree().process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = at
		ev.global_position = at
		ev.ctrl_pressed = ctrl
		ev.pressed = pressed
		Input.parse_input_event(ev)
		for i in range(3):
			await get_tree().process_frame


## The nearest container to a point that still has something in it.
func smoke_nearest_container(at: Vector2) -> Dictionary:
	var best := {}
	var bd := INF
	for c in sim.world.containers:
		if c.looted:
			continue
		var d: float = at.distance_squared_to(Vector2(c.x, c.y))
		if d < bd:
			bd = d
			best = c
	return best


## The scripted session: walk, sprint, photograph the districts, then fight.
func smoke_run(smoke: Node) -> void:
	var p := sim.players[0]
	var start := p.pos
	await smoke.checkpoint("spawn")
	await smoke.hold("move_right", 90)
	if p.pos.x - start.x < 60.0:
		smoke.fail("player did not walk east: dx=%.1f" % (p.pos.x - start.x))
	await smoke.checkpoint("walked_east")
	Input.action_press("sprint")
	await smoke.hold("move_down", 90)
	Input.action_release("sprint")
	if p.stam >= p.max_stam:
		smoke.fail("sprinting did not drain stamina")
	await smoke.checkpoint("sprinted_south")
	for spot in [["suburbs", 118, 120], ["market_row", 200, 158], ["downtown", 262, 172],
			["farms", 30, 140], ["lake_lodge", 190, 52], ["forest", 60, 30], ["junkyard", 190, 270]]:
		smoke_teleport(spot[1], spot[2])
		await smoke.frames(3)
		await smoke.checkpoint(spot[0])

	# The pack: search a container, look at what came out, drop something and
	# pick it back up. All of it through the real keys and the real panel.
	var box := smoke_nearest_container(Vector2(160 * 32, 160 * 32))
	if box.is_empty():
		smoke.fail("no container in the world to search")
	else:
		smoke_teleport(int(box.tx), int(box.ty) + 1)
		await smoke.frames(3)
		var before := p.bag.used()
		await smoke.hold("interact", 150)
		if not box.looted:
			smoke.fail("holding E beside the %s did not search it" % box.label)
		if p.bag.used() <= before:
			smoke.fail("the search put nothing in the pack")
		await smoke.checkpoint("searched")

	await smoke.tap("inventory")
	await smoke.frames(3)
	if not inventory.visible:
		smoke.fail("Tab did not open the pack")
	await smoke.checkpoint("pack_open")

	# Ctrl+click the bandages off the hotbar: they should land on the ground.
	var piles := sim.pickups.size()
	await smoke_click(inventory.cell_centre("hotbar", 1), true)
	await smoke.frames(2)
	if sim.pickups.size() <= piles:
		smoke.fail("ctrl+click on the hotbar dropped nothing")
	await smoke.tap("inventory")
	await smoke.frames(2)
	if inventory.visible:
		smoke.fail("Tab did not close the pack")
	await smoke.checkpoint("dropped")

	# Step clear, then walk back over the pile: the magnet hands it back.
	if not sim.pickups.is_empty():
		var pile: Dictionary = sim.pickups[0]
		var away := p.pos
		smoke_teleport(int(p.pos.x / 32) + 6, int(p.pos.y / 32))
		await smoke.frames(10)
		p.pos = pile.pos
		var waited := 0
		while not sim.pickups.is_empty() and waited < 120:
			await smoke.frames(1)
			waited += 1
		if not sim.pickups.is_empty():
			smoke.fail("the dropped pile was never picked back up")
		if p.count_carried("bandage") < 2:
			smoke.fail("the bandages did not come back: %d" % p.count_carried("bandage"))
	await smoke.checkpoint("pack_recovered")

	# Build mode: open the bar, put up a wall, look at it, take it down.
	for id in ["wood", "stone", "sticks", "scrap"]:
		p.bag.add(id, 120)
	await smoke.tap("build")
	await smoke.frames(3)
	if not build_bar.open:
		smoke.fail("B did not open the build bar")
	build_bar.selected = build_bar.cards().find("woodWall")
	# A tile the wall can actually go on, due east so that walking into it
	# below means something: beside the camp shack, "two to the right" is as
	# likely to be the shack wall as open ground.
	var tile := Vector2i(int(p.pos.x / 32) + 2, int(p.pos.y / 32))
	for i in range(2, 6):
		var t := Vector2i(int(p.pos.x / 32) + i, int(p.pos.y / 32))
		if sim.structs.can_place(sim, "woodWall", t.x, t.y, p).ok:
			tile = t
			break
	var spot := Vector2(tile.x * 32 + 16, tile.y * 32 + 16)
	# Point the cursor at the tile in the world and let it settle: the scene
	# recomputes the hovered tile from the real mouse every physics frame, and
	# the camera leads toward the cursor, so one warp is a moving target.
	for i in range(12):
		smoke_aim(spot)
		await smoke.frames(2)
		if build_bar.check.ok and build_bar.hover_tile == tile:
			break
	if not build_bar.check.ok:
		smoke.fail("the ghost says the wall cannot go there: %s" % build_bar.check.reason)
	await smoke_click(get_viewport().get_canvas_transform() * spot)
	await smoke.frames(3)
	var wall := sim.structs.at_tile(tile.x, tile.y)
	if wall.is_empty():
		smoke.fail("clicking in build mode did not put up a wall")
	await smoke.checkpoint("built_a_wall")

	# It is solid: walking into it stops you.
	if not wall.is_empty():
		var before_x := p.pos.x
		await smoke.hold("move_right", 60)
		if p.pos.x > wall.pos.x:
			smoke.fail("walked straight through the wall")
		if p.pos.x <= before_x:
			smoke.fail("did not walk toward the wall at all")
		# Damage it, then repair it with the tool.
		sim.structs.damage(sim, wall, wall.max_hp * 0.6)
		build_bar.selected = build_bar.cards().find("repair")
		smoke_aim(wall.pos)
		await smoke.frames(3)
		await smoke_click(get_viewport().get_canvas_transform() * wall.pos)
		await smoke.frames(3)
		if wall.hp < wall.max_hp:
			smoke.fail("REPAIR left the wall at %.0f of %.0f" % [wall.hp, wall.max_hp])
		await smoke.checkpoint("repaired_the_wall")
		build_bar.selected = build_bar.cards().find("demolish")
		smoke_aim(wall.pos)
		await smoke.frames(3)
		await smoke_click(get_viewport().get_canvas_transform() * wall.pos)
		await smoke.frames(3)
		if not sim.structs.at_tile(tile.x, tile.y).is_empty():
			smoke.fail("DEMOLISH left the wall standing")
	await smoke.tap("build")
	await smoke.frames(2)
	if build_bar.open:
		smoke.fail("B did not close the build bar")

	# A fight on the highway west of the camp: a walker walks in, the pistol
	# answers. The six-weapon test kit, so every weapon is to hand.
	sim.give_test_kit(p)
	smoke_teleport(120, 160)
	sim.enemies.list.clear()
	await smoke.frames(3)
	var walker := sim.enemies.spawn("walker", p.pos + Vector2(220, 0), true)
	await smoke.frames(20)
	await smoke.checkpoint("walker_approaches")
	await smoke.tap("slot4")
	if p.weapon().id != "pistol":
		smoke.fail("slot 4 should be the pistol, holding %s" % p.weapon().id)
	var frames := 0
	Input.action_press("fire")
	while not walker.dead and frames < 240:
		smoke_aim(walker.pos)
		await smoke.frames(1)
		frames += 1
	Input.action_release("fire")
	if not walker.dead:
		smoke.fail("the walker survived %d frames of pistol fire (hp %.0f)" % [frames, walker.hp])
	if sim.stats.kills < 1:
		smoke.fail("no kill was counted")
	await smoke.checkpoint("walker_shot")

	# A raid, forced: the warning, then the first wave on the ring.
	Raid.start(sim)
	sim.raid.timer = 0.5
	await smoke.frames(120)
	if sim.raid == null or sim.raid.alive_count(sim) == 0:
		smoke.fail("the raid's first wave never arrived")
	await smoke.checkpoint("raid_wave")
	if sim.raid != null:
		sim.raid.force_end(sim)
	await smoke.frames(5)
	await smoke.checkpoint("raid_over")
