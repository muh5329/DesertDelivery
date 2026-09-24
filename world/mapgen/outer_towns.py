"""Town and hamlet layouts for the outer world: streets (main / lane / plaza / quay) and building
plots lining them, per town identity (the `style` ids are the contract with the architecture kit).

A layout is built in 2-D against the pre-carve heightfield (water, slope); heights are assigned
after the heightfield has been carved (outer.py), so every plot's `y` is the final ground.
"""
import math
import numpy as np

STYLE_FLOORS = {"puerto": (3, 6), "valdoro": (2, 4), "sarmada": (1, 3), "isola": (2, 3), "campo": (1, 3)}


# ------------------------------------------------------------------ geometry helpers
def perp(t):
    return np.array([-t[1], t[0]])


def unit(v):
    n = math.hypot(v[0], v[1])
    return v / n if n > 1e-9 else np.array([1.0, 0.0])


def rect_corners(c, t, w, d):
    """Rectangle centred at c, `w` along unit t, `d` along perp(t)."""
    n = perp(t)
    hw = 0.5 * w; hd = 0.5 * d
    return np.array([c + t * hw + n * hd, c - t * hw + n * hd, c - t * hw - n * hd, c + t * hw - n * hd])


def sat_overlap(a, b, eps=0.05):
    """Separating-axis test for two convex quads; touching (within eps) is not an overlap."""
    for poly in (a, b):
        for k in range(4):
            e = poly[(k + 1) % 4] - poly[k]
            ax = np.array([-e[1], e[0]]); ln = math.hypot(*ax)
            if ln < 1e-9: continue
            ax /= ln
            pa = a @ ax; pb = b @ ax
            if pa.max() <= pb.min() + eps or pb.max() <= pa.min() + eps:
                return False
    return True


def seg_seg_dist(p1, p2, q1, q2):
    def pt_seg(p, a, b):
        ab = b - a; L2 = ab @ ab
        t = 0.0 if L2 < 1e-12 else max(0.0, min(1.0, ((p - a) @ ab) / L2))
        return math.hypot(*(a + ab * t - p))
    # intersection test
    def orient(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    o1 = orient(p1, p2, q1); o2 = orient(p1, p2, q2); o3 = orient(q1, q2, p1); o4 = orient(q1, q2, p2)
    if (o1 > 0) != (o2 > 0) and (o3 > 0) != (o4 > 0):
        return 0.0
    return min(pt_seg(p1, q1, q2), pt_seg(p2, q1, q2), pt_seg(q1, p1, p2), pt_seg(q2, p1, p2))


def point_in_poly(p, poly):
    x, y = p; inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]; x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xi = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
            if xi > x: inside = not inside
    return inside


def poly_len(pts):
    return float(np.sum(np.hypot(*(np.diff(pts, axis=0)).T)))


def along(pts, s):
    """Point and unit tangent at arc length s."""
    seg = np.hypot(*(np.diff(pts, axis=0)).T)
    cum = np.concatenate([[0], np.cumsum(seg)])
    s = max(0.0, min(s, cum[-1]))
    k = int(np.searchsorted(cum, s, side="right") - 1)
    k = max(0, min(k, len(pts) - 2))
    t = (s - cum[k]) / max(seg[k], 1e-9)
    p = pts[k] + (pts[k + 1] - pts[k]) * t
    return p, unit(pts[k + 1] - pts[k])


def wiggle(a, b, rng, amp, n):
    """A lane from a to b with a gentle organic wobble."""
    a = np.asarray(a, float); b = np.asarray(b, float)
    t = np.linspace(0, 1, n + 1)
    d = b - a; nn = perp(unit(d))
    ph = rng.uniform(0, 6.28); ph2 = rng.uniform(0, 6.28)
    off = amp * (np.sin(t * math.pi * 2 + ph) * 0.6 + np.sin(t * math.pi * 3.7 + ph2) * 0.4) * np.sin(t * math.pi)
    return a[None] + d[None] * t[:, None] + nn[None] * off[:, None]


def arc(c, r, a0, a1, n):
    t = np.linspace(a0, a1, n)
    return np.stack([c[0] + r * np.cos(t), c[1] + r * np.sin(t)], 1)


