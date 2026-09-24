"""Per-town layouts (streets + plots) for the five towns and the hamlets.

Every layout works on a `Ctx` (the pre-carve heightfield) and fills a `Town` (outer_towns.py):
streets first (they reserve their corridors), then plots along them, then the specials.
Street heights (`pts3`) are assigned later by outer.py from the town surface rules each
layout leaves in `town.street_rule` (smoothed land, a terrace level, or a ramp).
"""
import math
import numpy as np
from scipy import ndimage
from skimage import measure
import outer_towns as T
from outer_towns import unit, perp, along, poly_len, wiggle, arc

N = 2001; STEP = 12.5; ORIGIN = -12500.0


class Ctx:
    def __init__(self, h):
        self.h = h
        self.hs = ndimage.gaussian_filter(h, 2.0)          # ~25 m smoothed land

    def H(self, x, z, smooth=False):
        a = self.hs if smooth else self.h
        gx = (x - ORIGIN) / STEP; gz = (z - ORIGIN) / STEP
        i = int(min(max(gx, 0), N - 2)); j = int(min(max(gz, 0), N - 2))
        u = gx - i; v = gz - j
        return float(a[j, i] * (1 - u) * (1 - v) + a[j, i + 1] * u * (1 - v) + a[j + 1, i] * (1 - u) * v + a[j + 1, i + 1] * u * v)

    def land(self, x, z, min_h=1.2):
        return self.H(x, z) > min_h

    def grad(self, x, z, e=12.5):
        return np.array([self.H(x + e, z, True) - self.H(x - e, z, True), self.H(x, z + e, True) - self.H(x, z - e, True)]) / (2 * e)

    def shoreline(self, x0, z0, x1, z1, level=1.0):
        i0 = int((x0 - ORIGIN) / STEP); i1 = int((x1 - ORIGIN) / STEP)
        j0 = int((z0 - ORIGIN) / STEP); j1 = int((z1 - ORIGIN) / STEP)
        sub = ndimage.gaussian_filter(self.h, 1.5)[j0:j1, i0:i1]
        out = []
        for c in measure.find_contours(sub, level):
            pts = np.stack([ORIGIN + (c[:, 1] + i0) * STEP, ORIGIN + (c[:, 0] + j0) * STEP], 1)
            out.append(pts)
        out.sort(key=lambda p: -len(p))
        return out

    def inland_normal(self, p, t, probe=30.0):
        n = perp(t)
        return n if self.H(*(p + n * probe)) > self.H(*(p - n * probe)) else -n

    def contour(self, level, centre, radius):
        c = centre
        pts = self.shoreline(c[0] - radius - 50, c[1] - radius - 50, c[0] + radius + 50, c[1] + radius + 50, level)
        best = None; bd = 1e9
        for p in pts:
            d = np.min(np.hypot(*(p - c).T))
            if d < bd: bd = d; best = p
        return best


def smooth_line(pts, sigma=3.0):
    pts = np.asarray(pts, float)
    if len(pts) < 5: return pts
    out = np.stack([ndimage.gaussian_filter1d(pts[:, 0], sigma, mode="nearest"), ndimage.gaussian_filter1d(pts[:, 1], sigma, mode="nearest")], 1)
    out[0] = pts[0]; out[-1] = pts[-1]
    return out


def resample_line(pts, step):
    pts = np.asarray(pts, float)
    seg = np.hypot(*np.diff(pts, axis=0).T)
    cum = np.concatenate([[0], np.cumsum(seg)])
    n = max(2, int(cum[-1] / step) + 1)
    s = np.linspace(0, cum[-1], n)
    return np.stack([np.interp(s, cum, pts[:, 0]), np.interp(s, cum, pts[:, 1])], 1)


def offset_line(ctx, pts, dist):
    """Offset a polyline `dist` metres inland (positive) or seaward (negative)."""
    out = []
    for k in range(len(pts)):
        a = pts[max(k - 1, 0)]; b = pts[min(k + 1, len(pts) - 1)]
        t = unit(b - a)
        n = ctx.inland_normal(pts[k], t)
        out.append(pts[k] + n * dist)
    return np.array(out)


def clip_radius(pts, c, r):
    keep = np.hypot(*(pts - c).T) <= r
    if keep.sum() < 2: return None
    idx = np.where(keep)[0]
    # longest contiguous run
    runs = np.split(idx, np.where(np.diff(idx) != 1)[0] + 1)
    run = max(runs, key=len)
    return pts[run[0]:run[-1] + 1] if len(run) >= 2 else None


def land_fn(ctx, min_h=1.0):
    return lambda x, z: ctx.H(x, z) > min_h


def slope_ok(ctx, max_grade):
    def f(x, z):
        g = ctx.grad(x, z)
        return ctx.H(x, z) > 1.0 and math.hypot(*g) < max_grade
    return f


