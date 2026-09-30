extends Node
## Procedural sound bank. Every effect is synthesised at start-up: no audio assets.
## `play` uses a small 2D voice pool; `play_at` uses positional voices so distant
## gunfire is quieter and panned. Loops (engine, skid, ambience) are owned by callers.
##
## Audio pass (see docs/AUDIO_PASS.md): every firearm is a layered synth (transient crack,
## blast body, pitch-dropping thump, mechanical action tick, urban slap-back echoes) plus a
## "<name>_far" variant (low-passed, no crack, long rolling tail). `play_shot_at` picks near or
## far by distance. Extra loops `club_bass` and `room_tone` and one-shots `dog_far` and
## `siren_far` are exposed for ambient zones. All synthesis is seeded: every peer builds an
## identical bank (`bank_checksum`).

const RATE: int = 22050
## Beyond this many metres a shot uses the "_far" sample.
const FAR_SHOT_DISTANCE: float = 55.0
const SPACE_BUS: String = "SfxSpace"
## The saturated shots are about 8 dB hotter (RMS) than the old ones; this keeps the mix level.
const GUN_TRIM_DB: float = -6.0
## Reverb send per acoustic space; `set_space` applies one to gunfire voices.
const SPACES: Dictionary = {
	"outdoor": {"room": 0.30, "damp": 0.65, "wet": 0.05, "pre": 24.0},
	"alley": {"room": 0.62, "damp": 0.45, "wet": 0.20, "pre": 14.0},
	"indoor": {"room": 0.42, "damp": 0.40, "wet": 0.28, "pre": 8.0},
	"hall": {"room": 0.85, "damp": 0.30, "wet": 0.34, "pre": 22.0},
}

var volume: float = 0.55
var _bank: Dictionary = {}
var _gain: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _voices_3d: Array[AudioStreamPlayer3D] = []
var _next_voice: int = 0
var _next_voice_3d: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _guns: Array[String] = []
var _spatial: Dictionary = {}
var _space: String = "outdoor"
var _space_ready: bool = false
var build_ms: float = 0.0
## Sounds synthesised on demand (or one per frame at idle): far shots and far one-shots.
var _lazy: Dictionary = {}


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
	rebuild()
	set_process(not _lazy.is_empty())
	_setup_space_bus()
	set_space(_space)


func _exit_tree() -> void:
	for voice: AudioStreamPlayer in _voices:
		voice.stop()
	for voice_3d: AudioStreamPlayer3D in _voices_3d:
		voice_3d.stop()


## Rebuilds the whole bank from scratch (deterministic: same bytes every time).
func rebuild() -> void:
	var started: int = Time.get_ticks_usec()
	_bank.clear()
	_lazy.clear()
	_gain.clear()
	_guns.clear()
	_spatial.clear()
	_build_bank()
	build_ms = float(Time.get_ticks_usec() - started) / 1000.0


func has_sound(sound: String) -> bool:
	return _bank.has(sound) or _lazy.has(sound)


func stream(sound: String) -> AudioStreamWAV:
	_ensure(sound)
	return _bank.get(sound) as AudioStreamWAV


## Idle-time build: one deferred sound per frame after boot so nothing hitches mid-fight.
func _process(_delta: float) -> void:
	if _lazy.is_empty():
		set_process(false)
		return
	_ensure(str(_lazy.keys()[0]))


func _ensure(sound: String) -> void:
	if not _lazy.has(sound):
		return
	var entry: Array = _lazy[sound]
	_lazy.erase(sound)
	var builder: Callable = entry[0]
	_bank[sound] = _wav(builder.call() as PackedFloat32Array, bool(entry[1]), float(entry[2]))


func _ensure_all() -> void:
	for sound: String in _lazy.keys():
		_ensure(sound)


func master_db(extra_db: float = 0.0) -> float:
	return linear_to_db(maxf(volume, 0.0001)) + extra_db


## Sorted list of every sound name in the bank.
func sound_names() -> Array:
	_ensure_all()
	var names: Array = _bank.keys()
	names.sort()
	return names


## Per-sound level hint in dB (what `play` adds); callers of `stream()` may use it.
func gain_hint(sound: String) -> float:
	return float(_gain.get(sound, 0.0))


func duration(sound: String) -> float:
	var wav: AudioStreamWAV = stream(sound)
	return 0.0 if wav == null else float(wav.data.size()) / 2.0 / float(RATE)


func bank_seconds() -> float:
	_ensure_all()
	var total: float = 0.0
	for sound: String in _bank:
		total += duration(sound)
	return total


## Order-independent checksum of every sample byte, for determinism checks.
func bank_checksum() -> int:
	_ensure_all()
	var sum: int = 0
	for sound: String in _bank:
		sum = (sum + hash(sound) * 31 + hash((_bank[sound] as AudioStreamWAV).data)) & 0x7FFFFFFFFFFF
	return sum


func play(sound: String, pitch: float = 1.0, gain_db: float = 0.0) -> void:
	_ensure(sound)
	if not _bank.has(sound) or volume <= 0.001:
		return
	var voice: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = _bank[sound]
	voice.pitch_scale = pitch * _rng.randf_range(0.97, 1.03)
	voice.volume_db = master_db(float(_gain.get(sound, 0.0)) + gain_db)
	voice.bus = _bus_for(sound)
	voice.play()


func play_at(sound: String, at: Vector3, pitch: float = 1.0, gain_db: float = 0.0) -> void:
	_ensure(sound)
	if not _bank.has(sound) or volume <= 0.001:
		return
	var voice: AudioStreamPlayer3D = _voices_3d[_next_voice_3d]
	_next_voice_3d = (_next_voice_3d + 1) % _voices_3d.size()
	voice.global_position = at
	voice.stream = _bank[sound]
	voice.pitch_scale = pitch * _rng.randf_range(0.96, 1.04)
	voice.volume_db = master_db(float(_gain.get(sound, 0.0)) + gain_db)
	voice.bus = _bus_for(sound)
	voice.play()


## Which sample plays for a shot heard `distance` metres away: the near sample, or its
## "_far" variant beyond FAR_SHOT_DISTANCE (falls back to the near sample if none exists).
func shot_sound(weapon: String, distance: float) -> String:
	var far_name: String = weapon + "_far"
	if distance >= FAR_SHOT_DISTANCE and has_sound(far_name):
		return far_name
	return weapon


## Positional gunshot: picks near/far by distance to the listener (camera / local player).
func play_shot_at(weapon: String, at: Vector3, listener: Vector3, pitch: float = 1.0, gain_db: float = 0.0) -> void:
	var distance: float = at.distance_to(listener)
	var sound: String = shot_sound(weapon, distance)
	if not has_sound(sound):
		sound = weapon
	play_at(sound, at, pitch, gain_db)


## Footstep sample name for a surface ("concrete", "wood", "metal", "carpet", "grass") and variant 0-3.
## Unknown surfaces fall back to the legacy concrete-ish `step0-3`.
func step_sound(surface: String, variant: int) -> String:
	var name: String = "step_%s%d" % [surface, posmod(variant, 4)]
	if has_sound(name):
		return name
	return "step%d" % posmod(variant, 4)


## Plays a footstep with a random variant for `surface`.
func play_step(surface: String = "concrete", gain_db: float = 0.0, pitch: float = 1.0) -> void:
	play(step_sound(surface, _rng.randi() % 4), pitch * _rng.randf_range(0.94, 1.06), gain_db)


