"""Expands the 720 m painting island into the 1248 m world (3x the area).

Reads the painting-derived data/island_map.png (241 px, 720 m: R=height, G=biome, B=tree
density) and writes the 417 px / 1248 m version:
  - the painted island is scaled by K = 1248/720 (every road and hub in painting pixels
    follows automatically through Island._px, because px_per_m in island_meta.json shrinks);
  - two new landmasses are grown into what used to be open sea: the Highlands in the north
    (moorland plateau: monastery, quarry, mountain pass) and the Southern Shore (dunes, the
    salt pans, the bodega's fields, a badlands headland with the old fort);
  - data/sea_depth.png (the sea shader's depth map) and island_meta.json are regenerated.

Run from the project root:  python3 world/mapgen/expand.py
It is idempotent: it always starts from world/mapgen/island_map_720.png (the original map).
"""
from PIL import Image, ImageDraw
import numpy as np, json, os, shutil
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, "data")
SRC = os.path.join(ROOT, "world", "mapgen", "island_map_720.png")
if not os.path.exists(SRC):
    shutil.copy(os.path.join(DATA, "island_map.png"), SRC)

SIZE0, N0 = 720.0, 241
SIZE, N = 1248.0, 417
CELL = 3.0
K = SIZE / SIZE0
SEA, LIMESTONE, FOREST, FARM, BADLANDS, TOWN, BEACH, LAKE, DUNES, MOOR, SALTFLAT = range(11)
LAND_LIFT = 1.15          # a touch more relief now that slopes are 1.7x longer

old = np.asarray(Image.open(SRC).convert("RGB")).astype(np.float32)
old_h = old[..., 0] / 255.0 * 90.0 - 10.0
old_b = old[..., 1].astype(np.uint8)
old_d = old[..., 2] / 255.0

# ---------------------------------------------------------------- scale the painted island
jj, ii = np.mgrid[0:N, 0:N]
wx = ii * CELL - SIZE / 2; wz = jj * CELL - SIZE / 2          # world metres of each new cell
gx = (wx / K + SIZE0 / 2) / CELL; gz = (wz / K + SIZE0 / 2) / CELL   # old grid coords (float)
inside = (gx >= 0) & (gx <= N0 - 1) & (gz >= 0) & (gz <= N0 - 1)
gxc = np.clip(gx, 0, N0 - 1.001); gzc = np.clip(gz, 0, N0 - 1.001)
h = ndimage.map_coordinates(old_h, [gzc, gxc], order=1, mode="nearest")
d = ndimage.map_coordinates(old_d, [gzc, gxc], order=1, mode="nearest")
b = old_b[np.clip(np.round(gzc), 0, N0 - 1).astype(int), np.clip(np.round(gxc), 0, N0 - 1).astype(int)]
b = b.copy(); b[~inside] = SEA
land_old = (b != SEA) & (b != LAKE)
h = np.where(land_old & (h > 0), h * LAND_LIFT, h)

# ---------------------------------------------------------------- new land
def poly_mask(poly):
    """Polygon in world metres -> boolean cell mask."""
    mk = Image.new("L", (N, N), 0)
    pts = [((x + SIZE / 2) / CELL, (z + SIZE / 2) / CELL) for x, z in poly]
    ImageDraw.Draw(mk).polygon(pts, fill=255)
    return np.asarray(mk) > 0

def wobble(mask, amount, seed, sigma=3.0):
    """Push the mask edge in and out with smooth noise so coasts are not polygon-straight."""
    rng = np.random.default_rng(seed)
    n = ndimage.gaussian_filter(rng.standard_normal((N, N)), sigma)
    n = n / (np.abs(n).max() + 1e-6)
    sdf = ndimage.distance_transform_edt(mask) - ndimage.distance_transform_edt(~mask)
    return sdf * CELL + n * amount > 0

def blob(cx, cz, r):
    return ((wx - cx) ** 2 + (wz - cz) ** 2) < r * r

HIGHLANDS = wobble(poly_mask([(-560, -320), (-520, -450), (-450, -535), (-340, -588), (-220, -592), (-110, -565),
                              (-45, -495), (-35, -410), (-75, -345), (-200, -318), (-420, -312)]), 28.0, 11)
