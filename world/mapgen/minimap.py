"""The minimap's world map, baked offline: the 25 km country and the core island painted as a
storybook map (sea by depth, relief shading, biomes, forests, contours, coast line, rivers, lakes,
roads by class, towns' plots and streets).

    python3 world/mapgen/minimap.py          (from the project root; ~1-2 min)

Reads   data/outer/height.f32, aux.png, splat.png, tint.png, plan.json   (world/mapgen/outer.py)
        data/island_map.png                                                (the core: R height, G biome, B trees)
        world/mapgen/minimap_core.json   the core's roads, houses and places (tests/minimap_export.gd)
Writes  data/minimap/overview.webp   4096^2, the whole 25 km square: x = -12500 + (i + 0.5) * 25000 / 4096,
                                     z likewise by row (north, -z, is up)
        data/minimap/detail.webp     an atlas of 1.5 m/px insets: the core island, every town and hamlet
        data/minimap/map.json        {world, overview, detail: {size, mpp, insets: [{id, world, px}]}}
The game (ui/map/world_map.gd) loads these on a worker at boot; nothing is drawn per frame but the
markers. Labels are not baked: the minimap writes them upright at the zoom that suits them.
"""
import json, math, os, sys, time
import numpy as np
from scipy import ndimage
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DATA = os.path.join(ROOT, "data")
OUT = os.environ.get("MINIMAP_OUT", os.path.join(DATA, "minimap"))

N, STEP, ORIGIN, WORLD = 2001, 12.5, -12500.0, 25000.0
CORE_HALF, CORE_N, CORE_CELL = 624.0, 417, 3.0
OV = int(os.environ.get("MINIMAP_SIZE", "4096"))
DETAIL_MPP = 1.5
SS = 2                                      # supersampling of the vector layers

# biome ids (Terrain.Biome)
SEA, LIMESTONE, FOREST, FARM, BADLANDS, TOWN, BEACH, LAKE, DUNES, MOOR, SALTFLAT = range(11)
BIOME_RGB = np.array([
    [222, 208, 170],   # SEA (on land: a beach)
    [196, 190, 170],   # LIMESTONE
    [138, 160, 104],   # FOREST
    [190, 194, 128],   # FARM
    [214, 170, 112],   # BADLANDS
    [216, 204, 176],   # TOWN
    [236, 222, 176],   # BEACH
    [120, 170, 190],   # LAKE
    [232, 206, 150],   # DUNES
    [168, 158, 122],   # MOOR
    [238, 234, 220],   # SALTFLAT
], np.float32) / 255.0

INK = np.array([52, 58, 56], np.float32) / 255.0
SEA_SHALLOW = np.array([156, 206, 200], np.float32) / 255.0
SEA_MID = np.array([96, 160, 178], np.float32) / 255.0
SEA_DEEP = np.array([48, 106, 138], np.float32) / 255.0
WATER = (104, 164, 190)
ROOF = {"puerto": (192, 104, 78), "valdoro": (116, 118, 122), "sarmada": (236, 228, 212), "isola": (226, 176, 150),
        "campo": (200, 150, 96), "core": (196, 110, 80)}
ROOF_EDGE = (86, 64, 50)
PAVING = (224, 214, 192)
PAVING_EDGE = (150, 136, 112)
# road classes: (casing rgb, fill rgb, overview casing px, overview fill px, dashed)
ROADS = {
    "highway": ((120, 52, 36), (238, 170, 70), 6.0, 3.6, False),
    "road": ((112, 92, 70), (246, 236, 206), 4.4, 2.6, False),
    "track": ((128, 100, 70), (128, 100, 70), 0.0, 1.8, True),
    "street": ((128, 116, 98), (238, 230, 210), 3.2, 2.0, False),
}


def log(*a):
    print("[minimap]", *a, flush=True)


