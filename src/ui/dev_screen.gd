class_name DevScreen
extends Control
## The dev menu, behind F1. One filterable list of everything the owner might
## want to make happen right now — every item in the game, every enemy, every
## district to stand in, and a short column of verbs.
##
## It is one list rather than a set of tabs on purpose. Tabs mean knowing which
## tab a thing lives on before you can look for it; typing three letters does
## not. `pipe` finds the pipe, `beh` finds the behemoth, `junk` finds the
## junkyard, and the row says which of those it is.
##
## Never reachable in a release build — `scenes/main.gd` only builds this when
## `OS.is_debug_build()` or `--dev` says so, so there is nothing to switch off
## before shipping.

const ROW := 22.0
const PANEL_W := 620.0
const SHOWN := 16

const BG := Color("#12140f")
const EDGE := Color("#3d4a33")
const TEXT := Color("#cfd6c4")
const DIM := Color("#7d8a72")
const HOT := Color("#1f2a18")
const ACCENT := Color("#b7e08a")
const KIND_COLOR := {
	"give": Color("#b7e08a"), "enemy": Color("#e05a4a"),
	"goto": Color("#7fb0d8"), "verb": Color("#d9c46a"),
}

var sim: GameSim
## Whose pack the items land in, and whose feet the world moves under.
var player: PlayerSim = null
var open := false

var filter := ""
var sel := 0
var top := 0
var mouse := Vector2.ZERO

## Every row the menu can do, built once. {kind, id, label, note}
var _all: Array[Dictionary] = []
var _shown: Array[Dictionary] = []


func _init(sim_: GameSim) -> void:
	sim = sim_
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build_catalogue()
	_refilter()


func toggle() -> void:
	open = not open
	visible = open
	# The list owns the mouse while it is up, and gives it straight back.
	mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if open:
		filter = ""
		sel = 0
		top = 0
		_refilter()
	queue_redraw()


# ------------------------------------------------------------- catalogue --

func _build_catalogue() -> void:
	_all.clear()
	# Everything carryable, straight off the registry so a new item in
	# config.gd is in the dev menu the moment it exists.
	for id in Items.registry():
		var it: Dictionary = Items.registry()[id]
		_all.append({"kind": "give", "id": id, "label": String(it.name), "note": String(it.kind)})
	for type in Config.ENEMIES:
		var e: Dictionary = Config.ENEMIES[type]
		_all.append({"kind": "enemy", "id": type,
			"label": "Spawn %s" % String(e.get("name", type)), "note": "enemy"})
	for l in sim.world.locations:
		_all.append({"kind": "goto", "id": String(l.id),
			"label": "Go to %s" % String(l.name), "note": "tier %d" % int(l.get("tier", 1))})
	for v in [
		["heal", "Heal to full", "you"],
		["stamina", "Refill stamina", "you"],
		["xp", "Grant 1000 XP", "you"],
		["res", "50 of every resource", "you"],
		# The meter takes twenty minutes to fill on its own, which is right in
		# play and useless at a keyboard trying to see what FERAL feels like.
		["mutate", "+20 Mutation", "you"],
		["human", "Clear the Mutation meter", "you"],
		# Wearing a weapon out honestly is several hundred swings, which is
		# right in play and useless at a keyboard trying to see what breaking
		# feels like — or whether the bench will mend it.
		["blunt", "Wear what you are holding to a sliver", "you"],
		["mend", "Mend everything you are carrying", "you"],
		["day", "Set the clock to noon", "world"],
		["night", "Set the clock to midnight", "world"],
		["clear", "Kill every enemy loaded", "world"],
		["quiet", "Clear the threat meter", "world"],
	]:
		_all.append({"kind": "verb", "id": v[0], "label": v[1], "note": v[2]})


func _refilter() -> void:
	_shown.clear()
	var f := filter.to_lower()
	for row in _all:
		if f.is_empty() or String(row.label).to_lower().contains(f) \
			or String(row.id).to_lower().contains(f):
			_shown.append(row)
	sel = clampi(sel, 0, maxi(0, _shown.size() - 1))
	_scroll_to_sel()


func _scroll_to_sel() -> void:
	top = clampi(top, maxi(0, sel - SHOWN + 1), sel)
	top = clampi(top, 0, maxi(0, _shown.size() - SHOWN))


# ----------------------------------------------------------------- doing --

