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

# --------------------------------------------------------------- containers --

## Searchable furniture. `table` and `rolls` are consumed by loot (Phase 3);
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
