class_name WorldConfig
extends Definition
## World-level tunables: streaming grid and the generation seed.

@export var chunk_size := 60.0         # metres per streaming chunk
@export var stream_radius := 3         # chunks loaded around the focus (3 -> 7x7)
@export var unload_margin := 1         # chunks beyond the radius kept alive (hysteresis)
@export var chunks_per_frame := 1      # build budget: chunks instantiated per frame
@export var seed := 2026
@export var full_tier_radius := 100.0  # entity simulation tiers by distance to the focus
@export var reduced_tier_radius := 300.0
@export var abstract_tier_radius := 1000.0
