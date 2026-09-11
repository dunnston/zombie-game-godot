# UI redesign — one PR (`ui-redesign`)

Source: `DEADLINE UI redesign/design_handoff_deadline_ui/` (README + 11 `.dc.html`
mockups at 1920×1080). High fidelity: tokens, type, spacing, borders and states
are exact. Branch off an up-to-date `origin/main`, PR into `main`.

## Hard requirements

- **Nothing ever goes off screen, at any window size or aspect** (owner,
  2026-09-11). Design resolution becomes the mockups' 1920×1080 with
  `canvas_items` + `expand`: the logical viewport is then never smaller than
  1920×1080 in either axis, so a layout that fits 1920×1080 fits everywhere,
  and every screen lays out from the live viewport so wider/taller windows
  get the extra room rather than bars. Proved by a test, not by eye.
- Everything the current UI shows is preserved. Every state change still goes
  through `Actions` (invariant 8). Every number comes from `Config`/`data`
  (invariant 5). Refusal strings are the sim's own, verbatim.
- `_cells()` / `_craft_rows()` / `_char_rows()` / `_crew_rows()` / `_rows()` /
  `_buttons()` stay the single source of what is drawn and what is clickable.
- No transition over ~120ms; hover never resizes (borders grow inward).

## Owner's decisions (2026-09-11)

- Fonts downloaded from google/fonts on GitHub (OFL, licences beside them).
- **Control nodes**, not immediate-mode drawing. Screens are real
  containers, buttons and line edits. Their scripts build them, because every
  screen is data-driven and the tests construct them with `.new(sim)`. The
  Theme is built at boot from `src/ui/ui.gd`, which is the one file to edit
  for any colour, face, size or border. The rect-list lookups the smoke run
  uses (`cell_centre`, `recipe_centre`, `button_centre`…) now read the nodes'
  own global rects, so the smoke clicks real controls.
- Settings: only what exists, plus a real Fullscreen/Windowed toggle.
- With a full-screen menu open, WASD still walks and the arrow keys navigate.
  Typing into a search field walks nowhere and fires no screen key.
- Nothing off screen: design resolution 1920×1080 (window opens at 1280×720),
  `canvas_items` + `expand`, every column that can grow is a scroll area, and
  a label told to expand trims rather than widening its container (every
  other label keeps its natural width — see the review). Checked at every
  smoke checkpoint; a headless test cannot lay out containers before the
  first frame (probed), so the check lives in the smoke run.

## Plan

- [x] 0. Branch; `project.godot` viewport 1920×1080 (close the editor first — §8).
      Camera zoom already derives from `vp.y / view_height`, so the world
      frames the same.
- [x] 1. Fonts in `art/fonts/` with their OFL licences: Oswald 500/600,
      Barlow 400/500/600, IBM Plex Mono 400/500. `FontVariation`s carry the
      tracking, so no node sets it.
- [x] 2. `src/ui/ui.gd` — the kit. Colour tokens, type scale, the four-state
      `StyleBoxFlat` sets (`anti_aliasing = false`, equal content margins), and
      one draw function per component: panel (+header), tab, primary button,
      secondary button / chip, item slot (art via `Items.art_rect`, mono count,
      condition sliver on `Config.WEAR`), list row, tooltip, progress bar with
      band ticks, badge, requirement line, keycap hint, stepper. Plus a
      `Theme` built from the same tokens for any real `Control`.
- [x] 3. Shared chrome: 64px top bar (wordmark, Pack / Craft / Character /
      Crew / Map tabs, readouts, close keycap from `KeyBinds`), optional 60px
      sub-bar (title, context chip, search, filter, count), 24px body, 44px
      footer of key hints. Rails 272, detail 460, gaps 20.
- [x] 4. Pack: worn column (six slots with name + DR, armour total, EQUIP
      BEST), 30-slot grid, hotbar row, item detail panel, click menu, tooltip;
      the haul beside it inside an instance.
- [x] 5. Container (stash / chest / boot): container grid + DEPOSIT ALL /
      TAKE SUPPLIES (+ REFUEL on a boot), your pack, the pantry readout.
      Raised Bed, instance door and walk-out panels in the same chrome.
- [x] 6. Crafting (C): category rail derived from what a recipe makes
      (Weapons, Tools, Clothing/Armor, Ammo, Medical, Food, Consumables,
      Materials, Special, Misc), bench group, On hand; 5-across card grid
      with CAN CRAFT / SHORT N / bench strip; detail panel (stats from
      `weapons.json`, have/need rows, requirement line, ×N stepper, CRAFT).
      Search `/`, can-make-now `F`, Tab category, Enter craft, Shift+Enter ×5.
- [x] 7. Workbench (E at a bench/station): tier pips + UPGRADE with the real
      `BENCH_UPGRADE_COST`; MEND rows, UPGRADE rows with rank pips or the
      refusal; the bench's recipes on the rail; mend detail panel.
- [x] 8. Character (K): level/XP/derived stats sub-bar, six attributes,
      the selected tree's perks with rank pips and Buy / Fully learned / the
      requirement. Select-then-spend unchanged.
