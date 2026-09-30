extends SceneTree
## Map 0.8 fill audit: how full the city is, how much of it can be entered, and how far a car can
## see down its street. Headless: godot --headless --path . --script res://tests/city_fill.gd
## Prints "CITY FILL RESULT: N checks, M failures".
##
## HOW THE METRICS ARE COUNTED (world.buildings, one record per building):
##  * Enterable ratio = records with enterable == true / all records. A record is one building however
##    many outlines its builder registered. Enterable: the 12 Midtown walk-in shops, the eight trademark
##    plots (highrise, hotel, garage, motel, nightclub, stripclub, burger, gunstore) and every prefab
##    (scripts/buildings/prefabs.gd, root meta "enterable"). Solid: every generic `_tower`,
##    `_building` and `_fill_block` box, and Midtown's sealed CARGO 04.
##  * Sightlines: three parallel rays (centre and +-1.5 m, so a lone lamp post does not count as a
##    blocker) at car eye height (1.3 m) along every road segment, both ways, every 12 m. A ray ends at
##    its first collider ("hit") or where it leaves the land ("coast": a view over water is scenic and is
##    listed separately). The sightline of a spot is the best of its three rays.
##  * Emptiness: a 4 m grid over land. A cell is FILLED if it is on a road (centre line +- half width +
##    1.5 m), inside a building outline grown 1.5 m, inside a park/plaza polygon, or a downward ray from
##    8 m meets something taller than 2.2 m (container stacks, walls). Everything else is EMPTY. The
##    largest empty axis-aligned square is what the target limits.
## Also writes work/captures/city_fill_map.png (a colour map of all of it) for a look.

const WorldScript = preload("res://scripts/world.gd")
## Set once the fill pass is done: the targets become real assertions.
const ASSERT_TARGETS: bool = true
const EYE: float = 1.3
const MAX_RAY: float = 500.0
const CELL: float = 4.0
## The most sightlines (see _sightlines) that may run over 110 m across open ground, off every carriageway.
const OPEN_VIEW_LIMIT: int = 380

var world: Variant
var space: PhysicsDirectSpaceState3D
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + label)


func _physics(count: int) -> void:
	for step: int in range(count):
		await physics_frame


func _run() -> void:
	create_timer(160).timeout.connect(func() -> void: quit(2))
	world = WorldScript.new()
	root.add_child(world)
	await _physics(4)
	space = world.get_world_3d().direct_space_state
	_ratio()
	_index_roads()
	var view: Dictionary = _sightlines()
	_emptiness()
	_overlaps()
	print("CARVED STREETS: %s" % [world.city_fill.carved])
	_prop_cost()
	_road_solid_checks()
	_road_sweep()
	_cluster_checks()
	_life_checks()
	await _determinism()
	print("CITY FILL RESULT: %d checks, %d failures" % [checks, failures])
	world.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)


# --- Enterable ratio -------------------------------------------------------------------------------

func _ratio() -> void:
	var total: int = world.buildings.size()
	var open: int = 0
	var by_kind: Dictionary = {}
	var by_district: Dictionary = {}
	for record: Dictionary in world.buildings:
		var kind: String = str(record["kind"])
		var entry: Array = by_kind.get(kind, [0, 0])
		entry[0] += 1
		if bool(record["enterable"]):
			entry[1] += 1
			open += 1
		by_kind[kind] = entry
		var poly: PackedVector2Array = world.footprint_polys[(record["footprints"] as Array)[0]] if not (record["footprints"] as Array).is_empty() else PackedVector2Array()
		if not poly.is_empty():
			var center: Vector2 = Vector2.ZERO
			for point: Vector2 in poly:
				center += point
			center /= poly.size()
			var district: String = world.district_at(Vector3(center.x, 0, center.y))
			var counts: Array = by_district.get(district, [0, 0])
			counts[0] += 1
			counts[1] += 1 if bool(record["enterable"]) else 0
			by_district[district] = counts
	var ratio: float = float(open) / float(maxi(total, 1))
	print("ENTERABLE: %d of %d buildings (%.1f%%)" % [open, total, ratio * 100.0])
	for kind: String in by_kind:
		print("  kind %-14s %3d buildings, %3d enterable" % [kind, by_kind[kind][0], by_kind[kind][1]])
	for district: String in by_district:
		print("  district %-16s %3d buildings, %3d enterable (%.0f%%)" % [district, by_district[district][0], by_district[district][1], 100.0 * by_district[district][1] / maxf(by_district[district][0], 1)])
	_check(total >= 100, "The building registry covers the city (%d buildings)" % total)
	if ASSERT_TARGETS:
		_check(ratio >= 0.5, "At least half the buildings are enterable (%.1f%%)" % (ratio * 100.0))


# --- Sightlines ------------------------------------------------------------------------------------------

