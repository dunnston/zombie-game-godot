class_name CharPage
extends RefCounted
## The character sheet (K): the six attributes on the left, the selected
## attribute's perk tree on the right. Nothing is merely greyed out: a row you
## cannot buy says why, because "Needs STR 5" is a plan and "No skill points"
## is a wait, and those are different problems.
##
## Clicking an attribute you are not looking at selects it; clicking the one
## you are looking at spends a point. One click never does both, so browsing
## the tree can never cost you a point.


func build(s: InventoryScreen, col: VBoxContainer) -> void:
	var p := s.player
	var points := Ui.hbox(0)
	s.section(points, func() -> String: return str(p.skill_points), func(box: Container) -> void:
		if p.skill_points > 0:
			box.add_child(Ui.boxed(Ui.box(Ui.ACCENT_FILL, Color("#7a6420"), 1, 0, 14, 7), Ui.hbox(10, [
				Ui.label(str(p.skill_points), "Mono14", Ui.ACCENT_HI),
				Ui.label("Point to spend" if p.skill_points == 1 else "Points to spend", "Caps", Ui.ACCENT_HI)]))))
	col.add_child(s.tab_bar([points]))

	var lvl := Ui.label("", "ScreenTitle")
	var xp_v := Ui.label("", "Mono12", Ui.XP)
	var xp := UiMeter.new(8, Ui.XP)
	var xp_box := Ui.vbox(6, [Ui.hbox(8, [Ui.expand(Ui.label("Experience", "Caps")), xp_v]), xp])
	xp_box.custom_minimum_size.x = 420
	var stats := Ui.hbox(28)
	var vals := {}
	for k in ["Health", "Stamina", "Carry", "Armour", "Crit"]:
		var v := Ui.label("", "Mono18")
		vals[k] = v
		stats.add_child(Ui.vbox(3, [Ui.label(k, "Caps"), v]))
	var spent := Ui.label("", "Mono", Ui.TEXT_DIM)
	s.refresher(func() -> void:
		Ui.set_text(lvl, "Level %d" % p.level)
		Ui.set_text(xp_v, "%d / %d XP" % [roundi(p.xp), p.xp_next])
		xp.set_value(p.xp / maxf(1.0, float(p.xp_next)))
		Ui.set_text(vals.Health, str(roundi(p.max_hp)))
		Ui.set_text(vals.Stamina, str(roundi(p.max_stam)))
		Ui.set_text(vals.Carry, str(roundi(p.carry_cap)))
		Ui.set_text(vals.Armour, "%d%%" % roundi(p.armor_dr * 100.0))
		Ui.set_text(vals.Crit, "%d%%" % roundi(p.crit_chance * 100.0))
		Ui.set_text(spent, "%d OF %d POINTS SPENT" % [Progression.spent_points(p), Progression.lifetime_points(p)]))
	col.add_child(Chrome.sub_bar([lvl, xp_box, Ui.rule(true, 40), stats, Ui.spacer(), spent], 76))

	var body := Chrome.body()
	col.add_child(Chrome.body_margin(body))
	var attrs := Ui.vbox(8)
	s.section(attrs, func() -> String: return _attr_sig(s), func(box: Container) -> void: _build_attrs(s, box))
	var left := Ui.panel("Pane", Ui.vbox(0, [
		Ui.panel("PanelHead", Ui.hbox(12, [Ui.expand(Ui.label("Attributes", "Caps")), Ui.label("Click to open its tree  ·  click again to raise it", "Small")])),
		Ui.expand(Ui.scroller(Ui.pad(attrs, 12)), true, true),
		Ui.boxed(Ui.edge(Color(0, 0, 0, 0), Ui.LINE_SOFT, 0, 1, 0, 0, 16, 16),
			Ui.para("Nothing is spent by browsing. A point buys one rank of an attribute or one rank of a perk.", "Small", Color(1, 1, 1, 0.4)))]))
	left.custom_minimum_size.x = 560
	body.add_child(left)

	var tree := Ui.vbox(0)
	Ui.expand(tree, true, true)
	s.section(tree, func() -> String: return _tree_sig(s), func(box: Container) -> void: _build_tree(s, box))
	var right := Ui.panel("Pane", tree)
	Ui.expand(right, true, true)
	body.add_child(right)


