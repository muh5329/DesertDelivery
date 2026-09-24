"""Road routing for the outer world: A* over a coarse cost grid, polyline smoothing and
resampling, grade-limited vertical profiles, bridge detection and cut/fill carving.
"""
import numpy as np
from numba import njit
from scipy import ndimage

# 16-neighbour moves (8 + knight moves) so routes are not limited to 45 degree headings
MOVES = np.array([[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1],
                  [2, 1], [1, 2], [-1, 2], [-2, 1], [-2, -1], [-1, -2], [1, -2], [2, -1]], np.int64)


@njit(cache=True)
def _heap_push(hf, hn, size, f, node):
    i = size
    hf[i] = f; hn[i] = node
    while i > 0:
        p = (i - 1) >> 1
        if hf[p] <= hf[i]:
            break
        hf[p], hf[i] = hf[i], hf[p]
        hn[p], hn[i] = hn[i], hn[p]
        i = p
    return size + 1


@njit(cache=True)
def _heap_pop(hf, hn, size):
    f = hf[0]; node = hn[0]
    size -= 1
    hf[0] = hf[size]; hn[0] = hn[size]
    i = 0
    while True:
        l = 2 * i + 1; r = l + 1; m = i
        if l < size and hf[l] < hf[m]: m = l
        if r < size and hf[r] < hf[m]: m = r
        if m == i: break
        hf[m], hf[i] = hf[i], hf[m]
        hn[m], hn[i] = hn[i], hn[m]
        i = m
    return f, node, size