## Distance a ray from `from` (x/z) along `dir` travels: [metres, "hit" or "coast", hit point].
func _ray_length(from: Vector2, dir: Vector2) -> Array:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(from.x, EYE, from.y), Vector3(from.x + dir.x * MAX_RAY, EYE, from.y + dir.y * MAX_RAY))
	var hit: Dictionary = space.intersect_ray(query)
	var reach: float = MAX_RAY
	var by: String = "far"
	if not hit.is_empty():
		reach = Vector2((hit["position"] as Vector3).x - from.x, (hit["position"] as Vector3).z - from.y).length()
		by = "hit"
	var step: float = 6.0
	var travelled: float = step
	while travelled < reach:
		if not world._on_land(from + dir * travelled):
			return [travelled, "coast"]
		travelled += step
	return [reach, by]


func _sightlines() -> Dictionary:
	var per_district: Dictionary = {}
	var ends: Dictionary = {}
	var over: int = 0
	var open_views: int = 0
	var open_ends: Dictionary = {}
	var samples: int = 0
	var longest: Array = []
	for road: Dictionary in world.roads:
		var points: PackedVector2Array = road["points"]
		for index: int in range(points.size() - 1):
			var a: Vector2 = points[index]
			var b: Vector2 = points[index + 1]
			var length: float = a.distance_to(b)
			if length < 1.0:
				continue
			var forward: Vector2 = (b - a) / length
			var across: Vector2 = Vector2(-forward.y, forward.x)
			var steps: int = maxi(1, int(length / 12.0))
			for step: int in range(steps + 1):
				var at: Vector2 = a + forward * (length * step / steps)
				if not world._on_land(at):
					continue
				for dir: Vector2 in [forward, -forward]:
					var best: Array = [0.0, "hit"]
					var best_from: Vector2 = at
					for lateral: float in [-1.5, 0.0, 1.5]:
						var result: Array = _ray_length(at + across * lateral, dir)
						if float(result[0]) > float(best[0]):
							best = result
							best_from = at + across * lateral
					samples += 1
					var district: String = world.district_at(Vector3(at.x, 0, at.y))
					var record: Dictionary = per_district.get(district, {"hit": 0.0, "coast": 0.0, "over": 0, "n": 0, "where": Vector2.ZERO, "road": ""})
					record["n"] += 1
					if str(best[1]) == "coast":
						record["coast"] = maxf(float(record["coast"]), float(best[0]))
					else:
						if float(best[0]) > float(record["hit"]):
							record["hit"] = float(best[0])
							record["where"] = at
							record["road"] = str(road["name"])
						if float(best[0]) > 120.0:
							record["over"] += 1
							over += 1
					per_district[district] = record
					if str(best[1]) != "coast":
						longest.append([float(best[0]), str(road["name"]), at, dir])
						# How much of the view runs over open ground (off every carriageway by 1 m)?
						var length_ray: float = float(best[0])
						var first_off: float = length_ray
						var probe: float = 6.0
						while probe < length_ray:
							if _road_depth(best_from + dir * probe) < -1.0:
								first_off = probe
								break
							probe += 6.0
						if length_ray - first_off > 110.0:
							open_views += 1
							open_ends[str(road["name"])] = int(open_ends.get(str(road["name"]), 0)) + 1
						if float(best[0]) > 150.0:
							var end_at: Vector2 = at + dir * float(best[0])
							var cell: String = "(%d,%d)" % [roundi(end_at.x / 25.0) * 25, roundi(end_at.y / 25.0) * 25]
							ends[cell] = int(ends.get(cell, 0)) + 1
	longest.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) > float(q[0]))
	var buckets: Array[int] = [0, 0, 0, 0]
	for entry: Array in longest:
		var metres: float = float(entry[0])
		buckets[0] += 1 if metres > 150.0 else 0
		buckets[1] += 1 if metres > 200.0 else 0
		buckets[2] += 1 if metres > 300.0 else 0
		buckets[3] += 1 if metres >= 499.0 else 0
	print("SIGHTLINE HISTOGRAM: over 150 m %d, over 200 m %d, over 300 m %d, unbroken to the 500 m limit %d" % [buckets[0], buckets[1], buckets[2], buckets[3]])
	print("SIGHTLINES: %d samples, %d longer than 120 m (blocked by a building or prop; views over water excluded)" % [samples, over])
	var names: Array = per_district.keys()
	names.sort()
	for district: String in names:
		var record: Dictionary = per_district[district]
		print("  %-16s longest %5.0f m on %s at (%.0f, %.0f); over 120 m: %3d of %3d; longest view over water %.0f m" % [district, float(record["hit"]), str(record["road"]), (record["where"] as Vector2).x, (record["where"] as Vector2).y, int(record["over"]), int(record["n"]), float(record["coast"])])
	var shown: Dictionary = {}
	print("  Longest 12 sightlines by street:")
	for entry: Array in longest:
		if shown.size() >= 12:
			break
		if shown.has(entry[1]):
			continue
		shown[entry[1]] = true
		print("    %5.0f m  %-22s from (%.0f, %.0f) heading (%.1f, %.1f)" % [float(entry[0]), str(entry[1]), (entry[2] as Vector2).x, (entry[2] as Vector2).y, (entry[3] as Vector2).x, (entry[3] as Vector2).y])
	var end_cells: Array = ends.keys()
	end_cells.sort_custom(func(p: String, q: String) -> bool: return int(ends[p]) > int(ends[q]))
	var listing: Array[String] = []
	for cell: String in end_cells.slice(0, 14):
		listing.append("%s x%d" % [cell, ends[cell]])
	print("  Where rays over 150 m END (25 m cells): %s" % ", ".join(listing))
	var worst: float = float(longest[0][0]) if not longest.is_empty() else 0.0
	_check(samples > 500, "Sightlines sampled every road (%d rays)" % samples)
	if ASSERT_TARGETS:
		# Street-long views along a carriageway cannot be broken any more (nothing solid stands on a road now);
		# what the off-road corner and sightline props guard is the view that leaves the street and runs over
		# open gray ground. (Before this pass: 0.8's in-road chicanes broke the street views instead.)
		print("OPEN-GROUND VIEWS: %d rays run more than 110 m over open ground; by street: %s" % [open_views, open_ends])
		_check(open_views <= OPEN_VIEW_LIMIT, "Views over open ground are broken up by off-road props (%d rays over 110 m, limit %d)" % [open_views, OPEN_VIEW_LIMIT])
	return per_district


