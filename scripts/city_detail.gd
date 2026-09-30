extends RefCounted
## Static, deterministic public-space dressing. Uses the existing world palette/batching.
## No NPCs, vendors, safe zones or transaction rules. Streets remain fully drivable.
## Coordinates are world x/z; one merged/cullable node per site, no extra lights.
const SITES: Array[Dictionary] = [
	{"name": "Trust Plaza", "rect": Rect2(156, -144, 38, 40), "style": "plaza"},
	{"name": "West End Gardens", "rect": Rect2(-206, -44, 50, 40), "style": "garden"},
	{"name": "Old Town Green", "rect": Rect2(-44, 156, 37, 22), "style": "garden"},
	{"name": "Nightlife Commons", "rect": Rect2(130, 104, 40, 44), "style": "plaza"},
	{"name": "Sunset Picnic Lawn", "rect": Rect2(236, 22, 31, 76), "style": "picnic"},
	{"name": "West Bank Promenade", "rect": Rect2(-182, 15, 59, 14), "style": "promenade"},
	{"name": "Nightlife Parking", "rect": Rect2(26, 218, 40, 30), "style": "parking"},
	{"name": "Wharf Workers Lot", "rect": Rect2(-312, -188, 60, 35), "style": "parking"},
]
const STONE: Color = Color(0.55, 0.52, 0.46)
const STEEL: Color = Color(0.12, 0.13, 0.14)
const CREAM: Color = Color(0.88, 0.82, 0.66)
const RED: Color = Color(0.72, 0.19, 0.14)
const GREEN: Color = Color(0.24, 0.42, 0.2)
var w: Node3D
var site: String

## Existing sidewalk scatter must also leave the entrances to these paths open.
static func is_path_entrance(at: Vector2) -> bool:
	for spec: Dictionary in SITES:
		if spec["style"] in ["parking", "promenade"]:
			continue
		var rect: Rect2 = spec["rect"]
		var center: Vector2 = rect.get_center()
		if absf(at.y - center.y) < 2.4 and minf(absf(at.x - rect.position.x), absf(at.x - rect.end.x)) < 3.0:
			return true
		if absf(at.x - center.x) < 2.4 and minf(absf(at.y - rect.position.y), absf(at.y - rect.end.y)) < 3.0:
			return true
	return false

func _init(world: Node3D) -> void:
	w = world

func build() -> void:
	for spec: Dictionary in SITES:
		site = spec["name"]
		var node: Node3D = w._begin("Public " + site)
		var rect: Rect2 = spec["rect"]
		w.public_spaces.append(spec.duplicate())
		var center: Vector2 = rect.get_center()
		match spec["style"]:
			"parking":
				_parking(rect)
			"promenade":
				_cart(Vector2(-178, 23))
				_newsstand(Vector2(-126, 21))
			_:
				# A crossing path gives walkers an obvious route rather than a field of props.
				_paving(Vector2(center.x, center.y), Vector2(rect.size.x - 4, 2.4))
				if spec["style"] != "picnic":
					_paving(center, Vector2(2.4, rect.size.y - 4))
				# Edges retain wide walk-through openings; raised beds stop straight car cuts.
				for x: float in [rect.position.x + 7, rect.end.x - 7]:
					for z: float in [rect.position.y + 5, rect.end.y - 5]:
						_bed(Vector2(x, z))
				for z: float in [center.y - 4.5, center.y + 4.5]:
					_bench(Vector2(rect.position.x + 4.5, z), PI * 0.5)
					_bench(Vector2(rect.end.x - 4.5, z), -PI * 0.5)
				if spec["style"] == "garden":
					_table(Vector2(center.x - 6, center.y + 4))
					_notice(Vector2(center.x + 6, center.y - 4))
				else:
					_cart(Vector2(center.x - 8, center.y + 6))
					_table(Vector2(center.x + 5, center.y + 7))
					if spec["style"] == "plaza":
						_newsstand(Vector2(center.x + 8, center.y - 7))
				_bin(Vector2(center.x - 5, center.y + 7))
		w._finish(node)
		# Only nearby players need the small props; existing district surfaces remain visible.
		for child: Node in node.get_children():
			if child is GeometryInstance3D:
				child.visibility_range_end = 85.0
				child.visibility_range_end_margin = 8.0

