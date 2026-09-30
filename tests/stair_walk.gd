extends SceneTree
## Stair walk suite: drives the REAL FastPlayer (Input.action_press("move_forward"), physics only, no
## jump and no teleports mid-flight) up and back down every staircase in the game, and checks that the
## player ends on the floor the flight leads to. Reuse `walk_route()` from other suites.
## Run: godot --headless --path . --script res://tests/stair_walk.gd
##
## Cases come from each building's published `routes` meta (every route that changes height is walked
## up and reversed down) plus explicit extras (stage steps, roof stair). Each case is one check; a
## SCRIPT ERROR hangs headless Godot, so always run under `timeout 170`.

var checks: int = 0
var failures: int = 0
var game: Variant
var results: Array[String] = []
var walker: Node3D
var patched: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + label)


## Yaw that makes the player's forward (-Z) point along the horizontal vector (dx, dz).
static func yaw_toward(dx: float, dz: float) -> float:
	return atan2(-dx, -dz)


## Faces the player at each waypoint in turn and holds move_forward until it is within `reach` metres
## (horizontally) of it, using physics only. Returns true when every waypoint was reached in order.
## Fails (false) on `timeout` seconds of simulated time in total, or when the player makes less than
## 0.3 m of horizontal progress over two seconds (snagged on a step). `points` are WORLD positions.
## The caller places the player at points[0] first (a start teleport, never mid-flight). Pass
## `stats` to read back {"frames", "stuck_at", "waypoint"} for reporting.
static func walk_route(tree: SceneTree, player: Node, points: Array[Vector3], timeout: float, stats: Dictionary = {}, reach: float = 0.35) -> bool:
	player.set("input_grace", 0.0)
	var budget: int = int(timeout * 60.0)
	var frames: int = 0
	var window_start: Vector3 = player.global_position
	var window_frames: int = 0
	stats["frames"] = 0
	stats["stuck_at"] = Vector3.INF
	stats["waypoint"] = 0
	var ok: bool = true
	for index: int in range(1, points.size()):
		stats["waypoint"] = index
		var target: Vector3 = points[index]
		while true:
			var flat: Vector3 = target - player.global_position
			flat.y = 0.0
			if flat.length() < reach:
				break
			if frames >= budget:
				ok = false
				break
			player.set("input_grace", 0.0)
			player.rotation.y = yaw_toward(flat.x, flat.z)
			Input.action_press("move_forward")
			await tree.physics_frame
			frames += 1
			window_frames += 1
			if window_frames >= 120:
				var moved: Vector3 = player.global_position - window_start
				moved.y = 0.0
				if moved.length() < 0.3:
					stats["stuck_at"] = player.global_position
					ok = false
					break
				window_start = player.global_position
				window_frames = 0
		if not ok:
			break
	Input.action_release("move_forward")
	stats["frames"] = frames
	# Let the player come to rest so the caller reads a settled height.
	for settle: int in range(20):
		await tree.physics_frame
	return ok


## The player only reads movement while the mouse is captured, and headless Godot cannot capture it.
## When capture does not stick, build the walker from the REAL scripts/player.gd source with only that
## gate removed (same physics, same capsule, same speeds); windowed runs use game.player untouched.
func _make_walker() -> Node3D:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return game.player
	var source: String = FileAccess.get_file_as_string("res://scripts/player.gd")
	source = source.replace("class_name FastPlayer" + char(10), "")
	var gate: String = "var controls_active: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and input_grace <= 0.0"
	_check(source.contains(gate), "player.gd still has the mouse-capture gate this suite patches for headless runs")
	source = source.replace(gate, "var controls_active: bool = input_grace <= 0.0")
	var script: GDScript = GDScript.new()
	script.source_code = source
	script.reload()
	var node: CharacterBody3D = CharacterBody3D.new()
	node.set_script(script)
	game.add_child(node)
	patched = true
	return node


func _frames(count: int) -> void:
	for i: int in range(count):
		await physics_frame
	await process_frame


