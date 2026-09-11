# Handoff: DEADLINE UI redesign

## Overview

A full UI redesign for **DEADLINE**, a top-down 2D zombie survival game with online co-op, built in **Godot 4.7.2** (`dunnston/zombie-game-godot`, branch `main`). The redesign covers every screen the game has today: HUD, Crafting, Building (menu plus placement mode), Inventory, Container/storage, Workbench, Character, Crew, Map, Title with save slots, Settings and Pause.

The goal was a modern AAA survival look (The Last of Us / The Division / DayZ) that is consistent everywhere, readable before decorative, and **rebuildable in Godot**: flat colors, 1–2px borders, 0–3px corners, simple vertical gradients, 9-slice panels, free (OFL) fonts. No backdrop blur, no per-pixel effects, no drop shadows.

Everything the current UI shows is preserved. What changed is how it looks and how it is organized. The current UI is drawn immediate-mode in GDScript (`_draw` with `draw_rect` / `draw_string`); the redesign is intended to become a real **Godot `Theme` resource plus `Control` scenes**.

## About the design files

The `.dc.html` files in this bundle are **design references created in HTML** — prototypes showing the intended look, layout and states. They are not production code and nothing in them should be ported literally.

The task is to **recreate these designs in Godot 4.7.2**, using the project's existing structure:

- Build a `Theme` resource (`StyleBoxFlat` sets, `FontFile` entries, per-type overrides) from §"Design tokens" below.
- Replace the immediate-mode `_draw` screens in `src/ui/` with `Control` scenes that use that theme, keeping the existing logic seams intact: `_cells()` / `_craft_rows()` / `_rows()` remain the single source of what is drawn and what is clickable, and every state-changing action still goes through `Actions` (invariant 8).
- All content stays in `data/*.json` read through `Config` (invariant 5). Every number in the mockups came from those files; none of it should be hardcoded in the UI.

Each HTML file needs `support.js` (included) beside it to render. Open them in a browser at 1920×1080 or wider.

## Fidelity

**High-fidelity.** Colors, type sizes, spacing, border widths and component states are final and exact — take the values from this README (or read them off the `Style Sheet.dc.html` file). Recreate them precisely.

Three exceptions, all flat placeholders, all to be replaced with real content:

- **Item icons** — neutral colored swatches using each item's `color` field from `data/*.json` (the current `Items.color_of` scheme). Real art arrives per-item as `art/items/<id>.png` per `art/items/README.md`; the slot component must fit art inside the swatch box without stretching, exactly as `Items.art_rect` already does.
- **World render** — the HUD, Build placement and Pause frames show a flat block-and-road stand-in for the game world, labelled as such.
- **Title art** and the **map ground image** — likewise placeholders. The real map ground is the existing 320×320 one-pixel-per-tile `ImageTexture` from `MapScreen._ground()`.

## Fonts

All three are OFL and should ship with the game as `FontFile` resources.

| Role | Family | Weights used |
| --- | --- | --- |
| Display — screen titles, item names, button labels | **Oswald** | 500, 600 |
| UI — body copy, list rows, labels | **Barlow** | 400, 500, 600 |
| Numeric — counts, have/need, timers, keycaps | **IBM Plex Mono** | 400, 500 |

Rules: display and label text is uppercase with positive tracking; body copy is never uppercased. Numbers are always mono so `41 / 24` and `3 / 5` align in a column. Set tracking on Theme font variations, not per-node. Nothing below **12px**.

## Design tokens

Authored at **1920×1080, scale 1.0**. The game's viewport is 1280×720 with `canvas_items` stretch, so these sizes are what the UI should be authored at inside a 1080p design resolution.

### Color

| Token | Hex | Use |
| --- | --- | --- |
| ink/void | `#0B0D10` | Screen dim, progress-bar tracks |
| ink/base | `#101318` | Sub-bars, footers, tooltips |
| panel | `#14161A` | Panel body (unchanged from the current build) |
| panel/raised | `#1B1F26` | Panel headers, cards, inputs |
| panel/hover | `#242A32` | Hover, active tab |
| panel/selected | `#2B3340` | Selected row or card |
| line/soft | `#2A3038` | Dividers, disabled borders |
| line/default | `#3A4048` | Every normal border |
| line/strong | `#5A6470` | Hover border, tooltip edge |
| text/high | `#EBE6D6` | Titles, primary values |
| text/body | `#C7C2B4` | Body copy, list rows |
| text/dim | `#8A8F84` | Labels, secondary |
| text/off | `#6A6F68` | Disabled, locked |
| accent | `#C9A227` | Primary action, selection |
| accent/hi | `#E0C24A` | Hover, focus ring |
| accent/press | `#A8861C` | Pressed |
| state/ok | `#9FD07A` | Can craft, requirement met |
| state/short | `#C96A5A` | Missing materials, refusal |
| state/danger | `#C8423A` | Health, damage, demolish |
| state/locked | `#8A949E` | Gated on a bench or tool |
| xp | `#9FD0FF` | Level and XP only |
| mutation | `#B06AD0` | Mutation meter, chemistry |