# ------------------------------------------------------------------ data
def load():
    d = {}
    d["h"] = np.fromfile(os.path.join(DATA, "outer", "height.f32"), dtype="<f4").reshape(N, N)
    aux = np.array(Image.open(os.path.join(DATA, "outer", "aux.png")).convert("RGBA"))
    d["forest"] = aux[..., 0].astype(np.float32) / 255.0
    d["biome"] = aux[..., 2]
    splat = np.array(Image.open(os.path.join(DATA, "outer", "splat.png")).convert("RGBA")).astype(np.float32) / 255.0
    d["rock"], d["snow"] = splat[..., 0], splat[..., 3]
    d["tint"] = np.array(Image.open(os.path.join(DATA, "outer", "tint.png")).convert("RGB")).astype(np.float32) / 255.0
    core = np.array(Image.open(os.path.join(DATA, "island_map.png")).convert("RGB"))
    d["core_h"] = core[..., 0].astype(np.float32) / 255.0 * 90.0 - 10.0
    d["core_b"] = core[..., 1]
    d["core_trees"] = core[..., 2].astype(np.float32) / 255.0
    # biome colours smoothed on their grids: no stair-stepped cell edges when magnified
    d["bcol"] = ndimage.gaussian_filter(BIOME_RGB[np.clip(d["biome"], 0, 10)], sigma=(5, 5, 0))
    d["core_bcol"] = ndimage.gaussian_filter(BIOME_RGB[np.clip(d["core_b"], 0, 10)], sigma=(1.5, 1.5, 0))
    d["plan"] = json.load(open(os.path.join(DATA, "outer", "plan.json")))
    d["core"] = json.load(open(os.path.join(HERE, "minimap_core.json")))
    return d


def sample(d, xs, zs):
    """Fields at world points (2-D arrays xs, zs): height, biome, forest, rock, snow, tint, colour."""
    gi = (xs - ORIGIN) / STEP; gj = (zs - ORIGIN) / STEP
    co = np.array([gj, gi])
    h = ndimage.map_coordinates(d["h"], co, order=1, mode="nearest")
    biome = ndimage.map_coordinates(d["biome"], co, order=0, mode="nearest")
    forest = ndimage.map_coordinates(d["forest"], co, order=1, mode="nearest")
    rock = ndimage.map_coordinates(d["rock"], co, order=1, mode="nearest")
    snow = ndimage.map_coordinates(d["snow"], co, order=1, mode="nearest")
    tco = np.array([(zs - ORIGIN) / 25.0, (xs - ORIGIN) / 25.0])
    tint = np.stack([ndimage.map_coordinates(d["tint"][..., c], tco, order=1, mode="nearest") for c in range(3)], -1)
    bcol = np.stack([ndimage.map_coordinates(d["bcol"][..., c], co, order=1, mode="nearest") for c in range(3)], -1)
    # the core square comes from the island's own map
    # (16 m past the core's edge too: the outer data blends its flat core fill in over one cell there)
    inside = (np.abs(xs) <= CORE_HALF + 16.0) & (np.abs(zs) <= CORE_HALF + 16.0)
    if inside.any():
        ci = (xs[inside] + CORE_HALF) / CORE_CELL; cj = (zs[inside] + CORE_HALF) / CORE_CELL
        cc = np.array([cj, ci])
        hc = ndimage.map_coordinates(d["core_h"], cc, order=1, mode="nearest")
        # the core's sea meets the lagoon's depth over its last 120 m (no square seam in the water)
        xi, zi = xs[inside], zs[inside]
        edge = np.clip((CORE_HALF + 16.0 - np.maximum(np.abs(xi), np.abs(zi))) / 120.0, 0.0, 1.0)
        lagoon = -4.6
        hc = np.where(hc < 0.0, np.minimum(hc * edge + lagoon * (1.0 - edge), -0.2), hc)
        h[inside] = hc
        bcol[inside] = np.stack([ndimage.map_coordinates(d["core_bcol"][..., c], cc, order=1, mode="nearest") for c in range(3)], -1)
        biome[inside] = ndimage.map_coordinates(d["core_b"], cc, order=0, mode="nearest")
        forest[inside] = ndimage.map_coordinates(d["core_trees"], cc, order=1, mode="nearest") * 0.9
        rock[inside] = 0.0; snow[inside] = 0.0
        tint[inside] = 0.5
    return h, biome, forest, rock, snow, tint, bcol


