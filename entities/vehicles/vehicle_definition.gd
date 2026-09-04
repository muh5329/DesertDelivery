class_name VehicleDefinition
extends Definition
## Tunables for one kind of vehicle. A Vehicle entity reads these once when it is created, so
## a car, a boat or an NPC's bike is a new .tres, not a new script.

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
@export_group("Flight")
@export var can_fly := false
@export var takeoff_speed := 15.0
@export var flight_max_speed := 46.0
@export var flight_thrust := 11.0
@export var ceiling := 170.0
@export_group("Look")
@export var body_colour := Color(0.80, 0.16, 0.14)
