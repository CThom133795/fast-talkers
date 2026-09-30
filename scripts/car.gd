class_name FastCar
extends CharacterBody3D
## Asset-free vehicles for Port Halcyon: sedan, coupe, SUV, pickup and motorcycle.
## Fixed-step kinematic handling: velocity retains inertia while steering turns
## the chassis, and bounded lateral grip brings the tires back into line.
## Body pitch/roll are visual suspension cues, not a rigid-body simulation.
## Forward is local -Z. Place this node's origin at road height.
##
## Seats: every vehicle lists its seats (eye point, door, fire arc). Passengers aim and
## shoot out of the windows; pickup-bed and pillion gunners have (almost) all-round arcs.
## The collision hull is compound (lower body, pillars, roof) so bullets pass through
## window openings: occupants can shoot out and be shot, the doors are cover.

const MeshMerge = preload("res://scripts/mesh_merge.gd")
const MeshKit = preload("res://scripts/mesh_kit.gd")
const VehicleKit = preload("res://scripts/vehicle_kit.gd")

signal crashed(strength: float)
signal wrecked
## A window broke (bullet or crash): `at` is where, in world space.
signal glass_broken(index: int, at: Vector3)

## Handling and layout per type. City playtest tuning: roughly 20% lower top speed, 20-25% less acceleration.
## Seat arcs: (centre, half-width) in radians, +yaw turns left. shoot: "driveby" (driver,
## one-handed, while aiming), "window", "open" (bed / pillion) or "none".
const TYPES: Dictionary = {
	"sedan": {"label": "SEDAN", "accel": 5.6, "brake": 19.0, "top": 25.0, "reverse": 8.0, "grip": 19.0, "handbrake": 3.8,
		"wheelbase": 2.7, "hull": Vector3(1.92, 1.5, 4.4), "belt": 1.0, "roof": 1.5, "cabin": Vector2(-1.1, 1.25), "mid": 0.21, "health": 800.0,
		"wheel_r": 0.34, "axles": Vector2(-1.36, 1.34), "track": 0.89, "chase": 7.2, "engine_pitch": 1.0,
		"seats": [
			{"name": "DRIVER", "eye": Vector3(-0.38, 1.18, -0.3), "door": Vector3(-1.62, 0.12, -0.3), "arc": Vector2(1.57, 1.3), "shoot": "driveby", "pane": 0},
			{"name": "FRONT PASSENGER", "eye": Vector3(0.56, 1.18, -0.3), "door": Vector3(1.62, 0.12, -0.3), "arc": Vector2(-1.57, 1.4), "shoot": "window", "pane": 1},
			{"name": "REAR LEFT", "eye": Vector3(-0.56, 1.16, 0.72), "door": Vector3(-1.62, 0.12, 0.72), "arc": Vector2(1.66, 1.4), "shoot": "window", "pane": 2},
			{"name": "REAR RIGHT", "eye": Vector3(0.56, 1.16, 0.72), "door": Vector3(1.62, 0.12, 0.72), "arc": Vector2(-1.66, 1.4), "shoot": "window", "pane": 3},
		]},
	"coupe": {"label": "COUPE", "accel": 7.0, "brake": 21.0, "top": 28.5, "reverse": 8.0, "grip": 21.0, "handbrake": 3.4,
		"wheelbase": 2.55, "hull": Vector3(1.88, 1.3, 4.3), "belt": 0.9, "roof": 1.3, "cabin": Vector2(-0.55, 0.95), "health": 650.0,
		"wheel_r": 0.33, "axles": Vector2(-1.4, 1.3), "track": 0.88, "chase": 6.8, "engine_pitch": 1.18,
		"seats": [
			{"name": "DRIVER", "eye": Vector3(-0.38, 1.02, 0.25), "door": Vector3(-1.6, 0.12, 0.2), "arc": Vector2(1.57, 1.3), "shoot": "driveby", "pane": 0},
			{"name": "PASSENGER", "eye": Vector3(0.56, 1.02, 0.25), "door": Vector3(1.6, 0.12, 0.2), "arc": Vector2(-1.57, 1.4), "shoot": "window", "pane": 1},
		]},
	"suv": {"label": "SUV", "accel": 4.8, "brake": 17.0, "top": 22.5, "reverse": 7.5, "grip": 17.5, "handbrake": 4.6,
		"wheelbase": 2.95, "hull": Vector3(2.06, 1.95, 4.8), "belt": 1.3, "roof": 1.92, "cabin": Vector2(-1.05, 2.05), "mid": 0.27, "health": 1250.0,
		"wheel_r": 0.4, "axles": Vector2(-1.5, 1.45), "track": 0.94, "chase": 8.0, "engine_pitch": 0.85,
		"seats": [
			{"name": "DRIVER", "eye": Vector3(-0.42, 1.55, -0.3), "door": Vector3(-1.72, 0.12, -0.3), "arc": Vector2(1.57, 1.3), "shoot": "driveby", "pane": 0},
			{"name": "FRONT PASSENGER", "eye": Vector3(0.6, 1.55, -0.3), "door": Vector3(1.72, 0.12, -0.3), "arc": Vector2(-1.57, 1.4), "shoot": "window", "pane": 1},
			{"name": "REAR LEFT", "eye": Vector3(-0.6, 1.53, 0.85), "door": Vector3(-1.72, 0.12, 0.85), "arc": Vector2(1.66, 1.4), "shoot": "window", "pane": 2},
			{"name": "REAR RIGHT", "eye": Vector3(0.6, 1.53, 0.85), "door": Vector3(1.72, 0.12, 0.85), "arc": Vector2(-1.66, 1.4), "shoot": "window", "pane": 3},
		]},
	"pickup": {"label": "PICKUP", "accel": 5.0, "brake": 17.5, "top": 23.0, "reverse": 7.5, "grip": 17.0, "handbrake": 4.2,
		"wheelbase": 3.2, "hull": Vector3(2.0, 1.85, 5.3), "belt": 1.05, "roof": 1.9, "cabin": Vector2(-1.25, 0.15), "health": 1050.0,
		"wheel_r": 0.39, "axles": Vector2(-1.7, 1.55), "track": 0.92, "chase": 8.4, "engine_pitch": 0.8,
		"seats": [
			{"name": "DRIVER", "eye": Vector3(-0.4, 1.52, -0.55), "door": Vector3(-1.7, 0.12, -0.55), "arc": Vector2(1.57, 1.3), "shoot": "driveby", "pane": 0},
			{"name": "PASSENGER", "eye": Vector3(0.58, 1.52, -0.55), "door": Vector3(1.7, 0.12, -0.55), "arc": Vector2(-1.57, 1.4), "shoot": "window", "pane": 1},
			{"name": "BED LEFT", "eye": Vector3(-0.45, 2.2, 1.35), "door": Vector3(-1.65, 0.12, 2.1), "arc": Vector2(1.57, PI), "shoot": "open", "pane": -1},
			{"name": "BED RIGHT", "eye": Vector3(0.45, 2.2, 1.35), "door": Vector3(1.65, 0.12, 2.1), "arc": Vector2(-1.57, PI), "shoot": "open", "pane": -1},
		]},
	"motorcycle": {"label": "MOTORCYCLE", "accel": 8.2, "brake": 22.0, "top": 30.0, "reverse": 3.0, "grip": 23.0, "handbrake": 2.8,
		"wheelbase": 1.45, "hull": Vector3(0.62, 1.0, 2.1), "belt": 0.0, "roof": 0.0, "cabin": Vector2.ZERO, "health": 380.0,
		"wheel_r": 0.33, "axles": Vector2(-0.72, 0.72), "track": 0.0, "chase": 5.4, "engine_pitch": 1.55,
		"seats": [
			{"name": "RIDER", "eye": Vector3(0.0, 1.6, 0.12), "door": Vector3(-1.05, 0.12, 0.1), "arc": Vector2(0.0, 1.85), "shoot": "driveby", "pane": -1},
			{"name": "PILLION", "eye": Vector3(0.0, 1.76, 0.6), "door": Vector3(1.05, 0.12, 0.55), "arc": Vector2(PI, PI), "shoot": "open", "pane": -1, "blocked": 0.42},
		]},
}

@export var vehicle_type: String = "sedan"
@export var engine_acceleration: float = 5.6
@export var braking_deceleration: float = 19.0
@export var maximum_forward_speed: float = 25.0
@export var maximum_reverse_speed: float = 8.0
@export var lateral_grip: float = 17.5
@export var handbrake_grip: float = 3.8
@export var wheelbase: float = 2.7
@export var gravity_acceleration: float = 24.0
@export var paint_color: Color = Color("d5a748")
@export var model_name: String = "SEDAN"
## Crew livery: a side and roof stripe. Transparent means no stripe.
@export var stripe_color: Color = Color(0, 0, 0, 0)

## A player drives with the keyboard/pad. `autopilot` is the practice wheelman.
var occupied: bool = false
var enabled: bool = true
var autopilot: bool = false
var autopilot_path: PackedVector3Array = PackedVector3Array()
var autopilot_speed: float = 13.0
## Waypoints before this index are a one-way lead-in; after the last point the loop
## restarts here (0 = the whole path is the loop).
var autopilot_loop_from: int = 0
var speed_kph: float = 0.0
## Read by audio/effects: driver input, sideways tyre speed (m/s), brake-light state.
var throttle_input: float = 0.0
var slip: float = 0.0
var braking: bool = false
var handbrake_on: bool = false
var longitudinal_speed: float = 0.0
var spawn_transform: Transform3D = Transform3D.IDENTITY
var health: float = 800.0
var max_health: float = 800.0
var disabled: bool = false
## Seat index -> occupant tag ("" empty, "player", "bot").
var occupants: Array[String] = []
var seats: Array = []
var spec: Dictionary = {}

var _steering: float = 0.0
var _tail_material: StandardMaterial3D
var _head_material: StandardMaterial3D
var _spinners: Array[Node3D] = []
var _body_spin: Vector3 = Vector3.ZERO
var _bounce: float = 0.0
var _bounce_velocity: float = 0.0
var _was_grounded: bool = true
var _air_speed: float = 0.0
var _body: Node3D
var _front_wheels: Array[Node3D] = []
## Every window: {points (body space), roll (seat pane index or -1), open, broken}. The
## intact, closed panes share one mesh, rebuilt when a window rolls down or breaks.
var _glass: Array[Dictionary] = []
var _glass_mesh: MeshInstance3D
var _previous_forward_speed: float = 0.0
var _wheel_angle: float = 0.0
var _materials: Dictionary = {}
var _resting: bool = false
var _ap_index: int = -1
var _ap_stuck: float = 0.0
var _ap_reverse: float = 0.0
var _ai_steer: float = 0.0
var _ai_throttle: float = 0.0
## Online: another peer drives this car. It follows their snapshots 100 ms behind instead
## of simulating (docs/NET_M1_SPEC.md §6).
var net_puppet: bool = false
## Online: health belongs to the host. When set, take_damage() reports through this
## `func(car: FastCar, amount: float)` instead of changing health locally.
var net_damage_hook: Callable = Callable()
var _net_buffer: Array[Dictionary] = []
const NET_DELAY: float = 0.1
const NET_FLAG_BRAKING: int = 1
const NET_FLAG_HANDBRAKE: int = 2
const NET_FLAG_LIT: int = 4


