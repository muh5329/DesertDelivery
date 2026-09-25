"""Bakes the far-tree impostors of the imported Quaternius trees (assets/trees/impostors/).

Beyond the real models' range the wilderness drew hand-made card trees: a round clump texture
stretched over tall crossed cards, lit from the card normal - from the air and across a valley
the forests read as rows of dark rounded slabs. An impostor here is the real model seen
orthographically from three sides - along Z, along X and from above - rasterised with the leaf
atlas' alpha test (tree_raster.py, 4x4 supersampled), so its silhouette is the tree's own. A
texel does not store a colour but what the leaf shader needs to colour it like the near tree:

  R  the height in the model's bounds (the leaf shader's top-lit gradient; the kind's palette and
     `y_bottom` fraction apply at run time, so one bake serves every species look)
  G  bark (1) or leaves (0)
  B  crown occlusion: how far behind the crown's front the visible leaf lies (holes darker)
  A  coverage

impostors.json keeps, per model, the atlas cells' rectangles in model space (WorldKit builds the
three cards from them: two crossed vertical cards through the trunk and a flat one in the crown)
and the bounds the gradient uses.

    python3 world/mapgen/tree_impostors.py          # after tree_bark.py
"""
import json, os, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tree_bark as tb
import tree_raster as tr

OUT = os.path.join(tb.TREES, "impostors")
CELL = 256            # texels per atlas cell
SS = 4                # supersampling
LEAF_CUT = 0.38       # the leaf shader's alpha_cut
LEAF_TEX = {"TwistedTree": "Leaves_TwistedTree_C.png", "Pine": "Leaf_Pine_C.png"}


def dilate(rgb, cov, steps=12):
    """Push covered colours into the empty texels (the mips average them in)."""
    rgb = rgb.copy(); have = cov > 0
    for _ in range(steps):
        acc = np.zeros_like(rgb); n = np.zeros(cov.shape)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0: continue
                sh = np.roll(np.roll(have, dy, 0), dx, 1)
                acc += np.roll(np.roll(rgb, dy, 0), dx, 1) * sh[..., None]; n += sh
        grow = (~have) & (n > 0)
        rgb[grow] = acc[grow] / n[grow][:, None]
        have = have | grow
    return rgb


def bake(name):
    g, prims = tb.read_gltf(name)
    fam = tb.family(name)
    atlas_alpha = np.asarray(Image.open(os.path.join(tb.TREES, LEAF_TEX[fam])).convert("RGBA"), np.float32)[..., 3] / 255.0
    V, UV, T, TAG = [], [], [], []
    base = 0
    for p in prims:
        leaf = not p["name"].startswith("Bark")
        V.append(p["pos"]); UV.append(p["uv"])
        tri = p["idx"].reshape(-1, 3).astype(np.int64) + base
        T.append(tri); TAG.append(np.full(len(tri), 1 if leaf else 0))
        base += len(p["pos"])
    V = np.concatenate(V).astype(np.float64); UV = np.concatenate(UV); T = np.concatenate(T); TAG = np.concatenate(TAG)
    lo, hi = V.min(0), V.max(0)
    leaf_v = np.concatenate([p["pos"] for p in prims if not p["name"].startswith("Bark")])
    # views: (screen u axis, screen v axis (up), depth axis toward the viewer)
    views = {"z": (0, 1, 2), "x": (2, 1, 0), "y": (0, 2, 1)}
    res = CELL * SS
    cells = []
    atlas = np.zeros((CELL, CELL * 3, 4), np.float32)
    meta = {"bounds": [lo.tolist(), hi.tolist()], "cells": {}}
    for ci, (vname, (ua, va, da)) in enumerate(views.items()):
        u0, u1 = lo[ua], hi[ua]
        v0, v1 = lo[va], hi[va]
        if vname == "y":
            # the top card: the crown only (the trunk under it is not seen from above)
            v0, v1 = lo[va], hi[va]
        pad_u = (u1 - u0) * 0.02; pad_v = (v1 - v0) * 0.02
        u0 -= pad_u; u1 += pad_u; v0 -= pad_v; v1 += pad_v
        # pixel coords: u right, v down (the top of the tree at row 0; the top card: -Z at row 0)
        px = (V[:, ua] - u0) / (u1 - u0) * res
        py = (v1 - V[:, va]) / (v1 - v0) * res if vname != "y" else (V[:, va] - v0) / (v1 - v0) * res
        depth = -V[:, da]
        z, tid, bary = tr.raster(np.stack([px, py], 1), depth, T, (res, res), UV, atlas_alpha, LEAF_CUT, TAG)
        cov = (tid >= 0).astype(np.float32)
        y = tr.interp(V[:, 1:2].astype(np.float32), T, tid, bary)[..., 0]
        h01 = np.clip((y - lo[1]) / max(hi[1] - lo[1], 1e-6), 0, 1)
        bark = np.zeros_like(cov); bark[tid >= 0] = (TAG[tid[tid >= 0]] == 0)
        # crown occlusion: depth behind the nearest leaf within ~1/16 of the cell
        zz = np.where(tid >= 0, z, np.inf)
        k = res // 16
        front = zz.copy()
        for s in (1, 2, 4, 8):
            if s > k: break
            for ax in (0, 1):
                front = np.minimum(front, np.minimum(np.roll(front, s, ax), np.roll(front, -s, ax)))
        extent = hi[da] - lo[da]
        with np.errstate(invalid="ignore"):
            behind = np.where(tid >= 0, zz - np.where(np.isfinite(front), front, zz), 0.0)
        occ = 1.0 - 0.6 * np.clip(behind / max(extent * 0.35, 1e-3), 0, 1)
        # downsample SSxSS
        def down(a):
            return a.reshape(CELL, SS, CELL, SS).mean((1, 3))
        c = down(cov)
        w = np.maximum(c, 1e-6)
        rgb = np.stack([down(h01 * cov) / w, down(bark * cov) / w, down(occ * cov) / w], -1)
        rgb = dilate(rgb, c)
        # coverage -> alpha: a texel half covered is a leaf edge (the shader cuts at ~0.38)
        a = np.clip(c * 1.25, 0, 1)
        atlas[:, ci * CELL:(ci + 1) * CELL, :3] = rgb
        atlas[:, ci * CELL:(ci + 1) * CELL, 3] = a
        rect = [float(u0), float(v0), float(u1), float(v1)]
        cell = {"axis": vname, "rect": rect, "uv": [ci / 3.0, 0.0, (ci + 1) / 3.0, 1.0]}
        if vname == "y":
            # the flat card sits at the crown's upper third
            cell["height"] = float(np.percentile(leaf_v[:, 1], 70))
        meta["cells"][vname] = cell
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray((np.clip(atlas, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + ".png"), optimize=True)
    print("%-14s impostor %s  bounds %s..%s" % (name, atlas.shape[1::-1], np.round(lo, 1), np.round(hi, 1)))
    return meta


def main():
    names = sys.argv[1:] or tb.MODELS
    path = os.path.join(OUT, "impostors.json")
    meta = json.load(open(path)) if os.path.exists(path) else {}
    for n in names: meta[n] = bake(n)
    json.dump(meta, open(path, "w"), indent=1)


if __name__ == "__main__":
    main()
