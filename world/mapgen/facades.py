"""Bakes the architecture kit's tileable PBR layers (assets/buildings/, read by ArchMaterials into two
Texture2DArrays, one layer per material, in the order of LAYERS below).

Packing (per layer, S x S, seamless):
  <name>_alb.png  RGB albedo (sRGB) + A tint mask: how much the per-vertex / per-instance tint
                  multiplies the albedo (1 = painted plaster, 0 = mortar, grout, glass, exposed stone)
  <name>_nrm.png  RG tangent-space normal (OpenGL, +y = image up) + B cavity AO + A roughness
UVs are in metres; each layer covers TILE_M metres (kept in sync with arch.gdshader).

Run from the project root:  python3 world/mapgen/facades.py   [--size 1024] [--only plaster,brick]
"""
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import cKDTree

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "buildings")
S = 1024

# name, metres per tile (the shader's TILE array uses the same numbers, same order)
LAYERS = [
    ("plaster", 3.0), ("whitewash", 3.0), ("rubble", 3.0), ("ashlar", 3.0), ("brick", 1.8),
    ("adobe", 3.0), ("azulejo", 1.12), ("roof_tile", 2.0), ("slate", 2.4), ("timber", 2.0),
    ("shutter", 1.0), ("glass", 1.0), ("iron", 1.0), ("stone", 2.0), ("door", 2.4),
    ("canvas", 2.0), ("terrace", 3.0),
]
TILE = dict(LAYERS)


# ---------------------------------------------------------------- tileable primitives
def fbm(seed, beta=2.0, fmin=1.0, fmax=None, aniso=(1.0, 1.0)):
    """Seamless 1/f^beta noise (FFT), zero mean, unit std. Frequencies in cycles per tile;
    aniso stretches: (1, 0.1) = long in y (streaks), (0.1, 1) = long in x."""
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((S, S))
    fy = np.fft.fftfreq(S)[:, None] * S
    fx = np.fft.fftfreq(S)[None, :] * S
    f = np.sqrt((fx * aniso[0]) ** 2 + (fy * aniso[1]) ** 2)
    f[0, 0] = 1.0
    amp = f ** (-beta / 2.0)
    amp *= 1.0 / (1.0 + np.exp(-(f - fmin) * 2.0))
    if fmax is not None:
        amp *= 1.0 / (1.0 + np.exp((f - fmax) * 0.5))
    amp[0, 0] = 0.0
    r = np.real(np.fft.ifft2(np.fft.fft2(w) * amp))
    return (r - r.mean()) / (r.std() + 1e-9)


def n01(x):
    return (x - x.min()) / (x.max() - x.min() + 1e-9)


def blur(x, s):
    return ndimage.gaussian_filter(x, s, mode="wrap")


def grid():
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    return xx + 0.5, yy + 0.5


def cells(seed, n, stretch=(1.0, 1.0), warp=0.0, warp_seed=0, jitter_grid=False):
    """Periodic Voronoi. Returns (edge distance in px, cell id, d1). stretch > 1 makes cells longer
    along that axis. warp displaces the lookup by fbm (px) for irregular (rubble) edges."""
    rng = np.random.default_rng(seed)
    if jitter_grid:
        k = int(round(np.sqrt(n)))
        gx, gy = np.meshgrid(np.arange(k), np.arange(k))
        pts = (np.stack([gx.ravel(), gy.ravel()], 1) + 0.15 + rng.random((k * k, 2)) * 0.7) * (S / k)
    else:
        pts = rng.random((n, 2)) * S
    sx, sy = stretch
    box = np.array([S / sx, S / sy])
    tree = cKDTree(pts / np.array([sx, sy]), boxsize=box)
    xx, yy = grid()
    if warp > 0:
        xx = xx + fbm(warp_seed, 2.2, 2, 40) * warp
        yy = yy + fbm(warp_seed + 1, 2.2, 2, 40) * warp
    q = np.stack([(np.mod(xx, S) / sx).ravel(), (np.mod(yy, S) / sy).ravel()], 1)
    q = np.mod(q, box - 1e-6)
    d, i = tree.query(q, k=2)
    edge = (d[:, 1] - d[:, 0]) * min(sx, sy)
    return edge.reshape(S, S), i[:, 0].reshape(S, S), d[:, 0].reshape(S, S)


def hash01(ids, seed):
    """Deterministic per-id random in [0,1) (splitmix64)."""
    with np.errstate(over="ignore"):
        x = np.asarray(ids).astype(np.uint64) + np.uint64(seed + 1) * np.uint64(0x9E3779B97F4A7C15)
        x ^= x >> np.uint64(30); x *= np.uint64(0xBF58476D1CE4E5B9)
        x ^= x >> np.uint64(27); x *= np.uint64(0x94D049BB133111EB)
        x ^= x >> np.uint64(31)
    return (x >> np.uint64(11)).astype(np.float64) / float(2 ** 53)


def normal_from_height(h, tile_m, strength=1.0):
    """h in metres -> GL tangent normal (RG) with +y = image up."""
    px = tile_m / S
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) / (2 * px)
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) / (2 * px)
    nx = -dx * strength
    ny = dy * strength
    nz = np.ones_like(h)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    return nx / l, ny / l


