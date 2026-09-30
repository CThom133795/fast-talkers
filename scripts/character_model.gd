extends Node3D
## Crew member for a gritty crime game: a procedural SKINNED human. One continuous mesh on
## a 17-bone Skeleton3D, realistic proportions (1.8 m, about 7.5 heads tall), a sculpted head
## with a painted face texture, clothing coloured per crew (suits, tracksuit, linen shirt),
## hats and hair as rigid parts on the head bone. No ink outlines: it should read as a
## person, not a toy. Procedural spring animation drives the bones (walk, strafe, idle,
## aim, flinch, sit/ride, fall). Pure visuals: owners add collision and call `animate()`.
## Origin at the feet, facing -Z. Used by practice bots, drivers, the title lineup, and by
## remote players in multiplayer.

const Factions = preload("res://scripts/factions.gd")
const MeshKit = preload("res://scripts/mesh_kit.gd")

enum Bone { HIPS, SPINE, CHEST, NECK, HEAD, UPPERARM_L, FOREARM_L, HAND_L, UPPERARM_R, FOREARM_R, HAND_R, THIGH_L, SHIN_L, FOOT_L, THIGH_R, SHIN_R, FOOT_R }
const BONE_NAMES: Array[String] = ["hips", "spine", "chest", "neck", "head", "upperarm_l", "forearm_l", "hand_l", "upperarm_r", "forearm_r", "hand_r", "thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r"]
const BONE_PARENTS: Array[int] = [-1, 0, 1, 2, 3, 2, 5, 6, 2, 8, 9, 0, 11, 12, 0, 14, 15]
## Rest joint positions in model space (arms hanging, feet apart a little).
const REST: Array[Vector3] = [
	Vector3(0, 0.97, 0), Vector3(0, 1.1, 0), Vector3(0, 1.3, 0), Vector3(0, 1.5, 0), Vector3(0, 1.585, 0),
	Vector3(-0.19, 1.43, 0), Vector3(-0.21, 1.145, 0.01), Vector3(-0.222, 0.88, 0.02),
	Vector3(0.19, 1.43, 0), Vector3(0.21, 1.145, 0.01), Vector3(0.222, 0.88, 0.02),
	Vector3(-0.095, 0.94, 0), Vector3(-0.1, 0.51, 0.005), Vector3(-0.105, 0.085, 0.0),
	Vector3(0.095, 0.94, 0), Vector3(0.1, 0.51, 0.005), Vector3(0.105, 0.085, 0.0),
]
const RING: int = 12

var crew: String = "morris"
## Materials an owner can tint (hit flashes); `colors` holds their resting albedo.
var materials: Array[StandardMaterial3D] = []
var colors: Array[Color] = []
var skeleton: Skeleton3D
## Kept for owners of the old rig: `arms` is the skeleton; joints are bone indices.
var arms: Node3D
var hips: int = Bone.HIPS
var torso: int = Bone.CHEST
var head: int = Bone.HEAD
var shoulder_l: int = Bone.UPPERARM_L
var shoulder_r: int = Bone.UPPERARM_R
var elbow_l: int = Bone.FOREARM_L
var elbow_r: int = Bone.FOREARM_R
var leg_l: int = Bone.THIGH_L
var leg_r: int = Bone.THIGH_R
var knee_l: int = Bone.SHIN_L
var knee_r: int = Bone.SHIN_R
var personality: float = 0.0
## Sitting in a vehicle seat (hands forward to the wheel) or astride a motorcycle.
var seated: bool = false
var riding: bool = false

var _angles: Array[Vector3] = []
var _velocities: Array[Vector3] = []
var _hip_offset: Vector3 = Vector3.ZERO
var _phase: float = 0.0
var _time: float = 0.0
var _dead: bool = false
var _body: SurfaceTool
var _head_surface: SurfaceTool
var _weapon: Node3D


func build(crew_id: String, armed: bool = true) -> void:
	crew = crew_id
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	materials.clear()
	colors.clear()
	_dead = false
	scale = Vector3.ONE
	var c: Dictionary = Factions.get_crew(crew)
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	arms = skeleton
	for index: int in range(BONE_NAMES.size()):
		skeleton.add_bone(BONE_NAMES[index])
		var parent: int = BONE_PARENTS[index]
		if parent >= 0:
			skeleton.set_bone_parent(index, parent)
		var offset: Vector3 = REST[index] - (REST[parent] if parent >= 0 else Vector3.ZERO)
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, offset))
	skeleton.reset_bone_poses()
	_angles.clear()
	_velocities.clear()
	for index: int in range(BONE_NAMES.size()):
		_angles.append(Vector3.ZERO)
		_velocities.append(Vector3.ZERO)
	_body = SurfaceTool.new()
	_body.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	_body.begin(Mesh.PRIMITIVE_TRIANGLES)
	_head_surface = SurfaceTool.new()
	_head_surface.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	_head_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_build_body(c)
	_build_head(c)
	var mesh: ArrayMesh = ArrayMesh.new()
	_body.commit(mesh)
	_head_surface.commit(mesh)
	var body_material: StandardMaterial3D = StandardMaterial3D.new()
	body_material.vertex_color_use_as_albedo = true
	body_material.roughness = 0.78
	body_material.rim_enabled = true
	body_material.rim = 0.08
	body_material.rim_tint = 0.5
	var face_material: StandardMaterial3D = StandardMaterial3D.new()
	face_material.albedo_texture = _face_texture(c)
	face_material.roughness = 0.62
	face_material.rim_enabled = true
	face_material.rim = 0.08
	face_material.rim_tint = 0.5
	mesh.surface_set_material(0, body_material)
	mesh.surface_set_material(1, face_material)
	for material: StandardMaterial3D in [body_material, face_material]:
		materials.append(material)
		colors.append(material.albedo_color)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "Body"
	instance.mesh = mesh
	skeleton.add_child(instance)
	instance.skeleton = NodePath("..")
	instance.skin = skeleton.create_skin_from_rest_transforms()
	if armed:
		_weapon = _build_sidearm()
	personality = float(absi(hash(crew)) % 100) / 100.0


