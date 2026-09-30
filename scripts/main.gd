extends Node3D
## Offline vertical-slice coordinator. Round economy is deliberately isolated here
## so that a future authority/server can own transactions and objective state.
## Two modes share one world: CONTRACT (buy phase → exchange → delivery rounds) and
## FREE ROAM (no clock or economy: the whole arsenal, the armory range, every vehicle).
const PlayerScript = preload("res://scripts/player.gd")
const CarScript = preload("res://scripts/car.gd")
const WorldScript = preload("res://scripts/world.gd")
const GuardScript = preload("res://scripts/guard.gd")
const SfxScript = preload("res://scripts/sfx.gd")
const VoiceScript = preload("res://scripts/voice.gd")
const EffectsScript = preload("res://scripts/effects.gd")
const ArmoryScript = preload("res://scripts/armory.gd")
const Factions = preload("res://scripts/factions.gd")
const CharacterModel = preload("res://scripts/character_model.gd")
const MeshKit = preload("res://scripts/mesh_kit.gd")
const NetScript = preload("res://scripts/net.gd")
const OnlineScript = preload("res://scripts/online.gd")
const START_CASH: int = 3200
const DEAL_COST: int = 800
const PAYOUT: int = 2600
const ROUND_SECONDS: float = 240.0
## Pre-round buy phase (CS-style freeze time): crews are held at their HQ while they buy.
const BUY_SECONDS: float = 30.0
const BUY_STATION_RADIUS: float = 7.0
## How far a player may wander from the HQ door while the doors are locked.
const HQ_YARD: float = 7.0
const ARMOR_PRICE: int = 650
## Buy menu tabs: the five weapon classes, then gear and attachments.
const BUY_TABS: Array[String] = ["pistol", "smg", "rifle", "shotgun", "marksman", "gear", "mods"]
const TAB_LABEL: Dictionary = {"pistol": "PISTOLS", "smg": "SMGS", "rifle": "RIFLES", "shotgun": "SHOTGUNS", "marksman": "MARKSMAN", "gear": "GEAR", "mods": "MODS"}
const DEAL := Vector3(0,0,-42)
const GOLD := Color("edb965")
const TEAL := Color("76c8bd")
const RED := Color("e4604c")
const INK := Color("f1e9d6")
const MUTED := Color("93a29f")
## Midtown pool vehicles. cars[0] (the yellow sedan) is the contract-mode default car.
## The motor pool beside the armory lets free roam try every vehicle type.
const CAR_SPAWNS: Array[Dictionary] = [
	{"at": Vector3(5, 0.5, 8), "yaw": 0.0, "color": Color("d5a748"), "name": "YELLOW SEDAN", "type": "sedan"},
	{"at": Vector3(4.2, 0.5, -58), "yaw": 0.0, "color": Color("d9d6cc"), "name": "WHITE SEDAN", "type": "sedan"},
	{"at": Vector3(-4.2, 0.5, -27.0), "yaw": 0.0, "color": Color("b8201f"), "name": "RED MOTORCYCLE", "type": "motorcycle"},
	{"at": Vector3(-4.2, 0.5, -17.0), "yaw": 0.0, "color": Color("1f4f8f"), "name": "BLUE COUPE", "type": "coupe"},
	{"at": Vector3(-4.4, 0.5, 26.0), "yaw": PI, "color": Color("2f3a2c"), "name": "GREEN SUV", "type": "suv"},
	{"at": Vector3(4.6, 0.5, 32.0), "yaw": 0.0, "color": Color("c9c1b0"), "name": "CREAM PICKUP", "type": "pickup"},
]
## Each crew parks a liveried car and a bike outside its HQ.
const CREW_RIDES: Dictionary = {"morris": "sedan", "kingsway": "suv", "solnegro": "pickup", "kojimoto": "coupe"}
const RADAR_RANGE: float = 90.0
## Extra free-roam security, kept well clear of the armory yard so the range stays calm.
const DRILL_POSTS: Array[Vector3] = [Vector3(-9.3, 0, -35.2), Vector3(-10.5, 0, -46.5), Vector3(1.5, 0, -55.0)]
const GUNFIRE_ALERT_RADIUS: float = 7.0
const GUARD_RESPAWN: float = 12.0
## Door reach for getting in: metres from the door, or from the vehicle's centre.
const DOOR_REACH: float = 2.6
const CENTRE_REACH: float = 4.2
## Walk-in shop doors answer E within this distance (and only when no car door is nearer).
const SHOP_DOOR_REACH: float = 2.0
enum Phase { MENU, BUY, LIVE, RESULT }
var phase: Phase = Phase.MENU
var free_roam: bool = false
var player: FastPlayer
## Last vehicle the player entered (kept for older callers and tests).
var car: FastCar
var cars: Array[FastCar] = []
## The vehicle the player is sitting in (null on foot) and the seat index (0 = driver).
var vehicle: FastCar = null
var seat: int = -1
## Driver aiming out of the window (hold RMB / LB): one-handed guns only.
var driveby: bool = false
var avatar: CharacterModel
var guards: Array[FastGuard] = []
var drill_guards: Array[FastGuard] = []
var world: FastWorld
## Online session (docs/NET_M1_SPEC.md). Always present; idle offline.
var net: FastNet
## The online match: remote players, shared cars, items and host rules (scripts/online.gd).
var online: FastOnline
var armory: ArmoryScript
var effects: EffectsScript
var sfx: SfxScript
var voice: Node
var chase: Camera3D
var case_mesh: Node3D
var cash: int = START_CASH
var round_number: int = 0
var losses: int = 0
var time_left: float = ROUND_SECONDS
var carrying: bool = false
## Gamepad D-pad taps and holds. Down: tap drops the trade item, hold drops the crew phone. Up: tap swaps to
## the last weapon, hold raises the binoculars. Keyed by JOY_BUTTON_*; the tap fires on release.
const PAD_HOLD_SECONDS: float = 0.5
var _pad_hold_start: Dictionary = {}
var _pad_hold_fired: Dictionary = {}
var _pad_binoculars: bool = false
var violence: bool = false
var paid: bool = false
var paused: bool = false
var msg_timer: float = 0.0
var hit_timer: float = 0.0
var hit_kind: String = "hit"
var damage_flash: float = 0.0
var damage_marks: Array[Dictionary] = []
var shots_fired: int = 0
var shots_hit: int = 0
var respawn_timer: float = -1.0
var hud: Control
var overlay: Control
## Full-screen HUD layer; the crosshair is drawn at its exact centre.
var crosshair: Control
var top_left: Label
var top_center: Label
var top_right: Label
var objective_label: Label
var marker_label: Label
var stats_label: Label
var prompt_label: Label
var prompt_panel: PanelContainer
var hint_label: Label
var feed_label: Label
var vitals_label: Label
var weapon_label: Label
var ammo_label: Label
var slots_label: Label
var fps_label: Label
var mini_map: Control
var menu: PanelContainer
var menu_stack: VBoxContainer
var menu_scroll: ScrollContainer
var buy_status: Label
var buy_buttons: Array[Button] = []
## Items bought this round -> price paid (sell-back refunds exactly this).
var purchased: Dictionary = {}
## Delivery point: the player's crew HQ (set by _apply_crew).
var HOME: Vector3 = Vector3(0, 0, 15)
## GPS line on the radar and map: the street route to the current objective (contracts only).
var gps_path: PackedVector3Array = PackedVector3Array()
var gps_color: Color = Color.WHITE
var _gps_timer: float = 0.0
var hq_spawn: Vector3 = Vector3(0, 1, 12)
var hq_yaw: float = 0.0
var buy_time_left: float = BUY_SECONDS
var buy_menu_open: bool = false
var buy_tab: String = "rifle"
var buy_detail: Label
## Which carried weapon the MODS tab fits parts to.
var buy_mod_target: String = ""
## Survivors keep their gear into the next round (CS rules); the dead start over.
var _carry_gear: bool = false
var _armor_before: float = 0.0
var master_volume: float = 0.55
var fov_setting: float = 85.0
var show_fps: bool = false
## 0 = off, 1 = medium (2 cascades, 70 m, default), 2 = high (4 cascades, 95 m).
var shadow_quality: int = 1
var settings_path: String = "user://settings.cfg"
## Pause when the window loses focus. Automated render captures switch this off.
var pause_on_focus_loss: bool = true
var engine_player: AudioStreamPlayer
var skid_player: AudioStreamPlayer
var horn_player: AudioStreamPlayer
var ambience_player: AudioStreamPlayer
var _trigger_hit: bool = false
var _pellet_count: int = 0
var _rpm: float = 0.0
var _last_skid: Vector3 = Vector3.INF
var _chase_yaw: float = 0.0
var _chase_pitch: float = 0.0
var _chase_idle: float = 10.0
var _shake: float = 0.0
var _title_angle: float = 0.6
var _guard_respawns: Dictionary = {}
var _rack_start: int = -1
var rack_best: float = 0.0
## The player's crew (identity only: rules are identical for every crew).
var crew: String = "morris"
var lighting_dusk: bool = true
var lineup: Array[Node3D] = []
var accent_bar: ColorRect
var full_map: Control
var map_open: bool = false
## Film grade post-process (grain, contrast, split tone, vignette) under the HUD.
var film_grade: bool = true
## Potato mode (bare-minimum PCs): hides collision-free dressing via world.set_potato_mode.
var potato_mode: bool = false
## Audio-only city life: a local RNG (never gameplay) schedules distant dogs and sirens.
var _ambient_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _ambient_wait: float = 30.0
var _space_check: float = 0.0
var _space: String = "outdoor"
var _interior_bed: String = ""
var _interior_bed_player: AudioStreamPlayer
var _interior_nodes: Array[Node3D] = []
var _interiors_scanned: bool = false
## Coarse grid over the walk-in interiors (cell -> indices into _interior_nodes, ascending), built once after the
## world exists: the host looks a building up for every voice frame, so it must not scan all ~700 of them.
var _interior_grid: Dictionary = {}
const INTERIOR_CELL: float = 32.0
## Same idea for doors (cell -> indices into world.interactable_doors). Lift doors move, so they are listed apart.
var _door_grid: Dictionary = {}
var _door_lifts: PackedInt32Array = PackedInt32Array()
var _door_grid_count: int = -1
const DOOR_CELL: float = 16.0
## Round summary bookkeeping (contract rounds).
var _round_started_msec: int = 0
var _round_shots_base: int = 0
var _round_hits_base: int = 0
var grade_rect: ColorRect
var _steam_timer: float = 0.0
var laser_dot: MeshInstance3D
var laser_beam: MeshInstance3D
var using_pad: bool = false
var pad_is_playstation: bool = false
var pad_device: int = 0
var vibration: bool = true
## Vehicle camera: first person from the seat, or a third-person chase view. Aiming, a
## drive-by or a gunner's shot always uses the seat's eye.
var drive_third_person: bool = false
var _tp_heading: float = 0.0
var _tp_distance: float = 7.0
var _tp_last_look: Vector2 = Vector2.ZERO
var _tp_idle: float = 0.0
## Menu action for the pad's B / Circle button (back or resume), set by each menu.
var _menu_back: Callable = Callable()
## Street tips ("the line"): a payphone rings mid-round; answering reveals a cash stash at
## a neutral spot for a short window. States: idle, ringing, active, carried, done.
const TIP_VALUE: int = 900
const TIP_WINDOW: float = 75.0
var tip_state: String = "idle"
var tip_timer: float = -1.0
var tip_phone: Vector3 = Vector3.ZERO
var tip_site: Dictionary = {}
var stash_mesh: Node3D
var _ring_clock: float = 0.0

func _ready() -> void:
	_setup_input()
	net = NetScript.new()
	net.name = "Net"
	add_child(net)
	world = WorldScript.new()
	add_child(world)
	armory = ArmoryScript.new()
	add_child(armory)
	effects = EffectsScript.new()
	add_child(effects)
	sfx = SfxScript.new()
	add_child(sfx)
	for spawn: Dictionary in CAR_SPAWNS:
		_add_car(spawn["at"], spawn["yaw"], spawn["color"], spawn["name"], Color(0, 0, 0, 0), spawn["type"])
	for crew_id: String in Factions.ORDER:
		var home_spawn: Dictionary = world.crew_spawns[crew_id]
		var livery: Dictionary = Factions.get_crew(crew_id)
		var ride: String = str(CREW_RIDES.get(crew_id, "sedan"))
		_add_car(home_spawn["car"], home_spawn["yaw"], livery["car"], "%s %s" % [livery["short"], CarScript.TYPES[ride]["label"]], livery["car_stripe"], ride)
		var behind: Vector3 = (home_spawn["car"] as Vector3) + Basis(Vector3.UP, float(home_spawn["yaw"])) * Vector3(0, 0, 6.2)
		_add_car(behind, home_spawn["yaw"], (livery["color"] as Color).darkened(0.15), "%s MOTORCYCLE" % livery["short"], livery["car_stripe"], "motorcycle")
	for parked: Dictionary in world.parked_vehicles:
		_add_car(parked["at"], parked["yaw"], parked["color"], str(parked.get("name", "")), Color(0, 0, 0, 0), str(parked.get("type", "sedan")))
	car = cars[0]
	player = PlayerScript.new()
	player.position = Vector3(0,1,12)
	add_child(player)
	player.shot_fired.connect(_on_shot)
	player.weapon_fired.connect(_on_weapon_fired)
	player.weapon_event.connect(_on_weapon_event)
	_ambient_rng.seed = 0x5A1E5
	player.damaged.connect(_on_player_damaged)
	player.footstep.connect(_on_footstep)
	player.landed.connect(func(_speed: float): sfx.play("land"))
	player.died.connect(_on_player_died)
	# Other players' bodies (layer 3) are solid to you on foot.
	player.collision_mask = 1 | 4
	chase = Camera3D.new()
	chase.fov = 72.0
	chase.far = 650.0
	add_child(chase)
	avatar = CharacterModel.new()
	add_child(avatar)
	avatar.visible = false
	for pos: Vector3 in [Vector3(-3,0,-43),Vector3(3,0,-43)]:
		guards.append(_spawn_guard(pos))
	for pos: Vector3 in DRILL_POSTS:
		drill_guards.append(_spawn_guard(pos))
	for target: StaticBody3D in armory.get("targets"):
		target.connect("struck", _on_target_struck.bind(target))
	_build_case()
	_build_lineup()
	_build_ui()
	_build_audio()
	online = OnlineScript.new()
	online.name = "Online"
	add_child(online)
	online.setup(self, net)
	# Host hit-claim hooks (docs/NETWORK_SECURITY_AND_STEAM.md section 6): line of sight and map bounds.
	net.los_check = _net_los_clear
	net.map_half_extent = _city_half_extent() + NET_MAP_MARGIN
	voice = VoiceScript.new()
	voice.name = "Voice"
	add_child(voice)
	voice.setup(net, sfx)
	net.voice_space = func(at: Vector3) -> int:
		var building: Node3D = _building_at(at)
		return -1 if building == null else building.get_instance_id()
	net.voice_doors = func() -> Array:
		var open_doors: Array = []
		if is_instance_valid(world):
			for door: Dictionary in world.interactable_doors:
				if bool(door.get("open", false)) and door.get("position") is Vector3:
					open_doors.append(door["position"])
		return open_doors
	# The host routes every voice frame: only the open doorways next to the talker matter (grid lookup).
	net.voice_doors_near = _open_doors_near
	voice.phone_locator = online.phone_voice_position
	_load_settings()
	_apply_crew()
	_show_title()
	if "--capture" in OS.get_cmdline_user_args():
		_capture_views.call_deferred()
	# `Fast Talkers.exe -- --solo-week` jumps straight into SOLO WEEK (exe smoke tests, quick demos).
	elif "--solo-week" in OS.get_cmdline_user_args():
		online.start_solo_week.call_deferred()

func _add_car(at: Vector3, yaw: float, paint: Color, title: String, stripe: Color, type: String = "sedan") -> FastCar:
	var ride: FastCar = CarScript.new()
	ride.vehicle_type = type
	ride.paint_color = paint
	ride.stripe_color = stripe
	ride.model_name = title if not title.is_empty() else str(CarScript.TYPES.get(type, CarScript.TYPES["sedan"])["label"])
	ride.position = at
	ride.rotation.y = yaw
	ride.spawn_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	add_child(ride)
	ride.crashed.connect(_on_car_crashed.bind(ride))
	ride.wrecked.connect(_on_vehicle_wrecked.bind(ride))
	ride.glass_broken.connect(_on_car_glass_broken.bind(ride))
	cars.append(ride)
	return ride

## Title-screen lineup: one representative of each crew under the Exchange neon.
func _build_lineup() -> void:
	for index: int in range(Factions.ORDER.size()):
		var model: CharacterModel = CharacterModel.new()
		add_child(model)
		model.build(Factions.ORDER[index], false)
		model.rotation.y = PI + 0.32 - index * 0.16
		lineup.append(model)

## Applies the player's crew: viewmodel wardrobe, HUD accent, rival outfits on practice bots.
func _apply_crew() -> void:
	var identity: Dictionary = Factions.get_crew(crew)
	player.set_outfit(identity["sleeve"], identity["glove"])
	avatar.build(crew, false)
	# Contracts start and end at the crew's own HQ: the case must be carried home.
	var base: Dictionary = world.crew_spawns.get(crew, {})
	if not base.is_empty():
		HOME = base["hq"]
		HOME.y = 0.0
		# New map data places the player on the real doorway approach. Older world
		# files still have a usable fallback while the 0.5 map is integrated.
		var outward: Vector3 = base.get("door", -HOME)
		outward.y = 0.0
		outward = outward.normalized()
		hq_yaw = float(base.get("spawn_yaw", atan2(-outward.x, -outward.z)))
		hq_spawn = base.get("spawn", HOME + outward * 2.5 + Vector3(0, 0.3, 0))
	for guard: FastGuard in guards:
		guard.set_crew(Factions.next_id(crew, 1))
	for guard: FastGuard in drill_guards:
		guard.set_crew(Factions.next_id(crew, 2))
	if is_instance_valid(accent_bar):
		accent_bar.color = identity["color"]
	for index: int in range(lineup.size()):
		var forward: float = 0.7 if Factions.ORDER[index] == crew else 0.0
		lineup[index].position = Vector3(0.6 + index * 1.4, 0.03, -41.2 + forward)

func _spawn_guard(pos: Vector3) -> FastGuard:
	var guard: FastGuard = GuardScript.new()
	guard.position = pos
	guard.rotation.y = PI
	guard.target = player
	add_child(guard)
	guard.eliminated.connect(_guard_eliminated.bind(guard))
	return guard

func _all_guards() -> Array[FastGuard]:
	var all: Array[FastGuard] = []
	all.append_array(guards)
	all.append_array(drill_guards)
	return all

## Margin (metres) added around the city when narrowing the host's snapshot bounds.
const NET_MAP_MARGIN: float = 200.0

## Largest |x| or |z| of any land polygon or road point, at least the city limit `FastWorld.HALF`.
func _city_half_extent() -> float:
	var extent: float = FastWorld.HALF
	if not is_instance_valid(world):
		return extent
	for polygon: PackedVector2Array in world.land:
		for point: Vector2 in polygon:
			extent = maxf(extent, maxf(absf(point.x), absf(point.y)))
	for road: Dictionary in world.roads:
		for point: Vector2 in road["points"]:
			extent = maxf(extent, maxf(absf(point.x), absf(point.y)))
	return extent

## Host hit-claim line of sight (`net.los_check`): true when nothing in the world blocks a -> b. Players
## (layers 2, 4, 8) are off the mask; cars and shop glass share the world layer, so they are excluded by
## body. The far end is pulled back 0.3 m so the target's own cover lip or surface never blocks a real hit.
func _net_los_clear(from: Vector3, to: Vector3) -> bool:
	var span: Vector3 = to - from
	var length: float = span.length()
	if length < 0.5:
		return true
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to - span / length * 0.3, 1)
	var skip: Array[RID] = [player.get_rid()]
	for ride: FastCar in cars:
		if is_instance_valid(ride):
			skip.append(ride.get_rid())
	if is_instance_valid(world):
		for glass: Dictionary in world.glass_panes:
			var pane: CollisionObject3D = glass["body"] as CollisionObject3D
			if is_instance_valid(pane):
				skip.append(pane.get_rid())
	query.exclude = skip
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _setup_input() -> void:
	var keys: Dictionary = {"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"sprint":KEY_SHIFT,"crouch":KEY_CTRL,"jump":KEY_SPACE,"handbrake":KEY_SPACE,"reload":KEY_R,"interact":KEY_E,"buy":KEY_B,"escape":KEY_ESCAPE,"drop":KEY_G,
		"weapon_1":KEY_1,"weapon_2":KEY_2,"weapon_3":KEY_3,"weapon_4":KEY_4,"weapon_5":KEY_5,"quick_swap":KEY_Q,"horn":KEY_H,"rearm":KEY_T,"fullscreen":KEY_F11,"fps":KEY_F3,
		"map":KEY_M,"gunsmith":KEY_B,"seat":KEY_F,"camera_toggle":KEY_V,"chat":KEY_ENTER,
		"hands_up":KEY_X,"binoculars":KEY_Z,"voice_radio":KEY_Y,"voice_ptt":KEY_N,"drop_phone":KEY_K,"phone_call":KEY_P}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = keys[action]
		InputMap.action_add_event(action, key)
	InputMap.action_add_event("crouch", _key(KEY_C))
	InputMap.action_add_event("chat", _key(KEY_KP_ENTER))
	InputMap.action_add_event("chat", _key(KEY_T))
	var buttons: Dictionary = {"fire":MOUSE_BUTTON_LEFT,"aim":MOUSE_BUTTON_RIGHT,"weapon_prev":MOUSE_BUTTON_WHEEL_UP,"weapon_next":MOUSE_BUTTON_WHEEL_DOWN,
		"driveby_aim":MOUSE_BUTTON_RIGHT,"driveby_fire":MOUSE_BUTTON_LEFT}
	for action: String in buttons:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var button := InputEventMouseButton.new()
		button.button_index = buttons[action]
		InputMap.action_add_event(action, button)
	_setup_gamepad()

