# Desert Delivery — architecture

The one rule: **gameplay systems never care whether a piece of the world is currently loaded.**
The scene tree is a temporary visualisation of authoritative state that lives elsewhere — the
`WorldDatabase`, the `EntityManager`, the definitions in `data/`, and the save file.

## Folders (feature-based, not by file type)

```
res://
├── core/                    application infrastructure — the only globals live here
│   ├── app/                 game.gd (root, boot + wiring), game.tscn (main scene), game_state.gd, cli_args.gd
│   ├── events/              event_bus.gd  → autoload `Events`
│   ├── save/                save_manager.gd → autoload `Saves`
│   ├── settings/            graphics_settings.gd (quality presets, user://graphics.cfg)
│   ├── definitions/         definition.gd (base Resource: id + display_name)
│   └── utils/               materials.gd (Mats: primitive mesh + material helpers)
├── world/
│   ├── world_manager.gd     owns terrain / environment / database / streamer
│   ├── world_config.gd      WorldConfig resource (chunk size, stream radius, tier radii, seed)
│   ├── database/            world_database.gd (recipes per chunk, locations, hubs), hub.gd
│   ├── streaming/           world_streamer.gd, chunk.gd
│   ├── terrain/             terrain.gd (map-driven heightfield, roads, bridges, viaducts -> Terrain3D), bridge.gd
│   ├── sky/                 day_night.gd (DayNight: sun, moon, sky, fog, the dn_* shader globals), night_lights.gd
│   │                        (lamp-light pool, bulb glass), lighthouse_beam.gd, vehicle_lights.gd, campfire_glow.gd
│   ├── outer/               the 25 km outer world (ADR 0010): outer_world.gd (OuterWorld: queries + collision),
│   │                        outer_ground.gd (the lattice surface), outer_terrain_view.gd + .gdshader (CDLOD),
│   │                        outer_roads.gd (network, ribbons, masonry / concrete bridges, road furniture),
│   │                        outer_towns.gd (towns, plots, landmarks), outer_props.gd (town dressing, quay walls,
│   │                        terrace walls), outer_flora.gd (wilderness, fields), outer_rivers.gd + river.gdshader
│   ├── kit/                 world_kit.gd (every builder: houses, rocks, kits, arcades, sea, sky),
│   │                        building_kit.gd (BuildingKit: plots -> buildings, per-town styles) + building/
│   │                        (ArchStyles plans, ArchFacade walls/openings/roofs, ArchModules instanced pieces,
│   │                        ArchSpecial towers/churches/walls/gates, ArchMaterials + arch.gdshader, ArchMesh)
│   ├── island/              island.gd (the generator for THIS island: hubs, places, roads, biomes)
│   ├── life/                IslandLife (the 64 residents, drivers, the clock), Resident, ResidentActor, ViewPool,
│   │                        RoadNavigation, CharacterLook, IslandWildlife; the outer world's life (ADR 0012):
│   │                        OuterLife -> TownFolk (TownPopulation per town: spots, walking graph, people;
│   │                        Townsperson records; pooled TownBody views), OuterTraffic + TrafficModels,
│   │                        OuterBoats
│   └── mapgen/              extract.py (painting → 720 m map), expand.py (→ 1248 m world + new land), textures.py,
│                            outer.py (+ outer_*.py: the outer world → data/outer; outer_water.py rivers, wadis,
│                            erg, oases; outer_props.py town dressing), outer_textures.py,
│                            facades.py (the architecture kit's PBR layers → assets/buildings),
│                            trees.py + tree_bark.py (the Quaternius trees' leaf cards + procedural bark tubes),
│                            tree_impostors.py (their far impostors → assets/trees/impostors), foliage.py
├── assets/terrain/          ground textures for Terrain3D
├── addons/terrain_3d/       the Terrain3D GDExtension (rendering + collision of the ground)
├── entities/
│   ├── entity_manager.gd    registry by stable id + simulation tiers
│   ├── player/              player.gd (body), rider_model.gd (visual + rifle IK poses), rider.gd (the player's controller)
│   ├── enemies/             enemy.gd (bandit / pirate body + AI), enemy_outfit.gd, enemy_weapons.gd
│   ├── people/              townsfolk bodies: person_builder.gd (near/far meshes, cache, worker-thread builds),
│   │                        character_mesh.gd (skinned grid/loft emitter, 13-bone rig), person_body.gd (body,
│   │                        clothing), person_head.gd (face, eyes, hair, beards, hats), person.gdshader, skin.gdshader
│   ├── vehicles/            vehicle.gd (base), vehicle_definition.gd, ground_drive.gd, bike/ (bike.gd, bike_visual.gd,
│   │                        bike_audio.gd), jeep/ (jeep.gd, jeep_visual.gd, planing_drive.gd: the amphibious Jeep),
│   │                        cart/ (cargo_cart.gd, cart_visual.gd, cart_canopy.gd, cargo_load_view.gd, hitch_system.gd,
│   │                        vehicle_clearance.gd, ground_pose.gd: the Cart and the Rig, ADR 0014)
│   └── camera/              chase_camera.gd
├── gameplay/
│   ├── gameplay_manager.gd  owns the systems below
│   ├── controls/            controls.gd — the ControlIntent seam (Keyboard / Scripted sources)
│   ├── delivery/            delivery_system.gd, job_definition.gd
│   ├── cargo/               inventory.gd (Inventory), item_definition.gd (goods + equipment), cargo_system.gd
│   │                        (CargoSystem: the pack, holds in reach, stores, moves, use), cargo_panel.gd (the G panel)
│   ├── journey/             journey_system.gd (courier counters, the fuel tank, engine upgrades),
│   │                        road_services.gd (RoadServices: fuel stations, highway service stops,
│   │                        coach & ferry travel), station_panel.gd (a town station's window)
│   ├── weapons/             gun.gd (GunSystem: the M1 Garand), garand_model.gd, mesh_kit.gd, weapon_materials.gd, weapon_audio.gd
│   ├── combat/              encounter_director.gd (camps, ambushes), camp_kit.gd, player_vitals.gd, health.gd, combat_fx.gd
│   └── colony/              colony_system.gd (ColonySystem: core residents' jobs, areas, sites, roads, the save),
│                            urgent_supply.gd (UrgentSupply: short colonies post optional truck jobs),
│                            the colony sim (ADR 0011): economy_catalog.gd (goods, buildings, ships, colonies),
│                            colony_town.gd (ColonyTown: one colony's rules), colony_economy.gd (ColonyEconomy:
│                            towns, charters, placement, the 4 Hz tick, saves), shipping_network.gd (water grid,
│                            routes, lanes, ships, pirates), colony_views.gd (buildings, porters, ships, map overlay),
│                            colony_props.gd + mesh_bits.gd (yards, scaffolds), ship_model.gd (coaster, schooner),
│                            road_haulage.gd (RoadHaulage: carters' wagons between colonies by road)
├── ai/                      autopilot.gd (a Controls.Source that drives a Vehicle along the roads)
├── ui/                      hud/hud.gd, debug/debug_overlay.gd, mayor_view.gd (F4) + mayor/ (theme, trade page),
│                            settings/graphics_menu.gd (F10 quality presets), loading/loading_screen.gd (LoadingScreen),
│                            map/ (WorldMap: the baked map + waypoint + discovery; Minimap in the HUD; FullMap (M);
│                            MapIcons; map.gdshader)
├── data/                    the database: island maps, outer/ (the outer world), minimap/ (the baked map),
│                            config/world.tres, vehicles/*.tres, jobs/*.tres
└── tests/                   in-game test nodes and render tools (run with --test=NAME)
```

