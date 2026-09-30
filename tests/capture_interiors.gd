extends SceneTree
## Review captures of the landmark interiors (club, strip club). Views are in each plot's local
## frame (+Z = out of the front door) and converted with the plot node's transform, so they follow
## the building if its plot moves. Run windowed (not headless); writes work/captures/interior_*.png.
##   godot --path . --script res://tests/capture_interiors.gd [-- only=<prefix>]
const WorldScript = preload("res://scripts/world.gd")

const VIEWS: Array = [
	["club_street", "nightclub", Vector3(-4, 1.7, 30), Vector3(-2, 3.5, 18)],
	["club_lobby", "nightclub", Vector3(-4, 1.7, 16.5), Vector3(8, 1.2, 13)],
	["club_floor", "nightclub", Vector3(-4, 1.7, 10.5), Vector3(-1.5, 1.2, -9)],
	["club_bar", "nightclub", Vector3(-3, 1.7, 7), Vector3(-15, 1.4, -1)],
	["club_vip", "nightclub", Vector3(11, 5.3, -8.5), Vector3(-4, 1.5, 2)],
	["club_mezz_stair", "nightclub", Vector3(8, 1.7, 9), Vector3(14.9, 3.2, 4)],
	["club_back", "nightclub", Vector3(-10, 1.7, -11), Vector3(-2, 1.0, -17)],
	["club_office", "nightclub", Vector3(5.5, 1.7, -12), Vector3(14, 1.0, -16)],
	["velvet_street", "stripclub", Vector3(0, 1.7, 28), Vector3(0, 3.5, 16)],
	["velvet_room", "stripclub", Vector3(8, 1.7, 9.5), Vector3(-2, 1.4, -4)],
	["velvet_stage", "stripclub", Vector3(-9, 1.7, 6), Vector3(-2, 1.6, -4)],
	["velvet_bar", "stripclub", Vector3(-3, 1.7, 2), Vector3(-10, 1.2, 10)],
	["velvet_vestibule", "stripclub", Vector3(-2, 1.7, 15), Vector3(4, 1.4, 13)],
	["velvet_dressing", "stripclub", Vector3(-3, 1.7, -10.3), Vector3(-10, 1.5, -15.5)],
	["velvet_office", "stripclub", Vector3(5, 1.7, -10.5), Vector3(13, 1.0, -15)],
]

var world: Node3D
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


func _run() -> void:
	folder = ProjectSettings.globalize_path("res://work/captures")
	DirAccess.make_dir_recursive_absolute(folder)
	world = WorldScript.new()
	root.add_child(world)
	camera = Camera3D.new()
	camera.far = 1500.0
	camera.fov = 70.0
	root.add_child(camera)
	camera.current = true
	await _frames(30)
	for view: Array in VIEWS:
		var label: String = str(view[0])
		if not label.begins_with(only):
			continue
		var node: Node3D = world.plot_nodes[str(view[1])]
		camera.global_position = node.global_transform * (view[2] as Vector3)
		camera.look_at(node.global_transform * (view[3] as Vector3), Vector3.UP)
		await _frames(12)
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/interior_%s.png" % [folder, label])
		print("CAPTURED ", label, " draw calls ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	world.queue_free()
	await _frames(5)
	quit(0)
