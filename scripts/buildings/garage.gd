extends RefCounted
## Plot "garage": CENTRAL PARKING, a three-deck concrete garage on Motor Mile, the kind of place
## where a deal happens on the top deck. Ground floor, one mid deck and an open roof deck.
##
## Circulation (local frame, +Z = street front): cars enter along the front aisle, climb the west
## ramp (0 -> 1, heading -Z) to the back aisle, cross to the east ramp (1 -> 2, heading +Z) and come
## out on the roof's front aisle. Ramps are 11.7 degrees and 6.6 m wide; aisles are 7 m. Parking
## bays fill the middle block on every deck. Two U-stairs (not stacked, so their solid steps never
## cut headroom) link the decks, with railings round each stair hole. Open sides carry solid 1 m
## parapets (cover you can see); ramp sides are full-height walls. A ticket booth, a raised barrier
## arm, painted bays and level numbers, tube lights and a few dust-sheeted cars nobody came back for.
##
## Half size 15 x 14.

const BuildingKit = preload("res://scripts/buildings/building_kit.gd")

const HALF: Vector2 = Vector2(15, 14)
const LEVELS: Array[float] = [0.17, 3.07, 5.97]
const LANE: float = 7.0
const RAMP_Z: float = 7.0
const WEST_RAMP: Rect2 = Rect2(-15, -7, 7, 14)
const EAST_RAMP: Rect2 = Rect2(8, -7, 7, 14)
## U-stair A (ground -> deck 1) and B (deck 1 -> roof): start points (first riser, heading +Z).
const STAIR_A: Vector3 = Vector3(-4.2, 0.17, -6.5)
const STAIR_B: Vector3 = Vector3(2.8, 3.07, -6.5)
## Stair holes cover both flights, the landing and 0.8 m of turning headroom beyond it.
const HOLE_A: Rect2 = Rect2(-4.8, -6.8, 2.6, 4.7)
const HOLE_B: Rect2 = Rect2(2.2, -6.8, 2.6, 4.7)
## Walk route for tests/building_landmarks.gd: street -> stair A -> deck 1 -> stair B -> roof.
const ROUTE: Array[Vector3] = [Vector3(-3.0, 0.17, 16.0), Vector3(-3.0, 0.17, 10.0), Vector3(-4.4, 0.17, 7.8), Vector3(-4.4, 0.17, -1.0),
	Vector3(-5.4, 0.17, -2.0), Vector3(-5.4, 0.17, -7.2), Vector3(-4.2, 0.17, -7.2), Vector3(-4.2, 0.17, -6.7), Vector3(-4.2, 1.53, -4.0),
	Vector3(-4.2, 1.53, -3.4), Vector3(-2.8, 1.53, -3.4), Vector3(-2.8, 1.53, -4.0), Vector3(-2.8, 3.07, -7.0), Vector3(-2.8, 3.07, -7.8),
	Vector3(2.8, 3.07, -7.8), Vector3(2.8, 3.07, -6.7), Vector3(2.8, 4.43, -4.0), Vector3(2.8, 4.43, -3.4), Vector3(4.2, 4.43, -3.4),
	Vector3(4.2, 4.43, -4.0), Vector3(4.2, 5.97, -7.0), Vector3(4.2, 5.97, -10.0), Vector3(0.0, 5.97, -10.0)]


