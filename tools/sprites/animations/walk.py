"""An eight-frame walk cycle. Legs swing in opposition, the knee bends on the
swing-through, the arms counter the legs, the hips bob twice per cycle.
Bible: 8 frames, loop. Joint X rotation: negative swings a limb forward."""
import math

from common import key

NAME = "walk"
FRAMES = 8
FPS = 10
LOOP = True

LEG = 28.0    # hip swing, degrees each way
KNEE = 42.0   # knee bend at the top of the swing-through
ARM = 22.0
ELBOW = 18.0
BOB = 0.025
LEAN = 4.0


def cycle(j, f, t, leg, knee, arm, elbow, bob, lean, hip_z=0.86):
    bob_z = hip_z - bob * (1.0 - math.cos(2.0 * t)) / 2.0
    key(j["hips"], f, loc=(0.0, 0.0, bob_z), rot=(0.0, 0.0, 5.0 * math.sin(t)))
    key(j["spine"], f, rot=(lean, 0.0, -7.0 * math.sin(t)))
    key(j["head"], f, rot=(2.0, 0.0, 4.0 * math.sin(t)))
    for side, phase, sx in (("R", 0.0, -1.0), ("L", math.pi, 1.0)):
        s = math.sin(t + phase)
        # the knee bends while the leg comes forward (s rising through 0)
        swing_through = max(0.0, math.cos(t + phase))
        key(j["hip_" + side], f, rot=(-leg * s, 0.0, 0.0))
        key(j["knee_" + side], f, rot=(knee * swing_through * (0.3 + 0.7 * max(0.0, -s + 0.5)), 0.0, None))
        # arms oppose the same-side leg
        key(j["shoulder_" + side], f, rot=(arm * s - 6.0, 0.0, sx * -4.0))
        key(j["elbow_" + side], f, rot=(-elbow * (1.0 + s) / 2.0 - 6.0, 0.0, 0.0))


def apply(char: dict, scene) -> None:
    j = char["rig"]
    for f in range(1, FRAMES + 1):
        t = (f - 1) / FRAMES * math.tau
        cycle(j, f, t, LEG, KNEE, ARM, ELBOW, BOB, LEAN)
