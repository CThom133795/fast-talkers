class_name FastPlayer
extends CharacterBody3D
## Asset-free first-person controller. Weapon rays are resolved by the world.
## Feet are at the node origin; the player's eye height is 1.62 metres.
## Shots leave the camera centre (plus weapon spread), so camera recoil moves
## the crosshair and the bullet together: aim and impact always agree.
## In a vehicle seat the same controller aims out of the window (or off the back of a
## bike): look is clamped to the seat's arc and the vehicle carries the body.

signal shot_fired(origin: Vector3, direction: Vector3, damage: float)
signal weapon_fired(weapon_id: String)
signal weapon_event(event: String)
signal died
signal damaged(amount: float, source: Vector3)
signal footstep(loud: bool)
signal landed(speed: float)
## Social gesture changed (hands up = weapon away, cannot fire). For replication to others.
signal gesture_changed(hands_up: bool)

const WALK_SPEED: float = 4.3
const SPRINT_SPEED: float = 6.5
const CROUCH_SPEED: float = 2.15
const GROUND_ACCELERATION: float = 23.0
const GROUND_BRAKING: float = 29.0
const AIR_ACCELERATION: float = 5.0
const GRAVITY: float = 22.0
const JUMP_SPEED: float = 4.7
const STAND_HEIGHT: float = 1.8
const CROUCH_HEIGHT: float = 1.15
const BODY_RADIUS: float = 0.30
## Highest curb or single riser the player walks up without jumping (_try_step_up).
const STEP_UP_MAX: float = 0.2
const BASE_FOV: float = 85.0
const STAND_EYE: float = 1.62
const CROUCH_EYE: float = 1.02
## Weapon classes in number-key order (keys 1-5). Every weapon belongs to one class.
const SLOT_ORDER: Array[String] = ["pistol", "smg", "rifle", "shotgun", "marksman"]
const CLASS_LABEL: Dictionary = {"pistol": "PISTOL", "smg": "SMG", "rifle": "RIFLE", "shotgun": "SHOTGUN", "marksman": "MARKSMAN"}
## Variants per class, in display order. The first entry is the class's base weapon.
const VARIANTS: Dictionary = {
	"pistol": ["pistol", "m1911", "revolver"],
	"smg": ["smg", "mac", "tommy"],
	"rifle": ["rifle", "ak"],
	"shotgun": ["shotgun", "double", "auto12"],
	"marksman": ["marksman", "dmr"],
}
const SHORT: Dictionary = {"pistol": "P9", "m1911": ".45", "revolver": ".357", "smg": "VK-5", "mac": "MAC-11", "tommy": "TOMMY",
	"rifle": "M4", "ak": "KV-47", "shotgun": "870", "double": "SAWN-OFF", "auto12": "AUTO-12", "marksman": "M700", "dmr": "BR-58"}
const MeshKit = preload("res://scripts/mesh_kit.gd")
const MeshMerge = preload("res://scripts/mesh_merge.gd")
const SLOTS: Array[String] = ["optic", "muzzle", "underbarrel", "magazine"]
## Every attachment trades something away. Multipliers apply to the weapon's base stats.
## Which weapons take which part is listed per weapon ("mods") in WEAPONS.
const ATTACHMENTS: Dictionary = {
	"reflex": {"slot": "optic", "name": "REFLEX SIGHT", "short": "REFLEX", "price": 300, "fov_delta": -2.0, "unscope": true},
	"holo2x": {"slot": "optic", "name": "2X HOLO SIGHT", "short": "2X HOLO", "price": 450, "fov_scale": 0.62, "ads_time": 1.15},
	"scope4x": {"slot": "optic", "name": "4X SCOPE", "short": "4X", "price": 600, "scope_fov": 22.0, "ads_time": 1.3},
	"suppressor": {"slot": "muzzle", "name": "SUPPRESSOR", "short": "SUPP", "price": 500, "falloff_scale": 0.8, "recoil": 0.95, "quiet": true},
	"compensator": {"slot": "muzzle", "name": "COMPENSATOR", "short": "COMP", "price": 300, "recoil": 0.75, "loud": true},
	"choke": {"slot": "muzzle", "name": "CHOKE", "short": "CHOKE", "price": 250, "spread": 0.65},
	"foregrip": {"slot": "underbarrel", "name": "FOREGRIP", "short": "GRIP", "price": 250, "recoil_yaw": 0.6, "hip_spread": 0.85, "ads_time": 1.05},
	"laser": {"slot": "underbarrel", "name": "LASER SIGHT", "short": "LASER", "price": 300, "hip_spread": 0.7, "laser": true},
	"extended": {"slot": "magazine", "name": "EXTENDED MAG", "short": "EXT MAG", "price": 300, "capacity": 1.5, "reload": 1.15},
	"speed": {"slot": "magazine", "name": "SPEED MAG", "short": "SPEED", "price": 350, "reload": 0.75},
}
## Spread/recoil in degrees. falloff = (start m, end m, minimum multiplier).
## class: key slot. one_hand: usable from a driver's seat or a motorcycle saddle.
## action: "pump" / "bolt" cycle after a shot, "revolver" turns the cylinder, "break" opens to reload.
## weight: movement speed multiplier. Names are original; "pattern" notes the real-world archetype.
const WEAPONS: Dictionary = {
	"pistol": {"name": "P9 SERVICE PISTOL", "class": "pistol", "pattern": "9 mm service pistol", "price": 0, "one_hand": true,
		"capacity": 12, "reserve": 48, "damage": 34.0, "interval": 0.14, "reload": 1.35,
		"automatic": false, "fov": 66.0, "ads_time": 0.13, "pellets": 1, "hip_spread": 1.1, "ads_spread": 0.12,
		"recoil": 1.5, "recoil_yaw": 0.5, "headshot": 2.0, "falloff": Vector3(22.0, 50.0, 0.65), "per_round": 0.0, "scope": false, "sound": "pistol",
		"action": "", "weight": 1.0, "mods": ["reflex", "suppressor", "compensator", "laser", "extended", "speed"],
		"desc": "Issued free every round. Quick to draw, fast follow-up shots."},
	"m1911": {"name": ".45 M1911", "class": "pistol", "pattern": ".45 single-stack", "price": 350, "one_hand": true,
		"capacity": 8, "reserve": 40, "damage": 44.0, "interval": 0.19, "reload": 1.5,
		"automatic": false, "fov": 64.0, "ads_time": 0.14, "pellets": 1, "hip_spread": 1.2, "ads_spread": 0.13,
		"recoil": 2.4, "recoil_yaw": 0.6, "headshot": 2.0, "falloff": Vector3(20.0, 45.0, 0.6), "per_round": 0.0, "scope": false, "sound": "m1911",
		"action": "", "weight": 1.0, "mods": ["reflex", "suppressor", "compensator", "laser", "extended", "speed"],
		"desc": "Eight heavy rounds. Three to the body, two to the head. Punishes misses."},
	"revolver": {"name": ".357 REVOLVER", "class": "pistol", "pattern": ".357 magnum revolver", "price": 650, "one_hand": true,
		"capacity": 6, "reserve": 30, "damage": 58.0, "interval": 0.4, "reload": 2.3,
		"automatic": false, "fov": 60.0, "ads_time": 0.17, "pellets": 1, "hip_spread": 1.5, "ads_spread": 0.07,
		"recoil": 4.4, "recoil_yaw": 0.9, "headshot": 2.2, "falloff": Vector3(30.0, 65.0, 0.7), "per_round": 0.0, "scope": false, "sound": "revolver",
		"action": "revolver", "weight": 1.0, "mods": ["reflex", "laser", "speed"],
		"desc": "Two body shots or one to the head. Slow double action, slow reload."},
	"smg": {"name": "VK-5 SMG", "class": "smg", "pattern": "roller-delayed 9 mm SMG", "price": 1000, "one_hand": false,
		"capacity": 30, "reserve": 120, "damage": 22.0, "interval": 0.075, "reload": 1.9,
		"automatic": true, "fov": 60.0, "ads_time": 0.16, "pellets": 1, "hip_spread": 1.8, "ads_spread": 0.45,
		"recoil": 0.65, "recoil_yaw": 0.35, "headshot": 1.6, "falloff": Vector3(15.0, 38.0, 0.55), "per_round": 0.0, "scope": false, "sound": "smg",
		"action": "", "weight": 1.0, "mods": ["reflex", "holo2x", "suppressor", "compensator", "foregrip", "laser", "extended", "speed"],
		"desc": "Accurate and controllable. The professional's choice at street range."},
	"mac": {"name": "MAC-11 MACHINE PISTOL", "class": "smg", "pattern": "open-bolt machine pistol", "price": 800, "one_hand": true,
		"capacity": 32, "reserve": 128, "damage": 18.0, "interval": 0.05, "reload": 1.6,
		"automatic": true, "fov": 64.0, "ads_time": 0.12, "pellets": 1, "hip_spread": 2.5, "ads_spread": 1.1,
		"recoil": 0.55, "recoil_yaw": 0.8, "headshot": 1.5, "falloff": Vector3(9.0, 26.0, 0.5), "per_round": 0.0, "scope": false, "sound": "mac",
		"action": "", "weight": 1.04, "mods": ["reflex", "suppressor", "laser", "extended"],
		"desc": "1,200 rounds a minute, one hand. The drive-by gun. Useless past 20 m."},
	"tommy": {"name": "CHICAGO TYPEWRITER", "class": "smg", "pattern": ".45 drum-fed SMG", "price": 1400, "one_hand": false,
		"capacity": 50, "reserve": 100, "damage": 26.0, "interval": 0.086, "reload": 3.3,
		"automatic": true, "fov": 58.0, "ads_time": 0.25, "pellets": 1, "hip_spread": 2.0, "ads_spread": 0.5,
		"recoil": 0.95, "recoil_yaw": 0.42, "headshot": 1.7, "falloff": Vector3(16.0, 40.0, 0.6), "per_round": 0.0, "scope": false, "sound": "tommy",
		"action": "", "weight": 0.93, "mods": ["reflex", "compensator", "laser", "speed"],
		"desc": "Fifty-round drum and a built-in foregrip. Heavy, loud and slow to reload."},
	"rifle": {"name": "M4 CARBINE", "class": "rifle", "pattern": "5.56 mm carbine", "price": 1600, "one_hand": false,
		"capacity": 30, "reserve": 90, "damage": 28.0, "interval": 0.08, "reload": 2.1,
		"automatic": true, "fov": 55.0, "ads_time": 0.2, "pellets": 1, "hip_spread": 1.5, "ads_spread": 0.1,
		"recoil": 0.8, "recoil_yaw": 0.3, "headshot": 2.0, "falloff": Vector3(40.0, 90.0, 0.75), "per_round": 0.0, "scope": false, "sound": "rifle",
		"action": "", "weight": 0.97, "mods": ["reflex", "holo2x", "scope4x", "suppressor", "compensator", "foregrip", "laser", "extended", "speed"],
		"desc": "Low, predictable recoil and a fast rate of fire. Two headshots at any range."},
	"ak": {"name": "KV-47 RIFLE", "class": "rifle", "pattern": "7.62 mm Kalashnikov-pattern rifle", "price": 1500, "one_hand": false,
		"capacity": 30, "reserve": 90, "damage": 36.0, "interval": 0.1, "reload": 2.5,
		"automatic": true, "fov": 56.0, "ads_time": 0.23, "pellets": 1, "hip_spread": 1.7, "ads_spread": 0.14,
		"recoil": 1.25, "recoil_yaw": 0.62, "headshot": 2.8, "falloff": Vector3(35.0, 85.0, 0.75), "per_round": 0.0, "scope": false, "sound": "ak",
		"action": "", "weight": 0.96, "mods": ["reflex", "holo2x", "scope4x", "suppressor", "compensator", "foregrip", "laser", "extended", "speed"],
		"desc": "One headshot kills an unarmoured target. Hard-kicking and wanders sideways."},
	"shotgun": {"name": "870 PUMP", "class": "shotgun", "pattern": "12-gauge pump action", "price": 1100, "one_hand": false,
		"capacity": 6, "reserve": 30, "damage": 13.0, "interval": 0.82, "reload": 0.52,
		"automatic": false, "fov": 70.0, "ads_time": 0.2, "pellets": 9, "hip_spread": 4.6, "ads_spread": 3.3,
		"recoil": 4.6, "recoil_yaw": 1.1, "headshot": 1.5, "falloff": Vector3(8.0, 26.0, 0.25), "per_round": 0.52, "scope": false, "sound": "shotgun",
		"action": "pump", "weight": 0.97, "mods": ["reflex", "choke", "foregrip", "laser", "speed"],
		"desc": "Nine pellets, one-shot kill inside 8 m. Shells load one at a time."},
	"double": {"name": "SAWN-OFF", "class": "shotgun", "pattern": "cut-down double barrel", "price": 700, "one_hand": true,
		"capacity": 2, "reserve": 24, "damage": 14.0, "interval": 0.17, "reload": 1.9,
		"automatic": false, "fov": 72.0, "ads_time": 0.12, "pellets": 9, "hip_spread": 5.8, "ads_spread": 4.6,
		"recoil": 5.6, "recoil_yaw": 1.4, "headshot": 1.4, "falloff": Vector3(6.0, 18.0, 0.2), "per_round": 0.0, "scope": false, "sound": "double",
		"action": "break", "weight": 1.02, "mods": [],
		"desc": "Two barrels back to back, one hand. Devastating off the back of a bike."},
	"auto12": {"name": "AUTO-12", "class": "shotgun", "pattern": "semi-automatic 12-gauge", "price": 1500, "one_hand": false,
		"capacity": 7, "reserve": 35, "damage": 11.0, "interval": 0.27, "reload": 0.42,
		"automatic": false, "fov": 68.0, "ads_time": 0.2, "pellets": 8, "hip_spread": 4.2, "ads_spread": 3.0,
		"recoil": 3.4, "recoil_yaw": 0.9, "headshot": 1.5, "falloff": Vector3(9.0, 28.0, 0.25), "per_round": 0.42, "scope": false, "sound": "auto12",
		"action": "", "weight": 0.96, "mods": ["reflex", "choke", "foregrip", "laser", "speed"],
		"desc": "Seven shells as fast as you can pull. Less per pellet than the pump."},
	"marksman": {"name": "M700 BOLT RIFLE", "class": "marksman", "pattern": "bolt-action hunting rifle", "price": 2200, "one_hand": false,
		"capacity": 5, "reserve": 25, "damage": 78.0, "interval": 0.95, "reload": 2.5,
		"automatic": false, "fov": 20.0, "ads_time": 0.28, "pellets": 1, "hip_spread": 3.2, "ads_spread": 0.0,
		"recoil": 3.6, "recoil_yaw": 0.6, "headshot": 2.5, "falloff": Vector3(200.0, 300.0, 1.0), "per_round": 0.0, "scope": true, "sound": "marksman",
		"action": "bolt", "weight": 0.95, "mods": ["reflex", "suppressor", "extended", "speed"],
		"desc": "Scoped. One shot to the head at any range, two to the body."},
	"dmr": {"name": "BR-58 BATTLE RIFLE", "class": "marksman", "pattern": "7.62 mm battle rifle", "price": 1900, "one_hand": false,
		"capacity": 20, "reserve": 60, "damage": 48.0, "interval": 0.2, "reload": 2.6,
		"automatic": false, "fov": 44.0, "ads_time": 0.24, "pellets": 1, "hip_spread": 2.6, "ads_spread": 0.05,
		"recoil": 2.3, "recoil_yaw": 0.5, "headshot": 2.2, "falloff": Vector3(80.0, 160.0, 0.85), "per_round": 0.0, "scope": false, "sound": "dmr",
		"action": "", "weight": 0.95, "mods": ["reflex", "holo2x", "scope4x", "suppressor", "compensator", "foregrip", "laser", "extended", "speed"],
		"desc": "Semi-automatic, 20 rounds. One headshot kills; two body shots if they land."},
}

