class_name FastOnline
extends Node
## The online match (docs/NET_M1_SPEC.md §6–7): remote players, shared cars, the Ledger and
## the cash case, and — on the host — the round rules and payouts. main.gd stays the offline
## game; it calls in here at a handful of hook points when `active` is true.
##
## Authority: the host decides seats, items, car health, the clock and money; each peer moves
## its own body and drives its own car (DEMO trade-off, spec §2). No bots exist online.

const Factions = preload("res://scripts/factions.gd")
const RemoteScript = preload("res://scripts/remote_player.gd")
const MeshKit = preload("res://scripts/mesh_kit.gd")

const BUY_SECONDS: float = 30.0
const LIVE_SECONDS: float = 600.0
const SETTLE_SECONDS: float = 15.0
const RESPAWN_SECONDS: float = 10.0
const LEDGER: int = 0
const CASH: int = 1
const LEDGER_VALUE: int = 9000
const CASH_VALUE: int = 6000
const CLEAN_BONUS: int = 1500
const ROUND_WAGE: int = 1000
const START_CASH: int = 3200
const CASH_CAP: int = 16000
const REACH: float = 2.8
const BANK_REACH: float = 5.5
const STATE_RATE: float = 0.05
const DRIVER_RATE: float = 1.0 / 30.0
const HOST_CAR_RATE: float = 0.1
## Item ids from PHONE_BASE up: one crew phone per crew, in Factions.ORDER order. Ids below are trade items.
const PHONE_BASE: int = 2
const TRADE_ITEMS: Array[int] = [LEDGER, CASH]
const PHONE_REACH: float = 2.4
## The Week (docs/LEAD_DESIGN_DECISIONS.md §1): a match is a Week of Days, Friday is always the Dead Drop.
const WEEKDAYS: PackedStringArray = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY"]
## Contract value by weekday: honesty is cheap on Monday, betrayal is expensive on Thursday.
const DAY_VALUE: Array[float] = [0.6, 0.8, 1.0, 1.25, 1.6]
const WEEK_END_SECONDS: float = 20.0
const DEFAULT_WEEK_DAYS: int = 5

var game: Node
var net: FastNet
var active: bool = false
## Round state as last broadcast by the host.
var phase: String = ""
var time_left: float = 0.0
var round_number: int = 0
## Day of the Week (1..week_days) and which Week this is. round_number keeps counting across Weeks.
var day: int = 0
var week: int = 1
var week_days: int = DEFAULT_WEEK_DAYS
## Yesterday's results ("the morning paper"), shown at the start of the buy phase.
var recap: Array = []
## Friday: where the Dead Drop is (a neutral landmark name), announced when the doors open.
var drop_site: String = ""
## Phase lengths; tests shorten them (tests/week_flow.gd).
var buy_seconds: float = BUY_SECONDS
var live_seconds: float = LIVE_SECONDS
var settle_seconds: float = SETTLE_SECONDS
var week_end_seconds: float = WEEK_END_SECONDS
var seller: String = ""
var buyer: String = ""
var bank: Dictionary = {}
var results: Array = []
## item id -> {kind, holder, pos, banked}
var items: Dictionary = {}
var remotes: Dictionary = {}
var chat_ui: Control
var lobby: Control

var _item_nodes: Dictionary = {}
var _remote_root: Node3D
var _state_timer: float = 0.0
var _car_timer: float = 0.0
var _host_car_timer: float = 0.0
## Host: the last transform sent for each undriven car, so a car that comes to rest still
## sends its settled pose once (and a reset car its new spot).
var _host_car_sent: Dictionary = {}
var _broadcast_timer: float = 0.0
var _respawn_timer: float = -1.0
var _last_attacker: int = 0
var _applying_remote_glass: bool = false
var _pending_seat: Vector2i = Vector2i(-1, -1)
var _seat_of: Dictionary = {}
var _fired_at: float = -10.0
## Host only: which crews killed which this round ("a>b" keys).
var _kills: Dictionary = {}
var _round_rotation: int = 0
## Pellets that hit the same player in one frame go to the host as one summed claim
## (the host accepts at most 25 claims a second per shooter).
var _pending_hits: Dictionary = {}
## The round this peer last spawned for (a late joiner spawns mid-round).
var _spawned_round: int = -1
## The Week this peer last started (a new Week resets money and gear), -1 before the first buy phase.
var _seen_week: int = -1
## Last value pushed to player.set_sidearm_only, so it is only called on change.
var _sidearm_only: bool = false


func setup(owner_game: Node, owner_net: FastNet) -> void:
	game = owner_game
	net = owner_net
	_remote_root = Node3D.new()
	_remote_root.name = "Remotes"
	game.add_child(_remote_root)
	net.max_cars = game.cars.size()
	net.max_items = PHONE_BASE + Factions.ORDER.size()
	# Only whoever holds a crew phone may call another crew (docs/LEAD_DESIGN_DECISIONS.md §2).
	net.call_gate = func(sender: int) -> bool: return not _phone_of(sender).is_empty()
	net.seat_owner = func(car: int) -> int: return net.seat_holder(car, 0)
	net.match_started.connect(_on_match_started)
	net.peer_joined.connect(_on_peer_joined)
	net.peer_left.connect(_on_peer_left)
	net.server_closed.connect(_on_server_closed)
	net.remote_state.connect(_on_remote_state)
	net.remote_shot.connect(_on_remote_shot)
	net.damage_received.connect(_on_damage_received)
	net.player_died.connect(_on_player_died)
	net.seat_update.connect(_on_seat_update)
	net.remote_car.connect(_on_remote_car)
	net.car_health.connect(_on_car_health)
	net.remote_glass.connect(_on_remote_glass)
	net.item_update.connect(_on_item_update)
	net.round_state.connect(_on_round_state)
	net.grant.connect(_on_grant)
	net.chat.connect(_on_chat)
	net.world_event.connect(_on_world_event)
	net.host_seat_request.connect(_host_seat_request)
	net.host_seat_leave.connect(_host_seat_leave)
	net.host_car_damage.connect(_host_car_damage)
	net.host_item_request.connect(_host_item_request)
	# Steam invites (overlay "Join Game" or +connect_lobby at launch) jump straight to the lobby screen.
	net.steam_join_started.connect(func() -> void:
		if not active:
			show_lobby())
	net.steam_autostart.call_deferred()
	_build_items()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func car_index(ride: Node) -> int:
	return game.cars.find(ride)


# --------------------------------------------------------------------- lobby and start

func show_lobby() -> void:
	if not is_instance_valid(lobby):
		lobby = (load("res://scripts/lobby_ui.gd") as GDScript).new()
		game.hud.get_parent().add_child(lobby)
		lobby.call("setup", net)
		lobby.visible = false
		lobby.connect("back_requested", func() -> void:
			lobby.visible = false
			if not active:
				net.leave()
				game._show_title())
	game.menu.hide()
	lobby.call("open")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_match_started() -> void:
	active = true
	if is_instance_valid(lobby):
		lobby.visible = false
	game._hide_title_set()
	game.cash = START_CASH
	game.round_number = 0
	game._carry_gear = false
	day = 0
	week = 1
	recap = []
	drop_site = ""
	_seen_week = -1
	for guard: Node in game._all_guards():
		guard.call("set_present", false)
	_ensure_chat()
	for id: int in net.players.keys():
		if id != net.my_id():
			_spawn_remote(id)
	for ride: FastCar in game.cars:
		ride.set_net_puppet(not net.is_host())
		ride.net_damage_hook = _car_damage_hook
	_apply_my_crew()
	if net.is_host():
		_host_new_round()
	else:
		game.menu.hide()
		game._message("Joined the match. Waiting for the next phase from the host...", 5.0)


func _apply_my_crew() -> void:
	var my_crew: String = net.crew_of(net.my_id())
	if Factions.ORDER.has(my_crew):
		game.crew = my_crew
		game._apply_crew()
	# Crewmates spread out along the HQ doorstep instead of spawning inside each other.
	var mates: Array[int] = net.members_of(game.crew)
	mates.sort()
	var slot: int = maxi(mates.find(net.my_id()), 0)
	var side: Vector3 = Basis(Vector3.UP, game.hq_yaw) * Vector3.RIGHT
	game.hq_spawn += side * ((slot + 1) / 2) * 1.4 * (1.0 if slot % 2 == 1 else -1.0)
	if is_instance_valid(chat_ui):
		chat_ui.call("set_my_crew", game.crew)


