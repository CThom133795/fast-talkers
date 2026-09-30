extends RefCounted
## Midtown's walk-in businesses. Each signed storefront is a hollow ground floor under a
## solid upper block: a real doorway (a door leaf that swings, or a roller shutter at the
## garage), shop windows of breakable glass on a solid bulkhead, and an interior furnished
## to match the sign over the door. Two passes, because they land in different nodes:
##   build_shell()     facade, walls, glass, door, sign  -> the merged Midtown node
##   build_interior()  floor, ceiling, linings, props, a lamp -> its own node, whose meshes
##                     sit on render layer 2 so the lamp lights only the room.
## Local frame: +Z is out of the front door, +X runs along the facade; the origin is the
## building's centre at street level. `door` is the doorway's X offset along the facade.
## CARGO 04 stays sealed: it is the armory range's backstop.

const GlassScript = preload("res://scripts/breakable_glass.gd")
const MeshKit = preload("res://scripts/mesh_kit.gd")

## Ground-floor ceiling height and wall thickness.
const GROUND: float = 4.2
const WALL: float = 0.3
## Public rooms are at most this deep (per trade) and 2 * MAX_HALF_WIDTH wide.
const ROOM_DEPTH: Dictionary = {"exchange": 13.0, "imports": 15.0, "logistics": 14.0, "authority": 12.0, "freight": 11.0, "bar": 13.0, "hotel": 13.0, "pawn": 10.0, "cafe": 10.0, "store": 13.0, "garage": 16.0, "laundry": 10.0}
const MAX_HALF_WIDTH: float = 11.5

const SHOPS: Array[Dictionary] = [
	{"sign": "NORTHLINE  EXCHANGE", "kind": "exchange", "at": Vector2(-25, 10), "size": Vector3(25, 9.5, 29), "color": Color(0.63, 0.60, 0.49), "front": Vector3.RIGHT, "door": -5.0},
	{"sign": "MERIDIAN  IMPORTS", "kind": "imports", "at": Vector2(-24, -34), "size": Vector3(23, 13, 20), "color": Color(0.53, 0.38, 0.29), "front": Vector3.BACK, "door": 6.0},
	{"sign": "MERCURY  LOGISTICS", "kind": "logistics", "at": Vector2(26, 13), "size": Vector3(26, 12, 24), "color": Color(0.43, 0.50, 0.48), "front": Vector3.LEFT, "door": 0.0},
	{"sign": "PORT AUTHORITY", "kind": "authority", "at": Vector2(-24, -68), "size": Vector3(25, 18, 20), "color": Color(0.48, 0.50, 0.47), "front": Vector3.BACK, "door": 0.0},
	{"sign": "EASTBANK  FREIGHT", "kind": "freight", "at": Vector2(25, -68), "size": Vector3(23, 11, 20), "color": Color(0.59, 0.45, 0.35), "front": Vector3.BACK, "door": -5.0},
	{"sign": "THE BRASS RAIL", "kind": "bar", "at": Vector2(-25, 60), "size": Vector3(25, 15, 31), "color": Color(0.49, 0.44, 0.36), "front": Vector3.RIGHT, "door": -4.0},
	{"sign": "HOTEL CARLYLE", "kind": "hotel", "at": Vector2(27, 62), "size": Vector3(27, 17, 30), "color": Color(0.57, 0.55, 0.44), "front": Vector3.LEFT, "door": 0.0},
	{"sign": "LUCKY STAR PAWN", "kind": "pawn", "at": Vector2(-61, -33), "size": Vector3(22, 19, 21), "color": Color(0.5, 0.42, 0.36), "front": Vector3.BACK, "door": 3.0},
	{"sign": "ROSA'S CAFE", "kind": "cafe", "at": Vector2(61, -33), "size": Vector3(22, 15, 21), "color": Color(0.62, 0.5, 0.4), "front": Vector3.BACK, "door": -4.0},
	{"sign": "KWON'S 24/7", "kind": "store", "at": Vector2(-61, 9), "size": Vector3(22, 22, 21), "color": Color(0.42, 0.46, 0.45), "front": Vector3.BACK, "door": -6.0},
	{"sign": "MIDTOWN GARAGE", "kind": "garage", "at": Vector2(61, 9), "size": Vector3(22, 17, 21), "color": Color(0.44, 0.44, 0.42), "front": Vector3.RIGHT, "door": 0.0},
	{"sign": "SUDS LAUNDROMAT", "kind": "laundry", "at": Vector2(61, 60), "size": Vector3(22, 20, 21), "color": Color(0.46, 0.48, 0.5), "front": Vector3.BACK, "door": 5.0},
]

## Sign colour, lamp colour and awning stripes per kind.
const STYLE: Dictionary = {
	"exchange": {"sign": Color(0.94, 0.86, 0.64), "lamp": Color(1.0, 0.86, 0.62), "neon": false},
	"imports": {"sign": Color(0.94, 0.86, 0.64), "lamp": Color(0.9, 0.92, 1.0), "neon": false},
	"logistics": {"sign": Color(0.6, 0.9, 1.0), "lamp": Color(0.9, 0.95, 1.0), "neon": false},
	"authority": {"sign": Color(0.94, 0.9, 0.8), "lamp": Color(0.95, 0.95, 1.0), "neon": false},
	"freight": {"sign": Color(0.95, 0.8, 0.5), "lamp": Color(1.0, 0.9, 0.75), "neon": false},
	"bar": {"sign": Color(1.0, 0.62, 0.25), "lamp": Color(1.0, 0.62, 0.36), "neon": true, "awning": [Color(0.4, 0.08, 0.08), Color(0.2, 0.04, 0.04)]},
	"hotel": {"sign": Color(1.0, 0.85, 0.55), "lamp": Color(1.0, 0.82, 0.55), "neon": true},
	"pawn": {"sign": Color(1.0, 0.85, 0.2), "lamp": Color(1.0, 0.9, 0.7), "neon": true, "awning": [Color(0.1, 0.25, 0.15), Color(0.85, 0.75, 0.3)]},
	"cafe": {"sign": Color(1.0, 0.5, 0.45), "lamp": Color(1.0, 0.8, 0.6), "neon": true, "awning": [Color(0.75, 0.15, 0.15), Color(0.95, 0.92, 0.85)]},
	"store": {"sign": Color(0.35, 1.0, 0.55), "lamp": Color(0.9, 1.0, 0.95), "neon": true, "awning": [Color(0.1, 0.45, 0.25), Color(0.95, 0.95, 0.9)]},
	"garage": {"sign": Color(0.95, 0.75, 0.3), "lamp": Color(1.0, 0.95, 0.85), "neon": false},
	"laundry": {"sign": Color(0.4, 0.8, 1.0), "lamp": Color(0.9, 0.97, 1.0), "neon": true, "awning": [Color(0.15, 0.35, 0.6), Color(0.9, 0.93, 0.95)]},
}

var world: Node3D
var spec: Dictionary
var kind: String
var at: Vector3
var yaw: float
var basis: Basis
var width: float
var depth: float
var height: float
var door_x: float
var door_width: float
var door_height: float
## Interior extents (inside the walls).
var hw: float
var z_back: float
var z_front: float


func _init(owner: Node3D, shop: Dictionary) -> void:
	world = owner
	spec = shop
	kind = str(shop["kind"])
	var centre: Vector2 = shop["at"]
	at = Vector3(centre.x, 0, centre.y)
	var front: Vector3 = shop["front"]
	yaw = atan2(front.x, front.z)
	basis = Basis(Vector3.UP, yaw)
	var size: Vector3 = shop["size"]
	width = size.x if absf(front.z) > 0.5 else size.z
	depth = size.z if absf(front.z) > 0.5 else size.x
	height = size.y
	door_x = float(shop["door"])
	door_width = 4.6 if kind == "garage" else (2.4 if kind in ["exchange", "hotel", "authority"] else 1.8)
	door_height = 3.5 if kind == "garage" else 2.7
	hw = width * 0.5 - WALL
	z_back = -depth * 0.5 + WALL
	z_front = depth * 0.5 - WALL


## Local shop space -> world.
func _p(local: Vector3) -> Vector3:
	return at + basis * local


func _box(local: Vector3, size: Vector3, material: Material, solid: bool = false) -> MeshInstance3D:
	return world._box_with(_p(local), size, material, solid, yaw)


func _mat(color: Color, tex: String = "", roughness: float = 0.85) -> StandardMaterial3D:
	return world._material(color, roughness, tex)


func _solid(local: Vector3, size: Vector3) -> void:
	world._collider(_p(local), size, yaw)


# --- Shell ----------------------------------------------------------------------------------

