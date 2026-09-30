extends RefCounted
## Plot "highrise": HALCYON TRUST, an eighteen-storey office tower frozen at the end of 1999. This
## pass fits the lobby and the second-floor claims office under a sealed tower: glass frontage,
## security desk, building directory, planters and benches; two working lifts side by side at the
## back of the lobby and two U-stairwells at opposite corners (front-east, back-west), so the upper
## floor has no single chokepoint; an open-plan office with cubicles, a glass-walled corner
## conference room, copier and water cooler, and a rear service door.
## Local frame (BuildingKit): +Z = out of the front door, +X along the facade. Half size 15 x 15.

const BuildingKit = preload("res://scripts/buildings/building_kit.gd")
const Rooms = preload("res://scripts/buildings/neighborhood_rooms.gd")

const HALF: Vector2 = Vector2(15, 15)
const FLOORS: Array[float] = [0.17, 4.77]
const OFFICE_TOP: float = 8.37
const TOWER_TOP: float = 62.0
const LIFT_A: Rect2 = Rect2(-4.2, -9.0, 2.4, 2.6)
const LIFT_B: Rect2 = Rect2(1.8, -9.0, 2.4, 2.6)
## Stair A (back-west) rises toward the back wall and returns; stair B (front-east) toward the front.
const STAIR_A: Vector3 = Vector3(-12.4, 0.17, -8.7)
const STAIR_B: Vector3 = Vector3(12.4, 0.17, 8.7)
const HOLE_A: Rect2 = Rect2(-14.6, -14.6, 3.0, 5.9)
const HOLE_B: Rect2 = Rect2(11.6, 8.7, 3.0, 5.9)
const WEST_ROUTE: Array[Vector3] = [Vector3(0, 0.17, 16.6), Vector3(0, 0.17, 11.0), Vector3(-9.0, 0.17, -2.0), Vector3(-12.4, 0.17, -7.6),
	Vector3(-12.4, 0.17, -8.4), Vector3(-12.4, 2.47, -12.4), Vector3(-12.4, 2.47, -13.3), Vector3(-13.8, 2.47, -13.3), Vector3(-13.8, 2.47, -12.4),
	Vector3(-13.8, 4.77, -8.4), Vector3(-13.8, 4.77, -7.4), Vector3(-9.0, 4.77, -4.0), Vector3(-7.0, 4.77, 2.0)]
const EAST_ROUTE: Array[Vector3] = [Vector3(0, 0.17, 16.6), Vector3(0, 0.17, 11.0), Vector3(9.5, 0.17, 7.0), Vector3(12.4, 0.17, 7.6),
	Vector3(12.4, 0.17, 8.4), Vector3(12.4, 2.47, 12.4), Vector3(12.4, 2.47, 13.3), Vector3(13.8, 2.47, 13.3), Vector3(13.8, 2.47, 12.4),
	Vector3(13.8, 4.77, 8.4), Vector3(13.8, 4.77, 7.4), Vector3(9.0, 4.77, 4.0)]
const SERVICE_ROUTE: Array[Vector3] = [Vector3(0, 0.17, 11.0), Vector3(6.0, 0.17, -3.0), Vector3(8.0, 0.17, -12.5), Vector3(8.0, 0.17, -16.6)]


