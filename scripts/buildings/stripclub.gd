extends RefCounted
## Plot "stripclub": THE VELVET ROOM. Tasteful and non-explicit: no people, no figures, no imagery.
## Windowless neon front with a canopy, cashier vestibule, main room with a raised stage and runway
## (brass poles), stage-side chairs, horseshoe booths, a back bar, and a staff corridor behind the
## stage leading to a dressing room, the back office with its safe, and exits on both side alleys.
##
## Local frame (BuildingKit): +Z = out of the front door, +X along the facade. Half size 15 x 16.

const BuildingKit = preload("res://scripts/buildings/building_kit.gd")
const Rooms = preload("res://scripts/buildings/neighborhood_rooms.gd")

const HALF: Vector2 = Vector2(15, 16)
const HEIGHT: float = 6.0
const FLOOR_Y: float = 0.17  # just above the 0.16 m block plinth, so the floor is not buried
const VESTIBULE_Z: float = 11.0
const STAFF_Z: float = -6.0
const ROOMS_Z: float = -9.2
const STAGE_TOP: float = 0.84
## Walk routes used by tests/building_clubs.gd.
const ROUTE: Array[Vector3] = [Vector3(0, 0.12, 17.5), Vector3(0, 0.12, 13.5), Vector3(0, 0.12, 9.5), Vector3(8.5, 0.12, 5.0),
	Vector3(10, 0.12, -3.5), Vector3(10, 0.12, -7.8), Vector3(13, 0.12, -7.8), Vector3(16.8, 0.12, -7.8)]
const WEST_ROUTE: Array[Vector3] = [Vector3(10, 0.12, -7.8), Vector3(0, 0.12, -7.8), Vector3(-10, 0.12, -7.8), Vector3(-16.8, 0.12, -7.8)]


