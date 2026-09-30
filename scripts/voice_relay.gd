extends RefCounted
## Host-side routing of voice frames (pure: no scene tree, so tests/voice.gd drives it directly).
##
## Modes: PROXIMITY (default open mic) reaches listeners within `range` metres, and only between
## players in the same living/dead state (the dead cannot feed the living information by listening
## or talking). CREW (hold-to-talk radio) reaches the talker's own crew at any distance, dead or
## alive, and never anyone else: enemies can never receive crew voice. PHONE is host-made only: when a
## talker stands by a phone that is in a live call, the same frame is also relayed to whoever stands by the
## OTHER phone (`phone_targets`). Clients may only send PROXIMITY or CREW; PHONE exists on the receiving side.

enum Mode { PROXIMITY = 0, CREW = 1, PHONE = 2 }
const PROXIMITY_RANGE: float = 35.0
## A talker this close to a phone in a live call is picked up by it (a held phone is at its holder, so the
## holder always is). Close enough that the phone does not pick up the whole room.
const PHONE_PICKUP: float = 1.2
## Listeners this close to the OTHER phone of a live call hear it (a speakerphone on the table).
const PHONE_SPEAKER: float = 3.5
## Different spaces (inside a walk-in building vs outside, or two buildings) only hear each other
## when BOTH stand within this many metres of the same open doorway, and then muffled.
const DOOR_RADIUS: float = 4.0


## Any mode a listener may be told about (what `_relay_voice` accepts).
static func valid_mode(mode: int) -> bool:
	return mode == Mode.PROXIMITY or mode == Mode.CREW or mode == Mode.PHONE


## The modes a client may SEND to the host. PHONE is never one of them: the host decides it.
static func valid_send_mode(mode: int) -> bool:
	return mode == Mode.PROXIMITY or mode == Mode.CREW


## peers: id -> {"crew": String, "pos": Vector3, "dead": bool, "space": int (-1 = outdoors, else which
## walk-in building)}. doors: world positions of currently OPEN doorways. People inside a building hear
## each other; passersby outside do not (crew radio ignores all of this).
## Returns [[peer_id, distance, muffled], ...].
static func targets(sender: int, mode: int, peers: Dictionary, prox_range: float = PROXIMITY_RANGE, doors: Array = []) -> Array:
	var out: Array = []
	if not peers.has(sender) or not valid_send_mode(mode):
		return out
	var me: Dictionary = peers[sender]
	var my_pos: Vector3 = me.get("pos", Vector3.INF)
	var my_crew: String = String(me.get("crew", ""))
	for id: int in peers.keys():
		if id == sender:
			continue
		var them: Dictionary = peers[id]
		var pos: Vector3 = them.get("pos", Vector3.INF)
		var dist: float = my_pos.distance_to(pos) if my_pos.is_finite() and pos.is_finite() else INF
		if mode == Mode.CREW:
			if my_crew.is_empty() or String(them.get("crew", "")) != my_crew:
				continue
			out.append([id, minf(dist, 9999.0) if is_finite(dist) else 0.0, false])
		else:
			if not is_finite(dist) or dist > prox_range or bool(them.get("dead", false)) != bool(me.get("dead", false)):
				continue
			var muffled: bool = false
			if int(me.get("space", -1)) != int(them.get("space", -1)):
				if not _through_door(my_pos, pos, doors):
					continue
				muffled = true
			out.append([id, dist, muffled])
	return out


static func _through_door(a: Vector3, b: Vector3, doors: Array) -> bool:
	for door: Variant in doors:
		if door is Vector3 and a.distance_to(door) <= DOOR_RADIUS and b.distance_to(door) <= DOOR_RADIUS:
			return true
	return false


## Who also hears a PROXIMITY frame through a phone. calls: [{"a": Vector3, "b": Vector3}, ...], the positions
## of the two phones of every LIVE call (a held phone is at its holder). A living talker within `pickup` metres
## of one phone is carried to every living listener within `speaker` metres of the other. The dead cannot use
## phones, and crew radio never comes through here (the host only calls this for proximity frames).
## Returns [[peer_id, metres to the speaking phone], ...].
static func phone_targets(sender: int, peers: Dictionary, calls: Array, pickup: float = PHONE_PICKUP, speaker: float = PHONE_SPEAKER) -> Array:
	var out: Dictionary = {}
	if not peers.has(sender) or calls.is_empty():
		return []
	var me: Dictionary = peers[sender]
	var my_pos: Vector3 = me.get("pos", Vector3.INF)
	if bool(me.get("dead", false)) or not my_pos.is_finite():
		return []
	for call: Variant in calls:
		if not (call is Dictionary):
			continue
		var phones: Array = [call.get("a", Vector3.INF), call.get("b", Vector3.INF)]
		for side: int in range(2):
			var near: Variant = phones[side]
			var far: Variant = phones[1 - side]
			if not (near is Vector3) or not (far is Vector3) or not (near as Vector3).is_finite() or not (far as Vector3).is_finite():
				continue
			if my_pos.distance_to(near) > pickup:
				continue
			for id: int in peers.keys():
				if id == sender:
					continue
				var them: Dictionary = peers[id]
				var pos: Vector3 = them.get("pos", Vector3.INF)
				if bool(them.get("dead", false)) or not pos.is_finite():
					continue
				var dist: float = pos.distance_to(far)
				if dist <= speaker and dist < float(out.get(id, INF)):
					out[id] = dist
	var rows: Array = []
	for id: int in out.keys():
		rows.append([id, float(out[id])])
	return rows
