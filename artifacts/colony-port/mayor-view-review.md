# Mayor view port and independent review

Ported the actual Red Sea Baron MayorView Jobs, Areas, Build and Paths UI into
`ui/mayor_view.gd`, preserving profession assignment, work toggles, resource
circles, workplace previews/blueprints, road/path drawing, erase and undo.
Source project files were only read.

Adaptations use existing DesertDelivery residents and ColonySystem. Entry is F4
through Game, restricted to grounded on-foot mode and no other modal. Save uses
existing F5. Escape/Return closes; PanelStack owns mouse/input restoration and
Game owns player physics/HUD/streaming focus. MayorView restores prior camera
and terrain view camera. A separate map focus allows streaming camera pans
without moving the courier. Bounded resident map markers remain visible even
when distant full character actors are culled around the courier.

The orthographic camera pans within the 25 km terrain and ray projection uses
terrain height queries and bisection rather than requiring streamed colliders.
Mouse presses on UI never begin a world order; releasing a map drag over a
panel cancels it. Large map zoom retains lightweight position markers.

The simulation agent independently reviewed input cancellation and camera
restoration. Their caught terrain API mismatch (`surface_height` versus
`height_at`) was corrected before tests. Reciprocal backend review found
ownership cleanup and route-planning spike risks; the backend agent corrected
ownership and queued route planning.

`mayor-view-tests.log` records the real game headless interaction checks passing:
entry gates, all four actual tab pages, modal/HUD/physics behavior, sidebar
click-through prevention, remote terrain projection, island bounds, camera and
player state restoration, and rejecting overlapping modals. Shutdown emits an
existing procedural-audio `AudioStreamGeneratorPlayback` reference leak, verified
with verbose output; no Mayor UI node leak or runtime script error was found.
The parent agent owns graphical layout review and final integration captures.

Final independent UI source review also accepted the active-only resident
MultiMesh markers: fixed instance count tied to existing residents, no duplicate
actors, and no rendering side effects outside Mayor view. All 18 interaction
checks passed. Root was notified to connect `blocks_world_input()` for the
inactive entry-button click as well as the active modal, avoiding a rejected
mounted-entry click falling through into attack polling.
