# The bus, made from Kenney's Car Kit "garbage-truck" (CC0).
#
#   blender -b --python art-src/bus/build.py
#
# Reads assets/kenney/car/bus.glb and writes assets/models/bus.glb.
#
# What is kept, because the code expects it:
#  * The four "wheel-*" objects are untouched (BfhBus finds them by name, spins and steers
#    them, and measures the wheel radius off the mesh). The art node's scale, the collision
#    hull and the VehicleWheel3D positions in props/bfh_bus.tscn were sized to this model, so
#    the body's bounds stay what they were, give or take a few centimetres of trim.
#  * Every surface stays on the kit's own colormap (one material), as before.
#
# What is changed: the green paint becomes school-bus yellow; the open skip is capped with a
# roof (its heap of rubbish is removed); a black belt line, a row of black windows down both
# sides, a roof lamp bar, red flames up the cab's flanks, two exhaust stacks and four roof
# spikes behind them, and red tail lamps are added.
import bpy
import bmesh
import os
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets", "kenney", "car", "bus.glb")
TEX = os.path.join(ROOT, "assets", "kenney", "car", "Textures", "colormap.png")
OUT = os.path.join(ROOT, "assets", "models", "bus.glb")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
body = bpy.data.objects["body"]
arm = bpy.data.objects["arm"]
img = bpy.data.images.load(TEX)
W, H = img.size
px = list(img.pixels)


def texel(rgb):
    """A pixel in the middle of a solid block of exactly this colour, as a UV."""
    want = tuple(c / 255.0 for c in rgb)
    for y in range(3, H - 3, 5):
        for x in range(3, W - 3, 5):
            ok = True
            for dy in (-3, 0, 3):
                for dx in (-3, 0, 3):
                    i = ((y + dy) * W + (x + dx)) * 4
                    if max(abs(px[i + k] - want[k]) for k in range(3)) > 0.006:
                        ok = False
            if ok:
                return ((x + 0.5) / W, (y + 0.5) / H)
    raise RuntimeError("no block of %s" % (rgb,))


def colour_at(uv):
    x = min(W - 1, max(0, int(uv[0] * W)))
    y = min(H - 1, max(0, int(uv[1] * H)))
    i = (y * W + x) * 4
    return tuple(int(round(px[i + k] * 255)) for k in range(3))


DARK = texel((56, 56, 61))
YELLOW = texel((255, 194, 20))
ORANGE = texel((255, 126, 68))
RED = texel((222, 67, 62))
WHITE = texel((255, 255, 255))
GLASS = texel((56, 56, 61))

# The skip's rubbish is not wanted under a roof.
bpy.data.objects.remove(bpy.data.objects["trash"], do_unlink=True)


def edit(obj, fn):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    fn(bm, bm.loops.layers.uv.active)
    bm.normal_update()
    bm.to_mesh(obj.data)
    bm.free()


def repaint(bm, uvl):
    n = 0
    for f in bm.faces:
        c = colour_at(f.loops[0][uvl].uv)
        if c[1] > c[0] + 40 and c[1] > c[2] + 20:
            for l in f.loops:
                l[uvl].uv = YELLOW
            n += 1
    print("REPAINTED", n)


def bounds(o):
    vs = [v.co for v in o.data.vertices]
    return (Vector([min(v[i] for v in vs) for i in range(3)]), Vector([max(v[i] for v in vs) for i in range(3)]))


lo0, hi0 = None, None


