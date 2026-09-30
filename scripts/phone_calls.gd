extends RefCounted
## Phone calls between two crew PHONES (docs/VOICE_CHAT.md "Phone calls"). Pure state: no scene tree, no
## network, so the tests drive it directly. The host (online.gd) owns the one real instance and replicates
## `to_wire()` to everybody; clients only ever read `from_wire()` results.
##
## A call joins two phone ITEMS, not people: `a` is the phone that dialled, `b` the phone that rings. It
## rings for RING_SECONDS, goes LIVE when `b` is answered, and ends when either side hangs up, nobody
## answers, the call reaches MAX_SECONDS, or the host ends everything (the Day is over).

enum State { RINGING = 0, LIVE = 1 }
const RING_SECONDS: float = 20.0
const MAX_SECONDS: float = 180.0
## Most calls that can exist at once (one per phone pair, and there are four phones).
const MAX_CALLS: int = 8

## {"a": caller phone item, "b": callee phone item, "state": State, "t": seconds in this state, "total": seconds since dialled}
var calls: Array[Dictionary] = []


## The call a phone item is in (either end), or an empty Dictionary.
func call_of(item: int) -> Dictionary:
	for entry: Dictionary in calls:
		if int(entry["a"]) == item or int(entry["b"]) == item:
			return entry
	return {}


func is_busy(item: int) -> bool:
	return not call_of(item).is_empty()


## The phone on the other end of `item`'s call, or -1.
func partner_of(item: int) -> int:
	var entry: Dictionary = call_of(item)
	if entry.is_empty():
		return -1
	return int(entry["b"]) if int(entry["a"]) == item else int(entry["a"])


## Starts ringing `callee` from `caller`. Returns "" on success, else the reason to tell the caller.
func dial(caller: int, callee: int) -> String:
	if caller < 0 or callee < 0 or caller == callee or calls.size() >= MAX_CALLS:
		return "Wrong number."
	if is_busy(caller) or is_busy(callee):
		return "Line busy."
	calls.append({"a": caller, "b": callee, "state": State.RINGING, "t": 0.0, "total": 0.0})
	return ""


## The ringing phone `item` picks up. False when it is not the callee of a ringing call.
func answer(item: int) -> bool:
	var entry: Dictionary = call_of(item)
	if entry.is_empty() or int(entry["state"]) != State.RINGING or int(entry["b"]) != item:
		return false
	entry["state"] = State.LIVE
	entry["t"] = 0.0
	return true


## Ends the call `item` is in. Returns it (with "live_seconds" set) or an empty Dictionary.
func hang_up(item: int) -> Dictionary:
	var entry: Dictionary = call_of(item)
	if entry.is_empty():
		return {}
	calls.erase(entry)
	entry["live_seconds"] = float(entry["t"]) if int(entry["state"]) == State.LIVE else 0.0
	return entry


## Advances every call. Returns the calls that ended on their own, each with "reason": "noanswer" or "timeout".
func tick(delta: float) -> Array[Dictionary]:
	var ended: Array[Dictionary] = []
	for entry: Dictionary in calls.duplicate():
		entry["t"] = float(entry["t"]) + delta
		entry["total"] = float(entry["total"]) + delta
		if int(entry["state"]) == State.RINGING and float(entry["t"]) >= RING_SECONDS:
			calls.erase(entry)
			entry["reason"] = "noanswer"
			entry["live_seconds"] = 0.0
			ended.append(entry)
		elif int(entry["state"]) == State.LIVE and float(entry["t"]) >= MAX_SECONDS:
			calls.erase(entry)
			entry["reason"] = "timeout"
			entry["live_seconds"] = float(entry["t"])
			ended.append(entry)
	return ended


## Ends everything (the Day is over, phones reset). Returns the ended calls with "reason" set.
func clear(reason: String) -> Array[Dictionary]:
	var ended: Array[Dictionary] = []
	for entry: Dictionary in calls:
		entry["reason"] = reason
		entry["live_seconds"] = float(entry["t"]) if int(entry["state"]) == State.LIVE else 0.0
		ended.append(entry)
	calls.clear()
	return ended


## The calls in progress, as [a, b, state, seconds in that state] rows for the wire.
func to_wire() -> Array:
	var out: Array = []
	for entry: Dictionary in calls:
		out.append([int(entry["a"]), int(entry["b"]), int(entry["state"]), snappedf(float(entry["t"]), 0.1)])
	return out


## Validates a wire payload (a peer may send anything): at most MAX_CALLS rows of [a, b, state, t].
## Returns [{"a", "b", "state", "t"}, ...] and silently drops malformed rows.
static func from_wire(data: Variant, max_item: int = 64) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (data is Array):
		return out
	for row: Variant in (data as Array):
		if out.size() >= MAX_CALLS:
			break
		if not (row is Array) or (row as Array).size() != 4:
			continue
		var fields: Array = row
		if not (fields[0] is int and fields[1] is int and fields[2] is int and (fields[3] is float or fields[3] is int)):
			continue
		var a: int = fields[0]
		var b: int = fields[1]
		var state: int = fields[2]
		var t: float = float(fields[3])
		if a < 0 or b < 0 or a >= max_item or b >= max_item or a == b or state < 0 or state > State.LIVE or not is_finite(t):
			continue
		out.append({"a": a, "b": b, "state": state, "t": clampf(t, 0.0, MAX_SECONDS + 5.0)})
	return out
