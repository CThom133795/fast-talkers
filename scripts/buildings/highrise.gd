extends RefCounted
## Plot "highrise": HALCYON TRUST high-rise (M2: 16-20 storeys, two lifts and two stairwells, three fitted floors).
## M1 placeholder: a plain solid shell with a sign, so the city looks right before M2 replaces
## this file with the real building (see docs/tasks/MAP_0_6_PLAN.md). Keep `static func build`.

const BuildingKit = preload("res://scripts/buildings/building_kit.gd")


static func build(world: Node3D, plot: Dictionary) -> void:
	var kit: BuildingKit = BuildingKit.new(world, "Highrise", plot)
	kit.stub_shell(68.0, Color(0.42, 0.5, 0.57), "panel", "HALCYON  TRUST", Color(0.7, 0.9, 1.0), true, 0.5)
	kit.finish()
