extends RefCounted
## Plot "nightclub": CLUB VOLTAGE. A late-90s warehouse club on the Nightlife block.
## Street queue rope and canopy, entry lobby with coat check, main room with a lit dance floor
## (emissive panels, no extra dynamic lights), raised DJ booth between speaker stacks, a long bar,
## lounge booths, a VIP mezzanine reached by a railed stair, and a back-of-house with stock room,
## manager's office and two exits (rear alley door, side fire door). Collision is only what you see.
##
## Local frame (BuildingKit): +Z = out of the front door, +X along the facade. Half size 16 x 18.

const BuildingKit = preload("res://scripts/buildings/building_kit.gd")
const Rooms = preload("res://scripts/buildings/neighborhood_rooms.gd")

const HALF: Vector2 = Vector2(16, 18)
const HEIGHT: float = 8.0
const FLOOR_Y: float = 0.17  # just above the 0.16 m block plinth, so the floor is not buried
const MEZZ_Y: float = 3.72
const LOBBY_Z: float = 12.0
const BACK_Z: float = -10.0
## Walk route used by tests/building_clubs.gd: front door -> dance floor edge -> staff door -> alley.
const ROUTE: Array[Vector3] = [Vector3(-4, 0.12, 19.5), Vector3(-4, 0.12, 14), Vector3(-4, 0.12, 9), Vector3(-9, 0.12, -6),
	Vector3(-10, 0.12, -8.5), Vector3(-10, 0.12, -12), Vector3(-10, 0.12, -16.5), Vector3(-10, 0.12, -19.5)]
const FIRE_ROUTE: Array[Vector3] = [Vector3(-9, 0.12, -6), Vector3(-12, 0.12, -8.2), Vector3(-15, 0.12, -8.2), Vector3(-17.8, 0.12, -8.2)]
const MEZZ_ROUTE: Array[Vector3] = [Vector3(14.9, 0.12, 11.2), Vector3(14.9, 3.72, 4.0), Vector3(11.0, 3.72, 0), Vector3(11.0, 3.72, -8.4)]


