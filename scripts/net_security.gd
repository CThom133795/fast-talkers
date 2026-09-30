class_name NetSecurity
extends RefCounted
## Reusable validation helpers for the listen-server (docs/NETWORK_SECURITY_AND_STEAM.md).
## Everything here is pure (no scene tree, no multiplayer), so tests/net_security.gd can drive it directly.
##
## The host is the only referee: every `any_peer` RPC arriving at the host goes through `FastNet`, which
## uses these helpers to check shapes, ranges, ownership and rates before anything reaches game code.

## Bump whenever an RPC signature, the RPC list order or the world generation changes. Peers whose
## protocol or build tag differ are refused at the handshake (the world is built by creation order, so
## mismatched builds would silently disagree about car / door / item indices).
const PROTOCOL: int = 3
## Longest string any RPC argument may carry before it is even looked at.
const MAX_WIRE_STRING: int = 512
## Movement snapshot bounds: nothing in the game moves faster than this (cars top out well below).
const MAX_SPEED: float = 110.0
## Extra metres allowed per snapshot for jitter, bunched packets and seat snaps.
const TELEPORT_SLACK: float = 18.0
## Default playable box; FastNet.map_bounds can be narrowed by the lead.
const MAP_HALF_EXTENT: float = 6000.0
const MAP_MIN_Y: float = -200.0
const MAP_MAX_Y: float = 1500.0


## The build tag compared at the handshake: "<protocol>|<config/version>".
static func build_tag() -> String:
	return "%d|%s" % [PROTOCOL, str(ProjectSettings.get_setting("application/config/version", "dev"))]


## Handshake check. Returns "" when the peer may join, else a short human reason.
static func check_version(theirs: String, ours: String) -> String:
	if theirs.length() > 64:
		return "bad handshake"
	if theirs != ours:
		return "version mismatch (host %s, you %s)" % [ours, clean_text(theirs, 32)]
	return ""


## Printable, bracket-free (no BBCode), length-clamped text. Oversized input is cut before scanning,
## so a 1 MB chat line costs the host no more than a normal one.
static func clean_text(text: String, max_len: int) -> String:
	var src: String = text.substr(0, maxi(max_len, 0) * 4 + 8)
	var out: PackedStringArray = PackedStringArray()
	for index: int in range(src.length()):
		var code: int = src.unicode_at(index)
		if code < 32 or code == 127 or (code >= 0x80 and code < 0xA0):
			continue
		if (code >= 0x200B and code <= 0x200F) or (code >= 0x202A and code <= 0x202E) or (code >= 0x2066 and code <= 0x2069) or code == 0xFEFF:
			continue
		if code >= 0xD800 and code <= 0xDFFF:
			continue
		if code == 91:
			out.append("(")
		elif code == 93:
			out.append(")")
		else:
			out.append(src[index])
	return "".join(out).strip_edges().substr(0, max_len)


static func string_ok(text: String, max_len: int = MAX_WIRE_STRING) -> bool:
	return text.length() <= max_len


static func finite_f(value: float, limit: float) -> bool:
	return is_finite(value) and absf(value) < limit


static func finite_v(value: Vector3, limit: float) -> bool:
	return value.is_finite() and absf(value.x) < limit and absf(value.y) < limit and absf(value.z) < limit


static func int_in(value: int, lo: int, hi: int) -> bool:
	return value >= lo and value <= hi


## Inside the playable box (defaults above).
static func in_map(pos: Vector3, half_extent: float = MAP_HALF_EXTENT) -> bool:
	return pos.is_finite() and absf(pos.x) <= half_extent and absf(pos.z) <= half_extent and pos.y >= MAP_MIN_Y and pos.y <= MAP_MAX_Y


## Could a body get from `from` to `to` in `seconds`? (speed cap + fixed slack)
static func step_ok(from: Vector3, to: Vector3, seconds: float, max_speed: float = MAX_SPEED, slack: float = TELEPORT_SLACK) -> bool:
	return from.distance_to(to) <= max_speed * clampf(seconds, 0.0, 2.0) + slack


## Upper bound of damage one accepted claim may carry for a weapon: every pellet, headshot, 50 %
## slack for mods. Weapon "" (a car hitting someone) falls back to `fallback`.
static func max_claim_damage(weapon: String, weapons: Dictionary, fallback: float) -> float:
	if weapon.is_empty() or not weapons.has(weapon):
		return fallback
	var stats: Dictionary = weapons[weapon]
	var base: float = float(stats.get("damage", 0.0)) * maxf(1.0, float(stats.get("pellets", 1))) * maxf(1.0, float(stats.get("headshot", 2.0)))
	return minf(base * 1.5, fallback * 2.0)


## Longest distance a weapon's hit claim may span.
static func weapon_range(weapon: String, weapons: Dictionary, fallback: float) -> float:
	if weapon.is_empty() or not weapons.has(weapon):
		return fallback
	var falloff: Variant = (weapons[weapon] as Dictionary).get("falloff", null)
	if falloff is Vector3:
		# Shots keep flying past the falloff end at reduced damage; 4x the end, capped by the fallback.
		return minf(maxf((falloff as Vector3).y * 4.0, 60.0), fallback)
	return fallback


## Dictionary shape guard: size cap and only String keys (host -> client payloads).
static func dict_ok(data: Dictionary, max_size: int = 64) -> bool:
	if data.size() > max_size:
		return false
	for key: Variant in data.keys():
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME and typeof(key) != TYPE_INT:
			return false
	return true


## Token bucket: `capacity` burst, `rate` tokens per second. `now_ms` is injectable for tests.
class TokenBucket:
	extends RefCounted
	var capacity: float
	var rate: float
	var tokens: float
	var stamp: int = -1

	func _init(cap: float, per_second: float) -> void:
		capacity = cap
		rate = per_second
		tokens = cap

	func take(now_ms: int, cost: float = 1.0) -> bool:
		if stamp >= 0:
			tokens = minf(capacity, tokens + float(maxi(now_ms - stamp, 0)) * rate / 1000.0)
		stamp = now_ms
		if tokens >= cost:
			tokens -= cost
			return true
		return false


## Per-peer strike counter with decay: `limit` strikes inside the decay window means kick.
class Strikes:
	extends RefCounted
	var limit: int
	var decay_ms: int
	var _data: Dictionary = {}

	func _init(max_strikes: int = 10, decay_every_ms: int = 5000) -> void:
		limit = max_strikes
		decay_ms = decay_every_ms

	## Adds a strike; returns true when the peer crossed the limit.
	func add(peer: int, now_ms: int, weight: int = 1) -> bool:
		var entry: Array = _data.get(peer, [0, now_ms])
		var decayed: int = (now_ms - int(entry[1])) / maxi(decay_ms, 1)
		var count: int = maxi(int(entry[0]) - decayed, 0)
		if decayed > 0:
			entry[1] = now_ms
		count += weight
		entry[0] = count
		_data[peer] = entry
		return count >= limit

	func count(peer: int) -> int:
		return int((_data.get(peer, [0, 0]) as Array)[0])

	func clear(peer: int) -> void:
		_data.erase(peer)

	func reset() -> void:
		_data.clear()
