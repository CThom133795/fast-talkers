extends SceneTree
## Isolated fleet render review: actual seat-eye cameras pitched into the cabin, plus close
## exterior views over a ground plane (wheel contact, arches, plates, rear lamps).
## Output: work/captures/cabins/cabin_<type>_<view>.png. Runs under Xvfb + Mesa software GL:
## xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --script res://tests/capture_cabins.gd
const Car = preload("res://scripts/car.gd")
const TYPES: Array[String] = ["sedan", "coupe", "suv", "pickup", "motorcycle"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var folder: String = ProjectSettings.globalize_path("res://work/captures/cabins")
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
	sun.shadow_enabled = true
	root.add_child(sun)
	# Ground plane at road height, so wheel contact and ride height read in the shots.
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var asphalt: StandardMaterial3D = StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.36, 0.36, 0.37)
	asphalt.roughness = 0.95
	ground.material_override = asphalt
	root.add_child(ground)
	var camera: Camera3D = Camera3D.new()
	camera.near = 0.025
	root.add_child(camera)
	camera.current = true
	for kind: String in TYPES:
		var car: Node3D = Car.new()
		car.vehicle_type = kind
		root.add_child(car)
		car.set_physics_process(false)
		var views: Array = ["outside", "front", "rear"] if kind == "motorcycle" else ["driver", "passenger", "back", "outside", "front", "rear"]
		for view: String in views:
			camera.fov = 85
			match view:
				"outside":
					camera.fov = 40
					camera.position = Vector3(-4.6, 1.5, -5.2)
					camera.look_at(Vector3(0, 0.6, 0))
				"front":
					# Low side view of the front wheel and its arch.
					camera.fov = 50
					camera.position = Vector3(-3.4, 0.45, -1.4)
					camera.look_at(Vector3(0, 0.4, -1.2))
				"rear":
					camera.fov = 45
					camera.position = Vector3(2.6, 1.3, 5.6)
					camera.look_at(Vector3(0, 0.7, 1.5))
				"back":
					# Rear-seat (or pickup bed) occupant looking forward between the front seats.
					camera.position = car.seat_eye(2 if car.seat_count() > 2 else 1)
					camera.look_at(camera.position + Vector3(0.2, -0.45, -1))
				_:
					camera.position = car.seat_eye(0 if view == "driver" else 1)
					camera.look_at(camera.position + Vector3(0.35 if view == "driver" else -0.45, -0.65, -1))
			for frame: int in range(4):
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png(folder + "/cabin_" + kind + "_" + view + ".png")
		car.queue_free()
		await process_frame
	quit(0)
