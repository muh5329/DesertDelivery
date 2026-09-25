"""Rebuilds the bark of the imported Quaternius trees (assets/trees) as clean procedural tubes.

trees.py quadric-decimated the pack's trunks to 0.5-3 k triangles without keeping the surface
closed: seen close up (a plaza tree, a lane olive) a trunk was a lattice of disconnected triangles
with the sky showing through. The pack's originals are not in the repository, but the decimated
vertices still lie on the original trunk and limb surfaces, so:

  1. `--extract` (once): a skeleton per model is recovered from the decimated bark (the committed
     glTFs at SOURCE_REV): the vertices joined by their triangles and by proximity, the geodesic
     distance from the foot over that graph, cut into slabs, each slab's points clustered in space
     -> one node per cluster (centre, measured radius) linked to the cluster it grows from. Noise is
     pruned, the foot merged into one root, the radii replaced by a pipe model (a fork's radius from
     its children's, a taper along the limb) scaled to the measured trunk. Written to
     world/mapgen/tree_skeletons.json (reviewable, hand-tunable).
  2. default: every limb of the skeleton becomes a closed tapered tube (Catmull-Rom smoothed, rings
     where it bends, sides by radius, parallel-transported frames so it never twists by accident),
     the trunk with a root flare and buttress lobes, TwistedTree with a spiral grain; UVs run up the
     limb (v) and round it (u, whole repeats) for the bark map, normals from the surface. Tips close
     in a short cone. The bark primitive of each glTF is replaced; the leaf cards are copied
     byte-for-byte. Budgets: TwistedTree <= 3000 bark triangles, Pine <= 900.

    python3 world/mapgen/tree_bark.py --extract     # skeletons from the decimated bark (git SOURCE_REV)
    python3 world/mapgen/tree_bark.py               # tubes -> assets/trees/*.gltf/.bin
"""
import json, math, os, subprocess, sys
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TREES = os.path.join(ROOT, "assets", "trees")
SKEL = os.path.join(ROOT, "world", "mapgen", "tree_skeletons.json")
SOURCE_REV = "13521a7"          # the last commit with the decimated bark (the skeletons' source)
MODELS = ["TwistedTree_1", "TwistedTree_2", "TwistedTree_3", "Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"]
BUDGET = {"TwistedTree": 3000, "Pine": 900}
CT = {5126: np.float32, 5123: np.uint16, 5125: np.uint32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}

# per family: pipe-model exponent, tip radius (m), taper (radius gained per metre of limb),
# bark texture width in metres, spiral grain (u repeats per v), flare
STYLE = {
    "TwistedTree": {"exp": 2.3, "tip": 0.035, "taper": 0.010, "tex_w": 0.9, "twist": 0.18,
                    "flare": 0.3, "flare_len": 0.7, "lobes": 5, "lobe_amt": 0.12, "sink": 0.35},
    "Pine": {"exp": 2.5, "tip": 0.018, "taper": 0.026, "tex_w": 0.55, "twist": 0.0,
             "flare": 0.3, "flare_len": 0.35, "lobes": 4, "lobe_amt": 0.08, "sink": 0.3},
}


def family(name):
    return name.split("_")[0]


# ------------------------------------------------------------------ glTF io
def read_gltf(name, rev=None):
    if rev:
        g = json.loads(subprocess.check_output(["git", "-C", ROOT, "show", "%s:assets/trees/%s.gltf" % (rev, name)]))
        buf = subprocess.check_output(["git", "-C", ROOT, "show", "%s:assets/trees/%s.bin" % (rev, name)])
    else:
        g = json.load(open(os.path.join(TREES, name + ".gltf")))
        buf = open(os.path.join(TREES, name + ".bin"), "rb").read()

    def acc(i):
        a = g["accessors"][i]; bv = g["bufferViews"][a["bufferView"]]
        n = NC[a["type"]]
        return np.frombuffer(buf, dtype=CT[a["componentType"]], count=a["count"] * n,
                             offset=bv.get("byteOffset", 0) + a.get("byteOffset", 0)).reshape(a["count"], n).copy()
    prims = []
    for p in g["meshes"][0]["primitives"]:
        at = p["attributes"]
        prims.append({"mat": p["material"], "name": g["materials"][p["material"]]["name"],
                      "pos": acc(at["POSITION"]), "nrm": acc(at["NORMAL"]), "uv": acc(at["TEXCOORD_0"]),
                      "idx": acc(p["indices"]).reshape(-1).astype(np.uint32)})
    return g, prims


