extends SceneTree
## Windowed render review and draw-call measurement for scripts/buildings/prefabs.gd (needs a GPU; not for headless
## runs). Builds a row of every kind on a flat test yard far from the city, then for each building takes a street
## view, an oblique aerial and one view along each published walk route from inside, printing the draw calls the
## building adds (against an empty-yard baseline) and the frame time. Output: res://work/captures/prefabs/*.png.
## Run: godot --path . --script res://tests/capture_prefabs.gd
## Pass `-- only=<kind>` to capture one kind, `-- dusk` for the dusk lighting, `-- large` for larger footprints.

const World = preload("res://scripts/world.gd")
const Prefabs = preload("res://scripts/buildings/prefabs.gd")
const ORIGIN: Vector2 = Vector2(6000, 6000)

var world: Node3D
var camera: Camera3D
var folder: String
var only: String = ""
var dusk: bool = false
var large: bool = false
var noshadow: bool = false


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("only="):
			only = arg.substr(5)
		if arg == "dusk":
			dusk = true
		if arg == "large":
			large = true
		if arg == "noshadow":
			noshadow = true
	call_deferred("_run")


func _frames(count: int) -> void:
	for step: int in range(count):
		await process_frame


func _draws() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))


## Average draw calls and milliseconds per frame over a few frames.
func _measure() -> Dictionary:
	await _frames(4)
	var calls: int = 0
	var start: int = Time.get_ticks_usec()
	for step: int in range(8):
		await process_frame
		calls = maxi(calls, _draws())
	var ms: float = float(Time.get_ticks_usec() - start) / 8000.0
	return {"calls": calls, "ms": ms}


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [folder, label])


func _look(from: Vector3, at: Vector3) -> void:
	camera.global_position = from
	camera.look_at(at, Vector3.UP)


