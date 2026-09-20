# Validation record

Environment: Godot 4.7, Apple M4 Pro, current project Compatibility renderer.

| Check | Observed result |
| --- | --- |
| Controls regression | 20 assertions passed: analog input, true floor/coyote/buffered jump, steering, reverse inputs |
| Riding feel | 33 assertions passed |
| Features | 31 assertions passed, including swim, pistol, flight |
| Truck | 13 assertions passed, including cargo/winch/wall pull |
| Life | Zero failures after state and wardrobe changes |
| Delivery | Zero failures including callback/save payout regression |
| Journey | Zero failures after guarded job selection/load |
| Architecture | Zero failures, including core-to-north-viaduct navigation |
| World extent | Zero failures, remote visual/query/physics agreement, 25-tile bounds, deterministic dressing reload |
| Storybook materials | Passed bounded cache, idempotent reuse and transparency preservation |
| Automated driving | Two deliveries completed in 91.7 simulation seconds; 1,313 m driven; exit success |
| Blender GLB pipeline | Validated imported steering/wheel/rig names; existing scene and object names preserved during reauthor export |
| Editor import | No new script/resource compilation errors |
| Diff | No whitespace errors |

The automated driving run retains a one-object shutdown leak warning. Existing raw PNG loading and Terrain3D deprecation warnings remain. Export packaging has not been certified. Test passes do not establish AAA art quality or platform-wide performance.

See `autopilot-integration.log`, `benchmark.json`, `performance-review.md` and the independent review reports for direct evidence and limitations.
