extends SceneTree
## Crew HQ suite: the four crew compounds (scripts/buildings/crew_hq.gd). For every crew: the spawn, the
## delivery point and the phone are inside a registered walk-in building; every one of the eight spawn-line
## slots online.gd hands out (0, +-1.4 ... +-5.6 m sideways) stands on clear interior floor within the buy
## radius; the crew phone sits on a desk surface a player can reach, walking from the spawn with the real
## player; the walk from the spawn out through the front door reaches the crew's car on the street; there
## is a second exterior door; the interior stays inside its light and mesh budget.
## Run: godot --headless --path . --script res://tests/crew_hq.gd
const StairWalk = preload("res://tests/stair_walk.gd")
const Factions = preload("res://scripts/factions.gd")

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
	if not hits.is_empty():
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
	var phone: Vector3 = base["phone"]
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
	# The walk out: spawn through the front door to the crew's car.
	var route: Array = (node.get_meta("routes") as Dictionary).get("to_street", [])
	var path: Array[Vector3] = []
	for point: Vector3 in route:
		path.append(node.global_transform * point)
	_check(path.size() >= 3, "%s: a published route from the spawn to the street" % crew)
	if path.size() >= 3:
		for index: int in range(doors.size()):
			var door_index: int = int(doors[index]["index"])
			world.set_door_open(door_index, true, true)
		await _frames(30)
		var stats: Dictionary = await _walk(path, 90.0)
		var car: Vector3 = base["car"]
		var near: float = _flat(walker.global_position, car)
		_check(bool(stats["reached"]) and near < 3.5, "%s: the player walks from the spawn out of the front door to the car (%.1f m away, %d frames, stuck %s)" % [crew, near, int(stats["frames"]), str(stats["stuck_at"])])


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
	print("CREW HQ RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