static func build(world: Node3D, plot: Dictionary) -> void:
	var kit: BuildingKit = BuildingKit.new(world, "Nightclub", plot)
	var outer: Material = kit.mat(Color(0.15, 0.13, 0.19), "panel")
	var block: Material = kit.mat(Color(0.3, 0.29, 0.31), "brick")
	var concrete: Material = kit.mat(Color(0.34, 0.33, 0.32), "tiles", 0.95)
	var roof: Material = kit.mat(Color(0.22, 0.23, 0.23), "roof")
	var rect: Rect2 = Rect2(-HALF, HALF * 2.0)
	kit.footprint(rect)
	kit.floor_slab(rect, FLOOR_Y, concrete)
	kit.floor_slab(rect, HEIGHT, roof)
	# --- Shell: front (entrance + cashier window), back (alley door), sides (fire door on the left).
	kit.wall(Vector2(-HALF.x, HALF.y), Vector2(HALF.x, HALF.y), HEIGHT, outer, [
		BuildingKit.opening(HALF.x - 4.0, 2.4), BuildingKit.opening(HALF.x + 7.0, 1.6, 1.0, 2.0, "window")])
	kit.wall(Vector2(-HALF.x, -HALF.y), Vector2(HALF.x, -HALF.y), HEIGHT, block, [BuildingKit.opening(HALF.x - 10.0, 1.6)])
	kit.wall(Vector2(-HALF.x, -HALF.y), Vector2(-HALF.x, HALF.y), HEIGHT, outer, [BuildingKit.opening(HALF.y - 8.2, 1.4)])
	kit.wall(Vector2(HALF.x, -HALF.y), Vector2(HALF.x, HALF.y), HEIGHT, outer)
	kit.add_door(Vector3(-4, FLOOR_Y, HALF.y), 2.4, 2.6, Vector3.BACK, "Club Voltage entrance", "door", kit.mat(Color(0.08, 0.08, 0.09), "metal", 0.5))
	kit.add_door(Vector3(-10, FLOOR_Y, -HALF.y), 1.6, 2.6, Vector3.FORWARD, "Club Voltage alley door", "door", kit.mat(Color(0.35, 0.37, 0.38), "metal", 0.6))
	kit.add_door(Vector3(-HALF.x, FLOOR_Y, -8.2), 1.4, 2.6, Vector3.LEFT, "Club Voltage fire exit", "door", kit.mat(Color(0.55, 0.12, 0.1), "metal", 0.6))
	_street_front(kit)
	# --- Inner walls: lobby screen, back-of-house, office.
	var partition: Material = kit.mat(Color(0.12, 0.11, 0.14), "panel")
	kit.wall(Vector2(-HALF.x + 0.15, LOBBY_Z), Vector2(HALF.x - 0.15, LOBBY_Z), 3.6, partition, [
		BuildingKit.opening(HALF.x - 4.0 - 0.15, 3.0, 0.0, 2.7, "gap"), BuildingKit.opening(HALF.x + 3.0 - 0.15, 2.0, 0.0, 2.7, "gap")], FLOOR_Y)
	kit.box(Vector3(0, FLOOR_Y + 3.6 + 0.1, LOBBY_Z), Vector3(HALF.x * 2 - 0.3, 0.2, 0.3), partition)
	kit.wall(Vector2(-HALF.x + 0.15, BACK_Z), Vector2(HALF.x - 0.15, BACK_Z), HEIGHT - 0.3, block, [
		BuildingKit.opening(HALF.x - 10.0 - 0.15, 1.4), BuildingKit.opening(HALF.x + 11.5 - 0.15, 1.2)], FLOOR_Y)
	kit.add_door(Vector3(-10, FLOOR_Y, BACK_Z), 1.4, 2.6, Vector3.BACK, "Club Voltage staff door", "door", kit.mat(Color(0.2, 0.2, 0.22), "metal", 0.6))
	kit.wall(Vector2(4, BACK_Z - 0.15), Vector2(4, -HALF.y + 0.15), 3.4, block, [BuildingKit.opening(3.0, 1.1)], FLOOR_Y)
	kit.box(Vector3(10, FLOOR_Y + 3.4 + 0.15, -14), Vector3(12, 0.3, 7.7), roof, true)
	kit.add_door(Vector3(4, FLOOR_Y, BACK_Z - 3.15), 1.1, 2.3, Vector3.LEFT, "Club Voltage office")
	kit.add_door(Vector3(11.5, FLOOR_Y, BACK_Z), 1.2, 2.6, Vector3.BACK, "Club Voltage office (club side)")
	_structure(kit, block)
	# --- VIP mezzanine along the right wall: slab, railing, stair.
	var mezz: Rect2 = Rect2(Vector2(9.0, BACK_Z + 0.15), Vector2(HALF.x - 0.15 - 9.0, 4.5 - BACK_Z - 0.15))
	kit.floor_slab(mezz, MEZZ_Y, concrete)
	kit.railing(Vector3(9.0, MEZZ_Y, BACK_Z + 0.2), Vector3(9.0, MEZZ_Y, 4.5))
	kit.railing(Vector3(9.0, MEZZ_Y, 4.5), Vector3(14.05, MEZZ_Y, 4.5))
	var stair: Dictionary = kit.stairs_straight(Vector3(14.9, FLOOR_Y, 10.5), Vector3.FORWARD, MEZZ_Y - FLOOR_Y, 1.5, kit.mat(Color(0.2, 0.2, 0.22), "metal", 0.6))
	kit.node.set_meta("mezzanine_stair", stair)
	for z: float in [-4.0, 2.0]:
		kit.box(Vector3(9.3, MEZZ_Y * 0.5, z), Vector3(0.35, MEZZ_Y - 0.3, 0.35), kit.mat(Color(0.18, 0.18, 0.2), "metal", 0.5), true)
	kit.begin_interior()
	_lobby(kit)
	_dance_floor(kit)
	_bar(kit)
	_lounge(kit)
	_vip(kit)
	_back_of_house(kit)
	kit.interior_light(Vector3(0, 6.2, 0), Color(0.8, 0.45, 1.0), 2.6, 22.0)
	kit.interior_light(Vector3(-4, 3.0, -14), Color(1.0, 0.92, 0.78), 1.6, 12.0)
	kit.end_interior()
	kit.world._landmark("CLUB VOLTAGE", Vector3(-4, 0, HALF.y + 5.0))
	kit.node.set_meta("walk_in", true)
	kit.node.set_meta("interior_half", HALF)
	kit.node.set_meta("routes", {"front_to_alley": ROUTE, "fire_exit": FIRE_ROUTE, "mezzanine": MEZZ_ROUTE})
	kit.finish()


