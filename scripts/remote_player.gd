class_name FastRemote
extends CharacterBody3D
## Another player's body in an online match. It contains no networking code: the lead feeds it
## `push_state()` snapshots (20 Hz), `seat_in()/seat_out()` and `apply_remote_health()`.
## Renders 100 ms behind the newest snapshot (interpolation), extrapolates at most 150 ms, then
## holds, and snaps on teleports. The body is a CharacterModel plus a hit capsule on physics
## layer 3 (rays and cars); seated players sit on layer 4 (rays only). See docs/NET_M1_SPEC.md 4.
## Real matches only contain players, so nothing here thinks for itself.

## A remote player was hit by something the local machine simulated (a car, an explosion).
## The lead forwards it to the host; health is never changed locally.
signal struck(amount: float, source: Vector3)

const CharacterModel = preload("res://scripts/character_model.gd")
const Factions = preload("res://scripts/factions.gd")
const MeshKit = preload("res://scripts/mesh_kit.gd")

const FLAG_CROUCH: int = 1
const FLAG_AIMING: int = 2
const FLAG_DEAD: int = 4
const FLAG_FIRING: int = 8
const FLAG_LEDGER: int = 16
const FLAG_CASH: int = 32
const FLAG_SPRINT: int = 64
## Hands-up gesture (weapon away, both arms raised).
const FLAG_HANDS_UP: int = 128

const RENDER_DELAY: float = 0.1
const EXTRAPOLATE_MAX: float = 0.15
const SNAP_DISTANCE: float = 8.0
const BUFFER_MAX: int = 32

const RADIUS: float = 0.34
const STAND_HEIGHT: float = 1.8
## A little taller than the local player's 1.15 so the lowered head stays inside the hitbox.
const CROUCH_HEIGHT: float = 1.3
const SEATED_HEIGHT: float = 1.1
const SEATED_CENTER: float = 0.85
const CROUCH_DROP: float = 0.35
## How far (m, outward from the body) the carried cases hang from the left hand bone.
const CARRY_OUT: float = -0.12
const LAYER_BODY: int = 4
const LAYER_SEATED: int = 8

var peer_id: int = 0
var crew: String = "morris"
var display_name: String = ""
## Last health value the host told us, for the lead's HUD or name tag.
var health: float = 100.0
## Set to a value >= 0 to replace the wall clock (deterministic tests).
var now_override: float = -1.0
## Most recent look direction from the snapshots (kept while seated, for the head).
var look_yaw: float = 0.0
var look_pitch: float = 0.0

var model: CharacterModel
var name_tag: Label3D
var capsule: CapsuleShape3D
var sidearm_prop: Node3D
var longgun_prop: Node3D
var ledger_prop: Node3D
var cash_prop: Node3D

var _configured: bool = false
var _built: bool = false
var _shape: CollisionShape3D
var _buffer: Array[Dictionary] = []
var _flags: int = 0
var _weapon_id: String = "pistol"
var _dead: bool = false
var _seated: bool = false
var _crouch: float = 0.0
var _flash: float = 0.0
var _fall: Tween
var _car: Node3D
var _eye_local: Vector3 = Vector3.ZERO
var _bike: bool = false
var _anim_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	if _configured and not _built:
		_build()


## Names the body and builds its visuals. Safe before or after `add_child`.
func setup(id: int, crew_id: String, player_name: String) -> void:
	peer_id = id
	crew = crew_id
	display_name = player_name
	_configured = true
	if is_inside_tree() or _built:
		_build()


func _build() -> void:
	_built = true
	if is_instance_valid(_fall):
		_fall.kill()
	if model != null:
		model.queue_free()
		model.get_parent().remove_child(model)
	if name_tag != null:
		name_tag.queue_free()
		remove_child(name_tag)
	if _shape == null:
		_shape = CollisionShape3D.new()
		capsule = CapsuleShape3D.new()
		capsule.radius = RADIUS
		_shape.shape = capsule
		add_child(_shape)
	collision_layer = LAYER_BODY
	collision_mask = 0
	model = CharacterModel.new()
	model.name = "Model"
	add_child(model)
	model.build(crew, true)
	sidearm_prop = null
	for child: Node in model.skeleton.get_children():
		if child is BoneAttachment3D:
			sidearm_prop = child as Node3D
			break
	longgun_prop = _build_longgun()
	_build_carry_props()
	name_tag = Label3D.new()
	name_tag.name = "NameTag"
	name_tag.text = display_name
	name_tag.font_size = 44
	name_tag.pixel_size = 0.0055
	name_tag.outline_size = 10
	name_tag.outline_modulate = Color(0.02, 0.02, 0.03, 0.9)
	name_tag.modulate = Factions.color(crew)
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.shaded = false
	name_tag.no_depth_test = false
	name_tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	name_tag.visibility_range_end = 40.0
	name_tag.position = Vector3(0, 2.1, 0)
	add_child(name_tag)
	_dead = false
	_seated = false
	_crouch = 0.0
	_refresh(true)


