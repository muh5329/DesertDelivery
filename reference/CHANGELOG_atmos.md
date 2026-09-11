# atmos branch — atmosphere, lighting, post

## What changed
- `world/kit/world_kit.gd`: new `Atmosphere` const dictionary at the top (sky/sun/ambient/fog/grade/
  vignette tunables, sRGB colours sampled from `ref_cliff_coast.png`), `_build_environment` rewritten
  around it, plus `_cloud_cover_texture()` (equirectangular noise mask for `ProceduralSkyMaterial.sky_cover`,
  alpha faded to 0 in the last ~2 deg above the horizon because the cameras look down and only see the
  lowest ~12 deg of sky) and `_build_vignette()` (CanvasLayer 1 + ColorRect with a `blend_mul` radial
  shader; below the HUD, which is added later).
- `project.godot`: `directional_shadow/size=2048`, `soft_shadow_filter_quality=3` (Soft High, 13-tap PCF).
  `shadow_blur` is a no-op in Compatibility; softness now comes from texel size (2 splits over 260 m).
- Sun: 24 deg elevation, yaw -48 (from camera-left / sea side in both cliff spots), `#ffd6b0` x1.25.
- Ambient: sky 0.7 + lilac `#8a87a0` fill, energy 0.7 -> shadow rock ~V0.41 vs lit ~V0.67.
- Fog: exponential 0.0034 (~40 % at 150 m, ~75 % at 400 m), `fog_light_color #6688b4` x1.18 (aerial
  perspective is a no-op on geometry in Compat, so fog colour == horizon sky), sun scatter 0.22,
  height fog below 6 m (sea mist; NOT distance-scaled, so kept low), `fog_sky_affect 0.15` (it mixes the
  whole sky uniformly toward fog, no vertical falloff — keep it low).
- Sky: top `#7cb4ea`, horizon `#5a82b0`, curve 0.35, energy 1.4 (the grade desaturates and the filmic
  tonemap compresses blue, so inputs are over-saturated on purpose); additive pink-mauve clouds
  (`sky_cover_modulate (0.30,0.15,0.21)` — sky_cover is ADDED to the sky, so the tint must be small).
- Grade: Filmic, exposure 0.82, white 3.5, saturation 0.85, colour-correction ramp `#15171d`->`#f5e9ea`
  (lifted blue blacks, warm-pink whites), glow 0.28, vignette 0.16.

## Measured (compare.py vs ref_cliff_coast.png)
- cliff_coast: 0.290 -> 0.500 (colour 0.097 -> 0.360); cliff_coast_b: 0.335 -> 0.452.
  (Pass 6 with a duller sky scored 0.522; the brighter, bluer zenith of the final pass matches the
  reference's sampled gradient better by eye and by pixel: zenith ref #8ea8c1 S0.26 / ours #8699ac S0.22,
  horizon sky ref #69809c / ours #7992aa, far sea ref #5f7c9f / ours #6d8098.)
- Lit rock #ab9b95 (ref #a78e74), shadow rock #5a5d68 (ref arch shadow #424c62), far village haze
  #a7a1a5 (ref far stack #636a7b — ours is lighter because the village geometry is white).
- World gen 7.2 s; architecture/feature/edge tests pass.

## Still missing / open
- Sea-sky horizon still a small step (~12 levels): the far sea is 100 % fog while the sky just above
  the horizon is brighter; the water pass should make the sea's far colour converge on the fog colour.
- Far haze on land reads lavender-grey rather than the reference's blue (#6b849f); the distant
  geometry is very bright (white houses, pale rocks) so 75 % fog still leaves it light.
- The colour-correction ramp + saturation 0.85 also desaturate the water; the water pass may want to
  compensate in its shader (reference water is the one saturated thing).
- Clouds are additive blobs — good at a glance, but they have no shadowed underside.
