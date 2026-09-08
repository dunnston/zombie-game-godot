class_name Config
## Every tunable number and every content definition lives here. One file to
## balance. Numbers are the prototype's current values (see
## tasks/port-inventory.md); a number that moves should move for a reason.

const TILE := 32
const WORLD_TILES := 320
const WORLD_SIZE := TILE * WORLD_TILES   # 10240px square

# ------------------------------------------------------------------ terrain --

enum T {
	GRASS, ROAD, SIDEWALK, DIRT, FLOOR_WOOD,
	WALL, WATER, RUBBLE, LOT, FLOOR_TILE, GRAVEL,
	FIELD, SAND, FENCE,
}

## Base colour `a` and a translucent detail colour `b`, per terrain.
const TERRAIN := {
	T.GRASS:      {"a": Color("#38472a"), "b": Color("#31402552")},
	T.ROAD:       {"a": Color("#2b2c2e"), "b": Color("#33343664")},
	T.SIDEWALK:   {"a": Color("#474742"), "b": Color("#50504b64")},
	T.DIRT:       {"a": Color("#463c2d"), "b": Color("#4f442f64")},
	T.FLOOR_WOOD: {"a": Color("#463726"), "b": Color("#50402c64")},
	T.WALL:       {"a": Color("#6a6055"), "b": Color("#75695c64")},
	T.WATER:      {"a": Color("#22384a"), "b": Color("#2b445864")},
	T.RUBBLE:     {"a": Color("#3a3730"), "b": Color("#45413864")},
	T.LOT:        {"a": Color("#313236"), "b": Color("#3a3b4064")},
	T.FLOOR_TILE: {"a": Color("#54544f"), "b": Color("#5d5d5764")},
	T.GRAVEL:     {"a": Color("#3e3d38"), "b": Color("#4a4941aa")},
	T.FIELD:      {"a": Color("#4b3a26"), "b": Color("#5a4630aa")},
	T.SAND:       {"a": Color("#6e6449"), "b": Color("#7c7255aa")},
	T.FENCE:      {"a": Color("#38472a"), "b": Color("#31402552")},
}

## Indexed by T. Solid to feet: wall, water, fence.
const SOLID_BY_TILE := [0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1]
## Solid to feet but not to bullets: you shoot across a river or over a fence.
const SHOOT_OVER_BY_TILE := [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1]

# ------------------------------------------------------------------- player --

const PLAYER := {
	"max_hp": 100.0,
	"r": 13.0,
	"speed": 176.0,
	"sprint_mul": 1.62,
	"max_stam": 100.0,
	"stam_drain": 26.0,
	"stam_regen": 20.0,
	"stam_regen_delay": 0.65,
	# Work costs stamina; fighting barely does. A harvest swing is the
	# expensive one and also stops recovery for stam_chop_delay afterwards.
	# A combat swing costs stam_swing and is never refused.
	"stam_chop": 6.0,
	"stam_swing": 2.0,
	"stam_chop_delay": 1.1,
	# Exhaustion has hysteresis: once the bar bottoms out you are winded, and
	# you have to get back to half before you can work again.
	"stam_winded_recovery": 0.5,
	"carry_cap": 200.0,
	"inv_slots": 30,
	"hotbar_slots": 6,
	"pickup_range": 46.0,
	"interact_range": 76.0,
	"search_time": 1.05,
	"invuln_after_hit": 0.32,
	"respawn_time": 3.0,
	"downed_time": 30.0,
	"revive_time": 2.5,
	"revive_hp_frac": 0.4,
	# Ground-ring tints, one per seat.
	"colors": ["#dff0ff", "#ffd27a", "#9fe8a0", "#f0a0e8"],
	"names": ["Survivor", "Ash", "Bex", "Cole", "Dee"],
}

## view_height is world pixels of height on screen at zoom 1; the camera
## zooms so that the viewport shows about that much world vertically.
const CAMERA := {"follow": 7.5, "view_height": 580.0, "min_zoom": 0.9, "max_zoom": 2.6, "lead": 0.22, "lead_max": 170.0}

# ---------------------------------------------------------------- resources --

## Everything that stacks as a count. Phase 2 uses the ammunition and the
## medical entries; Phase 3's inventory uses the rest. `wt` per unit.
const RES := {
	"wood":    {"name": "Wood",         "short": "WOOD", "color": "#a3763f", "wt": 1.0,  "stack": 50},
	"sticks":  {"name": "Sticks",       "short": "STCK", "color": "#8a6a3c", "wt": 0.5,  "stack": 50},
	"stone":   {"name": "Stone",        "short": "STNE", "color": "#8f8a80", "wt": 1.5,  "stack": 50},
	"fiber":   {"name": "Fiber",        "short": "FIBR", "color": "#9aae5a", "wt": 0.3,  "stack": 50},
	"scrap":   {"name": "Scrap",        "short": "SCRP", "color": "#9aa2ab", "wt": 1.0,  "stack": 50},
	"cloth":   {"name": "Cloth",        "short": "CLTH", "color": "#c2a98a", "wt": 1.0,  "stack": 50},
	"elec":    {"name": "Electronics",  "short": "ELEC", "color": "#59b8c4", "wt": 1.0,  "stack": 30},
	"battery": {"name": "Batteries",    "short": "BATT", "color": "#8fd08a", "wt": 0.5,  "stack": 20},
	"med":     {"name": "Medical",      "short": "MED",  "color": "#d9575f", "wt": 1.0,  "stack": 30},
	"parts":   {"name": "Weapon Parts", "short": "PART", "color": "#c9a227", "wt": 1.0,  "stack": 20},
	"mil":     {"name": "Military",     "short": "MIL",  "color": "#7fa14a", "wt": 1.0,  "stack": 20},
	"fuel":    {"name": "Fuel",         "short": "FUEL", "color": "#d2762c", "wt": 1.0,  "stack": 20},
	"rations": {"name": "Rations",      "short": "FOOD", "color": "#c4a86a", "wt": 1.0,  "stack": 20},
	"arrow":   {"name": "Arrows",       "short": "ARRW", "color": "#b9a072", "wt": 0.15, "stack": 60},
	"ammoP":   {"name": "9mm Rounds",   "short": "9MM",  "color": "#d8c98a", "wt": 0.2,  "stack": 120},
	"ammoS":   {"name": "Shells",       "short": "SHEL", "color": "#c9584e", "wt": 0.3,  "stack": 60},
	"ammoR":   {"name": "Rifle Rounds", "short": "RIFL", "color": "#b8a05a", "wt": 0.25, "stack": 90},
}

const CONSUMABLES := {
	"bandage": {"id": "bandage", "name": "Bandage", "heal": 28.0, "time": 0.9, "color": "#d8cfc0"},
	"medkit":  {"id": "medkit",  "name": "Medkit",  "heal": 80.0, "time": 1.6, "color": "#d9575f"},
	# Not a healing item — it opens car doors (Phase 4). It lives here so it
	# rides along in the same inventory the rest of the small stuff uses.
	"lockpick": {"id": "lockpick", "name": "Lockpick", "heal": 0.0, "time": 0.0, "color": "#9aa2ab", "tool": true},
}

# --------------------------------------------------------------------- gear --

const GEAR_SLOTS := ["head", "body", "hands", "legs", "feet", "offhand"]
const GEAR_SLOT_NAMES := {"head": "Head", "body": "Body", "hands": "Hands", "legs": "Legs", "feet": "Feet", "offhand": "Off-hand"}

## The five slots that carry damage reduction. Every armour rule — three tiers
## per slot, a full set under the cap, the body the biggest single
## contributor — is about these and not about the off-hand, which holds a
## light and protects nothing.
const ARMOR_SLOTS := ["head", "body", "hands", "legs", "feet"]