static func build(world: Node3D, plot: Dictionary) -> void:
	var kit: BuildingKit = BuildingKit.new(world, "Stripclub", plot)
	var outer: Material = kit.mat(Color(0.24, 0.08, 0.11), "stucco")
	var block: Material = kit.mat(Color(0.32, 0.3, 0.3), "brick")
	var carpet: Material = kit.mat(Color(0.2, 0.05, 0.09), "tatami", 0.95)
	var roof: Material = kit.mat(Color(0.22, 0.23, 0.23), "roof")
	var rect: Rect2 = Rect2(-HALF, HALF * 2.0)
	kit.footprint(rect)
	kit.floor_slab(rect, FLOOR_Y, carpet)
	kit.floor_slab(rect, HEIGHT, roof)
	kit.wall(Vector2(-HALF.x, HALF.y), Vector2(HALF.x, HALF.y), HEIGHT, outer, [BuildingKit.opening(HALF.x, 2.2)])
	kit.wall(Vector2(-HALF.x, -HALF.y), Vector2(HALF.x, -HALF.y), HEIGHT, block)
	kit.wall(Vector2(-HALF.x, -HALF.y), Vector2(-HALF.x, HALF.y), HEIGHT, outer, [BuildingKit.opening(HALF.y - 7.6, 1.4)])
	kit.wall(Vector2(HALF.x, -HALF.y), Vector2(HALF.x, HALF.y), HEIGHT, outer, [BuildingKit.opening(HALF.y - 7.6, 1.4)])
	var steel_door: Material = kit.mat(Color(0.3, 0.3, 0.32), "metal", 0.6)
	kit.add_door(Vector3(0, FLOOR_Y, HALF.y), 2.2, 2.6, Vector3.BACK, "Velvet Room entrance", "door", kit.mat(Color(0.12, 0.02, 0.05), "planks", 0.6))
	kit.add_door(Vector3(HALF.x, FLOOR_Y, -7.6), 1.4, 2.6, Vector3.RIGHT, "Velvet Room east alley door", "door", steel_door)
	kit.add_door(Vector3(-HALF.x, FLOOR_Y, -7.6), 1.4, 2.6, Vector3.LEFT, "Velvet Room west alley door", "door", steel_door)
	_street_front(kit)
	var partition: Material = kit.mat(Color(0.3, 0.07, 0.1), "stucco")
	# Vestibule screen with the cashier window, staff wall behind the stage, back rooms.
	kit.wall(Vector2(-HALF.x + 0.15, VESTIBULE_Z), Vector2(HALF.x - 0.15, VESTIBULE_Z), 3.2, partition, [
		BuildingKit.opening(HALF.x - 0.15, 2.4, 0.0, 2.7, "gap"), BuildingKit.opening(HALF.x + 9.0 - 0.15, 1.0)], FLOOR_Y)
	kit.box(Vector3(0, FLOOR_Y + 3.2 + 0.1, VESTIBULE_Z), Vector3(HALF.x * 2 - 0.3, 0.2, 0.3), partition)
	kit.wall(Vector2(3.2, VESTIBULE_Z + 0.15), Vector2(3.2, HALF.y - 0.15), 3.2, partition, [BuildingKit.opening(2.35, 1.6, 1.0, 2.0, "window")], FLOOR_Y)
	kit.box(Vector3(9.1, FLOOR_Y + 3.2 + 0.1, (VESTIBULE_Z + HALF.y) * 0.5), Vector3(11.8, 0.2, HALF.y - VESTIBULE_Z - 0.3), partition, true)
	kit.add_door(Vector3(9.0, FLOOR_Y, VESTIBULE_Z), 1.0, 2.3, Vector3.FORWARD, "Velvet Room cashier booth")
	kit.wall(Vector2(-HALF.x + 0.15, STAFF_Z), Vector2(HALF.x - 0.15, STAFF_Z), HEIGHT - 0.3, block, [
		BuildingKit.opening(HALF.x + 10.0 - 0.15, 1.3)], FLOOR_Y)
	kit.add_door(Vector3(10, FLOOR_Y, STAFF_Z), 1.3, 2.6, Vector3.BACK, "Velvet Room staff only", "door", steel_door)
	kit.wall(Vector2(-HALF.x + 0.15, ROOMS_Z), Vector2(HALF.x - 0.15, ROOMS_Z), 3.2, block, [
		BuildingKit.opening(HALF.x - 8.0 - 0.15, 1.0), BuildingKit.opening(HALF.x + 7.0 - 0.15, 1.0)], FLOOR_Y)
	kit.wall(Vector2(0, ROOMS_Z - 0.15), Vector2(0, -HALF.y + 0.15), 3.2, block, [], FLOOR_Y)
	kit.box(Vector3(0, FLOOR_Y + 3.2 + 0.15, (ROOMS_Z - HALF.y) * 0.5), Vector3(HALF.x * 2 - 0.3, 0.3, HALF.y + ROOMS_Z - 0.3), roof, true)
	kit.add_door(Vector3(-8, FLOOR_Y, ROOMS_Z), 1.0, 2.3, Vector3.BACK, "Velvet Room dressing room")
	kit.add_door(Vector3(7, FLOOR_Y, ROOMS_Z), 1.0, 2.3, Vector3.BACK, "Velvet Room office")
	kit.begin_interior()
	_vestibule(kit)
	_stage(kit)
	_seating(kit)
	_bar(kit)
	_dressing_room(kit)
	_office(kit)
	kit.interior_light(Vector3(0, 4.6, 1.0), Color(1.0, 0.55, 0.65), 3.2, 24.0)
	kit.interior_light(Vector3(0, 2.8, -12.5), Color(1.0, 0.9, 0.75), 1.5, 11.0)
	_club_props(kit)
	kit.end_interior()
	kit.world._landmark("THE VELVET ROOM", Vector3(0, 0, HALF.y + 5.0))
	kit.node.set_meta("walk_in", true)
	kit.node.set_meta("interior_half", HALF)
	kit.node.set_meta("routes", {"front_to_east_alley": ROUTE, "west_alley": WEST_ROUTE})
	kit.finish_props()
	kit.finish()


