class_name DamageLog
extends RefCounted
## What the Target Range's damage panel says (`RangePanel`), worked out from
## the events and kept apart from the drawing so it can be tested.
##
## Only one seat's hits — the player at this screen (owner, 2026-09-29: "own
## hits only"). Both halves count in **sessions**: hits keep adding up until
## `RANGE.session_gap` seconds pass without one, and the next hit starts a
## fresh count. Dealt and taken each have their own clock, so being bitten
## does not reset the numbers for the gun you are testing.
##
## Time is whatever the caller passes as `now`, in seconds.

## Blows landing at the same moment on the same body are one hit: a shotgun's
## pellets, or a melee arc that caught it once. Two events closer than this.
const SAME_HIT := 0.001

var seat := 0

## One row per body hit this session, in the order first hit:
## {id, type, hits, total, first, first_t, last, last_t, hp, max, bleed, ttk}.
## `ttk` is seconds from the first hit to the one that put it down, or -1.
var dealt: Array[Dictionary] = []
var dealt_last_t := -INF
## Every hit taken this session, oldest first: {label, raw, dmg, t}.
var taken: Array[Dictionary] = []
var taken_last_t := -INF


func clear() -> void:
	dealt.clear()
	taken.clear()
	dealt_last_t = -INF
	taken_last_t = -INF


func feed(ev: Dictionary, now: float) -> void:
	if int(ev.get("seat", -1)) != seat:
		return
	match String(ev.t):
		"dealt":
			_dealt(ev, now)
		"player_hit":
			_taken(ev, now)


func _gap() -> float:
	return float(Config.RANGE.session_gap)


func _dealt(ev: Dictionary, now: float) -> void:
	if now - dealt_last_t > _gap():
		dealt.clear()
	dealt_last_t = now
	var id := int(ev.id)
	var row := {}
	for r in dealt:
		if int(r.id) == id:
			row = r
	var dmg := float(ev.dmg)
	if row.is_empty():
		row = {"id": id, "type": String(ev.type), "hits": 0, "total": 0.0, "first": 0.0, "first_t": now,
			"last": 0.0, "last_t": -INF, "hp": 0.0, "max": float(ev.max), "bleed": 0.0, "ttk": -1.0}
		dealt.append(row)
	row.total = float(row.total) + dmg
	if String(ev.kind) == "bleed":
		row.bleed = float(row.bleed) + dmg
	elif now - float(row.last_t) < SAME_HIT:
		row.last = float(row.last) + dmg
		if int(row.hits) == 1:
			row.first = row.last
	else:
		row.hits = int(row.hits) + 1
		row.last = dmg
		row.last_t = now
		if int(row.hits) == 1:
			row.first = dmg
			row.first_t = now
	row.hp = float(ev.hp)
	if float(ev.hp) <= 0.0 and float(row.ttk) < 0.0:
		row.ttk = now - float(row.first_t)


## Sustained damage per second on a body: everything after the first hit over
## the time since it. The first hit cannot count — no time had passed to earn
## it — so one hit has no DPS yet, and reads as -1.
static func dps(row: Dictionary, now: float) -> float:
	var end := now
	if float(row.ttk) >= 0.0:
		end = float(row.first_t) + float(row.ttk)
	var span := end - float(row.first_t)
	if span <= 0.05 or (int(row.hits) < 2 and float(row.bleed) <= 0.0):
		return -1.0
	return (float(row.total) - float(row.first)) / span


func _taken(ev: Dictionary, now: float) -> void:
	if now - taken_last_t > _gap():
		taken.clear()
	taken_last_t = now
	var dmg := float(ev.dmg)
	taken.append({"label": String(ev.get("label", "")), "raw": float(ev.get("raw", dmg)), "dmg": dmg, "t": now})


## The taken session summed: {hits, raw, dmg}.
func taken_totals() -> Dictionary:
	var raw := 0.0
	var dmg := 0.0
	for h in taken:
		raw += float(h.raw)
		dmg += float(h.dmg)
	return {"hits": taken.size(), "raw": raw, "dmg": dmg}