## Fifteen armour pieces, three tiers across five slots, plus the two lights.
## A full tier-1 set is 0.23 DR, a full tier-3 set 0.70, against a hard cap of
## 0.72: scavenging can make you tough, never immune.
##
## `light` is what Phase 4's renderer punches out of the darkness and `burn`
## is how many seconds of being lit the thing holds. The torch is the first
## night's answer — sticks and fiber — and burns itself away. The flashlight
## is brighter and reaches much further because it is a cone rather than a
## puddle, and it eats batteries, which you find before you can make them.
const GEAR := {
	"hardHat":     {"id": "hardHat",     "name": "Hard Hat",        "slot": "head",  "dr": 0.05, "wt": 3.0,  "tier": 1, "color": "#c9a227"},
	"riotHelm":    {"id": "riotHelm",    "name": "Riot Helmet",     "slot": "head",  "dr": 0.10, "wt": 5.0,  "tier": 2, "color": "#4d5866"},
	"milHelm":     {"id": "milHelm",     "name": "Combat Helmet",   "slot": "head",  "dr": 0.15, "wt": 6.0,  "tier": 3, "color": "#5b6640"},
	"lightVest":   {"id": "lightVest",   "name": "Padded Vest",     "slot": "body",  "dr": 0.10, "wt": 6.0,  "tier": 1, "color": "#6f7a52"},
	"heavyVest":   {"id": "heavyVest",   "name": "Riot Armor",      "slot": "body",  "dr": 0.20, "wt": 11.0, "tier": 2, "color": "#4d5866"},
	"milVest":     {"id": "milVest",     "name": "Plate Carrier",   "slot": "body",  "dr": 0.28, "wt": 14.0, "tier": 3, "color": "#5b6640"},
	"workGloves":  {"id": "workGloves",  "name": "Work Gloves",     "slot": "hands", "dr": 0.02, "wt": 1.0,  "tier": 1, "color": "#a3763f"},
	"tacGloves":   {"id": "tacGloves",   "name": "Tactical Gloves", "slot": "hands", "dr": 0.04, "wt": 2.0,  "tier": 2, "color": "#4d5866"},
	"armGuards":   {"id": "armGuards",   "name": "Arm Guards",      "slot": "hands", "dr": 0.07, "wt": 4.0,  "tier": 3, "color": "#5b6640"},
	"denimPants":  {"id": "denimPants",  "name": "Work Trousers",   "slot": "legs",  "dr": 0.04, "wt": 2.0,  "tier": 1, "color": "#4a5a72"},
	"paddedLegs":  {"id": "paddedLegs",  "name": "Padded Leggings", "slot": "legs",  "dr": 0.08, "wt": 5.0,  "tier": 2, "color": "#6f7a52"},
	"milGreaves":  {"id": "milGreaves",  "name": "Combat Trousers", "slot": "legs",  "dr": 0.12, "wt": 7.0,  "tier": 3, "color": "#5b6640"},
	"workBoots":   {"id": "workBoots",   "name": "Work Boots",      "slot": "feet",  "dr": 0.02, "wt": 3.0,  "tier": 1, "color": "#6b4a2f"},
	"combatBoots": {"id": "combatBoots", "name": "Combat Boots",    "slot": "feet",  "dr": 0.05, "wt": 4.0,  "tier": 2, "color": "#3f4a38"},
	"milBoots":    {"id": "milBoots",    "name": "Assault Boots",   "slot": "feet",  "dr": 0.08, "wt": 5.0,  "tier": 3, "color": "#5b6640"},
	"torch": {
		"id": "torch", "name": "Torch", "slot": "offhand", "dr": 0.0, "wt": 2.0, "tier": 1,
		"color": "#e0913a", "light": {"radius": 200.0, "strength": 0.80, "warm": "#ffb45a"},
		"burn": 210.0, "consumed": true,
	},
	"flashlight": {
		"id": "flashlight", "name": "Flashlight", "slot": "offhand", "dr": 0.0, "wt": 2.0, "tier": 2,
		"color": "#d8d2c0",
		"light": {"radius": 140.0, "strength": 0.72, "warm": "#fff6cd", "cone_len": 460.0, "cone_spread": 0.34, "cone_strength": 0.86},
		"burn": 300.0, "battery": "battery",
	},
}

## No amount of scavenging should make you immune.
const MAX_GEAR_DR := 0.72

## A lit player is noticed this much further out — the cost of seeing at night.
const LIT_SENSE_BONUS := 90.0

## Weapons and consumables carry no weight of their own in the tables, so the
## item registry gives them these. A gun is six units; a bandage is half one.
const WEAPON_WT := 6.0
const CONSUMABLE_WT := 0.5
const CONSUMABLE_STACK := 10

# ------------------------------------------------------------------ weapons --

## Melee: dmg / cd / range / arc / knock. Tools are deliberately poor weapons;
## `axe`, `pick`, `knife`, `scythe`, `hammer` are what the harvest gates ask
## for, `chop_mul` is how much better than a fist they are at scenery. The
## stone tools come before the metal ones so a fresh game finds them first.
## Guns: real magazines, reload time, spread (radians), bullet speed and life,
## pellets, pierce, threat per shot and a noise radius. The bow is a gun with
## a magazine of one and no muzzle flash; it keeps drawing while held.
const WEAPONS := {
	"fists":     {"id": "fists",     "name": "Fists",            "kind": "melee", "dmg": 9.0,  "cd": 0.42, "range": 34.0, "arc": 1.0,  "knock": 70.0,  "color": "#c8b89a"},
	"pipe":      {"id": "pipe",      "name": "Steel Pipe",       "kind": "melee", "dmg": 24.0, "cd": 0.40, "range": 48.0, "arc": 1.15, "knock": 150.0, "color": "#9aa2ab"},
	"machete":   {"id": "machete",   "name": "Machete",          "kind": "melee", "dmg": 40.0, "cd": 0.34, "range": 54.0, "arc": 1.0,  "knock": 110.0, "chop_mul": 1.3, "color": "#cfd6dd"},
	"axe":       {"id": "axe",       "name": "Hatchet",          "kind": "melee", "dmg": 30.0, "cd": 0.52, "range": 48.0, "arc": 0.9,  "knock": 130.0, "tool": true, "axe": true, "chop_mul": 2.4, "color": "#b08a5a"},
	"pick":      {"id": "pick",      "name": "Stone Pickaxe",    "kind": "melee", "dmg": 26.0, "cd": 0.62, "range": 50.0, "arc": 0.9,  "knock": 150.0, "tool": true, "pick": true, "chop_mul": 2.2, "tool_mul": 2.4, "color": "#9a9088"},
	"knife":     {"id": "knife",     "name": "Stone Knife",      "kind": "melee", "dmg": 19.0, "cd": 0.28, "range": 40.0, "arc": 0.8,  "knock": 60.0,  "tool": true, "knife": true, "chop_mul": 1.5, "color": "#c2b8a6"},
	"scythe":    {"id": "scythe",    "name": "Scythe",           "kind": "melee", "dmg": 24.0, "cd": 0.46, "range": 62.0, "arc": 1.6,  "knock": 80.0,  "tool": true, "scythe": true, "chop_mul": 2.0, "tool_mul": 2.2, "color": "#b9b3a2"},
	"hammer":    {"id": "hammer",    "name": "Stone Hammer",     "kind": "melee", "dmg": 36.0, "cd": 0.72, "range": 46.0, "arc": 1.2,  "knock": 240.0, "tool": true, "hammer": true, "chop_mul": 1.8, "structure_mul": 0.8, "color": "#8a8078"},
	"fireaxe":   {"id": "fireaxe",   "name": "Fire Axe",         "kind": "melee", "dmg": 34.0, "cd": 0.46, "range": 52.0, "arc": 1.0,  "knock": 190.0, "tool": true, "axe": true, "chop_mul": 4.2, "color": "#c4463a"},
	"steelpick": {"id": "steelpick", "name": "Steel Pickaxe",    "kind": "melee", "dmg": 30.0, "cd": 0.56, "range": 54.0, "arc": 0.9,  "knock": 210.0, "tool": true, "pick": true, "chop_mul": 4.4, "tool_mul": 2.4, "color": "#aeb6bd"},
	"sledge":    {"id": "sledge",    "name": "Sledgehammer",     "kind": "melee", "dmg": 78.0, "cd": 0.86, "range": 60.0, "arc": 1.7,  "knock": 340.0, "shake": 5.0, "chop_mul": 1.6, "structure_mul": 1.0, "color": "#8d7a5e"},
	"bow":       {"id": "bow",       "name": "Hunting Bow",      "kind": "gun", "dmg": 19.0, "cd": 0.85,  "mag": 1,  "reload": 0.55, "spread": 0.03,  "ammo": "arrow", "speed": 780.0,  "life": 0.85, "knock": 60.0,  "shake": 0.4, "pellets": 1, "pierce": 0, "threat": 0.15, "noise": 90.0,  "bow": true, "color": "#9a7a48"},
	"pistol":    {"id": "pistol",    "name": "M9 Pistol",        "kind": "gun", "dmg": 27.0, "cd": 0.17,  "mag": 12, "reload": 1.15, "spread": 0.035, "ammo": "ammoP", "speed": 1150.0, "life": 0.55, "knock": 55.0,  "shake": 1.6, "pellets": 1, "pierce": 0, "threat": 1.0,  "noise": 420.0, "color": "#71787f"},
	"smg":       {"id": "smg",       "name": "Scrap SMG",        "kind": "gun", "dmg": 17.0, "cd": 0.075, "mag": 30, "reload": 1.6,  "spread": 0.075, "ammo": "ammoP", "speed": 1100.0, "life": 0.5,  "knock": 40.0,  "shake": 1.2, "pellets": 1, "pierce": 0, "threat": 0.6,  "noise": 400.0, "color": "#6b7178"},
	"shotgun":   {"id": "shotgun",   "name": "Pump Shotgun",     "kind": "gun", "dmg": 16.0, "cd": 0.75,  "mag": 6,  "reload": 0.5,  "spread": 0.20,  "ammo": "ammoS", "speed": 980.0,  "life": 0.30, "knock": 230.0, "shake": 6.5, "pellets": 8, "pierce": 0, "threat": 2.4,  "noise": 620.0, "shell_reload": true, "color": "#5e5148"},
	"rifle":     {"id": "rifle",     "name": "Hunting Rifle",    "kind": "gun", "dmg": 78.0, "cd": 0.52,  "mag": 8,  "reload": 1.9,  "spread": 0.012, "ammo": "ammoR", "speed": 1700.0, "life": 0.9,  "knock": 120.0, "shake": 4.2, "pellets": 1, "pierce": 2, "threat": 2.0,  "noise": 700.0, "color": "#4c4136"},
	"carbine":   {"id": "carbine",   "name": "Military Carbine", "kind": "gun", "dmg": 36.0, "cd": 0.105, "mag": 40, "reload": 2.3,  "spread": 0.045, "ammo": "ammoR", "speed": 1500.0, "life": 0.8,  "knock": 70.0,  "shake": 2.0, "pellets": 1, "pierce": 1, "threat": 1.1,  "noise": 560.0, "color": "#4a5340"},
}