## Simple rifle/shotgun prop laid along the right hand bone (-Y is the barrel direction).
func _build_longgun() -> Node3D:
	var attachment: BoneAttachment3D = BoneAttachment3D.new()
	attachment.bone_name = "hand_r"
	model.skeleton.add_child(attachment)
	var steel: StandardMaterial3D = StandardMaterial3D.new()
	steel.albedo_color = Color(0.07, 0.075, 0.09)
	steel.metallic = 0.4
	steel.roughness = 0.5
	var wood: StandardMaterial3D = StandardMaterial3D.new()
	wood.albedo_color = Color(0.24, 0.14, 0.08)
	wood.roughness = 0.75
	var gun: Node3D = Node3D.new()
	attachment.add_child(gun)
	gun.position = Vector3(0.0, -0.06, -0.035)
	for part: Array in [
		[Vector3(0.05, 0.42, 0.07), Vector3(0, -0.2, 0.0), steel],
		[Vector3(0.022, 0.36, 0.022), Vector3(0, -0.6, -0.012), steel],
		[Vector3(0.045, 0.24, 0.085), Vector3(0, 0.16, 0.012), wood],
		[Vector3(0.04, 0.2, 0.05), Vector3(0, -0.28, 0.055), wood],
	]:
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.mesh = MeshKit.rounded_box(part[0], 0.006, 1)
		mesh_instance.material_override = part[2]
		mesh_instance.position = part[1]
		gun.add_child(mesh_instance)
	attachment.visible = false
	return attachment


## Briefcase props hung from the left hand, held ~0.12 m out from the leg so they do not clip it and
## sized/coloured to read at 10-20 m: a warm oxblood leather Ledger with a bright brass clasp band, and a
## bright brushed-aluminium cash case with a dark edge band and a gold tag stripe.
func _build_carry_props() -> void:
	var attachment: BoneAttachment3D = BoneAttachment3D.new()
	attachment.bone_name = "hand_l"
	model.skeleton.add_child(attachment)
	var leather: StandardMaterial3D = StandardMaterial3D.new()
	leather.albedo_color = Color(0.45, 0.18, 0.1)
	leather.roughness = 0.6
	var strap: StandardMaterial3D = StandardMaterial3D.new()
	strap.albedo_color = Color(0.3, 0.11, 0.06)
	strap.roughness = 0.65
	var brass: StandardMaterial3D = StandardMaterial3D.new()
	brass.albedo_color = Color(0.95, 0.76, 0.28)
	brass.metallic = 0.5
	brass.roughness = 0.35
	var aluminium: StandardMaterial3D = StandardMaterial3D.new()
	aluminium.albedo_color = Color(0.86, 0.88, 0.91)
	aluminium.metallic = 0.5
	aluminium.roughness = 0.4
	var edge: StandardMaterial3D = StandardMaterial3D.new()
	edge.albedo_color = Color(0.22, 0.23, 0.26)
	edge.metallic = 0.4
	edge.roughness = 0.5
	ledger_prop = Node3D.new()
	ledger_prop.name = "LedgerCase"
	attachment.add_child(ledger_prop)
	ledger_prop.position = Vector3(CARRY_OUT, -0.32, 0.0)
	_add_box(ledger_prop, Vector3(0.12, 0.36, 0.5), Vector3.ZERO, leather)
	_add_box(ledger_prop, Vector3(0.13, 0.05, 0.5), Vector3(0.0, 0.1, 0.0), brass)
	_add_box(ledger_prop, Vector3(0.13, 0.09, 0.11), Vector3(0.0, 0.1, 0.0), brass)
	_add_box(ledger_prop, Vector3(0.13, 0.05, 0.5), Vector3(0.0, -0.16, 0.0), strap)
	_add_box(ledger_prop, Vector3(0.05, 0.14, 0.18), Vector3(0.0, 0.24, 0.0), strap)
	cash_prop = Node3D.new()
	cash_prop.name = "CashCase"
	attachment.add_child(cash_prop)
	cash_prop.position = Vector3(CARRY_OUT, -0.32, 0.0)
	_add_box(cash_prop, Vector3(0.12, 0.36, 0.5), Vector3.ZERO, aluminium)
	_add_box(cash_prop, Vector3(0.13, 0.03, 0.5), Vector3.ZERO, edge)
	_add_box(cash_prop, Vector3(0.13, 0.04, 0.5), Vector3(0.0, -0.13, 0.0), brass)
	_add_box(cash_prop, Vector3(0.05, 0.14, 0.18), Vector3(0.0, 0.24, 0.0), edge)
	ledger_prop.visible = false
	cash_prop.visible = false


