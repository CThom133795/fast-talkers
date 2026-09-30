extends RefCounted
## CREW HQS. The four crew headquarters as walk-in compounds (replacing the solid `_tower` shells that
## used to stand on these footprints): Morris Social Club, the Kojimoto Building, the Sol Negro hacienda
## and the Kingsway Courts community room. Each has a ground-floor interior (the upper storeys stay a
## solid mass with the old tower's windows, so the skyline and the street layout do not change), at
## least two exterior doors, a main room with the crew's spawn line, lockers and a gun rack by the door
## (the buy phase happens there), a desk that holds the crew phone, a war table with a map of the city,
## a few themed rooms and signage in the crew's colour.
##
## Frame (BuildingKit): +Z = out of the front door, +X along the facade; the plot is the old tower's
## footprint. `world._crew_compound` builds one from inside a district and returns the world-space spawn
## data: {hq, spawn, phone, door}. The spawn line: online.gd spreads up to eight crewmates across the
## room sideways from `spawn` (0, +-1.4, +-2.8, +-4.2, +-5.6 m), so that strip is always open floor. The crew
## phone is placed by online.gd 3.2 m along that line and 0.3 m above `spawn`, so each compound has a
## narrow phone table exactly there (see `_phone_table`) and its spawn point is lifted to match.
##
## Collision is only what you see for furniture that can be cover (tables, counters, sofas, lockers,
## machines); chairs, stools, cushions and small dressing are visual, and the dressing is merged into
## the props node (kit.finish_props) that potato mode hides.

const Kit = preload("res://scripts/buildings/building_kit.gd")
const Factions = preload("res://scripts/factions.gd")

## Interior floor top (just above the 0.16 m block plinth), ceiling underside and storey top (slab top).
const F: float = 0.17
const CEIL: float = 4.3
const STOREY: float = 4.6
## Thickness of the visual wall skin inside the shell.
const SKIN: float = 0.08
## The hq (delivery point) sits this far inside the front door's wall line, the spawn 2.5 m further in.
const HQ_IN: float = 1.7
const SPAWN_IN: float = 4.2
## Sideways offsets of the eight spawn slots, for the tests (see online.gd `_apply_my_crew`).
const SLOT_STEP: float = 1.4
const DOOR_H: float = 2.6

const TITLES: Dictionary = {
	"morris": {"node": "MorrisClub", "name": "MORRIS SOCIAL CLUB"},
	"kojimoto": {"node": "KojimotoBuilding", "name": "KOJIMOTO BUILDING"},
	"solnegro": {"node": "SolNegroHacienda", "name": "SOL NEGRO HACIENDA"},
	"kingsway": {"node": "KingswayCourts", "name": "KINGSWAY COURTS"},
}


static func title(crew: String) -> String:
	return str(TITLES[crew]["name"])


## Builds crew `crew`'s compound on `plot` ({center, size (frontage, depth), height, front, district}, world
## space) and returns {hq, spawn, phone, door} in world space.
static func build(world: Node3D, crew: String, plot: Dictionary) -> Dictionary:
	var kit: Kit = Kit.new(world, str(TITLES[crew]["node"]), plot)
	var p: Dictionary = _palette(kit, crew, float(plot["height"]))
	var info: Dictionary = {}
	match crew:
		"morris":
			info = _morris(kit, p)
		"kojimoto":
			info = _kojimoto(kit, p)
		"solnegro":
			info = _solnegro(kit, p)
		_:
			info = _kingsway(kit, p)
	kit.finish_props()
	kit.finish()
	kit.node.set_meta("walk_in", true)
	kit.node.set_meta("interior_half", kit.size * 0.5)
	kit.node.set_meta("crew_hq", crew)
	kit.node.set_meta("routes", info["routes"])
	var out: Vector3 = (kit.node.transform.basis * Vector3.BACK).normalized()
	return {"hq": kit.to_world(info["hq"]), "spawn": kit.to_world(info["spawn"]), "phone": kit.to_world(info["phone"]), "door": out, "node": kit.node}


# --- Palette --------------------------------------------------------------------------------------

static func _palette(kit: Kit, crew: String, height: float) -> Dictionary:
	var accent: Color = Factions.color(crew)
	var p: Dictionary = {"crew": crew, "height": height}
	p["accent"] = kit.mat(accent, "", 0.55)
	p["accent_dark"] = kit.mat(accent.darkened(0.5), "", 0.65)
	p["glow_accent"] = kit.glow(accent.lightened(0.2), 1.5)
	p["concrete"] = kit.mat(Color(0.34, 0.33, 0.32), "tiles", 0.95)
	p["roof_slab"] = kit.mat(Color(0.22, 0.23, 0.23), "roof")
	p["steel"] = kit.mat(Color(0.55, 0.57, 0.59), "metal", 0.35)
	p["locker"] = kit.mat(Color(0.36, 0.4, 0.42), "metal", 0.45)
	p["locker_door"] = kit.mat(Color(0.46, 0.5, 0.52), "metal", 0.4)
	p["black"] = kit.mat(Color(0.07, 0.07, 0.08), "", 0.5)
	p["white"] = kit.mat(Color(0.9, 0.88, 0.82), "", 0.8)
	p["wood"] = kit.mat(Color(0.42, 0.26, 0.14), "planks", 0.6)
	p["dark"] = kit.mat(Color(0.2, 0.12, 0.08), "planks", 0.55)
	p["paper"] = kit.mat(Color(0.93, 0.9, 0.8), "", 0.9)
	p["brass"] = kit.mat(Color(0.75, 0.6, 0.28), "metal", 0.3)
	p["glass"] = kit.mat(Color(0.62, 0.76, 0.8), "", 0.05)
	p["warm"] = kit.glow(Color(1.0, 0.85, 0.6), 1.0)
	p["leaf"] = kit.mat(Color(0.2, 0.42, 0.2), "", 0.8)
	p["pot"] = kit.mat(Color(0.55, 0.3, 0.2), "", 0.8)
	p["gun_board"] = kit.mat(Color(0.1, 0.09, 0.08), "", 0.9)
	p["frame"] = kit.mat(Color(0.7, 0.55, 0.25), "metal", 0.35)
	p["door"] = kit.mat(Color(0.2, 0.13, 0.09), "planks", 0.6)
	p["door_steel"] = kit.mat(Color(0.3, 0.32, 0.34), "metal", 0.55)
	var maps: Dictionary = _map_materials(kit)
	p["map_table"] = maps["table"]
	p["map_wall"] = maps["wall"]
	return p


## The city map: land, streets and the four crew districts (in their colours) drawn once into a small
## texture from the world's own data, shared by every HQ. A BoxMesh's UVs are a 3x2 atlas, so the table
## material maps the top face (seen from above, north up) and the wall material maps the +Z face.
static func _map_materials(kit: Kit) -> Dictionary:
	var world: Node3D = kit.world
	if world.has_meta("crew_hq_maps"):
		return world.get_meta("crew_hq_maps")
	var px: int = 160
	var bounds: Rect2 = world.map_bounds()
	var image: Image = Image.create(px, px, false, Image.FORMAT_RGB8)
	var sea: Color = Color(0.15, 0.23, 0.31)
	var land: Color = Color(0.8, 0.74, 0.56)
	var street: Color = Color(0.97, 0.96, 0.9)
	var crew_zones: Array[Dictionary] = []
	for district: Dictionary in world.districts:
		if str(district["crew"]) != "":
			crew_zones.append(district)
	for j: int in range(px):
		for i: int in range(px):
			var at: Vector2 = bounds.position + Vector2((float(i) + 0.5) / px * bounds.size.x, (float(j) + 0.5) / px * bounds.size.y)
			var color: Color = sea
			for poly: PackedVector2Array in world.land:
				if Geometry2D.is_point_in_polygon(at, poly):
					color = land
					break
			if color == land:
				for zone: Dictionary in crew_zones:
					for shape: PackedVector2Array in zone["polys"]:
						if Geometry2D.is_point_in_polygon(at, shape):
							color = land.lerp(Color(zone["color"]), 0.6)
			image.set_pixel(i, j, color)
	for road: Dictionary in world.roads:
		var points: PackedVector2Array = road["points"]
		var thick: int = maxi(1, int(round(float(road["width"]) / bounds.size.x * px)))
		for index: int in range(points.size() - 1):
			var steps: int = int(points[index].distance_to(points[index + 1]) / bounds.size.x * px * 2.0) + 1
			for step: int in range(steps + 1):
				var at: Vector2 = points[index].lerp(points[index + 1], float(step) / steps)
				var cell: Vector2 = (at - bounds.position) / bounds.size * px
				image.fill_rect(Rect2i(int(cell.x) - thick / 2, int(cell.y) - thick / 2, thick, thick), street)
	for zone: Dictionary in crew_zones:
		var sum: Vector2 = Vector2.ZERO
		var shape: PackedVector2Array = (zone["polys"] as Array)[0]
		for point: Vector2 in shape:
			sum += point
		var cell: Vector2 = (sum / shape.size() - bounds.position) / bounds.size * px
		image.fill_rect(Rect2i(int(cell.x) - 3, int(cell.y) - 3, 7, 7), Color(0.95, 0.95, 0.92))
		image.fill_rect(Rect2i(int(cell.x) - 2, int(cell.y) - 2, 5, 5), Color(zone["color"]))
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	var table: StandardMaterial3D = StandardMaterial3D.new()
	table.albedo_texture = texture
	table.roughness = 0.9
	table.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	table.uv1_scale = Vector3(-3.0, -2.0, 1.0)
	table.uv1_offset = Vector3(2.0, 2.0, 0.0)
	var wall: StandardMaterial3D = StandardMaterial3D.new()
	wall.albedo_texture = texture
	wall.roughness = 0.9
	wall.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	wall.uv1_scale = Vector3(3.0, 2.0, 1.0)
	var maps: Dictionary = {"table": table, "wall": wall}
	world.set_meta("crew_hq_maps", maps)
	return maps


# --- Shell ----------------------------------------------------------------------------------------

static func _op(pos: float, width: float, sill: float = 0.0, top: float = DOOR_H, kind: String = "door") -> Dictionary:
	return {"pos": pos, "width": width, "sill": sill, "top": top, "kind": kind}


static func _win(pos: float, width: float = 2.2) -> Dictionary:
	return _op(pos, width, 0.9, 2.45, "window")


## `pos` (a coordinate along the wall: x for walls along X, z for walls along Z) -> Kit openings.
static func _openings(a: Vector2, b: Vector2, ops: Array, as_gaps: bool = false) -> Array:
	var horizontal: bool = absf(b.x - a.x) > absf(b.y - a.y)
	var start: float = a.x if horizontal else a.y
	var heading: float = signf(b.x - a.x) if horizontal else signf(b.y - a.y)
	var out: Array = []
	for op: Dictionary in ops:
		var kind: String = str(op["kind"])
		if as_gaps and kind == "window":
			kind = "gap"
		out.append(Kit.opening((float(op["pos"]) - start) * heading, float(op["width"]), float(op["sill"]), float(op["top"]), kind))
	return out


static func _wall(kit: Kit, a: Vector2, b: Vector2, height: float, material: Material, ops: Array = [], base: float = 0.0, thickness: float = Kit.WALL) -> void:
	kit.wall(a, b, height, material, _openings(a, b, ops), base, thickness)


## A solid interior partition from floor to ceiling with doorless openings (kind "gap").
static func _part(kit: Kit, a: Vector2, b: Vector2, material: Material, ops: Array = []) -> void:
	_wall(kit, a, b, CEIL - F, material, ops, F, 0.2)


## A visual-only skin on a wall line between heights y0 and y1 (absolute), leaving the openings clear.
static func _skin(kit: Kit, a: Vector2, b: Vector2, y0: float, y1: float, material: Material, ops: Array, thick: float = SKIN) -> void:
	var span: Vector2 = b - a
	var length: float = span.length()
	var direction: Vector2 = span / length
	var angle: float = atan2(direction.x, direction.y)
	var sorted: Array = _openings(a, b, ops, true)
	sorted.sort_custom(func(m: Dictionary, n: Dictionary) -> bool: return float(m["at"]) < float(n["at"]))
	var cursor: float = 0.0
	for spec: Dictionary in sorted:
		var s0: float = clampf(float(spec["at"]) - float(spec["width"]) * 0.5, 0.0, length)
		var s1: float = clampf(float(spec["at"]) + float(spec["width"]) * 0.5, 0.0, length)
		if s0 > cursor + 0.01:
			_strip(kit, a, direction, angle, cursor, s0, y0, y1, material, thick)
		if float(spec["sill"]) > y0 + 0.01:
			_strip(kit, a, direction, angle, s0, s1, y0, minf(float(spec["sill"]), y1), material, thick)
		if float(spec["top"]) < y1 - 0.01:
			_strip(kit, a, direction, angle, s0, s1, maxf(float(spec["top"]), y0), y1, material, thick)
		cursor = maxf(cursor, s1)
	if cursor < length - 0.01:
		_strip(kit, a, direction, angle, cursor, length, y0, y1, material, thick)


static func _strip(kit: Kit, a: Vector2, direction: Vector2, angle: float, s0: float, s1: float, y0: float, y1: float, material: Material, thick: float) -> void:
	if s1 - s0 < 0.01 or y1 - y0 < 0.01:
		return
	var mid: Vector2 = a + direction * ((s0 + s1) * 0.5)
	kit.box(Vector3(mid.x, (y0 + y1) * 0.5, mid.y), Vector3(thick, y1 - y0, s1 - s0), material, false, angle)


