extends SceneTree
## Turns a house plan in metres into a layout row in `data/layouts.json`
## (`Layout`, PROJECT.md §10 "House layouts"), run headless:
##
##   godot --headless --path . -s tools/import_layout.gd -- <plan> <id> [--floor=N]
##
## `<plan>` is a `house_layout.json` as the owner's drafts come (rooms as
## wall-centreline bounds, openings with a centre and a clear width, objects
## with a plan centre, a footprint and the way they face), or the `.zip` it
## came in. One tile is one metre (`Config.STAGE_UNITS`), so a wall at
## x = 4.8 m is the wall tile in column 5, and the plan's front (d = 0) is
## the map's bottom row, which faces south like every door in the town.
## Every object is mapped by its name to what the game has (`NAMES`); one
## it cannot map, or cannot fit on the floor where the plan put it, is
## reported and left out, never guessed. The row is written through
## `DataTable.encode`, the only thing allowed to write a table, and then
## checked the way the tests check every layout (`Layout.problems`,
## `Layout.playable`), so the report says whether the house works before
## anyone walks it.

const PATH := LayoutFile.PATH
## The plan's facing letters in quarter turns from south (`Furnish.DIRS`).
const FACING := {"S": 0, "E": 1, "N": 2, "W": 3}
## An opening is never narrower than the town's doorways.
const MIN_OPENING := 2


