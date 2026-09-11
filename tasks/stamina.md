# Stamina — one PR (`stamina`)

Branch off an up-to-date `origin/main`, PR into `main`.

Stamina stops being a thing that **refuses** you and becomes a thing that
**slows** you. Nothing in the game says "no" for want of puff any more: you
still swing, still harvest, still move — you just do it sluggishly until you
have stood still long enough to get your breath back.

## The model (owner, 2026-09-11)

- Stamina is spent by **sprinting** and by **every melee or tool swing**. A
  swing that hits nothing still costs.
- **Guns are outside the system.** Firing costs no stamina and is not slowed
  by being winded. Being tired does not spoil your aim.
- **Crops and ground pickups are outside it too.** Harvesting a crop plot or
  picking an item off the ground costs nothing and is never penalised — both
  go through `interact`/`Loot`, not a swing. Wood and stone are swung at, so
  they slow down on their own.
- At zero you are **winded**. Binary — a condition, not a slope.
- Winded's penalty is **sluggishness, not weakness**: melee and tool swings
  take longer, and look like they take longer. Damage per hit, yield per
  tree, and every drop table are untouched. **No yield modifier exists
  anywhere in this system** (owner, explicit).
- **Regen runs normally throughout**, the moment you stop spending — the
  ordinary `stam_regen_delay` (0.65s) is the only gap. Being winded does not
  block recovery; it only makes you slow while it lasts.
- The debuff lasts `WINDED.dur` (3.0s to start). **Swinging or sprinting
  while winded restarts that timer**, so someone who keeps working stays
  sluggish. Stopping is the only way out.
- When it ends the bar returns to its normal colour and keeps filling at
  whatever rate the player's stats and gear allow.
- Max stamina and regen are moved by consumables, levels and perks — which is
  already true (see "Already built").

### Why the timer needs no floor

An earlier draft blocked regen for the 3s, which meant the debuff ended on an
empty bar and the next swing re-wound you instantly — one swing every three
seconds, flickering. Regen running during the debuff removes that: three
uninterrupted seconds now returns roughly 47 stamina (0.65s delay, then
2.35s at 20/s), so the player always comes out of it with something to spend.

## Already built — no work, only content

Max stamina and regen already move with food, levels, perks and bands:

| Source | Effect | Where |
|---|---|---|
| Fed | +10 max, x1.2 regen | `config.gd:601` |
| Surge | x1.3 regen | `config.gd:585` |
| Nausea | x0.8 regen | `config.gd:577` |
| Fever | x0.85 max | `config.gd:594` |
| CON rank | +10 max, +1.2 regen | `perks.gd:98-102` |
| Marathon | +45 max, +5 regen per rank | `perks.gd:149-150` |
| Turning / Feral | +15 / +25 max | `config.gd:549,559` |

Woodcraft (`chop_stam_mul`, `perks.gd:151`) still discounts harvest swings.

## Mechanism

**Winded is a mods band, like a mutation band.** `recompute_stats` is the only
source of stat modifiers (invariant 4) and `_apply_mods` already eats any
`{"add", "mul"}` dict, so winded becomes a `Config.WINDED` entry applied when
the flag is set. Tuning it is then a `Config` edit, not a code change.

```
WINDED := {
    "dur": 3.0,      # debuff seconds; any swing or sprint restarts it
    "mul": {"swing_rate_mul": 1.6},   # swings take 60% longer
}
```

`swing_rate_mul` is a new field in `Config.STAT_BASE` (`config.gd:358-362`),
1.0 everywhere else. It multiplies:

- `player_sim.gd:601` — `attack_cd = w.cd` becomes `w.cd * p.swing_rate_mul`.
  Melee does not currently read `fire_rate_mul` at all; guns do, at `:614`,
  and are deliberately left on that path untouched.
- `combat.gd:217` — `swing.dur = minf(0.26, w.cd * 0.75)`. Both the cap and
  the term scale, or the swing snaps at normal speed and only the *gap*
  grows, which reads as lag rather than fatigue.

**`Stamina` is the only writer** (the `Mutation.add` precedent, invariant 9).
Today eight places write `stam`/`winded` directly: `player_sim.gd:684,691,
697-700,745`, `combat.gd:221,238`, `progression.gd:94`, `save_game.gd:313`,
`dev_screen.gd:188-190`. The module owns spend, regen, the debuff clock and
its edges, and calling `recompute_stats` on each edge — `recompute_stats` is
not per-tick, so the flip is where it has to happen. `protocol.gd:645`
already recomputes after every snapshot, so a guest picks the penalty up from
`PF_WINDED` for free.

