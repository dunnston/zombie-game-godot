# Notion sync — Phase 6 content

**Read-only diff, 2026-09-09. Nothing has been written to Notion.**

Procedure is `PROJECT.md` §10. This is step 3: report before changing
anything. The direction is unusual — §10 is written for pulling *from*
Notion, and this is pushing the other way, because Phase 6 designed its
content in code first.

## What is there now

All three tables are exactly as seeded on 2026-09-09: 117 Item rows (75 in
game, 42 Planned — the weapon classes the owner enumerated), 5 Workbenches,
37 Loot Sources. **Not one row of Phase 6 content exists in Notion.**

## What would be added — Items, 16 rows

### Consumables misc — the suppressant chain (6)

| Name | Code ID | Stack / Wt | What it does | Made at | Recipe |
| --- | --- | --- | --- | --- | --- |
| Raw Brain Matter | `brainRaw` | 20 / 0.4 | −10 Mutation, Nausea 60s | — | found on a body |
| Mutated Brain Matter | `brainMut` | 20 / 0.4 | −20 Mutation, Nausea 90s | — | found on a Brute or Behemoth |
| Neural Tissue | `brainSpec` | 10 / 0.3 | Ingredient only — never eaten | — | found on a Behemoth |
| Stabilized Neural Serum | `serum` | 10 / 0.5 | −30 Mutation, no side effect | Basic (bench 1) | 3 Raw Brain Matter, 2 Medical, 1 Cloth · XP 10 |
| Refined Suppressant | `suppressant` | 10 / 0.6 | −50 Mutation, no side effect | **Chemistry Station** | 6 Raw Brain Matter, 1 Mutated Brain Matter, 4 Medical, 2 Electronics · XP 30 |
| Experimental Suppressant | `experimental` | 5 / 0.7 | −75 Mutation, Surge 90s, 25% Fever | **Chemistry Station** | 2 Mutated Brain Matter, 1 Neural Tissue, 6 Medical, 2 Military · XP 60 |

### Consumables food — buffs only, no hunger meter (9)

| Name | Code ID | Stack / Wt | Buff | Made at |
| --- | --- | --- | --- | --- |
| Candy Bar | `candyBar` | 20 / 0.2 | Wired 108s | found |
| Tinned Food | `cannedFood` | 15 / 0.6 | Fed 300s | found |
| Clean Water | `water` | 15 / 0.8 | Hydrated 300s | found |
| Warm Soda | `soda` | 15 / 0.7 | Wired 180s | found |
| Instant Coffee | `coffee` | 10 / 0.3 | Wired 288s | found |
| Dried Meat | `jerky` | 15 / 0.4 | Sated 300s | Basic · 4 Rations, 2 Fiber · yields 2 · XP 4 |
| Hot Meal | `hotMeal` | 5 / 0.9 | Steady 240s, heals 15 | Basic · 3 Rations, 1 Clean Water, 2 Wood · XP 6 |
| Field Ration | `mre` | 10 / 0.8 | Fed 600s, heals 10 | found |
| Bottle of Spirits | `booze` | 8 / 1.0 | Drunk 180s | found |

The six buffs, for the Notes column: **Fed** +10 max stamina and +20%
regen · **Sated** +12 max health and +10% melee · **Steady** −10% spread and
+5% gun damage · **Hydrated** −15% Mutation rate and +5% regen · **Wired**
+8% speed, +8% fire rate, +10% regen · **Drunk** +15% melee, −30% stagger,
+30% spread.

### Building — 1 row

| Name | Code ID | Build cost | HP | Notes |
| --- | --- | --- | --- | --- |
| Chemistry Station | `chemStation` | 30 Scrap, 20 Electronics, 4 Weapon Parts, 8 Medical | 260 | Tier 2. Refines brain matter. **Not a rung on the workbench ladder** — no workbench tier ever unlocks its recipes. |

## What would change — Loot Sources

**Two new rows**, `raiderBody` and `enforcerBody`: what a Raider and an
Enforcer are carrying when you put them down.

**Eight existing rows gain food in `Drops`** — Kitchen Unit (tinned food,
water, coffee, spirits), Refrigerator (water, dried meat, soda, tinned
food), Vending Machine (soda, candy, water), Military Crate (field rations,
water), Footlocker (field rations, spirits), Cabinet (tinned food, candy),
Car Trunk (water, candy), Supply Cabinet — hospital (water). Weights are feel
numbers and are not edited from Notion (§10); only the `Drops` links change.

## Three things that do not add up

These are questions for the owner, not coin tosses.

1. **The Chemistry Station is a sixth bench and the Workbenches table has
   five.** The five are a ladder — Player Menu, Basic, Advanced, Tech,
   Recycle — and the Chemistry Station is deliberately *not* on it: that is
   the whole design, and `bench` stays 0 on both its recipes. Does it become
   a sixth row (Order 5), or is chemistry meant to fold into **Tech** when the
   bench rework lands? **Recommendation: its own row.** A ladder position
   would be a lie about how it works.
2. **Loot Sources has no `Kind` for a body.** The three kinds are Container,
   Harvest and Vehicle. A raider's body is none of them.
   **Recommendation: add a fourth Kind, `Body`** — enemy drop tables are real
   loot sources and there is nowhere else for them.
3. **`Rations` is filed as food and behaves as a material.** The existing row
   is Consumables food with Code ID `rations (recipe: rationPack)`, but in the
   code `rations` is a `RES`: survivor upkeep, and now an ingredient in two
   recipes. It is not edible. **Recommendation: move it to Materials** and
   note that Consumables food is the nine new rows.

And one smaller thing: **the Items table has no column for a buff.** Weapons
have ten 1–5 ratings; food has a named effect and a duration. Until the owner
wants a column, these go in `Stats` (`Fed 300s: +10 max stamina, +20%
regen`) with the fuller description in `Notes`.

## What is deliberately not going in

The three human enemy types (`looter`, `raider`, `enforcer`) and the Mutation
tuning table. Notion owns *what exists, what it costs, where it is made and
where it is found* — enemies are none of those, and the meter's numbers are
feel, tuned by playing.
