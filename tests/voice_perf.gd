extends SceneTree
## Host voice routing cost against the REAL built city (docs/VOICE_CHAT.md "Host routing cost").
## With open mics the host routes 25-50 frames/s per talker. Each frame used to scan ~700 interiors per player and
## rebuild a list of all ~1,270 doors; now spaces are cached per player and looked up in a grid, and only the open
## doors next to the talker are fetched. This checks the grids agree with the plain scans, the routed targets are
## identical to the unoptimised path, and that 1,000 frames to 8 peers take under 250 ms.
## Run: godot --headless --path . --script res://tests/voice_perf.gd

const Relay = preload("res://scripts/voice_relay.gd")
const PORT: int = 24775
const SETTINGS: String = "user://voice_perf_settings.cfg"

var game: Variant
var net: FastNet
var checks: int = 0
var failures: int = 0
var tap_rows: Array = []
var finished: bool = false


func _initialize() -> void:
	create_timer(150.0).timeout.connect(func() -> void:
		if not finished:
			_check(false, "watchdog: voice_perf finished within 150 s")
			_finish())
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _finish() -> void:
	if finished:
		return
	finished = true
	if net != null:
		net.leave()
	print("VOICE PERF RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _record(target: int, sender: int, mode: int, _dist: float, _frame: PackedByteArray, muffled: bool = false) -> void:
	tap_rows.append([target, sender, mode, muffled])


## The original scan: every interior, matrix inverse each (kept here as the reference for the grid).
func _naive_building(at: Vector3) -> Node3D:
	for node: Node3D in game._interior_nodes:
		if not is_instance_valid(node):
			continue
		var local: Vector3 = node.global_transform.affine_inverse() * at
		var half: Vector2 = node.get_meta("interior_half")
		var ceiling: float = 5.5 if node.name.begins_with("Garage") else (4.3 if node.name.begins_with("Motel") else 9.0)
		if absf(local.x) < half.x and absf(local.z) < half.y and local.y > -1.0 and local.y < ceiling:
			return node
	return null


func _naive_space(at: Vector3) -> int:
	var building: Node3D = _naive_building(at)
	return -1 if building == null else building.get_instance_id()


func _naive_doors() -> Array:
	var out: Array = []
	for door: Dictionary in game.world.interactable_doors:
		if bool(door.get("open", false)) and door.get("position") is Vector3:
			out.append(door["position"])
	return out


func _run() -> void:
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.pause_on_focus_loss = false
	game.settings_path = SETTINGS
	root.add_child(game)
	for i: int in range(4):
		await process_frame
	net = game.net
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	# --- building lookup: grid vs the plain scan -----------------------------------------------------------
	var t0: int = Time.get_ticks_usec()
	game._building_at(Vector3.ZERO)
	var build_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	var interiors: Array = game._interior_nodes
	print("interiors: %d, scan + grid build: %.1f ms, grid cells: %d" % [interiors.size(), build_ms, game._interior_grid.size()])
	_check(interiors.size() > 100, "the real city has walk-in interiors (%d)" % interiors.size())
	var bounds: Rect2 = game.world.map_bounds()
	var samples: Array[Vector3] = []
	for i: int in range(2500):
		samples.append(Vector3(rng.randf_range(bounds.position.x, bounds.end.x), rng.randf_range(0.0, 8.0), rng.randf_range(bounds.position.y, bounds.end.y)))
	for node: Node3D in interiors:
		var half: Vector2 = node.get_meta("interior_half")
		for k: int in range(3):
			# Inside, just inside an edge, just outside an edge, above the ceiling, below the floor.
			samples.append(node.global_transform * Vector3(rng.randf_range(-half.x, half.x) * 0.9, 1.0, rng.randf_range(-half.y, half.y) * 0.9))
		samples.append(node.global_transform * Vector3(half.x - 0.05, 1.0, 0.0))
		samples.append(node.global_transform * Vector3(half.x + 0.05, 1.0, 0.0))
		samples.append(node.global_transform * Vector3(0.0, 12.0, 0.0))
		samples.append(node.global_transform * Vector3(0.0, -2.0, 0.0))
	var mismatches: int = 0
	var inside: int = 0
	for at: Vector3 in samples:
		var fast: Node3D = game._building_at(at)
		if fast != _naive_building(at):
			mismatches += 1
		if fast != null:
			inside += 1
	_check(mismatches == 0, "the interior grid finds the same building as the full scan at %d sample points (%d mismatches, %d inside a building)" % [samples.size(), mismatches, inside])
	# --- doors: open doors near a point vs the plain list ----------------------------------------------------
	var doors: Array[Dictionary] = game.world.interactable_doors
	var lifts: int = 0
	for index: int in range(doors.size()):
		if str(doors[index].get("kind", "")) == "lift":
			lifts += 1
		# Open roughly a third of them, lifts included (they are the moving ones).
		doors[index]["open"] = rng.randf() < 0.35
	print("doors: %d (%d lift doors)" % [doors.size(), lifts])
	var door_bad: int = 0
	for index: int in range(0, doors.size(), 3):
		var centre: Vector3 = doors[index]["position"]
		var at: Vector3 = centre + Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-6.0, 6.0))
		var fast: Array = game._open_doors_near(at, Relay.DOOR_RADIUS)
		var slow: Array = _naive_doors().filter(func(p: Vector3) -> bool: return at.distance_to(p) <= Relay.DOOR_RADIUS)
		fast.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x or (a.x == b.x and a.z < b.z))
		slow.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x or (a.x == b.x and a.z < b.z))
		if fast != slow:
			door_bad += 1
	_check(door_bad == 0, "the door grid returns exactly the open doors within reach of a point (%d of %d probes differed)" % [door_bad, (doors.size() + 2) / 3])
	_check(game._open_doors_near(Vector3(99999, 0, 99999), 4.0).is_empty(), "no doors far from the city")
	# --- routed targets: optimised host path vs Relay with naive spaces and the full door list ---------------
	_check(net.host(PORT, "127.0.0.1") == OK, "the game's net hosts on localhost")
	for id: int in range(2, 9):
		net.players[id] = net._new_entry("P%d" % id)
		net._hello_done[id] = true
		net.players[id]["crew"] = "morris" if id % 2 == 0 else "kingsway"
	net.voice_tap = _record
	var frame: PackedByteArray = PackedByteArray()
	frame.resize(323)
	var differing: int = 0
	var scenarios: int = 0
	var muffled_seen: int = 0
	for scenario: int in range(240):
		var node: Node3D = interiors[rng.randi() % interiors.size()]
		var half: Vector2 = node.get_meta("interior_half")
		var positions: Dictionary = {}
		var ids: Array = range(1, 9)
		for slot: int in range(ids.size()):
			var id: int = ids[slot]
			var pos: Vector3
			if slot % 2 == 0:
				pos = node.global_transform * Vector3(rng.randf_range(-half.x, half.x) * 0.9, 0.5, rng.randf_range(-half.y, half.y) * 0.9)
			else:
				# Outside, hugging the building's edge (where doorways and walls decide the answer).
				pos = node.global_transform * Vector3((half.x + rng.randf_range(0.5, 6.0)) * (1.0 if rng.randf() < 0.5 else -1.0), 0.5, rng.randf_range(-half.y, half.y))
			positions[id] = pos
			net._latest[id] = {"pos": pos, "flags": 0}
		# A doorway right at the talker now and then, so the muffled path is exercised.
		var sender: int = 1 + (scenario % 8)
		if scenario % 3 == 0:
			var nearest: Dictionary = {}
			var best: float = INF
			for door: Dictionary in doors:
				var d: float = (door["position"] as Vector3).distance_to(positions[sender])
				if d < best and str(door.get("kind", "")) != "lift":
					best = d
					nearest = door
			if not nearest.is_empty() and best < 40.0:
				# Move another peer and the sender next to that door.
				var door_at: Vector3 = nearest["position"]
				nearest["open"] = true
				positions[sender] = door_at + Vector3(1.0, 0.0, 0.0)
				net._latest[sender] = {"pos": positions[sender], "flags": 0}
				var other: int = 1 + ((scenario + 3) % 8)
				if other != sender:
					positions[other] = door_at + Vector3(-1.0, 0.0, 0.0)
					net._latest[other] = {"pos": positions[other], "flags": 0}
		net._voice_space_cache.clear()
		net._voice_radio_until.clear()
		tap_rows.clear()
		net._h_voice(sender, Relay.Mode.PROXIMITY, frame)
		var fast_rows: Array = tap_rows.map(func(r: Array) -> Array: return [r[0], r[3]])
		fast_rows.sort()
		var reference_peers: Dictionary = {}
		for id: int in positions.keys():
			reference_peers[id] = {"crew": net.crew_of(id), "pos": positions[id], "dead": false, "space": _naive_space(positions[id])}
		var slow_rows: Array = Relay.targets(sender, Relay.Mode.PROXIMITY, reference_peers, net.voice_range, _naive_doors()).map(func(r: Array) -> Array: return [r[0], r[2]])
		slow_rows.sort()
		scenarios += 1
		for row: Array in slow_rows:
			if bool(row[1]):
				muffled_seen += 1
		if fast_rows != slow_rows:
			differing += 1
			print("DIFF scenario %d sender %d\n  fast %s\n  slow %s" % [scenario, sender, str(fast_rows), str(slow_rows)])
	_check(differing == 0, "the optimised routing picks the same targets (and muffling) as the unoptimised path in %d scenarios (%d differ; %d muffled deliveries seen)" % [scenarios, differing, muffled_seen])
	# --- the benchmark --------------------------------------------------------------------------------------
	# Eight players crowd one big interior and the street beside it, so every frame has everybody in earshot.
	var hub: Node3D = interiors[0]
	var biggest: float = 0.0
	for node: Node3D in interiors:
		var size: float = (node.get_meta("interior_half") as Vector2).length()
		if size > biggest:
			biggest = size
			hub = node
	var hub_half: Vector2 = hub.get_meta("interior_half")
	var base: Dictionary = {}
	for id: int in range(1, 9):
		var pos: Vector3 = hub.global_transform * Vector3(rng.randf_range(-hub_half.x, hub_half.x) * 0.8, 0.5, rng.randf_range(-hub_half.y, hub_half.y) * 0.8)
		if id > 5:
			pos = hub.global_transform * Vector3(hub_half.x + 2.0 * float(id - 5), 0.5, 0.0)
		base[id] = pos
	net.voice_tap = func(_t: int, _s: int, _m: int, _d: float, _f: PackedByteArray, _mu: bool) -> void: pass
	net._h_voice(1, Relay.Mode.PROXIMITY, frame)
	var started: int = Time.get_ticks_usec()
	for n: int in range(1000):
		var id: int = 1 + (n % 8)
		# Everyone shuffles a few centimetres a frame (walking speed at 25 frames a second per talker).
		var drift: Vector3 = Vector3(sin(float(n) * 0.05), 0.0, cos(float(n) * 0.05)) * 0.04 * float(n % 50)
		net._latest[id] = {"pos": base[id] + drift, "flags": 0}
		net._voice_radio_until.clear()
		net._h_voice(id, Relay.Mode.PROXIMITY, frame)
	var cached_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	print("1000 voice frames, 8 peers, real city: %.1f ms total (%.3f ms per frame)" % [cached_ms, cached_ms / 1000.0])
	_check(cached_ms < 250.0, "routing 1,000 voice frames with 8 peers takes %.1f ms (< 250 ms)" % cached_ms)
	# Worst case: nobody's space is ever cached, so every frame looks up all 8 players.
	started = Time.get_ticks_usec()
	for n: int in range(1000):
		net._voice_space_cache.clear()
		net._voice_radio_until.clear()
		net._h_voice(1 + (n % 8), Relay.Mode.PROXIMITY, frame)
	var cold_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	print("same with the space cache cleared every frame: %.1f ms" % cold_ms)
	_check(cold_ms < 250.0, "even with no cache hits, 1,000 frames take %.1f ms (< 250 ms)" % cold_ms)
	# For the record: the old path (a full scan per player per frame), on a tenth of the frames.
	started = Time.get_ticks_usec()
	for n: int in range(100):
		for id: int in range(1, 9):
			_naive_space(base[id])
		_naive_doors()
	var old_ms: float = float(Time.get_ticks_usec() - started) / 1000.0 * 10.0
	print("the old per-frame scan would take about %.0f ms for the same 1000 frames" % old_ms)
	_finish()