func build_shell() -> void:
	var size: Vector3 = spec["size"]
	var color: Color = spec["color"]
	var tex: String = "brick" if color.r > color.b + 0.08 else "panel"
	var wall: StandardMaterial3D = _mat(color, tex, 0.9)
	var trim: StandardMaterial3D = _mat(color.darkened(0.35), tex, 0.9)
	world._footprint(Rect2(at.x - size.x * 0.5, at.z - size.z * 0.5, size.x, size.z))
	# Upper floors are solid; the ground floor is walls round a room.
	_box(Vector3(0, GROUND + (height - GROUND) * 0.5, 0), Vector3(width, height - GROUND, depth), wall, true)
	_box(Vector3(0, GROUND * 0.5, -depth * 0.5 + WALL * 0.5), Vector3(width, GROUND, WALL), wall, true)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(side * (width * 0.5 - WALL * 0.5), GROUND * 0.5, 0), Vector3(WALL, GROUND, depth - WALL * 2.0), wall, true)
	# Shopfront: piers, bulkheads under the windows, a header over every opening.
	var face_z: float = depth * 0.5 - WALL * 0.5
	var openings: Array = _openings()
	var cursor: float = -width * 0.5
	for opening: Array in openings:
		var x0: float = opening[0]
		var x1: float = opening[1]
		var y0: float = opening[2]
		var y1: float = opening[3]
		if x0 > cursor + 0.01:
			_box(Vector3((cursor + x0) * 0.5, GROUND * 0.5, face_z), Vector3(x0 - cursor, GROUND, WALL), wall, true)
		if y0 > 0.01:
			_box(Vector3((x0 + x1) * 0.5, y0 * 0.5, face_z), Vector3(x1 - x0, y0, WALL), trim, true)
		_box(Vector3((x0 + x1) * 0.5, (y1 + GROUND) * 0.5, face_z), Vector3(x1 - x0, GROUND - y1, WALL), wall, true)
		if str(opening[4]) == "window":
			_glass(Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, face_z), Vector3(x1 - x0, y1 - y0, 0.05))
			# A slim mullion and a sill read as a real shop window.
			_box(Vector3((x0 + x1) * 0.5, y0 + 0.04, face_z + WALL * 0.5 + 0.06), Vector3(x1 - x0 + 0.1, 0.08, 0.14), trim)
			_box(Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, face_z + 0.05), Vector3(0.07, y1 - y0, 0.07), _mat(Color(0.12, 0.12, 0.13), "", 0.5))
		cursor = x1
	if cursor < width * 0.5 - 0.01:
		_box(Vector3((cursor + width * 0.5) * 0.5, GROUND * 0.5, face_z), Vector3(width * 0.5 - cursor, GROUND, WALL), wall, true)
	# Door frame, then a door that swings (or a shutter that rolls).
	_box(Vector3(door_x, door_height + 0.08, face_z + 0.2), Vector3(door_width + 0.3, 0.16, 0.12), _mat(Color(0.12, 0.12, 0.13), "", 0.5))
	for side: float in [-1.0, 1.0]:
		_box(Vector3(door_x + side * (door_width * 0.5 + 0.08), door_height * 0.5, face_z + 0.2), Vector3(0.14, door_height, 0.12), _mat(Color(0.12, 0.12, 0.13), "", 0.5))
	_door()
	# Fascia band over the shopfront, the sign on it, and an awning where the trade suits one.
	var style: Dictionary = STYLE[kind]
	_box(Vector3(0, GROUND + 0.2, depth * 0.5 + 0.12), Vector3(width + 0.1, 0.4, 0.26), trim)
	var sign_at: Vector3 = _p(Vector3(0, 3.62, depth * 0.5 + 0.22))
	if bool(style["neon"]):
		world._neon(str(spec["sign"]), sign_at, yaw, style["sign"], clampi(int(width * 3.4), 40, 64))
	else:
		_box(Vector3(0, 3.62, depth * 0.5 + 0.1), Vector3(minf(width * 0.8, 16.0), 0.95, 0.14), _mat(Color(0.12, 0.23, 0.25), "", 0.6))
		world._label(str(spec["sign"]), _p(Vector3(0, 3.62, depth * 0.5 + 0.19)), 52, style["sign"], yaw)
	if style.has("awning"):
		var colors: Array = style["awning"]
		var front: Vector3 = spec["front"]
		world._awning(_p(Vector3(0, 3.05, depth * 0.5)), width * 0.82, front, colors[0], colors[1])
	# Upper-floor windows on the front and both sides, roof cap and plant.
	var glass: StandardMaterial3D = world._material(Color(0.16, 0.24, 0.29), 0.3)
	var warm: StandardMaterial3D = world._glow(Color(1.0, 0.78, 0.46), 1.3)
	var floors: int = int((height - GROUND - 1.0) / 3.1)
	for floor_index: int in range(floors):
		var y: float = GROUND + 1.55 + floor_index * 3.1
		var columns: int = maxi(1, int(width / 3.5))
		for column: int in range(columns):
			var x: float = -width * 0.5 + (column + 0.5) * width / columns
			_box(Vector3(x, y, depth * 0.5 + 0.045), Vector3(1.65, 1.55, 0.1), warm if world._rng.randf() < 0.3 else glass)
			_box(Vector3(x, y - 0.85, depth * 0.5 + 0.17), Vector3(1.9, 0.15, 0.35), _mat(color.lightened(0.12), tex, 0.9))
		var side_columns: int = maxi(1, int(depth / 3.5))
		for side: float in [-1.0, 1.0]:
			for column: int in range(side_columns):
				var z: float = -depth * 0.5 + (column + 0.5) * depth / side_columns
				_box(Vector3(side * (width * 0.5 + 0.04), y, z), Vector3(0.1, 1.55, 1.65), warm if world._rng.randf() < 0.3 else glass)
	_box(Vector3(0, height + 0.16, 0), Vector3(width + 0.45, 0.32, depth + 0.45), _mat(Color(0.29, 0.31, 0.30), "roof"))
	_box(Vector3(-width * 0.22, height + 0.65, -depth * 0.2), Vector3(2.2, 1.0, 2.5), _mat(Color(0.43, 0.45, 0.43), "metal"))


## Shopfront openings along the facade: [x0, x1, y0, y1, "door" | "window"], sorted.
func _openings() -> Array:
	var openings: Array = [[door_x - door_width * 0.5, door_x + door_width * 0.5, 0.0, door_height, "door"]]
	if kind == "garage":
		return openings
	# Windows fill the facade either side of the door, 1 m piers between, 1.2 m at corners.
	var sill: float = 0.85
	var top: float = 3.05
	for side: float in [-1.0, 1.0]:
		var inner: float = door_x + side * (door_width * 0.5 + 0.9)
		var outer: float = side * (width * 0.5 - 1.2)
		var span: float = (outer - inner) * side
		if span < 1.6:
			continue
		var count: int = maxi(1, int(round(span / 3.6)))
		var pane: float = (span - (count - 1) * 0.8) / count
		for index: int in range(count):
			var a: float = inner + side * index * (pane + 0.8)
			var b: float = a + side * pane
			openings.append([minf(a, b), maxf(a, b), sill, top, "window"])
	openings.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
	return openings


func _glass(local: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = GlassScript.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var pane: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	pane.mesh = mesh
	pane.material_override = _shop_glass()
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pane.visibility_range_end = 80.0
	body.add_child(pane)
	body.pane = pane
	body.position = _p(local)
	body.rotation.y = yaw
	world._target.add_child(body)
	world.glass_panes.append({"body": body, "shop": str(spec["sign"])})


func _shop_glass() -> StandardMaterial3D:
	if world._materials.has("shop_glass"):
		return world._materials["shop_glass"] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.62, 0.66, 0.24)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.05
	material.metallic = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	world._materials["shop_glass"] = material
	return material


## The door leaves (or roller shutter) and the door's record in world.interactable_doors.
## Doors start open so the room is reachable before main.gd binds a key to them.
func _door() -> void:
	var face_z: float = depth * 0.5 - WALL * 0.5
	var leaves: Array = []
	if kind == "garage":
		var shutter: Node3D = Node3D.new()
		world._target.add_child(shutter)
		shutter.position = _p(Vector3(door_x, 0, face_z))
		shutter.rotation.y = yaw
		shutter.set_meta("roller", door_height - 0.2)
		shutter.position.y = door_height - 0.2
		var body: StaticBody3D = _leaf_body(Vector3(0, door_height * 0.5, 0), Vector3(door_width, door_height, 0.08), _mat(Color(0.5, 0.52, 0.5), "metal", 0.6))
		shutter.add_child(body)
		leaves.append(shutter)
	else:
		var count: int = 2 if door_width > 2.0 else 1
		var leaf: float = door_width / count
		for index: int in range(count):
			var hinge_side: float = -1.0 if index == 0 else 1.0
			var hinge: Node3D = Node3D.new()
			world._target.add_child(hinge)
			hinge.position = _p(Vector3(door_x + hinge_side * door_width * 0.5, 0, face_z - WALL * 0.3))
			var swing: float = 1.7 if hinge_side < 0.0 else -1.7
			hinge.set_meta("closed_yaw", yaw)
			hinge.set_meta("swing", swing)
			hinge.rotation.y = yaw + swing
			var wood: StandardMaterial3D = _mat(Color(0.3, 0.2, 0.13), "planks", 0.7)
			var body: StaticBody3D = _leaf_body(Vector3(-hinge_side * leaf * 0.5, door_height * 0.5, 0), Vector3(leaf - 0.04, door_height - 0.04, 0.06), wood)
			hinge.add_child(body)
			var window: MeshInstance3D = MeshInstance3D.new()
			var mesh: BoxMesh = BoxMesh.new()
			mesh.size = Vector3(leaf * 0.55, 0.9, 0.07)
			window.mesh = mesh
			window.material_override = _shop_glass()
			window.position = Vector3(0, 0.45, 0)
			body.get_child(1).add_child(window)
			leaves.append(hinge)
	var index: int = world.interactable_doors.size()
	world.interactable_doors.append({"index": index, "label": str(spec["sign"]), "kind": kind, "position": _p(Vector3(door_x, 0, depth * 0.5)),
		"inside": _p(Vector3(door_x, 0, z_front - 1.6)), "outside": _p(Vector3(door_x, 0, depth * 0.5 + 1.6)), "open": true,
		"district": "MIDTOWN", "width": door_width})
	world._door_nodes.append(leaves)


func _leaf_body(offset: Vector3, size: Vector3, material: Material) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	# The collider is a touch wider than the leaf so a shut pair of doors has no seam.
	box.size = size + Vector3(0.06, 0.0, 0.0)
	shape.shape = box
	body.add_child(shape)
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.visibility_range_end = 80.0
	body.add_child(mesh_instance)
	body.position = offset
	return body


# --- Interior -------------------------------------------------------------------------------

