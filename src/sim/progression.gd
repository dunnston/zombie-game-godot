class_name Progression
extends RefCounted
## XP, levels and spending skill points.
##
## Levelling never interrupts play with a forced draft. It hands you points
## and a notification; you open the character sheet and spend them when you
## are somewhere safe enough to think about it.
##
## Every source of XP in the game comes through `add_xp` — kills, containers,
## harvesting, crafting, building and raid payouts — because that is the only
## place `xp_mul` is applied and the only place a level-up can be noticed.


## Awards XP and levels the player up as many times as it takes. A raid
## payout early on is worth several levels at once, so the loop matters.
static func add_xp(sim: GameSim, p: PlayerSim, amount: float, label := "") -> void:
	if p == null or amount <= 0.0:
		return
	var gained := amount * p.xp_mul
	p.xp += gained
	if sim != null and not label.is_empty():
		sim.emit({"t": "xp", "x": p.pos.x, "y": p.pos.y, "n": roundi(gained), "label": label})

	var levelled := 0
	while p.xp >= float(p.xp_next):
		p.xp -= float(p.xp_next)
		p.level += 1
		p.xp_next = Config.xp_for_level(p.level)
		p.skill_points += Config.points_for_level(p.level)
		levelled += 1
	if levelled > 0 and sim != null:
		sim.emit({"t": "level_up", "x": p.pos.x, "y": p.pos.y, "level": p.level})
		var plural := "" if p.skill_points == 1 else "s"
		sim.notify("LEVEL %d — %d skill point%s to spend (K)" % [p.level, p.skill_points, plural],
			"#ffe08a", true)


# ------------------------------------------------------------------ spending --

static func raise_attribute(sim: GameSim, p: PlayerSim, id: String) -> bool:
	var check := Perks.can_raise_attr(p, id)
	if not check.ok:
		if sim != null:
			sim.notify(check.reason, "#c96a5a")
		return false

	var hp_before := p.max_hp
	var stam_before := p.max_stam
	p.attrs[id] = int(p.attrs.get(id, Config.ATTR_START)) + 1
	p.skill_points -= Perks.attr_cost()
	Perks.recompute_stats(p)
	_hand_over_gains(p, hp_before, stam_before)

	if sim != null:
		var a: Dictionary = Config.ATTRS[id]
		sim.notify("%s %d" % [a.name, int(p.attrs[id])], a.color)
		sim.emit({"t": "spend", "x": p.pos.x, "y": p.pos.y, "color": a.color})
	return true


static func buy_perk(sim: GameSim, p: PlayerSim, perk_id: String) -> bool:
	var perk := Perks.perk_by_id(perk_id)
	if perk.is_empty():
		return false
	var st := Perks.perk_status(p, perk)
	if not st.ok:
		if sim != null:
			sim.notify(st.reason, "#c96a5a")
		return false

	var hp_before := p.max_hp
	var stam_before := p.max_stam
	p.perks[perk_id] = int(p.perks.get(perk_id, 0)) + 1
	p.skill_points -= Perks.perk_cost()
	Perks.recompute_stats(p)
	_hand_over_gains(p, hp_before, stam_before)

	if sim != null:
		var rank: int = int(p.perks[perk_id])
		var suffix := " %d/%d" % [rank, int(perk.max)] if int(perk.max) > 1 else ""
		sim.notify("%s%s — %s" % [perk.name, suffix, perk.desc], "#b7e08a")
		sim.emit({"t": "spend", "x": p.pos.x, "y": p.pos.y, "color": "#b7e08a"})
	return true


## A rank that raises the ceiling hands the difference over rather than
## leaving it as headroom: buying Thick Skin mid-raid heals you by 30, it does
## not hand you a bar that is suddenly three-quarters empty.
##
## This is the one thing about a purchase that is not a pure function of the
## build, which is why it lives here and not in the recompute.
static func _hand_over_gains(p: PlayerSim, hp_before: float, stam_before: float) -> void:
	p.hp += maxf(0.0, p.max_hp - hp_before)
	p.stam += maxf(0.0, p.max_stam - stam_before)


# -------------------------------------------------------------- for the sheet --

## Every point the player has ever earned. Level 1 grants nothing; the first
## point arrives with level 2.
static func lifetime_points(p: PlayerSim) -> int:
	var total := 0
	for l in range(2, p.level + 1):
		total += Config.points_for_level(l)
	return total


static func spent_points(p: PlayerSim) -> int:
	return lifetime_points(p) - p.skill_points
