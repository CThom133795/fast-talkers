extends SceneTree
## Anti-slop city audit: props resting on the ground, level road centrelines, walkable doorways,
## no over-repeated shop signs, furnished public spaces, and static clutter that keeps roads,
## doors, crew spawns and parked cars clear. Headless: godot --headless --path . --script res://tests/city_audit.gd
const World = preload("res://scripts/world.gd")
var checks: int = 0
var failures: int = 0
var world: Node3D
var space: PhysicsDirectSpaceState3D

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

## Height of the walkable ground below `at`, skipping small props (boxes under 2.5 m a side).
func _ground(at: Vector2, from_y: float = 6.0) -> float:
	var exclude: Array[RID] = []
	for attempt: int in range(8):
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(at.x, from_y, at.y), Vector3(at.x, -4.0, at.y))
		query.exclude = exclude
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return -INF
		var owner: Object = hit["collider"]
		var small: bool = false
		if owner is CollisionObject3D:
			var body: CollisionObject3D = owner as CollisionObject3D
			var shape_owner: int = body.shape_find_owner(int(hit["shape"]))
			var shape: Shape3D = body.shape_owner_get_shape(shape_owner, 0)
			if shape is BoxShape3D:
				var size: Vector3 = (shape as BoxShape3D).size
				small = size.x < 2.5 and size.z < 2.5
		if not small:
			return (hit["position"] as Vector3).y
		exclude.append(hit["rid"])
	return -INF

func _top_hit(at: Vector2) -> String:
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, 3.0, at.y), Vector3(at.x, -4.0, at.y)))
	if hit.is_empty():
		return "nothing"
	var body: Node3D = hit["collider"] as Node3D
	var detail: String = ""
	for child: Node in body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			detail = " box %s" % ((child as CollisionShape3D).shape as BoxShape3D).size
	return "%s at %s%s" % [body.get_path(), body.global_position.snapped(Vector3(0.1, 0.1, 0.1)), detail]

func _count_bodies(node: Node) -> int:
	var total: int = 1 if node is CollisionObject3D else 0
	for child: Node in node.get_children():
		total += _count_bodies(child)
	return total

func _capsule_blocked(from: Vector3, to: Vector3, exclude: Array[RID]) -> String:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.5
	query.shape = capsule
	query.collision_mask = 1
	query.exclude = exclude
	var steps: int = maxi(2, int(from.distance_to(to) / 0.25))
	for step: int in range(steps + 1):
		var at: Vector3 = from.lerp(to, float(step) / steps)
		query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 1.15, 0))
		var hits: Array[Dictionary] = space.intersect_shape(query, 1)
		if not hits.is_empty():
			var collider: Node3D = hits[0]["collider"]
			return "%s at %s" % [collider.get_path(), at.snapped(Vector3(0.1, 0.1, 0.1))]
	return ""