def noise(shape, scale, seed):
    rng = np.random.default_rng(seed)
    small = rng.random((max(2, int(shape[0] / scale)) + 2, max(2, int(shape[1] / scale)) + 2)).astype(np.float32)
    return ndimage.zoom(small, (shape[0] / (small.shape[0] - 2), shape[1] / (small.shape[1] - 2)), order=3)[:shape[0], :shape[1]]


# ------------------------------------------------------------------ the painting
def paint(d, x0, z0, mpp, W, H, seed=1):
    """The ground of a window: x0, z0 the top-left corner (m), mpp metres per pixel."""
    xs = x0 + (np.arange(W, dtype=np.float32) + 0.5) * mpp
    zs = z0 + (np.arange(H, dtype=np.float32) + 0.5) * mpp
    X, Z = np.meshgrid(xs, zs)
    h, biome, forest, rock, snow, tint, bcol = sample(d, X, Z)
    del X, Z
    water = (h <= 0.05) | (biome == LAKE)
    col = bcol
    # the in-game ground tint (field strips, heather, desert) at a third
    col = np.clip(col * (1.0 + (tint * 2.0 - 1.0) * 0.45), 0, 1)
    col = col * (1 - 0.55 * forest[..., None]) + np.array([96, 128, 80], np.float32) / 255.0 * (0.55 * forest[..., None])
    col = col * (1 - 0.5 * rock[..., None]) + np.array([170, 164, 150], np.float32) / 255.0 * (0.5 * rock[..., None])
    col = col * (1 - snow[..., None]) + np.array([246, 246, 242], np.float32) / 255.0 * snow[..., None]
    # woods stippled with tree crowns (a storybook touch) where the canopy is dense
    if mpp < 8.0:
        crowns = noise((H, W), max(1.5, 7.0 / mpp), seed + 3)
        dots = (crowns > 0.62) & (forest > 0.35) & ~water
        col[dots] = col[dots] * 0.78
    # relief: light from the north-west, exaggerated so hills read from above
    gy, gx = np.gradient(np.where(water, 0.0, h).astype(np.float32), mpp)
    ex = 2.2 if mpp > 4 else 1.4
    nx, nz = -gx * ex, -gy * ex
    ln = np.sqrt(nx * nx + nz * nz + 1.0)
    L = np.array([-0.55, -0.55, 0.63]); L = L / np.linalg.norm(L)
    shade = (nx * L[0] + nz * L[1] + L[2]) / ln
    flat = L[2]
    rel = np.clip((shade - flat) * 1.25, -0.45, 0.35)
    col = col * (1.0 + rel[..., None])
    # contours every 50 m, stronger every 250 m
    if mpp < 20:
        for step, a in ((50.0, 0.10), (250.0, 0.16)):
            k = np.floor(np.maximum(h, 0.0) / step)
            edge = np.zeros_like(k, bool)
            edge[:, 1:] |= k[:, 1:] != k[:, :-1]
            edge[1:, :] |= k[1:, :] != k[:-1, :]
            edge &= ~water & (h > step * 0.5)
            col[edge] = col[edge] * (1 - a) + np.array([110, 84, 60], np.float32) / 255.0 * a
    # the sea by depth, with a lighter band along the shore
    depth = np.clip(-h, 0.0, 60.0)
    t1 = np.clip(depth / 8.0, 0, 1)[..., None]; t2 = np.clip((depth - 8.0) / 30.0, 0, 1)[..., None]
    sea = SEA_SHALLOW * (1 - t1) + SEA_MID * t1
    sea = sea * (1 - t2) + SEA_DEEP * t2
    lakec = np.array(WATER, np.float32) / 255.0
    sea = np.where((biome == LAKE)[..., None] & (h > -0.5)[..., None], lakec, sea)
    col = np.where(water[..., None], sea, col)
    land = ~water
    # the coast: a foam halo in the water and an ink line on the shore
    px_halo = max(1, int(round(18.0 / mpp)))
    dist = ndimage.distance_transform_edt(water)
    halo = water & (dist <= px_halo)
    fa = np.clip(1.0 - dist / (px_halo + 1), 0, 1)[..., None] * 0.45
    col = np.where(halo[..., None], col * (1 - fa) + np.array([0.93, 0.96, 0.92]) * fa, col)
    shore = land & ndimage.binary_dilation(water, iterations=1)
    col[shore] = col[shore] * 0.35 + INK * 0.65
    # paper grain
    grain = noise((H, W), 3.0, seed + 7) * 0.5 + noise((H, W), 40.0, seed + 9) * 0.5
    col = col * (0.95 + 0.07 * grain[..., None])
    return np.clip(col, 0, 1), water


