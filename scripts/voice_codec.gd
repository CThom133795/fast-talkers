extends RefCounted
## Voice audio plumbing that needs no scene tree: IMA-ADPCM (4 bit) codec, a linear resampler, and a
## noise-gate voice-activity detector. Pure GDScript so tests/voice.gd can drive it headless.
##
## Wire format of one frame: [predictor s16 LE][step index u8][nibbles...]. The header makes every
## frame decodable on its own (packet loss never desyncs the decoder). One frame = 640 samples at
## 16 kHz = 40 ms -> 3 + 320 bytes = 323 bytes, ~8.1 kB/s (about 65 kbit/s) per talker before RPC overhead.
## The decoder yields 1 + 2*(bytes-3) samples, i.e. one padding sample for an even-length frame.

const RATE: int = 16000
const FRAME_SAMPLES: int = 640
const HEADER_BYTES: int = 3
## Hard cap on anything sent or accepted (2x a normal frame, no more).
const MAX_FRAME_BYTES: int = 3 + 640
const MIN_FRAME_BYTES: int = 4

const STEPS: PackedInt32Array = [
	7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143,
	157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552,
	1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487,
	12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
]
const INDEX_ADJUST: PackedInt32Array = [-1, -1, -1, -1, 2, 4, 6, 8]

## Encoder state carried across frames (only the step index; each frame restates it in its header).
var index: int = 0


## Encodes float samples (-1..1). Returns the wire frame.
func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	var count: int = mini(samples.size(), FRAME_SAMPLES * 2)
	if count < 2:
		return out
	var predictor: int = clampi(int(roundf(samples[0] * 32767.0)), -32768, 32767)
	out.resize(HEADER_BYTES + (count) / 2)
	out.encode_s16(0, predictor)
	out[2] = index
	var pred: int = predictor
	var idx: int = index
	var write: int = HEADER_BYTES
	var low: int = 0
	var have_low: bool = false
	for i: int in range(1, count):
		var target: int = clampi(int(roundf(samples[i] * 32767.0)), -32768, 32767)
		var step: int = STEPS[idx]
		var diff: int = target - pred
		var nibble: int = 0
		if diff < 0:
			nibble = 8
			diff = -diff
		var delta: int = step >> 3
		if diff >= step:
			nibble |= 4
			diff -= step
			delta += step
		step >>= 1
		if diff >= step:
			nibble |= 2
			diff -= step
			delta += step
		step >>= 1
		if diff >= step:
			nibble |= 1
			delta += step
		pred = clampi(pred - delta if (nibble & 8) != 0 else pred + delta, -32768, 32767)
		idx = clampi(idx + INDEX_ADJUST[nibble & 7], 0, 88)
		if have_low:
			out[write] = low | (nibble << 4)
			write += 1
			have_low = false
		else:
			low = nibble
			have_low = true
	if have_low:
		out[write] = low
		write += 1
	out.resize(write)
	index = idx
	return out


## Decodes a wire frame to float samples. Malformed input (too short / too long / bad index) returns [].
static func decode(frame: PackedByteArray) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	if frame.size() < MIN_FRAME_BYTES or frame.size() > MAX_FRAME_BYTES:
		return out
	var pred: int = frame.decode_s16(0)
	var idx: int = int(frame[2])
	if idx > 88:
		return out
	out.resize(1 + (frame.size() - HEADER_BYTES) * 2)
	out[0] = float(pred) / 32768.0
	var write: int = 1
	for read: int in range(HEADER_BYTES, frame.size()):
		var byte: int = frame[read]
		for half: int in range(2):
			var nibble: int = (byte >> (4 * half)) & 15
			var step: int = STEPS[idx]
			var delta: int = step >> 3
			if (nibble & 4) != 0:
				delta += step
			if (nibble & 2) != 0:
				delta += step >> 1
			if (nibble & 1) != 0:
				delta += step >> 2
			pred = clampi(pred - delta if (nibble & 8) != 0 else pred + delta, -32768, 32767)
			idx = clampi(idx + INDEX_ADJUST[nibble & 7], 0, 88)
			out[write] = float(pred) / 32768.0
			write += 1
	return out


## Signal-to-noise ratio in dB of `decoded` against `original` (over the shorter of the two).
static func snr_db(original: PackedFloat32Array, decoded: PackedFloat32Array) -> float:
	var n: int = mini(original.size(), decoded.size())
	var signal_energy: float = 0.0
	var noise_energy: float = 0.0
	for i: int in range(n):
		signal_energy += original[i] * original[i]
		var err: float = original[i] - decoded[i]
		noise_energy += err * err
	return 10.0 * log(maxf(signal_energy, 1e-12) / maxf(noise_energy, 1e-12)) / log(10.0)


static func rms_db(samples: PackedFloat32Array, gain: float = 1.0) -> float:
	if samples.is_empty():
		return -120.0
	var energy: float = 0.0
	for sample: float in samples:
		energy += sample * sample
	return 10.0 * log(maxf(energy * gain * gain / float(samples.size()), 1e-12)) / log(10.0)


## Streaming linear resampler (phase carries across chunks so there are no seams).
class Resampler:
	extends RefCounted
	var from_rate: float = 48000.0
	var to_rate: float = 16000.0
	var _pos: float = 0.0
	var _last: float = 0.0
	var _has_last: bool = false

	func _init(from_hz: float = 48000.0, to_hz: float = 16000.0) -> void:
		from_rate = from_hz
		to_rate = to_hz

	func process(input: PackedFloat32Array) -> PackedFloat32Array:
		var out: PackedFloat32Array = PackedFloat32Array()
		if input.is_empty() or from_rate <= 0.0 or to_rate <= 0.0:
			return out
		var step: float = from_rate / to_rate
		# Virtual stream: [last, input...]; _pos indexes into it (0 = the carried sample).
		var count: int = input.size() + 1
		if not _has_last:
			_last = input[0]
			_has_last = true
		while _pos + 1.0 < float(count):
			var base: int = int(_pos)
			var frac: float = _pos - float(base)
			var a: float = _last if base == 0 else input[base - 1]
			var b: float = input[base]
			out.append(a + (b - a) * frac)
			_pos += step
		_pos -= float(count - 1)
		_last = input[input.size() - 1]
		return out


## Noise gate with hangover: opens above `gate_db`, stays open `hangover` frames after the last loud one.
class Gate:
	extends RefCounted
	var gate_db: float = -42.0
	var hangover: int = 8
	var _left: int = 0
	var open: bool = false

	static func rms_db_of(samples: PackedFloat32Array, gain: float) -> float:
		if samples.is_empty():
			return -120.0
		var energy: float = 0.0
		for sample: float in samples:
			energy += sample * sample
		return 10.0 * log(maxf(energy * gain * gain / float(samples.size()), 1e-12)) / log(10.0)

	## Returns true when this frame should be transmitted.
	func process(samples: PackedFloat32Array, gain: float = 1.0) -> bool:
		if rms_db_of(samples, gain) > gate_db:
			_left = hangover
		elif _left > 0:
			_left -= 1
		open = _left > 0
		return open

	func reset() -> void:
		_left = 0
		open = false