func leave_match() -> void:
	var was_active: bool = active
	active = false
	phase = ""
	_spawned_round = -1
	round_number = 0
	day = 0
	week = 1
	recap = []
	drop_site = ""
	_set_sidearm_only(false)
	bank.clear()
	results = []
	_kills.clear()
	for id: int in remotes.keys():
		(remotes[id] as Node).queue_free()
	remotes.clear()
	_seat_of.clear()
	for ride: FastCar in game.cars:
		ride.set_net_puppet(false)
		ride.net_damage_hook = Callable()
	for item: int in _item_nodes.keys():
		(_item_nodes[item] as Node3D).visible = false
	items.clear()
	if is_instance_valid(chat_ui):
		chat_ui.visible = false
	net.leave()
	if was_active:
		game._show_title()


func _on_server_closed() -> void:
	if active:
		leave_match()
		game._message("The host closed the match.", 6.0)


# --------------------------------------------------------------------- remotes

func _spawn_remote(id: int) -> void:
	if remotes.has(id) or id == net.my_id():
		return
	var remote: FastRemote = RemoteScript.new()
	remote.name = "Remote%d" % id
	remote.setup(id, net.crew_of(id), net.name_of(id))
	_remote_root.add_child(remote)
	remote.struck.connect(_on_remote_struck.bind(id))
	remotes[id] = remote


func _on_peer_joined(id: int) -> void:
	if not active:
		return
	_spawn_remote(id)
	if net.is_host():
		# Catch a late joiner up: where the cases are, who sits where, where parked cars ended up.
		for item: int in items.keys():
			var data: Dictionary = (items[item] as Dictionary).duplicate()
			data["msg"] = ""
			net.broadcast_item(item, data)
		for car: int in range(game.cars.size()):
			for seat: int in range((game.cars[car] as FastCar).seat_count()):
				var holder: int = net.seat_holder(car, seat)
				if holder != 0:
					net.broadcast_seat(car, seat, holder)
		_host_car_sent.clear()
		_host_broadcast()


func _on_peer_left(id: int) -> void:
	if remotes.has(id):
		(remotes[id] as Node).queue_free()
		remotes.erase(id)
	_seat_of.erase(id)
	if active and net.is_host():
		# Their seats free up and whatever they carried drops where they stood.
		for ride_index: int in range(game.cars.size()):
			for seat_index: int in range((game.cars[ride_index] as FastCar).seat_count()):
				if net.seat_holder(ride_index, seat_index) == id:
					net.broadcast_seat(ride_index, seat_index, 0)
		_host_drop_all(id, net.latest_pos(id))


func _on_remote_state(id: int, state: Dictionary) -> void:
	if not active:
		return
	if not remotes.has(id):
		_spawn_remote(id)
	(remotes[id] as FastRemote).push_state(_now(), state)


func _on_remote_struck(amount: float, _source: Vector3, id: int) -> void:
	# My car ran someone over: claim it like a hit.
	var remote: FastRemote = remotes.get(id)
	if remote == null:
		return
	net.send_claim_hit(id, amount, false, game.player.global_position, remote.global_position + Vector3(0, 1, 0), "")


# --------------------------------------------------------------------- per-frame

func tick(delta: float) -> void:
	if not active:
		return
	if net.is_host():
		_host_tick(delta)
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = STATE_RATE
		_send_my_state()
	var vehicle: FastCar = game.vehicle
	if vehicle != null and game.seat == 0:
		_car_timer -= delta
		if _car_timer <= 0.0:
			_car_timer = DRIVER_RATE
			var data: Dictionary = vehicle.net_state()
			net.send_car_state(car_index(vehicle), data["xform"], data["vel"], data["steer"], data["speed"], data["flags"])
	if _respawn_timer > 0.0:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
	_set_sidearm_only(_my_trade_item() >= 0)
	_update_item_visuals()


## The user's rule: carrying a trade item limits you to the sidearm (player.gd owns the weapon logic).
func _set_sidearm_only(on: bool) -> void:
	if on == _sidearm_only or game == null or game.player == null:
		return
	_sidearm_only = on
	if game.player.has_method("set_sidearm_only"):
		game.player.call("set_sidearm_only", on)


func _send_my_state() -> void:
	var player: FastPlayer = game.player
	var flags: int = 0
	if player.crouching: flags |= 1
	if player.aiming: flags |= 2
	if player.is_dead(): flags |= 4
	if _now() - _fired_at < 0.25: flags |= 8
	if _holding(LEDGER): flags |= 16
	if _holding(CASH): flags |= 32
	if player.sprinting: flags |= 64
	if player.get("hands_up") == true: flags |= 128
	var car: int = car_index(game.vehicle) if game.vehicle != null else -1
	var seat: int = game.seat if game.vehicle != null else -1
	var yaw: float = player.rotation.y
	net.send_state(player.global_position, yaw, player.look_pitch(), flags, player.weapon_id, car, seat, player.health)


func _holding(item: int) -> bool:
	return items.has(item) and int(items[item].get("holder", 0)) == net.my_id()


# --------------------------------------------------------------------- shooting

## main._on_shot hit a remote player: the host validates and forwards the damage.
func claim_hit(remote: FastRemote, amount: float, head: bool, origin: Vector3, point: Vector3) -> void:
	var entry: Dictionary = _pending_hits.get(remote.peer_id, {"amount": 0.0, "head": false, "origin": origin, "point": point})
	entry["amount"] = float(entry["amount"]) + amount
	entry["head"] = bool(entry["head"]) or head
	_pending_hits[remote.peer_id] = entry
	remote.flash_hit()
	if _pending_hits.size() == 1 and float(entry["amount"]) == amount:
		_flush_hits.call_deferred()


func _flush_hits() -> void:
	for victim: int in _pending_hits.keys():
		var entry: Dictionary = _pending_hits[victim]
		net.send_claim_hit(victim, float(entry["amount"]), bool(entry["head"]), entry["origin"], entry["point"], game.player.weapon_id)
	_pending_hits.clear()


## Once per trigger pull: everyone else hears the shot and sees a tracer.
func weapon_fired(quiet: bool) -> void:
	if not active:
		return
	_fired_at = _now()
	var camera: Camera3D = game.player.camera
	var origin: Vector3 = camera.global_position
	var query := PhysicsRayQueryParameters3D.create(origin, origin - camera.global_basis.z * 200.0)
	query.exclude = [game.player.get_rid()]
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
	var end: Vector3 = hit.position if not hit.is_empty() else origin - camera.global_basis.z * 200.0
	net.send_shot_fx(game.player.muzzle_position(), end, game.player.weapon_id, quiet)


func _on_remote_shot(id: int, origin: Vector3, end: Vector3, weapon: String, quiet: bool) -> void:
	if not active:
		return
	var stats: Dictionary = FastPlayer.WEAPONS.get(weapon, FastPlayer.WEAPONS["pistol"])
	# Distance-aware gunshots (near / far samples) when sfx.gd offers them.
	var shot_fx: bool = game.sfx.has_method("play_shot_at")
	var listener: Vector3 = game.player.camera.global_position
	if quiet:
		if shot_fx:
			game.sfx.call("play_shot_at", "suppressed", origin, listener)
		else:
			game.sfx.play_at("suppressed", origin)
		game.effects.call("tracer", origin, end, Color(0.55, 0.52, 0.48), 0.008, 0.03)
	else:
		if shot_fx:
			game.sfx.call("play_shot_at", str(stats.get("sound", weapon)), origin, listener, 1.0, 3.0)
		else:
			game.sfx.play_at(str(stats.get("sound", weapon)), origin, 1.0, 3.0)
		game.effects.call("tracer", origin, end, Color(1.0, 0.86, 0.55), 0.016, 0.05)
		game.effects.call("muzzle_light", origin)
	# A near miss cracks past your ear.
	var head: Vector3 = game.player.camera.global_position
	if id != net.my_id() and Geometry3D.get_closest_point_to_segment(head, origin, end).distance_to(head) < 2.0:
		game.sfx.play("whiz", randf_range(0.85, 1.15))