static func build(world: Node3D, plot: Dictionary) -> void:
	var kit: BuildingKit = BuildingKit.new(world, "Garage", plot)
	var concrete: Material = kit.mat(Color(0.52, 0.51, 0.48), "panel", 0.95)
	var deck: Material = kit.mat(Color(0.4, 0.4, 0.39), "asphalt", 0.95)
	var wall: Material = kit.mat(Color(0.6, 0.58, 0.54), "panel")
	var rect: Rect2 = Rect2(-HALF, HALF * 2.0)
	kit.footprint(rect)
	kit.floor_slab(rect, LEVELS[0], deck)
	kit.floor_slab(rect, LEVELS[1], deck, [WEST_RAMP, HOLE_A])
	kit.floor_slab(rect, LEVELS[2], deck, [EAST_RAMP, HOLE_B])
	# Ramps and the walls that keep cars on them (full height; they are also the decks' guards).
	var ramp_west: Dictionary = kit.ramp(Vector3(-11.5, LEVELS[0], RAMP_Z), Vector3(-11.5, LEVELS[1], -RAMP_Z), LANE - 0.4, deck)
	var ramp_east: Dictionary = kit.ramp(Vector3(11.5, LEVELS[1], -RAMP_Z), Vector3(11.5, LEVELS[2], RAMP_Z), LANE - 0.4, deck)
	kit.node.set_meta("ramps", [ramp_west, ramp_east])
	kit.wall(Vector2(-8, -RAMP_Z), Vector2(-8, RAMP_Z), LEVELS[1] + 1.0 - LEVELS[0], wall, [], LEVELS[0], 0.25)
	kit.wall(Vector2(-HALF.x, -RAMP_Z), Vector2(-HALF.x, RAMP_Z), LEVELS[1] + 1.0 - LEVELS[0], wall, [], LEVELS[0], 0.3)
	kit.wall(Vector2(8, -RAMP_Z), Vector2(8, RAMP_Z), LEVELS[2] + 1.0 - LEVELS[0], wall, [], LEVELS[0], 0.25)
	kit.wall(Vector2(HALF.x, -RAMP_Z), Vector2(HALF.x, RAMP_Z), LEVELS[2] + 1.0 - LEVELS[0], wall, [], LEVELS[0], 0.3)
	# Parapets: every open edge of both upper decks; the ground floor is open to the street in front
	# and has a low wall elsewhere with a pedestrian gap at the back.
	for level: int in [1, 2]:
		var y: float = LEVELS[level]
		kit.parapet(Vector3(-HALF.x, y, HALF.y - 0.2), Vector3(HALF.x, y, HALF.y - 0.2), 1.0, 0.4, wall)
		kit.parapet(Vector3(-HALF.x, y, -HALF.y + 0.2), Vector3(HALF.x, y, -HALF.y + 0.2), 1.0, 0.4, wall)
		for side: float in [-1.0, 1.0]:
			kit.parapet(Vector3(side * (HALF.x - 0.2), y, -HALF.y), Vector3(side * (HALF.x - 0.2), y, -RAMP_Z), 1.0, 0.4, wall)
			kit.parapet(Vector3(side * (HALF.x - 0.2), y, RAMP_Z), Vector3(side * (HALF.x - 0.2), y, HALF.y), 1.0, 0.4, wall)
	kit.parapet(Vector3(-HALF.x, LEVELS[0], -HALF.y + 0.2), Vector3(-1.0, LEVELS[0], -HALF.y + 0.2), 1.0, 0.4, wall)
	kit.parapet(Vector3(1.0, LEVELS[0], -HALF.y + 0.2), Vector3(HALF.x, LEVELS[0], -HALF.y + 0.2), 1.0, 0.4, wall)
	for side: float in [-1.0, 1.0]:
		kit.parapet(Vector3(side * (HALF.x - 0.2), LEVELS[0], -HALF.y), Vector3(side * (HALF.x - 0.2), LEVELS[0], -RAMP_Z), 1.0, 0.4, wall)
		kit.parapet(Vector3(side * (HALF.x - 0.2), LEVELS[0], RAMP_Z), Vector3(side * (HALF.x - 0.2), LEVELS[0], HALF.y), 1.0, 0.4, wall)
	# Columns carrying the decks (cover), clear of every aisle.
	for at: Vector2 in [Vector2(0, RAMP_Z), Vector2(0, -RAMP_Z), Vector2(-8, HALF.y - 0.3), Vector2(8, HALF.y - 0.3), Vector2(-8, -HALF.y + 0.3), Vector2(8, -HALF.y + 0.3)]:
		kit.box(Vector3(at.x, (LEVELS[0] + LEVELS[2]) * 0.5, at.y), Vector3(0.6, LEVELS[2] - LEVELS[0], 0.6), concrete, true)
	# Stairs and the rails round their holes.
	var steel: Material = kit.mat(Color(0.3, 0.32, 0.34), "metal", 0.6)
	kit.stairs_u(STAIR_A, Vector3.BACK, LEVELS[1] - LEVELS[0], 1.2, 0.2, steel)
	kit.stairs_u(STAIR_B, Vector3.BACK, LEVELS[2] - LEVELS[1], 1.2, 0.2, steel)
	_hole_rails(kit, HOLE_A, LEVELS[1], 1.2)
	_hole_rails(kit, HOLE_B, LEVELS[2], 1.2)
	_street_front(kit, concrete)
	for level: int in range(3):
		_deck_dressing(kit, level)
	kit.world._landmark("CENTRAL PARKING", Vector3(0, 0, HALF.y + 5.0))
	kit.node.set_meta("walk_in", true)
	kit.node.set_meta("interior_half", HALF)
	kit.node.set_meta("routes", {"street_to_roof": ROUTE})
	_props(kit)
	kit.finish_props()
	kit.finish()