## The shell on the old tower's footprint: floor, the ground storey's four walls with their openings (cfg
## front/back/west/east), the ceiling slab, and one solid mass for the upper storeys with the old tower's
## window grid and roof cap.
static func _shell(kit: Kit, p: Dictionary, cfg: Dictionary) -> void:
	var half: Vector2 = kit.size * 0.5
	var height: float = float(p["height"])
	var rect: Rect2 = Rect2(-half, half * 2.0)
	kit.footprint(rect)
	kit.floor_slab(rect, F, p["concrete"])
	kit.floor_slab(rect, STOREY, p["roof_slab"])
	var cx: float = half.x - 0.15
	var cz: float = half.y - 0.15
	var outer: Material = cfg["outer"]
	_wall(kit, Vector2(-cx, cz), Vector2(cx, cz), STOREY, outer, cfg["front"])
	_wall(kit, Vector2(-cx, -cz), Vector2(cx, -cz), STOREY, outer, cfg["back"])
	_wall(kit, Vector2(-cx, -cz), Vector2(-cx, cz), STOREY, outer, cfg["west"])
	_wall(kit, Vector2(cx, -cz), Vector2(cx, cz), STOREY, outer, cfg["east"])
	var mass: float = height - STOREY
	kit.box(Vector3(0, STOREY + mass * 0.5, 0), Vector3(half.x * 2.0, mass, half.y * 2.0), outer, true)
	kit.box(Vector3(0, height + 0.16, 0), Vector3(half.x * 2.0 + 0.45, 0.32, half.y * 2.0 + 0.45), cfg["roof"])
	var first_y: float = 6.2
	var rows: int = int((height - 1.2 - first_y) / 3.1) + 1
	var lit: float = float(cfg.get("lit", 0.4))
	kit.window_grid(Vector3(-half.x, 0, half.y), Vector3.RIGHT, Vector3.BACK, half.x * 2.0, first_y, rows, 3.1, 3.4, lit)
	kit.window_grid(Vector3(-half.x, 0, -half.y), Vector3.RIGHT, Vector3.FORWARD, half.x * 2.0, first_y, rows, 3.1, 3.4, lit)
	kit.window_grid(Vector3(half.x, 0, -half.y), Vector3.BACK, Vector3.RIGHT, half.y * 2.0, first_y, rows, 3.1, 3.4, lit)
	kit.window_grid(Vector3(-half.x, 0, -half.y), Vector3.BACK, Vector3.LEFT, half.y * 2.0, first_y, rows, 3.1, 3.4, lit)


## Door leaf and a timber surround on the outside of the wall line.
static func _door(kit: Kit, p: Dictionary, at: Vector3, width: float, out: Vector3, label: String, leaf: String = "door") -> void:
	kit.add_door(Vector3(at.x, F, at.z), width, DOOR_H, out, label, "door", p[leaf])
	var yaw: float = atan2(out.x, out.z)
	var trim: Material = p["trim"]
	var basis: Basis = Basis(Vector3.UP, yaw)
	for side: float in [-1.0, 1.0]:
		var jamb: Vector3 = Vector3(at.x, 0, at.z) + basis * Vector3(side * (width * 0.5 + 0.07), 0, 0.12)
		kit.box(Vector3(jamb.x, DOOR_H * 0.5 + 0.05, jamb.z), Vector3(0.14, DOOR_H + 0.1, 0.42), trim, false, yaw)
	var head: Vector3 = Vector3(at.x, 0, at.z) + basis * Vector3(0, 0, 0.12)
	kit.box(Vector3(head.x, DOOR_H + 0.12, head.z), Vector3(width + 0.42, 0.16, 0.42), trim, false, yaw)


## Wall skin, wainscot line, skirting, crown and ceiling on the interior layer (call after begin_interior).
static func _lining(kit: Kit, p: Dictionary, cfg: Dictionary) -> void:
	var half: Vector2 = kit.size * 0.5
	var lx: float = half.x - 0.34
	var lz: float = half.y - 0.34
	var runs: Array = [
		[Vector2(-lx, lz), Vector2(lx, lz), cfg["front"]], [Vector2(-lx, -lz), Vector2(lx, -lz), cfg["back"]],
		[Vector2(-lx, -lz), Vector2(-lx, lz), cfg["west"]], [Vector2(lx, -lz), Vector2(lx, lz), cfg["east"]]]
	for run: Array in runs:
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var ops: Array = run[2]
		_skin(kit, a, b, F, CEIL, cfg["plaster"], ops)
		_skin(kit, a, b, F, F + 0.14, cfg["trim"], ops, 0.12)
		_skin(kit, a, b, 1.0, 1.1, p["accent"], ops, 0.1)
		_skin(kit, a, b, CEIL - 0.1, CEIL, cfg["trim"], [], 0.12)
	kit.box(Vector3(0, CEIL - 0.01, 0), Vector3(half.x * 2.0 - 0.6, 0.02, half.y * 2.0 - 0.6), cfg["ceiling"])


## A thin finish over part of the floor (wood, tile, carpet, a rug).
static func _floor(kit: Kit, rect: Rect2, material: Material, lift: float = 0.0) -> void:
	var c: Vector2 = rect.get_center()
	kit.box(Vector3(c.x, F + 0.006 + lift, c.y), Vector3(rect.size.x, 0.012, rect.size.y), material, false)


# --- Furniture ------------------------------------------------------------------------------------

## A box placed in a furniture piece's own frame: `at` the piece's origin on the floor, `yaw` its turn,
## (dx, dz) the offset in that frame, `y0` the height of the box's bottom above the floor.
static func _o(kit: Kit, at: Vector2, yaw: float, dx: float, dz: float, y0: float, w: float, h: float, d: float, material: Material, solid: bool = false) -> void:
	var turned: Vector3 = Basis(Vector3.UP, yaw) * Vector3(dx, 0.0, dz)
	kit.box(Vector3(at.x + turned.x, F + y0 + h * 0.5, at.y + turned.z), Vector3(w, h, d), material, solid, yaw)


static func _chair(kit: Kit, p: Dictionary, x: float, z: float, yaw: float, tone: String = "dark") -> void:
	var m: Material = p[tone]
	var at: Vector2 = Vector2(x, z)
	_o(kit, at, yaw, 0, 0, 0.44, 0.44, 0.05, 0.44, m)
	_o(kit, at, yaw, 0, -0.2, 0.49, 0.44, 0.5, 0.05, m)
	for lx: float in [-0.18, 0.18]:
		for lz: float in [-0.18, 0.18]:
			_o(kit, at, yaw, lx, lz, 0.0, 0.04, 0.44, 0.04, m)


static func _stool(kit: Kit, p: Dictionary, x: float, z: float, tone: String = "leather", height: float = 0.68) -> void:
	var at: Vector2 = Vector2(x, z)
	_o(kit, at, 0.0, 0, 0, height - 0.06, 0.36, 0.07, 0.36, p[tone])
	_o(kit, at, 0.0, 0, 0, 0.04, 0.06, height - 0.1, 0.06, p["steel"])
	_o(kit, at, 0.0, 0, 0, 0.0, 0.3, 0.04, 0.3, p["steel"])


## A table: solid top, visual apron and legs.
static func _table(kit: Kit, p: Dictionary, x: float, z: float, yaw: float, w: float, d: float, h: float, top: String = "wood", leg: String = "dark") -> void:
	var at: Vector2 = Vector2(x, z)
	_o(kit, at, yaw, 0, 0, h - 0.06, w, 0.06, d, p[top], true)
	_o(kit, at, yaw, 0, 0, h - 0.17, w - 0.2, 0.11, d - 0.2, p[leg])
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_o(kit, at, yaw, sx * (w * 0.5 - 0.1), sz * (d * 0.5 - 0.1), 0.0, 0.08, h - 0.17, 0.08, p[leg])


## A sofa facing the piece's +Z: solid seat and back, visual arms.
static func _sofa(kit: Kit, p: Dictionary, x: float, z: float, yaw: float, length: float, tone: String) -> void:
	var at: Vector2 = Vector2(x, z)
	var m: Material = p[tone]
	_o(kit, at, yaw, 0, 0, 0.0, length, 0.46, 0.86, m, true)
	_o(kit, at, yaw, 0, -0.33, 0.46, length, 0.52, 0.2, m, true)
	for side: float in [-1.0, 1.0]:
		_o(kit, at, yaw, side * (length * 0.5 - 0.11), 0.0, 0.46, 0.22, 0.24, 0.86, m)
	_o(kit, at, yaw, 0, 0.06, 0.46, length - 0.5, 0.1, 0.6, p["accent_dark"])


## A bank of steel lockers facing the piece's +Z with crew-coloured tops (solid body, visual doors).
static func _lockers(kit: Kit, p: Dictionary, x: float, z: float, yaw: float, count: int, each: float = 0.5, tall: float = 1.95) -> void:
	var at: Vector2 = Vector2(x, z)
	_o(kit, at, yaw, 0, 0, 0.0, count * each, tall, 0.55, p["locker"], true)
	_o(kit, at, yaw, 0, 0.0, tall - 0.12, count * each + 0.04, 0.14, 0.59, p["accent"])
	_o(kit, at, yaw, 0, 0.0, 0.0, count * each + 0.02, 0.1, 0.57, p["black"])
	for i: int in range(count):
		var dx: float = (float(i) - (count - 1) * 0.5) * each
		_o(kit, at, yaw, dx, 0.285, 0.14, each - 0.05, tall - 0.4, 0.02, p["locker_door"])
		_o(kit, at, yaw, dx + each * 0.3, 0.3, 0.95, 0.03, 0.22, 0.03, p["black"])
		for slot: float in [0.0, 0.07]:
			_o(kit, at, yaw, dx, 0.3, tall - 0.42 - slot, each - 0.18, 0.025, 0.02, p["black"])


## Guns on a dark board on the wall `z_face` (front wall: facing -1, back wall: +1); needs begin_props().
## `board` is (centre x, width); three rows of long guns and sidearms.
static func _gun_rack(kit: Kit, p: Dictionary, z_face: float, facing: float, board_x: float, board_w: float, y: float = 1.05) -> void:
	var bz: float = z_face + facing * 0.03
	kit.prop(Vector3(board_x, y + 0.65, bz), Vector3(board_w, 1.45, 0.05), p["gun_board"])
	kit.prop(Vector3(board_x, y + 1.42, bz + facing * 0.02), Vector3(board_w + 0.1, 0.06, 0.06), p["wood"])
	var front: float = z_face + facing * 0.05
	var x0: float = board_x - board_w * 0.5 + 0.12
	kit.display_gun(Vector3(x0, y + 1.22, front), "rifle", 0, facing)
	kit.display_gun(Vector3(x0 + 1.4, y + 1.22, front), "carbine", 2, facing)
	kit.display_gun(Vector3(x0, y + 0.82, front), "shotgun", 1, facing)
	kit.display_gun(Vector3(x0 + 1.4, y + 0.82, front), "lever", 0, facing)
	for index: int in range(3):
		kit.display_gun(Vector3(x0 + 0.05 + index * 0.45, y + 0.42, front), "pistol", 1 + index % 2, facing)
	kit.display_gun(Vector3(x0 + 1.5, y + 0.42, front), "revolver", 1, facing)
	kit.display_gun(Vector3(x0 + 1.9, y + 0.42, front), "revolver", 0, facing)


## A desk (top, two drawer pedestals, front panel) whose visitors stand at the piece's +Z; returns the
## desk-top centre (local, top surface height).
static func _desk(kit: Kit, p: Dictionary, x: float, z: float, yaw: float, w: float = 1.8, d: float = 0.85, tone: String = "dark") -> Vector3:
	var at: Vector2 = Vector2(x, z)
	_o(kit, at, yaw, 0, 0, 0.72, w, 0.05, d, p[tone], true)
	for side: float in [-1.0, 1.0]:
		_o(kit, at, yaw, side * (w * 0.5 - 0.27), 0.0, 0.0, 0.5, 0.72, d - 0.12, p[tone], true)
		for drawer: float in [0.12, 0.34, 0.56]:
			_o(kit, at, yaw, side * (w * 0.5 - 0.27), d * 0.5 - 0.055, drawer, 0.4, 0.17, 0.02, p["black"])
			_o(kit, at, yaw, side * (w * 0.5 - 0.27), d * 0.5 - 0.04, drawer + 0.06, 0.12, 0.03, 0.02, p["brass"])
	_o(kit, at, yaw, 0, -d * 0.5 + 0.1, 0.2, w - 1.0, 0.5, 0.03, p[tone])
	return Vector3(x, F + 0.77, z)


## A flat map sheet lying on a table top (table-top UVs, north up whatever the building's turn).
static func _map_sheet(kit: Kit, p: Dictionary, x: float, z: float, top_y: float, side: float) -> void:
	var turn: float = -kit.yaw
	kit.box(Vector3(x, F + top_y + 0.004, z), Vector3(side + 0.08, 0.008, side + 0.08), p["paper"], false, turn)
	kit.box(Vector3(x, F + top_y + 0.012, z), Vector3(side, 0.008, side), p["map_table"], false, turn)


## A map on the wall, facing the piece's +Z, bottom at y0.
static func _wall_map(kit: Kit, p: Dictionary, x: float, z: float, yaw: float, w: float, h: float, y0: float) -> void:
	var at: Vector2 = Vector2(x, z)
	_o(kit, at, yaw, 0, -0.012, y0 - 0.05, w + 0.1, h + 0.1, 0.03, p["frame"])
	_o(kit, at, yaw, 0, 0.004, y0, w, h, 0.02, p["map_wall"])


## A framed picture (visual), facing the piece's +Z.
static func _picture(kit: Kit, p: Dictionary, x: float, z: float, yaw: float, w: float, h: float, y0: float, canvas: Material) -> void:
	var at: Vector2 = Vector2(x, z)
	_o(kit, at, yaw, 0, 0, y0 - 0.04, w + 0.08, h + 0.08, 0.03, p["frame"])
	_o(kit, at, yaw, 0, 0.012, y0, w, h, 0.02, canvas)


static func _plant(kit: Kit, p: Dictionary, x: float, z: float, tall: float = 0.9) -> void:
	var at: Vector2 = Vector2(x, z)
	_o(kit, at, 0.0, 0, 0, 0.0, 0.34, 0.36, 0.34, p["pot"])
	for index: int in range(5):
		var turn: float = float(index) * 1.26
		var lean: Vector3 = Basis(Vector3.UP, turn) * Vector3(0.0, 0.0, 0.1)
		_o(kit, at + Vector2(lean.x, lean.z), turn, 0, 0, 0.36 + index * 0.05, 0.08, tall - 0.36, 0.3, p["leaf"])


## A hanging lamp (visual): cord, shade and a glowing bulb.
static func _hanging(kit: Kit, p: Dictionary, x: float, z: float, drop: float, shade: String, w: float = 0.5) -> void:
	var at: Vector2 = Vector2(x, z)
	_o(kit, at, 0.0, 0, 0, CEIL - F - drop, 0.02, drop, 0.02, p["black"])
	_o(kit, at, 0.0, 0, 0, CEIL - F - drop - 0.14, w, 0.16, w, p[shade])
	_o(kit, at, 0.0, 0, 0, CEIL - F - drop - 0.17, w * 0.6, 0.04, w * 0.6, p["warm"])