def write_gltf(name, g, prims):
    blob = bytearray(); views, accs, out_prims = [], [], []

    def add(arr, target, atype, ctype):
        nonlocal blob
        while len(blob) % 4: blob += b"\0"
        data = np.ascontiguousarray(arr).tobytes()
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
        blob += data
        a = {"bufferView": len(views) - 1, "componentType": ctype, "count": int(arr.shape[0]), "type": atype}
        if atype == "VEC3":
            a["min"] = [float(v) for v in arr.min(0)]; a["max"] = [float(v) for v in arr.max(0)]
        accs.append(a)
        return len(accs) - 1

    for p in prims:
        out_prims.append({"attributes": {"POSITION": add(p["pos"].astype(np.float32), 34962, "VEC3", 5126),
                                         "NORMAL": add(p["nrm"].astype(np.float32), 34962, "VEC3", 5126),
                                         "TEXCOORD_0": add(p["uv"].astype(np.float32), 34962, "VEC2", 5126)},
                          "indices": add(p["idx"].astype(np.uint32).reshape(-1, 1), 34963, "SCALAR", 5125),
                          "material": p["mat"]})
    mats = json.loads(json.dumps(g["materials"]))
    for m in mats:
        if m["name"].startswith("Bark"):
            # closed tubes with a clean tangent frame: one-sided, and the pack's normal map is back
            m["doubleSided"] = False
            src = [i for i, im in enumerate(g["images"]) if im["name"] == m["name"] + "_Normal"]
            tex = [i for i, t in enumerate(g["textures"]) if src and t["source"] == src[0]]
            if tex: m["normalTexture"] = {"index": tex[0]}
    out = {"asset": {"generator": "trees.py + tree_bark.py (Quaternius Stylized Nature, CC0)", "version": "2.0"},
           "scene": 0, "scenes": [{"name": "Scene", "nodes": [0]}], "nodes": [{"mesh": 0, "name": name}],
           "meshes": [{"name": name, "primitives": out_prims}], "materials": mats, "textures": g["textures"],
           "images": g["images"], "samplers": g.get("samplers", []),
           "buffers": [{"byteLength": len(blob), "uri": name + ".bin"}], "bufferViews": views, "accessors": accs}
    open(os.path.join(TREES, name + ".bin"), "wb").write(blob)
    json.dump(out, open(os.path.join(TREES, name + ".gltf"), "w"), indent=1)


