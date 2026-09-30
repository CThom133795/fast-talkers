extends SceneTree
## CLUB VOLTAGE, THE VELVET ROOM, the HOTEL MERIDIAN ground floor and the burger drive-through: walk-in interiors, real exits, walkable routes (including the
## mezzanine stair and stage steps), rail/cover collision that matches what is drawn, lamp budget,
## merged meshes and no leftover solid stub shell.
const World = preload("res://scripts/world.gd")
const Nightclub = preload("res://scripts/buildings/nightclub.gd")
const Stripclub = preload("res://scripts/buildings/stripclub.gd")
const Hotel = preload("res://scripts/buildings/hotel.gd")
const Burger = preload("res://scripts/buildings/burger.gd")
const Glass = preload("res://scripts/breakable_glass.gd")
const Garage = preload("res://scripts/buildings/garage.gd")
const Motel = preload("res://scripts/buildings/motel.gd")
const Highrise = preload("res://scripts/buildings/highrise.gd")
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


func _space() -> PhysicsDirectSpaceState3D:
	return world.get_world_3d().direct_space_state


## Floor height under a world point (ray from `above` metres over it), or NAN.
func _floor_at(at: Vector3, above: float = 1.3) -> float:
	var hit: Dictionary = _space().intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3(0, above, 0), at - Vector3(0, 1.0, 0)))
	return float((hit["position"] as Vector3).y) if not hit.is_empty() else NAN


## A standing body (radius 0.3, feet 0.3 above the floor so a single stair riser ahead doesn't count) fits here.
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
		print("  BLOCKED %s at %s by %s at %s" % [note, at, collider.get_path(), collider.global_position])
	return hits.is_empty()


## Samples a local polyline every 0.4 m: finds the floor under each sample, checks the floor is
## where the route expects it (+-0.35 m) and that a body fits.
func _route_ok(node: Node3D, route: Array, label: String) -> bool:
	var ok: bool = true
	for i: int in range(route.size() - 1):
		var a: Vector3 = route[i]
		var b: Vector3 = route[i + 1]
		var steps: int = maxi(1, int(ceil(a.distance_to(b) / 0.4)))
		for s: int in range(steps + 1):
			var local: Vector3 = a.lerp(b, float(s) / steps)
			var at: Vector3 = node.global_transform * local
			var floor_y: float = _floor_at(at)
			if is_nan(floor_y) or absf(floor_y - at.y) > 0.35:
				print("  FLOOR %s at local %s: expected %.2f got %s" % [label, local, at.y, floor_y])
				ok = false
				continue
			ok = _clear(Vector3(at.x, floor_y, at.z), label + " local %s" % local) and ok
	return ok


func _doors_for(prefix: String) -> Array:
	var found: Array = []
	for door: Dictionary in world.interactable_doors:
		if str(door["label"]).begins_with(prefix):
			found.append(door)
	return found