## Windowless front: neon, a short canopy, brass rope and a painted "OPEN 8PM - 4AM" board.
static func _street_front(kit: BuildingKit) -> void:
	var brass: Material = kit.mat(Color(0.74, 0.6, 0.3), "metal", 0.35)
	kit.box(Vector3(0, 3.1, HALF.y + 1.5), Vector3(4.2, 0.22, 3.0), kit.mat(Color(0.35, 0.05, 0.1), "", 0.7))
	kit.box(Vector3(0, 2.96, HALF.y + 2.95), Vector3(4.2, 0.08, 0.08), kit.glow(Color(1.0, 0.3, 0.5), 2.0))
	for x: float in [-1.95, 1.95]:
		kit.box(Vector3(x, 1.55, HALF.y + 2.85), Vector3(0.08, 3.1, 0.08), brass, true)
	kit.neon_sign("THE  VELVET  ROOM", Vector3(0, 4.6, HALF.y + 0.3), 0.0, Color(1.0, 0.3, 0.5), 76)
	kit.neon_sign("GENTLEMEN'S CLUB", Vector3(0, 3.75, HALF.y + 0.3), 0.0, Color(0.95, 0.8, 0.5), 36)
	kit.box(Vector3(-6.5, 1.9, HALF.y + 0.17), Vector3(2.4, 1.2, 0.03), kit.mat(Color(0.08, 0.06, 0.07)))
	kit.sign_label("OPEN 8PM - 4AM\nNO COVER BEFORE 10", Vector3(-6.5, 1.9, HALF.y + 0.2), 18, Color(0.95, 0.85, 0.7))
	for x: float in [-3.6, 3.6]:
		kit.box(Vector3(x, FLOOR_Y + 0.5, HALF.y + 1.4), Vector3(0.09, 1.0, 0.09), brass, true)
		kit.box(Vector3(x + (0.9 if x < 0.0 else -0.9), FLOOR_Y + 0.86, HALF.y + 1.4), Vector3(1.7, 0.05, 0.05), kit.mat(Color(0.45, 0.05, 0.1)))


static func _vestibule(kit: BuildingKit) -> void:
	var wood: Material = kit.mat(Color(0.28, 0.14, 0.1), "planks")
	# Cashier booth east of the entry (window onto the vestibule), a bench and an ATM on the west side.
	kit.box(Vector3(3.8, FLOOR_Y + 0.5, 13.5), Vector3(0.7, 1.0, 2.6), wood, true)
	kit.box(Vector3(3.8, FLOOR_Y + 1.03, 13.5), Vector3(0.85, 0.06, 2.8), kit.mat(Color(0.08, 0.06, 0.06), "", 0.3), true)
	kit.box(Vector3(4.9, FLOOR_Y + 0.25, 13.5), Vector3(0.5, 0.5, 0.5), kit.mat(Color(0.3, 0.3, 0.32), "metal"))
	Rooms.desk(kit, Vector3(11.5, FLOOR_Y, 14.6))
	kit.sign_label("PAY HERE", Vector3(3.03, 2.35, 13.5), 22, Color(0.95, 0.85, 0.7), PI * -0.5)
	kit.box(Vector3(-13.6, FLOOR_Y + 0.9, VESTIBULE_Z + 1.8), Vector3(0.9, 1.8, 0.7), kit.mat(Color(0.4, 0.42, 0.45), "metal"), true)
	kit.box(Vector3(-13.14, FLOOR_Y + 1.35, VESTIBULE_Z + 1.8), Vector3(0.02, 0.35, 0.45), kit.glow(Color(0.4, 0.8, 0.6), 0.6))
	kit.sign_label("ATM", Vector3(-13.12, FLOOR_Y + 1.7, VESTIBULE_Z + 1.8), 22, Color(0.9, 0.9, 0.9), PI * 0.5)
	kit.box(Vector3(-6.0, FLOOR_Y + 0.25, HALF.y - 0.7), Vector3(3.0, 0.5, 0.8), kit.mat(Color(0.5, 0.08, 0.12), "", 0.5), true)


