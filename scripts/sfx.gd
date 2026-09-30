extends Node
## Procedural sound bank. Every effect is synthesised at start-up: no audio assets.
## `play` uses a small 2D voice pool; `play_at` uses positional voices so distant
## gunfire is quieter and panned. Loops (engine, skid, ambience) are owned by callers.

const RATE: int = 22050

var volume: float = 0.55
var _bank: Dictionary = {}
var _gain: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _voices_3d: Array[AudioStreamPlayer3D] = []
var _next_voice: int = 0
var _next_voice_3d: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1999
	for index: int in range(14):
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	for index: int in range(10):
		var voice_3d: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		voice_3d.unit_size = 14.0
		voice_3d.max_distance = 220.0
		voice_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(voice_3d)
		_voices_3d.append(voice_3d)
	_build_bank()


func _exit_tree() -> void:
	for voice: AudioStreamPlayer in _voices:
		voice.stop()
	for voice_3d: AudioStreamPlayer3D in _voices_3d:
		voice_3d.stop()


func has_sound(sound: String) -> bool:
	return _bank.has(sound)


func stream(sound: String) -> AudioStreamWAV:
	return _bank.get(sound) as AudioStreamWAV


func master_db(extra_db: float = 0.0) -> float:
	return linear_to_db(maxf(volume, 0.0001)) + extra_db


func play(sound: String, pitch: float = 1.0, gain_db: float = 0.0) -> void:
	if not _bank.has(sound) or volume <= 0.001:
		return
	var voice: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = _bank[sound]
	voice.pitch_scale = pitch * _rng.randf_range(0.97, 1.03)
	voice.volume_db = master_db(float(_gain.get(sound, 0.0)) + gain_db)
	voice.play()


func play_at(sound: String, at: Vector3, pitch: float = 1.0, gain_db: float = 0.0) -> void:
	if not _bank.has(sound) or volume <= 0.001:
		return
	var voice: AudioStreamPlayer3D = _voices_3d[_next_voice_3d]
	_next_voice_3d = (_next_voice_3d + 1) % _voices_3d.size()
	voice.global_position = at
	voice.stream = _bank[sound]
	voice.pitch_scale = pitch * _rng.randf_range(0.96, 1.04)
	voice.volume_db = master_db(float(_gain.get(sound, 0.0)) + gain_db)
	voice.play()


func _add(sound: String, samples: PackedFloat32Array, gain_db: float = 0.0, loop: bool = false) -> void:
	_bank[sound] = _wav(samples, loop)
	_gain[sound] = gain_db