func build_interior() -> void:
	var node: Node3D = world._begin("Interior" + kind.capitalize())
	var style: Dictionary = STYLE[kind]
	var looks: Dictionary = _looks()
	var lining: StandardMaterial3D = _mat(looks["wall"], looks["wall_tex"])
	# The public room is capped to a believable size; the rest of the floor plate is
	# back-of-house behind solid partitions (the shop windows beyond them show a dark store).
	var room_depth: float = float(ROOM_DEPTH.get(kind, 12.0))
	var plate_half: float = hw
	var shortened: bool = z_front - z_back > room_depth + 1.0
	if shortened:
		z_back = z_front - room_depth
		_box(Vector3(0, GROUND * 0.5, z_back - 0.1), Vector3(plate_half * 2.0, GROUND, 0.2), lining, true)
	if hw > MAX_HALF_WIDTH:
		hw = MAX_HALF_WIDTH
		for side: float in [-1.0, 1.0]:
			_box(Vector3(side * (hw + 0.1), GROUND * 0.5, (z_front + z_back) * 0.5 - 0.1), Vector3(0.2, GROUND, z_front - z_back + 0.2), lining, true)
	if shortened and not kind in ["imports", "logistics", "laundry", "store"]:
		_staff_door()
	var inner_depth: float = z_front - z_back
	var mid_z: float = (z_front + z_back) * 0.5
	_box(Vector3(0, 0.02, mid_z), Vector3(hw * 2.0, 0.04, inner_depth), _mat(looks["floor"], looks["floor_tex"]))
	_box(Vector3(0, GROUND - 0.05, mid_z), Vector3(hw * 2.0, 0.1, inner_depth), _mat((looks["ceiling"] as Color).darkened(0.35), "", 0.95))
	for t: float in [0.33, 0.66]:
		_box(Vector3(0, GROUND - 0.25, lerpf(z_back, z_front, t)), Vector3(hw * 2.0, 0.3, 0.35), _mat((looks["ceiling"] as Color).darkened(0.55), "", 0.9))
	_box(Vector3(0, GROUND * 0.5, z_back + 0.02), Vector3(hw * 2.0, GROUND - 0.1, 0.04), lining)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(side * (hw - 0.02), GROUND * 0.5, mid_z), Vector3(0.04, GROUND - 0.1, inner_depth), lining)
	if looks.has("dado"):
		var dado: StandardMaterial3D = _mat(looks["dado"], "planks", 0.7)
		_box(Vector3(0, 0.55, z_back + 0.05), Vector3(hw * 2.0, 1.1, 0.04), dado)
		for side: float in [-1.0, 1.0]:
			_box(Vector3(side * (hw - 0.05), 0.55, mid_z), Vector3(0.04, 1.1, inner_depth), dado)
	# Ceiling fixtures in a loose grid.
	var fixture: StandardMaterial3D = world._glow((style["lamp"] as Color).lerp(Color.WHITE, 0.3), 1.4)
	for x: float in [-hw * 0.5, hw * 0.5]:
		for z: float in [lerpf(z_back, z_front, 0.3), lerpf(z_back, z_front, 0.72)]:
			_box(Vector3(x, GROUND - 0.12, z), Vector3(1.4, 0.05, 0.35), fixture)
	call("_furnish_" + kind)
	var props: Node3D = _dress(node)
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.light_color = style["lamp"]
	lamp.light_energy = 2.3
	lamp.omni_range = maxf(hw * 2.0, inner_depth) * 0.9
	lamp.omni_attenuation = 0.9
	lamp.shadow_enabled = false
	lamp.light_cull_mask = 1 << (world.INTERIOR_LAYER - 1)
	lamp.position = _p(Vector3(0, GROUND - 0.6, mid_z))
	node.add_child(lamp)
	world._interior_lights.append(lamp)
	world._finish(node)
	for child: Node in node.get_children():
		if child is GeometryInstance3D:
			var geometry: GeometryInstance3D = child as GeometryInstance3D
			geometry.layers = 1 << (world.INTERIOR_LAYER - 1)
			# Furnished rooms only draw up close; from further out the lit shop window reads.
			geometry.visibility_range_end = 45.0
			geometry.visibility_range_end_margin = 5.0
	_finish_props(props)


func _looks() -> Dictionary:
	match kind:
		"exchange": return {"floor": Color(0.84, 0.82, 0.76), "floor_tex": "tiles", "wall": Color(0.86, 0.82, 0.7), "wall_tex": "stucco", "ceiling": Color(0.9, 0.88, 0.82), "dado": Color(0.36, 0.22, 0.14)}
		"imports": return {"floor": Color(0.5, 0.5, 0.48), "floor_tex": "panel", "wall": Color(0.6, 0.42, 0.33), "wall_tex": "brick", "ceiling": Color(0.4, 0.42, 0.42)}
		"logistics": return {"floor": Color(0.52, 0.53, 0.52), "floor_tex": "panel", "wall": Color(0.78, 0.8, 0.78), "wall_tex": "panel", "ceiling": Color(0.7, 0.72, 0.72)}
		"authority": return {"floor": Color(0.62, 0.66, 0.68), "floor_tex": "tiles", "wall": Color(0.72, 0.78, 0.74), "wall_tex": "stucco", "ceiling": Color(0.88, 0.9, 0.88), "dado": Color(0.42, 0.46, 0.44)}
		"freight": return {"floor": Color(0.46, 0.44, 0.4), "floor_tex": "planks", "wall": Color(0.76, 0.72, 0.6), "wall_tex": "stucco", "ceiling": Color(0.8, 0.78, 0.72)}
		"bar": return {"floor": Color(0.3, 0.2, 0.14), "floor_tex": "planks", "wall": Color(0.42, 0.12, 0.1), "wall_tex": "stucco", "ceiling": Color(0.18, 0.12, 0.1), "dado": Color(0.24, 0.15, 0.09)}
		"hotel": return {"floor": Color(0.5, 0.12, 0.14), "floor_tex": "tiles", "wall": Color(0.9, 0.84, 0.7), "wall_tex": "stucco", "ceiling": Color(0.95, 0.92, 0.84), "dado": Color(0.4, 0.26, 0.16)}
		"pawn": return {"floor": Color(0.55, 0.5, 0.42), "floor_tex": "tiles", "wall": Color(0.7, 0.66, 0.5), "wall_tex": "panel", "ceiling": Color(0.75, 0.74, 0.7)}
		"cafe": return {"floor": Color(0.86, 0.84, 0.8), "floor_tex": "tiles", "wall": Color(0.95, 0.88, 0.72), "wall_tex": "stucco", "ceiling": Color(0.95, 0.93, 0.88), "dado": Color(0.55, 0.2, 0.18)}
		"store": return {"floor": Color(0.82, 0.82, 0.78), "floor_tex": "tiles", "wall": Color(0.88, 0.9, 0.86), "wall_tex": "panel", "ceiling": Color(0.9, 0.92, 0.9)}
		"garage": return {"floor": Color(0.42, 0.42, 0.4), "floor_tex": "panel", "wall": Color(0.62, 0.62, 0.58), "wall_tex": "panel", "ceiling": Color(0.5, 0.5, 0.5)}
		_: return {"floor": Color(0.74, 0.78, 0.8), "floor_tex": "tiles", "wall": Color(0.82, 0.9, 0.92), "wall_tex": "panel", "ceiling": Color(0.9, 0.94, 0.95)}


## A shut door in the back partition: the room clearly goes on, but not for customers.
func _staff_door() -> void:
	var x: float = hw * 0.6 if door_x < 0.0 else -hw * 0.6
	_box(Vector3(x, 1.1, z_back + 0.04), Vector3(1.0, 2.2, 0.06), _mat(Color(0.32, 0.3, 0.28), "planks", 0.7))
	_box(Vector3(x + 0.35, 1.05, z_back + 0.09), Vector3(0.12, 0.05, 0.06), _mat(Color(0.7, 0.7, 0.68), "", 0.3))
	world._label("STAFF ONLY", _p(Vector3(x, 2.45, z_back + 0.08)), 26, Color(0.9, 0.9, 0.85), yaw)


## A plain dark-steel frame colour used by several trades.
func _steel() -> StandardMaterial3D:
	return _mat(Color(0.2, 0.21, 0.22), "metal", 0.5)


func _wood() -> StandardMaterial3D:
	return _mat(Color(0.38, 0.24, 0.14), "planks", 0.7)


## A counter: a solid base with a top that overhangs a little.
func _counter(centre: Vector3, length: float, depth_z: float, along_x: bool, base: StandardMaterial3D, top: StandardMaterial3D, tall: float = 1.05) -> void:
	var size: Vector3 = Vector3(length, tall, depth_z) if along_x else Vector3(depth_z, tall, length)
	_box(centre + Vector3(0, tall * 0.5, 0), size, base, true)
	_box(centre + Vector3(0, tall + 0.03, 0), size + Vector3(0.08, -tall + 0.06, 0.08), top)


func _crt(local: Vector3, screen: Color) -> void:
	_box(local + Vector3(0, 0.22, 0), Vector3(0.48, 0.42, 0.45), _mat(Color(0.78, 0.76, 0.7), "", 0.6))
	_box(local + Vector3(0, 0.24, 0.23), Vector3(0.36, 0.28, 0.02), world._glow(screen, 0.9))


func _chair(local: Vector3, facing_back: bool, color: Color) -> void:
	var seat: StandardMaterial3D = _mat(color, "", 0.8)
	_box(local + Vector3(0, 0.45, 0), Vector3(0.45, 0.06, 0.45), seat)
	_box(local + Vector3(0, 0.75, -0.2 if facing_back else 0.2), Vector3(0.45, 0.55, 0.05), seat)
	for corner: Vector2 in [Vector2(-0.19, -0.19), Vector2(0.19, -0.19), Vector2(-0.19, 0.19), Vector2(0.19, 0.19)]:
		_box(local + Vector3(corner.x, 0.22, corner.y), Vector3(0.04, 0.44, 0.04), _steel())


func _shelf_unit(centre: Vector3, length: float, along_x: bool, tall: float, goods: Array, deep: float = 0.6) -> void:
	var size: Vector3 = Vector3(length, tall, deep) if along_x else Vector3(deep, tall, length)
	_solid(centre + Vector3(0, tall * 0.5, 0), size)
	var frame: StandardMaterial3D = _steel()
	for end: float in [-0.5, 0.5]:
		var post: Vector3 = Vector3(end * length, tall * 0.5, 0) if along_x else Vector3(0, tall * 0.5, end * length)
		_box(centre + post, Vector3(0.06, tall, deep) if along_x else Vector3(deep, tall, 0.06), frame)
	var levels: int = maxi(2, int(tall / 0.55))
	for level: int in range(levels):
		var y: float = 0.15 + level * (tall - 0.2) / levels
		_box(centre + Vector3(0, y, 0), Vector3(length, 0.04, deep) if along_x else Vector3(deep, 0.04, length), frame)
		if goods.is_empty():
			continue
		var count: int = int(length / 0.5)
		for item: int in range(count):
			if world._rng.randf() < 0.18:
				continue
			var t: float = -length * 0.5 + (item + 0.5) * length / count
			var color: Color = goods[world._rng.randi() % goods.size()]
			var h: float = world._rng.randf_range(0.18, 0.36)
			var offset: Vector3 = Vector3(t, y + 0.02 + h * 0.5, 0) if along_x else Vector3(0, y + 0.02 + h * 0.5, t)
			_box(centre + offset, Vector3(0.38, h, deep * 0.7) if along_x else Vector3(deep * 0.7, h, 0.38), _mat(color, "", 0.7))