# --- Mesh construction -------------------------------------------------------------------

## Weighted vertex into a surface: `bones` is up to four [bone, weight] pairs.
func _vertex(surface: SurfaceTool, position: Vector3, normal: Vector3, color: Color, bones: Array, uv: Vector2 = Vector2.ZERO) -> void:
	var indices: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var weights: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var total: float = 0.0
	for index: int in range(mini(bones.size(), 4)):
		indices[index] = int(bones[index][0])
		weights[index] = float(bones[index][1])
		total += weights[index]
	for index: int in range(4):
		weights[index] = weights[index] / maxf(total, 0.0001)
	surface.set_bones(indices)
	surface.set_weights(weights)
	surface.set_color(color)
	surface.set_normal(normal)
	surface.set_uv(uv)
	surface.add_vertex(position)


## A lofted tube through horizontal elliptical rings. Each ring: {"y", "c" (x/z centre),
## "r" (x/z radii), "bones", "color" (Callable(angle_from_front, ring) -> Color)}.
## Angles are measured from the front (-Z), positive towards +X.
func _tube(rings: Array, cap_bottom: bool = false, cap_top: bool = false) -> void:
	var grid: Array = []
	for ring: Dictionary in rings:
		var row: Array = []
		var center: Vector2 = ring.get("c", Vector2.ZERO)
		var radii: Vector2 = ring["r"]
		for segment: int in range(RING):
			var front_angle: float = TAU * segment / RING
			var local: Vector2 = Vector2(sin(front_angle) * radii.x, -cos(front_angle) * radii.y)
			var position: Vector3 = Vector3(center.x + local.x, float(ring["y"]), center.y + local.y)
			var normal: Vector3 = Vector3(sin(front_angle) / maxf(radii.x, 0.001), 0.0, -cos(front_angle) / maxf(radii.y, 0.001)).normalized()
			var shade: Callable = ring["color"]
			row.append([position, normal, shade.call(front_angle, ring)])
		grid.append(row)
	# Smooth normals from the actual surface (around x up), so slopes like the shoulders
	# and the waist shade correctly instead of looking cut from card.
	for index: int in range(grid.size()):
		for segment: int in range(RING):
			var around: Vector3 = (grid[index][(segment + 1) % RING][0] as Vector3) - (grid[index][(segment - 1 + RING) % RING][0] as Vector3)
			var up: Vector3 = (grid[mini(index + 1, grid.size() - 1)][segment][0] as Vector3) - (grid[maxi(index - 1, 0)][segment][0] as Vector3)
			var normal: Vector3 = up.cross(around).normalized()
			if normal.dot(grid[index][segment][1]) < 0.0:
				normal = -normal
			if normal.length() > 0.5:
				grid[index][segment][1] = normal
	for index: int in range(rings.size() - 1):
		var bones_a: Array = rings[index]["bones"]
		var bones_b: Array = rings[index + 1]["bones"]
		for segment: int in range(RING):
			var next: int = (segment + 1) % RING
			var a: Array = grid[index][segment]
			var b: Array = grid[index][next]
			var c: Array = grid[index + 1][next]
			var d: Array = grid[index + 1][segment]
			_quad(a, b, c, d, bones_a, bones_b)
	if cap_bottom:
		_cap(grid[0], rings[0], true)
	if cap_top:
		_cap(grid[grid.size() - 1], rings[rings.size() - 1], false)


func _quad(a: Array, b: Array, c: Array, d: Array, bones_ab: Array, bones_cd: Array) -> void:
	# Godot front faces wind clockwise seen from outside: flip any triangle facing in.
	for triangle: Array in [[a, bones_ab, d, bones_cd, c, bones_cd], [a, bones_ab, c, bones_cd, b, bones_ab]]:
		var p0: Vector3 = triangle[0][0]
		var p1: Vector3 = triangle[2][0]
		var p2: Vector3 = triangle[4][0]
		var outward: Vector3 = (triangle[0][1] as Vector3)
		var order: Array = [0, 2, 4]
		if (p1 - p0).cross(p2 - p0).dot(outward) > 0.0:
			order = [0, 4, 2]
		for slot: int in order:
			var vertex: Array = triangle[slot]
			_vertex(_body, vertex[0], vertex[1], vertex[2], triangle[slot + 1])


func _cap(row: Array, ring: Dictionary, bottom: bool) -> void:
	var center: Vector2 = ring.get("c", Vector2.ZERO)
	var middle: Vector3 = Vector3(center.x, float(ring["y"]), center.y)
	var normal: Vector3 = Vector3.DOWN if bottom else Vector3.UP
	for segment: int in range(RING):
		var a: Array = row[segment]
		var b: Array = row[(segment + 1) % RING]
		var points: Array = [middle, a[0], b[0]]
		if ((points[1] as Vector3) - middle).cross((points[2] as Vector3) - middle).dot(normal) > 0.0:
			points = [middle, b[0], a[0]]
		for point: Vector3 in points:
			_vertex(_body, point, normal, a[2], ring["bones"])


## Adds a primitive mesh (rounded box, sphere, cylinder...) rigidly bound to one bone.
func _rigid(mesh: Mesh, xform: Transform3D, bone: int, color: Color, surface: SurfaceTool = null) -> void:
	var target: SurfaceTool = surface if surface != null else _body
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var bones: Array = [[bone, 1.0]]
	if indices.is_empty():
		for index: int in range(vertices.size()):
			_vertex(target, xform * vertices[index], (xform.basis * normals[index]).normalized(), color, bones)
		return
	for index: int in indices:
		_vertex(target, xform * vertices[index], (xform.basis * normals[index]).normalized(), color, bones)


