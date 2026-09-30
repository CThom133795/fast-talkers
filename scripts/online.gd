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

var game: Node
var net: FastNet
var active: bool = false
## Round state as last broadcast by the host.
var phase: String = ""
var time_left: float = 0.0
var round_number: int = 0
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


func setup(owner_game: Node, owner_net: FastNet) -> void:
	game = owner_game
	net = owner_net
	_remote_root = Node3D.new()
	_remote_root.name = "Remotes"
	game.add_child(_remote_root)
	net.max_cars = game.cars.size()
	net.max_items = 2
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
	net.host_seat_request.connect(_host_seat_request)
	net.host_seat_leave.connect(_host_seat_leave)
	net.host_car_damage.connect(_host_car_damage)
	net.host_item_request.connect(_host_item_request)
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
	if active:
		_spawn_remote(id)


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
	_update_item_visuals()


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
	if quiet:
		game.sfx.play_at("suppressed", origin)
		game.effects.call("tracer", origin, end, Color(0.55, 0.52, 0.48), 0.008, 0.03)
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


# --------------------------------------------------------------------- items (client side)

func _build_items() -> void:
	for item: int in [LEDGER, CASH]:
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
		var tag: Label3D = Label3D.new()
		tag.name = "Tag"
		tag.text = "THE LEDGER" if item == LEDGER else "CASH  $%s" % game._money(CASH_VALUE)
		tag.font_size = 34
		tag.position.y = 0.9
		tag.modulate = Color("edb965") if item == LEDGER else Color("cfd6da")
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.visibility_range_end = 30.0
		tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(tag)
		node.visible = false
		_item_nodes[item] = node


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
	if int(data.get("holder", 0)) == me and int(before.get("holder", 0)) != me:
		game.sfx.play("draw", 0.8)
		game._message("You have %s. Bank it at your HQ (teal), trade it, or hide it. %s drops it." % [_item_name(item), game._glyph("drop")], 6.0)


func _update_item_visuals() -> void:
	for item: int in _item_nodes.keys():
		var node: Node3D = _item_nodes[item]
		var data: Dictionary = items.get(item, {})
		var on_ground: bool = not data.is_empty() and int(data.get("holder", 0)) == 0 and str(data.get("banked", "")).is_empty()
		node.visible = on_ground
		if on_ground:
			node.global_position = data.get("pos", Vector3.ZERO)
			node.rotation.y += get_process_delta_time() * 0.6


func _item_name(item: int) -> String:
	return "the Ledger" if item == LEDGER else "the cash case"


## E on foot: pick up, or bank at HQ. True if it handled the key.
func interact() -> bool:
	if not active or phase != "live" or game.player.is_dead():
		return false
	var at: Vector3 = game.player.global_position
	for item: int in items.keys():
		var data: Dictionary = items[item]
		if int(data.get("holder", 0)) == net.my_id() and _flat(at, game.HOME) < BANK_REACH:
			net.send_item_request("bank", item, at)
			return true
	for item: int in items.keys():
		var data: Dictionary = items[item]
		if int(data.get("holder", 0)) == 0 and str(data.get("banked", "")).is_empty() and at.distance_to(data.get("pos", Vector3.INF)) < REACH:
			net.send_item_request("pickup", item, at)
			return true
	return false


## G: drop everything carried, at your feet.
func drop() -> bool:
	if not active:
		return false
	var dropped: bool = false
	for item: int in items.keys():
		if int(items[item].get("holder", 0)) == net.my_id():
			net.send_item_request("drop", item, game.player.global_position - game.player.global_basis.z * 1.0)
			dropped = true
	return dropped


func prompt_text() -> String:
	if not active or phase != "live" or game.player.is_dead():
		return ""
	var at: Vector3 = game.player.global_position
	for item: int in items.keys():
		if int(items[item].get("holder", 0)) == net.my_id() and _flat(at, game.HOME) < BANK_REACH:
			return "[%s]  BANK %s AT YOUR HQ" % [game._glyph("interact"), _item_name(item).to_upper()]
	for item: int in items.keys():
		var data: Dictionary = items[item]
		if int(data.get("holder", 0)) == 0 and str(data.get("banked", "")).is_empty() and at.distance_to(data.get("pos", Vector3.INF)) < REACH:
			return "[%s]  PICK UP %s" % [game._glyph("interact"), _item_name(item).to_upper()]
	return ""


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