## Railings on three sides of a stair hole plus the part of the fourth that isn't the arrival.
static func _hole_rails(kit: BuildingKit, hole: Rect2, y: float, flight: float) -> void:
	kit.railing(Vector3(hole.position.x, y, hole.position.y), Vector3(hole.position.x, y, hole.end.y))
	kit.railing(Vector3(hole.position.x, y, hole.end.y), Vector3(hole.end.x, y, hole.end.y))
	kit.railing(Vector3(hole.end.x, y, hole.position.y), Vector3(hole.end.x, y, hole.end.y))
	kit.railing(Vector3(hole.position.x, y, hole.position.y), Vector3(hole.end.x - flight - 0.2, y, hole.position.y))


static func _street_front(kit: BuildingKit, concrete: Material) -> void:
	var yellow: Material = kit.mat(Color(0.9, 0.75, 0.15), "", 0.7)
	var black: Material = kit.mat(Color(0.08, 0.08, 0.08), "", 0.7)
	kit.box(Vector3(0, 2.75, HALF.y + 0.25), Vector3(HALF.x * 2, 0.9, 0.3), concrete)
	kit.neon_sign("CENTRAL  PARKING", Vector3(-3.0, 2.75, HALF.y + 0.45), 0.0, Color(0.4, 0.8, 1.0), 56)
	kit.sign_label("MONTHLY $45   DAILY $6   LOST TICKET $20", Vector3(8.5, 2.75, HALF.y + 0.42), 18, Color(0.92, 0.9, 0.82))
	# Ticket booth on the island between entry and exit, and a barrier arm left raised.
	var booth: Vector3 = Vector3(0.0, LEVELS[0], 11.5)
	kit.box(booth + Vector3(0, 0.1, 0), Vector3(2.4, 0.2, 3.6), concrete, true)
	kit.box(booth + Vector3(0, 1.3, 0), Vector3(1.6, 2.2, 1.8), kit.mat(Color(0.75, 0.72, 0.62), "panel"), true)
	kit.box(booth + Vector3(0, 2.5, 0), Vector3(1.9, 0.18, 2.1), kit.mat(Color(0.3, 0.3, 0.32), "metal"))
	for side: float in [-1.0, 1.0]:
		kit.box(booth + Vector3(side * 0.81, 1.5, 0), Vector3(0.02, 0.8, 1.2), kit.glass_material())
		kit.box(booth + Vector3(side * 1.05, 0.7, 1.3), Vector3(0.3, 1.0, 0.3), yellow, true)
	var arm_pivot: Vector3 = booth + Vector3(-1.05, 1.25, 1.3)
	for index: int in range(6):
		var t: float = (index + 0.5) / 6.0
		kit.box(arm_pivot + Vector3(-0.35 * t * 6.0 * 0.2, 3.2 * t, 0), Vector3(0.1, 0.55, 0.1), yellow if index % 2 == 0 else black)
	kit.sign_label("PAY AT BOOTH", booth + Vector3(0, 1.9, 0.92), 18, Color(0.15, 0.15, 0.15))
	# Height bar over the entry, hung on chains from the deck edge (no collision: it clears cars).
	kit.box(Vector3(-7.5, 2.1, HALF.y - 0.6), Vector3(9.0, 0.18, 0.18), yellow)
	kit.sign_label("CLEARANCE 7'2\"", Vector3(-7.5, 2.1, HALF.y - 0.5), 16, Color(0.1, 0.1, 0.1))
	for x: float in [-11.5, -3.5]:
		kit.box(Vector3(x, 2.5, HALF.y - 0.6), Vector3(0.04, 0.62, 0.04), kit.mat(Color(0.3, 0.3, 0.3), "metal"))