func _ready() -> void:
	spec = TYPES.get(vehicle_type, TYPES["sedan"])
	engine_acceleration = spec["accel"]
	braking_deceleration = spec["brake"]
	maximum_forward_speed = spec["top"]
	maximum_reverse_speed = spec["reverse"]
	lateral_grip = spec["grip"]
	handbrake_grip = spec["handbrake"]
	wheelbase = spec["wheelbase"]
	max_health = spec["health"]
	health = max_health
	seats = spec["seats"]
	occupants.clear()
	for index: int in range(seats.size()):
		occupants.append("")
	if model_name == "SEDAN" or model_name.is_empty():
		model_name = str(spec["label"])
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(40.0)
	max_slides = 5
	# World/characters can collide with the vehicle as a normal solid body.
	collision_layer = 1
	# Layer 3 (value 4): other players on foot, so cars can run them down.
	collision_mask = 1 | 4
	_build_hull()
	_body = Node3D.new()
	_body.position.y = 0.8
	add_child(_body)
	_build_model()
	add_to_group("vehicles")


func is_bike() -> bool:
	return vehicle_type == "motorcycle"


# --- Seats -----------------------------------------------------------------------

func seat_count() -> int:
	return seats.size()


func seat_free(index: int) -> bool:
	return index >= 0 and index < occupants.size() and occupants[index].is_empty()


func seat_info(index: int) -> Dictionary:
	return seats[clampi(index, 0, seats.size() - 1)] as Dictionary


func seat_eye(index: int) -> Vector3:
	return global_transform * (seat_info(index)["eye"] as Vector3)


func door_position(index: int) -> Vector3:
	return global_transform * (seat_info(index)["door"] as Vector3)


## The free seat whose door is nearest to `at` (-1 if full). `passenger_only` skips the driver.
func nearest_free_seat(at: Vector3, passenger_only: bool = false) -> int:
	var best: int = -1
	var best_distance: float = INF
	for index: int in range(seats.size()):
		if not seat_free(index) or (passenger_only and index == 0):
			continue
		var distance: float = door_position(index).distance_to(at)
		if distance < best_distance:
			best = index
			best_distance = distance
	return best


func next_free_seat(from: int) -> int:
	for step: int in range(1, seats.size()):
		var index: int = (from + step) % seats.size()
		if seat_free(index):
			return index
	return -1


func occupied_seats() -> int:
	var count: int = 0
	for tag: String in occupants:
		if not tag.is_empty():
			count += 1
	return count


## Rolls a window down (a gunner is using it) or back up. A broken window stays broken.
func set_window_open(pane: int, open: bool) -> void:
	if pane < 0:
		return
	for entry: Dictionary in _glass:
		if int(entry["roll"]) == pane and bool(entry["open"]) != open:
			entry["open"] = open
			_rebuild_glass()


## True while seat pane `pane` shows glass (closed and not broken).
func window_closed(pane: int) -> bool:
	for entry: Dictionary in _glass:
		if int(entry["roll"]) == pane:
			return not bool(entry["open"]) and not bool(entry["broken"])
	return false


func glass_count() -> int:
	return _glass.size()


func intact_glass() -> int:
	var count: int = 0
	for entry: Dictionary in _glass:
		if not bool(entry["broken"]):
			count += 1
	return count


func glass_broken_at(index: int) -> bool:
	return index >= 0 and index < _glass.size() and bool(_glass[index]["broken"])


## The first intact, closed window the segment `from`→`to` passes through:
## {index, position, distance} in world space, or {} if it misses every pane.
func glass_hit(from: Vector3, to: Vector3) -> Dictionary:
	if _glass.is_empty() or not is_instance_valid(_body):
		return {}
	var into_body: Transform3D = _body.global_transform.affine_inverse()
	var a: Vector3 = into_body * from
	var b: Vector3 = into_body * to
	var best: Dictionary = {}
	var best_distance: float = INF
	for index: int in range(_glass.size()):
		var entry: Dictionary = _glass[index]
		if bool(entry["open"]) or bool(entry["broken"]):
			continue
		var points: Array = entry["points"]
		for corner: int in range(1, points.size() - 1):
			var crossing: Variant = Geometry3D.segment_intersects_triangle(a, b, points[0], points[corner], points[corner + 1])
			if crossing == null:
				continue
			var distance: float = a.distance_to(crossing as Vector3)
			if distance < best_distance:
				best_distance = distance
				best = {"index": index, "position": _body.global_transform * (crossing as Vector3), "distance": distance}
	return best


## Shatters window `index` (a bullet or a crash). Returns false if it was already gone.
func break_glass(index: int, at: Vector3 = Vector3.INF) -> bool:
	if index < 0 or index >= _glass.size() or bool(_glass[index]["broken"]):
		return false
	_glass[index]["broken"] = true
	_rebuild_glass()
	var where: Vector3 = at if at != Vector3.INF else _glass_centre(index)
	_scatter_glass(where)
	glass_broken.emit(index, where)
	return true


func _glass_centre(index: int) -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	var points: Array = _glass[index]["points"]
	for point: Vector3 in points:
		sum += point
	return _body.global_transform * (sum / maxf(points.size(), 1))


func _add_glass(points: Array, roll: int) -> void:
	_glass.append({"points": points, "roll": roll, "open": false, "broken": false})


func _rebuild_glass() -> void:
	if not is_instance_valid(_body) or _glass.is_empty():
		return
	if not is_instance_valid(_glass_mesh):
		_glass_mesh = MeshInstance3D.new()
		_glass_mesh.name = "Glass"
		_glass_mesh.material_override = _glass_material()
		_glass_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_glass_mesh.visibility_range_end = 130.0
		_glass_mesh.visibility_range_end_margin = 8.0
		_body.add_child(_glass_mesh)
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any: bool = false
	for entry: Dictionary in _glass:
		if bool(entry["open"]) or bool(entry["broken"]):
			continue
		any = true
		var points: Array = entry["points"]
		var a: Vector3 = points[0]
		var normal: Vector3 = ((points[1] as Vector3) - a).cross((points[2] as Vector3) - a).normalized()
		for corner: int in range(1, points.size() - 1):
			for point: Vector3 in [a, points[corner], points[corner + 1]]:
				tool.set_normal(normal)
				tool.add_vertex(point)
	_glass_mesh.mesh = tool.commit() if any else null


## Crumbs of safety glass drop out of the frame and fade.
func _scatter_glass(at: Vector3) -> void:
	if not is_inside_tree():
		return
	var material: StandardMaterial3D = _glass_material()
	for index: int in range(9):
		var shard: MeshInstance3D = MeshInstance3D.new()
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(randf_range(0.03, 0.09), randf_range(0.03, 0.08), 0.012)
		shard.mesh = mesh
		shard.material_override = material
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_parent().add_child(shard)
		shard.global_position = at + Vector3(randf_range(-0.25, 0.25), randf_range(-0.2, 0.2), randf_range(-0.25, 0.25))
		shard.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var drop: float = maxf(shard.global_position.y - global_position.y - 0.02, 0.1)
		var tween: Tween = shard.create_tween()
		tween.tween_property(shard, "global_position:y", shard.global_position.y - drop, sqrt(drop / 4.9)).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_interval(1.2)
		tween.tween_property(shard, "scale", Vector3.ONE * 0.1, 0.5)
		tween.tween_callback(shard.queue_free)


# --- Driving -----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if net_puppet:
		_follow_net(delta)
		return
	var driven: bool = (occupied or autopilot) and enabled
	if not driven and _resting:
		return
	var forward: Vector3 = -global_transform.basis.z.normalized()
	var right: Vector3 = global_transform.basis.x.normalized()
	var longitudinal: float = velocity.dot(forward)
	var steer_input: float = 0.0
	var throttle: float = 0.0
	var handbrake: bool = false
	if occupied and enabled:
		# Keyboard A/D or the left stick steer; W/S or RT/LT drive. Stick Y never throttles.
		steer_input = clampf(Input.get_axis("move_left", "move_right") + Input.get_axis("stick_left", "stick_right"), -1.0, 1.0)
		throttle = clampf(Input.get_axis("move_back", "move_forward") + Input.get_action_strength("pad_throttle") - Input.get_action_strength("pad_brake"), -1.0, 1.0)
		handbrake = Input.is_action_pressed("handbrake")
	elif autopilot and enabled:
		_drive_autopilot(delta, forward, longitudinal)
		steer_input = _ai_steer
		throttle = _ai_throttle
	if disabled:
		throttle = 0.0
	# Quick to turn in, quicker to straighten: the wheel self-centres when you let go.
	var returning: bool = absf(steer_input) < absf(_steering) or steer_input * _steering < 0.0
	_steering = move_toward(_steering, steer_input, delta * (6.5 if returning else 4.2))
	var grounded: bool = is_on_floor()
	if grounded:
		if not driven:
			longitudinal = move_toward(longitudinal, 0.0, delta * 5.0)
		elif absf(throttle) > 0.01:
			if longitudinal * throttle < -0.25:
				# S brakes forward travel before selecting reverse; W does the converse.
				longitudinal = move_toward(longitudinal, 0.0, braking_deceleration * delta)
			else:
				var speed_limit: float = maximum_forward_speed if throttle > 0.0 else maximum_reverse_speed
				var power: float = 1.0 - 0.48 * clampf(absf(longitudinal) / speed_limit, 0.0, 1.0)
				longitudinal += throttle * engine_acceleration * power * delta
		else:
			var rolling_drag: float = 0.42 + longitudinal * longitudinal * 0.004
			longitudinal = move_toward(longitudinal, 0.0, rolling_drag * delta)
		if handbrake:
			longitudinal = move_toward(longitudinal, 0.0, 5.8 * delta)
		longitudinal = clampf(longitudinal, -maximum_reverse_speed, maximum_forward_speed)
		var previous_lateral: float = velocity.dot(right)
		velocity = forward * longitudinal + right * previous_lateral + Vector3.UP * velocity.y
		# Less steering lock at speed avoids instant high-speed direction changes.
		var speed_fraction: float = clampf(absf(longitudinal) / maximum_forward_speed, 0.0, 1.0)
		_wheel_angle = _steering * lerpf(0.52, 0.12, speed_fraction)
		var yaw_rate: float = -longitudinal * tan(_wheel_angle) / wheelbase
		# The tyres can only carry so much cornering force, so the chassis never rotates
		# faster than grip can swing the car round: it goes where it points instead of
		# sliding wide. The handbrake lifts the cap (and the grip) for deliberate slides.
		var grip_yaw: float = lateral_grip * 1.3 / maxf(absf(longitudinal), 3.0)
		if handbrake:
			yaw_rate *= 1.25
			grip_yaw *= 1.8
		var yaw_cap: float = minf(1.55, grip_yaw)
		rotate_y(clampf(yaw_rate, -yaw_cap, yaw_cap) * delta)
		forward = -global_transform.basis.z.normalized()
		right = global_transform.basis.x.normalized()
		var lateral_speed: float = velocity.dot(right)
		var grip: float = handbrake_grip if handbrake else lateral_grip
		if not handbrake:
			# Proportional bite on top of the fixed grip: small slides die quickly.
			lateral_speed *= exp(-5.0 * delta)
		lateral_speed = move_toward(lateral_speed, 0.0, grip * delta)
		velocity = forward * velocity.dot(forward) + right * lateral_speed + Vector3.UP * velocity.y
		velocity.y = -0.6
	else:
		velocity.y -= gravity_acceleration * delta
	throttle_input = throttle
	handbrake_on = handbrake and occupied
	braking = driven and (handbrake or (longitudinal > 0.25 and throttle < -0.01) or (longitudinal < -0.25 and throttle > 0.01))
	var before: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	var planar_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	speed_kph = planar_velocity.length() * 3.6
	longitudinal_speed = velocity.dot(forward)
	slip = velocity.dot(right) if grounded else 0.0
	_check_impacts(before, planar_velocity)
	_update_visuals(delta, velocity.dot(forward), grounded)
	# Parked and still: stop simulating until someone gets in (saves CPU with many cars).
	_resting = not driven and grounded and planar_velocity.length() < 0.05 and absf(_bounce) < 0.002 and _body_spin.length() < 0.01


