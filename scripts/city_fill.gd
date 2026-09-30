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
	_carve_streets()
	for road_index: int in range(w.roads.size()):
		_frontage(road_index)
	_coast_frontage()
	_dress_alleys()
	_street_props()
	_life()
	_far_massing()
	for key: Vector3i in _decor_cells:
		var decor: Node3D = _decor_cells[key]
		w._finish(decor)
		for child: Node in decor.get_children():
			if child is GeometryInstance3D and not child is Label3D:
				(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				(child as GeometryInstance3D).visibility_range_end = 70.0
				w._detail_ranges.append(child)
	for key: Vector3i in _prop_cells:
		var calm: Node3D = _prop_cells[key]
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


## Rects that stop a 1.3 m line of sight (buildings, walls, tall props), for the sightline planner.
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
		_index_road(road_index)
	_index_slabs()


## Puts one street's segments into the road grid (each segment in every cell its bounds touch).
func _index_road(road_index: int) -> void:
	if true:
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


func _index_slabs() -> void:
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
var _need_sides: bool = false
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
	if _need_sides:
		# Side-door kinds: the strip beside each wall is free of poles and props too.
		for side: float in [-1.0, 1.0]:
			for step: int in range(-2, 3):
				if w.solid_near(center + u * side * (hw + 1.7) + v * (float(step) * hd * 0.4), 0.5):
					_why("side")
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
		_need_sides = wide
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
		var shade: Color = color * float(face[4]) * 0.7
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


# --- Street props: kerb corners and open ground ---------------------------------------------------------

## Nothing solid stands on a road. The 0.8 chicane islands that used to sit in the carriageway are gone: the
## same vocabulary (clipped hedges with plane trees, kiosks, billboards on planters, construction hoardings)
## is placed on the free gray ground BESIDE the streets instead, in two passes:
##  1. Junction corners: at every street corner with open gray ground between the kerb and the buildings
##     (where drivers cut across the pavement) a solid cluster stands 0.5 m off both kerbs, with 2 m of
##     walkway left behind it. Never on a doorway, alley mouth, phone, crew spawn, park or Midtown's ring.
##  2. Sightlines: where a long view (SIGHT_LIMIT+) runs out over open ground past a bend or a street's end,
##     a hoarding, hedge row or billboard closes it (only ever where the clear-lot test passes: off the road).
## Every cluster is recorded in `clusters` ({kind, center, u, v, hw, hd, corner}) for the tests.
const KIOSKS: PackedStringArray = ["NEWS & TOBACCO", "FLOWERS", "PRETZELS", "LOTTO", "BUS TOKENS", "COFFEE", "MAPS & CARDS", "FRESH JUICE"]
const BOARDS: PackedStringArray = ["MILLENNIUM SALE", "VISIT THE PIER", "HALCYON RADIO 98.7", "LOTTO TONIGHT", "GRAND OPENING", "CALL 555-0142", "RENT A STORAGE UNIT", "PORT HALCYON SAVINGS"]
const SIGHT_LIMIT: float = 110.0
## A corner cluster keeps this far off both kerbs, and leaves this much walkway between it and the buildings.
const CORNER_SETBACK: float = 0.5
const CORNER_WALK: float = 2.0
## Cluster kinds: a hedge with plane trees, a kiosk, a billboard on a planter, a lone tree in a planter, a hoarding.
const HEDGE: int = 0
const KIOSK: int = 1
const BOARD: int = 2
const TREE: int = 3
const HOARD: int = 4
## Half sizes (across, deep) per kind.
const HALF: Array[Vector2] = [Vector2(2.4, 0.9), Vector2(2.0, 1.4), Vector2(2.6, 0.8), Vector2(0.95, 0.95), Vector2(5.0, 0.15)]
var clusters: Array[Dictionary] = []
var corners_dressed: int = 0
var _prop_index: int = 0
var _prop_cells: Dictionary = {}
var _hot: Array = []


func _street_props() -> void:
	_junction_corners()
	_sightline_clusters()
	_open_ground_sites()


# --- Junction corners ---

## Every crossing and T-junction: {at, arms: [[unit direction away from the junction, road half width], ...]}.
## An arm exists where that street really runs on 10 m past the junction.
func _junctions() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var seen: Dictionary = {}
	var boxes: Array[Rect2] = []
	for road: Dictionary in w.roads:
		var points: PackedVector2Array = road["points"]
		var box: Rect2 = Rect2(points[0], Vector2.ZERO)
		for point: Vector2 in points:
			box = box.expand(point)
		boxes.append(box.grow(float(road["width"]) * 0.5 + 2.0))
	for a: int in range(w.roads.size()):
		var road_a: Dictionary = w.roads[a]
		if str(road_a["name"]).begins_with("FOUNTAIN"):
			continue
		var pa: PackedVector2Array = road_a["points"]
		for b: int in range(a + 1, w.roads.size()):
			var road_b: Dictionary = w.roads[b]
			if str(road_b["name"]).begins_with("FOUNTAIN") or not boxes[a].intersects(boxes[b]):
				continue
			var pb: PackedVector2Array = road_b["points"]
			# Each spot: [junction point, direction of road a there, direction of road b there].
			var spots: Array[Array] = []
			for i: int in range(pa.size() - 1):
				for j: int in range(pb.size() - 1):
					var hit: Variant = Geometry2D.segment_intersects_segment(pa[i], pa[i + 1], pb[j], pb[j + 1])
					if hit != null:
						spots.append([hit, (pa[i + 1] - pa[i]).normalized(), (pb[j + 1] - pb[j]).normalized()])
			# A street that ends on the side of another (a T-junction, or a dead end cut in by the fill).
			for order: int in range(2):
				var ending: PackedVector2Array = pa if order == 0 else pb
				var through: PackedVector2Array = pb if order == 0 else pa
				var half: float = float((road_b if order == 0 else road_a)["width"]) * 0.5 + 1.0
				for tip: int in [0, ending.size() - 1]:
					for j: int in range(through.size() - 1):
						var near: Vector2 = Geometry2D.get_closest_point_to_segment(ending[tip], through[j], through[j + 1])
						if near.distance_to(ending[tip]) <= half:
							var inward: Vector2 = (ending[1] - ending[0]).normalized() if tip == 0 else (ending[ending.size() - 2] - ending[ending.size() - 1]).normalized()
							var along: Vector2 = (through[j + 1] - through[j]).normalized()
							spots.append([near, inward, along] if order == 0 else [near, along, inward])
			for spot: Array in spots:
				var at: Vector2 = spot[0]
				var key: String = "%d/%d" % [a, b]
				var dup: bool = false
				for other: Vector2 in seen.get(key, []):
					dup = dup or other.distance_to(at) < 6.0
				if dup:
					continue
				if not seen.has(key):
					seen[key] = []
				(seen[key] as Array).append(at)
				var arms: Array = []
				for entry: Array in [[a, spot[1], road_a], [b, spot[2], road_b]]:
					for sign: float in [1.0, -1.0]:
						var dir: Vector2 = (entry[1] as Vector2) * sign
						if _street_runs(int(entry[0]), at + dir * 10.0):
							arms.append([dir, float((entry[2] as Dictionary)["width"]) * 0.5])
				found.append({"at": at, "arms": arms})
	return found


## True if road `road_index` has its centre line within 1.5 m of `p`.
func _street_runs(road_index: int, p: Vector2) -> bool:
	var points: PackedVector2Array = (w.roads[road_index] as Dictionary)["points"]
	for index: int in range(points.size() - 1):
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, points[index], points[index + 1])) < 1.5:
			return true
	return false


