"""Outer-world generator: the 25 km country round the hand-built core.

    python3 world/mapgen/outer.py            (from the project root; ~3-5 min)

Reads   world/mapgen/core_exits.json   (the four core exit roads, dumped from the booted game by
                                          tests/dump_core_exits.gd)
        data/island_map.png            (the core's own map: water inside the core for sea lanes)
Writes  data/outer/height.f32          2001 x 2001 float32 LE, 12.5 m, x = -12500 + i*12.5, row-major by z
        data/outer/splat.png           RGBA8 2001^2: R rock, G sand/beach, B soil/farmland, A snow (grass = rest)
        data/outer/aux.png             RGBA8 2001^2: R forest density, G flatten (roads, pads), B biome id, A wetness/cliff
        data/outer/tint.png            RGB8 1001^2 (25 m): macro colour multiplier (x2 in the shader, 128 = 1.0)
        data/outer/roads.png           L8 4096^2 (6.1 m): road coverage for the far terrain shader
        data/outer/micro.png           L8 256^2 tileable micro relief (64 m tile), 128 = 0
        data/outer/plan.json           towns, hamlets, roads, bridges, sea lanes, ports, camps, landmarks
See docs/adr/0010-outer-world.md for the layout contract.
"""
import json, math, os, sys, time, pickle
import numpy as np
from scipy import ndimage
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(os.path.dirname(HERE))
import outer_land as L
import outer_noise as NZ
import outer_route as R
import outer_towns as T
import outer_layouts as LY
import outer_water as W

N, STEP, ORIGIN = L.N, L.STEP, L.ORIGIN
OUT = os.environ.get("OUTER_OUT", os.path.join(ROOT, "data", "outer"))
CACHE = os.environ.get("OUTER_CACHE", "/tmp/outer_cache")
LATTICE = 6.25                     # the runtime surface: triangles on a 6.25 m lattice (half the data spacing)
MICRO_TILE = 64.0                  # micro relief tile (m), 256 px
MICRO_AMP = 0.45                   # metres (+-), masked off on roads and pads
ROUTE_CELL = 25.0

# classes: width (m), grade limit, water cost multiplier, min turn radius
CLASSES = {
    "highway": dict(width=11.0, gmax=0.07, water=7.0, radius=70.0, sigma=6.0),
    "road": dict(width=7.0, gmax=0.10, water=40.0, radius=22.0, sigma=4.0),
    "track": dict(width=4.5, gmax=0.14, water=200.0, radius=10.0, sigma=3.0),
    "street": dict(width=7.0, gmax=0.16, water=60.0, radius=8.0, sigma=0.0),
}

TOWN_DEFS = [
    # id, name, style, centre, radius, sea_side, gate
    ("puerto_alto", "Puerto Alto", "puerto", (7480, 1850), 700, True, (7020, 2260)),
    ("campo_real", "Campo Real", "campo", (5600, -2250), 480, False, (5060, -2120)),
    ("valdoro", "Valdoro", "valdoro", None, 230, False, None),
    ("sarmada", "Sarmada", "sarmada", (2650, 8650), 420, True, None),
    ("isola_serena", "Isola Serena", "isola", None, 240, True, None),
]
# the causeway's mainland end on the ring highway: at the head of the valley that comes down to the
# strait (north of it the mainland meets the water in a 70 m cliff a road cannot descend)
ISOLA_JUNCTION = (-7300, 2950)
# grade limits for mountain roads that climb valley heads steeper than their class allows (the
# alpine highway into Valdoro, the dam road): without them the pinned ends leave long fills
ROAD_GMAX = {"ring.valdoro.campo_real": 0.095, "ring.isola_junction.valdoro": 0.095, "spoke.north": 0.095,
             "road.dam": 0.12, "road.northwest": 0.12}


def log(*a):
    print("[outer %6.1fs]" % (time.time() - T0), *a, flush=True)


def cached(name, fn, *args, force=False):
    os.makedirs(CACHE, exist_ok=True)
    p = os.path.join(CACHE, name + ".pkl")
    if os.path.exists(p) and not force and os.environ.get("OUTER_FRESH", "") not in ("1", name):
        with open(p, "rb") as f: return pickle.load(f)
    v = fn(*args)
    with open(p, "wb") as f: pickle.dump(v, f)
    return v


# ------------------------------------------------------------------ sampling helpers
def bil(h, x, z):
    gx = (np.asarray(x) - ORIGIN) / STEP; gz = (np.asarray(z) - ORIGIN) / STEP
    i = np.clip(np.floor(gx).astype(int), 0, N - 2); j = np.clip(np.floor(gz).astype(int), 0, N - 2)
    u = gx - i; v = gz - j
    return h[j, i] * (1 - u) * (1 - v) + h[j, i + 1] * u * (1 - v) + h[j + 1, i] * (1 - u) * v + h[j + 1, i + 1] * u * v


def micro_tile():
    """The tileable micro-relief texture (256 px over MICRO_TILE metres), -1..1."""
    n = 256
    a = np.arange(n) / n
    X, Z = np.meshgrid(a, a)
    out = np.zeros((n, n))
    rng = np.random.default_rng(99)
    amp = 1.0
    for o, freq in enumerate((2, 4, 8, 16)):
        ph = rng.uniform(0, 2 * np.pi, (6,))
        for k in range(3):
            fx = freq * rng.integers(-2, 3) or freq; fz = freq * rng.integers(-2, 3) or freq
            out += amp * np.sin(2 * np.pi * (fx * X + fz * Z) + ph[k]) / 3
        amp *= 0.5
    out /= np.abs(out).max()
    q = np.round(out * 127 + 128).clip(1, 255).astype(np.uint8)
    return q


def lattice_heights(h, flat, micro_img, xs, zs):
    """The runtime surface at lattice points: bilinear data + micro relief x (1 - flatten)."""
    base = bil(h, xs, zs)
    fl = bil(flat, xs, zs)
    m = (micro_sample(micro_img, xs, zs) - 128.0) / 127.0
    return base + m * MICRO_AMP * (1.0 - np.clip(fl, 0, 1))


def micro_sample(img, xs, zs):
    n = img.shape[0]
    gx = np.mod(np.asarray(xs) / MICRO_TILE * n, n); gz = np.mod(np.asarray(zs) / MICRO_TILE * n, n)
    i = np.floor(gx).astype(int); j = np.floor(gz).astype(int)
    u = gx - i; v = gz - j
    i1 = (i + 1) % n; j1 = (j + 1) % n
    f = img.astype(float)
    return f[j, i] * (1 - u) * (1 - v) + f[j, i1] * u * (1 - v) + f[j1, i] * (1 - u) * v + f[j1, i1] * u * v


def surface_at(h, flat, micro_img, x, z):
    """Exactly the runtime height_at: triangle interpolation on the 6.25 m lattice."""
    x = np.asarray(x, float); z = np.asarray(z, float)
    gx = (x - ORIGIN) / LATTICE; gz = (z - ORIGIN) / LATTICE
    i = np.floor(gx); j = np.floor(gz)
    u = gx - i; v = gz - j
    x0 = ORIGIN + i * LATTICE; z0 = ORIGIN + j * LATTICE
    a = lattice_heights(h, flat, micro_img, x0, z0)
    b = lattice_heights(h, flat, micro_img, x0 + LATTICE, z0)
    c = lattice_heights(h, flat, micro_img, x0, z0 + LATTICE)
    d = lattice_heights(h, flat, micro_img, x0 + LATTICE, z0 + LATTICE)
    lower = u + v <= 1.0
    return np.where(lower, a + (b - a) * u + (c - a) * v, d + (c - d) * (1 - u) + (b - d) * (1 - v))


# ------------------------------------------------------------------ stage 1: terrain
def stage_terrain():
    h, f = L.base_heights(); log("base heights")
    h = L.shape(h, f); log("shaped")
    h = L.erode(h, f); log("eroded")
    # crisp mesas: re-terrace the arid plateau after erosion (flat tops, steep risers)
    arid = f["wS"] * L.smoothstep(70, 120, h)
    h = h + (L.terrace(h, 22.0, 4.0) - h) * arid * 0.9
    h = L.carve_estuary(h, f); log("estuary")
    h = L.carve_strait(h, f); log("strait")
    # the core square: match the core's own seabed at its edge (the core map's rim is -3..-7)
    ax = np.maximum(np.abs(f["x"]), np.abs(f["z"]))
    h = np.where(ax < L.CORE_HALF + 2, np.minimum(h, -6.0), h)
    fields = {k: f[k].astype(np.float32) for k in ("c", "lag", "wN", "wS", "wE", "wW", "gentle", "crest", "canyon", "mesa")}
    return h.astype(np.float64), fields


# ------------------------------------------------------------------ stage 2: town sites and layouts
def find_site(ctx, around, radius, hmin, hmax, step=50.0, want_slope=(0.0, 0.3)):
    best = None; bs = 1e9
    for dz in np.arange(-radius, radius + 1, step):
        for dx in np.arange(-radius, radius + 1, step):
            x = around[0] + dx; z = around[1] + dz
            hh = ctx.H(x, z, True)
            if hh < hmin or hh > hmax: continue
            g = math.hypot(*ctx.grad(x, z, 40.0))
            if g < want_slope[0] or g > want_slope[1]: continue
            s = math.hypot(dx, dz) / radius + abs(g - 0.5 * (want_slope[0] + want_slope[1])) * 3
            if s < bs: bs = s; best = np.array([x, z])
    return best


PLOT_CAP = {"puerto": 660, "campo": 285, "sarmada": 330, "valdoro": 190, "isola": 150}
KEEP_KINDS = {"church", "tower", "town_hall", "wall", "gate", "citadel", "lighthouse", "windmill", "market_hall", "barn", "granary", "boathouse"}


def cap_plots(t, cap):
    """Keep the town within its plot budget: drop ordinary plots farthest from the centre."""
    if len(t.plots) <= cap: return
    special = [p for p in t.plots if p["kind"] in KEEP_KINDS]
    rest = [p for p in t.plots if p["kind"] not in KEEP_KINDS]
    rest.sort(key=lambda p: math.hypot(p["x"] - t.center[0], p["z"] - t.center[1]))
    t.plots = special + rest[:max(cap - len(special), 0)]
    t.plots.sort(key=lambda p: int(p["id"].split(".b")[1]))


