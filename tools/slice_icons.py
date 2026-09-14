"""Cut the generated icon sheets into one 128x128 PNG per id.

The icon set arrived as twelve contact sheets (`Icons/batch1..12.png`, one per
batch of `tasks/icon-generation-prompt.md`) with a transparent background, not
as a file per item. This finds every opaque blob on a sheet, gives each one to
the nearest seed below, and writes each seed's pixels — and only its pixels,
so a long diagonal weapon never carries a slice of its neighbour — padded to a
square and downscaled.

Seeds are the approximate centre of each picture in sheet pixels, placed by
looking at the sheets. They are the record of which picture is which id.
The structure sheets carry a caption under each picture, pale grey text on a
translucent shadow; `uncaption` clears those before anything is cut.

    conda activate deadline-art      (python, pillow, numpy, scipy)
    python tools/slice_icons.py Icons

Items land in art/items/, structures in art/structures/. Every id is checked
against the data tables, so a typo stops the run rather than shipping.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as nd

ROOT = Path(__file__).resolve().parent.parent
SIZE = 128
MARGIN = 0.04       # of the square's side, on each edge
SOLID = 40          # alpha above which a pixel is part of a picture
EDGE = 4            # px beyond a picture's solid pixels that still count as its edge
CAPTIONED = {11, 12}  # the sheets that label each picture in text

SHEETS = {
    1: {"wood": (155, 140), "sticks": (460, 140), "stone": (765, 140), "fiber": (1070, 140), "scrap": (1380, 140),
        "cloth": (155, 390), "elec": (460, 390), "battery": (765, 390), "med": (1070, 390), "parts": (1370, 390),
        "mil": (155, 640), "fuel": (460, 640), "rations": (755, 640), "compost": (1070, 650), "sludge": (1390, 650),
        "precision": (765, 890)},
    2: {"seedPotato": (240, 270), "seedCorn": (635, 300), "seedHerb": (1050, 290), "arrow": (1440, 260),
        "ammoP": (330, 730), "ammoS": (870, 700), "ammoR": (1310, 680)},
    3: {"pipe": (155, 140), "machete": (460, 140), "axe": (765, 140), "pick": (1080, 140), "knife": (1390, 140),
        "scythe": (160, 380), "hammer": (455, 390), "fireaxe": (760, 385), "steelpick": (1090, 390), "sledge": (1390, 380),
        "varsityBat": (145, 640), "bladedPike": (460, 630), "doubleBitAxe": (770, 630), "leafSpringBlade": (1080, 635), "makeshiftConcreteClub": (1390, 635),
        "metalSpear": (160, 890), "pistonHammer": (455, 890), "woodenSpear": (765, 890), "baseballBat": (1080, 890), "boarSpear": (1390, 885)},
    4: {"campingAxe": (150, 130), "chainsaw": (465, 135), "cleaver": (765, 130), "crowbar": (1050, 130), "fryingPan": (1385, 125),
        "gardenSpear": (150, 370), "halliganBar": (460, 380), "huntingKnife": (760, 380), "katana": (1070, 375), "kitchenKnife": (1390, 380),
        "kukri": (160, 625), "largeWrench": (460, 615), "mace": (760, 615), "makeshiftKnifeSpear": (1070, 610), "maul": (1375, 620),
        "pitchfork": (160, 850), "policeBaton": (460, 865), "shovel": (765, 860), "spikedBat": (1070, 860), "splittingAxe": (1375, 865)},
    5: {"bow": (180, 170), "pistol": (550, 185), "smg": (940, 180), "shotgun": (1310, 175),
        "rifle": (205, 515), "carbine": (585, 495), "sixShooter": (945, 510), "compoundBow": (1370, 490),
        "crossbow": (210, 845), "machinePistol": (580, 840), "pipeShotgun": (940, 820), "akStyleRifle": (1300, 815)},
    6: {"arStyleRifle": (235, 165), "boltActionRifle": (600, 175), "compactSmg": (955, 195), "doubleBarrelShotgun": (1330, 165),
        "lmg": (270, 490), "leverActionRifle": (640, 490), "marksmanRifle": (1015, 490), "revolver": (1370, 490),
        "scopedHuntingRifle": (290, 810), "semiAutoShotgun": (785, 785), "slingshot": (1360, 830)},
    7: {"hardHat": (265, 165), "riotHelm": (755, 165), "milHelm": (1240, 165),
        "lightVest": (270, 495), "heavyVest": (765, 495), "milVest": (1240, 495),
        "workGloves": (270, 850), "tacGloves": (765, 845), "armGuards": (1240, 850)},
    8: {"denimPants": (230, 305), "paddedLegs": (595, 305), "milGreaves": (960, 305), "torch": (1330, 285),
        "workBoots": (230, 750), "combatBoots": (590, 750), "milBoots": (940, 750), "flashlight": (1330, 755)},
    9: {"bandage": (170, 170), "medkit": (490, 170), "brainRaw": (800, 200), "brainMut": (1120, 200), "brainSpec": (1405, 175),
        "serum": (250, 480), "suppressant": (570, 480), "experimental": (880, 485), "lockpick": (1260, 510),
        "cannedFood": (510, 805), "jerky": (940, 820)},
    10: {"hotMeal": (180, 300), "mre": (510, 260), "candyBar": (840, 295), "water": (1125, 260), "soda": (1385, 300),
         "coffee": (155, 730), "booze": (430, 700), "potato": (715, 740), "corn": (1050, 725), "herbs": (1365, 735)},
    11: {"bedroll": (200, 200), "bunk": (580, 175), "raisedBed": (965, 210), "watchtower": (1345, 210),
         "stash": (275, 490), "chest": (725, 520), "locker": (1085, 490),
         "workbench": (260, 820), "barricade": (755, 830), "woodWall": (1270, 800)},
    12: {"stoneWall": (210, 210), "reinforcedWall": (580, 190), "metalWall": (945, 180), "gate": (1330, 190),
         "spike": (200, 550), "turret": (595, 530), "floodlight": (935, 530), "chemStation": (1320, 560),
         "generator": (755, 850)},
}


def table_ids(name):
    doc = json.loads((ROOT / "data" / f"{name}.json").read_text(encoding="utf-8"))
    rows = doc["rows"] if isinstance(doc, dict) else doc
    return {r["id"] for r in rows}


def uncaption(sheet):
    """Clears the text captions from a structure sheet, in place.

    A caption is pale, colourless and translucent (alpha under ~220, where the
    pictures themselves are ~250), sitting on the soft shadow that joins it to
    the picture above. Its letters are found by that, joined into a line, and
    everything translucent in the line's box goes — the text and the shadow
    behind it — while any solid picture pixel in the box, a bunk's leg, stays.
    """
    rgb = sheet[..., :3].astype(int)
    alpha = sheet[..., 3]
    text = (alpha > SOLID) & (alpha < 230) & (rgb.mean(-1) > 95) & (np.ptp(rgb, axis=-1) < 16)
    lines, _ = nd.label(nd.binary_dilation(text, structure=np.ones((5, 15))))
    for sl in nd.find_objects(lines):
        h, w = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
        if text[sl].sum() < 150 or w < 2.5 * h:
            continue
        box = (slice(max(sl[0].start - 3, 0), sl[0].stop + 3), slice(max(sl[1].start - 3, 0), sl[1].stop + 3))
        sheet[box][..., 3] = np.where(sheet[box][..., 3] >= 230, sheet[box][..., 3], 0)


def cut(sheet, seeds):
    """{id: RGBA array} — each seed's pixels, cropped to what it owns."""
    alpha = sheet[..., 3]
    # No dilation: some pictures sit a pixel or two apart (the LMG's muzzle
    # and the lever-action's stock). A picture's loose bits — a crumb of
    # compost, a lockpick's tension wrench — are blobs of their own and reach
    # it by being nearest its seed.
    labels, n = nd.label(alpha > SOLID)
    # A picture's faint anti-aliased edge belongs to it; the near-invisible
    # haze the generator left across the rest of the sheet belongs to nothing.
    dist, (iy, ix) = nd.distance_transform_edt(labels == 0, return_indices=True)
    labels = np.where((alpha > 0) & (dist <= EDGE), labels[iy, ix], 0)

    names = list(seeds)
    pts = np.array([seeds[k] for k in names], dtype=float)
    owner = np.full(n + 1, -1)
    for k, sl in enumerate(nd.find_objects(labels), start=1):
        if sl is None:
            continue
        mask = labels[sl] == k
        a = alpha[sl][mask]
        if a.size < 4:
            continue
        cy, cx = nd.center_of_mass(mask)
        c = np.array([sl[1].start + cx, sl[0].start + cy])
        owner[k] = int(np.argmin(np.hypot(*(pts - c).T)))

    out = {}
    for i, name in enumerate(names):
        mine = np.isin(labels, np.nonzero(owner == i)[0])
        ys, xs = np.nonzero(mine)
        if ys.size == 0:
            raise SystemExit(f"{name}: nothing on the sheet near {seeds[name]}")
        img = np.where(mine[..., None], sheet, 0).astype(np.uint8)
        out[name] = img[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    return out


def square(rgba):
    h, w = rgba.shape[:2]
    side = int(round(max(h, w) / (1 - 2 * MARGIN)))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(Image.fromarray(rgba, "RGBA"), ((side - w) // 2, (side - h) // 2))
    # Premultiplied, so the transparent black around a picture does not bleed
    # a dark fringe into its edge.
    return canvas.convert("RGBa").resize((SIZE, SIZE), Image.LANCZOS).convert("RGBA")


def main():
    src = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "Icons")
    items = table_ids("res") | table_ids("weapons") | table_ids("gear") | table_ids("consumables")
    items.discard("fists")
    structures = table_ids("structures")
    seen = set()
    for batch, seeds in SHEETS.items():
        for name in seeds:
            if name in seen:
                raise SystemExit(f"{name} is seeded twice")
            if name not in items and name not in structures:
                raise SystemExit(f"{name} (batch {batch}) is not an id in data/")
            seen.add(name)
        sheet = np.array(Image.open(src / f"batch{batch}.png").convert("RGBA"))
        if batch in CAPTIONED:
            uncaption(sheet)
        for name, rgba in cut(sheet, seeds).items():
            folder = ROOT / "art" / ("structures" if name in structures else "items")
            folder.mkdir(parents=True, exist_ok=True)
            square(rgba).save(folder / f"{name}.png", optimize=True)
    missing = sorted((items | structures) - seen)
    print(f"{len(seen)} icons written; no art for {len(missing)}: {', '.join(missing) or '-'}")


if __name__ == "__main__":
    main()
