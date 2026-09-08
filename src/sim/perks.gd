class_name Perks
extends RefCounted
## Attributes and perks, and the one pure pass that turns them into stats.
##
## A skill point buys either a rank in one of the six attributes or a rank in
## one of the twenty-eight perks. Perks are gated on the rank of their parent
## attribute, so investing in an attribute is what opens its tree.
##
## **Nothing is mutated on purchase.** Buying writes a number into `p.attrs`
## or `p.perks` and then the whole stat block is rebuilt from scratch, base ->
## attributes -> perks -> gear. That is invariant 4, and it is what makes
## save/load, respawn and any future respec correct by construction: there is
## exactly one place a modifier can come from, and no way for one to be
## applied twice or left behind.
##
## The tables live in `config.gd` (invariant 5). This file is the behaviour.


## A fresh attribute block, every rank at the starting value.
static func starting_attrs() -> Dictionary:
	var out := {}
	for id in Config.ATTR_IDS:
		out[id] = Config.ATTR_START
	return out


static func perk_by_id(id: String) -> Dictionary:
	for k in Config.PERKS:
		if k.id == id:
			return k
	return {}


static func perks_for(attr: String) -> Array:
	var out: Array = []
	for k in Config.PERKS:
		if k.attr == attr:
			out.append(k)
	return out


# ------------------------------------------------------------ stat rebuild --

## Rebuilds every derived stat from scratch. Safe to call at any time, and
## called by everything that changes what a player is or wears.
##
## The order matters only where a perk multiplies rather than adds: the
## multiplicative ones (spread, search, build cost, threat, noise) compound
## with the attribute term, which is why the attribute pass runs first.
static func recompute_stats(p: PlayerSim) -> void:
	for key in Config.STAT_BASE:
		p.set(key, Config.STAT_BASE[key])
	_apply_attributes(p)
	for k in Config.PERKS:
		var rank: int = int(p.perks.get(k.id, 0))
		if rank > 0:
			_apply_perk(p, String(k.id), rank)
	_apply_gear(p)

	p.max_hp = roundf(p.max_hp)
	p.max_stam = roundf(p.max_stam)
	p.carry_cap = roundf(p.carry_cap)
	# Losing a source of maximum health must not leave you standing above your
	# own ceiling. Gaining one is *not* handled here — see Progression.
	p.hp = minf(p.hp, p.max_hp)
	p.stam = minf(p.stam, p.max_stam)


## Rank 1 is the baseline the tables are written against, so a rank of 2 —
## where everyone starts — is worth exactly one step of each line below.
static func _apply_attributes(p: PlayerSim) -> void:
	var r := func(id: String) -> float:
		return float(int(p.attrs.get(id, Config.ATTR_START)) - 1)

	p.melee_mul += 0.09 * r.call("str")
	p.carry_cap += 25.0 * r.call("str")
	p.chop_mul += 0.06 * r.call("str")

	p.spread_mul *= pow(0.96, r.call("per"))
	p.search_mul *= pow(0.95, r.call("per"))
	p.pickup_range += 3.0 * r.call("per")

	p.max_hp += 12.0 * r.call("con")
	p.max_stam += 10.0 * r.call("con")
	# CON is the only attribute that touches stamina, and while only sprinting
	# spent it, raising the ceiling was the whole effect. Harvesting empties
	# the bar now, so recovery is half the stat and CON raises both.
	p.stam_regen += 1.2 * r.call("con")

	# The roster is a count of whole people, so it steps every two ranks off
	# the raw rank rather than off the baseline-adjusted one.
	p.survivor_cap += int(p.attrs.get("cha", Config.ATTR_START)) / 2
	p.survivor_dmg_mul += 0.06 * r.call("cha")

	p.xp_mul += 0.07 * r.call("int")
	p.build_cost_mul *= pow(0.97, r.call("int"))
	p.turret_mul += 0.05 * r.call("int")

	p.crit_chance += 0.02 * r.call("lck")
	p.rare_loot_mul += 0.05 * r.call("lck")


