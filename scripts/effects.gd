extends Node3D
## Cheap, capped combat and driving effects: tracers, impact debris, bullet marks,
## ejected brass, muzzle light, floating damage numbers and tyre marks.
## Everything reuses shared meshes/materials and ring buffers so long sessions stay flat.

const MAX_PARTICLES: int = 180
const MAX_DECALS: int = 90
const MAX_SKIDS: int = 360

var _particles: Array[Dictionary] = []
var _tracers: Array[Dictionary] = []
var _floaters: Array[Dictionary] = []
var _decals: Array[MeshInstance3D] = []
var _decal_index: int = 0
var _skids: Array[MeshInstance3D] = []
var _skid_index: int = 0
var _lights: Array[OmniLight3D] = []
var _light_life: Array[float] = []
var _cube: BoxMesh
var _decal_mesh: QuadMesh
var _skid_mesh: QuadMesh
var _materials: Dictionary = {}


func _ready() -> void:
	_cube = BoxMesh.new()
	_cube.size = Vector3.ONE
	_decal_mesh = QuadMesh.new()
	_decal_mesh.size = Vector2(0.11, 0.11)
	_skid_mesh = QuadMesh.new()
	_skid_mesh.size = Vector2(0.24, 0.62)
	_skid_mesh.orientation = PlaneMesh.FACE_Y
	for index: int in range(3):
		var light: OmniLight3D = OmniLight3D.new()
		light.omni_range = 7.0
		light.light_energy = 0.0
		light.light_color = Color(1.0, 0.78, 0.45)
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		_lights.append(light)
		_light_life.append(0.0)


