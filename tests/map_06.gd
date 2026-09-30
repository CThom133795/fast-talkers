extends SceneTree
## 0.6 map checks (docs/MAP_0_6.md) against FastWorld and the Armory on their own (no main.gd):
## size, HQ routes and distances, roads and the outer ring, district connectivity, the eight
## trademark plots and their builders, the gun store in every game mode, and determinism.
## Run: godot --headless --path . --script res://tests/map_06.gd
## Exit code 0 when every check passes.

const WorldScript = preload("res://scripts/world.gd")
const ArmoryScript = preload("res://scripts/armory.gd")
const EXCHANGE: Vector3 = Vector3(0, 0, -42)
const CREWS: Array[String] = ["kojimoto", "solnegro", "kingsway", "morris"]
const NEW_DISTRICTS: Array[String] = ["UPTOWN", "MOTOR MILE", "NIGHTLIFE", "WEST END", "OLD TOWN", "SLIP SIDE", "OLD WHARF", "EAST SHORE", "SOUTH DOCKS"]

var world: Variant
var armory: Variant
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


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	return world.get_world_3d().direct_space_state.intersect_ray(query)


func _capsule_hits(at: Vector3) -> int:
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.7
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.95, 0))
	return world.get_world_3d().direct_space_state.intersect_shape(query, 8).size()


func _run() -> void:
	world = WorldScript.new()
	root.add_child(world)
	armory = ArmoryScript.new()
	root.add_child(armory)
	await _physics(4)
	_layout_checks()
	_road_checks()
	_district_checks()
	_plot_checks()
	await _gun_store_checks()
	_armory_checks()
	await _determinism_checks()
	print("MAP 0.6 RESULT: %d checks, %d failures" % [checks, failures])
	world.queue_free()
	armory.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)


# --- Size, HQs and routes ----------------------------------------------------------------------

func _layout_checks() -> void:
	var bounds: Rect2 = world.map_bounds()
	_check(bounds.size.x >= 780.0 and bounds.size.y >= 750.0, "The map is about 800 x 800 m (%.0f x %.0f)" % [bounds.size.x, bounds.size.y])
	var lengths: Array[float] = []
	var hqs: Array[Vector2] = []
	for crew: String in CREWS:
		var hq: Vector3 = world.crew_spawns[crew]["hq"]
		hqs.append(Vector2(hq.x, hq.z))
		var metres: float = world.route_length(hq, EXCHANGE)
		lengths.append(metres)
		print("  route %-9s -> Exchange %.1f m (straight %.1f m), HQ at (%.0f, %.0f)" % [crew, metres, Vector2(hq.x, hq.z).distance_to(Vector2(EXCHANGE.x, EXCHANGE.z)), hq.x, hq.z])
	_check(lengths.min() >= 330.0 and lengths.max() <= 380.0, "Every HQ route to the Exchange is 330-380 m (%.0f..%.0f)" % [lengths.min(), lengths.max()])
	_check(lengths.max() / lengths.min() <= 1.06, "The HQ routes are within 6%% of each other (%.1f%%)" % ((lengths.max() / lengths.min() - 1.0) * 100.0))
	var closest: float = INF
	for a: int in range(hqs.size()):
		for b: int in range(a + 1, hqs.size()):
			var metres: float = hqs[a].distance_to(hqs[b])
			closest = minf(closest, metres)
			print("  HQ %s <-> %s: %.0f m" % [CREWS[a], CREWS[b], metres])
	_check(closest >= 300.0, "Every pair of HQs is at least 300 m apart (closest %.0f m)" % closest)
	# Not in the four corners of the map: an HQ is a corner one if it sits in the outer quarter on both axes.
	var corners: int = 0
	for hq: Vector2 in hqs:
		var u: float = (hq.x - bounds.position.x) / bounds.size.x
		var v: float = (hq.y - bounds.position.y) / bounds.size.y
		if (u < 0.2 or u > 0.8) and (v < 0.2 or v > 0.8):
			corners += 1
	_check(corners == 0, "No crew HQ sits in a corner of the map (%d do)" % corners)
	# Each HQ is its own neighbourhood on the map.
	var names: Dictionary = {}
	for crew: String in CREWS:
		names[world.district_at(world.crew_spawns[crew]["hq"])] = true
	_check(names.size() == 4, "The four HQs are in four different districts")
	var on_land: bool = true
	for crew: String in CREWS:
		on_land = on_land and world.is_on_land(world.crew_spawns[crew]["spawn"]) and _capsule_hits(world.crew_spawns[crew]["spawn"]) == 0
	_check(on_land, "Every HQ doorstep spawn is clear ground")


