"""Dressing for the outer towns: where the fountains, trees, benches, lamps, market stalls, cafe
tables, washing lines, bollards, boats, jetties, cranes, nets, gardens and terrace walls go.

Runs after every height is final (outer.py `export`), so each prop carries the runtime surface
height. The output per town is a list of compact records, `props`:
    [kind, x, y, z, yaw_deg, variant]
(OuterProps builds them with the architecture kit's ArchProps modules; `tree:<species>` kinds are
drawn with the wilderness trees), and `terraces`: dry-stone wall polylines [[x, z], ...] (Valdoro's
slopes). Placement keeps clear of the building plots, the navigation roads (main streets, the
highway approaches), the delivery ring and counter on the plaza, and of every other prop.
"""
import math
import numpy as np
from scipy import ndimage
import outer_towns as T
import outer_layouts as LY
from outer_towns import unit, perp, along, poly_len
from skimage import measure

ORIGIN = -12500.0; STEP = 12.5; N = 2001

FOUNTAIN = {"puerto": "fountain_grand", "campo": "fountain_basin", "sarmada": "fountain_moorish", "valdoro": "fountain_trough", "isola": "well"}
PLAZA_TREE = {"puerto": "oak", "campo": "oak", "sarmada": "palm", "valdoro": "oak", "isola": "umbrella"}
WASHING = {"puerto": 0.35, "isola": 0.4, "valdoro": 0.2, "sarmada": 0.12, "campo": 0.08}
BOATS = {"puerto": ["boat_fishing", "boat_fishing", "boat_small", "dinghy"], "isola": ["boat_small", "boat_small", "boat_fishing", "dinghy"],
         "sarmada": ["boat_fishing", "boat_small", "dinghy", "boat_small"]}


class Dresser:
    def __init__(self, town, h, surface, nav):
        self.t = town; self.h = h; self.surface = surface
        self.props = []
        self.grid = {}
        self.nav = nav                      # [(a, b, half)] navigation road segments near the town
        self.keep = []                      # [(centre, radius)] kept clear (ring, counter)
        self.rng = np.random.default_rng(town.seed + 77)

    # ---- queries
    def H(self, p):
        gx = (p[0] - ORIGIN) / STEP; gz = (p[1] - ORIGIN) / STEP
        i = int(min(max(gx, 0), N - 2)); j = int(min(max(gz, 0), N - 2)); u = gx - i; v = gz - j
        a = self.h
        return float(a[j, i] * (1 - u) * (1 - v) + a[j, i + 1] * u * (1 - v) + a[j + 1, i] * (1 - u) * v + a[j + 1, i + 1] * u * v)

    def in_plot(self, p, r):
        c = self.t.CELL
        for (i, j) in self.t._cells(p[0] - r, p[1] - r, p[0] + r, p[1] + r):
            for poly in self.t._plot_cells.get((i, j), ()):
                if T.point_in_poly(p, poly): return True
                for k in range(4):
                    a = poly[k]; b = poly[(k + 1) % 4]
                    ab = b - a; L2 = ab @ ab
                    tt = 0.0 if L2 < 1e-9 else max(0.0, min(1.0, ((p - a) @ ab) / L2))
                    if math.hypot(*(a + ab * tt - p)) < r: return True
        return False

    def near_nav(self, p, r):
        for a, b, half in self.nav:
            ab = b - a; L2 = ab @ ab
            tt = 0.0 if L2 < 1e-9 else max(0.0, min(1.0, ((p - a) @ ab) / L2))
            if math.hypot(*(a + ab * tt - p)) < half + r: return True
        return False

    def near_prop(self, p, r):
        gi = int(math.floor(p[0] / 8.0)); gj = int(math.floor(p[1] / 8.0))
        for dj in (-1, 0, 1):
            for di in (-1, 0, 1):
                for q, rq in self.grid.get((gi + di, gj + dj), ()):
                    if math.hypot(q[0] - p[0], q[1] - p[1]) < r + rq: return True
        return False

    def free(self, p, r, land=True, nav=1.2, plots=True):
        p = np.asarray(p, float)
        if land and self.H(p) < 1.0: return False
        if not land and self.H(p) > -1.0: return False
        if plots and self.in_plot(p, r): return False
        if nav is not None and self.near_nav(p, r + nav): return False
        if self.near_prop(p, r): return False
        for c, rr in self.keep:
            if math.hypot(c[0] - p[0], c[1] - p[1]) < rr + r: return False
        return True

    def add(self, kind, p, yaw_deg, variant=0, r=0.8, y=None):
        p = np.asarray(p, float)
        if y is None: y = float(self.surface([p[0]], [p[1]])[0])
        self.props.append([kind, round(float(p[0]), 2), round(float(y), 2), round(float(p[1]), 2), round(float(yaw_deg), 1), int(variant)])
        key = (int(math.floor(p[0] / 8.0)), int(math.floor(p[1] / 8.0)))
        self.grid.setdefault(key, []).append((p, r))

    def street_dist(self, p, kinds=None):
        best = 1e9
        for st in self.t.streets:
            if kinds and st["kind"] not in kinds: continue
            P = st["pts"]; half = st["width"] * 0.5
            for k in range(len(P) - 1):
                a = P[k]; b = P[k + 1]; ab = b - a; L2 = ab @ ab
                tt = 0.0 if L2 < 1e-9 else max(0.0, min(1.0, ((p - a) @ ab) / L2))
                best = min(best, math.hypot(*(a + ab * tt - p)) - half)
        return best