## What each kind of scenery gives up and what it takes. `needs` is the tool
## without which nothing happens; `boost` merely does it better. Small
## scenery never has a `needs`: the tools are made from what it drops.
const HARVEST := {
	"wood":          {"res": "wood",  "min": 6, "max": 11, "bonus": "sticks", "bonus_min": 1, "bonus_max": 3, "needs": "axe", "xp": 4, "label": "WOOD"},
	"fiber":         {"res": "fiber", "min": 2, "max": 4,  "bonus": "sticks", "bonus_min": 1, "bonus_max": 2, "boost": "scythe", "xp": 2, "label": "FIBER"},
	"stone":         {"res": "stone", "min": 2, "max": 4,  "boost": "pick", "xp": 2, "label": "STONE"},
	"boulder":       {"res": "stone", "min": 9, "max": 16, "needs": "pick", "xp": 5, "label": "STONE"},
	"litter_sticks": {"res": "sticks", "min": 2, "max": 4, "xp": 1, "label": "STICKS"},
	"litter_stone":  {"res": "stone",  "min": 1, "max": 3, "xp": 1, "label": "STONE"},
	"litter_fiber":  {"res": "fiber",  "min": 2, "max": 4, "xp": 1, "label": "FIBER"},
	"thicket":       {"res": "fiber", "min": 9, "max": 15, "bonus": "sticks", "bonus_min": 2, "bonus_max": 4, "needs": "scythe", "xp": 4, "label": "FIBER"},
}

const NEEDS_HINT := {
	"axe": "You need a HATCHET to fell trees — bushes give fiber and sticks, rocks give stone",
	"pick": "That boulder needs a STONE PICKAXE — loose rocks you can break by hand",
	"scythe": "That thicket needs a SCYTHE — small bushes you can pull by hand",
}

## What a new survivor wakes up with: a pipe in the first hotbar slot and a
## couple of bandages beside it. Everything else is out there to be found.
## `weapon` is also what a death drop leaves you, so a respawn is never
## completely toothless.
const START_KIT := {
	"weapon": "pipe",
	"hotbar": [["pipe", 1], ["bandage", 2]],
}

## The six-weapon test kit. Not what a game starts with — the smoke run and
## the combat tests ask for it by name so they can fire everything.
const TEST_KIT := {
	"hotbar": [["pipe", 1], ["axe", 1], ["bow", 1], ["pistol", 1], ["shotgun", 1], ["rifle", 1]],
	"bag": [["arrow", 30], ["ammoP", 60], ["ammoS", 24], ["ammoR", 16], ["bandage", 4], ["medkit", 1]],
}

# ------------------------------------------------------------------ enemies --

## Four tiers. `struct_mul` scales damage against player structures only:
## walkers and runners threaten you, brutes are what breaches a wall.
const ENEMIES := {
	"walker":   {"id": "walker",   "name": "Walker",   "hp": 58.0,   "speed": 60.0,  "dmg": 13.0, "atk_cd": 1.0,  "atk_range": 26.0, "r": 12.0, "xp": 10,  "sense": 330.0, "knock_resist": 0.0,  "struct_mul": 0.5, "threat": 0.35, "body": "#5c6b45", "dark": "#3d4a2e"},
	"runner":   {"id": "runner",   "name": "Runner",   "hp": 44.0,   "speed": 132.0, "dmg": 11.0, "atk_cd": 0.65, "atk_range": 25.0, "r": 11.0, "xp": 18,  "sense": 430.0, "knock_resist": 0.15, "struct_mul": 0.4, "threat": 0.5,  "body": "#7a5a3c", "dark": "#513a26"},
	"brute":    {"id": "brute",    "name": "Brute",    "hp": 300.0,  "speed": 52.0,  "dmg": 34.0, "atk_cd": 1.35, "atk_range": 34.0, "r": 19.0, "xp": 55,  "sense": 380.0, "knock_resist": 0.75, "struct_mul": 2.2, "threat": 1.1,  "body": "#6b4b52", "dark": "#452f34"},
	"behemoth": {"id": "behemoth", "name": "Behemoth", "hp": 1100.0, "speed": 46.0,  "dmg": 58.0, "atk_cd": 1.6,  "atk_range": 44.0, "r": 27.0, "xp": 200, "sense": 900.0, "knock_resist": 0.95, "struct_mul": 4.0, "threat": 2.5,  "body": "#7d4348", "dark": "#4a262b", "boss": true},
}

