class_name EnemySim
extends RefCounted
## One enemy's state. Plain data stepped by Enemies.tick_ai; the view reads
## it to draw. `def` is the Config.ENEMIES row; the hot numbers are copied
## out so the AI loop does no dictionary lookups.

var id := 0                      # stable identity for the wire; the array index is not
var type := "walker"
var def: Dictionary
var pos := Vector2.ZERO
## Where `pos` was at the top of this tick. Presentation only — see
## `Util.render_pos`.
var prev_pos := Vector2.ZERO
var vel := Vector2.ZERO
var angle := 0.0
var hp := 0.0
var max_hp := 0.0
var r := 12.0
var speed := 60.0
var dmg := 13.0
var atk_range := 26.0
var atk_cd_base := 1.0
var sense := 330.0
var knock_resist := 0.0

var flash := 0.0
var dead := false
var aggro := false               # hunting a player; expires unless renewed by real sensing
var alert_t := 0.0               # window in which a noise destination is acted on
var has_noise := false
var noise_at := Vector2.ZERO
var atk_cd := 0.0
var windup := 0.0                # committed to a swing that lands when this hits zero
var anim := 0.0
var slow_t := 0.0

# Alight. `burn_t` counts the fire down and `burn_spread_t` is when it next
# tries to take something with it. Both live here rather than in a list, so a
# dead enemy takes its fire with it and nothing has to be reaped.
var burn_t := 0.0
var burn_spread_t := 0.0
var stuck_t := 0.0
var last_pos := Vector2.ZERO
var wander_a := 0.0
var wander_t := 0.0
var growl_t := 0.0
var raid := false
var last_raid_dist := -1.0
var raid_stall := 0.0

# What it is walking at and what it is swinging at. `objective` is the
# structure a raider is heading for; `blocker` is whatever player-built
# thing is in the way right now; `pending_struct` is the one a committed
# wind-up will land on. Empty Dictionary means none.
var objective := {}
var blocker := {}
var pending_struct := {}


## The structure this enemy is about to hit, or an empty Dictionary. Kept as
## a function so the view can ask without knowing the three fields.
func swinging_at_structure() -> bool:
	return not pending_struct.is_empty()


func _init(type_: String, at: Vector2, hp_mul := 1.0) -> void:
	type = type_
	def = Config.ENEMIES[type_]
	pos = at
	prev_pos = at
	last_pos = at
	hp = def.hp * hp_mul
	max_hp = hp
	r = def.r
	speed = def.speed
	dmg = def.dmg
	atk_range = def.atk_range
	atk_cd_base = def.atk_cd
	sense = def.sense
	knock_resist = def.knock_resist