def yaw_facing(d):
    """Yaw (degrees) whose local +z points along the 2-D direction d."""
    return math.degrees(math.atan2(d[0], d[1]))


def yaw_x_along(d):
    """Yaw (degrees) whose local +x points along d."""
    return math.degrees(math.atan2(-d[1], d[0]))


# ------------------------------------------------------------------ plazas
def dress_plaza(D, st, main):
    t = D.t; style = t.style; rng = D.rng
    A = st["pts"][0]; B = st["pts"][-1]
    tt = unit(B - A); n = perp(tt)
    Lh = math.hypot(*(B - A)) * 0.5; W = st["width"] * 0.5
    c = (A + B) * 0.5
    if Lh < 6 or W < 8: return
    # the fountain, off the ring
    fk = FOUNTAIN[style]
    fr = {"fountain_grand": 5.2, "fountain_basin": 3.4, "fountain_moorish": 3.4, "fountain_trough": 2.4, "well": 1.4}[fk]
    if not main: fk = "fountain_basin" if style != "sarmada" else "fountain_moorish"; fr = 3.4
    for s in (0.5, -0.5, 0.0, 0.75, -0.75):
        p = c + tt * (Lh * s)
        if D.free(p, fr, nav=0.8):
            D.add(fk, p, yaw_facing(n) if fk == "fountain_trough" else rng.uniform(0, 90), 0, fr)
            break
    # trees in planters along the long sides, benches between them, lamps at the corners
    sp = PLAZA_TREE[style]
    step = 11.0 if style != "sarmada" else 9.0
    for side in (1, -1):
        s = -Lh + 5.0
        k = 0
        while s < Lh - 4.0:
            p = c + tt * s + n * side * (W - 3.0)
            if D.free(p, 1.3, nav=0.6):
                D.add("planter_round" if style in ("puerto", "sarmada") else "planter", p, rng.uniform(0, 90), 0, 1.3)
                D.add("tree:" + sp, p, rng.uniform(0, 360), 0, 0.1)
            q = c + tt * (s + step * 0.5) + n * side * (W - 3.0)
            if k % 2 == 0 and D.free(q, 1.0, nav=0.6):
                D.add("bench", q, yaw_facing(-n * side), 0 if style in ("puerto", "campo", "isola") else 1, 1.0)
            s += step; k += 1
    for sa in (-1, 1):
        for sb in (-1, 1):
            p = c + tt * sa * (Lh - 2.0) + n * sb * (W - 1.5)
            if D.free(p, 0.4, nav=0.4): D.add("lamp_plaza", p, yaw_x_along(tt), 0, 0.4)
    if not main: return
    # the market: two facing rows of stalls in the half away from the fountain
    stalls = 0
    half = -1.0 if D.props and any(pr[0].startswith("fountain") or pr[0] == "well" for pr in D.props[-12:]) else 1.0
    fpos = [np.array([pr[1], pr[3]]) for pr in D.props if pr[0].startswith("fountain") or pr[0] == "well"]
    if fpos:
        half = -1.0 if (fpos[-1] - c) @ tt > 0 else 1.0
    maxst = {"puerto": 10, "campo": 10, "sarmada": 12, "valdoro": 5, "isola": 5}[style]
    for row in (-1, 1):
        s = 3.0
        while s < Lh - 3.0 and stalls < maxst:
            p = c + tt * half * s + n * row * min(4.2, W * 0.35)
            if D.free(p, 1.4, nav=0.5):
                D.add("stall", p, yaw_facing(-n * row), int(rng.integers(0, 4)), 1.4)
                stalls += 1
            s += 3.1
    # cafe tables in front of the arcades and shopfronts facing the plaza
    for pl in t.plots:
        if not any(tg in pl["tags"] for tg in ("arcade", "shopfront")): continue
        pc = np.array([pl["x"], pl["z"]])
        fwd = np.array([math.sin(math.radians(pl["yaw"])), math.cos(math.radians(pl["yaw"]))])
        front = pc + fwd * (pl["d"] * 0.5)
        # on this plaza: the front lies inside its rectangle (+2 m)
        rel = front - c
        if abs(rel @ tt) > Lh + 8 or abs(rel @ n) > W + 6: continue
        side_ax = perp(fwd)
        for k in range(int(rng.integers(2, 5))):
            p = front + fwd * rng.uniform(2.8, 5.5) + side_ax * rng.uniform(-pl["w"] * 0.4, pl["w"] * 0.4)
            if D.free(p, 1.3, nav=0.8): D.add("cafe", p, rng.uniform(0, 360), int(rng.integers(0, 2)), 1.3)


