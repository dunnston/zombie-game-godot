class_name CrewPage
extends RefCounted
## The roster: one row per person on the left, the selected survivor and the
## four jobs on the right. The decision is "what is this person for", and it
## belongs beside the pack you would be stocking for them.
##
## Both caps are shown, separately — Charisma "will follow you" against bunks
## built — because being told "no room" without which limit is binding is
## useless.


func build(s: InventoryScreen, col: VBoxContainer) -> void:
	var status := Ui.hbox(0)
	s.section(status, func() -> String: return _ration_state(s)[0], func(box: Container) -> void:
		var r: Array = _ration_state(s)
		if not String(r[0]).is_empty():
			box.add_child(Ui.boxed(Ui.box(Ui.SHORT_FILL, Color("#7a3f36"), 1, 0, 14, 7),
				Ui.hbox(10, [Ui.label(String(r[0]), "Caps", Ui.SHORT), Ui.label(String(r[1]), "Mono", Ui.SHORT)]))))
	col.add_child(s.tab_bar([status]))

	var stats := Ui.hbox(28)
	var vals := {}
	for k in [["roster", "Roster", null], ["cha", "Will follow you", Color("#c48fd0")], ["bunks", "Bunks built", Ui.ACCENT_HI],
			["upkeep", "Upkeep", null], ["towers", "Free watchtowers", null]]:
		var v := Ui.label("", "Mono18", k[2])
		vals[k[0]] = v
		stats.add_child(Ui.vbox(3, [Ui.label(String(k[1]), "Caps"), v]))
	var why := Ui.label("", "Body14", Ui.TEXT_DIM)
	why.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.refresher(func() -> void:
		var lim := s.sim.crew.limits(s.sim)
		var crew := s.sim.crew.alive()
		Ui.set_text(vals.roster, "%d / %d" % [crew.size(), int(lim.cap)])
		Ui.set_text(vals.cha, "%d  ·  CHA" % int(lim.charisma))
		Ui.set_text(vals.bunks, str(int(lim.bunks)))
		Ui.set_text(vals.upkeep, "%.1f rations / min" % _per_min(s))
		Ui.set_text(vals.towers, str(s.sim.crew.free_towers(s.sim).size()))
		var refusal := s.sim.crew.recruit_refusal(s.sim, s.player) if not s.sim.crew.rescues.is_empty() else ""
		Ui.set_text(why, refusal))
	col.add_child(Chrome.sub_bar([Ui.label("Crew", "ScreenTitle"), stats, Ui.expand(why)], 76))

	var body := Chrome.body()
	col.add_child(Chrome.body_margin(body))
	var roster := Ui.vbox(8)
	s.section(roster, func() -> String: return _roster_sig(s), func(box: Container) -> void: _build_roster(s, box))
	var left := Ui.panel("Pane", Ui.vbox(0, [
		Ui.panel("PanelHead", Ui.hbox(12, [Ui.expand(Ui.label("Survivors", "Caps")), Ui.label("Click to select  ·  then pick a job", "Small")])),
		Ui.expand(Ui.scroller(Ui.pad(roster, 12)), true, true), _pantry(s)]))
	left.custom_minimum_size.x = 640
	body.add_child(left)

	var right := Ui.vbox(16)
	Ui.expand(right, true, true)
	s.section(right, func() -> String: return _detail_sig(s), func(box: Container) -> void: _build_detail(s, box))
	body.add_child(right)


func _per_min(s: InventoryScreen) -> float:
	return s.sim.crew.alive().size() * float(Config.SURVIVOR.upkeep_per_min) * s.player.upkeep_mul


## The top bar's warning: nothing when fed, a coral chip when short.
func _ration_state(s: InventoryScreen) -> Array:
	var rations := s.sim.crew.rations_held(s.sim)
	var per := _per_min(s)
	if s.sim.crew.debt > 1.0:
		return ["Out of rations", "THEY ARE STARVING"]
	if per > 0.0 and rations < per * 3.0:
		return ["Rations short", "%d IN STASH  ·  %.1f / MIN" % [rations, per]]
	return ["", ""]


func _selected(s: InventoryScreen) -> SurvivorSim:
	var crew := s.sim.crew.alive()
	if crew.is_empty():
		return null
	for c in crew:
		if c.id == s.crew_sel:
			return c
	s.crew_sel = crew[0].id
	return crew[0]


func _roster_sig(s: InventoryScreen) -> String:
	var sig := str(s.crew_sel) + "|"
	for c in s.sim.crew.alive():
		sig += "%d%s%d%s%s%s%d%d," % [c.id, c.job, c.level, str(c.downed), str(c.hungry), str(c.out_of_ammo), roundi(c.hp), roundi(c.xp)]
	return sig