# ------------------------------------------------------------------ vector layers
class Canvas:
    """Supersampled RGBA drawing over a window; `to_px` maps world (x, z) to canvas pixels."""
    def __init__(self, x0, z0, mpp, W, H):
        self.x0, self.z0, self.mpp, self.W, self.H = x0, z0, mpp, W, H
        self.img = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
        self.draw = ImageDraw.Draw(self.img)

    def px(self, x, z):
        return ((x - self.x0) / self.mpp * SS, (z - self.z0) / self.mpp * SS)

    def visible(self, pts, pad=50.0):
        xs = [p[0] for p in pts]; zs = [p[1] for p in pts]
        return not (max(xs) < self.x0 - pad or min(xs) > self.x0 + self.W * self.mpp + pad or
                    max(zs) < self.z0 - pad or min(zs) > self.z0 + self.H * self.mpp + pad)

    def line(self, pts, rgb, width_px, dashed=False, dash_px=6.0):
        if len(pts) < 2 or not self.visible(pts): return
        w = max(1, int(round(width_px * SS)))
        q = [self.px(x, z) for x, z in pts]
        if not dashed:
            self.draw.line(q, fill=rgb + (255,), width=w, joint="curve")
            r = w / 2.0
            for e in (q[0], q[-1]):
                self.draw.ellipse([e[0] - r, e[1] - r, e[0] + r, e[1] + r], fill=rgb + (255,))
            return
        # dashes along the polyline
        on, acc = True, 0.0
        seg = [q[0]]
        L = dash_px * SS
        for a, b in zip(q[:-1], q[1:]):
            dx, dy = b[0] - a[0], b[1] - a[1]
            ln = math.hypot(dx, dy)
            t = 0.0
            while t < ln:
                step = min(L - acc, ln - t)
                t += step; acc += step
                p = (a[0] + dx * t / ln, a[1] + dy * t / ln)
                if on: seg.append(p)
                if acc >= L - 1e-6:
                    if on and len(seg) > 1: self.draw.line(seg, fill=rgb + (255,), width=w)
                    on = not on; acc = 0.0; seg = [p]
        if on and len(seg) > 1: self.draw.line(seg, fill=rgb + (255,), width=w)

    def poly(self, pts, fill, outline=None, width_px=1.0):
        if len(pts) < 3 or not self.visible(pts): return
        q = [self.px(x, z) for x, z in pts]
        self.draw.polygon(q, fill=fill + (255,))
        if outline is not None:
            self.draw.line(q + [q[0]], fill=outline + (255,), width=max(1, int(round(width_px * SS))))

    def disc(self, x, z, r_m, fill):
        cx, cy = self.px(x, z); r = r_m / self.mpp * SS
        self.draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill + (255,))

    def result(self):
        return self.img.resize((self.W, self.H), Image.LANCZOS)


def plot_corners(p, grow=0.0):
    yaw = math.radians(p["yaw"])
    f = (math.sin(yaw), math.cos(yaw)); t = (f[1], -f[0])
    hw = p["w"] * 0.5 + grow; hd = p["d"] * 0.5 + grow
    c = (p["x"], p["z"])
    return [(c[0] + t[0] * sw * hw + f[0] * sd * hd, c[1] + t[1] * sw * hw + f[1] * sd * hd)
            for sw, sd in ((1, 1), (-1, 1), (-1, -1), (1, -1))]


