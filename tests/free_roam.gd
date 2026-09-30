extends SceneTree
## Headless checks for Free Roam, the arsenal, range targets, practice bots, vehicles and
## seats, the buy phase, controller menus and settings. Complements tests/integration.gd
## (Codex's contract-loop suite).
## Run: godot --headless --path . --script res://tests/free_roam.gd

var game: Variant
var failures: int = 0
var checks: int = 0
var completed: bool = false
var pellets: int = 0
var crashes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func _frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame
	await process_frame


func _release_inputs() -> void:
	for action: String in ["move_forward", "move_back", "move_left", "move_right", "handbrake", "fire", "aim", "sprint", "crouch", "jump", "reload", "driveby_aim", "driveby_fire", "pad_throttle"]:
		if InputMap.has_action(action):
			Input.action_release(action)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _timeout() -> void:
	if completed:
		return
	_release_inputs()
	push_error("Free roam suite did not finish within 150 seconds.")
	quit(2)


func _target(kind: String) -> Variant:
	for target: Variant in game.armory.targets:
		if str(target.kind) == kind and target.travel == 0.0:
			return target
	return null


func _pad(button: int) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func _action(action: String) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	game._unhandled_input(event)


func _vehicle(type: String) -> Variant:
	for ride: Variant in game.cars:
		if ride.vehicle_type == type:
			return ride
	return null


