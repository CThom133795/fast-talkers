extends RefCounted
## Smoother procedural primitives for characters, guns, cars and props.
## `rounded_box` builds a box whose edges and corners are rounded with a few arc
## segments (smooth normals), so shapes read as moulded or tailored rather than
## blocky, at a few hundred triangles each. Meshes are cached by parameters.

static var _cache: Dictionary = {}


static func rounded_box(size: Vector3, radius: float, segments: int = 2) -> ArrayMesh:
	var key: String = "rb%s|%.4f|%d" % [str(size), radius, segments]
	if _cache.has(key):
		return _cache[key] as ArrayMesh
	var half: Vector3 = size * 0.5
	var r: float = minf(radius, minf(half.x, minf(half.y, half.z)) * 0.95)
	var inner: Vector3 = half - Vector3.ONE * r
	var axes_coords: Array = [_coords(half.x, r, segments), _coords(half.y, r, segments), _coords(half.z, r, segments)]
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis: int in range(3):
		var u_axis: int = (axis + 1) % 3
		var v_axis: int = (axis + 2) % 3
		var cu: PackedFloat32Array = axes_coords[u_axis]
		var cv: PackedFloat32Array = axes_coords[v_axis]
		for face_sign: float in [-1.0, 1.0]:
			var face_normal: Vector3 = Vector3.ZERO
			face_normal[axis] = face_sign
			for i: int in range(cu.size() - 1):
				for j: int in range(cv.size() - 1):
					var quad: Array[Vector3] = []
					for corner: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]:
						var p: Vector3 = Vector3.ZERO
						p[axis] = face_sign * half[axis]
						p[u_axis] = cu[corner.x]
						p[v_axis] = cv[corner.y]
						quad.append(p)
					_emit(tool, quad[0], quad[1], quad[2], inner, r, face_normal)
					_emit(tool, quad[0], quad[2], quad[3], inner, r, face_normal)
	# Indexed like Godot's primitive meshes. MeshMerge appends parts into one SurfaceTool:
	# if any part carries indices, un-indexed parts in the same surface are dropped, which
	# made whole gun slides and receivers vanish when they shared a material with a barrel.
	tool.index()
	var mesh: ArrayMesh = tool.commit()
	_cache[key] = mesh
	return mesh


static func _coords(h: float, r: float, segments: int) -> PackedFloat32Array:
	var list: PackedFloat32Array = PackedFloat32Array()
	for k: int in range(segments + 1):
		var angle: float = PI * 0.5 * float(k) / float(segments)
		list.append(-(h - r) - r * cos(angle))
	for k: int in range(segments, -1, -1):
		var angle: float = PI * 0.5 * float(k) / float(segments)
		list.append((h - r) + r * cos(angle))
	return list


static func _round(p: Vector3, inner: Vector3, r: float, fallback: Vector3) -> Array:
	var q: Vector3 = p.clamp(-inner, inner)
	var offset: Vector3 = p - q
	var normal: Vector3 = offset.normalized() if offset.length() > 0.00001 else fallback
	return [q + normal * r, normal]


static func _emit(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inner: Vector3, r: float, face_normal: Vector3) -> void:
	var ra: Array = _round(a, inner, r, face_normal)
	var rb: Array = _round(b, inner, r, face_normal)
	var rc: Array = _round(c, inner, r, face_normal)
	# Godot front faces wind clockwise seen from outside: flip if this one faces in.
	var first: Array = rb
	var second: Array = rc
	if ((rb[0] as Vector3) - (ra[0] as Vector3)).cross((rc[0] as Vector3) - (ra[0] as Vector3)).dot(face_normal) > 0.0:
		first = rc
		second = rb
	for vertex: Array in [ra, first, second]:
		tool.set_normal(vertex[1])
		tool.add_vertex(vertex[0])


static func capsule(radius: float, height: float, radial: int = 12, rings: int = 3) -> CapsuleMesh:
	var key: String = "cap%.4f|%.4f|%d|%d" % [radius, height, radial, rings]
	if not _cache.has(key):
		var mesh: CapsuleMesh = CapsuleMesh.new()
		mesh.radius = radius
		mesh.height = maxf(height, radius * 2.0)
		mesh.radial_segments = radial
		mesh.rings = rings
		_cache[key] = mesh
	return _cache[key] as CapsuleMesh


static func sphere(radius: float, height: float, radial: int = 14, rings: int = 7, hemisphere: bool = false) -> SphereMesh:
	var key: String = "sph%.4f|%.4f|%d|%d|%s" % [radius, height, radial, rings, str(hemisphere)]
	if not _cache.has(key):
		var mesh: SphereMesh = SphereMesh.new()
		mesh.radius = radius
		mesh.height = height
		mesh.radial_segments = radial
		mesh.rings = rings
		mesh.is_hemisphere = hemisphere
		_cache[key] = mesh
	return _cache[key] as SphereMesh


static func cylinder(top: float, bottom: float, height: float, radial: int = 14) -> CylinderMesh:
	var key: String = "cyl%.4f|%.4f|%.4f|%d" % [top, bottom, height, radial]
	if not _cache.has(key):
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = top
		mesh.bottom_radius = bottom
		mesh.height = height
		mesh.radial_segments = radial
		mesh.rings = 1
		_cache[key] = mesh
	return _cache[key] as CylinderMesh


static func torus(inner: float, outer: float, rings: int = 16, segments: int = 6) -> TorusMesh:
	var key: String = "tor%.4f|%.4f|%d|%d" % [inner, outer, rings, segments]
	if not _cache.has(key):
		var mesh: TorusMesh = TorusMesh.new()
		mesh.inner_radius = inner
		mesh.outer_radius = outer
		mesh.rings = rings
		mesh.ring_segments = segments
		_cache[key] = mesh
	return _cache[key] as TorusMesh