func _add_box(parent: Node3D, size: Vector3, at: Vector3, material: StandardMaterial3D) -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = MeshKit.rounded_box(size, 0.008, 1)
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)


# --- Snapshots ---------------------------------------------------------------------------

## Buffers one snapshot. `time` is the local receive time in seconds. Snapshots older than the
## newest one are dropped; a jump of more than 8 m clears the buffer and snaps to the new spot.
func push_state(time: float, state: Dictionary) -> void:
	var entry: Dictionary = {
		"t": time,
		"pos": state.get("pos", Vector3.ZERO) as Vector3,
		"yaw": float(state.get("yaw", 0.0)),
		"pitch": float(state.get("pitch", 0.0)),
		"flags": int(state.get("flags", 0)),
		"weapon": str(state.get("weapon", "pistol")),
		"car": int(state.get("car", -1)),
		"seat": int(state.get("seat", 0)),
		"health": float(state.get("health", 100.0)),
	}
	var first: bool = _buffer.is_empty()
	if not first:
		var newest: Dictionary = _buffer[_buffer.size() - 1]
		if time < float(newest["t"]):
			return
		if ((entry["pos"] as Vector3) - (newest["pos"] as Vector3)).length() > SNAP_DISTANCE:
			_buffer.clear()
			first = true
	_buffer.append(entry)
	while _buffer.size() > BUFFER_MAX:
		_buffer.pop_front()
	if first and _built:
		# Nothing to interpolate from: appear in the right place at once.
		_place(entry["pos"] as Vector3)
		rotation.y = float(entry["yaw"]) if not _seated else rotation.y
		look_yaw = float(entry["yaw"])
		look_pitch = float(entry["pitch"])
		_flags = int(entry["flags"])
		_weapon_id = str(entry["weapon"])
		_refresh(true)


func _now() -> float:
	return now_override if now_override >= 0.0 else Time.get_ticks_msec() / 1000.0


func _place(at: Vector3) -> void:
	if is_inside_tree():
		global_position = at
	else:
		position = at


## Interpolated state at render time `rt`: writes position/yaw/pitch and the discrete flags.
func _sample(rt: float) -> void:
	var count: int = _buffer.size()
	if count == 0:
		return
	var index: int = -1
	for k: int in range(count - 1, -1, -1):
		if float(_buffer[k]["t"]) <= rt:
			index = k
			break
	var target: Vector3
	var yaw: float
	var pitch: float
	var discrete: Dictionary
	if index < 0:
		# Older than everything buffered: hold the first snapshot.
		discrete = _buffer[0]
		target = discrete["pos"] as Vector3
		yaw = float(discrete["yaw"])
		pitch = float(discrete["pitch"])
		_anim_velocity = Vector3.ZERO
	elif index == count - 1:
		discrete = _buffer[index]
		target = discrete["pos"] as Vector3
		yaw = float(discrete["yaw"])
		pitch = float(discrete["pitch"])
		var estimate: Vector3 = Vector3.ZERO
		if count >= 2:
			var before: Dictionary = _buffer[index - 1]
			var span: float = float(discrete["t"]) - float(before["t"])
			if span > 0.0001:
				estimate = (target - (before["pos"] as Vector3)) / span
				estimate.y = 0.0
		var ahead: float = rt - float(discrete["t"])
		target += estimate * minf(ahead, EXTRAPOLATE_MAX)
		_anim_velocity = estimate if ahead <= EXTRAPOLATE_MAX else Vector3.ZERO
	else:
		discrete = _buffer[index]
		var later: Dictionary = _buffer[index + 1]
		var span: float = float(later["t"]) - float(discrete["t"])
		var weight: float = clampf((rt - float(discrete["t"])) / span, 0.0, 1.0) if span > 0.0001 else 1.0
		var from: Vector3 = discrete["pos"] as Vector3
		var to: Vector3 = later["pos"] as Vector3
		target = from.lerp(to, weight)
		yaw = lerp_angle(float(discrete["yaw"]), float(later["yaw"]), weight)
		pitch = lerpf(float(discrete["pitch"]), float(later["pitch"]), weight)
		_anim_velocity = Vector3((to.x - from.x) / span, 0.0, (to.z - from.z) / span) if span > 0.0001 else Vector3.ZERO
	look_yaw = yaw
	look_pitch = pitch
	var flags: int = int(discrete["flags"])
	var weapon: String = str(discrete["weapon"])
	if flags != _flags or weapon != _weapon_id:
		_flags = flags
		_weapon_id = weapon
		_refresh(false)
	if not _seated:
		_place(target)
		rotation.y = yaw
		velocity = _anim_velocity