## Selects the reverb applied to gunfire/crash/glass voices: "outdoor", "alley", "indoor", "hall".
func set_space(space: String) -> void:
	if not SPACES.has(space):
		return
	_space = space
	if not _space_ready:
		return
	var index: int = AudioServer.get_bus_index(SPACE_BUS)
	if index < 0 or AudioServer.get_bus_effect_count(index) == 0:
		return
	var reverb: AudioEffectReverb = AudioServer.get_bus_effect(index, 0) as AudioEffectReverb
	if reverb == null:
		return
	var config: Dictionary = SPACES[space]
	reverb.room_size = float(config["room"])
	reverb.damping = float(config["damp"])
	reverb.wet = float(config["wet"])
	reverb.dry = 1.0
	reverb.predelay_msec = float(config["pre"])


func current_space() -> String:
	return _space


func _setup_space_bus() -> void:
	var index: int = AudioServer.get_bus_index(SPACE_BUS)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, SPACE_BUS)
		AudioServer.set_bus_send(index, "Master")
		AudioServer.add_bus_effect(index, AudioEffectReverb.new())
	_space_ready = AudioServer.get_bus_effect_count(index) > 0 and AudioServer.get_bus_effect(index, 0) is AudioEffectReverb


func _bus_for(sound: String) -> StringName:
	if _space_ready and _spatial.has(sound):
		return SPACE_BUS
	return &"Master"


func _add(sound: String, samples: PackedFloat32Array, gain_db: float = 0.0, loop: bool = false, target_rms: float = 0.0) -> void:
	_bank[sound] = _wav(samples, loop, target_rms)
	_gain[sound] = gain_db


## A firearm: near sample plus "<name>_far". Both play through the reverb-space bus.
func _add_lazy(sound: String, builder: Callable, gain_db: float, loop: bool = false, target_rms: float = 0.0) -> void:
	_lazy[sound] = [builder, loop, target_rms]
	_gain[sound] = gain_db


func _add_gun(sound: String, profile: Dictionary, gain_db: float) -> void:
	gain_db += GUN_TRIM_DB
	_add(sound, _shot(profile, false), gain_db)
	_add_lazy(sound + "_far", func() -> PackedFloat32Array: return _shot(profile, true), gain_db - 3.0)
	_guns.append(sound)
	_spatial[sound] = true
	_spatial[sound + "_far"] = true


## Gun profile. Length includes the slap-back tail. `extra` may override crack_decay,
## boom_decay, act (action tick level), act_at (s) and slap (echo taps: [delay s, gain, tone]).
func _p(length: float, lowpass: float, decay: float, thump_hz: float, thump: float, tail: float, tail_decay: float, crack: float, seed_value: int, extra: Dictionary = {}) -> Dictionary:
	var profile: Dictionary = {
		"len": length, "lp": lowpass, "decay": decay, "hz": thump_hz, "thump": thump,
		"tail": tail, "tail_decay": tail_decay, "crack": crack, "seed": seed_value,
		"crack_decay": 650.0, "boom_decay": 15.0, "sub": 0.8, "grit": 0.4, "drive": 2.4, "act": 0.10, "act_at": 0.05,
		"slap": [[0.07, 0.26, 0.35], [0.15, 0.13, 0.25]],
	}
	profile.merge(extra, true)
	return profile


func _build_bank() -> void:
	var handgun_slap: Array = [[0.07, 0.26, 0.35], [0.15, 0.13, 0.25]]
	var smg_slap: Array = [[0.05, 0.22, 0.4], [0.11, 0.11, 0.3]]
	var rifle_slap: Array = [[0.09, 0.32, 0.3], [0.19, 0.18, 0.22], [0.33, 0.09, 0.18]]
	var big_slap: Array = [[0.10, 0.36, 0.26], [0.22, 0.21, 0.2], [0.38, 0.11, 0.16]]
	# Handguns: crisp crack, small body, slide tick.
	_add_gun("pistol", _p(0.50, 0.42, 30.0, 150.0, 0.55, 0.35, 9.0, 0.55, 11, {"slap": handgun_slap, "act": 0.11}), -3.0)
	_add_gun("m1911", _p(0.58, 0.34, 24.0, 118.0, 0.80, 0.40, 8.0, 0.50, 51, {"slap": handgun_slap, "act": 0.14, "act_at": 0.055, "crack_decay": 560.0}), -2.0)
	_add_gun("revolver", _p(0.95, 0.30, 18.0, 92.0, 1.00, 0.65, 5.0, 0.90, 52, {"slap": big_slap, "act": 0.0, "crack_decay": 480.0, "boom_decay": 13.0}), 0.0)
	# Submachine guns: shorter, rattlier, higher.
	_add_gun("smg", _p(0.34, 0.55, 42.0, 190.0, 0.40, 0.25, 12.0, 0.65, 12, {"slap": smg_slap, "crack_decay": 850.0, "act": 0.14, "act_at": 0.04}), -5.0)
	_add_gun("mac", _p(0.26, 0.62, 55.0, 220.0, 0.32, 0.18, 16.0, 0.60, 53, {"slap": smg_slap, "crack_decay": 950.0, "act": 0.18, "act_at": 0.035}), -6.0)
	_add_gun("tommy", _p(0.46, 0.40, 30.0, 120.0, 0.65, 0.35, 10.0, 0.45, 54, {"slap": smg_slap, "crack_decay": 520.0, "act": 0.16, "act_at": 0.045}), -3.5)
	# Rifles: hard crack with a sizzle, deep body, long street slap.
	_add_gun("rifle", _p(0.72, 0.36, 26.0, 120.0, 0.70, 0.50, 6.5, 0.85, 13, {"slap": rifle_slap, "crack_decay": 430.0, "act": 0.10, "act_at": 0.06}), -2.0)
	_add_gun("ak", _p(0.80, 0.32, 22.0, 105.0, 0.85, 0.60, 5.5, 0.95, 55, {"slap": rifle_slap, "crack_decay": 380.0, "act": 0.16, "act_at": 0.055}), -1.0)
	_add_gun("marksman", _p(1.25, 0.30, 20.0, 95.0, 0.90, 0.80, 3.8, 1.05, 15, {"slap": big_slap, "crack_decay": 340.0, "act": 0.0}), 0.0)
	_add_gun("dmr", _p(1.05, 0.32, 20.0, 100.0, 0.90, 0.75, 4.5, 1.00, 58, {"slap": big_slap, "crack_decay": 360.0, "act": 0.06, "act_at": 0.07}), 0.0)
	# Shotguns: big low blast, noisy body, wide slap.
	_add_gun("shotgun", _p(0.98, 0.22, 16.0, 75.0, 1.00, 0.70, 5.0, 0.60, 14, {"slap": big_slap, "crack_decay": 300.0, "boom_decay": 11.0, "sub": 1.0, "act": 0.0}), 0.0)
	_add_gun("double", _p(1.12, 0.20, 13.0, 62.0, 1.05, 0.85, 4.2, 0.55, 56, {"slap": big_slap, "crack_decay": 280.0, "boom_decay": 9.0, "sub": 1.1, "act": 0.0}), 1.0)
	_add_gun("auto12", _p(0.86, 0.24, 18.0, 82.0, 0.95, 0.60, 5.5, 0.60, 57, {"slap": big_slap, "crack_decay": 340.0, "boom_decay": 12.0, "sub": 0.9, "act": 0.12, "act_at": 0.08}), -0.5)
	_add_gun("guard_shot", _p(0.68, 0.38, 28.0, 140.0, 0.55, 0.45, 7.0, 0.65, 16, {"slap": rifle_slap, "act": 0.08}), -1.0)
	# Suppressed: a dull "thup" with the action clacking louder than the shot.
	_add_gun("suppressed", _p(0.34, 0.20, 38.0, 105.0, 0.70, 0.12, 22.0, 0.10, 17, {"slap": [[0.05, 0.12, 0.2]], "crack_decay": 900.0, "boom_decay": 22.0, "grit": 0.1, "drive": 1.6, "act": 0.55, "act_at": 0.022}), -11.0)
	# Handling: clacks, slides, thunks, clicks and brass, timed like the real actions.
	_add("dry", _handling([[0.0, "click", 2700.0, 0.9], [0.020, "clack", 1500.0, 0.30]], 0.10, 21), -10.0)
	_add("mag_out", _handling([[0.0, "click", 3100.0, 0.55], [0.035, "slide", 0.12, 0.30], [0.16, "clack", 1300.0, 0.45]], 0.26, 22), -8.0)
	_add("mag_in", _handling([[0.0, "slide", 0.09, 0.28], [0.10, "thunk", 135.0, 0.95], [0.108, "clack", 1700.0, 0.55], [0.14, "click", 2500.0, 0.45]], 0.26, 23), -6.0)
	_add("pump", _handling([[0.0, "clack", 900.0, 0.85], [0.03, "slide", 0.13, 0.40], [0.175, "clack", 1150.0, 1.0], [0.18, "thunk", 150.0, 0.55]], 0.34, 24), -4.0)
	_add("bolt", _handling([[0.0, "clack", 1300.0, 0.70], [0.035, "slide", 0.10, 0.38], [0.17, "slide", 0.08, 0.34], [0.265, "clack", 1000.0, 1.0], [0.30, "click", 2200.0, 0.4]], 0.40, 25), -5.0)
	_add("shell", _handling([[0.0, "brass", 5200.0, 0.60], [0.05, "brass", 4700.0, 0.40], [0.09, "brass", 5600.0, 0.22]], 0.18, 26), -8.0)
	_add("draw", _handling([[0.0, "cloth", 0.10, 0.65], [0.085, "click", 2100.0, 0.35], [0.10, "clack", 1100.0, 0.25]], 0.18, 27), -12.0)
	_add("break_open", _handling([[0.0, "click", 2300.0, 0.6], [0.07, "clack", 800.0, 0.95], [0.10, "slide", 0.08, 0.25], [0.22, "brass", 4900.0, 0.4], [0.30, "brass", 5300.0, 0.25]], 0.42, 28), -5.0)
	_add("cylinder", _handling([[0.0, "click", 1700.0, 0.6], [0.03, "click", 1900.0, 0.6], [0.06, "click", 2100.0, 0.6], [0.09, "click", 2300.0, 0.6], [0.12, "clack", 1400.0, 0.5]], 0.22, 29), -8.0)
	_add("slide", _handling([[0.0, "clack", 1200.0, 0.60], [0.02, "slide", 0.09, 0.40], [0.14, "clack", 1500.0, 1.0], [0.145, "thunk", 170.0, 0.4]], 0.28, 30), -5.0)
	_add("safety", _handling([[0.0, "click", 2000.0, 0.8], [0.03, "clack", 1600.0, 0.4]], 0.10, 31), -11.0)
	_add("holster", _handling([[0.0, "cloth", 0.12, 0.6], [0.11, "thunk", 200.0, 0.5], [0.115, "click", 2000.0, 0.4]], 0.22, 32), -10.0)
	_add("hit", _impact(0.07, 170.0, 0.0, 0.0, 65.0, 66), -6.0)
	_add("headshot", _impact(0.24, 140.0, 2300.0, 0.28, 17.0, 67), -6.0)
	_add("kill", _impact(0.2, 95.0, 0.0, 0.0, 22.0, 68), -4.0)
	_add("steel", _impact(0.7, 210.0, 830.0, 0.32, 8.5, 69), -5.0)
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
	_add("ambience", _ambience_loop(), -17.0, true, AMBIENCE_RMS)
	_add("club_bass", _club_bass_loop(), -14.0, true)
	_add("room_tone", _room_tone_loop(), -22.0, true, 0.05)
	_add_lazy("dog_far", _dog_far, -16.0)
	_add_lazy("siren_far", _siren_far, -18.0)
	_add("ui", _click(0.03, 1500.0, 120.0), -14.0)
	_add("cash", _cash(), -8.0)
	_add("ring", _ring(), -4.0)
	_add("deny", _sweep(0.14, 320.0, 240.0, 22.0), -10.0)
	_add("glass", _glass_break(0.7, 61), -3.0)
	for extra: String in ["glass", "crash", "door"]:
		_spatial[extra] = true
	_build_world_sounds()


