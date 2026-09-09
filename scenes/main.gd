extends Node2D
## The root scene. Builds the simulation and the nodes that draw it, gathers
## the local player's intent every physics step, ticks the sim, drains its
## events into the effects and the HUD, and moves the camera. Nothing here
## changes game state except through Intent.

const WORLD_SEED := 20240917
## The slot the smoke run writes to, deliberately outside `Saves.MAX_SLOTS`.
## `user://` is shared with the real game, and a headless run that claimed the
## first free slot would land on somebody's save.
const SMOKE_SLOT := 93

var sim: GameSim
var terrain: TerrainRenderer
var props_below: PropRenderer
var props_above: PropRenderer
var enemy_view: EnemyView
var pickup_view: PickupView
var structure_view: StructureView
var fx: FxView
var lights: LightView
var survivor_view: SurvivorView
var vehicle_view: VehicleView
var player_view: PlayerView
var camera: Camera2D
var hud: Hud
var map: MapScreen
var ears: SfxView
var inventory: InventoryScreen
var build_bar: BuildBar
var menu: MenuScreen
var shake := 0.0

## Co-op (Phase 5). `me` is the local player whatever seat it holds; every
## screen and view that used to assume seat 0 is pointed at it. The host
## session and the socket hub exist only while hosting; the guest session
## only while joined; `role` says which loop `_physics_process` runs.
var me: PlayerSim
var role := "solo"                  # solo / host / guest / joining
var net_host: NetHost = null
var net_guest: NetGuest = null
var hub: EnetHub = null
## The router's answer to "open the port": the cheap way onto the internet.
var door: NetDoor = null
var prefs := {}
var _join_t := 0.0
## An in-process guest the smoke run pumps through a loopback, so the
## co-op path is exercised by the real scene without a second machine.
var smoke_guest: NetGuest = null
var _shake_rng := RandomNumberGenerator.new()

## The slot this game belongs to, or -1 for a run with no home. Autosave and
## QUIT TO TITLE both need to know where to write, and "nowhere" is a real
## answer — a smoke run has no slot and must not create one.
var slot := -1
var _autosave_t := 0.0
## True while the title screen is up: the world exists behind it, but nothing
## steps and nothing reads the keyboard.
var at_title := false


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
	vehicle_view = VehicleView.new(sim)
	add_child(vehicle_view)
	survivor_view = SurvivorView.new(sim)
	add_child(survivor_view)
	player_view = PlayerView.new(sim)
	add_child(player_view)
	props_above = PropRenderer.new(sim, true)
	add_child(props_above)
	fx = FxView.new(sim)
	add_child(fx)
	# Last of the world nodes: its CanvasModulate darkens the whole canvas and
	# its lights add back on top of that.
	lights = LightView.new(sim)
	add_child(lights)

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
	# Above the HUD, below the screens: the map is part of the world you are
	# looking at, and the pack is something you opened over it.
	map = MapScreen.new(sim)
	layer.add_child(map)
	ears = SfxView.new(sim)
	inventory = InventoryScreen.new(sim)
	layer.add_child(inventory)
	build_bar = BuildBar.new(sim)
	layer.add_child(build_bar)
	structure_view.build_bar = build_bar
	menu = MenuScreen.new()
	menu.chose.connect(_on_menu)
	layer.add_child(menu)
	# A smoke run must not touch this machine's identity file (§8: every
	# `user://` path a headless run can write is redirected).
	if Smoke.enabled:
		NetPrefs.STORE = "user://smoke/net.json"
	prefs = NetPrefs.load()
	menu.fields.address = String(prefs.address)
	menu.fields.name = String(prefs.name)
	menu.fields.password = String(prefs.password)
	menu.net.port = Config.NET.port
	_set_local(sim.players[0])
	# The smoke run drives the game directly and has no business clicking
	# through a title screen, so it starts in the world it was given. Everybody
	# else gets a front door.
	if Smoke.enabled:
		menu.visible = false
	else:
		_enter_title()
	print("boot: world %d ms, terrain %d ms, props %d, containers %d" % [t1 - t0, t2 - t1, sim.world.props.size(), sim.world.containers.size()])