## A flat two-sided triangle in the XY plane (a shirt V, an open collar).
func _triangle(a: Vector2, b: Vector2, c: Vector2) -> ArrayMesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for points: Array in [[a, b, c], [a, c, b]]:
		var normal: Vector3 = Vector3.FORWARD if points[1] == b else Vector3.BACK
		for point: Vector2 in points:
			surface.set_normal(normal)
			surface.add_vertex(Vector3(point.x, point.y, 0.0))
	return surface.commit()


func _at(position: Vector3, rotation: Vector3 = Vector3.ZERO, size: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rotation).scaled(size), position)


func _solid(color: Color) -> Callable:
	return func(_angle: float, _ring: Dictionary) -> Color: return color


func _near(angle: float, target: float, width: float) -> bool:
	return absf(wrapf(angle - target, -PI, PI)) < width


func _build_body(c: Dictionary) -> void:
	var skin: Color = c["skin"]
	var pants: Color = c["pants"]
	var jacket: Color = c["jacket"]
	var shirt: Color = c["shirt"]
	var tie: Color = c["tie"]
	var accent: Color = c["accent"]
	var band: Color = c["color"]
	var shoes: Color = c["shoes"]
	var tracksuit: bool = crew == "kingsway"
	var linen: bool = crew == "solnegro"
	var suit: bool = crew == "morris" or crew == "kojimoto"
	var stripe_side: float = PI * 0.5
	# Legs: trousers taper from the hip to a slight flare at the shoe.
	for side: float in [-1.0, 1.0]:
		var thigh: int = Bone.THIGH_L if side < 0.0 else Bone.THIGH_R
		var shin: int = Bone.SHIN_L if side < 0.0 else Bone.SHIN_R
		var x: float = 0.095 * side
		var leg_color: Callable = func(angle: float, _ring: Dictionary) -> Color:
			if tracksuit and _near(angle, stripe_side * side, 0.28):
				return accent
			return pants
		var legs: Array = [
			{"y": 0.1, "c": Vector2(x * 1.08, 0.01), "r": Vector2(0.058, 0.064), "bones": [[shin, 1.0]], "color": leg_color},
			{"y": 0.22, "c": Vector2(x * 1.07, 0.008), "r": Vector2(0.052, 0.056), "bones": [[shin, 1.0]], "color": leg_color},
			{"y": 0.4, "c": Vector2(x * 1.05, 0.01), "r": Vector2(0.06, 0.066), "bones": [[shin, 1.0]], "color": leg_color},
			{"y": 0.51, "c": Vector2(x * 1.04, 0.0), "r": Vector2(0.061, 0.064), "bones": [[shin, 0.5], [thigh, 0.5]], "color": leg_color},
			{"y": 0.62, "c": Vector2(x * 1.02, 0.0), "r": Vector2(0.068, 0.072), "bones": [[thigh, 1.0]], "color": leg_color},
			{"y": 0.82, "c": Vector2(x, -0.004), "r": Vector2(0.083, 0.086), "bones": [[thigh, 1.0]], "color": leg_color},
			{"y": 0.93, "c": Vector2(x * 0.92, -0.004), "r": Vector2(0.092, 0.09), "bones": [[thigh, 0.7], [Bone.HIPS, 0.3]], "color": leg_color},
		]
		_tube(legs, true, false)
		# Shoes (boots for the cartel, white trainers for the Royals).
		var foot: int = Bone.FOOT_L if side < 0.0 else Bone.FOOT_R
		var shoe_height: float = 0.1 if not linen else 0.14
		_rigid(MeshKit.rounded_box(Vector3(0.1, shoe_height, 0.27), 0.035, 2), _at(Vector3(x * 1.1, shoe_height * 0.5, -0.045)), foot, shoes)
		_rigid(MeshKit.rounded_box(Vector3(0.104, 0.025, 0.28), 0.01, 1), _at(Vector3(x * 1.1, 0.012, -0.046)), foot, shoes.darkened(0.45) if not tracksuit else Color(0.92, 0.92, 0.9))
	# Torso: pelvis, waist, chest, shoulders. Clothing is painted by angle from the front.
	# Plain garment colours on the body; shirt fronts, ties and lapels are overlay panels
	# (vertex-colour boundaries on a coarse mesh smear into stains).
	var torso_color: Callable = func(_angle: float, ring: Dictionary) -> Color:
		var y: float = float(ring["y"])
		if linen:
			return pants if y < 0.96 else shirt
		return jacket
	var torso: Array = [
		{"y": 0.86, "r": Vector2(0.155, 0.105), "bones": [[Bone.HIPS, 1.0]], "color": torso_color},
		{"y": 0.95, "r": Vector2(0.166, 0.111), "bones": [[Bone.HIPS, 1.0]], "color": torso_color},
		{"y": 0.97, "r": Vector2(0.168, 0.112), "bones": [[Bone.HIPS, 1.0]], "color": torso_color},
		{"y": 1.08, "r": Vector2(0.152, 0.1), "bones": [[Bone.SPINE, 0.7], [Bone.HIPS, 0.3]], "color": torso_color},
		{"y": 1.18, "r": Vector2(0.158, 0.104), "bones": [[Bone.SPINE, 0.6], [Bone.CHEST, 0.4]], "color": torso_color},
		{"y": 1.3, "r": Vector2(0.172, 0.114), "bones": [[Bone.CHEST, 1.0]], "color": torso_color},
		{"y": 1.38, "r": Vector2(0.186, 0.114), "bones": [[Bone.CHEST, 1.0]], "color": torso_color},
		{"y": 1.43, "r": Vector2(0.186, 0.106), "bones": [[Bone.CHEST, 1.0]], "color": torso_color},
		{"y": 1.458, "r": Vector2(0.165, 0.096), "bones": [[Bone.CHEST, 1.0]], "color": torso_color},
		{"y": 1.478, "r": Vector2(0.13, 0.084), "bones": [[Bone.CHEST, 0.8], [Bone.NECK, 0.2]], "color": torso_color},
		{"y": 1.495, "r": Vector2(0.085, 0.07), "bones": [[Bone.CHEST, 0.6], [Bone.NECK, 0.4]], "color": torso_color},
	]
	_tube(torso, true, false)
	# Suit jacket skirt over the hips, and a belt for jeans and trackies.
	if suit:
		_tube([
			{"y": 0.83, "r": Vector2(0.178, 0.122), "bones": [[Bone.HIPS, 1.0]], "color": _solid(jacket)},
			{"y": 1.0, "r": Vector2(0.172, 0.117), "bones": [[Bone.HIPS, 0.6], [Bone.SPINE, 0.4]], "color": _solid(jacket)},
		])
	if linen or tracksuit:
		var belt: Color = Color(0.29, 0.18, 0.11) if linen else jacket.darkened(0.2)
		_tube([
			{"y": 0.955, "r": Vector2(0.171, 0.115), "bones": [[Bone.HIPS, 1.0]], "color": _solid(belt)},
			{"y": 0.99, "r": Vector2(0.171, 0.115), "bones": [[Bone.HIPS, 1.0]], "color": _solid(belt)},
		])
	if linen:
		_rigid(MeshKit.rounded_box(Vector3(0.07, 0.045, 0.012), 0.006, 1), _at(Vector3(0, 0.972, -0.118)), Bone.HIPS, band)
		# Open collar: a V of chest skin between the shirt's lapels.
		_rigid(_triangle(Vector2(-0.055, 0.0), Vector2(0.055, 0.0), Vector2(0.0, -0.13)), _at(Vector3(0, 1.49, -0.106), Vector3(-0.12, 0, 0)), Bone.CHEST, skin)
		for side: float in [-1.0, 1.0]:
			_rigid(MeshKit.rounded_box(Vector3(0.05, 0.1, 0.006), 0.002, 1), _at(Vector3(side * 0.045, 1.42, -0.118), Vector3(0, 0, side * 0.45)), Bone.CHEST, shirt.darkened(0.06))
	if suit:
		# Shirt front and tie in the jacket's V, lapels either side, buttons below.
		_rigid(_triangle(Vector2(-0.075, 0.0), Vector2(0.075, 0.0), Vector2(0.0, -0.3)), _at(Vector3(0, 1.485, -0.111), Vector3(-0.08, 0, 0)), Bone.CHEST, shirt)
		if crew == "morris":
			_rigid(MeshKit.rounded_box(Vector3(0.034, 0.24, 0.008), 0.003, 1), _at(Vector3(0, 1.36, -0.122), Vector3(-0.08, 0, 0)), Bone.CHEST, tie)
			_rigid(MeshKit.rounded_box(Vector3(0.04, 0.03, 0.012), 0.004, 1), _at(Vector3(0, 1.475, -0.113)), Bone.CHEST, tie.darkened(0.15))
		else:
			for dot: Vector3 in [Vector3(-0.02, 1.43, -0.122), Vector3(0.022, 1.36, -0.122), Vector3(-0.012, 1.3, -0.122)]:
				_rigid(MeshKit.sphere(0.012, 0.024, 8, 4), _at(dot, Vector3.ZERO, Vector3(1, 1, 0.4)), Bone.CHEST, accent)
		for side: float in [-1.0, 1.0]:
			_rigid(MeshKit.rounded_box(Vector3(0.05, 0.3, 0.01), 0.003, 1), _at(Vector3(side * 0.06, 1.345, -0.117), Vector3(-0.08, 0, side * 0.24)), Bone.CHEST, jacket.lightened(0.14))
		for button: float in [1.12, 1.05]:
			_rigid(MeshKit.sphere(0.008, 0.016, 6, 3), _at(Vector3(0, button, -0.107)), Bone.SPINE, jacket.darkened(0.5))
	if tracksuit:
		_rigid(MeshKit.rounded_box(Vector3(0.008, 0.46, 0.006), 0.002, 1), _at(Vector3(0, 1.22, -0.118)), Bone.CHEST, Color(0.85, 0.85, 0.82))
	# Neck and collar.
	_tube([
		{"y": 1.47, "r": Vector2(0.06, 0.062), "bones": [[Bone.NECK, 1.0]], "color": _solid(skin)},
		{"y": 1.6, "r": Vector2(0.054, 0.058), "c": Vector2(0, 0.008), "bones": [[Bone.NECK, 0.5], [Bone.HEAD, 0.5]], "color": _solid(skin)},
	])
	if not tracksuit:
		var collar: Color = shirt if not linen else shirt.darkened(0.04)
		_tube([
			{"y": 1.475, "r": Vector2(0.071, 0.072), "bones": [[Bone.NECK, 1.0]], "color": _solid(collar)},
			{"y": 1.545, "r": Vector2(0.065, 0.068), "bones": [[Bone.NECK, 1.0]], "color": _solid(collar)},
		])
	else:
		_tube([
			{"y": 1.46, "r": Vector2(0.075, 0.075), "bones": [[Bone.NECK, 1.0]], "color": _solid(jacket)},
			{"y": 1.53, "r": Vector2(0.066, 0.068), "bones": [[Bone.NECK, 1.0]], "color": _solid(jacket)},
		])
	# Gold chains for the Royals and the cartel.
	if tracksuit or linen:
		_rigid(MeshKit.torus(0.075, 0.084, 18, 4), _at(Vector3(0, 1.43, -0.03), Vector3(1.2, 0, 0)), Bone.CHEST, Color("e9c24a"))
	# Arms: sleeves to the wrist (rolled on the cartel's shirts), armband on the left.
	for side: float in [-1.0, 1.0]:
		var upper: int = Bone.UPPERARM_L if side < 0.0 else Bone.UPPERARM_R
		var fore: int = Bone.FOREARM_L if side < 0.0 else Bone.FOREARM_R
		var hand: int = Bone.HAND_L if side < 0.0 else Bone.HAND_R
		var shoulder: Vector3 = REST[upper]
		var elbow: Vector3 = REST[fore]
		var wrist: Vector3 = REST[hand]
		var sleeve: Color = c["sleeve"]
		var sleeve_color: Callable = func(angle: float, ring: Dictionary) -> Color:
			var y: float = float(ring["y"])
			if side < 0.0 and y > 1.219 and y < 1.301:
				return band
			if tracksuit and _near(angle, stripe_side * side, 0.3):
				return accent
			if linen and y < 1.065:
				return skin
			return sleeve
		# Rings at colour boundaries come in close pairs so the armband and cuffs have edges.
		var heights: Array[float] = [wrist.y + 0.02, 1.0, 1.062, 1.068, elbow.y, 1.2, 1.218, 1.222, 1.298, 1.302, 1.36, shoulder.y - 0.035, shoulder.y + 0.025]
		var arm: Array = []
		for y: float in heights:
			var t_fore: float = clampf((y - wrist.y) / (elbow.y - wrist.y), 0.0, 1.0)
			var t_upper: float = clampf((y - elbow.y) / (shoulder.y - elbow.y), 0.0, 1.0)
			var at: Vector2
			var radius: Vector2
			var weights: Array
			if y <= elbow.y:
				at = Vector2(lerpf(wrist.x, elbow.x, t_fore), lerpf(wrist.z, elbow.z, t_fore))
				radius = Vector2(lerpf(0.033, 0.044, sqrt(t_fore)), lerpf(0.036, 0.046, sqrt(t_fore)))
				weights = [[fore, 1.0]] if t_fore < 0.85 else [[fore, 0.5], [upper, 0.5]]
				if t_fore < 0.1:
					weights = [[fore, 0.7], [hand, 0.3]]
			else:
				at = Vector2(lerpf(elbow.x, shoulder.x * 0.96, t_upper), lerpf(elbow.z, 0.0, t_upper))
				radius = Vector2(lerpf(0.046, 0.06, t_upper), lerpf(0.047, 0.062, t_upper))
				weights = [[upper, 1.0]] if t_upper < 0.8 else [[upper, 0.7], [Bone.CHEST, 0.3]]
			if y > shoulder.y:
				at.x = shoulder.x * 0.84
				radius = Vector2(0.048, 0.058)
				weights = [[upper, 0.4], [Bone.CHEST, 0.6]]
			arm.append({"y": y, "c": at, "r": radius, "bones": weights, "color": sleeve_color})
		_tube(arm, true, true)
		# Deltoid cap: rounds the shoulder line into the arm.
		var sleeve_top: Color = sleeve_color.call(0.0, {"y": shoulder.y})
		_rigid(MeshKit.sphere(0.062, 0.124, 12, 6), _at(Vector3(shoulder.x * 0.93, shoulder.y - 0.012, 0.0), Vector3.ZERO, Vector3(1.0, 0.85, 1.05)), upper, sleeve_top)
		# Hand: palm, finger block, thumb. Gloves where the crew wears them.
		var glove: Color = c["glove"]
		var hand_x: float = wrist.x + side * 0.004
		_rigid(MeshKit.rounded_box(Vector3(0.035, 0.085, 0.078), 0.015, 2), _at(Vector3(hand_x, wrist.y - 0.052, wrist.z)), hand, glove)
		_rigid(MeshKit.rounded_box(Vector3(0.03, 0.075, 0.07), 0.013, 2), _at(Vector3(hand_x - side * 0.003, wrist.y - 0.125, wrist.z - 0.002), Vector3(0.12, 0, 0)), hand, glove)
		_rigid(MeshKit.capsule(0.013, 0.07, 8, 2), _at(Vector3(hand_x - side * 0.004, wrist.y - 0.06, wrist.z - 0.045), Vector3(0.5, 0, 0)), hand, glove)


