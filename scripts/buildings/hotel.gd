extends RefCounted
## Plot "hotel": HOTEL MERIDIAN, a tired four-star from the late 80s. This pass builds the walk-in
## ground floor under a sealed tower: glass frontage and canopy, lobby with reception desk, key
## cubbies and a luggage cart, a sunken lounge with columns, a lobby bar with its own side-street
## door, a lift lobby (lift cars are not fitted yet: doors are shut and read as out of service),
## and a back-of-house (housekeeping, linen, luggage cage, manager's office) with a service door.
## Upper guest floors, a working lift and stairwell are the next pass (see CLAUDE_HANDOFF.md).
##
## Local frame (BuildingKit): +Z = out of the front door, +X along the facade. Half size 15 x 14.

const BuildingKit = preload("res://scripts/buildings/building_kit.gd")
const Rooms = preload("res://scripts/buildings/neighborhood_rooms.gd")

const HALF: Vector2 = Vector2(15, 14)
const FLOOR_Y: float = 0.17  # just above the 0.16 m block plinth
const GROUND: float = 4.6
const TOP: float = 25.0
const BACK_Z: float = -6.0
const ROUTE: Array[Vector3] = [Vector3(0, 0.17, 15.6), Vector3(0, 0.17, 12), Vector3(0, 0.17, 8), Vector3(5, 0.17, -3.5),
	Vector3(5, 0.17, -8), Vector3(9, 0.17, -11), Vector3(10, 0.17, -12.8), Vector3(10, 0.17, -15.6)]
const BAR_ROUTE: Array[Vector3] = [Vector3(-16.6, 0.17, 2), Vector3(-12, 0.17, 2), Vector3(-6, 0.17, 4.2), Vector3(-6, 0.17, 8),
	Vector3(-1, 0.17, 9.5), Vector3(0, 0.17, 12), Vector3(0, 0.17, 15.6)]