func _physics_process(dt: float) -> void:
	# The menu owns everything while it is up. The world is still there — a
	# pause menu is drawn over a live game — but nothing steps and nothing
	# reads the keyboard, so Escape is the only way back and the horde is not
	# eating you while you read the controls.
	if menu.visible:
		# The menu owns Escape while it is up, and knows what one step out of
		# where it is means: cancel a rebind, leave a subpage, close the pause
		# menu. Only the title screen has nothing to back out of.
		if Input.is_action_just_pressed("pause"):
			menu.back()
		# The wire does not pause. A guest keeps telling the host it is
		# holding nothing; a host with guests keeps the world running for
		# them; a dial in progress keeps dialling.
		_net_menu_step(dt)
		return

	_tick_autosave(dt)

	# Polled rather than handled as an event, like every other key here: the
	# smoke run presses actions through `Input`, which sets the action state
	# without ever synthesising an InputEvent.
	if Input.is_action_just_pressed("inventory"):
		inventory.mode = "pack"
		inventory.toggle()
		if inventory.visible and build_bar.open:
			build_bar.toggle()
	elif Input.is_action_just_pressed("crafting"):
		# C is crafting, but crafting is a tab of the pack rather than a
		# screen of its own — so C opens the pack on that tab.
		if inventory.visible and inventory.mode == "craft":
			inventory.toggle()
		else:
			inventory.mode = "craft"
			inventory.visible = true
			if build_bar.open:
				build_bar.toggle()
	elif Input.is_action_just_pressed("character"):
		# K is the character sheet, on the same argument as C: it is a tab of
		# the pack, not a screen of its own.
		if inventory.visible and inventory.mode == "char":
			inventory.toggle()
		else:
			inventory.mode = "char"
			inventory.visible = true
			if build_bar.open:
				build_bar.toggle()
	elif Input.is_action_just_pressed("map"):
		# The town map is a panel over a running world, like the pack: reading it
		# is not a time-out, and the markers on it are live for that reason.
		map.toggle()
		if map.open and build_bar.open:
			build_bar.toggle()
	elif Input.is_action_just_pressed("build") and not inventory.visible and not map.open:
		# Same rule as the pack: an open screen closes build mode, and build mode
		# does not open behind one. Without the map here, B put the ghost and the
		# click handler back on a screen you cannot see the world through — you
		# could place, repair and salvage behind the town map.
		build_bar.toggle()
	elif Input.is_action_just_pressed("pause"):
		# Escape closes what is open, innermost first, and only opens the pause
		# menu once there is nothing left to close.
		if inventory.visible:
			inventory.toggle()
		elif map.open:
			map.toggle()
		elif build_bar.open:
			build_bar.toggle()
		else:
			menu.over_game = true
			menu.came_from = MenuScreen.Page.PAUSE
			menu.open(MenuScreen.Page.PAUSE)
	elif Input.is_action_just_pressed("quick_save"):
		_save_current()
	elif Input.is_action_just_pressed("quick_load"):
		_quick_load()

	var intent := me.intent
	# An open panel owns the mouse: you can still walk, but a click belongs to
	# the screen you are looking at rather than to the gun in your hand.
	LocalInput.gather(intent, self, inventory.visible or build_bar.open or map.open)
	if build_bar.open:
		build_bar.update_hover(get_global_mouse_position())
		# One click, one action — except REPAIR, which is meant to be swept
		# along a wall. It only fires on a piece that is actually damaged, so
		# holding it over one already fixed does nothing.
		var held_sweep: bool = build_bar.sweeps() and build_bar.check.ok and Input.is_action_pressed("fire")
		if Input.is_action_just_pressed("fire") or held_sweep:
			build_bar.click(get_viewport().get_mouse_position())
		if Input.is_action_just_pressed("wheel_down"):
			build_bar.cycle(1)
		elif Input.is_action_just_pressed("wheel_up"):
			build_bar.cycle(-1)
		build_bar.fill_intent(intent)
	if role == "guest":
		# No `sim.tick` on a guest: the mirror is the host's picture, and the
		# only thing this machine simulates is its own next step.
		net_guest.poll()
		net_guest.tick(dt)
		_after_guest_step()
		return
	_host_step(dt)


## One simulation step, and — while hosting — the wire around it: what the
## guests want goes in before the step, what happened comes out after it.
func _host_step(dt: float) -> void:
	if net_host == null:
		sim.tick(dt)
		return
	if hub != null:
		hub.poll()
		for id in hub.joined:
			if hub.links.has(id):
				net_host.attach(hub.links[id])
		hub.joined.clear()
		hub.left.clear()
	net_host.poll()
	sim.tick(dt)
	net_host.after_tick(dt)
	if smoke_guest != null:
		smoke_guest.poll()
		smoke_guest.tick(dt)


## What a guest checks after every step: whether the renderers have to be
## told about a felled tree, and whether the host is still there.
func _after_guest_step() -> void:
	if net_guest.world_dirty:
		net_guest.world_dirty = false
		props_below.rebuild()
		props_above.rebuild()
	if net_guest.status != "joined":
		# The mirror is a stale copy of somebody else's world: back to the
		# title, with the reason on the JOIN page and the address still there.
		var why := net_guest.reason
		_enter_title()
		menu.net.error = "The host left." if why.is_empty() else why
		menu.came_from_net = MenuScreen.Page.TITLE
		menu.open(MenuScreen.Page.JOIN)


## The wire while a menu is up.
func _net_menu_step(dt: float) -> void:
	match role:
		"guest":
			net_guest.poll()
			net_guest.tick(dt, true)
			_after_guest_step()
		"host":
			# The door stays open while the host reads the menu: a dial has to
			# land even if nobody else is here yet.
			if hub != null:
				hub.poll()
			# Guests are playing: the world goes on without the host's hands
			# on it. Alone, a pause is a pause.
			if net_host.connected_count() > 0 or (hub != null and not hub.joined.is_empty()):
				NetProtocol.clear_intent(me.intent)
				_host_step(dt)
		"joining":
			_join_step(dt)


## Loading rebuilds the simulation in place. Every view holds the same
## `sim` reference and reads it fresh each frame, so the only things that
## have to be told are the ones that cached a player: the screens and the
## player's own view.
func _load_slot(which: int) -> bool:
	var r := SaveGame.load_from(sim, which)
	if not r.ok:
		sim.notify(r.reason, "#c96a5a", true)
		return false
	var p := sim.players[0]
	_set_local(p)
	inventory.visible = false
	# Through `toggle`, not the flag: a Control keeps what it last drew, and
	# the scene stops redrawing a closed bar.
	if build_bar.open:
		build_bar.toggle()
	# The world is a new object. The terrain layers and the prop renderers
	# both cached the old one — the props by bucketing its dictionaries, so
	# without this the view goes on drawing a container the restored world
	# says is still full.
	terrain.build(sim.world)
	props_below.rebuild()
	props_above.rebuild()
	camera.position = p.pos
	sim.notify("Loaded", "#b7e08a", true)
	return true


## Everything a new world invalidates. `_load_slot` does the same work for a
## restored one; NEW GAME needs it too, because the world object is replaced
## either way and the renderers cache it.
func _rebuild_views() -> void:
	var p := sim.players[0]
	_set_local(p)
	inventory.visible = false
	if build_bar.open:
		build_bar.toggle()
	map.open = false
	terrain.build(sim.world)
	props_below.rebuild()
	props_above.rebuild()
	camera.position = p.pos


## Everything that has to know which player is this machine's. One place,
## because the list is long and a view left pointing at seat 0 would draw a
## guest's screen from the host's body.
func _set_local(p: PlayerSim) -> void:
	me = p
	player_view.local = p
	hud.player = p
	inventory.player = p
	build_bar.player = p
	map.player = p
	structure_view.player = p
	props_below.player = p
	props_above.player = p
	ears.player = p


