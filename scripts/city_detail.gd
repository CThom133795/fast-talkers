extends RefCounted
const MeshKit = preload("res://scripts/mesh_kit.gd")
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
## Sites on open ground (the picnic lawn) sit 0.16 m lower than those on a paved plinth.
var lift: float = 0.0

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
		lift = w.surface_height(center) - 0.16
		match spec["style"]:
			"parking":
				_parking(rect)
			"promenade":
				_cart(Vector2(-178, 23))
				_newsstand(Vector2(-126, 21))
				# Somewhere to sit and wait on the waterfront walk, not just two kiosks.
				for x: float in [-166.0, -152.0, -140.0]:
					_bench(Vector2(x, 23.5), 0.0)
				_bin(Vector2(-159, 23.5))
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
				w._detail_ranges.append(child)
	_clutter()

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
	return Vector3(at.x, height + lift, at.y)

func _solid(at: Vector3, size: Vector3, color: Color, yaw: float = 0.0) -> void:
	w._box_with(at, size, w._material(color), true, yaw)
	(w.city_furniture.back()["solids"] as Array).append({"at": at, "size": size, "yaw": yaw})

func _paving(at: Vector2, size: Vector2) -> void:
	# The cross path's second arm sits 4 mm higher so the two tops never share a plane.
	var raise: float = 0.004 if size.y > size.x else 0.0
	w._box(_at(at, 0.215 + raise), Vector3(size.x, 0.02, size.y), STONE, false, "tiles")

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

# --- Lived-in clutter: a late-1999 city paused mid-moment -----------------------------------
## Static and seeded. Runs after every other builder, so drawing from the world's seeded _rng
## here cannot shift any earlier placement; creation order is fixed (roof order, then yards,
## then public spaces, then parking). Pieces merge per 60 m cell, split in two: "Clutter" cells
## hold things with collision (dumpsters, pallet and tyre stacks, crates) and stay in every
## mode; "Decor" cells are collision-free dressing, in the "potato_optional" group that
## world.set_potato_mode() hides. Decor casts no shadow; neither takes neon light passes.
const CELL: float = 60.0
const CARDBOARD: Color = Color(0.58, 0.45, 0.3)
const PLANT: Color = Color(0.46, 0.48, 0.47)
const OIL: Color = Color(0.07, 0.07, 0.08)
const PAPER: Array[Color] = [Color(0.86, 0.82, 0.7), Color(0.78, 0.66, 0.52), Color(0.72, 0.8, 0.84), Color(0.9, 0.74, 0.62)]
const INK: Array[Color] = [Color(0.62, 0.16, 0.12), Color(0.14, 0.2, 0.36), Color(0.12, 0.12, 0.12)]
## Original, period-dated bill posters. No brands.
const POSTERS: Array[String] = ["Y2K\nREADY?", "GRAND\nOPENING\n1998", "FOR\nLEASE", "LOST CAT\nANSWERS TO\nBISCUIT", "MILLENNIUM\nEVE BASH\nDEC 31", "LIVE BAND\nFRIDAY", "ROOMS\nWEEKLY", "WE BUY\nGOLD", "CLOSING\nDOWN\nSALE", "PAGERS\n50% OFF", "CD SWAP\nSUNDAY", "VOTE NO\nON 14", "DRIVERS\nWANTED", "BOXING\nAUG 99", "PSYCHIC\nREADINGS", "APT FOR\nRENT"]
const BUNTING: Array[Color] = [Color(0.8, 0.2, 0.16), Color(0.95, 0.8, 0.3), Color(0.2, 0.45, 0.75), Color(0.25, 0.6, 0.35)]
var _cells: Dictionary = {}
var _cell_order: Array[Vector3i] = []
var _poster_index: int = 0