## What the plan calls a thing -> what the game stands there. Matched on
## the lowercased name, exact first, then by the first entry whose key the
## name contains. `skip` names what the plan draws that the game has no
## tile for (a lamp on a table, the hood over a stove, a chair that comes
## with its table); `repeat` fills a run (a counter run) with copies.
const NAMES := {
	# living
	"sofa": {"what": "sofa"},
	"couch": {"what": "sofa"},
	"loveseat": {"what": "loveseat"},
	"armchair": {"what": "armchair"},
	"coffee table": {"what": "coffee_table"},
	"side table": {"what": "table_small"},
	"end table": {"what": "table_small"},
	"tv stand": {"what": "tv_stand"},
	"media console": {"what": "tv_stand"},
	"tv": {"skip": "the television is part of the TV stand"},
	"television": {"skip": "the television is part of the TV stand"},
	"table lamp": {"skip": "lamps stand on the furniture that draws them"},
	"floor lamp": {"skip": "lamps stand on the furniture that draws them"},
	"rug": {"what": "rug", "solid": false},
	"fireplace": {"what": "fireplace"},
	"piano": {"what": "piano"},
	"bookshelf": {"container": "bookshelf"},
	"bookcase": {"container": "bookshelf"},
	"houseplant": {"what": "houseplant", "solid": false},
	"plant": {"what": "houseplant", "solid": false},
	"painting": {"what": "painting", "kind": "wall"},
	"picture": {"what": "painting", "kind": "wall"},
	"wall clock": {"what": "wall_clock", "kind": "wall"},
	"clock": {"what": "wall_clock", "kind": "wall"},
	"mirror": {"what": "mirror", "kind": "wall"},
	# dining
	"dining table": {"what": "dining"},
	"dining chair": {"skip": "the chairs come with the dining table"},
	"sideboard": {"container": "cabinet"},
	"buffet": {"container": "cabinet"},
	"hutch": {"container": "cabinet"},
	# entry
	"entry console": {"container": "cabinet"},
	"console table": {"container": "cabinet"},
	"shoe bench": {"what": "bench"},
	"bench": {"what": "bench"},
	"coat hooks": {"skip": "nothing hangs on a hook yet"},
	"coat rack": {"skip": "nothing hangs on a hook yet"},
	# kitchen
	"refrigerator": {"container": "fridge"},
	"fridge": {"container": "fridge"},
	"range": {"what": "stove"},
	"oven": {"what": "stove"},
	"stove": {"what": "stove"},
	"range hood": {"skip": "the hood is part of the stove"},
	"sink base": {"what": "sink"},
	"kitchen sink": {"what": "sink"},
	"sink bowl": {"skip": "the bowl is part of the sink"},
	"dishwasher": {"container": "kitchen"},
	"counter": {"container": "kitchen", "repeat": true},
	"island": {"what": "island"},
	"upper cabinet": {"skip": "upper cabinets are in the kitchen unit's model"},
	"pantry": {"what": "pantry_shelf"},
	"cabinet": {"container": "cabinet"},
	# bathroom
	"toilet": {"what": "toilet"},
	"vanity": {"container": "vanity"},
	"bathtub": {"what": "bathtub"},
	"tub": {"what": "bathtub"},
	"shower": {"what": "shower"},
	"medicine cabinet": {"container": "medcab"},
	"towel": {"what": "towels", "solid": false},
	"washer": {"what": "washer"},
	"washing machine": {"what": "washer"},
	"dryer": {"what": "dryer"},
	"hamper": {"what": "laundry_basket", "solid": false},
	"laundry basket": {"what": "laundry_basket", "solid": false},
	"folding counter": {"container": "cabinet"},
	"linen cabinet": {"container": "cabinet"},
	"linen closet": {"container": "cabinet"},
	# bedroom
	"queen bed": {"what": "bed_double"},
	"king bed": {"what": "bed_double"},
	"double bed": {"what": "bed_double"},
	"full bed": {"what": "bed_single"},
	"twin bed": {"what": "bed_single"},
	"single bed": {"what": "bed_single"},
	"bunk bed": {"what": "bunk_bed"},
	"crib": {"what": "crib"},
	"bed": {"what": "bed_single"},
	"nightstand": {"container": "nightstand"},
	"night stand": {"container": "nightstand"},
	"bedside table": {"container": "nightstand"},
	"dresser": {"container": "dresser"},
	"chest of drawers": {"container": "dresser"},
	"wardrobe": {"container": "wardrobe"},
	"armoire": {"container": "wardrobe"},
	"hanging clothes": {"container": "wardrobe"},
	"closet": {"container": "wardrobe"},
	"desk chair": {"skip": "the chair comes with the desk"},
	"office chair": {"skip": "the chair comes with the desk"},
	"desk": {"container": "desk"},
	"shelf unit": {"container": "bookshelf"},
	"shelves": {"container": "bookshelf"},
	"filing": {"container": "filing"},
	"radiator": {"what": "radiator"},
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var plan := ""
	var id := ""
	var storey := 0
	for a in args:
		if a.begins_with("--floor="):
			storey = int(a.trim_prefix("--floor="))
		elif a.begins_with("--"):
			continue
		elif plan.is_empty():
			plan = a
		elif id.is_empty():
			id = a
	if plan.is_empty() or id.is_empty():
		printerr("usage: import_layout.gd -- <plan.json|.zip> <layout-id> [--floor=N]")
		quit(2)
		return
	# A first run makes the table before Config loads it, so the load is quiet.
	if not FileAccess.file_exists(PATH):
		LayoutFile.save(LayoutFile.SCHEMA.duplicate(true))
	var text := _read_plan(plan)
	if text.is_empty():
		printerr("could not read a house_layout.json from %s" % plan)
		quit(1)
		return
	var doc: Variant = JSON.parse_string(text)
	if typeof(doc) != TYPE_DICTIONARY:
		printerr("%s is not a JSON object" % plan)
		quit(1)
		return
	var report := PackedStringArray()
	var row := to_row(doc, id, storey, report)
	row["notes"] = "Imported by tools/import_layout from %s (floor %d) on %s." % [plan.get_file(), storey, Time.get_date_string_from_system()]
	for line in report:
		print(line)
	var problems := Layout.problems(row)
	for p in problems:
		print("PROBLEM: %s" % p)
	_write(row)
	# The table was loaded before the row existed; stamp the row as the
	# game will to ask Furnish's rule of the whole house.
	LayoutFile.refresh()
	var world := World.new(1, "lab:" + id)
	var playable := not world.buildings.is_empty() and Layout.playable(world, world.buildings[0])
	print("")
	for line in row.map:
		print("  " + line)
	print("")
	print("%s: %d things, %d problems, %s" % [id, row.things.size(), problems.size(), "playable" if playable else "NOT PLAYABLE: a room is cut off or a container cannot be reached"])
	print("written to %s" % PATH)
	quit(0 if problems.is_empty() and playable else 1)


## The plan's text from a .json file or the first house_layout.json in a .zip.
func _read_plan(path: String) -> String:
	if path.to_lower().ends_with(".zip"):
		var z := ZIPReader.new()
		if z.open(path) != OK:
			return ""
		for f in z.get_files():
			if f.get_file() == "house_layout.json":
				return z.read_file(f).get_string_from_utf8()
		return ""
	return FileAccess.get_file_as_string(path)


## A plan floor as a layout row. `report` gets a line per opening and object.
##
## The grid: every distinct wall line of the floor (the rooms' bounds) is a
## tile row or column of its own, and a room keeps its whole metres between
## two lines — a 2.2 m powder room is two tiles across, a 4.8 m living room
## four — because a wall here is a metre thick and the plan's is fifteen
## centimetres: snapping centrelines straight to tiles made that powder
## room one tile wide with three fittings in it. `Grid` maps a plan
## coordinate to a tile position along one axis.
static func to_row(doc: Dictionary, id: String, storey: int, report: PackedStringArray) -> Dictionary:
	var rooms: Array = []
	for r in doc.get("rooms", []):
		if int(r.get("floor", 0)) == storey:
			rooms.append(r)
	if rooms.is_empty():
		report.append("no rooms on floor %d" % storey)
		return {"id": id, "use": "house", "floor": "wood", "map": [], "things": []}
	var xs: Array[float] = []
	var ds: Array[float] = []
	for r in rooms:
		var b: Array = r.bounds_x_d_m
		_line(xs, float(b[0]))
		_line(xs, float(b[2]))
		_line(ds, float(b[1]))
		_line(ds, float(b[3]))
	var gx := Grid.new(xs)
	var gd := Grid.new(ds)
	var cols := gx.tiles
	var rows := gd.tiles
	var grid: Array[PackedStringArray] = []
	for y in range(rows):
		var line := PackedStringArray()
		line.resize(cols)
		line.fill(Layout.OUT)
		grid.append(line)
	# Walls on every room's border, floor strictly inside. Two rooms that
	# share a line share the wall tile. The plan's front (d = 0) is the
	# bottom row, so the door faces south like every door in the town.
	var room_rects := {}
	for r in rooms:
		var b: Array = r.bounds_x_d_m
		var x0 := gx.line(float(b[0]))
		var x1 := gx.line(float(b[2]))
		var d0 := gd.line(float(b[1]))
		var d1 := gd.line(float(b[3]))
		room_rects[String(r.get("id", ""))] = Rect2i(x0, rows - 1 - d1, x1 - x0 + 1, d1 - d0 + 1)
		for d in range(d0, d1 + 1):
			for x in range(x0, x1 + 1):
				var edge := x == x0 or x == x1 or d == d0 or d == d1
				var y := rows - 1 - d
				if edge:
					if grid[y][x] != Layout.FLOOR:
						grid[y][x] = Layout.WALL
				else:
					grid[y][x] = Layout.FLOOR
	# Openings: a doorway where one side is outside, a gap otherwise; the
	# town's two tiles wide where the wall has room, one where it has not.
	var doors := 0
	for o in doc.get("openings", []):
		if int(o.get("floor", 0)) != storey:
			continue
		var c: Array = o.center_x_d_m
		var outside := false
		for side in o.get("connects", []):
			if String(side).begins_with("OUTSIDE"):
				outside = true
		var along_x := String(o.get("wall_axis", "X")).to_upper() == "X"
		var tag := "%s %s" % [o.get("id", "?"), "->".join(o.get("connects", []))]
		var cx := float(c[0])
		var cd := float(c[1])
		var across := gd.line(cd) if along_x else gx.line(cx)
		var u := gx.u(cx) if along_x else gd.u(cd)
		if _cut(grid, Layout.DOOR if outside else Layout.GAP, along_x, across, u, 2, report, tag) > 0 and outside:
			doors += 1
	# A stairwell opens onto the hall where the stairs are stepped onto. The
	# game has no stairs, so on either floor it is a nook off the hall.
	var stairs: Dictionary = doc.get("stairs", {})
	for r in rooms:
		if not String(r.get("name", "")).to_lower().contains("stair"):
			continue
		var p: Array = stairs.get("ground_approach_m" if storey == 0 else "upper_exit_m", [])
		if p.size() < 3:
			continue
		var px := float(p[0])
		var pd := -float(p[2])
		var b: Array = r.bounds_x_d_m
		var tag := "%s stairwell" % r.get("id", "?")
		if pd < float(b[1]) or pd > float(b[3]):
			_cut(grid, Layout.GAP, true, gd.line(float(b[1]) if pd < float(b[1]) else float(b[3])), gx.u(px), 2, report, tag)
		else:
			_cut(grid, Layout.GAP, false, gx.line(float(b[0]) if px < float(b[0]) else float(b[2])), gd.u(pd), 2, report, tag)
	# A floor with no way in from outside (an upper storey) gets the front
	# door: the town has one storey, and this one stands on the ground.
	if doors == 0:
		_cut(grid, Layout.DOOR, true, gd.line(ds[0]), gx.u((xs[0] + xs[xs.size() - 1]) / 2.0), cols, report, "no doorway on this floor; the front wall")
	var map: Array = []
	for line in grid:
		map.append("".join(line))
	var row := {"id": id, "use": "house", "floor": "wood", "map": map, "things": []}
	# Objects, in the plan's order, each where its centre falls.
	var taken := {}
	var floor_ys: Array = doc.get("structure", {}).get("floor_y_m", [])
	var floor_y := float(floor_ys[storey]) if storey < floor_ys.size() else 0.0
	for o in doc.get("objects", []):
		if int(o.get("floor", 0)) != storey:
			continue
		var name := String(o.get("name", "")).to_lower()
		var spec := _spec_for(name)
		var tag := "%s %s" % [o.get("id", "?"), o.get("name", "?")]
		var room: Rect2i = room_rects.get(String(o.get("room", "")), Rect2i(0, 0, cols, rows))
		if spec.is_empty():
			report.append("%s: SKIPPED, no mapping for '%s' (add one to NAMES in tools/import_layout.gd)" % [tag, name])
			continue
		if spec.has("skip"):
			report.append("%s: skipped, %s" % [tag, spec.skip])
			continue
		# Raised off its floor (a cabinet over a vanity, a mirror): only a
		# piece that hangs can be, the rest stand on the floor or not at all.
		var raised := float(o.get("position_m", [0, 0, 0])[1]) - floor_y > 0.3
		if raised and String(spec.get("kind", "furniture")) != "wall":
			report.append("%s: skipped, it is mounted %.1f m up and the game stands a %s on the floor" % [tag, float(o.position_m[1]) - floor_y, spec.get("what", spec.get("container", "?"))])
			continue
		var centre: Array = o.get("plan_center_x_d_m", [float(o.position_m[0]), -float(o.position_m[2])])
		var cx := float(centre[0])
		var cd := float(centre[1])
		var d: int = FACING.get(String(o.get("front", "S")).to_upper(), 0)
		var what := String(spec.get("what", ""))
		var container := String(spec.get("container", ""))
		var kind := String(spec.get("kind", "furniture"))
		var sz := Layout.size_of(what, container)
		var n := 1
		if spec.get("repeat", false):
			var fp: Array = o.get("world_footprint_x_d_m", [1.0, 1.0])
			var along := float(fp[0]) if d % 2 == 0 else float(fp[1])
			n = maxi(1, roundi(along / float(sz.x)))
		for k in range(n):
			var t := {"x": 0, "y": 0, "d": d, "w": sz.x, "h": sz.y}
			if container.is_empty():
				t["what"] = what
			else:
				t["container"] = container
			if kind != "furniture":
				t["kind"] = kind
			if spec.has("solid"):
				t["solid"] = spec.solid
			# The k-th copy of a run sits beside the first along its face.
			var side := Furnish.DIRS[(d + 1) % 4]
			var ccx := cx + side.x * (k - (n - 1) / 2.0) * sz.x
			var ccd := cd - side.y * (k - (n - 1) / 2.0) * sz.x
			var solid := bool(t.get("solid", kind != "wall"))
			var where := _fit(row, taken, t, gx.u(ccx), gd.u(ccd), rows, room, solid)
			if where.x < 0:
				report.append("%s: SKIPPED, nowhere to stand a %s %dx%d facing %d around %.1f,%.1f" % [tag, what if container.is_empty() else container, sz.x, sz.y, d, ccx, ccd])
				continue
			t.x = where.x
			t.y = where.y
			var f := Layout.footprint(t)
			for yy in range(f.position.y, f.end.y):
				for xx in range(f.position.x, f.end.x):
					taken[yy * 4096 + xx] = solid
			row.things.append(t)
			report.append("%s: %s%s at %d,%d facing %d" % [tag, what if container.is_empty() else container + " (container)", " on the wall" if kind == "wall" else "", t.x, t.y, d])
	return row


## One axis of the grid: the plan's wall lines in metres and the tile each
## stands in. Between two lines a room keeps its whole metres of floor.
class Grid:
	var lines: Array[float]
	var at: Array[int] = []
	var tiles := 0

	func _init(lines_: Array[float]) -> void:
		lines = lines_
		var col := 0
		for i in range(lines.size()):
			if i > 0:
				col += maxi(1, floori(lines[i] - lines[i - 1] + 0.01)) + 1
			at.append(col)
		tiles = col + 1

	## The tile of the wall line nearest a plan coordinate.
	func line(v: float) -> int:
		var best := 0
		for i in range(lines.size()):
			if absf(lines[i] - v) < absf(lines[best] - v):
				best = i
		return at[best]

	## A plan coordinate as a position along the tiles: between two lines
	## the room's metres stretch evenly over its floor tiles (the wall
	## tiles are not part of the room), so the middle of a room is the
	## middle of its floor and a thing against a wall is on the tile
	## beside it. On a line, the line's tile.
	func u(v: float) -> float:
		if v <= lines[0]:
			return at[0] + 0.5
		for i in range(1, lines.size()):
			if v < lines[i]:
				var f := (v - lines[i - 1]) / (lines[i] - lines[i - 1])
				return at[i - 1] + 1 + f * (at[i] - at[i - 1] - 1)
		return at[at.size() - 1] + 0.5


## Adds a wall line, once, to a sorted list (lines a centimetre apart are one).
static func _line(lines: Array[float], v: float) -> void:
	for l in lines:
		if absf(l - v) < 0.05:
			return
	lines.append(v)
	lines.sort()


## The mapping for a plan name: exact, else the first key the name contains.
static func _spec_for(name: String) -> Dictionary:
	if NAMES.has(name):
		return NAMES[name]
	for key: String in NAMES:
		if name.contains(key):
			return NAMES[key]
	return {}


## The first of `n` tiles centred at tile position `u`.
static func _lo(u: float, n: int) -> int:
	return roundi(u - n / 2.0)


## Cuts an opening of `ch` into the wall tile row or column `across`,
## centred on tile position `u` along it: `MIN_OPENING` wide where the
## wall has room within `reach` tiles of the centre, one wide where it has
## not, nowhere when no wall there joins two spaces. Returns the width cut.
static func _cut(grid: Array[PackedStringArray], ch: String, along_x: bool, across: int, u: float, reach: int, report: PackedStringArray, tag: String) -> int:
	var rows := grid.size()
	var offs: Array[int] = [0]
	for k in range(1, reach + 1):
		offs.append(-k)
		offs.append(k)
	for wt in range(MIN_OPENING, 0, -1):
		var lo := _lo(u, wt)
		for off in offs:
			var ok := true
			for k in range(wt):
				var x := lo + off + k if along_x else across
				var d := across if along_x else lo + off + k
				ok = ok and _joins(grid, x, rows - 1 - d, along_x)
			if not ok:
				continue
			for k in range(wt):
				var x := lo + off + k if along_x else across
				var d := across if along_x else lo + off + k
				grid[rows - 1 - d][x] = ch
			var at_x := lo + off if along_x else across
			var at_y := rows - 1 - (across if along_x else lo + off + wt - 1)
			report.append("%s: %s %d wide at %d,%d" % [tag, "doorway" if ch == Layout.DOOR else "opening", wt, at_x, at_y])
			return wt
	report.append("%s: SKIPPED, no wall between two spaces near there" % tag)
	return 0


## Whether a wall tile can be cut into an opening: it is a wall, and the
## two tiles either side of it across the wall are floor or the outdoors,
## so the opening joins two spaces rather than running into a corner.
static func _joins(grid: Array[PackedStringArray], x: int, y: int, along_x: bool) -> bool:
	if not _is(grid, x, y, Layout.WALL):
		return false
	var a := Vector2i(x, y - 1) if along_x else Vector2i(x - 1, y)
	var b := Vector2i(x, y + 1) if along_x else Vector2i(x + 1, y)
	return _open(grid, a) and _open(grid, b)


static func _is(grid: Array[PackedStringArray], x: int, y: int, ch: String) -> bool:
	if y < 0 or y >= grid.size() or x < 0 or x >= grid[y].size():
		return ch == Layout.OUT
	return grid[y][x] == ch


static func _open(grid: Array[PackedStringArray], t: Vector2i) -> bool:
	return _is(grid, t.x, t.y, Layout.FLOOR) or _is(grid, t.x, t.y, Layout.OUT)


## Where a thing centred at tile position (ux, ud) stands in the map: the
## tiles its footprint covers from there, or the nearest shift of one tile
## that puts it on free floor. (-1, -1) when none does. A hung piece wants
## the wall tile its back is to. `room` is the plan room's tiles, walls
## included. A solid piece is placed only where the room stays open
## (`_room_open`), the rule Furnish applies when it stands things itself.
static func _fit(row: Dictionary, taken: Dictionary, t: Dictionary, ux: float, ud: float, rows: int, room: Rect2i, solid: bool) -> Vector2i:
	var f := Layout.footprint(t)
	var d := int(t.d)
	var hung := String(t.get("kind", "")) == "wall"
	var x0 := _lo(ux, f.size.x)
	var d_lo := _lo(ud, f.size.y)
	var y0 := rows - 1 - (d_lo + f.size.y - 1)
	var tries: Array[Vector2i] = [Vector2i.ZERO]
	if hung:
		# Back onto the wall: step away from the way it faces first.
		tries.append(-Furnish.DIRS[d])
	tries.append_array([Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)])
	for off in tries:
		var at := Vector2i(x0, y0) + off
		var ok := true
		var inner := Rect2i(room.position + Vector2i.ONE, room.size - Vector2i(2, 2))
		# Hung on the room's own wall, or standing on its own floor: a shift
		# never carries a thing through a wall into the next room.
		if hung:
			ok = room.has_point(at) and not inner.has_point(at)
		else:
			ok = inner.encloses(Rect2i(at, f.size))
		for yy in range(at.y, at.y + f.size.y):
			for xx in range(at.x, at.x + f.size.x):
				var ch := Layout.at(row, xx, yy)
				if taken.has(yy * 4096 + xx):
					ok = false
				elif hung:
					ok = ok and ch == Layout.WALL and Layout.is_floor(Layout.at(row, xx + Furnish.DIRS[d].x, yy + Furnish.DIRS[d].y))
				else:
					ok = ok and ch == Layout.FLOOR
		if ok and solid and not hung and not _room_open(row, taken, Rect2i(at, f.size), room):
			ok = false
		if ok:
			return at
	return Vector2i(-1, -1)


