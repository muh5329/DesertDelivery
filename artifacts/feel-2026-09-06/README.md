# Into the Wind gameplay reference pass — 6 September 2026

Reference: https://www.youtube.com/watch?v=1jIytCTGk5Y (Into the Wind gameplay overview).
The video was viewed in the browser and its transcript inspected. The main implemented
influences are unhurried cargo choices, weight affecting riding and flight, village fuel
and workshop services, home rest, a composed rear camera, fuller planting and quiet ambience.

## Actual game captures

- `riding.png`: real bike, live HUD and camera on a town road. Normal scripted throttle.
- `lemon-court.png`: streamed courtyard using the new Blender olive asset.
- `courier-counter.png` / `courier-counter-1280.png`: actual interactive counter at two sizes.
  The capture fixture sets168coins and38%fuel to expose service affordances; it does not save progress.

## Verification

- Journey tests:41 checks, including fragile damage and actual payout, optional cargo/load,
  purchases, no overdraft, fuel distance and reserve, rest, save/load, modal input and remote rejection.
- Riding tests:17 checks. Three-second launch:37.6m empty,24.8m with80kg,
  33.1m with80kg and level3engine. Brake20m/s to stop in10.9m; depleted groundfuel2.2m/s.
  Loaded takeoff threshold, depletion glide, camera wall retraction and60/120Hz smoothing also pass.
- Complete road-driving test:10 deliveries,6,889m,522.6simulation seconds, 5 automated reset recoveries.
  The test driver now detects circling without waypoint progress and replans after recovery.
- Delivery, resident grounding/traffic, streaming/save architecture, flight/on-foot and truck
  regressions pass. Logs are retained here.

This remains an interpretation using simpler procedural geometry. It does not reproduce the
trailer’s authored cinematics, pirate encounters, weather events, interiors or animation quality.
