"""Water and desert landforms for the outer world, applied to the eroded heightfield before the
towns and roads are laid out (outer.py `stage_landscape`):

  - hydrology: priority-flood drainage (every cell drains to the sea), D8 receivers and the
    upstream area of every cell;
  - rivers: the few biggest channels outside the arid south, traced from their heads to the sea,
    the estuary or the lagoon, carved as a bed with banks; their water surface is a polyline with
    a monotone level (plan.json `rivers`, drawn by world/outer/outer_rivers.gd);
  - wadis: the dry river beds of the south (and the Rambla), shallow braided sand-and-gravel beds
    with oleander and tamarisk along the banks (feature map, no water);
  - the erg: a sand sea east of the mesas, a smoothed basin covered by transverse dunes;
  - oases: irrigated plots and palm groves in the Rambla near the coast and round Sarmada.

Everything is on the N x N data grid (x = ORIGIN + i * STEP, z = ORIGIN + j * STEP).
"""
import math
import numpy as np
from numba import njit
from scipy import ndimage
import outer_land as L
import outer_noise as NZ
import outer_route as R

N, STEP, ORIGIN = L.N, L.STEP, L.ORIGIN

# the sand sea east of the mesas: centre, radii (x, z), rotation; dunes trend NW-SE (wind from NE)
ERG = (6500.0, 4650.0, 2000.0, 1250.0, 0.35)
ERG_WAVE = 230.0            # crest spacing (m)
ERG_AMP = 16.0              # dune height (m)
# irrigated oases: (x, z, radius): the Rambla's mouth above Sarmada, the Sarmada palm grove, two
# desert hamlets' gardens (the plan adds the Sarmada grove as an `oasis` landmark already)
OASES = [(1750.0, 7650.0, 420.0), (3180.0, 8450.0, 260.0), (1500.0, 6900.0, 260.0), (-300.0, 8250.0, 200.0)]
RIVER_AREA_KM2 = 7.0        # upstream area where a channel becomes a river (non-arid land)
WADI_AREA_KM2 = 2.5         # ... or a wadi (the arid south)
MAX_RIVERS = 7


# ------------------------------------------------------------------ drainage
@njit(cache=True)
def _push(hf, hn, size, f, node):
    i = size
    hf[i] = f; hn[i] = node
    while i > 0:
        p = (i - 1) >> 1
        if hf[p] <= hf[i]: break
        hf[p], hf[i] = hf[i], hf[p]
        hn[p], hn[i] = hn[i], hn[p]
        i = p
    return size + 1


@njit(cache=True)
def _pop(hf, hn, size):
    f = hf[0]; node = hn[0]
    size -= 1
    hf[0] = hf[size]; hn[0] = hn[size]
    i = 0
    while True:
        l = 2 * i + 1; r = l + 1; m = i
        if l < size and hf[l] < hf[m]: m = l
        if r < size and hf[r] < hf[m]: m = r
        if m == i: break
        hf[m], hf[i] = hf[i], hf[m]
        hn[m], hn[i] = hn[i], hn[m]
        i = m
    return f, node, size


@njit(cache=True)
def drainage(h, outlet):
    """Priority flood from the outlet cells (sea, map border): returns (receiver, order, filled).
    receiver[c] = the cell c drains into (-1 for outlets); order = cells from the outlets upward
    (every cell comes after its receiver), so a reverse sweep accumulates areas."""
    n0, n1 = h.shape
    total = n0 * n1
    rec = np.full(total, -1, np.int64)
    done = np.zeros(total, np.uint8)
    filled = h.ravel().copy()
    order = np.empty(total, np.int64)
    hf = np.empty(total + 8); hn = np.empty(total + 8, np.int64)
    size = 0; no = 0
    for j in range(n0):
        for i in range(n1):
            c = j * n1 + i
            if outlet[j, i] or i == 0 or j == 0 or i == n1 - 1 or j == n0 - 1:
                done[c] = 1
                size = _push(hf, hn, size, filled[c], c)
    di = (1, 1, 0, -1, -1, -1, 0, 1)
    dj = (0, 1, 1, 1, 0, -1, -1, -1)
    while size > 0:
        f, c, size = _pop(hf, hn, size)
        order[no] = c; no += 1
        ci = c % n1; cj = c // n1
        for k in range(8):
            ni = ci + di[k]; nj = cj + dj[k]
            if ni < 0 or nj < 0 or ni >= n1 or nj >= n0: continue
            nn = nj * n1 + ni
            if done[nn]: continue
            done[nn] = 1
            rec[nn] = c
            e = 1e-3 * (1.4142 if (di[k] != 0 and dj[k] != 0) else 1.0)
            if filled[nn] < f + e: filled[nn] = f + e
            size = _push(hf, hn, size, filled[nn], nn)
    return rec, order[:no], filled.reshape(n0, n1)


