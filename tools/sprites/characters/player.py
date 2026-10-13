"""The Rugged Survivor, from the approved turnaround
(`Zombie Game Art/Good/Rugged Survivor Character Turnaround.png`) and the
bible's description: messy brown hair and a short beard, olive canvas
overshirt with rolled sleeves over a cream undershirt, brown leather belt,
grey-blue jeans, brown lace-up boots, large brown canvas backpack. Unarmed
for now; the pistol is a later piece.

A stocky, big-headed figure about five heads tall, built as a jointed
puppet (see common.joint). Joint names are the contract with the animation
modules: hips, spine, neck, head, shoulder_/elbow_/hip_/knee_ with R or L.
R is the character's right, which is screen-left when he faces you.
"""
import bpy

import common
from common import ball, box, cyl, detail, joint

NAME = "player"
HEIGHT = 1.8

# ---- palette (bible swatches where one exists, sampled from the turnaround otherwise)
SKIN = ("#C99A6E", "#9A6B48", "#E0B98F")
HAIR = ("#4A3224", "#2F1F17", "#6B4A34")
SHIRT = ("#57563E", "#403F2D", "#6F6E52")     # bible: olive jacket
UNDER = ("#EBD3BB", "#B9A288", "#F5E6D3")     # bible: off-white
JEANS = ("#4F5B66", "#333C45", "#64737F")     # the turnaround's grey-blue
LEATHER = ("#664332", "#3F2A1F", "#80573F")   # bible: leather
BOOT = ("#7A5234", "#4D3320", "#95683F")
CANVAS = ("#6E5B3B", "#463A25", "#857049")

# ---- proportions, metres from the feet. Short legs, wide shoulders, big head.
HIP_Z = 0.80
SHOULDER_Z = 1.30
SHOULDER_X = 0.30
NECK_Z = 1.38
HEAD_R = 0.19
HEAD_Z = NECK_Z + HEAD_R + 0.01
# The camera looks down at 45 degrees, which hides a face. The turnaround
# cheats the face toward the viewer; so does this, by a fixed tilt on a
# joint the animations never touch.
FACE_TILT_DEG = -18.0


def _wedge(name, mat, parent, loc, w, depth, h):
    """A flat triangle, point down: the V of undershirt in the open overshirt."""
    bpy.ops.mesh.primitive_cone_add(vertices=3, radius1=w, radius2=0.0, depth=h)
    o = bpy.context.object
    o.name = name
    o.parent = parent
    o.location = loc
    o.rotation_euler = (0.0, 0.0, 0.0)
    o.scale = (1.0, depth / w, 1.0)
    o.data.materials.append(mat)
    return o