static func build(world: Node3D, plot: Dictionary) -> void:
	var kit: BuildingKit = BuildingKit.new(world, "Highrise", plot)
	var granite: Material = kit.mat(Color(0.3, 0.32, 0.34), "tiles", 0.5)
	var panel: Material = kit.mat(Color(0.42, 0.5, 0.57), "panel")
	var carpet: Material = kit.mat(Color(0.28, 0.3, 0.36), "tatami", 0.95)
	var plaster: Material = kit.mat(Color(0.8, 0.79, 0.74), "stucco")
	var rect: Rect2 = Rect2(-HALF, HALF * 2.0)
	kit.footprint(rect)
	kit.floor_slab(rect, FLOORS[0], granite)
	kit.floor_slab(rect, FLOORS[1], carpet, [LIFT_A, LIFT_B, HOLE_A, HOLE_B])
	kit.floor_slab(rect, OFFICE_TOP, kit.mat(Color(0.7, 0.7, 0.68), "panel"), [LIFT_A, LIFT_B])
	# Lobby shell: glass frontage with double doors, a service door at the back.
	kit.wall(Vector2(-HALF.x, HALF.y), Vector2(HALF.x, HALF.y), FLOORS[1], granite, [
		BuildingKit.opening(HALF.x, 3.0), BuildingKit.opening(HALF.x - 7.5, 8.0, 0.4, 3.9, "window"), BuildingKit.opening(HALF.x + 7.5, 8.0, 0.4, 3.9, "window")])
	kit.wall(Vector2(-HALF.x, -HALF.y), Vector2(HALF.x, -HALF.y), FLOORS[1], granite, [BuildingKit.opening(HALF.x + 8.0, 1.6)])
	kit.wall(Vector2(-HALF.x, -HALF.y), Vector2(-HALF.x, HALF.y), FLOORS[1], granite)
	kit.wall(Vector2(HALF.x, -HALF.y), Vector2(HALF.x, HALF.y), FLOORS[1], granite)
	kit.add_door(Vector3(0, FLOORS[0], HALF.y), 3.0, 2.8, Vector3.BACK, "Halcyon Trust entrance", "door", kit.glass_material())
	kit.add_door(Vector3(8, FLOORS[0], -HALF.y), 1.6, 2.6, Vector3.FORWARD, "Halcyon Trust service door", "door", kit.mat(Color(0.4, 0.42, 0.42), "metal", 0.6))
	# Office floor shell: ribbon windows on every side (breakable glass).
	var ribbon: Array = []
	for index: int in range(5):
		ribbon.append(BuildingKit.opening(3.0 + index * 6.0, 4.2, 0.9, 2.6, "window"))
	for wall_line: Array in [[Vector2(-HALF.x, HALF.y), Vector2(HALF.x, HALF.y)], [Vector2(-HALF.x, -HALF.y), Vector2(HALF.x, -HALF.y)],
			[Vector2(-HALF.x, -HALF.y), Vector2(-HALF.x, HALF.y)], [Vector2(HALF.x, -HALF.y), Vector2(HALF.x, HALF.y)]]:
		kit.wall(wall_line[0], wall_line[1], OFFICE_TOP - FLOORS[1], panel, ribbon, FLOORS[1])
	# Lifts (both serve both floors), stairs and rails round the stair holes on the office floor.
	var lift_wall: Material = kit.mat(Color(0.55, 0.5, 0.42), "metal", 0.5)
	var lift_a: int = kit.lift(LIFT_A, FLOORS, Vector3.BACK, "Halcyon Trust lift A", lift_wall)
	var lift_b: int = kit.lift(LIFT_B, FLOORS, Vector3.BACK, "Halcyon Trust lift B", lift_wall)
	kit.node.set_meta("lifts", [lift_a, lift_b])
	# A wall in the niche between the two shafts carries the company plaque.
	kit.wall(Vector2(-1.65, -7.7), Vector2(1.65, -7.7), FLOORS[1] - FLOORS[0], plaster, [], FLOORS[0], 0.2)
	var steel: Material = kit.mat(Color(0.3, 0.32, 0.34), "metal", 0.6)
	kit.stairs_u(STAIR_A, Vector3.FORWARD, FLOORS[1] - FLOORS[0], 1.2, 0.2, steel)
	kit.stairs_u(STAIR_B, Vector3.BACK, FLOORS[1] - FLOORS[0], 1.2, 0.2, steel)
	# Stairwell walls on the lobby side (fire doors are open arches) and rails on the office floor.
	kit.wall(Vector2(-11.3, -14.85), Vector2(-11.3, -8.4), FLOORS[1] - FLOORS[0], plaster, [], FLOORS[0], 0.2)
	kit.wall(Vector2(11.3, 14.85), Vector2(11.3, 8.4), FLOORS[1] - FLOORS[0], plaster, [], FLOORS[0], 0.2)
	kit.railing(Vector3(HOLE_A.end.x, FLOORS[1], HOLE_A.position.y), Vector3(HOLE_A.end.x, FLOORS[1], HOLE_A.end.y))
	kit.railing(Vector3(HOLE_A.end.x - 1.4, FLOORS[1], HOLE_A.end.y), Vector3(HOLE_A.end.x, FLOORS[1], HOLE_A.end.y))
	kit.railing(Vector3(HOLE_B.position.x, FLOORS[1], HOLE_B.position.y), Vector3(HOLE_B.position.x, FLOORS[1], HOLE_B.end.y))
	kit.railing(Vector3(HOLE_B.position.x, FLOORS[1], HOLE_B.position.y), Vector3(HOLE_B.position.x + 1.4, FLOORS[1], HOLE_B.position.y))
	_tower(kit, panel)
	_street_front(kit)
	kit.begin_interior()
	_lobby(kit)
	_office(kit)
	kit.interior_light(Vector3(0, 3.8, 4.0), Color(0.95, 0.95, 0.88), 2.4, 22.0)
	kit.interior_light(Vector3(0, OFFICE_TOP - 0.6, 0.0), Color(0.9, 0.95, 1.0), 2.2, 22.0)
	_office_props(kit)
	kit.end_interior()
	kit.world._landmark("HALCYON TRUST", Vector3(0, 0, HALF.y + 5.0))
	kit.node.set_meta("walk_in", true)
	kit.node.set_meta("interior_half", HALF)
	kit.node.set_meta("routes", {"west_stair": WEST_ROUTE, "east_stair": EAST_ROUTE, "service": SERVICE_ROUTE})
	kit.finish_props()
	kit.finish()


