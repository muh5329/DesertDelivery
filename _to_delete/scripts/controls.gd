class_name Controls
extends RefCounted
## The ControlIntent seam. Physics modules (Bike, Player, ChaseCamera) never read Input;
## they consume a `Controls.Intent` produced once per physics tick by a `Controls.Source`.
## Two adapters sit at this seam:
##   * `Controls.Keyboard` — reads the keyboard / mouse / gamepad and decides what each key
##                            means in the current mode (Space = handbrake riding, jump on foot;
##                            S = brake on the ground, pull-up at takeoff speed and in the air...).
##   * `Controls.Scripted` — a plain value the Autopilot and the test suites fill in.
## Because both adapters produce the same Intent, the physics is identical for a human,
## the autopilot and a test.


## Everything a rider can ask for in one tick. Analogue values are 0..1 (steer/pitch -1..1);
## `*_pressed` fields are edge-triggered (true for exactly one tick).
class Intent:
	extends RefCounted
	var throttle := 0.0
	var brake := 0.0
	var steer := 0.0          # -1 left .. +1 right
	var pitch := 0.0          # flight: +1 nose up (pull back), -1 nose down
	var boost := false        # flight: full power (Shift)
	var handbrake := false
	var move := Vector2.ZERO  # on foot: x strafe (+ right), y forward (+), camera-relative
	var run := false
	var aim := false          # held
	var look := Vector2.ZERO  # free-look delta this tick (radians): x yaw (+ right), y pitch (+ down)
	var look_back := false
	var jump_pressed := false
	var fire_pressed := false
	var interact_pressed := false
	var wings_pressed := false
	var reset_pressed := false

	func clear_edges() -> void:
		jump_pressed = false; fire_pressed = false; interact_pressed = false
		wings_pressed = false; reset_pressed = false


## What the adapter needs to know to interpret the keys.
class Context:
	extends RefCounted
	var on_foot := false
	var wings_out := false
	var airborne := false
	var at_takeoff_speed := false


class Source:
	extends RefCounted
	func read(_ctx: Context, _delta: float) -> Intent:
		return Intent.new()


## Adapter 1: the real player. Owns every Input.* read in the game (except Esc, which is Main's).
class Keyboard:
	extends Source
	var mouse_sensitivity := 0.0022
	var stick_look_rate := Vector2(2.4, 1.8)
	var _mouse_delta := Vector2.ZERO

	## Feed mouse motion here (from a Node's _unhandled_input); it is consumed on the next read().
	func feed_mouse(relative: Vector2) -> void:
		_mouse_delta += relative

	func read(ctx: Context, delta: float) -> Intent:
		var i := Intent.new()
		var fwd := Input.get_action_strength("accelerate")
		var back := Input.get_action_strength("brake")
		var side := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
		i.run = Input.is_action_pressed("run")
		i.aim = Input.is_action_pressed("aim")
		i.look_back = Input.is_action_pressed("look_back")
		i.jump_pressed = Input.is_action_just_pressed("jump")
		# on foot a click with the mouse free just re-captures it (Main does that); it never fires
		i.fire_pressed = Input.is_action_just_pressed("fire") and not (ctx.on_foot and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
		i.interact_pressed = Input.is_action_just_pressed("interact")
		i.wings_pressed = Input.is_action_just_pressed("transform")
		i.reset_pressed = Input.is_action_just_pressed("reset_bike")
		# free look: mouse (captured) + right stick
		var look := _mouse_delta * mouse_sensitivity
		_mouse_delta = Vector2.ZERO
		var rs := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
		if rs.length() > 0.2:
			look += rs * stick_look_rate * delta
		i.look = look
		if ctx.on_foot:
			i.move = Vector2(side, fwd - back).limit_length(1.0)
			return i
		# riding / flying
		i.steer = side
		i.throttle = fwd
		i.boost = i.run
		if ctx.wings_out:
			# flight-stick convention: pull back (S) raises the nose, push forward (W) lowers it
			if ctx.airborne:
				i.pitch = back - fwd
				i.brake = 0.0
			elif ctx.at_takeoff_speed:
				i.pitch = back        # on the takeoff roll S rotates, it never brakes
				i.brake = 0.0
			else:
				i.brake = back
			i.handbrake = false       # Space is unused with wings out
		else:
			i.brake = back
			i.handbrake = Input.is_action_pressed("handbrake")
		return i


## Adapter 2: scripted control for the Autopilot and the test suites. Set the fields, call
## press() for edge-triggered buttons; read() hands the intent over and clears the edges.
class Scripted:
	extends Source
	var intent := Intent.new()

	func press(button: String) -> void:
		match button:
			"jump": intent.jump_pressed = true
			"fire": intent.fire_pressed = true
			"interact": intent.interact_pressed = true
			"wings": intent.wings_pressed = true
			"reset": intent.reset_pressed = true

	func read(_ctx: Context, _delta: float) -> Intent:
		var out := Intent.new()
		out.throttle = intent.throttle; out.brake = intent.brake; out.steer = intent.steer
		out.pitch = intent.pitch; out.boost = intent.boost; out.handbrake = intent.handbrake
		out.move = intent.move; out.run = intent.run; out.aim = intent.aim
		out.look = intent.look; out.look_back = intent.look_back
		out.jump_pressed = intent.jump_pressed; out.fire_pressed = intent.fire_pressed
		out.interact_pressed = intent.interact_pressed; out.wings_pressed = intent.wings_pressed
		out.reset_pressed = intent.reset_pressed
		intent.clear_edges()
		intent.look = Vector2.ZERO
		return out