func _attr_sig(s: InventoryScreen) -> String:
	var sig := s.char_attr + str(s.player.skill_points)
	for id in Config.ATTR_IDS:
		sig += str(s.player.attrs.get(id, 0)) + String(Perks.can_raise_attr(s.player, id).reason)
	return sig


func _build_attrs(s: InventoryScreen, box: Container) -> void:
	for id: String in Config.ATTR_IDS:
		var a: Dictionary = Config.ATTRS[id]
		var rank: int = int(s.player.attrs.get(id, Config.ATTR_START))
		var on := s.char_attr == id
		var check := Perks.can_raise_attr(s.player, id)
		var ac := Color(String(Ui.ATTR_COLORS.get(id, "#c7c2b4")))
		var maxed := rank >= Config.ATTR_MAX
		var top := Ui.hbox(12, [Ui.label("%s %d" % [String(a.abbr), rank], "Mono18", ac),
			Ui.label(String(a.get("name", id)), "Row", Ui.TEXT_HIGH if on else Ui.TEXT_BODY), Ui.spacer(),
			Ui.label(String(a.per_rank), "Small")])
		var bottom := Ui.hbox(12, [Ui.expand(Ui.label(String(a.blurb), "Small", Color(1, 1, 1, 0.35 if on else 0.3)))])
		if on or maxed:
			bottom.add_child(Ui.label("Spend a point" if check.ok else String(check.reason), "Caps", Ui.OK if check.ok else Ui.TEXT_OFF))
		var face := Ui.pad(Ui.vbox(6, [top, bottom]), 14, 12, 14, 12)
		var aid := id
		var b := Ui.face_button("RailRow", face, func() -> void:
			if s.char_attr != aid:
				s.char_attr = aid
				s.char_perk = -1
			else:
				Actions.raise_attribute(s.sim, s.player, aid))
		var normal := Ui.box(Ui.SELECTED if on else Ui.TAB, ac if on else Ui.LINE, 1, 2, 0, 0)
		var hot := Ui.box(Ui.SELECTED if on else Ui.HOVER, ac if on else Ui.LINE_STRONG, 1, 2, 0, 0)
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", hot)
		b.add_theme_stylebox_override("pressed", hot)
		b.add_theme_stylebox_override("hover_pressed", hot)
		if maxed:
			b.modulate.a = 0.6
		s.reg_row("attr:" + id, b)
		box.add_child(b)


func _tree_sig(s: InventoryScreen) -> String:
	var sig := "%s|%d|%d|" % [s.char_attr, s.char_perk, s.player.skill_points]
	for perk in Perks.perks_for(s.char_attr):
		var st := Perks.perk_status(s.player, perk)
		sig += "%s%d%s," % [perk.id, int(st.rank), String(st.reason)]
	return sig + str(s.player.attrs)