# --- The trades -----------------------------------------------------------------------------

## Northline Exchange: a banking hall. Teller line with glass screens, a vault door, deposit
## boxes, a roped queue and benches for the people waiting to do business.
func _furnish_exchange() -> void:
	var brass: StandardMaterial3D = _mat(Color(0.78, 0.62, 0.3), "", 0.35)
	var marble: StandardMaterial3D = _mat(Color(0.9, 0.88, 0.84), "tiles", 0.3)
	var counter_z: float = z_back + 6.0
	_counter(Vector3(1.8, 0, counter_z), hw * 2.0 - 5.2, 0.9, true, _wood(), marble, 1.1)
	for index: int in range(4):
		var x: float = -hw + 5.0 + index * (hw * 2.0 - 7.0) / 3.0
		_box(Vector3(x, 1.75, counter_z), Vector3(0.06, 1.2, 0.06), brass)
	_box(Vector3(1.8, 1.75, counter_z), Vector3(hw * 2.0 - 5.2, 1.1, 0.03), _shop_glass())
	_box(Vector3(1.8, 2.36, counter_z), Vector3(hw * 2.0 - 5.2, 0.08, 0.1), brass)
	# Vault door and deposit boxes on the back wall.
	var steel: StandardMaterial3D = _mat(Color(0.55, 0.57, 0.58), "metal", 0.35)
	world._mesh_at(MeshKit.cylinder(1.35, 1.35, 0.35, 28), _p(Vector3(-hw * 0.35, 1.6, z_back + 0.25)), steel, yaw, Vector3(PI * 0.5, 0, 0))
	world._mesh_at(MeshKit.cylinder(0.25, 0.25, 0.3, 12), _p(Vector3(-hw * 0.35, 1.6, z_back + 0.5)), brass, yaw, Vector3(PI * 0.5, 0, 0))
	for spoke: int in range(3):
		var bar: MeshInstance3D = _box(Vector3(-hw * 0.35, 1.6, z_back + 0.55), Vector3(1.2, 0.07, 0.07), brass)
		bar.rotation = Vector3(0, yaw, spoke * PI / 3.0)
	_box(Vector3(hw * 0.45, 1.5, z_back + 0.1), Vector3(hw * 0.7, 2.4, 0.16), _mat(Color(0.62, 0.6, 0.52), "metal", 0.4))
	# Roped queue, benches and a board of rates.
	var rope: StandardMaterial3D = _mat(Color(0.55, 0.08, 0.1), "", 0.8)
	for index: int in range(4):
		var z: float = counter_z + 3.0
		var x: float = -2.0 + index * 2.4
		_box(Vector3(x, 0.5, z), Vector3(0.1, 1.0, 0.1), brass)
		if index < 3:
			_box(Vector3(x + 1.2, 0.85, z), Vector3(2.3, 0.05, 0.05), rope)
	for x: float in [-hw + 2.5, hw - 2.5]:
		world._bench(_p(Vector3(x, 0.0, z_front - 5.5)), yaw + PI * 0.5 * signf(x))
	_box(Vector3(hw - 0.08, 2.6, lerpf(z_back, z_front, 0.55)), Vector3(0.06, 1.2, 2.4), world._glow(Color(0.35, 0.9, 0.55), 0.9))
	world._label("RATES", _p(Vector3(hw - 0.14, 3.4, lerpf(z_back, z_front, 0.55))), 40, Color(0.95, 0.88, 0.6), yaw - PI * 0.5)
	for x: float in [-hw * 0.5, hw * 0.5]:
		world._cylinder(_p(Vector3(x, GROUND - 0.5, lerpf(z_back, z_front, 0.5))), 0.35, 0.3, Color.WHITE, 10, world._glow(Color(1.0, 0.85, 0.6), 1.6))
	world._planter(_p(Vector3(hw - 1.0, 0.0, z_front - 1.0)))
	world._planter(_p(Vector3(-hw + 1.0, 0.0, z_front - 1.0)))


## Meridian Imports: a warehouse showroom. Pallet racking, a forklift, stacked crates and a
## glass-fronted site office.
func _furnish_imports() -> void:
	var orange: StandardMaterial3D = _mat(Color(0.85, 0.42, 0.12), "", 0.6)
	var blue: StandardMaterial3D = _mat(Color(0.16, 0.3, 0.55), "", 0.6)
	# Racking along the back wall: orange uprights, blue beams, crates and drums.
	var rack_z: float = z_back + 0.8
	var rack_length: float = hw * 2.0 - 1.0
	_solid(Vector3(0, 1.8, rack_z), Vector3(rack_length, 3.6, 1.2))
	for index: int in range(5):
		var x: float = -rack_length * 0.5 + index * rack_length / 4.0
		_box(Vector3(x, 1.8, rack_z), Vector3(0.1, 3.6, 1.2), orange)
	for y: float in [1.2, 2.5, 3.6]:
		_box(Vector3(0, y, rack_z), Vector3(rack_length, 0.1, 1.2), blue)
	for index: int in range(8):
		var x: float = -rack_length * 0.5 + 1.0 + index * (rack_length - 2.0) / 7.0
		var level: float = [0.0, 1.25, 2.55][index % 3]
		_box(Vector3(x, level + 0.5, rack_z), Vector3(1.0, 0.95, 1.0), _mat(Color(0.56, 0.43, 0.28), "planks"))
	# A forklift, parked with its forks down.
	var yellow: StandardMaterial3D = _mat(Color(0.9, 0.7, 0.12), "", 0.55)
	var lift: Vector3 = Vector3(-3.0, 0, lerpf(z_back, z_front, 0.52))
	_box(lift + Vector3(0, 0.65, 0), Vector3(1.2, 1.0, 2.0), yellow, true)
	_box(lift + Vector3(0, 1.3, 0.55), Vector3(1.1, 0.2, 0.7), _mat(Color(0.1, 0.1, 0.1)))
	for x: float in [-0.45, 0.45]:
		_box(lift + Vector3(x, 1.4, -1.1), Vector3(0.1, 2.6, 0.12), _steel())
		_box(lift + Vector3(x * 0.8, 0.12, -1.7), Vector3(0.12, 0.06, 1.1), _steel())
		_box(lift + Vector3(x * 1.1, 2.1, 0.0), Vector3(0.06, 1.3, 0.06), _steel())
	_box(lift + Vector3(0, 2.75, 0.0), Vector3(1.1, 0.06, 1.3), _steel())
	for z: float in [-0.6, 0.6]:
		for x: float in [-0.62, 0.62]:
			world._mesh_at(MeshKit.cylinder(0.25, 0.25, 0.2, 12), _p(lift + Vector3(x, 0.25, z)), _mat(Color(0.08, 0.08, 0.08)), yaw, Vector3(0, 0, PI * 0.5))
	# Crate stacks and the site office in the front corner away from the door.
	for spot: Vector3 in [Vector3(3.0, 0, -1.0), Vector3(4.3, 0, -1.0), Vector3(3.6, 1.2, -1.0), Vector3(-hw + 1.5, 0, -2.0)]:
		world._crate(_p(spot))
	var office: Vector3 = Vector3(-hw + 2.6, 0, z_front - 2.6)
	var panel: StandardMaterial3D = _mat(Color(0.7, 0.72, 0.68), "panel")
	_box(office + Vector3(0, 1.2, -2.4), Vector3(5.2, 2.4, 0.1), panel, true)
	_box(office + Vector3(2.6, 0.5, -0.9), Vector3(0.1, 1.0, 3.0), panel, true)
	_box(office + Vector3(2.6, 1.7, -0.9), Vector3(0.05, 1.4, 3.0), _shop_glass())
	_box(office + Vector3(-0.6, 0.38, -1.4), Vector3(1.6, 0.76, 0.8), _wood(), true)
	_crt(office + Vector3(-0.6, 0.78, -1.5), Color(0.4, 0.9, 0.5))


## Mercury Logistics: a courier depot. Service counter by the door, a roller conveyor,
## parcel racking and caged pallets.
func _furnish_logistics() -> void:
	var cardboard: Array = [Color(0.62, 0.48, 0.3), Color(0.7, 0.56, 0.36), Color(0.55, 0.42, 0.27)]
	_counter(Vector3(-hw * 0.5 - 1.0, 0, z_front - 4.0), hw - 2.5, 0.8, true, _mat(Color(0.3, 0.4, 0.5), "panel"), _mat(Color(0.85, 0.85, 0.82)))
	_crt(Vector3(-hw * 0.5 - 1.0, 1.08, z_front - 4.0), Color(0.4, 0.7, 1.0))
	# Conveyor down the middle of the depot.
	var belt_x: float = hw * 0.35
	var belt_length: float = (z_front - z_back) - 8.0
	var belt_z: float = z_back + 2.0 + belt_length * 0.5
	_box(Vector3(belt_x, 0.45, belt_z), Vector3(1.0, 0.9, belt_length), _steel(), true)
	for index: int in range(int(belt_length / 0.5)):
		_box(Vector3(belt_x, 0.92, z_back + 2.2 + index * 0.5), Vector3(0.96, 0.05, 0.08), _mat(Color(0.6, 0.62, 0.62), "", 0.3))
	for index: int in range(7):
		var box: Vector3 = Vector3(belt_x, 1.1, z_back + 3.0 + index * belt_length / 7.0)
		_box(box, Vector3(0.6, 0.35, 0.5), _mat(cardboard[index % 3], "", 0.9))
	_shelf_unit(Vector3(0, 0, z_back + 0.5), hw * 2.0 - 1.0, true, 2.8, cardboard)
	_shelf_unit(Vector3(-hw + 0.5, 0, lerpf(z_back, z_front, 0.4)), (z_front - z_back) * 0.45, false, 2.8, cardboard)
	# Caged roll containers.
	for index: int in range(3):
		var cage: Vector3 = Vector3(-hw * 0.45 + index * 1.1, 0, lerpf(z_back, z_front, 0.45))
		_box(cage + Vector3(0, 0.9, 0), Vector3(0.9, 1.8, 1.0), world._chainlink(), true)
		_box(cage + Vector3(0, 0.5, 0), Vector3(0.8, 0.8, 0.9), _mat(cardboard[index % 3], "", 0.9))


