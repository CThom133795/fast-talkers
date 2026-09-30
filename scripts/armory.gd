extends Node3D
## The free-roam target range in HALCYON ARMS' outdoor yard (East Shore, behind the gun store; see
## scripts/buildings/gunstore.gd). Static props plus reactive targets; main.gd connects each target's
## `struck` signal. Shooters stand west of the firing line and face east, so targets use yaw -PI/2.
##
## Two groups, because the range only looks like a test level in free roam:
##   - furniture: the firing benches and their steel legs. Ordinary things at any range; always there.
##   - dressing: targets, plates, the rack and its board, painted lines, distance and firing-line
##     labels, the "LONG RANGE" signage. Visible, solid and active in free roam; hidden, with no
##     collision, and inactive in contract and online matches (`set_mode`).
## The layout is the 0.5 Midtown armory's, translated by ORIGIN into the yard, so main.gd's
## SPAWN / RACK / LONG_LINE_X keep their meaning.

const TargetScript = preload("res://scripts/range_target.gd")
const MeshMerge = preload("res://scripts/mesh_merge.gd")
## The old lot's (0,0,0) in the yard (world coordinates). The firing line is at x = 300.
const ORIGIN: Vector3 = Vector3(286.5, 0.0, -30.0)
## Where a free-roam player starts (the firing line) and the rearm rack, in world coordinates
## (the 0.5 values (12.8, 0.1, -32.5) and (13.2, 0, -42.2) plus ORIGIN).
const SPAWN: Vector3 = Vector3(299.3, 0.1, -62.5)
const RACK: Vector3 = Vector3(299.7, 0.0, -72.2)
## The long-range firing line: x is LONG_LINE_X and its centre is LONG_LINE.
const LONG_LINE_X: float = 298.5
const LONG_LINE: Vector3 = Vector3(298.5, 0.0, -45.0)
const FACE_WEST: float = -PI * 0.5

var targets: Array[StaticBody3D] = []
## The five small plates at 8 m, used by the timed plate-rack challenge.
var rack: Array[StaticBody3D] = []
## "free_roam", "contract" or "online".
var mode: String = "free_roam"
var dressing: Node3D
var furniture: Node3D
var _materials: Dictionary = {}
var _layers: Dictionary = {}


func _ready() -> void:
	furniture = Node3D.new()
	furniture.name = "RangeFurniture"
	furniture.position = ORIGIN
	add_child(furniture)
	dressing = Node3D.new()
	dressing.name = "RangeDressing"
	dressing.position = ORIGIN
	add_child(dressing)
	_build_yard()
	_build_rack()
	_build_long_range()
	MeshMerge.merge_children(furniture)
	MeshMerge.merge_children(dressing)


func reset_targets() -> void:
	for target: StaticBody3D in targets:
		target.call("reset_target")


## Shows and arms the range dressing (free roam) or hides and disarms it (matches).
func set_mode(new_mode: String) -> void:
	mode = new_mode
	set_open(new_mode == "free_roam")


func set_open(open: bool) -> void:
	dressing.visible = open
	for body: Node in _collision_bodies(dressing):
		var object: CollisionObject3D = body as CollisionObject3D
		if open:
			if _layers.has(object):
				object.collision_layer = int(_layers[object])
		else:
			if not _layers.has(object):
				_layers[object] = object.collision_layer
			object.collision_layer = 0
	for target: StaticBody3D in targets:
		target.set("active", open)
		if not open:
			target.call("reset_target")


## True while the dressing is up and the targets can be hit.
func is_open() -> bool:
	return dressing.visible


func _collision_bodies(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in root.get_children():
		if child is CollisionObject3D:
			found.append(child)
		found.append_array(_collision_bodies(child))
	return found


func _material(color: Color, roughness: float = 0.85) -> StandardMaterial3D:
	var key: String = str(color) + str(roughness)
	if not _materials.has(key):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = roughness
		_materials[key] = material
	return _materials[key] as StandardMaterial3D


func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color, solid: bool = false) -> void:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color)
	mesh.position = at
	parent.add_child(mesh)
	if solid:
		var body: StaticBody3D = StaticBody3D.new()
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box_shape: BoxShape3D = BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.position = at
		body.add_child(shape)
		parent.add_child(body)


func _label(words: String, at: Vector3, font_size: int, color: Color, yaw: float = 0.0, flat: bool = false, billboard: bool = false) -> void:
	var label: Label3D = Label3D.new()
	label.text = words
	label.font_size = font_size
	label.pixel_size = 0.012
	label.modulate = color
	label.outline_size = 6
	label.outline_modulate = Color(0.1, 0.12, 0.13)
	label.position = at
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.rotation = Vector3(-PI * 0.5 if flat else 0.0, yaw, 0.0)
	if billboard:
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	dressing.add_child(label)


func _target(kind: String, at: Vector3, size: Vector2 = Vector2(0.5, 0.5), height: float = 1.1, travel: float = 0.0) -> StaticBody3D:
	var target: StaticBody3D = TargetScript.new()
	target.set("kind", kind)
	target.set("plate_size", size)
	target.set("plate_height", height)
	target.set("travel", travel)
	target.position = at
	target.rotation.y = FACE_WEST
	dressing.add_child(target)
	targets.append(target)
	return target