## The ambient spawner. A standing population per danger tier near each
## living player, scaled by night and by the quiet field. The ring is off
## screen; anything further than `cull` from every player is removed.
##
## count_radius reaches past the ring's outer edge. The prototype counted
## within 950px of a ring that ran 880–1300, so most of what it spawned
## never counted and a still player in tier 1 collected 26 enemies in 20
## seconds against a target of 4 (measured here). See PROJECT.md §6.
const SPAWN := {
	"density": [0, 4, 10, 17, 24],
	"mix": {
		1: [["walker", 0.94], ["runner", 0.06]],
		2: [["walker", 0.70], ["runner", 0.28], ["brute", 0.02]],
		3: [["walker", 0.52], ["runner", 0.36], ["brute", 0.12]],
		4: [["walker", 0.40], ["runner", 0.36], ["brute", 0.24]],
	},
	"max_enemies": 160,
	"interval": 0.6,
	"count_radius": 1400.0,
	"ring_min": 880.0,
	"ring_width": 420.0,
	"cull": 2400.0,
	"seed_count": 5,
	"seed_radius": 1100.0,
	"light_sense_bonus": 90.0,
	"sneak_sense_mul": 0.55,
}

## How loud things are, as a radius. Guns carry their own in WEAPONS.
const NOISE := {
	"chop": 140.0,
	"build": 190.0,
	"turret": 520.0,
	"generator": 300.0,
	"pick_snap": 260.0,
	"engine": 420.0,
	"crash": 380.0,
	"alert_time": 8.0,
}

## The quiet field: killing buys local, temporary calm. Raids ignore it.
const QUIET := {
	"cell": 256.0,
	"per_kill": 1.0,
	"max": 6.0,
	"decay_per_sec": 6.0 / 270.0,
	"suppress_at": 2.9,
	"struct_quiet": 1.6,
	"struct_radius": 400.0,
	"floor": 0.3,
	"kernel_reach": 1.7,
}

## Navigation: a local flow field around each living player, rebuilt when
## they move a tile or the world changes. Enemies beyond it steer straight.
const NAV := {
	"radius_tiles": 40,
	"rebuild_after_tiles": 1,
	"max_age": 1.5,
}

# --------------------------------------------------------------- threat/raid --

const THREAT := {
	"max": 100.0,
	"decay_per_sec": 0.12,
	"kill_walk": 0.35,
	"per_gunshot": 1.0,
	"per_build": 1.0,
	"per_craft": 0.4,
	"per_loot": 0.45,
	"generator_per_sec": 0.55,
	"turret_per_shot": 0.06,
	"post_raid_reset": 14.0,
	"warn_at": [40.0, 70.0, 90.0],
}

const RAIDS := [
	{"name": "SCATTERED HORDE", "waves": 2, "base": 8,  "growth": 3, "mix": {"walker": 1.0}, "reward": {"scrap": 30, "wood": 30, "parts": 2}, "xp": 120},
	{"name": "RUNNING HORDE",   "waves": 3, "base": 11, "growth": 4, "mix": {"walker": 0.65, "runner": 0.35}, "reward": {"scrap": 45, "parts": 3, "elec": 10}, "xp": 220},
	{"name": "HEAVY HORDE",     "waves": 3, "base": 14, "growth": 5, "mix": {"walker": 0.55, "runner": 0.3, "brute": 0.15}, "reward": {"scrap": 60, "parts": 5, "elec": 15, "mil": 3}, "xp": 360},
	{"name": "SIEGE",           "waves": 4, "base": 18, "growth": 6, "mix": {"walker": 0.45, "runner": 0.33, "brute": 0.22}, "reward": {"scrap": 80, "parts": 7, "elec": 20, "mil": 6}, "xp": 520},
	{"name": "BEHEMOTH SIEGE",  "waves": 4, "base": 22, "growth": 7, "mix": {"walker": 0.4, "runner": 0.32, "brute": 0.25, "behemoth": 0.03}, "reward": {"scrap": 110, "parts": 10, "elec": 28, "mil": 12}, "xp": 800},
]

const RAID := {
	"warning_time": 12.0,
	"spawn_interval": 0.22,
	"ring_min": 520.0,
	"ring_max": 800.0,
	"relocate_min": 360.0,
	"relocate_max": 560.0,
	"hp_per_index": 0.06,
	"stall_interval": 4.0,
	"stall_limit": 12.0,
	# Only a raider this far from the raid centre is a candidate for the
	# anti-stall warp. It sits below ring_min so a raider wedged where it
	# spawned is still rescued, and well above melee reach so one shouldering
	# through the fight is never teleported out of it.
	"stall_radius": 400.0,
	"stall_closing": 30.0,
	"max_seconds": 300.0,
	"breakoff_time": 25.0,
	"inter_wave": 3.5,
	"anchor_on_player_beyond": 1500.0,
	"player_lure": 300.0,
	"kill_xp_mul": 1.25,
}


## Raids past the authored list keep scaling instead of stopping.
static func raid_spec(index: int) -> Dictionary:
	if index < RAIDS.size():
		return RAIDS[index]
	var last: Dictionary = RAIDS[RAIDS.size() - 1]
	var over := index - RAIDS.size() + 1
	var spec := last.duplicate(true)
	spec.name = "BEHEMOTH SIEGE +%d" % over
	spec.base = last.base + over * 5
	spec.growth = last.growth + over
	spec.xp = roundi(last.xp * (1.0 + over * 0.35))
	var reward := {}
	for id in last.reward:
		reward[id] = roundi(last.reward[id] * (1.0 + over * 0.3))
	spec.reward = reward
	return spec

# ---------------------------------------------------------------- districts --

## Order matters: location_at_px returns the first match, so the small named
## places inside the forest come before the forest itself.
const LOCATIONS := [
	# the town
	{"id": "camp",       "name": "ROADSIDE CAMP",       "tier": 1, "rect": Rect2i(146, 146, 28, 28), "desc": "Quiet crossroads. Good first base."},
	{"id": "suburb",     "name": "PINE HOLLOW SUBURBS", "tier": 1, "rect": Rect2i(86, 86, 62, 58),   "desc": "Empty homes. Wood, cloth, odds and ends."},
	{"id": "residenceE", "name": "EAST TERRACES",       "tier": 2, "rect": Rect2i(176, 86, 56, 44),  "desc": "Denser housing. More of them here."},
	{"id": "commercial", "name": "MARKET ROW",          "tier": 2, "rect": Rect2i(172, 136, 60, 34), "desc": "Shops and a hardware store. Loud crowds."},
	{"id": "gas",        "name": "FUEL STOP",           "tier": 2, "rect": Rect2i(110, 162, 26, 22), "desc": "Fuel and scrap. Watch the pumps."},
	{"id": "police",     "name": "PRECINCT 12",         "tier": 3, "rect": Rect2i(178, 176, 40, 34), "desc": "Guns, ammo and armour. Heavily infested."},
	{"id": "hospital",   "name": "ST. MARTHA HOSPITAL", "tier": 3, "rect": Rect2i(90, 188, 46, 42),  "desc": "Medicine. The halls are full."},
	{"id": "industrial", "name": "DOCK YARD",           "tier": 3, "rect": Rect2i(144, 198, 30, 36), "desc": "Electronics and parts. Brutes work here."},
	{"id": "military",   "name": "CHECKPOINT DELTA",    "tier": 4, "rect": Rect2i(204, 204, 32, 32), "desc": "Military hardware. You will need a plan."},
	# the country
	{"id": "farms",      "name": "HOLLOW CREEK FARMS",  "tier": 1, "rect": Rect2i(2, 66, 52, 106),   "desc": "Fields and barns across the river. Food, fuel, quiet."},
	{"id": "ranch",      "name": "SADDLEBACK RANCH",    "tier": 1, "rect": Rect2i(2, 206, 52, 50),   "desc": "Paddocks and a stable. The end of the lane."},
	{"id": "lumber",     "name": "GRAYSON LUMBER",      "tier": 2, "rect": Rect2i(88, 14, 44, 38),   "desc": "Log stacks and a sawmill. Wood by the ton."},
	{"id": "lake",       "name": "LOON LAKE",           "tier": 2, "rect": Rect2i(170, 8, 54, 46),   "desc": "A lodge on the shore. Quiet, until it is not."},
	{"id": "junkyard",   "name": "RUST BELT SALVAGE",   "tier": 2, "rect": Rect2i(166, 250, 48, 42), "desc": "Wrecks stacked three high. Scrap and parts."},
	{"id": "forest",     "name": "BLACKPINE FOREST",    "tier": 2, "rect": Rect2i(0, 0, 320, 62), "label": Vector2i(150, 6), "desc": "Deep woods. Cabins, and things between the trees."},
	# the city
	{"id": "heights",    "name": "CROWN HEIGHTS",       "tier": 3, "rect": Rect2i(240, 62, 80, 68),  "desc": "Apartment blocks. Crowded, floor after floor."},
	{"id": "downtown",   "name": "DOWNTOWN",            "tier": 4, "rect": Rect2i(240, 132, 80, 82), "desc": "Office towers and the bank. The whole city died here."},
	{"id": "mall",       "name": "GALLERIA MALL",       "tier": 3, "rect": Rect2i(240, 216, 80, 54), "desc": "Shops, a drugstore and an outfitters. Everyone came here."},
]

