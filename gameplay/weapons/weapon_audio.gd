class_name WeaponAudio
extends Node
## Every combat sound, synthesised once at boot into small PCM samples (no audio assets):
## the Garand's crack and its tail, the en-bloc clip's "ping" (bright inharmonic partials between
## 2.5 and 4.5 kHz ringing down), the clip going in, the bolt slamming home, a dry click, the
## bandits' lever rifles and revolvers, near-miss whizzes, hit/kill ticks and the low-health
## heartbeat. Played through small pools of 2D / 3D players.
##
##   play(name, at = null, volume_db = 0, pitch = 1)   `at` a Vector3 plays it positioned

const RATE := 22050
static var _samples: Dictionary = {}

var _pool2d: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _next2d := 0
var _next3d := 0
var _rng := RandomNumberGenerator.new()
## Every play() call, newest last (tests and the HUD's "ping" feedback read it).
var history: Array[StringName] = []


func _ready() -> void:
	if _samples.is_empty(): WeaponAudio.synthesise()
	for i in range(6):
		var p := AudioStreamPlayer.new(); p.bus = &"Master"; add_child(p); _pool2d.append(p)
	for i in range(14):
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 9.0
		p.max_distance = 420.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 0.8
		add_child(p); _pool3d.append(p)


func play(sound: StringName, at: Variant = null, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	history.append(sound)
	if history.size() > 64: history.remove_at(0)
	var s: AudioStreamWAV = _samples.get(sound)
	if s == null: return
	if at is Vector3:
		var p := _pool3d[_next3d]; _next3d = (_next3d + 1) % _pool3d.size()
		p.stream = s; p.volume_db = volume_db; p.pitch_scale = pitch
		if p.is_inside_tree():
			p.global_position = at
			p.play()
	else:
		var p := _pool2d[_next2d]; _next2d = (_next2d + 1) % _pool2d.size()
		p.stream = s; p.volume_db = volume_db; p.pitch_scale = pitch
		if p.is_inside_tree(): p.play()


func has_played(sound: StringName) -> bool:
	return history.has(sound)


# ================================================================================ synthesis
static func synthesise() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 1936
	_samples[&"garand_shot"] = _wav(_shot(rng, 1.1, 1.0, 62.0, 0.9))
	_samples[&"lever_shot"] = _wav(_shot(rng, 0.9, 0.8, 80.0, 0.7))
	_samples[&"pistol_shot"] = _wav(_shot(rng, 0.6, 0.65, 110.0, 0.5))
	_samples[&"ping"] = _wav(_ping(rng))
	_samples[&"clip_in"] = _wav(_clip_in(rng))
	_samples[&"bolt"] = _wav(_bolt(rng))
	_samples[&"dry"] = _wav(_click(rng, 0.08, [1850.0, 3400.0], 0.012, 0.35))
	_samples[&"hit"] = _wav(_click(rng, 0.07, [1900.0, 2850.0], 0.02, 0.45))
	_samples[&"kill"] = _wav(_kill(rng))
	_samples[&"whiz"] = _wav(_whiz(rng))
	_samples[&"heartbeat"] = _wav(_heartbeat())
	_samples[&"lever"] = _wav(_click(rng, 0.25, [900.0, 1650.0, 2600.0], 0.03, 0.5, 0.11))
	_samples[&"pickup"] = _wav(_pickup())
	_samples[&"thud"] = _wav(_thud(rng))


static func _wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray(); data.resize(buf.size() * 2)
	var peak := 0.0001
	for v in buf: peak = maxf(peak, absf(v))
	var g := minf(1.0, 0.92 / peak)
	for i in range(buf.size()):
		data.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array(); b.resize(int(seconds * RATE))
	return b


## A rifle report: a supersonic crack (white noise, 3 ms), the muzzle boom (a decaying low
## sine with a pitch drop) and a filtered noise tail that reads as the shot rolling away.
static func _shot(rng: RandomNumberGenerator, seconds: float, crack: float, boom_hz: float, tail: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var lp := 0.0; var lp2 := 0.0
	var ph := 0.0
	for i in range(b.size()):
		var t := float(i) / RATE
		var n := rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.35
		lp2 += (n - lp2) * 0.04
		var s := n * crack * exp(-t / 0.004)
		s += lp * 0.9 * exp(-t / 0.035)
		ph += TAU * boom_hz * (1.0 + 1.5 * exp(-t / 0.02)) / RATE
		s += sin(ph) * 0.8 * exp(-t / 0.09)
		s += lp2 * tail * 3.0 * exp(-t / (seconds * 0.32)) * (1.0 - exp(-t / 0.02))
		b[i] = s
	return b


## The en-bloc clip leaving the receiver: a spring-steel strip struck hard. Inharmonic partials
## at 2.5-4.5 kHz, the highest dying fastest, a slight shimmer from two close partials beating.
static func _ping(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(1.25)
	var partials := [[2530.0, 0.55, 0.42], [2552.0, 0.25, 0.40], [3180.0, 0.50, 0.30], [3710.0, 0.40, 0.22], [4460.0, 0.28, 0.14], [1270.0, 0.10, 0.10]]
	for i in range(b.size()):
		var t := float(i) / RATE
		var s := 0.0
		for p in partials:
			s += sin(TAU * p[0] * t) * p[1] * exp(-t / p[2])
		s *= 1.0 - exp(-t / 0.0008)
		s += rng.randf_range(-1.0, 1.0) * 0.5 * exp(-t / 0.003)
		b[i] = s
	return b


static func _click(rng: RandomNumberGenerator, seconds: float, freqs: Array, decay: float, noise: float, second_at: float = -1.0) -> PackedFloat32Array:
	var b := _buf(seconds)
	for i in range(b.size()):
		var t := float(i) / RATE
		var s := 0.0
		for k in range(2 if second_at > 0.0 else 1):
			var tt := t - (second_at * k)
			if tt < 0.0: continue
			var env := exp(-tt / decay)
			for f in freqs: s += sin(TAU * float(f) * tt) * env * 0.4
			s += rng.randf_range(-1.0, 1.0) * noise * exp(-tt / (decay * 0.3))
		b[i] = s
	return b


## Clip pressed into the magazine: a scrape, then the snap of the clip latch.
static func _clip_in(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(0.35)
	var lp := 0.0
	for i in range(b.size()):
		var t := float(i) / RATE
		var n := rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.2
		var s := lp * 0.5 * (smoothstep(0.0, 0.03, t) - smoothstep(0.08, 0.14, t))
		var tt := t - 0.15
		if tt > 0.0:
			s += (sin(TAU * 2100.0 * tt) * 0.5 + sin(TAU * 3350.0 * tt) * 0.3 + n * 0.6) * exp(-tt / 0.018)
		b[i] = s
	return b


## The bolt slamming home: a heavy metallic clack with a low body thunk.
static func _bolt(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(0.4)
	for i in range(b.size()):
		var t := float(i) / RATE
		var n := rng.randf_range(-1.0, 1.0)
		var s := n * 0.9 * exp(-t / 0.006)
		s += (sin(TAU * 1180.0 * t) * 0.5 + sin(TAU * 2060.0 * t) * 0.35 + sin(TAU * 3320.0 * t) * 0.25) * exp(-t / 0.045)
		s += sin(TAU * 170.0 * t) * 0.6 * exp(-t / 0.06)
		b[i] = s
	return b


static func _kill(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(0.22)
	for i in range(b.size()):
		var t := float(i) / RATE
		var s := sin(TAU * 1500.0 * t) * exp(-t / 0.03) * 0.5
		if t > 0.07: s += sin(TAU * 2250.0 * (t - 0.07)) * exp(-(t - 0.07) / 0.05) * 0.5
		s += rng.randf_range(-1.0, 1.0) * 0.2 * exp(-t / 0.004)
		b[i] = s
	return b


## A bullet passing close: band-limited noise swelling and dropping in pitch.
static func _whiz(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(0.28)
	var lp := 0.0; var hp := 0.0; var prev := 0.0
	for i in range(b.size()):
		var t := float(i) / RATE
		var n := rng.randf_range(-1.0, 1.0)
		var k := lerpf(0.6, 0.12, t / 0.28)
		lp += (n - lp) * k
		hp = lp - prev; prev = lp
		var env := sin(clampf(t / 0.28, 0.0, 1.0) * PI) * exp(-t / 0.2)
		b[i] = hp * env * 3.0
	return b


static func _heartbeat() -> PackedFloat32Array:
	var b := _buf(0.5)
	for i in range(b.size()):
		var t := float(i) / RATE
		var s := sin(TAU * 52.0 * t) * exp(-t / 0.05) * (1.0 - exp(-t / 0.005))
		var t2 := t - 0.17
		if t2 > 0.0: s += sin(TAU * 46.0 * t2) * 0.7 * exp(-t2 / 0.06) * (1.0 - exp(-t2 / 0.005))
		b[i] = s
	return b


static func _pickup() -> PackedFloat32Array:
	var b := _buf(0.35)
	for i in range(b.size()):
		var t := float(i) / RATE
		var s := sin(TAU * 880.0 * t) * exp(-t / 0.08) * 0.5
		if t > 0.09: s += sin(TAU * 1320.0 * (t - 0.09)) * exp(-(t - 0.09) / 0.1) * 0.5
		b[i] = s
	return b


static func _thud(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(0.3)
	var lp := 0.0
	for i in range(b.size()):
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
		b[i] = (lp * 2.0 + sin(TAU * 90.0 * t) * 0.6) * exp(-t / 0.06)
	return b