# --- Emptiness -------------------------------------------------------------------------------------------

func _emptiness() -> void:
	var bounds: Rect2 = world.map_bounds()
	var columns: int = int(bounds.size.x / CELL) + 1
	var rows: int = int(bounds.size.y / CELL) + 1
	var grid: PackedByteArray = PackedByteArray()
	grid.resize(columns * rows)
	# 0 water, 1 empty land, 2 road, 3 building, 4 park/plaza, 5 tall solid.
	var expanded: Array[PackedVector2Array] = []
	var enterable_polys: Array[bool] = []
	for record: Dictionary in world.buildings:
		for index: int in record["footprints"]:
			var offset: Array[PackedVector2Array] = Geometry2D.offset_polygon(world.footprint_polys[index], 1.5)
			if not offset.is_empty():
				expanded.append(offset[0])
				enterable_polys.append(bool(record["enterable"]))
	var empty_cells: int = 0
	var land_cells: int = 0
	# Dressed ground: everything a builder placed (props, walls, yards, lawns, paved lots), by 16 m cell.
	var dressed: Dictionary = {}
	for rect: Rect2 in world._blockers:
		var low: Vector2i = Vector2i(floori(rect.position.x / 16.0), floori(rect.position.y / 16.0))
		var high: Vector2i = Vector2i(floori(rect.end.x / 16.0), floori(rect.end.y / 16.0))
		for cx: int in range(low.x, high.x + 1):
			for cy: int in range(low.y, high.y + 1):
				if not dressed.has(Vector2i(cx, cy)):
					dressed[Vector2i(cx, cy)] = []
				(dressed[Vector2i(cx, cy)] as Array).append(rect.grow(1.0))
	# The gun club's range yard, Halcyon Beach and the pier are open on purpose.
	var zones: Array[PackedVector2Array] = [world.BEACH, PackedVector2Array([Vector2(285, -104), Vector2(415, -104), Vector2(415, -20), Vector2(285, -20)])]
	for row: int in range(rows):
		for column: int in range(columns):
			var at: Vector2 = bounds.position + Vector2((column + 0.5) * CELL, (row + 0.5) * CELL)
			var kind: int = 0
			if world._on_land(at):
				kind = 1
				var done: bool = false
				for road: Dictionary in world.roads:
					var points: PackedVector2Array = road["points"]
					var half: float = float(road["width"]) * 0.5 + 1.5
					for segment: int in range(points.size() - 1):
						if at.distance_to(Geometry2D.get_closest_point_to_segment(at, points[segment], points[segment + 1])) < half:
							done = true
							break
					if done:
						break
				if done:
					kind = 2
				else:
					for index: int in range(expanded.size()):
						if Geometry2D.is_point_in_polygon(at, expanded[index]):
							kind = 3
							break
					if kind == 1:
						for plaza: PackedVector2Array in world.plazas:
							if Geometry2D.is_point_in_polygon(at, plaza):
								kind = 4
								break
					if kind == 1:
						var key: Vector2i = Vector2i(floori(at.x / 16.0), floori(at.y / 16.0))
						if dressed.has(key):
							for rect: Rect2 in dressed[key]:
								if rect.has_point(at):
									kind = 5
									break
					if kind == 1:
						for zone: PackedVector2Array in zones:
							if Geometry2D.is_point_in_polygon(at, zone):
								kind = 4
								break
					if kind == 1:
						var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, 8.0, at.y), Vector3(at.x, 0.5, at.y)))
						if not hit.is_empty() and (hit["position"] as Vector3).y > 2.2:
							kind = 5
				land_cells += 1
				empty_cells += 1 if kind == 1 else 0
			grid[row * columns + column] = kind
	# Largest empty square (dynamic programming), and the biggest connected empty region.
	var best_side: int = 0
	var best_at: Vector2i = Vector2i.ZERO
	var side: PackedInt32Array = PackedInt32Array()
	side.resize(columns * rows)
	for row: int in range(rows):
		for column: int in range(columns):
			var index: int = row * columns + column
			if grid[index] != 1:
				side[index] = 0
				continue
			if row == 0 or column == 0:
				side[index] = 1
			else:
				side[index] = mini(mini(side[index - 1], side[index - columns]), side[index - columns - 1]) + 1
			if side[index] > best_side:
				best_side = side[index]
				best_at = Vector2i(column, row)
	var corner: Vector2 = bounds.position + Vector2((best_at.x - best_side + 1) * CELL, (best_at.y - best_side + 1) * CELL)
	print("EMPTINESS: %d of %d land cells (%.1f%%) are empty; largest empty square %.0f m at (%.0f, %.0f)-(%.0f, %.0f)" % [empty_cells, land_cells, 100.0 * empty_cells / maxf(land_cells, 1), best_side * CELL, corner.x, corner.y, corner.x + best_side * CELL, corner.y + best_side * CELL])
	# Connected empty regions, largest first.
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(columns * rows)
	var regions: Array = []
	for start: int in range(columns * rows):
		if grid[start] != 1 or seen[start] == 1:
			continue
		var queue: Array[int] = [start]
		seen[start] = 1
		var count: int = 0
		var low: Vector2i = Vector2i(columns, rows)
		var high: Vector2i = Vector2i(-1, -1)
		while not queue.is_empty():
			var current: int = queue.pop_back()
			count += 1
			var cx: int = current % columns
			var cy: int = current / columns
			low = Vector2i(mini(low.x, cx), mini(low.y, cy))
			high = Vector2i(maxi(high.x, cx), maxi(high.y, cy))
			for delta: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = cx + delta.x
				var ny: int = cy + delta.y
				if nx < 0 or ny < 0 or nx >= columns or ny >= rows:
					continue
				var next: int = ny * columns + nx
				if grid[next] == 1 and seen[next] == 0:
					seen[next] = 1
					queue.append(next)
		regions.append([count, low, high])
	regions.sort_custom(func(p: Array, q: Array) -> bool: return int(p[0]) > int(q[0]))
	for index: int in range(mini(10, regions.size())):
		var region: Array = regions[index]
		var low_at: Vector2 = bounds.position + Vector2(region[1]) * CELL
		var high_at: Vector2 = bounds.position + Vector2(region[2] + Vector2i.ONE) * CELL
		print("  empty region %d: %5.0f m2, box (%.0f, %.0f)-(%.0f, %.0f) [%s]" % [index + 1, float(region[0]) * CELL * CELL, low_at.x, low_at.y, high_at.x, high_at.y, world.district_at(Vector3((low_at.x + high_at.x) * 0.5, 0, (low_at.y + high_at.y) * 0.5))])
	_write_map(grid, columns, rows, expanded, enterable_polys, bounds)
	_check(land_cells > 1000, "The emptiness grid covers the land (%d cells)" % land_cells)
	if ASSERT_TARGETS:
		_check(best_side * CELL <= 60.0, "The biggest empty land square is at most 60 m (%.0f m)" % (best_side * CELL))