func _on_damage_received(amount: float, source: Vector3, attacker: int) -> void:
	if not active or game.player.is_dead():
		return
	_last_attacker = attacker
	game.player.take_damage(amount, source)


## main._on_player_died calls this online instead of ending the contract.
func on_local_death() -> void:
	net.send_report_death(_last_attacker, game.player.global_position)
	_respawn_timer = RESPAWN_SECONDS
	game._message("You were dropped. Anything you carried is on the ground. Back at HQ in %d seconds." % int(RESPAWN_SECONDS), 6.0)


func _respawn() -> void:
	_respawn_timer = -1.0
	if game.vehicle != null:
		game._exit_vehicle(true)
	game.player.reset_player(game.hq_spawn)
	game.player.set_loadout(["pistol"])
	game.player.armor = 0.0
	game.player.can_fire = phase == "live"
	game.player.face(game.hq_yaw)
	game.player.camera.make_current()
	_last_attacker = 0
	game._message("Back at HQ with the P9. Your crew still needs you.", 4.0)


func _on_player_died(id: int, killer: int, pos: Vector3) -> void:
	if not active:
		return
	if net.is_host():
		_host_drop_all(id, pos)
		var a: String = net.crew_of(killer)
		var b: String = net.crew_of(id)
		if killer > 0 and not a.is_empty() and a != b:
			_kills["%s>%s" % [a, b]] = true
	var text: String = "%s was dropped" % net.name_of(id)
	if killer > 0 and killer != id:
		text += " by %s" % net.name_of(killer)
	_system(text + ".")


# --------------------------------------------------------------------- seats and cars

## main._enter_vehicle asks here first: true once the host gave us that seat.
func seat_granted(ride: FastCar, seat: int) -> bool:
	return net.seat_holder(car_index(ride), seat) == net.my_id()


func request_seat(ride: FastCar, seat: int) -> void:
	_pending_seat = Vector2i(car_index(ride), seat)
	net.send_request_seat(_pending_seat.x, seat)


func leave_seat(ride: FastCar, seat: int) -> void:
	if active:
		net.send_leave_seat(car_index(ride), seat)


func _on_seat_update(car: int, seat: int, peer: int) -> void:
	if not active or car < 0 or car >= game.cars.size():
		return
	var ride: FastCar = game.cars[car]
	var me: int = net.my_id()
	if seat < ride.seat_count():
		if peer == me:
			pass
		elif peer == 0:
			if ride.occupants[seat] != "player":
				ride.occupants[seat] = ""
		else:
			ride.occupants[seat] = "remote"
	if seat == 0:
		if peer == me:
			ride.set_net_puppet(false)
		elif peer == 0:
			ride.occupied = false if ride != game.vehicle or game.seat != 0 else ride.occupied
			ride.set_net_puppet(not net.is_host())
			if net.is_host():
				ride.wake()
		else:
			ride.occupied = false
			ride.set_net_puppet(true)
	# Remote bodies follow their seats.
	for id: int in _seat_of.keys():
		var held: Vector2i = _seat_of[id]
		if held == Vector2i(car, seat) and id != peer:
			_seat_of.erase(id)
			if remotes.has(id):
				(remotes[id] as FastRemote).seat_out()
	if peer != 0 and peer != me and remotes.has(peer):
		_seat_of[peer] = Vector2i(car, seat)
		(remotes[peer] as FastRemote).seat_in(ride, ride.seat_info(seat)["eye"], ride.is_bike())
	# Our own request came back granted.
	if peer == me and _pending_seat == Vector2i(car, seat):
		_pending_seat = Vector2i(-1, -1)
		if game.vehicle == ride:
			game._swap_to_seat(seat)
		else:
			if game.vehicle != null:
				game._exit_vehicle(true)
			game._enter_vehicle(ride, seat)


func _on_remote_car(car: int, data: Dictionary) -> void:
	if not active or car < 0 or car >= game.cars.size():
		return
	var ride: FastCar = game.cars[car]
	if ride == game.vehicle and game.seat == 0:
		return
	if not ride.net_puppet:
		ride.set_net_puppet(true)
	ride.push_net_state(_now(), data)


func _car_damage_hook(ride: FastCar, amount: float) -> void:
	if not active:
		ride.apply_damage(amount)
		return
	net.send_car_damage(car_index(ride), amount)


func _on_car_health(car: int, health: float, disabled: bool) -> void:
	if car >= 0 and car < game.cars.size():
		(game.cars[car] as FastCar).set_net_health(health, disabled)


## main._on_car_glass_broken: tell everyone which window went.
func glass_broken(ride: FastCar, index: int) -> void:
	if active and not _applying_remote_glass:
		net.send_glass(car_index(ride), index)


func _on_remote_glass(car: int, index: int) -> void:
	if car < 0 or car >= game.cars.size():
		return
	_applying_remote_glass = true
	(game.cars[car] as FastCar).break_glass(index)
	_applying_remote_glass = false


# --------------------------------------------------------------------- shared world state

## main._interact toggled a shop door: everyone else sees (and is blocked by) it too.
func door_changed(index: int) -> void:
	if active and index >= 0 and index < game.world.interactable_doors.size():
		net.send_world_event("door", index, 1 if bool(game.world.interactable_doors[index]["open"]) else 0)


func _on_world_event(kind: String, index: int, value: int) -> void:
	if not active:
		return
	if kind == "door" and index < game.world.interactable_doors.size():
		game.world.set_door_open(index, value == 1)
	elif kind == "lift" and game.world.has_method("call_lift"):
		game.world.call("call_lift", index, value)


# --------------------------------------------------------------------- items (client side)
#
# Item ids: LEDGER and CASH are trade items (carry one at a time, sidearm only while you do).
# PHONE_BASE + i is crew Factions.ORDER[i]'s phone: its own slot, dropped with K, never banked.

func _build_items() -> void:
	for item: int in TRADE_ITEMS:
		var node: Node3D = Node3D.new()
		node.name = "Ledger" if item == LEDGER else "CashCase"
		game.add_child(node)
		var leather: StandardMaterial3D = StandardMaterial3D.new()
		leather.albedo_color = Color(0.2, 0.11, 0.07) if item == LEDGER else Color(0.72, 0.74, 0.76)
		leather.roughness = 0.55 if item == LEDGER else 0.3
		leather.metallic = 0.0 if item == LEDGER else 0.7
		var body: MeshInstance3D = MeshInstance3D.new()
		body.mesh = MeshKit.rounded_box(Vector3(0.5, 0.36, 0.13), 0.025, 2)
		body.material_override = leather
		node.add_child(body)
		var trim: StandardMaterial3D = StandardMaterial3D.new()
		trim.albedo_color = Color("d5a356") if item == LEDGER else Color(0.2, 0.21, 0.22)
		trim.metallic = 0.8
		trim.roughness = 0.3
		var handle: MeshInstance3D = MeshInstance3D.new()
		handle.mesh = MeshKit.rounded_box(Vector3(0.16, 0.04, 0.035), 0.012, 1)
		handle.material_override = trim
		handle.position.y = 0.21
		node.add_child(handle)
		node.add_child(_item_tag("THE LEDGER" if item == LEDGER else "CASH CASE", Color("edb965") if item == LEDGER else Color("cfd6da"), 30.0))
		node.visible = false
		_item_nodes[item] = node
	for index: int in range(Factions.ORDER.size()):
		var crew_id: String = Factions.ORDER[index]
		var phone: Node3D = Node3D.new()
		phone.name = "CrewPhone_" + crew_id
		game.add_child(phone)
		# A late-90s brick cellphone: dark shell, stub antenna, a band in the crew's colour.
		var shell: StandardMaterial3D = StandardMaterial3D.new()
		shell.albedo_color = Color(0.08, 0.08, 0.09)
		shell.roughness = 0.6
		var handset: MeshInstance3D = MeshInstance3D.new()
		handset.mesh = MeshKit.rounded_box(Vector3(0.09, 0.26, 0.06), 0.014, 1)
		handset.material_override = shell
		phone.add_child(handset)
		var antenna: MeshInstance3D = MeshInstance3D.new()
		antenna.mesh = MeshKit.rounded_box(Vector3(0.016, 0.12, 0.016), 0.005, 1)
		antenna.material_override = shell
		antenna.position = Vector3(0.028, 0.18, 0.0)
		phone.add_child(antenna)
		var band_material: StandardMaterial3D = StandardMaterial3D.new()
		band_material.albedo_color = Factions.color(crew_id)
		band_material.emission_enabled = true
		band_material.emission = Factions.color(crew_id)
		band_material.emission_energy_multiplier = 0.6
		var band: MeshInstance3D = MeshInstance3D.new()
		band.mesh = MeshKit.rounded_box(Vector3(0.094, 0.03, 0.064), 0.006, 1)
		band.material_override = band_material
		band.position.y = -0.06
		phone.add_child(band)
		phone.add_child(_item_tag("%s PHONE" % Factions.get_crew(crew_id)["short"], Factions.color(crew_id), 20.0))
		phone.visible = false
		_item_nodes[PHONE_BASE + index] = phone