## Gamepad bindings (XInput/SDL layout; Steam Input maps other pads onto this).
## Left-stick actions are separate from WASD so the stick steers a car without
## also throttling it; triggers drive and shoot. While driving, LB aims out of the
## window and RB fires, so the triggers stay on the throttle and brake.
func _setup_gamepad() -> void:
	var axes: Dictionary = {
		"stick_left": [JOY_AXIS_LEFT_X, -1.0], "stick_right": [JOY_AXIS_LEFT_X, 1.0],
		"stick_up": [JOY_AXIS_LEFT_Y, -1.0], "stick_down": [JOY_AXIS_LEFT_Y, 1.0],
		"look_left": [JOY_AXIS_RIGHT_X, -1.0], "look_right": [JOY_AXIS_RIGHT_X, 1.0],
		"look_up": [JOY_AXIS_RIGHT_Y, -1.0], "look_down": [JOY_AXIS_RIGHT_Y, 1.0],
		"fire": [JOY_AXIS_TRIGGER_RIGHT, 1.0], "aim": [JOY_AXIS_TRIGGER_LEFT, 1.0],
		"pad_throttle": [JOY_AXIS_TRIGGER_RIGHT, 1.0], "pad_brake": [JOY_AXIS_TRIGGER_LEFT, 1.0],
	}
	for action: String in axes:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		var motion := InputEventJoypadMotion.new()
		motion.axis = axes[action][0]
		motion.axis_value = axes[action][1]
		InputMap.action_add_event(action, motion)
	var pad_buttons: Dictionary = {
		"jump": [JOY_BUTTON_A], "handbrake": [JOY_BUTTON_A], "crouch": [JOY_BUTTON_B],
		"reload": [JOY_BUTTON_X], "interact": [JOY_BUTTON_Y], "weapon_next": [JOY_BUTTON_RIGHT_SHOULDER],
		"weapon_prev": [JOY_BUTTON_LEFT_SHOULDER], "horn": [JOY_BUTTON_LEFT_STICK], "quick_swap": [JOY_BUTTON_DPAD_UP],
		"drop": [JOY_BUTTON_DPAD_DOWN], "gunsmith": [JOY_BUTTON_DPAD_RIGHT], "buy": [JOY_BUTTON_DPAD_LEFT], "rearm": [JOY_BUTTON_DPAD_LEFT],
		"seat": [JOY_BUTTON_DPAD_RIGHT], "driveby_aim": [JOY_BUTTON_LEFT_SHOULDER], "driveby_fire": [JOY_BUTTON_RIGHT_SHOULDER],
		"escape": [JOY_BUTTON_START], "map": [JOY_BUTTON_BACK], "camera_toggle": [JOY_BUTTON_RIGHT_STICK],
		# R3 is only the vehicle camera, so on foot it is free: hands up. Binoculars (hold D-pad up) and the
		# phone drop (hold D-pad down) are timed holds handled in _pad_hold_update, not plain button actions.
		"hands_up": [JOY_BUTTON_RIGHT_STICK],
		# D-pad left is also the shop: online.phone_input only takes the press while you hold a phone
		# (or a call is ringing / live) and you are not at the HQ counter or in the buy phase.
		"phone_call": [JOY_BUTTON_DPAD_LEFT],
	}
	for action: String in pad_buttons:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for index: int in pad_buttons[action]:
			var button := InputEventJoypadButton.new()
			button.button_index = index
			InputMap.action_add_event(action, button)
	# Godot 4's built-in ui_accept / ui_cancel have no joypad buttons, so the D-pad could
	# move menu focus but A never pressed a button and B never went back. Bind them here.
	for pair: Array in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var ui_button := InputEventJoypadButton.new()
		ui_button.button_index = pair[1]
		if not InputMap.action_has_event(pair[0], ui_button):
			InputMap.action_add_event(pair[0], ui_button)

## Tracks the last device used so prompts can switch live between keyboard and pad.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.45):
		if not using_pad:
			using_pad = true
		pad_device = event.device
		var pad_name: String = Input.get_joy_name(event.device).to_lower()
		pad_is_playstation = pad_name.contains("ps") or pad_name.contains("dualsense") or pad_name.contains("dualshock") or pad_name.contains("sony")
	elif event is InputEventKey or event is InputEventMouseButton or (event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 6.0):
		using_pad = false

const GLYPHS: Dictionary = {
	"interact": ["E", "Y", "TRIANGLE"], "reload": ["R", "X", "SQUARE"], "fire": ["LMB", "RT", "R2"],
	"aim": ["RMB", "LT", "L2"], "jump": ["SPACE", "A", "CROSS"], "crouch": ["CTRL", "B", "CIRCLE"],
	"sprint": ["SHIFT", "L3", "L3"], "map": ["M", "VIEW", "CREATE"], "escape": ["ESC", "MENU", "OPTIONS"],
	"gunsmith": ["B", "D-PAD RIGHT", "D-PAD RIGHT"], "buy": ["B", "D-PAD LEFT", "D-PAD LEFT"], "rearm": ["T", "D-PAD LEFT", "D-PAD LEFT"],
	"tabs": ["1-7", "LB / RB", "L1 / R1"], "back": ["ESC", "B", "CIRCLE"], "accept": ["CLICK", "A", "CROSS"],
	"drop": ["G", "D-PAD DOWN", "D-PAD DOWN"], "horn": ["H", "L3", "L3"], "quick_swap": ["Q", "D-PAD UP", "D-PAD UP"],
	"weapons": ["1-5", "LB / RB", "L1 / R1"], "handbrake": ["SPACE", "A", "CROSS"],
	"drive": ["W / S", "RT / LT", "R2 / L2"], "steer": ["A / D", "L-STICK", "L-STICK"], "look": ["MOUSE", "R-STICK", "R-STICK"],
	"seat": ["F", "D-PAD RIGHT", "D-PAD RIGHT"], "camera_toggle": ["V", "R3", "R3"], "hands_up": ["X", "R3", "R3"],
	"binoculars": ["Z", "HOLD D-PAD UP", "HOLD D-PAD UP"], "drop_phone": ["K", "HOLD D-PAD DOWN", "HOLD D-PAD DOWN"], "phone_call": ["P", "D-PAD LEFT", "D-PAD LEFT"], "driveby_aim": ["HOLD RMB", "HOLD LB", "HOLD L1"], "driveby_fire": ["LMB", "RB", "R1"],
}

## Prompt name for an action on the device the player is using right now.
func _glyph(action: String) -> String:
	var names: Array = GLYPHS.get(action, [action.to_upper(), action.to_upper(), action.to_upper()])
	if not using_pad:
		return str(names[0])
	return str(names[2]) if pad_is_playstation else str(names[1])

func _rumble(weak: float, strong: float, seconds: float) -> void:
	if vibration and using_pad:
		Input.start_joy_vibration(pad_device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), seconds)