def draw_vectors(d, cv, detail):
    """Rivers, lakes, streets, plots and roads onto a Canvas. `detail`: true widths (insets)."""
    plan, core = d["plan"], d["core"]
    mpp = cv.mpp
    # rivers (their width, at least a thin line) and the mountain lake
    for r in plan.get("rivers", []):
        pts = [(p[0], p[2]) for p in r["points"]]
        w = max(np.median([p[3] for p in r["points"]]) / mpp, 1.3)
        cv.line(pts, WATER, w)
    lk = plan.get("lake")
    if lk and lk.get("polygon"):
        cv.poly([(p[0], p[1]) for p in lk["polygon"]], WATER, (70, 110, 130), 1.0)

    def width(cls, rw, which):
        cas, fill, ow_c, ow_f, dashed = ROADS[cls]
        if not detail: return ow_c if which == 0 else ow_f
        f = max(rw / mpp, ow_f * 0.8)
        return f + max(2.0, 1.4 / mpp * 2.0) if which == 0 else f

    towns = plan["towns"] + plan["hamlets"]
    roads = []   # (class, width m, pts)
    for r in plan["roads"]:
        roads.append((r["class"], r["width"], [(p[0], p[2]) for p in r["points"]]))
    for r in core["roads"]:
        roads.append((r["class"], r["width"], [(p[0], p[1]) for p in r["points"]]))
    streets = []
    for t in towns:
        for s in t["streets"]:
            streets.append((s["kind"], s["width"], [(p[0], p[2]) for p in s["points"]]))
    # paved plazas and courtyards first
    if detail:
        for kind, w, pts in streets:
            if kind == "plaza": cv.line(pts, PAVING_EDGE, w / mpp + 2.0)
        for c in core["courtyards"]: cv.disc(c[0], c[1], c[2] + 1.5, PAVING_EDGE)
        for kind, w, pts in streets:
            if kind == "plaza": cv.line(pts, PAVING, w / mpp)
        for c in core["courtyards"]: cv.disc(c[0], c[1], c[2], PAVING)
    # casings, then fills, from the smallest class up
    order = ["track", "street", "road", "highway"]
    for cls in order:
        cas, fill, _, _, dashed = ROADS[cls]
        if dashed: continue
        for c2, w, pts in roads:
            if c2 == cls: cv.line(pts, cas, width(cls, w, 0))
        if cls == "street":
            for kind, w, pts in streets:
                if kind != "plaza": cv.line(pts, cas, (w / mpp + 2.0) if detail else 2.6)
    for cls in order:
        cas, fill, _, _, dashed = ROADS[cls]
        for c2, w, pts in roads:
            if c2 == cls:
                cv.line(pts, fill, width(cls, w, 1), dashed=dashed, dash_px=max(3.0, 14.0 / mpp) if detail else 4.0)
        if cls == "street":
            for kind, w, pts in streets:
                if kind != "plaza": cv.line(pts, ROADS["street"][1], (w / mpp) if detail else 1.6)
    # buildings over the streets' edges
    for t in towns:
        roof = ROOF.get(t["style"], ROOF["core"])
        for p in t["plots"]:
            if p["kind"] == "wall": continue
            cv.poly(plot_corners(p), roof, ROOF_EDGE if detail else None, 1.0)
    for hx, hz in core["houses"]:
        s = 3.6
        cv.poly([(hx - s, hz - s), (hx + s, hz - s), (hx + s, hz + s), (hx - s, hz + s)], ROOF["core"], ROOF_EDGE if detail else None, 1.0)


def compose(d, x0, z0, mpp, W, H, detail, seed):
    base, water = paint(d, x0, z0, mpp, W, H, seed)
    cv = Canvas(x0, z0, mpp, W, H)
    draw_vectors(d, cv, detail)
    over = np.asarray(cv.result()).astype(np.float32) / 255.0
    a = over[..., 3:4]
    out = base * (1 - a) + over[..., :3] * a
    return (np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)