func _to_world(node: Node3D, route: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for point: Vector3 in route:
		out.append(node.global_transform * point)
	return out


## Walks one case: places the player at the first point, walks, and checks the final height.
func _case(label: String, node: Node3D, route: Array, timeout: float = 40.0) -> void:
	var points: Array[Vector3] = _to_world(node, route)
	var player: Variant = walker
	player.reset_player(points[0] + Vector3(0, 0.08, 0))
	player.rotation.y = yaw_toward(points[1].x - points[0].x, points[1].z - points[0].z)
	await _frames(8)
	var stats: Dictionary = {}
	var reached: bool = await walk_route(self, player, points, timeout, stats)
	var want: float = points[points.size() - 1].y
	var got: float = player.global_position.y
	var landed: bool = absf(got - want) < 0.4 and player.is_on_floor()
	var verdict: String = "reached all %d waypoints, feet y %.2f (want %.2f)" % [points.size() - 1, got, want]
	if not reached:
		verdict = "STOPPED at waypoint %d of %d near %s (y %.2f, want %.2f), %d frames" % [int(stats["waypoint"]), points.size() - 1, stats["stuck_at"], got, want, int(stats["frames"])]
	results.append("%s: %s" % [label, "OK" if reached and landed else "FAIL"])
	_check(reached and landed, "%s: %s" % [label, verdict])


func _rises(route: Array) -> bool:
	var low: float = 1000.0
	var high: float = -1000.0
	for point: Vector3 in route:
		low = minf(low, point.y)
		high = maxf(high, point.y)
	return high - low > 0.5


func _run() -> void:
	create_timer(160.0, true, false, true).timeout.connect(func() -> void:
		push_error("Stair walk suite timed out")
		quit(2))
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.settings_path = "res://.godot/test_settings.cfg"
	root.add_child(game)
	await _frames(3)
	game._start_free_roam()
	await _frames(5)
	var world: Node3D = game.world
	# Physics steps are fixed at 1/60 s whatever the wall clock, so run the walks faster than real time.
	Engine.time_scale = 4.0
	# Guards are practice-only and present in free roam: park them out of the way of the walks.
	for guard: Variant in game._all_guards():
		guard.set_present(false)
	walker = _make_walker()
	print("Walker: ", "patched copy of player.gd (headless: no mouse capture)" if patched else "the game's own FastPlayer")
	# Every published route that changes height, up and reversed down.
	var nodes: Array[Node3D] = []
	for child: Node in world.get_children():
		if child is Node3D and child.has_meta("routes"):
			nodes.append(child as Node3D)
	nodes.sort_custom(func(a: Node3D, b: Node3D) -> bool: return str(a.name) < str(b.name))
	# Map 0.8 places hundreds of prefabs: walk every landmark, and one placed prefab per kind (tests/prefabs.gd
	# walks every kind's stairs at several sizes and seeds).
	var seen_kinds: Dictionary = {}
	var sampled: Array[Node3D] = []
	for node: Node3D in nodes:
		if node.has_meta("enterable") and node.has_meta("kind"):
			var kind: String = str(node.get_meta("kind"))
			if seen_kinds.has(kind):
				continue
			seen_kinds[kind] = true
		sampled.append(node)
	print("Walking %d of %d buildings with routes (prefab kinds: %s)" % [sampled.size(), nodes.size(), ", ".join(PackedStringArray(seen_kinds.keys()))])
	nodes = sampled
	for node: Node3D in nodes:
		var key: String = str(node.name)
		var routes: Dictionary = node.get_meta("routes", {})
		var names: Array = routes.keys()
		names.sort()
		for route_name: String in names:
			var route: Array = routes[route_name]
			if not _rises(route):
				continue
			await _case("%s %s UP" % [key, route_name], node, route)
			var back: Array = route.duplicate()
			back.reverse()
			await _case("%s %s DOWN" % [key, route_name], node, back)
	# Explicit extras that no published route covers.
	for extra: Array in _extras(world):
		await _case(str(extra[0]) + " UP", extra[1], extra[2])
		var back: Array = (extra[2] as Array).duplicate()
		back.reverse()
		await _case(str(extra[0]) + " DOWN", extra[1], back)
	# Every flight of the walked buildings: head room, open sky over the roof stair, no slot beside a flight, no trap.
	await _safety_phase(world, nodes)
	# Curbs and single risers: player.gd _try_step_up walks over a 0.18 m ledge but not a 0.45 m one.
	var pad: Node3D = Node3D.new()
	pad.name = "CurbTestPad"
	world.add_child(pad)
	pad.global_position = Vector3(0, 300, 0)
	var body: StaticBody3D = StaticBody3D.new()
	pad.add_child(body)
	for spec: Array in [[Vector3(0, -0.25, 0), Vector3(24, 0.5, 24)], [Vector3(0, 0.09, -2.0), Vector3(6, 0.18, 1.0)], [Vector3(0, 0.225, -6.0), Vector3(6, 0.45, 1.0)]]:
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = spec[1]
		shape.shape = box
		shape.position = spec[0]
		body.add_child(shape)
	await _frames(2)
	walker.reset_player(pad.global_position + Vector3(0, 0.08, 1.0))
	walker.rotation.y = yaw_toward(0.0, -1.0)
	await _frames(8)
	var curb_stats: Dictionary = {}
	var over: bool = await walk_route(self, walker, [pad.global_position + Vector3(0, 0, 1.0), pad.global_position + Vector3(0, 0.18, -2.0)] as Array[Vector3], 8.0, curb_stats)
	_check(over and walker.global_position.y > 300.1, "a 0.18 m curb is walked up without jumping (y %.2f)" % walker.global_position.y)
	var blocked: bool = await walk_route(self, walker, [walker.global_position, pad.global_position + Vector3(0, 0.45, -7.0)] as Array[Vector3], 4.0, {})
	_check(not blocked and walker.global_position.y < 300.4, "a 0.45 m ledge still blocks (y %.2f)" % walker.global_position.y)
	Input.action_release("move_forward")
	pad.queue_free()
	print("--- per-flight summary ---")
	for line: String in results:
		print(line)
	print("STAIR WALK RESULT: %d checks, %d failures" % [checks, failures])
	Input.action_release("move_forward")
	Engine.time_scale = 1.0
	quit(0 if failures == 0 else 1)


## Cases not published as routes: the strip club stage steps, Halcyon Trust's terrace to the plant room.
func _extras(world: Node3D) -> Array:
	var extras: Array = []
	if world.plot_nodes.has("highrise"):
		var tower_routes: Dictionary = (world.plot_nodes["highrise"] as Node3D).get_meta("routes", {})
		if tower_routes.has("plant_door"):
			extras.append(["highrise plant room door", world.plot_nodes["highrise"], tower_routes["plant_door"]])
	if world.plot_nodes.has("stripclub"):
		extras.append(["stripclub stage steps", world.plot_nodes["stripclub"], [Vector3(6.0, 0.17, -2.9), Vector3(4.6, 0.17, -2.9), Vector3(2.4, 1.01, -2.9), Vector3(1.4, 1.01, -2.9)]])
	return extras


# --- Stair safety: head room, open sky, slots and traps ------------------------------------------------------
## For every flight a kit published (BuildingKit's "flights" meta) in the walked buildings: (1) 2.1 m of clear air
## above every tread; (2) no slot between a flight's open side and a wall that a body could wedge into (every gap
## is <= 0.1 m or >= 0.9 m); (3) points just beside the open sides and past the landing edges are either inside
## solid geometry, or a body dropped there lands on the stair itself or on a floor it can walk back to the flight's
## bottom from (BFS over capsule-sized free cells); (4) the space under a flight's high end is solid. Halcyon
## Trust's roof stair must end in the open (a ray straight up from the last ROOF_ROUTE point hits nothing).
const HEADROOM: float = 2.1
const PROBE_CELL: float = 0.3
## Real walker drops (physics, then walk_route along the BFS path) per building: the rest use an analytic capsule sweep.
const REAL_PROBES: int = 10

var world_ref: Node3D


func _space() -> PhysicsDirectSpaceState3D:
	return world_ref.get_world_3d().direct_space_state


func _capsule_query(at: Vector3, radius: float, height: float) -> PhysicsShapeQueryParameters3D:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, height * 0.5, 0))
	query.collision_mask = 1
	return query