func _run() -> void:
	create_timer(120).timeout.connect(func() -> void: quit(2))
	world = World.new()
	root.add_child(world)
	await _frames(3)
	for spec: Array in [["nightclub", "Club Voltage", "CLUB VOLTAGE", 3, Nightclub.HALF], ["stripclub", "Velvet Room", "THE VELVET ROOM", 3, Stripclub.HALF],
			["hotel", "Hotel Meridian", "HOTEL MERIDIAN", 3, Hotel.HALF], ["garage", "", "CENTRAL PARKING", 0, Garage.HALF],
			["highrise", "Halcyon Trust", "HALCYON TRUST", 2, Highrise.HALF]]:
		var key: String = spec[0]
		var node: Node3D = world.plot_nodes[key]
		_check(node.has_meta("walk_in") and (node.has_node("Interior") or key == "garage"), key + " is a walk-in building")
		_check(node.get_meta("interior_half", Vector2.ZERO) == spec[4], key + " publishes its interior half-size")
		var named: bool = false
		for landmark: Dictionary in world.landmarks:
			named = named or landmark["name"] == spec[2]
		_check(named, key + " appears on the map as " + spec[2])
		var doors: Array = _doors_for(spec[1])
		var exits: int = 0
		for door: Dictionary in doors:
			var label: String = door["label"]
			if label.contains("entrance") or label.contains("alley") or label.contains("fire exit") or label.contains("service door"):
				exits += 1
				var outside: Vector3 = door["outside"]
				_check(world.is_on_land(outside), "%s opens onto land" % label)
				_check(_clear(Vector3(outside.x, 0.05, outside.z) + (outside - (door["position"] as Vector3)).normalized() * 0.4, label), "%s has a clear threshold outside" % label)
			if str(door.get("kind", "door")) == "lift":
				continue  # a landing's inside is the shaft; the car is only there when it is called
			var inside: Vector3 = door["inside"]
			var floor_y: float = _floor_at(inside)
			_check(not is_nan(floor_y) and _clear(Vector3(inside.x, floor_y, inside.z), label + " inside"), "%s has a clear landing inside" % label)
		if not str(spec[1]).is_empty():
			_check(exits >= spec[3], "%s has %d street/alley exits (>= %d)" % [key, exits, spec[3]])
		var routes: Dictionary = node.get_meta("routes", {})
		_check(routes.size() >= (1 if key == "garage" else 2), key + " publishes its walk routes")
		for route_name: String in routes:
			_check(_route_ok(node, routes[route_name], key + " " + route_name), "%s route %s is walkable end to end" % [key, route_name])
		# Lamp budget: at most two interior lamps (main room group + back of house), on the interior layer.
		var lamps: int = 0
		var layered: bool = true
		for light: Node in node.find_children("*", "OmniLight3D", true, false):
			lamps += 1
			layered = layered and (light as OmniLight3D).light_cull_mask == 1 << (world.INTERIOR_LAYER - 1)
		_check(lamps <= 2 and layered, "%s uses %d interior-layer lamps (<= 2)" % [key, lamps])
		# Merged: few mesh instances left after finish(), and the interior furniture sits on layer 2 with a range.
		var meshes: int = 0
		for child: Node in node.find_children("*", "MeshInstance3D", true, false):
			if not (child.get_parent() is StaticBody3D or child.get_parent().get_parent() is Node3D and child.get_parent().has_meta("closed_yaw")):
				meshes += 1
		print("  %s mesh instances after merge: %d" % [key, meshes])
		_check(meshes <= 90, "%s merges to %d mesh instances (<= 90)" % [key, meshes])
		var interior_ok: bool = true
		for child: Node in (node.get_node("Interior").get_children() if node.has_node("Interior") else []):
			if child is GeometryInstance3D:
				var geometry: GeometryInstance3D = child
				interior_ok = interior_ok and geometry.layers == 1 << (world.INTERIOR_LAYER - 1) and geometry.visibility_range_end > 0.0
		_check(interior_ok, key + " furnishings are on the interior layer with a draw range")
	# Nightclub mezzanine rail: low shot hits the kick board, a standing shot over the rail passes.
	var club: Node3D = world.plot_nodes["nightclub"]
	var low: Dictionary = _space().intersect_ray(PhysicsRayQueryParameters3D.create(club.global_transform * Vector3(6.0, Nightclub.MEZZ_Y + 0.2, -6.5), club.global_transform * Vector3(11.5, Nightclub.MEZZ_Y + 0.2, -6.5)))
	_check(not low.is_empty() and absf((club.global_transform.affine_inverse() * (low["position"] as Vector3)).x - 8.85) < 0.3, "Mezzanine kick board stops a low shot at the rail line")
	var high: Dictionary = _space().intersect_ray(PhysicsRayQueryParameters3D.create(club.global_transform * Vector3(6.0, Nightclub.MEZZ_Y + 1.62, -6.5), club.global_transform * Vector3(11.5, Nightclub.MEZZ_Y + 1.62, -6.5)))
	_check(high.is_empty(), "A standing shot over the mezzanine rail is not blocked by invisible collision")
	var bar_hit: Dictionary = _space().intersect_ray(PhysicsRayQueryParameters3D.create(club.global_transform * Vector3(-9.0, 0.7, 1.0), club.global_transform * Vector3(-14.0, 0.7, 1.0)))
	_check(not bar_hit.is_empty() and absf((club.global_transform.affine_inverse() * (bar_hit["position"] as Vector3)).x + 12.1) < 0.3, "Bar counter is waist-high cover where it is drawn")
	var over_bar: Dictionary = _space().intersect_ray(PhysicsRayQueryParameters3D.create(club.global_transform * Vector3(-9.0, 1.5, 1.0), club.global_transform * Vector3(-14.5, 1.5, 1.0)))
	_check(over_bar.is_empty(), "A shot over the bar counter reaches the back bar area")
	var dance_y: float = _floor_at(club.global_transform * Vector3(-1.5, 0.12, -1.0))
	_check(absf(dance_y - Nightclub.FLOOR_Y) < 0.02, "Dance floor panels are flush with the floor (no trip step)")
	# Strip club: the stage is solid at its drawn height and its steps climb onto it.
	var velvet: Node3D = world.plot_nodes["stripclub"]
	var stage_y: float = _floor_at(velvet.global_transform * Vector3(-2.0, 1.0, -3.8), 1.0)
	_check(absf(stage_y - (Stripclub.FLOOR_Y + Stripclub.STAGE_TOP)) < 0.05, "Stage top is solid at its drawn height (%.2f)" % stage_y)
	_check(_route_ok(velvet, [Vector3(4.6, 0.12, -2.9), Vector3(4.0, 0.12, -2.9), Vector3(2.3, 1.01, -2.9), Vector3(0.5, 1.01, -3.6)], "stage steps"), "Stage steps lead onto the stage")
	var runway_end: Dictionary = _space().intersect_ray(PhysicsRayQueryParameters3D.create(velvet.global_transform * Vector3(-2.0, 0.5, 6.0), velvet.global_transform * Vector3(-2.0, 0.5, 1.0)))
	_check(not runway_end.is_empty(), "Runway is solid cover at seated height")
	# Burger drive-through: a car-sized box fits the whole lane, the pickup window is real glass, the pole stands on the ground.
	var burger: Node3D = world.plot_nodes["burger"]
	var lane_clear: bool = true
	for step: int in range(12):
		var local: Vector3 = Vector3(Burger.LANE_X, 0, lerpf(9.0, -11.0, step / 11.0))
		var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		var car_box: BoxShape3D = BoxShape3D.new()
		car_box.size = Vector3(1.9, 1.3, 4.4)
		query.shape = car_box
		var at: Vector3 = burger.global_transform * local
		query.transform = Transform3D(burger.global_transform.basis, Vector3(at.x, world.surface_height(Vector2(at.x, at.z)) + 0.9, at.z))
		var hits: Array[Dictionary] = _space().intersect_shape(query, 2)
		if not hits.is_empty():
			print("  LANE BLOCKED at local %s by %s" % [local, (hits[0]["collider"] as Node).get_path()])
			lane_clear = false
	_check(lane_clear, "Burger drive-through lane fits a car from entry to exit")
	var window_hit: Dictionary = _space().intersect_ray(PhysicsRayQueryParameters3D.create(burger.global_transform * Vector3(Burger.LANE_X, 1.6, Burger.WINDOW_Z), burger.global_transform * Vector3(10.5, 1.6, Burger.WINDOW_Z)))
	_check(not window_hit.is_empty() and window_hit["collider"] is Glass, "Burger pickup window is breakable glass in the kitchen wall")
	var pole: Vector3 = burger.global_transform * Vector3(-13.6, 0, 11.8)
	var pole_hit: Dictionary = _space().intersect_ray(PhysicsRayQueryParameters3D.create(pole + Vector3(3, 1.0, 0) + (burger.global_transform.basis * Vector3(0, 0, 0)), pole + Vector3(-3, 1.0, 0)))
	_check(not pole_hit.is_empty(), "Burger pole sign has a solid pole where it is drawn")
	# High-rise: two lifts that each ride lobby -> office floor, two stairwells (routes above).
	var tower: Node3D = world.plot_nodes["highrise"]
	var tower_lifts: Array = tower.get_meta("lifts", [])
	_check(tower_lifts.size() == 2, "Halcyon Trust has two lifts")
	for lift_index: int in tower_lifts:
		var car: Node3D = world.lifts[lift_index]["car"]
		var start_y: float = car.global_position.y
		world.call_lift(lift_index, 1)
		for step: int in range(600):
			await physics_frame
			if absf(car.global_position.y - (start_y + Highrise.FLOORS[1] - Highrise.FLOORS[0])) < 0.05:
				break
		_check(absf(car.global_position.y - (start_y + Highrise.FLOORS[1] - Highrise.FLOORS[0])) < 0.05, "Lift %d rides from the lobby to the office floor (car y %.2f -> %.2f)" % [lift_index, start_y, car.global_position.y])
	# Motel upper storey: both exterior stairs reach the walkway and a room, four upper room doors.
	var upper: Node3D = null
	for child: Node in world.get_children():
		if child.name.begins_with("MotelUpper"):
			upper = child
	_check(upper != null and int(upper.get_meta("upper_rooms", 0)) == 4, "Motel has a furnished upper storey with four rooms")
	if upper != null:
		for route_name: String in upper.get_meta("routes"):
			_check(_route_ok(upper, upper.get_meta("routes")[route_name], "motel " + route_name), "Motel %s reaches the walkway and a room" % route_name)
	var upper_doors: int = 0
	for door: Dictionary in world.interactable_doors:
		if str(door["label"]).begins_with("Sea Breeze room 20"):
			upper_doors += 1
	_check(upper_doors == 4, "Motel rooms 201-204 have doors (%d)" % upper_doors)
	var walkway_rail: Dictionary = _space().intersect_ray(PhysicsRayQueryParameters3D.create(upper.global_transform * Vector3(0, Motel.DECK_Y + 0.2, 8.0), upper.global_transform * Vector3(0, Motel.DECK_Y + 0.2, 12.5)))
	_check(not walkway_rail.is_empty(), "Motel walkway edge has a solid kick board")
	# Gun store: Coast Road (edges included) stays clear of the range yard and its long-range plates.
	var yard_world: Rect2 = Rect2(290.0, -98.0, 90.0, 70.0)
	var road_clear: bool = true
	for road: Dictionary in world.roads:
		if str(road["name"]) != "COAST ROAD":
			continue
		var points: PackedVector2Array = road["points"]
		for index: int in range(points.size() - 1):
			for step: int in range(41):
				var at: Vector2 = points[index].lerp(points[index + 1], step / 40.0)
				road_clear = road_clear and not yard_world.grow(float(road["width"]) * 0.5).has_point(at)
	_check(road_clear, "Coast Road runs round the gun store range yard, not through it")
	# Garage: ramps within the 12 degree limit, and a sedan actually drives up each one.
	var garage: Node3D = world.plot_nodes["garage"]
	for ramp: Dictionary in garage.get_meta("ramps"):
		_check(float(ramp["degrees"]) <= 12.0, "Garage ramp is %.1f degrees (<= 12)" % float(ramp["degrees"]))
	for action: String in ["move_left", "move_right", "stick_left", "stick_right", "move_forward", "move_back", "pad_throttle", "pad_brake", "handbrake"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	for climb: Array in [[Vector3(-11.5, Garage.LEVELS[0] + 0.4, 10.5), 0.0, Garage.LEVELS[1], "west ramp to deck 2"],
			[Vector3(11.5, Garage.LEVELS[1] + 0.4, -10.5), PI, Garage.LEVELS[2], "east ramp to the roof"]]:
		var car: Node3D = Car.new()
		car.vehicle_type = "sedan"
		root.add_child(car)
		car.reset_car(garage.global_transform * (climb[0] as Vector3))
		car.rotation.y = garage.rotation.y + float(climb[1])
		car.enabled = true
		await _frames(10)
		car.occupied = true
		Input.action_press("move_forward")
		await _frames(300)
		Input.action_release("move_forward")
		var reached: float = car.global_position.y
		_check(reached > float(climb[2]) - 0.2, "A sedan drives up the garage %s (reached y %.2f, deck at %.2f)" % [climb[3], reached, float(climb[2])])
		car.occupied = false
		car.queue_free()
		await _frames(2)
	world.queue_free()
	await _frames(3)
	print("BUILDING LANDMARKS RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