## Canopy, vertical neon blade, queue rope, bouncer's podium and a poster wall.
static func _street_front(kit: BuildingKit) -> void:
	var steel: Material = kit.mat(Color(0.14, 0.14, 0.15), "metal", 0.5)
	var brass: Material = kit.mat(Color(0.72, 0.58, 0.28), "metal", 0.35)
	var rope: Material = kit.mat(Color(0.5, 0.06, 0.1), "", 0.7)
	kit.box(Vector3(-4, 3.2, HALF.y + 1.25), Vector3(5.2, 0.24, 2.5), steel)
	kit.box(Vector3(-4, 3.05, HALF.y + 2.45), Vector3(5.2, 0.1, 0.1), kit.glow(Color(0.4, 0.9, 1.0), 2.2))
	kit.neon_sign("CLUB  VOLTAGE", Vector3(2.5, 5.4, HALF.y + 0.3), 0.0, Color(0.4, 0.9, 1.0), 84)
	kit.neon_sign("VOLTAGE", Vector3(-HALF.x + 1.2, 5.0, HALF.y + 0.6), 0.0, Color(1.0, 0.3, 0.8), 56, false, true)
	kit.sign_label("21+  ID REQUIRED", Vector3(-7.4, 2.1, HALF.y + 0.17), 26, Color(0.9, 0.9, 0.85))
	# Queue: brass stanchions along the wall, rope between them (thin posts collide, the rope doesn't).
	for index: int in range(6):
		var x: float = -6.4 - index * 1.4
		kit.box(Vector3(x, FLOOR_Y + 0.5, HALF.y + 1.6), Vector3(0.09, 1.0, 0.09), brass, true)
		kit.box(Vector3(x, FLOOR_Y + 0.03, HALF.y + 1.6), Vector3(0.34, 0.06, 0.34), brass)
		if index > 0:
			kit.box(Vector3(x + 0.7, FLOOR_Y + 0.86, HALF.y + 1.6), Vector3(1.3, 0.05, 0.05), rope)
	kit.box(Vector3(-1.1, FLOOR_Y + 0.55, HALF.y + 1.0), Vector3(0.6, 1.1, 0.45), steel, true)
	# Paste-up posters beside the door (original acts).
	var colors: Array[Color] = [Color(0.85, 0.3, 0.2), Color(0.2, 0.5, 0.8), Color(0.9, 0.8, 0.2), Color(0.3, 0.7, 0.4)]
	for index: int in range(4):
		kit.box(Vector3(5.0 + index * 1.05, 1.7, HALF.y + 0.17), Vector3(0.9, 1.25, 0.02), kit.mat(colors[index]))
	kit.sign_label("DJ KESTREL / FRI", Vector3(6.6, 2.5, HALF.y + 0.19), 18, Color(0.95, 0.95, 0.9))
	kit.sign_label("NYE 1999\nSOLD OUT", Vector3(7.1, 1.7, HALF.y + 0.19), 14, Color(0.15, 0.1, 0.1))


## Two structural columns in the main room: real cover, square to the grid.
static func _structure(kit: BuildingKit, material: Material) -> void:
	for at: Vector2 in [Vector2(-6.5, 4.0), Vector2(5.0, 4.0), Vector2(-6.5, -5.0)]:
		kit.box(Vector3(at.x, HEIGHT * 0.5, at.y), Vector3(0.7, HEIGHT - 0.2, 0.7), material, true)