## True when a standing body (feet at `at`) overlaps solid geometry.
func _blocked(at: Vector3, radius: float = 0.3, height: float = 1.8) -> bool:
	return not _space().intersect_shape(_capsule_query(at, radius, height), 1).is_empty()


## Where a standing body dropped with its feet at `at` comes to rest (INF when nothing is below within 16 m).
func _drop_to(at: Vector3) -> Vector3:
	var query: PhysicsShapeQueryParameters3D = _capsule_query(at, 0.3, 1.8)
	query.motion = Vector3(0, -16.0, 0)
	var fractions: PackedFloat32Array = _space().cast_motion(query)
	if fractions.size() < 2 or fractions[0] >= 1.0:
		return Vector3.INF
	return at + query.motion * fractions[0]


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return _space().intersect_ray(PhysicsRayQueryParameters3D.create(from, to))


## Free cell test for the floor walk-back search: a body (radius 0.28) fits 0.3 m above the floor and the floor is there.
func _cell_free(x: float, z: float, floor_y: float) -> bool:
	if _blocked(Vector3(x, floor_y + 0.3, z), 0.28, 1.5):
		return false
	var hit: Dictionary = _ray(Vector3(x, floor_y + 0.6, z), Vector3(x, floor_y - 0.5, z))
	return not hit.is_empty() and absf(float((hit["position"] as Vector3).y) - floor_y) < 0.35


