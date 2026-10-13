"""The sprint: the walk cycle with everything bigger, a forward lean, and a
higher bob. Bible: 8 frames, loop."""
import math

from animations.walk import cycle

NAME = "run"
FRAMES = 8
FPS = 12
LOOP = True


def apply(char: dict, scene) -> None:
    j = char["rig"]
    for f in range(1, FRAMES + 1):
        t = (f - 1) / FRAMES * math.tau
        cycle(j, f, t, leg=45.0, knee=80.0, arm=42.0, elbow=70.0, bob=0.06, lean=14.0, hip_z=0.90)