func _write_map(grid: PackedByteArray, columns: int, rows: int, expanded: Array[PackedVector2Array], enterable_polys: Array[bool], bounds: Rect2) -> void:
	var image: Image = Image.create(columns, rows, false, Image.FORMAT_RGB8)
	var palette: Array[Color] = [Color(0.05, 0.1, 0.25), Color(0.95, 0.15, 0.15), Color(0.45, 0.45, 0.47), Color(0.3, 0.32, 0.4), Color(0.4, 0.75, 0.4), Color(0.9, 0.6, 0.2)]
	for row: int in range(rows):
		for column: int in range(columns):
			var kind: int = grid[row * columns + column]
			var color: Color = palette[kind]
			if kind == 3:
				var at: Vector2 = bounds.position + Vector2((column + 0.5) * CELL, (row + 0.5) * CELL)
				for index: int in range(expanded.size()):
					if enterable_polys[index] and Geometry2D.is_point_in_polygon(at, expanded[index]):
						color = Color(0.95, 0.9, 0.3)
						break
			image.set_pixel(column, row, color)
	var folder: String = ProjectSettings.globalize_path("res://work/captures")
	DirAccess.make_dir_recursive_absolute(folder)
	if OS.get_cmdline_user_args().has("quadrants"):
		_write_quadrants(image, bounds, folder)
	image.resize(columns * 4, rows * 4, Image.INTERPOLATE_NEAREST)
	image.save_png(folder + "/city_fill_map.png")
	print("MAP written to %s/city_fill_map.png (origin %.0f, %.0f; %.0f m per pixel/2; red = empty land, yellow = enterable building, slate = solid building, grey = road, green = park)" % [folder, bounds.position.x, bounds.position.y, CELL])