## Runtime tree

```
Game (core/app/game.gd)            boots, wires, holds the CLI/session state
├── LoadingScreen                  up from the first frame of the boot, and over long moves
├── WorldManager
│   ├── Environment                sky, sun, sea, abyss, boundaries, Terrain — always resident
│   │   └── OuterWorld             outer terrain (CDLOD), collision tiles, roads, bridges, town silhouettes, wilderness, rivers
│   └── WorldStreamer              Chunk_x_y nodes around the focus (7×7 of 60 m by default)
├── EntityManager                  bike, jeep, cart, player body, pickups, targets, (NPCs, cars...) by id
├── Rider                          player controller: mode + ControlIntent routing
├── HitchSystem                    the Cart and what tows it (the Rig); the cart's save provider
├── ChaseCamera
├── GameplayManager
│   ├── DeliverySystem
│   ├── GunSystem                  the Garand (+ CombatFx, WeaponAudio)
│   ├── PlayerVitals               the courier's Health (a node on the Player), knock-out + respawn
│   ├── EncounterDirector          camps (props + Enemies spawned by distance), road ambushes
│   └── Autopilot                  only with --autotest / --shots
├── CargoSystem                    the courier's pack, the holds in reach, the stores
├── BikeAudio
├── UI / HUD (+ Minimap), CargoPanel (G), WorldMap, FullMap (M)
└── Debug / DebugOverlay           F3
```

