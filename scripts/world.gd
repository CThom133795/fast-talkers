extends Node3D
class_name FastWorld
## Port Halcyon (0.5): one continuous, asymmetric mainland about 510 m across. North is -Z.
## Midtown (Codex's original district) is the neutral downtown grid with the Union Exchange,
## the armory and walk-in businesses (see interiors.gd). Round it, each neighbourhood keeps
## its own street grid at its own orientation, stitched together by bent arterials, open
## plazas and waterfront drives, so there is no single city-wide grid and every district
## has three or more ways in. Crew turf is spread round the compass, not in the corners:
## Lantern Row (Kojimoto893) west of downtown, Solana Heights (Sol Negro) on the north-east
## bluff, Kingsway (Royals) on the east waterfront and Morris Park (Morris Mafia) south of
## downtown. HQ-to-Exchange routes are measured over the road graph (`route_length`) and kept
## within a few percent of each other. Neutral ground: the Harbor (N), Canal Market (NW, the
## one remaining canal, a dead-end inlet), West Bank Plaza and the West Slip (W), Union
## Station (SW), the Strip with Halcyon Beach (S) and Fountain Square (E).
## Neighbourhoods were authored in the 0.4 island layout and are placed by a rigid transform
## per kit (KITS); every map record (footprints, landmarks, spawns) is converted to world
## space as it is made. All geometry is procedural; each district is its own node so meshes
## batch and merge.
const MeshMerge = preload("res://scripts/mesh_merge.gd")
const RetroTextures = preload("res://scripts/retro_textures.gd")
const Factions = preload("res://scripts/factions.gd")
const MeshKit = preload("res://scripts/mesh_kit.gd")
const Interiors = preload("res://scripts/interiors.gd")
const CityDetail = preload("res://scripts/city_detail.gd")
const CityFill = preload("res://scripts/city_fill.gd")
## Kept for the city-limit tests: the Harbor mole's north quay is at z = -HALF on Halcyon
## Avenue, and Union Street ends at the West Slip quay at x = -HALF.
const HALF: float = 200.0
## Sea level: the one water plane for the sea, the canal and the slip. Land is at y = 0.
const SEA_LEVEL: float = -1.2
## Quay edge: coping height (the kerb you can see and stand behind) and the rail on top.
## Both are real colliders; nothing invisible stands above the rail, so shots clear it.
const COPING_HEIGHT: float = 0.34
const RAIL_HEIGHT: float = 1.12
## Visual layer for interior meshes: interior lamps only light this layer.
const INTERIOR_LAYER: int = 2
## Small static clutter renders on its own layer that the neon street lights skip: a merged
## 60 m clutter cell would otherwise take an extra lighting pass per surface for every nearby sign.
const CLUTTER_LAYER: int = 3
## Neighbourhood kits: authored around `from` (0.4 coordinates), placed at `to` turned by
## `yaw` (radians about +Y). Their outer frame is `from` ± `half`.
const KITS: Dictionary = {
	"lantern": {"from": Vector2(-147, -147), "to": Vector2(-300, -70), "yaw": PI * 0.5 + 0.1, "half": Vector2(53, 53)},
	"solana": {"from": Vector2(147, -147), "to": Vector2(309, -174), "yaw": -PI * 0.5 - 0.16, "half": Vector2(53, 53)},
	"kingsway": {"from": Vector2(147, 147), "to": Vector2(240, 190), "yaw": PI * 0.5 + 0.08, "half": Vector2(53, 53)},
	"morris": {"from": Vector2(-147, 147), "to": Vector2(-90, 253), "yaw": -PI * 0.5 - 0.12, "half": Vector2(53, 53)},
	"strip": {"from": Vector2(147, 0), "to": Vector2(115, 338), "yaw": -PI * 0.5, "half": Vector2(53, 82)},
	"station": {"from": Vector2(0, 152), "to": Vector2(-255, 230), "yaw": -PI * 0.5 + 0.06, "half": Vector2(82, 58)},
}
## Where the 0.5 sites that hang off a kit went (0.6 moved every kit outward). The strip's
## beach, pier and quay gap, Morris Marina and Kingsway Docks are authored in 0.5 world
## coordinates and simply shift by the same amount as their kit.
const STRIP_SHIFT: Vector2 = Vector2(20, 176)
const MORRIS_SHIFT: Vector2 = Vector2(-20, 132)
const DOCKS_SHIFT: Vector2 = Vector2(160, 111)
const RAILS: Array[float] = [168.0, 178.0]

var _materials: Dictionary = {}
var _meshes: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _tex: RetroTextures = RetroTextures.new()
var _target: Node3D
var _glow_materials: Array[StandardMaterial3D] = []
var _lights: Array[OmniLight3D] = []
## Building footprints for the HUD map: world-space bounding rectangles (kept for
## compatibility) and the exact outlines in `footprint_polys` (same order).
var footprints: Array[Rect2] = []
var footprint_polys: Array[PackedVector2Array] = []
## Every building on the map (0.8), one record each, for the enterable-ratio audit and the map:
## {name, kind ("solid", "shop", "plot" or a prefab kind), enterable, footprints (indices into
## footprint_polys)}. A record covers all the outlines its builder registered while it was open.
var buildings: Array[Dictionary] = []
var _building_open: Dictionary = {}
## World x/z bounds of everything solid or tall the builders placed (props, walls, yards), so the
## 0.8 fill pass (city_fill.gd) never drops a building on top of hand-authored dressing.
var _blockers: Array[Rect2] = []
## The 0.8 fill pass (scripts/city_fill.gd): its `placed` lots and `alleys` are for the tests.
var city_fill: RefCounted
var _blockers_off: bool = false
var _road_boxes: Array[Rect2] = []
var _solid_grid: Dictionary = {}
## The part of `_blockers` that stops a car-height (1.3 m) line of sight: used by the fill pass to plan its sightline props.
var eye_blockers: Array[Rect2] = []
## Buildings the fill passes made, for the far-distance stand-ins (city_fill.gd builds one merged, vertex-coloured
## massing mesh per 96 m cell from these): {center (x/z), size (frontage, height, depth), yaw, color}.
var lod_lots: Array[Dictionary] = []
## Beyond this distance a fill building is drawn as its massing box only.
const NEAR_RANGE: float = 110.0
## Districts for the map: {name, rect, color, crew, polys, label_at}.
var districts: Array[Dictionary] = []
## Named places for the map and mission sites: {name, at, neutral}.
var landmarks: Array[Dictionary] = []
## Crew id -> {"car": Vector3, "yaw": float, "hq": Vector3, "spawn": Vector3,
## "spawn_yaw": float, "door": Vector3}. `hq` is the delivery point on the HQ's doorstep;
## `spawn`/`spawn_yaw` stand the crew just outside the door looking down the street.
var crew_spawns: Dictionary = {}
## Open paved squares and parks (x/z polygons) for the map.
var plazas: Array[PackedVector2Array] = []
## Authored public spaces and their solid furniture; used by collision/playtest checks.
var public_spaces: Array[Dictionary] = []
var city_furniture: Array[Dictionary] = []
## Park/plaza perimeter rail runs (CityDetail): {site, from, to, y, inward}. Solid to vehicles.
var park_rails: Array[Dictionary] = []
## Static lived-in clutter (alley bins, bags, boxes, rooftop plant, oil stains): kind, at (x/z), radius, roof.
var city_clutter: Array[Dictionary] = []
## Flat tower roofs for rooftop plant: world centre, size, yaw, roof height, world front, business sign.
var _roofs: Array[Dictionary] = []
## Top faces of raised slabs (world polygon, height) so late dressing can sit on the real surface.
var _slab_tops: Array[Dictionary] = []
## Generic shop-sign uses per text, so no sign is stamped across the city more than twice.
var _sign_uses: Dictionary = {}
## Distance-culled detail meshes (public-space props, clutter): potato mode shortens their range.
var _detail_ranges: Array[GeometryInstance3D] = []
var potato_mode: bool = false
## Walk-in doors: {index, label, kind, position, inside, outside, open, district}.
## Doors start open; `set_door_open(index, open)` swings one (main.gd can bind E to it).
var interactable_doors: Array[Dictionary] = []
## Storefront glass: {body, mesh, broken}. Shots break it (it has take_damage).
var glass_panes: Array[Dictionary] = []
## Sun is exposed so the settings menu can change shadow quality.
var sun: DirectionalLight3D
var environment: Environment
var dusk: bool = true
## Steam vents (world positions) that main.gd puffs steam from.
var steam_vents: Array[Vector3] = []
## Street payphones (world positions): tips come in on these during contracts.
var payphones: Array[Vector3] = []
## Land masses as x/z polygons; everything else is sea.
var land: Array[PackedVector2Array] = []
## Streets: {"name", "points" (centre line), "width"}.
var roads: Array[Dictionary] = []
## Bridge decks: {"rect", "along_x"}.
var bridges: Array[Dictionary] = []
## Rects where the quay barrier is open (bridge ends, pier roots).
var quay_gaps: Array[Rect2] = []
## Parked vehicles for main.gd to spawn: {at, yaw, color, type, name}.
var parked_vehicles: Array[Dictionary] = []
## A closed driving loop on the roads (practice wheelman route).
var road_loop: PackedVector3Array = PackedVector3Array()
## Street-furniture palette for the district being built.
var _street_palette: Array[Color] = [Color(0.8, 0.2, 0.18), Color(0.2, 0.45, 0.75), Color(0.95, 0.75, 0.2), Color(0.25, 0.6, 0.35)]
var _occupied: Array[Vector2] = []
var _pending_blocks: Array[Dictionary] = []
## Placement of the node being built: local (kit) space -> world space.
var _xf: Transform3D = Transform3D.IDENTITY
var _xf_yaw: float = 0.0
var _interior_lights: Array[OmniLight3D] = []
## Per door: its leaves (hinges or a roller shutter).
var _door_nodes: Array[Array] = []
## Road graph for `route`: node positions and adjacency {neighbour index: metres}.
var _graph_points: PackedVector2Array = PackedVector2Array()
var _graph_links: Array[Dictionary] = []

func _ready() -> void:
	_rng.seed = 31071999
	_build_environment()
	_define_land()
	_define_roads()
	var city: Node3D = _begin("City")
	_build_land_and_water()
	_build_roads()
	_build_bridges()
	_build_puddles_and_vents()
	_finish(city)
	var midtown: Node3D = _begin("Midtown")
	_build_streets()
	_build_district()
	_build_props()
	_build_squares()
	_build_midtown_life()
	_finish(midtown)
	_define_districts()
	for builder: Callable in [_build_lantern_row, _build_solana_heights, _build_morris_park, _build_kingsway, _build_harbor, _build_station, _build_canal_market, _build_strip, _build_waterfronts, _build_plazas, _build_uptown, _build_motor_mile, _build_nightlife, _build_west_end, _build_old_town, _build_slip_side, _build_old_wharf, _build_south_docks, _build_east_shore]:
		var before: int = get_child_count()
		_pending_blocks.clear()
		builder.call()
		for pending: Dictionary in _pending_blocks:
			_target = pending["target"]
			_xf = pending["xf"]
			_street_life(pending["rect"])
		for index: int in range(before, get_child_count()):
			var node: Node = get_child(index)
			if node is Node3D and not node is Light3D:
				_finish(node as Node3D)
	_build_plots()
	# Walk-in businesses last: each interior is its own node so its lamp only lights it.
	for shop: Dictionary in Interiors.SHOPS:
		Interiors.new(self, shop).build_interior()
	# Map 0.8: street-frontage infill (prefab buildings, aprons, alleys) before the clutter pass.
	city_fill = CityFill.new(self)
	city_fill.build()
	CityDetail.new(self).build()
	_xf = Transform3D.IDENTITY
	_xf_yaw = 0.0
	set_dusk(dusk)
	# The practice wheelman's loop: the downtown ring, a point every ~11 m in the right-hand
	# lane (clockwise seen from above). wheelman_path() gets there along the streets.
	var corners: Array[Vector2] = [Vector2(-85, -85), Vector2(85, -85), Vector2(85, 85), Vector2(-85, 85)]
	for index: int in range(corners.size()):
		var from: Vector2 = corners[index]
		var to: Vector2 = corners[(index + 1) % corners.size()]
		for step: int in range(16):
			var at: Vector2 = from.lerp(to, step / 16.0)
			road_loop.append(Vector3(at.x, 0, at.y))

# --- Plots for the trademark buildings, lifts and mode dressing (0.6) -----------------------

## Reserved footprints for the trademark buildings. `center` is the plot's centre on the ground
## (world x/z), `size` is (width along the facade, depth), `yaw` turns the plot's local frame
## (+Z out of the front door, +X along the facade; the frame Interiors and BuildingKit use) and
## `front` is the world direction the facade faces. Each has a builder in scripts/buildings/<key>.gd
## (`static func build(world, plot)`), called once, in PLOT_ORDER, after the districts.
const PLOTS: Dictionary = {
	"highrise": {"center": Vector2(125, -176), "size": Vector2(30, 30), "yaw": 0.0, "front": Vector3.BACK, "district": "UPTOWN"},
	"hotel": {"center": Vector2(175, -176), "size": Vector2(30, 28), "yaw": 0.0, "front": Vector3.BACK, "district": "UPTOWN"},
	"garage": {"center": Vector2(202, 10), "size": Vector2(30, 28), "yaw": 0.0, "front": Vector3.BACK, "district": "MOTOR MILE"},
	"motel": {"center": Vector2(170, 10), "size": Vector2(32, 28), "yaw": 0.0, "front": Vector3.BACK, "district": "MOTOR MILE"},
	"burger": {"center": Vector2(120, 62), "size": Vector2(30, 26), "yaw": PI, "front": Vector3.FORWARD, "district": "MOTOR MILE"},
	"nightclub": {"center": Vector2(98, 244), "size": Vector2(32, 36), "yaw": PI, "front": Vector3.FORWARD, "district": "NIGHTLIFE"},
	"stripclub": {"center": Vector2(150, 244), "size": Vector2(30, 32), "yaw": PI, "front": Vector3.FORWARD, "district": "NIGHTLIFE"},
	"gunstore": {"center": Vector2(269, -66), "size": Vector2(26, 46), "yaw": -PI * 0.5, "front": Vector3.LEFT, "district": "EAST SHORE"},
}
const PLOT_ORDER: Array[String] = ["highrise", "hotel", "garage", "motel", "nightclub", "stripclub", "burger", "gunstore"]
const PLOT_BUILDERS: Dictionary = {
	"highrise": preload("res://scripts/buildings/highrise.gd"),
	"hotel": preload("res://scripts/buildings/hotel.gd"),
	"garage": preload("res://scripts/buildings/garage.gd"),
	"motel": preload("res://scripts/buildings/motel.gd"),
	"nightclub": preload("res://scripts/buildings/nightclub.gd"),
	"stripclub": preload("res://scripts/buildings/stripclub.gd"),
	"burger": preload("res://scripts/buildings/burger.gd"),
	"gunstore": preload("res://scripts/buildings/gunstore.gd"),
}

## Plot key -> the Node3D its builder made, and the footprint_polys indices it registered.
var plot_nodes: Dictionary = {}
var plot_footprints: Dictionary = {}
## "free_roam", "contract" or "online" (see set_mode).
var mode: String = "free_roam"
## interactable_doors indices of the gun store's range door, yard door and yard gate.
var gun_doors: Array[int] = []
## Lifts: {index, label, car, floors (landing heights), floor (destination), from_floor, t (0..1),
## doors (per landing: leaf nodes), open (per landing 0..1), buttons, panel}.
var lifts: Array[Dictionary] = []

func _build_plots() -> void:
	for key: String in PLOT_ORDER:
		var before_nodes: int = get_child_count()
		var before_footprints: int = footprint_polys.size()
		_begin_building("plot", true, key)
		PLOT_BUILDERS[key].build(self, PLOTS[key])
		_end_building()
		var indices: Array[int] = []
		for index: int in range(before_footprints, footprint_polys.size()):
			indices.append(index)
		plot_footprints[key] = indices
		for index: int in range(before_nodes, get_child_count()):
			var node: Node = get_child(index)
			if node is Node3D and not node is Light3D:
				if not plot_nodes.has(key):
					plot_nodes[key] = node
				_finish(node as Node3D)
	_xf = Transform3D.IDENTITY
	_xf_yaw = 0.0
	set_physics_process(not lifts.is_empty())

## Switches the city between game modes. The gun store is a real business in every mode; in
## contract and online rounds its range doors and yard gate are locked shut (so it reads as a
## closed range), and in free roam they are open. The range dressing (targets, rack, painted
## lines, labels) belongs to the Armory node: main.gd calls armory.set_mode(mode) too.
func set_mode(new_mode: String) -> void:
	mode = new_mode
	var closed: bool = new_mode != "free_roam"
	for index: int in gun_doors:
		var entry: Dictionary = interactable_doors[index]
		entry["locked"] = closed
		set_door_open(index, not closed, true)

## Locked doors ignore E and network events (set_mode locks the gun store's range in matches).
func is_door_locked(index: int) -> bool:
	return index >= 0 and index < interactable_doors.size() and bool(interactable_doors[index].get("locked", false))

# --- Lifts ---------------------------------------------------------------------------------

## Sends lift `index` to landing `floor` (ignored while it is travelling or if the floor does not exist).
func call_lift(index: int, floor: int) -> void:
	if index < 0 or index >= lifts.size():
		return
	var lift: Dictionary = lifts[index]
	if floor < 0 or floor >= (lift["floors"] as Array).size():
		return
	if float(lift["t"]) < 1.0:
		lift["queued"] = floor
		return
	if floor == int(lift["floor"]):
		return
	lift["from_floor"] = lift["floor"]
	lift["floor"] = floor
	lift["t"] = 0.0
	lift["queued"] = -1

## Plain-data state for the network: {floor (destination), from (departure landing), t (0..1 trip
## progress, 1 = arrived), y (car height), moving}.
func lift_state(index: int) -> Dictionary:
	var lift: Dictionary = lifts[index]
	return {"floor": int(lift["floor"]), "from": int(lift["from_floor"]), "t": float(lift["t"]), "y": (lift["car"] as Node3D).position.y, "moving": float(lift["t"]) < 1.0}

## Puts lift `index` at `t` of the way from landing `from_floor` (default: where it is coming from)
## to landing `floor`.
func set_lift_state(index: int, floor: int, t: float, from_floor: int = -1) -> void:
	if index < 0 or index >= lifts.size():
		return
	var lift: Dictionary = lifts[index]
	var count: int = (lift["floors"] as Array).size()
	lift["floor"] = clampi(floor, 0, count - 1)
	if from_floor >= 0:
		lift["from_floor"] = clampi(from_floor, 0, count - 1)
	lift["t"] = clampf(t, 0.0, 1.0)
	_place_lift(lift, 0.0)

## Metres per second of the lifts' car, and how long the doors take to slide.
const LIFT_SPEED: float = 2.6
const LIFT_DOOR_SPEED: float = 1.6

func _physics_process(delta: float) -> void:
	for lift: Dictionary in lifts:
		_place_lift(lift, delta)

func _place_lift(lift: Dictionary, delta: float) -> void:
	var floors: Array = lift["floors"]
	var from_y: float = float(floors[int(lift["from_floor"])])
	var to_y: float = float(floors[int(lift["floor"])])
	if float(lift["t"]) < 1.0 and delta > 0.0:
		var duration: float = maxf(2.2, absf(to_y - from_y) / LIFT_SPEED)
		# The doors must be shut before the car leaves.
		var shut: bool = true
		for amount: float in lift["open"]:
			shut = shut and amount < 0.02
		if shut:
			lift["t"] = minf(1.0, float(lift["t"]) + delta / duration)
			if float(lift["t"]) >= 1.0 and int(lift.get("queued", -1)) >= 0:
				var queued: int = int(lift["queued"])
				lift["queued"] = -1
				call_lift(int(lift["index"]), queued)
	var t: float = float(lift["t"])
	var eased: float = t * t * (3.0 - 2.0 * t)
	var car: AnimatableBody3D = lift["car"]
	car.position.y = lerpf(from_y, to_y, eased)
	# Landing doors slide open on the floor the car is at, once it has stopped.
	var open: Array = lift["open"]
	var doors: Array = lift["doors"]
	for landing: int in range(open.size()):
		var target: float = 1.0 if (t >= 1.0 and landing == int(lift["floor"])) else 0.0
		if delta <= 0.0:
			open[landing] = target
		else:
			open[landing] = move_toward(float(open[landing]), target, delta * LIFT_DOOR_SPEED)
		for leaf: Node3D in doors[landing]:
			leaf.position.x = float(leaf.get_meta("closed_x")) + float(leaf.get_meta("slide")) * float(open[landing])
	# The car's own panel button rides with the car.
	var panel: int = int(lift.get("panel", -1))
	if panel >= 0:
		var local: Vector3 = lift["panel_local"]
		interactable_doors[panel]["position"] = (car.get_parent() as Node3D).to_global(Vector3(local.x, car.position.y, local.z))

func map_bounds() -> Rect2:
	var bounds: Rect2 = Rect2(Vector2(-HALF, -HALF), Vector2(HALF * 2.0, HALF * 2.0))
	for poly: PackedVector2Array in land:
		for point: Vector2 in poly:
			bounds = bounds.expand(point)
	return bounds.grow(6.0)

func district_at(at: Vector3) -> String:
	var point: Vector2 = Vector2(at.x, at.z)
	for district: Dictionary in districts:
		for poly: PackedVector2Array in district["polys"]:
			if Geometry2D.is_point_in_polygon(point, poly):
				return str(district["name"])
	return "PORT HALCYON"

## True if the x/z point is on land (not in the sea, the canal or the slip).
func is_on_land(at: Vector3) -> bool:
	return _on_land(Vector2(at.x, at.z))

## Map layers for the radar and the full map: land, district tints, plazas, bridges, roads,
## buildings and walk-in doors. The caller clears the canvas to the sea colour first.
func draw_map(canvas: Control, to_screen: Callable, scale: float) -> void:
	for poly: PackedVector2Array in land:
		canvas.draw_colored_polygon(_screen_poly(poly, to_screen), Color(0.2, 0.21, 0.2))
	for district: Dictionary in districts:
		var tint: Color = district["color"]
		tint.a = 0.2 if str(district["crew"]) != "" else 0.07
		for poly: PackedVector2Array in district["polys"]:
			canvas.draw_colored_polygon(_screen_poly(poly, to_screen), tint)
	for plaza: PackedVector2Array in plazas:
		canvas.draw_colored_polygon(_screen_poly(plaza, to_screen), Color(0.36, 0.35, 0.31))
	var road_color: Color = Color(0.4, 0.42, 0.43)
	for bridge: Dictionary in bridges:
		var rect: Rect2 = bridge["rect"]
		canvas.draw_rect(Rect2(to_screen.call(Vector3(rect.position.x, 0, rect.position.y)), rect.size * scale), Color(0.52, 0.36, 0.26))
	if _road_boxes.size() != roads.size():
		_road_boxes.clear()
		for road: Dictionary in roads:
			var points: PackedVector2Array = road["points"]
			var box: Rect2 = Rect2(points[0], Vector2.ZERO)
			for point: Vector2 in points:
				box = box.expand(point)
			_road_boxes.append(box.grow(float(road["width"])))
	var canvas_rect: Rect2 = Rect2(Vector2.ZERO, canvas.size)
	for index: int in range(roads.size()):
		var road: Dictionary = roads[index]
		var box: Rect2 = _road_boxes[index]
		var corner_a: Vector2 = to_screen.call(Vector3(box.position.x, 0, box.position.y))
		var corner_b: Vector2 = to_screen.call(Vector3(box.end.x, 0, box.end.y))
		if not canvas_rect.intersects(Rect2(corner_a, Vector2.ZERO).expand(corner_b)):
			continue
		var line: PackedVector2Array = _screen_poly(road["points"], to_screen)
		canvas.draw_polyline(line, road_color, maxf(float(road["width"]) * scale, 1.5))
	# Only the buildings that can show on this canvas are drawn: the radar is redrawn every frame and the
	# city has hundreds of footprints, each of them a canvas draw call.
	var view: Rect2 = Rect2(Vector2.ZERO, canvas.size)
	for index: int in range(footprint_polys.size()):
		var bounds: Rect2 = footprints[index]
		var at: Vector2 = to_screen.call(Vector3(bounds.get_center().x, 0, bounds.get_center().y))
		var reach: float = bounds.size.length() * scale
		if not view.grow(reach).has_point(at):
			continue
		canvas.draw_colored_polygon(_screen_poly(footprint_polys[index], to_screen), Color(0.27, 0.29, 0.31))
	if scale > 0.9:
		for door: Dictionary in interactable_doors:
			var dot: Vector2 = to_screen.call(door["position"])
			if view.grow(4.0).has_point(dot):
				canvas.draw_circle(dot, maxf(scale * 1.2, 2.0), Color(0.45, 0.95, 0.6, 0.9))

## Swings a walk-in door open or shut (the garage's shutter rolls). Doors are physical: a
## shut door blocks bodies and bullets, an open one leaves the doorway clear.
func set_door_open(index: int, open: bool, force: bool = false) -> void:
	if index < 0 or index >= interactable_doors.size():
		return
	# Lift landings are worked by call_lift; locked doors (the gun store's range in matches) stay shut.
	if str(interactable_doors[index]["kind"]) == "lift":
		return
	if not force and bool(interactable_doors[index].get("locked", false)):
		return
	interactable_doors[index]["open"] = open
	for leaf: Node3D in _door_nodes[index]:
		var tween: Tween = leaf.create_tween()
		if leaf.has_meta("roller"):
			tween.tween_property(leaf, "position:y", float(leaf.get_meta("roller")) if open else 0.0, 0.8).set_trans(Tween.TRANS_SINE)
		else:
			var closed: float = float(leaf.get_meta("closed_yaw"))
			tween.tween_property(leaf, "rotation:y", closed + (float(leaf.get_meta("swing")) if open else 0.0), 0.35).set_trans(Tween.TRANS_SINE)

func toggle_door(index: int) -> void:
	if index < 0 or index >= interactable_doors.size():
		return
	var entry: Dictionary = interactable_doors[index]
	if str(entry["kind"]) == "lift":
		# A landing button calls the car to its floor; the car's own panel sends it to the next floor.
		var lift: Dictionary = lifts[int(entry["lift"])]
		if int(entry["floor"]) >= 0:
			call_lift(int(entry["lift"]), int(entry["floor"]))
		else:
			call_lift(int(entry["lift"]), (int(lift["floor"]) + 1) % (lift["floors"] as Array).size())
		return
	set_door_open(index, not bool(entry["open"]))

## Puts every shot-out shop window back (e.g. between rounds).
func reset_glass() -> void:
	for glass: Dictionary in glass_panes:
		(glass["body"] as Node).call("restore")

## The nearest walk-in door within `radius` metres of `at` (-1 if none). Doors on other floors of a
## building (their position.y is the floor's height) are out of reach.
func door_near(at: Vector3, radius: float = 2.2) -> int:
	var best: int = -1
	var best_distance: float = radius
	for door: Dictionary in interactable_doors:
		if absf(at.y - float(door["position"].y)) > 3.2:
			continue
		var distance: float = Vector2(at.x - door["position"].x, at.z - door["position"].z).length()
		if distance < best_distance:
			best_distance = distance
			best = int(door["index"])
	return best

## Shortest drive between two points along the street network, as a polyline from the
## point on the road nearest `from` to the point on the road nearest `to` (y = 0).
## Empty if unreachable.
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	return _route_raw(from, to)