# --------------------------------------------------------------- structures --

## Build anywhere: a "base" is wherever your structures happen to be.
##
## `solid` blocks feet but never bullets (invariant 3) — a base you cannot
## shoot out of is a base that punishes you for building it. `protect` marks
## the pieces a raider inside the perimeter should prefer, so a horde that
## is already through heads for the workbench rather than back out. `threat`
## scales what putting one up costs you in attention. `store` is a slot
## count; `tier` 2 needs the upgraded workbench.
const STASH_SLOTS := 48
const BENCH_UPGRADE_COST := {"scrap": 55, "elec": 20, "parts": 5}

const BUILD := {
	"range": 190.0,
	# About a compound, so post-raid recovery is one decision rather than a lap.
	"repair_all_range": 520.0,
	# A repair costs this share of the build price, scaled by the damage.
	"repair_cost_share": 0.45,
	"salvage_share": 0.5,
	"store_reach_bonus": 40.0,
	"bench_range": 110.0,
}

const STRUCTURES := {
	"bedroll": {
		"id": "bedroll", "name": "Bedroll", "cost": {"wood": 15, "cloth": 12}, "hp": 90.0,
		"solid": false, "tier": 1, "threat": 1.0,
		"desc": "Sets your respawn point. Only the newest one is active.",
	},
	"bunk": {
		"id": "bunk", "name": "Bunk", "cost": {"wood": 22, "cloth": 14}, "hp": 140.0,
		"solid": true, "tier": 1, "threat": 1.0, "protect": true, "houses": 1,
		"desc": "Somewhere for one survivor to sleep. No bunk, no recruit.",
	},
	"watchtower": {
		"id": "watchtower", "name": "Watchtower", "cost": {"wood": 45, "scrap": 20}, "hp": 420.0,
		"solid": true, "tier": 1, "threat": 2.0, "protect": true, "post": "sniper",
		"sniper_range": 520.0, "sniper_dmg": 1.9,
		"desc": "Assign a survivor here and they cover the whole approach.",
	},
	"stash": {
		"id": "stash", "name": "Supply Stash", "cost": {"wood": 25, "scrap": 8}, "hp": 220.0,
		"solid": true, "tier": 1, "threat": 2.0, "protect": true, "store": STASH_SLOTS,
		"desc": "The base pantry and armoury. 48 slots. Survivors and towers feed from this one.",
	},
	"chest": {
		"id": "chest", "name": "Wooden Chest", "cost": {"wood": 20, "sticks": 8}, "hp": 180.0,
		"solid": true, "tier": 1, "threat": 0.5, "protect": true, "store": 16,
		"desc": "Sixteen slots of overflow. Cheap — build as many as you need.",
	},
	"locker": {
		"id": "locker", "name": "Steel Locker", "cost": {"scrap": 34, "parts": 1}, "hp": 420.0,
		"solid": true, "tier": 1, "threat": 1.0, "protect": true, "store": 32,
		"desc": "Thirty-two slots, and it survives a raid that flattens a chest.",
	},
	"workbench": {
		"id": "workbench", "name": "Workbench", "cost": {"wood": 30, "scrap": 18}, "hp": 300.0,
		"solid": true, "tier": 1, "threat": 3.0, "protect": true,
		"desc": "Unlocks crafting while you stand near it. Upgradeable.",
	},
	"barricade": {
		"id": "barricade", "name": "Barricade", "cost": {"wood": 8}, "hp": 160.0,
		"solid": true, "tier": 1, "threat": 0.5, "wall": true,
		"desc": "Cheap, fast, and flimsy. Good for funnelling.",
	},
	"woodWall": {
		"id": "woodWall", "name": "Wood Wall", "cost": {"wood": 16}, "hp": 340.0,
		"solid": true, "tier": 1, "threat": 1.0, "wall": true,
		"desc": "The bread-and-butter wall.",
	},
	# Built from nothing but what the ground gives up: the wall you can raise
	# before you own a single tool that needs metal.
	"stoneWall": {
		"id": "stoneWall", "name": "Stone Wall", "cost": {"stone": 18, "sticks": 4}, "hp": 430.0,
		"solid": true, "tier": 1, "threat": 1.0, "wall": true,
		"desc": "Dry stone. No wood, no scrap — just what you carried up the hill.",
	},
	"reinforcedWall": {
		"id": "reinforcedWall", "name": "Reinforced Wall", "cost": {"wood": 12, "scrap": 22}, "hp": 920.0,
		"solid": true, "tier": 1, "threat": 1.5, "wall": true,
		"desc": "Wood and sheet metal. Buys you real time.",
	},
	"metalWall": {
		"id": "metalWall", "name": "Steel Wall", "cost": {"scrap": 45, "parts": 2}, "hp": 2100.0,
		"solid": true, "tier": 2, "threat": 2.0, "wall": true,
		"desc": "Brutes still get through — eventually.",
	},
	"gate": {
		"id": "gate", "name": "Gate", "cost": {"wood": 22, "scrap": 12}, "hp": 560.0,
		"solid": true, "tier": 1, "threat": 1.5, "gate": true,
		"desc": "Stand next to it and interact to open or close.",
	},
	"spike": {
		"id": "spike", "name": "Spike Trap", "cost": {"wood": 12, "scrap": 10}, "hp": 200.0,
		"solid": false, "tier": 1, "threat": 1.5, "trap": true, "trap_dmg": 26.0, "trap_cd": 0.55,
		"desc": "Shreds anything that walks over it. Wears out.",
	},
	"turret": {
		"id": "turret", "name": "Auto Turret", "cost": {"scrap": 50, "elec": 28, "parts": 6}, "hp": 340.0,
		"solid": true, "tier": 2, "threat": 5.0, "protect": true, "powered": true,
		"range": 330.0, "dmg": 22.0, "fire_cd": 0.28, "mag": 40, "reload": 2.2,
		"desc": "Needs a powered Generator within 260px. Eats 9mm from your stash.",
	},
	"floodlight": {
		"id": "floodlight", "name": "Floodlight", "cost": {"scrap": 22, "elec": 12}, "hp": 200.0,
		"solid": false, "tier": 2, "threat": 2.0, "powered": true, "light_radius": 260.0,
		"desc": "Pushes back the dark. Needs a powered Generator within 260px.",
	},
	"generator": {
		"id": "generator", "name": "Generator", "cost": {"scrap": 38, "elec": 16}, "hp": 380.0,
		"solid": true, "tier": 2, "threat": 4.0, "protect": true, "power_radius": 260.0,
		"fuel_burn": 0.35, "fuel_max": 100.0,
		"desc": "Burns Fuel to power turrets nearby. Loud — raises Threat while running.",
	},
}

const BUILD_ORDER := [
	"woodWall", "stoneWall", "barricade", "reinforcedWall", "metalWall", "gate", "spike",
	"workbench", "stash", "chest", "locker", "bedroll", "bunk", "watchtower",
	"generator", "turret", "floodlight",
]

