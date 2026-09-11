# r1_look — round-1 LOOK lane (critique items 2, 7, 11, sun half of 1, camera of 4)

## What changed
- `reference/spots.json`: `cliff_coast` is now the critic's proposal `from [-592,38,-322] -> at [-522,5,-200]`
  (hangs over the inlet mouth, faces SE): land LEFT, sea RIGHT, the west wall runs lower-left to
  upper-centre, stacks in the right third, far coast in haze. The north-wall end takes ~15 % of the
  left edge (the reference's foreground cliff) — not blocked, kept as proposed.
- `world/kit/world_kit.gd` `Atmosphere`:
  - sun yaw -48 -> **-62** (light rakes along the west walls at ~60 deg: west faces ~cos 60, top faces lit,
    N joints in shadow); elevation unchanged 24.
  - ambient energy 0.7 -> **0.34**, sky contribution 0.7 -> 0.5 (shadow faces now fall well below lit).
  - fog: colour `#6688b4` x1.18 -> **`#6b84a0` x1.05** (below the sky, not above it), density 0.0034 -> **0.003**
    (36 % at 150 m, 70 % at 400 m), height fog 6 m/0.035 -> **2 m/0.012** (no second haze over rocks/water).
  - grade: exposure 0.82 -> **0.68**, contrast 1.0 -> **1.22**, saturation 0.85 -> **1.0**, lift_black `#15171d` -> `#0e1016`.
  - sky: top `#7cb4ea` -> `#9cb2d8`, horizon `#5a82b0` -> `#6a8bb6` (with the grade no longer desaturating,
    the old inputs rendered a saturated blue sky; measured now: zenith `#98a8c4` S0.22 vs ref `#a2abc4` S0.17,
    horizon `#809aba` vs ref `#809cb7`).
  - clouds (`_cloud_cover_texture`): 2-octave noise generated at quarter width and stretched 4:1, threshold
    ramp 0.30 wide, cover 0.5, tint (0.22,0.12,0.18), thinner toward the zenith: soft stratus smears, no
    cauliflower lobes.
- `_build_sea`: `world_size` read from `island_meta.json.sea_size` (1733, was hard-coded 1000 — the far
  fallback depth was read 0.58x too close to the origin); sun direction + colour passed to the shader;
  sea `sky_horizon` = fog colour (the 20 % darkening left a step between far sea and sky).
- `world/kit/sea.gdshader`:
  - bands: navy `(0.065,0.10,0.165)` (lit ~`#2a3d5e`), `band_mid 1.6 -> 2.5`, `band_navy 3.8 -> 6`, shallow
    colour darkened (the bright sand shallow was the "bathtub ring"), turquoise less green.
  - foam: `foam_depth 0.9 -> 1.6`, ring x 1.5 m clump noise, solid in the last 25 cm, trailing streaks
    along `wave_a_dir` (noise squeezed 1:6, cubic falloff from the rock foot), whitecaps on a normalised
    noise (the old threshold 0.9 was above the noise's 0.3..0.7 range and never fired), `EMISSION` so the
    foam clips to cream regardless of sun/ambient.
  - glints: Blinn lobe (pow 180) toward the real sun, broken by the foam noise; `wave_strength 0.6`,
    `sparkle 0.9`, roughness 0.10. (Glints show in the harbour spot; in the three cliff spots the sun is
    behind the camera, so its mirror is out of frame — correct, not a bug.)
  - **seam fix**: the depth buffer is trusted only for vertical depth < 4..7 m; deeper hits are the
    Terrain3D sea rim (-10.5 m past +-624) or the abyss (-14 m past +-768) and drew a straight line in
    the sea; the height map takes over there. `far_w` (distance) and `map_w` (depth source) are now
    separate so roughness/foam/glint fades do not redraw the seam.
- `project.godot`: unchanged (2048 shadow map / soft-high PCF were already right).

## Measured (PIL, 96 % crop; ref cliff: p1 0.10, std 0.17, S 0.29)
| | r0 | now |
|---|---|---|
| cliff_coast (new camera) compare | 0.514 | **0.543** (colour 0.370 -> 0.424) |
| cliff_coast_b | 0.472 | **0.513** |
| cliff_arch | 0.515 | **0.546** |
| cliff_coast p1 / std / S | 0.29 / 0.11 / 0.21 | **0.16 / 0.16 / 0.28** |
| cliff_coast_b p1 / std / S | 0.34 / 0.11 / 0.19 | **0.22 / 0.16 / 0.25** |
| cliff_arch p1 / std / S | 0.34 / 0.11 / 0.19 | **0.20 / 0.17 / 0.24** |
| villa p1 / S (ref 0.08 / 0.35) | 0.25 / 0.19 | **0.11 / 0.30** |
- Stack at 200 m (cliff_coast_b) `#5d718c` (target no lighter than `#68788e`).
- Best pass by score was p3 (0.553/0.513/0.549) with ambient 0.38; the final darker pass trades 0.01 of
  score for lower blacks (p1 0.20 -> 0.16 on cliff_coast) and the seam fix.
- World gen 8.6–9.5 s; architecture / feature / edge tests pass.

## Still missing / open
- p1 luminance 0.16–0.22 vs target ≤ 0.14: what is dark in the reference is scrub, boulder contacts and
  warm shadow rock; our rocks are still neutral grey and the bushes pale (ROCKS/GROUND). Pushing ambient
  lower than 0.34 starts crushing the wall's shadow side below the reference's V0.43.
- Far coast at 400–500 m still reads neutral light grey (`#7c7c7e`) rather than blue: 70 % fog over
  white rock/houses. Fog cannot fix bright geometry; it needs the rock/ground darkening.
- Foam rings are still a uniform-width band in front of every rock (a limit of depth-buffer foam at
  grazing angles); the streaks are short. No wave displacement.
- The Terrain3D seabed steps from -5 m to -10.5 m at +-624 (terrain lane); the sea hides it now, but the
  step is visible from underwater/debug views.