static func _lobby(kit: BuildingKit) -> void:
	var wood: Material = kit.mat(Rooms.WOOD, "planks")
	var dark: Material = kit.mat(Color(0.08, 0.08, 0.1), "", 0.6)
	# Cashier / coat check behind the small front window: counter, hatch shelf, coat rail.
	kit.box(Vector3(7.0, FLOOR_Y + 0.55, HALF.y - 2.2), Vector3(4.5, 1.1, 0.7), wood, true)
	kit.box(Vector3(7.0, FLOOR_Y + 1.14, HALF.y - 2.2), Vector3(4.7, 0.08, 0.85), dark, true)
	kit.box(Vector3(10.2, FLOOR_Y + 1.1, LOBBY_Z + 1.0), Vector3(0.06, 2.2, 0.06), dark)
	kit.bar(Vector3(10.2, FLOOR_Y + 1.9, LOBBY_Z + 1.0), Vector3(14.8, FLOOR_Y + 1.9, LOBBY_Z + 1.0), 0.05, dark, false)
	var coats: Array[Color] = [Color(0.2, 0.2, 0.25), Color(0.45, 0.3, 0.2), Color(0.15, 0.3, 0.2), Color(0.5, 0.48, 0.44)]
	for index: int in range(7):
		kit.box(Vector3(10.7 + index * 0.6, FLOOR_Y + 1.35, LOBBY_Z + 1.0), Vector3(0.5, 1.0, 0.18), kit.mat(coats[index % coats.size()]))
	kit.box(Vector3(7.0, FLOOR_Y + 1.3, HALF.y - 2.0), Vector3(0.34, 0.24, 0.3), kit.mat(Color(0.25, 0.26, 0.24), "metal"))
	kit.sign_label("COVER $10", Vector3(7.0, 2.6, HALF.y - 1.82), 24, Color(1.0, 0.85, 0.4))
	# Cigarette machine and a payphone by the lobby screen.
	kit.box(Vector3(-13.6, FLOOR_Y + 0.95, LOBBY_Z + 0.55), Vector3(1.0, 1.9, 0.6), kit.mat(Color(0.55, 0.12, 0.12), "metal"), true)
	kit.box(Vector3(-13.6, FLOOR_Y + 1.4, LOBBY_Z + 0.87), Vector3(0.8, 0.5, 0.03), kit.glow(Color(1.0, 0.9, 0.7), 0.8))
	kit.box(Vector3(-11.8, FLOOR_Y + 1.5, LOBBY_Z + 0.25), Vector3(0.4, 0.6, 0.18), kit.mat(Color(0.3, 0.32, 0.33), "metal"))