## Stage: a raised platform against the staff wall with a runway toward the room, two brass poles,
## a mirrored back panel, footlights and a tip rail. Stage steps at stage left.
static func _stage(kit: BuildingKit) -> void:
	var deck: Material = kit.mat(Color(0.1, 0.07, 0.08), "planks", 0.4)
	var brass: Material = kit.mat(Color(0.8, 0.66, 0.34), "metal", 0.25)
	var rail: Material = kit.mat(Color(0.2, 0.05, 0.08), "", 0.5)
	kit.box(Vector3(-2.0, FLOOR_Y + STAGE_TOP * 0.5, STAFF_Z + 2.2), Vector3(9.0, STAGE_TOP, 4.1), deck, true)
	kit.box(Vector3(-2.0, FLOOR_Y + STAGE_TOP * 0.5, STAFF_Z + 6.2), Vector3(2.2, STAGE_TOP, 4.0), deck, true)
	kit.box(Vector3(-2.0, FLOOR_Y + STAGE_TOP * 0.5, STAFF_Z + 8.6), Vector3(3.4, STAGE_TOP, 1.2), deck, true)
	for at: Vector2 in [Vector2(-2.0, STAFF_Z + 2.4), Vector2(-2.0, STAFF_Z + 8.5)]:
		kit.box(Vector3(at.x, FLOOR_Y + STAGE_TOP + (HEIGHT - STAGE_TOP - FLOOR_Y) * 0.5, at.y), Vector3(0.07, HEIGHT - STAGE_TOP - FLOOR_Y, 0.07), brass, true)
	kit.box(Vector3(-2.0, FLOOR_Y + 2.6, STAFF_Z + 0.22), Vector3(8.6, 3.2, 0.04), kit.mat(Color(0.55, 0.52, 0.56), "", 0.05))
	kit.box(Vector3(-2.0, FLOOR_Y + 4.5, STAFF_Z + 0.3), Vector3(9.0, 0.6, 0.12), kit.mat(Color(0.4, 0.04, 0.1), "", 0.8))
	# Footlights along the runway edge (emissive strip, no dynamic light), tip rail at seated height.
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(-2.0 + side * 1.12, FLOOR_Y + STAGE_TOP - 0.05, STAFF_Z + 6.2), Vector3(0.04, 0.05, 4.0), kit.glow(Color(1.0, 0.8, 0.5), 1.6))
		kit.box(Vector3(-2.0 + side * 1.75, FLOOR_Y + STAGE_TOP - 0.05, STAFF_Z + 8.6), Vector3(0.04, 0.05, 1.2), kit.glow(Color(1.0, 0.8, 0.5), 1.6))
	kit.box(Vector3(-2.0, FLOOR_Y + STAGE_TOP + 0.06, STAFF_Z + 4.25), Vector3(9.0, 0.03, 0.04), kit.glow(Color(1.0, 0.8, 0.5), 1.4))
	kit.box(Vector3(-2.0, FLOOR_Y + STAGE_TOP + 0.03, STAFF_Z + 9.35), Vector3(3.6, 0.06, 0.25), rail)
	# Stage steps at stage left.
	kit.stairs_straight(Vector3(4.0, FLOOR_Y, STAFF_Z + 3.1), Vector3.LEFT, STAGE_TOP, 1.2, deck, false)


