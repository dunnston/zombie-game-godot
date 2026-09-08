extends Node2D
## The root scene. Builds the simulation and the nodes that draw it, gathers
## the local player's intent every physics step, ticks the sim, and moves
## the camera. Nothing here changes game state except through Intent.

const WORLD_SEED := 20240917

var sim: GameSim
var terrain: TerrainRenderer
var props_below: PropRenderer
var props_above: PropRenderer
var player_view: PlayerView
var camera: Camera2D
var hud: Hud


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
	player_view = PlayerView.new(sim.players[0])
	add_child(player_view)
	props_above = PropRenderer.new(sim, true)
	add_child(props_above)

	camera = Camera2D.new()
	var C := Config.CAMERA
	var z := clampf(get_viewport_rect().size.y / C.view_height, C.min_zoom, C.max_zoom)
	camera.zoom = Vector2(z, z)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = Config.WORLD_SIZE
	camera.limit_bottom = Config.WORLD_SIZE
	camera.position = sim.players[0].pos
	add_child(camera)
	camera.make_current()

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new(sim)
	layer.add_child(hud)
	print("boot: world %d ms, terrain %d ms, props %d, containers %d" % [t1 - t0, t2 - t1, sim.world.props.size(), sim.world.containers.size()])


func _physics_process(dt: float) -> void:
	LocalInput.gather(sim.players[0].intent, self)
	sim.tick(dt)


func _process(dt: float) -> void:
	_update_camera(dt)
	props_below.queue_redraw()
	props_above.queue_redraw()
	player_view.queue_redraw()
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


# ------------------------------------------------------------------ smoke --

func smoke_state() -> Dictionary:
	var p := sim.players[0]
	var loc := sim.world.location_at_px(p.pos.x, p.pos.y)
	return {
		"x": p.pos.x, "y": p.pos.y, "tx": int(p.pos.x / 32), "ty": int(p.pos.y / 32),
		"location": loc.get("id", "outskirts"), "stam": p.stam, "hp": p.hp, "winded": p.winded,
	}


func smoke_teleport(tx: int, ty: int) -> void:
	var p := sim.players[0]
	p.pos = sim.world.unstick(Vector2(tx * 32 + 16, ty * 32 + 16), p.r)
	p.vel = Vector2.ZERO
	camera.position = p.pos


## The scripted session: walk, sprint, then photograph the districts.
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