@njit(cache=True)
def accumulate(rec, order, weight):
    acc = weight.copy()
    for q in range(order.size - 1, -1, -1):
        c = order[q]
        r = rec[c]
        if r >= 0: acc[r] += acc[c]
    return acc


# ------------------------------------------------------------------ channel tracing
def trace_channels(rec, acc_km2, mask_ok, threshold_km2, stop, max_n, min_len_cells=40):
    """Channels whose upstream area exceeds the threshold: traced from their heads down the
    receivers, each ending where it meets the sea (`stop`), a bigger channel already traced, or the
    edge. Returns [(cells (list of flat idx), area_km2 at each cell)] biggest first."""
    n1 = N
    big = (acc_km2 >= threshold_km2) & mask_ok
    flat = big.ravel()
    # heads: channel cells with no channel cell draining into them
    has_up = np.zeros(flat.size, bool)
    idx = np.where(flat)[0]
    r = rec[idx]
    ok = r >= 0
    has_up[r[ok]] |= flat[idx[ok]]
    heads = idx[~has_up[idx]]
    # trace every head to its outlet; order channels by the area at their outlet
    paths = []
    for h0 in heads:
        path = [h0]; c = h0
        while True:
            nx = rec[c]
            if nx < 0: break
            path.append(nx)
            if stop.ravel()[nx]: break
            c = nx
            if len(path) > 20000: break
        paths.append(path)
    paths.sort(key=lambda p: -acc_km2.ravel()[p[-1]] - 1e-6 * len(p))
    taken = np.zeros(flat.size, bool)
    out = []
    for p in paths:
        seg = []
        for c in p:
            seg.append(c)
            if taken[c]: break
        # the part of the path not already a channel (plus the confluence cell)
        if len(seg) < min_len_cells: continue
        for c in seg: taken[c] = True
        out.append(seg)
        if len(out) >= max_n: break
    return out