@njit(cache=True)
def astar(h, water, forbid, roadcell, cell, start, goal, target, gmax, k_grade, water_mult, cross_pen, follow_mult, heur_w, mult):
    """h: routing heights (n, n); water/forbid/roadcell/target: uint8 masks.
    goal >= 0: single goal node (A* with Euclid heuristic); goal < 0: stop at the first node
    with target != 0 (Dijkstra). Returns the node path (flat indices j * n + i)."""
    n0, n1 = h.shape
    total = n0 * n1
    g = np.full(total, 1e30)
    parent = np.full(total, -1, np.int64)
    closed = np.zeros(total, np.uint8)
    cap = total * 4
    hf = np.empty(cap); hn = np.empty(cap, np.int64)
    size = 0
    g[start] = 0.0
    gi = goal % n1; gj = goal // n1
    size = _heap_push(hf, hn, size, 0.0, start)
    found = -1
    while size > 0:
        f, node, size = _heap_pop(hf, hn, size)
        if closed[node]: continue
        closed[node] = 1
        ci = node % n1; cj = node // n1
        if goal >= 0:
            if node == goal: found = node; break
        elif target[cj, ci] != 0 and node != start:
            found = node; break
        hc = h[cj, ci]
        for m in range(16):
            di = MOVES[m, 0]; dj = MOVES[m, 1]
            ni = ci + di; nj = cj + dj
            if ni < 0 or nj < 0 or ni >= n1 or nj >= n0: continue
            nn = nj * n1 + ni
            if closed[nn]: continue
            if forbid[nj, ni]: continue
            L = np.sqrt(di * di + dj * dj) * cell
            # knight moves: the two cells the move passes between must be passable too
            if m >= 8:
                ai = ci + (di // 2 if abs(di) == 2 else 0); aj = cj + (dj // 2 if abs(dj) == 2 else 0)
                bi = ci + (di if abs(di) == 1 else di // 2); bj = cj + (dj if abs(dj) == 1 else dj // 2)
                if forbid[aj, ai] or forbid[bj, bi]: continue
            dh = h[nj, ni] - hc
            gr = abs(dh) / L
            wet = water[nj, ni] != 0
            if wet:
                c = L * water_mult
            else:
                q = gr / gmax
                c = L * (1.0 + k_grade * q * q)
                if gr > gmax:
                    c += L * 400.0 * (gr - gmax) / gmax
            c *= mult[nj, ni]
            if roadcell[nj, ni] != 0:
                c = c * follow_mult + cross_pen
            ng = g[node] + c
            if ng < g[nn]:
                g[nn] = ng
                parent[nn] = node
                hh = 0.0
                if goal >= 0:
                    hh = np.sqrt(float((ni - gi) ** 2 + (nj - gj) ** 2)) * cell * heur_w
                if size >= cap: return np.zeros(0, np.int64)
                size = _heap_push(hf, hn, size, ng + hh, nn)
    if found < 0:
        return np.zeros(0, np.int64)
    out = []
    node = found
    while node >= 0:
        out.append(node)
        node = parent[node]
    res = np.empty(len(out), np.int64)
    for k in range(len(out)):
        res[k] = out[len(out) - 1 - k]
    return res


def rdp(pts, tol):
    """Ramer-Douglas-Peucker simplification (keeps the ends)."""
    pts = np.asarray(pts, float)
    if len(pts) < 3: return pts
    keep = np.zeros(len(pts), bool); keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        if b <= a + 1: continue
        p = pts[a]; q = pts[b]; d = q - p
        L = np.hypot(*d)
        seg = pts[a + 1:b] - p
        if L < 1e-9: dist = np.hypot(seg[:, 0], seg[:, 1])
        else: dist = np.abs(seg[:, 0] * d[1] - seg[:, 1] * d[0]) / L
        k = int(np.argmax(dist))
        if dist[k] > tol:
            m = a + 1 + k; keep[m] = True
            stack.append((a, m)); stack.append((m, b))
    return pts[keep]


def chaikin(pts, iterations=3, keep_ends=True):
    pts = np.asarray(pts, float)
    for _ in range(iterations):
        if len(pts) < 3: break
        q = 0.75 * pts[:-1] + 0.25 * pts[1:]
        r = 0.25 * pts[:-1] + 0.75 * pts[1:]
        new = np.empty((2 * (len(pts) - 1), 2))
        new[0::2] = q; new[1::2] = r
        if keep_ends:
            new = np.vstack([pts[:1], new, pts[-1:]])
        pts = new
    return pts


def resample(pts, step):
    """Points every `step` metres along the polyline; the last point is kept exactly."""
    pts = np.asarray(pts, float)
    seg = np.hypot(*(pts[1:] - pts[:-1]).T)
    cum = np.concatenate([[0], np.cumsum(seg)])
    total = cum[-1]
    n = max(int(np.ceil(total / step - 1e-6)), 1)
    s = np.linspace(0, total, n + 1)
    x = np.interp(s, cum, pts[:, 0]); z = np.interp(s, cum, pts[:, 1])
    out = np.stack([x, z], 1)
    out[0] = pts[0]; out[-1] = pts[-1]
    return out


def curvature_smooth(pts, min_radius, iterations=60, fixed_head=1, fixed_tail=1):
    """Laplacian relaxation where the turn radius is below `min_radius` (ends fixed)."""
    p = np.asarray(pts, float).copy()
    n = len(p)
    if n < 5: return p
    for _ in range(iterations):
        a = p[:-2]; b = p[1:-1]; c = p[2:]
        ab = np.hypot(*(b - a).T); bc = np.hypot(*(c - b).T); ac = np.hypot(*(c - a).T)
        cross = np.abs((b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (b[:, 1] - a[:, 1]) * (c[:, 0] - a[:, 0]))
        R = ab * bc * ac / np.maximum(2 * cross, 1e-9)
        bad = R < min_radius
        bad[:fixed_head] = False
        if fixed_tail > 0: bad[-fixed_tail:] = False
        if not bad.any(): break
        mid = 0.5 * (a + c)
        b[bad] = b[bad] + 0.5 * (mid[bad] - b[bad])
        p[1:-1] = b
    return p


def lipschitz_profile(target, ds, gmax, fixed, lower, cut_bias=0.5):
    """Grade-limited profile close to `target`: a blend of the upper and lower Lipschitz
    envelopes (`cut_bias` 0.5 = their mean, balanced cut and fill; toward 1 = the envelope under
    the ground, i.e. cuttings rather than fills), clamped to the envelopes of the `fixed` samples
    (exact there) and raised to the envelope of the `lower` bounds (bridges / clearances). All
    results have |dy/ds| <= gmax."""
    n = len(target)
    G = gmax * ds
    up = target.copy(); lo = target.copy()
    for i in range(1, n):
        up[i] = min(up[i], up[i - 1] + G); lo[i] = max(lo[i], lo[i - 1] - G)
    for i in range(n - 2, -1, -1):
        up[i] = min(up[i], up[i + 1] + G); lo[i] = max(lo[i], lo[i + 1] - G)
    y = cut_bias * up + (1.0 - cut_bias) * lo
    # lower bounds (deck clearances): raise to their Lipschitz envelope
    if lower is not None:
        lb = lower.copy()
        for i in range(1, n): lb[i] = max(lb[i], lb[i - 1] - G)
        for i in range(n - 2, -1, -1): lb[i] = max(lb[i], lb[i + 1] - G)
        y = np.maximum(y, lb)
    if fixed:
        U = np.full(n, 1e9); Lo = np.full(n, -1e9)
        idx = np.arange(n)
        for k, v in fixed.items():
            d = np.abs(idx - k) * G
            U = np.minimum(U, v + d); Lo = np.maximum(Lo, v - d)
        y = np.clip(y, Lo, U)
    return y


def smooth_profile(y, sigma_samples, fixed, lower=None, gmax=None, ds=4.0):
    """Gaussian smoothing (keeps the Lipschitz bound) with the fixed samples re-pinned."""
    if sigma_samples <= 0: return y
    ys = ndimage.gaussian_filter1d(y, sigma_samples, mode="nearest")
    if lower is not None:
        ys = np.maximum(ys, lower)
    if fixed:
        n = len(y); idx = np.arange(n); G = gmax * ds
        U = np.full(n, 1e9); Lo = np.full(n, -1e9)
        for k, v in fixed.items():
            d = np.abs(idx - k) * G
            U = np.minimum(U, v + d); Lo = np.maximum(Lo, v - d)
        ys = np.clip(ys, Lo, U)
    return ys


@njit(cache=True)
def carve_roads(h, origin, cell, xs, zs, ys, hw, seg_ok, full_extra, blend, dist_out, yt_out, hw_out):
    """For every grid cell within `blend` metres of a road segment (seg_ok[k] = segment k..k+1
    is carved), record the nearest segment's distance, its interpolated height and the road's
    half width."""
    n0, n1 = h.shape
    for k in range(len(xs) - 1):
        if not seg_ok[k]: continue
        ax = xs[k]; az = zs[k]; bx = xs[k + 1]; bz = zs[k + 1]
        r = blend + hw[k] + full_extra
        i0 = int((min(ax, bx) - r - origin) / cell); i1 = int((max(ax, bx) + r - origin) / cell) + 1
        j0 = int((min(az, bz) - r - origin) / cell); j1 = int((max(az, bz) + r - origin) / cell) + 1
        if i0 < 0: i0 = 0
        if j0 < 0: j0 = 0
        if i1 > n1 - 1: i1 = n1 - 1
        if j1 > n0 - 1: j1 = n0 - 1
        dx = bx - ax; dz = bz - az
        L2 = dx * dx + dz * dz
        for j in range(j0, j1 + 1):
            wz = origin + j * cell
            for i in range(i0, i1 + 1):
                wx = origin + i * cell
                t = 0.0
                if L2 > 1e-9:
                    t = ((wx - ax) * dx + (wz - az) * dz) / L2
                    if t < 0: t = 0.0
                    if t > 1: t = 1.0
                px = ax + dx * t; pz = az + dz * t
                d = np.sqrt((wx - px) ** 2 + (wz - pz) ** 2)
                if d < dist_out[j, i]:
                    dist_out[j, i] = d
                    yt_out[j, i] = ys[k] + (ys[k + 1] - ys[k]) * t
                    hw_out[j, i] = hw[k]


def apply_carve(h, dist, yt, hw, full_extra, blend):
    """Blend the heightfield toward the road heights: exact within half width + full_extra,
    smooth falloff to `blend` metres beyond that."""
    d0 = hw + full_extra
    t = np.clip((dist - d0) / blend, 0, 1)
    w = 1 - t * t * (3 - 2 * t)
    w[dist > 1e8] = 0
    return h + (yt - h) * w, w
