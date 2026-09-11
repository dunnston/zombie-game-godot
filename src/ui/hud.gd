class_name Hud
extends Control
## The in-game overlay: where you are and how dangerous it is, health and
## stamina, what you are holding and how much is left, the Threat meter, the
## raid banner and the notices. Reads the sim; changes nothing.
##
## Control nodes anchored to the window's edges, so it stays in its corners at
## any size: location and raid top-centre, Threat and the clock top-right,
## notices mid-left, the bars bottom-left, the hotbar bottom-centre and the
## minimap bottom-right (drawn by `MapScreen`, which this leaves room for).
## `refresh()` is called once a frame by the scene and only sets what changed.

var sim: GameSim
## Whose bars these are: the local player, whatever seat they hold.
var player: PlayerSim = null
## What the scene knows about the connection, for the corner line.
var net_line := ""
var notices: Array[Dictionary] = []
var hurt := 0.0
## What the death screen calls it. Turning is a death with its own word.
var death_cause := "died"
## Set by the scene while build placement owns the bottom of the screen: the
## slim bar sits where the interact prompt does.
var placing := false

var _hurt: ColorRect
var _tint: ColorRect
var _down_tint: ColorRect
var _lurch: Label
var _loc: Label
var _danger: UiPips
var _inst: Label
var _boss_box: VBoxContainer
var _boss_name: Label
var _boss_bar: UiMeter
var _raid_box: VBoxContainer
var _raid_title: Label
var _raid_wave: Label
var _raid_left: Label
var _raid_bar: UiMeter
var _raid_panel: PanelContainer
var _threat_label: Label
var _threat: UiMeter
var _day: Label
var _clock: Label
var _daybar: UiMeter
var _light_card: PanelContainer
var _light_name: Label
var _light_left: Label
var _light_bar: UiMeter
var _dark_hint: Label
var _notice_box: VBoxContainer
var _notice_sig := ""
var _mates: VBoxContainer
var _mates_sig := ""
var _effects: Label
var _hp: UiMeter
var _stam: UiMeter
var _mut: UiMeter
var _xp: UiMeter
var _prompt: PanelContainer
var _prompt_key: Label
var _prompt_text: Label
var _progress: UiMeter
var _reloading: Label
var _carry: Label
var _carry_bar: UiMeter
var _slots: Array[HotSlot] = []
var _heal: Label
var _heal_key: Label
var _dose: Label
var _dose_key: Label
var _debug: Label
var _net: Label
var _dead_box: VBoxContainer
var _dead_title: Label
var _dead_line: Label


func _init(sim_: GameSim) -> void:
	sim = sim_
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Ui.theme()
	_build()


func on_event(ev: Dictionary) -> void:
	match ev.t:
		"notify":
			notices.append({"text": ev.text, "color": Color(ev.color), "life": 5.5 if ev.important else 3.5, "max": 5.5 if ev.important else 3.5, "big": ev.important})
			if notices.size() > 6:
				notices.pop_front()
		"player_hit":
			hurt = clampf(ev.dmg / 45.0, 0.18, 0.7)
		"player_died":
			hurt = 0.9
			death_cause = String(ev.get("cause", "died"))


func tick(dt: float) -> void:
	hurt = maxf(0.0, hurt - dt * 1.6)
	for i in range(notices.size() - 1, -1, -1):
		notices[i].life -= dt
		if notices[i].life <= 0.0:
			notices.remove_at(i)


## The boss worth a bar: awake — hunting, or hurt — and close enough to be the
## fight you are in. On a guest it is whatever the snapshot says it is.
func _boss_near(p: PlayerSim) -> EnemySim:
	for e in sim.enemies.list:
		if e.dead or not e.def.get("boss", false):
			continue
		if (e.aggro or e.hp < e.max_hp) and e.pos.distance_to(p.pos) < 1100.0:
			return e
	return null


# ------------------------------------------------------------------ build --

## Anchors a box to a corner of the window at a margin, growing away from it.
func _corner(c: Control, preset: int, margin := Vector2(24, 24)) -> Control:
	add_child(c)
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	var right := preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT]
	var bottom := preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM]
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
	if preset in [Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM]:
		c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var dx := -margin.x if right else margin.x
	var dy := -margin.y if bottom else margin.y
	if preset in [Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM]:
		dx = 0.0
	c.offset_left += dx
	c.offset_right += dx
	c.offset_top += dy
	c.offset_bottom += dy
	return c