static func build(world: Node3D, plot: Dictionary) -> void:
	var kit: BuildingKit = BuildingKit.new(world, "Hotel", plot)
	var stucco: Material = kit.mat(Color(0.62, 0.5, 0.4), "stucco")
	var base: Material = kit.mat(Color(0.42, 0.36, 0.32), "brick")
	var marble: Material = kit.mat(Color(0.78, 0.74, 0.66), "tiles", 0.4)
	var roof: Material = kit.mat(Color(0.29, 0.31, 0.3), "roof")
	var rect: Rect2 = Rect2(-HALF, HALF * 2.0)
	kit.footprint(rect)
	kit.floor_slab(rect, FLOOR_Y, marble)
	kit.floor_slab(rect, GROUND, roof)
	# Ground floor shell: glass frontage, service door at the back, bar door on the west side.
	kit.wall(Vector2(-HALF.x, HALF.y), Vector2(HALF.x, HALF.y), GROUND, base, [
		BuildingKit.opening(HALF.x, 2.6), BuildingKit.opening(HALF.x - 6.0, 5.0, 0.6, 3.4, "window"),
		BuildingKit.opening(HALF.x + 6.0, 5.0, 0.6, 3.4, "window"), BuildingKit.opening(HALF.x - 11.5, 3.0, 0.9, 3.2, "window")])
	kit.wall(Vector2(-HALF.x, -HALF.y), Vector2(HALF.x, -HALF.y), GROUND, base, [BuildingKit.opening(HALF.x + 10.0, 1.6)])
	kit.wall(Vector2(-HALF.x, -HALF.y), Vector2(-HALF.x, HALF.y), GROUND, base, [BuildingKit.opening(HALF.y + 2.0, 1.6)])
	kit.wall(Vector2(HALF.x, -HALF.y), Vector2(HALF.x, HALF.y), GROUND, base)
	kit.add_door(Vector3(0, FLOOR_Y, HALF.y), 2.6, 2.6, Vector3.BACK, "Hotel Meridian entrance", "door", kit.glass_material())
	kit.add_door(Vector3(10, FLOOR_Y, -HALF.y), 1.6, 2.6, Vector3.FORWARD, "Hotel Meridian service door", "door", kit.mat(Color(0.4, 0.42, 0.42), "metal", 0.6))
	kit.add_door(Vector3(-HALF.x, FLOOR_Y, 2.0), 1.6, 2.6, Vector3.LEFT, "Hotel Meridian bar entrance", "door", kit.mat(Color(0.3, 0.16, 0.1), "planks", 0.6))
	_tower(kit, stucco, roof)
	_street_front(kit)
	# Back-of-house partition (staff door), the office wall and the lift recess.
	var plaster: Material = kit.mat(Color(0.82, 0.76, 0.64), "stucco")
	kit.wall(Vector2(-HALF.x + 0.15, BACK_Z), Vector2(HALF.x - 0.15, BACK_Z), GROUND - FLOOR_Y - 0.3, plaster, [BuildingKit.opening(HALF.x + 5.0 - 0.15, 1.4)], FLOOR_Y)
	kit.add_door(Vector3(5, FLOOR_Y, BACK_Z), 1.4, 2.6, Vector3.BACK, "Hotel Meridian staff only", "door", kit.mat(Color(0.5, 0.42, 0.3), "planks", 0.6))
	kit.wall(Vector2(0, BACK_Z - 0.15), Vector2(0, -HALF.y + 0.15), GROUND - FLOOR_Y - 0.3, plaster, [BuildingKit.opening(4.0, 1.1)], FLOOR_Y)
	kit.add_door(Vector3(0, FLOOR_Y, -10.15), 1.1, 2.3, Vector3.RIGHT, "Hotel Meridian office")
	for x: float in [-4.0, 4.0]:
		kit.box(Vector3(x, (FLOOR_Y + GROUND) * 0.5, 6.0), Vector3(0.8, GROUND - FLOOR_Y, 0.8), kit.mat(Color(0.7, 0.66, 0.6), "tiles", 0.4), true)
	kit.begin_interior()
	_reception(kit)
	_lounge(kit)
	_bar(kit)
	_lift_lobby(kit)
	_back_of_house(kit)
	_ceiling(kit)
	kit.interior_light(Vector3(0, 3.9, 4.0), Color(1.0, 0.88, 0.66), 2.6, 22.0)
	kit.interior_light(Vector3(0, 3.6, -10.0), Color(0.95, 0.95, 0.9), 1.5, 13.0)
	kit.end_interior()
	kit.world._landmark("HOTEL MERIDIAN", Vector3(0, 0, HALF.y + 5.0))
	kit.node.set_meta("walk_in", true)
	kit.node.set_meta("interior_half", HALF)
	kit.node.set_meta("routes", {"front_to_service": ROUTE, "bar_door_to_front": BAR_ROUTE})
	kit.finish()