func _run() -> void:
	create_timer(150).timeout.connect(func() -> void: quit(2))
	world = World.new()
	root.add_child(world)
	await _frames(4)
	space = world.get_world_3d().direct_space_state

	# 1. Authored furniture rests on the surface below it (no floating or buried props).
	var loose: Array[String] = []
	for item: Dictionary in world.city_furniture:
		var lowest: float = INF
		for solid: Dictionary in item["solids"]:
			lowest = minf(lowest, (solid["at"] as Vector3).y - (solid["size"] as Vector3).y * 0.5)
		if lowest == INF:
			continue
		# The surrounding surface, sampled just beyond the prop so its own top is not mistaken for ground.
		var ground: float = -INF
		for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			var sample: float = _ground((item["at"] as Vector2) + direction * (float(item["radius"]) + 0.4))
			if absf(sample - lowest) < absf(ground - lowest):
				ground = sample
		# A cart stands on its wheels, not its body box.
		var tolerance: float = 0.24 if item["kind"] == "hot dog cart" else 0.12
		if lowest - ground > tolerance or ground - lowest > 0.12:
			loose.append("%s %s at %s: base %.2f, ground %.2f" % [item["site"], item["kind"], item["at"], lowest, ground])
	for line: String in loose:
		print("  LOOSE " + line)
	_check(loose.is_empty(), "Every public-space prop sits on its ground (%d loose of %d)" % [loose.size(), world.city_furniture.size()])
	var bad_phones: Array[String] = []
	for phone: Vector3 in world.payphones:
		var ground: float = _ground(Vector2(phone.x, phone.z) + Vector2(0.6, 0.6))
		if absf(phone.y - ground) > 0.12 and absf(phone.y - _ground(Vector2(phone.x, phone.z) - Vector2(0.6, 0.6))) > 0.12:
			bad_phones.append("%s (ground %.2f)" % [phone, ground])
	for line: String in bad_phones:
		print("  LOOSE payphone " + line)
	var sunk: Array[String] = []
	for item: Dictionary in world.city_clutter:
		if item.has("y"):
			var ground: float = _ground(item["at"])
			if absf(float(item["y"]) - ground) > 0.12:
				sunk.append("%s at %s: base %.2f, ground %.2f" % [item["kind"], item["at"], item["y"], ground])
	for line: String in sunk:
		print("  LOOSE " + line)
	_check(sunk.is_empty(), "Alley dumpsters sit on their ground (%d off)" % sunk.size())
	_check(bad_phones.is_empty(), "Payphones stand on the pavement (%d of %d off)" % [bad_phones.size(), world.payphones.size()])

	# 1b. Solid props (boxes up to 3 m tall and 8 m long) do not start below a paved plinth's top.
	var sunk_props: Array[String] = []
	var bodies: Array[Node] = [world]
	while not bodies.is_empty():
		var node: Node = bodies.pop_back()
		bodies.append_array(node.get_children())
		if not node is StaticBody3D or node.get_child_count() != 1 or not node.get_child(0) is CollisionShape3D:
			continue
		var box: BoxShape3D = (node.get_child(0) as CollisionShape3D).shape as BoxShape3D
		if box == null or box.size.y > 3.0 or maxf(box.size.x, box.size.z) > 8.0 or box.size.y < 0.3 or minf(box.size.x, box.size.z) < 0.2:
			continue
		var center: Vector3 = (node as Node3D).global_position
		var bottom: float = center.y - box.size.y * 0.5
		var surface: float = world.surface_height(Vector2(center.x, center.z))
		if surface >= 0.15 and bottom > -0.05 and bottom < surface - 0.04:
			var plot: String = ""
			for key: String in world.plot_nodes:
				if is_instance_valid(world.plot_nodes[key]) and (world.plot_nodes[key] as Node).is_ancestor_of(node):
					plot = key
			if not plot.is_empty():
				# Trademark buildings live in scripts/buildings/* (lead-owned): reported, not failed.
				print("  REPORT sunk in plot %s: %s at %s bottom %.2f on plinth %.2f" % [plot, node.name, center.snapped(Vector3(0.1, 0.1, 0.1)), bottom, surface])
				continue
			sunk_props.append("%s at %s bottom %.2f on plinth %.2f" % [node.get_parent().name, center.snapped(Vector3(0.1, 0.1, 0.1)), bottom, surface])
	for line: String in sunk_props.slice(0, 40):
		print("  SUNK " + line)
	_check(sunk_props.is_empty(), "No solid prop is sunk into a paved plinth (%d)" % sunk_props.size())

	# 2. Road centrelines have no physical steps (kerbs, plinths or slabs intruding onto the carriageway).
	var steps: Array[String] = []
	for road: Dictionary in world.roads:
		var points: PackedVector2Array = road["points"]
		for i: int in range(points.size() - 1):
			var length: float = points[i].distance_to(points[i + 1])
			var samples: int = maxi(1, int(length / 2.0))
			for s: int in range(samples):
				# Nudged off exact grid vertices; dead ends into the quay coping are allowed.
				var at: Vector2 = points[i].lerp(points[i + 1], float(s) / samples) + Vector2(0.137, 0.071)
				if at.distance_to(points[0]) < 4.0 or at.distance_to(points[points.size() - 1]) < 4.0:
					continue
				if not world.is_on_land(Vector3(at.x, 0, at.y)):
					continue
				var on_bridge: bool = false
				for bridge: Dictionary in world.bridges:
					on_bridge = on_bridge or (bridge["rect"] as Rect2).grow(4.0).has_point(at)
				if on_bridge:
					continue
				var ground: float = _ground(at, 3.0)
				if ground > 0.12 or ground < -0.1:
					steps.append("%s at %s: %.2f (%s)" % [road.get("name", "road"), at.snapped(Vector2(0.1, 0.1)), ground, _top_hit(at)])
	# Known, reported, outside this audit's files or needing a road-layout change:
	# the Strip ring's south-west corner meets the beach rock revetment (x 24, z 400). (Coast Road
	# used to cross the gun store range yard; it now swings east round it, so that exception is gone.)
	var known: Array[Rect2] = [Rect2(18, 394, 14, 14)]
	var unexpected: Array[String] = []
	for line: String in steps:
		var hit_known: bool = false
		var numbers: PackedStringArray = line.get_slice("(", 1).get_slice(")", 0).split(",")
		var at: Vector2 = Vector2(float(numbers[0]), float(numbers[1]))
		for rect: Rect2 in known:
			hit_known = hit_known or rect.has_point(at)
		if hit_known:
			print("  KNOWN STEP " + line)
		else:
			unexpected.append(line)
	steps = unexpected
	for line: String in steps.slice(0, 30):
		print("  STEP " + line)
	_check(steps.is_empty(), "Road centrelines are level with the carriageway (%d raised/sunken samples)" % steps.size())

	# 3. Every ground-level doorway is walkable inside to outside with its leaf excluded.
	for index: int in range(world.interactable_doors.size()):
		var door: Dictionary = world.interactable_doors[index]
		if door["kind"] == "lift" or not door.has("inside") or not door.has("outside"):
			continue
		if world.is_door_locked(index):
			continue
		world.set_door_open(index, true, true)
	await _frames(40)
	for index: int in range(world.interactable_doors.size()):
		var door: Dictionary = world.interactable_doors[index]
		if door["kind"] == "lift" or not door.has("inside") or not door.has("outside") or world.is_door_locked(index):
			continue
		var exclude: Array[RID] = []
		for leaf: Node in world._door_nodes[index]:
			var stack: Array[Node] = [leaf]
			while not stack.is_empty():
				var node: Node = stack.pop_back()
				stack.append_array(node.get_children())
				if node is CollisionObject3D:
					exclude.append((node as CollisionObject3D).get_rid())
		var blocked: String = _capsule_blocked(door["inside"], door["outside"], exclude)
		if not blocked.is_empty():
			print("  DOOR %d %s blocked by %s" % [index, door["label"], blocked])
		_check(blocked.is_empty(), "Doorway %d (%s) walkable inside to outside" % [index, door["label"]])

	# 4. Shop signs and neon are not copy-pasted around the city.
	var texts: Dictionary = {}
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Label3D and (node as Label3D).font_size >= 40:
			var words: String = (node as Label3D).text.replace("\n", "")
			# Level markers and bay numbers ("R", "2", "G") are meant to repeat.
			if words.strip_edges().length() >= 4:
				texts[words] = int(texts.get(words, 0)) + 1
	var repeated: Array[String] = []
	for words: String in texts:
		if int(texts[words]) > 3:
			repeated.append("%s x%d" % [words, texts[words]])
	print("  Large signs: %d distinct texts; repeated > 3: %s" % [texts.size(), repeated])
	_check(repeated.is_empty(), "No large sign text repeats more than three times")

	# 5. Public spaces are furnished.
	for spec: Dictionary in world.public_spaces:
		var count: int = 0
		for item: Dictionary in world.city_furniture:
			count += 1 if item["site"] == spec["name"] else 0
		_check(count >= 4, "%s has furniture (%d pieces)" % [spec["name"], count])

	# 6. Static clutter (bins, bags, boxes, rooftop plant, oil stains) keeps roads, doors, spawns and cars clear.
	_check(world.city_clutter.size() >= 40, "City has lived-in clutter (%d pieces)" % world.city_clutter.size())
	var clutter_bad: Array[String] = []
	for item: Dictionary in world.city_clutter:
		var at: Vector2 = item["at"]
		if item.get("roof", false):
			continue
		var radius: float = item["radius"]
		for road: Dictionary in world.roads:
			var points: PackedVector2Array = road["points"]
			for i: int in range(points.size() - 1):
				if at.distance_to(Geometry2D.get_closest_point_to_segment(at, points[i], points[i + 1])) < float(road["width"]) * 0.5 + radius + 0.5:
					if item["kind"] != "oil stain":
						clutter_bad.append("%s at %s on road" % [item["kind"], at])
		for door: Dictionary in world.interactable_doors:
			var position: Vector3 = door["position"]
			if at.distance_to(Vector2(position.x, position.z)) < radius + 2.5:
				clutter_bad.append("%s at %s blocks door %s" % [item["kind"], at, door["label"]])
		for crew: Dictionary in world.crew_spawns.values():
			for key: String in ["spawn", "car", "hq"]:
				var position: Vector3 = crew[key]
				if at.distance_to(Vector2(position.x, position.z)) < radius + 4.0:
					clutter_bad.append("%s at %s crowds a crew %s" % [item["kind"], at, key])
		for vehicle: Dictionary in world.parked_vehicles:
			var position: Vector3 = vehicle["at"]
			if item["kind"] != "oil stain" and at.distance_to(Vector2(position.x, position.z)) < radius + 3.0:
				clutter_bad.append("%s at %s crowds a parked car" % [item["kind"], at])
	for line: String in clutter_bad:
		print("  CLUTTER " + line)
	_check(clutter_bad.is_empty(), "Clutter keeps roads, doors, crew spawns and parked cars clear (%d problems)" % clutter_bad.size())

	# 7. Coast railings: collision explains what is seen (docs/RAILING_COLLISION_NOTES.md).
	# A standing shot (1.62 m) over the 1.12 m rail passes; a low one (0.2 m) meets the coping.
	var edges: int = 0
	var high_blocked: Array[String] = []
	var low_open: int = 0
	var mainland: PackedVector2Array = world.land[0]
	for index: int in range(mainland.size()):
		var a: Vector2 = mainland[index]
		var b: Vector2 = mainland[(index + 1) % mainland.size()]
		if a.distance_to(b) < 6.0 or (a.y >= 389.0 and b.y >= 389.0):
			continue
		var mid: Vector2 = (a + b) * 0.5
		var in_gap: bool = false
		for gap: Rect2 in world.quay_gaps:
			in_gap = in_gap or gap.grow(1.0).has_point(mid)
		for bridge: Dictionary in world.bridges:
			in_gap = in_gap or (bridge["rect"] as Rect2).grow(2.0).has_point(mid)
		if in_gap:
			continue
		var normal: Vector2 = (b - a).normalized().orthogonal()
		edges += 1
		var high: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(mid.x - normal.x * 0.9, 1.62, mid.y - normal.y * 0.9), Vector3(mid.x + normal.x * 0.9, 1.62, mid.y + normal.y * 0.9)))
		if not high.is_empty():
			high_blocked.append("%s by %s" % [mid.snapped(Vector2(0.1, 0.1)), (high["collider"] as Node).get_path()])
		var low: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(mid.x - normal.x * 0.9, 0.2, mid.y - normal.y * 0.9), Vector3(mid.x + normal.x * 0.9, 0.2, mid.y + normal.y * 0.9)))
		low_open += 1 if low.is_empty() else 0
	for line: String in high_blocked:
		print("  RAIL eye-height shot blocked at " + line)
	_check(edges > 20 and high_blocked.size() <= edges / 20, "Eye-height shots clear the coast rail (%d of %d edges blocked)" % [high_blocked.size(), edges])
	_check(low_open <= edges / 10, "Low shots meet the visible coping (%d of %d edges open)" % [low_open, edges])

	# 8. Potato mode hides only collision-free dressing; every collider stays.
	var optional: Array[Node] = world.get_tree().get_nodes_in_group("potato_optional")
	var with_collision: int = 0
	for node: Node in optional:
		var nodes: Array[Node] = [node]
		while not nodes.is_empty():
			var item: Node = nodes.pop_back()
			nodes.append_array(item.get_children())
			with_collision += 1 if item is CollisionObject3D else 0
	_check(optional.size() >= 10, "Decor cells are marked potato_optional (%d)" % optional.size())
	_check(with_collision == 0, "No potato_optional node carries collision (%d bodies)" % with_collision)
	var bodies_before: int = _count_bodies(world)
	world.set_potato_mode(true)
	var hidden: bool = true
	for node: Node in optional:
		hidden = hidden and not (node as Node3D).visible
	_check(hidden and _count_bodies(world) == bodies_before, "Potato mode hides the decor and keeps all %d collision bodies" % bodies_before)
	world.set_potato_mode(false)
	var kinds: Dictionary = {}
	for item: Dictionary in world.city_clutter:
		kinds[item["kind"]] = int(kinds.get(item["kind"], 0)) + 1
	print("  Clutter by kind: %s" % kinds)
	_check(kinds.size() >= 12, "Clutter is varied (%d kinds)" % kinds.size())

	# 9. Draw-call hygiene: static district nodes draw their shadows through one proxy each.
	var proxies: int = 0
	for child: Node in world.get_children():
		if child.get_node_or_null("ShadowProxy") != null:
			proxies += 1
	_check(proxies >= 15, "Static districts use a single shadow-pass proxy (%d nodes)" % proxies)

	world.queue_free()
	await _frames(3)
	print("CITY AUDIT RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