Nothing else is a top-level node.

## The boot and the loading screen

`Game._boot` is a sequence of named stages — `WorldManager.setup_steps` (terrain, ground, core,
the four `OuterWorld.SETUP_STEPS`, sky, textures), then vehicles, gameplay, life, colony, UI and
the first streaming ring — with one frame between stages so the `LoadingScreen` draws the stage and
a bar weighted by the measured stage times (`Game.BOOT_WEIGHTS`). Meanwhile the tree is paused (no
physics step, no streaming, no life) and the viewport's 3D is off, so a stage frame costs the
loading screen alone. `booted` / `boot_finished` mark the end; the test runner starts there.
In play the screen then waits (a PanelStack panel: controls blocked, HUD back) for
`WorldManager.settled()` — chunks, collision tiles, road ribbons and the near wilderness round the
focus built — and a run of smooth frames, then fades. `Game.relocate(text, move)` draws it before a
long move (coach & ferry tickets, F6); `Game.cover_move(from, text)` covers one that already
happened (a far respawn, F9). Tests, tools, `--autotest` and `--shots` dismiss it at once.

## The map

`world/mapgen/minimap.py` bakes the map offline into `data/minimap`: a 4096² overview of the whole
25 km square (north, -z, up) and an atlas of 1.5 m/px insets (the core, every town and hamlet),
from `data/outer`, the core's map and `world/mapgen/minimap_core.json` (the core's runtime roads and
houses, dumped by `tests/minimap_export.gd`). `WorldMap` decodes both on a worker during the boot
(the overview DXT1-compressed) and owns the waypoint, the minimap's zoom and orientation and the
camps discovered (saved as `map`); `markers()` gathers the dynamic markers (10 Hz). `Minimap` (in the
HUD's root, so it hides with the HUD) and `FullMap` draw the texture with `map.gdshader` (view centre,
metres per pixel, rotation; insets faded in close up) and only the markers per frame. Autoloads: `Events`, `Saves`. That is the whole global surface.

## The flow

```
painting ──extract.py──▶ island_map_720.png ──expand.py──▶ data/island_map.png
                                                              ├─▶ Terrain (3 m heightfield: roads, pads)
                                                              │     └─▶ Terrain3D (1.5 m mesh + textures + collision)
                                                              └─▶ Island.generate()
                                                   ├─ resident: sea, sky, boundaries → Environment
                                                   ├─ data:     locations, hubs     → WorldDatabase
                                                   └─ recipes:  one Callable per prop, per chunk
                                                                 → WorldDatabase.records
world/mapgen/outer.py ──▶ data/outer (height.f32, splat/aux/tint/roads/feat PNGs, plan.json)
                                                              └─▶ OuterWorld (boot, ~0.8 s)
                                                   ├─ resident: CDLOD terrain, bridges, silhouettes, lake
                                                   ├─ data:     roads → Terrain.road_samples, towns → locations
                                                   ├─ recipes:  plots, lamps, landmarks, signs → WorldDatabase
                                                   └─ streamed round the focus/camera: collision tiles,
                                                                road ribbons, wilderness
player position ──▶ WorldStreamer ──▶ Chunk.build(): run the chunk's recipes → nodes
								  └──▶ Chunk.queue_free() when out of range
```

