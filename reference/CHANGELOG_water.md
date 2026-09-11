# water branch — sea and lake surface

## What changed
- `world/kit/sea.gdshader` (new): the Compatibility water recipe from `RESEARCH_tech.md` §3, extended.
  - Vertical depth from `hint_depth_texture` (works with the project's MSAA 4x — verified with
    `--debugsea=3`), so colour bands and foam hug every rock, stack, boat and shoreline.
  - Far fallback: the island height map (`data/sea_depth.png`, the old shelf-depth logic) takes over
    beyond 350–600 m or where the depth buffer holds the far plane.
  - Bands by depth (the seabed near the coast is only 1–4 m deep, so they are compressed):
    wet-sand → turquoise (0.5 m) → mid (1.6 m) → navy (3.8 m). Albedos are ~0.5x of the target
    output because the sun + blue sky ambient + ACES lift them ~2x.
  - Shoreline / rock-ring foam from depth + two scrolling noises, sparse whitecaps in deeper water.
  - Two scrolling normal maps (0.9 m chop, 7 m swell) fading with distance, small sparkle term.
  - Fresnel sky reflection tinted by the environment's `fog_light_color` (darkened 20 %) and sky
    top colour, read from the WorldEnvironment in `sink` at build time — no environment file touched.
  - Refracted seabed through `hint_screen_texture` (offset by the wave normal, rejected where the
    offset pixel is above the surface); the shader does its own bed/water blend with ALPHA 1.
  - Engine specular lowered (SPECULAR 0.3, roughness 0.16 → 0.4 far) so the horizon is not a mirror.
- `world/kit/world_kit.gd`: `_build_sea` loads the shader, builds the noise/normal textures
  synchronously (`_noise_texture`), passes sky/fog colours, abyss plane now uses `SEA_NAVY`
  (= the shader's deep band) at −14 m.
- `tests/view.gd`: `--debugsea=N` (1 depth, 2 screen texture, 3 buffer depth, 4 fallback weight).
- `reference/spots.json`: added a `lake` spot (badlands lake, LAKE biome at −2..−3 m).

## Measured (compare.py vs ref_cliff_coast.png)
- cliff_coast_b: 0.335 → 0.353 (colour 0.130 → 0.155). cliff_coast: 0.290 → 0.293 (little water in frame).
- Sampled render pixels, cliff_coast_b: deep body (26,49,88) vs reference navy (40,59,95); rock ring
  turquoise/green and cream foam present; harbour boats and jetties get their own foam rings; the
  lake reads as a blue pool with a foam edge and turquoise shallows.
- World generation 5.9–7.1 s (< 20 s); architecture / feature / edge tests pass.

## Still missing / open
- Mid-distance sea is still bluer and brighter than the reference (52,96,148 vs ~52,70,100): the
  saturated blue sky ambient and the light fog colour of the current environment dominate; the
  environment branch's hazy sky/fog should pull it the rest of the way (sky colours are read at
  build time, so it follows automatically).
- Far horizon fades to the fog colour (engine fog) — also an environment-branch matter.
- No trailing foam streaks in the swell direction, no wave vertex displacement (optional item).
- Lake shore uses the same surf-style foam ring as the sea (slightly too lively for still water).
