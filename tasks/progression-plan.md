# The progression plan (owner, 2026-09-30)

**The full plan is in Notion:** DEADLINE → *Progression Map*
(page `3eb10d456b168109b2b9fb53380e759c`,
https://app.notion.com/p/3eb10d456b168109b2b9fb53380e759c). Read it before
proposing anything about progression, balance, recipes, benches, bosses or
the early game. This file is the pointer and a summary, so the shape survives
if nobody opens Notion. When the two disagree, Notion is right.

**Nothing in it is built.** Every number there is a first pass.

## The goal

Make the core loop fun through a progression where the next thing to do is
always obvious, always just out of reach but never tedious, and where
progress brings better gear, new areas, and chores that go away. Models:
Valheim, Core Keeper, Abiotic Factor. Anti-models: Vein and Project Zomboid
(stacked skill gates, fiddly chains).

## Decisions

- Five chapters, one per danger tier plus a finale, 15–25 hours.
- A boss in its own dungeon closes each chapter. Its drop upgrades the
  workbench (tiers I–V), and the item is never lost.
- One found and one made material per chapter; one refining step.
- Recipes arrive in waves of at most eight, each revealed by doing something
  from the wave before. A recipe can be pinned to the HUD. The next bench
  upgrade is always listed, locked, naming the boss item it needs.
- Crafted gear is the backbone; loot is the surprise.
- Levels, attributes and perks never gate a recipe or a bench.
- The start is strict: craft **and build** from the pack only, carry 100,
  torches burn out, weapons wear. Each chore is removed by an item the player
  crafts after a boss upgrades the bench.
- Death: keep worn gear and the hotbar; the pack drops.
- Raid ceiling and weapon level cap rise with the bench tier.
- Survivors recruit from chapter 1; jobs unlock with the bench.
- Each chapter adds a cosmetic decor set and a boss trophy.
- The ending: no cure. Beating Patient Zero lets you set your Mutation band.

| Ch | Find → make | Boss | Drop |
| --- | --- | --- | --- |
| 1 Roadside | Scrap → Cloth | The Butcher, a barn at Hollow Creek Farms (new) | Butcher's Saw |
| 2 Steel | Sheet Metal → Steel Bar (Forge) | The Coach, Pine Hollow High (built) | Master Breaker |
| 3 Power | Electronics → Circuits (Electronics Bench) | The Foreman, Dock Yard (new) | Foreman's Cutting Head |
| 4 Military | Military Hardware → Composite Plate | The Colonel, Checkpoint Delta (new) | Quarantine Clearance |
| 5 The Source | Neural Tissue → Stabilised Mutagen | Patient Zero, a lab under Downtown (new) | Zero's Spinal Fluid |

## What this changes in the existing design

- **Pillar 2** ("danger is the only gate") still holds for places. Crafting
  tiers are now gated by boss kills.
- **The shared stash gets a reach.** It answers §7's open question: the stash
  pays only from the pack at first, inside the base after the Storage Link,
  and from anywhere after the Field Radio.
- **`tasks/instanced-dungeons.md` §11** (School, Hospital, Mall, Prison) is
  superseded: the Prison is dropped; the Hospital and Mall are optional
  chapter 3 dungeons built after the main five.

## Build order

Each step is one PR that leaves the game playable.

- [ ] A. The strict start: craft and build from the pack, carry 100, keep gear on death
- [ ] B. Guidance: recipe waves, the pinned recipe, the locked upgrade row
- [ ] C. The ladder: bench tiers I–V, recipes moved, raid ceiling, level cap, job gates
- [ ] D. Steel: Hacksaw, wrecks, Sheet Metal, Forge, chapter 2 recipes, first chore items
- [ ] E. The Butcher and his barn — **playtest gate: chapters 1 and 2**
- [ ] F. Power: Electronics Bench, Circuits, Storage Link, Tactical set
- [ ] G. The Foreman
- [ ] H. Military: Cutting Torch, sealed crates, Composite Plate, Radio Beacon, Field Radio
- [ ] I. The Colonel
- [ ] J. The Source: the lab, Patient Zero, the Neural Regulator
- [ ] K. Side dungeons: the Hospital and the Mall

Re-tune the numbers for chapters 3 to 5 after A–E have been played, before
building F onward.
