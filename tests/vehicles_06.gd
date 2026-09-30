extends SceneTree
## 0.6 vehicle changes: breakable glass (bullets and crashes), the grip-capped handling model
## and the third-person vehicle camera with its settings toggle.
## Run: godot --headless --path . --script res://tests/vehicles_06.gd

var game: Variant
var checks: int = 0
var failures: int = 0
## Broken-glass signal log for the car under test.
var _broken_log: Array = []


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


## Nearest hit distance of a horizontal ray, or INF.
func _ray_distance(from: Vector3, dir: Vector3, length: float, exclude: Array) -> float:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + dir * length)
	query.exclude = exclude
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
	return INF if hit.is_empty() else from.distance_to(hit["position"] as Vector3)


## True when there is ground below `at` and nothing within `radius` metres around it.
func _is_open(at: Vector3, radius: float, exclude: Array) -> bool:
	var down: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(at + Vector3(0, 2, 0), at + Vector3(0, -2, 0))
	down.exclude = exclude
	if game.get_world_3d().direct_space_state.intersect_ray(down).is_empty():
		return false
	for step: int in range(8):
		var dir: Vector3 = Vector3(cos(step * TAU / 8.0), 0, sin(step * TAU / 8.0))
		for height: float in [0.5, 1.2, 1.8]:
			if _ray_distance(at + Vector3(0, height, 0), dir, radius, exclude) < radius:
				return false
	return true


