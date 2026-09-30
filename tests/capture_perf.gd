extends SceneTree
## Windowed performance sample: draw calls, objects, primitives and frame time at several
## views (vsync off). Run (not headless): godot --path . --script res://tests/capture_perf.gd

const VIEWS: Array = [
	["midtown", Vector3(0, 0.2, -18), Vector3(0, 3, -45)],
	["midtown_north_long", Vector3(0, 0.2, 60), Vector3(0, 2, -100)],
	["harbor", Vector3(0, 0.2, -140), Vector3(-40, 6, -185)],
	["strip_beach", Vector3(60, 0.2, 200), Vector3(110, 3, 250)],
	["lantern_row", Vector3(-150, 0.2, -50), Vector3(-192, 6, -22)],
	["exchange_interior", Vector3(-15, 0.2, 15), Vector3(-30, 1.8, 15)],
	["aerial", Vector3(-60, 90, 170), Vector3(10, 0, -20)],
]

var game: Variant


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for step: int in range(count):
		await process_frame


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.pause_on_focus_loss = false
	game.settings_path = "user://perf_settings.cfg"
	root.add_child(game)
	await _frames(30)
	game._start_free_roam()
	game.player.invulnerable = true
	for view: Array in VIEWS:
		var from: Vector3 = view[1]
		var target: Vector3 = view[2]
		game.player.global_position = from
		var direction: Vector3 = target - (from + Vector3(0, 1.62, 0))
		game.player.face(atan2(-direction.x, -direction.z))
		game.player._pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
		await _frames(30)
		var start: int = Time.get_ticks_usec()
		await _frames(60)
		var frame_ms: float = float(Time.get_ticks_usec() - start) / 60.0 / 1000.0
		print("PERF %-20s draw calls %5d  objects %5d  primitives %8d  frame %.2f ms (%d fps)" % [view[0], Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), frame_ms, int(1000.0 / maxf(frame_ms, 0.01))])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://perf_settings.cfg"))
	game.queue_free()
	for settle: int in range(10):
		await process_frame
	quit(0)