# --- Roads -------------------------------------------------------------------------------------

func _road_checks() -> void:
	var off: Array[String] = []
	for road: Dictionary in world.roads:
		if str(road["name"]) == "NORTH SHORE ROAD":
			continue
		var points: PackedVector2Array = road["points"]
		for index: int in range(points.size()):
			if not world.is_on_land(Vector3(points[index].x, 0, points[index].y)):
				off.append(str(road["name"]))
			if index > 0:
				var mid: Vector2 = points[index - 1].lerp(points[index], 0.5)
				if not world.is_on_land(Vector3(mid.x, 0, mid.y)):
					off.append(str(road["name"]))
	_check(off.is_empty(), "Every street lies on land (bar the canal bridge) %s" % str(off.slice(0, 3)))
	var stray: int = 0
	for outline: PackedVector2Array in world.footprint_polys:
		for corner: Vector2 in outline:
			if not world.is_on_land(Vector3(corner.x, 0, corner.y)):
				stray += 1
	_check(stray == 0, "Every building outline lies on land (%d stray corners)" % stray)
	world.route(Vector3.ZERO, Vector3(10, 0, 10))
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
	_check(overlaps.is_empty(), "No building sits on a street, plots included %s" % str(overlaps.slice(0, 3)))
	# An outer ring road: a cycle of streets round Midtown at about r = 200 m. Cut the ring at the north and
	# at the south in turn: the other half must still connect east to west.
	_check(_ring_survives(-PI * 0.5) and _ring_survives(PI * 0.5), "An outer ring road circles Midtown at about r = 200 m")
	var loop_ok: bool = world.road_loop.size() == 64
	_check(loop_ok and Vector2(world.road_loop[0].x, world.road_loop[0].z).distance_to(Vector2(-85, -85)) < 1.0, "The practice wheelman's road_loop is still the downtown ring")


## True if, with every street node within +-35 degrees of `cut_angle` removed, an east node and a west node
## on the ring (radius 140-300 m from the origin) are still joined by streets inside that band.
func _ring_survives(cut_angle: float) -> bool:
	var points: PackedVector2Array = world._graph_points
	var allowed: Dictionary = {}
	for index: int in range(points.size()):
		var radius: float = points[index].length()
		if radius < 140.0 or radius > 300.0:
			continue
		var angle: float = atan2(points[index].y, points[index].x)
		if absf(wrapf(angle - cut_angle, -PI, PI)) < deg_to_rad(35.0):
			continue
		allowed[index] = true
	var start: int = _nearest_node(Vector2(227, -20), allowed)
	var goal: int = _nearest_node(Vector2(-200, 10), allowed)
	if start < 0 or goal < 0:
		return false
	var seen: Dictionary = {start: true}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		if current == goal:
			return true
		for neighbour: int in world._graph_links[current]:
			if allowed.has(neighbour) and not seen.has(neighbour):
				seen[neighbour] = true
				queue.append(neighbour)
	return false


func _nearest_node(at: Vector2, allowed: Dictionary) -> int:
	var best: int = -1
	var best_distance: float = INF
	for index: int in allowed:
		var distance: float = (world._graph_points[index] as Vector2).distance_to(at)
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


# --- Districts ------------------------------------------------------------------------------------

func _district_checks() -> void:
	var by_name: Dictionary = {}
	for district: Dictionary in world.districts:
		by_name[str(district["name"])] = district
	for title: String in NEW_DISTRICTS:
		_check(by_name.has(title), "The map has %s" % title)
		if not by_name.has(title):
			continue
		var polys: Array = by_name[title]["polys"]
		var outline: PackedVector2Array = polys[0]
		var entries: int = 0
		var inside_node: int = -1
		for a: int in range(world._graph_points.size()):
			var inside: bool = Geometry2D.is_point_in_polygon(world._graph_points[a], outline)
			if inside and inside_node < 0:
				inside_node = a
			for b: int in world._graph_links[a]:
				if b > a and inside != Geometry2D.is_point_in_polygon(world._graph_points[b], outline):
					entries += 1
		var reach: float = INF
		if inside_node >= 0:
			reach = world.route_length(Vector3(world._graph_points[inside_node].x, 0, world._graph_points[inside_node].y), EXCHANGE)
		_check(entries >= 2 and reach < INF, "%s has 2+ routes in and is reachable (%d entries)" % [title, entries])
	_check(world.landmarks.size() >= 55, "The 0.6 map has its landmarks (%d)" % world.landmarks.size())
	_check(world.plazas.size() >= 8, "The city has plazas and parks (%d)" % world.plazas.size())