## What the survivor on a Watchtower is shooting. Bought once for the whole
## base, then chosen per tower, so two towers can answer the same approach
## differently. The axis is noise against effect: arrows are free, weak and
## almost silent; the cannon flattens a group and brings the district down on
## you. `dmg`, `cd` and `range` multiply the survivor's own numbers, so a
## levelled crew is better with every armament rather than with one.
##
## Posting a survivor is Phase 4. The table is here because the tower, its
## cost and its choice of armament are Phase 3.
const ARMAMENTS := {
	"arrows": {
		"id": "arrows", "name": "Arrows", "order": 0, "cost": {},
		"dmg": 1.0, "cd": 1.25, "range": 480.0, "noise": 90.0, "ammo": {"arrow": 1},
		"speed": 780.0, "life": 0.85, "knock": 60.0, "pierce": 0, "color": "#c8a878",
		"desc": "Quiet, cheap, and weak. Nothing hears a tower shooting arrows.",
	},
	"firearrows": {
		"id": "firearrows", "name": "Fire Arrows", "order": 1,
		"cost": {"wood": 20, "cloth": 20, "fuel": 30, "parts": 2},
		"dmg": 0.75, "cd": 1.45, "range": 480.0, "noise": 120.0, "ammo": {"arrow": 1, "fuel": 1},
		"speed": 720.0, "life": 0.85, "knock": 60.0, "pierce": 0, "color": "#ff9a3a", "burns": true,
		"desc": "Sets what it hits alight, and fire spreads. Watch your treeline.",
	},
	"sniper": {
		"id": "sniper", "name": "Sniper Rifle", "order": 2,
		"cost": {"scrap": 70, "parts": 12, "mil": 6},
		"dmg": 1.9, "cd": 1.7, "range": 520.0, "noise": 700.0, "ammo": {"ammoR": 1},
		"speed": 1700.0, "life": 0.55, "knock": 110.0, "pierce": 1, "color": "#e8f0c0",
		"desc": "One shot, one walker. Every district hears it.",
	},
	"cannon": {
		"id": "cannon", "name": "Scrap Cannon", "order": 3,
		"cost": {"scrap": 90, "parts": 8, "elec": 10},
		"dmg": 3.4, "cd": 3.2, "range": 420.0, "noise": 950.0, "ammo": {"scrap": 2},
		"speed": 900.0, "life": 0.5, "knock": 260.0, "pierce": 0, "color": "#ffd08a", "splash": 70.0,
		"desc": "Flattens a group. The loudest thing you can build.",
	},
}

## The one every base starts with, so a manned tower always does something.
const DEFAULT_ARMAMENT := "arrows"

# -------------------------------------------------------------- loot tables --