## Chairs around the runway, horseshoe booths along both walls, cocktail tables.
static func _seating(kit: BuildingKit) -> void:
	var velvet: Material = kit.mat(Color(0.45, 0.04, 0.12), "", 0.5)
	var black: Material = kit.mat(Color(0.06, 0.05, 0.05), "", 0.4)
	for side: float in [-1.0, 1.0]:
		for index: int in range(3):
			var at: Vector3 = Vector3(-2.0 + side * 2.0, FLOOR_Y, STAFF_Z + 5.0 + index * 1.2)
			kit.box(at + Vector3(0, 0.25, 0), Vector3(0.5, 0.5, 0.5), velvet)
			kit.box(at + Vector3(side * 0.22, 0.65, 0), Vector3(0.08, 0.5, 0.5), velvet)
	for x: float in [-11.8, 11.8]:
		for z: float in [-1.0, 5.0]:
			var toward: float = -signf(x)
			kit.box(Vector3(x - toward * 1.2, FLOOR_Y + 0.25, z), Vector3(1.0, 0.5, 3.2), velvet, true)
			kit.box(Vector3(x - toward * 1.65, FLOOR_Y + 0.9, z), Vector3(0.25, 1.1, 3.2), velvet, true)
			for end: float in [-1.0, 1.0]:
				kit.box(Vector3(x - toward * 0.4, FLOOR_Y + 0.25, z + end * 1.35), Vector3(1.0, 0.5, 0.6), velvet, true)
			kit.box(Vector3(x + toward * 0.2, FLOOR_Y + 0.36, z), Vector3(0.8, 0.06, 1.4), black, true)
			kit.box(Vector3(x + toward * 0.2, FLOOR_Y + 0.17, z), Vector3(0.2, 0.34, 0.2), black)
			kit.box(Vector3(x - toward * 1.65, FLOOR_Y + 2.3, z), Vector3(0.05, 0.4, 0.4), kit.glow(Color(1.0, 0.6, 0.45), 0.9))
	for at: Vector2 in [Vector2(5.5, 7.0), Vector2(-7.5, 8.5), Vector2(5.5, 1.5)]:
		kit.box(Vector3(at.x, FLOOR_Y + 0.37, at.y), Vector3(0.08, 0.74, 0.08), black)
		kit.box(Vector3(at.x, FLOOR_Y + 0.75, at.y), Vector3(0.7, 0.04, 0.7), black)
		for dx: float in [-0.6, 0.6]:
			kit.box(Vector3(at.x + dx, FLOOR_Y + 0.23, at.y), Vector3(0.42, 0.46, 0.42), velvet)


## Back bar in the vestibule corner of the main room: counter (waist-high cover), back shelf, stools.
static func _bar(kit: BuildingKit) -> void:
	var wood: Material = kit.mat(Color(0.2, 0.1, 0.08), "planks")
	var chrome: Material = kit.mat(Color(0.7, 0.72, 0.74), "metal", 0.25)
	kit.box(Vector3(-9.0, FLOOR_Y + 0.55, VESTIBULE_Z - 2.4), Vector3(8.0, 1.1, 0.8), wood, true)
	kit.box(Vector3(-9.0, FLOOR_Y + 1.13, VESTIBULE_Z - 2.4), Vector3(8.2, 0.06, 1.0), kit.mat(Color(0.05, 0.05, 0.05), "", 0.25), true)
	kit.box(Vector3(-9.0, FLOOR_Y + 0.5, VESTIBULE_Z - 0.55), Vector3(8.0, 1.0, 0.5), wood, true)
	var bottles: Array[Material] = [kit.glow(Color(0.95, 0.6, 0.2), 0.6), kit.glow(Color(0.8, 0.85, 0.9), 0.5), kit.glow(Color(0.6, 0.15, 0.25), 0.6)]
	for index: int in range(14):
		kit.box(Vector3(-12.3 + index * 0.5, FLOOR_Y + 1.18, VESTIBULE_Z - 0.55), Vector3(0.09, 0.32, 0.09), bottles[index % bottles.size()])
	for index: int in range(6):
		var x: float = -12.0 + index * 1.2
		kit.box(Vector3(x, FLOOR_Y + 0.4, VESTIBULE_Z - 3.35), Vector3(0.06, 0.8, 0.06), chrome)
		kit.box(Vector3(x, FLOOR_Y + 0.82, VESTIBULE_Z - 3.35), Vector3(0.42, 0.08, 0.42), kit.mat(Color(0.45, 0.04, 0.12), "", 0.5))
	kit.neon_sign("COCKTAILS", Vector3(-9.0, 3.0, VESTIBULE_Z - 0.2), PI, Color(0.95, 0.8, 0.5), 40)