SOUTH = wobble(poly_mask([(-480, 285), (-500, 400), (-455, 505), (-365, 565), (-230, 598), (-80, 592), (80, 602),
                          (240, 592), (365, 565), (440, 485), (440, 390), (395, 300), (250, 262), (0, 245), (-250, 258)]), 30.0, 12)
# a sheltered cove for the fishing village and a lagoon behind the dunes
COVE = wobble(blob(-395, 440, 34) | blob(-420, 470, 30), 8.0, 13)
LAGOON = wobble(blob(-40, 545, 26) | blob(-15, 555, 22), 8.0, 14)
SOUTH &= ~COVE
new_land = (HIGHLANDS | SOUTH) & ~land_old & (b != LAKE)

nb = b.copy(); nh = h.copy(); nd = d.copy()
# biomes of the new land
nb[new_land & HIGHLANDS] = MOOR
south = new_land & SOUTH
nb[south] = FOREST
nb[south & (wx < -120)] = DUNES
nb[south & (wx > 175)] = BADLANDS
BODEGA_FIELDS = wobble(blob(20, 430, 95) | blob(-40, 470, 60), 12.0, 15)
nb[south & BODEGA_FIELDS & (wx >= -120) & (wx <= 175)] = FARM
SALT = wobble(poly_mask([(-225, 445), (-95, 440), (-80, 520), (-130, 550), (-215, 535)]), 8.0, 16)
nb[south & SALT] = SALTFLAT
nb[LAGOON & south] = LAKE
land = (nb != SEA) & (nb != LAKE)

# heights of the new land: a shelf that climbs with distance from the sea, plus landmarks
dist_sea = ndimage.distance_transform_edt(land) * CELL
ramp = np.clip(dist_sea / 60.0, 0, 1)
rng = np.random.default_rng(7)
rough = ndimage.gaussian_filter(rng.standard_normal((N, N)), 2.0); rough /= np.abs(rough).max()
hn = np.zeros((N, N), np.float32)
moor = nb == MOOR
hn[moor] = 20.0 + 26.0 * np.clip(dist_sea[moor] / 90.0, 0, 1) + 5.0 * rough[moor]
hn += 20.0 * np.exp(-(((wx + 300) ** 2 + (wz + 470) ** 2) / (2 * 70.0 ** 2))) * moor     # the monastery peak
hn += 8.0 * np.exp(-(((wx + 120) ** 2 + (wz + 400) ** 2) / (2 * 60.0 ** 2))) * moor       # the quarry hill
hn[nb == DUNES] = 2.0 + 5.0 * ramp[nb == DUNES] + 2.5 * np.abs(rough[nb == DUNES])
hn[nb == SALTFLAT] = 0.7
f = (nb == FOREST) & south
hn[f] = 4.0 + 7.0 * ramp[f] + 2.0 * rough[f]
fa = (nb == FARM) & south
hn[fa] = 3.5 + 5.0 * ramp[fa] + 1.0 * rough[fa]
bd = (nb == BADLANDS) & south
hn[bd] = 7.0 + 14.0 * ramp[bd] + 3.0 * rough[bd]
hn += 14.0 * np.exp(-(((wx - 330) ** 2 + (wz - 520) ** 2) / (2 * 55.0 ** 2))) * bd         # the fort's headland
hn = np.maximum(hn, 1.0)
nh[new_land] = hn[new_land]
# beaches: a sandy rim on the new low coasts (not under cliffs or salt)
rim = new_land & (dist_sea < 7.5) & np.isin(nb, [DUNES, FOREST, FARM])
nb[rim] = BEACH; nh[rim] = np.minimum(nh[rim], 1.8 + 0.6 * ramp[rim])
# water: the shelf deepens with distance from any land, lagoon and lake are shallow basins
dist_land = ndimage.distance_transform_edt(~land) * CELL
sea_h = -1.2 - np.clip(dist_land / 149.0, 0, 1) * 9.0
nh[nb == SEA] = sea_h[nb == SEA]
nh[LAGOON & (nb == LAKE)] = -2.2
# soften the seams between old coast and new land and the new land itself
halo = ndimage.binary_dilation(new_land, iterations=4) & land
sm = ndimage.gaussian_filter(nh, 1.2)
nh = np.where(halo, sm, nh)
# tree density on the new land
nd[nb == MOOR] = 0.15 + 0.25 * np.clip(rough[nb == MOOR] + 0.5, 0, 1)
nd[(nb == FOREST) & south] = 0.55 + 0.3 * rough[(nb == FOREST) & south]
nd[(nb == FARM) & south] = 0.1
nd[np.isin(nb, [DUNES, SALTFLAT, BEACH]) & new_land] = 0.02
nd[(nb == BADLANDS) & south] = 0.25
nd = np.clip(nd, 0, 1)