func _route_raw(from: Vector3, to: Vector3) -> PackedVector3Array:
	if _graph_points.is_empty():
		_build_road_graph()
	var path: PackedVector3Array = PackedVector3Array()
	var start: Array = _nearest_graph_edge(Vector2(from.x, from.z))
	var goal: Array = _nearest_graph_edge(Vector2(to.x, to.z))
	if start.is_empty() or goal.is_empty():
		return path
	var start_at: Vector2 = start[2]
	var goal_at: Vector2 = goal[2]
	# Same stretch of road: drive straight there.
	if (start[0] == goal[0] and start[1] == goal[1]) or (start[0] == goal[1] and start[1] == goal[0]):
		path.append(Vector3(start_at.x, 0, start_at.y))
		path.append(Vector3(goal_at.x, 0, goal_at.y))
		return path
	var distance: PackedFloat32Array = PackedFloat32Array()
	var previous: PackedInt32Array = PackedInt32Array()
	distance.resize(_graph_points.size())
	previous.resize(_graph_points.size())
	distance.fill(INF)
	previous.fill(-1)
	var open: Array[int] = []
	for end: int in [start[0], start[1]]:
		distance[end] = start_at.distance_to(_graph_points[end])
		open.append(end)
	var closed: Dictionary = {}
	while not open.is_empty():
		var best: int = 0
		for index: int in range(1, open.size()):
			if distance[open[index]] < distance[open[best]]:
				best = index
		var current: int = open[best]
		open.remove_at(best)
		if closed.has(current):
			continue
		closed[current] = true
		var links: Dictionary = _graph_links[current]
		for neighbour: int in links:
			var through: float = distance[current] + float(links[neighbour])
			if through < distance[neighbour]:
				distance[neighbour] = through
				previous[neighbour] = current
				open.append(neighbour)
	# Arrive through whichever end of the goal's stretch of road is closer overall.
	var last: int = goal[0]
	if distance[goal[1]] + _graph_points[goal[1]].distance_to(goal_at) < distance[goal[0]] + _graph_points[goal[0]].distance_to(goal_at):
		last = goal[1]
	if distance[last] == INF:
		return path
	path.append(Vector3(goal_at.x, 0, goal_at.y))
	var cursor: int = last
	while cursor >= 0:
		path.insert(0, Vector3(_graph_points[cursor].x, 0.0, _graph_points[cursor].y))
		cursor = previous[cursor]
	path.insert(0, Vector3(start_at.x, 0, start_at.y))
	return path

## The practice wheelman's route from anywhere: along the streets to the downtown ring, then
## round road_loop. (Pure pursuit straight at the ring from a far-off HQ would cut through
## buildings on this map.)
func wheelman_path(from: Vector3) -> PackedVector3Array:
	var path: PackedVector3Array = route(from, road_loop[0])
	path.append_array(road_loop)
	return path

## Length in metres of `route(from, to)` plus the walk from each point to its road (INF if
## there is no way through).
func route_length(from: Vector3, to: Vector3) -> float:
	# The street-graph distance (the crews' fairness metric).
	var path: PackedVector3Array = _route_raw(from, to)
	if path.is_empty():
		return INF
	var total: float = Vector2(from.x - path[0].x, from.z - path[0].z).length() + Vector2(to.x - path[path.size() - 1].x, to.z - path[path.size() - 1].z).length()
	for index: int in range(path.size() - 1):
		total += path[index].distance_to(path[index + 1])
	return total

func _screen_poly(poly: PackedVector2Array, to_screen: Callable) -> PackedVector2Array:
	var screen: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in poly:
		screen.append(to_screen.call(Vector3(point.x, 0, point.y)))
	return screen

# --- Lighting ------------------------------------------------------------------

## Potato mode, for bare-minimum PCs (the settings toggle lives in main.gd). Hides the
## collision-free dressing in the "potato_optional" group (posters, bags, cardboard, leaves,
## bunting, rooftop plant, oil stains...) and draws the remaining small detail to 60 % of its
## range. Nothing with collision is hidden or removed, so cover, routes and gameplay are the same
## in both modes (multiplayer fairness); colliders never depend on visibility anyway.
func set_potato_mode(enabled: bool) -> void:
	potato_mode = enabled
	for node: Node in get_tree().get_nodes_in_group("potato_optional"):
		if node is Node3D and is_ancestor_of(node):
			(node as Node3D).visible = not enabled
	for geometry: GeometryInstance3D in _detail_ranges:
		if not is_instance_valid(geometry):
			continue
		if not geometry.has_meta("full_range"):
			geometry.set_meta("full_range", geometry.visibility_range_end)
		geometry.visibility_range_end = float(geometry.get_meta("full_range")) * (0.6 if enabled else 1.0)

func set_dusk(value: bool) -> void:
	dusk = value
	var sky_material: ProceduralSkyMaterial = environment.sky.sky_material as ProceduralSkyMaterial
	if dusk:
		# Violet haze and deep sky keep contrast; the orange lives in the sun and the neon.
		sky_material.sky_top_color = Color(0.06, 0.07, 0.2)
		sky_material.sky_horizon_color = Color(0.98, 0.5, 0.28)
		sky_material.ground_horizon_color = Color(0.36, 0.24, 0.3)
		sky_material.ground_bottom_color = Color(0.05, 0.05, 0.08)
		sky_material.sky_curve = 0.09
		sky_material.sun_angle_max = 20.0
		# Enough fill that a player in shadow is still readable at combat range.
		environment.ambient_light_color = Color(0.4, 0.42, 0.62)
		environment.ambient_light_energy = 0.85
		environment.fog_light_color = Color(0.22, 0.2, 0.36)
		environment.fog_light_energy = 1.0
		environment.fog_density = 0.0026
		environment.fog_sky_affect = 0.25
		sun.rotation_degrees = Vector3(-14.0, -96.0, 0.0)
		sun.light_color = Color(1.0, 0.64, 0.4)
		sun.light_energy = 1.1
	else:
		sky_material.sky_top_color = Color(0.25, 0.40, 0.50)
		sky_material.sky_horizon_color = Color(0.70, 0.73, 0.69)
		sky_material.ground_horizon_color = Color(0.70, 0.73, 0.69)
		sky_material.ground_bottom_color = Color(0.30, 0.33, 0.30)
		sky_material.sky_curve = 0.20
		sky_material.sun_angle_max = 1.4
		environment.ambient_light_color = Color(0.73, 0.80, 0.86)
		environment.ambient_light_energy = 0.35
		environment.fog_light_color = Color(0.62, 0.68, 0.69)
		environment.fog_light_energy = 0.55
		environment.fog_density = 0.0018
		environment.fog_sky_affect = 1.0
		sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
		sun.light_color = Color(1.0, 0.93, 0.81)
		sun.light_energy = 0.8
	environment.glow_enabled = dusk
	for material: StandardMaterial3D in _glow_materials:
		material.emission_energy_multiplier = float(material.get_meta("energy")) * (1.0 if dusk else 0.35)
	for light: OmniLight3D in _lights:
		light.visible = dusk

func _build_environment() -> void:
	var world: WorldEnvironment = WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.glow_intensity = 0.7
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 0.95
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	world.environment = environment
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 95.0
	add_child(sun)

# --- Construction helpers ----------------------------------------------------------

func _begin(title: String) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = title.replace(" ", "")
	add_child(node)
	_target = node
	_xf = Transform3D.IDENTITY
	_xf_yaw = 0.0
	return node

## Starts a neighbourhood kit's node, placed by its KITS transform. Everything built until
## the next _begin/_place is authored in the kit's 0.4 coordinates.
func _place(kit: String, title: String) -> Node3D:
	var node: Node3D = _begin(title)
	_xf = kit_transform(kit)
	_xf_yaw = float(KITS[kit]["yaw"])
	node.transform = _xf
	return node

func kit_transform(kit: String) -> Transform3D:
	var spec: Dictionary = KITS[kit]
	var from: Vector2 = spec["from"]
	var to: Vector2 = spec["to"]
	return Transform3D(Basis(Vector3.UP, float(spec["yaw"])), Vector3(to.x, 0, to.y)) * Transform3D(Basis.IDENTITY, Vector3(-from.x, 0, -from.y))

## A kit's authored point in world x/z.
func _kp(kit: String, local: Vector2) -> Vector2:
	var at: Vector3 = kit_transform(kit) * Vector3(local.x, 0, local.y)
	return Vector2(at.x, at.z)

## A kit's outer frame in world space (grown by `margin`).
func _kit_poly(kit: String, margin: float = 0.0) -> PackedVector2Array:
	var from: Vector2 = KITS[kit]["from"]
	var half: Vector2 = (KITS[kit]["half"] as Vector2) + Vector2(margin, margin)
	var poly: PackedVector2Array = PackedVector2Array()
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		poly.append(_kp(kit, from + corner * half))
	return poly

func _w(at: Vector3) -> Vector3:
	return _xf * at

func _w2(at: Vector2) -> Vector2:
	var world: Vector3 = _xf * Vector3(at.x, 0, at.y)
	return Vector2(world.x, world.z)

## Records a building outline (in the current build space) for the map.
func _footprint(rect: Rect2) -> void:
	var outline: PackedVector2Array = PackedVector2Array()
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		outline.append(_w2(corner))
	footprint_polys.append(outline)
	var bounds: Rect2 = Rect2(outline[0], Vector2.ZERO)
	for point: Vector2 in outline:
		bounds = bounds.expand(point)
	footprints.append(bounds)
	if _building_open.is_empty():
		buildings.append({"name": "", "kind": "solid", "enterable": false, "footprints": [footprint_polys.size() - 1]})
	else:
		(_building_open["footprints"] as Array).append(footprint_polys.size() - 1)

## Opens a building record: every outline registered until `_end_building()` belongs to it.
func _begin_building(kind: String, enterable: bool, title: String = "") -> void:
	_building_open = {"name": title, "kind": kind, "enterable": enterable, "footprints": []}
	buildings.append(_building_open)

func _end_building() -> void:
	_building_open = {}

func _on_land(at: Vector2) -> bool:
	for poly: PackedVector2Array in land:
		if Geometry2D.is_point_in_polygon(at, poly):
			return true
	return false

func _finish(node: Node3D) -> void:
	if node.has_meta("finished"):
		return
	node.set_meta("finished", true)
	_batch_static_meshes(node)
	# Remaining one-off boxes (walls, signs, kerbs) merge into one mesh per material.
	MeshMerge.merge_children(node)
	# The sun's shadow splits then draw the node's static casters in one call each.
	MeshMerge.shadow_proxy(node)

## A named district for the map and the radar. `polys` overrides the rectangle's shape.
func _district(title: String, rect: Rect2, color: Color, crew: String, polys: Array = []) -> void:
	var shapes: Array[PackedVector2Array] = []
	for poly: Variant in polys:
		shapes.append(poly as PackedVector2Array)
	if shapes.is_empty():
		shapes.append(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]))
	districts.append({"name": title, "rect": rect, "color": color, "crew": crew, "polys": shapes, "label_at": Vector3(rect.get_center().x, 0, rect.position.y + 10.0)})

func _landmark(title: String, at: Vector3, neutral: bool = true) -> void:
	landmarks.append({"name": title, "at": _w(at), "neutral": neutral})

func _batch_static_meshes(parent: Node3D) -> void:
	# Repeated windows, kerbs and road paint share one instanced draw call.
	var groups: Dictionary = {}
	for child: Node in parent.get_children():
		if child is MeshInstance3D:
			var instance: MeshInstance3D = child as MeshInstance3D
			var key: String = str(instance.mesh.get_instance_id()) + ":" + str(instance.material_override.get_instance_id())
			if not groups.has(key):
				groups[key] = []
			var group: Array = groups[key]
			group.append(instance)
	for key: String in groups:
		var group: Array = groups[key]
		if group.size() < 3:
			continue
		var first: MeshInstance3D = group[0] as MeshInstance3D
		var batch: MultiMeshInstance3D = MultiMeshInstance3D.new()
		var multimesh: MultiMesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = first.mesh
		multimesh.instance_count = group.size()
		batch.multimesh = multimesh
		batch.material_override = first.material_override
		batch.cast_shadow = first.cast_shadow
		for index: int in range(group.size()):
			var instance: MeshInstance3D = group[index] as MeshInstance3D
			multimesh.set_instance_transform(index, instance.transform)
			instance.visible = false
			instance.queue_free()
		parent.add_child(batch)

func _material(color: Color, roughness: float = 0.9, tex: String = "") -> StandardMaterial3D:
	if not tex.is_empty():
		return _tex.material(tex, color, roughness)
	var key: String = str(color) + str(roughness)
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	_materials[key] = material
	return material

## Self-lit surfaces: lit windows, lamps, neon tubes and lanterns. Dimmed in daylight.
func _glow(color: Color, energy: float = 1.6) -> StandardMaterial3D:
	var key: String = "glow" + str(color) + str(energy)
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.3)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.set_meta("energy", energy)
	_materials[key] = material
	_glow_materials.append(material)
	return material

func _box(at: Vector3, size: Vector3, color: Color, solid: bool = false, tex: String = "") -> MeshInstance3D:
	return _box_with(at, size, _material(color, 0.9, tex), solid)

func _box_with(at: Vector3, size: Vector3, material: Material, solid: bool = false, angle: float = 0.0) -> MeshInstance3D:
	var key: String = str(size)
	var mesh: BoxMesh
	if _meshes.has(key):
		mesh = _meshes[key] as BoxMesh
	else:
		mesh = BoxMesh.new()
		mesh.size = size
		_meshes[key] = mesh
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.rotation.y = angle
	_target.add_child(instance)
	_note_blocker(at, size, angle)
	if solid:
		_collider(at, size, angle)
	return instance

## Records a box's world x/z bounds for the fill pass (small flat decals are ignored).
func _note_blocker(at: Vector3, size: Vector3, angle: float = 0.0) -> void:
	var area: float = size.x * size.z
	if _blockers_off or (size.y < 0.5 and area < 25.0) or area > 40000.0:
		return
	var world_at: Vector3 = _xf * at
	var yaw: float = angle + _xf_yaw
	var eye: bool = world_at.y - size.y * 0.5 <= 1.3 and world_at.y + size.y * 0.5 >= 1.3
	# A long turned box (a diagonal quay face, a fence) is recorded in short pieces, so its bounds
	# do not swallow the ground beside it.
	var length: float = maxf(size.x, size.z)
	if length > 8.0 and minf(size.x, size.z) < 4.0 and absf(sin(2.0 * yaw)) > 0.05:
		var along: Vector2 = Vector2(cos(yaw), -sin(yaw)) if size.x >= size.z else Vector2(sin(yaw), cos(yaw))
		var pieces: int = ceili(length / 5.0)
		for piece: int in range(pieces):
			var offset: float = (float(piece) + 0.5) / pieces * length - length * 0.5
			var chunk: Vector2 = Vector2(world_at.x, world_at.z) + along * offset
			var half_length: float = length / pieces * 0.5
			var half_thick: float = minf(size.x, size.z) * 0.5
			var reach_x: float = absf(along.x) * half_length + absf(along.y) * half_thick
			var reach_z: float = absf(along.y) * half_length + absf(along.x) * half_thick
			_add_blocker(Rect2(chunk.x - reach_x, chunk.y - reach_z, reach_x * 2.0, reach_z * 2.0), size.y, area, eye)
		return
	var ex: float = absf(cos(yaw)) * size.x * 0.5 + absf(sin(yaw)) * size.z * 0.5
	var ez: float = absf(sin(yaw)) * size.x * 0.5 + absf(cos(yaw)) * size.z * 0.5
	_add_blocker(Rect2(world_at.x - ex, world_at.z - ez, ex * 2.0, ez * 2.0), size.y, area, eye)

func _add_blocker(rect: Rect2, height: float, area: float, eye: bool = false) -> void:
	_blockers.append(rect)
	if eye:
		eye_blockers.append(rect)
	if height >= 0.5 and area < 400.0:
		var low: Vector2i = Vector2i(floori(rect.position.x / 16.0), floori(rect.position.y / 16.0))
		var high: Vector2i = Vector2i(floori(rect.end.x / 16.0), floori(rect.end.y / 16.0))
		for cx: int in range(low.x, high.x + 1):
			for cy: int in range(low.y, high.y + 1):
				var key: Vector2i = Vector2i(cx, cy)
				if not _solid_grid.has(key):
					_solid_grid[key] = []
				(_solid_grid[key] as Array).append(rect)

## True if a tall solid the builders placed (prop, wall, container stack) lies within `radius` of `at`.
func solid_near(at: Vector2, radius: float) -> bool:
	var key: Vector2i = Vector2i(floori(at.x / 16.0), floori(at.y / 16.0))
	if not _solid_grid.has(key):
		return false
	for rect: Rect2 in _solid_grid[key]:
		if rect.grow(radius).has_point(at):
			return true
	return false

## Invisible collision only (sea wall height, canal railings, fences).
func _collider(at: Vector3, size: Vector3, angle: float = 0.0) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.position = at
	body.rotation.y = angle
	body.add_child(collision)
	_target.add_child(body)
	_note_blocker(at, size, angle)

func _cylinder(at: Vector3, radius: float, height: float, color: Color, segments: int = 8, material: Material = null) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material if material != null else _material(color)
	instance.position = at
	_target.add_child(instance)
	if height >= 0.5:
		_note_blocker(at, Vector3(radius * 2.0, height, radius * 2.0))
	return instance

func _label(words: String, at: Vector3, font_size: int, color: Color, angle: float = 0.0, pixel: float = 0.017) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = words
	label.font_size = font_size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_modulate = Color(0.12, 0.15, 0.17)
	label.outline_size = 4
	label.position = at
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.rotation.y = angle
	label.no_depth_test = false
	label.visibility_range_end = 120.0
	_target.add_child(label)
	return label

## Neon sign: glowing text on a dark board, optionally lighting the street around it.
func _neon(words: String, at: Vector3, angle: float, color: Color, font_size: int = 72, light: bool = false, vertical: bool = false) -> void:
	var text: String = words
	if vertical:
		var letters: PackedStringArray = PackedStringArray()
		for index: int in range(words.length()):
			letters.append(words[index])
		text = "\n".join(letters)
	var label: Label3D = _label(text, at, font_size, color.lightened(0.25), angle, 0.014)
	label.outline_modulate = color.darkened(0.45)
	label.outline_size = 12
	var lines: int = text.count("\n") + 1
	var longest: int = 0
	for line: String in text.split("\n"):
		longest = maxi(longest, line.length())
	var board: Vector2 = Vector2(longest * font_size * 0.0095 + 0.6, lines * font_size * 0.0165 + 0.35)
	var back: Vector3 = Vector3(sin(angle), 0, cos(angle))
	_box_with(at - back * 0.09, Vector3(board.x, board.y, 0.12), _material(Color(0.06, 0.05, 0.08)), false, angle)
	if light and _lights.size() < 9:
		var lamp: OmniLight3D = OmniLight3D.new()
		lamp.light_color = color
		lamp.light_energy = 1.6
		lamp.omni_range = 11.0
		lamp.shadow_enabled = false
		lamp.light_cull_mask = 0xFFFFF & ~(1 << (CLUTTER_LAYER - 1))
		lamp.position = at + back * 1.6
		_target.add_child(lamp)
		_lights.append(lamp)

## Beveled raised slab (sidewalks, plazas, block plinths). The bevel is part of the
## collision hull: no square vertical curb to snag a character capsule or the sedan.
func _slab(rect: Rect2, color: Color, tex: String = "tiles", height: float = 0.16, bevel: float = 0.45) -> void:
	var hx: float = rect.size.x * 0.5
	var hz: float = rect.size.y * 0.5
	var corners: PackedVector3Array = PackedVector3Array([
		Vector3(-hx, 0.0, -hz), Vector3(hx, 0.0, -hz), Vector3(hx, 0.0, hz), Vector3(-hx, 0.0, hz),
		Vector3(-hx + bevel, height, -hz + bevel), Vector3(hx - bevel, height, -hz + bevel),
		Vector3(hx - bevel, height, hz - bevel), Vector3(-hx + bevel, height, hz - bevel)
	])
	_hull(Vector3(rect.get_center().x, 0, rect.get_center().y), corners, _material(color, 0.9, tex))
	var top: PackedVector2Array = PackedVector2Array()
	for corner: Vector2 in [Vector2(-hx + bevel, -hz + bevel), Vector2(hx - bevel, -hz + bevel), Vector2(hx - bevel, hz - bevel), Vector2(-hx + bevel, hz - bevel)]:
		top.append(_w2(rect.get_center() + corner))
	_slab_tops.append({"poly": top, "height": height})

## Walking-surface height at a world x/z from the recorded slabs (0 on open ground or road).
func surface_height(at: Vector2) -> float:
	var best: float = 0.0
	for slab: Dictionary in _slab_tops:
		if float(slab["height"]) > best and Geometry2D.is_point_in_polygon(at, slab["poly"]):
			best = float(slab["height"])
	return best

## A raised slab turned by `yaw` (the fill pass's lot aprons): same bevelled hull as `_slab`.
func _slab_rot(center: Vector2, size: Vector2, yaw: float, color: Color, tex: String = "tiles", height: float = 0.16, bevel: float = 0.45) -> void:
	var hx: float = size.x * 0.5
	var hz: float = size.y * 0.5
	var corners: PackedVector3Array = PackedVector3Array([
		Vector3(-hx, 0.0, -hz), Vector3(hx, 0.0, -hz), Vector3(hx, 0.0, hz), Vector3(-hx, 0.0, hz),
		Vector3(-hx + bevel, height, -hz + bevel), Vector3(hx - bevel, height, -hz + bevel),
		Vector3(hx - bevel, height, hz - bevel), Vector3(-hx + bevel, height, hz - bevel)
	])
	_hull(Vector3(center.x, 0, center.y), corners, _material(color, 0.9, tex), yaw)
	var top: PackedVector2Array = PackedVector2Array()
	var basis: Basis = Basis(Vector3.UP, yaw)
	for corner: Vector2 in [Vector2(-hx + bevel, -hz + bevel), Vector2(hx - bevel, -hz + bevel), Vector2(hx - bevel, hz - bevel), Vector2(-hx + bevel, hz - bevel)]:
		var turned: Vector3 = basis * Vector3(corner.x, 0, corner.y)
		top.append(_w2(center + Vector2(turned.x, turned.z)))
	_slab_tops.append({"poly": top, "height": height})

func _hull(at: Vector3, corners: PackedVector3Array, material: Material, yaw: float = 0.0) -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces: Array[PackedInt32Array] = [
		PackedInt32Array([4, 7, 6, 5]), PackedInt32Array([0, 4, 5, 1]),
		PackedInt32Array([1, 5, 6, 2]), PackedInt32Array([2, 6, 7, 3]),
		PackedInt32Array([3, 7, 4, 0])
	]
	for face: PackedInt32Array in faces:
		var normal: Vector3 = (corners[face[1]] - corners[face[0]]).cross(corners[face[2]] - corners[face[0]]).normalized()
		# Godot's front faces use clockwise winding, normals point outward.
		for corner_index: int in [0, 2, 1, 0, 3, 2]:
			surface.set_normal(normal)
			surface.add_vertex(corners[face[corner_index]])
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.material_override = material
	instance.position = at
	instance.rotation.y = yaw
	_target.add_child(instance)
	var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	shape.points = corners
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	var body: StaticBody3D = StaticBody3D.new()
	body.position = at
	body.rotation.y = yaw
	body.add_child(collision)
	_target.add_child(body)

func _walkway(at: Vector3, length: float, color: Color) -> void:
	_slab(Rect2(at.x - 2.4, at.z - length * 0.5, 4.8, length), color, "tiles")

## Generic city building with windows on every face (some lit), a roof cap and an optional
## street sign. `front` is the outward normal of the entrance facade.
func _tower(center: Vector2, size: Vector3, color: Color, tex: String, front: Vector3 = Vector3.BACK, sign_text: String = "", sign_color: Color = Color(0.94, 0.86, 0.64), roof: Color = Color(0.29, 0.31, 0.30), lit: float = 0.35, enter: String = "") -> void:
	# A prefab kind in `enter` makes this hand-placed business an enterable building (Map 0.8).
	if enter != "" and _tower_prefab(enter, center, size, color, front, sign_text):
		return
	var at: Vector3 = Vector3(center.x, 0, center.y)
	_footprint(Rect2(center.x - size.x * 0.5, center.y - size.z * 0.5, size.x, size.z))
	_box(at + Vector3(0, size.y * 0.5, 0), size, color, true, tex)
	_box(at + Vector3(0, 0.55, 0), Vector3(size.x + 0.14, 1.1, size.z + 0.14), color.darkened(0.3), false, tex)
	_box(at + Vector3(0, size.y + 0.16, 0), Vector3(size.x + 0.45, 0.32, size.z + 0.45), roof, false, "roof")
	_roofs.append({"center": _w2(center), "size": size, "yaw": _xf_yaw, "top": size.y + 0.32, "front": _xf.basis * front, "business": not sign_text.is_empty()})
	var glass: StandardMaterial3D = _material(Color(0.16, 0.24, 0.29), 0.3)
	var warm: StandardMaterial3D = _glow(Color(1.0, 0.78, 0.46), 1.3)
	var floors: int = int((size.y - 1.2) / 3.1)
	for face: Vector3 in [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT]:
		var along_x: bool = absf(face.z) > 0.5
		var span: float = size.x if along_x else size.z
		var depth: float = size.z if along_x else size.x
		var columns: int = maxi(1, int(span / 3.4))
		for floor_index: int in range(floors):
			var y: float = 2.4 + float(floor_index) * 3.1
			if y + 1.0 > size.y:
				continue
			for column: int in range(columns):
				var t: float = -span * 0.5 + (column + 0.5) * span / columns
				var offset: Vector3 = (Vector3(t, 0, 0) if along_x else Vector3(0, 0, t)) + face * (depth * 0.5 + 0.045)
				var window_size: Vector3 = Vector3(1.55, 1.5, 0.1) if along_x else Vector3(0.1, 1.5, 1.55)
				var is_lit: bool = _rng.randf() < lit and floor_index > 0
				_box_with(at + offset + Vector3(0, y, 0), window_size, warm if is_lit else glass)
	if not sign_text.is_empty():
		var angle: float = atan2(front.x, front.z)
		var span_front: float = size.x if absf(front.z) > 0.5 else size.z
		var depth_front: float = size.z if absf(front.z) > 0.5 else size.x
		var sign_at: Vector3 = at + front * (depth_front * 0.5 + 0.3) + Vector3(0, 4.3, 0)
		_neon(sign_text, sign_at, angle, sign_color, clampi(int(span_front * 4.2), 40, 86))

func _lamp(at: Vector3, toward: Vector3) -> void:
	var steel: Color = Color(0.2, 0.22, 0.24)
	_box(at + Vector3(0, 3.5, 0), Vector3(0.14, 7, 0.14), steel, true)
	_box(at + toward * 0.7 + Vector3(0, 6.94, 0), Vector3(1.5 if absf(toward.x) > 0.5 else 0.12, 0.12, 0.12 if absf(toward.x) > 0.5 else 1.5), steel)
	_box_with(at + toward * 1.4 + Vector3(0, 6.86, 0), Vector3(0.6, 0.14, 0.34) if absf(toward.x) > 0.5 else Vector3(0.34, 0.14, 0.6), _glow(Color(1.0, 0.66, 0.28), 2.4))

## True if a world x/z point lies on a carriageway (within half a street's width + `margin` of its centre line).
## Street furniture and lamps use it to keep off the road surface.
func _on_carriageway(at: Vector2, margin: float = 0.0) -> bool:
	for road: Dictionary in roads:
		var half: float = float(road["width"]) * 0.5 + margin
		var points: PackedVector2Array = road["points"]
		for index: int in range(points.size() - 1):
			if at.distance_squared_to(Geometry2D.get_closest_point_to_segment(at, points[index], points[index + 1])) < half * half:
				return true
	return false