# --- Frame update ------------------------------------------------------------------------

func _process(delta: float) -> void:
	if model == null:
		return
	_sample(_now() - RENDER_DELAY)
	if _seated and is_instance_valid(_car):
		global_transform = _car.global_transform * Transform3D(Basis.IDENTITY, _eye_local - Vector3(0, model.eye_height(), 0))
	var hands_up: bool = (_flags & FLAG_HANDS_UP) != 0 and not _dead and not _seated
	model.set("hands_up", hands_up)
	var aiming: bool = not _dead and not hands_up and (_flags & (FLAG_AIMING | FLAG_FIRING)) != 0
	var moving: Vector3 = Vector3.ZERO if (_dead or _seated) else _anim_velocity
	model.animate(delta, moving, aiming)
	if not _dead:
		_pose_extras(delta)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		var amount: float = _flash / 0.15
		for index: int in range(model.materials.size()):
			model.materials[index].albedo_color = model.colors[index].lerp(Color(1.0, 0.3, 0.25), amount * 0.7)


## Crouch (bent legs, lowered body) and look pitch, layered over the model's own animation.
func _pose_extras(delta: float) -> void:
	var skeleton: Skeleton3D = model.skeleton
	var crouching: bool = (_flags & FLAG_CROUCH) != 0 and not _seated
	_crouch = move_toward(_crouch, 1.0 if crouching else 0.0, delta * 7.0)
	model.position.y = -CROUCH_DROP * _crouch
	name_tag.position.y = (1.75 if _seated else 2.1 - CROUCH_DROP * _crouch)
	if _crouch > 0.001:
		var t: float = _crouch
		for leg: Array in [[CharacterModel.Bone.THIGH_L, CharacterModel.Bone.SHIN_L, CharacterModel.Bone.FOOT_L], [CharacterModel.Bone.THIGH_R, CharacterModel.Bone.SHIN_R, CharacterModel.Bone.FOOT_R]]:
			skeleton.set_bone_pose_rotation(leg[0], Quaternion(Vector3.RIGHT, 1.2 * t))
			skeleton.set_bone_pose_rotation(leg[1], Quaternion(Vector3.RIGHT, -1.8 * t))
			skeleton.set_bone_pose_rotation(leg[2], Quaternion(Vector3.RIGHT, 0.6 * t))
		var spine: int = CharacterModel.Bone.SPINE
		skeleton.set_bone_pose_rotation(spine, skeleton.get_bone_pose_rotation(spine) * Quaternion(Vector3.RIGHT, -0.5 * t))
	# Positive pitch looks up: tilt the head most and the chest a little.
	var pitch: float = clampf(look_pitch, -1.2, 1.2)
	var head: int = CharacterModel.Bone.HEAD
	skeleton.set_bone_pose_rotation(head, skeleton.get_bone_pose_rotation(head) * Quaternion(Vector3.RIGHT, pitch * 0.55))
	if not _seated:
		var chest: int = CharacterModel.Bone.CHEST
		skeleton.set_bone_pose_rotation(chest, skeleton.get_bone_pose_rotation(chest) * Quaternion(Vector3.RIGHT, pitch * 0.2))