## Four zoomed quadrant maps (2 px per metre) with a 50 m grid (bright every 100 m), for planning streets.
func _write_quadrants(image: Image, bounds: Rect2, folder: String) -> void:
	var scale: int = 8
	var big: Image = image.duplicate()
	big.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
	var px_per_m: float = float(scale) / CELL
	for metre_x: int in range(int(ceilf(bounds.position.x / 50.0)) * 50, int(bounds.end.x), 50):
		var px: int = int((metre_x - bounds.position.x) * px_per_m)
		var color: Color = Color(1, 1, 1, 1) if metre_x % 100 == 0 else Color(0.55, 0.55, 0.65)
		for py: int in range(0, big.get_height()):
			big.set_pixel(px, py, color)
	for metre_z: int in range(int(ceilf(bounds.position.y / 50.0)) * 50, int(bounds.end.y), 50):
		var py: int = int((metre_z - bounds.position.y) * px_per_m)
		var color: Color = Color(1, 1, 1, 1) if metre_z % 100 == 0 else Color(0.55, 0.55, 0.65)
		for px: int in range(0, big.get_width()):
			big.set_pixel(px, py, color)
	var half_w: int = big.get_width() / 2
	var half_h: int = big.get_height() / 2
	var names: Array[String] = ["nw", "ne", "sw", "se"]
	for index: int in range(4):
		var part: Image = big.get_region(Rect2i((index % 2) * half_w, (index / 2) * half_h, half_w, half_h))
		part.save_png("%s/city_fill_q_%s.png" % [folder, names[index]])
	print("QUADRANTS written; origin (%.0f, %.0f), 2 px per metre, quadrant size %d x %d px, split at x %.0f z %.0f" % [bounds.position.x, bounds.position.y, half_w, half_h, bounds.position.x + half_w / px_per_m, bounds.position.y + half_h / px_per_m])


# --- Street props off the road ------------------------------------------------------------------------

## The corner and sightline clusters (scripts/city_fill.gd `clusters`): kerb corners are dressed, and every
## cluster keeps off doors, crew car spawns, alley mouths and the Midtown ring.
func _cluster_checks() -> void:
	var fill: Variant = world.city_fill
	var clusters: Array[Dictionary] = fill.clusters
	var corners: int = 0
	var kinds: Dictionary = {}
	for cluster: Dictionary in clusters:
		corners += 1 if bool(cluster["corner"]) else 0
		kinds[int(cluster["kind"])] = int(kinds.get(int(cluster["kind"]), 0)) + 1
	print("PLACEMENT FAILS: %s" % [fill.fail_reasons])
	print("PROPS: %d clusters (%d at junction corners), kinds %s" % [clusters.size(), corners, kinds])
	_check(corners >= 40 and corners == fill.corners_dressed, "Junction corners are dressed with solid props (%d corners, %d clusters in all)" % [corners, clusters.size()])
	_check(kinds.size() >= 4, "Corner props are varied (%d kinds)" % kinds.size())
	# Each cluster is a solid you cannot drive through (its collider is found by a shape query).
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(0.6, 0.6, 0.6)
	var hollow: int = 0
	for cluster: Dictionary in clusters:
		var at: Vector2 = cluster["center"]
		var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.collision_mask = 1
		query.transform = Transform3D(Basis.IDENTITY, Vector3(at.x, 0.9, at.y))
		if space.intersect_shape(query, 1).is_empty():
			hollow += 1
	_check(hollow == 0, "Every cluster is solid where it stands (%d hollow of %d)" % [hollow, clusters.size()])
	var bad: Array[String] = []
	var walkway: int = 0
	for cluster: Dictionary in clusters:
		var at: Vector2 = cluster["center"]
		var reach: float = Vector2(float(cluster["hw"]), float(cluster["hd"])).length()
		for door: Dictionary in world.interactable_doors:
			var spot: Vector3 = door["position"]
			if Vector2(spot.x, spot.z).distance_to(at) < reach + 2.0:
				bad.append("%s at %s within 2 m of door %s" % [cluster["kind"], at, door["label"]])
		for crew: Dictionary in world.crew_spawns.values():
			var car: Vector3 = crew["car"]
			if Vector2(car.x, car.z).distance_to(at) < 8.0:
				bad.append("%s at %s within 8 m of a crew car" % [cluster["kind"], at])
		for alley: Dictionary in fill.alleys:
			if (alley["at"] as Vector2).distance_to(at) < reach + 2.0:
				bad.append("%s at %s in an alley mouth" % [cluster["kind"], at])
		if absf(at.x) <= 100.0 and absf(at.y) <= 100.0:
			bad.append("%s at %s inside the Midtown ring" % [cluster["kind"], at])
		# A corner cluster keeps 2 m of walkway: no building footprint within 2 m of the middle of its back face.
		if bool(cluster["corner"]):
			var v: Vector2 = cluster["v"]
			var open: bool = true
			for footprint: Rect2 in world.footprints:
				var back: Vector2 = at + v * float(cluster["hd"])
				var nearest: Vector2 = Vector2(clampf(back.x, footprint.position.x, footprint.end.x), clampf(back.y, footprint.position.y, footprint.end.y))
				if nearest.distance_to(back) < 1.95:
					open = false
			walkway += 1 if open else 0
			if not open:
				bad.append("%s at %s has no walkway behind it" % [cluster["kind"], at])
		_check_off_road(cluster, bad)
	for line: String in bad.slice(0, 20):
		print("  CLUSTER " + line)
	_check(bad.is_empty(), "Clusters keep off doors (2 m), crew cars (8 m), alley mouths, the Midtown ring and the road (%d problems)" % bad.size())