def set_rule(town, idx, rule):
    town.streets[idx]["rule"] = rule


# ------------------------------------------------------------------ Puerto Alto
PA_CASTLE = np.array([7760.0, 2170.0])


def layout_puerto(town, ctx):
    """The port city: a quay along the estuary and the bay, a Baixa of streets parallel to it
    with cross streets every ~70 m, the grand plaza open to the quay, the old town on the castle
    hill behind, the avenue out to the highway gate in the west."""
    rng = town.rng
    c = town.center
    land = land_fn(ctx, 1.4)
    shores = ctx.shoreline(c[0] - 1100, c[1] - 900, c[0] + 800, c[1] + 900, 1.0)
    shore = smooth_line(resample_line(shores[0], 12.0), 4.0)
    shore = clip_radius(shore, c, town.radius + 60)
    if shore[0][0] > shore[-1][0]: shore = shore[::-1]
    quay = smooth_line(resample_line(offset_line(ctx, shore, 11.0), 10.0), 3.0)
    town.quay_edges.append(offset_line(ctx, shore, 2.0).tolist())
    qi = town.add_street("quay", 16.0, quay); set_rule(town, qi, ("flat", 2.6))
    corner_s = _corner_s(quay)
    Lq = poly_len(quay)
    # the grand plaza, open to the quay 220 m west of the corner
    ps = max(corner_s - 220, 80)
    pp, pt = along(quay, ps)
    pn = ctx.inland_normal(pp, pt)
    plaza_c = pp + pn * (8 + 38)
    town.plaza = plaza_c
    pz = town.add_street("plaza", 70.0, [plaza_c - pt * 46, plaza_c + pt * 46]); set_rule(town, pz, ("flat", None))
    # streets parallel to the quay (the estuary part only: s < corner_s + 60)
    q_est = np.array([p for k, p in enumerate(quay) if corner_s - 760 < k * 10.0 < corner_s + 40])
    rows = []
    for k in range(5):
        off = 46.0 + 50.0 * k
        pl = smooth_line(resample_line(offset_line(ctx, q_est, off), 10.0), 3.0)
        pl = T.clip_to_land(land, pl)
        if pl is None: continue
        pl = clip_radius(pl, c, town.radius)
        if pl is None or poly_len(pl) < 60: continue
        rows.append(town.add_street("lane", 9.0 if k % 2 == 0 else 7.0, pl))
    # cross streets: perpendicular to the quay every ~70 m, from the quay to the last row
    cross = []
    for s in np.arange(max(corner_s - 740, 20.0), corner_s + 30, 68.0):
        if abs(s - ps) < 50: continue
        p, t = along(quay, s)
        n = ctx.inland_normal(p, t)
        pts = resample_line(np.vstack([p + n * 8, p + n * 260]), 10.0)
        pts = T.clip_to_land(land, pts)
        if pts is None: continue
        pts = clip_radius(pts, c, town.radius)
        if pts is not None: cross.append(town.add_street("lane", 7.0, pts))
    # along the bay shore (after the corner): short streets up the hill
    for s in np.arange(corner_s + 70, Lq - 30, 80.0):
        p, t = along(quay, s)
        n = ctx.inland_normal(p, t)
        pts = T.clip_to_land(land, resample_line(np.vstack([p + n * 8, p + n * 200]), 10.0))
        if pts is None: continue
        pts = clip_radius(pts, c, town.radius)
        if pts is not None: cross.append(town.add_street("lane", 6.0, pts))
    # the avenue: from the plaza straight inland, then round to the gate in the west
    gate = np.asarray(town.gate, float)
    from outer_route import chaikin
    a1 = plaza_c + pn * 35
    a2 = plaza_c + pn * 300
    av = chaikin(np.vstack([a1, a2, a2 + T.unit(gate - a2) * 200 + perp(T.unit(gate - a2)) * 30, gate]), 3)
    town.main_street = town.add_street("main", 12.0, resample_line(av, 8.0))
    # the old town on the castle hill: lanes round it and radiating from its square
    hill = PA_CASTLE
    lanes = []
    for r in (55.0, 105.0, 160.0):
        n = int(2 * math.pi * r / 12)
        ring = arc(hill, r, 0, 2 * math.pi, n)
        ring += np.stack([np.sin(np.linspace(0, 12, n) + r), np.cos(np.linspace(0, 9, n) + r)], 1) * 5
        ring = T.clip_to_land(land, ring)
        if ring is None: continue
        lanes.append(town.add_street("lane", 5.5, ring))
    for k in range(7):
        ang = k * 2 * math.pi / 7 + 0.3
        a = hill + np.array([math.cos(ang), math.sin(ang)]) * 22
        b = hill + np.array([math.cos(ang), math.sin(ang)]) * 230
        w = T.clip_to_land(land, wiggle(a, b, rng, 9, 16))
        if w is None: continue
        lanes.append(town.add_street("lane", 5.0, w))
    sq = hill + T.unit(plaza_c - hill) * 36
    oq = town.add_street("plaza", 30.0, [sq - pt * 12, sq + pt * 12]); set_rule(town, oq, ("flat", None))
    # ---- the grand plaza: the dome cathedral facing the river, the clock tower, arcaded palazzi
    town.try_plot("church", plaza_c + pn * (35 + 20), -pn, 34, 36, 3, ["corner"], land)
    town.try_plot("tower", plaza_c + pn * (35 + 6) + pt * 40, -pn, 9, 9, 7, ["corner"], land)
    town.try_plot("town_hall", plaza_c + pn * (35 + 14) - pt * 38, -pn, 26, 24, 4, ["arcade"], land)
    for side in (-1, 1):
        for k in range(2):
            p = plaza_c + pt * side * (46 + 12) + pn * (-12 + k * 26)
            town.try_plot("palazzo", p, -pt * side, 24, 20, 4, ["arcade", "shopfront"], land)
    town.try_plot("church", sq + pn * 26, -pn, 16, 26, 2, [], land)
    # ---- the quay: warehouses on the working stretches, shops by the plaza
    for side in (1, -1):
        town.line_plots(qi, side, None, (14, 26), (14, 20), land, setback=1.0, gap=1.5,
                        floors=lambda: int(rng.integers(2, 4)), kinds=["warehouse"] * 3 + ["shop"], tags=["quay"])
    row = lambda: int(rng.integers(3, 7))
    for idx in [town.main_street] + rows + cross:
        for side in (1, -1):
            town.line_plots(idx, side, None, (6.0, 9.5), (10, 15), land, setback=0.3, floors=row,
                            kinds=["rowhouse"] * 6 + ["shop"] * 2 + ["palazzo"], tags=["shopfront"] if idx == town.main_street else [])
    for idx in lanes:
        for side in (1, -1):
            town.line_plots(idx, side, None, (5.0, 8.0), (8, 12), land, setback=0.3, floors=lambda: int(rng.integers(2, 5)),
                            kinds=["rowhouse"] * 5 + ["house"] * 3)
    # ---- the lighthouse on the point where the estuary meets the bay, cranes on the quay
    cp, ct = along(shore, min(corner_s, poly_len(shore) - 5))
    cn = ctx.inland_normal(cp, ct)
    # the breakwater: a stone mole off the point, the lighthouse on its head
    mole1 = cp - cn * 95.0
    m0 = cp + cn * 25.0
    town.fill.append([(m0 + ct * 9).tolist(), (m0 - ct * 9).tolist(), (mole1 - ct * 9).tolist(), (mole1 + ct * 9).tolist()])
    mo = town.add_street("quay", 10.0, [cp + cn * 4, mole1 + cn * 13]); set_rule(town, mo, ("flat", 2.4))
    town.quay_edges.append([(cp + ct * 6.5).tolist(), (mole1 + ct * 6.5).tolist()])
    town.quay_edges.append([(mole1 - ct * 6.5).tolist(), (cp - ct * 6.5).tolist()])
    town.try_plot("lighthouse", mole1 + cn * 2, -cn, 7, 7, 7, [], None, check_bounds=False, check_streets=False)
    town.landmarks.append({"id": "puerto_alto.lighthouse", "kind": "lighthouse", "pos": mole1 + cn * 2, "yaw_deg": 0.0})
    for k in range(6):
        p, t = along(quay, 60 + k * 60)
        n = ctx.inland_normal(p, t)
        town.landmarks.append({"id": "puerto_alto.crane%d" % k, "kind": "crane", "pos": p - n * 6.5,
                               "yaw_deg": math.degrees(math.atan2(-n[0], -n[1]))})
    bn = pn
    town.port = {"berth": pp - bn * 30, "heading_deg": math.degrees(math.atan2(pt[0], pt[1]))}
    town.landmarks.append({"id": "puerto_alto.castle", "kind": "castle_ruin", "pos": hill, "yaw_deg": 20.0})


