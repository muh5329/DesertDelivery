"""The outer world's landforms: coastline, regions, mountains, plateau, plains, archipelago,
erosion, the lagoon round the core, the estuary and the mountain lake.

All arrays are (N, N) indexed [j, i] with x = ORIGIN + i * STEP, z = ORIGIN + j * STEP
(row-major by z, -z = north). Heights in metres, sea level 0.
"""
import numpy as np
from scipy import ndimage
import outer_noise as nz

N = 2001
STEP = 12.5
ORIGIN = -12500.0
CORE_HALF = 624.0

# ------------------------------------------------------------------ design constants (metres)
# the estuary: from the lagoon's east shore to the eastern bay (polyline, width, depth)
ESTUARY = [(1350, 260), (2300, 420), (3300, 640), (4300, 520), (5300, 760), (6300, 1060),
           (7000, 1240), (7700, 1330), (8400, 1560), (9200, 1750), (10400, 1900)]
ESTUARY_W0, ESTUARY_W1 = 190.0, 320.0
ESTUARY_DEPTH = 13.0
# the eastern bay (sea) and the southern bay
EAST_BAY = (10150.0, 1950.0, 2050.0)      # centre x, z, radius
SOUTH_BAY = (1450.0, 10050.0, 1850.0)
# Puerto Alto's hills: the castle hill (old town) and the heights west of the city
PA_HILLS = [(7760, 2170, 270, 46.0), (6900, 2300, 420, 34.0), (7950, 2780, 380, 30.0)]
# the mountain lake (reservoir) in the northern range and its dam
LAKE = (2350.0, -7250.0, 640.0, 760.0)    # centre x, z, radius, water level
DAM = (2330.0, -6560.0)
# Valdoro's valley: a glacial trough from the foothills up into the range
VALDORO_VALLEY = [(-300, -2300), (-850, -3500), (-900, -4300), (-1250, -5000), (-1300, -5800), (-1850, -6600), (-2150, -7400), (-2700, -8200)]
# western archipelago: (x, z, rx, rz, height, yaw)
ISLANDS = [(-9350, 1250, 1900, 1250, 150, 0.35), (-8150, -2450, 950, 700, 110, -0.4), (-10450, -1350, 700, 520, 80, 0.2),
           (-8350, 3900, 820, 600, 90, 0.8), (-10850, 3350, 520, 420, 60, 0.1), (-11050, -150, 380, 300, 45, 0.0),
           (-7950, -4700, 650, 480, 95, 0.6), (-9650, 5650, 500, 380, 55, -0.3), (-11250, -3550, 420, 330, 50, 0.4),
           (-10200, 6800, 300, 240, 35, 0.2), (-11600, 1900, 260, 200, 30, 0.0), (-9000, -3900, 300, 260, 40, 0.0)]


def grid():
    a = ORIGIN + np.arange(N) * STEP
    x, z = np.meshgrid(a, a)
    return x, z


