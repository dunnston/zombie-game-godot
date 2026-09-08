class_name PlayerSim
extends RefCounted
## One player's simulation state: position, stamina, aim. No nodes, no Input.

var seat := 0
var display_name := "Survivor"

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var r: float = Config.PLAYER.r
var angle := 0.0

var hp: float = Config.PLAYER.max_hp
var max_hp: float = Config.PLAYER.max_hp
var dead := false

# 100 base + CON 2 at the start. recompute_stats() (Phase 4) will own this.
var max_stam := 110.0
var stam := 110.0
var stam_regen: float = Config.PLAYER.stam_regen
var stam_lock := 0.0
var winded := false
var sprinting := false
var sneaking := false
var speed_mul := 1.0

var intent := Intent.new()


func tick(world: World, dt: float) -> void:
	if dead:
		return
	pos = world.unstick(pos, r)
	angle = atan2(intent.aim.y - pos.y, intent.aim.x - pos.x)
	move(world, dt, false)


## Stamina, speed and the actual step, from the movement half of the intent.
## Separate from tick so a guest can run exactly this to predict itself.
func move(world: World, dt: float, rooted := false) -> void:
	var it := intent
	var P := Config.PLAYER
	var moving := it.mx != 0.0 or it.my != 0.0

	sneaking = it.sneak
	sprinting = not sneaking and it.sprint and moving and stam > 1.0

	if sprinting:
		stam = maxf(0.0, stam - P.stam_drain * dt)
		stam_lock = P.stam_regen_delay
		if stam <= 0.0:
			sprinting = false
	else:
		stam_lock = maxf(0.0, stam_lock - dt)
		if stam_lock <= 0.0:
			stam = minf(max_stam, stam + stam_regen * dt)

	# Winded latches on running yourself flat and clears at half. The other
	# edge — a harvest swing turned down — belongs to melee (Phase 2).
	if stam <= 0.0:
		winded = true
	elif winded and stam >= max_stam * P.stam_winded_recovery:
		winded = false

	var speed: float = P.speed * speed_mul
	if sprinting:
		speed *= P.sprint_mul
	if sneaking:
		speed *= 0.5
	if rooted:
		speed = 0.0

	var k := Util.smooth(18.0, dt)
	vel.x += (it.mx * speed - vel.x) * k
	vel.y += (it.my * speed - vel.y) * k
	if not moving:
		vel *= exp(-11.0 * dt)
	pos = world.move_circle(pos, vel * dt, r)
