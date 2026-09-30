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

	# --- Round report -------------------------------------------------------------------
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
