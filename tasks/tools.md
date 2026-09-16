# Tools: what they are now, and a plan for better ones

From the *Multiplayer Playing* playtest (2026-09-15): *"tools — generate more
robust tools — devise plan for more efficient tools etc — higher yield — is
there overlap between weapons (yes)"*. This is the plan, not the build. The
numbers in §3 are proposals for the owner to accept, change or refuse.

## 1. What is actually in the game

Every tool **is a weapon**: one row in `WEAPONS`, carried in the hotbar,
swung by the same `melee_attack`. What makes it a tool is three fields:

- `axe` / `pick` / `scythe` — a flag saying it is allowed to work a kind of
  scenery at all (`HARVEST.needs`, or `boost` for a job you can do by hand).
- `chop_mul` — how fast it gets through what it is working on.
- `noise` — how far the work is heard, which is what stops the best tool
  being free.

| Tool | Tier | dmg | cd | chop_mul | dur | noise | Works |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Stone Knife | 1 | 19 | 0.36 | 1.5 | 600 | 22 | — |
| Hatchet | 1 | 30 | 0.52 | 2.4 | 600 | 60 | trees |
| Stone Pickaxe | 1 | 26 | 0.62 | 2.2 | 600 | 85 | boulders |
| Camping Axe | 1 | 32 | 0.50 | 3.0 | 480 | 65 | trees |
| Scythe | 2 | 24 | 0.46 | 2.0 | 600 | 55 | thickets |
| Fire Axe | 2 | 34 | 0.46 | 4.2 | 420 | 80 | trees |
| Steel Pickaxe | 2 | 36 | 0.56 | 4.4 | 420 | 95 | boulders |
| Splitting Axe | 2 | 40 | 0.62 | 5.0 | 460 | 90 | trees |
| Double-Bit Axe | 3 | 52 | 0.54 | 5.5 | 520 | 95 | trees |
| Chainsaw | 3 | 26 | 0.25 | 8.0 | 220 | **520** | trees |

**What a better tool buys you today is speed and nothing else.** The yield is
the *rule's*, not the tool's: `HARVEST.wood` pays 6–11 wood whether you are
holding a Hatchet or a Chainsaw. The only multiplier on the payout is
`loot_mul`, which is the player's (Scrounger, and the Mutation band).

## 2. The overlap with weapons — the owner is right, and it is mostly fine

There is no separate tool slot, no tool durability system, no tool-only
damage: a Splitting Axe is a 40-damage weapon that also fells trees, and a
Machete is a 40-damage weapon that does not. The overlap is **deliberate** and
it fits pillar 1 (no survival chores) and the six-slot hotbar: carrying a
dedicated woodcutting item you cannot fight with would be a chore.

What is *not* fine is that the overlap is currently **free**. The Splitting
Axe is a better weapon than the Machete *and* a tool. The tiers only ever
climb: nothing about the best tool costs you anything except noise, and noise
is invisible until a horde arrives.

**The fix is a trade, not a split.** Three levers already exist:

1. **Noise** — already per weapon, already read by the sim, and the Chainsaw
   proves it can be the whole cost of a tool (520px is a phone call to the
   district).
2. **Stamina cost** — `stam` per weapon, already read by `Stamina.swing_cost`,
   and blank on every row (it falls back to 2.0). A heavy tool that costs
   real puff is a decision to use it rather than a strict upgrade.
3. **Durability** — already per weapon (`dur`), and already the reason a
   Chainsaw is not simply the answer (220 uses).

## 3. The proposal

### 3a. Yield belongs to the tool (this is the owner's "higher yield")

Add `harvest_mul` to a `WEAPONS` row — a multiplier on what the roll pays,
beside `chop_mul`, which is only how fast the swing gets through it.

```
per-swing wood  = HARVEST.wood roll × loot_mul × w.harvest_mul
time to a tree  = prop hp ÷ (dmg × chop_mul × chop_mul_player)
```

Proposed values — deliberately much flatter than `chop_mul`, so a better tool
is mostly *faster* and only a little *richer*:

| Tool | chop_mul (today) | harvest_mul (new) |
| --- | --- | --- |
| Hatchet, Stone Pickaxe | 2.2–2.4 | **1.0** |
| Camping Axe | 3.0 | **1.0** |
| Fire Axe, Steel Pickaxe, Splitting Axe | 4.2–5.0 | **1.15** |
| Double-Bit Axe | 5.5 | **1.25** |
| Chainsaw | 8.0 | **1.0** — it is speed, and it is loud |
| By hand / wrong tool | 1.0 | **0.6** |

A tier-2 tool is then worth about **twice the trees an hour** and **15% more
wood a tree**; the Chainsaw is four times the trees and no better paid, which
keeps it a decision rather than an endgame.

### 3b. The heavy tools cost puff

Fill in `stam` on the tool rows (the field exists, nothing reads a default but
the 2.0 fallback). Proposed: Hatchet 2.0 · Camping Axe 2.5 · Fire Axe 3.5 ·
Splitting Axe 4.0 · Double-Bit Axe 4.5 · Chainsaw 1.0 (it is the engine
working, not you) · Sledge 6.0. `stam_chop_mul` (3.0) still multiplies it, so
a Splitting Axe swing is 12 stamina of work against the Hatchet's 6 — with
about half as many swings needed. **Net: the same bar for the same tree, and
a much shorter job.**

### 3c. A tool bench tier, not a tool slot

The Notion Workbenches plan already has Basic / Advanced / Tech. Tools land
naturally: stone tools by hand, steel at Advanced, the Chainsaw at Tech with
Fuel as an upkeep. No new system, no new slot.

### 3d. What this leaves alone

- No tool-only slot, no tool belt: the hotbar is the answer, and Sleight of
  Hand (2026-09-15) now grows it to eight.
- No separate tool durability: `dur` and the bench that mends it already work.
- No "tools cannot fight": that is the overlap the owner spotted, and it is
  the right one to keep. It is paid for in noise, stamina and durability.

## 4. What it would take

| Piece | Where | Size |
| --- | --- | --- |
| `harvest_mul` on a weapon row | `data/weapons.json` fields + `Loot.roll_harvest` | small |
| The new numbers | the editor (`tools\edit`) and Notion's Items table | content |
| `stam` on the tool rows | content, already read | content |
| "Wrong tool" 0.6 | `Combat.chop_prop`, where `needs` is already checked | small |
| The panel saying so | the item detail: "WOOD +15% · 4.2× faster" | small |
| Tests | a tier-1 vs tier-2 harvest, measured through a real swing | small |

**One PR, mostly content.** The code is `harvest_mul` and one multiplication.

## 5. Questions for the owner

1. Is **15–25%** the right size for a better tool's yield, or should the tier
   jump be bigger (say 1.5× at tier 3) and the speed jump smaller?
2. Should working with the **wrong tool** (a pipe on a bush) pay 0.6, or
   should it stay at 1.0 and remain purely slower?
3. The **Chainsaw**: speed only, as proposed — or speed *and* yield, and let
   the noise be the whole cost?
4. Do you want a **fourth tool kind** (a shovel for the farm plots, a crowbar
   for locked things) or is three enough?