# --- Plots ---------------------------------------------------------------------------------------------

func _plot_polygon(plot: Dictionary) -> PackedVector2Array:
	var center: Vector2 = plot["center"]
	var size: Vector2 = plot["size"]
	var front: Vector3 = plot["front"]
	var forward: Vector2 = Vector2(front.x, front.z)
	var along: Vector2 = Vector2(-forward.y, forward.x)
	var poly: PackedVector2Array = PackedVector2Array()
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		poly.append(center + along * corner.x * size.x * 0.5 + forward * corner.y * size.y * 0.5)
	return poly


func _plot_checks() -> void:
	_check(world.PLOTS.size() == 8 and world.PLOT_ORDER.size() == 8, "There are eight plots")
	for key: String in ["hotel", "garage", "motel", "nightclub", "stripclub", "burger", "highrise", "gunstore"]:
		_check(world.PLOTS.has(key), "Plot %s is reserved" % key)
	var plot_indices: Dictionary = {}
	for key: String in world.PLOT_ORDER:
		for index: int in world.plot_footprints.get(key, []):
			plot_indices[index] = key
	for key: String in world.PLOT_ORDER:
		var plot: Dictionary = world.PLOTS[key]
		var poly: PackedVector2Array = _plot_polygon(plot)
		var on_land: bool = true
		for corner: Vector2 in poly:
			on_land = on_land and world.is_on_land(Vector3(corner.x, 0, corner.y))
		_check(on_land, "%s: the plot is on land" % key)
		var center: Vector2 = plot["center"]
		var front: Vector3 = plot["front"]
		var depth: float = (plot["size"] as Vector2).y
		var frontage: Vector2 = center + Vector2(front.x, front.z) * depth * 0.5
		var nearest: float = INF
		var half: float = 0.0
		for road: Dictionary in world.roads:
			var points: PackedVector2Array = road["points"]
			for segment: int in range(points.size() - 1):
				var distance: float = Geometry2D.get_closest_point_to_segment(frontage, points[segment], points[segment + 1]).distance_to(frontage) - float(road["width"]) * 0.5
				if distance < nearest:
					nearest = distance
					half = float(road["width"]) * 0.5
		_check(nearest <= 12.0 and nearest >= 1.0, "%s: the plot faces a road (%.1f m of frontage to the kerb)" % [key, nearest])
		# Clear frontage: no building outline between the facade and the road, and no other footprint on the plot.
		var blocked: int = 0
		for index: int in range(world.footprint_polys.size()):
			if plot_indices.get(index, "") == key:
				continue
			var outline: PackedVector2Array = world.footprint_polys[index]
			if not Geometry2D.intersect_polygons(poly, outline).is_empty():
				blocked += 1
			for step: int in range(1, 6):
				var sample: Vector2 = frontage + Vector2(front.x, front.z) * (float(step) * 2.0)
				if Geometry2D.is_point_in_polygon(sample, outline):
					blocked += 1
		_check(blocked == 0, "%s: no other footprint overlaps the plot or blocks its frontage (%d)" % [key, blocked])
		_check(world.plot_nodes.has(key) and (world.plot_nodes[key] as Node3D).get_child_count() > 0, "%s: its builder made a building" % key)
		var own: Array = world.plot_footprints.get(key, [])
		var within: bool = not own.is_empty()
		for index: int in own:
			for corner: Vector2 in world.footprint_polys[index]:
				within = within and Geometry2D.is_point_in_polygon(corner, poly.duplicate()) or _near_polygon(corner, poly, 0.6)
		_check(within, "%s: its footprint stays inside the plot" % key)
	for a: int in range(world.PLOT_ORDER.size()):
		for b: int in range(a + 1, world.PLOT_ORDER.size()):
			var shared: Array[PackedVector2Array] = Geometry2D.intersect_polygons(_plot_polygon(world.PLOTS[world.PLOT_ORDER[a]]), _plot_polygon(world.PLOTS[world.PLOT_ORDER[b]]))
			_check(shared.is_empty(), "Plots %s and %s do not overlap" % [world.PLOT_ORDER[a], world.PLOT_ORDER[b]])