## True if `p` is inside any carriageway (centre line + half width + `margin`), carved streets included.
func _on_road(p: Vector2, margin: float) -> bool:
	var key: Vector2i = _key(p)
	if not _segs.has(key):
		return false
	for seg: Array in _segs[key]:
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])) < float(seg[2]) + margin:
			return true
	return false


func _junction_corners() -> void:
	for junction: Dictionary in _junctions():
		var at: Vector2 = junction["at"]
		var arms: Array = junction["arms"]
		if arms.size() < 3:
			continue
		arms.sort_custom(func(p: Array, q: Array) -> bool: return (p[0] as Vector2).angle() < (q[0] as Vector2).angle())
		for index: int in range(arms.size()):
			var arm_a: Array = arms[index]
			var arm_b: Array = arms[(index + 1) % arms.size()]
			var a: Vector2 = arm_a[0]
			var b: Vector2 = arm_b[0]
			var wedge: float = fposmod(b.angle() - a.angle(), TAU)
			if wedge < deg_to_rad(50.0) or wedge > deg_to_rad(130.0):
				continue
			# The kerb corner: where the two kerb lines facing each other meet.
			var na: Vector2 = Vector2(-a.y, a.x)
			var nb: Vector2 = Vector2(b.y, -b.x)
			var det: float = na.x * nb.y - na.y * nb.x
			if absf(det) < 0.2:
				continue
			var ha: float = float(arm_a[1])
			var hb: float = float(arm_b[1])
			var apex: Vector2 = at + Vector2((ha * nb.y - na.y * hb) / det, (na.x * hb - ha * nb.x) / det)
			_dress_corner(apex, (a + b).normalized())


## One corner: the first kind (rotating through the four) that stands 0.5 m off both kerbs with its walkway free.
func _dress_corner(apex: Vector2, out: Vector2) -> void:
	var u: Vector2 = Vector2(-out.y, out.x)
	for attempt: int in range(4):
		var kind: int = (_prop_index + attempt) % 4
		var half: Vector2 = HALF[kind]
		var spot: Variant = null
		# Slide the cluster out along the bisector until its outline is 0.5 m off every carriageway.
		for step: int in range(0, 21):
			var probe: Vector2 = apex + out * (0.25 * step)
			if _outline_off_roads(probe, u, out, half):
				spot = probe
				break
		if spot == null:
			continue
		var center: Vector2 = spot
		if not _corner_ok(center, u, out, half):
			continue
		_register_cluster(kind, center, u, out, half, true)
		_build_cluster(kind, center, u, out, half)
		_prop_index += 1
		corners_dressed += 1
		return