func _cell(at: Vector2, decor: bool = false) -> Node3D:
	var key: Vector3i = Vector3i(floori(at.x / CELL), floori(at.y / CELL), 1 if decor else 0)
	if not _cells.has(key):
		var saved: Node3D = w._target
		var node: Node3D = w._begin("%s %d %d" % ["Decor" if decor else "Clutter", key.x, key.y])
		w._target = saved
		if decor:
			node.add_to_group("potato_optional")
		_cells[key] = node
		_cell_order.append(key)
	return _cells[key] as Node3D

func _clutter_claim(at: Vector2, radius: float, kind: String, roof: bool = false) -> bool:
	if not roof:
		if not can_place(at, radius):
			return false
		w._occupied.append(at)
	w.city_clutter.append({"kind": kind, "at": at, "radius": radius, "roof": roof})
	w._target = _cell(at, roof)
	return true

## Collision-free dressing at `at`: recorded for the audit, built into the decor cell.
func _decor(at: Vector2, kind: String, radius: float = 0.5, on_wall: bool = false) -> void:
	w.city_clutter.append({"kind": kind, "at": at, "radius": radius, "roof": on_wall, "decor": true})
	w._target = _cell(at, true)

## A point on a tower's front (side 1) or back (side -1) wall: `along` the facade, at height
## `y`, `out` metres proud of it. Returns [position, yaw facing out of the wall].
func _on_wall(roof: Dictionary, side: float, along: float, y: float, out: float) -> Array:
	var front: Vector3 = (roof["front"] as Vector3).normalized() * side
	var size: Vector3 = roof["size"]
	var yaw: float = float(roof["yaw"])
	var local_z: Vector3 = Vector3(sin(yaw), 0, cos(yaw))
	var depth: float = size.z if absf(front.dot(local_z)) > 0.5 else size.x
	var center: Vector2 = roof["center"]
	var across: Vector3 = Vector3(front.z, 0, -front.x)
	var at: Vector3 = Vector3(center.x, y, center.y) + front * (depth * 0.5 + out) + across * along
	return [at, atan2(front.x, front.z)]

func _facade_span(roof: Dictionary) -> float:
	var front: Vector3 = (roof["front"] as Vector3).normalized()
	var size: Vector3 = roof["size"]
	var yaw: float = float(roof["yaw"])
	return size.x if absf(front.dot(Vector3(sin(yaw), 0, cos(yaw)))) > 0.5 else size.z