def cavity(h, tile_m, radius_m=0.03, k=18.0):
    """Ambient occlusion from height: how far a pixel sits below its blurred surroundings."""
    r = max(1.0, radius_m / tile_m * S)
    c = blur(h, r) - h
    return np.clip(1.0 - np.maximum(c, 0) * k / max(radius_m, 1e-3) * 0.05, 0.35, 1.0)


def lines_mask(seed, count, length_px, width=1.0, wander=0.35, branch=0.0):
    """Random-walk cracks, wrapped. Returns 0..1 mask."""
    rng = np.random.default_rng(seed)
    m = np.zeros((S, S))
    for _ in range(count):
        x, y = rng.random() * S, rng.random() * S
        a = rng.random() * np.pi * 2
        L = int(length_px * (0.5 + rng.random()))
        for _s in range(L):
            a += rng.normal() * wander
            x = (x + np.cos(a)) % S
            y = (y + np.sin(a)) % S
            m[int(y), int(x)] = 1.0
            if branch > 0 and rng.random() < branch / L:
                pass
    if width > 1.0:
        m = ndimage.grey_dilation(m, size=(int(width), int(width)), mode="wrap")
    return np.clip(blur(m, 0.6) * 2.5, 0, 1)


def mix(a, b, t):
    t = t[..., None] if np.ndim(t) == 2 and np.ndim(a) == 3 else t
    return a * (1 - t) + b * t


def rgb(c):
    return np.array(c, dtype=np.float64)


def fill(c):
    return np.ones((S, S, 3)) * rgb(c)


def srgb_speckle(alb, seed, amt):
    return alb * (1.0 + amt * fbm(seed, 0.5, 64)[..., None])


# ---------------------------------------------------------------- materials
# each returns dict(alb=HxWx3, mask=HxW, h=HxW metres, rough=HxW, ao=HxW or None, ns=normal strength)

def mat_plaster():
    """Lime plaster: an even, faintly trowelled surface with soft stains and hairline cracks.
    (Worn bases and exposed stone are the shader's job, so nothing repeats every tile.)"""
    t = TILE["plaster"]
    und = fbm(11, 2.6, 1, 40)
    grain = fbm(12, 0.8, 80)
    h = und * 0.0008 + grain * 0.00012 + blur(fbm(13, 1.6, 20, 200), 1.0) * 0.00012
    streak = n01(fbm(13, 2.0, 1, 200, aniso=(1.0, 0.08)))
    blot = n01(fbm(14, 2.6, 1, 20))
    alb = fill((0.89, 0.875, 0.845))
    alb *= (1.0 + 0.018 * fbm(15, 2.0, 2, 60))[..., None]
    alb *= (1.0 + 0.012 * fbm(16, 0.6, 60, 300))[..., None]
    alb *= (1.0 - 0.045 * np.clip((streak - 0.6) * 3, 0, 1))[..., None]
    alb = mix(alb, alb * rgb((0.95, 0.93, 0.9)), np.clip((blot - 0.65) * 3, 0, 1) * 0.6)
    cr = lines_mask(17, 6, 220, 1.0, 0.45)
    h -= cr * 0.0006
    alb *= (1.0 - 0.1 * cr)[..., None]
    rough = 0.9 + 0.03 * fbm(21, 1.0, 20)
    return dict(alb=alb, mask=np.ones((S, S)), h=h, rough=rough, ao=cavity(h, t, 0.02), ns=1.0)


def mat_whitewash():
    t = TILE["whitewash"]
    edge, cid, _ = cells(31, 70, stretch=(1.4, 1.0), warp=10, warp_seed=32)
    stones = blur(np.clip(edge / 70.0, 0, 1), 5.0)      # the stones under many coats of lime, rounded off
    h = stones * 0.006 + hash01(cid, 3) * 0.0015
    strokes = fbm(33, 2.2, 4, 200, aniso=(0.15, 1.0))
    h += strokes * 0.0005 + fbm(34, 1.0, 60) * 0.00015
    h = blur(h, 2.0)
    alb = fill((0.95, 0.945, 0.93))
    alb = mix(alb, rgb((0.88, 0.89, 0.9)), np.clip(1 - stones, 0, 1) * 0.3)
    alb *= (1.0 + 0.015 * fbm(35, 1.5, 3, 200))[..., None]
    dirt = np.clip((n01(fbm(36, 2.8, 1, 30)) - 0.65) * 3, 0, 1)
    alb = mix(alb, alb * rgb((0.93, 0.92, 0.89)), dirt * 0.5)
    rough = 0.93 - 0.02 * stones
    return dict(alb=alb, mask=np.ones((S, S)), h=h, rough=rough, ao=cavity(h, t, 0.05, 10), ns=0.8)


