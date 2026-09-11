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


def save(name, img, base_light=0.62):
    """Bakes a top-light gradient (top 1.0 -> base `base_light`) into the card, then bleeds colour
    into the transparent pixels so mipmaps don't darken the edges. The gradient stands in for the
    canopy shading the reference has (lit crown, dark underside) without lighting the cards."""
    a = np.asarray(img)[..., 3:4].astype(np.float32) / 255.0
    rgb = np.asarray(img)[..., :3].astype(np.float32)
    ramp = np.linspace(1.0, base_light, S, dtype=np.float32)[:, None, None]
    rgb = np.clip(rgb * ramp, 0, 255)
    img = Image.fromarray(np.concatenate([rgb, np.asarray(img)[..., 3:4]], -1).astype(np.uint8), "RGBA")
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


def clump(name, colours, n, size, shape="ellipse", jitter=0.5, spike=False, interior=1.0, base_light=0.62, gap=0.0):
    """`interior` < 1 bakes a dark heart: leaves are multiplied by interior..1.0 from the centre
    to the rim, so a bush reads as a lit shell round a shadowed inside (critique r2 item 12:
    "a baked dark interior, not a dark whole"). `gap` > 0: every second leaf first clears a rim
    of `gap` px round itself, so the lobes are separated by 1-2 px gaps and the card's mip chain
    thins out toward the silhouette (r4 item 5: the canopies had become smooth opaque blobs)."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = S / 2, S / 2
    for i in range(n):
        # denser towards the middle so the card edge breaks up
        u = rng.uniform(0, 1)
        r = S * 0.46 * math.sqrt(u) * (1.0 + jitter * rng.uniform(-0.3, 0.3))
        a = rng.uniform(0, 2 * math.pi)
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r * 0.9
        col = colours[rng.integers(0, len(colours))]
        heart = interior + (1.0 - interior) * math.sqrt(u)
        col = tuple(int(v * rng.uniform(0.75, 1.15) * heart) for v in col) + (255,)
        if spike:
            L = rng.uniform(size * 0.8, size * 1.6); ang = a + rng.uniform(-0.6, 0.6)
            d.line([(x, y), (x + math.cos(ang) * L, y + math.sin(ang) * L)], fill=col, width=int(rng.uniform(2, 4)))
        else:
            w = rng.uniform(size * 0.6, size * 1.2); h = w * rng.uniform(0.5, 1.0)
            ang = rng.uniform(0, math.pi)
            leaf = Image.new("RGBA", (int(w * 2) + 2, int(w * 2) + 2), (0, 0, 0, 0))
            ImageDraw.Draw(leaf).ellipse((w * 0.5, w - h * 0.5, w * 1.5, w + h * 0.5), fill=col)
            leaf = leaf.rotate(math.degrees(ang), resample=Image.BILINEAR)
            if gap > 0.0 and i % 2 == 1:
                cut = Image.new("L", leaf.size, 0)
                ImageDraw.Draw(cut).ellipse((w * 0.5 - gap, w - h * 0.5 - gap, w * 1.5 + gap, w + h * 0.5 + gap), fill=255)
                cut = cut.rotate(math.degrees(ang), resample=Image.BILINEAR)
                img.paste((0, 0, 0, 0), (int(x - w), int(y - w)), mask=cut)
            img.alpha_composite(leaf, (int(x - w), int(y - w)))
    save(name, img, base_light)


# grass: dry olive (#9a9a5a base -> #b8a860 tips), never the neon lime of the first pass
grass_card("grass_card", (118, 118, 72), (184, 168, 96), 26)
grass_card("dry_grass_card", (132, 118, 66), (196, 178, 112), 24, 1.2)
grass_card("dune_grass_card", (146, 136, 84), (206, 196, 138), 14, 1.4)
# flowers: grass with blossoms on top
for name, col in [("flower_card_pink", (215, 110, 170)), ("flower_card_yellow", (240, 200, 70)), ("flower_card_white", (245, 245, 235))]:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(10):
        x = rng.uniform(50, S - 50); h = rng.uniform(0.5, 0.9) * (S - 30)
        blade(d, x, S - 4, x + rng.uniform(-30, 30), S - 4 - h, 5, (88, 96, 52), (140, 138, 78))
    for i in range(7):
        x = rng.uniform(40, S - 40); y = rng.uniform(30, 120); r = rng.uniform(9, 15)
        for k in range(6):
            a = k * math.pi / 3
            d.ellipse((x + math.cos(a) * r * 0.8 - r * 0.55, y + math.sin(a) * r * 0.8 - r * 0.55, x + math.cos(a) * r * 0.8 + r * 0.55, y + math.sin(a) * r * 0.8 + r * 0.55), fill=col + (255,))
        d.ellipse((x - r * 0.4, y - r * 0.4, x + r * 0.4, y + r * 0.4), fill=(250, 210, 90, 255))
    save(name, img)
# canopies: real greens, baked yellow-olive (H 65-80, R >= 1.5 B): the blue fog and the grade's
# blue black-lift pull every rendered canopy ~30 deg toward cyan, so a true-green card (H95,
# round 3 first try) rendered teal H170 while these land on the reference's #5f8a3e / #2f4a2c.
# Round 3 (critique item 6): saturation up, value down from round 2's lime, and the baked
# interior is 0.30-0.45 of the rim (ref bush core #31341a): a bush is a lit shell round a really
# dark inside.
clump("pine_clump", [(84, 104, 50), (100, 124, 58), (66, 84, 42), (120, 146, 74)], 3200, 16, spike=True, interior=0.4)
clump("olive_clump", [(128, 138, 90), (110, 120, 76), (146, 154, 106), (96, 106, 66)], 1100, 15, interior=0.45, gap=1.0)
# cypress (r4 item 7): near black-olive, H 55-90 - the reference's sentinels are #2a2a0f, ours rendered #344537 teal-green
clump("cypress_clump", [(66, 74, 32), (80, 90, 38), (52, 60, 26)], 2160, 11, interior=0.45, base_light=0.62)
# (r4 item 7: x0.8 - the cliff-top scrub rendered lime on the arch crown, the reference's is #6a5743-class)
clump("scrub_clump", [(80, 96, 46), (94, 114, 52), (64, 78, 38), (108, 124, 62)], 950, 14, jitter=0.9, interior=0.35, gap=1.0)
clump("heather_clump", [(118, 92, 108), (98, 80, 90), (132, 106, 118), (104, 112, 70)], 1400, 10, interior=0.5)
# vines: a uniform mid-green (H 70-90, S ~0.45: lit #6d7a36 / shade #3f4420 in the critique) on
# the dark soil strips - r2's yellow-olive H50 card under a warm tint read as orange rows
# (r4 item 8: the H78 card still rendered H120-170 through the fog and grade - yellow-olive H60
# on the card lands on the reference's H70-90 rows)
# and brighter (interior 0.6): at 250 m a V0.3 row takes half its colour from the blue fog and
# goes teal whatever its hue; the reference's rows are #707f37 V0.5
clump("broadleaf_clump", [(150, 150, 60), (166, 164, 70), (128, 126, 52), (180, 178, 82)], 1000, 17, interior=0.7, gap=1.0)
