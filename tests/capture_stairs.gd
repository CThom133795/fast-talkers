extends SceneTree
## Review captures of the Halcyon Trust stairwells, roof terrace and plant room (copy of capture_interiors.gd with other views). Views are in each plot's local
## frame (+Z = out of the front door) and converted with the plot node's transform, so they follow
## the building if its plot moves. Run windowed (not headless); writes work/captures/interior_*.png.
##   godot --path . --script res://tests/capture_interiors.gd [-- only=<prefix>]
const WorldScript = preload("res://scripts/world.gd")

const VIEWS: Array = [
	["roof_stair_office", "highrise", Vector3(-8, 6.4, -7), Vector3(-14.25, 6.5, -3)],
	["roof_stair_up", "highrise", Vector3(-14.25, 5.8, -7.5), Vector3(-14.25, 8.0, -1)],
	["roof_deck", "highrise", Vector3(-8, 11.0, 10), Vector3(-13, 8.6, -3)],
	["roof_deck_door", "highrise", Vector3(-13, 9.9, 2.5), Vector3(-6.2, 9.3, -1.5)],
	["plant_room", "highrise", Vector3(-5.4, 9.9, -1.5), Vector3(-2.5, 9.2, -2.0)],
	["tower_west_outside", "highrise", Vector3(-42, 16, 6), Vector3(-10, 9, 0)],
	["tower_west_far", "highrise", Vector3(-60, 20, 12), Vector3(0, 12, 0)],
	["stairA_lobby", "highrise", Vector3(-8, 1.7, -3), Vector3(-12.85, 1.5, -10)],
	["stairA_top", "highrise", Vector3(-9, 6.4, -5), Vector3(-13.5, 4.5, -11)],
]

var world: Node3D
var camera: Camera3D
var folder: String
var only: String = ""
## compare=1: after each capture, also print the draw calls with potato mode on (props hidden).
var compare: bool = false


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("only="):
			only = arg.substr(5)
		if arg == "compare=1":
			compare = true
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
		root.get_viewport().get_texture().get_image().save_png("%s/stairs_%s.png" % [folder, label])
		print("CAPTURED ", label, " draw calls ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if compare:
			world.set_potato_mode(true)
			await _frames(6)
			await RenderingServer.frame_post_draw
			print("  potato (props hidden) ", label, " draw calls ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			world.set_potato_mode(false)
	world.queue_free()
	await _frames(5)
	quit(0)