def build(bm, uvl):
    global lo0, hi0
    repaint(bm, uvl)

    def box(x0, x1, y0, y1, z0, z1, uv):
        r = bmesh.ops.create_cube(bm, size=1.0)
        verts = r["verts"]
        for v in verts:
            v.co = Vector((x1 if v.co.x > 0 else x0, y1 if v.co.y > 0 else y0, z1 if v.co.z > 0 else z0))
        for f in {f for v in verts for f in v.link_faces}:
            for l in f.loops:
                l[uvl].uv = uv

    def spike(x, y, z, r, h, uv):
        res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=4, radius1=r, radius2=0.0, depth=h)
        for v in res["verts"]:
            v.co += Vector((x, y, z + h / 2))
        for f in {f for v in res["verts"] for f in v.link_faces}:
            for l in f.loops:
                l[uvl].uv = uv

    lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), min(v.co.z for v in bm.verts)))
    hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), max(v.co.z for v in bm.verts)))
    lo0, hi0 = lo, hi
    print("BOUNDS BEFORE", tuple(lo), tuple(hi))
    X, Y, Z = hi.x, hi.y, hi.z

    # The skip: the vertices at the very top, which bound the open box.
    top = [v.co for v in bm.verts if v.co.z > Z - 0.02]
    tx0, tx1 = min(v.x for v in top), max(v.x for v in top)
    ty0, ty1 = min(v.y for v in top), max(v.y for v in top)
    print("SKIP TOP", tx0, tx1, ty0, ty1)
    # The cab's roof is what is between the cab's windscreen and the skip.
    cab_top = max(v.co.z for v in bm.verts if v.co.y < ty0 - 0.02 and v.co.y > -1.2)
    print("CAB TOP", cab_top)

    # 1. A roof over the skip, a hair under the old top.
    box(tx0 + 0.02, tx1 - 0.02, ty0 + 0.02, ty1 - 0.02, Z - 0.08, Z - 0.01, YELLOW)
    # Roof rails along its edge, in black.
    box(tx0, tx1, ty0, ty0 + 0.06, Z - 0.1, Z, DARK)
    box(tx0, tx1, ty1 - 0.06, ty1, Z - 0.1, Z, DARK)

    # 2. Belt line and a row of windows down both sides of the skip.
    n = 5
    span = (ty1 - 0.12) - (ty0 + 0.12)
    step = span / n
    for sx in (-1, 1):
        xa, xb = (X - 0.02, X + 0.01) if sx > 0 else (-X - 0.01, -X + 0.02)
        box(xa, xb, ty0 + 0.04, ty1 - 0.04, 0.60, 0.72, DARK)
        for i in range(n):
            y0 = ty0 + 0.12 + i * step + 0.04
            box(xa, xb, y0, y0 + step - 0.08, 1.05, 1.38, GLASS)

    # 3. Roof lamp bar on the cab, under the skip's top.
    box(-0.50, 0.50, ty0 - 0.30, ty0 - 0.14, cab_top, cab_top + 0.07, DARK)
    for sx in (-1, 1):
        box(sx * 0.30 - 0.12 if sx < 0 else 0.18, sx * 0.30 + 0.12 if sx < 0 else 0.42,
            ty0 - 0.28, ty0 - 0.16, cab_top + 0.07, cab_top + 0.15, RED if sx < 0 else ORANGE)

    # 4. Flames up the cab's flanks: stepped tongues, red under orange, pointing back.
    for sx in (-1, 1):
        xa, xb = (X - 0.02, X + 0.01) if sx > 0 else (-X - 0.01, -X + 0.02)
        y_front = lo.y + 0.30
        for i, (L, h) in enumerate([(0.70, 0.10), (0.52, 0.10), (0.36, 0.09), (0.22, 0.08)]):
            z0 = 0.66 + i * 0.1
            box(xa, xb, y_front, y_front + L, z0, z0 + h, RED if i % 2 == 0 else ORANGE)

    # 5. Exhaust stacks behind the cab, and spikes on the skip's roof corners.
    for sx in (-1, 1):
        box(sx * (X - 0.10) - 0.045, sx * (X - 0.10) + 0.045, ty0 + 0.10, ty0 + 0.19, Z - 0.02, Z + 0.28, DARK)
        for yy in (ty0 + 0.35, ty1 - 0.20):
            spike(sx * (X - 0.12), yy, Z - 0.02, 0.07, 0.24, WHITE)

    # 6. Tail lamps and a bumper on the rear.
    box(-0.62, -0.42, Y - 0.04, Y + 0.02, 0.50, 0.64, RED)
    box(0.42, 0.62, Y - 0.04, Y + 0.02, 0.50, 0.64, RED)
    box(-X, X, Y - 0.06, Y + 0.0, 0.20, 0.34, DARK)


edit(body, build)
edit(arm, lambda bm, uvl: repaint(bm, uvl))

lo2, hi2 = bounds(body)
print("BOUNDS AFTER", tuple(lo2), tuple(hi2))

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True)
print("WROTE", OUT)