var enabled: bool = true
var in_vehicle: bool = false
## Buy phase: the weapon stays holstered until the doors open.
var can_fire: bool = true
var health: float = 100.0
var armor: float = 0.0
var ammo: int = 12
var reserve: int = 48
var weapon_id: String = "pistol"
var owned: Array[String] = ["pistol"]
## Carrying a trade item (case, Ledger, cash): only the sidearm (pistol class) can be drawn or fired.
## Owned primaries stay slung. Set through `set_sidearm_only`; cleared by death and `reset_player`.
var sidearm_only: bool = false
var infinite_reserve: bool = false
var regenerate: bool = false
var invulnerable: bool = false
var reloading: bool = false
var stamina: float = 100.0
var camera: Camera3D
var mouse_sensitivity: float = 0.0023
var base_fov: float = BASE_FOV
## Held binoculars: a narrow field of view for scouting a meeting; the weapon is lowered.
var binoculars: bool = false
const BINOCULAR_FOV: float = 16.0
## Hands up: a readable peace signal. The weapon is put away and cannot fire or reload.
var hands_up: bool = false
var aiming: bool = false
var crouching: bool = false
var sprinting: bool = false
var ads_blend: float = 0.0
## Controller look: multiplier on base turn rates, invert option.
var pad_sensitivity: float = 1.0
var invert_y: bool = false
## Viewmodel wardrobe, set from the player's crew.
var sleeve_color: Color = Color(0.15, 0.17, 0.19)
var glove_color: Color = Color(0.16, 0.13, 0.10)
## weapon id -> {slot: attachment id}
var attachments: Dictionary = {}
## Ignores gameplay presses briefly after a menu closes (A on "Resume" must not jump).
var input_grace: float = 0.0
## Vehicle seat state. Look is relative to the vehicle's heading. All seats permit a
## full turn; the seat's blocked cone limits firing only, never the camera.
var seat_look: bool = false
var seat_can_shoot: bool = false
var seat_one_hand: bool = false
var seat_yaw: float = 0.0
## (centre, half-width) in radians; +yaw turns left.
var seat_arc: Vector2 = Vector2(0.0, PI)
var seat_pitch: Vector2 = Vector2(-0.6, 0.5)
## Half-angle of a blocked cone straight ahead (the rider in front of a pillion gunner).
var seat_blocked: float = 0.0
var vehicle_yaw: float = 0.0
## The vehicle carrying the player and the seat's eye point in its local space. The body
## follows it every physics tick (vehicles move first), so shots leave from the seat.
var seat_vehicle: Node3D = null
var seat_eye_local: Vector3 = Vector3.ZERO
## Drive-by and passenger modifiers set by the game each frame.
var spread_scale: float = 1.0
## Blocks firing while the vehicle camera is in third person (shots come from the eye).
var hold_fire: bool = false
var allow_ads: bool = true
var fire_action: String = "fire"

var _head: Node3D
var _body_collision: CollisionShape3D
var _capsule: CapsuleShape3D
var _gun: Node3D
var _model: Node3D
var _flash: Node3D
var _muzzle: Node3D
var _ejector: Node3D
var _cycler: Node3D
var _cycler_angle: float = 0.0
var _stats: Dictionary = WEAPONS["pistol"]
var _ammo_state: Dictionary = {}
var _previous_weapon: String = "pistol"
var _pitch: float = 0.0
var _recoil_pitch: float = 0.0
var _recoil_yaw: float = 0.0
var _bloom: float = 0.0
var _since_shot: float = 10.0
var _cooldown: float = 0.0
var _draw_time: float = 0.0
var _reload_time: float = 0.0
var _reload_duration: float = 0.0
var _cycle_time: float = 0.0
var _gun_kick: float = 0.0
var _flash_time: float = 0.0
var _stamina_delay: float = 0.0
var _exhausted: bool = false
var _dead: bool = false
var _sight_height: float = 0.064
var _ads_depth: float = -0.27
var _hip_pose: Vector3 = Vector3(0.2, -0.2, -0.36)
var _sway: Vector2 = Vector2.ZERO
var _mouse_frame: Vector2 = Vector2.ZERO
var _bob_phase: float = 0.0
var _step_distance: float = 0.0
var _was_on_floor: bool = true
var _fall_speed: float = 0.0
var _land_dip: float = 0.0
var _obstruction: float = 0.0
var _since_damage: float = 10.0
var _death_tilt: float = 0.0
var _edge_time: float = 0.0
var _sprint_latch: bool = false
var _has_optic: bool = false
var _gun_velocity: Vector3 = Vector3.ZERO
var _gun_spin: Vector3 = Vector3.ZERO
var _materials: Dictionary = {}


func _ready() -> void:
	name = "Player"
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(46.0)
	_capsule = CapsuleShape3D.new()
	_capsule.radius = BODY_RADIUS
	_capsule.height = STAND_HEIGHT
	_body_collision = CollisionShape3D.new()
	_body_collision.shape = _capsule
	_body_collision.position.y = STAND_HEIGHT * 0.5
	add_child(_body_collision)
	_head = Node3D.new()
	_head.name = "Head"
	_head.position.y = STAND_EYE
	add_child(_head)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.03
	camera.far = 650.0
	camera.fov = base_fov
	camera.current = true
	_head.add_child(camera)
	_gun = Node3D.new()
	_gun.name = "Weapon"
	_gun.position = _hip_pose
	camera.add_child(_gun)
	equip(weapon_id)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or _dead:
		return
	if in_vehicle and not seat_look:
		return
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_LEFT_STICK and not in_vehicle:
		_sprint_latch = not _sprint_latch
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		# Aim is applied immediately; ADS scales sensitivity with the zoomed field of view.
		var zoom_scale: float = lerpf(1.0, camera.fov / base_fov, ads_blend)
		if binoculars:
			zoom_scale = camera.fov / base_fov
		var sensitivity: float = mouse_sensitivity * zoom_scale
		_turn(-motion.screen_relative.x * sensitivity)
		_pitch = clampf(_pitch - motion.screen_relative.y * sensitivity, -1.48, 1.48)
		if in_vehicle:
			_clamp_seat()
		_mouse_frame += motion.screen_relative


## Turns the body on foot, or the look direction within a vehicle seat.
func _turn(amount: float) -> void:
	if in_vehicle:
		seat_yaw += amount
		_clamp_seat()
		rotation.y = vehicle_yaw + seat_yaw
	else:
		rotate_y(amount)


func _clamp_seat() -> void:
	var relative: float = wrapf(seat_yaw - seat_arc.x, -PI, PI)
	seat_yaw = seat_arc.x + clampf(relative, -seat_arc.y, seat_arc.y)
	_pitch = clampf(_pitch, seat_pitch.x, seat_pitch.y)


func _process(delta: float) -> void:
	_follow_seat()
	_pad_look(delta)
	_update_camera(delta)
	_update_weapon_visuals(delta)


func _follow_seat() -> void:
	if in_vehicle and is_instance_valid(seat_vehicle):
		apply_seat(seat_vehicle.global_transform * seat_eye_local, seat_vehicle.global_rotation.y)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_draw_time = maxf(0.0, _draw_time - delta)
	_cycle_time = maxf(0.0, _cycle_time - delta)
	input_grace = maxf(0.0, input_grace - delta)
	_since_shot += delta
	_bloom = move_toward(_bloom, 0.0, delta * 4.5)
	_recover_recoil(delta)
	if not enabled or _dead:
		velocity = Vector3.ZERO
		return
	var controls_active: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and input_grace <= 0.0
	if in_vehicle:
		velocity = Vector3.ZERO
		_follow_seat()
		if seat_can_shoot:
			if reloading:
				_advance_reload(delta, controls_active)
			_update_aim(delta, controls_active)
			_weapon_input(controls_active)
		return
	_since_damage += delta
	if regenerate and _since_damage > 4.0 and health < 100.0:
		health = minf(100.0, health + 14.0 * delta)
	if reloading:
		_advance_reload(delta, controls_active)
	var wants_crouch: bool = controls_active and Input.is_action_pressed("crouch")
	if wants_crouch != crouching:
		if wants_crouch or _can_stand():
			_set_crouch(wants_crouch)
	var target_eye_height: float = CROUCH_EYE if crouching else STAND_EYE
	_head.position.y = move_toward(_head.position.y, target_eye_height, delta * 5.0)
	_update_aim(delta, controls_active)
	var move_input: Vector2 = Vector2.ZERO
	if controls_active:
		move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back") + Input.get_vector("stick_left", "stick_right", "stick_up", "stick_down")
		move_input = move_input.limit_length(1.0)
	var direction: Vector3 = global_transform.basis * Vector3(move_input.x, 0.0, move_input.y)
	direction.y = 0.0
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	if stamina >= 20.0:
		_exhausted = false
	if move_input.y > -0.2 or aiming:
		_sprint_latch = false
	sprinting = controls_active and (Input.is_action_pressed("sprint") or _sprint_latch) and move_input.y < -0.2
	sprinting = sprinting and not crouching and not aiming and not _exhausted
	sprinting = sprinting and not Input.is_action_pressed("fire") and is_on_floor()
	if sprinting and reloading and _stats.get("per_round", 0.0) > 0.0:
		reloading = false
	if sprinting:
		stamina = maxf(0.0, stamina - 17.0 * delta)
		_stamina_delay = 0.65
		if stamina <= 0.0:
			_exhausted = true
			sprinting = false
	else:
		_stamina_delay = maxf(0.0, _stamina_delay - delta)
		if _stamina_delay <= 0.0:
			stamina = minf(100.0, stamina + 23.0 * delta)
	var speed: float = WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	elif aiming:
		speed = lerpf(WALK_SPEED, 2.5, ads_blend)
	speed *= float(_stats.get("weight", 1.0))
	var acceleration: float = GROUND_ACCELERATION if is_on_floor() else AIR_ACCELERATION
	if direction.length_squared() < 0.001 and is_on_floor():
		acceleration = GROUND_BRAKING
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
	elif controls_active and Input.is_action_just_pressed("jump") and not crouching and stamina >= 10.0:
		velocity.y = JUMP_SPEED
		stamina -= 10.0
		_stamina_delay = 0.65
	else:
		velocity.y = 0.0
	_try_step_up(delta)
	move_and_slide()
	_track_steps(delta)
	_weapon_input(controls_active)


## Curbs, plinths and single risers up to STEP_UP_MAX: lift the body over a ledge that blocks the way
## (stairs carry their own glide slabs in BuildingKit). A wall still blocks: lifted, the move must be clear.
func _try_step_up(delta: float) -> void:
	if not is_on_floor() or velocity.y > 0.01:
		return
	var motion: Vector3 = Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length() < 0.001:
		return
	var here: Transform3D = global_transform
	if not test_move(here, motion):
		return
	# Probe a little ahead: one frame's motion would land the rounded capsule bottom on the ledge's edge,
	# whose tilted contact normal reads as a wall.
	var probe: Vector3 = motion.normalized() * maxf(motion.length(), 0.15)
	var lifted: Transform3D = here.translated(Vector3.UP * STEP_UP_MAX)
	if test_move(here, Vector3.UP * STEP_UP_MAX) or test_move(lifted, probe):
		return
	var landing: KinematicCollision3D = KinematicCollision3D.new()
	var hit: bool = test_move(lifted.translated(probe), Vector3.DOWN * (STEP_UP_MAX + 0.02), landing)
	if hit and landing.get_normal().y >= cos(floor_max_angle):
		global_position.y += STEP_UP_MAX + landing.get_travel().y