func _item_tag(text: String, color: Color, reach: float) -> Label3D:
	var tag: Label3D = Label3D.new()
	tag.name = "Tag"
	tag.text = text
	tag.font_size = 34 if reach > 25.0 else 26
	tag.position.y = 0.9 if reach > 25.0 else 0.55
	tag.modulate = color
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.visibility_range_end = reach
	tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return tag


static func is_phone(item: int) -> bool:
	return item >= PHONE_BASE


## The crew a phone item belongs to.
static func phone_crew(item: int) -> String:
	var index: int = item - PHONE_BASE
	return Factions.ORDER[index] if index >= 0 and index < Factions.ORDER.size() else ""


static func phone_item(crew_id: String) -> int:
	var index: int = Factions.ORDER.find(crew_id)
	return PHONE_BASE + index if index >= 0 else -1


func _holder(item: int) -> int:
	return int((items.get(item, {}) as Dictionary).get("holder", 0))


func _loose(item: int) -> bool:
	var data: Dictionary = items.get(item, {})
	return not data.is_empty() and int(data.get("holder", 0)) == 0 and str(data.get("banked", "")).is_empty() and not bool(data.get("hidden", false))


## The trade item a peer carries (LEDGER or CASH), or -1.
func _trade_item_of(peer: int) -> int:
	for item: int in TRADE_ITEMS:
		if items.has(item) and _holder(item) == peer:
			return item
	return -1


func _my_trade_item() -> int:
	return _trade_item_of(net.my_id()) if net != null else -1


## The crew whose phone a peer carries, or "".
func _phone_of(peer: int) -> String:
	for item: int in items.keys():
		if is_phone(item) and _holder(item) == peer:
			return phone_crew(item)
	return ""


func _on_item_update(item: int, data: Dictionary) -> void:
	if not active or not _item_nodes.has(item):
		return
	var before: Dictionary = items.get(item, {})
	items[item] = data
	var message: String = str(data.get("msg", ""))
	if not message.is_empty():
		_system(message)
	# Picked up or lost by me: tell the player what to do next.
	var me: int = net.my_id()
	var holder: int = int(data.get("holder", 0))
	if holder == me and int(before.get("holder", 0)) != me:
		game.sfx.play("draw", 0.8)
		if is_phone(item):
			var owner_crew: String = phone_crew(item)
			var whose: String = "your crew's phone" if owner_crew == game.crew else "the %s phone. Your calls will come from them" % Factions.get_crew(owner_crew)["name"]
			game._message("You have %s. Open chat, TAB to a crew and call. %s drops it." % [whose, game._glyph("drop_phone")], 7.0)
		else:
			game._message("You have %s: sidearm only while you carry it. Bank it at your HQ (teal), trade it, or hide it. %s drops it." % [_item_name(item), game._glyph("drop")], 6.0)
	# Our own phone just walked off with a rival: the crew should know.
	if is_phone(item) and phone_crew(item) == game.crew and holder != 0 and holder != int(before.get("holder", 0)) and net.crew_of(holder) != game.crew:
		game._message("A rival has your crew's phone. Their calls will sound like you.", 6.0)


func _update_item_visuals() -> void:
	var spin: float = get_process_delta_time() * 0.6
	for item: int in _item_nodes.keys():
		var node: Node3D = _item_nodes[item]
		var on_ground: bool = _loose(item)
		node.visible = on_ground
		if on_ground:
			node.global_position = (items[item] as Dictionary).get("pos", Vector3.ZERO)
			if not is_phone(item):
				node.rotation.y += spin


func _item_name(item: int) -> String:
	if is_phone(item):
		return "the %s phone" % Factions.get_crew(phone_crew(item))["short"]
	return "the Ledger" if item == LEDGER else "the cash case"


## Phones can be picked up in the buy phase too (the crew phone sits at the HQ spawn); trade items only on the street.
func _item_phase_ok(item: int) -> bool:
	return phase == "live" or (phase == "buy" and is_phone(item))


## E on foot: pick up, or bank at HQ. True if it handled the key.
func interact() -> bool:
	if not active or (phase != "live" and phase != "buy") or game.player.is_dead():
		return false
	var at: Vector3 = game.player.global_position
	var mine: int = _my_trade_item()
	if phase == "live" and mine >= 0 and _flat(at, game.HOME) < BANK_REACH:
		net.send_item_request("bank", mine, at)
		return true
	for item: int in items.keys():
		if not _loose(item) or not _item_phase_ok(item):
			continue
		var reach: float = PHONE_REACH if is_phone(item) else REACH
		if at.distance_to((items[item] as Dictionary).get("pos", Vector3.INF)) >= reach:
			continue
		if is_phone(item) and not _phone_of(net.my_id()).is_empty():
			game._message("You already carry a phone. %s drops it." % game._glyph("drop_phone"), 3.0)
			return true
		if not is_phone(item) and mine >= 0:
			game._message("Hands full: drop %s first (%s)." % [_item_name(mine), game._glyph("drop")], 3.0)
			return true
		net.send_item_request("pickup", item, at)
		return true
	return false


## G: drop the trade item at your feet (the phone stays in its own slot).
func drop() -> bool:
	if not active:
		return false
	var mine: int = _my_trade_item()
	if mine < 0:
		return false
	net.send_item_request("drop", mine, game.player.global_position - game.player.global_basis.z * 1.0)
	return true


## K: drop the crew phone you carry.
func drop_phone() -> bool:
	if not active:
		return false
	for item: int in items.keys():
		if is_phone(item) and _holder(item) == net.my_id():
			net.send_item_request("drop", item, game.player.global_position - game.player.global_basis.z * 0.8)
			return true
	return false


func prompt_text() -> String:
	if not active or (phase != "live" and phase != "buy") or game.player.is_dead():
		return ""
	var at: Vector3 = game.player.global_position
	var mine: int = _my_trade_item()
	if phase == "live" and mine >= 0 and _flat(at, game.HOME) < BANK_REACH:
		return "[%s]  BANK %s AT YOUR HQ" % [game._glyph("interact"), _item_name(mine).to_upper()]
	for item: int in items.keys():
		if not _loose(item) or not _item_phase_ok(item):
			continue
		var reach: float = PHONE_REACH if is_phone(item) else REACH
		if at.distance_to((items[item] as Dictionary).get("pos", Vector3.INF)) < reach:
			if not is_phone(item) and mine >= 0:
				return "HANDS FULL  ·  [%s] DROP %s FIRST" % [game._glyph("drop"), _item_name(mine).to_upper()]
			return "[%s]  PICK UP %s" % [game._glyph("interact"), _item_name(item).to_upper()]
	return ""


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


# --------------------------------------------------------------------- the Week and the Day (client side)

