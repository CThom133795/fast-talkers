extends RefCounted
## Plot "burger": the burger joint (M2: diner counter, booths, kitchen, drive-thru lane and window, pole sign).
## M1 placeholder: a plain solid shell with a sign, so the city looks right before M2 replaces
## this file with the real building (see docs/tasks/MAP_0_6_PLAN.md). Keep `static func build`.

const BuildingKit = preload("res://scripts/buildings/building_kit.gd")


static func build(world: Node3D, plot: Dictionary) -> void:
	var kit: BuildingKit = BuildingKit.new(world, "Burger", plot)
	kit.stub_shell(5.5, Color(0.86, 0.72, 0.5), "stucco", "BIG BOY  BURGERS", Color(1.0, 0.4, 0.3), true, 0.6)
	kit.finish()