func _key(code: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.physical_keycode = code
	return key

func _process(delta: float) -> void:
	online.tick(delta)
	if phase == Phase.MENU:
		_orbit_title(delta)
		for model: Node3D in lineup:
			(model as CharacterModel).animate(delta, Vector3.ZERO, false)
	if phase == Phase.BUY and not paused:
		buy_time_left = online.time_left if online.active else buy_time_left - delta
		# Doors are locked: the player can look around and walk the HQ yard, nothing more.
		var offset: Vector3 = player.global_position - hq_spawn
		offset.y = 0.0
		if offset.length() > HQ_YARD:
			var held: Vector3 = hq_spawn + offset.normalized() * HQ_YARD
			player.global_position = Vector3(held.x, player.global_position.y, held.z)
		if is_instance_valid(buy_status):
			_update_buy_status()
		if buy_time_left <= 0.0 and not online.active:
			_start_live()
	if phase == Phase.LIVE and not paused:
		if online.active:
			time_left = online.time_left
		elif not free_roam:
			time_left -= delta
			_tick_tip(delta)
			if time_left <= 0.0:
				_finish(false, "Time is money", "The collection window closed before delivery.")
		if player.position.y < -20.0:
			if free_roam: _respawn()
			else: player.take_damage(1000.0)
		for ride: FastCar in cars:
			if ride.position.y < -20.0:
				if ride == vehicle:
					_exit_vehicle(true)
				_clear_vehicle(ride)
				ride.reset_to_spawn()
		if respawn_timer > 0.0:
			respawn_timer -= delta
			if respawn_timer <= 0.0:
				_respawn()
		_tick_guard_respawns(delta)
		_update_driveby()
		_update_gps(delta)
		_update_ambient_events(delta)
	_pad_hold_update()
	player.binoculars = (phase == Phase.LIVE or phase == Phase.BUY) and not paused and not player.is_dead() \
		and (vehicle == null or not _driving()) and InputMap.has_action("binoculars") and (Input.is_action_pressed("binoculars") or _pad_binoculars)
	# Offline: the briefcase is the trade item, so only the sidearm works while it is carried. Online, the
	# match layer (online.gd) drives this from the items the player really holds.
	if not online.active and player.sidearm_only != carrying:
		player.set_sidearm_only(carrying)
	_update_space(delta)
	if vehicle != null and phase != Phase.MENU:
		_update_seat_modifiers()
		_update_vehicle_camera(delta)
	_update_avatar(delta)
	_update_wheelmen(delta)
	_focus_menu()
	msg_timer = maxf(0.0,msg_timer-delta)
	hit_timer = maxf(0.0,hit_timer-delta)
	damage_flash = maxf(0.0, damage_flash - delta * 1.6)
	for index: int in range(damage_marks.size() - 1, -1, -1):
		damage_marks[index]["life"] = float(damage_marks[index]["life"]) - delta
		if float(damage_marks[index]["life"]) <= 0.0:
			damage_marks.remove_at(index)
	if msg_timer == 0.0:
		feed_label.text = ""
	_update_vehicle_audio(delta)
	_update_laser()
	_update_steam(delta)
	_update_hud()
	overlay.queue_redraw()
	mini_map.queue_redraw()
	full_map.visible = map_open and phase == Phase.LIVE and not paused
	if full_map.visible:
		full_map.queue_redraw()

func _exit_tree() -> void:
	# Stop looping voices so shutdown never leaves a playback holding its stream.
	_stop_loops()
	if is_instance_valid(ambience_player):
		ambience_player.stop()
	if is_instance_valid(_interior_bed_player):
		_interior_bed_player.stop()

## Pad users get a focused button whenever a menu is open, so D-pad/stick and A work.
func _focus_menu() -> void:
	if not menu.visible or not using_pad:
		return
	var owner: Control = get_viewport().gui_get_focus_owner()
	if owner != null and menu.is_ancestor_of(owner):
		return
	var first: Button = _first_button(menu_stack)
	if first != null:
		first.grab_focus()

func _first_button(parent: Node) -> Button:
	for child: Node in parent.get_children():
		if child is Button and not (child as Button).disabled:
			return child as Button
		if child is Container:
			var inner: Button = _first_button(child)
			if inner != null:
				return inner
	return null

func _notification(what: int) -> void:
	# Losing window focus mid-contract opens the pause menu instead of leaving the game running blind.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_on_focus_loss and (phase == Phase.LIVE or phase == Phase.BUY) and not paused and is_instance_valid(menu):
		_pause()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and not event.pressed:
		_pad_hold_release((event as InputEventJoypadButton).button_index)
	if online.is_typing():
		return
	# P (D-pad left) works the crew phone: dial, answer, hang up. While the dial strip is open it also takes 1-4, ESC.
	if online.active and (phase == Phase.LIVE or phase == Phase.BUY) and not paused and not buy_menu_open and online.phone_input(event):
		get_viewport().set_input_as_handled()
		return
	if online.active and event.is_action_pressed("chat") and (phase == Phase.LIVE or phase == Phase.BUY) and not paused:
		online.open_chat()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.is_action_pressed("ui_cancel") and menu.visible and _menu_back.is_valid():
		_menu_back.call()
		return
	if event.is_action_pressed("map") and phase == Phase.LIVE and not paused:
		map_open = not map_open
		return
	# R3 is also the vehicle camera, and hands cannot go up in a seat, so the pad press is left for that.
	if event.is_action_pressed("hands_up") and (phase == Phase.LIVE or phase == Phase.BUY) and not paused \
			and not (vehicle != null and event is InputEventJoypadButton):
		toggle_hands_up()
		return
	if event.is_action_pressed("fullscreen"):
		_toggle_fullscreen()
		return
	if event.is_action_pressed("fps"):
		show_fps = not show_fps
		_save_settings()
		return
	if event.is_action_pressed("escape"):
		if phase == Phase.LIVE or phase == Phase.BUY:
			if buy_menu_open: _close_buy_menu()
			elif paused: _resume()
			else: _pause()
		return
	if phase == Phase.BUY and not paused:
		_buy_phase_input(event)
		return
	if phase != Phase.LIVE or paused:
		return
	# Shop is D-pad left and seats are D-pad right, so a rider can change seats
	# without opening the contract-mode shop.
	if not free_roam and vehicle == null and event.is_action_pressed("buy"):
		if buy_menu_open:
			_close_buy_menu()
		elif _at_buy_station():
			_open_buy_menu()
		else:
			_message("Visit your HQ supply counter to buy equipment.")
		return
	if buy_menu_open:
		_buy_phase_input(event)
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventJoypadButton and event.is_action_pressed("quick_swap") and not player.is_dead():
		_pad_hold_begin(JOY_BUTTON_DPAD_UP)
	if vehicle != null:
		if _driving():
			if event.is_action_pressed("horn"):
				horn_player.volume_db = sfx.call("master_db", -4.0)
				horn_player.play()
			elif event.is_action_released("horn"):
				horn_player.stop()
		if event.is_action_pressed("interact"):
			_interact()
			return
		if event.is_action_pressed("seat"):
			_swap_seat()
			return
		if event.is_action_pressed("camera_toggle"):
			drive_third_person = not drive_third_person
			_save_settings()
			_message("Vehicle camera: %s. %s to switch." % ["third person" if drive_third_person else "first person", _glyph("camera_toggle")], 2.0)
			return
		if not player.seat_can_shoot or player.is_dead():
			return
		_weapon_keys(event, driveby)
		return
	if event.is_action_pressed("interact"):
		_interact()
		return
	if event.is_action_pressed("seat"):
		var ride: FastCar = _nearest_car(CENTRE_REACH)
		if ride != null:
			_ride(ride)
			return
	if event.is_action_pressed("drop"):
		if event is InputEventJoypadButton:
			# The pad's D-pad down is tap = drop the trade item (on release), hold = drop the phone.
			_pad_hold_begin(JOY_BUTTON_DPAD_DOWN)
		elif _drop_trade_item():
			return
	if event.is_action_pressed("drop_phone"):
		_drop_phone()
	if player.is_dead():
		return
	_weapon_keys(event, false)
	if event.is_action_pressed("quick_swap") and not (event is InputEventJoypadButton):
		player.quick_swap()
	if event.is_action_pressed("gunsmith") and free_roam:
		_gunsmith()
		return
	if event.is_action_pressed("rearm") and free_roam:
		_rearm()

## G / D-pad down tap: drops the trade item at your feet. Online, the match layer owns the items and
## returns true when it handled the drop; offline, the contract briefcase goes on the ground.
func _drop_trade_item() -> bool:
	if online.drop():
		return true
	if carrying:
		carrying = false
		case_mesh.position = player.position - player.global_basis.z * 1.2
		case_mesh.position.y = 0.5
		case_mesh.visible = true
		_message("Briefcase dropped. %s to collect it again." % _glyph("interact"))
	return false

## K / hold D-pad down: drops the crew phone. There is no phone offline, so this only exists online.
func _drop_phone() -> void:
	if online.active and online.has_method("drop_phone"):
		online.call("drop_phone")

## Starts timing a D-pad press (see `PAD_HOLD_SECONDS`).
func _pad_hold_begin(button: int) -> void:
	_pad_hold_start[button] = Time.get_ticks_msec()
	_pad_hold_fired[button] = false

## A D-pad release: a press that never reached the hold time counts as the tap.
func _pad_hold_release(button: int) -> void:
	if not _pad_hold_start.has(button):
		return
	var fired: bool = bool(_pad_hold_fired.get(button, false))
	_pad_hold_start.erase(button)
	_pad_hold_fired.erase(button)
	if button == JOY_BUTTON_DPAD_UP:
		_pad_binoculars = false
	if fired or phase != Phase.LIVE or paused or vehicle != null or player.is_dead():
		return
	if button == JOY_BUTTON_DPAD_DOWN:
		_drop_trade_item()
	elif button == JOY_BUTTON_DPAD_UP:
		player.quick_swap()

## Fires the hold action of any D-pad press that has been down for `PAD_HOLD_SECONDS`.
func _pad_hold_update() -> void:
	if _pad_hold_start.is_empty():
		return
	if (phase != Phase.LIVE and phase != Phase.BUY) or paused:
		_pad_hold_start.clear()
		_pad_hold_fired.clear()
		_pad_binoculars = false
		return
	for button: int in _pad_hold_start.keys():
		if bool(_pad_hold_fired.get(button, false)):
			continue
		if float(Time.get_ticks_msec() - int(_pad_hold_start[button])) < PAD_HOLD_SECONDS * 1000.0:
			continue
		_pad_hold_fired[button] = true
		if button == JOY_BUTTON_DPAD_DOWN:
			_drop_phone()
		elif button == JOY_BUTTON_DPAD_UP:
			_pad_binoculars = true

## Number keys pick a weapon class; in free roam, pressing the key of the class in hand
## steps through that class's models (P9 → .45 → .357, M4 → KV-47, ...).
func _weapon_keys(event: InputEvent, locked_wheel: bool) -> void:
	for slot: int in range(FastPlayer.SLOT_ORDER.size()):
		if event.is_action_pressed("weapon_%d" % (slot + 1)):
			var weapon_class: String = FastPlayer.SLOT_ORDER[slot]
			var have: String = player.owned_in_class(weapon_class)
			if free_roam and have != "" and have == player.weapon_id and not player.in_vehicle:
				var variants: Array = FastPlayer.VARIANTS[weapon_class]
				var next: String = str(variants[(variants.find(have) + 1) % variants.size()])
				player.replace_in_class(next)
				_message("%s  /  %s. Press %d again for the next %s." % [FastPlayer.WEAPONS[next]["name"], FastPlayer.WEAPONS[next]["pattern"], slot + 1, str(FastPlayer.CLASS_LABEL[weapon_class]).to_lower()], 4.0)
			elif have.is_empty():
				_message("No %s in your loadout%s." % [str(FastPlayer.CLASS_LABEL[weapon_class]).to_lower(), "" if free_roam else " this round"])
			elif player.sidearm_only and FastPlayer.is_primary(have):
				_message("Hands full: only your sidearm while you carry the trade item. %s drops it." % _glyph("drop"))
			elif not player.switch_weapon(have) and player.in_vehicle and not player.can_use(have):
				_message("Only one-handed guns from this seat: pistols, the MAC-11 or the sawn-off.")
	if locked_wheel:
		return
	if event.is_action_pressed("weapon_next"):
		player.cycle_weapon(1)
	elif event.is_action_pressed("weapon_prev"):
		player.cycle_weapon(-1)

func _interact() -> void:
	if vehicle != null:
		# A practice wheelman pulls over when asked; then the door opens.
		if seat != 0 and vehicle.autopilot and absf(vehicle.speed_kph) > 8.0:
			vehicle.autopilot_speed = 0.0
			_message("The wheelman pulls over. %s again to get out." % _glyph("interact"), 3.0)
			return
		_exit_vehicle()
		return
	if online.active and online.interact():
		return
	if not free_roam and not online.active:
		if _tip_interact():
			return
		if carrying and _flat_distance(player.position,HOME) < 4.5:
			_finish(true,"Deal closed", "Delivered the briefcase to your HQ. Contract revenue: $2,600.")
			return
		if not carrying and case_mesh.visible and player.position.distance_to(case_mesh.position) < 3.1:
			if not paid and not violence:
				_open_deal()
			else:
				_collect_case()
			return
	if _near_rack():
		if free_roam:
			_rearm()
		else:
			sfx.play("deny")
			_message("The armory only resupplies in Free Roam. Buy equipment in the buy phase.")
		return
	var shop_door: int = _shop_door_in_reach()
	if shop_door >= 0:
		world.toggle_door(shop_door)
		online.door_changed(shop_door)
		sfx.play("ui", 0.6)
		return
	var nearest: FastCar = _nearest_car(CENTRE_REACH)
	if nearest != null:
		var index: int = 0 if nearest.seat_free(0) else nearest.nearest_free_seat(player.global_position)
		if index < 0:
			_message("The %s is full." % nearest.model_name.to_lower())
			return
		_enter_vehicle(nearest, index)

## The walk-in shop door the player can reach (-1 if none, or if a car door is nearer).
func _shop_door_in_reach() -> int:
	var index: int = world.door_near(player.global_position, SHOP_DOOR_REACH)
	if index < 0:
		return -1
	var door_distance: float = _flat_distance(player.global_position, world.interactable_doors[index]["position"])
	for ride: FastCar in cars:
		for seat_index: int in range(ride.seat_count()):
			if player.position.distance_to(ride.door_position(seat_index)) < door_distance:
				return -1
	return index

## Nearest vehicle whose centre is within `radius` or whose nearest door is within reach.
func _nearest_car(radius: float) -> FastCar:
	var best: FastCar = null
	var best_distance: float = INF
	for ride: FastCar in cars:
		var distance: float = player.position.distance_to(ride.position)
		var reach: bool = distance < radius
		for index: int in range(ride.seat_count()):
			var door: float = player.position.distance_to(ride.door_position(index))
			if door < DOOR_REACH:
				reach = true
				distance = minf(distance, door)
		if reach and distance < best_distance:
			best = ride
			best_distance = distance
	return best

# --- Vehicles and seats ---------------------------------------------------------------

func _driving() -> bool:
	return vehicle != null and seat == 0

func _ride(target: FastCar) -> void:
	var index: int = target.nearest_free_seat(player.global_position, true)
	if index < 0:
		_message("No passenger seat free.")
		return
	_enter_vehicle(target, index)

func _enter_vehicle(target: FastCar, index: int) -> void:
	if target == null or not target.seat_free(index) or player.is_dead():
		return
	# Online the host hands out seats; we get in when it says so (FastOnline._on_seat_update).
	if online.active and not online.seat_granted(target, index):
		online.request_seat(target, index)
		return
	vehicle = target
	seat = index
	car = target
	driveby = false
	target.occupants[index] = "player"
	target.wake()
	player.add_collision_exception_with(target)
	target.add_collision_exception_with(player)
	if index == 0:
		target.occupied = true
		target.stop_autopilot()
	_apply_seat_mode()
	_chase_yaw = 0.0
	_chase_pitch = 0.0
	_chase_idle = 10.0
	chase.fov = 70.0
	chase.position = target.position + target.global_basis.z * float(target.spec.get("chase", 7.2)) + Vector3(0, 4, 0)
	sfx.play("car_door_close")
	if index == 0 and not target.is_bike():
		sfx.play("engine_start", 1.0, -4.0)
	if index != 0 and free_roam and target.seat_free(0):
		_start_wheelman(target)
	if target.disabled:
		_message("This one is wrecked: the engine will not turn over.", 3.0)

## Seat state for the player: driver, window gunner, or open gunner (pickup bed,
## pillion). Every camera can turn freely; the seat's window opens while firing.
func _apply_seat_mode() -> void:
	if vehicle == null:
		return
	var info: Dictionary = vehicle.seat_info(seat)
	var shoot: String = str(info["shoot"])
	# The driver's, passengers' and pillion rider's cameras can all rotate freely.
	# Solid bodywork determines which directions actually permit a shot.
	var arc: Vector2 = Vector2(0.0, PI)
	var pitch_limits: Vector2 = Vector2(-1.25, 1.25)
	player.seat_vehicle = vehicle
	player.seat_eye_local = info["eye"]
	var pane: int = int(info.get("pane", -1))
	if seat == 0:
		if driveby:
			# The camera stays at the driver's eye so looking around remains continuous.
			player.enter_seat(true, true, true, arc, pitch_limits)
			player.allow_ads = false
			player.fire_action = "driveby_fire"
			player.camera.make_current()
		else:
			player.enter_seat(true, false, true, arc, pitch_limits)
			player.allow_ads = true
			player.fire_action = "fire"
			player.camera.make_current()
		vehicle.set_window_open(pane, driveby)
	else:
		player.enter_seat(true, shoot != "none", false, arc, pitch_limits, float(info.get("blocked", 0.0)))
		player.allow_ads = true
		player.fire_action = "fire"
		player.camera.make_current()
		vehicle.set_window_open(pane, true)
	player.set_body_collision(true)
	player.input_grace = 0.1

func _exit_vehicle(force: bool = false) -> bool:
	if vehicle == null:
		return false
	var leaving: FastCar = vehicle
	if not force and absf(leaving.speed_kph) > 8.0:
		_message("Slow below 8 km/h before getting out.")
		return false
	var exit_pos: Vector3 = leaving.door_position(seat)
	if not force and _blocked(exit_pos, leaving):
		_message("Door is blocked. %s to move seats, or reposition." % _glyph("seat"))
		return false
	var info: Dictionary = leaving.seat_info(seat)
	leaving.set_window_open(int(info.get("pane", -1)), false)
	leaving.occupants[seat] = ""
	online.leave_seat(leaving, seat)
	if seat == 0:
		leaving.occupied = false
	player.remove_collision_exception_with(leaving)
	leaving.remove_collision_exception_with(player)
	vehicle = null
	seat = -1
	driveby = false
	player.hold_fire = false
	avatar.visible = false
	player.leave_seat()
	player.position = exit_pos
	player.face(leaving.rotation.y)
	player.camera.make_current()
	horn_player.stop()
	sfx.play("car_door_open")
	_dismiss_wheelman(leaving)
	return true

func _blocked(at: Vector3, ignore: FastCar) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.36
	shape.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.9, 0))
	query.exclude = [ignore.get_rid(), player.get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(query).is_empty()

func _swap_seat() -> void:
	if vehicle == null:
		return
	var next: int = vehicle.next_free_seat(seat)
	if next < 0:
		_message("No free seat to move to.")
		return
	if online.active:
		online.request_seat(vehicle, next)
		return
	_swap_to_seat(next)

## Moves the player to another seat of the vehicle they are in.
func _swap_to_seat(next: int) -> void:
	var info: Dictionary = vehicle.seat_info(seat)
	vehicle.set_window_open(int(info.get("pane", -1)), false)
	vehicle.occupants[seat] = ""
	if seat == 0:
		vehicle.occupied = false
	seat = next
	vehicle.occupants[seat] = "player"
	driveby = false
	if seat == 0:
		vehicle.occupied = true
		vehicle.stop_autopilot()
	_apply_seat_mode()
	sfx.play("draw", 0.8)
	_message(str(vehicle.seat_info(seat)["name"]), 1.5)
	if seat != 0 and free_roam and vehicle.seat_free(0):
		_start_wheelman(vehicle)

## Hold RMB (or LB) at the wheel to enable one-handed firing; looking stays free.
func _update_driveby() -> void:
	if not _driving() or player.is_dead():
		return
	var info: Dictionary = vehicle.seat_info(0)
	var wants: bool = str(info["shoot"]) == "driveby" and Input.is_action_pressed("driveby_aim")
	if wants == driveby:
		return
	if wants and player.ordered_owned().filter(func(id: String) -> bool: return FastPlayer.is_one_hand(id)).is_empty():
		return
	driveby = wants
	_apply_seat_mode()

## Moving vehicles cost accuracy: gunners pay for speed, drivers pay for steering too.
func _update_seat_modifiers() -> void:
	var speed: float = clampf(absf(vehicle.speed_kph) / 100.0, 0.0, 1.0)
	if seat == 0:
		player.spread_scale = 1.6 + speed * 0.6
	else:
		player.spread_scale = 1.0 + speed * (0.5 if str(vehicle.seat_info(seat)["shoot"]) == "window" else 0.8)

## The local first-person camera sits at eye level; drawing a second full head here
## would put the camera inside its face. Remote avatars are a multiplayer task.
func _update_avatar(delta: float) -> void:
	# In the third-person vehicle view the player's own character sits in the seat.
	var show: bool = vehicle != null and chase.current and phase != Phase.MENU
	avatar.visible = show
	if not show:
		return
	avatar.seated = true
	avatar.riding = vehicle.is_bike()
	var eye: Vector3 = vehicle.seat_info(seat)["eye"]
	avatar.global_transform = vehicle.global_transform * Transform3D(Basis.IDENTITY, eye - Vector3(0, avatar.eye_height(), 0))
	avatar.animate(delta, Vector3.ZERO, false)

## Third person is used when chosen, except while aiming, doing a drive-by or dead.
func _third_person_active() -> bool:
	if not drive_third_person or vehicle == null or phase == Phase.MENU or player.is_dead() or driveby:
		return false
	return not (seat != 0 and player.seat_can_shoot and Input.is_action_pressed("aim"))

func _update_vehicle_camera(delta: float) -> void:
	var third: bool = _third_person_active()
	player.hold_fire = third
	if not third:
		if chase.current:
			player.camera.make_current()
		return
	var snap: bool = not chase.current
	if snap:
		chase.make_current()
		chase.fov = fov_setting * 0.85
		_tp_heading = vehicle.global_rotation.y + player.seat_yaw
		_tp_distance = float(vehicle.spec.get("chase", 7.2))
	_update_third_person(delta, snap)

## Chase camera placed from the car's current transform every frame (no positional lag,
## so no jitter); only its heading and distance are smoothed. Mouse/stick orbit it; let go
## and it swings back behind the car once you are moving.
func _update_third_person(delta: float, snap: bool) -> void:
	var look: Vector2 = Vector2(player.seat_yaw, player.look_pitch())
	_tp_idle = 0.0 if look.distance_to(_tp_last_look) > 0.0005 else _tp_idle + delta
	if _tp_idle > 1.4 and absf(vehicle.longitudinal_speed) > 3.0:
		player.ease_seat_look(0.0, -0.12, 1.0 - exp(-2.4 * delta))
		look = Vector2(player.seat_yaw, player.look_pitch())
	_tp_last_look = look
	var speed_fraction: float = clampf(absf(vehicle.longitudinal_speed) / vehicle.maximum_forward_speed, 0.0, 1.0)
	var target_heading: float = vehicle.global_rotation.y + look.x
	_tp_heading = target_heading if snap else lerp_angle(_tp_heading, target_heading, 1.0 - exp(-9.0 * delta))
	var elevation: float = clampf(0.3 - look.y * 0.9, -0.15, 1.25)
	var focus: Vector3 = vehicle.global_position + Vector3(0, 1.5 if not vehicle.is_bike() else 1.3, 0)
	var want: float = float(vehicle.spec.get("chase", 7.2)) + speed_fraction * 1.6
	var direction: Vector3 = Vector3(sin(_tp_heading) * cos(elevation), sin(elevation), cos(_tp_heading) * cos(elevation))
	var query := PhysicsRayQueryParameters3D.create(focus, focus + direction * (want + 0.4))
	query.exclude = [vehicle.get_rid(), player.get_rid()]
	var obstruction := get_world_3d().direct_space_state.intersect_ray(query)
	if not obstruction.is_empty():
		want = maxf(1.2, focus.distance_to(obstruction.position) - 0.4)
	# Pull in at once for walls, ease back out.
	_tp_distance = want if snap or want < _tp_distance else lerpf(_tp_distance, want, 1.0 - exp(-4.0 * delta))
	chase.global_position = focus + direction * _tp_distance
	chase.look_at(focus + Vector3(0, 0.25, 0))
	chase.fov = lerpf(chase.fov, fov_setting * 0.85 + speed_fraction * 10.0, 1.0 - exp(-3.0 * delta))

## Practice wheelman: a rival-crew practice bot drives a loop so a solo player can test
## shooting from a passenger seat. Offline free roam only; real matches have no AI.
func _start_wheelman(target: FastCar) -> void:
	if not free_roam or not target.seat_free(0) or world.road_loop.size() < 2 or target.disabled:
		return
	target.occupants[0] = "bot"
	var driver: CharacterModel = CharacterModel.new()
	target.add_child(driver)
	driver.build(Factions.next_id(crew, 3), false)
	driver.seated = true
	driver.riding = target.is_bike()
	driver.position = (target.seat_info(0)["eye"] as Vector3) - Vector3(0, driver.eye_height(), 0)
	target.set_meta("wheelman", driver)
	# Along the streets to the downtown ring first, then round and round the ring.
	var lead: PackedVector3Array = world.route(target.global_position, world.road_loop[0])
	var path: PackedVector3Array = lead.duplicate()
	path.append_array(world.road_loop)
	target.start_autopilot(path, 12.5 if not target.is_bike() else 13.5, lead.size())
	_message("A practice wheelman takes the wheel and drives a loop. Shoot from your seat; %s asks him to pull over." % _glyph("interact"), 6.0)

func _dismiss_wheelman(target: FastCar) -> void:
	if target.occupants.size() == 0 or target.occupants[0] != "bot":
		return
	for index: int in range(1, target.occupants.size()):
		if target.occupants[index] == "player":
			return
	target.stop_autopilot()
	target.occupants[0] = ""
	if target.has_meta("wheelman"):
		var driver: Node = target.get_meta("wheelman")
		if is_instance_valid(driver):
			driver.queue_free()
		target.remove_meta("wheelman")

func _clear_vehicle(target: FastCar) -> void:
	_dismiss_wheelman(target)
	target.occupied = false
	target.stop_autopilot()
	for index: int in range(target.occupants.size()):
		target.occupants[index] = ""

func _update_wheelmen(delta: float) -> void:
	for ride: FastCar in cars:
		if ride.has_meta("wheelman"):
			var driver: CharacterModel = ride.get_meta("wheelman") as CharacterModel
			if is_instance_valid(driver):
				driver.animate(delta, Vector3.ZERO, false)

func _flat_distance(a:Vector3,b:Vector3) -> float:
	return Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))

func _near_rack() -> bool:
	return _flat_distance(player.position, ArmoryScript.RACK + Vector3(0, 0, 0.8)) < 2.4

func _collect_case() -> void:
	sfx.play("briefcase_open")
	carrying = true
	case_mesh.visible = false
	_message("Briefcase secured. Get it home to your HQ (teal marker).")

func _open_deal() -> void:
	_lock_controls(true)
	_clear_menu()
	_menu_back = _resume
	_heading("THE EXCHANGE", "A clean deal costs less than a funeral.")
	_text("Broker: Eight hundred for the documents. Cash now.\n\nYou have $%s. Keep your weapon down and we all go home." % _money(cash))
	_button("PAY $800  /  TAKE THE CASE", _pay_deal, cash < DEAL_COST)
	_button("TAKE IT BY FORCE", func():
		violence = true
		_alert_guards()
		_collect_case()
		_resume())
	_button("WALK AWAY", _resume)
	menu.show()

func _pay_deal() -> void:
	if cash < DEAL_COST or paid or phase != Phase.LIVE:
		return
	cash -= DEAL_COST
	paid = true
	sfx.play("cash_riffle")
	sfx.play("cash", 1.0, -4.0)
	_collect_case()
	_resume()

## Contract mode alerts every guard. Free roam only alerts guards near the trouble.
func _alert_guards(near: Vector3 = Vector3.INF) -> void:
	if not free_roam:
		violence = true
	var alerted: bool = false
	for guard: FastGuard in _all_guards():
		if not guard.visible or guard.health <= 0.0:
			continue
		if not free_roam or near == Vector3.INF or guard.global_position.distance_to(near) < 38.0:
			if not guard.hostile:
				alerted = true
			guard.hostile = true
	if not free_roam:
		_message("Deal is hostile. Security is armed.")
	elif alerted:
		_message("Security is hostile. Take cover or fall back to the armory.")

func _guard_eliminated(guard: FastGuard = null) -> void:
	if free_roam:
		if guard != null:
			_guard_respawns[guard] = GUARD_RESPAWN
			_alert_guards(guard.global_position)
		_message("Security down. They regroup in %d seconds." % int(GUARD_RESPAWN))
		return
	_alert_guards()
	_message("Security down. There is no kill bonus; the contract pays.")

func _tick_guard_respawns(delta: float) -> void:
	for guard: Variant in _guard_respawns.keys():
		var remaining: float = float(_guard_respawns[guard]) - delta
		if remaining > 0.0:
			_guard_respawns[guard] = remaining
			continue
		_guard_respawns.erase(guard)
		var typed: FastGuard = guard as FastGuard
		if free_roam and is_instance_valid(typed) and typed.health <= 0.0:
			typed.reset_guard()
			typed.set_present(true)
			typed.active = true

func _reset_world_state() -> void:
	if vehicle != null:
		_exit_vehicle(true)
	for ride: FastCar in cars:
		_clear_vehicle(ride)
		ride.reset_to_spawn()
	car = cars[0]
	for guard: FastGuard in _all_guards():
		guard.reset_guard()
	_guard_respawns.clear()
	armory.call("reset_targets")
	effects.call("clear")
	# Shops reopen; the range follows the selected mode instead of reopening in matches.
	world.reset_glass()
	for door: Dictionary in world.interactable_doors:
		if not world.gun_doors.has(int(door["index"])) and not bool(door["open"]):
			world.set_door_open(int(door["index"]), true)
	_sync_world_mode()
	gps_path = PackedVector3Array()
	_gps_timer = 0.0
	respawn_timer = -1.0
	damage_marks.clear()
	damage_flash = 0.0
	hit_timer = 0.0
	_stop_loops()

## Used by offline and online round resets, and by the title after leaving a match.
func _sync_world_mode() -> void:
	var mode: String = "free_roam" if free_roam else ("online" if online.active else "contract")
	world.set_mode(mode)
	armory.set_mode(mode)

func _hide_title_set() -> void:
	for model: Node3D in lineup:
		model.visible = false

# --- Rounds and the buy phase ---------------------------------------------------------

func _start_round() -> void:
	_hide_title_set()
	free_roam = false
	# CS rules: walk away alive and your guns, parts and armour carry over.
	var keep: bool = _carry_gear and not player.is_dead()
	round_number += 1
	phase = Phase.BUY
	time_left = ROUND_SECONDS
	buy_time_left = BUY_SECONDS
	carrying = false
	violence = false
	paid = false
	purchased.clear()
	buy_mod_target = ""
	_reset_world_state()
	if keep:
		player.revive(hq_spawn)
		player.refill()
	else:
		player.reset_player(hq_spawn)
		player.set_loadout(["pistol"])
		player.armor = 0.0
	player.infinite_reserve = false
	player.regenerate = false
	player.invulnerable = false
	player.can_fire = false
	player.face(hq_yaw)
	player.camera.make_current()
	for guard: FastGuard in guards:
		guard.set_present(true)
	for guard: FastGuard in drill_guards:
		guard.set_present(false)
	case_mesh.position = DEAL + Vector3(0,0.55,0)
	case_mesh.visible = true
	_carry_gear = true
	_reset_tip(randf_range(35.0, 80.0))
	# Doors stay shut: no driving and no security until the phase ends.
	paused = false
	player.enabled = true
	for ride: FastCar in cars:
		ride.enabled = false
		ride.set_physics_process(true)
	for guard: FastGuard in _all_guards():
		guard.active = false
	buy_tab = "rifle" if _current_primary().is_empty() else "mods"
	_show_buy()
	if keep and player.owned.size() > 1:
		_message("You walked away last round: your gear carried over.", 5.0)

func _start_free_roam() -> void:
	_hide_title_set()
	free_roam = true
	phase = Phase.LIVE
	round_number = 0
	time_left = ROUND_SECONDS
	carrying = false
	violence = false
	paid = false
	purchased.clear()
	buy_menu_open = false
	_reset_world_state()
	case_mesh.visible = false
	_reset_tip(-1.0)
	player.reset_player(ArmoryScript.SPAWN)
	player.set_loadout(["pistol", "smg", "shotgun", "marksman", "rifle"])
	player.infinite_reserve = true
	player.regenerate = true
	player.can_fire = true
	player.armor = 100.0
	player.face(-PI * 0.5)
	player.camera.make_current()
	for guard: FastGuard in _all_guards():
		guard.set_present(true)
	shots_fired = 0
	shots_hit = 0
	_resume()
	_message("Welcome to Halcyon Arms, East Shore. Try the range, take a car from the customer lot, or explore Port Halcyon. M opens the city map. Keys 1-5 cycle weapon classes; %s drives, %s rides as a gunner." % [_glyph("interact"), _glyph("seat")], 10.0)

func _rearm() -> void:
	player.refill()
	player.health = 100.0
	player.armor = 100.0
	sfx.play("mag_in")
	sfx.play("cash", 1.3, -6.0)
	_message("Rearmed: every weapon refilled, armor and health restored.")

func _respawn() -> void:
	respawn_timer = -1.0
	if vehicle != null:
		_exit_vehicle(true)
	player.reset_player(ArmoryScript.SPAWN)
	player.face(-PI * 0.5)
	player.refill()
	player.armor = 100.0
	player.camera.make_current()
	for guard: FastGuard in _all_guards():
		if guard.health > 0.0:
			guard.hostile = false
			guard.accuracy_budget = 0.5
	_message("Back at the armory. Security has stood down.")