## True if a registered door lies within `radius` (x/z) of a world point.
func door_within(at: Vector2, radius: float) -> bool:
	for door: Dictionary in interactable_doors:
		var spot: Vector3 = door["position"]
		if Vector2(spot.x, spot.z).distance_to(at) < radius:
			return true
	return false

## Lamps along the edges of a block, one every `spacing` metres, facing the road.
func _block_lamps(rect: Rect2, spacing: float = 26.0) -> void:
	for side: int in range(4):
		var horizontal: bool = side < 2
		var length: float = rect.size.x if horizontal else rect.size.y
		var count: int = maxi(1, int(length / spacing))
		for index: int in range(count):
			var t: float = (index + 0.5) / count
			var at: Vector3
			var toward: Vector3
			match side:
				0:
					at = Vector3(rect.position.x + rect.size.x * t, 0.16, rect.position.y + 1.1)
					toward = Vector3.FORWARD
				1:
					at = Vector3(rect.position.x + rect.size.x * t, 0.16, rect.end.y - 1.1)
					toward = Vector3.BACK
				2:
					at = Vector3(rect.position.x + 1.1, 0.16, rect.position.y + rect.size.y * t)
					toward = Vector3.LEFT
				_:
					at = Vector3(rect.end.x - 1.1, 0.16, rect.position.y + rect.size.y * t)
					toward = Vector3.RIGHT
			if _on_land(_w2(Vector2(at.x, at.z))) and not door_within(_w2(Vector2(at.x, at.z)), 2.6) and not _on_carriageway(_w2(Vector2(at.x, at.z)), 0.3):
				_lamp(at, toward)

## A city block: raised paved plinth with lamps. Returns the buildable interior.
func _block(rect: Rect2, paving: Color = Color(0.5, 0.49, 0.45), tex: String = "tiles", lamps: bool = true) -> Rect2:
	_slab(rect, paving, tex)
	if lamps:
		_block_lamps(rect)
	_pending_blocks.append({"rect": rect, "target": _target, "xf": _xf})
	return rect.grow(-3.2)

func _tree(at: Vector3, style: String = "plane") -> void:
	match style:
		"palm":
			for segment: int in range(5):
				var lean: float = segment * 0.18
				_box(at + Vector3(lean, 0.9 + segment * 1.6, 0), Vector3(0.34, 1.7, 0.34), Color(0.45, 0.34, 0.24))
			var top: Vector3 = at + Vector3(0.9, 8.4, 0)
			for frond: int in range(6):
				var angle: float = frond * TAU / 6.0
				_box_with(top + Vector3(cos(angle), -0.3, sin(angle)) * 1.3, Vector3(2.8, 0.12, 0.7), _material(Color(0.22, 0.46, 0.2)), false, -angle)
		"blossom":
			_cylinder(at + Vector3(0, 1.4, 0), 0.16, 2.8, Color(0.3, 0.2, 0.18))
			_cylinder(at + Vector3(0, 3.3, 0), 1.7, 1.6, Color(0.95, 0.62, 0.78), 6)
			_cylinder(at + Vector3(0.4, 4.2, 0.2), 1.1, 1.0, Color(0.98, 0.72, 0.84), 6)
		_:
			_box(at + Vector3(0, 0.38, 0), Vector3(1.5, 0.75, 1.5), Color(0.53, 0.51, 0.43), true, "tiles")
			_cylinder(at + Vector3(0, 1.5, 0), 0.13, 2.3, Color(0.37, 0.28, 0.18))
			_cylinder(at + Vector3(0, 3.0, 0), 1.25, 1.6, Color(0.35, 0.42, 0.25), 6)
			_cylinder(at + Vector3(0, 4.0, 0), 0.85, 1.0, Color(0.42, 0.49, 0.28), 6)

func _container(at: Vector3, color: Color, rotated: bool = false) -> void:
	var size: Vector3 = Vector3(2.6, 2.7, 6.1) if rotated else Vector3(6.1, 2.7, 2.6)
	# Yard stacks (levels of 2.7 m from the ground) stand on the paved plinth, not sunk into it.
	if absf(at.y - roundf(at.y / 2.7) * 2.7) < 0.01:
		at.y += surface_height(_w2(Vector2(at.x, at.z)))
	_box(at + Vector3(0, 1.35, 0), size, color, true, "metal")

## Chain-link on steel posts. You can see and shoot through the mesh; what stops bodies is
## the solid you can see: a 1.2 m windbreak screen along the bottom and the posts.
func _fence(from: Vector3, to: Vector3, height: float = 3.2) -> void:
	var span: Vector3 = to - from
	var length: float = span.length()
	var angle: float = atan2(span.x, span.z)
	var mid: Vector3 = (from + to) * 0.5
	var mesh: MeshInstance3D = _box_with(mid + Vector3(0, height * 0.5, 0), Vector3(0.05, height, length), _chainlink(), false, angle)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box_with(mid + Vector3(0, 0.6, 0), Vector3(0.06, 1.2, length), _material(Color(0.14, 0.24, 0.2), 0.9), true, angle)
	_box_with(mid + Vector3(0, height, 0), Vector3(0.07, 0.07, length), _material(Color(0.32, 0.34, 0.35), 0.6), false, angle)
	var posts: int = maxi(2, int(length / 3.0) + 1)
	for index: int in range(posts):
		var post: Vector3 = from + span * (float(index) / float(posts - 1))
		_box(post + Vector3(0, height * 0.5, 0), Vector3(0.08, height, 0.08), Color(0.32, 0.34, 0.35), true)

func _chainlink() -> StandardMaterial3D:
	if _materials.has("chainlink"):
		return _materials["chainlink"] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.58, 0.6, 0.45)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = _tex.texture("metal")
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3(2, 2, 2)
	_materials["chainlink"] = material
	return material

func _awning(at: Vector3, width: float, face: Vector3, color_a: Color, color_b: Color) -> void:
	var stripes: int = maxi(2, int(width / 0.6))
	var along: Vector3 = Vector3(1, 0, 0) if absf(face.z) > 0.5 else Vector3(0, 0, 1)
	for stripe: int in range(stripes):
		var offset: float = -width * 0.5 + (stripe + 0.5) * width / stripes
		var size: Vector3 = Vector3(width / stripes, 0.12, 1.6) if absf(face.z) > 0.5 else Vector3(1.6, 0.12, width / stripes)
		_box(at + along * offset + face * 0.8, size, color_a if stripe % 2 == 0 else color_b)

## A parked vehicle: main.gd spawns a real, enterable vehicle here.
func _car_prop(at: Vector3, angle: float, color: Color, type: String = "sedan", title: String = "") -> void:
	var world: Vector3 = _w(at)
	parked_vehicles.append({"at": Vector3(world.x, 0.5, world.z), "yaw": angle + _xf_yaw, "color": color, "type": type, "name": title})