## Port Authority: a public office. Reception desk, turnstiles, rows of waiting seats,
## flags and a lit harbour chart.
func _furnish_authority() -> void:
	_counter(Vector3(0, 0, z_back + 4.5), 7.0, 1.0, true, _mat(Color(0.35, 0.38, 0.4), "panel"), _mat(Color(0.8, 0.8, 0.76)))
	_counter(Vector3(3.3, 0, z_back + 3.0), 2.4, 1.0, false, _mat(Color(0.35, 0.38, 0.4), "panel"), _mat(Color(0.8, 0.8, 0.76)))
	_crt(Vector3(-1.5, 1.08, z_back + 4.5), Color(0.45, 0.75, 1.0))
	_crt(Vector3(1.5, 1.08, z_back + 4.5), Color(0.45, 0.75, 1.0))
	world._label("PORT OF HALCYON", _p(Vector3(0, 3.2, z_back + 0.08)), 56, Color(0.9, 0.85, 0.6), yaw)
	# Turnstiles: waist-high posts with a gap wide enough to walk through between each.
	for x: float in [-3.6, -1.8, 1.8, 3.6]:
		_box(Vector3(x, 0.5, z_back + 8.0), Vector3(0.3, 1.0, 0.8), _steel(), true)
		_box(Vector3(x + 0.5 * signf(x), 0.95, z_back + 8.0), Vector3(0.7, 0.05, 0.05), _mat(Color(0.8, 0.8, 0.8), "", 0.3))
	# Waiting seats either side of the entrance lane.
	for side: float in [-1.0, 1.0]:
		for row: int in range(2):
			for seat: int in range(4):
				_chair(Vector3(side * (4.5 + seat * 0.6), 0, z_front - 3.5 - row * 1.6), false, Color(0.2, 0.3, 0.45))
	for index: int in range(2):
		var pole: Vector3 = Vector3(-hw + 1.2 + index * 1.2, 0, z_back + 1.5)
		_box(pole + Vector3(0, 1.4, 0), Vector3(0.06, 2.8, 0.06), _mat(Color(0.8, 0.7, 0.35), "", 0.35))
		_box(pole + Vector3(0.45, 2.3, 0), Vector3(0.8, 0.55, 0.03), _mat([Color(0.16, 0.3, 0.6), Color(0.85, 0.65, 0.2)][index], "", 0.9))
	_box(Vector3(hw - 0.08, 2.2, lerpf(z_back, z_front, 0.4)), Vector3(0.06, 1.6, 3.2), world._glow(Color(0.35, 0.55, 0.85), 0.8))


## Eastbank Freight: a freight office. Counter across the room, desks with terminals,
## filing cabinets and pallets waiting for pickup.
func _furnish_freight() -> void:
	var counter_z: float = z_front - 6.0
	_counter(Vector3(hw * 0.35, 0, counter_z), hw * 1.3, 0.8, true, _wood(), _mat(Color(0.7, 0.66, 0.56)))
	for x: float in [-hw * 0.2, hw * 0.45]:
		var desk: Vector3 = Vector3(x, 0, counter_z - 3.2)
		_box(desk + Vector3(0, 0.38, 0), Vector3(1.6, 0.76, 0.8), _wood(), true)
		_crt(desk + Vector3(0, 0.78, -0.1), Color(0.95, 0.65, 0.2))
		_chair(desk + Vector3(0, 0, 0.8), false, Color(0.2, 0.2, 0.22))
	for index: int in range(5):
		_box(Vector3(hw * 0.1 + index * 0.6, 0.7, z_back + 0.35), Vector3(0.5, 1.4, 0.6), _mat(Color(0.5, 0.52, 0.48), "metal", 0.5), true)
	_box(Vector3(-hw * 0.3, 2.3, z_back + 0.06), Vector3(3.6, 1.6, 0.04), _mat(Color(0.75, 0.72, 0.55), "", 0.9))
	for spot: Vector3 in [Vector3(-hw + 1.5, 0, z_back + 2.0), Vector3(-hw + 1.5, 0, z_back + 3.4), Vector3(-hw + 1.5, 1.2, z_back + 2.0)]:
		world._crate(_p(spot))
	_box(Vector3(-hw + 3.0, 0.07, z_back + 2.6), Vector3(1.2, 0.14, 1.0), _mat(Color(0.56, 0.43, 0.28), "planks"))


## The Brass Rail: a bar. Long counter and stools, a back bar of lit bottles, booths along
## one wall, a pool table and a jukebox.
func _furnish_bar() -> void:
	var brass: StandardMaterial3D = _mat(Color(0.8, 0.62, 0.28), "", 0.3)
	var bar_z: float = z_back + 3.2
	var bar_length: float = hw * 2.0 - 7.0
	var bar_x: float = hw - bar_length * 0.5 - 1.0
	_counter(Vector3(bar_x, 0, bar_z), bar_length, 0.8, true, _wood(), _mat(Color(0.2, 0.12, 0.08), "planks", 0.4), 1.1)
	_box(Vector3(bar_x, 0.2, bar_z + 0.5), Vector3(bar_length, 0.05, 0.05), brass)
	for index: int in range(int(bar_length / 1.1)):
		var stool: Vector3 = Vector3(bar_x - bar_length * 0.5 + 0.6 + index * 1.1, 0, bar_z + 1.0)
		_box(stool + Vector3(0, 0.38, 0), Vector3(0.06, 0.76, 0.06), brass)
		world._cylinder(_p(stool + Vector3(0, 0.78, 0)), 0.22, 0.08, Color(0.45, 0.1, 0.08), 10)
	# Back bar: mirrored shelves of bottles that glow in the dim room.
	_box(Vector3(bar_x, 1.8, z_back + 0.15), Vector3(bar_length, 2.0, 0.3), _wood())
	_box(Vector3(bar_x, 2.0, z_back + 0.32), Vector3(bar_length - 0.4, 1.2, 0.02), _mat(Color(0.6, 0.62, 0.66), "", 0.08))
	var bottles: Array = [Color(0.9, 0.55, 0.2), Color(0.35, 0.8, 0.4), Color(0.85, 0.85, 0.7), Color(0.7, 0.25, 0.2)]
	for shelf: float in [1.35, 2.05]:
		for index: int in range(int(bar_length / 0.3)):
			if world._rng.randf() < 0.25:
				continue
			var bottle: Vector3 = Vector3(bar_x - bar_length * 0.5 + 0.3 + index * 0.3, shelf + 0.15, z_back + 0.42)
			_box(bottle, Vector3(0.09, 0.3, 0.09), world._glow(bottles[index % bottles.size()], 0.7))
	# Booths along the far wall, a pool table, a jukebox and a neon sign.
	var leather: StandardMaterial3D = _mat(Color(0.45, 0.1, 0.08), "", 0.6)
	for index: int in range(3):
		var booth: Vector3 = Vector3(-hw + 1.0, 0, z_back + 4.5 + index * 3.4)
		for side: float in [-1.0, 1.0]:
			_box(booth + Vector3(0.3, 0.25, side * 1.05), Vector3(1.6, 0.5, 0.55), leather, true)
			_box(booth + Vector3(0.3, 0.85, side * 1.35), Vector3(1.6, 0.9, 0.15), leather, true)
		_box(booth + Vector3(0.4, 0.74, 0), Vector3(1.2, 0.06, 1.1), _wood(), true)
	var pool: Vector3 = Vector3(hw * 0.2, 0, lerpf(z_back, z_front, 0.62))
	_box(pool + Vector3(0, 0.4, 0), Vector3(1.5, 0.8, 2.7), _wood(), true)
	_box(pool + Vector3(0, 0.82, 0), Vector3(1.3, 0.04, 2.5), _mat(Color(0.1, 0.4, 0.2), "", 0.9))
	world._cylinder(_p(pool + Vector3(0, 2.6, 0)), 0.5, 0.2, Color.WHITE, 8, world._glow(Color(1.0, 0.85, 0.5), 1.4))
	var jukebox: Vector3 = Vector3(hw - 0.6, 0, z_front - 3.0)
	_box(jukebox + Vector3(0, 0.8, 0), Vector3(0.9, 1.6, 0.7), _wood(), true)
	_box(jukebox + Vector3(-0.36, 1.0, 0), Vector3(0.02, 1.0, 0.55), world._glow(Color(1.0, 0.35, 0.7), 1.6))
	world._neon("COLD BEER", _p(Vector3(-hw * 0.2, 3.1, z_back + 0.06)), yaw, Color(0.3, 0.8, 1.0), 44)