func _build_bank() -> void:
	# Weapons: length, lowpass, body decay, thump Hz, thump, tail, tail decay, crack, seed.
	_add("pistol", _gunshot(0.42, 0.42, 30.0, 150.0, 0.55, 0.35, 9.0, 0.55, 11), -3.0)
	_add("smg", _gunshot(0.30, 0.55, 42.0, 190.0, 0.40, 0.25, 12.0, 0.65, 12), -5.0)
	_add("rifle", _gunshot(0.60, 0.36, 26.0, 120.0, 0.70, 0.50, 6.5, 0.80, 13), -2.0)
	_add("shotgun", _gunshot(0.85, 0.22, 16.0, 75.0, 1.00, 0.70, 5.0, 0.60, 14), 0.0)
	_add("marksman", _gunshot(1.10, 0.30, 20.0, 95.0, 0.90, 0.80, 3.8, 1.00, 15), 0.0)
	# Variants: each gun is recognisable by ear (a pop, a boom, a rip, a crack).
	_add("m1911", _gunshot(0.50, 0.34, 24.0, 118.0, 0.75, 0.40, 8.0, 0.50, 51), -2.0)
	_add("revolver", _gunshot(0.85, 0.30, 18.0, 92.0, 1.00, 0.65, 5.0, 0.85, 52), 0.0)
	_add("mac", _gunshot(0.22, 0.62, 55.0, 220.0, 0.32, 0.18, 16.0, 0.55, 53), -6.0)
	_add("tommy", _gunshot(0.40, 0.40, 30.0, 120.0, 0.60, 0.35, 10.0, 0.45, 54), -3.5)
	_add("ak", _gunshot(0.70, 0.32, 22.0, 105.0, 0.85, 0.60, 5.5, 0.90, 55), -1.0)
	_add("double", _gunshot(1.00, 0.20, 13.0, 62.0, 1.00, 0.85, 4.2, 0.55, 56), 1.0)
	_add("auto12", _gunshot(0.75, 0.24, 18.0, 82.0, 0.95, 0.60, 5.5, 0.60, 57), -0.5)
	_add("dmr", _gunshot(0.95, 0.32, 20.0, 100.0, 0.90, 0.75, 4.5, 0.95, 58), 0.0)
	_add("break_open", _mechanical([0.0, 0.09, 0.22], 0.32, 59), -5.0)
	_add("cylinder", _mechanical([0.0, 0.03, 0.06, 0.09], 0.16, 60), -8.0)
	_add("guard_shot", _gunshot(0.55, 0.38, 28.0, 140.0, 0.55, 0.45, 7.0, 0.60, 16), -1.0)
	_add("suppressed", _gunshot(0.28, 0.2, 38.0, 105.0, 0.7, 0.12, 22.0, 0.08, 17), -11.0)
	_add("dry", _click(0.035, 2600.0, 140.0), -10.0)
	_add("mag_out", _mechanical([0.0, 0.07], 0.16, 21), -8.0)
	_add("mag_in", _mechanical([0.0, 0.05, 0.11], 0.2, 22), -6.0)
	_add("pump", _mechanical([0.0, 0.17], 0.3, 23), -4.0)
	_add("bolt", _mechanical([0.0, 0.14, 0.26], 0.36, 24), -5.0)
	_add("shell", _mechanical([0.0, 0.04], 0.12, 25), -8.0)
	_add("draw", _mechanical([0.0], 0.12, 26), -12.0)
	_add("hit", _click(0.06, 2350.0, 70.0), -6.0)
	_add("headshot", _bell([1760.0, 3520.0, 2640.0], 0.32, 12.0), -6.0)
	_add("kill", _sweep(0.2, 900.0, 420.0, 16.0), -4.0)
	_add("steel", _bell([820.0, 1340.0, 2210.0, 3170.0], 0.9, 5.5), -5.0)
	_add("impact", _thud(0.09, 0.30, 60.0, 180.0, 31), -14.0)
	_add("whiz", _whiz(0.2, 32), -6.0)
	_add("hurt", _thud(0.28, 0.12, 14.0, 70.0, 33), 0.0)
	for index: int in range(4):
		_add("step%d" % index, _thud(0.1, 0.16 + index * 0.03, 42.0, 85.0 + index * 12.0, 40 + index), -16.0)
	_add("land", _thud(0.18, 0.12, 26.0, 70.0, 45), -9.0)
	_add("door", _thud(0.22, 0.10, 22.0, 105.0, 46), -3.0)
	_add("crash", _crash(0.6, 47), 0.0)
	_add("horn", _horn(), -4.0, true)
	_add("engine", _engine_loop(), -7.0, true)
	_add("skid", _noise_loop(0.8, 0.5, 0.18, 48), -9.0, true)
	_add("ambience", _ambience_loop(), -17.0, true)
	_add("ui", _click(0.03, 1500.0, 120.0), -14.0)
	_add("cash", _cash(), -8.0)
	_add("ring", _ring(), -4.0)
	_add("deny", _sweep(0.14, 320.0, 240.0, 22.0), -10.0)
	_add("glass", _glass_break(0.7, 61), -3.0)


func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	var peak: float = 0.0001
	for sample: float in samples:
		peak = maxf(peak, absf(sample))
	var gain: float = 0.92 / peak
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for index: int in range(samples.size()):
		data.encode_s16(index * 2, int(clampf(samples[index] * gain, -1.0, 1.0) * 32000.0))
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func _buffer(length: float) -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(int(length * RATE))
	return samples


