extends RefCounted
## SEA BREEZE MOTEL. Ground floor (neighborhood_rooms.gd): reception, rooms 101/102, ice machine,
## front and rear exits. This builder adds the upper storey: four furnished rooms 201-204 opening
## onto a railed roof walkway, reached by two independent exterior stairs (east and west), a
## vending machine and ice chest on the walkway, a pole sign with a VACANCY board, and window AC
## units. The drained pool still has no room on this plot (see CLAUDE_HANDOFF.md).

const Kit = preload("res://scripts/buildings/building_kit.gd")
const Rooms = preload("res://scripts/buildings/neighborhood_rooms.gd")

const HALF: Vector2 = Vector2(14, 11)   # the ground-floor shell (neighborhood_rooms.motel)
const DECK_Y: float = 4.45               # top of the ground-floor roof slab
const ROOM_H: float = 3.0
const ROOMS_FRONT: float = -1.0          # z of the upper rooms' front wall
const STAIR_X: float = 15.0
const LANDING_Z: Vector2 = Vector2(3.6, 5.6)
## Walk routes for tests/building_landmarks.gd (y values are only hints; the test finds the floor).
const EAST_ROUTE: Array[Vector3] = [Vector3(15.0, 0.16, 14.6), Vector3(15.0, 0.16, 13.2), Vector3(15.0, 4.45, 5.6),
	Vector3(15.0, 4.45, 4.6), Vector3(12.5, 4.45, 4.6), Vector3(3.5, 4.45, 1.0), Vector3(3.5, 4.45, -0.3), Vector3(3.5, 4.45, -3.0)]
const WEST_ROUTE: Array[Vector3] = [Vector3(-15.0, 0.16, 14.6), Vector3(-15.0, 0.16, 13.2), Vector3(-15.0, 4.45, 5.6),
	Vector3(-15.0, 4.45, 4.6), Vector3(-12.5, 4.45, 4.6), Vector3(-10.5, 4.45, 1.0), Vector3(-10.5, 4.45, -0.3), Vector3(-10.5, 4.45, -3.0)]