## Sealed tower above the office floor: solid mass, a deterministic lit-window pattern (no RNG),
## a crown and roof plant.
static func _tower(kit: BuildingKit, panel: Material) -> void:
	kit.box(Vector3(0, (OFFICE_TOP + TOWER_TOP) * 0.5, 0), Vector3(HALF.x * 2, TOWER_TOP - OFFICE_TOP, HALF.y * 2), panel, true)
	var dark: Material = kit.mat(Color(0.14, 0.2, 0.26), "", 0.25)
	var lit: Material = kit.glow(Color(0.9, 0.95, 1.0), 1.1)
	var rows: int = int((TOWER_TOP - OFFICE_TOP - 1.0) / 3.4)
	for face: int in range(4):
		var normal: Vector3 = [Vector3.BACK, Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT][face]
		var along: Vector3 = Vector3.UP.cross(normal)
		var angle: float = atan2(normal.x, normal.z)
		for row: int in range(rows):
			var y: float = OFFICE_TOP + 1.9 + row * 3.4
			var pattern: int = (row * 5 + face * 3) % 13
			kit.box(normal * (HALF.x + 0.05) + Vector3(0, y, 0), Vector3(HALF.x * 2 - 1.0, 1.5, 0.1), lit if pattern < 2 else dark, false, angle)
			if pattern >= 2 and pattern < 4:
				kit.box(normal * (HALF.x + 0.07) + along * ((row % 3) - 1) * 7.0 + Vector3(0, y, 0), Vector3(3.0, 1.5, 0.1), lit, false, angle)
	kit.box(Vector3(0, TOWER_TOP + 0.6, 0), Vector3(HALF.x * 2 + 0.6, 1.2, HALF.y * 2 + 0.6), kit.mat(Color(0.3, 0.34, 0.38), "metal", 0.5))
	kit.box(Vector3(-5, TOWER_TOP + 2.4, -4), Vector3(8.0, 2.4, 6.0), kit.mat(Color(0.5, 0.52, 0.52), "metal", 0.6))
	kit.box(Vector3(7, TOWER_TOP + 5.0, 6), Vector3(0.3, 8.0, 0.3), kit.mat(Color(0.6, 0.2, 0.15), "metal"))
	kit.box(Vector3(7, TOWER_TOP + 9.1, 6), Vector3(0.4, 0.3, 0.4), kit.glow(Color(1.0, 0.2, 0.15), 2.0))


static func _street_front(kit: BuildingKit) -> void:
	kit.neon_sign("HALCYON  TRUST", Vector3(0, FLOORS[1] - 0.4, HALF.y + 0.35), 0.0, Color(0.7, 0.9, 1.0), 72)
	kit.box(Vector3(0, 3.9, HALF.y + 1.8), Vector3(8.0, 0.25, 3.6), kit.mat(Color(0.25, 0.27, 0.3), "metal", 0.5))
	for x: float in [-3.9, 3.9]:
		kit.box(Vector3(x, 1.95, HALF.y + 3.5), Vector3(0.14, 3.9, 0.14), kit.mat(Color(0.6, 0.62, 0.64), "metal", 0.3), true)
	kit.sign_label("1999", Vector3(0, 3.6, HALF.y + 3.62), 26, Color(0.8, 0.84, 0.88))