func _build_tree(s: InventoryScreen, box: Container) -> void:
	var id := s.char_attr
	var a: Dictionary = Config.ATTRS[id]
	var ac := Color(String(Ui.ATTR_COLORS.get(id, "#c7c2b4")))
	var list := Perks.perks_for(id)
	var rank: int = int(s.player.attrs.get(id, Config.ATTR_START))
	box.add_child(Ui.panel("PanelHead", Ui.hbox(12, [Ui.label("%s tree" % String(a.get("name", id)), "SectionHead", ac),
		Ui.expand(Ui.label("%d perks  ·  gated on your %s rank" % [list.size(), String(a.abbr)], "Small")),
		Ui.label("%s %d / %d" % [String(a.abbr), rank, Config.ATTR_MAX], "Mono", Ui.TEXT_DIM)])))
	var rows := Ui.vbox(10)
	for i in range(list.size()):
		rows.add_child(_perk_row(s, list[i], i == s.char_perk))
	# The other trees, one click away.
	var others := Ui.hbox(24, [Ui.label("Other trees", "Caps")])
	for other: String in Config.ATTR_IDS:
		if other == id:
			continue
		var oa: Dictionary = Config.ATTRS[other]
		var face := Ui.hbox(8, [Ui.rect(Color(String(Ui.ATTR_COLORS.get(other, "#c7c2b4"))), 10, 10),
			Ui.label("%s %d" % [String(oa.get("name", other)), int(s.player.attrs.get(other, Config.ATTR_START))], "Body14")])
		(face.get_child(0) as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var oid := other
		var b := Ui.face_button("RailRow", face, func() -> void:
			s.char_attr = oid
			s.char_perk = -1)
		b.custom_minimum_size.y = 32
		others.add_child(b)
	rows.add_child(Ui.boxed(Ui.box(Ui.BASE, Ui.LINE_SOFT, 1, 2, 16, 8), others))
	box.add_child(Ui.expand(Ui.scroller(Ui.pad(rows, 16)), true, true))
	box.add_child(Ui.boxed(Ui.edge(Color(0, 0, 0, 0), Ui.LINE_SOFT, 0, 1, 0, 0, 16, 14),
		Ui.hbox(28, [Ui.hint("↑↓", "Move"), Ui.hint("←→", "Switch tree"), Ui.hint("ENTER", "Buy a rank"), Ui.spacer(),
			Ui.label("A locked row says what it needs — that is a plan, not a refusal", "Small", Ui.TEXT_OFF)])))


func _perk_row(s: InventoryScreen, perk: Dictionary, on: bool) -> Control:
	var st := Perks.perk_status(s.player, perk)
	var rank: int = int(st.rank)
	var mx: int = int(perk.max)
	var full := rank >= mx
	var locked: bool = st.locked
	var name_col := Ui.TEXT_DIM if locked else Ui.TEXT_HIGH
	var rank_col := Ui.OK if full else (Ui.ACCENT_HI if rank > 0 else Ui.TEXT_OFF)
	var action: Control
	if st.ok:
		var pid := String(perk.id)
		var buy := Ui.button("BUY", "PrimarySmall", func() -> void: Actions.buy_perk(s.sim, s.player, pid))
		buy.custom_minimum_size = Vector2(76, 30)
		s.reg_row("perk:" + pid, buy)
		action = buy
	elif full:
		action = Ui.badge("Fully learned", Ui.OK)
	else:
		action = Ui.badge(String(st.reason), Ui.LOCKED if locked else Ui.TEXT_OFF)
	var top := Ui.hbox(12, [Ui.label(String(perk.name), "ItemName", name_col), Ui.label("%d / %d" % [rank, mx], "Mono14", rank_col),
		Ui.spacer(), action])
	for c in top.get_children():
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pips := UiPips.new(mx, Vector2(26, 6), Ui.OK if full else Ui.ACCENT_HI, Ui.LINE if not locked else Ui.LINE_SOFT, 4)
	pips.set_filled(rank)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bottom := Ui.hbox(16, [pips, Ui.expand(Ui.label(String(perk.desc), "Body14", Ui.TEXT_OFF if locked else Ui.TEXT_BODY)),
		Ui.label("NEEDS %s %d" % [String(Config.ATTRS[perk.attr].abbr), int(perk.req)], "Mono12", Ui.TEXT_OFF)])
	var bg := Ui.DIM_CARD if locked else Ui.RAISED
	var edge := Ui.ACCENT_HI if on else (Ui.LINE_SOFT if locked else Ui.LINE)
	var p := Ui.boxed(Ui.box(bg, edge, 2 if on else 1, 2, 16, 14), Ui.vbox(8, [top, bottom]))
	if not s._named.has("perk:" + String(perk.id)):
		s.reg_row("perk:" + String(perk.id), p)
	return p


func nav(s: InventoryScreen, dx: int, dy: int) -> void:
	if dx != 0:
		var i := Config.ATTR_IDS.find(s.char_attr)
		s.char_attr = String(Config.ATTR_IDS[(i + dx + Config.ATTR_IDS.size()) % Config.ATTR_IDS.size()])
		s.char_perk = -1
		return
	var n := Perks.perks_for(s.char_attr).size()
	if n > 0:
		s.char_perk = clampi(s.char_perk + dy, 0, n - 1)


## Enter buys the highlighted rank; Shift+Enter raises the attribute itself.
func commit(s: InventoryScreen, shift: bool) -> void:
	if shift:
		Actions.raise_attribute(s.sim, s.player, s.char_attr)
		return
	var list := Perks.perks_for(s.char_attr)
	if s.char_perk >= 0 and s.char_perk < list.size():
		Actions.buy_perk(s.sim, s.player, String(list[s.char_perk].id))


func press(_s: InventoryScreen, _id: String) -> void:
	pass
