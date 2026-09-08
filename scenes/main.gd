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
var lights: LightView
var survivor_view: SurvivorView
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
	survivor_view = SurvivorView.new(sim)
	add_child(survivor_view)
	player_view = PlayerView.new(sim.players[0])
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
	elif Input.is_action_just_pressed("build") and not inventory.visible:
		build_bar.toggle()
	elif Input.is_action_just_pressed("pause"):
		if inventory.visible:
			inventory.toggle()
		elif build_bar.open:
			build_bar.toggle()
	elif Input.is_action_just_pressed("quick_save"):
		var r := SaveGame.save_to(sim, 0)
		sim.notify("Saved" if r.ok else r.reason, "#b7e08a" if r.ok else "#c96a5a", true)
	elif Input.is_action_just_pressed("quick_load"):
		_load_slot(0)

	var intent := sim.players[0].intent
	# An open panel owns the mouse: you can still walk, but a click belongs to
	# the screen you are looking at rather than to the gun in your hand.
	LocalInput.gather(intent, self, inventory.visible or build_bar.open)
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
	sim.tick(dt)


## Loading rebuilds the simulation in place. Every view holds the same
## `sim` reference and reads it fresh each frame, so the only things that
## have to be told are the ones that cached a player: the screens and the
## player's own view.
func _load_slot(slot: int) -> void:
	var r := SaveGame.load_from(sim, slot)
	if not r.ok:
		sim.notify(r.reason, "#c96a5a", true)
		return
	var p := sim.players[0]
	player_view.p = p
	inventory.player = p
	build_bar.player = p
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


func _process(dt: float) -> void:
	for ev in sim.events:
		if ev.t == "shake":
			shake = maxf(shake, ev.amount)
		elif ev.t == "open_store":
			inventory.open_store(Vector2i(ev.tx, ev.ty))
		fx.on_event(ev)
		lights.on_event(ev)
		hud.on_event(ev)
	sim.events.clear()
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
	var p := sim.players[0]
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
		var prop := {"kind": "pine", "tx": ftx + i, "ty": fty,
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