## Loop level target so the richer ambience sits where the old rumble did.
const AMBIENCE_RMS: float = 0.26


func _wav(samples: PackedFloat32Array, loop: bool, target_rms: float = 0.0) -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	var peak: float = 0.0001
	var energy: float = 0.0
	for sample: float in samples:
		peak = maxf(peak, absf(sample))
		energy += sample * sample
	var gain: float = 0.92 / peak
	if target_rms > 0.0:
		var rms: float = sqrt(energy / maxf(float(samples.size()), 1.0))
		gain = minf(gain, target_rms / maxf(rms, 0.0001))
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


## Peak-relative tanh soft clip: keeps the crack from spiking over the body, never exceeds 1.
func _soft_clip(samples: PackedFloat32Array, drive: float) -> PackedFloat32Array:
	var peak: float = 0.0001
	for sample: float in samples:
		peak = maxf(peak, absf(sample))
	var scale: float = drive / peak
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(samples.size())
	for index: int in range(samples.size()):
		out[index] = tanh(samples[index] * scale)
	return out


## Layered firearm, gritty and boomy. Near: a click-sharp transient, a high-passed noise crack with
## quantised "grit" noise, blast body, a pitch-dropping thump plus a sub layer with a long decay,
## a noise-based action tick, all driven into a tanh saturator, then heavy street slap-back echoes.
## Far: no crack, everything low-passed, slower onset and a long rolling tail of reflections.
func _shot(profile: Dictionary, far: bool) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(profile["seed"]) + (7000 if far else 0)
	var length: float = float(profile["len"])
	var lowpass: float = float(profile["lp"])
	var decay: float = float(profile["decay"])
	var tail_decay: float = float(profile["tail_decay"])
	var crack: float = float(profile["crack"])
	var thump: float = float(profile["thump"]) * 1.25
	var sub: float = float(profile["sub"]) * thump
	var grit: float = float(profile["grit"])
	var tail: float = float(profile["tail"]) * 1.3
	var hz: float = float(profile["hz"])
	var sub_hz: float = clampf(hz * 0.6, 44.0, 72.0)
	if far:
		length = length * 1.5 + 0.55
		lowpass *= 0.6
		tail_decay *= 0.55
		crack *= 0.18
		grit *= 0.2
		tail *= 1.5
		thump *= 0.9
		sub *= 1.1
	var out: PackedFloat32Array = _buffer(length)
	var first: float = 0.0
	var second: float = 0.0
	var prev_noise: float = 0.0
	var phase: float = 0.0
	var sub_phase: float = 0.0
	# Recursive envelopes: one multiply per sample instead of an exp() call.
	var k_crack: float = exp(-float(profile["crack_decay"]) / RATE)
	var k_body: float = exp(-decay / RATE)
	var k_boom: float = exp(-float(profile["boom_decay"]) / RATE)
	var k_sub: float = exp(-9.0 / RATE)
	var k_tail: float = exp(-tail_decay / RATE)
	var k_pitch: float = exp(-70.0 / RATE)
	var k_grit: float = exp(-140.0 / RATE)
	var e_crack: float = 1.0
	var e_body: float = 1.0
	var e_boom: float = 1.0
	var e_sub: float = 1.0
	var e_tail: float = 1.0
	var e_pitch: float = 1.0
	var e_grit: float = 1.0
	var fade_start: int = out.size() - int(0.05 * RATE)
	var attack_samples: int = int(0.004 * RATE) if far else 0
	for index: int in range(out.size()):
		var noise: float = rng.randf_range(-1.0, 1.0)
		first += (noise - first) * lowpass
		second += (first - second) * lowpass * 0.5
		var bright: float = noise - prev_noise * 0.7
		prev_noise = noise
		var value: float = bright * e_crack * crack + first * e_body
		value += floorf(noise * 3.0) / 3.0 * e_grit * grit
		if index < 3 and not far:
			value += crack * 1.6
		phase += hz * (1.0 + 1.1 * e_pitch) / RATE
		sub_phase += sub_hz / RATE
		value += sin(TAU * phase) * e_boom * thump + sin(TAU * sub_phase) * e_sub * sub
		value += second * 2.2 * e_tail * tail
		if index > fade_start:
			value *= float(out.size() - index) / float(out.size() - fade_start)
		if index < attack_samples:
			value *= float(index) / float(attack_samples)
		out[index] = value
		e_crack *= k_crack
		e_body *= k_body
		e_boom *= k_boom
		e_sub *= k_sub
		e_tail *= k_tail
		e_pitch *= k_pitch
		e_grit *= k_grit
	var taps: Array
	if far:
		# Far-off: the same shot smeared by rooftops, low-passed twice, with rolling echoes.
		out = _one_pole(_one_pole(out, 0.30), 0.30)
		taps = [[0.13, 0.55, 0.18], [0.27, 0.40, 0.14], [0.44, 0.26, 0.12], [0.68, 0.15, 0.10]]
	else:
		_action_tick(out, float(profile["act_at"]), float(profile["act"]), rng)
		taps = profile["slap"]
	# Saturate the dry shot (grit, and the low end fattens), then add the room around it.
	out = _soft_clip(out, float(profile["drive"]) if not far else 1.8)
	out = _echoes(out, taps)
	return _soft_clip(out, 1.4)