static func _lobby(kit: BuildingKit) -> void:
	var wood: Material = kit.mat(Color(0.35, 0.22, 0.14), "planks")
	var granite: Material = kit.mat(Color(0.2, 0.2, 0.22), "", 0.25)
	# Security desk facing the doors, with a CCTV bank and a sign-in book.
	kit.box(Vector3(0, FLOORS[0] + 0.55, 2.0), Vector3(5.0, 1.1, 0.8), wood, true)
	kit.box(Vector3(0, FLOORS[0] + 1.13, 2.0), Vector3(5.2, 0.06, 1.0), granite, true)
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(side * 2.9, FLOORS[0] + 0.55, 1.2), Vector3(0.8, 1.1, 2.4), wood, true)
	for index: int in range(4):
		kit.box(Vector3(-1.2 + index * 0.8, FLOORS[0] + 1.42, 1.75), Vector3(0.6, 0.45, 0.4), kit.mat(Color(0.2, 0.2, 0.2), "metal"))
		kit.box(Vector3(-1.2 + index * 0.8, FLOORS[0] + 1.42, 1.98), Vector3(0.48, 0.34, 0.02), kit.glow(Color(0.5, 0.7, 0.6), 0.5))
	kit.box(Vector3(1.6, FLOORS[0] + 1.18, 2.2), Vector3(0.5, 0.04, 0.35), kit.mat(Color(0.15, 0.2, 0.35)))
	kit.sign_label("ALL VISITORS MUST SIGN IN", Vector3(0, FLOORS[0] + 0.8, 2.42), 14, Color(0.85, 0.8, 0.6))
	# Directory board beside the lifts: most floors empty since the move.
	kit.box(Vector3(-7.0, FLOORS[0] + 1.8, -7.6), Vector3(2.4, 2.0, 0.12), granite)
	kit.sign_label("HALCYON TRUST\n\nLOBBY . . . . . SECURITY\n2 . . . . . CLAIMS DEPT\n3-18 . . . . CLOSED FOR\n   RENOVATION  (Y2K)", Vector3(-7.0, FLOORS[0] + 1.8, -7.53), 14, Color(0.9, 0.9, 0.85))
	kit.box(Vector3(0, FLOORS[0] + 3.4, -7.55), Vector3(3.2, 0.7, 0.1), kit.mat(Color(0.75, 0.62, 0.35), "metal", 0.3))
	kit.sign_label("HALCYON  TRUST", Vector3(0, FLOORS[0] + 3.4, -7.49), 28, Color(0.12, 0.1, 0.08))
	# Planters and benches along the glass.
	for x: float in [-10.0, -4.5, 4.5, 10.0]:
		kit.box(Vector3(x, FLOORS[0] + 0.3, 12.8), Vector3(1.4, 0.6, 1.0), granite, true)
		kit.box(Vector3(x, FLOORS[0] + 1.0, 12.8), Vector3(1.1, 0.9, 0.8), kit.mat(Color(0.2, 0.34, 0.18)))
	# Ceiling: a plaster lining under the office slab with a grid of light panels (visual only).
	var lining_y: float = FLOORS[1] - 0.32
	kit.box(Vector3(0, lining_y, 3.0), Vector3(HALF.x * 2 - 0.4, 0.03, 23.4), kit.mat(Color(0.82, 0.8, 0.74), "stucco"))
	for x: float in [-9.0, -3.0, 3.0, 9.0]:
		for z: float in [-3.0, 3.0, 9.0]:
			kit.box(Vector3(x, lining_y - 0.02, z), Vector3(1.8, 0.02, 1.2), kit.glow(Color(1.0, 0.95, 0.85), 1.1))
	# Two waiting groups on rugs: leather sofas, low tables, the day's papers.
	for side: float in [-1.0, 1.0]:
		var at: Vector3 = Vector3(side * 9.8, FLOORS[0], 4.0)
		kit.box(at + Vector3(0, 0.006, 0), Vector3(5.0, 0.012, 4.0), kit.mat(Color(0.4, 0.12, 0.1), "tatami", 0.95))
		kit.box(at + Vector3(0, 0.22, -1.4), Vector3(3.2, 0.44, 0.9), kit.mat(Color(0.12, 0.1, 0.09), "", 0.45), true)
		kit.box(at + Vector3(0, 0.7, -1.8), Vector3(3.2, 0.6, 0.2), kit.mat(Color(0.12, 0.1, 0.09), "", 0.45), true)
		kit.box(at + Vector3(0, 0.2, 0.2), Vector3(1.6, 0.4, 0.8), granite, true)
		kit.box(at + Vector3(0.3, 0.42, 0.2), Vector3(0.5, 0.04, 0.35), kit.mat(Color(0.85, 0.83, 0.78)))
	for x: float in [-8.0, 8.0]:
		kit.box(Vector3(x, FLOORS[0] + 0.23, 9.5), Vector3(2.6, 0.12, 0.7), wood)
		for dx: float in [-1.0, 1.0]:
			kit.box(Vector3(x + dx, FLOORS[0] + 0.1, 9.5), Vector3(0.12, 0.22, 0.6), granite)