A recipe is a closure that calls a `WorldKit` builder with every parameter already decided at
generation time; `Chunk.build()` sets `kit.sink` to itself and runs them. Loading a chunk twice
gives the same chunk (the kit rng is reseeded from the coordinate).

## How the guide's principles map onto the code

1. **Regions and chunks** — `WorldDatabase.chunk_of(x, z)`, `WorldConfig.chunk_size` (60 m),
   `stream_radius` (3). Locations/hubs are the logical regions; chunks are technical.
2. **Resources as the database** — `Definition` → `VehicleDefinition` (`data/vehicles/bike.tres`),
   `JobDefinition` (`data/jobs/*.tres`), `WorldConfig` (`data/config/world.tres`). A car is a new
   `.tres` plus a `Vehicle` subclass, not a fork of the bike.
3. **Entity / controller / presentation** — `Bike` (physics) ← `Rider` (controller) → `BikeVisual`
   (presentation); `Player` ← `Rider` → `RiderModel`. Controllers produce `Controls.Intent`;
   bodies consume it; visuals read state.
4. **Composition** — `Vehicle` is the shared base for anything drivable; `Rider`, `Autopilot` and a
   future NPC driver are all `Controls.Source`s. Components will be added as nodes under entities
   (Health, Interaction...) rather than deeper class trees.
5. **Few autoloads** — two. Managers hang under `Game`.
6. **Events** — `core/events/event_bus.gd`: `message`, `job_changed`, `package_collected`,
   `delivery_completed`, `gun_picked_up`, `can_hit`, `shot_fired`, `clip_pinged`, `target_damaged`,
   `enemy_killed`, `player_damaged`, `player_died`, `player_respawned`, `camp_alerted`, `camp_cleared`,
   `ambush_started`, `rider_mode_changed`, `vehicle_crashed`,
   `chunk_loaded/unloaded`, `entity_registered`, `simulation_tier_changed`, `game_saved/loaded`.
   The HUD subscribes; nothing knows the HUD exists.
7. **Simulation vs loaded scenes** — the `WorldDatabase` (recipes, locations, hubs) exists before
   any chunk does. `GunSystem` asks a `Hub` for wall tops without the farm being loaded.
8. **Stable ids** — `vehicle.bike`, `player`, `pickup.ammo.dunes_lookout`, `can.hilltop_farm.2`,
   `enemy.camp_bandit_3.2` (camp `camp.bandit.3`, slot 2), locations
   `villa_rosa_office`, `harbour_cafe`, jobs `job.seed_crate`. The save file records these, never
   node paths.
9. **Locations as self-contained content** — each hub has a `_define_*` (data) and `_build_*`
   (geometry) pair in `island.gd`; the delivery ring and wall records come from `_define_*`.
10. **Independent systems, dependencies point down** — `Game → World/Entity/Gameplay`; gameplay
    reads the database and the entity registry, publishes on the bus.
11–12. **Layered AI and simulation tiers** — `EntityManager` computes FULL / REDUCED / ABSTRACT /
    DORMANT by distance to the focus every 0.5 s and calls `set_simulation_tier(tier)` on entities
    that implement it. NPCs and cars plug in here.
13. **Local physics per vehicle** — `Vehicle.apply(intent)`; the controller is whoever holds the
    `Controls.Source`.
14. **Debug tools** — `DebugOverlay` (F3): fps, frame time, position, chunk, loaded/pending chunks,
    build ms, entities per tier, nodes/objects/draw calls, biome, nearest location, save slot.
    F6 teleport to the next hub, F7 reload the chunk under the player, F8 toggle streaming,
    F5/F9 quick save/load.
15. **Feature-based folders** — see above.

## The outer world

