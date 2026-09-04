# Desert Delivery

A small third-person motorbike courier game inspired by *Into the Wind*, set on a 1.25 km island grown from a
reference painting, built in **Godot 4.4+** with the GL Compatibility renderer. Everything (roads, buildings,
vegetation, the bike and the rider) is generated procedurally from GDScript at start-up. The ground itself is
drawn and collided by the **Terrain3D** plugin (`addons/terrain_3d`): the generated heightfield is handed to it
with a per-cell texture map (grass, limestone, dirt roads, sand, red clay, ploughed soil, salt) and a colour
tint map, so it renders with real PBR textures, normal maps and a clipmap LOD instead of the old flat facets.

## Run it

1. Install Godot 4.4 or newer (standard build) from https://godotengine.org/download.
2. Open Godot → **Import** → pick `project.godot` in this folder → **Edit** → press **F5** (Play).
   Or from a terminal: `godot --path /path/to/DesertDelivery`.
   The Terrain3D GDExtension ships in `addons/terrain_3d` (binaries for macOS, Windows, Linux, iOS, Android, web);
   it does not need to be enabled as an editor plugin for the game to run. `--facet` on the command line
   (after `--`) renders the old flat-shaded terrain instead, for comparison.

## Controls

| Action | Keys | Gamepad |
| --- | --- | --- |
| Accelerate | W / ↑ | Right trigger / A |
| Brake / reverse | S / ↓ | Left trigger / B |
| Steer | A D / ← → | Left stick |
| Handbrake (drift) | Space | X |
| Reset bike to the nearest road | R | Y |
| Look back | C | — |
| Quit | Esc | — |

## Beyond the bike

- **E** hops off the bike (when stopped) — walk with WASD, Shift to run, Space to jump, mouse / right stick to look. E next to the bike to ride again. R on foot brings you and the bike back to the nearest road.
- **Swim** — wade into the sea and the boy swims (slower, can't shoot); the bike auto-resets if it ends up in the water.
- **Pistol** — an old pistol sits on a crate at the Dunes Lookout. On foot, hold RMB / LB to aim over the shoulder and F / LMB / RB to fire. Tin cans line the farm's stone wall and the lookout bench (9 total).
- **Plane** — T / D-pad-up folds the wings out. Throttle (W) past 54 km/h, then pull back (S / ↓) to lift off. In the air the engine cruises on its own: S/↓ raises the nose, W/↑ lowers it, A/D bank, Shift boosts. To land, nose down gently and pull up just before touchdown; T folds the wings again.
- Esc twice within 3 s quits (the first press also frees the mouse; click to re-capture).

## The loop

Ride to the glowing ring at the pickup, slow to a stop inside it to load the package onto the rear
rack, then follow the compass (top-left) to the destination ring and stop again to hand it over.
Ten jobs chain round the island: Villa Rosa Office (SW vineyards) → Hilltop Farm (NW massif) → Harbour Cafe
(NE town, over the strait aqueduct) → Dunes Lookout (badlands, over the gorge viaduct) → Lakeside Camp →
Bodega San Marco (the southern vineyards) → the Salinas (salt pans) → Cala Blanca (fishing cove) → the Marble
Quarry and San Telmo Monastery (the northern Highlands, over the mountain pass) → back to the Villa.
Signposts at each hub point the way; F6 teleports to the next hub.

## Places

Eight hubs with delivery rings — Villa Rosa, Hilltop Farm, the Harbour, Dunes Lookout, San Telmo Monastery,
the Marble Quarry, Cala Blanca and the Salinas — and nine more named places to find: the Town Square and the
Lighthouse on the town island, the Hamlet by the bay, Windmill Ridge, the Hill Chapel, the Refugio on the pass,
the Lakeside Camp, the Bodega and Torre Vieja (the old fort on the southern headland).

## Automated checks

All checks run inside the booted game through the test runner (`--test=NAME` loads `tests/NAME.gd`):

```
godot --headless --path . -- --autotest --deliveries=10 --maxtime=2800   # drives the whole loop, exits 0 on success
godot --headless --path . -- --test=architecture_tests          # streaming, world database, tiers, events, save/load
godot --headless --path . -- --test=edge_tests                  # brake/reverse, sea reset, camera
godot --headless --path . -- --test=feature_tests               # dismount, swim, pistol, plane
xvfb-run godot --path . --rendering-driver opengl3 -- --test=feature_shots --out=/tmp/fshots
xvfb-run godot --path . --rendering-driver opengl3 -- --test=view --out=/tmp/view   # 20+ fixed views, streamed
xvfb-run godot --path . --rendering-driver opengl3 -- --shots=/tmp/shots --autotest   # + screenshots
python3 world/mapgen/extract.py [painting.png]   # painting -> world/mapgen/island_map_720.png (the 720 m map)
python3 world/mapgen/expand.py                   # 720 m map -> data/ (1248 m world with the new land)
python3 world/mapgen/textures.py                 # bake the procedural ground textures in assets/terrain
```

Debug keys in game: **F3** overlay (fps, chunk, loaded chunks, entities per tier, draw calls...),
**F5/F9** quick save/load, **F6** teleport to the next hub, **F7** reload the chunk under you, **F8** toggle streaming.

## Layout

See `ARCHITECTURE.md` for the full picture; `CONTEXT.md` for the domain vocabulary.

- `core/` – `Game` root (boot + wiring), `Events` bus, `Saves`, definitions, utils
- `world/` – `WorldManager`, `WorldDatabase` (recipes per chunk, locations, hubs), `WorldStreamer` + `Chunk`, `Terrain` (heightfield → Terrain3D), `WorldKit` builders, the `Island` generator, `mapgen/` (extract, expand, textures)
- `assets/terrain/` – ground textures (two CC0 ambientCG sets + five baked ones)
- `assets/foliage/` – grass / flower / leaf-clump cards (baked by `world/mapgen/foliage.py`) for the tree canopies and Terrain3D's instancer grass
- `addons/terrain_3d/` – the Terrain3D plugin
- `entities/` – `EntityManager` (ids + simulation tiers), player (`Player`, `Rider`, `RiderModel`), vehicles (`Vehicle` base, `Bike`), camera
- `gameplay/` – `GameplayManager`, `Controls` seam, `DeliverySystem` + `JobDefinition`, `GunSystem`
- `ai/` – `Autopilot`
- `ui/` – `HUD`, `DebugOverlay`
- `data/` – island maps, `config/world.tres`, `vehicles/bike.tres`, `jobs/*.tres`
- `tests/` – test nodes and render tools
