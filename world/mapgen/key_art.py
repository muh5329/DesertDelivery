"""The loading screen's key art: a beauty shot of the world graded into the storybook look.

    xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --audio-driver Dummy --rendering-driver vulkan \\
        -- --facet --test=uiux_shots --views=keyart --out=/tmp/keyart --size=1600x900
    python3 world/mapgen/key_art.py /tmp/keyart/keyart_1600x900.png

Grades the render (golden split-toning, a little more colour and contrast), paints it (a Kuwahara
filter: flat brush-like patches with crisp edges), lays paper grain and a vignette over it, and
writes assets/ui/loading_key_art.jpg (1600 x 900). The title is not baked: the loading screen sets it.
"""
import os, sys
import numpy as np
from scipy import ndimage
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "assets", "ui", "loading_key_art.jpg")


def kuwahara(img, r):
    """Per channel means of the four (r+1)^2 quadrants round each pixel; keep the calmest one."""
    lum = img @ np.array([0.3, 0.59, 0.11], np.float32)
    k = r + 1
    mean = ndimage.uniform_filter(img, size=(k, k, 1), mode="reflect")
    lm = ndimage.uniform_filter(lum, size=k, mode="reflect")
    lv = ndimage.uniform_filter(lum * lum, size=k, mode="reflect") - lm * lm
    best = None; best_v = None
    h = r // 2 + 1
    for dy in (-h, h):
        for dx in (-h, h):
            m = np.roll(mean, (dy, dx), axis=(0, 1)); v = np.roll(lv, (dy, dx), axis=(0, 1))
            if best is None:
                best, best_v = m.copy(), v.copy()
            else:
                sel = v < best_v
                best[sel] = m[sel]; best_v[sel] = v[sel]
    return best


def main(src):
    img = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255.0
    H, W, _ = img.shape
    # paint: a small Kuwahara, then a touch of the original's edges back
    pad = 8
    big = np.pad(img, ((pad, pad), (pad, pad), (0, 0)), mode="reflect")
    p = kuwahara(big, 3)[pad:-pad, pad:-pad]
    edges = img - ndimage.gaussian_filter(img, (1.2, 1.2, 0))
    img = np.clip(p + edges * 0.5, 0, 1)
    # grade: contrast, saturation, golden highlights, violet-brown shadows
    lum = (img @ np.array([0.3, 0.59, 0.11], np.float32))[..., None]
    img = lum + (img - lum) * 1.35
    img = np.clip((img - 0.5) * 1.12 + 0.5, 0, 1)
    lum = (img @ np.array([0.3, 0.59, 0.11], np.float32))[..., None]
    warm = np.array([1.10, 0.98, 0.78], np.float32)
    cool = np.array([0.86, 0.80, 0.92], np.float32)
    t = np.clip((lum - 0.25) / 0.6, 0, 1)
    img = img * (cool * (1 - t) + warm * t)
    # a low sun from the left: warm light washing across the top
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    glow = np.exp(-(((xx - W * 0.22) / (W * 0.55)) ** 2 + ((yy - H * 0.30) / (H * 0.45)) ** 2))
    img = img + glow[..., None] * np.array([0.16, 0.10, 0.02], np.float32)
    # paper grain and fibres
    rng = np.random.default_rng(7)
    grain = ndimage.gaussian_filter(rng.random((H, W)).astype(np.float32), 0.7)
    fib = ndimage.gaussian_filter(rng.random((H // 4, W // 4)).astype(np.float32), (0.6, 3.0))
    fib = np.asarray(Image.fromarray((fib * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)).astype(np.float32) / 255.0
    img = img * (0.93 + 0.08 * grain[..., None] + 0.04 * (fib[..., None] - 0.5))
    # vignette
    d = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2)
    img = img * (1.0 - 0.28 * np.clip(d - 0.55, 0, 1)[..., None] ** 1.3)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)).save(OUT, quality=90, optimize=True)
    print("key art ->", OUT, os.path.getsize(OUT), "bytes")


if __name__ == "__main__":
    main(sys.argv[1])