# --------------------------------------------------------------------- round (client side)

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
	if not changed:
		return
	match phase:
		"buy": _enter_buy()
		"live": _enter_live()
		"settle": _enter_settle()


func _enter_buy() -> void:
	var g: Node = game
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
	g._show_buy()
	g._message(briefing(), 14.0)


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
	if g.vehicle != null:
		g._exit_vehicle(true)
	g.phase = g.Phase.RESULT
	g._lock_controls(true)
	g._clear_menu()
	g._menu_back = Callable()
	g._heading("ROUND %02d SETTLED" % round_number, "NEXT ROUND IN A FEW SECONDS")
	var lines: PackedStringArray = PackedStringArray()
	for line: Variant in results:
		lines.append(str(line))
	g._text("\n".join(lines) if not lines.is_empty() else "Nobody banked anything this round.")
	g._text(_standings(), 16, g.TEAL)
	g._text("Your balance: $%s. Survivors keep their gear." % g._money(g.cash), 16, g.GOLD)
	g._button("LEAVE MATCH", leave_match)
	g.menu.show()


func _standings() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for crew_id: String in Factions.ORDER:
		if bank.has(crew_id):
			parts.append("%s  $%s" % [Factions.get_crew(crew_id)["short"], game._money(int(bank[crew_id]))])
	return "MATCH EARNINGS   " + "     ".join(parts) if not parts.is_empty() else ""


func my_role() -> String:
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
		"seller":
			return "You hold THE LEDGER. %s has $%s for it. Sell it, keep it, or take their money too." % [buyer_name, game._money(CASH_VALUE)]
		"buyer":
			return "You hold the CASH. %s has the Ledger. Buy it ($%s to you when banked) or take it." % [seller_name, game._money(LEDGER_VALUE)]
		"both":
			return "Solo test: you hold both the Ledger and the cash."
	return "%s sells the Ledger to %s. Crash the deal: bank either case at your HQ." % [seller_name, buyer_name]


## The objective board text shown at the start of every buy phase.
func briefing() -> String:
	var lines: PackedStringArray = PackedStringArray(["ROUND %02d  /  OBJECTIVE BOARD" % round_number, role_line()])
	lines.append("Ledger banked by the buyer: +$%s to them. Cash banked by anyone but the buyer: +$%s to that crew." % [game._money(LEDGER_VALUE), game._money(CASH_VALUE)])
	lines.append("Clean deal (both banked, no kills between you): +$%s each. Phones: %s chat, TAB to call another crew." % [game._money(CLEAN_BONUS), "ENTER"])
	return "\n".join(lines)


func update_hud() -> void:
	var g: Node = game
	var seconds: int = maxi(0, int(ceil(time_left)))
	g.top_left.text = "%s    /    ONLINE ROUND %02d" % [Factions.get_crew(g.crew)["name"], round_number]
	g.top_right.text = "$%s" % g._money(g.cash)
	if phase == "buy":
		g.top_center.text = "BUY  0:%02d" % seconds
		g.top_center.add_theme_color_override("font_color", g.GOLD)
		g.objective_label.text = "BUY PHASE  ·  " + role_line()
		g.marker_label.text = "%s  BUY MENU     ENTER  CHAT / CALL     DOORS OPEN IN %ds" % [g._glyph("buy"), seconds]
	else:
		g.top_center.text = "%02d:%02d" % [seconds / 60, seconds % 60]
		g.top_center.add_theme_color_override("font_color", g.RED if seconds <= 30 else g.INK)
		var carrying: PackedStringArray = PackedStringArray()
		for item: int in items.keys():
			if int(items[item].get("holder", 0)) == net.my_id():
				carrying.append(_item_name(item).to_upper())
		if not carrying.is_empty():
			g.objective_label.text = "CARRYING %s  ·  BANK AT YOUR HQ (TEAL)" % " + ".join(carrying)
		else:
			g.objective_label.text = role_line()
		g.marker_label.text = _item_status()
	g.stats_label.text = _standings()


func _item_status() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for item: int in [LEDGER, CASH]:
		if not items.has(item):
			continue
		var data: Dictionary = items[item]
		var label: String = "LEDGER" if item == LEDGER else "CASH"
		var banked: String = str(data.get("banked", ""))
		var holder: int = int(data.get("holder", 0))
		if not banked.is_empty():
			parts.append("%s: BANKED BY %s" % [label, Factions.get_crew(banked)["short"]])
		elif holder == net.my_id():
			parts.append("%s: YOU" % label)
		elif holder != 0:
			var holder_crew: String = net.crew_of(holder)
			parts.append("%s: %s" % [label, ("YOUR CREW" if holder_crew == game.crew else Factions.get_crew(holder_crew)["short"])])
		else:
			parts.append("%s: ON THE GROUND  ·  %dm" % [label, int(_flat(game.player.global_position, data.get("pos", Vector3.ZERO)))])
	return "     ".join(parts)