## Snapshot for the network: what a puppet needs to follow and animate this car.
func net_state() -> Dictionary:
	var flags: int = (NET_FLAG_BRAKING if braking else 0) | (NET_FLAG_HANDBRAKE if handbrake_on else 0) | (NET_FLAG_LIT if occupied or autopilot else 0)
	return {"xform": global_transform, "vel": velocity, "steer": _steering, "speed": longitudinal_speed, "flags": flags}


## Buffers a driver's snapshot (`time` = local receive time in seconds).
func push_net_state(time: float, state: Dictionary) -> void:
	if not _net_buffer.is_empty():
		if time <= float(_net_buffer[-1]["t"]):
			return
		# A teleport (respawn, reset): jump straight there.
		if (state["xform"] as Transform3D).origin.distance_to((_net_buffer[-1]["xform"] as Transform3D).origin) > 12.0:
			_net_buffer.clear()
	var entry: Dictionary = state.duplicate()
	entry["t"] = time
	_net_buffer.append(entry)
	while _net_buffer.size() > 24:
		_net_buffer.pop_front()
	if _net_buffer.size() == 1:
		global_transform = state["xform"]


## Becomes (or stops being) a puppet. Leaving puppet mode keeps the last velocity so a car
## whose driver got out rolls on naturally under local simulation.
func set_net_puppet(on: bool) -> void:
	if on == net_puppet:
		return
	net_puppet = on
	_net_buffer.clear()
	_resting = false


func _follow_net(delta: float) -> void:
	if _net_buffer.is_empty():
		return
	var render: float = Time.get_ticks_msec() / 1000.0 - NET_DELAY
	var older: Dictionary = _net_buffer[0]
	var newer: Dictionary = _net_buffer[-1]
	for index: int in range(_net_buffer.size() - 1):
		if float(_net_buffer[index + 1]["t"]) >= render:
			older = _net_buffer[index]
			newer = _net_buffer[index + 1]
			break
	var span: float = maxf(float(newer["t"]) - float(older["t"]), 0.001)
	var weight: float = clampf((render - float(older["t"])) / span, 0.0, 1.0)
	var from: Transform3D = older["xform"]
	var to: Transform3D = newer["xform"]
	var target: Transform3D = from.interpolate_with(to, weight)
	if render > float(newer["t"]):
		# Past the newest snapshot: coast along the ground on its velocity for up to 0.2 s
		# (never vertically, so a stale falling snapshot can't sink or lift the car).
		var ahead: float = minf(render - float(newer["t"]), 0.2)
		var coast: Vector3 = newer["vel"]
		coast.y = 0.0
		target = Transform3D(to.basis, to.origin + coast * ahead)
	global_transform = target
	velocity = (newer["vel"] as Vector3)
	_steering = lerpf(float(older["steer"]), float(newer["steer"]), weight)
	var speed: float = lerpf(float(older["speed"]), float(newer["speed"]), weight)
	longitudinal_speed = speed
	speed_kph = Vector2(velocity.x, velocity.z).length() * 3.6
	var flags: int = int(newer["flags"])
	braking = flags & NET_FLAG_BRAKING != 0
	handbrake_on = flags & NET_FLAG_HANDBRAKE != 0
	var speed_fraction: float = clampf(absf(speed) / maximum_forward_speed, 0.0, 1.0)
	_wheel_angle = _steering * lerpf(0.52, 0.12, speed_fraction)
	_update_visuals(delta, speed, true)
	if is_instance_valid(_tail_material):
		var lit: bool = flags & NET_FLAG_LIT != 0 and not disabled
		_tail_material.emission_energy_multiplier = 3.2 if braking else (0.7 if lit else 0.0)
		_head_material.emission_energy_multiplier = 1.6 if lit else 0.1


## Practice wheelman: pure-pursuit steering around a waypoint loop, slowing for corners,
## backing out when stuck. Offline practice only (no AI in real matches).
func _drive_autopilot(delta: float, forward: Vector3, longitudinal: float) -> void:
	_ai_steer = 0.0
	_ai_throttle = 0.0
	if autopilot_path.size() < 2:
		return
	if _ap_index < 0 and autopilot_loop_from > 0:
		_ap_index = 0
	if _ap_index < 0:
		var best: float = INF
		for index: int in range(autopilot_path.size()):
			var distance: float = autopilot_path[index].distance_to(global_position)
			var ahead: float = (autopilot_path[index] - global_position).dot(forward)
			if ahead > 0.0 and distance < best:
				best = distance
				_ap_index = index
		if _ap_index < 0:
			_ap_index = 0
	var target: Vector3 = autopilot_path[_ap_index]
	if Vector2(target.x - global_position.x, target.z - global_position.z).length() < 7.0:
		_ap_index = _ap_next(_ap_index)
		target = autopilot_path[_ap_index]
	var after: Vector3 = autopilot_path[_ap_next(_ap_index)]
	var to_target: Vector3 = target - global_position
	to_target.y = 0.0
	var local: Vector3 = global_transform.basis.inverse() * to_target
	var angle: float = atan2(local.x, -local.z)
	_ai_steer = clampf(angle * 1.8, -1.0, 1.0)
	var turn: float = absf((target - global_position).normalized().signed_angle_to((after - target).normalized(), Vector3.UP))
	var distance_left: float = to_target.length()
	var wanted: float = autopilot_speed
	if turn > 0.5 and distance_left < 22.0:
		wanted = lerpf(6.0, autopilot_speed, clampf((distance_left - 6.0) / 16.0, 0.0, 1.0))
	if absf(angle) > 0.6:
		wanted = minf(wanted, 7.0)
	_ai_throttle = clampf((wanted - longitudinal) * 0.35, -1.0, 1.0)
	if _ap_reverse > 0.0:
		_ap_reverse -= delta
		_ai_throttle = -0.8
		_ai_steer = -_ai_steer
		return
	if longitudinal < 1.0 and _ai_throttle > 0.3:
		_ap_stuck += delta
		if _ap_stuck > 2.2:
			_ap_stuck = 0.0
			_ap_reverse = 1.4
	else:
		_ap_stuck = 0.0


func _ap_next(index: int) -> int:
	return index + 1 if index + 1 < autopilot_path.size() else clampi(autopilot_loop_from, 0, autopilot_path.size() - 1)


func start_autopilot(path: PackedVector3Array, speed: float = 13.0, loop_from: int = 0) -> void:
	autopilot_path = path
	autopilot_speed = speed
	autopilot_loop_from = loop_from
	autopilot = true
	_ap_index = -1
	_ap_stuck = 0.0
	_ap_reverse = 0.0
	_resting = false


func stop_autopilot() -> void:
	autopilot = false
	_ai_steer = 0.0
	_ai_throttle = 0.0


func _check_impacts(before: Vector3, after: Vector3) -> void:
	var impact_speed: float = before.length()
	for index: int in range(get_slide_collision_count()):
		var collision: KinematicCollision3D = get_slide_collision(index)
		var other: Object = collision.get_collider()
		# Running into people or other cars hurts them; walls simply stop the car.
		if other != null and impact_speed > 3.0 and other.has_method("take_damage") and absf(collision.get_normal().y) < 0.7:
			other.take_damage(impact_speed * (4.0 if other is FastCar else 7.0), global_position)
			if other is FastCar:
				(other as FastCar).wake()
	var lost: float = impact_speed - after.length()
	if lost > 3.5 and is_instance_valid(_body):
		jolt(lost)
	if lost > 7.0:
		take_damage((lost - 7.0) * 12.0)
	if lost > 10.0 and get_slide_collision_count() > 0:
		# A hard hit breaks the window nearest the impact.
		var contact: Vector3 = get_slide_collision(0).get_position()
		var nearest: int = -1
		var best: float = INF
		for index: int in range(_glass.size()):
			if not bool(_glass[index]["broken"]):
				var distance: float = _glass_centre(index).distance_to(contact)
				if distance < best:
					best = distance
					nearest = index
		if nearest >= 0:
			break_glass(nearest)
	if (occupied or autopilot) and lost > 3.5:
		crashed.emit(lost)


func wake() -> void:
	_resting = false


func is_resting() -> bool:
	return _resting


## Online: the host's word on this car's health.
func set_net_health(value: float, is_disabled: bool) -> void:
	health = clampf(value, 0.0, max_health)
	if is_disabled and not disabled:
		disabled = true
		wrecked.emit()
	elif not is_disabled:
		disabled = false


## Bullets and crashes wear the vehicle down. At zero the engine dies: it still rolls and
## still gives cover, but it will not drive until the round (or the practice world) resets.
func take_damage(amount: float, _source: Vector3 = Vector3.INF) -> void:
	if amount <= 0.0 or disabled:
		return
	if net_damage_hook.is_valid():
		net_damage_hook.call(self, amount)
		return
	apply_damage(amount)


## Changes health directly (offline, or the host resolving online damage).
func apply_damage(amount: float) -> void:
	if amount <= 0.0 or disabled:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		disabled = true
		wrecked.emit()


func rear_contacts() -> Array[Vector3]:
	var points: Array[Vector3] = []
	var track: float = maxf(float(spec.get("track", 0.89)), 0.05)
	var rear: float = (spec.get("axles", Vector2(-1.36, 1.34)) as Vector2).y
	for side: float in [-1.0, 1.0]:
		points.append(global_transform * Vector3(side * track, 0.0, rear))
	return points


func reset_to_spawn() -> void:
	reset_car(spawn_transform.origin)
	rotation = spawn_transform.basis.get_euler()