func _update_aim(delta: float, controls_active: bool) -> void:
	aiming = controls_active and allow_ads and Input.is_action_pressed("aim") and not reloading and _draw_time <= 0.0 and weapon_ready()
	var ads_time: float = float(_stats.get("ads_time", 0.18))
	ads_blend = move_toward(ads_blend, 1.0 if aiming else 0.0, delta / ads_time)


func _weapon_input(controls_active: bool) -> void:
	if not controls_active or not weapon_ready():
		return
	if Input.is_action_just_pressed("reload"):
		_start_reload()
	var trigger: bool = Input.is_action_pressed(fire_action) if bool(_stats["automatic"]) else Input.is_action_just_pressed(fire_action)
	if trigger:
		_try_fire()


## Right-stick look: radial deadzone, exponential response and a turn boost when the
## stick is held at the edge, so fine aim and fast 180s both work.
func _pad_look(delta: float) -> void:
	if not enabled or _dead or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if in_vehicle and not seat_look:
		return
	var stick: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down", 0.14)
	if stick.length() < 0.01:
		_edge_time = 0.0
		return
	var shaped: Vector2 = stick.normalized() * pow(stick.length(), 1.8)
	_edge_time = _edge_time + delta if stick.length() > 0.95 else 0.0
	var boost: float = 1.0 + clampf((_edge_time - 0.22) / 0.35, 0.0, 1.0) * 0.7
	var zoom_scale: float = lerpf(1.0, camera.fov / base_fov, ads_blend)
	_turn(-shaped.x * deg_to_rad(240.0) * pad_sensitivity * zoom_scale * boost * delta)
	var pitch_sign: float = -1.0 if invert_y else 1.0
	_pitch = clampf(_pitch - shaped.y * pitch_sign * deg_to_rad(170.0) * pad_sensitivity * zoom_scale * delta, -1.48, 1.48)
	if in_vehicle:
		_clamp_seat()
	_mouse_frame += shaped * 9.0


func _track_steps(delta: float) -> void:
	var on_floor: bool = is_on_floor()
	if on_floor and not _was_on_floor:
		if _fall_speed > 2.5:
			_land_dip = clampf(_fall_speed * 0.012, 0.02, 0.09)
			_kick_viewmodel(Vector3(0, -0.12 * _fall_speed, 0), Vector3(-0.6 * _fall_speed, 0, 0))
			landed.emit(_fall_speed)
		_step_distance = 0.0
	if on_floor:
		_fall_speed = 0.0
	_was_on_floor = on_floor
	var planar: float = Vector2(velocity.x, velocity.z).length()
	if on_floor and planar > 0.6:
		_step_distance += planar * delta
		var stride: float = 2.45 if sprinting else (1.4 if crouching else 1.95)
		if _step_distance >= stride:
			_step_distance = 0.0
			footstep.emit(not crouching)


func _can_stand() -> bool:
	var standing_capsule: CapsuleShape3D = CapsuleShape3D.new()
	standing_capsule.radius = BODY_RADIUS * 0.96
	standing_capsule.height = STAND_HEIGHT - 0.04
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = standing_capsule
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (STAND_HEIGHT * 0.5 + 0.025))
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _set_crouch(value: bool) -> void:
	crouching = value
	var height: float = CROUCH_HEIGHT if crouching else STAND_HEIGHT
	_capsule.height = height
	_body_collision.position.y = height * 0.5


## Current cone half-angle in degrees, used by shots and the dynamic crosshair.
func current_spread() -> float:
	var spread: float = lerpf(float(_stats["hip_spread"]), float(_stats["ads_spread"]), ads_blend)
	var planar: float = Vector2(velocity.x, velocity.z).length()
	spread += planar * 0.16 * (1.0 - ads_blend * 0.75)
	if not is_on_floor() and not in_vehicle:
		spread += 2.2
	if crouching and not in_vehicle:
		spread *= 0.75
	return (spread + _bloom) * spread_scale


func weapon_stats() -> Dictionary:
	return _stats


## False while the hands are up or the binoculars are raised: no firing, no reloading.
func weapon_ready() -> bool:
	return not hands_up and not binoculars


## Raises or lowers the hands. Returns true when the state changed.
func set_hands_up(value: bool) -> bool:
	if value == hands_up or (value and (_dead or in_vehicle)):
		return false
	hands_up = value
	if value:
		aiming = false
		ads_blend = 0.0
		reloading = false
	gesture_changed.emit(hands_up)
	return true


func is_scoped() -> bool:
	return bool(_stats.get("scope", false)) and ads_blend > 0.82 and (not in_vehicle or seat_can_shoot) and not _dead


func is_dead() -> bool:
	return _dead


static func class_of(id: String) -> String:
	return str((WEAPONS.get(id, WEAPONS["pistol"]) as Dictionary)["class"])


static func is_one_hand(id: String) -> bool:
	return bool((WEAPONS.get(id, WEAPONS["pistol"]) as Dictionary).get("one_hand", false))


static func is_primary(id: String) -> bool:
	return class_of(id) != "pistol"


func _try_fire() -> void:
	if not weapon_ready():
		return
	if _cooldown > 0.0 or _draw_time > 0.0 or not enabled or not can_fire or _dead or hold_fire:
		return
	if in_vehicle and not seat_can_shoot:
		return
	# A pillion gunner can inspect the rider and the road ahead without a camera stop,
	# but cannot fire through the person in front.
	if in_vehicle and seat_blocked > 0.0 and absf(wrapf(seat_yaw, -PI, PI)) < seat_blocked:
		return
	if reloading:
		# Shell-by-shell reloads can be interrupted to fire a loaded round.
		if float(_stats.get("per_round", 0.0)) > 0.0 and ammo > 0:
			reloading = false
		else:
			return
	if ammo <= 0:
		_cooldown = 0.25
		weapon_event.emit("dry")
		_start_reload()
		return
	ammo -= 1
	_cooldown = float(_stats["interval"])
	_since_shot = 0.0
	_gun_kick = minf(1.6, _gun_kick + 1.0)
	_flash_time = 0.05
	var kick_scale: float = lerpf(1.0, 0.72, ads_blend) * (0.8 if crouching and not in_vehicle else 1.0)
	_recoil_pitch = minf(_recoil_pitch + deg_to_rad(float(_stats["recoil"])) * randf_range(0.85, 1.1) * kick_scale, deg_to_rad(14.0))
	_recoil_yaw = clampf(_recoil_yaw + deg_to_rad(randf_range(-1.0, 1.0) * float(_stats["recoil_yaw"])) * kick_scale, -0.09, 0.09)
	if bool(_stats["automatic"]):
		_bloom = minf(_bloom + 0.22, 2.5)
	var punch: float = clampf(float(_stats["recoil"]) / 1.5, 0.5, 2.6)
	_kick_viewmodel(Vector3(randf_range(-0.05, 0.05), 0.22, 1.05) * punch, Vector3(3.0, randf_range(-1.0, 1.0), randf_range(-1.4, 1.4)) * punch)
	var action: String = str(_stats.get("action", ""))
	if action == "pump" or action == "bolt":
		_cycle_time = 0.5
	elif action == "revolver":
		_cycler_angle += TAU / 6.0
	var origin: Vector3 = camera.global_position
	var spread: float = current_spread()
	var basis: Basis = camera.global_transform.basis
	for pellet: int in range(int(_stats.get("pellets", 1))):
		var radius: float = tan(deg_to_rad(spread) * sqrt(randf()))
		var theta: float = randf() * TAU
		var direction: Vector3 = (-basis.z + basis.x * radius * cos(theta) + basis.y * radius * sin(theta)).normalized()
		shot_fired.emit(origin, direction, float(_stats["damage"]))
	weapon_fired.emit(weapon_id)


func _recover_recoil(delta: float) -> void:
	# Recoil climbs while firing and settles once the trigger rests.
	# Sustained automatic fire recovers slowly; single shots settle after a beat.
	var settle: float = 1.6 if _since_shot < minf(float(_stats["interval"]) * 1.4, 0.18) else 7.5
	_recoil_pitch = move_toward(_recoil_pitch, 0.0, delta * settle * maxf(_recoil_pitch, 0.02))
	_recoil_yaw = move_toward(_recoil_yaw, 0.0, delta * settle * maxf(absf(_recoil_yaw), 0.01))


func _start_reload() -> void:
	if reloading or ammo >= int(_stats["capacity"]) or (reserve <= 0 and not infinite_reserve) or _dead:
		return
	reloading = true
	aiming = false
	var per_round: float = float(_stats.get("per_round", 0.0))
	if per_round > 0.0:
		_reload_duration = per_round
		_reload_time = per_round + 0.25
		weapon_event.emit("reload_start")
	else:
		_reload_duration = float(_stats["reload"])
		_reload_time = _reload_duration
		weapon_event.emit("break_open" if str(_stats.get("action", "")) == "break" else "mag_out")


func _advance_reload(delta: float, _controls_active: bool) -> void:
	_reload_time -= delta
	var per_round: float = float(_stats.get("per_round", 0.0))
	if per_round > 0.0:
		if _reload_time <= 0.0:
			ammo += 1
			if not infinite_reserve:
				reserve -= 1
			weapon_event.emit("shell")
			if ammo >= int(_stats["capacity"]) or (reserve <= 0 and not infinite_reserve):
				reloading = false
				weapon_event.emit("pump")
				_cycle_time = 0.5
			else:
				_reload_time = per_round
		return
	if _reload_time <= _reload_duration * 0.35 and _reload_time + delta > _reload_duration * 0.35:
		weapon_event.emit("mag_in")
	if _reload_time <= 0.0:
		var required: int = int(_stats["capacity"]) - ammo
		var transferred: int = required if infinite_reserve else mini(required, reserve)
		ammo += transferred
		if not infinite_reserve:
			reserve -= transferred
		reloading = false


## Grants a weapon with full ammunition and selects it (purchases, round resets).
func equip(id: String) -> void:
	if not WEAPONS.has(id):
		id = "pistol"
	if not owned.has(id):
		owned.append(id)
	if sidearm_only and is_primary(id):
		# Bought while carrying a trade item: it goes slung, full, and the sidearm stays in hand.
		var stats: Dictionary = compute_stats(id)
		_ammo_state[id] = Vector2i(int(stats["capacity"]), int(stats["reserve"]))
		if is_primary(weapon_id) or not owned.has(weapon_id):
			_draw_sidearm()
		return
	_ammo_state.erase(id)
	_select(id)
	ammo = int(_stats["capacity"])
	reserve = int(_stats["reserve"])
	_cooldown = 0.18
	_draw_time = 0.0


## Replaces whatever the player carries in this weapon's class with `id`, full and
## selected. Attachments on the replaced weapon go with it.
func replace_in_class(id: String) -> void:
	if not WEAPONS.has(id):
		return
	var weapon_class: String = class_of(id)
	for existing: String in owned.duplicate():
		if existing != id and class_of(existing) == weapon_class:
			drop_weapon(existing, false)
	equip(id)


## Removes a weapon from the inventory (sold back, discarded or replaced). With
## `keep_armed`, the player is never left empty-handed: they draw what is left, or a P9.
func drop_weapon(id: String, keep_armed: bool = true) -> void:
	owned.erase(id)
	_ammo_state.erase(id)
	attachments.erase(id)
	if not keep_armed:
		return
	if owned.is_empty():
		owned.append("pistol")
	if weapon_id == id:
		equip(owned[0])


static func short_name(id: String) -> String:
	return str(SHORT.get(id, id.to_upper()))


## The weapon of a class that the player carries, or "" if none.
func owned_in_class(weapon_class: String) -> String:
	for id: String in owned:
		if class_of(id) == weapon_class:
			return id
	return ""


## Replaces the inventory. Every weapon starts full; the last entry is selected.
func set_loadout(ids: Array) -> void:
	owned.clear()
	_ammo_state.clear()
	attachments.clear()
	for id: Variant in ids:
		if WEAPONS.has(str(id)) and not owned.has(str(id)):
			owned.append(str(id))
	if owned.is_empty():
		owned.append("pistol")
	_previous_weapon = owned[0]
	equip(owned[owned.size() - 1])


## Trade-item rule: while `on`, primaries are slung and only the pistol class works. Turning it on with a
## primary drawn switches to the owned sidearm (adding a P9 if there is none). Turning it off does not
## auto-switch: the player draws the primary again themselves.
func set_sidearm_only(on: bool) -> void:
	sidearm_only = on
	if on and is_primary(weapon_id):
		_draw_sidearm()


## Draws the pistol-class weapon for the trade-item rule.
func _draw_sidearm() -> void:
	var sidearm: String = owned_in_class("pistol")
	if sidearm.is_empty():
		sidearm = "pistol"
		owned.append(sidearm)
	if weapon_id == sidearm:
		return
	if not switch_weapon(sidearm):
		# Dead, or otherwise unable to animate a draw: the state must still be sidearm-only.
		_ammo_state[weapon_id] = Vector2i(ammo, reserve)
		_select(sidearm)
		var saved: Vector2i = _ammo_state.get(sidearm, Vector2i(int(_stats["capacity"]), int(_stats["reserve"])))
		ammo = mini(saved.x, int(_stats["capacity"]))
		reserve = saved.y


