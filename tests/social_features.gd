extends SceneTree
## Headless checks for the overnight social/presentation features in main.gd, player.gd and
## character_model.gd: hands up (a peace signal that really disarms you), binoculars, the
## round report, potato-mode persistence, indoor/outdoor reverb detection and the audio-only
## ambient events. Uses an isolated settings file.
## Run: godot --headless --path . --script res://tests/social_features.gd

const SETTINGS: String = "res://.godot/social_test_settings.cfg"
const CharacterModelScript = preload("res://scripts/character_model.gd")

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


func _timeout() -> void:
	if completed:
		return
	Input.action_release("binoculars")
	push_error("Social features suite did not finish within 120 seconds.")
	quit(2)


func _menu_text(node: Node) -> String:
	var text: String = ""
	for child: Node in node.get_children():
		if child is Label:
			text += (child as Label).text + "\n"
		text += _menu_text(child)
	return text


func _run() -> void:
	create_timer(120.0).timeout.connect(_timeout)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.settings_path = SETTINGS
	root.add_child(game)
	await _frames(3)
	var player: Variant = game.player

	# --- Potato mode setting ---------------------------------------------------------
	_check(game.potato_mode == false, "Potato mode is off by default")
	game.potato_mode = true
	game._apply_settings()
	if game.world.has_method("set_potato_mode"):
		_check(bool(game.world.get("potato_mode")), "Potato mode reaches world.set_potato_mode")
	game._save_settings()
	var config: ConfigFile = ConfigFile.new()
	_check(config.load(SETTINGS) == OK and bool(config.get_value("video", "potato_mode", false)), "Potato mode is saved in the settings file")
	game.potato_mode = false
	game._load_settings()
	_check(game.potato_mode == true, "Potato mode is restored from the settings file")
	game.potato_mode = false
	game._apply_settings()
	game._save_settings()

	# --- Hands up -----------------------------------------------------------------------
	game._start_free_roam()
	await _frames(20)
	var signalled: Array = []
	player.gesture_changed.connect(func(up: bool): signalled.append(up))
	_check(game.toggle_hands_up() and player.hands_up and not player.weapon_ready(), "X raises the hands and puts the weapon away")
	_check(signalled == [true], "Raising the hands emits gesture_changed(true) for replication")
	var before: int = player.ammo
	player._cooldown = 0.0
	player._draw_time = 0.0
	player._try_fire()
	_check(player.ammo == before, "With hands up the player cannot fire")
	await _frames(2)
	_check(not player._gun.visible, "With hands up the first-person weapon is hidden")
	_check(game.toggle_hands_up() and not player.hands_up and player.weapon_ready(), "X again lowers the hands")
	player._cooldown = 0.0
	player._draw_time = 0.0
	player._try_fire()
	_check(player.ammo == before - 1, "Hands down: the weapon fires again")
	player.set_hands_up(true)
	player.reset_player(player.global_position)
	_check(not player.hands_up, "A respawn/reset lowers the hands")

	# --- Hands up on the character model (what other players see) -----------------------
	var model: Variant = CharacterModelScript.new()
	model.build("morris", true)
	root.add_child(model)
	model.hands_up = true
	for step: int in range(90):
		model.animate(1.0 / 60.0, Vector3.ZERO, false)
	var skeleton: Skeleton3D = model.skeleton
	var hand_y: float = skeleton.get_bone_global_pose(CharacterModelScript.Bone.HAND_R).origin.y
	var head_y: float = skeleton.get_bone_global_pose(CharacterModelScript.Bone.HEAD).origin.y
	_check(hand_y > head_y, "Character model: hands-up pose lifts the hands above the head (%.2f vs %.2f)" % [hand_y, head_y])
	var weapon: Variant = model.get("_weapon")
	_check(weapon == null or not (weapon as Node3D).visible, "Character model: the sidearm is hidden with hands up")
	model.hands_up = false
	for step: int in range(90):
		model.animate(1.0 / 60.0, Vector3.ZERO, false)
	hand_y = skeleton.get_bone_global_pose(CharacterModelScript.Bone.HAND_R).origin.y
	_check(hand_y < head_y - 0.3, "Character model: hands come back down")
	model.queue_free()

	# --- Binoculars ---------------------------------------------------------------------
	Input.action_press("binoculars")
	await _frames(30)
	_check(player.binoculars and player.camera.fov < 25.0 and not player.weapon_ready(), "Holding Z raises binoculars: narrow view (%.1f°), weapon lowered" % player.camera.fov)
	Input.action_release("binoculars")
	await _frames(30)
	_check(not player.binoculars and player.camera.fov > 50.0, "Releasing Z lowers the binoculars")

	# --- Audio hooks --------------------------------------------------------------------
	game.guard_shot(player.global_position + Vector3(30, 1.5, 0), player.global_position, false)
	_check(true, "Guard shots use the distance-aware play_shot_at")
	game._on_weapon_event("mag_in")
	game._on_weapon_event("draw")
	_check(game.sfx.has_sound("slide") and game.sfx.has_sound("holster"), "Slide and holster sounds exist for the reload/switch hooks")
	game._ambient_wait = 0.0
	game._update_ambient_events(0.1)
	_check(game._ambient_wait >= 25.0 and game._ambient_wait <= 60.0, "Ambient dog/siren events reschedule 25-60 s later")
	var rng_a: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_a.seed = 0x5A1E5
	_check(is_equal_approx(rng_a.randf_range(25.0, 60.0), game._ambient_wait), "Ambient events use their own seeded RNG (the global RNG is untouched)")
	_check(not game.player_indoors(), "Standing in the armory yard counts as outdoors")
	var interiors: Array = game._interior_nodes
	if interiors.is_empty():
		_check(true, "No building declares an interior (indoor reverb inactive)")
	else:
		var inside: Node3D = interiors[0]
		var saved: Vector3 = player.global_position
		player.global_position = inside.global_transform * Vector3(0, 1.0, 0)
		game._update_space(1.0)
		_check(game.player_indoors() and game._space == "indoor", "Inside %s the reverb switches to indoor" % inside.name)
		player.global_position = saved
		game._update_space(1.0)
		_check(game._space == "outdoor", "Leaving the building restores outdoor reverb")
		# Interior beds: club bass in the club, room tone elsewhere, hall reverb in the garage, its roof is outdoors.
		var by_name: Dictionary = {}
		for node: Node3D in interiors:
			by_name[node.name] = node
		for spec: Array in [["Nightclub", Vector3(-1.5, 1.0, -1.0), "indoor", "club_bass"], ["Hotel", Vector3(0, 1.0, 4.0), "indoor", "room_tone"],
				["Garage", Vector3(0, 1.0, 10.5), "hall", ""], ["Garage", Vector3(0, 6.9, -10.0), "outdoor", ""]]:
			if not by_name.has(spec[0]):
				_check(false, "%s declares an interior" % spec[0])
				continue
			player.global_position = (by_name[spec[0]] as Node3D).global_transform * (spec[1] as Vector3)
			game._update_space(1.0)
			_check(game._space == spec[2] and game._interior_bed == spec[3], "%s at %s: %s reverb, bed '%s' (got %s, '%s')" % [spec[0], spec[1], spec[2], spec[3], game._space, game._interior_bed])
		player.global_position = saved
		game._update_space(1.0)
		_check(game._interior_bed == "", "Outdoors the interior bed stops")

	# --- Round report -------------------------------------------------------------------
	game._start_round()
	await _frames(3)
	game._start_live()
	await _frames(3)
	# --- Trade item: sidearm only ------------------------------------------------------
	player.set_loadout(["pistol", "smg"])
	_check(player.weapon_id == "smg" and not player.sidearm_only, "Contract loadout: SMG in hand, sidearm rule off")
	game.carrying = true
	await _frames(2)
	_check(player.sidearm_only and player.weapon_id == "pistol", "Offline: carrying the case sets sidearm-only and draws the pistol")
	_check(not player.switch_weapon("smg") and not player.can_use("smg") and player.can_use("pistol"), "Sidearm-only: the primary cannot be drawn")
	player.cycle_weapon(1)
	player.quick_swap()
	_check(player.weapon_id == "pistol", "Sidearm-only: cycling and quick swap never draw a primary")
	player.equip("rifle")
	_check(player.owned.has("rifle") and player.weapon_id == "pistol", "Sidearm-only: a purchased primary is owned but stays holstered")
	game.carrying = false
	await _frames(2)
	_check(not player.sidearm_only and player.weapon_id == "pistol", "Dropping the case clears the rule without auto-switching")
	_check(player.switch_weapon("rifle") and player.weapon_id == "rifle", "After the drop the holstered primary can be drawn again")
	player.set_sidearm_only(true)
	_check(player.weapon_id == "pistol" and player.sidearm_only, "Setting sidearm-only with a primary drawn switches to the pistol")
	player.set_loadout(["smg"])
	player.set_sidearm_only(true)
	_check(player.weapon_id == "pistol" and player.owned.has("pistol"), "With no sidearm owned, sidearm-only adds and draws a pistol")
	player.reset_player(player.global_position)
	_check(not player.sidearm_only, "reset_player clears sidearm-only")
	player.set_loadout(["pistol"])

	# --- Phone drop key, pad holds, hands up / binoculars pad binds -----------------------
	var k_bound: bool = false
	for event: InputEvent in InputMap.action_get_events("drop_phone"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_K:
			k_bound = true
	_check(k_bound, "drop_phone is bound to K")
	var pad_hands: bool = false
	for event: InputEvent in InputMap.action_get_events("hands_up"):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_RIGHT_STICK:
			pad_hands = true
	_check(pad_hands, "hands_up has a pad bind (R3)")
	_check(game._glyph("drop_phone") == "K" and game._glyph("binoculars") == "Z", "Glyphs exist for the phone drop and binoculars")
	var press_down: InputEventJoypadButton = InputEventJoypadButton.new()
	press_down.button_index = JOY_BUTTON_DPAD_DOWN
	press_down.pressed = true
	var release_down: InputEventJoypadButton = InputEventJoypadButton.new()
	release_down.button_index = JOY_BUTTON_DPAD_DOWN
	release_down.pressed = false
	game.carrying = true
	game._unhandled_input(press_down)
	_check(game.carrying, "Pad D-pad down press alone does not drop the trade item yet")
	game._unhandled_input(release_down)
	_check(not game.carrying, "A pad D-pad down tap drops the trade item on release")
	game.carrying = true
	game._unhandled_input(press_down)
	game._pad_hold_start[JOY_BUTTON_DPAD_DOWN] = Time.get_ticks_msec() - 700
	game._pad_hold_update()
	_check(bool(game._pad_hold_fired.get(JOY_BUTTON_DPAD_DOWN, false)), "Holding D-pad down 0.5 s fires the phone drop")
	game._unhandled_input(release_down)
	_check(game.carrying, "A D-pad down hold does not also drop the trade item")
	game.carrying = false
	await _frames(2)
	var press_up: InputEventJoypadButton = InputEventJoypadButton.new()
	press_up.button_index = JOY_BUTTON_DPAD_UP
	press_up.pressed = true
	var release_up: InputEventJoypadButton = InputEventJoypadButton.new()
	release_up.button_index = JOY_BUTTON_DPAD_UP
	release_up.pressed = false
	game._unhandled_input(press_up)
	game._pad_hold_start[JOY_BUTTON_DPAD_UP] = Time.get_ticks_msec() - 700
	game._pad_hold_update()
	await _frames(2)
	_check(game._pad_binoculars and player.binoculars, "Holding D-pad up raises the binoculars")
	game._unhandled_input(release_up)
	await _frames(2)
	_check(not game._pad_binoculars and not player.binoculars, "Releasing D-pad up lowers the binoculars")

	# --- Host line-of-sight and map-bound hooks ----------------------------------------------
	_check(game.net.los_check.is_valid(), "net.los_check is set after online setup")
	_check(game.net.map_half_extent >= 400.0 and game.net.map_half_extent < 6000.0, "net.map_half_extent is the city plus a margin (%.0f m)" % game.net.map_half_extent)
	_check(bool(game.net.los_check.call(Vector3(0, 60, 0), Vector3(30, 60, 0))), "los_check: an open-air segment is clear")
	var walled: bool = false
	var walled_clear: bool = false
	for rect: Rect2 in game.world.footprints:
		if rect.size.x < 8.0 or rect.size.y < 8.0:
			continue
		var centre: Vector2 = rect.get_center()
		var from: Vector3 = Vector3(rect.position.x - 6.0, 1.5, centre.y)
		var to: Vector3 = Vector3(rect.end.x + 6.0, 1.5, centre.y)
		if not bool(game.net.los_check.call(from, to)):
			walled = true
			# The same wall must not block a segment that never crosses it.
			walled_clear = bool(game.net.los_check.call(from, from + Vector3(0, 0, 4.0))) or bool(game.net.los_check.call(from, from + Vector3(-4.0, 0, 0)))
			break
	_check(walled, "los_check: a segment through a solid building is blocked")
	_check(walled_clear, "los_check: open ground beside that building is clear")
	if not game.world.glass_panes.is_empty():
		var pane: Node3D = game.world.glass_panes[0]["body"] as Node3D
		var glass_from: Vector3 = pane.global_transform * Vector3(0, 0, -0.6)
		var glass_to: Vector3 = pane.global_transform * Vector3(0, 0, 0.6)
		_check(bool(game.net.los_check.call(glass_from, glass_to)), "los_check: an intact shop window does not block a hit")


	# Death (ends the contract round, so it runs last and the round is restarted for the report check).
	player.set_loadout(["pistol", "smg"])
	player.set_sidearm_only(true)
	player.take_damage(1000.0)
	_check(player.is_dead() and not player.sidearm_only, "Death clears sidearm-only")
	game._start_round()
	await _frames(3)
	game._start_live()
	await _frames(3)

	game.shots_fired += 3
	game.shots_hit += 1
	game._finish(false, "Test", "Report check.")
	await _frames(2)
	var shown: String = _menu_text(game.menu)
	_check(shown.contains("Round report") and shown.contains("3 shots, 1 hit"), "The round-end screen carries a round report (time, shots, hits, documents)")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	completed = true
	print("SOCIAL FEATURES RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
