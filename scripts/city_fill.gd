extends RefCounted
## Map 0.8 fill pass: street-frontage infill for the whole city. Runs after every hand-authored
## builder and the plots, before city_detail.gd's clutter. It walks every long straight road (both
## sides, in road order, so the result is deterministic) and lays lots along the frontage: a paved
## apron and a building (an enterable prefab from scripts/buildings/prefabs.gd, or a solid shell where
## no prefab fits), with a 5 m ALLEY cut through the row every few lots. A lot is only built where it
## is clear of every road, footprint, hand-placed prop or yard (`world._blockers`), park, parked car
## and slab edge, and of the coast, so nothing overlaps and nothing is buried.
## Every building here is a record in `world.buildings` (enterable or solid).
## No AI, no RNG drawn from the world's main stream: the pass has its own seeded generator.
const CityDetail = preload("res://scripts/city_detail.gd")
const PREFABS_PATH: String = "res://scripts/buildings/prefabs.gd"
const SEED: int = 8081999
## Kerb-to-building setback (a 3.4 m sidewalk), lot gaps, alley width.
const SETBACK: float = 3.4
## Coast rows: an 8 m promenade between the quay rail and the lot, and how close a lot may come to the water.
const PROMENADE: float = 8.0
const PARTY_GAP: float = 0.8
## Kinds with a side door need a 3.4 m gap to their neighbours; the others sit party-wall to party-wall.
const WIDE_KINDS: PackedStringArray = ["warehouse", "auto_shop", "church_hall", "bar"]
const WIDE_GAP: float = 3.4
const ALLEY: float = 5.0
const CELL: float = 16.0
## Fallback lot sizes when a prefab kind has no size of its own: {kind: [min frontage, max frontage, min depth, max depth, floors min, floors max]}.
const SIZES: Dictionary = {
	"corner_store": [9.0, 12.0, 10.0, 13.0, 1, 2],
	"row_shop": [7.0, 11.0, 11.0, 15.0, 2, 3],
	"walkup": [10.0, 15.0, 12.0, 16.0, 3, 5],
	"warehouse": [16.0, 28.0, 14.0, 22.0, 1, 2],
	"office": [16.0, 22.0, 16.0, 20.0, 2, 4],
	"bar": [10.0, 14.0, 12.0, 15.0, 1, 2],
	"auto_shop": [12.0, 18.0, 13.0, 18.0, 1, 1],
	"church_hall": [10.0, 14.0, 16.0, 20.0, 1, 1],
	"diner_small": [10.0, 14.0, 10.0, 13.0, 1, 1],
}
## What each district builds, as [kind, weight].
const KINDS: Dictionary = {
	"MIDTOWN": [["row_shop", 3], ["office", 3], ["walkup", 2], ["bar", 1], ["corner_store", 1], ["diner_small", 1]],
	"LANTERN ROW": [["bar", 3], ["row_shop", 3], ["walkup", 2], ["corner_store", 1]],
	"SOLANA HEIGHTS": [["row_shop", 3], ["walkup", 3], ["corner_store", 1], ["bar", 1], ["church_hall", 1]],
	"KINGSWAY": [["walkup", 5], ["corner_store", 2], ["row_shop", 1]],
	"MORRIS PARK": [["walkup", 4], ["row_shop", 2], ["bar", 1], ["corner_store", 1], ["church_hall", 1]],
	"THE HARBOR": [["warehouse", 5]],
	"CANAL MARKET": [["row_shop", 3], ["warehouse", 2], ["corner_store", 1]],
	"UNION STATION": [["row_shop", 2], ["office", 2], ["bar", 1], ["corner_store", 1]],
	"THE STRIP": [["bar", 3], ["row_shop", 2], ["office", 1], ["diner_small", 2]],
	"EASTGATE": [["office", 4], ["row_shop", 1]],
	"UPTOWN": [["office", 6], ["bar", 1]],
	"MOTOR MILE": [["auto_shop", 4], ["warehouse", 2], ["corner_store", 1], ["diner_small", 1]],
	"NIGHTLIFE": [["bar", 4], ["row_shop", 2], ["office", 2], ["diner_small", 1]],
	"WEST END": [["walkup", 4], ["row_shop", 2], ["corner_store", 1]],
	"OLD TOWN": [["walkup", 3], ["row_shop", 3], ["corner_store", 1], ["bar", 1], ["church_hall", 1]],
	"SLIP SIDE": [["warehouse", 4], ["auto_shop", 1]],
	"OLD WHARF": [["warehouse", 5], ["auto_shop", 1]],
	"EAST SHORE": [["row_shop", 1], ["corner_store", 1], ["walkup", 1]],
	"SOUTH DOCKS": [["warehouse", 5], ["auto_shop", 1]],
	"NORTH BLUFF": [["walkup", 2], ["row_shop", 1]],
	"WEST BANK": [["row_shop", 2], ["walkup", 2], ["office", 1]],
	"PORT HALCYON": [["row_shop", 1], ["walkup", 1], ["warehouse", 1]],
}
## Wall colours and textures by district family.
const BRICK: Array[Color] = [Color(0.56, 0.3, 0.24), Color(0.62, 0.38, 0.28), Color(0.5, 0.27, 0.25), Color(0.66, 0.46, 0.34), Color(0.58, 0.33, 0.27)]
const STUCCO: Array[Color] = [Color(0.93, 0.74, 0.58), Color(0.62, 0.8, 0.78), Color(0.92, 0.86, 0.7), Color(0.86, 0.6, 0.55), Color(0.75, 0.82, 0.62)]
const CONCRETE: Array[Color] = [Color(0.58, 0.58, 0.56), Color(0.5, 0.52, 0.5), Color(0.44, 0.46, 0.5), Color(0.62, 0.6, 0.55)]
const METAL: Array[Color] = [Color(0.5, 0.52, 0.5), Color(0.42, 0.46, 0.5), Color(0.55, 0.5, 0.42), Color(0.36, 0.42, 0.4)]
const DARK: Array[Color] = [Color(0.16, 0.14, 0.2), Color(0.2, 0.16, 0.24), Color(0.12, 0.14, 0.2), Color(0.24, 0.16, 0.2)]
const SURNAMES: Array[String] = ["ORTEGA", "NOVAK", "HALLORAN", "NAKAMURA", "OKAFOR", "BRENNAN", "SANTORO", "KOWALSKI", "LINDQVIST", "MARLOW", "ABERNATHY", "DELACROIX", "PETROV", "IBARRA", "FAIRWEATHER", "TANAKA", "GALLAGHER", "MOREAU", "VASQUEZ", "HOLLIS", "ZIELINSKI", "OYELARAN", "CASSIDY", "BERGSTROM", "RAMIREZ", "QUINLAN", "DUBOIS", "PALMER", "ROSSETTI", "KAPLAN", "SUTHERLAND", "MENDEZ", "TREMBLAY", "OLSEN", "HARGROVE", "CHEN", "LOMBARDI", "PARKER", "WHITAKER", "DIAZ"]
const TRADES: Dictionary = {
	"corner_store": ["CORNER MARKET", "GROCERY", "SMOKES & PAPERS", "LIQUOR & DELI", "24 HR MART", "BODEGA"],
	"row_shop": ["HARDWARE", "TAILOR", "PHARMACY", "BAKERY", "SHOE REPAIR", "RECORDS", "FLORIST", "BARBER", "BOOKS", "OPTICAL", "PHOTO", "LAUNDRY", "PIZZA", "NOODLES", "TV REPAIR", "VIDEO RENTAL"],
	"walkup": ["APARTMENTS", "ROOMS", "FLATS", "RESIDENCE", "COURT"],
	"warehouse": ["CARGO", "FREIGHT", "COLD STORE", "SHIPPING", "SUPPLY", "TIMBER", "SALVAGE", "DISTRIBUTION"],
	"office": ["INSURANCE", "LAW OFFICES", "REALTY", "ACCOUNTING", "TRAVEL", "DENTAL", "TRUST", "CLINIC", "EMPLOYMENT", "SURVEYORS"],
	"bar": ["TAVERN", "LOUNGE", "PUB", "CLUB", "BAR", "TAP ROOM", "CANTINA"],
	"auto_shop": ["AUTO", "GARAGE", "TIRE & LUBE", "BODY SHOP", "MOTORS", "SMOG CHECK"],
	"church_hall": ["PARISH HALL", "COMMUNITY HALL", "MISSION", "CHAPEL"],
	"diner_small": ["DINER", "COFFEE SHOP", "LUNCHEONETTE", "GRILL"],
}
const SIGN_COLORS: Array[Color] = [Color(1.0, 0.85, 0.55), Color(0.95, 0.5, 0.4), Color(0.5, 0.9, 1.0), Color(0.6, 1.0, 0.6), Color(1.0, 0.6, 0.85)]

