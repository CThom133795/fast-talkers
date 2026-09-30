extends SceneTree
## Windowed review captures of the 0.8 fill pass (needs a GPU; not for headless runs). Writes
## work/captures/fill_<label>.png. Run: godot --path . --script res://tests/capture_fill.gd
## `-- only=<prefix>` limits the views; `day=1` uses daylight, `size=WxH` sets the window size.
const WorldScript = preload("res://scripts/world.gd")
## [label, camera position, look-at point]
const VIEWS: Array = [
	["halcyon_south", Vector3(4, 1.7, 110), Vector3(2, 3, 250)],
	["union_west", Vector3(-150, 1.7, 40), Vector3(-60, 3, 35)],
	["old_town_street", Vector3(-100, 1.7, 100), Vector3(-100, 6, 190)],
	["east_rim", Vector3(330, 1.7, 60), Vector3(380, 4, 120)],
	["west_rim", Vector3(-330, 1.7, 100), Vector3(-380, 4, 200)],
	["south_rim", Vector3(-100, 1.7, 300), Vector3(-160, 4, 360)],
	["wharf", Vector3(-300, 1.7, -215), Vector3(-350, 6, -175)],
	["docks", Vector3(230, 1.7, 302), Vector3(340, 12, 320)],
	["aerial_nw", Vector3(-200, 220, -160), Vector3(-200, 0, -60)],
	["aerial_e", Vector3(400, 200, 150), Vector3(300, 0, 80)],
	["aerial_s", Vector3(0, 260, 470), Vector3(0, 0, 250)],
]
var world: Node3D
var camera: Camera3D
var folder: String
var only: String = ""
var day: bool = true


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("only="):
			only = arg.substr(5)
		elif arg == "dusk=1":
			day = false
	call_deferred("_run")


func _frames(count: int) -> void:
	for step: int in range(count):
		await process_frame


func _run() -> void:
	folder = ProjectSettings.globalize_path("res://work/captures")
	DirAccess.make_dir_recursive_absolute(folder)
	world = WorldScript.new()
	root.add_child(world)
	camera = Camera3D.new()
	camera.far = 3000.0
	camera.fov = 70.0
	root.add_child(camera)
	camera.current = true
	await _frames(20)
	world.set_dusk(not day)
	for view: Array in VIEWS:
		var label: String = str(view[0])
		if not label.begins_with(only):
			continue
		var aerial: bool = label.begins_with("aerial")
		world.environment.fog_enabled = not aerial
		camera.global_position = view[1]
		camera.look_at(view[2], Vector3.UP)
		await _frames(12)
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/fill_%s.png" % [folder, label])
		print("CAPTURED ", label)
	world.queue_free()
	for settle: int in range(10):
		await process_frame
	quit(0)
