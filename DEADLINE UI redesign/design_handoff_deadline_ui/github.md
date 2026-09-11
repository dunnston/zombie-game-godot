repo: dunnston/zombie-game-godot
branch: main

## Last sync

date: 2026-09-11T13:54:01Z

### Updated in this project

- Read the in-code UI (HUD, build bar, inventory/craft/char/crew, map, menu screens) and lifted exact colors and sizes.
- Built a Godot-ready style sheet: color tokens, type scale, spacing, radius/border rules, components in four states.
- Built twelve 1920x1080 mockups from real `data/*.json` values.
- Crafting and Building share one layout: category rail, card grid, detail panel; Building collapses to a slim placement bar.

## Screen map

| Project screen | Repo files it was built from |
| --- | --- |
| Style Sheet.dc.html | src/ui/hud.gd, src/ui/build_bar.gd, src/ui/inventory_screen.gd, src/ui/dev_screen.gd |
| Crafting.dc.html | src/ui/inventory_screen.gd (`_draw_craft`), src/sim/crafting.gd, data/recipes.json, data/res.json, data/weapons.json, data/categories.json |
| Build.dc.html | src/ui/build_bar.gd, src/sim/structures.gd refs, data/structures.json, data/categories.json |
| HUD.dc.html | src/ui/hud.gd, src/ui/map_screen.gd, src/core/bindings.gd |
| Inventory.dc.html | src/ui/inventory_screen.gd (`_cells`, `_draw_cell`, `_draw_tooltip`, `_buttons`), data/gear.json, data/res.json, data/containers.json |
| Workbench.dc.html | src/ui/inventory_screen.gd (bench mode, `_craft_rows`), src/sim/crafting.gd, data/recipes.json, data/res.json |
| Character.dc.html | src/config.gd (ATTR_IDS, ATTRS, PERKS), src/sim/perks.gd, src/ui/inventory_screen.gd (`_draw_char`) |
| Crew.dc.html | src/sim/survivors.gd, src/ui/inventory_screen.gd (`_draw_crew`), data/structures.json |
| Map.dc.html | src/ui/map_screen.gd |
| Title.dc.html | src/ui/menu_screen.gd (Page.TITLE, Page.LOAD), src/sim/saves.gd refs |
| Pause and Settings.dc.html | src/ui/menu_screen.gd (Page.PAUSE, Page.CONTROLS), src/core/bindings.gd |

## Open questions for the owner

- `Config.BENCH_UPGRADE_COST` was not read — the Workbench upgrade button carries a placeholder label.
- `Config.JOBS` names/colors were inferred from job ids in `survivors.gd` (guard, scavenger, builder, sniper).
- Structure repair pricing is not shown: `Structures.repair_cost` is the missing health fraction x full cost x `Config.BUILD.repair_cost_share`, and that share value was not read.
- Perk effect lines were derived from `Perks._apply_perk`, not from the `desc` strings in `config.gd`.
