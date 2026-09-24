"""Material maps for the outer world: splat weights, auxiliary masks (forest density, flatten,
biome id), the macro tint and the far-distance road mask.

Biome ids are Terrain.Biome: SEA 0, LIMESTONE 1, FOREST 2, FARM 3, BADLANDS 4, TOWN 5, BEACH 6,
LAKE 7, DUNES 8, MOOR 9, SALTFLAT 10.
"""
import numpy as np
from scipy import ndimage
import cv2
import outer_land as L
import outer_noise as NZ

SEA, LIMESTONE, FOREST, FARM, BADLANDS, TOWN, BEACH, LAKE, DUNES, MOOR, SALTFLAT = range(11)


def smoothstep(a, b, v):
    t = np.clip((v - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def slope_of(h):
    gz, gx = np.gradient(h, L.STEP)
    return np.hypot(gx, gz)        # rise over run


def paint(h, fields, flat, towns, lake_mask, lake_level, field_mask_out=None, feat=None, rivers=()):
    x, z = L.grid()
    if feat is None: feat = np.zeros(h.shape + (4,))
    wadi = feat[..., 0]; irr = feat[..., 1]; erg = feat[..., 2]
    s = slope_of(ndimage.gaussian_filter(h, 0.7))
    wN, wS, wE, wW = fields["wN"], fields["wS"], fields["wE"], fields["wW"]
    n1 = NZ.fbm(x, z, 501, 900.0, 4)          # patches
    n2 = NZ.fbm(x, z, 502, 260.0, 3)
    n3 = NZ.fbm(x, z, 503, 3000.0, 3)
    land = h > 0.0
    # ---------------- farmland: the eastern plains and the valley floors near the towns
    farm = wE * smoothstep(0.10, 0.03, s) * smoothstep(1.0, 4.0, h) * smoothstep(120, 60, h)
    farm = np.maximum(farm, (1 - wN) * (1 - wS) * (1 - wW) * smoothstep(0.07, 0.02, s) * smoothstep(3.0, 6.0, h)
                      * smoothstep(90, 50, h) * smoothstep(-0.05, 0.25, n3) * 0.9)
    farm *= smoothstep(-0.35, -0.05, n1 * 0.6 + n3 * 0.5)
    # the oases: irrigated plots in the desert
    farm = np.maximum(farm, irr * smoothstep(0.12, 0.04, s) * 0.95)
    farm = np.where(lake_mask > 0, 0, farm)
    # ---------------- sand: beaches, dunes on the southern bays, the estuary banks
    shore = land & (h < 3.5)
    beach = smoothstep(4.5, 1.5, h) * smoothstep(0.25, 0.08, s) * land
    beach = np.maximum(beach, (h <= 0.0) * smoothstep(-4.0, -0.5, h))    # the seabed near the shore
    # the south: sand drifts only in the hollows now (the erg and the wadi beds carry the sand), so
    # the plateau between them reads as gravel plain and rock rather than one sheet of orange
    desert_sand = wS * smoothstep(0.06, 0.015, s) * smoothstep(0.25, 0.6, n1 * 0.5 + n2 * 0.5 + 0.2) * 0.55
    sand = np.clip(np.maximum.reduce([beach, desert_sand, erg * 0.98, wadi * 0.75 * smoothstep(0.35, 0.15, s)]), 0, 1)
    # river beds: gravel bars and sand along the northern rivers
    rbank = np.zeros(h.shape)
    for rv in rivers:
        P = np.array([[q[0], q[2]] for q in rv["points"]]); w = np.array([q[3] for q in rv["points"]])
        if len(P) > 1: _band(rbank, P, w * 0.5 + 3.0, 10.0)
    sand = np.maximum(sand, rbank * 0.45 * (1 - wS))
    # ---------------- rock: steep ground, the alpine crest, mesa rims and canyon walls
    rock = smoothstep(0.55, 0.95, s + n2 * 0.08)
    rock = np.maximum(rock, smoothstep(950, 1150, h + n1 * 60) * 0.85)
    rock = np.maximum(rock, wS * smoothstep(0.3, 0.6, s + n2 * 0.1) * (1 - erg))
    rock = np.maximum(rock, wW * smoothstep(0.4, 0.7, s) )
    # ---------------- snow: above ~850 m on the gentler faces, patchy toward its lower edge
    snow_line = 860 + n1 * 70 + n2 * 25
    snow = smoothstep(snow_line, snow_line + 120, h) * smoothstep(1.3, 0.8, s)
    rock = rock * (1 - snow * 0.8)
    # ---------------- biome ids
    biome = np.full(h.shape, FOREST, np.uint8)
    biome[wE * farm > 0.3] = FARM
    biome[farm > 0.45] = FARM
    moor = (h > 520) | ((wW > 0.5) & (h > 180))
    biome[moor] = MOOR
    biome[(h > 950) | (rock > 0.6)] = LIMESTONE
    arid = wS > 0.45
    biome[arid] = BADLANDS
    biome[arid & (sand > 0.5)] = DUNES
    biome[erg > 0.5] = DUNES
    biome[(irr > 0.5) & (farm > 0.4)] = FARM
    biome[land & (beach > 0.5)] = BEACH
    biome[~land] = SEA
    biome[(lake_mask > 0) & (h < lake_level + 0.5)] = LAKE
    # towns
    tmask = np.zeros(h.shape, bool)
    for t in towns:
        if t.hamlet: continue
        i = int((t.center[0] - L.ORIGIN) / L.STEP); j = int((t.center[1] - L.ORIGIN) / L.STEP)
        r = int(t.radius * 0.8 / L.STEP)
        yy, xx = np.ogrid[-r:r + 1, -r:r + 1]
        disc = (xx * xx + yy * yy) <= r * r
        sl = (slice(max(j - r, 0), j + r + 1), slice(max(i - r, 0), i + r + 1))
        sub = disc[: sl[0].stop - sl[0].start, : sl[1].stop - sl[1].start]
        tmask[sl] |= sub & (flat[sl] > 0.5)
    biome[tmask & land] = TOWN
    # ---------------- forest density
    forest = np.zeros(h.shape)
    alp_forest = wN * smoothstep(120, 260, h) * smoothstep(1250, 950, h + n1 * 80) * smoothstep(0.2, 0.55, n1 * 0.5 + n3 * 0.5 + 0.5)
    low_forest = (1 - wN) * (1 - wS) * smoothstep(0.05, 0.35, n1 * 0.7 + n3 * 0.4) * 0.8
    west_scrub = wW * smoothstep(-0.1, 0.3, n1 + 0.2 * n2) * 0.85
    south_scrub = wS * smoothstep(0.25, 0.55, n1) * 0.35
    # riparian growth: oleander and tamarisk along the wadi banks, poplars and willows by the rivers,
    # palms and orchards in the oases
    bank = np.clip(ndimage.maximum_filter(wadi, 5) - wadi * 0.8, 0, 1)
    riparian = np.maximum(bank * 0.75 * wS, rbank * 0.6)
    oasis = irr * 0.55
    forest = np.maximum.reduce([alp_forest, low_forest, west_scrub, south_scrub * (1 - erg), riparian, oasis])
    forest *= (1 - farm * 0.9) * land * smoothstep(1.8, 5.0, h) * (1 - np.clip(flat, 0, 1)) * smoothstep(1.2, 0.6, s)
    forest *= (1 - snow)
    forest *= 1 - smoothstep(0.3, 0.7, erg)
    # ---------------- splat maps
    splat = np.stack([rock, sand, farm, snow], -1)
    splat = np.clip(splat, 0, 1)
    tot = splat.sum(-1, keepdims=True)
    splat = np.where(tot > 1, splat / np.maximum(tot, 1e-6), splat)
    # dryness (0 lush -> 1 parched): south dry, north lush
    dry = np.clip(0.35 + 0.55 * wS - 0.35 * wN - 0.15 * wW + 0.2 * wE * 0 + n3 * 0.15, 0, 1)
    aux = np.stack([forest, np.clip(flat, 0, 1), biome / 255.0, dry], -1)
    # ---------------- macro tint (sRGB-ish multiplier, 0.5 = x1 in the shader)
    tint = macro_tint(h, s, biome, n1, n2, n3, wN, wS, wE, wW, farm, forest, dry, feat, rock)
    # ---------------- cavity: valleys and gullies darker, crests lighter (far-view occlusion)
    cav = np.zeros(h.shape)
    for sig, wgt, sc in ((1.5, 0.45, 6.0), (5.0, 0.35, 18.0), (16.0, 0.20, 45.0)):
        cav += wgt * np.clip((ndimage.gaussian_filter(h, sig) - h) / sc, -1, 1)
    feat = feat.copy()
    feat[..., 3] = np.clip(0.5 + 0.5 * cav, 0, 1) * land + 0.5 * (1 - land)
    return splat, aux, tint, biome, feat


def _band(img, P, half, soft):
    """max-paint a soft band round a polyline (half widths per point) into img."""
    import outer_route as R
    dist = np.full(img.shape, 1e9); yt = np.zeros(img.shape); hw = np.zeros(img.shape)
    R.carve_roads(img, L.ORIGIN, L.STEP, P[:, 0].copy(), P[:, 1].copy(), np.zeros(len(P)), np.asarray(half, float),
                  np.ones(len(P) - 1, np.uint8), 0.0, soft, dist, yt, hw)
    m = dist < 1e8
    v = np.zeros(img.shape)
    v[m] = 1.0 - smoothstep(hw[m], hw[m] + soft, dist[m])
    np.maximum(img, v, out=img)


def macro_tint(h, s, biome, n1, n2, n3, wN, wS, wE, wW, farm, forest, dry, feat=None, rock=None):
    """Broad colour variation over the base textures (multiplier; 1.0 = texture as is)."""
    lush = np.array([0.80, 1.02, 0.72]); straw = np.array([1.10, 1.00, 0.72])
    olive = np.array([0.92, 0.98, 0.74]); ochre = np.array([1.06, 0.97, 0.80])
    red = np.array([1.10, 0.90, 0.76]); alpine = np.array([0.86, 0.98, 0.84])
    grey = np.array([0.98, 0.98, 0.96])
    t = np.zeros(h.shape + (3,))
    base = lush[None, None] * (1 - dry[..., None]) + straw[None, None] * dry[..., None]
    base = base * (1 + 0.10 * n1[..., None]) * (1 + 0.05 * n2[..., None])
    base = base * (1 - wN[..., None] * 0.3) + alpine[None, None] * wN[..., None] * 0.3 * (1 + 0.1 * n1[..., None])
    arid = ochre[None, None] * (1 - smoothstep(0.2, 0.6, n3)[..., None]) + red[None, None] * smoothstep(0.2, 0.6, n3)[..., None]
    base = base * (1 - wS[..., None] * 0.7) + arid * wS[..., None] * 0.7
    base = base * (1 - forest[..., None] * 0.18)
    t = base
    t = np.where((biome == LIMESTONE)[..., None], grey[None, None] * (1 + 0.06 * n2[..., None]), t)
    if feat is not None:
        wadi = feat[..., 0][..., None]; irr = feat[..., 1][..., None]; erg = feat[..., 2][..., None]
        S = wS[..., None]
        # the south, zone by zone: dark gravel plains (reg) on the flat plateau, pale sand seas, bleached
        # wadi floors, red-brown badland slopes, green irrigated plots
        flatness = smoothstep(0.08, 0.02, s)[..., None]
        reg = np.array([0.90, 0.74, 0.58]) * (1 + 0.08 * n2[..., None])      # varnished, warm brown
        t = t * (1 - S * flatness * 0.55 * (1 - erg)) + reg * S * flatness * 0.55 * (1 - erg)
        badl = np.array([1.12, 0.86, 0.70]) * (1 + 0.1 * n1[..., None])
        steep = smoothstep(0.12, 0.35, s)[..., None]
        t = t * (1 - S * steep * 0.5) + badl * S * steep * 0.5
        sandsea = np.array([1.20, 1.04, 0.80]) * (1 + 0.05 * n2[..., None])
        t = t * (1 - erg) + sandsea * erg
        bleach = np.array([1.22, 1.14, 1.00])
        t = t * (1 - wadi * 0.7) + bleach * wadi * 0.7
        green = np.array([0.62, 0.98, 0.46]) * (1 + 0.1 * n2[..., None])
        t = t * (1 - irr * 0.85) + green * irr * 0.85
        # the scrub belt between the green north and the desert: olive / sage mottling
        belt = (smoothstep(0.1, 0.35, wS) * smoothstep(0.75, 0.45, wS))[..., None]
        sage = np.array([0.92, 0.96, 0.74]) * (1 + 0.12 * n2[..., None])
        t = t * (1 - belt * 0.45) + sage * belt * 0.45
    return np.clip(t, 0.3, 1.9)


def road_mask(roads, n=4096, ss=2):
    """Road coverage at 25000/n m per pixel (supersampled x ss)."""
    size = n * ss
    img = np.zeros((size, size), np.uint8)
    k = size / 25000.0
    for r in roads:
        pts = r["pts"]
        w = r["width"] * (0.9 if r["class"] != "track" else 0.8)
        th = max(1, int(round(w * k)))
        p = np.round((pts + 12500.0) * k * 16).astype(np.int32)
        cv2.polylines(img, [p.reshape(-1, 1, 2)], False, 255, th, cv2.LINE_AA, shift=4)
    img = cv2.resize(img, (n, n), interpolation=cv2.INTER_AREA)
    return img