# ------------------------------------------------------------------ streets
def dress_streets(D):
    t = D.t; rng = D.rng; style = t.style
    chance = WASHING.get(style, 0.1)
    for st in t.streets:
        if st["kind"] not in ("lane",) or st["width"] > 6.5: continue
        P = st["pts"]; L = poly_len(P); half = st["width"] * 0.5
        s = 6.0; last = -99.0
        while s < L - 6.0:
            p, d = along(P, s)
            n = perp(d)
            if s - last > 12.0 and rng.random() < chance:
                a = p + n * (half + 1.2); b = p - n * (half + 1.2)
                if D.in_plot(a, 0.4) and D.in_plot(b, 0.4) and not D.near_nav(p, 1.0):
                    length = int(round(st["width"] + 0.8))
                    y = float(D.surface([p[0]], [p[1]])[0]) + rng.uniform(4.3, 6.2)
                    D.add("washing", p, yaw_x_along(n), length, 0.2, y=y)
                    last = s
            s += 4.0
    # shop and barn clutter at the plot fronts
    for pl in t.plots:
        k = pl["kind"]
        if k not in ("shop", "barn", "warehouse", "granary", "house", "rowhouse") or rng.random() > (0.55 if k in ("shop", "barn", "warehouse") else 0.12):
            continue
        pc = np.array([pl["x"], pl["z"]])
        fwd = np.array([math.sin(math.radians(pl["yaw"])), math.cos(math.radians(pl["yaw"]))])
        sa = perp(fwd)
        p = pc + fwd * (pl["d"] * 0.5 + 0.7) + sa * rng.choice([-1, 1]) * (pl["w"] * 0.5 - 0.9)
        if k == "barn":
            kind, r = ("cart", 1.7) if rng.random() < 0.6 else ("haybale", 1.0)
        elif k == "warehouse":
            kind, r = ("crates", 1.3) if rng.random() < 0.6 else ("barrel", 0.45)
        elif k in ("house", "rowhouse"):
            kind, r = "pot_big", 0.5
        else:
            kind, r = (["barrel", "crates", "pot_big"][int(rng.integers(0, 3))], 1.0)
        if D.free(p, r, nav=1.0):
            D.add(kind, p, yaw_facing(fwd) + rng.uniform(-20, 20), int(rng.integers(0, 3)), r)


