class_name Units
extends RefCounted
## The one place the sim's pixels become the stage's metres, and a sim
## angle becomes a facing. The sim is 2D: `x` east, `y` south, 32 px a tile.
## The 3D stage is `x` east, `z` south, `y` up, one metre a tile
## (`Config.STAGE_UNITS`), so a 1.70 m model is the 54 px person `PLAYER.r`
## 13 px always meant. Nothing else may do this arithmetic.

const PX := Config.STAGE_UNITS


## A sim point on the ground, `h` metres up.
static func to3(v: Vector2, h := 0.0) -> Vector3:
	return Vector3(v.x / PX, h, v.y / PX)


## A stage point back on the sim's ground.
static func to2(v: Vector3) -> Vector2:
	return Vector2(v.x * PX, v.z * PX)


## A sim length in metres.
static func m(px: float) -> float:
	return px / PX


## The yaw (radians about Y) that turns a model's own forward onto a sim
## angle. The sim's angle 0 is east and grows clockwise on screen (toward
## south); a glTF character faces +Z. Rotating +Z by `yaw` about Y gives
## (sin yaw, 0, cos yaw), and that has to be (cos a, 0, sin a).
static func yaw(angle: float) -> float:
	return PI / 2.0 - angle


## The sim direction a yaw faces: `yaw` run backwards, for tests and for
## anything that reads a facing off a node.
static func angle_of(yaw_: float) -> float:
	return PI / 2.0 - yaw_
