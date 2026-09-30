extends RefCounted
## Plot "stripclub": THE VELVET ROOM (M2: tasteful and non-explicit: stage, booths, bar, back office, no people).
## M1 placeholder: a plain solid shell with a sign, so the city looks right before M2 replaces
## this file with the real building (see docs/tasks/MAP_0_6_PLAN.md). Keep `static func build`.

const BuildingKit = preload("res://scripts/buildings/building_kit.gd")


static func build(world: Node3D, plot: Dictionary) -> void:
	var kit: BuildingKit = BuildingKit.new(world, "Stripclub", plot)
	kit.stub_shell(7.0, Color(0.2, 0.08, 0.1), "panel", "THE  VELVET  ROOM", Color(1.0, 0.3, 0.5), false, 0.0)
	kit.finish()