## Radar/map: items on the ground (gold Ledger, silver cash) and crewmates.
func draw_markers(canvas: Control, to_screen: Callable, on_radar: bool) -> void:
	if not active:
		return
	for item: int in items.keys():
		var data: Dictionary = items[item]
		if int(data.get("holder", 0)) != 0 or not str(data.get("banked", "")).is_empty():
			continue
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
	for item: int in items.keys():
		if int(items[item].get("holder", 0)) == net.my_id():
			return game.HOME
	var best: Vector3 = Vector3.INF
	var best_distance: float = INF
	for item: int in items.keys():
		var data: Dictionary = items[item]
		if int(data.get("holder", 0)) == 0 and str(data.get("banked", "")).is_empty():
			var distance: float = _flat(game.player.global_position, data.get("pos", Vector3.ZERO))
			if distance < best_distance:
				best_distance = distance
				best = data.get("pos", Vector3.ZERO)
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
	chat_ui.connect("send_requested", func(channel: String, text: String) -> void: net.send_chat(channel, text))
	chat_ui.connect("typing_changed", _on_typing_changed)


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
	chat_ui.call("add_message", net.name_of(from_id), crew_id, channel, text, Factions.color(crew_id) if Factions.ORDER.has(crew_id) else Color.WHITE)
	if channel.begins_with("call:") and from_id != net.my_id():
		game.sfx.play("ring", 1.2, -8.0)


func _system(text: String) -> void:
	if is_instance_valid(chat_ui):
		chat_ui.call("add_message", "", "", "system", text, Color("edb965"))


# --------------------------------------------------------------------- host: round rules

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
			"buy": _host_set_phase("live", LIVE_SECONDS)
			"live": _host_settle()
			"settle": _host_new_round()
		return
	if _broadcast_timer <= 0.0:
		_host_broadcast()
	# Cars nobody drives are simulated here and followed by clients.
	_host_car_timer -= delta
	if _host_car_timer <= 0.0:
		_host_car_timer = HOST_CAR_RATE
		for index: int in range(game.cars.size()):
			var ride: FastCar = game.cars[index]
			if ride.net_puppet or ride.is_resting() or (ride == game.vehicle and game.seat == 0):
				continue
			var data: Dictionary = ride.net_state()
			net.send_car_state(index, data["xform"], data["vel"], data["steer"], data["speed"], data["flags"])


func _host_broadcast() -> void:
	_broadcast_timer = 0.5
	net.broadcast_round({"phase": phase, "time": time_left, "round": round_number, "seller": seller, "buyer": buyer, "bank": bank, "results": results})


func _host_set_phase(new_phase: String, seconds: float) -> void:
	phase = new_phase
	time_left = seconds
	net.accept_hits = new_phase == "live"
	# Clear the local phase so our own broadcast triggers the transition here too.
	var announce: String = phase
	phase = ""
	var round_before: int = round_number
	round_number = round_before
	net.broadcast_round({"phase": announce, "time": seconds, "round": round_number, "seller": seller, "buyer": buyer, "bank": bank, "results": results})
	_broadcast_timer = 0.5


func _host_new_round() -> void:
	var crews: Array[String] = []
	for crew_id: String in Factions.ORDER:
		if not net.members_of(crew_id).is_empty():
			crews.append(crew_id)
	if crews.is_empty():
		crews.append(net.crew_of(1))
	seller = crews[_round_rotation % crews.size()]
	buyer = crews[(_round_rotation + 1) % crews.size()]
	_round_rotation += 1
	round_number += 1
	results = []
	_kills.clear()
	if round_number > 1:
		for id: int in net.players.keys():
			net.grant_to(id, ROUND_WAGE, "Round wage")
	for crew_id: String in crews:
		if not bank.has(crew_id):
			bank[crew_id] = 0
	# Every seat empties: the round resets every car to its spot.
	for car: int in range(game.cars.size()):
		for seat: int in range((game.cars[car] as FastCar).seat_count()):
			if net.seat_holder(car, seat) != 0:
				net.broadcast_seat(car, seat, 0)
	_host_set_phase("buy", BUY_SECONDS)
	_host_place(LEDGER, seller, "")
	_host_place(CASH, buyer, "")


