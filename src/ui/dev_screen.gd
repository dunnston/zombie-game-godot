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

## Sized for the 1920x1080 design resolution and coloured from `Ui`, so a
## developer tool still reads as part of the same game. It stays drawn by
## hand: it is a debug list, not a screen a player ever sees.
const ROW := 32.0
const PANEL_W := 860.0
const SHOWN := 18

const BG := Ui.PANEL
const EDGE := Ui.LINE
const TEXT := Ui.TEXT_BODY
const DIM := Ui.TEXT_DIM
const HOT := Ui.HOVER
const ACCENT := Ui.ACCENT_HI
const KIND_COLOR := {
	"give": Color("#9fd07a"), "enemy": Color("#e05a4a"),
	"goto": Color("#9fd0ff"), "verb": Color("#e0c24a"),
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
		# Seeing an interrupt land needs something mid-swing to interrupt,
		# which is a fight you have to arrange. This is that fight, on demand.
		["rock", "Stagger and open up everything near you", "world"],
		# A potato is nine minutes and corn is eighteen, which is right in
		# play and useless at a keyboard trying to see what a harvest feels
		# like — or whether a row of beds reads at a glance.
		["ripen", "Ripen and fill every raised bed", "world"],
		["day", "Set the clock to noon", "world"],
		["night", "Set the clock to midnight", "world"],
		["clear", "Kill every enemy loaded", "world"],
		["quiet", "Clear the threat meter", "world"],
		# The School is a walk from anywhere and a fight at the end, which is
		# right in play and useless at a keyboard checking the way out.
		["school", "Walk into Pine Hollow High", "world"],
		["boss", "Put down the School's boss", "world"],
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
			Stamina.refill(player)
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
				player.hotbar.set_wear_at(player.slot, 1)
				sim.notify("DEV  %s is down to its last use" % Config.WEAPONS[wid].name, "#d9c46a")
			else:
				sim.notify("DEV  that does not wear out", "#8a8f84")
		"school":
			if sim.instance != null:
				sim.notify("DEV  already inside", "#8a8f84")
				return
			var door := Instance.door_for(sim, "school")
			if door.is_empty():
				return
			player.driving_id = 0
			player.pos = door.stand
			player.prev_pos = door.stand
			# Through the real door, refusals and all: a dev key that walked
			# past the daily chain would test nothing about the chain.
			Instance.enter(sim, player, "school")
		"boss":
			if sim.instance == null or sim.instance.boss == null or sim.instance.boss.dead:
				sim.notify("DEV  no boss standing", "#8a8f84")
				return
			Damage.kill_enemy(sim, sim.instance.boss, player)
		"mend":
			for row in Wear.worn_carried(player):
				Wear.mend(Wear.container_for(player, String(row.c)), int(row.i))
			sim.notify("DEV  everything mended", "#b7e08a")
		"ripen":
			var beds := 0
			for s in sim.structs.list:
				if not Farming.is_bed(s):
					continue
				s.water = Config.FARM.water_max
				if Farming.planted(s):
					s.grow = Farming.grow_time(s)
				beds += 1
			sim.notify("DEV  %d bed%s watered and ripened" % [beds, "" if beds == 1 else "s"],
				"#b7e08a" if beds > 0 else "#8a8f84")
		"rock":
			# Through the same two writers the weapons use, resistance and
			# immunity included — so what this shows is the real mechanic and
			# not a second one that only the dev menu can reach. A Behemoth
			# standing here will refuse, which is the correct answer.
			var rocked := 0
			for e in sim.enemies.list:
				if e.dead or e.pos.distance_squared_to(player.pos) > 400.0 * 400.0:
					continue
				if Damage.stagger_enemy(sim, e, 1.2) > 0.0:
					rocked += 1
				Damage.bleed_enemy(e, 6.0, player)
			sim.notify("DEV  %d rocked and bleeding" % rocked, "#d9c46a")
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
	var body := Ui.font("ui", 500)
	var caps := Ui.font("ui", 600, 1)
	var mono := Ui.font("mono", 500)
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Ui.SCRIM)

	var p := _panel_rect()
	Ui.box(BG, EDGE, 1, 3).draw(get_canvas_item(), p)

	draw_string(Ui.font("display", 600, 1), p.position + Vector2(16, 26), "DEV MENU", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ACCENT)
	draw_string(mono, p.position + Vector2(PANEL_W - 16, 24), "%d of %d" % [_shown.size(), _all.size()],
		HORIZONTAL_ALIGNMENT_RIGHT, -1, 13, DIM)

	# The filter line, with a caret so an empty one still looks like a field.
	var fy := p.position.y + ROW * 1.6
	Ui.box(Ui.VOID, Ui.LINE, 1, 2).draw(get_canvas_item(), Rect2(p.position.x + 12, fy - 20, PANEL_W - 24, 30))
	var typed := filter if not filter.is_empty() else "type to filter"
	draw_string(body, Vector2(p.position.x + 24, fy), typed + ("_" if not filter.is_empty() else ""),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, TEXT if not filter.is_empty() else DIM)

	var list := _list_rect()
	for i in range(top, mini(top + SHOWN, _shown.size())):
		var row: Dictionary = _shown[i]
		var y := list.position.y + (i - top) * ROW
		var rect := Rect2(list.position.x, y, list.size.x, ROW)
		if i == sel or rect.has_point(mouse):
			Ui.box(HOT, Ui.ACCENT if i == sel else Ui.LINE, 1, 2).draw(get_canvas_item(), rect)
		var color: Color = KIND_COLOR.get(String(row.kind), TEXT)
		draw_rect(Rect2(rect.position.x + 4, y + 8, 4, ROW - 16), color)
		draw_string(body, Vector2(rect.position.x + 18, y + ROW - 10), String(row.label),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Ui.TEXT_HIGH if i == sel else TEXT)
		draw_string(mono, Vector2(rect.position.x + rect.size.x - 10, y + ROW - 10), String(row.note).to_upper(),
			HORIZONTAL_ALIGNMENT_RIGHT, -1, 12, DIM)

	if _shown.is_empty():
		draw_string(body, list.position + Vector2(18, 22), "Nothing matches", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, DIM)

	draw_string(caps, Vector2(p.position.x + 16, p.end.y - 14),
		"↑↓ CHOOSE   ENTER GIVE   SHIFT+ENTER TEN   ESC CLOSE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
