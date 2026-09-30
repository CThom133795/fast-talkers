extends SceneTree
## Crew HQ suite: the four crew compounds (scripts/buildings/crew_hq.gd). For every crew: the spawn, the
## delivery point and the phone are inside a registered walk-in building; every one of the eight spawn-line
## slots online.gd hands out (0, +-1.4 ... +-5.6 m sideways) stands on clear interior floor within the buy
## radius; the crew phone sits on a desk surface a player can reach, walking from the spawn with the real
## player; the walk from the spawn out through the front door reaches the crew's car on the street; there
## are at least two exterior doors, every one of them reachable (a flood fill over clear floor with the real
## player's capsule, and a real-player walk along the published route through each door to open ground
## outside); the spawn has headroom; nothing of an HQ stands in a road carriageway; the interior stays inside
## its light and mesh budget; and two builds of the city agree on every HQ (spawn, phone, doors, collision).
## Run: godot --headless --path . --script res://tests/crew_hq.gd
const StairWalk = preload("res://tests/stair_walk.gd")
const Factions = preload("res://scripts/factions.gd")
const WorldScript = preload("res://scripts/world.gd")

## Expected compound: node name prefix of the building, title of the registry record.
const TITLES: Dictionary = {
	"morris": "MORRIS SOCIAL CLUB", "kojimoto": "KOJIMOTO BUILDING", "solnegro": "SOL NEGRO HACIENDA", "kingsway": "KINGSWAY COURTS"}

var checks: int = 0
var failures: int = 0
var game: Variant
var world: Node3D
var walker: Node3D


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


## The floor under a point (y of the first hit looking down from `above` m over it), or NAN.
func _floor_at(at: Vector3, above: float = 1.0) -> float:
	var hit: Dictionary = _space().intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3(0, above, 0), at - Vector3(0, 1.0, 0)))
	return float((hit["position"] as Vector3).y) if not hit.is_empty() else NAN


## A standing player (radius 0.3, 1.8 m, feet at `at`, lifted 0.05 m so the floor itself does not count) fits.
func _clear(at: Vector3, note: String = "") -> bool:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.05 + 0.9, 0))
	query.collision_mask = 1
	var hits: Array[Dictionary] = _space().intersect_shape(query, 4)
	if not hits.is_empty() and note != "":
		var collider: Node3D = hits[0]["collider"]
		print("  BLOCKED %s at %s by %s at %s" % [note, at, collider.get_path(), collider.global_position])
	return hits.is_empty()


## The HQ's building node, found by its crew meta.
func _hq_node(crew: String) -> Node3D:
	for child: Node in world.get_children():
		if child is Node3D and str(child.get_meta("crew_hq", "")) == crew:
			return child as Node3D
	return null


## online.gd `_apply_my_crew`: the sideways offset of spawn slot `slot`.
static func _slot_offset(slot: int) -> float:
	return float((slot + 1) / 2) * 1.4 * (1.0 if slot % 2 == 1 else -1.0)


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


## Walks the real player along world waypoints (first = start) and reports whether it got there.
func _walk(points: Array[Vector3], timeout: float = 60.0) -> Dictionary:
	walker.reset_player(points[0] + Vector3(0, 0.08, 0))
	walker.rotation.y = StairWalk.yaw_toward(points[1].x - points[0].x, points[1].z - points[0].z)
	await _frames(8)
	var stats: Dictionary = {}
	var reached: bool = await StairWalk.walk_route(self, walker, points, timeout, stats)
	stats["reached"] = reached
	return stats


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Does any registered building record in world.buildings carry this title (kind crew_hq, enterable)?
func _registered(title: String) -> bool:
	for record: Dictionary in world.buildings:
		if str(record["name"]) == title and str(record["kind"]) == "crew_hq" and bool(record["enterable"]) and not (record["footprints"] as Array).is_empty():
			return true
	return false


