extends SceneTree
## Windowed render review of the 0.6 layout (needs a GPU; not for headless runs): an aerial of the
## whole map, one street view per new district, every crew HQ doorstep and the gun store in each
## mode. Output: res://work/captures/map06_*.png (git-ignored).
## Run: godot --path . --script res://tests/capture_map06.gd
## Pass `-- only=<prefix>` to capture just the views whose label starts with <prefix>.

const WorldScript = preload("res://scripts/world.gd")
const ArmoryScript = preload("res://scripts/armory.gd")

## [label, camera position, look-at point]
const VIEWS: Array = [
	["uptown", Vector3(140, 1.7, -112), Vector3(130, 24, -176)],
	["uptown_hotel", Vector3(190, 1.7, -140), Vector3(175, 10, -176)],
	["motor_mile", Vector3(104, 1.7, 45), Vector3(185, 4, 12)],
	["motor_mile_burger", Vector3(140, 1.7, 30), Vector3(120, 3, 62)],
	["nightlife", Vector3(56, 1.7, 212), Vector3(118, 6, 244)],
	["nightlife_avenue", Vector3(72, 1.7, 110), Vector3(72, 8, 260)],
	["west_end", Vector3(-150, 1.7, -98), Vector3(-150, 8, -60)],
	["old_town", Vector3(-100, 1.7, 96), Vector3(-100, 6, 160)],
	["slip_side", Vector3(-200, 1.7, 66), Vector3(-330, 5, 90)],
	["west_slip", Vector3(-186, 1.7, 40), Vector3(-330, 1, 35)],
	["old_wharf", Vector3(-250, 1.7, -196), Vector3(-350, 6, -215)],
	["south_docks", Vector3(230, 1.7, 302), Vector3(340, 12, 320)],
	["east_shore", Vector3(240, 1.7, 40), Vector3(300, 3, 70)],
	["gunstore_front", Vector3(226, 1.7, -50), Vector3(255, 2.5, -66)],
	["gunstore_lot", Vector3(236, 1.7, -84), Vector3(262, 3, -60)],
	["gunstore_yard", Vector3(296, 1.7, -78), Vector3(340, 1.5, -50)],
	["gunstore_shop", Vector3(247.5, 1.7, -66), Vector3(268, 1.8, -66)],
	["gunstore_range", Vector3(263, 1.7, -60), Vector3(280, 1.4, -66)],
	["lantern_hq", Vector3(-270, 1.7, -60), Vector3(-312, 6, -36)],
	["solana_hq", Vector3(255, 1.7, -130), Vector3(296, 4, -145)],
	["kingsway_hq", Vector3(228, 1.7, 130), Vector3(255, 8, 152)],
	["morris_hq", Vector3(-80, 1.7, 200), Vector3(-92, 4, 226)],
	["strip", Vector3(60, 1.7, 270), Vector3(110, 5, 330)],
	["beach", Vector3(90, 1.7, 388), Vector3(120, 3, 430)],
	["aerial_north_east", Vector3(-30, 240, -320), Vector3(180, 0, -60)],
	["aerial_south_west", Vector3(120, 240, 470), Vector3(-120, 0, 160)],
	["aerial_full", Vector3(0, 900, 100), Vector3(0, 0, 99)],
]

var world: Node3D
var armory: Node3D
var camera: Camera3D
var folder: String
var only: String = ""


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("only="):
			only = arg.substr(5)
	call_deferred("_run")


func _frames(count: int) -> void:
	for step: int in range(count):
		await process_frame


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/map06_%s.png" % [folder, label])
	print("CAPTURED ", label)


func _run() -> void:
	folder = ProjectSettings.globalize_path("res://work/captures")
	DirAccess.make_dir_recursive_absolute(folder)
	world = WorldScript.new()
	root.add_child(world)
	armory = ArmoryScript.new()
	root.add_child(armory)
	camera = Camera3D.new()
	camera.far = 3000.0
	camera.fov = 70.0
	root.add_child(camera)
	camera.current = true
	await _frames(30)
	for view: Array in VIEWS:
		var label: String = str(view[0])
		if not label.begins_with(only):
			continue
		var aerial: bool = label.begins_with("aerial")
		world.environment.fog_enabled = not aerial
		camera.fov = 45.0 if label == "aerial_full" else (60.0 if aerial else 70.0)
		camera.global_position = view[1]
		camera.look_at(view[2], Vector3.UP if label != "aerial_full" else Vector3(0, 0, -1))
		await _frames(12)
		await _shot(label)
	if only.is_empty() or "gunstore".begins_with(only) or only.begins_with("gunstore"):
		# The same yard in a contract round: dressing hidden, range doors locked.
		world.set_mode("contract")
		armory.set_mode("contract")
		await _frames(90)
		for view: Array in VIEWS:
			var label: String = str(view[0])
			if label == "gunstore_yard" or label == "gunstore_front":
				camera.global_position = view[1]
				camera.look_at(view[2], Vector3.UP)
				await _frames(10)
				await _shot(label + "_contract")
	world.queue_free()
	armory.queue_free()
	for settle: int in range(10):
		await process_frame
	quit(0)
