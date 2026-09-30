extends SceneTree
## Voice chat (scripts/voice_codec.gd, voice_relay.gd, voice.gd and the host relay in net.gd):
## ADPCM round trip and frame caps, resampler, noise gate, relay routing (proximity range, crew-only,
## never to enemies, squad key mutes proximity), rejects (spoofed / oversized / flood), open-mic and
## push-to-talk modes, and that headless with no microphone nothing errors.
## Run: godot --headless --path . --script res://tests/voice.gd

const Codec = preload("res://scripts/voice_codec.gd")
const Relay = preload("res://scripts/voice_relay.gd")
const VoiceScript = preload("res://scripts/voice.gd")
const Factions = preload("res://scripts/factions.gd")
const PORT: int = 24692

var checks: int = 0
var failures: int = 0
var net: FastNet
var tap: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


## A speech-ish test frame: a few harmonics under a syllable envelope.
func _speech(seed_phase: float = 0.0, amp: float = 0.4, count: int = Codec.FRAME_SAMPLES) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	for i: int in range(count):
		var t: float = float(i) / float(Codec.RATE)
		var env: float = 0.55 + 0.45 * sin(TAU * 4.0 * t + seed_phase)
		out[i] = amp * env * (sin(TAU * 180.0 * t + seed_phase) * 0.6 + sin(TAU * 540.0 * t) * 0.3 + sin(TAU * 1300.0 * t + 1.0) * 0.15)
	return out


