extends Node

const Codec = preload("res://scripts/voice_codec.gd")
const Relay = preload("res://scripts/voice_relay.gd")
## In-game voice chat (docs/VOICE_CHAT.md). Capture -> noise gate -> ADPCM -> FastNet.send_voice;
## FastNet.voice_frame -> decode -> positional (proximity) or radio (crew) playback.
##
## Proximity is the default and intended way to play: the mic is OPEN (a noise gate keeps silence off
## the wire). Players may opt into push-to-talk for proximity (`proximity_mode = "push_to_talk"`, key
## action `voice_ptt`). Crew radio is always hold-to-talk (`voice_radio`) and reaches only your crew.
## With no microphone, on a headless run, or offline, everything here is a harmless no-op.

signal speaking_changed(local_active: bool, radio: bool)

const CAPTURE_BUS: String = "VoiceCapture"
const RADIO_BUS: String = "VoiceRadio"
const ACTION_RADIO: String = "voice_radio"
const ACTION_PTT: String = "voice_ptt"
const PEER_TIMEOUT_MS: int = 4000
## Playback buffer is kept between these many samples: below MIN we wait, above MAX we drop old audio.
const JITTER_MIN: int = 640
const JITTER_MAX: int = 6400

## Settings-friendly public API.
var enabled: bool = true
var mic_gain: float = 1.0
var gate_db: float = -42.0
var output_volume: float = 1.0
## "open" (default, recommended) or "push_to_talk".
var proximity_mode: String = "open"
var net: FastNet
var sfx: Node

var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _mic_ok: bool = false
var _resampler: RefCounted
var _encoder: RefCounted = Codec.new()
var _gate = Codec.Gate.new()
var _pcm: PackedFloat32Array = PackedFloat32Array()
var _radio_down: bool = false
var _ptt_down: bool = false
var _sending: bool = false
var _sending_radio: bool = false
var _muted: Dictionary = {}
var _peers: Dictionary = {}
var _label: Label
var frames_sent: int = 0
var frames_played: int = 0
## Test hook: forces the "key is held" state without an InputMap.
var test_radio_held: bool = false
var test_ptt_held: bool = false


func setup(owner_net: FastNet, owner_sfx: Node = null) -> void:
	net = owner_net
	sfx = owner_sfx
	net.voice_frame.connect(_on_voice_frame)
	net.peer_left.connect(_drop_peer)


func _ready() -> void:
	_build_hud()
	_setup_radio_bus()
	_setup_capture()
	set_process(true)


func mic_available() -> bool:
	return _mic_ok


func set_peer_muted(id: int, muted: bool) -> void:
	if muted:
		_muted[id] = true
		_drop_peer(id)
	else:
		_muted.erase(id)


func is_peer_muted(id: int) -> bool:
	return _muted.has(id)


## Applies a settings dictionary (keys: enabled, mic_gain, gate_db, output_volume, proximity_mode).
func apply_settings(data: Dictionary) -> void:
	enabled = bool(data.get("enabled", enabled))
	mic_gain = clampf(float(data.get("mic_gain", mic_gain)), 0.0, 4.0)
	gate_db = clampf(float(data.get("gate_db", gate_db)), -70.0, -15.0)
	output_volume = clampf(float(data.get("output_volume", output_volume)), 0.0, 2.0)
	var mode: String = str(data.get("proximity_mode", proximity_mode))
	proximity_mode = mode if mode == "open" or mode == "push_to_talk" else "open"
	_gate.gate_db = gate_db


func settings() -> Dictionary:
	return {"enabled": enabled, "mic_gain": mic_gain, "gate_db": gate_db, "output_volume": output_volume, "proximity_mode": proximity_mode}


# ---------------------------------------------------------------- capture

func _setup_radio_bus() -> void:
	if AudioServer.get_bus_index(RADIO_BUS) >= 0:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, RADIO_BUS)
	AudioServer.set_bus_send(index, "Master")
	var band: AudioEffectBandPassFilter = AudioEffectBandPassFilter.new()
	band.cutoff_hz = 1500.0
	band.resonance = 0.7
	AudioServer.add_bus_effect(index, band)
	var crunch: AudioEffectDistortion = AudioEffectDistortion.new()
	crunch.mode = AudioEffectDistortion.MODE_OVERDRIVE
	crunch.drive = 0.25
	AudioServer.add_bus_effect(index, crunch)


func _mic_supported() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)):
		return false
	return AudioServer.get_input_device_list().size() > 0