def cells_to_xz(cells):
    c = np.asarray(cells)
    return np.stack([ORIGIN + (c % N) * STEP, ORIGIN + (c // N) * STEP], 1).astype(float)


# ------------------------------------------------------------------ the stage
def smoothstep(a, b, v):
    t = np.clip((v - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def erg_mask(x, z):
    ex, ez, rx, rz, yaw = ERG
    dx = x - ex; dz = z - ez
    c, s = math.cos(yaw), math.sin(yaw)
    u = (dx * c + dz * s) / rx; v = (-dx * s + dz * c) / rz
    rr = np.sqrt(u * u + v * v) + NZ.fbm(x, z, 701, 1100.0, 4) * 0.42 + NZ.fbm(x, z, 702, 300.0, 2) * 0.08
    return 1.0 - smoothstep(0.6, 1.05, rr)


def dunes(x, z):
    """Transverse dunes with sinuous, bifurcating crests: a gentle windward slope and a steep lee,
    crests perpendicular to the NE wind; 0..1."""
    def field(wind, wave, seed, warp):
        wx = x + NZ.fbm(x, z, seed, 650.0, 3) * warp
        wz = z + NZ.fbm(x + 333, z, seed + 1, 650.0, 3) * warp
        s = (wx * wind[0] + wz * wind[1]) / wave
        s = s + NZ.fbm(x, z, seed + 2, 1300.0, 2) * 0.9
        f = s - np.floor(s)
        # asymmetric profile: a long windward slope, a short steep lee (slip face)
        return np.where(f < 0.75, (f / 0.75) ** 1.6, 1.0 - smoothstep(0.75, 1.0, f))
    main = field(np.array([-0.62, 0.78]), ERG_WAVE, 711, 190.0)          # transverse, wind from the NE
    cross = field(np.array([0.85, 0.53]), ERG_WAVE * 0.55, 721, 120.0)   # a secondary set: linked, barchanoid crests
    # crest height varies along the crest; where the sets reinforce, tall star-like peaks
    amp = 0.55 + 0.45 * (NZ.fbm(x, z, 714, 380.0, 2) * 0.5 + 0.5)
    stars = smoothstep(0.35, 0.8, NZ.fbm(x, z, 715, 900.0, 2) * 0.5 + 0.5)
    return (main * amp * (0.8 + 0.2 * cross)) + cross * 0.3 * (0.4 + stars) + main * cross * stars * 0.6


def stage_landscape(h, fields):
    """Returns (h, feat, rivers, wadis): the heightfield with the erg, the carved river beds and
    wadis; feat (N, N, 4) float: R wadi / dry bed 0..1, G irrigation 0..1, B erg 0..1, A (unused
    here: cavity, filled by paint); rivers = [{"pts": (n, 2), "area": (n,), "width", "depth"}]."""
    x, z = L.grid()
    wS = fields["wS"]; wN = fields["wN"]
    h = h.copy()
    # ---- the erg: flatten the incised plateau into a basin, then raise the dunes over it
    em = erg_mask(x, z) * (h > 20)
    basin = ndimage.gaussian_filter(h, 22.0)                # ~275 m: the incised plateau becomes a basin
    ground = h + (basin - h) * smoothstep(0.0, 0.6, em)
    du = dunes(x, z) * ERG_AMP * smoothstep(0.2, 0.8, em)
    h = ground + du
    # ---- drainage over the land
    sea = h < 0.3
    lx, lz, lr, ll = L.LAKE
    lake = np.hypot(x - lx, z - lz) < lr + 60
    core = np.maximum(np.abs(x), np.abs(z)) < 1500
    rec, order, filled = drainage(h, sea)
    acc = accumulate(rec, order, np.full(N * N, STEP * STEP / 1e6))
    acc2 = acc.reshape(N, N)
    stop = sea | lake | core
    arid = (wS > 0.35).ravel()
    # ---- rivers: the biggest channels on the green land (not the arid south)
    ok_river = (~(wS > 0.35)) & ~lake & ~core & (h > 0.3)
    rivers = []
    for cells in trace_channels(rec, acc2, ok_river, RIVER_AREA_KM2, stop | (wS > 0.35), MAX_RIVERS, 60):
        pts = cells_to_xz(cells)
        area = acc[np.asarray(cells)]
        rivers.append({"cells": cells, "area": area})
    # ---- wadis: the dry beds of the arid south
    ok_wadi = (wS > 0.3) & ~core & (h > 0.3) & (em < 0.5)
    wadis = []
    for cells in trace_channels(rec, acc2, ok_wadi, WADI_AREA_KM2, stop | (em > 0.5), 60, 30):
        wadis.append({"cells": cells, "area": acc[np.asarray(cells)]})
    # ---- carve: rivers get a bed and banks, wadis a broad shallow floor
    dist = np.full(h.shape, 1e9); yt = np.zeros(h.shape); hw = np.zeros(h.shape)
    wadi_bed = np.zeros(h.shape)
    out_rivers = []
    for rv in rivers:
        P = cells_to_xz(rv["cells"])
        a = rv["area"]
        P, a = _smooth_channel(P, a, 4.0)
        g = _bil(h, P)
        width = np.clip(5.0 + 4.5 * np.sqrt(a), 6.0, 34.0)
        depth = np.clip(1.4 + 0.35 * np.sqrt(a), 1.4, 3.6)
        bed = np.minimum.accumulate(ndimage.minimum_filter1d(g, 5)) - depth
        R.carve_roads(h, ORIGIN, STEP, P[:, 0].copy(), P[:, 1].copy(), bed.astype(np.float64), width * 0.5,
                      np.ones(len(P) - 1, np.uint8), 2.0, 14.0, dist, yt, hw)
        level = bed + depth * 0.62
        out_rivers.append({"pts": P, "area": a, "width": width, "depth": depth, "bed": bed, "level": level})
    hc, w = R.apply_carve(h, dist, yt, hw, 2.0, 14.0)
    h = np.minimum(h, hc)
    for wd in wadis:
        P = cells_to_xz(wd["cells"])
        a = wd["area"]
        P, a = _smooth_channel(P, a, 6.0)
        width = np.clip(12.0 + 9.0 * np.sqrt(a), 14.0, 90.0)
        _paint_line(wadi_bed, P, width * 0.5, 18.0)
    # the wadi floors: a gentle flattening toward their local minimum (braided, shallow)
    lowf = ndimage.minimum_filter(h, 3)
    h = h - (h - lowf) * np.clip(wadi_bed, 0, 1) * 0.55
    # the Rambla is one big wadi (the valley shaped in outer_land)
    rd, rt = L.polyline_distance(x, z, L.SOUTH_VALLEY)
    rambla = (1.0 - smoothstep(90.0, 260.0, rd + NZ.fbm(x, z, 721, 300.0, 3) * 70.0)) * smoothstep(0.02, 0.1, rt)
    wadi_bed = np.maximum(wadi_bed, rambla * 0.9)
    # ---- oases: irrigated gardens and palm groves (feature only; the paint makes them fields)
    irr = np.zeros(h.shape)
    patchy = smoothstep(-0.25, 0.15, NZ.fbm(x, z, 732, 160.0, 3))
    for ox, oz, orad in OASES:
        d = np.hypot(x - ox, z - oz) + NZ.fbm(x, z, 731, 260.0, 3) * orad * 0.6
        irr = np.maximum(irr, (1.0 - smoothstep(orad * 0.45, orad, d)) * patchy)
    # the irrigated plots follow the Rambla's floor near the coast rather than a round blob
    rdv, rtv = L.polyline_distance(x, z, L.SOUTH_VALLEY)
    irr *= np.where(rdv < 400, 1.0, 1.0 - smoothstep(400, 700, rdv) * 0.6)
    irr *= (h > 1.0)
    feat = np.zeros(h.shape + (4,))
    feat[..., 0] = np.clip(wadi_bed, 0, 1)
    feat[..., 1] = irr
    feat[..., 2] = em
    return h, feat, out_rivers


def _bil(h, P):
    gx = (P[:, 0] - ORIGIN) / STEP; gz = (P[:, 1] - ORIGIN) / STEP
    i = np.clip(np.floor(gx).astype(int), 0, N - 2); j = np.clip(np.floor(gz).astype(int), 0, N - 2)
    u = gx - i; v = gz - j
    return h[j, i] * (1 - u) * (1 - v) + h[j, i + 1] * u * (1 - v) + h[j + 1, i] * (1 - u) * v + h[j + 1, i + 1] * u * v


def _smooth_channel(P, a, step):
    """Grid staircase -> a meandering smooth line every `step` m (areas carried along)."""
    cum0 = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(P, axis=0).T))])
    Q = R.chaikin(R.rdp(P, 7.0), 3)
    Q = R.resample(Q, step)
    cum = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(Q, axis=0).T))])
    aa = np.interp(cum / max(cum[-1], 1e-6) * cum0[-1], cum0, a)
    return Q, aa