def smoothstep(a, b, v):
    t = np.clip((v - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def polyline_distance(x, z, pts):
    """Distance from every grid point to a polyline, and the along-line parameter 0..1."""
    pts = np.asarray(pts, float)
    best = np.full(x.shape, 1e12); along = np.zeros(x.shape)
    seg = np.linalg.norm(pts[1:] - pts[:-1], axis=1)
    cum = np.concatenate([[0], np.cumsum(seg)]); total = cum[-1]
    for k in range(len(pts) - 1):
        a = pts[k]; b = pts[k + 1]; ab = b - a
        t = np.clip(((x - a[0]) * ab[0] + (z - a[1]) * ab[1]) / (ab @ ab), 0, 1)
        d = np.hypot(x - (a[0] + ab[0] * t), z - (a[1] + ab[1] * t))
        m = d < best
        best[m] = d[m]; along[m] = (cum[k] + t[m] * seg[k]) / total
    return best, along


def coast_field(x, z):
    """Signed distance-like coast function: > 0 on the mainland (metres inland), < 0 offshore."""
    r = np.hypot(x, z)
    th = np.arctan2(z, x)                                  # 0 = east, +pi/2 = south
    # control radii by bearing (every 22.5 deg from east, clockwise through south)
    ang = np.arange(17) * (np.pi / 8)
    rad = np.array([9500, 10300, 10900, 9600, 10000, 10700, 9000, 7600, 6900, 7300, 7400, 9600,
                    10700, 11000, 11600, 10300, 9500], float)
    thp = np.mod(th, 2 * np.pi)
    R = np.interp(thp, ang, rad)
    west = smoothstep(-3000, -6500, x)                    # the west breaks into rugged coves
    # warped outline: capes and bays (~4 km), headlands (~1.3 km), ragged coves (~400 m)
    qx = x + nz.fbm(x, z, 14, 2500.0, 3) * 700
    qz = z + nz.fbm(x + 999, z, 15, 2500.0, 3) * 700
    w1 = nz.fbm(qx, qz, 11, 5200.0, 3)
    w2 = nz.fbm(qx * 1.3 + 500, qz * 1.3, 12, 1300.0, 4)
    w3 = nz.fbm(qx, qz, 13, 380.0, 3)
    R = R + w1 * 2300 + w2 * (700 + 600 * west) + w3 * (120 + 180 * west)
    c = R - r
    # the two bays
    for bx, bz, br in (EAST_BAY, SOUTH_BAY):
        d = np.hypot(x - bx, z - bz)
        c = np.minimum(c, (d - br) * 1.0 + nz.fbm(x, z, 17, 700.0, 3) * 220 + nz.fbm(x, z, 18, 1800.0, 3) * 450)
    return c


def lagoon_field(x, z):
    """> 0 outside the lagoon ring round the core (metres from its shore)."""
    p = 3.0
    d = (np.abs(x) ** p + np.abs(z) ** p) ** (1 / p)      # rounded square
    shore = 1480 + nz.fbm(x, z, 21, 1100.0, 3) * 260 + nz.fbm(x, z, 22, 300.0, 2) * 60
    return d - shore


def base_heights():
    x, z = grid()
    c = coast_field(x, z)
    lag = lagoon_field(x, z)
    # region weights
    wN = smoothstep(-2300, -5200, z)
    wS = smoothstep(2400, 5200, z) * (1 - wN)
    wE = smoothstep(2000, 4600, x) * (1 - wN) * (1 - wS)
    wW = smoothstep(-2300, -5000, x) * (1 - wN) * (1 - wS)
    # domain warp shared by the relief fields
    wx = x + nz.fbm(x, z, 31, 3200.0, 3) * 900 + nz.fbm(x, z, 33, 700.0, 2) * 160
    wz = z + nz.fbm(x + 7000, z - 3000, 32, 3200.0, 3) * 900 + nz.fbm(x, z, 34, 700.0, 2) * 160
    lowf = nz.fbm(wx, wz, 41, 2600.0, 5)                  # -1..1 broad hills
    detail = nz.fbm(wx, wz, 42, 420.0, 4)
    inland = smoothstep(0, 3200, c)
    # --- lowland (the centre ring round the lagoon)
    h_low = 18 + 70 * inland + 55 * lowf + 9 * detail
    # --- north: the alpine range (ridged, with a main crest line and spurs)
    ridge = nz.ridged(wx * 0.85, wz * 1.15, 51, 5200.0, 7, gain=0.52, sharp=2.2)
    crest = smoothstep(-3200, -6800, z) * (1 - smoothstep(-9300, -10600, z))
    mass = nz.fbm(wx, wz, 52, 6000.0, 3) * 0.5 + 0.5
    h_alp = 150 + crest * (240 + 1150 * ridge ** 1.35 * (0.55 + 0.5 * mass)) + 50 * detail
    # --- south: the arid plateau with mesas and canyons
    plateau = 170 + 110 * (nz.fbm(wx, wz, 61, 5200.0, 3) * 0.5 + 0.5)
    mesa_n = nz.fbm(wx * 1.1, wz, 62, 1500.0, 4)
    mesa = smoothstep(0.05, 0.12, mesa_n) * (80 + 70 * smoothstep(0.2, 0.45, mesa_n))
    can_n = nz.fbm(wx, wz * 0.8, 63, 2600.0, 4)
    canyon = 1 - smoothstep(0.0, 0.06, np.abs(can_n)) ** 0.7
    can2 = 1 - smoothstep(0.0, 0.05, np.abs(nz.fbm(wx + 900, wz, 64, 1200.0, 3)))
    coastal = smoothstep(0, 2600, c)                       # the plateau steps down to the south coast
    h_s = (plateau + mesa) * (0.25 + 0.75 * coastal) + 14 * detail
    h_s = h_s - canyon * (h_s - 35) * 0.8 - can2 * 40 * coastal
    # --- east: the farmland plains (low, gently rolling) and the windmill ridge
    h_e = 12 + 38 * inland + 22 * lowf + 4 * detail
    rid_d, _ = polyline_distance(x, z, [(5900, -3350), (6500, -2900), (7100, -2500)])
    h_e = h_e + 38 * np.exp(-(rid_d / 220.0) ** 2)
    # --- west: rugged hills and headlands
    wr = nz.ridged(wx, wz, 71, 2300.0, 6, sharp=1.8)
    h_w = 40 + 230 * wr * (0.4 + 0.6 * inland) + 60 * lowf + 20 * detail
    for hx, hz, hr, hh in PA_HILLS:
        dd = np.hypot(x - hx, z - hz) + nz.fbm(x, z, 44, 300.0, 2) * 60
        h_e = h_e + hh * np.exp(-(dd / hr) ** 2)
        h_low = h_low + hh * np.exp(-(dd / hr) ** 2)
    wsum = wN + wS + wE + wW
    wL = np.clip(1 - wsum, 0, 1)
    h = (h_low * wL + h_alp * wN + h_s * wS + h_e * wE + h_w * wW) / (wL + wN + wS + wE + wW)
    # --- coast: cliffs in the west / north, gentle beaches in the east and the south bays
    gentle = smoothstep(1500, 5000, x) + smoothstep(6000, 8500, z) * (1 - smoothstep(-2500, -5000, x))
    gentle = np.clip(gentle, 0, 1)
    ramp_len = 180 + 650 * gentle
    land = smoothstep(0, ramp_len, c)
    land = land ** (0.5 + 0.5 * gentle)
    shore_h = 1.5 + 3.0 * gentle
    h = shore_h + (h - shore_h) * land
    # seabed: -3 at the shore to -40 about 3 km out
    sea = -2.0 - 38 * smoothstep(0, 3000, -c) - 4 * (1 - gentle) * smoothstep(0, 300, -c)
    h = np.where(c > 0, h, sea + nz.fbm(x, z, 81, 900.0, 3) * 2.0 * smoothstep(0, 400, -c))
    # --- archipelago
    for k, (ix, iz, rx, rz, ih, yaw) in enumerate(ISLANDS):
        dx = x - ix; dz = z - iz
        near = (np.abs(dx) < 2.2 * max(rx, rz)) & (np.abs(dz) < 2.2 * max(rx, rz))
        if not near.any(): continue
        sl = np.ix_(np.where(near.any(axis=1))[0], np.where(near.any(axis=0))[0])
        xs, zs = x[sl], z[sl]
        qx = xs + nz.fbm(xs, zs, 90 + k, 900.0, 3) * rx * 0.45
        qz = zs + nz.fbm(xs + 77, zs, 290 + k, 900.0, 3) * rz * 0.45
        dx = qx - ix; dz = qz - iz
        cy, sy = np.cos(yaw), np.sin(yaw)
        u = (dx * cy + dz * sy) / rx; v = (-dx * sy + dz * cy) / rz
        rr = np.sqrt(u * u + v * v) + nz.fbm(xs, zs, 190 + k, 300.0, 3) * 0.18 + nz.fbm(xs, zs, 390 + k, 110.0, 2) * 0.05
        prof = 1 - smoothstep(0.0, 1.0, rr)
        isl_h = -2.5 + (ih * (0.3 + 0.7 * nz.ridged(xs, zs, 95 + k, 900.0, 4)) * smoothstep(0.0, 0.6, prof) + 3.0 * smoothstep(0.0, 0.08, prof))
        shelf = -2.5 - 32 * smoothstep(1.0, 1.9, rr)
        isl = np.where(rr < 1.0, isl_h, shelf)
        hs = h[sl]
        h[sl] = np.where((rr < 2.0) & (isl > hs), isl, hs)
    # --- the lagoon ring round the core: -4 at the core edge down to -13, sloping up to the mainland
    lagoon_bed = -4.5 - 9.0 * smoothstep(CORE_HALF, 1100, np.maximum(np.abs(x), np.abs(z)))
    inner = smoothstep(-60, 380, lag)                      # 0 in the lagoon, 1 on the mainland
    lagoon_h = lagoon_bed + (h - lagoon_bed) * inner
    h = np.where(lag < 380, np.minimum(h, lagoon_h), h)
    fields = dict(x=x, z=z, c=c, lag=lag, wN=wN, wS=wS, wE=wE, wW=wW, gentle=gentle, crest=crest, canyon=canyon, mesa=mesa)
    return h, fields


def terrace(h, step, k=4.0):
    t = h / step
    f = t - np.floor(t)
    return (np.floor(t) + f ** k) * step


def shape(h, f):
    """Post shaping: plateau terraces, the Valdoro trough, the lake basin, the estuary."""
    x, z = f["x"], f["z"]
    # terraced mesas in the south: flat tops, stepped risers (only on land well above the sea)
    arid = f["wS"] * smoothstep(40, 90, h)
    ter = terrace(h, 24.0, 3.5)
    h = h + (ter - h) * arid * 0.85
    # Valdoro's valley: a U-shaped trough, floor rising from 60 m to 680 m
    d, t = polyline_distance(x, z, VALDORO_VALLEY)
    floor = 60 + 620 * t ** 1.3 + nz.fbm(x, z, 111, 600.0, 3) * 18
    width = 480 + 360 * t + nz.fbm(x, z, 112, 1500.0, 2) * 160
    u = np.clip(d / width, 0, 1)
    trough = floor + (h - floor) * (u ** 2.2)
    wv = 1 - smoothstep(0.85, 1.0, u)
    h = np.where(h > trough, h + (trough - h) * wv, h)
    # the mountain lake: a basin 30 m below the water level, rim kept above it
    lx, lz, lr, ll = LAKE
    ld = np.hypot(x - lx, z - lz) + nz.fbm(x, z, 101, 400.0, 3) * 150
    bowl = ll - 32 * (1 - smoothstep(0, lr, ld)) ** 0.7
    rim = np.maximum(h, ll + 8 + 60 * smoothstep(lr, lr + 900, ld))
    inside = ld < lr
    h = np.where(inside, np.minimum(h, bowl), h)
    ring = (ld >= lr) & (ld < lr + 700)
    blend = smoothstep(lr + 700, lr, ld)
    h = np.where(ring, h + (rim - h) * blend * (h < rim), h)
    # the lake's outlet gorge below the dam, draining south
    od, ot = polyline_distance(x, z, [(DAM[0], DAM[1] + 40), (2150, -5600), (1800, -4600), (1500, -3700)])
    gorge_floor = (ll - 60) - 520 * ot
    gw = 120 + 200 * ot
    gu = np.clip(od / gw, 0, 1)
    g = gorge_floor + (h - gorge_floor) * gu ** 1.6
    h = np.where((h > g) & (gu < 1) & ~inside, g, h)
    return h


def carve_estuary(h, f):
    x, z = f["x"], f["z"]
    d, t = polyline_distance(x, z, ESTUARY)
    width = ESTUARY_W0 + (ESTUARY_W1 - ESTUARY_W0) * t ** 1.5
    half = width * 0.5
    bed = -ESTUARY_DEPTH * (1 - (np.clip(d / half, 0, 1)) ** 2) - 1.0
    bank = smoothstep(half, half + 260 + 200 * t, d)      # banks rise over ~260-460 m
    carved = np.where(d < half, np.minimum(h, bed), h)
    shore = 0.8 + (np.maximum(h, 0.8) - 0.8) * bank
    carved = np.where((d >= half) & (d < half + 460 + 200 * t), np.minimum(carved, shore), carved)
    return carved


def erode(h, f, seed=7, droplets=900000):
    mask = np.clip(smoothstep(4, 40, h), 0, 1).astype(np.float64)
    # the lagoon and core stay untouched
    mask *= smoothstep(1400, 2200, np.maximum(np.abs(f["x"]), np.abs(f["z"])))
    hh = h.astype(np.float64).copy()
    nz.erode_hydraulic(hh, mask, droplets, seed, STEP, 2, 0.1, 5.0, 0.004, 0.35, 0.3, 0.015, 4.0, 110, 0.0)
    nz.erode_thermal(hh, mask, 25, 9.5, 0.5)
    return hh
