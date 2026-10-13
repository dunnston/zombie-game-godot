"""Standing still: a slow breath, a slight sway, the arms hanging a little
forward as in the turnaround. Bible: 4 to 6 frames, loop."""
import math

from common import key

NAME = "idle"
FRAMES = 6
FPS = 6
LOOP = True


def apply(char: dict, scene) -> None:
    j = char["rig"]
    for f in range(1, FRAMES + 1):
        t = (f - 1) / FRAMES * math.tau
        breath = (1.0 - math.cos(t)) / 2.0          # 0 at the start, 1 mid-cycle
        key(j["hips"], f, loc=(0.0, 0.0, 0.86 - 0.012 * breath))
        key(j["spine"], f, rot=(2.0 * breath, 0.0, 0.0))
        key(j["head"], f, rot=(3.0 - 2.0 * breath, 0.0, 1.5 * math.sin(t)))
        for side, sx in (("R", -1.0), ("L", 1.0)):
            key(j["shoulder_" + side], f, rot=(-10.0 - 3.0 * breath, 0.0, sx * -4.0))
            key(j["elbow_" + side], f, rot=(-8.0, 0.0, 0.0))
            key(j["hip_" + side], f, rot=(0.0, 0.0, sx * 3.0))
            key(j["knee_" + side], f, rot=(0.0, 0.0, None))