def _paint_line(img, P, half, soft):
    """max-paint a soft band of `half` metres round the polyline into img (0..1)."""
    dist = np.full(img.shape, 1e9); yt = np.zeros(img.shape); hw = np.zeros(img.shape)
    R.carve_roads(img, ORIGIN, STEP, P[:, 0].copy(), P[:, 1].copy(), np.zeros(len(P)), np.asarray(half, float) * np.ones(len(P)),
                  np.ones(len(P) - 1, np.uint8), 0.0, soft, dist, yt, hw)
    m = dist < 1e8
    v = np.zeros(img.shape)
    v[m] = 1.0 - smoothstep(hw[m], hw[m] + soft, dist[m])
    np.maximum(img, v, out=img)


def river_levels(h_final, rivers):
    """After every carve: the water level along each river, never above its banks and monotone
    downstream; runs where the ground over the channel stands above the water (a road embankment,
    a town pad) split the river. Returns the export records."""
    out = []
    k = 0
    for rv in rivers:
        P = rv["pts"]; lv = rv["level"].copy(); w = rv["width"]
        g = _bil(h_final, P)
        lv = np.minimum.accumulate(np.minimum(lv, g + rv["depth"] * 0.62))
        lv = np.maximum(lv, 0.05)
        # buried: the ground at the centre above the water by more than 0.4 m
        wet = g < lv + 0.4
        lab, nl = ndimage.label(wet)
        for q in range(1, nl + 1):
            idx = np.where(lab == q)[0]
            if len(idx) < 12: continue
            a, b = idx[0], idx[-1] + 1
            out.append({"id": "river.%d" % k, "points": [[round(float(P[i, 0]), 2), round(float(lv[i]), 2), round(float(P[i, 1]), 2),
                        round(float(w[i]), 2)] for i in range(a, b)]})
            k += 1
    return out


def river_distance_fn(rivers):
    """(pts (n, 2)) -> (distance to the nearest river channel edge, that river's level there)."""
    segs = []
    for rv in rivers:
        P = rv["pts"]
        for i in range(len(P) - 1):
            segs.append((P[i], P[i + 1], rv["width"][i] * 0.5, rv["level"][i]))
    if not segs:
        return lambda pts: (np.full(len(pts), 1e9), np.zeros(len(pts)))
    A = np.array([s[0] for s in segs]); B = np.array([s[1] for s in segs])
    H = np.array([s[2] for s in segs]); LV = np.array([s[3] for s in segs])
    lo = np.minimum(A, B) - 60; hi = np.maximum(A, B) + 60

    def f(pts):
        d = np.full(len(pts), 1e9); lvl = np.zeros(len(pts))
        for k, p in enumerate(pts):
            m = (p[0] > lo[:, 0]) & (p[0] < hi[:, 0]) & (p[1] > lo[:, 1]) & (p[1] < hi[:, 1])
            if not m.any(): continue
            a = A[m]; b = B[m]; ab = b - a
            t = np.clip(((p - a) * ab).sum(1) / np.maximum((ab * ab).sum(1), 1e-9), 0, 1)
            dd = np.hypot(*(a + ab * t[:, None] - p).T) - H[m]
            q = int(np.argmin(dd))
            d[k] = dd[q]; lvl[k] = LV[m][q]
        return d, lvl
    return f
