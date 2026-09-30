extends SceneTree
## Windowed render review: drives the real game through each system and saves PNGs.
## Run (not headless): godot --path . --script res://tests/capture.gd
## Output: ../../work/captures/*.png. Takes about 40 seconds.

var game: Variant
var folder: String
var index: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for step: int in range(count):
		await process_frame


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	index += 1
	var path: String = "%s/%02d_%s.png" % [folder, index, label]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURED ", path)


func _look(target: Vector3, _unused: float = 0.0) -> void:
	# Aim the real camera at a world point: yaw on the body, pitch on the head.
	var from: Vector3 = game.player.global_position + Vector3(0, game.player._head.position.y, 0)
	var direction: Vector3 = target - from
	game.player.face(atan2(-direction.x, -direction.z))
	game.player._pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())


func _hold(action: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _run() -> void:
	folder = ProjectSettings.globalize_path("res://../../work/captures")
	DirAccess.make_dir_recursive_absolute(folder)
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.pause_on_focus_loss = false
	root.add_child(game)
	await _frames(90)
	await _shot("title")
	game._settings(true)
	await _frames(5)
	await _shot("settings")
	game._show_title()
	game._start_free_roam()
	await _frames(40)
	await _shot("freeroam_spawn")
	# Carbine: hip fire into the dummies, then aim down sights.
	_look(Vector3(25, 1.3, -33), -0.02)
	await _frames(20)
	for burst: int in range(4):
		game.player._try_fire()
		await _frames(6)
	await _shot("carbine_hipfire")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_hold("aim", true)
	await _frames(30)
	await _shot("carbine_ads")
	_hold("aim", false)
	for id: String in ["pistol", "smg", "shotgun"]:
		game.player.switch_weapon(id)
		await _frames(30)
		await _shot(id + "_hip")
		_hold("aim", true)
		await _frames(25)
		game.player._try_fire()
		await _frames(2)
		await _shot(id + "_ads_fire")
		_hold("aim", false)
		await _frames(20)
	# Plate rack reaction.
	game.player.switch_weapon("pistol")
	await _frames(25)
	_look(Vector3(21, 1.15, -39.6), -0.03)
	await _frames(5)
	for plate: int in range(5):
		_look(Vector3(21, 1.15, -41.2 + plate * 0.8), -0.03)
		await _frames(2)
		game.player._cooldown = 0.0
		game.player._try_fire()
		await _frames(24)
	await _frames(8)
	await _shot("plates_down")
	# Marksman on the long-range lane.
	game.player.global_position = Vector3(11.0, 0.1, -15.0)
	game.player.switch_weapon("marksman")
	await _frames(25)
	_look(Vector3(52.0, 1.55, -21.8), 0.0)
	await _frames(5)
	await _shot("marksman_hip")
	_hold("aim", true)
	await _frames(35)
	await _shot("marksman_scope")
	_hold("aim", false)
	await _frames(20)
	# Provoke security at the exchange and capture a firefight.
	game.player.global_position = Vector3(1.5, 0.1, -27.0)
	game.player.switch_weapon("rifle")
	await _frames(25)
	_look(Vector3(-3, 1.3, -43), -0.02)
	await _frames(5)
	game.player._try_fire()
	await _frames(70)
	await _shot("guards_hostile")
	for burst: int in range(8):
		game.player._try_fire()
		await _frames(7)
	await _frames(10)
	await _shot("guard_combat")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game._pause()
	await _frames(5)
	await _shot("pause_freeroam")
	game._resume()
	# Drive the teal sedan with a handbrake turn for tyre marks.
	game._respawn()
	await _frames(5)
	var teal: Variant = game.cars[1]
	game.player.global_position = teal.global_position + Vector3(0, 0, 2.5)
	await _frames(5)
	game._interact()
	await _frames(5)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_hold("move_forward", true)
	await _frames(110)
	await _shot("driving_speed")
	_hold("move_left", true)
	_hold("handbrake", true)
	await _frames(40)
	_hold("handbrake", false)
	_hold("move_left", false)
	await _frames(30)
	await _shot("driving_drift")
	_hold("move_forward", false)
	_hold("move_back", true)
	await _frames(60)
	_hold("move_back", false)
	await _frames(20)
	await _shot("driving_brake")
	# Contract mode buy desk.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game._show_title()
	game.cash = 3200
	game.round_number = 0
	game._start_round()
	await _frames(20)
	await _shot("contract_buy")
	game._purchase("marksman", 2200)
	await _frames(5)
	await _shot("contract_bought")
	game._start_live()
	await _frames(30)
	await _shot("contract_live")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("CAPTURE COMPLETE: %d images" % index)
	game.queue_free()
	await process_frame
	quit(0)
