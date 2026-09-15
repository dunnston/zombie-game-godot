# Structure art

The build menu's picture of each buildable: `<id>.png`, named after the
structure's id in `data/structures.json` (`woodWall`, `chemStation`), case
included. It shows on the menu's cards, the detail panel and the placement
bar. Without a file the menu shows the piece's colour, as it always did.

Menu art only. The street draws a built piece in code, top-down, because it
shows what the piece is doing — damage, an open gate, a turret's aim, a crop's
growth — and a three-quarter picture cannot. A file named after no structure
fails `tests/icons_test.gd`.

128×128, transparent, square. `tools/slice_icons.py` cut the current set.
