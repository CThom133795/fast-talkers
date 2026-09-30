extends StaticBody3D
## Reactive armory targets. "plate": steel popper that falls when hit and resets.
## "dummy": humanoid stand with a head zone that reports damage and resets when downed.
## Local +Z faces the shooter. `travel` > 0 slides the target along local X.

const MeshMerge = preload("res://scripts/mesh_merge.gd")

signal struck(amount: float, headshot: bool, downed: bool, at: Vector3)

var kind: String = "plate"
var plate_size: Vector2 = Vector2(0.5, 0.5)
var plate_height: float = 1.1
var travel: float = 0.0
var travel_speed: float = 1.2
var reset_delay: float = 2.2
var active: bool = true
var down: bool = false
var health: float = 100.0

var _pivot: Node3D
var _shapes: Array[CollisionShape3D] = []
var _materials: Array[StandardMaterial3D] = []
var _colors: Array[Color] = []
var _origin: Vector3
var _phase: float = 0.0
var _reset_timer: float = 0.0
var _flash: float = 0.0


func _ready() -> void:
	set_meta("practice_target", true)
	_origin = position
	_phase = randf() * TAU
	if kind == "dummy":
		_build_dummy()
	else:
		_build_plate()
	MeshMerge.merge_children(self)
	MeshMerge.merge_children(_pivot)


func _physics_process(delta: float) -> void:
	if not active:
		return
	if travel > 0.0:
		_phase += delta * travel_speed
		position = _origin + transform.basis.x * sin(_phase) * travel
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		for index: int in range(_materials.size()):
			_materials[index].albedo_color = _colors[index].lerp(Color(1.0, 0.95, 0.75), _flash / 0.12)
	if down:
		_reset_timer -= delta
		if _reset_timer <= 0.0:
			reset_target()


func hit_zone(at: Vector3) -> String:
	if kind == "dummy" and at.y - global_position.y > 1.55:
		return "head"
	return "body"


func take_hit(amount: float, at: Vector3, headshot: bool) -> void:
	if down:
		return
	_flash = 0.12
	var downed: bool = false
	if kind == "plate":
		downed = true
	else:
		health -= amount
		downed = health <= 0.0
	if downed:
		down = true
		_reset_timer = reset_delay
		for shape: CollisionShape3D in _shapes:
			shape.set_deferred("disabled", true)
		var tween: Tween = create_tween()
		tween.tween_property(_pivot, "rotation:x", -1.45 if kind == "plate" else -1.25, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	struck.emit(amount, headshot, downed, at)


func take_damage(amount: float) -> void:
	take_hit(amount, global_position + Vector3.UP, false)


func reset_target() -> void:
	down = false
	health = 100.0
	for shape: CollisionShape3D in _shapes:
		shape.set_deferred("disabled", false)
	var tween: Tween = create_tween()
	tween.tween_property(_pivot, "rotation:x", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_plate() -> void:
	var steel: Color = Color(0.78, 0.74, 0.62)
	var post: Color = Color(0.22, 0.25, 0.26)
	_visual(self, Vector3(0.08, plate_height - plate_size.y * 0.5, 0.08), Vector3(0, (plate_height - plate_size.y * 0.5) * 0.5, -0.06), post, false)
	_visual(self, Vector3(0.7, 0.06, 0.5), Vector3(0, 0.03, -0.06), post, false)
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, plate_height - plate_size.y * 0.5, 0)
	add_child(_pivot)
	_visual(_pivot, Vector3(plate_size.x, plate_size.y, 0.035), Vector3(0, plate_size.y * 0.5, 0), steel, true)
	_visual(_pivot, Vector3(plate_size.x * 0.34, plate_size.y * 0.34, 0.01), Vector3(0, plate_size.y * 0.5, 0.022), Color(0.85, 0.36, 0.2), true)
	_add_shape(Vector3(plate_size.x, plate_size.y, 0.08), Vector3(0, plate_height, 0))


func _build_dummy() -> void:
	var canvas: Color = Color(0.74, 0.64, 0.46)
	var stand: Color = Color(0.25, 0.27, 0.27)
	_visual(self, Vector3(0.9, 0.06, 0.5), Vector3(0, 0.03, 0), stand, false)
	_visual(self, Vector3(0.08, 0.5, 0.08), Vector3(0, 0.28, 0), stand, false)
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 0.5, 0)
	add_child(_pivot)
	_visual(_pivot, Vector3(0.22, 0.5, 0.2), Vector3(-0.13, 0.25, 0), canvas.darkened(0.2), true)
	_visual(_pivot, Vector3(0.22, 0.5, 0.2), Vector3(0.13, 0.25, 0), canvas.darkened(0.2), true)
	_visual(_pivot, Vector3(0.6, 0.62, 0.26), Vector3(0, 0.82, 0), canvas, true)
	_visual(_pivot, Vector3(0.3, 0.3, 0.27), Vector3(0, 1.27, 0), canvas.lightened(0.1), true)
	_visual(_pivot, Vector3(0.2, 0.2, 0.01), Vector3(0, 0.88, 0.135), Color(0.8, 0.22, 0.18), true)
	_visual(_pivot, Vector3(0.1, 0.1, 0.01), Vector3(0, 1.28, 0.14), Color(0.8, 0.22, 0.18), true)
	for side: float in [-1.0, 1.0]:
		_visual(_pivot, Vector3(0.14, 0.5, 0.16), Vector3(side * 0.38, 0.8, 0), canvas.darkened(0.12), true)
	_add_shape(Vector3(0.62, 1.12, 0.3), Vector3(0, 1.06, 0))
	_add_shape(Vector3(0.3, 0.32, 0.3), Vector3(0, 1.77, 0))


func _add_shape(size: Vector3, at: Vector3) -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	add_child(shape)
	_shapes.append(shape)


func _visual(parent: Node3D, size: Vector3, at: Vector3, color: Color, reactive: bool) -> void:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5 if kind == "plate" else 0.95
	material.metallic = 0.4 if kind == "plate" and reactive else 0.0
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	if reactive:
		_materials.append(material)
		_colors.append(color)