func can_use(id: String) -> bool:
	if sidearm_only and is_primary(id):
		return false
	if not in_vehicle:
		return true
	return seat_can_shoot and (not seat_one_hand or is_one_hand(id))


func switch_weapon(id: String) -> bool:
	if id == weapon_id or not owned.has(id) or _dead or not can_use(id):
		return false
	_ammo_state[weapon_id] = Vector2i(ammo, reserve)
	_previous_weapon = weapon_id
	_select(id)
	var saved: Vector2i = _ammo_state.get(id, Vector2i(int(_stats["capacity"]), int(_stats["reserve"])))
	ammo = mini(saved.x, int(_stats["capacity"]))
	reserve = saved.y
	# The draw time gates the new weapon; the old weapon's fire cooldown does not carry over.
	_cooldown = 0.0
	_draw_time = 0.3
	ads_blend = 0.0
	weapon_event.emit("draw")
	return true


## Owned weapons in key order (class order, then variant order).
func ordered_owned() -> Array[String]:
	var ordered: Array[String] = []
	for weapon_class: String in SLOT_ORDER:
		for id: String in VARIANTS[weapon_class]:
			if owned.has(id):
				ordered.append(id)
	return ordered


func cycle_weapon(step: int) -> void:
	var available: Array[String] = []
	for id: String in ordered_owned():
		if can_use(id):
			available.append(id)
	if available.size() < 2:
		return
	var index: int = available.find(weapon_id)
	switch_weapon(available[(index + step + available.size()) % available.size()])


func quick_swap() -> void:
	if owned.has(_previous_weapon):
		switch_weapon(_previous_weapon)


func refill() -> void:
	_ammo_state.clear()
	ammo = int(_stats["capacity"])
	reserve = int(_stats["reserve"])
	reloading = false


func _select(id: String) -> void:
	weapon_id = id
	_stats = compute_stats(id)
	reloading = false
	_gun_kick = 0.0
	_flash_time = 0.0
	_bloom = 0.0
	_cycle_time = 0.0
	_cycler_angle = 0.0
	if is_instance_valid(_gun):
		_build_gun()


func take_damage(amount: float, source: Vector3 = Vector3.INF) -> void:
	if _dead or amount <= 0.0:
		return
	if invulnerable:
		damaged.emit(amount, source)
		return
	var absorbed: float = minf(armor, amount * 0.65)
	armor = maxf(0.0, armor - absorbed)
	health = maxf(0.0, health - (amount - absorbed))
	_since_damage = 0.0
	damaged.emit(amount, source)
	if health <= 0.0:
		_dead = true
		sidearm_only = false
		enabled = false
		reloading = false
		aiming = false
		died.emit()


func reset_player(pos: Vector3) -> void:
	sidearm_only = false
	global_position = pos
	velocity = Vector3.ZERO
	health = 100.0
	armor = 0.0
	stamina = 100.0
	_stamina_delay = 0.0
	_exhausted = false
	_dead = false
	_death_tilt = 0.0
	enabled = true
	binoculars = false
	set_hands_up(false)
	aiming = false
	ads_blend = 0.0
	sprinting = false
	_pitch = 0.0
	_recoil_pitch = 0.0
	_recoil_yaw = 0.0
	_since_damage = 10.0
	rotation = Vector3.ZERO
	if is_instance_valid(_head):
		_head.rotation = Vector3.ZERO
		_head.position.y = STAND_EYE
		_set_crouch(false)
		camera.fov = base_fov
	set_vehicle_mode(false)
	equip(weapon_id)


## Heals and restores the body without touching the inventory (a survivor's next round).
func revive(pos: Vector3) -> void:
	var keep_ammo: int = ammo
	var keep_reserve: int = reserve
	var keep_armor: float = armor
	reset_player(pos)
	ammo = keep_ammo
	reserve = keep_reserve
	armor = keep_armor


func set_outfit(sleeve: Color, glove: Color) -> void:
	sleeve_color = sleeve
	glove_color = glove
	if is_instance_valid(_gun):
		_build_gun()


func face(yaw: float) -> void:
	rotation = Vector3(0.0, yaw, 0.0)
	_pitch = 0.0


## Sits in a vehicle seat. `look` lets the player aim around the seat's arc (passengers,
## drive-by); `can_shoot` lets them fire; `one_hand` restricts them to one-handed weapons.
func enter_seat(look: bool, can_shoot: bool, one_hand: bool, arc: Vector2, pitch_limits: Vector2, blocked: float = 0.0) -> void:
	var was_seated: bool = in_vehicle
	in_vehicle = true
	seat_look = look
	seat_can_shoot = can_shoot
	seat_one_hand = one_hand
	seat_arc = arc
	seat_pitch = pitch_limits
	seat_blocked = blocked
	if not was_seated:
		seat_yaw = arc.x
		_pitch = 0.0
	_clamp_seat()
	velocity = Vector3.ZERO
	aiming = false
	ads_blend = 0.0
	sprinting = false
	_sprint_latch = false
	if is_instance_valid(_head):
		_set_crouch(true)
		_head.position.y = CROUCH_EYE
	if can_shoot and not can_use(weapon_id):
		for id: String in ordered_owned():
			if can_use(id):
				switch_weapon(id)
				break
	if is_instance_valid(_gun):
		_gun.visible = can_shoot


func leave_seat() -> void:
	in_vehicle = false
	seat_vehicle = null
	seat_look = false
	seat_can_shoot = false
	seat_one_hand = false
	seat_blocked = 0.0
	spread_scale = 1.0
	allow_ads = true
	fire_action = "fire"
	velocity = Vector3.ZERO
	aiming = false
	ads_blend = 0.0
	sprinting = false
	reloading = false
	if is_instance_valid(_head):
		_set_crouch(false)
		_head.position.y = STAND_EYE
		_head.rotation.z = 0.0
	if is_instance_valid(_body_collision):
		_body_collision.set_deferred("disabled", false)
	if is_instance_valid(_gun):
		_gun.visible = true


## Places the seated body so the camera sits at `eye` and faces the seat's look direction.
func apply_seat(eye: Vector3, heading: float) -> void:
	vehicle_yaw = heading
	global_position = eye - Vector3(0.0, _head.position.y if is_instance_valid(_head) else CROUCH_EYE, 0.0)
	rotation = Vector3(0.0, heading + seat_yaw, 0.0)


func seat_look_direction() -> float:
	return seat_yaw


func look_pitch() -> float:
	return _pitch


## Eases the seated look toward (yaw, pitch): the third-person camera swinging back
## behind the car when the player stops looking around.
func ease_seat_look(yaw: float, pitch: float, weight: float) -> void:
	seat_yaw = lerp_angle(seat_yaw, yaw, weight)
	_pitch = lerpf(_pitch, pitch, weight)
	_clamp_seat()


## Driver's seat without drive-by: body hidden in the car, no collision, no weapon.
func set_vehicle_mode(active: bool) -> void:
	if active:
		enter_seat(false, false, false, Vector2.ZERO, Vector2(-0.4, 0.4))
		if is_instance_valid(_body_collision):
			_body_collision.set_deferred("disabled", true)
	else:
		leave_seat()


func set_body_collision(on: bool) -> void:
	if is_instance_valid(_body_collision):
		_body_collision.set_deferred("disabled", not on)


func muzzle_position() -> Vector3:
	return _muzzle.global_position if is_instance_valid(_muzzle) else camera.global_position


func ejector_position() -> Vector3:
	return _ejector.global_position if is_instance_valid(_ejector) else camera.global_position


func _update_camera(delta: float) -> void:
	if not is_instance_valid(_head):
		return
	_land_dip = move_toward(_land_dip, 0.0, delta * 0.35)
	if _dead:
		_death_tilt = move_toward(_death_tilt, 1.0, delta * 1.6)
	_head.rotation.x = _pitch + _recoil_pitch - _death_tilt * 0.5
	_head.rotation.z = _death_tilt * 0.6
	camera.rotation.y = _recoil_yaw
	camera.position.y = -_land_dip - _death_tilt * 0.9
	var target_fov: float = lerpf(base_fov, float(_stats["fov"]), ads_blend * ads_blend * (3.0 - 2.0 * ads_blend))
	if sprinting:
		target_fov += 4.0
	if binoculars and not _dead:
		target_fov = BINOCULAR_FOV
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-delta * 20.0))


func _update_weapon_visuals(delta: float) -> void:
	if not is_instance_valid(_gun):
		return
	delta = minf(delta, 0.05)
	_gun.visible = (not in_vehicle or seat_can_shoot) and not _dead and not is_scoped() and weapon_ready()
	_gun_kick = move_toward(_gun_kick, 0.0, delta * 9.0)
	_flash_time = maxf(0.0, _flash_time - delta)
	if is_instance_valid(_flash):
		_flash.visible = _flash_time > 0.0 and not bool(_stats.get("quiet", false))
		if _flash.visible:
			_flash.rotation.z = randf() * TAU
			_flash.scale = Vector3.ONE * randf_range(0.8, 1.25) * (1.0 - ads_blend * 0.55) * (1.35 if bool(_stats.get("loud", false)) else 1.0)
	# Sway lags mouse movement a little; it decays quickly so aim stays honest.
	var sway_target: Vector2 = Vector2(-_mouse_frame.x, -_mouse_frame.y) * 0.0011 * (1.0 - ads_blend * 0.85)
	_mouse_frame = Vector2.ZERO
	_sway = _sway.lerp(sway_target.clamp(Vector2(-0.07, -0.07), Vector2(0.07, 0.07)), 1.0 - exp(-delta * 10.0))
	var planar: float = Vector2(velocity.x, velocity.z).length() if is_on_floor() else 0.0
	_bob_phase += planar * delta * (2.0 if sprinting else 2.6)
	var bob_amount: float = clampf(planar / WALK_SPEED, 0.0, 1.5) * (1.0 - ads_blend * 0.9)
	var ads_pose: Vector3 = Vector3(0.0, -_sight_height, _ads_depth)
	var target_position: Vector3 = _hip_pose.lerp(ads_pose, ads_blend * ads_blend * (3.0 - 2.0 * ads_blend))
	target_position += Vector3(sin(_bob_phase) * 0.012, -absf(cos(_bob_phase)) * 0.015, 0.0) * bob_amount
	var target_rotation: Vector3 = Vector3(_sway.y, _sway.x, _sway.x * 0.6 + sin(_bob_phase) * 0.025 * bob_amount)
	if sprinting:
		target_position += Vector3(-0.05, -0.07, 0.06)
		target_rotation += Vector3(-0.28, 0.55, 0.22)
	if not can_fire and not in_vehicle:
		# Holstered during the buy phase: the weapon rides low.
		target_position += Vector3(0.0, -0.1, 0.05)
		target_rotation += Vector3(-0.5, 0.2, 0.1)
	if reloading:
		var progress: float = 1.0 - clampf(_reload_time / maxf(0.01, _reload_duration), 0.0, 1.0)
		var dip: float = sin(progress * PI)
		if float(_stats.get("per_round", 0.0)) > 0.0:
			dip = 0.55 + sin(progress * PI) * 0.2
		target_position += Vector3(-0.02, -0.12 * dip, 0.03 * dip)
		target_rotation += Vector3(0.3 * dip, 0.12 * dip, 0.55 * dip)
	if _draw_time > 0.0:
		var draw: float = _draw_time / 0.3
		target_position.y -= draw * 0.22
		target_rotation.x -= draw * 0.7
	# Lift the muzzle when a wall is in the way instead of pushing it through.
	var blocked: bool = false
	if is_inside_tree() and not in_vehicle:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 0.72, 1)
		blocked = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	_obstruction = move_toward(_obstruction, 1.0 if blocked and not aiming else 0.0, delta * 5.0)
	target_position += Vector3(-0.03, -0.04, 0.14) * _obstruction
	target_rotation.x += 0.75 * _obstruction
	# Damped springs: moves overshoot slightly and settle, so the weapon has weight.
	# Stiffer while aiming so the sight picture stays steady.
	var stiffness: float = lerpf(190.0, 420.0, ads_blend)
	var damping: float = lerpf(17.0, 26.0, ads_blend)
	_gun_velocity += (target_position - _gun.position) * stiffness * delta
	_gun_velocity *= exp(-damping * delta)
	_gun.position += _gun_velocity * delta
	_gun_spin += (target_rotation - _gun.rotation) * stiffness * delta
	_gun_spin *= exp(-damping * delta)
	_gun.rotation += _gun_spin * delta
	if is_instance_valid(_cycler):
		match str(_stats.get("action", "")):
			"revolver":
				_cycler.rotation.z = lerp_angle(_cycler.rotation.z, _cycler_angle, 1.0 - exp(-delta * 30.0))
			"break":
				var open: float = 0.0
				if reloading:
					var t: float = 1.0 - clampf(_reload_time / maxf(0.01, _reload_duration), 0.0, 1.0)
					open = clampf(minf(t, 1.0 - t) * 5.0, 0.0, 1.0)
				_cycler.rotation.x = lerpf(_cycler.rotation.x, -0.75 * open, 1.0 - exp(-delta * 18.0))
			_:
				var pull: float = sin(clampf(1.0 - _cycle_time / 0.5, 0.0, 1.0) * PI) if _cycle_time > 0.0 else 0.0
				_cycler.position.z = float(_cycler.get_meta("rest_z")) + pull * 0.08


## Recoil and landing impulses feed the springs so the gun bounces back naturally.
func _kick_viewmodel(push: Vector3, spin: Vector3) -> void:
	var calm: float = 1.0 - ads_blend * 0.6
	_gun_velocity += push * calm
	_gun_spin += spin * calm