# ------------------------------------------------------------------ the harbour
def dress_port(D, ctx):
    t = D.t; rng = D.rng; style = t.style
    berth = None
    if t.port is not None:
        b = t.port["berth"]; berth = np.array([b[0], b[2]]) if len(b) == 3 else np.array(b[:2])
    kinds = BOATS.get(style, BOATS["isola"])
    for edge in t.quay_edges:
        E = np.asarray(edge, float)
        if len(E) < 3: continue
        E = LY.resample_line(E, 4.0)
        L = poly_len(E)
        s = 4.0; next_bollard = 0.0; next_boat = rng.uniform(6, 14); next_jetty = rng.uniform(40, 90); next_stack = rng.uniform(10, 25)
        while s < L - 4.0:
            p, d = along(E, s)
            n = perp(d)
            inl = n if D.H(p + n * 12) > D.H(p - n * 12) else -n
            sea = -inl
            clear_berth = berth is None or math.hypot(*(p - berth)) > 55.0
            if s >= next_bollard:
                q = p + inl * 1.2
                if D.H(q) > 1.0 and D.free(q, 0.3, nav=0.3): D.add("quay_bollard", q, yaw_facing(sea), 0, 0.3)
                next_bollard = s + 11.0
            if s >= next_jetty and clear_berth and style != "sarmada":
                tip = p + sea * 30.0
                if D.H(tip) < -2.0 and D.H(p + sea * 10.0) < -0.8:
                    length = 24 if rng.random() < 0.5 else 32
                    root = p + inl * 0.5
                    D.add("jetty", root, yaw_facing(inl), length, 1.8, y=0.0)
                    for k in range(2):
                        side = 1 if k == 0 else -1
                        bk = kinds[int(rng.integers(0, len(kinds)))]
                        bw = {"boat_fishing": 3.1, "boat_small": 2.1, "dinghy": 1.5}[bk]
                        bp = root + sea * (length * rng.uniform(0.4, 0.75)) + d * side * (1.6 + bw * 0.5 + 0.4)
                        if D.H(bp) < -1.0: D.add(bk, bp, yaw_facing(sea if rng.random() < 0.5 else -sea), int(rng.integers(0, 3)), bw, y=0.0)
                    next_jetty = s + rng.uniform(110, 170); next_boat = s + 14
                else:
                    next_jetty = s + 20
            if s >= next_boat and clear_berth:
                bk = kinds[int(rng.integers(0, len(kinds)))]
                bw = {"boat_fishing": 3.1, "boat_small": 2.1, "dinghy": 1.5}[bk]
                bl = {"boat_fishing": 9.5, "boat_small": 6.2, "dinghy": 3.8}[bk]
                bp = p + sea * (2.8 + bw * 0.5 + rng.uniform(0.2, 1.2))
                if D.H(bp) < -0.9 and D.free(bp, bl * 0.5, land=False, nav=None, plots=False):
                    D.add(bk, bp, yaw_facing(d if rng.random() < 0.5 else -d), int(rng.integers(0, 3)), bl * 0.5, y=0.0)
                next_boat = s + bl + rng.uniform(3, 14)
            if s >= next_stack:
                q = p + inl * rng.uniform(4.0, 8.0)
                kind = ["crates", "barrel", "net_rack", "lobster_pots", "crates"][int(rng.integers(0, 5))]
                if style == "puerto" and rng.random() < 0.4: kind = "crates"
                r = {"crates": 1.4, "barrel": 0.5, "net_rack": 2.3, "lobster_pots": 0.9}[kind]
                if D.H(q) > 1.0 and D.free(q, r, nav=1.5): D.add(kind, q, yaw_x_along(d), int(rng.integers(0, 3)), r)
                next_stack = s + rng.uniform(14, 32)
            s += 2.0


def dress_beach(D, ctx):
    """Isola: small boats pulled up on the shingle beyond the quay, net racks and pots by them."""
    t = D.t; rng = D.rng
    shores = ctx.shoreline(t.center[0] - 450, t.center[1] - 450, t.center[0] + 450, t.center[1] + 450, 0.8)
    for sh in shores[:2]:
        sh = LY.resample_line(sh, 6.0)
        L = poly_len(sh); s = 5.0
        while s < L - 5:
            p, d = along(sh, s)
            n = perp(d)
            inl = n if D.H(p + n * 10) > D.H(p - n * 10) else -n
            q = p + inl * rng.uniform(4.0, 7.0)
            if 0.4 < D.H(q) < 3.0 and rng.random() < 0.35 and D.free(q, 3.2, nav=2.0):
                bk = "boat_small" if rng.random() < 0.7 else "dinghy"
                D.add(bk, q, yaw_facing(-inl), int(rng.integers(0, 3)), 3.2)
                r2 = q + d * 4.5 + inl * 2.0
                if rng.random() < 0.5 and D.free(r2, 2.3, nav=1.5): D.add("net_rack" if rng.random() < 0.5 else "lobster_pots", r2, yaw_x_along(d), 0, 2.3)
            s += rng.uniform(6.0, 14.0)