## Breadth-first search over 0.3 m cells at floor level `floor_y`, from `from` to within 1.3 m of any of `goals`.
## Returns the path (waypoints every ~1.8 m, ending at the goal cell), or an empty array when `from` cannot get
## there (or is already there: see `_near`).
func _floor_path(from: Vector3, goals: Array[Vector3], floor_y: float) -> Array[Vector3]:
	var low: Vector2 = Vector2(from.x, from.z)
	var high: Vector2 = low
	for goal_at: Vector3 in goals:
		low = Vector2(minf(low.x, goal_at.x), minf(low.y, goal_at.z))
		high = Vector2(maxf(high.x, goal_at.x), maxf(high.y, goal_at.z))
	low -= Vector2(3.0, 3.0)
	high += Vector2(3.0, 3.0)
	var columns: int = int((high.x - low.x) / PROBE_CELL) + 1
	var rows: int = int((high.y - low.y) / PROBE_CELL) + 1
	var start_cell: Vector2i = Vector2i(int((from.x - low.x) / PROBE_CELL), int((from.z - low.y) / PROBE_CELL))
	var parents: Dictionary = {start_cell: start_cell}
	var queue: Array[Vector2i] = [start_cell]
	var head: int = 0
	var goal: Vector2i = Vector2i(-1, -1)
	var known: Dictionary = {}
	var steps: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		var centre: Vector2 = low + Vector2(cell.x + 0.5, cell.y + 0.5) * PROBE_CELL
		if _near(centre, goals):
			goal = cell
			break
		for step: Vector2i in steps:
			var next: Vector2i = cell + step
			if next.x < 0 or next.y < 0 or next.x >= columns or next.y >= rows or parents.has(next):
				continue
			if not known.has(next):
				var at: Vector2 = low + Vector2(next.x + 0.5, next.y + 0.5) * PROBE_CELL
				known[next] = _cell_free(at.x, at.y, floor_y)
			if known[next]:
				parents[next] = cell
				queue.append(next)
	var path: Array[Vector3] = []
	if goal.x < 0:
		return path
	var back: Vector2i = goal
	var chain: Array[Vector2i] = []
	while back != start_cell:
		chain.append(back)
		back = parents[back]
	chain.reverse()
	for index: int in range(chain.size()):
		if index % 6 == 5 or index == chain.size() - 1:
			var at: Vector2 = low + Vector2(chain[index].x + 0.5, chain[index].y + 0.5) * PROBE_CELL
			path.append(Vector3(at.x, floor_y, at.y))
	return path


