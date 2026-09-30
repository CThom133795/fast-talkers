extends SceneTree
## Headless checks for scripts/buildings/prefabs.gd (BuildingPrefabs): every kind at its minimum size and at a larger
## size, with several seeds. Each build must register a footprint and a street door (and an escape door where the kind
## has one), keep every doorway clear, be walkable along its published routes (every stair lands on a floor), be
## deterministic for a seed, and stay inside a mesh budget. Prints "PREFABS RESULT: N checks, M failures".
## Run: godot --headless --path . --script res://tests/prefabs.gd
const Prefabs = preload("res://scripts/buildings/prefabs.gd")
const StairWalk = preload("res://tests/stair_walk.gd")

## Where the test buildings go: far from the map (each building carries its own floors).
const ORIGIN: Vector2 = Vector2(6000, 6000)
## Kinds that must have a second way out (label contains one of these).
const ESCAPE_WORDS: Array[String] = ["alley", "rear", "fire exit", "service", "side door", "back door"]
const NEEDS_ESCAPE: Array[String] = ["walkup", "warehouse", "corner_store", "row_shop", "bar", "auto_shop", "office", "church_hall", "diner_small"]

var checks: int = 0
var failures: int = 0
var world: Node3D
var game: Variant
var walker: Node3D
var walk_nodes: Array[Node3D] = []
var slot: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + label)


func _frames(count: int) -> void:
	for i: int in range(count):
		await physics_frame
	await process_frame


func _space() -> PhysicsDirectSpaceState3D:
	return world.get_world_3d().direct_space_state


func _floor_at(at: Vector3, above: float = 1.3) -> float:
	var hit: Dictionary = _space().intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3(0, above, 0), at - Vector3(0, 1.0, 0)))
	return float((hit["position"] as Vector3).y) if not hit.is_empty() else NAN


## A standing body (radius 0.3, feet 0.3 above the floor so one stair riser ahead doesn't count) fits here.
func _clear(at: Vector3, note: String = "") -> bool:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.5
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.3 + 0.75, 0))
	query.collision_mask = 1
	var hits: Array[Dictionary] = _space().intersect_shape(query, 4)
	if not hits.is_empty():
		var collider: Node3D = hits[0]["collider"]
		print("  BLOCKED %s at %s by %s" % [note, at, collider.get_path()])
	return hits.is_empty()


## Samples a local polyline every 0.15 m: the floor under each sample must be where the route expects it (+-0.35 m),
## no step between samples (0.15 m apart) may rise more than 0.2 m, and a body must fit.
func _route_ok(node: Node3D, route: Array, label: String) -> bool:
	var ok: bool = true
	var last: float = NAN
	for i: int in range(route.size() - 1):
		var a: Vector3 = route[i]
		var b: Vector3 = route[i + 1]
		var steps: int = maxi(1, int(ceil(a.distance_to(b) / 0.15)))
		for s: int in range(steps + 1):
			var local: Vector3 = a.lerp(b, float(s) / steps)
			var at: Vector3 = node.global_transform * local
			var floor_y: float = _floor_at(at)
			if is_nan(floor_y) or absf(floor_y - at.y) > 0.35:
				print("  FLOOR %s at local %s: expected %.2f got %s" % [label, local, at.y, floor_y])
				ok = false
				continue
			if not is_nan(last) and absf(floor_y - last) > 0.21:
				print("  STEP %s at local %s: floor jumps %.2f" % [label, local, floor_y - last])
				ok = false
			last = floor_y
			ok = _clear(Vector3(at.x, floor_y, at.z), label + " local %s" % local) and ok
	return ok


func _count_meshes(node: Node) -> Dictionary:
	var meshes: int = 0
	var surfaces: int = 0
	var glass: int = 0
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var owner: Node = child.get_parent()
		if owner is StaticBody3D and owner.get_script() != null:
			glass += 1
			continue
		if owner.has_meta("closed_yaw") or (owner.get_parent() != null and owner.get_parent().has_meta("closed_yaw")) or owner.has_meta("roller") or (owner.get_parent() != null and owner.get_parent().has_meta("roller")):
			continue
		var instance: MeshInstance3D = child as MeshInstance3D
		if instance.mesh != null:
			meshes += 1
			surfaces += instance.mesh.get_surface_count()
	return {"meshes": meshes, "surfaces": surfaces, "glass": glass}


