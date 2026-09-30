extends SceneTree
## Windowed vehicle review. A studio lineup of the whole fleet in the open harbour yard
## (HUD hidden), noses west: side, front three-quarter and rear three-quarter, plus a
## close three-quarter of each type; then the gunner's views (rear window, pickup bed,
## pillion) and the driver's drive-by in play. Output: ../../work/captures/veh_*.png.
## Run (not headless): godot --path . --script res://tests/capture_vehicles.gd

const TYPES: Array[String] = ["motorcycle", "coupe", "sedan", "suv", "pickup"]
## Lineup: along +X in the harbour yard, noses pointing -X.
const ORIGIN: Vector3 = Vector3(30.0, 0.1, -104.0)
const SPACING: float = 7.0

var game: Variant
var folder: String


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for step: int in range(count):
		await process_frame


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/veh_%s.png" % [folder, label])
	print("CAPTURED ", label)


func _vehicle(type: String) -> Variant:
	for ride: Variant in game.cars:
		if ride.vehicle_type == type:
			return ride
	return null


func _camera(at: Vector3, target: Vector3, fov: float = 40.0) -> void:
	game.chase.fov = fov
	game.chase.global_position = at
	game.chase.look_at(target)
	game.chase.make_current()


func _hud(visible: bool) -> void:
	for child: Node in game.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = visible


func _run() -> void:
	folder = ProjectSettings.globalize_path("res://../../work/captures")
	DirAccess.make_dir_recursive_absolute(folder)
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.pause_on_focus_loss = false
	game.settings_path = "user://capture_settings.cfg"
	root.add_child(game)
	await _frames(30)
	game._start_free_roam()
	await _frames(10)
	game.player.global_position = ORIGIN + Vector3(0, 0, 30)
	var lineup: Array = []
	for index: int in range(TYPES.size()):
		var ride: Variant = _vehicle(TYPES[index])
		ride.reset_car(ORIGIN + Vector3(index * SPACING, 0, 0))
		ride.rotation.y = PI * 0.5
		lineup.append(ride)
	await _frames(40)
	_hud(false)
	var middle: Vector3 = ORIGIN + Vector3(SPACING * 2.0, 0.8, 0)
	_camera(middle + Vector3(0, 0.6, 26), middle, 38.0)
	await _frames(8)
	await _shot("lineup_side")
	_camera(middle + Vector3(-24, 3.2, 14), middle + Vector3(-3, -0.3, 0), 44.0)
	await _frames(5)
	await _shot("lineup_front")
	_camera(middle + Vector3(24, 3.0, 14), middle + Vector3(3, -0.3, 0), 44.0)
	await _frames(5)
	await _shot("lineup_rear")
	for ride: Variant in lineup:
		var at: Vector3 = ride.global_position + Vector3(0, 0.8, 0)
		_camera(at + Vector3(-5.4, 1.1, 4.4), at + Vector3(0, -0.15, 0), 40.0)
		await _frames(5)
		await _shot("front_" + str(ride.vehicle_type))
		_camera(at + Vector3(5.4, 1.4, 4.6), at + Vector3(0, -0.15, 0), 40.0)
		await _frames(5)
		await _shot("rear_" + str(ride.vehicle_type))
	_hud(true)
	game.chase.fov = 72.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Rear-right window gunner in the SUV, aiming out to the right.
	var suv: Variant = _vehicle("suv")
	game._enter_vehicle(suv, 3)
	game.player.replace_in_class("ak")
	await _frames(40)
	await _shot("gunner_suv_rear")
	# Pickup bed gunner looking back over the tailgate.
	game._exit_vehicle(true)
	var pickup: Variant = _vehicle("pickup")
	game._enter_vehicle(pickup, 2)
	game.player.seat_yaw = PI * 0.8
	await _frames(40)
	await _shot("gunner_pickup_bed")
	game._exit_vehicle(true)
	# Pillion gunner on the bike with the sawn-off.
	var bike: Variant = _vehicle("motorcycle")
	game._enter_vehicle(bike, 1)
	game.player.replace_in_class("double")
	game.player.seat_yaw = 1.2
	await _frames(40)
	await _shot("gunner_pillion")
	game._exit_vehicle(true)
	# Driver: chase camera, then the drive-by lean-out.
	var sedan: Variant = _vehicle("sedan")
	game._enter_vehicle(sedan, 0)
	await _frames(40)
	await _shot("driver_chase")
	Input.action_press("driveby_aim")
	await _frames(40)
	await _shot("driver_driveby")
	Input.action_release("driveby_aim")
	game._exit_vehicle(true)
	game._enter_vehicle(bike, 0)
	await _frames(50)
	await _shot("rider_chase")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture_settings.cfg"))
	game.queue_free()
	for settle: int in range(10):
		await process_frame
	quit(0)