## Applies the discrete parts of the state: dead/revive, capsule, layers, props, name tag.
func _refresh(force: bool) -> void:
	var dead: bool = (_flags & FLAG_DEAD) != 0
	if dead and not _dead:
		_die()
	elif not dead and _dead:
		_revive()
	elif force and dead:
		_dead = true
	var crouching: bool = (_flags & FLAG_CROUCH) != 0 and not _seated and not dead
	var height: float = STAND_HEIGHT
	var center: float = STAND_HEIGHT * 0.5
	if _seated:
		height = SEATED_HEIGHT
		center = SEATED_CENTER
	elif crouching:
		height = CROUCH_HEIGHT
		center = CROUCH_HEIGHT * 0.5
	capsule.height = height
	_shape.position.y = center
	collision_layer = 0 if dead else (LAYER_SEATED if _seated else LAYER_BODY)
	collision_mask = 0
	var armed_now: bool = not dead and (_flags & (FLAG_AIMING | FLAG_FIRING)) != 0
	var long_gun: bool = FastPlayer.is_primary(_weapon_id)
	if sidearm_prop != null:
		sidearm_prop.visible = armed_now and not long_gun
	if longgun_prop != null:
		longgun_prop.visible = armed_now and long_gun
	if ledger_prop != null:
		ledger_prop.visible = not dead and (_flags & FLAG_LEDGER) != 0
		cash_prop.visible = not dead and (_flags & FLAG_CASH) != 0
		# Both at once: keep the cases from overlapping.
		var both: bool = ledger_prop.visible and cash_prop.visible
		ledger_prop.position.z = -0.29 if both else 0.0
		cash_prop.position.z = 0.29 if both else 0.0
	if name_tag != null:
		name_tag.visible = not dead


func _die() -> void:
	_dead = true
	_crouch = 0.0
	if is_instance_valid(_fall):
		_fall.kill()
	model.set_dead(true)
	if _seated:
		return
	# Knees give, then a heavy fall onto the back with one small settle (as guard.gd).
	_fall = create_tween()
	_fall.tween_property(model, "position:y", -0.08, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fall.tween_property(model, "rotation:x", PI * 0.5, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fall.parallel().tween_property(model, "position:y", 0.14, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fall.tween_property(model, "rotation:x", PI * 0.47, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _revive() -> void:
	_dead = false
	if is_instance_valid(_fall):
		_fall.kill()
	model.rotation = Vector3.ZERO
	model.position = Vector3.ZERO
	model.set_dead(false)


# --- Public API --------------------------------------------------------------------------

func is_dead() -> bool:
	return _dead


func is_seated() -> bool:
	return _seated


func is_crouching() -> bool:
	return not _dead and not _seated and (_flags & FLAG_CROUCH) != 0


## Number of buffered snapshots (tests and debug overlays).
func buffered() -> int:
	return _buffer.size()


## "head" or "body" for a world-space hit point.
func hit_zone(at: Vector3) -> String:
	var threshold: float = 1.5
	if _seated:
		threshold = 1.0
	elif is_crouching():
		threshold = 1.05
	return "head" if at.y - global_position.y > threshold else "body"


## Hits by cars or explosions simulated here. The lead forwards `struck` to the host.
func take_damage(amount: float, source: Vector3 = Vector3.INF) -> void:
	struck.emit(amount, source)


func apply_remote_health(value: float) -> void:
	health = value


## Brief red tint when a shot lands on this body.
func flash_hit() -> void:
	_flash = 0.15


## Follows `car` each frame from now on (the car supplies the position). `eye_local` is the
## seat's eye position in car space (car.seat_info(seat)["eye"]).
func seat_in(car: Node3D, eye_local: Vector3, bike: bool) -> void:
	if is_instance_valid(_car) and _car is PhysicsBody3D:
		remove_collision_exception_with(_car as PhysicsBody3D)
	_car = car
	_eye_local = eye_local
	_bike = bike
	_seated = true
	_crouch = 0.0
	model.seated = true
	model.riding = bike
	model.position = Vector3.ZERO
	model.rotation = Vector3.ZERO
	if car is PhysicsBody3D:
		add_collision_exception_with(car as PhysicsBody3D)
	_refresh(true)
	if is_instance_valid(car) and is_inside_tree():
		global_transform = car.global_transform * Transform3D(Basis.IDENTITY, eye_local - Vector3(0, model.eye_height(), 0))


## Back on foot: the buffered on-foot position takes over on the next frame.
func seat_out() -> void:
	if is_instance_valid(_car) and _car is PhysicsBody3D:
		remove_collision_exception_with(_car as PhysicsBody3D)
	_car = null
	_seated = false
	rotation = Vector3.ZERO
	model.seated = false
	model.riding = false
	_refresh(true)
