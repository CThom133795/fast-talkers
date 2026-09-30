extends SceneTree
## Public-space safety, real collision, walk-in rooms and actual vehicle acceleration/caps.
const World = preload("res://scripts/world.gd")
const Car = preload("res://scripts/car.gd")
var checks: int = 0
var failures: int = 0
var world: Node3D

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

func _clear(at: Vector3) -> bool:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.7
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 1.0, 0))
	query.collision_mask = 1
	var hits: Array[Dictionary] = world.get_world_3d().direct_space_state.intersect_shape(query)
	if not hits.is_empty():
		var collider: Node3D = hits[0]["collider"]
		print("BLOCKED at %s by %s at %s" % [at, collider.get_path(), collider.global_position])
	return hits.is_empty()

func _run() -> void:
	create_timer(100).timeout.connect(func() -> void: quit(2))
	# main.gd normally registers gameplay actions; this isolated world/car test supplies them.
	for action: String in ["move_left", "move_right", "stick_left", "stick_right", "move_forward", "move_back", "pad_throttle", "pad_brake", "handbrake"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	world = World.new()
	root.add_child(world)
	await _frames(3)
	_check(world.public_spaces.size() == 8, "Eight authored public spaces")
	_check(world.city_furniture.size() >= 45, "City has substantial new furniture (%d props)" % world.city_furniture.size())
	var kinds: Dictionary = {}
	for item: Dictionary in world.city_furniture:
		kinds[item["kind"]] = true
		var at: Vector2 = item["at"]
		var radius: float = item["radius"]
		var clear_roads: bool = true
		for road: Dictionary in world.roads:
			var points: PackedVector2Array = road["points"]
			for i: int in range(points.size() - 1):
				clear_roads = clear_roads and at.distance_to(Geometry2D.get_closest_point_to_segment(at, points[i], points[i + 1])) >= float(road["width"]) * 0.5 + radius + 0.79
		_check(clear_roads, "%s %s leaves road and shoulder clear" % [item["site"], item["kind"]])
		var collision_ok: bool = not (item["solids"] as Array).is_empty()
		for solid: Dictionary in item["solids"]:
			var p: Vector3 = solid["at"]
			var size: Vector3 = solid["size"]
			var dir: Vector3 = Basis(Vector3.UP, float(solid["yaw"])) * Vector3.FORWARD
			var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p - dir * (size.z * 0.5 + 0.1), p))
			collision_ok = collision_ok and not hit.is_empty()
		_check(collision_ok, "%s has collision matching its solid furniture" % item["kind"])
	for kind: String in ["raised planter", "bench", "picnic table", "newsstand", "hot dog cart", "parking wheel stop", "community board"]:
		_check(kinds.has(kind), "Built " + kind)
	# Public crossing paths stay usable at standing height, not merely present in the road graph.
	for name: String in ["West End Gardens", "Nightlife Commons", "Old Town Green"]:
		for spec: Dictionary in world.public_spaces:
			if spec["name"] != name:
				continue
			var rect: Rect2 = spec["rect"]
			var open: bool = true
			for step: int in range(11):
				var p: Vector2 = Vector2(lerpf(rect.position.x + 2, rect.end.x - 2, step / 10.0), rect.get_center().y)
				open = open and _clear(Vector3(p.x, 0.22, p.y))
			_check(open, name + " retains an open pedestrian crossing")
	for key: String in ["burger", "motel"]:
		var node: Node3D = world.plot_nodes[key]
		_check(node.has_meta("walk_in") and node.has_node("Interior"), key + " is a furnished walk-in building")
		var through: bool = true
		var half: Vector2 = node.get_meta("interior_half")
		for i: int in range(21):
			through = through and _clear(node.global_transform * Vector3(0, 0.12, lerpf(-half.y - 1, half.y + 1, i / 20.0)))
		_check(through, key + " front-to-back escape aisle is walkable")
	# Drive all types on an isolated, collision-backed straight test surface.
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(160, 1, 1200)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(1100, -0.5, 700)
	root.add_child(floor_body)
	var cars: Array[Node3D] = []
	var old_accel: Array[float] = [7.2, 9.0, 6.0, 6.4, 11.0]
	for kind: String in ["sedan", "coupe", "suv", "pickup", "motorcycle"]:
		var car: Node3D = Car.new()
		car.vehicle_type = kind
		root.add_child(car)
		car.reset_car(Vector3(1040 + cars.size() * 24, 0.2, 1100))
		car.enabled = true
		cars.append(car)
	await _frames(10)
	for car: Node3D in cars:
		car.occupied = true
	Input.action_press("move_forward")
	await _frames(120)
	for i: int in range(cars.size()):
		var car: Node3D = cars[i]
		var speed: float = car.velocity.length()
		_check(speed > 6 and speed < old_accel[i] * 1.65, "%s two-second acceleration is restrained (%.1f m/s)" % [car.vehicle_type, speed])
	await _frames(780)
	for car: Node3D in cars:
		var speed: float = car.velocity.length()
		_check(speed >= car.maximum_forward_speed - 0.2 and speed <= car.maximum_forward_speed + 0.2, "%s reaches its reduced cap (%.1f km/h)" % [car.vehicle_type, speed * 3.6])
	Input.action_release("move_forward")
	Input.action_press("move_back")
	var stopped: Dictionary = {}
	for i: int in range(120):
		await physics_frame
		for car: Node3D in cars:
			if not stopped.has(car) and car.velocity.dot(-car.global_transform.basis.z) <= 0.3:
				stopped[car] = true
				car.occupied = false
	Input.action_release("move_back")
	for car: Node3D in cars:
		_check(stopped.has(car), car.vehicle_type + " retains responsive braking")
		car.queue_free()
	floor_body.queue_free()
	world.queue_free()
	await _frames(3)
	print("CITY DETAIL RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
