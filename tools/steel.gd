extends SceneTree
## One-shot content write for chapter 2's material (progression step D,
## `tasks/progression-plan.md` §7), run headless:
##
##   godot --headless --path . -s tools/steel.gd
##
## Sheet Metal and Steel Bar; the Hacksaw that cuts wrecks; the Forge that
## turns metal into bars; every chapter 2 recipe recosted in Steel Bar; and
## the three chore items Workbench II unlocks — the Pack Frame, the Oil
## Lantern and the Repair Kit. Through `DataTable.encode`, the only thing
## allowed to write a table (PROJECT.md §10).

const NEW_RES := [
	{"id": "sheetMetal", "name": "Sheet Metal", "short": "SHMT", "color": "#8e9aa6", "stack": 30, "wt": 2.0,
		"found": "car wrecks, with a Hacksaw — thickest at Rust Belt Salvage"},
	{"id": "steelBar", "name": "Steel Bar", "short": "STEL", "color": "#c0c8d0", "stack": 30, "wt": 2.0,
		"found": "the Forge, from Sheet Metal and wood"},
]

const NEW_WEAPONS := [
	{"id": "hacksaw", "name": "Hacksaw", "kind": "melee", "tier": 2, "tool": true, "hacksaw": true,
		"dmg": 14.0, "cd": 0.5, "arc": 0.7, "range": 44.0, "knock": 60.0, "noise": 70.0, "chop_mul": 1.0,
		"crit": 0.03, "crit_mul": 1.8, "stagger": 0.15, "dur": 600, "color": "#a8b0b8",
		"salvage": {"scrap": 6}},
]

const NEW_GEAR := [
	{"id": "oilLantern", "name": "Oil Lantern", "slot": "offhand", "tier": 2, "dr": 0.0, "wt": 2.5, "color": "#e8b45a",
		"battery": "fuel", "burn": 2700.0,
		"light": {"radius": 260.0, "strength": 1.0, "warm": "#ffc070"}},
]

const NEW_CONSUMABLES := [
	{"id": "packFrame", "name": "Pack Frame", "color": "#a3763f", "stack": 1, "wt": 3.0, "time": 1.2,
		"verb": "Fit", "pack": 1},
	{"id": "repairKit", "name": "Repair Kit", "color": "#9aa2ab", "stack": 5, "wt": 1.0, "time": 2.0,
		"verb": "Use", "mend": 0.5},
]

## Recipe id -> new cost, in Steel Bar (Progression Map §7).
const RECOST := {
	"machete": {"steelBar": 4, "wood": 2, "cloth": 1},
	"metalSpear": {"steelBar": 2, "wood": 4},
	"doubleBitAxe": {"steelBar": 6, "wood": 8},
	"fireaxe": {"steelBar": 3, "wood": 6},
	"steelpick": {"steelBar": 4, "wood": 6},
	"compoundBow": {"steelBar": 2, "sticks": 8, "cloth": 4, "parts": 1},
	"pipeShotgun": {"steelBar": 4, "parts": 2, "wood": 4},
	"pistol": {"steelBar": 5, "parts": 4},
	"riotHelm": {"steelBar": 4, "cloth": 4},
	"heavyVest": {"steelBar": 8, "cloth": 12},
	"tacGloves": {"steelBar": 2, "cloth": 6},
	"paddedLegs": {"steelBar": 5, "cloth": 10},
	"combatBoots": {"steelBar": 3, "cloth": 6},
}

const NEW_RECIPES := [
	{"id": "hacksaw", "name": "Hacksaw", "bench": 2, "wave": 1, "cost": {"scrap": 12, "wood": 6, "cloth": 2}, "give": {"weapon": "hacksaw"}, "xp": 14,
		"notes": "Chapter 2's Foothold: the tool that turns the wrecks you have walked past since minute one into Sheet Metal, and opens what is padlocked."},
	{"id": "steelBar", "name": "Steel Bar", "bench": 0, "wave": 1, "station": "forge", "cost": {"sheetMetal": 1, "wood": 2}, "give": {"res": {"steelBar": 1}}, "xp": 3,
		"notes": "Made at the Forge and nowhere else: `station`, like the chemistry, so no workbench tier hands it out."},
	{"id": "packFrame", "name": "Pack Frame", "bench": 2, "wave": 2, "cost": {"steelBar": 6, "cloth": 12}, "give": {"item": "packFrame", "n": 1}, "xp": 20,
		"notes": "The first chore removed: fit it and you carry 160."},
	{"id": "oilLantern", "name": "Oil Lantern", "bench": 2, "wave": 2, "cost": {"steelBar": 3, "cloth": 2}, "give": {"gear": "oilLantern"}, "xp": 12,
		"notes": "A fill of Fuel lasts about five nights. The torch stops being a thing you remake every dusk."},
	{"id": "repairKit", "name": "Repair Kit x2", "bench": 2, "wave": 2, "cost": {"steelBar": 1, "scrap": 4, "cloth": 2}, "give": {"item": "repairKit", "n": 2}, "xp": 6,
		"notes": "Mends the held weapon by half, anywhere. The bench is still where it comes back whole."},
]

