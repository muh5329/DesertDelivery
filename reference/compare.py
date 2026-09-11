"""Rough render-vs-reference comparison: python3 reference/compare.py render.png reference.png [out_dir]
Prints a 0..1 similarity (colour histogram + edge/texture energy + luminance layout) and writes a
side-by-side image next to the render. Use the side-by-side with your eyes; the score only tracks trends."""
import sys, os
import numpy as np
from PIL import Image, ImageFilter

def load(p, size=(512, 288)):
    im = Image.open(p).convert("RGB")
    im = im.crop((0, 0, im.width, int(im.height * 0.96)))   # drop player-bar overlays in refs
    return im.resize(size, Image.LANCZOS)

def hist(im):
    a = np.asarray(im.convert("HSV")).reshape(-1, 3)
    h, _ = np.histogramdd(a, bins=(12, 6, 6), range=((0, 256),) * 3)
    h = h / h.sum(); return h

def texture(im):
    g = np.asarray(im.convert("L").filter(ImageFilter.FIND_EDGES)).astype(np.float32) / 255
    # per-region edge energy on a 8x5 grid
    H, W = g.shape; cells = []
    for j in range(5):
        for i in range(8):
            cells.append(g[j*H//5:(j+1)*H//5, i*W//8:(i+1)*W//8].mean())
    return np.array(cells)

def layout(im):
    g = np.asarray(im.convert("L").resize((16, 9), Image.BOX)).astype(np.float32) / 255
    return g.flatten()

r = load(sys.argv[1]); ref = load(sys.argv[2])
out_dir = sys.argv[3] if len(sys.argv) > 3 else os.path.dirname(sys.argv[1])
hs = 1 - 0.5 * np.abs(hist(r) - hist(ref)).sum()
tr, tf = texture(r), texture(ref)
ts = 1 - np.clip(np.abs(tr - tf).mean() / (tf.mean() + 1e-6), 0, 1)
ls = 1 - np.abs(layout(r) - layout(ref)).mean()
score = 0.45 * hs + 0.35 * ts + 0.20 * ls
print("similarity %.3f  (colour %.3f, texture-energy %.3f, luminance-layout %.3f; render edge energy %.3f vs ref %.3f)" % (score, hs, ts, ls, tr.mean(), tf.mean()))
side = Image.new("RGB", (1024, 288)); side.paste(r, (0, 0)); side.paste(ref, (512, 0))
name = "compare_" + os.path.splitext(os.path.basename(sys.argv[1]))[0] + ".png"
side.save(os.path.join(out_dir, name)); print("side-by-side:", os.path.join(out_dir, name))