out = np.zeros((N, N, 3), np.uint8)
out[..., 0] = np.clip((nh + 10.0) / 90.0 * 255.0, 0, 255).astype(np.uint8)
out[..., 1] = nb
out[..., 2] = (nd * 255).astype(np.uint8)
Image.fromarray(out).save(os.path.join(DATA, "island_map.png"))

# ---------------------------------------------------------------- sea depth map for the shader
SEA_SIZE = 1733.0; SN = 578
land_big = np.zeros((SN, SN), bool)
off = int(round((SEA_SIZE - SIZE) / 2 / (SEA_SIZE / (SN - 1))))
scale = (SEA_SIZE / (SN - 1)) / CELL
sj, si = np.mgrid[0:SN, 0:SN]
gi = np.round((si - off) * scale).astype(int); gj = np.round((sj - off) * scale).astype(int)
ok = (gi >= 0) & (gi < N) & (gj >= 0) & (gj < N)
land_big[ok] = land[gj[ok], gi[ok]]
dist_big = ndimage.distance_transform_edt(~land_big) * (SEA_SIZE / (SN - 1))
h_big = -1.2 - np.clip(dist_big / 149.0, 0, 1) * 9.0
sea_map = np.clip((h_big + 10) / 90 * 255, 0, 255).astype(np.uint8)
sea_map[land_big] = 255
Image.fromarray(np.stack([sea_map] * 3, -1)).save(os.path.join(DATA, "sea_depth.png"))

# ---------------------------------------------------------------- meta
meta_path = os.path.join(DATA, "island_meta.json")
meta = json.load(open(meta_path))
ppm = meta["img_w"] / SIZE
def to_px(x, z): return [(x + SIZE / 2) * ppm, z * ppm + meta["img_h"] / 2]
old_islets = [i for i in meta["islets"] if i[2] > 1.0]
# new sea stacks and islets off the new coasts (painting px so Island._px places them)
extra = [(-560, 430, 9), (-535, 520, 6), (-300, 610, 7), (160, 625, 8), (470, 540, 10), (480, 430, 6),
         (-600, -420, 8), (-520, -560, 7), (-380, -615, 6), (-10, -560, 9), (30, -600, 5)]
new_islets = []
for x, z, r in extra:
    i = int((x + SIZE / 2) / CELL); j = int((z + SIZE / 2) / CELL)
    if 0 <= i < N and 0 <= j < N and nb[j, i] == SEA:
        new_islets.append(to_px(x, z) + [r * ppm])
meta.update({"islets": old_islets + new_islets, "px_per_m": ppm, "size": SIZE, "sea_size": SEA_SIZE})
json.dump(meta, open(meta_path, "w"))

# preview
pal = {0: (20, 60, 140), 1: (230, 225, 210), 2: (40, 90, 40), 3: (170, 170, 60), 4: (200, 110, 60), 5: (190, 80, 60),
       6: (240, 220, 170), 7: (60, 130, 190), 8: (235, 210, 150), 9: (120, 90, 110), 10: (245, 245, 240)}
prev = np.zeros((N, N, 3), np.uint8)
for k, c in pal.items(): prev[nb == k] = c
shade = np.clip(0.6 + nh / 90.0, 0.5, 1.3)[..., None]
prev = np.clip(prev * shade, 0, 255).astype(np.uint8)
Image.fromarray(prev).resize((N * 2, N * 2), Image.NEAREST).save("/tmp/island_preview.png")
print("land cells:", int(land.sum()), "of", N * N, "| class counts:", {k: int((nb == k).sum()) for k in range(11)})
print("height range:", float(nh.min()), float(nh.max()), "| islets:", len(meta["islets"]))
