"""Entry point for `tools\\sprites.cmd`: Blender runs this headless.

    blender -b --python tools/sprites/run.py -- <character> <animation> [options]

Picks `characters/<character>.py` and `animations/<animation>.py`, builds the
scene from `common`, renders every direction and packs the sheets into
`assets/sprites/<character>/`.
"""
import argparse
import importlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
import common  # noqa: E402


def main() -> int:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser(prog="tools\\sprites")
    p.add_argument("character", help="a module in tools/sprites/characters/")
    p.add_argument("animation", help="a module in tools/sprites/animations/")
    p.add_argument("--size", type=int, default=common.CANVAS, help="canvas px (default %d)" % common.CANVAS)
    p.add_argument("--dirs", default=",".join(common.DIRECTIONS), help="comma list, default S,SE,E,NE,N")
    p.add_argument("--out", default=None, help="output folder (default art/render/<character>)")
    p.add_argument("--save-blend", action="store_true", help="also write art/blend/<character>.blend")
    a = p.parse_args(argv)

    char_mod = importlib.import_module("characters." + a.character)
    anim_mod = importlib.import_module("animations." + a.animation)
    dirs = [d.strip().upper() for d in a.dirs.split(",") if d.strip()]
    for d in dirs:
        if d not in common.DIRECTIONS:
            p.error("unknown direction %r; rendered directions are %s" % (d, ", ".join(common.DIRECTIONS)))

    scene = common.new_scene(a.size)
    char = char_mod.build(scene)
    anim_mod.apply(char, scene)
    if a.save_blend:
        blend_dir = os.path.join(PROJECT, "art", "blend")
        os.makedirs(blend_dir, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(blend_dir, a.character + ".blend"))

    out = a.out or os.path.join(PROJECT, "art", "render", a.character)
    written = common.render(char, anim_mod, out, dirs, a.size)
    print("SPRITES_OK %d sheets -> %s" % (len(written), os.path.relpath(out, PROJECT)))
    for w in written:
        print("  " + os.path.basename(w))
    return 0


if __name__ == "__main__":
    try:
        code = main()
    except SystemExit as e:  # argparse
        code = int(e.code or 0)
    except Exception:
        import traceback
        traceback.print_exc()
        code = 1
    sys.stdout.flush()
    if code:
        sys.exit(code)
