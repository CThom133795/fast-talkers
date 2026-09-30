extends SceneTree
## Windowed character sheet: the four crews idle, walking, aiming and knocked down.
## Output: ../../work/captures/char_*.png. Run (not headless):
## godot --path . --script res://tests/capture_characters.gd

const CharacterModel = preload("res://scripts/character_model.gd")
const Factions = preload("res://scripts/factions.gd")

var game: Variant
var models: Array = []
var folder: String


func _initialize() -> void:
	call_deferred("_run")


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/char_%s.png" % [folder, label])
	print("CAPTURED ", label)


func _animate(frames: int, velocity: Vector3, aiming: bool) -> void:
	for step: int in range(frames):
		await process_frame
		for model: Variant in models:
			model.animate(1.0 / 60.0, velocity, aiming)


func _run() -> void:
	folder = ProjectSettings.globalize_path("res://../../work/captures")
	DirAccess.make_dir_recursive_absolute(folder)
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.pause_on_focus_loss = false
	game.settings_path = "user://capture_settings.cfg"
	root.add_child(game)
	for step: int in range(20):
		await process_frame
	game._hide_title_set()
	game.menu.hide()
	game.hud.visible = false
	for index: int in range(4):
		var model: Variant = CharacterModel.new()
		game.add_child(model)
		model.build(Factions.ORDER[index], true)
		model.position = Vector3(-2.7 + index * 1.8, 0.03, -30.0)
		model.rotation.y = PI
		models.append(model)
	var camera: Camera3D = Camera3D.new()
	game.add_child(camera)
	camera.fov = 40.0
	camera.position = Vector3(0, 1.35, -22.5)
	camera.look_at(Vector3(0, 1.0, -30.0))
	camera.make_current()
	await _animate(40, Vector3.ZERO, false)
	await _shot("idle")
	await _animate(22, Vector3(0, 0, 3.2), false)
	await _shot("walk")
	await _animate(30, Vector3.ZERO, true)
	await _shot("aim")
	for model: Variant in models:
		model.flinch(4.0)
	await _animate(4, Vector3.ZERO, true)
	await _shot("flinch")
	camera.position = Vector3(0.9, 1.75, -27.8)
	camera.look_at(Vector3(0.9, 1.7, -30.0))
	camera.fov = 32.0
	await _animate(20, Vector3.ZERO, false)
	await _shot("faces")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture_settings.cfg"))
	game.queue_free()
	for settle: int in range(10):
		await process_frame
	quit(0)
