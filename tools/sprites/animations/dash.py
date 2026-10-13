"""The dash: a committed low burst, 0.18 s in the sim. Four frames, one-shot:
crouch, launch, stretched flat, landing step. The engine draws the
after-images; the art just has to read as a lunge, not a run."""
import math

from common import key

NAME = "dash"
FRAMES = 4
FPS = 20
LOOP = False

# per frame: (hip z, torso lean, lead leg, trail leg, lead knee, arms back)
POSES = [
    (0.78, 22.0, -25.0, 20.0, 55.0, 15.0),
    (0.84, 38.0, -55.0, 40.0, 30.0, 28.0),
    (0.86, 42.0, -65.0, 45.0, 15.0, 34.0),
    (0.80, 20.0, -20.0, 30.0, 60.0, 12.0),
]


def apply(char: dict, scene) -> None:
    j = char["rig"]
    for f, (hz, lean, lead, trail, lead_knee, arms) in enumerate(POSES, start=1):
        key(j["hips"], f, loc=(0.0, 0.0, hz), rot=(0.0, 0.0, 0.0))
        key(j["spine"], f, rot=(lean, 0.0, 0.0))
        key(j["head"], f, rot=(-lean * 0.6, 0.0, 0.0))
        key(j["hip_R"], f, rot=(lead, 0.0, 0.0))
        key(j["knee_R"], f, rot=(lead_knee, 0.0, None))
        key(j["hip_L"], f, rot=(trail, 0.0, 0.0))
        key(j["knee_L"], f, rot=(35.0, 0.0, None))
        for side, sx in (("R", -1.0), ("L", 1.0)):
            key(j["shoulder_" + side], f, rot=(arms, 0.0, sx * -10.0))
            key(j["elbow_" + side], f, rot=(-50.0, 0.0, 0.0))