## `n` is the quantity modifier: holding shift asks for ten of a thing, and
## ten of a thing that does not stack is ten separate grants.
func apply(row: Dictionary, n := 1) -> void:
	if player == null:
		return
	match String(row.kind):
		"give":
			var id := String(row.id)
			var entry := Loot.item_entry_id(id)
			var got := 0
			# Resources take a count; equipment is one object at a time.
			if Items.kind_of(id) == "res":
				Loot.give_entry(sim, player, {"id": entry, "n": n})
				got = n
			else:
				for i in range(n):
					if Loot.give_entry(sim, player, {"id": entry, "n": 1}).is_empty():
						break
					got += 1
			sim.notify("DEV  +%d %s" % [got, Items.name_of(id)], "#b7e08a")
		"enemy":
			# Far enough out to see it come, close enough to not have to walk.
			for i in range(n):
				var a := sim.rng.next() * TAU
				var at := player.pos + Vector2.from_angle(a) * 220.0
				var spot := sim.world.find_open_spot(sim.rng, at, 0.0, 90.0)
				sim.enemies.spawn(String(row.id), player.pos if spot == Vector2.INF else spot, true)
			sim.notify("DEV  spawned %d %s" % [n, String(row.id)], "#e05a4a")
		"goto":
			for l in sim.world.locations:
				if String(l.id) != String(row.id):
					continue
				var r: Rect2i = l.rect
				var mid := Vector2(r.position.x + r.size.x / 2.0, r.position.y + r.size.y / 2.0) * Config.TILE
				var spot := sim.world.find_open_spot(sim.rng, mid, 0.0, 120.0, 40, player.r)
				player.pos = mid if spot == Vector2.INF else spot
				player.driving_id = 0
				sim.notify("DEV  %s" % String(l.name), "#7fb0d8")
				break
		"verb":
			_verb(String(row.id))


func _verb(id: String) -> void:
	match id:
		"heal":
			player.hp = player.max_hp
			player.downed = false
			sim.notify("DEV  healed", "#b7e08a")
		"stamina":
			player.stam = player.max_stam
			player.stam_lock = 0.0
			player.winded = false
			sim.notify("DEV  stamina", "#b7e08a")
		"xp":
			Progression.add_xp(sim, player, 1000, "DEV")
		"mutate":
			Mutation.add(sim, player, 20.0, "dev")
		"blunt":
			var wid := player.held_id()
			if Wear.wears(wid):
				# Down to one use, not to zero: the next swing is what breaks
				# it, so the break itself can be watched rather than arrived at.
				player.wear[wid] = 1
				sim.notify("DEV  %s is down to its last use" % Config.WEAPONS[wid].name, "#d9c46a")
			else:
				sim.notify("DEV  that does not wear out", "#8a8f84")
		"mend":
			for wid2 in Wear.worn_carried(player):
				Wear.mend(player, wid2)
			sim.notify("DEV  everything mended", "#b7e08a")
		"human":
			Mutation.suppress(sim, player, Config.MUTATION.max)
		"res":
			# Fifty of everything is more than a pack holds. Overflow lands at
			# the player's feet rather than vanishing, which is the same rule
			# the rest of the game uses and keeps the menu honest about what
			# it actually gave you.
			for rid in Config.RES:
				Loot.give_res_or_drop(sim, player, rid, 50, player.pos)
			sim.notify("DEV  resources — check your feet for the overflow", "#b7e08a")
		"day":
			sim.clock.t = 0.5
			sim.notify("DEV  noon", "#d9c46a")
		"night":
			sim.clock.t = 0.0
			sim.notify("DEV  midnight", "#d9c46a")
		"clear":
			var n := 0
			for e in sim.enemies.list:
				if not e.dead:
					e.dead = true
					n += 1
			sim.enemies.rebuild_spatial()
			sim.notify("DEV  cleared %d" % n, "#d9c46a")
		"quiet":
			sim.threat.value = 0.0
			sim.threat.tier = 0
			sim.notify("DEV  threat cleared", "#d9c46a")


# ----------------------------------------------------------------- input --

func _gui_input(event: InputEvent) -> void:
	if not open:
		return
	if event is InputEventMouseMotion:
		mouse = (event as InputEventMouseMotion).position
		queue_redraw()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		mouse = mb.position
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			top = clampi(top + 2, 0, maxi(0, _shown.size() - SHOWN))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			top = maxi(0, top - 2)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			var hit := _row_at(mouse)
			if hit >= 0:
				sel = hit
				apply(_shown[hit], 10 if Input.is_key_pressed(KEY_SHIFT) else 1)
		accept_event()
		queue_redraw()


