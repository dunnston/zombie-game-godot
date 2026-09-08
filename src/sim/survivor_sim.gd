class_name SurvivorSim
extends RefCounted
## One person you rescued. Named, levelled, and permanently killable.
##
## Their combat numbers are derived, not stored: `refresh()` rebuilds them from
## level and the base owner's Charisma perks, the same way `recompute_stats`
## rebuilds the player's. So Inspiring Presence reaches the crew already
## standing in your base, not just the next hire, and a save stores the level
## rather than the health it implies.

const S := Config.SURVIVOR

var id := 0
var display_name := "Survivor"
var level := 1
var xp := 0.0

var pos := Vector2.ZERO
## Where `pos` was at the top of this tick, for the view to interpolate from.
var prev_pos := Vector2.ZERO
var vel := Vector2.ZERO
var angle := 0.0
var r: float = S.r
var anim := 0.0
var flash := 0.0

var hp := 0.0
var max_hp := 0.0
var dmg := 0.0
var dead := false
## Downed is a countdown, not a death: someone has `revive_time` to reach them.
var downed := false
var down_t := 0.0
var hungry := false
var kills := 0
var tint := Config.SURVIVOR_TINTS[0]

var job := "guard"
## The Watchtower a sniper is assigned to. Assigned is not the same as posted:
## `posted` is true only while they are actually standing on it.
var tower := {}
var posted := false
var cd := 0.0
var out_of_ammo := false

# ------------------------------------------------------------- job state --
## The container or structure this person is walking to. Different jobs target
## different shapes, so it is cleared on reassignment rather than reused.
var run_target := {}
var job_t := 0.0
## Give-up timers. There is no pathfinding, so every walk needs one.
var reach_t := 0.0
var last_reach_d := INF
var home_t := 0.0
var last_home_d := INF
## Targets this person has failed to reach, forgotten when nothing is left.
var unreachable := {}

## A scavenger's haul on the way home: resources as id -> count, and whatever
## did not stack as loot entries. Both were taken out of a real container, so
## neither may ever be quietly dropped.
var carrying := {}
var carry_items: Array[Dictionary] = []

var target: EnemySim = null
var shot_range: float = S.range
var shot_dmg_mul := 1.0


func _init(at: Vector2, name_: String, level_: int) -> void:
	pos = at
	prev_pos = at
	display_name = name_
	level = maxi(1, level_)


## Rebuilds what level and the owner's perks are worth. Called on recruit, on
## level up, and by `Survivors.refresh_all` whenever the owner's build changes.
func refresh(owner: PlayerSim) -> void:
	var hp_mul: float = owner.survivor_hp_mul if owner != null else 1.0
	var dmg_mul: float = owner.survivor_dmg_mul if owner != null else 1.0
	max_hp = roundf((S.base_hp + S.hp_per_level * (level - 1)) * hp_mul)
	dmg = (S.base_dmg + S.dmg_per_level * (level - 1)) * dmg_mul
	hp = minf(hp, max_hp)


func xp_to_next() -> float:
	return S.xp_per_level * level


func alive() -> bool:
	return not dead
