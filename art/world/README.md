# Street art

How each buildable looks once it is built, seen from above: `<id>.png`,
named after the structure's id in `data/structures.json`, case included.
The build menu's icons are `art/structures/`, and are a separate picture.

| File | What it is |
| --- | --- |
| `<id>.png` | The piece, fitted to its tiles without stretching. A piece longer than it is wide is drawn lying flat, and turned with it |
| `gate_open.png` | A gate standing open. Without it an open gate is drawn in code, never as a shut one |
| `turret_head.png` | The turret's head, square and centred on the point it turns about, drawn over `turret.png` and turned to its aim |

Without a file the street draws the piece in code, as it always did, so a
picture can arrive or be replaced one piece at a time. Whatever the piece is
doing — damage, a crop, power, a turret's aim — is drawn over the picture.
Any other file name fails `tests/icons_test.gd`; the states a piece may have
are `Structures.WORLD_STATES`.

Draw the piece to fill its tiles: a wall has to reach the edge of its tile to
meet the next one. Transparent background. The pictures are drawn with
mipmaps, like the icons, so 128px on the long side shrinks cleanly.

The current set was cut from the owner's `building/` sheets by
`tools/slice_world.py`, whose seed table records which picture is which id.