def stage_towns(h):
    ctx = LY.Ctx(h)
    towns = []
    for k, (tid, name, style, centre, radius, sea, gate) in enumerate(TOWN_DEFS):
        if tid == "valdoro":
            centre = find_site(ctx, (-1500, -5150), 700, 330, 440, 25.0, (0.12, 0.32))
            g = ctx.grad(*centre, 60.0); down = -T.unit(g)
            # the gate: down the slope, where the valley road passes below the terraces
            gate = centre + down * 240
        if tid == "isola_serena":
            # the south-east shore of the big western island: the village climbs from the harbour
            sh = max(ctx.shoreline(-9400, 1500, -8200, 2600, 1.0), key=len)
            kk = int(np.argmin(np.hypot(*(sh - np.array([-8800.0, 2250.0])).T)))
            st = T.unit(sh[min(kk + 5, len(sh) - 1)] - sh[max(kk - 5, 0)])
            centre = sh[kk] + ctx.inland_normal(sh[kk], st) * 120
            gate = centre + np.array([330.0, -260.0])
        t = T.Town(tid, name, style, centre, radius, sea, 1000 + k * 17)
        if tid == "sarmada":
            shores = ctx.shoreline(centre[0] - 700, centre[1] - 700, centre[0] + 700, centre[1] + 700, 1.0)
            sh = shores[0]; kk = int(np.argmin(np.hypot(*(sh - centre).T)))
            st = T.unit(sh[min(kk + 5, len(sh) - 1)] - sh[max(kk - 5, 0)])
            inl = ctx.inland_normal(sh[kk], st)
            gate = sh[kk] + inl * (150 + 40 + 190)
        t.gate = np.asarray(gate, float)
        {"puerto": LY.layout_puerto, "campo": LY.layout_campo, "valdoro": LY.layout_valdoro,
         "sarmada": LY.layout_sarmada, "isola": LY.layout_isola}[style](t, ctx)
        cap_plots(t, PLOT_CAP[style])
        log("town", tid, "plots", len(t.plots), "streets", len(t.streets), "centre", t.center.round(0))
        towns.append(t)
    return towns


def town_heights(h, towns, flat):
    """Assign street heights, carve the town surfaces (streets and plot pads) into `h`."""
    ctx = LY.Ctx(h)
    hs = ndimage.gaussian_filter(h, 4.0)          # ~50 m: the smooth town ground
    dist = np.full(h.shape, 1e9); yt = np.zeros(h.shape); hw = np.zeros(h.shape)
    for t in towns:
        # street profiles
        for st in t.streets:
            pts = st["pts"]
            rule = st.get("rule", ("smooth", None))
            if rule[0] == "flat" and rule[1] is not None:
                y = np.full(len(pts), float(rule[1]))
            elif rule[0] == "ramp":
                ctrl = np.asarray(rule[1], float)
                # height from the nearest control point run (piecewise linear along the control path)
                seg = np.hypot(*np.diff(ctrl[:, :2], axis=0).T); cum = np.concatenate([[0], np.cumsum(seg)])
                sp = np.hypot(*np.diff(pts, axis=0).T); cs = np.concatenate([[0], np.cumsum(sp)])
                y = np.interp(cs / max(cs[-1], 1e-6) * cum[-1], cum, ctrl[:, 2])
            elif rule[0] == "land":
                y = ndimage.gaussian_filter1d(bil(hs, pts[:, 0], pts[:, 1]), 2.0, mode="nearest")
            else:
                y = bil(hs, pts[:, 0], pts[:, 1])
                if t.style in ("campo", "sarmada"):
                    y = 0.5 * y + 0.5 * float(bil(hs, [t.center[0]], [t.center[1]])[0])
                if rule[0] == "flat": y = np.full(len(pts), float(np.mean(y)))
            y = np.maximum(y, 2.2 if t.sea_side else 1.5)
            st["y"] = y
        # plot pads: the height of the street they front (or the land)
        for p in t.plots:
            if "_level" in p:
                p["_pad"] = p["_level"]
            elif "_street" in p:
                st = t.streets[p["_street"]]
                k = int(np.argmin(np.hypot(*(st["pts"] - p["_front"]).T)))
                p["_pad"] = float(st["y"][k])
            else:
                p["_pad"] = max(float(bil(hs, [p["x"]], [p["z"]])[0]), 2.2 if t.sea_side else 1.5)
        # rasterise: streets as segments, plot pads as their centre rectangles
        for st in t.streets:
            pts = st["pts"]; y = st["y"]
            ok = np.ones(len(pts) - 1, np.uint8)
            R.carve_roads(h, ORIGIN, STEP, pts[:, 0].copy(), pts[:, 1].copy(), y.astype(np.float64), np.full(len(pts), st["width"] * 0.5), ok, 3.0, 40.0, dist, yt, hw)
        for p in t.plots:
            poly = p["_poly"]
            c = np.array([p["x"], p["z"]])
            # the pad as a short thick segment along its frontage
            fr = T.unit(poly[0] - poly[1])
            a = c - fr * max(p["w"] * 0.5 - p["d"] * 0.5, 0.0); b = c + fr * max(p["w"] * 0.5 - p["d"] * 0.5, 0.0)
            R.carve_roads(h, ORIGIN, STEP, np.array([a[0], b[0]]), np.array([a[1], b[1]]), np.array([p["_pad"], p["_pad"]]),
                          np.array([p["d"] * 0.5, p["d"] * 0.5]), np.ones(1, np.uint8), 3.0, 40.0, dist, yt, hw)
        # quays and moles filled up to land
        for poly in t.fill:
            poly = np.asarray(poly)
            i0, j0 = ((poly.min(0) - ORIGIN) / STEP).astype(int) - 1; i1, j1 = ((poly.max(0) - ORIGIN) / STEP).astype(int) + 2
            for j in range(j0, j1):
                for i in range(i0, i1):
                    if T.point_in_poly((ORIGIN + i * STEP, ORIGIN + j * STEP), poly):
                        dist[j, i] = 0; yt[j, i] = 2.3; hw[j, i] = 7
    # quays: a paved strip at quay level behind every quay edge, the water in front of it dredged to
    # a berth depth, so the quay wall (OuterProps) stands between land and deep water
    dredge = np.zeros(h.shape, bool)
    filled = np.zeros(h.shape, bool)
    for t in towns:
        for poly in t.fill:
            poly = np.asarray(poly)
            i0, j0 = ((poly.min(0) - ORIGIN) / STEP).astype(int) - 1; i1, j1 = ((poly.max(0) - ORIGIN) / STEP).astype(int) + 2
            for j in range(j0, j1):
                for i in range(i0, i1):
                    if T.point_in_poly((ORIGIN + i * STEP, ORIGIN + j * STEP), poly): filled[j, i] = True
    landish = np.where(filled, 5.0, h)
    for t in towns:
        for edge in t.quay_edges:
            E = LY.resample_line(np.asarray(edge, float), 6.0)
            if len(E) < 2: continue
            for k in range(len(E) - 1):
                a = E[k]; b = E[k + 1]; ab = b - a; L2 = ab @ ab
                if L2 < 1e-6: continue
                nrm = T.perp(T.unit(ab))
                if bil(landish, [a[0] + nrm[0] * 9], [a[1] + nrm[1] * 9])[0] < bil(landish, [a[0] - nrm[0] * 9], [a[1] - nrm[1] * 9])[0]: nrm = -nrm
                i0 = int((min(a[0], b[0]) - 32 - ORIGIN) / STEP); i1 = int((max(a[0], b[0]) + 32 - ORIGIN) / STEP) + 1
                j0 = int((min(a[1], b[1]) - 32 - ORIGIN) / STEP); j1 = int((max(a[1], b[1]) + 32 - ORIGIN) / STEP) + 1
                jj, ii = np.mgrid[j0:j1 + 1, i0:i1 + 1]
                X = ORIGIN + ii * STEP; Z = ORIGIN + jj * STEP
                tt = ((X - a[0]) * ab[0] + (Z - a[1]) * ab[1]) / L2
                on = (tt >= -0.05) & (tt <= 1.05)
                lat = (X - a[0]) * nrm[0] + (Z - a[1]) * nrm[1]
                quay = on & (lat >= -0.5) & (lat <= 13.0)
                sea = on & (lat < -0.5) & (lat > -65.0)
                dist[jj[quay], ii[quay]] = 0.0; yt[jj[quay], ii[quay]] = 2.3; hw[jj[quay], ii[quay]] = 7.0
                dredge[jj[sea], ii[sea]] = True
    h2, w = R.apply_carve(h, dist, yt, hw, 3.0, 40.0)
    # (the quay edge follows the smoothed shoreline: whatever beach or spit lies in front of it goes)
    h2 = np.where(dredge & ~ndimage.binary_dilation(filled, iterations=1), np.minimum(h2, -3.4), h2)
    # never lower the ground below the sea inside a town's pads (quays stay land)
    flat_new = np.clip((dist < hw + 4) * 1.0, 0, 1)
    flat[:] = np.maximum(flat, ndimage.uniform_filter(flat_new, 3))
    return h2


# ------------------------------------------------------------------ stage 3: sea lanes
def core_water():
    """Water mask inside the core (the core's own map), on our grid."""
    img = np.asarray(Image.open(os.path.join(ROOT, "data", "island_map.png")).convert("RGB")).astype(float)
    hc = img[..., 0] / 255 * 90 - 10
    return hc


