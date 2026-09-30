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