func _on_player_died() -> void:
	if vehicle != null:
		_exit_vehicle(true)
	if online.active:
		online.on_local_death()
		return
	if free_roam:
		respawn_timer = 2.6
		_message("You were dropped. Respawning at the armory...")
		return
	if tip_state == "carried":
		tip_state = "done"
	_finish(false, "Contract terminated", "You were eliminated. Everything you carried is lost.")

func _show_buy() -> void:
	_open_buy_menu()

func _open_buy_menu() -> void:
	if phase == Phase.LIVE and not _at_buy_station():
		_message("Visit your HQ supply counter to buy equipment.")
		return
	buy_menu_open = true
	_render_buy()
	menu.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _close_buy_menu() -> void:
	buy_menu_open = false
	_clear_menu()
	menu.hide()
	if (phase == Phase.BUY or phase == Phase.LIVE) and not paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		player.input_grace = 0.15

## The round-long counter is physically at your HQ. You have to be on foot to use it.
func _at_buy_station() -> bool:
	return vehicle == null and not player.is_dead() and _flat_distance(player.global_position, HOME) <= BUY_STATION_RADIUS

func _can_buy_now() -> bool:
	return phase == Phase.BUY or (phase == Phase.LIVE and buy_menu_open and _at_buy_station())

func _buy_phase_input(event: InputEvent) -> void:
	if event.is_action_pressed("buy"):
		if buy_menu_open: _close_buy_menu()
		else: _open_buy_menu()
		return
	if buy_menu_open:
		var step: int = 0
		if event.is_action_pressed("weapon_next") and event is InputEventJoypadButton:
			step = 1
		elif event.is_action_pressed("weapon_prev") and event is InputEventJoypadButton:
			step = -1
		for index: int in range(BUY_TABS.size()):
			if index < 5 and event.is_action_pressed("weapon_%d" % (index + 1)):
				buy_tab = BUY_TABS[index]
				_render_buy()
				return
		if step != 0:
			buy_tab = BUY_TABS[(BUY_TABS.find(buy_tab) + step + BUY_TABS.size()) % BUY_TABS.size()]
			_render_buy()
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	# Doors closed: preview and switch weapons, but nothing fires until LIVE.
	_weapon_keys(event, false)

func _current_primary() -> String:
	for id: String in player.owned:
		if FastPlayer.is_primary(id):
			return id
	return ""

func _price(item: String) -> int:
	if item == "armor":
		return ARMOR_PRICE
	if FastPlayer.WEAPONS.has(item):
		return int(FastPlayer.WEAPONS[item]["price"])
	return 0

## Builds the buy menu for the current tab. Rebuilt after every purchase; focus returns
## to the same row so pad users can keep buying.
func _render_buy() -> void:
	var focus_index: int = -1
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	var rows: Array = _buy_rows()
	for index: int in range(rows.size()):
		if rows[index] == focus_owner:
			focus_index = index
	_clear_menu()
	_menu_back = _close_buy_menu
	var identity: Dictionary = Factions.get_crew(crew)
	_heading("BUY PHASE" if phase == Phase.BUY else "HQ SUPPLY COUNTER", "ROUND %02d  /  %s HQ  /  %s" % [round_number, identity["short"], "DOORS LOCKED" if phase == Phase.BUY else "NO REFUNDS"])
	buy_status = _text("", 15, INK)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	for index: int in range(BUY_TABS.size()):
		var tab: String = BUY_TABS[index]
		var tab_button := _small_button(TAB_LABEL[tab], func():
			buy_tab = tab
			_render_buy(), tab == buy_tab)
		tab_button.set_meta("buy_tab", tab)
		tabs.add_child(tab_button)
	menu_stack.add_child(tabs)
	var list: Array[Button] = []
	match buy_tab:
		"gear":
			var armor_label: String = "BODY ARMOR  (75)    $%s" % _money(ARMOR_PRICE)
			if phase == Phase.BUY and purchased.has("armor"):
				armor_label += "    ·    SELL BACK"
			elif player.armor >= 75.0:
				armor_label += "    ·    WORN"
			var armor_button: Button = _button(armor_label, func():
				if phase == Phase.BUY and purchased.has("armor"): _sell("armor")
				else: _purchase("armor", ARMOR_PRICE)
				_render_buy(), (phase != Phase.BUY or not purchased.has("armor")) and (player.armor >= 75.0 or cash < ARMOR_PRICE))
			armor_button.focus_entered.connect(func(): _buy_describe("Absorbs 65% of every hit until it is used up. Carries over if you survive."))
			list.append(armor_button)
		"mods":
			var target: String = buy_mod_target if player.owned.has(buy_mod_target) else (_current_primary() if not _current_primary().is_empty() else player.owned_in_class("pistol"))
			buy_mod_target = target
			var switcher: Button = _button("FITTING:  %s   ⇄" % FastPlayer.WEAPONS[target]["name"], func():
				var carried: Array[String] = player.ordered_owned()
				buy_mod_target = carried[(carried.find(buy_mod_target) + 1) % carried.size()]
				_render_buy(), player.owned.size() < 2)
			list.append(switcher)
			var options: int = 0
			for slot: String in FastPlayer.SLOTS:
				for part_id: String in player.options_for(target, slot):
					options += 1
					var part: Dictionary = FastPlayer.ATTACHMENTS[part_id]
					var key: String = "att:%s:%s" % [target, part_id]
					var fitted: bool = player.attachment(target, slot) == part_id
					var label: String = "%s  /  %s    $%s" % [slot.to_upper(), part["name"], _money(int(part["price"]))]
					if phase == Phase.BUY and purchased.has(key):
						label += "    ·    SELL BACK"
					elif fitted:
						label += "    ·    FITTED"
					var part_button: Button = _button(label, func():
						if phase == Phase.BUY and purchased.has(key): _sell(key)
						else: _purchase_attachment(target, part_id)
						_render_buy(), (phase != Phase.BUY or not purchased.has(key)) and (fitted or cash < int(part["price"])))
					part_button.focus_entered.connect(func(): _buy_describe(_attachment_detail(part_id)))
					part_button.mouse_entered.connect(func(): _buy_describe(_attachment_detail(part_id)))
					list.append(part_button)
			if options == 0:
				_text("The %s takes no attachments." % FastPlayer.WEAPONS[target]["name"], 14, MUTED)
		_:
			for id: String in FastPlayer.VARIANTS[buy_tab]:
				var stats: Dictionary = FastPlayer.WEAPONS[id]
				var price: int = int(stats["price"])
				var owned: bool = player.owned.has(id)
				var label: String = "%s    %s" % [stats["name"], "FREE" if price == 0 else "$" + _money(price)]
				if phase == Phase.BUY and purchased.has(id):
					label += "    ·    SELL BACK"
				elif owned:
					label += "    ·    CARRIED"
				var slot_holder: String = _current_primary() if FastPlayer.is_primary(id) else player.owned_in_class("pistol")
				var refund: int = int(purchased.get(slot_holder, 0)) if phase == Phase.BUY else 0
				var weapon_button: Button = _button(label, func():
					if phase == Phase.BUY and purchased.has(id): _sell(id)
					else: _buy_weapon(id)
					_render_buy(), (phase != Phase.BUY or not purchased.has(id)) and (owned or cash + refund < price))
				weapon_button.focus_entered.connect(func(): _buy_describe(_weapon_detail(id)))
				weapon_button.mouse_entered.connect(func(): _buy_describe(_weapon_detail(id)))
				list.append(weapon_button)
	buy_buttons = list
	buy_detail = _text("", 13, MUTED)
	_button("CLOSE MENU  (%s)" % _glyph("buy"), _close_buy_menu)
	if online.active:
		_text(online.briefing(), 13, GOLD)
	_text("%s tabs   ·   %s buy%s   ·   %s close.\nOne primary and one sidearm. Survive to keep what you carry." % [_glyph("tabs"), _glyph("accept"), " / sell back" if phase == Phase.BUY else " · no refunds after the doors open", _glyph("back")], 12, MUTED)
	_update_buy_status()
	if not list.is_empty():
		_buy_describe(_weapon_detail(FastPlayer.VARIANTS[buy_tab][0]) if FastPlayer.VARIANTS.has(buy_tab) else "")
	var rows_now: Array = _buy_rows()
	if focus_index >= 0 and focus_index < rows_now.size() and using_pad:
		(rows_now[focus_index] as Control).grab_focus.call_deferred()

## Focusable rows in the current buy menu, in order (tabs, items, footer).
func _buy_rows() -> Array:
	var rows: Array = []
	for child: Node in menu_stack.get_children():
		if child is Button:
			rows.append(child)
		elif child is HBoxContainer:
			for inner: Node in child.get_children():
				if inner is Button:
					rows.append(inner)
	return rows

func _buy_describe(text: String) -> void:
	if is_instance_valid(buy_detail):
		buy_detail.text = text

func _weapon_detail(id: String) -> String:
	var stats: Dictionary = FastPlayer.WEAPONS[id]
	var rpm: int = int(round(60.0 / float(stats["interval"])))
	var falloff: Vector3 = stats["falloff"]
	var damage: String = "%d×%d" % [int(stats["pellets"]), int(stats["damage"])] if int(stats["pellets"]) > 1 else str(int(stats["damage"]))
	var traits: PackedStringArray = PackedStringArray()
	if bool(stats.get("one_hand", false)):
		traits.append("ONE-HANDED (drive-by, bike)")
	if bool(stats["automatic"]):
		traits.append("FULL AUTO")
	if bool(stats.get("scope", false)):
		traits.append("SCOPED")
	return "%s  —  %s\n%s\nDAMAGE %s   ·   HEAD ×%.1f   ·   %d RPM   ·   MAG %d   ·   RELOAD %.1fs   ·   FULL DAMAGE TO %dm%s" % [stats["name"], stats["pattern"], stats["desc"], damage, float(stats["headshot"]), rpm, int(stats["capacity"]), float(stats["per_round"]) if float(stats["per_round"]) > 0.0 else float(stats["reload"]), int(falloff.x), ("\n" + "   ·   ".join(traits)) if not traits.is_empty() else ""]

func _attachment_detail(part_id: String) -> String:
	var part: Dictionary = FastPlayer.ATTACHMENTS[part_id]
	var notes: Dictionary = {
		"reflex": "Red-dot sight picture. On the M700 it replaces the scope for close work.",
		"holo2x": "2× magnification; aiming down sights takes 15% longer.",
		"scope4x": "4× scope. Long-range picture, 30% slower to aim.",
		"suppressor": "No muzzle flash or tracer and far quieter. Damage falls off 20% sooner.",
		"compensator": "Vertical recoil −25%. Louder and brighter.",
		"choke": "Pellet spread −35%.",
		"foregrip": "Sideways recoil −40%, hip spread −15%, aiming 5% slower.",
		"laser": "Hip spread −30%. The beam and dot are visible to everyone.",
		"extended": "+50% capacity, reloads 15% slower.",
		"speed": "Reloads 25% faster.",
	}
	return "%s  —  %s slot\n%s" % [part["name"], str(part["slot"]).to_upper(), notes.get(part_id, "")]

func _update_buy_status() -> void:
	if not is_instance_valid(buy_status):
		return
	var loadout: PackedStringArray = PackedStringArray()
	for id: String in player.ordered_owned():
		loadout.append(FastPlayer.short_name(id))
	if phase == Phase.BUY:
		buy_status.text = "CASH  $%s     ·     DOORS OPEN IN  %ds\nCARRYING  %s     ·     ARMOR  %d" % [_money(cash), maxi(0, int(ceil(buy_time_left))), " + ".join(loadout), int(player.armor)]
	else:
		buy_status.text = "CASH  $%s     ·     SUPPLY COUNTER OPEN  /  NO REFUNDS\nCARRYING  %s     ·     ARMOR  %d" % [_money(cash), " + ".join(loadout), int(player.armor)]

func _update_buy() -> void:
	_update_buy_status()

## UI path for weapons: frees the slot first (selling back this round's purchase, or
## leaving a carried gun in the HQ locker), then buys.
func _buy_weapon(id: String) -> bool:
	var price: int = _price(id)
	var holder: String = _current_primary() if FastPlayer.is_primary(id) else player.owned_in_class("pistol")
	var refund: int = int(purchased.get(holder, 0)) if phase == Phase.BUY else 0
	if not _can_buy_now() or cash + refund < price or player.owned.has(id):
		sfx.play("deny")
		return false
	if not holder.is_empty() and holder != id:
		if phase == Phase.BUY and purchased.has(holder):
			_sell(holder)
		elif FastPlayer.is_primary(holder) or (phase == Phase.LIVE and purchased.has(holder)):
			purchased.erase(holder)
			player.drop_weapon(holder)
	return _purchase(id, price)

## Validated like every transaction: phase, funds, one primary, no duplicates.
func _purchase(item: String, cost: int) -> bool:
	if not _can_buy_now() or cash < cost or purchased.has(item):
		sfx.play("deny")
		return false
	if item == "armor":
		if player.armor >= 75.0:
			sfx.play("deny")
			return false
		_armor_before = player.armor
		cash -= cost
		purchased[item] = cost
		player.armor = 75.0
	elif FastPlayer.WEAPONS.has(item):
		if player.owned.has(item) or (FastPlayer.is_primary(item) and not _current_primary().is_empty()):
			sfx.play("deny")
			return false
		cash -= cost
		purchased[item] = cost
		if FastPlayer.is_primary(item):
			player.equip(item)
		else:
			player.replace_in_class(item)
	else:
		sfx.play("deny")
		return false
	sfx.play("cash")
	_update_buy()
	return true

## Sell-back during the buy phase refunds exactly what was paid this round.
func _sell(item: String) -> bool:
	if phase != Phase.BUY or not purchased.has(item):
		sfx.play("deny")
		return false
	var refund: int = int(purchased[item])
	purchased.erase(item)
	if item == "armor":
		player.armor = _armor_before
	elif item.begins_with("att:"):
		var parts: PackedStringArray = item.split(":")
		var part: Dictionary = FastPlayer.ATTACHMENTS[parts[2]]
		player.set_attachment(parts[1], str(part["slot"]), "")
	elif FastPlayer.WEAPONS.has(item):
		for key: Variant in purchased.keys():
			if str(key).begins_with("att:%s:" % item):
				refund += int(purchased[key])
				purchased.erase(key)
		player.drop_weapon(item)
		if player.owned_in_class("pistol").is_empty():
			player.equip("pistol")
	cash += refund
	sfx.play("cash", 0.85)
	_update_buy()
	return true

## The weapon contract-mode attachments are bought for: the primary if any, else the pistol.
func _shop_target() -> String:
	var primary: String = _current_primary()
	return primary if not primary.is_empty() else player.owned_in_class("pistol")

func _show_attachment_shop() -> void:
	buy_tab = "mods"
	buy_mod_target = _shop_target()
	_open_buy_menu()

## Contract-mode attachment purchase: validated like every other transaction (phase, funds,
## fit). Replacing a part bought this round refunds it.
func _purchase_attachment(weapon: String, part_id: String) -> bool:
	if not _can_buy_now() or not FastPlayer.ATTACHMENTS.has(part_id) or not player.owned.has(weapon):
		sfx.play("deny")
		return false
	var part: Dictionary = FastPlayer.ATTACHMENTS[part_id]
	var slot: String = part["slot"]
	var previous: String = player.attachment(weapon, slot)
	var previous_key: String = "att:%s:%s" % [weapon, previous]
	var refund: int = int(purchased.get(previous_key, 0)) if phase == Phase.BUY else 0
	if previous == part_id or cash + refund < int(part["price"]) or not player.fits(weapon, part_id):
		sfx.play("deny")
		return false
	if not previous.is_empty() and purchased.has(previous_key):
		if phase == Phase.BUY:
			cash += int(purchased[previous_key])
		purchased.erase(previous_key)
	cash -= int(part["price"])
	purchased["att:%s:%s" % [weapon, part_id]] = int(part["price"])
	player.set_attachment(weapon, slot, part_id)
	sfx.play("cash")
	return true

## Free-roam gunsmith: cycle any compatible attachment on the weapon in hand.
func _gunsmith() -> void:
	_lock_controls(true)
	_clear_menu()
	_menu_back = _resume
	var id: String = player.weapon_id
	var stats: Dictionary = player.weapon_stats()
	_heading("GUNSMITH", "FREE ROAM  /  %s" % stats["name"])
	_text("Damage %d  ·  Magazine %d  ·  Reload %.1fs  ·  Recoil %.1f°  ·  Hip spread %.1f°  ·  Aim zoom %d°" % [stats["damage"], stats["capacity"], stats["reload"] if float(stats["per_round"]) <= 0.0 else stats["per_round"], stats["recoil"], stats["hip_spread"], stats["fov"]], 14, INK)
	var weapon_class: String = FastPlayer.class_of(id)
	_button("MODEL:  %s   »" % stats["name"], func():
		var variants: Array = FastPlayer.VARIANTS[weapon_class]
		player.replace_in_class(str(variants[(variants.find(id) + 1) % variants.size()]))
		sfx.play("mag_in")
		_gunsmith())
	for slot: String in FastPlayer.SLOTS:
		var options: Array[String] = player.options_for(id, slot)
		if options.is_empty():
			continue
		var current: String = player.attachment(id, slot)
		var shown: String = "STANDARD" if current.is_empty() else str(FastPlayer.ATTACHMENTS[current]["name"])
		_button("%s:  %s   »" % [slot.to_upper(), shown], func():
			var cycle: Array[String] = [""]
			cycle.append_array(options)
			var index: int = cycle.find(current)
			player.set_attachment(id, slot, cycle[(index + 1) % cycle.size()])
			sfx.play("mag_in")
			_gunsmith())
	_button("NEXT WEAPON  »", func():
		player.cycle_weapon(1)
		_gunsmith())
	_button("ARSENAL  /  ALL 13 WEAPONS", _arsenal)
	_button("CLEAR ATTACHMENTS", func():
		for slot: String in FastPlayer.SLOTS:
			player.set_attachment(id, slot, "")
		_gunsmith())
	_button("DONE", _resume)
	_text("Suppressors hide your muzzle flash and tracer and barely spook security.\nLasers tighten hip fire, but the red beam shows everyone where you are.", 13, MUTED)
	menu.show()

## Free-roam arsenal: every weapon, grouped by class. Picking one swaps it into its class slot.
func _arsenal() -> void:
	_lock_controls(true)
	_clear_menu()
	_menu_back = _gunsmith
	_heading("ARSENAL", "FREE ROAM  /  PICK ANY WEAPON")
	for weapon_class: String in FastPlayer.SLOT_ORDER:
		_text("%d  ·  %s" % [FastPlayer.SLOT_ORDER.find(weapon_class) + 1, FastPlayer.CLASS_LABEL[weapon_class]], 13, TEAL)
		for id: String in FastPlayer.VARIANTS[weapon_class]:
			var stats: Dictionary = FastPlayer.WEAPONS[id]
			var state: String = "IN HAND" if player.weapon_id == id else ("CARRIED" if player.owned.has(id) else "")
			_button("%s   /   %s%s" % [stats["name"], stats["pattern"], ("    ·    " + state) if not state.is_empty() else ""], func():
				player.replace_in_class(id)
				sfx.play("mag_in")
				_arsenal())
	_button("←  GUNSMITH", _gunsmith)
	_button("DONE", _resume)
	menu.show()

func _item_name(item: String) -> String:
	if item == "armor":
		return "BODY ARMOR"
	return str(FastPlayer.WEAPONS[item]["name"])

## Recomputes the GPS route about once a second: home (teal) while carrying the case or a
## stash, else the case at the Exchange (amber), else a stash the tip pointed at (blue).
func _update_gps(delta: float) -> void:
	if free_roam or player.is_dead():
		gps_path = PackedVector3Array()
		return
	_gps_timer -= delta
	if _gps_timer > 0.0:
		return
	_gps_timer = 1.0
	if online.active:
		var goal: Vector3 = online.gps_target()
		gps_color = TEAL if goal == HOME else GOLD
		if goal == Vector3.INF or _flat_distance(player.global_position, goal) < 12.0:
			gps_path = PackedVector3Array()
			return
		gps_path = world.route(player.global_position, goal)
		if not gps_path.is_empty():
			gps_path.append(goal)
		return
	var target: Vector3 = Vector3.INF
	if carrying or tip_state == "carried":
		target = HOME
		gps_color = TEAL
	elif case_mesh.visible:
		target = case_mesh.global_position
		gps_color = GOLD
	elif tip_state == "active":
		target = tip_site["at"]
		gps_color = Color("7fb1ff")
	if target == Vector3.INF or _flat_distance(player.global_position, target) < 12.0:
		gps_path = PackedVector3Array()
		return
	gps_path = world.route(player.global_position, target)
	if not gps_path.is_empty():
		gps_path.append(target)