func reset_car(pos: Vector3) -> void:
	global_position = pos
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	speed_kph = 0.0
	_steering = 0.0
	_wheel_angle = 0.0
	_previous_forward_speed = 0.0
	health = max_health
	disabled = false
	_resting = false
	stop_autopilot()
	if is_instance_valid(_body):
		_body.rotation = Vector3.ZERO
		_body_spin = Vector3.ZERO
		_bounce = 0.0
		_bounce_velocity = 0.0
	for entry: Dictionary in _glass:
		entry["open"] = false
		entry["broken"] = false
	_rebuild_glass()
	# Old snapshots would drag a reset puppet back to where it was.
	_net_buffer.clear()
	reset_physics_interpolation()


func exit_position() -> Vector3:
	# Driver's side; caller should check clearance before moving a player here.
	return door_position(0)


func _update_visuals(delta: float, forward_speed: float, grounded: bool) -> void:
	delta = minf(delta, 0.05)
	var acceleration: float = (forward_speed - _previous_forward_speed) / maxf(delta, 0.001)
	_previous_forward_speed = forward_speed
	# Suspension: readable pitch and roll on damped springs, a bounce on landings and big
	# crashes. A motorcycle leans into the turn instead of rolling out of it.
	var target_pitch: float = clampf(-acceleration * 0.0065, -0.09, 0.07) if grounded else -0.03
	var target_roll: float = clampf(_steering * forward_speed * 0.0085, -0.12, 0.12) if grounded else 0.0
	if is_bike():
		target_pitch *= 0.5
		target_roll = clampf(-_steering * forward_speed * 0.028, -0.5, 0.5) if grounded else 0.0
	_body_spin += (Vector3(target_pitch, 0.0, target_roll) - Vector3(_body.rotation.x, 0.0, _body.rotation.z)) * 70.0 * delta
	_body_spin *= exp(-7.5 * delta)
	_body.rotation.x += _body_spin.x * delta
	_body.rotation.z += _body_spin.z * delta
	if grounded and not _was_grounded:
		_bounce_velocity -= clampf(absf(_air_speed) * 0.25, 0.4, 2.5)
	_was_grounded = grounded
	_air_speed = velocity.y
	var rumble: float = sin(Time.get_ticks_msec() * 0.06) * 0.003 if (occupied or autopilot) and enabled and not disabled else 0.0
	_bounce_velocity += (0.0 - _bounce) * 140.0 * delta
	_bounce_velocity *= exp(-11.0 * delta)
	_bounce += _bounce_velocity * delta
	_body.position.y = 0.8 + _bounce + rumble
	for front_wheel: Node3D in _front_wheels:
		front_wheel.rotation.y = -_wheel_angle
	var wheel_radius: float = float(spec.get("wheel_r", 0.38))
	for spinner: Node3D in _spinners:
		spinner.rotate_object_local(Vector3.RIGHT, -forward_speed * delta / wheel_radius)
	if is_instance_valid(_tail_material):
		var lit: bool = (occupied or autopilot) and not disabled
		_tail_material.emission_energy_multiplier = 3.2 if braking else (0.7 if lit else 0.0)
		_head_material.emission_energy_multiplier = 1.6 if lit else 0.1


## Impulse from a crash: the body jolts and wobbles back.
func jolt(strength: float) -> void:
	_bounce_velocity -= clampf(strength * 0.1, 0.2, 1.6)
	_body_spin += Vector3(-clampf(strength * 0.2, 0.3, 2.4), 0.0, randf_range(-1.2, 1.2))
	_resting = false


# --- Collision hull -----------------------------------------------------------------------

func _shape(size: Vector3, at: Vector3, angle_x: float = 0.0) -> void:
	var collider: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	collider.shape = box
	collider.position = at
	collider.rotation.x = angle_x
	add_child(collider)


## Rounded runners under the body. A box hull catches on the internal edges where land
## collision triangles meet (the car stops dead mid-street); capsules glide over them.
const SKID: float = 0.13


func _skids(half_width: float, length: float, z: float) -> void:
	for side: float in ([0.0] if half_width <= 0.0 else [-1.0, 1.0]):
		var collider: CollisionShape3D = CollisionShape3D.new()
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = SKID
		capsule.height = length
		collider.shape = capsule
		collider.rotation.x = PI * 0.5
		collider.position = Vector3(side * half_width, SKID, z)
		add_child(collider)


## Lower body up to the beltline (riding on skids), roof and pillars above it: the window
## openings are open, so shots pass through them in both directions.
func _build_hull() -> void:
	var hull: Vector3 = spec["hull"]
	var belt: float = float(spec["belt"])
	match vehicle_type:
		"motorcycle":
			_shape(Vector3(0.5, 0.95 - SKID, 1.95), Vector3(0, SKID + (0.95 - SKID) * 0.5, 0.05))
			_skids(0.0, 1.9, 0.05)
		"pickup":
			var cabin: Vector2 = spec["cabin"]
			_shape(Vector3(hull.x, belt - SKID, hull.z), Vector3(0, SKID + (belt - SKID) * 0.5, 0))
			_skids(hull.x * 0.5 - 0.35, hull.z - 0.3, 0.0)
			_shape(Vector3(hull.x - 0.1, 0.12, cabin.y - cabin.x), Vector3(0, float(spec["roof"]) - 0.06, (cabin.x + cabin.y) * 0.5))
			for z: float in [cabin.x + 0.1, cabin.y - 0.05]:
				for side: float in [-1.0, 1.0]:
					_shape(Vector3(0.12, float(spec["roof"]) - belt, 0.14), Vector3(side * (hull.x * 0.5 - 0.1), (belt + float(spec["roof"])) * 0.5, z))
		_:
			var cabin: Vector2 = spec["cabin"]
			var roof: float = float(spec["roof"])
			_shape(Vector3(hull.x, belt - SKID, hull.z), Vector3(0, SKID + (belt - SKID) * 0.5, 0))
			_skids(hull.x * 0.5 - 0.35, hull.z - 0.3, 0.0)
			_shape(Vector3(hull.x - 0.14, 0.12, cabin.y - cabin.x), Vector3(0, roof - 0.06, (cabin.x + cabin.y) * 0.5))
			var pillars: Array[float] = [cabin.x + 0.12, cabin.y - 0.1]
			if spec.has("mid"):
				pillars.append(float(spec["mid"]))
			for z: float in pillars:
				for side: float in [-1.0, 1.0]:
					_shape(Vector3(0.12, roof - belt, 0.14), Vector3(side * (hull.x * 0.5 - 0.12), (belt + roof) * 0.5, z))


# --- Models ------------------------------------------------------------------------------

func _build_model() -> void:
	var paint: StandardMaterial3D = _paint(paint_color)
	var trim: StandardMaterial3D = _mat(Color("1b1f22"), 0.7)
	var chrome: StandardMaterial3D = _mat(Color("a9b0b3"), 0.25, 0.8)
	var headlamp: StandardMaterial3D = _mat(Color("f2e7b4"), 0.3)
	var tail_lamp: StandardMaterial3D = _mat(Color("b62f32"), 0.4)
	headlamp.emission_enabled = true
	headlamp.emission = Color("fff1c4")
	headlamp.emission_energy_multiplier = 0.1
	tail_lamp.emission_enabled = true
	tail_lamp.emission = Color("ff2a22")
	tail_lamp.emission_energy_multiplier = 0.0
	_head_material = headlamp
	_tail_material = tail_lamp
	match vehicle_type:
		"coupe": _build_coupe(paint, trim, chrome)
		"suv": _build_suv(paint, trim, chrome)
		"pickup": _build_pickup(paint, trim, chrome)
		"motorcycle": _build_bike(paint, trim, chrome)
		_: _build_sedan(paint, trim, chrome)
	_build_wheels()
	# The body shell becomes one mesh per material. The glass is its own mesh, rebuilt when
	# a gunner rolls a window down or a window breaks.
	MeshMerge.merge_children(_body)
	_limit_draw_distance(self)
	_rebuild_glass()


## Vehicles are the busiest meshes in the city (a dozen materials each): past 130 m they
## are not drawn, and glass, wheels and small parts never cast shadows.
func _limit_draw_distance(node: Node) -> void:
	for child: Node in node.get_children():
		if child is GeometryInstance3D:
			var geometry: GeometryInstance3D = child as GeometryInstance3D
			geometry.visibility_range_end = 130.0
			geometry.visibility_range_end_margin = 8.0
			if node != _body:
				geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_limit_draw_distance(child)


## One fleet, late-90s / early-2000s: every car body is a side profile extruded across its
## width (VehicleKit.profile) with real wheel-arch cut-outs, bevelled shoulders and a
## little tumblehome, a glasshouse whose pillars, roof and panes follow the same profile
## lines, clear-lens lamps, and the same wheel family. Heights here are metres above the
## road; the body node sits 0.8 m up, so builders subtract BODY_Y.
const BODY_Y: float = 0.8
const BODY: Dictionary = {
	"sedan": {"width": 1.86, "arch": 0.43, "tuck": 0.07, "rim": "cap",
		"nose": [Vector2(-2.19, 0.3), Vector2(-2.23, 0.48), Vector2(-2.22, 0.66), Vector2(-2.1, 0.76)],
		"top": [Vector2(-1.2, 0.9), Vector2(1.34, 0.93), Vector2(1.48, 0.96), Vector2(2.1, 0.94)],
		"tail": [Vector2(2.19, 0.78), Vector2(2.22, 0.5), Vector2(2.18, 0.3)],
		"glass": [Vector2(-1.17, 0.91), Vector2(-0.5, 1.43), Vector2(0.8, 1.44), Vector2(1.38, 0.95)],
		"belt_half": 0.86, "roof_half": 0.68, "posts": [0.22], "roll": [true, true]},
	"coupe": {"width": 1.82, "arch": 0.38, "tuck": 0.08, "rim": "alloy",
		"nose": [Vector2(-2.14, 0.26), Vector2(-2.19, 0.42), Vector2(-2.16, 0.56), Vector2(-2.03, 0.67)],
		"top": [Vector2(-0.56, 0.8), Vector2(1.5, 0.86), Vector2(2.02, 0.88)],
		"tail": [Vector2(2.13, 0.8), Vector2(2.16, 0.5), Vector2(2.1, 0.28)],
		"glass": [Vector2(-0.52, 0.82), Vector2(0.1, 1.27), Vector2(0.62, 1.28), Vector2(1.74, 0.88)],
		"belt_half": 0.83, "roof_half": 0.63, "posts": [0.78], "roll": [true, false]},
	"suv": {"width": 2.0, "arch": 0.5, "tuck": 0.05, "rim": "offroad",
		"nose": [Vector2(-2.3, 0.46), Vector2(-2.39, 0.62), Vector2(-2.37, 0.98), Vector2(-2.27, 1.1)],
		"top": [Vector2(-1.0, 1.22), Vector2(2.3, 1.25)],
		"tail": [Vector2(2.38, 1.12), Vector2(2.4, 0.64), Vector2(2.34, 0.46)],
		"glass": [Vector2(-0.98, 1.23), Vector2(-0.38, 1.86), Vector2(2.24, 1.88), Vector2(2.35, 1.26)],
		"belt_half": 0.93, "roof_half": 0.84, "posts": [0.27, 1.4], "roll": [true, true, false]},
	"pickup": {"width": 1.98, "arch": 0.48, "tuck": 0.05, "rim": "offroad",
		"nose": [Vector2(-2.6, 0.42), Vector2(-2.68, 0.6), Vector2(-2.66, 0.96), Vector2(-2.56, 1.07)],
		"top": [Vector2(-1.15, 1.2), Vector2(0.18, 1.22)],
		"tail": [Vector2(0.2, 0.42)],
		"glass": [Vector2(-1.12, 1.22), Vector2(-0.62, 1.86), Vector2(0.06, 1.88), Vector2(0.14, 1.24)],
		"belt_half": 0.9, "roof_half": 0.8, "posts": [], "roll": [true]},
}