## Hotel Carlyle: a hotel lobby. Front desk and key rack, lounge chairs round a low table,
## brass lift doors and a chandelier.
func _furnish_hotel() -> void:
	var brass: StandardMaterial3D = _mat(Color(0.82, 0.66, 0.32), "", 0.3)
	_counter(Vector3(0, 0, z_back + 4.0), 7.5, 1.0, true, _wood(), _mat(Color(0.88, 0.86, 0.8), "tiles", 0.3), 1.1)
	_crt(Vector3(-2.0, 1.12, z_back + 4.0), Color(0.5, 0.9, 0.7))
	world._label("RECEPTION", _p(Vector3(0, 3.1, z_back + 0.08)), 48, Color(0.85, 0.7, 0.35), yaw)
	for row: int in range(3):
		for column: int in range(8):
			_box(Vector3(-1.75 + column * 0.5, 1.4 + row * 0.35, z_back + 0.1), Vector3(0.3, 0.22, 0.08), brass)
	# Lounge: four armchairs round a low table and two potted palms.
	var velvet: StandardMaterial3D = _mat(Color(0.2, 0.3, 0.22), "", 0.9)
	var lounge: Vector3 = Vector3(-hw * 0.55, 0, lerpf(z_back, z_front, 0.62))
	_box(lounge + Vector3(0, 0.22, 0), Vector3(1.2, 0.44, 0.8), _wood(), true)
	for offset: Vector3 in [Vector3(-1.4, 0, 0), Vector3(1.4, 0, 0), Vector3(0, 0, -1.3), Vector3(0, 0, 1.3)]:
		_box(lounge + offset + Vector3(0, 0.3, 0), Vector3(0.9, 0.6, 0.9), velvet, true)
		_box(lounge + offset * 1.25 + Vector3(0, 0.75, 0), Vector3(0.9 if absf(offset.z) > 0.1 else 0.2, 0.7, 0.2 if absf(offset.z) > 0.1 else 0.9), velvet)
	for spot: Vector3 in [Vector3(-hw + 1.0, 0, z_front - 1.2), Vector3(hw - 1.0, 0, z_front - 1.2)]:
		world._planter(_p(spot))
	# Lift doors on the side wall, with a floor dial.
	for index: int in range(2):
		var z: float = lerpf(z_back, z_front, 0.35) + index * 2.2
		_box(Vector3(hw - 0.08, 1.25, z), Vector3(0.06, 2.5, 1.5), brass)
		_box(Vector3(hw - 0.1, 1.25, z), Vector3(0.04, 2.5, 0.03), _mat(Color(0.3, 0.24, 0.1)))
		_box(Vector3(hw - 0.1, 2.85, z), Vector3(0.04, 0.3, 0.6), world._glow(Color(1.0, 0.6, 0.25), 1.2))
	# Chandelier.
	var centre: Vector3 = Vector3(0, GROUND - 0.9, lerpf(z_back, z_front, 0.55))
	world._cylinder(_p(centre), 0.9, 0.25, Color.WHITE, 12, world._glow(Color(1.0, 0.9, 0.7), 1.8))
	world._cylinder(_p(centre + Vector3(0, 0.45, 0)), 0.03, 0.7, Color(0.8, 0.66, 0.32), 6, brass)
	var cart: Vector3 = Vector3(hw * 0.5, 0, z_front - 3.0)
	_box(cart + Vector3(0, 0.2, 0), Vector3(0.8, 0.08, 1.4), _mat(Color(0.5, 0.1, 0.12)), true)
	for z: float in [-0.65, 0.65]:
		_box(cart + Vector3(0, 1.0, z), Vector3(0.05, 1.6, 0.05), brass)
	_box(cart + Vector3(0, 1.8, 0), Vector3(0.05, 0.05, 1.35), brass)
	_box(cart + Vector3(0, 0.5, 0.2), Vector3(0.5, 0.45, 0.7), _mat(Color(0.35, 0.25, 0.15), "", 0.8))


## Lucky Star Pawn: glass display cases in a U, guitars and a stack of televisions on the
## walls, and the big safe behind the counter.
func _furnish_pawn() -> void:
	var case_z: float = z_back + 3.5
	for part: Array in [[Vector3(0, 0, case_z), hw * 1.4, true], [Vector3(-hw * 0.7, 0, case_z + 2.0), 4.0, false], [Vector3(hw * 0.7, 0, case_z + 2.0), 4.0, false]]:
		var centre: Vector3 = part[0]
		var length: float = part[1]
		var along_x: bool = part[2]
		var size: Vector3 = Vector3(length, 0.8, 0.7) if along_x else Vector3(0.7, 0.8, length)
		_box(centre + Vector3(0, 0.4, 0), size, _wood(), true)
		_box(centre + Vector3(0, 0.95, 0), size * Vector3(1, 0.36, 1), _shop_glass())
		_box(centre + Vector3(0, 0.84, 0), size * Vector3(0.9, 0.05, 0.8), world._glow(Color(1.0, 0.82, 0.35), 0.7))
	# Guitars on the back wall.
	var finishes: Array = [Color(0.75, 0.3, 0.1), Color(0.1, 0.1, 0.1), Color(0.85, 0.75, 0.55), Color(0.6, 0.1, 0.12)]
	for index: int in range(5):
		var x: float = -hw * 0.25 + index * 1.1
		_box(Vector3(x, 1.7, z_back + 0.1), Vector3(0.42, 0.55, 0.08), _mat(finishes[index % 4], "", 0.4))
		_box(Vector3(x, 2.35, z_back + 0.1), Vector3(0.06, 0.75, 0.05), _mat(Color(0.3, 0.2, 0.12)))
	# A stack of TVs, some showing the late news.
	for row: int in range(3):
		for column: int in range(3):
			_crt(Vector3(hw - 1.0 - column * 0.55, row * 0.5, z_back + 0.4), Color(0.4, 0.55, 0.8) if (row + column) % 2 == 0 else Color(0.08, 0.08, 0.1))
	_box(Vector3(hw - 0.8, 0.7, z_back + 2.2), Vector3(1.0, 1.4, 0.9), _mat(Color(0.25, 0.3, 0.28), "metal", 0.4), true)
	world._neon("WE BUY GOLD", _p(Vector3(0, 3.1, z_back + 0.06)), yaw, Color(1.0, 0.8, 0.2), 40)


## Rosa's Cafe: a counter with an espresso machine and a lit pastry case, small tables
## and a chalk menu board.
func _furnish_cafe() -> void:
	var counter_z: float = z_back + 2.2
	_counter(Vector3(hw * 0.2, 0, counter_z), hw * 1.4, 0.7, true, _mat(Color(0.55, 0.2, 0.18), "planks"), _mat(Color(0.9, 0.9, 0.86), "tiles", 0.3))
	_box(Vector3(hw * 0.5, 1.3, counter_z), Vector3(0.7, 0.5, 0.5), _mat(Color(0.75, 0.77, 0.78), "", 0.2))
	_box(Vector3(-hw * 0.15, 1.3, counter_z), Vector3(1.6, 0.5, 0.6), world._glow(Color(1.0, 0.85, 0.6), 0.8))
	_box(Vector3(0, 2.6, z_back + 0.06), Vector3(4.0, 1.4, 0.04), _mat(Color(0.12, 0.14, 0.12), "", 0.9))
	world._label("ESPRESSO  CANNOLI  PANINI", _p(Vector3(0, 2.8, z_back + 0.1)), 30, Color(0.95, 0.95, 0.9), yaw)
	for spot: Vector2 in [Vector2(-hw * 0.6, 0.45), Vector2(-hw * 0.15, 0.55), Vector2(hw * 0.35, 0.5), Vector2(-hw * 0.6, 0.75), Vector2(hw * 0.5, 0.78)]:
		var table: Vector3 = Vector3(spot.x, 0, lerpf(z_back, z_front, spot.y))
		world._cylinder(_p(table + Vector3(0, 0.36, 0)), 0.06, 0.72, Color(0.2, 0.2, 0.2), 6)
		world._cylinder(_p(table + Vector3(0, 0.74, 0)), 0.42, 0.04, Color(0.9, 0.9, 0.86), 12)
		_solid(table + Vector3(0, 0.37, 0), Vector3(0.84, 0.74, 0.84))
		_chair(table + Vector3(0, 0, -0.7), false, Color(0.55, 0.2, 0.18))
		_chair(table + Vector3(0, 0, 0.7), true, Color(0.55, 0.2, 0.18))


## Kwon's 24/7: aisles of stocked shelving, a checkout by the door and lit drinks fridges
## along the back wall.
func _furnish_store() -> void:
	var goods: Array = [Color(0.85, 0.2, 0.15), Color(0.95, 0.8, 0.2), Color(0.2, 0.5, 0.85), Color(0.3, 0.7, 0.3), Color(0.9, 0.9, 0.85), Color(0.6, 0.3, 0.7)]
	var aisle_length: float = (z_front - z_back) - 8.0
	for x: float in [-hw * 0.1, hw * 0.3, hw * 0.7]:
		_shelf_unit(Vector3(x, 0, z_back + 3.0 + aisle_length * 0.5), aisle_length, false, 1.6, goods, 0.9)
	_shelf_unit(Vector3(-hw + 0.4, 0, lerpf(z_back, z_front, 0.45)), (z_front - z_back) * 0.5, false, 2.0, goods, 0.5)
	for index: int in range(int(hw * 2.0 / 1.2) - 2):
		var x: float = -hw + 2.0 + index * 1.2
		_box(Vector3(x, 1.0, z_back + 0.45), Vector3(1.1, 2.0, 0.8), _mat(Color(0.85, 0.86, 0.86), "metal", 0.4), true)
		_box(Vector3(x, 1.05, z_back + 0.86), Vector3(0.95, 1.7, 0.02), world._glow(Color(0.75, 0.9, 1.0), 0.6))
	_counter(Vector3(door_x - 2.4, 0, z_front - 2.4), 2.4, 0.8, false, _mat(Color(0.2, 0.4, 0.3), "panel"), _mat(Color(0.85, 0.85, 0.8)))
	_box(Vector3(door_x - 2.4, 1.2, z_front - 2.9), Vector3(0.45, 0.3, 0.4), _mat(Color(0.2, 0.2, 0.22), "", 0.5))
	_box(Vector3(door_x - 2.4, 1.3, z_front - 1.8), Vector3(0.5, 0.5, 0.6), world._glow(Color(1.0, 0.25, 0.2), 0.6))


