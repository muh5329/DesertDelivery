# Asset research — CC0 / CC-BY sources reachable from this container

Scope: sourced 3D meshes and textures for the stylised-realistic Mediterranean coast
(`BRIEF.md`, `RESEARCH_art.md`). Everything shortlisted is on disk under `/root/assets_pool/`
(589 MB total, licence files alongside). Nothing in `/root/dd` was touched apart from this file.

## 0. TL;DR

| Need | Result | Where |
|---|---|---|
| (c) seamless rock/cliff, gravel road, dry ground | **Solved, CC0, high quality** — 28 ambientCG 1K PBR sets, incl. pale stratified limestone (Rock019/021/023/024) | `/root/assets_pool/ambientcg/` |
| (a) sculpted limestone rock meshes | **Not found** as mid-poly scans. Only stylised low-poly rocks (Quaternius 250–520 tris, Kenney/Babylon ~150–300). Fall back to procedural (§4) + ambientCG limestone textures | `quaternius_stylized_nature/glTF/Rock_Medium_*.gltf` as placeholders |
| (b) pine / olive / cypress / scrub | **Partial.** Quaternius Stylized Nature (CC0): 5 conical pines 1.6–5 k tris, 5 "twisted" broad-crown trees 9–10 k tris (good umbrella-pine / old-olive base after retexture), bushes, grass clumps; 2K bark albedo+normal. ambientCG bark sets. No cypress, no olive, no real leaf atlas → keep procedural cards (§4) | `quaternius_stylized_nature/` |
| (d) pier / boat / lamp / wall props | **Solved-ish.** Quaternius Medieval Village + Fantasy Props (CC0, textured PBR, mid-poly): plaster & stone walls, round-tile roofs, wooden fence, wall lantern, barrels. Kenney Pirate Kit (CC0, low-poly flat colour): row boats, dock platforms, small ship. Kenney Graveyard Kit: stone walls, lightposts | `kenney_aura3d/quaternius/*`, `kenney_aura3d/kenney/*` |
| Procedural tooling | `bpy` 4.4 (Blender as a pip module) installed and verified headless: mesh gen, decimate, glTF export, Cycles CPU render. `friggog/tree-gen` (Weber–Penn trees) verified working through bpy | `pip3 install bpy`, `/root/assets_pool/tree-gen` |

## 1. What is reachable (and what is not)

- `git clone https://github.com/...` and `raw.githubusercontent.com` work for any public repo.
  `api.github.com` is **locked to session repos** (search and `repos/*` both 403) → no repo search;
  everything below was found by guessing names or mining npm indexes.
- **GitHub release assets work** (`github.com/<o>/<r>/releases/download/...` →
  `release-assets.githubusercontent.com`). This is what unlocks ambientCG/Quaternius.
- Blocked: polyhaven, ambientcg.com, quaternius.com, kenney.nl, sketchfab, opengameart, codeload
  zip archives (403), git-LFS `media.githubusercontent.com` (400).
- npm registry search works and was useful for discovery: `@jgengine/assets` (index of CC0 packs
  mirrored on a GitHub release) and `@aura3d/asset-index` (points at a GitHub repo of CC0 GLBs).

## 2. Usable assets (shortlist)

### 2.1 ambientCG PBR materials — CC0 — `/root/assets_pool/ambientcg/<Id>/`

Source: ambientCG (Lennart Demes), CC0 1.0. Mirror used:
`https://github.com/Noisemaker111/jgengine/releases/download/packs/ambientcg-ambientcg-<id>.zip`
(1K-JPG variant; 2K/4K are **not** on the mirror). Every set has `*_Color.jpg`, `*_NormalGL.jpg`,
`*_Roughness.jpg`, `*_Displacement.jpg`, most have `*_AmbientOcclusion.jpg`, plus a sphere preview
`<Id>.png`. All 1024×1024, seamless. Attribution line (not required for CC0, but for `CREDITS.md`):
`"<Id>" by ambientCG (https://ambientcg.com/view?id=<Id>), CC0 1.0`.

