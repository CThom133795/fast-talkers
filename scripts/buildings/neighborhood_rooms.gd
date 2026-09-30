extends RefCounted
## Small reusable room/prop examples built on BuildingKit. No parallel scene framework.
## Local +Z faces the street. Keep a 3 m central aisle and a second exit for each building.
const Kit = preload("res://scripts/buildings/building_kit.gd")
const CREAM: Color = Color(0.86, 0.8, 0.67)
const WOOD: Color = Color(0.42, 0.26, 0.16)
const RED: Color = Color(0.56, 0.15, 0.12)
const STEEL: Color = Color(0.15, 0.16, 0.17)

## `east_openings`: extra BuildingKit.opening()s in the +X side wall (e.g. a drive-through window).
static func shell(kit: Kit, title: String, half: Vector2, color: Color, east_openings: Array = []) -> void:
	var wall: Material = kit.mat(color, "stucco")
	kit.footprint(Rect2(-half, half * 2.0))
	kit.floor_slab(Rect2(-half, half * 2.0), 0.12, kit.mat(CREAM, "tiles"))
	kit.floor_slab(Rect2(-half, half * 2.0), 4.45, kit.mat(STEEL, "roof"))
	kit.wall(Vector2(-half.x, half.y), Vector2(half.x, half.y), 4.2, wall, [
		Kit.opening(half.x, 2.4), Kit.opening(half.x - 6, 5, 0.85, 2.9, "window"), Kit.opening(half.x + 6, 5, 0.85, 2.9, "window")])
	kit.wall(Vector2(-half.x, -half.y), Vector2(half.x, -half.y), 4.2, wall, [Kit.opening(half.x, 2.2)])
	kit.wall(Vector2(-half.x, -half.y), Vector2(-half.x, half.y), 4.2, wall)
	kit.wall(Vector2(half.x, -half.y), Vector2(half.x, half.y), 4.2, wall, east_openings)
	kit.add_door(Vector3(0, 0.12, half.y), 2.4, 2.6, Vector3.BACK, title + " entrance")
	kit.add_door(Vector3(0, 0.12, -half.y), 2.2, 2.6, Vector3.FORWARD, title + " service exit")
	kit.box(Vector3(0, 3.52, half.y + 0.23), Vector3(half.x * 1.7, 0.95, 0.22), kit.mat(RED))
	kit.sign_label(title, Vector3(0, 3.52, half.y + 0.37), 44, CREAM)
	kit.world._landmark(title, Vector3(0, 0, half.y + 4))
	kit.node.set_meta("walk_in", true)
	kit.node.set_meta("interior_half", half)

static func booth(kit: Kit, at: Vector3) -> void:
	var red: Material = kit.mat(RED)
	var wood: Material = kit.mat(WOOD, "planks")
	for side: float in [-1.0, 1.0]:
		kit.box(at + Vector3(0, 0.49, side * 1.4), Vector3(3.1, 0.75, 0.75), red, true)
		kit.box(at + Vector3(0, 1.17, side * 1.75), Vector3(3.1, 0.9, 0.15), red, true)
	kit.box(at + Vector3(0, 0.98, 0), Vector3(2.7, 0.14, 1.3), wood, true)
	kit.box(at + Vector3(0, 0.52, 0), Vector3(0.25, 0.9, 0.25), kit.mat(STEEL), true)
	kit.box(at + Vector3(0.65, 1.15, 0.2), Vector3(0.24, 0.2, 0.2), kit.mat(CREAM))

static func desk(kit: Kit, at: Vector3) -> void:
	kit.box(at + Vector3(0, 0.88, 0), Vector3(2.0, 0.14, 0.85), kit.mat(WOOD, "planks"), true)
	for x: float in [-0.75, 0.75]:
		kit.box(at + Vector3(x, 0.45, 0), Vector3(0.14, 0.8, 0.65), kit.mat(STEEL), true)
	kit.box(at + Vector3(0.45, 1.17, -0.1), Vector3(0.56, 0.44, 0.38), kit.mat(CREAM))
	kit.box(at + Vector3(0.45, 1.17, 0.1), Vector3(0.42, 0.3, 0.035), kit.mat(STEEL))
	kit.box(at + Vector3(-0.4, 0.47, 1.0), Vector3(0.65, 0.7, 0.65), kit.mat(RED), true)

static func room_finish(kit: Kit, half: Vector2) -> void:
	# Interior linings use layer 2, so the room lamp warms the room rather than the street.
	var lining: Material = kit.mat(CREAM, "stucco")
	# Sits just above the 0.16 m block plinth; at 0.137 it was buried and the street paving showed indoors.
	kit.box(Vector3(0, 0.17, 0), Vector3(half.x * 2 - 0.35, 0.02, half.y * 2 - 0.35), kit.mat(CREAM, "tiles"))
	kit.box(Vector3(0, 4.14, 0), Vector3(half.x * 2 - 0.3, 0.02, half.y * 2 - 0.3), lining)
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(side * (half.x - 0.16), 2.1, 0), Vector3(0.02, 4.15, half.y * 2 - 0.3), lining)
		# Rear exit stays open; no inner panel across its doorway.
		kit.box(Vector3(side * (half.x + 1.2) * 0.5, 2.1, -half.y + 0.16), Vector3(half.x - 1.2, 4.15, 0.02), lining)
	for z: float in [-4.0, 5.0]:
		kit.box(Vector3(0, 4.06, z), Vector3(3.4, 0.06, 0.5), kit.glow(Color(1, 0.86, 0.65), 1.1))