# ------------------------------------------------------------------ 1. skeleton extraction
def extract(name):
    from scipy.spatial import cKDTree
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import dijkstra, connected_components
    g, prims = read_gltf(name, SOURCE_REV)
    bark = [p for p in prims if p["name"].startswith("Bark")][0]
    uq, inv = np.unique(np.round(bark["pos"], 4), axis=0, return_inverse=True)
    P = uq.astype(np.float64); n = len(P); inv = inv.reshape(-1)
    H = float(np.ptp(P[:, 1]))
    link, binw, clus = 0.03 * H, 0.03 * H, 0.05 * H
    tris = inv[bark["idx"].reshape(-1, 3)]
    e = np.concatenate([tris[:, [0, 1]], tris[:, [1, 2]], tris[:, [0, 2]]])
    pr = np.array(sorted(cKDTree(P).query_pairs(link)))
    if len(pr): e = np.concatenate([e, pr])
    e = e[e[:, 0] != e[:, 1]]

    def graph(edges):
        w = np.linalg.norm(P[edges[:, 0]] - P[edges[:, 1]], axis=1) + 1e-6
        return coo_matrix((np.concatenate([w, w]), (np.concatenate([edges[:, 0], edges[:, 1]]), np.concatenate([edges[:, 1], edges[:, 0]]))), shape=(n, n)).tocsr()
    ymin = P[:, 1].min()
    roots = np.where(P[:, 1] < ymin + 0.02 * H)[0]
    # stray pieces (the decimation's islands) join the rooted piece at their nearest point
    while True:
        nc, lab = connected_components(graph(e), directed=False)
        if nc == 1: break
        main = np.where(lab == lab[roots[0]])[0]
        oth = np.where(lab != lab[roots[0]])[0]
        d, j = cKDTree(P[main]).query(P[oth])
        k = int(np.argmin(d))
        e = np.concatenate([e, [[oth[k], main[j[k]]]]])
    A = graph(e)
    dist = dijkstra(A, indices=roots, min_only=True)
    b = np.floor(dist / binw).astype(int)
    # clusters: single linkage in space inside each geodesic slab
    lab = -np.ones(n, int); nc = 0
    for bb in np.unique(b):
        ii = np.where(b == bb)[0]
        prs = np.array(sorted(cKDTree(P[ii]).query_pairs(clus))) if len(ii) > 1 else np.zeros((0, 2), int)
        if len(prs) == 0:
            lab[ii] = nc + np.arange(len(ii)); nc += len(ii); continue
        M = coo_matrix((np.ones(len(prs)), (prs[:, 0], prs[:, 1])), shape=(len(ii), len(ii)))
        k, l2 = connected_components(M, directed=False)
        lab[ii] = nc + l2; nc += k
    cbin = np.zeros(nc, int); cbin[lab] = b
    cnt = np.bincount(lab, minlength=nc)
    cen = np.stack([np.bincount(lab, P[:, k], minlength=nc) / np.maximum(cnt, 1) for k in range(3)], 1)
    Ac = A.tocoo()
    par = -np.ones(nc, int)
    votes = {}
    for r, c, dr, dc in zip(lab[Ac.row], lab[Ac.col], b[Ac.row], b[Ac.col]):
        if dr <= dc or dr - dc > 2: continue
        votes.setdefault(r, {}).setdefault(c, 0.0); votes[r][c] += 1.0 / (dr - dc)
    for r, vs in votes.items(): par[r] = max(vs, key=vs.get)
    # the foot: every slab-0 cluster merges into one root
    foot = np.where(cbin == 0)[0]
    root_pos = P[b == 0].mean(0)
    for k in range(nc):
        if par[k] >= 0 and cbin[par[k]] == 0: par[k] = foot[0]
        if par[k] < 0 and cbin[k] > 0:
            lower = np.where(cbin < cbin[k])[0]
            par[k] = lower[np.argmin(np.linalg.norm(cen[lower] - cen[k], axis=1))]
            if cbin[par[k]] == 0: par[k] = foot[0]
    cen[foot[0]] = root_pos; cnt[foot[0]] = int((b == 0).sum())
    alive = np.ones(nc, bool); alive[foot[1:]] = False
    # measured radius: median distance of the cluster's points from its axis
    rm = np.full(nc, np.nan)
    for k in range(nc):
        if not alive[k] or cnt[k] < 4: continue
        pts = P[lab == k] if k != foot[0] else P[b == 0]
        d = cen[k] - cen[par[k]] if par[k] >= 0 else np.array([0.0, 1.0, 0.0])
        d = d / (np.linalg.norm(d) + 1e-9)
        v = pts - cen[k]; v -= np.outer(v @ d, d)
        rm[k] = np.median(np.linalg.norm(v, axis=1))
    nodes = {int(k): {"p": cen[k].tolist(), "parent": int(par[k]), "rm": None if np.isnan(rm[k]) else float(rm[k]), "n": int(cnt[k])}
             for k in range(nc) if alive[k]}
    return clean(name, nodes, int(foot[0]), H)


def children_of(nodes):
    ch = {k: [] for k in nodes}
    for k, v in nodes.items():
        if v["parent"] in nodes: ch[v["parent"]].append(k)
    return ch


