extends RefCounted
## Plot "hotel": HOTEL MERIDIAN (M2: 6-8 storeys, lobby, bar, lift, stairwell, guest floors, rooftop pool).
## M1 placeholder: a plain solid shell with a sign, so the city looks right before M2 replaces
## this file with the real building (see docs/tasks/MAP_0_6_PLAN.md). Keep `static func build`.

const BuildingKit = preload("res://scripts/buildings/building_kit.gd")


static func build(world: Node3D, plot: Dictionary) -> void:
	var kit: BuildingKit = BuildingKit.new(world, "Hotel", plot)
	kit.stub_shell(25.0, Color(0.62, 0.5, 0.4), "stucco", "HOTEL  MERIDIAN", Color(1.0, 0.85, 0.55), true, 0.5)
	kit.finish()
