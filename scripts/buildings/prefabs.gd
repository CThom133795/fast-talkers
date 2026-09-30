class_name BuildingPrefabs
extends RefCounted
## BuildingPrefabs: reusable, parametric, seeded, ENTERABLE buildings for the city fill (Map 0.8).
##
## One call builds a whole building: `BuildingPrefabs.build(world, kind, center, size, yaw, floors, seed, style)`.
## The building is authored in a BuildingKit frame (local +Z = the street front, +X along the facade), and the
## kit's node is turned so that the front faces `Basis(UP, yaw) * Vector3.FORWARD`: yaw 0 puts the front on
## world -Z, PI puts it on +Z (`front_yaw()` converts from a facing direction). Exteriors are merged per
## building (one draw per material) with real breakable glass only on the shopfront; interiors sit on the
## interior render layer (visible within INTERIOR_RANGE), furniture that is not cover is collision-free and
## merged, and every building keeps at most two interior lamps.
##
## Kinds (all enterable): corner_store, row_shop, walkup, warehouse, office, bar, auto_shop, church_hall,
## diner_small. `min_size()` and `max_floors()` describe what each can be; `build()` clamps to them.
## Every building publishes meta: "enterable" (true), "kind", "floors", "size" (the clamped footprint),
## "floor_ys" (walking-surface heights, local), "doors" (door records), "stairs" (flight records with local
## bottom/top points), "routes" (walk polylines in the kit's local frame, like the trademark buildings),
## "roof_y", "front_yaw" and "sign".

const Kit = preload("res://scripts/buildings/building_kit.gd")

const KIND_LIST: PackedStringArray = ["corner_store", "row_shop", "walkup", "warehouse", "office", "bar", "auto_shop", "church_hall", "diner_small"]
## Storey height, floor slab, exterior wall, partition and parapet thickness/height (metres).
const FH: float = 3.4
const SLAB: float = 0.3
const WALL_T: float = 0.3
const PART_T: float = 0.16
const PARAPET: float = 1.0
## Interior meshes are drawn within this range (the kit uses 45; prefabs are placed many times).
const INTERIOR_RANGE: float = 26.0
## Collision-free furnishings are drawn within this range.
const PROP_RANGE: float = 20.0
const DOOR_H: float = 2.6

const WALLS: Array = [
	{"c": Color(0.55, 0.27, 0.21), "t": "brick"}, {"c": Color(0.46, 0.3, 0.24), "t": "brick"}, {"c": Color(0.64, 0.44, 0.31), "t": "brick"},
	{"c": Color(0.5, 0.25, 0.2), "t": "brick"}, {"c": Color(0.74, 0.68, 0.53), "t": "stucco"}, {"c": Color(0.56, 0.63, 0.56), "t": "stucco"},
	{"c": Color(0.76, 0.6, 0.55), "t": "stucco"}, {"c": Color(0.52, 0.55, 0.58), "t": "panel"}, {"c": Color(0.64, 0.6, 0.5), "t": "brick"},
]
const TRIMS: Array[Color] = [Color(0.86, 0.82, 0.7), Color(0.9, 0.9, 0.86), Color(0.28, 0.36, 0.3), Color(0.32, 0.32, 0.36), Color(0.78, 0.7, 0.5)]
const ACCENTS: Array[Color] = [Color(0.16, 0.36, 0.3), Color(0.5, 0.14, 0.12), Color(0.14, 0.24, 0.42), Color(0.7, 0.5, 0.14), Color(0.3, 0.2, 0.35), Color(0.12, 0.38, 0.4)]
const SIGNS: Dictionary = {
	"corner_store": ["LUCKY SEVEN DELI", "ORCHARD PHARMACY", "MERCADO LOPEZ", "BLUE MOON LIQUORS", "HARBOR PAWN & LOAN", "TWO BROTHERS MARKET"],
	"row_shop": ["FRANKIE'S BARBERS", "ALTERATIONS  TAILOR", "PARK TV REPAIR", "GROOVE RECORDS", "SUDS N DUDS LAUNDRY", "CORNER CLEANERS"],
	"walkup": ["THE MARLOWE", "ELM COURT", "BELLA VISTA APTS", "PINE ARMS", "THE CARLTON HOUSE", "ROSEDALE MANOR"],
	"warehouse": ["KESSLER FREIGHT", "DOCKSIDE SUPPLY", "TRI COUNTY WHOLESALE", "MERCER CARTAGE", "NORTHSIDE STORAGE"],
	"office": ["OAKLEY & FINCH LAW", "BAYVIEW INSURANCE", "ROSSI TITLE CO", "HARLAN FREIGHT AGENCY"],
	"bar": ["THE RUSTY ANCHOR", "SIDE POCKET LOUNGE", "O'MALLEY'S", "CLUB EIGHT BALL", "THE LAST DROP"],
	"auto_shop": ["VINNY'S AUTO REPAIR", "PIT STOP GARAGE", "DELTA TIRE & LUBE", "MAPLE BRAKE & MUFFLER"],
	"church_hall": ["GRACE COMMUNITY HALL", "OUR LADY OF THE HARBOR", "ST BRIDGET PARISH HALL"],
	"diner_small": ["MABEL'S DINER", "SUNRISE COFFEE SHOP", "THE BLUE PLATE"],
}


static func kinds() -> PackedStringArray:
	return KIND_LIST


## Smallest footprint in metres for a kind: x = frontage width, y = depth.
static func min_size(kind: String) -> Vector2:
	match kind:
		"corner_store":
			return Vector2(10, 12)
		"row_shop":
			return Vector2(6.5, 14)
		"walkup":
			return Vector2(16, 14)
		"warehouse":
			return Vector2(16, 20)
		"office":
			return Vector2(16, 16)
		"bar":
			return Vector2(12, 14)
		"auto_shop":
			return Vector2(14, 16)
		"church_hall":
			return Vector2(10, 16)
		"diner_small":
			return Vector2(10, 10)
	return Vector2(10, 10)


## Tallest storey count a kind supports (the ground floor counts). walkup and office need at least 2.
static func max_floors(kind: String) -> int:
	match kind:
		"corner_store":
			return 2
		"row_shop":
			return 2
		"walkup":
			return 4
		"office":
			return 4
		"warehouse":
			return 2
	return 1


const MORE_KINDS: Array[String] = ["cooler", "case", "cubicle", "conf", "pool", "booth", "stove", "tires", "drum", "workbench", "lectern", "safe"]


static func min_floors(kind: String) -> int:
	return 2 if kind == "walkup" or kind == "office" else 1


## The yaw that makes a building's front face the world direction `front` (flat).
static func front_yaw(front: Vector3) -> float:
	# The front is local -Z (FORWARD), so Basis(UP, yaw) * FORWARD = front.
	return atan2(-front.x, -front.z)


## Builds one enterable building. `center` is the world x/z of the footprint centre; `size` is the frontage
## and depth in metres (raised to min_size); `yaw` turns it, local -Z (FORWARD) being the street front;
## `floors` counts the storeys including the ground (clamped to min_floors..max_floors); `seed` drives all
## variety. Registers the footprint (world.footprints), doors (world.interactable_doors) and shopfront
## glass (world.glass_panes) like the kit does and returns the building's root Node3D, with meta
## "enterable" = true, "kind" = kind and "floors" = floors (see the header for the rest).
## `style` may carry "palette" (Array of Colour: wall, trim, accent), "sign" (String), "tex" (String),
## "lit" (float, share of lit windows) and "district" (String).
static func build(world: Node3D, kind: String, center: Vector2, size: Vector2, yaw: float, floors: int, seed: int, style: Dictionary = {}) -> Node3D:
	if not KIND_LIST.has(kind):
		push_error("BuildingPrefabs.build: unknown kind '%s'" % kind)
		return null
	var least: Vector2 = min_size(kind)
	var clamped: Vector2 = Vector2(maxf(size.x, least.x), maxf(size.y, least.y))
	var storeys: int = clampi(floors, min_floors(kind), max_floors(kind))
	var saved_target: Node3D = world._target
	var saved_xf: Transform3D = world._xf
	var saved_yaw: float = world._xf_yaw
	var c: Ctx = Ctx.new(world, kind, center, clamped, yaw, storeys, seed, style)
	match kind:
		"walkup", "office":
			_walkup(c)
		"corner_store":
			_row_shop(c)
		"bar":
			_bar(c)
		"auto_shop":
			_auto_shop(c)
		"diner_small":
			_diner_small(c)
		"church_hall":
			_church_hall(c)
		"row_shop":
			_row_shop(c)
		"warehouse":
			_warehouse(c)
		_:
			push_error("BuildingPrefabs.build: '%s' is not built yet" % kind)
	c.finish()
	world._target = saved_target
	world._xf = saved_xf
	world._xf_yaw = saved_yaw
	return c.kit.node


# --- The build context -----------------------------------------------------------------------------