## True when the plan point is within 1.3 m of any goal.
func _near(at: Vector2, goals: Array[Vector3]) -> bool:
	for goal_at: Vector3 in goals:
		if Vector2(at.x - goal_at.x, at.y - goal_at.z).length() < 1.3:
			return true
	return false


## True when `at` lies over one of the node's flights or landings (horizontally, with a 0.4 m margin).
func _over_stair(flights: Array, xf: Transform3D, at: Vector3) -> bool:
	for flight: Dictionary in flights:
		var start: Vector3 = xf * (flight["start"] as Vector3)
		var heading: Vector3 = xf.basis * (flight["heading"] as Vector3)
		heading.y = 0.0
		heading = heading.normalized()
		var lateral: Vector3 = Vector3.UP.cross(heading)
		var rel: Vector3 = at - start
		var along: float = rel.dot(heading)
		var across: float = rel.dot(lateral)
		if str(flight["kind"]) == "u_landing":
			if along > -0.4 and along < float(flight["depth"]) + 0.4 and absf(across) < float(flight["span"]) * 0.5 + 0.4:
				return true
		else:
			var length: float = float(flight["steps"]) * float(flight["run"])
			if along > -0.4 and along < length + 0.4 and absf(across) < float(flight["width"]) * 0.5 + 0.4:
				return true
	return false


## Where a body that fell can walk to: one metre before every flight's bottom and one metre beyond every top that
## lands on a floor (world positions; a U stair's first flight tops out on its landing, which is not a floor).
func _flight_goals(flights: Array, xf: Transform3D) -> Array[Vector3]:
	var goals: Array[Vector3] = []
	for flight: Dictionary in flights:
		var kind: String = str(flight["kind"])
		if kind == "u_landing":
			continue
		var heading: Vector3 = xf.basis * (flight["heading"] as Vector3)
		heading.y = 0.0
		heading = heading.normalized()
		var start: Vector3 = xf * (flight["start"] as Vector3)
		if kind != "u_back":
			goals.append(start - heading * 1.0)
		if kind != "u_up":
			var top: Vector3 = start + heading * (float(flight["steps"]) * float(flight["run"]) + 1.0) + Vector3(0, float(flight["steps"]) * float(flight["rise"]), 0)
			goals.append(top)
	return goals


## The goals at a floor level (within 0.35 m of `y`).
func _level_goals(goals: Array[Vector3], y: float) -> Array[Vector3]:
	var level: Array[Vector3] = []
	for goal_at: Vector3 in goals:
		if absf(goal_at.y - y) < 0.35:
			level.append(Vector3(goal_at.x, y, goal_at.z))
	return level


