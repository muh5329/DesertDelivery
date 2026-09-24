# Desert Delivery

A third-person courier game on a **25 km × 25 km** country: a detailed 1.248 km Mediterranean island at the centre, ringed by a lagoon, and round it a generated country — an alpine range with a dammed lake in the north, an arid plateau of mesas and canyons in the south, farmland plains and an estuary in the east, a rugged coast and an archipelago in the west. Five towns (the port city of Puerto Alto, the alpine hill town of Valdoro, the walled desert port of Sarmada, the island village of Isola Serena, the plains market town of Campo Real) and fourteen hamlets are joined by ~220 km of highways, roads and tracks with 40+ bridges, and by sea lanes between the ports. See [ADR 0010](docs/adr/0010-outer-world.md).

The September 2026 overhaul adds a hand-painted, Ghibli-inspired summer palette, an ImageGen gouache surface used by terrain and object materials, a newly authored Blender delivery truck, regraded existing GLBs, and occupation-based wardrobe silhouettes for all 64 residents. The shared base character and most existing model topology remain. Godot **4.7 Forward+ (Vulkan)** is the current renderer on macOS; Terrain3D draws and collides the detailed core.

The gameplay pass adds explicit player/resident states, responsive bike and truck handling, buffered/coyote jumps, safe mounting, blocked-route recovery, spatial traffic lookup, and atomic delivery payouts with saved receipts. Implementation, real screenshots, adversarial findings and remaining quality gaps are in [the overhaul review](artifacts/overhaul-2026-09-19/README.md). AAA quality has not been demonstrated.

## Run it