func _build_head(c: Dictionary) -> void:
	var skin: Color = c["skin"]
	var center: Vector3 = Vector3(0, 1.66, -0.008)
	var radii: Vector3 = Vector3(0.088, 0.132, 0.104)
	var latitudes: int = 14
	var longitudes: int = 20
	var grid: Array = []
	for lat: int in range(latitudes + 1):
		var row: Array = []
		var v: float = float(lat) / latitudes
		var polar: float = v * PI
		for lon: int in range(longitudes + 1):
			var u: float = float(lon) / longitudes
			var around: float = (u - 0.5) * TAU
			# Unit sphere, front = -Z at u = 0.5.
			var unit: Vector3 = Vector3(sin(polar) * sin(around), cos(polar), -sin(polar) * cos(around))
			var point: Vector3 = _sculpt(unit)
			var position: Vector3 = center + Vector3(point.x * radii.x, point.y * radii.y, point.z * radii.z)
			var normal: Vector3 = Vector3(point.x / radii.x, point.y / radii.y, point.z / radii.z).normalized()
			row.append([position, normal, Vector2(u, v)])
		grid.append(row)
	var bones: Array = [[Bone.HEAD, 1.0]]
	for lat: int in range(latitudes):
		for lon: int in range(longitudes):
			var a: Array = grid[lat][lon]
			var b: Array = grid[lat][lon + 1]
			var cc: Array = grid[lat + 1][lon + 1]
			var d: Array = grid[lat + 1][lon]
			for triangle: Array in [[a, b, cc], [a, cc, d]]:
				var p0: Vector3 = triangle[0][0]
				var p1: Vector3 = triangle[1][0]
				var p2: Vector3 = triangle[2][0]
				var outward: Vector3 = ((p0 + p1 + p2) / 3.0 - center).normalized()
				var order: Array = [0, 1, 2]
				if (p1 - p0).cross(p2 - p0).dot(outward) > 0.0:
					order = [0, 2, 1]
				for slot: int in order:
					var vertex: Array = triangle[slot]
					_vertex(_head_surface, vertex[0], vertex[1], Color.WHITE, bones, vertex[2])
	# Ears and a shallow bridge; the sculpted face supplies the tip. A separate ball on
	# the nose made the entire head read like a toy from normal play distance.
	for side: float in [-1.0, 1.0]:
		_rigid(MeshKit.sphere(0.024, 0.046, 10, 5), _at(center + Vector3(side * 0.087, -0.016, 0.009), Vector3.ZERO, Vector3(0.42, 1.0, 0.68)), Bone.HEAD, skin.darkened(0.045))
	_rigid(MeshKit.rounded_box(Vector3(0.014, 0.041, 0.012), 0.005, 2), _at(center + Vector3(0, -0.019, -0.104), Vector3(-0.25, 0, 0)), Bone.HEAD, skin)
	_build_hat(c, center)


