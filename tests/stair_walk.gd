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
	create_timer(165.0).timeout.connect(func() -> void:
		push_error("Stair walk suite timed out")
		quit(2))
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.settings_path = "res://.godot/test_settings.cfg"
	root.add_child(game)
	await _frames(3)
	game._start_free_roam()
	await _frames(5)
	var world: Node3D = game.world
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
	print("--- per-flight summary ---")
	for line: String in results:
		print(line)
	print("STAIR WALK RESULT: %d checks, %d failures" % [checks, failures])
	Input.action_release("move_forward")
	quit(0 if failures == 0 else 1)


## Cases not published as routes: the strip club stage steps.
func _extras(world: Node3D) -> Array:
	var extras: Array = []
	if world.plot_nodes.has("stripclub"):
		extras.append(["stripclub stage steps", world.plot_nodes["stripclub"], [Vector3(6.0, 0.17, -2.9), Vector3(4.6, 0.17, -2.9), Vector3(2.4, 1.01, -2.9), Vector3(1.4, 1.01, -2.9)]])
	return extras
