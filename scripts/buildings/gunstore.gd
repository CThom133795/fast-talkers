extends RefCounted
## HALCYON ARMS - GUNS & RANGE (plot "gunstore", East Shore). A believable late-90s gun shop that
## exists in every game mode:
##   - a brick storefront with a rooftop sign, barred breakable windows and a glass-and-steel door;
##   - the shop: counters, display cases, a gun wall, ammunition shelves, a register;
##   - a back door to an indoor range: eight lanes with booths, overhead baffles, paper-target carriers
##     and a bullet trap;
##   - a fenced outdoor yard behind (chain-link, berms, a vehicle gate onto Gun Club Road) for long range.
## The range doors and the yard gate are registered in world.gun_doors; world.set_mode() locks them in
## contract and online rounds. The free-roam target range (targets, plates, rack, painted lines, labels)
## is the Armory node's job: scripts/armory.gd lays it out inside this yard.
##
## Local frame (see building_kit.gd): +Z is out of the front door (world -X, towards East Shore Drive), +X
## runs along the facade (world +Z). The building is 26 wide (X) and 46 deep (Z): shop at the front, indoor
## range behind it, the yard beyond the back wall.

const BuildingKit = preload("res://scripts/buildings/building_kit.gd")

const HALF_W: float = 13.0
const HALF_D: float = 23.0
const HEIGHT: float = 4.6
const SHOP_BACK: float = 7.0
const YARD_DEPTH: float = 80.0
## The yard fence, in local coordinates: x from -26 to 34 (world z -92..-32), z from -23 to -103.
const YARD_X0: float = -26.0
const YARD_X1: float = 34.0
## The range door in the partition (x along the facade).
const RANGE_DOOR_X: float = -6.2


static func build(world: Node3D, plot: Dictionary) -> void:
	var kit: BuildingKit = BuildingKit.new(world, "GunStore", plot)
	_shell(kit)
	var yard_door: int = _doors(kit)
	_yard(kit, yard_door)
	_parking(kit)
	kit.begin_interior()
	_shop_interior(kit)
	_range_interior(kit)
	kit.end_interior()
	kit.finish()


