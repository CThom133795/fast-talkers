extends SceneTree
## FastRemote (scripts/remote_player.gd): interpolation, extrapolation cap, snap, hit zones,
## collision layers, death/revive, crouch, seats, carry and weapon props, name tag.
## Run: godot --headless --path . --script res://tests/remote_player.gd

var checks: int = 0
var failures: int = 0
var remote: FastRemote
var clock: float = 10.0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _state(pos: Vector3, flags: int = 0, weapon: String = "pistol", yaw: float = 0.0, pitch: float = 0.0) -> Dictionary:
	return {"pos": pos, "yaw": yaw, "pitch": pitch, "flags": flags, "weapon": weapon, "car": -1, "seat": 0, "health": 100.0}


## Pushes two identical snapshots 50 ms apart and renders exactly at the newest one, so earlier
## phases of the test never leak motion into this one.
func _settle(pos: Vector3, flags: int = 0, weapon: String = "pistol", yaw: float = 0.0, pitch: float = 0.0) -> void:
	clock += 1.0
	remote.push_state(clock, _state(pos, flags, weapon, yaw, pitch))
	remote.push_state(clock + 0.05, _state(pos, flags, weapon, yaw, pitch))
	remote.now_override = clock + 0.05 + FastRemote.RENDER_DELAY
	remote._process(1.0 / 60.0)


func _ray(from: Vector3, to: Vector3, mask: int) -> Object:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, mask)
	var hit: Dictionary = root.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") as Object if not hit.is_empty() else null


