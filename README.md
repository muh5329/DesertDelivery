# Desert Delivery

A small third-person motorbike courier game inspired by *Into the Wind*, set on an island generated from a
reference painting, built in **Godot 4.3** with the GL Compatibility renderer. Everything (terrain, roads, buildings, vegetation, the bike and the
rider) is generated procedurally from GDScript at start-up, so the project has no binary assets.

## Run it

1. Install Godot 4.3 (standard build) from https://godotengine.org/download.
2. Open Godot → **Import** → pick `project.godot` in this folder → **Edit** → press **F5** (Play).
   Or from a terminal: `godot --path /path/to/DesertDelivery`.

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
Four jobs chain across the island: Villa Rosa Office (SW vineyards) → Hilltop Farm (NW massif) → Harbour
Cafe (NE town, over the strait aqueduct) → Dunes Lookout (badlands, over the gorge viaduct) → back to the Villa. Signposts at each hub point the way.

## Automated checks

```
godot --headless --path . -- --autotest --deliveries=4          # drives itself, exits 0 on success
godot --headless --path . -s tools/edge_tests.gd                # brake/reverse, sea reset, camera
godot --headless --path . -s tools/feature_tests.gd             # dismount, swim, pistol, plane
xvfb-run godot --path . --rendering-driver opengl3 -s tools/feature_shots.gd -- --out=/tmp/fshots
xvfb-run godot --path . --rendering-driver opengl3 -- --shots=/tmp/shots --autotest   # + screenshots
godot --path . --rendering-driver opengl3 -s tools/view.gd -- --out=/tmp/view --nofog  # 9 fixed views
godot --headless --path . -s tools/road_dump.gd                                # road profiles / bridges (ROAD=n)
python3 tools/mapgen/extract.py [painting.png]                                 # regenerate data/ from the painting
godot --path . --rendering-driver opengl3 -s tools/bike_view.gd -- --out=/tmp/bike     # bike turntable
```

## Layout

The domain vocabulary (Rider, Mode, ControlIntent, Framing, Hub, Ground) is in `CONTEXT.md`.

- `scripts/main.gd` – entry point and wiring only
- `scripts/rider.gd` – the Rider module: owns the mode (riding / flying / on foot / swimming) and every transition
- `scripts/controls.gd` – the ControlIntent seam: `Controls.Keyboard` (reads input, decides key meaning per mode) and `Controls.Scripted` (autopilot, tests)
- `scripts/hub.gd` – Hub records (centre, ring, walls, bench) published by the level
- `tools/mapgen/extract.py` – turns the reference painting into `data/island_map.png` (height / biome / tree density), `data/sea_depth.png` and `data/island_meta.json`
- `scripts/terrain.gd` – map-driven heightfield: biomes, roads (bridges, viaducts, ramps, grade limit), pads, flat-shaded facet mesh, collision, `probe(pos)` / `nearest_road(pos)`
- `scripts/world_kit.gd` – the building blocks: sky/light, depth-banded sea, rocks, tree / hoodoo kits, houses, walls, piers, boats, arcades, lighthouse
- `scripts/level.gd` – the island layout from the painting: roads in painting pixels, massif, harbour town, hamlet, vineyards, badlands + lake, aqueducts, hubs
- `scripts/bike.gd` – arcade bike physics (CharacterBody3D), `scripts/bike_visual.gd` – bike + rider model
- `scripts/chase_camera.gd` – third-person camera: `follow(target, framing)`, `look(delta)`, `view_ray()`
- `scripts/game_manager.gd` – jobs, pickup / drop-off zones, `scripts/hud.gd` – HUD
- `scripts/player.gd` / `scripts/rider_model.gd` – on-foot controller (walk/run/jump/swim) and the animated boy
- `scripts/gun.gd` – pistol pickup, over-the-shoulder hitscan, tin-can targets
- `scripts/bike_audio.gd` – procedural engine / wind / prop / gunshot audio
- `scripts/autopilot.gd` – road-graph driver used by the verifier
# DesertDelivery