func _draw_gps(canvas: Control, to_screen: Callable, width: float) -> void:
	if gps_path.size() < 2:
		return
	var line: PackedVector2Array = PackedVector2Array([to_screen.call(player.global_position)])
	for point: Vector3 in gps_path:
		line.append(to_screen.call(point))
	var tint: Color = gps_color
	tint.a = 0.85
	canvas.draw_polyline(line, Color(0, 0, 0, 0.6), width + 2.0)
	canvas.draw_polyline(line, tint, width)

func _start_live() -> void:
	phase = Phase.LIVE
	buy_menu_open = false
	player.can_fire = true
	for ride: FastCar in cars:
		ride.enabled = true
	for guard: FastGuard in guards: guard.active = true
	_round_started_msec = Time.get_ticks_msec()
	_round_shots_base = shots_fired
	_round_hits_base = shots_hit
	_resume()
	_message("Doors open. Collect the documents at the Exchange in Midtown (amber), then bring them home to your HQ (teal). Follow the route line on your radar, or take your own way.")

## One line for the round-end screen: time on the clock, shots, hits and what you carried out.
func round_summary() -> String:
	var seconds: int = maxi(0, (Time.get_ticks_msec() - _round_started_msec) / 1000) if _round_started_msec > 0 else 0
	var shots: int = maxi(0, shots_fired - _round_shots_base)
	var hits: int = maxi(0, shots_hit - _round_hits_base)
	var outcome: String = "documents delivered" if paid else ("documents lost" if carrying or tip_state == "done" else "no documents moved")
	return "Round report: %d:%02d on the clock  /  %d shot%s, %d hit%s  /  %s." % [seconds / 60, seconds % 60, shots, "" if shots == 1 else "s", hits, "" if hits == 1 else "s", outcome]


## Hands up / down: weapon away as a readable peace signal (X). Not while driving or dead.
func toggle_hands_up() -> bool:
	if vehicle != null or player.is_dead():
		return false
	if not player.set_hands_up(not player.hands_up):
		return false
	_message("HANDS UP: weapon away, you cannot fire. Press %s to lower them." % _glyph("hands_up") if player.hands_up else "Hands down. Weapon ready.", 3.0)
	return true


## Occasional far-off city life (audio only; a local RNG, so gameplay stays deterministic).
func _update_ambient_events(delta: float) -> void:
	_ambient_wait -= delta
	if _ambient_wait > 0.0:
		return
	_ambient_wait = _ambient_rng.randf_range(25.0, 60.0)
	if _space != "outdoor" or not sfx.has_method("play_at"):
		return
	var angle: float = _ambient_rng.randf() * TAU
	var sound: String = "dog_far" if _ambient_rng.randf() < 0.7 else "siren_far"
	sfx.play_at(sound, player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * 90.0, 1.0, -3.0)


## Indoor/outdoor reverb from the building footprints that declare an interior
## (meta "interior_half": half extents in the building's local XZ).
func _update_space(delta: float) -> void:
	_space_check -= delta
	if _space_check > 0.0:
		return
	_space_check = 0.25
	var building: Node3D = _building_around_player()
	var next: String = "outdoor"
	if building != null:
		next = "hall" if building.name.begins_with("Garage") else "indoor"
	if next != _space:
		_space = next
		if sfx.has_method("set_space"):
			sfx.set_space(next)
	_update_interior_bed(building)


func player_indoors() -> bool:
	return _building_around_player() != null


## The walk-in building (a node with meta "interior_half") the player stands inside, or null. The
## open roof deck of the parking garage and the motel's roof walkway count as outdoors.
func _building_around_player() -> Node3D:
	return _building_at(player.global_position)


## The walk-in building around a world point, or null (also used by the voice relay to decide who
## shares a room with whom). Looks only at the interiors in the point's grid cell.
func _building_at(at: Vector3) -> Node3D:
	if not _interiors_scanned and is_instance_valid(world):
		_interiors_scanned = true
		_collect_interiors(world, 0)
		_build_interior_grid()
	var cell: Vector2i = Vector2i(floori(at.x / INTERIOR_CELL), floori(at.z / INTERIOR_CELL))
	for index: int in (_interior_grid.get(cell, PackedInt32Array()) as PackedInt32Array):
		var node: Node3D = _interior_nodes[index]
		if not is_instance_valid(node):
			continue
		var local: Vector3 = node.global_transform.affine_inverse() * at
		var half: Vector2 = node.get_meta("interior_half")
		# Garage roof deck and the motel's roof walkway are open air.
		var ceiling: float = _interior_ceiling(node)
		if absf(local.x) < half.x and absf(local.z) < half.y and local.y > -1.0 and local.y < ceiling:
			return node
	return null


func _interior_ceiling(node: Node3D) -> float:
	return 5.5 if node.name.begins_with("Garage") else (4.3 if node.name.begins_with("Motel") else 9.0)


## Files every interior under the grid cells its world-space box touches (buildings never move).
func _build_interior_grid() -> void:
	_interior_grid.clear()
	for index: int in range(_interior_nodes.size()):
		var node: Node3D = _interior_nodes[index]
		if not is_instance_valid(node):
			continue
		var half: Vector2 = node.get_meta("interior_half")
		var low: Vector2 = Vector2(INF, INF)
		var high: Vector2 = Vector2(-INF, -INF)
		for corner: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(-half.x, half.y), Vector2(half.x, half.y)]:
			for y: float in [-1.0, _interior_ceiling(node)]:
				var world_point: Vector3 = node.global_transform * Vector3(corner.x, y, corner.y)
				low = Vector2(minf(low.x, world_point.x), minf(low.y, world_point.z))
				high = Vector2(maxf(high.x, world_point.x), maxf(high.y, world_point.z))
		for cx: int in range(floori(low.x / INTERIOR_CELL), floori(high.x / INTERIOR_CELL) + 1):
			for cz: int in range(floori(low.y / INTERIOR_CELL), floori(high.y / INTERIOR_CELL) + 1):
				var cell: Vector2i = Vector2i(cx, cz)
				var list: PackedInt32Array = _interior_grid.get(cell, PackedInt32Array())
				list.append(index)
				_interior_grid[cell] = list


## Positions of the currently OPEN doorways within `radius` metres of `at` (voice routing asks for the talker's
## DOOR_RADIUS). Doors are filed in a grid once; lift doors move with their car, so they are checked live.
func _open_doors_near(at: Vector3, radius: float) -> Array:
	var out: Array = []
	if not is_instance_valid(world):
		return out
	var doors: Array[Dictionary] = world.interactable_doors
	if _door_grid_count != doors.size():
		_build_door_grid()
	var low: Vector2i = Vector2i(floori((at.x - radius) / DOOR_CELL), floori((at.z - radius) / DOOR_CELL))
	var high: Vector2i = Vector2i(floori((at.x + radius) / DOOR_CELL), floori((at.z + radius) / DOOR_CELL))
	for cx: int in range(low.x, high.x + 1):
		for cz: int in range(low.y, high.y + 1):
			for index: int in (_door_grid.get(Vector2i(cx, cz), PackedInt32Array()) as PackedInt32Array):
				_add_open_door(doors[index], at, radius, out)
	for index: int in _door_lifts:
		_add_open_door(doors[index], at, radius, out)
	return out


func _add_open_door(door: Dictionary, at: Vector3, radius: float, out: Array) -> void:
	if bool(door.get("open", false)) and door.get("position") is Vector3 and at.distance_to(door["position"]) <= radius:
		out.append(door["position"])


func _build_door_grid() -> void:
	_door_grid.clear()
	_door_lifts = PackedInt32Array()
	var doors: Array[Dictionary] = world.interactable_doors
	_door_grid_count = doors.size()
	for index: int in range(doors.size()):
		var door: Dictionary = doors[index]
		if not (door.get("position") is Vector3):
			continue
		if str(door.get("kind", "")) == "lift":
			_door_lifts.append(index)
			continue
		var at: Vector3 = door["position"]
		var cell: Vector2i = Vector2i(floori(at.x / DOOR_CELL), floori(at.z / DOOR_CELL))
		var list: PackedInt32Array = _door_grid.get(cell, PackedInt32Array())
		list.append(index)
		_door_grid[cell] = list


## Interior sound beds (docs/AUDIO_PASS.md): muffled club bass in the two clubs, room tone in
## other walk-in buildings, nothing in the open garage or outdoors. One looping player, swapped
## only when the bed changes; the street ambience dips indoors.
func _update_interior_bed(building: Node3D) -> void:
	var bed: String = ""
	if building != null and not building.name.begins_with("Garage"):
		bed = "club_bass" if building.name.begins_with("Nightclub") or building.name.begins_with("Stripclub") else "room_tone"
	if bed == _interior_bed or not sfx.has_method("has_sound"):
		return
	_interior_bed = bed
	if not is_instance_valid(_interior_bed_player):
		_interior_bed_player = AudioStreamPlayer.new()
		add_child(_interior_bed_player)
	_interior_bed_player.stop()
	if not bed.is_empty() and sfx.has_sound(bed):
		_interior_bed_player.stream = sfx.call("stream", bed)
		var hint: float = sfx.call("gain_hint", bed) if sfx.has_method("gain_hint") else 0.0
		_interior_bed_player.volume_db = sfx.call("master_db", hint - (4.0 if bed == "club_bass" else 8.0))
		_interior_bed_player.play()
	if is_instance_valid(ambience_player):
		ambience_player.volume_db = sfx.call("master_db", -17.0 - (8.0 if not bed.is_empty() else 0.0))


func _collect_interiors(node: Node, depth: int) -> void:
	for child: Node in node.get_children():
		if child is Node3D and child.has_meta("interior_half") and child.get_meta("interior_half") is Vector2:
			_interior_nodes.append(child as Node3D)
		elif depth < 2:
			_collect_interiors(child, depth + 1)


func _finish(won: bool, title: String, detail: String) -> void:
	if phase != Phase.LIVE: return
	phase = Phase.RESULT
	if won:
		cash += PAYOUT
		losses = 0
		sfx.play("cash")
	else:
		losses += 1
		var relief: int = mini(1200 + (losses - 1) * 300,2400)
		cash += relief
		detail += "\nCompany recovery allowance: $%s." % _money(relief)
	cash = mini(cash,16000)
	if not player.is_dead():
		detail += "\nYou walked away: your weapons, parts and armour carry into the next round."
	detail += "\n" + round_summary()
	_lock_controls(true)
	_clear_menu()
	_heading(title.to_upper(),"ROUND %02d  /  %s" % [round_number,"SETTLED" if won else "FAILED"])
	_text(detail + "\n\nNext-round balance: $%s" % _money(cash))
	_button("NEXT CONTRACT  →",_start_round)
	_button("MAIN MENU",_show_title)
	menu.show()

func _show_title() -> void:
	phase = Phase.MENU
	free_roam = false
	_sync_world_mode()
	_carry_gear = false
	buy_menu_open = false
	if vehicle != null:
		_exit_vehicle(true)
	for ride: FastCar in cars:
		_clear_vehicle(ride)
	_lock_controls(true)
	for guard: FastGuard in _all_guards():
		guard.set_present(false)
	case_mesh.visible = false
	_reset_tip(-1.0)
	for model: Node3D in lineup:
		model.visible = true
	_orbit_title(0.0)
	chase.fov = 50.0
	chase.make_current()
	_clear_menu()
	_menu_back = Callable()
	_heading("FAST\nTALKERS", "PORT HALCYON  /  PROTOTYPE 0.6")
	_text("GOOD BUSINESS.  BAD COMPANY.",22,GOLD)
	var identity: Dictionary = Factions.get_crew(crew)
	_button("CREW:  %s  (%s)" % [identity["name"], str(identity["kind"]).to_upper()], func():
		crew = Factions.next_id(crew)
		_apply_crew()
		_save_settings()
		_show_title())
	_button("PLAY ONLINE  /  HOST OR JOIN A MATCH  →", online.show_lobby)
	_text("The deal round with friends: LAN, Tailscale or a forwarded port. Players only, no bots.", 14, MUTED)
	_button("FREE ROAM  /  ARMORY, RANGE & MOTOR POOL  →", _start_free_roam)
	_text("No clock, no money. Every weapon and vehicle, the range and practice bots.", 14, MUTED)
	_button("CONTRACT  /  ROUND MODE  →",func():
		cash = START_CASH
		round_number = 0
		losses = 0
		_carry_gear = false
		_start_round())
	_text("Buy at your HQ, get the case from the Exchange by deal or by force, bring it home.", 14, MUTED)
	# Kept below the older modes so pad/menu walks (tests/free_roam.gd) still reach them in the same order.
	_button("SOLO WEEK  /  THE REAL WEEK, JUST YOU  →", online.start_solo_week)
	_text("Monday to Friday on this PC: the crew phone, the cases, the Friday Dead Drop. For demos and practice.", 14, MUTED)
	_button("CONTROLS & SETTINGS",func(): _settings(true))
	_button("QUIT",func(): get_tree().quit())
	_text("Offline modes use practice bots; online matches are players only.\nVoice: open-mic proximity voice is on by default; hold Y for the crew radio.",13,MUTED)
	menu.show()

func _orbit_title(delta: float) -> void:
	# A slow handheld drift on the crew lineup under the Exchange neon.
	_title_angle += delta * 0.35
	chase.position = Vector3(-2.6 + sin(_title_angle) * 0.18, 1.5 + sin(_title_angle * 0.7) * 0.05, -34.4)
	chase.look_at(Vector3(-0.2, 1.4, -41.0))

func _pause() -> void:
	buy_menu_open = false
	_lock_controls(true)
	_clear_menu()
	_menu_back = _resume
	if online.active:
		_heading("ON HOLD", "ONLINE MATCH  /  THE CITY KEEPS MOVING")
		_button("RESUME", _resume)
		_button("CONTROLS & SETTINGS", func(): _settings(false))
		_button("LEAVE MATCH", online.leave_match)
		menu.show()
		return
	if free_roam:
		_heading("ON HOLD", "FREE ROAM  /  PAUSED")
		_button("RESUME",_resume)
		_button("GUNSMITH  /  ATTACHMENTS",_gunsmith)
		_button("ARSENAL  /  ALL 13 WEAPONS",_arsenal)
		_button("REARM & HEAL",func():
			_rearm()
			_resume())
		_button("RETURN TO THE ARMORY",func():
			if vehicle != null:
				_exit_vehicle(true)
			respawn_timer = -1.0
			player.reset_player(ArmoryScript.SPAWN)
			player.face(-PI * 0.5)
			player.armor = 100.0
			player.camera.make_current()
			_resume())
		_button("RESET GUARDS, TARGETS & VEHICLES",func():
			var was_in_vehicle: bool = vehicle != null
			_reset_world_state()
			for guard: FastGuard in _all_guards():
				guard.set_present(true)
			if was_in_vehicle:
				player.reset_player(ArmoryScript.SPAWN)
				player.face(-PI * 0.5)
				player.camera.make_current()
			_resume())
		_button("CREW:  %s" % Factions.get_crew(crew)["name"],func():
			crew = Factions.next_id(crew)
			_apply_crew()
			_save_settings()
			_pause())
		_button("INVULNERABLE:  %s" % ("ON" if player.invulnerable else "OFF"),func():
			player.invulnerable = not player.invulnerable
			_pause())
		_button("CONTROLS & SETTINGS",func(): _settings(false))
		_button("MAIN MENU",_show_title)
		menu.show()
		return
	_heading("ON HOLD", "CONTRACT PAUSED")
	_button("RESUME",_resume)
	_button("CONTROLS & SETTINGS",func(): _settings(false))
	_button("RECOVER STUCK VEHICLE",func():
		var stuck: FastCar = vehicle if vehicle != null else car
		if vehicle != null:
			_exit_vehicle(true)
			player.position = HOME + Vector3(0, 1, 0)
			player.camera.make_current()
		stuck.reset_to_spawn()
		_resume())
	_button("ABANDON CONTRACT",func():
		_resume()
		if phase == Phase.BUY:
			_start_live()
		_finish(false,"Contract abandoned","The company recalled your team."))
	menu.show()

func _settings(from_title: bool) -> void:
	_clear_menu()
	_menu_back = func():
		_save_settings()
		if from_title: _show_title()
		else: _pause()
	_heading("OPERATOR HANDBOOK", "CONTROLS & SETTINGS")
	_text("WASD  walk / drive        MOUSE  look freely, including in vehicles\nSHIFT  sprint        CTRL or C  crouch        SPACE  jump / handbrake\nLMB  fire        RMB  aim / scope        R  reload\n1-5  weapon class (free roam: press again for the next model)\nWHEEL  cycle        Q  last weapon        B  buy menu / gunsmith\nE  enter (driver) / exit, trade, deliver, rearm at the armory\nF  ride as a passenger gunner / change seats\nAt the wheel: hold RMB to enable one-handed fire, then LMB to shoot\nV  vehicle camera (first / third person)        H  horn        G  drop case        K  drop the crew phone        T  rearm (free roam)\nX  hands up (weapon away: a peace signal)        Z  hold for binoculars\nCarrying a case, the Ledger or cash: only your sidearm can be drawn or fired\nVoice: open mic reaches players within 35 m (or hold N to talk if you switch to push-to-talk)        Y  hold for crew radio\nF11  fullscreen        F3  FPS counter        ESC  pause        M  city map\n\nController: sticks move/look, RT fire / throttle, LT aim / brake, A jump / handbrake,\nB crouch / back, X reload, Y interact, LB/RB weapons (buy menu: tabs),\nD-pad left: buy in contracts / rearm in free roam. D-pad right: gunsmith / ride / change seat.\nAt the wheel: hold LB to\nenable one-handed fire, then RB to shoot. L3 sprint (in car: horn), View: map, Menu: pause.\nD-pad down: drop the trade item (hold: drop the crew phone). D-pad up: last weapon (hold: binoculars).\nR3 on foot: hands up (in a vehicle: camera).\n\nVehicles: W throttle, S brake then reverse. Exit below 8 km/h.",14)
	_text("Sound volume",14,TEAL)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = master_volume
	slider.value_changed.connect(func(value: float):
		master_volume = value
		_apply_settings())
	menu_stack.add_child(slider)
	_text("Voice chat  /  proximity mic is on by default; hold Y for crew radio",14,TEAL)
	var voice_on := CheckButton.new()
	voice_on.text = "Voice chat"
	voice_on.button_pressed = voice.enabled
	voice_on.toggled.connect(func(on: bool): voice.enabled = on)
	menu_stack.add_child(voice_on)
	var open_mic := CheckButton.new()
	open_mic.text = "Open mic (recommended); off = hold N to talk to people nearby"
	open_mic.button_pressed = voice.proximity_mode == "open"
	open_mic.toggled.connect(func(on: bool): voice.proximity_mode = "open" if on else "push_to_talk")
	menu_stack.add_child(open_mic)
	_text("Voice volume",14,TEAL)
	var voice_volume := HSlider.new()
	voice_volume.min_value = 0.0
	voice_volume.max_value = 2.0
	voice_volume.step = 0.05
	voice_volume.value = voice.output_volume
	voice_volume.value_changed.connect(func(value: float): voice.output_volume = value)
	menu_stack.add_child(voice_volume)
	_text("Microphone level",14,TEAL)
	var mic_level := HSlider.new()
	mic_level.min_value = 0.2
	mic_level.max_value = 4.0
	mic_level.step = 0.1
	mic_level.value = voice.mic_gain
	mic_level.value_changed.connect(func(value: float): voice.mic_gain = value)
	menu_stack.add_child(mic_level)
	_text("Mouse sensitivity",14,TEAL)
	var sensitivity := HSlider.new()
	sensitivity.min_value = 0.0005
	sensitivity.max_value = 0.006
	sensitivity.step = 0.0001
	sensitivity.value = player.mouse_sensitivity
	sensitivity.value_changed.connect(func(value:float): player.mouse_sensitivity = value)
	menu_stack.add_child(sensitivity)
	var fov_label := _text("Field of view  /  %d°" % int(fov_setting),14,TEAL)
	var fov := HSlider.new()
	fov.min_value = 70.0
	fov.max_value = 100.0
	fov.step = 1.0
	fov.value = fov_setting
	fov.value_changed.connect(func(value: float):
		fov_setting = value
		fov_label.text = "Field of view  /  %d°" % int(value)
		_apply_settings())
	menu_stack.add_child(fov)
	_text("Controller look speed",14,TEAL)
	var pad_look := HSlider.new()
	pad_look.min_value = 0.3
	pad_look.max_value = 2.5
	pad_look.step = 0.05
	pad_look.value = player.pad_sensitivity
	pad_look.value_changed.connect(func(value: float): player.pad_sensitivity = value)
	menu_stack.add_child(pad_look)
	_button("INVERT LOOK (CONTROLLER):  %s" % ("ON" if player.invert_y else "OFF"),func():
		player.invert_y = not player.invert_y
		_save_settings()
		_settings(from_title))
	_button("VEHICLE CAMERA:  %s" % ("THIRD PERSON" if drive_third_person else "FIRST PERSON"),func():
		drive_third_person = not drive_third_person
		_save_settings()
		_settings(from_title))
	_button("VIBRATION:  %s" % ("ON" if vibration else "OFF"),func():
		vibration = not vibration
		_save_settings()
		_rumble(0.4, 0.4, 0.2)
		_settings(from_title))
	_button("FULLSCREEN:  %s" % ("ON" if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else "OFF"),func():
		_toggle_fullscreen()
		_settings(from_title))
	_button("FILM GRADE (GRAIN & COLOUR):  %s" % ("ON" if film_grade else "OFF"),func():
		film_grade = not film_grade
		_apply_settings()
		_save_settings()
		_settings(from_title))
	_button("LIGHTING:  %s" % ("DUSK" if lighting_dusk else "DAY"),func():
		lighting_dusk = not lighting_dusk
		_apply_settings()
		_save_settings()
		_settings(from_title))
	_button("SHADOWS:  %s" % ["OFF (FASTEST)", "MEDIUM", "HIGH"][shadow_quality],func():
		shadow_quality = (shadow_quality + 1) % 3
		_apply_settings()
		_save_settings()
		_settings(from_title))
	_button("POTATO MODE (LOW-END PCs):  %s" % ("ON" if potato_mode else "OFF"),func():
		potato_mode = not potato_mode
		_apply_settings()
		_save_settings()
		_settings(from_title))
	_button("FPS COUNTER:  %s" % ("ON" if show_fps else "OFF"),func():
		show_fps = not show_fps
		_save_settings()
		_settings(from_title))
	_button("BACK",func():
		_save_settings()
		if from_title: _show_title()
		else: _pause())

