# The Target Range

A developer's instance for testing every weapon: how it **sounds**, what it
**deals**, and what the things it is pointed at **deal back**. Notion card
DL-109 on *Ideas & Roadmap*. Decided with the owner on 2026-09-29.

## The owner's decisions

- **Reached from F1**, never from the town. The dev menu only exists in a
  debug build or under `--dev`, and the host refuses a guest's range command
  without it (`Actions.dev`).
- **Co-op: every control works for a guest**, not just the host. Each one goes
  through `Actions.range_control`, which a guest sends to the host.
- **No enemy armor.** Enemies keep HP and knockback resistance.
- **Baseline build inside**: level 1, no perks, the Mutation meter clear. It
  applies only inside; your real build comes back when you leave. (May be
  revisited.)
- **Weapons at level 1** in the lockers, with a control that moves the held
  weapon's level between 1 and `UPGRADE.max`.
- **Wear is a switch**, off by default, so you can see how fast a weapon
  wears out when you want to.
- **Stationary targets**: one of each enemy type (bosses left out for now),
  at their real HP, that do not attack. Distance markers every 5 tiles.
- **Live rooms**: enemies that attack, one type per room, three each, behind
  unbreakable walls nothing shoots over or through. A leash stops them just
  inside the doorway, so they never follow you out.
- **Mutation stays on** inside: bites still raise it. It is put back as it was
  when you leave, with the rest of your build.
- **Dying keeps you in the range**: you get up at the entrance with what you
  had.
- **Leaving gives back the pack you walked in with**, at the spot a new game
  starts. Nothing from the range comes out.
- Chests of armor and gear, and meds and food, as well as every weapon and
  every ammunition.
- A **damage panel**: floating numbers per hit, a per-target readout (last hit,
  total, DPS, time to kill) and a log of damage taken (source, raw, after
  armor).
- Targets respawn 3s after dying, plus a reset-all control; a refill control
  for the live rooms. The party goes in together. Nothing is saved inside.
  The lane is longer than a sound carries (`SFX_RANGE`, 1500px).

One call made in building it, not by the owner: you go in **empty-handed**.
Your pack is held with your build and handed back on the way out, so your
own upgraded gear cannot skew the baseline's numbers.

## Three PRs

**A — the map, the lockers, going in and out** (`target-range`).
`Config.INSTANCES.range` has no `shell`, so the town stamp and the save's
fingerprint check skip it and the town is untouched. `World._gen_range` lays
out the hall, the lane and six rooms with one doorway each, and refuses every
blow to a wall in there (`damage_wall`). `TargetRange` holds each seat's build
and pack on the way in (in the save's own keys, so a save from inside merges
it straight over the player), furnishes six lockers on fixed tiles on the host
and on a guest's mirror alike, stocks them, respawns the dead at the entrance,
spends no weapon uses unless the switch is on, and gives everything back on
the way out. Finds go to the pack: the haul is closed in there
(`Instance.haul_open`). Protocol 11.

**B — targets and live rooms** (`target-range-b`). A `passive` flag on `EnemySim` (no step, no
swing, no alert, no knockback; stagger and bleed still land and show), each
target's post and its 3s respawn; a `leash` rectangle held at the end of every
step; the distance markers; *Reset targets* and *Refill live rooms* through
`Actions.range_control`. Built as planned, plus: kills in the range drop
nothing and pay no XP (the baseline would drift off level 1), and the range's
walls are not a thing to hit, so a leashed enemy never thumps one.

**C — the damage panel.** A view of floating numbers off the `hit` event (bleed
ticks summed every half second); a range-only panel with the per-target
readout and the damage-taken log. The `hit` event gains the enemy's `id`,
`player_hit` the damage before armor.
