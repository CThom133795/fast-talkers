extends RefCounted
## Plot "garage": the 4-level parking garage (M2: drivable ramps, pedestrian stair core, parked cars per level).
## M1 placeholder: a plain solid shell with a sign, so the city looks right before M2 replaces
## this file with the real building (see docs/tasks/MAP_0_6_PLAN.md). Keep `static func build`.

const BuildingKit = preload("res://scripts/buildings/building_kit.gd")


static func build(world: Node3D, plot: Dictionary) -> void:
	var kit: BuildingKit = BuildingKit.new(world, "Garage", plot)
	kit.stub_shell(13.6, Color(0.55, 0.55, 0.52), "panel", "PARKING  GARAGE", Color(0.4, 0.8, 1.0), false, 0.0)
	kit.finish()