## Weekday index 0..4 (MONDAY..FRIDAY). A short Week keeps its last Days, so it always ends on Friday.
static func weekday_index_of(the_day: int, days_in_week: int) -> int:
	return clampi(WEEKDAYS.size() - clampi(days_in_week, 1, WEEKDAYS.size()) + the_day - 1, 0, WEEKDAYS.size() - 1)


func weekday_index() -> int:
	return weekday_index_of(maxi(day, 1), week_days)


func day_name() -> String:
	return WEEKDAYS[weekday_index()]


## Friday is always the Dead Drop: no seller or buyer, no truce, whoever banks it is paid.
func is_dead_drop() -> bool:
	return weekday_index() == WEEKDAYS.size() - 1


## Today's value of a trade item (or the clean-deal bonus with item -1), rounded to $100.
func contract_value(item: int) -> int:
	var base: int = CLEAN_BONUS
	if item == LEDGER:
		base = LEDGER_VALUE
	elif item == CASH:
		base = CASH_VALUE
	return int(round(base * DAY_VALUE[weekday_index()] / 100.0)) * 100


func _on_round_state(data: Dictionary) -> void:
	if not active:
		return
	var new_phase: String = str(data.get("phase", ""))
	var new_round: int = int(data.get("round", 0))
	var changed: bool = new_phase != phase or new_round != round_number
	phase = new_phase
	round_number = new_round
	time_left = float(data.get("time", 0.0))
	seller = str(data.get("seller", ""))
	buyer = str(data.get("buyer", ""))
	bank = data.get("bank", {})
	results = data.get("results", [])
	day = clampi(int(data.get("day", day)), 0, WEEKDAYS.size())
	week = maxi(int(data.get("week", week)), 1)
	week_days = clampi(int(data.get("week_days", week_days)), 1, WEEKDAYS.size())
	recap = data.get("recap", [])
	drop_site = str(data.get("drop_site", ""))
	if not changed:
		return
	match phase:
		"buy":
			_enter_buy()
		"live":
			# Joined mid-round: spawn at HQ first.
			if _spawned_round != round_number:
				_enter_buy()
			_enter_live()
		"settle":
			_enter_settle()
		"week_end":
			_enter_week_end()


func _enter_buy() -> void:
	var g: Node = game
	_spawned_round = round_number
	# A new Week: money and gear start over (the first Week starts from _on_match_started).
	if _seen_week != -1 and week != _seen_week:
		g.cash = START_CASH
		g._carry_gear = false
	_seen_week = week
	g._hide_title_set()
	g.free_roam = false
	var keep: bool = g._carry_gear and not g.player.is_dead()
	g.round_number = round_number
	g.phase = g.Phase.BUY
	g.buy_time_left = time_left
	g.carrying = false
	g.violence = false
	g.paid = false
	g.purchased.clear()
	g.buy_mod_target = ""
	g._reset_world_state()
	for ride: FastCar in g.cars:
		ride.set_net_puppet(not net.is_host())
	_respawn_timer = -1.0
	_last_attacker = 0
	_apply_my_crew()
	if keep:
		g.player.revive(g.hq_spawn)
		g.player.refill()
	else:
		g.player.reset_player(g.hq_spawn)
		g.player.set_loadout(["pistol"])
		g.player.armor = 0.0
	_sidearm_only = false
	g.player.infinite_reserve = false
	g.player.regenerate = false
	g.player.invulnerable = false
	g.player.can_fire = false
	g.player.face(g.hq_yaw)
	g.player.camera.make_current()
	for guard: Node in g._all_guards():
		guard.call("set_present", false)
	g.case_mesh.visible = false
	g._reset_tip(-1.0)
	g._carry_gear = true
	g.paused = false
	g.player.enabled = true
	for ride: FastCar in g.cars:
		ride.enabled = false
	g.buy_tab = "rifle" if g._current_primary().is_empty() else "mods"
	if phase == "buy":
		# The objective board sits in the buy panel (read the board, then buy).
		g._show_buy()
	_system("%s, DAY %d OF %d  ·  WEEK %d" % [day_name(), day, week_days, week])
	for line: String in morning_paper():
		_system(line)
	g._message("%s.  %s" % [day_name(), role_line()], 8.0)


## "The morning paper": yesterday's results, a line or two, so yesterday becomes today's grudges.
func morning_paper() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if recap.is_empty():
		return lines
	lines.append("THE MORNING PAPER:")
	for line: Variant in recap:
		lines.append("  " + str(line))
	return lines


func _enter_live() -> void:
	var g: Node = game
	g.phase = g.Phase.LIVE
	g.buy_menu_open = false
	g.player.can_fire = not g.player.is_dead()
	for ride: FastCar in g.cars:
		ride.enabled = true
	g._resume()
	g._message("Doors open. %s" % role_line(), 6.0)


func _enter_settle() -> void:
	var g: Node = game
	_result_screen("END OF %s" % day_name(), "%s COMES NEXT" % WEEKDAYS[mini(weekday_index() + 1, WEEKDAYS.size() - 1)] if day < week_days else "END OF WEEK STANDINGS NEXT")
	var lines: PackedStringArray = PackedStringArray()
	for line: Variant in results:
		lines.append(str(line))
	g._text("\n".join(lines) if not lines.is_empty() else "Nobody banked anything today.")
	g._text(_standings(), 16, g.TEAL)
	g._text("Your balance: $%s. Survivors keep their gear tomorrow; the dead start with a pistol." % g._money(g.cash), 16, g.GOLD)
	g._button("LEAVE MATCH", leave_match)
	g.menu.show()


func _enter_week_end() -> void:
	var g: Node = game
	_result_screen("END OF WEEK %d" % week, "A NEW WEEK STARTS IN A FEW SECONDS. MONEY AND GEAR RESET.")
	var lines: PackedStringArray = PackedStringArray()
	for line: Variant in results:
		lines.append(str(line))
	g._text("\n".join(lines), 16, g.GOLD)
	g._button("LEAVE MATCH", leave_match)
	g.menu.show()


func _result_screen(title: String, subtitle: String) -> void:
	var g: Node = game
	if g.vehicle != null:
		g._exit_vehicle(true)
	g.phase = g.Phase.RESULT
	g._lock_controls(true)
	g._clear_menu()
	g._menu_back = Callable()
	g._heading(title, subtitle)


## Crews by banked money this Week, richest first.
func standings_order() -> Array[String]:
	var order: Array[String] = []
	for crew_id: String in Factions.ORDER:
		if bank.has(crew_id):
			order.append(crew_id)
	order.sort_custom(func(a: String, b: String) -> bool: return int(bank[a]) > int(bank[b]))
	return order


func _standings() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for crew_id: String in standings_order():
		parts.append("%s  $%s" % [Factions.get_crew(crew_id)["short"], game._money(int(bank[crew_id]))])
	return "WEEK %d BANK   " % week + "     ".join(parts) if not parts.is_empty() else ""


func my_role() -> String:
	if is_dead_drop():
		return "dead_drop"
	var mine: String = game.crew
	if mine == seller and mine == buyer:
		return "both"
	if mine == seller:
		return "seller"
	if mine == buyer:
		return "buyer"
	return "third"


func role_line() -> String:
	var seller_name: String = Factions.get_crew(seller)["name"] if not seller.is_empty() else "?"
	var buyer_name: String = Factions.get_crew(buyer)["name"] if not buyer.is_empty() else "?"
	match my_role():
		"dead_drop":
			var where: String = ("at %s" % drop_site) if not drop_site.is_empty() else "somewhere in the city; the spot is called when the doors open"
			return "FRIDAY DEAD DROP: the Ledger ($%s) and a cash case ($%s) are %s. Bank either at your HQ. No rules today." % [game._money(contract_value(LEDGER)), game._money(contract_value(CASH)), where]
		"seller":
			return "You hold THE LEDGER. %s has $%s for it. Sell it, keep it, or take their money too." % [buyer_name, game._money(contract_value(CASH))]
		"buyer":
			return "You hold the CASH. %s has the Ledger. Buy it ($%s to you when banked) or take it." % [seller_name, game._money(contract_value(LEDGER))]
		"both":
			return "Solo test: you hold both the Ledger and the cash."
	return "%s sells the Ledger to %s. Crash the deal: bank either case at your HQ." % [seller_name, buyer_name]