func _near_polygon(at: Vector2, poly: PackedVector2Array, margin: float) -> bool:
	for index: int in range(poly.size()):
		if Geometry2D.get_closest_point_to_segment(at, poly[index], poly[(index + 1) % poly.size()]).distance_to(at) <= margin:
			return true
	return false


# --- The gun store -------------------------------------------------------------------------------------

func _gun_store_checks() -> void:
	var doors: Array = world.gun_doors
	_check(doors.size() == 3, "The gun store has a range door, a yard door and a yard gate registered (%d)" % doors.size())
	var shop: Dictionary = {}
	for door: Dictionary in world.interactable_doors:
		if str(door["label"]) == "HALCYON ARMS":
			shop = door
	_check(not shop.is_empty(), "HALCYON ARMS has an ordinary walk-in shop door")
	var shop_index: int = int(shop["index"]) if not shop.is_empty() else -1
	# --- Free roam: everything open and armed.
	world.set_mode("free_roam")
	armory.set_mode("free_roam")
	await _physics(60)
	var every_open: bool = true
	for index: int in doors:
		every_open = every_open and bool(world.interactable_doors[index]["open"]) and not world.is_door_locked(index)
	_check(every_open, "Free roam: the range door, yard door and yard gate are open")
	for index: int in doors:
		var door: Dictionary = world.interactable_doors[index]
		var outside: Vector3 = (door["outside"] as Vector3) + Vector3(0, 1.0, 0)
		var inside: Vector3 = (door["inside"] as Vector3) + Vector3(0, 1.0, 0)
		_check(_ray(outside, inside).is_empty(), "Free roam: %s is clear to walk and shoot through" % str(door["label"]).strip_edges())
		_check(_capsule_hits(door["inside"]) == 0 and _capsule_hits(door["outside"]) == 0, "Free roam: standing room either side of %s" % str(door["label"]).strip_edges())
	var armed: int = 0
	var live: int = 0
	for target: StaticBody3D in armory.targets:
		if target.collision_layer != 0:
			armed += 1
		if bool(target.get("active")):
			live += 1
	_check(armory.dressing.visible and armed == armory.targets.size() and live == armory.targets.size() and armory.targets.size() >= 12, "Free roam: the range dressing is visible, solid and live (%d targets)" % armory.targets.size())
	var plate: StaticBody3D = armory.rack[0]
	var eye: Vector3 = ArmoryScript.SPAWN + Vector3(0, 1.6, 0)
	var aim: Vector3 = plate.global_position + Vector3(0, plate.get("plate_height"), 0)
	var shot: Dictionary = _ray(eye, aim + (aim - eye).normalized() * 0.3)
	_check(not shot.is_empty() and (shot["collider"] == plate or (shot["collider"] as Node).get_parent() == plate or plate.is_ancestor_of(shot["collider"])), "Free roam: a shot from the firing line reaches the first rack plate")
	# --- Contract and online: a believable closed range, no test-level dressing.
	for mode: String in ["contract", "online"]:
		world.set_mode(mode)
		armory.set_mode(mode)
		await _physics(90)
		var shut: bool = true
		var blocked: bool = true
		for index: int in doors:
			var door: Dictionary = world.interactable_doors[index]
			shut = shut and not bool(door["open"]) and world.is_door_locked(index)
			blocked = blocked and not _ray((door["outside"] as Vector3) + Vector3(0, 1.0, 0), (door["inside"] as Vector3) + Vector3(0, 1.0, 0)).is_empty()
		_check(shut and blocked, "%s: the range door, yard door and yard gate are locked shut and block the way" % mode.capitalize())
		world.toggle_door(doors[0])
		world.set_door_open(doors[1], true)
		_check(not bool(world.interactable_doors[doors[0]]["open"]) and not bool(world.interactable_doors[doors[1]]["open"]), "%s: E and network events cannot open a locked range door" % mode.capitalize())
		var hidden: int = 0
		var solid: int = 0
		for target: StaticBody3D in armory.targets:
			if target.collision_layer != 0:
				solid += 1
			if not bool(target.get("active")):
				hidden += 1
		_check(not armory.dressing.visible and solid == 0 and hidden == armory.targets.size(), "%s: targets are hidden, inactive and have no collision" % mode.capitalize())
		var rack_shot: Dictionary = _ray(eye, aim + (aim - eye).normalized() * 0.3)
		_check(rack_shot.is_empty() or not plate.is_ancestor_of(rack_shot["collider"]) and rack_shot["collider"] != plate, "%s: a shot through the yard finds no rack plate" % mode.capitalize())
		var bodies: int = 0
		for child: Node in _bodies(armory.dressing):
			if (child as CollisionObject3D).collision_layer != 0:
				bodies += 1
		_check(bodies == 0, "%s: no range dressing has collision (%d bodies)" % [mode.capitalize(), bodies])
		_check(not shop.is_empty() and not world.is_door_locked(shop_index) and bool(world.interactable_doors[shop_index]["open"]), "%s: the shop itself stays a normal open business" % mode.capitalize())
		world.set_door_open(shop_index, false)
		await _physics(60)
		_check(not _ray((shop["outside"] as Vector3) + Vector3(0, 1, 0), (shop["inside"] as Vector3) + Vector3(0, 1, 0)).is_empty(), "%s: the shop door closes like any door" % mode.capitalize())
		world.set_door_open(shop_index, true)
		await _physics(60)
		var pane_count: int = 0
		for glass: Dictionary in world.glass_panes:
			if str(glass["shop"]).begins_with("EAST SHORE"):
				pane_count += 1
		_check(pane_count >= 2, "%s: the shop has breakable windows (%d panes)" % [mode.capitalize(), pane_count])
	# --- Back to free roam.
	world.set_mode("free_roam")
	armory.set_mode("free_roam")
	await _physics(90)
	var restored: bool = armory.dressing.visible
	for target: StaticBody3D in armory.targets:
		restored = restored and target.collision_layer != 0 and bool(target.get("active"))
	for index: int in doors:
		restored = restored and bool(world.interactable_doors[index]["open"])
	_check(restored, "Switching back to free roam restores the dressing, the targets and the open doors")


