extends SceneTree
## Isolated fleet render review: actual seat-eye cameras pitched into the cabin.
const Car = preload("res://scripts/car.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var folder: String = ProjectSettings.globalize_path("res://work/captures")
	DirAccess.make_dir_recursive_absolute(folder)
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.38, 0.45)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	env.environment.ambient_light_energy = 0.7
	root.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	root.add_child(sun)
	var camera: Camera3D = Camera3D.new()
	camera.near = 0.025
	camera.fov = 85
	root.add_child(camera)
	camera.current = true
	for kind: String in ["sedan", "coupe", "suv", "pickup"]:
		var car: Node3D = Car.new()
		car.vehicle_type = kind
		root.add_child(car)
		car.set_physics_process(false)
		for view: String in ["driver", "passenger", "outside"]:
			if view == "outside":
				camera.position = Vector3(-3.3, 2.4, -4.5)
				camera.look_at(Vector3(0, 0.8, 0))
			else:
				camera.position = car.seat_eye(0 if view == "driver" else 1)
				camera.look_at(camera.position + Vector3(0.35 if view == "driver" else -0.45, -0.65, -1))
			for frame: int in range(4):
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png(folder + "/cabin_" + kind + "_" + view + ".png")
		car.queue_free()
		await process_frame
	quit(0)
