# Structure art generation prompt — placeable buildings, world sprites

This is the world-sprite counterpart to `tasks/icon-generation-prompt.md`.
That one is for inventory icons; this one is for what a built piece actually
looks like sitting in the scene — the raised bed, the walls, the turret.

## Why this is still needed after the icon set landed

The icon pass is done: 124 item icons are in `art/items/`, and all 19
buildables have art in `art/structures/`. But that art is **build-menu
only** — `src/ui/build_bar.gd` loads it for the menu cards, and it was
generated as three-quarter/isometric icon art.

The world is untouched. `src/world/structure_view.gd` still draws every
placed piece as a hand-coded flat rectangle from its `COLORS` dict, exactly
as before. And the isometric menu art can't be reused there: a top-down game
needs sprites seen from directly above, or a placed wall looks like it's
lying on its side.

So this prompt is for a **second, separate set**: top-down world sprites.
They need their own folder — `art/structures/` is now the menu-icon folder —
so these should land in `art/world/<id>.png`.

## The grid constraint, up front

Everything placeable in this game is **exactly one tile: 32×32 pixels.**
Verified in the code, not assumed:

- `Config.TILE = 32` (`src/config.gd`).
- `Structures.grid` is keyed `ty * W + tx` — **one structure per tile**, and
  `can_place()` refuses any tile that already holds one. There are no
  multi-tile footprints anywhere in the game.
- A placed piece's `pos` is the tile *center*:
  `Vector2(tx*32 + 16, ty*32 + 16)`. Tile (tx,ty) covers pixels
  `[tx*32, tx*32+32)`.
- There is no y-sorting and no per-structure z-index, so a sprite that
  overhangs its tile would draw over its neighbours wrong. **Art must stay
  inside its 32×32 box.**

So "fits perfectly on the grid" means one rule: every sprite is a 32×32 PNG,
and nothing spills outside it.

---

## Style Bible (paste this first, by itself)

I need top-down world sprites for the buildable structures in DEADLINE, a
top-down 2D post-apocalyptic zombie survival game built in Godot. These are
not inventory icons — these are what the object looks like placed in the
world, seen from above.

**The single hardest requirement: each sprite is exactly 32×32 pixels.**
The game is a 32px tile grid and every buildable occupies exactly one tile.

**How to deliver that so it survives:** don't generate a small blurry image.
Design each sprite as a **32×32 pixel grid**, but render it large — 512×512,
where every one of the 32×32 logical pixels is a perfectly uniform,
axis-aligned 16×16 block of flat color. No anti-aliasing, no gradients
inside a block, no soft edges, no blur, no drop shadow. Done that way, the
image downsamples to a crisp 32×32 with no quality loss. If blocks are
misaligned or edges are feathered, the sprite turns to mush at real size and
is unusable.

**Style:** true pixel art. Limited palette per sprite (roughly 4–6 colors:
a base, a highlight, a shadow, an accent). Readable shapes over detail — at
32px there is room for a silhouette and about three details, nothing more.

**Camera:** straight top-down / orthographic overhead. **Not isometric, not
three-quarter.** You're looking straight down at the object from directly
above. A wall is a slab seen from above with a lit top edge, not a wall seen
from the side.

**The ground it sits on is dark and desaturated** — grass `#38472a`, road
`#2b2c2e`, sidewalk `#474742`, dirt `#463c2d`, gravel `#3e3d38`, concrete
lot `#313236`. Every structure must read clearly against that, so keep
structures lighter and higher-contrast than the ground. Each item below has
a hex color the game already uses for it — build the sprite's palette around
that hex as the base tone.

**Leave these OUT of the art — the game draws them in code on top:**
- Damage. Pieces are drawn at full health; the engine darkens the sprite as
  HP drops and flashes it white on hit. Don't bake in cracks or damage.