func _check_crew(crew: String) -> void:
	var base: Dictionary = world.crew_spawns[crew]
	var node: Node3D = _hq_node(crew)
	_check(node != null, "%s: the HQ is a building node" % crew)
	if node == null:
		return
	var half: Vector2 = node.get_meta("interior_half")
	_check(node.has_meta("walk_in") and node.has_node("Interior") and half.x > 5.0 and half.y > 5.0, "%s: walk-in building with an Interior and a published interior_half %s" % [crew, str(half)])
	_check(_registered(TITLES[crew]), "%s: registered as an enterable building (%s)" % [crew, TITLES[crew]])
	var spawn: Vector3 = base["spawn"]
	var hq: Vector3 = base["hq"]
	var online_side: Vector3 = Basis(Vector3.UP, float(base["spawn_yaw"])) * Vector3.RIGHT
	var phone: Vector3 = spawn + online_side * 3.2 + Vector3(0, 0.3, 0)
	phone.y = maxf(phone.y, 0.3)
	_check(phone.distance_to(base["phone"]) < 0.02, "%s: the published phone spot is where online.gd _host_place_phones puts the phone (%s)" % [crew, str(phone)])
	_check(game._building_at(spawn) == node and game._building_at(hq) == node and game._building_at(phone + Vector3(0, -0.5, 0)) == node,
		"%s: spawn, delivery point and phone are inside the building (main.gd _building_at)" % crew)
	# Lamps: few, and on the interior layer.
	var lights: Array[Node] = node.find_children("*", "OmniLight3D", true, false)
	_check(lights.size() >= 2 and lights.size() <= 3, "%s: %d interior lamps (2-3)" % [crew, lights.size()])
	# Mesh budget: merged meshes per material, not thousands of loose boxes.
	var loose: int = 0
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		if not (child.get_parent() is StaticBody3D) and not child.get_parent().has_meta("closed_yaw"):
			loose += 1
	print("  %s: %d mesh instances under the building, %d lamps" % [crew, loose, lights.size()])
	_check(loose <= 90, "%s: %d mesh instances (<= 90) after merging" % [crew, loose])
	# The eight spawn-line slots.
	var side: Vector3 = Basis(Vector3.UP, float(base["spawn_yaw"])) * Vector3.RIGHT
	var slots_ok: bool = true
	for slot: int in range(9):
		var spot: Vector3 = spawn + side * _slot_offset(slot)
		var ground: float = _floor_at(spot, 0.6)
		var ok: bool = not is_nan(ground) and absf(ground - F) < 0.06 and game._building_at(spot) == node and _clear(Vector3(spot.x, ground, spot.z), "%s slot %d" % [crew, slot])
		ok = ok and _flat(spot, hq) <= game.BUY_STATION_RADIUS
		if not ok:
			print("  SLOT %d at %s: floor %s" % [slot, spot, str(ground)])
		slots_ok = slots_ok and ok
	_check(slots_ok, "%s: all nine spawn-line slots are clear interior floor within the buy radius of the delivery point" % crew)
	# Headroom: the ceiling is well above a standing player over the spawn point and over the delivery point.
	var headroom_ok: bool = true
	for at: Vector3 in [spawn, hq]:
		var up: Dictionary = _space().intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, F + 0.1, at.z), Vector3(at.x, F + 6.0, at.z)))
		var clearance: float = float((up["position"] as Vector3).y) - F if not up.is_empty() else 99.0
		headroom_ok = headroom_ok and clearance > 2.6 and _clear(Vector3(at.x, F, at.z), "%s headroom" % crew)
	_check(headroom_ok, "%s: the spawn point and the delivery point have a standing player's headroom" % crew)
	# Items that start beside the spawn (online.gd _host_place: +-1.6 m sideways) sit on clear floor too.
	var items_ok: bool = true
	for sign_value: float in [-1.6, 1.6]:
		var spot: Vector3 = spawn + side * sign_value
		items_ok = items_ok and _clear(Vector3(spot.x, F, spot.z), "%s item spot" % crew)
	_check(items_ok, "%s: the ledger and cash case doorstep spots are clear floor" % crew)
	# Facing: the crew looks out of the front door (spawn_yaw forward points along door).
	var forward: Vector3 = Basis(Vector3.UP, float(base["spawn_yaw"])) * Vector3.FORWARD
	_check(forward.dot(base["door"]) > 0.99, "%s: the spawn faces the front door" % crew)
	# The phone rests on a desk surface.
	var ray: Dictionary = _space().intersect_ray(PhysicsRayQueryParameters3D.create(phone + Vector3(0, 0.2, 0), phone - Vector3(0, 0.6, 0)))
	var rest: float = phone.y - float((ray["position"] as Vector3).y) if not ray.is_empty() else 99.0
	_check(not ray.is_empty() and rest > 0.03 and rest < 0.3 and (ray["collider"] is StaticBody3D), "%s: the crew phone rests on a desk surface (%.2f m above it)" % [crew, rest])
	# A standing player can reach it: a clear floor spot within pickup distance, and the real player walks there from the spawn.
	var reach: float = game.online.PHONE_REACH
	var stand: Vector3 = Vector3.INF
	for ring: float in [0.8, 1.0, 1.2, 1.5]:
		for step: int in range(16):
			var angle: float = float(step) / 16.0 * TAU
			var spot: Vector3 = Vector3(phone.x + cos(angle) * ring, F, phone.z + sin(angle) * ring)
			if stand == Vector3.INF and _clear(spot) and absf(_floor_at(spot, 0.6) - F) < 0.06 and spot.distance_to(phone) < reach - 0.3:
				stand = spot
	_check(stand != Vector3.INF, "%s: there is clear floor within pickup reach (%.1f m) of the phone" % [crew, reach])
	if stand != Vector3.INF:
		var points: Array[Vector3] = [spawn, stand]
		var stats: Dictionary = await _walk(points, 40.0)
		_check(bool(stats["reached"]), "%s: the player walks from the spawn to the phone (%d frames)" % [crew, int(stats["frames"])])
	# Doors: at least two exterior doors, each at least 1.2 m wide.
	var doors: Array[Dictionary] = []
	for entry: Dictionary in world.interactable_doors:
		var local: Vector3 = node.global_transform.affine_inverse() * (entry["position"] as Vector3)
		if absf(local.x) <= half.x + 0.3 and absf(local.z) <= half.y + 0.3 and local.y < 1.0 and (absf(absf(local.x) - half.x) < 0.5 or absf(absf(local.z) - half.y) < 0.5):
			doors.append(entry)
	var wide: int = 0
	for entry: Dictionary in doors:
		if float(entry["width"]) >= 1.2:
			wide += 1
	_check(doors.size() >= 2 and wide == doors.size(), "%s: %d exterior doors, all at least 1.2 m wide" % [crew, doors.size()])
	for entry: Dictionary in doors:
		world.set_door_open(int(entry["index"]), true, true)
	await _frames(30)
	# Flood fill over clear floor from the spawn (the player's capsule, doors open): every door's inside and
	# outside approach is reachable, so the fill passes out of the building through each of them.
	var reach_map: Dictionary = _flood(node, half, spawn)
	var flood_ok: bool = true
	for entry: Dictionary in doors:
		var inside_ok: bool = reach_map.has(_cell(node, entry["inside"]))
		var outside_ok: bool = reach_map.has(_cell(node, entry["outside"]))
		if not (inside_ok and outside_ok):
			print("  DOOR %s: inside reachable %s, outside reachable %s" % [entry["label"], str(inside_ok), str(outside_ok)])
		flood_ok = flood_ok and inside_ok and outside_ok
	_check(flood_ok, "%s: the floor is connected from the spawn to both sides of every door (%d cells)" % [crew, reach_map.size()])
	# Real-player walks along the published routes: out of the front door to the car, and through every other door.
	var routes: Dictionary = node.get_meta("routes")
	_check(routes.has("to_street") and (routes["to_street"] as Array).size() >= 3, "%s: a published route from the spawn to the street" % crew)
	_check(routes.size() >= doors.size(), "%s: %d published routes for %d doors" % [crew, routes.size(), doors.size()])
	var covered: Dictionary = {}
	for key: String in routes:
		var path: Array[Vector3] = []
		for point: Vector3 in routes[key]:
			path.append(node.global_transform * point)
		var stats: Dictionary = await _walk(path, 90.0)
		var end: Vector3 = walker.global_position
		var end_local: Vector3 = node.global_transform.affine_inverse() * end
		var outside: bool = absf(end_local.x) > half.x + 1.5 or absf(end_local.z) > half.y + 1.5
		var ground: float = _floor_at(end, 1.0)
		var good: bool = bool(stats["reached"]) and outside and not is_nan(ground) and ground < 0.6
		if key == "to_street":
			var car: Vector3 = base["car"]
			var near: float = _flat(end, car)
			good = good and near < 3.5
			_check(good, "%s: the player walks from the spawn out of the front door to the car (%.1f m away, %d frames, stuck %s)" % [crew, near, int(stats["frames"]), str(stats["stuck_at"])])
		else:
			_check(good, "%s: the player walks from the spawn through '%s' to open ground outside (%d frames, stuck %s)" % [crew, key, int(stats["frames"]), str(stats["stuck_at"])])
		for entry: Dictionary in doors:
			var at: Vector2 = Vector2((entry["position"] as Vector3).x, (entry["position"] as Vector3).z)
			for index: int in range(path.size() - 1):
				var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(at, Vector2(path[index].x, path[index].z), Vector2(path[index + 1].x, path[index + 1].z))
				if nearest.distance_to(at) < 0.8:
					covered[int(entry["index"])] = true
	_check(covered.size() == doors.size(), "%s: every exterior door lies on a walked route (%d of %d)" % [crew, covered.size(), doors.size()])
	# Nothing of the HQ stands in a road carriageway.
	var worst: float = 99.0
	var worst_road: String = ""
	for shape: Node in node.find_children("*", "CollisionShape3D", true, false):
		var box: BoxShape3D = (shape as CollisionShape3D).shape as BoxShape3D
		if box == null:
			continue
		var basis: Basis = (shape as CollisionShape3D).global_transform.basis
		for sx: float in [-0.5, 0.0, 0.5]:
			for sz: float in [-0.5, 0.0, 0.5]:
				var corner: Vector3 = (shape as CollisionShape3D).global_position + basis * Vector3(sx * box.size.x, 0, sz * box.size.z)
				for road: Dictionary in world.roads:
					var line: PackedVector2Array = road["points"]
					for index: int in range(line.size() - 1):
						var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(corner.x, corner.z), line[index], line[index + 1])
						var gap: float = nearest.distance_to(Vector2(corner.x, corner.z)) - float(road["width"]) * 0.5
						if gap < worst:
							worst = gap
							worst_road = str(road["name"])
	_check(worst >= 0.0, "%s: no collision box reaches a carriageway (closest %.1f m clear of %s)" % [crew, worst, worst_road])