def _corner_s(quay):
    """Arc length of the sharpest turn of the quay (where the estuary shore meets the bay)."""
    best = 0; bk = 0.0; s = 0.0
    for k in range(1, len(quay) - 1):
        a = unit(quay[k] - quay[k - 1]); b = unit(quay[k + 1] - quay[k])
        turn = 1 - a @ b
        s += math.hypot(*(quay[k] - quay[k - 1]))
        if turn > bk: bk = turn; best = s
    return best if best > 0 else poly_len(quay) * 0.5


# ------------------------------------------------------------------ Sarmada
def layout_sarmada(town, ctx):
    rng = town.rng
    c = town.center
    land = land_fn(ctx, 1.4)
    shores = ctx.shoreline(c[0] - 700, c[1] - 700, c[0] + 700, c[1] + 700, 1.0)
    shore = smooth_line(resample_line(shores[0], 10.0), 3.0)
    # shore direction near the town and the sea normal
    k = int(np.argmin(np.hypot(*(shore - c).T)))
    st = unit(shore[min(k + 5, len(shore) - 1)] - shore[max(k - 5, 0)])
    inl = ctx.inland_normal(shore[k], st)
    sea = -inl
    # the walled medina: a rectangle along the shore
    W, D = 380.0, 300.0
    mc = shore[k] + inl * (D * 0.5 + 40)
    ax = st; ay = inl
    corners = [mc - ax * W / 2 - ay * D / 2, mc + ax * W / 2 - ay * D / 2, mc + ax * W / 2 + ay * D / 2, mc - ax * W / 2 + ay * D / 2]
    wall_poly = np.array(corners)
    town.center = mc
    town.boundary = np.array([mc - ax * (W / 2 - 6) - ay * (D / 2 - 6), mc + ax * (W / 2 - 6) - ay * (D / 2 - 6),
                              mc + ax * (W / 2 - 6) + ay * (D / 2 - 6), mc - ax * (W / 2 - 6) + ay * (D / 2 - 6)])
    town.walls.append(np.vstack([wall_poly, wall_poly[:1]]).tolist())
    # the market square and the main street from the land gate (inland side) to the sea gate
    plaza = mc - ay * 20 + ax * 20
    town.plaza = plaza
    land_gate = mc + ay * D / 2
    sea_gate = mc - ay * D / 2
    gate = np.asarray(town.gate, float)
    main = np.vstack([sea_gate - ay * 30, plaza, land_gate, land_gate + ay * 40, gate])
    from outer_route import chaikin
    main = resample_line(chaikin(main, 2), 8.0)
    town.main_street = town.add_street("main", 9.0, main)
    pz = town.add_street("plaza", 44.0, [plaza - ax * 26, plaza + ax * 26]); set_rule(town, pz, ("flat", None))
    # the kasbah in the inland corner away from the harbour: its ground is kept free of derbs
    kc = mc + ax * (W / 2 - 45) + ay * (D / 2 - 45)
    kas = np.array([kc - ax * 36 - ay * 32, kc + ax * 36 - ay * 32, kc + ax * 36 + ay * 32, kc - ax * 36 + ay * 32])
    def outside_kasbah(w):
        if w is None: return None
        keep = np.array([not T.point_in_poly(p, kas) for p in w])
        if keep.all(): return w
        idx = np.where(keep)[0]
        if len(idx) < 2: return None
        runs = np.split(idx, np.where(np.diff(idx) != 1)[0] + 1)
        run = max(runs, key=len)
        return w[run[0]:run[-1] + 1] if len(run) >= 2 else None
    # the derbs: a jittered grid of narrow lanes, some dropped, all wobbling
    lanes = []
    for a in range(-4, 5):
        if a == 0: continue
        p0 = mc + ay * (a * 34) - ax * (W / 2 - 8); p1 = mc + ay * (a * 34) + ax * (W / 2 - 8)
        if rng.random() < 0.15: continue
        w = wiggle(p0, p1, rng, 5, 20)
        w = outside_kasbah(T.clip_to_poly(town.boundary)(w))
        if w is not None: lanes.append(town.add_street("lane", 4.5, w))
    for b in range(-5, 6):
        if b == 0: continue
        off = b * 36 + rng.uniform(-5, 5)
        p0 = mc + ax * off - ay * (D / 2 - 8); p1 = mc + ax * off + ay * (D / 2 - 8)
        if rng.random() < 0.3:
            # a dead-end derb: only half the way across
            p1 = mc + ax * off + ay * rng.uniform(-40, 40)
        w = wiggle(p0, p1, rng, 4, 16)
        w = outside_kasbah(T.clip_to_poly(town.boundary)(w))
        if w is not None: lanes.append(town.add_street("lane", 4.0, w))
    # the harbour: a quay along the shore outside the sea wall and a mole with the lighthouse
    q0 = shore[max(k - 26, 0)]; q1 = shore[min(k + 26, len(shore) - 1)]
    qline = resample_line(offset_line(ctx, shore[max(k - 26, 0):min(k + 26, len(shore) - 1) + 1], 9.0), 10.0)
    qi = town.add_street("quay", 12.0, qline); set_rule(town, qi, ("flat", 2.4))
    town.quay_edges.append(offset_line(ctx, shore[max(k - 26, 0):min(k + 26, len(shore) - 1) + 1], 2.0).tolist())
    mole0 = shore[k] + ax * 90
    mole1 = mole0 + sea * 150 + ax * 40
    # (rooted 25 m inland and 18 m wide, so the dredging in front of the quay cannot cut it off)
    m0 = mole0 + inl * 25.0
    town.fill.append([(m0 - ax * 9).tolist(), (m0 + ax * 9).tolist(), (mole1 + ax * 9).tolist(), (mole1 - ax * 9).tolist()])
    mi = town.add_street("quay", 10.0, [mole0 + inl * 6, mole1]); set_rule(town, mi, ("flat", 2.4))
    town.landmarks.append({"id": "sarmada.lighthouse", "kind": "lighthouse", "pos": mole1 + sea * 4, "yaw_deg": 0.0})
    town.port = {"berth": (mole0 + mole1) * 0.5 - ax * 24, "heading_deg": math.degrees(math.atan2(-sea[0], -sea[1]))}
    # ---- walls, towers and gates (the kit builds them from these plots)
    for e in range(4):
        a = wall_poly[e]; b = wall_poly[(e + 1) % 4]
        L = math.hypot(*(b - a)); t = unit(b - a)
        nseg = max(1, int(L / 30))
        out = unit(perp(t)) if (perp(t) @ (a - mc)) > 0 else -unit(perp(t))
        for s in range(nseg):
            p = a + t * (L * (s + 0.5) / nseg)
            gate_here = min(np.hypot(*(p - land_gate)), np.hypot(*(p - sea_gate))) < L / nseg * 0.6
            if gate_here:
                town.try_plot("gate", p, out, 16, 9, 3, [], None, check_streets=False, check_bounds=False)
            else:
                town.try_plot("wall", p, out, L / nseg, 3.0, 3, [], None, check_streets=True, check_bounds=False)
        town.try_plot("tower", a, out, 9, 9, 4, ["corner"], None, check_streets=False, check_bounds=False)
    town.try_plot("citadel", kc, -ay, 62, 52, 3, ["corner"], land, check_streets=True)
    # houses: flat-roofed courtyard houses along every derb and the main street
    fl = lambda: int(rng.integers(1, 4))
    for idx in [town.main_street] + lanes:
        for side in (1, -1):
            town.line_plots(idx, side, None, (7.0, 13.0), (8, 13), land, setback=0.3, floors=fl,
                            kinds=["house"] * 7 + ["shop"] * 2, tags=["terrace"])
    for side in (1, -1):
        town.line_plots(pz, side, None, (8, 14), (10, 14), land, setback=0.5, floors=2, kinds=["shop", "market_hall", "house"], tags=["arcade", "shopfront"])
    for side in (1, -1):
        town.line_plots(qi, side, None, (10, 18), (10, 16), land, setback=0.8, floors=lambda: int(rng.integers(1, 3)),
                        kinds=["warehouse", "boathouse"], tags=["quay"])
    # the oasis palm grove north-west of the walls (dressing reads it from the plan)
    town.landmarks.append({"id": "sarmada.oasis", "kind": "oasis", "pos": mc + ay * (D / 2 + 260) - ax * 220, "yaw_deg": 0.0, "radius": 190.0})
    town.landmarks.append({"id": "sarmada.watchtower", "kind": "watchtower", "pos": mc + ax * (W / 2 + 320) + ay * 120, "yaw_deg": 0.0})