## Puts an item on the doorstep of a crew's HQ.
func _host_place(item: int, crew_id: String, message: String) -> void:
	var base: Dictionary = game.world.crew_spawns.get(crew_id, {})
	var at: Vector3 = base.get("spawn", Vector3.ZERO)
	var side: Vector3 = Basis(Vector3.UP, float(base.get("spawn_yaw", 0.0))) * Vector3.RIGHT
	at += side * (1.6 if item == LEDGER else -1.6) + Vector3(0, 0.35, 0)
	at.y = maxf(at.y, 0.35)
	net.broadcast_item(item, {"kind": "ledger" if item == LEDGER else "cash", "holder": 0, "pos": at, "banked": "", "msg": message})


func _items_all_banked() -> bool:
	for item: int in [LEDGER, CASH]:
		if not items.has(item) or str(items[item].get("banked", "")).is_empty():
			return false
	return true


func _host_pos(id: int) -> Vector3:
	return game.player.global_position if id == net.my_id() else net.latest_pos(id)


func _host_item_request(from_id: int, action: String, item: int, pos: Vector3) -> void:
	if not active or phase != "live" or not items.has(item):
		return
	var data: Dictionary = (items[item] as Dictionary).duplicate()
	var at: Vector3 = _host_pos(from_id)
	var who: String = net.name_of(from_id)
	var crew_id: String = net.crew_of(from_id)
	match action:
		"pickup":
			if int(data.get("holder", 0)) != 0 or not str(data.get("banked", "")).is_empty() or net.is_dead(from_id):
				return
			if at.distance_to(data.get("pos", Vector3.INF)) > REACH + 1.2:
				return
			data["holder"] = from_id
			data["msg"] = "%s (%s) picked up %s." % [who, Factions.get_crew(crew_id)["short"], _item_name(item)]
		"drop":
			if int(data.get("holder", 0)) != from_id:
				return
			data["holder"] = 0
			data["pos"] = (pos if pos.distance_to(at) < 3.0 else at) * Vector3(1, 0, 1) + Vector3(0, maxf(at.y, 0.0) + 0.35, 0)
			data["msg"] = "%s dropped %s." % [who, _item_name(item)]
		"bank":
			if int(data.get("holder", 0)) != from_id:
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
	if item == LEDGER:
		if crew_id == buyer:
			amount = LEDGER_VALUE
			line = "%s delivered the Ledger to their client: +$%s." % [crew_name, game._money(amount)]
		elif crew_id == seller:
			line = "%s kept the Ledger. No sale." % crew_name
		else:
			amount = LEDGER_VALUE
			line = "%s stole the Ledger and sold it on: +$%s." % [crew_name, game._money(amount)]
	else:
		if crew_id == buyer:
			line = "%s kept their cash." % crew_name
		else:
			amount = CASH_VALUE
			line = "%s banked the buyer's cash: +$%s." % [crew_name, game._money(amount)]
	results.append(line)
	if amount > 0:
		bank[crew_id] = int(bank.get(crew_id, 0)) + amount
		for id: int in net.members_of(crew_id):
			net.grant_to(id, amount, "Banked %s" % _item_name(item))


func _host_settle() -> void:
	var ledger_by: String = str(items.get(LEDGER, {}).get("banked", ""))
	var cash_by: String = str(items.get(CASH, {}).get("banked", ""))
	var clean: bool = seller != buyer and ledger_by == buyer and cash_by == seller and not _kills.has("%s>%s" % [seller, buyer]) and not _kills.has("%s>%s" % [buyer, seller])
	if clean:
		results.append("CLEAN DEAL: nobody got hurt. +$%s to both crews." % game._money(CLEAN_BONUS))
		for crew_id: String in [seller, buyer]:
			bank[crew_id] = int(bank.get(crew_id, 0)) + CLEAN_BONUS
			for id: int in net.members_of(crew_id):
				net.grant_to(id, CLEAN_BONUS, "Clean deal")
	if results.is_empty():
		results.append("Time ran out. Nobody banked anything.")
	_host_set_phase("settle", SETTLE_SECONDS)


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


func _host_car_damage(_from_id: int, car: int, amount: float) -> void:
	if car < 0 or car >= game.cars.size():
		return
	var ride: FastCar = game.cars[car]
	ride.apply_damage(amount)
	net.broadcast_car_health(car, ride.health, ride.disabled)