## Painted bays, level numbers on the columns, tube lights under the deck above, oil stains and a
## few dust-sheeted cars (static, solid: cover and set dressing, not drivable).
static func _deck_dressing(kit: BuildingKit, level: int) -> void:
	var y: float = LEVELS[level]
	var paint: Material = kit.mat(Color(0.85, 0.83, 0.75), "", 0.9)
	var stain: Material = kit.mat(Color(0.2, 0.2, 0.19), "", 0.4)
	for row: float in [-1.0, 1.0]:
		for index: int in range(7):
			var x: float = -7.6 + index * 2.53
			kit.box(Vector3(x, y + 0.006, row * 4.6), Vector3(0.1, 0.012, 4.8), paint)
	kit.box(Vector3(0, y + 0.006, 0), Vector3(15.2, 0.012, 0.1), paint)
	for arrow: Vector3 in [Vector3(-11.5, 0, 10.5), Vector3(0, 0, -10.5), Vector3(11.5, 0, -10.5)]:
		kit.box(Vector3(arrow.x, y + 0.006, arrow.z), Vector3(0.3, 0.012, 1.8), paint)
	var tag: String = ["G", "2", "R"][level]
	for at: Vector2 in [Vector2(0, RAMP_Z), Vector2(0, -RAMP_Z)]:
		for face: float in [-1.0, 1.0]:
			kit.box(Vector3(at.x, y + 1.9, at.y + face * 0.31), Vector3(0.58, 0.8, 0.02), kit.mat(Color(0.2, 0.45, 0.75)))
			kit.sign_label(tag, Vector3(at.x, y + 1.9, at.y + face * 0.33), 64, Color(0.95, 0.95, 0.9), 0.0 if face > 0.0 else PI)
	if level < 2:
		var tube: Material = kit.glow(Color(0.85, 0.95, 1.0), 1.4)
		for x: float in [-11.5, -4.0, 4.0, 11.5]:
			for z: float in [-10.5, 0.0, 10.5]:
				if level == 0 and absf(x) > 10.0 and absf(z) < 7.0:
					continue
				kit.box(Vector3(x, LEVELS[level + 1] - 0.36, z), Vector3(0.12, 0.08, 1.6), tube)
	else:
		for at: Vector2 in [Vector2(-8, 10.5), Vector2(8, -10.5)]:
			kit.box(Vector3(at.x, y + 2.5, at.y), Vector3(0.18, 5.0, 0.18), kit.mat(Color(0.25, 0.26, 0.27), "metal"), true)
			kit.box(Vector3(at.x, y + 5.0, at.y), Vector3(0.9, 0.2, 0.35), kit.glow(Color(1.0, 0.85, 0.6), 1.2))
	for index: int in range(5):
		var at: Vector3 = Vector3(-6.3 + ((index * 5 + level * 3) % 7) * 2.53, y + 0.004, (2.6 if (index + level) % 2 == 0 else -2.6))
		kit.box(at, Vector3(0.9, 0.008, 1.3), stain)
	var sheet: Array[Color] = [Color(0.5, 0.5, 0.46), Color(0.34, 0.38, 0.42), Color(0.55, 0.47, 0.36)]
	var bays: Array = [[Vector2(-6.3, 2.4), Vector2(5.1, -2.4)], [Vector2(-1.3, 2.4), Vector2(6.4, 2.4)], [Vector2(-5.0, -2.4)]][level]
	for bay: Vector2 in bays:
		var cover: Material = kit.mat(sheet[int(absf(bay.x)) % sheet.size()], "", 0.95)
		kit.box(Vector3(bay.x, y + 0.55, bay.y), Vector3(1.8, 0.8, 4.3), cover, true)
		kit.box(Vector3(bay.x, y + 1.2, bay.y + 0.3), Vector3(1.6, 0.5, 2.2), cover, true)
		kit.box(Vector3(bay.x, y + 0.16, bay.y), Vector3(1.9, 0.3, 4.4), cover)