var w: Node3D
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var prefabs: Variant = null
## Uniform grids (CELL m): footprints, props and yards; road segments; slab tops; parked cars.
var _rects: Dictionary = {}
var _obbs: Dictionary = {}
var _zones: Dictionary = {}
var _segs: Dictionary = {}
var _slabs: Dictionary = {}
var _keepout: Array[PackedVector2Array] = []
var _used_signs: Dictionary = {}
var _cells: Dictionary = {}
## Stats for the tests: lots built by kind, prefab and solid.
var placed: Array[Dictionary] = []
var alleys: Array[Dictionary] = []
var _sign_index: int = 0


func _init(world: Node3D) -> void:
	w = world
	rng.seed = SEED
	prefabs = w._prefab_library()


func build() -> void:
	w._blockers_off = true
	_index()
	for road_index: int in range(w.roads.size()):
		_frontage(road_index)
	_coast_frontage()
	_dress_alleys()
	_calming()
	_far_massing()
	for key: Vector3i in _calm_cells:
		var calm: Node3D = _calm_cells[key]
		w._finish(calm)
		for child: Node in calm.get_children():
			if child is GeometryInstance3D and not child is Label3D:
				(child as GeometryInstance3D).visibility_range_end = 260.0
				(child as GeometryInstance3D).visibility_range_end_margin = 10.0
	for key: Vector3i in _cells:
		var node: Node3D = _cells[key]
		w._finish(node)
		for child: Node in node.get_children():
			if child is GeometryInstance3D and not child is Label3D:
				(child as GeometryInstance3D).visibility_range_end = w.NEAR_RANGE
				(child as GeometryInstance3D).visibility_range_end_margin = 6.0
				w._detail_ranges.append(child)
	w._blockers_off = false
	w._xf = Transform3D.IDENTITY
	w._xf_yaw = 0.0


# --- Spatial index -----------------------------------------------------------------------------

func _key(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


## Rects that stop a 1.3 m line of sight (buildings, walls, tall props), for the chicane planner.
var _eye: Dictionary = {}

func _add_eye(rect: Rect2) -> void:
	var low: Vector2i = _key(rect.position)
	var high: Vector2i = _key(rect.end)
	for cx: int in range(low.x, high.x + 1):
		for cy: int in range(low.y, high.y + 1):
			var key: Vector2i = Vector2i(cx, cy)
			if not _eye.has(key):
				_eye[key] = []
			(_eye[key] as Array).append(rect)


func _add_rect(rect: Rect2) -> void:
	var low: Vector2i = _key(rect.position)
	var high: Vector2i = _key(rect.end)
	for cx: int in range(low.x, high.x + 1):
		for cy: int in range(low.y, high.y + 1):
			var key: Vector2i = Vector2i(cx, cy)
			if not _rects.has(key):
				_rects[key] = []
			(_rects[key] as Array).append(rect)


func _index() -> void:
	for rect: Rect2 in w.footprints:
		_add_rect(rect.grow(1.2))
	for rect: Rect2 in w._blockers:
		_add_rect(rect.grow(0.6))
	for rect: Rect2 in w.eye_blockers:
		_add_eye(rect)
	for rect: Rect2 in w.footprints:
		_add_eye(rect)
	for vehicle: Dictionary in w.parked_vehicles:
		var at: Vector3 = vehicle["at"]
		_add_rect(Rect2(at.x - 3.6, at.z - 3.6, 7.2, 7.2))
	# Parks, plazas and the public spaces city_detail.gd dresses later.
	for poly: PackedVector2Array in w.plazas:
		_keepout.append(poly)
	for spec: Dictionary in CityDetail.SITES:
		var rect: Rect2 = (spec["rect"] as Rect2).grow(2.0)
		_keepout.append(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]))
	# The gun club's range yard and long-range lanes, the beach and pier, Sunset Park.
	for rect: Rect2 in [Rect2(285, -104, 130, 84), Rect2(236, 22, 96, 76)]:
		_keepout.append(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]))
	_keepout.append(w.BEACH)
	for poly: PackedVector2Array in _keepout:
		var bounds: Rect2 = Rect2(poly[0], Vector2.ZERO)
		for point: Vector2 in poly:
			bounds = bounds.expand(point)
		_add_keepout_bounds(bounds)
	for road_index: int in range(w.roads.size()):
		var road: Dictionary = w.roads[road_index]
		var points: PackedVector2Array = road["points"]
		var half: float = float(road["width"]) * 0.5 + 3.0
		for index: int in range(points.size() - 1):
			var a: Vector2 = points[index]
			var b: Vector2 = points[index + 1]
			var box: Rect2 = Rect2(a, Vector2.ZERO).expand(b).grow(half)
			var low: Vector2i = _key(box.position)
			var high: Vector2i = _key(box.end)
			for cx: int in range(low.x, high.x + 1):
				for cy: int in range(low.y, high.y + 1):
					var key: Vector2i = Vector2i(cx, cy)
					if not _segs.has(key):
						_segs[key] = []
					(_segs[key] as Array).append([a, b, half - 3.0, road_index])
	for slab: Dictionary in w._slab_tops:
		var poly: PackedVector2Array = slab["poly"]
		var bounds: Rect2 = Rect2(poly[0], Vector2.ZERO)
		for point: Vector2 in poly:
			bounds = bounds.expand(point)
		var low: Vector2i = _key(bounds.position)
		var high: Vector2i = _key(bounds.end)
		for cx: int in range(low.x, high.x + 1):
			for cy: int in range(low.y, high.y + 1):
				var key: Vector2i = Vector2i(cx, cy)
				if not _slabs.has(key):
					_slabs[key] = []
				(_slabs[key] as Array).append([bounds, poly, float(slab["height"])])


## Keep-out polygons are tested by bounds first: they go in the rect grid as marked entries.
var _keepout_bounds: Array[Rect2] = []

func _add_keepout_bounds(bounds: Rect2) -> void:
	_keepout_bounds.append(bounds)