## The objective board text shown at the start of every buy phase.
func briefing() -> String:
	var lines: PackedStringArray = PackedStringArray(["%s, DAY %d OF %d  /  WEEK %d  /  OBJECTIVE BOARD" % [day_name(), day, week_days, week], role_line()])
	if is_dead_drop():
		lines.append("Whoever banks the Ledger gets $%s; whoever banks the cash gets $%s. No clean-deal bonus on Friday." % [game._money(contract_value(LEDGER)), game._money(contract_value(CASH))])
	else:
		lines.append("Ledger banked by the buyer: +$%s to them. Cash banked by anyone but the buyer: +$%s to that crew." % [game._money(contract_value(LEDGER)), game._money(contract_value(CASH))])
		lines.append("Clean deal (both banked, no kills between you): +$%s each. Contracts grow every Day; Friday is the Dead Drop." % game._money(contract_value(-1)))
	lines.append("Your crew phone sits at the HQ spawn: whoever holds it calls other crews (ENTER, then TAB). One case at a time; sidearm only while carrying.")
	lines.append_array(morning_paper())
	return "\n".join(lines)


func update_hud() -> void:
	var g: Node = game
	var seconds: int = maxi(0, int(ceil(time_left)))
	g.top_left.text = "%s    /    %s  ·  DAY %d OF %d" % [Factions.get_crew(g.crew)["name"], day_name(), day, week_days]
	g.top_right.text = "$%s" % g._money(g.cash)
	var phone: String = _phone_of(net.my_id())
	var slots: String = "CASE: %s    PHONE: %s" % [_item_name(_my_trade_item()).to_upper().trim_prefix("THE ") if _my_trade_item() >= 0 else "-", Factions.get_crew(phone)["short"] if not phone.is_empty() else "-"]
	if phase == "buy":
		g.top_center.text = "BUY  0:%02d" % seconds
		g.top_center.add_theme_color_override("font_color", g.GOLD)
		g.objective_label.text = "BUY PHASE  ·  " + role_line()
		g.marker_label.text = "%s  BUY MENU     ENTER  CHAT / CALL     DOORS OPEN IN %ds     %s" % [g._glyph("buy"), seconds, slots]
	else:
		g.top_center.text = "%02d:%02d" % [seconds / 60, seconds % 60]
		g.top_center.add_theme_color_override("font_color", g.RED if seconds <= 30 else g.INK)
		var mine: int = _my_trade_item()
		if mine >= 0:
			g.objective_label.text = "CARRYING %s  ·  SIDEARM ONLY  ·  BANK AT YOUR HQ (TEAL)" % _item_name(mine).to_upper()
		else:
			g.objective_label.text = role_line()
		g.marker_label.text = _item_status() + "     " + slots
	g.stats_label.text = _standings()


func _item_status() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for item: int in TRADE_ITEMS:
		if not items.has(item):
			continue
		var data: Dictionary = items[item]
		var label: String = "LEDGER" if item == LEDGER else "CASH"
		var banked: String = str(data.get("banked", ""))
		var holder: int = int(data.get("holder", 0))
		if bool(data.get("hidden", false)):
			parts.append("%s: DEAD DROP AT DOORS OPEN" % label)
		elif not banked.is_empty():
			parts.append("%s: BANKED BY %s" % [label, Factions.get_crew(banked)["short"]])
		elif holder == net.my_id():
			parts.append("%s: YOU" % label)
		elif holder != 0:
			var holder_crew: String = net.crew_of(holder)
			parts.append("%s: %s" % [label, ("YOUR CREW" if holder_crew == game.crew else Factions.get_crew(holder_crew)["short"])])
		else:
			parts.append("%s: ON THE GROUND  ·  %dm" % [label, int(_flat(game.player.global_position, data.get("pos", Vector3.ZERO)))])
	return "     ".join(parts)


## Radar/map: trade items on the ground (gold Ledger, silver cash) and crewmates. Phones never show on the map.
func draw_markers(canvas: Control, to_screen: Callable, on_radar: bool) -> void:
	if not active:
		return
	for item: int in TRADE_ITEMS:
		if not _loose(item):
			continue
		var data: Dictionary = items[item]
		var color: Color = Color("edb965") if item == LEDGER else Color("cfd6da")
		if on_radar:
			game._radar_marker(data.get("pos", Vector3.ZERO), color)
		else:
			canvas.draw_circle(to_screen.call(data.get("pos", Vector3.ZERO)), 6.0, color)
	for id: int in remotes.keys():
		if net.crew_of(id) != game.crew:
			continue
		var remote: FastRemote = remotes[id]
		var point: Vector2 = to_screen.call(remote.global_position)
		canvas.draw_circle(point, 3.5, Factions.color(game.crew))
		canvas.draw_arc(point, 4.0, 0.0, TAU, 10, Color(0, 0, 0, 0.8), 1.0)


## GPS target while online: home when carrying, else the nearest loose case.
func gps_target() -> Vector3:
	if _my_trade_item() >= 0:
		return game.HOME
	var best: Vector3 = Vector3.INF
	var best_distance: float = INF
	for item: int in TRADE_ITEMS:
		if _loose(item):
			var at: Vector3 = (items[item] as Dictionary).get("pos", Vector3.ZERO)
			var distance: float = _flat(game.player.global_position, at)
			if distance < best_distance:
				best_distance = distance
				best = at
	return best


func _on_grant(amount: int, reason: String) -> void:
	game.cash = clampi(game.cash + amount, 0, CASH_CAP)
	if amount > 0:
		game.sfx.play("cash")
	game._message("%s%s$%s  /  %s" % ["+" if amount >= 0 else "-", "", game._money(absi(amount)), reason], 5.0)


# --------------------------------------------------------------------- chat

func _ensure_chat() -> void:
	if is_instance_valid(chat_ui):
		chat_ui.visible = true
		return
	var script: GDScript = load("res://scripts/chat_ui.gd") as GDScript
	if script == null:
		return
	chat_ui = script.new()
	game.hud.add_child(chat_ui)
	var names: Dictionary = {}
	for crew_id: String in Factions.ORDER:
		names[crew_id] = Factions.get_crew(crew_id)["name"]
	chat_ui.call("setup", names, game.crew)
	chat_ui.connect("send_requested", _send_chat)
	chat_ui.connect("typing_changed", _on_typing_changed)


## Calls to another crew need a phone in hand (the host checks too, via net.call_gate).
func _send_chat(channel: String, text: String) -> void:
	if channel.begins_with("call:") and _phone_of(net.my_id()).is_empty():
		_system("No phone in hand. Your crew's phone sits at your HQ spawn; whoever holds it makes the calls.")
		return
	net.send_chat(channel, text)


func is_typing() -> bool:
	return is_instance_valid(chat_ui) and bool(chat_ui.call("is_typing"))


func open_chat() -> void:
	if is_instance_valid(chat_ui):
		chat_ui.call("open_chat")


func _on_typing_changed(typing: bool) -> void:
	# Typing frees the mouse (so the player stops taking look/move input) and lets a car coast.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if typing else Input.MOUSE_MODE_CAPTURED
	if game.vehicle != null and game.seat == 0:
		game.vehicle.enabled = not typing and game.phase == game.Phase.LIVE


func _on_chat(from_id: int, channel: String, text: String) -> void:
	if not is_instance_valid(chat_ui):
		return
	var crew_id: String = net.crew_of(from_id)
	var caller: String = net.name_of(from_id)
	# A call shows the phone it came from, not the person: a stolen phone speaks for its owners.
	if channel.begins_with("call:"):
		var phone_crew_id: String = _phone_of(from_id)
		if not phone_crew_id.is_empty():
			crew_id = phone_crew_id
			caller = "%s PHONE" % Factions.get_crew(phone_crew_id)["short"]
	chat_ui.call("add_message", caller, crew_id, channel, text, Factions.color(crew_id) if Factions.ORDER.has(crew_id) else Color.WHITE)
	if channel.begins_with("call:") and from_id != net.my_id():
		game.sfx.play("ring", 1.2, -8.0)