## Dressing room: bulb-framed mirrors over a vanity counter, a clothes rail with garment bags,
## lockers and a folding screen. No figures or explicit imagery.
static func _dressing_room(kit: BuildingKit) -> void:
	var counter: Material = kit.mat(Color(0.85, 0.8, 0.72), "", 0.4)
	var bulb: Material = kit.glow(Color(1.0, 0.9, 0.7), 1.8)
	kit.box(Vector3(-7.5, FLOOR_Y + 0.8, -HALF.y + 0.55), Vector3(9.0, 0.08, 0.7), counter, true)
	for index: int in range(3):
		var x: float = -11.0 + index * 3.4
		kit.box(Vector3(x, FLOOR_Y + 1.6, -HALF.y + 0.18), Vector3(1.6, 1.1, 0.03), kit.mat(Color(0.6, 0.65, 0.7), "", 0.05))
		for b: int in range(5):
			kit.box(Vector3(x - 0.8 + b * 0.4, FLOOR_Y + 2.2, -HALF.y + 0.22), Vector3(0.09, 0.09, 0.09), bulb)
		kit.box(Vector3(x, FLOOR_Y + 0.25, -HALF.y + 1.3), Vector3(0.45, 0.5, 0.45), kit.mat(Color(0.3, 0.3, 0.32), "metal"))
	for index: int in range(4):
		kit.box(Vector3(-14.5, FLOOR_Y + 0.95, -14.8 + index * 0.62), Vector3(0.5, 1.9, 0.58), kit.mat(Color(0.3, 0.38, 0.45), "metal"), true)
	var dark: Material = kit.mat(Color(0.15, 0.15, 0.16), "metal", 0.4)
	kit.bar(Vector3(-5.0, FLOOR_Y + 1.8, -10.2), Vector3(-1.0, FLOOR_Y + 1.8, -10.2), 0.04, dark, false)
	var cloth: Array[Color] = [Color(0.7, 0.1, 0.3), Color(0.1, 0.1, 0.12), Color(0.85, 0.75, 0.6), Color(0.3, 0.1, 0.5)]
	for index: int in range(6):
		kit.box(Vector3(-4.7 + index * 0.62, FLOOR_Y + 1.25, -10.2), Vector3(0.45, 1.05, 0.12), kit.mat(cloth[index % cloth.size()]))


## Back office: desk, CRT, floor safe, filing cabinets, CCTV monitor, a sofa.
static func _office(kit: BuildingKit) -> void:
	Rooms.desk(kit, Vector3(7.5, FLOOR_Y, -13.5))
	var green: Material = kit.mat(Color(0.2, 0.23, 0.2), "metal", 0.4)
	kit.box(Vector3(13.8, FLOOR_Y + 0.6, -15.0), Vector3(1.1, 1.2, 1.0), green, true)
	kit.box(Vector3(13.25, FLOOR_Y + 0.8, -15.0), Vector3(0.04, 0.2, 0.2), kit.mat(Color(0.75, 0.75, 0.7), "metal", 0.3))
	kit.box(Vector3(13.22, FLOOR_Y + 0.45, -15.0), Vector3(0.06, 0.06, 0.4), kit.mat(Color(0.75, 0.75, 0.7), "metal", 0.3))
	for x: float in [2.0, 2.7]:
		kit.box(Vector3(x, FLOOR_Y + 0.7, -15.45), Vector3(0.6, 1.4, 0.7), kit.mat(Color(0.45, 0.47, 0.44), "metal"), true)
	kit.box(Vector3(11.0, FLOOR_Y + 2.1, -15.6), Vector3(0.6, 0.45, 0.4), kit.mat(Color(0.2, 0.2, 0.2), "metal"))
	kit.box(Vector3(11.0, FLOOR_Y + 2.1, -15.39), Vector3(0.46, 0.33, 0.02), kit.glow(Color(0.5, 0.75, 0.6), 0.6))
	kit.box(Vector3(13.9, FLOOR_Y + 0.25, -11.2), Vector3(0.9, 0.5, 2.4), kit.mat(Color(0.3, 0.2, 0.14), "", 0.5), true)
	kit.box(Vector3(14.45, FLOOR_Y + 0.8, -11.2), Vector3(0.2, 0.7, 2.4), kit.mat(Color(0.3, 0.2, 0.14), "", 0.5), true)


