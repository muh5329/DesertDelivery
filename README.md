# Desert Delivery

A small third-person motorbike courier game inspired by *Into the Wind*, set on a 1.25 km island grown from a
reference painting, tested in **Godot 4.7** with the Forward+ renderer (Vulkan on macOS). Roads and settlements are
generated from GDScript; the courier, motorcycle, town buildings, vehicles and wildlife use
Blender-authored glTF assets. The ground itself is
drawn and collided by the **Terrain3D** plugin (`addons/terrain_3d`): the generated heightfield is handed to it
with a per-cell texture map (grass, limestone, dirt roads, sand, red clay, ploughed soil, salt) and a colour
tint map, so it renders with real PBR textures, normal maps and a clipmap LOD instead of the old flat facets.

## Run it

1. Install Godot 4.7 (standard build) from https://godotengine.org/download.
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
| Reset active vehicle to the nearest road | R | Y |
| Look back | C | — |
| Fire / release truck winch | Q | RB |
| Toggle truck cargo packing (while stopped) | G | — |
| Island journal | N | — |
| Close journal / quit | Esc | B closes journal |

## Beyond the bike

- **E** exits the current vehicle (when stopped) — walk with WASD, Shift to run, Space to jump, mouse / right stick to look. E beside either vehicle mounts it. R brings the active vehicle and rider back to the nearest road.
- **Cargo truck** — a compact red truck is parked a short walk behind the starting bike. It is slower but has a 4×6 rear packing rack for larger loads. Stop and press G, move the translucent tetromino with WASD, rotate with Z, place with Space, undo with X, and press G again to secure the load. Unsupported or overlapping pieces cannot be placed; a fuller rack adds weight and trims the truck's top speed.
- **Winch** — while driving the truck, Q fires the front cable at a tree, rock, building, or other solid obstacle up to 38 m ahead. It reels in automatically and can pull the truck up steep walls when the anchor is high; press Q again to release it.
- **Swim** — wade into the sea and the boy swims (slower, can't shoot); the bike auto-resets if it ends up in the water.
- **Pistol** — an old pistol sits on a crate at the Dunes Lookout. On foot, hold RMB / LB to aim over the shoulder and F / LMB / RB to fire. Tin cans line the farm's stone wall and the lookout bench (9 total).
- **Plane** — T / D-pad-up folds the wings out. Throttle (W) past 54 km/h, then pull back (S / ↓) to lift off. In the air the engine cruises on its own: S/↓ raises the nose, W/↑ lowers it, A/D bank, Shift boosts. To land, nose down gently and pull up just before touchdown; T folds the wings again.
- Esc twice within 3 s quits (the first press also frees the mouse; click to re-capture).

## The loop

Ride to the glowing ring at the pickup, slow to a stop inside it to load the package onto the rear
rack, then follow the compass (top-left) to the destination ring and stop again to hand it over.
Walking and the cargo truck also support handoffs. Stay grounded and below 2.5 m/s in the
ring for half a second. Coins are awarded once on delivery, and F5/F9 preserves the current
package, job and wallet. Ten jobs chain round the island: Villa Rosa Office (SW vineyards) → Hilltop Farm (NW massif) → Harbour Cafe
(NE town, over the strait aqueduct) → Dunes Lookout (badlands, over the gorge viaduct) → Lakeside Camp →
Bodega San Marco (the southern vineyards) → the Salinas (salt pans) → Cala Blanca (fishing cove) → the Marble
Quarry and San Telmo Monastery (the northern Highlands, over the mountain pass) → back to the Villa.
Signposts at each hub point the way; F6 teleports to the next hub.

## Places

Eight hubs with delivery rings — Villa Rosa, Hilltop Farm, the Harbour, Dunes Lookout, San Telmo Monastery,
the Marble Quarry, Cala Blanca and the Salinas — and nine more named places to find: the Town Square and the
Lighthouse on the town island, the Hamlet by the bay, Windmill Ridge, the Hill Chapel, the Refugio on the pass,
the Lakeside Camp, the Bodega and Torre Vieja (the old fort on the southern headland).

## Island life and journal

Press **N** to open the parchment field journal. Search or sort the 64 named residents,
select a person, then choose a weekday in the weekly grid or day selector to read their exact
itinerary. Field notes and the selected resident are saved with F5; F9 restores them. Closing
the journal consumes that input so it cannot also fire the pistol or quit the game.

Each resident has an occupation, home, daily routine and weekly overrides in
`data/life/residents.json`. The seven-day calendar repeats after Sunday, with 48 real minutes
per island day. Residents walk to activity stations, work with job props, eat, shop and rest;
16 delivery drivers travel between island destinations and unload before their next journey.
Records continue travelling when their models are outside streaming range. The clock, routes,
completed work and notes persist in the existing save system.

Traffic uses the road graph, finite acceleration/braking, junction priority, ground and bridge support, animated
wheels and steering, and nearby body collisions. Wildlife includes grazing sheep, deer,
rabbits and dogs, circling gulls, and two boats on validated water routes. Sky clouds drift
while daylight changes with the simulation clock.

These are stylized game assets inspired by the supplied references. Residents currently share
the courier base mesh with palette/size variants; their occupations are outdoor activity
stations with timed work cycles, rather than enterable shops with a production economy.

## Blender assets

The assets were authored through Blender MCP. Editable sources are in `assets/source/`, with
`.gdignore` preventing automatic Blender conversion during game import. Runtime files are
in `assets/models/`. Reproduction scripts are in `tools/blender/`: `common.py`, `bike.py`,
`character.py`, `island_kit.py`, `town_revision.py` and `hero_finish.py`. They use the project
path at the top of `common.py`; update it when moving the repository. Run the generators
through Blender in that order, with `hero_finish.py` last, then let Godot import the GLBs.

## Automated checks

All checks run inside the booted game through the test runner (`--test=NAME` loads `tests/NAME.gd`):

```
godot --headless --path . -- --autotest --deliveries=10 --maxtime=2800   # drives the whole loop, exits 0 on success
godot --headless --path . -- --test=architecture_tests          # streaming, world database, tiers, events, save/load
godot --headless --path . -- --test=edge_tests                  # brake/reverse, sea reset, camera
godot --headless --path . -- --test=feature_tests               # dismount, swim, pistol, plane
godot --headless --path . -- --test=truck_tests                 # mount, Tetris rack, winch pull / wall climb
godot --headless --path . -- --test=delivery_tests              # all handoffs, wallet, loaded stage, on-foot / truck
godot --headless --path . -- --test=life_tests                  # routines, navigation, grounding and collisions
godot --path . -- --test=catalogue_view --out=/tmp/journal.png   # actual UI checks and two viewport captures
godot --path . -- --test=town_world_view --out=/tmp/town         # streamed street and aerial captures
godot --path . -- --test=life_view --out=/tmp/residents          # real working resident and driver views
xvfb-run godot --path . --rendering-driver opengl3 -- --test=feature_shots --out=/tmp/fshots
xvfb-run godot --path . --rendering-driver opengl3 -- --test=view --out=/tmp/view   # 20+ fixed views, streamed
xvfb-run godot --path . --rendering-driver opengl3 -- --shots=/tmp/shots --autotest   # + screenshots
python3 world/mapgen/extract.py [painting.png]   # painting -> world/mapgen/island_map_720.png (the 720 m map)
python3 world/mapgen/expand.py                   # 720 m map -> data/ (1248 m world with the new land)
python3 world/mapgen/textures.py                 # pack / bake the ground textures in assets/terrain
python3 world/mapgen/foliage.py                  # bake the leaf / grass cards in assets/foliage
xvfb-run godot --path . --rendering-driver opengl3 -- --test=view --spots=cliff_coast --out=/tmp/x
python3 reference/compare.py /tmp/x/cliff_coast.png reference/ref_cliff_coast.png   # similarity vs the reference
```

Debug keys in game: **F3** overlay (fps, chunk, loaded chunks, entities per tier, draw calls...),
**F5/F9** quick save/load, **F6** teleport to the next hub, **F7** reload the chunk under you, **F8** toggle streaming.

## Layout

See `ARCHITECTURE.md` for the full picture; `CONTEXT.md` for the domain vocabulary.

- `core/` – `Game` root (boot + wiring), `Events` bus, `Saves`, definitions, utils
- `world/` – `WorldManager`, `WorldDatabase` (recipes per chunk, locations, hubs), `WorldStreamer` + `Chunk`, `Terrain` (heightfield → Terrain3D), `WorldKit` builders, the `Island` generator, `mapgen/` (extract, expand, textures)
- `assets/terrain/` – ground textures (seven packed CC0 ambientCG sets + four baked ones; see `assets/CREDITS.md`)
- `assets/rock/`, `assets/trees/` – rock textures and the Quaternius CC0 trees with `leaf.gdshader`
- `reference/` – reference screenshots, brief, camera spots, `compare.py`, per-round critiques and changelogs
- `assets/foliage/` – grass / flower / leaf-clump cards (baked by `world/mapgen/foliage.py`) for the tree canopies and Terrain3D's instancer grass
- `addons/terrain_3d/` – the Terrain3D plugin
- `entities/` – `EntityManager` (ids + simulation tiers), player (`Player`, `Rider`, `RiderModel`), vehicles (`Vehicle` base, `Bike`, `Truck`, `TruckCargo`), camera
- `gameplay/` – `GameplayManager`, `Controls` seam, `DeliverySystem` + `JobDefinition`, `GunSystem`
- `ai/` – `Autopilot`
- `ui/` – `HUD`, `DebugOverlay`
- `data/` – island maps, `config/world.tres`, vehicle definitions (`bike.tres`, `truck.tres`), `jobs/*.tres`
- `tests/` – test nodes and render tools