# ------------------------------------------------------------------ Campo Real
def layout_campo(town, ctx):
    rng = town.rng
    c = town.center
    land = land_fn(ctx, 1.5)
    R = 135.0
    town.plaza = c.copy()
    gate = np.asarray(town.gate, float)
    gdir = unit(gate - c)
    # the four cross streets out through the wall gates; the main one runs to the highway gate
    dirs = [gdir, perp(gdir), -gdir, -perp(gdir)]
    from outer_route import chaikin
    main = resample_line(chaikin(np.vstack([c + gdir * 36, c + gdir * (R + 40), (c + gdir * (R + 40) + gate) * 0.5 + perp(gdir) * 20, gate]), 2), 8.0)
    town.main_street = town.add_street("main", 10.0, main)
    pz = town.add_street("plaza", 60.0, [c - perp(gdir) * 30, c + perp(gdir) * 30]); set_rule(town, pz, ("flat", None))
    cross = []
    for d in dirs[1:]:
        cross.append(town.add_street("lane", 8.0, resample_line(np.vstack([c + d * 34, c + d * (R + 260)]), 10.0)))
    rings = []
    for r in (64.0, 106.0):
        n = int(2 * math.pi * r / 10)
        ring = arc(c, r, 0, 2 * math.pi, n + 1)
        rings.append(town.add_street("lane", 6.0, ring))
    # the ring road outside the wall
    ring_out = arc(c, R + 22, 0, 2 * math.pi, 90)
    rings.append(town.add_street("lane", 7.0, ring_out))
    # the wall: segments on the circle, a gate where each cross street leaves
    town.walls.append(arc(c, R, 0, 2 * math.pi, 64).tolist())
    nseg = 28
    gate_angles = [math.atan2(d[1], d[0]) for d in dirs]
    for s in range(nseg):
        a0 = 2 * math.pi * s / nseg; a1 = 2 * math.pi * (s + 1) / nseg; am = 0.5 * (a0 + a1)
        p = c + R * np.array([math.cos(am), math.sin(am)])
        out = np.array([math.cos(am), math.sin(am)])
        near_gate = min(abs((am - g + math.pi) % (2 * math.pi) - math.pi) for g in gate_angles)
        seg_len = 2 * R * math.sin(math.pi / nseg)
        if near_gate < math.pi / nseg:
            town.try_plot("gate", p, out, 14, 8, 3, [], None, check_streets=False, check_bounds=False)
        else:
            town.try_plot("wall", p, out, seg_len, 2.5, 3, [], None, check_bounds=False)
            if s % 4 == 0:
                town.try_plot("tower", c + (R + 1) * out, out, 7, 7, 4, [], None, check_bounds=False)
    # plaza: the town hall with its tower, the church, arcaded houses round the square
    pn = gdir; pt = perp(gdir)
    town.try_plot("town_hall", c - pn * 44, pn, 26, 18, 3, ["arcade", "corner"], land)
    town.try_plot("tower", c - pn * 44 + pt * 17, pn, 8, 8, 7, [], land)
    town.try_plot("church", c + pt * 50, -pt, 18, 30, 2, ["corner"], land)
    for side in (1, -1):
        town.line_plots(pz, side, None, (7, 11), (10, 13), land, setback=0.3, floors=lambda: int(rng.integers(2, 4)),
                        kinds=["house", "shop", "palazzo"], tags=["arcade", "shopfront"])
    fl = lambda: int(rng.integers(1, 4))
    for idx in rings[:2] + cross + [town.main_street]:
        for side in (1, -1):
            town.line_plots(idx, side, None, (8.0, 13.0), (10, 14), land, setback=0.3, floors=fl, kinds=["house"] * 6 + ["shop"] * 2)
    for side in (1, -1):
        town.line_plots(rings[2], side, None, (8, 14), (10, 15), land, setback=0.5, floors=fl, kinds=["house", "house", "shop", "barn"])
    # the new quarter: a grid south-east of the walls
    ax = perp(gdir); ay = -gdir
    o = c + ay * (R + 70) - ax * 150
    town.boundary = None
    grid_district(town, o, ax, 3, 4, 64, 52, 7.0, 7.0, land, ["house"] * 6 + ["shop", "granary"], (8, 13), (10, 15), floors=fl)
    # farm compounds round the edge: a house, a barn and a granary round a yard
    for k in range(8):
        ang = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(R + 230, town.radius - 40)
        fc = c + r * np.array([math.cos(ang), math.sin(ang)])
        _farm(town, fc, ang + math.pi * 0.5, land)
    # the windmills on the ridge north-east of the town
    for k in range(5):
        p = np.array([6150.0, -3180.0]) + np.array([200.0, 150.0]) * k + rng.uniform(-25, 25, 2)
        town.try_plot("windmill", p, unit(c - p), 9, 9, 3, [], land, check_bounds=False)
        town.landmarks.append({"id": "campo_real.windmill%d" % k, "kind": "windmill_site", "pos": p, "yaw_deg": 0.0})


