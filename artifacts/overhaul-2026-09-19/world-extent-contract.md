# 25 km world extent

The playable world occupies X/Z -12,500 to +12,500 metres (625 km²).
`Terrain.SIZE` is the full extent; `Terrain.CORE_SIZE` is the preserved 1,248 m
painted settlement area. The original 417×417 three-metre map and its metadata
remain authoritative for that area. Buildings, vehicles and people retain metre scale.

The outer island uses a fixed 401×401 height grid (62.5 m spacing), one indexed
mesh, and at most 25 collision tiles around the active rider/vehicle. Collision
and gameplay heights use the exact rendered triangle diagonal. Teleporting moves
the collision window without loading every tile. The sea rim overlaps the core
underwater, including the headless fallback terrain.

A physical nine-metre-wide north viaduct joins the monastery road to the outer
highlands. Its samples are included in the same navigation graph and bridge
support queries as local streets. An integration assertion proves routing from
the original road network to its outer endpoint.

Validation: `tests/world_expanse_tests.gd` raycasts three remote positions and the
viaduct, checks sample and collision budgets and extent. `architecture_tests`
checks the full runtime and core-to-outer AStar connection. Both pass.

Limitations: 25 km describes the square world bounds, including water; the
coastline is irregular. Remote terrain is a coarse wilderness foundation, not
625 km² of authored AAA scenery. Procedural grove, shrub, rock and meadow dressing streams in 320 m tiles around
the courier (25 tiles, one build per frame, at most 63,000 transforms). Meshes
are shared; grass/shrubs cull after 550 m and trees after 1,050 m. Trees are
decorative, without a blanket of physical trunk colliders. Detailed authored
props, scheduled residents and delivery jobs remain concentrated in the original
settlement area. The viaduct provides
access, not a complete remote road or town network. This work does not establish
AAA visual quality.