## The nine sample points of an oriented box (corners, edge midpoints, centre).
func _outline(center: Vector2, u: Vector2, v: Vector2, half: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for sx: float in [-1.0, 0.0, 1.0]:
		for sz: float in [-1.0, 0.0, 1.0]:
			points.append(center + u * sx * half.x + v * sz * half.y)
	return points


func _outline_off_roads(center: Vector2, u: Vector2, v: Vector2, half: Vector2) -> bool:
	for point: Vector2 in _outline(center, u, v, half):
		if _on_road(point, CORNER_SETBACK):
			return false
	return true


## The site tests every cluster passes: away from doors, alley mouths, phones, crew spawns, parked cars,
## bridges, the Midtown ring and the public spaces city_detail.gd dresses. `reach` is the cluster's radius.
func _site_ok(center: Vector2, reach: float) -> bool:
	# Midtown's ring roads (the practice wheelman's loop, shop kerbs right on the street) stay as they are.
	if absf(center.x) <= 100.0 and absf(center.y) <= 100.0:
		_why("p-midtown")
		return false
	if w.door_within(center, reach + 3.0):
		_why("p-door")
		return false
	for alley: Dictionary in alleys:
		if (alley["at"] as Vector2).distance_to(center) < reach + 5.0:
			_why("p-alley")
			return false
	for phone: Vector3 in w.payphones:
		if Vector2(phone.x, phone.z).distance_to(center) < reach + 2.5:
			_why("p-phone")
			return false
	for crew: Dictionary in w.crew_spawns.values():
		for key: String in ["spawn", "car", "hq"]:
			var spot: Vector3 = crew[key]
			if Vector2(spot.x, spot.z).distance_to(center) < ((8.0 if key == "car" else 6.0) + reach):
				_why("p-crew")
				return false
	for vehicle: Dictionary in w.parked_vehicles:
		var spot: Vector3 = vehicle["at"]
		if Vector2(spot.x, spot.z).distance_to(center) < reach + 4.0:
			_why("p-car")
			return false
	for bridge: Dictionary in w.bridges:
		if (bridge["rect"] as Rect2).grow(reach + 10.0).has_point(center):
			_why("p-bridge")
			return false
	if CityDetail.is_path_entrance(center):
		_why("p-path")
		return false
	return true


## Geometry and ground tests for a cluster; a corner's walkway is the 2 m behind it, toward the buildings.
func _corner_ok(center: Vector2, u: Vector2, v: Vector2, half: Vector2, walkway: bool = true) -> bool:
	var reach: float = half.length()
	if not _site_ok(center, reach):
		return false
	var outline: Array[Vector2] = _outline(center, u, v, half)
	for point: Vector2 in outline:
		if not w._on_land(point):
			_why("p-land")
			return false
		for angle: int in range(0, 8):
			if not w._on_land(point + Vector2.RIGHT.rotated(angle * PI * 0.25) * 3.0):
				_why("p-coast")
				return false
	var box: Rect2 = _bounds(PackedVector2Array(outline)).grow(1.0)
	for index: int in range(_keepout.size()):
		if box.intersects(_keepout_bounds[index]):
			for point: Vector2 in outline:
				if Geometry2D.is_point_in_polygon(point, _keepout[index]):
					_why("p-park")
					return false
			if not Geometry2D.intersect_polygons(_corners(center, u, v, half.x, half.y), _keepout[index]).is_empty():
				_why("p-park")
				return false
	var height: float = _height_at(center)
	for point: Vector2 in outline:
		if absf(_height_at(point) - height) > 0.02:
			_why("p-slab")
			return false
	# Nothing tall already stands here (hand-placed props, poles, walls).
	for point: Vector2 in outline:
		if w.solid_near(point, 0.6):
			_why("p-solid")
			return false
	# Lots, their rear zones and earlier clusters.
	var low: Vector2i = _key(box.position)
	var high: Vector2i = _key(box.end)
	for cx: int in range(low.x, high.x + 1):
		for cy: int in range(low.y, high.y + 1):
			var key: Vector2i = Vector2i(cx, cy)
			for source: Dictionary in [_obbs, _zones]:
				if source.has(key):
					for other: Array in source[key]:
						if _obb_pair(center, u, v, half.x + 0.5, half.y + 0.5, other):
							_why("p-lot")
							return false
	if not walkway:
		return true
	# Walkway: the prop plus 2 m behind it (and 0.5 m, at least 2 m in all, each end) is clear of buildings, walls and tall props.
	var walk_center: Vector2 = center + v * CORNER_WALK * 0.5
	var walk_half: Vector2 = Vector2(maxf(half.x + 0.5, CORNER_WALK), half.y + CORNER_WALK * 0.5)
	var walk_box: Rect2 = _bounds(_corners(walk_center, u, v, walk_half.x, walk_half.y)).grow(0.5)
	for cx: int in range(_key(walk_box.position).x, _key(walk_box.end).x + 1):
		for cy: int in range(_key(walk_box.position).y, _key(walk_box.end).y + 1):
			var key: Vector2i = Vector2i(cx, cy)
			if _eye.has(key):
				for rect: Rect2 in _eye[key]:
					if walk_box.intersects(rect) and _obb_hits(walk_center, u, v, walk_half.x, walk_half.y, rect):
						_why("p-walk")
						return false
			# Lots built by this pass (their footprints are not in the eye index).
			if _obbs.has(key):
				for other: Array in _obbs[key]:
					if _obb_pair(walk_center, u, v, walk_half.x, walk_half.y, other):
						_why("p-walk")
						return false
	# Every registered footprint (porches and wings included).
	for rect: Rect2 in w.footprints:
		if walk_box.intersects(rect) and _obb_hits(walk_center, u, v, walk_half.x, walk_half.y, rect):
			_why("p-walk")
			return false
	return true


## Puts a cluster on the books: lot-style obstacle (so later passes keep clear), and occupied marks so
## city_detail.gd's street signs and clutter stand outside it.
func _register_cluster(kind: int, center: Vector2, u: Vector2, v: Vector2, half: Vector2, corner: bool) -> void:
	_register_obb(_obbs, center, u, v, half.x, half.y)
	clusters.append({"kind": kind, "center": center, "u": u, "v": v, "hw": half.x, "hd": half.y, "corner": corner})
	w._occupied.append(center)
	for point: Vector2 in _corners(center, u, v, half.x, half.y):
		w._occupied.append(point)


## Builds one cluster at `center` (u across, v deep). Merges like every other fill prop (one node per 96 m cell).
func _build_cluster(kind: int, center: Vector2, u: Vector2, v: Vector2, half: Vector2) -> void:
	w._target = _prop_node(center)
	w._xf = Transform3D.IDENTITY
	w._xf_yaw = 0.0
	# Solid props must show up as blockers (city_detail.gd keeps its clutter off them).
	w._blockers_off = false
	var ground: float = maxf(_height_at(center), 0.0)
	var yaw: float = atan2(-u.y, u.x)
	var width: float = half.x * 2.0
	var depth: float = half.y * 2.0
	var facing: Vector3 = Vector3(v.x, 0, v.y)
	var hedge: StandardMaterial3D = w._material(Color(0.2, 0.36, 0.2), 0.95, "grass")
	var index: int = _prop_index
	if kind == TREE:
		w._tree(Vector3(center.x, ground, center.y), "plane")
	else:
		var kerb: StandardMaterial3D = w._material(Color(0.62, 0.6, 0.55), 0.9, "stucco")
		# Kerbed base: solid, 0.3 m high.
		w._box_with(Vector3(center.x, ground + 0.15, center.y), Vector3(width, 0.3, depth), kerb, true, yaw)
		match kind:
			HEDGE:
				# A clipped hedge wall (1.5 m, solid) with two plane trees on it.
				w._box_with(Vector3(center.x, ground + 1.05, center.y), Vector3(width - 0.5, 1.5, depth - 0.5), hedge, true, yaw)
				for offset: float in [-0.25, 0.25]:
					var tree_at: Vector2 = center + u * width * offset
					w._cylinder(Vector3(tree_at.x, ground + 2.4, tree_at.y), 0.14, 3.0, Color(0.37, 0.28, 0.18), 6)
					w._cylinder(Vector3(tree_at.x, ground + 4.2, tree_at.y), 1.3, 1.8, Color(0.33, 0.45, 0.26), 6)
			KIOSK:
				# A kiosk: a solid box with an awning and a sign on its two long faces.
				var paint: Color = [Color(0.2, 0.42, 0.36), Color(0.62, 0.2, 0.18), Color(0.2, 0.3, 0.5), Color(0.72, 0.55, 0.16)][index % 4]
				w._box_with(Vector3(center.x, ground + 1.55, center.y), Vector3(width - 0.4, 2.5, depth - 0.4), w._material(paint, 0.7, "panel"), true, yaw)
				w._box_with(Vector3(center.x, ground + 2.9, center.y), Vector3(width + 0.2, 0.16, depth + 0.8), w._material(Color(0.9, 0.86, 0.78), 0.8), false, yaw)
				var words: String = str(KIOSKS[index % KIOSKS.size()])
				for way: float in [1.0, -1.0]:
					var label_at: Vector3 = Vector3(center.x, ground + 2.35, center.y) + facing * way * (half.y - 0.15)
					var label: Label3D = w._label(words, label_at, 36, Color(1.0, 0.95, 0.8), atan2(facing.x * way, facing.z * way), _fit(words, width - 0.9))
					label.visibility_range_end = 60.0
			_:
				# A billboard on two posts over a hedge planter (the hedge is the solid at eye height).
				w._box_with(Vector3(center.x, ground + 0.9, center.y), Vector3(width - 0.6, 1.2, depth - 0.3), hedge, true, yaw)
				for offset: float in [-0.32, 0.32]:
					var post_at: Vector2 = center + u * width * offset
					w._box_with(Vector3(post_at.x, ground + 3.4, post_at.y), Vector3(0.3, 5.4, 0.3), w._material(Color(0.3, 0.3, 0.32), 0.6, "metal"), true, yaw)
				var board_at: Vector3 = Vector3(center.x, ground + 5.0, center.y)
				w._box_with(board_at, Vector3(width * 0.9, 2.4, 0.3), w._material(Color(0.14, 0.14, 0.18), 0.8), false, yaw)
				var text: String = str(BOARDS[index % BOARDS.size()])
				for way: float in [1.0, -1.0]:
					var label: Label3D = w._label(text, board_at + facing * way * 0.2, 36, Color(1.0, 0.85, 0.4), atan2(facing.x * way, facing.z * way), _fit(text, width * 0.84))
					label.visibility_range_end = 90.0
	w._blockers_off = true


## The label pixel size that fits `words` (36 px type, ~0.55 em per glyph) into `span` metres, at most 0.034.
func _fit(words: String, span: float) -> float:
	var longest: int = 1
	for line: String in words.split("\n"):
		longest = maxi(longest, line.length())
	return minf(0.034, span / (float(longest) * 0.55 * 36.0))


func _prop_node(at: Vector2) -> Node3D:
	var key: Vector3i = Vector3i(floori(at.x / 96.0), floori(at.y / 96.0), 7)
	if not _prop_cells.has(key):
		var saved: Node3D = w._target
		var node: Node3D = w._begin("Props %d %d" % [key.x, key.y])
		w._target = saved
		_prop_cells[key] = node
	return _prop_cells[key] as Node3D


# --- Sightlines over open ground ---

## The longest 2D sightlines down the streets are found first (a ray along every street every 30 m, blocked
## by lots, footprints, props and the clusters already placed). Where such a view runs on over open ground
## (past a bend, or off a street's end) a hoarding, hedge row or billboard goes across it, on ground that
## passes the full clear-lot test (so never on a carriageway), in five passes.
func _sightline_clusters() -> void:
	for pass_index: int in range(5):
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
			# A cluster placed earlier this pass on this same line already cuts it.
			var cut: bool = false
			for other: Vector2 in placed_here:
				var along: float = (other - origin).dot(dir)
				if along > 8.0 and along < reach and absf((other - origin).cross(dir)) < 4.0:
					cut = true
					break
			if cut:
				continue
			var spot: Variant = _try_cluster(origin, dir, reach)
			if spot != null:
				placed_here.append(spot)


## Tries to close the line from `origin` along `dir` with one prop across it, on clear ground off every road:
## the view only counts once it leaves the carriageway, so the spots are measured from where it does (past a
## bend or off a street's end). Returns where the prop stood (null if nothing fits).
func _try_cluster(origin: Vector2, dir: Vector2, reach: float) -> Variant:
	var across: Vector2 = Vector2(-dir.y, dir.x)
	var leave: float = 8.0
	while leave < reach and _on_road(origin + dir * leave, 1.0):
		leave += 4.0
	if leave >= reach - 20.0:
		return null
	for offset: float in [14.0, 24.0, 34.0, 48.0, 62.0, 80.0, 100.0, 8.0]:
		var distance: float = leave + offset
		if distance > reach - 10.0:
			continue
		var spot: Vector2 = origin + dir * distance
		if _on_road(spot, 6.0):
			continue
		var kind: int = [HOARD, HEDGE, BOARD][_prop_index % 3]
		var half: Vector2 = HALF[kind]
		# Paved block plinths count as free ground here (unlike for lots): only tall solids, buildings, lots, parks
		# and the carriageway (1 m clear) rule a spot out.
		if not _outline_off_roads(spot, across, dir, half + Vector2(1.0, 1.0)) or not _corner_ok(spot, across, dir, half, false):
			continue
		_register_cluster(kind, spot, across, dir, half, false)
		if kind == HOARD:
			_hoarding(spot, across, dir)
		else:
			_build_cluster(kind, spot, across, dir, half)
		_prop_index += 1
		return spot
	return null


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
	w._target = _prop_node(at)
	w._xf = Transform3D.IDENTITY
	w._xf_yaw = 0.0
	# Its solid fence shows up as a blocker (city_detail.gd keeps its clutter off it).
	w._blockers_off = false
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
	w._blockers_off = true


# --- Yard and lot dressing across the long views over open ground -------------------------------------

## Where a long view still runs out over open gray ground after the hoardings (a ray that leaves the carriageway and
## goes on for OPEN_VIEW+ metres), a solid piece of 1999 city clutter stands across it, in the district's own character:
## shipping containers, pallet stacks, a fenced trailer yard, box vans, skip bins with tyre stacks, a brick wall with a
## bus shelter or a billboard on legs. Same rules as the corner clusters: flat ground, 1.5 m clear of every building,
## lot and solid prop, 1.5 m off every carriageway, clear of doors, alleys, phones, crew cars, parks and Midtown's ring.
const OPEN_VIEW: float = 110.0
const SITE_MAX: int = 90
const CONTAINERS: int = 10
const PALLETS: int = 11
const YARD: int = 12
const VANS: int = 13
const SKIPS: int = 14
const WALL: int = 15
## Half sizes (across, deep) per site kind (CONTAINERS .. WALL).
const SITE_HALF: Array[Vector2] = [Vector2(6.3, 1.5), Vector2(4.9, 1.3), Vector2(6.1, 3.0), Vector2(5.9, 1.7), Vector2(6.4, 2.0), Vector2(6.2, 1.5)]
## The compact form of each (one container, two pallet rows of two, a trailer alone, one van, two skips, a short wall).
const SITE_COMPACT: Array[Vector2] = [Vector2(3.2, 1.4), Vector2(2.6, 1.3), Vector2(5.4, 1.6), Vector2(3.0, 1.2), Vector2(4.4, 2.0), Vector2(3.4, 1.5)]
const SITE_MARGIN: float = 0.8
const INDUSTRIAL: PackedStringArray = ["THE HARBOR", "SLIP SIDE", "OLD WHARF", "SOUTH DOCKS", "PORT HALCYON", "MOTOR MILE", "CANAL MARKET"]
const COMMERCIAL: PackedStringArray = ["THE STRIP", "NIGHTLIFE", "UPTOWN", "EASTGATE", "UNION STATION", "MIDTOWN"]
const PAINT: Array[Color] = [Color(0.62, 0.2, 0.16), Color(0.16, 0.32, 0.5), Color(0.2, 0.42, 0.3), Color(0.72, 0.6, 0.22), Color(0.5, 0.52, 0.54), Color(0.78, 0.44, 0.16)]
var sites: int = 0
var _site_misses: Dictionary = {}
var _site_index: int = 0
var _sc: Vector2 = Vector2.ZERO
var _su: Vector2 = Vector2.RIGHT
var _sv: Vector2 = Vector2.DOWN
var _syaw: float = 0.0
var _sg: float = 0.0


func _open_ground_sites() -> void:
	for pass_index: int in range(4):
		var hot: Array = _open_views()
		if hot.is_empty():
			return
		hot.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) > float(q[0]))
		var spots: Array[Vector2] = []
		for entry: Array in hot:
			if sites >= SITE_MAX:
				return
			var origin: Vector2 = entry[1]
			var dir: Vector2 = entry[4]
			var total: float = entry[2]
			var leave: float = entry[3]
			# A site placed earlier this pass on this same line already cuts it.
			var cut: bool = false
			for other: Vector2 in spots:
				var along: float = (other - origin).dot(dir)
				if along > leave and along < total and absf((other - origin).cross(dir)) < 5.0:
					cut = true
					break
			if cut:
				continue
			# A line that took every candidate once and fitted nothing is not tried again.
			var line: Vector3i = Vector3i(roundi(dir.x * 50.0), roundi(dir.y * 50.0), roundi(origin.cross(dir) / 3.0))
			if _site_misses.has(line):
				continue
			var spot: Variant = _try_site(origin, dir, leave, total)
			if spot != null:
				spots.append(spot)
			else:
				_site_misses[line] = true
		if spots.is_empty():
			return