## Each entry is `{id, min, max, w}`. `id` is a resource, or a prefixed
## `weapon:` / `gear:` / `item:` id — the same grammar a ground pickup is
## decoded with, so the two can never drift apart.
##
## Every table reads true to the thing you are opening: a fridge holds food, a
## wardrobe holds clothes, a gun safe holds guns. That is what makes a
## building's exterior worth reading before you go in.
const LOOT := {
	"cabinet": [
		{"id": "rations", "min": 2, "max": 5, "w": 18}, {"id": "cloth", "min": 3, "max": 8, "w": 30},
		{"id": "wood", "min": 4, "max": 10, "w": 28}, {"id": "scrap", "min": 2, "max": 6, "w": 24},
		{"id": "med", "min": 1, "max": 2, "w": 10}, {"id": "item:bandage", "min": 1, "max": 2, "w": 8},
	],
	"kitchen": [
		{"id": "rations", "min": 3, "max": 8, "w": 34}, {"id": "cloth", "min": 2, "max": 6, "w": 26},
		{"id": "scrap", "min": 3, "max": 8, "w": 30}, {"id": "med", "min": 1, "max": 3, "w": 14},
		{"id": "elec", "min": 1, "max": 2, "w": 10}, {"id": "item:bandage", "min": 1, "max": 1, "w": 10},
	],
	"toolbox": [
		{"id": "scrap", "min": 6, "max": 14, "w": 34}, {"id": "wood", "min": 8, "max": 18, "w": 30},
		{"id": "battery", "min": 1, "max": 2, "w": 12}, {"id": "parts", "min": 1, "max": 2, "w": 16},
		{"id": "elec", "min": 1, "max": 3, "w": 12},
		{"id": "weapon:pipe", "min": 1, "max": 1, "w": 6}, {"id": "weapon:axe", "min": 1, "max": 1, "w": 5},
	],
	"shelf": [
		{"id": "rations", "min": 4, "max": 10, "w": 32}, {"id": "cloth", "min": 4, "max": 10, "w": 28},
		{"id": "med", "min": 2, "max": 5, "w": 24}, {"id": "scrap", "min": 3, "max": 7, "w": 22},
		{"id": "item:bandage", "min": 1, "max": 3, "w": 16}, {"id": "elec", "min": 1, "max": 3, "w": 10},
	],
	"pharmacy": [
		{"id": "med", "min": 5, "max": 12, "w": 40}, {"id": "item:medkit", "min": 1, "max": 2, "w": 24},
		{"id": "item:bandage", "min": 2, "max": 4, "w": 24}, {"id": "cloth", "min": 3, "max": 7, "w": 12},
	],
	"electronics": [
		{"id": "elec", "min": 5, "max": 12, "w": 40}, {"id": "battery", "min": 1, "max": 4, "w": 22},
		{"id": "parts", "min": 1, "max": 3, "w": 24}, {"id": "scrap", "min": 6, "max": 14, "w": 26},
		{"id": "fuel", "min": 5, "max": 12, "w": 10},
	],
	"carTrunk": [
		{"id": "scrap", "min": 4, "max": 10, "w": 34}, {"id": "fuel", "min": 4, "max": 12, "w": 26},
		{"id": "battery", "min": 1, "max": 2, "w": 14}, {"id": "parts", "min": 1, "max": 1, "w": 14},
		{"id": "cloth", "min": 2, "max": 5, "w": 16}, {"id": "elec", "min": 1, "max": 2, "w": 10},
	],
	"policeLocker": [
		{"id": "ammoP", "min": 14, "max": 30, "w": 30}, {"id": "ammoS", "min": 6, "max": 14, "w": 20},
		{"id": "parts", "min": 2, "max": 4, "w": 16}, {"id": "gear:lightVest", "min": 1, "max": 1, "w": 8},
		{"id": "gear:heavyVest", "min": 1, "max": 1, "w": 5}, {"id": "med", "min": 2, "max": 5, "w": 10},
		{"id": "gear:riotHelm", "min": 1, "max": 1, "w": 7}, {"id": "gear:tacGloves", "min": 1, "max": 1, "w": 7},
		{"id": "gear:combatBoots", "min": 1, "max": 1, "w": 6}, {"id": "gear:paddedLegs", "min": 1, "max": 1, "w": 6},
	],
	"gunSafe": [
		{"id": "weapon:pistol", "min": 1, "max": 1, "w": 22}, {"id": "weapon:shotgun", "min": 1, "max": 1, "w": 16},
		{"id": "weapon:rifle", "min": 1, "max": 1, "w": 8}, {"id": "ammoP", "min": 20, "max": 40, "w": 22},
		{"id": "ammoS", "min": 10, "max": 20, "w": 18}, {"id": "parts", "min": 3, "max": 6, "w": 14},
	],
	"militaryCrate": [
		{"id": "rations", "min": 6, "max": 14, "w": 14}, {"id": "mil", "min": 4, "max": 10, "w": 32},
		{"id": "ammoR", "min": 12, "max": 26, "w": 24}, {"id": "parts", "min": 3, "max": 7, "w": 18},
		{"id": "elec", "min": 5, "max": 12, "w": 12}, {"id": "weapon:carbine", "min": 1, "max": 1, "w": 4},
		{"id": "gear:milVest", "min": 1, "max": 1, "w": 5}, {"id": "item:medkit", "min": 1, "max": 2, "w": 5},
	],
	"hospitalCrate": [
		{"id": "rations", "min": 3, "max": 8, "w": 12}, {"id": "med", "min": 8, "max": 16, "w": 36},
		{"id": "item:medkit", "min": 1, "max": 3, "w": 26}, {"id": "elec", "min": 3, "max": 8, "w": 16},
		{"id": "parts", "min": 1, "max": 3, "w": 12}, {"id": "mil", "min": 1, "max": 3, "w": 10},
	],
	"fuelPump": [{"id": "fuel", "min": 12, "max": 26, "w": 100}],
	"fuelDrum": [{"id": "fuel", "min": 8, "max": 18, "w": 70}, {"id": "scrap", "min": 2, "max": 6, "w": 30}],
	"logPile": [
		{"id": "wood", "min": 12, "max": 24, "w": 64}, {"id": "arrow", "min": 4, "max": 10, "w": 8},
		{"id": "scrap", "min": 1, "max": 3, "w": 14}, {"id": "cloth", "min": 1, "max": 3, "w": 12},
		{"id": "parts", "min": 1, "max": 1, "w": 10},
	],
	"crate": [
		{"id": "wood", "min": 8, "max": 18, "w": 30}, {"id": "scrap", "min": 8, "max": 18, "w": 30},
		{"id": "elec", "min": 2, "max": 6, "w": 16}, {"id": "parts", "min": 1, "max": 3, "w": 12},
		{"id": "cloth", "min": 4, "max": 10, "w": 12},
	],
	"bookshelf": [
		{"id": "cloth", "min": 3, "max": 8, "w": 34},      # paper and dust jackets
		{"id": "elec", "min": 1, "max": 3, "w": 16},       # an old radio, a calculator
		{"id": "rations", "min": 1, "max": 3, "w": 14},    # someone's hidden snacks
		{"id": "med", "min": 1, "max": 2, "w": 12}, {"id": "parts", "min": 1, "max": 1, "w": 8},
		{"id": "item:bandage", "min": 1, "max": 2, "w": 16},
	],
	"dresser": [
		{"id": "cloth", "min": 5, "max": 12, "w": 46}, {"id": "item:bandage", "min": 1, "max": 3, "w": 20},
		{"id": "med", "min": 1, "max": 3, "w": 14}, {"id": "scrap", "min": 1, "max": 4, "w": 12},
		{"id": "ammoP", "min": 3, "max": 8, "w": 8},       # a bedside pistol's spare rounds
	],
	"wardrobe": [
		{"id": "cloth", "min": 8, "max": 16, "w": 46}, {"id": "item:bandage", "min": 1, "max": 3, "w": 16},
		{"id": "gear:lightVest", "min": 1, "max": 1, "w": 5}, {"id": "gear:denimPants", "min": 1, "max": 1, "w": 12},
		{"id": "gear:workBoots", "min": 1, "max": 1, "w": 10}, {"id": "gear:hardHat", "min": 1, "max": 1, "w": 6},
		{"id": "gear:workGloves", "min": 1, "max": 1, "w": 10}, {"id": "scrap", "min": 1, "max": 3, "w": 10},
		{"id": "rations", "min": 1, "max": 3, "w": 8},
	],
	"desk": [
		{"id": "elec", "min": 2, "max": 6, "w": 34}, {"id": "battery", "min": 1, "max": 2, "w": 14},
		{"id": "parts", "min": 1, "max": 2, "w": 20}, {"id": "cloth", "min": 2, "max": 5, "w": 18},
		{"id": "scrap", "min": 2, "max": 6, "w": 16}, {"id": "ammoP", "min": 4, "max": 10, "w": 12},
	],
	"filing": [
		{"id": "cloth", "min": 4, "max": 10, "w": 34}, {"id": "battery", "min": 1, "max": 1, "w": 10},
		{"id": "elec", "min": 1, "max": 3, "w": 18}, {"id": "parts", "min": 1, "max": 2, "w": 16},
		{"id": "ammoP", "min": 5, "max": 12, "w": 18}, {"id": "med", "min": 1, "max": 3, "w": 14},
	],
	"fridge": [
		{"id": "rations", "min": 6, "max": 14, "w": 58}, {"id": "med", "min": 1, "max": 3, "w": 20},
		{"id": "cloth", "min": 1, "max": 3, "w": 12}, {"id": "fuel", "min": 1, "max": 3, "w": 10},
	],
	"nightstand": [
		{"id": "med", "min": 2, "max": 5, "w": 30}, {"id": "battery", "min": 1, "max": 2, "w": 16},
		{"id": "item:bandage", "min": 1, "max": 2, "w": 22}, {"id": "ammoP", "min": 4, "max": 10, "w": 20},
		{"id": "cloth", "min": 1, "max": 4, "w": 16}, {"id": "elec", "min": 1, "max": 2, "w": 12},
	],
	"vanity": [
		{"id": "med", "min": 3, "max": 7, "w": 44}, {"id": "item:bandage", "min": 1, "max": 3, "w": 26},
		{"id": "cloth", "min": 2, "max": 6, "w": 22}, {"id": "item:medkit", "min": 1, "max": 1, "w": 8},
	],
	"footlocker": [
		{"id": "mil", "min": 3, "max": 8, "w": 28}, {"id": "arrow", "min": 8, "max": 20, "w": 8},
		{"id": "ammoR", "min": 8, "max": 18, "w": 20}, {"id": "gear:milVest", "min": 1, "max": 1, "w": 6},
		{"id": "gear:milHelm", "min": 1, "max": 1, "w": 6}, {"id": "gear:armGuards", "min": 1, "max": 1, "w": 6},
		{"id": "gear:milGreaves", "min": 1, "max": 1, "w": 6}, {"id": "gear:milBoots", "min": 1, "max": 1, "w": 6},
		{"id": "parts", "min": 2, "max": 5, "w": 14}, {"id": "item:medkit", "min": 1, "max": 2, "w": 8},
		{"id": "rations", "min": 3, "max": 8, "w": 6},
	],
	"vending": [
		{"id": "rations", "min": 5, "max": 12, "w": 62}, {"id": "scrap", "min": 2, "max": 5, "w": 22},
		{"id": "elec", "min": 1, "max": 2, "w": 16},
	],
	"toolrack": [
		{"id": "parts", "min": 2, "max": 5, "w": 34}, {"id": "weapon:bow", "min": 1, "max": 1, "w": 6},
		{"id": "arrow", "min": 6, "max": 16, "w": 10}, {"id": "scrap", "min": 6, "max": 14, "w": 32},
		{"id": "wood", "min": 5, "max": 12, "w": 22}, {"id": "weapon:pipe", "min": 1, "max": 1, "w": 6},
		{"id": "weapon:machete", "min": 1, "max": 1, "w": 4}, {"id": "weapon:axe", "min": 1, "max": 1, "w": 8},
		{"id": "weapon:fireaxe", "min": 1, "max": 1, "w": 3},
	],
	"displaycase": [
		{"id": "elec", "min": 4, "max": 10, "w": 34}, {"id": "battery", "min": 1, "max": 3, "w": 16},
		{"id": "parts", "min": 2, "max": 5, "w": 26}, {"id": "weapon:pistol", "min": 1, "max": 1, "w": 10},
		{"id": "ammoP", "min": 10, "max": 22, "w": 18}, {"id": "scrap", "min": 3, "max": 8, "w": 14},
	],
}

# --------------------------------------------------------------- containers --

