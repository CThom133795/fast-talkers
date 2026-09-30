extends SceneTree
## 0.5 map, interiors and railing checks against FastWorld on its own (no main.gd).
## Run: godot --headless --path . --script res://tests/map_interiors.gd
## Exit code 0 when every check passes.

const WorldScript = preload("res://scripts/world.gd")
const Interiors = preload("res://scripts/interiors.gd")
const EXCHANGE: Vector3 = Vector3(0, 0, -42)
const CREW_DISTRICTS: Dictionary = {"kojimoto": "LANTERN ROW", "solnegro": "SOLANA HEIGHTS", "kingsway": "KINGSWAY", "morris": "MORRIS PARK"}

var world: Variant
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _physics(count: int) -> void:
	for step: int in range(count):
		await physics_frame


func _ray(from: Vector3, to: Vector3, exclude: Array[RID] = []) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = exclude
	return world.get_world_3d().direct_space_state.intersect_ray(query)


func _capsule_hits(at: Vector3) -> int:
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.7
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.95, 0))
	return world.get_world_3d().direct_space_state.intersect_shape(query, 8).size()


## Fraction of a capsule sweep from `at` along `motion` that is free (1.0 = never blocked).
func _sweep(at: Vector3, motion: Vector3) -> float:
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.7
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.9, 0))
	query.motion = motion
	var result: PackedFloat32Array = world.get_world_3d().direct_space_state.cast_motion(query)
	return result[0]


func _target(at: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.5, 1.5, 0.4)
	shape.shape = box
	body.add_child(shape)
	body.position = at
	root.add_child(body)
	return body


func _run() -> void:
	world = WorldScript.new()
	root.add_child(world)
	await _physics(4)
	await _map_checks()
	await _interior_checks()
	await _railing_checks()
	print("MAP/INTERIORS RESULT: %d checks, %d failures" % [checks, failures])
	world.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)


# --- Map ------------------------------------------------------------------------------------