func _spec_body() -> Dictionary:
	return BODY[vehicle_type] as Dictionary


## Body-space position from a (z, height above road) profile point.
func _bp(point: Vector2, x: float = 0.0) -> Vector3:
	return Vector3(x, point.y - BODY_Y, point.x)


## Lower-body outline: nose, bonnet and deck, tail, then the sills with arch cut-outs.
func _lower_outline(body: Dictionary, front_axle_only: bool = false) -> PackedVector2Array:
	var outline: PackedVector2Array = PackedVector2Array()
	for key: String in ["nose", "top", "tail"]:
		for point: Vector2 in body[key]:
			outline.append(Vector2(point.x, point.y - BODY_Y))
	var sill: float = (body["nose"] as Array)[0].y
	var axles: Vector2 = spec["axles"]
	var ends: Array = [axles.x] if front_axle_only else [axles.y, axles.x]
	for axle: float in ends:
		_arch(outline, axle, float(spec["wheel_r"]), float(body["arch"]), sill)
	return outline


## Appends a wheel arch (rear side first, going forward) to a sill line at `sill`.
func _arch(outline: PackedVector2Array, axle: float, wheel: float, radius: float, sill: float) -> void:
	var lift: float = clampf((sill - wheel) / radius, -0.95, 0.95)
	# The arc's end points sit on the sill line itself, so no extra sill points (duplicates
	# would stop the outline triangulating).
	var start: float = asin(lift)
	for step: int in range(11):
		var angle: float = lerpf(start, PI - start, step / 10.0)
		outline.append(Vector2(axle + radius * cos(angle), wheel + radius * sin(angle) - BODY_Y))


## Half-width of the body side at a height above the road (tumblehome included).
func _side_x(body: Dictionary, height: float) -> float:
	var sill: float = (body["nose"] as Array)[0].y
	var peak: float = 0.0
	for key: String in ["nose", "top", "tail"]:
		for point: Vector2 in body[key]:
			peak = maxf(peak, point.y)
	return float(body["width"]) * 0.5 - float(body["tuck"]) * clampf((height - sill) / maxf(peak - sill, 0.01), 0.0, 1.0)


func _car_body(paint: StandardMaterial3D, trim: StandardMaterial3D, chrome: StandardMaterial3D) -> void:
	var body: Dictionary = _spec_body()
	var width: float = body["width"]
	var axles: Vector2 = spec["axles"]
	var glass: Array = body["glass"]
	var cabin_open: Vector2 = Vector2((glass[0] as Vector2).x + 0.25, (glass[3] as Vector2).x - 0.05)
	_part(VehicleKit.profile(_lower_outline(body, vehicle_type == "pickup"), width * 0.5, 0.07, float(body["tuck"]), cabin_open, float(body["belt_half"]) - 0.14), Vector3.ZERO, paint)
	# Dark wheel-well liners behind every arch.
	var well: StandardMaterial3D = _mat(Color(0.035, 0.035, 0.04), 0.95)
	for axle: float in [axles.x, axles.y]:
		var arch: float = body["arch"]
		for side: float in [-1.0, 1.0]:
			_soft(Vector3(0.22, arch * 1.05, arch * 1.9), Vector3(side * (width * 0.5 - 0.19), float(spec["wheel_r"]) + arch * 0.35 - BODY_Y, axle), well, 0.05)
	_glasshouse(body, paint, trim)
	_cabin_interior(body, trim)


## Roof, pillars and glass along the profile's four glass points: screen base, roof front,
## roof rear, backlight base. Side windows run between the A and C pillar lines and the
## posts in body["posts"]; rows flagged in body["roll"] roll down for gunners.
func _glasshouse(body: Dictionary, paint: StandardMaterial3D, trim: StandardMaterial3D) -> void:
	var g: Array = body["glass"]
	var belt: float = (g[0] as Vector2).y
	var belt_half: float = body["belt_half"]
	var roof_half: float = body["roof_half"]
	var roof_y: float = maxf((g[1] as Vector2).y, (g[2] as Vector2).y)
	# Roof skin: a thin profile with rounded edges.
	var roof: PackedVector2Array = PackedVector2Array([
		Vector2((g[1] as Vector2).x - 0.03, (g[1] as Vector2).y + 0.03 - BODY_Y), Vector2((g[2] as Vector2).x + 0.03, (g[2] as Vector2).y + 0.03 - BODY_Y),
		Vector2((g[2] as Vector2).x - 0.05, (g[2] as Vector2).y - 0.04 - BODY_Y), Vector2((g[1] as Vector2).x + 0.05, (g[1] as Vector2).y - 0.04 - BODY_Y)])
	_part(VehicleKit.profile(roof, roof_half + 0.04, 0.035, 0.0), Vector3.ZERO, paint)
	var x_at: Callable = func(height: float) -> float: return lerpf(belt_half, roof_half, clampf((height - belt) / maxf(roof_y - belt, 0.01), 0.0, 1.0))
	var a_line: Callable = func(height: float) -> float: return lerpf((g[0] as Vector2).x, (g[1] as Vector2).x, clampf((height - (g[0] as Vector2).y) / ((g[1] as Vector2).y - (g[0] as Vector2).y), 0.0, 1.0))
	var c_line: Callable = func(height: float) -> float: return lerpf((g[3] as Vector2).x, (g[2] as Vector2).x, clampf((height - (g[3] as Vector2).y) / ((g[2] as Vector2).y - (g[3] as Vector2).y), 0.0, 1.0))
	var roof_at: Callable = func(z: float) -> float: return lerpf((g[1] as Vector2).y, (g[2] as Vector2).y, clampf((z - (g[1] as Vector2).x) / maxf((g[2] as Vector2).x - (g[1] as Vector2).x, 0.01), 0.0, 1.0))
	# Pillars: A and C follow the screens; posts between the side windows are blacked out.
	for side: float in [-1.0, 1.0]:
		for line: Array in [[g[0], g[1]], [g[3], g[2]]]:
			var low: Vector2 = line[0]
			var high: Vector2 = line[1]
			var pillar: MeshInstance3D = _part(MeshKit.rounded_box(Vector3(0.075, 1.0, 0.09), 0.025, 1), Vector3.ZERO, paint)
			var from: Vector3 = _bp(low, side * (float(x_at.call(low.y)) - 0.02))
			var to: Vector3 = _bp(high, side * (float(x_at.call(high.y)) - 0.02))
			pillar.transform = VehicleKit.strut(from, to)
			pillar.scale = Vector3(1.0, from.distance_to(to), 1.0)
		for post: float in body["posts"]:
			var top: float = roof_at.call(post)
			var bar: MeshInstance3D = _part(MeshKit.rounded_box(Vector3(0.07, 1.0, 0.12), 0.02, 1), Vector3.ZERO, trim)
			var from: Vector3 = _bp(Vector2(post, belt), side * (belt_half - 0.02))
			var to: Vector3 = _bp(Vector2(post, top), side * (roof_half - 0.02))
			bar.transform = VehicleKit.strut(from, to)
			bar.scale = Vector3(1.0, from.distance_to(to), 1.0)
	# Screens (fixed).
	for line: Array in [[g[0], g[1]], [g[3], g[2]]]:
		var low: Vector2 = line[0]
		var high: Vector2 = line[1]
		var points: Array = [_bp(low, -belt_half + 0.1), _bp(low, belt_half - 0.1), _bp(high, roof_half - 0.08), _bp(high, -roof_half + 0.08)]
		_add_glass(points, -1)
	# Side windows between the pillar lines and posts.
	var bottom: float = belt + 0.03
	var breaks: Array = [null]
	breaks.append_array(body["posts"])
	breaks.append(null)
	var rolls: Array = body["roll"]
	for row: int in range(breaks.size() - 1):
		for side: float in [-1.0, 1.0]:
			var points: Array = []
			var front_low: float = float(a_line.call(bottom)) + 0.06 if breaks[row] == null else float(breaks[row]) + 0.06
			var rear_low: float = float(c_line.call(bottom)) - 0.06 if breaks[row + 1] == null else float(breaks[row + 1]) - 0.06
			var front_top_y: float = float(roof_at.call(front_low)) - 0.05
			var rear_top_y: float = float(roof_at.call(rear_low)) - 0.05
			var front_high: float = float(a_line.call(front_top_y)) + 0.06 if breaks[row] == null else front_low
			var rear_high: float = float(c_line.call(rear_top_y)) - 0.06 if breaks[row + 1] == null else rear_low
			for corner: Vector2 in [Vector2(front_low, bottom), Vector2(front_high, front_top_y), Vector2(rear_high, rear_top_y), Vector2(rear_low, bottom)]:
				points.append(_bp(corner, side * (float(x_at.call(corner.y)) - 0.03)))
			var roll: int = row * 2 + (0 if side < 0.0 else 1) if row < rolls.size() and bool(rolls[row]) else -1
			_add_glass(points, roll)


