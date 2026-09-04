"""Bakes the foliage card textures in assets/foliage (RGBA, alpha-cut):
grass_card (blade tufts for the Terrain3D instancer), flower cards, and leaf clumps for the
crossed-card tree canopies (pine needles, olive leaves, cypress scales, scrub, heather).
Run from the project root:  python3 world/mapgen/foliage.py
"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np, os, math

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "foliage")
os.makedirs(OUT, exist_ok=True)
S = 256
rng = np.random.default_rng(5)


def save(name, img):
    # premultiplied-looking edges: bleed colour into transparent pixels so mipmaps don't darken
    a = np.asarray(img)[..., 3:4].astype(np.float32) / 255.0
    rgb = np.asarray(img)[..., :3].astype(np.float32)
    blurred = np.asarray(img.filter(ImageFilter.GaussianBlur(3)))[..., :3].astype(np.float32)
    rgb = np.where(a > 0.05, rgb, blurred)
    out = np.concatenate([rgb, np.asarray(img)[..., 3:4]], -1).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(os.path.join(OUT, name + ".png"))
    print("baked", name)


def blade(draw, x0, y0, x1, y1, w, c0, c1, steps=18):
    """A tapered, slightly curved grass blade from (x0,y0) up to (x1,y1)."""
    cx = (x0 + x1) / 2 + rng.uniform(-12, 12)
    for i in range(steps):
        t0 = i / steps; t1 = (i + 1) / steps
        def p(t):
            return ((1 - t) ** 2 * x0 + 2 * (1 - t) * t * cx + t * t * x1, (1 - t) * y0 + t * y1)
        a = p(t0); b = p(t1)
        ww = w * (1 - t0) + 0.6
        col = tuple(int(c0[k] * (1 - t0) + c1[k] * t0) for k in range(3)) + (255,)
        draw.line([a, b], fill=col, width=int(max(ww, 1)))


def grass_card(name, base, tip, blades, spread=1.0):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(blades):
        x = rng.uniform(40, S - 40)
        h = rng.uniform(0.45, 1.0) * (S - 20)
        lean = rng.uniform(-70, 70) * spread
        c0 = tuple(int(v * rng.uniform(0.8, 1.0)) for v in base)
        c1 = tuple(int(v * rng.uniform(0.85, 1.1)) for v in tip)
        blade(d, x, S - 4, x + lean, S - 4 - h, rng.uniform(5, 9), c0, c1)
    save(name, img)


def clump(name, colours, n, size, shape="ellipse", jitter=0.5, spike=False):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = S / 2, S / 2
    for i in range(n):
        # denser towards the middle so the card edge breaks up
        r = S * 0.46 * math.sqrt(rng.uniform(0, 1)) * (1.0 + jitter * rng.uniform(-0.3, 0.3))
        a = rng.uniform(0, 2 * math.pi)
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r * 0.9
        col = colours[rng.integers(0, len(colours))]
        col = tuple(int(v * rng.uniform(0.75, 1.15)) for v in col) + (255,)
        if spike:
            L = rng.uniform(size * 0.8, size * 1.6); ang = a + rng.uniform(-0.6, 0.6)
            d.line([(x, y), (x + math.cos(ang) * L, y + math.sin(ang) * L)], fill=col, width=int(rng.uniform(2, 4)))
        else:
            w = rng.uniform(size * 0.6, size * 1.2); h = w * rng.uniform(0.5, 1.0)
            ang = rng.uniform(0, math.pi)
            leaf = Image.new("RGBA", (int(w * 2) + 2, int(w * 2) + 2), (0, 0, 0, 0))
            ImageDraw.Draw(leaf).ellipse((w * 0.5, w - h * 0.5, w * 1.5, w + h * 0.5), fill=col)
            leaf = leaf.rotate(math.degrees(ang), resample=Image.BILINEAR)
            img.alpha_composite(leaf, (int(x - w), int(y - w)))
    save(name, img)


grass_card("grass_card", (70, 92, 30), (150, 165, 70), 26)
grass_card("dry_grass_card", (120, 105, 50), (190, 175, 100), 24, 1.2)
grass_card("dune_grass_card", (140, 130, 70), (205, 195, 130), 14, 1.4)
# flowers: grass with blossoms on top
for name, col in [("flower_card_pink", (215, 110, 170)), ("flower_card_yellow", (240, 200, 70)), ("flower_card_white", (245, 245, 235))]:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(10):
        x = rng.uniform(50, S - 50); h = rng.uniform(0.5, 0.9) * (S - 30)
        blade(d, x, S - 4, x + rng.uniform(-30, 30), S - 4 - h, 5, (60, 85, 30), (110, 140, 50))
    for i in range(7):
        x = rng.uniform(40, S - 40); y = rng.uniform(30, 120); r = rng.uniform(9, 15)
        for k in range(6):
            a = k * math.pi / 3
            d.ellipse((x + math.cos(a) * r * 0.8 - r * 0.55, y + math.sin(a) * r * 0.8 - r * 0.55, x + math.cos(a) * r * 0.8 + r * 0.55, y + math.sin(a) * r * 0.8 + r * 0.55), fill=col + (255,))
        d.ellipse((x - r * 0.4, y - r * 0.4, x + r * 0.4, y + r * 0.4), fill=(250, 210, 90, 255))
    save(name, img)
clump("pine_clump", [(28, 62, 34), (40, 80, 42), (22, 50, 28), (52, 92, 48)], 3200, 16, spike=True)
clump("olive_clump", [(118, 132, 92), (96, 112, 76), (140, 150, 108), (84, 100, 66)], 1100, 15)
clump("cypress_clump", [(26, 52, 28), (36, 66, 34), (20, 42, 22)], 1800, 11)
clump("scrub_clump", [(88, 106, 50), (110, 124, 60), (70, 90, 42), (130, 128, 70)], 950, 14)
clump("heather_clump", [(120, 82, 120), (96, 70, 96), (140, 100, 130), (90, 96, 70)], 1400, 10)
clump("broadleaf_clump", [(60, 110, 44), (84, 132, 56), (46, 92, 38), (110, 150, 70)], 1000, 17)