def _farm(town, fc, yaw, land):
    fwd = np.array([math.cos(yaw), math.sin(yaw)]); side = perp(fwd)
    got = town.try_plot("house", fc - fwd * 14, fwd, 12, 9, 2, ["corner"], land)
    if got is None: return 0
    town.try_plot("barn", fc + side * 16, -side, 20, 12, 2, [], land)
    town.try_plot("granary", fc - side * 14 + fwd * 4, side, 8, 8, 2, [], land)
    return 1


def grid_district(town, origin, axis, nu, nv, bu, bv, wu, wv, land, kinds, wr, dr, floors=None):
    ax = unit(np.asarray(axis, float)); ay = perp(ax)
    new = []
    for a in range(nu):
        p0 = origin + ay * (a * bv); pts = T.clip_to_land(land, np.linspace(p0, p0 + ax * bu * (nv - 1), 12))
        if pts is None: continue
        pts = clip_radius(pts, town.center, town.radius)
        if pts is not None: new.append(town.add_street("lane", wu, pts))
    for b in range(nv):
        p0 = origin + ax * (b * bu); pts = T.clip_to_land(land, np.linspace(p0, p0 + ay * bv * (nu - 1), 12))
        if pts is None: continue
        pts = clip_radius(pts, town.center, town.radius)
        if pts is not None: new.append(town.add_street("lane", wv, pts))
    for idx in new:
        for side in (1, -1):
            town.line_plots(idx, side, None, wr, dr, land, floors=floors, kinds=kinds)
    return new