## Claims office: cubicle rows, a glass conference room in the front-west corner, copier, cooler,
## filing wall and a manager's desk by the east windows. Stair holes and lift doors stay clear.
static func _office(kit: BuildingKit) -> void:
	var y: float = FLOORS[1]
	var partition: Material = kit.mat(Color(0.5, 0.52, 0.5), "panel", 0.95)
	for row: int in range(2):
		var z: float = -1.5 + row * 5.5
		for index: int in range(3):
			var x: float = -3.0 + index * 4.0
			kit.box(Vector3(x, y + 0.75, z), Vector3(3.8, 1.5, 0.08), partition, true)
			kit.box(Vector3(x - 1.9, y + 0.75, z + 1.2), Vector3(0.08, 1.5, 2.4), partition, true)
			Rooms.desk(kit, Vector3(x + 0.2, y, z + 1.1))
	# Conference room: glass partitions (breakable), table, chairs, whiteboard.
	kit.glass_pane(Vector3(-8.0, y + 1.4, 11.0), Vector3(0.06, 2.6, 7.4))
	kit.glass_pane(Vector3(-11.5, y + 1.4, 7.2), Vector3(6.8, 2.6, 0.06))
	kit.box(Vector3(-11.5, y + 0.75, 11.0), Vector3(4.0, 0.08, 1.8), kit.mat(Color(0.3, 0.2, 0.12), "planks"), true)
	for dx: float in [-1.4, 0.0, 1.4]:
		for dz: float in [-1.3, 1.3]:
			kit.box(Vector3(-11.5 + dx, y + 0.25, 11.0 + dz), Vector3(0.5, 0.5, 0.5), kit.mat(Color(0.12, 0.12, 0.14)))
	kit.box(Vector3(-14.8, y + 1.6, 11.0), Vector3(0.04, 1.2, 2.4), kit.mat(Color(0.95, 0.95, 0.93)))
	kit.sign_label("Q4 LOSSES?\nY2K PLAN", Vector3(-14.76, y + 1.7, 11.0), 16, Color(0.2, 0.2, 0.6), PI * 0.5)
	# Services by the lifts: copier, water cooler, filing cabinets.
	kit.box(Vector3(6.5, y + 0.55, -7.8), Vector3(1.2, 1.1, 0.8), kit.mat(Color(0.8, 0.78, 0.72), "metal"), true)
	kit.box(Vector3(8.2, y + 0.65, -8.0), Vector3(0.4, 1.3, 0.4), kit.mat(Color(0.85, 0.85, 0.85)))
	kit.box(Vector3(8.2, y + 1.45, -8.0), Vector3(0.3, 0.4, 0.3), kit.mat(Color(0.5, 0.7, 0.9), "", 0.1))
	for index: int in range(5):
		kit.box(Vector3(-6.0 + index * 0.7, y + 0.7, -14.5), Vector3(0.6, 1.4, 0.7), kit.mat(Color(0.45, 0.47, 0.44), "metal"), true)
	Rooms.desk(kit, Vector3(11.5, y, 0.0))
	kit.box(Vector3(13.5, y + 0.55, 3.0), Vector3(1.0, 1.1, 1.0), kit.mat(Color(0.22, 0.24, 0.22), "metal", 0.4), true)
	for z: float in [-8.0, 0.0, 8.0]:
		for x: float in [-6.0, 0.0, 6.0]:
			kit.box(Vector3(x, OFFICE_TOP - 0.33, z), Vector3(1.2, 0.04, 0.6), kit.glow(Color(0.92, 0.96, 1.0), 1.0))