def stage_lanes(h, towns, harbour, exits=None):
    hc = core_water()
    # 50 m lane grid over the whole world
    C = 50.0; n = int(25000 / C) + 1
    a = ORIGIN + np.arange(n) * C
    X, Z = np.meshgrid(a, a)
    hh = bil(h, X, Z)
    inside = (np.abs(X) < 624) & (np.abs(Z) < 624)
    # core cells from the core map
    ci = np.clip(np.round((X + 624) / 3).astype(int), 0, 416); cj = np.clip(np.round((Z + 624) / 3).astype(int), 0, 416)
    hh = np.where(inside, hc[cj, ci], hh)
    water = hh < -0.5
    clear = ndimage.distance_transform_edt(water) * C
    deep = hh < -8.0
    ok = (clear >= 60) & deep
    ok_core = (clear >= 25) & (hh < -1.5)
    near_core = np.maximum(np.abs(X), np.abs(Z)) < 1300
    passable = np.where(near_core, ok_core | ok, ok)
    # the core exits leave on low decks: ships keep clear of their corridors across the lagoon
    for name, ex in (exits or {}).items():
        pts = np.asarray(ex["points"], float)[:, [0, 2]]
        b0 = ex["bridges"][0][0] if ex["bridges"] else len(pts) - 1
        a = pts[max(b0 - 5, 0)]; t = T.unit(pts[-1] - pts[-8]); b = pts[-1] + t * 260.0
        ab = b - a; L2 = ab @ ab
        tt = np.clip(((X - a[0]) * ab[0] + (Z - a[1]) * ab[1]) / L2, 0, 1)
        d = np.hypot(X - (a[0] + ab[0] * tt), Z - (a[1] + ab[1] * tt))
        passable &= d > 90.0
    forbid = (~passable).astype(np.uint8)
    ports = {"core": harbour}
    for t in towns:
        if t.port is not None: ports[t.id] = np.asarray(t.port["berth"], float)
    def node(p):
        i = int(round((p[0] - ORIGIN) / C)); j = int(round((p[1] - ORIGIN) / C))
        # nearest passable cell
        if forbid[j, i]:
            best = None; bd = 1e9
            for dj in range(-14, 15):
                for di in range(-14, 15):
                    jj = j + dj; ii = i + di
                    if 0 <= jj < n and 0 <= ii < n and not forbid[jj, ii]:
                        d = di * di + dj * dj
                        if d < bd: bd = d; best = (ii, jj)
            i, j = best
        return j * n + i
    zero = np.zeros((n, n), np.uint8)
    pairs = [("core", "puerto_alto"), ("puerto_alto", "sarmada"), ("sarmada", "isola_serena"), ("core", "sarmada")]
    lanes = []
    for a_id, b_id in pairs:
        pa = ports[a_id]; pb = ports[b_id]
        # ships keep to the middle of channels: cost falls off with the clearance from land
        mult = (1.0 + 2.0 / (1.0 + clear / 120.0)).astype(np.float64)
        path = R.astar(np.zeros((n, n)), zero, forbid, zero, C, node(pa), node(pb), zero,
                       1.0, 0.0, 1.0, 0.0, 1.0, 1.0, mult)
        if len(path) == 0:
            log("LANE FAILED", a_id, b_id); continue
        pts = np.stack([ORIGIN + (path % n) * C, ORIGIN + (path // n) * C], 1)
        pts = R.rdp(pts, 30.0)
        pts = R.chaikin(pts, 3)
        pts = np.vstack([pa, pts[1:-1], pb])
        lanes.append({"id": "lane.%s.%s" % (a_id, b_id), "from": a_id, "to": b_id, "points": pts})
        log("lane", a_id, b_id, "%.1f km" % (R.resample(pts, 10).shape[0] * 0.01))
    return lanes


# ------------------------------------------------------------------ stage 4: roads
class Net:
    def __init__(self):
        self.roads = []          # dicts: id, cls, pts (n,2), y (n,), bridges, from, to, fixed
        self.cells = None


def route_grid(h, towns, lake_mask):
    step = int(ROUTE_CELL / STEP)
    hr = ndimage.gaussian_filter(h, 1.5)[::step, ::step]
    n = hr.shape[0]
    water = (hr < 0.4).astype(np.uint8)
    if RIVER_MASK is not None:
        water |= ndimage.maximum_filter(RIVER_MASK, step)[::step, ::step].astype(np.uint8)
    forbid = np.zeros((n, n), np.uint8)
    a = ORIGIN + np.arange(n) * ROUTE_CELL
    X, Z = np.meshgrid(a, a)
    forbid[np.maximum(np.abs(X), np.abs(Z)) < 640] = 1                 # the core itself
    forbid[lake_mask[::step, ::step] > 0] = 1
    forbid[hr < -30] = 1
    for t in towns:
        d = np.hypot(X - t.center[0], Z - t.center[1])
        forbid[d < t.radius * 0.8] = 1
    set_hard_forbid(towns, X, Z)
    return hr, water, forbid, X, Z


HARD = None                # route cells no road may use, even round a gate: the towns' plots and walls
HARD_REACH = 14.0          # a cell is off limits when its centre is this close to a plot or a wall


def set_hard_forbid(towns, X=None, Z=None):
    """The towns' (and hamlets') plots, walls and walled precincts as route cells (C-3): the ring
    and the spokes used to cut through Sarmada's wall and citadel because the cells round a gate
    were cleared for the approach. Cells within 30 m of a gate stay open."""
    global HARD
    n = int(25000 / ROUTE_CELL) + 1
    if X is None:
        a = ORIGIN + np.arange(n) * ROUTE_CELL
        X, Z = np.meshgrid(a, a)
    hard = np.zeros(X.shape, np.uint8)
    def mark(px, pz, reach):
        i0 = max(int((px - reach - ORIGIN) / ROUTE_CELL), 0); i1 = min(int((px + reach - ORIGIN) / ROUTE_CELL) + 1, X.shape[1] - 1)
        j0 = max(int((pz - reach - ORIGIN) / ROUTE_CELL), 0); j1 = min(int((pz + reach - ORIGIN) / ROUTE_CELL) + 1, X.shape[0] - 1)
        return j0, j1, i0, i1
    for t in towns:
        for p in t.plots:
            poly = p["_poly"]
            r0 = 0.5 * math.hypot(p["w"], p["d"]) + HARD_REACH
            j0, j1, i0, i1 = mark(p["x"], p["z"], r0)
            if j1 < j0 or i1 < i0: continue
            xs = X[j0:j1 + 1, i0:i1 + 1]; zs = Z[j0:j1 + 1, i0:i1 + 1]
            dmin = np.full(xs.shape, 1e9)
            for k in range(4):
                a = poly[k]; b = poly[(k + 1) % 4]; ab = b - a; L2 = max(ab @ ab, 1e-9)
                tt = np.clip(((xs - a[0]) * ab[0] + (zs - a[1]) * ab[1]) / L2, 0, 1)
                dmin = np.minimum(dmin, np.hypot(xs - a[0] - ab[0] * tt, zs - a[1] - ab[1] * tt))
            inside = np.ones(xs.shape, bool)
            for k in range(4):
                a = poly[k]; b = poly[(k + 1) % 4]
                c = (b[0] - a[0]) * (zs - a[1]) - (b[1] - a[1]) * (xs - a[0])
                inside &= c >= 0
            inside2 = np.ones(xs.shape, bool)
            for k in range(4):
                a = poly[k]; b = poly[(k + 1) % 4]
                c = (b[0] - a[0]) * (zs - a[1]) - (b[1] - a[1]) * (xs - a[0])
                inside2 &= c <= 0
            hard[j0:j1 + 1, i0:i1 + 1] |= ((dmin < HARD_REACH) | inside | inside2).astype(np.uint8)
        # walled precincts: everything inside the wall line (and just outside it)
        for wl in t.walls:
            W_ = np.asarray(wl, float)
            if len(W_) < 3: continue
            lo_ = W_.min(0) - 40; hi_ = W_.max(0) + 40
            j0, j1, i0, i1 = mark(0.5 * (lo_[0] + hi_[0]), 0.5 * (lo_[1] + hi_[1]), 0.5 * max(hi_ - lo_))
            for j in range(j0, j1 + 1):
                for i in range(i0, i1 + 1):
                    q = (X[j, i], Z[j, i])
                    if T.point_in_poly(q, W_): hard[j, i] = 1; continue
                    for k in range(len(W_) - 1):
                        if T.seg_seg_dist(np.array(q), np.array(q), W_[k], W_[k + 1]) < 20.0: hard[j, i] = 1; break
        # the gate stays reachable
        if t.gate is not None:
            g = np.asarray(t.gate, float)
            hard[np.hypot(X - g[0], Z - g[1]) < 30.0] = 0
    HARD = hard


def to_node(p, n):
    i = int(round((p[0] - ORIGIN) / ROUTE_CELL)); j = int(round((p[1] - ORIGIN) / ROUTE_CELL))
    return j * n + max(0, min(i, n - 1)) if 0 <= j < n else 0


def parallel_mult(roadcells, keep_free):
    """Cost multiplier that keeps new roads from running alongside existing ones (40-220 m off
    them), except round the junction points in `keep_free`."""
    n = roadcells.shape[0]
    if not roadcells.any(): return np.ones((n, n))
    d = ndimage.distance_transform_edt(roadcells == 0) * ROUTE_CELL
    m = np.where((d > 30) & (d < 220), 2.6, 1.0)
    for p, r in keep_free:
        i = int(round((p[0] - ORIGIN) / ROUTE_CELL)); j = int(round((p[1] - ORIGIN) / ROUTE_CELL))
        k = int(r / ROUTE_CELL) + 1
        m[max(j - k, 0):j + k + 1, max(i - k, 0):i + k + 1] = 1.0
    return m.astype(np.float64)


def route(grid, a, b, cls, roadcells, target=None, extra_forbid=None, clear_around=(), water=None, gmax=None):
    hr, wmask, forbid, X, Z = grid
    n = hr.shape[0]
    mult = parallel_mult(roadcells, list(clear_around) + [(a, 500.0)] + ([(b, 500.0)] if b is not None else []))
    fb = forbid.copy()
    if extra_forbid is not None: fb |= extra_forbid
    for p, r in clear_around:
        i = int(round((p[0] - ORIGIN) / ROUTE_CELL)); j = int(round((p[1] - ORIGIN) / ROUTE_CELL))
        k = int(r / ROUTE_CELL) + 1
        fb[max(j - k, 0):j + k + 1, max(i - k, 0):i + k + 1] = 0
    if HARD is not None:
        hard = HARD.copy()
        # the ends themselves (a gate, a junction on the network, a hamlet's yard) stay open
        for p in ([a] + ([b] if b is not None else [])):
            hard[np.hypot(X - p[0], Z - p[1]) < 30.0] = 0
        fb |= hard
    c = dict(CLASSES[cls])
    if gmax is not None: c["gmax"] = gmax
    s = to_node(a, n)
    if target is None:
        g = to_node(b, n)
        path = R.astar(hr, wmask, fb, roadcells, ROUTE_CELL, s, g, roadcells, c["gmax"], 1.6, c["water"] if water is None else water, 60.0, 1.0, 1.0, mult)
    else:
        path = R.astar(hr, wmask, fb, roadcells, ROUTE_CELL, s, -1, target, c["gmax"], 1.6, c["water"] if water is None else water, 0.0, 1.0, 0.0, mult)
    if len(path) == 0: return None
    return np.stack([ORIGIN + (path % n) * ROUTE_CELL, ORIGIN + (path // n) * ROUTE_CELL], 1)


def shape_path(cells, a, b, cls, lead_a=None, lead_b=None):
    """Grid path -> smooth polyline from exactly `a` to exactly `b`, resampled every 4 m."""
    pts = cells.copy()
    pts[0] = a
    if b is not None: pts[-1] = b
    pts = R.rdp(pts, 9.0 if cls == "highway" else 5.0)
    head = [np.asarray(a, float)]
    if lead_a is not None: head.append(np.asarray(a, float) + lead_a)
    tail = []
    if lead_b is not None and b is not None: tail.append(np.asarray(b, float) + lead_b)
    if b is not None: tail.append(np.asarray(b, float))
    mid = pts[1:-1] if b is not None else pts[1:]
    # drop mid points too close to the lead-ins
    keep = []
    for p in mid:
        if lead_a is not None and np.hypot(*(p - head[-1])) < 40: continue
        if tail and np.hypot(*(p - tail[0])) < 40: continue
        keep.append(p)
    poly = np.vstack(head + keep + tail) if keep else np.vstack(head + tail)
    # no spurs: a route that overshoots a lead-in and comes back would leave a U-turn in the road
    poly = R.remove_cusps(poly, 100.0, len(head), len(tail))
    poly = R.chaikin(poly, 3)
    poly = R.resample(poly, 6.0)
    poly = R.curvature_smooth(poly, CLASSES[cls]["radius"], 80, 1, 1)
    # switchbacks: the legs kept far enough apart for the grid to hold both beds (M-6, M-9)
    poly = R.separate_legs(poly, CLASSES[cls]["width"] + 26.0, 48.0, 60, 3 if lead_a is not None else 1, 3 if lead_b is not None else 1)
    poly = R.curvature_smooth(poly, CLASSES[cls]["radius"], 60, 1, 1)
    return R.resample(poly, 4.0)


def ground_along(h, pts):
    return bil(h, pts[:, 0], pts[:, 1])


def lane_crossings(pts, lanes, margin=70.0):
    """Mask of samples within `margin` of a sea lane (ships pass under here)."""
    m = np.zeros(len(pts), bool)
    for ln in lanes:
        lp = ln["points"]
        for k in range(len(lp) - 1):
            a = lp[k]; b = lp[k + 1]; ab = b - a; L2 = ab @ ab
            if L2 < 1e-9: continue
            t = np.clip(((pts - a) @ ab) / L2, 0, 1)
            d = np.hypot(*(pts - (a + ab[None] * t[:, None])).T)
            m |= d < margin
    return m


def make_profile(h, pts, cls, fixed, lanes, gmax=None):
    c = dict(CLASSES[cls])
    if gmax is not None: c["gmax"] = gmax
    g = ground_along(h, pts)
    wet = g < 0.6
    # short wet runs (coves, a shoreline wobble) are crossed on an embankment, not a bridge
    lab, nl = ndimage.label(wet)
    for k in range(1, nl + 1):
        idx = np.where(lab == k)[0]
        if len(idx) < EMBANK[cls]: wet[idx] = False
    target = np.where(wet, np.maximum(g, 0) + 6.5, np.maximum(g, 1.6))
    lower = np.where(wet, 6.5, -1e9)
    riv = river_samples(pts)
    if riv is not None:
        # rivers are crossed on a bridge: the deck clears the water by 3.4 m
        rd, rl = riv
        over = rd < 4.0
        lower = np.where(over, np.maximum(lower, rl + 3.4), lower)
        target = np.where(over, np.maximum(target, rl + 3.4), target)
    if lanes:
        under = lane_crossings(pts, lanes) & wet
        lower = np.where(under, 13.5, lower)
    target = ndimage.gaussian_filter1d(target, max(c["sigma"], 1.0), mode="nearest")
    # biased toward cuts: where the ground climbs faster than the grade allows, a road cuts into the
    # hillside (the carve makes a cutting) rather than riding a long fill or a land viaduct
    y = R.lipschitz_profile(target, 4.0, c["gmax"], fixed, lower, cut_bias=CUT_BIAS)
    y = R.smooth_profile(y, c["sigma"] * 0.7, fixed, np.where(lower > -1e8, lower, -1e9), c["gmax"], 4.0)
    # re-apply the grade limit after smoothing (tiny drift at pinned ends), keeping the clearances
    y = R.lipschitz_profile(y, 4.0, c["gmax"] * 1.02, fixed, lower)
    return y, g


# a deck this far above the ground is a viaduct; lower fills are embankments (the carve builds them)
LAND_BRIDGE = {"highway": 15.0, "road": 14.0, "track": 14.0, "street": 99.0}
CUT_BIAS = 0.62
# wet runs shorter than this many samples (4 m) are filled as an embankment (a shore track crosses
# its coves on a rubble causeway rather than a string of little bridges)
EMBANK = {"highway": 16, "road": 16, "track": 50, "street": 16}
RIVER_ABUT = 14.0          # a river bridge spans the channel plus this much of each bank
RIVER_FN = None            # (pts) -> (distance to a river channel's edge, its water level): set by main()
RIVER_MASK = None          # N x N: river channel cells (routing treats them as water to cross)


def river_samples(pts):
    if RIVER_FN is None: return None
    return RIVER_FN(pts)


def find_bridges(y, g, cls, pts=None):
    """Bridge spans: over water (the sea, a river), or where the deck stands high above the ground
    (a viaduct)."""
    wet = g < 0.6
    lab, nl = ndimage.label(wet)
    for k in range(1, nl + 1):
        idx = np.where(lab == k)[0]
        if len(idx) < EMBANK[cls]: wet[idx] = False
    high = wet | (y - g > LAND_BRIDGE[cls])
    riv = river_samples(pts) if pts is not None else None
    if riv is not None:
        # the abutments stand back from the banks (the road bed is carved flat 9 m past its edge)
        high |= riv[0] < RIVER_ABUT
    spans = []
    k = 0; n = len(y)
    while k < n:
        if high[k]:
            k0 = k
            while k < n and high[k]: k += 1
            spans.append([k0, k - 1])
        else:
            k += 1
    # merge spans with short gaps, pad each span by a sample of abutment
    merged = []
    for s in spans:
        if merged and s[0] - merged[-1][1] < 8: merged[-1][1] = s[1]
        else: merged.append(list(s))
    out = []
    for a, b in merged:
        if b - a < 2 and g[a] > 0.6 and (riv is None or riv[0][a:b + 1].min() >= RIVER_ABUT): continue
        out.append([max(a - 1, 0), min(b + 1, n - 1)])
    return out


def snap_index(n_samples, k):
    """Nearest sample index the navigation graph keeps (multiples of 3, or the last one)."""
    c = int(round(k / 3.0)) * 3
    if c >= n_samples - 1: return n_samples - 1
    return max(c, 0)


def add_road(net, h, rid, cls, pts, lanes, fixed_ends, frm, to):
    fixed = {}
    if fixed_ends[0] is not None: fixed[0] = fixed_ends[0]
    if fixed_ends[1] is not None: fixed[len(pts) - 1] = fixed_ends[1]
    y, g = make_profile(h, pts, cls, fixed, lanes, ROAD_GMAX.get(rid))
    br = find_bridges(y, g, cls, pts)
    road = {"id": rid, "class": cls, "width": CLASSES[cls]["width"], "pts": pts, "y": y, "g": g, "g0": g.copy(), "y0": y.copy(), "bridges": br, "from": frm, "to": to,
            "pinned": (fixed_ends[0] is not None, fixed_ends[1] is not None)}
    net.roads.append(road)
    return road


def nearest_sample(net, p, classes=None, exclude=()):
    best = None; bd = 1e18
    for r in net.roads:
        if classes and r["class"] not in classes: continue
        if r["id"] in exclude: continue
        d = np.hypot(*(r["pts"] - p).T)
        k = int(np.argmin(d))
        if d[k] < bd: bd = d[k]; best = (r, k)
    return best, bd


def junction_on(road, k):
    """A junction point on `road` near sample k that the nav graph keeps and that is not on a bridge."""
    n = len(road["pts"])
    k = snap_index(n, k)
    for off in range(0, 60, 3):
        for kk in (k + off, k - off):
            kk = snap_index(n, kk)
            if not any(a - 3 <= kk <= b + 3 for a, b in road["bridges"]):
                return kk
    return k


def roadcell_mask(net, n):
    m = np.zeros((n, n), np.uint8)
    for r in net.roads:
        i = np.round((r["pts"][:, 0] - ORIGIN) / ROUTE_CELL).astype(int); j = np.round((r["pts"][:, 1] - ORIGIN) / ROUTE_CELL).astype(int)
        ok = (i >= 0) & (j >= 0) & (i < n) & (j < n)
        m[j[ok], i[ok]] = 1
    return m


def stage_roads(h, towns, exits, lanes, lake_mask):
    net = Net()
    grid = route_grid(h, towns, lake_mask)
    n = grid[0].shape[0]
    tmap = {t.id: t for t in towns}
    gates = {t.id: np.asarray(t.gate, float) for t in towns}
    gy = {tid: float(bil(h, [g[0]], [g[1]])[0]) for tid, g in gates.items()}
    for tid in gy: gy[tid] = max(gy[tid], 2.0)
    gates["isola_junction"] = np.asarray(ISOLA_JUNCTION, float)
    gy["isola_junction"] = max(float(bil(h, [ISOLA_JUNCTION[0]], [ISOLA_JUNCTION[1]])[0]), 2.0)
    clear = [(g, 180.0) for g in gates.values()]

    def link(rid, cls, a_id, b_id, a=None, b=None, ya=None, yb=None, lead_a=None, lead_b=None, vias=(), water=None):
        pa = gates[a_id] if a is None else a; pb = gates[b_id] if b is None else b
        stops = [pa + (lead_a if lead_a is not None else 0)] + [np.asarray(v, float) for v in vias] + [pb + (lead_b if lead_b is not None else 0)]
        parts = []
        for s0, s1 in zip(stops[:-1], stops[1:]):
            c = route(grid, s0, s1, cls, roadcell_mask(net, n), clear_around=clear + [(pa, 300.0), (s0, 200.0), (s1, 200.0)], water=water,
                      gmax=ROAD_GMAX.get(rid))
            if c is None:
                log("ROUTE FAILED", rid); return None
            parts.append(c if not parts else c[1:])
        cells = np.vstack(parts)
        pts = shape_path(cells, pa, pb, cls, lead_a=lead_a, lead_b=lead_b)
        r = add_road(net, h, rid, cls, pts, lanes, (gy.get(a_id) if ya is None else ya, gy.get(b_id) if yb is None else yb), a_id, b_id)
        log("road", rid, cls, "%.2f km" % (len(pts) * 0.004), "bridges", len(r["bridges"]))
        return r

    # --- the ring highway joining the five towns
    ring = [("valdoro", "campo_real"), ("campo_real", "puerto_alto"), ("puerto_alto", "sarmada"),
            ("sarmada", "isola_junction"), ("isola_junction", "valdoro")]
    # (a second via at (-5400, 6400) folded the highway into a loop on the south-west hills)
    ring_vias = {("sarmada", "isola_junction"): [(-1800, 8700)]}
    for a_id, b_id in ring:
        link("ring.%s.%s" % (a_id, b_id), "highway", a_id, b_id, vias=ring_vias.get((a_id, b_id), ()))
    # --- the four spokes from the core exits
    spoke_vias = {}
    # the north spoke meets the ring in the valley below Valdoro instead of at the town gate, so
    # the gate is not a five-way knot of highways
    # the west spoke joins the ring north of the Isola junction instead of running beside it into
    # the junction (two highways side by side at different heights, M-6)
    spoke_join = {"north": ("ring.valdoro.campo_real", (-830.0, -4000.0)),
                  "west": ("ring.sarmada.isola_junction", (-7298.0, 3125.0))}
    byid = {r["id"]: r for r in net.roads}
    for name, dest in (("north", "valdoro"), ("east", "campo_real"), ("south", "sarmada"), ("west", "isola_junction")):
        ex = exits[name]
        p = np.asarray(ex["points"], float)
        last = p[-1]; prev = p[-8]
        tan = T.unit(last[[0, 2]] - prev[[0, 2]])
        if name in spoke_join and spoke_join[name][0] in byid:
            pr = byid[spoke_join[name][0]]
            k = junction_on(pr, int(np.argmin(np.hypot(*(pr["pts"] - np.asarray(spoke_join[name][1])).T))))
            J = pr["pts"][k]; yJ = float(pr["y"][k])
            t = pr["pts"][min(k + 1, len(pr["pts"]) - 1)] - pr["pts"][max(k - 1, 0)]
            nrm = T.perp(T.unit(t))
            if nrm @ (last[[0, 2]] - J) < 0: nrm = -nrm
            r = link("spoke.%s" % name, "highway", "core_" + name, dest, a=last[[0, 2]], ya=float(last[1]), lead_a=tan * 160.0,
                     b=J, yb=yJ, lead_b=nrm * 40.0)
            if r is not None:
                r["join_end"] = {"road": pr["id"], "index": int(k)}
            continue
        link("spoke.%s" % name, "highway", "core_" + name, dest, a=last[[0, 2]], ya=float(last[1]), lead_a=tan * 160.0,
             vias=spoke_vias.get(name, ()))
    # --- the causeway to Isola Serena
    # straight over the strait at its narrows (it used to run 2 km down the shore to a later crossing);
    # it leaves the ring where the ring turns away from the strait, not at the junction (the two
    # shared their first 240 m side by side, one climbing, one descending: the washboard of M-6)
    ring_w = byid.get("ring.isola_junction.valdoro") or next((r for r in net.roads if r["id"] == "ring.isola_junction.valdoro"), None)
    if ring_w is not None:
        k = junction_on(ring_w, int(np.argmin(np.hypot(*(ring_w["pts"] - np.array([-7440.0, 2760.0])).T))))
        J = ring_w["pts"][k]; yJ = float(ring_w["y"][k])
        t = ring_w["pts"][min(k + 1, len(ring_w["pts"]) - 1)] - ring_w["pts"][max(k - 1, 0)]
        nrm = T.perp(T.unit(t))
        if nrm @ (gates["isola_serena"] - J) < 0: nrm = -nrm
        r = link("causeway.isola_serena", "road", "isola_junction", "isola_serena", a=J, ya=yJ, lead_a=nrm * 30.0, water=2.5)
        if r is not None: r["join"] = {"road": ring_w["id"], "index": int(k)}
    else:
        link("causeway.isola_serena", "road", "isola_junction", "isola_serena", water=2.5)
    net.gy = gy
    return net


# the gravel shoulder beyond the carriageway (OuterRoads.SHOULDER): part of the ribbon
SHOULDER = {"highway": 1.6, "road": 1.1, "track": 0.7, "street": 0.0}
# how far a plot or a prop keeps from a navigation road's ribbon; the town streets' own plots front
# them at their setback
PLOT_ROAD_MARGIN = 1.0
PLOT_STREET_MARGIN = 0.25


def road_clearance(r):
    """Half width a plot must keep from road r's centre line."""
    if r["class"] == "street": return r["width"] * 0.5 + PLOT_STREET_MARGIN
    return r["width"] * 0.5 + SHOULDER[r["class"]] + PLOT_ROAD_MARGIN


def _seg_arrays(roads):
    A = []; B = []; H = []; I = []
    for r in roads:
        P = r["pts"]; c = road_clearance(r)
        A.append(P[:-1]); B.append(P[1:]); H.append(np.full(len(P) - 1, c)); I += [r["id"]] * (len(P) - 1)
    return np.vstack(A), np.vstack(B), np.concatenate(H), I


def poly_road_overlap(poly, A, B, H):
    """How far (m) the convex quad `poly` reaches into any road clearance band (<= 0: clear), and
    the index of the worst segment."""
    c = poly.mean(0); R0 = float(np.max(np.hypot(*(poly - c).T)))
    lo = np.minimum(A, B) - H[:, None]; hi = np.maximum(A, B) + H[:, None]
    m = np.where((c[0] + R0 > lo[:, 0]) & (c[0] - R0 < hi[:, 0]) & (c[1] + R0 > lo[:, 1]) & (c[1] - R0 < hi[:, 1]))[0]
    if len(m) == 0: return -1e9, -1
    best = -1e9; bi = -1
    for i in m:
        d = T.seg_seg_dist(A[i], B[i], poly[0], poly[1])
        for k in (1, 2, 3):
            d = min(d, T.seg_seg_dist(A[i], B[i], poly[k], poly[(k + 1) % 4]))
        if T.point_in_poly(A[i], poly) or T.point_in_poly(B[i], poly): d = 0.0
        if H[i] - d > best: best = H[i] - d; bi = i
    return best, bi


def clear_plots_off_roads(towns, roads):
    """C-3: no building stands in a navigation road's ribbon. Whatever still reaches into one after
    routing (a road smoothed round a corner, a hamlet's lane) is dropped; a town-wall piece the
    road passes through becomes the road's gateway (the wall is cut back to the passage)."""
    A, B, H, I = _seg_arrays(roads)
    dropped = 0
    for t in towns:
        keep = []
        for p in t.plots:
            over, i = poly_road_overlap(p["_poly"], A, B, H)
            if over > 0.0:
                dropped += 1
                log("plot %s (%s) cleared off %s: %.1f m into its ribbon" % (p["id"], p["kind"], I[i], over))
                continue
            keep.append(p)
        if len(keep) != len(t.plots):
            t.plots = keep
            t._plot_cells = {}
            for p in keep:
                xmin, zmin = p["_poly"].min(0); xmax, zmax = p["_poly"].max(0)
                for cc in t._cells(xmin, zmin, xmax, zmax): t._plot_cells.setdefault(cc, []).append(p["_poly"])
    return dropped


# ------------------------------------------------------------------ stage 5: streets, hamlets, secondary roads, tracks
HAMLET_NAMES = {
    "puerto": ["Casal da Ribeira", "Vila Nova do Sal", "Quinta das Garças", "Porto Velho"],
    "campo": ["Molino Alto", "Cortijo Blanco", "Casas del Trigo", "Villalba", "Granja Real", "Torre del Rio"],
    "valdoro": ["Borgo Pini", "Malga Alta", "Rocca Bruna", "Fontana Fredda"],
    "sarmada": ["Ksar Amane", "Douar Tamri", "Oasis Zagora", "Aït Lmal"],
    "isola": ["Punta Rasa", "Cala Serena", "Marina Piccola", "Faro Vecchio"],
}


def export_main_streets(net, h, towns, gy):
    """Every town's main street becomes a road from its gate (the highway junction) to its plaza."""
    for t in towns:
        st = t.streets[t.main_street]
        pts = st["pts"]; y = st["y"]
        g = np.asarray(t.gate, float)
        if np.hypot(*(pts[-1] - g)) < np.hypot(*(pts[0] - g)):
            pts = pts[::-1]; y = y[::-1]
        pts = pts.copy(); pts[0] = g
        seg = np.hypot(*np.diff(pts, axis=0).T); cum = np.concatenate([[0], np.cumsum(seg)])
        P = R.resample(pts, 4.0)
        s2 = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(P, axis=0).T))])
        yy = np.interp(s2 / s2[-1] * cum[-1], cum, y)
        # ramp from the gate height into the town surface over the first 80 m
        w = np.clip(s2 / 80.0, 0, 1)
        yy = gy[t.id] * (1 - w) + yy * w
        yy = R.lipschitz_profile(yy, 4.0, 0.16, {0: gy[t.id]}, None)
        g_along = ground_along(h, P)
        road = {"id": "street.%s.main" % t.id, "class": "street", "width": st["width"], "pts": P, "y": yy, "g": g_along,
                "bridges": [], "from": "gate", "to": t.id, "town": t.id, "pinned": (True, True)}
        net.roads.append(road)


def branch(net, grid, h, lanes, rid, cls, p, frm, to, join_classes=("highway", "road"), y_end=None, straight=False):
    """A road from the network (a junction sample) to the point p."""
    hr, water, forbid, X, Z = grid
    n = hr.shape[0]
    rc = np.zeros((n, n), np.uint8)
    for r in net.roads:
        if r["class"] not in join_classes: continue
        ok = np.ones(len(r["pts"]), bool)
        for a, b in r["bridges"]: ok[max(a - 6, 0):b + 7] = False
        i = np.round((r["pts"][ok, 0] - ORIGIN) / ROUTE_CELL).astype(int); j = np.round((r["pts"][ok, 1] - ORIGIN) / ROUTE_CELL).astype(int)
        m = (i >= 0) & (j >= 0) & (i < n) & (j < n)
        rc[j[m], i[m]] = 1
    if straight:
        (r, k), d = nearest_sample(net, p, join_classes)
        cells = np.vstack([r["pts"][k], p])
    else:
        cells = route(grid, p, None, cls, rc, target=rc, clear_around=[(p, 150.0)], gmax=ROAD_GMAX.get(rid))
        if cells is None:
            log("BRANCH FAILED", rid); return None
        cells = cells[::-1]
    (r, k), d = nearest_sample(net, cells[0], join_classes)
    k = junction_on(r, k)
    J = r["pts"][k]; yJ = float(r["y"][k])
    t = r["pts"][min(k + 1, len(r["pts"]) - 1)] - r["pts"][max(k - 1, 0)]
    nrm = T.perp(T.unit(t))
    if nrm @ (p - J) < 0: nrm = -nrm
    cells = cells.copy(); cells[0] = J
    pts = shape_path(cells, J, p, cls, lead_a=nrm * 30.0)
    road = add_road(net, h, rid, cls, pts, lanes, (yJ, y_end), frm, to)
    road["join"] = {"road": r["id"], "index": int(k)}
    return road


def pick_hamlets(h, net, towns, want=14, seed=5):
    rng = np.random.default_rng(seed)
    ctx = LY.Ctx(h)
    cands = []
    for r in net.roads:
        if r["class"] != "highway": continue
        P = r["pts"]
        for k in range(60, len(P) - 60, 90):
            t = T.unit(P[k + 1] - P[k - 1]); nrm = T.perp(t)
            for side in (1, -1):
                off = rng.uniform(140, 320)
                c = P[k] + nrm * side * off
                hh = ctx.H(*c, True)
                if hh < 4 or hh > 800: continue
                if math.hypot(*ctx.grad(*c, 40.0)) > 0.10: continue
                cands.append(c)
    # a few remote hamlets away from the highways
    rng.shuffle(cands)
    chosen = []
    remote = [np.asarray(c, float) for c in [(7400, -6900), (-3300, -8200), (5200, 6200), (-6500, 5200), (-5600, -5300), (9000, -3500)]]
    order = remote + cands
    for c in order:
        best = find_site(ctx, c, 400, 4, 850, 50.0, (0.0, 0.10))
        if best is None: continue
        c = best
        if min((np.hypot(*(c - t.center)) - t.radius for t in towns)) < 1300: continue
        if max(abs(c[0]), abs(c[1])) < 2200: continue
        if any(np.hypot(*(c - q)) < 1800 for q in chosen): continue
        (r, k), d = nearest_sample(net, c)
        if d < 60: continue
        chosen.append(c)
        if len(chosen) >= want: break
    return chosen


def stage_extras(h, net, towns, lanes, lake_mask, gy):
    grid = route_grid(h, towns, lake_mask)
    ctx = LY.Ctx(h)
    export_main_streets(net, h, towns, gy)
    hamlets = []
    sites = pick_hamlets(h, net, towns)
    used = {k: 0 for k in HAMLET_NAMES}
    for k, c in enumerate(sites):
        near = min(towns, key=lambda t: np.hypot(*(c - t.center)))
        style = near.style
        names = HAMLET_NAMES[style]
        name = names[used[style] % len(names)]; used[style] += 1
        hid = "hamlet_" + name.lower().replace(" ", "_").replace("'", "").replace("ï", "i").replace("ç", "c")
        if used[style] > len(names):          # the names ran out: a second Casas del Trigo is "Casas del Trigo II"
            name += " II"; hid += "_2"
        (r0, k0), d = nearest_sample(net, c, ("highway", "road"))
        kind = "farmstead" if style == "campo" or (style != "isola" and k % 3 == 1) else "village"
        road = branch(net, grid, h, lanes, "road.%s" % hid, "road", c, r0["id"], hid, straight=d < 450)
        if road is None: continue
        ht = T.Town(hid, name, style, c, 120, False, 5000 + k)
        ht.kind = "hamlet"; ht.hamlet = True
        P = road["pts"]
        # the hamlet's lane: the last ~160 m of its access road
        m = max(len(P) - 40, 0)
        ht.gate = P[m]
        # the lane is the access road itself: the plots keep clear of its ribbon (carriageway +
        # shoulder) by a metre, so the street they line is laid out that wide
        ht.main_street = ht.add_street("main", road["width"] + 2.0 * (SHOULDER[road["class"]] + 1.0) + 0.2, P[m:])
        ht.streets[ht.main_street]["y"] = road["y"][m:]
        ht.streets[ht.main_street]["rule"] = ("road", None)
        ht.plaza = P[-1]
        land = LY.land_fn(ctx, 1.5)
        fl = lambda: int(ht.rng.integers(1, 3))
        if kind == "farmstead":
            tdir = T.unit(P[-1] - P[-5])
            LY._farm(ht, P[-1] + tdir * 30, math.atan2(tdir[1], tdir[0]), land)
            ht.line_plots(ht.main_street, 1, None, (8, 12), (8, 12), land, start=6, floors=fl, kinds=["house", "barn", "granary"], max_plots=4)
        else:
            for side in (1, -1):
                ht.line_plots(ht.main_street, side, None, (6, 10), (8, 12), land, start=6, floors=fl,
                              kinds=["house"] * 5 + ["barn", "shop"], max_plots=5)
            tdir = T.unit(P[-1] - P[-5])
            if ht.rng.random() < 0.6:
                ht.try_plot("church", P[-1] + tdir * 16, -tdir, 9, 15, 1, [], land, check_bounds=False)
        hamlets.append(ht)
        log("hamlet", hid, style, kind, "plots", len(ht.plots))
    # from here on new roads keep off the hamlets' plots too
    set_hard_forbid(towns + hamlets)
    # secondary roads and tracks to the landmarks
    pois = []
    def poi(pid, kind, around, rad, hmin, hmax, cls, slope=(0.0, 0.2)):
        p = find_site(ctx, around, rad, hmin, hmax, 50.0, slope)
        if p is None: log("POI not found", pid); return
        pois.append({"id": pid, "kind": kind, "pos": p, "cls": cls})
    poi("dam", "gatehouse", (L.DAM[0], L.DAM[1] + 120), 100, 0, 2000, "road", (0.0, 0.6))
    poi("alpine_hut", "hut", (-600, -7700), 900, 780, 1000, "track")
    poi("summit_view", "viewpoint", (1200, -8600), 1200, 950, 1250, "track", (0.0, 0.35))
    poi("pass_chapel", "chapel", (4300, -6700), 900, 700, 1000, "track")
    poi("north_cape", "lighthouse", (7600, -8300), 1200, 10, 120, "track", (0.0, 0.3))
    poi("canyon_overlook", "viewpoint", (-1500, 6300), 900, 150, 400, "track")
    poi("mesa_top", "viewpoint", (4700, 6100), 1200, 200, 450, "track")
    poi("west_cliffs", "viewpoint", (-6900, -1500), 900, 30, 300, "track")
    poi("castle_hill", "castle_ruin", (-4200, 3300), 1200, 120, 400, "track", (0.0, 0.25))
    poi("sw_cape", "lighthouse", (-5400, 8300), 1200, 8, 150, "track", (0.0, 0.3))
    poi("se_watchtower", "watchtower", (8200, 6200), 1200, 20, 250, "track")
    poi("nw_monastery", "monastery", (-5200, -6600), 1200, 250, 700, "road")
    for q in pois:
        road = branch(net, grid, h, lanes, "%s.%s" % (q["cls"], q["id"]), q["cls"], q["pos"], "network", q["id"],
                      join_classes=("highway", "road", "track"))
        if road is not None:
            q["pos3"] = [float(q["pos"][0]), float(road["y"][-1]), float(q["pos"][1])]
            log("poi", q["id"], q["cls"], "%.2f km" % (len(road["pts"]) * 0.004))
    # a few more country roads so the countryside is a network, not a star
    links = [("road.east_coast", "road", (7800, -3300)), ("road.plains_north", "road", (3600, -3200)),
             ("road.south_plateau", "road", (-2600, 4200)), ("road.west_hills", "road", (-4800, -1200)),
             ("track.desert_south", "track", (5600, 8300)), ("track.north_range", "track", (-2400, -7200))]
    for rid, cls, p in links:
        p = find_site(ctx, p, 800, 5, 900, 50.0, (0.0, 0.2))
        if p is None: continue
        road = branch(net, grid, h, lanes, rid, cls, p, "network", rid.split(".")[1], join_classes=("highway", "road", "track"))
        if road is not None: log("link", rid, "%.2f km" % (len(road["pts"]) * 0.004))
    # country roads between points of the network (loops, coasts, the lagoon shore)
    country = [
        ("road.lagoon_north_east", "road", (-150, -1900), (1700, -700)),
        ("road.lagoon_south_east", "road", (1750, 900), (500, 1950)),
        ("road.lagoon_south_west", "road", (400, 1950), (-1850, 600)),
        ("road.lagoon_north_west", "road", (-1850, 400), (-500, -1900)),
        ("road.east_coast_north", "road", (6900, 700), (8600, -5200)),
        ("road.plains_loop", "road", (3200, -1200), (4300, -4200)),
        ("road.plains_east", "road", (6600, -1400), (8800, -1500)),
        ("road.south_coast_east", "road", (3600, 8700), (7600, 6800)),
        ("road.plateau_cross", "road", (-900, 5200), (4600, 5600)),
        # (the NW coast is a 200-400 m sea cliff: no coast road there, a lane out to the clifftops)
        ("road.northwest", "road", (-3800, -3600), (-5300, -4000)),
        ("track.valdoro_head", "track", (-1700, -5700), (-2300, -7300)),
        ("track.canyon_floor", "track", (-2600, 4800), (-800, 7400)),
        ("track.southwest_hills", "track", (-4600, 5200), (-6300, 3300)),
        ("road.north_foothills", "road", (2600, -4300), (5300, -4100)),
    ]
    for rid, cls, a, b in country:
        road = link_points(net, grid, h, lanes, rid, cls, np.asarray(a, float), np.asarray(b, float))
        if road is not None: log("country", rid, "%.2f km" % (len(road["pts"]) * 0.004))
    return hamlets, pois


def link_points(net, grid, h, lanes, rid, cls, a, b, snap=500.0):
    """A road between two points; an end within `snap` m of the network starts exactly on a
    junction sample of it."""
    ends = []
    ctx = LY.Ctx(h)
    for p in (a, b):
        (r, k), d = nearest_sample(net, p, ("highway", "road", "track"))
        if d >= snap:
            q = find_site(ctx, p, 700, 4.0, 900, 25.0, (0.0, 0.2))
            if q is not None: p = q
        if d < snap:
            k = junction_on(r, k)
            ends.append((r["pts"][k].copy(), float(r["y"][k]), r, k))
        else:
            ends.append((p, None, None, None))
    pa, ya, ra, ka = ends[0]; pb, yb, rb, kb = ends[1]
    def lead(r, k, p, other):
        if r is None: return None
        t = r["pts"][min(k + 1, len(r["pts"]) - 1)] - r["pts"][max(k - 1, 0)]
        nrm = T.perp(T.unit(t))
        return (nrm if nrm @ (other - p) > 0 else -nrm) * 30.0
    la = lead(ra, ka, pa, pb); lb = lead(rb, kb, pb, pa)
    # routed between the lead-in points, so the road leaves and meets its parents square
    qa = pa + la if la is not None else pa; qb = pb + lb if lb is not None else pb
    cells = route(grid, qa, qb, cls, roadcell_mask(net, grid[0].shape[0]), clear_around=[(pa, 200.0), (pb, 200.0)], gmax=ROAD_GMAX.get(rid))
    if cells is None:
        log("LINK FAILED", rid); return None
    pts = shape_path(cells, pa, pb, cls, lead_a=la, lead_b=lb)
    road = add_road(net, h, rid, cls, pts, lanes, (ya, yb), "network", "network")
    if ra is not None: road["join"] = {"road": ra["id"], "index": int(ka)}
    if rb is not None: road["join_end"] = {"road": rb["id"], "index": int(kb)}
    return road

# ------------------------------------------------------------------ stage 6: carve, finalise, camps, export
# the carve: exact (flat across, the profile along) within half width + CARVE_EXACT, blending into
# the land over CARVE_BLEND beyond. The runtime surface at a point mixes data nodes up to ~18 m away
# (bilinear 12.5 m data on a 6.25 m lattice), so the exact zone reaches well past the carriageway.
CARVE_EXACT = 9.0
CARVE_BLEND = 40.0
# under a deck the ground stays BRIDGE_CLEAR below it, except toward the abutments: the clearance
# ramps in from 0 at BRIDGE_ABUT metres past the abutment at BRIDGE_RAMP per metre, so the ground
# the approach samples stand on is never dug away (the old 3x3-cell cut left a 4 m cliff at every
# bridge end, C-1)
BRIDGE_CLEAR = 4.0
BRIDGE_ABUT = 8.0
BRIDGE_RAMP = 0.25
# profile <-> carve consistency passes (M-6, M-9): where two roads (a junction, a crossing, a
# parallel pair, the legs of a hairpin) ask the 12.5 m grid for different heights within reach of
# each other, the grid holds a mix; each pass re-fits the profiles to what the grid holds (within
# their grade limits) until the ground under every road is its profile
RELAX_PASSES = 30
RELAX_TOL = 0.05
RELAX_OVER = 0.6


def _bridge_mask(r):
    br = np.zeros(len(r["pts"]), bool)
    for a, b in r["bridges"]: br[a:b + 1] = True
    return br


def carve_net(h, net, rivers):
    """Carve every road into `h` (bridge spans excepted), lower the ground under the decks, recut
    the river channels. Returns (h2, dist to the nearest carved road, its half width)."""
    dist = np.full(h.shape, 1e9); yt = np.zeros(h.shape); hw = np.zeros(h.shape)
    for r in net.roads:
        P = r["pts"]; y = r["y"]
        ok = np.ones(len(P) - 1, np.uint8)
        for a, b in r["bridges"]: ok[max(a, 0):b] = 0
        R.carve_roads(h, ORIGIN, STEP, P[:, 0].copy(), P[:, 1].copy(), y.astype(np.float64), np.full(len(P), r["width"] * 0.5), ok,
                      CARVE_EXACT, CARVE_BLEND, dist, yt, hw)
    h2, w = R.apply_carve(h, dist, yt, hw, CARVE_EXACT, CARVE_BLEND)
    # under the decks: the ground at most (deck - clearance), the clearance ramping in from the
    # abutments; only cells nearer the deck than any carved road (a road under a bridge keeps its bed)
    db = np.full(h.shape, 1e9); ytb = np.zeros(h.shape); hwb = np.zeros(h.shape)
    for r in net.roads:
        P = r["pts"]; y = r["y"]
        for a, b in r["bridges"]:
            if b <= a: continue
            seg = np.hypot(*np.diff(P[a:b + 1], axis=0).T)
            s = np.concatenate([[0], np.cumsum(seg)])
            from_end = np.minimum(s, s[-1] - s)
            c = np.clip((from_end - BRIDGE_ABUT) * BRIDGE_RAMP, 0.0, BRIDGE_CLEAR)
            Q = P[a:b + 1]
            R.carve_roads(h2, ORIGIN, STEP, Q[:, 0].copy(), Q[:, 1].copy(), (y[a:b + 1] - c).astype(np.float64),
                          np.full(b - a + 1, r["width"] * 0.5 + 1.0), np.ones(b - a, np.uint8), 0.0, 13.0, db, ytb, hwb)
    under = (db < hwb + 13.0) & (db < dist)
    h2 = np.where(under, np.minimum(h2, ytb), h2)
    # the river channels are cut again (the carve's blend may have filled them next to a bridge),
    # but not into a road's own bed: the rivers are bridged with the abutments clear of the banks
    hr = recarve_rivers(h2, rivers, net)
    road_bed = (dist < hw + CARVE_EXACT + 2.0) & ~under
    h2 = np.where(road_bed, h2, hr)
    return h2, dist, hw


def relax_profiles(h2, flat, micro, net):
    """Fit every road's profile to the surface the grid now holds (bridge decks and pinned ends
    stay), within the road's grade limit. Returns the worst |surface - profile| before the fit."""
    byid = {r["id"]: r for r in net.roads}
    worst = 0.0; worst_at = None
    for r in net.roads:
        P = r["pts"]; y = r["y"]; n = len(P)
        s = surface_at(h2, flat, micro, P[:, 0], P[:, 1])
        br = _bridge_mask(r)
        # the approach samples next to a deck keep the deck's ramp
        near = br.copy()
        for a, b in r["bridges"]:
            near[max(a - 2, 0):min(b + 3, n)] = True
        dev = np.abs(s - y); dev[near] = 0.0
        k = int(np.argmax(dev))
        if dev[k] > worst: worst = float(dev[k]); worst_at = (r["id"], k)
        fixed = {int(k): float(y[k]) for k in np.where(near)[0]}
        for end, key in ((0, "join"), (n - 1, "join_end")):
            if key in r and r[key]["road"] in byid:
                p = byid[r[key]["road"]]; fixed[end] = float(p["y"][r[key]["index"]])
            elif r.get("pinned", (True, True))[0 if end == 0 else 1]:
                fixed[end] = float(y[end])
        # over-relaxed a little: two roads pulling on each other's ground meet in fewer passes
        target = np.where(near, y, s + RELAX_OVER * (s - y))
        c = CLASSES[r["class"]]
        g = ROAD_GMAX.get(r["id"], c["gmax"])
        r["y"] = R.lipschitz_profile(target, 4.0, g, fixed, None)
    return worst, worst_at


def stage_carve(h, net, flat, rivers, micro):
    for it in range(RELAX_PASSES + 1):
        h2, dist, hw = carve_net(h, net, rivers)
        fm = np.clip(1.0 - (dist - (hw + 5.0)) / 10.0, 0, 1)
        fl = np.round(np.clip(np.maximum(flat, fm), 0, 1) * 255) / 255
        if it == RELAX_PASSES: break
        worst, at = relax_profiles(h2.astype(np.float32).astype(np.float64), fl, micro, net)
        log("carve pass %d: worst ground/profile mismatch %.2f m at %s" % (it, worst, at))
        if worst < RELAX_TOL: break
    flat[:] = np.maximum(flat, fm)
    return h2


def finalise_heights(h, flat, micro, net, towns):
    """Everything that stands on the ground takes the runtime surface's height."""
    for r in net.roads:
        P = r["pts"]
        gs = surface_at(h, flat, micro, P[:, 0], P[:, 1])
        br = np.zeros(len(P), bool)
        for a, b in r["bridges"]: br[a:b + 1] = True
        y = np.where(br, r["y"], gs)
        # junction samples keep their parent's exact height (set below)
        r["y"] = y
        r["g"] = gs
    byid = {r["id"]: r for r in net.roads}
    for r in net.roads:
        if "join" in r:
            p = byid[r["join"]["road"]]; k = r["join"]["index"]
            r["pts"][0] = p["pts"][k]; r["y"][0] = p["y"][k]
        if "join_end" in r:
            p = byid[r["join_end"]["road"]]; k = r["join_end"]["index"]
            r["pts"][-1] = p["pts"][k]; r["y"][-1] = p["y"][k]
    # ring / spoke ends meeting at the gates: all share the first road's gate sample
    gate_pt = {}
    for r in net.roads:
        for end in (0, -1):
            key = (round(float(r["pts"][end][0]), 1), round(float(r["pts"][end][1]), 1))
            if key in gate_pt:
                r["y"][end] = gate_pt[key]
            else:
                gate_pt[key] = float(r["y"][end])
    for t in towns:
        for st in t.streets:
            P = st["pts"]
            st["pts3"] = np.stack([P[:, 0], surface_at(h, flat, micro, P[:, 0], P[:, 1]), P[:, 1]], 1)
        for p in t.plots:
            poly = p["_poly"]
            q = np.vstack([poly, poly.mean(0)[None], 0.5 * (poly + np.roll(poly, 1, 0))])
            g = surface_at(h, flat, micro, q[:, 0], q[:, 1])
            p["y"] = round(float(g.max()), 2)
            p["ground_min"] = round(float(g.min()), 2)
        if t.port is not None:
            b = np.asarray(t.port["berth"], float)
            t.port = {"berth": [round(float(b[0]), 2), 0.0, round(float(b[1]), 2)], "heading_deg": round(float(t.port["heading_deg"]), 1)}
        if t.plaza is not None:
            pz = np.asarray(t.plaza, float)
            t.plaza = [round(float(pz[0]), 2), round(float(surface_at(h, flat, micro, [pz[0]], [pz[1]])[0]), 2), round(float(pz[1]), 2)]


def pick_camps(h, net, towns, flat, micro, seed=17):
    rng = np.random.default_rng(seed)
    ctx = LY.Ctx(h)
    camps = []
    settled = [(t.center, t.radius + 900) for t in towns]
    hw = [r for r in net.roads if r["class"] == "highway"]
    tries = 0
    while len([c for c in camps if c["kind"] == "bandit"]) < 10 and tries < 4000:
        tries += 1
        r = hw[int(rng.integers(0, len(hw)))]
        k = int(rng.integers(20, len(r["pts"]) - 20))
        if any(a - 10 <= k <= b + 10 for a, b in r["bridges"]): continue
        P = r["pts"]; t = T.unit(P[k + 1] - P[k - 1]); nrm = T.perp(t) * (1 if rng.random() < 0.5 else -1)
        c = P[k] + nrm * rng.uniform(120, 260)
        hh = ctx.H(*c)
        if hh < 5 or math.hypot(*ctx.grad(*c, 25.0)) > 0.15: continue
        if any(np.hypot(*(c - q)) < rr for q, rr in settled): continue
        (rr_, kk), d = nearest_sample(net, c)
        if d < 90: continue
        if any(np.hypot(c[0] - q["pos"][0], c[1] - q["pos"][2]) < 1500 for q in camps): continue
        face = P[k] - c
        y = float(surface_at(h, flat, micro, [c[0]], [c[1]])[0])
        camps.append({"id": "camp.bandit.%d" % len(camps), "kind": "bandit", "pos": [round(float(c[0]), 2), round(y, 2), round(float(c[1]), 2)],
                      "facing_deg": round(math.degrees(math.atan2(face[0], face[1])), 1)})
    # pirate coves: low coast far from towns and roads, facing the sea
    land = h > 0.5
    coast = land & ~ndimage.binary_erosion(land, iterations=2)
    js, is_ = np.where(coast)
    order = rng.permutation(len(js))
    pir = 0
    for o in order:
        if pir >= 4: break
        j, i = js[o], is_[o]
        c = np.array([ORIGIN + i * STEP, ORIGIN + j * STEP])
        if max(abs(c[0]), abs(c[1])) < 3000: continue
        if h[j, i] > 5 or any(np.hypot(*(c - q)) < rr + 1600 for q, rr in settled): continue
        (rr_, kk), d = nearest_sample(net, c)
        if d < 600: continue
        if any(np.hypot(c[0] - q["pos"][0], c[1] - q["pos"][2]) < 4000 for q in camps if q["kind"] == "pirate"): continue
        g = ctx.grad(*c, 25.0)
        sea = -T.unit(g) if np.hypot(*g) > 1e-4 else np.array([1.0, 0.0])
        c2 = c - sea * 25
        if ctx.H(*c2) < 1.5: continue
        y = float(surface_at(h, flat, micro, [c2[0]], [c2[1]])[0])
        camps.append({"id": "camp.pirate.%d" % pir, "kind": "pirate", "pos": [round(float(c2[0]), 2), round(y, 2), round(float(c2[1]), 2)],
                      "facing_deg": round(math.degrees(math.atan2(sea[0], sea[1])), 1)})
        pir += 1
    return camps


def lake_fill(h):
    """The mountain lake: water fills the basin up to 1.5 m below its spill level (the dam wall
    across the outlet gorge counts as ground). Returns (level, mask over the grid, shore polygon);
    the polygon runs 1 m above the water so the mesh edge tucks under the banks."""
    from skimage import measure
    lx, lz, lr, ll = L.LAKE
    r = 1600.0
    i0 = int((lx - r - ORIGIN) / STEP); j0 = int((lz - r - ORIGIN) / STEP); n = int(2 * r / STEP)
    sub = h[j0:j0 + n, i0:i0 + n].astype(np.float64).copy()
    X = ORIGIN + (np.arange(n) + i0) * STEP; Z = ORIGIN + (np.arange(n) + j0) * STEP
    XX, ZZ = np.meshgrid(X, Z)
    ddx = XX - L.DAM[0]
    sub[(np.abs(ddx) <= 145) & (np.abs(ZZ - (L.DAM[1] - ddx * ddx / 2200.0)) < 9)] = 1e4
    ci = int((lx - X[0]) / STEP); cj = int((lz - Z[0]) / STEP)
    dist = np.hypot(XX - lx, ZZ - lz)

    def region(level):
        lab, _ = ndimage.label(sub < level)
        k = lab[cj, ci]
        return (lab == k) if k else None
    lo, hi = float(sub[cj, ci]), ll
    for _ in range(32):
        m = (lo + hi) * 0.5; reg = region(m)
        if reg is None or (reg & (dist > 1300)).any(): hi = m
        else: lo = m
    level = round(lo - 1.5, 2)
    reg = region(level + 1.0)
    field = np.where(ndimage.binary_dilation(reg, iterations=2), sub, level + 50.0)
    best = None
    for c in measure.find_contours(field, level + 1.0):
        if best is None or len(c) > len(best): best = c
    pts = np.stack([X[0] + best[:, 1] * STEP, Z[0] + best[:, 0] * STEP], 1)
    pts = R.rdp(pts, 5.0)
    mask = np.zeros(h.shape, np.uint8)
    mask[j0:j0 + n, i0:i0 + n] = region(level)
    log("lake level %.1f m (spill %.1f), %.2f km2, shore %d points" % (level, lo, mask.sum() * STEP * STEP / 1e6, len(pts)))
    return level, mask, [[round(float(p[0]), 1), round(float(p[1]), 1)] for p in pts]


def recarve_rivers(h, rivers, net):
    """The road carve's blend may have filled a river channel next to a bridge: cut the channel
    (only its bed and banks) again, lowering the ground only."""
    dist = np.full(h.shape, 1e9); yt = np.zeros(h.shape); hw = np.zeros(h.shape)
    for rv in rivers:
        P = rv["pts"]
        R.carve_roads(h, ORIGIN, STEP, P[:, 0].copy(), P[:, 1].copy(), rv["bed"].astype(np.float64), rv["width"] * 0.5,
                      np.ones(len(P) - 1, np.uint8), 0.5, 5.0, dist, yt, hw)
    hc, w = R.apply_carve(h, dist, yt, hw, 0.5, 5.0)
    return np.minimum(h, hc)


def export(h, flat, micro, splat, aux, tint, rmask, net, towns, hamlets, lanes, camps, pois, harbour, lake, feat=None, rivers=()):
    os.makedirs(OUT, exist_ok=True)
    h.astype("<f4").tofile(os.path.join(OUT, "height.f32"))
    Image.fromarray(np.round(splat * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "splat.png"), optimize=True)
    Image.fromarray(np.round(aux * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "aux.png"), optimize=True)
    t8 = np.round(np.clip(tint[::2, ::2] * 0.5, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(t8, "RGB").save(os.path.join(OUT, "tint.png"), optimize=True)
    Image.fromarray(rmask, "L").save(os.path.join(OUT, "roads.png"), optimize=True)
    Image.fromarray(micro, "L").save(os.path.join(OUT, "micro.png"))
    if feat is not None:
        Image.fromarray(np.round(np.clip(feat, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "feat.png"), optimize=True)
    # min / max height per 200 m quadtree leaf over [-12800, 12800] (128 x 128) for the terrain LOD
    mm = np.zeros((128, 128, 2), np.float32)
    for j in range(128):
        j0 = max(int((j * 200 - 12800 - ORIGIN) / STEP) - 1, 0); j1 = min(int(((j + 1) * 200 - 12800 - ORIGIN) / STEP) + 2, N)
        for i in range(128):
            i0 = max(int((i * 200 - 12800 - ORIGIN) / STEP) - 1, 0); i1 = min(int(((i + 1) * 200 - 12800 - ORIGIN) / STEP) + 2, N)
            if j0 >= j1 or i0 >= i1: mm[j, i] = (-40.0, -40.0); continue
            blk = h[j0:j1, i0:i1]
            mm[j, i] = (blk.min() - MICRO_AMP, blk.max() + MICRO_AMP)
    mm.astype("<f4").tofile(os.path.join(OUT, "minmax.f32"))
    def r2(v): return round(float(v), 2)
    roads = []
    for r in net.roads:
        pts = [[r2(p[0]), r2(y), r2(p[1])] for p, y in zip(r["pts"], r["y"])]
        e = {"id": r["id"], "class": r["class"], "width": r["width"], "points": pts, "bridges": [[int(a), int(b)] for a, b in r["bridges"]],
             "from": r["from"], "to": r["to"]}
        if "join" in r: e["join"] = r["join"]
        if "join_end" in r: e["join_end"] = r["join_end"]
        if "town" in r: e["town"] = r["town"]
        roads.append(e)
    ports = [{"id": "port.core", "town": "core", "berth": [r2(harbour[0]), 0.0, r2(harbour[1])], "heading_deg": 90.0}]
    for t in towns:
        if t.port: ports.append({"id": "port." + t.id, "town": t.id, "berth": t.port["berth"], "heading_deg": t.port["heading_deg"]})
    landmarks = []
    for t in towns + hamlets:
        for lm in t.landmarks:
            p = np.asarray(lm["pos"], float)
            y = float(surface_at(h, flat, micro, [p[0]], [p[1]])[0])
            e = {"id": lm["id"], "kind": lm["kind"], "pos": [r2(p[0]), r2(y), r2(p[1])], "yaw_deg": r2(lm.get("yaw_deg", 0.0))}
            if "radius" in lm: e["radius"] = lm["radius"]
            if lm.get("plot"): e["plot"] = True        # the building is a plot; the landmark only names it
            landmarks.append(e)
    for q in pois:
        if "pos3" in q:
            landmarks.append({"id": "poi." + q["id"], "kind": q["kind"], "pos": [r2(v) for v in q["pos3"]], "yaw_deg": 0.0})
    # the desert oases (palm groves round irrigated plots; the flora reads kind "oasis")
    for k, (ox, oz, orad) in enumerate(W.OASES):
        if any(lm["kind"] == "oasis" and math.hypot(lm["pos"][0] - ox, lm["pos"][2] - oz) < orad for lm in landmarks): continue
        oy = float(surface_at(h, flat, micro, [ox], [oz])[0])
        landmarks.append({"id": "oasis.%d" % k, "kind": "oasis", "pos": [r2(ox), r2(oy), r2(oz)], "yaw_deg": 0.0, "radius": orad * 0.8})
    # the dam across the lake outlet and the lake itself
    landmarks.append({"id": "lake.dam", "kind": "dam", "pos": [r2(L.DAM[0]), r2(lake[0] + 3), r2(L.DAM[1])], "yaw_deg": 0.0})
    plan = {"version": 1, "grid": {"n": N, "step": STEP, "origin": ORIGIN},
            "surface": {"lattice": LATTICE, "micro_tile": MICRO_TILE, "micro_amp": MICRO_AMP},
            "lake": {"x": L.LAKE[0], "z": L.LAKE[1], "radius": L.LAKE[2], "level": lake[0], "polygon": lake[2]},
            "towns": [t.to_json() for t in towns], "hamlets": [t.to_json() for t in hamlets], "roads": roads,
            "sea_lanes": [{"id": ln["id"], "from": ln["from"], "to": ln["to"], "points": [[r2(p[0]), r2(p[1])] for p in ln["points"]]} for ln in lanes],
            "ports": ports, "camps": camps, "landmarks": landmarks, "rivers": list(rivers),
            "estuary": [[float(a), float(b)] for a, b in L.ESTUARY]}
    with open(os.path.join(OUT, "plan.json"), "w") as f:
        json.dump(plan, f, separators=(",", ":"))
    sizes = {n_: os.path.getsize(os.path.join(OUT, n_)) // 1024 for n_ in os.listdir(OUT)}
    log("wrote", sizes)

# ------------------------------------------------------------------ main
def main():
    global T0
    T0 = time.time()
    exits = json.load(open(os.path.join(HERE, "core_exits.json")))
    global RIVER_FN, RIVER_MASK
    h, fields = cached("terrain", stage_terrain)
    log("terrain", h.min(), h.max())
    h, feat, rivers = cached("landscape", W.stage_landscape, h, fields)
    log("landscape: %d rivers, erg, wadis, oases" % len(rivers))
    RIVER_FN = W.river_distance_fn(rivers)
    RIVER_MASK = np.zeros(h.shape, np.uint8)
    for rv in rivers:
        P = rv["pts"]
        ii = np.round((P[:, 0] - ORIGIN) / STEP).astype(int); jj = np.round((P[:, 1] - ORIGIN) / STEP).astype(int)
        RIVER_MASK[np.clip(jj, 0, N - 1), np.clip(ii, 0, N - 1)] = 1
    towns = cached("towns", stage_towns, h)
    flat = np.zeros_like(h)
    h1 = town_heights(h.copy(), towns, flat)
    log("town surfaces carved")
    lake_mask = (np.hypot(fields_x() - L.LAKE[0], fields_z() - L.LAKE[1]) < L.LAKE[2] + 150).astype(np.uint8)
    harbour = np.array([262.0, -40.0])
    lanes = stage_lanes(h1, towns, harbour, exits)
    net = stage_roads(h1, towns, exits, lanes, lake_mask)
    hamlets, pois = stage_extras(h1, net, towns, lanes, lake_mask, net.gy)
    log("plots cleared off the roads: %d" % clear_plots_off_roads(towns + hamlets, net.roads))
    total = sum(len(r["pts"]) for r in net.roads) * 0.004
    log("roads total %.1f km" % total)
    micro = micro_tile()
    h2 = stage_carve(h1, net, flat, rivers, micro)
    # the runtime reads float32 heights and an 8-bit flatten mask: finalise against exactly those
    h2 = h2.astype(np.float32).astype(np.float64)
    flat[:] = np.round(np.clip(flat, 0, 1) * 255) / 255
    log("roads carved")
    finalise_heights(h2, flat, micro, net, towns + hamlets)
    if os.environ.get("OUTER_STOP") == "roads":
        # a quick look at the network without the dressing, the paint and the export
        with open(os.path.join(CACHE, "debug_roads.pkl"), "wb") as f:
            pickle.dump({"roads": net.roads, "towns": towns + hamlets}, f)
        log("stopped after the roads (OUTER_STOP=roads)")
        return
    import outer_props as PR
    nprops = PR.dress(towns + hamlets, h2, flat, micro, net.roads, surface_at, LY.Ctx(h2))
    log("props", nprops)
    camps = pick_camps(h2, net, towns + hamlets, flat, micro)
    log("camps", len(camps))
    lake = lake_fill(h2)
    river_out = W.river_levels(h2, rivers)
    log("rivers: %d runs, %.1f km" % (len(river_out), sum(len(r["points"]) for r in river_out) * 0.004))
    import outer_paint as PT
    splat, aux, tint, biome, feat = PT.paint(h2, fields, flat, towns + hamlets, lake[1], lake[0], feat=feat, rivers=river_out)
    rmask = PT.road_mask(net.roads)
    log("painted")
    export(h2, flat, micro, splat, aux, tint, rmask, net, towns, hamlets, lanes, camps, pois, harbour, lake, feat, river_out)
    with open(os.path.join(CACHE, "debug.pkl"), "wb") as f:
        pickle.dump({"h": h2.astype(np.float32), "towns": towns + hamlets, "lanes": lanes, "roads": net.roads, "pois": pois}, f)


_XZ = None
def fields_x():
    global _XZ
    if _XZ is None: _XZ = L.grid()
    return _XZ[0]
def fields_z():
    global _XZ
    if _XZ is None: _XZ = L.grid()
    return _XZ[1]


if __name__ == "__main__":
    main()
