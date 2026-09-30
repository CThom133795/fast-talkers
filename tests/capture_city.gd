extends SceneTree
## Windowed render review of Port Halcyon (0.5 layout): title lineup, street views of every
## district and plaza, two aerials, every walk-in interior seen from its doorway, and the
## full map. Output: ../../work/captures/city_*.png
## Run (not headless): godot --path . --script res://tests/capture_city.gd
## Pass `-- only=<prefix>` to capture just the views whose label starts with <prefix>.

const VIEWS: Array = [
	["midtown_exchange", Vector3(0, 0.2, -18), Vector3(0, 3, -45)],
	["midtown_shopfronts", Vector3(4, 0.2, 40), Vector3(-12, 2.5, 62)],
	["midtown_ring_east", Vector3(84, 0.2, 30), Vector3(66, 3, 4)],
	["canal_walk", Vector3(-6, 0.2, -13), Vector3(-60, 2, -16)],
	["eastbank_square", Vector3(90, 0.2, -94), Vector3(62, 3, -62)],
	["lantern_row", Vector3(-150, 0.2, -50), Vector3(-192, 6, -22)],
	["lantern_alley", Vector3(-150, 0.2, -12), Vector3(-148, 3, -30)],
	["west_bank_plaza", Vector3(-140, 0.2, 26), Vector3(-176, 3, 20)],
	["west_slip", Vector3(-186, 0.2, 38), Vector3(-240, 1, 32)],
	["canal_basin", Vector3(-140, 0.2, -146), Vector3(-168, 1, -178)],
	["canal_market", Vector3(-120, 0.2, -110), Vector3(-150, 2, -130)],
	["canal_bridge", Vector3(-196, 0.2, -212), Vector3(-160, 1, -218)],
	["harbor", Vector3(0, 0.2, -140), Vector3(40, 6, -180)],
	["solana_heights", Vector3(150, 0.2, -104), Vector3(167, 3, -121)],
	["fountain_square", Vector3(122, 0.2, -30), Vector3(150, 3, -56)],
	["eastside_park", Vector3(214, 0.2, -58), Vector3(160, 3, -58)],
	["kingsway", Vector3(160, 0.2, 20), Vector3(178, 8, 2)],
	["kingsway_waterfront", Vector3(214, 0.2, 40), Vector3(250, 3, 60)],
	["morris_park", Vector3(-60, 0.2, 100), Vector3(-80, 4, 114)],
	["piazza", Vector3(-30, 0.2, 164), Vector3(-43, 2, 180)],
	["union_station", Vector3(-118, 0.2, 170), Vector3(-141, 8, 184)],
	["rail_yard", Vector3(-186, 0.2, 90), Vector3(-216, 2, 101)],
	["the_strip", Vector3(60, 0.2, 100), Vector3(86, 5, 113)],
	["halcyon_beach", Vector3(60, 0.2, 230), Vector3(110, 3, 250)],
	["halcyon_pier", Vector3(80, 1.5, 238), Vector3(95, 10, 280)],
	["quay_rail", Vector3(-10, 0.2, -196), Vector3(-10, 1.2, -206)],
	["aerial_west", Vector3(-40, 110, 150), Vector3(-150, 0, -60)],
	["aerial_east", Vector3(40, 110, -170), Vector3(150, 0, 60)],
]

var game: Variant
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
	root.get_viewport().get_texture().get_image().save_png("%s/city_%s.png" % [folder, label])
	print("CAPTURED ", label)


func _look(from: Vector3, target: Vector3) -> void:
	game.player.global_position = from
	var direction: Vector3 = target - (from + Vector3(0, 1.62, 0))
	game.player.face(atan2(-direction.x, -direction.z))
	game.player._pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())


func _run() -> void:
	folder = ProjectSettings.globalize_path("res://../../work/captures")
	DirAccess.make_dir_recursive_absolute(folder)
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.pause_on_focus_loss = false
	game.settings_path = "user://capture_settings.cfg"
	root.add_child(game)
	await _frames(60)
	if only.is_empty():
		await _shot("00_title")
	game._start_free_roam()
	game.player.invulnerable = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for view: Array in VIEWS:
		if not str(view[0]).begins_with(only):
			continue
		_look(view[1], view[2])
		await _frames(20)
		await _shot(view[0])
	# Every walk-in business from just inside its door.
	for door: Dictionary in game.world.interactable_doors:
		var label: String = "interior_" + str(door["kind"])
		if not label.begins_with(only):
			continue
		var inside: Vector3 = door["inside"]
		var inward: Vector3 = (inside - (door["outside"] as Vector3)).normalized()
		_look(inside - inward * 0.6 + Vector3(0, 0.1, 0), inside + inward * 12.0 + Vector3(0, 1.2, 0))
		await _frames(15)
		await _shot(label)
	if only.is_empty():
		game.map_open = true
		await _frames(5)
		await _shot("zz_full_map")
		game.map_open = false
		game.world.set_dusk(false)
		_look(Vector3(0, 0.2, -18), Vector3(0, 3, -45))
		await _frames(10)
		await _shot("zz_day_midtown")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture_settings.cfg"))
	game.queue_free()
	for settle: int in range(10):
		await process_frame
	quit(0)