func _system(text: String) -> void:
	if is_instance_valid(chat_ui):
		chat_ui.call("add_message", "", "", "system", text, Color("edb965"))


# --------------------------------------------------------------------- host: the Week and the Day

func _host_tick(delta: float) -> void:
	if phase.is_empty():
		return
	time_left -= delta
	_broadcast_timer -= delta
	var ended: bool = time_left <= 0.0
	if phase == "live" and _items_all_banked():
		ended = true
	if ended:
		match phase:
			"buy":
				_host_set_phase("live", live_seconds)
				if is_dead_drop():
					_host_reveal_dead_drop()
			"live": _host_settle()
			"settle":
				if day >= week_days:
					_host_week_end()
				else:
					_host_new_round()
			"week_end": _host_new_week()
		return
	if _broadcast_timer <= 0.0:
		_host_broadcast()
	# Cars nobody drives are simulated here and followed by clients.
	_host_car_timer -= delta
	if _host_car_timer <= 0.0:
		_host_car_timer = HOST_CAR_RATE
		for index: int in range(game.cars.size()):
			var ride: FastCar = game.cars[index]
			if ride.net_puppet or (ride == game.vehicle and game.seat == 0):
				continue
			var data: Dictionary = ride.net_state()
			var xform: Transform3D = data["xform"]
			if ride.is_resting():
				var sent: Variant = _host_car_sent.get(index)
				if sent != null and (sent as Transform3D).is_equal_approx(xform):
					continue
				data["vel"] = Vector3.ZERO
				data["speed"] = 0.0
			_host_car_sent[index] = xform
			net.send_car_state(index, xform, data["vel"], data["steer"], data["speed"], data["flags"])


## Everything a peer needs to draw the Day: phase, clock, roles, the Week and the bank.
func _round_payload(phase_name: String, seconds: float) -> Dictionary:
	return {"phase": phase_name, "time": seconds, "round": round_number, "seller": seller, "buyer": buyer, "bank": bank,
		"results": results, "day": day, "week": week, "week_days": week_days, "recap": recap, "drop_site": drop_site}


func _host_broadcast() -> void:
	_broadcast_timer = 0.5
	net.broadcast_round(_round_payload(phase, time_left))


func _host_set_phase(new_phase: String, seconds: float) -> void:
	phase = new_phase
	time_left = seconds
	net.accept_hits = new_phase == "live"
	# Clear the local phase so our own broadcast triggers the transition here too.
	phase = ""
	net.broadcast_round(_round_payload(new_phase, seconds))
	_broadcast_timer = 0.5


func _active_crews() -> Array[String]:
	var crews: Array[String] = []
	for crew_id: String in Factions.ORDER:
		if not net.members_of(crew_id).is_empty():
			crews.append(crew_id)
	if crews.is_empty():
		crews.append(net.crew_of(1))
	return crews


## Morning: the next Day of the Week. Yesterday's results become the morning paper.
func _host_new_round() -> void:
	var crews: Array[String] = _active_crews()
	recap = results.duplicate()
	day += 1
	drop_site = ""
	if is_dead_drop():
		seller = ""
		buyer = ""
	else:
		seller = crews[_round_rotation % crews.size()]
		buyer = crews[(_round_rotation + 1) % crews.size()]
		_round_rotation += 1
	round_number += 1
	results = []
	_kills.clear()
	if day > 1:
		for id: int in net.players.keys():
			net.grant_to(id, ROUND_WAGE, "Day wage")
	for crew_id: String in crews:
		if not bank.has(crew_id):
			bank[crew_id] = 0
	# Every seat empties: the round resets every car to its spot.
	for car: int in range(game.cars.size()):
		for seat: int in range((game.cars[car] as FastCar).seat_count()):
			if net.seat_holder(car, seat) != 0:
				net.broadcast_seat(car, seat, 0)
	_host_set_phase("buy", buy_seconds)
	if is_dead_drop():
		# The goods appear when the doors open, somewhere neutral.
		for item: int in TRADE_ITEMS:
			net.broadcast_item(item, {"kind": "ledger" if item == LEDGER else "cash", "holder": 0, "pos": Vector3(0, -50, 0), "banked": "", "hidden": true, "msg": ""})
	else:
		_host_place(LEDGER, seller, "")
		_host_place(CASH, buyer, "")
	_host_place_phones(crews)


## After Friday: standings and a winner, then a new Week.
func _host_week_end() -> void:
	var order: Array[String] = standings_order()
	var lines: Array = []
	for index: int in range(order.size()):
		lines.append("%d.  %s   $%s" % [index + 1, Factions.get_crew(order[index])["name"], game._money(int(bank[order[index]]))])
	if order.is_empty() or int(bank[order[0]]) <= 0:
		lines.append("Nobody banked a dollar this Week.")
	elif order.size() > 1 and int(bank[order[0]]) == int(bank[order[1]]):
		lines.append("A tie at the top: nobody owns the city this Week.")
	else:
		lines.append("%s WIN WEEK %d." % [Factions.get_crew(order[0])["name"], week])
	results = lines
	_host_set_phase("week_end", week_end_seconds)


func _host_new_week() -> void:
	week += 1
	day = 0
	for crew_id: String in bank.keys():
		bank[crew_id] = 0
	_host_new_round()


## Puts an item on the doorstep of a crew's HQ.
func _host_place(item: int, crew_id: String, message: String) -> void:
	var base: Dictionary = game.world.crew_spawns.get(crew_id, {})
	var at: Vector3 = base.get("spawn", Vector3.ZERO)
	var side: Vector3 = Basis(Vector3.UP, float(base.get("spawn_yaw", 0.0))) * Vector3.RIGHT
	at += side * (1.6 if item == LEDGER else -1.6) + Vector3(0, 0.35, 0)
	at.y = maxf(at.y, 0.35)
	net.broadcast_item(item, {"kind": "ledger" if item == LEDGER else "cash", "holder": 0, "pos": at, "banked": "", "msg": message})


## Each morning every crew's phone is back where the crew spawns (whoever stole it yesterday lost it overnight).
func _host_place_phones(crews: Array[String]) -> void:
	for crew_id: String in Factions.ORDER:
		var item: int = phone_item(crew_id)
		if not crews.has(crew_id):
			if items.has(item):
				net.broadcast_item(item, {"kind": "phone", "holder": 0, "pos": Vector3(0, -50, 0), "banked": "", "hidden": true, "msg": ""})
			continue
		var base: Dictionary = game.world.crew_spawns.get(crew_id, {})
		var at: Vector3 = base.get("spawn", Vector3.ZERO)
		var side: Vector3 = Basis(Vector3.UP, float(base.get("spawn_yaw", 0.0))) * Vector3.RIGHT
		at += side * 3.2 + Vector3(0, 0.3, 0)
		at.y = maxf(at.y, 0.3)
		net.broadcast_item(item, {"kind": "phone", "holder": 0, "pos": at, "banked": "", "msg": ""})


## Friday: both goods land on a street next to a neutral landmark, and everyone hears where.
func _host_reveal_dead_drop() -> void:
	var spot: Dictionary = dead_drop_spot(game.world, week * 31 + round_number * 7)
	drop_site = str(spot["name"])
	var at: Vector3 = spot["at"]
	var along: Vector3 = spot["along"]
	for item: int in TRADE_ITEMS:
		var place: Vector3 = at + along * (1.4 if item == LEDGER else -1.4)
		place.y = at.y + 0.35
		net.broadcast_item(item, {"kind": "ledger" if item == LEDGER else "cash", "holder": 0, "pos": place, "banked": "",
			"msg": ("DEAD DROP: the goods are on the street by %s. No rules." % drop_site) if item == LEDGER else ""})
	_host_broadcast()