## Every street sample's long views {open metres, start, total length, metres to leave the carriageway, direction}.
func _open_views() -> Array:
	var found: Array = []
	for road: Dictionary in w.roads:
		if str(road["name"]).begins_with("FOUNTAIN"):
			continue
		var points: PackedVector2Array = road["points"]
		for index: int in range(points.size() - 1):
			var a: Vector2 = points[index]
			var b: Vector2 = points[index + 1]
			var length: float = a.distance_to(b)
			if length < 20.0:
				continue
			var u: Vector2 = (b - a) / length
			var across: Vector2 = Vector2(-u.y, u.x)
			var steps: int = maxi(1, int(length / 30.0))
			for step: int in range(steps + 1):
				var p: Vector2 = a + u * (length * step / steps)
				for dir: Vector2 in [u, -u]:
					for lateral: float in [-1.5, 0.0, 1.5]:
						var q: Vector2 = p + across * lateral
						var seen: Array = _march(q, dir)
						var total: float = seen[0]
						if bool(seen[1]) or total <= OPEN_VIEW:
							continue
						var leave: float = 6.0
						while leave < total and _on_road(q + dir * leave, 1.0):
							leave += 6.0
						if total - leave > OPEN_VIEW:
							found.append([total - leave, q, total, leave, dir])
	return found