## Dash, steering wheel and seats (just behind each seat's eye point), visible through
## the glass and from the passenger seats.
func _cabin_interior(body: Dictionary, trim: StandardMaterial3D) -> void:
	var g: Array = body["glass"]
	var belt: float = (g[0] as Vector2).y - BODY_Y
	var cloth: StandardMaterial3D = _mat(Color(0.16, 0.14, 0.13), 0.95)
	var dash_z: float = (g[0] as Vector2).x + 0.10
	_soft(Vector3(float(body["belt_half"]) * 2.0 - 0.12, 0.20, 0.30), Vector3(0, belt - 0.12, dash_z), trim, 0.05)
	var driver_eye: Vector3 = (seats[0] as Dictionary)["eye"]
	var wheel: MeshInstance3D = _part(MeshKit.torus(0.15, 0.18, 18, 6), Vector3(driver_eye.x, belt + 0.02, dash_z + 0.20), trim)
	wheel.rotation = Vector3(PI * 0.5 - 0.5, 0, 0)
	var floor_y: float = (body["nose"] as Array)[0].y - BODY_Y + 0.12
	var front: float = (g[0] as Vector2).x + 0.25
	var rear: float = (g[3] as Vector2).x - 0.05
	var inner: float = float(body["belt_half"]) - 0.14
	_soft(Vector3(inner * 2 + 0.08, 0.05, rear - front), Vector3(0, floor_y - 0.025, (front + rear) * 0.5), cloth, 0.01)
	for side: float in [-1.0, 1.0]:
		_soft(Vector3(0.06, belt - floor_y, rear - front), Vector3(side * (inner + 0.03), (belt + floor_y) * 0.5, (front + rear) * 0.5), trim, 0.02)
		_soft(Vector3(0.12, 0.08, 0.6), Vector3(side * (inner - 0.04), belt - 0.17, driver_eye.z), cloth, 0.02)
	# Restrained dashboard details, all using the existing trim/cloth materials.
	_soft(Vector3(0.3, 0.09, 0.035), Vector3(driver_eye.x, belt - 0.05, dash_z + 0.155), cloth, 0.015)
	_soft(Vector3(0.2, 0.16, 0.45), Vector3(0, floor_y + 0.09, driver_eye.z - 0.05), trim, 0.02)
	for seat_spec: Dictionary in seats:
		var eye: Vector3 = seat_spec["eye"]
		if eye.y > float(spec["roof"]) or str(seat_spec["shoot"]) == "open":
			continue
		var seat_at: Vector3 = Vector3(eye.x * 0.8, 0.0, eye.z + 0.14)
		# A seated eye is ~0.75 m over the cushion; the headrest stays under the roof lining.
		var cushion_y: float = maxf(floor_y + 0.08, eye.y - BODY_Y - 0.75)
		_soft(Vector3(0.52, 0.14, 0.5), Vector3(seat_at.x, cushion_y, seat_at.z), cloth, 0.05)
		_soft(Vector3(0.5, 0.56, 0.14), Vector3(seat_at.x, cushion_y + 0.33, seat_at.z + 0.3), cloth, 0.05, Vector3(-0.14, 0, 0))
		_soft(Vector3(0.26, 0.18, 0.1), Vector3(seat_at.x, cushion_y + 0.68, seat_at.z + 0.34), cloth, 0.04, Vector3(-0.14, 0, 0))


## Clear-lens headlamps with an amber corner lamp, a grille, a wraparound tail-lamp bar,
## bumpers with a rubbing strip, door shut-lines, handles, mirrors, plates and a tailpipe.
func _car_details(paint: StandardMaterial3D, trim: StandardMaterial3D, chrome: StandardMaterial3D, grille_chrome: bool, lamp_height: float, tail_height: float, tail_style: String) -> void:
	var body: Dictionary = _spec_body()
	var nose: Array = body["nose"]
	var tail: Array = body["tail"]
	var front_z: float = _surface_z(nose, lamp_height)
	var rear_z: float = _rear_z(tail_height)
	var amber: StandardMaterial3D = _mat(Color(0.95, 0.55, 0.12), 0.35)
	var half: float = _side_x(body, lamp_height) - 0.06
	# Front: lamps, corner lamps and grille.
	for side: float in [-1.0, 1.0]:
		var lamp_x: float = side * (half - 0.28)
		_soft(Vector3(0.5, 0.17, 0.05), Vector3(lamp_x, lamp_height - BODY_Y, front_z - 0.01), _head_material, 0.03)
		_soft(Vector3(0.54, 0.21, 0.04), Vector3(lamp_x, lamp_height - BODY_Y, front_z + 0.005), chrome, 0.03)
		_soft(Vector3(0.12, 0.15, 0.2), Vector3(side * (half + 0.02), lamp_height - BODY_Y, front_z + 0.1), amber, 0.03)
	var grille_width: float = (half - 0.55) * 2.0
	_soft(Vector3(grille_width, 0.16, 0.05), Vector3(0, lamp_height - 0.01 - BODY_Y, front_z - 0.005), _mat(Color(0.05, 0.05, 0.055), 0.6), 0.03)
	if grille_chrome:
		_soft(Vector3(grille_width + 0.06, 0.2, 0.03), Vector3(0, lamp_height - 0.01 - BODY_Y, front_z + 0.01), chrome, 0.02)
		for bar: int in range(3):
			_soft(Vector3(grille_width, 0.02, 0.03), Vector3(0, lamp_height - 0.06 + bar * 0.05 - BODY_Y, front_z - 0.02), chrome, 0.005)
	# Rear lamps.
	var tail_half: float = _side_x(body, tail_height) - 0.05
	match tail_style:
		"bar":
			_soft(Vector3(tail_half * 2.0 - 0.1, 0.13, 0.05), Vector3(0, tail_height - BODY_Y, rear_z + 0.01), _tail_material, 0.03)
			for side: float in [-1.0, 1.0]:
				_soft(Vector3(0.18, 0.13, 0.055), Vector3(side * (tail_half - 0.2), tail_height - BODY_Y, rear_z + 0.012), amber, 0.03)
		"tall":
			for side: float in [-1.0, 1.0]:
				_soft(Vector3(0.16, 0.46, 0.06), Vector3(side * (tail_half - 0.06), tail_height - BODY_Y, rear_z + 0.01), _tail_material, 0.03)
		_:
			for side: float in [-1.0, 1.0]:
				_soft(Vector3(0.4, 0.14, 0.05), Vector3(side * (tail_half - 0.25), tail_height - BODY_Y, rear_z + 0.01), _tail_material, 0.04)
	# Plates and a tailpipe.
	var plate: StandardMaterial3D = _mat(Color(0.88, 0.86, 0.72), 0.5)
	_soft(Vector3(0.46, 0.13, 0.02), Vector3(0, (nose[0] as Vector2).y + 0.1 - BODY_Y, front_z - 0.02), plate, 0.01)
	_soft(Vector3(0.46, 0.13, 0.02), Vector3(0, tail_height - 0.2 - BODY_Y, rear_z + 0.03), plate, 0.01)
	var pipe: MeshInstance3D = _part(MeshKit.cylinder(0.035, 0.035, 0.24, 8), Vector3(0.45, (nose[0] as Vector2).y + 0.02 - BODY_Y, rear_z - 0.06), chrome)
	pipe.rotation.x = PI * 0.5
	# Mirrors on stalks at the A-pillar foot, door handles and the door shut-lines.
	var g: Array = body["glass"]
	var belt: float = (g[0] as Vector2).y
	var seam: StandardMaterial3D = _mat(Color(0.05, 0.05, 0.05), 0.8)
	for side: float in [-1.0, 1.0]:
		var skin: float = side * (_side_x(body, belt - 0.15) + 0.004)
		_soft(Vector3(0.1, 0.12, 0.2), Vector3(side * (float(body["belt_half"]) + 0.14), belt + 0.08 - BODY_Y, (g[0] as Vector2).x + 0.22), trim, 0.03)
		_soft(Vector3(0.14, 0.03, 0.05), Vector3(side * (float(body["belt_half"]) + 0.05), belt + 0.04 - BODY_Y, (g[0] as Vector2).x + 0.22), trim, 0.01)
		var cuts: Array = [(g[0] as Vector2).x - 0.02]
		cuts.append_array(body["posts"])
		for index: int in range(cuts.size()):
			var cut: float = float(cuts[index])
			_soft(Vector3(0.012, belt - (nose[0] as Vector2).y - 0.12, 0.012), Vector3(skin, (belt + (nose[0] as Vector2).y) * 0.5 - BODY_Y, cut), seam, 0.004)
			if index < (body["roll"] as Array).size() and bool(body["roll"][index]):
				_soft(Vector3(0.03, 0.04, 0.16), Vector3(skin + side * 0.01, belt - 0.14 - BODY_Y, cut + 0.62 if index == 0 else cut + 0.25), chrome, 0.01)
		# Rubbing strip along the doors.
		_soft(Vector3(0.025, 0.05, 1.8), Vector3(side * (_side_x(body, belt - 0.36) + 0.01), belt - 0.36 - BODY_Y, (g[0] as Vector2).x + 1.0), trim, 0.01)
	if stripe_color.a > 0.0:
		var stripe: StandardMaterial3D = _paint(stripe_color)
		var stripe_y: float = belt - 0.2
		var length: float = rear_z - front_z - 0.6
		for side: float in [-1.0, 1.0]:
			_soft(Vector3(0.02, 0.08, length), Vector3(side * (_side_x(body, stripe_y) + 0.006), stripe_y - BODY_Y, (front_z + rear_z) * 0.5), stripe, 0.01)
		_soft(Vector3(0.32, 0.02, absf((g[2] as Vector2).x - (g[1] as Vector2).x)), Vector3(0, maxf((g[1] as Vector2).y, (g[2] as Vector2).y) + 0.04 - BODY_Y, ((g[1] as Vector2).x + (g[2] as Vector2).x) * 0.5), stripe, 0.008)


## Where the nose (or tail) outline crosses a height above the road.
func _surface_z(points: Array, height: float) -> float:
	var best: float = (points[0] as Vector2).x
	for index: int in range(points.size() - 1):
		var a: Vector2 = points[index]
		var b: Vector2 = points[index + 1]
		if (height - a.y) * (height - b.y) <= 0.0 and absf(b.y - a.y) > 0.0001:
			return lerpf(a.x, b.x, (height - a.y) / (b.y - a.y))
		if absf(a.y - height) < absf(best - height):
			best = a.x
	return best


func _rear_z(height: float) -> float:
	if vehicle_type == "pickup":
		return 2.7
	var body: Dictionary = _spec_body()
	var tail: Array = [(body["top"] as Array).back()]
	tail.append_array(body["tail"])
	return _surface_z(tail, height)


## A black plastic fender flare: a half-ring band round the top of a wheel arch.
func _flare(axle: float, wheel: float, arch: float, sill: float) -> ArrayMesh:
	var band: PackedVector2Array = PackedVector2Array()
	var start: float = asin(clampf((sill - wheel) / arch, -0.95, 0.95))
	for step: int in range(11):
		var angle: float = lerpf(start, PI - start, step / 10.0)
		band.append(Vector2(axle + (arch + 0.09) * cos(angle), wheel + (arch + 0.09) * sin(angle) - BODY_Y))
	for step: int in range(10, -1, -1):
		var angle: float = lerpf(start, PI - start, step / 10.0)
		band.append(Vector2(axle + arch * cos(angle), wheel + arch * sin(angle) - BODY_Y))
	return VehicleKit.profile(band, 0.05, 0.02, 0.0)


func _bumpers(material: StandardMaterial3D, height: float, depth: float, wrap: float) -> void:
	var body: Dictionary = _spec_body()
	var nose: Array = body["nose"]
	var tail: Array = body["tail"]
	var front_z: float = _surface_z(nose, height)
	var rear_z: float = _rear_z(height)
	var half: float = _side_x(body, height)
	for end: float in [-1.0, 1.0]:
		var z: float = front_z if end < 0.0 else rear_z
		_soft(Vector3(half * 2.0 + 0.04, 0.2, depth), Vector3(0, height - BODY_Y, z + end * depth * 0.3), material, 0.07)
		for side: float in [-1.0, 1.0]:
			_soft(Vector3(0.1, 0.2, wrap), Vector3(side * (half - 0.02), height - BODY_Y, z - end * wrap * 0.4), material, 0.05)


