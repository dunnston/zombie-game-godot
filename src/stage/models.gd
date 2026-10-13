class_name Models
extends RefCounted
## Which mesh draws what on the 3D stage, and which clip plays for which
## state. A view table, never content: Notion owns what exists and what it
## costs, the stage owns what it looks like. A kind that is not here draws
## as a capsule at its 2D radius in its 2D colour, and a structure that is
## not here draws as a box in `StructureView.COLORS`, so the whole loop
## plays while the owner makes the rest (`tasks/3d-conversion.md`).
##
## Clip names are the animation library's (`lib`, built by
## `tools/build_anims.gd` from the owner's Mixamo exports); a state maps to a
## clip and a state with no clip does nothing, or borrows its nearest
## (`ActorModel._clip_for`). Root motion is already out of every clip, and the
## speed each cycle was animated at is in the clip (`speed` meta), so nothing
## here says how fast a walk is. `run_over` is the speed in metres per second
## above which a body is drawn running instead of walking. `scale` is how much
## bigger than a person it is drawn.

const CHARACTERS := "res://assets/models/characters/"
const ENEMIES := "res://assets/models/enemies/"
const STRUCTURES := "res://assets/models/structures/"
const ANIMS := "res://assets/anims/"

const PLAYER := {
	"scene": CHARACTERS + "player.glb",
	"lib": ANIMS + "player.res",
	"clips": {
		"idle": "idle", "walk": "walk", "run": "run", "attack": "attack",
		"hurt": "hurt", "die": "die", "downed": "downed", "dash": "dash",
		"shoot": "shoot", "collect": "collect", "throw": "throw",
		# No sneak or reload in the exports yet: sneaking borrows the walk, and a
		# reload leaves whatever was playing.
	},
	"hand": "mixamorig:RightHand",
}

## The two zombies share a body of states. A walker is drawn running above
## 1.2 m/s because its walk clip is a 0.3 m/s shamble and it moves at 1.9;
## the runner's is 4.1 and its clip is 2.8.
const ENEMY_MODELS := {
	"walker": {
		"scene": ENEMIES + "walker.glb",
		"lib": ANIMS + "walker.res",
		"clips": {"idle": "idle", "walk": "walk", "run": "run", "attack": "attack", "hurt": "hurt",
			"die": "die", "crawl": "crawl", "getup": "getup", "bite_low": "bite_low", "die_low": "crawl"},
		"run_over": 1.2,
	},
	"runner": {
		"scene": ENEMIES + "runner.glb",
		"lib": ANIMS + "runner.res",
		"clips": {"idle": "idle", "walk": "walk", "run": "run", "attack": "attack", "hurt": "hurt",
			"die": "die", "crawl": "crawl_fast", "getup": "getup", "bite_low": "bite_low", "die_low": "crawl_fast"},
		"run_over": 3.0,
	},
	"coach": {
		"scene": ENEMIES + "coach.glb",
		"lib": ANIMS + "coach.res",
		"clips": {"idle": "idle", "walk": "walk", "run": "run", "attack": "attack", "hurt": "hurt",
			"die": "die", "wake": "wake", "asleep": "wake", "slam": "slam", "charge_wind": "charge_wind",
			"charge_go": "charge_go", "stun": "stun", "throw": "throw", "whistle": "whistle",
			"roar": "roar", "agony": "agony"},
		"run_over": 3.0,
		"scale": 1.5,
	},
}

## Structure type -> a static GLB, fitted to the piece's footprint by its
## bounds (`StaticModel.fit`), so a Meshy export at any scale lands on its
## tiles with its base on the ground.
const STRUCTURE_MODELS := {
	"workbench": STRUCTURES + "workbench.glb",
	"chemStation": STRUCTURES + "chemStation.glb",
	"chest": STRUCTURES + "chest.glb",
	"locker": STRUCTURES + "locker.glb",
	"generator": STRUCTURES + "generator.glb",
	"bedroll": STRUCTURES + "bedroll.glb",
	"bunk": STRUCTURES + "bunk.glb",
	"raisedBed": STRUCTURES + "raisedBed.glb",
	"longBed": STRUCTURES + "raisedBed.glb",
	"turret": STRUCTURES + "turret.glb",
}

## Which states loop, and which hold their last frame when they end.
const LOOPING := ["idle", "walk", "run", "sneak", "crawl", "stun"]
const HOLDING := ["die", "downed", "die_low", "getup", "asleep"]
## Which states are a clip's first frame, held: a dead crawler slumped where it
## was, a boss on the gym floor before anyone walks in.
const FROZEN := ["die_low", "asleep"]

static var _scenes := {}
static var _libs := {}


## A clip library, loaded once; null when it is not built, which leaves a body
## standing still rather than crashing the stage.
static func library(path: String) -> AnimationLibrary:
	if path.is_empty():
		return null
	if not _libs.has(path):
		_libs[path] = load(path) if ResourceLoader.exists(path) else null
	return _libs[path]


## A model's scene, loaded once. Null when the file is not there, which is
## how a kind falls back to its capsule rather than crashing the stage.
static func scene(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[path]