## One site across the line from `origin` along `dir`, somewhere past where it leaves the road. Returns where it stood.
func _try_site(origin: Vector2, dir: Vector2, leave: float, total: float) -> Variant:
	var across: Vector2 = Vector2(-dir.y, dir.x)
	# Nearest first (within 104 m of the road, the view is closed for good); a view that cannot be closed but runs
	# on for 200+ m gets a prop further out instead, which at least halves it.
	for step: int in range(0, 70):
		var distance: float = leave + 6.0 + 4.0 * step if step < 25 else leave + 106.0 + 10.0 * (step - 25)
		if distance > total - 12.0 or (step >= 25 and total - leave < 200.0):
			break
		for shift: float in [0.0, 2.0, -2.0, 4.0, -4.0, 6.0, -6.0]:
			var spot: Vector2 = origin + dir * distance + across * shift
			if _on_road(spot, 3.0):
				continue
			var list: Array[int] = _site_list(w.district_at(Vector3(spot.x, 0.0, spot.y)))
			for attempt: int in range(list.size() * 2):
				var compact: bool = attempt >= list.size()
				var kind: int = list[(_site_index + attempt) % list.size()]
				var half: Vector2 = (SITE_COMPACT if compact else SITE_HALF)[kind - CONTAINERS]
				if half.x < absf(shift) + 1.8:
					continue
				var padded: Vector2 = half + Vector2(SITE_MARGIN, SITE_MARGIN)
				if not _outline_off_roads(spot, across, dir, padded) or not _rect_clear(spot, across, dir, half.x + 0.3, half.y + 0.3):
					continue
				if not _corner_ok(spot, across, dir, half + Vector2(0.5, 0.5), false):
					continue
				_register_cluster(kind, spot, across, dir, half, false)
				_build_site(kind, spot, across, dir, compact)
				_site_index += 1
				sites += 1
				return spot
	return null


func _site_list(district: String) -> Array[int]:
	if INDUSTRIAL.has(district):
		return [CONTAINERS, YARD, PALLETS, SKIPS, VANS, CONTAINERS]
	if COMMERCIAL.has(district):
		return [WALL, VANS, SKIPS, WALL, PALLETS]
	return [WALL, VANS, SKIPS, WALL]


## No lot, footprint or porch within the box (with margin already in hw/hd).
func _rect_clear(center: Vector2, u: Vector2, v: Vector2, hw: float, hd: float) -> bool:
	var box: Rect2 = _bounds(_corners(center, u, v, hw, hd)).grow(1.0)
	for cx: int in range(_key(box.position).x, _key(box.end).x + 1):
		for cy: int in range(_key(box.position).y, _key(box.end).y + 1):
			var key: Vector2i = Vector2i(cx, cy)
			for source: Dictionary in [_rects, _eye]:
				if source.has(key):
					for rect: Rect2 in source[key]:
						if box.intersects(rect) and _obb_hits(center, u, v, hw, hd, rect):
							_why("p-site")
							return false
	return true


## One box in the site's own frame: `a` across, `b` deep (toward the far end of the view), `y` the centre height.
func _sb(a: float, b: float, y: float, size: Vector3, material: Material, solid: bool = true) -> void:
	var at: Vector2 = _sc + _su * a + _sv * b
	w._box_with(Vector3(at.x, _sg + y, at.y), size, material, solid, _syaw)