## Walking-surface height from the slab index (0 on open ground).
func _height_at(p: Vector2) -> float:
	var best: float = 0.0
	var key: Vector2i = _key(p)
	if not _slabs.has(key):
		return 0.0
	for entry: Array in _slabs[key]:
		if float(entry[2]) > best and (entry[0] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, entry[1]):
			best = float(entry[2])
	return best


# --- Lot tests ---------------------------------------------------------------------------------

## The four corners of an oriented lot: centre, unit vectors along the frontage (u) and toward the
## back (v), half frontage and half depth.
func _corners(center: Vector2, u: Vector2, v: Vector2, hw: float, hd: float) -> PackedVector2Array:
	return PackedVector2Array([center - u * hw - v * hd, center + u * hw - v * hd, center + u * hw + v * hd, center - u * hw + v * hd])


func _bounds(poly: PackedVector2Array) -> Rect2:
	var box: Rect2 = Rect2(poly[0], Vector2.ZERO)
	for point: Vector2 in poly:
		box = box.expand(point)
	return box


## Registers a built lot (oriented, grown by half a party gap) so later lots keep clear of it.
func _add_obb(center: Vector2, u: Vector2, v: Vector2, hw: float, hd: float) -> void:
	# The 3 m behind a lot (its rear doors and yard) is reserved too: no lot may be built into it.
	_register_obb(_zones, center + v * (hd + 1.5), u, v, hw, 1.5)
	_register_obb(_obbs, center, u, v, hw, hd)


func _register_obb(into: Dictionary, center: Vector2, u: Vector2, v: Vector2, hw: float, hd: float) -> void:
	var box: Rect2 = _bounds(_corners(center, u, v, hw, hd))
	var low: Vector2i = _key(box.position)
	var high: Vector2i = _key(box.end)
	for cx: int in range(low.x, high.x + 1):
		for cy: int in range(low.y, high.y + 1):
			var key: Vector2i = Vector2i(cx, cy)
			if not into.has(key):
				into[key] = []
			(into[key] as Array).append([center, u, v, hw, hd])


## Separating axis test between two oriented rectangles ([centre, u, v, hw, hd]).
func _obb_pair(center: Vector2, u: Vector2, v: Vector2, hw: float, hd: float, other: Array) -> bool:
	var oc: Vector2 = other[0]
	var ou: Vector2 = other[1]
	var ov: Vector2 = other[2]
	var ow: float = other[3]
	var od: float = other[4]
	var d: Vector2 = oc - center
	for axis: Vector2 in [u, v, ou, ov]:
		var reach: float = absf(u.dot(axis)) * hw + absf(v.dot(axis)) * hd + absf(ou.dot(axis)) * ow + absf(ov.dot(axis)) * od
		if absf(d.dot(axis)) > reach:
			return false
	return true


## True if the oriented rectangle overlaps an axis-aligned rectangle (separating axis test).
func _obb_hits(center: Vector2, u: Vector2, v: Vector2, hw: float, hd: float, rect: Rect2) -> bool:
	var rc: Vector2 = rect.get_center()
	var rh: Vector2 = rect.size * 0.5
	var d: Vector2 = rc - center
	if absf(d.x) > rh.x + absf(u.x) * hw + absf(v.x) * hd:
		return false
	if absf(d.y) > rh.y + absf(u.y) * hw + absf(v.y) * hd:
		return false
	if absf(d.dot(u)) > hw + absf(u.x) * rh.x + absf(u.y) * rh.y:
		return false
	if absf(d.dot(v)) > hd + absf(v.x) * rh.x + absf(v.y) * rh.y:
		return false
	return true


func _dist_segment_lot(a: Vector2, b: Vector2, center: Vector2, u: Vector2, v: Vector2, hw: float, hd: float) -> float:
	var la: Vector2 = Vector2((a - center).dot(u), (a - center).dot(v))
	var lb: Vector2 = Vector2((b - center).dot(u), (b - center).dot(v))
	if (absf(la.x) <= hw and absf(la.y) <= hd) or (absf(lb.x) <= hw and absf(lb.y) <= hd):
		return 0.0
	var corners: Array[Vector2] = [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]
	var best: float = INF
	for index: int in range(4):
		var pair: PackedVector2Array = Geometry2D.get_closest_points_between_segments(la, lb, corners[index], corners[(index + 1) % 4])
		best = minf(best, pair[0].distance_to(pair[1]))
	return best


var fail_reasons: Dictionary = {}
var _alley_props: Array[Dictionary] = []
var _setback: float = SETBACK
var _coast_gap: float = 8.0
var _apron_front: float = 0.0

var fail_log: Array = []
var _last_reason: String = ""

func _why(reason: String) -> void:
	_last_reason = reason
	fail_reasons[reason] = int(fail_reasons.get(reason, 0)) + 1


## Can a lot of this size stand here? `own` is the road it fronts (its own kerb gap is the setback).
func _clear(center: Vector2, u: Vector2, v: Vector2, fw: float, dp: float, extra: float = 0.0) -> bool:
	var hw: float = fw * 0.5 + extra
	var hd: float = dp * 0.5 + extra
	var poly: PackedVector2Array = _corners(center, u, v, hw + 1.0, hd + 1.0)
	for point: Vector2 in poly:
		if not w._on_land(point):
			_why("land")
			return false
		# 8 m off the coast: quay walks and rails stay open.
		for angle: int in range(0, 8):
			var probe: Vector2 = point + Vector2.RIGHT.rotated(angle * PI * 0.25) * _coast_gap
			if not w._on_land(probe):
				_why("coast")
				return false
	var box: Rect2 = _bounds(poly).grow(1.0)
	var low: Vector2i = _key(box.position)
	var high: Vector2i = _key(box.end)
	var seen_rects: Dictionary = {}
	for cx: int in range(low.x, high.x + 1):
		for cy: int in range(low.y, high.y + 1):
			var key: Vector2i = Vector2i(cx, cy)
			if _rects.has(key):
				for rect: Rect2 in _rects[key]:
					if box.intersects(rect) and _obb_hits(center, u, v, hw, hd, rect):
						_why("rect")
						return false
			if _obbs.has(key):
				for other: Array in _obbs[key]:
					if _obb_pair(center, u, v, hw + 0.3, hd + 0.3, other):
						_why("lot")
						return false
			if _zones.has(key):
				for other: Array in _zones[key]:
					if _obb_pair(center, u, v, hw, hd, other):
						_why("rear")
						return false
			if _segs.has(key):
				for seg: Array in _segs[key]:
					var gap: float = _dist_segment_lot(seg[0], seg[1], center, u, v, hw, hd)
					if gap < float(seg[2]) + 2.6:
						_why("road")
						return false
	for index: int in range(_keepout.size()):
		if box.intersects(_keepout_bounds[index]) and not Geometry2D.intersect_polygons(poly, _keepout[index]).is_empty():
			_why("park")
			return false
	# Front doorway zone free of street furniture; a 3 m strip behind the lot free of other lots (rear doors).
	var columns: int = maxi(2, ceili(2.0 * hw / 1.6))
	for column: int in range(columns + 1):
		var lateral: float = -hw + 2.0 * hw * float(column) / float(columns)
		for reach: float in [0.5, 1.5, 2.5, 3.3]:
			if w.solid_near(center - v * (hd + reach) + u * lateral, 0.5):
				_why("furniture")
				return false
	var rear: Array = [center + v * (hd + 1.6), u, v, hw, 1.6]
	var rear_box: Rect2 = _bounds(_corners(rear[0], u, v, hw, 1.6))
	for key: Vector2i in [_key(rear[0]), _key(center + v * (hd + 0.4)), _key(center + v * (hd + 2.8))]:
		if _rects.has(key):
			for rect: Rect2 in _rects[key]:
				if rear_box.intersects(rect) and _obb_hits(rear[0], u, v, hw, 1.6, rect):
					_why("rear")
					return false
	for key: Vector2i in [_key(rear[0]), _key(center + v * (hd + 0.4)), _key(center + v * (hd + 2.8))]:
		if _obbs.has(key):
			for other: Array in _obbs[key]:
				if _obb_pair(rear[0], u, v, hw, 1.6, other):
					_why("rear")
					return false
	# Not straddling a slab edge: the whole lot (and its apron) is on one surface height.
	var height: float = _height_at(center)
	for point: Vector2 in _corners(center, u, v, hw + 0.6, hd + 0.6):
		if absf(_height_at(point) - height) > 0.02:
			_why("slab")
			return false
	for mid: Vector2 in [center - u * hw, center + u * hw, center - v * hd, center + v * hd]:
		if absf(_height_at(mid) - height) > 0.02:
			return false
	return true