- Health bars, labels, text, numbers, status icons.
- Glow rings, light cones, power radius indicators.
- Drop shadows (there's a separate shadow layer).

**Background must be transparent.** For walls and other pieces meant to form
a continuous run, the art should fill the full 32×32 edge to edge so that
two side by side touch with no seam. For freestanding objects (turret,
generator, floodlight, bedroll) a transparent margin inside the tile is
fine and usually looks better.

**Output:** one image per sprite, and tell me the exact filename to save it
as — I'll give the filename with each item below.

Confirm you understand the 32×32 pixel-grid requirement and the top-down
camera, then I'll send Batch 1.

---

## Batch 1 — Walls & defenses (7 sprites)

These are the tiling-critical ones. The player builds these in long runs, so
each must fill the full 32×32 edge to edge, and the left edge must visually
continue into the right edge of an identical tile placed beside it (and the
same top-to-bottom). Think of each as a section of wall viewed from directly
above.

The five walls should form a clear progression from crude to heavy — right
now they're near-identical colored blocks, which is the exact problem I'm
fixing.

- `art/world/barricade.png` — Barricade — base `#8a6a3c` — rough scrap timber thrown
  together at angles, gaps visible, obviously the flimsiest of the set
- `art/world/woodWall.png` — Wood Wall — base `#a3763f` — neat horizontal wooden
  planks, solid and uniform
- `art/world/stoneWall.png` — Stone Wall — base `#8f8a80` — dry-stacked irregular grey
  stone blocks, no wood or metal anywhere
- `art/world/reinforcedWall.png` — Reinforced Wall — base `#9a8256` — wood planks with
  riveted sheet-metal plates bolted over them, visibly patched
- `art/world/metalWall.png` — Steel Wall — base `#9aa2ab` — heavy welded steel plate
  with rivets along the edges, the toughest-looking of the five
- `art/world/spike.png` — Spike Trap — base `#8a8078` — a bed of sharpened stakes
  pointing up out of the ground, seen from above (tips toward the viewer).
  Not solid — the player walks over it — so keep it low and ground-level
- `art/world/gate_closed.png` — Gate (closed) — base `#b08a5a` — a wooden gate barring
  the tile, with visible hinges and a cross-brace, clearly a door rather
  than a wall

## Batch 2 — Gate open state (1 sprite)

The gate is the only piece with two visual states; the game swaps between
them when the player opens it.

- `art/world/gate_open.png` — Gate (open) — base `#b08a5a` — the same gate swung open:
  two posts at the left and right edges of the tile with a clear walkable
  gap down the middle. The player physically walks through this gap, so the
  middle must read as open ground, not as a barrier

## Batch 3 — Storage & crafting (5 sprites)

Freestanding objects. These may have a small transparent margin inside the
32×32 so they read as objects standing on the ground rather than as floor.

- `art/world/stash.png` — Supply Stash — base `#a3763f` — a large wooden supply crate
  seen from above, lid boards visible, the biggest storage piece
- `art/world/chest.png` — Wooden Chest — base `#8a6a3c` — a smaller wooden chest from
  above, visibly smaller and simpler than the stash
- `art/world/locker.png` — Steel Locker — base `#9aa2ab` — a grey steel cabinet from
  above, metal not wood, with a vent or handle detail
- `art/world/workbench.png` — Workbench — base `#b08a5a` — a wooden work surface from
  above with a few tools scattered on it. Keep the upper-left area
  relatively clear — the game stamps a "II" marker there when it's upgraded
- `art/world/chemStation.png` — Chemistry Station — base `#7fd0c4` — a lab bench from
  above with beakers, tubing and a teal chemical glow to the glassware

## Batch 4 — Beds & the garden (3 sprites)

Two of these have strict layout requirements because the game draws things
into them.

- `art/world/bedroll.png` — Bedroll — base `#6f7a52` — a rolled-out sleeping bag /
  bedroll lying flat on the ground, seen from above, olive canvas
- `art/world/bunk.png` — Bunk — base `#6f7a52` — a simple wood-framed bunk bed from
  above: frame, mattress, pillow at one end
- `art/world/raisedBed.png` — Raised Bed — base frame `#5a4632` — **this one has a
  hard constraint.** It's a wooden garden box seen from above: draw only the
  wooden frame as a border around the outside of the tile, and leave the
  entire center as plain dark soil. The game draws the crop into that center
  itself — it tints the soil darker when watered and grows three shoots
  through four stages. So the middle must be empty, flat, unobstructed soil
  with nothing planted in it, and the wooden frame must not intrude into it.
  Draw the frame about 4–5 pixels thick around the edge

## Batch 5 — Powered & special (4 sprites)

All four of these have code-drawn elements on top. Read the note on each —
including something in the art that the game also draws will double up and
look broken.

- `art/world/watchtower.png` — Watchtower — base `#a3763f` — a wooden tower seen from
  directly above: you're looking down onto the platform, with the legs
  visible splaying out beneath at the corners. Resist drawing it from the
  side — it has to read as tall while staying in a flat top-down tile
- `art/world/turret.png` — Auto Turret — base `#5e6a72` — **draw the base only, with
  NO gun barrel.** The game draws the barrel as a separate rotating line
  that aims at targets. So: a mounted turret base/housing from above, with a
  clear center where a barrel would pivot from
- `art/world/floodlight.png` — Floodlight — base `#c9a227` — a floodlight fixture on a
  base, seen from above, lamp face pointing up at the viewer. Don't draw any
  light glow or beam — the game draws the lit radius itself
- `art/world/generator.png` — Generator — base `#71787f` — a small fuel generator unit
  from above: engine housing, a fuel cap, an exhaust stack. No exhaust smoke
  or running indicator — the game animates that

---

## Optional phase 2 — connected walls

Everything above gives one sprite per wall type, which is a big improvement
on the flat colored blocks the game draws today. If you later want wall runs
to properly join up — corners, T-junctions, ends — the project already has
the pattern for it: `src/world/tile_art.gd` generates neighbour-aware
terrain with a 4-bit mask (`fence_m0`…`fence_m15`, documented there as
"bit 1 left, 2 right, 4 up, 8 down", and `water_m0`…`water_m15`).

That would mean 16 variants per wall type instead of 1, so it's a much
bigger art job (80 sprites for five wall types). Worth doing only if plain
wall runs look wrong once the single-sprite version is in the game. Don't
start here.

---

## After you have the images

Send me the PNGs. They go in a new folder, `art/world/<id>.png` — keeping
them separate from `art/structures/`, which now holds the isometric
build-menu icons.

There is **no code path that loads world sprites yet**.
`src/world/structure_view.gd` draws every placed piece as a hand-coded
rectangle from its `COLORS` dict and has never been touched by the art work.
Wiring these up means:

- A loader in `structure_view.gd` that draws the sprite for a tile when one
  exists and falls back to the current colored rectangle when it doesn't, so
  the game stays playable while the set is incomplete.
- Keeping every code-drawn overlay working on top of the sprite: the damage
  darkening and white hit-flash (these become a modulate on the sprite), the
  health bar, the raised bed's soil tint and four-stage crop shoots, the
  turret's rotating barrel, the gate's open/closed swap, the powered rings on
  the floodlight and generator, the bedroll's active ring, and the "II" on an
  upgraded workbench.
- A test in the same spirit as `tests/icons_test.gd` — no file means the
  placeholder, a file is found by name, a misnamed file is caught.