1. Install Godot 4.7 (standard build) from https://godotengine.org/download.
2. Open Godot → **Import** → pick `project.godot` in this folder → **Edit** → press **F5** (Play).
   Or from a terminal: `godot --path /path/to/DesertDelivery`.
   Desktop uses Forward+; macOS selects Vulkan after full-render profiling. For older GPUs, use `godot --path /path/to/DesertDelivery --rendering-method gl_compatibility`.
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
- Hold Space for a higher on-foot jump; tap for a short hop. Movement follows the camera, and manual orbit keeps your chosen direction. The camera retracts around obstacles and hides the character when pushed too close.
- **Cargo truck** — a compact red truck is parked a short walk behind the starting bike. It is slower but has a 4×6 rear packing rack for larger loads. Stop and press G, move the translucent tetromino with WASD, rotate with Z, place with Space, undo with X, and press G again to secure the load. Unsupported or overlapping pieces cannot be placed; a fuller rack adds weight and trims the truck's top speed.
- **Winch** — while driving the truck, Q fires the front cable at a tree, rock, building, or other solid obstacle up to 38 m ahead. It reels in automatically and can pull the truck up steep walls when the anchor is high; press Q again to release it.
- **Swim** — wade into the sea and the boy swims (slower, can't shoot); the bike auto-resets if it ends up in the water.
- **Pistol** — an old pistol sits on a crate at the Dunes Lookout. On foot, hold RMB / LB to aim over the shoulder and F / LMB / RB to fire. Tin cans line the farm's stone wall and the lookout bench (9 total).
- **Plane** — T / D-pad-up folds the wings out. Throttle (W) past 54 km/h, then pull back (S / ↓) to lift off. In the air the engine cruises on its own: S/↓ raises the nose, W/↑ lowers it, A/D bank, Shift boosts. To land, nose down gently and pull up just before touchdown; T folds the wings again.
- Flight can climb to **5,000 m above sea level**, well above the outer island mountains.
- Esc twice within 3 s quits (the first press also frees the mouse; click to re-capture).

## The loop

Ride to the glowing ring at the pickup, slow to a stop inside it to load the package onto the rear
rack, then follow the compass (top-left) to the destination ring and stop again to hand it over.
Walking and the cargo truck also support handoffs. Stay grounded and below 2.5 m/s in the
ring for half a second. Coins are awarded once on delivery, and F5/F9 preserves the current
package, job and wallet. Fifteen jobs chain round the island and out into the country: Villa Rosa Office (SW vineyards) → Hilltop Farm (NW massif) → Harbour Cafe
(NE town, over the strait aqueduct) → Dunes Lookout (badlands, over the gorge viaduct) → Lakeside Camp →
Bodega San Marco (the southern vineyards) → the Salinas (salt pans) → Cala Blanca (fishing cove) → the Marble
Quarry and San Telmo Monastery (the northern Highlands, over the mountain pass) → back to the Villa, and on out
over the lagoon bridges: Campo Real (the plains) → Puerto Alto (over the estuary bridge) → Sarmada (the south coast)
→ Isola Serena (over the causeway) → Valdoro (up the switchbacks in the north).
Signposts at each hub and at every outer junction point the way; F6 teleports to the next hub.

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

These are stylized game assets inspired by the supplied references. Residents share
the courier base rig with identity proportions, hair variants and occupation-specific hats, aprons, satchels and spectacles; their occupations are outdoor activity
stations with timed work cycles, rather than enterable shops with a production economy.

## Blender assets

The assets were authored through Blender MCP. Editable sources are in `assets/source/`, with
`.gdignore` preventing automatic Blender conversion during game import. Runtime files are
in `assets/models/`. Reproduction scripts are in `tools/blender/`: `common.py`, `bike.py`,
`character.py`, `island_kit.py`, `town_revision.py` and `hero_finish.py`. The new truck is generated by `storybook_truck.py`; `storybook_assets.py` applies a reproducible paint/roughness pass to the other GLBs using archived originals. The palm revision uses `town_revision.py` with broader sage fronds. The generated surface and exact ImageGen prompt are in `assets/storybook/README.md`. They use the project
path at the top of `common.py`; update it when moving the repository. Run the generators
through Blender in that order, with `hero_finish.py` last, then let Godot import the GLBs.

## Automated checks

All checks run inside the booted game through the test runner (`--test=NAME` loads `tests/NAME.gd`):

```
godot --headless --path . -- --autotest --deliveries=10 --maxtime=2800   # drives the whole loop, exits 0 on success
godot --headless --path . -- --test=outer_world_tests           # outer world: data, surface == collision, roads, towns, plots, budgets
godot --headless --path . -s tests/control_regression_tests.gd # analog, buffered/coyote jumps, controls
godot --headless --path . -s tests/third_person_tests.gd       # movement, jump height, slopes, camera obstruction
godot --headless --path . -s tests/bike_dynamics_tests.gd      # suspension, crest airtime, landing and timestep parity
godot --headless --path . -s tests/streaming_budget_tests.gd   # incremental construction and collider ownership
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
python3 world/mapgen/outer_textures.py           # bake meadow / alpine / snow / asphalt / cobble textures
python3 world/mapgen/outer.py                    # generate the outer world into data/outer (~1 min)
godot --headless --path . -- --test=dump_core_exits   # refresh world/mapgen/core_exits.json after changing the core exits
python3 world/mapgen/foliage.py                  # bake the leaf / grass cards in assets/foliage
xvfb-run godot --path . --rendering-driver opengl3 -- --test=view --spots=cliff_coast --out=/tmp/x
python3 reference/compare.py /tmp/x/cliff_coast.png reference/ref_cliff_coast.png   # similarity vs the reference
```

Debug keys in game: **F3** overlay (fps, chunk, loaded chunks, entities per tier, draw calls...),
**F5/F9** quick save/load, **F6** teleport to the next hub, **F7** reload the chunk under you, **F8** toggle streaming.

The latest measured frame rates, controller changes, visual reviews and limitations are in [the performance and controls report](artifacts/performance-controls/README.md).

## Layout

See `ARCHITECTURE.md` for the full picture; `CONTEXT.md` for the domain vocabulary.

- `core/` – `Game` root (boot + wiring), `Events` bus, `Saves`, definitions, utils
- `world/` – `WorldManager`, `WorldDatabase` (recipes per chunk, locations, hubs), `WorldStreamer` + `Chunk`, `Terrain` (heightfield → Terrain3D), `WorldKit` builders, the `Island` generator, `outer/` (the outer world), `mapgen/` (extract, expand, textures, outer)
- `assets/terrain/` – ground textures (seven packed CC0 ambientCG sets + four baked ones; see `assets/CREDITS.md`)
- `assets/rock/`, `assets/trees/` – rock textures and the Quaternius CC0 trees with `leaf.gdshader`
- `reference/` – reference screenshots, brief, camera spots, `compare.py`, per-round critiques and changelogs
- `assets/foliage/` – grass / flower / leaf-clump cards (baked by `world/mapgen/foliage.py`) for the tree canopies and Terrain3D's instancer grass
- `addons/terrain_3d/` – the Terrain3D plugin
- `entities/` – `EntityManager` (ids + simulation tiers), player (`Player`, `Rider`, `RiderModel`), vehicles (`Vehicle` base, `Bike`, `Truck`, `TruckCargo`), camera
- `gameplay/` – `GameplayManager`, `Controls` seam, `DeliverySystem` + `JobDefinition`, `GunSystem`
- `ai/` – `Autopilot`
- `ui/` – `HUD`, `DebugOverlay`
- `data/` – island maps, `outer/` (outer world heights, maps and plan), `config/world.tres`, vehicle definitions (`bike.tres`, `truck.tres`), `jobs/*.tres`
- `tests/` – test nodes and render tools