static func _shell(kit: BuildingKit) -> void:
	var brick: StandardMaterial3D = kit.mat(Color(0.44, 0.38, 0.32), "brick", 0.9)
	var trim: StandardMaterial3D = kit.mat(Color(0.13, 0.13, 0.14), "", 0.6)
	var roof: StandardMaterial3D = kit.mat(Color(0.29, 0.31, 0.3), "roof", 0.9)
	kit.footprint(Rect2(-HALF_W, -HALF_D, HALF_W * 2.0, HALF_D * 2.0))
	var front: float = HALF_D - 0.15
	# Storefront: a door in the middle, a barred window either side.
	kit.wall(Vector2(-HALF_W, front), Vector2(HALF_W, front), HEIGHT, brick, [
		BuildingKit.opening(HALF_W, 1.9, 0.0, 2.6, "door"),
		BuildingKit.opening(HALF_W - 7.5, 4.6, 0.9, 2.9, "window"),
		BuildingKit.opening(HALF_W + 7.5, 4.6, 0.9, 2.9, "window")])
	# Side walls are blank brick; the back wall has the yard door.
	kit.wall(Vector2(-HALF_W + 0.15, -HALF_D), Vector2(-HALF_W + 0.15, HALF_D), HEIGHT, brick)
	kit.wall(Vector2(HALF_W - 0.15, -HALF_D), Vector2(HALF_W - 0.15, HALF_D), HEIGHT, brick)
	kit.wall(Vector2(-HALF_W, -HALF_D + 0.15), Vector2(HALF_W, -HALF_D + 0.15), HEIGHT, brick, [BuildingKit.opening(HALF_W + 7.0, 1.9, 0.0, 2.6, "door")])
	# Partition between the shop and the range hall, with the range door in it.
	kit.wall(Vector2(-HALF_W + 0.3, SHOP_BACK), Vector2(HALF_W - 0.3, SHOP_BACK), HEIGHT - 0.1, kit.mat(Color(0.82, 0.8, 0.72), "stucco", 0.9), [BuildingKit.opening(6.5, 1.9, 0.0, 2.6, "door")])
	# Roof, a low parapet and a cornice; a rooftop sign board over the front.
	kit.floor_slab(Rect2(-HALF_W, -HALF_D, HALF_W * 2.0, HALF_D * 2.0), HEIGHT + 0.3, roof)
	for corners: Array in [[Vector3(-HALF_W, HEIGHT + 0.3, -HALF_D), Vector3(HALF_W, HEIGHT + 0.3, -HALF_D)], [Vector3(HALF_W, HEIGHT + 0.3, -HALF_D), Vector3(HALF_W, HEIGHT + 0.3, HALF_D)],
			[Vector3(HALF_W, HEIGHT + 0.3, HALF_D), Vector3(-HALF_W, HEIGHT + 0.3, HALF_D)], [Vector3(-HALF_W, HEIGHT + 0.3, HALF_D), Vector3(-HALF_W, HEIGHT + 0.3, -HALF_D)]]:
		kit.parapet(corners[0], corners[1], 0.6, 0.3, brick)
	kit.box(Vector3(0, HEIGHT + 0.15, HALF_D + 0.12), Vector3(HALF_W * 2.0 + 0.3, 0.4, 0.3), trim)
	kit.box(Vector3(0, HEIGHT + 2.1, HALF_D - 0.6), Vector3(15.0, 2.6, 0.3), kit.mat(Color(0.08, 0.1, 0.1), "", 0.6))
	for post: float in [-6.5, 6.5]:
		kit.box(Vector3(post, HEIGHT + 0.9, HALF_D - 0.6), Vector3(0.25, 1.4, 0.25), trim)
	kit.sign_label("HALCYON  ARMS", Vector3(0, HEIGHT + 2.6, HALF_D - 0.42), 96, Color(0.96, 0.84, 0.5), 0.0)
	kit.sign_label("GUNS  -  AMMO  -  RANGE", Vector3(0, HEIGHT + 1.55, HALF_D - 0.42), 44, Color(0.85, 0.9, 0.85), 0.0)
	kit.neon_sign("OPEN", Vector3(HALF_W - 4.6, 2.05, HALF_D + 0.1), 0.0, Color(1.0, 0.25, 0.2), 44)
	kit.box(Vector3(0, 3.55, HALF_D + 0.13), Vector3(HALF_W * 2.0, 0.9, 0.12), trim)
	kit.sign_label("FIREARMS  *  AMMUNITION  *  INDOOR RANGE", Vector3(0, 3.55, HALF_D + 0.22), 32, Color(0.95, 0.92, 0.8), 0.0)
	# Steel bars over both windows: thin, solid, and you can see through and shoot between them.
	for centre: float in [-7.5, 7.5]:
		var x0: float = centre - 2.3
		for index: int in range(21):
			var x: float = x0 + index * 0.23
			var bar: MeshInstance3D = kit.box(Vector3(x, 1.95, HALF_D + 0.22), Vector3(0.035, 2.2, 0.035), trim)
			bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			kit.collider(Vector3(x, 1.95, HALF_D + 0.22), Vector3(0.035, 2.2, 0.035))
		for y: float in [0.9, 1.9, 2.85]:
			kit.box(Vector3(centre, y, HALF_D + 0.22), Vector3(4.7, 0.05, 0.05), trim, true)
	# A steel roller grille housing over the door and a step up to it.
	kit.box(Vector3(0, 0.08, HALF_D + 0.8), Vector3(3.0, 0.16, 1.4), kit.mat(Color(0.46, 0.45, 0.42), "tiles", 0.9), true)


## The three doors that lock in matches and the shop's own door. Returns the yard door's index.
static func _doors(kit: BuildingKit) -> int:
	var front: float = HALF_D - 0.15
	var glass_door: StandardMaterial3D = kit.mat(Color(0.1, 0.1, 0.11), "metal", 0.5)
	kit.add_door(Vector3(0, 0, front), 1.9, 2.6, Vector3.BACK, "HALCYON ARMS", "door", glass_door, 2)
	var range_door: int = kit.add_door(Vector3(RANGE_DOOR_X, 0, SHOP_BACK), 1.9, 2.6, Vector3.BACK, "INDOOR  RANGE", "range", kit.mat(Color(0.2, 0.22, 0.2), "metal", 0.6), 2)
	var yard_door: int = kit.add_door(Vector3(7.0, 0, -HALF_D + 0.15), 1.9, 2.6, Vector3.BACK, "RANGE  YARD", "range", kit.mat(Color(0.2, 0.22, 0.2), "metal", 0.6), 2)
	kit.world.gun_doors.append(range_door)
	kit.world.gun_doors.append(yard_door)
	return yard_door