def mat_rubble(seed=41):
    t = TILE["rubble"]
    # two scales of stone: big blocks, with small pinning stones filling the joints between them
    edge, cid, d1 = cells(seed, 120, stretch=(1.5, 1.0), warp=9, warp_seed=seed + 1, jitter_grid=True)
    edge2, cid2, _ = cells(seed + 20, 900, stretch=(1.3, 1.0), warp=3, warp_seed=seed + 21)
    mortar_w = 3.0 + 1.5 * n01(fbm(seed + 2, 1.5, 4, 60))
    big = np.clip((edge - mortar_w) / 2.5, 0, 1)
    small = np.clip((edge2 - 2.5) / 2.0, 0, 1) * (1 - big) * (edge < mortar_w + 1.5) * (fbm(seed + 22, 1.0, 20, 200) > 1.2)
    stone = np.maximum(big, small)
    bulge = np.clip((edge - mortar_w) / 30.0, 0, 1) ** 0.6
    r = hash01(cid, seed); r2 = hash01(cid, seed + 5)
    rs = hash01(cid2, seed + 7)
    rr = np.where(big > 0.5, r, rs)
    h = big * bulge * (0.012 + 0.012 * r) + small * 0.005 + fbm(seed + 3, 2.2, 6, 120) * 0.0015
    h = h * stone + (-0.01 + fbm(seed + 4, 1.0, 40) * 0.0015) * (1 - stone)
    base = 0.5 + 0.17 * rr
    col = np.stack([base, base * 0.99, base * 0.965], -1)
    warm = (hash01(cid, seed + 9) > 0.7).astype(float)
    dark = (r2 < 0.07).astype(float)
    col = mix(col, col * rgb((1.08, 0.99, 0.88)), warm * 0.6)
    col = mix(col, col * 0.8, dark)
    # within-stone mottling (low frequency) and a faint granite grain
    col *= (1.0 + 0.10 * fbm(seed + 6, 2.2, 8, 120))[..., None]
    col *= (1.0 + 0.035 * np.clip(fbm(seed + 8, 0.3, 150), -2.5, 2.5))[..., None]
    lich = np.clip((n01(fbm(seed + 10, 2.2, 3, 80)) - 0.68) * 5, 0, 1) * (r2 > 0.35)
    col = mix(col, rgb((0.64, 0.63, 0.5)), lich * 0.4)
    mort = fill((0.56, 0.54, 0.5)) * (1.0 + 0.08 * fbm(seed + 11, 1.0, 30))[..., None]
    alb = mix(mort, col, stone)
    ao = cavity(h, t, 0.06, 26)
    alb *= (0.72 + 0.28 * ao)[..., None]
    mask = 0.3 + 0.35 * stone
    rough = 0.8 * stone + 0.95 * (1 - stone)
    return dict(alb=alb, mask=mask, h=h, rough=rough, ao=ao, ns=1.0)

def courses(n_rows, lengths, seed, stagger=True):
    """Running-bond blocks: returns (row, block id, x within block px, y within row px, block w px, row h px)."""
    rng = np.random.default_rng(seed)
    xx, yy = grid()
    rh = S / n_rows
    row = np.floor(yy / rh).astype(int) % n_rows
    yin = yy - row * rh
    bid = np.zeros((S, S), dtype=np.int64)
    xin = np.zeros((S, S))
    bw = np.zeros((S, S))
    for rrow in range(n_rows):
        # widths summing to S
        ws = []
        acc = 0.0
        while acc < S:
            w = lengths[0] + rng.random() * (lengths[1] - lengths[0]) if isinstance(lengths, tuple) else lengths
            ws.append(w); acc += w
        ws = np.array(ws) * (S / acc)
        edges = np.concatenate([[0], np.cumsum(ws)])
        off = (rng.random() * S) if stagger == "random" else ((ws[0] * 0.5) if (stagger and rrow % 2) else 0.0)
        sel = row == rrow
        x = np.mod(xx[sel] - off, S)
        k = np.searchsorted(edges, x, side="right") - 1
        k = np.clip(k, 0, len(ws) - 1)
        xin[sel] = x - edges[k]
        bw[sel] = ws[k]
        bid[sel] = rrow * 1000 + k
    return row, bid, xin, yin, bw, rh


def mat_ashlar():
    t = TILE["ashlar"]
    row, bid, xin, yin, bw, rh = courses(8, (190.0, 400.0), 51, stagger="random")
    j = 2.2
    dx = np.minimum(xin, bw - xin); dy = np.minimum(yin, rh - yin)
    de = np.minimum(dx, dy)
    face = np.clip((de - j) / 5.0, 0, 1)
    r = hash01(bid, 52)
    chisel = fbm(53, 1.0, 60, 400, aniso=(1.0, 0.35))
    h = face * (0.006 + 0.004 * r) + chisel * 0.0006 * face + fbm(54, 2.0, 2, 60) * 0.0015
    h -= (1 - face) * 0.003
    alb = fill((0.80, 0.775, 0.72))
    alb *= (0.92 + 0.14 * r)[..., None]
    alb *= (1.0 + 0.04 * fbm(55, 1.2, 10, 300))[..., None]
    alb = mix(alb, alb * rgb((0.86, 0.84, 0.8)), np.clip((n01(fbm(56, 2.5, 1, 40)) - 0.6) * 2.5, 0, 1))
    joint = 1 - face
    alb = mix(alb, rgb((0.74, 0.72, 0.68)), joint * 0.7)
    mask = 0.55 + 0.45 * face
    rough = 0.8 + 0.08 * joint + 0.03 * chisel
    return dict(alb=alb, mask=mask, h=h, rough=rough, ao=cavity(h, t, 0.03), ns=1.0)


