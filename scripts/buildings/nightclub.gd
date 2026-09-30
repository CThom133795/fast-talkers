extends RefCounted
## Plot "nightclub": CLUB VOLTAGE (M2: queue rope, dance floor with light panels, DJ booth, bar, VIP mezzanine).
## M1 placeholder: a plain solid shell with a sign, so the city looks right before M2 replaces
## this file with the real building (see docs/tasks/MAP_0_6_PLAN.md). Keep `static func build`.

const BuildingKit = preload("res://scripts/buildings/building_kit.gd")


static func build(world: Node3D, plot: Dictionary) -> void:
	var kit: BuildingKit = BuildingKit.new(world, "Nightclub", plot)
	kit.stub_shell(9.0, Color(0.13, 0.11, 0.17), "panel", "CLUB  VOLTAGE", Color(0.4, 0.9, 1.0), false, 0.0)
	kit.finish()