def clean(name, nodes, root, H):
    st = STYLE[family(name)]
    nodes[root]["parent"] = -1
    # siblings closer than their own girth are one limb the slab clustering split (the decimated
    # surface is sparse): merge them, children and all, repeatedly
    changed = True
    while changed:
        changed = False
        ch = children_of(nodes)
        for k in list(nodes.keys()):
            if k not in nodes: continue
            cs = [c for c in ch.get(k, []) if c in nodes]
            for i in range(len(cs)):
                for j in range(i + 1, len(cs)):
                    a, b = cs[i], cs[j]
                    if a not in nodes or b not in nodes: continue
                    pa, pb = np.array(nodes[a]["p"]), np.array(nodes[b]["p"])
                    lim = 1.3 * max(nodes[a]["rm"] or 0.0, nodes[b]["rm"] or 0.0) + 0.02 * H
                    if np.linalg.norm(pa - pb) > lim: continue
                    na, nb = nodes[a]["n"], nodes[b]["n"]
                    nodes[a]["p"] = ((pa * na + pb * nb) / max(na + nb, 1)).tolist()
                    nodes[a]["n"] = na + nb
                    ra, rb = nodes[a]["rm"], nodes[b]["rm"]
                    nodes[a]["rm"] = max(ra or 0.0, rb or 0.0) or None
                    for c in ch.get(b, []):
                        if c in nodes: nodes[c]["parent"] = a
                    nodes.pop(b)
                    changed = True
            if changed: break
    # prune: twigs of one or two nodes off a fork (the slab clusters' noise), repeatedly
    for _ in range(3):
        ch = children_of(nodes)
        drop = set()
        for k, v in nodes.items():
            if ch[k] or k == root: continue
            # walk down to the fork
            chain = [k]; q = v["parent"]
            while q in nodes and len(ch[q]) == 1 and q != root:
                chain.append(q); q = nodes[q]["parent"]
            if q in nodes and len(ch[q]) > 1 and len(chain) <= 2 and sum(nodes[c]["n"] for c in chain) < 12:
                drop.update(chain)
        for k in drop: nodes.pop(k)
    # reindex: parents before children
    ch = children_of(nodes)
    order = [root]; i = 0
    while i < len(order):
        order += sorted(ch[order[i]], key=lambda c: nodes[c]["p"][1]); i += 1
    remap = {k: j for j, k in enumerate(order)}
    out = [{"p": nodes[k]["p"], "parent": remap.get(nodes[k]["parent"], -1), "rm": nodes[k]["rm"], "n": nodes[k]["n"]} for k in order]
    # smooth the positions along the limbs (fork and foot points fixed)
    ch = children_of({i: v for i, v in enumerate(out)})
    P = np.array([v["p"] for v in out])
    # the limb a fork continues: its heaviest child (most nodes above it)
    weight = np.ones(len(out))
    for i in reversed(range(len(out))):
        if out[i]["parent"] >= 0: weight[out[i]["parent"]] += weight[i]
    for _ in range(8):
        Q = P.copy()
        for i, v in enumerate(out):
            if v["parent"] < 0 or not ch[i]: continue
            main = max(ch[i], key=lambda c: weight[c])
            Q[i] = 0.5 * P[i] + 0.25 * (P[v["parent"]] + P[main])
        P = Q
    # pipe-model radii from the tips down, scaled to the measured trunk
    rp = np.zeros(len(out))
    for i in reversed(range(len(out))):
        cs = ch[i]
        if not cs: rp[i] = st["tip"]; continue
        pipe = sum(rp[c] ** st["exp"] for c in cs) ** (1.0 / st["exp"])
        tap = max(rp[c] + st["taper"] * np.linalg.norm(P[c] - P[i]) for c in cs)
        rp[i] = max(pipe, tap)
    ratios = [v["rm"] / rp[i] for i, v in enumerate(out) if v["rm"] and v["n"] >= 8 and rp[i] > 3 * st["tip"]]
    # (the decimated surface over-reads the thin limbs' girth; the cap keeps a TwistedTree's
    # trunk inside the plaza planters, 0.85 m, at its usual scale)
    s = float(np.clip(np.median(ratios), 0.6, 1.5)) if ratios else 1.0
    # the foot's measure is the flare's; the trunk takes the ratio of its first metres
    for i, v in enumerate(out):
        v["p"] = [round(float(x), 4) for x in P[i]]
        v["r"] = round(float(max(rp[i] * s, st["tip"])), 4)
        v.pop("rm"); v.pop("n")
    print("%-14s nodes %4d  radius scale %.2f  trunk r %.3f" % (name, len(out), s, out[0]["r"]))
    return out


# ------------------------------------------------------------------ 2. tubes
def chains(nodes):
    """Limbs as lists of node indices: the thickest child continues its parent's limb, every other
    child starts a new limb at the fork."""
    ch = children_of({i: v for i, v in enumerate(nodes)})
    out = []
    stack = [(0, None)]
    while stack:
        start, fork = stack.pop()
        limb = [fork] if fork is not None else []
        k = start
        while True:
            limb.append(k)
            cs = sorted(ch[k], key=lambda c: -nodes[c]["r"])
            if not cs: break
            for c in cs[1:]: stack.append((c, k))
            k = cs[0]
        out.append(limb)
    return out


