extends SceneTree
## Headless integration checks against the actual playable scene and physics world.
## Run: godot --headless --path . --script res://tests/integration.gd
## Any failed check exits with status 1; an unfinished suite exits with status 2.

var game: Variant
var failures: int = 0
var checks: int = 0
var completed: bool = false


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
	for action: String in ["move_forward", "move_back", "move_left", "move_right", "handbrake", "fire", "aim", "sprint", "crouch", "jump", "reload"]:
		if InputMap.has_action(action):
			Input.action_release(action)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _timeout() -> void:
	if completed:
		return
	_release_inputs()
	push_error("Integration suite did not finish within 60 seconds.")
	quit(2)


func _run() -> void:
	create_timer(60.0).timeout.connect(_timeout)
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	if scene == null:
		push_error("Cannot load main scene.")
		quit(1)
		return
	game = scene.instantiate()
	root.add_child(game)
	await _frames(3)
	_check(game.phase == game.Phase.MENU, "Main scene starts at title menu")
	game._start_round()
	_check(game.phase == game.Phase.BUY and game.cash == 3200, "Round starts with buying phase and $3,200")
	_check(is_equal_approx(game.buy_time_left, 30.0), "Pre-round buy phase lasts 30 seconds")
	_check(game._purchase("rifle", 1600), "Carbine purchase succeeds")
	_check(game.cash == 1600 and game.player.weapon_id == "rifle", "Purchase deducts exact price and equips weapon")
	_check(not game._purchase("rifle", 1600) and game.cash == 1600, "Duplicate purchase cannot debit cash")
	_check(not game._purchase("smg", 1000) and game.cash == 1600, "Only one primary weapon can be purchased")
	_check(game._purchase("armor", 650) and game.cash == 950 and game.player.armor == 75.0, "Armor purchase grants protection and debits $650")
	_check(not game._purchase("armor", 650) and game.cash == 950, "Duplicate armor cannot debit cash")
	game._start_live()
	_check(not game._purchase("smg", 1000) and game.cash == 950, "Buying is rejected after deployment")

	# Walk through the actual interaction, paid pickup, drop, recollect and delivery.
	game.player.position = Vector3(0, 0.1, -40.0)
	game._interact()
	_check(game.paused and game.menu.visible and not game.carrying, "Exchange interaction opens negotiation without free pickup")
	game._pay_deal()
	_check(game.paid and game.carrying and not game.case_mesh.visible and game.cash == 150, "Paid deal debits $800 once and grants the case")
	game._pay_deal()
	_check(game.cash == 150, "Repeated payment cannot debit cash twice")
	var drop: InputEventAction = InputEventAction.new()
	drop.action = "drop"
	drop.pressed = true
	game._unhandled_input(drop)
	_check(not game.carrying and game.case_mesh.visible, "Drop returns the case to the world")
	game._interact()
	_check(game.carrying and game.cash == 150, "Recollecting a paid case costs nothing")
	game.player.position = game.HOME
	game._interact()
	_check(game.phase == game.Phase.RESULT and game.cash == 2750, "Delivery ends round and grants exactly $2,600")
	game._finish(true, "Repeat", "Repeat")
	game._interact()
	_check(game.cash == 2750, "Repeated completion cannot pay twice")

	# Loss streaks carry money forward; equipment and death state reset per round.
	var allowances: Array[int] = [1200, 1500, 1800, 2100, 2400, 2400]
	for allowance: int in allowances:
		game._start_round()
		game._start_live()
		var balance: int = game.cash
		game._finish(false, "Integration loss", "Test recovery allowance")
		_check(game.cash == mini(balance + allowance, 16000), "Loss allowance is $%d with wallet cap" % allowance)
		game._finish(false, "Repeat", "Repeat")
		_check(game.cash == mini(balance + allowance, 16000), "Repeated loss does not pay again")
	game._start_round()
	game._purchase("armor", 650)
	game._purchase("smg", 1000)
	game._start_live()
	game.player.take_damage(1000.0)
	_check(game.phase == game.Phase.RESULT and game.player.health == 0.0, "Player death ends the live round")
	game._start_round()
	_check(game.player.health == 100.0 and game.player.armor == 0.0 and game.player.weapon_id == "pistol", "Next round restores health and resets purchased loadout")
	_check(not game.player.in_vehicle and not game.carrying and not game.paid and game.purchased.is_empty(), "Next round clears vehicle, contract and purchase state")
	game._start_live()
	await _frames(20)
	var crosshair_rect: Rect2 = game.crosshair.get_global_rect()
	var viewport_rect: Rect2 = root.get_visible_rect()
	_check(crosshair_rect.get_center().distance_to(viewport_rect.get_center()) < 0.1, "Crosshair control is centered on the actual viewport")
	var aim_ray: Vector3 = game.player.camera.project_ray_normal(crosshair_rect.get_center())
	_check(aim_ray.dot(-game.player.camera.global_basis.z) > 0.99999, "Crosshair center projects onto the weapon's forward aim ray")
	var ammo_before: int = game.player.ammo
	game.player._try_fire()
	_check(game.player.ammo == ammo_before - 1, "Weapon consumes one round when fired")
	game.player._try_fire()
	_check(game.player.ammo == ammo_before - 1, "Fire-rate cooldown prevents immediate duplicate shot")
	var reserve_before: int = game.player.reserve
	game.player._start_reload()
	await _frames(95)
	_check(game.player.ammo == ammo_before and game.player.reserve == reserve_before - 1 and not game.player.reloading, "Reload transfers rounds from finite reserve")

	# Enemies must see and damage the player through the real collision layers.
	game.player.position = Vector3(0, 0.1, -37)
	await _frames(3)
	game.guards[0].hostile = true
	game.guards[0].cooldown = 0.0
	await _frames(12)
	_check(game.player.health < 100.0, "Hostile guard ray hits the player collision layer")
	game.guards[0].active = false
	game.guards[1].active = false
	var guard_health: float = game.guards[0].health
	var target_point: Vector3 = game.guards[0].global_position + Vector3(0, 1.3, 0)
	var shot_origin: Vector3 = game.player.camera.global_position
	game._on_shot(shot_origin, (target_point - shot_origin).normalized(), 34.0)
	_check(game.guards[0].health < guard_health, "Player shot ray damages a guard in the integrated world")
	var kill_balance: int = game.cash
	game.guards[0].take_damage(1000.0)
	_check(game.cash == kill_balance and game.violence, "Guard elimination starts hostility without creating money")

	# Fresh round provides a clear road and a neutral encounter for vehicle tests.
	game._finish(false, "Vehicle setup", "Setup")
	game._start_round()
	game._start_live()
	game.player.position = Vector3(3.0, 0.1, 8)
	await _frames(35)
	game._interact()
	await _frames(3)
	_check(game.car.occupied and game.player.in_vehicle and game.player.camera.current, "Interact enters sedan with a first-person driver camera")
	var start_z: float = game.car.position.z
	Input.action_press("move_forward")
	await _frames(100)
	Input.action_release("move_forward")
	_check(game.car.position.z < start_z - 4.0 and game.car.speed_kph > 15.0, "Throttle moves the grounded sedan forward in the real world")
	var paused_position: Vector3 = game.car.position
	var paused_time: float = game.time_left
	game._pause()
	await _frames(40)
	_check(game.paused and game.car.position.distance_to(paused_position) < 0.001, "Pausing a moving sedan freezes its position")
	_check(is_equal_approx(game.time_left, paused_time), "Pause freezes the round timer")
	game._resume()
	await _frames(3)
	game._interact()
	_check(game.car.occupied and game.player.in_vehicle, "Vehicle rejects unsafe exit above 8 km/h")
	# The city limit moved from 80 m to world.HALF (200 m) in 0.3; same 15 m run-up as before.
	var limit: float = game.world.HALF
	game.car.reset_car(Vector3(0, 0.1, -limit + 15.0))
	await _frames(25)
	Input.action_press("move_forward")
	await _frames(240)
	Input.action_release("move_forward")
	_check(game.car.position.z > -limit + 1.9 and game.car.position.z < -limit + 5.0, "Sedan stops at district boundary instead of crossing the wall")
	_check(game.car.speed_kph < 2.0, "Wall collision removes forward speed")
	game.car.reset_car(Vector3(-limit + 1.1, 0.1, 35))
	await _frames(25)
	game._interact()
	_check(game.car.occupied and game.player.in_vehicle and game.car.speed_kph < 1.0, "Stopped sedan rejects exit when driver door is against a wall")
	game.car.reset_car(Vector3(0, 0.1, 8))
	await _frames(25)
	game._interact()
	await _frames(3)
	_check(not game.car.occupied and not game.player.in_vehicle and game.player.camera.current, "Stopped sedan exits safely and restores first-person camera")
	_check(game.player.position.x < -1.0, "Exit positions player beside the driver door")
	game._enter_vehicle(game.car, 0)
	await _frames(3)
	var seat_pad := InputEventJoypadButton.new()
	seat_pad.button_index = JOY_BUTTON_DPAD_RIGHT
	seat_pad.pressed = true
	game._unhandled_input(seat_pad)
	_check(game.seat == 1 and game.player.in_vehicle, "D-pad right changes seats during a contract instead of opening the buy menu")
	game._exit_vehicle(true)
	game.player.reset_player(Vector3(5.8, 0.1, 11))
	await _frames(12)
	# The headless display cannot capture a mouse, so player input is intentionally
	# gated off. Exercise the real player hull, floor snap and move_and_slide at
	# walking velocity to verify geometry traversal without bypassing collision.
	game.player.set_physics_process(false)
	for step: int in range(60):
		await physics_frame
		game.player.velocity = Vector3(game.player.WALK_SPEED, -0.4, 0.0)
		game.player.move_and_slide()
	game.player.velocity = Vector3.ZERO
	game.player.set_physics_process(true)
	await _frames(8)
	_check(game.player.position.x > 8.0 and game.player.position.x < 11.7, "Player collision hull traverses road-to-sidewalk slope at walking speed")
	_check(game.player.position.y > 0.12 and game.player.position.y < 0.3 and game.player.is_on_floor(), "Sloped sidewalk supports the player at its raised surface")

	# An unaffordable exchange must leave its case and balance untouched.
	game.cash = 799
	game.player.position = Vector3(0, 0.1, -40)
	game._interact()
	game._pay_deal()
	_check(game.cash == 799 and not game.paid and not game.carrying and game.case_mesh.visible, "Insufficient funds cannot purchase the briefcase")

	# Use the actual robbery button callback rather than setting contract flags.
	var robbery_button: Button = null
	for child: Node in game.menu_stack.get_children():
		if child is Button and (child as Button).text == "TAKE IT BY FORCE":
			robbery_button = child as Button
	_check(robbery_button != null, "Negotiation exposes the robbery route")
	if robbery_button != null:
		var robbery_balance: int = game.cash
		robbery_button.pressed.emit()
		_check(game.violence and game.carrying and not game.paid and not game.paused, "Robbery collects the case and resumes a hostile round")
		_check(game.cash == robbery_balance and game.guards[0].hostile and game.guards[1].hostile, "Robbery costs no $800 and alerts both guards")
		game.player.position = game.HOME
		game._interact()
		_check(game.phase == game.Phase.RESULT and game.cash == robbery_balance + 2600 and game.losses == 0, "Robbed case delivers full reward and resets loss streak")
		game._interact()
		game._finish(true, "Repeat robbery", "Repeat")
		_check(game.cash == robbery_balance + 2600, "Robbery delivery reward cannot repeat")
	game._start_round()
	game._start_live()
	var timeout_balance: int = game.cash
	game.time_left = 0.02
	await _frames(10)
	_check(game.phase == game.Phase.RESULT and game.cash == timeout_balance + 1200, "Expired round ends in defeat and grants first-loss recovery")
	await _frames(10)
	_check(game.cash == timeout_balance + 1200 and game.losses == 1, "Expired timer cannot repeatedly grant recovery money")
	# Round-long HQ purchases are allowed, but the sell-back window is only pre-round.
	game._start_round()
	var shop_balance: int = game.cash
	_check(game._buy_weapon("m1911") and game.cash == shop_balance - 350, "Sidearm purchase works during the buy phase")
	_check(game._sell("m1911") and game.cash == shop_balance, "Buy-phase return refunds this round's purchase")
	game._start_live()
	game.player.position = game.HOME
	var buy_pad := InputEventJoypadButton.new()
	buy_pad.button_index = JOY_BUTTON_DPAD_LEFT
	buy_pad.pressed = true
	game._unhandled_input(buy_pad)
	_check(game.buy_menu_open and game._buy_weapon("m1911") and game.cash == shop_balance - 350, "HQ supply counter sells equipment mid-round")
	_check(not game._sell("m1911") and game.cash == shop_balance - 350, "Mid-round purchases cannot be refunded")
	game._close_buy_menu()
	_check(not game._buy_weapon("revolver"), "A closed counter rejects mid-round purchases")
	_release_inputs()
	completed = true
	print("INTEGRATION RESULT: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