def mat_brick_base(seed=61, tile_m=None):
    t = tile_m or TILE["brick"]
    rows = int(round(t / 0.075))
    per = t / 0.257
    row, bid, xin, yin, bw, rh = courses(rows, S / per, seed, stagger=True)
    j = 0.011 / t * S * 0.5
    ex = fbm(seed + 1, 1.5, 20, 200) * 0.9
    dx = np.minimum(xin, bw - xin) + ex; dy = np.minimum(yin, rh - yin) + ex * 0.6
    face = np.clip((np.minimum(dx, dy) - j) / 1.2, 0, 1)
    r = hash01(bid, seed + 2); r2 = hash01(bid, seed + 3)
    reds = np.stack([0.55 + 0.12 * r, 0.26 + 0.1 * r, 0.17 + 0.05 * r], -1)
    dark = (r2 < 0.12)[..., None]
    reds = np.where(dark, reds * rgb((0.62, 0.58, 0.6)), reds)
    yel = (r2 > 0.94)[..., None]
    reds = np.where(yel, rgb((0.72, 0.52, 0.34)) * (0.9 + 0.2 * r[..., None]), reds)
    reds *= (1.0 + 0.08 * fbm(seed + 4, 0.8, 40))[..., None]
    mort = fill((0.72, 0.69, 0.62)) * (1 + 0.05 * fbm(seed + 5, 1.0, 50))[..., None]
    alb = mix(mort, reds, face)
    h = face * (0.006 + 0.002 * r) + fbm(seed + 6, 1.0, 60) * 0.0006 - (1 - face) * 0.004
    return dict(alb=alb, face=face, h=h)


def mat_brick():
    t = TILE["brick"]
    b = mat_brick_base()
    face = b["face"]
    eff = np.clip((n01(fbm(62, 2.4, 1, 30)) - 0.72) * 3, 0, 1)       # efflorescence
    alb = mix(b["alb"], rgb((0.8, 0.78, 0.72)), eff * 0.35)
    mask = 0.25 + 0.55 * face
    rough = 0.82 + 0.1 * (1 - face)
    return dict(alb=alb, mask=mask, h=b["h"], rough=rough, ao=cavity(b["h"], t, 0.01), ns=1.0)


def mat_adobe():
    """Earth render: soft lumps, faint rain rivulets, a few straw flecks."""
    t = TILE["adobe"]
    lumps = fbm(71, 2.6, 1, 40)
    riv = fbm(72, 2.0, 3, 200, aniso=(1.0, 0.1))
    h = lumps * 0.003 + riv * 0.0004 + fbm(73, 0.9, 60) * 0.00015
    h = blur(h, 1.0)
    alb = fill((0.80, 0.72, 0.60))
    alb *= (1.0 + 0.03 * fbm(74, 1.8, 2, 120))[..., None]
    alb = mix(alb, alb * rgb((0.93, 0.9, 0.86)), np.clip(n01(riv) - 0.6, 0, 1) * 0.8)
    rng = np.random.default_rng(75)
    fl = np.zeros((S, S))
    for _ in range(700):
        x, y = rng.random() * S, rng.random() * S
        a = rng.random() * np.pi
        for s_ in range(int(5 + rng.random() * 8)):
            fl[int(y + np.sin(a) * s_) % S, int(x + np.cos(a) * s_) % S] = 1
    fl = blur(fl, 0.6)
    alb = mix(alb, rgb((0.85, 0.75, 0.5)), np.clip(fl, 0, 1) * 0.3)
    rough = 0.95 + 0.02 * fbm(77, 1, 20)
    return dict(alb=alb, mask=np.ones((S, S)), h=h, rough=rough, ao=cavity(h, t, 0.03), ns=0.8)


