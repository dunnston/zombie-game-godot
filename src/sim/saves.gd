class_name Saves
extends RefCounted
## Save slots: an index of what is on disk, and the summaries the title screen
## reads. `SaveGame` writes and reads a *payload*; this decides which file, and
## remembers enough about each one to be worth choosing between.
##
## The index is deliberately separate from the payloads. Listing four saves
## should not mean parsing four world-sized JSON files, so day, level, kills
## and play time live in one small file that is rewritten on every save.
##
## An index entry can outlive its payload (a file deleted from outside) and a
## payload can outlive its entry (an index that failed to write). Both are
## survivable and neither is silent: `list()` reports what it can read, and a
## slot whose payload will not load says so with the reason `SaveGame` gives.

const DIR := "user://saves"
const INDEX := "user://saves/index.json"
## How many slots the title screen offers. Anything numbered above this is
## out of the player's reach — the tests use that range, so a headless run can
## never overwrite a real save.
const MAX_SLOTS := 6
## How often a game with a slot writes itself down.
const AUTOSAVE_EVERY := 120.0


static func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))


static func read_index() -> Dictionary:
	if not FileAccess.file_exists(INDEX):
		return {"v": 1, "current": -1, "slots": {}}
	var f := FileAccess.open(INDEX, FileAccess.READ)
	if f == null:
		return {"v": 1, "current": -1, "slots": {}}
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or not data.has("slots"):
		return {"v": 1, "current": -1, "slots": {}}
	return data


static func write_index(idx: Dictionary) -> bool:
	_ensure_dir()
	var f := FileAccess.open(INDEX, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(idx))
	f.close()
	return true


## Every slot that has a payload on disk, newest first. The index is the
## source of the *summary*; the file is the source of whether it exists at all,
## so an index entry with no file is dropped rather than offered.
static func list() -> Array[Dictionary]:
	var idx := read_index()
	var out: Array[Dictionary] = []
	for key in idx.slots:
		var n := int(key)
		if not FileAccess.file_exists(SaveGame.slot_path(n)):
			continue
		var s: Dictionary = idx.slots[key].duplicate()
		s["slot"] = n
		out.append(s)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("updated", 0.0)) > float(b.get("updated", 0.0)))
	return out


## The slot CONTINUE opens: the one last chosen, or failing that the one last
## written. Loading marks a slot current before it saves, so coming straight
## back after a LOAD returns to the game that was picked rather than to
## whichever happened to be written last.
static func latest() -> Dictionary:
	var idx := read_index()
	var current := int(idx.get("current", -1))
	var all := list()
	for s in all:
		if int(s.slot) == current:
			return s
	return all[0] if not all.is_empty() else {}


static func has_any() -> bool:
	return not list().is_empty()


## The lowest slot number with nothing in it, or -1 when they are all taken.
static func first_free() -> int:
	var idx := read_index()
	for n in range(MAX_SLOTS):
		if not idx.slots.has(str(n)) and not FileAccess.file_exists(SaveGame.slot_path(n)):
			return n
	return -1


## A name nobody else is using: "Game 3", unless one was given.
static func default_name() -> String:
	var taken := {}
	for s in list():
		taken[String(s.get("name", ""))] = true
	for i in range(1, MAX_SLOTS + 2):
		var n := "Game %d" % i
		if not taken.has(n):
			return n
	return "Game"


## Writes the live game into a slot and refreshes what the title screen shows.
## The summary is taken from the sim rather than from the payload, because the
## payload is a world and this has to stay small.
static func save_to(sim: GameSim, slot: int, name_ := "") -> Dictionary:
	var r := SaveGame.save_to(sim, slot)
	if not r.ok:
		return r
	var idx := read_index()
	var key := str(slot)
	var entry: Dictionary = idx.slots.get(key, {})
	if String(entry.get("name", "")).is_empty():
		entry["name"] = name_ if not name_.is_empty() else default_name()
	if not entry.has("created"):
		entry["created"] = Time.get_unix_time_from_system()
	entry["updated"] = Time.get_unix_time_from_system()
	entry["playtime"] = sim.time
	entry["day"] = sim.clock.day
	entry["level"] = sim.players[0].level if not sim.players.is_empty() else 1
	entry["kills"] = int(sim.stats.get("kills", 0))
	entry["seed"] = sim.world.world_seed
	entry["version"] = SaveGame.VERSION
	idx.slots[key] = entry
	idx["current"] = slot
	write_index(idx)
	return {"ok": true, "reason": ""}


## Marks a slot as the one CONTINUE should open, without writing a payload.
static func mark_current(slot: int) -> void:
	var idx := read_index()
	idx["current"] = slot
	write_index(idx)


static func delete(slot: int) -> bool:
	var path := SaveGame.slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var idx := read_index()
	idx.slots.erase(str(slot))
	if int(idx.get("current", -1)) == slot:
		idx["current"] = -1
	return write_index(idx)


# ------------------------------------------------------------------ labels --

## "2h 14m", "14m", "40s" — long enough to be worth showing, short enough to
## sit in a row.
static func playtime_label(seconds: float) -> String:
	var s := int(maxf(0.0, seconds))
	if s < 60:
		return "%ds" % s
	if s < 3600:
		return "%dm" % (s / 60)
	return "%dh %dm" % [s / 3600, (s % 3600) / 60]


## "just now", "12 minutes ago", "3 days ago". Relative rather than a
## timestamp: what matters on a save list is which one you were last in.
static func when_label(unix: float) -> String:
	if unix <= 0.0:
		return "never"
	var d := Time.get_unix_time_from_system() - unix
	if d < 90.0:
		return "just now"
	if d < 3600.0:
		return "%d minutes ago" % int(d / 60.0)
	if d < 86400.0:
		var h := int(d / 3600.0)
		return "%d hour%s ago" % [h, "" if h == 1 else "s"]
	var days := int(d / 86400.0)
	return "%d day%s ago" % [days, "" if days == 1 else "s"]


## One line describing a slot, for the list.
static func summary_line(s: Dictionary) -> String:
	var kills := int(s.get("kills", 0))
	return "Day %d  ·  level %d  ·  %d kill%s  ·  %s played" % [
		int(s.get("day", 1)), int(s.get("level", 1)), kills, "" if kills == 1 else "s",
		playtime_label(float(s.get("playtime", 0.0)))]