## A slow ceiling fan (visual).
static func _fan(kit: Kit, p: Dictionary, x: float, z: float, turn: float = 0.0) -> void:
	var at: Vector2 = Vector2(x, z)
	_o(kit, at, 0.0, 0, 0, CEIL - F - 0.42, 0.04, 0.32, 0.04, p["black"])
	_o(kit, at, 0.0, 0, 0, CEIL - F - 0.52, 0.22, 0.12, 0.22, p["brass"])
	for index: int in range(4):
		var angle: float = turn + index * PI * 0.5
		_o(kit, at, angle, 0, 0.62, CEIL - F - 0.5, 0.2, 0.025, 0.95, p["wood"])


## Text on a wall; `yaw` is the direction the text faces (0 = +Z, PI = -Z, PI/2 = +X).
static func _text(kit: Kit, words: String, x: float, y: float, z: float, yaw: float, size: int, color: Color) -> void:
	kit.sign_label(words, Vector3(x, y, z), size, color, yaw)


# --- Shared dressing --------------------------------------------------------------------------------

## A desk's dressing: a blotter and a beige landline (the crew phone itself rests on the phone table, see
## `_phone_table`); needs begin_props().
static func _phone_dressing(kit: Kit, p: Dictionary, desk_top: Vector3, yaw: float, side: float = 0.55) -> void:
	var basis: Basis = Basis(Vector3.UP, yaw)
	var landline: Vector3 = desk_top + basis * Vector3(side, 0.0, 0.05)
	var beige: Material = kit.mat(Color(0.8, 0.77, 0.66), "", 0.6)
	kit.prop(Vector3(landline.x, desk_top.y + 0.05, landline.z), Vector3(0.24, 0.1, 0.22), beige, yaw)
	kit.prop(Vector3(landline.x, desk_top.y + 0.115, landline.z), Vector3(0.22, 0.03, 0.07), beige, yaw)
	kit.prop(Vector3(desk_top.x, desk_top.y + 0.006, desk_top.z), Vector3(0.5, 0.012, 0.36), p["black"], yaw)


# --- The crew phone's table -------------------------------------------------------------------------
# online.gd `_host_place_phones` stands each crew's phone PHONE_SIDE m along the spawn line's right-hand side
# (footprint -X, the crew faces +Z) and PHONE_LIFT m above the spawn point, so the table is built under that
# spot and the spawn point is lifted to suit (a player drops the last few decimetres onto the floor). The
# table sits in the gap between spawn slots 3 (2.8 m) and 5 (4.2 m), which is why it is this narrow.

const PHONE_SIDE: float = 3.2
const PHONE_LIFT: float = 0.3
## The handset stands on its base: its centre is this high above the surface it rests on.
const PHONE_HALF: float = 0.13
const PHONE_TABLE_W: float = 0.72
const PHONE_TABLE_CENTER: float = 3.5


## The phone table for a door at `door_x`/`door_z`: a solid top `height` m above the floor with an apron,
## legs and a lower shelf (palette keys `tone`, `leg`), a cradle and a notepad on it. Returns the top
## surface's absolute height.
static func _phone_table(kit: Kit, p: Dictionary, door_x: float, door_z: float, height: float, depth: float, tone: String, leg: String) -> float:
	var z: float = door_z - SPAWN_IN
	var x: float = door_x - PHONE_TABLE_CENTER
	var at: Vector2 = Vector2(x, z)
	var w: float = PHONE_TABLE_W
	_o(kit, at, 0.0, 0, 0, height - 0.05, w, 0.05, depth, p[tone], true)
	_o(kit, at, 0.0, 0, 0, height - 0.15, w - 0.1, 0.1, depth - 0.1, p[leg])
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_o(kit, at, 0.0, sx * (w * 0.5 - 0.06), sz * (depth * 0.5 - 0.06), 0.0, 0.05, height - 0.15, 0.05, p[leg])
	_o(kit, at, 0.0, 0, 0, 0.18, w - 0.1, 0.03, depth - 0.1, p[leg])
	var top: float = F + height
	kit.begin_props()
	var phone_x: float = door_x - PHONE_SIDE
	kit.prop(Vector3(phone_x, top + 0.006, z), Vector3(0.15, 0.012, 0.15), p["black"])
	kit.prop(Vector3(phone_x, top + 0.0135, z), Vector3(0.15, 0.003, 0.03), p["accent"])
	kit.prop(Vector3(x - 0.05, top + 0.004, z - depth * 0.25), Vector3(0.22, 0.008, 0.3), p["paper"], 0.2)
	kit.prop(Vector3(x - 0.2, top + 0.012, z - depth * 0.25), Vector3(0.01, 0.012, 0.14), p["black"], 0.5)
	kit.end_props()
	return top


## The build() result for a compound: the delivery point just inside the front door, the spawn point 4.2 m in
## (lifted so the phone online.gd puts beside it rests on the phone table's top) and that phone spot.
static func _info(door_x: float, door_z: float, top_y: float, routes: Dictionary, hq_shift: Vector2 = Vector2.ZERO) -> Dictionary:
	var spawn_y: float = top_y + PHONE_HALF - PHONE_LIFT
	var z: float = door_z - SPAWN_IN
	return {"hq": Vector3(door_x + hq_shift.x, F, door_z - HQ_IN + hq_shift.y), "spawn": Vector3(door_x, spawn_y, z),
		"phone": Vector3(door_x - PHONE_SIDE, spawn_y + PHONE_LIFT, z), "routes": routes}


## A crate (solid) with slats, for the import rooms.
static func _crate(kit: Kit, p: Dictionary, x: float, z: float, yaw: float, w: float, h: float, d: float, tone: String = "wood") -> void:
	var at: Vector2 = Vector2(x, z)
	_o(kit, at, yaw, 0, 0, 0.0, w, h, d, p[tone], true)
	for level: float in [0.3, 0.62]:
		if level < h - 0.1:
			_o(kit, at, yaw, 0, 0, level, w + 0.03, 0.06, d + 0.03, p["dark"])


## A pillow or cushion on the floor or a seat (visual).
static func _cushion(kit: Kit, at: Vector2, yaw: float, y0: float, w: float, d: float, material: Material) -> void:
	_o(kit, at, yaw, 0, 0, y0, w, 0.08, d, material)


## A bookcase against a wall (solid), facing the piece's +Z: a carcase, shelves and rows of book spines.
static func _bookcase(kit: Kit, p: Dictionary, x: float, z: float, yaw: float, length: float, tall: float = 2.1) -> void:
	var at: Vector2 = Vector2(x, z)
	_o(kit, at, yaw, 0, 0, 0.0, length, tall, 0.4, p["dark"], true)
	var tints: Array[Material] = [kit.mat(Color(0.35, 0.12, 0.1), "", 0.8), kit.mat(Color(0.12, 0.2, 0.3), "", 0.8), kit.mat(Color(0.3, 0.3, 0.18), "", 0.8), kit.mat(Color(0.75, 0.7, 0.58), "", 0.8)]
	for shelf: int in range(5):
		var y: float = 0.25 + shelf * 0.38
		_o(kit, at, yaw, 0, 0.05, y, length - 0.08, 0.03, 0.34, p["wood"])
		var cursor: float = -length * 0.5 + 0.12
		var index: int = shelf
		while cursor < length * 0.5 - 0.2:
			var thick: float = 0.05 + float((index * 7 + shelf * 3) % 4) * 0.012
			_o(kit, at, yaw, cursor + thick * 0.5, 0.2, y + 0.03, thick, 0.22 + float((index * 5) % 3) * 0.03, 0.02, tints[(index + shelf) % 4])
			cursor += thick + 0.012
			index += 1


