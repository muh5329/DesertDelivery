class_name VehicleDefinition
extends Definition
## Tunables for one kind of vehicle. A Vehicle entity reads these once when it is created, so
## a car, a boat or an NPC's bike is a new .tres, not a new script.
##
## Everything a GroundDrive needs to feel like *this* vehicle lives here. Before the drive was
## extracted these numbers were literals inside Bike._physics_process and Truck._physics_process,
## and they had already drifted apart (slope 5.5 vs 4.5, coast drag 1.2 vs 1.0) with no record of
## whether that was a decision. Now the difference between a bike and a truck is this file.

@export_group("Ground")
@export var max_speed := 27.0          # m/s
@export var reverse_speed := 5.0
@export var accel := 9.5
@export var brake_decel := 16.0
@export var drag := 0.55
@export var drag_quad := 0.012
@export var steer_rate_low := 1.9      # rad/s at standstill
@export var steer_rate_high := 0.75    # rad/s at max speed
@export var gravity := 22.0
@export var wheelbase := 1.5

@export_group("Feel")
## Extra drag while coasting (no throttle, no brake) — the engine-braking fudge.
@export var coast_drag := 1.2
## How hard a slope pushes the vehicle along (m/s² per unit of normal·forward).
@export var slope_gain := 5.5
## Handbrake deceleration (m/s²).
@export var handbrake_decel := 11.0
## Reverse acceleration as a fraction of the motor's forward acceleration.
@export var reverse_accel_scale := 0.5
## Seconds the brake must be held at standstill before reverse engages.
@export var reverse_delay := 0.35
## How fast the steer input catches up: while steering, and while recentring (1/s).
@export var steer_smooth_hold := 3.8
@export var steer_smooth_free := 6.5
## Low stick deflections stay precise while full steering keeps its turning radius.
@export_range(0.0, 1.0) var steering_precision := 0.22
## At cruise, settle steering more gradually to avoid sudden lane changes.
@export_range(0.2, 1.0) var cruise_steer_response := 0.78
@export var throttle_response := 4.5
@export var throttle_release := 8.0
## Speed (m/s) at which steering reaches full authority.
@export var yaw_speed_ref := 1.5
## Yaw multipliers while the handbrake is down, and while airborne.
@export var handbrake_yaw_gain := 1.6
@export var air_yaw_scale := 0.25
## Extra downward velocity that keeps the vehicle stuck to the slope.
@export var ground_snap := 2.0
## Lateral drift: how much slip a hard turn generates, and the speed it scrubs. 0 disables drifting.
@export var drift_gain := 0.9
@export var drift_handbrake_gain := 1.6
@export var drift_scrub := 6.0
## Speed above which dust kicks up.
@export var dust_min_speed := 3.0

@export_group("Impacts")
## Head-on wall hits: how much speed a square hit scrubs, the speed below which hits are ignored,
## and the speed above which a square hit counts as a crash.
@export var scrub_factor := 0.85
@export var scrub_min_speed := 3.0
@export var crash_min_speed := 8.0
## Glancing hits multiply speed by this each tick (1.0 = no scrub).
@export var graze_scrub := 0.985
## Landing impact (m/s) above which speed is scrubbed, and by how much.
@export var hard_landing_impact := 9.0
@export var hard_landing_scale := 0.7

@export_group("Suspension")
## Opt-in wheel spring solver; heavy vehicles retain their existing floor solver.
@export var suspension_enabled := false
@export var suspension_rest_height := .04
@export var wheel_radius := .32
@export var suspension_travel := .20
@export var suspension_spring := 160.0
@export var suspension_damping := 22.0
@export var suspension_max_force := 220.0
@export var tire_grip := 32.0
@export var tire_slide_grip := 12.0

## How fast the ground normal and the body pitch ease toward the wheel rays (1/s).
@export var normal_ease := 10.0
@export var pitch_ease := 9.0
## Airborne nose attitude: gain on vertical velocity, and its limits (rad).
@export var air_pitch_gain := 0.05
@export var air_pitch_min := -0.5
@export var air_pitch_max := 0.35
## Fall back to level attitude when no wheel is touching (light vehicles), instead of holding
## the last measured normal and pitch (heavy ones).
@export var attitude_relaxes := true
## Let the wheel rays report "grounded" when the body itself has just lost floor contact.
@export var ray_ground_assist := true
## Ceiling above the top speed that the drive will let speed reach (collisions, slopes, gravity).
@export var overspeed := 1.16

@export_group("Flight")
@export var can_fly := false
@export var takeoff_speed := 15.0
@export var flight_max_speed := 46.0
@export var flight_thrust := 11.0
@export var ceiling := 5000.0 # Metres above sea level; clears the outer island highlands.

@export_group("Boost")
## A short burst tank (seconds of boost, Shift) that refills on its own — the LegendOfJeep's.
@export var boost_seconds := 0.0
@export var boost_accel := 0.0          # extra m/s² while boosting
@export var boost_top := 1.0            # top-speed multiplier while boosting
@export var boost_refill := 0.35        # seconds of boost regained per second

@export_group("Water")
## Amphibious: floats and planes across water too deep to ford (PlaningDrive), drives back out
## where the bed rises again.
@export var amphibious := false
@export var water_max_speed := 10.0     # m/s planing, flat out
@export var water_accel := 3.0
@export var water_turn_rate := 0.9      # rad/s at planing speed
@export var float_depth := 0.95         # water deeper than this lifts the hull (m)
@export var draught := 0.45             # body origin below the waterline while afloat (m)

@export_group("Towing and fuel")
## Where a towed Cart's drawbar eye sits, in body space (behind the vehicle is +z).
@export var hitch_offset := Vector3(0, 0.55, 1.3)
## Towed mass (kg) that halves the top speed; acceleration falls off faster.
@export var tow_mass_half := 300.0
## A full tank on the level with nothing aboard (m), and the load (kg) that burns a whole extra tank.
@export var tank_range_m := 30000.0
@export var cargo_kg_per_extra_tank := 160.0

@export_group("Look")
@export var body_colour := Color(0.80, 0.16, 0.14)