## A 7 x 6 grid of emissive floor panels in four colours, a low surround and a mirror-ball rig.
static func _dance_floor(kit: BuildingKit) -> void:
	var palette: Array[Material] = [kit.glow(Color(1.0, 0.2, 0.55), 1.4), kit.glow(Color(0.2, 0.6, 1.0), 1.4),
		kit.glow(Color(1.0, 0.75, 0.2), 1.3), kit.glow(Color(0.35, 0.95, 0.5), 1.3)]
	var origin: Vector3 = Vector3(-1.5, FLOOR_Y, -1.0)
	for i: int in range(7):
		for j: int in range(6):
			var at: Vector3 = origin + Vector3((i - 3) * 1.2, 0.015, (j - 2.5) * 1.2)
			kit.box(at, Vector3(1.12, 0.03, 1.12), palette[(i * 3 + j * 5 + i * j) % palette.size()])
	kit.box(origin + Vector3(0, 0.012, 0), Vector3(8.7, 0.024, 7.5), kit.mat(Color(0.05, 0.05, 0.06), "metal", 0.4))
	# Mirror ball and a lighting truss hung from the roof: no collision, far above head height.
	var truss: Material = kit.mat(Color(0.35, 0.36, 0.38), "metal", 0.4)
	kit.box(origin + Vector3(0, 6.2, -3.8), Vector3(9.0, 0.25, 0.25), truss)
	kit.box(origin + Vector3(0, 6.2, 3.8), Vector3(9.0, 0.25, 0.25), truss)
	kit.box(origin + Vector3(0, 5.3, 0), Vector3(0.7, 0.7, 0.7), kit.glow(Color(0.85, 0.88, 0.95), 1.0))
	kit.box(origin + Vector3(0, 6.6, 0), Vector3(0.03, 1.9, 0.03), truss)
	for x: float in [-3.6, -1.2, 1.2, 3.6]:
		for z: float in [-3.8, 3.8]:
			kit.box(origin + Vector3(x, 5.95, z), Vector3(0.3, 0.35, 0.3), kit.mat(Color(0.08, 0.08, 0.08), "metal"))
	# DJ booth: raised deck with two steps, desk facing the floor, speaker stacks either side.
	var deck: Material = kit.mat(Color(0.1, 0.1, 0.11), "metal", 0.5)
	kit.box(Vector3(-1.5, FLOOR_Y + 0.27, BACK_Z + 2.0), Vector3(6.0, 0.54, 3.6), deck, true)
	kit.box(Vector3(-1.5, FLOOR_Y + 0.09, BACK_Z + 4.1), Vector3(2.0, 0.18, 0.6), deck, true)
	kit.box(Vector3(-1.5, FLOOR_Y + 0.18, BACK_Z + 4.1 - 0.3), Vector3(2.0, 0.36, 0.3), deck, true)
	kit.box(Vector3(-3.4, FLOOR_Y + 0.54 + 0.5, BACK_Z + 2.9), Vector3(2.4, 1.0, 0.8), deck, true)
	kit.box(Vector3(0.4, FLOOR_Y + 0.54 + 0.5, BACK_Z + 2.9), Vector3(2.4, 1.0, 0.8), deck, true)
	for x: float in [-3.9, -2.9, -0.1, 0.9]:
		kit.box(Vector3(x, FLOOR_Y + 1.58, BACK_Z + 2.9), Vector3(0.5, 0.06, 0.4), kit.mat(Color(0.2, 0.2, 0.2), "metal"))
		kit.box(Vector3(x, FLOOR_Y + 1.62, BACK_Z + 2.9), Vector3(0.36, 0.015, 0.36), kit.glow(Color(0.3, 0.9, 0.6), 0.9))
	var cone: Material = kit.mat(Color(0.05, 0.05, 0.05), "", 0.8)
	for x: float in [-6.8, 3.8]:
		kit.box(Vector3(x, FLOOR_Y + 1.5, BACK_Z + 1.2), Vector3(1.4, 3.0, 1.2), kit.mat(Color(0.12, 0.12, 0.13), "panel"), true)
		for y: float in [0.8, 1.9, 2.6]:
			kit.box(Vector3(x, FLOOR_Y + y, BACK_Z + 1.82), Vector3(0.9, 0.55 if y < 2.5 else 0.3, 0.03), cone)
	kit.neon_sign("V O L T A G E", Vector3(-1.5, 5.0, BACK_Z + 0.25), 0.0, Color(0.4, 0.9, 1.0), 64)