func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("remote_player did not finish in 60 s")
		quit(2))
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	var floor_box: BoxShape3D = BoxShape3D.new()
	floor_box.size = Vector3(400, 1, 400)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)
	remote = FastRemote.new()
	remote.setup(7, "kingsway", "Vinny")
	root.add_child(remote)
	await process_frame
	await physics_frame
	remote.now_override = clock

	_check(remote.peer_id == 7 and remote.crew == "kingsway" and remote.display_name == "Vinny", "setup stores identity")
	_check(remote.model != null and remote.model.skeleton != null, "model built")
	_check(remote.name_tag != null and remote.name_tag.text == "Vinny", "name tag text")
	_check(remote.name_tag.visibility_range_end == 40.0, "name tag visible to 40 m")
	_check(remote.name_tag.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and not remote.name_tag.no_depth_test, "name tag: no shadow, depth tested")
	_check(remote.name_tag.modulate.is_equal_approx(FastRemote.Factions.color("kingsway")), "name tag in crew colour")
	_check(remote.collision_layer == 4 and remote.collision_mask == 0, "standing collision layer 3 (value 4), mask 0")

	# Setup after add_child is also fine.
	var late: FastRemote = FastRemote.new()
	root.add_child(late)
	late.setup(9, "morris", "Late")
	_check(late.model != null and late.name_tag != null, "setup after add_child builds")
	late.queue_free()
	var early: FastRemote = FastRemote.new()
	early.setup(10, "solnegro", "Early")
	_check(early.model == null, "setup before tree defers the build")
	root.add_child(early)
	_check(early.model != null and early.collision_layer == 4, "deferred build runs in _ready")
	early.queue_free()

	# --- Interpolation -------------------------------------------------------------------
	remote.push_state(1.0, _state(Vector3(0, 0, 0), 0, "pistol", 0.0))
	remote.push_state(1.1, _state(Vector3(2, 0, 0), 0, "pistol", 1.0))
	remote.now_override = 1.15
	remote._process(1.0 / 60.0)
	_check(absf(remote.global_position.x - 1.0) < 0.001, "interpolation midpoint at render time now-0.1 (x=%.3f)" % remote.global_position.x)
	_check(absf(remote.rotation.y - 0.5) < 0.001, "yaw lerps to midpoint (%.3f)" % remote.rotation.y)
	_check(remote._anim_velocity.length() > 15.0, "velocity estimated from the bracketing snapshots")
	remote.now_override = 1.175
	remote._process(1.0 / 60.0)
	_check(absf(remote.global_position.x - 1.5) < 0.001, "interpolation quarter step (x=%.3f)" % remote.global_position.x)
	remote.now_override = 1.05
	remote._process(1.0 / 60.0)
	_check(remote.global_position.x == 0.0, "before the oldest snapshot holds the first")

	# --- Extrapolation cap ---------------------------------------------------------------
	remote.now_override = 1.25
	remote._process(1.0 / 60.0)
	_check(absf(remote.global_position.x - 3.0) < 0.001, "extrapolates 50 ms at 20 m/s (x=%.3f)" % remote.global_position.x)
	remote.now_override = 1.5
	remote._process(1.0 / 60.0)
	_check(absf(remote.global_position.x - 5.0) < 0.001, "extrapolation capped at 150 ms (x=%.3f)" % remote.global_position.x)
	_check(remote.velocity.length() < 0.01, "held pose is not animated as running")
	remote.now_override = 3.0
	remote._process(1.0 / 60.0)
	_check(absf(remote.global_position.x - 5.0) < 0.001, "long silence holds position")

	# --- Snap on teleport ----------------------------------------------------------------
	remote.push_state(3.1, _state(Vector3(50, 0, 0)))
	_check(remote.global_position.is_equal_approx(Vector3(50, 0, 0)), "teleport over 8 m snaps immediately")
	_check(remote.buffered() == 1, "teleport clears stale snapshots")
	remote.push_state(3.0, _state(Vector3(-9, 0, 0)))
	_check(remote.buffered() == 1, "out-of-order snapshot dropped")

	# --- Buffer bound --------------------------------------------------------------------
	for index: int in range(60):
		remote.push_state(4.0 + index * 0.05, _state(Vector3(50.0 + index * 0.1, 0, 0)))
	_check(remote.buffered() <= 32, "buffer bounded (%d)" % remote.buffered())

	clock = 10.0

	# --- Hit zones and layers (standing) -------------------------------------------------
	_settle(Vector3(50, 0, 0))
	_check(remote.hit_zone(Vector3(50, 1.6, 0)) == "head", "standing: 1.6 m is head")
	_check(remote.hit_zone(Vector3(50, 1.4, 0)) == "body", "standing: 1.4 m is body")
	_check(remote.hit_zone(Vector3(50, 1.51, 0)) == "head" and remote.hit_zone(Vector3(50, 1.49, 0)) == "body", "standing head threshold 1.5 m")
	_check(remote.collision_layer == 4, "standing collision layer 3")
	await physics_frame
	_check(_ray(Vector3(50, 1.0, 5), Vector3(50, 1.0, -5), 4) == remote, "standing: ray on layer 3 hits")
	_check(_ray(Vector3(50, 1.0, 5), Vector3(50, 1.0, -5), 8) == null, "standing: ray on layer 4 misses")
	_check(is_equal_approx(remote.capsule.height, 1.8) and is_equal_approx(remote.capsule.radius, 0.34), "capsule 0.34 x 1.8")

	# --- Crouch --------------------------------------------------------------------------
	_settle(Vector3(50, 0, 0), FastRemote.FLAG_CROUCH)
	_check(remote.capsule.height < 1.8, "crouch shortens the capsule (%.2f)" % remote.capsule.height)
	_check(remote.is_crouching(), "crouching reported")
	for index: int in range(30):
		remote._process(1.0 / 60.0)
	_check(remote.model.position.y < -0.2, "crouch lowers the model (%.2f)" % remote.model.position.y)
	_settle(Vector3(50, 0, 0), 0)
	for index: int in range(30):
		remote._process(1.0 / 60.0)
	_check(is_equal_approx(remote.capsule.height, 1.8) and absf(remote.model.position.y) < 0.001, "standing again restores capsule and model")

	# --- Weapon props --------------------------------------------------------------------
	_settle(Vector3(50, 0, 0), 0, "pistol")
	_check(not remote.sidearm_prop.visible and not remote.longgun_prop.visible, "holstered: no weapon prop when not aiming")
	_settle(Vector3(50, 0, 0), FastRemote.FLAG_AIMING, "pistol")
	_check(remote.sidearm_prop.visible and not remote.longgun_prop.visible, "aiming a sidearm shows the sidearm")
	_settle(Vector3(50, 0, 0), FastRemote.FLAG_AIMING, "rifle")
	_check(remote.longgun_prop.visible and not remote.sidearm_prop.visible, "aiming a long gun shows the long gun")
	_settle(Vector3(50, 0, 0), FastRemote.FLAG_FIRING, "shotgun")
	_check(remote.longgun_prop.visible and not remote.sidearm_prop.visible, "firing a shotgun shows the long gun")
	_settle(Vector3(50, 0, 0), 0, "rifle")
	_check(not remote.longgun_prop.visible and not remote.sidearm_prop.visible, "long gun holstered when not aiming")

	# --- Carry props ---------------------------------------------------------------------
	_settle(Vector3(50, 0, 0), 0)
	_check(not remote.ledger_prop.visible and not remote.cash_prop.visible, "no carry props by default")
	_settle(Vector3(50, 0, 0), FastRemote.FLAG_LEDGER)
	_check(remote.ledger_prop.visible and not remote.cash_prop.visible, "Ledger flag shows the leather case")
	_settle(Vector3(50, 0, 0), FastRemote.FLAG_CASH)
	_check(remote.cash_prop.visible and not remote.ledger_prop.visible, "cash flag shows the aluminium case")
	_settle(Vector3(50, 0, 0), FastRemote.FLAG_CASH | FastRemote.FLAG_LEDGER)
	_check(remote.cash_prop.visible and remote.ledger_prop.visible, "both flags show both cases")
	_check(absf(remote.ledger_prop.position.z - remote.cash_prop.position.z) >= 0.5, "both carry props sit apart when both are held")
	_settle(Vector3(50, 0, 0), 0)
	_check(not remote.ledger_prop.visible and not remote.cash_prop.visible, "carry props hide again")
	# The crew phone rides on the belt, banded in the owning crew's colour (online.gd calls set_phone).
	_check(not remote.phone_prop.visible, "no phone on the belt by default")
	remote.set_phone(true, Color(0.8, 0.2, 0.2))
	_check(remote.phone_prop.visible, "set_phone(true) shows the phone on the belt")
	remote.set_phone(false)
	_check(not remote.phone_prop.visible, "set_phone(false) hides it again")
	# --- Hands-up gesture (state flag 128) ----------------------------------------------------
	_settle(Vector3(50, 0, 0), FastRemote.FLAG_HANDS_UP | FastRemote.FLAG_AIMING)
	_check(remote.model.get("hands_up") == true, "hands-up flag raises the remote's hands")
	_settle(Vector3(50, 0, 0), FastRemote.FLAG_HANDS_UP | FastRemote.FLAG_DEAD)
	_check(remote.model.get("hands_up") != true, "a dead remote never shows hands up")
	_settle(Vector3(50, 0, 0), 0)
	_check(remote.model.get("hands_up") != true, "hands come down when the flag clears")
	_check(remote.ledger_prop.position.x <= -0.1 and remote.cash_prop.position.x <= -0.1, "carry props hang outward of the leg")
	var case_box: AABB = (remote.ledger_prop.get_child(0) as MeshInstance3D).mesh.get_aabb()
	_check(case_box.size.z >= 0.45 and case_box.size.y >= 0.33, "carry props are large enough to read at range (%s)" % str(case_box.size))

	# --- take_damage / health ------------------------------------------------------------
	var struck_log: Array = []
	remote.struck.connect(func(amount: float, source: Vector3) -> void: struck_log.append([amount, source]))
	remote.apply_remote_health(80.0)
	remote.take_damage(25.0, Vector3(1, 2, 3))
	_check(struck_log.size() == 1 and is_equal_approx(float(struck_log[0][0]), 25.0) and struck_log[0][1] == Vector3(1, 2, 3), "take_damage emits struck")
	_check(is_equal_approx(remote.health, 80.0), "take_damage leaves health alone; apply_remote_health sets it")
	remote.flash_hit()
	remote._process(1.0 / 60.0)
	_check(remote._flash > 0.0, "flash_hit starts a tint")

	# --- Seated --------------------------------------------------------------------------
	var car: StaticBody3D = StaticBody3D.new()
	root.add_child(car)
	car.global_position = Vector3(20, 0, 0)
	car.rotation.y = 0.6
	var eye: Vector3 = Vector3(-0.4, 1.2, 0.1)
	remote.seat_in(car, eye, false)
	_settle(Vector3(50, 0, 0), 0, "pistol", 1.0)
	var expected: Vector3 = car.global_transform * (eye - Vector3(0, remote.model.eye_height(), 0))
	_check(remote.is_seated() and remote.model.seated and not remote.model.riding, "seat_in sets seated, not riding")
	_check(remote.global_position.is_equal_approx(expected), "seated body follows the car, ignoring buffered pos")
	_check(remote.collision_layer == 8, "seated collision layer 4 (value 8)")
	_check(is_equal_approx(remote.capsule.height, 1.1), "seated capsule 1.1 m")
	var base_y: float = remote.global_position.y
	_check(remote.hit_zone(Vector3(20, base_y + 1.05, 0)) == "head", "seated: 1.05 m is head")
	_check(remote.hit_zone(Vector3(20, base_y + 0.95, 0)) == "body", "seated: 0.95 m is body")
	await physics_frame
	var seat_center: Vector3 = remote.global_position + Vector3(0, 0.85, 0)
	_check(_ray(seat_center + Vector3(0, 0, 5), seat_center - Vector3(0, 0, 5), 8) == remote, "seated: ray on layer 4 hits")
	_check(_ray(seat_center + Vector3(0, 0, 5), seat_center - Vector3(0, 0, 5), 4) == null, "seated: layer 3 rays miss")
	car.global_position = Vector3(30, 0, 0)
	remote._process(1.0 / 60.0)
	_check(is_equal_approx(remote.global_position.x, (car.global_transform * (eye - Vector3(0, remote.model.eye_height(), 0))).x), "seated body tracks a moving car")
	remote.seat_out()
	_settle(Vector3(50, 0, 0))
	_check(not remote.is_seated() and not remote.model.seated and remote.collision_layer == 4, "seat_out returns to layer 3")
	_check(remote.global_position.is_equal_approx(Vector3(50, 0, 0)), "seat_out resumes the buffered position")
	remote.seat_in(car, eye, true)
	_check(remote.model.riding, "bike seat sets riding")
	remote.seat_out()
	_settle(Vector3(50, 0, 0))

	# --- Dead and revive -----------------------------------------------------------------
	_settle(Vector3(50, 0, 0), FastRemote.FLAG_DEAD)
	_check(remote.is_dead(), "dead flag marks dead")
	_check(remote.collision_layer == 0, "dead: collision off")
	_check(not remote.name_tag.visible, "dead: name tag hidden")
	await create_timer(1.0).timeout
	_check(remote.model.rotation.x > 1.2, "dead: fall tween laid the body down (%.2f)" % remote.model.rotation.x)
	await physics_frame
	_check(_ray(Vector3(50, 0.5, 5), Vector3(50, 0.5, -5), 4 | 8) == null, "dead: rays pass through")
	_settle(Vector3(50, 0, 0), 0)
	_check(not remote.is_dead() and remote.collision_layer == 4, "revive restores collision")
	_check(remote.name_tag.visible, "revive shows the name tag")
	_check(is_zero_approx(remote.model.rotation.x) and is_zero_approx(remote.model.position.y), "revive resets the pose")
	_check(is_equal_approx(remote.capsule.height, 1.8), "revive restores the capsule")

	print("REMOTE PLAYER RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