func _toggle_fullscreen() -> void:
	var fullscreen: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
	_save_settings()

func _apply_settings() -> void:
	sfx.set("volume", master_volume)
	player.base_fov = fov_setting
	if is_instance_valid(world.sun):
		world.sun.shadow_enabled = shadow_quality > 0
		world.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if shadow_quality == 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		world.sun.directional_shadow_max_distance = 95.0 if shadow_quality == 2 else 70.0
	if is_instance_valid(ambience_player):
		ambience_player.volume_db = sfx.call("master_db", -17.0)
	if world.dusk != lighting_dusk:
		world.set_dusk(lighting_dusk)
	if is_instance_valid(grade_rect):
		grade_rect.visible = film_grade
	if world.has_method("set_potato_mode"):
		world.call("set_potato_mode", potato_mode)

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		master_volume = float(config.get_value("audio", "volume", master_volume))
		player.mouse_sensitivity = float(config.get_value("input", "sensitivity", player.mouse_sensitivity))
		fov_setting = float(config.get_value("video", "fov", fov_setting))
		show_fps = bool(config.get_value("video", "show_fps", show_fps))
		shadow_quality = clampi(int(config.get_value("video", "shadows", shadow_quality)), 0, 2)
		lighting_dusk = bool(config.get_value("video", "dusk", lighting_dusk))
		film_grade = bool(config.get_value("video", "film_grade", film_grade))
		potato_mode = bool(config.get_value("video", "potato_mode", potato_mode))
		player.pad_sensitivity = float(config.get_value("input", "pad_sensitivity", player.pad_sensitivity))
		player.invert_y = bool(config.get_value("input", "invert_y", player.invert_y))
		vibration = bool(config.get_value("input", "vibration", vibration))
		drive_third_person = bool(config.get_value("video", "drive_third_person", drive_third_person))
		if voice != null:
			voice.apply_settings({
				"enabled": config.get_value("voice", "enabled", voice.enabled), "mic_gain": config.get_value("voice", "mic_gain", voice.mic_gain),
				"gate_db": config.get_value("voice", "gate_db", voice.gate_db), "output_volume": config.get_value("voice", "output_volume", voice.output_volume),
				"proximity_mode": config.get_value("voice", "proximity_mode", voice.proximity_mode)})
		var saved_crew: String = str(config.get_value("profile", "crew", crew))
		if Factions.ORDER.has(saved_crew):
			crew = saved_crew
		if bool(config.get_value("video", "fullscreen", false)) and DisplayServer.get_name() != "headless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_apply_settings()

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "volume", master_volume)
	if voice != null:
		for key: String in voice.settings():
			config.set_value("voice", key, voice.settings()[key])
	config.set_value("input", "sensitivity", player.mouse_sensitivity)
	config.set_value("video", "fov", fov_setting)
	config.set_value("video", "show_fps", show_fps)
	config.set_value("video", "shadows", shadow_quality)
	config.set_value("video", "dusk", lighting_dusk)
	config.set_value("video", "film_grade", film_grade)
	config.set_value("video", "potato_mode", potato_mode)
	config.set_value("input", "pad_sensitivity", player.pad_sensitivity)
	config.set_value("input", "invert_y", player.invert_y)
	config.set_value("input", "vibration", vibration)
	config.set_value("profile", "crew", crew)
	config.set_value("video", "drive_third_person", drive_third_person)
	config.set_value("video", "fullscreen", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	config.save(settings_path)

func _lock_controls(lock: bool) -> void:
	paused = lock
	player.enabled = not lock
	for ride: FastCar in cars:
		ride.enabled = (not lock or online.active) and phase != Phase.BUY
		ride.set_physics_process(not lock or online.active)
	for guard: FastGuard in _all_guards(): guard.active = not lock and phase == Phase.LIVE and guard.visible
	for target: StaticBody3D in armory.get("targets"):
		target.set("active", not lock and free_roam and armory.is_open())
	if lock:
		_stop_loops()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if lock else Input.MOUSE_MODE_CAPTURED

func _resume() -> void:
	menu.hide()
	buy_menu_open = false
	_lock_controls(false)
	player.input_grace = 0.15

func _message(message: String, duration: float = 5.0) -> void:
	feed_label.text = message
	msg_timer = duration

func _money(amount: int) -> String:
	var digits: String = str(absi(amount))
	var grouped: String = ""
	while digits.length() > 3:
		grouped = "," + digits.substr(digits.length() - 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if amount < 0 else "") + digits + grouped

# --- Combat -----------------------------------------------------------------

func _falloff(stats: Dictionary, distance: float) -> float:
	var curve: Vector3 = stats.get("falloff", Vector3(1000, 2000, 1))
	if distance <= curve.x:
		return 1.0
	return lerpf(1.0, curve.z, clampf((distance - curve.x) / maxf(curve.y - curve.x, 0.01), 0.0, 1.0))

func _on_shot(origin: Vector3,direction: Vector3,damage: float) -> void:
	if phase != Phase.LIVE or paused: return
	var query := PhysicsRayQueryParameters3D.create(origin,origin + direction * 320.0)
	# Keep the occupied vehicle in the ray. Its compound lower body, roof and
	# pillars stop shots while the window openings and pickup bed stay clear.
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var end := origin + direction * 170.0
	var stats: Dictionary = player.weapon_stats()
	if not hit.is_empty():
		end = hit.position
		var collider: Object = hit.collider
		var amount: float = damage * _falloff(stats, origin.distance_to(end))
		var headshot: bool = collider.has_method("hit_zone") and str(collider.call("hit_zone", end)) == "head"
		if headshot:
			amount *= float(stats.get("headshot", 2.0))
		if collider is FastRemote:
			if online.active:
				online.claim_hit(collider as FastRemote, amount, headshot, origin, end)
			_register_hit(headshot, false)
			effects.call("impact", end, hit.normal, "flesh")
		elif collider is FastGuard:
			var guard: FastGuard = collider as FastGuard
			var was_alive: bool = guard.health > 0.0
			guard.take_damage(amount)
			_register_hit(headshot, was_alive and guard.health <= 0.0)
			effects.call("impact", end, hit.normal, "flesh")
			if free_roam:
				effects.call("damage_number", end, amount, headshot)
			_alert_guards(guard.global_position)
		elif collider is FastCar:
			# Vehicles soak bullets (their doors are cover) until the engine dies.
			(collider as FastCar).take_damage(amount * 0.6)
			effects.call("impact", end, hit.normal, "car")
			sfx.call("play_at", "impact", end, 1.6)
		elif collider.has_method("take_hit"):
			var plate: bool = str(collider.get("kind")) == "plate"
			effects.call("impact", end, hit.normal, "steel" if plate else "dust")
			collider.call("take_hit", amount, end, headshot)
		elif collider.has_method("take_damage"):
			collider.call("take_damage", amount)
			_register_hit(false, false)
			_alert_guards()
		else:
			effects.call("impact", end, hit.normal, "world")
			if origin.distance_to(end) < 40.0:
				sfx.call("play_at", "impact", end)
	_break_car_glass(origin, end)
	_pellet_count += 1
	if int(stats.get("pellets", 1)) == 1 or _pellet_count % 3 == 0:
		var start: Vector3 = player.muzzle_position()
		if bool(stats.get("quiet", false)):
			effects.call("tracer", start, end, Color(0.55, 0.52, 0.48), 0.008, 0.03)
		else:
			effects.call("tracer", start, end, Color(1.0, 0.86, 0.55), 0.016, 0.05)

## Car windows along a shot's path shatter and the bullet carries on (the hull is open at
## the windows, so the ray result beyond the glass is already correct).
func _break_car_glass(from: Vector3, to: Vector3) -> void:
	for ride: FastCar in cars:
		if ride.glass_count() == 0 or Geometry3D.get_closest_point_to_segment(ride.global_position, from, to).distance_to(ride.global_position) > 4.5:
			continue
		for attempt: int in range(3):
			var pane: Dictionary = ride.glass_hit(from, to)
			if pane.is_empty():
				break
			ride.break_glass(int(pane["index"]), pane["position"])

func _on_car_glass_broken(index: int, at: Vector3, ride: FastCar) -> void:
	sfx.play_at("glass", at, randf_range(0.92, 1.1))
	online.glass_broken(ride, index)

func _register_hit(headshot: bool, killed: bool) -> void:
	_trigger_hit = true
	hit_timer = 0.2
	hit_kind = "kill" if killed else ("head" if headshot else "hit")
	if killed:
		sfx.play("kill")
	sfx.play("headshot" if headshot else "hit")

func _on_target_struck(amount: float, headshot: bool, downed: bool, at: Vector3, target: StaticBody3D) -> void:
	_trigger_hit = true
	hit_timer = 0.2
	if str(target.get("kind")) == "plate":
		hit_kind = "kill" if downed else "hit"
		sfx.play_at("steel", at, randf_range(0.92, 1.12))
		sfx.play("hit", 1.2, -6.0)
		if downed and free_roam and armory.rack.has(target):
			_rack_progress()
		return
	effects.call("damage_number", at, amount, headshot)
	hit_kind = "kill" if downed else ("head" if headshot else "hit")
	sfx.play("headshot" if headshot else "hit")
	if downed:
		sfx.play("kill")

## Timed plate-rack drill: the clock starts on the first plate and stops on the fifth.
func _rack_progress() -> void:
	var down: int = 0
	for plate: StaticBody3D in armory.rack:
		if bool(plate.get("down")):
			down += 1
	var now: int = Time.get_ticks_msec()
	if down == 1:
		_rack_start = now
	if down < armory.rack.size() or _rack_start < 0:
		return
	var seconds: float = (now - _rack_start) / 1000.0
	_rack_start = -1
	var record: bool = rack_best <= 0.0 or seconds < rack_best
	if record:
		rack_best = seconds
	sfx.play("cash", 1.2 if record else 1.0)
	_message("PLATE RACK CLEARED  /  %.2f s%s" % [seconds, "  /  NEW BEST" if record else "  /  best %.2f s" % rack_best], 6.0)

func _on_weapon_fired(id: String) -> void:
	var kick: Dictionary = {"pistol": [0.25, 0.1], "smg": [0.2, 0.08], "rifle": [0.3, 0.15], "shotgun": [0.6, 0.6], "marksman": [0.5, 0.55]}
	var power: Array = kick.get(FastPlayer.class_of(id), [0.3, 0.1])
	_rumble(power[0], power[1], 0.09)
	var stats: Dictionary = player.weapon_stats()
	var quiet: bool = bool(stats.get("quiet", false))
	online.weapon_fired(quiet)
	if quiet:
		sfx.play("suppressed", 1.35 - clampf(float(stats["damage"]) / 100.0, 0.0, 0.6))
	else:
		sfx.play(str(stats.get("sound", id)), 1.0, 2.5 if bool(stats.get("loud", false)) else 0.0)
		effects.call("muzzle_light", player.muzzle_position())
	shots_fired += 1
	if _trigger_hit:
		shots_hit += 1
	_trigger_hit = false
	var action: String = str(stats.get("action", ""))
	if action == "pump" or action == "bolt":
		get_tree().create_timer(0.34 if action == "pump" else 0.4).timeout.connect(_cycle_action.bind(id))
	elif action == "revolver":
		sfx.play("cylinder", 1.2, -6.0)
	elif action != "break" and player.ads_blend < 0.5:
		effects.call("brass", player.ejector_position(), player.camera.global_basis.x, player.camera.global_basis.z)
	# Gunfire close to security spooks them, even if nobody was hit.
	if phase == Phase.LIVE:
		for guard: FastGuard in _all_guards():
			var radius: float = GUNFIRE_ALERT_RADIUS * (0.4 if quiet else 1.0)
			if guard.visible and guard.health > 0.0 and not guard.hostile and guard.global_position.distance_to(player.global_position) < radius:
				_alert_guards(guard.global_position)
				break

func _cycle_action(id: String) -> void:
	if not is_instance_valid(player) or player.weapon_id != id:
		return
	var action: String = str(player.weapon_stats().get("action", ""))
	sfx.play("pump" if action == "pump" else "bolt")
	if player.ads_blend < 0.5:
		effects.call("brass", player.ejector_position(), player.camera.global_basis.x, player.camera.global_basis.z, action == "pump")

func _on_weapon_event(event: String) -> void:
	match event:
		"dry": sfx.play("dry")
		"mag_out": sfx.play("mag_out")
		"mag_in":
			sfx.play("mag_in")
			# Pistols rack the slide once the new magazine is seated.
			if FastPlayer.class_of(player.weapon_id) == "pistol" and is_inside_tree():
				get_tree().create_timer(0.16).timeout.connect(func(): sfx.play("slide"))
		"shell": sfx.play("shell")
		"pump": sfx.play("pump")
		"reload_start": sfx.play("shell", 0.85)
		"draw":
			# The previous weapon goes away first, then the new one is drawn.
			sfx.play("holster", 1.0, -3.0)
			sfx.play("draw")
		"break_open": sfx.play("break_open")

func _on_player_damaged(amount: float, source: Vector3) -> void:
	_rumble(0.5, clampf(amount / 25.0, 0.2, 0.9), 0.22)
	damage_flash = minf(1.0, damage_flash + amount / 22.0)
	if source != Vector3.INF:
		damage_marks.append({"source": source, "life": 1.3})
	sfx.play("hurt", randf_range(0.9, 1.1))

func _on_footstep(loud: bool) -> void:
	sfx.play("step%d" % (randi() % 4), randf_range(0.9, 1.1), 0.0 if loud else -6.0)

func guard_shot(origin:Vector3,end:Vector3,hit:bool = true) -> void:
	var finish: Vector3 = end
	if not hit:
		# Carry the miss on until it strikes the world, and crack past the player's ear.
		var direction: Vector3 = (end - origin).normalized()
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 90.0)
		query.exclude = [player.get_rid()]
		var impact := get_world_3d().direct_space_state.intersect_ray(query)
		finish = origin + direction * 90.0
		if not impact.is_empty():
			finish = impact.position
			effects.call("impact", finish, impact.normal, "world")
		var head: Vector3 = player.camera.global_position
		if Geometry3D.get_closest_point_to_segment(head, origin, finish).distance_to(head) < 2.5:
			sfx.play("whiz", randf_range(0.85, 1.15))
	effects.call("tracer", origin, finish, Color("f08a5d"), 0.022, 0.08)
	effects.call("muzzle_light", origin)
	sfx.play_shot_at("guard_shot", origin, player.global_position)
	if hit and msg_timer < 2.5:
		_message("Taking fire! Find cover or leave the exchange.", 3.0)

# --- Vehicles -----------------------------------------------------------------

func _update_chase(delta: float) -> void:
	var speed_fraction: float = clampf(absf(vehicle.longitudinal_speed) / vehicle.maximum_forward_speed, 0.0, 1.0)
	_chase_idle += delta
	var stick: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down", 0.15)
	if stick.length() > 0.01 and not paused:
		_chase_yaw = wrapf(_chase_yaw - stick.x * 2.4 * delta, -PI, PI)
		_chase_pitch = clampf(_chase_pitch + stick.y * 1.3 * delta, -0.35, 0.8)
		_chase_idle = 0.0
	if _chase_idle > 1.4:
		var settle: float = 1.0 - exp(-2.6 * delta)
		_chase_yaw = lerp_angle(_chase_yaw, 0.0, settle)
		_chase_pitch = lerpf(_chase_pitch, 0.0, settle)
	var back: Vector3 = vehicle.global_basis.z
	back.y = 0.0
	back = back.normalized().rotated(Vector3.UP, _chase_yaw)
	var distance: float = float(vehicle.spec.get("chase", 7.2))
	var focus := vehicle.global_position + Vector3(0, 1.6 if not vehicle.is_bike() else 1.3, 0)
	var desired := vehicle.global_position + back * (distance + speed_fraction * 1.8) + Vector3(0, distance * 0.5 + _chase_pitch * 4.0, 0)
	var query := PhysicsRayQueryParameters3D.create(focus, desired)
	query.exclude = [vehicle.get_rid(),player.get_rid()]
	var obstruction := get_world_3d().direct_space_state.intersect_ray(query)
	if not obstruction.is_empty():
		desired = obstruction.position + obstruction.normal * 0.4
	chase.global_position = chase.global_position.lerp(desired, 1.0 - exp(-9.0 * delta))
	if _shake > 0.0:
		chase.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = move_toward(_shake, 0.0, delta * 1.2)
	if chase.global_position.distance_to(focus) > 0.1:
		chase.look_at(focus)
	chase.fov = lerpf(chase.fov, 70.0 + speed_fraction * 14.0, 1.0 - exp(-3.0 * delta))

## Steam from street vents and smoke from wrecked or badly damaged vehicles.
func _update_steam(delta: float) -> void:
	_steam_timer -= delta
	if _steam_timer > 0.0:
		return
	_steam_timer = 0.18
	var eye: Vector3 = player.global_position if phase != Phase.MENU else chase.global_position
	for vent: Vector3 in world.steam_vents:
		if vent.distance_to(eye) < 80.0:
			effects.call("steam", vent)
	for ride: FastCar in cars:
		if (ride.disabled or ride.health < ride.max_health * 0.35) and ride.global_position.distance_to(eye) < 90.0:
			var hull: Vector3 = ride.spec["hull"]
			effects.call("smoke", ride.global_transform * Vector3(0, hull.y * 0.7, -hull.z * 0.38))

## Laser sight: a red dot where the hip-fire aim lands and a faint beam from the muzzle.
## Visible to everyone in multiplayer, which is the attachment's trade-off.
func _update_laser() -> void:
	if not is_instance_valid(laser_dot):
		var red: StandardMaterial3D = StandardMaterial3D.new()
		red.albedo_color = Color(1.0, 0.12, 0.08)
		red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		laser_dot = MeshInstance3D.new()
		laser_dot.mesh = SphereMesh.new()
		(laser_dot.mesh as SphereMesh).radius = 0.025
		(laser_dot.mesh as SphereMesh).height = 0.05
		laser_dot.material_override = red
		laser_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(laser_dot)
		var beam_material: StandardMaterial3D = red.duplicate()
		beam_material.albedo_color = Color(1.0, 0.15, 0.1, 0.28)
		beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		laser_beam = MeshInstance3D.new()
		laser_beam.mesh = BoxMesh.new()
		(laser_beam.mesh as BoxMesh).size = Vector3(0.004, 0.004, 1.0)
		laser_beam.material_override = beam_material
		laser_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(laser_beam)
	var armed: bool = not player.in_vehicle or player.seat_can_shoot
	var show: bool = phase == Phase.LIVE and not paused and armed and not player.is_dead() and bool(player.weapon_stats().get("laser", false)) and not player.is_scoped()
	laser_dot.visible = false
	laser_beam.visible = false
	if not show:
		return
	var origin: Vector3 = player.camera.global_position
	var query := PhysicsRayQueryParameters3D.create(origin, origin - player.camera.global_basis.z * 120.0)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var point: Vector3 = hit.position
	laser_dot.global_position = point + (hit.normal as Vector3) * 0.02
	laser_dot.visible = true
	var start: Vector3 = player.muzzle_position()
	var length: float = start.distance_to(point)
	if length > 0.2:
		laser_beam.visible = true
		laser_beam.global_position = (start + point) * 0.5
		laser_beam.scale = Vector3(1, 1, length)
		laser_beam.look_at(point, Vector3.UP if absf((point - start).normalized().y) < 0.98 else Vector3.RIGHT)

func _on_car_crashed(strength: float, ride: FastCar) -> void:
	if ride != vehicle:
		return
	_rumble(0.4, clampf(strength * 0.08, 0.2, 1.0), 0.3)
	sfx.play("crash", clampf(1.25 - strength * 0.025, 0.7, 1.2), clampf(-12.0 + strength * 1.2, -12.0, 2.0))
	_shake = minf(0.4, strength * 0.035)
	# A hard hit throws you off a motorcycle.
	if ride.is_bike() and strength > 11.0:
		_exit_vehicle(true)
		player.velocity = Vector3.ZERO
		player.take_damage(clampf(strength * 1.6, 15.0, 45.0), ride.global_position)
		_message("Thrown off the bike!", 2.5)
	elif strength > 6.0:
		_message("That one will buff out.", 2.0)