func _build_sedan(paint: StandardMaterial3D, trim: StandardMaterial3D, chrome: StandardMaterial3D) -> void:
	# Full-size late-90s saloon: long bonnet and boot, upright six-light glasshouse, chrome
	# grille and a full-width tail-lamp bar. The workhorse (and the taxi).
	_car_body(paint, trim, chrome)
	_car_details(paint, trim, chrome, true, 0.7, 0.82, "bar")
	_bumpers(_mat(Color(0.12, 0.12, 0.13), 0.7), 0.5, 0.2, 0.5)
	var antenna: MeshInstance3D = _part(MeshKit.cylinder(0.006, 0.006, 0.7, 4), Vector3(0.6, 1.3 - BODY_Y, 1.7), chrome)
	antenna.rotation.x = 0.15


func _build_coupe(paint: StandardMaterial3D, trim: StandardMaterial3D, chrome: StandardMaterial3D) -> void:
	# Sport-compact coupe: low nose, long bonnet, fastback glass, a wing on the boot lid,
	# side skirts, black grille slot and a lower air dam. Fast and fragile.
	_car_body(paint, trim, chrome)
	_car_details(paint, trim, trim, false, 0.58, 0.76, "twin")
	_soft(Vector3(1.5, 0.08, 0.3), Vector3(0, 0.3 - BODY_Y, -2.12), trim, 0.03)
	_soft(Vector3(1.66, 0.04, 0.3), Vector3(0, 1.02 - BODY_Y, 1.96), paint, 0.02)
	for side: float in [-0.62, 0.62]:
		_soft(Vector3(0.05, 0.12, 0.12), Vector3(side, 0.93 - BODY_Y, 1.96), trim, 0.02)
	for side: float in [-1.0, 1.0]:
		_soft(Vector3(0.05, 0.1, 1.76), Vector3(side * 0.9, 0.32 - BODY_Y, -0.05), trim, 0.03)
	_soft(Vector3(0.5, 0.04, 0.7), Vector3(0, 0.72 - BODY_Y, -1.2), _paint(paint_color.darkened(0.25)), 0.02)


func _build_suv(paint: StandardMaterial3D, trim: StandardMaterial3D, chrome: StandardMaterial3D) -> void:
	# Mid-size body-on-frame 4x4: tall two-box shape, black fender flares and bumpers, step
	# bars, roof rails, chrome grille, rear quarter glass and a spare wheel on the tailgate.
	_car_body(paint, trim, chrome)
	_car_details(paint, trim, chrome, true, 0.95, 1.0, "tall")
	var plastic: StandardMaterial3D = _mat(Color(0.14, 0.14, 0.15), 0.8)
	_bumpers(plastic, 0.62, 0.26, 0.45)
	var body: Dictionary = BODY["suv"]
	var axles: Vector2 = spec["axles"]
	for side: float in [-1.0, 1.0]:
		for axle: float in [axles.x, axles.y]:
			_part(_flare(axle, float(spec["wheel_r"]), float(body["arch"]), 0.46), Vector3(side * (float(body["width"]) * 0.5 + 0.02), 0, 0), plastic)
		_soft(Vector3(0.22, 0.06, 1.8), Vector3(side * 1.02, 0.42 - BODY_Y, -0.02), plastic, 0.02)
		_soft(Vector3(0.05, 0.06, 2.3), Vector3(side * 0.74, 1.94 - BODY_Y, 0.9), trim, 0.02)
		for z: float in [-0.2, 2.0]:
			_soft(Vector3(0.06, 0.08, 0.08), Vector3(side * 0.74, 1.91 - BODY_Y, z), trim, 0.02)
	for z: float in [0.3, 1.6]:
		_soft(Vector3(1.5, 0.04, 0.05), Vector3(0, 1.97 - BODY_Y, z), trim, 0.02)
	var spare: MeshInstance3D = _part(MeshKit.torus(0.24, 0.4, 20, 8), Vector3(0, 0.95 - BODY_Y, 2.5), _mat(Color(0.05, 0.05, 0.06), 0.9))
	spare.rotation.x = PI * 0.5
	var cover: MeshInstance3D = _part(MeshKit.cylinder(0.3, 0.3, 0.1, 18), Vector3(0, 0.95 - BODY_Y, 2.52), paint)
	cover.rotation.x = PI * 0.5
	for x: float in [-0.5, 0.5]:
		_soft(Vector3(0.07, 0.34, 0.07), Vector3(x, 0.72 - BODY_Y, -2.5), chrome, 0.02)
	_soft(Vector3(1.2, 0.07, 0.07), Vector3(0, 0.86 - BODY_Y, -2.52), chrome, 0.02)


func _build_pickup(paint: StandardMaterial3D, trim: StandardMaterial3D, chrome: StandardMaterial3D) -> void:
	# Full-size regular-cab pickup: long bonnet, big chrome grille and bumpers, upright cab,
	# and an open bed (two gunners kneel in it) with its own rear arches.
	_car_body(paint, trim, chrome)
	_car_details(paint, trim, chrome, true, 0.95, 0.98, "tall")
	_bumpers(chrome, 0.58, 0.22, 0.3)
	var body: Dictionary = BODY["pickup"]
	var axles: Vector2 = spec["axles"]
	var width: float = body["width"]
	# Bed sides are thin profiles with the rear arch cut out; floor, headboard, tailgate.
	var side_outline: PackedVector2Array = PackedVector2Array([Vector2(0.26, 0.42 - BODY_Y), Vector2(0.26, 1.18 - BODY_Y), Vector2(2.64, 1.18 - BODY_Y), Vector2(2.68, 0.42 - BODY_Y)])
	var arch_part: PackedVector2Array = PackedVector2Array()
	_arch(arch_part, axles.y, float(spec["wheel_r"]), float(body["arch"]), 0.42)
	side_outline.append_array(arch_part)
	for side: float in [-1.0, 1.0]:
		_part(VehicleKit.profile(side_outline, 0.06, 0.02, 0.0), Vector3(side * (width * 0.5 - 0.06), 0, 0), paint)
		_soft(Vector3(0.1, 0.05, 2.4), Vector3(side * (width * 0.5 - 0.06), 1.2 - BODY_Y, 1.46), trim, 0.02)
		_part(MeshKit.rounded_box(Vector3(0.36, 0.5, 1.0), 0.06, 1), Vector3(side * (width * 0.5 - 0.3), 0.72 - BODY_Y, axles.y), paint)
	var metal: StandardMaterial3D = _mat(Color(0.2, 0.21, 0.22), 0.6, 0.3)
	_soft(Vector3(width - 0.12, 0.06, 2.4), Vector3(0, 0.66 - BODY_Y, 1.46), metal, 0.02)
	_soft(Vector3(width - 0.1, 0.56, 0.08), Vector3(0, 0.92 - BODY_Y, 0.26), paint, 0.03)
	_soft(Vector3(width, 0.64, 0.08), Vector3(0, 0.88 - BODY_Y, 2.66), paint, 0.03)
	_soft(Vector3(0.9, 0.08, 0.04), Vector3(0, 1.05 - BODY_Y, 2.71), chrome, 0.02)
	_soft(Vector3(width - 0.3, 0.22, 0.12), Vector3(0, 0.52 - BODY_Y, 2.5), _mat(Color(0.1, 0.1, 0.11), 0.8), 0.03)
	for side: float in [-1.0, 1.0]:
		_soft(Vector3(0.22, 0.05, 1.3), Vector3(side * 1.02, 0.42 - BODY_Y, -0.5), _mat(Color(0.14, 0.14, 0.15), 0.8), 0.02)