## The sealed guest tower above the lobby: solid mass (it is what bullets meet), windows with lit
## rooms picked by a fixed pattern (no RNG, so the rest of the city's seeded generation is unaffected
## by this builder), a cornice and rooftop plant.
static func _tower(kit: BuildingKit, stucco: Material, roof: Material) -> void:
	kit.box(Vector3(0, (GROUND + TOP) * 0.5, 0), Vector3(HALF.x * 2, TOP - GROUND, HALF.y * 2), stucco, true)
	kit.box(Vector3(0, TOP + 0.2, 0), Vector3(HALF.x * 2 + 0.5, 0.4, HALF.y * 2 + 0.5), roof)
	kit.box(Vector3(0, GROUND + 0.2, 0), Vector3(HALF.x * 2 + 0.3, 0.4, HALF.y * 2 + 0.3), kit.mat(Color(0.45, 0.4, 0.36), "stucco"))
	var dark: Material = kit.mat(Color(0.16, 0.24, 0.29), "", 0.3)
	var warm: Material = kit.glow(Color(1.0, 0.78, 0.46), 1.3)
	var curtain: Material = kit.mat(Color(0.55, 0.45, 0.32), "", 0.9)
	var rows: int = int((TOP - GROUND - 1.6) / 3.2)
	for face: int in range(3):
		var normal: Vector3 = [Vector3.BACK, Vector3.LEFT, Vector3.RIGHT][face]
		var along: Vector3 = Vector3.UP.cross(normal) * -1.0
		var length: float = HALF.x * 2 if face == 0 else HALF.y * 2
		var reach: float = HALF.y if face == 0 else HALF.x
		var columns: int = int(length / 3.0)
		var angle: float = atan2(normal.x, normal.z)
		for row: int in range(rows):
			for column: int in range(columns):
				var offset: float = -length * 0.5 + (column + 0.5) * length / columns
				var at: Vector3 = normal * (reach + 0.05) + along * offset + Vector3(0, GROUND + 1.9 + row * 3.2, 0)
				var pattern: int = (row * 7 + column * 3 + face * 5) % 11
				kit.box(at, Vector3(1.5, 1.6, 0.1), warm if pattern < 3 else (curtain if pattern < 6 else dark), false, angle)
	for at: Vector3 in [Vector3(-8, TOP + 1.2, -6), Vector3(-4, TOP + 1.2, -6), Vector3(9, TOP + 2.0, 5)]:
		kit.box(at, Vector3(2.6, 1.6 if at.x < 0 else 3.2, 2.2), kit.mat(Color(0.5, 0.52, 0.52), "metal", 0.6))
	kit.box(Vector3(6, TOP + 3.0, -7), Vector3(3.0, 5.2, 3.0), kit.mat(Color(0.3, 0.3, 0.32), "metal"))


static func _street_front(kit: BuildingKit) -> void:
	var brass: Material = kit.mat(Color(0.74, 0.6, 0.3), "metal", 0.3)
	var maroon: Material = kit.mat(Color(0.4, 0.08, 0.1), "", 0.7)
	kit.box(Vector3(0, 3.5, HALF.y + 2.4), Vector3(6.0, 0.3, 4.8), maroon)
	kit.box(Vector3(0, 3.33, HALF.y + 4.8), Vector3(6.0, 0.06, 0.06), kit.glow(Color(1.0, 0.85, 0.55), 1.6))
	for x: float in [-2.9, 2.9]:
		kit.box(Vector3(x, 1.75, HALF.y + 4.6), Vector3(0.12, 3.5, 0.12), brass, true)
	kit.neon_sign("HOTEL  MERIDIAN", Vector3(0, GROUND + 1.0, HALF.y + 0.3), 0.0, Color(1.0, 0.85, 0.55), 84)
	kit.neon_sign("MERIDIAN", Vector3(HALF.x - 0.8, 12.0, HALF.y + 0.9), 0.0, Color(1.0, 0.85, 0.55), 64, false, true)
	# A red carpet runner, a luggage cart and two planters at the door; ash urn.
	kit.box(Vector3(0, FLOOR_Y + 0.005, HALF.y + 2.4), Vector3(2.4, 0.01, 4.6), kit.mat(Color(0.5, 0.06, 0.08), "", 0.95))
	for x: float in [-4.2, 4.2]:
		kit.box(Vector3(x, FLOOR_Y + 0.35, HALF.y + 1.0), Vector3(1.0, 0.7, 1.0), kit.mat(Color(0.3, 0.28, 0.26), "tiles"), true)
		kit.box(Vector3(x, FLOOR_Y + 1.0, HALF.y + 1.0), Vector3(0.8, 0.7, 0.8), kit.mat(Color(0.2, 0.36, 0.18)))
	kit.box(Vector3(2.0, FLOOR_Y + 0.4, HALF.y + 3.8), Vector3(0.35, 0.8, 0.35), kit.mat(Color(0.2, 0.2, 0.21), "metal"), true)