## Keys come through `_input` rather than `_gui_input` because a Control only
## sees the keyboard while it holds focus, and this panel must not steal focus
## from anything. Everything it uses is marked handled, so F1 and Escape are
## the only keys that leave the menu.
func _input(event: InputEvent) -> void:
	if not open or not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_ESCAPE:
			toggle()
		KEY_DOWN:
			sel = mini(sel + 1, maxi(0, _shown.size() - 1))
			_scroll_to_sel()
		KEY_UP:
			sel = maxi(sel - 1, 0)
			_scroll_to_sel()
		KEY_ENTER, KEY_KP_ENTER:
			if sel < _shown.size():
				apply(_shown[sel], 10 if k.shift_pressed else 1)
		KEY_BACKSPACE:
			filter = filter.substr(0, maxi(0, filter.length() - 1))
			_refilter()
		_:
			# Typing filters. Anything that is not a printable character —
			# F1 included, so the key that opened this closes it — is left
			# for whoever else wants it.
			var ch := char(k.unicode)
			if k.unicode >= 32 and not ch.is_empty():
				filter += ch
				sel = 0
				_refilter()
			else:
				return
	accept_event()
	queue_redraw()


func _row_at(at: Vector2) -> int:
	var r := _list_rect()
	if not r.has_point(at):
		return -1
	var i := top + int((at.y - r.position.y) / ROW)
	return i if i >= 0 and i < _shown.size() else -1


# ------------------------------------------------------------------ draw --

func _panel_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var h := ROW * (SHOWN + 3) + 24.0
	return Rect2(roundf((vp.x - PANEL_W) / 2.0), roundf((vp.y - h) / 2.0), PANEL_W, h)


func _list_rect() -> Rect2:
	var p := _panel_rect()
	return Rect2(p.position.x + 12.0, p.position.y + ROW * 2.0 + 8.0, PANEL_W - 24.0, ROW * SHOWN)


func _draw() -> void:
	if not open:
		return
	var font := ThemeDB.fallback_font
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.55))

	var p := _panel_rect()
	draw_rect(p, BG)
	draw_rect(p, EDGE, false, 2.0)

	draw_string(font, p.position + Vector2(14, 18), "DEV MENU", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ACCENT)
	draw_string(font, p.position + Vector2(PANEL_W - 14, 18), "%d of %d" % [_shown.size(), _all.size()],
		HORIZONTAL_ALIGNMENT_RIGHT, -1, 11, DIM)

	# The filter line, with a caret so an empty one still looks like a field.
	var fy := p.position.y + ROW * 1.6
	draw_line(Vector2(p.position.x + 12, fy + 4), Vector2(p.position.x + PANEL_W - 12, fy + 4), EDGE, 1.0)
	var typed := filter if not filter.is_empty() else "type to filter"
	draw_string(font, Vector2(p.position.x + 14, fy), typed + ("_" if not filter.is_empty() else ""),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT if not filter.is_empty() else DIM)

	var list := _list_rect()
	for i in range(top, mini(top + SHOWN, _shown.size())):
		var row: Dictionary = _shown[i]
		var y := list.position.y + (i - top) * ROW
		var rect := Rect2(list.position.x, y, list.size.x, ROW)
		if i == sel or rect.has_point(mouse):
			draw_rect(rect, HOT)
		var color: Color = KIND_COLOR.get(String(row.kind), TEXT)
		draw_rect(Rect2(rect.position.x + 2, y + 6, 4, ROW - 12), color)
		draw_string(font, Vector2(rect.position.x + 14, y + ROW - 7), String(row.label),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT)
		draw_string(font, Vector2(rect.position.x + rect.size.x - 8, y + ROW - 7), String(row.note),
			HORIZONTAL_ALIGNMENT_RIGHT, -1, 10, DIM)

	if _shown.is_empty():
		draw_string(font, list.position + Vector2(14, 18), "nothing matches", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)

	draw_string(font, Vector2(p.position.x + 14, p.end.y - 10),
		"↑↓ choose   ENTER give   SHIFT+ENTER ten   ESC close",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM)