func _bodies(root_node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in root_node.get_children():
		if child is CollisionObject3D:
			found.append(child)
		found.append_array(_bodies(child))
	return found


func _armory_checks() -> void:
	var plot: Dictionary = world.PLOTS["gunstore"]
	var center: Vector2 = plot["center"]
	var yard: Rect2 = Rect2(Vector2(center.x + 23.0, center.y - 26.0), Vector2(80.0, 60.0))
	_check(yard.grow(-2.0).has_point(Vector2(ArmoryScript.SPAWN.x, ArmoryScript.SPAWN.z)) and yard.grow(-2.0).has_point(Vector2(ArmoryScript.RACK.x, ArmoryScript.RACK.z)), "The firing line spawn and the rack are inside the yard behind the gun store")
	var inside: bool = true
	for target: StaticBody3D in armory.targets:
		inside = inside and yard.grow(-1.0).has_point(Vector2(target.global_position.x, target.global_position.z))
	_check(inside, "Every range target stands inside the yard")
	_check(is_equal_approx(ArmoryScript.LONG_LINE.x, ArmoryScript.LONG_LINE_X) and ArmoryScript.SPAWN.x > ArmoryScript.LONG_LINE_X, "The armory keeps SPAWN, RACK, LONG_LINE_X (and adds LONG_LINE)")
	_check(world.is_on_land(ArmoryScript.SPAWN) and world.is_on_land(Vector3(ArmoryScript.LONG_LINE_X + 70.0, 0, ArmoryScript.LONG_LINE.z)), "The whole range is on land")


# --- Determinism ---------------------------------------------------------------------------------------

func _checksum(node: Node3D) -> Dictionary:
	var sums: Dictionary = {}
	sums["footprints"] = str(node.footprint_polys).sha256_text()
	sums["parked"] = str(node.parked_vehicles).sha256_text()
	sums["roads"] = str(node.roads).sha256_text()
	sums["doors"] = str(node.interactable_doors.map(func(door: Dictionary) -> Array: return [door["label"], door["position"], door["kind"]])).sha256_text()
	sums["landmarks"] = str(node.landmarks).sha256_text()
	sums["payphones"] = str(node.payphones).sha256_text()
	sums["crew"] = str(node.crew_spawns).sha256_text()
	sums["glass"] = str(node.glass_panes.size())
	return sums


func _determinism_checks() -> void:
	var first: Dictionary = _checksum(world)
	var second_world: Node3D = WorldScript.new()
	root.add_child(second_world)
	await _physics(2)
	var second: Dictionary = _checksum(second_world)
	for key: String in first:
		_check(first[key] == second[key], "Two builds of the city agree on %s" % key)
	_check(world.footprint_polys.size() > 100 and world.parked_vehicles.size() >= 25, "The checksums cover the whole city (%d footprints, %d parked vehicles)" % [world.footprint_polys.size(), world.parked_vehicles.size()])
	second_world.queue_free()
	await process_frame