# ------------------------------------------------------------------ around the town
def dress_gardens(D, count, r0, r1):
    t = D.t; rng = D.rng
    got = 0
    for k in range(count * 12):
        if got >= count: break
        ang = rng.uniform(0, 2 * math.pi); r = rng.uniform(r0, r1)
        p = t.center + r * np.array([math.cos(ang), math.sin(ang)])
        g = np.array([D.H(p + [6, 0]) - D.H(p - [6, 0]), D.H(p + [0, 6]) - D.H(p - [0, 6])]) / 12.0
        if math.hypot(*g) > 0.09: continue
        if D.street_dist(p) < 7.5: continue
        if not D.free(p, 7.5, nav=3.0): continue
        # align with the nearest street
        best = None; bd = 1e9
        for st in t.streets:
            P = st["pts"]
            k2 = int(np.argmin(np.hypot(*(P - p).T)))
            dd = math.hypot(*(P[k2] - p))
            if dd < bd and len(P) > 1:
                bd = dd; best = unit(P[min(k2 + 1, len(P) - 1)] - P[max(k2 - 1, 0)])
        yaw = yaw_facing(best) if best is not None else rng.uniform(0, 360)
        D.add("garden", p, yaw, int(rng.integers(0, 2)), 7.5)
        got += 1


def terraces(D, h_smooth, r0=170.0, r1=560.0, step_h=5.0):
    """Valdoro: dry-stone terrace walls along the contours of the slopes round the town."""
    t = D.t
    c = t.center
    i0 = int((c[0] - r1 - ORIGIN) / STEP); j0 = int((c[1] - r1 - ORIGIN) / STEP)
    n = int(2 * r1 / STEP) + 1
    sub = h_smooth[j0:j0 + n, i0:i0 + n]
    lo = math.floor(sub.min() / step_h) * step_h; hi = sub.max()
    out = []
    for lvl in np.arange(lo, hi, step_h):
        for con in measure.find_contours(sub, lvl):
            pts = np.stack([ORIGIN + (con[:, 1] + i0) * STEP, ORIGIN + (con[:, 0] + j0) * STEP], 1)
            pts = LY.resample_line(pts, 6.0)
            run = []
            for p in pts:
                r = math.hypot(*(p - c))
                g = np.array([D.H(p + [6, 0]) - D.H(p - [6, 0]), D.H(p + [0, 6]) - D.H(p - [0, 6])]) / 12.0
                ok = r0 < r < r1 and 0.1 < math.hypot(*g) < 0.55 and not D.in_plot(p, 3.0) and not D.near_nav(p, 4.0) \
                    and D.street_dist(p) > 3.0 and D.H(p) > 2.0
                if ok: run.append(p)
                else:
                    if len(run) >= 5: out.append(run)
                    run = []
            if len(run) >= 5: out.append(run)
    return [[[round(float(p[0]), 2), round(float(p[1]), 2)] for p in run] for run in out]


GAP_TREES = {"puerto": ["oak", "umbrella", "cypress"], "campo": ["oak", "olive", "cypress"], "sarmada": ["palm", "palm", "olive"],
             "valdoro": ["oak", "pine", "oak"], "isola": ["umbrella", "olive", "palm"]}