# --- Attachments ---------------------------------------------------------------------

## Effective stats for a weapon with its current attachments.
func compute_stats(id: String) -> Dictionary:
	var stats: Dictionary = (WEAPONS[id] as Dictionary).duplicate()
	var fitted: Dictionary = attachments.get(id, {})
	for slot: String in fitted:
		var part: Dictionary = ATTACHMENTS[fitted[slot]]
		for key: String in ["recoil", "recoil_yaw", "hip_spread", "ads_time", "reload", "per_round"]:
			if part.has(key):
				stats[key] = float(stats[key]) * float(part[key])
		if part.has("reload"):
			stats["per_round"] = float(stats["per_round"]) * float(part["reload"])
		if part.has("spread"):
			stats["hip_spread"] = float(stats["hip_spread"]) * float(part["spread"])
			stats["ads_spread"] = float(stats["ads_spread"]) * float(part["spread"])
		if part.has("capacity"):
			stats["capacity"] = int(round(float(stats["capacity"]) * float(part["capacity"])))
		if part.has("falloff_scale"):
			var curve: Vector3 = stats["falloff"]
			stats["falloff"] = Vector3(curve.x * float(part["falloff_scale"]), curve.y * float(part["falloff_scale"]), curve.z)
		if part.has("fov_delta"):
			stats["fov"] = float(stats["fov"]) + float(part["fov_delta"])
		if part.has("fov_scale"):
			stats["fov"] = float(stats["fov"]) * float(part["fov_scale"])
		if part.has("scope_fov"):
			stats["fov"] = float(part["scope_fov"])
			stats["scope"] = true
		if bool(part.get("unscope", false)) and bool(stats["scope"]):
			# A reflex sight replaces the bolt rifle's scope: close-range sight picture.
			stats["scope"] = false
			stats["fov"] = 48.0
			stats["ads_time"] = float(stats["ads_time"]) * 0.75
		for flag: String in ["quiet", "loud", "laser"]:
			if bool(part.get(flag, false)):
				stats[flag] = true
	return stats


func fits(id: String, part_id: String) -> bool:
	return ATTACHMENTS.has(part_id) and WEAPONS.has(id) and ((WEAPONS[id] as Dictionary).get("mods", []) as Array).has(part_id)


func options_for(id: String, slot: String) -> Array[String]:
	var result: Array[String] = []
	for part_id: String in ATTACHMENTS:
		if str(ATTACHMENTS[part_id]["slot"]) == slot and fits(id, part_id):
			result.append(part_id)
	return result


func attachment(id: String, slot: String) -> String:
	return str((attachments.get(id, {}) as Dictionary).get(slot, ""))


## Fits (or with "" removes) an attachment. Returns false if it does not fit.
func set_attachment(id: String, slot: String, part_id: String) -> bool:
	if not WEAPONS.has(id) or not SLOTS.has(slot):
		return false
	if not part_id.is_empty() and (not fits(id, part_id) or str(ATTACHMENTS[part_id]["slot"]) != slot):
		return false
	var fitted: Dictionary = attachments.get(id, {})
	if part_id.is_empty():
		fitted.erase(slot)
	else:
		fitted[slot] = part_id
	attachments[id] = fitted
	if id == weapon_id:
		_stats = compute_stats(id)
		ammo = mini(ammo, int(_stats["capacity"]))
		if is_instance_valid(_gun):
			_build_gun()
	elif _ammo_state.has(id):
		var saved: Vector2i = _ammo_state[id]
		_ammo_state[id] = Vector2i(mini(saved.x, int(compute_stats(id)["capacity"])), saved.y)
	return true


func attachment_summary(id: String) -> String:
	var names: PackedStringArray = PackedStringArray()
	for slot: String in SLOTS:
		var part_id: String = attachment(id, slot)
		if not part_id.is_empty():
			names.append(str(ATTACHMENTS[part_id]["short"]))
	return "  ·  ".join(names)


# --- Viewmodel ----------------------------------------------------------------------
# Each weapon builds its own silhouette from bevelled parts. Every iron sight's top edge
# sits exactly on `_sight_height`, the line the ADS pose centres on screen, so the
# front sight marks the shot. `spec` carries what the shared code needs afterwards.

func _build_gun() -> void:
	for child: Node in _gun.get_children():
		_gun.remove_child(child)
		child.queue_free()
	_model = Node3D.new()
	_gun.add_child(_model)
	_cycler = null
	var optic: String = attachment(weapon_id, "optic")
	var muzzle_part: String = attachment(weapon_id, "muzzle")
	var under: String = attachment(weapon_id, "underbarrel")
	var mag_part: String = attachment(weapon_id, "magazine")
	_has_optic = not optic.is_empty()
	var spec: Dictionary = {"optic_base": 0.056, "optic_z": -0.03, "mag_size": Vector3.ZERO, "mag_at": Vector3.ZERO,
		"mag_angles": Vector3.ZERO, "mag_curve": 0.0, "mag_color": Color(0.04, 0.042, 0.05), "grip_at": Vector3.ZERO,
		"muzzle_z": -0.16, "muzzle_y": 0.035, "support": Vector3(-0.035, -0.07, 0.01), "flash": 0.09, "mount": 0.0}
	match weapon_id:
		"m1911": _model_m1911(spec)
		"revolver": _model_revolver(spec)
		"smg": _model_vk5(spec)
		"mac": _model_mac(spec)
		"tommy": _model_tommy(spec)
		"rifle": _model_m4(spec)
		"ak": _model_ak(spec)
		"shotgun": _model_pump(spec)
		"double": _model_double(spec)
		"auto12": _model_auto12(spec)
		"marksman": _model_bolt(spec)
		"dmr": _model_dmr(spec)
		_: _model_p9(spec)
	var dark: StandardMaterial3D = _steel(Color(0.035, 0.04, 0.05), 0.5, 0.35)
	var polymer: StandardMaterial3D = _material(Color(0.06, 0.06, 0.065), 0.85)
	var muzzle_z: float = spec["muzzle_z"]
	var muzzle_y: float = spec["muzzle_y"]
	var support: Vector3 = spec["support"]
	var grip_at: Vector3 = spec["grip_at"]
	# Magazine: longer when extended, with a bright pull tab when it is a speed mag.
	var mag_size: Vector3 = spec["mag_size"]
	if mag_size != Vector3.ZERO:
		var size: Vector3 = mag_size
		var at: Vector3 = spec["mag_at"]
		if mag_part == "extended":
			var extra: float = size.y * 0.45 if class_of(weapon_id) != "pistol" else 0.045
			size.y += extra
			at.y -= extra * 0.5
		var mag_material: StandardMaterial3D = _steel(spec["mag_color"], 0.55, 0.3)
		var bottom: Vector3 = _magazine(size, at, spec["mag_angles"], float(spec["mag_curve"]), mag_material)
		if mag_part == "speed":
			_add_box(Vector3(size.x * 0.8, 0.012, size.z * 0.6), bottom, _material(Color(1.0, 0.75, 0.1), 0.5), spec["mag_angles"])
	elif mag_part == "speed" and class_of(weapon_id) == "shotgun":
		for shell: int in range(4):
			_add_cylinder(0.009, 0.03, Vector3(0.03, 0.02, -0.06 + shell * 0.022), _material(Color(0.78, 0.18, 0.14), 0.5), Vector3(0, 0, PI * 0.5))
	# Optics. Aiming through one sits the gun a little further out than iron sights.
	var optic_base: float = spec["optic_base"]
	var optic_z: float = spec["optic_z"]
	if _has_optic:
		_ads_depth -= 0.05
		var mount: float = float(spec["mount"])
		if mount > 0.0:
			# Side-rail or receiver mount up to the optic base.
			_add_box(Vector3(0.028, mount, 0.09), Vector3(0, optic_base - mount * 0.5, optic_z), dark)
	match optic:
		"reflex":
			_sight_height = optic_base + 0.028
			_add_box(Vector3(0.03, 0.01, 0.05), Vector3(0, optic_base + 0.005, optic_z), dark)
			_frame_sight(Vector2(0.036, 0.03), optic_z, dark, Color(1.0, 0.15, 0.1))
		"holo2x":
			_sight_height = optic_base + 0.034
			_add_box(Vector3(0.042, 0.012, 0.075), Vector3(0, optic_base + 0.006, optic_z), dark)
			_frame_sight(Vector2(0.046, 0.04), optic_z - 0.02, dark, Color(1.0, 0.3, 0.15), true)
		"scope4x":
			_sight_height = optic_base + 0.032
			_add_cylinder(0.019, 0.26, Vector3(0, _sight_height, optic_z), dark, Vector3(PI * 0.5, 0, 0))
			_add_cylinder(0.026, 0.06, Vector3(0, _sight_height, optic_z - 0.15), dark, Vector3(PI * 0.5, 0, 0))
			_add_cylinder(0.023, 0.04, Vector3(0, _sight_height, optic_z + 0.13), dark, Vector3(PI * 0.5, 0, 0))
			for ring: float in [-0.06, 0.06]:
				_add_box(Vector3(0.024, _sight_height - optic_base, 0.018), Vector3(0, (optic_base + _sight_height) * 0.5, optic_z + ring), dark)
	# Muzzle devices move the muzzle point forward.
	match muzzle_part:
		"suppressor":
			var radius: float = 0.017 if class_of(weapon_id) == "pistol" else 0.021
			_add_cylinder(radius, 0.17, Vector3(0, muzzle_y, muzzle_z - 0.085), dark, Vector3(PI * 0.5, 0, 0))
			muzzle_z -= 0.17
		"compensator":
			_add_box(Vector3(0.03, 0.03, 0.05), Vector3(0, muzzle_y, muzzle_z - 0.025), _steel(Color(0.12, 0.12, 0.13), 0.4, 0.5))
			for port: float in [-0.01, 0.01]:
				_add_box(Vector3(0.032, 0.006, 0.008), Vector3(0, muzzle_y + 0.012, muzzle_z - 0.025 + port), dark)
			muzzle_z -= 0.05
		"choke":
			_add_cylinder(0.021, 0.045, Vector3(0, muzzle_y, muzzle_z - 0.02), _steel(Color(0.12, 0.12, 0.13), 0.4, 0.5), Vector3(PI * 0.5, 0, 0))
			muzzle_z -= 0.045
	# Underbarrel: a vertical grip takes the support hand; a laser sits under the barrel.
	match under:
		"foregrip":
			if weapon_id == "shotgun" and _cycler != null:
				_add_box(Vector3(0.026, 0.08, 0.032), Vector3(0, -0.06, 0), polymer, Vector3(-0.1, 0, 0), _cycler)
			else:
				_add_box(Vector3(0.026, 0.085, 0.032), grip_at, polymer, Vector3(-0.1, 0, 0))
			support = grip_at + Vector3(-0.005, -0.03, 0.0)
		"laser":
			var laser_at: Vector3 = Vector3(0, muzzle_y - 0.035, maxf(muzzle_z + 0.09, -0.3) if class_of(weapon_id) != "pistol" else -0.1)
			_add_box(Vector3(0.022, 0.022, 0.06), laser_at, dark)
			_add_sphere(0.006, laser_at + Vector3(0, 0, -0.031), _glow(Color(1.0, 0.1, 0.05)))
	_hands(support)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, muzzle_y, muzzle_z)
	_model.add_child(_muzzle)
	_ejector = Node3D.new()
	_ejector.position = Vector3(0.03, muzzle_y + 0.01, -0.02)
	_model.add_child(_ejector)
	_build_flash(Vector3(0, muzzle_y, muzzle_z - 0.05), float(spec["flash"]))
	MeshMerge.merge_children(_model)
	_gun.position = _hip_pose
	_gun_velocity = Vector3.ZERO
	_gun_spin = Vector3.ZERO


## Gloved shooting hand on the grip, support hand at `support`, crew sleeves up the forearms.
func _hands(support: Vector3) -> void:
	var sleeve: StandardMaterial3D = _material(sleeve_color, 0.9)
	var glove: StandardMaterial3D = _material(glove_color, 0.8)
	var cuff: StandardMaterial3D = _material(sleeve_color.darkened(0.25), 0.9)
	_add_box(Vector3(0.056, 0.064, 0.074), Vector3(0.006, -0.06, 0.04), glove)
	for finger: int in range(3):
		_add_capsule_between(Vector3(0.028, -0.035 - finger * 0.021, 0.012), Vector3(-0.024, -0.04 - finger * 0.021, 0.0), 0.0105, glove)
	_add_capsule_between(Vector3(-0.022, -0.02, 0.06), Vector3(-0.026, 0.004, -0.0), 0.0105, glove)
	_add_capsule_between(Vector3(0.02, -0.08, 0.08), Vector3(0.075, -0.16, 0.36), 0.036, sleeve)
	_add_cylinder(0.039, 0.028, Vector3(0.024, -0.075, 0.075), cuff, Vector3(PI * 0.5 - 0.3, 0.18, 0))
	_add_box(Vector3(0.054, 0.056, 0.068), support, glove)
	for finger: int in range(3):
		_add_capsule_between(support + Vector3(-0.027, 0.02 - finger * 0.018, -0.01), support + Vector3(0.025, 0.024 - finger * 0.018, -0.012), 0.009, glove)
	_add_capsule_between(support + Vector3(-0.01, -0.02, 0.03), support + Vector3(-0.1, -0.1, 0.3), 0.033, sleeve)