static func _reception(kit: BuildingKit) -> void:
	var wood: Material = kit.mat(Color(0.36, 0.2, 0.12), "planks")
	var top: Material = kit.mat(Color(0.2, 0.18, 0.17), "", 0.3)
	kit.box(Vector3(9.0, FLOOR_Y + 0.55, 4.0), Vector3(0.8, 1.1, 8.0), wood, true)
	kit.box(Vector3(9.0, FLOOR_Y + 1.13, 4.0), Vector3(1.0, 0.06, 8.2), top, true)
	kit.box(Vector3(9.0, FLOOR_Y + 0.55, 8.4), Vector3(3.0, 1.1, 0.8), wood, true)
	kit.box(Vector3(9.0, FLOOR_Y + 1.13, 8.4), Vector3(3.2, 0.06, 1.0), top, true)
	# Key cubbies with keys on hooks, a bell, a guest ledger, a CRT and card imprinter.
	kit.box(Vector3(14.75, FLOOR_Y + 2.0, 4.0), Vector3(0.2, 1.8, 5.0), wood)
	for row: int in range(4):
		for column: int in range(8):
			var key_at: Vector3 = Vector3(14.62, FLOOR_Y + 1.35 + row * 0.42, 1.95 + column * 0.58)
			kit.box(key_at, Vector3(0.04, 0.36, 0.5), kit.mat(Color(0.18, 0.1, 0.06)))
			if (row * 8 + column) % 3 != 0:
				kit.box(key_at + Vector3(-0.05, -0.08, 0), Vector3(0.03, 0.14, 0.05), kit.mat(Color(0.8, 0.66, 0.3), "metal", 0.3))
	kit.box(Vector3(8.8, FLOOR_Y + 1.2, 2.0), Vector3(0.14, 0.08, 0.14), kit.mat(Color(0.8, 0.66, 0.3), "metal", 0.3))
	kit.box(Vector3(8.9, FLOOR_Y + 1.18, 5.0), Vector3(0.5, 0.04, 0.7), kit.mat(Color(0.2, 0.25, 0.4)))
	kit.box(Vector3(10.0, FLOOR_Y + 1.38, 6.2), Vector3(0.5, 0.45, 0.5), kit.mat(Color(0.8, 0.78, 0.7)))
	kit.box(Vector3(9.74, FLOOR_Y + 1.38, 6.2), Vector3(0.02, 0.32, 0.4), kit.glow(Color(0.45, 0.8, 0.55), 0.6))
	kit.box(Vector3(12.5, FLOOR_Y + 0.45, 4.0), Vector3(0.5, 0.9, 0.5), kit.mat(Color(0.2, 0.2, 0.22), "", 0.6))
	kit.sign_label("RECEPTION", Vector3(9.0, 3.5, 8.9), 30, Color(0.85, 0.72, 0.4))
	# Brass luggage cart by the desk.
	var brass: Material = kit.mat(Color(0.8, 0.66, 0.34), "metal", 0.3)
	kit.box(Vector3(6.2, FLOOR_Y + 0.25, 10.5), Vector3(1.0, 0.08, 1.6), kit.mat(Color(0.45, 0.08, 0.1)))
	for dz: float in [-0.75, 0.75]:
		kit.box(Vector3(6.2, FLOOR_Y + 1.1, 10.5 + dz), Vector3(0.05, 1.7, 0.05), brass)
	kit.box(Vector3(6.2, FLOOR_Y + 1.95, 10.5), Vector3(0.05, 0.05, 1.55), brass)
	kit.box(Vector3(6.2, FLOOR_Y + 0.55, 10.2), Vector3(0.7, 0.5, 0.3), kit.mat(Color(0.28, 0.2, 0.14)))
	kit.box(Vector3(6.2, FLOOR_Y + 0.5, 10.9), Vector3(0.55, 0.4, 0.25), kit.mat(Color(0.14, 0.2, 0.3)))