## Garage dressing (docs/INTERIOR_PROPS.md): a ticket dispenser at the entry, a lost-and-found box
## on the booth island, oil drums and a pail of absorbent in the front-east corner. Collision-free,
## hidden in potato mode.
static func _props(kit: BuildingKit) -> void:
	kit.begin_props()
	var booth: Vector3 = Vector3(0.0, LEVELS[0], 11.5)
	var yellow: Material = kit.mat(Color(0.9, 0.75, 0.15), "", 0.7)
	var grey: Material = kit.mat(Color(0.3, 0.31, 0.33), "", 0.5)
	kit.prop(booth + Vector3(-0.6, 0.75, -1.35), Vector3(0.36, 1.1, 0.3), yellow)
	kit.prop(booth + Vector3(-0.6, 1.05, -1.19), Vector3(0.22, 0.14, 0.02), kit.glow(Color(1.0, 0.3, 0.2), 0.6))
	kit.prop(booth + Vector3(-0.6, 0.85, -1.19), Vector3(0.12, 0.03, 0.03), grey)
	kit.prop(booth + Vector3(-0.6, 0.6, -1.19), Vector3(0.2, 0.08, 0.02), grey)
	kit.prop_carton(booth + Vector3(0.45, 0.4, -1.3), Vector3(0.5, 0.4, 0.4), Color(0.55, 0.42, 0.28), Color(0.62, 0.48, 0.32))
	kit.prop(booth + Vector3(0.4, 0.66, -1.3), Vector3(0.2, 0.12, 0.12), kit.mat(Color(0.1, 0.1, 0.12), "", 0.8))
	kit.prop(booth + Vector3(0.55, 0.64, -1.25), Vector3(0.14, 0.08, 0.2), kit.mat(Color(0.5, 0.15, 0.12), "", 0.8))
	kit.sign_label("LOST & FOUND", booth + Vector3(0.45, 0.45, -1.09), 12, Color(0.1, 0.1, 0.1))
	var drums: Array[Material] = [kit.mat(Color(0.15, 0.3, 0.55), "metal", 0.6), kit.mat(Color(0.6, 0.15, 0.1), "metal", 0.6)]
	for index: int in range(3):
		var at: Vector3 = Vector3(HALF.x - 0.75 - (index % 2) * 0.65, LEVELS[0], HALF.y - 1.0 - float(index / 2) * 0.65)
		kit.prop(at + Vector3(0, 0.44, 0), Vector3(0.58, 0.88, 0.58), drums[index % 2], 0.4 * index)
		kit.prop(at + Vector3(0, 0.3, 0), Vector3(0.6, 0.04, 0.6), grey, 0.4 * index)
		kit.prop(at + Vector3(0, 0.62, 0), Vector3(0.6, 0.04, 0.6), grey, 0.4 * index)
	kit.prop(Vector3(HALF.x - 1.9, LEVELS[0] + 0.2, HALF.y - 0.9), Vector3(0.35, 0.4, 0.35), kit.mat(Color(0.85, 0.8, 0.6), "", 0.8))
	kit.end_props()
