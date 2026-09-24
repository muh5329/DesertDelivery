"""Noise and erosion kernels for the outer-world generator (world/mapgen/outer.py).

Everything here is numba-jitted and works on whole grids in world metres:
  perlin2(x, z, seed)          gradient noise, ~[-1, 1]
  fbm(x, z, seed, ...)         fractal sum
  ridged(x, z, seed, ...)      ridged multifractal (sharp crests, 0..1)
  erode_hydraulic(h, ...)      particle (droplet) hydraulic erosion, in place
  erode_thermal(h, ...)        talus-angle thermal erosion, in place
"""
import numpy as np
from numba import njit, prange

@njit(cache=True, inline="always")
def _hash(i, j, seed):
    h = (i * 374761393 + j * 668265263 + seed * 144269504) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return h ^ (h >> 16)


@njit(cache=True, inline="always")
def _grad(h, x, z):
    k = h & 7
    if k == 0: return (x + z) * 0.7071
    if k == 1: return (-x + z) * 0.7071
    if k == 2: return (x - z) * 0.7071
    if k == 3: return (-x - z) * 0.7071
    if k == 4: return x
    if k == 5: return -x
    if k == 6: return z
    return -z


@njit(cache=True)
def perlin_pt(x, z, seed):
    i0 = np.floor(x); j0 = np.floor(z)
    fx = x - i0; fz = z - j0
    i = int(i0); j = int(j0)
    u = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)
    v = fz * fz * fz * (fz * (fz * 6.0 - 15.0) + 10.0)
    n00 = _grad(_hash(i, j, seed), fx, fz)
    n10 = _grad(_hash(i + 1, j, seed), fx - 1.0, fz)
    n01 = _grad(_hash(i, j + 1, seed), fx, fz - 1.0)
    n11 = _grad(_hash(i + 1, j + 1, seed), fx - 1.0, fz - 1.0)
    a = n00 + u * (n10 - n00)
    b = n01 + u * (n11 - n01)
    return (a + v * (b - a)) * 1.41


@njit(cache=True, parallel=True)
def fbm(x, z, seed, wavelength, octaves, gain=0.5, lacunarity=2.0):
    out = np.empty(x.shape)
    fx = x.ravel(); fz = z.ravel(); fo = out.ravel()
    for n in prange(fx.size):
        amp = 1.0; f = 1.0 / wavelength; s = 0.0; tot = 0.0
        for o in range(octaves):
            s += amp * perlin_pt(fx[n] * f, fz[n] * f, seed + o * 1013)
            tot += amp; amp *= gain; f *= lacunarity
        fo[n] = s / tot
    return out


@njit(cache=True, parallel=True)
def ridged(x, z, seed, wavelength, octaves, gain=0.5, lacunarity=2.05, sharp=2.0):
    """Ridged multifractal: each octave 1-|n|, sharpened, weighted by the previous octave."""
    out = np.empty(x.shape)
    fx = x.ravel(); fz = z.ravel(); fo = out.ravel()
    for n in prange(fx.size):
        amp = 1.0; f = 1.0 / wavelength; s = 0.0; tot = 0.0; w = 1.0
        for o in range(octaves):
            r = 1.0 - abs(perlin_pt(fx[n] * f, fz[n] * f, seed + o * 7919))
            r = r ** sharp
            r *= w
            w = min(1.0, max(0.0, r * 1.6))
            s += amp * r; tot += amp; amp *= gain; f *= lacunarity
        fo[n] = s / tot
    return out


@njit(cache=True)
def _bil(h, x, z):
    n0, n1 = h.shape
    i = int(x); j = int(z)
    if i < 0: i = 0
    if j < 0: j = 0
    if i > n1 - 2: i = n1 - 2
    if j > n0 - 2: j = n0 - 2
    u = x - i; v = z - j
    return (h[j, i] * (1 - u) * (1 - v) + h[j, i + 1] * u * (1 - v) + h[j + 1, i] * (1 - u) * v + h[j + 1, i + 1] * u * v)


@njit(cache=True)
def _grad_at(h, x, z):
    n0, n1 = h.shape
    i = int(x); j = int(z)
    u = x - i; v = z - j
    gx = (h[j, i + 1] - h[j, i]) * (1 - v) + (h[j + 1, i + 1] - h[j + 1, i]) * v
    gz = (h[j + 1, i] - h[j, i]) * (1 - u) + (h[j + 1, i + 1] - h[j, i + 1]) * u
    return gx, gz