func _on_vehicle_wrecked(ride: FastCar) -> void:
	if ride == vehicle:
		_message("The engine is dead. Get out and find another ride.", 4.0)
	sfx.play_at("crash", ride.global_position, 0.7)

func _build_audio() -> void:
	engine_player = _loop_player("engine")
	skid_player = _loop_player("skid")
	horn_player = _loop_player("horn")
	ambience_player = _loop_player("ambience")
	ambience_player.volume_db = sfx.call("master_db", -17.0)
	ambience_player.play()

func _loop_player(sound: String) -> AudioStreamPlayer:
	var stream_player := AudioStreamPlayer.new()
	stream_player.stream = sfx.call("stream", sound)
	add_child(stream_player)
	return stream_player

func _stop_loops() -> void:
	if not is_instance_valid(engine_player): return
	engine_player.stop()
	skid_player.stop()
	horn_player.stop()

func _update_vehicle_audio(delta: float) -> void:
	var running: bool = vehicle != null and (vehicle.occupied or vehicle.autopilot) and not vehicle.disabled and phase == Phase.LIVE and not paused
	if not running:
		if engine_player.playing: _stop_loops()
		return
	if not engine_player.playing:
		engine_player.play()
	var speed: float = absf(vehicle.longitudinal_speed)
	var shifts: Array[float] = [0.0, 6.5, 12.5, 19.0, 25.5, 33.0]
	var gear: int = 0
	while gear < 4 and speed > shifts[gear + 1]:
		gear += 1
	var in_gear: float = clampf((speed - shifts[gear]) / (shifts[gear + 1] - shifts[gear]), 0.0, 1.0)
	var target_rpm: float = (0.12 if gear == 0 else 0.34) + in_gear * (0.88 if gear == 0 else 0.62)
	target_rpm = maxf(target_rpm, 0.1 + absf(vehicle.throttle_input) * (0.35 if speed < 2.0 else 0.0))
	_rpm = lerpf(_rpm, target_rpm, 1.0 - exp(-7.0 * delta))
	engine_player.pitch_scale = (0.6 + _rpm * 1.3) * float(vehicle.spec.get("engine_pitch", 1.0))
	engine_player.volume_db = sfx.call("master_db", -11.0 + absf(vehicle.throttle_input) * 4.0 + _rpm * 3.0)
	var sliding: bool = vehicle.is_on_floor() and (absf(vehicle.slip) > 2.4 or (vehicle.handbrake_on and vehicle.speed_kph > 12.0))
	if sliding:
		if not skid_player.playing: skid_player.play()
		skid_player.volume_db = sfx.call("master_db", -16.0 + clampf(absf(vehicle.slip), 0.0, 8.0) * 1.3)
		skid_player.pitch_scale = 0.85 + clampf(vehicle.speed_kph / 120.0, 0.0, 0.4)
		# Lay a mark every half metre so the trail is continuous at any speed.
		if _last_skid == Vector3.INF or _last_skid.distance_to(vehicle.global_position) > 0.45:
			_last_skid = vehicle.global_position
			for contact: Vector3 in vehicle.rear_contacts():
				effects.call("skid", contact, vehicle.velocity)
			if randf() < 0.15:
				effects.call("smoke", vehicle.rear_contacts()[randi() % 2])
	else:
		_last_skid = Vector3.INF
		if skid_player.playing:
			skid_player.stop()

# --- Street tips -------------------------------------------------------------------

## Arms a tip to ring `delay` seconds into the live round (negative: never).
func _reset_tip(delay: float) -> void:
	tip_state = "idle"
	tip_timer = delay
	tip_site = {}
	if is_instance_valid(stash_mesh):
		stash_mesh.visible = false

func _tick_tip(delta: float) -> void:
	match tip_state:
		"idle":
			if tip_timer < 0.0:
				return
			tip_timer -= delta
			if tip_timer <= 0.0:
				_ring_tip()
		"ringing":
			tip_timer -= delta
			_ring_clock -= delta
			if _ring_clock <= 0.0:
				_ring_clock = 1.6
				sfx.play_at("ring", tip_phone + Vector3(0, 1.5, 0))
			if tip_timer <= 0.0:
				tip_state = "done"
				_message("The payphone stopped ringing. Someone else took that call.", 3.0)
		"active":
			tip_timer -= delta
			if tip_timer <= 0.0:
				tip_state = "done"
				stash_mesh.visible = false
				_message("Too slow: the stash at %s is gone." % tip_site["name"], 4.0)

## A payphone near the player starts ringing (close enough to hear, far enough to choose).
func _ring_tip() -> void:
	if world.payphones.is_empty():
		tip_state = "done"
		return
	var best: Vector3 = world.payphones[0]
	var best_score: float = INF
	for phone: Vector3 in world.payphones:
		var distance: float = _flat_distance(phone, player.global_position)
		var score: float = absf(distance - 45.0)
		if score < best_score:
			best_score = score
			best = phone
	tip_phone = best
	tip_state = "ringing"
	tip_timer = 30.0
	_ring_clock = 0.0
	_message("A payphone is ringing on the street (blue on the radar). Answer it, or leave it.", 5.0)

## Answering the phone, grabbing the stash and banking it at HQ. True if it handled E.
func _tip_interact() -> bool:
	if tip_state == "ringing" and _flat_distance(player.global_position, tip_phone) < 2.8:
		var sites: Array[Dictionary] = []
		for landmark: Dictionary in world.landmarks:
			var distance: float = _flat_distance(landmark["at"], player.global_position)
			if bool(landmark["neutral"]) and str(landmark["name"]) != "UNION EXCHANGE" and str(landmark["name"]) != "ARMORY" and distance > 60.0 and distance < 220.0:
				sites.append(landmark)
		if sites.is_empty():
			sites.append({"name": "PIER 9", "at": Vector3(-10, 0, -188)})
		tip_site = sites[randi() % sites.size()]
		tip_state = "active"
		tip_timer = TIP_WINDOW
		_place_stash(tip_site["at"])
		sfx.play("phone_pickup")
		if is_inside_tree():
			get_tree().create_timer(2.6).timeout.connect(func(): sfx.play("phone_hangup"))
		_message("Voice on the line: \"There's a bag at %s. Nobody's watching it. Yet.\" You have %d seconds." % [tip_site["name"], int(TIP_WINDOW)], 7.0)
		return true
	if tip_state == "active" and is_instance_valid(stash_mesh) and stash_mesh.visible and player.global_position.distance_to(stash_mesh.global_position) < 2.8:
		tip_state = "carried"
		stash_mesh.visible = false
		sfx.play("cash_bundle")
		_message("Stash grabbed. Bank it at your HQ; if you drop, it's gone.", 4.0)
		return true
	if tip_state == "carried" and _flat_distance(player.position, HOME) < 4.5:
		tip_state = "done"
		cash = mini(cash + TIP_VALUE, 16000)
		sfx.play("cash_riffle")
		sfx.play("cash")
		_message("Stash banked: +$%s. The contract still needs the case." % _money(TIP_VALUE), 4.0)
		return not carrying
	return false

func _tip_prompt() -> String:
	if tip_state == "ringing" and _flat_distance(player.global_position, tip_phone) < 2.8:
		return "[%s]  ANSWER THE PAYPHONE" % _glyph("interact")
	if tip_state == "active" and is_instance_valid(stash_mesh) and stash_mesh.visible and player.global_position.distance_to(stash_mesh.global_position) < 2.8:
		return "[%s]  GRAB THE STASH" % _glyph("interact")
	if tip_state == "carried" and _flat_distance(player.position, HOME) < 4.5:
		return "[%s]  BANK THE STASH  /  $%s" % [_glyph("interact"), _money(TIP_VALUE)]
	return ""

func _place_stash(at: Vector3) -> void:
	if not is_instance_valid(stash_mesh):
		stash_mesh = Node3D.new()
		add_child(stash_mesh)
		var bag := MeshInstance3D.new()
		bag.mesh = MeshKit.rounded_box(Vector3(0.7, 0.34, 0.34), 0.12, 2)
		var canvas_material := StandardMaterial3D.new()
		canvas_material.albedo_color = Color(0.16, 0.2, 0.14)
		canvas_material.roughness = 0.95
		bag.material_override = canvas_material
		stash_mesh.add_child(bag)
		var label := Label3D.new()
		label.text = "STASH"
		label.position.y = 1.6
		label.font_size = 36
		label.modulate = Color("7fb1ff")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stash_mesh.add_child(label)
	stash_mesh.global_position = at + Vector3(randf_range(-2.0, 2.0), 0.35, randf_range(-2.0, 2.0))
	stash_mesh.visible = true

# --- HUD ---------------------------------------------------------------------

func _update_hud() -> void:
	hud.visible = phase != Phase.MENU
	if not hud.visible:
		return
	var seconds: int = maxi(0,int(ceil(time_left)))
	var stats: Dictionary = player.weapon_stats()
	if online.active:
		online.update_hud()
	elif free_roam:
		top_left.text = "%s    /    FREE ROAM" % Factions.get_crew(crew)["name"]
		top_center.text = "ARMORY OPEN"
		top_center.add_theme_color_override("font_color", TEAL)
		top_right.text = "NO CLOCK  /  NO WALLET"
		objective_label.text = "FREE ROAM  /  EXPLORE & TEST THE ARSENAL"
		marker_label.text = "ARMORY  ·  %dm       LONG RANGE  ·  %dm       EXCHANGE  ·  %dm" % [_flat_distance(player.position, ArmoryScript.RACK), _flat_distance(player.position, ArmoryScript.LONG_LINE), _flat_distance(player.position, DEAL)]
		var accuracy: int = int(round(100.0 * shots_hit / maxf(shots_fired, 1)))
		var best: String = "    RACK BEST %.2fs" % rack_best if rack_best > 0.0 else "    PLATE RACK: DROP ALL 5 FAST"
		stats_label.text = "SHOTS %d    HITS %d    ACCURACY %d%%%s%s" % [shots_fired, shots_hit, accuracy, best, "    INVULNERABLE" if player.invulnerable else ""]
	elif phase == Phase.BUY:
		var buy_seconds: int = maxi(0, int(ceil(buy_time_left)))
		top_left.text = "%s    /    ROUND %02d" % [Factions.get_crew(crew)["name"], round_number]
		top_center.text = "BUY  0:%02d" % buy_seconds
		top_center.add_theme_color_override("font_color", GOLD)
		top_right.text = "$%s" % _money(cash)
		objective_label.text = "00  /  BUY PHASE  ·  DOORS OPEN IN %ds" % buy_seconds
		marker_label.text = "%s  BUY MENU       %s  PAUSE       THE HQ DOORS ARE LOCKED UNTIL THE ROUND GOES LIVE" % [_glyph("buy"), _glyph("escape")]
		stats_label.text = ""
	else:
		top_left.text = "%s    /    ROUND %02d" % [Factions.get_crew(crew)["name"], round_number]
		top_center.text = "%02d:%02d" % [seconds/60,seconds%60]
		top_center.add_theme_color_override("font_color", RED if seconds <= 30 else INK)
		top_right.text = "$%s" % _money(cash)
		objective_label.text = "02  /  BRING THE CASE HOME TO YOUR HQ" if carrying else "01  /  COLLECT THE BRIEFCASE AT THE EXCHANGE"
		var destination := HOME if carrying else case_mesh.position
		marker_label.text = "%s  ·  %dm" % ["HQ (TEAL)" if carrying else "EXCHANGE (AMBER)",_flat_distance(player.position,destination)]
		stats_label.text = "HOSTILE DEAL" if violence else ("PAID  /  CASE IS YOURS" if paid else "")
		if tip_state == "ringing":
			stats_label.text += ("    " if not stats_label.text.is_empty() else "") + "A PAYPHONE IS RINGING NEARBY (BLUE)"
		elif tip_state == "active":
			stats_label.text += ("    " if not stats_label.text.is_empty() else "") + "TIP: STASH AT %s  ·  %ds  ·  %dm" % [tip_site["name"], int(ceil(tip_timer)), _flat_distance(player.position, tip_site["at"])]
		elif tip_state == "carried":
			stats_label.text += ("    " if not stats_label.text.is_empty() else "") + "CARRYING THE STASH  ·  BANK IT AT YOUR HQ  /  $%s" % _money(TIP_VALUE)
	vitals_label.text = "HEALTH  %d        ARMOR  %d" % [ceili(player.health), ceili(player.armor)]
	if vehicle != null and (not player.seat_can_shoot):
		weapon_label.text = "%s   /   %s" % [vehicle.model_name, "WRECKED" if vehicle.disabled else "CONDITION %d%%" % int(round(100.0 * vehicle.health / vehicle.max_health))]
		ammo_label.text = "%d KM/H" % int(absf(vehicle.speed_kph))
		var gear_text: String = "R" if vehicle.longitudinal_speed < -0.3 else ("N" if absf(vehicle.longitudinal_speed) < 0.3 and absf(vehicle.throttle_input) < 0.1 else "D")
		slots_label.text = "%s%s" % [gear_text, "    HANDBRAKE" if vehicle.handbrake_on else ""]
	else:
		var fitted: String = player.attachment_summary(player.weapon_id)
		var seat_text: String = ""
		if vehicle != null:
			seat_text = "%s  /  %s   ·   " % [vehicle.model_name, vehicle.seat_info(seat)["name"]]
		weapon_label.text = seat_text + str(stats["name"]) + ("   /   " + fitted if not fitted.is_empty() else "")
		var reserve_text: String = "INF" if player.infinite_reserve else str(player.reserve)
		ammo_label.text = "RELOADING" if player.reloading and float(stats.get("per_round", 0.0)) <= 0.0 else "%d  /  %s" % [player.ammo, reserve_text]
		var slots: PackedStringArray = PackedStringArray()
		for index: int in range(FastPlayer.SLOT_ORDER.size()):
			var id: String = player.owned_in_class(FastPlayer.SLOT_ORDER[index])
			if not id.is_empty():
				slots.append(("[%d %s]" if id == player.weapon_id else "%d %s") % [index + 1, FastPlayer.short_name(id)])
		slots_label.text = "   ".join(slots)
	ammo_label.add_theme_color_override("font_color", RED if (vehicle == null or player.seat_can_shoot) and player.ammo == 0 else INK)
	fps_label.visible = show_fps
	fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	prompt_label.text = ""
	hint_label.text = ""
	if (phase == Phase.LIVE or phase == Phase.BUY) and not paused:
		if phase == Phase.BUY:
			hint_label.text = "%s BUY MENU    %s LOOK    %s WEAPONS    WEAPONS STAY HOLSTERED UNTIL THE DOORS OPEN" % [_glyph("buy"), _glyph("look"), _glyph("weapons")]
		elif _driving() and not driveby:
			hint_label.text = "%s DRIVE    %s STEER    %s LOOK    %s HANDBRAKE    %s ONE-HANDED FIRE    %s SEATS" % [_glyph("drive"), _glyph("steer"), _glyph("look"), _glyph("handbrake"), _glyph("driveby_aim"), _glyph("seat")]
		elif vehicle != null:
			hint_label.text = "%s FIRE    %s AIM    %s RELOAD    %s WEAPONS    %s CHANGE SEAT    %s EXIT" % [_glyph("driveby_fire") if driveby else _glyph("fire"), _glyph("aim"), _glyph("reload"), _glyph("weapons"), _glyph("seat"), _glyph("interact")]
		else:
			hint_label.text = "%s SPRINT    %s CROUCH    %s AIM    %s RELOAD    %s WEAPONS    %s MAP    %s MENU" % [_glyph("sprint"), _glyph("crouch"), _glyph("aim"), _glyph("reload"), _glyph("weapons"), _glyph("map"), _glyph("escape")]
		if phase == Phase.LIVE:
			prompt_label.text = _prompt_text()
	prompt_panel.visible = not prompt_label.text.is_empty()

func _prompt_text() -> String:
	if player.is_dead():
		return "RESPAWNING..." if free_roam or online.active else ""
	if online.active and vehicle == null:
		var online_prompt: String = online.prompt_text()
		if not online_prompt.is_empty():
			return online_prompt
	if vehicle != null:
		if absf(vehicle.speed_kph) > 8.0:
			return "[%s]  ASK THE WHEELMAN TO PULL OVER" % _glyph("interact") if seat != 0 and vehicle.autopilot else ""
		return "[%s]  EXIT    [%s]  CHANGE SEAT" % [_glyph("interact"), _glyph("seat")]
	if not free_roam:
		var tip_prompt: String = _tip_prompt()
		if not tip_prompt.is_empty():
			return tip_prompt
		if carrying and _flat_distance(player.position,HOME) < 4.5:
			return "[%s]  DELIVER BRIEFCASE  /  $2,600" % _glyph("interact")
		if not carrying and case_mesh.visible and player.position.distance_to(case_mesh.position) < 3.1:
			return ("[%s]  COLLECT BRIEFCASE" if paid or violence else "[%s]  NEGOTIATE THE EXCHANGE") % _glyph("interact")
		if _at_buy_station():
			return "[%s]  HQ SUPPLY COUNTER  /  PURCHASES OPEN, NO REFUNDS" % _glyph("buy")
	if _near_rack():
		return "[%s]  REARM    [%s]  GUNSMITH & ARSENAL" % [_glyph("interact"), _glyph("gunsmith")] if free_roam else "ARMORY CLOSED DURING CONTRACTS"
	var shop_door: int = _shop_door_in_reach()
	if shop_door >= 0:
		var door: Dictionary = world.interactable_doors[shop_door]
		if world.is_door_locked(shop_door):
			return "RANGE CLOSED DURING MATCHES  /  %s" % str(door["label"]).replace("  ", " ")
		var verb: String = ("CLOSE THE SHUTTER" if bool(door["open"]) else "RAISE THE SHUTTER") if str(door["kind"]) == "garage" else ("CLOSE THE DOOR" if bool(door["open"]) else "OPEN THE DOOR")
		return "[%s]  %s  /  %s" % [_glyph("interact"), verb, str(door["label"]).replace("  ", " ")]
	var nearest: FastCar = _nearest_car(CENTRE_REACH)
	if nearest != null:
		var drive: String = ("DRIVE" if not nearest.is_bike() else "RIDE") if nearest.seat_free(0) else "GET IN"
		var ride: String = "    [%s]  %s" % [_glyph("seat"), "PILLION GUNNER" if nearest.is_bike() else "RIDE AS GUNNER"] if nearest.nearest_free_seat(player.global_position, true) >= 0 else ""
		return "[%s]  %s %s%s%s" % [_glyph("interact"), drive, nearest.model_name, ride, "    (WRECKED)" if nearest.disabled else ""]
	if player.ammo == 0 and not player.reloading:
		return "[%s]  RELOAD" % _glyph("reload")
	return ""