Semantic colour is the only colour with meaning: amber = the action you can take, green = a condition met, coral = a condition unmet, steel = gated elsewhere.

Material swatches keep their existing ids from `data/res.json` and must not be re-picked: Scrap `#9AA2AB`, Wood `#A3763F`, Sticks `#8A6A3C`, Stone `#8F8A80`, Fiber `#9AAE5A`, Cloth `#C2A98A`, Electronics `#59B8C4`, Medical `#D9575F`, Weapon Parts `#C9A227`, Military `#7FA14A`, Fuel `#D2762C`, Rations `#C4A86A`, Precision `#9FD0FF`. Weapon and gear swatches come from `data/weapons.json` / `data/gear.json` the same way.

### Type scale

| px | Family / weight | Tracking | Use |
| --- | --- | --- | --- |
| 34 | Oswald 600, caps | +0.06em | Screen title |
| 26 | Oswald 600, caps | +0.05em | Panel title |
| 20 | Oswald 500, caps | +0.08em | Section head |
| 17 | Oswald 500, caps | +0.03em | Item name |
| 15 | Barlow 400/500 | — | Body copy, list rows (line-height 1.45) |
| 13 | Barlow 400 | — | Small copy, hints |
| 12 | Barlow 600, caps | +0.10–0.12em | Labels |
| 22 / 20 | IBM Plex Mono 500 | — | Big stat values, quantity |
| 15 / 14 / 13 / 12 | IBM Plex Mono 500 | — | Counts, have/need, keycaps |

### Spacing, corners, borders

- Spacing base 4: **4, 8, 12, 16, 20, 24, 32, 48**. Screen margins 24. Panel padding 20–24. Grid gaps 20. Row gaps 8. Card inner padding 13–14.
- Corners, three values only: **0** meters and tracks, **2** slots / buttons / chips / tabs, **3** panels and cards.
- Borders: **1px `#2A3038`** disabled and dividers, **1px `#3A4048`** normal, **1px `#5A6470`** hover, **2px `#E0C24A`** selected or keyboard-focused. Selection grows the border inward — the box size is identical across states so nothing shifts on hover.

### Godot theme notes

- Each component is four `StyleBoxFlat` resources (`normal` / `hover` / `pressed` / `disabled`) differing only in `bg_color`, `border_color` and `border_width_*`. Set `anti_aliasing = false` so 1px borders stay 1px, and keep `content_margin_*` equal across all four.
- Selection and keyboard focus share one look (2px `#E0C24A`); give grids a `focus` stylebox identical to `selected` so arrow-key browsing and mouse selection never stack two highlights.
- Where a panel should read as metal or card, swap the flat box for a `StyleBoxTexture` 9-slice with 6px margins and the same border colour painted into the edge. Depth comes from the three panel greys and the border ladder — never from shadows.

## Components (every state)

`Style Sheet.dc.html` shows each of these in normal / hover / selected / disabled.