func _run() -> void:
	folder = ProjectSettings.globalize_path("res://work/captures/prefabs")
	DirAccess.make_dir_recursive_absolute(folder)
	world = World.new()
	root.add_child(world)
	world.set_dusk(dusk)
	# A flat yard: a grey plinth like a city block, big enough for the row.
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: BoxMesh = BoxMesh.new()
	plane.size = Vector3(900, 0.16, 200)
	ground.mesh = plane
	ground.material_override = world._material(Color(0.42, 0.42, 0.4), 0.9, "tiles")
	ground.position = Vector3(ORIGIN.x + 300, 0.08, ORIGIN.y)
	root.add_child(ground)
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = plane.size
	shape.shape = box
	body.add_child(shape)
	body.position = ground.position
	root.add_child(body)
	camera = Camera3D.new()
	camera.far = 400.0
	camera.fov = 72.0
	root.add_child(camera)
	camera.current = true
	world.environment.fog_enabled = false
	if noshadow:
		world.sun.shadow_enabled = false
	await _frames(20)
	_look(Vector3(ORIGIN.x - 400, 30, ORIGIN.y), Vector3(ORIGIN.x - 500, 30, ORIGIN.y))
	var base: Dictionary = await _measure()
	print("BASELINE (empty yard): %d draw calls, %.2f ms" % [base["calls"], base["ms"]])
	var slot: int = 0
	var report: Array[String] = []
	for kind: String in Prefabs.kinds():
		if not only.is_empty() and kind != only:
			continue
		var least: Vector2 = Prefabs.min_size(kind)
		var size: Vector2 = least + (Vector2(8, 6) if large else Vector2(2, 2))
		var floors: int = Prefabs.max_floors(kind) if large else maxi(Prefabs.min_floors(kind), mini(2, Prefabs.max_floors(kind)))
		var center: Vector2 = ORIGIN + Vector2(slot * 70.0, 0)
		slot += 1
		var node: Node3D = Prefabs.build(world, kind, center, size, 0.0, floors, 7, {"district": "TEST"})
		await _frames(6)
		var front: Vector3 = Basis(Vector3.UP, 0.0) * Vector3.FORWARD
		var mid: Vector3 = Vector3(center.x, 0, center.y)
		var depth: float = Vector2(node.get_meta("size")).y
		var height: float = float(node.get_meta("roof_y"))
		# Street view: eye height, 14 m out, looking at the front.
		_look(mid + front * (depth * 0.5 + 14.0) + Vector3(0, 1.7, 0), mid + Vector3(0, minf(height * 0.4, 4.0), 0) + front * depth * 0.5)
		var street: Dictionary = await _measure()
		await _shot("%s_street" % kind)
		# Breakdown: shell only (interior hidden), then interior only.
		var interior: Node3D = node.get_node_or_null("Interior") as Node3D
		if interior != null:
			interior.visible = false
			var shell_only: Dictionary = await _measure()
			interior.visible = true
			var hidden: Array[Node3D] = []
			for child: Node in node.get_children():
				if child is Node3D and child != interior and (child as Node3D).visible:
					(child as Node3D).visible = false
					hidden.append(child as Node3D)
			var interior_only: Dictionary = await _measure()
			for child: Node3D in hidden:
				child.visible = true
			print("BREAKDOWN %s street: total %d, shell %d, interior+props %d" % [kind, street["calls"], shell_only["calls"], interior_only["calls"]])
		# Oblique aerial: from the front corner, high.
		_look(mid + front * (depth * 0.5 + 16.0) + Vector3(-Vector2(node.get_meta("size")).x * 0.7, height + 12.0, 0), mid + Vector3(0, height * 0.4, 0))
		await _measure()
		await _shot("%s_aerial" % kind)
		# Back of the building (the alley side).
		_look(mid - front * (depth * 0.5 + 10.0) + Vector3(Vector2(node.get_meta("size")).x * 0.3, 1.7, 0), mid + Vector3(0, 2.5, 0) - front * depth * 0.5)
		await _shot("%s_back" % kind)
		# Inside: from each of the first doors, looking in.
		var door_records: Array = node.get_meta("doors")
		for d: int in range(mini(4, door_records.size())):
			var entry: Dictionary = world.interactable_doors[int(door_records[d]["index"])]
			var here: Vector3 = entry["position"]
			var beyond: Vector3 = entry["inside"]
			var into: Vector3 = (beyond - here)
			into.y = 0.0
			into = into.normalized()
			var eye_at: Vector3 = here + into * 0.6 + Vector3(0, 1.62, 0)
			_look(eye_at, eye_at + into * 8.0 + Vector3(0, -0.3, 0))
			await _frames(3)
			await _shot("%s_door%d" % [kind, d])
		# Inside: one view along each published route, from its start.
		var routes: Dictionary = node.get_meta("routes")
		var inside_worst: Dictionary = {"calls": 0, "ms": 0.0}
		var names: Array = routes.keys()
		names.sort()
		for route_name: String in names:
			var route: Array = routes[route_name]
			var a: Vector3 = node.global_transform * (route[0] as Vector3)
			var b: Vector3 = node.global_transform * (route[route.size() - 1] as Vector3)
			var mid_pt: Vector3 = node.global_transform * (route[mini(2, route.size() - 1)] as Vector3)
			var eye: Vector3 = a + Vector3(0, 1.62, 0)
			var target: Vector3 = mid_pt + Vector3(0, 1.4, 0)
			if eye.distance_to(target) < 0.5:
				target = b + Vector3(0, 1.4, 0)
			_look(eye, target)
			var measured: Dictionary = await _measure()
			if int(measured["calls"]) > int(inside_worst["calls"]):
				inside_worst = measured
			await _shot("%s_in_%s" % [kind, route_name])
		var line: String = "%s (%s, %d floors): street %d draws (+%d over the yard), %.2f ms; inside worst %d draws (+%d), %.2f ms" % [kind, size, floors, street["calls"], int(street["calls"]) - int(base["calls"]), street["ms"], inside_worst["calls"], int(inside_worst["calls"]) - int(base["calls"]), inside_worst["ms"]]
		print("MEASURE ", line)
		report.append(line)
	print("--- prefab draw call summary (baseline %d) ---" % base["calls"])
	for line: String in report:
		print(line)
	world.queue_free()
	for settle: int in range(6):
		await process_frame
	quit(0)
