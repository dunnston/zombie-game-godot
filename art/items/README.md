# Item art

Every item has an icon here: a PNG named after its id. Without one, an item
falls back to a coloured pip or crate on the ground and a coloured square in
the pack, so art can arrive (or be replaced) one item at a time, by dropping a
PNG in this folder. No code changes.

| File | Where it shows |
| --- | --- |
| `<id>.png` | The item's icon: pack slots, the hotbar, the drag ghost |
| `<id>_ground.png` | How it looks dropped in the street. Optional — without it the icon is used there too |

`<id>` is the item's id exactly as the content editor shows it (`pistol`,
`ammoP`, `scrap`, `bandage`), case included. A file named after nothing fails
`tests/icons_test.gd`, so a typo cannot quietly ship a picture no item uses.

Square images read best: art is fitted inside the slot without stretching.
The pack draws icons at about 34×25 px and the ground at 16×16, so design at
128×128 and let it scale — the art is drawn with mipmaps (`Items.ART_FILTER`),
so it shrinks cleanly.

Buildables are not items: their build-menu pictures live in `art/structures/`
under the same rules.

The current set was cut from twelve generated contact sheets by
`tools/slice_icons.py`, whose seed table records which picture is which id.

Open the project in the Godot editor once after adding files so they are
imported; the game also reads un-imported files while you iterate.
