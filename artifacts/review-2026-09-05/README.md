# Island revision review

These are actual Godot captures, not target mockups. Blender sources and exported models
are in `assets/source` and `assets/models`.

- `town-street.png`, `lemon-court.png`: blue shutters/domes, terrace houses, continuous paving and courtyard planting.
- `catalogue.png`, `catalogue-1280.png`: functioning parchment journal at two viewport sizes.
- `resident-at-work.png`, `traffic.png`: actual grounded worker and driven compact cars.
- `bike-and-rider.png`: new articulated motorcycle/courier assets in the studio viewer.

Validation: delivery transactions, repeated-load safety, grounded handoffs, resident schedules,
road-corridor bounds, junction yielding, collision bodies, UI focus and note persistence pass.
The ten-job autopilot completes in506.8 simulated seconds over6,904m; it used seven existing
reset recoveries around obstacles, so this is not evidence of flawless autonomous driving.
Architecture, feature, truck and edge suites pass. Godot4.7 Forward+ with Vulkan on macOS
renders the final game; Metal produced intermittent crashes/black town frames in this session.

Current limits: residents share the courier base mesh with palette/size variants; work uses
outdoor activity stations and timed cycles. There are no enterable shop interiors or production
economy. The references guide this simplified art pass; their full visual fidelity and terrain
composition have not been reproduced. Existing Terrain3D deprecation and exit leak warnings
are recorded in the logs.
