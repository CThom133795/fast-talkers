extends RefCounted
## BIG BOY BURGERS: the walk-in diner (booths, service counter, kitchen, two exits) from
## neighborhood_rooms.gd, plus its lot dressing: a drive-through lane down the east side with a
## wall-mounted menu board, order speaker and a pickup window cut into the kitchen wall, a tall
## pole sign, a striped awning band, rooftop plant and a grease bin and dumpster out back.
## Keep static build(world, plot).

const Kit = preload("res://scripts/buildings/building_kit.gd")
const Rooms = preload("res://scripts/buildings/neighborhood_rooms.gd")

const HALF: Vector2 = Vector2(12, 10)
## Lane centre line (local x) and the pickup window's local z, used by tests/building_clubs.gd.
const LANE_X: float = 13.6
const WINDOW_Z: float = -8.0


static func build(world: Node3D, plot: Dictionary) -> void:
	Rooms.diner(world, plot)
	var kit: Kit = Kit.new(world, "BurgerLot", plot)
	var red: Material = kit.mat(Rooms.RED)
	var cream: Material = kit.mat(Rooms.CREAM)
	var steel: Material = kit.mat(Rooms.STEEL, "metal", 0.5)
	var paint: Material = kit.mat(Color(0.92, 0.86, 0.3), "", 0.8)
	# Drive-through: painted lane edge and arrows (flush with the lot, no collision), pickup sill.
	# Paint follows the real walking surface (plinth or open lot), so it neither floats nor sinks.
	for x: float in [LANE_X - 1.45, LANE_X + 1.45]:
		for z: float in [-9.0, -3.0, 3.0, 9.0]:
			kit.box(Vector3(x, _ground(kit, Vector3(x, 0, z)) + 0.008, z), Vector3(0.12, 0.012, 6.0), paint)
	for z: float in [-3.0, 4.5]:
		var y: float = _ground(kit, Vector3(LANE_X, 0, z)) + 0.008
		kit.box(Vector3(LANE_X, y, z), Vector3(0.25, 0.012, 1.6), paint)
		kit.box(Vector3(LANE_X, y, z - 0.95), Vector3(0.8, 0.012, 0.3), paint)
	kit.box(Vector3(HALF.x + 0.16, 3.4, 8.2), Vector3(0.12, 0.7, 2.6), red)
	kit.sign_label("DRIVE THRU", Vector3(HALF.x + 0.23, 3.4, 8.2), 32, Rooms.CREAM, PI * 0.5)
	kit.box(Vector3(HALF.x + 0.35, 1.02, WINDOW_Z), Vector3(0.45, 0.08, 1.8), steel)
	kit.box(Vector3(HALF.x + 0.2, 2.45, WINDOW_Z), Vector3(0.5, 0.12, 2.2), red)
	kit.sign_label("PAY  &  PICK UP", Vector3(HALF.x + 0.47, 2.45, WINDOW_Z), 18, Rooms.CREAM, PI * 0.5)
	# Menu board and speaker mounted on the wall, facing the lane (lit panel, no dynamic light).
	kit.box(Vector3(HALF.x + 0.18, 1.9, 3.0), Vector3(0.14, 1.9, 2.8), kit.mat(Color(0.1, 0.1, 0.1)))
	kit.box(Vector3(HALF.x + 0.26, 1.9, 3.0), Vector3(0.02, 1.7, 2.6), kit.glow(Color(1.0, 0.9, 0.7), 0.9))
	kit.sign_label("BIG BOY  $2.49\nDOUBLE  $3.29\nFRIES  $0.99\nSHAKE  $1.59", Vector3(HALF.x + 0.28, 1.9, 3.0), 16, Color(0.35, 0.05, 0.03), PI * 0.5)
	kit.box(Vector3(HALF.x + 0.16, 1.2, 0.9), Vector3(0.2, 0.5, 0.4), steel)
	kit.box(Vector3(HALF.x + 0.27, 1.25, 0.9), Vector3(0.02, 0.3, 0.3), kit.mat(Color(0.25, 0.25, 0.25), "metal"))
	# Pole sign at the front-west corner: a slim steel pole and a two-sided lit cabinet.
	var pole_at: Vector3 = Vector3(-HALF.x - 1.6, 0, HALF.y + 1.8)
	pole_at.y = _ground(kit, pole_at)
	kit.box(pole_at + Vector3(0, 3.8, 0), Vector3(0.35, 7.6, 0.35), steel, true)
	kit.box(pole_at + Vector3(0, 8.6, 0), Vector3(4.6, 2.0, 0.5), red)
	for side: float in [-1.0, 1.0]:
		kit.box(pole_at + Vector3(0, 8.6, side * 0.26), Vector3(4.3, 1.7, 0.02), kit.glow(Color(1.0, 0.92, 0.75), 1.1))
		kit.sign_label("BIG BOY\nBURGERS", pole_at + Vector3(0, 8.6, side * 0.28), 64, Rooms.RED, 0.0 if side > 0.0 else PI)
	kit.box(pole_at + Vector3(0, 7.2, 0), Vector3(3.6, 0.6, 0.35), cream)
	kit.sign_label("OPEN 24 HRS", pole_at + Vector3(0, 7.2, 0.19), 30, Rooms.RED)
	kit.sign_label("OPEN 24 HRS", pole_at + Vector3(0, 7.2, -0.19), 30, Rooms.RED, PI)
	# Striped awning band over the front windows, and a roof edge.
	for index: int in range(16):
		var x: float = -HALF.x + 0.75 + index * 1.5
		if absf(x) < 1.6:
			continue
		kit.box(Vector3(x, 3.05, HALF.y + 0.6), Vector3(1.5, 0.12, 1.2), red if index % 2 == 0 else cream, false, 0.0)
	kit.box(Vector3(0, 4.55, 0), Vector3(HALF.x * 2 + 0.4, 0.2, HALF.y * 2 + 0.4), cream)
	# Rooftop: two condensers and the kitchen's grease exhaust stack above the griddles.
	for x: float in [-6.0, -2.5]:
		kit.box(Vector3(x, 5.2, -6.0), Vector3(2.2, 1.1, 1.6), kit.mat(Color(0.55, 0.57, 0.57), "metal", 0.6))
		kit.box(Vector3(x, 5.77, -6.0), Vector3(1.2, 0.04, 1.2), steel)
	kit.box(Vector3(7.5, 5.4, -8.5), Vector3(1.0, 1.6, 1.0), steel)
	kit.box(Vector3(7.5, 6.3, -8.5), Vector3(1.4, 0.2, 1.4), steel)
	# Out back: a dumpster, a grease bin and flattened boxes, clear of the rear door.
	var back: float = _ground(kit, Vector3(-7.0, 0, -HALF.y - 1.3))
	kit.box(Vector3(-7.0, back + 0.65, -HALF.y - 1.3), Vector3(2.6, 1.3, 1.5), kit.mat(Color(0.18, 0.32, 0.2), "metal", 0.7), true)
	kit.box(Vector3(-7.0, back + 1.35, -HALF.y - 1.3), Vector3(2.7, 0.1, 1.6), kit.mat(Color(0.1, 0.12, 0.1), "", 0.8))
	kit.box(Vector3(-3.6, back + 0.5, -HALF.y - 0.9), Vector3(1.1, 1.0, 0.9), kit.mat(Color(0.35, 0.3, 0.22), "metal"), true)
	kit.box(Vector3(-9.6, back + 0.04, -HALF.y - 0.9), Vector3(1.2, 0.08, 0.9), kit.mat(Color(0.55, 0.42, 0.28)))
	kit.box(Vector3(-9.5, back + 0.105, -HALF.y - 0.8), Vector3(1.0, 0.05, 0.8), kit.mat(Color(0.6, 0.47, 0.3)))
	kit.node.set_meta("drive_thru", {"lane_x": LANE_X, "window_z": WINDOW_Z})
	kit.finish()


## Walking-surface height under a local point (block plinth, lot or open ground).
static func _ground(kit: Kit, local: Vector3) -> float:
	var at: Vector3 = kit.to_world(local)
	return kit.world.surface_height(Vector2(at.x, at.z))