## Probe points for one flight (local frame): [{at, note, slot?, side?, under?}].
func _probe_points(flight: Dictionary) -> Array:
	var points: Array = []
	var start: Vector3 = flight["start"]
	var heading: Vector3 = flight["heading"]
	var lateral: Vector3 = Vector3.UP.cross(heading)
	if str(flight["kind"]) == "u_landing":
		var depth: float = float(flight["depth"])
		var span: float = float(flight["span"])
		for off: float in [0.4, 0.8]:
			for lat: float in [-0.25, 0.25]:
				points.append({"at": start + heading * (depth + off) + lateral * (span * lat) + Vector3(0, 0.25, 0), "from": start + heading * (depth - 0.05) + lateral * (span * lat) + Vector3(0, 0.25, 0),
					"note": "past the landing's far edge (+%.1f)" % off})
			for side: float in [-1.0, 1.0]:
				points.append({"at": start + heading * (depth * 0.5) + lateral * (side * (span * 0.5 + off)) + Vector3(0, 0.25, 0), "from": start + heading * (depth * 0.5) + lateral * (side * (span * 0.5 - 0.05)) + Vector3(0, 0.25, 0),
					"note": "beside the landing (%+.0f, +%.1f)" % [side, off]})
		return points
	var steps: int = int(flight["steps"])
	var run: float = float(flight["run"])
	var rise: float = float(flight["rise"])
	var width: float = float(flight["width"])
	var length: float = steps * run
	for frac: float in [0.3, 0.85]:
		var d: float = length * frac
		var index: int = mini(steps - 1, int(d / run))
		var tread: float = (index + 1) * rise
		for side: float in [-1.0, 1.0]:
			points.append({"at": start + heading * d + lateral * (side * (width * 0.5 - 0.02)) + Vector3(0, tread + 0.3, 0), "note": "side %+.0f at %.0f%%" % [side, frac * 100.0], "slot": true, "side": side})
			for off: float in [0.4, 0.8]:
				points.append({"at": start + heading * d + lateral * (side * (width * 0.5 + off)) + Vector3(0, tread + 0.25, 0), "from": start + heading * d + lateral * (side * (width * 0.5 - 0.05)) + Vector3(0, tread + 0.25, 0),
					"note": "beside side %+.0f at %.0f%% (+%.1f)" % [side, frac * 100.0, off]})
	points.append({"at": start + heading * (length * 0.9) + Vector3(0, float(flight["base_y"]) - start.y + 0.05, 0), "note": "under the high end", "under": true})
	return points


