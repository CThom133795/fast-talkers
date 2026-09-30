extends SceneTree
## Windowed viewmodel review: each weapon with attachment builds, hip and aimed.
## Output: ../../work/captures/gun_*.png. Run (not headless):
## godot --path . --script res://tests/capture_guns.gd

const BUILDS: Array = [
	["p9_stock", "pistol", {}], ["m1911_stock", "m1911", {}], ["revolver_stock", "revolver", {}],
	["vk5_stock", "smg", {}], ["mac_stock", "mac", {}], ["tommy_stock", "tommy", {}],
	["m4_stock", "rifle", {}], ["ak_stock", "ak", {}], ["ak_holo_grip", "ak", {"optic": "holo2x", "underbarrel": "foregrip"}],
	["pump_stock", "shotgun", {}], ["sawnoff_stock", "double", {}], ["auto12_stock", "auto12", {}],
	["m700_stock", "marksman", {}], ["br58_stock", "dmr", {}],
	["rifle_reflex_supp_grip_ext", "rifle", {"optic": "reflex", "muzzle": "suppressor", "underbarrel": "foregrip", "magazine": "extended"}],
	["rifle_holo_comp_laser", "rifle", {"optic": "holo2x", "muzzle": "compensator", "underbarrel": "laser"}],
	["rifle_scope", "rifle", {"optic": "scope4x"}],
	["smg_reflex_laser_speed", "smg", {"optic": "reflex", "underbarrel": "laser", "magazine": "speed"}],
	["pistol_reflex_supp_ext", "pistol", {"optic": "reflex", "muzzle": "suppressor", "magazine": "extended"}],
	["shotgun_reflex_choke_grip", "shotgun", {"optic": "reflex", "muzzle": "choke", "underbarrel": "foregrip"}],
	["marksman_stock", "marksman", {}],
	["marksman_reflex_supp", "marksman", {"optic": "reflex", "muzzle": "suppressor"}],
]

var game: Variant
var folder: String


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for step: int in range(count):
		await process_frame


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/gun_%s.png" % [folder, label])
	print("CAPTURED ", label)


func _run() -> void:
	folder = ProjectSettings.globalize_path("res://../../work/captures")
	DirAccess.make_dir_recursive_absolute(folder)
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.pause_on_focus_loss = false
	game.settings_path = "user://capture_settings.cfg"
	root.add_child(game)
	await _frames(30)
	game._start_free_roam()
	await _frames(20)
	var player: Variant = game.player
	var target: Vector3 = Vector3(25, 1.3, -33)
	var from: Vector3 = player.global_position + Vector3(0, 1.62, 0)
	var direction: Vector3 = target - from
	player.face(atan2(-direction.x, -direction.z))
	player._pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for build: Array in BUILDS:
		var id: String = build[1]
		player.replace_in_class(id)
		for slot: String in ["optic", "muzzle", "underbarrel", "magazine"]:
			player.set_attachment(id, slot, str((build[2] as Dictionary).get(slot, "")))
		await _frames(40)
		await _shot(build[0] + "_hip")
		Input.action_press("aim")
		await _frames(35)
		await _shot(build[0] + "_ads")
		Input.action_release("aim")
		await _frames(15)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game._gunsmith()
	await _frames(5)
	await _shot("zz_gunsmith_menu")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture_settings.cfg"))
	game.queue_free()
	for settle: int in range(10):
		await process_frame
	quit(0)