const GRADE_SHADER: String = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain = 0.04;
uniform float saturation = 0.9;
uniform float contrast = 1.06;
uniform float vignette = 0.34;
void fragment() {
	vec3 colour = texture(screen_tex, SCREEN_UV).rgb;
	float luma = dot(colour, vec3(0.299, 0.587, 0.114));
	colour = mix(vec3(luma), colour, saturation);
	colour = (colour - 0.5) * contrast + 0.5;
	// Split tone: cool shadows, warm sodium highlights.
	colour *= mix(vec3(0.94, 0.97, 1.07), vec3(1.06, 1.0, 0.92), smoothstep(0.15, 0.85, luma));
	float noise = fract(sin(dot(floor(SCREEN_UV / SCREEN_PIXEL_SIZE) + fract(TIME * 7.13) * 91.7, vec2(12.9898, 78.233))) * 43758.5453);
	colour += (noise - 0.5) * grain;
	vec2 offset = SCREEN_UV - 0.5;
	colour *= 1.0 - dot(offset, offset) * vignette * 1.6;
	COLOR = vec4(clamp(colour, 0.0, 1.0), 1.0);
}
"""

func _build_ui() -> void:
	# The grade layer sits between the 3D view and the HUD, so text stays crisp.
	var grade_layer := CanvasLayer.new()
	grade_layer.layer = 1
	add_child(grade_layer)
	grade_rect = ColorRect.new()
	grade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grade_shader := Shader.new()
	grade_shader.code = GRADE_SHADER
	var grade_material := ShaderMaterial.new()
	grade_material.shader = grade_shader
	grade_rect.material = grade_material
	grade_layer.add_child(grade_rect)
	var canvas := CanvasLayer.new()
	canvas.layer = 2
	add_child(canvas)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	hud.add_child(overlay)
	crosshair = overlay
	var bar := ColorRect.new()
	bar.color = Color(0.04,0.07,0.08,0.88)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 56
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bar)
	top_left = _hud_label(Vector2(28,17),18,INK)
	top_center = _hud_label(Vector2(0,15),21,INK)
	top_center.size.x = 1280
	top_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_right = _hud_label(Vector2(0,17),18,GOLD)
	top_right.size.x = 1252
	top_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	objective_label = _hud_label(Vector2(28,74),22,GOLD)
	marker_label = _hud_label(Vector2(28,106),15,TEAL)
	stats_label = _hud_label(Vector2(28,128),14,MUTED)
	feed_label = _hud_label(Vector2(28,540),16,GOLD)
	feed_label.size.x = 700
	feed_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vitals_label = _hud_label(Vector2(28,604),15,INK)
	weapon_label = _hud_label(Vector2(0,596),15,MUTED)
	weapon_label.size.x = 1252
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label = _hud_label(Vector2(0,612),38,INK)
	ammo_label.size.x = 1252
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slots_label = _hud_label(Vector2(0,664),13,MUTED)
	slots_label.size.x = 1252
	slots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label = _hud_label(Vector2(0,694),12,MUTED)
	hint_label.size.x = 1280
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fps_label = _hud_label(Vector2(0,258),13,MUTED)
	fps_label.size.x = 1252
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	prompt_panel = PanelContainer.new()
	prompt_panel.add_theme_stylebox_override("panel",_style(Color(0.035,0.065,0.075,0.82),Color("53645d"),10))
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(prompt_panel)
	prompt_label = Label.new()
	prompt_label.add_theme_font_size_override("font_size",16)
	prompt_label.add_theme_color_override("font_color",INK)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_panel.add_child(prompt_label)
	prompt_panel.resized.connect(func(): prompt_panel.position = Vector2((1280 - prompt_panel.size.x) * 0.5, 452))
	prompt_label.resized.connect(func(): prompt_panel.reset_size())
	mini_map = Control.new()
	mini_map.position = Vector2(1072,70)
	mini_map.size = Vector2(180,180)
	mini_map.clip_contents = true
	mini_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini_map.draw.connect(_draw_map)
	hud.add_child(mini_map)
	accent_bar = ColorRect.new()
	accent_bar.position = Vector2(0, 56)
	accent_bar.size = Vector2(1280, 3)
	accent_bar.color = Factions.color(crew)
	accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(accent_bar)
	full_map = Control.new()
	full_map.position = Vector2(40, 64)
	full_map.size = Vector2(1200, 650)
	full_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full_map.visible = false
	full_map.draw.connect(_draw_full_map)
	canvas.add_child(full_map)
	menu = PanelContainer.new()
	menu.position = Vector2(66,30)
	menu.custom_minimum_size = Vector2(610,660)
	menu.add_theme_stylebox_override("panel",_style(Color(0.035,0.065,0.075,0.96),Color("45514c"),30))
	canvas.add_child(menu)
	menu_scroll = ScrollContainer.new()
	menu_scroll.custom_minimum_size = Vector2(550,600)
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_scroll.follow_focus = true
	menu.add_child(menu_scroll)
	menu_stack = VBoxContainer.new()
	menu_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_stack.add_theme_constant_override("separation",10)
	menu_scroll.add_child(menu_stack)

func _radar_point(world_position: Vector3) -> Vector2:
	# North-up radar centred on the player (or their vehicle).
	var offset: Vector2 = Vector2(world_position.x - player.global_position.x, world_position.z - player.global_position.z)
	return mini_map.size * 0.5 + offset * (mini_map.size.x * 0.5 / RADAR_RANGE)

func _facing() -> Vector3:
	return -vehicle.global_basis.z if vehicle != null else -player.global_basis.z

func _draw_map() -> void:
	var scale: float = mini_map.size.x * 0.5 / RADAR_RANGE
	mini_map.draw_rect(Rect2(Vector2.ZERO, mini_map.size), Color(0.07, 0.16, 0.21, 0.94))
	_draw_city(mini_map, _radar_point, scale, false)
	_draw_gps(mini_map, _radar_point, 2.5)
	online.draw_markers(mini_map, _radar_point, true)
	var center: Vector2 = mini_map.size * 0.5
	if free_roam:
		_radar_marker(ArmoryScript.RACK, TEAL)
		_radar_marker(ArmoryScript.LONG_LINE, GOLD)
	else:
		_radar_marker(HOME, TEAL)
		if not carrying and case_mesh.visible:
			_radar_marker(case_mesh.position, GOLD)
		if tip_state == "ringing":
			_radar_marker(tip_phone, Color("7fb1ff"))
		elif tip_state == "active":
			_radar_marker(tip_site["at"], Color("7fb1ff"))
	var facing: Vector3 = _facing()
	_draw_arrow(mini_map, center, Vector2(facing.x, facing.z), 7.0, Color.WHITE)
	mini_map.draw_rect(Rect2(Vector2.ZERO, mini_map.size), Factions.color(crew).darkened(0.2), false, 2.0)
	mini_map.draw_string(ThemeDB.fallback_font, Vector2(6, mini_map.size.y - 6), _district_at(player.global_position), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.85))

func _radar_marker(at: Vector3, color: Color) -> void:
	# Off-radar objectives pin to the edge so the direction is always readable.
	var point: Vector2 = _radar_point(at)
	var inset: Rect2 = Rect2(Vector2(6, 6), mini_map.size - Vector2(12, 12))
	var clamped: Vector2 = point.clamp(inset.position, inset.end)
	mini_map.draw_circle(clamped, 5.0 if clamped == point else 4.0, color)
	mini_map.draw_arc(clamped, 5.5, 0.0, TAU, 12, Color(0, 0, 0, 0.8), 1.5)

func _draw_arrow(canvas: Control, at: Vector2, direction: Vector2, size: float, color: Color) -> void:
	var tip: Vector2 = direction.normalized() if direction.length() > 0.01 else Vector2.UP
	var side: Vector2 = Vector2(-tip.y, tip.x)
	canvas.draw_colored_polygon(PackedVector2Array([at + tip * size, at - tip * size * 0.6 + side * size * 0.6, at - tip * size * 0.3, at - tip * size * 0.6 - side * size * 0.6]), color)

## Shared by the radar and the full map: water, districts, roads, buildings, vehicles, bots, landmarks.
func _draw_city(canvas: Control, to_screen: Callable, scale: float, labels: bool) -> void:
	world.draw_map(canvas, to_screen, scale)
	for ride: FastCar in cars:
		var at: Vector2 = to_screen.call(ride.global_position)
		var forward: Vector3 = -ride.global_basis.z
		var length: float = 2.0 if ride.is_bike() else 3.0
		canvas.draw_line(at - Vector2(forward.x, forward.z) * length, at + Vector2(forward.x, forward.z) * length, ride.paint_color.lightened(0.2), 2.5 if ride.is_bike() else 3.5)
	for guard: FastGuard in _all_guards():
		if guard.visible and guard.health > 0.0:
			canvas.draw_circle(to_screen.call(guard.global_position), 2.5, RED if guard.hostile else Color(0.75, 0.75, 0.72))
	for crew_id: String in world.crew_spawns:
		var hq: Vector3 = world.crew_spawns[crew_id]["hq"]
		canvas.draw_circle(to_screen.call(hq), 4.0 if not labels else 7.0, Factions.color(crew_id))
	if not labels:
		return
	var font: Font = ThemeDB.fallback_font
	for district: Dictionary in world.districts:
		var at: Vector2 = to_screen.call(district["label_at"])
		var title: String = str(district["name"])
		if str(district["crew"]) != "":
			title += "\n" + str(Factions.get_crew(str(district["crew"]))["name"])
		canvas.draw_multiline_string(font, at - Vector2(90, 0), title, HORIZONTAL_ALIGNMENT_CENTER, 180, 12, -1, (district["color"] as Color).lightened(0.35))
	for landmark: Dictionary in world.landmarks:
		var at: Vector2 = to_screen.call(landmark["at"])
		canvas.draw_rect(Rect2(at - Vector2(2, 2), Vector2(4, 4)), GOLD if bool(landmark["neutral"]) else Color(0.9, 0.9, 0.9))
		canvas.draw_string(font, at + Vector2(5, 4), str(landmark["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.93, 0.86, 0.9))

func _district_at(at: Vector3) -> String:
	return world.district_at(at)

func _full_map_point(world_position: Vector3) -> Vector2:
	var bounds: Rect2 = world.map_bounds()
	var side: float = minf(full_map.size.x - 300.0, full_map.size.y) - 30.0
	var scale: float = side / maxf(bounds.size.x, bounds.size.y)
	var origin: Vector2 = Vector2(300.0 + (full_map.size.x - 300.0 - bounds.size.x * scale) * 0.5, (full_map.size.y - bounds.size.y * scale) * 0.5)
	return origin + (Vector2(world_position.x, world_position.z) - bounds.position) * scale

func _draw_full_map() -> void:
	if not map_open:
		return
	var bounds: Rect2 = world.map_bounds()
	var side: float = minf(full_map.size.x - 300.0, full_map.size.y) - 30.0
	var scale: float = side / maxf(bounds.size.x, bounds.size.y)
	full_map.draw_rect(Rect2(Vector2.ZERO, full_map.size), Color(0.02, 0.03, 0.05, 0.95))
	full_map.draw_rect(Rect2(Vector2(290, 0), full_map.size - Vector2(290, 0)), Color(0.06, 0.15, 0.2, 0.95))
	_draw_city(full_map, _full_map_point, scale, true)
	_draw_gps(full_map, _full_map_point, 3.0)
	online.draw_markers(full_map, _full_map_point, false)
	var facing: Vector3 = _facing()
	_draw_arrow(full_map, _full_map_point(player.global_position), Vector2(facing.x, facing.z), 9.0, Color.WHITE)
	if free_roam:
		full_map.draw_circle(_full_map_point(ArmoryScript.RACK), 5.0, TEAL)
	else:
		full_map.draw_circle(_full_map_point(HOME), 6.0, TEAL)
		if not carrying and case_mesh.visible:
			full_map.draw_circle(_full_map_point(case_mesh.position), 6.0, GOLD)
	var font: Font = ThemeDB.fallback_font
	full_map.draw_string(font, Vector2(24, 44), "PORT HALCYON", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, INK)
	full_map.draw_multiline_string(font, Vector2(24, 76), "Crew turf is tinted in crew colours.
Gold squares: mission landmarks.
White squares: crew landmarks.
Coloured dots: crew HQs.

Meet anywhere: a street, plaza,
shop, rooftop or moving car.
Mission sites hold objectives;
they are not required deal zones.
Use another route when a crew
holds a road or doorway.", HORIZONTAL_ALIGNMENT_LEFT, 260, 13, -1, MUTED)
	var row: float = 300.0
	for crew_id: String in Factions.ORDER:
		var identity: Dictionary = Factions.get_crew(crew_id)
		full_map.draw_circle(Vector2(32, row - 4), 6.0, identity["color"])
		full_map.draw_string(font, Vector2(46, row), "%s  /  %s" % [identity["name"], identity["district"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
		row += 22.0
	full_map.draw_string(font, Vector2(24, full_map.size.y - 24), "%s  CLOSE MAP" % _glyph("map"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)

func _draw_overlay() -> void:
	if phase != Phase.LIVE:
		return
	var size: Vector2 = overlay.size
	var center: Vector2 = size * 0.5
	var font: Font = ThemeDB.fallback_font
	# Vitals bars.
	var bar_width: float = 250.0
	overlay.draw_rect(Rect2(28, 628, bar_width, 9), Color(0, 0, 0, 0.5))
	var health_color: Color = RED if player.health < 35.0 else Color("e9e1cb")
	overlay.draw_rect(Rect2(28, 628, bar_width * player.health / 100.0, 9), health_color)
	overlay.draw_rect(Rect2(28, 641, bar_width, 5), Color(0, 0, 0, 0.5))
	overlay.draw_rect(Rect2(28, 641, bar_width * minf(player.armor, 100.0) / 100.0, 5), Color("7fb1c9"))
	overlay.draw_rect(Rect2(28, 650, bar_width, 3), Color(0, 0, 0, 0.4))
	overlay.draw_rect(Rect2(28, 650, bar_width * player.stamina / 100.0, 3), GOLD if player.stamina > 20.0 else RED)
	if vehicle != null:
		overlay.draw_rect(Rect2(28, 588, bar_width, 4), Color(0, 0, 0, 0.5))
		overlay.draw_rect(Rect2(28, 588, bar_width * vehicle.health / vehicle.max_health, 4), Color("d9a441") if not vehicle.disabled else RED)
	# Damage: red edges plus an arc pointing at the shooter.
	var low_health: float = 0.0
	if player.health < 35.0 and not player.is_dead():
		low_health = (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)) * 0.35
	var edge: float = maxf(damage_flash * 0.55, low_health)
	if edge > 0.01:
		var tint: Color = Color(0.75, 0.05, 0.03, edge)
		for band: int in range(4):
			var thickness: float = 18.0 + band * 22.0
			var alpha_tint: Color = Color(tint.r, tint.g, tint.b, tint.a * (0.45 - band * 0.1))
			overlay.draw_rect(Rect2(0, 0, size.x, thickness), alpha_tint)
			overlay.draw_rect(Rect2(0, size.y - thickness, size.x, thickness), alpha_tint)
			overlay.draw_rect(Rect2(0, 0, thickness, size.y), alpha_tint)
			overlay.draw_rect(Rect2(size.x - thickness, 0, thickness, size.y), alpha_tint)
	var forward: Vector3 = -player.camera.global_basis.z
	forward.y = 0.0
	var right: Vector3 = player.camera.global_basis.x
	right.y = 0.0
	for mark: Dictionary in damage_marks:
		var to_source: Vector3 = (mark["source"] as Vector3) - player.global_position
		var angle: float = atan2(to_source.dot(right.normalized()), to_source.dot(forward.normalized())) - PI * 0.5
		var alpha: float = clampf(float(mark["life"]) / 0.6, 0.0, 1.0)
		overlay.draw_arc(center, 110.0, angle - 0.32, angle + 0.32, 18, Color(0.95, 0.2, 0.12, 0.8 * alpha), 7.0)
	if player.is_dead():
		overlay.draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.0, 0.0, 0.35))
		overlay.draw_string(font, Vector2(0, center.y - 40), "DOWN", HORIZONTAL_ALIGNMENT_CENTER, size.x, 54, RED)
		return
	if (vehicle != null and (not player.seat_can_shoot or chase.current)) or paused:
		return
	if player.is_scoped():
		_draw_scope(center, size)
	else:
		_draw_crosshair(center, size)
	if hit_timer > 0.0:
		var color: Color = Color.WHITE
		var reach: float = 10.0
		if hit_kind == "head":
			color = GOLD
			reach = 13.0
		elif hit_kind == "kill":
			color = RED
			reach = 15.0
		color.a = clampf(hit_timer / 0.12, 0.0, 1.0)
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				overlay.draw_line(center + Vector2(sx, sy) * 5.0, center + Vector2(sx, sy) * reach, color, 2.0, true)

func _draw_crosshair(center: Vector2, size: Vector2) -> void:
	var color: Color = Color(1, 1, 1, 0.85)
	var aim: float = player.ads_blend
	var spread: float = player.current_spread()
	var gap: float = 3.0 + tan(deg_to_rad(spread)) / tan(deg_to_rad(player.camera.fov * 0.5)) * size.y * 0.5
	var pellets: bool = int(player.weapon_stats().get("pellets", 1)) > 1
	overlay.draw_circle(center, 1.4, color)
	if aim > 0.65 and not pellets:
		return
	var fade: Color = Color(color.r, color.g, color.b, color.a * (1.0 - aim * 0.6))
	if pellets:
		overlay.draw_arc(center, gap, 0.0, TAU, 32, fade, 1.5, true)
		return
	for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		overlay.draw_line(center + direction * gap, center + direction * (gap + 7.0), fade, 2.0)

func _draw_scope(center: Vector2, size: Vector2) -> void:
	var radius: float = size.y * 0.44
	var black: Color = Color(0.01, 0.01, 0.01)
	overlay.draw_arc(center, radius + 400.0, 0.0, TAU, 96, black, 800.0)
	overlay.draw_arc(center, radius, 0.0, TAU, 96, Color(0.05, 0.05, 0.05), 6.0, true)
	var reticle: Color = Color(0.02, 0.02, 0.02, 0.95)
	overlay.draw_line(center - Vector2(radius, 0), center - Vector2(18, 0), reticle, 2.0)
	overlay.draw_line(center + Vector2(18, 0), center + Vector2(radius, 0), reticle, 2.0)
	overlay.draw_line(center - Vector2(0, radius), center - Vector2(0, 18), reticle, 2.0)
	overlay.draw_line(center + Vector2(0, 18), center + Vector2(0, radius), reticle, 2.0)
	overlay.draw_line(center - Vector2(radius, 0), center - Vector2(radius * 0.55, 0), reticle, 6.0)
	overlay.draw_line(center + Vector2(radius * 0.55, 0), center + Vector2(radius, 0), reticle, 6.0)
	overlay.draw_line(center + Vector2(0, radius * 0.55), center + Vector2(0, radius), reticle, 6.0)
	for mark: int in range(1, 5):
		overlay.draw_circle(center + Vector2(0, mark * 16.0 + 6.0), 1.6, reticle)
		overlay.draw_circle(center + Vector2(mark * 16.0 + 6.0, 0), 1.6, reticle)
		overlay.draw_circle(center - Vector2(mark * 16.0 + 6.0, 0), 1.6, reticle)
	overlay.draw_circle(center, 1.6, Color(0.9, 0.15, 0.1))

func _hud_label(pos:Vector2,font_size:int,color:Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	# Outlines, not drop shadows: shadowed text breaks 2D batching in the
	# Compatibility renderer (~2 draw calls per glyph instead of ~4 per label).
	label.add_theme_color_override("font_outline_color",Color(0,0,0,0.72))
	label.add_theme_constant_override("outline_size",4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(label)
	return label

func _clear_menu() -> void:
	_menu_back = Callable()
	for child:Node in menu_stack.get_children():
		menu_stack.remove_child(child)
		child.queue_free()
	menu.size = Vector2(610,660)
	menu_scroll.scroll_vertical = 0
	buy_status = null
	buy_detail = null
	buy_buttons.clear()

func _heading(title:String,kicker:String) -> void:
	_text(kicker,13,TEAL)
	_text(title,38,INK)
	var line := HSeparator.new()
	menu_stack.add_child(line)

func _text(content:String,font_size:int=18,color:Color=Color("d0d5cc")) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 540
	menu_stack.add_child(label)
	return label

func _style(background:Color,border:Color,padding:int=16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

func _button(content:String,callback:Callable,disabled:bool=false) -> Button:
	var button := _make_button(content, callback, disabled, 16, 40)
	menu_stack.add_child(button)
	return button

## Compact button for tab rows (not added to the menu stack).
func _small_button(content: String, callback: Callable, active: bool) -> Button:
	var button := _make_button(content, callback, false, 12, 30)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if active:
		button.add_theme_stylebox_override("normal", _style(Color("4c5040"), GOLD, 6))
	return button

func _make_button(content: String, callback: Callable, disabled: bool, font_size: int, height: int) -> Button:
	var button := Button.new()
	button.text = content
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = height
	var pad: int = 12 if height >= 36 else 6
	button.add_theme_font_size_override("font_size",font_size)
	button.add_theme_color_override("font_color",INK)
	button.add_theme_color_override("font_disabled_color",Color("5d6866"))
	button.add_theme_stylebox_override("normal",_style(Color("1c2d30"),Color("53645d"),pad))
	button.add_theme_stylebox_override("hover",_style(Color("35453d"),GOLD,pad))
	button.add_theme_stylebox_override("focus",_style(Color("35453d"),GOLD,pad))
	button.add_theme_stylebox_override("pressed",_style(Color("4c5040"),GOLD,pad))
	button.add_theme_stylebox_override("disabled",_style(Color("142023"),Color("2c3634"),pad))
	button.disabled = disabled
	button.pressed.connect(func(): sfx.play("ui"))
	button.pressed.connect(callback)
	return button

func _build_case() -> void:
	case_mesh = Node3D.new()
	add_child(case_mesh)
	case_mesh.position = DEAL + Vector3(0,0.55,0)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7,0.45,0.22)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("d5a356")
	mesh.material_override = mat
	case_mesh.add_child(mesh)
	var handle := MeshInstance3D.new()
	var handle_box := BoxMesh.new()
	handle_box.size = Vector3(0.22,0.06,0.05)
	handle.mesh = handle_box
	handle.material_override = mat
	handle.position.y = 0.26
	case_mesh.add_child(handle)
	var label := Label3D.new()
	label.text = "THE EXCHANGE"
	label.position.y = 2.5
	label.font_size = 40
	label.modulate = GOLD
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	case_mesh.add_child(label)

func _capture_views() -> void:
	# Repeatable render review without simulating desktop input.
	pause_on_focus_loss = false
	var folder: String = ProjectSettings.globalize_path("res://../../work")
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder + "/title.png")
	_start_round()
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder + "/buy.png")
	_start_live()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder + "/gameplay.png")
	_enter_vehicle(cars[0], 0)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder + "/driving.png")
	_exit_vehicle(true)
	_start_free_roam()
	pause_on_focus_loss = false
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder + "/freeroam.png")
	get_tree().quit()
