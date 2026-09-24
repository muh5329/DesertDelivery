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
│   ├── definitions/         definition.gd (base Resource: id + display_name)
│   └── utils/               materials.gd (Mats: primitive mesh + material helpers)
├── world/
│   ├── world_manager.gd     owns terrain / environment / database / streamer
│   ├── world_config.gd      WorldConfig resource (chunk size, stream radius, tier radii, seed)
│   ├── database/            world_database.gd (recipes per chunk, locations, hubs), hub.gd
│   ├── streaming/           world_streamer.gd, chunk.gd
│   ├── terrain/             terrain.gd (map-driven heightfield, roads, bridges, viaducts -> Terrain3D), bridge.gd
│   ├── outer/               the 25 km outer world (ADR 0010): outer_world.gd (OuterWorld: queries + collision),
│   │                        outer_ground.gd (the lattice surface), outer_terrain_view.gd + .gdshader (CDLOD),
│   │                        outer_roads.gd (network, ribbons, bridges), outer_towns.gd (towns, plots, landmarks),
│   │                        outer_flora.gd (wilderness)
│   ├── kit/                 world_kit.gd (every builder: houses, rocks, kits, arcades, sea, sky),
│   │                        building_kit.gd (BuildingKit: plots -> buildings, per-town styles) + building/
│   │                        (ArchStyles plans, ArchFacade walls/openings/roofs, ArchModules instanced pieces,
│   │                        ArchSpecial towers/churches/walls/gates, ArchMaterials + arch.gdshader, ArchMesh)
│   ├── island/              island.gd (the generator for THIS island: hubs, places, roads, biomes)
│   └── mapgen/              extract.py (painting → 720 m map), expand.py (→ 1248 m world + new land), textures.py,
│                            outer.py (+ outer_*.py: the outer world → data/outer), outer_textures.py,
│                            facades.py (the architecture kit's PBR layers → assets/buildings)
├── assets/terrain/          ground textures for Terrain3D
├── addons/terrain_3d/       the Terrain3D GDExtension (rendering + collision of the ground)
├── entities/
│   ├── entity_manager.gd    registry by stable id + simulation tiers
│   ├── player/              player.gd (body), rider_model.gd (visual), rider.gd (the player's controller)
│   ├── vehicles/            vehicle.gd (base), vehicle_definition.gd, bike/ (bike.gd, bike_visual.gd, bike_audio.gd)
│   └── camera/              chase_camera.gd
├── gameplay/
│   ├── gameplay_manager.gd  owns the systems below
│   ├── controls/            controls.gd — the ControlIntent seam (Keyboard / Scripted sources)
│   ├── delivery/            delivery_system.gd, job_definition.gd
│   └── weapons/             gun.gd
├── ai/                      autopilot.gd (a Controls.Source that drives a Vehicle along the roads)
├── ui/                      hud/hud.gd, debug/debug_overlay.gd
├── data/                    the database: island maps, outer/ (the outer world), config/world.tres, vehicles/*.tres, jobs/*.tres
└── tests/                   in-game test nodes and render tools (run with --test=NAME)
```

## Runtime tree

```
Game (core/app/game.gd)            boots, wires, holds the CLI/session state
├── WorldManager
│   ├── Environment                sky, sun, sea, abyss, boundaries, Terrain — always resident
│   │   └── OuterWorld             outer terrain (CDLOD), collision tiles, roads, bridges, town silhouettes, wilderness
│   └── WorldStreamer              Chunk_x_y nodes around the focus (7×7 of 60 m by default)
├── EntityManager                  bike, player body, pickups, targets, (NPCs, cars...) by id
├── Rider                          player controller: mode + ControlIntent routing
├── ChaseCamera
├── GameplayManager
│   ├── DeliverySystem
│   ├── GunSystem
│   └── Autopilot                  only with --autotest / --shots
├── BikeAudio
├── UI / HUD
└── Debug / DebugOverlay           F3
```

Nothing else is a top-level node. Autoloads: `Events`, `Saves`. That is the whole global surface.

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
world/mapgen/outer.py ──▶ data/outer (height.f32, splat/aux/tint/roads PNGs, plan.json)
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
   `delivery_completed`, `gun_picked_up`, `can_hit`, `rider_mode_changed`, `vehicle_crashed`,
   `chunk_loaded/unloaded`, `entity_registered`, `simulation_tier_changed`, `game_saved/loaded`.
   The HUD subscribes; nothing knows the HUD exists.
7. **Simulation vs loaded scenes** — the `WorldDatabase` (recipes, locations, hubs) exists before
   any chunk does. `GunSystem` asks a `Hub` for wall tops without the farm being loaded.
8. **Stable ids** — `vehicle.bike`, `player`, `pickup.pistol`, `can.hilltop_farm.2`, locations
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
`res://world/kit/building_kit.gd` exists, a placeholder otherwise. See ADR 0010.

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

The plan of a building (`ArchStyles.plan`) is a pure function of the plot and its seed, so the far
silhouette (`BuildingKit.build_lod`) always matches the detailed building. `tests/building_showcase.gd`
builds every style x kind and renders them.

## Persistence

`Saves.register(key, provider)`; a provider implements `save_state() -> Dictionary` and
`load_state(d)`. Registered: `delivery`, `gun`, `bike`, `rider`. Files: `user://saves/<slot>.json`,
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

## Adding an NPC or a car (the point of all this)

- Car: `entities/vehicles/car/car.gd extends Vehicle` (+ `car_definition.tres`), spawn it with
  `entities.register(car, &"vehicle.car.taxi_01", &"vehicle")`, give it a `Controls.Source`
  (a driver AI that follows `Terrain.road_samples` like the Autopilot does).
- NPC: a body under `entities/npc/`, registered with a stable id, implementing
  `set_simulation_tier()` so far NPCs become schedule-only records; spawn/despawn on
  `Events.chunk_loaded/unloaded` of their home chunk, with their state in the save file.
