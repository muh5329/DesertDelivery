"""A small orthographic triangle rasteriser (numpy): tree_impostors.py bakes the far-tree cards
with it (depth test, per-triangle alpha test against a leaf atlas, barycentric interpolation)."""
import numpy as np


def raster(xy, depth, tris, size, alpha_uv=None, alpha_tex=None, alpha_cut=0.5, tri_tag=None):
    """xy: (n, 2) pixel coordinates, depth: (n,) (smaller = nearer), tris: (m, 3) indices.
    alpha_uv / alpha_tex: per-vertex UVs and an (h, w) alpha map for triangles whose tag is 1
    (alpha-tested cards). Returns (zbuf, tri_id, bary) with tri_id = -1 where nothing drew."""
    W, H = size
    zbuf = np.full((H, W), np.inf, np.float32)
    tid = np.full((H, W), -1, np.int32)
    bary = np.zeros((H, W, 3), np.float32)
    if alpha_tex is not None:
        th, tw = alpha_tex.shape
    for t, (a, b, c) in enumerate(tris):
        p0, p1, p2 = xy[a], xy[b], xy[c]
        x0 = max(int(np.floor(min(p0[0], p1[0], p2[0]))), 0); x1 = min(int(np.ceil(max(p0[0], p1[0], p2[0]))), W - 1)
        y0 = max(int(np.floor(min(p0[1], p1[1], p2[1]))), 0); y1 = min(int(np.ceil(max(p0[1], p1[1], p2[1]))), H - 1)
        if x1 < x0 or y1 < y0: continue
        den = (p1[1] - p2[1]) * (p0[0] - p2[0]) + (p2[0] - p1[0]) * (p0[1] - p2[1])
        if abs(den) < 1e-12: continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        w0 = ((p1[1] - p2[1]) * (gx - p2[0]) + (p2[0] - p1[0]) * (gy - p2[1])) / den
        w1 = ((p2[1] - p0[1]) * (gx - p2[0]) + (p0[0] - p2[0]) * (gy - p2[1])) / den
        w2 = 1.0 - w0 - w1
        m = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not m.any(): continue
        z = w0 * depth[a] + w1 * depth[b] + w2 * depth[c]
        if alpha_tex is not None and tri_tag is not None and tri_tag[t] == 1:
            u = w0 * alpha_uv[a, 0] + w1 * alpha_uv[b, 0] + w2 * alpha_uv[c, 0]
            v = w0 * alpha_uv[a, 1] + w1 * alpha_uv[b, 1] + w2 * alpha_uv[c, 1]
            iu = np.clip((u % 1.0) * tw, 0, tw - 1).astype(int); iv = np.clip((v % 1.0) * th, 0, th - 1).astype(int)
            m &= alpha_tex[iv, iu] >= alpha_cut
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        m &= z < sub
        if not m.any(): continue
        sub[m] = z[m]
        tid[y0:y1 + 1, x0:x1 + 1][m] = t
        bb = bary[y0:y1 + 1, x0:x1 + 1]
        bb[m] = np.stack([w0[m], w1[m], w2[m]], 1)
    return zbuf, tid, bary


def interp(attr, tris, tid, bary):
    """Per-pixel interpolation of a per-vertex attribute (n, k) -> (H, W, k)."""
    H, W = tid.shape
    out = np.zeros((H, W, attr.shape[1]), np.float32)
    m = tid >= 0
    t = tris[tid[m]]
    b = bary[m]
    out[m] = attr[t[:, 0]] * b[:, :1] + attr[t[:, 1]] * b[:, 1:2] + attr[t[:, 2]] * b[:, 2:3]
    return out