## Everything a kind builder needs: the kit, a seeded rng, palette materials, storey heights, placement
## claims (so furniture never blocks a doorway or a stair) and the records published as meta.
class Ctx extends RefCounted:
	var world: Node3D
	var kit: Kit
	var kind: String
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var style: Dictionary
	var W: float
	var D: float
	var hx: float
	var hz: float
	var floors: int
	var f0: float
	var roof_y: float
	var lit: float = 0.25
	var sign_text: String = ""
	var sign_index: int = -1
	var wall_col: Color
	var trim_col: Color
	var accent_col: Color
	var wall_tex: String
	var m_wall: StandardMaterial3D
	var m_trim: StandardMaterial3D
	var m_roof: StandardMaterial3D
	var m_accent: StandardMaterial3D
	var m_dark: StandardMaterial3D
	var m_floor: StandardMaterial3D
	var m_part: StandardMaterial3D
	var m_metal: StandardMaterial3D
	var m_pane_in: StandardMaterial3D
	var m_ceil: StandardMaterial3D
	var m_pale: StandardMaterial3D
	var m_wood: StandardMaterial3D
	var m_fabric: StandardMaterial3D
	var m_ac: StandardMaterial3D
	var m_glass_in: Material
	var doors: Array = []
	var stairs: Array = []
	var routes: Dictionary = {}
	var zones: Dictionary = {}
	var props: Array = []
	var lamps: int = 0
	var blinds: bool = false
	var extra_floors: Array[float] = []

	func _init(w: Node3D, kind_name: String, center: Vector2, sz: Vector2, yaw: float, storeys: int, seed_value: int, style_in: Dictionary) -> void:
		world = w
		kind = kind_name
		style = style_in
		W = sz.x
		D = sz.y
		hx = W * 0.5
		hz = D * 0.5
		floors = storeys
		rng.seed = seed_value * 7919 + kind_name.hash()
		var ground: float = world.surface_height(center)
		f0 = maxf(ground, 0.16) + 0.01
		roof_y = f0 + storeys * FH
		lit = float(style.get("lit", 0.25))
		var picks: Array = SIGNS.get(kind_name, ["MAIN STREET"])
		var pick: int = rng.randi() % picks.size()
		sign_index = pick if not style.has("sign") else -1
		sign_text = str(style.get("sign", picks[pick]))
		var wall_pick: Dictionary = WALLS[rng.randi() % WALLS.size()]
		wall_col = wall_pick["c"]
		wall_tex = str(wall_pick["t"])
		trim_col = TRIMS[rng.randi() % TRIMS.size()]
		accent_col = ACCENTS[rng.randi() % ACCENTS.size()]
		var palette: Array = style.get("palette", [])
		if palette.size() >= 1:
			wall_col = palette[0]
		if palette.size() >= 2:
			trim_col = palette[1]
		if palette.size() >= 3:
			accent_col = palette[2]
		if style.has("tex"):
			wall_tex = str(style["tex"])
		var plot: Dictionary = {"center": center, "size": sz, "yaw": yaw + PI, "district": str(style.get("district", ""))}
		kit = Kit.new(world, kind_name.capitalize().replace("_", ""), plot)
		m_wall = kit.mat(wall_col, wall_tex, 0.9)
		m_trim = kit.mat(trim_col, "", 0.8)
		m_roof = kit.mat(Color(0.2, 0.21, 0.22), "roof", 0.9)
		m_accent = kit.mat(accent_col, "", 0.7)
		m_dark = kit.mat(Color(0.16, 0.24, 0.29), "", 0.3)
		m_floor = kit.mat(Color(0.66, 0.6, 0.5), "tiles", 0.9)
		m_part = kit.mat(Color(0.82, 0.78, 0.68).lerp(accent_col, 0.08), "stucco", 0.95)
		m_metal = kit.mat(Color(0.22, 0.23, 0.24), "metal", 0.5)
		m_pane_in = kit.mat(Color(0.72, 0.82, 0.92), "", 0.3)
		m_ceil = kit.mat(Color(0.86, 0.83, 0.76), "stucco", 0.95)
		m_pale = mat(Color(0.9, 0.9, 0.87), "", 0.8)
		m_wood = kit.mat(Color(0.4, 0.26, 0.16), "planks", 0.8)
		var fabrics: Array[Color] = [Color(0.5, 0.2, 0.18), Color(0.25, 0.4, 0.3), Color(0.28, 0.34, 0.45), Color(0.55, 0.45, 0.25), Color(0.4, 0.3, 0.42)]
		m_fabric = mat(fabrics[rng.randi() % fabrics.size()], "", 0.8)
		m_ac = kit.mat(Color(0.72, 0.72, 0.68), "metal", 0.6)
		kit.footprint(Rect2(-hx, -hz, W, D))

	## Top of the walking surface of storey `i` (0 = ground floor).
	func fy(i: int) -> float:
		return f0 + i * FH

	func storey_at(y: float) -> int:
		return maxi(0, roundi((y - f0) / FH))

	## Plain (untextured) colours snap to a coarse grid so a building shares a handful of materials (one draw each).
	func mat(color: Color, tex: String = "", rough: float = 0.85) -> StandardMaterial3D:
		if tex.is_empty():
			return kit.mat(Color(snappedf(color.r, 0.125), snappedf(color.g, 0.125), snappedf(color.b, 0.125)), "", 0.3 if rough < 0.4 else 0.8)
		return kit.mat(color, tex, rough)

	func glow(color: Color, energy: float = 1.3) -> StandardMaterial3D:
		return kit.glow(color, energy)

	# --- placement claims ---

	func reserve(s: int, r: Rect2) -> void:
		if not zones.has(s):
			zones[s] = []
		(zones[s] as Array).append(r)

	## Claims a floor rectangle on storey `s` if it is free of doors, stairs and earlier furniture.
	func claim(s: int, r: Rect2) -> bool:
		if not zones.has(s):
			zones[s] = []
		for other: Rect2 in zones[s]:
			if other.intersects(r):
				return false
		(zones[s] as Array).append(r)
		return true

	## The first candidate rectangle inside `room` that can be claimed, or an empty Rect2.
	func fit(s: int, room: Rect2, candidates: Array) -> Rect2:
		for candidate: Rect2 in candidates:
			if room.encloses(candidate) and claim(s, candidate):
				return candidate
		return Rect2()

	# --- boxes with a rotation about the furniture origin ---

	## A visible box at `off` (furniture-local) around `origin`, the furniture turned by `angle` about Y.
	func fbox(origin: Vector3, angle: float, off: Vector3, box_size: Vector3, material: Material, solid: bool = false) -> void:
		kit.box(origin + Basis(Vector3.UP, angle) * off, box_size, material, solid, angle)

	## The same as a collision-free prop (merged into the props node, hidden in potato mode).
	func fprop(origin: Vector3, angle: float, off: Vector3, box_size: Vector3, material: Material) -> void:
		props.append([origin + Basis(Vector3.UP, angle) * off, box_size, material, angle])

	func deco(at: Vector3, box_size: Vector3, material: Material, angle: float = 0.0) -> void:
		props.append([at, box_size, material, angle])

	## A cylinder (water tanks, vents, drums); collision is the caller's business.
	func cyl(center: Vector3, radius: float, height: float, material: Material, segments: int = 10) -> void:
		var instance: MeshInstance3D = MeshInstance3D.new()
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = segments
		mesh.rings = 1
		instance.mesh = mesh
		instance.material_override = material
		instance.position = center
		kit._current.add_child(instance)

	## Collision only, around a furniture origin.
	func fcollide(origin: Vector3, angle: float, off: Vector3, box_size: Vector3) -> void:
		kit.collider(origin + Basis(Vector3.UP, angle) * off, box_size, angle)

	# --- structure ---

	func to_interior() -> void:
		kit.begin_interior()

	func to_shell() -> void:
		kit.end_interior()

	## The four outer walls to parapet height. Openings are kit openings whose "at" is the local x (front, back)
	## or z (left, right) of the opening's centre.
	func walls(front: Array = [], back: Array = [], left: Array = [], right: Array = []) -> void:
		var top: float = roof_y + PARAPET
		kit.wall(Vector2(-hx + WALL_T, hz - WALL_T * 0.5), Vector2(hx - WALL_T, hz - WALL_T * 0.5), top, m_wall, _shift(front, hx - WALL_T))
		kit.wall(Vector2(-hx + WALL_T, -hz + WALL_T * 0.5), Vector2(hx - WALL_T, -hz + WALL_T * 0.5), top, m_wall, _shift(back, hx - WALL_T))
		kit.wall(Vector2(-hx + WALL_T * 0.5, -hz), Vector2(-hx + WALL_T * 0.5, hz), top, m_wall, _shift(left, hz))
		kit.wall(Vector2(hx - WALL_T * 0.5, -hz), Vector2(hx - WALL_T * 0.5, hz), top, m_wall, _shift(right, hz))
		# The parapet cap and the front cornice.
		var cap_y: float = top + 0.07
		kit.box(Vector3(0, cap_y, hz - 0.2), Vector3(W + 0.2, 0.14, 0.5), m_trim)
		kit.box(Vector3(0, cap_y, -hz + 0.2), Vector3(W + 0.2, 0.14, 0.5), m_trim)
		kit.box(Vector3(-hx + 0.2, cap_y, 0), Vector3(0.5, 0.14, D - 0.4), m_trim)
		kit.box(Vector3(hx - 0.2, cap_y, 0), Vector3(0.5, 0.14, D - 0.4), m_trim)
		if rng.randf() < 0.6:
			kit.box(Vector3(0, roof_y - 0.25, hz + 0.12), Vector3(W + 0.1, 0.42, 0.28), m_trim)

	func _shift(openings: Array, offset: float) -> Array:
		var shifted: Array = []
		for spec: Dictionary in openings:
			var copy: Dictionary = spec.duplicate()
			copy["at"] = float(spec["at"]) + offset
			shifted.append(copy)
		return shifted

	## A floor plate for storey `i` whose top is fy(i), with holes (stairwells). Interior layer, solid.
	func slab(i: int, holes: Array = []) -> void:
		kit.floor_slab(Rect2(-hx + 0.03, -hz + 0.03, W - 0.06, D - 0.06), fy(i), m_floor, holes)

	## The roof: shell layer, solid, with holes for a roof stair.
	func roof_slab(holes: Array = []) -> void:
		kit.floor_slab(Rect2(-hx + 0.03, -hz + 0.03, W - 0.06, D - 0.06), roof_y, m_roof, holes)

	## A pale ceiling plate just under the roof slab (the roof itself is dark tar), with the same holes.
	func roof_ceiling(holes: Array = []) -> void:
		kit.floor_slab(Rect2(-hx + WALL_T, -hz + WALL_T, W - WALL_T * 2.0, D - WALL_T * 2.0), roof_y - SLAB - 0.001, m_ceil, holes, 0.03)

	## An interior partition wall on storey `s` (from the floor to the underside of the next slab).
	func part(s: int, a: Vector2, b: Vector2, openings: Array = [], thickness: float = PART_T) -> void:
		kit.wall(a, b, FH - SLAB, m_part, openings, fy(s), thickness)

	## A partition with `at` given as the coordinate along the wall (x for walls along X, z for walls along Z).
	func partx(s: int, x0: float, x1: float, z: float, openings_x: Array = []) -> void:
		var specs: Array = []
		for spec: Dictionary in openings_x:
			var copy: Dictionary = spec.duplicate()
			copy["at"] = float(spec["at"]) - x0
			specs.append(copy)
		part(s, Vector2(x0, z), Vector2(x1, z), specs)

	func partz(s: int, z0: float, z1: float, x: float, openings_z: Array = []) -> void:
		var specs: Array = []
		for spec: Dictionary in openings_z:
			var copy: Dictionary = spec.duplicate()
			copy["at"] = float(spec["at"]) - z0
			specs.append(copy)
		part(s, Vector2(x, z0), Vector2(x, z1), specs)

	## A doorway opening description with `at` as the coordinate along the wall.
	func gap(at: float, width: float = 1.0, top: float = 2.4) -> Dictionary:
		return Kit.opening(at, width, 0.0, top, "door")

	# --- doors ---

	## A frame (jambs and header) around a doorway; `along_x` when the wall runs along X.
	func frame(center: Vector3, width: float, height: float, along_x: bool, depth: float = WALL_T) -> void:
		var jamb: float = 0.09
		var d: float = depth + 0.05
		if along_x:
			kit.box(center + Vector3(-(width * 0.5 + jamb * 0.5), height * 0.5, 0), Vector3(jamb, height, d), m_trim)
			kit.box(center + Vector3(width * 0.5 + jamb * 0.5, height * 0.5, 0), Vector3(jamb, height, d), m_trim)
			kit.box(center + Vector3(0, height + jamb * 0.5, 0), Vector3(width + jamb * 2.0, jamb, d), m_trim)
		else:
			kit.box(center + Vector3(0, height * 0.5, -(width * 0.5 + jamb * 0.5)), Vector3(d, height, jamb), m_trim)
			kit.box(center + Vector3(0, height * 0.5, width * 0.5 + jamb * 0.5), Vector3(d, height, jamb), m_trim)
			kit.box(center + Vector3(0, height + jamb * 0.5, 0), Vector3(d, jamb, width + jamb * 2.0), m_trim)

	## A hinged door in a wall opening, registered with the world, with a frame and a placement clearance on both
	## sides. `facing` is the direction people arrive from. Returns the interactable_doors index.
	func door(center: Vector3, width: float, height: float, facing: Vector3, label: String, kind_name: String = "door", inner: bool = false, leaf_mat: Material = null, thickness: float = WALL_T) -> int:
		var index: int = kit.add_door(center, width, height, facing, label, kind_name, leaf_mat, 2 if width >= 1.4 else 0)
		var along_x: bool = absf(facing.z) > 0.5
		frame(center, width, height, along_x, thickness)
		for hinge: Node in world._door_nodes[index]:
			for body: Node in hinge.get_children():
				for part_node: Node in body.get_children():
					if part_node is GeometryInstance3D:
						(part_node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						(part_node as GeometryInstance3D).visibility_range_end = 16.0 if inner else 40.0
		var s: int = storey_at(center.y)
		var reach: Vector2 = Vector2(width * 0.5 + 0.3, 1.7)
		if along_x:
			reserve(s, Rect2(center.x - reach.x, center.z - reach.y, reach.x * 2.0, reach.y * 2.0))
		else:
			reserve(s, Rect2(center.x - reach.y, center.z - reach.x, reach.y * 2.0, reach.x * 2.0))
		doors.append({"index": index, "label": label, "storey": s, "local": center, "facing": facing, "width": width, "kind": kind_name, "inner": inner})
		return index

	## A roll-up door (a shutter that lifts): a wide opening that starts open. Registered as a door.
	func roller(center: Vector3, width: float, height: float, facing: Vector3, label: String) -> int:
		var out: Vector3 = Vector3(facing.x, 0, facing.z).normalized()
		var shutter: Node3D = Node3D.new()
		kit._current.add_child(shutter)
		shutter.position = center
		shutter.rotation.y = atan2(out.x, out.z)
		shutter.set_meta("roller", height - 0.2)
		shutter.position.y = center.y + height - 0.2
		var body: StaticBody3D = StaticBody3D.new()
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box_shape: BoxShape3D = BoxShape3D.new()
		box_shape.size = Vector3(width, height, 0.08)
		shape.shape = box_shape
		body.add_child(shape)
		var visual: MeshInstance3D = MeshInstance3D.new()
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = box_shape.size
		visual.mesh = mesh
		visual.material_override = kit.mat(Color(0.5, 0.52, 0.5), "metal", 0.6)
		visual.visibility_range_end = 60.0
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(visual)
		body.position = Vector3(0, height * 0.5, 0)
		shutter.add_child(body)
		var index: int = world.interactable_doors.size()
		world.interactable_doors.append({"index": index, "label": label, "kind": "door", "position": kit.to_world(center), "inside": kit.to_world(center - out * 1.6),
			"outside": kit.to_world(center + out * 1.6), "open": true, "district": str(style.get("district", "")), "width": width})
		world._door_nodes.append([shutter])
		var along_x: bool = absf(out.z) > 0.5
		frame(center, width, height, along_x, WALL_T)
		var s: int = storey_at(center.y)
		if along_x:
			reserve(s, Rect2(center.x - width * 0.5 - 0.3, center.z - 2.0, width + 0.6, 4.0))
		else:
			reserve(s, Rect2(center.x - 2.0, center.z - width * 0.5 - 0.3, 4.0, width + 0.6))
		doors.append({"index": index, "label": label, "storey": s, "local": center, "facing": facing, "width": width, "kind": "roller", "inner": false})
		return index

	# --- facade dressing ---

	## A painted window on an outer wall: frame, glass (dark, or lit warm), sill and a pale pane on the inside.
	## `pos` is the window centre on the wall's outer face; `normal` is the outward unit vector.
	func window(pos: Vector3, normal: Vector3, w: float, h: float, is_lit: bool, with_ac: bool = false, tint: Material = null) -> void:
		var angle: float = atan2(normal.x, normal.z)
		var glass: Material = kit.glow(Color(1.0, 0.78, 0.46), 1.3) if is_lit else m_dark
		if tint != null:
			glass = tint
		if blinds:
			deco(pos - normal * (WALL_T + 0.05) + Vector3(0, h * 0.22, 0), Vector3(w * 0.95, h * 0.56, 0.03), m_ceil)
		kit.box(pos + normal * 0.03, Vector3(w + 0.26, h + 0.26, 0.06), m_trim, false, angle)
		kit.box(pos + normal * 0.05, Vector3(w, h, 0.04), glass, false, angle)
		kit.box(pos + normal * 0.09 - Vector3(0, h * 0.5 + 0.17, 0), Vector3(w + 0.4, 0.07, 0.24), m_trim, false, angle)
		kit.box(pos - normal * (WALL_T + 0.01), Vector3(w, h, 0.04), m_pane_in, false, angle)
		if with_ac:
			kit.box(pos + normal * 0.3 - Vector3(0, h * 0.5 + 0.35, 0), Vector3(0.72, 0.44, 0.5), m_ac, false, angle)

	## Rows of windows along one outer wall. side: "front", "back", "left" or "right". `avoid` holds Vector2(min, max)
	## ranges along the wall (local x or z) that stay clear (doors, storefronts). `storeys` lists the storeys.
	func windows_on(side: String, storeys: Array, spacing: float = 3.2, avoid: Array = [], w: float = 1.3, h: float = 1.5, sill: float = 0.95, tint: Material = null) -> void:
		var length: float = W if side == "front" or side == "back" else D
		var count: int = maxi(1, floori((length - 1.6) / spacing))
		for s: int in storeys:
			for index: int in range(count):
				var t: float = -length * 0.5 + (index + 0.5) * length / count
				var blocked: bool = false
				for range_v: Vector2 in avoid:
					if t > range_v.x - w * 0.5 - 0.15 and t < range_v.y + w * 0.5 + 0.15:
						blocked = true
				if blocked:
					continue
				var y: float = fy(s) + sill + h * 0.5
				var pos: Vector3
				var normal: Vector3
				match side:
					"front":
						pos = Vector3(t, y, hz)
						normal = Vector3.BACK
					"back":
						pos = Vector3(t, y, -hz)
						normal = Vector3.FORWARD
					"left":
						pos = Vector3(-hx, y, t)
						normal = Vector3.LEFT
					_:
						pos = Vector3(hx, y, t)
						normal = Vector3.RIGHT
				var is_lit: bool = rng.randf() < lit
				var with_ac: bool = s > 0 and not is_lit and rng.randf() < 0.22
				window(pos, normal, w, h, is_lit, with_ac, tint)

	## A sign board with painted text over the front, centred at local x.
	func fascia(at_x: float, y: float, width: float, height: float = 0.7, font: int = 42) -> void:
		kit.box(Vector3(at_x, y, hz + 0.16), Vector3(width, height, 0.14), m_accent)
		kit.sign_label(sign_text, Vector3(at_x, y, hz + 0.25), font, Color(0.96, 0.92, 0.8))

	## A tilted awning over the front: a slab pitched out and down.
	func awning(at_x: float, y: float, width: float, out: float = 1.3) -> void:
		var awning_mesh: MeshInstance3D = MeshInstance3D.new()
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(width, 0.06, out)
		awning_mesh.mesh = mesh
		awning_mesh.material_override = m_accent
		awning_mesh.transform = Transform3D(Basis(Vector3.RIGHT, 0.32), Vector3(at_x, y, hz + out * 0.5 - 0.05))
		kit._current.add_child(awning_mesh)
		kit.box(Vector3(at_x, y - 0.2, hz + out - 0.1), Vector3(width, 0.36, 0.05), m_accent)

	## A door step and low cheek walls in front of a street door (collision on the cheeks only).
	func stoop(at_x: float, width: float) -> void:
		var base: float = f0 - 0.01
		kit.box(Vector3(at_x, base - 0.06, hz + 0.55), Vector3(width + 0.5, 0.12, 1.1), m_trim, true)
		for side: float in [-1.0, 1.0]:
			kit.box(Vector3(at_x + side * (width * 0.5 + 0.3), base + 0.35, hz + 0.6), Vector3(0.22, 0.6, 1.0), m_trim, true)

	## A visual-only fire escape on the front: platforms with rails and stairs between them (no collision, so nobody
	## can climb it; the drop ladder stops short of the ground).
	func fire_escape(at_x: float, from_storey: int, to_storey: int) -> void:
		var steel: StandardMaterial3D = m_metal
		for s: int in range(from_storey, to_storey + 1):
			var y: float = fy(s)
			kit.box(Vector3(at_x, y - 0.05, hz + 0.6), Vector3(2.4, 0.06, 1.2), steel)
			kit.box(Vector3(at_x, y + 1.0, hz + 1.17), Vector3(2.4, 0.05, 0.05), steel)
			for side: float in [-1.0, 1.0]:
				kit.box(Vector3(at_x + side * 1.17, y + 1.0, hz + 0.6), Vector3(0.05, 0.05, 1.1), steel)
			for post: int in range(4):
				kit.box(Vector3(at_x - 1.17 + post * 0.78, y + 0.5, hz + 1.17), Vector3(0.04, 1.0, 0.04), steel)
			if s < to_storey:
				kit.bar(Vector3(at_x - 0.9, y, hz + 0.9), Vector3(at_x + 0.9, fy(s + 1) - 0.05, hz + 0.9), 0.1, steel, false)
				kit.bar(Vector3(at_x - 0.7, y, hz + 0.8), Vector3(at_x + 1.1, fy(s + 1) - 0.05, hz + 0.8), 0.06, steel, false)
		kit.bar(Vector3(at_x + 1.0, fy(from_storey) - 0.05, hz + 0.9), Vector3(at_x + 1.0, 2.4, hz + 0.9), 0.05, steel, false)

	## A lamp on the interior layer (at most two per building).
	func lamp(at: Vector3, energy: float = 2.0, light_range: float = 13.0) -> void:
		if lamps >= 2:
			return
		lamps += 1
		kit.interior_light(at, Color(1.0, 0.86, 0.62), energy, light_range)

	# --- finishing ---

	func finish() -> void:
		var node: Node3D = kit.node
		# Props first (they need the interior node): one collision-free, merged, layer-2 node.
		if not props.is_empty():
			if kit.interior == null:
				kit.begin_interior()
			kit.begin_props()
			for entry: Array in props:
				kit.prop(entry[0], entry[1], entry[2], float(entry[3]))
			kit.end_props()
		if kit.props != null:
			var prop_node: Node3D = kit.props
			world.MeshMerge.merge_children(prop_node)
			for child: Node in prop_node.get_children():
				if child is GeometryInstance3D:
					var geometry: GeometryInstance3D = child as GeometryInstance3D
					geometry.layers = 1 << (world.INTERIOR_LAYER - 1)
					geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					geometry.visibility_range_end = PROP_RANGE
					geometry.visibility_range_end_margin = 3.0
			prop_node.add_to_group("potato_optional")
			prop_node.set_meta("prop_node", true)
			prop_node.set_meta("finished", true)
		BuildingPrefabs._consolidate(node)
		if kit.interior != null:
			BuildingPrefabs._consolidate(kit.interior)
		# No multimesh batching: one merged mesh per material is fewer draws for a unique building.
		node.set_meta("finished", true)
		world.MeshMerge.merge_children(node)
		BuildingPrefabs._shadow_proxy(node)
		if kit.interior != null:
			var interior: Node3D = kit.interior
			interior.set_meta("finished", true)
			world.MeshMerge.merge_children(interior)
			for child: Node in interior.get_children():
				if child is GeometryInstance3D:
					var geometry: GeometryInstance3D = child as GeometryInstance3D
					geometry.layers = 1 << (world.INTERIOR_LAYER - 1)
					geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					geometry.visibility_range_end = INTERIOR_RANGE
					geometry.visibility_range_end_margin = 4.0
		var floor_ys: Array[float] = []
		for i: int in range(floors):
			floor_ys.append(fy(i))
		floor_ys.append_array(extra_floors)
		node.set_meta("enterable", true)
		node.set_meta("kind", kind)
		node.set_meta("floors", floors)
		node.set_meta("size", Vector2(W, D))
		node.set_meta("floor_ys", floor_ys)
		node.set_meta("doors", doors)
		node.set_meta("stairs", stairs)
		node.set_meta("routes", routes)
		node.set_meta("roof_y", roof_y)
		node.set_meta("sign", sign_text)
		node.set_meta("walk_in", true)
		node.set_meta("interior_half", Vector2(hx, hz))
		node.set_meta("front_yaw", kit.yaw)


## Folds the plain single-shape static bodies directly under `parent` into one body (the kit makes one body per
## wall piece and slab; a building has hundreds). Stair flights, glass and scripted bodies are left alone.
static func _shadow_proxy(parent: Node3D) -> void:
	# The world's proxy needs two donors; a merged building has one mesh with many surfaces, and every surface would
	# be drawn once per shadow split. Fold the casting meshes into one positions-only mesh drawn SHADOWS_ONLY.
	var vertices: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var donors: Array[MeshInstance3D] = []
	for child: Node in parent.get_children():
		if not (child is MeshInstance3D):
			continue
		var instance: MeshInstance3D = child as MeshInstance3D
		if instance.mesh == null or instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON or instance.visibility_range_end > 0.0:
			continue
		for surface: int in range(instance.mesh.get_surface_count()):
			var material: Material = instance.mesh.surface_get_material(surface)
			if material is BaseMaterial3D and (material as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var local_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var local_indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var base: int = vertices.size()
			vertices.append_array(instance.transform * local_vertices)
			if local_indices == null or (local_indices as PackedInt32Array).is_empty():
				for i: int in range(local_vertices.size()):
					indices.append(base + i)
			else:
				for index: int in (local_indices as PackedInt32Array):
					indices.append(base + index)
		donors.append(instance)
	if donors.is_empty() or vertices.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var shadow_mesh: ArrayMesh = ArrayMesh.new()
	shadow_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	for donor: MeshInstance3D in donors:
		donor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var proxy: MeshInstance3D = MeshInstance3D.new()
	proxy.name = "ShadowProxy"
	proxy.mesh = shadow_mesh
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	parent.add_child(proxy)


static func _consolidate(parent: Node3D) -> void:
	var merged: StaticBody3D = StaticBody3D.new()
	merged.name = "Solid"
	var moved: int = 0
	for child: Node in parent.get_children():
		if not (child is StaticBody3D) or child.get_script() != null or str(child.name).begins_with("Flight") or child == merged:
			continue
		var body: StaticBody3D = child as StaticBody3D
		var plain: bool = true
		for part: Node in body.get_children():
			if not (part is CollisionShape3D):
				plain = false
		if not plain:
			continue
		for part: Node in body.get_children():
			var shape_node: CollisionShape3D = part as CollisionShape3D
			var carried: Transform3D = body.transform * shape_node.transform
			body.remove_child(shape_node)
			merged.add_child(shape_node)
			shape_node.transform = carried
			moved += 1
		parent.remove_child(body)
		body.queue_free()
	if moved > 0:
		parent.add_child(merged)
	else:
		merged.free()


# --- WALKUP: apartments with a lobby, two U-stair bays, a corridor core and two flats a floor ---------

const BAY_W: float = 1.05
const BAY_GAP: float = 0.1
const CORE_HALF: float = 2.45
## A U-stair's depth: nine 0.3 m steps plus the landing.
const U_DEPTH: float = 3.9


static func _walkup(c: Ctx) -> void:
	c.blinds = c.kind == "office"
	var hx: float = c.hx
	var hz: float = c.hz
	var z_back: float = -hz + WALL_T
	var z_s: float = z_back + U_DEPTH + 0.02
	# Bay x ranges: A on the left of the core, B on the right, with a spacer wall on x = 0.
	var bays: Array[Rect2] = [Rect2(-2.3, z_back, 2.2, z_s - z_back + 0.3), Rect2(0.1, z_back, 2.2, z_s - z_back + 0.3)]
	var flights: int = c.floors
	# --- exterior ---
	var door_w: float = 1.8
	var rear_x: float = 1.2
	c.walls([Kit.opening(0.0, door_w, 0.0, DOOR_H, "door")], [Kit.opening(rear_x, 1.4, 0.0, DOOR_H, "door")])
	c.roof_slab(_roof_holes(c, bays, flights - 1))
	var front_gap: Vector2 = Vector2(-CORE_HALF - 0.1, CORE_HALF + 0.1)
	c.windows_on("front", [0], 3.4, [front_gap])
	c.windows_on("front", range(1, c.floors), 3.4, [])
	c.windows_on("back", range(c.floors), 3.6, [Vector2(rear_x - 0.9, rear_x + 0.9)])
	c.windows_on("left", range(c.floors), 3.6)
	c.windows_on("right", range(c.floors), 3.6)
	c.door(Vector3(0, c.f0, hz - WALL_T * 0.5), door_w, DOOR_H, Vector3.BACK, c.sign_text + " entrance")
	c.door(Vector3(rear_x, c.f0, -hz + WALL_T * 0.5), 1.4, DOOR_H, Vector3.FORWARD, c.sign_text + " alley door")
	c.stoop(0.0, door_w)
	c.awning(0.0, c.f0 + 3.0, door_w + 1.0, 1.4)
	c.fascia(0.0, c.f0 + 3.55, 3.6, 0.55, 30)
	if c.floors >= 2 and c.rng.randf() < 0.75:
		var side: float = -1.0 if c.rng.randf() < 0.5 else 1.0
		c.fire_escape(side * (hx * 0.5 + 0.3), 1, c.floors - 1)
	# --- interior ---
	c.to_interior()
	for s: int in range(c.floors):
		var holes: Array = []
		if s >= 1:
			holes.append(bays[(s - 1) % 2])
		c.slab(s, holes)
	c.roof_ceiling(_roof_holes(c, bays, flights - 1))
	for s: int in range(c.floors):
		_walkup_storey(c, s, z_s, bays)
	_walkup_stairs(c, z_s, bays)
	c.lamp(Vector3(0, c.fy(0) + 2.6, z_s + 2.0), 2.2, 13.0)
	if c.floors >= 3:
		c.lamp(Vector3(0, c.fy(2) + 2.6, z_s + 2.0), 2.0, 13.0)
	c.to_shell()
	_roof_bulkhead(c, bays, z_s, flights - 1)
	_roof_details(c)


static func _roof_holes(c: Ctx, bays: Array[Rect2], flight: int) -> Array:
	return [bays[flight % 2]]


## One storey of the walkup: partitions round the core, a door to each flat, the flats and the lobby dressing.
static func _walkup_storey(c: Ctx, s: int, z_s: float, bays: Array[Rect2]) -> void:
	var hz: float = c.hz
	var hx: float = c.hx
	var z_back: float = -hz + WALL_T
	var z_front: float = hz - WALL_T
	var door_z: float = z_s + 2.0
	var y: float = c.fy(s)
	for side: float in [-1.0, 1.0]:
		var x: float = side * CORE_HALF
		c.partz(s, z_back, z_front, x, [c.gap(door_z, 1.1, DOOR_H)])
		var facing: Vector3 = Vector3.RIGHT if side < 0.0 else Vector3.LEFT
		if c.kind == "office":
			c.frame(Vector3(x, y, door_z), 1.1, DOOR_H, false, PART_T)
			c.reserve(s, Rect2(x - 1.7, door_z - 0.8, 3.4, 1.6))
		else:
			c.door(Vector3(x, y, door_z), 1.1, DOOR_H, facing, "%s flat %d" % [c.sign_text, s * 2 + (1 if side < 0.0 else 2)], "door", true, null, PART_T)
		var flat: Rect2
		if side < 0.0:
			flat = Rect2(-hx + WALL_T, z_back, hx - WALL_T - CORE_HALF - PART_T * 0.5, z_front - z_back)
		else:
			flat = Rect2(CORE_HALF + PART_T * 0.5, z_back, hx - WALL_T - CORE_HALF - PART_T * 0.5, z_front - z_back)
		_flat(c, s, flat, flat.end.x if side < 0.0 else flat.position.x, door_z)
	# The spacer between the two bays, and a rail over the flight-one half of any stairwell hole in this floor.
	c.partz(s, z_back, z_s + 0.3, 0.0)
	c.reserve(s, Rect2(-CORE_HALF, z_back, CORE_HALF * 2.0, z_s + 0.3 - z_back))
	if s >= 1:
		_hole_rail(c, (s - 1) % 2, y, z_s)
	if s == 0:
		_lobby(c, z_s)
		if c.kind == "office":
			_reception(c, door_z)


## A rail across the flight-one half of the arrival edge of a stairwell hole at floor height `y`.
static func _hole_rail(c: Ctx, bay: int, y: float, z_s: float) -> void:
	var z: float = z_s + 0.3 + 0.16
	if bay == 0:
		c.kit.railing(Vector3(-1.2, y, z), Vector3(-0.1, y, z))
	else:
		c.kit.railing(Vector3(1.2, y, z), Vector3(2.3, y, z))


## The lobby: mailboxes on the right partition, a notice board on the left, a lamp, a radiator.
static func _lobby(c: Ctx, z_s: float) -> void:
	var y: float = c.fy(0)
	var z: float = c.hz - WALL_T - 2.2
	var brass: StandardMaterial3D = c.mat(Color(0.7, 0.58, 0.3), "metal", 0.4)
	var tin: StandardMaterial3D = c.mat(Color(0.5, 0.52, 0.5), "metal", 0.5)
	c.deco(Vector3(CORE_HALF - PART_T * 0.5 - 0.05, y + 1.35, z), Vector3(0.1, 0.9, 1.6), tin)
	for row: int in range(3):
		for col: int in range(4):
			c.deco(Vector3(CORE_HALF - PART_T * 0.5 - 0.11, y + 1.05 + row * 0.28, z - 0.6 + col * 0.4), Vector3(0.03, 0.2, 0.3), brass)
	c.deco(Vector3(-CORE_HALF + PART_T * 0.5 + 0.04, y + 1.6, z), Vector3(0.05, 0.9, 0.7), c.mat(Color(0.5, 0.36, 0.2), "planks", 0.8))
	for note: int in range(4):
		c.deco(Vector3(-CORE_HALF + PART_T * 0.5 + 0.075, y + 1.4 + (note % 2) * 0.4, z - 0.22 + (note / 2) * 0.4), Vector3(0.02, 0.24, 0.18), c.mat([Color(0.95, 0.94, 0.88), Color(0.95, 0.85, 0.4), Color(0.85, 0.5, 0.5), Color(0.6, 0.75, 0.85)][note], "", 0.9))


## Both stair bays' flights: bay A from floor 0, bay B from floor 1, and so on, one flight per storey and one to the roof.
static func _walkup_stairs(c: Ctx, z_s: float, bays: Array[Rect2]) -> void:
	var steel: StandardMaterial3D = c.mat(Color(0.34, 0.3, 0.26), "planks", 0.8)
	for k: int in range(c.floors):
		var bay: Rect2 = bays[k % 2]
		var x_start: float = bay.end.x - BAY_W * 0.5
		var x_second: float = x_start - (BAY_W + BAY_GAP)
		var floor_y: float = c.fy(k)
		var start: Vector3 = Vector3(x_start, floor_y, z_s)
		var flight: Dictionary = c.kit.stairs_u(start, Vector3.FORWARD, FH, BAY_W, BAY_GAP, steel)
		var top: Vector3 = flight["top"]
		var landing_y: float = float((flight["landing"] as Vector3).y)
		c.stairs.append({"from": k, "to": k + 1, "bottom": start, "top": top, "landing": flight["landing"], "kind": "u"})
		c.routes["stair_%d" % k] = [Vector3(x_start, floor_y, z_s + 1.0), Vector3(x_start, floor_y, z_s), Vector3(x_start, landing_y, z_s - 2.7),
			Vector3(x_start, landing_y, z_s - 3.3), Vector3(x_second, landing_y, z_s - 3.3), Vector3(x_second, landing_y, z_s - 2.7),
			Vector3(x_second, top.y, top.z), Vector3(x_second, top.y, top.z + 1.0)]
		c.reserve(k, Rect2(bay.position.x, bay.position.y, bay.size.x, bay.size.y))
	c.routes["rear"] = [Vector3(1.2, c.f0, -c.hz + 1.0), Vector3(1.2, c.f0, z_s + 1.0), Vector3(0.0, c.f0, c.hz - 1.0)]




## The roof stair head: walls and a flat roof over the last flight's hole, a door out onto the roof and the hole rail.
static func _roof_bulkhead(c: Ctx, bays: Array[Rect2], z_s: float, flight: int) -> void:
	var bay: Rect2 = bays[flight % 2]
	var y: float = c.roof_y
	var z_back: float = -c.hz + WALL_T
	var z_e: float = z_s + 0.3 + 1.7
	var h: float = 2.9
	for sx: float in [bay.position.x - 0.1, bay.end.x + 0.1]:
		c.kit.wall(Vector2(sx, z_back), Vector2(sx, z_e), h, c.m_wall, [], y, 0.2)
	c.kit.wall(Vector2(bay.position.x - 0.2, z_back + 0.1), Vector2(bay.end.x + 0.2, z_back + 0.1), h, c.m_wall, [], y, 0.2)
	var x_door: float = bay.position.x + BAY_W * 0.5
	var x0: float = bay.position.x - 0.2
	c.kit.wall(Vector2(x0, z_e), Vector2(bay.end.x + 0.2, z_e), h, c.m_wall, [Kit.opening(x_door - x0, 1.0, 0.0, 2.5, "door")], y, 0.2)
	c.kit.box(Vector3((bay.position.x + bay.end.x) * 0.5, y + h + 0.1, (z_back + z_e) * 0.5), Vector3(bay.size.x + 0.7, 0.2, z_e - z_back + 0.3), c.m_roof, true)
	c.door(Vector3(x_door, y, z_e), 1.0, 2.5, Vector3.BACK, c.sign_text + " roof access", "door", false, null, 0.2)
	_hole_rail(c, flight % 2, y, z_s)
	c.reserve(c.floors, Rect2(bay.position.x - 0.4, z_back, bay.size.x + 0.8, z_e + 1.8 - z_back))
	c.routes["roof"] = [Vector3(x_door, y, z_s + 1.0), Vector3(x_door, y, z_e + 1.4)]


## Roof clutter: a wooden water tank on legs, a chimney, a vent or two and an AC condenser, all claimed so they keep
## clear of the roof door. Solid, so the roof has cover.
static func _roof_details(c: Ctx) -> void:
	var y: float = c.roof_y
	var wood: StandardMaterial3D = c.mat(Color(0.4, 0.28, 0.18), "planks", 0.9)
	var metal: StandardMaterial3D = c.m_metal
	var brick: StandardMaterial3D = c.mat(Color(0.5, 0.26, 0.2), "brick", 0.9)
	var tank_at: Vector2 = Vector2(c.hx * 0.45 * (1.0 if c.rng.randf() < 0.5 else -1.0), -c.hz * 0.35)
	if c.claim(c.floors, Rect2(tank_at.x - 1.6, tank_at.y - 1.6, 3.2, 3.2)):
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			c.kit.box(Vector3(tank_at.x + corner.x * 1.0, y + 0.9, tank_at.y + corner.y * 1.0), Vector3(0.14, 1.8, 0.14), metal)
		c.cyl(Vector3(tank_at.x, y + 2.85, tank_at.y), 1.3, 2.1, wood, 12)
		c.cyl(Vector3(tank_at.x, y + 4.0, tank_at.y), 1.4, 0.2, c.m_roof, 12)
		c.kit.collider(Vector3(tank_at.x, y + 1.9, tank_at.y), Vector3(2.6, 3.8, 2.6))
	var spot: Vector2 = Vector2(-c.hx * 0.3, c.hz * 0.35)
	if c.claim(c.floors, Rect2(spot.x - 0.6, spot.y - 0.6, 1.2, 1.2)):
		c.kit.box(Vector3(spot.x, y + 1.3, spot.y), Vector3(0.9, 2.6, 0.9), brick, true)
		c.kit.box(Vector3(spot.x, y + 2.65, spot.y), Vector3(1.1, 0.12, 1.1), c.m_trim)
	var unit: Vector2 = Vector2(c.hx * 0.3, c.hz * 0.3)
	if c.claim(c.floors, Rect2(unit.x - 0.8, unit.y - 0.8, 1.6, 1.6)):
		c.kit.box(Vector3(unit.x, y + 0.5, unit.y), Vector3(1.3, 1.0, 1.3), c.m_ac, true)
		c.kit.box(Vector3(unit.x, y + 1.02, unit.y), Vector3(1.0, 0.06, 1.0), c.m_dark)
	for index: int in range(2):
		var at: Vector2 = Vector2(c.rng.randf_range(-c.hx + 2.0, c.hx - 2.0), c.rng.randf_range(-c.hz + 2.0, c.hz - 2.0))
		if c.claim(c.floors, Rect2(at.x - 0.5, at.y - 0.5, 1.0, 1.0)):
			c.cyl(Vector3(at.x, y + 0.45, at.y), 0.28, 0.9, metal, 8)
			c.kit.collider(Vector3(at.x, y + 0.45, at.y), Vector3(0.56, 0.9, 0.56))
			c.cyl(Vector3(at.x, y + 0.95, at.y), 0.4, 0.1, c.m_trim, 8)


# --- Flats and furniture --------------------------------------------------------------------------

## A flat filling `rect` (interior, x/z) on storey `s`, entered through the wall at x = `entry_x` at `entry_z`. Two rooms split
## on z (the entry room is the living room), a bathroom in the far corner of the bedroom, furniture placed with claims.
static func _flat(c: Ctx, s: int, rect: Rect2, entry_x: float, entry_z: float) -> void:
	var min_edge: bool = absf(entry_x - rect.position.x) < absf(entry_x - rect.end.x)
	var far_x: float = rect.end.x if min_edge else rect.position.x
	var z_lo: float = rect.position.y
	var z_hi: float = rect.end.y
	var back_entry: bool = entry_z < (z_lo + z_hi) * 0.5
	var z_p: float = clampf(entry_z + 1.9 if back_entry else entry_z - 1.9, z_lo + 3.6, z_hi - 3.6)
	var living: Rect2 = Rect2(rect.position.x, z_lo, rect.size.x, z_p - z_lo) if back_entry else Rect2(rect.position.x, z_p, rect.size.x, z_hi - z_p)
	var bedroom: Rect2 = Rect2(rect.position.x, z_p, rect.size.x, z_hi - z_p) if back_entry else Rect2(rect.position.x, z_lo, rect.size.x, z_p - z_lo)
	var door_x: float = rect.position.x + 1.5 if min_edge else rect.end.x - 1.5
	c.partx(s, rect.position.x, rect.end.x, z_p, [c.gap(door_x, 1.0, 2.4)])
	c.reserve(s, Rect2(door_x - 0.8, z_p - 0.9, 1.6, 1.8))
	if c.kind == "office":
		_office_fill(c, s, living, bedroom, min_edge, back_entry)
		return
	# Bathroom in the bedroom's far corner: two walls, a doorway from the bedroom, and three fixtures.
	var bath_w: float = 2.2
	var bath_d: float = 2.4
	var far_z: float = z_hi if back_entry else z_lo
	var bath_x0: float = far_x - bath_w if far_x > rect.position.x + 0.1 else far_x
	var bath_z0: float = z_lo if far_z == z_lo else z_hi - bath_d
	var inner_x: float = far_x - bath_w if far_x > rect.position.x + 0.1 else far_x + bath_w
	var inner_z: float = bath_z0 + bath_d if far_z == z_lo else bath_z0
	c.partz(s, bath_z0, bath_z0 + bath_d, inner_x)
	c.partx(s, bath_x0, bath_x0 + bath_w, inner_z, [c.gap(bath_x0 + bath_w * 0.5, 0.8, 2.3)])
	c.reserve(s, Rect2(bath_x0 + bath_w * 0.5 - 0.6, inner_z - 0.9, 1.2, 1.8))
	var bath: Rect2 = Rect2(bath_x0, bath_z0, bath_w, bath_d)
	var bath_room: Rect2 = bath.grow(0.0)
	var far_wall: String = "s" if far_z == z_hi else "n"
	var side_wall: String = "e" if far_x > rect.position.x + 0.1 else "w"
	_put(c, s, bath_room, "toilet", far_wall, 0.15)
	_put(c, s, bath_room, "sink", side_wall, bath_d - 0.7 if far_wall == "n" else 0.1)
	_put_any(c, s, bath_room, "tub", [[far_wall, 0.8], [far_wall, 0.3]])
	c.reserve(s, bath)
	# Bedroom.
	var bed_along: float = 0.3 if far_x > rect.position.x + 0.1 else bedroom.size.x - 1.6 - 0.36
	var bed_wall: String = far_wall
	if not _put(c, s, bedroom, "bed", bed_wall, bed_along):
		_put_any(c, s, bedroom, "bed", [["w", 0.6], ["e", 0.6]])
	_put_any(c, s, bedroom, "dresser", [["w" if min_edge else "e", 0.3], ["e" if min_edge else "w", 0.3], ["n" if bed_wall == "s" else "s", 0.3]])
	if c.rng.randf() < 0.7:
		_put_any(c, s, bedroom, "nightstand", [[bed_wall, bed_along + 1.68], [bed_wall, bed_along - 0.55]])
	# Living room.
	var ext_wall: String = "n" if back_entry else "s"
	_put_any(c, s, living, "counter", [[ext_wall, 0.1], [ext_wall, living.size.x - 2.3]], 2.2)
	_put_any(c, s, living, "fridge", [[ext_wall, 2.4], [ext_wall, living.size.x - 3.2]])
	var far_side: String = "e" if min_edge else "w"
	var entry_side: String = "w" if min_edge else "e"
	_put_any(c, s, living, "sofa", [[far_side, -1.0], [ext_wall, 3.0]])
	_put_any(c, s, living, "tv", [[entry_side, 0.3], [entry_side, 3.6], [entry_side, 2.0], [("s" if ext_wall == "n" else "n"), 0.5]])
	_free_table(c, s, living)


## A free-standing table with chairs near the middle of a room.
static func _free_table(c: Ctx, s: int, room: Rect2) -> void:
	var cx: float = room.position.x + room.size.x * 0.5
	var cz: float = room.position.y + room.size.y * 0.5
	var spots: Array = [Rect2(cx - 0.65, cz - 0.45, 1.3, 0.9), Rect2(cx - 0.65, cz - 1.7, 1.3, 0.9), Rect2(cx - 0.65, cz + 0.8, 1.3, 0.9)]
	var spot: Rect2 = c.fit(s, room, spots)
	if spot.size.x > 0.0:
		_furn(c, s, "table", spot, 0.0, spot.size)


## Footprint (length along its wall, depth) of each furniture kind.
static func _dims(kind: String, length: float = -1.0) -> Vector2:
	match kind:
		"bed":
			return Vector2(1.6, 2.1)
		"sofa":
			return Vector2(1.9, 0.9)
		"dresser":
			return Vector2(1.0, 0.5)
		"nightstand":
			return Vector2(0.5, 0.45)
		"tv":
			return Vector2(1.0, 0.5)
		"counter":
			return Vector2(length if length > 0.0 else 2.0, 0.65)
		"fridge":
			return Vector2(0.75, 0.75)
		"toilet":
			return Vector2(0.5, 0.75)
		"sink":
			return Vector2(0.6, 0.5)
		"tub":
			return Vector2(1.7, 0.8)
	return _dims_extra(kind, length)


## Tries `[wall, along]` pairs in order until one fits.
static func _put_any(c: Ctx, s: int, room: Rect2, kind: String, options: Array, length: float = -1.0) -> bool:
	for option: Array in options:
		if _put(c, s, room, kind, str(option[0]), float(option[1]), length):
			return true
	return false


## Places furniture against a wall of `room` (wall: n = back / min z, s = front / max z, w = min x, e = max x) at `along`
## metres from the wall's start (negative = centred). Returns false when the spot is not free.
static func _put(c: Ctx, s: int, room: Rect2, kind: String, wall: String, along: float = -1.0, length: float = -1.0) -> bool:
	var dims: Vector2 = _dims(kind, length)
	var gap: float = 0.03
	var rect: Rect2
	var facing: Vector2
	var span: float = room.size.x if wall == "n" or wall == "s" else room.size.y
	var start: float = room.position.x if wall == "n" or wall == "s" else room.position.y
	var at: float = start + (span - dims.x) * 0.5 if along < 0.0 else start + along + gap
	match wall:
		"n":
			rect = Rect2(at, room.position.y + gap, dims.x, dims.y)
			facing = Vector2(0, 1)
		"s":
			rect = Rect2(at, room.end.y - gap - dims.y, dims.x, dims.y)
			facing = Vector2(0, -1)
		"w":
			rect = Rect2(room.position.x + gap, at, dims.y, dims.x)
			facing = Vector2(1, 0)
		_:
			rect = Rect2(room.end.x - gap - dims.y, at, dims.y, dims.x)
			facing = Vector2(-1, 0)
	if not room.grow(0.001).encloses(rect):
		return false
	if not c.claim(s, rect):
		return false
	_furn(c, s, kind, rect, atan2(facing.x, facing.y), dims)
	return true


## Builds one piece of furniture: `rect` is its floor footprint, `angle` turns local +Z (its front) to face into the room.
static func _furn(c: Ctx, s: int, kind: String, rect: Rect2, angle: float, dims: Vector2) -> void:
	var o: Vector3 = Vector3(rect.get_center().x, c.fy(s), rect.get_center().y)
	var wood: StandardMaterial3D = c.m_wood
	var pale: StandardMaterial3D = c.m_pale
	var fabric: StandardMaterial3D = c.m_fabric
	match kind:
		"bed":
			c.fbox(o, angle, Vector3(0, 0.25, 0), Vector3(1.55, 0.4, 2.05), wood)
			c.fbox(o, angle, Vector3(0, 0.52, 0.05), Vector3(1.45, 0.16, 1.9), fabric)
			c.fbox(o, angle, Vector3(0, 0.75, -0.98), Vector3(1.6, 0.9, 0.06), wood)
			c.fcollide(o, angle, Vector3(0, 0.3, 0), Vector3(1.55, 0.62, 2.05))
			c.fprop(o, angle, Vector3(-0.35, 0.65, -0.72), Vector3(0.6, 0.12, 0.34), pale)
			c.fprop(o, angle, Vector3(0.35, 0.65, -0.72), Vector3(0.6, 0.12, 0.34), pale)
		"sofa":
			c.fbox(o, angle, Vector3(0, 0.25, 0.05), Vector3(1.9, 0.42, 0.78), fabric)
			c.fbox(o, angle, Vector3(0, 0.62, -0.32), Vector3(1.9, 0.5, 0.2), fabric)
			for arm: float in [-0.88, 0.88]:
				c.fbox(o, angle, Vector3(arm, 0.42, 0.05), Vector3(0.16, 0.24, 0.78), fabric)
			c.fcollide(o, angle, Vector3(0, 0.45, 0), Vector3(1.9, 0.9, 0.86))
		"dresser":
			c.fbox(o, angle, Vector3(0, 0.42, 0), Vector3(1.0, 0.84, 0.5), wood)
			c.fcollide(o, angle, Vector3(0, 0.42, 0), Vector3(1.0, 0.84, 0.5))
			c.fprop(o, angle, Vector3(0, 0.9, 0.05), Vector3(0.4, 0.14, 0.2), c.mat(Color(0.75, 0.62, 0.3), "", 0.4))
		"nightstand":
			c.fbox(o, angle, Vector3(0, 0.3, 0), Vector3(0.5, 0.6, 0.45), wood)
			c.fcollide(o, angle, Vector3(0, 0.3, 0), Vector3(0.5, 0.6, 0.45))
			c.fprop(o, angle, Vector3(0, 0.75, 0), Vector3(0.16, 0.28, 0.16), c.glow(Color(1.0, 0.85, 0.6), 0.8))
		"tv":
			c.fbox(o, angle, Vector3(0, 0.3, 0), Vector3(1.0, 0.6, 0.5), wood)
			c.fcollide(o, angle, Vector3(0, 0.3, 0), Vector3(1.0, 0.6, 0.5))
			c.fprop(o, angle, Vector3(0, 0.84, 0), Vector3(0.6, 0.48, 0.45), c.mat(Color(0.2, 0.2, 0.22), "", 0.6))
			c.fprop(o, angle, Vector3(0, 0.86, 0.23), Vector3(0.5, 0.36, 0.02), c.glow(Color(0.3, 0.45, 0.62), 0.6))
		"counter":
			c.fbox(o, angle, Vector3(0, 0.44, 0), Vector3(dims.x, 0.88, dims.y - 0.05), pale)
			c.fbox(o, angle, Vector3(0, 0.92, 0), Vector3(dims.x + 0.02, 0.05, dims.y), wood)
			c.fcollide(o, angle, Vector3(0, 0.47, 0), Vector3(dims.x, 0.94, dims.y))
			c.fprop(o, angle, Vector3(-dims.x * 0.2, 0.96, 0.05), Vector3(0.5, 0.03, 0.36), c.mat(Color(0.7, 0.72, 0.74), "metal", 0.3))
			c.fprop(o, angle, Vector3(-dims.x * 0.2, 1.08, -0.15), Vector3(0.04, 0.24, 0.04), c.mat(Color(0.75, 0.76, 0.78), "", 0.2))
		"fridge":
			c.fbox(o, angle, Vector3(0, 0.9, 0), Vector3(0.72, 1.8, 0.72), pale)
			c.fcollide(o, angle, Vector3(0, 0.9, 0), Vector3(0.72, 1.8, 0.72))
			c.fprop(o, angle, Vector3(0.28, 1.2, 0.37), Vector3(0.04, 0.5, 0.03), c.m_metal)
		"table":
			c.fbox(o, angle, Vector3(0, 0.72, 0), Vector3(1.2, 0.05, 0.8), wood)
			c.fbox(o, angle, Vector3(0, 0.36, 0), Vector3(0.16, 0.7, 0.16), wood)
			c.fcollide(o, angle, Vector3(0, 0.38, 0), Vector3(1.2, 0.76, 0.8))
			for chair: Vector2 in [Vector2(-0.4, 0.62), Vector2(0.4, 0.62), Vector2(-0.4, -0.62), Vector2(0.4, -0.62)]:
				c.fprop(o, angle, Vector3(chair.x, 0.44, chair.y), Vector3(0.4, 0.05, 0.4), wood)
				c.fprop(o, angle, Vector3(chair.x, 0.7, chair.y + (0.18 if chair.y > 0.0 else -0.18)), Vector3(0.4, 0.42, 0.04), wood)
			c.fprop(o, angle, Vector3(0.1, 0.76, 0.0), Vector3(0.24, 0.02, 0.24), c.mat(Color(0.9, 0.88, 0.8), "", 0.7))
		"toilet":
			c.fbox(o, angle, Vector3(0, 0.22, 0.05), Vector3(0.4, 0.44, 0.5), pale)
			c.fbox(o, angle, Vector3(0, 0.55, -0.27), Vector3(0.42, 0.5, 0.2), pale)
			c.fcollide(o, angle, Vector3(0, 0.35, 0), Vector3(0.45, 0.7, 0.72))
		"sink":
			c.fbox(o, angle, Vector3(0, 0.42, 0), Vector3(0.1, 0.84, 0.1), pale)
			c.fbox(o, angle, Vector3(0, 0.86, 0), Vector3(0.6, 0.12, 0.45), pale)
			c.fcollide(o, angle, Vector3(0, 0.45, 0), Vector3(0.6, 0.9, 0.48))
			c.fprop(o, angle, Vector3(0, 1.3, -0.24), Vector3(0.5, 0.6, 0.02), c.mat(Color(0.6, 0.66, 0.7), "", 0.05))
		"tub":
			c.fbox(o, angle, Vector3(0, 0.3, 0), Vector3(1.7, 0.6, 0.8), pale)
			c.fcollide(o, angle, Vector3(0, 0.3, 0), Vector3(1.7, 0.6, 0.8))
			c.fprop(o, angle, Vector3(0, 0.62, 0), Vector3(1.5, 0.02, 0.6), c.mat(Color(0.75, 0.85, 0.9), "", 0.2))
		_:
			_furn_extra(c, s, kind, o, angle, dims)


# --- More furniture: shop fixtures, warehouse racks, desks -----------------------------------------

static func _dims_extra(kind: String, length: float) -> Vector2:
	match kind:
		"shelf":
			return Vector2(length if length > 0.0 else 1.6, 0.45)
		"crate":
			return Vector2(0.9, 0.9)
		"washer":
			return Vector2(0.75, 0.72)
		"barber_chair":
			return Vector2(0.8, 0.9)
		"bin":
			return Vector2(length if length > 0.0 else 1.6, 0.6)
		"rack":
			return Vector2(length if length > 0.0 else 1.6, 0.5)
		"bench":
			return Vector2(length if length > 0.0 else 1.5, 0.5)
		"desk":
			return Vector2(1.5, 0.8)
		"cabinet":
			return Vector2(0.55, 0.65)
		"forklift":
			return Vector2(1.2, 2.5)
		"pallet_rack":
			return Vector2(length if length > 0.0 else 4.0, 0.75)
	return _dims_more(kind, length)


static func _furn_extra(c: Ctx, s: int, kind: String, o: Vector3, angle: float, dims: Vector2) -> void:
	var wood: StandardMaterial3D = c.m_wood
	var pale: StandardMaterial3D = c.m_pale
	var goods: Array[Color] = [Color(0.8, 0.3, 0.2), Color(0.25, 0.5, 0.7), Color(0.85, 0.75, 0.3), Color(0.9, 0.9, 0.85)]
	if MORE_KINDS.has(kind):
		_furn_more(c, kind, o, angle, dims)
		return
	match kind:
		"shelf":
			var board: StandardMaterial3D = c.mat(Color(0.55, 0.55, 0.52), "metal", 0.6)
			c.fbox(o, angle, Vector3(0, 1.0, -0.2), Vector3(dims.x, 2.0, 0.04), board)
			for level: int in range(4):
				c.fbox(o, angle, Vector3(0, 0.3 + level * 0.55, 0), Vector3(dims.x, 0.04, dims.y), board)
			for end: float in [-1.0, 1.0]:
				c.fbox(o, angle, Vector3(end * (dims.x * 0.5 - 0.02), 1.0, 0), Vector3(0.04, 2.0, dims.y), board)
			c.fcollide(o, angle, Vector3(0, 1.0, 0), Vector3(dims.x, 2.0, dims.y))
			var count: int = int(dims.x / 0.3)
			for level: int in range(3):
				for i: int in range(count):
					var mat: StandardMaterial3D = c.mat(goods[(i + level * 2 + int(o.x * 3.0)) % goods.size()], "", 0.8)
					c.fprop(o, angle, Vector3(-dims.x * 0.5 + 0.2 + i * 0.3, 0.42 + level * 0.55, 0.02), Vector3(0.2, 0.16 + (i % 3) * 0.05, 0.25), mat)
		"crate":
			var size: float = 0.7 + c.rng.randf() * 0.35
			c.fbox(o, angle, Vector3(0, size * 0.5, 0), Vector3(size, size, size), wood)
			c.fbox(o, angle, Vector3(0, size * 0.5, 0), Vector3(size + 0.03, 0.06, size + 0.03), c.mat(Color(0.3, 0.2, 0.12), "planks", 0.8))
			c.fcollide(o, angle, Vector3(0, size * 0.5, 0), Vector3(size, size, size))
		"washer":
			c.fbox(o, angle, Vector3(0, 0.48, 0), Vector3(0.72, 0.95, 0.68), pale)
			c.fcollide(o, angle, Vector3(0, 0.48, 0), Vector3(0.72, 0.95, 0.68))
			c.fprop(o, angle, Vector3(0, 0.55, 0.35), Vector3(0.42, 0.42, 0.03), c.mat(Color(0.2, 0.28, 0.34), "", 0.1))
			c.fprop(o, angle, Vector3(0, 0.88, 0.33), Vector3(0.6, 0.08, 0.04), c.mat(Color(0.7, 0.2, 0.2), "", 0.5))
		"barber_chair":
			var leather: StandardMaterial3D = c.mat(Color(0.5, 0.1, 0.1), "", 0.5)
			c.fbox(o, angle, Vector3(0, 0.25, 0), Vector3(0.5, 0.5, 0.5), c.m_metal)
			c.fbox(o, angle, Vector3(0, 0.55, 0.05), Vector3(0.72, 0.16, 0.7), leather)
			c.fbox(o, angle, Vector3(0, 0.95, -0.3), Vector3(0.7, 0.8, 0.14), leather)
			c.fbox(o, angle, Vector3(0, 0.2, 0.4), Vector3(0.5, 0.08, 0.3), c.m_metal)
			c.fcollide(o, angle, Vector3(0, 0.55, 0), Vector3(0.8, 1.1, 0.9))
			c.fprop(o, angle, Vector3(0, 1.35, -0.3), Vector3(0.3, 0.14, 0.1), leather)
		"bin":
			c.fbox(o, angle, Vector3(0, 0.4, 0), Vector3(dims.x, 0.8, dims.y), wood)
			c.fcollide(o, angle, Vector3(0, 0.4, 0), Vector3(dims.x, 0.8, dims.y))
			for i: int in range(int(dims.x / 0.12)):
				c.fprop(o, angle, Vector3(-dims.x * 0.5 + 0.1 + i * 0.12, 0.9, 0.05 * ((i % 3) - 1)), Vector3(0.09, 0.3, 0.3), c.mat(goods[i % goods.size()], "", 0.7))
		"rack":
			c.fbox(o, angle, Vector3(0, 1.6, 0), Vector3(dims.x, 0.04, 0.04), c.m_metal)
			for end: float in [-1.0, 1.0]:
				c.fbox(o, angle, Vector3(end * (dims.x * 0.5 - 0.03), 0.8, 0), Vector3(0.04, 1.6, 0.4), c.m_metal)
			c.fcollide(o, angle, Vector3(0, 0.85, 0), Vector3(dims.x, 1.7, 0.5))
			for i: int in range(int(dims.x / 0.16)):
				c.fprop(o, angle, Vector3(-dims.x * 0.5 + 0.12 + i * 0.16, 1.1, 0), Vector3(0.05, 1.0, 0.4), c.mat(goods[(i * 5) % goods.size()].darkened(0.2), "", 0.9))
		"bench":
			c.fbox(o, angle, Vector3(0, 0.45, 0), Vector3(dims.x, 0.06, 0.45), wood)
			for end: float in [-1.0, 1.0]:
				c.fbox(o, angle, Vector3(end * (dims.x * 0.5 - 0.06), 0.22, 0), Vector3(0.06, 0.44, 0.4), wood)
			c.fcollide(o, angle, Vector3(0, 0.25, 0), Vector3(dims.x, 0.5, 0.45))
		"desk":
			c.fbox(o, angle, Vector3(0, 0.74, 0), Vector3(1.5, 0.05, 0.75), wood)
			for end: float in [-1.0, 1.0]:
				c.fbox(o, angle, Vector3(end * 0.65, 0.36, 0), Vector3(0.14, 0.72, 0.65), c.m_metal)
			c.fcollide(o, angle, Vector3(0, 0.4, 0), Vector3(1.5, 0.8, 0.75))
			var beige: StandardMaterial3D = c.mat(Color(0.78, 0.75, 0.66), "", 0.7)
			c.fprop(o, angle, Vector3(0.35, 0.96, -0.1), Vector3(0.4, 0.36, 0.38), beige)
			c.fprop(o, angle, Vector3(0.35, 0.97, 0.1), Vector3(0.32, 0.25, 0.02), c.glow(Color(0.25, 0.45, 0.6), 0.6))
			c.fprop(o, angle, Vector3(-0.3, 0.78, 0.05), Vector3(0.3, 0.03, 0.4), c.mat(Color(0.95, 0.94, 0.88), "", 0.9))
			c.fprop(o, angle, Vector3(0, 0.45, 0.7), Vector3(0.45, 0.06, 0.45), c.m_dark)
			c.fprop(o, angle, Vector3(0, 0.8, 0.9), Vector3(0.45, 0.6, 0.06), c.m_dark)
		"cabinet":
			c.fbox(o, angle, Vector3(0, 0.65, 0), Vector3(0.5, 1.3, 0.6), c.mat(Color(0.5, 0.52, 0.5), "metal", 0.5))
			c.fcollide(o, angle, Vector3(0, 0.65, 0), Vector3(0.5, 1.3, 0.6))
			for drawer: int in range(3):
				c.fprop(o, angle, Vector3(0, 0.35 + drawer * 0.4, 0.31), Vector3(0.3, 0.04, 0.02), c.m_dark)
		"forklift":
			var yellow: StandardMaterial3D = c.mat(Color(0.85, 0.65, 0.1), "", 0.5)
			c.fbox(o, angle, Vector3(0, 0.55, -0.3), Vector3(1.0, 0.7, 1.4), yellow)
			c.fbox(o, angle, Vector3(0, 0.6, -1.05), Vector3(1.0, 0.8, 0.5), c.m_dark)
			c.fbox(o, angle, Vector3(0, 0.95, 0.15), Vector3(0.7, 0.16, 0.7), c.m_dark)
			for post: Vector2 in [Vector2(-0.45, -0.2), Vector2(0.45, -0.2), Vector2(-0.45, 0.4), Vector2(0.45, 0.4)]:
				c.fbox(o, angle, Vector3(post.x, 1.5, post.y), Vector3(0.05, 1.1, 0.05), c.m_dark)
			c.fbox(o, angle, Vector3(0, 2.05, 0.1), Vector3(1.0, 0.05, 0.7), c.m_dark)
			for mast: float in [-0.35, 0.35]:
				c.fbox(o, angle, Vector3(mast, 1.1, 0.75), Vector3(0.08, 2.2, 0.08), c.m_metal)
				c.fbox(o, angle, Vector3(mast, 0.08, 1.15), Vector3(0.12, 0.05, 0.9), c.m_metal)
			c.fcollide(o, angle, Vector3(0, 1.05, -0.05), Vector3(1.2, 2.1, 2.5))
		"pallet_rack":
			var steel: StandardMaterial3D = c.mat(Color(0.2, 0.3, 0.55), "metal", 0.5)
			var orange: StandardMaterial3D = c.mat(Color(0.85, 0.45, 0.1), "metal", 0.5)
			var height: float = 3.0
			var bays: int = maxi(1, int(dims.x / 2.0))
			for post: int in range(bays + 1):
				for zed: float in [-1.0, 1.0]:
					c.fbox(o, angle, Vector3(-dims.x * 0.5 + post * dims.x / bays, height * 0.5, zed * (dims.y * 0.5 - 0.06)), Vector3(0.1, height, 0.1), steel)
			for level: int in range(3):
				c.fbox(o, angle, Vector3(0, 0.6 + level * 1.15, 0.3), Vector3(dims.x, 0.12, 0.08), orange)
				c.fbox(o, angle, Vector3(0, 0.6 + level * 1.15, -0.3), Vector3(dims.x, 0.12, 0.08), orange)
			c.fcollide(o, angle, Vector3(0, height * 0.5, 0), Vector3(dims.x, height, dims.y))
			for level: int in range(3):
				for bay: int in range(bays):
					if (bay + level + int(o.z)) % 4 == 0:
						continue
					var mat: StandardMaterial3D = c.mat(goods[(bay * 3 + level) % goods.size()].darkened(0.15), "", 0.8)
					c.fprop(o, angle, Vector3(-dims.x * 0.5 + (bay + 0.5) * dims.x / bays, 0.68 + level * 1.15 + 0.4, 0), Vector3(1.4, 0.7, 0.6), mat)
					c.fprop(o, angle, Vector3(-dims.x * 0.5 + (bay + 0.5) * dims.x / bays, 0.68 + level * 1.15 + 0.03, 0), Vector3(1.5, 0.08, 0.7), wood)


# --- ROW SHOP: a narrow shop with a separate street door and stair to a walk-up flat ------------------

const TRADES: Array[String] = ["barber", "tailor", "tv_repair", "records", "laundromat", "laundromat"]
const STORE_TRADES: Array[String] = ["deli", "pharmacy", "market", "liquor", "pawn", "market"]


static func _row_shop(c: Ctx) -> void:
	var hx: float = c.hx
	var hz: float = c.hz
	var z_back: float = -hz + WALL_T
	var z_front: float = hz - WALL_T
	var two: bool = c.floors >= 2
	var hall_w: float = 1.5
	var x_h0: float = -hx + WALL_T
	var x_p: float = x_h0 + hall_w + PART_T * 0.5
	var xs0: float = x_p + PART_T * 0.5 if two else x_h0
	var xs1: float = hx - WALL_T
	var door_w: float = 1.5
	var sd_x: float = xs0 + 0.2 + door_w * 0.5 + 0.35
	var x_hc: float = x_h0 + hall_w * 0.5
	var back_x: float = sd_x
	var z_s: float = z_front - 1.7
	var z_e: float = z_s - 19 * Kit.STEP_RUN
	var store: bool = c.kind == "corner_store"
	var trades: Array[String] = STORE_TRADES if store else TRADES
	var trade: String = trades[c.sign_index % trades.size()] if c.sign_index >= 0 else trades[c.rng.randi() % trades.size()]
	# --- exterior ---
	var front: Array = [Kit.opening(sd_x, door_w, 0.0, DOOR_H, "door")]
	var win0: float = sd_x + door_w * 0.5 + 0.35
	var win1: float = xs1 - 0.35
	var panes: int = maxi(1, ceili((win1 - win0) / 3.2))
	var pane_w: float = ((win1 - win0) - (panes - 1) * 0.2) / panes
	for p: int in range(panes):
		front.append(Kit.opening(win0 + pane_w * 0.5 + p * (pane_w + 0.2), pane_w, 0.5, 2.7, "window"))
	if two:
		front.append(Kit.opening(x_hc, 1.2, 0.0, DOOR_H, "door"))
	c.walls(front, [Kit.opening(back_x, 1.4, 0.0, DOOR_H, "door")])
	c.roof_slab()
	var avoid_front: Array = [Vector2(-hx, x_p)] if two else []
	c.windows_on("front", range(1, c.floors), 2.6, avoid_front)
	c.windows_on("back", range(c.floors), 3.2, [Vector2(back_x - 1.0, back_x + 1.0)])
	c.windows_on("right", range(c.floors), 3.4)
	if two:
		c.windows_on("left", [1], 3.6)
	c.door(Vector3(sd_x, c.f0, hz - WALL_T * 0.5), door_w, DOOR_H, Vector3.BACK, c.sign_text + " entrance")
	c.door(Vector3(back_x, c.f0, -hz + WALL_T * 0.5), 1.4, DOOR_H, Vector3.FORWARD, c.sign_text + " alley door")
	if two:
		c.door(Vector3(x_hc, c.f0, hz - WALL_T * 0.5), 1.2, DOOR_H, Vector3.BACK, c.sign_text + " upstairs entrance")
	var shop_mid: float = (xs0 + xs1) * 0.5
	c.awning(shop_mid, c.f0 + 2.85, xs1 - xs0 + 0.2, 1.2)
	c.fascia(shop_mid, c.f0 + 3.5, minf(xs1 - xs0, 6.4 if store else 4.6), 0.6, 34 if store else 30)
	if trade == "barber":
		c.kit.box(Vector3(xs1 - 0.2, c.f0 + 1.2, hz + 0.25), Vector3(0.18, 0.7, 0.18), c.mat(Color(0.9, 0.9, 0.9), "", 0.4))
		c.kit.box(Vector3(xs1 - 0.2, c.f0 + 1.2, hz + 0.25), Vector3(0.2, 0.16, 0.2), c.mat(Color(0.75, 0.1, 0.1), "", 0.4))
		c.kit.box(Vector3(xs1 - 0.2, c.f0 + 1.45, hz + 0.25), Vector3(0.2, 0.16, 0.2), c.mat(Color(0.15, 0.2, 0.6), "", 0.4))
	# --- interior ---
	c.to_interior()
	c.m_floor = c.mat(Color(0.62, 0.58, 0.5), "tiles", 0.9)
	c.slab(0)
	var hole: Array = [Rect2(x_h0, z_e, hall_w, z_s - z_e)] if two else []
	if two:
		c.slab(1, hole)
	c.roof_ceiling()
	var z_bk: float = z_back + 4.2
	# The stair hall: partition down the whole depth, the flight, an end wall.
	if two:
		c.partz(0, z_back, z_front, x_p)
		var steel: StandardMaterial3D = c.mat(Color(0.34, 0.3, 0.26), "planks", 0.8)
		var flight: Dictionary = c.kit.stairs_straight(Vector3(x_hc, c.f0, z_s), Vector3.FORWARD, FH, 1.2, steel)
		var top: Vector3 = flight["top"]
		c.stairs.append({"from": 0, "to": 1, "bottom": Vector3(x_hc, c.f0, z_s), "top": top, "kind": "straight"})
		var z_a: float = z_e - 1.4
		c.partz(1, z_back, z_front, x_p, [c.gap(z_a, 1.1, DOOR_H)])
		c.door(Vector3(x_p, c.fy(1), z_a), 1.1, DOOR_H, Vector3.LEFT, c.sign_text + " flat 1", "door", true, null, PART_T)
		c.routes["stair"] = [Vector3(x_hc, c.f0, z_s + 1.0), Vector3(x_hc, c.f0, z_s), Vector3(x_hc, top.y, top.z), Vector3(x_hc, top.y, top.z - 1.2)]
		c.reserve(0, Rect2(x_h0, z_e - 0.2, hall_w, z_s - z_e + 1.6))
		c.reserve(1, Rect2(x_h0, z_e - 3.0, hall_w, 3.0))
		var flat: Rect2 = Rect2(xs0, z_back, xs1 - xs0, z_front - z_back)
		_flat(c, 1, flat, xs0, z_a)
		c.lamp(Vector3(x_hc, c.fy(1) + 2.6, z_e - 1.0), 1.6, 9.0)
	# Shop floor, back room, the doorway between them.
	c.partx(0, xs0, xs1, z_bk, [c.gap(back_x, 1.2, DOOR_H)])
	c.reserve(0, Rect2(sd_x - 0.8, z_back, 1.6, D_of(c)))
	var shop: Rect2 = Rect2(xs0, z_bk + 0.08, xs1 - xs0, z_front - z_bk - 0.08)
	if store:
		_store_fixtures(c, trade, shop, sd_x + 0.8)
	else:
		_trade_fixtures(c, trade, shop)
	var back_room: Rect2 = Rect2(xs0, z_back, xs1 - xs0, z_bk - z_back - 0.08)
	_put_any(c, 0, back_room, "shelf", [["w", 0.3], ["e", 0.3]], 1.8)
	_put_any(c, 0, back_room, "shelf", [["e", 0.3], ["w", 2.4]], 1.8)
	_put_any(c, 0, back_room, "crate", [["e", 0.2], ["e", 1.2], ["w", 0.2]])
	_put_any(c, 0, back_room, "crate", [["e", 2.2], ["w", 1.2], ["w", 0.2]])
	_put_any(c, 0, back_room, "sink", [["n", 0.2], ["n", 2.0]])
	c.lamp(Vector3(shop_mid, c.f0 + 2.7, (z_front + z_bk) * 0.5), 2.2, 11.0)
	c.routes["shop_to_alley"] = [Vector3(sd_x, c.f0, z_front - 0.8), Vector3(sd_x, c.f0, z_bk + 0.8), Vector3(back_x, c.f0, z_bk - 0.8), Vector3(back_x, c.f0, z_back + 0.8)]
	c.to_shell()
	_roof_details(c)


static func D_of(c: Ctx) -> float:
	return c.D - WALL_T * 2.0


## The shop's fixtures for a trade, placed against the shop's walls so a lane stays open from the door to the back.
static func _trade_fixtures(c: Ctx, trade: String, shop: Rect2) -> void:
	var steel: StandardMaterial3D = c.m_metal
	match trade:
		"barber":
			_put_any(c, 0, shop, "counter", [["e", 0.3]], 1.8)
			_put_any(c, 0, shop, "barber_chair", [["e", 2.4]])
			_put_any(c, 0, shop, "barber_chair", [["e", 3.9]])
			_put_any(c, 0, shop, "bench", [["e", 5.6], ["e", 5.2]], 1.6)
			c.deco(Vector3(shop.end.x - 0.03, c.f0 + 1.5, shop.position.y + 3.9), Vector3(0.03, 1.1, 3.6), c.mat(Color(0.6, 0.66, 0.7), "", 0.05))
		"tailor":
			_put_any(c, 0, shop, "counter", [["e", 0.3]], 2.0)
			_put_any(c, 0, shop, "rack", [["e", 2.6]], 1.6)
			_put_any(c, 0, shop, "rack", [["e", 4.4]], 1.6)
			_put_any(c, 0, shop, "rack", [["e", 6.2]], 1.6)
		"tv_repair":
			_put_any(c, 0, shop, "counter", [["e", 0.3]], 2.0)
			_put_any(c, 0, shop, "shelf", [["e", 2.6]], 1.6)
			_put_any(c, 0, shop, "shelf", [["e", 4.4]], 1.6)
			_put_any(c, 0, shop, "bench", [["e", 6.4], ["e", 6.0]], 1.6)
			for stack: int in range(6):
				var at: Vector3 = Vector3(shop.end.x - 0.6, c.f0 + 0.2 + (stack % 3) * 0.42, shop.position.y + 6.5 + (stack / 3) * 0.0 + 0.0)
				c.deco(at + Vector3(0, 0.6, 0), Vector3(0.5, 0.38, 0.45), c.mat(Color(0.2, 0.2, 0.22), "", 0.6), 0.0)
				break
		"records":
			_put_any(c, 0, shop, "counter", [["e", 0.3]], 1.6)
			_put_any(c, 0, shop, "bin", [["e", 2.1]], 1.6)
			_put_any(c, 0, shop, "bin", [["e", 3.9]], 1.6)
			_put_any(c, 0, shop, "bin", [["e", 5.7]], 1.6)
		_:
			for i: int in range(4):
				_put_any(c, 0, shop, "washer", [["e", 0.3 + i * 0.85]])
			_put_any(c, 0, shop, "counter", [["e", 4.0]], 1.6)
			_put_any(c, 0, shop, "bench", [["e", 6.0], ["e", 5.6]], 1.5)
	# The light box sign hung inside the window.
	c.deco(Vector3(shop.get_center().x, c.f0 + 2.4, shop.end.y - 0.4), Vector3(1.2, 0.35, 0.05), c.glow(Color(1.0, 0.4, 0.3), 0.9))


# --- WAREHOUSE: a big open hall with racks, a forklift, a roll-up door and a raised office ------------

static func _warehouse(c: Ctx) -> void:
	var hx: float = c.hx
	var hz: float = c.hz
	c.roof_y = c.f0 + 6.9 + (c.floors - 1) * 0.9
	var z_back: float = -hz + WALL_T
	var z_front: float = hz - WALL_T
	var x_left: float = -hx + WALL_T
	var x_right: float = hx - WALL_T
	var pd_x: float = -hx * 0.55
	var roll_x: float = hx * 0.3
	var side_z: float = -hz * 0.25
	var back_x: float = hx * 0.35
	c.walls([Kit.opening(pd_x, 1.5, 0.0, DOOR_H, "door"), Kit.opening(roll_x, 4.2, 0.0, 4.0, "door")],
		[Kit.opening(back_x, 1.5, 0.0, DOOR_H, "door")], [], [Kit.opening(side_z, 1.5, 0.0, DOOR_H, "door")])
	c.roof_slab()
	c.windows_on("front", [0], 4.0, [Vector2(pd_x - 1.0, pd_x + 1.0), Vector2(roll_x - 2.4, roll_x + 2.4)], 1.8, 0.9, 4.4)
	c.windows_on("left", [0], 4.0, [], 1.8, 0.9, 4.4)
	c.windows_on("right", [0], 4.0, [Vector2(side_z - 1.0, side_z + 1.0)], 1.8, 0.9, 4.4)
	c.windows_on("back", [0], 4.0, [Vector2(back_x - 1.0, back_x + 1.0)], 1.8, 0.9, 4.4)
	c.door(Vector3(pd_x, c.f0, hz - WALL_T * 0.5), 1.5, DOOR_H, Vector3.BACK, c.sign_text + " entrance")
	c.roller(Vector3(roll_x, c.f0, hz - WALL_T * 0.5), 4.2, 4.0, Vector3.BACK, c.sign_text + " loading door")
	c.door(Vector3(back_x, c.f0, -hz + WALL_T * 0.5), 1.5, DOOR_H, Vector3.FORWARD, c.sign_text + " back door")
	c.door(Vector3(hx - WALL_T * 0.5, c.f0, side_z), 1.5, DOOR_H, Vector3.RIGHT, c.sign_text + " side door")
	# A steel-frame lintel sign and a loading-bay bumper strip.
	c.fascia(pd_x, c.f0 + 3.1, 4.4, 0.6, 30)
	c.kit.box(Vector3(roll_x, c.f0 + 4.25, hz + 0.1), Vector3(4.8, 0.3, 0.2), c.m_metal)
	c.kit.box(Vector3(roll_x, c.f0 + 0.2, hz + 0.2), Vector3(5.0, 0.4, 0.3), c.mat(Color(0.15, 0.15, 0.16), "", 0.8))
	c.to_interior()
	c.m_floor = c.mat(Color(0.5, 0.5, 0.48), "panel", 0.95)
	c.slab(0)
	# The mezzanine office in the back-left corner, reached by a straight flight along the left wall.
	var mezz_w: float = 7.5
	var mezz_d: float = 6.4
	var z_m: float = z_back + mezz_d
	var x_mz1: float = x_left + mezz_w
	var x_st: float = x_left + 0.9
	var z_s: float = z_m + 19 * Kit.STEP_RUN
	var y1: float = c.fy(1)
	c.extra_floors.append(y1)
	c.kit.floor_slab(Rect2(x_left, z_back, mezz_w, mezz_d), y1, c.m_floor)
	var steel: StandardMaterial3D = c.mat(Color(0.3, 0.32, 0.34), "metal", 0.6)
	var flight: Dictionary = c.kit.stairs_straight(Vector3(x_st, c.f0, z_s), Vector3.FORWARD, FH, 1.2, steel)
	var top: Vector3 = flight["top"]
	c.stairs.append({"from": 0, "to": 1, "bottom": Vector3(x_st, c.f0, z_s), "top": top, "kind": "straight"})
	c.routes["mezz"] = [Vector3(x_st, c.f0, z_s + 1.2), Vector3(x_st, c.f0, z_s), Vector3(x_st, top.y, top.z), Vector3(x_st, top.y, top.z - 1.0)]
	c.reserve(0, Rect2(x_left, z_m - 0.3, 1.8, z_s - z_m + 2.2))
	# Office walls: a front wall with the door at the stair and a fake window strip, a right wall.
	var z_o: float = z_m - 1.6
	c.partx(1, x_left, x_mz1, z_o, [c.gap(x_st, 1.2, DOOR_H)])
	c.partz(1, z_back, z_o, x_mz1)
	c.kit.box(Vector3((x_st + 0.6 + x_mz1) * 0.5, y1 + 1.6, z_o + 0.09), Vector3(x_mz1 - x_st - 1.0, 0.9, 0.03), c.m_pane_in)
	c.kit.box(Vector3(x_mz1 - 0.09, y1 + 1.6, (z_back + z_o) * 0.5), Vector3(0.03, 0.9, z_o - z_back - 1.0), c.m_pane_in)
	c.kit.railing(Vector3(x_st + 0.8, y1, z_m), Vector3(x_mz1, y1, z_m))
	c.kit.railing(Vector3(x_mz1, y1, z_m), Vector3(x_mz1, y1, z_o))
	c.reserve(1, Rect2(x_st - 0.8, z_o, 1.8, z_m - z_o + 0.2))
	c.door(Vector3(x_st, y1, z_o), 1.2, DOOR_H, Vector3.BACK, c.sign_text + " office", "door", true, null, PART_T)
	var office: Rect2 = Rect2(x_left, z_back, mezz_w - 0.1, z_o - z_back - 0.08)
	_put_any(c, 1, office, "desk", [["n", 1.0], ["n", 2.6]])
	_put_any(c, 1, office, "desk", [["n", 4.2], ["e", 0.8]])
	for i: int in range(3):
		_put_any(c, 1, office, "cabinet", [["w", 0.3 + i * 0.7], ["e", 3.0 + i * 0.7]])
	_put_any(c, 1, office, "bench", [["e", 0.5], ["s", 4.0]], 1.2)
	# The forklift parks beside the rack rows (placed first so the racks keep clear of it).
	var lift_rect: Rect2 = Rect2(x_right - 6.2, z_front - 9.4, 1.4, 2.7)
	if c.claim(0, lift_rect):
		_furn(c, 0, "forklift", Rect2(lift_rect.position.x + 0.1, lift_rect.position.y + 0.1, 1.2, 2.5), 0.3, Vector2(1.2, 2.5))
	# Racks in long rows with cross gaps, keeping the loading zone and both lanes free.
	var lane_left: float = x_left + 2.6
	var row_x: float = lane_left + 0.75
	var z_r0: float = z_back + 0.6
	var z_r1: float = z_front - 6.5
	c.reserve(0, Rect2(x_left, z_front - 6.5, x_right - x_left, 6.5 - 0.0))
	c.reserve(0, Rect2(x_right - 2.6, z_back, 2.6, z_front - z_back))
	var side_lane_z: float = side_z
	c.reserve(0, Rect2(x_right - 5.0, side_lane_z - 1.2, 5.0, 2.4))
	while row_x + 0.8 < x_right - 3.2:
		var z: float = z_r0
		while z + 3.0 < z_r1:
			var seg: float = minf(4.0, z_r1 - z)
			_pallet_pair(c, row_x, z + seg * 0.5, seg)
			z += seg + 1.6
		row_x += 4.6
	# The forklift and stacked crates in the loading zone.
	for i: int in range(5):
		var at: Vector2 = Vector2(x_left + 1.2 + i * 1.3, z_front - 1.2)
		var rect: Rect2 = Rect2(at.x - 0.5, at.y - 0.5, 1.0, 1.0)
		if rect.position.x < pd_x + 1.0 and rect.end.x > pd_x - 1.0:
			continue
		_furn(c, 0, "crate", rect, c.rng.randf() * 1.5, Vector2(0.9, 0.9))
	# Ceiling: steel purlins across the hall and a couple of hanging lamps (lights are two omni lamps).
	var beam: StandardMaterial3D = c.m_metal
	var lampglow: StandardMaterial3D = c.glow(Color(1.0, 0.95, 0.8), 0.9)
	var beam_y: float = c.roof_y - SLAB - 0.4
	var z_b: float = z_back + 2.0
	while z_b < z_front - 1.0:
		c.deco(Vector3(0, beam_y, z_b), Vector3(W_of(c), 0.3, 0.2), beam)
		c.deco(Vector3(-hx * 0.5, beam_y - 0.5, z_b + 2.0), Vector3(1.4, 0.06, 0.25), lampglow)
		c.deco(Vector3(hx * 0.5, beam_y - 0.5, z_b + 2.0), Vector3(1.4, 0.06, 0.25), lampglow)
		z_b += 4.0
	c.lamp(Vector3(0, c.f0 + 5.2, z_front - 5.0), 3.0, 20.0)
	c.lamp(Vector3(0, c.f0 + 5.2, z_back + 5.0), 3.0, 20.0)
	c.routes["hall"] = [Vector3(pd_x, c.f0, z_front - 0.8), Vector3(pd_x, c.f0, z_front - 3.0), Vector3(x_right - 1.3, c.f0, z_front - 3.0),
		Vector3(x_right - 1.3, c.f0, side_z), Vector3(x_right - 0.8, c.f0, side_z)]
	c.to_shell()
	_roof_details(c)


static func W_of(c: Ctx) -> float:
	return c.W - WALL_T * 2.0


## Two pallet racks back to back, `length` long, centred on (x, z).
static func _pallet_pair(c: Ctx, x: float, z: float, length: float) -> void:
	for side: float in [-1.0, 1.0]:
		var rect: Rect2 = Rect2(x + side * 0.4 - 0.375, z - length * 0.5, 0.75, length)
		if c.claim(0, rect):
			_furn(c, 0, "pallet_rack", rect, PI * 0.5 if side < 0.0 else -PI * 0.5, Vector2(length, 0.75))


# --- Even more furniture ---------------------------------------------------------------------------

static func _dims_more(kind: String, length: float) -> Vector2:
	match kind:
		"cooler":
			return Vector2(1.2, 0.7)
		"case":
			return Vector2(length if length > 0.0 else 1.6, 0.65)
		"cubicle":
			return Vector2(1.9, 1.8)
		"conf":
			return Vector2(3.0, 1.3)
		"pool":
			return Vector2(2.7, 1.5)
		"booth":
			return Vector2(2.3, 1.6)
		"stove":
			return Vector2(1.2, 0.8)
		"tires":
			return Vector2(0.8, 0.8)
		"drum":
			return Vector2(0.6, 0.6)
		"workbench":
			return Vector2(2.4, 0.75)
		"lectern":
			return Vector2(0.6, 0.5)
		"safe":
			return Vector2(0.7, 0.6)
	return Vector2(1.0, 1.0)


static func _furn_more(c: Ctx, kind: String, o: Vector3, angle: float, dims: Vector2) -> void:
	var wood: StandardMaterial3D = c.m_wood
	var pale: StandardMaterial3D = c.m_pale
	var black: StandardMaterial3D = c.mat(Color(0.12, 0.12, 0.13), "", 0.8)
	match kind:
		"cooler":
			c.fbox(o, angle, Vector3(0, 1.0, 0), Vector3(1.2, 2.0, 0.7), pale)
			c.fbox(o, angle, Vector3(0, 1.0, 0.36), Vector3(1.1, 1.8, 0.03), c.glow(Color(0.7, 0.85, 1.0), 0.5))
			c.fcollide(o, angle, Vector3(0, 1.0, 0), Vector3(1.2, 2.0, 0.7))
		"case":
			c.fbox(o, angle, Vector3(0, 0.42, 0), Vector3(dims.x, 0.85, dims.y - 0.05), wood)
			c.fbox(o, angle, Vector3(0, 1.0, 0), Vector3(dims.x - 0.1, 0.22, dims.y - 0.15), c.m_pane_in)
			c.fcollide(o, angle, Vector3(0, 0.55, 0), Vector3(dims.x, 1.1, dims.y))
			for i: int in range(int(dims.x / 0.4)):
				c.fprop(o, angle, Vector3(-dims.x * 0.5 + 0.25 + i * 0.4, 0.98, 0), Vector3(0.18, 0.1, 0.14), c.mat([Color(0.8, 0.7, 0.2), Color(0.7, 0.7, 0.72), Color(0.6, 0.3, 0.2)][i % 3], "", 0.3))
		"cubicle":
			var panel: StandardMaterial3D = c.mat(Color(0.5, 0.55, 0.6), "", 0.9)
			c.fbox(o, angle, Vector3(0, 0.7, -0.87), Vector3(1.9, 1.4, 0.06), panel)
			for side: float in [-1.0, 1.0]:
				c.fbox(o, angle, Vector3(side * 0.93, 0.7, 0.0), Vector3(0.06, 1.4, 1.74), panel)
				c.fcollide(o, angle, Vector3(side * 0.93, 0.7, 0.0), Vector3(0.06, 1.4, 1.74))
			c.fcollide(o, angle, Vector3(0, 0.7, -0.87), Vector3(1.9, 1.4, 0.06))
			c.fbox(o, angle, Vector3(0, 0.74, -0.55), Vector3(1.5, 0.05, 0.6), wood)
			c.fcollide(o, angle, Vector3(0, 0.4, -0.55), Vector3(1.5, 0.8, 0.6))
			var beige: StandardMaterial3D = c.mat(Color(0.78, 0.75, 0.66), "", 0.7)
			c.fprop(o, angle, Vector3(0.3, 0.96, -0.62), Vector3(0.4, 0.36, 0.38), beige)
			c.fprop(o, angle, Vector3(0.3, 0.97, -0.42), Vector3(0.32, 0.25, 0.02), c.glow(Color(0.25, 0.45, 0.6), 0.6))
			c.fprop(o, angle, Vector3(0, 0.45, -0.05), Vector3(0.45, 0.06, 0.45), black)
			c.fprop(o, angle, Vector3(0, 0.8, -0.28), Vector3(0.45, 0.6, 0.06), black)
		"conf":
			c.fbox(o, angle, Vector3(0, 0.75, 0), Vector3(3.0, 0.06, 1.2), wood)
			c.fbox(o, angle, Vector3(0, 0.37, 0), Vector3(2.4, 0.7, 0.3), wood)
			c.fcollide(o, angle, Vector3(0, 0.4, 0), Vector3(3.0, 0.8, 1.2))
			for i: int in range(3):
				for side: float in [-1.0, 1.0]:
					c.fprop(o, angle, Vector3(-1.0 + i * 1.0, 0.5, side * 0.85), Vector3(0.45, 0.06, 0.45), black)
					c.fprop(o, angle, Vector3(-1.0 + i * 1.0, 0.8, side * 1.05), Vector3(0.45, 0.6, 0.06), black)
		"pool":
			c.fbox(o, angle, Vector3(0, 0.4, 0), Vector3(2.7, 0.8, 1.5), wood)
			c.fbox(o, angle, Vector3(0, 0.82, 0), Vector3(2.3, 0.05, 1.1), c.mat(Color(0.15, 0.4, 0.25), "", 0.95))
			c.fcollide(o, angle, Vector3(0, 0.45, 0), Vector3(2.7, 0.9, 1.5))
			for i: int in range(5):
				c.fprop(o, angle, Vector3(0.5 + (i % 3) * 0.12, 0.88, (i / 3) * 0.14 - 0.07), Vector3(0.08, 0.08, 0.08), c.mat([Color(0.8, 0.2, 0.2), Color(0.95, 0.95, 0.9), Color(0.2, 0.3, 0.7)][i % 3], "", 0.3))
			c.fprop(o, angle, Vector3(0, 2.1, 0), Vector3(1.8, 0.12, 0.4), c.glow(Color(1.0, 0.9, 0.6), 0.9))
		"booth":
			var seat: StandardMaterial3D = c.m_fabric
			for side: float in [-1.0, 1.0]:
				c.fbox(o, angle, Vector3(side * 0.9, 0.22, 0), Vector3(0.5, 0.44, 1.5), seat)
				c.fbox(o, angle, Vector3(side * 1.12, 0.7, 0), Vector3(0.1, 0.55, 1.5), seat)
			c.fbox(o, angle, Vector3(0, 0.74, 0), Vector3(0.9, 0.05, 0.9), wood)
			c.fbox(o, angle, Vector3(0, 0.37, 0), Vector3(0.14, 0.7, 0.14), c.m_metal)
			c.fcollide(o, angle, Vector3(0, 0.45, 0), Vector3(2.3, 0.9, 1.6))
			c.fprop(o, angle, Vector3(0.1, 0.78, 0.1), Vector3(0.1, 0.12, 0.1), pale)
		"stove":
			c.fbox(o, angle, Vector3(0, 0.45, 0), Vector3(1.2, 0.9, 0.8), c.m_ac)
			c.fcollide(o, angle, Vector3(0, 0.45, 0), Vector3(1.2, 0.9, 0.8))
			for i: int in range(4):
				c.fprop(o, angle, Vector3(-0.35 + (i % 2) * 0.7, 0.93, -0.15 + (i / 2) * 0.35), Vector3(0.28, 0.03, 0.28), black)
		"tires":
			for i: int in range(3):
				c.fbox(o, angle, Vector3(0, 0.11 + i * 0.22, 0), Vector3(0.7, 0.22, 0.7), black)
			c.fcollide(o, angle, Vector3(0, 0.33, 0), Vector3(0.7, 0.66, 0.7))
		"drum":
			c.cyl(o + Vector3(0, 0.45, 0), 0.29, 0.9, c.mat(Color(0.2, 0.3, 0.55), "", 0.5), 8)
			c.fcollide(o, angle, Vector3(0, 0.45, 0), Vector3(0.6, 0.9, 0.6))
		"workbench":
			c.fbox(o, angle, Vector3(0, 0.9, 0), Vector3(2.4, 0.06, 0.75), wood)
			for end: float in [-1.0, 1.0]:
				c.fbox(o, angle, Vector3(end * 1.1, 0.44, 0), Vector3(0.1, 0.88, 0.65), c.m_metal)
			c.fbox(o, angle, Vector3(0, 0.2, 0), Vector3(2.2, 0.06, 0.6), c.m_metal)
			c.fcollide(o, angle, Vector3(0, 0.47, 0), Vector3(2.4, 0.94, 0.75))
			c.fprop(o, angle, Vector3(-0.8, 1.0, 0.1), Vector3(0.18, 0.14, 0.12), c.m_metal)
		"lectern":
			c.fbox(o, angle, Vector3(0, 0.55, 0), Vector3(0.6, 1.1, 0.5), wood)
			c.fcollide(o, angle, Vector3(0, 0.55, 0), Vector3(0.6, 1.1, 0.5))
		"safe":
			c.fbox(o, angle, Vector3(0, 0.5, 0), Vector3(0.7, 1.0, 0.6), c.m_dark)
			c.fcollide(o, angle, Vector3(0, 0.5, 0), Vector3(0.7, 1.0, 0.6))
			c.fprop(o, angle, Vector3(0, 0.6, 0.31), Vector3(0.2, 0.2, 0.03), c.mat(Color(0.75, 0.62, 0.3), "", 0.3))


## Two shelves back to back running along z: a shop gondola. `x` is the centre line.
static func _gondola(c: Ctx, x: float, z0: float, length: float) -> bool:
	var a: Rect2 = Rect2(x - 0.45, z0, 0.45, length)
	var b: Rect2 = Rect2(x, z0, 0.45, length)
	if not c.claim(0, a):
		return false
	if not c.claim(0, b):
		return false
	_furn(c, 0, "shelf", a, -PI * 0.5, Vector2(length, 0.45))
	_furn(c, 0, "shelf", b, PI * 0.5, Vector2(length, 0.45))
	return true


static func _gondolas(c: Ctx, shop: Rect2, count: int) -> void:
	var placed: int = 0
	var gx: float = shop.position.x + 2.6
	while gx < shop.end.x - 1.7 and placed < count:
		var gz: float = shop.position.y + 1.6
		while gz + 2.2 < shop.end.y - 1.0 and placed < count:
			if _gondola(c, gx, gz, 2.2):
				placed += 1
			gz += 3.4
		gx += 1.9


## Shop fixtures for the corner stores.
static func _store_fixtures(c: Ctx, trade: String, shop: Rect2, aisle_end_x: float) -> void:
	var counter_at: float = aisle_end_x - shop.position.x + 0.1
	match trade:
		"deli":
			_put_any(c, 0, shop, "counter", [["n", counter_at]], 2.6)
			for i: int in range(3):
				_put_any(c, 0, shop, "cooler", [["e", 0.3 + i * 1.3]])
			_gondolas(c, shop, 2)
		"pharmacy":
			_put_any(c, 0, shop, "counter", [["n", counter_at]], 3.0)
			_put_any(c, 0, shop, "cooler", [["e", 0.3]])
			_gondolas(c, shop, 4)
		"liquor":
			_put_any(c, 0, shop, "counter", [["n", counter_at]], 2.0)
			for i: int in range(4):
				_put_any(c, 0, shop, "cooler", [["e", 0.3 + i * 1.3]])
			_gondolas(c, shop, 2)
		"pawn":
			_put_any(c, 0, shop, "counter", [["n", counter_at]], 2.6)
			for i: int in range(3):
				_put_any(c, 0, shop, "case", [["e", 0.3 + i * 1.9]], 1.6)
			_put_any(c, 0, shop, "case", [["w", 2.6], ["w", 4.0]], 1.6)
			_put_any(c, 0, shop, "shelf", [["n", counter_at + 3.0]], 1.8)
			for g: int in range(4):
				c.deco(Vector3(shop.end.x - 0.05 - g * 0.0, c.f0 + 1.9, shop.position.y + 1.0 + g * 1.5), Vector3(0.1, 0.9, 0.35), c.mat(Color(0.6, 0.35, 0.15), "planks", 0.6))
		_:
			_put_any(c, 0, shop, "counter", [["n", counter_at]], 1.8)
			for i: int in range(3):
				_put_any(c, 0, shop, "cooler", [["e", 0.3 + i * 1.3]])
			_gondolas(c, shop, 4)
	c.deco(Vector3(shop.get_center().x, c.f0 + 2.4, shop.end.y - 0.4), Vector3(1.2, 0.35, 0.05), c.glow(Color(1.0, 0.4, 0.3), 0.9))


# --- OFFICE: the walkup's core with cubicle floors -------------------------------------------------

## Fills the two rooms of an office side: open-plan cubicles (a waiting room and records on the ground floor) and a
## boss office (right) or conference room (left).
static func _office_fill(c: Ctx, s: int, living: Rect2, other: Rect2, min_edge: bool, back_entry: bool) -> void:
	var far_wall: String = "e" if min_edge else "w"
	if s == 0:
		for i: int in range(4):
			_put_any(c, s, living, "bench", [[far_wall, 0.3 + i * 2.2]], 1.6)
		_put_any(c, s, living, "cabinet", [["n", 0.2], ["s", 0.2]])
		for i: int in range(3):
			_put_any(c, s, other, "shelf", [[far_wall, 0.3 + i * 2.0]], 1.8)
		_put_any(c, s, other, "desk", [["n" if not back_entry else "s", 1.0]])
		return
	var z: float = 0.2
	while z + 1.9 <= living.size.y:
		_put(c, s, living, "cubicle", far_wall, z)
		z += 2.0
	if living.size.x >= 7.4:
		z = living.position.y + 0.3
		while z + 1.9 <= living.end.y:
			var x0: float = living.position.x + 3.7 if far_wall == "w" else living.end.x - 3.7 - 1.8
			var rect: Rect2 = Rect2(x0, z, 1.8, 1.9)
			if living.encloses(rect) and c.claim(s, rect):
				_furn(c, s, "cubicle", rect, PI * 0.5 if far_wall == "w" else -PI * 0.5, Vector2(1.9, 1.8))
			z += 2.0
	var far_z: String = "s" if back_entry else "n"
	if min_edge:
		_put_any(c, s, other, "desk", [[far_z, 0.8], [far_z, 2.0]])
		_put_any(c, s, other, "sofa", [["e", 0.5], ["w", 0.5]])
		_put_any(c, s, other, "cabinet", [[far_z, 0.1], [far_z, other.size.x - 0.7]])
		_put_any(c, s, other, "shelf", [["w", 0.3], ["e", 0.3]], 1.6)
	else:
		var mid: Rect2 = Rect2(other.get_center().x - 1.5, other.get_center().y - 0.65, 3.0, 1.3)
		if other.encloses(mid) and c.claim(s, mid):
			_furn(c, s, "conf", mid, 0.0, Vector2(3.0, 1.3))
		_put_any(c, s, other, "cabinet", [[far_z, 0.1], [far_z, other.size.x - 0.7]])


## The office lobby's reception desk (in place of mail boxes' company).
static func _reception(c: Ctx, door_z: float) -> void:
	var rect: Rect2 = Rect2(-CORE_HALF + 0.35, door_z + 2.2, 0.65, 2.4)
	if rect.end.y < c.hz - WALL_T - 1.5 and c.claim(0, rect):
		_furn(c, 0, "counter", rect, PI * 0.5, Vector2(2.4, 0.65))


# --- BAR: a bar or pool hall with booths, a back office, restrooms and an alley door -----------------

static func _bar(c: Ctx) -> void:
	var hx: float = c.hx
	var hz: float = c.hz
	var z_back: float = -hz + WALL_T
	var z_front: float = hz - WALL_T
	var x_left: float = -hx + WALL_T
	var x_right: float = hx - WALL_T
	var z_bk: float = z_back + 4.4
	c.walls([Kit.opening(0.0, 1.6, 0.0, DOOR_H, "door"), Kit.opening(-hx * 0.5, 2.0, 0.9, 2.5, "window")], [Kit.opening(0.0, 1.4, 0.0, DOOR_H, "door")])
	c.roof_slab()
	c.windows_on("right", [0], 4.5, [], 1.0, 0.7, 1.6)
	c.windows_on("left", [0], 4.5, [], 1.0, 0.7, 1.6)
	c.windows_on("back", [0], 4.5, [Vector2(-1.2, 1.2)], 1.0, 0.7, 1.6)
	c.windows_on("front", [0], 4.0, [Vector2(-1.4, 1.4), Vector2(-hx * 0.5 - 1.6, -hx * 0.5 + 1.6)], 1.0, 0.7, 1.6)
	c.door(Vector3(0, c.f0, hz - WALL_T * 0.5), 1.6, DOOR_H, Vector3.BACK, c.sign_text + " entrance")
	c.door(Vector3(0, c.f0, -hz + WALL_T * 0.5), 1.4, DOOR_H, Vector3.FORWARD, c.sign_text + " alley door")
	c.fascia(0.0, c.f0 + 3.3, minf(W_of(c), 7.0), 0.9, 40)
	c.kit.box(Vector3(hx * 0.5, c.f0 + 2.0, hz + 0.1), Vector3(1.4, 0.5, 0.1), c.glow(Color(1.0, 0.25, 0.2), 1.4))
	c.kit.box(Vector3(-hx * 0.5, c.f0 + 3.0, hz + 0.12), Vector3(1.0, 0.4, 0.08), c.glow(Color(0.3, 0.6, 1.0), 1.4))
	c.awning(0.0, c.f0 + 2.8, 2.4, 1.0)
	c.to_interior()
	c.m_floor = c.mat(Color(0.5, 0.42, 0.34), "planks", 0.85)
	c.slab(0)
	c.roof_ceiling()
	# Back of house: two restrooms, a corridor to the alley door and an office, each opening off the bar room.
	var hall: float = 0.9
	var wc_w: float = 2.3
	var x_wc2: float = -hall - PART_T
	var x_wc1: float = x_wc2 - wc_w - PART_T
	c.partz(0, z_back, z_bk, -hall - PART_T * 0.5)
	c.partz(0, z_back, z_bk, hall + PART_T * 0.5)
	c.partz(0, z_back, z_bk, x_wc1)
	var wc1: Rect2 = Rect2(x_left, z_back, x_wc1 - x_left, z_bk - z_back - 0.08)
	var wc2: Rect2 = Rect2(x_wc1 + PART_T * 0.5, z_back, x_wc2 - x_wc1 - PART_T, z_bk - z_back - 0.08)
	var office: Rect2 = Rect2(hall + PART_T, z_back, x_right - hall - PART_T, z_bk - z_back - 0.08)
	c.partx(0, x_left, x_right, z_bk, [c.gap((x_left + x_wc1) * 0.5, 0.9), c.gap((x_wc1 + x_wc2) * 0.5, 0.9), c.gap(0.0, 1.6, DOOR_H), c.gap((hall + x_right) * 0.5, 0.9)])
	for rect: Rect2 in [wc1, wc2]:
		_put_any(c, 0, rect, "toilet", [["n", 0.3]])
		_put_any(c, 0, rect, "sink", [["w", 1.2], ["e", 1.2]])
	_put_any(c, 0, office, "desk", [["n", 0.8]])
	_put_any(c, 0, office, "safe", [["e", 0.3]])
	_put_any(c, 0, office, "cabinet", [["w", 0.2], ["w", 1.0]])
	_put_any(c, 0, office, "shelf", [["e", 1.5]], 1.6)
	# The bar room.
	var main: Rect2 = Rect2(x_left, z_bk + PART_T * 0.5, x_right - x_left, z_front - z_bk - PART_T * 0.5)
	c.reserve(0, Rect2(-1.0, z_back, 2.0, D_of(c)))
	var length: float = minf(7.0, main.size.y - 3.4)
	var counter: Rect2 = Rect2(x_right - 2.0, main.position.y + 1.0, 0.65, length)
	if c.claim(0, counter):
		_furn(c, 0, "counter", counter, -PI * 0.5, Vector2(length, 0.65))
	_put(c, 0, main, "shelf", "e", 1.0, length)
	for i: int in range(int(length)):
		c.deco(Vector3(counter.position.x - 0.35, c.f0 + 0.38, counter.position.y + 0.6 + i * 1.0), Vector3(0.34, 0.7, 0.34), c.m_wood)
	for i: int in range(3):
		_put_any(c, 0, main, "booth", [["w", 0.4 + i * 2.5]])
	var pool_spots: Array = [Rect2(x_left + 2.6, z_bk + 1.2, 1.5, 2.7), Rect2(x_left + 2.6, z_bk + 4.2, 1.5, 2.7), Rect2(1.4, z_bk + 1.2, 1.5, 2.7)]
	var pool_at: Rect2 = c.fit(0, main, pool_spots)
	if pool_at.size.x > 0.0:
		_furn(c, 0, "pool", pool_at, PI * 0.5, Vector2(2.7, 1.5))
	c.deco(Vector3(x_left + 0.06, c.f0 + 2.2, main.get_center().y), Vector3(0.05, 0.5, 1.4), c.glow(Color(0.3, 0.7, 1.0), 1.0))
	c.deco(Vector3(x_right - 0.06, c.f0 + 2.6, main.get_center().y - 1.0), Vector3(0.05, 0.6, 1.2), c.glow(Color(1.0, 0.5, 0.2), 1.0))
	c.lamp(Vector3(0, c.f0 + 2.8, main.get_center().y), 2.2, 12.0)
	c.lamp(Vector3(0, c.f0 + 2.8, z_back + 2.0), 1.6, 8.0)
	c.routes["bar_to_alley"] = [Vector3(0, c.f0, z_front - 0.8), Vector3(0, c.f0, z_bk + 0.8), Vector3(0, c.f0, z_bk - 0.8), Vector3(0, c.f0, z_back + 0.8)]
	c.to_shell()
	_roof_details(c)


# --- AUTO SHOP: a service bay with a car on a lift, tool walls and an office ------------------------

static func _auto_shop(c: Ctx) -> void:
	var hx: float = c.hx
	var hz: float = c.hz
	c.roof_y = c.f0 + 5.2
	var z_back: float = -hz + WALL_T
	var z_front: float = hz - WALL_T
	var x_left: float = -hx + WALL_T
	var x_right: float = hx - WALL_T
	var bay_x: float = x_left + 3.4
	var off_w: float = 5.0
	var off_d: float = 4.6
	var cust_x: float = x_right - off_w * 0.5
	var lane_x: float = x_right - off_w - 1.4
	c.walls([Kit.opening(bay_x, 4.0, 0.0, 3.6, "door"), Kit.opening(cust_x, 1.4, 0.0, DOOR_H, "door"), Kit.opening(cust_x - 2.6, 1.6, 0.9, 2.5, "window")],
		[Kit.opening(lane_x, 1.5, 0.0, DOOR_H, "door")], [Kit.opening(z_back + 4.0, 1.4, 0.0, DOOR_H, "door")])
	c.roof_slab()
	c.windows_on("right", [0], 4.0, [], 1.6, 0.8, 3.6)
	c.windows_on("back", [0], 4.0, [Vector2(lane_x - 1.0, lane_x + 1.0)], 1.6, 0.8, 3.6)
	c.windows_on("left", [0], 4.0, [Vector2(-hz + 3.0, -hz + 5.0)], 1.6, 0.8, 3.6)
	c.roller(Vector3(bay_x, c.f0, hz - WALL_T * 0.5), 4.0, 3.6, Vector3.BACK, c.sign_text + " service bay")
	c.door(Vector3(cust_x, c.f0, hz - WALL_T * 0.5), 1.4, DOOR_H, Vector3.BACK, c.sign_text + " entrance")
	c.door(Vector3(lane_x, c.f0, -hz + WALL_T * 0.5), 1.5, DOOR_H, Vector3.FORWARD, c.sign_text + " alley door")
	c.door(Vector3(-hx + WALL_T * 0.5, c.f0, z_back + 4.0), 1.4, DOOR_H, Vector3.LEFT, c.sign_text + " side door")
	c.fascia(0.0, c.f0 + 4.3, minf(W_of(c) - 1.0, 8.0), 0.8, 40)
	c.kit.box(Vector3(bay_x, c.f0 + 3.75, hz + 0.08), Vector3(4.6, 0.3, 0.16), c.m_metal)
	c.to_interior()
	c.m_floor = c.mat(Color(0.42, 0.42, 0.4), "panel", 0.95)
	c.slab(0)
	c.roof_ceiling()
	# The office: two partitions, a doorway into the bay, counter, desk and chairs.
	var off: Rect2 = Rect2(x_right - off_w, z_front - off_d, off_w, off_d)
	c.partz(0, z_front - off_d, z_front, x_right - off_w, [c.gap(z_front - 2.2, 1.1, DOOR_H)])
	c.partx(0, x_right - off_w, x_right, z_front - off_d)
	c.reserve(0, Rect2(x_right - off_w - 1.4, z_front - 3.0, 2.8, 1.6))
	var office_room: Rect2 = Rect2(off.position.x + 0.08, off.position.y + 0.08, off.size.x - 0.08, off.size.y - 0.08)
	_put_any(c, 0, office_room, "counter", [["n", 0.3]], 2.4)
	_put_any(c, 0, office_room, "desk", [["e", 0.4], ["e", 2.0]])
	_put_any(c, 0, office_room, "cabinet", [["e", 3.4], ["w", 2.0]])
	_put_any(c, 0, office_room, "bench", [["w", 1.5], ["w", 0.6]], 1.6)
	c.deco(Vector3(off.position.x + 0.04, c.f0 + 1.9, off.position.y + 2.3), Vector3(0.04, 0.5, 1.6), c.glow(Color(1.0, 0.3, 0.2), 0.9))
	# The bay: a lift with a raised car, a parked car, the tool wall, benches, tyres and drums.
	var lift_z: float = z_front - 6.0
	var car_rect: Rect2 = Rect2(bay_x - 1.1, lift_z - 2.4, 2.2, 4.8)
	c.claim(0, Rect2(bay_x - 2.3, z_front - 3.2, 4.6, 2.4))
	if c.claim(0, car_rect):
		var body: StandardMaterial3D = c.m_accent
		c.kit.box(Vector3(bay_x, c.f0 + 2.45, lift_z), Vector3(1.9, 0.7, 4.3), body)
		c.kit.box(Vector3(bay_x, c.f0 + 3.0, lift_z + 0.2), Vector3(1.6, 0.5, 2.2), c.m_dark)
		c.kit.collider(Vector3(bay_x, c.f0 + 2.6, lift_z), Vector3(1.9, 1.2, 4.3))
		for side: float in [-1.0, 1.0]:
			for end: float in [-1.0, 1.0]:
				c.kit.box(Vector3(bay_x + side * 1.35, c.f0 + 1.3, lift_z + end * 1.4), Vector3(0.22, 2.6, 0.22), c.mat(Color(0.85, 0.65, 0.1), "", 0.5))
				c.kit.collider(Vector3(bay_x + side * 1.35, c.f0 + 1.3, lift_z + end * 1.4), Vector3(0.22, 2.6, 0.22))
		for side: float in [-1.0, 1.0]:
			c.kit.box(Vector3(bay_x + side * 0.9, c.f0 + 2.05, lift_z), Vector3(0.12, 0.1, 4.0), c.m_metal)
	var second: Rect2 = Rect2(bay_x + 3.4 - 1.0, z_front - 8.2, 2.0, 4.4)
	if second.end.x < off.position.x - 1.6 and c.claim(0, second):
		c.kit.box(Vector3(second.get_center().x, c.f0 + 0.65, second.get_center().y), Vector3(1.9, 0.7, 4.2), c.mat(Color(0.5, 0.5, 0.55), "", 0.4))
		c.kit.box(Vector3(second.get_center().x, c.f0 + 1.2, second.get_center().y), Vector3(1.6, 0.5, 2.2), c.m_dark)
		c.kit.collider(Vector3(second.get_center().x, c.f0 + 0.75, second.get_center().y), Vector3(1.9, 1.3, 4.2))
	c.reserve(0, Rect2(lane_x - 0.8, z_back, 1.6, D_of(c)))
	c.reserve(0, Rect2(-hx * 0.0 + x_left + 3.4 - 2.4, z_front - 3.0, off.position.x - x_left, 2.6))
	_put_any(c, 0, Rect2(x_left, z_back, lane_x - 0.9 - x_left, z_front - z_back - 4.0), "workbench", [["n", 0.4], ["n", 3.0]])
	c.deco(Vector3((x_left + lane_x) * 0.5, c.f0 + 1.9, z_back + 0.3), Vector3(minf(lane_x - x_left - 1.0, 6.0), 1.3, 0.04), c.mat(Color(0.6, 0.55, 0.3), "planks", 0.8))
	for i: int in range(10):
		c.deco(Vector3(x_left + 1.0 + i * 0.6, c.f0 + 1.8 + (i % 3) * 0.25, z_back + 0.36), Vector3(0.1, 0.32, 0.03), c.m_metal)
	var yard: Rect2 = Rect2(x_left, z_back, lane_x - 0.9 - x_left, z_front - z_back - 4.0)
	_put_any(c, 0, yard, "tires", [["w", 3.0], ["w", 4.0], ["w", 5.0]])
	_put_any(c, 0, yard, "tires", [["w", 6.0], ["w", 7.0]])
	_put_any(c, 0, yard, "drum", [["w", 8.0], ["w", 8.8], ["n", 6.4]])
	_put_any(c, 0, yard, "shelf", [["w", 9.0], ["w", 10.5]], 1.6)
	c.lamp(Vector3(0, c.f0 + 4.4, z_front - 5.0), 2.6, 15.0)
	c.lamp(Vector3(0, c.f0 + 4.4, z_back + 4.0), 2.6, 15.0)
	c.routes["bay_to_alley"] = [Vector3(cust_x, c.f0, z_front - 0.8), Vector3(cust_x, c.f0, z_front - 2.2), Vector3(x_right - off_w - 0.7, c.f0, z_front - 2.2), Vector3(lane_x, c.f0, z_front - 3.3), Vector3(lane_x, c.f0, z_back + 1.0)]
	c.to_shell()
	_roof_details(c)


# --- DINER: a small diner with booths, a counter with stools and a kitchen ----------------------------

static func _diner_small(c: Ctx) -> void:
	var hx: float = c.hx
	var hz: float = c.hz
	var z_back: float = -hz + WALL_T
	var z_front: float = hz - WALL_T
	var x_left: float = -hx + WALL_T
	var x_right: float = hx - WALL_T
	var door_x: float = x_right - 1.5
	var z_k: float = z_back + 3.6
	var win0: float = x_left + 0.6
	var win1: float = door_x - 1.3
	var front: Array = [Kit.opening(door_x, 1.5, 0.0, DOOR_H, "door")]
	var panes: int = maxi(1, ceili((win1 - win0) / 3.0))
	var pane_w: float = ((win1 - win0) - (panes - 1) * 0.2) / panes
	for p: int in range(panes):
		front.append(Kit.opening(win0 + pane_w * 0.5 + p * (pane_w + 0.2), pane_w, 0.6, 2.6, "window"))
	c.walls(front, [Kit.opening(door_x, 1.4, 0.0, DOOR_H, "door")])
	c.roof_slab()
	c.windows_on("left", [0], 3.6, [], 1.3, 1.2, 1.0)
	c.windows_on("right", [0], 3.6, [], 1.3, 1.2, 1.0)
	c.windows_on("back", [0], 4.0, [Vector2(door_x - 1.0, door_x + 1.0)], 1.3, 1.0, 1.2)
	c.door(Vector3(door_x, c.f0, hz - WALL_T * 0.5), 1.5, DOOR_H, Vector3.BACK, c.sign_text + " entrance")
	c.door(Vector3(door_x, c.f0, -hz + WALL_T * 0.5), 1.4, DOOR_H, Vector3.FORWARD, c.sign_text + " alley door")
	c.awning(-0.6, c.f0 + 2.9, W_of(c) - 3.0, 1.2)
	c.fascia(-0.6, c.f0 + 3.55, minf(W_of(c) - 3.2, 5.5), 0.6, 34)
	c.kit.box(Vector3(0, c.roof_y + PARAPET + 0.9, hz - 0.5), Vector3(minf(W_of(c) - 2.0, 5.0), 1.2, 0.2), c.m_accent)
	c.kit.box(Vector3(0, c.roof_y + PARAPET + 0.9, hz - 0.38), Vector3(minf(W_of(c) - 2.4, 4.6), 0.9, 0.06), c.glow(Color(1.0, 0.85, 0.4), 1.3))
	c.to_interior()
	c.m_floor = c.mat(Color(0.6, 0.58, 0.52), "tiles", 0.7)
	c.slab(0)
	c.roof_ceiling()
	var counter_x0: float = x_left + 0.6
	var counter_len: float = door_x - 1.4 - counter_x0 - 0.2
	# The kitchen wall: a doorway at the lane and a pass-through behind the counter.
	c.partx(0, x_left, x_right, z_k, [c.gap(door_x, 1.2, DOOR_H), Kit.opening(counter_x0 + counter_len * 0.5, minf(counter_len - 0.6, 3.0), 1.0, 2.2, "gap")])
	var kitchen: Rect2 = Rect2(x_left, z_back, x_right - x_left, z_k - z_back - 0.08)
	c.reserve(0, Rect2(door_x - 0.8, z_back, 1.6, D_of(c)))
	_put_any(c, 0, kitchen, "stove", [["n", 0.3], ["n", 1.6]])
	_put_any(c, 0, kitchen, "counter", [["n", 3.0], ["n", 3.6]], 2.0)
	_put_any(c, 0, kitchen, "fridge", [["w", 1.2], ["w", 0.3]])
	_put_any(c, 0, kitchen, "sink", [["w", 2.4], ["n", 5.2]])
	# Dining room.
	var dining: Rect2 = Rect2(x_left, z_k + PART_T * 0.5, x_right - x_left, z_front - z_k - PART_T * 0.5)
	var cr: Rect2 = Rect2(counter_x0, dining.position.y + 0.9, counter_len, 0.65)
	if c.claim(0, cr):
		_furn(c, 0, "counter", cr, 0.0, Vector2(counter_len, 0.65))
		for i: int in range(int(counter_len / 0.8)):
			c.deco(Vector3(counter_x0 + 0.5 + i * 0.8, c.f0 + 0.36, cr.end.y + 0.45), Vector3(0.36, 0.72, 0.36), c.m_accent)
	for i: int in range(3):
		_put_any(c, 0, dining, "booth", [["s", 0.3 + i * 2.5]])
	_put_any(c, 0, dining, "booth", [["w", 1.6]])
	_free_table(c, 0, Rect2(dining.position.x + 0.5, dining.position.y + 2.4, dining.size.x - 3.2, dining.size.y - 5.0))
	c.lamp(Vector3(0, c.f0 + 2.8, dining.get_center().y), 2.2, 11.0)
	c.routes["diner_to_alley"] = [Vector3(door_x, c.f0, z_front - 0.8), Vector3(door_x, c.f0, z_k + 0.8), Vector3(door_x, c.f0, z_k - 0.8), Vector3(door_x, c.f0, z_back + 0.8)]
	c.to_shell()
	_roof_details(c)


# --- CHURCH HALL: a nave with pews and a dais, kitchen and restroom behind, stained glass ------------

static func _church_hall(c: Ctx) -> void:
	var hx: float = c.hx
	var hz: float = c.hz
	c.roof_y = c.f0 + 6.4
	var z_back: float = -hz + WALL_T
	var z_front: float = hz - WALL_T
	var x_left: float = -hx + WALL_T
	var x_right: float = hx - WALL_T
	var back_w: float = 2.6
	var z_bk: float = z_back + 4.0
	var side_z: float = 1.0
	c.walls([Kit.opening(0.0, 2.0, 0.0, 3.0, "door")], [Kit.opening(x_right - 1.3, 1.2, 0.0, DOOR_H, "door")], [], [Kit.opening(side_z, 1.4, 0.0, DOOR_H, "door")])
	c.roof_slab()
	var stained: Material = c.kit.glow(Color(0.45, 0.35, 0.95), 0.9)
	c.windows_on("left", [0], 3.2, [Vector2(-hz, -hz + 4.4)], 1.1, 2.4, 0.9, stained)
	c.windows_on("right", [0], 3.2, [Vector2(-hz, -hz + 4.4), Vector2(side_z - 0.9, side_z + 0.9)], 1.1, 2.4, 0.9, stained)
	c.windows_on("front", [0], 3.4, [Vector2(-1.8, 1.8)], 1.1, 2.4, 0.9, stained)
	c.door(Vector3(0, c.f0, hz - WALL_T * 0.5), 2.0, 3.0, Vector3.BACK, c.sign_text + " entrance")
	c.door(Vector3(x_right - 1.3, c.f0, -hz + WALL_T * 0.5), 1.2, DOOR_H, Vector3.FORWARD, c.sign_text + " back door")
	c.door(Vector3(hx - WALL_T * 0.5, c.f0, side_z), 1.4, DOOR_H, Vector3.RIGHT, c.sign_text + " side door")
	c.fascia(0.0, c.f0 + 3.6, minf(W_of(c) - 1.0, 6.0), 0.6, 26)
	var top: float = c.roof_y + PARAPET
	c.kit.box(Vector3(0, top + 0.5, hz - 0.2), Vector3(W_of(c) - 1.0, 1.0, 0.5), c.m_trim)
	c.kit.box(Vector3(0, top + 1.3, hz - 0.2), Vector3(W_of(c) * 0.5, 0.7, 0.5), c.m_trim)
	c.kit.box(Vector3(0, top + 2.6, hz - 0.2), Vector3(0.25, 2.0, 0.25), c.m_accent)
	c.kit.box(Vector3(0, top + 3.0, hz - 0.2), Vector3(1.2, 0.25, 0.25), c.m_accent)
	c.to_interior()
	c.m_floor = c.mat(Color(0.5, 0.4, 0.3), "planks", 0.85)
	c.slab(0)
	c.roof_ceiling()
	var x_l: float = x_left + back_w
	var x_r: float = x_right - back_w
	c.partz(0, z_back, z_bk, x_l)
	c.partz(0, z_back, z_bk, x_r)
	c.partx(0, x_left, x_l, z_bk, [c.gap((x_left + x_l) * 0.5, 0.9)])
	c.partx(0, x_r, x_right, z_bk, [c.gap(x_right - 1.3, 1.0, DOOR_H)])
	var wc: Rect2 = Rect2(x_left, z_back, back_w - 0.08, z_bk - z_back - 0.08)
	var kitchen: Rect2 = Rect2(x_r + 0.08, z_back, back_w - 0.08, z_bk - z_back - 0.08)
	_put_any(c, 0, wc, "toilet", [["n", 0.3]])
	_put_any(c, 0, wc, "sink", [["w", 1.3], ["e", 1.3]])
	_put_any(c, 0, kitchen, "stove", [["e", 0.3], ["e", 1.6]])
	_put_any(c, 0, kitchen, "fridge", [["w", 0.3]])
	var nave: Rect2 = Rect2(x_left, z_bk + PART_T * 0.5, x_right - x_left, z_front - z_bk - PART_T * 0.5)
	# The dais between the back rooms: one 0.17 m step up.
	var dais: Rect2 = Rect2(x_l + 0.2, z_back, x_r - x_l - 0.4, 2.4)
	c.kit.box(Vector3(dais.get_center().x, c.f0 + 0.085, dais.get_center().y), Vector3(dais.size.x, 0.17, dais.size.y), c.m_wood, true)
	c.reserve(0, dais)
	c.reserve(0, Rect2(-1.0, z_bk, 2.0, z_front - z_bk))
	c.reserve(0, Rect2(x_left, z_bk + 0.1, x_right - x_left, 2.0))
	c.reserve(0, Rect2(x_right - 2.2, side_z - 1.2, 2.2, 2.4))
	c.reserve(0, Rect2(x_left, z_front - 3.0, x_right - x_left, 3.0))
	var lectern: Rect2 = Rect2(-0.3, z_back + 0.6, 0.6, 0.5)
	if c.claim(0, lectern):
		c.kit.box(Vector3(0, c.f0 + 0.17 + 0.55, z_back + 0.85), Vector3(0.6, 1.1, 0.5), c.m_wood, true)
	c.kit.box(Vector3(0, c.f0 + 3.3, z_back + 0.1), Vector3(0.3, 2.4, 0.1), c.m_accent)
	c.kit.box(Vector3(0, c.f0 + 3.7, z_back + 0.1), Vector3(1.3, 0.3, 0.1), c.m_accent)
	var row_z: float = z_bk + 2.4
	while row_z + 0.5 < z_front - 3.2:
		for side: float in [-1.0, 1.0]:
			var x0: float = 1.1 if side > 0.0 else x_left + 0.9
			var x1: float = x_right - 2.4 if side > 0.0 else -1.1
			var pew: Rect2 = Rect2(x0, row_z, minf(x1 - x0, 3.6), 0.5)
			if pew.size.x > 1.0 and c.claim(0, pew):
				_furn(c, 0, "bench", pew, 0.0, Vector2(pew.size.x, 0.5))
		row_z += 1.3
	c.lamp(Vector3(0, c.f0 + 5.0, nave.get_center().y), 2.6, 16.0)
	c.routes["nave_to_back"] = [Vector3(0, c.f0, z_front - 1.0), Vector3(0, c.f0, z_bk + 1.1), Vector3(x_right - 1.3, c.f0, z_bk + 1.1), Vector3(x_right - 1.3, c.f0, z_bk - 0.8), Vector3(x_right - 1.3, c.f0, z_back + 0.8)]
	c.to_shell()
	_roof_details(c)