Selected (previews in each folder — pick by eye; all of Rock001–025, Rocks001–008, Gravel001–015,
Ground001–025, Grass001–005, Bark001–008, Moss001–002, PavingStones001–025 exist on the mirror if
more are wanted; `_dl/ambientcg_available.txt` has the verified list):

| Id | Look | Use |
|---|---|---|
| **Rock019** | pale cream limestone, strong horizontal bedding | primary cliff-face albedo/normal (triplanar on kit rocks; Terrain3D slope texture) — matches ref strata |
| **Rock021** | pale stratified, yellow-ochre streaks | second cliff variant (macro variation) |
| **Rock023** | grey-white cracked strata (already in project as `rock023_alb_ht`) | keep |
| **Rock024** | pale marbled limestone, subtle | boulders / talus |
| **Rock025** | white blocky limestone slabs | hero arch / stacks |
| **Rock017 / Rock018** | white chalky rounded rock | far stacks, sun-bleached tops |
| **Rock005** | pale granular rock | fallback |
| **Rocks002** | pale limestone rubble | scree / talus apron ground |
| **Rocks007 / Rocks008** | limestone cobbles in dirt | beach edge, under boulders |
| **Gravel009** | fine compacted grey gravel | road crown |
| **Gravel003 / Gravel006** | sandy gravel | road margins |
| **Gravel002 / Gravel015** | coarse gravel | road shoulders, track |
| **Ground004** | dusty pale earth | bench / dry earth (`#b09776` in ref) |
| **Ground006 / Ground009** | dry tan soil | road ruts (colour-map tint) |
| **Ground025** | sandy soil with tyre-track imprint | dirt road |
| **Ground012** | pale grey dry dirt | between scrub |
| **Ground015 / Ground024** | dry straw / dead grass litter | dry-grass patches (the ref's `#a89660`) |
| **Ground022** | pale pebbly dirt | beach-side ground |
| **Grass004** | greenest that is still yellowish | only if a lawn is needed (probably not) |
| **Bark001** | deep-fissured grey bark | old olive / stone pine trunk |
| **Bark007** | plated pale bark | stone pine trunk |
| **Bark003** | smooth tan bark | young trees |

Terrain3D packing note: Terrain3D wants `albedo+height` and `normal+roughness` (see existing
`assets/terrain/*_alb_ht.png` / `*_nrm_rgh.png`); a 10-line PIL script packs
Displacement→A of Color, Roughness→A of NormalGL.

### 2.2 Quaternius "Stylized Nature MegaKit" (free tier) — CC0 — `/root/assets_pool/quaternius_stylized_nature/`

Source: Quaternius, CC0 1.0 (`License_Standard.txt` in folder). Mirror: same jgengine release,
`quaternius-quaternius-stylized-nature.zip`. Formats: `glTF/*.gltf`+`.bin`, `FBX/`, `OBJ/`,
textures in `Textures/` (2048² bark albedo+normal, 1024–2048² leaf atlases with alpha; leaf colour
comes from `*_C.png` gradient maps so recolouring to the ref's dark desaturated greens is trivial).
Attribution: `Stylized Nature MegaKit by Quaternius (https://quaternius.com), CC0`.

| File (glTF) | tris | size (m) | textures | use |
|---|---|---|---|---|
| `TwistedTree_1..5` | 9.1–10.1 k | 10–13 w × 16–19 h | Bark_TwistedTree (2K alb+nrm), Leaves_TwistedTree(_C) | best **umbrella-pine / ancient-olive base**: gnarled trunk, wide flat-ish crown. Scale ×0.6, swap leaf card colour to `#3a4a36/#6e7d52`, or strip leaf mesh and re-emit our own clumps on the branch tips |
| `Pine_1..5` | 1.6–5.0 k | 4–6 w × 7–10 h | Bark_NormalTree, Leaf_Pine(_C) | conical pines — not umbrella-shaped; usable as far-tier conifers or as branch source for flat-top pine (delete lower tiers, keep the top 2 tiers, widen) |
| `CommonTree_1..5` | 3.2–6.3 k | 4 w × 7–9 h | Bark_NormalTree, Leaves_NormalTree | the road-side round deciduous shade tree (§4 of art research) |
| `Bush_Common`, `Bush_Common_Flowers` | 900 / 1.4 k | 1.9 × 1.6 | leaf atlas | scrub domes (recolour) |
| `DeadTree_1..5` | 5.6–6.6 k | 6–8 w × 9–16 h | Bark_DeadTree (2K alb+nrm) | dead/olive-like bare trunks, ledge snags |
| `Rock_Medium_1..3` | 244–522 | 3.0–3.4 × 1.9–2.3 | Rocks_Diffuse 2K (green-grey) | **stylised blocky boulders** — faceted, bedded look actually close to the brief's "block" language; re-texture with Rock019 triplanar + vertex AO. Too low-poly for close-ups |
| `Pebble_Round/Square_*` | 48–136 | 0.3–0.5 | PathRocks_Diffuse | beach pebbles |
| `RockPath_*` | 0.6–3.5 k | 1–2 | PathRocks_Diffuse | flagstone patches for courtyards |
| `Grass_Common/Wispy_*` | 155–622 | 0.6–1.5 | Grass.png 512 | dry-grass tufts (recolour to straw) |
| `Fern_1`, `Plant_1/7`, `Clover`, `Flower_*`, `Mushroom_*`, `Petal_*` | tiny | | | villa garden only |

The paid tier has the big stratified sandstone formations seen in `Preview_3.jpg`; not available.

### 2.3 Quaternius "Medieval Village MegaKit" + "Fantasy Props MegaKit" — CC0 — `/root/assets_pool/kenney_aura3d/quaternius/`

Source: Quaternius, CC0 (manifest of the mirror repo `gchahal1982/aura3d-cc0-assets` marks every
file CC0; Quaternius publishes all packs CC0). glTF + `.bin`, shared 2K PBR trims
(`T_Plaster_*`, `T_UnevenBrick_*`, `T_Brick_*`, `T_RoundTiles_*`, `T_WoodTrim_*`, `T_RockTrim_*`,
each BaseColor/Normal/Roughness-or-ORM). 176 + 94 pieces. Mid-poly, textured, reads
**Mediterranean** (plaster walls, terracotta round-tile roofs, uneven stone walls).
Attribution: `Medieval Village MegaKit / Fantasy Props MegaKit by Quaternius, CC0`.

Useful pieces (tris): `Wall_Plaster_Straight` (86), `Wall_Plaster_Window_Wide_Round`,
`Wall_Plaster_Door_Round`, `Wall_UnevenBrick_Straight` (dry-stone look), `Wall_Arch` (196),
`Corner_Exterior_*`, `Roof_RoundTiles_4x6 … 8x14`, `Roof_Dormer_RoundTile`, `Prop_Chimney`,
`Prop_WoodenFence_Single/Extension` (40), `Prop_MetalFence_*`, `Prop_Vine1..9` (wall creepers),
`Prop_Wagon`, `Prop_Crate`; Fantasy props: `Lantern_Wall` (2.8 k), `Torch_Metal`, `Barrel` and
`Barrel_Holder`, `Bucket_Wooden_1`, `Bench`, `Stall_Cart_Empty`, `Vase_*`, `Rope_*`.
Use: house facades / village walls upgrade for `world_kit._add_house`, road-side lanterns, harbour clutter.

### 2.4 Kenney kits — CC0 — `/root/assets_pool/kenney_aura3d/kenney/`

Source: Kenney (kenney.nl), CC0, via `gchahal1982/aura3d-cc0-assets` (GLB, one 512² `colormap.png`
per kit, flat-colour low-poly; tri counts 50–1400). Style is *below* the brief's bar, so treat as
placeholders / distant LOD / shape references:

- `pirate-kit/`: `boat-row-large` (174 tris, 2.7 m), `boat-row-small`, `ship-small` (1.4 k),
  `structure-platform-dock(-small)` (pier modules 2.5 m), `platform-planks`, `structure-fence`,
  `rocks-a/b/c` + `rocks-sand-*` (3.6–5 m boulder clusters, 230–550 tris), `palm-*`.
- `graveyard-kit/`: `stone-wall`, `stone-wall-curve/-column/-damaged` (dry-stone wall run),
  `lightpost-single/double`, `lantern-glass/candle`, `iron-fence-*`, `rocks`, `rocks-tall`.
- `mini-forest/`, `modular-cave-kit/`: fetched but not useful (tiny/blocky).
Attribution: `Kenney (https://kenney.nl), CC0`.

### 2.5 Babylon.js Assets — **CC-BY 4.0** — `/root/assets_pool/babylon_ccby/`

Source: `BabylonJS/Assets` (repo README: CC-BY 4.0 unless a folder says otherwise; the copied
folders have no other licence). Attribution: `Assets from BabylonJS/Assets
(https://github.com/BabylonJS/Assets), CC BY 4.0`. Clearly marked as CC-BY.

- `villagePack/` GLBs (embedded PNG textures): `rocks1` (160 tris, 5 m cluster), `rocks2..4`,
  `bush1..5`, `tree1..4` (240–1084 tris, 7–10 m round trees), `wall`, `wallArch`, `wallCorner`,
  `lightPost1..3`, `fence`, `stump`, `hollowLog`. Low-poly stylised, less useful than Quaternius.
- `textures/`: `rockyGround_basecolor/normal/metalRough.png` 1024² (tan rocky soil — decent
  bench ground), `rock.png`+`rockn.png` 512², `sand.jpg` 894², `dirt.jpg` 1024², `grass.jpg` 1024²,
  `waterbump.png` 256² (water normal), `waterFoam_circular_mask.png` 2048² (foam ring sprite for
  the rock-foam idea in RESEARCH_art §5.2), `stoneso.png` 2048².
- `underwaterSceneRocksBarnaclesMussels.glb` + `rocks/rockMat1|2` textures: one 100 k-tri sculpted
  rock formation (11 m) and a 31 k one (7 m) — the only *sculpted* rocks found. Underwater
  colouring, needs decimation and re-texture; last resort only.
- NOT taken: `meshes/Trees/Broadleaf_Desktop_*` — these are SpeedTree sample atlases, licence
  unclear despite repo CC-BY.

### 2.6 Godot demo projects — MIT — `/root/assets_pool/godot_demo_mit/material_testers_test_materials/`

`godotengine/godot-demo-projects` is MIT (whole repo; no per-file notice for these). 1024²
`sand_albedo/normal/rough`, `rock_albedo/ao/depth/rough` (red sandstone — wrong colour),
`texture_rock_*` 1024×666 (grey rock with normal). Marginal; sand set is the only one worth using.

### 2.7 Already in the project (for completeness)

`assets/terrain/` has ambientCG Ground037 / Rock023 (+ project-made clay/dirt/salt/sand/soil);
`demo/assets/models/RockA/B/C.glb` (Terrain3D demo, MIT, 250–290 tris, 5–14 m) are the low-poly
rocks the art research complains about.

## 3. Nothing found for X → fall back to procedural

1. **Mid-poly sculpted limestone blocks / arch / stacks with baked textures.** No CC0 scan mirror
   on GitHub is reachable (Poly Haven models are not mirrored anywhere found; Sketchfab blocked).
   → Do the block kit procedurally as RESEARCH_art §1.1 describes (box + bedding + joints + noise),
   now textured with **Rock019/021/025** triplanar and vertex-AO. `bpy` is available if we want
   to do it in Blender instead of GDScript (boolean cuts, bevel, decimate, bake AO to vertex
   colour, export glb). Quaternius `Rock_Medium_*` / Kenney `rocks-*` only as shape references.
2. **Umbrella pine, olive, cypress meshes.** None. → Use Quaternius `TwistedTree_*` as the
   umbrella-pine / old-olive trunk+crown base (retexture, prune), or generate with `tree-gen`
   (GPL tool, output unrestricted): presets `small_pine`, `black_oak`, `douglas_fir`, `palm`,
   `lombardy_poplar` (≈ cypress silhouette). Verified: `small_pine` generates in 2.5 s but yields
   288 k leaf tris — must lower `leaf_blos_num`/curve resolution and bake to crossed cards.
   Cypress stays the existing card tier.
3. **Real leaf/needle atlases (pine needle clusters, olive leaves, scrub).** Quaternius atlases are
   flat stylised silhouettes; ambientCG has no foliage. → keep `world/mapgen/foliage.py` cards,
   just recolour + baked gradient per RESEARCH_art §4.1.
4. **Dry Mediterranean grass texture.** ambientCG Grass001–005 are all lush green. → Ground015 /
   Ground024 (dead-grass litter) tinted, or desaturate/yellow-shift Grass004.
5. **Tyre-rut road decal.** None. → Ground025 (has track imprints) plus the colour-map rut stripes.
6. **Water / foam textures.** No CC0 water normal found except Babylon `waterbump.png` (CC-BY,
   256²); generate normal maps procedurally (FastNoise in Godot) as planned; the CC-BY foam-ring
   mask can be used or regenerated in PIL.
7. **HDRI / sky.** Not needed (procedural sky), but `pmndrs/assets` (npm `@pmndrs/assets`) and
   Godot demos ship CC0 Poly Haven HDRIs if ever wanted.

## 4. Tooling notes

- `pip3 install bpy` (4.4.0, 369 MB wheel) works with `numpy<2`; headless `import bpy`, mesh
  ops, Cycles CPU render, glTF/FBX/OBJ import-export all verified. Helper scripts:
  `/root/assets_pool/_tools/meshinfo.py <file|dir>` (tri/vert/bbox/textures via trimesh),
  `/root/assets_pool/_tools/render_sheet.py out.jpg files…` (Cycles contact sheet, ~1 s/thumb).
- `trimesh`, `pillow`, `pygltflib` installed.
- `/root/assets_pool/_ls.sh owner/repo` lists a repo's file tree without downloading blobs.

## 5. Repos checked and rejected

| Repo | Why |
|---|---|
| `Unity-Technologies/BoatAttack` (palms, cliffs, boats, jetty) | Unity Companion License — not CC |
| `Unity-Technologies/TerrainToolSamples` | UCL |
| `KhronosGroup/glTF-Sample-Assets`, `glTF-Sample-Models` | no nature content (Sponza is CC-BY 3.0, wrong subject) |
| `KhronosGroup/Vulkan-Samples-Assets` | `rock.gltf` 205 verts, terrain Apache — trivial |
| `SaschaWillems/Vulkan-Assets` | unclear licences, no rocks |
| `gkjohnson/3d-demo-data` | "not intended for general distribution" |
| `mrdoob/three.js`, `aframevr/sample-assets`, `bevyengine/bevy`, `google/model-viewer`, `pmndrs/assets`, `armory3d/armory_examples` | no rocks/trees; texture provenance unclear |
| `OGRECave/ogre` Samples/Media | old textures of unknown origin; the ambientCG ones there are the same Rock020/Ground037 |
| `TokisanGames/Terrain3D`, `Zylann/godot_heightmap_plugin`, `dreadpon/godot_spatial_gardener`, `godotengine/tps-demo`, `Calinou/godot-sponza`, Kenney starter kits | nothing beyond what the project already has |
| `pmndrs/market-assets` | Kenney low-poly + ambientCG Rock020/Grass001 (superseded by the full ambientCG mirror) |
| `KayKit-Game-Assets/*` (CC0, GitHub) | exists and clonable, but flat low-poly hex/dungeon style — not fetched |
