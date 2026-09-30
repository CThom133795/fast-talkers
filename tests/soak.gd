extends SceneTree
## Chaos soak: a scripted bot hammers every system for several thousand frames
## (weapons, targets, security, deaths, cars, menus, both modes). Any script
## error shows up in the log. Run headless with a fixed step to go fast:
## godot --headless --fixed-fps 60 --path . --script res://tests/soak.gd

const FRAMES: int = 6000
var game: Variant
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	rng.seed = 424242
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.settings_path = "user://soak_settings.cfg"
	root.add_child(game)
	await process_frame
	game._start_free_roam()
	var player: Variant = game.player
	var ids: Array[String] = ["pistol", "smg", "rifle", "shotgun", "marksman"]
	var spots: Array[Vector3] = [Vector3(12.8, 0.2, -32.5), Vector3(0, 0.2, -30), Vector3(-6, 0.2, -40), Vector3(11, 0.2, -15), Vector3(0, 0.2, 10), Vector3(20, 0.2, 30)]
	var deaths: int = 0
	var drives: int = 0
	var peak_particles: int = 0
	var start_msec: int = Time.get_ticks_msec()
	for frame: int in range(FRAMES):
		await physics_frame
		var roll: int = rng.randi_range(0, 99)
		if player.in_vehicle:
			Input.action_press("move_forward")
			if roll < 12:
				Input.action_press("handbrake")
			elif roll < 30:
				Input.action_release("handbrake")
			if roll % 7 == 0:
				Input.action_press("move_left" if roll % 2 == 0 else "move_right")
			elif roll % 5 == 0:
				Input.action_release("move_left")
				Input.action_release("move_right")
			if roll == 99 or frame % 400 == 399:
				for action: String in ["move_forward", "handbrake", "move_left", "move_right"]:
					Input.action_release(action)
				game.car.reset_car(game.car.global_position + Vector3(0, 0.4, 0))
				game._interact()
			continue
		if player.is_dead():
			continue
		if roll < 35:
			player._try_fire()
		elif roll < 40:
			player.switch_weapon(ids[rng.randi_range(0, ids.size() - 1)])
		elif roll < 43:
			player._start_reload()
		elif roll < 46:
			player.face(rng.randf_range(-PI, PI))
			player._pitch = rng.randf_range(-0.2, 0.15)
		elif roll < 47:
			player.global_position = spots[rng.randi_range(0, spots.size() - 1)]
		elif roll < 48 and frame % 3 == 0:
			var sedan: Variant = game.cars[rng.randi_range(0, game.cars.size() - 1)]
			player.global_position = sedan.global_position + Vector3(0, 0.2, 2.8)
			await physics_frame
			game._interact()
			if player.in_vehicle:
				drives += 1
		elif roll == 48 and frame % 5 == 0:
			player.take_damage(1000.0)
			deaths += 1
		elif roll == 49 and frame % 7 == 0:
			game._pause()
			await process_frame
			game._resume()
		elif roll == 50 and frame % 11 == 0:
			game._rearm()
		peak_particles = maxi(peak_particles, game.effects._particles.size())
	for action: String in ["move_forward", "handbrake", "move_left", "move_right"]:
		Input.action_release(action)
	# Contract mode leg: buy, deploy, rob the exchange, die, go again.
	if player.in_vehicle:
		game.car.occupied = false
		player.set_vehicle_mode(false)
	game._show_title()
	for round_index: int in range(3):
		game._start_round()
		game._purchase(["rifle", "shotgun", "marksman"][round_index], [1600, 1100, 2200][round_index])
		game._start_live()
		player.global_position = Vector3(0, 0.2, -40)
		await physics_frame
		game._interact()
		for child: Node in game.menu_stack.get_children():
			if child is Button and (child as Button).text == "TAKE IT BY FORCE":
				(child as Button).pressed.emit()
		for frame: int in range(240):
			await physics_frame
			if frame % 9 == 0:
				player._try_fire()
		if game.phase == game.Phase.LIVE:
			player.take_damage(1000.0)
	var elapsed: float = (Time.get_ticks_msec() - start_msec) / 1000.0
	print("SOAK RESULT: %d frames, %d deaths, %d drives, peak particles %d, decals %d, skids %d, final phase %d, %.1fs" % [FRAMES, deaths, drives, peak_particles, game.effects._decals.size(), game.effects._skids.size(), game.phase, elapsed])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://soak_settings.cfg"))
	game.queue_free()
	# Give the audio thread a moment to release stopped playbacks before exit.
	for settle: int in range(10):
		await process_frame
	quit(0)