## A cluster's outline stays 0.4 m off every carriageway.
func _check_off_road(cluster: Dictionary, bad: Array[String]) -> void:
	var at: Vector2 = cluster["center"]
	var u: Vector2 = cluster["u"]
	var v: Vector2 = cluster["v"]
	for sx: float in [-1.0, 0.0, 1.0]:
		for sz: float in [-1.0, 0.0, 1.0]:
			var point: Vector2 = at + u * sx * float(cluster["hw"]) + v * sz * float(cluster["hd"])
			if _road_depth(point) > -0.4:
				bad.append("%s at %s stands on or beside a carriageway" % [cluster["kind"], at])
				return


## Two builds of the world place the same props in the same spots (the fill pass has its own seeded stream).
func _determinism() -> void:
	var first: Array[Dictionary] = world.city_fill.clusters
	var second_world: Variant = WorldScript.new()
	root.add_child(second_world)
	await _physics(2)
	var second: Array[Dictionary] = second_world.city_fill.clusters
	var same: bool = first.size() == second.size()
	for index: int in range(mini(first.size(), second.size())):
		same = same and first[index]["center"] == second[index]["center"] and first[index]["kind"] == second[index]["kind"]
	_check(same, "A second build places the same %d props in the same spots (%d)" % [first.size(), second.size()])
	second_world.queue_free()
	await process_frame


## What the street props cost: colliders, merged meshes and labels in the fill pass's prop cells ("Props .."
## now, "Calm .." before this pass).
func _prop_cost() -> void:
	var bodies: int = 0
	var meshes: int = 0
	var labels: int = 0
	var cells: int = 0
	for node: Node in world.get_children():
		if str(node.name).begins_with("Props") or str(node.name).begins_with("Calm"):
			cells += 1
			var stack: Array[Node] = [node]
			while not stack.is_empty():
				var current: Node = stack.pop_back()
				stack.append_array(current.get_children())
				bodies += 1 if current is StaticBody3D else 0
				meshes += 1 if current is MeshInstance3D else 0
				labels += 1 if current is Label3D else 0
	print("PROP COST: %d cells, %d colliders, %d merged meshes (draw calls), %d labels" % [cells, bodies, meshes, labels])


# --- Nothing solid on the carriageway ----------------------------------------------------------------

## A road's centre-line segments (with their half widths) in a coarse grid, so the carriageway test is fast.
var _road_grid: Dictionary = {}

func _index_roads() -> void:
	_road_grid.clear()
	for road: Dictionary in world.roads:
		var points: PackedVector2Array = road["points"]
		var half: float = float(road["width"]) * 0.5
		for index: int in range(points.size() - 1):
			var box: Rect2 = Rect2(points[index], Vector2.ZERO).expand(points[index + 1]).grow(half + 1.0)
			for cx: int in range(floori(box.position.x / 16.0), floori(box.end.x / 16.0) + 1):
				for cy: int in range(floori(box.position.y / 16.0), floori(box.end.y / 16.0) + 1):
					var key: Vector2i = Vector2i(cx, cy)
					if not _road_grid.has(key):
						_road_grid[key] = []
					(_road_grid[key] as Array).append([points[index], points[index + 1], half, index == 0, index == points.size() - 2, str(road["name"])])