## Long bar on the left wall: counter (cover at waist height), back bar with lit bottle shelves,
## stools (no collision), beer taps, ice well.
static func _bar(kit: BuildingKit) -> void:
	var wood: Material = kit.mat(Color(0.25, 0.14, 0.1), "planks")
	var top: Material = kit.mat(Color(0.06, 0.06, 0.07), "", 0.3)
	var chrome: Material = kit.mat(Color(0.7, 0.72, 0.74), "metal", 0.25)
	kit.box(Vector3(-12.6, FLOOR_Y + 0.55, 1.0), Vector3(0.8, 1.1, 13.0), wood, true)
	kit.box(Vector3(-12.6, FLOOR_Y + 1.13, 1.0), Vector3(1.0, 0.07, 13.2), top, true)
	kit.box(Vector3(-12.2, FLOOR_Y + 0.08, 1.0), Vector3(0.08, 0.08, 12.8), chrome)
	kit.box(Vector3(-15.45, FLOOR_Y + 0.5, 1.0), Vector3(0.6, 1.0, 12.0), wood, true)
	var bottles: Array[Material] = [kit.glow(Color(0.5, 0.9, 0.4), 0.7), kit.glow(Color(0.95, 0.6, 0.2), 0.7),
		kit.glow(Color(0.8, 0.85, 0.9), 0.6), kit.glow(Color(0.7, 0.2, 0.3), 0.7)]
	for shelf: int in range(3):
		var y: float = FLOOR_Y + 1.5 + shelf * 0.55
		kit.box(Vector3(-15.55, y, 1.0), Vector3(0.36, 0.04, 11.0), kit.mat(Color(0.8, 0.85, 0.9), "", 0.1))
		for index: int in range(18):
			kit.box(Vector3(-15.55, y + 0.17, -4.1 + index * 0.6 + shelf * 0.2), Vector3(0.09, 0.3, 0.09), bottles[(index + shelf) % bottles.size()])
	kit.box(Vector3(-15.8, FLOOR_Y + 3.2, 1.0), Vector3(0.04, 0.9, 11.0), kit.mat(Color(0.35, 0.38, 0.42), "", 0.05))
	for z: float in [-2.0, 1.0, 4.0]:
		kit.box(Vector3(-12.5, FLOOR_Y + 1.35, z), Vector3(0.12, 0.4, 0.5), chrome)
	for index: int in range(8):
		var z: float = -4.6 + index * 1.5
		kit.box(Vector3(-11.4, FLOOR_Y + 0.4, z), Vector3(0.06, 0.8, 0.06), chrome)
		kit.box(Vector3(-11.4, FLOOR_Y + 0.82, z), Vector3(0.42, 0.08, 0.42), kit.mat(Color(0.5, 0.08, 0.12)))
	kit.neon_sign("BAR", Vector3(-15.75, 5.0, 1.0), PI * 0.5, Color(1.0, 0.35, 0.7), 56)


## Low lounge booths and cocktail tables along the right-hand wall under the mezzanine.
static func _lounge(kit: BuildingKit) -> void:
	var vinyl: Material = kit.mat(Color(0.32, 0.12, 0.4), "", 0.5)
	var table: Material = kit.mat(Color(0.08, 0.08, 0.09), "", 0.3)
	for z: float in [-7.0, -2.0]:
		kit.box(Vector3(14.9, FLOOR_Y + 0.25, z), Vector3(1.6, 0.5, 3.6), vinyl, true)
		kit.box(Vector3(15.55, FLOOR_Y + 0.85, z), Vector3(0.3, 0.9, 3.6), vinyl, true)
		kit.box(Vector3(12.9, FLOOR_Y + 0.28, z), Vector3(1.2, 0.56, 1.8), table, true)
	for at: Vector2 in [Vector2(6.5, 8.0), Vector2(9.5, 8.5), Vector2(6.5, -8.0)]:
		kit.box(Vector3(at.x, FLOOR_Y + 0.55, at.y), Vector3(0.08, 1.1, 0.08), table)
		kit.box(Vector3(at.x, FLOOR_Y + 1.1, at.y), Vector3(0.7, 0.05, 0.7), table)
		kit.box(Vector3(at.x, FLOOR_Y + 0.02, at.y), Vector3(0.45, 0.04, 0.45), table)