## Midtown Garage: a working body shop behind a roll-up door. A two-post lift, tool
## benches, stacked tyres, and a car on the bay (a real one: drive it out).
func _furnish_garage() -> void:
	var yellow: StandardMaterial3D = _mat(Color(0.9, 0.72, 0.12), "", 0.5)
	var lift: Vector3 = Vector3(-hw * 0.55, 0, lerpf(z_back, z_front, 0.4))
	for side: float in [-1.0, 1.0]:
		_box(lift + Vector3(side * 1.6, 1.6, 0), Vector3(0.35, 3.2, 0.35), yellow, true)
		_box(lift + Vector3(side * 1.1, 0.35, 0.6), Vector3(1.0, 0.1, 0.12), _steel())
		_box(lift + Vector3(side * 1.1, 0.35, -0.6), Vector3(1.0, 0.1, 0.12), _steel())
	_box(lift + Vector3(0, 3.25, 0), Vector3(3.6, 0.2, 0.3), yellow)
	for index: int in range(3):
		var bench: Vector3 = Vector3(hw - 0.6, 0, z_back + 1.5 + index * 2.4)
		_box(bench + Vector3(0, 0.45, 0), Vector3(1.0, 0.9, 2.0), _mat(Color(0.7, 0.12, 0.1), "metal", 0.5), true)
		_box(bench + Vector3(0, 0.93, 0), Vector3(1.05, 0.06, 2.05), _mat(Color(0.3, 0.3, 0.3), "metal", 0.4))
	_box(Vector3(hw - 0.08, 2.0, z_back + 4.0), Vector3(0.05, 1.2, 4.5), _mat(Color(0.35, 0.36, 0.34), "metal"))
	for stack: Vector3 in [Vector3(-hw + 0.8, 0, z_back + 0.8), Vector3(-hw + 0.8, 0, z_back + 2.0), Vector3(-hw + 2.0, 0, z_back + 0.8)]:
		for level: int in range(4):
			world._mesh_at(MeshKit.torus(0.18, 0.36, 14, 6), _p(stack + Vector3(0, 0.12 + level * 0.24, 0)), _mat(Color(0.07, 0.07, 0.08)), yaw)
		_solid(stack + Vector3(0, 0.5, 0), Vector3(0.75, 1.0, 0.75))
	for spot: Vector3 in [Vector3(-1.0, 0.03, -2.0), Vector3(1.5, 0.03, 1.5)]:
		var stain: MeshInstance3D = world._mesh_at(MeshKit.cylinder(0.8, 0.8, 0.005, 14), _p(spot), _mat(Color(0.12, 0.12, 0.12), "", 0.2), yaw)
		stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The customer's car sits in the entry bay, nose to the shutter.
	var front: Vector3 = spec["front"]
	world._car_prop(_p(Vector3(door_x, 0.03, z_front - 4.5)), atan2(-front.x, -front.z), Color(0.55, 0.12, 0.1), "coupe", "GARAGE COUPE")


## Suds Laundromat: a row of front-loaders, stacked dryers, a folding table and plastic
## chairs, and a vending machine humming in the corner.
func _furnish_laundry() -> void:
	var enamel: StandardMaterial3D = _mat(Color(0.92, 0.93, 0.92), "", 0.4)
	var porthole: StandardMaterial3D = _mat(Color(0.15, 0.2, 0.25), "", 0.1)
	var washers: int = int((hw * 2.0 - 3.0) / 0.8)
	_solid(Vector3(0, 0.5, z_back + 0.45), Vector3(washers * 0.8, 1.0, 0.8))
	for index: int in range(washers):
		var x: float = -washers * 0.4 + 0.4 + index * 0.8
		_box(Vector3(x, 0.5, z_back + 0.45), Vector3(0.74, 1.0, 0.76), enamel)
		world._mesh_at(MeshKit.cylinder(0.22, 0.22, 0.04, 16), _p(Vector3(x, 0.52, z_back + 0.84)), porthole, yaw, Vector3(PI * 0.5, 0, 0))
	for level: int in range(2):
		for index: int in range(5):
			var z: float = lerpf(z_back, z_front, 0.3) + index * 0.8
			_box(Vector3(-hw + 0.45, 0.5 + level * 1.0, z), Vector3(0.8, 0.95, 0.74), enamel)
			world._mesh_at(MeshKit.cylinder(0.24, 0.24, 0.04, 16), _p(Vector3(-hw + 0.87, 0.52 + level * 1.0, z)), porthole, yaw, Vector3(0, 0, PI * 0.5))
	_solid(Vector3(-hw + 0.45, 1.0, lerpf(z_back, z_front, 0.3) + 1.6), Vector3(0.8, 2.0, 4.0))
	_box(Vector3(hw * 0.2, 0.45, lerpf(z_back, z_front, 0.5)), Vector3(3.0, 0.9, 1.0), _mat(Color(0.8, 0.78, 0.72), "", 0.6), true)
	for index: int in range(4):
		_chair(Vector3(-hw * 0.2 + index * 0.6, 0, z_front - 2.5), false, Color(0.2, 0.55, 0.75))
	var vend: Vector3 = Vector3(hw - 0.6, 0, z_back + 1.0)
	_box(vend + Vector3(0, 0.95, 0), Vector3(0.9, 1.9, 0.8), _mat(Color(0.75, 0.12, 0.1), "", 0.5), true)
	_box(vend + Vector3(-0.46, 1.2, 0), Vector3(0.02, 1.0, 0.6), world._glow(Color(1.0, 0.9, 0.8), 0.9))



# --- Trade dressing (docs/INTERIOR_PROPS.md) ------------------------------------------------------
## Small collision-free props that say what the business is. They go into a "Props" child node
## that is merged per material, drawn within PROP_RANGE on the interior layer, shadowless, and in the
## "potato_optional" group (world.set_potato_mode hides it). No RNG: the city's seeded generation
## is unchanged. Nothing here collides, so routes and cover are the same with or without it.
const PROP_RANGE: float = 34.0


func _dress(node: Node3D) -> Node3D:
	var props: Node3D = Node3D.new()
	props.name = "Props"
	node.add_child(props)
	world._target = props
	_wall_dressing()
	var method: String = "_props_" + kind
	if has_method(method):
		call(method)
	world._target = node
	return props


func _finish_props(props: Node3D) -> void:
	world._batch_static_meshes(props)
	world.MeshMerge.merge_children(props)
	for child: Node in props.get_children():
		if child is GeometryInstance3D:
			var geometry: GeometryInstance3D = child as GeometryInstance3D
			geometry.layers = 1 << (world.INTERIOR_LAYER - 1)
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			geometry.visibility_range_end = PROP_RANGE
			geometry.visibility_range_end_margin = 3.0
	props.add_to_group("potato_optional")
	props.set_meta("prop_node", true)


## Every room: a wall clock and a 1999 calendar on the left wall, a notice board on the right.
func _wall_dressing() -> void:
	var mid_z: float = (z_front + z_back) * 0.5
	var paper: StandardMaterial3D = _mat(Color(0.95, 0.94, 0.9), "", 0.9)
	_box(Vector3(-hw + 0.05, 2.9, mid_z - 1.0), Vector3(0.04, 0.38, 0.38), _mat(Color(0.1, 0.1, 0.1), "", 0.4))
	_box(Vector3(-hw + 0.075, 2.9, mid_z - 1.0), Vector3(0.02, 0.32, 0.32), paper)
	_box(Vector3(-hw + 0.05, 1.85, mid_z + 1.4), Vector3(0.02, 0.5, 0.36), paper)
	_box(Vector3(-hw + 0.06, 2.02, mid_z + 1.4), Vector3(0.02, 0.18, 0.34), _mat(Color(0.3, 0.5, 0.7), "", 0.8))
	_box(Vector3(hw - 0.05, 1.8, mid_z + 2.2), Vector3(0.04, 0.8, 1.2), _mat(Color(0.6, 0.45, 0.3), "", 0.9))
	for index: int in range(5):
		var colors: Array = [Color(0.95, 0.94, 0.9), Color(0.95, 0.85, 0.4), Color(0.6, 0.8, 0.95), Color(0.95, 0.94, 0.9), Color(0.95, 0.6, 0.6)]
		_box(Vector3(hw - 0.075, 1.65 + (index % 2) * 0.3, mid_z + 1.8 + index * 0.2), Vector3(0.01, 0.22, 0.17), _mat(colors[index], "", 0.9))


func _binders(centre: Vector3, count: int, along_x: bool) -> void:
	var colors: Array = [Color(0.12, 0.2, 0.45), Color(0.1, 0.1, 0.1), Color(0.55, 0.1, 0.1), Color(0.85, 0.85, 0.8), Color(0.2, 0.4, 0.25)]
	for index: int in range(count):
		var offset: float = (index - count * 0.5) * 0.07
		_box(centre + (Vector3(offset, 0, 0) if along_x else Vector3(0, 0, offset)), Vector3(0.06, 0.3, 0.26) if along_x else Vector3(0.26, 0.3, 0.06), _mat(colors[index % colors.size()], "", 0.7))


## Offices (exchange, imports, logistics, authority, freight): a wall shelf of binders and archive
## boxes on the right wall, a fax and phone on a side table by it.
func _office_wall() -> void:
	var mid_z: float = (z_front + z_back) * 0.5
	var x: float = hw - 0.2
	_box(Vector3(x, 1.95, mid_z - 1.6), Vector3(0.3, 0.03, 2.0), _wood())
	_binders(Vector3(x, 2.12, mid_z - 2.0), 9, false)
	for index: int in range(2):
		_box(Vector3(x, 2.1, mid_z - 1.0 + index * 0.38), Vector3(0.28, 0.26, 0.34), _mat(Color(0.8, 0.72, 0.55), "", 0.9))


func _props_exchange() -> void:
	_office_wall()


func _props_imports() -> void:
	_office_wall()


func _props_logistics() -> void:
	_office_wall()


func _props_authority() -> void:
	_office_wall()


func _props_freight() -> void:
	_office_wall()


