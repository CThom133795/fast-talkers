extends SceneTree
## 0.5 vehicle art checks: every type builds a complete body (no failed profiles), sits on
## its wheels, stays inside its collision hull, keeps its seat/door/window API, and the
## five silhouettes are distinct. Run: godot --headless --path . --script res://tests/vehicle_art.gd

const CarScript = preload("res://scripts/car.gd")
const TYPES: Array[String] = ["sedan", "coupe", "suv", "pickup", "motorcycle"]

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


## Bounding box of every visible mesh under `node`, in the car's space.
func _bounds(car: Node3D, node: Node, box: Array) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).visible:
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			var aabb: AABB = car.global_transform.affine_inverse() * mesh_instance.global_transform * mesh_instance.get_aabb()
			box[0] = aabb if box[0] == null else (box[0] as AABB).merge(aabb)
		_bounds(car, child, box)


func _run() -> void:
	var sizes: Dictionary = {}
	var x: float = 0.0
	for type: String in TYPES:
		var car: Variant = CarScript.new()
		car.vehicle_type = type
		car.position = Vector3(x, 0, 0)
		x += 8.0
		root.add_child(car)
		await process_frame
		var spec: Dictionary = car.spec
		var hull: Vector3 = spec["hull"]
		var box: Array = [null]
		_bounds(car, car, box)
		var aabb: AABB = box[0]
		sizes[type] = aabb.size
		print("  %s: model %s, hull %s" % [type, str(aabb.size), str(hull)])
		_check(aabb.size.x <= hull.x + 0.35 and aabb.size.z <= hull.z + 0.75, "%s: model stays within its collision hull footprint" % type)
		_check(aabb.position.y > -0.02 and aabb.position.y < 0.05, "%s: sits on its tyres (lowest point %.3f m)" % [type, aabb.position.y])
		if type != "motorcycle":
			# Allowance above the roof for a whip antenna or roof rails.
			_check(aabb.end.y <= float(spec["roof"]) + 0.2 and aabb.end.y >= float(spec["roof"]) - 0.2, "%s: roofline matches the hull roof (%.2f vs %.2f)" % [type, aabb.end.y, float(spec["roof"])])
		# The body mesh is complete: its lower panels have side faces (a failed profile
		# triangulation would leave the car see-through).
		var body: Node3D = car.get("_body")
		var body_triangles: int = 0
		for child: Node in body.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
				var mesh: Mesh = (child as MeshInstance3D).mesh
				for surface: int in range(mesh.get_surface_count()):
					var indices: Variant = mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
					if indices != null:
						body_triangles += (indices as PackedInt32Array).size() / 3
		_check(body_triangles > 600, "%s: complete body mesh (%d triangles)" % [type, body_triangles])
		var wheels: int = car.get("_spinners").size()
		_check(wheels == (2 if type == "motorcycle" else 4), "%s: %d wheels" % [type, wheels])
		var wheel_r: float = spec["wheel_r"]
		_check(wheel_r >= 0.3 and wheel_r <= 0.42, "%s: wheel radius %.2f is in the fleet's family" % [type, wheel_r])
		# Seat, door and window API unchanged: every window seat has a pane that rolls down.
		var panes_ok: bool = true
		for index: int in range(car.seat_count()):
			var seat: Dictionary = car.seat_info(index)
			var pane: int = int(seat["pane"])
			if pane >= 0:
				panes_ok = panes_ok and car.window_closed(pane)
				car.set_window_open(pane, true)
				panes_ok = panes_ok and not car.window_closed(pane)
				car.set_window_open(pane, false)
				panes_ok = panes_ok and car.window_closed(pane)
			var eye: Vector3 = seat["eye"]
			if type != "motorcycle" and str(seat["shoot"]) != "open":
				panes_ok = panes_ok and eye.y > float(spec["belt"]) and eye.y < aabb.end.y
		_check(panes_ok, "%s: every window seat's pane rolls down and eyes sit between belt and roof" % type)
		# Glass: every car window is breakable. A shot across the cabin at eye height breaks
		# the windows it passes through; a reset reglazes them.
		if type != "motorcycle":
			var total: int = car.glass_count()
			var eye_world: Vector3 = car.seat_eye(0)
			var across: Dictionary = car.glass_hit(eye_world + car.global_basis.x * -4.0, eye_world + car.global_basis.x * 4.0)
			var broke: bool = not across.is_empty() and car.break_glass(int(across["index"]), across["position"])
			_check(total >= 4 and broke and car.intact_glass() == total - 1 and not car.break_glass(int(across["index"])), "%s: %d breakable windows; a shot through the driver's window breaks it once" % [type, total])
			var through: Dictionary = car.glass_hit(eye_world + car.global_basis.z * 6.0 + Vector3(0, 0.1, 0), eye_world - car.global_basis.z * 6.0 + Vector3(0, 0.1, 0))
			_check(not through.is_empty(), "%s: a shot along the cabin meets the screen glass" % type)
			car.reset_car(car.global_position)
			_check(car.intact_glass() == total, "%s: reset reglazes every window" % type)
		_check(car.door_position(0).distance_to(car.global_transform * (car.seat_info(0)["door"] as Vector3)) < 0.01 and car.nearest_free_seat(car.door_position(0)) == 0, "%s: door and seat lookups unchanged" % type)
	# Distinct silhouettes: every pair differs by 12 cm+ in length, height or width.
	var distinct: bool = true
	for a: int in range(TYPES.size()):
		for b: int in range(a + 1, TYPES.size()):
			var sa: Vector3 = sizes[TYPES[a]]
			var sb: Vector3 = sizes[TYPES[b]]
			if (sa - sb).abs().max_axis_index() >= 0 and maxf(absf(sa.x - sb.x), maxf(absf(sa.y - sb.y), absf(sa.z - sb.z))) < 0.12:
				distinct = false
				print("  too alike: ", TYPES[a], " ", TYPES[b])
	_check(distinct, "The five types have distinct silhouettes")
	print("VEHICLE ART RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
