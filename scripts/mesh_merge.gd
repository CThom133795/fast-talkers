extends RefCounted
## Draw-call reduction for procedural geometry. Collapses the direct MeshInstance3D
## children of a node that share a material_override into one ArrayMesh with one
## surface per material. Materials are reused, so later colour/emission changes on
## them (brake lights, hit flashes) still apply. Children that have their own
## children (pivots, animated parts) are left alone. Shadow-casting and
## non-casting pieces (outlines, paint, decals) are merged into separate instances
## so their shadow setting survives.


static func merge_children(parent: Node3D) -> Array[MeshInstance3D]:
	var buckets: Dictionary = {true: {}, false: {}}
	var orders: Dictionary = {true: [], false: []}
	for child: Node in parent.get_children():
		if not child is MeshInstance3D:
			continue
		var instance: MeshInstance3D = child as MeshInstance3D
		if instance.mesh == null or instance.material_override == null or instance.get_child_count() > 0 or not instance.visible:
			continue
		var casts: bool = instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var groups: Dictionary = buckets[casts]
		var material: Material = instance.material_override
		if not groups.has(material):
			groups[material] = []
			(orders[casts] as Array).append(material)
		(groups[material] as Array).append(instance)
	var merged_nodes: Array[MeshInstance3D] = []
	for casts: bool in [true, false]:
		var groups: Dictionary = buckets[casts]
		var order: Array = orders[casts]
		var total: int = 0
		for material: Material in order:
			total += (groups[material] as Array).size()
		if total < 2:
			continue
		var merged_mesh: ArrayMesh = ArrayMesh.new()
		for material: Material in order:
			var tool: SurfaceTool = SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			for instance: MeshInstance3D in groups[material]:
				tool.append_from(instance.mesh, 0, instance.transform)
			tool.commit(merged_mesh)
			merged_mesh.surface_set_material(merged_mesh.get_surface_count() - 1, material)
		for material: Material in order:
			for instance: MeshInstance3D in groups[material]:
				parent.remove_child(instance)
				instance.queue_free()
		var merged: MeshInstance3D = MeshInstance3D.new()
		merged.name = "Merged" if casts else "MergedNoShadow"
		merged.mesh = merged_mesh
		if not casts:
			merged.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(merged)
		merged_nodes.append(merged)
	return merged_nodes


## Shadow-pass reduction. The directional shadow renders every casting surface once per
## split, so a merged node with twelve materials costs twelve draws per split. This gathers
## the direct, static, shadow-casting geometry of `parent` (merged meshes and instanced
## window/kerb batches) into one positions+normals mesh drawn SHADOWS_ONLY, and turns the
## visible pieces' own shadow casting off. The shadow silhouette is unchanged; the shadow
## pass costs one draw per split for the whole node. Pieces with children, a visibility
## range, alpha transparency or a non-default layer mask keep casting their own shadows.
static func shadow_proxy(parent: Node3D) -> MeshInstance3D:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var donors: Array[GeometryInstance3D] = []
	for child: Node in parent.get_children():
		if not (child is MeshInstance3D or child is MultiMeshInstance3D):
			continue
		var geometry: GeometryInstance3D = child as GeometryInstance3D
		if geometry.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON or geometry.get_child_count() > 0 or not geometry.visible:
			continue
		if geometry.layers != 1 or geometry.visibility_range_end > 0.0 or _transparent(geometry.material_override):
			continue
		var mesh: Mesh = null
		var placements: Array[Transform3D] = []
		if geometry is MeshInstance3D:
			mesh = (geometry as MeshInstance3D).mesh
			placements.append(geometry.transform)
		else:
			var multimesh: MultiMesh = (geometry as MultiMeshInstance3D).multimesh
			if multimesh == null:
				continue
			mesh = multimesh.mesh
			for index: int in range(multimesh.instance_count):
				placements.append(geometry.transform * multimesh.get_instance_transform(index))
		if mesh == null or not mesh is ArrayMesh and not mesh is PrimitiveMesh:
			continue
		var skip: bool = false
		for surface: int in range(mesh.get_surface_count()):
			if _transparent(mesh.surface_get_material(surface)) and geometry.material_override == null:
				skip = true
		if skip:
			continue
		for surface: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			var local_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var local_normals: Variant = arrays[Mesh.ARRAY_NORMAL]
			var local_indices: Variant = arrays[Mesh.ARRAY_INDEX]
			if local_indices == null or (local_indices as PackedInt32Array).is_empty():
				local_indices = PackedInt32Array(range(local_vertices.size()))
			if local_normals == null or (local_normals as PackedVector3Array).size() != local_vertices.size():
				local_normals = PackedVector3Array()
				(local_normals as PackedVector3Array).resize(local_vertices.size())
			for placement: Transform3D in placements:
				var base: int = vertices.size()
				vertices.append_array(placement * local_vertices)
				normals.append_array(Transform3D(placement.basis.orthonormalized(), Vector3.ZERO) * (local_normals as PackedVector3Array))
				var shifted: PackedInt32Array = (local_indices as PackedInt32Array).duplicate()
				for i: int in range(shifted.size()):
					shifted[i] += base
				indices.append_array(shifted)
		donors.append(geometry)
	if donors.size() < 2 or vertices.size() > 2000000:
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var shadow_mesh: ArrayMesh = ArrayMesh.new()
	shadow_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	for donor: GeometryInstance3D in donors:
		donor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var proxy: MeshInstance3D = MeshInstance3D.new()
	proxy.name = "ShadowProxy"
	proxy.mesh = shadow_mesh
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	parent.add_child(proxy)
	return proxy


static func _transparent(material: Material) -> bool:
	return material is BaseMaterial3D and (material as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