func _build_bike(paint: StandardMaterial3D, trim: StandardMaterial3D, chrome: StandardMaterial3D) -> void:
	# A late-90s standard (naked) bike: sculpted tank and tail, a finned air-cooled engine,
	# 4-into-1 exhaust, telescopic forks, a round lamp and twin clocks.
	var dark: StandardMaterial3D = _mat(Color(0.06, 0.065, 0.07), 0.6, 0.4)
	var alloy: StandardMaterial3D = _mat(Color(0.55, 0.57, 0.58), 0.35, 0.7)
	var leather: StandardMaterial3D = _mat(Color(0.07, 0.065, 0.065), 0.7)
	var axles: Vector2 = spec["axles"]
	var wheel: float = spec["wheel_r"]
	# Frame spine and swingarm.
	_strut_part(MeshKit.rounded_box(Vector3(0.07, 1.0, 0.07), 0.02, 1), Vector3(0, 0.98 - BODY_Y, -0.52), Vector3(0, 0.82 - BODY_Y, 0.42), dark)
	for side: float in [-1.0, 1.0]:
		_strut_part(MeshKit.rounded_box(Vector3(0.05, 1.0, 0.08), 0.02, 1), Vector3(side * 0.11, 0.5 - BODY_Y, 0.12), Vector3(side * 0.11, wheel - BODY_Y, axles.y), dark)
		_strut_part(MeshKit.cylinder(0.025, 0.025, 1.0, 8), Vector3(side * 0.12, 0.52 - BODY_Y, 0.5), Vector3(side * 0.12, 0.92 - BODY_Y, 0.38), alloy)
	# Engine: crankcase, finned cylinder block, and the exhaust down the right side.
	_soft(Vector3(0.36, 0.3, 0.46), Vector3(0, 0.45 - BODY_Y, -0.02), alloy, 0.06)
	for fin: int in range(5):
		_soft(Vector3(0.4, 0.03, 0.3), Vector3(0, 0.62 + fin * 0.05 - BODY_Y, -0.18), alloy, 0.01, Vector3(-0.35, 0, 0))
	_strut_part(MeshKit.cylinder(0.035, 0.035, 1.0, 8), Vector3(0.1, 0.62 - BODY_Y, -0.36), Vector3(0.16, 0.34 - BODY_Y, 0.1), chrome)
	_strut_part(MeshKit.cylinder(0.06, 0.05, 1.0, 10), Vector3(0.18, 0.36 - BODY_Y, 0.12), Vector3(0.2, 0.52 - BODY_Y, 0.78), chrome)
	# Tank, seat and tail as profiles: the silhouette that says "motorcycle" at 100 m.
	var tank: PackedVector2Array = PackedVector2Array([Vector2(-0.56, 0.86), Vector2(-0.5, 1.07), Vector2(-0.2, 1.12), Vector2(0.06, 1.02), Vector2(0.08, 0.86)])
	for index: int in range(tank.size()):
		tank[index].y -= BODY_Y
	_part(VehicleKit.profile(tank, 0.17, 0.05, 0.06), Vector3.ZERO, paint)
	var seat: PackedVector2Array = PackedVector2Array([Vector2(0.04, 0.92), Vector2(0.06, 1.0), Vector2(0.72, 1.02), Vector2(0.78, 0.95), Vector2(0.72, 0.9)])
	for index: int in range(seat.size()):
		seat[index].y -= BODY_Y
	_part(VehicleKit.profile(seat, 0.14, 0.04, 0.02), Vector3.ZERO, leather)
	var tail: PackedVector2Array = PackedVector2Array([Vector2(0.6, 0.86), Vector2(0.74, 0.94), Vector2(0.98, 0.97), Vector2(1.02, 0.9), Vector2(0.9, 0.84)])
	for index: int in range(tail.size()):
		tail[index].y -= BODY_Y
	_part(VehicleKit.profile(tail, 0.1, 0.03, 0.02), Vector3.ZERO, paint)
	_soft(Vector3(0.14, 0.06, 0.05), Vector3(0, 0.93 - BODY_Y, 1.02), _tail_material, 0.02)
	_soft(Vector3(0.16, 0.1, 0.02), Vector3(0, 0.78 - BODY_Y, 1.0), _mat(Color(0.88, 0.86, 0.72), 0.5), 0.01)
	_soft(Vector3(0.12, 0.04, 0.5), Vector3(0, 0.72 - BODY_Y, 0.9), dark, 0.02, Vector3(0.35, 0, 0))
	# Forks, bars, lamp, clocks, mirrors and fenders.
	for side: float in [-1.0, 1.0]:
		_strut_part(MeshKit.cylinder(0.028, 0.028, 1.0, 10), Vector3(side * 0.1, wheel - BODY_Y, axles.x), Vector3(side * 0.1, 1.06 - BODY_Y, -0.56), chrome)
		_strut_part(MeshKit.cylinder(0.04, 0.04, 1.0, 10), Vector3(side * 0.1, wheel - BODY_Y, axles.x), Vector3(side * 0.1, 0.62 - BODY_Y, -0.66), dark)
		_part(MeshKit.cylinder(0.012, 0.012, 0.3, 6), Vector3(side * 0.26, 1.28 - BODY_Y, -0.5), chrome).rotation.x = -0.2
		_soft(Vector3(0.1, 0.06, 0.03), Vector3(side * 0.27, 1.43 - BODY_Y, -0.52), dark, 0.02)
		_part(MeshKit.cylinder(0.024, 0.024, 0.12, 10), Vector3(side * 0.36, 1.12 - BODY_Y, -0.52), leather).rotation.z = PI * 0.5
	_part(MeshKit.cylinder(0.018, 0.018, 0.64, 10), Vector3(0, 1.12 - BODY_Y, -0.52), chrome).rotation.z = PI * 0.5
	var lamp: MeshInstance3D = _part(MeshKit.sphere(0.1, 0.2, 14, 7), Vector3(0, 0.98 - BODY_Y, -0.72), _head_material)
	lamp.scale = Vector3(1.0, 1.0, 0.55)
	var bucket: MeshInstance3D = _part(MeshKit.sphere(0.11, 0.22, 14, 7), Vector3(0, 0.98 - BODY_Y, -0.67), chrome)
	bucket.scale = Vector3(1.0, 1.0, 0.7)
	for side: float in [-1.0, 1.0]:
		var clock: MeshInstance3D = _part(MeshKit.cylinder(0.05, 0.05, 0.05, 12), Vector3(side * 0.06, 1.14 - BODY_Y, -0.6), dark)
		clock.rotation.x = -0.6
	_soft(Vector3(0.14, 0.03, 0.52), Vector3(0, wheel + 0.36 - BODY_Y, axles.x - 0.04), paint, 0.015, Vector3(0.1, 0, 0))
	_soft(Vector3(0.12, 0.03, 0.4), Vector3(0, wheel + 0.34 - BODY_Y, axles.y + 0.08), dark, 0.015, Vector3(-0.3, 0, 0))
	for side: float in [-1.0, 1.0]:
		_soft(Vector3(0.1, 0.03, 0.04), Vector3(side * 0.2, 0.42 - BODY_Y, 0.2), dark, 0.01)
		_soft(Vector3(0.1, 0.03, 0.04), Vector3(side * 0.18, 0.55 - BODY_Y, 0.58), dark, 0.01)
	if stripe_color.a > 0.0:
		_soft(Vector3(0.36, 0.035, 0.36), Vector3(0, 1.1 - BODY_Y, -0.24), _paint(stripe_color), 0.015)


## A part (built along +Y, one metre long) stretched between two body-space points.
func _strut_part(mesh: Mesh, from: Vector3, to: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var part: MeshInstance3D = _part(mesh, Vector3.ZERO, material)
	part.transform = VehicleKit.strut(from, to)
	part.scale = Vector3(1.0, from.distance_to(to), 1.0)
	return part


## One wheel family for the whole fleet: a rounded tyre, then a rim by type: steel with a
## hubcap (saloons), five-spoke alloy (coupe), chunky six-spoke (4x4s), cast three-spoke
## (bike). Front wheels steer; all of them spin.
func _build_wheels() -> void:
	var rubber: StandardMaterial3D = _mat(Color("141618"), 0.92)
	var silver: StandardMaterial3D = _mat(Color("a4abae"), 0.3, 0.75)
	var gunmetal: StandardMaterial3D = _mat(Color("4c5256"), 0.35, 0.6)
	var hub_dark: StandardMaterial3D = _mat(Color("1b1f22"), 0.7)
	var radius: float = float(spec["wheel_r"])
	var style: String = "bike" if is_bike() else str(_spec_body().get("rim", "cap"))
	var axles: Vector2 = spec["axles"]
	var sides: Array = [0.0] if is_bike() else [-1.0, 1.0]
	for axle_z: float in [axles.x, axles.y]:
		for side: float in sides:
			var wheel_pivot: Node3D = Node3D.new()
			wheel_pivot.position = Vector3(side * float(spec["track"]), radius, axle_z)
			add_child(wheel_pivot)
			if axle_z < 0.0:
				_front_wheels.append(wheel_pivot)
			var spinner: Node3D = Node3D.new()
			wheel_pivot.add_child(spinner)
			_spinners.append(spinner)
			var tube: float = 0.07 if is_bike() else radius * (0.5 if style == "offroad" else 0.4)
			var tyre: MeshInstance3D = _part(MeshKit.torus(radius - tube, radius, 22, 8), Vector3.ZERO, rubber, spinner)
			tyre.rotation.z = PI * 0.5
			tyre.scale = Vector3(1.0, 0.5 if is_bike() else (1.25 if style == "offroad" else 1.05), 1.0)
			var rim_r: float = radius - tube + 0.02
			var face: float = side * 0.06
			match style:
				"cap":
					var cap: MeshInstance3D = _part(MeshKit.cylinder(rim_r, rim_r * 0.92, 0.16, 18), Vector3.ZERO, silver, spinner)
					cap.rotation.z = PI * 0.5
					for slot: int in range(6):
						var angle: float = slot * TAU / 6.0
						_part(MeshKit.rounded_box(Vector3(0.02, 0.05, 0.08), 0.01, 1), Vector3(face + side * 0.03, sin(angle) * rim_r * 0.62, cos(angle) * rim_r * 0.62), hub_dark, spinner).rotation.x = -angle
					_part(MeshKit.cylinder(0.05, 0.05, 0.04, 10), Vector3(face + side * 0.04, 0, 0), silver, spinner).rotation.z = PI * 0.5
				"alloy", "offroad":
					var spokes: int = 5 if style == "alloy" else 6
					var dish: MeshInstance3D = _part(MeshKit.cylinder(rim_r, rim_r, 0.14, 18), Vector3.ZERO, hub_dark, spinner)
					dish.rotation.z = PI * 0.5
					var lip: MeshInstance3D = _part(MeshKit.torus(rim_r - 0.03, rim_r + 0.005, 18, 4), Vector3(face * 0.8, 0, 0), silver if style == "alloy" else gunmetal, spinner)
					lip.rotation.z = PI * 0.5
					for spoke: int in range(spokes):
						var bar: MeshInstance3D = _part(MeshKit.rounded_box(Vector3(0.05, rim_r * 0.95, 0.07 if style == "alloy" else 0.1), 0.02, 1), Vector3(face, 0, 0), silver if style == "alloy" else gunmetal, spinner)
						bar.rotation.x = spoke * TAU / spokes
						bar.position = Vector3(face, cos(spoke * TAU / spokes) * rim_r * 0.47, sin(spoke * TAU / spokes) * rim_r * 0.47)
					_part(MeshKit.cylinder(0.06, 0.06, 0.05, 10), Vector3(face + side * 0.02, 0, 0), silver, spinner).rotation.z = PI * 0.5
				_:
					var hub: MeshInstance3D = _part(MeshKit.cylinder(0.06, 0.06, 0.12, 12), Vector3.ZERO, gunmetal, spinner)
					hub.rotation.z = PI * 0.5
					var disc: MeshInstance3D = _part(MeshKit.cylinder(0.12, 0.12, 0.012, 16), Vector3(0.07, 0, 0), silver, spinner)
					disc.rotation.z = PI * 0.5
					for spoke: int in range(3):
						var bar: MeshInstance3D = _part(MeshKit.rounded_box(Vector3(0.03, radius - tube - 0.04, 0.045), 0.012, 1), Vector3.ZERO, gunmetal, spinner)
						bar.rotation.x = spoke * TAU / 3.0
						bar.position = Vector3(0, cos(spoke * TAU / 3.0) * (radius - tube) * 0.48, sin(spoke * TAU / 3.0) * (radius - tube) * 0.48)
			MeshMerge.merge_children(spinner)


func _paint(color: Color) -> StandardMaterial3D:
	var key: String = "paint" + str(color)
	if not _materials.has(key):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.28
		material.metallic = 0.25
		material.metallic_specular = 0.7
		material.clearcoat_enabled = true
		material.clearcoat = 0.5
		_materials[key] = material
	return _materials[key] as StandardMaterial3D


func _mat(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var key: String = str(color) + str(roughness) + str(metallic)
	if not _materials.has(key):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = roughness
		material.metallic = metallic
		_materials[key] = material
	return _materials[key] as StandardMaterial3D


func _glass_material() -> StandardMaterial3D:
	if not _materials.has("glass"):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		# Lightly tinted glass: you can see who is inside (and they can see out), with a
		# specular sheen so it still reads as glass rather than an open cage.
		material.albedo_color = Color(0.46, 0.55, 0.6, 0.2)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 0.05
		material.metallic = 0.15
		material.metallic_specular = 0.85
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials["glass"] = material
	return _materials["glass"] as StandardMaterial3D


func _part(mesh: Mesh, pos: Vector3, material: StandardMaterial3D, parent: Node3D = null) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.position = pos
	(parent if parent != null else _body).add_child(mesh_instance)
	return mesh_instance


func _soft(size: Vector3, pos: Vector3, material: StandardMaterial3D, radius: float, angles: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = _part(MeshKit.rounded_box(size, radius, 2), pos, material)
	mesh_instance.rotation = angles
	return mesh_instance
