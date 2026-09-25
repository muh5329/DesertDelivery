# 0013 — One clock lights the world; lamps glow everywhere but light only near the camera; quality is a preset

**Status:** accepted · September 2026

## Context

The review (M-12) found night to be the day with the brightness turned down: `IslandLife` lowered
the sun, the ambient and the sky's `daylight` and nothing else followed. Half the materials fake
their own light — the leaf shader's olive ambient floor, the arch kit's and the rocks' sky fill,
the forest floor's bounce, the sea's own fog and horizon (it rebuilds the sky's horizon colour so
the far sea meets the sky), the far silhouettes' flat vertex colour — so the sea horizon, the
canopies and the distant towns stayed day-bright under a dark sky. Lamps were constant emission
(lit at noon) and cast no light; there was no moon, no stars, no dusk.

The same review (m-16) asked for a way to trade quality for frame rate on the target Mac (an M4
Pro at a Retina backbuffer), where the Forward+ stack (SSAO, SSIL, volumetric fog, four cascades)
had no fallback.

## Decision

**One clock, one state, pushed everywhere.** `DayNight` (world/sky, a child of the Environment)
takes the hour from `IslandLife` and computes the sun and a full moon on the celestial sphere
(latitude 45.7°, declination 10°, late summer: sunrise ~6:19, sunset ~19:41). The two angles are
chosen so that at `DayNight.REFERENCE_HOUR` (14:44) the sun stands exactly where the art passes put
it (`Atmosphere.sun_elevation_deg` 48°, `sun_yaw_deg` -40°): the reference look is that afternoon,
and `tests/view.gd` (the `reference/compare.py` renders) pins that hour. Every look value is a key frame by the
*sun's elevation* (night, blue hour, sunset, golden hour, day = `WorldKit.Atmosphere` unchanged),
so dawn and dusk share one palette and the day look the art passes tuned is untouched. The state
goes to:

- the one `DirectionalLight3D`: the sun by day, the moon by night. It swaps while the sun is below
  the horizon and its energy is zero, so one shadow map serves both and the swap never shows;
- the sky shader: gradient, sun disc (as uniforms, not `LIGHT0`, which is the moon at night),
  glow lobes, the moon's disc and halo, stars (fixed to the celestial sphere, turning with the
  hour; no `TIME`, so the radiance map is re-filtered only when the sky is pushed, every ~2 game
  minutes), cloud colours;
- the environment: ambient, fog colour and sun scatter, exposure (a little eye adaptation at night);
- the sea's own fog and horizon colours, and its glints (the moon's path at night);
- **global shader uniforms** (project.godot `[shader_globals]`): `dn_fill` scales every fill a
  material fakes (leaf floor, arch and rock sky fill, forest-floor bounce, sea foam, far
  silhouettes, bark), `dn_night`, `dn_lamps` (street lamps on), `dn_windows` (share of windows
  lit, by the hour) and `dn_sun_dir`. A material that fakes light reads these; nothing has to
  find and update it.

**Lamps glow everywhere; light comes from a pool.** Lamp glass is emissive by `dn_lamps` in every
lamp material (`NightLights.bulb_material()`, the arch kit's warm-tinted glass: lanterns, plaza
lamps, lighthouse lanterns). Only the nearest lamps cast light: `NightLights` keeps a pool of
OmniLight3Ds (the preset's budget, 4-20) and moves them onto the nearest registered lamp positions
(nodes in the group `night_lights` with a `night_lights` meta — street lamps, bridge lamps, core
lamp posts, the kit's lanterns) at 4 Hz, easing each in and out. A streamed chunk takes its lamps
with it (group membership ends with the node). Windows light by instance (the arch shader hashes
the window module's instance origin against `dn_windows`); far silhouettes draw a window grid
that averages to a glow once a window is under ~2 px. Lighthouse beams are resident (seen across
the bay before the chunk streams in) and turn on the GPU. The courier's bike and truck carry a
SpotLight3D headlight; traffic carries a Decal whose emission lays a pool of light on the road
(no light per car). Camp fires flicker and widen after dark.

**Quality is a preset.** `GraphicsSettings` (core/settings) holds Low / Medium / High / Ultra —
SSAO / SSIL / volumetric fog and their quality, cascades, shadow distance and atlas, soft-shadow
quality, anti-aliasing (FXAA; TAA; FSR 2 on a Retina screen; TAA + MSAA 2x with alpha-to-coverage
foliage at Ultra), mesh LOD bias, anisotropy and the lamp-light budget — applied at boot and from
the F10 menu (`GraphicsMenu`), saved in `user://graphics.cfg`, `--quality=` for one run. High is
the default, tuned for the M4 Pro at a Retina window.

## Consequences

- A new material that fakes light must multiply its fill by `dn_fill` (and a glowing one by
  `dn_lamps` or `dn_night`), or it will glow at night. The globals must exist in project.godot or
  the shader fails to compile.
- Real light is budgeted: a street far from the camera glows but lights nothing. The pool's
  budget is the only knob; shadows from lamps are off (the headlight's are a preset).
- The sun no longer sits at the reference's fixed yaw except at 14:44 (REFERENCE_HOUR); the
  morning light comes from the east. Reference comparisons must pin that hour (view.gd does).
- DayNight owns the Environment's ambient, fog colour, exposure and the sky's colours: tune the
  day look in `WorldKit.Atmosphere`, the rest in `DayNight.KEYS`.

## Reopen if

- A dynamic weather system arrives (clouds, rain): it becomes a second input to the same state.
- The moon should have phases (the moon direction is the sun's, 12 h later; a phase would move it).
- Lamps need shadows, or many more real lights (a clustered budget per area rather than per camera).