## Shapes a unit sphere into a head: a narrower jaw and chin, a fuller skull at the back,
## a brow ridge, cheekbones and a nose bridge.
func _sculpt(unit: Vector3) -> Vector3:
	var point: Vector3 = unit
	if point.y < -0.1:
		# A square-ish jaw that stays wider than the neck, a chin that comes forward, and a
		# flatter underside: the lower head must not read as more neck.
		var jaw: float = clampf((-point.y - 0.1) / 0.9, 0.0, 1.0)
		point.x *= lerpf(1.0, 1.12, jaw)
		if point.z < 0.0:
			point.z *= lerpf(1.0, 1.05, jaw)
		else:
			point.z *= lerpf(1.0, 0.55, jaw)
		if point.y < -0.7:
			point.y = -0.7 + (point.y + 0.7) * 0.6
	if point.z > 0.0 and point.y > -0.4:
		point.z *= 1.07
	if point.z < 0.0:
		var front: float = -point.z
		point.z -= 0.07 * exp(-pow((point.y - 0.18) / 0.1, 2.0)) * front
		point.z -= 0.09 * exp(-(pow(point.x / 0.1, 2.0) + pow((point.y + 0.05) / 0.2, 2.0))) * front
		point.z += 0.05 * exp(-(pow((absf(point.x) - 0.33) / 0.12, 2.0) + pow((point.y - 0.06) / 0.08, 2.0))) * front
		point.x *= 1.0 + 0.04 * exp(-pow((point.y + 0.05) / 0.15, 2.0))
	return point