## The outdoor yard: chain-link on a solid windbreak, a vehicle gate onto Gun Club Road, earth berms
## and a shooting pad (the targets are the Armory node's).
static func _yard(kit: BuildingKit, _yard_door: int) -> void:
	var z_back: float = -HALF_D
	var z_end: float = -HALF_D - YARD_DEPTH
	var gate_at: float = -41.0
	var gate_width: float = 6.0
	var y: float = 0.0
	# North and east sides, the south side either side of the gate, and the back-wall returns.
	kit.world._fence(Vector3(YARD_X0, y, z_back), Vector3(YARD_X0, y, z_end), 3.2)
	kit.world._fence(Vector3(YARD_X0, y, z_end), Vector3(YARD_X1, y, z_end), 3.2)
	kit.world._fence(Vector3(YARD_X1, y, z_end), Vector3(YARD_X1, y, gate_at - gate_width * 0.5), 3.2)
	kit.world._fence(Vector3(YARD_X1, y, gate_at + gate_width * 0.5), Vector3(YARD_X1, y, z_back), 3.2)
	kit.world._fence(Vector3(YARD_X0, y, z_back), Vector3(-HALF_W, y, z_back), 3.2)
	kit.world._fence(Vector3(HALF_W, y, z_back), Vector3(YARD_X1, y, z_back), 3.2)
	# The gate: two leaves that swing into the yard, registered like a door.
	var gate: int = kit.add_door(Vector3(YARD_X1, 0, gate_at), gate_width, 2.4, Vector3.RIGHT, "RANGE  YARD  GATE", "gate", kit.mat(Color(0.14, 0.24, 0.2), "metal", 0.8), 2)
	kit.world.gun_doors.append(gate)
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(YARD_X1, 1.7, gate_at + side * (gate_width * 0.5 + 0.15)), Vector3(0.3, 3.4, 0.3), kit.mat(Color(0.32, 0.34, 0.35), "metal", 0.6), true)
	kit.sign_label("HALCYON ARMS  -  RANGE MEMBERS ONLY", Vector3(YARD_X1 + 0.12, 2.4, gate_at), 30, Color(0.95, 0.92, 0.8), PI * 0.5)
	# Earth berms: the backstop behind the long range and low banks along the fence lines.
	var earth: StandardMaterial3D = kit.mat(Color(0.36, 0.3, 0.22), "grass", 0.95)
	kit.box(Vector3((YARD_X0 + YARD_X1) * 0.5, 1.6, z_end - 3.0), Vector3(YARD_X1 - YARD_X0 + 6.0, 3.2, 5.0), earth, true)
	kit.box(Vector3(YARD_X0 - 3.0, 0.7, (z_back + z_end) * 0.5), Vector3(4.0, 1.4, YARD_DEPTH), earth, true)
	# A concrete shooting pad along the back wall.
	kit.box(Vector3((YARD_X0 + YARD_X1) * 0.5 + 0.0, 0.03, z_back - 15.0), Vector3(YARD_X1 - YARD_X0 - 1.0, 0.05, 30.0), kit.mat(Color(0.5, 0.49, 0.46), "tiles", 0.9))
	kit.sign_label("WEAR EYE AND EAR PROTECTION", Vector3(0, 3.6, -HALF_D - 0.12), 34, Color(1.0, 0.85, 0.3), PI)
	kit.sign_label("CEASE FIRE WHEN THE FLAG IS UP", Vector3(0, 3.0, -HALF_D - 0.12), 26, Color(0.9, 0.9, 0.85), PI)


## The lot in front: asphalt, painted bays and the free-roam motor pool.
static func _parking(kit: BuildingKit) -> void:
	kit.box(Vector3(0, 0.03, HALF_D + 7.5), Vector3(HALF_W * 2.0 + 6.0, 0.05, 14.0), kit.mat(Color(0.2, 0.22, 0.23), "asphalt", 0.9))
	var bays: Array[float] = [-11.0, -5.5, 5.5, 11.0]
	for x: float in [-13.75, -8.25, -2.75, 2.75, 8.25, 13.75]:
		kit.box(Vector3(x, 0.07, HALF_D + 5.2), Vector3(0.09, 0.015, 5.2), kit.mat(Color(0.74, 0.7, 0.53)))
	var types: Array[String] = ["sedan", "coupe", "suv", "pickup"]
	var colors: Array[Color] = [Color(0.72, 0.68, 0.55), Color(0.1, 0.25, 0.45), Color(0.22, 0.3, 0.22), Color(0.55, 0.15, 0.12)]
	for index: int in range(bays.size()):
		kit.world._car_prop(Vector3(bays[index], 0.03, HALF_D + 4.6), 0.0, colors[index], types[index], "RANGE %s" % types[index].to_upper())
	kit.world._car_prop(Vector3(0.0, 0.03, HALF_D + 9.5), PI * 0.5, Color(0.08, 0.08, 0.09), "motorcycle", "RANGE MOTORCYCLE")
	kit.sign_label("CUSTOMER PARKING", Vector3(-14.6, 2.2, HALF_D + 12.0), 40, Color(0.9, 0.9, 0.85), PI * 0.5)


