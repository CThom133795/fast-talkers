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

## Inspect the rendered paint triangles, not the intentionally solid damage/vehicle hull.
## A closed body extrusion used to hide every occupant below the shoulder line.
func _paint_between(car: Node3D, from: Vector3, to: Vector3) -> bool:
	var body: Node3D = car.get("_body")
	var material: Material = car._paint(car.paint_color)
	for child: Node in body.get_children():
		if not child is MeshInstance3D:
			continue
		var instance: MeshInstance3D = child
		for surface: int in range(instance.mesh.get_surface_count()):
			if instance.mesh.surface_get_material(surface) != material and instance.material_override != material:
				continue
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var frame: Transform3D = body.transform * instance.transform
			for i: int in range(0, indices.size(), 3):
				if Geometry3D.segment_intersects_triangle(from, to, frame * vertices[indices[i]], frame * vertices[indices[i + 1]], frame * vertices[indices[i + 2]]) != null:
					return true
	return false


## Every body triangle (all materials, glass excluded) in body-node space. `materials`
## (optional) receives each triangle's material id, parallel to the result.
func _body_triangles(car: Node3D, materials: Array = []) -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	var body: Node3D = car.get("_body")
	for child: Node in body.get_children():
		if not child is MeshInstance3D or child.name == "Glass" or (child as MeshInstance3D).mesh == null:
			continue
		var instance: MeshInstance3D = child
		for surface: int in range(instance.mesh.get_surface_count()):
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			if indices == null:
				continue
			var idx: PackedInt32Array = indices
			var material: Material = instance.material_override if instance.material_override != null else instance.mesh.surface_get_material(surface)
			for i: int in range(0, idx.size(), 3):
				materials.append(material.get_instance_id() if material != null else 0)
				out.append(PackedVector3Array([instance.transform * vertices[idx[i]], instance.transform * vertices[idx[i + 1]], instance.transform * vertices[idx[i + 2]]]))
	return out


## First body triangle (any material but glass) crossed by a car-space segment, or null.
func _solid_between(car: Node3D, triangles: Array[PackedVector3Array], from: Vector3, to: Vector3) -> Variant:
	var body: Node3D = car.get("_body")
	var local_from: Vector3 = body.transform.affine_inverse() * from
	var local_to: Vector3 = body.transform.affine_inverse() * to
	for tri: PackedVector3Array in triangles:
		var hit: Variant = Geometry3D.segment_intersects_triangle(local_from, local_to, tri[0], tri[1], tri[2])
		if hit != null:
			return body.transform * (hit as Vector3)
	return null