def mat_azulejo():
    t = TILE["azulejo"]
    n = 8
    tp = S / n
    xx, yy = grid()
    tx = np.floor(xx / tp).astype(int); ty = np.floor(yy / tp).astype(int)
    tid = (ty % n) * n + (tx % n)
    # hand-painted wobble
    wx = xx + fbm(81, 2.0, 8, 200) * 1.3; wy = yy + fbm(82, 2.0, 8, 200) * 1.3
    u = (np.mod(wx, tp) / tp) * 2 - 1; v = (np.mod(wy, tp) / tp) * 2 - 1
    # corner quarter-circles -> circles across four tiles
    rc = np.sqrt((1 - np.abs(u)) ** 2 + (1 - np.abs(v)) ** 2)
    ring = np.clip(1 - np.abs(rc - 0.62) / 0.11, 0, 1)
    corner = np.clip((0.34 - rc) / 0.05, 0, 1) * (1 - np.clip((0.16 - rc) / 0.04, 0, 1) * 0.9)
    # central quatrefoil
    th = np.arctan2(v, u); r = np.sqrt(u * u + v * v)
    petal = 0.44 * (0.5 + 0.5 * np.abs(np.cos(2 * th)))
    flower = np.clip((petal - r) / 0.04, 0, 1)
    hole = np.clip((0.1 - r) / 0.03, 0, 1)
    dots = np.clip((0.07 - np.sqrt((np.abs(u) - 0.55) ** 2 + v ** 2)) / 0.03, 0, 1) + np.clip((0.07 - np.sqrt(u ** 2 + (np.abs(v) - 0.55) ** 2)) / 0.03, 0, 1)
    diag = np.clip(1 - np.abs(np.abs(u) - np.abs(v)) / 0.05, 0, 1) * ((r > 0.42) & (rc > 0.72))
    pat = np.clip(ring + corner + flower * (1 - hole * 0.85) + dots + diag * 0.8, 0, 1)
    pat *= 0.8 + 0.2 * n01(fbm(83, 1.5, 20, 300))          # uneven cobalt
    pat = blur(pat, 0.7)
    gx = np.minimum(np.mod(xx, tp), tp - np.mod(xx, tp)); gy = np.minimum(np.mod(yy, tp), tp - np.mod(yy, tp))
    grout = np.clip(1.6 - np.minimum(gx, gy), 0, 1)
    rt = hash01(tid, 84); rt2 = hash01(tid, 85)
    chip = ((rt2 < 0.035) & (np.sqrt(u * u + v * v) < 0.5 + 0.4 * rt)).astype(float)
    chip = blur(chip, 1.0)
    glaze = fill((0.93, 0.92, 0.87)) * (0.97 + 0.05 * rt)[..., None]
    craze_e, _, _ = cells(86, 900)
    craze = np.clip(1 - craze_e / 1.2, 0, 1) * 0.25
    glaze *= (1 - 0.1 * craze)[..., None]
    alb = mix(glaze, rgb((0.95, 0.95, 0.95)), pat)
    alb = mix(alb, rgb((0.55, 0.54, 0.5)), grout)
    alb = mix(alb, rgb((0.7, 0.68, 0.63)), chip)
    mask = pat * (1 - grout) * (1 - chip)
    h = (1 - grout) * 0.003 + (u * (rt - 0.5) + v * (rt2 - 0.5)) * 0.0008 - chip * 0.002
    h += (1 - (u * u + v * v) * 0.5) * 0.0005
    rough = 0.1 + 0.08 * craze + 0.8 * grout + 0.7 * chip + 0.04 * n01(fbm(87, 1.5, 10))
    return dict(alb=alb, mask=mask, h=h, rough=np.clip(rough, 0.05, 1), ao=cavity(h, t, 0.006), ns=0.8)


def mat_roof_tile():
    t = TILE["roof_tile"]
    cols = 9; rows = 5
    xx, yy = grid()
    cw = S / cols; rh = S / rows
    c = np.floor(xx / cw).astype(int) % cols
    x = np.mod(xx, cw) / cw                 # 0..1 across a column; the channel is centred, caps sit on x = 0/1
    xc = np.minimum(x, 1 - x)
    capw = 0.27
    iscap_geom = xc < capw
    # caps and channels are staggered by half a row; each tile's lower edge is a little irregular
    ystag = np.where(iscap_geom, yy + rh * 0.5, yy)
    colid = np.where(iscap_geom, np.floor((xx + cw * 0.5) / cw).astype(int) % cols + 50, c)
    rid0 = np.floor(ystag / rh).astype(int) % rows
    jit = (hash01(rid0 * 131 + colid, 91) - 0.5) * 0.10 * rh + blur(fbm(97, 2.0, 4, 40), 2.0) * 1.2
    yr = np.mod(ystag + jit, rh) / rh       # 0 top .. 1 lower edge
    tid = (np.floor((ystag + jit) / rh).astype(int) % rows) * 131 + colid
    channel = 0.004 + 0.016 * (1 - np.cos(np.clip((xc - capw * 0.4) / (0.5 - capw * 0.4), 0, 1) * np.pi)) * 0.5 * 0 + 0.018 * (xc / 0.5)
    cap = np.where(iscap_geom, 0.03 + 0.05 * np.sqrt(np.clip(1 - (xc / capw) ** 2, 0, 1)), -1)
    iscap = (cap > channel).astype(float)
    prof = np.maximum(cap, channel)
    ramp = 0.03 * yr ** 1.3
    h = prof + ramp + fbm(92, 1.2, 30, 300) * 0.0008
    rr = hash01(tid, 93); rr2 = hash01(tid, 94)
    base = np.stack([0.72 + 0.10 * rr, 0.38 + 0.10 * rr, 0.23 + 0.05 * rr], -1)
    base = np.where((rr2 < 0.18)[..., None], base * rgb((0.78, 0.7, 0.68)), base)
    base = np.where((rr2 > 0.9)[..., None], base * 0.4 + rgb((0.8, 0.6, 0.47)) * 0.6, base)
    base *= (1 + 0.07 * fbm(95, 1.4, 10, 200))[..., None]
    lich = np.clip((n01(fbm(96, 2.0, 4, 200)) - 0.64) * 4, 0, 1) * iscap
    base = mix(base, rgb((0.68, 0.66, 0.52)), lich * 0.55)
    # baked shading: cap crowns catch light, channels and the underside of each overlap are dark
    crown = np.where(iscap > 0, np.sqrt(np.clip(1 - (xc / capw) ** 2, 0, 1)), 0)
    shade = 0.72 + 0.28 * crown + 0.1 * iscap
    under = np.clip(1 - yr / 0.10, 0, 1)
    shade *= 1 - 0.55 * under
    side = np.where(iscap > 0, 0, np.clip(1 - (xc - capw) / 0.08, 0, 1))
    shade *= 1 - 0.45 * side
    alb = base * shade[..., None]
    ao = np.clip(cavity(h, t, 0.05, 30) * (1 - 0.4 * under) * (1 - 0.3 * side), 0.2, 1)
    mask = np.clip(0.75 - lich * 0.5, 0, 1)
    rough = 0.76 + 0.1 * (1 - iscap) + 0.06 * lich
    return dict(alb=alb, mask=mask, h=h, rough=rough, ao=ao, ns=1.0)