# --- Frontage ----------------------------------------------------------------------------------

func _pick_kind(district: String) -> String:
	var table: Array = KINDS.get(district, KINDS["PORT HALCYON"])
	var total: int = 0
	for entry: Array in table:
		total += int(entry[1])
	var roll: int = rng.randi() % total
	for entry: Array in table:
		roll -= int(entry[1])
		if roll < 0:
			return str(entry[0])
	return str((table[0] as Array)[0])


## Lot size limits for a kind (a prefab library's own numbers win where it has them).
func _limits(kind: String) -> Array:
	var spec: Array = SIZES.get(kind, SIZES["row_shop"])
	var limits: Array = spec.duplicate()
	if prefabs != null:
		var minimum: Vector2 = prefabs.min_size(kind)
		limits[0] = maxf(float(limits[0]), minimum.x)
		limits[2] = maxf(float(limits[2]), minimum.y)
		limits[1] = maxf(float(limits[1]), float(limits[0]) + 2.0)
		limits[3] = maxf(float(limits[3]), float(limits[2]) + 2.0)
		limits[5] = mini(int(limits[5]), int(prefabs.max_floors(kind)))
		limits[4] = mini(int(limits[4]), int(limits[5]))
	return limits


## Waterfront rows: lots along the quay facing the sea over an 8 m promenade (buildings, bars and
## warehouses with their backs to the land), so the rim of the island is not bare ground.
func _coast_frontage() -> void:
	_setback = PROMENADE
	_coast_gap = 5.0
	_apron_front = 1.0
	var mainland: PackedVector2Array = w.land[0]
	for index: int in range(mainland.size()):
		var a: Vector2 = mainland[index]
		var b: Vector2 = mainland[(index + 1) % mainland.size()]
		var length: float = a.distance_to(b)
		if length < 18.0:
			continue
		var dir: Vector2 = (b - a) / length
		var mid: Vector2 = (a + b) * 0.5
		var inward: float = 1.0 if w._on_land(mid + Vector2(-dir.y, dir.x) * 6.0) else -1.0
		if not w._on_land(mid + Vector2(-dir.y, dir.x) * inward * 6.0):
			continue
		_run(a, dir, length, 0.0, inward)
	_setback = SETBACK
	_coast_gap = 8.0
	_apron_front = 0.0


func _frontage(road_index: int) -> void:
	var road: Dictionary = w.roads[road_index]
	var points: PackedVector2Array = road["points"]
	var half: float = float(road["width"]) * 0.5
	for index: int in range(points.size() - 1):
		var a: Vector2 = points[index]
		var b: Vector2 = points[index + 1]
		var length: float = a.distance_to(b)
		if length < 18.0:
			continue
		var dir: Vector2 = (b - a) / length
		for side: float in [1.0, -1.0]:
			_run(a, dir, length, half, side)


func _run(a: Vector2, dir: Vector2, length: float, half: float, side: float) -> void:
	var normal: Vector2 = Vector2(-dir.y, dir.x) * side
	# Lots stand on the far side of the sidewalk; `back` points away from the road.
	var back: Vector2 = normal
	var front: Vector2 = -normal
	var t: float = 2.0
	var since_alley: int = 0
	var run_start: float = -1.0
	var last_gap: float = 99.0
	var last_wide: bool = false
	while t < length - 5.0:
		var probe: Vector2 = a + dir * (t + 6.0) + normal * (half + _setback + 6.0)
		var district: String = w.district_at(Vector3(probe.x, 0, probe.y))
		var kind: String = _pick_kind(district)
		var limits: Array = _limits(kind)
		# A wide-gap kind keeps 3.4 m from the lot before it (its side door).
		var wide: bool = WIDE_KINDS.has(kind)
		if run_start >= 0.0 and (wide or last_wide) and last_gap < WIDE_GAP:
			t += WIDE_GAP - last_gap
			last_gap = WIDE_GAP
		var free: float = length - 3.0 - t
		if free < float(limits[0]):
			break
		# The smallest lot first: if it does not fit here, slide on.
		if not _fits(a, dir, normal, half, t, float(limits[0]), float(limits[2])):
			fail_log.append([a + dir * (t + 3.0) + normal * (half + _setback + 5.0), _last_reason])
			t += 3.0
			if run_start >= 0.0:
				run_start = -1.0
				since_alley += 1
			continue
		var fw: float = minf(rng.randf_range(float(limits[0]), float(limits[1])), free)
		var dp: float = rng.randf_range(float(limits[2]), float(limits[3]))
		while fw > float(limits[0]) + 0.01 or dp > float(limits[2]) + 0.01:
			if _fits(a, dir, normal, half, t, fw, dp):
				break
			fw = maxf(float(limits[0]), fw - 2.0)
			dp = maxf(float(limits[2]), dp - 1.5)
		var center: Vector2 = a + dir * (t + fw * 0.5) + normal * (half + _setback + dp * 0.5)
		_build_lot(kind, district, center, dir, back, front, fw, dp, limits)
		if run_start < 0.0:
			run_start = t
		t += fw
		since_alley += 1
		last_wide = wide
		if since_alley >= 3 + rng.randi() % 3 or t - run_start > 58.0:
			_alley(a + dir * (t + ALLEY * 0.5) + normal * (half + _setback), dir, back, dp)
			t += ALLEY
			since_alley = 0
			run_start = -1.0
		else:
			t += PARTY_GAP
			last_gap = PARTY_GAP


func _fits(a: Vector2, dir: Vector2, normal: Vector2, half: float, t: float, fw: float, dp: float) -> bool:
	var center: Vector2 = a + dir * (t + fw * 0.5) + normal * (half + _setback + dp * 0.5)
	return _clear(center, dir, normal, fw, dp)


# --- Building a lot ------------------------------------------------------------------------------

func _cell_node(at: Vector2) -> Node3D:
	var key: Vector3i = Vector3i(floori(at.x / 64.0), floori(at.y / 64.0), 0)
	if not _cells.has(key):
		var saved: Node3D = w._target
		var node: Node3D = w._begin("Fill %d %d" % [key.x, key.y])
		w._target = saved
		_cells[key] = node
	return _cells[key] as Node3D


