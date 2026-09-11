class_name Controls
extends RefCounted
## The ControlIntent seam. Physics modules (GroundDrive, Player) never read Input; they consume
## a `Controls.Intent` produced once per physics tick by a `Controls.Source`.
##
## The seam runs one way. A `Source` turns a device into a `Reading` — what the player is
## *doing*: axes, look, and which actions were pressed this tick. A `Scheme`, owned by whatever
## is being controlled, turns that Reading into an Intent — what it *means* here: S is a brake
## on the ground, a pull-up at takeoff speed, and pitch in the air; Space is a handbrake on the
## bike, a jump on foot, and "place this tetromino" in the truck's cargo rack.
##
## That is the inversion. The Keyboard used to be handed a Context describing the vehicle
## (wings_out, airborne, at_takeoff_speed, driving_truck, cargo_build_mode) so it could decide
## those meanings itself — vehicle state flowing backwards through the seam every tick, and the
## truck's Tetris mode reaching all the way into the key reader. Now the Bike's meanings live on
## the Bike and the Truck's on the Truck, and a new vehicle brings its own Scheme with it.
##
## Two adapters produce Intents, so the physics is identical for a human, the autopilot and a test:
##   * `Controls.Keyboard` — the real device. The only reader of `Input.*` in the game.
##   * `Controls.Scripted` — a plain value the Autopilot and the test suites fill in.


# --- named commands ---------------------------------------------------------------------------
## Edge-triggered commands. Adding a control means a name here and one line in one Scheme —
## it used to mean editing Intent, clear_edges, Keyboard, Context and two halves of Scripted.
const JUMP := &"jump"
const FIRE := &"fire"
const INTERACT := &"interact"
const WINGS := &"wings"
const RESET := &"reset"
const WINCH := &"winch"
const CARGO_MODE := &"cargo"
const CARGO_PLACE := &"place_cargo"
const CARGO_ROTATE := &"rotate_cargo"
const CARGO_REMOVE := &"remove_cargo"

## Every device action a Reading carries. One list, read once per tick.
const ACTIONS: Array[StringName] = [
	&"accelerate", &"brake", &"steer_left", &"steer_right", &"handbrake", &"jump", &"fire",
	&"interact", &"transform", &"reset_bike", &"winch", &"cargo_mode", &"cargo_rotate",
	&"cargo_remove",
]


## Everything a courier can ask for in one tick. Analogue values are 0..1 (steer/pitch -1..1);
## commands are edge-triggered — true for exactly one tick.
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
	var cargo_move := Vector2i.ZERO
	var commands: Dictionary = {}

	func press(command: StringName) -> void:
		commands[command] = true

	func pressed(command: StringName) -> bool:
		return bool(commands.get(command, false))

	func clear_edges() -> void:
		commands.clear()
		cargo_move = Vector2i.ZERO

	## A field-for-field copy. Reflection rather than a hand-written list, because the list was
	## the thing most likely to silently drop a newly added field.
	func copy() -> Intent:
		var out := Intent.new()
		for p in get_property_list():
			if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
			var v: Variant = get(p.name)
			out.set(p.name, v.duplicate() if v is Dictionary else v)
		return out


## What the device is doing, before anything has decided what it means.
class Reading:
	extends RefCounted
	var forward := 0.0
	var back := 0.0
	var side := 0.0           # -1 left .. +1 right
	var run := false
	var aim := false
	var look_back := false
	var look := Vector2.ZERO
	var held: Dictionary = {}
	var pressed: Dictionary = {}
	var mouse_captured := true

	func just(action: StringName) -> bool:
		return bool(pressed.get(action, false))

	func down(action: StringName) -> bool:
		return bool(held.get(action, false))


## How the thing being controlled wants the device read. The Rider hands the active Scheme to
## the Source every tick; the Source never learns what wings or a cargo rack are.
class Scheme:
	extends RefCounted
	func map(_r: Reading, _i: Intent) -> void:
		pass


## On foot: the boy walks, runs, jumps, aims and fires.
class Foot:
	extends Scheme
	func map(r: Reading, i: Intent) -> void:
		i.move = Vector2(r.side, r.forward - r.back).limit_length(1.0)
		if r.just(&"jump"): i.press(JUMP)
		# A click with the mouse free just re-captures it (Game does that); it never fires.
		if r.just(&"fire") and r.mouse_captured: i.press(FIRE)


class Source:
	extends RefCounted
	func read(_scheme: Scheme, _delta: float) -> Intent:
		return Intent.new()


## Adapter 1: the real player. Owns every Input.* read in the game (except Esc, which is Game's).
class Keyboard:
	extends Source
	var blocked := false
	var mouse_sensitivity := 0.0022
	var stick_look_rate := Vector2(2.4, 1.8)
	var _mouse_delta := Vector2.ZERO

	## Feed mouse motion here (from a Node's _unhandled_input); it is consumed on the next read().
	func feed_mouse(relative: Vector2) -> void:
		_mouse_delta += relative

	func read(scheme: Scheme, delta: float) -> Intent:
		var i := Intent.new()
		if blocked:
			_mouse_delta = Vector2.ZERO
			return i
		var r := _device(delta)
		i.run = r.run
		i.aim = r.aim
		i.look_back = r.look_back
		i.look = r.look
		# Two commands mean the same thing whatever you are sitting on.
		if r.just(&"interact"): i.press(INTERACT)
		if r.just(&"reset_bike"): i.press(RESET)
		if scheme: scheme.map(r, i)
		return i

	func _device(delta: float) -> Reading:
		var r := Reading.new()
		r.forward = Input.get_action_strength("accelerate")
		r.back = Input.get_action_strength("brake")
		r.side = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
		r.run = Input.is_action_pressed("run")
		r.aim = Input.is_action_pressed("aim")
		r.look_back = Input.is_action_pressed("look_back")
		r.mouse_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		for a in ACTIONS:
			r.held[a] = Input.is_action_pressed(a)
			r.pressed[a] = Input.is_action_just_pressed(a)
		# free look: mouse (captured) + right stick
		var look := _mouse_delta * mouse_sensitivity
		_mouse_delta = Vector2.ZERO
		var rs := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
		if rs.length() > 0.2:
			look += rs * stick_look_rate * delta
		r.look = look
		return r


## Adapter 2: scripted control for the Autopilot and the test suites. Set the fields, call
## press() for commands; read() hands the intent over and clears the edges.
class Scripted:
	extends Source
	var intent := Intent.new()

	func press(command: String) -> void:
		intent.press(StringName(command))

	func read(_scheme: Scheme, _delta: float) -> Intent:
		var out := intent.copy()
		intent.clear_edges()
		intent.look = Vector2.ZERO
		return out