func _mesh_at(mesh: Mesh, at: Vector3, material: Material, angle: float = 0.0, tilt: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.rotation = Vector3(tilt.x, angle, tilt.z)
	_target.add_child(instance)
	return instance

# --- Street life: furniture, litter, puddles and steam -------------------------------------

func _free_spot(at: Vector2, clearance: float) -> bool:
	if _on_carriageway(at, clearance + 0.3):
		return false
	for footprint: Rect2 in footprints:
		if footprint.grow(clearance).has_point(at):
			return false
	for used: Vector2 in _occupied:
		if used.distance_to(at) < 2.4:
			return false
	# Nothing stands in a doorway (prefab doors are registered as their block is built).
	for door: Dictionary in interactable_doors:
		var spot: Vector3 = door["position"]
		if Vector2(spot.x, spot.z).distance_to(at) < 3.0:
			return false
	return true

## Scatters crew-palette street furniture along a block's sidewalk edge.
func _street_life(rect: Rect2) -> void:
	var perimeter: float = (rect.size.x + rect.size.y) * 2.0
	var count: int = int(perimeter / 11.0)
	for index: int in range(count):
		var t: float = _rng.randf() * perimeter
		var at: Vector2
		var facing: float
		if t < rect.size.x:
			at = Vector2(rect.position.x + t, rect.position.y + 1.5)
			facing = PI
		elif t < rect.size.x * 2.0:
			at = Vector2(rect.position.x + t - rect.size.x, rect.end.y - 1.5)
			facing = 0.0
		elif t < rect.size.x * 2.0 + rect.size.y:
			at = Vector2(rect.position.x + 1.5, rect.position.y + t - rect.size.x * 2.0)
			facing = -PI * 0.5
		else:
			at = Vector2(rect.end.x - 1.5, rect.position.y + t - rect.size.x * 2.0 - rect.size.y)
			facing = PI * 0.5
		var world_at2: Vector2 = _w2(at)
		if not _on_land(world_at2) or not _free_spot(world_at2, 0.7) or CityDetail.is_path_entrance(world_at2):
			continue
		_occupied.append(world_at2)
		var world_at: Vector3 = Vector3(at.x, 0.16, at.y)
		var roll: float = _rng.randf()
		if roll < 0.14:
			_payphone(world_at, facing)
		elif roll < 0.32:
			_news_box(world_at, facing, _street_palette[_rng.randi() % _street_palette.size()])
		elif roll < 0.5:
			_trash_bags(world_at)
		elif roll < 0.62:
			_hydrant(world_at)
		elif roll < 0.74:
			_bench(world_at, facing)
		elif roll < 0.86:
			_dumpster(world_at, facing, _street_palette[_rng.randi() % _street_palette.size()].darkened(0.35))
		else:
			_planter(world_at)

func _payphone(at: Vector3, facing: float) -> void:
	payphones.append(_w(at))
	var basis: Basis = Basis(Vector3.UP, facing)
	var hood: Color = _street_palette[_rng.randi() % _street_palette.size()]
	_mesh_at(MeshKit.rounded_box(Vector3(0.12, 2.1, 0.12), 0.04, 1), at + Vector3(0, 1.05, 0), _material(Color(0.3, 0.32, 0.34), 0.4), facing)
	_mesh_at(MeshKit.rounded_box(Vector3(0.75, 0.9, 0.5), 0.08, 2), at + Vector3(0, 1.5, 0) + basis * Vector3(0, 0, 0.12), _material(Color(0.62, 0.64, 0.66), 0.35), facing)
	_mesh_at(MeshKit.rounded_box(Vector3(0.85, 0.16, 0.62), 0.06, 2), at + Vector3(0, 2.02, 0) + basis * Vector3(0, 0, 0.12), _material(hood, 0.5), facing)
	_mesh_at(MeshKit.capsule(0.035, 0.24, 8, 2), at + Vector3(0.18, 1.45, 0) + basis * Vector3(0.18, 0, 0.4), _material(Color(0.08, 0.08, 0.09)), facing)
	_collider(at + Vector3(0, 1.05, 0), Vector3(0.8, 2.1, 0.6), facing)

func _news_box(at: Vector3, facing: float, color: Color) -> void:
	_mesh_at(MeshKit.rounded_box(Vector3(0.52, 1.0, 0.46), 0.05, 2), at + Vector3(0, 0.5, 0), _material(color, 0.45), facing)
	_mesh_at(MeshKit.rounded_box(Vector3(0.4, 0.3, 0.04), 0.01, 1), at + Vector3(0, 0.72, 0) + Basis(Vector3.UP, facing) * Vector3(0, 0, -0.24), _material(Color(0.8, 0.85, 0.85), 0.2), facing)
	_collider(at + Vector3(0, 0.5, 0), Vector3(0.52, 1.0, 0.46), facing)

func _trash_bags(at: Vector3) -> void:
	for bag: int in range(2 + _rng.randi() % 3):
		var offset: Vector3 = Vector3(_rng.randf_range(-0.5, 0.5), 0.0, _rng.randf_range(-0.5, 0.5))
		var bag_mesh: MeshInstance3D = _mesh_at(MeshKit.sphere(0.32, 0.5, 10, 5), at + offset + Vector3(0, 0.22, 0), _material(Color(0.06, 0.06, 0.07), 0.35), _rng.randf() * TAU)
		bag_mesh.scale = Vector3(1.0, _rng.randf_range(0.8, 1.1), 0.9)
	_collider(at + Vector3(0, 0.3, 0), Vector3(1.2, 0.6, 1.2))

func _hydrant(at: Vector3) -> void:
	var red: Color = Color(0.78, 0.14, 0.1) if _rng.randf() < 0.7 else Color(0.95, 0.75, 0.15)
	_mesh_at(MeshKit.cylinder(0.14, 0.17, 0.7, 12), at + Vector3(0, 0.35, 0), _material(red, 0.4))
	_mesh_at(MeshKit.sphere(0.15, 0.2, 12, 5, true), at + Vector3(0, 0.7, 0), _material(red, 0.4))
	_mesh_at(MeshKit.cylinder(0.06, 0.06, 0.42, 8), at + Vector3(0, 0.45, 0), _material(red.darkened(0.2), 0.4), 0.0, Vector3(0, 0, PI * 0.5))
	_collider(at + Vector3(0, 0.4, 0), Vector3(0.36, 0.8, 0.36))

func _bench(at: Vector3, facing: float) -> void:
	var basis: Basis = Basis(Vector3.UP, facing)
	_mesh_at(MeshKit.rounded_box(Vector3(1.8, 0.08, 0.45), 0.03, 1), at + Vector3(0, 0.46, 0), _material(Color(0.45, 0.28, 0.16), 0.8, "planks"), facing)
	_mesh_at(MeshKit.rounded_box(Vector3(1.8, 0.4, 0.07), 0.03, 1), at + Vector3(0, 0.76, 0) + basis * Vector3(0, 0, 0.22), _material(Color(0.45, 0.28, 0.16), 0.8, "planks"), facing)
	for side: float in [-1.0, 1.0]:
		_mesh_at(MeshKit.rounded_box(Vector3(0.08, 0.46, 0.45), 0.02, 1), at + Vector3(0, 0.23, 0) + basis * Vector3(side * 0.8, 0, 0), _material(Color(0.12, 0.13, 0.14), 0.5), facing)
	_collider(at + Vector3(0, 0.45, 0), Vector3(1.8, 0.9, 0.5), facing)

func _dumpster(at: Vector3, facing: float, color: Color) -> void:
	var basis: Basis = Basis(Vector3.UP, facing)
	_mesh_at(MeshKit.rounded_box(Vector3(1.9, 1.15, 1.05), 0.08, 2), at + Vector3(0, 0.6, 0), _material(color, 0.8, "metal"), facing)
	var lid: MeshInstance3D = _mesh_at(MeshKit.rounded_box(Vector3(1.95, 0.08, 1.1), 0.03, 1), at + Vector3(0, 1.22, 0) + basis * Vector3(0, 0.02, 0.04), _material(Color(0.1, 0.1, 0.11), 0.6), facing)
	lid.rotation.x = 0.12
	_collider(at + Vector3(0, 0.62, 0), Vector3(1.9, 1.25, 1.05), facing)

func _planter(at: Vector3) -> void:
	_mesh_at(MeshKit.rounded_box(Vector3(1.0, 0.55, 1.0), 0.08, 2), at + Vector3(0, 0.28, 0), _material(Color(0.55, 0.52, 0.46), 0.9, "stucco"))
	_mesh_at(MeshKit.sphere(0.55, 0.8, 10, 5), at + Vector3(0, 0.85, 0), _material(Color(0.24, 0.42, 0.2), 0.9))
	_collider(at + Vector3(0, 0.3, 0), Vector3(1.0, 0.6, 1.0))

## Rain puddles near kerbs mirror the sky and neon; a few manhole vents breathe steam.
func _build_puddles_and_vents() -> void:
	var water: StandardMaterial3D = StandardMaterial3D.new()
	water.albedo_color = Color(0.05, 0.06, 0.08)
	water.roughness = 0.04
	water.metallic = 0.6
	for index: int in range(160):
		var road: Dictionary = roads[_rng.randi() % roads.size()]
		var points: PackedVector2Array = road["points"]
		var segment: int = _rng.randi() % (points.size() - 1)
		var along: Vector2 = points[segment].lerp(points[segment + 1], _rng.randf())
		var direction: Vector2 = (points[segment + 1] - points[segment]).normalized()
		var across: Vector2 = Vector2(-direction.y, direction.x) * (float(road["width"]) * 0.5 - _rng.randf_range(0.8, 2.6)) * (1.0 if _rng.randf() < 0.5 else -1.0)
		var spot: Vector2 = along + across
		var puddle: MeshInstance3D = _mesh_at(MeshKit.cylinder(1.0, 1.0, 0.004, 14), Vector3(spot.x, 0.06, spot.y), water, _rng.randf() * TAU)
		puddle.scale = Vector3(_rng.randf_range(0.7, 1.8), 1.0, _rng.randf_range(0.5, 1.2))
		puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for at: Vector3 in [Vector3(-3.5, 0.05, -20), Vector3(3.2, 0.05, 44), Vector3(-235, 0.05, -80), Vector3(171, 0.05, 41), Vector3(-88, 0.05, 60), Vector3(62, 0.05, -144), Vector3(-100, 0.05, 120), Vector3(124, 0.05, 190)]:
		_mesh_at(MeshKit.cylinder(0.45, 0.45, 0.03, 16), at, _material(Color(0.12, 0.12, 0.13), 0.5, "metal"))
		steam_vents.append(at + Vector3(0, 0.1, 0))

func _build_midtown_life() -> void:
	_payphone(Vector3(-9.8, 0.16, 20.5), -PI * 0.5)
	_payphone(Vector3(9.9, 0.16, -26.5), PI * 0.5)
	_news_box(Vector3(-9.6, 0.16, -26.0), -PI * 0.5, Color(0.8, 0.2, 0.18))
	_news_box(Vector3(-9.6, 0.16, -24.8), -PI * 0.5, Color(0.2, 0.45, 0.75))
	_trash_bags(Vector3(-11.2, 0.16, -42.5))
	_hydrant(Vector3(9.6, 0.16, 26.0))
	_hydrant(Vector3(-9.6, 0.16, -62.0))
	_dumpster(Vector3(-11.0, 0.16, 27.0), -PI * 0.5, Color(0.25, 0.4, 0.3))
	_bench(Vector3(10.2, 0.16, 8.0), PI * 0.5)
	_car_prop(Vector3(5.2, 0.03, -70.0), PI, Color(0.2, 0.32, 0.5))
	_car_prop(Vector3(-40.0, 0.03, -47.2), PI * 0.5, Color(0.85, 0.72, 0.3))
	_car_prop(Vector3(55.0, 0.03, 37.8), -PI * 0.5, Color(0.3, 0.45, 0.32))

# --- Land, water and roads ----------------------------------------------------------------

## The mainland is one simple polygon (no holes): the harbour basins, the Canal Market inlet
## and the West Slip are notches in its coastline. Piers are separate strips of land.
func _define_land() -> void:
	land.append(MAINLAND)
	# Halcyon Pier off the beach, Morris Marina's jetty and Kingsway Docks.
	land.append(_moved([Vector2(91, 250), Vector2(99, 250), Vector2(99, 298), Vector2(91, 298)], STRIP_SHIFT))
	land.append(PackedVector2Array([Vector2(-84, 366), Vector2(-76, 366), Vector2(-76, 400), Vector2(-84, 400)]))
	land.append(_moved([Vector2(236, 55), Vector2(270, 55), Vector2(270, 65), Vector2(236, 65)], DOCKS_SHIFT))
	# Where piers meet a quay, the quay edge opens.
	for gap: Rect2 in [Rect2(108, 422, 14, 14), Rect2(-88, 364, 16, 16), Rect2(402, 163, 12, 16)]:
		quay_gaps.append(gap)

func _moved(points: Array, by: Vector2) -> PackedVector2Array:
	var moved: PackedVector2Array = PackedVector2Array()
	for point: Variant in points:
		moved.append((point as Vector2) + by)
	return moved

const MAINLAND: PackedVector2Array = [
	# North shore, west to east: the north-west headland (the wharf), Canal Market (with its
	# inlet and basin), the Harbor's basins either side of the mole, Uptown's shore and the
	# north-east cape under Solana Heights.
	Vector2(-404, -140), Vector2(-402, -200), Vector2(-396, -240), Vector2(-370, -262), Vector2(-322, -268), Vector2(-280, -266), Vector2(-252, -246), Vector2(-243, -224),
	Vector2(-230, -218), Vector2(-206, -228), Vector2(-175, -229),
	Vector2(-175, -176), Vector2(-183, -176), Vector2(-183, -160), Vector2(-153, -160), Vector2(-153, -176), Vector2(-161, -176),
	Vector2(-161, -229), Vector2(-122, -231), Vector2(-96, -227), Vector2(-86, -214), Vector2(-82, -200),
	Vector2(-70, -200), Vector2(-70, -172), Vector2(-26, -172), Vector2(-26, -200), Vector2(26, -200), Vector2(26, -172),
	Vector2(70, -172), Vector2(70, -200), Vector2(82, -200), Vector2(90, -216), Vector2(122, -222), Vector2(166, -224), Vector2(204, -222),
	Vector2(224, -250), Vector2(254, -282), Vector2(298, -292), Vector2(342, -280), Vector2(380, -258), Vector2(404, -222),
	# East shore: Solana's bluff, the East Shore park and the gun club, Kingsway's docks.
	Vector2(410, -170), Vector2(404, -120), Vector2(410, -70), Vector2(402, -20), Vector2(409, 30), Vector2(404, 80),
	Vector2(411, 130), Vector2(406, 180), Vector2(410, 230),
	# South-east: the south docks, then Halcyon Beach bulges south of the Strip.
	Vector2(400, 275), Vector2(378, 320), Vector2(342, 356), Vector2(292, 384), Vector2(242, 398),
	Vector2(218, 396), Vector2(198, 416), Vector2(165, 426), Vector2(130, 432), Vector2(95, 434), Vector2(63, 426), Vector2(38, 416), Vector2(20, 412),
	# South shore: Halcyon Avenue's end, Morris Marina and the Station's quay.
	Vector2(8, 394), Vector2(-14, 384), Vector2(-34, 376), Vector2(-60, 372), Vector2(-100, 374), Vector2(-150, 376),
	Vector2(-190, 380), Vector2(-240, 382), Vector2(-292, 372), Vector2(-338, 350), Vector2(-374, 324), Vector2(-396, 282),
	# West shore: the rail yard, the West Slip (Union Street ends at its head, x = -HALF),
	# Lantern Point's headland, and back up to the wharf.
	Vector2(-402, 230), Vector2(-397, 180), Vector2(-401, 130), Vector2(-396, 80), Vector2(-398, 52),
	Vector2(-200, 52), Vector2(-200, 18), Vector2(-398, 18),
	Vector2(-408, -30), Vector2(-404, -80),
]

## Midtown towers replaced by Eastbank Square and Corner Park.
const SQUARE_SITES: Array[Vector2] = [Vector2(61, -66), Vector2(-61, 60)]

## Fountain Square's centre, a neutral roundabout between Solana Heights and Kingsway.
const FOUNTAIN: Vector2 = Vector2(150, -56)

## Cross streets of each kit in its authored space: "x" lines run along local z, "z" lines along local x.
const KIT_STREETS: Dictionary = {
	"lantern": {"x": [-150.0], "z": [-150.0]},
	"solana": {"x": [150.0], "z": [-150.0]},
	"kingsway": {"x": [150.0], "z": [150.0]},
	"morris": {"x": [-150.0], "z": [150.0]},
	"strip": {"x": [150.0], "z": [-50.0, -15.0, 35.0]},
	"station": {"x": [0.0], "z": [150.0]},
}

## The street network as centre-line polylines. Each neighbourhood keeps its own street
## grid at its own angle (its cross streets and its perimeter ring come from its kit
## transform); long arterials, diagonal boulevards, waterfront drives and a roundabout tie
## them together, and the new 0.6 districts (Uptown, Motor Mile, Nightlife, West End, Old
## Town, the wharf and the docks) hang their own grids on the same network. Every crew
## district has three or more road entries and there is an outer ring road round Midtown.
func _define_roads() -> void:
	# --- Midtown's grid (unchanged) and its through-routes --------------------------------
	_road("HALCYON AVENUE", [Vector2(0, -200), Vector2(0, 382)], 14.0)
	_road("RING WEST", [Vector2(-88, -94), Vector2(-88, 94)])
	_road("RING EAST", [Vector2(88, -94), Vector2(88, 94)])
	_road("RING NORTH", [Vector2(-94, -88), Vector2(94, -88)])
	_road("RING SOUTH", [Vector2(-94, 88), Vector2(94, 88)])
	# Two diagonals cut Midtown's corners through Eastbank Square and Corner Park.
	_road("BROADWAY", [Vector2(88, -88), Vector2(46, -50)])
	_road("PARK ROW", [Vector2(-88, 88), Vector2(-50, 35)])
	# --- The six neighbourhood kits: cross streets and a perimeter ring each ---------------
	for kit: String in KITS:
		_kit_streets(kit)
		_kit_ring(kit)
	# --- West: Meridian runs out to Lantern Row, the wharf road to the north-west ----------
	_road("MERIDIAN STREET", [_ring_snap("lantern", Vector2(-250, -50)), Vector2(-235, -50), Vector2(-100, -50), Vector2(88, -50), Vector2(112, -52), Vector2(134, -56)])
	_road("WHARF ROAD", [_ring_snap("lantern", Vector2(-300, -150)), Vector2(-280, -148), Vector2(-235, -150)])
	# West of Halcyon Avenue, Canal Street is the pedestrian Canal Walk (see _build_squares);
	# the east half is a street.
	_road("CANAL STREET", [Vector2(0, -15), Vector2(88, -15), Vector2(104, -19), Vector2(118, -22), Vector2(170, -24), Vector2(227, -21)])
	# Union Street: the West Slip's head at x = -HALF to Motor Mile and the east coast road.
	_road("UNION STREET", [Vector2(-HALF, 35), Vector2(96, 35), Vector2(227, 35), Vector2(340, 35)])
	# --- North: the harbour front and its quays, the Canal Market shore, Uptown's streets ---
	_road("HARBOR ROAD", [Vector2(-235, -150), Vector2(88, -150), Vector2(227, -150)])
	_road("WEST QUAY ROAD", [Vector2(-88, -94), Vector2(-88, -196)])
	_road("EAST QUAY ROAD", [Vector2(88, -94), Vector2(88, -150)])
	_road("NORTH SHORE ROAD", _curve([Vector2(-235, -196), Vector2(-222, -212), Vector2(-196, -217), Vector2(-150, -217), Vector2(-112, -214), Vector2(-88, -196)], 4))
	_road("WEST BANK ROAD", [Vector2(-235, -196), Vector2(-235, -156), Vector2(-212, -104), Vector2(-212, 9), Vector2(-112, 9), Vector2(-100, 4), Vector2(-88, 2)])
	# Uptown: a small grid of tower blocks north-east of Midtown (see _build_uptown).
	_road("UPTOWN WEST", [Vector2(100, -206), Vector2(100, -98)])
	_road("UPTOWN MIDDLE", [Vector2(150, -206), Vector2(150, -72)])
	_road("UPTOWN EAST", [Vector2(200, -206), Vector2(200, -98)])
	_road("UPTOWN NORTH", [Vector2(100, -206), Vector2(200, -206), Vector2(226, -222), _ring_snap("solana", Vector2(255, -232))])
	# --- East: Fountain Square (a roundabout), Solana Boulevard and the east shore drive ---
	var ring: Array = []
	for step: int in range(25):
		var angle: float = step * TAU / 24.0
		ring.append(FOUNTAIN + Vector2(cos(angle), sin(angle)) * 16.0)
	_road("FOUNTAIN SQUARE", ring, 10.0)
	_road("UPTOWN SOUTH", [Vector2(100, -98), Vector2(227, -98)])
	_road("SOLANA BOULEVARD", [FOUNTAIN + Vector2(cos(-0.7), sin(-0.7)) * 16.0, Vector2(227, -98), Vector2(262, -108), _ring_snap("solana", Vector2(285, -120))])
	_road("EAST SHORE DRIVE", [Vector2(227, -150), Vector2(227, 102)], 14.0)
	_road("PARK ROAD", [Vector2(166, -56), Vector2(227, -58)])
	_road("BAYSIDE AVENUE", [Vector2(88, 88), Vector2(100, 99), Vector2(118, 102), Vector2(227, 102)])
	# Kingsway Boulevard: the diagonal from Midtown's east ring at Canal Street through Motor Mile.
	_road("KINGSWAY BOULEVARD", [Vector2(88, -15), Vector2(141, 35), _ring_snap("kingsway", Vector2(240, 130))])
	# Coast Road swings east round the Halcyon Arms range yard (world x 292-378, z -97..-29) instead of
	# running through it and past the long-range plates, then rejoins the old line at x 340.
	_road("COAST ROAD", [_ring_snap("solana", Vector2(335, -105)), Vector2(386, -105), Vector2(388, -22), Vector2(340, -22), Vector2(340, 35), Vector2(340, 110), _ring_snap("kingsway", Vector2(315, 135))])
	_road("SOLANA BLUFF DRIVE", [Vector2(227, -150), Vector2(240, -170), Vector2(238, -200), _ring_snap("solana", Vector2(255, -190))])
	# --- South: Halcyon Avenue to the beach, the outer ring, Old Town and the Strip ---------
	_road("MORRIS LINK", [Vector2(0, 250), _ring_snap("morris", Vector2(-20, 250))])
	_road("MORRIS NORTH LINK", [Vector2(0, 212), _ring_snap("morris", Vector2(-25, 200))])
	_road("STRIP LINK", [Vector2(0, 310), _ring_snap("strip", Vector2(30, 310))])
	_road("STATION LINK", [_ring_snap("station", Vector2(-180, 230)), _ring_snap("morris", Vector2(-160, 230))])
	_road("SLIP HEAD ROAD", [Vector2(-212, 9), Vector2(-190, 10), Vector2(-190, 212)])
	_road("SOUTH RING ROAD", [Vector2(0, 212), Vector2(176, 212)])
	_road("STATION NORTH LINK", [Vector2(-190, 212), _ring_snap("station", Vector2(-180, 200))])
	_road("SOUTH DOCKS ROAD", [_ring_snap("kingsway", Vector2(240, 262)), Vector2(215, 268), _ring_snap("strip", Vector2(200, 270))])
	# Old Town (the old Morris site): three streets north of Morris Park.
	for x: float in [-150.0, -100.0, -50.0]:
		_road("OLD TOWN %d" % int(-x), [Vector2(x, 88), Vector2(x, 190)])
	_road("OLD TOWN NORTH", [Vector2(-150, 88), Vector2(-94, 88)])
	_road("OLD TOWN MIDDLE", [Vector2(-150, 150), Vector2(-20, 150)])
	# Nightlife (the old Strip site): avenues down to the Strip's north ring.
	for x: float in [20.0, 72.0, 124.0, 176.0]:
		_road("NIGHTLIFE %d" % int(x), [Vector2(x, 98), Vector2(x, 276)])
	_road("NIGHTLIFE NORTH", [Vector2(20, 98), Vector2(176, 98)])
	_road("NIGHTLIFE MIDDLE", [Vector2(20, 154), Vector2(176, 154)])
	# West End (the old Lantern site), the slip-side quay, the wharf, the docks.
	_road("WEST END 150", [Vector2(-150, -100), Vector2(-150, 9)])
	_road("WEST END NORTH", [Vector2(-212, -100), Vector2(-88, -100)])
	_road("SLIP SIDE ROAD", [Vector2(-392, 62), Vector2(-190, 62)])
	_road("SLIP SIDE LINK", [Vector2(-330, 62), Vector2(-330, 112), _ring_snap("station", Vector2(-330, 135))])
	_road("WHARF NORTH", [Vector2(-380, -195), Vector2(-320, -195), Vector2(-235, -196)])
	_road("WHARF SPINE", [Vector2(-320, -238), Vector2(-320, -195), _ring_snap("lantern", Vector2(-320, -140))])
	_road("DOCK ROAD", [Vector2(215, 268), Vector2(215, 300), Vector2(330, 300), Vector2(385, 300)])
	_road("DOCK SPUR", [Vector2(300, 300), Vector2(300, 372)])
	# The canal's only road crossing, and a footbridge over the inlet nearer the sea.
	_bridge(Rect2(-178, -224, 20, 14), true)
	_bridge(Rect2(-178, -194, 20, 4), true, true)

## A kit's own cross streets, in its authored space (ends 5.5 m past the frame so they reach
## the perimeter ring).
func _kit_streets(kit: String) -> void:
	var spec: Dictionary = KITS[kit]
	var from: Vector2 = spec["from"]
	var half: Vector2 = (spec["half"] as Vector2) + Vector2(5.5, 5.5)
	var lines: Dictionary = KIT_STREETS[kit]
	for x: float in lines["x"]:
		_road("%s AVENUE %d" % [kit.to_upper(), int(absf(x))], [_kp(kit, Vector2(x, from.y - half.y)), _kp(kit, Vector2(x, from.y + half.y))])
	for z: float in lines["z"]:
		_road("%s CROSS %d" % [kit.to_upper(), int(absf(z))], [_kp(kit, Vector2(from.x - half.x, z)), _kp(kit, Vector2(from.x + half.x, z))])

## The kit's perimeter ring, 9 m outside its frame.
func _kit_ring(kit: String) -> void:
	var poly: PackedVector2Array = _kit_poly(kit, 9.0)
	var points: Array = []
	for point: Vector2 in poly:
		points.append(point)
	points.append(poly[0])
	_road("%s RING" % kit.to_upper(), points)

## The point on a kit's ring nearest to a world x/z (where an arterial joins it).
func _ring_snap(kit: String, near: Vector2) -> Vector2:
	var poly: PackedVector2Array = _kit_poly(kit, 9.0)
	var best: Vector2 = poly[0]
	var best_distance: float = INF
	for index: int in range(poly.size()):
		var point: Vector2 = Geometry2D.get_closest_point_to_segment(near, poly[index], poly[(index + 1) % poly.size()])
		if point.distance_to(near) < best_distance:
			best_distance = point.distance_to(near)
			best = point
	return best

func _road(title: String, points: Array, width: float = 12.0) -> void:
	var line: PackedVector2Array = PackedVector2Array()
	for point: Variant in points:
		line.append(point as Vector2)
	roads.append({"name": title, "points": line, "width": width})

func _bridge(rect: Rect2, along_x: bool, foot: bool = false) -> void:
	bridges.append({"rect": rect, "along_x": along_x, "foot": foot})
	quay_gaps.append(rect.grow(0.5))

## Smooths a control polyline with Catmull-Rom segments (`steps` per span).
func _curve(controls: Array, steps: int) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for index: int in range(controls.size() - 1):
		var p0: Vector2 = controls[maxi(index - 1, 0)]
		var p1: Vector2 = controls[index]
		var p2: Vector2 = controls[index + 1]
		var p3: Vector2 = controls[mini(index + 2, controls.size() - 1)]
		for step: int in range(steps):
			var t: float = float(step) / steps
			var t2: float = t * t
			var t3: float = t2 * t
			result.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	result.append(controls[controls.size() - 1])
	return result

func _build_land_and_water() -> void:
	# One sea plane under the whole map: harbour, channels and canal are all the same sea.
	_box(Vector3(30, SEA_LEVEL, 0), Vector3(1400, 0.2, 1400), Color(0.12, 0.24, 0.3), false, "water")
	var grass: StandardMaterial3D = _material(Color(0.40, 0.42, 0.36), 0.9, "grass")
	for poly: PackedVector2Array in land:
		_land_mesh(poly, grass, 0.0, true)
		_coast(poly)
	# Halcyon Beach: sand over the bulge south of the Strip.
	var sand: StandardMaterial3D = _material(Color(0.86, 0.76, 0.56), 0.95, "grass")
	_land_mesh(BEACH, sand, 0.012, false)

## Flat land at height `y` from a simple polygon, with trimesh collision if `solid`.
func _land_mesh(poly: PackedVector2Array, material: Material, y: float, solid: bool) -> void:
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
	if indices.is_empty():
		push_warning("Land polygon failed to triangulate (%d points)." % poly.size())
		return
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces: PackedVector3Array = PackedVector3Array()
	for index: int in range(0, indices.size(), 3):
		var a: Vector3 = Vector3(poly[indices[index]].x, y, poly[indices[index]].y)
		var b: Vector3 = Vector3(poly[indices[index + 1]].x, y, poly[indices[index + 1]].y)
		var c: Vector3 = Vector3(poly[indices[index + 2]].x, y, poly[indices[index + 2]].y)
		# Godot's front faces wind clockwise seen from above.
		if (b - a).cross(c - a).y > 0.0:
			var swap: Vector3 = b
			b = c
			c = swap
		for vertex: Vector3 in [a, b, c]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(vertex)
			faces.append(vertex)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.material_override = material
	_target.add_child(instance)
	if solid:
		var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(_grid_faces(poly, y))
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = shape
		var body: StaticBody3D = StaticBody3D.new()
		body.add_child(collision)
		_target.add_child(body)

## Collision faces for flat land, cut into 32 m cells first. Triangulating a big coastline in
## one go makes slivers hundreds of metres long, and vehicle hulls snag on their edges.
func _grid_faces(poly: PackedVector2Array, y: float) -> PackedVector3Array:
	var faces: PackedVector3Array = PackedVector3Array()
	var bounds: Rect2 = Rect2(poly[0], Vector2.ZERO)
	for point: Vector2 in poly:
		bounds = bounds.expand(point)
	var cell: float = 32.0
	var x: float = floorf(bounds.position.x / cell) * cell
	while x < bounds.end.x:
		var z: float = floorf(bounds.position.y / cell) * cell
		while z < bounds.end.y:
			var square: PackedVector2Array = PackedVector2Array([Vector2(x, z), Vector2(x + cell, z), Vector2(x + cell, z + cell), Vector2(x, z + cell)])
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(poly, square):
				var indices: PackedInt32Array = Geometry2D.triangulate_polygon(piece)
				# Winding is irrelevant here: the shape collides on both faces.
				for index: int in range(0, indices.size(), 3):
					for corner: int in [0, 1, 2]:
						var point: Vector2 = piece[indices[index + corner]]
						faces.append(Vector3(point.x, y, point.y))
			z += cell
		x += cell
	return faces

func _signed_area(poly: PackedVector2Array) -> float:
	var area: float = 0.0
	for index: int in range(poly.size()):
		var a: Vector2 = poly[index]
		var b: Vector2 = poly[(index + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5

const BEACH: PackedVector2Array = [Vector2(24, 400), Vector2(33, 391), Vector2(197, 391), Vector2(218, 396), Vector2(198, 416), Vector2(165, 426), Vector2(130, 432), Vector2(95, 434), Vector2(63, 426), Vector2(38, 416)]

## Quay edges round a land mass: a stone face down to the water, a coping kerb and a rail on
## posts. Collision is exactly what you see: the coping is solid, the top rail is a thin bar,
## and the gap between them and the air above the rail are open, so shots pass over and
## under the rail while nobody can walk or drive off (a jump clears 0.5 m; the rail is at
## 1.12 m). The beach has a low rock revetment instead. Edges open at bridges and piers.
func _coast(poly: PackedVector2Array) -> void:
	var clockwise: bool = _signed_area(poly) < 0.0
	var stone: StandardMaterial3D = _material(Color(0.5, 0.49, 0.45), 0.9, "cobble")
	var coping: StandardMaterial3D = _material(Color(0.66, 0.64, 0.58), 0.8)
	var rail: StandardMaterial3D = _material(Color(0.18, 0.19, 0.2), 0.6)
	var rocks: StandardMaterial3D = _material(Color(0.42, 0.41, 0.38), 0.95, "cobble")
	for index: int in range(poly.size()):
		var a: Vector2 = poly[index]
		var b: Vector2 = poly[(index + 1) % poly.size()]
		var edge: Vector2 = b - a
		if edge.length() < 0.1:
			continue
		var direction: Vector2 = edge.normalized()
		var outward: Vector2 = Vector2(-direction.y, direction.x) if clockwise else Vector2(direction.y, -direction.x)
		var beach: bool = _on_beach(a) and _on_beach(b)
		for span: Vector2 in _open_spans(a, b):
			var from: Vector2 = a + edge * span.x
			var to: Vector2 = a + edge * span.y
			var length: float = from.distance_to(to)
			if length < 0.3:
				continue
			var mid: Vector2 = (from + to) * 0.5
			var angle: float = atan2(direction.x, direction.y)
			var face_at: Vector2 = mid + outward * 0.15
			_box_with(Vector3(face_at.x, -1.3, face_at.y), Vector3(0.3, 2.8, length), stone, false, angle)
			if beach:
				# Rock revetment at the tide line: waist-low, solid, and it looks it.
				var rock_at: Vector2 = mid + outward * 0.3
				_box_with(Vector3(rock_at.x, 0.36, rock_at.y), Vector3(1.0, 0.72, length + 0.3), rocks, true, angle)
				continue
			_box_with(Vector3(face_at.x, COPING_HEIGHT * 0.5, face_at.y), Vector3(0.5, COPING_HEIGHT, length + 0.1), coping, true, angle)
			var posts: int = maxi(1, int(length / 3.0))
			for post: int in range(posts + 1):
				var at: Vector2 = from.lerp(to, float(post) / posts) + outward * 0.2
				_box_with(Vector3(at.x, (COPING_HEIGHT + RAIL_HEIGHT) * 0.5, at.y), Vector3(0.07, RAIL_HEIGHT - COPING_HEIGHT, 0.07), rail)
			var rail_at: Vector2 = mid + outward * 0.2
			_box_with(Vector3(rail_at.x, RAIL_HEIGHT, rail_at.y), Vector3(0.07, 0.07, length), rail, true, angle)

## The parts of edge a→b (as 0..1 parameter spans) not covered by a bridge or pier gap.
## Coast vertices that belong to Halcyon Beach (the sand bulge south of the Strip).
func _on_beach(at: Vector2) -> bool:
	return at.y >= 389.0 and at.x >= 22.0 and at.x <= 220.0

func _open_spans(a: Vector2, b: Vector2) -> Array[Vector2]:
	var covered: Array[Vector2] = []
	for gap: Rect2 in quay_gaps:
		var hit: Vector2 = _clip_segment(a, b, gap)
		if hit.y > hit.x:
			covered.append(hit)
	covered.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	var spans: Array[Vector2] = []
	var cursor: float = 0.0
	for part: Vector2 in covered:
		if part.x > cursor:
			spans.append(Vector2(cursor, part.x))
		cursor = maxf(cursor, part.y)
	if cursor < 1.0:
		spans.append(Vector2(cursor, 1.0))
	return spans

## Liang-Barsky: the parameter interval of segment a→b inside `rect` (empty if y <= x).
func _clip_segment(a: Vector2, b: Vector2, rect: Rect2) -> Vector2:
	var t0: float = 0.0
	var t1: float = 1.0
	var d: Vector2 = b - a
	var checks: Array = [[-d.x, a.x - rect.position.x], [d.x, rect.end.x - a.x], [-d.y, a.y - rect.position.y], [d.y, rect.end.y - a.y]]
	for check: Array in checks:
		var p: float = check[0]
		var q: float = check[1]
		if absf(p) < 0.00001:
			if q < 0.0:
				return Vector2(1.0, 0.0)
			continue
		var r: float = q / p
		if p < 0.0:
			t0 = maxf(t0, r)
		else:
			t1 = minf(t1, r)
	return Vector2(t0, t1)

## Asphalt ribbons with mitred joints, centre lines, and zebra crossings at bridge ends.
func _build_roads(from_index: int = 0) -> void:
	var asphalt: StandardMaterial3D = _material(Color(0.18, 0.20, 0.21), 0.9, "asphalt")
	var paint: StandardMaterial3D = _material(Color(0.83, 0.76, 0.48))
	for road_index: int in range(from_index, roads.size()):
		var road: Dictionary = roads[road_index]
		var points: PackedVector2Array = road["points"]
		var width: float = road["width"]
		# Millimetre-scale sorting offsets: overlapping ribbons must not rise into
		# a visible staircase merely because their road records were built later.
		var y: float = 0.02 + road_index * 0.00004
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var lefts: PackedVector2Array = PackedVector2Array()
		var rights: PackedVector2Array = PackedVector2Array()
		for index: int in range(points.size()):
			var before: Vector2 = points[index] - points[maxi(index - 1, 0)]
			var after: Vector2 = points[mini(index + 1, points.size() - 1)] - points[index]
			var tangent: Vector2
			if before.length() > 0.01 and after.length() > 0.01:
				tangent = (before.normalized() + after.normalized()).normalized()
			else:
				tangent = (after if after.length() > 0.01 else before).normalized()
			var normal: Vector2 = Vector2(-tangent.y, tangent.x)
			var miter: float = 1.0
			if before.length() > 0.01 and after.length() > 0.01:
				var incoming: Vector2 = before.normalized()
				miter = 1.0 / maxf(0.5, normal.dot(Vector2(-incoming.y, incoming.x)))
			lefts.append(points[index] + normal * width * 0.5 * miter)
			rights.append(points[index] - normal * width * 0.5 * miter)
		for index: int in range(points.size() - 1):
			var quad: Array[Vector3] = [Vector3(lefts[index].x, y, lefts[index].y), Vector3(rights[index].x, y, rights[index].y), Vector3(rights[index + 1].x, y, rights[index + 1].y), Vector3(lefts[index + 1].x, y, lefts[index + 1].y)]
			for triangle: Array in [[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]]:
				var a: Vector3 = triangle[0]
				var b: Vector3 = triangle[1]
				var c: Vector3 = triangle[2]
				if (b - a).cross(c - a).y > 0.0:
					var swap: Vector3 = b
					b = c
					c = swap
				for vertex: Vector3 in [a, b, c]:
					surface.set_normal(Vector3.UP)
					surface.add_vertex(vertex)
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.mesh = surface.commit()
		instance.material_override = asphalt
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_target.add_child(instance)
		# Double centre line, dashed, stopping short of junctions.
		for index: int in range(points.size() - 1):
			var from: Vector2 = points[index]
			var to: Vector2 = points[index + 1]
			var length: float = from.distance_to(to)
			var direction: Vector2 = (to - from) / maxf(length, 0.01)
			var side: Vector2 = Vector2(-direction.y, direction.x)
			var angle: float = atan2(direction.x, direction.y)
			var dash: float = 3.5
			while dash < length - 1.0:
				var at: Vector2 = from + direction * dash
				if not _near_other_road(at, road_index, 2.5):
					for offset: float in [-0.15, 0.15]:
						var mark: Vector2 = at + side * offset
						_box_with(Vector3(mark.x, y + 0.008, mark.y), Vector3(0.1, 0.012, 3.2), paint, false, angle)
				dash += 7.0
	# Streets added later (the fill pass's cul-de-sacs) have no bridges to stripe.
	for bridge: Dictionary in (bridges if from_index == 0 else ([] as Array[Dictionary])):
		var rect: Rect2 = bridge["rect"]
		var along_x: bool = bridge["along_x"]
		if bridge.get("foot", false):
			continue
		for end: float in [-1.0, 1.0]:
			for stripe: int in range(5):
				var offset: float = -4.4 + stripe * 2.2
				if along_x:
					_box(Vector3(rect.get_center().x + end * (rect.size.x * 0.5 + 3.0), 0.06, rect.get_center().y + offset), Vector3(2.2, 0.02, 1.3), Color(0.76, 0.75, 0.65))
				else:
					_box(Vector3(rect.get_center().x + offset, 0.06, rect.get_center().y + end * (rect.size.y * 0.5 + 3.0)), Vector3(1.3, 0.02, 2.2), Color(0.76, 0.75, 0.65))

func _near_other_road(at: Vector2, skip: int, margin: float) -> bool:
	for index: int in range(roads.size()):
		if index == skip:
			continue
		var points: PackedVector2Array = roads[index]["points"]
		var half: float = float(roads[index]["width"]) * 0.5 + margin
		for segment: int in range(points.size() - 1):
			if Geometry2D.get_closest_point_to_segment(at, points[segment], points[segment + 1]).distance_to(at) < half:
				return true
	return false

## Decks, parapets and girders. The road bridge's parapet is solid steel plate (cover, and
## it looks it); footbridges have an open post-and-rail balustrade with a thin collider.
func _build_bridges() -> void:
	var deck: StandardMaterial3D = _material(Color(0.45, 0.45, 0.42), 0.85, "panel")
	var steel: StandardMaterial3D = _material(Color(0.38, 0.22, 0.16), 0.6, "metal")
	var planks: StandardMaterial3D = _material(Color(0.5, 0.38, 0.26), 0.9, "planks")
	for bridge: Dictionary in bridges:
		var rect: Rect2 = bridge["rect"]
		var along_x: bool = bridge["along_x"]
		var foot: bool = bridge.get("foot", false)
		var center: Vector3 = Vector3(rect.get_center().x, 0, rect.get_center().y)
		_box_with(center + Vector3(0, -0.2 if foot else -0.35, 0), Vector3(rect.size.x, 0.4 if foot else 0.7, rect.size.y), planks if foot else deck, true)
		var span: float = rect.size.x if along_x else rect.size.y
		var across: float = rect.size.y if along_x else rect.size.x
		for side: float in [-1.0, 1.0]:
			var offset: Vector3 = Vector3(0, 0, side * (across * 0.5 - 0.25)) if along_x else Vector3(side * (across * 0.5 - 0.25), 0, 0)
			if foot:
				var posts: int = int(span / 2.0)
				for post: int in range(posts + 1):
					var t: float = -span * 0.5 + span * float(post) / posts
					_box_with(center + offset + (Vector3(t, 0.56, 0) if along_x else Vector3(0, 0.56, t)), Vector3(0.08, 1.12, 0.08), steel)
				_box_with(center + offset + Vector3(0, RAIL_HEIGHT, 0), Vector3(span, 0.08, 0.08) if along_x else Vector3(0.08, 0.08, span), steel, true)
				_box_with(center + offset + Vector3(0, 0.15, 0), Vector3(span, 0.3, 0.1) if along_x else Vector3(0.1, 0.3, span), steel, true)
				continue
			var size: Vector3 = Vector3(span, 1.1, 0.5) if along_x else Vector3(0.5, 1.1, span)
			_box_with(center + offset + Vector3(0, 0.55, 0), size, steel, true)
			var girder: Vector3 = Vector3(span, 1.4, 0.4) if along_x else Vector3(0.4, 1.4, span)
			_box_with(center + offset + Vector3(0, -1.2, 0), girder, steel)
			for post: int in range(4):
				var t: float = -span * 0.5 + (post + 0.5) * span / 4.0
				var post_at: Vector3 = center + offset + (Vector3(t, 1.4, 0) if along_x else Vector3(0, 1.4, t))
				_box_with(post_at, Vector3(0.3, 0.6, 0.3), steel)

## Road graph for route(): every road polyline is split where it crosses or meets another
## road (a T-junction counts when an end lies on the other road), and nodes are shared.
func _build_road_graph() -> void:
	_graph_points = PackedVector2Array()
	_graph_links.clear()
	var keys: Dictionary = {}
	var segments: Array = []
	for road: Dictionary in roads:
		var points: PackedVector2Array = road["points"]
		for index: int in range(points.size() - 1):
			segments.append([points[index], points[index + 1], float(road["width"])])
	var cuts: Array = []
	for segment: Array in segments:
		cuts.append([0.0, 1.0])
	for i: int in range(segments.size()):
		var a0: Vector2 = segments[i][0]
		var a1: Vector2 = segments[i][1]
		var length: float = a0.distance_to(a1)
		if length < 0.01:
			continue
		for j: int in range(segments.size()):
			if i == j:
				continue
			var b0: Vector2 = segments[j][0]
			var b1: Vector2 = segments[j][1]
			var crossing: Variant = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
			if crossing != null:
				(cuts[i] as Array).append(a0.distance_to(crossing as Vector2) / length)
			# A road that ends on this one (within its half-width) joins it there.
			for end: Vector2 in [b0, b1]:
				var closest: Vector2 = Geometry2D.get_closest_point_to_segment(end, a0, a1)
				if closest.distance_to(end) < float(segments[i][2]) * 0.5 + 1.0:
					(cuts[i] as Array).append(a0.distance_to(closest) / length)
					_graph_link(_graph_node(closest, keys), _graph_node(end, keys))
	for i: int in range(segments.size()):
		var a0: Vector2 = segments[i][0]
		var a1: Vector2 = segments[i][1]
		var along: Array = cuts[i]
		along.sort()
		for k: int in range(along.size() - 1):
			var from: int = _graph_node(a0.lerp(a1, float(along[k])), keys)
			var to: int = _graph_node(a0.lerp(a1, float(along[k + 1])), keys)
			_graph_link(from, to)

func _graph_node(at: Vector2, keys: Dictionary) -> int:
	var key: Vector2i = Vector2i(roundi(at.x * 2.0), roundi(at.y * 2.0))
	if keys.has(key):
		return int(keys[key])
	_graph_points.append(at)
	_graph_links.append({})
	keys[key] = _graph_points.size() - 1
	return _graph_points.size() - 1

func _graph_link(a: int, b: int) -> void:
	if a == b:
		return
	var metres: float = _graph_points[a].distance_to(_graph_points[b])
	_graph_links[a][b] = metres
	_graph_links[b][a] = metres

## The road stretch nearest `at`: [node a, node b, closest point] (empty if no roads).
func _nearest_graph_edge(at: Vector2) -> Array:
	var best: Array = []
	var best_distance: float = INF
	for a: int in range(_graph_points.size()):
		for b: int in _graph_links[a]:
			if b < a:
				continue
			var point: Vector2 = Geometry2D.get_closest_point_to_segment(at, _graph_points[a], _graph_points[b])
			var distance: float = point.distance_squared_to(at)
			if distance < best_distance:
				best_distance = distance
				best = [a, b, point]
	return best

# --- Midtown (Codex's original district) ---------------------------------------------------

func _build_streets() -> void:
	var concrete: Color = Color(0.48, 0.48, 0.43)
	var curb: Color = Color(0.67, 0.64, 0.55)
	# Walkways are split at road junctions, keeping every crossing flush.
	for side: float in [-1.0, 1.0]:
		for segment: Vector2 in [Vector2(-68, 22), Vector2(-32.5, 23), Vector2(10, 38), Vector2(61, 40)]:
			_walkway(Vector3(side * 9.4, 0, segment.x), segment.y, concrete)
			_box(Vector3(side * 7.52, 0.165, segment.x), Vector3(0.13, 0.01, segment.y - 0.9), curb)
	for z: float in [-24.0, -6.0, 26.0]:
		for stripe: int in range(6):
			_box(Vector3(-5.5 + stripe * 2.2, 0.052, z), Vector3(1.3, 0.02, 2.2), Color(0.76, 0.75, 0.65))
	# Subtle asphalt patches and drain grates lend texture without external assets.
	for z: float in [-65.0, -35.0, -1.0, 21.0, 56.0]:
		_box(Vector3(4.3, 0.045, z), Vector3(2.0, 0.012, 3.0), Color(0.205, 0.222, 0.222))
		for slat: int in range(6):
			_box(Vector3(-6.4 + slat * 0.1, 0.052, z), Vector3(0.04, 0.014, 0.8), Color(0.085, 0.10, 0.11))

func _building(at: Vector3, size: Vector3, color: Color, floors: int, title: String = "") -> void:
	_footprint(Rect2(at.x - size.x * 0.5, at.z - size.z * 0.5, size.x, size.z))
	var tex: String = "brick" if color.r > color.b + 0.08 else "panel"
	_box(at + Vector3(0, size.y * 0.5, 0), size, color, true, tex)
	_box(at + Vector3(0, 0.5, 0), Vector3(size.x + 0.14, 1.0, size.z + 0.14), color.darkened(0.18), false, tex)
	_box(at + Vector3(0, size.y + 0.16, 0), Vector3(size.x + 0.45, 0.32, size.z + 0.45), Color(0.29, 0.31, 0.30), false, "roof")
	_box(at + Vector3(-size.x * 0.22, size.y + 0.65, -size.z * 0.2), Vector3(2.2, 1.0, 2.5), Color(0.43, 0.45, 0.43), false, "metal")
	var glass: StandardMaterial3D = _material(Color(0.16, 0.24, 0.29), 0.3)
	var warm: StandardMaterial3D = _glow(Color(1.0, 0.78, 0.46), 1.3)
	var columns: int = maxi(1, int(size.x / 3.5))
	for floor_index: int in range(floors):
		var y: float = 2.4 + float(floor_index) * 3.1
		if y + 1.0 > size.y:
			continue
		for column: int in range(columns):
			var x: float = -size.x * 0.5 + (column + 0.5) * size.x / columns
			_box_with(at + Vector3(x, y, size.z * 0.5 + 0.045), Vector3(1.65, 1.55, 0.10), warm if _rng.randf() < 0.3 else glass)
			_box(at + Vector3(x, y - 0.85, size.z * 0.5 + 0.17), Vector3(1.9, 0.15, 0.35), color.lightened(0.12))
		var side_columns: int = maxi(1, int(size.z / 3.5))
		# Both side faces are exposed now that the city continues past Midtown.
		for exposed_side: float in [-1.0, 1.0]:
			for column: int in range(side_columns):
				var z: float = -size.z * 0.5 + (column + 0.5) * size.z / side_columns
				_box_with(at + Vector3(exposed_side * (size.x * 0.5 + 0.04), y, z), Vector3(0.10, 1.55, 1.65), warm if _rng.randf() < 0.3 else glass)
	if not title.is_empty():
		_box(at + Vector3(0, 4.8, size.z * 0.5 + 0.16), Vector3(size.x * 0.84, 1.7, 0.26), Color(0.12, 0.23, 0.25))
		_label(title, at + Vector3(0, 4.8, size.z * 0.5 + 0.31), 54, Color(0.94, 0.86, 0.64))

func _build_district() -> void:
	# Signed storefronts are walk-in businesses (interiors.gd): hollow ground floor, real
	# door, breakable shop windows. Their rooms are furnished after Midtown merges.
	var shop_sites: Array[Vector2] = []
	for shop: Dictionary in Interiors.SHOPS:
		_begin_building("shop", true, str(shop["sign"]))
		Interiors.new(self, shop).build_shell()
		_end_building()
		shop_sites.append(shop["at"])
	_building(Vector3(39, 0, -35), Vector3(14, 8, 18), Color(0.65, 0.54, 0.37), 2, "CARGO  04")
	for side: float in [-1.0, 1.0]:
		for z: float in [-66.0, -33.0, 9.0, 60.0]:
			var height: float = _rng.randf_range(13.0, 27.0)
			if not shop_sites.has(Vector2(side * 61.0, z)) and not SQUARE_SITES.has(Vector2(side * 61.0, z)):
				# The z -66 tower sits 0.5 m north so its face stops at the kerb of Meridian Street (z -56), not in the carriageway.
				_building(Vector3(side * 61.0, 0, z - (0.5 if z < -60.0 else 0.0)), Vector3(22, height, 21), Color(0.42, 0.46, 0.45), int(height / 3.2))
	# Midtown Parking: the old armory lot is a pay-and-display car park (the range moved to Halcyon Arms).
	_box(Vector3(20, 0.02, -34), Vector3(21, 0.035, 22), Color(0.2, 0.22, 0.23), false, "asphalt")
	_box(Vector3(21, 0.10, -43), Vector3(18, 0.20, 1.2), Color(0.70, 0.63, 0.45), true)
	_box(Vector3(22, 1.6, -43.5), Vector3(20, 3.2, 0.5), Color(0.46, 0.43, 0.35), true, "panel")
	_label("MIDTOWN PARKING  /  PAY AT THE MACHINE", Vector3(22, 2.0, -44.70), 34, Color(0.94, 0.79, 0.48))
	for at: Array in [[Vector3(15.9, 0.03, -34.4), 0.0, Color(0.55, 0.14, 0.14), "sedan"], [Vector3(24.1, 0.03, -34.4), 0.0, Color(0.2, 0.28, 0.4), "coupe"]]:
		_car_prop(at[0], float(at[1]), at[2], str(at[3]), "MIDTOWN LOT")
	for x: float in [13.0, 30.0]:
		_box(Vector3(x, 0.65, -41), Vector3(0.3, 1.3, 0.3), Color(0.93, 0.63, 0.21), true)
	# Street-facing loading doors and awnings.
	for z: float in [-39.0, -32.0, -25.0]:
		_box(Vector3(-12.43, 1.7, z), Vector3(0.10, 3.2, 4.5), Color(0.27, 0.31, 0.30))
		for slat: int in range(7):
			_box(Vector3(-12.36, 0.5 + slat * 0.43, z), Vector3(0.035, 0.04, 4.5), Color(0.37, 0.39, 0.36))
	_box(Vector3(-11.4, 4, -32), Vector3(2.1, 0.18, 21), Color(0.24, 0.33, 0.32))
	_label("FAST TALKERS", Vector3(-11.25, 7.6, -31), 74, Color(0.96, 0.75, 0.39), PI * 0.5)
	# The Union Exchange gantry: a landmark over the avenue (contracts are collected here),
	# not a meeting zone. The poles stand on the sidewalks, clear of traffic.
	for side: float in [-1.0, 1.0]:
		_box(Vector3(side * 8.8, 3.9, -38.0), Vector3(0.35, 7.8, 0.35), Color(0.2, 0.22, 0.24), true)
	_box(Vector3(0, 7.9, -38.0), Vector3(18.2, 0.4, 0.4), Color(0.2, 0.22, 0.24))
	_neon("UNION EXCHANGE", Vector3(0, 6.9, -37.85), 0.0, Color(0.98, 0.7, 0.34), 70, true)
	_landmark("UNION EXCHANGE", Vector3(0, 0, -42))
	_landmark("MIDTOWN PARKING", Vector3(13, 0, -40))

func _crate(at: Vector3, size: float = 1.2) -> void:
	var wood: Color = Color(0.56, 0.43, 0.28)
	_box(at + Vector3(0, size * 0.5, 0), Vector3(size, size, size), wood, true, "planks")
	for side: float in [-1.0, 1.0]:
		_box(at + Vector3(side * size * 0.31, size * 0.5, size * 0.505), Vector3(0.11, size, 0.04), wood.darkened(0.28))
		_box(at + Vector3(size * 0.505, size * 0.5, side * size * 0.31), Vector3(0.04, size, 0.11), wood.darkened(0.28))
	_box(at + Vector3(0, size + 0.02, 0), Vector3(size, 0.04, 0.12), wood.darkened(0.22))

func _build_props() -> void:
	# Yard crates sit in the street-side (map south-east) corner of the lot.
	for at: Vector3 in [Vector3(-10.8, 0.16, -39), Vector3(-10.8, 0.16, -36.8), Vector3(28.6, 0, -24.4), Vector3(27.2, 0, -24.4), Vector3(28.6, 1.2, -24.4), Vector3(14, 0.16, 0)]:
		_crate(at)
	var steel: Color = Color(0.23, 0.28, 0.29)
	for side: float in [-1.0, 1.0]:
		for z: float in [-60.0, -30.0, 2.0, 23.0, 53.0]:
			var x: float = side * 8.7
			_box(Vector3(x, 3.5, z), Vector3(0.15, 7, 0.15), steel, true)
			_box(Vector3(x - side * 0.7, 6.94, z), Vector3(1.5, 0.12, 0.12), steel)
			_box_with(Vector3(x - side * 1.4, 6.88, z), Vector3(0.65, 0.16, 0.35), _glow(Color(1.0, 0.66, 0.28), 2.4))
		# Pedestrian railings guard sidewalks without blocking intersections.
		for z: float in [-66.0, 19.0, 56.0]:
			for offset: float in [-2.0, 0.0, 2.0]:
				_box(Vector3(side * 7.75, 0.7, z + offset), Vector3(0.06, 1.1, 0.06), steel)
			_box(Vector3(side * 7.75, 1.22, z), Vector3(0.06, 0.07, 4.0), steel)
	for z: float in [-57.0, -9.0, 29.0]:
		_box(Vector3(-10.2, 1.0, z), Vector3(1.25, 1.65, 0.65), Color(0.24, 0.36, 0.34), true)
		_box(Vector3(-10.2, 1.65, z + 0.34), Vector3(0.95, 0.13, 0.03), Color(0.08, 0.12, 0.13))
	# Freight container in the back lot, recognizable corrugations included.
	_box(Vector3(25, 1.35, -58), Vector3(6.1, 2.7, 2.6), Color(0.35, 0.48, 0.49), true, "metal")
	_label("M / 028", Vector3(25, 1.5, -56.60), 38, Color(0.82, 0.83, 0.71))
	for at: Vector3 in [Vector3(-10.1, 0.16, 7), Vector3(10.5, 0.16, -37), Vector3(10.5, 0.16, 58)]:
		_tree(at)
	# Painted parking bays.
	for x: float in [14.0, 18.0, 22.0, 26.0, 30.0]:
		_box(Vector3(x, 0.05, -28.4), Vector3(0.09, 0.015, 5), Color(0.74, 0.70, 0.53))
	_label("PARKING", Vector3(31.65, 4.4, -28), 46, Color(0.95, 0.79, 0.43), -PI * 0.5)

## Two small squares where the diagonal avenues cut Midtown's north-east and south-west
## corners: somewhere to stand, sit, hide behind a planter or a clock tower. (No painted
## deal zones: meetings happen wherever the players choose.)
func _build_squares() -> void:
	var stone: Color = Color(0.72, 0.68, 0.6)
	for square: Dictionary in [{"rect": Rect2(50, -82, 38, 30), "feature": Vector3(72, 0, -61), "name": "EASTBANK SQUARE"},
			{"rect": Rect2(-88, 46, 38, 36), "feature": Vector3(-72, 0, 50), "name": "CORNER PARK"}]:
		var rect: Rect2 = square["rect"]
		# Paving sits just under the road surface so the avenue runs across it.
		_box(Vector3(rect.get_center().x, 0.006, rect.get_center().y), Vector3(rect.size.x, 0.012, rect.size.y), Color(0.55, 0.52, 0.47), false, "tiles")
		plazas.append(_rect_poly(rect))
		var at: Vector3 = square["feature"]
		_box(at + Vector3(0, 0.6, 0), Vector3(2.6, 1.2, 2.6), stone, true, "stucco")
		_box(at + Vector3(0, 4.2, 0), Vector3(1.2, 6.0, 1.2), stone, true, "stucco")
		for face: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
			var dial: MeshInstance3D = _cylinder(at + Vector3(0, 6.3, 0) + face * 0.62, 0.42, 0.04, Color.WHITE, 16, _glow(Color(1.0, 0.95, 0.8), 1.2))
			dial.rotation = Vector3(PI * 0.5, atan2(face.x, face.z), 0)
		_box(at + Vector3(0, 7.5, 0), Vector3(1.6, 0.3, 1.6), Color(0.3, 0.28, 0.26), false, "roof")
		_landmark(str(square["name"]), at)
	for spot: Vector3 in [Vector3(58, 0, -78), Vector3(54, 0, -72), Vector3(80, 0, -60.5), Vector3(-58, 0, 72), Vector3(-60, 0, 80), Vector3(-80, 0, 54)]:
		_tree(spot)
	for spot: Array in [[Vector3(66, 0, -80), PI], [Vector3(76.5, 0, -59.5), 0.0], [Vector3(-76, 0, 47), PI], [Vector3(-66, 0, 78), 0.0]]:
		_bench(spot[0], spot[1])
	for spot: Vector3 in [Vector3(56, 0, -80), Vector3(60, 0, -76), Vector3(-58, 0, 66)]:
		_planter(spot)
	# Canal Walk: the old west half of Canal Street, paved over, planted and closed to
	# traffic by bollards at both ends. The pawn shop and Meridian Imports open onto it.
	var walk: Rect2 = Rect2(-82, -21, 75, 12)
	_slab(walk, Color(0.56, 0.53, 0.48), "tiles")
	plazas.append(_rect_poly(walk))
	for x: float in [-72.0, -52.0, -32.0]:
		_tree(Vector3(x, 0.16, -15))
	for x: float in [-62.0, -42.0, -22.0]:
		_bench(Vector3(x, 0.16, -18.2), 0.0)
		_bench(Vector3(x, 0.16, -11.8), PI)
	for end_x: float in [-80.5, -8.5]:
		for index: int in range(6):
			_box(Vector3(end_x, 0.6, -19.5 + index * 1.8), Vector3(0.26, 0.9, 0.26), Color(0.25, 0.27, 0.28), true, "metal")
	_news_box(Vector3(-12.0, 0.16, -18.5), 0.0, Color(0.8, 0.2, 0.18))
	_landmark("CANAL WALK", Vector3(-45, 0, -15))

# --- Crew districts ------------------------------------------------------------------

## A crew's base, authored in its kit's space. `hq` is the doorstep (delivery point) and
## `door` the direction out of the front door; everything is stored in world space.
func _crew_spawn(crew: String, car: Vector3, yaw: float, hq: Vector3, door: Vector3 = Vector3.BACK) -> void:
	var out: Vector3 = (_xf.basis * door).normalized()
	var home: Vector3 = _w(hq)
	crew_spawns[crew] = {"car": _w(car), "yaw": yaw + _xf_yaw, "hq": home, "door": out,
		"spawn": home + out * 2.5 + Vector3(0, 0.1, 0), "spawn_yaw": atan2(-out.x, -out.z)}

## Lantern Row (Kojimoto893, NW): dense, narrow and vertical. Stacked neon, lanterns,
## dark timber and slate roofs.
func _build_lantern_row() -> void:
	_place("lantern", "LanternRow")
	_street_palette = [Color(0.55, 0.3, 0.85), Color(0.95, 0.35, 0.6), Color(0.25, 0.75, 0.85), Color(0.9, 0.2, 0.25)]
	var violet: Color = Factions.color("kojimoto")
	var timber: Color = Color(0.3, 0.22, 0.17)
	var plaster: Color = Color(0.78, 0.74, 0.66)
	var slate: Color = Color(0.16, 0.16, 0.2)
	# HQ block: the Kojimoto Building with a walled front garden and a timber gate.
	var hq: Rect2 = _block(Rect2(-200, -200, 44, 44), Color(0.36, 0.35, 0.38), "cobble")
	_tower(Vector2(-181, -184), Vector3(28, 22, 22), Color(0.17, 0.16, 0.2), "panel", Vector3.BACK, "", Color.WHITE, slate, 0.5)
	_neon("KOJIMOTO", Vector3(-166.6, 13, -176), PI * 0.5, violet, 110, true, true)
	_neon("KARAOKE  MURASAKI", Vector3(-181, 4.4, -172.6), 0.0, Color(0.95, 0.35, 0.85), 70)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(-176 + side * 3.2, 1.9, -160.5), Vector3(0.5, 3.8, 0.5), timber, true, "planks")
	_box(Vector3(-176, 3.95, -160.5), Vector3(8.4, 0.35, 1.2), slate, false, "roof")
	_box(Vector3(-176, 3.55, -160.5), Vector3(7.2, 0.3, 0.6), timber, false, "planks")
	for x: float in [-196.0, -157.0]:
		_box(Vector3(x, 1.1, -166), Vector3(0.5, 2.2, 12), plaster, true, "stucco")
	_label("KOJIMOTO893", Vector3(-176, 3.6, -160.1), 44, Color(0.95, 0.9, 1.0))
	_landmark("KOJIMOTO BUILDING", Vector3(-181, 0, -172), false)
	_crew_spawn("kojimoto", Vector3(-152.6, 0.5, -170), PI, Vector3(-176, 0.2, -163))
	# Pachinko and bar row with stacked vertical neon.
	_block(Rect2(-144, -200, 50, 44), Color(0.36, 0.35, 0.38), "cobble")
	var fronts: Array = [["PACHINKO", Color(0.3, 0.9, 1.0)], ["RAMEN", Color(1.0, 0.35, 0.3)], ["HOTEL", Color(0.95, 0.45, 0.9)], ["BAR KOI", Color(1.0, 0.8, 0.3)]]
	for index: int in range(4):
		var x: float = -137.0 + index * 12.0
		var height: float = 12.0 + (index % 2) * 6.0
		_tower(Vector2(x, -166), Vector3(10.5, height, 14), [timber, Color(0.62, 0.52, 0.44), Color(0.22, 0.2, 0.26), plaster][index], "planks" if index % 2 == 0 else "stucco", Vector3.BACK, "", Color.WHITE, slate, 0.55)
		_neon(fronts[index][0], Vector3(x + 4.4, height * 0.55 + 1.0, -158.4), 0.0, fronts[index][1], 60, index == 0, true)
		_awning(Vector3(x, 3.2, -159), 9.5, Vector3.BACK, Color(0.5, 0.12, 0.2), Color(0.9, 0.85, 0.8))
	_landmark("PACHINKO ROW", Vector3(-119, 0, -158), false)
	# Lantern Alley: two terraces with lanterns strung across a narrow lane.
	_block(Rect2(-200, -144, 44, 50), Color(0.36, 0.35, 0.38), "cobble")
	for row_x: float in [-189.5, -166.5]:
		for index: int in range(3):
			var z: float = -135.0 + index * 15.0
			_tower(Vector2(row_x, z), Vector3(17, 9.5 + index * 2.0, 13.5), [timber, plaster, Color(0.24, 0.22, 0.28)][index], "planks" if index != 1 else "stucco", Vector3.RIGHT if row_x < -178 else Vector3.LEFT, "", Color.WHITE, slate, 0.5)
	for z: int in range(-139, -99, 4):
		_box(Vector3(-178, 5.2, z), Vector3(6.2, 0.04, 0.04), Color(0.1, 0.1, 0.1))
		for offset: float in [-1.8, 0.0, 1.8]:
			_box_with(Vector3(-178 + offset, 4.85, z), Vector3(0.36, 0.48, 0.36), _glow(Color(1.0, 0.28, 0.35) if (z / 4 + int(offset)) % 2 == 0 else Color(0.8, 0.45, 1.0), 2.0))
	_landmark("LANTERN ALLEY", Vector3(-178, 0, -119), false)
	# Koi garden and teahouse pavilion.
	_block(Rect2(-144, -144, 50, 50), Color(0.44, 0.43, 0.4), "cobble")
	_box(Vector3(-119, 0.18, -122), Vector3(30, 0.06, 26), Color(0.3, 0.45, 0.27), false, "grass")
	_box(Vector3(-114, 0.21, -122), Vector3(12, 0.05, 9), Color(0.12, 0.3, 0.36), false, "water")
	for at: Vector3 in [Vector3(-130, 0.2, -132), Vector3(-108, 0.2, -132), Vector3(-130, 0.2, -110), Vector3(-104, 0.2, -112)]:
		_tree(at, "blossom")
	for x: float in [-127.0, -121.0]:
		for z: float in [-116.0, -110.0]:
			_box(Vector3(x, 1.6, z), Vector3(0.3, 3.2, 0.3), timber)
	_box(Vector3(-124, 3.35, -113), Vector3(8.6, 0.35, 8.6), slate, false, "roof")
	_tower(Vector2(-119, -100.5), Vector3(30, 7.5, 7), Color(0.28, 0.2, 0.18), "planks", Vector3.BACK, "IZAKAYA  NORA", Color(1.0, 0.5, 0.3), slate, 0.6)
	_landmark("KOI GARDEN", Vector3(-119, 0, -122), false)

## Solana Heights (Sol Negro, NE): sun-baked stucco, terracotta, palms and walled courtyards.
func _build_solana_heights() -> void:
	_place("solana", "SolanaHeights")
	_street_palette = [Color(0.92, 0.65, 0.15), Color(0.2, 0.6, 0.55), Color(0.85, 0.35, 0.2), Color(0.55, 0.75, 0.3)]
	var gold: Color = Factions.color("solnegro")
	var terracotta: Color = Color(0.72, 0.36, 0.22)
	var pastels: Array[Color] = [Color(0.93, 0.74, 0.58), Color(0.62, 0.8, 0.78), Color(0.92, 0.86, 0.7), Color(0.86, 0.6, 0.55), Color(0.75, 0.82, 0.62)]
	# HQ compound with courtyard, fountain and a gated wall.
	_block(Rect2(156, -200, 44, 44), Color(0.72, 0.62, 0.5), "tiles")
	var wall: Color = Color(0.9, 0.82, 0.68)
	_box(Vector3(178, 1.3, -197.5), Vector3(40, 2.6, 0.6), wall, true, "stucco")
	_box(Vector3(158.8, 1.3, -178), Vector3(0.6, 2.6, 40), wall, true, "stucco")
	_box(Vector3(197.2, 1.3, -178), Vector3(0.6, 2.6, 40), wall, true, "stucco")
	_box(Vector3(166.5, 1.3, -158.8), Vector3(15.5, 2.6, 0.6), wall, true, "stucco")
	_box(Vector3(189.5, 1.3, -158.8), Vector3(15.5, 2.6, 0.6), wall, true, "stucco")
	for side: float in [-1.0, 1.0]:
		_box(Vector3(178 + side * 3.9, 2.0, -158.8), Vector3(0.9, 4.0, 0.9), wall.darkened(0.1), true, "stucco")
	_tower(Vector2(178, -187), Vector3(30, 8.2, 14), Color(0.94, 0.86, 0.72), "stucco", Vector3.BACK, "", Color.WHITE, terracotta, 0.55)
	_neon("SOL NEGRO IMPORTS", Vector3(178, 5.2, -158.3), 0.0, gold, 66, true)
	_cylinder(Vector3(178, 0.55, -170), 2.4, 0.9, Color(0.8, 0.72, 0.6), 12)
	_cylinder(Vector3(178, 0.95, -170), 2.0, 0.1, Color(0.2, 0.4, 0.45), 12, _material(Color(0.2, 0.4, 0.45), 0.1, "water"))
	_cylinder(Vector3(178, 1.6, -170), 0.3, 1.8, Color(0.8, 0.72, 0.6))
	for at: Vector3 in [Vector3(164, 0.16, -174), Vector3(192, 0.16, -174), Vector3(164, 0.16, -165), Vector3(192, 0.16, -165)]:
		_tree(at, "palm")
	_landmark("SOL NEGRO COMPOUND", Vector3(178, 0, -170), false)
	_crew_spawn("solnegro", Vector3(178, 0.5, -147.4), -PI * 0.5, Vector3(178, 0.2, -161))
	# Cantina and auto shop.
	_block(Rect2(94, -200, 50, 44), Color(0.7, 0.6, 0.48), "tiles")
	_tower(Vector2(106, -168), Vector3(18, 5.2, 16), pastels[0], "stucco", Vector3.BACK, "CANTINA DEL SOL", Color(1.0, 0.75, 0.3), terracotta, 0.7, "bar")
	_tower(Vector2(131, -170), Vector3(22, 6.5, 16), Color(0.66, 0.64, 0.6), "stucco", Vector3.BACK, "TALLER  MECANICO", Color(0.95, 0.55, 0.25), Color(0.4, 0.4, 0.42), 0.3, "auto_shop")
	_box(Vector3(131, 2.2, -161.9), Vector3(9, 4.4, 0.2), Color(0.2, 0.2, 0.22), false, "metal")
	_car_prop(Vector3(122, 0.16, -186), 0.3, Color(0.55, 0.2, 0.15))
	_car_prop(Vector3(138, 0.16, -188), -0.2, Color(0.8, 0.78, 0.7))
	_landmark("CANTINA DEL SOL", Vector3(106, 0, -158), false)
	# Pastel row houses under palms.
	_block(Rect2(156, -144, 44, 50), Color(0.7, 0.6, 0.48), "tiles")
	for index: int in range(4):
		_tower(Vector2(163 + index * 10.2, -128), Vector3(9.4, 7.0 + (index % 2) * 1.5, 12), pastels[index + 1], "stucco", Vector3.LEFT, "", Color.WHITE, terracotta, 0.45)
	for z: float in [-112.0, -104.0]:
		for x: float in [162.0, 176.0, 190.0]:
			_tree(Vector3(x, 0.16, z), "palm")
	# Mercado colonnade and plaza.
	_block(Rect2(94, -144, 50, 50), Color(0.74, 0.64, 0.5), "tiles")
	_tower(Vector2(119, -132), Vector3(40, 7.5, 14), Color(0.9, 0.82, 0.66), "stucco", Vector3.BACK, "MERCADO  SOLANA", gold, terracotta, 0.4)
	for index: int in range(9):
		_box(Vector3(101 + index * 4.5, 1.9, -123.6), Vector3(0.6, 3.8, 0.6), Color(0.86, 0.78, 0.62), true, "stucco")
	_box(Vector3(119, 3.95, -123.6), Vector3(40, 0.5, 2.2), terracotta, false, "roof")
	_tower(Vector2(137, -104), Vector3(10, 5, 10), Color(0.95, 0.95, 0.9), "stucco", Vector3.LEFT, "FARMACIA", Color(0.3, 1.0, 0.5), terracotta, 0.5)
	for at: Vector3 in [Vector3(106, 0.16, -110), Vector3(118, 0.16, -104), Vector3(124, 0.16, -114)]:
		_tree(at, "palm")
	_landmark("MERCADO SOLANA", Vector3(119, 0, -118), false)

## Morris Park (Morris Mafia, SW): brick tenements, striped awnings, fire escapes,
## a cobbled piazza and a chapel bell tower.
func _build_morris_park() -> void:
	_place("morris", "MorrisPark")
	_street_palette = [Color(0.72, 0.15, 0.2), Color(0.16, 0.36, 0.24), Color(0.9, 0.82, 0.62), Color(0.2, 0.3, 0.55)]
	var crimson: Color = Factions.color("morris")
	var bricks: Array[Color] = [Color(0.56, 0.3, 0.24), Color(0.62, 0.38, 0.28), Color(0.5, 0.27, 0.25), Color(0.66, 0.46, 0.34)]
	var cream: Color = Color(0.92, 0.86, 0.72)
	var green: Color = Color(0.16, 0.34, 0.24)
	# HQ: the Morris Social Club with its garage.
	_block(Rect2(-200, 156, 44, 44), Color(0.46, 0.43, 0.4), "cobble")
	_tower(Vector2(-180, 172), Vector3(30, 11, 18), bricks[0], "brick", Vector3.FORWARD, "", Color.WHITE, Color(0.25, 0.2, 0.2), 0.5)
	_awning(Vector3(-180, 3.3, 163), 28.0, Vector3.FORWARD, crimson, cream)
	_neon("MORRIS  SOCIAL CLUB", Vector3(-180, 6.4, 162.6), PI, crimson, 64, true)
	_tower(Vector2(-166, 190), Vector3(16, 5.5, 14), bricks[3], "brick", Vector3.RIGHT, "GARAGE", cream, Color(0.25, 0.2, 0.2), 0.0)
	_landmark("MORRIS SOCIAL CLUB", Vector3(-180, 0, 162), false)
	_crew_spawn("morris", Vector3(-147.4, 0.5, 178), 0.0, Vector3(-180, 0.2, 160.5), Vector3.FORWARD)
	# Bakery and tenements with fire escapes.
	_block(Rect2(-144, 156, 50, 44), Color(0.46, 0.43, 0.4), "cobble")
	for index: int in range(3):
		var x: float = -135.0 + index * 16.0
		var height: float = 14.0 + index * 1.6
		_tower(Vector2(x, 170), Vector3(14.5, height, 16), bricks[index + 1], "brick", Vector3.FORWARD, "", Color.WHITE, Color(0.25, 0.2, 0.2), 0.45)
		for floor_index: int in range(1, int(height / 3.1)):
			_box(Vector3(x, 1.0 + floor_index * 3.1, 161.3), Vector3(5, 0.08, 1.2), Color(0.12, 0.12, 0.13))
			_box(Vector3(x, 1.5 + floor_index * 3.1, 160.8), Vector3(5, 1.0, 0.05), Color(0.12, 0.12, 0.13))
	_awning(Vector3(-135, 3.2, 161.5), 13.0, Vector3.FORWARD, crimson, cream)
	_neon("FORNO  ROSSI", Vector3(-135, 4.6, 161.4), PI, Color(1.0, 0.75, 0.4), 56)
	_landmark("FORNO ROSSI", Vector3(-135, 0, 160), false)
	# Chapel with a bell tower.
	_block(Rect2(-200, 94, 44, 50), Color(0.5, 0.47, 0.42), "cobble")
	_tower(Vector2(-182, 120), Vector3(14, 10, 26), cream, "stucco", Vector3.RIGHT, "SANTA LUCIA", Color(1.0, 0.9, 0.7), Color(0.4, 0.22, 0.18), 0.2)
	_box(Vector3(-172, 9, 104), Vector3(5, 18, 5), cream, true, "stucco")
	_box(Vector3(-172, 18.6, 104), Vector3(5.8, 1.2, 5.8), Color(0.4, 0.22, 0.18), false, "roof")
	_box_with(Vector3(-172, 14.5, 101.45), Vector3(1.6, 1.6, 0.1), _glow(Color(1.0, 0.9, 0.6), 1.6))
	_tower(Vector2(-164, 134), Vector3(10, 12, 14), bricks[2], "brick", Vector3.RIGHT, "", Color.WHITE, Color(0.25, 0.2, 0.2), 0.4)
	_landmark("SANTA LUCIA CHAPEL", Vector3(-182, 0, 120), false)
	# Piazza with a fountain, cafe and plane trees.
	_block(Rect2(-144, 94, 50, 50), Color(0.55, 0.5, 0.44), "cobble")
	_cylinder(Vector3(-119, 0.6, 116), 3.2, 0.9, cream, 16)
	_cylinder(Vector3(-119, 1.0, 116), 2.8, 0.1, Color.WHITE, 16, _material(Color(0.2, 0.4, 0.46), 0.1, "water"))
	_cylinder(Vector3(-119, 2.0, 116), 0.4, 2.4, cream, 8)
	_cylinder(Vector3(-119, 3.3, 116), 1.1, 0.3, cream, 12)
	_tower(Vector2(-119, 136), Vector3(40, 9, 10), bricks[1], "brick", Vector3.FORWARD, "CAFFE  VERONA", Color(1.0, 0.85, 0.55), Color(0.25, 0.2, 0.2), 0.5)
	for index: int in range(4):
		var table: Vector3 = Vector3(-132 + index * 8.5, 0.16, 126)
		_cylinder(table + Vector3(0, 0.5, 0), 0.5, 0.06, Color(0.9, 0.9, 0.88), 10)
		_cylinder(table + Vector3(0, 1.3, 0), 0.06, 2.6, Color(0.3, 0.3, 0.3), 6)
		_cylinder(table + Vector3(0, 2.6, 0), 1.3, 0.08, crimson if index % 2 == 0 else green, 8)
	for at: Vector3 in [Vector3(-136, 0.16, 104), Vector3(-102, 0.16, 104), Vector3(-136, 0.16, 118), Vector3(-102, 0.16, 118)]:
		_tree(at)
	_landmark("PIAZZA MORRIS", Vector3(-119, 0, 116), false)

## Kingsway (Royals, SE): concrete projects, the Cage court, murals and chain-link.
func _build_kingsway() -> void:
	_place("kingsway", "Kingsway")
	_street_palette = [Color(0.1, 0.72, 0.68), Color(0.95, 0.3, 0.7), Color(0.98, 0.82, 0.2), Color(0.35, 0.55, 1.0)]
	var teal: Color = Factions.color("kingsway")
	var concrete: Color = Color(0.58, 0.58, 0.56)
	var tags: Array[Color] = [teal, Color(0.95, 0.3, 0.7), Color(0.98, 0.82, 0.2), Color(0.35, 0.55, 1.0)]
	# HQ: Kingsway Courts, an L of slab towers around a courtyard.
	_block(Rect2(156, 156, 44, 44), Color(0.5, 0.5, 0.49), "tiles")
	_tower(Vector2(165, 178), Vector3(12, 25, 36), concrete, "panel", Vector3.RIGHT, "", Color.WHITE, Color(0.3, 0.3, 0.3), 0.4)
	_tower(Vector2(184, 190), Vector3(26, 19, 12), concrete.darkened(0.08), "panel", Vector3.FORWARD, "", Color.WHITE, Color(0.3, 0.3, 0.3), 0.4)
	for floor_index: int in range(1, 8):
		_box(Vector3(171.2, floor_index * 3.1, 178), Vector3(0.4, 0.25, 36), teal)
	_neon("ROYALS", Vector3(171.3, 21, 178), PI * 0.5, teal, 120, true)
	_box(Vector3(184, 1.6, 166), Vector3(18, 3.2, 0.5), Color(0.62, 0.62, 0.6), true, "panel")
	for index: int in range(4):
		_box(Vector3(177.5 + index * 4.4, 1.6, 166.28), Vector3(3.6, 2.6, 0.06), tags[index])
	_label("KINGSWAY COURTS", Vector3(184, 2.9, 165.7), 40, Color(1, 1, 1), PI)
	_landmark("KINGSWAY COURTS", Vector3(184, 0, 176), false)
	_crew_spawn("kingsway", Vector3(178, 0.5, 152.6), -PI * 0.5, Vector3(184, 0.2, 162), Vector3.FORWARD)
	# The Cage: fenced basketball court.
	_block(Rect2(94, 156, 50, 44), Color(0.5, 0.5, 0.49), "tiles")
	_box(Vector3(119, 0.19, 176), Vector3(28, 0.04, 16), Color(0.22, 0.38, 0.42), false, "asphalt")
	_box(Vector3(119, 0.22, 176), Vector3(0.12, 0.02, 16), Color(0.9, 0.9, 0.9))
	for side: float in [-1.0, 1.0]:
		_box(Vector3(119 + side * 13, 1.6, 176), Vector3(0.14, 3.2, 0.14), Color(0.2, 0.2, 0.22))
		_box(Vector3(119 + side * 12.6, 3.2, 176), Vector3(0.08, 1.1, 1.8), Color(0.95, 0.95, 0.95))
	_fence(Vector3(104, 0.16, 167), Vector3(134, 0.16, 167))
	_fence(Vector3(104, 0.16, 185), Vector3(134, 0.16, 185))
	_fence(Vector3(104, 0.16, 167), Vector3(104, 0.16, 172))
	_fence(Vector3(104, 0.16, 180), Vector3(104, 0.16, 185))
	_fence(Vector3(134, 0.16, 167), Vector3(134, 0.16, 185))
	_label("THE CAGE", Vector3(119, 4.2, 166.8), 60, teal, PI)
	_tower(Vector2(119, 194), Vector3(40, 16, 8), concrete, "panel", Vector3.FORWARD, "", Color.WHITE, Color(0.3, 0.3, 0.3), 0.4)
	_landmark("THE CAGE", Vector3(119, 0, 176), false)
	# More towers.
	_block(Rect2(156, 94, 44, 50), Color(0.5, 0.5, 0.49), "tiles")
	_tower(Vector2(168, 112), Vector3(18, 22, 16), concrete.lightened(0.05), "panel", Vector3.LEFT, "", Color.WHITE, Color(0.3, 0.3, 0.3), 0.35)
	_tower(Vector2(188, 128), Vector3(16, 19, 22), concrete, "panel", Vector3.LEFT, "", Color.WHITE, Color(0.3, 0.3, 0.3), 0.35)
	# Corner store, laundromat, mural wall.
	_block(Rect2(94, 94, 50, 50), Color(0.5, 0.5, 0.49), "tiles")
	_tower(Vector2(106, 106), Vector3(16, 5, 14), Color(0.8, 0.78, 0.72), "panel", Vector3.LEFT, "KWIK STOP  24/7", Color(0.35, 1.0, 0.6), Color(0.3, 0.3, 0.3), 0.8, "corner_store")
	_tower(Vector2(106, 125), Vector3(16, 5, 14), Color(0.76, 0.76, 0.8), "panel", Vector3.LEFT, "SPIN CITY", Color(0.4, 0.8, 1.0), Color(0.3, 0.3, 0.3), 0.8, "row_shop")
	_box(Vector3(135, 2, 118), Vector3(0.6, 4, 36), Color(0.6, 0.6, 0.58), true, "panel")
	for index: int in range(8):
		_box(Vector3(134.66, 1.2 + (index % 3) * 0.9, 102 + index * 4.2), Vector3(0.06, 1.6, 3.4), tags[index % 4])
	_label("ROYALS", Vector3(134.6, 2.8, 118), 110, teal, -PI * 0.5)
	_car_prop(Vector3(122, 0.16, 110), 1.2, Color(0.12, 0.11, 0.1))
	_landmark("KWIK STOP", Vector3(106, 0, 106), false)

# --- Neutral common areas -------------------------------------------------------------------

## The Harbor (N): container yard, cranes, cold storage and Pier 9 on the sea wall.
func _build_harbor() -> void:
	_begin("Harbor")
	_street_palette = [Color(0.85, 0.5, 0.15), Color(0.2, 0.45, 0.7), Color(0.6, 0.6, 0.6), Color(0.75, 0.2, 0.15)]
	var yard: Color = Color(0.46, 0.46, 0.44)
	# Paving: the central mole, the thin outer quays, the quay south of the basins, the yards.
	for rect: Rect2 in [Rect2(-26, -200, 52, 28), Rect2(-82, -200, 12, 28), Rect2(70, -200, 12, 28), Rect2(-82, -172, 164, 16), Rect2(-82, -144, 75, 50), Rect2(7, -144, 75, 50)]:
		_box(Vector3(rect.get_center().x, 0.01, rect.get_center().y), Vector3(rect.size.x, 0.02, rect.size.y), yard, false, "panel")
	var colors: Array[Color] = [Color(0.62, 0.22, 0.16), Color(0.18, 0.36, 0.56), Color(0.24, 0.5, 0.36), Color(0.78, 0.6, 0.18), Color(0.3, 0.52, 0.55), Color(0.5, 0.5, 0.5)]
	# Container stacks on the mole either side of Pier Road, and along the basin quay:
	# aisles wide enough to drive through and ambush in.
	for side: float in [-1.0, 1.0]:
		for row: int in range(3):
			var at: Vector3 = Vector3(side * 17.0, 0, -195 + row * 8.5)
			var stack: int = 1 + int(_rng.randi() % 3)
			for level: int in range(stack):
				_container(at + Vector3(0, level * 2.7, 0), colors[(row * 2 + level + (1 if side > 0.0 else 0)) % colors.size()], true)
		for column: int in range(4):
			var yard_at: Vector3 = Vector3(side * (34.0 + column * 9.0), 0, -163.5)
			for level: int in range(1 + int(_rng.randi() % 2)):
				_container(yard_at + Vector3(0, level * 2.7, 0), colors[(column + level) % colors.size()])
	# Ship-to-shore cranes stand on the basin quays with their booms out over the water.
	for crane_x: float in [-48.0, 48.0]:
		for side: float in [-1.0, 1.0]:
			for leg_z: float in [-168.0, -159.0]:
				_box(Vector3(crane_x + side * 7, 13, leg_z), Vector3(1.2, 26, 1.2), Color(0.85, 0.55, 0.15), true)
		_box(Vector3(crane_x, 26.5, -176), Vector3(16, 1.6, 36), Color(0.85, 0.55, 0.15))
		_box(Vector3(crane_x, 24.5, -164), Vector3(4, 3, 4), Color(0.25, 0.25, 0.28), false, "metal")
		_box_with(Vector3(crane_x, 27.6, -194), Vector3(0.6, 0.6, 0.6), _glow(Color(1.0, 0.2, 0.15), 3.0))
	# Bollards along the mole and the basin quays.
	for side: float in [-1.0, 1.0]:
		for z: int in range(-196, -172, 6):
			_cylinder(Vector3(side * 25.2, 0.45, z), 0.3, 0.9, Color(0.2, 0.2, 0.22))
		for x: int in range(28, 70, 8):
			_cylinder(Vector3(side * x, 0.45, -171.2), 0.3, 0.9, Color(0.2, 0.2, 0.22))
	# The MV Halcyon Star, moored in the west basin: cover, a landmark and a skyline.
	var hull: Color = Color(0.22, 0.24, 0.3)
	_box(Vector3(-48, 1.4, -187), Vector3(36, 5.6, 10), hull, true, "metal")
	_box(Vector3(-48, -0.9, -187), Vector3(35, 1.6, 9.4), Color(0.55, 0.14, 0.12), false, "metal")
	_box(Vector3(-31, 2.2, -187), Vector3(3, 4.0, 7), hull, true, "metal")
	_box(Vector3(-61, 7.2, -187), Vector3(8, 6.4, 9), Color(0.9, 0.88, 0.82), true, "panel")
	for deck: int in range(3):
		_box_with(Vector3(-56.95, 5.2 + deck * 1.9, -187), Vector3(0.1, 0.9, 7.4), _glow(Color(1.0, 0.85, 0.55), 1.2))
	_cylinder(Vector3(-63, 12.0, -187), 1.1, 4.0, Color(0.75, 0.2, 0.15), 12)
	for stack: int in range(4):
		_container(Vector3(-50 + stack * 6.5, 4.2, -187), colors[stack % colors.size()], true)
	_neon("HALCYON STAR", Vector3(-48, 3.0, -181.9), 0.0, Color(0.95, 0.9, 0.8), 60)
	# A tug in the east basin.
	_box(Vector3(48, 0.2, -188), Vector3(5, 2.4, 12), Color(0.8, 0.25, 0.15), true, "metal")
	_box(Vector3(48, 2.4, -186), Vector3(3.6, 2.4, 4), Color(0.9, 0.88, 0.82), false, "panel")
	_label("PIER  9", Vector3(-12, 0.06, -190), 80, Color(0.95, 0.85, 0.3), 0.0, 0.03).rotation.x = -PI * 0.5
	_landmark("PIER 9", Vector3(-10, 0, -188))
	_landmark("CONTAINER YARD", Vector3(18, 0, -182))
	_landmark("HALCYON STAR", Vector3(-48, 0, -176))
	# Cold storage warehouse with loading docks.
	_tower(Vector2(-44, -124), Vector3(44, 10, 26), Color(0.62, 0.66, 0.68), "metal", Vector3.BACK, "COLD STORAGE  7", Color(0.5, 0.85, 1.0), Color(0.35, 0.37, 0.38), 0.1)
	for index: int in range(4):
		_box(Vector3(-60 + index * 10, 2.2, -110.9), Vector3(6, 4.4, 0.2), Color(0.3, 0.33, 0.35), false, "metal")
		_box(Vector3(-60 + index * 10, 0.6, -109.8), Vector3(6, 1.2, 2), Color(0.5, 0.5, 0.48), true, "panel")
	_landmark("COLD STORAGE 7", Vector3(-44, 0, -106))
	# Harbor office, trailers and light towers.
	_tower(Vector2(64, -130), Vector3(18, 7, 12), Color(0.8, 0.76, 0.66), "panel", Vector3.LEFT, "HARBOR OFFICE", Color(0.95, 0.85, 0.5), Color(0.3, 0.3, 0.3), 0.6, "row_shop")
	for index: int in range(3):
		_container(Vector3(20 + index * 3.2, 0, -122), colors[index + 2], true)
		_container(Vector3(20 + index * 3.2, 0, -110), colors[index], true)
	for at: Vector3 in [Vector3(-10, 0, -160), Vector3(10, 0, -120), Vector3(-76, 0, -162)]:
		_box(at + Vector3(0, 9, 0), Vector3(0.5, 18, 0.5), Color(0.3, 0.3, 0.32), true)
		_box_with(at + Vector3(0, 18.3, 0), Vector3(2.2, 0.8, 0.5), _glow(Color(1.0, 0.85, 0.6), 2.6))

## Union Station (S): station hall with a clock tower, platforms and a rail yard.
func _build_station() -> void:
	_place("station", "UnionStation")
	_street_palette = [Color(0.8, 0.2, 0.18), Color(0.2, 0.45, 0.75), Color(0.95, 0.75, 0.2), Color(0.25, 0.6, 0.35)]
	var stone: Color = Color(0.8, 0.74, 0.62)
	_block(Rect2(7, 94, 75, 50), Color(0.55, 0.52, 0.47), "tiles")
	_tower(Vector2(47, 123), Vector3(56, 14, 30), stone, "stucco", Vector3.FORWARD, "UNION  STATION", Color(1.0, 0.85, 0.5), Color(0.3, 0.28, 0.26), 0.55)
	_box(Vector3(17, 13, 110), Vector3(7, 26, 7), stone, true, "stucco")
	_box(Vector3(17, 26.6, 110), Vector3(8, 1.2, 8), Color(0.3, 0.28, 0.26), false, "roof")
	_cylinder(Vector3(17, 21, 106.4), 2.2, 0.2, Color.WHITE, 16, _glow(Color(1.0, 0.95, 0.8), 1.4)).rotation.x = PI * 0.5
	_box(Vector3(17, 21.6, 106.2), Vector3(0.18, 1.3, 0.06), Color(0.08, 0.08, 0.1))
	_box(Vector3(17.45, 21, 106.2), Vector3(0.95, 0.14, 0.06), Color(0.08, 0.08, 0.1))
	_landmark("UNION STATION", Vector3(47, 0, 106))
	# Taxi rank and parking with a bus shelter.
	_block(Rect2(-82, 94, 75, 50), Color(0.5, 0.5, 0.48), "tiles")
	for index: int in range(8):
		_box(Vector3(-74 + index * 5, 0.18, 110), Vector3(0.1, 0.02, 6), Color(0.85, 0.82, 0.6))
	_car_prop(Vector3(-66, 0.16, 110), 0.0, Color(0.95, 0.78, 0.1))
	_car_prop(Vector3(-51, 0.16, 110), 0.0, Color(0.95, 0.78, 0.1))
	_car_prop(Vector3(-36, 0.16, 126), 0.0, Color(0.5, 0.52, 0.55))
	_box(Vector3(-20, 2.6, 104), Vector3(8, 0.2, 3), Color(0.2, 0.22, 0.25))
	_box(Vector3(-20, 1.3, 105.4), Vector3(8, 2.6, 0.1), Color(0.5, 0.6, 0.65), true)
	_neon("TAXI", Vector3(-58, 4, 101.2), PI, Color(1.0, 0.85, 0.2), 60)
	# Rail yard: two tracks, a platform between them, a parked train and freight cars.
	for span: Vector2 in [Vector2(-82, -7), Vector2(7, 82)]:
		_box(Vector3((span.x + span.y) * 0.5, 0.02, 176), Vector3(span.y - span.x, 0.03, 44), Color(0.36, 0.33, 0.3), false, "roof")
	for rail_z: float in RAILS:
		for side: float in [-1.0, 1.0]:
			for span: Vector2 in [Vector2(-82, -7), Vector2(7, 82)]:
				_box(Vector3((span.x + span.y) * 0.5, 0.1, rail_z + side * 0.72), Vector3(span.y - span.x, 0.12, 0.1), Color(0.5, 0.48, 0.45))
		for x: int in range(-81, 82, 2):
			if absi(x) > 8:
				_box(Vector3(x, 0.05, rail_z), Vector3(0.3, 0.08, 2.4), Color(0.3, 0.22, 0.16))
	# Platform ends are ramps (0.9 m over 1.3 m) so players can walk up them.
	_slab(Rect2(-80, 171, 72, 4), Color(0.6, 0.58, 0.52), "tiles", 0.9, 1.3)
	_slab(Rect2(8, 171, 72, 4), Color(0.6, 0.58, 0.52), "tiles", 0.9, 1.3)
	for x: int in range(-76, 80, 12):
		if absi(x) > 10:
			_box(Vector3(x, 2.4, 173), Vector3(0.25, 3.2, 0.25), Color(0.25, 0.27, 0.28))
	_box(Vector3(-44, 4.1, 173), Vector3(72, 0.25, 5), Color(0.25, 0.3, 0.32), false, "metal")
	_box(Vector3(44, 4.1, 173), Vector3(72, 0.25, 5), Color(0.25, 0.3, 0.32), false, "metal")
	for index: int in range(3):
		var at: Vector3 = Vector3(-68 + index * 17, 0.3, 178)
		_box(at + Vector3(0, 2.0, 0), Vector3(16, 3.6, 3.1), Color(0.62, 0.64, 0.66), true, "metal")
		_box_with(at + Vector3(0, 2.6, 1.57), Vector3(14, 0.9, 0.05), _glow(Color(1.0, 0.85, 0.6), 1.0))
		_box(at + Vector3(0, 1.2, 1.57), Vector3(16, 0.3, 0.06), Factions.color(Factions.ORDER[index]))
	for index: int in range(4):
		_box(Vector3(22 + index * 15, 2.0, 168), Vector3(14, 3.6, 3.0), [Color(0.45, 0.22, 0.15), Color(0.25, 0.3, 0.35), Color(0.5, 0.42, 0.2), Color(0.3, 0.38, 0.28)][index], true, "metal")
	for side: float in [-1.0, 1.0]:
		_box(Vector3(side * 9, 1.2, 164), Vector3(0.2, 2.4, 0.2), Color(0.9, 0.9, 0.9))
		_box(Vector3(side * 5.5, 2.3, 164), Vector3(7, 0.18, 0.18), Color(0.85, 0.15, 0.12))
	_landmark("RAIL YARD", Vector3(-40, 0, 176))

## Canal Market (NW): the city's one remaining canal, a dead-end inlet from the sea with a
## boat basin at its head. Harbor Road runs past the basin, the North Shore Road bridge and
## a footbridge cross the inlet, and the open-air market square sits south of Harbor Road.
func _build_canal_market() -> void:
	_begin("CanalMarket")
	_street_palette = [Color(0.85, 0.3, 0.2), Color(0.25, 0.55, 0.8), Color(0.95, 0.8, 0.25), Color(0.3, 0.65, 0.4)]
	var canopies: Array[Color] = [Color(0.85, 0.25, 0.2), Color(0.2, 0.55, 0.8), Color(0.95, 0.75, 0.2), Color(0.3, 0.65, 0.35)]
	# West bank: the fish hall faces the inlet across its quay.
	# Both bank blocks stop short of North Shore Road's curve (their corners used to put a
	# kerbed plinth on the carriageway at x -228 and x -100, z -206).
	_block(Rect2(-229, -205, 42, 49), Color(0.5, 0.48, 0.44), "cobble")
	_tower(Vector2(-210, -186), Vector3(17, 7, 36), Color(0.6, 0.64, 0.66), "metal", Vector3.RIGHT, "FISH HALL", Color(0.5, 0.9, 1.0), Color(0.3, 0.33, 0.35), 0.2, "warehouse")
	for index: int in range(3):
		_box(Vector3(-199.5, 2.2, -198 + index * 12), Vector3(0.2, 4.4, 6), Color(0.3, 0.33, 0.35), false, "metal")
		_box(Vector3(-198.4, 0.76, -198 + index * 12), Vector3(2, 1.2, 6), Color(0.5, 0.5, 0.48), true, "panel")
	_landmark("FISH HALL", Vector3(-196, 0, -186))
	# East bank: warehouse lofts over the basin, with kiosks on the quay.
	_block(Rect2(-149, -201, 55, 45), Color(0.5, 0.48, 0.44), "cobble")
	_tower(Vector2(-122, -190), Vector3(40, 13, 18), Color(0.6, 0.42, 0.3), "brick", Vector3.BACK, "CANAL LOFTS", Color(1.0, 0.8, 0.5), Color(0.28, 0.25, 0.24), 0.45, "walkup")
	for at: Vector3 in [Vector3(-142, 0.16, -170), Vector3(-130, 0.16, -166), Vector3(-196, 0.16, -150 + -14)]:
		_box(at + Vector3(0, 1.4, 0), Vector3(4, 2.8, 3), Color(0.25, 0.42, 0.36), true, "planks")
		_box(at + Vector3(0, 3.0, 0), Vector3(4.8, 0.3, 3.8), Color(0.72, 0.36, 0.22), false, "roof")
	for x: float in [-145.0, -110.0, -100.0]:
		_tree(Vector3(x, 0.16, -162))
	# Boats in the basin and moored along the inlet.
	for boat: Vector3 in [Vector3(-176, 0, -168), Vector3(-160, 0, -167), Vector3(-168, 0, -204)]:
		_box(boat + Vector3(0, -0.7, 0), Vector3(3.0, 1.2, 6.0), Color(0.92, 0.9, 0.86), true, "panel")
		_box(boat + Vector3(0, 0.1, 0.8), Vector3(2.0, 0.9, 2.4), Color(0.2, 0.36, 0.45), false, "panel")
	_landmark("CANAL BASIN", Vector3(-168, 0, -156))
	_landmark("CANAL BRIDGE", Vector3(-168, 0, -217))
	# South of Harbor Road: a warehouse and the open-air market square.
	_block(Rect2(-173, -144, 50, 38), Color(0.52, 0.5, 0.45), "cobble")
	plazas.append(PackedVector2Array([Vector2(-173, -144), Vector2(-123, -144), Vector2(-123, -106), Vector2(-173, -106)]))
	for row: int in range(3):
		for column: int in range(4):
			var at: Vector3 = Vector3(-164 + column * 9.5, 0.16, -135 + row * 10.5)
			_box(at + Vector3(0, 0.55, 0), Vector3(3.2, 1.1, 1.6), Color(0.5, 0.36, 0.24), true, "planks")
			for post_x: float in [-1.5, 1.5]:
				_box(at + Vector3(post_x, 1.3, -0.9), Vector3(0.08, 2.6, 0.08), Color(0.3, 0.3, 0.3))
			_box(at + Vector3(0, 2.6, -0.3), Vector3(3.6, 0.1, 2.8), canopies[(row + column) % 4])
	_neon("CANAL MARKET", Vector3(-148, 5.2, -143.7), 0.0, Color(1.0, 0.8, 0.35), 64, true)
	_box(Vector3(-148, 2.4, -143.9), Vector3(0.3, 4.8, 0.3), Color(0.25, 0.27, 0.28))
	_landmark("CANAL MARKET", Vector3(-148, 0, -126))
	# East of the square, a covered produce hall.
	_block(Rect2(-117, -144, 23, 38), Color(0.5, 0.48, 0.44), "cobble")
	_tower(Vector2(-105.5, -125), Vector3(16, 6, 30), Color(0.74, 0.7, 0.6), "stucco", Vector3.LEFT, "PRODUCE", Color(0.5, 1.0, 0.5), Color(0.72, 0.36, 0.22), 0.5, "warehouse")

## Waterfront landmarks that went with the crew turf: Lantern Point's pagoda on its
## headland, the Solana lookout on the north-east cape, Morris Marina's jetty and the
## Kingsway Docks pier.
func _build_waterfronts() -> void:
	_begin("Waterfronts")
	_street_palette = [Color(0.6, 0.6, 0.6), Color(0.3, 0.5, 0.7), Color(0.8, 0.7, 0.4), Color(0.4, 0.6, 0.4)]
	var slate: Color = Color(0.16, 0.16, 0.2)
	var violet: Color = Factions.color("kojimoto")
	var base: Vector3 = Vector3(-391, 0, -58)
	for tier: int in range(5):
		var width: float = 7.0 - tier * 1.1
		_box(base + Vector3(0, 1.0 + tier * 2.6, 0), Vector3(width, 2.0, width), Color(0.55, 0.12, 0.12), tier == 0, "planks")
		_box(base + Vector3(0, 2.2 + tier * 2.6, 0), Vector3(width + 2.2, 0.35, width + 2.2), slate, false, "roof")
	_cylinder(base + Vector3(0, 15.5, 0), 0.12, 3.0, Color(0.8, 0.7, 0.3), 6)
	_box_with(base + Vector3(3.6, 1.3, 0), Vector3(0.1, 1.6, 1.2), _glow(violet, 1.8))
	for at: Vector3 in [Vector3(-387, 0, -42), Vector3(-395, 0, -74), Vector3(-388, 0, -80)]:
		_tree(at, "blossom")
	_landmark("LANTERN POINT", base + Vector3(6, 0, 0), false)
	# Solana Lookout: a whitewashed gazebo and palms on the north-east cape.
	var solana: Vector3 = Vector3(330, 0, -265)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_box(solana + Vector3(corner.x * 3.0, 1.6, corner.y * 3.0), Vector3(0.4, 3.2, 0.4), Color(0.95, 0.93, 0.88), true, "stucco")
	_box(solana + Vector3(0, 3.4, 0), Vector3(7.4, 0.4, 7.4), Color(0.72, 0.36, 0.22), false, "roof")
	_cylinder(solana + Vector3(0, 0.3, 0), 3.4, 0.6, Color(0.9, 0.86, 0.76), 12)
	for at: Vector3 in [Vector3(346, 0, -262), Vector3(314, 0, -262), Vector3(360, 0, -268)]:
		_tree(at, "palm")
	_landmark("SOLANA LOOKOUT", solana, false)
	# Morris Marina: cabin cruisers along the jetty.
	for index: int in range(4):
		var z: float = 372.0 + index * 7.0
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var boat: Vector3 = Vector3(-80 + side * 5.2, 0, z)
		_box(boat + Vector3(0, -0.6, 0), Vector3(3.0, 1.4, 6.5), Color(0.95, 0.95, 0.94), true, "panel")
		_box(boat + Vector3(0, 0.6, 0.6), Vector3(2.2, 1.0, 3.0), Color(0.2, 0.3, 0.4), false, "panel")
		_box(boat + Vector3(0, -0.2, 0), Vector3(3.05, 0.2, 6.55), Factions.color("morris"))
	_box(Vector3(-80, 0.06, 384), Vector3(8, 0.12, 32), Color(0.55, 0.4, 0.26), false, "planks")
	_neon("MORRIS MARINA", Vector3(-80, 3.8, 363.6), PI, Color(1.0, 0.8, 0.5), 56)
	_box(Vector3(-80, 1.9, 363.8), Vector3(0.3, 3.8, 0.3), Color(0.3, 0.3, 0.3))
	_landmark("MORRIS MARINA", Vector3(-80, 0, 384), false)
	# Kingsway Docks: a working pier with a crane, crates and an old trawler.
	var dock: Vector3 = Vector3(DOCKS_SHIFT.x, 0, DOCKS_SHIFT.y)
	_box(dock + Vector3(253, 0.06, 60), Vector3(34, 0.12, 10), Color(0.5, 0.48, 0.44), false, "panel")
	_box(dock + Vector3(260, 0.2, 70.5), Vector3(14, 2.4, 5), Color(0.2, 0.45, 0.42), true, "metal")
	_box(dock + Vector3(256, 2.6, 70.5), Vector3(4, 2.4, 3.6), Color(0.9, 0.88, 0.82), false, "panel")
	_box(dock + Vector3(246, 5, 57), Vector3(0.6, 10, 0.6), Factions.color("kingsway"), true)
	_box(dock + Vector3(250, 9.8, 57), Vector3(9, 0.5, 0.5), Factions.color("kingsway"))
	for at: Vector3 in [Vector3(240, 0.1, 58), Vector3(241.4, 0.1, 58), Vector3(240.6, 1.3, 58), Vector3(264, 0.1, 58)]:
		_crate(dock + at)
	_landmark("KINGSWAY DOCKS", dock + Vector3(252, 0, 60), false)
	# Lamps along the waterfront drives.
	for road: Dictionary in roads:
		var title: String = str(road["name"])
		if title in ["SOLANA BLUFF DRIVE", "NORTH SHORE ROAD", "EAST SHORE DRIVE", "COAST ROAD"]:
			var points: PackedVector2Array = road["points"]
			for index: int in range(1, points.size() - 1, 3):
				var direction: Vector2 = (points[index + 1] - points[index - 1]).normalized()
				var outward: Vector2 = Vector2(-direction.y, direction.x)
				var at: Vector2 = points[index] + outward * 7.2
				if not _on_land(at) or _near_other_road(at, roads.find(road), 1.0):
					at = points[index] - outward * 7.2
					outward = -outward
				if _on_land(at) and not _near_other_road(at, roads.find(road), 1.0) and not _on_carriageway(at, 0.3):
					_lamp(Vector3(at.x, 0.0, at.y), Vector3(-outward.x, 0, -outward.y).normalized().round())

## Open squares and parks between the neighbourhoods: fountains, statues, trees, benches
## and waist-high planters and walls (cover without walls of text: everything is solid
## exactly where it looks solid).
func _build_plazas() -> void:
	_begin("Plazas")
	_street_palette = [Color(0.8, 0.2, 0.18), Color(0.2, 0.45, 0.75), Color(0.95, 0.75, 0.2), Color(0.25, 0.6, 0.35)]
	var stone: Color = Color(0.78, 0.74, 0.66)
	# West Bank Plaza: between Lantern Row and Union Street, a statue on a plinth.
	var west: Rect2 = Rect2(-182, 15, 59, 14)
	_slab(west, Color(0.56, 0.53, 0.48), "tiles")
	plazas.append(_rect_poly(west))
	_box(Vector3(-152, 0.96, 20.5), Vector3(3.2, 1.6, 3.2), stone, true, "stucco")
	_box(Vector3(-152, 3.06, 20.5), Vector3(0.9, 2.6, 0.7), Color(0.3, 0.42, 0.36), true, "metal")
	_box(Vector3(-152, 4.66, 20.5), Vector3(0.5, 0.6, 0.5), Color(0.3, 0.42, 0.36), false, "metal")
	for x: float in [-174.0, -164.0, -138.0, -128.0]:
		_tree(Vector3(x, 0.16, 20.5))
	for x: float in [-171.0, -161.0, -143.0, -133.0]:
		_bench(Vector3(x, 0.16, 16.0), PI)
		_planter(Vector3(x, 0.16, 25.0))
	_landmark("WEST BANK PLAZA", Vector3(-152, 0, 24))
	# Slip Park: lawns and a promenade between Union Street and the station.
	var slip: Rect2 = Rect2(-182, 41, 51, 11)
	_slab(slip, Color(0.52, 0.5, 0.45), "tiles")
	plazas.append(_rect_poly(slip))
	for x: float in [-172.0, -158.0, -144.0]:
		_tree(Vector3(x, 0.16, 46.5))
	_landmark("WEST SLIP", Vector3(-214, 0, 35))
	# Fountain Square: a roundabout island with a three-tier fountain, in Eastside Park.
	var center: Vector3 = Vector3(FOUNTAIN.x, 0, FOUNTAIN.y)
	_cylinder(center + Vector3(0, 0.12, 0), 11.0, 0.24, stone, 24, _material(Color(0.56, 0.53, 0.48), 0.9, "tiles"))
	_cylinder(center + Vector3(0, 0.55, 0), 5.0, 0.9, stone, 20)
	_collider(center + Vector3(0, 0.45, 0), Vector3(7.0, 0.9, 7.0))
	_cylinder(center + Vector3(0, 1.02, 0), 4.6, 0.08, Color.WHITE, 20, _material(Color(0.2, 0.4, 0.46), 0.1, "water"))
	_cylinder(center + Vector3(0, 2.0, 0), 0.5, 2.2, stone, 10)
	_cylinder(center + Vector3(0, 3.2, 0), 1.6, 0.3, stone, 14)
	_cylinder(center + Vector3(0, 4.0, 0), 0.25, 1.4, stone, 8)
	var island: PackedVector2Array = PackedVector2Array()
	for step: int in range(16):
		island.append(FOUNTAIN + Vector2(cos(step * TAU / 16.0), sin(step * TAU / 16.0)) * 11.0)
	plazas.append(island)
	for angle: float in [0.4, 2.0, 3.6, 5.2]:
		_tree(center + Vector3(cos(angle), 0, sin(angle)) * 8.5 + Vector3(0, 0.24, 0))
	_landmark("FOUNTAIN SQUARE", center + Vector3(0, 0, 12))
	# Eastside Park round the square: lawns, trees, benches and low stone walls.
	plazas.append(PackedVector2Array([Vector2(103, -94), Vector2(221, -94), Vector2(221, -27), Vector2(103, -27)]))
	_box(Vector3(162, 0.02, -60), Vector3(118, 0.03, 66), Color(0.3, 0.42, 0.27), false, "grass")
	for at: Vector2 in [Vector2(112, -86), Vector2(126, -84), Vector2(112, -34), Vector2(128, -36), Vector2(180, -88), Vector2(186, -40), Vector2(180, -30), Vector2(138, -86), Vector2(176, -84)]:
		_tree(Vector3(at.x, 0.0, at.y))
	for wall: Array in [[Vector3(120, 0, -70), 10.0, 0.0], [Vector3(186, 0, -65.5), 12.0, 0.0], [Vector3(182, 0, -44), 10.0, PI * 0.5], [Vector3(128, 0, -44), 8.0, PI * 0.5]]:
		_box_with((wall[0] as Vector3) + Vector3(0, 0.45, 0), Vector3(float(wall[1]), 0.9, 0.5), _material(stone, 0.9, "stucco"), true, float(wall[2]))
	for at: Vector3 in [Vector3(120, 0, -73), Vector3(186, 0, -68.5), Vector3(140, 0, -30)]:
		_bench(at, 0.0)
	_landmark("EASTSIDE PARK", Vector3(190, 0, -58))
	# Eastgate: a hotel and a bank tower face the park from the north-east.
	for at: Vector2 in [Vector2(196, -73), Vector2(206, -70), Vector2(214, -84)]:
		_tree(Vector3(at.x, 0.0, at.y))
	_tower(Vector2(204, -38), Vector3(16, 30, 18), Color(0.46, 0.5, 0.52), "panel", Vector3.LEFT, "HALCYON SAVINGS", Color(0.6, 0.9, 1.0), Color(0.28, 0.3, 0.3), 0.35)

# --- 0.6 districts: the new ring of land -------------------------------------------------------

## Block-filling styles: heights, colours, textures and shop signs for the generic buildings of
## the new districts. (The hand-authored kits and Midtown keep their own art.)
const FILL_STYLES: Dictionary = {
	"highrise": {"height": Vector2(30.0, 62.0), "colors": [Color(0.42, 0.46, 0.5), Color(0.5, 0.55, 0.58), Color(0.36, 0.4, 0.46), Color(0.55, 0.52, 0.47)], "tex": "panel", "lit": 0.45, "width": Vector2(20.0, 30.0), "signs": ["HALCYON BANK", "MERIDIAN TRUST", "PORT LIFE", "CARLYLE & CO", "NORTHLINE", "UNION MUTUAL"], "sign_color": Color(0.7, 0.9, 1.0)},
	"midrise": {"height": Vector2(14.0, 26.0), "colors": [Color(0.6, 0.55, 0.47), Color(0.5, 0.52, 0.5), Color(0.66, 0.6, 0.5), Color(0.44, 0.46, 0.5)], "tex": "stucco", "lit": 0.4, "width": Vector2(16.0, 24.0), "signs": ["LAW OFFICES", "MERCURY CLINIC", "ATLAS INSURANCE", "PARK VIEW APTS"], "sign_color": Color(0.95, 0.85, 0.6)},
	"brick": {"height": Vector2(9.0, 17.0), "colors": [Color(0.56, 0.3, 0.24), Color(0.62, 0.38, 0.28), Color(0.5, 0.27, 0.25), Color(0.66, 0.46, 0.34)], "tex": "brick", "lit": 0.4, "width": Vector2(11.0, 17.0), "signs": ["DELI", "HARDWARE", "TAILOR", "CORNER PUB", "PHARMACY", "BARBER"], "sign_color": Color(1.0, 0.85, 0.55)},
	"warehouse": {"height": Vector2(7.0, 11.0), "colors": [Color(0.5, 0.52, 0.5), Color(0.42, 0.46, 0.5), Color(0.55, 0.5, 0.42), Color(0.36, 0.42, 0.4)], "tex": "metal", "lit": 0.08, "width": Vector2(20.0, 32.0), "signs": ["CARGO WORKS", "COLD STORE", "SHIPPING CO", "TIMBER YARD", "NET LOFT", "CANNERY"], "sign_color": Color(0.9, 0.8, 0.45)},
	"neon": {"height": Vector2(7.0, 13.0), "colors": [Color(0.16, 0.14, 0.2), Color(0.2, 0.16, 0.24), Color(0.12, 0.14, 0.2), Color(0.24, 0.16, 0.2)], "tex": "panel", "lit": 0.6, "width": Vector2(14.0, 22.0), "signs": ["LUCKY DRAGON", "SILVER SLIPPER", "CASINO ORIOLE", "THE 400 CLUB", "SPIN PALACE", "DICE & DIAMONDS", "AMBER STAR CLUB", "CLUB ORBIT"], "sign_color": Color(1.0, 0.45, 0.85)},
	"flats": {"height": Vector2(10.0, 20.0), "colors": [Color(0.64, 0.6, 0.52), Color(0.58, 0.62, 0.6), Color(0.68, 0.56, 0.48), Color(0.52, 0.54, 0.6)], "tex": "stucco", "lit": 0.4, "width": Vector2(14.0, 22.0), "signs": [], "sign_color": Color(1.0, 0.9, 0.7)},
}

## An enterable prefab standing where a hand-placed `_tower` would have been (kit or world frame): the
## footprint is the tower's, the front faces the same way. False if the library or the kind is missing or the
## lot is smaller than the prefab's minimum.
func _tower_prefab(kind: String, center: Vector2, size: Vector3, color: Color, front: Vector3, title: String) -> bool:
	var lib: Variant = _prefab_library()
	if lib == null or not lib.kinds().has(kind):
		return false
	var world_front: Vector3 = (_xf.basis * front).normalized()
	var across: bool = absf(front.z) > 0.5
	var frontage: float = size.x if across else size.z
	var depth: float = size.z if across else size.x
	var least: Vector2 = lib.min_size(kind)
	if frontage < least.x or depth < least.y:
		return false
	var at: Vector2 = _w2(center)
	var floors: int = clampi(int(size.y / 3.4), 1, int(lib.max_floors(kind)))
	var seed: int = absi(int(at.x * 131.0) * 7919 + int(at.y * 977.0)) + 31
	var palette: Array[Color] = [color, color.lightened(0.35), color.darkened(0.35)]
	var saved_xf: Transform3D = _xf
	var saved_yaw: float = _xf_yaw
	var saved_target: Node3D = _target
	_begin_building(kind, true, title)
	var record: Dictionary = _building_open
	var node: Variant = lib.build(self, kind, at, Vector2(frontage, depth), lib.front_yaw(world_front), floors, seed, {"palette": palette, "sign": title, "lit": 0.4, "district": "hand"})
	_end_building()
	_xf = saved_xf
	_xf_yaw = saved_yaw
	_target = saved_target
	if node == null:
		buildings.erase(record)
		return false
	if (record["footprints"] as Array).is_empty():
		_footprint(Rect2(center.x - size.x * 0.5, center.y - size.z * 0.5, size.x, size.z))
		(record["footprints"] as Array).append(footprint_polys.size() - 1)
		buildings.pop_back()
	_finish(node as Node3D)
	limit_range(node as Node3D, NEAR_RANGE)
	lod_lots.append({"center": at, "size": Vector3(size.x, floors * 3.4 + 1.2, size.z), "yaw": _xf_yaw, "color": color})
	return true

## Which prefab kinds fill each generic style (best fit first); the high-rises stay solid towers.
const FILL_PREFABS: Dictionary = {
	"brick": ["walkup", "row_shop", "corner_store"],
	"flats": ["walkup", "row_shop"],
	"midrise": ["office", "walkup"],
	"neon": ["bar", "row_shop"],
	"warehouse": ["warehouse", "auto_shop"],
}

## Fills a block's buildable rectangle with one or two rows of generic buildings. Lots whose
## rectangle meets `keep_clear` (a reserved plot) are left out. Front faces the nearer street.
func _fill_block(area: Rect2, style: String, keep_clear: Rect2 = Rect2()) -> void:
	var spec: Dictionary = FILL_STYLES[style]
	var along_x: bool = area.size.x >= area.size.y
	var length: float = area.size.x if along_x else area.size.y
	var depth: float = area.size.y if along_x else area.size.x
	var rows: int = 2 if depth >= 32.0 else 1
	# Two rows back to back leave a 5 m alley between them (rear doors, dumpsters, a way through).
	var row_gap: float = 5.0 if rows == 2 else 0.0
	var row_depth: float = (depth - row_gap) / rows
	var widths: Vector2 = spec["width"]
	for row: int in range(rows):
		var cursor: float = 0.0
		var side: float = -1.0 if row == 0 else 1.0
		while length - cursor > 9.0:
			var span: float = minf(_rng.randf_range(widths.x, widths.y), length - cursor)
			if length - cursor - span < 9.0:
				span = length - cursor
			var lot_center: float = cursor + span * 0.5
			var offset: float = (row_depth * 0.5 + row_gap * 0.5) * side if rows == 2 else 0.0
			var center: Vector2 = Vector2(area.position.x + lot_center, area.get_center().y + offset) if along_x else Vector2(area.get_center().x + offset, area.position.y + lot_center)
			var lot_size: Vector2 = Vector2(span, row_depth) if along_x else Vector2(row_depth, span)
			cursor += span + (3.4 if style == "warehouse" else 0.8)
			var lot: Rect2 = Rect2(center - lot_size * 0.5, lot_size)
			if keep_clear.size != Vector2.ZERO and lot.intersects(keep_clear.grow(1.0)):
				continue
			var height: float = _rng.randf_range(float(spec["height"].x), float(spec["height"].y))
			var colors: Array = spec["colors"]
			var color: Color = colors[_rng.randi() % colors.size()]
			var front: Vector3
			if along_x:
				front = Vector3.FORWARD if side < 0.0 else Vector3.BACK
				if rows == 1:
					front = Vector3.BACK if _rng.randf() < 0.5 else Vector3.FORWARD
			else:
				front = Vector3.LEFT if side < 0.0 else Vector3.RIGHT
				if rows == 1:
					front = Vector3.RIGHT if _rng.randf() < 0.5 else Vector3.LEFT
			var signs: Array = spec["signs"]
			var title: String = ""
			if not signs.is_empty() and _rng.randf() < 0.65:
				title = str(signs[_rng.randi() % signs.size()])
				# Same random draw as before; a third copy of a generic sign becomes the least-used one.
				if int(_sign_uses.get(title, 0)) >= 2:
					for option: Variant in signs:
						if int(_sign_uses.get(str(option), 0)) < int(_sign_uses.get(title, 0)):
							title = str(option)
				_sign_uses[title] = int(_sign_uses.get(title, 0)) + 1
			var sign_color: Color = spec["sign_color"]
			if style == "neon":
				sign_color = [Color(1.0, 0.45, 0.85), Color(0.3, 0.9, 1.0), Color(1.0, 0.85, 0.3), Color(0.5, 1.0, 0.45)][_rng.randi() % 4]
			var roof: Color = Color(0.29, 0.31, 0.3)
			if _fill_prefab(style, center, lot_size, front, height, color, title):
				continue
			_tower(center, Vector3(lot_size.x, height, lot_size.y), color, str(spec["tex"]), front, title, sign_color, roof, float(spec["lit"]))
			_rooftop(center, lot_size, height)
	# Dumpsters and bags along the alley between the rows.
	if rows == 2:
		var stops: int = maxi(1, int(length / 26.0))
		for stop: int in range(stops):
			var along: float = (stop + 0.5) * length / stops
			var wall_side: float = -1.0 if stop % 2 == 0 else 1.0
			var spot: Vector2 = Vector2(area.position.x + along, area.get_center().y + wall_side * 1.4) if along_x else Vector2(area.get_center().x + wall_side * 1.4, area.position.y + along)
			if _free_spot(_w2(spot), 0.7):
				_occupied.append(_w2(spot))
				_dumpster(Vector3(spot.x, 0.16, spot.y), 0.0 if along_x else PI * 0.5, Color(0.2, 0.33, 0.26))

## The prefab library (scripts/buildings/prefabs.gd), or null while it is not in the project.
var _prefab_lib: Variant = null
var _prefab_checked: bool = false

func _prefab_library() -> Variant:
	if not _prefab_checked:
		_prefab_checked = true
		if ResourceLoader.exists("res://scripts/buildings/prefabs.gd"):
			_prefab_lib = load("res://scripts/buildings/prefabs.gd")
	return _prefab_lib

## Fills a block lot with an enterable prefab instead of a solid tower: the kinds a style may use, best
## fit first. Returns false when the library is missing, the style keeps its solid towers (the high-rises)
## or no kind fits the lot. Axis-aligned lots in world space (district nodes have no transform).
func _fill_prefab(style: String, center: Vector2, lot: Vector2, front: Vector3, height: float, color: Color, title: String) -> bool:
	var lib: Variant = _prefab_library()
	if lib == null or not FILL_PREFABS.has(style):
		return false
	var across: bool = absf(front.z) > 0.5
	var frontage: float = lot.x if across else lot.y
	var depth: float = lot.y if across else lot.x
	for kind: String in FILL_PREFABS[style]:
		if not lib.kinds().has(kind):
			continue
		var least: Vector2 = lib.min_size(kind)
		if frontage < least.x or depth < least.y:
			continue
		var floors: int = clampi(int(height / 3.4), 1, int(lib.max_floors(kind)))
		var palette: Array[Color] = [color, color.lightened(0.35), color.darkened(0.35)]
		var seed: int = absi(int(center.x * 131.0) * 7919 + int(center.y * 977.0)) + 17
		_begin_building(kind, true, title)
		var record: Dictionary = _building_open
		var node: Variant = lib.build(self, kind, center, Vector2(frontage, depth), lib.front_yaw(front), floors, seed, {"palette": palette, "sign": title, "lit": 0.3, "district": style})
		_end_building()
		if node == null:
			buildings.erase(record)
			continue
		if (record["footprints"] as Array).is_empty():
			_footprint(Rect2(center - lot * 0.5, lot))
			(record["footprints"] as Array).append(footprint_polys.size() - 1)
			buildings.pop_back()
		_finish(node as Node3D)
		limit_range(node as Node3D, NEAR_RANGE)
		lod_lots.append({"center": center, "size": Vector3(lot.x, height, lot.y), "yaw": 0.0, "color": color})
		return true
	return false

## Draws every mesh under `node` only within `metres` (interiors keep their own shorter range).
func limit_range(node: Node3D, metres: float) -> void:
	for child: Node in node.find_children("*", "GeometryInstance3D", true, false):
		var geometry: GeometryInstance3D = child as GeometryInstance3D
		if geometry.visibility_range_end <= 0.0:
			geometry.visibility_range_end = metres
			geometry.visibility_range_end_margin = 6.0
		_detail_ranges.append(geometry)

## A water tank and a vent stack on a roof (breaks up the skyline; nothing solid).
func _rooftop(center: Vector2, size: Vector2, height: float) -> void:
	if size.x < 10.0 or size.y < 10.0 or _rng.randf() < 0.35:
		return
	var at: Vector3 = Vector3(center.x + _rng.randf_range(-0.25, 0.25) * size.x, height + 0.32, center.y + _rng.randf_range(-0.25, 0.25) * size.y)
	if not _roofs.is_empty():
		_roofs.back()["taken"] = _w2(Vector2(at.x, at.z))
	if _rng.randf() < 0.5:
		_cylinder(at + Vector3(0, 1.4, 0), 1.3, 2.4, Color(0.4, 0.3, 0.24), 8)
		_cylinder(at + Vector3(0, 2.8, 0), 0.2, 0.7, Color(0.2, 0.2, 0.22), 6)
	else:
		_box(at + Vector3(0, 0.7, 0), Vector3(2.4, 1.4, 1.8), Color(0.45, 0.47, 0.46), false, "metal")
		_box(at + Vector3(0.6, 1.7, 0.2), Vector3(0.5, 1.2, 0.5), Color(0.3, 0.3, 0.32))

## One block of a district: the paved plinth, then its buildings (unless a plot or park takes it).
func _district_block(rect: Rect2, style: String, paving: Color = Color(0.46, 0.45, 0.43), keep_clear: Rect2 = Rect2()) -> Rect2:
	# Lamps go up after the buildings, so none stands in a prefab's doorway.
	var buildable: Rect2 = _block(rect, paving, "tiles", false)
	if style != "":
		_fill_block(buildable, style, keep_clear)
	_block_lamps(rect)
	return buildable

## A small paved park in a block: lawn, path, trees and benches (cover, no walls of text).
func _pocket_park(rect: Rect2) -> void:
	_block(rect, Color(0.4, 0.42, 0.36), "tiles")
	var lawn: Rect2 = rect.grow(-3.2)
	_box(Vector3(lawn.get_center().x, 0.2, lawn.get_center().y), Vector3(lawn.size.x, 0.05, lawn.size.y), Color(0.32, 0.44, 0.28), false, "grass")
	plazas.append(_rect_poly(rect))
	var trees: int = maxi(3, int(rect.get_area() / 260.0))
	for index: int in range(trees):
		var at: Vector2 = Vector2(_rng.randf_range(lawn.position.x + 2.0, lawn.end.x - 2.0), _rng.randf_range(lawn.position.y + 2.0, lawn.end.y - 2.0))
		# The two crossing paths (city_detail.gd's park sites) stay open.
		if absf(at.x - rect.get_center().x) < 3.2 or absf(at.y - rect.get_center().y) < 3.2:
			continue
		_tree(Vector3(at.x, 0.2, at.y))
	_bench(Vector3(lawn.get_center().x, 0.2, lawn.position.y + 1.6), 0.0)
	_bench(Vector3(lawn.get_center().x, 0.2, lawn.end.y - 1.6), PI)

## A row of parking bays with a few cars (Motor Mile, Nightlife, the docks).
func _parking_row(from: Vector3, count: int, direction: Vector3, colors: Array[Color], car_every: int = 2) -> void:
	var across: Vector3 = Vector3(-direction.z, 0, direction.x)
	for index: int in range(count):
		var at: Vector3 = from + direction * (index * 3.2)
		_box(at + across * 2.8 + Vector3(0, 0.05, 0), Vector3(0.09, 0.015, 5.2) if absf(direction.x) > 0.5 else Vector3(5.2, 0.015, 0.09), Color(0.74, 0.7, 0.53))
		if index % car_every == 0 and index < count - 1:
			var color: Color = colors[_rng.randi() % colors.size()]
			var yaw: float = atan2(across.x, across.z)
			_car_prop(at + direction * 1.6 + across * 2.8, yaw + PI, color, ["sedan", "coupe", "suv", "pickup"][_rng.randi() % 4])

## A tall pole sign (Motor Mile pylons, the wharf's cannery).
func _pylon(at: Vector3, words: String, color: Color, angle: float, height: float = 12.0) -> void:
	_box(at + Vector3(0, height * 0.5, 0), Vector3(0.5, height, 0.5), Color(0.3, 0.3, 0.32), true, "metal")
	_neon(words, at + Vector3(0, height + 1.6, 0), angle, color, 64)

## Uptown: the tower blocks north-east of Midtown, between the harbour and Fountain Square.
## The HALCYON TRUST high-rise and the HOTEL MERIDIAN plots sit on its northern blocks.
func _build_uptown() -> void:
	_begin("Uptown")
	_street_palette = [Color(0.3, 0.4, 0.55), Color(0.75, 0.75, 0.78), Color(0.85, 0.7, 0.3), Color(0.25, 0.5, 0.45)]
	_district_block(Rect2(106, -200, 38, 44), "", Color(0.5, 0.5, 0.5))
	_district_block(Rect2(156, -200, 38, 44), "", Color(0.5, 0.5, 0.5))
	_district_block(Rect2(106, -144, 38, 40), "highrise", Color(0.5, 0.5, 0.5))
	# Trust Plaza: a paved square with a fountain-less water feature and trees.
	_block(Rect2(156, -144, 38, 40), Color(0.6, 0.58, 0.54), "tiles")
	plazas.append(_rect_poly(Rect2(156, -144, 38, 40)))
	_cylinder(Vector3(175, 0.5, -124), 3.6, 0.7, Color(0.7, 0.68, 0.62), 14)
	_cylinder(Vector3(175, 0.86, -124), 3.2, 0.06, Color.WHITE, 14, _material(Color(0.2, 0.4, 0.46), 0.1, "water"))
	_cylinder(Vector3(175, 1.8, -124), 0.35, 2.0, Color(0.7, 0.68, 0.62), 8)
	for at: Vector2 in [Vector2(162, -138), Vector2(188, -138), Vector2(162, -110), Vector2(188, -110)]:
		_tree(Vector3(at.x, 0.16, at.y))
	for at: Vector2 in [Vector2(167, -138), Vector2(183, -138), Vector2(167, -110), Vector2(183, -110)]:
		_bench(Vector3(at.x, 0.16, at.y), 0.0 if at.y < -124.0 else PI)
	_landmark("TRUST PLAZA", Vector3(175, 0, -124))
	_landmark("UPTOWN", Vector3(150, 0, -172))

## Motor Mile: the car-dealer strip along Union Street east of Midtown (the motel, the parking
## garage and the burger joint are the plots), with pole signs and a used-car lot.
func _build_motor_mile() -> void:
	_begin("MotorMile")
	_street_palette = [Color(0.85, 0.25, 0.2), Color(0.95, 0.75, 0.2), Color(0.2, 0.5, 0.75), Color(0.3, 0.6, 0.3)]
	_district_block(Rect2(150, -9, 71, 38), "", Color(0.44, 0.44, 0.43))
	_district_block(Rect2(100, 41, 40, 48), "", Color(0.44, 0.44, 0.43))
	# The used-car lot behind the burger joint and pole signs along Union Street.
	_parking_row(Vector3(104, 0.16, 76), 11, Vector3.RIGHT, [Color(0.7, 0.1, 0.12), Color(0.15, 0.3, 0.55), Color(0.85, 0.82, 0.7), Color(0.12, 0.12, 0.13)], 3)
	_pylon(Vector3(146, 0.16, 27), "MOTOR MILE", Color(1.0, 0.75, 0.25), PI, 10.0)
	_pylon(Vector3(97, 0.16, 43), "EATS", Color(1.0, 0.4, 0.3), 0.0, 8.0)
	_landmark("MOTOR MILE", Vector3(146, 0, 40))

## Nightlife: a grid of casinos, arcades and neon-fronted clubs between the old Strip site and
## the Strip proper; the NIGHT CLUB and STRIP CLUB plots are its two southern blocks.
func _build_nightlife() -> void:
	_begin("Nightlife")
	_street_palette = [Color(1.0, 0.3, 0.8), Color(0.3, 0.9, 1.0), Color(1.0, 0.85, 0.3), Color(0.5, 1.0, 0.4)]
	var xs: Array[float] = [26.0, 78.0, 130.0]
	var zs: Array[Vector2] = [Vector2(104, 44), Vector2(160, 46), Vector2(218, 52)]
	for row: int in range(zs.size()):
		for column: int in range(xs.size()):
			var rect: Rect2 = Rect2(xs[column], zs[row].x, 40, zs[row].y)
			if row == 2 and column >= 0:
				# The two southern-east blocks are the night club and strip club plots; the west one is a car park.
				_district_block(rect, "", Color(0.3, 0.3, 0.32) if column == 0 else Color(0.36, 0.35, 0.38))
			elif row == 0 and column == 2:
				_pocket_park(rect)
			elif row == 1 and column == 1:
				_district_block(rect, "neon", Color(0.36, 0.35, 0.38))
			else:
				_district_block(rect, "neon" if (row + column) % 2 == 0 else "midrise", Color(0.36, 0.35, 0.38))
	_parking_row(Vector3(30, 0.16, 251), 10, Vector3.RIGHT, [Color(0.9, 0.2, 0.5), Color(0.15, 0.15, 0.2), Color(0.85, 0.85, 0.9), Color(0.2, 0.5, 0.7)], 2)
	_pylon(Vector3(64.5, 0.16, 204.3), "NIGHTLIFE", Color(1.0, 0.3, 0.8), 0.0, 11.0)
	_landmark("NIGHTLIFE", Vector3(100, 0, 154))

## West End: rowhouses, lofts and corner shops where Lantern Row used to stand, between the
## canal market and Midtown's west ring.
func _build_west_end() -> void:
	_begin("WestEnd")
	_street_palette = [Color(0.55, 0.3, 0.25), Color(0.3, 0.4, 0.5), Color(0.8, 0.7, 0.4), Color(0.35, 0.5, 0.35)]
	var columns: Array[Vector2] = [Vector2(-206, 50), Vector2(-144, 44)]
	var rows: Array[Vector2] = [Vector2(-94, 38), Vector2(-44, 40)]
	for row: int in range(rows.size()):
		for column: int in range(columns.size()):
			var rect: Rect2 = Rect2(columns[column].x, rows[row].x, columns[column].y, rows[row].y)
			if row == 1 and column == 0:
				_pocket_park(rect)
			else:
				_district_block(rect, "brick" if (row + column) % 2 == 0 else "flats", Color(0.4, 0.39, 0.38))
	_landmark("WEST END", Vector3(-150, 0, -50))

## Old Town: brick tenements and shopfronts north of Morris Park.
func _build_old_town() -> void:
	_begin("OldTown")
	_street_palette = [Color(0.72, 0.15, 0.2), Color(0.16, 0.36, 0.24), Color(0.9, 0.82, 0.62), Color(0.2, 0.3, 0.55)]
	var columns: Array[Vector2] = [Vector2(-144, 38), Vector2(-94, 38), Vector2(-44, 37)]
	var rows: Array[Vector2] = [Vector2(100, 44), Vector2(156, 22)]
	for row: int in range(rows.size()):
		for column: int in range(columns.size()):
			var rect: Rect2 = Rect2(columns[column].x, rows[row].x, columns[column].y, rows[row].y)
			if row == 1 and column == 2:
				_pocket_park(rect)
			else:
				_district_block(rect, "brick", Color(0.42, 0.4, 0.38))
	_landmark("OLD TOWN", Vector3(-100, 0, 120))

## Slip Side: boatyards, chandlers and warehouses along the south bank of the West Slip.
func _build_slip_side() -> void:
	_begin("SlipSide")
	_street_palette = [Color(0.3, 0.5, 0.6), Color(0.7, 0.6, 0.3), Color(0.5, 0.5, 0.5), Color(0.6, 0.3, 0.25)]
	var columns: Array[Vector2] = [Vector2(-386, 50), Vector2(-324, 46), Vector2(-272, 42), Vector2(-224, 30)]
	for column: Vector2 in columns:
		_district_block(Rect2(column.x, 68, column.y, 60), "warehouse", Color(0.44, 0.44, 0.42))
	# Boats hauled out on the quay.
	for index: int in range(5):
		var at: Vector3 = Vector3(-380 + index * 34, 0.16, 54.5)
		_box(at + Vector3(0, 0.6, 0), Vector3(7.0, 1.2, 2.6), Color(0.9, 0.9, 0.88), true, "panel")
		_box(at + Vector3(-0.6, 1.5, 0), Vector3(2.6, 0.8, 1.8), Color(0.2, 0.34, 0.45))
	_landmark("SLIP SIDE", Vector3(-290, 0, 62))

## The Old Wharf (north-west): a working shipyard and cannery west of the Canal Market.
func _build_old_wharf() -> void:
	_begin("OldWharf")
	_street_palette = [Color(0.85, 0.5, 0.15), Color(0.2, 0.45, 0.7), Color(0.6, 0.6, 0.6), Color(0.75, 0.2, 0.15)]
	_district_block(Rect2(-380, -236, 54, 35), "warehouse", Color(0.46, 0.46, 0.44))
	_district_block(Rect2(-314, -236, 64, 35), "warehouse", Color(0.46, 0.46, 0.44))
	_district_block(Rect2(-380, -189, 54, 37), "", Color(0.46, 0.46, 0.44))
	_district_block(Rect2(-314, -189, 64, 37), "", Color(0.46, 0.46, 0.44))
	var colors: Array[Color] = [Color(0.62, 0.22, 0.16), Color(0.18, 0.36, 0.56), Color(0.24, 0.5, 0.36), Color(0.78, 0.6, 0.18), Color(0.3, 0.52, 0.55)]
	for row: int in range(3):
		for column: int in range(6):
			if (row + column) % 5 == 4:
				continue
			for level: int in range(1 + (row + column) % 3):
				_container(Vector3(-374 + column * 8.2, level * 2.7, -184 + row * 3.2 * 1.0), colors[(row * 2 + column + level) % colors.size()], false)
	# The yard fence ends at the kerb of the wharf spine (x -326) and of Wharf North (z -189), not across them.
	_fence(Vector3(-382, 0.16, -156), Vector3(-327, 0.16, -156))
	_fence(Vector3(-327, 0.16, -156), Vector3(-327, 0.16, -188.5))
	for at: Vector3 in [Vector3(-360, 0, -170), Vector3(-296, 0, -170), Vector3(-296, 0, -215)]:
		_box(at + Vector3(0, 8, 0), Vector3(0.5, 16, 0.5), Color(0.3, 0.3, 0.32), true)
		_box_with(at + Vector3(0, 16.3, 0), Vector3(2.2, 0.8, 0.5), _glow(Color(1.0, 0.85, 0.6), 2.4))
	_pylon(Vector3(-327.6, 0.16, -203.6), "OLD WHARF", Color(0.6, 0.9, 1.0), PI * 0.5, 9.0)
	_landmark("OLD WHARF", Vector3(-320, 0, -200))

## South Docks: quays, container stacks and cold stores between Kingsway and the Strip.
func _build_south_docks() -> void:
	_begin("SouthDocks")
	_street_palette = [Color(0.85, 0.5, 0.15), Color(0.2, 0.45, 0.7), Color(0.6, 0.6, 0.6), Color(0.75, 0.2, 0.15)]
	_district_block(Rect2(246, 306, 48, 62), "warehouse", Color(0.46, 0.46, 0.44))
	_district_block(Rect2(306, 306, 72, 62), "", Color(0.46, 0.46, 0.44))
	_district_block(Rect2(246, 262, 48, 32), "warehouse", Color(0.46, 0.46, 0.44))
	_district_block(Rect2(306, 262, 72, 32), "", Color(0.46, 0.46, 0.44))
	var colors: Array[Color] = [Color(0.62, 0.22, 0.16), Color(0.18, 0.36, 0.56), Color(0.24, 0.5, 0.36), Color(0.78, 0.6, 0.18), Color(0.5, 0.5, 0.5)]
	for stack: Vector2 in [Vector2(312, 270), Vector2(326, 270), Vector2(340, 270), Vector2(354, 270), Vector2(312, 282), Vector2(326, 282), Vector2(340, 282), Vector2(312, 314), Vector2(326, 314), Vector2(340, 314), Vector2(354, 314), Vector2(312, 326), Vector2(340, 326), Vector2(354, 326)]:
		for level: int in range(1 + int(absf(stack.x + stack.y)) % 3):
			_container(Vector3(stack.x, level * 2.7, stack.y), colors[(int(stack.x) / 7 + level) % colors.size()], false)
	for crane_z: float in [340.0]:
		for side: float in [-1.0, 1.0]:
			for leg_x: float in [344.0, 353.0]:
				_box(Vector3(leg_x, 13, crane_z + side * 7), Vector3(1.2, 26, 1.2), Color(0.85, 0.55, 0.15), true)
		_box(Vector3(348.5, 26.5, crane_z), Vector3(36, 1.6, 16), Color(0.85, 0.55, 0.15))
		_box_with(Vector3(366, 27.6, crane_z), Vector3(0.6, 0.6, 0.6), _glow(Color(1.0, 0.2, 0.15), 3.0))
	_landmark("SOUTH DOCKS", Vector3(300, 0, 300))

## The north bluff and the east shore: parkland, a ball field and long lawns (the gun club sits
## on its own spur road, see scripts/buildings/gunstore.gd).
func _build_east_shore() -> void:
	_begin("EastShore")
	_street_palette = [Color(0.3, 0.55, 0.3), Color(0.8, 0.7, 0.4), Color(0.4, 0.5, 0.7), Color(0.7, 0.3, 0.25)]
	# Sunset Park: a wide lawn south of the gun club, with a ball diamond.
	var park: Rect2 = Rect2(236, 22, 96, 76)
	plazas.append(_rect_poly(park))
	_box(Vector3(park.get_center().x, 0.02, park.get_center().y), Vector3(park.size.x, 0.03, park.size.y), Color(0.3, 0.42, 0.27), false, "grass")
	_box(Vector3(284, 0.05, 62), Vector3(22, 0.02, 22), Color(0.6, 0.45, 0.3), false, "planks").rotation.y = PI * 0.25
	for corner: Vector2 in [Vector2(0, 0), Vector2(10, -10), Vector2(-10, -10), Vector2(0, -20)]:
		_box(Vector3(284 + corner.x, 0.1, 72 + corner.y), Vector3(0.6, 0.12, 0.6), Color(0.95, 0.95, 0.9))
	for index: int in range(10):
		var angle: float = 0.6 + index * 0.25
		_fence(Vector3(284 + cos(angle) * 30.0, 0.16, 72 - sin(angle) * 34.0 + 6.0), Vector3(284 + cos(angle + 0.25) * 30.0, 0.16, 72 - sin(angle + 0.25) * 34.0 + 6.0), 2.4)
	for at: Vector2 in [Vector2(244, 27), Vector2(252, 90), Vector2(324, 27), Vector2(324, 90), Vector2(264, 28), Vector2(304, 92)]:
		_tree(Vector3(at.x, 0.0, at.y))
	_bench(Vector3(262, 0.0, 60), PI * 0.5)
	_bench(Vector3(306, 0.0, 58), -PI * 0.5)
	_landmark("SUNSET PARK", Vector3(284, 0, 60))
	# Palms along the coast road and the bluff.
	for z: int in range(-96, 120, 24):
		_tree(Vector3(352.0, 0.0, float(z)), "palm")
	for x: int in range(250, 400, 30):
		_tree(Vector3(float(x), 0.0, -256.0 + absf(float(x) - 330.0) * 0.1), "palm")

func _rect_poly(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])

## District outlines for the map and the radar, in world space. Midtown is first so it
## wins where a neighbourhood's margin touches the downtown ring.
func _define_districts() -> void:
	_district("MIDTOWN", Rect2(-94, -94, 188, 188), Color(0.8, 0.78, 0.7), "")
	_district_polys("LANTERN ROW", [_kit_poly("lantern", 6.0)], Factions.color("kojimoto"), "kojimoto")
	_district_polys("SOLANA HEIGHTS", [_kit_poly("solana", 6.0)], Factions.color("solnegro"), "solnegro")
	_district_polys("KINGSWAY", [_kit_poly("kingsway", 6.0)], Factions.color("kingsway"), "kingsway")
	_district_polys("MORRIS PARK", [_kit_poly("morris", 6.0)], Factions.color("morris"), "morris")
	_district("THE HARBOR", Rect2(-82, -200, 185, 106), Color(0.55, 0.62, 0.7), "")
	_district("CANAL MARKET", Rect2(-241, -229, 147, 123), Color(0.6, 0.7, 0.62), "")
	_district_polys("UNION STATION", [_kit_poly("station", 6.0)], Color(0.7, 0.66, 0.6), "")
	_district_polys("THE STRIP", [_kit_poly("strip", 6.0), BEACH], Color(0.9, 0.5, 0.75), "")
	_district("EASTGATE", Rect2(94, -94, 147, 73), Color(0.62, 0.72, 0.6), "")
	_district("WEST BANK", Rect2(-241, 6, 147, 46), Color(0.66, 0.66, 0.74), "")
	# 0.6: the new ring of land (Midtown's neighbours first, then the outer districts).
	_district("UPTOWN", Rect2(94, -212, 112, 116), Color(0.62, 0.66, 0.8), "")
	_district("MOTOR MILE", Rect2(94, -17, 133, 114), Color(0.85, 0.7, 0.45), "")
	_district("NIGHTLIFE", Rect2(14, 98, 168, 180), Color(0.85, 0.4, 0.8), "")
	_district("WEST END", Rect2(-241, -106, 153, 115), Color(0.68, 0.6, 0.55), "")
	_district("OLD TOWN", Rect2(-157, 82, 143, 108), Color(0.75, 0.55, 0.5), "")
	_district("SLIP SIDE", Rect2(-398, 52, 206, 92), Color(0.6, 0.66, 0.7), "")
	_district("OLD WHARF", Rect2(-404, -252, 160, 112), Color(0.58, 0.62, 0.64), "")
	_district("EAST SHORE", Rect2(233, -110, 177, 238), Color(0.55, 0.7, 0.55), "")
	_district("SOUTH DOCKS", Rect2(190, 255, 220, 145), Color(0.6, 0.64, 0.68), "")
	_district("NORTH BLUFF", Rect2(228, -290, 180, 58), Color(0.7, 0.68, 0.5), "")

func _district_polys(title: String, polys: Array, color: Color, crew: String) -> void:
	var first: PackedVector2Array = polys[0]
	var bounds: Rect2 = Rect2(first[0], Vector2.ZERO)
	for poly: PackedVector2Array in polys:
		for point: Vector2 in poly:
			bounds = bounds.expand(point)
	_district(title, bounds, color, crew, polys)

## The Strip (E): the neutral nightlife hub. Club Halcyon, the diner, the motel and the bowl.
func _build_strip() -> void:
	_place("strip", "TheStrip")
	_street_palette = [Color(1.0, 0.3, 0.8), Color(0.3, 0.9, 1.0), Color(1.0, 0.85, 0.3), Color(0.5, 1.0, 0.4)]
	var magenta: Color = Color(1.0, 0.3, 0.8)
	var cyan: Color = Color(0.3, 0.9, 1.0)
	for rect: Rect2 in [Rect2(94, -82, 50, 26), Rect2(156, -82, 44, 26), Rect2(94, -44, 50, 23), Rect2(156, -44, 44, 23), Rect2(94, -9, 50, 38), Rect2(156, -9, 44, 38), Rect2(94, 41, 50, 41), Rect2(156, 41, 44, 41)]:
		_block(rect, Color(0.42, 0.41, 0.42), "tiles")
	# Club Halcyon.
	_tower(Vector2(121, 10), Vector3(40, 12, 30), Color(0.12, 0.1, 0.14), "panel", Vector3.LEFT, "", Color.WHITE, Color(0.08, 0.08, 0.1), 0.0)
	_box_with(Vector3(121, 11.4, 10), Vector3(40.6, 0.4, 30.6), _glow(magenta, 2.2))
	_box_with(Vector3(121, 10.6, 10), Vector3(40.6, 0.2, 30.6), _glow(cyan, 2.0))
	_neon("CLUB  HALCYON", Vector3(100.6, 7.5, 10), -PI * 0.5, magenta, 96, true)
	_box(Vector3(99, 3.4, 10), Vector3(3.5, 0.25, 10), Color(0.1, 0.1, 0.12))
	for z: float in [6.0, 8.0, 12.0, 14.0]:
		_cylinder(Vector3(98.2, 0.66, z), 0.06, 1.0, Color(0.85, 0.7, 0.3))
	_landmark("CLUB HALCYON", Vector3(98, 0, 10))
	# Nite Owl Diner.
	_tower(Vector2(114, -32.5), Vector3(24, 5, 11), Color(0.78, 0.8, 0.82), "metal", Vector3.LEFT, "", Color.WHITE, Color(0.6, 0.15, 0.15), 0.9)
	_neon("NITE OWL DINER", Vector3(101.6, 6.8, -32.5), -PI * 0.5, Color(1.0, 0.45, 0.3), 70, true)
	_landmark("NITE OWL DINER", Vector3(100, 0, -32))
	# Cosmo Bowl with a giant pin.
	_tower(Vector2(119, -69), Vector3(38, 8, 20), Color(0.3, 0.3, 0.5), "panel", Vector3.LEFT, "COSMO BOWL", cyan, Color(0.2, 0.2, 0.3), 0.3)
	_cylinder(Vector3(126, 11, -69), 1.1, 5.5, Color(0.95, 0.95, 0.95), 10)
	_cylinder(Vector3(126, 14.5, -69), 0.7, 1.6, Color(0.95, 0.95, 0.95), 10)
	_cylinder(Vector3(126, 12.9, -69), 1.14, 0.35, Color(0.9, 0.15, 0.15), 10)
	_landmark("COSMO BOWL", Vector3(100, 0, -69))
	# Starlite Motel: an L of rooms around a pool and a tall star sign.
	_tower(Vector2(178, 72), Vector3(36, 7, 10), Color(0.92, 0.84, 0.66), "stucco", Vector3.FORWARD, "", Color.WHITE, Color(0.25, 0.4, 0.45), 0.6)
	_tower(Vector2(193, 56), Vector3(10, 7, 22), Color(0.92, 0.84, 0.66), "stucco", Vector3.LEFT, "", Color.WHITE, Color(0.25, 0.4, 0.45), 0.6)
	_box(Vector3(172, 3.55, 66.3), Vector3(36, 0.2, 2.6), Color(0.4, 0.42, 0.44))
	_box(Vector3(172, 4.5, 65.1), Vector3(36, 0.9, 0.08), Color(0.25, 0.27, 0.28))
	_box(Vector3(174, 0.2, 54), Vector3(12, 0.1, 7), Color(0.2, 0.55, 0.7), false, "water")
	_box(Vector3(160, 6, 50), Vector3(0.5, 12, 0.5), Color(0.3, 0.3, 0.32), true)
	_neon("STARLITE\nMOTEL", Vector3(160, 11.5, 49.6), PI, Color(1.0, 0.85, 0.3), 80, true)
	_landmark("STARLITE MOTEL", Vector3(172, 0, 58))
	# Arcade, parking and billboards.
	_tower(Vector2(178, -32.5), Vector3(18, 6, 12), Color(0.2, 0.18, 0.3), "panel", Vector3.LEFT, "LUCKY 8 ARCADE", Color(0.5, 1.0, 0.4), Color(0.15, 0.15, 0.2), 0.7)
	for index: int in range(6):
		_box(Vector3(100 + index * 5, 0.18, 62), Vector3(0.1, 0.02, 6), Color(0.85, 0.82, 0.6))
	_car_prop(Vector3(112, 0.16, 62), 0.0, Color(0.7, 0.1, 0.35))
	_car_prop(Vector3(122, 0.16, 70), 0.1, Color(0.2, 0.25, 0.3))
	_box(Vector3(178, 9, -69), Vector3(0.4, 18, 0.4), Color(0.3, 0.3, 0.32), true)
	_box(Vector3(178, 18.5, -69), Vector3(0.3, 4, 12), Color(0.12, 0.12, 0.15))
	_neon("HALCYON COLA", Vector3(177.7, 18.5, -69), -PI * 0.5, Color(0.95, 0.25, 0.3), 90)
	_build_beach()

## Halcyon Beach: sand, palms and umbrellas between Ocean Drive and the sea, lifeguard
## towers, and Halcyon Pier with its Ferris wheel. An open, long-sightline neutral zone.
func _build_beach() -> void:
	var cream: Color = Color(0.95, 0.9, 0.8)
	for index: int in range(14):
		var t: float = float(index) / 13.0
		var z: float = lerpf(-66.0, 66.0, t)
		var road_x: float = 212.0 + cos((z / 70.0) * PI * 0.5) * 12.0
		_tree(Vector3(road_x - 8.0, 0.0, z), "palm")
	var stripes: Array[Color] = [Color(0.95, 0.3, 0.3), Color(0.2, 0.6, 0.9), Color(1.0, 0.85, 0.2), Color(0.3, 0.8, 0.5)]
	for index: int in range(10):
		var z: float = -54.0 + index * 12.0
		var x: float = 232.0 - absf(z) * 0.1
		_cylinder(Vector3(x, 1.2, z), 0.05, 2.4, Color(0.9, 0.9, 0.9), 6)
		_cylinder(Vector3(x, 2.45, z), 1.5, 0.12, Color.WHITE, 8, _material(stripes[index % stripes.size()], 0.8))
		_box(Vector3(x + 1.6, 0.1, z), Vector3(1.8, 0.08, 0.9), stripes[(index + 1) % stripes.size()])
	for z: float in [-40.0, 30.0]:
		var x: float = 236.0 - absf(z) * 0.08
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			_box(Vector3(x + corner.x * 1.1, 1.5, z + corner.y * 1.1), Vector3(0.15, 3.0, 0.15), cream)
		_box(Vector3(x, 3.1, z), Vector3(2.8, 0.2, 2.8), cream, true, "planks")
		_box(Vector3(x, 4.2, z), Vector3(2.6, 2.0, 2.6), Color(0.9, 0.25, 0.2), false, "planks")
	_landmark("HALCYON BEACH", Vector3(232, 0, -20))
	# Halcyon Pier: a boardwalk out to sea and a Ferris wheel lit up at dusk.
	_box(Vector3(260, 0.06, 0), Vector3(48, 0.12, 8), Color(0.55, 0.4, 0.26), false, "planks")
	for x: int in range(238, 284, 6):
		for side: float in [-1.0, 1.0]:
			_cylinder(Vector3(x, -1.0, side * 3.6), 0.25, 2.4, Color(0.3, 0.24, 0.18), 6)
	var hub: Vector3 = Vector3(274, 16.0, 0)
	var wheel: MeshInstance3D = _mesh_at(MeshKit.torus(13.2, 14.0, 40, 6), hub, _glow(Color(1.0, 0.45, 0.8), 1.8))
	wheel.rotation.x = PI * 0.5
	wheel.rotation.y = PI * 0.5
	for spoke: int in range(12):
		var angle: float = spoke * TAU / 12.0
		var spoke_box: MeshInstance3D = _box_with(hub + Vector3(0, sin(angle) * 6.8, cos(angle) * 6.8), Vector3(0.2, 13.6, 0.2), _material(Color(0.85, 0.85, 0.9), 0.4))
		spoke_box.rotation.x = PI * 0.5 - angle
		var car_at: Vector3 = hub + Vector3(0, sin(angle) * 13.6 - 1.2, cos(angle) * 13.6)
		_box_with(car_at, Vector3(1.6, 1.4, 1.6), _material(stripes[spoke % stripes.size()], 0.6))
	for side: float in [-1.0, 1.0]:
		var leg: MeshInstance3D = _box_with(Vector3(274, 8.0, side * 4.0), Vector3(0.6, 17.0, 0.6), _material(Color(0.85, 0.85, 0.9), 0.4))
		leg.rotation.x = side * 0.28
	_neon("HALCYON PIER", Vector3(240, 4.2, 4.3), 0.0, Color(0.3, 0.9, 1.0), 70, true)
	_landmark("HALCYON PIER", Vector3(262, 0, 0))
