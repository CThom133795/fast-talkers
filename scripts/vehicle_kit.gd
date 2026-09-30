extends RefCounted
## Coachwork primitives for car.gd. `profile` extrudes a side outline (z, y) across the
## car's width, the way pressed-steel panels read: bevelled shoulders, a little tumblehome
## (the top tucks in) and real wheel-arch cut-outs when the outline has them. `pane`
## builds a flat glass polygon so windows can follow slanted pillars. Meshes are indexed
## (MeshMerge drops un-indexed parts that share a surface with indexed ones) and cached.

static var _cache: Dictionary = {}


## `outline`: closed (z, y) polygon in body space, any winding, may be concave.
## `half_width`: half the width at the bottom of the outline; the top is `tuck` narrower.
## `bevel`: how far the side edges are rounded off.
static func profile(outline: PackedVector2Array, half_width: float, bevel: float, tuck: float = 0.0, cabin: Vector2 = Vector2.ZERO, inner_half: float = 0.0) -> ArrayMesh:
	var key: String = "pr%s|%.3f|%.3f|%.3f|%s|%.3f" % [str(outline), half_width, bevel, tuck, str(cabin), inner_half]
	if _cache.has(key):
		return _cache[key] as ArrayMesh
	var count: int = outline.size()
	var area: float = 0.0
	var bottom: float = INF
	var top: float = -INF
	for index: int in range(count):
		var a: Vector2 = outline[index]
		var b: Vector2 = outline[(index + 1) % count]
		area += a.x * b.y - b.x * a.y
		bottom = minf(bottom, a.y)
		top = maxf(top, a.y)
	var ccw: bool = area > 0.0
	# Outward normal of each edge, in (z, y).
	var edge_normals: Array[Vector2] = []
	for index: int in range(count):
		var e: Vector2 = outline[(index + 1) % count] - outline[index]
		var n: Vector2 = Vector2(e.y, -e.x) if ccw else Vector2(-e.y, e.x)
		edge_normals.append(n.normalized() if n.length() > 0.00001 else Vector2.UP)
	# Smooth vertex normals, except across sharp creases (then each edge keeps its own).
	var span: float = maxf(top - bottom, 0.001)
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(count):
		var next: int = (index + 1) % count
		var n_edge: Vector2 = edge_normals[index]
		var n_before: Vector2 = edge_normals[(index - 1 + count) % count]
		var n_after: Vector2 = edge_normals[next]
		var n_start: Vector2 = _shade(n_before, n_edge)
		var n_end: Vector2 = _shade(n_after, n_edge)
		var p0: Vector2 = outline[index]
		var p1: Vector2 = outline[next]
		var h0: float = half_width - tuck * (p0.y - bottom) / span
		var h1: float = half_width - tuck * (p1.y - bottom) / span
		var i0: Vector2 = p0 - _bisector(n_before, n_edge) * bevel
		var i1: Vector2 = p1 - _bisector(n_edge, n_after) * bevel
		for side: float in [-1.0, 1.0]:
			# Bevel strip: from the side face's inset edge out to the shoulder line.
			var inner_a: Vector3 = Vector3(side * h0, i0.y, i0.x)
			var inner_b: Vector3 = Vector3(side * h1, i1.y, i1.x)
			var outer_a: Vector3 = Vector3(side * (h0 - bevel), p0.y, p0.x)
			var outer_b: Vector3 = Vector3(side * (h1 - bevel), p1.y, p1.x)
			var bevel_a: Vector3 = (Vector3(side, 0, 0) + _n3(n_start)).normalized()
			var bevel_b: Vector3 = (Vector3(side, 0, 0) + _n3(n_end)).normalized()
			_tri(tool, [inner_a, outer_a, outer_b], [bevel_a, _n3(n_start), _n3(n_end)])
			_tri(tool, [inner_a, outer_b, inner_b], [bevel_a, _n3(n_end), bevel_b])
		# Optional opening in upward-facing coachwork strips. Side faces, bonnet, trunk,
		# arches and underside remain intact; cabin upholstery is built separately.
		var cuts: Array[float] = [0.0, 1.0]
		var can_cut: bool = inner_half > 0.0 and n_edge.y > 0.25 and absf(p1.x - p0.x) > 0.001
		if can_cut:
			for z: float in [cabin.x, cabin.y]:
				var t: float = (z - p0.x) / (p1.x - p0.x)
				if t > 0.001 and t < 0.999:
					cuts.append(t)
		cuts.sort()
		for segment: int in range(cuts.size() - 1):
			var a: Vector2 = p0.lerp(p1, cuts[segment])
			var b: Vector2 = p0.lerp(p1, cuts[segment + 1])
			var ha: float = lerpf(h0, h1, cuts[segment]) - bevel
			var hb: float = lerpf(h0, h1, cuts[segment + 1]) - bevel
			var middle: float = (a.x + b.x) * 0.5
			if can_cut and middle > cabin.x and middle < cabin.y:
				_strip(tool, a, b, -ha, -hb, -inner_half, -inner_half, n_start, n_end)
				_strip(tool, a, b, inner_half, inner_half, ha, hb, n_start, n_end)
			else:
				_strip(tool, a, b, -ha, -hb, ha, hb, n_start, n_end)
	# Flat side faces from the inset outline.
	var inset: PackedVector2Array = PackedVector2Array()
	for index: int in range(count):
		inset.append(outline[index] - _bisector(edge_normals[(index - 1 + count) % count], edge_normals[index]) * bevel)
	# Triangulate the true outline (always simple) and reuse its indices on the inset points:
	# at tight arch corners the inset itself can fold over and fail to triangulate.
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	if triangles.is_empty():
		push_warning("VehicleKit.profile: outline failed to triangulate (%d points)." % count)
	for side: float in [-1.0, 1.0]:
		for t: int in range(0, triangles.size(), 3):
			var corners: Array[Vector3] = []
			for k: int in range(3):
				var p: Vector2 = inset[triangles[t + k]]
				var h: float = half_width - tuck * (outline[triangles[t + k]].y - bottom) / span
				corners.append(Vector3(side * h, p.y, p.x))
			_tri(tool, corners, [Vector3(side, 0, 0), Vector3(side, 0, 0), Vector3(side, 0, 0)])
	tool.index()
	var mesh: ArrayMesh = tool.commit()
	_cache[key] = mesh
	return mesh