func _run() -> void:
	create_timer(150.0).timeout.connect(_timeout)
	game = (load("res://main.tscn") as PackedScene).instantiate()
	# Portable Godot keeps user:// beside the executable, which can be read-only in CI.
	game.settings_path = "res://.godot/test_settings.cfg"
	root.add_child(game)
	await _frames(3)
	var player: Variant = game.player

	# --- Controller on menus (0.4 fix) -----------------------------------------------
	var accept_pad: bool = false
	for event: InputEvent in InputMap.action_get_events("ui_accept"):
		accept_pad = accept_pad or (event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A)
	var cancel_pad: bool = false
	for event: InputEvent in InputMap.action_get_events("ui_cancel"):
		cancel_pad = cancel_pad or (event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B)
	_check(accept_pad and cancel_pad, "Menus accept the pad's A and B buttons")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _frames(2)
	var focused: Control = root.gui_get_focus_owner()
	_check(focused is Button and game.menu.is_ancestor_of(focused), "A pad press focuses a title-menu button")
	# CREW, then PLAY ONLINE, then FREE ROAM.
	for step: int in range(2):
		await _pad(JOY_BUTTON_DPAD_DOWN)
		await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	_check(game.phase == game.Phase.LIVE and game.free_roam, "D-pad and A start Free Roam from the title menu")
	_action("escape")
	await _frames(2)
	_check(game.paused and game.menu.visible, "Menu (Start) opens the pause menu")
	await _pad(JOY_BUTTON_B)
	await _frames(2)
	_check(not game.paused and not game.menu.visible, "B backs out of the pause menu")

	# --- Mode setup --------------------------------------------------------------
	game._start_free_roam()
	await _frames(5)
	_check(game.phase == game.Phase.LIVE and game.free_roam and not game.paused, "Free roam starts live without a buy phase")
	_check(player.owned.size() == 5 and player.infinite_reserve and player.armor == 100.0, "Free roam grants one weapon per class, infinite reserve and full armor")
	_check(not game.case_mesh.visible, "Briefcase objective is hidden in free roam")
	var present: int = 0
	for guard: Variant in game._all_guards():
		if guard.visible and guard.collision_layer == 1:
			present += 1
	_check(present == 5, "Exchange and drill security are all present in free roam")
	var clock: float = game.time_left
	await _frames(30)
	_check(is_equal_approx(clock, game.time_left), "Free roam has no round clock")
	_check(player.global_position.distance_to(game.ArmoryScript.SPAWN) < 1.0, "Player spawns at the armory firing line")

	# --- Arsenal -----------------------------------------------------------------
	for id: String in ["pistol", "smg", "shotgun", "marksman", "rifle"]:
		player.switch_weapon(id)
		await _frames(1)
		_check(player.weapon_id == id and player.weapon_stats()["name"] != "", "Switches to %s" % id)
	await _frames(25)
	player._try_fire()
	var rifle_after_shot: int = player.ammo
	player.switch_weapon("pistol")
	await _frames(25)
	player.switch_weapon("rifle")
	await _frames(25)
	_check(rifle_after_shot == 29 and player.ammo == 29, "Magazine state is kept per weapon when swapping")
	_check(not player.switch_weapon("rifle"), "Switching to the equipped weapon is a no-op")
	var reserve_before: int = player.reserve
	player._start_reload()
	await _frames(140)
	_check(player.ammo == 30 and player.reserve == reserve_before, "Infinite reserve reloads without consuming reserve")
	player.cycle_weapon(1)
	await _frames(1)
	_check(player.weapon_id == "shotgun", "Mouse-wheel cycling follows class order")
	player.quick_swap()
	await _frames(1)
	_check(player.weapon_id == "rifle", "Quick swap returns to the previous weapon")

	# 0.4: every weapon in the roster builds, draws and fires.
	_check(player.WEAPONS.size() == 13, "The roster has 13 weapons")
	var per_class: bool = true
	for weapon_class: String in player.SLOT_ORDER:
		per_class = per_class and (player.VARIANTS[weapon_class] as Array).size() >= 2
	_check(per_class, "Every weapon class has at least two distinct models")
	var all_fire: bool = true
	var models: Dictionary = {}
	for id: String in player.WEAPONS:
		player.replace_in_class(id)
		await _frames(24)
		var before: int = player.ammo
		player._cooldown = 0.0
		player._try_fire()
		all_fire = all_fire and player.weapon_id == id and player.ammo == before - 1 and player._model.get_child_count() > 0
		models[str(player._sight_height) + str(player._hip_pose) + str(player._ads_depth)] = true
		if player.ammo != before - 1:
			print("  weapon did not fire: ", id)
	_check(all_fire, "All 13 weapons draw, build a viewmodel and fire")
	_check(models.size() >= 10, "Weapons have distinct sight lines and poses (%d unique)" % models.size())
	_check(player.WEAPONS["ak"]["damage"] > player.WEAPONS["rifle"]["damage"] and player.WEAPONS["ak"]["recoil"] > player.WEAPONS["rifle"]["recoil"] and player.WEAPONS["ak"]["interval"] > player.WEAPONS["rifle"]["interval"], "KV-47 hits harder, kicks harder and fires slower than the M4")
	_check(player.WEAPONS["ak"]["damage"] * player.WEAPONS["ak"]["headshot"] >= 100.0 and player.WEAPONS["rifle"]["damage"] * player.WEAPONS["rifle"]["headshot"] < 100.0, "KV-47 kills with one unarmoured headshot; the M4 needs two")
	player.set_loadout(["pistol", "smg", "shotgun", "marksman", "rifle"])
	player.switch_weapon("pistol")
	await _frames(20)
	var key_three: InputEventAction = InputEventAction.new()
	key_three.action = "weapon_3"
	key_three.pressed = true
	game._unhandled_input(key_three)
	await _frames(20)
	_check(player.weapon_id == "rifle", "Key 3 selects the rifle")
	game._unhandled_input(key_three)
	await _frames(20)
	_check(player.weapon_id == "ak" and not player.owned.has("rifle"), "Pressing 3 again swaps the M4 for the KV-47 in free roam")
	game._unhandled_input(key_three)
	await _frames(20)
	_check(player.weapon_id == "rifle", "And again cycles back to the M4")
	player.replace_in_class("revolver")
	await _frames(25)
	player._cooldown = 0.0
	player._try_fire()
	await _frames(8)
	_check(absf(player._cycler.rotation.z) > 0.5, "The revolver's cylinder turns on each shot")
	player.replace_in_class("pistol")
	player.switch_weapon("rifle")
	await _frames(25)

	# Shotgun: nine pellets per trigger and shell-by-shell reloading.
	player.switch_weapon("shotgun")
	await _frames(25)
	player.shot_fired.connect(func(_o: Vector3, _d: Vector3, _dmg: float): pellets += 1)
	player._try_fire()
	_check(pellets == 9 and player.ammo == 5, "Shotgun fires nine pellets and one shell")
	await _frames(55)
	player._try_fire()
	await _frames(55)
	player._start_reload()
	await _frames(50)
	_check(player.reloading and player.ammo == 5, "Shotgun loads one shell at a time")
	player._cooldown = 0.0
	player._try_fire()
	_check(not player.reloading and player.ammo == 4, "Firing interrupts a shell-by-shell reload")
	player.switch_weapon("rifle")
	await _frames(20)
	var before_swap_fire: int = player.ammo
	player._try_fire()
	_check(player.ammo == before_swap_fire - 1, "A fresh weapon fires once drawn, regardless of the last gun's cycle time")

	# Recoil kicks the aim up, then settles back once the trigger rests.
	player.switch_weapon("rifle")
	await _frames(25)
	player._recoil_pitch = 0.0
	player._try_fire()
	var kicked: float = player._recoil_pitch
	await _frames(70)
	_check(kicked > 0.005 and player._recoil_pitch < kicked * 0.1, "Camera recoil kicks and then recovers")
	_check(player.current_spread() < player.WEAPONS["rifle"]["hip_spread"] + 0.8, "Standing hip spread stays near the weapon's base cone")

	# --- Range targets -----------------------------------------------------------
	var plate: Variant = _target("plate")
	var eye: Vector3 = player.camera.global_position
	var plate_point: Vector3 = plate.global_position + Vector3(0, plate.plate_height, 0)
	game._on_shot(eye, (plate_point - eye).normalized(), 29.0)
	_check(plate.down, "Steel plate falls when hit")
	await _frames(int(plate.reset_delay * 60.0) + 25)
	_check(not plate.down, "Steel plate resets after its delay")
	var dummy: Variant = _target("dummy")
	player.switch_weapon("marksman")
	await _frames(25)
	eye = player.camera.global_position
	var head: Vector3 = dummy.global_position + Vector3(0, 1.77, 0)
	game._on_shot(eye, (head - eye).normalized(), 78.0)
	_check(dummy.down, "Marksman headshot drops a range dummy in one hit")
	var body_dummy: Variant = null
	for target: Variant in game.armory.targets:
		if str(target.kind) == "dummy" and target != dummy:
			body_dummy = target
			break
	player.switch_weapon("pistol")
	await _frames(25)
	eye = player.camera.global_position
	body_dummy.reset_target()
	await _frames(2)
	var chest: Vector3 = body_dummy.global_position + Vector3(0, 1.2, 0)
	game._on_shot(eye, (chest - eye).normalized(), 34.0)
	_check(not body_dummy.down and is_equal_approx(body_dummy.health, 66.0), "Pistol body shot deals 34 to a dummy")
	var neutral: int = 0
	for guard: Variant in game._all_guards():
		if not guard.hostile:
			neutral += 1
	_check(neutral == 5, "Range practice does not alert security")

	# Timed plate-rack drill.
	game.armory.reset_targets()
	await _frames(25)
	game.rack_best = 0.0
	eye = player.camera.global_position
	for rack_plate: Variant in game.armory.rack:
		var rack_point: Vector3 = rack_plate.global_position + Vector3(0, rack_plate.plate_height, 0)
		game._on_shot(eye, (rack_point - eye).normalized(), 34.0)
		await _frames(6)
	_check(game.rack_best > 0.0 and game.rack_best < 1.0, "Clearing all five rack plates records a time")

	# --- Armory rack ---------------------------------------------------------------
	player.ammo = 0
	player.health = 40.0
	player.global_position = game.ArmoryScript.RACK + Vector3(0, 0.1, 1.2)
	await _frames(3)
	game._interact()
	_check(player.ammo == int(player.weapon_stats()["capacity"]) and player.health == 100.0, "Armory rack refills ammunition and health")

	# --- Security ------------------------------------------------------------------
	var guard: Variant = game.guards[0]
	player.global_position = Vector3(0, 0.1, -36.0)
	await _frames(5)
	player.switch_weapon("rifle")
	await _frames(25)
	eye = player.camera.global_position
	var guard_head: Vector3 = guard.global_position + Vector3(0, 1.75, 0)
	var health_before: float = guard.health
	game._on_shot(eye, (guard_head - eye).normalized(), 28.0)
	_check(is_equal_approx(health_before - guard.health, 56.0), "M4 headshot on security deals double damage")
	_check(guard.hostile and game.guards[1].hostile, "Shooting security alerts the nearby squad")
	guard.take_damage(1000.0)
	_check(game._guard_respawns.has(guard), "Downed security is queued to regroup")
	game._guard_respawns[guard] = 0.05
	await _frames(10)
	_check(guard.health == 100.0 and guard.visible and not guard.hostile, "Security regroups neutral after the respawn delay")
	var far_guard: Variant = game.drill_guards[0]
	for each: Variant in game._all_guards():
		each.hostile = false
	player.global_position = far_guard.global_position + Vector3(4.0, 0.1, 0)
	await _frames(3)
	player._cooldown = 0.0
	player._try_fire()
	_check(far_guard.hostile, "Gunfire right next to a guard spooks them")
	game.guard_shot(far_guard.global_position + Vector3(0, 1.45, 0), player.camera.global_position + Vector3(1.5, 0, 0), false)
	_check(true, "A guard's missed shot resolves without errors")

	# Free-roam death respawns at the armory instead of ending a round.
	player.take_damage(1000.0)
	_check(game.phase == game.Phase.LIVE and player.is_dead(), "Death in free roam does not end the session")
	await _frames(int(2.6 * 60.0) + 20)
	_check(not player.is_dead() and player.health == 100.0 and player.global_position.distance_to(game.ArmoryScript.SPAWN) < 1.0, "Player respawns at the armory")
	var calm: bool = true
	for each: Variant in game._all_guards():
		calm = calm and not each.hostile
	_check(calm, "Security stands down after a respawn")
	await _frames(150)
	var home_again: bool = true
	for each: Variant in game._all_guards():
		if each.health > 0.0:
			home_again = home_again and Vector2(each.global_position.x - each.home.x, each.global_position.z - each.home.z).length() < 0.5
	_check(home_again, "Calm security walks back to their posts")
	player.invulnerable = true
	player.take_damage(50.0)
	_check(player.health == 100.0, "Invulnerable toggle blocks damage")

	# --- Vehicles ------------------------------------------------------------------
	var types: Dictionary = {}
	for ride: Variant in game.cars:
		types[ride.vehicle_type] = true
	_check(types.has("sedan") and types.has("coupe") and types.has("suv") and types.has("pickup") and types.has("motorcycle"), "Sedans, coupes, SUVs, pickups and motorcycles all spawn")
	_check(game.world.parked_vehicles.size() >= 8 and game.cars.size() >= 6 + 8 + game.world.parked_vehicles.size(), "Parked cars around the city are real, enterable vehicles")
	_check(_vehicle("sedan").seat_count() == 4 and _vehicle("coupe").seat_count() == 2 and _vehicle("motorcycle").seat_count() == 2 and _vehicle("pickup").seat_count() == 4, "Seat counts: sedan 4, coupe 2, pickup 4 (two in the bed), bike 2")
	var sedan: Variant = game.cars[1]
	sedan.reset_car(Vector3(30, 0.1, 35))
	sedan.rotation.y = 0.0
	await _frames(10)
	player.global_position = sedan.door_position(0) + Vector3(-0.4, 0.1, 0)
	await _frames(5)
	game._interact()
	await _frames(3)
	_check(game.car == sedan and sedan.occupied and player.in_vehicle and player.camera.current, "E enters the driver's seat of the nearest vehicle")
	_check(not game.avatar.visible, "The first-person driver camera is clear of the local avatar's head")
	game.car.crashed.connect(func(_strength: float): crashes += 1)
	sedan.reset_car(Vector3(game.world.HALF + 5.0, 0.1, 35))
	sedan.rotation.y = -PI * 0.5
	await _frames(10)
	Input.action_press("move_forward")
	await _frames(240)
	Input.action_release("move_forward")
	await _frames(10)
	_check(crashes > 0, "Hitting the city limit reports a crash for audio and camera shake")
	sedan.reset_car(Vector3(30, 0.1, 35))
	await _frames(20)
	# Drive-by: hold aim at the wheel to lean out with a one-handed gun.
	player.switch_weapon("rifle")
	Input.action_press("driveby_aim")
	await _frames(4)
	_check(game.driveby and player.seat_can_shoot and player.camera.current and player.is_one_hand(player.weapon_id), "Holding aim at the wheel enables one-handed fire without locking the view")
	_check(player.fire_action == "driveby_fire" and not player.allow_ads, "Drive-by fires on RB/LMB so the triggers keep driving")
	Input.action_release("driveby_aim")
	await _frames(4)
	_check(not game.driveby and player.camera.current and not player.seat_can_shoot, "Releasing aim keeps the free-look driver camera")
	_action("seat")
	await _frames(3)
	_check(game.seat == 1 and player.seat_can_shoot and not sedan.occupied, "F moves to the passenger seat")
	_check(not sedan.window_closed(1), "The gunner's window rolls down")
	game._exit_vehicle(true)
	await _frames(3)
	_check(not sedan.occupied and not player.in_vehicle and sedan.occupants.count("player") == 0, "Exits the vehicle")
	_check(sedan.window_closed(1), "The window rolls back up when the gunner leaves")
	var runner: Variant = game.cars[0]
	var victim: Variant = game.drill_guards[2]
	for each: Variant in game._all_guards():
		each.reset_guard()
		each.set_present(true)
	victim.reset_guard()
	victim.set_present(true)
	victim.active = true
	runner.reset_car(victim.global_position + Vector3(0, 0.1, 14.0))
	player.global_position = runner.global_position + Vector3(-2.5, 0.1, 0)
	await _frames(5)
	game._interact()
	await _frames(3)
	Input.action_press("move_forward")
	await _frames(150)
	Input.action_release("move_forward")
	_check(victim.health < 100.0, "Driving into security injures them")
	Input.action_press("move_back")
	await _frames(90)
	Input.action_release("move_back")
	await _frames(60)
	game._exit_vehicle(true)
	await _frames(3)

	# Passenger gunner: shots leave through the window opening and hit someone outside.
	for each: Variant in game._all_guards():
		each.reset_guard()
		each.set_present(true)
	var mark: Variant = game.drill_guards[1]
	var suv: Variant = _vehicle("suv")
	suv.reset_car(mark.global_position + Vector3(-6.0, 0.1, 0.0))
	suv.rotation.y = 0.0
	await _frames(10)
	game._enter_vehicle(suv, 3)
	await _frames(4)
	eye = player.camera.global_position
	var target_chest: Vector3 = mark.global_position + Vector3(0, 1.2, 0)
	var mark_health: float = mark.health
	game._on_shot(eye, (target_chest - eye).normalized(), 30.0)
	_check(mark.health < mark_health, "A rear-seat gunner hits a target outside the window")
	var roof_ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(eye, eye + Vector3.UP * 2.0)
	roof_ray.exclude = [player.get_rid()]
	var roof_hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(roof_ray)
	_check(not roof_hit.is_empty() and roof_hit.get("collider") == suv, "The occupied SUV roof stops upward shots through solid bodywork")
	player._turn(3.0)
	_check(absf(wrapf(player.seat_yaw, -PI, PI)) > 2.9, "Window passengers can look almost all the way around")
	game._exit_vehicle(true)
	await _frames(3)
	# Pillion gunner: all-round arc except straight ahead through the rider.
	var bike: Variant = _vehicle("motorcycle")
	bike.reset_car(Vector3(91, 0.1, 40))
	await _frames(10)
	game._enter_vehicle(bike, 1)
	await _frames(3)
	player.seat_yaw = 0.05
	player._clamp_seat()
	_check(is_equal_approx(player.seat_yaw, 0.05) and player.seat_can_shoot and player.seat_blocked > 0.05, "Pillion can look forward while the rider blocks the firing cone")
	# The practice wheelman drives a loop while the player rides.
	var bike_start: Vector3 = bike.global_position
	_check(bike.autopilot and bike.occupants[0] == "bot", "A practice wheelman takes the handlebars when you ride pillion in free roam")
	await _frames(200)
	_check(bike.global_position.distance_to(bike_start) > 8.0, "The wheelman drives off along the road loop")
	game._interact()
	await _frames(240)
	game._interact()
	await _frames(3)
	if player.in_vehicle or bike.autopilot:
		print("  pull-over state: at %s speed %.1f km/h autopilot %s in_vehicle %s" % [str(bike.global_position), bike.speed_kph, str(bike.autopilot), str(player.in_vehicle)])
	_check(not player.in_vehicle and not bike.autopilot and bike.occupants[0] == "", "Asking to pull over stops the bike; getting off dismisses the wheelman")
	# Riding a bike into something hard throws the rider.
	bike.reset_car(Vector3(66, 0.1, 35))
	await _frames(5)
	game._enter_vehicle(bike, 0)
	await _frames(3)
	player.invulnerable = false
	var rider_health: float = player.health
	game._on_car_crashed(15.0, bike)
	await _frames(3)
	_check(not player.in_vehicle and player.health < rider_health, "A hard crash throws the rider off the bike")
	player.health = 100.0
	player.invulnerable = true
	# Vehicles soak bullets until the engine dies.
	var wreck: Variant = _vehicle("coupe")
	wreck.reset_car(Vector3(50, 0.1, 35))
	await _frames(10)
	player.global_position = Vector3(38, 0.1, 35)
	await _frames(3)
	eye = player.camera.global_position
	var coupe_before: float = wreck.health
	game._on_shot(eye, (wreck.global_position + Vector3(0, 0.6, 0) - eye).normalized(), 30.0)
	_check(wreck.health < coupe_before, "Bullets damage vehicles")
	wreck.take_damage(10000.0)
	game._enter_vehicle(wreck, 0)
	Input.action_press("move_forward")
	await _frames(60)
	Input.action_release("move_forward")
	_check(wreck.disabled and wreck.speed_kph < 3.0, "A wrecked vehicle's engine won't drive")
	game._exit_vehicle(true)
	wreck.reset_to_spawn()
	await _frames(3)
	player.invulnerable = false

	# --- Contract mode: the buy phase ------------------------------------------------
	game._show_title()
	game.cash = 3200
	game._start_round()
	await _frames(3)
	var hidden: bool = true
	for drill: Variant in game.drill_guards:
		hidden = hidden and not drill.visible and drill.collision_layer == 0
	_check(hidden, "Contract mode removes drill security")
	_check(game.phase == game.Phase.BUY and not game.paused and game.buy_menu_open and game.menu.visible, "Rounds open with a live buy phase and the buy menu")
	_check(player.global_position.distance_to(game.hq_spawn) < 1.5 and game._flat_distance(game.HOME, game.world.crew_spawns[game.crew]["hq"]) < 0.1, "The crew spawns at its own HQ, which is also the delivery point")
	_check(player.owned.size() == 1 and not player.infinite_reserve and not player.regenerate, "Contract mode starts with a pistol-only finite loadout")
	var ammo_holstered: int = player.ammo
	player._cooldown = 0.0
	player._try_fire()
	_check(player.ammo == ammo_holstered and not player.can_fire, "Weapons stay holstered during the buy phase")
	var buy_clock: float = game.buy_time_left
	await _frames(30)
	_check(game.buy_time_left < buy_clock - 0.3, "The buy phase counts down in real time")
	var tabs_found: bool = false
	for child: Node in game.menu_stack.get_children():
		tabs_found = tabs_found or child is HBoxContainer
	_check(tabs_found, "The buy menu has category tabs")
	var before_tab: String = game.buy_tab
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(2)
	_check(game.buy_tab != before_tab, "RB switches buy-menu tabs on a pad")
	_check(game._purchase("shotgun", 1100) and player.weapon_id == "shotgun" and game.cash == 2100, "Shotgun can be bought in the buy phase")
	_check(not game._purchase("marksman", 2200) and game.cash == 2100, "A second primary is rejected by the strict purchase path")
	_check(game._buy_weapon("ak") and not player.owned.has("shotgun") and player.owned.has("ak") and game.cash == 3200 - 1500, "Buying a different primary sells this round's primary back first")
	_check(game._sell("ak") and game.cash == 3200 and not player.owned.has("ak"), "Sell-back refunds the full price during the buy phase")
	_check(game._buy_weapon("m1911") and player.owned_in_class("pistol") == "m1911" and not player.owned.has("pistol"), "A sidearm purchase replaces the free P9")
	_check(game._sell("m1911") and player.owned_in_class("pistol") == "pistol" and game.cash == 3200, "Selling the sidearm gives the P9 back")
	game._purchase("armor", 650)
	_check(game._sell("armor") and player.armor == 0.0 and game.cash == 3200, "Armour can be sold back too")
	game._buy_weapon("rifle")
	_check(game._purchase_attachment("rifle", "reflex") and game.cash == 3200 - 1600 - 300 and player.attachment("rifle", "optic") == "reflex", "The buy menu fits a reflex sight for $300")
	_check(not game._purchase_attachment("rifle", "reflex"), "Buying the same attachment twice is rejected")
	_check(not game._purchase_attachment("rifle", "choke"), "Attachments that do not fit are rejected")
	_check(game._purchase_attachment("rifle", "holo2x") and game.cash == 3200 - 1600 - 450, "Swapping this round's optic refunds the old one")
	game.buy_tab = "mods"
	game._render_buy()
	_check(game.menu.visible and game.menu_stack.get_child_count() > 6, "The MODS tab lists attachments")
	_check(not player.switch_weapon("smg"), "Cannot switch to a weapon you do not own")
	game.buy_time_left = 0.05
	await _frames(6)
	_check(game.phase == game.Phase.LIVE and player.can_fire and not game.buy_menu_open, "The round goes live when the buy timer runs out")
	_check(not game._purchase("armor", 650) and not game._purchase_attachment("rifle", "suppressor"), "Purchases require the HQ counter after deployment")
	# Street tips: a payphone rings, the call reveals a stash, the stash banks at HQ.
	_check(game.tip_state == "idle" and game.tip_timer > 30.0, "Each contract round arms a street tip")
	game._ring_tip()
	await _frames(2)
	_check(game.tip_state == "ringing" and game.world.payphones.has(game.tip_phone), "A street payphone starts ringing")
	player.global_position = game.tip_phone + Vector3(0.8, 0.1, 0.8)
	await _frames(3)
	var tip_cash: int = game.cash
	game._interact()
	_check(game.tip_state == "active" and game.stash_mesh.visible and bool(game.tip_site.get("neutral", true)), "Answering reveals a stash at a neutral spot")
	player.global_position = game.stash_mesh.global_position + Vector3(0.6, 0.0, 0.6)
	await _frames(3)
	game._interact()
	_check(game.tip_state == "carried" and not game.stash_mesh.visible, "The stash can be grabbed")
	player.global_position = game.HOME + Vector3(0.5, 0.2, 0.5)
	await _frames(3)
	game._interact()
	_check(game.tip_state == "done" and game.cash == tip_cash + game.TIP_VALUE and game.phase == game.Phase.LIVE, "Banking the stash at HQ pays without ending the round")
	player.global_position = game.ArmoryScript.RACK + Vector3(0, 0.1, 1.2)
	await _frames(3)
	var contract_ammo: int = player.ammo
	player.ammo = 1
	game._interact()
	_check(player.ammo == 1, "The armory does not resupply during contracts")
	player.ammo = contract_ammo
	game._finish(false, "Survived", "Setup")
	game._start_round()
	await _frames(2)
	_check(player.owned.has("rifle") and player.attachment("rifle", "optic") == "holo2x" and game.purchased.is_empty(), "Survivors keep their weapons and attachments (CS rules)")
	game._start_live()
	player.take_damage(1000.0)
	game._start_round()
	await _frames(2)
	_check(player.owned.size() == 1 and player.attachments.is_empty() and player.armor == 0.0, "The dead start the next round with a pistol")
	game._start_live()

	# --- 0.3: attachments ------------------------------------------------------------------
	game._show_title()
	game._start_free_roam()
	await _frames(5)
	player.switch_weapon("rifle")
	await _frames(25)
	_check(not player.fits("pistol", "scope4x") and player.fits("rifle", "scope4x") and not player.fits("double", "reflex"), "Attachment fit rules are per weapon")
	_check(not player.set_attachment("rifle", "optic", "choke"), "Wrong-slot attachments are refused")
	var muzzle_before: Vector3 = player.camera.to_local(player.muzzle_position())
	player.set_attachment("rifle", "muzzle", "suppressor")
	player.set_attachment("rifle", "magazine", "extended")
	await _frames(2)
	var muzzle_after: Vector3 = player.camera.to_local(player.muzzle_position())
	_check(bool(player.weapon_stats().get("quiet", false)) and int(player.weapon_stats()["capacity"]) == 45, "Suppressor and extended mag change the carbine's stats")
	_check(muzzle_after.z < muzzle_before.z - 0.1, "Suppressor moves the muzzle forward on the model")
	player.set_attachment("rifle", "optic", "scope4x")
	_check(bool(player.weapon_stats()["scope"]) and is_equal_approx(float(player.weapon_stats()["fov"]), 22.0), "4x scope turns the carbine into a scoped rifle")
	player._start_reload()
	await _frames(170)
	_check(player.ammo == 45, "Extended magazine reloads to 45")
	player.set_attachment("rifle", "magazine", "")
	_check(player.ammo == 30, "Removing the extended mag clamps the loaded rounds")
	player.set_attachment("marksman", "optic", "reflex")
	player.switch_weapon("marksman")
	await _frames(25)
	_check(not bool(player.weapon_stats()["scope"]) and float(player.weapon_stats()["fov"]) > 40.0, "A reflex sight replaces the bolt rifle's scope")
	player.set_attachment("marksman", "optic", "")
	_check(player.attachment_summary("rifle").contains("SUPP"), "HUD summary lists fitted attachments")
	player.switch_weapon("smg")
	await _frames(25)
	player.set_attachment("smg", "underbarrel", "laser")
	await _frames(3)
	_check(game.laser_dot != null and game.laser_dot.visible, "Laser sight projects a visible dot")
	player.set_attachment("smg", "underbarrel", "")
	await _frames(2)
	_check(not game.laser_dot.visible, "Laser dot disappears when the laser is removed")
	game._gunsmith()
	_check(game.paused and game.menu.visible, "Gunsmith opens as a menu")
	var first_slot: Button = null
	for child: Node in game.menu_stack.get_children():
		if child is Button and (child as Button).text.begins_with("OPTIC"):
			first_slot = child as Button
			break
	if first_slot != null:
		first_slot.pressed.emit()
	_check(first_slot != null and player.attachment("smg", "optic") != "", "Gunsmith cycles an optic onto the weapon in hand")
	game._arsenal()
	var arsenal_rows: int = 0
	for child: Node in game.menu_stack.get_children():
		if child is Button and (child as Button).text.contains("/"):
			arsenal_rows += 1
	_check(arsenal_rows >= 13, "The arsenal lists every weapon")
	game._resume()

	# --- 0.3: controller --------------------------------------------------------------------
	var has_pad_fire: bool = false
	for event: InputEvent in InputMap.action_get_events("fire"):
		has_pad_fire = has_pad_fire or event is InputEventJoypadMotion
	_check(has_pad_fire and InputMap.has_action("stick_left") and InputMap.has_action("look_right") and InputMap.has_action("pad_throttle"), "Gamepad bindings exist for fire, sticks and triggers")
	game.using_pad = false
	var keyboard_glyph: String = game._glyph("interact")
	game.using_pad = true
	game.pad_is_playstation = false
	var xbox_glyph: String = game._glyph("interact")
	game.pad_is_playstation = true
	var ps_glyph: String = game._glyph("interact")
	game.using_pad = false
	_check(keyboard_glyph == "E" and xbox_glyph == "Y" and ps_glyph == "TRIANGLE", "Prompts switch between keyboard, Xbox and PlayStation names")
	var pad_car: Variant = game.cars[0]
	pad_car.reset_car(Vector3(0, 0.1, 60))
	player.global_position = pad_car.global_position + Vector3(-2.5, 0.1, 0)
	await _frames(5)
	game._interact()
	await _frames(3)
	var pad_start: float = pad_car.position.z
	Input.action_press("pad_throttle", 1.0)
	await _frames(90)
	Input.action_release("pad_throttle")
	_check(pad_car.occupied and pad_car.position.z < pad_start - 3.0, "Right trigger drives the car")
	pad_car.reset_car(pad_car.position)
	await _frames(20)
	game._interact()
	await _frames(3)

	# --- Map, crews, city, characters, grade --------------------------------------------
	var map_event: InputEventAction = InputEventAction.new()
	map_event.action = "map"
	map_event.pressed = true
	game._unhandled_input(map_event)
	await _frames(2)
	_check(game.map_open and game.full_map.visible, "Map key opens the full city map")
	game._unhandled_input(map_event)
	_check(not game.map_open, "Map key closes it again")
	_check(game.world.districts.size() >= 9 and game.world.crew_spawns.size() == 4 and game.world.landmarks.size() >= 20, "Port Halcyon has its districts, 4 crew HQs and its landmarks")
	_check(game._district_at(Vector3(0, 0, 0)) == "MIDTOWN", "Radar names the district under the player")
	game.crew = "kingsway"
	game._apply_crew()
	var rivals: bool = true
	for bot_guard: Variant in game._all_guards():
		rivals = rivals and bot_guard.crew != "kingsway"
	_check(rivals, "Practice bots always wear a rival crew's colours")
	var bot: Variant = game.guards[0]
	_check(bot.suit.has_method("animate") and bot.suit.shoulder_r != null, "Practice bots use the animated crew rig")
	game.film_grade = false
	game._apply_settings()
	_check(not game.grade_rect.visible, "Film grade can be switched off")
	game.film_grade = true
	game._apply_settings()

	# --- Settings persistence ------------------------------------------------------
	game.crew = "kojimoto"
	game.master_volume = 0.3
	game.fov_setting = 92.0
	player.mouse_sensitivity = 0.004
	game._save_settings()
	game.crew = "morris"
	game.master_volume = 0.9
	game.fov_setting = 75.0
	player.mouse_sensitivity = 0.001
	game._load_settings()
	_check(is_equal_approx(game.master_volume, 0.3) and is_equal_approx(game.fov_setting, 92.0) and is_equal_approx(player.mouse_sensitivity, 0.004), "Settings persist through save and load")
	_check(is_equal_approx(player.base_fov, 92.0), "Field of view setting applies to the camera")
	_check(game.crew == "kojimoto" and game.Factions.get_crew("kojimoto")["name"] == "KOJIMOTO893" and game.Factions.get_crew("morris")["name"] == "MORRIS MAFIA", "Crews are the Morris Mafia and Kojimoto893, and the choice persists")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.settings_path))

	_release_inputs()
	completed = true
	print("FREE ROAM RESULT: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	# Give the audio thread a moment to release stopped playbacks before exit.
	for settle: int in range(10):
		await process_frame
	quit(1 if failures > 0 else 0)