## Office dressing (docs/INTERIOR_PROPS.md): binders, phones, in/out trays, keyboards, mugs and 1999
## calendars on every desk; a fax on the filing wall; papers on the conference table. Collision-free,
## merged, hidden in potato mode.
static func _office_props(kit: BuildingKit) -> void:
	kit.begin_props()
	var y: float = FLOORS[1]
	var desks: Array[Vector3] = []
	for row: int in range(2):
		for index: int in range(3):
			desks.append(Vector3(-3.0 + index * 4.0 + 0.2, y, -1.5 + row * 5.5 + 1.1))
	desks.append(Vector3(11.5, y, 0.0))
	var binder_colors: Array[Color] = [Color(0.12, 0.2, 0.45), Color(0.1, 0.1, 0.1), Color(0.55, 0.1, 0.1), Color(0.85, 0.85, 0.8), Color(0.2, 0.4, 0.25)]
	var beige: Material = kit.mat(Color(0.78, 0.75, 0.66), "", 0.7)
	var dark: Material = kit.mat(Color(0.12, 0.12, 0.13), "", 0.6)
	var paper: Material = kit.mat(Color(0.95, 0.95, 0.92), "", 0.9)
	var mug: Material = kit.mat(Color(0.9, 0.9, 0.86), "", 0.5)
	for n: int in range(desks.size()):
		var at: Vector3 = desks[n]
		var top: float = at.y + 0.95
		for b: int in range(4 + n % 3):
			kit.prop(Vector3(at.x - 0.9 + b * 0.07, top + 0.15, at.z - 0.3), Vector3(0.06, 0.3, 0.26), kit.mat(binder_colors[(b + n) % binder_colors.size()], "", 0.7))
		kit.prop(Vector3(at.x - 0.15, top + 0.04, at.z - 0.2), Vector3(0.2, 0.07, 0.22), beige)
		kit.prop(Vector3(at.x - 0.15, top + 0.09, at.z - 0.22), Vector3(0.2, 0.04, 0.06), dark)
		for t: int in range(2):
			kit.prop(Vector3(at.x - 0.55, top + 0.03 + t * 0.08, at.z + 0.1), Vector3(0.3, 0.02, 0.24), dark)
			kit.prop(Vector3(at.x - 0.55, top + 0.05 + t * 0.08, at.z + 0.1), Vector3(0.22, 0.02 + t * 0.02, 0.28), paper)
		kit.prop(Vector3(at.x + 0.45, top + 0.015, at.z + 0.25), Vector3(0.44, 0.03, 0.16), beige)
		kit.prop(Vector3(at.x + 0.85, top + 0.05, at.z + 0.2), Vector3(0.08, 0.1, 0.08), mug if n % 2 == 0 else kit.mat(Color(0.2, 0.3, 0.55), "", 0.5))
		# A 1999 wall calendar on the cubicle partition behind the desk (manager: on the window mullion side).
		if n < 6:
			kit.prop(Vector3(at.x - 0.3, y + 1.25, at.z - 1.05), Vector3(0.32, 0.44, 0.01), paper)
			kit.prop(Vector3(at.x - 0.3, y + 1.38, at.z - 1.045), Vector3(0.3, 0.16, 0.01), kit.mat([Color(0.3, 0.5, 0.7), Color(0.7, 0.4, 0.2), Color(0.3, 0.55, 0.3)][n % 3], "", 0.8))
	kit.sign_label("DEC  1999", Vector3(-3.1, y + 1.2, -1.435), 7, Color(0.15, 0.15, 0.18))
	# Fax on the filing wall, papers and mugs on the conference table.
	kit.prop(Vector3(-5.3, y + 1.49, -14.5), Vector3(0.42, 0.18, 0.36), beige)
	kit.prop(Vector3(-5.3, y + 1.6, -14.62), Vector3(0.3, 0.06, 0.1), paper)
	kit.prop(Vector3(-3.9, y + 1.45, -14.5), Vector3(0.3, 0.1, 0.35), dark)
	for dx: float in [-1.4, 0.0, 1.4]:
		for dz: float in [-0.6, 0.6]:
			kit.prop(Vector3(-11.5 + dx, y + 0.8, 11.0 + dz), Vector3(0.22, 0.01, 0.3), paper, 0.1 * dx)
			kit.prop(Vector3(-11.3 + dx, y + 0.84, 11.0 + dz * 0.6), Vector3(0.08, 0.1, 0.08), mug)
	kit.prop(Vector3(-11.5, y + 0.83, 11.0), Vector3(0.24, 0.07, 0.24), kit.mat(Color(0.15, 0.15, 0.16), "", 0.5))
	kit.end_props()
