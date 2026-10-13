class_name Models
extends RefCounted
## Which mesh draws what on the 3D stage, and which clip plays for which
## state. A view table, never content: Notion owns what exists and what it
## costs, the stage owns what it looks like. A kind that is not here draws
## as a capsule at its 2D radius in its 2D colour, and a structure that is
## not here draws as a box in `StructureView.COLORS`, so the whole loop
## plays while the owner makes the rest (`tasks/3d-conversion.md`).
##
## Clip names are the GLB's. `strip_root` names the clips whose hips carry
## root motion (a roll that travels four metres, a reload that jogs); the
## sim moves the body, so the hips' position track is removed at load.
## `walk_speed` / `run_speed` are the metres per second the cycles were
## animated at, which is what the playback speed is scaled against.

const CHARACTERS := "res://assets/models/characters/"
const ENEMIES := "res://assets/models/enemies/"
const STRUCTURES := "res://assets/models/structures/"

const PLAYER := {
	"scene": CHARACTERS + "player.glb",
	"clips": {
		# No Idle in this export: `""` holds frame 0 of the walk until the
		# owner re-exports with one.
		"idle": "", "walk": "Walking", "run": "Running", "sneak": "Sneaky_Walk_inplace",
		"attack": "Left_Short_Hook_from_Guard", "die": "Dead", "downed": "sleep",
		"dash": "Roll_Dodge_1", "reload": "Running_Reload",
	},
	"strip_root": ["Roll_Dodge_1", "Running_Reload", "Run_and_Shoot", "sleep"],
	"walk_speed": 1.4, "run_speed": 4.5,
	"hand": "mixamorig:RightHand",
}

const ENEMY_MODELS := {
	"walker": {
		"scene": ENEMIES + "walker.glb",
		"clips": {"idle": "Idle_02", "walk": "Walking", "run": "Running",
			"attack": "Left_Hook_from_Guard", "hurt": "Hit_Reaction_1", "die": "Dead"},
		"strip_root": [],
		"walk_speed": 1.4, "run_speed": 4.5,
	},
	"runner": {
		"scene": ENEMIES + "runner.glb",
		"clips": {"idle": "Idle_02", "walk": "Walking", "run": "Running",
			"attack": "Left_Hook_from_Guard", "die": "Fall_Dead_from_Abdominal_Injury"},
		"strip_root": [],
		"walk_speed": 1.4, "run_speed": 4.5,
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
const LOOPING := ["idle", "walk", "run", "sneak"]
const HOLDING := ["die", "downed"]

static var _scenes := {}


## A model's scene, loaded once. Null when the file is not there, which is
## how a kind falls back to its capsule rather than crashing the stage.
static func scene(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[path]