func _build_hat(c: Dictionary, center: Vector3) -> void:
	var hat: Color = c["hat_color"]
	var hair: Color = c["hair"]
	var top: float = center.y + 0.1
	match str(c["hat"]):
		"fedora":
			_rigid(MeshKit.cylinder(0.128, 0.128, 0.009, 24), _at(Vector3(0, top - 0.006, center.z)), Bone.HEAD, hat)
			_rigid(MeshKit.cylinder(0.084, 0.091, 0.071, 20), _at(Vector3(0, top + 0.032, center.z)), Bone.HEAD, hat)
			_rigid(MeshKit.cylinder(0.093, 0.093, 0.018, 20), _at(Vector3(0, top + 0.009, center.z)), Bone.HEAD, c["color"].darkened(0.35))
		"cap":
			_rigid(MeshKit.sphere(0.089, 0.064, 16, 6, true), _at(Vector3(0, top - 0.037, center.z + 0.004), Vector3.ZERO, Vector3(1.0, 1.0, 1.08)), Bone.HEAD, hat.darkened(0.18))
			_rigid(MeshKit.rounded_box(Vector3(0.112, 0.009, 0.067), 0.005, 1), _at(Vector3(0, top - 0.032, center.z - 0.098), Vector3(-0.1, 0, 0)), Bone.HEAD, hat.darkened(0.25))
		"cowboy":
			_rigid(MeshKit.cylinder(0.145, 0.145, 0.009, 24), _at(Vector3(0, top - 0.004, center.z), Vector3.ZERO, Vector3(1.0, 1.0, 1.1)), Bone.HEAD, hat)
			for side: float in [-1.0, 1.0]:
				_rigid(MeshKit.rounded_box(Vector3(0.036, 0.009, 0.21), 0.005, 1), _at(Vector3(side * 0.134, top + 0.008, center.z), Vector3(0, 0, side * 0.3)), Bone.HEAD, hat)
			_rigid(MeshKit.cylinder(0.078, 0.091, 0.073, 20), _at(Vector3(0, top + 0.034, center.z)), Bone.HEAD, hat)
			_rigid(MeshKit.cylinder(0.092, 0.092, 0.016, 20), _at(Vector3(0, top + 0.008, center.z)), Bone.HEAD, c["color"].darkened(0.4))
		"pompadour":
			_rigid(MeshKit.capsule(0.043, 0.13, 12, 3), _at(Vector3(0, top - 0.018, center.z - 0.022), Vector3(PI * 0.5 + 0.25, 0, 0), Vector3(1.4, 1.0, 1.0)), Bone.HEAD, hair)


