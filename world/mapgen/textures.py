"""Bakes the procedural ground textures Terrain3D uses next to the two ambientCG photo sets:
dirt (roads), sand (beaches, dunes, seabed), clay (badlands), soil (ploughed strips), salt (salinas).
Each is a 512 px seamless pair: *_alb_ht.png (RGB albedo, A height) and *_nrm_rgh.png (RGB normal, A roughness).
Run from the project root:  python3 world/mapgen/textures.py
"""
from PIL import Image
import numpy as np, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "terrain")
S = 512
rng = np.random.default_rng(3)


def fbm(seed, octaves=5, base=4.0, gain=0.55, cell=False):
    """Seamless fractal noise in [0,1] via tiled random grids upsampled with bicubic interpolation."""
    r = np.random.default_rng(seed)
    acc = np.zeros((S, S)); amp = 1.0; tot = 0.0
    for o in range(octaves):
        n = int(base * 2 ** o)
        g = r.random((n, n))
        if cell:
            # cellular-ish: distance to random points on the tile -> cracked polygons
            pts = r.random((n * n // 2, 2)) * S
            yy, xx = np.mgrid[0:S, 0:S]
            d = np.full((S, S), 1e9)
            for px, py in pts:
                for ox in (-S, 0, S):
                    for oy in (-S, 0, S):
                        d = np.minimum(d, (xx - px - ox) ** 2 + (yy - py - oy) ** 2)
            layer = np.sqrt(d); layer /= layer.max()
        else:
            big = np.tile(g, (3, 3))
            im = Image.fromarray((big * 255).astype(np.uint8)).resize((S * 3, S * 3), Image.BICUBIC)
            layer = np.asarray(im)[S:2 * S, S:2 * S] / 255.0
        acc += layer * amp; tot += amp; amp *= gain
    acc /= tot
    acc = (acc - acc.min()) / (acc.max() - acc.min() + 1e-6)
    return acc


def normal_from_height(h, strength):
    dx = np.roll(h, -1, 1) - np.roll(h, 1, 1)
    dy = np.roll(h, -1, 0) - np.roll(h, 1, 0)
    nx = -dx * strength; ny = -dy * strength; nz = np.ones_like(h)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / l * 0.5 + 0.5, ny / l * 0.5 + 0.5, nz / l * 0.5 + 0.5], -1)


def bake(name, light, dark, seed, strength, rough, cell=False, speck=0.25, warp=0.0):
    h = fbm(seed, cell=cell)
    if cell:
        h = 1.0 - h                       # ridges become cracks
        h = np.clip(h * 1.4 - 0.2, 0, 1)
    fine = fbm(seed + 1, octaves=3, base=48.0, gain=0.5)
    v = np.clip(h * (1.0 - speck) + fine * speck, 0, 1)
    col = np.array(dark)[None, None] * (1 - v[..., None]) + np.array(light)[None, None] * v[..., None]
    tone = 0.85 + 0.3 * fbm(seed + 2, octaves=2, base=2.0)
    col = np.clip(col * tone[..., None], 0, 1)
    alb = np.concatenate([col, v[..., None]], -1)
    Image.fromarray((alb * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, f"{name}_alb_ht.png"))
    nrm = normal_from_height(v * 255.0, strength)
    nr = np.concatenate([nrm, np.full((S, S, 1), rough)], -1)
    Image.fromarray((nr * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, f"{name}_nrm_rgh.png"))
    print("baked", name)


bake("dirt", (0.66, 0.52, 0.36), (0.38, 0.28, 0.18), 11, 0.05, 0.92, speck=0.35)
bake("sand", (0.90, 0.84, 0.66), (0.70, 0.62, 0.44), 12, 0.03, 0.85, speck=0.45)
bake("clay", (0.80, 0.48, 0.30), (0.46, 0.25, 0.15), 13, 0.08, 0.95, cell=True, speck=0.2)
bake("soil", (0.50, 0.38, 0.26), (0.26, 0.19, 0.12), 14, 0.06, 0.95, speck=0.4)
bake("salt", (1.0, 1.0, 0.98), (0.80, 0.82, 0.80), 15, 0.04, 0.55, cell=True, speck=0.15)