def dress_gaps(D, tries):
    """Trees and shrubs on the free ground between the plots (back gardens, empty lots, the edges of
    the squares) so the town is not a grid of houses on bare grass."""
    t = D.t; rng = D.rng
    kinds = GAP_TREES[t.style]
    for k in range(tries):
        ang = rng.uniform(0, 2 * math.pi); r = t.radius * math.sqrt(rng.uniform(0.02, 1.0))
        p = t.center + r * np.array([math.cos(ang), math.sin(ang)])
        if D.street_dist(p) < 3.5: continue
        if not D.free(p, 2.2, nav=3.0): continue
        # only where there are houses near: a gap in the town, not the open country
        if not D.in_plot(p, 20.0): continue
        # a big enough gap inside a block becomes a kitchen garden or an orchard corner
        if rng.random() < 0.18 and D.street_dist(p) > 8.0 and D.free(p, 7.2, nav=3.0):
            D.add("garden", p, rng.uniform(0, 360), int(rng.integers(0, 2)), 7.2)
            continue
        sp = kinds[int(rng.integers(0, len(kinds)))]
        D.add("tree:" + sp, p, rng.uniform(0, 360), 0, 2.2)


# ------------------------------------------------------------------ entry point
def dress(towns, h, flat, micro, roads, surface_at, ctx, hamlet_ids=()):
    """Fill `town.props` (and `town.terraces`) for every town and hamlet."""
    from scipy import ndimage as nd
    hs = nd.gaussian_filter(h, 1.2)
    surf = lambda xs, zs: surface_at(h, flat, micro, xs, zs)
    total = 0
    for t in towns:
        nav = []
        rad = t.radius + 400
        for r in roads:
            if r["class"] == "street" and r.get("town") not in (None, t.id): continue
            P = r["pts"]
            near = np.hypot(*(P - t.center).T) < rad
            if not near.any(): continue
            idx = np.where(near)[0]
            for k in idx[:-1]:
                if k + 1 < len(P): nav.append((P[k], P[k + 1], r["width"] * 0.5 + 0.5))
        D = Dresser(t, h, surf, nav)
        if t.plaza is not None:
            pz = np.asarray(t.plaza[:1] + t.plaza[2:] if len(t.plaza) == 3 else t.plaza, float)
            D.keep.append((pz, 9.5))
        if not t.hamlet:
            for st in t.streets:
                if st["kind"] == "plaza":
                    main = t.plaza is not None and math.hypot(*((st["pts"][0] + st["pts"][-1]) * 0.5 - D.keep[0][0])) < 60
                    dress_plaza(D, st, main)
            # Puerto Alto's dockside cranes are steel portal cranes (props), not the kit's derricks
            if t.style == "puerto":
                keep = []
                for lm in t.landmarks:
                    if lm["kind"] != "crane": keep.append(lm); continue
                    cp = np.asarray(lm["pos"], float)
                    sea = np.array([math.sin(math.radians(lm["yaw_deg"])), math.cos(math.radians(lm["yaw_deg"]))])
                    D.add("crane_port", cp - sea * 9.0, yaw_facing(-sea), 0, 3.4)
                t.landmarks = keep
            dress_streets(D)
            if t.sea_side: dress_port(D, ctx)
            if t.style == "isola": dress_beach(D, ctx)
            dress_gardens(D, {"puerto": 8, "campo": 10, "sarmada": 6, "valdoro": 5, "isola": 5}[t.style], t.radius * 0.8, t.radius + 180)
            dress_gaps(D, {"puerto": 3200, "campo": 1400, "sarmada": 1000, "valdoro": 800, "isola": 800}[t.style])
            t.terraces = terraces(D, hs) if t.style == "valdoro" else []
        else:
            # a hamlet: a well or trough on its little square, a cart, gardens round it
            pz = D.keep[0][0] if D.keep else t.center
            D.keep = []
            P = t.streets[t.main_street]["pts"]
            ld = unit(P[-1] - P[-5]) if len(P) > 5 else np.array([1.0, 0.0])
            for k in range(12):
                p = pz + perp(ld) * D.rng.choice([-1, 1]) * D.rng.uniform(6, 11) + ld * D.rng.uniform(-10, 4)
                if D.free(p, 1.4, nav=1.5):
                    D.add("well" if t.style in ("isola", "campo", "sarmada") else "fountain_trough", p, D.rng.uniform(0, 360), 0, 1.4)
                    break
            dress_streets(D)
            dress_gardens(D, 3, 25, 110)
            t.terraces = []
        t.props = D.props
        total += len(D.props)
    return total