func _build_site(kind: int, center: Vector2, u: Vector2, v: Vector2, compact: bool) -> void:
	w._target = _prop_node(center)
	w._xf = Transform3D.IDENTITY
	w._xf_yaw = 0.0
	w._blockers_off = false
	_sc = center
	_su = u
	_sv = v
	_syaw = atan2(-u.y, u.x)
	_sg = maxf(_height_at(center), 0.0)
	var i: int = _site_index
	var dark: StandardMaterial3D = w._material(Color(0.1, 0.1, 0.11), 0.9)
	match kind:
		CONTAINERS:
			# Two containers end to end (staggered so no line runs through the joint); a third on one of them.
			var first: StandardMaterial3D = w._material(PAINT[i % PAINT.size()], 0.7, "metal")
			var second: StandardMaterial3D = w._material(PAINT[(i + 2) % PAINT.size()], 0.7, "metal")
			var top: StandardMaterial3D = w._material(PAINT[(i + 4) % PAINT.size()], 0.7, "metal")
			if compact:
				_sb(0.0, 0.0, 1.3, Vector3(6.1, 2.6, 2.44), first)
				_sb(0.0, 0.0, 3.9, Vector3(6.1, 2.6, 2.44), top)
			else:
				_sb(-2.9, -0.35, 1.3, Vector3(6.1, 2.6, 2.44), first)
				_sb(2.9, 0.35, 1.3, Vector3(6.1, 2.6, 2.44), second)
				var side: float = -2.9 if i % 2 == 0 else 2.9
				_sb(side, -0.35 if i % 2 == 0 else 0.35, 3.9, Vector3(6.1, 2.6, 2.44), top)
		PALLETS:
			# Shrink-wrapped pallet stacks in two staggered rows.
			var wood: StandardMaterial3D = w._material(Color(0.6, 0.47, 0.3), 0.95, "planks")
			var wrap: StandardMaterial3D = w._material(Color(0.78, 0.8, 0.82), 0.4)
			var back_row: Array[float] = [-3.6, -1.2, 1.2, 3.6]
			if compact:
				back_row = [-1.2, 1.2]
			for n: int in range(back_row.size()):
				var tall: float = 1.5 + 0.12 * float((n + i) % 4)
				_sb(back_row[n], -0.6, tall * 0.5, Vector3(2.3, tall, 1.0), wood)
				_sb(back_row[n], -0.6, tall * 0.6, Vector3(2.34, tall * 0.5, 1.04), wrap, false)
			var front_row: Array[float] = [-2.4, 0.0, 2.4]
			if compact:
				front_row = [0.0]
			for n: int in range(front_row.size()):
				var tall: float = 1.6 + 0.14 * float((n + i + 1) % 4)
				_sb(front_row[n], 0.6, tall * 0.5, Vector3(2.3, tall, 1.0), wood)
				_sb(front_row[n], 0.6, tall * 0.6, Vector3(2.34, tall * 0.5, 1.04), wrap, false)
		YARD:
			# A chain-link run with a gap to walk through, and a parked box trailer behind it.
			var fence_b: float = -2.3
			var ends: Array[float] = [-6.0, -0.9, 0.9, 6.0]
			for n: int in range(0, 0 if compact else 4, 2):
				var from: Vector2 = _sc + _su * ends[n] + _sv * fence_b
				var to: Vector2 = _sc + _su * ends[n + 1] + _sv * fence_b
				w._fence(Vector3(from.x, _sg + 0.16, from.y), Vector3(to.x, _sg + 0.16, to.y), 2.4)
			var body: StandardMaterial3D = w._material(Color(0.82, 0.82, 0.8) if i % 2 == 0 else Color(0.2, 0.3, 0.46), 0.6, "panel")
			_sb(0.0, 0.6, 1.95, Vector3(10.4, 2.8, 2.5), body)
			_sb(0.6, 0.6, 0.45, Vector3(8.4, 0.3, 2.2), dark, false)
			for wheel: float in [3.0, 4.2]:
				_sb(wheel, 0.6, 0.45, Vector3(1.0, 0.9, 2.56), dark, false)
			for leg: float in [-3.6, -2.6]:
				_sb(leg, 0.6, 0.3, Vector3(0.12, 0.6, 2.2), dark, false)
		VANS:
			# Two box vans, nose out, staggered so their bodies overlap.
			for n: int in range(1 if compact else 2):
				var sign: float = -1.0 if n == 0 else 1.0
				var paint: StandardMaterial3D = w._material([Color(0.86, 0.85, 0.8), Color(0.28, 0.4, 0.3), Color(0.25, 0.3, 0.48), Color(0.7, 0.66, 0.5)][(i + n * 2) % 4], 0.6, "panel")
				var b: float = -0.6 if n == 0 else 0.6
				if compact:
					b = 0.0
				_sb(sign * 2.3, b, 1.75, Vector3(4.2, 2.4, 2.1), paint)
				_sb(sign * 5.0, b, 1.25, Vector3(1.6, 1.5, 2.0), paint)
				_sb(sign * 5.4, b, 1.6, Vector3(0.5, 0.6, 1.9), w._material(Color(0.25, 0.32, 0.36), 0.3), false)
				for axle: float in [1.3, 4.4]:
					_sb(sign * axle, b, 0.45, Vector3(0.9, 0.9, 2.3), dark, false)
		SKIPS:
			# Three skip bins (staggered, overlapping) and two tyre stacks in front of them.
			var spots: Array[Vector2] = [Vector2(-4.0, -0.6), Vector2(0.0, 0.6), Vector2(4.0, -0.6)]
			if compact:
				spots = [Vector2(-2.0, -0.6), Vector2(2.0, 0.6)]
			for n: int in range(spots.size()):
				var bin: StandardMaterial3D = w._material([Color(0.85, 0.65, 0.12), Color(0.18, 0.38, 0.24), Color(0.6, 0.2, 0.15), Color(0.2, 0.3, 0.5)][(i + n) % 4], 0.6, "metal")
				_sb(spots[n].x, spots[n].y, 0.75, Vector3(4.4, 1.5, 1.9), bin)
				_sb(spots[n].x, spots[n].y, 1.5, Vector3(4.5, 0.1, 2.0), dark, false)
			for stack: float in [-1.0, 1.3]:
				var at: Vector2 = _sc + _su * stack - _sv * 1.45
				w._cylinder(Vector3(at.x, _sg + 0.75, at.y), 0.42, 1.5, Color(0.08, 0.08, 0.09), 10)
				w._collider(Vector3(at.x, _sg + 0.75, at.y), Vector3(0.84, 1.5, 0.84), 0.0)
		WALL:
			var brick: StandardMaterial3D = w._material(Color(0.52, 0.28, 0.22), 0.95, "brick")
			var coping: StandardMaterial3D = w._material(Color(0.66, 0.64, 0.58), 0.85)
			var commercial: bool = COMMERCIAL.has(w.district_at(Vector3(center.x, 0.0, center.y)))
			if commercial:
				# A long low brick wall carrying a billboard on two steel legs.
				var run: float = 6.4 if compact else 11.6
				_sb(0.0, 0.0, 0.8, Vector3(run, 1.6, 0.45), brick)
				_sb(0.0, 0.0, 1.66, Vector3(run + 0.2, 0.12, 0.6), coping, false)
				var steel: StandardMaterial3D = w._material(Color(0.3, 0.3, 0.32), 0.6, "metal")
				var board: float = 5.4 if compact else 9.0
				for leg: float in [-board * 0.4, board * 0.4]:
					_sb(leg, 0.5, 3.6, Vector3(0.3, 4.0, 0.3), steel)
				_sb(0.0, 0.5, 6.4, Vector3(board, 3.0, 0.25), w._material(Color(0.14, 0.14, 0.18), 0.8), false)
				_sb(0.0, 0.5, 7.98, Vector3(board + 0.2, 0.14, 0.4), steel, false)
				var text: String = str(BOARDS[i % BOARDS.size()])
				for way: float in [1.0, -1.0]:
					var board_at: Vector2 = _sc + _su * 0.0 + _sv * (0.5 + way * 0.17)
					var label: Label3D = w._label(text, Vector3(board_at.x, _sg + 6.4, board_at.y), 36, Color(1.0, 0.85, 0.4), atan2(v.x * way, v.y * way), _fit(text, board * 0.84))
					label.visibility_range_end = 90.0
			else:
				# Garden wall either side of a bus shelter (its back panel is solid), open toward the street behind.
				var wing: float = 1.4 if compact else 4.2
				_sb(-1.8 - wing * 0.5, 0.0, 0.8, Vector3(wing, 1.6, 0.45), brick)
				_sb(1.8 + wing * 0.5, 0.0, 0.8, Vector3(wing, 1.6, 0.45), brick)
				_sb(-1.8 - wing * 0.5, 0.0, 1.66, Vector3(wing + 0.2, 0.12, 0.6), coping, false)
				_sb(1.8 + wing * 0.5, 0.0, 1.66, Vector3(wing + 0.2, 0.12, 0.6), coping, false)
				_sb(0.0, 0.0, 1.15, Vector3(3.6, 2.3, 0.12), w._material(Color(0.4, 0.56, 0.58), 0.3))
				var frame: StandardMaterial3D = w._material(Color(0.2, 0.3, 0.26), 0.6, "metal")
				_sb(0.0, -0.65, 2.42, Vector3(3.9, 0.1, 1.5), frame, false)
				for post: float in [-1.8, 1.8]:
					_sb(post, -1.3, 1.2, Vector3(0.08, 2.4, 0.08), frame, false)
				_sb(0.0, -0.35, 0.45, Vector3(2.4, 0.08, 0.42), w._material(Color(0.5, 0.36, 0.22), 0.9, "planks"))
	w._blockers_off = true


