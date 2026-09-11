"""Erodes the Quaternius leaf atlases (assets/trees/Leaves_TwistedTree_C.png, Leaf_Pine_C.png).
The pack's leaf lobes are smooth solid blobs, so a canopy of them renders as a filled silhouette
with a hard 1-px rim (round 4 critique item 5: the big tree's texture-energy cells sit -74/-70
under the reference). Only the alpha is used by the leaf shader, and this bites a ragged
2-22 px edge into every lobe and punches 3-8 px holes inside it, so the silhouette breaks up
into leaves again at the card's own scale and the mip chain thins toward the rim.
Sources: world/mapgen/leafsrc/ (the untouched pack textures, ignored by the importer).
Run from the project root:  python3 world/mapgen/leaf_erode.py
"""
from PIL import Image
import numpy as np, os
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "world", "mapgen", "leafsrc")
OUT = os.path.join(ROOT, "assets", "trees")
rng = np.random.default_rng(11)


def noise(shape, scale):
    """Blurred white noise normalised to 0..1 (a cheap blotchy field of ~`scale` px features)."""
    n = ndimage.gaussian_filter(rng.standard_normal(shape), scale)
    n -= n.min(); n /= max(n.max(), 1e-6)
    return n


def erode(name, bite=(3.0, 12.0), hole_frac=0.06):
    img = Image.open(os.path.join(SRC, name)).convert("RGBA")
    arr = np.asarray(img).copy()
    a = arr[..., 3] > 128
    dist = ndimage.distance_transform_edt(a)             # px to the nearest transparent pixel
    n1 = noise(a.shape, 7.0)                             # ~14 px blotches: the bite depth along the rim
    thr = bite[0] + (bite[1] - bite[0]) * n1
    keep = dist > thr
    # holes: the top `hole_frac` of a finer field, only well inside a lobe (never a second rim)
    n2 = noise(a.shape, 3.0)
    hole = (n2 > np.quantile(n2, 1.0 - hole_frac)) & (dist > 4.0)
    keep &= ~hole
    arr[..., 3] = np.where(keep, 255, 0).astype(np.uint8)
    before = a.mean(); after = keep.mean()
    Image.fromarray(arr, "RGBA").save(os.path.join(OUT, name))
    print("eroded", name, "coverage %.3f -> %.3f" % (before, after))


erode("Leaves_TwistedTree_C.png", bite=(2.0, 22.0), hole_frac=0.08)
erode("Leaf_Pine_C.png", bite=(2.0, 16.0), hole_frac=0.08)