## What each perk does. Runs during the recompute with the player's current
## rank in it, never on purchase.
##
## `rank` is the number of times the perk has been taken, and the linear perks
## multiply by it directly — Pack Mule at rank 3 is +210 carry, not +70. The
## multiplicative ones raise their factor to the rank for the same reason.
static func _apply_perk(p: PlayerSim, id: String, rank: int) -> void:
	var r := float(rank)
	match id:
		# ------------------------------------------------------ strength --
		"packMule":       p.carry_cap += 70.0 * r
		"heavyHitter":    p.melee_mul += 0.25 * r
		"demolisher":     p.chop_mul += 1.0 * r
		"adrenaline":     p.adrenaline = true

		# ---------------------------------------------------- perception --
		"scrounger":      p.loot_mul += 0.35 * r
		"quickHands":
			p.search_mul *= pow(0.7, r)
			p.pickup_range += 18.0 * r
		"eagleEye":
			p.spread_mul *= pow(0.78, r)
			p.range_mul += 0.12 * r
		"sixthSense":     p.radar_mul += 1.4

		# ------------------------------------------------- constitution --
		"thickSkin":      p.max_hp += 30.0 * r
		"marathon":
			p.max_stam += 45.0 * r
			p.stam_regen += 5.0 * r
		"woodcraft":      p.chop_stam_mul *= pow(0.65, r)
		"ironStomach":
			p.heal_mul += 0.6 * r
			p.heal_speed_mul *= pow(0.7, r)
		"secondWind":     p.second_wind = true

		# ------------------------------------------------------ charisma --
		"recruiter":      p.survivor_cap += rank
		"inspiring":
			p.survivor_dmg_mul += 0.3 * r
			p.survivor_hp_mul += 0.25 * r
		"quartermaster":  p.upkeep_mul *= pow(0.6, r)
		"leader":         p.survivor_xp_mul += 0.6

		# -------------------------------------------------- intelligence --
		"fastLearner":    p.xp_mul += 0.22 * r
		"engineer":       p.build_cost_mul *= pow(0.78, r)
		"fortifier":      p.struct_hp_mul += 0.45 * r
		"gunsmith":       p.craft_yield_mul += 0.6 * r
		"fireControl":    p.turret_mul += 0.35 * r
		"hotwire":
			p.hotwire = true
			p.hotwire_speed_mul *= pow(0.5, r - 1.0)

		# ---------------------------------------------------------- luck --
		"scavengersLuck": p.rare_loot_mul += 0.3 * r
		"luckyStrike":    p.crit_chance += 0.07 * r
		"ammoCache":      p.free_shot_chance += 0.2 * r
		"lowProfile":
			p.threat_mul *= pow(0.7, r)
			p.noise_mul *= pow(0.7, r)
		"fortune":        p.double_drop_chance += 0.35
		_:
			push_error("Perks._apply_perk: no branch for perk id '%s'" % id)


## Damage reduction from the five armour slots, capped. The off-hand holds a
## light and protects nothing.
static func _apply_gear(p: PlayerSim) -> void:
	var dr := 0.0
	for slot in Config.ARMOR_SLOTS:
		var id: String = p.equip.get(slot, "")
		if not id.is_empty() and Config.GEAR.has(id):
			dr += float(Config.GEAR[id].dr)
	p.armor_dr = minf(p.armor_dr + dr, Config.MAX_GEAR_DR)


# ---------------------------------------------------------- what a point buys --

static func attr_cost() -> int:
	return 1


static func perk_cost() -> int:
	return 1


## Whether a rank can be bought, and if not, why. The reason is the message:
## "already at maximum" and "no skill points" are different problems and the
## character screen says which rather than just greying the row out.
static func can_raise_attr(p: PlayerSim, id: String) -> Dictionary:
	if not Config.ATTRS.has(id):
		return {"ok": false, "reason": "Unknown attribute"}
	if int(p.attrs.get(id, 0)) >= Config.ATTR_MAX:
		return {"ok": false, "reason": "Already at maximum"}
	if p.skill_points < attr_cost():
		return {"ok": false, "reason": "No skill points"}
	return {"ok": true, "reason": ""}


## `locked` distinguishes "you have not invested enough in the attribute" —
## which is a plan — from "you cannot afford it right now", which is a wait.
static func perk_status(p: PlayerSim, perk: Dictionary) -> Dictionary:
	var rank: int = int(p.perks.get(perk.id, 0))
	# A perk whose system has not been built yet is shown and refused. Taking
	# it out of the tree would hide what is coming; leaving it buyable would
	# charge a point for nothing.
	var needs: String = perk.get("needs", "")
	if not needs.is_empty():
		return {"ok": false, "reason": "Waiting on %s" % needs, "rank": rank, "locked": true}
	if rank >= int(perk.max):
		return {"ok": false, "reason": "Fully learned", "rank": rank, "locked": false}
	if int(p.attrs.get(perk.attr, 0)) < int(perk.req):
		var abbr: String = Config.ATTRS[perk.attr].abbr
		return {"ok": false, "reason": "Needs %s %d" % [abbr, int(perk.req)], "rank": rank, "locked": true}
	if p.skill_points < perk_cost():
		return {"ok": false, "reason": "No skill points", "rank": rank, "locked": false}
	return {"ok": true, "reason": "", "rank": rank, "locked": false}