func _setup_capture() -> void:
	_mic_ok = false
	if not _mic_supported():
		return
	var index: int = AudioServer.get_bus_index(CAPTURE_BUS)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, CAPTURE_BUS)
		# Muted so you never hear yourself; the capture effect still records the pre-mute signal.
		AudioServer.set_bus_mute(index, true)
		AudioServer.add_bus_effect(index, AudioEffectCapture.new())
	_capture = AudioServer.get_bus_effect(index, 0) as AudioEffectCapture
	if _capture == null:
		return
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = CAPTURE_BUS
	add_child(_mic_player)
	_mic_player.play()
	_resampler = Codec.Resampler.new(AudioServer.get_mix_rate(), Codec.RATE)
	_mic_ok = true


func _radio_held() -> bool:
	return test_radio_held or (InputMap.has_action(ACTION_RADIO) and Input.is_action_pressed(ACTION_RADIO))


func _ptt_held() -> bool:
	return test_ptt_held or (InputMap.has_action(ACTION_PTT) and Input.is_action_pressed(ACTION_PTT))


## Decides what (if anything) the next mic frame is sent as. Returns -1 (nothing), or a Relay.Mode.
## Radio key wins (bypasses the gate; needs a crew); open mic goes through the noise gate;
## push-to-talk proximity only transmits while its key is held.
func decide_mode(radio_held: bool, ptt_held: bool, gate_open: bool, has_crew: bool) -> int:
	if not enabled:
		return -1
	if radio_held and has_crew:
		return Relay.Mode.CREW
	if proximity_mode == "push_to_talk":
		return Relay.Mode.PROXIMITY if ptt_held else -1
	return Relay.Mode.PROXIMITY if gate_open else -1


func _process(_delta: float) -> void:
	var radio: bool = _radio_held()
	var ptt: bool = _ptt_held()
	if radio != _radio_down:
		_radio_down = radio
		if sfx != null and net != null and net.is_online():
			sfx.call("play", "radio_squelch", 1.0 if radio else 0.8, -6.0)
	_ptt_down = ptt
	if _mic_ok and net != null:
		_poll_capture(radio, ptt)
	_update_playback()
	_update_hud()


func _poll_capture(radio: bool, ptt: bool) -> void:
	var available: int = _capture.get_frames_available()
	if available > 0:
		var stereo: PackedVector2Array = _capture.get_buffer(mini(available, 48000))
		var mono: PackedFloat32Array = PackedFloat32Array()
		mono.resize(stereo.size())
		for i: int in range(stereo.size()):
			mono[i] = (stereo[i].x + stereo[i].y) * 0.5
		_pcm.append_array(_resampler.process(mono))
	while _pcm.size() >= Codec.FRAME_SAMPLES:
		var frame: PackedFloat32Array = _pcm.slice(0, Codec.FRAME_SAMPLES)
		_pcm = _pcm.slice(Codec.FRAME_SAMPLES)
		process_mic_frame(frame, radio, ptt)
	if _pcm.size() > Codec.FRAME_SAMPLES * 8:
		_pcm.clear()


## One 40 ms mic frame (16 kHz mono floats): gain, gate, mode choice, encode, send. Public for tests.
func process_mic_frame(frame: PackedFloat32Array, radio: bool, ptt: bool) -> int:
	var boosted: PackedFloat32Array = frame.duplicate()
	for i: int in range(boosted.size()):
		boosted[i] = clampf(boosted[i] * mic_gain, -1.0, 1.0)
	_gate.gate_db = gate_db
	var gate_open: bool = _gate.process(boosted)
	var has_crew: bool = net != null and net.is_online() and not net.crew_of(net.my_id()).is_empty()
	var mode: int = decide_mode(radio, ptt, gate_open, has_crew)
	var sending: bool = mode >= 0
	if sending != _sending or (mode == Relay.Mode.CREW) != _sending_radio:
		_sending = sending
		_sending_radio = mode == Relay.Mode.CREW
		speaking_changed.emit(_sending, _sending_radio)
	if mode < 0 or net == null or not net.is_online():
		return -1
	net.send_voice(mode, _encoder.encode(boosted))
	frames_sent += 1
	return mode


# ---------------------------------------------------------------- playback

func _make_stream_player(radio: bool) -> Node:
	var generator: AudioStreamGenerator = AudioStreamGenerator.new()
	generator.mix_rate = float(Codec.RATE)
	generator.buffer_length = 0.5
	if radio:
		var flat: AudioStreamPlayer = AudioStreamPlayer.new()
		flat.stream = generator
		flat.bus = RADIO_BUS
		add_child(flat)
		flat.play()
		return flat
	var spatial: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	spatial.stream = generator
	spatial.unit_size = 5.0
	spatial.max_distance = 35.0
	spatial.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	spatial.attenuation_filter_cutoff_hz = 6000.0
	add_child(spatial)
	spatial.play()
	return spatial