## Searchable furniture. `table` and `rolls` say what searching one gives up;
## the world generator only needs the kind to exist.
const CONTAINERS := {
	"cabinet":       {"table": "cabinet",       "rolls": [1, 2], "sprite": "cabinet",     "label": "Cabinet"},
	"kitchen":       {"table": "kitchen",       "rolls": [1, 2], "sprite": "cabinet",     "label": "Kitchen Unit"},
	"toolbox":       {"table": "toolbox",       "rolls": [1, 3], "sprite": "toolbox",     "label": "Toolbox"},
	"shelf":         {"table": "shelf",         "rolls": [1, 2], "sprite": "shelf",       "label": "Shelving"},
	"pharmacy":      {"table": "pharmacy",      "rolls": [2, 3], "sprite": "medcab",      "label": "Medicine Cabinet"},
	"electronics":   {"table": "electronics",   "rolls": [2, 3], "sprite": "crate",       "label": "Parts Bin"},
	"crate":         {"table": "crate",         "rolls": [1, 3], "sprite": "crate",       "label": "Supply Crate"},
	"safe":          {"table": "gunSafe",       "rolls": [2, 3], "sprite": "safe",        "label": "Floor Safe"},
	"locker":        {"table": "dresser",       "rolls": [1, 2], "sprite": "locker",      "label": "Staff Locker"},
	"medcab":        {"table": "vanity",        "rolls": [1, 2], "sprite": "medcab",      "label": "Medicine Cabinet"},
	"carTrunk":      {"table": "carTrunk",      "rolls": [1, 2], "sprite": "trunk",       "label": "Car Trunk"},
	"policeLocker":  {"table": "policeLocker",  "rolls": [2, 3], "sprite": "locker",      "label": "Police Locker"},
	"gunSafe":       {"table": "gunSafe",       "rolls": [2, 3], "sprite": "safe",        "label": "Gun Safe"},
	"militaryCrate": {"table": "militaryCrate", "rolls": [3, 4], "sprite": "milcrate",    "label": "Military Crate"},
	"hospitalCrate": {"table": "hospitalCrate", "rolls": [2, 4], "sprite": "medcab",      "label": "Supply Cabinet"},
	"fuelPump":      {"table": "fuelPump",      "rolls": [1, 2], "sprite": "pump",        "label": "Fuel Pump"},
	"fuelDrum":      {"table": "fuelDrum",      "rolls": [1, 2], "sprite": "drum",        "label": "Fuel Drum"},
	"logPile":       {"table": "logPile",       "rolls": [2, 3], "sprite": "logs",        "label": "Log Pile"},
	"bookshelf":     {"table": "bookshelf",     "rolls": [1, 2], "sprite": "bookshelf",   "label": "Bookshelf"},
	"dresser":       {"table": "dresser",       "rolls": [1, 2], "sprite": "dresser",     "label": "Dresser"},
	"wardrobe":      {"table": "wardrobe",      "rolls": [1, 3], "sprite": "wardrobe",    "label": "Wardrobe"},
	"desk":          {"table": "desk",          "rolls": [1, 2], "sprite": "desk",        "label": "Desk"},
	"filing":        {"table": "filing",        "rolls": [1, 3], "sprite": "filing",      "label": "Filing Cabinet"},
	"fridge":        {"table": "fridge",        "rolls": [1, 2], "sprite": "fridge",      "label": "Refrigerator"},
	"nightstand":    {"table": "nightstand",    "rolls": [1, 1], "sprite": "nightstand",  "label": "Nightstand"},
	"vanity":        {"table": "vanity",        "rolls": [1, 2], "sprite": "vanity",      "label": "Bathroom Vanity"},
	"footlocker":    {"table": "footlocker",    "rolls": [2, 3], "sprite": "footlocker",  "label": "Footlocker"},
	"vending":       {"table": "vending",       "rolls": [2, 3], "sprite": "vending",     "label": "Vending Machine"},
	"toolrack":      {"table": "toolrack",      "rolls": [1, 3], "sprite": "toolrack",    "label": "Tool Rack"},
	"displaycase":   {"table": "displaycase",   "rolls": [2, 3], "sprite": "displaycase", "label": "Display Case"},
}

## What furnishes each kind of building, as [kind, weight] picks. A house
## fills with wardrobes and a precinct with filing cabinets, so a building's
## exterior tells you what is worth searching inside.
const FURNISHING := {
	"house": [
		["cabinet", 12], ["dresser", 14], ["wardrobe", 12], ["bookshelf", 12],
		["nightstand", 12], ["fridge", 9], ["kitchen", 9], ["vanity", 8],
		["desk", 6], ["toolbox", 4], ["shelf", 4],
	],
	"store": [
		["shelf", 26], ["vending", 14], ["displaycase", 10], ["fridge", 12],
		["kitchen", 8], ["cabinet", 8], ["filing", 6], ["pharmacy", 8], ["desk", 6],
	],
	"hardware": [
		["toolrack", 24], ["toolbox", 22], ["shelf", 18], ["crate", 14],
		["displaycase", 8], ["desk", 6], ["filing", 4],
	],
	"pawn": [
		["displaycase", 30], ["electronics", 24], ["shelf", 14], ["desk", 12],
		["filing", 8], ["safe", 6],
	],
	"police": [
		["policeLocker", 24], ["filing", 20], ["locker", 14], ["desk", 14],
		["gunSafe", 8], ["vending", 6], ["shelf", 6], ["footlocker", 6],
	],
	"hospital": [
		["pharmacy", 24], ["hospitalCrate", 20], ["medcab", 16], ["vanity", 10],
		["filing", 8], ["desk", 8], ["vending", 6], ["fridge", 6], ["bookshelf", 4],
	],
	"industrial": [
		["electronics", 24], ["crate", 20], ["toolrack", 16], ["toolbox", 14],
		["filing", 8], ["desk", 8], ["shelf", 6],
	],
	"military": [
		["militaryCrate", 26], ["footlocker", 24], ["gunSafe", 10], ["filing", 8],
		["desk", 8], ["electronics", 8], ["vending", 4],
	],
	"barn": [
		["toolrack", 20], ["toolbox", 18], ["crate", 16], ["shelf", 12],
		["fuelDrum", 12], ["logPile", 10], ["cabinet", 6], ["kitchen", 6],
	],
	"farmstore": [
		["shelf", 22], ["toolrack", 16], ["crate", 14], ["vending", 10],
		["fuelDrum", 10], ["fridge", 8], ["cabinet", 8], ["toolbox", 8], ["desk", 4],
	],
	"cabin": [
		["cabinet", 14], ["bookshelf", 12], ["footlocker", 12], ["fridge", 10],
		["kitchen", 8], ["wardrobe", 8], ["nightstand", 8], ["toolbox", 8],
		["gunSafe", 7], ["shelf", 6],
	],
	"lumber": [
		["logPile", 30], ["toolrack", 16], ["toolbox", 14], ["crate", 12],
		["fuelDrum", 10], ["shelf", 6], ["desk", 6], ["cabinet", 6],
	],
	"junk": [
		["toolbox", 24], ["crate", 18], ["electronics", 16], ["toolrack", 12],
		["fuelDrum", 10], ["shelf", 8], ["filing", 6], ["desk", 6],
	],
	"apartment": [
		["dresser", 14], ["wardrobe", 12], ["nightstand", 12], ["bookshelf", 10],
		["fridge", 10], ["kitchen", 10], ["cabinet", 10], ["vanity", 8],
		["desk", 6], ["locker", 4], ["vending", 4],
	],
	"office": [
		["desk", 26], ["filing", 22], ["electronics", 12], ["vending", 10],
		["locker", 8], ["bookshelf", 8], ["cabinet", 8], ["shelf", 6],
	],
	"bank": [
		["safe", 22], ["filing", 20], ["desk", 18], ["displaycase", 10],
		["locker", 10], ["cabinet", 8], ["electronics", 6], ["vending", 6],
	],
	"mall": [
		["shelf", 20], ["displaycase", 16], ["vending", 14], ["wardrobe", 10],
		["pharmacy", 10], ["fridge", 8], ["kitchen", 8], ["electronics", 8], ["cabinet", 6],
	],
	"drugstore": [
		["pharmacy", 26], ["shelf", 24], ["medcab", 10], ["vending", 10],
		["fridge", 10], ["cabinet", 8], ["displaycase", 6], ["desk", 6],
	],
	"gunshop": [
		["displaycase", 30], ["gunSafe", 22], ["shelf", 14], ["toolrack", 12],
		["policeLocker", 8], ["footlocker", 8], ["desk", 6],
	],
}