func _run() -> void:
	_codec()
	_resampler()
	_gate()
	_relay_pure()
	_relay_occlusion()
	_relay_phone()
	_host_routing()
	_host_phone_routing()
	_voice_node()
	await _end_to_end()
	print("VOICE RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _codec() -> void:
	var encoder: RefCounted = Codec.new()
	var source: PackedFloat32Array = _speech()
	var frame: PackedByteArray = encoder.encode(source)
	_check(frame.size() == Codec.HEADER_BYTES + Codec.FRAME_SAMPLES / 2, "a 40 ms frame is %d bytes (got %d)" % [Codec.HEADER_BYTES + Codec.FRAME_SAMPLES / 2, frame.size()])
	var decoded: PackedFloat32Array = Codec.decode(frame)
	_check(decoded.size() == Codec.FRAME_SAMPLES + 1, "decoder returns one padding sample (%d)" % decoded.size())
	var snr: float = Codec.snr_db(source, decoded)
	_check(snr > 20.0, "ADPCM round-trip SNR %.1f dB (> 20)" % snr)
	# Many consecutive frames with a carried step index stay accurate.
	var worst: float = 99.0
	var stream_encoder: RefCounted = Codec.new()
	for n: int in range(12):
		var piece: PackedFloat32Array = _speech(float(n) * 0.7, 0.05 + 0.08 * float(n % 5))
		worst = minf(worst, Codec.snr_db(piece, Codec.decode(stream_encoder.encode(piece))))
	_check(worst > 15.0, "worst SNR over 12 chained frames %.1f dB (> 15)" % worst)
	# Frames decode on their own: dropping frame 1 does not corrupt frame 2.
	var solo_encoder: RefCounted = Codec.new()
	solo_encoder.encode(_speech(0.3))
	var second_source: PackedFloat32Array = _speech(1.1, 0.3)
	var second: PackedByteArray = solo_encoder.encode(second_source)
	_check(Codec.snr_db(second_source, Codec.decode(second)) > 15.0, "a frame decodes correctly after its predecessor was lost")
	# Caps and garbage.
	_check(encoder.encode(_speech(0.0, 0.4, 20000)).size() <= Codec.MAX_FRAME_BYTES, "oversized input is capped at %d bytes" % Codec.MAX_FRAME_BYTES)
	_check(Codec.decode(PackedByteArray([1, 2])).is_empty() and Codec.decode(PackedByteArray()).is_empty(), "too-short frames decode to nothing")
	var bad_index: PackedByteArray = frame.duplicate()
	bad_index[2] = 200
	_check(Codec.decode(bad_index).is_empty(), "a corrupt step index decodes to nothing")
	var giant: PackedByteArray = PackedByteArray()
	giant.resize(Codec.MAX_FRAME_BYTES + 1)
	_check(Codec.decode(giant).is_empty(), "an over-long frame decodes to nothing")
	var random_bytes: PackedByteArray = PackedByteArray()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	random_bytes.resize(300)
	for i: int in range(300):
		random_bytes[i] = rng.randi() % 256
	random_bytes[2] = 10
	var noise: PackedFloat32Array = Codec.decode(random_bytes)
	var noise_peak: float = 0.0
	for sample: float in noise:
		noise_peak = maxf(noise_peak, absf(sample))
	_check(noise.size() > 0 and noise_peak <= 1.0, "random bytes decode to bounded audio (peak %.2f)" % noise_peak)
	_check(encoder.encode(PackedFloat32Array([0.1])).is_empty(), "a one-sample input encodes to nothing")
	var kbps: float = float(frame.size()) * 8.0 * 25.0 / 1000.0
	print("bandwidth per talker: %.1f kbit/s (%d bytes x 25 frames/s)" % [kbps, frame.size()])
	_check(kbps < 70.0, "voice payload under 70 kbit/s per talker (%.1f)" % kbps)


func _resampler() -> void:
	var resampler: RefCounted = Codec.new().get_script().Resampler.new(48000.0, 16000.0)
	var tone: PackedFloat32Array = PackedFloat32Array()
	tone.resize(4800)
	for i: int in range(4800):
		tone[i] = sin(TAU * 400.0 * float(i) / 48000.0)
	var out: PackedFloat32Array = PackedFloat32Array()
	# Feed in ragged chunks: phase must carry across them.
	for chunk: Array in [[0, 1000], [1000, 1777], [2777, 2023]]:
		out.append_array(resampler.process(tone.slice(int(chunk[0]), int(chunk[0]) + int(chunk[1]))))
	_check(absf(float(out.size()) - 1600.0) <= 3.0, "48 k -> 16 k gives a third of the samples (%d of 1600)" % out.size())
	var crossings: int = 0
	for i: int in range(1, out.size()):
		if (out[i - 1] < 0.0) != (out[i] < 0.0):
			crossings += 1
	_check(absi(crossings - 80) <= 2, "a 400 Hz tone stays 400 Hz through chunked resampling (%d crossings)" % crossings)


func _gate() -> void:
	var gate: RefCounted = Codec.Gate.new()
	gate.gate_db = -42.0
	gate.hangover = 3
	var silence: PackedFloat32Array = PackedFloat32Array()
	silence.resize(640)
	var quiet: PackedFloat32Array = _speech(0.0, 0.001)
	var loud: PackedFloat32Array = _speech(0.0, 0.3)
	_check(not gate.process(silence) and not gate.process(quiet), "silence and a -60 dB hiss are gated out")
	_check(gate.process(loud), "speech opens the gate")
	var tail: int = 0
	while gate.process(silence) and tail < 10:
		tail += 1
	_check(tail == 2, "hangover keeps the gate open for %d more frames (got %d)" % [3 - 1, tail])
	_check(not gate.process(silence), "gate closes after the hangover")
	gate.reset()
	_check(not gate.open and gate.process(loud, 1.0), "reset closes the gate and speech reopens it")
	var hot: RefCounted = Codec.Gate.new()
	_check(not hot.process(quiet, 1.0) and hot.process(quiet, 60.0), "mic gain lifts a quiet mic over the threshold")


func _relay_pure() -> void:
	var peers: Dictionary = {
		1: {"crew": "a", "pos": Vector3.ZERO, "dead": false},
		2: {"crew": "a", "pos": Vector3(500, 0, 0), "dead": false},
		3: {"crew": "b", "pos": Vector3(4, 0, 0), "dead": false},
		4: {"crew": "b", "pos": Vector3(34, 0, 0), "dead": false},
		5: {"crew": "b", "pos": Vector3(36, 0, 0), "dead": false},
		6: {"crew": "b", "pos": Vector3(3, 0, 0), "dead": true},
		7: {"crew": "", "pos": Vector3(2, 0, 0), "dead": false},
	}
	var prox: Array = Relay.targets(1, Relay.Mode.PROXIMITY, peers)
	var prox_ids: Array = prox.map(func(e: Array) -> int: return int(e[0]))
	prox_ids.sort()
	_check(prox_ids == [3, 4, 7], "proximity reaches only listeners within 35 m and alive (%s)" % str(prox_ids))
	_check(absf(float(prox[0][1]) - 4.0) < 0.01 or absf(float(prox[1][1]) - 4.0) < 0.01, "receivers are told the distance")
	var crew: Array = Relay.targets(1, Relay.Mode.CREW, peers).map(func(e: Array) -> int: return int(e[0]))
	_check(crew == [2], "crew radio reaches the crew mate at 500 m and nobody else (%s)" % str(crew))
	_check(Relay.targets(7, Relay.Mode.CREW, peers).is_empty(), "no crew, no radio")
	var dead_prox: Array = Relay.targets(6, Relay.Mode.PROXIMITY, peers).map(func(e: Array) -> int: return int(e[0]))
	_check(dead_prox.is_empty(), "the dead are not heard by the living in proximity (%s)" % str(dead_prox))
	_check(Relay.targets(99, Relay.Mode.PROXIMITY, peers).is_empty() and Relay.targets(1, 2, peers).is_empty() and Relay.targets(1, -1, peers).is_empty() and Relay.targets(1, 3, peers).is_empty(), "unknown sender and invalid / combined modes route nowhere")
	peers[3]["pos"] = Vector3.INF
	_check(not (Relay.targets(1, Relay.Mode.PROXIMITY, peers).map(func(e: Array) -> int: return int(e[0])).has(3)), "a peer with no known position is not a proximity listener")


func _relay_occlusion() -> void:
	# Ids: 10 talks inside building 100. 11 is inside too. 12 is a passerby outside 5 m away.
	# 13 stands outside by the open door. 14 is in a different building. 15 is outdoors far from any door.
	var peers: Dictionary = {
		10: {"crew": "a", "pos": Vector3(0, 0, 3), "dead": false, "space": 100},
		11: {"crew": "b", "pos": Vector3(8, 0, 0), "dead": false, "space": 100},
		12: {"crew": "b", "pos": Vector3(5, 0, 20), "dead": false, "space": -1},
		13: {"crew": "b", "pos": Vector3(0, 0, 8), "dead": false, "space": -1},
		14: {"crew": "b", "pos": Vector3(3, 0, 0), "dead": false, "space": 200},
		15: {"crew": "b", "pos": Vector3(30, 0, 30), "dead": false, "space": -1},
	}
	var doors: Array = [Vector3(0, 0, 5)]
	var result: Array = Relay.targets(10, Relay.Mode.PROXIMITY, peers, Relay.PROXIMITY_RANGE, doors)
	var ids: Array = result.map(func(e: Array) -> int: return int(e[0]))
	ids.sort()
	_check(ids == [11, 13], "people inside hear each other; only someone at the open door hears through it (%s)" % str(ids))
	var by_id: Dictionary = {}
	for entry: Array in result:
		by_id[int(entry[0])] = bool(entry[2])
	_check(by_id.get(11) == false and by_id.get(13) == true, "same-room voice is clear; through-the-door voice is muffled")
	var closed: Array = Relay.targets(10, Relay.Mode.PROXIMITY, peers, Relay.PROXIMITY_RANGE, []).map(func(e: Array) -> int: return int(e[0]))
	closed.sort()
	_check(closed == [11], "with the doors shut a passerby outside hears nothing (%s)" % str(closed))
	var outside_out: Array = Relay.targets(12, Relay.Mode.PROXIMITY, peers, Relay.PROXIMITY_RANGE, doors).map(func(e: Array) -> int: return int(e[0]))
	outside_out.sort()
	_check(outside_out == [13, 15] or outside_out == [13], "outside to outside is plain distance falloff, but the room inside stays private (%s)" % str(outside_out))
	_check(not outside_out.has(10) and not outside_out.has(11), "a passerby cannot hear the people inside")
	var radio: Array = Relay.targets(10, Relay.Mode.CREW, peers, Relay.PROXIMITY_RANGE, []).map(func(e: Array) -> int: return int(e[0]))
	_check(radio.is_empty(), "crew radio is unaffected by walls (no crew mates here, so nobody)")
	peers[15]["crew"] = "a"
	radio = Relay.targets(10, Relay.Mode.CREW, peers, Relay.PROXIMITY_RANGE, []).map(func(e: Array) -> int: return int(e[0]))
	_check(radio == [15], "crew radio crosses walls and distance")


## Phone relay (pure): who is picked up by a phone in a live call, and who hears the other phone.
func _relay_phone() -> void:
	_check(Relay.valid_mode(Relay.Mode.PHONE) and Relay.valid_mode(0) and Relay.valid_mode(1) and not Relay.valid_mode(3) and not Relay.valid_mode(-1), "the relay accepts modes 0, 1 and PHONE (2) and nothing else")
	_check(Relay.valid_send_mode(0) and Relay.valid_send_mode(1) and not Relay.valid_send_mode(Relay.Mode.PHONE) and not Relay.valid_send_mode(3), "a client may send only proximity or crew: PHONE is made by the host")
	_check(Relay.PHONE_PICKUP == 1.2 and Relay.PHONE_SPEAKER == 3.5, "pickup radius 1.2 m, speaker radius 3.5 m")
	# Phone A (held by talker 10) at the origin; phone B at x = 200. A call is {"a", "b"} phone positions.
	var a_at: Vector3 = Vector3(0, 0, 0)
	var b_at: Vector3 = Vector3(200, 0, 0)
	var peers: Dictionary = {
		10: {"crew": "a", "pos": a_at, "dead": false},
		11: {"crew": "b", "pos": Vector3(1.0, 0, 0), "dead": false},
		12: {"crew": "b", "pos": Vector3(3.0, 0, 0), "dead": false},
		13: {"crew": "b", "pos": Vector3(201, 0, 0), "dead": false},
		14: {"crew": "b", "pos": Vector3(203.4, 0, 0), "dead": false},
		15: {"crew": "b", "pos": Vector3(203.6, 0, 0), "dead": false},
		16: {"crew": "b", "pos": Vector3(200, 0, 2), "dead": true},
		17: {"crew": "c", "pos": Vector3(200.5, 0, 0), "dead": false},
		20: {"crew": "b", "pos": Vector3(1.3, 0, 0), "dead": false},
	}
	var calls: Array = [{"a": a_at, "b": b_at}]
	var ids_of: Callable = func(rows: Array) -> Array:
		var ids: Array = rows.map(func(r: Array) -> int: return int(r[0]))
		ids.sort()
		return ids
	var rows: Array = Relay.phone_targets(10, peers, calls)
	_check(ids_of.call(rows) == [13, 14, 17], "a talker at phone A is heard by the living within 3.5 m of phone B, not by the dead or at 3.6 m (%s)" % str(ids_of.call(rows)))
	var dist_of: Dictionary = {}
	for row: Array in rows:
		dist_of[int(row[0])] = float(row[1])
	_check(absf(float(dist_of[13]) - 1.0) < 0.01 and absf(float(dist_of[14]) - 3.4) < 0.01, "the listener is told the distance to the speaking phone")
	# People next to the talker's own phone get no phone copy (they hear the talker directly).
	_check(not dist_of.has(12) and not dist_of.has(11), "people next to the talker's own phone get no phone copy")
	# Pickup radius: 1.2 m picks up, 3 m (a bystander) does not.
	_check(ids_of.call(Relay.phone_targets(11, peers, calls)) == [13, 14, 17], "someone standing 1.0 m from the phone is picked up too")
	_check(Relay.phone_targets(12, peers, calls).is_empty() and Relay.phone_targets(20, peers, calls).is_empty(), "a bystander 3 m (or 1.3 m) from the phone is NOT picked up: it does not take in the room")
	# The other direction: the far side talking is heard within 3.5 m of phone A.
	var back: Array = ids_of.call(Relay.phone_targets(13, peers, calls))
	_check(back == [10, 11, 12, 20], "the far side talking is heard at phone A, but not at the far phone's own side (%s)" % str(back))
	# The dead cannot use phones.
	peers[10]["dead"] = true
	_check(Relay.phone_targets(10, peers, calls).is_empty(), "a dead talker is not picked up")
	peers[10]["dead"] = false
	# A dropped phone in a live call is a speakerphone on the table: radii come from the phone, not a person.
	var table: Dictionary = {"a": Vector3(50, 0.3, 50), "b": b_at}
	peers[18] = {"crew": "a", "pos": Vector3(50.6, 0, 50), "dead": false}
	_check(ids_of.call(Relay.phone_targets(18, peers, [table])) == [13, 14, 17], "a dropped phone on the table still picks up someone standing 0.6 m from it")
	_check(Relay.phone_targets(10, peers, [table]).is_empty(), "...and nobody else, however close to where the call started")
	# Two calls and bad input.
	var two: Array = [{"a": a_at, "b": b_at}, {"a": Vector3(0.5, 0, 0), "b": Vector3(300, 0, 0)}]
	peers[19] = {"crew": "c", "pos": Vector3(300, 0, 1), "dead": false}
	_check(ids_of.call(Relay.phone_targets(10, peers, two)) == [13, 14, 17, 19], "a talker by two phones in two calls reaches both far ends, once each")
	_check(Relay.phone_targets(10, peers, []).is_empty() and Relay.phone_targets(99, peers, calls).is_empty(), "no live calls or an unknown talker route nowhere")
	_check(Relay.phone_targets(10, peers, [{"a": Vector3.INF, "b": b_at}, "junk", {}]).is_empty(), "malformed call entries are ignored")
	_check(Relay.targets(10, Relay.Mode.PHONE, peers).is_empty(), "the ordinary relay never routes the PHONE mode")


## Host relay with a live call: proximity frames by a phone also go out as PHONE; radio never does.
func _host_phone_routing() -> void:
	net.voice_tap = _record
	net.voice_space = Callable()
	net.voice_doors = Callable()
	net._strikes.clear(6)
	net._voice_radio_until.erase(6)
	# Talker 6 holds phone A at the origin. Phone B is at x = 200. 8 is 1 m from B, 7 is 3 m from B, the host (1)
	# stands 3 m from the talker (it hears the talker directly and is nowhere near B).
	var line_a: Vector3 = Vector3.ZERO
	var line_b: Vector3 = Vector3(200, 0, 0)
	net._latest[6] = {"pos": line_a, "flags": 0}
	net._latest[8] = {"pos": Vector3(201, 0, 0), "flags": 0}
	net._latest[7] = {"pos": Vector3(203, 0, 0), "flags": 0}
	net._latest[1] = {"pos": Vector3(3, 0, 0), "flags": 0}
	var frame: PackedByteArray = Codec.new().encode(_speech())
	tap.clear()
	net._h_voice(6, Relay.Mode.PROXIMITY, frame)
	_check(tap.filter(func(r: Array) -> bool: return int(r[2]) == Relay.Mode.PHONE).is_empty(), "no live call: no PHONE frames")
	net.voice_phones = func() -> Array: return [{"a": line_a, "b": line_b}]
	tap.clear()
	var sent: int = net._h_voice(6, Relay.Mode.PROXIMITY, frame)
	var phone_rows: Array = tap.filter(func(r: Array) -> bool: return int(r[2]) == Relay.Mode.PHONE)
	var direct_rows: Array = tap.filter(func(r: Array) -> bool: return int(r[2]) == Relay.Mode.PROXIMITY)
	var phone_ids: Array = phone_rows.map(func(r: Array) -> int: return int(r[0]))
	phone_ids.sort()
	_check(phone_ids == [7, 8], "host: a live call carries the talker's proximity frame to the two listeners at the other phone (%s)" % str(phone_ids))
	_check(direct_rows.size() == 1 and int(direct_rows[0][0]) == 1 and sent == 3, "host: the normal proximity frame still goes out as before (people next to you hear you directly)")
	_check(int(phone_rows[0][1]) == 6, "host: PHONE frames carry the real talker id")
	# Crew radio never goes down a phone (the crew mate 8 hears it on the radio only).
	tap.clear()
	net._h_voice(6, Relay.Mode.CREW, frame)
	_check(tap.filter(func(r: Array) -> bool: return int(r[2]) == Relay.Mode.PHONE).is_empty() and _targets_of([]) == [1, 8], "host: crew radio reaches the crew only and is never relayed to a phone")
	net._voice_radio_until.erase(6)
	# A bystander 3 m from the phone is not picked up.
	net._latest[6] = {"pos": Vector3(3.0, 0, 0), "flags": 0}
	tap.clear()
	net._h_voice(6, Relay.Mode.PROXIMITY, frame)
	_check(tap.filter(func(r: Array) -> bool: return int(r[2]) == Relay.Mode.PHONE).is_empty(), "host: someone 3 m from the phone does not get on the call")
	# A dead talker cannot use a phone; a dead listener does not hear one.
	net._latest[6] = {"pos": line_a, "flags": 4}
	tap.clear()
	net._h_voice(6, Relay.Mode.PROXIMITY, frame)
	_check(tap.filter(func(r: Array) -> bool: return int(r[2]) == Relay.Mode.PHONE).is_empty(), "host: a dead talker is not carried down the phone")
	net._latest[6] = {"pos": line_a, "flags": 0}
	net._latest[8] = {"pos": Vector3(201, 0, 0), "flags": 4}
	tap.clear()
	net._h_voice(6, Relay.Mode.PROXIMITY, frame)
	var living: Array = tap.filter(func(r: Array) -> bool: return int(r[2]) == Relay.Mode.PHONE).map(func(r: Array) -> int: return int(r[0]))
	_check(living == [7], "host: a dead listener near the far phone does not hear it (%s)" % str(living))
	net._latest[8] = {"pos": Vector3(201, 0, 0), "flags": 0}
	# A client cannot ask for the PHONE mode itself.
	var strikes: int = net._strikes.count(6)
	tap.clear()
	_check(net._h_voice(6, Relay.Mode.PHONE, frame) == 0 and tap.is_empty() and net._strikes.count(6) > strikes, "a client frame claiming the PHONE mode is rejected with a strike")
	net.voice_phones = Callable()
	net._strikes.clear(6)
	net.voice_tap = Callable()


func _record(target: int, sender: int, mode: int, dist: float, _frame: PackedByteArray, muffled: bool = false) -> void:
	tap.append([target, sender, mode, dist, muffled])


func _targets_of(sender_ids: Array) -> Array:
	var ids: Array = []
	for row: Array in tap:
		ids.append(int(row[0]))
	ids.sort()
	return ids


func _host_routing() -> void:
	net = FastNet.new()
	net.name = "Net"
	net.use_upnp = false
	root.add_child(net)
	_check(net.host(PORT) == OK, "host starts")
	var crew_a: String = Factions.ORDER[0]
	var crew_b: String = Factions.ORDER[1]
	# Peer 6 talks. 7 is an enemy 4 m away. 8 is a crew mate 500 m away. The host (1) is an enemy 20 m away.
	for id: int in [6, 7, 8]:
		net.players[id] = net._new_entry("P%d" % id)
		net._hello_done[id] = true
	net.players[6]["crew"] = crew_a
	net.players[7]["crew"] = crew_b
	net.players[8]["crew"] = crew_a
	net.players[1]["crew"] = crew_b
	net._latest[6] = {"pos": Vector3.ZERO, "flags": 0}
	net._latest[7] = {"pos": Vector3(4, 0, 0), "flags": 0}
	net._latest[8] = {"pos": Vector3(500, 0, 0), "flags": 0}
	net._latest[1] = {"pos": Vector3(20, 0, 0), "flags": 0}
	net.voice_tap = _record
	var frame: PackedByteArray = Codec.new().encode(_speech())
	# Open-mic proximity.
	tap.clear()
	var sent: int = net._h_voice(6, Relay.Mode.PROXIMITY, frame)
	_check(sent == 2 and _targets_of([]) == [1, 7], "proximity frame reaches the two nearby players, not the far crew mate (%s)" % str(_targets_of([])))
	_check(int(tap[0][1]) == 6 and absf(float(tap[0][3]) - 4.0) < 0.1 or absf(float(tap[1][3]) - 4.0) < 0.1, "relay stamps the real sender and the distance")
	# Squad key held: crew-only, the nearby enemy gets nothing.
	tap.clear()
	sent = net._h_voice(6, Relay.Mode.CREW, frame)
	_check(sent == 1 and _targets_of([]) == [8], "squad radio: the far crew mate hears it, the enemy 4 m away and the host do not (%s)" % str(_targets_of([])))
	# While on the radio the same mic cannot also go out as proximity.
	tap.clear()
	sent = net._h_voice(6, Relay.Mode.PROXIMITY, frame)
	_check(sent == 0 and tap.is_empty(), "a proximity frame right after a radio frame is dropped (squad key mutes proximity)")
	# Released: after the hold window proximity resumes.
	net._voice_radio_until[6] = Time.get_ticks_msec() - 1
	sent = net._h_voice(6, Relay.Mode.PROXIMITY, frame)
	_check(sent == 2, "squad key released: open-mic proximity resumes")
	# Never to enemies in crew mode even when everyone is close.
	net._latest[8] = {"pos": Vector3(1, 0, 0), "flags": 0}
	tap.clear()
	net._voice_radio_until.erase(6)
	net._h_voice(6, Relay.Mode.CREW, frame)
	_check(_targets_of([]) == [8], "crew mode never reaches an enemy, however close")
	net._voice_radio_until.erase(6)
	net._latest[8] = {"pos": Vector3(500, 0, 0), "flags": 0}
	# Dead talker: heard only by other dead players in proximity; radio still reaches the crew.
	net._latest[6] = {"pos": Vector3.ZERO, "flags": 4}
	tap.clear()
	sent = net._h_voice(6, Relay.Mode.PROXIMITY, frame)
	_check(sent == 0, "a dead player's proximity voice reaches no living player")
	net._h_voice(6, Relay.Mode.CREW, frame)
	_check(_targets_of([]) == [8], "a dead player can still use the crew radio")
	net._latest[6] = {"pos": Vector3.ZERO, "flags": 0}
	net._voice_radio_until.erase(6)
	# Rejects.
	tap.clear()
	var strikes_before: int = net._strikes.count(6)
	_check(net._h_voice(6, 3, frame) == 0 and net._h_voice(6, -1, frame) == 0 and net._h_voice(6, 2, frame) == 0, "a frame claiming both modes (or any invalid mode) is rejected")
	var oversized: PackedByteArray = PackedByteArray()
	oversized.resize(5000)
	_check(net._h_voice(6, 0, oversized) == 0 and net._h_voice(6, 0, PackedByteArray([1, 2])) == 0 and net._h_voice(6, 0, PackedByteArray()) == 0, "oversized / undersized / empty frames are rejected")
	_check(net._h_voice(42, 0, frame) == 0 and net._h_voice(2, 0, frame) == 0, "unknown / not-joined senders are ignored (spoofed id)")
	_check(tap.is_empty() and net._strikes.count(6) >= strikes_before + 5, "rejected frames relayed nothing and earned strikes (%d)" % (net._strikes.count(6) - strikes_before))
	net._strikes.clear(6)
	# Client-side gate: only the host may send relays; spoofed peers are refused entry.
	_check(not net._gate(42, "voice", FastNet.LIMIT_VOICE), "an unknown peer is refused at the RPC gate")
	# Flood.
	net._rl.erase(6)
	net._budget.erase(6)
	var passed: int = 0
	for i: int in range(600):
		if net._gate(6, "voice", FastNet.LIMIT_VOICE):
			passed += 1
	_check(passed <= FastNet.LIMIT_VOICE + 5 and passed >= 20, "voice flood is rate limited (%d of 600 passed)" % passed)
	# Occlusion on the host relay: 6 talks inside a building (x > 900); 7 is inside; 8 is outside 2 m away.
	net.voice_space = func(at: Vector3) -> int: return 77 if at.x > 900.0 else -1
	net.voice_doors = func() -> Array: return []
	net._latest[6] = {"pos": Vector3(901, 0, 0), "flags": 0}
	net._latest[7] = {"pos": Vector3(906, 0, 0), "flags": 0}
	net._latest[8] = {"pos": Vector3(899, 0, 0), "flags": 0}
	net._latest[1] = {"pos": Vector3(880, 0, 0), "flags": 0}
	net._voice_radio_until.erase(6)
	net._strikes.clear(6)
	tap.clear()
	net._h_voice(6, Relay.Mode.PROXIMITY, frame)
	_check(_targets_of([]) == [7], "host relay: the person inside hears it, the passerby 2 m away outside the wall does not (%s)" % str(_targets_of([])))
	net.voice_doors = func() -> Array: return [Vector3(900, 0, 0)]
	tap.clear()
	net._h_voice(6, Relay.Mode.PROXIMITY, frame)
	var muffled_ids: Array = tap.filter(func(r: Array) -> bool: return bool(r[4])).map(func(r: Array) -> int: return int(r[0]))
	muffled_ids.sort()
	_check(_targets_of([]) == [1, 7, 8] or _targets_of([]) == [7, 8], "host relay: an open doorway lets the person next to it hear (%s)" % str(_targets_of([])))
	_check(muffled_ids.has(8) and not muffled_ids.has(7), "host relay: through-door voice is flagged muffled, same-room voice is not")
	net.voice_space = Callable()
	net.voice_doors = Callable()
	net._latest[1] = {"pos": Vector3(20, 0, 0), "flags": 0}
	# The host hears its own listeners through the signal (no RPC).
	net.voice_tap = Callable()
	var heard: Array = []
	net.voice_frame.connect(func(from_id: int, mode: int, _f: PackedByteArray, dist: float, _m: bool) -> void: heard.append([from_id, mode, dist]))
	net._latest[6] = {"pos": Vector3(10, 0, 0), "flags": 0}
	net._voice_radio_until.erase(6)
	net._strikes.clear(6)
	net._h_voice(6, Relay.Mode.PROXIMITY, frame)
	_check(heard.size() == 1 and int(heard[0][0]) == 6 and absf(float(heard[0][2]) - 10.0) < 0.1, "the host receives nearby proximity voice locally")
	heard.clear()
	net._h_voice(6, Relay.Mode.CREW, frame)
	_check(heard.is_empty(), "the host (an enemy) never hears a crew radio frame")
	net.players[1]["crew"] = crew_a
	net._voice_radio_until.erase(6)
	net._h_voice(6, Relay.Mode.CREW, frame)
	_check(heard.size() == 1 and int(heard[0][1]) == Relay.Mode.CREW, "a host in the talker's crew does hear it")


func _voice_node() -> void:
	# Offline node: nothing may error and nothing may be sent.
	var offline_net: FastNet = FastNet.new()
	offline_net.name = "OfflineNet"
	offline_net.use_upnp = false
	root.add_child(offline_net)
	var voice: Node = VoiceScript.new()
	voice.name = "Voice"
	root.add_child(voice)
	voice.setup(offline_net, null)
	_check(not voice.mic_available(), "headless: no microphone, capture never starts")
	_check(voice.process_mic_frame(_speech(), false, false) == -1, "offline: a loud frame is not sent")
	voice._process(0.016)
	_check(true, "voice _process runs headless with no mic and no network")
	# Mode decisions (both proximity styles and the radio).
	voice.apply_settings({"proximity_mode": "open", "enabled": true})
	_check(voice.decide_mode(false, false, true, true) == Relay.Mode.PROXIMITY, "open mic: speech goes out as proximity with no key held")
	_check(voice.decide_mode(false, false, false, true) == -1, "open mic: silence (gate closed) sends nothing")
	_check(voice.decide_mode(true, false, true, true) == Relay.Mode.CREW, "radio key held: speech goes out as CREW only (proximity muted)")
	_check(voice.decide_mode(true, false, false, true) == Relay.Mode.CREW, "radio key held: the gate is bypassed while transmitting")
	_check(voice.decide_mode(true, false, true, false) == Relay.Mode.PROXIMITY, "radio key with no crew falls back to proximity")
	_check(voice.decide_mode(false, true, true, true) == Relay.Mode.PROXIMITY, "open mic ignores the push-to-talk key")
	voice.apply_settings({"proximity_mode": "push_to_talk"})
	_check(voice.decide_mode(false, false, true, true) == -1, "push-to-talk: speech without the key sends nothing")
	_check(voice.decide_mode(false, true, false, true) == Relay.Mode.PROXIMITY, "push-to-talk: holding the key sends proximity even below the gate")
	_check(voice.decide_mode(true, true, true, true) == Relay.Mode.CREW, "push-to-talk: the radio key still wins and is crew-only")
	voice.apply_settings({"enabled": false})
	_check(voice.decide_mode(true, true, true, true) == -1, "voice disabled: nothing is ever sent")
	voice.apply_settings({"enabled": true, "proximity_mode": "bogus", "mic_gain": 99.0, "gate_db": -500.0, "output_volume": -3.0})
	_check(voice.proximity_mode == "open" and voice.mic_gain == 4.0 and voice.gate_db == -70.0 and voice.output_volume == 0.0, "settings are clamped and a bad mode falls back to open mic")
	voice.apply_settings({"output_volume": 1.0, "gate_db": -42.0, "mic_gain": 1.0})

	# Online host: frames from the mic path go through the host relay with the right mode.
	var host_net: FastNet = net
	host_net.leave()
	_check(host_net.host(PORT + 1) == OK, "second host starts")
	host_net.players[1]["crew"] = Factions.ORDER[0]
	host_net.players[9] = host_net._new_entry("P9")
	host_net.players[9]["crew"] = Factions.ORDER[0]
	host_net._hello_done[9] = true
	host_net._latest[1] = {"pos": Vector3.ZERO, "flags": 0}
	host_net._latest[9] = {"pos": Vector3(300, 0, 0), "flags": 0}
	tap.clear()
	host_net.voice_tap = _record
	var online_voice: Node = VoiceScript.new()
	online_voice.name = "OnlineVoice"
	root.add_child(online_voice)
	online_voice.setup(host_net, null)
	_check(online_voice.process_mic_frame(_speech(), false, false) == Relay.Mode.PROXIMITY and tap.is_empty(), "open mic online: a frame is sent as proximity; a listener 300 m away gets nothing")
	_check(online_voice.process_mic_frame(_speech(), true, false) == Relay.Mode.CREW and _targets_of([]) == [9], "radio key online: the far crew mate hears it")
	tap.clear()
	_check(online_voice.process_mic_frame(_speech(), false, false) == Relay.Mode.PROXIMITY and tap.is_empty(), "radio released: proximity resumes")
	_check(online_voice.frames_sent == 3, "three frames were sent (%d)" % online_voice.frames_sent)
	var silent: PackedFloat32Array = PackedFloat32Array()
	silent.resize(640)
	for i: int in range(12):
		online_voice.process_mic_frame(silent, false, false)
	_check(online_voice.frames_sent <= 3 + 8, "silence stops after the gate's hangover (%d frames total)" % online_voice.frames_sent)

	# Playback: a received frame builds a player, respects mute, and never errors headless.
	var frame: PackedByteArray = Codec.new().encode(_speech())
	online_voice._on_voice_frame(9, Relay.Mode.PROXIMITY, frame, 12.0)
	online_voice._on_voice_frame(9, Relay.Mode.CREW, frame, 300.0)
	_check(online_voice.peer_count() == 1 and online_voice.speakers().size() == 1, "received voice creates one playback entry and lists the speaker")
	online_voice.set_peer_muted(9, true)
	_check(online_voice.peer_count() == 0 and online_voice.is_peer_muted(9), "muting a peer drops their playback")
	online_voice._on_voice_frame(9, Relay.Mode.PROXIMITY, frame, 12.0)
	_check(online_voice.peer_count() == 0, "muted peers' frames are ignored")
	online_voice.set_peer_muted(9, false)
	online_voice._on_voice_frame(9, 7, frame, 12.0)
	online_voice._on_voice_frame(9, Relay.Mode.PROXIMITY, PackedByteArray([1]), 12.0)
	_check(online_voice.peer_count() == 0 or online_voice.peer_count() == 1, "garbage frames are ignored without errors")
	# Phone playback: needs a phone locator; the voice comes out of the phone, on the telephone bus.
	online_voice.set_peer_muted(9, true)
	online_voice.set_peer_muted(9, false)
	online_voice._on_voice_frame(9, Relay.Mode.PHONE, frame, 2.0)
	_check(online_voice.peer_count() == 0, "a PHONE frame with no phone locator is ignored")
	var phone_spot: Vector3 = Vector3(5, 1.3, 5)
	online_voice.phone_locator = func(_talker: int) -> Vector3: return phone_spot
	online_voice._on_voice_frame(9, Relay.Mode.PHONE, frame, 2.0)
	var handset: Node = (online_voice._peers[9] as Dictionary)["phone"] if online_voice.peer_count() == 1 else null
	_check(handset is AudioStreamPlayer3D and (handset as AudioStreamPlayer3D).bus == "VoicePhone" and (handset as Node3D).global_position.is_equal_approx(phone_spot), "a PHONE frame plays from the phone's position on the VoicePhone bus")
	_check(not online_voice.is_speaking(9) and online_voice.speakers().has("(phone) P9"), "phone voice is listed as (phone) and does not light the talker as speaking here")
	var phone_bus: int = AudioServer.get_bus_index("VoicePhone")
	_check(phone_bus >= 0 and AudioServer.get_bus_effect_count(phone_bus) == 3 and AudioServer.get_bus_effect(phone_bus, 0) is AudioEffectHighPassFilter and AudioServer.get_bus_effect(phone_bus, 1) is AudioEffectLowPassFilter, "the VoicePhone bus is a 300-3400 Hz band with a little crunch")
	online_voice.phone_locator = func(_talker: int) -> Vector3: return Vector3.INF
	online_voice._on_voice_frame(9, Relay.Mode.PHONE, frame, 2.0)
	online_voice._process(0.016)
	online_voice.set_peer_muted(9, true)
	_check(online_voice.peer_count() == 0, "muting the talker drops the phone player too")
	host_net.leave()


# ---------------------------------------------------------------- real ENet on localhost, one process

func _make_net(label: String) -> FastNet:
	var holder := Node.new()
	holder.name = label
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var node: FastNet = FastNet.new()
	node.name = "Net"
	node.use_upnp = false
	node.local_name = label
	holder.add_child(node)
	return node


func _wait(cond: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await process_frame
	return bool(cond.call())


func _end_to_end() -> void:
	var host: FastNet = _make_net("H")
	_check(host.host(PORT + 2) == OK, "e2e: host listening")
	var alice: FastNet = _make_net("Alice")
	var bob: FastNet = _make_net("Bob")
	var carol: FastNet = _make_net("Carol")
	for node: FastNet in [alice, bob, carol]:
		node.join("127.0.0.1", PORT + 2)
	var joined: bool = await _wait(func() -> bool: return host.players.size() == 4 and alice.players.size() == 4 and bob.players.size() == 4 and carol.players.size() == 4, 10.0)
	_check(joined, "e2e: three clients join (host sees %d)" % host.players.size())
	host.request_crew(Factions.ORDER[0])
	alice.request_crew(Factions.ORDER[0])
	carol.request_crew(Factions.ORDER[0])
	bob.request_crew(Factions.ORDER[1])
	var crews_ok: bool = await _wait(func() -> bool: return host.crew_of(alice.my_id()) == Factions.ORDER[0] and host.crew_of(bob.my_id()) == Factions.ORDER[1] and host.crew_of(carol.my_id()) == Factions.ORDER[0], 4.0)
	_check(crews_ok, "e2e: crews are set on the host")
	var got: Dictionary = {"bob": [], "carol": [], "host": []}
	bob.voice_frame.connect(func(from_id: int, mode: int, _f: PackedByteArray, dist: float, _m: bool) -> void: got["bob"].append([from_id, mode, dist]))
	carol.voice_frame.connect(func(from_id: int, mode: int, _f: PackedByteArray, dist: float, _m: bool) -> void: got["carol"].append([from_id, mode, dist]))
	host.voice_frame.connect(func(from_id: int, mode: int, _f: PackedByteArray, dist: float, _m: bool) -> void: got["host"].append([from_id, mode, dist]))
	# Positions: Alice at the origin, Bob (enemy) 3 m away, Carol (crew mate) 400 m away, host 500 m away.
	alice.send_state(Vector3(0, 0, 0), 0.0, 0.0, 0, "", -1, -1, 100.0)
	bob.send_state(Vector3(3, 0, 0), 0.0, 0.0, 0, "", -1, -1, 100.0)
	carol.send_state(Vector3(400, 0, 0), 0.0, 0.0, 0, "", -1, -1, 100.0)
	host.send_state(Vector3(0, 0, 500), 0.0, 0.0, 0, "", -1, -1, 100.0)
	await _wait(func() -> bool: return host.latest_state(alice.my_id()).has("pos") and host.latest_state(bob.my_id()).has("pos") and host.latest_state(carol.my_id()).has("pos"), 4.0)
	var frame: PackedByteArray = Codec.new().encode(_speech())
	# Squad key held: only the crew mates (Carol far away, host) hear Alice; the enemy 3 m away does not.
	for i: int in range(6):
		alice.send_voice(Relay.Mode.CREW, frame)
		await process_frame
	var radio_heard: bool = await _wait(func() -> bool: return not got["carol"].is_empty() and not got["host"].is_empty(), 4.0)
	await _wait(func() -> bool: return false, 0.3)
	_check(radio_heard and int(got["carol"][0][1]) == Relay.Mode.CREW and int(got["carol"][0][0]) == alice.my_id(), "e2e: Alice's radio frame reaches her crew mate 400 m away over real RPC, stamped with her id")
	_check(got["bob"].is_empty(), "e2e: the enemy standing 3 m away hears nothing while the squad key is held")
	_check(not got["host"].is_empty(), "e2e: the host, also in the crew, hears the radio")
	# Released (wait out the radio hold): open-mic proximity reaches Bob and nobody far away.
	await _wait(func() -> bool: return false, float(FastNet.VOICE_RADIO_HOLD_MS) / 1000.0 + 0.2)
	got["carol"].clear()
	got["host"].clear()
	for i: int in range(6):
		alice.send_voice(Relay.Mode.PROXIMITY, frame)
		await process_frame
	var near_heard: bool = await _wait(func() -> bool: return not got["bob"].is_empty(), 4.0)
	await _wait(func() -> bool: return false, 0.3)
	_check(near_heard and int(got["bob"][0][1]) == Relay.Mode.PROXIMITY and absf(float(got["bob"][0][2]) - 3.0) < 0.5, "e2e: open-mic proximity reaches the player 3 m away with the distance attached")
	_check(got["carol"].is_empty() and got["host"].is_empty(), "e2e: proximity does not reach people 400 m and 500 m away")
	# The host is a talker too: a client 3 m from the host hears it (clients once dropped frames from peer 1).
	got["bob"].clear()
	host.send_state(Vector3(3, 0, 2), 0.0, 0.0, 0, "", -1, -1, 100.0)
	await _wait(func() -> bool: return (host.latest_state(1).get("pos", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(3, 0, 2)), 2.0)
	host.voice_space = Callable()
	for i: int in range(6):
		host.send_voice(Relay.Mode.PROXIMITY, frame)
		await process_frame
	var from_host: bool = await _wait(func() -> bool: return not got["bob"].is_empty(), 4.0)
	_check(from_host and int(got["bob"][0][0]) == 1 and int(got["bob"][0][1]) == Relay.Mode.PROXIMITY, "e2e: a client hears the HOST talking (sender id 1 is accepted)")
	# A live call: phone A is with Alice at the origin, phone B lies 400 m away next to Carol.
	await _wait(func() -> bool: return false, float(FastNet.VOICE_RADIO_HOLD_MS) / 1000.0 + 0.2)
	got["bob"].clear()
	got["carol"].clear()
	host.voice_phones = func() -> Array: return [{"a": Vector3(0, 0, 0), "b": Vector3(400, 0, 1)}]
	for i: int in range(6):
		alice.send_voice(Relay.Mode.PROXIMITY, frame)
		await process_frame
	var phone_heard: bool = await _wait(func() -> bool: return not got["carol"].is_empty() and not got["bob"].is_empty(), 4.0)
	await _wait(func() -> bool: return false, 0.3)
	_check(phone_heard and int(got["carol"][0][1]) == Relay.Mode.PHONE and int(got["carol"][0][0]) == alice.my_id() and absf(float(got["carol"][0][2]) - 1.0) < 0.5, "e2e: Carol beside the far phone hears Alice over the PHONE mode, stamped with Alice's id")
	_check(int(got["bob"][0][1]) == Relay.Mode.PROXIMITY, "e2e: Bob next to Alice still hears her directly (and not a second, tinny copy)")
	host.voice_phones = Callable()
	for node: FastNet in [carol, bob, alice, host]:
		node.leave()
		node.get_parent().queue_free()