# --- New streets through the big empty blocks -----------------------------------------------------

## Where 60+ m of open ground lies behind a street's frontage, a short dead-end street (a lane, row or
## court) is cut in at right angles so the frontage engine can line it with buildings. Dead ends add no
## through routes, so `route()` and the crews' distances are unchanged.
const CARVE_NAMES: PackedStringArray = ["ALDER ROW", "BIRCH LANE", "CEDAR COURT", "DOGWOOD LANE", "ELM ROW", "FERN COURT", "GRANT LANE", "HAZEL ROW", "IVY COURT", "JUNIPER LANE", "LARCH ROW", "MAPLE COURT", "OLIVE LANE", "PINE ROW", "QUINCE COURT", "ROWAN LANE", "SPRUCE ROW", "TAMARACK COURT", "WILLOW LANE", "YARROW ROW", "ASH COURT", "BAY ROW", "CLOVER LANE", "DAHLIA ROW"]
const CARVE_MAX: int = 24
var carved: Array[String] = []


## How far open ground runs from `origin` along `normal`, over a 42 m wide corridor (lateral probes every 10.5 m):
## the shortest run before a building, prop, street, park, slab edge or the coast (10 m margin), capped at 100.
func _free_depth(origin: Vector2, dir: Vector2, normal: Vector2) -> float:
	var shortest: float = 100.0
	for lateral: float in [-21.0, -10.5, 0.0, 10.5, 21.0]:
		var run: float = 0.0
		while run < shortest:
			var at: Vector2 = origin + dir * lateral + normal * run
			if not w._on_land(at):
				break
			var blocked: bool = false
			for angle: int in range(0, 8, 2):
				if not w._on_land(at + Vector2.RIGHT.rotated(angle * PI * 0.25) * 10.0):
					blocked = true
			if blocked or _height_at(at) > 0.05:
				break
			var key: Vector2i = _key(at)
			if _rects.has(key):
				for rect: Rect2 in _rects[key]:
					if rect.grow(1.5).has_point(at):
						blocked = true
						break
			if not blocked and _segs.has(key):
				for seg: Array in _segs[key]:
					if at.distance_to(Geometry2D.get_closest_point_to_segment(at, seg[0], seg[1])) < float(seg[2]) + 3.0 and run > 1.0:
						blocked = true
						break
			if not blocked:
				for index: int in range(_keepout.size()):
					if _keepout_bounds[index].has_point(at) and Geometry2D.is_point_in_polygon(at, _keepout[index]):
						blocked = true
						break
			if blocked:
				break
			run += 4.0
		shortest = minf(shortest, run)
	return shortest


func _carve_streets() -> void:
	var first_new: int = w.roads.size()
	var parents: int = w.roads.size()
	for road_index: int in range(parents):
		if carved.size() >= CARVE_MAX:
			break
		var road: Dictionary = w.roads[road_index]
		if str(road["name"]).begins_with("FOUNTAIN"):
			continue
		var points: PackedVector2Array = road["points"]
		var half: float = float(road["width"]) * 0.5
		for index: int in range(points.size() - 1):
			var a: Vector2 = points[index]
			var b: Vector2 = points[index + 1]
			var length: float = a.distance_to(b)
			if length < 60.0:
				continue
			var dir: Vector2 = (b - a) / length
			for side: float in [1.0, -1.0]:
				var normal: Vector2 = Vector2(-dir.y, dir.x) * side
				var t: float = 30.0
				while t < length - 30.0 and carved.size() < CARVE_MAX:
					var best: float = _free_depth(a + dir * t + normal * (half + 4.0), dir, normal)
					if best >= 52.0:
						var start: Vector2 = a + dir * t
						var finish: Vector2 = start + normal * (half + best - 8.0)
						var title: String = CARVE_NAMES[carved.size() % CARVE_NAMES.size()]
						w._road(title, [start, finish], 10.0)
						carved.append(title)
						_index_road(w.roads.size() - 1)
						# The new street and its two rows of frontage fill the corridor: skip past it.
						t += 70.0
					else:
						t += 24.0
	if w.roads.size() > first_new:
		var saved: Node3D = w._target
		var node: Node3D = w._begin("FillRoads")
		w._build_roads(first_new)
		w._finish(node)
		w._target = saved
		w._xf = Transform3D.IDENTITY
		w._xf_yaw = 0.0


# --- Street life ------------------------------------------------------------------------------------

