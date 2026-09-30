extends SceneTree
## Windowed rig review: orthographic front view and head close-up of one crew member against
## a 10 cm grid, plus bone positions. Output: ../../work/captures/rig_*.png

const CharacterModel = preload("res://scripts/character_model.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var folder: String = ProjectSettings.globalize_path("res://../../work/captures")
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, 30, 0)
	world.add_child(light)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.5, 0.55, 0.6)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	world.add_child(environment)
	var model: Variant = CharacterModel.new()
	world.add_child(model)
	model.build("solnegro", false)
	for step: int in range(5):
		await process_frame
		model.animate(1.0 / 60.0, Vector3.ZERO, false)
	var line: StandardMaterial3D = StandardMaterial3D.new()
	line.albedo_color = Color(0.1, 0.1, 0.1)
	line.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for index: int in range(20):
		var bar: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(1.6, 0.003 if index % 5 != 0 else 0.008, 0.003)
		bar.mesh = box
		bar.material_override = line
		bar.position = Vector3(0, index * 0.1, 0.4)
		world.add_child(bar)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.1
	world.add_child(camera)
	camera.position = Vector3(0, 1.0, -3)
	camera.look_at(Vector3(0, 1.0, 0))
	camera.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(folder + "/rig_front.png")
	camera.size = 0.7
	camera.position = Vector3(0, 1.6, -3)
	camera.look_at(Vector3(0, 1.6, 0))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(folder + "/rig_head.png")
	var skeleton: Skeleton3D = model.skeleton
	for bone: int in range(skeleton.get_bone_count()):
		print(skeleton.get_bone_name(bone), " ", skeleton.get_bone_global_pose(bone).origin)
	print("AABB ", (model.skeleton.get_child(0) as MeshInstance3D).get_aabb())
	quit(0)