- **Panel** — body `#14161A`, header `#1B1F26`, border 1px `#3A4048`, radius 3. Over a live game the scrim is `#0B0D10` at 72%; over nothing it is opaque (this matches `MenuScreen._draw`).
- **Tab** — 40 tall (64 in the top bar). Normal `#181B20` / text `#8A8F84`; hover `#1F242B` / `#C7C2B4`; selected `#242A32` / `#EBE6D6` with a 2px `#C9A227` marker on the inner edge; disabled `#14161A` / `#565B56`.
- **Primary button** — 56 tall, `#C9A227` fill, 1px `#E0C24A`, label Oswald 600 / 22 caps in `#14161A` ink, keycap hint in mono at 70% ink. Hover `#E0C24A`, pressed `#A8861C`, disabled `#2A3038` with `#6A6F68` label and the refusal reason beside it in coral. One per panel.
- **Secondary button / filter chip** — 40 tall, `#1B1F26` + 1px `#3A4048`, label Barlow 600 / 13 / +0.1em caps. Selected gains a 1px `#C9A227` border and a filled 14px tick.
- **Item slot** — 56×56, grid gap 4, radius 2. Swatch inset 6px (5px when the 2px selected border is on, so the box never moves), count bottom-right in mono 12 on the swatch, condition sliver 3px along the bottom (green `#9FD07A` / amber `#D9C46A` / coral `#C96A5A`, thresholds from `Config.WEAR`). Empty slot `#171A1F` + 1px `#2A3038`.
- **List row** — 40 tall (44 where it is a mouse target). Transparent normal, `#242A32` + 1px `#3A4048` hover, `#2B3340` + 1px `#C9A227` selected, 45% opacity disabled. Text Barlow 500 / 15, trailing number mono 13.
- **Tooltip** — max width 320, `#101318`, 1px `#5A6470`, radius 3, padding 12/14. Title Oswald 17 caps, kind label Barlow 600 / 12 caps, rule `#2A3038`, stat rows label/value, flavour last in `#8A8F84`. Refusal variant: coral heading, one sentence.
- **Progress bar** — track `#0B0D10` + 1px `#2A3038`, radius 0. Heights 14 (status), 8 (secondary), 4 (sliver). Band ticks 1px white at 35%. Fill colours: HP `#C8423A`, stamina `#E0C24A` (grey `#8A8A7A` when winded), mutation = the band's own colour, XP `#9FD0FF`, weight `#8A8F84` → `#D9C46A` over 85% → `#C96A5A` overloaded.
- **Badge** — Barlow 600 / 12 / +0.09em caps, padding 3×8, radius 2, fill = state colour at ~14%, border = state at ~55%. Variants: can craft, short N, workbench II, bench tier, chemistry, disabled, and a mono `L4` weapon-level chip.
- **Requirement line (have/need)** — 40 tall, 18px material swatch, name Barlow 500 / 15, count always mono `have / need`. Met: green count + `✓` on `#1B1F26`. Short: coral count + `✕` on a coral-tinted row (`#1A1518` + 1px `#3A2A2C`). The bench/tool requirement uses the same row with a tick, the requirement name, and a right-aligned mono status (`STANDING AT ONE`, `NOT CARRIED`).

## Screens

Common chrome on every full-screen panel: a 64px top bar (wordmark, screen tabs Pack / Craft / Character / Crew / Map, right-hand readouts, close keycap), an optional 60px sub-bar (screen title, context chip, search, filter, count), a 24px-padded body, and a 44px footer of keyboard hints. Search is `/`, the "can make now" filter is `F`, Tab moves category, Enter commits, Shift+Enter does ×5.

### Crafting — `Crafting.dc.html`
The important one. Three columns.