def catmull(P, R, step):
    """Dense samples of a Catmull-Rom curve through P (radii linear)."""
    pts, rad = [], []
    n = len(P)
    for i in range(n - 1):
        p0 = P[max(i - 1, 0)]; p1 = P[i]; p2 = P[i + 1]; p3 = P[min(i + 2, n - 1)]
        m = max(2, int(math.ceil(np.linalg.norm(p2 - p1) / step)))
        for j in range(m):
            t = j / m
            t2, t3 = t * t, t * t * t
            q = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            pts.append(q); rad.append(R[i] + (R[i + 1] - R[i]) * t)
    pts.append(P[-1]); rad.append(R[-1])
    return np.array(pts), np.array(rad)


def sides_for(r, fam, q):
    th = [0.30, 0.16, 0.08, 0.04] if fam == "TwistedTree" else [0.16, 0.08, 0.035, 0.0]
    sides = [11, 9, 7, 5, 4] if fam == "TwistedTree" else [9, 7, 5, 4, 3]
    r = r / q
    for t, s in zip(th, sides):
        if r > t: return s
    return sides[-1]


def build(name, nodes, quality=1.0):
    fam = family(name); st = STYLE[fam]
    P = np.array([v["p"] for v in nodes]); R = np.array([v["r"] for v in nodes])
    ground = P[0, 1]
    V, N, UV, I = [], [], [], []
    for limb in chains(nodes):
        # (a stub a couple of nodes long off the foot is the slab clustering's noise, not a sucker)
        if limb[0] != 0 and P[limb[0], 1] - ground < 1.5 and len(limb) < 5: continue
        lp = P[limb].copy(); lr = R[limb].copy()
        if limb[0] != 0 and len(limb) >= 2:
            # a side limb starts at its fork (inside the parent limb) with its own radius
            lr[0] = lr[1]
        else:
            # the trunk: down into the ground so no slope shows the foot
            lp = np.vstack([lp[0] - [0, st["sink"], 0], lp]); lr = np.concatenate([[lr[0]], lr])
        if len(lp) < 2: continue
        dense, drad = catmull(lp, lr, 0.05)
        # rings: where the limb has bent 14 degrees or run its length allowance
        seg = np.linalg.norm(np.diff(dense, axis=0), axis=1)
        s_acc = np.concatenate([[0], np.cumsum(seg)])
        tan = np.gradient(dense, axis=0); tan /= np.linalg.norm(tan, axis=1, keepdims=True) + 1e-9
        keep = [0]; last_t = tan[0]
        for i in range(1, len(dense) - 1):
            run = s_acc[i] - s_acc[keep[-1]]
            allow = np.clip(7.0 * drad[i] * quality, 0.25, 1.6 * quality)
            flare_zone = limb[0] == 0 and dense[i, 1] - ground < st["flare_len"] * 2.5
            if flare_zone: allow = min(allow, st["flare_len"] * 0.35)
            if run >= allow or (np.degrees(np.arccos(np.clip(last_t @ tan[i], -1, 1))) > 14.0 * quality and run > 0.1):
                keep.append(i); last_t = tan[i]
        keep.append(len(dense) - 1)
        rp = dense[keep]; rr = drad[keep]; rs = s_acc[keep]
        rt = np.gradient(rp, axis=0); rt /= np.linalg.norm(rt, axis=1, keepdims=True) + 1e-9
        # parallel-transported frames
        up = np.array([0.0, 0.0, 1.0]) if abs(rt[0, 1]) > 0.9 else np.array([0.0, 1.0, 0.0])
        nrm0 = np.cross(rt[0], up); nrm0 /= np.linalg.norm(nrm0)
        frames = [nrm0]
        for i in range(1, len(rp)):
            f = frames[-1] - rt[i] * (frames[-1] @ rt[i]); f /= np.linalg.norm(f) + 1e-9
            frames.append(f)
        # sections of constant side count (a thinning limb drops sides)
        sec_start = 0
        while sec_start < len(rp) - 1:
            ns = sides_for(rr[sec_start], fam, quality)
            e = sec_start + 1
            while e < len(rp) - 1 and sides_for(rr[e], fam, quality) == ns: e += 1
            rings = list(range(sec_start, e + 1))
            repeats = max(1, int(round(2 * math.pi * rr[sec_start] / st["tex_w"])))
            base = len(V)
            grid = []
            for ri in rings:
                c = rp[ri]; t = rt[ri]; a = frames[ri]; bvec = np.cross(t, a)
                r = rr[ri]
                h = c[1] - ground
                trunk = limb[0] == 0
                row = []
                for j in range(ns + 1):
                    th = 2 * math.pi * j / ns
                    rad = r
                    if trunk and h < st["flare_len"] * 3:
                        # (below the foot the flare keeps widening a little: no kink at the ground)
                        f = min(math.exp(-h / st["flare_len"]), 1.4)
                        rad = r * (1 + st["flare"] * f) * (1 + st["lobe_amt"] * f * max(0.0, math.cos(st["lobes"] * th + 0.7)) ** 2 * 2.0)
                    d = a * math.cos(th) + bvec * math.sin(th)
                    row.append(c + d * rad)
                    v_coord = rs[ri] / st["tex_w"]
                    UV.append([repeats * j / ns + st["twist"] * v_coord, -v_coord])
                    V.append(c + d * rad)
                grid.append(row)
            grid = np.array(grid)                        # rings x (ns+1) x 3
            # normals from the surface: d/dtheta x d/ds
            dth = np.roll(grid[:, :-1], -1, axis=1) - np.roll(grid[:, :-1], 1, axis=1)
            dth = np.concatenate([dth, dth[:, :1]], axis=1)
            ds = np.gradient(grid, axis=0) if len(rings) > 1 else np.repeat(rt[rings][:, None, :], ns + 1, 1)
            nn = np.cross(dth, ds)
            radial = grid - rp[rings][:, None, :]
            flip = np.sum(nn * radial, axis=2) < 0
            nn[flip] *= -1
            nn /= np.linalg.norm(nn, axis=2, keepdims=True) + 1e-9
            N.extend(nn.reshape(-1, 3).tolist())
            for a_ in range(len(rings) - 1):
                for j in range(ns):
                    i0 = base + a_ * (ns + 1) + j; i1 = i0 + 1; i2 = i0 + ns + 1; i3 = i2 + 1
                    I.extend([i0, i2, i1, i1, i2, i3])
            if e == len(rp) - 1:
                # the tip: a short cone
                tipv = len(V)
                tip = rp[-1] + rt[-1] * max(rr[-1] * 2.5, 0.05)
                V.append(tip); N.append(rt[-1].tolist()); UV.append([0.5 * repeats, -(rs[-1] + 0.05) / st["tex_w"]])
                last = base + (len(rings) - 1) * (ns + 1)
                for j in range(ns): I.extend([last + j, tipv, last + j + 1])
            sec_start = e
    V = np.array(V, np.float32); N = np.array(N, np.float32); UV = np.array(UV, np.float32); I = np.array(I, np.uint32)
    # winding: outward normals must see counter-clockwise triangles (glTF front faces)
    tri = I.reshape(-1, 3)
    fn = np.cross(V[tri[:, 1]] - V[tri[:, 0]], V[tri[:, 2]] - V[tri[:, 0]])
    if np.sum(np.sum(fn * N[tri[:, 0]], axis=1) > 0) < len(tri) * 0.5:
        tri = tri[:, [0, 2, 1]]
    return V, N, UV, tri.reshape(-1).astype(np.uint32)


def main():
    if "--extract" in sys.argv:
        skel = {m: extract(m) for m in MODELS}
        json.dump(skel, open(SKEL, "w"), separators=(",", ":"))
        return
    skel = json.load(open(SKEL))
    for m in MODELS:
        g, prims = read_gltf(m)
        budget = BUDGET[family(m)]
        q = 1.0
        while True:
            V, N, UV, I = build(m, skel[m], q)
            if len(I) // 3 <= budget or q > 3: break
            q *= 1.12
        for p in prims:
            if p["name"].startswith("Bark"):
                old = len(p["idx"]) // 3
                p.update(pos=V, nrm=N, uv=UV, idx=I)
        write_gltf(m, g, prims)
        print("%-14s bark %5d -> %5d tris (%d verts, quality %.2f)" % (m, old, len(I) // 3, len(V), q))


if __name__ == "__main__":
    main()