func _props_bar() -> void:
	var bar_z: float = z_back + 3.2
	var bar_length: float = hw * 2.0 - 7.0
	var bar_x: float = hw - bar_length * 0.5 - 1.0
	var top: float = 1.1 + 0.06
	var glass: StandardMaterial3D = _mat(Color(0.75, 0.85, 0.9), "", 0.05)
	var beer: StandardMaterial3D = _mat(Color(0.85, 0.55, 0.12), "", 0.2)
	var ash: StandardMaterial3D = _mat(Color(0.2, 0.2, 0.22), "", 0.6)
	for index: int in range(int(bar_length / 1.1)):
		var x: float = bar_x - bar_length * 0.5 + 0.6 + index * 1.1
		_box(Vector3(x, top + 0.07, bar_z + 0.15), Vector3(0.08, 0.14, 0.08), beer if index % 2 == 0 else glass)
		if index % 3 == 0:
			_box(Vector3(x + 0.35, top + 0.02, bar_z + 0.1), Vector3(0.14, 0.04, 0.14), ash)
	for index: int in range(3):
		var booth: Vector3 = Vector3(-hw + 1.0, 0, z_back + 4.5 + index * 3.4)
		_box(booth + Vector3(0.4, 0.83, -0.2), Vector3(0.08, 0.12, 0.08), beer)
		_box(booth + Vector3(0.5, 0.79, 0.25), Vector3(0.14, 0.04, 0.14), ash)
	var pool: Vector3 = Vector3(hw * 0.2, 0, lerpf(z_back, z_front, 0.62))
	var balls: Array = [Color(0.95, 0.95, 0.9), Color(0.9, 0.75, 0.1), Color(0.1, 0.2, 0.7), Color(0.8, 0.1, 0.1), Color(0.4, 0.1, 0.5), Color(0.9, 0.45, 0.1), Color(0.1, 0.1, 0.1)]
	for index: int in range(7):
		_box(pool + Vector3(-0.3 + (index % 3) * 0.25, 0.87, -0.5 + float(index / 3) * 0.45), Vector3(0.06, 0.06, 0.06), _mat(balls[index], "", 0.2))
	_box(pool + Vector3(0.45, 0.87, 0.2), Vector3(0.03, 0.03, 1.4), _wood())


func _props_hotel() -> void:
	var top: float = 1.1 + 0.07
	_box(Vector3(1.5, top + 0.04, z_back + 4.0), Vector3(0.12, 0.08, 0.12), _mat(Color(0.82, 0.66, 0.32), "", 0.3))
	for index: int in range(6):
		var colors: Array = [Color(0.2, 0.55, 0.75), Color(0.95, 0.75, 0.2), Color(0.85, 0.3, 0.2), Color(0.3, 0.6, 0.35), Color(0.9, 0.9, 0.85), Color(0.55, 0.3, 0.6)]
		_box(Vector3(2.6 + (index % 3) * 0.14, top + 0.08 + float(index / 3) * 0.1, z_back + 4.2), Vector3(0.1, 0.16, 0.01), _mat(colors[index], "", 0.8))
	_box(Vector3(0.5, top + 0.01, z_back + 4.0), Vector3(0.5, 0.02, 0.35), _mat(Color(0.2, 0.25, 0.4), "", 0.7))
	var cart: Vector3 = Vector3(hw * 0.5, 0, z_front - 3.0)
	_box(cart + Vector3(0, 1.05, -0.2), Vector3(0.5, 0.35, 0.25), _mat(Color(0.12, 0.12, 0.14), "", 0.8))


func _props_pawn() -> void:
	var case_z: float = z_back + 3.5
	var gold: StandardMaterial3D = _mat(Color(0.9, 0.72, 0.3), "", 0.2)
	var silver: StandardMaterial3D = _mat(Color(0.78, 0.8, 0.82), "", 0.2)
	var black: StandardMaterial3D = _mat(Color(0.08, 0.08, 0.09), "", 0.5)
	var tag: StandardMaterial3D = _mat(Color(0.96, 0.95, 0.88), "", 0.8)
	var length: float = hw * 1.4
	for index: int in range(int(length / 0.45)):
		var x: float = -length * 0.5 + 0.3 + index * 0.45
		var item: StandardMaterial3D = [gold, silver, black][index % 3]
		_box(Vector3(x, 0.88, case_z), Vector3(0.12, 0.03 if index % 3 != 2 else 0.1, 0.12 if index % 3 != 2 else 0.16), item)
		_box(Vector3(x + 0.1, 0.87, case_z + 0.15), Vector3(0.06, 0.005, 0.035), tag)
	for index: int in range(4):
		_box(Vector3(-hw * 0.5 + index * 0.9, 2.9, z_back + 0.08), Vector3(0.5, 0.35, 0.04), [black, silver, gold, black][index])


func _props_cafe() -> void:
	var counter_z: float = z_back + 2.2
	var top: float = 1.05 + 0.06
	var cup: StandardMaterial3D = _mat(Color(0.95, 0.94, 0.9), "", 0.5)
	var coffee: StandardMaterial3D = _mat(Color(0.12, 0.06, 0.03), "", 0.2)
	for index: int in range(6):
		_box(Vector3(hw * 0.5 + 0.5 + (index % 3) * 0.12, top + 0.04 + float(index / 3) * 0.08, counter_z + 0.05), Vector3(0.09, 0.08, 0.09), cup)
	var pastries: Array = [Color(0.85, 0.6, 0.3), Color(0.95, 0.9, 0.7), Color(0.6, 0.35, 0.15)]
	for index: int in range(8):
		_box(Vector3(-hw * 0.15 - 0.6 + index * 0.17, 1.12, counter_z + 0.1), Vector3(0.12, 0.05, 0.1), _mat(pastries[index % 3], "", 0.7))
	for spot: Vector2 in [Vector2(-hw * 0.6, 0.45), Vector2(-hw * 0.15, 0.55), Vector2(hw * 0.35, 0.5), Vector2(-hw * 0.6, 0.75), Vector2(hw * 0.5, 0.78)]:
		var table: Vector3 = Vector3(spot.x, 0, lerpf(z_back, z_front, spot.y))
		_box(table + Vector3(0.1, 0.8, -0.1), Vector3(0.09, 0.08, 0.09), cup)
		_box(table + Vector3(0.1, 0.835, -0.1), Vector3(0.07, 0.006, 0.07), coffee)
		_box(table + Vector3(-0.12, 0.79, 0.1), Vector3(0.05, 0.06, 0.05), _mat(Color(0.95, 0.95, 0.95), "", 0.4))
		_box(table + Vector3(-0.2, 0.765, -0.15), Vector3(0.2, 0.01, 0.2), cup)


func _props_store() -> void:
	# Cigarette rack over the till, candy on the counter front, newspapers by the door.
	var cx: float = door_x - 2.4
	var cz: float = z_front - 2.4
	var packs: Array = [Color(0.85, 0.1, 0.1), Color(0.95, 0.95, 0.9), Color(0.2, 0.4, 0.2), Color(0.2, 0.3, 0.7), Color(0.9, 0.75, 0.2)]
	_box(Vector3(cx - 0.9, 2.2, cz), Vector3(0.2, 0.9, 1.6), _mat(Color(0.2, 0.2, 0.22), "", 0.6))
	for row: int in range(4):
		for column: int in range(8):
			_box(Vector3(cx - 0.79, 1.85 + row * 0.2, cz - 0.7 + column * 0.2), Vector3(0.02, 0.12, 0.08), _mat(packs[(row + column) % packs.size()], "", 0.7))
	for index: int in range(10):
		_box(Vector3(cx + 0.1, 1.12, cz - 0.9 + index * 0.18), Vector3(0.12, 0.04, 0.15), _mat(packs[index % packs.size()], "", 0.6))
	for index: int in range(3):
		_box(Vector3(cx + 0.6, 0.32 + index * 0.03, cz + 1.6), Vector3(0.4, 0.03, 0.32), _mat(Color(0.88, 0.87, 0.82), "", 0.9))


func _props_garage() -> void:
	# Tools on the pegboard over the benches, oil cans and a parts box on the bench tops.
	var steel: StandardMaterial3D = _mat(Color(0.6, 0.62, 0.64), "", 0.3)
	var red: StandardMaterial3D = _mat(Color(0.75, 0.12, 0.1), "", 0.5)
	for index: int in range(12):
		var z: float = z_back + 2.0 + index * 0.35
		_box(Vector3(hw - 0.12, 1.9 + (index % 3) * 0.3, z), Vector3(0.03, 0.28 - (index % 2) * 0.1, 0.05), steel if index % 4 != 0 else red)
	for index: int in range(3):
		var bench: Vector3 = Vector3(hw - 0.6, 0, z_back + 1.5 + index * 2.4)
		_box(bench + Vector3(0, 1.06, -0.5), Vector3(0.12, 0.2, 0.12), _mat(Color(0.9, 0.75, 0.15), "", 0.5))
		_box(bench + Vector3(0, 1.06, -0.3), Vector3(0.12, 0.2, 0.12), _mat(Color(0.2, 0.3, 0.6), "", 0.5))
		_box(bench + Vector3(0, 1.02, 0.4), Vector3(0.4, 0.12, 0.3), red)


func _props_laundry() -> void:
	# Detergent boxes on the washers, a basket and folded laundry on the folding table.
	var washers: int = int((hw * 2.0 - 3.0) / 0.8)
	var soap: Array = [Color(0.95, 0.5, 0.1), Color(0.2, 0.45, 0.85), Color(0.95, 0.95, 0.9)]
	for index: int in range(0, washers, 3):
		var x: float = -washers * 0.4 + 0.4 + index * 0.8
		_box(Vector3(x, 1.12, z_back + 0.4), Vector3(0.22, 0.24, 0.12), _mat(soap[index % 3], "", 0.7))
	var table: Vector3 = Vector3(hw * 0.2, 0, lerpf(z_back, z_front, 0.5))
	_box(table + Vector3(-0.8, 1.05, 0), Vector3(0.6, 0.3, 0.45), _mat(Color(0.3, 0.55, 0.8), "", 0.7))
	for index: int in range(4):
		_box(table + Vector3(0.2 + index * 0.35, 0.94 + (index % 2) * 0.03, 0.1), Vector3(0.3, 0.06 + (index % 2) * 0.03, 0.3), _mat([Color(0.95, 0.94, 0.9), Color(0.6, 0.2, 0.2), Color(0.3, 0.35, 0.5), Color(0.9, 0.85, 0.6)][index], "", 0.9))