## A painted face wrapped cylindrically round the head: hair and hairline, brows,
## eyes, nose shading, lips, a jaw shadow. Crews vary by skin, hair, stubble and shades.
func _face_texture(c: Dictionary) -> ImageTexture:
	var size: int = 256
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGB8)
	var skin: Color = c["skin"]
	var hair: Color = c["hair"]
	var shades: bool = crew == "kojimoto"
	var stubble: bool = crew == "morris" or crew == "solnegro"
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(crew)
	for y: int in range(size):
		for x: int in range(size):
			var u: float = (float(x) + 0.5) / size
			var v: float = (float(y) + 0.5) / size
			var from_front: float = u - 0.5
			var color: Color = skin
			# Subtle skin shading: warmer cheeks, darker under the jaw and at the sides.
			color = color.darkened(clampf(absf(from_front) * 0.35, 0.0, 0.18))
			color = color.lerp(Color(0.65, 0.38, 0.32), 0.035 * exp(-(pow((absf(from_front) - 0.08) / 0.04, 2.0) + pow((v - 0.6) / 0.05, 2.0))))
			if v > 0.76:
				color = color.darkened((v - 0.76) * 0.5)
			if stubble and v > 0.64 and v < 0.84 and absf(from_front) < 0.13:
				color = color.lerp(hair, 0.11 + rng.randf() * 0.05)
			# Hairline: low at the back, a clean line across the brow.
			var hairline: float = 0.33 + 0.05 * cos(from_front * PI * 5.0) if absf(from_front) < 0.2 else lerpf(0.37, 0.62, clampf((absf(from_front) - 0.2) / 0.3, 0.0, 1.0))
			if v < hairline:
				color = hair.lightened(rng.randf() * 0.06)
			# Brows.
			for side: float in [-1.0, 1.0]:
				var brow_u: float = side * 0.05
				if absf(from_front - brow_u) < 0.027 and absf(v - (0.469 - absf(from_front - brow_u) * 0.12)) < 0.005:
					color = color.lerp(hair, 0.72)
			# Eyes (or sunglasses).
			for side: float in [-1.0, 1.0]:
				var eye_u: float = side * 0.052
				var du: float = (from_front - eye_u) / 0.024
				var dv: float = (v - 0.506) / 0.009
				var socket: float = exp(-(du * du * 0.5 + dv * dv * 0.18))
				color = color.darkened(socket * 0.035)
				if du * du + dv * dv < 1.0:
					color = color.lerp(Color(0.72, 0.68, 0.62), 0.46)
					if absf(from_front - eye_u) < 0.006:
						color = Color(0.21, 0.18, 0.15)
					if dv < -0.6 or dv > 0.75:
						color = color.darkened(0.28)
			if shades and v > 0.482 and v < 0.526 and absf(from_front) < 0.082:
				color = Color(0.07, 0.07, 0.09).lerp(Color(0.2, 0.18, 0.23), 0.25 if v < 0.49 else 0.0)
			# Nose shading and nostrils.
			if absf(from_front) < 0.012 and v > 0.53 and v < 0.6:
				color = color.darkened(0.08)
			for side: float in [-1.0, 1.0]:
				if absf(from_front - side * 0.013) < 0.006 and absf(v - 0.612) < 0.006:
					color = color.darkened(0.23)
			# Lips and the line of the mouth.
			if absf(from_front) < 0.028 and absf(v - 0.682) < 0.008:
				color = color.lerp(Color(0.42, 0.26, 0.23), 0.2)
				if absf(v - 0.682) < 0.0025:
					color = color.darkened(0.22)
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## A pistol in the right hand, laid along the hand bone (-Y), so it points where the arm points.
func _build_sidearm() -> Node3D:
	var attachment: BoneAttachment3D = BoneAttachment3D.new()
	attachment.bone_name = "hand_r"
	skeleton.add_child(attachment)
	var steel: StandardMaterial3D = StandardMaterial3D.new()
	steel.albedo_color = Color(0.08, 0.085, 0.1)
	steel.metallic = 0.4
	steel.roughness = 0.45
	var grip: StandardMaterial3D = StandardMaterial3D.new()
	grip.albedo_color = Color(0.06, 0.06, 0.065)
	grip.roughness = 0.85
	var gun: Node3D = Node3D.new()
	attachment.add_child(gun)
	gun.position = Vector3(0.0, -0.08, -0.035)
	for part: Array in [[Vector3(0.028, 0.19, 0.036), Vector3(0, -0.07, -0.02), steel], [Vector3(0.026, 0.05, 0.1), Vector3(0, 0.02, 0.02), grip]]:
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.mesh = MeshKit.rounded_box(part[0], 0.006, 1)
		mesh_instance.material_override = part[2]
		mesh_instance.position = part[1]
		gun.add_child(mesh_instance)
	return gun


# --- Animation -------------------------------------------------------------------

## Damped spring toward a target rotation (Euler, radians), per bone.
func _spring(bone: int, target: Vector3, delta: float, stiffness: float = 110.0, damping: float = 13.0) -> void:
	_velocities[bone] += (target - _angles[bone]) * stiffness * delta
	_velocities[bone] *= exp(-damping * delta)
	_angles[bone] += _velocities[bone] * delta


func _apply() -> void:
	for bone: int in range(_angles.size()):
		skeleton.set_bone_pose_rotation(bone, Quaternion.from_euler(_angles[bone]))
	skeleton.set_bone_pose_position(Bone.HIPS, REST[Bone.HIPS] + _hip_offset)