func _build_flash(at: Vector3, flash_size: float) -> void:
	var flash_material: StandardMaterial3D = _material(Color(1.0, 0.78, 0.35), 1.0)
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash = Node3D.new()
	_flash.position = at
	_model.add_child(_flash)
	var petal_mesh: SphereMesh = MeshKit.sphere(flash_size * 0.5, flash_size * 0.35, 10, 4)
	for angle: float in [0.0, PI * 0.33, PI * 0.66]:
		var petal: MeshInstance3D = MeshInstance3D.new()
		petal.mesh = petal_mesh
		petal.material_override = flash_material
		petal.rotation.z = angle
		petal.scale = Vector3(1.0, 0.3, 0.25)
		petal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flash.add_child(petal)
	var core: MeshInstance3D = MeshInstance3D.new()
	core.mesh = MeshKit.sphere(flash_size * 0.26, flash_size * 0.9, 10, 5)
	core.material_override = flash_material
	core.rotation.x = PI * 0.5
	core.position.z = -flash_size * 0.3
	_flash.add_child(core)
	_flash.visible = false


## A magazine built from `curve`-bent segments (a banana mag curves forward as it drops).
## Returns the bottom centre, for base plates.
func _magazine(size: Vector3, at: Vector3, angles: Vector3, curve: float, material: StandardMaterial3D) -> Vector3:
	if curve <= 0.01:
		_add_box(size, at, material, angles)
		return at + Basis.from_euler(angles) * Vector3(0, -size.y * 0.5 - 0.006, 0)
	var segments: int = 3
	var length: float = size.y / segments
	var top: Vector3 = at + Basis.from_euler(angles) * Vector3(0, size.y * 0.5, 0)
	var tilt: float = angles.x
	var cursor: Vector3 = top
	for index: int in range(segments):
		var segment_tilt: float = tilt + curve * (float(index) + 0.5) / segments
		var down: Vector3 = Basis.from_euler(Vector3(segment_tilt, 0, 0)) * Vector3(0, -length, 0)
		_add_box(Vector3(size.x, length * 1.06, size.z), cursor + down * 0.5, material, Vector3(segment_tilt, 0, 0))
		cursor += down
	return cursor + Vector3(0, -0.006, 0)


func _model_p9(spec: Dictionary) -> void:
	_hip_pose = Vector3(0.2, -0.2, -0.38)
	_sight_height = 0.066
	_ads_depth = -0.34
	var slide: StandardMaterial3D = _steel(Color(0.1, 0.105, 0.12), 0.45, 0.45)
	var frame: StandardMaterial3D = _material(Color(0.07, 0.07, 0.075), 0.85)
	var dark: StandardMaterial3D = _steel(Color(0.035, 0.04, 0.05), 0.5, 0.35)
	_add_box(Vector3(0.036, 0.042, 0.19), Vector3(0, 0.035, -0.06), slide)
	for serration: int in range(5):
		_add_box(Vector3(0.037, 0.03, 0.003), Vector3(0, 0.035, 0.012 + serration * 0.0055), dark)
	_add_box(Vector3(0.012, 0.01, 0.03), Vector3(0.012, 0.045, -0.035), dark)
	_add_box(Vector3(0.034, 0.03, 0.16), Vector3(0, 0.004, -0.05), frame)
	_add_box(Vector3(0.032, 0.11, 0.05), Vector3(0, -0.055, 0.02), frame, Vector3(0.25, 0, 0))
	_add_box(Vector3(0.006, 0.03, 0.045), Vector3(0, -0.02, -0.035), frame)
	if not _has_optic:
		_notch(0.028, 0.056, dark)
		_front_post(-0.145, 0.056, dark)
	spec["optic_base"] = 0.056
	spec["optic_z"] = -0.03
	spec["mag_size"] = Vector3(0.026, 0.02, 0.046)
	spec["mag_at"] = Vector3(0, -0.112, 0.034)
	spec["mag_angles"] = Vector3(0.25, 0, 0)
	spec["muzzle_z"] = -0.158
	spec["muzzle_y"] = 0.035
	spec["support"] = Vector3(-0.035, -0.07, 0.01)


func _model_m1911(spec: Dictionary) -> void:
	_hip_pose = Vector3(0.2, -0.2, -0.38)
	_sight_height = 0.068
	_ads_depth = -0.34
	var blued: StandardMaterial3D = _steel(Color(0.07, 0.075, 0.09), 0.6, 0.35)
	var dark: StandardMaterial3D = _steel(Color(0.035, 0.04, 0.05), 0.5, 0.35)
	var walnut: StandardMaterial3D = _wood(Color(0.36, 0.17, 0.07))
	_add_box(Vector3(0.032, 0.038, 0.215), Vector3(0, 0.037, -0.065), blued)
	for serration: int in range(6):
		_add_box(Vector3(0.033, 0.028, 0.003), Vector3(0, 0.036, 0.018 + serration * 0.0055), dark)
	_add_cylinder(0.0135, 0.012, Vector3(0, 0.032, -0.168), blued)
	_add_box(Vector3(0.03, 0.026, 0.19), Vector3(0, 0.006, -0.055), blued)
	_add_box(Vector3(0.028, 0.105, 0.05), Vector3(0, -0.055, 0.025), blued, Vector3(0.3, 0, 0))
	for side: float in [-1.0, 1.0]:
		_add_box(Vector3(0.006, 0.075, 0.04), Vector3(side * 0.016, -0.055, 0.024), walnut, Vector3(0.3, 0, 0))
	_add_box(Vector3(0.024, 0.016, 0.03), Vector3(0, 0.012, 0.05), blued, Vector3(-0.3, 0, 0))
	_add_box(Vector3(0.01, 0.02, 0.014), Vector3(0, 0.058, 0.046), dark, Vector3(-0.5, 0, 0))
	_add_box(Vector3(0.006, 0.028, 0.045), Vector3(0, -0.018, -0.03), blued)
	if not _has_optic:
		_notch(0.03, 0.056, dark)
		_front_post(-0.16, 0.056, dark)
	spec["optic_base"] = 0.056
	spec["optic_z"] = -0.035
	spec["mag_size"] = Vector3(0.026, 0.012, 0.046)
	spec["mag_at"] = Vector3(0, -0.108, 0.04)
	spec["mag_angles"] = Vector3(0.3, 0, 0)
	spec["muzzle_z"] = -0.178
	spec["muzzle_y"] = 0.035
	spec["support"] = Vector3(-0.035, -0.07, 0.015)


func _model_revolver(spec: Dictionary) -> void:
	_hip_pose = Vector3(0.2, -0.2, -0.38)
	_sight_height = 0.058
	_ads_depth = -0.33
	# Stainless finish: the revolver reads as a different gun at a glance.
	var stainless: StandardMaterial3D = _steel(Color(0.5, 0.51, 0.53), 0.3, 0.75)
	var dark: StandardMaterial3D = _steel(Color(0.08, 0.08, 0.09), 0.5, 0.4)
	var walnut: StandardMaterial3D = _wood(Color(0.32, 0.15, 0.06))
	_add_box(Vector3(0.034, 0.058, 0.085), Vector3(0, 0.018, -0.012), stainless)
	var cylinder: Node3D = Node3D.new()
	cylinder.position = Vector3(0, 0.02, -0.032)
	_model.add_child(cylinder)
	_cycler = cylinder
	_add_part(MeshKit.cylinder(0.029, 0.029, 0.046, 18), Vector3.ZERO, stainless, Vector3(PI * 0.5, 0, 0), cylinder)
	for flute: int in range(6):
		var angle: float = flute * TAU / 6.0 + TAU / 12.0
		_add_box(Vector3(0.007, 0.007, 0.036), Vector3(cos(angle) * 0.026, sin(angle) * 0.026, 0), dark, Vector3(0, 0, angle), cylinder)
	_add_cylinder(0.0105, 0.13, Vector3(0, 0.03, -0.12), stainless)
	_add_box(Vector3(0.017, 0.02, 0.13), Vector3(0, 0.013, -0.12), stainless)
	_add_box(Vector3(0.016, 0.008, 0.15), Vector3(0, 0.043, -0.11), stainless)
	_add_box(Vector3(0.034, 0.1, 0.05), Vector3(0, -0.047, 0.045), walnut, Vector3(0.35, 0, 0))
	_add_box(Vector3(0.01, 0.024, 0.02), Vector3(0, 0.052, 0.032), dark, Vector3(-0.45, 0, 0))
	_add_box(Vector3(0.006, 0.026, 0.04), Vector3(0, -0.018, 0.002), stainless)
	if not _has_optic:
		_notch(0.02, 0.047, dark)
		_front_post(-0.18, 0.047, dark)
	spec["optic_base"] = 0.048
	spec["optic_z"] = -0.1
	spec["muzzle_z"] = -0.186
	spec["muzzle_y"] = 0.03
	spec["support"] = Vector3(-0.035, -0.07, 0.02)
	spec["flash"] = 0.12


func _model_vk5(spec: Dictionary) -> void:
	_hip_pose = Vector3(0.2, -0.21, -0.32)
	_sight_height = 0.082
	_ads_depth = -0.22
	var steel: StandardMaterial3D = _steel(Color(0.09, 0.095, 0.11), 0.5, 0.4)
	var dark: StandardMaterial3D = _steel(Color(0.035, 0.04, 0.05), 0.5, 0.35)
	var polymer: StandardMaterial3D = _material(Color(0.06, 0.06, 0.065), 0.85)
	_add_box(Vector3(0.05, 0.075, 0.27), Vector3(0, 0.02, -0.07), steel)
	_add_box(Vector3(0.062, 0.058, 0.13), Vector3(0, 0.006, -0.2), polymer)
	_add_cylinder(0.0115, 0.17, Vector3(0, 0.046, -0.2), steel)
	_add_cylinder(0.01, 0.06, Vector3(0, 0.03, -0.29), dark)
	_add_cylinder(0.013, 0.02, Vector3(0, 0.03, -0.32), dark)
	_add_box(Vector3(0.035, 0.1, 0.045), Vector3(0, -0.055, 0.04), polymer, Vector3(0.3, 0, 0))
	_add_box(Vector3(0.006, 0.03, 0.05), Vector3(0, -0.02, -0.005), polymer)
	for side: float in [-1.0, 1.0]:
		_add_cylinder(0.006, 0.19, Vector3(side * 0.019, 0.012, 0.14), dark)
	_add_box(Vector3(0.03, 0.075, 0.016), Vector3(0, -0.012, 0.24), dark)
	_add_box(Vector3(0.022, 0.012, 0.012), Vector3(-0.022, 0.046, -0.22), dark)
	if not _has_optic:
		_aperture(0.03, dark)
		_front_post(-0.24, 0.0575, dark)
		var hood: MeshInstance3D = _add_part(MeshKit.torus(0.011, 0.015, 16, 4), Vector3(0, _sight_height - 0.004, -0.24), dark, Vector3(PI * 0.5, 0, 0))
		hood.scale = Vector3(1.0, 1.0, 1.0)
	spec["optic_base"] = 0.0575
	spec["optic_z"] = -0.03
	spec["mount"] = 0.0
	spec["mag_size"] = Vector3(0.027, 0.15, 0.04)
	spec["mag_at"] = Vector3(0, -0.085, -0.1)
	spec["mag_angles"] = Vector3(0.12, 0, 0)
	spec["mag_curve"] = 0.25
	spec["grip_at"] = Vector3(0, -0.035, -0.22)
	spec["muzzle_z"] = -0.335
	spec["muzzle_y"] = 0.03
	spec["support"] = Vector3(-0.005, -0.035, -0.2)


func _model_mac(spec: Dictionary) -> void:
	_hip_pose = Vector3(0.19, -0.2, -0.36)
	_sight_height = 0.074
	_ads_depth = -0.3
	var steel: StandardMaterial3D = _steel(Color(0.06, 0.063, 0.07), 0.55, 0.35)
	var dark: StandardMaterial3D = _steel(Color(0.03, 0.03, 0.035), 0.6, 0.3)
	var polymer: StandardMaterial3D = _material(Color(0.05, 0.05, 0.055), 0.85)
	_add_box(Vector3(0.042, 0.1, 0.17), Vector3(0, 0.008, -0.03), steel)
	_add_box(Vector3(0.036, 0.012, 0.12), Vector3(0, 0.062, -0.03), dark)
	_add_cylinder(0.011, 0.05, Vector3(0, 0.03, -0.14), dark)
	for thread: int in range(4):
		_add_cylinder(0.0125, 0.004, Vector3(0, 0.03, -0.145 - thread * 0.009), dark)
	_add_box(Vector3(0.014, 0.012, 0.022), Vector3(0, -0.02, -0.11), dark)
	_add_sphere(0.008, Vector3(0, 0.066, 0.0), dark)
	_add_box(Vector3(0.034, 0.12, 0.046), Vector3(0, -0.1, 0.02), polymer, Vector3(0.1, 0, 0))
	for side: float in [-1.0, 1.0]:
		_add_cylinder(0.0035, 0.14, Vector3(side * 0.024, 0.01, -0.02), dark)
	if not _has_optic:
		_aperture(0.045, dark)
		_front_post(-0.105, 0.068, dark)
	spec["optic_base"] = 0.068
	spec["optic_z"] = -0.02
	spec["mag_size"] = Vector3(0.026, 0.05, 0.036)
	spec["mag_at"] = Vector3(0, -0.18, 0.024)
	spec["mag_angles"] = Vector3(0.1, 0, 0)
	spec["grip_at"] = Vector3(0, -0.035, -0.1)
	spec["muzzle_z"] = -0.2
	spec["muzzle_y"] = 0.03
	spec["support"] = Vector3(-0.03, -0.035, -0.1)


