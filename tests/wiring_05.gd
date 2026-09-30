extends SceneTree
## 0.5 integration of the world into the game: shop doors answer E with a prompt, rounds
## reglaze windows and reopen doors, the GPS line routes to the objective, and the practice
## wheelman drives the streets from a far-off HQ instead of cutting through buildings.
## Run: godot --headless --path . --script res://tests/wiring_05.gd

var game: Variant
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame
	await process_frame


func _run() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("wiring_05 did not finish in 90 s")
		quit(2))
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.pause_on_focus_loss = false
	game.settings_path = "user://wiring_test_settings.cfg"
	root.add_child(game)
	await _frames(3)
	game._start_free_roam()
	await _frames(5)
	var world: Variant = game.world
	var player: Variant = game.player
	# Shop doors: prompt, E to shut, E to open.
	var door: Dictionary = world.interactable_doors[7]
	player.global_position = (door["outside"] as Vector3) + Vector3(0, 0.1, 0)
	await _frames(3)
	_check(game._shop_door_in_reach() == 7 and str(game._prompt_text()).contains("CLOSE THE DOOR"), "Standing at a shop door prompts to close it")
	game._interact()
	await _frames(60)
	_check(not bool(door["open"]) and str(game._prompt_text()).contains("OPEN THE DOOR"), "E shuts the door and the prompt flips to OPEN")
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create((door["outside"] as Vector3) + Vector3(0, 1, 0), (door["inside"] as Vector3) + Vector3(0, 1, 0))
	query.exclude = [player.get_rid()]
	_check(not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "The shut door physically blocks the doorway")
	game._interact()
	await _frames(60)
	_check(bool(door["open"]), "E opens it again")
	# A car door beside a shop door wins: parking outside a shop never traps the E key.
	var garage: int = -1
	for candidate: Dictionary in world.interactable_doors:
		if str(candidate["kind"]) == "garage":
			garage = int(candidate["index"])
	_check(garage >= 0 and str(world.interactable_doors[garage]["label"]) == "MIDTOWN GARAGE", "The garage has a roll-up door")
	# Rounds reglaze and reopen.
	var pane: Variant = world.glass_panes[0]["body"]
	pane.take_damage(50.0)
	world.set_door_open(3, false)
	game._start_round()
	await _frames(5)
	_check(not pane.broken and pane.collision_layer == 1, "A new round reglazes shot-out shop windows")
	_check(bool(world.interactable_doors[3]["open"]), "A new round reopens shut shop doors")
	# GPS: after the buy phase, the radar line routes to the Exchange case.
	game._start_live()
	await _frames(5)
	game._update_gps(1.0)
	_check(game.gps_path.size() >= 2 and game.gps_color == game.GOLD, "The GPS line routes from the HQ to the case at the Exchange (amber)")
	var ends_near_case: bool = game.gps_path.size() > 0 and (game.gps_path[game.gps_path.size() - 1] as Vector3).distance_to(game.case_mesh.global_position) < 1.0
	_check(ends_near_case, "The GPS line ends at the case")
	game.carrying = true
	player.global_position = Vector3(0, 0.2, -30)
	await _frames(2)
	game._gps_timer = 0.0
	game._update_gps(0.1)
	_check(game.gps_color == game.TEAL and game.gps_path.size() >= 2, "Carrying the case, the GPS line routes home (teal)")
	game.carrying = false
	# Wheelman from a crew HQ far from downtown: streets first, no cutting through buildings.
	game._start_free_roam()
	await _frames(5)
	var bike: Variant = null
	for ride: Variant in game.cars:
		if ride.vehicle_type == "motorcycle":
			bike = ride
			break
	# Lantern Row's main street, 150 m out from downtown, clear of the parked crew cars.
	bike.reset_car(Vector3(-160, 0.1, -48))
	bike.rotation.y = -PI * 0.5
	await _frames(10)
	game._enter_vehicle(bike, 1)
	await _frames(3)
	_check(bike.autopilot and bike.autopilot_loop_from > 0, "The wheelman takes a street route to the ring before looping")
	var travelled: float = 0.0
	var last: Vector3 = bike.global_position
	var stuck_frames: int = 0
	for step: int in range(40):
		await _frames(15)
		travelled += bike.global_position.distance_to(last)
		if bike.global_position.distance_to(last) < 0.5:
			stuck_frames += 1
		last = bike.global_position
	_check(travelled > 60.0, "The wheelman drives the streets from Lantern Row (%.0f m in 10 s)" % travelled)
	_check(stuck_frames <= 4, "…without getting stuck against buildings (%d stalls)" % stuck_frames)
	game._exit_vehicle(true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://wiring_test_settings.cfg"))
	print("WIRING 0.5 RESULT: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
