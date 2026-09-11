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
- Movement is untouched beyond losing sprint: no walk-speed penalty.
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

## Balance review (2026-09-11)

Measured against the live tables, not estimated. Start player: 110 max,
21.2 regen, 26/s sprint drain, `stam_swing` 2.0, `stam_chop` 6.0.

**Sprint is the best-tuned number in the system: 4.2s from full.** Leave it.

**Combat already participates — an earlier note in this file was wrong.**
Ten walkers (58hp) costs 60 stamina with a pipe, 55% of the bar. The "55
swings before winded" figure ignored that a kill takes several swings and a
fight has several enemies.

### What a flat per-swing cost actually does

| | 10 walkers | % of bar | | tree (470hp) | stam | trees/bar |
|---|---|---|---|---|---|---|
| pipe | 60 | 55% | | axe | 36 | 3.1 |
| machete | 40 | 36% | | fireaxe | 24 | 4.6 |
| sledge | 20 | **18%** | | doubleBitAxe | 12 | **9.2** |

**A flat cost makes the heaviest weapon the most stamina-efficient one.** A
sledge clears that fight for a third of what a pipe costs, because cost is
per swing and it swings once per kill. Tools do the same: a doubleBitAxe fells
a tree for a third of an axe's stamina. The player's reward for upgrading is
paid twice — faster *and* cheaper — which is what erases the system.

Stone does not participate at all: one pick swing, 6 stamina, 18 rocks a bar.

### Fix: cost belongs to the weapon, not to `PLAYER`

Replace the flat `stam_swing` / `stam_chop` consts with a per-weapon `stam`
field in `data/weapons.json`; a harvest swing costs `stam x 1.5`. This is
also the fix for the last open item in §10 (`tasks/todo.md:1944`,
`PROJECT.md:2202`): **Stamina Cost is a 1-5 design-intent column that already
exists in Notion and has never had a per-weapon field behind it.** Per
CLAUDE.md, Notion owns what a thing costs — so the values come from that
column, mapped 1-5 onto a number. The formula below is only a seed for rows
Notion has not rated, and a sanity check on the mapping.

Seed: `stam = 1.0 + dmg x 0.09`.

| weapon | dmg | stam/swing | 10 walkers | % of bar |
|---|---|---|---|---|
| knife | 19 | 2.7 | 81 | 74% |
| pipe | 24 | 3.2 | 96 | 87% |
| machete | 40 | 4.6 | 92 | 84% |
| sledge | 92 | 9.3 | 93 | 85% |

A fight now costs roughly the same whatever you swing; the flat 1.0 is what a
light weapon pays for swinging more often, so it stays slightly the endurance
choice. Tool progression narrows from 3.0x to 2.2x (axe 33 stam/tree,
doubleBitAxe 17).

### Base stamina: leave it at 100 (110 at start)

With costs roughly doubled, a ten-walker fight is 85% of an early bar. That
is tight, and tight is the point — a new player should feel it. Raising the
base would undo the change we just made.

### The progression plan

Ceiling today: CON 2->10 (+80), Marathon x3 (+135), Fed (+10) = **325 max,
53.5 regen — 3.0x the bar and 2.5x the recovery.** The plan is that this is
allowed to happen, because of what it does and does not erase:

| | early (110) | late (325) |
|---|---|---|
| tree | 3.3 per bar | 19 per bar |
| walker | 9% of bar | 2.9% |
| behemoth (1100hp) | — | 31% |
| coach (1400hp) | — | 40% |

**Work graduates out of stamina; fighting never does.** Enemy HP scales 58 ->
1400 (24x) while the bar scales 3x, so a late-game player stops thinking
about stamina to chop wood — pillar 1, survival without survival chores — and
starts thinking about it again the moment something big turns up. That is
pillar 6 as well: getting stronger makes the world more dangerous, and the
bar is one of the places you feel it.

Two dials if the walk disagrees:

- **Marathon is the whole ceiling.** +45 max per rank x3 is more than CON
  gives across eight ranks. Dropping it to +25 puts the ceiling at 265
  (2.4x) without touching anything else.
- **`WINDED.dur`** is the real difficulty knob, not the bar. Three seconds is
  generous; the sluggishness only bites if the clock outlasts the fight.

### Not in this PR

Per-weapon `stam` is a Notion sync (PROJECT.md §10) and its own card, because
it touches 40+ content rows. This PR ships the mechanic with the flat consts
so the feel can be walked, and the per-weapon pass follows. What this PR must
not do is bake the flat cost in anywhere a weapon field cannot later replace:
`Stamina.swing_cost(p, w)` from day one, reading `w.get("stam", …)`.
