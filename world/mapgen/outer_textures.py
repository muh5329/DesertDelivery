"""Bakes the extra ground textures the outer-world terrain and roads use (512 px, seamless,
Terrain3D packing: *_alb_ht.png = RGB albedo + A height, *_nrm_rgh.png = RGB normal (GL) + A roughness).

  meadow     green grass from the ground015 photo's structure, recoloured
  alpine     short alpine turf with stones (ground024 structure, cooler green)
  snow       wind-packed snow with sastrugi ripples
  asphalt    fine-aggregate asphalt (roads, highways)
  cobble     worn stone setts (town streets and plazas)

Run from the project root:  python3 world/mapgen/outer_textures.py
"""
import os
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "terrain")
S = 512


def tile_noise(seed, base, octaves=5, gain=0.55):
    r = np.random.default_rng(seed)
    acc = np.zeros((S, S)); amp = 1.0; tot = 0.0
    for o in range(octaves):
        n = int(base * 2 ** o)
        g = r.random((n, n))
        big = np.tile(g, (3, 3))
        im = Image.fromarray((big * 255).astype(np.uint8)).resize((S * 3, S * 3), Image.BICUBIC)
        layer = np.asarray(im)[S:2 * S, S:2 * S] / 255.0
        acc += layer * amp; tot += amp; amp *= gain
    acc /= tot
    return (acc - acc.min()) / (acc.max() - acc.min() + 1e-6)


def normal_from_height(h, strength):
    dx = np.roll(h, -1, 1) - np.roll(h, 1, 1)
    dy = np.roll(h, -1, 0) - np.roll(h, 1, 0)
    nx = -dx * strength; ny = dy * strength; nz = np.ones_like(h)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / l * 0.5 + 0.5, ny / l * 0.5 + 0.5, nz / l * 0.5 + 0.5], -1)


def save(name, alb, ht, nrm, rough):
    a = np.concatenate([np.clip(alb, 0, 1), np.clip(ht, 0, 1)[..., None]], -1)
    Image.fromarray((a * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + "_alb_ht.png"))
    n = np.concatenate([nrm, np.clip(rough, 0, 1)[..., None] if np.ndim(rough) == 2 else np.full((S, S, 1), rough)], -1)
    Image.fromarray((n * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + "_nrm_rgh.png"))
    print("baked", name)


def load(name):
    a = np.asarray(Image.open(os.path.join(OUT, name + "_alb_ht.png")).convert("RGBA")).astype(float) / 255
    n = np.asarray(Image.open(os.path.join(OUT, name + "_nrm_rgh.png")).convert("RGBA")).astype(float) / 255
    return a, n


def recolour(src, lo, hi, var_seed, var_amt=0.12):
    lum = src[..., :3] @ np.array([0.3, 0.55, 0.15])
    lum = (lum - lum.mean()) / (lum.std() + 1e-6)
    t = np.clip(0.5 + lum * 0.22, 0, 1)[..., None]
    col = np.array(lo)[None, None] * (1 - t) + np.array(hi)[None, None] * t
    v = tile_noise(var_seed, 2, 3)[..., None]
    col = col * (1 - var_amt + 2 * var_amt * v)
    return col


def main():
    g15, n15 = load("ground015")
    g24, n24 = load("ground024")
    # meadow: the straw photo's blades, green; a little dry straw showing through in patches
    col = recolour(g15, (0.16, 0.25, 0.08), (0.46, 0.58, 0.24), 11)
    dry = tile_noise(12, 3, 3)[..., None]
    col = col * (1 - 0.25 * dry) + g15[..., :3] * 0.25 * dry
    save("meadow", col, g15[..., 3], n15[..., :3], n15[..., 3] * 0.2 + 0.78)
    # alpine turf: short cool grass with the scrub photo's stones kept grey
    col = recolour(g24, (0.17, 0.23, 0.12), (0.44, 0.50, 0.32), 13)
    stones = np.clip((g24[..., :3].mean(-1) - 0.55) * 4, 0, 1)[..., None]
    col = col * (1 - stones) + g24[..., :3] * stones
    save("alpine", col, g24[..., 3], n24[..., :3], 0.85)
    # snow: sastrugi ripples, soft blue in the troughs
    rip = tile_noise(21, 4, 4)
    y, x = np.mgrid[0:S, 0:S] / S
    ripple = 0.5 + 0.5 * np.sin((x * 3 + y * 7 + rip * 0.8) * 2 * np.pi * 3)
    h = np.clip(rip * 0.6 + ripple * 0.25 + tile_noise(22, 32, 2) * 0.15, 0, 1)
    col = np.array([0.80, 0.85, 0.93])[None, None] * (1 - h[..., None]) + np.array([0.97, 0.98, 1.0])[None, None] * h[..., None]
    save("snow", col, h, normal_from_height(h * 255, 0.012), 0.55 + 0.2 * (1 - h))
    # asphalt: dark fine aggregate with lighter stones and a little tar sheen variation
    base = tile_noise(31, 64, 2, 0.6)
    grit = (np.random.default_rng(32).random((S, S)) > 0.965) * 0.5 + (np.random.default_rng(33).random((S, S)) > 0.9) * 0.2
    grit = ndimage.gaussian_filter(grit, 0.6)
    patch = tile_noise(34, 3, 3)
    v = 0.20 + 0.06 * base + 0.25 * grit + 0.05 * patch
    col = np.stack([v * 1.02, v * 1.0, v * 0.97], -1)
    h = np.clip(base * 0.5 + grit, 0, 1)
    save("asphalt", col, h, normal_from_height(h * 255, 0.02), 0.72 - 0.15 * patch)
    # cobble: worn setts in running bond, grout darker
    yy, xx = np.mgrid[0:S, 0:S].astype(float)
    rows = 16; cols = 12
    ry = yy / S * rows
    row = np.floor(ry)
    shift = (row % 2) * 0.5
    cx = xx / S * cols + shift
    fx = cx - np.floor(cx); fy = ry - row
    jit = tile_noise(41, 16, 2)
    edge = np.minimum(np.minimum(fx, 1 - fx) * 1.3, np.minimum(fy, 1 - fy))
    stone = np.clip(edge * 9 - 0.3 + jit * 0.3, 0, 1)
    dome = np.sqrt(np.clip(stone, 0, 1))
    hue = tile_noise(42, 12, 1)
    tone = 0.45 + 0.18 * hue + 0.08 * tile_noise(43, 64, 2)
    col = np.stack([tone * 1.05, tone * 0.98, tone * 0.88], -1) * (0.35 + 0.65 * stone[..., None])
    save("cobble", col, dome, normal_from_height(dome * 255, 0.03), 0.8 - 0.2 * stone)


if __name__ == "__main__":
    main()
