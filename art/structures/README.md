# Structure art

The build menu's picture of each buildable: `<id>.png`, named after the
structure's id in `data/structures.json` (`woodWall`, `chemStation`), case
included. It shows on the menu's cards, the detail panel and the placement
bar. Without a file the menu shows the piece's colour, as it always did.

Menu art only. How a piece looks standing in the street is `art/world/`. A
file named after no structure fails `tests/icons_test.gd`.

128×128, transparent, square. `tools/slice_icons.py` cut the current set;
`longBed.png` was cut from its street picture by `tools/slice_world.py`.