## How far inside a carriageway the point lies, in metres (negative: that far outside the nearest one).
func _road_depth(p: Vector2, named: Array = []) -> float:
	var key: Vector2i = Vector2i(floori(p.x / 16.0), floori(p.y / 16.0))
	var best: float = -99.0
	if not _road_grid.has(key):
		return best
	for seg: Array in _road_grid[key]:
		# A street ends square at its last point: nothing past that end is carriageway.
		var along: float = (p - (seg[0] as Vector2)).dot((seg[1] as Vector2) - (seg[0] as Vector2))
		var length: float = ((seg[1] as Vector2) - (seg[0] as Vector2)).length()
		if (along < 0.6 * length and bool(seg[3])) or (along > (length - 0.6) * length and bool(seg[4])):
			continue
		var depth: float = float(seg[2]) - p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]))
		if depth > best:
			best = depth
			named.assign([seg[5]])
	return best


## Every box or cylinder collider in the world as {points (x/z outline samples), top (y), name}.
func _solid_shapes() -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if not node is StaticBody3D:
			continue
		for child: Node in node.get_children():
			if not child is CollisionShape3D or (child as CollisionShape3D).shape == null or (child as CollisionShape3D).disabled:
				continue
			var xf: Transform3D = (child as Node3D).global_transform
			var shape: Shape3D = (child as CollisionShape3D).shape
			var points: Array[Vector2] = []
			var top: float = xf.origin.y
			if shape is BoxShape3D:
				var half: Vector3 = (shape as BoxShape3D).size * 0.5
				top += half.y
				for sx: float in [-1.0, 0.0, 1.0]:
					for sz: float in [-1.0, 0.0, 1.0]:
						var at: Vector3 = xf * Vector3(sx * half.x, 0.0, sz * half.z)
						points.append(Vector2(at.x, at.z))
			elif shape is CylinderShape3D:
				var cyl: CylinderShape3D = shape as CylinderShape3D
				top += cyl.height * 0.5
				points.append(Vector2(xf.origin.x, xf.origin.z))
				for step: int in range(8):
					var ring: Vector2 = Vector2.RIGHT.rotated(step * PI * 0.25) * cyl.radius
					points.append(Vector2(xf.origin.x + ring.x, xf.origin.z + ring.y))
			else:
				continue
			shapes.append({"points": points, "top": top, "name": str((node as Node).get_path()), "size": (shape as BoxShape3D).size if shape is BoxShape3D else Vector3.ZERO, "at": xf.origin})
	return shapes


## No solid prop (a collider whose top stands 0.4 m or more above the road) may intrude more than 0.6 m into a
## carriageway: junction mouths, dead-end streets and carved lanes included. Bridge decks and their
## rails are the road itself and are skipped.
func _road_solid_checks() -> void:
	var offenders: Array[String] = []
	var tested: int = 0
	for shape: Dictionary in _solid_shapes():
		if float(shape["top"]) < 0.4:
			continue
		var points: Array[Vector2] = shape["points"]
		var near_bridge: bool = false
		for bridge: Dictionary in world.bridges:
			if (bridge["rect"] as Rect2).grow(4.0).has_point(points[4] if points.size() > 4 else points[0]):
				near_bridge = true
		if near_bridge:
			continue
		tested += 1
		var deepest: float = 0.0
		var deep_at: Vector2 = Vector2.ZERO
		var road_name: Array = []
		for point: Vector2 in points:
			var probe: Array = []
			var depth: float = _road_depth(point, probe)
			if depth > deepest:
				deepest = depth
				deep_at = point
				road_name = probe
		# A wall or building edge may touch the kerb line (0.6 m) without standing in the carriageway.
		if deepest > 0.6:
			offenders.append("%5.2f m deep at (%.1f, %.1f) top %.2f on %s: box %s at %s %s" % [deepest, deep_at.x, deep_at.y, float(shape["top"]), road_name, shape["size"], shape["at"], shape["name"]])
	offenders.sort()
	offenders.reverse()
	for line: String in offenders:
		if not "/Calm" in line:
			print("  ON ROAD " + line)
	print("ROAD SOLIDS: %d solid props tested, %d stand on a carriageway" % [tested, offenders.size()])
	_check(tested > 500 and offenders.is_empty(), "No solid prop stands on a road carriageway (%d of %d tested)" % [offenders.size(), tested])