func _clutter() -> void:
	var rng: RandomNumberGenerator = w._rng
	# A handful of shared materials, so each cell merges into a few draws.
	var metal: StandardMaterial3D = w._material(PLANT, 0.6, "metal")
	var dark: StandardMaterial3D = w._material(OIL, 0.3)
	var card: StandardMaterial3D = w._material(CARDBOARD, 0.95)
	var shutter: StandardMaterial3D = w._material(Color(0.52, 0.53, 0.5), 0.7, "metal")
	var plank: StandardMaterial3D = w._material(Color(0.5, 0.4, 0.28), 0.9, "planks")
	var clock_face: StandardMaterial3D = w._material(Color(0.9, 0.88, 0.8), 0.6)
	var back_lamp: StandardMaterial3D = w._glow(Color(1.0, 0.82, 0.55), 1.8)
	var bin_color: Color = Color(0.2, 0.33, 0.26)
	for roof: Dictionary in w._roofs:
		var center: Vector2 = roof["center"]
		var size: Vector3 = roof["size"]
		var top: float = roof["top"]
		var basis: Basis = Basis(Vector3.UP, float(roof["yaw"]))
		var span: float = _facade_span(roof)
		var columns: int = maxi(1, int(span / 3.4))
		var business: bool = bool(roof["business"])
		# Rooftop plant: condenser boxes with a fan disc and a vent pipe, in the roof quadrant
		# away from any water tank or plant box the district builder already put up there.
		if size.x >= 9.0 and size.z >= 9.0 and _clutter_claim(center, 0.0, "rooftop plant", true):
			var away: Vector2 = Vector2(1, 1)
			if roof.has("taken"):
				var offset: Vector2 = (roof["taken"] as Vector2) - center
				var taken: Vector3 = basis.inverse() * Vector3(offset.x, 0, offset.y)
				away = Vector2(-signf(taken.x) if absf(taken.x) > 0.01 else 1.0, -signf(taken.z) if absf(taken.z) > 0.01 else 1.0)
			for unit: int in range(1 + rng.randi() % 2):
				var local: Vector3 = Vector3(away.x * (size.x * 0.5 - 1.6 - unit * 2.0), 0, away.y * (size.z * 0.5 - 1.4))
				var at: Vector3 = Vector3(center.x, top, center.y) + basis * local
				w._box_with(at + Vector3(0, 0.55, 0), Vector3(1.6, 1.1, 1.1), metal, false, float(roof["yaw"]))
				w._cylinder(at + Vector3(0, 1.13, 0), 0.4, 0.06, OIL, 10, dark)
			var pipe: Vector3 = Vector3(center.x, top, center.y) + basis * Vector3(away.x * (size.x * 0.5 - 1.6), 0, away.y * (size.z * 0.5 - 3.2))
			w._cylinder(pipe + Vector3(0, 0.7, 0), 0.2, 1.4, PLANT, 8, metal)
		var ground: float = w.surface_height(center + Vector2(0.01, 0.01))
		# Bill posters between the ground-floor windows, front and back, faded and part-peeled.
		for side: float in [1.0, -1.0]:
			if columns < 2 or rng.randf() < 0.45:
				continue
			var gap: int = 1 + rng.randi() % (columns - 1)
			var along: float = -span * 0.5 + gap * span / columns
			for sheet: int in range(1 + rng.randi() % 2):
				# Above the 1.1 m base course (it stands 7 cm proud); overlapping sheets step outwards.
				var place: Array = _on_wall(roof, side, along + 0.33 * sheet, ground + 1.5 + rng.randf_range(-0.08, 0.08), 0.085 + sheet * 0.006)
				var at: Vector3 = place[0]
				var paper: Color = PAPER[rng.randi() % PAPER.size()]
				_decor(Vector2(at.x, at.z), "poster", 0.4, true)
				w._box_with(at, Vector3(0.6, 0.84, 0.012), w._material(paper, 0.95), false, place[1])
				# A peeled corner: a darker, smaller sheet of the poster underneath.
				if rng.randf() < 0.5:
					w._box_with(at + Vector3(0.18, -0.3, 0) + Vector3(sin(place[1]), 0, cos(place[1])) * 0.008, Vector3(0.22, 0.22, 0.012), w._material(paper.darkened(0.25), 0.95), false, place[1])
				var words: String = POSTERS[_poster_index % POSTERS.size()]
				_poster_index += 1 + rng.randi() % 3
				var label: Label3D = w._label(words, at + Vector3(sin(place[1]), 0, cos(place[1])) * 0.012, 30, INK[rng.randi() % INK.size()], place[1], 0.0045)
				label.outline_size = 0
				label.visibility_range_end = 38.0
		# Window air-conditioners hung under a few upper-floor windows (older, lower blocks);
		# on businesses only at the back, clear of the neon sign board over the entrance.
		if size.y > 8.0 and size.y < 26.0 and rng.randf() < 0.55:
			var floors: int = int((size.y - 1.2) / 3.1)
			for unit: int in range(1 + rng.randi() % 3):
				var floor_index: int = 1 + rng.randi() % maxi(1, floors - 1)
				var y: float = 2.4 + floor_index * 3.1
				if y + 1.0 > size.y:
					continue
				var column: int = rng.randi() % columns
				var place: Array = _on_wall(roof, -1.0 if business or rng.randf() < 0.4 else 1.0, -span * 0.5 + (column + 0.5) * span / columns + 0.35, y - 0.95, 0.27)
				var at: Vector3 = place[0]
				_decor(Vector2(at.x, at.z), "window AC", 0.5, true)
				w._box_with(at, Vector3(0.66, 0.42, 0.44), metal, false, place[1])
				w._box_with(at + Vector3(sin(place[1]), 0, cos(place[1])) * 0.225, Vector3(0.5, 0.28, 0.02), dark, false, place[1])
		if business:
			# Some shops never reopened after the holidays: a roller shutter over a ground-floor
			# window, with a FOR LEASE card; the rest have a stopped clock over the door.
			if columns >= 2 and rng.randf() < 0.3:
				var column: int = rng.randi() % columns
				var place: Array = _on_wall(roof, 1.0, -span * 0.5 + (column + 0.5) * span / columns, ground + 1.75, 0.13)
				var at: Vector3 = place[0]
				_decor(Vector2(at.x, at.z), "roller shutter", 1.0, true)
				w._box_with(at, Vector3(1.9, 3.2, 0.06), shutter, false, place[1])
				w._box_with(at + Vector3(0, 1.72, 0), Vector3(2.0, 0.32, 0.3), shutter, false, place[1])
				for rib: int in range(7):
					w._box_with(at + Vector3(0, -1.3 + rib * 0.42, 0) + Vector3(sin(place[1]), 0, cos(place[1])) * 0.035, Vector3(1.9, 0.03, 0.02), dark, false, place[1])
				var card_label: Label3D = w._label("FOR LEASE\n555-0199", at + Vector3(0, 0.1, 0) + Vector3(sin(place[1]), 0, cos(place[1])) * 0.05, 28, Color(0.75, 0.15, 0.1), place[1], 0.0045)
				card_label.outline_modulate = Color(0.95, 0.93, 0.85)
				card_label.outline_size = 10
				card_label.visibility_range_end = 38.0
			elif rng.randf() < 0.35:
				var place: Array = _on_wall(roof, 1.0, rng.randf_range(-0.3, 0.3) * span, ground + 3.35, 0.05)
				var at: Vector3 = place[0]
				var yaw: float = place[1]
				_decor(Vector2(at.x, at.z), "stopped clock", 0.5, true)
				w._mesh_at(MeshKit.cylinder(0.42, 0.42, 0.06, 16), at, clock_face, yaw, Vector3(PI * 0.5, 0, 0)).rotation = Vector3(PI * 0.5, yaw, 0)
				var outward: Vector3 = Vector3(sin(yaw), 0, cos(yaw))
				var across: Vector3 = Vector3(outward.z, 0, -outward.x)
				# Eleven fifty-nine: the minute hand at twelve, the hour hand just short of it.
				w._box_with(at + outward * 0.04 + Vector3(0, 0.15, 0), Vector3(0.035, 0.32, 0.02), dark, false, yaw)
				w._box_with(at + outward * 0.045 + Vector3(0, 0.1, 0) - across * 0.02, Vector3(0.05, 0.22, 0.02), dark, false, yaw + 0.0)
		elif columns >= 2 and rng.randf() < 0.22 and size.y > 7.0:
			# A boarded-up first-floor window on a few older buildings.
			var column: int = rng.randi() % columns
			var place: Array = _on_wall(roof, 1.0 if rng.randf() < 0.5 else -1.0, -span * 0.5 + (column + 0.5) * span / columns, 5.5, 0.13)
			var at: Vector3 = place[0]
			_decor(Vector2(at.x, at.z), "boarded window", 1.0, true)
			for board: int in range(4):
				w._box_with(at + Vector3(0, -0.6 + board * 0.4, 0), Vector3(1.75 + rng.randf_range(-0.1, 0.1), 0.26, 0.04), plank, false, float(place[1]) + rng.randf_range(-0.04, 0.04))
		if not business:
			continue
		# Service side of businesses: a lit back door, a dumpster (solid), loose bags, newspaper
		# bundles and flattened cardboard (walk-through).
		var back_door: Array = _on_wall(roof, -1.0, rng.randf_range(-0.25, 0.25) * span, ground + 1.05, 0.1)
		var door_at: Vector3 = back_door[0]
		_decor(Vector2(door_at.x, door_at.z), "back door", 0.6, true)
		w._box_with(door_at, Vector3(1.0, 2.1, 0.05), w._material(Color(0.24, 0.26, 0.27), 0.6, "metal"), false, back_door[1])
		w._box_with(door_at + Vector3(0, 1.4, 0) + Vector3(sin(back_door[1]), 0, cos(back_door[1])) * 0.08, Vector3(0.34, 0.14, 0.16), back_lamp, false, back_door[1])
		var front: Vector3 = roof["front"]
		var back: Vector2 = -Vector2(front.x, front.z).normalized()
		var depth: float = size.z if absf(Vector2(front.x, front.z).normalized().dot(Vector2(sin(float(roof["yaw"])), cos(float(roof["yaw"]))))) > 0.5 else size.x
		var spot: Vector2 = center + back * (depth * 0.5 + 1.9) + Vector2(back.y, -back.x) * rng.randf_range(-2.0, 2.0)
		var facing: float = atan2(back.x, back.y)
		if spot.distance_to(Vector2(door_at.x, door_at.z)) > 2.2 and _clutter_claim(spot, 1.3, "alley dumpster"):
			w.city_clutter.back()["y"] = _ground_y(spot)
			w._dumpster(Vector3(spot.x, _ground_y(spot), spot.y), facing, bin_color)
			_contact(spot, Vector2(2.3, 1.4), facing, dark)
			# Motor Mile and the docks keep old tyres out back.
			var district: String = w.district_at(Vector3(spot.x, 0, spot.y))
			var tyres: Vector2 = spot - Vector2(back.y, -back.x) * 2.0
			if district in ["MOTOR MILE", "SOUTH DOCKS", "OLD WHARF", "KINGSWAY"] and _clutter_claim(tyres, 0.7, "tyre stack"):
				var count: int = 3 + rng.randi() % 3
				for tyre: int in range(count):
					w._mesh_at(MeshKit.cylinder(0.36, 0.36, 0.24, 12), Vector3(tyres.x + rng.randf_range(-0.04, 0.04), _ground_y(tyres) + 0.12 + tyre * 0.25, tyres.y), dark)
				w._collider(Vector3(tyres.x, _ground_y(tyres) + count * 0.125, tyres.y), Vector3(0.72, count * 0.25, 0.72))
		var side_spot: Vector2 = spot + Vector2(back.y, -back.x) * 2.2
		if can_place(side_spot, 0.9) and side_spot.distance_to(Vector2(door_at.x, door_at.z)) > 1.6:
			w._occupied.append(side_spot)
			_decor(side_spot, "trash bags", 0.9)
			var base: float = _ground_y(side_spot)
			for bag: int in range(2 + rng.randi() % 3):
				var at: Vector2 = side_spot + Vector2(rng.randf_range(-0.45, 0.45), rng.randf_range(-0.45, 0.45))
				var mesh: MeshInstance3D = w._mesh_at(MeshKit.sphere(0.32, 0.5, 8, 4), Vector3(at.x, base + 0.2, at.y), dark, rng.randf() * TAU)
				mesh.scale = Vector3(1.0, rng.randf_range(0.75, 1.05), 0.9)
			for box: int in range(1 + rng.randi() % 2):
				var at: Vector2 = side_spot + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
				var height: float = rng.randf_range(0.3, 0.55)
				w._box_with(Vector3(at.x, base + height * 0.5, at.y), Vector3(0.6, height, 0.45), card, false, rng.randf() * PI)
			var flat: Vector2 = side_spot + Vector2(back.y, -back.x) * 1.1
			w._box_with(Vector3(flat.x, base + 0.012, flat.y), Vector3(1.1, 0.02, 0.8), card, false, rng.randf() * PI)
			# Unsold newspaper bundles, tied with string.
			for bundle: int in range(rng.randi() % 3):
				var at: Vector2 = side_spot - Vector2(back.y, -back.x) * 0.9 + Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2))
				w._box_with(Vector3(at.x, base + 0.13 + bundle * 0.25, at.y), Vector3(0.42, 0.24, 0.3), w._material(PAPER[0], 0.95), false, rng.randf_range(-0.3, 0.3))
				w._box_with(Vector3(at.x, base + 0.13 + bundle * 0.25, at.y), Vector3(0.02, 0.25, 0.31), dark, false, 0.0)
	# Motor Mile's lots: stacks of old tyres against the block edges (solid, knee to waist high).
	for spot: Vector2 in [Vector2(154, -5), Vector2(216, -5), Vector2(154, 25), Vector2(216, 25), Vector2(185, -5), Vector2(104, 45), Vector2(136, 45), Vector2(136, 85), Vector2(104, 60)]:
		if not _clutter_claim(spot, 0.7, "tyre stack"):
			continue
		var count: int = 3 + rng.randi() % 4
		var base: float = _ground_y(spot)
		for tyre: int in range(count):
			w._mesh_at(MeshKit.cylinder(0.36, 0.36, 0.24, 12), Vector3(spot.x + rng.randf_range(-0.04, 0.04), base + 0.12 + tyre * 0.25, spot.y + rng.randf_range(-0.04, 0.04)), dark)
		w._collider(Vector3(spot.x, base + count * 0.125, spot.y), Vector3(0.72, count * 0.25, 0.72))
		_contact(spot, Vector2(1.0, 1.0), 0.0, dark)
	# Working yards: pallet stacks and a loose crate or two on the wharf and dock plinths.
	var pallet: StandardMaterial3D = w._material(Color(0.56, 0.43, 0.28), 0.9, "planks")
	for spot: Vector2 in [Vector2(-302, -164), Vector2(-288, -182), Vector2(-270, -166), Vector2(-258, -181), Vector2(-356, -163), Vector2(318, 300), Vector2(334, 344), Vector2(366, 300), Vector2(370, 352), Vector2(290, 274)]:
		if not _clutter_claim(spot, 1.4, "pallet stack"):
			continue
		var base: float = _ground_y(spot)
		var yaw: float = rng.randf_range(-0.25, 0.25) + (PI * 0.5 if rng.randf() < 0.5 else 0.0)
		var layers: int = 3 + rng.randi() % 5
		for level: int in range(layers):
			w._box_with(Vector3(spot.x, base + 0.07 + level * 0.15, spot.y), Vector3(1.2, 0.14, 1.0), pallet, false, yaw + rng.randf_range(-0.05, 0.05))
		w._collider(Vector3(spot.x, base + layers * 0.075, spot.y), Vector3(1.2, layers * 0.15, 1.0), yaw)
		_contact(spot, Vector2(1.5, 1.3), yaw, dark)
		var beside: Vector2 = spot + Vector2(cos(yaw), -sin(yaw)) * 1.5
		if rng.randf() < 0.6 and can_place(beside, 0.7):
			w._occupied.append(beside)
			w.city_clutter.append({"kind": "crate", "at": beside, "radius": 0.7, "roof": false})
			w._crate(Vector3(beside.x, base, beside.y), 1.0)
	# Public spaces: leftover party bunting over the path, drifts of leaves and litter at the beds.
	for spec: Dictionary in SITES:
		if not spec["style"] in ["plaza", "garden", "picnic"]:
			continue
		var rect: Rect2 = spec["rect"]
		var mid: Vector2 = rect.get_center()
		var base: float = w.surface_height(mid) + 0.05
		# Poles stand beside, not in, the path entrances (is_path_entrance keeps 2.4 m either side).
		var from: Vector2 = Vector2(rect.position.x + 2.2, mid.y + 3.0)
		var to: Vector2 = Vector2(rect.end.x - 2.2, mid.y + 3.0)
		_decor(mid, "bunting", 0.3)
		for end: Vector2 in [from, to]:
			w._box_with(Vector3(end.x, base + 1.8, end.y), Vector3(0.08, 3.6, 0.08), dark, false)
		var flags: int = int(from.distance_to(to) / 0.55)
		for flag: int in range(flags):
			var t: float = (flag + 0.5) / flags
			var at: Vector2 = from.lerp(to, t)
			var sag: float = 0.55 * (1.0 - pow(2.0 * t - 1.0, 2.0))
			w._box_with(Vector3(at.x, base + 3.35 - sag, at.y), Vector3(0.3, 0.26, 0.01), w._material(BUNTING[flag % BUNTING.size()], 0.9), false)
		for corner: Vector2 in [rect.position + Vector2(3.2, 2.6), Vector2(rect.end.x - 3.2, rect.position.y + 2.6), rect.end - Vector2(3.2, 2.6), Vector2(rect.position.x + 3.2, rect.end.y - 2.6)]:
			if not can_place(corner, 1.0):
				continue
			_decor(corner, "leaf drift", 1.0)
			for leaf: int in range(9):
				var at: Vector2 = corner + Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.9, 0.9))
				var tone: Color = [Color(0.55, 0.35, 0.15), Color(0.62, 0.45, 0.18), Color(0.4, 0.3, 0.16)][leaf % 3]
				w._box_with(Vector3(at.x, w.surface_height(at) + 0.012 + leaf * 0.0004, at.y), Vector3(0.16, 0.01, 0.11), w._material(tone, 0.95), false, rng.randf() * PI)
	# Oil stains in the parking bays: flat, shadowless, no collision.
	for spec: Dictionary in SITES:
		if spec["style"] != "parking":
			continue
		var rect: Rect2 = spec["rect"]
		for x: float in range(int(rect.position.x + 5), int(rect.end.x - 4), 4):
			for z: float in [rect.position.y + 4, rect.end.y - 4]:
				if rng.randf() < 0.45:
					var at: Vector2 = Vector2(x + 2.0 + rng.randf_range(-0.4, 0.4), z + rng.randf_range(-0.8, 0.8))
					_decor(at, "oil stain", 0.6)
					var stain: MeshInstance3D = w._mesh_at(MeshKit.cylinder(0.6, 0.6, 0.004, 10), Vector3(at.x, 0.228, at.y), dark, rng.randf() * TAU)
					stain.scale = Vector3(rng.randf_range(0.8, 1.5), 1.0, rng.randf_range(0.6, 1.0))
	for key: Vector3i in _cell_order:
		var node: Node3D = _cells[key]
		# Clutter is small and low: a shadow-pass draw per cell costs more than it shows (measured
		# +140 calls on Motor Mile). Solid pieces get a flat contact-shadow patch instead.
		for child: Node in node.get_children():
			if child is GeometryInstance3D:
				(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w._finish(node)
		for child: Node in node.get_children():
			if child is GeometryInstance3D:
				var geometry: GeometryInstance3D = child as GeometryInstance3D
				geometry.layers = 1 << (w.CLUTTER_LAYER - 1)
				if geometry is Label3D:
					continue
				geometry.visibility_range_end = 90.0 if key.z == 0 else 70.0
				geometry.visibility_range_end_margin = 8.0
				w._detail_ranges.append(geometry)

## A flat dark patch under a solid prop: grounds it without a shadow-pass draw (shares the
## cell's dark material, so it adds no draw call).
func _contact(at: Vector2, size: Vector2, yaw: float, material: Material) -> void:
	w._box_with(Vector3(at.x, _ground_y(at) + 0.004, at.y), Vector3(size.x, 0.004, size.y), material, false, yaw)

## Walking-surface height at a clutter spot (raised slabs are recorded as they are built).
func _ground_y(at: Vector2) -> float:
	return w.surface_height(at)
