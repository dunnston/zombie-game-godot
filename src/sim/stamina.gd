class_name Stamina
extends RefCounted
## The stamina bar, and the only thing allowed to write it.
##
## Stamina does not refuse you anything. It is spent by sprinting and by every
## melee or tool swing, and when it runs out you are **winded**: you keep
## swinging, keep harvesting and keep walking, you just swing slowly. Guns are
## outside the system entirely — firing costs nothing and is never slowed,
## because being tired should not spoil your aim. So are crop plots and things
## picked up off the ground: neither is swung at.
##
## Every write goes through here for the same reason every write to the
## Mutation meter goes through `Mutation.add` (invariant 9): `winded` reaches
## the stats through `recompute_stats` and nowhere else (invariant 4), so the
## flip has to be somewhere that can recompute — and a guest has to agree with
## the host about when it happened.
##
## The debuff is a **clock, not a lock**. Regen runs at the normal rate the
## moment you stop spending, so three seconds of standing still hands back a
## usable bar; swinging or sprinting while winded restarts the clock, so
## somebody who keeps working stays sluggish until they choose to stop.


## Spends `amount` and stops recovery for a beat. `lock` overrides that beat —
## a harvest swing rests longer than a punch. Bottoming out here is the only
## way to become winded, and spending while already winded restarts the clock:
## the way out is to stop, not to push through.
static func spend(p: PlayerSim, amount: float, lock := -1.0) -> void:
	p.stam = maxf(0.0, p.stam - amount)
	p.stam_lock = Config.PLAYER.stam_regen_delay if lock < 0.0 else lock
	if p.winded:
		p.winded_t = float(Config.WINDED.dur)
	elif p.stam <= 0.0:
		_set_winded(p, true)


## One step of recovery and of the debuff clock. Called from `move`, which a
## guest also runs to predict itself, so the countdown on its own HUD is right
## without the host shipping it.
static func tick(p: PlayerSim, dt: float) -> void:
	# An empty bar means winded however it got empty — spent, or a ceiling
	# that dropped out from under it. Only spending restarts the clock, so
	# sitting at zero still counts down.
	if p.stam <= 0.0 and not p.winded:
		_set_winded(p, true)
	p.stam_lock = maxf(0.0, p.stam_lock - dt)
	if p.stam_lock <= 0.0:
		p.stam = minf(p.max_stam, p.stam + p.stam_regen * dt)
	if p.winded:
		p.winded_t = maxf(0.0, p.winded_t - dt)
		if p.winded_t <= 0.0:
			_set_winded(p, false)


## What one swing of `w` costs. `stam` is the weapon's own — the per-weapon
## field the §10 Stamina Cost rating is waiting for — and falls back to the
## flat `PLAYER.stam_swing` until the Notion sync fills it in, which is why
## every caller asks here rather than reading a const.
static func swing_cost(p: PlayerSim, w: Dictionary) -> float:
	return float(w.get("stam", Config.PLAYER.stam_swing))


## What one harvest swing costs: the same swing, worked. Woodcraft discounts
## it, and it rests longer afterwards (`stam_chop_delay`).
static func chop_cost(p: PlayerSim, w: Dictionary) -> float:
	return swing_cost(p, w) * float(Config.PLAYER.stam_chop_mul) * p.chop_stam_mul


## A ceiling that just went up hands the difference over (`Progression`), and
## a bar restored from a save lands here rather than being set behind our back.
static func grant(p: PlayerSim, amount: float) -> void:
	p.stam = clampf(p.stam + amount, 0.0, p.max_stam)
	if p.stam > 0.0 and p.winded:
		p.winded_t = minf(p.winded_t, float(Config.WINDED.dur))


static func restore(p: PlayerSim, value: float) -> void:
	p.stam = clampf(value, 0.0, p.max_stam)
	_set_winded(p, p.stam <= 0.0)


## The dev menu's "refill", and what a fresh player starts on.
static func refill(p: PlayerSim) -> void:
	p.stam = p.max_stam
	p.stam_lock = 0.0
	_set_winded(p, false)


## The one edge. `winded` is read by `recompute_stats` like a mutation band, so
## flipping it without recomputing would leave the penalty on a player who is
## no longer tired — or off one who is.
static func _set_winded(p: PlayerSim, on: bool) -> void:
	if p.winded == on:
		return
	p.winded = on
	p.winded_t = float(Config.WINDED.dur) if on else 0.0
	Equipment.recompute_stats(p)