# --- The shop -----------------------------------------------------------------------------------

static func _shop_interior(kit: BuildingKit) -> void:
	var floor_mat: StandardMaterial3D = kit.mat(Color(0.55, 0.53, 0.48), "tiles", 0.8)
	var wall_mat: StandardMaterial3D = kit.mat(Color(0.82, 0.8, 0.72), "stucco", 0.9)
	var wood: StandardMaterial3D = kit.mat(Color(0.3, 0.19, 0.12), "planks", 0.7)
	var steel: StandardMaterial3D = kit.mat(Color(0.2, 0.21, 0.22), "metal", 0.5)
	var z0: float = SHOP_BACK
	var z1: float = HALF_D - 0.3
	var mid_z: float = (z0 + z1) * 0.5
	kit.box(Vector3(0, 0.04, mid_z), Vector3(HALF_W * 2.0 - 0.6, 0.06, z1 - z0), floor_mat)
	kit.box(Vector3(0, HEIGHT - 0.06, mid_z), Vector3(HALF_W * 2.0 - 0.6, 0.1, z1 - z0), kit.mat(Color(0.86, 0.85, 0.8), "", 0.95))
	# Interior lining respects the storefront's door and windows; no painted-over openings.
	kit.wall(Vector2(-HALF_W, z1 - 0.02), Vector2(HALF_W, z1 - 0.02), HEIGHT, wall_mat, [
		BuildingKit.opening(HALF_W, 1.9, 0.0, 2.6, "door"),
		BuildingKit.opening(HALF_W - 7.5, 4.6, 0.9, 2.9, "gap"),
		BuildingKit.opening(HALF_W + 7.5, 4.6, 0.9, 2.9, "gap")])
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(side * (HALF_W - 0.32), 2.2, mid_z), Vector3(0.04, 4.3, z1 - z0), wall_mat)
	kit.wall(Vector2(-HALF_W, z0 + 0.2), Vector2(HALF_W, z0 + 0.2), HEIGHT, wall_mat,
		[BuildingKit.opening(HALF_W + RANGE_DOOR_X, 1.9, 0.0, 2.6, "door")])
	# The gun wall: pegboard behind the counter with rifles and shotguns on hooks, three rows.
	var board: StandardMaterial3D = kit.mat(Color(0.18, 0.14, 0.11), "planks", 0.8)
	for span: Vector2 in [Vector2(-10.9, RANGE_DOOR_X - 1.1), Vector2(RANGE_DOOR_X + 1.1, 10.9)]:
		kit.box(Vector3((span.x + span.y) * 0.5, 2.1, z0 + 0.26), Vector3(span.y - span.x, 2.2, 0.06), board)
	var stock_mat: StandardMaterial3D = kit.mat(Color(0.34, 0.2, 0.1), "planks", 0.6)
	var barrel_mat: StandardMaterial3D = kit.mat(Color(0.07, 0.07, 0.08), "", 0.4)
	for row: int in range(3):
		for column: int in range(8):
			var gx: float = -9.0 + column * 2.4 + (0.6 if row == 1 else 0.0)
			if absf(gx - RANGE_DOOR_X) < 1.8:
				continue
			var gy: float = 2.9 - row * 0.65
			kit.box(Vector3(gx, gy, z0 + 0.34), Vector3(1.05 if row == 0 else 0.85, 0.06, 0.06), barrel_mat)
			kit.box(Vector3(gx - (0.7 if row == 0 else 0.55), gy - 0.02, z0 + 0.34), Vector3(0.42, 0.13, 0.07), stock_mat)
	kit.sign_label("NO  LOITERING  -  ALL  SALES  FINAL", Vector3(-3.5, 3.9, z0 + 0.24), 26, Color(0.9, 0.85, 0.7), 0.0)
	# The counter: a long glass-topped display case with a return, cash register and a clerk's gap.
	var glass_top: StandardMaterial3D = kit.glass_material()
	var counter_z: float = z0 + 4.2
	for span: Vector2 in [Vector2(-11.6, -1.2), Vector2(1.2, 11.6)]:
		var length: float = span.y - span.x
		var cx: float = (span.x + span.y) * 0.5
		kit.box(Vector3(cx, 0.55, counter_z), Vector3(length, 1.1, 1.0), wood, true)
		kit.box(Vector3(cx, 1.13, counter_z), Vector3(length + 0.06, 0.05, 1.06), kit.mat(Color(0.1, 0.1, 0.11), "", 0.4))
		kit.box(Vector3(cx, 1.42, counter_z + 0.02), Vector3(length - 0.2, 0.5, 0.86), glass_top)
		# Handguns laid out under the glass.
		for gun: int in range(int(length / 1.0)):
			kit.box(Vector3(span.x + 0.6 + gun * 1.0, 1.2, counter_z), Vector3(0.24, 0.09, 0.07), barrel_mat)
	kit.box(Vector3(-12.3 + 0.9, 0.55, counter_z - 1.5), Vector3(1.0, 1.1, 3.0), wood, true)
	kit.box(Vector3(5.5, 1.3, counter_z - 0.05), Vector3(0.55, 0.32, 0.45), kit.mat(Color(0.75, 0.73, 0.66), "", 0.6))
	kit.box(Vector3(5.5, 1.36, counter_z + 0.2), Vector3(0.36, 0.2, 0.02), kit.glow(Color(0.5, 1.0, 0.6), 0.9))
	# Ammunition shelves along the side walls and a rack of rifles on the right.
	for side: float in [-1.0, 1.0]:
		var wall_x: float = side * (HALF_W - 0.62)
		for shelf: int in range(4):
			kit.box(Vector3(wall_x, 0.55 + shelf * 0.55, mid_z + 2.5), Vector3(0.5, 0.05, 6.0), steel)
		for stack: int in range(34):
			var sy: float = 0.62 + (stack % 4) * 0.55
			var sz: float = mid_z + 0.0 + floorf(stack / 4.0) * 0.72
			kit.box(Vector3(wall_x, sy + 0.08, sz), Vector3(0.36, 0.16, 0.5), kit.mat([Color(0.8, 0.2, 0.15), Color(0.9, 0.75, 0.2), Color(0.2, 0.4, 0.7), Color(0.85, 0.85, 0.8)][stack % 4], "", 0.6))
		for post: float in [-0.4, 6.3]:
			kit.box(Vector3(wall_x, 1.2, mid_z + post - 0.4 + 0.0), Vector3(0.06, 2.4, 0.06), steel)
	kit.box(Vector3(-HALF_W + 0.9, 1.4, mid_z + 6.0), Vector3(0.3, 2.6, 1.6), wood, true)
	kit.sign_label("SAFETY  FIRST", Vector3(HALF_W - 0.4, 3.4, mid_z), 34, Color(1.0, 0.85, 0.3), -PI * 0.5)
	for x: float in [-4.0, 4.0]:
		for z: float in [mid_z + 1.5, mid_z + 6.5]:
			kit.box(Vector3(x, HEIGHT - 0.14, z), Vector3(1.4, 0.05, 0.35), kit.glow(Color(1.0, 0.95, 0.85), 1.4))
	kit.interior_light(Vector3(0, HEIGHT - 0.7, mid_z), Color(1.0, 0.92, 0.75), 2.4, 15.0)