func _palette(kind: String, district: String) -> Array[Color]:
	match kind:
		"warehouse", "auto_shop":
			return METAL
		"bar":
			return DARK if district in ["NIGHTLIFE", "THE STRIP", "LANTERN ROW"] else BRICK
		"office":
			return CONCRETE
		"walkup", "row_shop", "corner_store":
			if district in ["SOLANA HEIGHTS", "EAST SHORE", "NORTH BLUFF"]:
				return STUCCO
			if district in ["KINGSWAY", "UNION STATION", "EASTGATE", "MIDTOWN"]:
				return CONCRETE if rng.randf() < 0.5 else BRICK
			return BRICK
	return CONCRETE


func _sign_for(kind: String) -> String:
	var trades: Array = TRADES[kind]
	for attempt: int in range(30):
		var text: String = "%s %s" % [SURNAMES[rng.randi() % SURNAMES.size()], trades[rng.randi() % trades.size()]]
		if kind == "walkup":
			text = "%s %s" % [SURNAMES[rng.randi() % SURNAMES.size()], trades[rng.randi() % trades.size()]]
		if not _used_signs.has(text):
			_used_signs[text] = true
			return text
	return str(trades[0])


func _texture(kind: String, color: Color) -> String:
	if kind in ["warehouse", "auto_shop"]:
		return "metal"
	return "brick" if color.r > color.b + 0.08 else "panel"


func _build_lot(kind: String, district: String, center: Vector2, u: Vector2, back: Vector2, front: Vector2, fw: float, dp: float, limits: Array) -> void:
	var palette: Array[Color] = _palette(kind, district)
	var color: Color = palette[rng.randi() % palette.size()]
	var floors: int = int(limits[4]) + (rng.randi() % maxi(1, int(limits[5]) - int(limits[4]) + 1))
	# Apron: a raised paved plinth under the lot and the sidewalk in front of it (skipped where the
	# lot already stands on a block plinth).
	var ground: float = _height_at(center)
	var lamp_wanted: bool = false
	if ground < 0.05:
		var apron_depth: float = dp + _setback - _apron_front + 1.0
		var apron_center: Vector2 = center - back * ((_setback - _apron_front) * 0.5 - 0.5)
		var yaw: float = atan2(-u.y, u.x)
		w._target = _cell_node(center)
		w._xf = Transform3D.IDENTITY
		w._xf_yaw = 0.0
		w._slab_rot(apron_center, Vector2(fw + 1.6, apron_depth), yaw, Color(0.5, 0.49, 0.45))
		ground = 0.16
		lamp_wanted = rng.randf() < 0.5
	var sign_text: String = _sign_for(kind)
	var record_before: int = w.buildings.size()
	var built: bool = false
	if prefabs != null and prefabs.kinds().has(kind):
		built = _prefab(kind, center, front, fw, dp, floors, color, sign_text, district)
	if not built:
		_solid_shell(kind, center, front, fw, dp, floors, color, sign_text)
	# A street lamp at the party-wall end of the sidewalk, never in front of a door.
	if lamp_wanted:
		var at: Vector2 = center + front * (dp * 0.5 + _setback - 1.3) + u * (fw * 0.5 + 0.1)
		if not w.door_within(at, 2.8) and not w.solid_near(at, 0.3):
			var toward: Vector3 = Vector3(front.x, 0, front.y)
			toward = Vector3(signf(toward.x), 0, 0) if absf(toward.x) > absf(toward.z) else Vector3(0, 0, signf(toward.z))
			w._target = _cell_node(center)
			w._xf = Transform3D.IDENTITY
			w._lamp(Vector3(at.x, 0.16, at.y), toward)
	_add_obb(center, u, back, fw * 0.5, dp * 0.5)
	placed.append({"kind": kind, "center": center, "front": front, "size": Vector2(fw, dp), "district": district, "prefab": built, "floors": floors})


func _prefab(kind: String, center: Vector2, front: Vector2, fw: float, dp: float, floors: int, color: Color, sign_text: String, district: String) -> bool:
	# Prefab frame: local -Z is the street front.
	var yaw: float = atan2(-front.x, -front.y)
	var style: Dictionary = {"palette": [color, color.lightened(0.35), color.darkened(0.35)], "sign": sign_text, "tex": _texture(kind, color), "lit": 0.3, "district": district}
	w._begin_building(kind, true, sign_text)
	var record: Dictionary = w._building_open
	w._xf = Transform3D.IDENTITY
	w._xf_yaw = 0.0
	var node: Variant = prefabs.build(w, kind, center, Vector2(fw, dp), yaw, floors, rng.randi(), style)
	w._end_building()
	w._xf = Transform3D.IDENTITY
	w._xf_yaw = 0.0
	if node == null:
		w.buildings.erase(record)
		return false
	if (record["footprints"] as Array).is_empty():
		_register_footprint(record, center, front, fw, dp)
	if not bool((node as Node3D).get_meta("enterable", true)):
		record["enterable"] = false
	w._finish(node as Node3D)
	w.limit_range(node as Node3D, w.NEAR_RANGE)
	w.lod_lots.append({"center": center, "size": Vector3(fw, 3.4 * floors + 1.2, dp), "yaw": atan2(front.x, front.y), "color": color})
	return true


## Records an oriented outline in footprint_polys / footprints and the building record.
func _register_footprint(record: Dictionary, center: Vector2, front: Vector2, fw: float, dp: float) -> void:
	var u: Vector2 = Vector2(front.y, -front.x)
	var poly: PackedVector2Array = _corners(center, u, -front, fw * 0.5, dp * 0.5)
	w.footprint_polys.append(poly)
	w.footprints.append(_bounds(poly))
	(record["footprints"] as Array).append(w.footprint_polys.size() - 1)


## A solid shell: a box with a plinth, roof, sign and windows on every face (the same look as `_tower`,
## but turned to the street). Not enterable.
func _solid_shell(kind: String, center: Vector2, front: Vector2, fw: float, dp: float, floors: int, color: Color, sign_text: String) -> void:
	var height: float = 3.4 * floors + 1.2
	var yaw: float = atan2(front.x, front.y)
	var node: Node3D = _cell_node(center)
	w._target = node
	w._xf = Transform3D.IDENTITY
	w._xf_yaw = 0.0
	var tex: String = _texture(kind, color)
	var record: Dictionary = {"name": sign_text, "kind": "solid", "enterable": false, "footprints": []}
	w.buildings.append(record)
	_register_footprint(record, center, front, fw, dp)
	var ground: float = _height_at(center)
	w._box_with(Vector3(center.x, ground + height * 0.5, center.y), Vector3(fw, height, dp), w._material(color, 0.9, tex), true, yaw)
	w._box_with(Vector3(center.x, ground + height + 0.16, center.y), Vector3(fw + 0.45, 0.32, dp + 0.45), w._material(Color(0.29, 0.31, 0.3), 0.9, "roof"), false, yaw)
	var basis: Basis = Basis(Vector3.UP, yaw)
	var glass: StandardMaterial3D = w._material(Color(0.16, 0.24, 0.29), 0.3)
	var warm: StandardMaterial3D = w._glow(Color(1.0, 0.78, 0.46), 1.3)
	for face: Vector3 in [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT]:
		var along_x: bool = absf(face.z) > 0.5
		var span: float = fw if along_x else dp
		var depth: float = dp if along_x else fw
		var columns: int = maxi(1, int(span / 3.4))
		for floor_index: int in range(floors):
			var y: float = 2.4 + float(floor_index) * 3.1
			if y + 1.0 > height:
				continue
			for column: int in range(columns):
				var t: float = -span * 0.5 + (column + 0.5) * span / columns
				var offset: Vector3 = (Vector3(t, 0, 0) if along_x else Vector3(0, 0, t)) + face * (depth * 0.5 + 0.045)
				var window_size: Vector3 = Vector3(1.55, 1.5, 0.1) if along_x else Vector3(0.1, 1.5, 1.55)
				var lit: bool = rng.randf() < 0.22 and floor_index > 0
				var at: Vector3 = Vector3(center.x, ground, center.y) + basis * (offset + Vector3(0, y, 0))
				w._box_with(at, window_size, warm if lit else glass, false, yaw)
	# Sign board over the front.
	var sign_at: Vector3 = Vector3(center.x + front.x * (dp * 0.5 + 0.3), ground + 4.3, center.y + front.y * (dp * 0.5 + 0.3))
	w._neon(sign_text, sign_at, yaw, SIGN_COLORS[rng.randi() % SIGN_COLORS.size()], clampi(int(fw * 4.2), 40, 80))
	w._roofs.append({"center": center, "size": Vector3(fw, height, dp), "yaw": yaw, "top": ground + height + 0.32, "front": Vector3(front.x, 0, front.y), "business": true})
	w.lod_lots.append({"center": center, "size": Vector3(fw, height + 0.3, dp), "yaw": yaw, "color": color})