static func diner(world: Node3D, plot: Dictionary) -> void:
	var kit: Kit = Kit.new(world, "Burger", plot)
	# Drive-through window in the kitchen's east wall (glass; the service sill is in burger.gd).
	shell(kit, "BIG BOY BURGERS", Vector2(12, 10), CREAM, [Kit.opening(2.0, 1.6, 1.05, 2.1, "window")])
	kit.begin_interior()
	room_finish(kit, Vector2(12, 10))
	for x: float in [-7.0, 7.0]:
		for z: float in [0.0, 5.0]:
			booth(kit, Vector3(x, 0.12, z))
	# Counter/service hatch leaves the central aisle open to the rear door.
	kit.box(Vector3(-6, 0.72, -4.3), Vector3(7.0, 1.2, 1.0), kit.mat(RED), true)
	kit.box(Vector3(-6, 1.38, -4.3), Vector3(7.2, 0.12, 1.15), kit.mat(CREAM), true)
	kit.box(Vector3(-4.8, 1.68, -4.3), Vector3(0.6, 0.5, 0.45), kit.mat(STEEL))
	kit.wall(Vector2(-11.7, -6), Vector2(11.7, -6), 4.08, kit.mat(CREAM), [Kit.opening(11.7, 3.0), Kit.opening(5.7, 5.0, 1.4, 2.6, "gap")], 0.12)
	for x: float in [-7.5, 7.5]:
		kit.box(Vector3(x, 0.65, -8.5), Vector3(5.4, 1.0, 1.6), kit.mat(STEEL), true)
		kit.box(Vector3(x, 1.21, -8.5), Vector3(5.6, 0.12, 1.7), kit.mat(CREAM), true)
		for dx: float in [-1.3, 0.0, 1.3]:
			kit.box(Vector3(x + dx, 1.3, -8.5), Vector3(0.85, 0.07, 0.85), kit.mat(STEEL))
	kit.box(Vector3(9.9, 2, -4.3), Vector3(2.4, 3.5, 1.0), kit.mat(CREAM), true)
	kit.sign_label("ORDER HERE", Vector3(-6, 2.2, -5.82), 28, RED)
	kit.interior_light(Vector3(0, 3.6, 0), Color(1, 0.86, 0.65), 2.1, 18)
	kit.end_interior()
	kit.finish()

static func motel(world: Node3D, plot: Dictionary) -> void:
	var kit: Kit = Kit.new(world, "Motel", plot)
	shell(kit, "SEA BREEZE MOTEL", Vector2(14, 11), Color(0.75, 0.8, 0.73))
	kit.begin_interior()
	room_finish(kit, Vector2(14, 11))
	# Starter lobby and two rooms. Upper walkway/pool remain for the planned M2 expansion.
	kit.wall(Vector2(-13.7, 0), Vector2(13.7, 0), 4.08, kit.mat(CREAM), [Kit.opening(13.7, 3.0)], 0.12)
	for side: float in [-1.0, 1.0]:
		var x: float = side * 2.0
		kit.wall(Vector2(x, -10.7), Vector2(x, 0), 4.08, kit.mat(CREAM), [Kit.opening(7.2, 1.9)], 0.12)
		kit.add_door(Vector3(x, 0.12, -3.5), 1.9, 2.6, Vector3(-side, 0, 0), "Sea Breeze room " + ("101" if side < 0 else "102"))
		kit.box(Vector3(side * 8.0, 0.4, -6.3), Vector3(3.0, 0.55, 4.0), kit.mat(WOOD), true)
		kit.box(Vector3(side * 8.0, 0.78, -6.3), Vector3(3.0, 0.22, 4.0), kit.mat(Color(0.25, 0.42, 0.48)), true)
		kit.box(Vector3(side * 8.0, 0.99, -7.7), Vector3(2.5, 0.22, 0.8), kit.mat(CREAM))
		kit.box(Vector3(side * 8.0, 1.12, -8.5), Vector3(3.2, 1.8, 0.2), kit.mat(WOOD), true)
		desk(kit, Vector3(side * 9.5, 0.12, -1.5))
	kit.box(Vector3(-7, 0.78, 4.3), Vector3(7, 1.3, 1.1), kit.mat(WOOD, "planks"), true)
	kit.box(Vector3(-7, 1.5, 4.3), Vector3(7.2, 0.12, 1.2), kit.mat(CREAM), true)
	kit.box(Vector3(-7, 2.15, 0.2), Vector3(5.8, 1.3, 0.12), kit.mat(WOOD))
	for i: int in range(8):
		kit.box(Vector3(-9.5 + i * 0.7, 2.15, 0.28), Vector3(0.16, 0.32, 0.04), kit.mat(CREAM))
	booth(kit, Vector3(8, 0.12, 5))
	kit.box(Vector3(11.5, 1.2, 1.6), Vector3(1.2, 2.1, 0.9), kit.mat(Color(0.22, 0.42, 0.5)), true)
	kit.sign_label("ICE", Vector3(11.5, 1.7, 2.1), 28, CREAM)
	kit.interior_light(Vector3(0, 3.5, 3), Color(1, 0.86, 0.65), 2, 21)
	kit.end_interior()
	kit.finish()