func _process(dt: float) -> void:
	for ev in sim.events:
		if ev.t == "shake":
			shake = maxf(shake, ev.amount)
		elif ev.t == "open_store":
			# The screen opens for whoever pressed E, and only on their machine.
			if int(ev.get("seat", me.seat)) == me.seat:
				inventory.open_store(Vector2i(ev.tx, ev.ty))
		elif ev.t == "open_boot":
			if me.driving_id == 0:
				inventory.open_boot(int(ev.id))
		fx.on_event(ev)
		lights.on_event(ev)
		hud.on_event(ev)
		ears.on_event(ev)
	sim.events.clear()
	if net_host != null:
		net_host.on_events_cleared()
	_refresh_net_lines()
	NetDoor.reap()
	fx.tick(dt)
	lights.tick()
	hud.tick(dt)
	shake = maxf(0.0, shake - dt * 22.0)
	_update_camera(dt)
	props_below.queue_redraw()
	props_above.queue_redraw()
	pickup_view.queue_redraw()
	structure_view.queue_redraw()
	if build_bar.open:
		build_bar.queue_redraw()
	inventory.tick()
	if inventory.visible:
		inventory.queue_redraw()
	enemy_view.queue_redraw()
	player_view.queue_redraw()
	fx.queue_redraw()
	hud.queue_redraw()


## Leads toward the cursor so you can see what you are aiming at.
func _update_camera(dt: float) -> void:
	var p := me
	var C := Config.CAMERA
	var mouse := get_global_mouse_position()
	# The camera follows where the player is *drawn*, not where the last
	# physics step left them — otherwise the world judders under a smooth
	# player instead of the player juddering across a smooth world.
	var at := Util.render_pos(p.prev_pos, p.pos)
	var lead := Vector2(
		clampf((mouse.x - at.x) * C.lead, -C.lead_max, C.lead_max),
		clampf((mouse.y - at.y) * C.lead, -C.lead_max, C.lead_max))
	camera.position = camera.position.lerp(at + lead, Util.smooth(C.follow, dt))
	if shake > 0.0:
		camera.offset = Vector2(_shake_rng.randf_range(-shake, shake), _shake_rng.randf_range(-shake, shake))
	else:
		camera.offset = Vector2.ZERO


# ------------------------------------------------------------------ smoke --