# ------------------------------------------------------------------ the town model
class Town:
    def __init__(self, tid, name, style, center, radius, sea_side, seed):
        self.id = tid; self.name = name; self.style = style
        self.center = np.asarray(center, float); self.radius = radius; self.sea_side = sea_side
        self.rng = np.random.default_rng(seed)
        self.seed = seed
        self.streets = []          # {kind, width, pts (n,2)}
        self.plots = []            # plot dicts (+ "_poly")
        self.plaza = None
        self.port = None           # {berth: (x,z), heading_deg}
        self.gate = None           # (x,z): where the main street meets the road network
        self.gate_dir = None
        self.main_street = None    # index into streets (the one exported as a road)
        self.landmarks = []        # {id, kind, pos (x,z), yaw_deg}
        self.fill = []             # polygons (x,z) raised to land (quays, moles)
        self.quay_edges = []       # polylines of quay walls (water side)
        self.boundary = None       # optional polygon limiting plots
        self.levels = []           # hill towns: (polygon, level) terraces (filled in by outer.py)
        self.walls = []            # wall polylines (for the far LOD / info)
        self.hamlet = False
        self.kind = "town"
        self.flat = 1.0            # 1 = flatten the town surface hard, 0 = follow the land
        self._seg_cells = {}
        self._plot_cells = {}
        self.extra_clear = []      # (a, b, half) road corridors near the town plots must avoid

    # ---- spatial index
    CELL = 24.0

    def _cells(self, xmin, zmin, xmax, zmax):
        c = self.CELL
        for j in range(int(math.floor(zmin / c)), int(math.floor(zmax / c)) + 1):
            for i in range(int(math.floor(xmin / c)), int(math.floor(xmax / c)) + 1):
                yield (i, j)

    def add_street(self, kind, width, pts):
        pts = np.asarray(pts, float)
        st = {"kind": kind, "width": float(width), "pts": pts}
        self.streets.append(st)
        idx = len(self.streets) - 1
        for k in range(len(pts) - 1):
            a = pts[k]; b = pts[k + 1]; r = width * 0.5 + 2
            for c in self._cells(min(a[0], b[0]) - r, min(a[1], b[1]) - r, max(a[0], b[0]) + r, max(a[1], b[1]) + r):
                self._seg_cells.setdefault(c, []).append((a, b, width * 0.5, idx))
        return idx

    def add_clear_corridor(self, pts, half):
        pts = np.asarray(pts, float)
        for k in range(len(pts) - 1):
            a = pts[k]; b = pts[k + 1]; r = half + 2
            for c in self._cells(min(a[0], b[0]) - r, min(a[1], b[1]) - r, max(a[0], b[0]) + r, max(a[1], b[1]) + r):
                self._seg_cells.setdefault(c, []).append((a, b, half, -1))

    def street_clear(self, poly, margin=0.3):
        xmin, zmin = poly.min(0); xmax, zmax = poly.max(0)
        seen = set()
        for c in self._cells(xmin, zmin, xmax, zmax):
            for (a, b, half, idx) in self._seg_cells.get(c, ()):
                key = (id(a), id(b))
                if key in seen: continue
                seen.add(key)
                # distance from segment to the polygon: 0 if a segment end is inside
                if point_in_poly(a, poly) or point_in_poly(b, poly): return False
                for k in range(4):
                    if seg_seg_dist(a, b, poly[k], poly[(k + 1) % 4]) < half + margin:
                        return False
        return True

    def plot_clear(self, poly):
        xmin, zmin = poly.min(0); xmax, zmax = poly.max(0)
        for c in self._cells(xmin, zmin, xmax, zmax):
            for q in self._plot_cells.get(c, ()):
                if sat_overlap(poly, q): return False
        return True

    def try_plot(self, kind, c, front, w, d, floors, tags=(), land=None, check_streets=True, check_bounds=True):
        """Place a plot centred at c (x, z) whose street side faces `front` (unit). `w` is the
        frontage (across `front`), `d` the depth (along `front`)."""
        c = np.asarray(c, float); front = unit(np.asarray(front, float))
        t = np.array([front[1], -front[0]])    # along the frontage
        poly = rect_corners(c, t, w, d)
        if check_bounds:
            if self.boundary is not None:
                if not all(point_in_poly(p, self.boundary) for p in poly): return None
            elif np.max(np.hypot(*(poly - self.center).T)) > self.radius: return None
        if land is not None and not all(land(p[0], p[1]) for p in list(poly) + [c]): return None
        if check_streets and not self.street_clear(poly): return None
        if not self.plot_clear(poly): return None
        yaw = math.degrees(math.atan2(front[0], front[1]))
        pid = "%s.b%d" % (self.id, len(self.plots))
        plot = {"id": pid, "style": self.style, "kind": kind, "x": float(c[0]), "z": float(c[1]), "y": 0.0,
                "yaw": round(yaw, 2), "w": round(float(w), 2), "d": round(float(d), 2), "floors": int(floors),
                "seed": int(self.rng.integers(1, 2 ** 31 - 1)), "tags": list(tags), "_poly": poly}
        self.plots.append(plot)
        xmin, zmin = poly.min(0); xmax, zmax = poly.max(0)
        for cc in self._cells(xmin, zmin, xmax, zmax):
            self._plot_cells.setdefault(cc, []).append(poly)
        return plot

    def floors(self, lo=None, hi=None):
        a, b = STYLE_FLOORS[self.style]
        return int(self.rng.integers(lo or a, (hi or b) + 1))

    def line_plots(self, st_idx, side, kind, wr, dr, land, setback=0.4, gap=0.0, start=4.0, end=4.0,
                   floors=None, tags=(), kinds=None, max_plots=10 ** 6, contiguous=True):
        """Line one side of a street with plots. side = +1 left / -1 right of the street direction."""
        st = self.streets[st_idx]
        pts = st["pts"]; half = st["width"] * 0.5
        L = poly_len(pts)
        s = start; made = []
        miss = 0
        while s < L - end and len(made) < max_plots:
            w = float(self.rng.uniform(*wr)); d = float(self.rng.uniform(*dr))
            p, t = along(pts, s + w * 0.5)
            n = perp(t) * side
            c = p + n * (half + setback + d * 0.5)
            k = kind if kinds is None else kinds[int(self.rng.integers(0, len(kinds)))]
            fl = floors() if callable(floors) else (floors if floors is not None else self.floors())
            tg = list(tags)
            if not made: tg.append("corner")
            plot = self.try_plot(k, c, -n, w, d, fl, tg, land)
            if plot is not None:
                plot["_street"] = st_idx; plot["_front"] = p
                made.append(plot); s += w + gap; miss = 0
            else:
                s += 2.0; miss += 1
        if made and "corner" not in made[-1]["tags"]:
            made[-1]["tags"].append("corner")
        return made

    def to_json(self):
        streets = []
        for st in self.streets:
            streets.append({"kind": st["kind"], "width": st["width"], "points": [[round(float(p[0]), 2), round(float(p[1]), 2), round(float(p[2]), 2)] if len(p) == 3 else [round(float(p[0]), 2), 0.0, round(float(p[1]), 2)] for p in st.get("pts3", st["pts"])]})
        plots = []
        for p in self.plots:
            q = {k: v for k, v in p.items() if not k.startswith("_")}
            q["x"] = round(float(q["x"]), 2); q["z"] = round(float(q["z"]), 2)
            plots.append(q)
        out = {"id": self.id, "name": self.name, "style": self.style, "kind": self.kind,
               "center": [round(float(self.center[0]), 2), round(float(self.center[1]), 2)],
               "radius": self.radius, "sea_side": bool(self.sea_side), "streets": streets, "plots": plots,
               "plaza": self.plaza, "port": self.port,
               "quay_edges": [[[round(float(p[0]), 2), round(float(p[1]), 2)] for p in e] for e in self.quay_edges],
               "walls": [[[round(float(p[0]), 2), round(float(p[1]), 2)] for p in w] for w in self.walls]}
        return out