- [x] 9. Crew: caps sub-bar (Charisma vs bunks, both shown), roster rows,
      selected survivor detail, four job cards with their preconditions,
      pantry footer.
- [x] 10. Build (B): the full menu in the Crafting layout (rail derived from
      structure fields, cards with HP and THREAT, detail + PLACE) and the slim
      placement bar above the hotbar with `Structures.can_place`'s reason.
- [x] 11. HUD: location + danger diamonds, raid banner + wave bar, threat /
      clock / light card, notices with state bars, bars block with teammate
      slivers and effect chips, 74×66 hotbar, carry, heal/suppress lines,
      interact prompt, 260px minimap with net and debug lines.
- [x] 12. Map (M): full page in the chrome with the real ground texture,
      districts, markers and raid ring; legend, you-are-here, district list.
- [x] 13. Title with the save-slot panel; Pause (720px over a 72% scrim);
      Settings with a page rail and the binds grouped Move/Fight/Use/Screens
      as `KeyBinds.ACTIONS` orders them, awaiting/conflict/changed states;
      New game / Load / Multiplayer / Host / Join in the same chrome.
- [x] 14. Dev menu onto the tokens (light touch; debug only).
- [ ] 15. ~~Tests: `ui_layout_test.gd` at several logical sizes~~ — **not
      possible as planned**: a headless `-s` run cannot lay containers out
      before the first frame (probed: every size came back zero). Replaced by
      `smoke_offscreen()`, asked at every smoke checkpoint, which fails the
      run if any visible Control reaches past the window. Existing UI tests
      kept green.
- [x] 16. Smoke: the hard-coded clicks gone (DEPOSIT ALL, the craft rows, the
      build bar, the CREW tab all through real controls), a build-menu
      checkpoint, the off-screen check everywhere; PNGs compared to the
      mockups. **Run at 1280×720 only** — the multi-size run was declined in
      this session; `PROJECT.md` §9 has the line to run it at any size.
- [x] 17. `tools/test --all`, PROJECT.md (§3, §4, §6, §8, §11), lessons, PR.

## Open questions from the handoff, answered from the repo

1. `Config.BENCH_UPGRADE_COST` = scrap 55, elec 20, parts 5 — shown on the button.
2. `Config.JOBS` has real names, colours and descs — used as is.
3. `Config.BUILD.repair_cost_share` = 0.45 — repair pricing stays off the
   detail panel as designed; the REPAIR tool's cursor line keeps its bill.
4. Perk lines use the `desc` strings in `config.gd`.

## Review

**What landed.** Every screen the handoff draws, as Control nodes on one
theme: `ui.gd` (tokens, faces, text styles, boxes, the Theme, builders),
`chrome.gd` (the frame), `ui_screen.gd` (sections and section-owned
refreshers), `kit/` (slot, meter, pips, swatch), and the HUD, pack (nine
modes), craft/bench, character, crew, build, map, title/pause/settings
screens on top. Design resolution 1920×1080; `LocalInput` gives the arrows to
an open screen and walks nowhere while typing; `main._goto` routes the tabs.

**What was measured.**
- `tools\test` 703 tests / 13600 asserts, `--all` 739 / 13748, zero
  failures. The UI tests that construct screens with `.new(sim)` pass
  unchanged in intent (`use_verb`, `recipes()` at a station, `card_info`,
  `_revealed`, the dev catalogue).
- Smoke 89 checkpoints, zero failures, **every checkpoint asserting that no
  visible Control reaches past the window** (1280×720 window, 1920×1080
  logical). The new screens are reached through real clicks: a build card
  and PLACE, a recipe card then CRAFT (and a check that the card alone does
  not craft), MEND, the CREW tab, DEPOSIT ALL.
- A headless probe (`process_frame`, then a walk of the tree) at a square
  window — 1920×1920 logical — found nothing off screen either.

**Found by looking at the pictures, not by the assertions** (all fixed):
every non-expanding label collapsed to nothing (trimming everywhere); rail
rows a few pixels tall and job cards 230px tall (a face button that copied
its content's early minimum and then only grew); a refresher registered
inside a rebuilt section kept writing to freed nodes (the smoke log); C
opening on UPGRADE because upgrade rows exist by hand; menu rows with no
padding; bills stacked into a column in the bench rows. And one the smoke
caught by clicking: the first fix for the button sizes overrode
`_get_minimum_size`, which a Button never asks — every composed button fell
back to its bare box and a click on Constitution landed on another row.

**What was not.** The smoke at other window sizes (the multi-size run was
declined in-session — `PROJECT.md` §9 has the command). Keyboard navigation
is exercised only by its code paths, not by a smoke leg. Nobody has played
it: the play gate is in `tasks/todo.md`, and three behaviours moved on
purpose (a card selects, B opens the menu, full screens are opaque).

**Deliberately left.** The dev menu (F1) is still drawn by hand — a debug
list, restyled onto the tokens. The Settings page has only what exists plus
Fullscreen, per the owner. District names on the full map clip at their
rectangle where districts are dense.