## A cell key on a 0.4 m grid in the building's frame.
func _cell(node: Node3D, world_point: Vector3) -> Vector2i:
	var local: Vector3 = node.global_transform.affine_inverse() * world_point
	return Vector2i(int(floor(local.x / 0.4)), int(floor(local.z / 0.4)))


## Flood fill over cells the player's capsule fits in, from `start` (world), 4-connected, within the building's
## footprint grown by 6 m. Returns the set of reached cells.
func _flood(node: Node3D, half: Vector2, start: Vector3) -> Dictionary:
	var xf: Transform3D = node.global_transform
	var seen: Dictionary = {}
	var clear_cache: Dictionary = {}
	var limit: Vector2 = half + Vector2(6.0, 6.0)
	var first: Vector2i = _cell(node, start)
	var queue: Array[Vector2i] = [first]
	seen[first] = true
	var head: int = 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if seen.has(next):
				continue
			var local: Vector3 = Vector3((float(next.x) + 0.5) * 0.4, 0.0, (float(next.y) + 0.5) * 0.4)
			if absf(local.x) > limit.x or absf(local.z) > limit.y:
				continue
			if not clear_cache.has(next):
				var world_point: Vector3 = xf * local
				var ground: float = _floor_at(world_point, 0.6)
				clear_cache[next] = not is_nan(ground) and ground < 0.6 and _clear(Vector3(world_point.x, ground, world_point.z))
			if clear_cache[next]:
				seen[next] = true
				queue.append(next)
	return seen