const NEW_STRUCTURES := [
	{"id": "forge", "name": "Forge", "tier": 2, "wave": 1, "cost": {"stone": 30, "scrap": 20, "wood": 10},
		"hp": 320.0, "solid": true, "protect": true, "station": "forge", "threat": 2.5,
		"desc": "Sheet Metal and wood go in, Steel Bar comes out. Stand near it to work.",
		"notes": "Chapter 2's station. A station, not a workbench rung, for the Chemistry Station's reason: what it makes is the material every chapter 2 recipe is priced in."},
]

## Chapter 2's recipes move to the Kit; the Hacksaw and the Forge are the
## Foothold. (The waves were written before the material existed.)
const WAVE := {"machete": 2, "metalSpear": 2, "fireaxe": 2, "steelpick": 2, "lockpick": 2}


func _init() -> void:
	_res()
	_weapons()
	_gear()
	_consumables()
	_recipes()
	_structures()
	_loot()
	quit()


func _load(path: String) -> Dictionary:
	var got := DataTable.decode(FileAccess.get_file_as_string(path))
	for e: String in got.errors:
		push_error("%s: %s" % [path, e])
	return got.doc


func _save(path: String, doc: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(DataTable.encode(doc))
	f.close()


func _has(doc: Dictionary, id: String) -> bool:
	for row: Dictionary in doc.rows:
		if String(row.id) == id:
			return true
	return false


func _append(path: String, rows: Array, extra_fields := {}) -> void:
	var doc := _load(path)
	for k in extra_fields:
		doc.fields[k] = extra_fields[k]
	var n := 0
	for row: Dictionary in rows:
		if _has(doc, String(row.id)):
			print("%s: %s already there" % [path, row.id])
			continue
		doc.rows.append(row.duplicate(true))
		n += 1
	_save(path, doc)
	print("%s: %d added" % [path, n])


func _res() -> void:
	_append("res://data/res.json", NEW_RES)


func _weapons() -> void:
	_append("res://data/weapons.json", NEW_WEAPONS, {"hacksaw": {"type": "bool"}})


func _gear() -> void:
	_append("res://data/gear.json", NEW_GEAR)


func _consumables() -> void:
	_append("res://data/consumables.json", NEW_CONSUMABLES, {"pack": {"type": "int"}, "mend": {"type": "float"}})


func _recipes() -> void:
	var path := "res://data/recipes.json"
	var doc := _load(path)
	var recost := 0
	for row: Dictionary in doc.rows:
		var id := String(row.id)
		if RECOST.has(id):
			row.cost = RECOST[id].duplicate()
			recost += 1
		if WAVE.has(id):
			row.wave = int(WAVE[id])
	var n := 0
	for r: Dictionary in NEW_RECIPES:
		if _has(doc, String(r.id)):
			# Re-run: fill in what an earlier pass left out.
			for row: Dictionary in doc.rows:
				if String(row.id) == String(r.id) and not row.has("name"):
					row.name = r.name
			continue
		doc.rows.append(r.duplicate(true))
		n += 1
	_save(path, doc)
	print("data/recipes.json: %d recosted, %d added" % [recost, n])


func _structures() -> void:
	_append("res://data/structures.json", NEW_STRUCTURES)


## Every weapon is found somewhere (`wear_test`): a Hacksaw hangs on the odd
## tool rack and lies in the odd toolbox, rarely — the bench is where it comes
## from.
func _loot() -> void:
	var path := "res://data/loot.json"
	var doc := _load(path)
	var n := 0
	for row: Dictionary in doc.rows:
		if not String(row.id) in ["toolrack", "toolbox"]:
			continue
		var there := false
		for e: Dictionary in row.entries:
			if String(e.id) == "weapon:hacksaw":
				there = true
		if not there:
			row.entries.append({"id": "weapon:hacksaw", "min": 1, "max": 1, "w": 3})
			n += 1
	_save(path, doc)
	print("data/loot.json: hacksaw in %d tables" % n)