## Whether a room stays playable with a solid piece on `placing`: every
## free floor tile of the room still reaches every other (through its
## openings too), and every solid tile can be reached from a free one
## beside it (`Furnish.still_open`, at import time).
static func _room_open(row: Dictionary, taken: Dictionary, placing: Rect2i, room: Rect2i) -> bool:
	var free := {}
	var solid := {}
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			if not Layout.is_floor(Layout.at(row, x, y)):
				continue
			var t := Vector2i(x, y)
			if placing.has_point(t) or taken.get(y * 4096 + x, false):
				solid[t] = true
			else:
				free[t] = true
	if free.is_empty():
		return false
	var seen := {}
	var stack: Array[Vector2i] = [free.keys()[0]]
	seen[stack[0]] = true
	while not stack.is_empty():
		var t: Vector2i = stack.pop_back()
		for off in Furnish.DIRS:
			var n: Vector2i = t + off
			if free.has(n) and not seen.has(n):
				seen[n] = true
				stack.append(n)
	if seen.size() < free.size():
		return false
	for t: Vector2i in solid:
		var beside := false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if free.has(t + Vector2i(dx, dy)):
					beside = true
		if not beside:
			return false
	return true


## The row into the table (`LayoutFile`, the one writer).
static func _write(row: Dictionary) -> void:
	LayoutFile.write(row)
