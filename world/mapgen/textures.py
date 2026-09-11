"""Bakes the ground textures Terrain3D uses (all 512 px, seamless):
  *_alb_ht.png  (RGB albedo, A height)     *_nrm_rgh.png (RGB normal, A roughness)

Two kinds:
 - packed ambientCG photo sets (CC0, /root/assets_pool/ambientcg, 1K JPG variants): Color x AO^0.6
   goes to albedo (a little cavity darkening baked in, GL Compat has no SSAO), Displacement to the
   height alpha, NormalGL + Roughness to the second image. Some are desaturated / retinted here so
   the in-engine `albedo_color` only has to nudge them.
 - procedural ones for the surfaces we have no photo for: sand (beaches, dunes, seabed), clay
   (badlands), soil (ploughed strips), salt (salinas).
Run from the project root:  python3 world/mapgen/textures.py
"""
from PIL import Image
import numpy as np, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "terrain")
POOL = "/root/assets_pool/ambientcg"
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


def load_map(set_id, kind, mode):
    p = os.path.join(POOL, set_id, f"{set_id}_1K-JPG_{kind}.jpg")
    return np.asarray(Image.open(p).convert(mode).resize((S, S), Image.LANCZOS)).astype(np.float32) / 255.0


def pack(name, set_id, sat=1.0, tint=(1.0, 1.0, 1.0), ao_pow=0.6, contrast=1.0, rough_mul=1.0, gamma=1.0):
    """Pack an ambientCG set. `sat` scales chroma, `tint` multiplies, `contrast` stretches value
    around the mean (< 1 flattens the photo so it reads painterly, not busy)."""
    col = load_map(set_id, "Color", "RGB")
    ao = load_map(set_id, "AmbientOcclusion", "L")
    ht = load_map(set_id, "Displacement", "L")
    nrm = load_map(set_id, "NormalGL", "RGB")
    rgh = load_map(set_id, "Roughness", "L")
    lum = col @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    col = lum[..., None] + (col - lum[..., None]) * sat
    mean = col.mean(axis=(0, 1), keepdims=True)
    col = mean + (col - mean) * contrast
    col = np.clip(col, 0, 1) ** (1.0 / gamma)   # > 1 lifts the mid-tones without clipping (the photos are shot in flat light)
    col = col * (ao[..., None] ** ao_pow) * np.array(tint, dtype=np.float32)[None, None]
    col = np.clip(col, 0, 1)
    alb = np.concatenate([col, ht[..., None]], -1)
    Image.fromarray((alb * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, f"{name}_alb_ht.png"))
    nr = np.concatenate([nrm, np.clip(rgh * rough_mul, 0, 1)[..., None]], -1)
    Image.fromarray((nr * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, f"{name}_nrm_rgh.png"))
    print("packed", name, "<-", set_id, "mean rgb", (col.mean(axis=(0, 1)) * 255).astype(int))


# photo sets (see assets/CREDITS.md)
pack("rock019", "Rock019", sat=0.75, tint=(1.0, 0.97, 0.90), contrast=0.85)     # pale bedded limestone: cliff faces
pack("rock021", "Rock021", sat=0.55, tint=(0.98, 0.95, 0.88), contrast=0.85)     # streaked slabs: variation on the steepest faces
pack("ground004", "Ground004", sat=0.7, tint=(1.02, 0.97, 0.88), contrast=0.8, gamma=1.35)   # dry trodden earth: the road
pack("ground015", "Ground015", sat=0.6, tint=(1.05, 1.0, 0.86), contrast=0.75, gamma=1.7)   # dry straw grass: meadows
pack("ground024", "Ground024", sat=0.6, tint=(1.0, 0.98, 0.88), contrast=0.8, gamma=1.6)    # stony scrub ground: karst, town
pack("rocks002", "Rocks002", sat=0.7, tint=(1.0, 0.96, 0.88), contrast=0.9, gamma=1.3)      # rubble: talus at cliff feet
pack("gravel009", "Gravel009", sat=0.8, tint=(1.04, 0.98, 0.88), contrast=0.9)   # fine gravel: road shoulders

# procedural (retinted toward the reference: sand #c3a682, clay unchanged, soil, salt)
bake("sand", (0.86, 0.76, 0.58), (0.68, 0.58, 0.42), 12, 0.03, 0.85, speck=0.45)
bake("clay", (0.78, 0.50, 0.32), (0.48, 0.28, 0.17), 13, 0.08, 0.95, cell=True, speck=0.2)
bake("soil", (0.72, 0.64, 0.50), (0.46, 0.39, 0.29), 14, 0.06, 0.95, speck=0.4)   # pale dry vineyard earth
bake("salt", (0.98, 0.98, 0.95), (0.80, 0.81, 0.78), 15, 0.04, 0.55, cell=True, speck=0.15)