## What an HQ is made of, as one string: collision boxes, the HQ's doors and the published data.
func _signature(w: Node3D, crew: String) -> String:
	var hq: Node3D = null
	for child: Node in w.get_children():
		if child is Node3D and str(child.get_meta("crew_hq", "")) == crew:
			hq = child as Node3D
	if hq == null:
		return "missing"
	var parts: PackedStringArray = PackedStringArray()
	for shape: Node in hq.find_children("*", "CollisionShape3D", true, false):
		var box: BoxShape3D = (shape as CollisionShape3D).shape as BoxShape3D
		parts.append("%s %s" % [str((shape as CollisionShape3D).global_position.snapped(Vector3(0.001, 0.001, 0.001))), str(box.size) if box != null else "?"])
	parts.append(str(hq.find_children("*", "MeshInstance3D", true, false).size()))
	parts.append(str(hq.find_children("*", "OmniLight3D", true, false).size()))
	parts.append(str(hq.get_meta("routes")))
	parts.append(str(w.crew_spawns[crew]))
	var half: Vector2 = hq.get_meta("interior_half")
	for entry: Dictionary in w.interactable_doors:
		var local: Vector3 = hq.global_transform.affine_inverse() * (entry["position"] as Vector3)
		if absf(local.x) <= half.x + 0.3 and absf(local.z) <= half.y + 0.3 and local.y < 1.0:
			parts.append("%s %d %s" % [entry["label"], int(entry["index"]), str(entry["position"])])
	return "\n".join(parts).sha256_text()


const F: float = 0.17


func _run() -> void:
	create_timer(165).timeout.connect(func() -> void:
		push_error("Crew HQ suite timed out")
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
	Engine.time_scale = 4.0
	walker = _make_walker()
	_check(world.crew_spawns.size() == 4, "four crew bases")
	for crew: String in Factions.ORDER:
		await _check_crew(crew)
	Input.action_release("move_forward")
	Engine.time_scale = 1.0
	# Determinism: a second build of the whole city gives the same HQs.
	var second_world: Node3D = WorldScript.new()
	root.add_child(second_world)
	await _frames(2)
	for crew: String in Factions.ORDER:
		_check(_signature(world, crew) == _signature(second_world, crew), "%s: a second build of the city gives the identical HQ (collision, doors, spawn, phone, routes)" % crew)
	_check(world.interactable_doors.size() == second_world.interactable_doors.size() and world.interactable_doors.size() < 2000, "door list: %d doors in both builds" % world.interactable_doors.size())
	second_world.queue_free()
	print("CREW HQ RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