**Swing costs.** Cost is decided by what the swing did: a prop costs
`stam_chop` (x `chop_stam_mul`), everything else — a fight, a whiff — costs
`stam_swing`. Work stays the expensive one.

## UI

- The stamina meter turns **red** while winded and returns to `Ui.ACCENT_HI`
  when the debuff ends (`hud.gd:426`, currently grey `#8a8a7a`).
- **Which red:** `Ui.DANGER` (`#c8423a`) is the health bar's own colour
  (`hud.gd:234`) and the two meters sit adjacent, so a DANGER stamina bar
  reads as a second health bar. Use `Ui.SHORT` (`#c96a5a`, "a condition
  unmet") — semantically right and distinguishable. If the owner wants a
  harder red on the walk, add a dedicated token to `ui.gd` rather than
  reusing DANGER.
- Keep the "— winded" label, and count the debuff down beside it.

## What this overturns

Each needs a `PROJECT.md` decision-log entry, not just a code change.

1. **Harvest refusal dies.** `Combat.can_chop` (`:150`), `swing_refused`
   (`:186`), the refusal branch and the "Winded — get your breath back before
   working again" notify (`:205-215`). The thesis at `config.gd:55-59` — "IS
   refused when the bar is short, which is what makes three trees a decision"
   — is replaced: three trees is still a decision, but the cost is time.
2. **The sprint floor dies.** `player_sim.gd:681` gates sprint on
   `stam > 1.0`, which is precisely why sprinting cannot wind you today.
   Becomes `> 0.0`. Overturns the logged decision at `PROJECT.md:1516`
   ("Sprinting alone never winds you", ported as found, flagged for the
   owner's walk) — this is the walk.
3. **Winded gets one owner.** `move` latches it *and* `combat.gd:210` sets it
   on a refused harvest. After this the bar decides, and only the bar.
4. **Hysteresis is replaced by a clock.** `stam_winded_recovery` (clear at
   half the bar) goes; the debuff ends on its own timer instead.

## Build order

- [ ] 1. `src/sim/stamina.gd` — the single writer: `spend`, `regen`, the
      debuff clock and its edges, `recompute_stats` on each flip. Route the
      eight existing writers through it.
- [ ] 2. `Config.WINDED` + `swing_rate_mul` in `STAT_BASE`; apply in
      `Perks.recompute_stats` beside the band and effect mods.
- [ ] 3. Swing rate: `player_sim.gd:601` and the animation at `combat.gd:217`.
- [ ] 4. Sprint drains to zero; drop the floor.
- [ ] 5. Every swing costs; delete the refusal path entirely.
- [ ] 6. HUD: the red bar, the label, the countdown.
- [ ] 7. Tests, then `PROJECT.md` (the four overturns above) and this file's
      review section.

## Tests

47 stamina assertions across six files. The ones that assert the old thesis
and must be rewritten rather than patched:

- `player_test.gd:75 test_sprint_hovers_above_empty` — asserts the floor by
  name. Becomes "sprinting to zero winds you".
- `player_test.gd:87 test_winded_latch_clears_at_half` — becomes the timer.
- `combat_test.gd` — 11 assertions, most on refusal. Become: every swing
  costs, a whiff costs, a winded swing is slower and yields the same.
- `dash_test.gd:150,156` — the dash still refuses when winded or short. That
  contract is untouched (`PROJECT.md:1610`).

New: a winded swing takes `swing_rate_mul` x longer and deals identical
damage; a winded harvest drops exactly what an unwinded one drops; a swing
while winded restarts the clock; regen runs during the debuff; firing a gun
costs nothing and is not slowed; a guest mirrors the penalty from `PF_WINDED`.

## Balance notes (not for this PR)

At 110 max and `stam_swing` 2.0, that is 55 swings before winded — almost
certainly too many once every swing costs. Sprint drain 26/s gives ~4.2s of
running from full, which is about right. Three seconds of rest returns ~47
stamina, so the debuff is currently generous at both ends. Expect to raise
swing cost and lower the bar rather than touch regen. All of it is
`config.gd:51-63`.
