extends SceneTree
## Headless map dump for layout review: writes ../../work/captures/map_dump.json (land,
## roads, districts, plazas, buildings, doors, landmarks, crew bases and each crew's
## route to the Exchange) and prints the route lengths.
## Run: godot --headless --path . --script res://tests/dump_map.gd

const WorldScript = preload("res://scripts/world.gd")
const EXCHANGE: Vector3 = Vector3(0, 0, -42)


func _initialize() -> void:
	call_deferred("_run")


func _v2(at: Variant) -> Array:
	if at is Vector3:
		return [snappedf((at as Vector3).x, 0.01), snappedf((at as Vector3).z, 0.01)]
	return [snappedf((at as Vector2).x, 0.01), snappedf((at as Vector2).y, 0.01)]


func _poly(poly: PackedVector2Array) -> Array:
	var out: Array = []
	for point: Vector2 in poly:
		out.append(_v2(point))
	return out


func _run() -> void:
	var world: Node3D = WorldScript.new()
	root.add_child(world)
	await process_frame
	var data: Dictionary = {}
	var bounds: Rect2 = world.map_bounds()
	data["bounds"] = [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]
	data["land"] = world.land.map(func(p: PackedVector2Array) -> Array: return _poly(p))
	data["plazas"] = world.plazas.map(func(p: PackedVector2Array) -> Array: return _poly(p))
	data["footprints"] = world.footprint_polys.map(func(p: PackedVector2Array) -> Array: return _poly(p))
	var districts: Array = []
	for district: Dictionary in world.districts:
		var color: Color = district["color"]
		districts.append({"name": district["name"], "crew": district["crew"], "color": [color.r, color.g, color.b], "polys": (district["polys"] as Array).map(func(p: PackedVector2Array) -> Array: return _poly(p)), "label_at": _v2(district["label_at"])})
	data["districts"] = districts
	var roads: Array = []
	for road: Dictionary in world.roads:
		roads.append({"name": road["name"], "width": road["width"], "points": _poly(road["points"])})
	data["roads"] = roads
	var bridges: Array = []
	for bridge: Dictionary in world.bridges:
		var rect: Rect2 = bridge["rect"]
		bridges.append(_poly(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])))
	data["bridges"] = bridges
	data["landmarks"] = world.landmarks.map(func(l: Dictionary) -> Dictionary: return {"name": l["name"], "at": _v2(l["at"]), "neutral": l["neutral"]})
	data["doors"] = world.interactable_doors.map(func(d: Dictionary) -> Dictionary: return {"label": d["label"], "at": _v2(d["position"])})
	var spawns: Dictionary = {}
	var routes: Array = []
	for crew: String in world.crew_spawns:
		var spawn: Dictionary = world.crew_spawns[crew]
		spawns[crew] = {"hq": _v2(spawn["hq"]), "spawn": _v2(spawn["spawn"]), "car": _v2(spawn["car"])}
		var path: PackedVector3Array = world.route(spawn["hq"], EXCHANGE)
		var line: Array = [_v2(spawn["hq"])]
		for point: Vector3 in path:
			line.append(_v2(point))
		line.append(_v2(EXCHANGE))
		routes.append(line)
		print("ROUTE %s -> EXCHANGE: %.1f m (straight %.1f m)" % [crew, world.route_length(spawn["hq"], EXCHANGE), Vector2(spawn["hq"].x, spawn["hq"].z).distance_to(Vector2(EXCHANGE.x, EXCHANGE.z))])
	for index: int in range(world.footprint_polys.size()):
		var outline: PackedVector2Array = world.footprint_polys[index]
		for road: Dictionary in world.roads:
			var points: PackedVector2Array = road["points"]
			for segment: int in range(points.size() - 1):
				var hit: bool = false
				for corner: int in range(outline.size()):
					var edge_a: Vector2 = outline[corner]
					var edge_b: Vector2 = outline[(corner + 1) % outline.size()]
					var closest: PackedVector2Array = Geometry2D.get_closest_points_between_segments(edge_a, edge_b, points[segment], points[segment + 1])
					if closest[0].distance_to(closest[1]) < float(road["width"]) * 0.5 - 0.6:
						hit = true
				if Geometry2D.is_point_in_polygon(points[segment], outline):
					hit = true
				if hit:
					print("OVERLAP building %d at %s with road %s" % [index, str(outline[0]), road["name"]])
					break
	data["spawns"] = spawns
	data["routes"] = routes
	var folder: String = ProjectSettings.globalize_path("res://../../work/captures")
	DirAccess.make_dir_recursive_absolute(folder)
	var file: FileAccess = FileAccess.open(folder + "/map_dump.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	print("DUMPED ", folder + "/map_dump.json", " footprints=", world.footprint_polys.size(), " landmarks=", world.landmarks.size(), " doors=", world.interactable_doors.size())
	world.queue_free()
	await process_frame
	quit(0)