# ------------------------------------------------------------------ Valdoro (terraced hill town)
def layout_valdoro(town, ctx):
    rng = town.rng
    c = town.center
    land = land_fn(ctx, 2.0)
    g = ctx.grad(*c)
    down = -unit(g)                       # downhill
    along_c = perp(down)                  # along the contours
    h0 = ctx.H(*c, smooth=True)
    step_h = 6.0
    terraces = []
    for k in range(-3, 4):
        lvl = h0 + k * step_h
        con = ctx.contour(lvl, c + (-down) * k * 25, 260)
        if con is None: continue
        con = smooth_line(resample_line(con, 8.0), 2.5)
        con = clip_radius(con, c, 190)
        if con is None or poly_len(con) < 80: continue
        # orient along +along_c
        if (con[-1] - con[0]) @ along_c < 0: con = con[::-1]
        terraces.append((lvl, con))
    terraces.sort(key=lambda t: t[0])
    lane_idx = []
    for lvl, con in terraces:
        k = town.add_street("lane", 6.0, con); set_rule(town, k, ("flat", lvl)); lane_idx.append((k, lvl, con))
    # the plaza on the middle terrace
    mid = lane_idx[len(lane_idx) // 2]
    pc, pt = along(mid[2], poly_len(mid[2]) * 0.5)
    up = -down
    plaza_c = pc + up * 18
    town.plaza = plaza_c
    # the switchback main street: from the gate up the terrace lanes, a ramp at alternate ends,
    # and along the plaza's terrace to the plaza
    gate = np.asarray(town.gate, float)
    zig = []
    for n, (k, lvl, con) in enumerate(lane_idx):
        a = con[0] if n % 2 == 0 else con[-1]
        b = con[-1] if n % 2 == 0 else con[0]
        zig.append((a, b, lvl))
    main_pts = [np.append(gate, ctx.H(*gate, smooth=True))]
    for n, (a, b, lvl) in enumerate(zig):
        main_pts.append(np.append(a + unit(b - a) * 30, lvl))
        if lvl >= mid[1] - 0.01:
            main_pts.append(np.append(pc, lvl))
            main_pts.append(np.append(plaza_c, lvl))
            break
        main_pts.append(np.append(a + unit(b - a) * 70, lvl))
    main3 = np.array(main_pts)
    from outer_route import chaikin
    xy = chaikin(main3[:, :2], 2)
    town.main_street = town.add_street("main", 7.0, resample_line(xy, 6.0))
    set_rule(town, town.main_street, ("ramp", main3.tolist()))
    pz = town.add_street("plaza", 30.0, [plaza_c - pt * 18, plaza_c + pt * 18]); set_rule(town, pz, ("flat", mid[1]))
    town.try_plot("church", plaza_c + up * 30, -up, 14, 24, 2, ["corner"], land)
    town.try_plot("tower", plaza_c + up * 26 + pt * 16, -up, 6, 6, 7, [], land)
    town.try_plot("town_hall", plaza_c + pt * 32, -pt, 14, 12, 3, ["corner"], land)
    # stair lanes straight down the slope between the terraces
    for off in (-90, 0, 90):
        a = c + along_c * off + up * 130; b = c + along_c * off - up * 130
        w = T.clip_to_land(land, wiggle(a, b, rng, 5, 14))
        if w is not None:
            w = clip_radius(w, c, 185)
            if w is not None:
                k = town.add_street("lane", 3.5, w); set_rule(town, k, ("land", None))
    fl = lambda: int(rng.integers(2, 5))
    for k, lvl, con in lane_idx:
        for side in (1, -1):
            town.line_plots(k, side, None, (6.0, 10.0), (8.0, 12.0), land, setback=0.3, floors=fl,
                            kinds=["house"] * 8 + ["shop", "barn"])
    for p in town.plots:
        if "_street" in p:
            for k, lvl, con in lane_idx:
                if p["_street"] == k: p["_level"] = lvl
    town.landmarks.append({"id": "valdoro.viewpoint", "kind": "viewpoint", "pos": c + down * 230, "yaw_deg": math.degrees(math.atan2(down[0], down[1]))})


# ------------------------------------------------------------------ Isola Serena
def layout_isola(town, ctx):
    rng = town.rng
    c = town.center
    land = land_fn(ctx, 1.3)
    shores = ctx.shoreline(c[0] - 500, c[1] - 500, c[0] + 500, c[1] + 500, 1.0)
    shore = smooth_line(resample_line(shores[0], 8.0), 3.0)
    shore = clip_radius(shore, c, town.radius + 30)
    k = int(np.argmin(np.hypot(*(shore - c).T)))
    st = unit(shore[min(k + 6, len(shore) - 1)] - shore[max(k - 6, 0)])
    inl = ctx.inland_normal(shore[k], st)
    # the harbour quay along the shore
    quay = smooth_line(resample_line(offset_line(ctx, shore, 8.0), 8.0), 2.0)
    qi = town.add_street("quay", 11.0, quay); set_rule(town, qi, ("flat", 2.2))
    town.quay_edges.append(offset_line(ctx, shore, 1.5).tolist())
    # plaza by the harbour with the church
    pc = shore[k] + inl * 42
    town.plaza = pc
    pz = town.add_street("plaza", 32.0, [pc - st * 20, pc + st * 20]); set_rule(town, pz, ("flat", None))
    # the lanes climbing the slope along the contours (pastel houses stacked up the hill)
    h0 = 2.5
    lanes = []
    for lvl in (9.0, 17.0, 26.0, 36.0):
        con = ctx.contour(lvl, c + inl * (lvl * 5), 300)
        if con is None: continue
        con = smooth_line(resample_line(con, 8.0), 2.5)
        con = clip_radius(con, c, town.radius)
        if con is None or poly_len(con) < 60: continue
        k2 = town.add_street("lane", 4.5, con); set_rule(town, k2, ("flat", lvl)); lanes.append(k2)
    # the main street from the gate down to the plaza (the causeway road arrives at the gate)
    gate = np.asarray(town.gate, float)
    from outer_route import chaikin
    ms = resample_line(chaikin(np.vstack([gate, (gate + pc) * 0.5 + st * 30, pc + inl * 16]), 3), 6.0)
    town.main_street = town.add_street("main", 7.0, ms)
    set_rule(town, town.main_street, ("land", None))
    # steps up the hill
    for off in (-70, 60):
        a = pc + st * off + inl * 10; b = a + inl * 200
        w = T.clip_to_land(land, wiggle(a, b, rng, 6, 12))
        if w is not None:
            w = clip_radius(w, c, town.radius)
            if w is not None:
                k3 = town.add_street("lane", 3.0, w); set_rule(town, k3, ("land", None))
    town.try_plot("church", pc + inl * 36, -inl, 12, 22, 2, ["corner"], land)
    town.try_plot("tower", pc + inl * 30 + st * 12, -inl, 5, 5, 6, [], land)
    fl = lambda: int(rng.integers(2, 4))
    for idx in [town.main_street] + lanes:
        for side in (1, -1):
            town.line_plots(idx, side, None, (5.0, 8.5), (7.0, 10.0), land, setback=0.3, floors=fl, kinds=["house"] * 8 + ["shop"], tags=["terrace"])
    for side in (1, -1):
        town.line_plots(qi, side, None, (6.0, 9.0), (8.0, 11.0), land, setback=0.4, floors=fl, kinds=["house", "shop", "house"], tags=["quay", "shopfront"])
    # boathouses right on the water's edge beyond the quay ends
    for s in np.linspace(10, poly_len(shore) - 10, 14):
        p, t = along(shore, s)
        n = ctx.inland_normal(p, t)
        town.try_plot("boathouse", p - n * 1.5, -n, 6.0, 9.0, 1, ["quay"], None, check_bounds=False)
    far = shore[0] if np.hypot(*(shore[0] - c)) > np.hypot(*(shore[-1] - c)) else shore[-1]
    town.landmarks.append({"id": "isola_serena.lighthouse", "kind": "lighthouse", "pos": far + unit(far - c) * 10, "yaw_deg": 0.0})
    bp, bt = along(quay, poly_len(quay) * 0.5)
    bn = ctx.inland_normal(bp, bt)
    town.port = {"berth": bp - bn * 22, "heading_deg": math.degrees(math.atan2(bt[0], bt[1]))}


# ------------------------------------------------------------------ hamlets
def layout_hamlet(town, ctx, road_pt, road_dir, kind):
    """A hamlet off a road: a short lane from the road with houses (village) or a farm
    courtyard (farmstead). `road_pt` is where the lane leaves the road."""
    rng = town.rng
    land = land_fn(ctx, 1.5)
    out = unit(town.center - road_pt)
    L = float(np.hypot(*(town.center - road_pt))) + 40
    lane = resample_line(np.vstack([road_pt, road_pt + out * L]), 6.0)
    town.main_street = town.add_street("main", 5.5 if kind != "farmstead" else 4.5, lane)
    set_rule(town, town.main_street, ("land", None))
    town.plaza = road_pt + out * (L - 10)
    fl = lambda: int(rng.integers(1, 3))
    if kind == "farmstead":
        _farm(town, road_pt + out * (L - 8), math.atan2(out[1], out[0]), land)
        town.line_plots(town.main_street, 1, None, (7, 11), (8, 12), land, start=14, floors=fl, kinds=["house", "barn", "granary"], max_plots=3)
    else:
        for side in (1, -1):
            town.line_plots(town.main_street, side, None, (6, 10), (8, 12), land, start=14, floors=fl,
                            kinds=["house"] * 5 + ["barn", "shop"], max_plots=5)
        if rng.random() < 0.6:
            town.try_plot("church", town.plaza + out * 18, -out, 9, 15, 1, [], land)