static func build(world: Node3D, plot: Dictionary) -> void:
	Rooms.motel(world, plot)
	var kit: Kit = Kit.new(world, "MotelUpper", plot)
	var stucco: Material = kit.mat(Color(0.75, 0.8, 0.73), "stucco")
	var trim: Material = kit.mat(Color(0.2, 0.45, 0.5))
	var roof: Material = kit.mat(Rooms.STEEL, "roof")
	var carpet: Material = kit.mat(Color(0.3, 0.36, 0.42), "tatami", 0.95)
	# Upper rooms: back wall on the building's back edge, front wall with a door and window per room.
	var top: float = DECK_Y + ROOM_H
	kit.floor_slab(Rect2(-HALF.x, -HALF.y, HALF.x * 2, HALF.y + ROOMS_FRONT), top + 0.3, roof)
	kit.wall(Vector2(-HALF.x, -HALF.y), Vector2(HALF.x, -HALF.y), ROOM_H, stucco, [], DECK_Y)
	kit.wall(Vector2(-HALF.x, -HALF.y), Vector2(-HALF.x, ROOMS_FRONT), ROOM_H, stucco, [], DECK_Y)
	kit.wall(Vector2(HALF.x, -HALF.y), Vector2(HALF.x, ROOMS_FRONT), ROOM_H, stucco, [], DECK_Y)
	var openings: Array = []
	for index: int in range(4):
		var cx: float = -10.5 + index * 7.0
		openings.append(Kit.opening(cx + HALF.x, 1.0, 0.0, 2.3))
		openings.append(Kit.opening(cx + HALF.x - 2.0, 1.8, 0.9, 2.1, "window"))
	kit.wall(Vector2(-HALF.x, ROOMS_FRONT), Vector2(HALF.x, ROOMS_FRONT), ROOM_H, stucco, openings, DECK_Y)
	for x: float in [-7.0, 0.0, 7.0]:
		kit.wall(Vector2(x, -HALF.y + 0.15), Vector2(x, ROOMS_FRONT - 0.15), ROOM_H, stucco, [], DECK_Y, 0.2)
	kit.box(Vector3(0, top + 0.45, ROOMS_FRONT + 0.2), Vector3(HALF.x * 2 + 0.3, 0.3, 0.5), trim)
	for index: int in range(4):
		var cx: float = -10.5 + index * 7.0
		kit.add_door(Vector3(cx, DECK_Y, ROOMS_FRONT), 1.0, 2.3, Vector3.BACK, "Sea Breeze room %d" % (201 + index), "door", kit.mat(Color(0.2, 0.42, 0.48), "planks", 0.6))
		kit.box(Vector3(cx + 0.9, DECK_Y + 2.45, ROOMS_FRONT + 0.17), Vector3(0.36, 0.2, 0.02), kit.mat(Color(0.8, 0.66, 0.3), "metal", 0.3))
		kit.sign_label(str(201 + index), Vector3(cx + 0.9, DECK_Y + 2.45, ROOMS_FRONT + 0.19), 16, Color(0.1, 0.1, 0.1))
		# Through-wall AC unit under each window: the most motel thing there is.
		kit.box(Vector3(cx - 2.0, DECK_Y + 0.55, ROOMS_FRONT + 0.3), Vector3(1.0, 0.45, 0.35), kit.mat(Color(0.78, 0.76, 0.7), "metal", 0.6))
	# Walkway: railing round the open roof, gaps where each stair lands, the landings themselves.
	kit.railing(Vector3(-HALF.x + 0.15, DECK_Y, HALF.y - 0.15), Vector3(HALF.x - 0.15, DECK_Y, HALF.y - 0.15))
	for side: float in [-1.0, 1.0]:
		var x: float = side * (HALF.x - 0.15)
		kit.railing(Vector3(x, DECK_Y, ROOMS_FRONT), Vector3(x, DECK_Y, LANDING_Z.x))
		kit.railing(Vector3(x, DECK_Y, LANDING_Z.y), Vector3(x, DECK_Y, HALF.y - 0.15))
		_stair(kit, side, roof)
	# Walkway furniture: vending machine and ice chest by the east stair, two folding chairs.
	kit.box(Vector3(12.8, DECK_Y + 0.95, ROOMS_FRONT + 0.6), Vector3(1.0, 1.9, 0.8), kit.mat(Color(0.65, 0.12, 0.1), "metal", 0.5), true)
	kit.box(Vector3(12.8, DECK_Y + 1.25, ROOMS_FRONT + 1.02), Vector3(0.8, 1.1, 0.03), kit.glow(Color(1.0, 0.9, 0.8), 0.8))
	kit.box(Vector3(-12.9, DECK_Y + 0.45, ROOMS_FRONT + 0.6), Vector3(0.9, 0.9, 0.7), kit.mat(Color(0.85, 0.85, 0.82), "metal", 0.4), true)
	kit.sign_label("ICE", Vector3(-12.9, DECK_Y + 0.6, ROOMS_FRONT + 0.96), 20, Color(0.2, 0.4, 0.7))
	for x: float in [-4.0, 8.0]:
		kit.box(Vector3(x, DECK_Y + 0.45, 2.0), Vector3(0.55, 0.06, 0.55), kit.mat(Color(0.9, 0.9, 0.86)))
		kit.box(Vector3(x, DECK_Y + 0.75, 1.75), Vector3(0.55, 0.6, 0.05), kit.mat(Color(0.9, 0.9, 0.86)))
		for leg: Vector2 in [Vector2(-0.24, -0.22), Vector2(0.24, -0.22), Vector2(-0.24, 0.22), Vector2(0.24, 0.22)]:
			kit.box(Vector3(x + leg.x, DECK_Y + 0.21, 2.0 + leg.y), Vector3(0.03, 0.42, 0.03), kit.mat(Color(0.6, 0.62, 0.64), "metal", 0.4))
	_pole_sign(kit)
	kit.begin_interior()
	for index: int in range(4):
		_room(kit, -10.5 + index * 7.0, carpet, index)
	kit.interior_light(Vector3(0, DECK_Y + 2.6, -6.0), Color(1.0, 0.86, 0.62), 2.0, 16.0)
	kit.end_interior()
	kit.node.set_meta("routes", {"east_stair": EAST_ROUTE, "west_stair": WEST_ROUTE})
	kit.node.set_meta("upper_rooms", 4)
	kit.finish()


## A straight exterior stair in the side margin, rising toward the back, with a top landing.
static func _stair(kit: Kit, side: float, material: Material) -> void:
	var at: Vector3 = kit.to_world(Vector3(side * STAIR_X, 0, 13.0))
	var ground: float = kit.world.surface_height(Vector2(at.x, at.z))
	var flight: Dictionary = kit.stairs_straight(Vector3(side * STAIR_X, ground, 13.0), Vector3.FORWARD, DECK_Y - ground, 1.4, kit.mat(Color(0.3, 0.32, 0.34), "metal", 0.6))
	var landing_start: float = (flight["top"] as Vector3).z
	kit.box(Vector3(side * STAIR_X, DECK_Y - 0.15, (landing_start + LANDING_Z.x) * 0.5), Vector3(1.6, 0.3, landing_start - LANDING_Z.x), material, true)
	kit.box(Vector3(side * (STAIR_X + 0.6), DECK_Y * 0.5, LANDING_Z.x + 0.2), Vector3(0.2, DECK_Y - 0.3, 0.2), material, true)
	kit.railing(Vector3(side * (STAIR_X + 0.75), DECK_Y, LANDING_Z.x), Vector3(side * (STAIR_X + 0.75), DECK_Y, landing_start), false)
	kit.railing(Vector3(side * (STAIR_X - 0.75), DECK_Y, LANDING_Z.x), Vector3(side * (STAIR_X + 0.75), DECK_Y, LANDING_Z.x), false)