# --- Far stand-ins ------------------------------------------------------------------------------

## One vertex-coloured mesh per 96 m cell holding every fill building's massing box (five faces, flat
## colour, no windows): beyond NEAR_RANGE the detailed shells and prefabs are culled and this single
## draw per cell takes over, so a long street costs a handful of calls instead of hundreds.
func _far_massing() -> void:
	var by_cell: Dictionary = {}
	for lot: Dictionary in w.lod_lots:
		var at: Vector2 = lot["center"]
		var key: Vector2i = Vector2i(floori(at.x / 96.0), floori(at.y / 96.0))
		if not by_cell.has(key):
			by_cell[key] = []
		(by_cell[key] as Array).append(lot)
	var material: StandardMaterial3D = w._material(Color.WHITE, 0.95)
	material = material.duplicate() as StandardMaterial3D
	material.vertex_color_use_as_albedo = true
	var keys: Array = by_cell.keys()
	keys.sort()
	for key: Vector2i in keys:
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for lot: Dictionary in by_cell[key]:
			_massing_box(tool, lot["center"], lot["size"], float(lot["yaw"]), lot["color"])
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.mesh = tool.commit()
		instance.material_override = material
		instance.name = "FarMassing %d %d" % [key.x, key.y]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_begin = w.NEAR_RANGE
		w.add_child(instance)


func _massing_box(tool: SurfaceTool, center: Vector2, size: Vector3, yaw: float, color: Color) -> void:
	var basis: Basis = Basis(Vector3.UP, yaw)
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	var corners: Array[Vector3] = []
	for y: float in [0.0, size.y]:
		for corner: Vector2 in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]:
			corners.append(Vector3(center.x, 0, center.y) + basis * Vector3(corner.x, y, corner.y))
	# Godot's front faces wind clockwise; the sides are shaded a little darker than the roof.
	var faces: Array = [[4, 7, 6, 5, 1.0], [0, 4, 5, 1, 0.8], [1, 5, 6, 2, 0.7], [2, 6, 7, 3, 0.8], [3, 7, 4, 0, 0.7]]
	for face: Array in faces:
		var shade: Color = color * float(face[4])
		shade.a = 1.0
		var normal: Vector3 = (corners[face[1]] - corners[face[0]]).cross(corners[face[2]] - corners[face[0]]).normalized()
		for index: int in [0, 2, 1, 0, 3, 2]:
			tool.set_color(shade)
			tool.set_normal(normal)
			tool.add_vertex(corners[face[index]])


# --- Alleys ----------------------------------------------------------------------------------------

## A 5 m alley between two lots: a dumpster and bags against one wall, a hydrant, a lamp at the
## street end. The middle 2.4 m stays clear. `at` is on the sidewalk line of the alley's mouth.
func _alley(at: Vector2, u: Vector2, back: Vector2, depth: float) -> void:
	alleys.append({"at": at, "dir": back, "width": ALLEY, "depth": depth})
	var node: Node3D = _cell_node(at)
	w._target = node
	w._xf = Transform3D.IDENTITY
	w._xf_yaw = 0.0
	var ground: float = _height_at(at + back * 3.0)
	# The alley floor is one paved plinth with the lot aprons either side (raised, so props stand on it).
	var yaw: float = atan2(-u.y, u.x)
	var floor_y: float = ground
	if ground < 0.05:
		var mid: Vector2 = at + back * ((depth + 1.0 - _setback) * 0.5)
		w._slab_rot(mid, Vector2(ALLEY + 1.6, depth + _setback + 1.0), yaw, Color(0.42, 0.41, 0.4), "asphalt")
		floor_y = 0.16
	var side: float = 1.0 if rng.randf() < 0.5 else -1.0
	var spot: Vector2 = at + back * (depth * 0.35) + u * side * (ALLEY * 0.5 - 1.05)
	_alley_props.append({"spot": spot, "u": u, "back": back, "side": side, "y": floor_y})


## Dumpsters and bags go in once every lot is built, so none stands at a side door.
func _dress_alleys() -> void:
	for prop: Dictionary in _alley_props:
		var spot: Vector2 = prop["spot"]
		var back: Vector2 = prop["back"]
		var u: Vector2 = prop["u"]
		var side: float = prop["side"]
		if w.door_within(spot, 3.6) or w.door_within(spot + back * 2.4, 2.6) or w.solid_near(spot, 1.4):
			continue
		w._target = _cell_node(spot)
		w._xf = Transform3D.IDENTITY
		w._xf_yaw = 0.0
		w._dumpster(Vector3(spot.x, float(prop["y"]), spot.y), atan2(-u.x * side, -u.y * side), Color(0.2, 0.33, 0.26))
		if not w.door_within(spot + back * 2.4, 2.6):
			w._trash_bags(Vector3(spot.x + back.x * 2.4, float(prop["y"]), spot.y + back.y * 2.4))


# --- Traffic calming: staggered kerb islands -------------------------------------------------------

## Long straight streets get a chicane every ~100 m: two solid islands (a planted hedge with trees, a kiosk
## or a billboard on a planter), one against each kerb 14 m apart, each reaching 1 m past the centre line, so
## no straight line of sight runs the length of a street and cars weave through a ~5 m gap. They are real
## solid props (collision matches what is seen) and stay clear of junctions, doors, plazas, bridges and
## parked cars. Every island is recorded in `world.calming_islands` (corner polygons) for the tests.
const CALM_SPACING: float = 100.0
const CALM_LENGTH: float = 4.0
const CALM_PAIR_GAP: float = 14.0
const KIOSKS: PackedStringArray = ["NEWS & TOBACCO", "FLOWERS", "PRETZELS", "LOTTO", "BUS TOKENS", "COFFEE", "MAPS & CARDS", "FRESH JUICE"]
const BOARDS: PackedStringArray = ["MILLENNIUM SALE", "VISIT THE PIER", "HALCYON RADIO 98.7", "LOTTO TONIGHT", "GRAND OPENING", "CALL 555-0142", "RENT A STORAGE UNIT", "PORT HALCYON SAVINGS"]
var _calm_index: int = 0
var _calm_cells: Dictionary = {}


