extends StaticBody3D
## Storefront glass: it stops bodies and bullets while whole, and shatters when shot
## (main.gd calls take_damage on any collider that has it). FastWorld.reset_glass()
## puts every pane back, e.g. between rounds.

signal shattered

var pane: MeshInstance3D
var broken: bool = false


func take_damage(_amount: float, _source: Vector3 = Vector3.INF) -> void:
	if broken:
		return
	broken = true
	pane.visible = false
	collision_layer = 0
	_scatter()
	shattered.emit()


func restore() -> void:
	broken = false
	pane.visible = true
	collision_layer = 1


## A few shards drop from the frame and fade: enough to read "that window is gone".
func _scatter() -> void:
	var box: BoxMesh = pane.mesh as BoxMesh
	var span: Vector3 = box.size if box != null else Vector3(1, 1, 0.05)
	for index: int in range(7):
		var shard: MeshInstance3D = MeshInstance3D.new()
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(randf_range(0.08, 0.25), randf_range(0.1, 0.35), 0.02)
		shard.mesh = mesh
		shard.material_override = pane.material_override
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shard)
		shard.position = pane.position + Vector3(randf_range(-0.5, 0.5) * span.x, randf_range(-0.3, 0.4) * span.y, 0)
		shard.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var tween: Tween = shard.create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "position:y", -0.1 - pane.position.y * 0.0 + 0.02, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(shard, "scale", Vector3.ONE * 0.2, 0.8).set_delay(0.3)
		tween.chain().tween_callback(shard.queue_free)