## Reject solid furniture near roads, building footprints, doors, spawns or existing props.
## Clearance uses a conservative bounding circle, including road shoulders and turning space.
func can_place(at: Vector2, radius: float) -> bool:
	for offset: Vector2 in [Vector2.ZERO, Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius)]:
		if not w._on_land(at + offset):
			return false
	if not w._free_spot(at, radius):
		return false
	for road: Dictionary in w.roads:
		var points: PackedVector2Array = road["points"]
		for i: int in range(points.size() - 1):
			if at.distance_to(Geometry2D.get_closest_point_to_segment(at, points[i], points[i + 1])) < float(road["width"]) * 0.5 + radius + 0.8:
				return false
	for door: Dictionary in w.interactable_doors:
		var position: Vector3 = door["position"]
		if at.distance_to(Vector2(position.x, position.z)) < radius + 4.0:
			return false
	for crew: Dictionary in w.crew_spawns.values():
		for key: String in ["spawn", "car", "hq"]:
			var position: Vector3 = crew[key]
			if at.distance_to(Vector2(position.x, position.z)) < radius + 6.0:
				return false
	for vehicle: Dictionary in w.parked_vehicles:
		var position: Vector3 = vehicle["at"]
		if at.distance_to(Vector2(position.x, position.z)) < radius + 4.0:
			return false
	return true

func _claim(at: Vector2, radius: float, kind: String) -> bool:
	if not can_place(at, radius):
		return false
	w._occupied.append(at)
	w.city_furniture.append({"site": site, "kind": kind, "at": at, "radius": radius, "solids": []})
	return true

func _at(at: Vector2, height: float) -> Vector3:
	return Vector3(at.x, height, at.y)

func _solid(at: Vector3, size: Vector3, color: Color, yaw: float = 0.0) -> void:
	w._box_with(at, size, w._material(color), true, yaw)
	(w.city_furniture.back()["solids"] as Array).append({"at": at, "size": size, "yaw": yaw})

func _paving(at: Vector2, size: Vector2) -> void:
	w._box(_at(at, 0.215), Vector3(size.x, 0.02, size.y), STONE, false, "tiles")

func _bed(at: Vector2) -> void:
	if not _claim(at, 2.0, "raised planter"):
		return
	_solid(_at(at, 0.65), Vector3(3.2, 1.0, 1.5), STONE)
	w._box(_at(at, 1.17), Vector3(2.8, 0.08, 1.15), Color(0.22, 0.18, 0.12))
	for x: float in [-0.85, 0.0, 0.85]:
		w._cylinder(_at(at + Vector2(x, 0), 1.45), 0.5, 0.55, GREEN, 6)

func _bench(at: Vector2, yaw: float) -> void:
	if not _claim(at, 1.4, "bench"):
		return
	w._bench(_at(at, 0.16), yaw)
	(w.city_furniture.back()["solids"] as Array).append({"at": _at(at, 0.61), "size": Vector3(1.8, 0.9, 0.5), "yaw": yaw})

func _table(at: Vector2) -> void:
	if not _claim(at, 2.0, "picnic table"):
		return
	_solid(_at(at, 0.99), Vector3(2.6, 0.14, 1.0), Color(0.45, 0.28, 0.16))
	for side: float in [-1.0, 1.0]:
		_solid(_at(at + Vector2(0, side * 1.0), 0.59), Vector3(2.6, 0.12, 0.4), Color(0.45, 0.28, 0.16))
		_solid(_at(at + Vector2(side * 0.9, 0), 0.55), Vector3(0.12, 0.8, 1.6), STEEL)