func _signature(node: Node3D) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for door: Dictionary in node.get_meta("doors"):
		parts.append("%s@%s" % [str(door["label"]), str((door["local"] as Vector3).snapped(Vector3(0.001, 0.001, 0.001)))])
	var counts: Dictionary = _count_meshes(node)
	parts.append("m%d s%d g%d" % [counts["meshes"], counts["surfaces"], counts["glass"]])
	parts.append(str(node.get_meta("floor_ys")))
	return "|".join(parts)


func _build(kind: String, size: Vector2, floors: int, seed_value: int) -> Node3D:
	var center: Vector2 = ORIGIN + Vector2(slot * 60.0, 0)
	slot += 1
	var yaw: float = [0.0, PI, PI * 0.5, -PI * 0.5][slot % 4]
	return Prefabs.build(world, kind, center, size, yaw, floors, seed_value, {"district": "TEST"})


func _test_one(kind: String, size: Vector2, floors: int, seed_value: int) -> void:
	var tag: String = "%s %s f%d s%d" % [kind, size, floors, seed_value]
	var footprints_before: int = world.footprints.size()
	var doors_before: int = world.interactable_doors.size()
	var node: Node3D = _build(kind, size, floors, seed_value)
	_check(node != null, tag + " builds")
	if node == null:
		return
	await _frames(2)
	_check(bool(node.get_meta("enterable", false)) and str(node.get_meta("kind", "")) == kind and int(node.get_meta("floors", 0)) >= 1, tag + " has enterable/kind/floors meta")
	_check(world.footprints.size() > footprints_before, tag + " registers a footprint")
	var doors: Array = node.get_meta("doors")
	_check(world.interactable_doors.size() - doors_before == doors.size(), tag + " registers every door it reports")
	var street: int = 0
	var escapes: int = 0
	for door: Dictionary in doors:
		var label: String = str(door["label"])
		if label.ends_with("entrance"):
			street += 1
		for word: String in ESCAPE_WORDS:
			if label.contains(word):
				escapes += 1
				break
		var entry: Dictionary = world.interactable_doors[int(door["index"])]
		_check(float(entry["width"]) >= 1.0 and bool(entry["open"]), "%s door '%s' is registered open" % [tag, label])
		var inside: Vector3 = entry["inside"]
		var floor_y: float = _floor_at(inside)
		_check(not is_nan(floor_y) and _clear(Vector3(inside.x, floor_y, inside.z), label + " inside"), "%s door '%s' has a clear landing inside" % [tag, label])
		var position: Vector3 = entry["position"]
		var sill: float = _floor_at(position)
		_check(not is_nan(sill) and _clear(Vector3(position.x, sill, position.z), label + " threshold"), "%s door '%s' threshold is clear" % [tag, label])
	_check(street >= 1, tag + " has a street door")
	if NEEDS_ESCAPE.has(kind):
		_check(escapes >= 1, tag + " has a second way out")
	var routes: Dictionary = node.get_meta("routes")
	_check(routes.size() >= 1, tag + " publishes walk routes")
	for route_name: String in routes:
		_check(_route_ok(node, routes[route_name], tag + " " + route_name), "%s route %s is walkable" % [tag, route_name])
	var stairs: Array = node.get_meta("stairs")
	var floor_ys: Array = node.get_meta("floor_ys")
	if int(node.get_meta("floors")) > 1:
		_check(stairs.size() >= int(node.get_meta("floors")) - 1, tag + " has a flight for every storey (%d)" % stairs.size())
	for flight: Dictionary in stairs:
		var top: Vector3 = flight["top"]
		var lands: bool = false
		for level: Variant in floor_ys:
			lands = lands or absf(top.y - float(level)) < 0.02
		lands = lands or absf(top.y - float(node.get_meta("roof_y"))) < 0.02
		_check(lands, "%s flight %s lands on a floor (y %.2f)" % [tag, str(flight.get("from", "?")), top.y])
	var counts: Dictionary = _count_meshes(node)
	print("  %s: %d mesh instances, %d surfaces, %d glass panes, %d doors" % [tag, counts["meshes"], counts["surfaces"], counts["glass"], doors.size()])
	_check(int(counts["meshes"]) <= 40, tag + " stays under 40 mesh instances (%d)" % counts["meshes"])
	_check(int(counts["surfaces"]) <= 90, tag + " stays under 90 surfaces (%d)" % counts["surfaces"])
	# Determinism: the same seed builds the same building.
	if seed_value == 2:
		walk_nodes.append(node)
	var again: Node3D = _build(kind, size, floors, seed_value)
	await _frames(1)
	_check(_signature(node) == _signature(again), tag + " is deterministic")