func _unshaded(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var key: String = str(color) + str(transparent)
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = material
	return material


func _process(delta: float) -> void:
	for index: int in range(_particles.size() - 1, -1, -1):
		var particle: Dictionary = _particles[index]
		var node: MeshInstance3D = particle["node"]
		var life: float = float(particle["life"]) - delta
		if life <= 0.0:
			node.queue_free()
			_particles.remove_at(index)
			continue
		particle["life"] = life
		var velocity: Vector3 = particle["velocity"]
		velocity.y -= float(particle["gravity"]) * delta
		velocity *= 1.0 - float(particle["drag"]) * delta
		particle["velocity"] = velocity
		node.position += velocity * delta
		if bool(particle["spin"]):
			node.rotate_x(delta * 14.0)
			node.rotate_y(delta * 9.0)
		if node.position.y < 0.02 and velocity.y < 0.0:
			node.position.y = 0.02
			particle["velocity"] = Vector3(velocity.x * 0.4, -velocity.y * 0.3, velocity.z * 0.4)
		var fraction: float = life / float(particle["max_life"])
		var grown: float = 1.0 + (1.0 - fraction) * float(particle["growth"])
		node.scale = Vector3.ONE * float(particle["size"]) * grown * (fraction if bool(particle["shrink"]) else 1.0)
	for index: int in range(_tracers.size() - 1, -1, -1):
		var tracer: Dictionary = _tracers[index]
		var life: float = float(tracer["life"]) - delta
		var mesh: MeshInstance3D = tracer["node"]
		if life <= 0.0:
			mesh.queue_free()
			_tracers.remove_at(index)
			continue
		tracer["life"] = life
		mesh.scale.x = life / float(tracer["max_life"])
		mesh.scale.y = mesh.scale.x
	for index: int in range(_floaters.size() - 1, -1, -1):
		var floater: Dictionary = _floaters[index]
		var label: Label3D = floater["node"]
		var life: float = float(floater["life"]) - delta
		if life <= 0.0:
			label.queue_free()
			_floaters.remove_at(index)
			continue
		floater["life"] = life
		label.position.y += delta * 0.9
		label.modulate.a = clampf(life / 0.35, 0.0, 1.0)
		label.outline_modulate.a = label.modulate.a
	for index: int in range(_lights.size()):
		if _light_life[index] > 0.0:
			_light_life[index] -= delta
			_lights[index].light_energy = maxf(0.0, _light_life[index] / 0.05) * 2.4
			_lights[index].visible = _light_life[index] > 0.0


func clear() -> void:
	for particle: Dictionary in _particles:
		(particle["node"] as Node).queue_free()
	_particles.clear()
	for tracer: Dictionary in _tracers:
		(tracer["node"] as Node).queue_free()
	_tracers.clear()
	for floater: Dictionary in _floaters:
		(floater["node"] as Node).queue_free()
	_floaters.clear()
	for decal: MeshInstance3D in _decals:
		decal.visible = false
	for skid: MeshInstance3D in _skids:
		skid.visible = false


func _spawn_particle(at: Vector3, velocity: Vector3, color: Color, size: float, life: float, gravity: float, drag: float = 1.5, shrink: bool = true, spin: bool = false, growth: float = 0.0) -> void:
	if _particles.size() >= MAX_PARTICLES:
		var oldest: Dictionary = _particles.pop_front()
		(oldest["node"] as Node).queue_free()
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = _cube
	node.material_override = _unshaded(color, color.a < 1.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = at
	node.scale = Vector3.ONE * size
	add_child(node)
	_particles.append({"node": node, "velocity": velocity, "life": life, "max_life": life, "gravity": gravity, "drag": drag, "size": size, "shrink": shrink, "spin": spin, "growth": growth})


func tracer(from: Vector3, to: Vector3, color: Color, width: float = 0.018, life: float = 0.06) -> void:
	var length: float = from.distance_to(to)
	if length < 0.05:
		return
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(width, width, length)
	mesh.mesh = box
	mesh.material_override = _unshaded(color)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	mesh.position = (from + to) * 0.5
	mesh.look_at_from_position(mesh.position, to, Vector3.UP if absf((to - from).normalized().y) < 0.98 else Vector3.RIGHT)
	_tracers.append({"node": mesh, "life": life, "max_life": life})


func impact(at: Vector3, normal: Vector3, kind: String = "world") -> void:
	var colors: Array[Color] = [Color(0.62, 0.58, 0.50), Color(0.45, 0.43, 0.38)]
	var count: int = 6
	var speed: float = 3.2
	if kind == "flesh":
		colors = [Color(0.62, 0.08, 0.07), Color(0.42, 0.05, 0.05)]
		count = 7
	elif kind == "steel":
		colors = [Color(1.0, 0.86, 0.45), Color(1.0, 0.62, 0.25)]
		count = 8
		speed = 5.5
	elif kind == "car":
		colors = [Color(1.0, 0.9, 0.6), Color(0.35, 0.35, 0.35)]
	for index: int in range(count):
		var spray: Vector3 = (normal + Vector3(randf_range(-0.7, 0.7), randf_range(-0.3, 0.9), randf_range(-0.7, 0.7))).normalized()
		_spawn_particle(at + normal * 0.03, spray * randf_range(0.5, 1.0) * speed, colors[index % colors.size()], randf_range(0.035, 0.07), randf_range(0.25, 0.5), 9.0 if kind != "steel" else 14.0)
	if kind == "world" or kind == "car":
		_decal(at, normal)


func _decal(at: Vector3, normal: Vector3) -> void:
	var decal: MeshInstance3D
	if _decals.size() < MAX_DECALS:
		decal = MeshInstance3D.new()
		decal.mesh = _decal_mesh
		decal.material_override = _unshaded(Color(0.06, 0.06, 0.06, 0.85), true)
		decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(decal)
		_decals.append(decal)
	else:
		decal = _decals[_decal_index]
		_decal_index = (_decal_index + 1) % MAX_DECALS
	decal.visible = true
	if normal.y > 0.9 and at.y < 0.05:
		# Street paint sits above the ground collider; keep ground marks visible.
		at.y = 0.058
	var up: Vector3 = Vector3.UP if absf(normal.y) < 0.95 else Vector3.FORWARD
	decal.global_transform = Transform3D(Basis.looking_at(-normal, up), at + normal * 0.012)
	decal.rotate_object_local(Vector3.FORWARD, randf() * TAU)


func brass(at: Vector3, right: Vector3, back: Vector3, shotgun: bool = false) -> void:
	var color: Color = Color(0.72, 0.16, 0.12) if shotgun else Color(0.86, 0.66, 0.28)
	var velocity: Vector3 = right * randf_range(1.9, 2.6) + Vector3.UP * randf_range(0.9, 1.5) + back * randf_range(0.3, 0.8)
	_spawn_particle(at + right * 0.05, velocity, color, 0.017 if not shotgun else 0.026, 0.9, 11.0, 0.4, false, true)


func muzzle_light(at: Vector3) -> void:
	for index: int in range(_lights.size()):
		if _light_life[index] <= 0.0 or index == _lights.size() - 1:
			_lights[index].global_position = at
			_lights[index].visible = true
			_lights[index].light_energy = 2.4
			_light_life[index] = 0.05
			return


func damage_number(at: Vector3, amount: float, headshot: bool) -> void:
	var label: Label3D = Label3D.new()
	label.text = str(int(round(amount)))
	label.font_size = 34 if headshot else 26
	label.pixel_size = 0.0018
	label.fixed_size = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(1.0, 0.36, 0.28) if headshot else Color(1.0, 0.95, 0.82)
	label.outline_size = 10
	label.outline_modulate = Color(0.05, 0.05, 0.05)
	label.position = at + Vector3(randf_range(-0.15, 0.15), 0.1, randf_range(-0.15, 0.15))
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(label)
	_floaters.append({"node": label, "life": 0.9})


func smoke(at: Vector3, amount: int = 1) -> void:
	for index: int in range(amount):
		_spawn_particle(at + Vector3(randf_range(-0.2, 0.2), 0.15, randf_range(-0.2, 0.2)), Vector3(randf_range(-0.5, 0.5), randf_range(0.4, 0.9), randf_range(-0.5, 0.5)), Color(0.8, 0.8, 0.78, 0.2), randf_range(0.14, 0.22), 0.8, -0.4, 1.4, false, true, 2.4)


func steam(at: Vector3) -> void:
	_spawn_particle(at + Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2)), Vector3(randf_range(-0.25, 0.25), randf_range(1.0, 1.6), randf_range(-0.25, 0.25)), Color(0.85, 0.85, 0.88, 0.16), randf_range(0.35, 0.5), 2.2, -0.2, 0.6, false, true, 3.0)


func skid(at: Vector3, heading: Vector3) -> void:
	var mark: MeshInstance3D
	if _skids.size() < MAX_SKIDS:
		mark = MeshInstance3D.new()
		mark.mesh = _skid_mesh
		mark.material_override = _unshaded(Color(0.05, 0.05, 0.05, 0.55), true)
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mark)
		_skids.append(mark)
	else:
		mark = _skids[_skid_index]
		_skid_index = (_skid_index + 1) % MAX_SKIDS
	mark.visible = true
	var flat: Vector3 = Vector3(heading.x, 0.0, heading.z)
	if flat.length_squared() < 0.001:
		flat = Vector3.FORWARD
	# `at` is the tyre contact point on the collision floor. Road asphalt and paint are
	# visual layers up to 5.6 cm above it, so lift the mark clear of them.
	mark.global_transform = Transform3D(Basis.looking_at(flat.normalized(), Vector3.UP), at + Vector3(0.0, 0.062, 0.0))
