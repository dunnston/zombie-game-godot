"""Cut the owner's building sheets into the street's pictures of each piece.

`art/structures/` is the build menu's icon of a piece; this is how the piece
looks standing in the street, top-down: `art/world/<id>.png`, plus a picture
per state where a piece has one (`gate_open`) and the turret's head, which
the street turns to the turret's aim.

The sheets arrived in `building/` (not in the repo): two contact sheets with
a black caption under each picture, a turret head on its own and the long
raised bed on its own. Captions are the only short things on a sheet — every
picture is taller than 70px, every line of text shorter than 40 — so they
are dropped by height before `slice_icons.cut` gives each picture to its
seed. Unlike an icon, a picture is cropped tight and keeps its shape: a wall
has to reach the edge of its tile to meet the next one.

    conda activate deadline-art      (python, pillow, numpy, scipy)
    python tools/slice_world.py path/to/building
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as nd

from slice_icons import ROOT, SOLID, SIZE, cut, square, table_ids

CAPTION_H = 40      # px; anything on a sheet shorter than this is text

SHEETS = {
    "ChatGPT Image Sep 15, 2026, 10_03_59 AM.png": {
        "bedroll": (318, 218), "bunk": (888, 214), "raisedBed": (1418, 214),
        "watchtower": (250, 640), "turret": (701, 660), "floodlight": (1130, 663), "generator": (1572, 641)},
    "ChatGPT Image Sep 15, 2026, 10_04_27 AM.png": {
        "barricade": (192, 170), "woodWall": (576, 170), "stoneWall": (960, 174), "reinforcedWall": (1343, 170),
        "metalWall": (192, 511), "spike": (576, 508), "gate": (960, 506), "gate_open": (1343, 506),
        "stash": (162, 833), "chest": (442, 848), "locker": (710, 846), "workbench": (1018, 849),
        "chemStation": (1356, 832)},
    "raisedbedlarge.png": {"longBed": (887, 443)},
}

# The head is drawn rotated about the middle of its body, so it is cut as a
# square centred there rather than cropped to what it covers.
HEAD = ("barrelsprite.png", "turret_head", (552, 656))

# Pictures named after a piece in a state rather than a piece.
STATES = {"gate_open", "turret_head"}

# Pieces that arrived with no build-menu icon: theirs is cut from the same
# picture, padded square the way `slice_icons` pads every icon.
NEEDS_ICON = {"longBed"}


def uncaption(sheet):
    labels, _ = nd.label(sheet[..., 3] > SOLID, structure=np.ones((3, 3)))
    for k, sl in enumerate(nd.find_objects(labels), start=1):
        if sl is not None and sl[0].stop - sl[0].start < CAPTION_H:
            sheet[sl][..., 3] = np.where(labels[sl] == k, 0, sheet[sl][..., 3])


def fit(rgba):
    """Longest side to SIZE, shape kept, premultiplied so no dark fringe."""
    h, w = rgba.shape[:2]
    k = SIZE / max(h, w)
    size = (max(1, round(w * k)), max(1, round(h * k)))
    return Image.fromarray(rgba, "RGBA").convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")


def head(src):
    name, out, (cx, cy) = HEAD
    sheet = np.array(Image.open(src / name).convert("RGBA"))
    ys, xs = np.nonzero(sheet[..., 3] > 0)
    r = int(np.ceil(max(np.abs(xs - cx).max(), np.abs(ys - cy).max()))) + 2
    canvas = np.zeros((2 * r, 2 * r, 4), np.uint8)
    y0, x0 = cy - r, cx - r
    sy, sx = slice(max(y0, 0), min(cy + r, sheet.shape[0])), slice(max(x0, 0), min(cx + r, sheet.shape[1]))
    canvas[sy.start - y0:sy.stop - y0, sx.start - x0:sx.stop - x0] = sheet[sy, sx]
    return out, fit(canvas)


def main():
    src = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "building")
    structures = table_ids("structures")
    folder = ROOT / "art" / "world"
    folder.mkdir(parents=True, exist_ok=True)
    written = []
    for file, seeds in SHEETS.items():
        for name in seeds:
            if name not in structures and name not in STATES:
                raise SystemExit(f"{name} ({file}) is not a structure id in data/")
        sheet = np.array(Image.open(src / file).convert("RGBA"))
        uncaption(sheet)
        for name, rgba in cut(sheet, seeds).items():
            fit(rgba).save(folder / f"{name}.png", optimize=True)
            if name in NEEDS_ICON:
                square(rgba).save(ROOT / "art" / "structures" / f"{name}.png", optimize=True)
            written.append(name)
    name, img = head(src)
    img.save(folder / f"{name}.png", optimize=True)
    written.append(name)
    missing = sorted(structures - set(written))
    print(f"{len(written)} pictures written; no picture for {len(missing)}: {', '.join(missing) or '-'}")


if __name__ == "__main__":
    main()