# ------------------------------------------------------------------ styles
def grid_district(town, origin, axis, nu, nv, bu, bv, width_u, width_v, land, kind_fn, wr, dr, floors=None,
                  tags=(), setback=0.4, clip=None, add_streets=True, skip=None):
    """A street grid: `nu` streets along `axis` (spaced bv) and `nv` across it (spaced bu); both
    sides of each street lined with plots. Returns the new street indices."""
    ax = unit(np.asarray(axis, float)); ay = perp(ax)
    o = np.asarray(origin, float)
    new = []
    Lu = bu * (nv - 1); Lv = bv * (nu - 1)
    for a in range(nu):
        p0 = o + ay * (a * bv) - ax * 6; p1 = o + ay * (a * bv) + ax * (Lu + 6)
        pts = np.linspace(p0, p1, 12)
        if clip is not None: pts = clip(pts)
        if pts is None or len(pts) < 2: continue
        new.append(town.add_street("lane", width_u, pts))
    for b in range(nv):
        p0 = o + ax * (b * bu) - ay * 6; p1 = o + ax * (b * bu) + ay * (Lv + 6)
        pts = np.linspace(p0, p1, 12)
        if clip is not None: pts = clip(pts)
        if pts is None or len(pts) < 2: continue
        new.append(town.add_street("lane", width_v, pts))
    for idx in new:
        for side in (1, -1):
            town.line_plots(idx, side, None, wr, dr, land, setback=setback, floors=floors, tags=tags, kinds=kind_fn)
    return new


def clip_to_poly(poly):
    def f(pts):
        inside = [point_in_poly(p, poly) for p in pts]
        if not any(inside): return None
        k0 = inside.index(True); k1 = len(inside) - 1 - inside[::-1].index(True)
        return pts[k0:k1 + 1] if k1 > k0 else None
    return f


def clip_to_land(land, pts, step=4.0):
    """Trim a polyline to its longest run over land."""
    dense = []
    for k in range(len(pts) - 1):
        a = pts[k]; b = pts[k + 1]; L = math.hypot(*(b - a))
        n = max(1, int(L / step))
        for q in range(n): dense.append(a + (b - a) * q / n)
    dense.append(pts[-1]); dense = np.array(dense)
    ok = [land(p[0], p[1]) for p in dense]
    best = (0, -1); cur = None
    for k, v in enumerate(ok):
        if v and cur is None: cur = k
        if (not v or k == len(ok) - 1) and cur is not None:
            e = k if v else k - 1
            if e - cur > best[1] - best[0]: best = (cur, e)
            cur = None
    if best[1] - best[0] < 3: return None
    return dense[best[0]:best[1] + 1]