static func _lounge(kit: BuildingKit) -> void:
	var sofa: Material = kit.mat(Color(0.28, 0.34, 0.26), "", 0.8)
	var rug: Material = kit.mat(Color(0.42, 0.14, 0.12), "tatami", 0.95)
	kit.box(Vector3(-2.5, FLOOR_Y + 0.006, 0.5), Vector3(6.0, 0.012, 4.4), rug)
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(-2.5, FLOOR_Y + 0.22, 0.5 + side * 1.7), Vector3(3.2, 0.44, 0.9), sofa, true)
		kit.box(Vector3(-2.5, FLOOR_Y + 0.7, 0.5 + side * 2.05), Vector3(3.2, 0.6, 0.22), sofa, true)
	kit.box(Vector3(-2.5, FLOOR_Y + 0.2, 0.5), Vector3(1.8, 0.4, 0.9), kit.mat(Color(0.3, 0.18, 0.1), "planks"), true)
	kit.box(Vector3(-2.2, FLOOR_Y + 0.46, 0.4), Vector3(0.5, 0.1, 0.35), kit.mat(Color(0.8, 0.78, 0.7)))
	for at: Vector2 in [Vector2(-6.4, 11.0), Vector2(6.8, -4.6), Vector2(-7.0, -4.6)]:
		kit.box(Vector3(at.x, FLOOR_Y + 0.35, at.y), Vector3(0.8, 0.7, 0.8), kit.mat(Color(0.5, 0.42, 0.34), "tiles"), true)
		kit.box(Vector3(at.x, FLOOR_Y + 1.3, at.y), Vector3(1.0, 1.3, 1.0), kit.mat(Color(0.18, 0.34, 0.16)))
	# A payphone pair and a lobby newspaper rack by the entrance.
	for x: float in [-13.9, -13.0]:
		kit.box(Vector3(x, FLOOR_Y + 1.5, -5.75), Vector3(0.6, 0.8, 0.3), kit.mat(Color(0.3, 0.32, 0.33), "metal"))
	kit.box(Vector3(3.5, FLOOR_Y + 0.55, 12.9), Vector3(1.2, 1.1, 0.5), kit.mat(Color(0.25, 0.2, 0.15), "planks"), true)


static func _bar(kit: BuildingKit) -> void:
	var wood: Material = kit.mat(Color(0.26, 0.14, 0.08), "planks")
	var chrome: Material = kit.mat(Color(0.7, 0.72, 0.74), "metal", 0.25)
	kit.box(Vector3(-11.5, FLOOR_Y + 0.55, 10.2), Vector3(6.0, 1.1, 0.8), wood, true)
	kit.box(Vector3(-11.5, FLOOR_Y + 1.13, 10.2), Vector3(6.2, 0.06, 1.0), kit.mat(Color(0.1, 0.1, 0.1), "", 0.25), true)
	kit.box(Vector3(-8.2, FLOOR_Y + 0.55, 11.8), Vector3(0.8, 1.1, 2.4), wood, true)
	kit.box(Vector3(-14.55, FLOOR_Y + 1.1, 10.2), Vector3(0.5, 2.2, 5.0), wood, true)
	var bottles: Array[Material] = [kit.glow(Color(0.95, 0.6, 0.2), 0.5), kit.glow(Color(0.8, 0.85, 0.9), 0.45), kit.glow(Color(0.3, 0.7, 0.35), 0.5)]
	for shelf: int in range(2):
		for index: int in range(10):
			kit.box(Vector3(-14.25, FLOOR_Y + 2.35 + shelf * 0.45, 8.0 + index * 0.45), Vector3(0.09, 0.3, 0.09), bottles[(index + shelf) % bottles.size()])
	for index: int in range(5):
		var x: float = -13.8 + index * 1.1
		kit.box(Vector3(x, FLOOR_Y + 0.4, 9.2), Vector3(0.06, 0.8, 0.06), chrome)
		kit.box(Vector3(x, FLOOR_Y + 0.82, 9.2), Vector3(0.42, 0.08, 0.42), kit.mat(Color(0.28, 0.34, 0.26), "", 0.8))
	for at: Vector2 in [Vector2(-12.0, 5.5), Vector2(-9.0, -2.0), Vector2(-12.5, -3.0)]:
		kit.box(Vector3(at.x, FLOOR_Y + 0.37, at.y), Vector3(0.1, 0.74, 0.1), chrome)
		kit.box(Vector3(at.x, FLOOR_Y + 0.75, at.y), Vector3(0.8, 0.05, 0.8), kit.mat(Color(0.3, 0.18, 0.1), "planks"))
		for dz: float in [-0.7, 0.7]:
			kit.box(Vector3(at.x, FLOOR_Y + 0.25, at.y + dz), Vector3(0.5, 0.5, 0.5), kit.mat(Color(0.28, 0.34, 0.26), "", 0.8))
	kit.neon_sign("THE COMPASS BAR", Vector3(-11.5, 3.6, 13.6), PI, Color(0.5, 0.85, 1.0), 36)