## Coplanar, overlapping triangles (z-fighting): bucket by quantised plane, then test the
## 2D overlap area inside each bucket. Only pairs of different materials count: that is
## the visible flicker (same-material overlaps shade identically). Returns [area, where].
func _coplanar_overlap(triangles: Array[PackedVector3Array], materials: Array) -> Array:
	var buckets: Dictionary = {}
	for t: int in range(triangles.size()):
		var tri: PackedVector3Array = triangles[t]
		var normal: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0])
		if normal.length() < 0.000001:
			continue
		normal = normal.normalized()
		# Orientation-free key so front and back faces of a sheet do not count as a pair.
		var key: String = "%d|%d|%d|%d" % [roundi(normal.x * 200.0), roundi(normal.y * 200.0), roundi(normal.z * 200.0), roundi(normal.dot(tri[0]) * 500.0)]
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append([tri, normal, materials[t]])
	var worst: float = 0.0
	var where: Vector3 = Vector3.ZERO
	for key: String in buckets:
		var list: Array = buckets[key]
		if list.size() < 2 or list.size() > 400:
			continue
		for a: int in range(list.size()):
			var ta: PackedVector3Array = list[a][0]
			var n: Vector3 = list[a][1]
			var u: Vector3 = (ta[1] - ta[0]).normalized()
			var v: Vector3 = n.cross(u)
			var pa: PackedVector2Array = PackedVector2Array()
			for p: Vector3 in ta:
				pa.append(Vector2(u.dot(p), v.dot(p)))
			for b: int in range(a + 1, list.size()):
				if list[b][2] == list[a][2]:
					continue
				var tb: PackedVector3Array = list[b][0]
				var pb: PackedVector2Array = PackedVector2Array()
				for p: Vector3 in tb:
					pb.append(Vector2(u.dot(p), v.dot(p)))
				for poly: PackedVector2Array in Geometry2D.intersect_polygons(pa, pb):
					var area: float = 0.0
					for i: int in range(poly.size()):
						area += poly[i].cross(poly[(i + 1) % poly.size()])
					area = absf(area) * 0.5
					if area > worst:
						worst = area
						where = (ta[0] + ta[1] + ta[2]) / 3.0
	return [worst, where]


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
				var below: Vector3 = Vector3(eye.x, (car.BODY[type]["nose"][0] as Vector2).y + 0.14, eye.z)
				_check(not _paint_between(car, eye - Vector3(0, 0.2, 0), below), "%s seat %d: no solid coachwork sheet across the occupant's torso/legs" % [type, index])
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
		# --- Overnight presentation checks -------------------------------------------
		# Wheels touch the road at rest and tuck inside the body (flares allowed).
		var wheels_ok: bool = true
		var widest: float = 0.0
		for spinner: Node3D in car.get("_spinners"):
			var wheel_box: Array = [null]
			_bounds(car, spinner, wheel_box)
			var wb: AABB = wheel_box[0]
			wheels_ok = wheels_ok and absf(wb.position.y) < 0.03
			widest = maxf(widest, maxf(absf(wb.position.x), absf(wb.end.x)))
		_check(wheels_ok, "%s: every tyre touches the ground plane at rest (within 3 cm)" % type)
		if type != "motorcycle":
			var body_half: float = float(car.BODY[type]["width"]) * 0.5
			_check(widest <= body_half + 0.08, "%s: tyres sit inside their arches (outer face %.2f vs body %.2f)" % [type, widest, body_half])
			var tri_materials: Array = []
			var triangles: Array[PackedVector3Array] = _body_triangles(car, tri_materials)
			var floor_y: float = car._cabin_floor_y(car.BODY[type]) + 0.8
			for index: int in range(car.seat_count()):
				var seat: Dictionary = car.seat_info(index)
				if str(seat["shoot"]) == "open":
					continue
				var eye: Vector3 = seat["eye"]
				# Seats rest on the cabin floor: probes between floor and cushion hit the seat base.
				var centre: Vector3 = car._seat_centre(eye)
				var cushion_bottom: float = car._cushion_y(car.BODY[type], eye) + 0.8 - 0.07
				var supported: bool = true
				for height: float in [floor_y + 0.02, (floor_y + cushion_bottom) * 0.5]:
					if height < cushion_bottom - 0.005:
						supported = supported and _solid_between(car, triangles, Vector3(centre.x, height, centre.z - 0.3), Vector3(centre.x, height, centre.z + 0.3)) != null
				_check(supported and cushion_bottom - floor_y < 0.5, "%s seat %d: cushion rests on the cabin floor (gap %.2f m is filled by a seat base)" % [type, index, cushion_bottom - floor_y])
				# Forward sight line (front row; rear rows look past headrests): nothing solid
				# between the eye and a point ahead through the screen.
				if absf(eye.z - float((car.seat_info(0)["eye"] as Vector3).z)) > 0.1:
					continue
				var ahead: Vector3 = eye + Vector3(0, -0.12, -1.6)
				var blocker: Variant = _solid_between(car, triangles, eye, ahead)
				_check(blocker == null, "%s seat %d: clear forward view through the windscreen%s" % [type, index, "" if blocker == null else " (blocked at %s)" % str(blocker)])
			# Under the dash: the footwell is closed, the road does not show through the cabin.
			# Nothing solid hangs in a wheel arch in front of the tyre (door shut-lines used to).
			var arch_clear: bool = true
			var axles: Vector2 = car.spec["axles"]
			var arch_r: float = float(car.BODY[type]["arch"])
			var side_half: float = float(car.BODY[type]["width"]) * 0.5
			for axle: float in [axles.x, axles.y]:
				for probe_x: float in [side_half - 0.1, side_half - 0.05, side_half + 0.005]:
					for sign: float in [-1.0, 1.0]:
						var y: float = float(car.spec["wheel_r"]) + arch_r * 0.5
						arch_clear = arch_clear and _solid_between(car, triangles, Vector3(sign * probe_x, y, axle - arch_r * 0.8), Vector3(sign * probe_x, y, axle + arch_r * 0.8)) == null
			# Wheel-arch roofs stop at the wells: no paint tunnel across the footwells/seats.
			var tunnel: bool = false
			for axle: float in [axles.x, axles.y]:
				for probe_x: float in [-0.4, 0.0, 0.4]:
					for lift: float in [0.3, 0.6, 0.9]:
						var tunnel_y: float = float(car.spec["wheel_r"]) + arch_r * lift
						tunnel = tunnel or _paint_between(car, Vector3(probe_x, tunnel_y, axle - arch_r), Vector3(probe_x, tunnel_y, axle + arch_r))
			_check(not tunnel, "%s: no paint arch tunnel across the car between the wheel wells" % type)
			_check(arch_clear, "%s: wheel arches are clear in front of the tyres" % type)
			var screen_z: float = float((car.BODY[type]["glass"] as Array)[0].x)
			var footwell_from: Vector3 = Vector3(float((car.seat_info(0)["eye"] as Vector3).x), floor_y + 0.12, screen_z + 0.4)
			var toe: Variant = _solid_between(car, triangles, footwell_from, Vector3(footwell_from.x, footwell_from.y, screen_z - 0.3))
			_check(toe != null, "%s: footwell is closed under the dash (toe board at %s)" % [type, str(toe)])
			var overlap: Array = _coplanar_overlap(triangles, tri_materials)
			_check(float(overlap[0]) < 0.0004, "%s: no coplanar overlapping faces between different materials (worst %.5f m2 at %s)" % [type, float(overlap[0]), str(overlap[1])])
		else:
			var bike_materials: Array = []
			var bike_triangles: Array[PackedVector3Array] = _body_triangles(car, bike_materials)
			var overlap_bike: Array = _coplanar_overlap(bike_triangles, bike_materials)
			_check(float(overlap_bike[0]) < 0.0004, "%s: no coplanar overlapping faces between different materials (worst %.5f m2 at %s)" % [type, float(overlap_bike[0]), str(overlap_bike[1])])
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
