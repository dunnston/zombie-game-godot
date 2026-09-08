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
var fx: FxView
var player_view: PlayerView
var camera: Camera2D
var hud: Hud
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
	print("boot: world %d ms, terrain %d ms, props %d, containers %d" % [t1 - t0, t2 - t1, sim.world.props.size(), sim.world.containers.size()])


func _physics_process(dt: float) -> void:
	LocalInput.gather(sim.players[0].intent, self)
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

	# A fight on the highway west of the camp: a walker walks in, the pistol
	# answers. Everything goes through the real input path but the spawn.
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
