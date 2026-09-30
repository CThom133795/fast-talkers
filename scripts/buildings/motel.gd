extends RefCounted
## Plot "motel": SEA BREEZE MOTEL (M2: two storeys, exterior walkway, 8-10 rooms, office, drained pool).
## M1 placeholder: a plain solid shell with a sign, so the city looks right before M2 replaces
## this file with the real building (see docs/tasks/MAP_0_6_PLAN.md). Keep `static func build`.

const BuildingKit = preload("res://scripts/buildings/building_kit.gd")


static func build(world: Node3D, plot: Dictionary) -> void:
	var kit: BuildingKit = BuildingKit.new(world, "Motel", plot)
	kit.stub_shell(7.0, Color(0.9, 0.82, 0.66), "stucco", "SEA BREEZE  MOTEL", Color(1.0, 0.8, 0.3), true, 0.5)
	kit.finish()
