class_name FastGuard
extends CharacterBody3D
## PRACTICE BOT: offline Practice modes only. Match builds contain no AI (see
## docs/MULTIPLAYER_DESIGN.md section 9); every other character there is a player.
## Deal security. Neutral until provoked. Hostile guards raise their weapon, strafe
## around their post and fire telegraphed shots. Hits use a deterministic accuracy
## budget (distance, target speed, crouch) so outcomes are readable, not random streaks.
signal eliminated

const CharacterModel = preload("res://scripts/character_model.gd")
const RANGE: float = 42.0
const DAMAGE: float = 9.0

var target: Node3D
var crew: String = "solnegro"
var hostile: bool = false
var active: bool = false
var health: float = 100.0
var cooldown: float = 1.8
var home: Vector3
var home_yaw: float = 0.0
var suit: Node3D
var accuracy_budget: float = 0.5

var _arms: Node3D
var _materials: Array[StandardMaterial3D] = []
var _colors: Array[Color] = []
var _flash: float = 0.0
var _strafe_direction: float = 1.0
var _strafe_timer: float = 1.0
var _shape: CollisionShape3D
var _flinch: Tween
var _raised: bool = false


func _ready() -> void:
	_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.85
	_shape.shape = capsule
	_shape.position.y = 0.95
	add_child(_shape)
	suit = CharacterModel.new()
	add_child(suit)
	set_crew(crew)
	home = position
	home_yaw = rotation.y
	_set_pose(false)


## Rebuilds the outfit for a crew. Practice bots always wear a rival crew's colours.
func set_crew(crew_id: String) -> void:
	crew = crew_id
	var model: CharacterModel = suit as CharacterModel
	model.build(crew_id)
	_arms = model.arms
	_materials = model.materials
	_colors = model.colors
	_set_pose(hostile and health > 0.0)


func _set_pose(raised: bool) -> void:
	# The rig springs toward the new pose every frame (see CharacterModel.animate).
	_raised = raised


func _process(delta: float) -> void:
	var model: CharacterModel = suit as CharacterModel
	model.animate(delta, velocity if health > 0.0 and active else Vector3.ZERO, _raised and health > 0.0)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		var amount: float = _flash / 0.15
		for index: int in range(_materials.size()):
			_materials[index].albedo_color = _colors[index].lerp(Color(1.0, 0.3, 0.25), amount * 0.7)


func _physics_process(delta: float) -> void:
	if health <= 0.0 or not active or not is_instance_valid(target):
		return
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= 24.0 * delta
	var flat := target.global_position - global_position
	flat.y = 0.0
	if flat.length() > 0.5:
		look_at(global_position + flat, Vector3.UP)
	velocity.x = 0.0
	velocity.z = 0.0
	if hostile:
		_strafe(delta)
	else:
		# Calm guards walk back to their post after a scuffle.
		var to_post: Vector3 = home - global_position
		to_post.y = 0.0
		if to_post.length() > 0.25:
			var step: Vector3 = to_post.normalized() * minf(1.4, to_post.length() / maxf(delta, 0.001))
			velocity.x = step.x
			velocity.z = step.z
	move_and_slide()
	_set_pose(hostile)
	if not hostile:
		return
	cooldown -= delta
	if cooldown > 0.0 or flat.length() > RANGE:
		return
	if target.has_method("is_dead") and target.is_dead():
		return
	var origin := global_position + Vector3(0, 1.45, 0) - global_basis.z * 0.5
	var crouched: bool = target is FastPlayer and (target as FastPlayer).crouching
	var end := target.global_position + Vector3(0, 0.7 if crouched else 1.0, 0)
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.collider != target:
		# No clear line of fire: reposition briefly and check again.
		cooldown = 0.35
		return
	cooldown = randf_range(0.95, 1.35)
	accuracy_budget += hit_chance(flat.length(), crouched)
	if accuracy_budget >= 1.0:
		accuracy_budget -= 1.0
		# Telegraphing and modest damage make this a testing encounter, not a bot aimbot.
		target.take_damage(DAMAGE, origin)
		get_parent().guard_shot(origin, end, true)
	else:
		var side: Vector3 = (end - origin).cross(Vector3.UP).normalized()
		var miss: Vector3 = end + side * randf_range(-1.0, 1.0) * 1.1 + Vector3.UP * randf_range(-0.5, 0.9)
		get_parent().guard_shot(origin, miss, false)


func hit_chance(distance: float, crouched: bool) -> float:
	var speed: float = 0.0
	if target is CharacterBody3D:
		var motion: Vector3 = (target as CharacterBody3D).velocity
		speed = Vector2(motion.x, motion.z).length()
	var chance: float = 0.9 - distance * 0.013 - speed * 0.07
	if crouched:
		chance -= 0.18
	return clampf(chance, 0.12, 0.9)


func _strafe(delta: float) -> void:
	_strafe_timer -= delta
	var side: Vector3 = global_basis.x
	side.y = 0.0
	var offset: Vector3 = global_position - home
	offset.y = 0.0
	if _strafe_timer <= 0.0 or offset.dot(side * _strafe_direction) > 1.6:
		_strafe_direction = -_strafe_direction
		_strafe_timer = randf_range(0.9, 1.9)
	velocity.x = side.x * _strafe_direction * 1.7
	velocity.z = side.z * _strafe_direction * 1.7


func hit_zone(at: Vector3) -> String:
	return "head" if at.y - global_position.y > 1.55 else "body"


func take_damage(amount: float, _source: Vector3 = Vector3.INF) -> void:
	if health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	hostile = true
	_flash = 0.15
	if is_instance_valid(_flinch):
		_flinch.kill()
	if health > 0.0:
		# A springy stagger sells the hit without taking control away from the bot.
		(suit as CharacterModel).flinch(amount * 0.15)
	else:
		collision_layer = 0
		collision_mask = 0
		_set_pose(false)
		(suit as CharacterModel).set_dead(true)
		# Knees give, then a heavy fall onto the back with one small settle.
		var tween := create_tween()
		tween.tween_property(suit, "position:y", -0.08, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(suit, "rotation:x", PI * 0.5, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(suit, "position:y", 0.14, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(suit, "rotation:x", PI * 0.47, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		eliminated.emit()


func set_present(present: bool) -> void:
	visible = present
	active = active and present
	collision_layer = 1 if present and health > 0.0 else 0
	collision_mask = 1 if present and health > 0.0 else 0
	_shape.disabled = not present


func reset_guard() -> void:
	position = home
	rotation = Vector3(0, home_yaw, 0)
	velocity = Vector3.ZERO
	health = 100.0
	hostile = false
	active = false
	cooldown = 1.8
	accuracy_budget = 0.5
	collision_layer = 1
	collision_mask = 1
	_shape.disabled = false
	_flash = 0.0
	if is_instance_valid(_flinch):
		_flinch.kill()
	for index: int in range(_materials.size()):
		_materials[index].albedo_color = _colors[index]
	suit.rotation = Vector3.ZERO
	suit.position = Vector3.ZERO
	(suit as CharacterModel).set_dead(false)
	_set_pose(false)