func smoke_state() -> Dictionary:
	var p := sim.players[0]
	var loc := sim.world.location_at_px(p.pos.x, p.pos.y)
	return {
		"role": role, "players": sim.present_players().size(),
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


## Which pack slot holds `id`, for the smoke run to click on.
func _smoke_bag_index(id: String) -> int:
	var p := sim.players[0]
	for i in range(p.bag.size()):
		if p.bag.id_at(i) == id:
			return i
	return 0


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
		# REPAIR is the tool you may hold: press and keep holding, and the
		# sweep fixes what is under the cursor.
		# Settle the cursor the same way the placement step does. The camera
		# leads toward the mouse, so one warp and a fixed wait is a moving
		# target: it happened to land before Phase 4 changed where the player
		# is standing by a few pixels, and then it did not.
		var wall_tile := Vector2i(wall.tx, wall.ty)
		for i in range(12):
			smoke_aim(wall.pos)
			await smoke.frames(2)
			if build_bar.check.ok and build_bar.hover_tile == wall_tile:
				break
		if not build_bar.check.ok or build_bar.hover_tile != wall_tile:
			smoke.fail("could not put the REPAIR cursor on the wall: hover=%s check=%s" %
				[str(build_bar.hover_tile), str(build_bar.check)])
		Input.action_press("fire")
		await smoke.frames(10)
		Input.action_release("fire")
		await smoke.frames(3)
		if wall.hp < wall.max_hp:
			smoke.fail("holding REPAIR left the wall at %.0f of %.0f" % [wall.hp, wall.max_hp])
		var wood_after := p.count_res("wood")
		await smoke.frames(10)
		if p.count_res("wood") != wood_after:
			smoke.fail("the sweep kept billing an intact wall")
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

	# Crafting: the tab of the pack, not a screen of its own. Make a hatchet
	# out of what the ground gives up.
	#
	# The pack is emptied first because the build section stuffed it with
	# four hundred units of material to have something to build with, and a
	# survivor carrying half a quarry cannot pick up a hatchet either — the
	# weight rule applies to a crafted weapon like everything else.
	p.bag.clear_all()
	for entry in [["sticks", 20], ["stone", 20], ["fiber", 20]]:
		p.bag.add(entry[0], entry[1])
	await smoke.tap("crafting")
	await smoke.frames(3)
	if not inventory.visible or inventory.mode != "craft":
		smoke.fail("C did not open the craft tab")
	await smoke.checkpoint("craft_tab")
	var axes := p.count_carried("axe")
	await smoke_click(inventory.recipe_centre("axe"))
	await smoke.frames(3)
	if p.count_carried("axe") <= axes:
		smoke.fail("clicking the Hatchet row crafted nothing")
	await smoke.tap("crafting")
	await smoke.frames(2)

	# Levelling: the sheet opens on K, an attribute takes a point, and the
	# point moves a stat the rest of the game reads. Crafting the hatchet
	# above has already paid some XP; this tops it up to a certain level.
	Progression.add_xp(sim, p, 3000.0)
	if p.level < 2 or p.skill_points < 1:
		smoke.fail("3000 XP did not level anyone up (level %d, %d points)" % [p.level, p.skill_points])
	await smoke.tap("character")
	await smoke.frames(3)
	if not inventory.visible or inventory.mode != "char":
		smoke.fail("K did not open the character sheet")
	await smoke.checkpoint("character_sheet")

	# The first click selects Constitution's tree, the second spends on it.
	var hp_before := p.max_hp
	var points_before := p.skill_points
	await smoke_click(inventory.char_row_centre("con"))
	await smoke.frames(2)
	if inventory.char_attr != "con":
		smoke.fail("clicking Constitution did not open its tree")
	if p.skill_points != points_before:
		smoke.fail("merely looking at an attribute cost a point")
	await smoke_click(inventory.char_row_centre("con"))
	await smoke.frames(3)
	if p.max_hp <= hp_before:
		smoke.fail("raising Constitution did not raise max health (%d -> %d)" % [hp_before, p.max_hp])
	if p.skill_points != points_before - 1:
		smoke.fail("raising an attribute did not cost exactly one point")
	await smoke.checkpoint("point_spent")
	await smoke.tap("character")
	await smoke.frames(2)

	# A chest, and the two-panel screen that opens when you press E at it.
	for entry in [["wood", 30], ["sticks", 20], ["stone", 40]]:
		p.bag.add(entry[0], entry[1])
	var chest_tile := Vector2i(-1, -1)
	for i in range(2, 6):
		var t := Vector2i(int(p.pos.x / 32) + i, int(p.pos.y / 32))
		if sim.structs.can_place(sim, "chest", t.x, t.y, p).ok:
			chest_tile = t
			break
	if chest_tile.x < 0:
		smoke.fail("nowhere to put a chest")
	else:
		sim.structs.place(sim, "chest", chest_tile.x, chest_tile.y, p)
		p.pos = Vector2(chest_tile.x * 32 + 16, chest_tile.y * 32 + 48)
		await smoke.frames(3)
		await smoke.tap("interact")
		await smoke.frames(4)
		if not inventory.visible or inventory.mode != "store":
			smoke.fail("E at the chest did not open it")
		await smoke.checkpoint("chest_open")
		var stored := p.count_res("stone")
		await smoke_click(inventory.cell_centre("bag", _smoke_bag_index("stone")), false)
		await smoke.frames(2)
		# DEPOSIT ALL is the button the haul is actually for.
		await smoke_click(Vector2(inventory._panel().position.x + 84, inventory._panel().position.y + inventory._panel().size.y - 84))
		await smoke.frames(3)
		var s := sim.structs.at_tile(chest_tile.x, chest_tile.y)
		if s.store.used() == 0:
			smoke.fail("DEPOSIT ALL put nothing in the chest")
		if p.count_res("stone") >= stored:
			smoke.fail("the stone did not leave the pack")
		await smoke.checkpoint("chest_filled")
		await smoke.tap("inventory")
		await smoke.frames(2)

	# Save, break something, load it back.
	await smoke.tap("quick_save")
	await smoke.frames(3)
	var saved_axes := p.count_carried("axe")
	var saved_pos := p.pos
	p.bag.clear_all()
	p.hotbar.clear_all()
	smoke_teleport(200, 200)
	await smoke.frames(3)
	await smoke.tap("quick_load")
	await smoke.frames(10)
	var q := sim.players[0]
	if q.count_carried("axe") != saved_axes:
		smoke.fail("the hatchet did not survive the save: %d of %d" % [q.count_carried("axe"), saved_axes])
	if q.pos.distance_to(saved_pos) > 4.0:
		smoke.fail("loaded %0.f px from where it saved" % q.pos.distance_to(saved_pos))
	if sim.structs.at_tile(chest_tile.x, chest_tile.y).is_empty():
		smoke.fail("the chest did not come back")
	await smoke.checkpoint("loaded")

	# A fight on the highway west of the camp: a walker walks in, the pistol
	# answers. The six-weapon test kit, so every weapon is to hand.
	sim.give_test_kit(sim.players[0])
	p = sim.players[0]
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

	# Night, and the light you carry into it. The clock is wound forward
	# rather than waited out: a day is nine minutes and the smoke run is not.
	sim.clock.t = 0.60
	sim.clock.phase = "day"
	await smoke.frames(4)
	await smoke.checkpoint("dusk")
	sim.clock.t = 0.82
	await smoke.frames(4)
	if not sim.clock.is_dark():
		smoke.fail("0.82 through the day is not dark (alpha %.2f)" % sim.clock.darkness().alpha)
	var night := sim.night_factors()
	if night.density <= 1.5 or night.threat <= 1.5:
		smoke.fail("night is not worth anything: %s" % str(night))
	await smoke.checkpoint("night")

	# A torch in the off-hand, lit. This is what Phase 3a's light fields were
	# put there for and the first time anything has read them.
	p.bag.add("gear:torch", 1)
	p.equip["offhand"] = "torch"
	Equipment.after_equip_change(p)
	Equipment.toggle_light(sim, p)
	await smoke.frames(4)
	if not p.lit:
		smoke.fail("the torch did not light")
	await smoke.checkpoint("torch_lit")

	# Fire: light the scenery and watch it burn. Planted rather than found,
	# so the checkpoint does not depend on what the generator put nearby.
	var ftx := floori(p.pos.x / 32) + 2
	var fty := floori(p.pos.y / 32)
	for i in range(4):
		# `si` is the sprite index every drawn pine has; without it the
		# renderer logged an error per prop per frame until they burned.
		var prop := {"kind": "pine", "si": 0, "tx": ftx + i, "ty": fty,
			"x": (ftx + i) * 32 + 16.0, "y": fty * 32 + 16.0, "hp": 40.0, "solid": false}
		sim.world.props.append(prop)
		sim.world.prop_grid[fty * Config.WORLD_TILES + ftx + i] = prop
		sim.fire.ignite_prop(sim, prop)
	props_above.rebuild()
	props_below.rebuild()
	await smoke.frames(6)
	if sim.fire.list.size() < 4:
		smoke.fail("the treeline did not catch: %d alight" % sim.fire.list.size())
	await smoke.checkpoint("fire")

	# The crew. Charisma and a bunk are both required, so the smoke has to
	# supply both before anyone will follow.
	sim.clock.t = 0.30
	p.attrs["cha"] = 10
	Perks.recompute_stats(p)
	for entry in [["wood", 200], ["cloth", 120], ["scrap", 200], ["stone", 120]]:
		p.bag.add(entry[0], entry[1])
	var btx := floori(p.pos.x / 32) - 3
	var bty := floori(p.pos.y / 32) + 2
	sim.structs.place(sim, "stash", btx, bty, p)
	sim.structs.place(sim, "bunk", btx + 1, bty, p)
	if sim.crew.cap(sim) < 1:
		smoke.fail("a bunk and Charisma 10 is still no room: %s" % str(sim.crew.limits(sim)))
	await smoke.frames(3)

	# Take somebody in, off the map and into the roster.
	if sim.crew.rescues.is_empty():
		smoke.fail("the world seeded nobody to find")
	else:
		var rescue: Dictionary = sim.crew.rescues[0]
		var out_there := sim.crew.rescues.size()
		var joined := sim.crew.recruit(sim, rescue, p)
		if joined == null:
			smoke.fail("nobody joined: %s" % sim.crew.recruit_refusal(sim))
		elif sim.crew.rescues.size() != out_there - 1:
			smoke.fail("they joined but are still out there")
		else:
			joined.pos = p.pos + Vector2(70, 0)
	await smoke.frames(4)
	await smoke.checkpoint("crew_joined")

	# The roster, and reassigning what they do all day.
	await smoke.tap("inventory")
	await smoke.frames(2)
	inventory.mode = "crew"
	await smoke.frames(3)
	if not inventory.visible or inventory.mode != "crew":
		smoke.fail("the roster did not open")
	await smoke.checkpoint("roster")

	var member := sim.crew.alive()[0] if not sim.crew.alive().is_empty() else null
	if member != null:
		if not sim.crew.assign_job(sim, member, "builder"):
			smoke.fail("could not put them on Builder duty")
		if member.job != "builder":
			smoke.fail("the job did not stick")
		await smoke.frames(3)
		await smoke.checkpoint("crew_reassigned")
	await smoke.tap("inventory")
	await smoke.frames(2)

	# A car. Find one, get into it, drive it, and leave it somewhere else.
	var car := {}
	for cand in sim.cars.list:
		if not cand.destroyed:
			car = cand
			break
	if car.is_empty():
		smoke.fail("the world generated no cars at all")
	else:
		# Open it and fill the tank rather than hunting the map for a key —
		# the locks have their own tests; this is about driving.
		car.locked = false
		car.hotwired = true
		car.fuel = Config.CAR.fuel_max
		p.pos = car.pos + Vector2(0, 50)
		await smoke.frames(3)
		await smoke.checkpoint("a_car")

		if not sim.cars.enter(sim, p, car):
			smoke.fail("could not get into the car")
		if p.driving_id != int(car.id):
			smoke.fail("in the car but not driving it")
		var from: Vector2 = car.pos
		var fuel_before: float = car.fuel
		# The real key, not the intent: `LocalInput.gather` rewrites the intent
		# from the keyboard every physics frame, so setting it here is undone
		# before the car ever reads it.
		await smoke.hold("move_up", 90)
		await smoke.frames(3)
		if car.pos.distance_to(from) < 30.0:
			smoke.fail("the car did not go anywhere (%.0f px)" % car.pos.distance_to(from))
		if car.fuel >= fuel_before:
			smoke.fail("driving burned no fuel")
		if p.pos.distance_to(car.pos) > 1.0:
			smoke.fail("the driver did not ride with the car")
		await smoke.checkpoint("driving")

		if not sim.cars.exit(sim, p):
			smoke.fail("could not get out")
		if p.driving_id != 0:
			smoke.fail("still driving after getting out")
		await smoke.frames(3)
		await smoke.checkpoint("parked")



	# The ears. Everything above has been making noise; this is the check that
	# it reached a voice rather than a silent bank — the audio equivalent of
	# reading the screenshot instead of the variable.
	if not Sfx.has("pistol"):
		smoke.fail("the sound bank never got built")
	var voiced := 0
	for cue in Config.SFX:
		Sfx._last.clear()
		if Sfx.play(cue):
			voiced += 1
	if voiced != Config.SFX.size():
		smoke.fail("only %d of %d cues reached a voice" % [voiced, Config.SFX.size()])
	await smoke.frames(2)
	var heard := 0
	for pl in Sfx._players:
		if pl.playing:
			heard += 1
	if heard == 0:
		smoke.fail("nothing is actually coming out of a player")

	# Muting is a setting on the menu, and it has to stop the sound.
	Sfx.set_muted(true)
	Sfx._last.clear()
	if Sfx.play("pistol"):
		smoke.fail("muted and still firing")
	Sfx.set_muted(false)
	Sfx._last.clear()
	if not Sfx.play("pistol"):
		smoke.fail("unmuting did not bring it back")
	await smoke.checkpoint("sound")

	# The map. The corner one has been on screen since the first checkpoint;
	# this is the one behind M, and the districts it has filled in.
	var found := 0
	for l in sim.world.locations:
		if l.discovered:
			found += 1
	if found < 2:
		smoke.fail("walked seven districts and found %d" % found)
	await smoke.tap("map")
	await smoke.frames(4)
	if not map.open:
		smoke.fail("M did not open the town map")
	await smoke.checkpoint("town_map")

	# B behind the map does nothing. Pressed, not called: the whole point is
	# that the key reaches the branch that refuses it.
	var built_before := sim.structs.list.size()
	await smoke.tap("build")
	await smoke.frames(3)
	if build_bar.open:
		smoke.fail("B opened build mode behind the town map")
	if sim.structs.list.size() != built_before:
		smoke.fail("something got built behind the map")

	# Sixth Sense is the reason the reveal radius is a number rather than
	# "all of them", so the map has to change when the perk is bought.
	var near_count := map._revealed(p).size()
	p.perks["sixthSense"] = 1
	Perks.recompute_stats(p)
	await smoke.frames(2)
	if map._revealed(p).size() < near_count:
		smoke.fail("Sixth Sense showed fewer, not more")
	await smoke.checkpoint("sixth_sense")

	await smoke.tap("pause")
	await smoke.frames(3)
	if map.open:
		smoke.fail("Escape did not close the map before opening anything else")
	if menu.visible:
		smoke.fail("Escape opened the pause menu with the map still up")
	p.perks.erase("sixthSense")
	Perks.recompute_stats(p)

	# The front door. The smoke run starts in the world rather than at the
	# title, so this drives the menu directly — but through the same rows and
	# the same signal a click goes through, not by calling the handlers.
	var test_slot := SMOKE_SLOT
	Saves.delete(test_slot)

	# Escape with nothing open is the pause menu.
	await smoke.tap("pause")
	await smoke.frames(4)
	if not menu.visible or menu.page != MenuScreen.Page.PAUSE:
		smoke.fail("Escape did not open the pause menu")
	await smoke.checkpoint("paused")

	# The world is frozen behind it: nothing steps while the menu is up.
	var frozen_at := sim.time
	await smoke.frames(20)
	if not is_equal_approx(sim.time, frozen_at):
		smoke.fail("the world kept running behind the pause menu")

	# CONTROLS, and back again to where it came from.
	if not smoke_click_menu("controls_page"):
		smoke.fail("no CONTROLS row on the pause menu")
	await smoke.frames(3)
	if menu.page != MenuScreen.Page.CONTROLS:
		smoke.fail("CONTROLS did not open")
	await smoke.checkpoint("controls")

	# Rebinding: click the row, press a key for real, and the InputMap moves
	# with it. The key goes through the viewport rather than into `_gui_input`,
	# because "the menu never gets the key" is exactly the bug this step exists
	# to catch — the first cut called the handler and missed it.
	if not smoke_click_menu("bind", -1, "map"):
		smoke.fail("no rebind row for the map key")
	await smoke.frames(2)
	if menu.rebinding != "map":
		smoke.fail("clicking the row did not start a rebind")
	get_viewport().push_input(rebound_pressed(KEY_N))
	await smoke.frames(2)
	if not menu.rebinding.is_empty():
		smoke.fail("the menu is still waiting for a key it was already sent")
	if KeyBinds.codes_for("map") != [KEY_N]:
		smoke.fail("rebinding did not take: %s" % str(KeyBinds.codes_for("map")))
	if KeyBinds.primary_label("map") != "N":
		smoke.fail("the prompt did not follow the binding")
	KeyBinds.reset_all()
	await smoke.checkpoint("rebound")

	# Escape backs out of a subpage rather than doing nothing.
	await smoke.tap("pause")
	await smoke.frames(3)
	if menu.page != MenuScreen.Page.PAUSE:
		smoke.fail("Escape on CONTROLS did not go back to the pause menu")
	if not smoke_click_menu("controls_page"):
		smoke.fail("no CONTROLS row on the pause menu")
	await smoke.frames(2)
	if not smoke_click_menu("back"):
		smoke.fail("no BACK row on CONTROLS")
	await smoke.frames(3)
	if menu.page != MenuScreen.Page.PAUSE:
		smoke.fail("BACK did not return to the pause menu")

	# SAVE writes a real slot with a summary the title screen can read.
	slot = test_slot
	if not smoke_click_menu("save"):
		smoke.fail("no SAVE row")
	await smoke.frames(4)
	var listed := {}
	for s in Saves.list():
		if int(s.slot) == test_slot:
			listed = s
	if listed.is_empty():
		smoke.fail("SAVE wrote no slot")
	elif int(listed.day) != sim.clock.day:
		smoke.fail("the summary does not match the game")

	# QUIT TO TITLE goes back to the front door with the world still loaded.
	if not smoke_click_menu("quit_to_title"):
		smoke.fail("no QUIT TO TITLE row")
	await smoke.frames(4)
	if not at_title or menu.page != MenuScreen.Page.TITLE:
		smoke.fail("did not land on the title screen")
	await smoke.checkpoint("title")

	# LOAD GAME lists what was just written, and opening it comes back in.
	if not smoke_click_menu("load_page"):
		smoke.fail("no LOAD GAME row")
	await smoke.frames(3)
	await smoke.checkpoint("load_list")
	if not smoke_click_menu("load", test_slot):
		smoke.fail("the slot just saved is not in the list")
	await smoke.frames(6)
	if at_title or menu.visible:
		smoke.fail("loading did not leave the title screen")
	await smoke.checkpoint("loaded_from_title")
	Saves.delete(test_slot)

	# Co-op, through this scene's real host loop: a guest session joined over
	# a loopback and pumped in-process. No socket — the socket has its own
	# test — but everything above it is the path a friend takes: the world as
	# a payload, a seat, a second body on screen, intent up, snapshots down.
	p = sim.players[0]
	var ends: Array = NetLink.Loopback.pair()
	net_host = NetHost.new(sim, "Host")
	net_host.attach(ends[0])
	role = "host"
	smoke_guest = NetGuest.new(ends[1], "smoke-guest", "Bex")
	await smoke.frames(20)
	if not smoke_guest.joined():
		smoke.fail("the loopback guest never joined: %s %s" % [smoke_guest.status, smoke_guest.reason])
	else:
		var gp := sim.player_by_identity("smoke-guest")
		if gp == null:
			smoke.fail("the host has no seat for the guest")
		else:
			var beside := sim.world.unstick(p.pos + Vector2(64, 0), gp.r)
			gp.pos = beside
			gp.prev_pos = beside
			smoke_guest.me.pos = beside
			smoke_guest.me.prev_pos = beside
			await smoke.frames(6)
			await smoke.checkpoint("coop_joined")
			var from := gp.pos
			smoke_guest.me.intent.mx = 1.0
			smoke_guest.me.intent.aim = beside + Vector2(200, 0)
			await smoke.frames(60)
			smoke_guest.me.intent.mx = 0.0
			if gp.pos.x - from.x < 40.0:
				smoke.fail("the guest's intent did not move their player on the host: dx=%.1f" % (gp.pos.x - from.x))
			if smoke_guest.me.pos.distance_to(gp.pos) > Config.NET.snap_over:
				smoke.fail("guest prediction drifted %.0f px from the host" % smoke_guest.me.pos.distance_to(gp.pos))
			if smoke_guest.sim.players.size() != sim.players.size():
				smoke.fail("the mirror's roster does not match the host's")
			await smoke.checkpoint("coop_walked")
			smoke_guest.leave()
			await smoke.frames(6)
			if not gp.away:
				smoke.fail("leaving did not park the guest's character")
			await smoke.checkpoint("coop_left")
	smoke_guest = null
	_stop_hosting()

# --------------------------------------------------------------- the menu --

## What the title screen and the pause menu ask for. The menu knows about rows
## and pages; everything that touches the simulation is here.
func _on_menu(what: String, arg: int) -> void:
	match what:
		"continue", "load":
			_stop_hosting()
			if _load_slot(arg):
				slot = arg
				Saves.mark_current(arg)
				_leave_title()
		"new_confirm":
			if arg < 0:
				return
			_stop_hosting()
			slot = arg
			sim.new_game(WORLD_SEED)
			_rebuild_views()
			# Written down immediately, so a slot the player chose exists on
			# disk before anything can go wrong in it.
			Saves.save_to(sim, slot)
			_leave_title()
		"host_start":
			_start_hosting(arg)
		"host_stop":
			_stop_hosting()
			menu.open(MenuScreen.Page.PAUSE if menu.over_game else MenuScreen.Page.TITLE)
		"copy_address":
			# A public address is a thing you paste to a friend, not retype.
			var text := String(menu.net.public)
			if text.is_empty() and not (menu.net.lan as Array).is_empty():
				text = String(menu.net.lan[0])
			if not text.is_empty():
				DisplayServer.clipboard_set(text)
				sim.notify("Copied %s" % text, "#9fd0ff")
		"join_start":
			_start_join()
		"join_cancel":
			_leave_game()
			menu.net.status = ""
		"leave_game":
			_leave_game()
			_enter_title()
		"delete":
			Saves.delete(arg)
			if slot == arg:
				slot = -1
			menu.queue_redraw()
		"resume":
			menu.close()
		"save":
			_save_current()
		"quit_to_title":
			# Only if it actually got to disk. A full disk turning "save and quit"
			# into "quit" would take the session with it and leave CONTINUE
			# pointing at an older payload.
			if _save_current():
				_stop_hosting()
				_enter_title()
		"quit":
			_stop_hosting()
			_leave_game()
			get_tree().quit()


# ---------------------------------------------------------------- co-op --

## Opens the door. `which` is the menu's `host_arg`: -2 hosts the game
## running now, -3 starts a new one, a slot number loads that save first. A
## guest's characters ride in whichever save this is.
func _start_hosting(which: int) -> void:
	_save_prefs()
	menu.net.error = ""
	if which == -3:
		var free := Saves.first_free()
		if free < 0:
			menu.net.error = "Every save slot is full — delete one first"
			return
		slot = free
		sim.new_game(WORLD_SEED)
		_rebuild_views()
		Saves.save_to(sim, slot)
	elif which >= 0:
		if not _load_slot(which):
			menu.net.error = "That save would not load"
			return
		slot = which
		Saves.mark_current(which)
	_stop_hosting()
	hub = EnetHub.new()
	var err := hub.host(Config.NET.port, Config.NET.max_players - 1)
	if not err.is_empty():
		hub = null
		menu.net.error = err
		return
	var name_ := String(menu.fields.name).strip_edges()
	net_host = NetHost.new(sim, name_ if not name_.is_empty() else "Host", NetProtocol.hash_password(String(menu.fields.password)))
	role = "host"
	sim.notify("Hosting on UDP port %d" % Config.NET.port, "#9fd0ff", true)
	if Config.NET.upnp:
		door = NetDoor.new()
		door.open(Config.NET.port)
	if at_title:
		_leave_title()
	else:
		menu.close()


func _stop_hosting() -> void:
	if net_host != null:
		net_host.stop()
		net_host = null
	if hub != null and role == "host":
		hub.close()
		hub = null
	if door != null:
		door.close()
		door = null
	if role == "host":
		role = "solo"
		if sim != null:
			sim.notify("Stopped hosting", "#8a8f84")


## Dials. The rest happens in `_join_step`, a frame at a time, so the menu
## can show what is going on and CANCEL can mean something.
func _start_join() -> void:
	_save_prefs()
	_leave_game()
	var text := String(menu.fields.address).strip_edges()
	var port: int = Config.NET.port
	var address := text
	var colon := text.rfind(":")
	if colon > 0 and text.substr(colon + 1).is_valid_int():
		address = text.left(colon)
		port = int(text.substr(colon + 1))
	if address.is_empty():
		menu.net.error = "Type the host's address first"
		return
	hub = EnetHub.new()
	var err := hub.join(address, port)
	if not err.is_empty():
		hub = null
		menu.net.error = err
		return
	role = "joining"
	_join_t = 0.0
	menu.net.error = ""
	menu.net.status = "dialling %s:%d…" % [address, port]


func _join_step(dt: float) -> void:
	_join_t += dt
	hub.poll()
	if net_guest == null:
		var link := hub.host_link()
		if link != null:
			var name_ := String(menu.fields.name).strip_edges()
			# The mirror is built into this scene's own `sim`, so every view
			# keeps the reference it already holds.
			net_guest = NetGuest.new(link, String(prefs.identity), name_ if not name_.is_empty() else "Guest",
				NetProtocol.hash_password(String(menu.fields.password)), sim)
			menu.net.status = "connected — waiting for the host…"
		elif not hub.error.is_empty() or _join_t > Config.NET.hello_timeout:
			var why := hub.error if not hub.error.is_empty() else "no answer"
			_leave_game()
			menu.net.error = "Could not reach the host (%s)" % why
		return
	net_guest.poll()
	net_guest.tick(dt, true)
	if net_guest.joined():
		_enter_guest_world()
	elif net_guest.status != "connecting":
		var why := net_guest.reason
		_leave_game()
		menu.net.error = why


## The host's world has arrived in `sim`. Everything that cached the old one
## is rebuilt, the local player becomes the seat the host gave us, and the
## pack screen's commands start going over the wire.
func _enter_guest_world() -> void:
	role = "guest"
	slot = -1
	Actions.guest = net_guest
	terrain.build(sim.world)
	props_below.rebuild()
	props_above.rebuild()
	inventory.visible = false
	if build_bar.open:
		build_bar.toggle()
	map.open = false
	_set_local(net_guest.me)
	camera.position = me.pos
	menu.net.status = ""
	_leave_title()


## Hangs up, whichever side of the dial we were on. The mirror left in `sim`
## is nobody's game: it is never saved, and CONTINUE or NEW GAME replace it.
func _leave_game() -> void:
	Actions.guest = null
	if net_guest != null:
		net_guest.leave()
		net_guest = null
	if hub != null and role != "host":
		hub.close()
		hub = null
	if role == "guest" or role == "joining":
		role = "solo"
	menu.net.status = ""


func _save_prefs() -> void:
	prefs.name = String(menu.fields.name).strip_edges()
	prefs.address = String(menu.fields.address).strip_edges()
	prefs.password = String(menu.fields.password)
	NetPrefs.save(prefs)


## What the menu and the HUD say about the connection, refreshed each frame.
func _refresh_net_lines() -> void:
	menu.net.role = role
	if role == "host" and net_host != null:
		menu.net.guests = net_host.guest_names()
		if door != null:
			door.poll()
			menu.net.door = door.status
			menu.net.public = door.public
		else:
			menu.net.door = ""
			menu.net.public = ""
		menu.net.lan = NetDoor.lan_addresses(Config.NET.port)
		hud.net_line = "hosting  ·  %d connected  ·  ↑%s ↓%s" % [net_host.connected_count(),
			String.humanize_size(net_host.stats.sent), String.humanize_size(net_host.stats.received)]
	elif role == "guest" and net_guest != null:
		menu.net.status = net_guest.host_name
		hud.net_line = "in %s's game  ·  ↑%s ↓%s" % [net_guest.host_name,
			String.humanize_size(net_guest.stats.sent), String.humanize_size(net_guest.stats.received)]
	else:
		menu.net.guests = []
		hud.net_line = ""


func _enter_title() -> void:
	_leave_game()
	at_title = true
	inventory.visible = false
	if build_bar.open:
		build_bar.toggle()
	menu.over_game = false
	menu.came_from = MenuScreen.Page.TITLE
	menu.open(MenuScreen.Page.TITLE)


func _leave_title() -> void:
	at_title = false
	menu.over_game = true
	menu.close()


## Writes the game into its slot, or says why it cannot. A run with no slot —
## a world started with F5 before anything named it — is given one rather than
## silently doing nothing. Returns whether the payload actually reached disk,
## because the one caller that leaves the game afterwards must not.
func _save_current() -> bool:
	if role == "guest":
		sim.notify("Guests do not save — the host's game keeps your character", "#c96a5a", true)
		return false
	if slot < 0:
		# The smoke run writes outside the player's six, for the same reason
		# the tests use 90-92: `user://` is shared with the real game, and a
		# headless run must never land on somebody's first save.
		slot = SMOKE_SLOT if Smoke.enabled else Saves.first_free()
	if slot < 0:
		sim.notify("Every save slot is full — delete one from the title screen", "#c96a5a", true)
		return false
	var r := Saves.save_to(sim, slot)
	sim.notify("Saved" if r.ok else r.reason, "#b7e08a" if r.ok else "#c96a5a", true)
	return r.ok


## F9 reopens the game you are in, not slot 0. With no slot yet it takes the
## same one CONTINUE would — quick load is a shortcut past the title screen,
## so it has to agree with the title screen about which game that is.
func _quick_load() -> void:
	if role == "guest":
		sim.notify("Not while in somebody else's game", "#c96a5a")
		return
	_stop_hosting()
	var which := slot
	if which < 0:
		var s := Saves.latest()
		if s.is_empty():
			sim.notify("Nothing saved yet", "#c96a5a", true)
			return
		which = int(s.slot)
	if _load_slot(which):
		slot = which
		Saves.mark_current(which)
		_autosave_t = 0.0
## A game with a slot writes itself down on a timer. One without does not:
## autosave must never invent a slot behind the player's back.
func _tick_autosave(dt: float) -> void:
	if slot < 0 or role == "guest":
		return
	_autosave_t += dt
	if _autosave_t < Saves.AUTOSAVE_EVERY:
		return
	_autosave_t = 0.0
	var r := Saves.save_to(sim, slot)
	if r.ok:
		sim.notify("Autosaved", "#8a8f84")

## Presses a menu row by id, the way a click does. Returns false when the row
## is not on the page — which is a failure worth reporting rather than a
## silent no-op. `action` picks between the many rows that share an id: every
## binding row is a "bind".
##
## Scrolls to find it, because `_rows()` returns only what is on screen and the
## map binding is twenty rows down a list of twenty-three. `_rows()` clamps
## `scroll` itself, so the bottom of the list is where the clamp stops moving.
func smoke_click_menu(id: String, arg := -1, action := "") -> bool:
	var last := -1
	while true:
		var rows := menu._rows()
		if menu.scroll == last:
			break
		last = menu.scroll
		for r in rows:
			if String(r.id) != id:
				continue
			if arg >= 0 and int(r.arg) != arg:
				continue
			if not action.is_empty() and String(r.get("action", "")) != action:
				continue
			menu._press(r)
			return true
		menu.scroll += 1
	menu.scroll = 0
	return false
## A real key-down event, for pushing through the viewport the way a keyboard
## does.
func rebound_pressed(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	return ev