## The longest 2D sightlines down the streets are found first (a ray along every street every 30 m, blocked
## by lots, footprints, props and the islands already placed) and a chicane pair goes ~90-125 m along each
## one that runs past SIGHT_LIMIT, in three passes, so islands land where the views actually are.
const SIGHT_LIMIT: float = 135.0
var _hot: Array = []

func _calming() -> void:
	# Existing islands (none at first) block rays; each new pair is registered as it is placed.
	for pass_index: int in range(4):
		_hot.clear()
		for road_index: int in range(w.roads.size()):
			var road: Dictionary = w.roads[road_index]
			if str(road["name"]).begins_with("FOUNTAIN"):
				continue
			var points: PackedVector2Array = road["points"]
			for index: int in range(points.size() - 1):
				var a: Vector2 = points[index]
				var b: Vector2 = points[index + 1]
				var length: float = a.distance_to(b)
				if length < 30.0:
					continue
				var u: Vector2 = (b - a) / length
				var steps: int = maxi(1, int(length / 30.0))
				for step: int in range(steps + 1):
					var p: Vector2 = a + u * (length * step / steps)
					for dir: Vector2 in [u, -u]:
						var seen: Array = _march(p, dir)
						if not bool(seen[1]) and float(seen[0]) > SIGHT_LIMIT:
							_hot.append([float(seen[0]), p, dir, road_index])
		if _hot.is_empty():
			return
		_hot.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) > float(q[0]))
		var placed_here: Array[Vector2] = []
		for entry: Array in _hot:
			var origin: Vector2 = entry[1]
			var dir: Vector2 = entry[2]
			var reach: float = minf(float(entry[0]), 400.0)
			# A pair placed earlier this pass on this same line already cuts it.
			var cut: bool = false
			for other: Vector2 in placed_here:
				var along: float = (other - origin).dot(dir)
				if along > 8.0 and along < reach and absf((other - origin).cross(dir)) < 4.0:
					cut = true
					break
			if cut:
				continue
			var done: bool = false
			for distance: float in [105.0, 95.0, 115.0, 85.0, 125.0, 75.0, 65.0, 55.0, 45.0]:
				if distance > reach - 12.0:
					continue
				var spot: Vector2 = origin + dir * distance
				var found: int = _road_at(spot)
				if found < 0:
					continue
				var road: Dictionary = w.roads[found]
				var points: PackedVector2Array = road["points"]
				var road_dir: Vector2 = Vector2.ZERO
				for index: int in range(points.size() - 1):
					if spot.distance_to(Geometry2D.get_closest_point_to_segment(spot, points[index], points[index + 1])) < 0.6:
						road_dir = (points[index + 1] - points[index]).normalized()
				if road_dir == Vector2.ZERO or absf(road_dir.cross(dir)) > 0.12:
					continue
				var start: Vector2 = spot if road_dir.dot(dir) > 0.0 else spot - road_dir * CALM_PAIR_GAP
				var forward: Vector2 = road_dir
				if _calm_ok(start, start + forward * CALM_PAIR_GAP, found):
					_island_pair(start, forward, float(road["width"]) * 0.5)
					placed_here.append(spot)
					done = true
					break
			if not done and _try_hoarding(origin, dir, reach):
				# No island fits along the street itself: the open ground the line runs out over is fenced off.
				placed_here.append(origin + dir * 90.0)


## Road index whose centre line passes within 0.6 m of `p` (-1 if none).
func _road_at(p: Vector2) -> int:
	var key: Vector2i = _key(p)
	if not _segs.has(key):
		return -1
	for seg: Array in _segs[key]:
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])) < 0.6:
			return int(seg[3])
	return -1


## How far a 2D ray runs from `p` along `dir` before it meets a lot, footprint, prop or island: [metres, ended at the coast].
func _march(p: Vector2, dir: Vector2) -> Array:
	var t: float = 8.0
	while t < 400.0:
		var q: Vector2 = p + dir * t
		if fmod(t, 16.0) < 4.0 and not w._on_land(q):
			return [t, true]
		var key: Vector2i = _key(q)
		if _eye.has(key):
			for rect: Rect2 in _eye[key]:
				if rect.has_point(q):
					return [t, false]
		if _obbs.has(key):
			for other: Array in _obbs[key]:
				var d: Vector2 = q - (other[0] as Vector2)
				if absf(d.dot(other[1])) <= float(other[3]) and absf(d.dot(other[2])) <= float(other[4]):
					return [t, false]
		t += 4.0
	return [400.0, false]


func _calm_ok(p: Vector2, q: Vector2, road_index: int) -> bool:
	# Nothing solid already stands in the carriageway here (a wall or prop that intrudes on the road).
	var along: Vector2 = (q - p).normalized()
	var across: Vector2 = Vector2(-along.y, along.x)
	for step: int in range(5):
		for lateral: float in [-5.0, -2.5, 0.0, 2.5, 5.0]:
			if w.solid_near(p.lerp(q, float(step) / 4.0) + across * lateral, 1.4):
				_why("c-solid")
				return false
	for at: Vector2 in [p, q, (p + q) * 0.5]:
		if not w._on_land(at):
			_why("c-land")
			return false
		for poly: PackedVector2Array in _keepout:
			if Geometry2D.is_point_in_polygon(at, poly):
				_why("c-park")
				return false
		for bridge: Dictionary in w.bridges:
			if (bridge["rect"] as Rect2).grow(22.0).has_point(at):
				_why("c-bridge")
				return false
		if w.door_within(at, 5.0):
			_why("c-door")
			return false
		# Chicane pairs keep 26 m from each other, so a car can always thread each one.
		for poly: PackedVector2Array in w.calming_islands:
			if (poly[0] + poly[2]) * 0.5 != Vector2.ZERO and ((poly[0] + poly[2]) * 0.5).distance_to(at) < 26.0:
				_why("c-island")
				return false
		for vehicle: Dictionary in w.parked_vehicles:
			var spot: Vector3 = vehicle["at"]
			if Vector2(spot.x, spot.z).distance_to(at) < 7.0:
				_why("c-car")
				return false
		# Junction zone: no other street within its half width + 4.5 m.
		for dx: int in range(-2, 3):
			for dy: int in range(-2, 3):
				var key: Vector2i = _key(at) + Vector2i(dx, dy)
				if not _segs.has(key):
					continue
				for seg: Array in _segs[key]:
					if int(seg[3]) == road_index:
						continue
					if at.distance_to(Geometry2D.get_closest_point_to_segment(at, seg[0], seg[1])) < float(seg[2]) + 4.5:
						_why("c-junction")
						return false
	return true


func _island_pair(at: Vector2, u: Vector2, half: float) -> void:
	var n: Vector2 = Vector2(-u.y, u.x)
	var side: float = 1.0 if (_calm_index % 2 == 0) else -1.0
	_island(at, u, n, half, side)
	_island(at + u * CALM_PAIR_GAP, u, n, half, -side)