func _model_tommy(spec: Dictionary) -> void:
	_hip_pose = Vector3(0.2, -0.22, -0.34)
	_sight_height = 0.086
	_ads_depth = -0.24
	var blued: StandardMaterial3D = _steel(Color(0.07, 0.075, 0.09), 0.6, 0.35)
	var dark: StandardMaterial3D = _steel(Color(0.035, 0.04, 0.05), 0.5, 0.35)
	var walnut: StandardMaterial3D = _wood(Color(0.38, 0.19, 0.08))
	_add_box(Vector3(0.05, 0.08, 0.26), Vector3(0, 0.022, -0.05), blued)
	_add_sphere(0.008, Vector3(0, 0.066, -0.09), dark)
	_add_cylinder(0.012, 0.3, Vector3(0, 0.035, -0.33), blued)
	for fin: int in range(9):
		_add_cylinder(0.017, 0.006, Vector3(0, 0.035, -0.2 - fin * 0.015), blued)
	_add_box(Vector3(0.03, 0.028, 0.05), Vector3(0, 0.035, -0.5), blued)
	for port: float in [-0.012, 0.0, 0.012]:
		_add_box(Vector3(0.018, 0.005, 0.006), Vector3(0, 0.05, -0.5 + port), dark)
	_add_box(Vector3(0.036, 0.09, 0.04), Vector3(0, -0.035, -0.3), walnut, Vector3(-0.12, 0, 0))
	_add_box(Vector3(0.02, 0.02, 0.05), Vector3(0, 0.012, -0.3), blued)
	_add_part(MeshKit.cylinder(0.085, 0.085, 0.045, 24), Vector3(0, -0.085, -0.12), blued, Vector3(0, 0, PI * 0.5))
	_add_part(MeshKit.cylinder(0.03, 0.03, 0.05, 12), Vector3(0, -0.085, -0.12), dark, Vector3(0, 0, PI * 0.5))
	_add_box(Vector3(0.034, 0.1, 0.045), Vector3(0, -0.05, 0.07), walnut, Vector3(0.3, 0, 0))
	_add_box(Vector3(0.042, 0.085, 0.26), Vector3(0, -0.02, 0.24), walnut, Vector3(-0.08, 0, 0))
	if not _has_optic:
		_aperture(0.05, dark)
		_front_post(-0.48, 0.049, dark)
	spec["optic_base"] = 0.062
	spec["optic_z"] = -0.02
	spec["grip_at"] = Vector3(0, -0.035, -0.3)
	spec["muzzle_z"] = -0.53
	spec["muzzle_y"] = 0.035
	spec["support"] = Vector3(-0.005, -0.065, -0.3)
	spec["flash"] = 0.12


func _model_m4(spec: Dictionary) -> void:
	_hip_pose = Vector3(0.2, -0.22, -0.33)
	_sight_height = 0.094
	_ads_depth = -0.22
	var parkerized: StandardMaterial3D = _steel(Color(0.1, 0.105, 0.105), 0.7, 0.25)
	var dark: StandardMaterial3D = _steel(Color(0.035, 0.04, 0.05), 0.5, 0.35)
	var polymer: StandardMaterial3D = _material(Color(0.06, 0.06, 0.065), 0.85)
	_add_box(Vector3(0.05, 0.07, 0.28), Vector3(0, 0.025, -0.06), parkerized)
	_add_box(Vector3(0.028, 0.012, 0.3), Vector3(0, 0.066, -0.08), dark)
	for slot: int in range(10):
		_add_box(Vector3(0.03, 0.004, 0.008), Vector3(0, 0.07, -0.21 + slot * 0.03), parkerized)
	_add_box(Vector3(0.058, 0.062, 0.25), Vector3(0, 0.024, -0.33), polymer)
	for rib: int in range(6):
		_add_box(Vector3(0.062, 0.006, 0.012), Vector3(0, 0.024, -0.24 - rib * 0.035), dark)
	_add_box(Vector3(0.03, 0.022, 0.02), Vector3(0, 0.063, -0.43), dark)
	_add_cylinder(0.011, 0.16, Vector3(0, 0.03, -0.53), dark)
	_add_cylinder(0.014, 0.045, Vector3(0, 0.03, -0.605), dark)
	_add_box(Vector3(0.046, 0.05, 0.2), Vector3(0, -0.03, -0.04), parkerized)
	_add_box(Vector3(0.036, 0.11, 0.045), Vector3(0, -0.075, 0.055), polymer, Vector3(0.3, 0, 0))
	_add_box(Vector3(0.006, 0.03, 0.05), Vector3(0, -0.06, 0.005), parkerized)
	_add_cylinder(0.016, 0.2, Vector3(0, 0.02, 0.19), dark)
	_add_box(Vector3(0.044, 0.085, 0.12), Vector3(0, -0.005, 0.27), polymer)
	_add_box(Vector3(0.03, 0.012, 0.02), Vector3(0, 0.058, 0.09), dark)
	if not _has_optic:
		_aperture(0.03, dark)
		_front_post(-0.43, 0.074, dark)
	spec["optic_base"] = 0.072
	spec["optic_z"] = -0.07
	spec["mag_size"] = Vector3(0.026, 0.17, 0.064)
	spec["mag_at"] = Vector3(0, -0.11, -0.1)
	spec["mag_angles"] = Vector3(0.14, 0, 0)
	spec["mag_curve"] = 0.14
	spec["grip_at"] = Vector3(0, -0.045, -0.33)
	spec["muzzle_z"] = -0.63
	spec["muzzle_y"] = 0.03
	spec["support"] = Vector3(-0.01, -0.03, -0.33)
	spec["flash"] = 0.14


func _model_ak(spec: Dictionary) -> void:
	_hip_pose = Vector3(0.2, -0.22, -0.33)
	_sight_height = 0.086
	_ads_depth = -0.2
	var blued: StandardMaterial3D = _steel(Color(0.06, 0.062, 0.07), 0.55, 0.35)
	var dark: StandardMaterial3D = _steel(Color(0.035, 0.04, 0.05), 0.5, 0.35)
	var wood: StandardMaterial3D = _wood(Color(0.5, 0.21, 0.08))
	_add_box(Vector3(0.05, 0.07, 0.3), Vector3(0, 0.015, -0.03), blued)
	_add_box(Vector3(0.046, 0.02, 0.24), Vector3(0, 0.058, 0.0), blued)
	_add_box(Vector3(0.03, 0.012, 0.012), Vector3(0.035, 0.03, -0.03), dark)
	_add_box(Vector3(0.03, 0.02, 0.05), Vector3(0, 0.06, -0.14), blued)
	_add_box(Vector3(0.036, 0.028, 0.19), Vector3(0, 0.058, -0.3), wood)
	_add_box(Vector3(0.056, 0.05, 0.2), Vector3(0, 0.012, -0.3), wood)
	_add_box(Vector3(0.03, 0.03, 0.03), Vector3(0, 0.045, -0.43), blued)
	_add_box(Vector3(0.03, 0.035, 0.025), Vector3(0, 0.045, -0.52), blued)
	for side: float in [-1.0, 1.0]:
		_add_box(Vector3(0.004, 0.03, 0.012), Vector3(side * 0.013, 0.074, -0.52), blued)
	_add_cylinder(0.011, 0.24, Vector3(0, 0.03, -0.5), dark)
	_add_cylinder(0.004, 0.22, Vector3(0, 0.008, -0.46), dark)
	_add_box(Vector3(0.026, 0.026, 0.04), Vector3(0, 0.03, -0.635), dark, Vector3(0.15, 0, 0))
	_add_box(Vector3(0.032, 0.1, 0.045), Vector3(0, -0.06, 0.07), _material(Color(0.42, 0.16, 0.07), 0.5), Vector3(0.28, 0, 0))
	_add_box(Vector3(0.006, 0.028, 0.045), Vector3(0, -0.035, 0.03), blued)
	_add_box(Vector3(0.04, 0.09, 0.25), Vector3(0, -0.035, 0.22), wood, Vector3(-0.14, 0, 0))
	if not _has_optic:
		_notch(-0.14, 0.07, dark)
		_front_post(-0.52, 0.0625, dark)
	spec["optic_base"] = 0.08
	spec["optic_z"] = -0.04
	spec["mount"] = 0.012
	spec["mag_size"] = Vector3(0.028, 0.2, 0.07)
	spec["mag_at"] = Vector3(0, -0.1, -0.1)
	spec["mag_angles"] = Vector3(0.1, 0, 0)
	spec["mag_curve"] = 0.6
	spec["mag_color"] = Color(0.34, 0.13, 0.06)
	spec["grip_at"] = Vector3(0, -0.035, -0.3)
	spec["muzzle_z"] = -0.66
	spec["muzzle_y"] = 0.03
	spec["support"] = Vector3(-0.01, -0.02, -0.3)
	spec["flash"] = 0.15


func _model_pump(spec: Dictionary) -> void:
	_hip_pose = Vector3(0.2, -0.21, -0.33)
	_sight_height = 0.07
	_ads_depth = -0.3
	var steel: StandardMaterial3D = _steel(Color(0.08, 0.085, 0.1), 0.55, 0.4)
	var dark: StandardMaterial3D = _steel(Color(0.035, 0.04, 0.05), 0.5, 0.35)
	var wood: StandardMaterial3D = _wood(Color(0.36, 0.19, 0.08))
	_add_box(Vector3(0.052, 0.085, 0.22), Vector3(0, 0.015, -0.02), steel)
	_add_cylinder(0.016, 0.52, Vector3(0, 0.047, -0.38), dark)
	_add_cylinder(0.014, 0.4, Vector3(0, 0.006, -0.32), dark)
	var pump: Node3D = Node3D.new()
	pump.position = Vector3(0, 0.006, -0.31)
	pump.set_meta("rest_z", -0.31)
	_model.add_child(pump)
	_cycler = pump
	_add_box(Vector3(0.05, 0.052, 0.15), Vector3.ZERO, wood, Vector3.ZERO, pump)
	for groove: int in range(5):
		_add_box(Vector3(0.052, 0.004, 0.006), Vector3(0, -0.01, -0.05 + groove * 0.025), _material(Color(0.2, 0.1, 0.05), 0.8), Vector3.ZERO, pump)
	_add_box(Vector3(0.046, 0.095, 0.27), Vector3(0, -0.035, 0.2), wood, Vector3(-0.12, 0, 0))
	_add_box(Vector3(0.012, 0.004, 0.5), Vector3(0, 0.063, -0.37), dark)
	if not _has_optic:
		_add_box(Vector3(0.008, 0.008, 0.008), Vector3(0, _sight_height - 0.004, -0.62), _material(Color(0.95, 0.85, 0.5), 0.3))
		_notch(-0.05, 0.062, dark)
	spec["optic_base"] = 0.0575
	spec["optic_z"] = -0.02
	spec["grip_at"] = Vector3(0, -0.04, -0.31)
	spec["muzzle_z"] = -0.64
	spec["muzzle_y"] = 0.047
	spec["support"] = Vector3(-0.005, -0.05, -0.31)
	spec["flash"] = 0.15


func _model_double(spec: Dictionary) -> void:
	_hip_pose = Vector3(0.2, -0.21, -0.34)
	_sight_height = 0.052
	_ads_depth = -0.3
	var blued: StandardMaterial3D = _steel(Color(0.07, 0.072, 0.085), 0.5, 0.45)
	var dark: StandardMaterial3D = _steel(Color(0.035, 0.04, 0.05), 0.5, 0.35)
	var wood: StandardMaterial3D = _wood(Color(0.4, 0.2, 0.08))
	_add_box(Vector3(0.068, 0.06, 0.09), Vector3(0, 0.012, 0.03), _steel(Color(0.45, 0.45, 0.46), 0.35, 0.7))
	_add_box(Vector3(0.012, 0.008, 0.03), Vector3(0, 0.046, 0.07), dark)
	# Barrels and forend hinge down together on reload.
	var hinge: Node3D = Node3D.new()
	hinge.position = Vector3(0, 0.0, -0.015)
	_model.add_child(hinge)
	_cycler = hinge
	for side: float in [-1.0, 1.0]:
		_add_part(MeshKit.cylinder(0.0165, 0.0165, 0.34, 16), Vector3(side * 0.0165, 0.02, -0.175), blued, Vector3(PI * 0.5, 0, 0), hinge)
		_add_part(MeshKit.cylinder(0.011, 0.011, 0.005, 12), Vector3(side * 0.0165, 0.02, -0.345), _material(Color(0.01, 0.01, 0.01), 0.9), Vector3(PI * 0.5, 0, 0), hinge)
	_add_box(Vector3(0.012, 0.006, 0.32), Vector3(0, 0.04, -0.175), blued, Vector3.ZERO, hinge)
	_add_box(Vector3(0.058, 0.03, 0.13), Vector3(0, -0.01, -0.11), wood, Vector3.ZERO, hinge)
	_add_sphere(0.004, Vector3(0, _sight_height - 0.004, -0.33), _material(Color(0.95, 0.85, 0.5), 0.3), hinge)
	_add_box(Vector3(0.042, 0.12, 0.06), Vector3(0, -0.055, 0.12), wood, Vector3(0.45, 0, 0))
	_add_box(Vector3(0.006, 0.026, 0.04), Vector3(0, -0.022, 0.06), blued)
	spec["muzzle_z"] = -0.35
	spec["muzzle_y"] = 0.02
	spec["support"] = Vector3(-0.005, -0.035, -0.11)
	spec["flash"] = 0.19