@njit(cache=True)
def erode_hydraulic(h, mask, droplets, seed, cell, radius=2, inertia=0.08, capacity=6.0, min_slope=0.004,
                    erode=0.35, deposit=0.25, evaporate=0.02, gravity=4.0, max_steps=90, sea=0.0):
    """Particle erosion (after H. Beyer / S. Lague). `h` in metres on a grid of `cell` metres;
    `mask` (0..1) scales erosion (0 = protected). Sediment capacity is in metres of height."""
    np.random.seed(seed)
    n0, n1 = h.shape
    # erosion brush
    offs = []
    ws = []
    tot = 0.0
    for dj in range(-radius, radius + 1):
        for di in range(-radius, radius + 1):
            d = np.sqrt(di * di + dj * dj)
            if d <= radius:
                w = 1.0 - d / (radius + 0.5)
                offs.append((di, dj)); ws.append(w); tot += w
    nb = len(offs)
    bi = np.empty(nb, np.int64); bj = np.empty(nb, np.int64); bw = np.empty(nb)
    for k in range(nb):
        bi[k] = offs[k][0]; bj[k] = offs[k][1]; bw[k] = ws[k] / tot
    for d in range(droplets):
        x = np.random.random() * (n1 - 3) + 1
        z = np.random.random() * (n0 - 3) + 1
        if _bil(h, x, z) < sea + 2.0:
            continue
        dx = 0.0; dz = 0.0; speed = 1.0; water = 1.0; sed = 0.0
        for step in range(max_steps):
            i = int(x); j = int(z)
            u = x - i; v = z - j
            hold = _bil(h, x, z)
            gx, gz = _grad_at(h, x, z)
            dx = dx * inertia - gx * (1 - inertia)
            dz = dz * inertia - gz * (1 - inertia)
            l = np.sqrt(dx * dx + dz * dz)
            if l < 1e-9:
                break
            dx /= l; dz /= l
            nx = x + dx; nz = z + dz
            if nx < 1 or nz < 1 or nx > n1 - 3 or nz > n0 - 3:
                break
            hnew = _bil(h, nx, nz)
            dh = hnew - hold
            slope = max(-dh / cell, min_slope)
            cap = slope * speed * water * capacity
            m = mask[j, i]
            if sed > cap or dh > 0:
                # deposit (fill the pit when climbing)
                amt = min(dh, sed) if dh > 0 else (sed - cap) * deposit
                sed -= amt
                h[j, i] += amt * (1 - u) * (1 - v)
                h[j, i + 1] += amt * u * (1 - v)
                h[j + 1, i] += amt * (1 - u) * v
                h[j + 1, i + 1] += amt * u * v
            else:
                amt = min((cap - sed) * erode, -dh) * m
                for k in range(nb):
                    ii = i + bi[k]; jj = j + bj[k]
                    if ii < 0 or jj < 0 or ii >= n1 or jj >= n0:
                        continue
                    e = amt * bw[k]
                    h[jj, ii] -= e
                sed += amt
            if hnew < sea - 1.0:
                break
            speed = np.sqrt(max(speed * speed + dh * -gravity / cell * 10.0, 0.01))
            water *= (1 - evaporate)
            x = nx; z = nz


@njit(cache=True)
def erode_thermal(h, mask, iterations, talus, rate=0.5):
    """Material above the talus height difference (per cell) slides to the lowest neighbour."""
    n0, n1 = h.shape
    for it in range(iterations):
        for j in range(1, n0 - 1):
            for i in range(1, n1 - 1):
                hc = h[j, i]
                best = 0.0; bi = 0; bj = 0
                for dj in range(-1, 2):
                    for di in range(-1, 2):
                        if di == 0 and dj == 0:
                            continue
                        f = 1.0 if (di == 0 or dj == 0) else 1.4142
                        d = (hc - h[j + dj, i + di]) / f
                        if d > best:
                            best = d; bi = di; bj = dj
                if best > talus:
                    mv = (best - talus) * 0.5 * rate * mask[j, i]
                    h[j, i] -= mv
                    h[j + bj, i + bi] += mv


@njit(cache=True, parallel=True)
def point_noise(px, pz, seed, wavelength, octaves):
    out = np.empty(px.size)
    for n in prange(px.size):
        amp = 1.0; f = 1.0 / wavelength; s = 0.0; tot = 0.0
        for o in range(octaves):
            s += amp * perlin_pt(px[n] * f, pz[n] * f, seed + o * 1013)
            tot += amp; amp *= 0.5; f *= 2.0
        out[n] = s / tot
    return out