## VIP deck: two sofas, low tables and a small service counter.
static func _vip(kit: BuildingKit) -> void:
	var leather: Material = kit.mat(Color(0.08, 0.07, 0.07), "", 0.45)
	var gold: Material = kit.mat(Color(0.78, 0.62, 0.3), "metal", 0.3)
	for z: float in [-7.5, -2.5]:
		kit.box(Vector3(15.1, MEZZ_Y + 0.25, z), Vector3(1.2, 0.5, 3.4), leather, true)
		kit.box(Vector3(15.55, MEZZ_Y + 0.85, z), Vector3(0.3, 0.8, 3.4), leather, true)
		kit.box(Vector3(13.2, MEZZ_Y + 0.22, z), Vector3(1.0, 0.44, 1.6), kit.mat(Color(0.5, 0.5, 0.52), "", 0.05), true)
	kit.box(Vector3(12.5, MEZZ_Y + 0.55, -9.3), Vector3(5.0, 1.1, 0.6), leather, true)
	kit.box(Vector3(12.5, MEZZ_Y + 1.12, -9.3), Vector3(5.1, 0.05, 0.7), gold)
	kit.sign_label("VIP", Vector3(15.8, MEZZ_Y + 2.2, -5.0), 40, Color(0.95, 0.8, 0.4), PI * -0.5)


## Back of house: keg/stock room, the manager's office with safe, a mop sink and a corridor to the alley.
static func _back_of_house(kit: BuildingKit) -> void:
	var crate: Material = kit.mat(Color(0.45, 0.33, 0.2), "planks")
	var steel: Material = kit.mat(Color(0.55, 0.57, 0.58), "metal", 0.4)
	for index: int in range(5):
		kit.box(Vector3(-1.0 + index * 0.62, FLOOR_Y + 0.35, -17.1), Vector3(0.5, 0.7, 0.5), steel, true)
	for at: Vector3 in [Vector3(-14.6, 0, -16.6), Vector3(-14.6, 0, -14.8), Vector3(-14.6, 0.8, -16.6), Vector3(-4.0, 0, -17.0)]:
		kit.box(at + Vector3(0, FLOOR_Y + 0.4, 0), Vector3(1.2, 0.8, 1.2), crate, true)
	kit.box(Vector3(-5.5, FLOOR_Y + 1.0, -11.0), Vector3(3.0, 2.0, 0.6), kit.mat(Color(0.3, 0.3, 0.32), "metal"), true)
	for y: float in [0.5, 1.1, 1.7]:
		for index: int in range(6):
			kit.box(Vector3(-6.7 + index * 0.45, FLOOR_Y + y + 0.15, -11.0), Vector3(0.3, 0.26, 0.3), crate)
	kit.box(Vector3(2.8, FLOOR_Y + 0.45, -17.3), Vector3(1.2, 0.9, 0.6), steel, true)
	# Office: desk with CRT, safe, filing cabinet, a wall calendar and CCTV monitor.
	Rooms.desk(kit, Vector3(10.5, FLOOR_Y, -15.5))
	kit.box(Vector3(14.9, FLOOR_Y + 0.55, -16.8), Vector3(1.0, 1.1, 1.0), kit.mat(Color(0.22, 0.24, 0.22), "metal", 0.4), true)
	kit.box(Vector3(14.9, FLOOR_Y + 0.75, -16.28), Vector3(0.18, 0.18, 0.04), kit.mat(Color(0.75, 0.75, 0.7), "metal", 0.3))
	kit.box(Vector3(5.0, FLOOR_Y + 0.7, -17.4), Vector3(0.6, 1.4, 0.7), kit.mat(Color(0.45, 0.47, 0.44), "metal"), true)
	kit.box(Vector3(10.5, FLOOR_Y + 2.2, -17.8), Vector3(0.8, 0.6, 0.02), kit.mat(Color(0.9, 0.9, 0.85)))
	kit.sign_label("DEC 1999", Vector3(10.5, FLOOR_Y + 2.38, -17.78), 14, Color(0.6, 0.1, 0.1))
	kit.box(Vector3(8.0, FLOOR_Y + 1.9, -17.55), Vector3(0.6, 0.45, 0.4), kit.mat(Color(0.2, 0.2, 0.2), "metal"))
	kit.box(Vector3(8.0, FLOOR_Y + 1.9, -17.34), Vector3(0.46, 0.33, 0.02), kit.glow(Color(0.5, 0.75, 0.6), 0.6))