# ------------------------------------------------------------------ insets
def inset_windows(d):
    """World rects (x0, z0, w, h) for the detail insets: the core, each town and hamlet."""
    wins = [("core", -CORE_HALF - 30.0, -CORE_HALF - 30.0, 2 * CORE_HALF + 60.0, 2 * CORE_HALF + 60.0)]
    for t in d["plan"]["towns"] + d["plan"]["hamlets"]:
        xs = [p["x"] for p in t["plots"]] + [q[0] for s in t["streets"] for q in s["points"]]
        zs = [p["z"] for p in t["plots"]] + [q[2] for s in t["streets"] for q in s["points"]]
        pad = 90.0
        x0, x1 = min(xs) - pad, max(xs) + pad
        z0, z1 = min(zs) - pad, max(zs) + pad
        wins.append((t["id"], x0, z0, x1 - x0, z1 - z0))
    return wins


def pack(sizes, width):
    """Shelf packing: sizes [(w, h)] -> positions, total height. Tallest first."""
    order = sorted(range(len(sizes)), key=lambda i: -sizes[i][1])
    pos = [None] * len(sizes)
    x = y = shelf = 0
    for i in order:
        w, h = sizes[i]
        if x + w > width:
            x = 0; y += shelf; shelf = 0
        pos[i] = (x, y); x += w; shelf = max(shelf, h)
    return pos, y + shelf


def main():
    t0 = time.time()
    os.makedirs(OUT, exist_ok=True)
    d = load()
    log("data loaded in %.1f s" % (time.time() - t0))
    mpp = WORLD / OV
    ov = compose(d, ORIGIN, ORIGIN, mpp, OV, OV, False, 11)
    Image.fromarray(ov).save(os.path.join(OUT, "overview.webp"), quality=90, method=6)
    log("overview %d^2 (%.2f m/px) in %.1f s" % (OV, mpp, time.time() - t0))
    wins = inset_windows(d)
    GUTTER = 4
    sizes = [(int(math.ceil(w / DETAIL_MPP)) + 2 * GUTTER, int(math.ceil(h / DETAIL_MPP)) + 2 * GUTTER) for _, _, _, w, h in wins]
    AW = 2048
    pos, AH = pack(sizes, AW)
    AH = (AH + 3) // 4 * 4
    atlas = np.zeros((AH, AW, 3), np.uint8)
    insets = []
    for k, (wid, x0, z0, w, h) in enumerate(wins):
        pw, ph = sizes[k]
        # paint the gutter too (continuous ground), so linear filtering never bleeds a neighbour in
        img = compose(d, x0 - GUTTER * DETAIL_MPP, z0 - GUTTER * DETAIL_MPP, DETAIL_MPP, pw, ph, True, 100 + k)
        px, py = pos[k]
        atlas[py:py + ph, px:px + pw] = img
        insets.append({"id": wid, "world": [round(x0, 2), round(z0, 2), round(pw - 2 * GUTTER) * DETAIL_MPP, round(ph - 2 * GUTTER) * DETAIL_MPP],
                       "px": [px + GUTTER, py + GUTTER, pw - 2 * GUTTER, ph - 2 * GUTTER]})
    Image.fromarray(atlas).save(os.path.join(OUT, "detail.webp"), quality=92, method=6)
    log("detail atlas %dx%d, %d insets in %.1f s" % (AW, AH, len(insets), time.time() - t0))
    meta = {"version": 1, "world": [ORIGIN, ORIGIN, WORLD],
            "overview": {"file": "overview.webp", "size": OV},
            "detail": {"file": "detail.webp", "size": [AW, AH], "mpp": DETAIL_MPP, "insets": insets}}
    json.dump(meta, open(os.path.join(OUT, "map.json"), "w"), indent=1)
    open(os.path.join(OUT, ".gdignore"), "w").close()
    log("done in %.1f s" % (time.time() - t0))


if __name__ == "__main__":
    main()