`Terrain` answers for the core square (|x|, |z| <= 624 m) and forwards every other `height_at`,
`normal_at`, `biome_at` and `road_dist_at` to `terrain.expanse` — the `OuterWorld`. Its ground is
triangles on a 6.25 m lattice over the 12.5 m data; the GPU patches, the collision tiles (200 m,
5 x 5 round the focus, one built per physics frame) and `height_at` evaluate the same lattice.
The outer roads are appended to `Terrain.road_samples` / `roads` / `bridges`, so RoadNavigation,
the autopilot, traffic, the reset key and `nearest_road` (a coarse 256 m grid answers far from
the core) cover the whole network. Towns and hamlets are WorldDatabase locations and recipes:
`BuildingKit.build_group(parent, plots, origin)` builds the plots when
`res://world/kit/building_kit.gd` exists, a placeholder otherwise; OuterTowns lays a paved apron
round every plot's foot where no street or plaza is (`OuterRoads.on_ribbon`). Water:
`Terrain.water_level_at(x, z)` is the sea level or, out here, the mountain lake's or a river's level
where one covers the point; swimming, the vehicles' splash rule (`Terrain.vehicle_submerged`: inland
water deeper than a ford) and the respawn's dry check use it. The core exits' bridges, and the last
14 m of their banks, are drawn and collided as the spokes' concrete decks (`OuterRoads._core_seams`).
See ADR 0010.

## The architecture kit

`BuildingKit` turns a plot into a building and is shared by the outer towns and the core island
(`WorldKit._house` builds a style `core` plot). A group of plots becomes three kinds of node:

- **one merged mesh** — walls cut around their openings, trim, plinths, roofs, baked one- or
  two-off pieces — one surface with one material (`arch.gdshader`): every texture is a layer of
  two `Texture2DArray`s (`ArchMaterials`, baked by `world/mapgen/facades.py`), a vertex carries its
  layer, tint, height above the ground and depth below the eaves, so grime, streaks, eave shadow
  and worn plaster come from the shader;
- **one MultiMeshInstance3D per module** (`ArchModules`: windows, French windows with balconies,
  doors, shopfronts, awnings, chimneys, dormers, merlons...), each module bringing its own reveal;
  instance data carry the paint, the window-frame colour and the host wall's plaster;
- **one StaticBody3D** with a box / convex shape per building part (walkable flat roofs, portico
  galleries and gate passages left open).

