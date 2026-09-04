class_name BikeAudio
extends Node
## Procedural engine + wind audio (no sound assets): an AudioStreamGenerator fed each frame
## with a low thumping single-cylinder tone whose pitch follows speed / throttle, plus wind noise
## that grows with speed. Cheap enough to run in GDScript at 22 kHz.

var bike: Bike
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _rate := 22050.0
var _rng := RandomNumberGenerator.new()
var _wind_lp := 0.0
var _rpm := 0.0
var enabled := true
var _shot := 0.0
var _shot_env := 0.0
var _park_mix := 1.0


func play_shot() -> void:
	_shot = 1.0


func setup(p_bike: Bike) -> void:
	bike = p_bike
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _rate
	gen.buffer_length = 0.12
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.volume_db = -8.0
	add_child(_player)
	_player.play()
	var pb := _player.get_stream_playback()
	if pb is AudioStreamGeneratorPlayback:
		_playback = pb
	else:
		enabled = false


func _process(delta: float) -> void:
	if not enabled or _playback == null or bike == null:
		return
	var sf := clampf(absf(bike.speed) / (bike.flight_max_speed if bike.airborne else bike.max_speed), 0.0, 1.0)
	var target_rpm := 0.16 + sf * 0.84 + bike.throttle * 0.10
	if bike.parked:
		target_rpm = 0.0
	_rpm = lerpf(_rpm, target_rpm, clampf(4.0 * delta, 0.0, 1.0))
	var freq := 28.0 + _rpm * 95.0
	_park_mix = move_toward(_park_mix, 0.0 if bike.parked else 1.0, delta * 2.5)   # engine fades out/in
	var eng_gain := (0.22 + _rpm * 0.25 + bike.throttle * 0.08) * _park_mix
	var wind_gain := sf * sf * 0.35 * _park_mix
	if bike.wings_out:
		freq *= 1.6      # prop whine
		eng_gain *= 0.8
	var frames := _playback.get_frames_available()
	frames = mini(frames, 2048)
	var inc := freq / _rate
	for i in range(frames):
		_phase += inc
		if _phase >= 1.0: _phase -= 1.0
		# thumpy single-cylinder: pulse train softened + 2nd/3rd harmonics
		var p := _phase
		var pulse := exp(-p * 9.0) * 1.6 - 0.15
		var eng := pulse * 0.6 + sin(p * TAU * 2.0) * 0.25 + sin(p * TAU * 3.0) * 0.12
		var n := _rng.randf_range(-1.0, 1.0)
		_wind_lp += (n - _wind_lp) * 0.08
		var s := eng * eng_gain + _wind_lp * wind_gain * 2.2
		if _shot > 0.001:
			# gunshot: sharp noise burst with a fast exponential tail
			s += n * _shot * 0.9
			_shot *= 0.9993
		s = clampf(s, -0.9, 0.9)
		_playback.push_frame(Vector2(s, s))
