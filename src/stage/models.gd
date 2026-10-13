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
## clip, or to a list of clips the body takes turns with (two swings, two
## deaths), and a state with no clip does nothing, or borrows its nearest
## (`ActorModel._clip_for`). A state with a weapon family in front of it
## (`rifle_walk`) is what the body does in that state with that kind of
## weapon in its hands; `ActorModel` looks for the family's clip first and
## falls back to the bare state, so a family only needs the clips that differ.
## Root motion is already out of every clip, and the speed each cycle was
## animated at is in the clip (`speed` meta), so nothing here says how fast a
## walk is. `run_over` is the speed in metres per second above which an enemy
## is drawn running instead of walking. `scale` is how much bigger than a
## person it is drawn.

const CHARACTERS := "res://assets/models/characters/"
const ENEMIES := "res://assets/models/enemies/"
const STRUCTURES := "res://assets/models/structures/"
const ANIMS := "res://assets/anims/"

const PLAYER := {
	"scene": CHARACTERS + "player.glb",
	"lib": ANIMS + "player.res",
	"clips": {
		"idle": "idle", "walk": "walk", "run": "run",
		# Every melee weapon swings the sword slash, at a zombie or a tree;
		# bare hands punch.
		"attack": "attack", "fists_attack": "punch",
		"hurt": "hurt", "die": "die", "downed": "downed",
		# Space, Sprint + Space, X.
		"jump": "jump", "roll": "roll", "dance": "dance",
		"crouch": "crouch", "shoot": "shoot", "collect": "collect", "throw": "throw",
		# With a long gun, a handgun or a bow in hand. Every gun fires with the
		# rifle's kick; the bow has its own release, its draw is its reload,
		# and it is the one weapon with an equip and a disarm.
		"rifle_idle": "rifle_idle", "rifle_walk": "rifle_walk", "rifle_run": "rifle_run",
		"pistol_idle": "pistol_idle", "pistol_walk": "pistol_walk", "pistol_run": "pistol_run",
		"bow_idle": "bow_idle", "bow_walk": "bow_walk", "bow_run": "bow_run",
		"bow_shoot": "bow_shoot", "bow_reload": "bow_reload",
		"bow_equip": "bow_equip", "bow_disarm": "bow_disarm",
		# No crouched walk, no swing with a weapon in it and no gun reload in
		# the exports yet: sneaking on the move borrows the walk, every melee
		# weapon swings like a fist, and a gun's reload leaves whatever was
		# playing.
	},
	"hand": "mixamorig:RightHand",
}

## The guns a body holds in one hand. Everything else that fires is carried
## like a rifle.
const HANDGUNS := ["pistol", "sixShooter", "machinePistol", "compactSmg", "smg"]

## The two zombies share a body of states. A walker is drawn running above
## 1.2 m/s because its walk clip is a 0.3 m/s shamble and it moves at 1.9;
## the runner's is 4.1 and its clip is 2.8.
const ENEMY_MODELS := {
	"walker": {
		"scene": ENEMIES + "walker.glb",
		"lib": ANIMS + "walker.res",
		"clips": {"idle": "idle", "walk": "walk", "run": "run", "attack": ["attack", "bite"], "hurt": "hurt",
			"die": ["die", "die2"], "eat": "eat", "crawl": "crawl", "getup": "getup", "bite_low": "bite_low",
			"die_low": "crawl"},
		"run_over": 1.2,
	},
	"runner": {
		"scene": ENEMIES + "runner.glb",
		"lib": ANIMS + "runner.res",
		"clips": {"idle": "idle", "walk": "walk", "run": "run", "attack": ["attack", "bite"], "hurt": "hurt",
			"die": ["die", "die2"], "eat": "eat", "crawl": "crawl_fast", "getup": "getup", "bite_low": "bite_low",
			"die_low": "crawl_fast"},
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
const LOOPING := ["idle", "walk", "run", "crouch", "crawl", "stun", "dance"]
const HOLDING := ["die", "downed", "die_low", "getup", "asleep"]
## Which states are a clip's first frame, held: a dead crawler slumped where it
## was, a boss on the gym floor before anyone walks in.
const FROZEN := ["die_low", "asleep"]

static var _scenes := {}
static var _libs := {}


## The clip family a weapon puts the body in: "bow", "pistol", "rifle",
## "fists" for bare hands, or "" for everything swung.
static func family_of(w: Dictionary) -> String:
	if w.get("bow", false):
		return "bow"
	if String(w.get("kind", "")) == "gun":
		return "pistol" if String(w.get("id", "")) in HANDGUNS else "rifle"
	if String(w.get("id", "")) == "fists":
		return "fists"
	return ""


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