func _build_yard() -> void:
	var paint: Color = Color(0.93, 0.78, 0.36)
	var bench: Color = Color(0.36, 0.3, 0.22)
	var steel: Color = Color(0.24, 0.27, 0.28)
	# Firing bench in two segments with a walk-through gap into the range.
	for center_z: float in [-38.5, -27.5]:
		_box(furniture, Vector3(14.2, 0.92, center_z), Vector3(0.75, 0.08, 6.0), bench, true)
		for leg_z: float in [-2.6, 2.6]:
			_box(furniture, Vector3(14.2, 0.45, center_z + leg_z), Vector3(0.6, 0.86, 0.08), steel, true)
	_box(dressing, Vector3(13.55, 0.055, -33.0), Vector3(0.12, 0.015, 18.0), paint)
	for metres: int in [5, 10, 15]:
		_box(dressing, Vector3(13.55 + metres, 0.052, -33.0), Vector3(0.06, 0.012, 18.0), Color(0.62, 0.6, 0.52))
		_label("%d M" % metres, Vector3(13.2 + metres, 0.07, -24.6), 64, paint, -PI * 0.5, true)
	_label("RANGE", Vector3(10.4, 3.1, -44.2), 64, Color(0.96, 0.84, 0.55), -PI * 0.5, false)
	_label("FIRING LINE", Vector3(13.2, 0.07, -33.0), 56, paint, -PI * 0.5, true)
	# Plate rack at 8 m, dummies at 12 m, heavy plates, one mover.
	for index: int in range(5):
		var rack_plate: StaticBody3D = _target("plate", Vector3(21.0, 0.03, -41.2 + index * 0.8), Vector2(0.32, 0.32), 1.15)
		rack_plate.set("reset_delay", 3.5)
		rack.append(rack_plate)
	_box(dressing, Vector3(21.0, 1.0, -39.6), Vector3(0.1, 0.06, 4.2), steel)
	for z: float in [-35.5, -33.0, -30.5]:
		_target("dummy", Vector3(25.0, 0.03, z))
	_target("plate", Vector3(30.8, 0.03, -38.0), Vector2(0.7, 0.7), 1.3)
	_target("plate", Vector3(30.8, 0.03, -27.5), Vector2(0.7, 0.7), 1.3)
	var mover: StaticBody3D = _target("plate", Vector3(21.0, 0.03, -27.0), Vector2(0.5, 0.5), 1.25, 2.0)
	mover.set("travel_speed", 1.3)
	_box(dressing, Vector3(21.0, 0.06, -27.0), Vector3(0.2, 0.06, 4.6), steel)
	_target("dummy", Vector3(17.5, 0.03, -25.2))
	_label("LONG RANGE  →", Vector3(15.5, 1.9, -23.2), 40, Color(0.6, 0.86, 0.8), -PI * 0.5, false)


func _build_rack() -> void:
	var frame: Color = Color(0.2, 0.24, 0.24)
	var at: Vector3 = RACK - ORIGIN
	_box(dressing, at + Vector3(0, 1.05, 0), Vector3(1.9, 2.1, 0.18), frame, true)
	_box(dressing, at + Vector3(0, 1.05, 0.1), Vector3(1.7, 1.9, 0.02), Color(0.12, 0.2, 0.2))
	# Silhouettes of the five weapons, shortest at the top.
	var lengths: Array[float] = [0.34, 0.6, 0.95, 1.05, 1.15]
	for index: int in range(lengths.size()):
		var y: float = 1.72 - index * 0.3
		_box(dressing, at + Vector3(0, y, 0.13), Vector3(lengths[index], 0.08, 0.04), Color(0.08, 0.09, 0.1))
		_box(dressing, at + Vector3(lengths[index] * 0.22, y - 0.07, 0.13), Vector3(0.05, 0.1, 0.04), Color(0.08, 0.09, 0.1))
	_box(dressing, at + Vector3(0, 0.45, 0.35), Vector3(1.6, 0.9, 0.5), Color(0.28, 0.33, 0.3), true)
	_label("ARMORY", at + Vector3(0, 2.3, 0.12), 40, Color(0.96, 0.75, 0.39))
	_label("E  REARM", at + Vector3(0, 0.92, 0.61), 26, Color(0.6, 0.86, 0.8))


func _build_long_range() -> void:
	var paint: Color = Color(0.95, 0.95, 0.9)
	var line: Vector3 = LONG_LINE - ORIGIN
	_box(dressing, Vector3(line.x, 0.05, line.z), Vector3(0.22, 0.015, 12.0), paint)
	_label("LONG RANGE  →", Vector3(line.x - 0.8, 0.07, line.z), 80, Color(0.95, 0.79, 0.43), -PI * 0.5, true)
	var plates: Array[Vector3] = [Vector3(38.0, 0.03, -8.3), Vector3(52.0, 0.03, -21.8), Vector3(66.0, 0.03, -8.3), Vector3(78.6, 0.03, -15.0)]
	for index: int in range(plates.size()):
		var at: Vector3 = plates[index]
		var size: Vector2 = Vector2(1.3, 1.3) if index == plates.size() - 1 else Vector2(0.8, 0.8)
		_target("plate", at, size, 1.55)
		_label("%d M" % int(round(at.x - (LONG_LINE_X - ORIGIN.x))), at + Vector3(0, 2.75, 0), 70, Color(0.95, 0.79, 0.43), 0.0, false, true)
