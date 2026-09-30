extends SceneTree
## Procedural sound bank (scripts/sfx.gd): every legacy name still exists, new names exist, streams
## are non-empty with peaks <= 1.0, loops are looped and seamless, the bank is deterministic
## (identical checksum on rebuild and on a second instance), far shot variants are duller and longer,
## distance selection, reverb spaces, and playback calls don't crash.
## Run: godot --headless --path . --script res://tests/sfx_audio.gd
## Set SFX_DUMP=1 to also write every sound to work/audio/<name>.wav (git-ignored) for listening.

const SfxScript = preload("res://scripts/sfx.gd")

## Every name the game called before the audio pass (must never disappear).
const LEGACY: PackedStringArray = [
	"ak", "ambience", "auto12", "bolt", "break_open", "cash", "crash", "cylinder", "deny", "dmr", "door",
	"double", "draw", "dry", "engine", "glass", "guard_shot", "headshot", "hit", "horn", "hurt", "impact",
	"kill", "land", "m1911", "mac", "mag_in", "mag_out", "marksman", "pistol", "pump", "revolver", "rifle",
	"ring", "shell", "shotgun", "skid", "smg", "steel", "step0", "step1", "step2", "step3", "suppressed",
	"tommy", "ui", "whiz",
]
const GUNS: PackedStringArray = [
	"pistol", "m1911", "revolver", "smg", "mac", "tommy", "rifle", "ak", "marksman", "dmr", "shotgun",
	"double", "auto12", "guard_shot", "suppressed",
]
const NEW_NAMES: PackedStringArray = [
	"slide", "safety", "holster", "club_bass", "room_tone", "dog_far", "siren_far",
]
const LOOPS: PackedStringArray = ["horn", "engine", "skid", "ambience", "club_bass", "room_tone"]
const HANDLING: PackedStringArray = [
	"dry", "mag_out", "mag_in", "pump", "bolt", "shell", "draw", "break_open", "cylinder", "slide", "safety", "holster",
]

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _samples(wav: AudioStreamWAV) -> PackedFloat32Array:
	var count: int = wav.data.size() / 2
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	for index: int in range(count):
		out[index] = float(wav.data.decode_s16(index * 2)) / 32768.0
	return out


func _peak(samples: PackedFloat32Array) -> float:
	var peak: float = 0.0
	for sample: float in samples:
		peak = maxf(peak, absf(sample))
	return peak


func _rms(samples: PackedFloat32Array) -> float:
	var energy: float = 0.0
	for sample: float in samples:
		energy += sample * sample
	return sqrt(energy / maxf(float(samples.size()), 1.0))


## Mean |x[n]-x[n-1]| over mean |x|: higher is brighter (more high-frequency content).
func _brightness(samples: PackedFloat32Array) -> float:
	var diff: float = 0.0
	var level: float = 0.0001
	for index: int in range(1, samples.size()):
		diff += absf(samples[index] - samples[index - 1])
		level += absf(samples[index])
	return diff / level