def mat_slate():
    t = TILE["slate"]
    rows = 8
    row, bid, xin, yin, bw, rh = courses(rows, (150.0, 330.0), 101, stagger="random")
    r = hash01(bid, 102); r2 = hash01(bid, 103)
    # rounded, slightly irregular lower edges; slabs thicken toward the bottom (heavy gneiss plates)
    wob = fbm(104, 2.4, 3, 60) * 4 + (r - 0.5) * 8
    ybot = rh - 3 + wob
    dxe = np.minimum(xin, bw - xin)
    corner = np.clip(1 - dxe / 30, 0, 1) ** 2 * 16
    inside = np.clip((ybot - corner - yin) / 1.5, 0, 1)
    t_in = yin / rh
    h = 0.016 * t_in + 0.006 * r + fbm(105, 1.8, 10, 300) * 0.0018
    gap = np.clip(1 - dxe / 1.8, 0, 1)
    h = h * inside + (1 - inside) * 0.0 - gap * 0.004
    base = 0.38 + 0.08 * r
    col = np.stack([base * 1.0, base * 1.0, base * 1.02], -1)
    col = np.where((r2 > 0.78)[..., None], col * rgb((1.12, 1.03, 0.92)), col)
    col *= (1 + 0.10 * fbm(106, 2.0, 6, 120))[..., None]
    col *= (1 + 0.04 * np.clip(fbm(109, 0.4, 120), -2, 2))[..., None]
    lich_o = np.clip((n01(fbm(107, 2.4, 3, 90)) - 0.8) * 6, 0, 1)
    lich_g = np.clip((n01(fbm(108, 2.2, 3, 120)) - 0.6) * 4, 0, 1)
    col = mix(col, rgb((0.68, 0.52, 0.28)), lich_o * 0.6)
    col = mix(col, rgb((0.62, 0.64, 0.55)), lich_g * 0.5)
    below = np.clip(1 - (yin - (ybot - corner)) / 14.0, 0, 1) * (1 - inside)
    shadow = (1 - inside) * 0.35 + below * 0.35 + gap * 0.3
    alb = col * (1 - shadow)[..., None]
    ao = np.clip(cavity(h, t, 0.04, 20) * (1 - 0.35 * (1 - inside)), 0.2, 1)
    mask = 0.35 * inside
    rough = 0.82 + 0.08 * lich_g
    return dict(alb=alb, mask=mask, h=h, rough=rough, ao=ao, ns=1.0)

def mat_timber(seed=111, weather=0.5):
    t = TILE["timber"]
    rng = np.random.default_rng(seed)
    ws = []
    acc = 0
    while acc < S:
        w = 70 + rng.random() * 80
        ws.append(w); acc += w
    ws = np.array(ws) * S / acc
    edges = np.concatenate([[0], np.cumsum(ws)])
    xx, yy = grid()
    k = np.clip(np.searchsorted(edges, xx, side="right") - 1, 0, len(ws) - 1)
    xin = xx - edges[k]; bw = ws[k]
    r = hash01(k, seed + 1); r2 = hash01(k, seed + 2)
    grain = fbm(seed + 3, 1.6, 4, 400, aniso=(1.0, 0.04)) + 0.4 * fbm(seed + 4, 1.2, 30, 400, aniso=(1.0, 0.1))
    # knots
    kn = np.zeros((S, S))
    for _ in range(18):
        cx, cy = rng.random() * S, rng.random() * S
        d = np.sqrt(((xx - cx + S / 2) % S - S / 2) ** 2 + (((yy - cy + S / 2) % S - S / 2) * 0.45) ** 2)
        kn += np.clip(1 - d / (4 + rng.random() * 5), 0, 1)
    gapd = np.minimum(xin, bw - xin)
    gap = np.clip(1 - (gapd - 1.5) / 1.5, 0, 1)
    cup = 1 - ((xin / bw) * 2 - 1) ** 2
    h = cup * 0.002 + grain * 0.0007 - gap * 0.008 - kn * 0.0008
    brown = rgb((0.46, 0.33, 0.22)); grey = rgb((0.56, 0.53, 0.49))
    col = mix(np.ones((S, S, 3)) * brown, np.ones((S, S, 3)) * grey, np.clip(weather + (r - 0.5) * 0.6 + 0.1 * fbm(seed + 5, 2, 2, 50), 0, 1))
    col *= (0.86 + 0.24 * r2)[..., None]
    col *= (1 + 0.1 * np.clip(grain, -2, 2))[..., None]
    col = mix(col, col * 0.55, np.clip(kn, 0, 1))
    alb = mix(col, rgb((0.08, 0.07, 0.06)), gap)
    mask = 1 - gap
    rough = 0.82 + 0.1 * gap + 0.03 * grain
    return dict(alb=alb, mask=mask, h=h, rough=rough, ao=cavity(h, t, 0.01), ns=1.0)