# --- The indoor range -----------------------------------------------------------------------------

static func _range_interior(kit: BuildingKit) -> void:
	var floor_mat: StandardMaterial3D = kit.mat(Color(0.32, 0.32, 0.31), "panel", 0.9)
	var wall_mat: StandardMaterial3D = kit.mat(Color(0.58, 0.58, 0.55), "panel", 0.9)
	var steel: StandardMaterial3D = kit.mat(Color(0.2, 0.21, 0.22), "metal", 0.5)
	var rubber: StandardMaterial3D = kit.mat(Color(0.1, 0.1, 0.1), "", 0.9)
	var z_front: float = SHOP_BACK - 0.3
	var z_back: float = -HALF_D + 0.3
	var length: float = z_front - z_back
	var mid_z: float = (z_front + z_back) * 0.5
	kit.box(Vector3(0, 0.04, mid_z), Vector3(HALF_W * 2.0 - 0.6, 0.06, length), floor_mat)
	kit.box(Vector3(0, HEIGHT - 0.06, mid_z), Vector3(HALF_W * 2.0 - 0.6, 0.1, length), kit.mat(Color(0.3, 0.3, 0.32), "", 0.95))
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(side * (HALF_W - 0.32), 2.2, mid_z), Vector3(0.04, 4.3, length), wall_mat)
	# Leave the back-wall lining and bullet trap clear of the yard-door escape aisle.
	var trap_spans: Array[Vector2] = [Vector2(-HALF_W + 0.3, 5.8), Vector2(8.2, HALF_W - 0.3)]
	for span: Vector2 in trap_spans:
		kit.box(Vector3((span.x + span.y) * 0.5, 2.2, z_back + 0.02), Vector3(span.y - span.x, 4.3, 0.04), wall_mat)
	# Eight lanes: a booth (two low dividers and a bench) at the firing line, a paper-target carrier
	# hanging at the far end, and the bullet trap behind it.
	var lane_width: float = 2.6
	var line_z: float = 2.6
	for lane: int in range(8):
		var x: float = (lane - 3.5) * lane_width
		kit.box(Vector3(x, 1.0, line_z + 0.7), Vector3(lane_width - 0.16, 0.08, 0.5), kit.mat(Color(0.34, 0.24, 0.16), "planks", 0.7), true)
		kit.box(Vector3(x, 0.5, line_z + 0.7), Vector3(0.08, 1.0, 0.44), steel)
		kit.sign_label(str(lane + 1), Vector3(x, 1.55, line_z + 1.05), 34, Color(1.0, 0.85, 0.3), 0.0)
		# Target frame and paper at 21 m.
		var target_z: float = z_back + 3.6
		kit.box(Vector3(x, 1.5, target_z), Vector3(0.62, 0.9, 0.02), kit.mat(Color(0.93, 0.92, 0.88), "", 0.9))
		kit.box(Vector3(x, 1.55, target_z + 0.015), Vector3(0.3, 0.55, 0.01), kit.mat(Color(0.12, 0.12, 0.13), "", 0.9))
		kit.box(Vector3(x, 2.0, target_z), Vector3(0.05, 3.8, 0.05), steel)
	for divider: int in range(9):
		var x: float = (divider - 4.0) * lane_width
		kit.box(Vector3(x, 0.9, line_z - 0.9), Vector3(0.07, 1.8, 3.0), steel, true)
	# Baffles: angled steel plates hanging across the range, low enough to catch a wild round.
	for baffle: int in range(3):
		var bz: float = lerpf(line_z - 4.0, z_back + 6.0, (baffle + 0.5) / 3.0)
		kit.box(Vector3(0, HEIGHT - 0.9, bz), Vector3(HALF_W * 2.0 - 0.8, 1.2, 0.12), steel, true)
	# Bullet trap: a dark rubber and steel wall with a sloped deflector.
	for span: Vector2 in trap_spans:
		var center_x: float = (span.x + span.y) * 0.5
		kit.box(Vector3(center_x, 1.6, z_back + 0.5), Vector3(span.y - span.x, 3.2, 0.9), rubber, true)
		kit.box(Vector3(center_x, 0.3, z_back + 1.3), Vector3(span.y - span.x, 0.6, 0.8), steel, true)
	kit.sign_label("INDOOR  RANGE  -  25 YARDS", Vector3(0, 3.7, z_front - 0.15), 44, Color(0.95, 0.85, 0.5), PI)
	kit.sign_label("HOLD FIRE  -  RANGE OFFICER ON DUTY", Vector3(0, 3.1, z_front - 0.15), 26, Color(0.9, 0.9, 0.85), PI)
	for x: float in [-6.0, 0.0, 6.0]:
		for z: float in [mid_z + 6.0, mid_z - 4.0]:
			kit.box(Vector3(x, HEIGHT - 0.14, z), Vector3(1.6, 0.05, 0.35), kit.glow(Color(0.85, 0.95, 1.0), 1.3))
	kit.interior_light(Vector3(0, HEIGHT - 0.8, mid_z), Color(0.9, 0.95, 1.0), 2.2, 20.0)