def build(scene) -> dict:
    m = {k: common.toon("player_" + k, *v) for k, v in {
        "skin": SKIN, "hair": HAIR, "shirt": SHIRT, "under": UNDER, "jeans": JEANS,
        "leather": LEATHER, "boot": BOOT, "canvas": CANVAS}.items()}

    root = common.root_empty(NAME)
    hips = joint("hips", root, (0.0, 0.0, HIP_Z))
    spine = joint("spine", hips, (0.0, 0.0, 0.04))
    neck = joint("neck", spine, (0.0, 0.0, NECK_Z - HIP_Z - 0.04))
    head = joint("head", neck, (0.0, 0.0, 0.0))
    skull = joint("skull", head, (0.0, 0.0, 0.0))
    skull.rotation_euler = (common.math.radians(FACE_TILT_DEG), 0.0, 0.0)

    # pelvis and belt
    ball("pelvis", m["jeans"], hips, (0.0, 0.0, -0.03), 0.22, scale=(1.15, 0.85, 0.65))
    cyl("belt", m["leather"], hips, (0.0, 0.0, 0.05), 0.245, 0.06, scale=(1.15, 0.85, 1.0))

    # torso: the overshirt, a cream V of undershirt, the pack straps on the chest
    torso_z = (SHOULDER_Z - HIP_Z) / 2.0 - 0.03
    front_y = -0.245 * 0.85
    cyl("torso", m["shirt"], spine, (0.0, 0.0, torso_z), 0.245, 0.44, scale=(1.15, 0.85, 1.0))
    ball("shoulders", m["shirt"], spine, (0.0, 0.0, torso_z + 0.19), 0.25, scale=(1.35, 0.85, 0.45))
    detail(_wedge("undershirt", m["under"], spine, (0.0, front_y - 0.012, torso_z + 0.07), 0.10, 0.035, 0.26))
    for sx in (-1.0, 1.0):
        detail(box("strap%+d" % sx, m["leather"], spine, (sx * 0.16, front_y - 0.014, torso_z + 0.03), (0.07, 0.03, 0.40)))
    # the backpack: stuffed canvas, a leather flap, a front pocket
    ball("pack", m["canvas"], spine, (0.0, 0.30, torso_z - 0.01), 0.21, scale=(0.95, 0.6, 1.2))
    box("pack_flap", m["leather"], spine, (0.0, 0.27, torso_z + 0.20), (0.36, 0.26, 0.07))
    detail(ball("pack_pocket", m["canvas"], spine, (0.0, 0.41, torso_z - 0.08), 0.11, scale=(1.1, 0.5, 0.8)))

    # neck and head: skin, a cap of messy hair, a short beard
    cyl("neck_m", m["skin"], neck, (0.0, 0.0, 0.0), 0.075, 0.08)
    hz = HEAD_Z - NECK_Z
    ball("head_m", m["skin"], skull, (0.0, 0.0, hz), HEAD_R, scale=(1.0, 1.0, 1.05))
    ball("hair", m["hair"], skull, (0.0, 0.03, hz + 0.07), HEAD_R + 0.01, scale=(1.0, 1.0, 0.7))
    detail(ball("hair_fringe", m["hair"], skull, (0.0, -0.10, hz + 0.13), 0.11, scale=(1.25, 0.8, 0.4)))
    detail(ball("beard", m["hair"], skull, (0.0, -0.12, hz - 0.11), 0.11, scale=(1.15, 0.9, 0.55)))
    for sx in (-1.0, 1.0):
        detail(ball("eye%+d" % sx, m["hair"], skull, (sx * 0.07, -0.175, hz - 0.01), 0.026, scale=(1.0, 0.5, 0.9)))

    # arms: rolled olive sleeve to the elbow, bare forearm, fist
    for sx, side in ((-1.0, "R"), (1.0, "L")):
        sh = joint("shoulder_" + side, spine, (sx * SHOULDER_X, 0.0, SHOULDER_Z - HIP_Z - 0.04))
        ball("deltoid_" + side, m["shirt"], sh, (0.0, 0.0, 0.0), 0.10)
        cyl("upper_arm_" + side, m["shirt"], sh, (0.0, 0.0, -0.14), 0.085, 0.28)
        el = joint("elbow_" + side, sh, (0.0, 0.0, -0.28))
        ball("elbow_m_" + side, m["skin"], el, (0.0, 0.0, 0.0), 0.07)
        cyl("forearm_" + side, m["skin"], el, (0.0, 0.0, -0.12), 0.065, 0.24)
        ball("hand_" + side, m["skin"], el, (0.0, -0.01, -0.27), 0.08, scale=(0.9, 1.1, 1.0))

    # legs: jeans, big boots
    for sx, side in ((-1.0, "R"), (1.0, "L")):
        hp = joint("hip_" + side, hips, (sx * 0.13, 0.0, -0.04))
        cyl("thigh_" + side, m["jeans"], hp, (0.0, 0.0, -0.18), 0.12, 0.36)
        kn = joint("knee_" + side, hp, (0.0, 0.0, -0.36))
        # feet splay outward a little, as in the turnaround; the animations key
        # the knee's X and leave Z alone
        kn.rotation_euler = (0.0, 0.0, common.math.radians(sx * -10.0))
        ball("knee_m_" + side, m["jeans"], kn, (0.0, 0.0, 0.0), 0.11)
        cyl("shin_" + side, m["jeans"], kn, (0.0, 0.0, -0.12), 0.105, 0.24)
        # the boot: a block foot with a taller cuff, sole on the ground
        cyl("cuff_" + side, m["boot"], kn, (0.0, 0.0, -0.25), 0.115, 0.14)
        box("boot_" + side, m["boot"], kn, (0.0, -0.045, -0.33), (0.23, 0.32, 0.20))
        box("sole_" + side, m["leather"], kn, (0.0, -0.045, -0.42), (0.24, 0.34, 0.04))

    joints = {o.name: o for o in root.children_recursive if o.type == "EMPTY"}
    return {"name": NAME, "root": root, "rig": joints, "height": HEIGHT}