## The physics version of the same claim, over the whole road network: a 1 m box (0.3 m to 5.0 m above the road, a truck's clearance) is
## queried on a 1 m grid over every carriageway, 0.75 m inside the kerb line (so the box cannot reach past it): everything a car,
## a truck or a walker could meet ( any shape, any prefab, any authored prop or fill prop, not just the colliders the outline test
## samples). Bridge decks are the road itself and skipped; parked vehicles (CharacterBody3D) are counted apart.
func _road_sweep() -> void:
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(1.0, 4.7, 1.0)
	var seen: Dictionary = {}
	var found: Dictionary = {}
	var vehicles: Dictionary = {}
	var probes: int = 0
	for road: Dictionary in world.roads:
		var points: PackedVector2Array = road["points"]
		var half: float = float(road["width"]) * 0.5
		for index: int in range(points.size() - 1):
			var a: Vector2 = points[index]
			var b: Vector2 = points[index + 1]
			var length: float = a.distance_to(b)
			if length < 0.1:
				continue
			var along: Vector2 = (b - a) / length
			var across: Vector2 = Vector2(-along.y, along.x)
			var step: int = 0
			while float(step) <= length:
				var centre: Vector2 = a + along * float(step)
				step += 1
				var lateral: float = -half
				while lateral <= half:
					var p: Vector2 = centre + across * lateral
					lateral += 1.0
					var key: Vector2i = Vector2i(roundi(p.x), roundi(p.y))
					if seen.has(key) or _road_depth(p) < 0.75:
						continue
					seen[key] = true
					var on_bridge: bool = false
					for bridge: Dictionary in world.bridges:
						on_bridge = on_bridge or (bridge["rect"] as Rect2).grow(3.0).has_point(p)
					if on_bridge:
						continue
					var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
					query.shape = shape
					query.collision_mask = 1
					query.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, 2.65, p.y))
					probes += 1
					for hit: Dictionary in space.intersect_shape(query, 4):
						var body: Node = hit["collider"]
						var record: Dictionary = vehicles if body is CharacterBody3D else found
						if not record.has(body.get_instance_id()):
							record[body.get_instance_id()] = "%s at %s (%s, road %s)" % [body.get_path(), (body as Node3D).global_position.snapped(Vector3(0.1, 0.1, 0.1)), p.snapped(Vector2(0.1, 0.1)), road["name"]]
	var lines: Array = found.values()
	lines.sort()
	for line: String in lines.slice(0, 40):
		print("  IN ROAD " + str(line))
	print("ROAD SWEEP: %d carriageway probes, %d solid bodies in the road, %d parked vehicles in the road" % [probes, found.size(), vehicles.size()])
	for line: String in (vehicles.values() as Array).slice(0, 10):
		print("  VEHICLE IN ROAD " + str(line))
	_check(probes > 20000 and found.is_empty(), "A sweep of every carriageway finds nothing solid (%d bodies in %d probes)" % [found.size(), probes])


# --- Life ------------------------------------------------------------------------------------------------

func _life_checks() -> void:
	var fill: Variant = world.city_fill
	print("LIFE: %d parked cars added (total %d), %d sidewalk props, %d laundry lines" % [fill.cars_added, world.parked_vehicles.size(), fill.props_added, fill.lines_added])
	_check(fill.cars_added >= 10 and fill.lines_added >= 5 and fill.props_added >= 20, "The fill lots have life: cars %d, props %d, laundry lines %d" % [fill.cars_added, fill.props_added, fill.lines_added])


# --- No overlaps ------------------------------------------------------------------------------------------

func _overlaps() -> void:
	var clashes: Array[String] = []
	var polys: Array[PackedVector2Array] = world.footprint_polys
	for a: int in range(polys.size()):
		var box_a: Rect2 = world.footprints[a]
		for b: int in range(a + 1, polys.size()):
			if not box_a.intersects(world.footprints[b]):
				continue
			# Buildings of one record (a plot's wings, a prefab's porch) may touch each other.
			var same: bool = false
			for record: Dictionary in world.buildings:
				if (record["footprints"] as Array).has(a) and (record["footprints"] as Array).has(b):
					same = true
					break
			if same:
				continue
			var shared: Array[PackedVector2Array] = Geometry2D.intersect_polygons(polys[a], polys[b])
			for piece: PackedVector2Array in shared:
				var area: float = 0.0
				for index: int in range(piece.size()):
					area += piece[index].cross(piece[(index + 1) % piece.size()])
				if absf(area) * 0.5 > 0.5:
					clashes.append("%d/%d at %s" % [a, b, str(polys[a][0])])
					break
	for line: String in clashes.slice(0, 12):
		print("  OVERLAP " + line)
	print("OVERLAPS: %d overlapping footprint pairs" % clashes.size())
	if ASSERT_TARGETS:
		_check(clashes.is_empty(), "No two building footprints overlap (%d pairs)" % clashes.size())