## One island against the `side` kerb (+1 = the left of the direction of travel), reaching 1 m past the centre line.
func _island(at: Vector2, u: Vector2, n: Vector2, half: float, side: float) -> void:
	var width: float = half + 1.0
	var lateral: float = side * (half - width * 0.5)
	var center: Vector2 = at + n * lateral
	var yaw: float = atan2(-n.y, n.x)
	var corners: PackedVector2Array = PackedVector2Array()
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		corners.append(center + n * corner.x * width * 0.5 + u * corner.y * CALM_LENGTH * 0.5)
	w.calming_islands.append(corners)
	_register_obb(_obbs, center, n, u, width * 0.5, CALM_LENGTH * 0.5)
	w._target = _calm_node(center)
	w._xf = Transform3D.IDENTITY
	w._xf_yaw = 0.0
	var kind: int = _calm_index % 3
	_calm_index += 1
	var kerb: StandardMaterial3D = w._material(Color(0.62, 0.6, 0.55), 0.9, "stucco")
	var hedge: StandardMaterial3D = w._material(Color(0.2, 0.36, 0.2), 0.95, "grass")
	var facing: Vector3 = Vector3(u.x, 0, u.y)
	# Kerbed base: solid, 0.3 m high.
	w._box_with(Vector3(center.x, 0.17, center.y), Vector3(width, 0.3, CALM_LENGTH), kerb, true, yaw)
	match kind:
		0:
			# A clipped hedge wall (1.5 m, solid) with two plane trees on it.
			w._box_with(Vector3(center.x, 1.07, center.y), Vector3(width - 0.5, 1.5, CALM_LENGTH - 1.0), hedge, true, yaw)
			for offset: float in [-0.25, 0.25]:
				var tree_at: Vector2 = center + n * width * offset
				w._cylinder(Vector3(tree_at.x, 2.4, tree_at.y), 0.14, 3.0, Color(0.37, 0.28, 0.18), 6)
				w._cylinder(Vector3(tree_at.x, 4.2, tree_at.y), 1.5, 1.8, Color(0.33, 0.45, 0.26), 6)
		1:
			# A kiosk: a solid box with an awning and a sign.
			var paint: Color = [Color(0.2, 0.42, 0.36), Color(0.62, 0.2, 0.18), Color(0.2, 0.3, 0.5), Color(0.72, 0.55, 0.16)][_calm_index % 4]
			w._box_with(Vector3(center.x, 1.5, center.y), Vector3(width - 0.8, 2.5, CALM_LENGTH - 0.8), w._material(paint, 0.7, "panel"), true, yaw)
			w._box_with(Vector3(center.x, 2.85, center.y), Vector3(width - 0.2, 0.16, CALM_LENGTH + 0.8), w._material(Color(0.9, 0.86, 0.78), 0.8), false, yaw)
			for way: float in [1.0, -1.0]:
				var label_at: Vector3 = Vector3(center.x, 2.3, center.y) + facing * way * (CALM_LENGTH * 0.5 - 0.35)
				var label: Label3D = w._label(str(KIOSKS[_calm_index % KIOSKS.size()]), label_at, 36, Color(1.0, 0.95, 0.8), atan2(facing.x * way, facing.z * way), 0.012)
				label.visibility_range_end = 60.0
		_:
			# A billboard on two posts over a hedge planter (the hedge is the solid at eye height).
			w._box_with(Vector3(center.x, 0.9, center.y), Vector3(width - 0.6, 1.4, CALM_LENGTH - 1.2), hedge, true, yaw)
			for offset: float in [-0.32, 0.32]:
				var post_at: Vector2 = center + n * width * offset
				w._box_with(Vector3(post_at.x, 3.4, post_at.y), Vector3(0.3, 5.4, 0.3), w._material(Color(0.3, 0.3, 0.32), 0.6, "metal"), true, yaw)
			var board_at: Vector3 = Vector3(center.x, 5.0, center.y)
			w._box_with(board_at, Vector3(width * 0.9, 2.4, 0.3), w._material(Color(0.14, 0.14, 0.18), 0.8), false, yaw)
			for way: float in [1.0, -1.0]:
				var label: Label3D = w._label(str(BOARDS[_calm_index % BOARDS.size()]), board_at + facing * way * 0.2, 36, Color(1.0, 0.85, 0.4), atan2(facing.x * way, facing.z * way), 0.034)
				label.visibility_range_end = 90.0


func _calm_node(at: Vector2) -> Node3D:
	var key: Vector3i = Vector3i(floori(at.x / 96.0), floori(at.y / 96.0), 7)
	if not _calm_cells.has(key):
		var saved: Node3D = w._target
		var node: Node3D = w._begin("Calm %d %d" % [key.x, key.y])
		w._target = saved
		_calm_cells[key] = node
	return _calm_cells[key] as Node3D


## Where a long line of sight runs off a street's end across open ground, a construction hoarding (a solid
## 10 m plywood fence with bill posters) closes it: the city is mid-boom, sites are fenced off.
const HOARDS: PackedStringArray = ["FUTURE HOME OF\nPORT HALCYON PLAZA", "COMING SOON\nLOFTS FROM $89,900", "SITE OFFICE\nNO ADMITTANCE", "BUILDING FOR THE\nNEW MILLENNIUM", "PARKING LOT\nCOMING 2000", "CALL 555-0177\nFOR LEASING"]
var _hoard_index: int = 0

func _try_hoarding(origin: Vector2, dir: Vector2, reach: float) -> bool:
	var across: Vector2 = Vector2(-dir.y, dir.x)
	for distance: float in [100.0, 90.0, 110.0, 80.0, 120.0, 70.0, 60.0, 130.0, 50.0]:
		if distance > reach - 12.0:
			continue
		var spot: Vector2 = origin + dir * distance
		if _road_at(spot) >= 0:
			continue
		if not _clear(spot, across, dir, 10.0, 1.2):
			continue
		_hoarding(spot, across, dir)
		return true
	return false


func _hoarding(at: Vector2, across: Vector2, dir: Vector2) -> void:
	_register_obb(_obbs, at, across, dir, 5.5, 1.0)
	w._target = _calm_node(at)
	w._xf = Transform3D.IDENTITY
	w._xf_yaw = 0.0
	var yaw: float = atan2(-across.y, across.x)
	var ground: float = maxf(_height_at(at), 0.0)
	var planks: StandardMaterial3D = w._material(Color(0.52, 0.46, 0.36), 0.9, "planks")
	w._box_with(Vector3(at.x, ground + 1.2, at.y), Vector3(10.0, 2.4, 0.3), planks, true, yaw)
	# Two raking braces and a cap rail.
	for offset: float in [-3.5, 3.5]:
		var brace_at: Vector2 = at + across * offset + dir * 0.7
		w._box_with(Vector3(brace_at.x, ground + 0.9, brace_at.y), Vector3(0.14, 1.8, 0.14), planks, false, yaw)
	w._box_with(Vector3(at.x, ground + 2.45, at.y), Vector3(10.2, 0.12, 0.42), w._material(Color(0.3, 0.3, 0.32), 0.7), false, yaw)
	var facing: Vector3 = Vector3(dir.x, 0, dir.y)
	var text: String = str(HOARDS[_hoard_index % HOARDS.size()])
	_hoard_index += 1
	for way: float in [1.0, -1.0]:
		var poster_at: Vector3 = Vector3(at.x, ground + 1.5, at.y) + facing * way * 0.17
		w._box_with(poster_at, Vector3(4.2, 1.2, 0.02), w._material(Color(0.9, 0.86, 0.72), 0.9), false, yaw)
		var label: Label3D = w._label(text, poster_at + facing * way * 0.02, 36, Color(0.5, 0.12, 0.1), atan2(facing.x * way, facing.z * way), 0.0135)
		label.outline_size = 0
		label.visibility_range_end = 60.0