## A neutral landmark and the nearest road point to it, for the Dead Drop (pure: tests call it).
## Returns {name, at (on the road, near its edge on the landmark's side), along (unit vector along the road)}.
static func dead_drop_spot(world: Node, pick: int) -> Dictionary:
	var sites: Array[Dictionary] = []
	for mark: Dictionary in world.get("landmarks"):
		if bool(mark.get("neutral", false)):
			sites.append(mark)
	if sites.is_empty():
		return {"name": "the city centre", "at": Vector3(0, 0, 0), "along": Vector3.RIGHT}
	var site: Dictionary = sites[posmod(pick, sites.size())]
	var target: Vector3 = site["at"]
	var flat: Vector2 = Vector2(target.x, target.z)
	var best: Vector2 = flat
	var best_distance: float = INF
	var best_dir: Vector2 = Vector2.RIGHT
	var best_width: float = 12.0
	for road: Dictionary in world.get("roads"):
		var points: PackedVector2Array = road["points"]
		for index: int in range(points.size() - 1):
			var point: Vector2 = Geometry2D.get_closest_point_to_segment(flat, points[index], points[index + 1])
			var distance: float = point.distance_to(flat)
			if distance < best_distance:
				best_distance = distance
				best = point
				best_dir = (points[index + 1] - points[index]).normalized()
				best_width = float(road.get("width", 12.0))
	# Sit near the road edge on the landmark's side, off the centre line but still on the tarmac.
	var toward: Vector2 = (flat - best)
	if toward.length() > 0.1:
		best += toward.normalized() * maxf(best_width * 0.5 - 2.0, 0.0)
	return {"name": str(site["name"]), "at": Vector3(best.x, 0.0, best.y), "along": Vector3(best_dir.x, 0.0, best_dir.y)}


func _items_all_banked() -> bool:
	for item: int in TRADE_ITEMS:
		if not items.has(item) or str(items[item].get("banked", "")).is_empty():
			return false
	return true


func _host_pos(id: int) -> Vector3:
	return game.player.global_position if id == net.my_id() else net.latest_pos(id)


func _host_item_request(from_id: int, action: String, item: int, pos: Vector3) -> void:
	if not active or not items.has(item) or not _item_phase_ok(item):
		return
	var data: Dictionary = (items[item] as Dictionary).duplicate()
	if bool(data.get("hidden", false)):
		return
	var at: Vector3 = _host_pos(from_id)
	var who: String = net.name_of(from_id)
	var crew_id: String = net.crew_of(from_id)
	var phone: bool = is_phone(item)
	match action:
		"pickup":
			if int(data.get("holder", 0)) != 0 or not str(data.get("banked", "")).is_empty() or net.is_dead(from_id):
				return
			if at.distance_to(data.get("pos", Vector3.INF)) > (PHONE_REACH if phone else REACH) + 1.2:
				return
			# One trade item and one phone per person; a second is refused ("hands full").
			if phone and not _phone_of(from_id).is_empty():
				return
			if not phone and _trade_item_of(from_id) >= 0:
				return
			data["holder"] = from_id
			var own_phone: bool = phone and phone_crew(item) == crew_id
			# Grabbing your own crew's phone is routine; everything else is news.
			data["msg"] = "" if own_phone else "%s (%s) picked up %s." % [who, Factions.get_crew(crew_id)["short"], _item_name(item)]
		"drop":
			if int(data.get("holder", 0)) != from_id:
				return
			data["holder"] = 0
			data["pos"] = (pos if pos.distance_to(at) < 3.0 else at) * Vector3(1, 0, 1) + Vector3(0, maxf(at.y, 0.0) + (0.3 if phone else 0.35), 0)
			data["msg"] = "" if phone else "%s dropped %s." % [who, _item_name(item)]
		"bank":
			if phone or phase != "live" or int(data.get("holder", 0)) != from_id:
				return
			var home: Vector3 = (game.world.crew_spawns.get(crew_id, {}) as Dictionary).get("hq", Vector3.INF)
			if _flat(at, home) > BANK_REACH + 1.5:
				return
			data["holder"] = 0
			data["banked"] = crew_id
			data["msg"] = "%s banked %s at the %s HQ." % [who, _item_name(item), Factions.get_crew(crew_id)["short"]]
			_host_payout(item, crew_id)
		_:
			return
	net.broadcast_item(item, data)


func _host_payout(item: int, crew_id: String) -> void:
	var amount: int = 0
	var line: String = ""
	var crew_name: String = Factions.get_crew(crew_id)["name"]
	var value: int = contract_value(item)
	if is_dead_drop():
		amount = value
		line = "%s banked %s from the Dead Drop: +$%s." % [crew_name, _item_name(item), game._money(amount)]
	elif item == LEDGER:
		if crew_id == buyer:
			amount = value
			line = "%s delivered the Ledger to their client: +$%s." % [crew_name, game._money(amount)]
		elif crew_id == seller:
			line = "%s kept the Ledger. No sale." % crew_name
		else:
			amount = value
			line = "%s stole the Ledger and sold it on: +$%s." % [crew_name, game._money(amount)]
	else:
		if crew_id == buyer:
			line = "%s kept their cash." % crew_name
		else:
			amount = value
			line = "%s banked the buyer's cash: +$%s." % [crew_name, game._money(amount)]
	results.append(line)
	if amount > 0:
		bank[crew_id] = int(bank.get(crew_id, 0)) + amount
		for id: int in net.members_of(crew_id):
			net.grant_to(id, amount, "Banked %s" % _item_name(item))


func _host_settle() -> void:
	var ledger_by: String = str(items.get(LEDGER, {}).get("banked", ""))
	var cash_by: String = str(items.get(CASH, {}).get("banked", ""))
	var clean: bool = not is_dead_drop() and seller != buyer and ledger_by == buyer and cash_by == seller and not _kills.has("%s>%s" % [seller, buyer]) and not _kills.has("%s>%s" % [buyer, seller])
	if clean:
		var bonus: int = contract_value(-1)
		results.append("CLEAN DEAL: nobody got hurt. +$%s to both crews." % game._money(bonus))
		for crew_id: String in [seller, buyer]:
			bank[crew_id] = int(bank.get(crew_id, 0)) + bonus
			for id: int in net.members_of(crew_id):
				net.grant_to(id, bonus, "Clean deal")
	if results.is_empty():
		results.append("Time ran out. Nobody banked anything.")
	_host_set_phase("settle", settle_seconds)


func _host_drop_all(id: int, pos: Vector3) -> void:
	for item: int in items.keys():
		var data: Dictionary = (items[item] as Dictionary).duplicate()
		if int(data.get("holder", 0)) == id:
			data["holder"] = 0
			data["pos"] = Vector3(pos.x, maxf(pos.y, 0.0) + 0.35, pos.z)
			data["msg"] = "%s dropped %s." % [net.name_of(id), _item_name(item)]
			net.broadcast_item(item, data)


func _host_seat_request(from_id: int, car: int, seat: int) -> void:
	if not active or car < 0 or car >= game.cars.size():
		return
	var ride: FastCar = game.cars[car]
	if seat >= ride.seat_count() or net.seat_holder(car, seat) != 0 or net.is_dead(from_id):
		return
	if from_id != net.my_id() and seat < ride.occupants.size() and ride.occupants[seat] == "player":
		return
	if _host_pos(from_id).distance_to(ride.global_position) > 7.0:
		return
	for other_car: int in range(game.cars.size()):
		for other_seat: int in range((game.cars[other_car] as FastCar).seat_count()):
			if net.seat_holder(other_car, other_seat) == from_id:
				net.broadcast_seat(other_car, other_seat, 0)
	net.broadcast_seat(car, seat, from_id)


func _host_seat_leave(from_id: int, car: int, seat: int) -> void:
	if net.seat_holder(car, seat) == from_id:
		net.broadcast_seat(car, seat, 0)


func _host_car_damage(from_id: int, car: int, amount: float) -> void:
	if not active or car < 0 or car >= game.cars.size():
		return
	var ride: FastCar = game.cars[car]
	# Only someone near the car (crashing it, or shooting it within weapon range) can damage it.
	if from_id != net.my_id() and net.has_latest(from_id) and _host_pos(from_id).distance_to(ride.global_position) > FastNet.MAX_HIT_RANGE:
		return
	ride.apply_damage(amount)
	net.broadcast_car_health(car, ride.health, ride.disabled)