## The real FastPlayer (physics only, no jumps) up every rising route of the larger builds; headless Godot cannot capture
## the mouse, so, like tests/stair_walk.gd, use a copy of player.gd with only the capture gate removed.
func _make_walker() -> Node3D:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return game.player
	var source: String = FileAccess.get_file_as_string("res://scripts/player.gd")
	source = source.replace("class_name FastPlayer" + char(10), "")
	var gate: String = "var controls_active: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and input_grace <= 0.0"
	source = source.replace(gate, "var controls_active: bool = input_grace <= 0.0")
	var script: GDScript = GDScript.new()
	script.source_code = source
	script.reload()
	var node: CharacterBody3D = CharacterBody3D.new()
	node.set_script(script)
	game.add_child(node)
	return node


func _rises(route: Array) -> bool:
	var low: float = 1000.0
	var high: float = -1000.0
	for point: Vector3 in route:
		low = minf(low, point.y)
		high = maxf(high, point.y)
	return high - low > 0.5


func _walk_case(label: String, node: Node3D, route: Array) -> void:
	var points: Array[Vector3] = []
	for point: Vector3 in route:
		points.append(node.global_transform * point)
	walker.reset_player(points[0] + Vector3(0, 0.08, 0))
	walker.rotation.y = StairWalk.yaw_toward(points[1].x - points[0].x, points[1].z - points[0].z)
	await _frames(8)
	var stats: Dictionary = {}
	var reached: bool = await StairWalk.walk_route(self, walker, points, 30.0, stats)
	var want: float = points[points.size() - 1].y
	var got: float = walker.global_position.y
	var landed: bool = absf(got - want) < 0.4 and walker.is_on_floor()
	_check(reached and landed, "%s walked by the real player: reached %s, feet y %.2f (want %.2f)" % [label, str(reached), got, want])


func _walk_phase() -> void:
	Engine.time_scale = 4.0
	walker = _make_walker()
	for node: Node3D in walk_nodes:
		var routes: Dictionary = node.get_meta("routes")
		var names: Array = routes.keys()
		names.sort()
		for route_name: String in names:
			var route: Array = routes[route_name]
			if not _rises(route):
				continue
			var tag: String = "%s %s" % [node.get_meta("kind"), route_name]
			await _walk_case(tag + " UP", node, route)
			var back: Array = route.duplicate()
			back.reverse()
			await _walk_case(tag + " DOWN", node, back)
	Input.action_release("move_forward")
	Engine.time_scale = 1.0


func _run() -> void:
	create_timer(165).timeout.connect(func() -> void:
		push_error("Prefabs suite timed out")
		quit(2))
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.settings_path = "res://.godot/test_settings.cfg"
	root.add_child(game)
	await _frames(3)
	game._start_free_roam()
	await _frames(5)
	world = game.world
	for guard: Variant in game._all_guards():
		guard.set_present(false)
	var only: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("only="):
			only = arg.substr(5)
	for kind: String in Prefabs.kinds():
		if not only.is_empty() and kind != only:
			continue
		var least: Vector2 = Prefabs.min_size(kind)
		var most: int = Prefabs.max_floors(kind)
		var least_floors: int = Prefabs.min_floors(kind)
		await _test_one(kind, least, least_floors, 1)
		await _test_one(kind, least + Vector2(6, 5), most, 2)
		await _test_one(kind, least + Vector2(2, 9), mini(most, least_floors + 1), 3)
		await _test_one(kind, least + Vector2(11, 3), least_floors, 4)
	if not OS.get_cmdline_user_args().has("nowalk"):
		await _walk_phase()
	_check(Prefabs.build(world, "no_such_kind", ORIGIN, Vector2(10, 10), 0.0, 1, 1) == null, "an unknown kind is refused")
	print("PREFABS RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