func _initials(n: String) -> String:
	var parts := n.split(" ", false)
	if parts.size() >= 2:
		return (parts[0].left(1) + parts[1].left(1)).to_upper()
	return n.left(2).to_upper()


func _build_roster(s: InventoryScreen, box: Container) -> void:
	var crew := s.sim.crew.alive()
	if crew.is_empty():
		box.add_child(Ui.panel("Inset", Ui.vbox(8, [
			Ui.para("Nobody yet. There are %d people out there to find — look inside buildings." % s.sim.crew.rescues.size(), "Body", Ui.TEXT_BODY),
			Ui.para("You will need a Bunk for each of them, and the Charisma to lead them.", "Small")])))
		return
	var sel := _selected(s)
	for c in crew:
		var job: Dictionary = Config.JOBS.get(c.job, Config.JOBS.guard)
		var jc := Color(String(job.color))
		var on := c == sel
		var tile := Ui.boxed(Ui.box(Ui.VOID, Ui.LINE_STRONG if on else Ui.LINE, 1, 0), Ui.label(_initials(c.display_name), "Mono15", jc))
		tile.custom_minimum_size = Vector2(40, 40)
		(tile.get_child(0) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var who := Ui.vbox(3, [Ui.label(c.display_name, "ItemName", Ui.TEXT_HIGH if on else Ui.TEXT_BODY),
			Ui.label("LEVEL %d  ·  %d / %d XP" % [c.level, roundi(c.xp), roundi(c.xp_to_next())], "Mono12")])
		who.custom_minimum_size.x = 190
		var m := UiMeter.new(10, Ui.DOWN if c.downed else Ui.DANGER)
		m.frac = clampf(c.hp / maxf(1.0, c.max_hp), 0.0, 1.0)
		var note := "HP %d / %d" % [roundi(c.hp), roundi(c.max_hp)]
		var nc := Ui.TEXT_DIM
		if c.downed:
			note = "DOWN  ·  %.0fS TO REACH THEM" % maxf(0.0, c.down_t)
			nc = Ui.DOWN
		elif c.hungry:
			note += "  ·  HUNGRY"
			nc = Ui.WORN
		var hp := Ui.vbox(4, [m, Ui.label(note, "Mono12", nc)])
		hp.custom_minimum_size.x = 150
		var badge: Control = Ui.badge(String(job.name) + ("  ·  tower" if c.posted else ""), jc)
		if c.downed:
			badge = Ui.badge("Get them up", Ui.SHORT)
		elif c.out_of_ammo:
			badge = Ui.badge("No ammo in the stash", Ui.SHORT)
		var row := Ui.hbox(12, [tile, who, hp, Ui.spacer(), badge])
		for x in row.get_children():
			(x as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var cid: int = c.id
		var b := Ui.face_button("RailRowOn" if on else "MenuRow", Ui.pad(row, 14, 12, 14, 12), func() -> void:
			s.crew_sel = cid
			s.crew_job = "")
		b.add_theme_stylebox_override("normal", Ui.box(Ui.SELECTED if on else Ui.TAB, Ui.ACCENT if on else Ui.LINE, 1, 2))
		s.reg_row("crew:%d" % cid, b)
		box.add_child(b)


## The pantry: what the crew eats and shoots, and the reminder that it comes
## out of the stash and never out of your pack.
func _pantry(s: InventoryScreen) -> PanelContainer:
	var rm := UiMeter.new(10)
	var rv := Ui.label("", "Mono", Ui.SHORT)
	var am := UiMeter.new(10, Ui.OK)
	var av := Ui.label("", "Mono", Ui.OK)
	for v in [rv, av]:
		(v as Label).custom_minimum_size.x = 80
		(v as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var cap := func(t: String) -> Label:
		var l := Ui.label(t, "Body14")
		l.custom_minimum_size.x = 170
		return l
	for m in [rm, am]:
		(m as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(m as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.refresher(func() -> void:
		var r := s.sim.crew.rations_held(s.sim)
		# Ten minutes of upkeep is what "stocked" means on the meter.
		var want := maxf(10.0, _per_min(s) * 10.0)
		var ok := r >= _per_min(s) * 3.0 and s.sim.crew.debt < 1.0
		rm.set_value(r / want, Ui.OK if ok else Ui.SHORT)
		Ui.set_text(rv, "%d / %d" % [r, roundi(want)])
		Ui.set_color(rv, Ui.OK if ok else Ui.SHORT)
		var a := s.sim.stash.count("ammoP") if s.sim.stash != null else 0
		am.set_value(a / 120.0, Ui.OK if a > 0 else Ui.SHORT)
		Ui.set_text(av, str(a))
		Ui.set_color(av, Ui.OK if a > 0 else Ui.SHORT))
	var col := Ui.vbox(10, [Ui.label("The pantry", "Caps"), Ui.hbox(12, [cap.call("Rations in the stash"), rm, rv]),
		Ui.hbox(12, [cap.call("9mm in the stash"), am, av]),
		Ui.para("They eat and shoot out of the shared stash, never out of your pack. Hungry survivors are slower and shoot less.",
			"Small", Color(1, 1, 1, 0.4))])
	return Ui.boxed(Ui.edge(Color(0, 0, 0, 0), Ui.LINE_SOFT, 0, 1, 0, 0, 16, 16), col)


func _detail_sig(s: InventoryScreen) -> String:
	var c := _selected(s)
	if c == null:
		return "none"
	return "%d|%s|%s|%d|%d|%s|%s|%d|%d|%d" % [c.id, c.job, s.crew_job, c.level, roundi(c.xp), str(c.downed), str(c.hungry),
		s.sim.crew.free_towers(s.sim).size(), s.sim.structs.damaged_within(c.pos).size() if s.sim.structs.list.size() > 0 else 0,
		c.carrying.size() + c.carry_items.size()]


func _build_detail(s: InventoryScreen, box: Container) -> void:
	var c := _selected(s)
	if c == null:
		box.add_child(Ui.panel("Inset", Ui.para("Take somebody in and they appear here: a Bunk each, and the Charisma to lead them.", "Body14", Ui.TEXT_DIM)))
		return
	var job: Dictionary = Config.JOBS.get(c.job, Config.JOBS.guard)
	var jc := Color(String(job.color))
	var tile := Ui.boxed(Ui.box(Ui.VOID, Ui.LINE_STRONG, 1, 0), Ui.label(_initials(c.display_name), "Mono22", jc))
	tile.custom_minimum_size = Vector2(96, 96)
	(tile.get_child(0) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var badges := Ui.hbox(6)
	var hauling := not c.carrying.is_empty() or not c.carry_items.is_empty()
	if hauling:
		badges.add_child(Ui.badge("Carrying a haul", Ui.OK))
	if c.hungry:
		badges.add_child(Ui.badge("Hungry", Ui.WORN))
	if c.downed:
		badges.add_child(Ui.badge("Down", Ui.DOWN))
	if c.out_of_ammo:
		badges.add_child(Ui.badge("No ammo", Ui.SHORT))
	badges.add_child(Ui.badge("HP %d / %d" % [roundi(c.hp), roundi(c.max_hp)], Ui.TEXT_BODY, true))
	var range_: float = float(Config.SURVIVOR.range)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 20)
	g.add_theme_constant_override("v_separation", 10)
	for st in [["Damage", "%.0f" % c.dmg], ["Range", "%d" % roundi(range_)], ["Kills", str(c.kills)], ["Level", str(c.level)]]:
		g.add_child(Ui.stat(String(st[0]), String(st[1])))
	var head := Ui.panel("PanelHeadWide", Ui.hbox(16, [tile, Ui.expand(Ui.vbox(7, [Ui.label(c.display_name, "PanelTitle"),
		Ui.label("Level %d  ·  on %s duty" % [c.level, String(job.name).to_lower()], "Caps"), badges])), g]))
	var xp := UiMeter.new(8, Ui.XP)
	xp.frac = clampf(c.xp / maxf(1.0, c.xp_to_next()), 0.0, 1.0)
	var bars := Ui.hbox(24, [Ui.expand(Ui.vbox(6, [Ui.hbox(8, [Ui.expand(Ui.label("Experience", "Caps")),
		Ui.label("%d / %d" % [roundi(c.xp), roundi(c.xp_to_next())], "Mono12", Ui.XP)]), xp]))])
	if hauling:
		var parts := PackedStringArray()
		for id in c.carrying:
			parts.append("%s %d" % [String(Config.RES[id].short) if Config.RES.has(id) else Items.name_of(id), int(c.carrying[id])])
		var hm := UiMeter.new(8, Color("#c4a86a"))
		hm.frac = 0.4
		bars.add_child(Ui.expand(Ui.vbox(6, [Ui.hbox(8, [Ui.expand(Ui.label("Haul carried", "Caps")),
			Ui.label("  ·  ".join(parts), "Mono12", Color("#c4a86a"))]), hm])))
	box.add_child(Ui.panel("Pane", Ui.vbox(0, [head, Ui.pad(bars, 20, 16, 20, 16)])))

	# The four jobs as cards, each with what it needs.
	var cards := GridContainer.new()
	cards.columns = 2
	cards.add_theme_constant_override("h_separation", 12)
	cards.add_theme_constant_override("v_separation", 12)
	if s.crew_job.is_empty():
		s.crew_job = c.job
	for id: String in Config.JOB_IDS:
		cards.add_child(_job_card(s, c, id))
	var assign_face := Ui.hbox(12, [Ui.label("ASSIGN", "Name18", Ui.INK), Ui.label("ENTER", "Mono12", Color(Ui.INK, 0.7))])
	for x in assign_face.get_children():
		(x as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var assign := Ui.face_button("Primary", Ui.pad(assign_face, 24, 0, 24, 0), func() -> void: s._press_button("assign"))
	assign.custom_minimum_size.y = 48
	assign.disabled = s.crew_job == c.job or not _job_block(s, c, s.crew_job).is_empty()
	s.reg_button("assign", assign)
	var foot := Ui.hbox(12, [assign, Ui.spacer(), Ui.label("A job they cannot reach is given up rather than leaned on", "Small", Ui.TEXT_OFF)])
	foot.get_child(2).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var jobs := Ui.panel("Pane", Ui.vbox(0, [
		Ui.panel("PanelHead", Ui.hbox(12, [Ui.expand(Ui.label("Job", "Caps")), Ui.label("One job at a time  ·  changing it hands in whatever they carry", "Small")])),
		Ui.expand(Ui.scroller(Ui.pad(cards, 16)), true, true),
		Ui.boxed(Ui.edge(Color(0, 0, 0, 0), Ui.LINE_SOFT, 0, 1, 0, 0, 16, 16), foot)]))
	Ui.expand(jobs, true, true)
	box.add_child(jobs)


## Why a job cannot be taken, or "". A Sniper is the only job that can be
## refused, and it says why up front rather than after the click.
func _job_block(s: InventoryScreen, c: SurvivorSim, id: String) -> String:
	if id == "sniper" and c.job != "sniper" and s.sim.crew.free_towers(s.sim).is_empty():
		return "No free Watchtower"
	return ""


func _job_card(s: InventoryScreen, c: SurvivorSim, id: String) -> Button:
	var job: Dictionary = Config.JOBS[id]
	var current := c.job == id
	var chosen := s.crew_job == id
	var blocked := _job_block(s, c, id)
	var top := Ui.hbox(10, [Ui.label(String(job.name), "Name18", Ui.TEXT_HIGH if current or chosen else (Ui.TEXT_DIM if not blocked.is_empty() else Ui.TEXT_BODY))])
	if current:
		top.add_child(Ui.boxed(Ui.box(Ui.ACCENT, Ui.ACCENT, 0, 0, 7, 2), Ui.label("Current", "Caps", Ui.INK)))
	var pre := "ALWAYS AVAILABLE"
	var pc := Ui.TEXT_OFF
	match id:
		"sniper":
			var n := s.sim.crew.free_towers(s.sim).size()
			pre = ("%d TOWER%s FREE" % [n, "" if n == 1 else "S"]) if blocked.is_empty() else blocked.to_upper()
			pc = Ui.LOCKED if blocked.is_empty() else Ui.SHORT
		"scavenger":
			var ok := s.sim.stash != null
			pre = "NEEDS A SUPPLY STASH  " + ("✓" if ok else "✕")
			pc = Ui.OK_DIM if ok else Ui.SHORT
		"builder":
			var n := s.sim.structs.damaged_within(c.pos).size()
			pre = "%d PIECE%s DAMAGED" % [n, "" if n == 1 else "S"]
			pc = Ui.ACCENT_HI if n > 0 else Ui.TEXT_OFF
	var face := Ui.vbox(8, [top, Ui.para(String(job.desc), "Body14", Ui.TEXT_BODY if chosen or current else Ui.TEXT_DIM),
		Ui.label(pre, "Mono12", pc)])
	var jid := id
	var b := Ui.face_button("RailRowOn" if chosen else ("CardDim" if not blocked.is_empty() else "Card"), Ui.pad(face, 16), func() -> void:
		s.crew_job = jid)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.reg_row("job:" + id, b)
	return b


func press(s: InventoryScreen, id: String) -> void:
	if id == "assign":
		commit(s)


func commit(s: InventoryScreen) -> void:
	var c := _selected(s)
	if c == null or s.crew_job.is_empty() or s.crew_job == c.job:
		return
	if _job_block(s, c, s.crew_job).is_empty():
		Actions.assign_job(s.sim, c, s.crew_job)


func nav(s: InventoryScreen, dx: int, dy: int) -> void:
	var crew := s.sim.crew.alive()
	if crew.is_empty():
		return
	if dy != 0:
		var i := 0
		for k in range(crew.size()):
			if crew[k].id == s.crew_sel:
				i = k
		s.crew_sel = crew[clampi(i + dy, 0, crew.size() - 1)].id
		s.crew_job = ""
	if dx != 0:
		var j := Config.JOB_IDS.find(s.crew_job)
		s.crew_job = String(Config.JOB_IDS[clampi(j + dx, 0, Config.JOB_IDS.size() - 1)])