func _full(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.visible = false
	add_child(r)
	return r


func _shadowed(l: Label) -> Label:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _build() -> void:
	_hurt = _full(Color("#8c1a1a", 0.0))
	_tint = _full(Color("#b07ad0", 0.0))
	_down_tint = _full(Color("#3a0a0a", 0.35))

	# Top centre: where you are, how bad it is, and what is coming.
	_loc = _shadowed(Ui.label("", "Location"))
	_loc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_danger = UiPips.new(4, Vector2(9, 9), Ui.ACCENT_HI, Color(1, 1, 1, 0.2), 5)
	_danger.diamond = true
	_danger._resize()
	var drow := Ui.hbox(8, [Ui.label("Danger", "Caps"), _danger])
	drow.alignment = BoxContainer.ALIGNMENT_CENTER
	_danger.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_inst = _shadowed(Ui.label("", "Mono14", Color("#d8c98a")))
	_inst.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name = _shadowed(Ui.label("", "Caps14", Color("#e8c0b0")))
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_bar = UiMeter.new(10, Ui.DANGER)
	_boss_bar.custom_minimum_size.x = 420
	_boss_bar.tick_color = Ui.TEXT_HIGH
	_boss_box = Ui.vbox(5, [_boss_name, _boss_bar])
	_raid_title = Ui.label("", "Name18")
	_raid_wave = Ui.label("", "Caps14")
	_raid_left = Ui.label("", "Mono14", Ui.TEXT_HIGH)
	_raid_panel = Ui.panel("HudLine", Ui.hbox(12, [_raid_title, Ui.rule(true, 18.0, Ui.LINE), _raid_wave, _raid_left]))
	for c in _raid_panel.get_child(0).get_children():
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_raid_bar = UiMeter.new(6, Ui.DANGER)
	_raid_bar.custom_minimum_size.x = 520
	_raid_box = Ui.vbox(8, [_raid_panel, _raid_bar])
	_raid_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_raid_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_raid_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_boss_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var top := Ui.vbox(4, [_loc, drow, _inst, Ui.fixed(0, 12), _boss_box, _raid_box])
	top.custom_minimum_size.x = 640
	_corner(top, Control.PRESET_CENTER_TOP, Vector2(0, 26))

	# Top right: Threat and the clock, then the light you are carrying.
	_threat_label = Ui.label("", "Caps")
	_threat = UiMeter.new(12, Ui.LIGHT)
	for w: float in Config.THREAT.warn_at:
		_threat.ticks.append(w / float(Config.THREAT.max))
	_threat.tick_color = Color(1, 1, 1, 0.4)
	_day = Ui.label("", "Caps")
	_clock = Ui.label("", "Mono")
	_daybar = UiMeter.new(4, Ui.NIGHT)
	var threat_card := Ui.panel("HudCard", Ui.vbox(6, [
		Ui.hbox(8, [Ui.expand(Ui.label("Threat", "Caps")), _threat_label]), _threat,
		Ui.fixed(0, 4), Ui.hbox(8, [Ui.expand(_day), _clock]), _daybar]))
	_light_name = Ui.label("", "Row14", Ui.LIGHT)
	_light_left = Ui.label("", "Mono", Ui.LIGHT)
	_light_bar = UiMeter.new(4, Ui.LIGHT)
	_light_card = Ui.panel("HudCard", Ui.vbox(6, [Ui.hbox(8, [Ui.expand(_light_name), _light_left]), _light_bar]))
	_light_card.add_theme_stylebox_override("panel", Ui.box(Ui.HUD_FILL, Ui.LINE, 1, 3, 14, 10))
	_dark_hint = _shadowed(Ui.para("", "Row14", Color(0.95, 0.75, 0.4)))
	var right := Ui.vbox(12, [threat_card, _light_card, _dark_hint])
	right.custom_minimum_size.x = 300
	_corner(right, Control.PRESET_TOP_RIGHT)

	# Notices, left of centre, newest at the bottom.
	_notice_box = Ui.vbox(8)
	_notice_box.custom_minimum_size.x = 420
	add_child(_notice_box)
	_notice_box.anchor_top = 0.4
	_notice_box.anchor_bottom = 0.4
	_notice_box.offset_left = 24
	_notice_box.offset_right = 444

	# Bottom left: the others at the table, what is working through you, and
	# the four bars.
	_mates = Ui.vbox(4)
	_effects = Ui.label("", "Mono12", Ui.TEXT_BODY)
	_hp = UiMeter.new(20, Ui.DANGER)
	_stam = UiMeter.new(20, Ui.ACCENT_HI)
	_mut = UiMeter.new(20, Ui.MUTATION)
	for b in Config.MUTATION.bands:
		var f := float(b.at) / float(Config.MUTATION.max)
		if f > 0.0:
			_mut.ticks.append(f)
	_xp = UiMeter.new(12, Ui.XP)
	_xp.right_color = Ui.WAIT
	var bars := Ui.vbox(8, [_mates, _effects, _hp, _stam, _mut, _xp])
	bars.custom_minimum_size.x = 300
	_corner(bars, Control.PRESET_BOTTOM_LEFT)

	# Bottom centre: the prompt above, the hotbar with carry weight on its left
	# and the healing and dose keys on its right.
	_prompt_key = Ui.label("", "Mono12", Ui.ACCENT)
	_prompt_text = Ui.label("", "Row", Color("#d8e8c0"))
	_progress = UiMeter.new(6, Ui.ACCENT)
	_progress.custom_minimum_size.x = 120
	_prompt = Ui.panel("HudLine", Ui.vbox(6, [Ui.hbox(10, [_prompt_key, _prompt_text]), _progress]))
	_progress.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_reloading = _shadowed(Ui.label("Reloading", "Caps14", Color("#ffe6a8")))
	_reloading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var prompt_col := Ui.vbox(8, [_prompt, _reloading])
	prompt_col.alignment = BoxContainer.ALIGNMENT_END
	_prompt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_corner(prompt_col, Control.PRESET_CENTER_BOTTOM, Vector2(0, 112))

	_carry = Ui.label("", "Mono12")
	_carry_bar = UiMeter.new(10)
	var carry := Ui.vbox(5, [Ui.hbox(8, [Ui.expand(Ui.label("Carry", "Caps")), _carry]), _carry_bar])
	carry.custom_minimum_size.x = 150
	var slots := Ui.hbox(4)
	for i in range(sim.players[0].hotbar.size()):
		var s := HotSlot.new(i)
		_slots.append(s)
		slots.add_child(s)
	_heal_key = Ui.label("", "Mono12", Ui.TEXT_OFF)
	_heal = Ui.label("", "Small", Color(1, 1, 1, 0.7))
	_dose_key = Ui.label("", "Mono12", Ui.TEXT_OFF)
	_dose = Ui.label("", "Small", Color("#c07f9a"))
	var meds := Ui.vbox(5, [Ui.hbox(8, [_heal_key, _heal]), Ui.hbox(8, [_dose_key, _dose])])
	meds.custom_minimum_size.x = 180
	var shelf := Ui.hbox(16, [Ui.pad(carry, 0, 0, 0, 6), slots, Ui.pad(meds, 0, 0, 0, 6)])
	for c in shelf.get_children():
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_END
	_corner(shelf, Control.PRESET_CENTER_BOTTOM)

	# Bottom right: the debug line and the connection above the minimap.
	_debug = Ui.label("", "Mono12", Color(1, 1, 1, 0.5))
	_net = Ui.label("", "Mono12", Color(Ui.XP, 0.7))
	var lines := Ui.vbox(6, [_debug, _net])
	for l in [_debug, _net]:
		(l as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lines.custom_minimum_size.x = 520
	_corner(lines, Control.PRESET_BOTTOM_RIGHT, Vector2(24, 24 + float(Config.MAP.corner) + 8))

	_lurch = _shadowed(Ui.label("Something else is driving", "PanelTitle", Color("#e0c0ff")))
	_lurch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lurch.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_lurch.anchor_top = 0.3
	_lurch.anchor_bottom = 0.3
	add_child(_lurch)

	_dead_title = _shadowed(Ui.label("", "ScreenTitle"))
	_dead_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dead_line = _shadowed(Ui.label("", "Body", Ui.TEXT_HIGH))
	_dead_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dead_box = Ui.vbox(8, [_dead_title, _dead_line])
	add_child(_dead_box)
	_dead_box.set_anchors_preset(Control.PRESET_CENTER)
	_dead_box.custom_minimum_size.x = 900
	_dead_box.offset_left = -450
	_dead_box.offset_right = 450
	_dead_box.offset_top = -40


# ---------------------------------------------------------------- refresh --

func refresh() -> void:
	var p: PlayerSim = player if player != null else sim.players[0]
	var alive := not p.dead

	_hurt.visible = hurt > 0.0
	_hurt.color.a = hurt * 0.45
	# The change, on the screen itself. It starts at the top band and grows
	# with how far into it you are, and it breathes — a still tint reads as a
	# bug, a slow pulse reads as something inside you.
	var feral_at := float(Config.MUTATION.bands[Config.MUTATION.bands.size() - 1].at)
	var over := clampf((p.mutation - feral_at) / maxf(1.0, float(Config.MUTATION.max) - feral_at), 0.0, 1.0)
	_tint.visible = over > 0.0 or p.lurch_t > 0.0
	if _tint.visible:
		var pulse := 0.62 + 0.38 * sin(sim.time * 2.4)
		_tint.color.a = 0.34 if p.lurch_t > 0.0 else 0.06 + 0.14 * over * pulse
	_lurch.visible = p.lurch_t > 0.0

	var loc := sim.world.location_at_px(p.pos.x, p.pos.y)
	Ui.set_text(_loc, String(loc.name) if not loc.is_empty() else "The Outskirts")
	var tier := sim.world.danger_at_px(p.pos.x, p.pos.y)
	_danger.set_filled(tier, Ui.TIER_COLORS[clampi(tier, 0, 4)] if tier > 1 else Ui.TIER_COLORS[1])

	# A run: what you are carrying out, how long it has taken, and what is open.
	var inst := sim.instance
	_inst.visible = inst != null
	if inst != null:
		var line := "HAUL %d / %d  ·  %d:%02d" % [roundi(Instance.haul_load(sim, p)), roundi(float(Config.INSTANCE.haul_cap)),
			int(inst.t) / 60, int(inst.t) % 60]
		var icol := Color("#d8c98a")
		if inst.state == "cleared":
			line += "  ·  THE WAY OUT IS OPEN"
			icol = Ui.WAIT
		elif not inst.keys.is_empty():
			line += "  ·  YOU HAVE THE %s KEY" % String(inst.keys.keys()[0]).to_upper()
		Ui.set_text(_inst, line)
		Ui.set_color(_inst, icol)

	# The boss: its name, what is left of it, and where the fight changes.
	var boss := _boss_near(p)
	_boss_box.visible = boss != null
	if boss != null:
		Ui.set_text(_boss_name, String(boss.def.name))
		_boss_bar.ticks.clear()
		for ph in Config.BOSSES.get(boss.type, {}).get("phases", []).slice(1):
			_boss_bar.ticks.append(float(ph.at))
		_boss_bar.set_value(boss.hp / boss.max_hp)

	# The raid banner. The living get their own colour: a horde and a raiding
	# party want completely different answers.
	var raid := sim.raid
	_raid_box.visible = raid != null
	if raid != null:
		var rcol := Color("#d0a06a") if raid.human else Ui.DOWN
		Ui.set_color(_raid_title, rcol)
		_raid_panel.add_theme_stylebox_override("panel", Ui.box(Ui.HUD_FILL, Color(rcol, 0.55), 1, 0, 18, 8))
		if raid.phase == "warning":
			Ui.set_text(_raid_title, "%s incoming" % raid.spec.name)
			Ui.set_text(_raid_wave, "Arrives in")
			Ui.set_text(_raid_left, "%dS" % ceili(raid.timer))
			_raid_bar.set_value(0.0, rcol)
		else:
			Ui.set_text(_raid_title, String(raid.spec.name))
			Ui.set_text(_raid_wave, "Wave %d / %d" % [raid.wave, raid.spec.waves])
			Ui.set_text(_raid_left, "%d LEFT" % (raid.total - raid.killed))
			_raid_bar.set_value(float(raid.killed) / maxf(1.0, float(raid.total)), rcol)

	# Threat and the clock.
	var tcol := Color(sim.threat.color())
	Ui.set_text(_threat_label, sim.threat.label())
	Ui.set_color(_threat_label, tcol)
	_threat.set_value(sim.threat.value / Config.THREAT.max, tcol)
	var pcol := Color("#d0c46a")
	if sim.clock.phase == "dusk":
		pcol = Color("#d98a4a")
	elif sim.clock.phase == "night":
		pcol = Ui.NIGHT
	Ui.set_text(_day, "Day %d" % sim.clock.day)
	Ui.set_text(_clock, "%s %s" % [sim.clock.clock_string(), sim.clock.phase_name().to_upper()])
	Ui.set_color(_clock, pcol)
	_daybar.set_value(sim.clock.t, pcol)

	# The light: what is left of it, or — in the dark with nothing lit — which
	# of the three ways to be unlit this is, and the key that fixes it.
	var lamp: Dictionary = Equipment.equipped_light(p)
	var dark: float = float(sim.clock.darkness().alpha)
	_light_card.visible = p.lit and not lamp.is_empty()
	_dark_hint.visible = sim.clock.is_dark() and not p.lit
	if _light_card.visible:
		var burn: float = maxf(1.0, float(lamp.get("burn", 1.0)))
		var left: float = clampf(p.light_fuel / burn, 0.0, 1.0)
		Ui.set_text(_light_name, String(lamp.name))
		Ui.set_text(_light_left, "%ds" % roundi(p.light_fuel))
		_light_bar.set_value(left, Ui.LIGHT if left > 0.25 else Ui.SHORT)
	if _dark_hint.visible:
		var key := KeyBinds.primary_label("light")
		var hint := "Dark — wear a Torch in your off-hand"
		if not lamp.is_empty():
			hint = "Dark — %s to light it again" % key if p.light_fuel > 0.0 \
				else "%s is flat — %s loads a battery" % [String(lamp.name), key]
		Ui.set_text(_dark_hint, hint)
		_dark_hint.modulate.a = 0.6 + 0.4 * dark

	_refresh_notices()
	_refresh_mates(p)

	# What is working through you: a meal, a Surge, or a raw brain.
	var chips := PackedStringArray()
	for id in p.effects:
		chips.append("%s %ds" % [String(Config.EFFECTS[id].name).to_upper(), ceili(float(p.effects[id]))])
	Ui.set_text(_effects, "  ·  ".join(chips))
	_effects.visible = not chips.is_empty()

	_hp.set_value(p.hp / maxf(1.0, p.max_hp), null, "HP %d" % roundi(p.hp))
	_stam.set_value(p.stam / maxf(1.0, p.max_stam), Color("#8a8a7a") if p.winded else Ui.ACCENT_HI,
		"Stamina" + ("  —  winded" if p.winded else ""))
	var band := Mutation.band_of(p)
	_mut.set_value(Mutation.fraction(p), Color(String(band.color)), "Mutation  ·  %s" % String(band.name),
		"%d%%" % roundi(p.mutation))
	var pts := ""
	if p.skill_points > 0:
		pts = "%d POINT%s  ·  %s" % [p.skill_points, "" if p.skill_points == 1 else "S", KeyBinds.primary_label("character")]
	_xp.set_value(p.xp / maxf(1.0, float(p.xp_next)), null, "LV %d" % p.level, pts)

	_refresh_prompt(p)
	_reloading.visible = not p.reloading.is_empty() and alive

	for i in range(_slots.size()):
		_slots[i].show_slot(p, i)
	var carried := p.carried_weight()
	var frac := clampf(carried / maxf(1.0, p.carry_cap), 0.0, 1.0)
	var wcol := Ui.TEXT_DIM
	if p.overloaded():
		wcol = Ui.SHORT
	elif frac > 0.85:
		wcol = Ui.ACCENT_HI
	_carry_bar.set_value(frac, wcol)
	Ui.set_text(_carry, "%d / %d" % [roundi(carried), roundi(p.carry_cap)])
	Ui.set_color(_carry, wcol if wcol != Ui.TEXT_DIM else Ui.TEXT_BODY)

	# The healing and the dose, named by their keys so rebinding changes what
	# the screen tells you to press.
	Ui.set_text(_heal_key, KeyBinds.primary_label("use_heal"))
	Ui.set_text(_heal, "bandage x%d  ·  medkit x%d" % [p.count_carried("bandage"), p.count_carried("medkit")])
	var doses := 0
	for id in Config.CONSUMABLES:
		if Mutation.is_suppressant(id):
			doses += p.count_carried(id)
	Ui.set_text(_dose_key, KeyBinds.primary_label("use_suppress"))
	Ui.set_text(_dose, "brain matter x%d" % doses)

	Ui.set_text(_net, net_line.to_upper())
	_net.visible = not net_line.is_empty()
	Ui.set_text(_debug, "%d fps  ·  tile %d,%d  ·  enemies %d  ·  kills %d" % [Engine.get_frames_per_second(),
		int(p.pos.x / 32), int(p.pos.y / 32), sim.enemies.alive_count(), sim.stats.kills])

	_dead_box.visible = p.dead or p.downed
	_down_tint.visible = p.downed and not p.dead
	if p.dead:
		var turned := death_cause == "turned"
		Ui.set_text(_dead_title, "You turned" if turned else "You died")
		Ui.set_color(_dead_title, Ui.MUTATION if turned else Ui.DOWN)
		Ui.set_text(_dead_line, "Respawning in %.1f" % maxf(0.0, p.respawn_t))
	elif p.downed:
		Ui.set_text(_dead_title, "You are down")
		Ui.set_color(_dead_title, Ui.DOWN)
		Ui.set_text(_dead_line, "A teammate can get you up  ·  %.0fs" % maxf(0.0, p.down_t))


## What the interact key is offering, or the channel in progress.
func _refresh_prompt(p: PlayerSim) -> void:
	var key := ""
	var text := ""
	var k := -1.0
	var kc := Ui.ACCENT
	if p.driving_id > 0:
		# At the wheel, driving is all there is — so the prompt is the controls.
		key = "%s %s %s %s" % [KeyBinds.primary_label("move_up"), KeyBinds.primary_label("move_left"),
			KeyBinds.primary_label("move_down"), KeyBinds.primary_label("move_right")]
		text = "Drive  ·  %s get out" % KeyBinds.primary_label("interact")
	elif not p.searching.is_empty():
		var c: Dictionary = p.searching.container
		text = "Searching %s" % c.label
		k = clampf(p.searching.t / p.searching.dur, 0.0, 1.0)
	elif not p.reviving.is_empty():
		var who := sim.player_by_seat(int(p.reviving.seat))
		text = "Getting %s up" % (who.display_name if who != null else "them")
		k = clampf(p.reviving.t / p.reviving.dur, 0.0, 1.0)
		kc = Ui.XP
	else:
		var target := Interact.best_target(sim, p)
		if not target.is_empty():
			key = KeyBinds.primary_label("interact")
			text = String(target.label)
	_prompt.visible = not text.is_empty() and not placing and not p.dead
	Ui.set_text(_prompt_key, key)
	_prompt_key.visible = not key.is_empty()
	Ui.set_text(_prompt_text, text)
	_progress.visible = k >= 0.0
	if k >= 0.0:
		_progress.set_value(k, kc)


func _refresh_notices() -> void:
	var sig := ""
	for n in notices:
		sig += String(n.text) + "\n"
	if sig != _notice_sig:
		_notice_sig = sig
		Ui.clear(_notice_box)
		for n in notices:
			var bar := Ui.rect(n.color, 4, 16)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			# Wrapped, not trimmed: a notice cut off at its first clause has
			# not been delivered.
			var l := _shadowed(Ui.para(String(n.text), "Row", Ui.TEXT_HIGH))
			_notice_box.add_child(Ui.hbox(10, [bar, Ui.expand(l)]))
	for i in range(mini(notices.size(), _notice_box.get_child_count())):
		var n: Dictionary = notices[i]
		(_notice_box.get_child(i) as Control).modulate.a = clampf(n.life / minf(1.0, n.max), 0.0, 1.0)


## The others at the table: a sliver of health each and their name, so you
## know who needs you before they say so.
func _refresh_mates(p: PlayerSim) -> void:
	var others: Array = []
	for q in sim.players:
		if q != p and not q.away:
			others.append(q)
	var sig := ""
	for q in others:
		sig += "%d," % q.seat
	if sig != _mates_sig:
		_mates_sig = sig
		Ui.clear(_mates)
		for q in others:
			var m := UiMeter.new(4, Ui.DANGER)
			var name_l := Ui.label("", "Mono12")
			_mates.add_child(Ui.hbox(10, [Ui.expand(m), name_l]))
			m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in range(mini(others.size(), _mates.get_child_count())):
		var q: PlayerSim = others[i]
		var row := _mates.get_child(i)
		var col := Color(Config.PLAYER.colors[q.seat % Config.PLAYER.colors.size()])
		var state := "  ·  DOWN" if q.downed else ("  ·  DEAD" if q.dead else "")
		(row.get_child(0) as UiMeter).set_value(q.hp / maxf(1.0, q.max_hp), Ui.DOWN if q.downed else Ui.DANGER)
		var l := row.get_child(1) as Label
		Ui.set_text(l, (q.display_name + state).to_upper())
		Ui.set_color(l, Ui.DOWN if q.downed else col)


## One hotbar slot on the HUD: 74x66, the number, the item, and the one line
## under it that matters for that kind of thing — rounds for a gun, uses for
## a tool, BROKEN when it is, how many for a stack.
class HotSlot extends Control:
	var index := 0
	var _key := ""
	var _p: PlayerSim = null

	func _init(i: int) -> void:
		index = i
		custom_minimum_size = Vector2(74, 66)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_slot(p: PlayerSim, i: int) -> void:
		var stack := p.hotbar.at(i)
		var id := String(stack.get("id", ""))
		var worn := Wear.is_worn(p.hotbar, i) if not id.is_empty() else false
		var key := "%s|%d|%s|%s|%s|%d|%.2f" % [id, int(stack.get("n", 0)), str(i == p.slot), str(Wear.is_broken(p.hotbar, i) if not id.is_empty() else false),
			str(p.mag.get(id, 0)), p.count_res(String(Config.WEAPONS.get(id, {}).get("ammo", ""))) if not id.is_empty() else 0,
			Wear.frac(p.hotbar, i) if worn else -1.0]
		key += "|%d" % Upgrade.level_in(stack)
		if key == _key:
			return
		_key = key
		_p = p
		queue_redraw()

	func _draw() -> void:
		var p := _p
		if p == null:
			return
		var i := index
		var stack := p.hotbar.at(i)
		var id := String(stack.get("id", ""))
		var held := i == p.slot
		var r := Rect2(Vector2.ZERO, size)
		var sb := Ui.box(Color(Ui.VOID, 0.82 if held else 0.7), Ui.ACCENT_HI if held else Color(1, 1, 1, 0.16), 2 if held else 1, 0)
		sb.draw(get_canvas_item(), r)
		var mono := Ui.font("mono", 500)
		draw_string(mono, Vector2(5, 14), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.55 if held else 0.45))
		var lv := Upgrade.level_in(stack)
		if lv > 1:
			draw_string(mono, Vector2(0, 14), "L%d" % lv, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5, 12, Ui.WAIT)
		if id.is_empty():
			return
		var broken := Wear.is_broken(p.hotbar, i)
		var sw := Rect2(9, 18, size.x - 18, 22)
		var tex := Items.icon_of(id)
		if tex != null:
			draw_texture_rect(tex, Items.art_rect(tex, sw), false, Color(1, 1, 1, 0.5 if broken else 1.0))
		else:
			draw_rect(sw, Color(Color(Items.color_of(id)), 0.5 if broken else 1.0))
		var wpn: Dictionary = Config.WEAPONS.get(id, {})
		var sub := ""
		var sub_col := Color(1, 1, 1, 0.7)
		var sub_font := mono
		if broken:
			sub = "BROKEN"
			sub_col = Ui.SHORT
			sub_font = Ui.font("ui", 600, 1)
		elif wpn.get("kind", "") == "gun":
			sub = "%d / %d" % [p.mag.get(id, 0), p.count_res(wpn.ammo)]
			sub_col = Color("#ffe6a8")
		elif wpn.get("tool", false):
			sub = "TOOL"
			sub_col = Color(1, 1, 1, 0.5)
			sub_font = Ui.font("ui", 600, 1)
		elif int(stack.get("n", 1)) > 1:
			sub = "x%d" % int(stack.n)
		var ui := Ui.font("ui", 500)
		var name_y := size.y - (20.0 if not sub.is_empty() else 12.0)
		var name_ := Items.name_of(id)
		var fs := 12
		draw_string(ui, Vector2(2, name_y), name_, HORIZONTAL_ALIGNMENT_CENTER, size.x - 4, fs,
			Ui.TEXT_BODY if broken else Color.WHITE, TextServer.JUSTIFICATION_NONE)
		if not sub.is_empty():
			draw_string(sub_font, Vector2(0, size.y - 6), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, sub_col)
		# A sliver of condition along the bottom, only once there is something
		# to say. A weapon must never break as a surprise.
		if Wear.is_worn(p.hotbar, i) and sub.is_empty():
			var frac := Wear.frac(p.hotbar, i)
			var wb := Rect2(6, size.y - 8, size.x - 12, 3)
			draw_rect(wb, Ui.VOID)
			draw_rect(Rect2(wb.position, Vector2(wb.size.x * frac, 3)), Ui.wear_color(frac))