## Static, deterministic dressing for the fill lots, built after everything else: parked cars along the kerb
## (appended to the END of world.parked_vehicles, so the older order never changes), newspaper boxes,
## planters and hydrants on the sidewalk, and laundry lines strung across the alleys. Everything keeps
## 3 m off doors and clear of props; the collision-free pieces (laundry) are `potato_optional`.
const CAR_COLORS: Array[Color] = [Color(0.55, 0.14, 0.14), Color(0.18, 0.26, 0.4), Color(0.78, 0.74, 0.62), Color(0.13, 0.13, 0.15), Color(0.32, 0.42, 0.3), Color(0.62, 0.5, 0.2), Color(0.5, 0.52, 0.55), Color(0.4, 0.2, 0.3)]
const CAR_TYPES: PackedStringArray = ["sedan", "sedan", "coupe", "suv", "pickup"]
const CLOTH: Array[Color] = [Color(0.9, 0.9, 0.86), Color(0.8, 0.3, 0.25), Color(0.25, 0.4, 0.65), Color(0.9, 0.8, 0.3), Color(0.35, 0.6, 0.4), Color(0.85, 0.6, 0.7)]
var _decor_cells: Dictionary = {}
var cars_added: int = 0
var props_added: int = 0
var lines_added: int = 0


func _life() -> void:
	for lot: Dictionary in placed:
		var center: Vector2 = lot["center"]
		var front: Vector2 = lot["front"]
		var size: Vector2 = lot["size"]
		var u: Vector2 = Vector2(front.y, -front.x)
		var edge: Vector2 = center + front * (size.y * 0.5 + 1.1)
		# A sidewalk piece near the party wall on one side.
		var roll: float = rng.randf()
		var lateral: float = (size.x * 0.5 - 1.3) * (1.0 if rng.randf() < 0.5 else -1.0)
		var spot: Vector2 = edge + u * lateral
		var yaw: float = atan2(front.x, front.y)
		if roll < 0.55 and not w.door_within(spot, 2.8) and not w.solid_near(spot, 0.9) and w._on_land(spot):
			w._target = _cell_node(spot)
			w._xf = Transform3D.IDENTITY
			w._xf_yaw = 0.0
			var ground: float = _height_at(spot) if _height_at(spot) > 0.05 else 0.16
			if roll < 0.2:
				w._news_box(Vector3(spot.x, ground, spot.y), yaw, w._street_palette[rng.randi() % w._street_palette.size()])
			elif roll < 0.4:
				w._planter(Vector3(spot.x, ground, spot.y))
			else:
				w._hydrant(Vector3(spot.x, ground, spot.y))
			props_added += 1
		# A parked car at the kerb in front of some lots.
		if rng.randf() < 0.85:
			_park_car(center, front, u, size)
	for alley: Dictionary in alleys:
		if rng.randf() < 0.6:
			_laundry(alley)


func _park_car(center: Vector2, front: Vector2, u: Vector2, size: Vector2) -> void:
	# The kerb lane: 1.3 m in from the road edge, which is (dp / 2 + setback) in front of the lot centre.
	var road_edge: Vector2 = center + front * (size.y * 0.5 + _setback)
	var at: Vector2 = road_edge + front * 1.4 + u * rng.randf_range(-size.x * 0.25, size.x * 0.25)
	if not w._on_land(at) or w.door_within(at, 4.0) or w.solid_near(at, 2.2):
		return
	# Exactly one street may lie within 14 m (the one it is parked on, 1.4 m inside its edge): no cars in junctions.
	var near_roads: int = 0
	var own_ok: bool = false
	for road: Dictionary in w.roads:
		var points: PackedVector2Array = road["points"]
		for index: int in range(points.size() - 1):
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(at, points[index], points[index + 1])
			var gap: float = at.distance_to(closest) - float(road["width"]) * 0.5
			if gap < 14.0:
				near_roads += 1
				own_ok = absf(gap + 1.4) < 0.5
	if near_roads != 1 or not own_ok:
		return
	for vehicle: Dictionary in w.parked_vehicles:
		var other: Vector3 = vehicle["at"]
		if Vector2(other.x, other.z).distance_to(at) < 7.0:
			return
	for crew: Dictionary in w.crew_spawns.values():
		for key: String in ["spawn", "car", "hq"]:
			var spot: Vector3 = crew[key]
			if Vector2(spot.x, spot.z).distance_to(at) < 12.0:
				return
	# Heading along the street, parked nose-first either way.
	var heading: float = atan2(u.x, u.y) + (0.0 if rng.randf() < 0.5 else PI)
	w._car_prop(Vector3(at.x, 0.03, at.y), heading, CAR_COLORS[rng.randi() % CAR_COLORS.size()], CAR_TYPES[rng.randi() % CAR_TYPES.size()], "")
	cars_added += 1


func _decor_node(at: Vector2) -> Node3D:
	var key: Vector3i = Vector3i(floori(at.x / 96.0), floori(at.y / 96.0), 9)
	if not _decor_cells.has(key):
		var saved: Node3D = w._target
		var node: Node3D = w._begin("FillDecor %d %d" % [key.x, key.y])
		node.add_to_group("potato_optional")
		w._target = saved
		_decor_cells[key] = node
	return _decor_cells[key] as Node3D


## A washing line across an alley at first-floor window height, with a few pieces pegged out.
func _laundry(alley: Dictionary) -> void:
	var at: Vector2 = alley["at"]
	var back: Vector2 = alley["dir"]
	var u: Vector2 = Vector2(back.y, -back.x)
	var reach: float = float(alley["depth"]) * rng.randf_range(0.45, 0.7)
	var mid: Vector2 = at + back * reach
	w._target = _decor_node(mid)
	w._xf = Transform3D.IDENTITY
	w._xf_yaw = 0.0
	var y: float = 5.6 + (0.0 if rng.randf() < 0.5 else 3.4)
	var yaw: float = atan2(-u.y, u.x)
	var line: StandardMaterial3D = w._material(Color(0.75, 0.72, 0.66), 0.9)
	w._box_with(Vector3(mid.x, y, mid.y), Vector3(ALLEY + 1.0, 0.03, 0.03), line, false, yaw)
	for piece: int in range(3 + rng.randi() % 3):
		var lateral: float = -ALLEY * 0.5 + 0.8 + (ALLEY - 1.6) * (float(piece) + rng.randf() * 0.5) / 5.0
		var spot: Vector2 = mid + u * lateral
		w._box_with(Vector3(spot.x, y - 0.4, spot.y), Vector3(0.5, 0.7, 0.02), w._material(CLOTH[rng.randi() % CLOTH.size()], 0.95), false, yaw + rng.randf_range(-0.2, 0.2))
	lines_added += 1