func _map_checks() -> void:
	var lengths: Array[float] = []
	for crew: String in CREW_DISTRICTS:
		var hq: Vector3 = world.crew_spawns[crew]["hq"]
		var metres: float = world.route_length(hq, EXCHANGE)
		lengths.append(metres)
		print("  route %s -> Exchange: %.1f m" % [crew, metres])
	var shortest: float = lengths.min()
	var longest: float = lengths.max()
	_check(longest < INF, "Every crew HQ can drive to the Union Exchange")
	_check(longest / shortest <= 1.08, "HQ-to-Exchange routes are within 8%% of each other (%.0f..%.0f m)" % [shortest, longest])
	# Spread round the compass, not parked in the four corners.
	var cardinal: int = 0
	var hqs: Array[Vector3] = []
	for crew: String in CREW_DISTRICTS:
		var hq: Vector3 = world.crew_spawns[crew]["hq"]
		hqs.append(hq)
		var bearing: float = fposmod(rad_to_deg(atan2(hq.z, hq.x)), 90.0)
		if bearing < 25.0 or bearing > 65.0:
			cardinal += 1
	_check(cardinal >= 2, "At least two crew HQs sit off the diagonals (%d do)" % cardinal)
	var closest_pair: float = INF
	for a: int in range(hqs.size()):
		for b: int in range(a + 1, hqs.size()):
			closest_pair = minf(closest_pair, Vector2(hqs[a].x, hqs[a].z).distance_to(Vector2(hqs[b].x, hqs[b].z)))
	_check(closest_pair > 110.0, "Crew HQs are spread across the city (closest pair %.0f m)" % closest_pair)
	# Continuous land: one mainland holds every HQ, Midtown and the Exchange; one canal left.
	var mainland: PackedVector2Array = world.land[0]
	var on_mainland: bool = Geometry2D.is_point_in_polygon(Vector2(EXCHANGE.x, EXCHANGE.z), mainland)
	for hq: Vector3 in hqs:
		on_mainland = on_mainland and Geometry2D.is_point_in_polygon(Vector2(hq.x, hq.z), mainland)
	_check(on_mainland, "Every HQ and the Exchange are on one continuous mainland")
	var road_bridges: int = 0
	for bridge: Dictionary in world.bridges:
		if not bool(bridge.get("foot", false)):
			road_bridges += 1
	_check(road_bridges <= 1, "At most one road bridge (the single remaining canal) (%d)" % road_bridges)
	_check(world.plazas.size() >= 4, "The city has open plazas and parks (%d)" % world.plazas.size())
	# Multiple ways into every crew district.
	for crew: String in CREW_DISTRICTS:
		var district: Dictionary = {}
		for candidate: Dictionary in world.districts:
			if str(candidate["name"]) == CREW_DISTRICTS[crew]:
				district = candidate
		var outline: PackedVector2Array = (district["polys"] as Array)[0]
		var entries: int = 0
		for a: int in range(world._graph_points.size()):
			for b: int in world._graph_links[a]:
				if b > a and Geometry2D.is_point_in_polygon(world._graph_points[a], outline) != Geometry2D.is_point_in_polygon(world._graph_points[b], outline):
					entries += 1
		_check(entries >= 3, "%s has 3+ road entries (%d)" % [CREW_DISTRICTS[crew], entries])
		_check(world.district_at(world.crew_spawns[crew]["hq"]) == CREW_DISTRICTS[crew], "%s's HQ is inside %s on the map" % [crew, CREW_DISTRICTS[crew]])
	_check(world.districts.size() >= 9 and world.district_at(Vector3.ZERO) == "MIDTOWN", "Districts are named and Midtown is at the centre")
	# Buildings stay off the streets.
	var overlaps: Array[String] = []
	for index: int in range(world.footprint_polys.size()):
		var outline: PackedVector2Array = world.footprint_polys[index]
		for road: Dictionary in world.roads:
			var points: PackedVector2Array = road["points"]
			for segment: int in range(points.size() - 1):
				for corner: int in range(outline.size()):
					var pair: PackedVector2Array = Geometry2D.get_closest_points_between_segments(outline[corner], outline[(corner + 1) % outline.size()], points[segment], points[segment + 1])
					var at_end: bool = (segment == 0 and pair[1].distance_to(points[0]) < 0.01) or (segment == points.size() - 2 and pair[1].distance_to(points[points.size() - 1]) < 0.01)
					if not at_end and pair[0].distance_to(pair[1]) < float(road["width"]) * 0.5 - 0.6:
						overlaps.append("%s @ %s" % [road["name"], str(outline[0])])
	_check(overlaps.is_empty(), "No building footprint sits on a road %s" % str(overlaps.slice(0, 3)))
	# Crew bases: the doorstep, main.gd's spawn rule and the crew cars are on clear land.
	for crew: String in CREW_DISTRICTS:
		var base: Dictionary = world.crew_spawns[crew]
		var hq: Vector3 = base["hq"]
		var outward: Vector3 = Vector3(-hq.x, 0, -hq.z).normalized()
		var main_spawn: Vector3 = Vector3(hq.x, 0.3, hq.z) + outward * 2.5
		_check(_capsule_hits(base["spawn"]) == 0 and world.is_on_land(base["spawn"]), "%s spawn outside the HQ door is clear" % crew)
		_check(_capsule_hits(main_spawn) == 0, "%s spawn by main.gd's rule (2.5 m towards the centre) is clear" % crew)
		var car: Vector3 = base["car"]
		var behind: Vector3 = car + Basis(Vector3.UP, float(base["yaw"])) * Vector3(0, 0, 6.2)
		_check(world.is_on_land(car) and world.is_on_land(behind) and _inside_building(car) == "" and _inside_building(behind) == "", "%s car and bike spawns are on open land" % crew)
	var parked_ok: bool = true
	for parked: Dictionary in world.parked_vehicles:
		if not world.is_on_land(parked["at"]) or (_inside_building(parked["at"]) != "" and str(parked["name"]) != "GARAGE COUPE"):
			parked_ok = false
			print("  parked vehicle off-road: ", parked)
	_check(parked_ok, "Parked vehicles stand on open land (the garage coupe is inside its garage)")


func _inside_building(at: Vector3) -> String:
	for outline: PackedVector2Array in world.footprint_polys:
		if Geometry2D.is_point_in_polygon(Vector2(at.x, at.z), outline):
			return str(outline[0])
	return ""


# --- Interiors ------------------------------------------------------------------------------

func _interior_checks() -> void:
	var doors: Array = world.interactable_doors
	_check(doors.size() >= 10, "Midtown has 10+ walk-in businesses (%d)" % doors.size())
	var signed: int = Interiors.SHOPS.size() + 1
	_check(float(doors.size()) / signed > 0.5, "A majority of signed Midtown storefronts are enterable (%d of %d)" % [doors.size(), signed])
	for door: Dictionary in doors:
		var outside: Vector3 = (door["outside"] as Vector3) + Vector3(0, 1.0, 0)
		var inside: Vector3 = (door["inside"] as Vector3) + Vector3(0, 1.0, 0)
		var label: String = str(door["label"]).strip_edges()
		_check(_ray(outside, inside).is_empty(), "%s: the open doorway is clear to walk and shoot through" % label)
		_check(_capsule_hits(door["inside"]) == 0, "%s: standing room just inside the door" % label)
		var down: Dictionary = _ray(inside, inside - Vector3(0, 3, 0))
		var up: Dictionary = _ray(inside, inside + Vector3(0, 6, 0))
		_check(not up.is_empty() and float(up["position"].y) < Interiors.GROUND + 0.3, "%s: a ceiling overhead" % label)
		_check(down.is_empty() or float(down["position"].y) < 0.2, "%s: a level floor" % label)
	# Shut one door of each kind and check it really closes.
	for index: int in [0, doors.size() - 2]:
		world.set_door_open(index, false)
	await _physics(90)
	for index: int in [0, doors.size() - 2]:
		var door: Dictionary = doors[index]
		var blocked: bool = not _ray((door["outside"] as Vector3) + Vector3(0, 1.0, 0), (door["inside"] as Vector3) + Vector3(0, 1.0, 0)).is_empty()
		_check(blocked and not bool(door["open"]), "%s: a shut door blocks the doorway" % str(door["label"]).strip_edges())
		world.set_door_open(index, true)
	await _physics(90)
	_check(_ray((doors[0]["outside"] as Vector3) + Vector3(0, 1, 0), (doors[0]["inside"] as Vector3) + Vector3(0, 1, 0)).is_empty(), "Doors open again")
	# Shop windows break when shot, and come back on reset.
	var pane: Dictionary = world.glass_panes[0]
	var body: StaticBody3D = pane["body"]
	_check(world.glass_panes.size() >= 30, "Shopfronts have breakable windows (%d panes)" % world.glass_panes.size())
	body.call("take_damage", 30.0)
	_check(body.collision_layer == 0 and not body.get("pane").visible, "A shot shatters a shop window (no collision, pane gone)")
	world.reset_glass()
	_check(body.collision_layer == 1 and body.get("pane").visible, "reset_glass() puts shop windows back")


