extends RefCounted
## Host-side routing of voice frames (pure: no scene tree, so tests/voice.gd drives it directly).
##
## Modes: PROXIMITY (default open mic) reaches listeners within `range` metres, and only between
## players in the same living/dead state (the dead cannot feed the living information by listening
## or talking). CREW (hold-to-talk radio) reaches the talker's own crew at any distance, dead or
## alive, and never anyone else: enemies can never receive crew voice.

enum Mode { PROXIMITY = 0, CREW = 1 }
const PROXIMITY_RANGE: float = 35.0
## Different spaces (inside a walk-in building vs outside, or two buildings) only hear each other
## when BOTH stand within this many metres of the same open doorway, and then muffled.
const DOOR_RADIUS: float = 4.0


static func valid_mode(mode: int) -> bool:
	return mode == Mode.PROXIMITY or mode == Mode.CREW


## peers: id -> {"crew": String, "pos": Vector3, "dead": bool, "space": int (-1 = outdoors, else which
## walk-in building)}. doors: world positions of currently OPEN doorways. People inside a building hear
## each other; passersby outside do not (crew radio ignores all of this).
## Returns [[peer_id, distance, muffled], ...].
static func targets(sender: int, mode: int, peers: Dictionary, prox_range: float = PROXIMITY_RANGE, doors: Array = []) -> Array:
	var out: Array = []
	if not peers.has(sender) or not valid_mode(mode):
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