## Lift lobby: two brass lift doors with shut leaves and a floor indicator, set in the partition.
## The cars are not fitted (upper floors are the next pass); the placard says so.
static func _lift_lobby(kit: BuildingKit) -> void:
	var brass: Material = kit.mat(Color(0.74, 0.6, 0.3), "metal", 0.25)
	for x: float in [-5.0, -1.5]:
		kit.box(Vector3(x, FLOOR_Y + 1.25, BACK_Z + 0.2), Vector3(1.5, 2.5, 0.1), brass)
		kit.box(Vector3(x, FLOOR_Y + 1.25, BACK_Z + 0.26), Vector3(0.02, 2.45, 0.02), kit.mat(Color(0.2, 0.18, 0.12)))
		kit.box(Vector3(x, FLOOR_Y + 2.85, BACK_Z + 0.2), Vector3(0.9, 0.25, 0.08), kit.mat(Color(0.1, 0.1, 0.1)))
		kit.box(Vector3(x, FLOOR_Y + 2.85, BACK_Z + 0.25), Vector3(0.14, 0.14, 0.02), kit.glow(Color(1.0, 0.45, 0.2), 1.0))
	kit.box(Vector3(-3.25, FLOOR_Y + 1.2, BACK_Z + 0.2), Vector3(0.18, 0.35, 0.05), brass)
	kit.box(Vector3(-3.25, FLOOR_Y + 1.7, BACK_Z + 0.2), Vector3(0.9, 0.35, 0.03), kit.mat(Color(0.9, 0.88, 0.8)))
	kit.sign_label("SERVICE SUSPENDED", Vector3(-3.25, FLOOR_Y + 1.7, BACK_Z + 0.23), 10, Color(0.2, 0.15, 0.1))


static func _back_of_house(kit: BuildingKit) -> void:
	var steel: Material = kit.mat(Color(0.55, 0.57, 0.58), "metal", 0.4)
	var linen: Material = kit.mat(Color(0.9, 0.9, 0.86))
	# Housekeeping (east): linen shelves, two carts, luggage cage, time clock.
	kit.box(Vector3(14.5, FLOOR_Y + 1.0, -10.0), Vector3(0.7, 2.0, 5.0), steel, true)
	for y: float in [0.5, 1.1, 1.7]:
		kit.box(Vector3(14.45, FLOOR_Y + y, -10.0), Vector3(0.55, 0.3, 4.6), linen)
	for z: float in [-8.0, -12.6]:
		kit.box(Vector3(12.3, FLOOR_Y + 0.55, z), Vector3(0.8, 1.1, 1.5), kit.mat(Color(0.3, 0.3, 0.34), "metal"), true)
		kit.box(Vector3(12.3, FLOOR_Y + 1.2, z), Vector3(0.7, 0.2, 1.4), linen)
	kit.box(Vector3(2.5, FLOOR_Y + 1.1, -13.2), Vector3(3.0, 2.2, 1.2), kit.mat(Color(0.35, 0.36, 0.37), "metal", 0.5), true)
	for index: int in range(4):
		kit.box(Vector3(1.5 + index * 0.7, FLOOR_Y + 0.35, -13.2), Vector3(0.55, 0.6, 0.8), kit.mat([Color(0.3, 0.2, 0.12), Color(0.12, 0.14, 0.2), Color(0.4, 0.1, 0.1), Color(0.2, 0.2, 0.2)][index]))
	kit.box(Vector3(7.8, FLOOR_Y + 1.5, -6.3), Vector3(0.4, 0.5, 0.2), kit.mat(Color(0.7, 0.68, 0.6), "metal"))
	# Manager's office (west): desk, safe, filing cabinet, room-status board.
	Rooms.desk(kit, Vector3(-7.5, FLOOR_Y, -11.0))
	kit.box(Vector3(-14.1, FLOOR_Y + 0.55, -13.0), Vector3(1.0, 1.1, 1.0), kit.mat(Color(0.22, 0.24, 0.22), "metal", 0.4), true)
	kit.box(Vector3(-13.58, FLOOR_Y + 0.75, -13.0), Vector3(0.04, 0.18, 0.18), kit.mat(Color(0.75, 0.75, 0.7), "metal", 0.3))
	kit.box(Vector3(-14.4, FLOOR_Y + 0.7, -8.0), Vector3(0.7, 1.4, 0.6), kit.mat(Color(0.45, 0.47, 0.44), "metal"), true)
	kit.box(Vector3(-7.5, FLOOR_Y + 2.1, -13.78), Vector3(3.0, 1.2, 0.04), kit.mat(Color(0.85, 0.85, 0.8)))
	for row: int in range(4):
		for column: int in range(10):
			if (row + column * 3) % 4 == 0:
				kit.box(Vector3(-8.85 + column * 0.3, FLOOR_Y + 1.7 + row * 0.25, -13.75), Vector3(0.12, 0.12, 0.02), kit.mat(Color(0.7, 0.15, 0.1)))