static func _strip(tool: SurfaceTool, a: Vector2, b: Vector2, left_a: float, left_b: float, right_a: float, right_b: float, na: Vector2, nb: Vector2) -> void:
	var la: Vector3 = Vector3(left_a, a.y, a.x)
	var lb: Vector3 = Vector3(left_b, b.y, b.x)
	var ra: Vector3 = Vector3(right_a, a.y, a.x)
	var rb: Vector3 = Vector3(right_b, b.y, b.x)
	_tri(tool, [la, ra, rb], [_n3(na), _n3(na), _n3(nb)])
	_tri(tool, [la, rb, lb], [_n3(na), _n3(nb), _n3(nb)])


## A flat convex glass polygon through `points` (in order round the edge).
static func pane(points: Array) -> ArrayMesh:
	var key: String = "pane%s" % str(points)
	if _cache.has(key):
		return _cache[key] as ArrayMesh
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a: Vector3 = points[0]
	var normal: Vector3 = ((points[1] as Vector3) - a).cross((points[2] as Vector3) - a).normalized()
	for index: int in range(1, points.size() - 1):
		_tri(tool, [a, points[index], points[index + 1]], [normal, normal, normal])
	tool.index()
	var mesh: ArrayMesh = tool.commit()
	_cache[key] = mesh
	return mesh


## Places a unit-length part so its local +Y runs from `a` to `b` (pillars, struts, forks).
static func strut(a: Vector3, b: Vector3) -> Transform3D:
	var y: Vector3 = (b - a).normalized()
	var x: Vector3 = Vector3.RIGHT - y * Vector3.RIGHT.dot(y)
	if x.length() < 0.001:
		x = Vector3.FORWARD - y * Vector3.FORWARD.dot(y)
	x = x.normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), (a + b) * 0.5)


## Shading normal where an edge (`own`) meets its neighbour: smooth across gentle bends,
## crisp across creases sharper than ~50 degrees.
static func _shade(neighbour: Vector2, own: Vector2) -> Vector2:
	if neighbour.dot(own) < 0.64:
		return own
	return (neighbour + own).normalized()


## Direction to move a corner outward so both edges move out by one unit.
static func _bisector(a: Vector2, b: Vector2) -> Vector2:
	var mid: Vector2 = (a + b)
	if mid.length() < 0.001:
		return a
	mid = mid.normalized()
	return mid / maxf(mid.dot(a), 0.35)


static func _n3(n: Vector2) -> Vector3:
	return Vector3(0, n.y, n.x)


## Emits a triangle facing along its normals (Godot front faces wind clockwise).
static func _tri(tool: SurfaceTool, corners: Array, normals: Array) -> void:
	var a: Vector3 = corners[0]
	var b: Vector3 = corners[1]
	var c: Vector3 = corners[2]
	var facing: Vector3 = (normals[0] as Vector3) + (normals[1] as Vector3) + (normals[2] as Vector3)
	var order: Array[int] = [0, 1, 2]
	if (b - a).cross(c - a).dot(facing) > 0.0:
		order = [0, 2, 1]
	for k: int in order:
		tool.set_normal(normals[k])
		tool.add_vertex(corners[k])