## Room dressing (docs/INTERIOR_PROPS.md): bills on the tip rail, glasses, bottles, ashtrays and
## drink menus on the tables and the bar. Collision-free, merged, hidden in potato mode.
static func _club_props(kit: BuildingKit) -> void:
	kit.begin_props()
	var glass: Material = kit.mat(Color(0.75, 0.85, 0.9), "", 0.05)
	var ash: Material = kit.mat(Color(0.2, 0.2, 0.22), "", 0.6)
	var cash: Material = kit.mat(Color(0.45, 0.6, 0.4), "", 0.9)
	var card: Material = kit.mat(Color(0.35, 0.05, 0.1), "", 0.7)
	var rail_y: float = FLOOR_Y + STAGE_TOP + 0.065
	for index: int in range(7):
		kit.prop(Vector3(-3.5 + index * 0.5, rail_y, STAFF_Z + 9.35 + (0.05 if index % 2 == 0 else -0.04)), Vector3(0.15, 0.006, 0.07), cash, 0.3 * (index % 3 - 1))
	var bar_top: float = FLOOR_Y + 1.16
	for index: int in range(8):
		var x: float = -12.5 + index * 0.95
		kit.prop(Vector3(x, bar_top + 0.06, VESTIBULE_Z - 2.6), Vector3(0.07, 0.12, 0.07), glass)
		if index % 3 == 0:
			kit.prop(Vector3(x + 0.3, bar_top + 0.02, VESTIBULE_Z - 2.3), Vector3(0.14, 0.04, 0.14), ash)
		if index % 3 == 1:
			kit.prop_bottle(Vector3(x + 0.35, bar_top, VESTIBULE_Z - 2.2), Color(0.35, 0.2, 0.06), 0.3)
	for x: float in [-11.8, 11.8]:
		for z: float in [-1.0, 5.0]:
			var toward: float = -signf(x)
			var t: float = FLOOR_Y + 0.39
			kit.prop(Vector3(x + toward * 0.2, t + 0.06, z - 0.3), Vector3(0.07, 0.12, 0.07), glass)
			kit.prop(Vector3(x + toward * 0.3, t + 0.02, z + 0.3), Vector3(0.14, 0.04, 0.14), ash)
			kit.prop(Vector3(x + toward * 0.05, t + 0.06, z + 0.05), Vector3(0.1, 0.12, 0.02), card)
			kit.prop_bottle(Vector3(x + toward * 0.4, t, z - 0.1), Color(0.1, 0.3, 0.1), 0.3)
	for at: Vector2 in [Vector2(5.5, 7.0), Vector2(-7.5, 8.5), Vector2(5.5, 1.5)]:
		var t2: float = FLOOR_Y + 0.77
		kit.prop(Vector3(at.x - 0.15, t2 + 0.06, at.y), Vector3(0.07, 0.12, 0.07), glass)
		kit.prop(Vector3(at.x + 0.15, t2 + 0.02, at.y + 0.1), Vector3(0.13, 0.04, 0.13), ash)
		kit.prop(Vector3(at.x + 0.1, t2 + 0.004, at.y - 0.2), Vector3(0.15, 0.008, 0.07), cash)
	kit.end_props()