func _model_auto12(spec: Dictionary) -> void:
	_hip_pose = Vector3(0.2, -0.21, -0.33)
	_sight_height = 0.078
	_ads_depth = -0.28
	var black: StandardMaterial3D = _steel(Color(0.045, 0.047, 0.055), 0.6, 0.3)
	var dark: StandardMaterial3D = _steel(Color(0.03, 0.03, 0.035), 0.5, 0.35)
	var polymer: StandardMaterial3D = _material(Color(0.055, 0.055, 0.06), 0.85)
	_add_box(Vector3(0.052, 0.08, 0.24), Vector3(0, 0.022, -0.02), black)
	_add_cylinder(0.013, 0.46, Vector3(0, 0.045, -0.37), dark)
	_add_cylinder(0.013, 0.36, Vector3(0, 0.013, -0.3), black)
	_add_box(Vector3(0.035, 0.045, 0.02), Vector3(0, 0.03, -0.48), black)
	_add_box(Vector3(0.05, 0.045, 0.18), Vector3(0, 0.015, -0.24), polymer)
	_add_box(Vector3(0.034, 0.11, 0.045), Vector3(0, -0.06, 0.1), polymer, Vector3(0.3, 0, 0))
	_add_box(Vector3(0.045, 0.085, 0.24), Vector3(0, -0.01, 0.25), polymer)
	for shell: int in range(4):
		_add_cylinder(0.009, 0.03, Vector3(-0.034, 0.02, -0.07 + shell * 0.022), _material(Color(0.1, 0.35, 0.7), 0.5), Vector3(0, 0, PI * 0.5))
	if not _has_optic:
		_aperture(0.05, dark)
		_front_post(-0.58, 0.058, dark)
	spec["optic_base"] = 0.062
	spec["optic_z"] = -0.02
	spec["grip_at"] = Vector3(0, -0.035, -0.24)
	spec["muzzle_z"] = -0.61
	spec["muzzle_y"] = 0.045
	spec["support"] = Vector3(-0.005, -0.02, -0.24)
	spec["flash"] = 0.15


func _model_bolt(spec: Dictionary) -> void:
	_hip_pose = Vector3(0.21, -0.23, -0.33)
	_sight_height = 0.086
	_ads_depth = -0.17
	var steel: StandardMaterial3D = _steel(Color(0.08, 0.085, 0.1), 0.55, 0.4)
	var dark: StandardMaterial3D = _steel(Color(0.035, 0.04, 0.05), 0.5, 0.35)
	var olive: StandardMaterial3D = _material(Color(0.2, 0.23, 0.13), 0.85)
	_add_box(Vector3(0.05, 0.075, 0.3), Vector3(0, 0.015, -0.05), steel)
	_add_cylinder(0.012, 0.46, Vector3(0, 0.03, -0.43), dark)
	_add_box(Vector3(0.05, 0.1, 0.3), Vector3(0, -0.025, 0.23), olive)
	_add_box(Vector3(0.056, 0.05, 0.3), Vector3(0, -0.005, -0.3), olive)
	if not _has_optic:
		_add_cylinder(0.022, 0.3, Vector3(0, 0.086, -0.06), dark, Vector3(PI * 0.5, 0, 0))
		_add_cylinder(0.031, 0.07, Vector3(0, 0.086, -0.23), dark, Vector3(PI * 0.5, 0, 0))
		_add_cylinder(0.027, 0.05, Vector3(0, 0.086, 0.11), dark, Vector3(PI * 0.5, 0, 0))
		_add_box(Vector3(0.02, 0.04, 0.02), Vector3(0, 0.055, -0.13), dark)
		_add_box(Vector3(0.02, 0.04, 0.02), Vector3(0, 0.055, 0.02), dark)
	var bolt: Node3D = Node3D.new()
	bolt.position = Vector3(0.04, 0.03, 0.03)
	bolt.set_meta("rest_z", 0.03)
	_model.add_child(bolt)
	_cycler = bolt
	_add_box(Vector3(0.055, 0.014, 0.014), Vector3.ZERO, steel, Vector3.ZERO, bolt)
	_add_sphere(0.012, Vector3(0.03, 0, 0), steel, bolt)
	spec["optic_base"] = 0.0525
	spec["optic_z"] = -0.06
	spec["mag_size"] = Vector3(0.03, 0.07, 0.06)
	spec["mag_at"] = Vector3(0, -0.055, -0.08)
	spec["muzzle_z"] = -0.66
	spec["muzzle_y"] = 0.03
	spec["support"] = Vector3(-0.005, -0.06, -0.3)
	spec["flash"] = 0.14


func _model_dmr(spec: Dictionary) -> void:
	_hip_pose = Vector3(0.21, -0.23, -0.33)
	_sight_height = 0.092
	_ads_depth = -0.2
	var steel: StandardMaterial3D = _steel(Color(0.06, 0.062, 0.07), 0.6, 0.35)
	var dark: StandardMaterial3D = _steel(Color(0.035, 0.04, 0.05), 0.5, 0.35)
	var polymer: StandardMaterial3D = _material(Color(0.06, 0.06, 0.065), 0.85)
	var wood: StandardMaterial3D = _wood(Color(0.34, 0.17, 0.07))
	_add_box(Vector3(0.052, 0.08, 0.32), Vector3(0, 0.018, -0.04), steel)
	_add_box(Vector3(0.044, 0.016, 0.2), Vector3(0, 0.064, 0.0), steel)
	_add_box(Vector3(0.012, 0.012, 0.08), Vector3(0.024, 0.066, -0.13), dark)
	_add_box(Vector3(0.012, 0.014, 0.03), Vector3(-0.032, 0.03, -0.12), dark)
	_add_box(Vector3(0.06, 0.06, 0.24), Vector3(0, 0.018, -0.33), polymer)
	for vent: int in range(5):
		_add_box(Vector3(0.062, 0.008, 0.018), Vector3(0, 0.03, -0.25 - vent * 0.04), dark)
	_add_box(Vector3(0.028, 0.04, 0.025), Vector3(0, 0.052, -0.56), steel)
	_add_cylinder(0.012, 0.3, Vector3(0, 0.03, -0.6), dark)
	_add_cylinder(0.016, 0.06, Vector3(0, 0.03, -0.76), dark)
	_add_box(Vector3(0.034, 0.11, 0.046), Vector3(0, -0.07, 0.06), polymer, Vector3(0.3, 0, 0))
	_add_box(Vector3(0.006, 0.028, 0.05), Vector3(0, -0.04, 0.015), steel)
	_add_box(Vector3(0.046, 0.1, 0.28), Vector3(0, -0.02, 0.24), wood)
	if not _has_optic:
		_aperture(0.09, dark)
		_front_post(-0.56, 0.072, dark)
	spec["optic_base"] = 0.074
	spec["optic_z"] = -0.08
	spec["mount"] = 0.004
	spec["mag_size"] = Vector3(0.032, 0.12, 0.075)
	spec["mag_at"] = Vector3(0, -0.09, -0.09)
	spec["mag_angles"] = Vector3(0.05, 0, 0)
	spec["grip_at"] = Vector3(0, -0.04, -0.34)
	spec["muzzle_z"] = -0.79
	spec["muzzle_y"] = 0.03
	spec["support"] = Vector3(-0.01, -0.03, -0.34)
	spec["flash"] = 0.16


## Iron sights. Every sight's top edge sits exactly on `_sight_height`, the line
## the ADS pose centres on the screen, so the front post tip marks the shot.
func _aperture(z: float, material: StandardMaterial3D) -> void:
	var y: float = _sight_height
	_add_box(Vector3(0.008, 0.03, 0.012), Vector3(-0.0105, y, z), material)
	_add_box(Vector3(0.008, 0.03, 0.012), Vector3(0.0105, y, z), material)
	_add_box(Vector3(0.029, 0.008, 0.012), Vector3(0, y - 0.0115, z), material)
	_add_box(Vector3(0.029, 0.006, 0.012), Vector3(0, y + 0.012, z), material)
	_add_box(Vector3(0.02, y - 0.0155 - 0.05, 0.02), Vector3(0, (y - 0.0155 + 0.05) * 0.5, z), material)


func _notch(z: float, base_top: float, material: StandardMaterial3D) -> void:
	var height: float = _sight_height - base_top
	for side: float in [-1.0, 1.0]:
		_add_box(Vector3(0.009, height, 0.01), Vector3(side * 0.0085, base_top + height * 0.5, z), material)


func _front_post(z: float, base_top: float, material: StandardMaterial3D) -> void:
	var height: float = _sight_height - base_top
	_add_box(Vector3(0.0035, height, 0.006), Vector3(0, base_top + height * 0.5, z), material)
	_add_box(Vector3(0.018, 0.008, 0.02), Vector3(0, base_top - 0.004, z), material)


## Hollow optic housing centred on the sight line, with glass and a glowing reticle.
func _frame_sight(window: Vector2, z: float, material: StandardMaterial3D, reticle: Color, ring: bool = false) -> void:
	var y: float = _sight_height
	var wall: float = 0.006
	for side: float in [-1.0, 1.0]:
		_add_box(Vector3(wall, window.y + wall * 2.0, 0.03), Vector3(side * (window.x * 0.5 + wall * 0.5), y, z), material)
	_add_box(Vector3(window.x + wall * 2.0, wall, 0.03), Vector3(0, y + window.y * 0.5 + wall * 0.5, z), material)
	_add_box(Vector3(window.x + wall * 2.0, wall * 1.4, 0.03), Vector3(0, y - window.y * 0.5 - wall * 0.7, z), material)
	var glass: StandardMaterial3D = StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.8, 1.0, 0.08)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pane: MeshInstance3D = MeshInstance3D.new()
	pane.mesh = MeshKit.rounded_box(Vector3(window.x, window.y, 0.002), 0.0005, 1)
	pane.material_override = glass
	pane.position = Vector3(0, y, z + 0.01)
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(pane)
	_add_sphere(0.0018, Vector3(0, y, z + 0.008), _glow(reticle))
	if ring:
		var halo: MeshInstance3D = MeshInstance3D.new()
		halo.mesh = MeshKit.torus(0.0085, 0.0098, 20, 4)
		halo.material_override = _glow(reticle)
		halo.rotation.x = PI * 0.5
		halo.position = Vector3(0, y, z + 0.008)
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_model.add_child(halo)


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var key: String = str(color) + str(roughness)
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	_materials[key] = material
	return material


## Gun steel: a little metallic so edges catch the sky and neon.
func _steel(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var key: String = "steel" + str(color) + str(roughness) + str(metallic)
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	material.metallic_specular = 0.6
	_materials[key] = material
	return material


## Lacquered wood with a procedural grain (local triplanar, so it sticks to the gun).
func _wood(color: Color) -> StandardMaterial3D:
	var key: String = "wood" + str(color)
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	if not _materials.has("wood_grain"):
		var image: Image = Image.create(64, 64, true, Image.FORMAT_RGB8)
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 1911
		var offsets: PackedFloat32Array = PackedFloat32Array()
		for x: int in range(64):
			offsets.append(rng.randf_range(0.0, TAU))
		for y: int in range(64):
			for x: int in range(64):
				var ring: float = sin(float(y) * 0.55 + sin(float(x) * 0.12 + offsets[x / 8]) * 2.4)
				var value: float = 0.78 + ring * 0.13 + rng.randf_range(-0.04, 0.04)
				image.set_pixel(x, y, Color(value, value, value))
		image.generate_mipmaps()
		_materials["wood_grain"] = ImageTexture.create_from_image(image)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = _materials["wood_grain"] as ImageTexture
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(9.0, 9.0, 9.0)
	material.roughness = 0.42
	material.metallic_specular = 0.55
	_materials[key] = material
	return material


func _glow(color: Color) -> StandardMaterial3D:
	var key: String = "glow" + str(color)
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials[key] = material
	return material


func _add_part(mesh: Mesh, offset: Vector3, material: StandardMaterial3D, angles: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var owner_node: Node3D = parent if parent != null else _model
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.position = offset
	mesh_instance.rotation = angles
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	owner_node.add_child(mesh_instance)
	return mesh_instance


func _add_box(size: Vector3, offset: Vector3, material: StandardMaterial3D, angles: Vector3 = Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var radius: float = clampf(minf(size.x, minf(size.y, size.z)) * 0.18, 0.0006, 0.008)
	return _add_part(MeshKit.rounded_box(size, radius, 2), offset, material, angles, parent)


## Cylinders run along local Z by default (barrels); pass angles to reorient.
func _add_cylinder(radius: float, length: float, offset: Vector3, material: StandardMaterial3D, angles: Vector3 = Vector3(PI * 0.5, 0, 0), parent: Node3D = null) -> MeshInstance3D:
	return _add_part(MeshKit.cylinder(radius, radius, length, 16), offset, material, angles, parent)


func _add_sphere(radius: float, offset: Vector3, material: StandardMaterial3D, parent: Node3D = null) -> MeshInstance3D:
	return _add_part(MeshKit.sphere(radius, radius * 2.0, 12, 6), offset, material, Vector3.ZERO, parent)


func _add_capsule_between(from: Vector3, to: Vector3, radius: float, material: StandardMaterial3D) -> MeshInstance3D:
	var span: Vector3 = to - from
	var mesh_instance: MeshInstance3D = _add_part(MeshKit.capsule(radius, span.length() + radius * 2.0, 10, 2), (from + to) * 0.5, material, Vector3.ZERO)
	mesh_instance.basis = Basis(Quaternion(Vector3.UP, span.normalized()))
	return mesh_instance