static func _pole_sign(kit: Kit) -> void:
	# Beside the west front window, clear of the west stair's foot.
	var at: Vector3 = kit.to_world(Vector3(-9.6, 0, HALF.y + 2.4))
	var base: Vector3 = Vector3(-9.6, kit.world.surface_height(Vector2(at.x, at.z)), HALF.y + 2.4)
	kit.box(base + Vector3(0, 3.5, 0), Vector3(0.3, 7.0, 0.3), kit.mat(Rooms.STEEL, "metal", 0.5), true)
	kit.box(base + Vector3(0, 7.9, 0), Vector3(3.6, 1.8, 0.4), kit.mat(Color(0.2, 0.45, 0.5)))
	kit.neon_sign("SEA BREEZE", base + Vector3(0, 8.1, 0.22), 0.0, Color(0.55, 0.95, 1.0), 48)
	kit.box(base + Vector3(0, 6.5, 0), Vector3(2.8, 0.7, 0.3), kit.mat(Color(0.1, 0.1, 0.1)))
	kit.neon_sign("VACANCY", base + Vector3(0, 6.5, 0.17), 0.0, Color(1.0, 0.25, 0.2), 36)
	kit.sign_label("COLOR TV  -  AIR COND  -  WEEKLY RATES", base + Vector3(0, 5.8, 0.17), 14, Color(0.9, 0.9, 0.85))


## One upper room: carpet, double bed with headboard, nightstand and lamp, dresser with a CRT TV,
## luggage rack, a bathroom box in the back corner (partition with a doorway, toilet, basin).
static func _room(kit: Kit, cx: float, carpet: Material, index: int) -> void:
	var y: float = DECK_Y
	var wood: Material = kit.mat(Rooms.WOOD, "planks")
	var spreads: Array[Color] = [Color(0.25, 0.42, 0.48), Color(0.5, 0.3, 0.25), Color(0.35, 0.4, 0.3), Color(0.45, 0.38, 0.5)]
	kit.box(Vector3(cx, y + 0.012, (ROOMS_FRONT - HALF.y) * 0.5), Vector3(6.6, 0.02, HALF.y + ROOMS_FRONT - 0.3), carpet)
	kit.box(Vector3(cx - 1.5, y + 0.3, -6.4), Vector3(2.0, 0.5, 2.6), wood, true)
	kit.box(Vector3(cx - 1.5, y + 0.62, -6.4), Vector3(2.0, 0.16, 2.6), kit.mat(spreads[index]), true)
	kit.box(Vector3(cx - 1.5, y + 0.76, -7.4), Vector3(1.6, 0.14, 0.45), kit.mat(Rooms.CREAM))
	kit.box(Vector3(cx - 1.5, y + 1.0, -7.85), Vector3(2.2, 1.2, 0.12), wood, true)
	kit.box(Vector3(cx - 3.0, y + 0.3, -7.3), Vector3(0.5, 0.6, 0.5), wood, true)
	kit.box(Vector3(cx - 3.0, y + 0.8, -7.3), Vector3(0.24, 0.4, 0.24), kit.glow(Color(1.0, 0.85, 0.6), 0.9))
	kit.box(Vector3(cx + 2.7, y + 0.45, -3.2), Vector3(0.6, 0.9, 1.8), wood, true)
	kit.box(Vector3(cx + 2.6, y + 1.15, -3.2), Vector3(0.5, 0.5, 0.55), kit.mat(Color(0.18, 0.18, 0.2)))
	kit.box(Vector3(cx + 2.34, y + 1.15, -3.2), Vector3(0.02, 0.36, 0.44), kit.glow(Color(0.35, 0.45, 0.6), 0.5))
	kit.box(Vector3(cx - 2.8, y + 0.25, -2.2), Vector3(0.9, 0.5, 0.5), kit.mat(Color(0.55, 0.5, 0.42), "metal"))
	kit.wall(Vector2(cx + 0.6, -7.2), Vector2(cx + 3.35, -7.2), 2.4, kit.mat(Rooms.CREAM, "tiles"), [Kit.opening(0.7, 0.8)], y, 0.12)
	kit.box(Vector3(cx + 2.8, y + 0.22, -10.1), Vector3(0.45, 0.44, 0.6), kit.mat(Color(0.92, 0.92, 0.9)), true)
	kit.box(Vector3(cx + 1.6, y + 0.8, -10.5), Vector3(0.7, 0.12, 0.45), kit.mat(Color(0.92, 0.92, 0.9)), true)
	kit.box(Vector3(cx + 1.6, y + 1.5, -10.8), Vector3(0.6, 0.7, 0.02), kit.mat(Color(0.6, 0.66, 0.7), "", 0.05))