## Footprint-local waypoints of a flat route (y = floor).
static func _path(points: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for point: Variant in points:
		var v: Vector2 = point
		out.append(Vector3(v.x, F, v.y))
	return out


# =====================================================================================================
# MORRIS SOCIAL CLUB. Brick, oxblood leather and brass: a members-only social club. Bar room up front,
# card room behind it with the planning table, the office and the kitchen. 30 x 18, front faces +Z.
# =====================================================================================================

static func _morris(kit: Kit, p: Dictionary) -> Dictionary:
	var crimson: Color = Factions.color("morris")
	p["plaster"] = kit.mat(Color(0.8, 0.72, 0.56), "stucco", 0.9)
	p["trim"] = kit.mat(Color(0.16, 0.09, 0.06), "planks", 0.6)
	p["ceiling"] = kit.mat(Color(0.7, 0.64, 0.5), "", 0.95)
	p["parquet"] = kit.mat(Color(0.3, 0.17, 0.1), "planks", 0.55)
	p["tile"] = kit.mat(Color(0.86, 0.83, 0.74), "tiles", 0.6)
	p["carpet"] = kit.mat(Color(0.3, 0.07, 0.1), "tatami", 0.95)
	p["runner"] = kit.mat(crimson.darkened(0.1), "tatami", 0.95)
	p["felt"] = kit.mat(Color(0.06, 0.32, 0.17), "", 0.95)
	p["leather"] = kit.mat(Color(0.38, 0.07, 0.09), "", 0.45)
	p["marble"] = kit.mat(Color(0.82, 0.8, 0.76), "", 0.3)
	p["mirror"] = kit.mat(Color(0.55, 0.7, 0.78), "", 0.04)
	p["rug"] = kit.mat(Color(0.12, 0.24, 0.16), "tatami", 0.95)
	var cfg: Dictionary = {
		"outer": kit.mat(Color(0.56, 0.3, 0.24), "brick"), "roof": kit.mat(Color(0.25, 0.2, 0.2), "roof"),
		"plaster": p["plaster"], "trim": p["trim"], "ceiling": p["ceiling"], "lit": 0.5,
		"front": [_op(0.0, 2.4), _win(-12.8), _win(-9.4), _win(9.4), _win(12.8)],
		"back": [_op(9.5, 1.4), _win(-10.0, 1.8)],
		"west": [_op(-0.2, 1.4), _win(7.0, 1.8), _win(3.4, 1.8), _win(-5.0, 1.8)],
		"east": [_win(-5.0, 1.6)]}
	_shell(kit, p, cfg)
	_door(kit, p, Vector3(0, 0, 8.85), 2.4, Vector3.BACK, "Morris Social Club entrance")
	_door(kit, p, Vector3(-14.85, 0, -0.2), 1.4, Vector3.LEFT, "Morris Social Club side door", "door_steel")
	_door(kit, p, Vector3(9.5, 0, -8.85), 1.4, Vector3.FORWARD, "Morris Social Club kitchen door", "door_steel")
	kit.begin_interior()
	_lining(kit, p, cfg)
	var plaster: Material = p["plaster"]
	# Floors: parquet up front and in the card room, tile in the kitchen, carpet in the office.
	_floor(kit, Rect2(-14.6, -1.1, 29.2, 9.7), p["parquet"])
	_floor(kit, Rect2(-4.9, -8.6, 9.8, 7.3), p["parquet"])
	_floor(kit, Rect2(5.1, -8.6, 9.5, 7.3), p["tile"])
	_floor(kit, Rect2(-14.6, -8.6, 9.5, 7.3), p["carpet"])
	_floor(kit, Rect2(-1.1, 2.4, 2.2, 6.0), p["runner"], 0.006)
	_floor(kit, Rect2(-4.3, -7.7, 8.6, 5.6), p["rug"], 0.006)
	# Partitions: bar room | back rooms, and the card room's two side walls.
	_part(kit, Vector2(-14.6, -1.2), Vector2(14.6, -1.2), plaster, [_op(9.8, 1.4, 0.0, 2.7, "gap"), _op(0.0, 3.0, 0.0, 3.0, "gap"), _op(-9.8, 1.2, 0.0, 2.7, "gap")])
	_part(kit, Vector2(-5.0, -8.6), Vector2(-5.0, -1.3), plaster, [_op(-4.0, 1.4, 0.0, 2.7, "gap")])
	_part(kit, Vector2(5.0, -8.6), Vector2(5.0, -1.3), plaster, [_op(-4.0, 1.4, 0.0, 2.7, "gap")])
	# --- Bar room: bar along the east wall, booths along the west wall.
	var bar: Vector2 = Vector2(11.3, 4.3)
	_o(kit, bar, 0.0, 0.0, 0.0, 0.0, 0.9, 1.06, 6.2, p["dark"], true)
	_o(kit, bar, 0.0, -0.1, 0.0, 1.06, 1.1, 0.06, 6.4, p["marble"])
	_o(kit, bar, 0.0, -0.46, 0.0, 0.45, 0.02, 0.45, 6.0, p["accent"])
	_o(kit, bar, 0.0, -0.6, 0.0, 0.12, 0.07, 0.07, 6.0, p["brass"])
	for z: float in [1.9, 3.1, 4.3, 5.5, 6.7]:
		_stool(kit, p, 10.25, z)
	_o(kit, Vector2(14.3, 4.3), 0.0, 0.0, 0.0, 0.0, 0.6, 0.95, 5.8, p["dark"], true)
	_o(kit, Vector2(14.3, 4.3), 0.0, 0.0, 0.0, 0.95, 0.66, 0.05, 5.9, p["marble"])
	_o(kit, Vector2(14.3, 4.3), 0.0, 0.3, 0.0, 1.25, 0.03, 1.5, 5.6, p["mirror"])
	for y: float in [1.2, 1.7, 2.2]:
		_o(kit, Vector2(14.3, 4.3), 0.0, 0.12, 0.0, y, 0.3, 0.04, 5.6, p["glass"])
	_o(kit, Vector2(14.3, 4.3), 0.0, 0.0, 0.0, 2.85, 0.6, 0.12, 5.9, p["dark"])
	kit.neon_sign("CAFFE  BAR", Vector3(14.52, 3.5, 4.3), -PI * 0.5, crimson.lightened(0.1), 40)
	for z: float in [7.0, 3.4]:
		_morris_booth(kit, p, -12.9, z)
	var jukebox: Vector2 = Vector2(7.0, -0.7)
	_o(kit, jukebox, 0.0, 0.0, 0.0, 0.0, 1.0, 1.55, 0.6, p["dark"], true)
	_o(kit, jukebox, 0.0, 0.0, 0.0, 1.55, 0.9, 0.22, 0.55, p["dark"])
	_o(kit, jukebox, 0.0, 0.0, 0.31, 0.55, 0.78, 0.8, 0.02, p["glow_accent"])
	_o(kit, jukebox, 0.0, 0.0, 0.32, 0.25, 0.7, 0.2, 0.02, p["warm"])
	_o(kit, jukebox, 0.0, 0.0, 0.31, 1.5, 0.8, 0.05, 0.02, p["brass"])
	# Lockers and the gun rack by the door, flanking the entrance.
	_lockers(kit, p, 4.65, 8.345, PI, 6)
	_o(kit, Vector2(-4.7, 8.37), 0.0, 0.0, 0.0, 0.0, 3.0, 0.9, 0.5, p["dark"], true)
	_o(kit, Vector2(-4.7, 8.37), 0.0, 0.0, 0.0, 0.9, 3.1, 0.05, 0.56, p["wood"])
	# Command desk and the chair behind it, two visitors' chairs; the crew phone rests on the telephone table.
	var desk_at: Vector2 = Vector2(0.0, 1.65)
	var desk_top: Vector3 = _desk(kit, p, desk_at.x, desk_at.y, 0.0)
	_chair(kit, p, 0.0, 0.85, 0.0, "leather")
	_chair(kit, p, -0.55, 2.8, PI)
	_chair(kit, p, 0.55, 2.8, PI)
	var table_top: float = _phone_table(kit, p, 0.0, 8.85, 0.74, 0.8, "marble", "dark")
	# --- Card room: a felt poker table and the planning table with the city map.
	_table(kit, p, -2.2, -5.0, 0.0, 2.1, 1.5, 0.76, "felt", "dark")
	for chair: Array in [[-2.2, -3.75, PI], [-2.2, -6.25, 0.0], [-3.65, -5.0, PI * 0.5], [-0.75, -5.0, -PI * 0.5], [-3.1, -6.1, 0.4], [-1.3, -3.9, PI + 0.4]]:
		_chair(kit, p, float(chair[0]), float(chair[1]), float(chair[2]), "leather")
	_table(kit, p, 2.6, -5.9, 0.0, 2.6, 1.4, 0.78, "dark", "dark")
	_map_sheet(kit, p, 2.6, -5.9, 0.78, 1.15)
	for chair: Array in [[1.8, -4.85, PI], [3.4, -4.85, PI], [1.8, -6.95, 0.0], [3.4, -6.95, 0.0]]:
		_chair(kit, p, float(chair[0]), float(chair[1]), float(chair[2]))
	_o(kit, Vector2(0.0, -8.25), 0.0, 0.0, 0.0, 0.0, 6.0, 0.9, 0.5, p["dark"], true)
	_o(kit, Vector2(0.0, -8.25), 0.0, 0.0, 0.0, 0.9, 6.1, 0.05, 0.56, p["marble"])
	_hanging(kit, p, -2.2, -5.0, 1.0, "felt", 0.9)
	_hanging(kit, p, 2.6, -5.9, 1.0, "accent_dark", 0.9)
	# --- Office (west): desk, safe, filing cabinets and the big wall map.
	var boss: Vector2 = Vector2(-10.0, -5.2)
	_desk(kit, p, boss.x, boss.y, 0.0, 2.2, 1.0)
	_chair(kit, p, -10.0, -6.25, 0.0, "leather")
	_chair(kit, p, -10.9, -4.2, PI)
	_chair(kit, p, -9.1, -4.2, PI)
	_o(kit, Vector2(-13.7, -8.05), 0.0, 0.0, 0.0, 0.0, 0.95, 1.15, 0.85, p["black"], true)
	_o(kit, Vector2(-13.7, -8.05), 0.0, 0.0, 0.43, 0.6, 0.22, 0.22, 0.03, p["brass"])
	_o(kit, Vector2(-13.7, -8.05), 0.0, 0.3, 0.44, 0.75, 0.05, 0.14, 0.03, p["accent"])
	for x: float in [-7.4, -6.8, -6.2]:
		_o(kit, Vector2(x, -8.3), 0.0, 0.0, 0.0, 0.0, 0.55, 1.35, 0.6, p["steel"], true)
		for drawer: float in [0.15, 0.55, 0.95]:
			_o(kit, Vector2(x, -8.3), 0.0, 0.0, 0.31, drawer, 0.45, 0.3, 0.02, p["locker_door"])
	_wall_map(kit, p, -10.0, -8.55, 0.0, 2.6, 1.5, 1.25)
	# --- Kitchen (east): range and hood, prep table, sink, fridge, shelves.
	_o(kit, Vector2(7.2, -8.15), 0.0, 0.0, 0.0, 0.0, 2.4, 0.92, 0.9, p["steel"], true)
	_o(kit, Vector2(7.2, -8.3), 0.0, 0.0, 0.0, 1.95, 2.6, 0.55, 0.85, p["steel"])
	_o(kit, Vector2(7.2, -8.4), 0.0, 0.0, 0.0, 2.5, 0.5, 1.8, 0.5, p["steel"])
	_table(kit, p, 12.3, -5.0, 0.0, 3.4, 1.0, 0.92, "steel", "steel")
	_o(kit, Vector2(14.15, -2.4), 0.0, 0.0, 0.0, 0.0, 0.8, 2.0, 0.85, p["steel"], true)
	_o(kit, Vector2(14.2, -7.4), 0.0, 0.0, 0.0, 0.0, 0.7, 0.92, 1.8, p["steel"], true)
	_o(kit, Vector2(14.0, -5.0), 0.0, 0.0, 0.0, 1.5, 0.3, 0.05, 3.0, p["steel"])
	_o(kit, Vector2(5.45, -7.1), 0.0, 0.0, 0.0, 0.0, 0.6, 1.9, 2.4, p["wood"], true)
	_o(kit, Vector2(5.45, -7.1), 0.0, 0.3, 0.0, 0.5, 0.02, 0.05, 2.3, p["dark"])
	_o(kit, Vector2(5.45, -7.1), 0.0, 0.3, 0.0, 1.0, 0.02, 0.05, 2.3, p["dark"])
	_o(kit, Vector2(5.45, -7.1), 0.0, 0.3, 0.0, 1.5, 0.02, 0.05, 2.3, p["dark"])
	# --- Lamps: one per room group (front room, card room + office, kitchen).
	kit.interior_light(Vector3(0, 3.9, 3.6), Color(1.0, 0.82, 0.58), 2.4, 20.0)
	kit.interior_light(Vector3(-6.5, 3.7, -5.0), Color(1.0, 0.85, 0.65), 1.8, 13.0)
	kit.interior_light(Vector3(8.5, 3.7, -5.0), Color(0.95, 0.98, 1.0), 1.7, 12.0)
	# --- Dressing.
	kit.begin_props()
	_gun_rack(kit, p, 8.62, -1.0, -4.7, 3.0)
	_phone_dressing(kit, p, desk_top, 0.0)
	_morris_props(kit, p)
	_fan(kit, p, -4.5, 4.0)
	_fan(kit, p, 4.5, 4.0, 0.8)
	var cream: Color = Color(0.95, 0.9, 0.78)
	_text(kit, "MORRIS  SOCIAL  CLUB  -  MEMBERS  ONLY", 0.0, 3.35, 8.6, PI, 26, cream)
	_text(kit, "FAMILY  FIRST.  BUSINESS  ALWAYS.", 0.0, 3.3, -8.55, 0.0, 34, cream)
	_text(kit, "MEMBERS'  LOCKERS", 4.65, 2.35, 8.6, PI, 22, cream)
	_text(kit, "ESPRESSO 1.50  CAPPUCCINO 2.00\nSAMBUCA 4.00  COGNAC 6.00", 12.5, 3.0, 8.6, PI, 22, cream)
	kit.end_props()
	kit.end_interior()
	var routes: Dictionary = {
		"to_street": _path([Vector2(0, 4.65), Vector2(0, 7.15), Vector2(0, 10.5), Vector2(0, 12.2), Vector2(-26.0, 12.2), Vector2(-34.4, 11.0), Vector2(-34.4, -6.0)]),
		"side_door": _path([Vector2(0, 4.65), Vector2(-2.0, 3.4), Vector2(-2.0, 0.8), Vector2(-13.0, 0.8), Vector2(-13.4, -0.2), Vector2(-14.85, -0.2), Vector2(-18.0, -0.2)]),
		"kitchen_door": _path([Vector2(0, 4.65), Vector2(2.0, 3.4), Vector2(8.0, 0.6), Vector2(9.8, 0.6), Vector2(9.8, -2.0), Vector2(9.6, -8.0), Vector2(9.5, -8.85), Vector2(9.5, -11.5)])}
	return _info(0.0, 8.85, table_top, routes)


static func _morris_booth(kit: Kit, p: Dictionary, x: float, z: float) -> void:
	var at: Vector2 = Vector2(x, z)
	for side: float in [-1.0, 1.0]:
		_o(kit, at, 0.0, 0.0, side * 0.95, 0.0, 3.0, 0.46, 0.6, p["leather"], true)
		_o(kit, at, 0.0, 0.0, side * 1.36, 0.46, 3.0, 0.85, 0.14, p["leather"], true)
	_o(kit, at, 0.0, 0.0, 0.0, 0.0, 0.14, 0.72, 0.14, p["steel"])
	_o(kit, at, 0.0, 0.0, 0.0, 0.72, 2.2, 0.05, 0.9, p["dark"], true)


static func _morris_props(kit: Kit, p: Dictionary) -> void:
	var glass: Material = p["glass"]
	var cash: Material = kit.mat(Color(0.45, 0.6, 0.4), "", 0.9)
	var ash: Material = kit.mat(Color(0.25, 0.25, 0.27), "", 0.5)
	var espresso: Material = kit.mat(Color(0.78, 0.8, 0.82), "metal", 0.2)
	# Bar top (z 1.2 - 7.4 at x ~ 11.3, top at 1.12 above the floor): glasses, bottles, ash, the machine.
	var top: float = F + 1.12
	for index: int in range(9):
		var z: float = 1.6 + index * 0.65
		kit.prop(Vector3(10.9, top + 0.06, z), Vector3(0.07, 0.12, 0.07), glass)
		if index % 3 == 0:
			kit.prop(Vector3(10.85, top + 0.012, z + 0.2), Vector3(0.14, 0.024, 0.14), ash)
	kit.prop(Vector3(11.5, top + 0.3, 6.5), Vector3(0.5, 0.6, 0.6), espresso)
	kit.prop(Vector3(11.3, top + 0.12, 6.5), Vector3(0.1, 0.24, 0.1), espresso)
	kit.prop(Vector3(11.45, top + 0.04, 2.0), Vector3(0.4, 0.14, 0.34), p["brass"])
	kit.prop_bottle(Vector3(11.6, top, 4.6), Color(0.1, 0.3, 0.1), 0.34)
	kit.prop_bottle(Vector3(11.6, top, 4.9), Color(0.5, 0.25, 0.08), 0.3)
	# Back bar shelves: bottles in rows.
	var tints: Array[Color] = [Color(0.45, 0.25, 0.08), Color(0.12, 0.35, 0.15), Color(0.75, 0.6, 0.2), Color(0.5, 0.08, 0.12), Color(0.8, 0.82, 0.85)]
	for shelf: int in range(3):
		for index: int in range(16):
			kit.prop_bottle(Vector3(14.42, F + 1.24 + shelf * 0.5, 1.7 + index * 0.35), tints[(index + shelf) % tints.size()], 0.3)
	# Booth tables: cups, ashtrays, a bowl of sugar.
	for z: float in [7.0, 3.4]:
		kit.prop(Vector3(-12.6, F + 0.77, z - 0.1), Vector3(0.14, 0.03, 0.14), ash)
		kit.prop(Vector3(-13.4, F + 0.79, z + 0.1), Vector3(0.09, 0.08, 0.09), p["white"])
		kit.prop(Vector3(-12.2, F + 0.79, z - 0.05), Vector3(0.09, 0.08, 0.09), p["white"])
	# Felt table: chips, cards, ashtrays; planning table: a pencil cup and a cigar box.
	var chips: Array[Material] = [kit.mat(Color(0.8, 0.15, 0.15), "", 0.6), kit.mat(Color(0.15, 0.15, 0.6), "", 0.6), kit.mat(Color(0.9, 0.9, 0.85), "", 0.6)]
	for index: int in range(9):
		kit.prop(Vector3(-2.6 + (index % 3) * 0.13, F + 0.79 + (index / 3) * 0.02, -5.2 + (index / 3) * 0.12), Vector3(0.1, 0.02, 0.1), chips[index % 3])
	for index: int in range(5):
		kit.prop(Vector3(-2.9 + index * 0.18, F + 0.765, -4.75), Vector3(0.1, 0.004, 0.14), p["paper"], 0.3 * index)
	kit.prop(Vector3(-1.6, F + 0.77, -4.6), Vector3(0.14, 0.03, 0.14), ash)
	kit.prop(Vector3(-2.2, F + 0.77, -5.6), Vector3(0.14, 0.03, 0.14), ash)
	kit.prop(Vector3(3.6, F + 0.82, -5.4), Vector3(0.3, 0.07, 0.18), kit.mat(Color(0.35, 0.2, 0.1), "planks", 0.5))
	kit.prop(Vector3(1.5, F + 0.84, -6.5), Vector3(0.08, 0.12, 0.08), p["black"])
	# Office: blotter, banker's lamp, a stack of cash and ledgers on the boss's desk.
	kit.prop(Vector3(-10.0, F + 0.76, -5.3), Vector3(0.7, 0.012, 0.45), p["leather"])
	kit.prop(Vector3(-10.7, F + 0.9, -5.6), Vector3(0.2, 0.26, 0.2), kit.mat(Color(0.1, 0.3, 0.2), "", 0.4))
	kit.prop(Vector3(-9.4, F + 0.8, -5.2), Vector3(0.2, 0.08, 0.1), cash)
	kit.prop(Vector3(-9.2, F + 0.79, -5.5), Vector3(0.25, 0.06, 0.18), p["wood"], 0.2)
	# Kitchen: pots on the range, a tomato crate, a pasta board.
	for x: float in [6.6, 7.2, 7.8]:
		kit.prop(Vector3(x, F + 1.05, -8.15), Vector3(0.3, 0.2, 0.3), p["steel"])
	kit.prop(Vector3(12.0, F + 0.97, -5.0), Vector3(0.8, 0.04, 0.5), p["wood"])
	kit.prop(Vector3(13.2, F + 0.98, -5.1), Vector3(0.5, 0.14, 0.4), kit.mat(Color(0.75, 0.15, 0.1), "", 0.6))
	for index: int in range(6):
		kit.prop(Vector3(13.6, F + 1.65, -6.0 + index * 0.45), Vector3(0.1, 0.05, 0.1), kit.mat(Color(0.7, 0.68, 0.6), "", 0.5))
	# Photos on the partition wall: framed portraits, all original family faces.
	var sepia: Material = kit.mat(Color(0.5, 0.4, 0.3), "", 0.8)
	for x: float in [-7.5, -5.5, -3.5, 3.5, 5.0]:
		_picture(kit, p, x, -1.0, 0.0, 0.5, 0.65, 1.7, sepia)




# =====================================================================================================
# Shared furniture for the other three compounds.
# =====================================================================================================

## A solid counter run facing the piece's +Z: a body, and a top slab with a little overhang.
static func _counter(kit: Kit, p: Dictionary, x: float, z: float, yaw: float, length: float, depth: float, height: float, body: String, top: String) -> void:
	var at: Vector2 = Vector2(x, z)
	_o(kit, at, yaw, 0, 0, 0.0, length, height - 0.05, depth, p[body], true)
	_o(kit, at, yaw, 0, 0.02, height - 0.05, length + 0.06, 0.05, depth + 0.06, p[top], true)


## Thin lattice bars over a window (visual): `along_z` for windows in a wall that runs along Z.
static func _lattice(kit: Kit, p: Dictionary, x: float, z: float, along_z: bool, w: float, y0: float, h: float, tone: String = "trim") -> void:
	var at: Vector2 = Vector2(x, z)
	var yaw: float = PI * 0.5 if along_z else 0.0
	for level: float in [0.0, 0.5, 1.0]:
		_o(kit, at, yaw, 0, 0, y0 + level * (h - 0.04), w, 0.04, 0.05, p[tone])
	for index: int in range(4):
		_o(kit, at, yaw, -w * 0.5 + 0.02 + float(index) * (w - 0.04) / 3.0, 0, y0, 0.04, h, 0.05, p[tone])


## A standing folding screen (visual): dark frame, paper panels and two feet.
static func _shoji(kit: Kit, p: Dictionary, x: float, z: float, yaw: float, w: float, h: float) -> void:
	var at: Vector2 = Vector2(x, z)
	_o(kit, at, yaw, 0, 0, 0.0, w, h, 0.04, p["shoji"])
	for index: int in range(4):
		_o(kit, at, yaw, -w * 0.5 + float(index) * w / 3.0, 0, 0.0, 0.05, h + 0.03, 0.06, p["trim"])
	for level: float in [0.0, 0.5, 1.0]:
		_o(kit, at, yaw, 0, 0, level * (h - 0.05), w, 0.05, 0.06, p["trim"])
	for side: float in [-1.0, 1.0]:
		_o(kit, at, yaw, side * w * 0.42, 0, 0.0, 0.05, 0.05, 0.5, p["trim"])


## A vending machine facing the piece's +Z (solid): lit selection panel, keypad and a dispenser flap.
static func _vending(kit: Kit, p: Dictionary, x: float, z: float, yaw: float, body: Material) -> void:
	var at: Vector2 = Vector2(x, z)
	_o(kit, at, yaw, 0, 0, 0.0, 0.95, 1.85, 0.85, body, true)
	_o(kit, at, yaw, -0.12, 0.43, 0.4, 0.62, 1.25, 0.03, p["glow_accent"])
	_o(kit, at, yaw, 0.35, 0.43, 0.9, 0.16, 0.4, 0.03, p["black"])
	_o(kit, at, yaw, -0.12, 0.43, 0.08, 0.62, 0.22, 0.03, p["black"])


## An upright arcade cabinet facing the piece's +Z (solid) with a lit screen and marquee.
static func _arcade(kit: Kit, p: Dictionary, x: float, z: float, yaw: float, body: Material, screen: Material) -> void:
	var at: Vector2 = Vector2(x, z)
	_o(kit, at, yaw, 0, 0, 0.0, 0.72, 1.75, 0.8, body, true)
	_o(kit, at, yaw, 0, 0.4, 0.95, 0.66, 0.08, 0.3, p["black"])
	_o(kit, at, yaw, 0, 0.405, 1.05, 0.54, 0.44, 0.02, screen)
	_o(kit, at, yaw, 0, 0.405, 1.55, 0.66, 0.18, 0.03, p["glow_accent"])
	for side: float in [-1.0, 1.0]:
		_o(kit, at, yaw, side * 0.14, 0.52, 1.03, 0.05, 0.05, 0.05, p["accent"])


## A pool table (solid body and rails), its long side along the piece's X.
static func _pool(kit: Kit, p: Dictionary, x: float, z: float, yaw: float) -> void:
	var at: Vector2 = Vector2(x, z)
	_o(kit, at, yaw, 0, 0, 0.0, 2.7, 0.86, 1.4, p["dark"], true)
	_o(kit, at, yaw, 0, 0, 0.86, 2.34, 0.02, 1.0, p["felt"])
	for end: float in [-1.0, 1.0]:
		_o(kit, at, yaw, end * 1.26, 0, 0.86, 0.18, 0.06, 1.4, p["dark"])
	for side: float in [-1.0, 1.0]:
		_o(kit, at, yaw, 0, side * 0.61, 0.86, 2.7, 0.06, 0.18, p["dark"])
	for corner_x: float in [-1.14, 0.0, 1.14]:
		for side: float in [-1.0, 1.0]:
			_o(kit, at, yaw, corner_x, side * 0.56, 0.875, 0.12, 0.01, 0.12, p["black"])


# =====================================================================================================
# KOJIMOTO BUILDING. A karaoke-bar front on Lantern Row over an oyabun's house: a dark-timber lounge with
# black lacquer, violet and pink neon coves and a koi tank by the door, a tatami room with a tokonoma
# alcove, the lacquer war table under paper lanterns and a steel izakaya kitchen at the back. 28 x 22,
# front faces +Z (the walled garden and its timber gate lie beyond the door).
# =====================================================================================================

static func _kojimoto(kit: Kit, p: Dictionary) -> Dictionary:
	var violet: Color = Factions.color("kojimoto")
	var pink: Color = Color(0.95, 0.35, 0.85)
	p["plaster"] = kit.mat(Color(0.72, 0.68, 0.6), "stucco", 0.9)
	p["trim"] = kit.mat(Color(0.12, 0.08, 0.06), "planks", 0.55)
	p["ceiling"] = kit.mat(Color(0.2, 0.17, 0.2), "", 0.95)
	p["tatami"] = kit.mat(Color(0.6, 0.58, 0.36), "tatami", 0.95)
	p["carpet"] = kit.mat(Color(0.17, 0.1, 0.24), "tatami", 0.95)
	p["parquet"] = kit.mat(Color(0.22, 0.13, 0.08), "planks", 0.5)
	p["tile"] = kit.mat(Color(0.56, 0.56, 0.54), "tiles", 0.6)
	p["lacquer"] = kit.mat(Color(0.05, 0.04, 0.06), "", 0.18)
	p["red_lacquer"] = kit.mat(Color(0.5, 0.06, 0.07), "", 0.2)
	p["shoji"] = kit.mat(Color(0.9, 0.87, 0.74), "", 0.9)
	p["leather"] = kit.mat(Color(0.09, 0.08, 0.11), "", 0.45)
	p["sofa"] = p["leather"]
	p["zabuton"] = kit.mat(violet.darkened(0.4), "", 0.9)
	p["water"] = kit.glow(Color(0.2, 0.7, 0.85), 0.9)
	p["screen"] = kit.glow(Color(0.55, 0.4, 0.95), 1.0)
	p["pink_neon"] = kit.glow(pink, 1.5)
	p["violet_neon"] = kit.glow(violet.lightened(0.15), 1.5)
	p["lantern"] = kit.mat(Color(0.88, 0.3, 0.2), "", 0.6)
	var cfg: Dictionary = {
		"outer": kit.mat(Color(0.17, 0.16, 0.2), "panel"), "roof": kit.mat(Color(0.16, 0.16, 0.2), "roof"),
		"plaster": p["plaster"], "trim": p["trim"], "ceiling": p["ceiling"], "lit": 0.5,
		"front": [_op(5.0, 2.4), _win(-4.0, 2.0)],
		"back": [_op(11.0, 1.4), _win(-9.0, 1.8), _win(-1.0, 1.8)],
		"west": [_win(8.5, 1.8), _win(-6.0, 1.8)],
		"east": [_op(3.0, 1.4), _win(-5.0, 1.8)]}
	_shell(kit, p, cfg)
	_door(kit, p, Vector3(5.0, 0, 10.85), 2.4, Vector3.BACK, "Kojimoto Building entrance")
	_door(kit, p, Vector3(13.85, 0, 3.0), 1.4, Vector3.RIGHT, "Kojimoto Building side door", "door_steel")
	_door(kit, p, Vector3(11.0, 0, -10.85), 1.4, Vector3.FORWARD, "Kojimoto Building kitchen door", "door_steel")
	kit.begin_interior()
	_lining(kit, p, cfg)
	var plaster: Material = p["plaster"]
	# Floors: stone in the entrance hall, plum carpet in the lounge, tatami, parquet and kitchen tile behind.
	_floor(kit, Rect2(-1.0, -0.8, 14.6, 11.4), p["tile"])
	_floor(kit, Rect2(-13.6, -0.8, 12.6, 11.4), p["carpet"])
	_floor(kit, Rect2(-13.6, -10.6, 8.5, 9.6), p["tatami"])
	_floor(kit, Rect2(-4.9, -10.6, 9.8, 9.6), p["parquet"])
	_floor(kit, Rect2(5.1, -10.6, 8.5, 9.6), p["tile"])
	# Partitions: hall | back rooms, and the two side walls of the war room.
	_part(kit, Vector2(-13.6, -1.0), Vector2(13.6, -1.0), plaster, [_op(-9.3, 1.6, 0.0, 2.7, "gap"), _op(0.0, 3.0, 0.0, 3.0, "gap"), _op(9.3, 1.4, 0.0, 2.7, "gap")])
	_part(kit, Vector2(-5.0, -10.6), Vector2(-5.0, -1.1), plaster, [_op(-7.0, 1.2, 0.0, 2.7, "gap")])
	_part(kit, Vector2(5.0, -10.6), Vector2(5.0, -1.1), plaster, [_op(-7.0, 1.2, 0.0, 2.7, "gap")])
	# Ceiling: timber beams over the hall and neon coves round the lounge.
	for z: float in [2.0, 8.0]:
		_o(kit, Vector2(0.0, z), 0.0, 0, 0, CEIL - F - 0.3, 27.0, 0.22, 0.22, p["trim"])
	_o(kit, Vector2(-7.3, 10.45), 0.0, 0, 0, CEIL - F - 0.13, 12.0, 0.05, 0.08, p["pink_neon"])
	_o(kit, Vector2(-13.45, 4.5), 0.0, 0, 0, CEIL - F - 0.13, 0.08, 0.05, 10.6, p["pink_neon"])
	_o(kit, Vector2(-7.3, -0.6), 0.0, 0, 0, CEIL - F - 0.13, 12.0, 0.05, 0.08, p["violet_neon"])
	for arch: Array in [[-9.3, 1.6], [0.0, 3.0], [9.3, 1.4]]:
		_o(kit, Vector2(float(arch[0]), -1.0), 0.0, 0, 0, 2.7, float(arch[1]) + 0.4, 0.16, 0.3, p["trim"])
	# --- Lounge (west hall): TV wall, two sofas, the lacquer table, the bar under the front wall.
	_o(kit, Vector2(-13.2, 4.2), 0.0, 0, 0, 0.0, 0.7, 0.5, 2.4, p["lacquer"], true)
	_sofa(kit, p, -6.4, 2.2, -PI * 0.5, 2.2, "sofa")
	_sofa(kit, p, -6.4, 6.2, -PI * 0.5, 2.2, "sofa")
	_table(kit, p, -9.4, 4.2, PI * 0.5, 1.6, 0.8, 0.42, "lacquer", "lacquer")
	_sofa(kit, p, -4.3, -0.25, 0.0, 2.3, "sofa")
	_table(kit, p, -4.3, 1.3, 0.0, 1.1, 0.5, 0.42, "lacquer", "lacquer")
	_counter(kit, p, -10.4, 8.9, 0.0, 5.4, 0.7, 1.05, "lacquer", "red_lacquer")
	for x: float in [-12.6, -11.4, -10.2, -9.0, -7.8]:
		_stool(kit, p, x, 8.05, "leather", 0.72)
	_o(kit, Vector2(-10.4, 10.36), 0.0, 0, 0, 0.0, 5.4, 0.92, 0.5, p["dark"], true)
	for y: float in [1.35, 1.8, 2.25]:
		_o(kit, Vector2(-10.4, 10.5), 0.0, 0, 0, y, 5.4, 0.03, 0.25, p["wood"])
	_plant(kit, p, -13.0, 0.3, 1.1)
	# --- Entrance hall (east): lockers and the gun rack flanking the door, the koi tank on the partition.
	_lockers(kit, p, 9.6, 10.345, PI, 6)
	_o(kit, Vector2(1.9, 10.37), 0.0, 0, 0, 0.0, 3.0, 0.9, 0.5, p["dark"], true)
	_o(kit, Vector2(1.9, 10.37), 0.0, 0, 0, 0.9, 3.1, 0.05, 0.56, p["wood"])
	var table_top: float = _phone_table(kit, p, 5.0, 10.85, 0.76, 0.8, "lacquer", "lacquer")
	_o(kit, Vector2(5.0, -0.45), 0.0, 0, 0, 0.0, 3.4, 0.8, 0.6, p["lacquer"], true)
	_o(kit, Vector2(5.0, -0.45), 0.0, 0, 0, 0.8, 3.3, 0.85, 0.52, p["water"])
	_o(kit, Vector2(5.0, -0.45), 0.0, 0, 0, 1.65, 3.4, 0.05, 0.6, p["lacquer"])
	_sofa(kit, p, 11.3, 0.3, 0.0, 2.2, "sofa")
	_table(kit, p, 11.3, 1.7, 0.0, 1.1, 0.5, 0.42, "lacquer", "lacquer")
	_o(kit, Vector2(13.3, 6.6), 0.0, 0, 0, 0.0, 0.5, 1.1, 2.4, p["dark"], true)
	_plant(kit, p, 13.0, 9.9, 1.0)
	# --- Tatami room (west back): the low table and cushions, the tokonoma alcove, the futon closet.
	_table(kit, p, -9.3, -5.7, 0.0, 2.2, 1.0, 0.38, "lacquer", "lacquer")
	for seat: Array in [[-10.2, -4.75, PI], [-8.4, -4.75, PI], [-10.2, -6.65, 0.0], [-8.4, -6.65, 0.0], [-11.4, -5.7, PI * 0.5], [-7.2, -5.7, -PI * 0.5]]:
		_cushion(kit, Vector2(float(seat[0]), float(seat[1])), float(seat[2]), 0.0, 0.6, 0.6, p["zabuton"])
	_o(kit, Vector2(-13.2, -5.7), 0.0, 0, 0, 0.0, 0.8, 0.14, 2.2, p["trim"])
	_picture(kit, p, -13.55, -5.7, PI * 0.5, 0.7, 1.5, 0.9, p["paper"])
	_plant(kit, p, -13.2, -3.9, 0.8)
	_o(kit, Vector2(-11.8, -9.9), 0.0, 0, 0, 0.0, 3.2, 2.1, 1.0, p["shoji"], true)
	for dx: float in [-1.6, -0.53, 0.53, 1.6]:
		_o(kit, Vector2(-11.8, -9.9), 0.0, dx, 0.51, 0.0, 0.03, 2.1, 0.02, p["trim"])
	_shoji(kit, p, -7.0, -2.3, 0.0, 1.8, 1.7)
	_hanging(kit, p, -9.3, -5.7, 1.1, "lantern", 0.5)
	# --- War room (centre): the lacquer table with the map, eight chairs, the big wall map.
	_table(kit, p, 0.0, -5.8, 0.0, 4.4, 1.4, 0.76, "lacquer", "lacquer")
	_map_sheet(kit, p, 0.0, -5.8, 0.76, 1.15)
	for x: float in [-1.6, -0.55, 0.55, 1.6]:
		_chair(kit, p, x, -4.7, PI, "leather")
		_chair(kit, p, x, -6.9, 0.0, "leather")
	_chair(kit, p, -2.75, -5.8, PI * 0.5, "leather")
	_chair(kit, p, 2.75, -5.8, -PI * 0.5, "leather")
	_wall_map(kit, p, 0.0, -10.5, 0.0, 3.0, 1.6, 1.2)
	_hanging(kit, p, -1.4, -5.8, 1.0, "lantern", 0.5)
	_hanging(kit, p, 1.4, -5.8, 1.0, "lantern", 0.5)
	# --- Kitchen and strongroom (east back): range and hood, prep table, sink run, fridge, safe, dry goods.
	_counter(kit, p, 7.4, -10.25, 0.0, 3.2, 0.7, 0.92, "steel", "steel")
	_o(kit, Vector2(7.4, -10.3), 0.0, 0, 0, 1.95, 3.0, 0.6, 0.7, p["steel"])
	_o(kit, Vector2(7.4, -10.4), 0.0, 0, 0, 2.5, 0.5, 1.6, 0.5, p["steel"])
	_table(kit, p, 8.6, -5.4, 0.0, 2.6, 0.9, 0.92, "steel", "steel")
	_counter(kit, p, 13.25, -6.9, -PI * 0.5, 2.6, 0.6, 0.92, "steel", "steel")
	_o(kit, Vector2(13.1, -2.5), 0.0, 0, 0, 0.0, 0.85, 1.95, 0.8, p["steel"], true)
	_o(kit, Vector2(13.0, -9.4), 0.0, 0, 0, 0.0, 1.0, 1.2, 0.9, p["black"], true)
	_o(kit, Vector2(13.0, -9.4), 0.0, -0.3, 0.45, 0.6, 0.2, 0.2, 0.03, p["brass"])
	_o(kit, Vector2(5.45, -3.2), 0.0, 0, 0, 0.0, 0.5, 1.9, 2.8, p["wood"], true)
	_hanging(kit, p, 8.6, -5.4, 1.2, "steel", 0.6)
	# Lamps: one per room group (hall and lounge, tatami and war room, kitchen).
	kit.interior_light(Vector3(0, 3.9, 4.5), Color(1.0, 0.86, 0.78), 2.4, 22.0)
	kit.interior_light(Vector3(-4.5, 3.7, -5.8), Color(1.0, 0.78, 0.6), 1.8, 13.0)
	kit.interior_light(Vector3(9.0, 3.7, -5.8), Color(0.96, 0.98, 1.0), 1.7, 12.0)
	# --- Dressing.
	kit.begin_props()
	_gun_rack(kit, p, 10.62, -1.0, 1.9, 3.0)
	var black: Material = p["black"]
	kit.prop(Vector3(-13.2, F + 0.92, 4.2), Vector3(0.55, 0.84, 1.5), black)
	kit.prop(Vector3(-12.9, F + 0.92, 4.2), Vector3(0.02, 0.68, 1.3), p["screen"])
	for z: float in [2.3, 6.1]:
		kit.prop(Vector3(-13.2, F + 0.85, z), Vector3(0.4, 1.3, 0.4), black)
	for z: float in [3.6, 4.0, 4.5]:
		kit.prop(Vector3(-9.4, F + 0.45, z), Vector3(0.05, 0.14, 0.05), p["white"])
	kit.prop(Vector3(-9.3, F + 0.43, 4.9), Vector3(0.2, 0.03, 0.26), p["pink_neon"])
	kit.prop(Vector3(-9.6, F + 0.44, 3.7), Vector3(0.06, 0.03, 0.2), black)
	var tints: Array[Color] = [Color(0.45, 0.25, 0.08), Color(0.12, 0.35, 0.15), Color(0.75, 0.6, 0.2), Color(0.5, 0.08, 0.12), Color(0.8, 0.82, 0.85)]
	for shelf: int in range(3):
		for index: int in range(12):
			kit.prop_bottle(Vector3(-12.9 + index * 0.45, F + 1.38 + shelf * 0.45, 10.5), tints[(index + shelf) % tints.size()], 0.3)
	for x: float in [-12.0, -10.8, -9.2]:
		kit.prop(Vector3(x, F + 1.08, 8.85), Vector3(0.07, 0.12, 0.07), p["glass"])
	for fish: int in range(7):
		kit.prop(Vector3(3.7 + fish * 0.45, F + 1.05 + float(fish % 3) * 0.2, -0.45 + float(fish % 2) * 0.1), Vector3(0.12, 0.05, 0.04), kit.mat(Color(0.95, 0.45, 0.15), "", 0.5))
	kit.prop(Vector3(5.0, F + 0.88, -0.45), Vector3(3.1, 0.06, 0.4), kit.mat(Color(0.78, 0.7, 0.55), "", 0.9))
	for z: float in [-4.6, -5.1, -5.7, -6.3]:
		kit.prop(Vector3(-9.3 + (z + 5.4) * 0.3, F + 0.4, z), Vector3(0.14, 0.05, 0.14), p["white"])
	kit.prop(Vector3(-13.15, F + 0.25, -5.7), Vector3(0.3, 0.1, 0.5), black)
	kit.prop(Vector3(-13.15, F + 0.4, -5.85), Vector3(0.05, 0.05, 0.8), black)
	kit.prop(Vector3(-13.15, F + 0.4, -5.55), Vector3(0.05, 0.05, 0.7), p["brass"])
	for x: float in [-1.0, -0.3, 0.4, 1.1]:
		kit.prop(Vector3(x, F + 0.775, -5.6 - x * 0.1), Vector3(0.08, 0.03, 0.08), p["white"])
	for x: float in [6.2, 7.4, 8.6]:
		kit.prop(Vector3(x, F + 1.08, -10.25), Vector3(0.3, 0.2, 0.3), p["steel"])
	kit.prop(Vector3(8.6, F + 0.96, -5.4), Vector3(0.8, 0.04, 0.5), p["wood"])
	for index: int in range(6):
		kit.prop(Vector3(5.45, F + 0.4 + (index % 3) * 0.6, -2.0 - index * 0.4), Vector3(0.3, 0.3, 0.3), kit.mat(Color(0.7, 0.66, 0.55), "", 0.7))
	_lattice(kit, p, -4.0, 10.6, false, 2.0, F + 0.9, 1.55)
	_lattice(kit, p, -9.0, -10.6, false, 1.8, F + 0.9, 1.55)
	_lattice(kit, p, -1.0, -10.6, false, 1.8, F + 0.9, 1.55)
	_lattice(kit, p, -13.6, 8.5, true, 1.8, F + 0.9, 1.55)
	_lattice(kit, p, -13.6, -6.0, true, 1.8, F + 0.9, 1.55)
	_lattice(kit, p, 13.6, -5.0, true, 1.8, F + 0.9, 1.55)
	_fan(kit, p, 6.0, 5.0)
	var white: Color = Color(0.96, 0.94, 1.0)
	_text(kit, "KOJIMOTO893  -  MEMBERS  ONLY", 5.0, 3.35, 10.6, PI, 26, white)
	_text(kit, "MEMBERS'  LOCKERS", 9.6, 2.35, 10.6, PI, 22, white)
	_text(kit, "DUTY  IS  THE  ONLY  DEBT", 0.0, 3.3, -10.55, 0.0, 34, white)
	_text(kit, "TATAMI  ROOM  -  SHOES  OFF", -9.3, 2.85, -0.85, 0.0, 22, white)
	kit.neon_sign("KARAOKE  MURASAKI", Vector3(-10.4, 3.35, 10.56), PI, pink, 44)
	kit.end_props()
	kit.end_interior()
	var routes: Dictionary = {
		"to_street": _path([Vector2(5.0, 6.65), Vector2(5.0, 10.85), Vector2(5.0, 14.0), Vector2(5.0, 22.5), Vector2(6.6, 24.5), Vector2(6.6, 29.5), Vector2(31.0, 30.0), Vector2(31.0, 15.5)]),
		"side_door": _path([Vector2(5.0, 6.65), Vector2(9.0, 5.0), Vector2(12.0, 3.0), Vector2(13.85, 3.0), Vector2(16.8, 3.0), Vector2(20.0, 3.0)]),
		"kitchen_door": _path([Vector2(5.0, 6.65), Vector2(7.0, 3.0), Vector2(9.3, 0.5), Vector2(9.3, -2.4), Vector2(11.0, -4.0), Vector2(11.0, -10.0), Vector2(11.0, -10.85), Vector2(11.0, -13.5)])}
	return _info(5.0, 10.85, table_top, routes)


# =====================================================================================================
# SOL NEGRO HACIENDA. A whitewashed ranch house behind the gated courtyard: saltillo tile and dark
# vigas, a sala with leather equipales, a carved dining table under wrought-iron lamps, the patron's
# study, and a cantina with crates of "imports" stacked beside the cash table. 30 x 14, front faces +Z
# onto the fountain courtyard; both ends open onto the side yards of the walled compound.
# =====================================================================================================

static func _solnegro(kit: Kit, p: Dictionary) -> Dictionary:
	var gold: Color = Factions.color("solnegro")
	p["plaster"] = kit.mat(Color(0.86, 0.72, 0.5), "stucco", 0.9)
	p["trim"] = kit.mat(Color(0.25, 0.14, 0.08), "planks", 0.6)
	p["ceiling"] = kit.mat(Color(0.8, 0.72, 0.58), "", 0.95)
	p["saltillo"] = kit.mat(Color(0.64, 0.36, 0.2), "tiles", 0.7)
	p["talavera"] = kit.mat(Color(0.2, 0.38, 0.6), "tiles", 0.4)
	p["parquet"] = kit.mat(Color(0.3, 0.18, 0.1), "planks", 0.55)
	p["leather"] = kit.mat(Color(0.5, 0.3, 0.15), "", 0.5)
	p["sofa"] = p["leather"]
	p["equipale"] = kit.mat(Color(0.55, 0.36, 0.2), "planks", 0.6)
	p["iron"] = kit.mat(Color(0.08, 0.08, 0.09), "metal", 0.5)
	p["rug"] = kit.mat(Color(0.55, 0.12, 0.1), "tatami", 0.95)
	p["rug_dark"] = kit.mat(Color(0.12, 0.11, 0.13), "tatami", 0.95)
	p["candle"] = kit.glow(Color(1.0, 0.75, 0.4), 1.4)
	p["sack"] = kit.mat(Color(0.62, 0.52, 0.36), "", 0.9)
	p["gold"] = kit.mat(gold, "metal", 0.3)
	var cfg: Dictionary = {
		"outer": kit.mat(Color(0.93, 0.85, 0.7), "stucco"), "roof": kit.mat(Color(0.72, 0.36, 0.22), "roof"),
		"plaster": p["plaster"], "trim": p["trim"], "ceiling": p["ceiling"], "lit": 0.55,
		"front": [_op(0.0, 2.6), _win(-4.2, 1.6), _win(4.2, 1.6), _win(-12.4, 1.6), _win(12.4, 1.6)],
		"back": [_win(-3.0, 1.4), _win(3.0, 1.4), _win(10.5, 1.6)],
		"west": [_op(2.0, 1.4), _win(-3.5, 1.6)],
		"east": [_op(2.0, 1.4)]}
	_shell(kit, p, cfg)
	_door(kit, p, Vector3(0.0, 0, 6.85), 2.6, Vector3.BACK, "Sol Negro Hacienda entrance")
	_door(kit, p, Vector3(-14.85, 0, 2.0), 1.4, Vector3.LEFT, "Sol Negro Hacienda west door", "door_steel")
	_door(kit, p, Vector3(14.85, 0, 2.0), 1.4, Vector3.RIGHT, "Sol Negro Hacienda east door", "door_steel")
	kit.begin_interior()
	_lining(kit, p, cfg)
	var plaster: Material = p["plaster"]
	# Floors: saltillo in the hall, planks in the study, dark tile in the dining room, talavera in the cantina.
	_floor(kit, Rect2(-14.6, -0.4, 29.2, 7.1), p["saltillo"])
	_floor(kit, Rect2(-14.6, -6.6, 9.5, 5.9), p["parquet"])
	_floor(kit, Rect2(-4.9, -6.6, 9.8, 5.9), p["rug_dark"])
	_floor(kit, Rect2(5.1, -6.6, 9.5, 5.9), p["talavera"])
	_floor(kit, Rect2(-10.6, 0.0, 4.4, 3.4), p["rug"], 0.006)
	_part(kit, Vector2(-14.6, -0.6), Vector2(14.6, -0.6), plaster, [_op(-9.8, 2.0, 0.0, 2.7, "gap"), _op(0.0, 3.6, 0.0, 3.0, "gap"), _op(9.8, 2.0, 0.0, 2.7, "gap")])
	_part(kit, Vector2(-5.0, -6.6), Vector2(-5.0, -0.7), plaster, [_op(-3.5, 1.4, 0.0, 2.7, "gap")])
	_part(kit, Vector2(5.0, -6.6), Vector2(5.0, -0.7), plaster, [_op(-3.5, 1.4, 0.0, 2.7, "gap")])
	# Vigas over the hall, lintels over the arches.
	for x: float in [-12.0, -8.0, -4.0, 0.0, 4.0, 8.0, 12.0]:
		_o(kit, Vector2(x, 3.0), 0.0, 0, 0, CEIL - F - 0.3, 0.25, 0.25, 7.2, p["trim"])
	for arch: Array in [[-9.8, 2.0], [0.0, 3.6], [9.8, 2.0]]:
		_o(kit, Vector2(float(arch[0]), -0.6), 0.0, 0, 0, 2.7, float(arch[1]) + 0.5, 0.2, 0.32, p["trim"])
	# --- Sala (west hall): leather sofa and equipales round the low table, palms.
	_sofa(kit, p, -8.5, 0.15, 0.0, 2.6, "sofa")
	_table(kit, p, -8.5, 1.6, 0.0, 1.6, 0.8, 0.45, "equipale", "dark")
	_sofa(kit, p, -11.3, 1.5, PI * 0.5, 0.95, "sofa")
	_sofa(kit, p, -5.9, 1.5, -PI * 0.5, 0.95, "sofa")
	_plant(kit, p, -13.9, 5.9, 1.6)
	_plant(kit, p, -13.9, 0.2, 1.2)
	_o(kit, Vector2(-4.0, 6.3), 0.0, 0, 0, 0.0, 2.4, 0.45, 0.45, p["equipale"], true)
	# --- Front wall flank: the gun rack cabinet and the lockers either side of the door.
	_o(kit, Vector2(-8.0, 6.37), 0.0, 0, 0, 0.0, 3.0, 0.9, 0.5, p["dark"], true)
	_o(kit, Vector2(-8.0, 6.37), 0.0, 0, 0, 0.9, 3.1, 0.05, 0.56, p["wood"])
	_lockers(kit, p, 8.5, 6.345, PI, 6)
	var table_top: float = _phone_table(kit, p, 0.0, 6.85, 0.76, 0.8, "talavera", "iron")
	# --- East hall: a round table with four chairs, a saddle on its stand by the east door.
	_table(kit, p, 9.5, 3.9, 0.0, 1.3, 1.3, 0.75, "equipale", "dark")
	for chair: Array in [[9.5, 2.85, 0.0], [9.5, 4.95, PI], [8.4, 3.9, PI * 0.5], [10.6, 3.9, -PI * 0.5]]:
		_chair(kit, p, float(chair[0]), float(chair[1]), float(chair[2]), "equipale")
	_plant(kit, p, 13.9, 5.9, 1.6)
	_o(kit, Vector2(13.9, 0.3), 0.0, 0, 0, 0.0, 0.5, 0.9, 1.0, p["equipale"], true)
	_o(kit, Vector2(13.9, 0.3), 0.0, 0, 0, 0.9, 0.4, 0.22, 0.85, p["leather"])
	_hanging(kit, p, -8.5, 1.6, 1.0, "iron", 0.9)
	_hanging(kit, p, 9.5, 3.9, 1.0, "iron", 0.9)
	# --- Study (west back): the patron's desk, a bookcase, the safe, a map, a leather chair.
	_desk(kit, p, -10.0, -3.6, 0.0, 2.4, 1.0)
	_chair(kit, p, -10.0, -4.8, 0.0, "leather")
	_chair(kit, p, -10.9, -2.3, PI)
	_chair(kit, p, -9.1, -2.3, PI)
	_bookcase(kit, p, -9.7, -6.35, 0.0, 4.4)
	_o(kit, Vector2(-13.8, -6.0), 0.0, 0, 0, 0.0, 0.95, 1.15, 0.85, p["black"], true)
	_o(kit, Vector2(-13.8, -6.0), 0.0, 0.0, 0.43, 0.6, 0.2, 0.2, 0.03, p["brass"])
	_wall_map(kit, p, -5.12, -5.6, -PI * 0.5, 1.6, 1.1, 1.3)
	_hanging(kit, p, -10.0, -3.6, 1.1, "iron", 0.8)
	# --- Dining room (centre): the carved table with the map, ten chairs, the shrine on the back wall.
	_table(kit, p, 0.0, -3.4, 0.0, 4.8, 1.3, 0.76, "equipale", "dark")
	_map_sheet(kit, p, 0.0, -3.4, 0.76, 1.1)
	for x: float in [-1.8, -0.6, 0.6, 1.8]:
		_chair(kit, p, x, -2.3, PI, "equipale")
		_chair(kit, p, x, -4.5, 0.0, "equipale")
	_chair(kit, p, -3.0, -3.4, PI * 0.5, "equipale")
	_chair(kit, p, 3.0, -3.4, -PI * 0.5, "equipale")
	_o(kit, Vector2(0.0, -6.25), 0.0, 0, 0, 0.0, 1.8, 0.9, 0.4, p["dark"], true)
	_hanging(kit, p, 0.0, -3.4, 0.9, "iron", 1.1)
	# --- Cantina and import store (east back): the bar under the east wall, crates, sacks, the cash table.
	_counter(kit, p, 12.6, -3.6, -PI * 0.5, 4.4, 0.7, 1.08, "dark", "wood")
	_o(kit, Vector2(14.35, -3.6), 0.0, 0, 0, 0.0, 0.5, 0.92, 4.4, p["dark"], true)
	for y: float in [1.35, 1.8, 2.25]:
		_o(kit, Vector2(14.45, -3.6), 0.0, 0, 0, y, 0.25, 0.03, 4.4, p["wood"])
	for z: float in [-5.2, -4.4, -3.6, -2.8, -2.0]:
		_stool(kit, p, 11.45, z, "leather", 0.72)
	_crate(kit, p, 6.4, -5.7, 0.05, 1.0, 0.8, 0.8)
	_crate(kit, p, 6.4, -4.6, 0.0, 1.0, 0.8, 0.8)
	_o(kit, Vector2(6.4, -5.2), 0.0, 0, 0, 0.8, 0.9, 0.7, 0.9, p["wood"], true)
	_crate(kit, p, 8.0, -6.0, 0.3, 0.8, 0.6, 0.6)
	for index: int in range(3):
		_o(kit, Vector2(7.7 + index * 0.75, -5.0), 0.3 + index * 0.4, 0, 0, 0.0, 0.6, 0.45, 0.9, p["sack"], true)
	_table(kit, p, 8.6, -2.0, 0.0, 1.8, 0.8, 0.76, "wood", "dark")
	_hanging(kit, p, 9.8, -3.6, 1.1, "iron", 0.8)
	# Lamps.
	kit.interior_light(Vector3(0, 3.9, 2.8), Color(1.0, 0.84, 0.6), 2.4, 22.0)
	kit.interior_light(Vector3(-9.8, 3.7, -3.6), Color(1.0, 0.8, 0.55), 1.8, 13.0)
	kit.interior_light(Vector3(9.8, 3.7, -3.6), Color(1.0, 0.86, 0.66), 1.8, 13.0)
	# --- Dressing.
	kit.begin_props()
	_gun_rack(kit, p, 6.62, -1.0, -8.0, 3.0)
	for x: float in [-0.6, -0.2, 0.2, 0.6]:
		kit.prop(Vector3(x, F + 0.92, -6.25), Vector3(0.05, 0.14, 0.05), p["candle"])
	kit.prop(Vector3(0.0, F + 1.95, -6.6), Vector3(0.1, 1.0, 0.04), p["wood"])
	kit.prop(Vector3(0.0, F + 2.15, -6.6), Vector3(0.6, 0.1, 0.04), p["wood"])
	kit.prop(Vector3(0.0, F + 1.4, -6.62), Vector3(1.8, 0.8, 0.02), kit.mat(Color(0.3, 0.12, 0.1), "", 0.9))
	kit.prop(Vector3(-0.5, F + 0.775, -3.4), Vector3(0.1, 0.4, 0.1), p["brass"])
	kit.prop(Vector3(0.5, F + 0.775, -3.4), Vector3(0.1, 0.4, 0.1), p["brass"])
	kit.prop(Vector3(-0.5, F + 1.0, -3.4), Vector3(0.05, 0.1, 0.05), p["candle"])
	kit.prop(Vector3(0.5, F + 1.0, -3.4), Vector3(0.05, 0.1, 0.05), p["candle"])
	var agave: Array[Color] = [Color(0.85, 0.75, 0.4), Color(0.25, 0.35, 0.15), Color(0.7, 0.45, 0.15), Color(0.85, 0.85, 0.8), Color(0.45, 0.1, 0.1)]
	for shelf: int in range(3):
		for index: int in range(11):
			kit.prop_bottle(Vector3(14.42, F + 1.38 + shelf * 0.45, -5.6 + index * 0.4), agave[(index + shelf) % agave.size()], 0.3)
	for z: float in [-5.0, -4.2, -3.4, -2.6, -1.8]:
		kit.prop(Vector3(12.45, F + 1.11, z), Vector3(0.07, 0.12, 0.07), p["glass"])
	var cash: Material = kit.mat(Color(0.45, 0.6, 0.4), "", 0.9)
	for index: int in range(6):
		kit.prop(Vector3(8.1 + (index % 3) * 0.3, F + 0.81 + (index / 3) * 0.06, -2.0 + (index / 3) * 0.12), Vector3(0.22, 0.05, 0.1), cash)
	kit.prop(Vector3(9.2, F + 0.84, -1.9), Vector3(0.3, 0.12, 0.22), p["black"])
	kit.prop(Vector3(-10.0, F + 0.76, -3.7), Vector3(0.7, 0.012, 0.45), p["leather"])
	kit.prop(Vector3(-10.7, F + 0.88, -3.8), Vector3(0.14, 0.2, 0.14), kit.mat(Color(0.3, 0.17, 0.08), "planks", 0.5))
	kit.prop(Vector3(-9.4, F + 0.79, -3.5), Vector3(0.2, 0.06, 0.12), cash)
	for x: float in [-1.5, 0.0, 1.5]:
		kit.prop(Vector3(x, F + 0.8, -2.85), Vector3(0.1, 0.06, 0.1), p["white"])
	var canvas: Material = kit.mat(Color(0.75, 0.45, 0.25), "", 0.9)
	var sky: Material = kit.mat(Color(0.3, 0.5, 0.65), "", 0.9)
	for x: float in [-7.0, -3.0, 3.0, 7.0]:
		_picture(kit, p, x, -0.45, 0.0, 0.8, 0.6, 1.6, canvas if int(x) % 2 == 0 else sky)
	_phone_dressing(kit, p, Vector3(-10.0, F + 0.77, -3.6), 0.0)
	for window: Array in [[-4.2, 6.6, false], [4.2, 6.6, false], [-12.4, 6.6, false], [12.4, 6.6, false], [-3.0, -6.6, false], [3.0, -6.6, false], [10.5, -6.6, false], [-14.6, -3.5, true]]:
		_lattice(kit, p, float(window[0]), float(window[1]), bool(window[2]), 1.5, F + 0.9, 1.55, "iron")
	_fan(kit, p, -4.5, 4.5)
	_fan(kit, p, 4.5, 4.5, 0.8)
	var cream: Color = Color(0.98, 0.93, 0.8)
	_text(kit, "SOL  NEGRO  IMPORTS  -  TODO  TIENE  PRECIO", 0.0, 3.4, 6.6, PI, 26, cream)
	_text(kit, "CASILLEROS", 8.5, 2.35, 6.6, PI, 22, cream)
	_text(kit, "CANTINA  -  TEQUILA  MEZCAL  CERVEZA", 14.5, 3.0, -3.6, -PI * 0.5, 22, cream)
	_text(kit, "NUESTRA  SENORA  DEL  SOL", 0.0, 2.75, -6.6, 0.0, 22, cream)
	kit.end_props()
	kit.end_interior()
	var routes: Dictionary = {
		"to_street": _path([Vector2(0, 2.65), Vector2(0, 6.85), Vector2(0, 10.0), Vector2(5.0, 13.0), Vector2(5.0, 22.0), Vector2(1.8, 27.0), Vector2(1.8, 33.0), Vector2(1.8, 37.2)]),
		"west_door": _path([Vector2(0, 2.65), Vector2(-2.0, 4.6), Vector2(-13.0, 4.6), Vector2(-13.0, 2.0), Vector2(-14.85, 2.0), Vector2(-18.0, 2.0)]),
		"east_door": _path([Vector2(0, 2.65), Vector2(2.0, 1.0), Vector2(12.0, 1.0), Vector2(13.0, 2.0), Vector2(14.85, 2.0), Vector2(18.0, 2.0)])}
	# The delivery point is nudged so that the spot 2.5 m from it towards the map centre (tests/map_interiors.gd's
	# reading of main.gd's old spawn rule) is clear floor.
	return _info(0.0, 6.85, table_top, routes, Vector2(-0.25, 0.0))


# =====================================================================================================
# KINGSWAY COURTS. The tenants' community room at the foot of the tallest slab: cream-and-mint cinder
# block under fluorescent tubes, linoleum, folding tables and stacking chairs, a vending machine and a
# church-hall kitchen, with the Royals' rec room at the west end (pool table, a couch round the TV, arcade
# cabinets, a trophy case, the crown mural). 36 x 12, front faces +Z onto the courtyard; the north end
# and the back wall have their own doors.
# =====================================================================================================

static func _kingsway(kit: Kit, p: Dictionary) -> Dictionary:
	var teal: Color = Factions.color("kingsway")
	var pink: Color = Color(0.95, 0.3, 0.7)
	var yellow: Color = Color(0.98, 0.82, 0.2)
	var blue: Color = Color(0.35, 0.55, 1.0)
	p["plaster"] = kit.mat(Color(0.78, 0.86, 0.82), "stucco", 0.9)
	p["trim"] = kit.mat(Color(0.3, 0.3, 0.3), "", 0.6)
	p["ceiling"] = kit.mat(Color(0.86, 0.86, 0.82), "", 0.95)
	p["linoleum"] = kit.mat(Color(0.74, 0.72, 0.62), "tiles", 0.6)
	p["carpet"] = kit.mat(Color(0.16, 0.26, 0.3), "tatami", 0.95)
	p["felt"] = kit.mat(Color(0.05, 0.36, 0.3), "", 0.95)
	p["leather"] = kit.mat(Color(0.3, 0.19, 0.12), "", 0.5)
	p["sofa"] = kit.mat(Color(0.14, 0.4, 0.42), "", 0.85)
	p["plastic"] = kit.mat(Color(0.12, 0.3, 0.34), "", 0.5)
	p["formica"] = kit.mat(Color(0.78, 0.74, 0.6), "", 0.55)
	p["cab"] = kit.mat(Color(0.82, 0.83, 0.76), "", 0.6)
	p["vend"] = kit.mat(Color(0.72, 0.12, 0.12), "", 0.4)
	p["tube"] = kit.glow(Color(0.95, 0.98, 1.0), 1.3)
	p["paint_teal"] = kit.mat(teal, "", 0.7)
	p["paint_pink"] = kit.mat(pink, "", 0.7)
	p["paint_yellow"] = kit.mat(yellow, "", 0.7)
	p["paint_blue"] = kit.mat(blue, "", 0.7)
	p["cork"] = kit.mat(Color(0.6, 0.45, 0.28), "", 0.95)
	p["gold"] = kit.mat(Color(0.85, 0.7, 0.25), "metal", 0.3)
	p["cabinet"] = kit.mat(Color(0.3, 0.12, 0.35), "", 0.5)
	var cfg: Dictionary = {
		"outer": kit.mat(Color(0.58, 0.58, 0.56), "panel"), "roof": kit.mat(Color(0.3, 0.3, 0.3), "roof"),
		"plaster": p["plaster"], "trim": p["trim"], "ceiling": p["ceiling"], "lit": 0.4,
		"front": [_op(7.0, 2.4), _win(-8.5, 1.8), _win(-5.0, 1.4), _win(15.2, 1.6)],
		"back": [_op(-10.0, 1.4), _win(-6.0, 1.4)],
		"west": [_win(-3.5, 2.0)],
		"east": [_op(0.0, 1.4)]}
	_shell(kit, p, cfg)
	_door(kit, p, Vector3(7.0, 0, 5.85), 2.4, Vector3.BACK, "Kingsway Courts community room entrance")
	_door(kit, p, Vector3(17.85, 0, 0.0), 1.4, Vector3.RIGHT, "Kingsway Courts north door", "door_steel")
	_door(kit, p, Vector3(-10.0, 0, -5.85), 1.4, Vector3.FORWARD, "Kingsway Courts rear door", "door_steel")
	kit.begin_interior()
	_lining(kit, p, cfg)
	var plaster: Material = p["plaster"]
	_floor(kit, Rect2(-2.9, -5.6, 20.5, 11.2), p["linoleum"])
	_floor(kit, Rect2(-17.6, -5.6, 14.4, 11.2), p["carpet"])
	# The rec room's east wall, open at the middle (a wide doorway) and by the back.
	_part(kit, Vector2(-3.0, -5.6), Vector2(-3.0, 5.6), plaster, [_op(1.0, 3.2, 0.0, 2.7, "gap"), _op(-3.6, 1.2, 0.0, 2.7, "gap")])
	# Fluorescent tubes.
	for line: float in [-2.6, 2.6]:
		for x: float in [-14.0, -9.0, -4.5, 0.5, 4.5, 8.5, 12.5, 16.0]:
			_o(kit, Vector2(x, line), 0.0, 0, 0, CEIL - F - 0.06, 1.3, 0.05, 0.14, p["tube"])
	# --- Rec room (west).
	_pool(kit, p, -8.5, -1.3, 0.0)
	_hanging(kit, p, -8.5, -1.3, 0.85, "felt", 1.5)
	_o(kit, Vector2(-17.2, 0.0), 0.0, 0, 0, 0.0, 0.7, 0.5, 2.2, p["dark"], true)
	_sofa(kit, p, -14.2, 0.0, -PI * 0.5, 2.6, "sofa")
	_sofa(kit, p, -14.2, 3.4, -PI * 0.5, 1.7, "sofa")
	_sofa(kit, p, -14.2, -3.4, -PI * 0.5, 1.7, "sofa")
	_table(kit, p, -12.0, 0.0, PI * 0.5, 1.3, 0.7, 0.42, "formica", "steel")
	_arcade(kit, p, -16.0, 5.25, PI, kit.mat(Color(0.12, 0.12, 0.3), "", 0.5), kit.glow(Color(0.3, 0.85, 0.5), 0.9))
	_arcade(kit, p, -14.9, 5.25, PI, kit.mat(Color(0.3, 0.1, 0.12), "", 0.5), kit.glow(Color(0.9, 0.5, 0.25), 0.9))
	_o(kit, Vector2(-11.5, 5.3), PI, 0, 0, 0.0, 2.2, 1.9, 0.5, p["dark"], true)
	_o(kit, Vector2(-11.5, 5.3), PI, 0, 0.26, 0.3, 1.9, 1.4, 0.02, p["glass"])
	_o(kit, Vector2(-4.4, 5.25), PI, 0, 0, 0.0, 0.9, 1.5, 0.6, p["cabinet"], true)
	_o(kit, Vector2(-4.4, 5.25), PI, 0, 0.31, 0.55, 0.78, 0.8, 0.02, p["glow_accent"])
	for stool_x: float in [-8.0, -7.0]:
		_stool(kit, p, stool_x, 1.3, "leather", 0.72)
	# --- Community hall (east): front flank, phone table, kitchen run, tables, vending, manager's corner.
	_o(kit, Vector2(1.5, 5.37), 0.0, 0, 0, 0.0, 3.0, 0.9, 0.5, p["dark"], true)
	_o(kit, Vector2(1.5, 5.37), 0.0, 0, 0, 0.9, 3.1, 0.05, 0.56, p["wood"])
	_lockers(kit, p, 11.0, 5.345, PI, 6)
	var table_top: float = _phone_table(kit, p, 7.0, 5.85, 0.76, 0.8, "formica", "steel")
	_counter(kit, p, 7.0, -5.3, 0.0, 6.4, 0.65, 0.92, "cab", "formica")
	_o(kit, Vector2(7.0, -5.45), 0.0, 0, 0, 1.5, 6.4, 0.7, 0.35, p["cab"])
	_o(kit, Vector2(11.2, -5.2), 0.0, 0, 0, 0.0, 0.85, 1.9, 0.8, p["steel"], true)
	_counter(kit, p, 14.0, -5.3, 0.0, 4.8, 0.65, 0.92, "cab", "formica")
	_o(kit, Vector2(14.0, -5.45), 0.0, 0, 0, 1.5, 4.8, 0.7, 0.35, p["cab"])
	_o(kit, Vector2(17.05, -5.2), 0.0, 0, 0, 0.0, 0.9, 1.9, 0.8, p["steel"], true)
	_table(kit, p, 4.5, -2.0, 0.0, 3.6, 0.8, 0.74, "formica", "steel")
	_map_sheet(kit, p, 4.5, -2.0, 0.74, 0.7)
	for x: float in [3.3, 4.5, 5.7]:
		_chair(kit, p, x, -1.05, PI, "plastic")
		_chair(kit, p, x, -2.95, 0.0, "plastic")
	_table(kit, p, 12.0, -2.4, 0.0, 1.8, 0.8, 0.74, "formica", "steel")
	_table(kit, p, 15.3, -2.4, 0.0, 1.8, 0.8, 0.74, "formica", "steel")
	for x: float in [11.4, 12.6, 14.7, 15.9]:
		_chair(kit, p, x, -3.3, 0.0, "plastic")
		_chair(kit, p, x, -1.5, PI, "plastic")
	_vending(kit, p, 17.1, 3.4, -PI * 0.5, p["vend"])
	_vending(kit, p, 17.1, 4.5, -PI * 0.5, kit.mat(Color(0.15, 0.3, 0.6), "", 0.4))
	_desk(kit, p, 0.6, -4.45, 0.0, 1.6, 0.8, "wood")
	_chair(kit, p, 0.6, -5.25, 0.0, "plastic")
	_o(kit, Vector2(2.6, -5.3), 0.0, 0, 0, 0.0, 0.5, 1.35, 0.6, p["steel"], true)
	_o(kit, Vector2(-2.1, -5.1), 0.0, 0, 0, 0.0, 0.9, 1.1, 0.9, p["black"], true)
	_o(kit, Vector2(-2.1, -5.1), 0.0, 0.0, 0.46, 0.6, 0.2, 0.2, 0.03, p["brass"])
	# Bulletin board on the rec room wall.
	_o(kit, Vector2(-2.87, -1.8), PI * 0.5, 0, 0, 1.1, 1.6, 1.0, 0.04, p["cork"])
	# Lamps: rec room, west hall, east hall.
	kit.interior_light(Vector3(-10.0, 3.7, 0.0), Color(1.0, 0.92, 0.8), 1.9, 14.0)
	kit.interior_light(Vector3(2.0, 3.9, 0.0), Color(0.96, 0.98, 0.94), 2.0, 14.0)
	kit.interior_light(Vector3(12.0, 3.9, 0.0), Color(0.96, 0.98, 0.94), 2.0, 14.0)
	# --- Dressing.
	kit.begin_props()
	_gun_rack(kit, p, 5.62, -1.0, 1.5, 3.0)
	_phone_dressing(kit, p, Vector3(0.6, F + 0.77, -4.45), 0.0)
	kit.prop(Vector3(-17.2, F + 0.92, 0.0), Vector3(0.55, 0.84, 1.5), p["black"])
	kit.prop(Vector3(-16.9, F + 0.92, 0.0), Vector3(0.02, 0.68, 1.3), kit.glow(Color(0.4, 0.7, 0.9), 0.9))
	var balls: Array[Material] = [kit.mat(Color(0.9, 0.85, 0.2), "", 0.3), kit.mat(Color(0.75, 0.1, 0.1), "", 0.3), kit.mat(Color(0.1, 0.1, 0.6), "", 0.3), kit.mat(Color(0.95, 0.95, 0.9), "", 0.3)]
	for index: int in range(8):
		kit.prop(Vector3(-8.0 + (index % 4) * 0.1 + (index / 4) * 0.06, F + 0.9, -1.35 + (index / 4) * 0.1), Vector3(0.055, 0.055, 0.055), balls[index % 4])
	for index: int in range(4):
		kit.prop(Vector3(-3.2, F + 1.1 + index * 0.0, -2.6 + index * 0.18), Vector3(0.03, 1.4, 0.03), p["wood"], 0.0)
	kit.prop(Vector3(-3.17, F + 0.8, -2.25), Vector3(0.05, 0.05, 0.9), p["dark"])
	for index: int in range(6):
		kit.prop(Vector3(-12.2 + (index % 3) * 0.6, F + 0.95 + (index / 3) * 0.6, 5.0), Vector3(0.12, 0.26 + (index % 2) * 0.06, 0.1), p["gold"] if index % 2 == 0 else p["brass"])
	var chip: Material = kit.mat(Color(0.9, 0.55, 0.2), "", 0.6)
	var cup: Material = kit.mat(Color(0.95, 0.95, 0.92), "", 0.4)
	for table_x: float in [4.5, 12.0, 15.3]:
		kit.prop(Vector3(table_x - 0.5, F + 0.77, -2.2 if table_x == 4.5 else -2.4), Vector3(0.08, 0.1, 0.08), cup)
		kit.prop(Vector3(table_x + 0.6, F + 0.76, -2.5), Vector3(0.28, 0.03, 0.2), chip)
	kit.prop(Vector3(13.2, F + 1.05, -5.25), Vector3(0.45, 0.25, 0.35), p["steel"])
	kit.prop(Vector3(9.8, F + 1.05, -5.3), Vector3(0.3, 0.3, 0.3), p["steel"])
	kit.prop(Vector3(16.2, F + 1.05, -5.3), Vector3(0.16, 0.36, 0.16), p["steel"])
	# Mural: the Royals' crown across the rec room's back wall, tags beside it.
	var crown_x: float = -14.4
	kit.prop(Vector3(crown_x, F + 2.0, -5.6), Vector3(3.2, 0.5, 0.03), p["paint_teal"])
	for index: int in range(5):
		var spike: float = -1.4 + float(index) * 0.7
		kit.prop(Vector3(crown_x + spike, F + 2.65 + (0.25 if index % 2 == 0 else 0.0), -5.6), Vector3(0.3, 0.75 + (0.5 if index % 2 == 0 else 0.0), 0.03), p["paint_teal"])
		kit.prop(Vector3(crown_x + spike, F + 3.0 + (0.5 if index % 2 == 0 else 0.0), -5.59), Vector3(0.16, 0.16, 0.03), p["paint_yellow"])
	kit.prop(Vector3(crown_x, F + 2.0, -5.59), Vector3(2.9, 0.12, 0.03), p["paint_yellow"])
	kit.prop(Vector3(crown_x, F + 1.2, -5.6), Vector3(3.4, 0.7, 0.02), p["paint_pink"])
	kit.prop(Vector3(crown_x - 2.2, F + 1.6, -5.6), Vector3(0.12, 1.6, 0.02), p["paint_blue"], 0.3)
	kit.prop(Vector3(crown_x + 2.3, F + 2.4, -5.6), Vector3(0.12, 1.9, 0.02), p["paint_blue"], -0.25)
	for window: Array in [[-8.5, 5.6, false], [-5.0, 5.6, false], [15.2, 5.6, false], [-6.0, -5.6, false], [-17.6, -3.5, true]]:
		_lattice(kit, p, float(window[0]), float(window[1]), bool(window[2]), 1.4, F + 0.9, 1.55, "steel")
	var white: Color = Color(0.97, 0.98, 0.95)
	_text(kit, "KINGSWAY  COURTS  TENANTS'  ASSOCIATION", 4.0, 3.3, 5.6, PI, 26, white)
	_text(kit, "TENANTS'  LOCKERS", 11.0, 2.35, 5.6, PI, 22, white)
	_text(kit, "ROYALS", crown_x, 1.05, -5.55, 0.0, 70, white)
	_text(kit, "HOLD  THE  BLOCK.", 9.0, 3.2, -5.6, 0.0, 34, white)
	_text(kit, "COMMUNITY  ROOM  -  PLEASE  KEEP  IT  CLEAN", 14.0, 2.75, -5.6, 0.0, 20, white)
	_text(kit, "NOTICES", -2.85, 2.3, -1.8, PI * 0.5, 22, white)
	kit.end_props()
	kit.end_interior()
	var routes: Dictionary = {
		"to_street": _path([Vector2(7.0, 1.65), Vector2(7.0, 5.85), Vector2(7.0, 8.0), Vector2(14.0, 8.0), Vector2(20.0, 8.0), Vector2(22.4, 12.5)]),
		"north_door": _path([Vector2(7.0, 1.65), Vector2(9.0, 0.4), Vector2(17.85, 0.0), Vector2(21.0, 0.0), Vector2(23.5, 0.0)]),
		"rear_door": _path([Vector2(7.0, 1.65), Vector2(5.0, 0.0), Vector2(2.0, 0.0), Vector2(-3.0, 1.0), Vector2(-6.0, 1.0), Vector2(-6.0, -3.8), Vector2(-10.0, -3.8), Vector2(-10.0, -5.85), Vector2(-10.0, -8.5)])}
	return _info(7.0, 5.85, table_top, routes, Vector2(0.0, -0.5))