def mat_shutter():
    t = TILE["shutter"]
    xx, yy = grid()
    n = 20
    ph = S / n
    s = np.mod(yy, ph) / ph
    prof = 0.004 * (1 - s)                 # each slat slopes down-and-out
    shade = np.clip((s - 0.82) / 0.18, 0, 1)
    h = prof + fbm(121, 1.0, 40) * 0.0002
    chips = np.clip((fbm(122, 1.4, 8, 200) - 1.7) * 3, 0, 1)
    wood = mat_timber(123, 0.6)["alb"]
    paint = fill((0.93, 0.93, 0.91)) * (1 + 0.03 * fbm(124, 1, 20))[..., None]
    alb = mix(paint, wood, chips)
    alb *= (1 - 0.6 * shade)[..., None]
    ao = 1 - 0.5 * shade
    mask = 1 - chips
    rough = 0.5 + 0.35 * chips
    return dict(alb=alb, mask=mask, h=h, rough=rough, ao=ao, ns=1.4)


def mat_glass():
    t = TILE["glass"]
    wav = fbm(131, 2.6, 1, 20)
    h = wav * 0.0006
    alb = fill((0.03, 0.04, 0.05)) * (1 + 0.1 * fbm(132, 2.2, 1, 40))[..., None]
    smudge = np.clip((n01(fbm(133, 2.4, 2, 60)) - 0.55) * 2.5, 0, 1)
    alb = mix(alb, rgb((0.16, 0.16, 0.15)), smudge * 0.3)
    rough = 0.05 + 0.08 * smudge
    return dict(alb=alb, mask=np.zeros((S, S)), h=h, rough=rough, ao=np.ones((S, S)), ns=0.25)


def mat_iron():
    t = TILE["iron"]
    ham = fbm(141, 2.0, 20, 200)
    h = ham * 0.0004
    rust = np.clip((n01(fbm(142, 2.2, 3, 150)) - 0.6) * 3.5, 0, 1)
    alb = mix(fill((0.11, 0.11, 0.115)), fill((0.32, 0.17, 0.09)), rust * 0.8)
    alb *= (1 + 0.1 * fbm(143, 0.5, 60))[..., None]
    rough = 0.5 + 0.35 * rust
    return dict(alb=alb, mask=0.45 * (1 - rust), h=h, rough=rough, ao=np.ones((S, S)), ns=1.0)


def mat_stone():
    t = TILE["stone"]
    tool = fbm(151, 1.2, 60, 400, aniso=(0.25, 1.0))
    h = fbm(152, 2.2, 2, 80) * 0.0015 + tool * 0.00035
    alb = fill((0.83, 0.81, 0.76))
    alb *= (1 + 0.04 * fbm(153, 1.6, 3, 300))[..., None]
    alb *= (1 + 0.05 * np.clip(fbm(154, 0.1, 150), -2, 2))[..., None]
    alb = mix(alb, alb * rgb((0.88, 0.86, 0.82)), np.clip((n01(fbm(155, 2.5, 1, 30)) - 0.62) * 3, 0, 1))
    rough = 0.74 + 0.04 * tool
    return dict(alb=alb, mask=np.ones((S, S)), h=h, rough=rough, ao=cavity(h, t, 0.02), ns=1.0)


def mat_door():
    t = TILE["door"]
    xx, yy = grid()
    m = S / t                                   # px per metre
    X = xx / m; Y = (S - yy) / m                # metres, Y up from the bottom
    h = np.zeros((S, S))
    # left half: two-leaf panelled door (each leaf 0.6 wide)
    left = X < 1.2
    lx = np.mod(X, 0.6)
    panel = np.zeros((S, S))
    for (y0, y1) in [(0.22, 1.12), (1.27, 2.02), (2.12, 2.3)]:
        inx = (lx > 0.11) & (lx < 0.49); iny = (Y > y0) & (Y < y1)
        dd = np.minimum(np.minimum(lx - 0.11, 0.49 - lx), np.minimum(Y - y0, y1 - Y))
        p = np.clip(dd / 0.035, 0, 1) * (inx & iny)
        panel = np.maximum(panel, p)
    frame_edge = (np.minimum(lx, 0.6 - lx) < 0.008)
    h_l = 0.008 - (1 - panel) * 0.0 + panel * 0.004 - ((panel > 0) & (panel < 1)) * 0.002
    h_l = np.where(frame_edge, -0.004, h_l)
    # right half: planks with two battens, studs and strap hinges
    rx = X - 1.2
    pw = 0.15
    pk = np.mod(rx, pw)
    gap = (np.minimum(pk, pw - pk) < 0.006)
    batten = ((Y > 0.4) & (Y < 0.55)) | ((Y > 1.85) & (Y < 2.0))
    stud = ((np.abs(np.mod(rx, pw) - pw / 2) < 0.012) & (batten) & (np.abs(np.mod(Y, 0.075) - 0.037) < 0.012))
    strap = ((np.abs(Y - 0.475) < 0.03) | (np.abs(Y - 1.925) < 0.03)) & (rx < 0.8)
    grain = fbm(161, 1.6, 4, 400, aniso=(1.0, 0.05))
    h_r = 0.004 + grain * 0.0006 - gap * 0.006 + batten * 0.0 + stud * 0.004 + strap * 0.002
    h = np.where(left, h_l, h_r) + fbm(162, 1.0, 40) * 0.0002
    wood = mat_timber(163, 0.3)["alb"]
    chips = np.clip((fbm(164, 1.4, 6, 200) - 1.5) * 3 + np.clip(0.35 - Y, 0, 1) * 4 * (n01(fbm(165, 1, 30)) > 0.4), 0, 1)
    paint = fill((0.92, 0.92, 0.9))
    alb = mix(paint, wood, chips)
    ironm = (stud | strap) & ~left
    alb = np.where(ironm[..., None], rgb((0.12, 0.11, 0.1)), alb)
    alb = np.where((gap & ~left)[..., None], alb * 0.35, alb)
    mask = (1 - chips) * (~ironm)
    rough = np.where(ironm, 0.55, 0.55 + 0.3 * chips)
    return dict(alb=alb, mask=mask.astype(float), h=h, rough=rough, ao=cavity(h, t, 0.01), ns=1.0)