func _gunshot(length: float, lowpass: float, decay: float, thump_hz: float, thump: float, tail: float, tail_decay: float, crack: float, seed_value: int) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: PackedFloat32Array = _buffer(length)
	var first: float = 0.0
	var second: float = 0.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var noise: float = rng.randf_range(-1.0, 1.0)
		first += (noise - first) * lowpass
		second += (first - second) * lowpass * 0.35
		var body: float = first * exp(-t * decay)
		var snap: float = noise * exp(-t * 190.0) * crack
		var boom: float = sin(TAU * thump_hz * t * (1.0 - t * 0.9)) * exp(-t * 24.0) * thump
		var rumble: float = second * 2.2 * exp(-t * tail_decay) * tail
		var fade: float = clampf((length - t) / 0.04, 0.0, 1.0)
		out[index] = (body + snap + boom + rumble) * fade
	return out


func _click(length: float, frequency: float, decay: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _buffer(length)
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		out[index] = (sin(TAU * frequency * t) + 0.3 * sin(TAU * frequency * 2.01 * t)) * exp(-t * decay)
	return out


func _mechanical(times: Array, length: float, seed_value: int) -> PackedFloat32Array:
	# Short metallic clacks: filtered noise bursts plus a resonant ping per event.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: PackedFloat32Array = _buffer(length)
	var smooth: float = 0.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var noise: float = rng.randf_range(-1.0, 1.0)
		smooth += (noise - smooth) * 0.6
		var value: float = 0.0
		for event_index: int in range(times.size()):
			var local: float = t - float(times[event_index])
			if local >= 0.0:
				var ping: float = sin(TAU * (1900.0 + event_index * 450.0) * local) * 0.5
				value += (smooth + ping) * exp(-local * 95.0)
		out[index] = value
	return out


func _bell(partials: Array, length: float, decay: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _buffer(length)
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var value: float = 0.0
		for partial_index: int in range(partials.size()):
			var frequency: float = float(partials[partial_index])
			value += sin(TAU * frequency * t) * exp(-t * decay * (1.0 + partial_index * 0.45)) / (1.0 + partial_index * 0.6)
		out[index] = value * minf(1.0, t * 400.0)
	return out


func _sweep(length: float, start_hz: float, end_hz: float, decay: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _buffer(length)
	var phase: float = 0.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var frequency: float = lerpf(start_hz, end_hz, t / length)
		phase += frequency / RATE
		out[index] = sin(TAU * phase) * exp(-t * decay) * minf(1.0, t * 300.0)
	return out


func _thud(length: float, lowpass: float, decay: float, thump_hz: float, seed_value: int) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: PackedFloat32Array = _buffer(length)
	var smooth: float = 0.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		smooth += (rng.randf_range(-1.0, 1.0) - smooth) * lowpass
		var boom: float = sin(TAU * thump_hz * t) * exp(-t * decay * 1.2)
		out[index] = (smooth * 1.6 + boom) * exp(-t * decay)
	return out


func _whiz(length: float, seed_value: int) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: PackedFloat32Array = _buffer(length)
	var fast: float = 0.0
	var slow: float = 0.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var noise: float = rng.randf_range(-1.0, 1.0)
		fast += (noise - fast) * 0.55
		slow += (noise - slow) * 0.12
		out[index] = (fast - slow) * sin(PI * t / length) * (1.0 - t / length * 0.5)
	return out


func _crash(length: float, seed_value: int) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: PackedFloat32Array = _buffer(length)
	var smooth: float = 0.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		smooth += (rng.randf_range(-1.0, 1.0) - smooth) * 0.25
		var metal: float = (sin(TAU * 310.0 * t) + sin(TAU * 473.0 * t) * 0.7 + sin(TAU * 1210.0 * t) * 0.3) * exp(-t * 9.0)
		var boom: float = sin(TAU * 55.0 * t) * exp(-t * 12.0)
		out[index] = smooth * 2.0 * exp(-t * 7.0) + metal * 0.4 + boom
	return out


func _horn() -> PackedFloat32Array:
	# 0.1 s holds exactly 40 and 50 cycles, so the loop point is seamless.
	var out: PackedFloat32Array = _buffer(0.1)
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var value: float = sin(TAU * 400.0 * t) + sin(TAU * 500.0 * t) + 0.35 * sin(TAU * 1200.0 * t) + 0.25 * sin(TAU * 1500.0 * t)
		out[index] = clampf(value * 0.9, -1.0, 1.0)
	return out


func _engine_loop() -> PackedFloat32Array:
	# 44 cycles of 55 Hz (0.8 s) with integer harmonics: seamless when looped.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 49
	var base: float = 55.0
	var count: int = int(round(44.0 * RATE / base))
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var smooth: float = 0.0
	for index: int in range(count):
		var t: float = float(index) / RATE
		var cycle: float = t * base
		var pulse: float = pow(0.5 + 0.5 * sin(TAU * cycle * 2.0), 5.0)
		smooth += (rng.randf_range(-1.0, 1.0) - smooth) * 0.3
		var value: float = sin(TAU * cycle) * 0.55 + sin(TAU * cycle * 2.0 + 0.4) * 0.35 + sin(TAU * cycle * 0.5) * 0.4
		value += sin(TAU * cycle * 3.0 + 1.1) * 0.16 + smooth * pulse * 0.5
		out[index] = value
	return out


func _noise_loop(length: float, fast_pole: float, slow_pole: float, seed_value: int) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: PackedFloat32Array = _buffer(length)
	var fast: float = 0.0
	var slow: float = 0.0
	for index: int in range(out.size()):
		var noise: float = rng.randf_range(-1.0, 1.0)
		fast += (noise - fast) * fast_pole
		slow += (noise - slow) * slow_pole
		out[index] = fast - slow
	return _crossfade_loop(out, int(0.08 * RATE))


func _ambience_loop() -> PackedFloat32Array:
	# Low city rumble with a distant traffic swell; crossfaded so the loop never clicks.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 50
	var out: PackedFloat32Array = _buffer(4.0)
	var brown: float = 0.0
	var hiss: float = 0.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		brown = clampf(brown + rng.randf_range(-1.0, 1.0) * 0.04, -1.0, 1.0) * 0.998
		hiss += (rng.randf_range(-1.0, 1.0) - hiss) * 0.08
		out[index] = brown + hiss * 0.25 * (0.6 + 0.4 * sin(TAU * t * 0.25))
	return _crossfade_loop(out, int(0.5 * RATE))


func _crossfade_loop(samples: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	var length: int = samples.size() - fade
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(length)
	for index: int in range(length):
		out[index] = samples[index]
	for index: int in range(fade):
		var blend: float = float(index) / float(fade)
		out[index] = samples[index] * blend + samples[length + index] * (1.0 - blend)
	return out


## An old street payphone: two bursts of a 440/480 Hz bell tone.
## Safety glass letting go: a bright crack, a hiss of crumbs and a scatter of tinkles.
func _glass_break(length: float, seed_value: int) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: PackedFloat32Array = _buffer(length)
	var last: float = 0.0
	var tinkles: Array = []
	for index: int in range(14):
		tinkles.append([rng.randf_range(0.01, length * 0.8), rng.randf_range(2600.0, 6200.0)])
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var noise: float = rng.randf_range(-1.0, 1.0)
		var bright: float = noise - last
		last = noise
		var value: float = bright * exp(-t * 9.0) * 0.7
		for tinkle: Array in tinkles:
			var since: float = t - float(tinkle[0])
			if since > 0.0 and since < 0.12:
				value += sin(TAU * float(tinkle[1]) * since) * exp(-since * 45.0) * 0.35
		out[index] = value
	return out


func _ring() -> PackedFloat32Array:
	var out: PackedFloat32Array = _buffer(1.1)
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var on: bool = t < 0.4 or (t > 0.55 and t < 0.95)
		var tremolo: float = 0.5 + 0.5 * sign(sin(TAU * 20.0 * t))
		out[index] = (sin(TAU * 440.0 * t) + sin(TAU * 480.0 * t)) * tremolo * (1.0 if on else 0.0) * 0.5
	return out


func _cash() -> PackedFloat32Array:
	var out: PackedFloat32Array = _buffer(0.55)
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var value: float = sin(TAU * 1318.5 * t) * exp(-t * 9.0)
		if t > 0.08:
			var late: float = t - 0.08
			value += sin(TAU * 1760.0 * late) * exp(-late * 7.0) + 0.4 * sin(TAU * 2637.0 * late) * exp(-late * 11.0)
		out[index] = value * minf(1.0, t * 500.0)
	return out