## Call every frame. `velocity` is world-space; `aiming` raises the weapon.
## Joint convention: +X swings a hanging limb forward (-Z); +Z swings a left limb out.
func animate(delta: float, velocity: Vector3, aiming: bool) -> void:
	if not is_instance_valid(skeleton):
		return
	delta = minf(delta, 0.05)
	_time += delta
	if seated:
		var spread: float = 0.22 if riding else 0.06
		for side: float in [-1.0, 1.0]:
			var thigh: int = Bone.THIGH_L if side < 0.0 else Bone.THIGH_R
			var shin: int = Bone.SHIN_L if side < 0.0 else Bone.SHIN_R
			var upper: int = Bone.UPPERARM_L if side < 0.0 else Bone.UPPERARM_R
			var fore: int = Bone.FOREARM_L if side < 0.0 else Bone.FOREARM_R
			_spring(thigh, Vector3(1.45 if not riding else 1.15, 0, -side * spread), delta, 160.0, 14.0)
			_spring(shin, Vector3(-1.5 if not riding else -1.75, 0, 0), delta, 160.0, 14.0)
			_spring(upper, Vector3(0.95 if not riding else 1.15, 0, -side * 0.12), delta)
			_spring(fore, Vector3(0.5, 0, 0), delta)
		_spring(Bone.SPINE, Vector3(-0.06 if not riding else 0.25, 0, 0), delta)
		_spring(Bone.CHEST, Vector3(0.0 if not riding else 0.1, 0, 0), delta)
		_spring(Bone.HEAD, Vector3(0.0 if not riding else -0.25, sin(_time * 0.5 + personality * 5.0) * 0.14, 0), delta, 80.0, 10.0)
		_hip_offset = Vector3(0, -0.42, 0.1) if not riding else Vector3(0, -0.28, 0.05)
		_apply()
		return
	var local: Vector3 = global_basis.inverse() * velocity
	var forward: float = -local.z
	var side_speed: float = local.x
	var speed: float = Vector2(forward, side_speed).length()
	var amount: float = clampf(speed / 3.4, 0.0, 1.3)
	_phase += speed * delta * 2.9
	var swing: float = sin(_phase) * 0.55 * amount
	var direction: Vector2 = Vector2(forward, side_speed).normalized() if speed > 0.05 else Vector2.ZERO
	if _dead:
		_spring(Bone.UPPERARM_L, Vector3(0.3, 0, 1.1), delta, 60.0, 8.0)
		_spring(Bone.UPPERARM_R, Vector3(0.2, 0, -1.2), delta, 60.0, 8.0)
		_spring(Bone.FOREARM_L, Vector3(0.5, 0, 0), delta, 60.0, 8.0)
		_spring(Bone.FOREARM_R, Vector3(0.4, 0, 0), delta, 60.0, 8.0)
		_spring(Bone.THIGH_L, Vector3(0.35, 0, 0.12), delta, 60.0, 8.0)
		_spring(Bone.THIGH_R, Vector3(-0.1, 0, -0.18), delta, 60.0, 8.0)
		_spring(Bone.SHIN_L, Vector3(-0.6, 0, 0), delta, 60.0, 8.0)
		_spring(Bone.HEAD, Vector3(0.3, 0.5, 0.0), delta, 60.0, 8.0)
		_apply()
		return
	# Legs: stride along the direction of travel (forward or strafing), knees bend on lift.
	for index: int in range(2):
		var leg_sign: float = 1.0 if index == 0 else -1.0
		var thigh: int = Bone.THIGH_L if index == 0 else Bone.THIGH_R
		var shin: int = Bone.SHIN_L if index == 0 else Bone.SHIN_R
		var foot: int = Bone.FOOT_L if index == 0 else Bone.FOOT_R
		var stride: float = swing * leg_sign
		var lift: float = maxf(0.0, sin(_phase + (0.0 if index == 0 else PI) + PI * 0.5)) * 0.95 * amount
		_spring(thigh, Vector3(stride * direction.x, 0, stride * direction.y * 0.7), delta, 180.0, 15.0)
		_spring(shin, Vector3(-lift - 0.04, 0, 0), delta, 180.0, 15.0)
		_spring(foot, Vector3(lift * 0.35 - stride * 0.2, 0, 0), delta, 180.0, 15.0)
	# Body: a gentle bob and counter-rotation, idle breathing and weight shift.
	var calm: float = 1.0 - clampf(amount, 0.0, 1.0)
	_hip_offset = Vector3(sin(_time * 0.8 + personality * 4.0) * 0.01 * calm, absf(sin(_phase)) * 0.025 * amount - 0.01 * amount, 0)
	var breathe: float = sin(_time * 1.9 + personality * 6.0) * 0.018
	_spring(Bone.HIPS, Vector3(0, sin(_phase) * 0.07 * amount, sin(_time * 0.8 + personality * 4.0) * 0.025 * calm), delta)
	_spring(Bone.SPINE, Vector3(-forward * 0.03 - amount * 0.03, -sin(_phase) * 0.06 * amount, -side_speed * 0.025), delta)
	_spring(Bone.CHEST, Vector3(breathe, -sin(_phase) * 0.06 * amount, 0), delta)
	var glance: float = sin(_time * 0.37 + personality * 9.0) * 0.3 * calm
	_spring(Bone.HEAD, Vector3(amount * 0.04 + sin(_time * 0.7) * 0.02, glance + sin(_phase) * 0.06 * amount, 0), delta, 80.0, 11.0)
	if aiming:
		# Two-handed pistol grip: gun arm straight out, support hand wrapped under it.
		_spring(Bone.UPPERARM_R, Vector3(1.48, 0.1, 0.05), delta, 150.0, 14.0)
		_spring(Bone.FOREARM_R, Vector3(0.04, 0, 0), delta, 150.0, 14.0)
		_spring(Bone.UPPERARM_L, Vector3(1.3, -0.62, 0.05), delta, 150.0, 14.0)
		_spring(Bone.FOREARM_L, Vector3(0.42, 0, 0), delta, 150.0, 14.0)
		_spring(Bone.HAND_R, Vector3(-0.05, 0, 0), delta)
	else:
		_spring(Bone.UPPERARM_R, Vector3(-swing * 0.7 + 0.08, 0, -0.06), delta)
		_spring(Bone.FOREARM_R, Vector3(0.25 + amount * 0.35, 0, 0), delta)
		_spring(Bone.UPPERARM_L, Vector3(swing * 0.7 + 0.05, 0, 0.06), delta)
		_spring(Bone.FOREARM_L, Vector3(0.2 + amount * 0.4, 0, 0), delta)
		_spring(Bone.HAND_R, Vector3(0, 0, 0), delta)
	_apply()


## Hit reaction: a kick to the chest and head springs; the body rocks back and recovers.
func flinch(strength: float) -> void:
	if _velocities.is_empty():
		return
	for bone: int in [Bone.CHEST, Bone.HEAD, Bone.SPINE]:
		_velocities[bone] += Vector3(-clampf(strength, 1.0, 6.0) * 1.3, randf_range(-2.5, 2.5), randf_range(-1.5, 1.5))


## Height of the eyes above the model's origin in the current pose (standing or seated).
func eye_height() -> float:
	if seated:
		return 1.66 - (0.28 if riding else 0.42)
	return 1.66


func set_dead(value: bool) -> void:
	_dead = value
	if not value:
		scale = Vector3.ONE
		for index: int in range(_angles.size()):
			_angles[index] = Vector3.ZERO
			_velocities[index] = Vector3.ZERO