- **Left rail, 272px** — Categories (Weapons 16, Tools 6, Clothing/Armor 8, Ammo 4, Medical 3, Food 5, Consumables 3, Materials 3, Special 0, Misc 0 — the owner's categories from `data/categories.json`), a Bench group (By hand 6 / Workbench 31 / Workbench II 8 / Chemistry Station 3 — note the station is a separate gate, not a rung of the ladder), and an "On hand" materials readout at the bottom.
- **Centre** — a 5-across card grid, gap 20, cards 174 tall. Card: 56px icon tile, name Oswald 500 / 17 caps, class line, cost chips (swatch + mono count), then a 26px status strip: green `CAN CRAFT`, coral `SHORT N <material>`, or steel `WORKBENCH II`. Locked and short cards drop to the dim palette (`#16191E` / `#13151A` bodies, `#2A3038` borders, 45% swatches) and locked cards show cost as one mono line rather than chips.
- **Right panel, 460px** — 96px icon, name, class line, state badges; description; a 3×2 stat grid from `data/weapons.json` (damage, swing `cd`, reach, bleed, crit, durability); the materials list as have/need rows; the requirement line; then the action block: quantity stepper (44/56/44) and the primary CRAFT button, with `+N XP` and the max quantity beneath.
- Refusal strings must come from `Crafting.status()` verbatim — `Needs a Workbench`, `Needs Workbench II`, `Needs a <station>`, `Needs a <tool>`, `No room for it`, `Too heavy to carry`, `Missing materials`, `Nothing can be made in here`.

### Building — `Build.dc.html` (two frames)
Frame 1 is the same three-column layout as Crafting, so the two screens are learned once: rail (Walls 6, Storage 3, Defence 4, Power 1, Living 3, Crafting stations 2, plus the Repair / Repair all / Demolish tools from `build_bar.gd`'s `TOOLS`), card grid (cost chips + `NNN HP`, status strip, `THREAT +N` on the right), detail panel (health / threat / solid stats, materials, requirement, **PLACE** button).

Frame 2 is **placement mode**: choosing a piece collapses the menu to a slim bar centred above the hotbar so the player can see the street. The bar carries, left to right: 44px icon + piece name + position in the category (`4 of 6`), the cost chips and HP, a wide blocked-reason cell (coral `✕`, `CANNOT PLACE HERE`, and the reason from `Structures.can_place` — e.g. "Something is already there"), and the key hints (LMB place, wheel change piece, Tab full menu, B leave). The world shows a tile grid under the cursor with a green valid ghost and a coral blocked ghost. Repair is the one tool that may be held and swept; placement and demolition stay one click, one action.

### HUD — `HUD.dc.html`
Location and danger diamonds top-centre; raid banner under it with a wave progress bar; threat meter + day/clock/phase + light fuel top-right; notices mid-left with a 4px state bar per line; HP / stamina / mutation (with band ticks and band name) / XP bars bottom-left with teammate slivers above and effect chips; hotbar of six 74×66 slots bottom-centre with selected slot at 2px accent, per-slot number, name, ammo `7 / 48` or `x2` or `BROKEN`, and the condition sliver; carry weight left of the hotbar; heal and suppressant key lines right of it; interact prompt above; minimap 260×260 bottom-right with the `M — MAP` hint, net line and debug line above it. Every key shown comes from `KeyBinds.primary_label` — never a hardcoded letter.

### Inventory and Container — `Inventory.dc.html` (two frames)
Frame 1 **Pack**: worn column (six labelled slots head/body/hands/legs/feet/off-hand with name + DR, armour total in the header, EQUIP BEST button), the 30-slot pack grid (10 across at this width), the hotbar row, an item detail panel, the click menu (EAT / DROP), and the tooltip. Frame 2 **Container**: the container grid on the left (Supply Stash, 48 slots, count in the header, DEPOSIT ALL MATERIALS / TAKE SUPPLIES footer), the player pack on the right, and the pantry readout — rations and 9mm in the stash, since the crew eats and shoots out of that pile and never out of your pack.

### Workbench — `Workbench.dc.html`
Bench context in the top bar (tier pips) with the upgrade action, then Mend rows (icon, name, condition % and bar, cost chips, MEND button) and Upgrade rows (level `n → n+1`, six rank pips, cost, or a coral refusal such as `NEEDS PRECISION PARTS`), with the rail listing Mend / Upgrade and the bench's recipe categories. Right panel details the selected mend: condition now vs after, materials, and the "mended at the bench that made it" requirement. The verb is **MEND** for gear and **REPAIR** for structures — two different jobs never share one word.

### Character — `Character.dc.html`
Level, XP bar, derived stats and points-to-spend in the sub-bar. Left: the six attributes from `Config.ATTRS` — abbr + rank in mono in the attribute's own colour (STR `#D9765A`, PER `#6FB0C4`, CON `#7EC46A`, CHA `#C48FD0`, INT `#D0C46A`, LCK `#D0A05A`), name, `per_rank` line, `blurb` underneath, and `SPEND A POINT` / the refusal on the selected row. Right: the selected attribute's perk tree — name, `rank / max`, rank pips, the effect per rank, the requirement (`NEEDS STR 5`), and a Buy / Fully learned / locked action. Clicking an attribute you are not looking at selects it; clicking the one you are looking at spends a point — one click never does both.

### Crew — `Crew.dc.html`
Roster rows (initials tile, name, level and XP, HP bar with `HUNGRY` / `DOWN` states, current job badge) plus an un-recruited survivor row carrying its refusal (`Every bunk is taken`). Sub-bar shows both caps independently — Charisma "will follow you" against bunks built — because being told "no room" without which limit is binding is useless. Right: selected survivor detail (damage, range, containers worked, ammo spent, XP, haul carried) and the four jobs as cards — Scavenger, Guard, Builder, Sniper — each with what it does and its precondition (`NEEDS A SUPPLY STASH`, `4 PIECES DAMAGED`, `1 TOWER FREE`). Footer: the pantry, and the reminder that a job they cannot reach is given up rather than leaned on.

### Map — `Map.dc.html`
Full-bleed square map with the district rectangles, names and `DANGER ▲` tiers for discovered districts and `? ? ?` for the rest, markers for structures / packs / crew / players / enemies / raid (pulsing ring), a legend panel, a "you are here" panel and a district list. The map is a readout, not a tool: nothing is clickable, so it never takes the mouse away from the gun.

### Title — `Title.dc.html`
Wordmark at Oswald 600 / 96 / +0.2em with the tagline, the menu column (CONTINUE with the save summary, NEW GAME, LOAD GAME, MULTIPLAYER, CONTROLS, SOUND, QUIT), and the save slots panel — three slots with name, summary line, timestamp and DELETE, the empty slot dashed. Disabled rows keep their note (`No saved game`, `Every slot is full`). Esc does nothing here, on purpose.

### Pause and Settings — `Pause and Settings.dc.html` (two frames)
Pause is a 720px panel over a 72% scrim: RESUME, SAVE (slot and last-written note), the hosting row with the connected guests and room code, CONTROLS, SOUND, SAVE AND QUIT TO TITLE. Settings is the full-screen version with a page rail (Controls / Sound / Display / Multiplayer), the 26 rebindable actions grouped Move / Fight / Use / Screens exactly as `KeyBinds.ACTIONS` orders them, a row awaiting a key (`press a key…` in `#FFE08A` with a 2px accent border), a conflict row (coral border, key in coral, `also <action>` beneath), a `changed` marker, the fixed keys panel (mouse buttons and Esc), and RESET TO DEFAULTS / BACK.

## Interactions and behaviour

- **Keyboard and mouse parity.** Arrow keys move the grid selection, Tab cycles category, Enter commits the panel's primary action, Shift+Enter is ×5, `/` focuses search, `F` toggles the "can make now" filter, Esc backs out one level. Keyboard focus and selection are the same visual state.
- **Refusals are shown, never silent.** Every disabled action carries the reason string from the sim (`Crafting.status`, `Structures.can_place`, `Perks.perk_status`, `Survivors.recruit_refusal`, `KeyBinds.conflicts_for`). "Needs STR 5" is a plan; "no skill points" is a wait; they must not both render as grey.
- **No transitions longer than ~120ms**, and no animation on state colour — a survival HUD that fades is a HUD you misread. The only moving things are the raid ring pulse and the mutation tint breath that already exist in `hud.gd`.
- **Hover never resizes.** Borders change colour and width inward only.
- Screens that belong to a thing in the world (container, bed, bench, instance door) still close themselves when the player walks away, per `InventoryScreen.tick()`.

## State

No new state. The mockups render existing sim state: `PlayerSim` (bag, hotbar, equip, attrs, perks, mag, effects, mutation, xp), `sim.structs`, `sim.stash`, `sim.crew`, `sim.threat`, `sim.clock`, `sim.raid`, `sim.instance`, `Saves`, `KeyBinds`. UI-local state is the same handful the current screens keep: selected category, selected item, search text, filter flag, scroll offset, quantity.

## Assets

No new assets. Fonts come from Google Fonts (Oswald, Barlow, IBM Plex Mono — all OFL). Item icons are the existing `art/items/<id>.png` pipeline; everything without art falls back to the colour swatch. The map ground is the existing generated `ImageTexture`.

## Files

| File | Screen |
| --- | --- |
| `Style Sheet.dc.html` | Tokens, type scale, spacing, and every component in four states |
| `Crafting.dc.html` | Crafting |
| `Build.dc.html` | Build menu + slim placement bar |
| `HUD.dc.html` | In-game HUD |
| `Inventory.dc.html` | Pack + container/storage |
| `Workbench.dc.html` | Workbench (mend, upgrade, tier) |
| `Character.dc.html` | Attributes and perks |
| `Crew.dc.html` | Survivors and jobs |
| `Map.dc.html` | Town map |
| `Title.dc.html` | Title screen with save slots |
| `Pause and Settings.dc.html` | Pause + settings/controls |
| `support.js` | Runtime the HTML files need to render — keep it beside them |
| `github.md` | Source association, screen → repo file map, and the open questions below |

## Open questions to resolve in code

Three values were not read out of the repo and are marked as placeholders in the mockups. Read them and substitute the real numbers rather than the labels:

1. `Config.BENCH_UPGRADE_COST` — the Workbench upgrade button carries a placeholder label instead of the cost.
2. `Config.JOBS` — job display names and colours were inferred from the job ids in `survivors.gd` (guard, scavenger, builder, sniper).
3. `Config.BUILD.repair_cost_share` — structure repair pricing is deliberately absent from the Build detail panel. `Structures.repair_cost` is missing-health fraction × full cost × that share.

Also worth confirming: perk effect lines in `Character.dc.html` were derived from the arithmetic in `Perks._apply_perk`, not from the `desc` strings in `config.gd`. Use the `desc` strings if they read better.