`ArchProps` (world/kit/building/arch_props.gd) builds the towns' street furniture, market, harbour
and country props the same way (modules in the kit's material): fountains, planters, benches, lamps,
stalls, cafe sets, carts, barrels, crates, washing lines, bollards, boats (their own MultiMesh with
the shader's `bob`), jetties, portal cranes, net racks, hay, gardens, dry-stone field walls.
`OuterProps` files a town's `props` records (world/mapgen/outer_props.py) per 60 m chunk as recipes:
one ArchCtx group per chunk, the plaza trees through the wilderness' tree models; it also builds the
quay walls along every `quay_edges` polyline and Valdoro's `terraces`.

**Trees.** Every tree model (assets/trees: TwistedTree_1-3, Pine_1-5) is two surfaces through
`WorldKit._tree_parts(model, kind, scale)`: the pack's leaf cards (the leaf shader paints them
with the kind's palette) and bark that `world/mapgen/tree_bark.py` rebuilt as closed tapered
tubes from a skeleton recovered from the pack's decimated trunks (`tree_skeletons.json`). The
core scatters, the rock builders' crest pines, the outer wilderness and the plaza planters all
take them from there. Far away (OuterFlora beyond 260 m) a tree is `WorldKit.tree_impostor`: the
same model baked by `tree_impostors.py` into three cards of data (height, bark, occlusion,
coverage) that the leaf shader colours like the near leaves - one draw call per variant bucket.

The plan of a building (`ArchStyles.plan`) is a pure function of the plot and its seed, so the far
silhouette (`BuildingKit.build_lod`) always matches the detailed building. `tests/building_showcase.gd`
builds every style x kind and renders them.

## Rendering (Forward+)

`WorldKit._build_environment` keeps the reference look (`Atmosphere`) and, when the renderer is
Forward+ (`WorldKit.forward_plus()`), adds `_forward_plus_quality`: short-range SSAO, SSIL, a thin
volumetric fog (sun shafts), and four shadow cascades (crisp contact shadows within ~23 m, stable
far shadows to 520 m). SDFGI is off (a 25 km world displaced on the GPU; cascades scroll-leak at
speed). The Compatibility renderer ignores all of it. `OuterWorld._follow_camera` grows the far
plane with altitude and keeps the sea plane under the camera; the sea fogs into the sky's horizon
colour before the far plane, so the horizon never shows the sky's lower half.

**Day and night (ADR 0013).** `DayNight` (world/sky, under the Environment) turns IslandLife's hour
into the sun and the moon (one DirectionalLight: the sun by day, the moon by night), the sky
(gradient, discs, stars, cloud colours), the environment (ambient, fog, exposure), the sea's own
fog and horizon, and the global shader uniforms `dn_fill` / `dn_night` / `dn_lamps` / `dn_windows`
/ `dn_sun_dir` (project.godot `[shader_globals]`) that every material faking its own light reads.
Lamp glass glows everywhere by `dn_lamps`; `NightLights` moves a small pool of OmniLights onto the
nearest lamps (group `night_lights`); lighthouse beams, headlights (`VehicleLights`) and camp fires
(`CampfireGlow`) are in world/sky too.

**Quality presets.** `GraphicsSettings` (core/settings): Low / Medium / High (default) / Ultra -
the post stack, shadows, anti-aliasing (FXAA, TAA, FSR 2 on Retina, MSAA + alpha-to-coverage),
LOD bias, anisotropy, the lamp-light budget. F10 opens `GraphicsMenu`; `--quality=` overrides for
one run. Textures that reach 3D materials from scripts go through `TexMips.ensure` (the importer's
defaults give them no mipmaps); the arch kit's and the terrain's texture arrays are VRAM-compressed
(S3TC / BPTC) on the worker threads at boot.

## Persistence

`Saves.register(key, provider)`; a provider implements `save_state() -> Dictionary` and
`load_state(d)`. Registered: `delivery`, `gun` (clip, reserve, cache, cans), `combat` (cleared camps,
dead enemies by camp slot, looted crates, kill stats), `bike`, `jeep` (its bed, afloat; an old save's `truck` block
is read by it through `Saves.alias`), `cart` (the HitchSystem: where, its load, what it is hitched to), `cargo`
(the pack), `rider`, ... Files: `user://saves/<slot>.json`,
diffs from the default world keyed by id (e.g. popped cans as `can.dunes_lookout.1`).

## Tests and tools

Everything runs inside the booted game through the test runner, so autoloads and the whole tree are
present:

```
godot --headless --path . -- --autotest --deliveries=4          # delivery loop end to end
godot --headless --path . -- --test=architecture_tests          # streaming, database, tiers, events, save/load
godot --headless --path . -- --test=edge_tests                  # brake/reverse, sea reset, camera
godot --headless --path . -- --test=feature_tests               # dismount, swim, pistol, plane (28 checks)
godot --headless --path . -- --test=outer_world_tests           # outer world: data, ground == collision, roads, towns, budgets
python3 world/mapgen/outer.py                                   # regenerate data/outer (~1 min)
xvfb-run godot --path . --rendering-driver opengl3 -- --test=view --nostream --nofog --out=/tmp/view
xvfb-run godot --path . --rendering-driver opengl3 -- --test=feature_shots --out=/tmp/fshots
ROAD=3 godot --headless --path . -- --test=road_dump            # road profiles / bridges
PX=.. PY=.. PZ=.. godot --headless --path . -- --test=near_probe --nostream
xvfb-run godot --path . --rendering-driver opengl3 -- --test=view --spots=cliff_coast,villa --out=DIR   # reference spots (reference/spots.json)
```

## Life in the outer world

`IslandLife` owns `OuterLife` (ADR 0012): `TownFolk`, `OuterTraffic`, `OuterBoats`. All three
cost nothing far from the viewer (the camera, or the courier):

- **Townsfolk** — per plan town a `TownPopulation` (generated on a worker thread within 1.6 km:
  spots, a street walking graph clear of plots and props, ~0.7 people a plot with trades from
  their work spots and a daily routine). Within ~0.5 km the town is *active*: people are placed by
  the routine (spread over frames), a slice of them is re-checked each frame, a due one asks for a
  route (worker batches) and walks it; positions are functions of the clock. Views: the 160
  nearest get a pooled `TownBody` (RiderModel, `manual_meshes`), the 40 nearest may draw the near
  mesh; meshes are `PersonBuilder` parts built and committed on workers (`request_part`,
  `poll_parts`).
- **Traffic** — `OuterTraffic` spawns 300-600 m out (150 m behind the camera), routes on
  `RoadNavigation` to town / hamlet gates, lanes and limits per road class, following, junction
  yielding, stops for the courier; kinematic colliders on layer 16; gone beyond 900 m.
- **Boats** — `OuterBoats`: per harbour moorings, fishing grounds and water routes (A* on a 20 m
  grid, planned on a worker within 3.2 km), boats and fishers drawn within 1.6 km; positions by
  the clock.

## Fuel, stations and travel

`JourneySystem` owns the tanks, one per vehicle: the bike's rides `tank_range_m` (30 km) on the level,
the Jeep's 40 km; a load burns more (a whole tank more per `cargo_kg_per_extra_tank`: 160 kg on the
bike, 600 kg on the Jeep; a towed Cart counts with its load), flight burns 1.6x per metre and
planing on water 2.2x; an empty tank limps (`Bike.LIMP_SPEED`, `Jeep.LIMP_SPEED`). The pumps and
the counter serve the vehicle the courier drives or last drove. It warns at a quarter, at 10 % and when empty, naming the nearest pump. `RoadServices`
places the fuel stations at boot from the world as loaded (the outer roads' samples, plots, props
and rivers — nothing in the generator's plan): one at the edge of each town on the highway into its
gate, highway service stops so no pump-to-pump stretch is longer than `MAX_GAP` (5.2 km), and the
courier counters. A station is a record, drawn (apron, pumps, canopy, shop, tall sign) within 1.1 km.
B on an apron fills up (a highway stop) or opens the `StationPanel` (a town: fuel and coach & ferry
tickets). A ticket to a visited town moves the courier and his bike there for coins and game time
(`RoadServices.travel`); the Villa Rosa counter and the town counters sell tickets too.

## Colonies and shipping

`Colony` (ColonySystem, a child of Game) owns `Economy` (ColonyEconomy): a `ColonyTown` record per
colony (the core villa, the five towns), a `ShippingNetwork` (the 50 m water grid built on a
worker thread at boot, routes, lanes and ships as records) and `ColonyViews` (what is near the
viewer). The economy ticks at 4 Hz by rates, loaded or not; porters' trips and ships' positions
are records the views read. Registered with `Saves` as `colony` (version 2). The Mayor view (F4)
is the UI; pirates come from the EncounterDirector's camps (`camp_cleared` recomputes raid risk).
`RoadHaulage` runs carters' wagons between any two chartered colonies by road (a distance along
the road by the clock, like a ship), so inland Valdoro and Campo Real trade. Every town colony's
hall keeps a kitchen garden (its staple food, two workers, filled last) and every town has local
food buildings, so a charter left alone feeds itself. Loading is per record: a damaged town or
lane is mended or dropped on its own and reported (`ColonySystem.load_report`,
`Saves.last_report`, a message); saves are written to a temp file and renamed.
`UrgentSupply` (in the economy) posts an optional cargo job (the Jeep, or a rig towing the Cart) when a founded town colony runs short
of food or goods; `DeliverySystem.start_extra_job` runs it on top of the route and resumes the
route after. See ADR 0011.

## Combat

`GunSystem` owns the Garand: hitscan down `ChaseCamera.view_ray()` inside a spread cone, a second
ray from the muzzle so nearby cover blocks, `take_hit()` on whatever `hurtbox` Area3D (layer 32) it
meets. Enemies are `CharacterBody3D`s on layer 64 (the player's mask includes it) with hurtboxes
on the rig's torso / hips / head pivots, so crouching behind cover really hides them. The
Hitscan starts at the muzzle's depth along the view ray, so nothing behind the courier is ever the
aim point. `EncounterDirector` is the ctx seam an `Enemy` talks to (courier, cover points, allies, hits on the
courier); enemies never touch the Rider or the HUD. Sight and cover rays share a budget of 10 per
physics frame across all enemies. Tiers: FULL = physics + 10 Hz AI, REDUCED = kinematic
(snapped to the surface under a moving man — a tower top, a roof — or kept where he stands, no
`move_and_slide`) + 3 Hz AI, below that frozen; camps despawn at 320 m anyway. Entities register
at the tier their distance gives. A streamed camp builds its props, then one man a frame; a man
is positioned *before* he enters the tree (a kinematic body added at the origin and moved sweeps
its broadphase box across the country in its first step: 0.4-1.4 s per man at an outer camp). A
hit, a kill or a near miss tells the camp where the shot came from (roughly): rifles see 250 m in
a fight, fire suppressively out to 260 m and bound forward when the shooter is out of their reach.
`encounters.add_camp(id, kind, pos, facing, size)` is the whole API a world needs to place a camp.
Enemies are townsfolk bodies: `EnemyOutfit.look_for(kind, seed)` (CharacterLook styles `bandit` /
`pirate`, eight pinned variants per kind prebuilt at boot) plus the outfit's gear on the pivots.

## Adding an NPC or a car (the point of all this)

- Car: `entities/vehicles/car/car.gd extends Vehicle` (+ `car_definition.tres`), spawn it with
  `entities.register(car, &"vehicle.car.taxi_01", &"vehicle")`, give it a `Controls.Source`
  (a driver AI that follows `Terrain.road_samples` like the Autopilot does).
- A townsperson's look: `CharacterLook.from_seed(seed, &"puerto", "dockworker")` (world/life) is a
  plain Dictionary; `CharacterLook.spawn(...)` or `RiderModel.new()` + `look = ...` (or
  `CharacterLook.apply(model, look)` on a live one) gives a model on the courier's pivot rig, so
  every animation, seating pose and hand prop works unchanged. The body is one skinned surface
  per detail level (one draw call), built by `PersonBuilder` and cached by look; set
  `async_build = true` for streamed people so the build happens on a worker thread.
- NPC: a body under `entities/npc/`, registered with a stable id, implementing
  `set_simulation_tier()` so far NPCs become schedule-only records; spawn/despawn on
  `Events.chunk_loaded/unloaded` of their home chunk, with their state in the save file.

## The Jeep, the Cart and the Rig (ADR 0014)

`Jeep` is a `Vehicle` like the bike: the GroundDrive on land (`data/vehicles/jeep.tres`, its
LegendOfJeep feel as data: torque, steering fall-off, handbrake drift, a boost tank), and its own
`PlaningDrive` afloat — deep water under the body lifts the hull to its draught, the propellers
push it to `water_max_speed`, a rudder turns it, a shallow bed under the front wheels hands it back
to the GroundDrive. `JeepVisual` animates LegendOfJeep's GLB (steering, spin, per-wheel travel from
the wheel rays, body lean and squash, the pontoons and propellers of the amphibious transformation,
the winch cable, the load on its bed).

A `CargoCart` hitched to a vehicle makes a **Rig**. The `HitchSystem` owns the coupling (the
source's rules: stopped, on the ground, backed up so the drawbar eye is within reach of the hitch,
a clear line; wings folded, not afloat), moves the cart with its tow vehicle on every `relocated`
(road recovery, respawn, save loaded) and saves the cart. Each tick the cart solves its drawbar
from the real axle-to-hitch direction and turns only where it is clear (`VehicleClearance`); the
tow vehicle's GroundDrive is tethered to the cart's axle (`tether_anchor` / `tether_length`) and,
while towing, collides with the vehicles layer — the cart can never swing through it. Mass slows
(`Vehicle.tow_scales`) and burns fuel (`JourneySystem.load_of`). A cart does not float: the Jeep
towing one splashes in deep water and the rig recovers together.

Goods are `Inventory`s of `ItemDefinition`s (the colony goods plus ammunition crates and fuel
cans): the courier's pack, the Jeep's bed, the Cart. `CargoSystem` lists the **holds** in reach
(those three, a founded colony's hall or warehouse, a station's or counter's shop), moves goods
between them (a colony's stock is its mayor's, free; a shop takes coins through
`Inventory.commit`), and uses equipment. `CargoPanel` (G) is its parchment window. The courier's
parcel can ride in the cart (`DeliverySystem.parcel_in_cart`): the cart in the drop-off ring
delivers it.