func _safety_phase(world: Node3D, nodes: Array[Node3D]) -> void:
	world_ref = world
	# Halcyon Trust: the roof stair ends under open sky.
	if world.plot_nodes.has("highrise"):
		var tower: Node3D = world.plot_nodes["highrise"]
		var roof: Array = (tower.get_meta("routes") as Dictionary)["roof_stair"]
		var last: Vector3 = tower.global_transform * (roof[roof.size() - 1] as Vector3)
		var up: Dictionary = _ray(last + Vector3(0, 0.3, 0), last + Vector3(0, 30.0, 0))
		_check(up.is_empty(), "Halcyon Trust's roof route ends in the open: nothing within 30 m straight above %s%s" % [last, "" if up.is_empty() else " (hit " + str((up["collider"] as Node).get_path()) + ")"])
	var total_points: int = 0
	var solid_points: int = 0
	var object_points: int = 0
	for node: Node3D in nodes:
		if not node.has_meta("flights"):
			continue
		var flights: Array = node.get_meta("flights")
		var xf: Transform3D = node.global_transform
		var tag: String = str(node.get_meta("kind")) if node.has_meta("kind") else str(node.name)
		var real_left: int = REAL_PROBES if node == world.plot_nodes.get("highrise") else 0
		var goals: Array[Vector3] = _flight_goals(flights, xf)
		var head_bad: Array[String] = []
		var slot_bad: Array[String] = []
		var trap_bad: Array[String] = []
		var under_bad: Array[String] = []
		for flight: Dictionary in flights:
			var kind: String = str(flight["kind"])
			var heading: Vector3 = xf.basis * (flight["heading"] as Vector3)
			heading.y = 0.0
			heading = heading.normalized()
			var lateral: Vector3 = Vector3.UP.cross(heading)
			var base_y: float = (xf * Vector3(0, float(flight["base_y"]), 0)).y
			# Head room above every tread (centre line).
			if kind != "u_landing":
				var start: Vector3 = xf * (flight["start"] as Vector3)
				for index: int in range(int(flight["steps"])):
					var tread: Vector3 = start + heading * ((index + 0.5) * float(flight["run"])) + Vector3(0, (index + 1) * float(flight["rise"]), 0)
					var hit: Dictionary = _ray(tread + Vector3(0, 0.05, 0), tread + Vector3(0, HEADROOM + 0.05, 0))
					if not hit.is_empty():
						head_bad.append("%s step %d: %.2f m (%s)" % [kind, index, float((hit["position"] as Vector3).y) - tread.y, (hit["collider"] as Node).name])
						break
			for probe: Dictionary in _probe_points(flight):
				total_points += 1
				var at: Vector3 = xf * (probe["at"] as Vector3)
				var note: String = "%s %s" % [kind, probe["note"]]
				if probe.has("slot"):
					# Gap between the open side and whatever is beside it, at knee and chest height.
					var outward: Vector3 = lateral * float(probe["side"])
					for height: float in [0.0, 0.9]:
						var from: Vector3 = at + Vector3(0, height, 0)
						var wall: Dictionary = _ray(from, from + outward * 0.95)
						if not wall.is_empty():
							var gap: float = from.distance_to(wall["position"]) - 0.02
							if gap > 0.1:
								slot_bad.append("%s: %.2f m slot at +%.1f m (%s)" % [note, gap, height, (wall["collider"] as Node).name])
					continue
				if probe.has("under"):
					if not _blocked(at, 0.3, 0.6):
						under_bad.append("%s: open space under the flight at %s" % [note, at])
					else:
						solid_points += 1
					continue
				if _blocked(at):
					solid_points += 1
					continue
				# A point on the far side of a wall from the flight is not reachable from it.
				if not _ray(xf * (probe["from"] as Vector3), at).is_empty():
					solid_points += 1
					continue
				var rest: Vector3 = _drop_to(at)
				if rest == Vector3.INF:
					trap_bad.append("%s: nothing below %s" % [note, at])
					continue
				if _over_stair(flights, xf, rest) and absf(rest.y - base_y) > 0.3:
					continue  # landed on the stair itself (or its landing): it walks down from there
				var level_goals: Array[Vector3] = _level_goals(goals, rest.y)
				if level_goals.is_empty():
					object_points += 1  # landed on furniture or a fixture (no floor of this building's stairs is at that height)
					continue
				if _near(Vector2(rest.x, rest.z), level_goals):
					continue
				var path: Array[Vector3] = _floor_path(Vector3(rest.x, rest.y, rest.z), level_goals, rest.y)
				if path.is_empty():
					trap_bad.append("%s: a body landing at %s (y %.2f) cannot walk back to a flight" % [note, rest, rest.y])
					continue
				if real_left > 0:
					real_left -= 1
					walker.reset_player(at + Vector3(0, 0.05, 0))
					await _frames(60)
					var settled: Vector3 = walker.global_position
					if settled.distance_to(rest) > 0.6:
						trap_bad.append("%s: the real body settled at %s, the sweep said %s" % [note, settled, rest])
						continue
					var route: Array[Vector3] = [settled]
					route.append_array(path)
					var stats: Dictionary = {}
					var walked: bool = await walk_route(self, walker, route, 25.0, stats)
					if not walked:
						trap_bad.append("%s: the real body could not walk back (stopped at waypoint %d near %s)" % [note, int(stats["waypoint"]), stats["stuck_at"]])
		_check(head_bad.is_empty(), "%s: 2.1 m of head room above every tread%s" % [tag, "" if head_bad.is_empty() else " FAILED: " + "; ".join(PackedStringArray(head_bad))])
		_check(slot_bad.is_empty(), "%s: no slot of 0.1-0.9 m beside a flight%s" % [tag, "" if slot_bad.is_empty() else " FAILED: " + "; ".join(PackedStringArray(slot_bad))])
		_check(under_bad.is_empty(), "%s: the space under every flight's high end is solid%s" % [tag, "" if under_bad.is_empty() else " FAILED: " + "; ".join(PackedStringArray(under_bad))])
		_check(trap_bad.is_empty(), "%s: nothing dropped beside a flight or landing is stuck%s" % [tag, "" if trap_bad.is_empty() else " FAILED: " + "; ".join(PackedStringArray(trap_bad))])
	print("Trap probe: %d points, %d inside solid geometry or walled off from the flight, %d landed on furniture" % [total_points, solid_points, object_points])
	Input.action_release("move_forward")