def mat_canvas():
    t = TILE["canvas"]
    xx, yy = grid()
    sw = S / 10
    stripe = (np.floor(xx / sw).astype(int) % 2 == 0).astype(float)
    stripe = blur(stripe, 0.8)
    weave = np.sin(xx * np.pi * 0.9) * np.sin(yy * np.pi * 0.9)
    h = weave * 0.00015 + fbm(171, 2.4, 1, 10, aniso=(1, 0.2)) * 0.002
    alb = fill((0.93, 0.92, 0.88)) * (1 + 0.04 * fbm(172, 2, 2, 60))[..., None]
    dirt = np.clip((n01(fbm(173, 2.4, 1, 30)) - 0.6) * 2, 0, 1)
    alb = mix(alb, alb * rgb((0.85, 0.83, 0.78)), dirt * 0.5)
    return dict(alb=alb, mask=stripe, h=h, rough=np.full((S, S), 0.92), ao=np.ones((S, S)), ns=1.0)


def mat_terrace():
    t = TILE["terrace"]
    ce, cid, _ = cells(181, 40, warp=12, warp_seed=182)
    crack = np.clip(1 - ce / 1.5, 0, 1) * (hash01(cid, 183) > 0.35)
    h = fbm(184, 2.4, 1, 60) * 0.002 + fbm(185, 0.8, 80) * 0.0003 - crack * 0.002
    alb = fill((0.85, 0.83, 0.79)) * (1 + 0.04 * fbm(186, 1.8, 2, 100))[..., None]
    stain = np.clip((n01(fbm(187, 2.8, 1, 20)) - 0.55) * 2.5, 0, 1)
    alb = mix(alb, alb * rgb((0.78, 0.77, 0.74)), stain * 0.6)
    alb *= (1 - 0.35 * crack)[..., None]
    rough = 0.9 - 0.05 * stain
    return dict(alb=alb, mask=np.ones((S, S)), h=h, rough=rough, ao=cavity(h, t, 0.02), ns=1.0)


MATS = {
    "plaster": mat_plaster, "whitewash": mat_whitewash, "rubble": mat_rubble, "ashlar": mat_ashlar,
    "brick": mat_brick, "adobe": mat_adobe, "azulejo": mat_azulejo, "roof_tile": mat_roof_tile,
    "slate": mat_slate, "timber": mat_timber, "shutter": mat_shutter, "glass": mat_glass,
    "iron": mat_iron, "stone": mat_stone, "door": mat_door, "canvas": mat_canvas, "terrace": mat_terrace,
}


def save(name, m, out_size):
    t = TILE[name]
    nx, ny = normal_from_height(m["h"], t, m.get("ns", 1.0))
    ao = m["ao"] if m.get("ao") is not None else np.ones((S, S))
    alb = np.clip(m["alb"], 0, 1)
    a = np.concatenate([alb, np.clip(m["mask"], 0, 1)[..., None]], -1)
    n = np.stack([nx * 0.5 + 0.5, ny * 0.5 + 0.5, np.clip(ao, 0, 1), np.clip(m["rough"], 0.03, 1)], -1)
    ia = Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGBA")
    inn = Image.fromarray((n * 255 + 0.5).astype(np.uint8), "RGBA")
    if out_size != S:
        ia = ia.resize((out_size, out_size), Image.LANCZOS)
        inn = inn.resize((out_size, out_size), Image.LANCZOS)
    ia.save(os.path.join(OUT, name + "_alb.png"), optimize=True)
    inn.save(os.path.join(OUT, name + "_nrm.png"), optimize=True)
    print("baked", name)


def bake_noise():
    """noise.png: 512 px macro variation for the shader (R blotches, G streaks, B mid, A fine)."""
    global S
    keep = S
    S = 512
    r = n01(fbm(901, 2.6, 1, 40)); g = n01(fbm(902, 2.0, 1, 200, aniso=(1.0, 0.08)))
    b = n01(fbm(903, 2.0, 3, 80)); a = n01(fbm(904, 1.0, 20))
    img = np.stack([r, g, b, a], -1)
    Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "noise.png"))
    S = keep
    print("baked noise")


def main():
    global S
    os.makedirs(OUT, exist_ok=True)
    out_size = 1024
    only = None
    args = sys.argv[1:]
    if "--size" in args: out_size = int(args[args.index("--size") + 1])
    if "--only" in args: only = args[args.index("--only") + 1].split(",")
    for name, _t in LAYERS:
        if only and name not in only: continue
        save(name, MATS[name](), out_size)
    if not only: bake_noise()


if __name__ == "__main__":
    main()