func _entry(id: int) -> Dictionary:
	if not _peers.has(id):
		_peers[id] = {"prox": null, "radio": null, "last_ms": 0, "radio_ms": 0, "mode": 0}
	return _peers[id]


func _on_voice_frame(from_id: int, mode: int, frame: PackedByteArray, distance: float, muffled: bool = false) -> void:
	if _muted.has(from_id) or output_volume <= 0.001:
		return
	var samples: PackedFloat32Array = Codec.decode(frame)
	if samples.is_empty():
		return
	var radio: bool = mode == Relay.Mode.CREW
	var entry: Dictionary = _entry(from_id)
	var key: String = "radio" if radio else "prox"
	var now: int = Time.get_ticks_msec()
	if radio and now - int(entry["radio_ms"]) > 600 and sfx != null:
		sfx.call("play", "radio_squelch", 1.1, -8.0)
	if radio:
		entry["radio_ms"] = now
	entry["last_ms"] = now
	entry["mode"] = mode
	if entry[key] == null:
		entry[key] = _make_stream_player(radio)
	var player: Node = entry[key]
	var volume_db: float = linear_to_db(maxf(output_volume, 0.0001)) - (8.0 if muffled else 0.0)
	player.set("volume_db", volume_db)
	if player is AudioStreamPlayer3D:
		# Heard through a doorway: a wall-muffled voice.
		(player as AudioStreamPlayer3D).attenuation_filter_cutoff_hz = 900.0 if muffled else 6000.0
	var playback: AudioStreamGeneratorPlayback = player.call("get_stream_playback") as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var buffered: int = int((0.5 * Codec.RATE) - playback.get_frames_available())
	if buffered > JITTER_MAX:
		return
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(samples.size())
	for i: int in range(samples.size()):
		out[i] = Vector2(samples[i], samples[i])
	if playback.get_frames_available() >= out.size():
		playback.push_buffer(out)
		frames_played += 1


func _update_playback() -> void:
	if net == null:
		return
	var now: int = Time.get_ticks_msec()
	for id: int in _peers.keys():
		var entry: Dictionary = _peers[id]
		if now - int(entry["last_ms"]) > PEER_TIMEOUT_MS * 5:
			_drop_peer(id)
			continue
		var prox: Node = entry["prox"]
		if prox is Node3D:
			var state: Dictionary = net.latest_state(id)
			if state.has("pos"):
				(prox as Node3D).global_position = (state["pos"] as Vector3) + Vector3(0, 1.6, 0)


func _drop_peer(id: int) -> void:
	if not _peers.has(id):
		return
	var entry: Dictionary = _peers[id]
	for key: String in ["prox", "radio"]:
		var player: Node = entry[key]
		if player != null and is_instance_valid(player):
			player.queue_free()
	_peers.erase(id)


func peer_count() -> int:
	return _peers.size()


## True while this peer's proximity voice is reaching us (crew radio never counts: that stays secret).
func is_speaking(id: int) -> bool:
	if not _peers.has(id):
		return false
	var entry: Dictionary = _peers[id]
	return Time.get_ticks_msec() - int(entry["last_ms"]) < 400 and int(entry["mode"]) != Relay.Mode.CREW


## Names of remote players heard in the last half second (for the HUD).
func speakers() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if net == null:
		return out
	var now: int = Time.get_ticks_msec()
	for id: int in _peers.keys():
		if now - int((_peers[id] as Dictionary)["last_ms"]) < 500:
			out.append(("%s%s" % ["[radio] " if int((_peers[id] as Dictionary)["mode"]) == Relay.Mode.CREW else "", net.name_of(id)]).replace("[", "(").replace("]", ")"))
	return out


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 200)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.visible = false
	layer.add_child(_label)


func _update_hud() -> void:
	if _label == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	if _sending:
		lines.append("RADIO (crew only)" if _sending_radio else "MIC (nearby)")
	elif net != null and net.is_online() and proximity_mode == "push_to_talk":
		lines.append("push to talk: hold to speak")
	for name: String in speakers():
		lines.append(name + " speaking")
	_label.text = "\n".join(lines)
	_label.visible = not lines.is_empty() and enabled and net != null and net.is_online()