func _run() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("vehicles_06 did not finish in 90 s")
		quit(2))
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.pause_on_focus_loss = false
	game.settings_path = "user://vehicles06_settings.cfg"
	root.add_child(game)
	await _frames(3)
	game._start_free_roam()
	await _frames(5)
	var player: Variant = game.player
	var sedan: Variant = null
	for ride: Variant in game.cars:
		if ride.vehicle_type == "sedan":
			sedan = ride
			break
	_check(sedan != null and sedan.glass_count() >= 4, "A sedan exists and has separate glass panes (%d)" % (0 if sedan == null else sedan.glass_count()))

	# --- Bullets through the windows --------------------------------------------------
	# The ring road's north side, checked for clear ground on all sides.
	var spot: Vector3 = Vector3.INF
	for x: float in [-40.0, 0.0, 40.0, -60.0, 60.0, -20.0, 20.0]:
		var candidate: Vector3 = Vector3(x, 0.1, -85.0)
		sedan.reset_car(candidate)
		await _frames(2)
		if _is_open(candidate, 4.5, [sedan.get_rid(), player.get_rid()]):
			spot = candidate
			break
	_check(spot != Vector3.INF, "Found open road with ground and 4.5 m clear for the shooting test")
	if spot == Vector3.INF:
		spot = Vector3(0, 0.1, -85)
	sedan.glass_broken.connect(func(index: int, _at: Vector3) -> void: _broken_log.append(index))
	sedan.reset_car(spot)
	await _frames(5)
	var before: int = sedan.intact_glass()
	_check(before == sedan.glass_count(), "A fresh sedan has every pane intact (%d)" % before)
	game.phase = game.Phase.LIVE
	game.paused = false
	# Low ray across the doors (below the beltline): no glass in the way.
	var here: Vector3 = sedan.global_position
	game._on_shot(here + Vector3(-5, 0.5, -0.3), Vector3.RIGHT, 30.0)
	_check(sedan.intact_glass() == before, "A shot through the lower doors breaks no glass")
	# Ray across the cabin at driver eye height.
	var pane: Dictionary = sedan.glass_hit(here + Vector3(-5, 1.18, -0.3), here + Vector3(5, 1.18, -0.3))
	_check(not pane.is_empty() and float(pane["distance"]) > 3.0 and float(pane["distance"]) < 5.0, "glass_hit finds the near window on a cabin-height ray")
	game._on_shot(here + Vector3(-5, 1.18, -0.3), Vector3.RIGHT, 30.0)
	var after: int = sedan.intact_glass()
	_check(after < before, "A shot across the cabin shatters window glass (%d -> %d panes)" % [before, after])
	_check(_broken_log.size() == before - after, "glass_broken fires once per shattered pane (%d)" % _broken_log.size())
	_check((not _broken_log.is_empty()) and not sedan.break_glass(int(_broken_log[0])), "A pane that is already gone cannot break twice")
	# Rolled-down windows are open air, not glass.
	sedan.reset_car(spot)
	await _frames(2)
	sedan.set_window_open(0, true)
	_check(not sedan.window_closed(0) and sedan.window_closed(1), "set_window_open(0) rolls only the driver window down")
	sedan.set_window_open(0, false)
	# A new round / free roam reglazes.
	game._on_shot(sedan.global_position + Vector3(-5, 1.18, -0.3), Vector3.RIGHT, 30.0)
	var shot_out: int = sedan.intact_glass()
	game._start_free_roam()
	await _frames(5)
	_check(shot_out < sedan.glass_count() and sedan.intact_glass() == sedan.glass_count(), "Free roam restart reglazes the shot-out car")

	# --- Crash breaks a pane ----------------------------------------------------------
	# Find a flat wall in front of a clear drive-up: a horizontal ray from road level.
	sedan.reset_car(Vector3(0, 0.1, -85))
	var run_from: Vector3 = Vector3.INF
	var run_yaw: float = 0.0
	var found_wall: bool = false
	var headings: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]
	for z: float in [-85.0, 85.0]:
		for x: float in [-60.0, -30.0, 0.0, 30.0, 60.0]:
			for dir: Vector3 in headings:
				var origin: Vector3 = Vector3(x, 1.0, z)
				var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + dir * 90.0)
				query.exclude = [sedan.get_rid(), player.get_rid()]
				var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
				if hit.is_empty() or not hit["collider"] is StaticBody3D:
					continue
				var distance: float = origin.distance_to(hit["position"] as Vector3)
				var normal: Vector3 = hit["normal"]
				if distance > 30.0 and distance < 85.0 and normal.dot(-dir) > 0.98 and absf(normal.y) < 0.05 and _is_open(Vector3(x, 0.1, z), 3.0, [sedan.get_rid(), player.get_rid()]):
					run_from = Vector3(x, 0.1, z)
					run_yaw = atan2(-dir.x, -dir.z)
					found_wall = true
					break
			if found_wall:
				break
		if found_wall:
			break
	_check(found_wall, "Found a flat wall to drive into")
	if found_wall:
		sedan.reset_car(run_from)
		sedan.rotation.y = run_yaw
		await _frames(5)
		var intact_before: int = sedan.intact_glass()
		var crash_log: Array = []
		sedan.crashed.connect(func(strength: float) -> void: crash_log.append(strength))
		sedan.occupied = true
		sedan.wake()
		var launch: Vector3 = -sedan.global_transform.basis.z * 28.0
		for step: int in range(300):
			if step < 3:
				sedan.velocity = Vector3(launch.x, sedan.velocity.y, launch.z)
			await physics_frame
			if not crash_log.is_empty():
				break
		await _frames(2)
		sedan.occupied = false
		_check(not crash_log.is_empty() and float(crash_log[0]) > 10.0, "The car hits the wall hard (speed lost %.1f m/s)" % (0.0 if crash_log.is_empty() else float(crash_log[0])))
		_check(sedan.intact_glass() < intact_before, "A hard crash breaks a pane (%d -> %d)" % [intact_before, sedan.intact_glass()])
	else:
		_check(false, "Crash breaks a pane (skipped: no wall)")
	game._start_free_roam()
	await _frames(5)

	# --- Handling ----------------------------------------------------------------------
	sedan.reset_car(Vector3(-80, 0.1, -85))
	sedan.rotation.y = -PI * 0.5
	await _frames(10)
	game._enter_vehicle(sedan, 0)
	await _frames(3)
	_check(sedan.occupied and game.vehicle == sedan and game.seat == 0, "The player takes the sedan's driver seat")
	Input.action_press("move_forward")
	var reached: bool = false
	for step: int in range(600):
		await physics_frame
		if sedan.velocity.length() > 20.0:
			reached = true
			break
	var speed_before: float = sedan.velocity.length()
	_check(reached, "The sedan accelerates past 20 m/s on the straight (%.1f m/s)" % speed_before)
	# Left lock: the ring road has open verge on that side (a right turn clips the kerb).
	var yaw_before: float = sedan.rotation.y
	var max_slip: float = 0.0
	Input.action_press("move_left")
	for step: int in range(90):
		await physics_frame
		max_slip = maxf(max_slip, absf(sedan.slip))
	Input.action_release("move_left")
	var turned: float = absf(angle_difference(yaw_before, sedan.rotation.y))
	Input.action_release("move_forward")
	_check(max_slip < 3.0, "Full-lock turn at speed stays gripped (max lateral %.2f m/s)" % max_slip)
	_check(turned > 0.6, "...and still turns the car (%.2f rad in 1.5 s)" % turned)

	# --- Camera ------------------------------------------------------------------------
	game._exit_vehicle(true)
	await _frames(2)
	game._start_free_roam()
	await _frames(5)
	game.drive_third_person = false
	game._enter_vehicle(sedan, 0)
	await _frames(5)
	_check(player.camera.current and not game.chase.current and not player.hold_fire, "First-person setting keeps the seat camera")
	game.drive_third_person = true
	await _frames(5)
	_check(game.chase.current and player.hold_fire and game.avatar.visible, "Third person: chase camera current, fire held, avatar seated in view")
	game.driveby = true
	_check(not game._third_person_active(), "A drive-by returns to first person")
	game.driveby = false
	game.drive_third_person = false
	await _frames(5)
	_check(player.camera.current and not game.chase.current and not player.hold_fire, "Toggling third person off returns the seat camera")
	game.drive_third_person = true
	await _frames(5)
	game._exit_vehicle(true)
	await _frames(3)
	_check(not player.hold_fire and not game.avatar.visible and player.camera.current, "Leaving the car clears hold_fire, hides the avatar and restores the camera")

	# --- Settings round-trip -----------------------------------------------------------
	game.drive_third_person = true
	game._save_settings()
	game.drive_third_person = false
	game._load_settings()
	_check(game.drive_third_person, "drive_third_person survives a save and load")
	game.drive_third_person = false
	game._save_settings()
	game.drive_third_person = true
	game._load_settings()
	_check(not game.drive_third_person, "...and the off state does too")

	Input.action_release("move_forward")
	Input.action_release("move_left")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://vehicles06_settings.cfg"))
	print("VEHICLES 0.6 RESULT: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