## A single-pole low-pass over a whole buffer (coefficient = amount of new input per sample).
func _one_pole(samples: PackedFloat32Array, coefficient: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(samples.size())
	var state: float = 0.0
	for index: int in range(samples.size()):
		state += (samples[index] - state) * coefficient
		out[index] = state
	return out


## Adds delayed, low-passed copies: taps are [delay seconds, gain, tone coefficient].
## Gains are boosted a little so the slap reads as a real street rather than a hint.
func _echoes(dry: PackedFloat32Array, taps: Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = dry.duplicate()
	for tap: Array in taps:
		var delay: int = int(float(tap[0]) * RATE)
		var gain: float = float(tap[1]) * 1.35
		var coefficient: float = float(tap[2])
		var state: float = 0.0
		for index: int in range(delay, out.size()):
			state += (dry[index - delay] - state) * coefficient
			out[index] += state * gain
	return out


## The gun's own mechanics right after the shot: a noise clack (no pitched ping). Metal partials
## sit far under the noise burst and die in a few ms.
func _action_tick(out: PackedFloat32Array, at: float, level: float, rng: RandomNumberGenerator) -> void:
	if level <= 0.0:
		return
	var start: int = int(at * RATE)
	var prev: float = 0.0
	var pitch: float = 1500.0 + rng.randf_range(-200.0, 200.0)
	for index: int in range(start, mini(out.size(), start + int(0.05 * RATE))):
		var local: float = float(index - start) / RATE
		var noise: float = rng.randf_range(-1.0, 1.0)
		var bright: float = noise - prev
		prev = noise
		var metal: float = sin(TAU * pitch * local) + sin(TAU * pitch * 2.63 * local + 1.1) * 0.7 + sin(TAU * pitch * 4.19 * local + 2.3) * 0.5
		out[index] += (bright * 0.8 * exp(-local * 260.0) + metal * 0.22 * exp(-local * 170.0)) * level * 1.4


func _click(length: float, frequency: float, decay: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _buffer(length)
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		out[index] = (sin(TAU * frequency * t) + 0.3 * sin(TAU * frequency * 2.01 * t)) * exp(-t * decay)
	return out


## Weapon handling from timed events: [time s, kind, parameter, gain]. Every kind is noise-led:
## filtered-noise bursts, friction scrapes and thuds, with inharmonic metal partials mixed well
## UNDER the noise and dying in a few ms, so nothing ever reads as a clean beep.
## also: paper (banknote flick / rustle, no tone).
## kinds: click (small sear/latch tick, parameter = brightness Hz), clack (metal-on-metal, Hz),
## thunk (seating thud, Hz), slide (steel friction scrape, parameter = duration s),
## brass (casing tink and bounce, Hz), cloth (leather/cloth, duration s).
func _handling(events: Array, length: float, seed_value: int) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: PackedFloat32Array = _buffer(length)
	for event: Array in events:
		var start: int = int(float(event[0]) * RATE)
		var kind: String = str(event[1])
		var param: float = float(event[2])
		var gain: float = float(event[3])
		var span: float = 0.14
		match kind:
			"slide", "cloth":
				span = param + 0.02
			"thunk":
				span = 0.10
			"click":
				span = 0.03
			"brass":
				span = 0.06
			"paper":
				span = 0.045
		var count: int = mini(out.size() - start, int(span * RATE))
		var low: float = 0.0
		var high_prev: float = 0.0
		var band: float = 0.0
		var partial_a: float = param * rng.randf_range(0.93, 1.07)
		var partial_b: float = param * rng.randf_range(2.4, 2.9)
		var partial_c: float = param * rng.randf_range(3.9, 4.6)
		var phase_b: float = rng.randf_range(0.0, TAU)
		var phase_c: float = rng.randf_range(0.0, TAU)
		for offset: int in range(maxi(count, 0)):
			var local: float = float(offset) / RATE
			var noise: float = rng.randf_range(-1.0, 1.0)
			var value: float = 0.0
			match kind:
				"click":
					# Sear/latch tick: a hard noise transient, a whisper of body underneath.
					var tick: float = (noise - high_prev * 0.5) * exp(-local * 650.0)
					high_prev = noise
					low += (noise - low) * 0.3
					value = tick * 0.9 + low * exp(-local * 260.0) * 0.5
				"clack":
					# Metal on metal: loud noise burst, quiet inharmonic partials, gritty decay.
					var burst: float = (noise - high_prev * 0.6) * exp(-local * 210.0)
					high_prev = noise
					low += (noise - low) * 0.35
					var ring: float = sin(TAU * partial_a * local) * 0.4 + sin(TAU * partial_b * local + phase_b) * 0.3 + sin(TAU * partial_c * local + phase_c) * 0.2
					value = burst * 0.9 + low * exp(-local * 120.0) * 0.5 + ring * exp(-local * 150.0) * 0.35
				"thunk":
					# Seating thud: low-passed noise punch and a short pitch-dropping body.
					low += (noise - low) * 0.16
					value = low * exp(-local * 55.0) * 1.5 + sin(TAU * param * local * (1.0 - local * 2.5)) * exp(-local * 38.0) * 0.6
				"slide":
					# Steel scrape: band-passed noise with a gritty 90 Hz stick-slip texture.
					low += (noise - low) * 0.45
					band += (low - band) * 0.10
					var u: float = local / maxf(param, 0.001)
					var grit: float = 0.55 + 0.45 * sin(TAU * 95.0 * local + sin(TAU * 13.0 * local) * 2.0)
					value = (low - band) * sin(PI * clampf(u, 0.0, 1.0)) * 1.1 * grit
				"brass":
					# Casing tink: noise burst first, inharmonic partials under it.
					var burst: float = (noise - high_prev * 0.5) * exp(-local * 320.0)
					high_prev = noise
					var ring: float = sin(TAU * partial_a * local) * 0.35 + sin(TAU * partial_b * local + phase_b) * 0.25
					value = burst * 0.8 + ring * exp(-local * 200.0) * 0.4 * minf(1.0, local * 1500.0)
				"cloth":
					low += (noise - low) * 0.22
					var u: float = local / maxf(param, 0.001)
					value = low * sin(PI * clampf(u, 0.0, 1.0)) * 1.1
				"paper":
					# Banknote flick: a dry band-passed rustle, no tone at all.
					low += (noise - low) * 0.55
					band += (low - band) * 0.2
					value = (low - band) * exp(-local * 320.0) * 1.6 + (noise - high_prev) * exp(-local * 900.0) * 0.3
					high_prev = noise
			out[start + offset] += value * gain
	return _soft_clip(out, 1.5)


## A noise impact: a hard broadband transient, a low-passed body thud and (optionally) a little
## inharmonic metal ring underneath. Used for hit markers and bullets striking steel.
func _impact(length: float, body_hz: float, metal_hz: float, metal: float, decay: float, seed_value: int) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: PackedFloat32Array = _buffer(length)
	var low: float = 0.0
	var prev: float = 0.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var noise: float = rng.randf_range(-1.0, 1.0)
		low += (noise - low) * 0.2
		var burst: float = (noise - prev * 0.6) * exp(-t * 420.0)
		prev = noise
		var ring: float = 0.0
		if metal > 0.0:
			ring = (sin(TAU * metal_hz * t) * 0.45 + sin(TAU * metal_hz * 1.63 * t + 0.8) * 0.35 + sin(TAU * metal_hz * 2.71 * t + 1.9) * 0.25 + sin(TAU * metal_hz * 3.97 * t + 0.3) * 0.15) * metal * exp(-t * decay)
		var body: float = (low * 1.4 + sin(TAU * body_hz * t * (1.0 - t * 2.0)) * 0.7) * exp(-t * decay * 1.6)
		out[index] = burst + body + ring + low * exp(-t * decay) * 0.6
	return _soft_clip(out, 1.5)


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


## City bed, 10 s, seamless: distant traffic rumble and hiss, one car pass-by, gusting wind,
## harbor water lap against a quay and one very faint far-off siren wail. Slow modulators use whole
## cycles per loop and are crossfaded, so the loop point never clicks.
func _ambience_loop() -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 50
	var span: float = AMBIENCE_SECONDS
	var out: PackedFloat32Array = _buffer(span + 0.6)
	var brown: float = 0.0
	var hiss: float = 0.0
	var pass_fast: float = 0.0
	var pass_slow: float = 0.0
	var wind_fast: float = 0.0
	var wind_slow: float = 0.0
	var lap_fast: float = 0.0
	var lap_slow: float = 0.0
	var siren_phase: float = 0.0
	# Slow modulators are evaluated every 32 samples (a control rate) to keep the build cheap.
	var rumble_mod: float = 1.0
	var hiss_mod: float = 0.0
	var pass_env: float = 0.0
	var wind_mod: float = 0.0
	var lap_env: float = 0.0
	var siren_env: float = 0.0
	var siren_step: float = 0.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		if index & 31 == 0:
			var u: float = fposmod(t, span) / span
			rumble_mod = 0.75 + 0.25 * sin(TAU * 2.0 * u + 0.5)
			hiss_mod = 0.22 * (0.6 + 0.4 * sin(TAU * 3.0 * u))
			pass_env = exp(-pow((u - 0.30) / 0.045, 2.0)) * 0.45
			var gust: float = 0.5 + 0.5 * sin(TAU * 3.0 * u + 1.0)
			wind_mod = (0.3 + 0.7 * gust * gust) * 0.9
			var lap_wave: float = 0.5 + 0.5 * sin(TAU * 4.0 * u)
			lap_wave *= lap_wave
			lap_env = lap_wave * lap_wave * (0.7 + 0.3 * sin(TAU * 7.0 * u + 2.0)) * 0.5
			siren_env = exp(-pow((u - 0.62) / 0.085, 2.0)) * 0.045
			siren_step = (690.0 + 230.0 * sin(TAU * 1.6 * t)) / RATE
		var noise: float = rng.randf_range(-1.0, 1.0)
		var noise_b: float = rng.randf_range(-1.0, 1.0)
		brown = clampf(brown + noise * 0.04, -1.0, 1.0) * 0.998
		hiss += (noise_b - hiss) * 0.08
		pass_fast += (noise_b - pass_fast) * 0.14
		pass_slow += (noise_b - pass_slow) * 0.03
		wind_fast += (noise_b - wind_fast) * 0.05
		wind_slow += (noise_b - wind_slow) * 0.012
		lap_fast += (noise - lap_fast) * 0.24
		lap_slow += (noise - lap_slow) * 0.06
		var value: float = brown * rumble_mod + hiss * hiss_mod + (pass_fast - pass_slow) * pass_env
		value += (wind_fast - wind_slow) * wind_mod + (lap_fast - lap_slow) * lap_env
		siren_phase += siren_step
		if siren_env > 0.0005:
			value += (sin(TAU * siren_phase) + 0.3 * sin(TAU * siren_phase * 2.0)) * siren_env
		out[index] = value
	return _crossfade_loop(out, int(0.6 * RATE))


const AMBIENCE_SECONDS: float = 10.0


## Music heard through a nightclub wall: 124 BPM four-on-the-floor kick, off-beat sub bass, dull
## claps, all low-passed. Exactly 8 beats long and wrapped, so it loops on the beat.
func _club_bass_loop() -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 62
	var beat: float = 60.0 / 124.0
	var count: int = int(round(8.0 * beat * RATE))
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var notes: Array = [55.0, 55.0, 65.41, 49.0]
	for beat_index: int in range(8):
		var start: int = int(round(float(beat_index) * beat * RATE))
		var phase: float = 0.0
		for offset: int in range(int(0.32 * RATE)):
			var local: float = float(offset) / RATE
			phase += (46.0 + 90.0 * exp(-local * 38.0)) / RATE
			out[(start + offset) % count] += sin(TAU * phase) * exp(-local * 11.0) * 1.0
		var bass_start: int = start + int(round(beat * 0.5 * RATE))
		var freq: float = float(notes[beat_index % 4])
		for offset: int in range(int(0.2 * RATE)):
			var local: float = float(offset) / RATE
			var env: float = minf(1.0, local * 220.0) * exp(-local * 7.0)
			out[(bass_start + offset) % count] += (sin(TAU * freq * local) + 0.35 * sin(TAU * freq * 2.0 * local)) * env * 0.55
		if beat_index % 2 == 1:
			var smooth: float = 0.0
			for offset: int in range(int(0.2 * RATE)):
				var local: float = float(offset) / RATE
				smooth += (rng.randf_range(-1.0, 1.0) - smooth) * 0.25
				out[(start + offset) % count] += smooth * exp(-local * 22.0) * 0.5
		for half: int in range(2):
			var hat_start: int = start + int(round(float(half) * beat * 0.5 * RATE))
			var prev: float = 0.0
			for offset: int in range(int(0.04 * RATE)):
				var local: float = float(offset) / RATE
				var noise: float = rng.randf_range(-1.0, 1.0)
				out[(hat_start + offset) % count] += (noise - prev) * exp(-local * 90.0) * 0.12
				prev = noise
	return _one_pole(_one_pole(out, 0.16), 0.22)


## Air handling and mains hum for interiors: 60/120/180 Hz plus a breath of air noise.
func _room_tone_loop() -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 63
	var span: float = 4.0
	var out: PackedFloat32Array = _buffer(span + 0.4)
	var air: float = 0.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var u: float = fposmod(t, span) / span
		air += (rng.randf_range(-1.0, 1.0) - air) * 0.07
		var hum: float = sin(TAU * 60.0 * t) * 0.5 + sin(TAU * 120.0 * t + 0.6) * 0.35 + sin(TAU * 180.0 * t + 1.3) * 0.12
		out[index] = hum * (0.85 + 0.15 * sin(TAU * 2.0 * u)) + air * 1.6 * (0.8 + 0.2 * sin(TAU * 1.0 * u + 1.0))
	return _crossfade_loop(out, int(0.4 * RATE))


## Three muffled barks from a few blocks away.
func _dog_far() -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 64
	var out: PackedFloat32Array = _buffer(1.6)
	var barks: Array = [[0.0, 1.0, 520.0], [0.30, 0.85, 495.0], [0.62, 0.7, 470.0]]
	for bark: Array in barks:
		var start: int = int(float(bark[0]) * RATE)
		var phase: float = 0.0
		for offset: int in range(int(0.15 * RATE)):
			var local: float = float(offset) / RATE
			var u: float = local / 0.15
			var f0: float = float(bark[2]) * (1.0 - 0.3 * u)
			phase += f0 / RATE
			var voice: float = 0.0
			for harmonic: int in range(1, 9):
				var weight: float = exp(-pow((float(harmonic) * f0 - 950.0) / 600.0, 2.0)) + 0.25 * exp(-pow((float(harmonic) * f0 - 2100.0) / 500.0, 2.0))
				voice += sin(TAU * phase * float(harmonic)) * weight / float(harmonic)
			var env: float = minf(1.0, local * 220.0) * exp(-u * 2.6)
			out[start + offset] += (voice + rng.randf_range(-0.15, 0.15)) * env * float(bark[1])
	out = _one_pole(_one_pole(out, 0.32), 0.4)
	return _soft_clip(_echoes(out, [[0.21, 0.30, 0.2], [0.45, 0.16, 0.15]]), 1.2)


## A distant emergency siren wailing through the buildings (2 s up-and-down cycle, fades in and out).
func _siren_far() -> PackedFloat32Array:
	var length: float = 4.0
	var out: PackedFloat32Array = _buffer(length)
	var phase: float = 0.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		phase += (720.0 + 260.0 * sin(TAU * 0.5 * t - 1.2)) / RATE
		var env: float = pow(sin(PI * t / length), 2.0)
		out[index] = (sin(TAU * phase) + 0.4 * sin(TAU * phase * 2.0) + 0.15 * sin(TAU * phase * 3.0)) * env
	out = _one_pole(_one_pole(out, 0.35), 0.5)
	return _soft_clip(_echoes(out, [[0.25, 0.3, 0.2], [0.55, 0.15, 0.15]]), 1.2)


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


## ---- Deal-world sounds (added lazily: built one per frame at idle, or on first use) ----

const STEP_SURFACES: PackedStringArray = ["concrete", "wood", "metal", "carpet", "grass"]
const STEP_GAINS: Array = [-16.0, -17.0, -15.0, -21.0, -17.0]


func _build_world_sounds() -> void:
	# Briefcase, cash, phone handling: noise-led events like the weapon handling above.
	_add_lazy("briefcase_open", func() -> PackedFloat32Array: return _handling([[0.0, "click", 2600.0, 0.95], [0.055, "click", 2900.0, 0.95], [0.12, "slide", 0.17, 0.22], [0.29, "thunk", 165.0, 0.45], [0.30, "clack", 800.0, 0.3]], 0.46, 101), -6.0)
	_add_lazy("briefcase_close", func() -> PackedFloat32Array: return _handling([[0.0, "thunk", 140.0, 0.85], [0.006, "clack", 1100.0, 0.5], [0.085, "click", 2500.0, 0.85], [0.14, "click", 2750.0, 0.85]], 0.28, 102), -6.0)
	_add_lazy("cash_riffle", _cash_riffle, -9.0)
	_add_lazy("cash_bundle", func() -> PackedFloat32Array: return _handling([[0.0, "thunk", 120.0, 0.7], [0.0, "paper", 0.0, 1.1], [0.03, "paper", 0.0, 0.5], [0.07, "paper", 0.0, 0.3]], 0.2, 103), -8.0)
	_add_lazy("phone_pickup", func() -> PackedFloat32Array: return _handling([[0.0, "clack", 700.0, 0.75], [0.03, "slide", 0.09, 0.2], [0.13, "click", 2000.0, 0.7]], 0.28, 104), -8.0)
	_add_lazy("phone_hangup", func() -> PackedFloat32Array: return _handling([[0.0, "thunk", 180.0, 0.65], [0.01, "clack", 900.0, 0.7], [0.045, "click", 1800.0, 0.75], [0.09, "brass", 3800.0, 0.3]], 0.22, 105), -8.0)
	_add_lazy("radio_squelch", _radio_squelch, -10.0)
	# Cars: doors are thumps and latches; the lock chirp is a real tonal device, so it is tonal.
	_add_lazy("car_door_open", func() -> PackedFloat32Array: return _handling([[0.0, "click", 2200.0, 0.85], [0.02, "clack", 900.0, 0.6], [0.075, "slide", 0.15, 0.25], [0.21, "thunk", 120.0, 0.4]], 0.4, 106), -5.0)
	_add_lazy("car_door_close", func() -> PackedFloat32Array: return _handling([[0.0, "thunk", 70.0, 1.2], [0.002, "thunk", 115.0, 0.7], [0.004, "clack", 650.0, 0.8], [0.014, "clack", 1600.0, 0.55], [0.07, "slide", 0.14, 0.12]], 0.36, 107), -3.0)
	_add_lazy("car_chirp", func() -> PackedFloat32Array: return _beeps([0.0, 0.13], 0.065, 2350.0), -18.0)
	_add_lazy("car_unlock", func() -> PackedFloat32Array: return _beeps([0.0], 0.07, 1950.0), -18.0)
	_add_lazy("car_alarm", _car_alarm, -20.0, true)
	_add_lazy("engine_start", _engine_start, -10.0)
	_add_lazy("engine_stall", _engine_stall, -6.0)
	# Payphone tones.
	_add_lazy("phone_dialtone", _dial_tone, -22.0, true)
	_add_lazy("phone_busy", _busy_tone, -22.0, true)
	_add_lazy("phone_dial", func() -> PackedFloat32Array: return _dtmf("5551999"), -20.0)
	# Footsteps per surface, four variants each.
	for surface_index: int in range(STEP_SURFACES.size()):
		for variant: int in range(4):
			var surface: String = STEP_SURFACES[surface_index]
			_add_lazy("step_%s%d" % [surface, variant], func() -> PackedFloat32Array: return _step(surface, variant), float(STEP_GAINS[surface_index]))
	# Ambient beds and one-shots for a city frozen in late 1999.
	_add_lazy("train_horn_far", _train_horn_far, -18.0)
	_add_lazy("neon_buzz", _neon_buzz, -22.0, true, 0.08)
	_add_lazy("rain_awning", _rain_awning, -19.0, true, 0.16)
	_add_lazy("ambience_hush", _hush_loop, -20.0, true, 0.06)


## Riffling a stack of notes: ~26 paper ticks that speed up, then one flat slap.
func _cash_riffle() -> PackedFloat32Array:
	var events: Array = []
	var time: float = 0.0
	var gap: float = 0.032
	for index: int in range(26):
		events.append([time, "paper", 0.0, 0.55 + 0.4 * absf(sin(float(index) * 2.3))])
		time += gap
		gap = maxf(gap * 0.955, 0.014)
	events.append([time + 0.01, "paper", 0.0, 1.0])
	events.append([time + 0.01, "thunk", 130.0, 0.4])
	return _handling(events, time + 0.16, 108)


## Push-to-talk: a burst of band-limited static with a hard leading edge.
func _radio_squelch() -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 109
	var out: PackedFloat32Array = _buffer(0.17)
	var fast: float = 0.0
	var slow: float = 0.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var noise: float = rng.randf_range(-1.0, 1.0)
		fast += (noise - fast) * 0.6
		slow += (noise - slow) * 0.09
		out[index] = (fast - slow) * (exp(-t * 55.0) * 0.7 + exp(-t * 900.0) * 1.2)
	return _soft_clip(out, 1.4)


## Short square-ish beeps (a car's lock confirmation). `times` are start times in seconds.
func _beeps(times: Array, duration: float, frequency: float) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 110
	var last: float = float(times[times.size() - 1]) + duration + 0.05
	var out: PackedFloat32Array = _buffer(last)
	for start_time: float in times:
		var start: int = int(start_time * RATE)
		for offset: int in range(int(duration * RATE)):
			var local: float = float(offset) / RATE
			var env: float = minf(1.0, local * 500.0) * minf(1.0, (duration - local) * 500.0)
			var wave: float = sin(TAU * frequency * local) + sin(TAU * frequency * 3.0 * local) * 0.33 + sin(TAU * frequency * 5.0 * local) * 0.2
			out[start + offset] += (wave * 0.6 + rng.randf_range(-0.12, 0.12)) * env
	return out


## Car alarm whoop: eight harsh 700-1500 Hz rising sweeps in 2.4 s (loops on the sweep).
func _car_alarm() -> PackedFloat32Array:
	var out: PackedFloat32Array = _buffer(2.4)
	var phase: float = 0.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var u: float = fposmod(t, 0.3) / 0.3
		phase += lerpf(700.0, 1500.0, u) / RATE
		var square: float = sign(sin(TAU * phase)) * 0.6 + sin(TAU * phase * 2.0) * 0.25
		out[index] = square * (0.75 + 0.25 * (1.0 - u))
	return _one_pole(out, 0.55)


## Starter motor cranking (noise pulses under a low buzz), a catch and an idle that settles.
func _engine_start() -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 111
	var out: PackedFloat32Array = _buffer(1.9)
	var smooth: float = 0.0
	var phase: float = 0.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var noise: float = rng.randf_range(-1.0, 1.0)
		smooth += (noise - smooth) * 0.2
		var value: float = 0.0
		if t < 0.95:
			# Cranking: ~7 compression pulses a second, slowly speeding up, plus the starter's grind.
			var pulse: float = pow(0.5 + 0.5 * sin(TAU * (6.0 * t + 1.6 * t * t)), 3.0)
			var grind: float = (noise - smooth) * 0.25
			value = (smooth * 1.4 * pulse + grind) * minf(1.0, t * 20.0)
			value += sin(TAU * 95.0 * t) * pulse * 0.25
		else:
			# Catch and idle: firing pulses at ~22 Hz that settle to ~15 Hz with a rev flare on the catch.
			var local: float = t - 0.95
			var rate: float = lerpf(30.0, 15.0, minf(local / 0.6, 1.0))
			phase += rate / RATE
			var fire: float = pow(0.5 + 0.5 * sin(TAU * phase), 4.0)
			var flare: float = exp(-local * 3.0)
			value = smooth * 1.2 * fire * (0.5 + 0.8 * flare) + sin(TAU * phase * 2.0) * 0.4 * (0.5 + flare) + sin(TAU * phase) * 0.35
			value *= minf(1.0, local * 60.0) * minf(1.0, (0.95 - local) / 0.15)
		out[index] = value
	return _soft_clip(out, 1.6)


## Cranking that catches once, coughs, and dies: pulses slow down while the sound decays and ends with a clunk.
func _engine_stall() -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 112
	var out: PackedFloat32Array = _buffer(1.5)
	var smooth: float = 0.0
	var phase: float = 0.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var noise: float = rng.randf_range(-1.0, 1.0)
		smooth += (noise - smooth) * 0.16
		var rate: float = lerpf(17.0, 2.5, clampf(t / 1.2, 0.0, 1.0))
		phase += rate / RATE
		var fire: float = pow(0.5 + 0.5 * sin(TAU * phase), 5.0)
		var level: float = exp(-t * 2.2)
		var value: float = (smooth * 1.3 * fire + sin(TAU * phase * 2.0) * 0.3 * fire) * level
		if t > 1.15:
			var clunk: float = t - 1.15
			value += smooth * exp(-clunk * 60.0) * 0.6 + sin(TAU * 85.0 * clunk) * exp(-clunk * 35.0) * 0.5
		out[index] = value * minf(1.0, (1.5 - t) / 0.05)
	return _soft_clip(out, 1.5)


## North American dial tone: 350 + 440 Hz, exactly 1 s so the loop is seamless.
func _dial_tone() -> PackedFloat32Array:
	var out: PackedFloat32Array = _buffer(1.0)
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		out[index] = (sin(TAU * 350.0 * t) + sin(TAU * 440.0 * t)) * 0.5
	return out


## Busy signal: 480 + 620 Hz, half a second on and half off (2 s loop).
func _busy_tone() -> PackedFloat32Array:
	var out: PackedFloat32Array = _buffer(2.0)
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var gate: float = 1.0 if fposmod(t, 1.0) < 0.5 else 0.0
		var ramp: float = minf(1.0, fposmod(t, 1.0) * 400.0) * minf(1.0, (0.5 - fposmod(t, 1.0)) * 400.0)
		out[index] = (sin(TAU * 480.0 * t) + sin(TAU * 620.0 * t)) * 0.5 * gate * clampf(ramp, 0.0, 1.0)
	return out


## Touch-tone dialing of `digits` (DTMF pairs, 70 ms tones with 55 ms gaps).
func _dtmf(digits: String) -> PackedFloat32Array:
	var rows: Array = [697.0, 770.0, 852.0, 941.0]
	var columns: Array = [1209.0, 1336.0, 1477.0]
	var out: PackedFloat32Array = _buffer(float(digits.length()) * 0.125 + 0.05)
	for position: int in range(digits.length()):
		var digit: int = int(digits.substr(position, 1))
		var row: int = 3 if digit == 0 else (digit - 1) / 3
		var column: int = 1 if digit == 0 else (digit - 1) % 3
		var start: int = int(float(position) * 0.125 * RATE)
		for offset: int in range(int(0.07 * RATE)):
			var local: float = float(offset) / RATE
			var env: float = minf(1.0, local * 800.0) * minf(1.0, (0.07 - local) * 800.0)
			out[start + offset] = (sin(TAU * float(rows[row]) * local) + sin(TAU * float(columns[column]) * local)) * 0.5 * env
	return out


## A footstep on `surface`: heel strike, body thud, scuff; the material sets the character.
func _step(surface: String, variant: int) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 200 + STEP_SURFACES.find(surface) * 10 + variant
	# click level/decay, body low-pass, body Hz, body level/decay, scuff level, ring level, length
	var config: Array
	match surface:
		"wood":
			config = [0.45, 320.0, 0.14, 150.0 + variant * 14.0, 1.0, 32.0, 0.25, 0.0, 0.2]
		"metal":
			config = [1.0, 240.0, 0.22, 110.0 + variant * 9.0, 0.5, 45.0, 0.15, 0.11, 0.3]
		"carpet":
			config = [0.0, 300.0, 0.07, 72.0 + variant * 5.0, 0.8, 55.0, 0.18, 0.0, 0.14]
		"grass":
			config = [0.0, 300.0, 0.3, 80.0, 0.3, 50.0, 0.9, 0.0, 0.24]
		_:
			config = [0.95, 380.0, 0.22, 90.0 + variant * 8.0, 0.9, 42.0, 0.28, 0.0, 0.17]
	var out: PackedFloat32Array = _buffer(float(config[8]))
	var low: float = 0.0
	var prev: float = 0.0
	var band: float = 0.0
	var scuff_at: float = 0.035 + float(variant) * 0.008
	var ring_hz: float = 380.0 + float(variant) * 60.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var noise: float = rng.randf_range(-1.0, 1.0)
		low += (noise - low) * float(config[2])
		var click: float = (noise - prev * 0.6) * exp(-t * float(config[1])) * float(config[0])
		prev = noise
		var body: float = (low * 1.6 + sin(TAU * float(config[3]) * t * (1.0 - t * 1.2))) * exp(-t * float(config[5])) * float(config[4])
		var scuff_local: float = t - scuff_at
		var scuff: float = 0.0
		if scuff_local > 0.0:
			band += (noise - band) * 0.35
			scuff = (band - low) * sin(minf(scuff_local / 0.06, 1.0) * PI * 0.5) * exp(-scuff_local * 30.0) * float(config[6])
			if surface == "grass":
				scuff *= 1.0 + 1.5 * absf(sin(scuff_local * 900.0 + float(variant)))
		var ring: float = 0.0
		if float(config[7]) > 0.0:
			ring = (sin(TAU * ring_hz * t) * 0.5 + sin(TAU * ring_hz * 2.41 * t + 0.7) * 0.35 + sin(TAU * ring_hz * 3.9 * t + 1.9) * 0.2) * exp(-t * 40.0) * float(config[7])
		out[index] = click + body + scuff + ring
	return _soft_clip(out, 1.5)


## A distant locomotive horn: a four-note chord in a long-long-short-long pattern, low-passed by
## distance and smeared by the buildings.
func _train_horn_far() -> PackedFloat32Array:
	var notes: Array = [311.0, 370.0, 415.0, 466.0]
	var blasts: Array = [[0.0, 1.2], [1.45, 1.1], [2.75, 0.45], [3.4, 1.5]]
	var out: PackedFloat32Array = _buffer(6.0)
	# One horn-shaped cycle (fundamental + 2nd + 3rd harmonic) in a table: one lookup per note per sample.
	var table: PackedFloat32Array = PackedFloat32Array()
	table.resize(1024)
	for entry: int in range(1024):
		var angle: float = TAU * float(entry) / 1024.0
		table[entry] = sin(angle) + sin(angle * 2.0) * 0.45 + sin(angle * 3.0) * 0.2
	var phases: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	for blast: Array in blasts:
		var start: int = int(float(blast[0]) * RATE)
		var length: float = float(blast[1])
		for offset: int in range(int(length * RATE)):
			var local: float = float(offset) / RATE
			var env: float = minf(1.0, local / 0.22) * minf(1.0, (length - local) / 0.3)
			var value: float = 0.0
			var detune: float = 1.0 + 0.012 * (1.0 - env)
			for note_index: int in range(4):
				phases[note_index] += float(notes[note_index]) * detune / RATE
				value += table[int(phases[note_index] * 1024.0) & 1023]
			out[start + offset] += value * env * 0.25
	out = _one_pole(_one_pole(out, 0.32), 0.45)
	return _soft_clip(_echoes(out, [[0.28, 0.32, 0.2], [0.6, 0.2, 0.15], [1.05, 0.12, 0.12]]), 1.2)


## Neon tube: 120 Hz mains buzz with harmonics, a hiss of gas, and a slow flicker with crackles.
## 3 s, whole cycles of 120 Hz, so it loops cleanly.
func _neon_buzz() -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 113
	var span: float = 3.0
	var out: PackedFloat32Array = _buffer(span)
	var flickers: Array = [[0.75, 0.05], [1.7, 0.03], [1.78, 0.02], [2.5, 0.06]]
	var prev: float = 0.0
	var dip: float = 0.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var noise: float = rng.randf_range(-1.0, 1.0)
		var sizzle: float = (noise - prev) * 0.12
		prev = noise
		if index & 15 == 0:
			dip = 0.0
			for flicker: Array in flickers:
				var distance: float = absf(t - float(flicker[0]))
				if distance < 0.15:
					dip = maxf(dip, exp(-pow(distance / float(flicker[1]), 2.0)))
		var hum: float = sin(TAU * 120.0 * t) * 0.6 + sin(TAU * 240.0 * t + 0.4) * 0.35 + sin(TAU * 360.0 * t + 1.0) * 0.28 + sin(TAU * 600.0 * t + 2.0) * 0.1
		var crackle: float = noise * dip * 0.5 * (1.0 if rng.randf() < 0.2 else 0.0)
		out[index] = (hum * (1.0 - 0.75 * dip) + sizzle * (1.0 + dip * 3.0)) + crackle
	return out


## Steady rain on a canvas awning: a band of patter, hundreds of small hollow drops and a low
## roar from the street beyond. 8 s, crossfaded.
func _rain_awning() -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 114
	var span: float = 8.0
	var out: PackedFloat32Array = _buffer(span + 0.6)
	var fast: float = 0.0
	var slow: float = 0.0
	var roar: float = 0.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var noise: float = rng.randf_range(-1.0, 1.0)
		fast += (noise - fast) * 0.4
		slow += (noise - slow) * 0.06
		roar += (noise - roar) * 0.015
		var swell: float = 0.85 + 0.15 * sin(TAU * 3.0 * fposmod(t, span) / span + 0.7)
		out[index] = (fast - slow) * 0.45 * swell + roar * 1.2
	var k_drop: float = exp(-260.0 / RATE)
	for drop: int in range(400):
		var start: int = rng.randi_range(0, out.size() - 500)
		var step: float = TAU * rng.randf_range(260.0, 620.0) / RATE
		var level: float = rng.randf_range(0.15, 0.6)
		var env: float = level
		for offset: int in range(400):
			out[start + offset] += (sin(step * float(offset)) * 0.3 + rng.randf_range(-0.7, 0.7)) * env
			env *= k_drop
	return _crossfade_loop(out, int(0.6 * RATE))


## "World paused in time": a very still bed. Two sub tones beating slowly, a breath of air and a
## thin far transformer hum. 6 s of whole cycles (55 Hz, 55.5 Hz, 120 Hz), so it loops cleanly.
func _hush_loop() -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 115
	var span: float = 6.0
	var out: PackedFloat32Array = _buffer(span + 0.5)
	var air: float = 0.0
	for index: int in range(out.size()):
		var t: float = float(index) / RATE
		var u: float = fposmod(t, span) / span
		air += (rng.randf_range(-1.0, 1.0) - air) * 0.03
		var drone: float = sin(TAU * 55.0 * t) * 0.5 + sin(TAU * 55.5 * t + 0.8) * 0.5
		var hum: float = sin(TAU * 120.0 * t + 0.3) * 0.08
		out[index] = drone * 0.5 + hum + air * 2.2 * (0.7 + 0.3 * sin(TAU * 2.0 * u))
	return _crossfade_loop(out, int(0.5 * RATE))