func _bin(at: Vector2) -> void:
	if not _claim(at, 0.7, "litter bin"):
		return
	_solid(_at(at, 0.66), Vector3(0.65, 1.0, 0.65), GREEN)
	w._box(_at(at, 1.19), Vector3(0.72, 0.08, 0.72), STEEL)

func _cart(at: Vector2) -> void:
	if not _claim(at, 1.8, "hot dog cart"):
		return
	_solid(_at(at, 0.85), Vector3(1.9, 1.0, 0.95), CREAM)
	w._box(_at(at, 1.39), Vector3(2.0, 0.08, 1.05), STONE)
	# Wheels, condiment bottles and a striped canopy, all from shared materials.
	for side: float in [-1.0, 1.0]:
		w._box(_at(at + Vector2(side * 0.72, 0.51), 0.38), Vector3(0.38, 0.38, 0.1), STEEL)
		_solid(_at(at + Vector2(side * 0.82, 0), 1.93), Vector3(0.07, 1.08, 0.07), STEEL)
	for i: int in range(5):
		w._box(_at(at + Vector2((i - 2) * 0.46, 0), 2.53), Vector3(0.46, 0.14, 1.5), RED if i % 2 == 0 else CREAM)
	for i: int in range(3):
		w._box(_at(at + Vector2(-0.45 + i * 0.25, -0.15), 1.53), Vector3(0.12, 0.22, 0.12), RED if i == 0 else Color(0.85, 0.65, 0.15))
	w._label("HALCYON DOGS", _at(at + Vector2(0, 0.485), 1.01), 26, RED, 0.0, 0.006)

func _newsstand(at: Vector2) -> void:
	if not _claim(at, 2.0, "newsstand"):
		return
	_solid(_at(at, 0.87), Vector3(2.5, 1.4, 1.1), GREEN)
	_solid(_at(at + Vector2(0, -0.44), 1.98), Vector3(2.5, 0.82, 0.22), GREEN)
	w._box(_at(at, 2.48), Vector3(2.9, 0.15, 1.5), CREAM)
	for i: int in range(4):
		w._box(_at(at + Vector2(-0.9 + i * 0.6, 0.12), 1.61), Vector3(0.43, 0.04, 0.52), CREAM)
	w._label("THE HALCYON POST", _at(at + Vector2(0, 0.57), 1.12), 24, CREAM, 0.0, 0.006)

func _notice(at: Vector2) -> void:
	if not _claim(at, 1.2, "community board"):
		return
	for side: float in [-1.0, 1.0]:
		_solid(_at(at + Vector2(side * 0.72, 0), 1.15), Vector3(0.1, 2.0, 0.1), STEEL)
	_solid(_at(at, 1.68), Vector3(1.6, 0.9, 0.16), STONE)
	for i: int in range(3):
		w._box(_at(at + Vector2((i - 1) * 0.46, 0.095), 1.7), Vector3(0.34, 0.52, 0.02), CREAM if i != 1 else RED)

func _parking(rect: Rect2) -> void:
	var center: Vector2 = rect.get_center()
	w._box(_at(center, 0.215), Vector3(rect.size.x - 2, 0.02, rect.size.y - 2), Color(0.18, 0.20, 0.21), false, "asphalt")
	# Two facing rows, a >7 m central manoeuvring aisle, entries at both ends.
	for x: float in range(int(rect.position.x + 5), int(rect.end.x - 4), 4):
		for z: float in [rect.position.y + 4, rect.end.y - 4]:
			w._box(_at(Vector2(x, z), 0.24), Vector3(0.09, 0.015, 5.5), CREAM)
			var stop: Vector2 = Vector2(x + 1.5, z + (-2.0 if z < center.y else 2.0))
			if _claim(stop, 1.2, "parking wheel stop"):
				_solid(_at(stop, 0.32), Vector3(2.1, 0.3, 0.28), STONE)
	_notice(Vector2(center.x, rect.position.y + 6))
	_bin(Vector2(center.x + 4, rect.position.y + 6))