func _run() -> void:
	var sfx: Node = SfxScript.new()
	root.add_child(sfx)
	await process_frame
	print("bank build: %.0f ms" % sfx.get("build_ms"))

	for sound: String in LEGACY:
		_check(sfx.has_sound(sound), "legacy sound exists: " + sound)
	for sound: String in GUNS:
		_check(sfx.has_sound(sound + "_far"), "far variant exists: " + sound + "_far")
	for sound: String in NEW_NAMES:
		_check(sfx.has_sound(sound), "new sound exists: " + sound)
	_check(not sfx.has_sound("no_such_sound"), "has_sound is false for an unknown name")
	_check(sfx.stream("no_such_sound") == null, "stream() of an unknown name is null")

	# Every weapon sound the game can request is present, with a far twin.
	var source: String = FileAccess.get_file_as_string("res://scripts/player.gd")
	var pattern: RegEx = RegEx.new()
	pattern.compile("\"sound\":\\s*\"(\\w+)\"")
	var seen: int = 0
	for found: RegExMatch in pattern.search_all(source):
		var weapon_sound: String = found.get_string(1)
		seen += 1
		_check(sfx.has_sound(weapon_sound) and sfx.has_sound(weapon_sound + "_far"), "player.gd weapon sound bank entry: " + weapon_sound)
	_check(seen >= 10, "player.gd lists at least 10 weapon sounds (%d)" % seen)

	# Streams: non-empty, 16-bit mono, peak <= 1.0, no NaN.
	var total_seconds: float = 0.0
	var names: Array = sfx.sound_names()
	var all_finite: bool = true
	var peak_over: String = ""
	var empty_named: String = ""
	var format_bad: String = ""
	for sound: String in names:
		var wav: AudioStreamWAV = sfx.stream(sound)
		if wav == null or wav.data.size() < 64:
			empty_named += sound + " "
			continue
		if wav.mix_rate != 22050 or wav.format != AudioStreamWAV.FORMAT_16_BITS or wav.stereo:
			format_bad += sound + " "
		var samples: PackedFloat32Array = _samples(wav)
		if _peak(samples) > 1.0:
			peak_over += sound + " "
		for sample: float in samples:
			if is_nan(sample) or is_inf(sample):
				all_finite = false
				break
		total_seconds += float(samples.size()) / 22050.0
	_check(empty_named == "", "no empty streams %s" % empty_named)
	_check(peak_over == "", "every peak <= 1.0 %s" % peak_over)
	_check(format_bad == "", "all mono 16-bit 22.05 kHz %s" % format_bad)
	_check(all_finite, "no NaN/inf samples")
	print("bank: %d sounds, %.1f s of audio, %.1f MB" % [names.size(), total_seconds, total_seconds * 22050.0 * 2.0 / 1048576.0])
	_check(absf(total_seconds - float(sfx.bank_seconds())) < 0.01, "bank_seconds() matches the streams")
	_check(total_seconds < 110.0, "total audio under 110 s (%.1f)" % total_seconds)
	_check(float(sfx.get("build_ms")) < 4000.0, "bank builds in under 4 s (%.0f ms)" % float(sfx.get("build_ms")))

	# Loops.
	for sound: String in LOOPS:
		var wav: AudioStreamWAV = sfx.stream(sound)
		var samples: PackedFloat32Array = _samples(wav)
		_check(wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and wav.loop_begin == 0 and wav.loop_end == samples.size(), "loop mode set over the whole clip: " + sound)
	for sound: String in ["ambience", "club_bass", "room_tone", "skid"]:
		var samples: PackedFloat32Array = _samples(sfx.stream(sound))
		var delta: float = 0.0
		for index: int in range(1, samples.size()):
			delta = maxf(delta, absf(samples[index] - samples[index - 1]))
		var seam: float = absf(samples[0] - samples[samples.size() - 1])
		_check(seam <= delta * 1.5 + 0.01, "loop seam is no bigger than the clip's own steps: %s (%.3f vs %.3f)" % [sound, seam, delta])
	_check(sfx.duration("ambience") >= 8.0, "ambience is a long bed (>= 8 s)")
	_check(absf(sfx.duration("club_bass") - 8.0 * 60.0 / 124.0) < 0.01, "club_bass is exactly 8 beats at 124 BPM")
	for sound: String in GUNS:
		_check(sfx.stream(sound).loop_mode == AudioStreamWAV.LOOP_DISABLED, "gun is one-shot: " + sound)

	# Guns: dense and boomy near, duller and longer far.
	for sound: String in GUNS:
		var near: PackedFloat32Array = _samples(sfx.stream(sound))
		var far: PackedFloat32Array = _samples(sfx.stream(sound + "_far"))
		_check(_brightness(far) < _brightness(near), "far shot is duller than near: %s (%.2f < %.2f)" % [sound, _brightness(far), _brightness(near)])
		_check(sfx.duration(sound + "_far") > sfx.duration(sound), "far shot has a longer tail: " + sound)
		_check(_rms(near) > 0.10, "shot is dense/gritty (rms %.2f): %s" % [_rms(near), sound])
		_check(_brightness(near) < 1.6, "shot is not a hiss (brightness %.2f): %s" % [_brightness(near), sound])
	var heavy: float = _brightness(_samples(sfx.stream("double")))
	var light: float = _brightness(_samples(sfx.stream("mac")))
	_check(heavy < light, "a 12-gauge is darker than a MAC-10 (%.2f < %.2f)" % [heavy, light])
	_check(sfx.duration("double") > sfx.duration("mac") * 2.0, "a 12-gauge rings much longer than a MAC-10")
	var distinct: Dictionary = {}
	for sound: String in GUNS:
		distinct[sfx.stream(sound).data.slice(0, 2000).hex_encode()] = true
	_check(distinct.size() == GUNS.size(), "every gun has its own waveform (%d unique)" % distinct.size())

	# Handling: short, noise-led (broadband) and never silent.
	for sound: String in HANDLING:
		var samples: PackedFloat32Array = _samples(sfx.stream(sound))
		_check(sfx.duration(sound) <= 0.5 and _rms(samples) > 0.04, "handling click is short and audible: %s (%.2f s, rms %.2f)" % [sound, sfx.duration(sound), _rms(samples)])
		_check(_brightness(samples) > 0.35, "handling sound is broadband, not a pure tone: %s (%.2f)" % [sound, _brightness(samples)])

	# Distance selection and playback.
	_check(sfx.shot_sound("pistol", 10.0) == "pistol", "near shot within range")
	_check(sfx.shot_sound("pistol", 200.0) == "pistol_far", "far shot beyond range")
	_check(sfx.shot_sound("whiz", 500.0) == "whiz", "sounds without a far twin never change")
	_check(sfx.shot_sound("pistol", SfxScript.FAR_SHOT_DISTANCE - 0.1) == "pistol" and sfx.shot_sound("pistol", SfxScript.FAR_SHOT_DISTANCE) == "pistol_far", "threshold is exact")
	sfx.play("pistol")
	sfx.play("bolt", 1.0, -3.0)
	sfx.play("no_such_sound")
	sfx.play_at("rifle", Vector3(10, 1, 10))
	sfx.play_shot_at("ak", Vector3(0, 1, 0), Vector3(0, 1, 100))
	sfx.play_shot_at("ak", Vector3(0, 1, 0), Vector3(0, 1, 5), 1.0, -2.0)
	sfx.play_shot_at("no_such_gun", Vector3.ZERO, Vector3.ONE)
	await process_frame
	_check(true, "play/play_at/play_shot_at run without errors")
	_check(is_equal_approx(float(sfx.master_db(0.0)), linear_to_db(float(sfx.get("volume")))), "master_db follows volume")

	# Reverb spaces.
	var bus: int = AudioServer.get_bus_index("SfxSpace")
	_check(bus >= 0, "SfxSpace bus exists")
	if bus >= 0:
		var reverb: AudioEffectReverb = AudioServer.get_bus_effect(bus, 0) as AudioEffectReverb
		_check(reverb != null, "SfxSpace carries a reverb")
		if reverb != null:
			sfx.set_space("outdoor")
			var outdoor_wet: float = reverb.wet
			sfx.set_space("indoor")
			_check(reverb.wet > outdoor_wet and sfx.current_space() == "indoor", "indoor is wetter than outdoor")
			sfx.set_space("bogus")
			_check(sfx.current_space() == "indoor", "unknown space ignored")
			sfx.set_space("outdoor")

	# Determinism: rebuilding, and a second instance, give byte-identical banks.
	var first_sum: int = int(sfx.bank_checksum())
	sfx.rebuild()
	var second_sum: int = int(sfx.bank_checksum())
	_check(first_sum == second_sum, "rebuild gives an identical bank (checksum %d)" % first_sum)
	var twin: Node = SfxScript.new()
	root.add_child(twin)
	_check(int(twin.bank_checksum()) == first_sum, "a second instance builds the same bank")
	# Lazy (idle-built) sounds are the same whether built on demand or in bulk.
	var lazy_only: Node = SfxScript.new()
	root.add_child(lazy_only)
	var direct: PackedByteArray = (lazy_only.stream("rifle_far") as AudioStreamWAV).data
	_check(direct == (sfx.stream("rifle_far") as AudioStreamWAV).data, "on-demand far shot equals bulk-built far shot")

	if OS.get_environment("SFX_DUMP") != "":
		var dir: String = ProjectSettings.globalize_path("res://work/audio")
		DirAccess.make_dir_recursive_absolute(dir)
		for sound: String in sfx.sound_names():
			(sfx.stream(sound) as AudioStreamWAV).save_to_wav(dir + "/" + sound + ".wav")
		print("wrote %d WAVs to %s" % [sfx.sound_names().size(), dir])

	print("SFX AUDIO RESULT: %d checks, %d failures" % [checks, failures])
	twin.queue_free()
	lazy_only.queue_free()
	sfx.queue_free()
	quit(1 if failures > 0 else 0)