# --- Railings and barriers ---------------------------------------------------------------------

func _railing_checks() -> void:
	# North harbour quay on the mole (Halcyon Avenue's end): rail at z = -200.
	var target: StaticBody3D = _target(Vector3(-10, 1.0, -214))
	await _physics(2)
	var over: Dictionary = _ray(Vector3(-10, 1.62, -196.5), Vector3(-10, 1.0, -214))
	_check(not over.is_empty() and over["collider"] == target, "A standing shot over the quay rail hits a target beyond it")
	var low: Dictionary = _ray(Vector3(-10, 0.2, -196.5), Vector3(-10, 0.2, -214))
	_check(not low.is_empty() and float(low["position"].z) > -200.6, "A ground-level shot still strikes the visible coping")
	var under: Dictionary = _ray(Vector3(-10, 0.72, -196.5), Vector3(-10, 0.72, -214))
	_check(not under.is_empty() and under["collider"] == target, "A crouched shot between coping and rail passes through the railing")
	_check(_sweep(Vector3(-10, 0, -197.5), Vector3(0, 0, -5)) < 0.99, "The rail stops a person walking off the quay")
	_check(_sweep(Vector3(-10, 0.5, -197.5), Vector3(0, 0, -5)) < 0.99, "It stops them at jump height too (0.5 m)")
	target.queue_free()
	# The beach revetment is waist-low: shots clear it, people do not.
	var beach: Vector3 = Vector3(110, 0, 250)
	var sea: StaticBody3D = _target(Vector3(110, 1.0, 266))
	await _physics(2)
	var over_rocks: Dictionary = _ray(beach + Vector3(0, 1.62, 0), Vector3(110, 1.0, 266))
	_check(not over_rocks.is_empty() and over_rocks["collider"] == sea, "Shots from the beach clear the rock revetment")
	_check(_sweep(beach, Vector3(0, 0, 12)) < 0.99, "The revetment keeps people out of the sea")
	sea.queue_free()
	# The Cage's chain-link: see-through and shoot-through above the windbreak screen.
	var xf: Transform3D = world.kit_transform("kingsway")
	var near_side: Vector3 = xf * Vector3(120.5, 0, 171)
	var far_side: Vector3 = xf * Vector3(120.5, 0, 162)
	var high: Dictionary = _ray(near_side + Vector3(0, 2.0, 0), far_side + Vector3(0, 2.0, 0))
	var screen: Dictionary = _ray(near_side + Vector3(0, 0.6, 0), far_side + Vector3(0, 0.6, 0))
	_check(high.is_empty() or (high["position"] as Vector3).distance_to(near_side + Vector3(0, 2, 0)) > 8.0, "Shots pass through chain-link above the windbreak")
	_check(not screen.is_empty(), "The chain-link's windbreak screen is solid")
	# No tall, thin, invisible walls left along the waterfront.
	var suspects: int = 0
	for body: Node in _static_bodies(world):
		for child: Node in body.get_children():
			if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
				var size: Vector3 = ((child as CollisionShape3D).shape as BoxShape3D).size
				var at: Vector3 = (body as Node3D).global_position
				if size.y >= 2.0 and minf(size.x, size.z) <= 0.7 and maxf(size.x, size.z) >= 2.0 and _near_coast(Vector2(at.x, at.z), 1.5):
					suspects += 1
	_check(suspects == 0, "No tall barrier colliders stand along the quays (%d)" % suspects)


func _static_bodies(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in node.get_children():
		if child is StaticBody3D:
			found.append(child)
		found.append_array(_static_bodies(child))
	return found


func _near_coast(at: Vector2, margin: float) -> bool:
	for poly: PackedVector2Array in world.land:
		for index: int in range(poly.size()):
			if Geometry2D.get_closest_point_to_segment(at, poly[index], poly[(index + 1) % poly.size()]).distance_to(at) < margin:
				return true
	return false