## Lobby ceiling: a plaster lining with a coffered border, recessed light panels, a chandelier over
## the lounge and a dark wainscot band on the walls. All visual (above head height), no collision.
static func _ceiling(kit: BuildingKit) -> void:
	var plaster: Material = kit.mat(Color(0.86, 0.8, 0.68), "stucco")
	var trim: Material = kit.mat(Color(0.5, 0.36, 0.22), "planks")
	var lobby_depth: float = HALF.y - BACK_Z - 0.3
	var lobby_center: float = (HALF.y + BACK_Z) * 0.5
	kit.box(Vector3(0, GROUND - 0.32, lobby_center), Vector3(HALF.x * 2 - 0.3, 0.04, lobby_depth), plaster)
	for x: float in [-7.5, 0.0, 7.5]:
		kit.box(Vector3(x, GROUND - 0.5, lobby_center), Vector3(0.3, 0.32, lobby_depth), trim)
	for z: float in [-1.0, 6.5]:
		kit.box(Vector3(0, GROUND - 0.5, z), Vector3(HALF.x * 2 - 0.3, 0.32, 0.3), trim)
	var panel: Material = kit.glow(Color(1.0, 0.92, 0.75), 1.0)
	for x: float in [-11.0, 4.0, 11.0]:
		for z: float in [2.5, 10.0]:
			kit.box(Vector3(x, GROUND - 0.35, z), Vector3(1.6, 0.03, 1.6), panel)
	var brass: Material = kit.mat(Color(0.8, 0.66, 0.34), "metal", 0.3)
	kit.box(Vector3(-2.5, GROUND - 0.9, 0.5), Vector3(0.04, 0.9, 0.04), brass)
	kit.box(Vector3(-2.5, GROUND - 1.4, 0.5), Vector3(1.4, 0.12, 1.4), brass)
	for dx: float in [-0.6, 0.6]:
		for dz: float in [-0.6, 0.6]:
			kit.box(Vector3(-2.5 + dx, GROUND - 1.28, 0.5 + dz), Vector3(0.16, 0.2, 0.16), kit.glow(Color(1.0, 0.85, 0.6), 1.8))
	# Wainscot band on the lobby side walls (a thin skin on the inner face; the wall is the collider).
	# The west run stops either side of the bar's street door.
	kit.box(Vector3(HALF.x - 0.16, FLOOR_Y + 0.5, lobby_center), Vector3(0.02, 1.0, lobby_depth), trim)
	for span: Vector2 in [Vector2(BACK_Z + 0.15, 1.1), Vector2(2.9, HALF.y - 0.15)]:
		kit.box(Vector3(-HALF.x + 0.16, FLOOR_Y + 0.5, (span.x + span.y) * 0.5), Vector3(0.02, 1.0, span.y - span.x), trim)
