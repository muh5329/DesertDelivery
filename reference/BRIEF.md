# Desert Delivery — fidelity push brief (read this first)

Goal: make the island's level geometry and rendering look like the three reference screenshots in
`reference/` (`ref_cliff_coast.png` is the primary target: stratified pale-limestone sea cliffs with
arches and stacks, boulder fields, a dirt coast road with tyre ruts, scrub bushes and umbrella pines,
turquoise-to-navy water with foam on the rocks, warm low sun, pink-hazed sky, strong aerial
perspective). The look is *stylised-realistic*: painterly but with real texture, AO and soft light —
not low-poly.

## The project (Godot 4.7, GL Compatibility renderer)
- Root: `/root/dd` (a git repo; `main` is the baseline). Work on your own branch, commit small.
- `world/terrain/terrain.gd` — 3 m heightfield (roads, bridges, pads) → Terrain3D (1.5 m mesh,
  control map = textures per biome / rock on slopes / dirt on roads, colour map tints, instancer
  grass). `Terrain.height_at()` etc. are the ground queries everyone uses.
- `world/island/island.gd` — the generator: hubs, places, roads, scatters (props are recipes per
  60 m chunk, streamed). `world/kit/world_kit.gd` — builders (houses, rocks `_add_rock`, foliage
  cards `_tier`, walls, sea shader `_build_sea`, environment `_build_environment`).
- `assets/terrain` (ground textures), `assets/foliage` (leaf/grass cards; `world/mapgen/foliage.py`).
- `addons/terrain_3d` — Terrain3D 1.0.2 (API notes in `reference/terrain3d_notes.md`).
- Docs: `ARCHITECTURE.md`, `CONTEXT.md`, `PROGRESS.md`.

## Constraints
- Renderer stays **GL Compatibility** (the game targets it; Vulkan/lavapipe crashes in this
  container so Forward+ can't be verified here). No SSAO/SDFGI/volumetric fog/SSR: fake AO with
  vertex colours / textures, do reflections in the water shader, use fog + sky for aerial perspective.
- Rendering here is software (llvmpipe): ~25–40 s per 1280×720 frame. Budget your renders.
- Network: GitHub (clone / raw), PyPI and npm are reachable. polyhaven.com, quaternius.com,
  kenney.nl, ambientcg.com are NOT. CC0 assets must come from GitHub mirrors (verify the licence
  file in the repo before using anything; record source + licence in `assets/CREDITS.md`).
- World generation must stay under ~20 s here (`[game] world generated in N ms` in the log);
  props must stay off roads (≥ 6 m from centrelines) and off delivery rings.
- Tests must keep passing: `godot --headless --path . -- --test=architecture_tests`,
  `--test=feature_tests`, `--test=edge_tests`, and the drive `--autotest --deliveries=10 --maxtime=1800`
  (run the long one only at the end of a round).

## Render harness
```
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -- --test=view --spots=NAME[,NAME] --out=/tmp/x
```
`tests/view.gd` reads named camera spots from `reference/spots.json` (`{"name": {"from": [x,y,z], "at": [x,y,z]}}`).
`cliff_coast` is the spot that should end up looking like `ref_cliff_coast.png`; add spots as needed.
Compare with `python3 reference/compare.py /tmp/x/cliff_coast.png reference/ref_cliff_coast.png`
(prints a similarity score and writes a side-by-side to `/tmp/x/compare_*.png`; look at the
side-by-side with the Read tool — the score is only a rough guide).
