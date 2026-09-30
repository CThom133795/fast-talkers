class_name FastNet
extends Node
## Networking layer (docs/NET_M1_SPEC.md §3). Listen-server ENet multiplayer: the host is peer 1 and
## plays too. Every RPC lives on this node ("/root/FastTalkers/Net"), so node paths match on all peers.
##
## Game rules do NOT live here. The `_host_*` handlers only check that the request is well formed, that the
## sender is who it claims to be and that it is not flooding; then they emit a `host_*` signal that
## main.gd answers (except hit claims, which are validated here from the latest known positions).
## Clients never call a `_host_*` handler directly: use the `send_*` wrappers, which call the handler
## locally with sender id 1 when we are the host.
##
## Security notes (docs/NETWORK_SECURITY_AND_STEAM.md): `allow_object_decoding` is forced off (no object or
## script injection over the wire), server relay is OFF (clients only ever talk to the host; the host
## validates and re-broadcasts snapshots, so a client cannot bypass host checks by sending straight to other
## clients), every RPC has typed parameters, and every incoming value is sanitised (finite numbers, clamped
## ids, printable clamped strings, known weapons and crews) before it reaches game code. Peers must pass a
## version handshake within HELLO_TIMEOUT_MS or they are dropped; nothing but the hello is accepted before it.
## Every client RPC also spends from a per-peer token bucket, and malformed / spoofed / impossible input
## earns strikes; STRIKE_LIMIT strikes (decaying) means a kick.
##
## Transport: ENet by default. `host_steam()` / `join_steam()` use the optional GodotSteam layer
## (scripts/steam_transport.gd) and hand its SteamMultiplayerPeer to the same `_attach_peer`, so every
## check below applies unchanged. Without the extension those calls return ERR_UNAVAILABLE.

const Factions = preload("res://scripts/factions.gd")
const Sec = preload("res://scripts/net_security.gd")
const VoiceRelayS = preload("res://scripts/voice_relay.gd")
const VoiceCodecS = preload("res://scripts/voice_codec.gd")
## Loaded on demand (never preloaded), so net.gd works even if this file or the extension is missing.
const STEAM_TRANSPORT_PATH: String = "res://scripts/steam_transport.gd"

const PORT: int = 24650
const MAX_PLAYERS: int = 8
const NAME_MAX: int = 24
const CHAT_MAX: int = 160
const REASON_MAX: int = 48
## Positions further from the origin than this are rejected as garbage.
const MAX_COORD: float = 100000.0
const MAX_SEAT: int = 16
## Hit claim validation (spec §2).
const MAX_HIT_RANGE: float = 320.0
const HIT_POINT_SLACK: float = 3.0
const MAX_HIT_DAMAGE: float = 250.0
## Host-side per-peer rate limits (messages per second).
const LIMIT_STATE: int = 40
const LIMIT_CAR: int = 40
const LIMIT_CHAT: int = 3
## Voice frames per second a peer may send (a talker sends 25/s of 40 ms frames); 5x this for two windows is a kick.
const LIMIT_VOICE: int = 40
const LIMIT_REQUEST: int = 10
const LIMIT_HIT: int = 25
const LIMIT_HELLO: int = 3
const ITEM_ACTIONS: PackedStringArray = ["pickup", "drop", "bank"]
## A connected peer must send a valid hello (name + build tag) within this time.
const HELLO_TIMEOUT_MS: int = 10000
## Global per-peer message budget (all client RPCs share it): burst and refill per second.
const BUDGET_BURST: float = 240.0
const BUDGET_RATE: float = 150.0
## Strikes before a kick; one strike decays every STRIKE_DECAY_MS.
const STRIKE_LIMIT: int = 10
const STRIKE_DECAY_MS: int = 5000
## Consecutive rejected (impossible) movement snapshots before the host resyncs to the new position.
const TELEPORT_RESYNC: int = 10
## After a phase change, death or match start, snapshots may jump (respawn at HQ) for this long.
const TELEPORT_GRACE_MS: int = 4000
## Shooter's claimed origin may be this far from their last snapshot (latency, cars, muzzle offset).
const HIT_ORIGIN_SLACK: float = 30.0

enum Mode { OFFLINE, HOST, CLIENT }

## Lobby / connection
signal lobby_changed()
signal connected()
signal connection_failed(reason: String)
## Emitted on every peer for every other peer that joins (clients also get one per existing player
## when they first receive the lobby, so main can spawn remotes from it).
signal peer_joined(id: int)
signal peer_left(id: int)
signal server_closed()
signal match_started()
signal match_ended()
signal upnp_done(status: String)
## A Steam invite / "Join Game" was accepted and a Steam join started (UI: show the lobby screen).
signal steam_join_started()

## Game messages (all peers)
signal remote_state(id: int, state: Dictionary)
signal remote_shot(id: int, origin: Vector3, end: Vector3, weapon: String, quiet: bool)
signal damage_received(amount: float, source: Vector3, attacker: int)
signal player_died(id: int, killer: int, pos: Vector3)
signal seat_update(car: int, seat: int, peer: int)
signal remote_car(car: int, data: Dictionary)
signal car_health(car: int, health: float, disabled: bool)
signal remote_glass(car: int, index: int)
signal item_update(item: int, data: Dictionary)
signal round_state(data: Dictionary)
signal grant(amount: int, reason: String)
signal chat(from_id: int, channel: String, text: String)
## A voice frame for the local player to play: from_id, mode (VoiceRelayS.Mode), ADPCM frame, metres from the talker.
signal voice_frame(from_id: int, mode: int, frame: PackedByteArray, distance: float, muffled: bool)
## Shared world state changed by a player: kind "door" (value 1 open / 0 shut) or "lift"
## (value = target floor). Cosmetic-plus-cover state; every peer applies it.
signal world_event(kind: String, index: int, value: int)

## Host-only requests that main.gd decides (no game rules in this file)
signal host_seat_request(from_id: int, car: int, seat: int)
signal host_seat_leave(from_id: int, car: int, seat: int)
signal host_car_damage(from_id: int, car: int, amount: float)
signal host_item_request(from_id: int, action: String, item: int, pos: Vector3)
## A hit claim passed validation and damage was sent to the victim.
signal hit_validated(shooter: int, victim: int, amount: float, head: bool, weapon: String)

## peer_id -> {"name": String, "crew": String, "ready": bool, "in_match": bool}. Host-authoritative.
var players: Dictionary = {}
var local_name: String = "Player"
var upnp_status: String = ""
var in_match: bool = false
## Tests set this false to skip the router probe.
var use_upnp: bool = true
## The lead sets these to the real counts; ids outside are rejected.
var max_cars: int = 128
var max_items: int = 64
## The lead flips this off outside the street phase so hit claims are ignored.
var accept_hits: bool = true
## Optional `seat_owner(car: int) -> int` (0 = nobody). Only the driver may send `_car_state`
## (the host may when there is no driver). Unset = allow anyone.
var seat_owner: Callable = Callable()
## Optional `los_check(from: Vector3, to: Vector3) -> bool` (host): a hit claim whose ray is blocked by
## world geometry is dropped. Unset = no line-of-sight test (range, position and weapon checks still run).
var los_check: Callable = Callable()
## Optional `call_gate(sender: int) -> bool` (host): may this peer phone another crew ("call:<crew>")?
## online.gd sets it so only whoever holds a crew phone can call (docs/LEAD_DESIGN_DECISIONS.md §2).
var call_gate: Callable = Callable()
## Host lobby setting: Days in a Week (5 = Monday..Friday, 3 = a quick Wednesday..Friday). online.gd reads it
## when the match starts and sends it to everyone in the round state.
var week_days: int = 5
## Last reason a peer was kicked for flooding (for tests / logs).
var last_kick: String = ""
## Handshake tag; peers with a different one are refused. Defaults to "<protocol>|<config/version>".
## The lead can append a world hash / seed so builds that generate a different world cannot join.
var build_tag: String = Sec.build_tag()
## Playable half-extent (metres) for snapshot positions; the lead can narrow it to the real map.
var map_half_extent: float = Sec.MAP_HALF_EXTENT
## "enet" (default) or "steam": which transport the current session uses.
var transport: String = "enet"
## Why the last Steam call could not run ("" when fine). Readable by UI.
var steam_status: String = ""

var _mode: int = Mode.OFFLINE
var _connected: bool = false
var _port: int = PORT
var _address: String = ""
var _latest: Dictionary = {}
## Test hook: when valid, the host calls it (target, sender, mode, distance, frame) instead of sending the relay RPC.
var voice_tap: Callable = Callable()
## Host-side world knowledge for proximity occlusion (set by main.gd): `voice_space(pos: Vector3) -> int`
## (-1 outdoors, else an id of the walk-in building around that point) and `voice_doors() -> Array` of
## the world positions of currently open doorways.
var voice_space: Callable = Callable()
var voice_doors: Callable = Callable()
var voice_range: float = 35.0
## Host: peer id -> tick (ms) until which that peer is "on the radio": their proximity frames are dropped.
var _voice_radio_until: Dictionary = {}
const VOICE_RADIO_HOLD_MS: int = 300
var _dead_until: Dictionary = {}
var _death_ms: Dictionary = {}
var _claim_ok: Dictionary = {}
var _hello_done: Dictionary = {}
var _rl: Dictionary = {}
var _seats: Dictionary = {}
var _threads: Array[Thread] = []
var _upnp_gen: int = 0
var _upnp_obj: UPNP = null
var _upnp_port: int = 0
var _hello_deadline: Dictionary = {}
var _hello_rejected: Dictionary = {}
var _budget: Dictionary = {}
var _strikes: Sec.Strikes = Sec.Strikes.new(STRIKE_LIMIT, STRIKE_DECAY_MS)
var _state_ms: Dictionary = {}
var _tp_rejects: Dictionary = {}
var _teleport_until: Dictionary = {}
var _teleport_all_until: int = 0
var _last_phase: String = ""
var _steam: Node = null
## victim -> [shooter, ms] of the last validated hit (death attribution check).
var _last_hitter: Dictionary = {}


func _ready() -> void:
	set_process(false)
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(_delta: float) -> void:
	_reap_threads()
	if _mode == Mode.HOST:
		_check_hello_timeouts()


func _exit_tree() -> void:
	leave()
	for thread: Thread in _threads:
		thread.wait_to_finish()
	_threads.clear()


# ---------------------------------------------------------------- connection

## Start listening. Returns OK or the ENet error (for example ERR_CANT_CREATE when the port is taken).
## Host a match. `bind_ip` "127.0.0.1" keeps it on this PC (the solo Week test: no firewall prompt, no UPnP).
func host(port: int = PORT, bind_ip: String = "*") -> Error:
	if not is_inside_tree():
		return ERR_UNCONFIGURED
	leave()
	var peer := ENetMultiplayerPeer.new()
	if bind_ip != "*":
		peer.set_bind_ip(bind_ip)
	var err: Error = peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	_attach_peer(peer)
	transport = "enet"
	_mode = Mode.HOST
	_connected = true
	_port = port
	_address = ""
	players = {1: _new_entry(clean_name(local_name))}
	_hello_done[1] = true
	if bind_ip == "*":
		_start_upnp(port)
	set_process(true)
	lobby_changed.emit()
	return OK


## Join a host. `address` may carry a port ("1.2.3.4:24650").
func join(address: String, port: int = PORT) -> Error:
	if not is_inside_tree():
		return ERR_UNCONFIGURED
	var host_name: String = address.strip_edges()
	var use_port: int = port
	if host_name.count(":") == 1:
		var parts: PackedStringArray = host_name.split(":")
		host_name = parts[0].strip_edges()
		if not parts[1].strip_edges().is_valid_int():
			return ERR_INVALID_PARAMETER
		use_port = parts[1].strip_edges().to_int()
	if host_name.is_empty() or use_port < 1 or use_port > 65535:
		return ERR_INVALID_PARAMETER
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(host_name, use_port)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	_attach_peer(peer)
	transport = "enet"
	_mode = Mode.CLIENT
	_connected = false
	_port = use_port
	_address = host_name
	lobby_changed.emit()
	return OK


## Close everything. Safe to call at any time, on any state.
func leave() -> void:
	var was_active: bool = _mode != Mode.OFFLINE or not players.is_empty()
	_mode = Mode.OFFLINE
	_connected = false
	_release_upnp()
	if _steam != null and transport == "steam":
		_steam.call("close")
	transport = "enet"
	if is_inside_tree():
		var peer: MultiplayerPeer = multiplayer.multiplayer_peer
		if peer != null and not (peer is OfflineMultiplayerPeer):
			peer.close()
		multiplayer.multiplayer_peer = null
	_reset_state()
	if was_active:
		lobby_changed.emit()


# ---------------------------------------------------------------- Steam (optional, UNVALIDATED)

## The Steam transport helper (created on first use; harmless without the extension).
func steam() -> Node:
	if _steam == null:
		var script: GDScript = load(STEAM_TRANSPORT_PATH) as GDScript if ResourceLoader.exists(STEAM_TRANSPORT_PATH) else null
		if script == null:
			return null
		_steam = script.new()
		_steam.name = "Steam"
		add_child(_steam)
		_steam.connect("peer_ready", _on_steam_peer_ready)
		_steam.connect("failed", _on_steam_failed)
		_steam.connect("invite_accepted", _on_steam_invite)
	_steam.set("build_tag", build_tag)
	_steam.set("max_members", MAX_PLAYERS)
	return _steam


## "" when Steam play is possible, else one plain sentence fragment for the UI
## ("Steam add-on not installed", "Steam not running", ...). Never touches Steam without the extension.
func steam_unavailable_reason() -> String:
	if not steam_extension_present():
		return "Steam add-on not installed"
	var helper: Node = steam()
	if helper == null:
		return "Steam support missing from this build"
	return String(helper.call("unavailable_reason"))


## GodotSteam singleton and its multiplayer peer class both registered.
static func steam_extension_present() -> bool:
	return Engine.has_singleton("Steam") and ClassDB.class_exists("SteamMultiplayerPeer")


func steam_available() -> bool:
	return steam_unavailable_reason().is_empty()


## Start Steam early (title screen) so invites accepted in the Steam overlay reach us, and join the
## lobby the game was launched with (+connect_lobby <id>). No-op without the extension.
func steam_autostart() -> void:
	if not is_inside_tree() or not steam_extension_present():
		steam_status = "Steam add-on not installed"
		return
	steam_status = steam_unavailable_reason()
	if not steam_status.is_empty():
		return
	var launch: int = int(steam().call("launch_lobby"))
	if launch > 0 and _mode == Mode.OFFLINE:
		join_steam(launch)


## Host over Steam: friends-only lobby, then the Steam invite overlay opens. ERR_UNAVAILABLE without Steam.
func host_steam(friends_only: bool = true) -> Error:
	if not is_inside_tree():
		return ERR_UNCONFIGURED
	steam_status = steam_unavailable_reason()
	if not steam_status.is_empty():
		return ERR_UNAVAILABLE
	leave()
	transport = "steam"
	var err: Error = steam().call("host_lobby", friends_only)
	if err != OK:
		transport = "enet"
		return err
	upnp_status = "Starting a Steam lobby..."
	return OK


## Join a friend's Steam lobby (normally from an invite, not typed). ERR_UNAVAILABLE without Steam.
func join_steam(lobby_id: int) -> Error:
	if not is_inside_tree():
		return ERR_UNCONFIGURED
	if lobby_id <= 0:
		return ERR_INVALID_PARAMETER
	steam_status = steam_unavailable_reason()
	if not steam_status.is_empty():
		return ERR_UNAVAILABLE
	leave()
	transport = "steam"
	var err: Error = steam().call("join_lobby", lobby_id)
	if err != OK:
		transport = "enet"
		return err
	# Waiting for the lobby and then the host: shows as "connecting".
	_mode = Mode.CLIENT
	_connected = false
	_address = "Steam lobby"
	lobby_changed.emit()
	return OK


## Host: open the Steam overlay's invite dialog again.
func invite_steam_friends() -> void:
	if _steam != null and transport == "steam":
		_steam.call("invite_friends")


func _on_steam_peer_ready(peer: MultiplayerPeer, hosting: bool) -> void:
	if transport != "steam":
		peer.close()
		return
	_attach_peer(peer)
	if hosting:
		_mode = Mode.HOST
		_connected = true
		_address = ""
		players = {1: _new_entry(clean_name(local_name))}
		_hello_done[1] = true
		upnp_status = "Hosting on Steam: no ports or addresses needed. Invite friends from the Steam overlay."
		set_process(true)
	else:
		_mode = Mode.CLIENT
		_connected = false
		_address = "Steam lobby"
	lobby_changed.emit()


func _on_steam_failed(reason: String) -> void:
	steam_status = reason
	if transport != "steam":
		return
	leave()
	connection_failed.emit(reason)


func _on_steam_invite(lobby_id: int) -> void:
	if in_match and _mode != Mode.OFFLINE:
		return
	if join_steam(lobby_id) == OK:
		steam_join_started.emit()


## True when hosting, or when a client has finished connecting.
func is_online() -> bool:
	return _mode == Mode.HOST or (_mode == Mode.CLIENT and _connected)


func is_host() -> bool:
	return _mode == Mode.HOST


## True while a join attempt is still waiting for the host.
func is_connecting() -> bool:
	return _mode == Mode.CLIENT and not _connected


## Our peer id: 1 when hosting, the assigned id once connected, else 0.
func my_id() -> int:
	if _mode == Mode.HOST:
		return 1
	if _mode == Mode.CLIENT and _connected and is_inside_tree():
		return multiplayer.get_unique_id()
	return 0


## Crew change request (client -> host; the host applies it and broadcasts). Ignored during a match.
func request_crew(crew: String) -> void:
	if not Factions.DATA.has(crew) or not is_online():
		return
	if _mode == Mode.HOST:
		_h_set_crew(1, crew)
	else:
		_host_request_crew.rpc_id(1, crew)


## Host only: start the match for everyone.
func request_start() -> void:
	if _mode != Mode.HOST or in_match:
		return
	_match_started.rpc()
	_broadcast_lobby()


## Host only: send everybody back to the lobby.
func end_match() -> void:
	if _mode != Mode.HOST or not in_match:
		return
	_match_ended.rpc()
	_broadcast_lobby()


## LAN IPv4 addresses to read out to a friend; Tailscale (100.64/10) ones are tagged and listed last.
func local_addresses() -> PackedStringArray:
	var lan: PackedStringArray = PackedStringArray()
	var tail: PackedStringArray = PackedStringArray()
	for address: String in IP.get_local_addresses():
		var parts: PackedStringArray = address.split(".")
		if parts.size() != 4:
			continue
		var valid: bool = true
		for part: String in parts:
			if not part.is_valid_int():
				valid = false
		if not valid:
			continue
		var first: int = parts[0].to_int()
		var second: int = parts[1].to_int()
		if first == 127 or first == 0 or (first == 169 and second == 254):
			continue
		if first == 100 and second >= 64 and second <= 127:
			tail.append(address + " (Tailscale)")
		elif not lan.has(address):
			lan.append(address)
	lan.append_array(tail)
	return lan


# ---------------------------------------------------------------- lookups

func crew_of(id: int) -> String:
	return String((players.get(id, {}) as Dictionary).get("crew", ""))


func name_of(id: int) -> String:
	return String((players.get(id, {}) as Dictionary).get("name", "Player"))


## Peer ids in the given crew.
func members_of(crew: String) -> Array[int]:
	var out: Array[int] = []
	for id: int in players.keys():
		if String((players[id] as Dictionary).get("crew", "")) == crew:
			out.append(id)
	return out


func has_latest(id: int) -> bool:
	return _latest.has(id)


## Latest position received in a `_state` snapshot (host: used to validate item and hit requests).
func latest_pos(id: int) -> Vector3:
	return (_latest.get(id, {}) as Dictionary).get("pos", Vector3.ZERO)


func latest_state(id: int) -> Dictionary:
	return (_latest.get(id, {}) as Dictionary).duplicate()


## Dead per the last snapshot flags, or reported dead within the last second.
func is_dead(id: int) -> bool:
	var flags: int = int((_latest.get(id, {}) as Dictionary).get("flags", 0))
	return (flags & 4) != 0 or Time.get_ticks_msec() < int(_dead_until.get(id, 0))


## Peer sitting in a seat according to the broadcast seat updates (0 = empty / unknown).
func seat_holder(car: int, seat: int) -> int:
	return int(_seats.get(Vector2i(car, seat), 0))


# ---------------------------------------------------------------- sanitising

## Printable, bracket-free (no BBCode), length-clamped text (see NetSecurity.clean_text).
static func clean_text(text: String, max_len: int) -> String:
	return Sec.clean_text(text, max_len)


static func clean_name(text: String) -> String:
	var out: String = clean_text(text, NAME_MAX)
	return out if not out.is_empty() else "Player"


static func finite_f(value: float) -> bool:
	return is_finite(value) and absf(value) < MAX_COORD * 10.0


static func finite_v(value: Vector3) -> bool:
	return value.is_finite() and absf(value.x) < MAX_COORD and absf(value.y) < MAX_COORD and absf(value.z) < MAX_COORD


static func finite_t(value: Transform3D) -> bool:
	return finite_v(value.origin) and value.basis.x.is_finite() and value.basis.y.is_finite() and value.basis.z.is_finite()


static func channel_ok(channel: String) -> bool:
	if channel == "all" or channel == "crew":
		return true
	return channel.begins_with("call:") and Factions.DATA.has(channel.substr(5))


static func weapon_ok(weapon: String) -> bool:
	return weapon.is_empty() or FastPlayer.WEAPONS.has(weapon)


func _car_ok(car: int) -> bool:
	return car >= 0 and car < max_cars


func _driver_ok(sender: int, car: int) -> bool:
	if not seat_owner.is_valid():
		return true
	var owner_id: int = int(seat_owner.call(car))
	return owner_id == sender or (owner_id == 0 and sender == 1)


func _new_entry(display_name: String) -> Dictionary:
	return {"name": display_name, "crew": _default_crew(), "ready": false, "in_match": in_match}


func _default_crew() -> String:
	for crew: String in Factions.ORDER:
		var used: bool = false
		for entry: Dictionary in players.values():
			if String(entry.get("crew", "")) == crew:
				used = true
		if not used:
			return crew
	return Factions.ORDER[0]


func _clean_dict(data: Dictionary) -> Dictionary:
	if not Sec.dict_ok(data, 64):
		return {}
	return data


# ---------------------------------------------------------------- rate limiting (host side)

## Fixed one-second windows per peer and key. A peer above 5x the limit for two windows in a row is kicked.
func _rate_ok(peer: int, key: String, limit: int) -> bool:
	if peer == 1 or _mode != Mode.HOST:
		return true
	var now: int = Time.get_ticks_msec()
	var per: Dictionary = _rl.get_or_add(peer, {})
	var entry: Array = per.get(key, [now, 0, 0])
	var elapsed: int = now - int(entry[0])
	if elapsed >= 1000:
		if elapsed < 2000 and int(entry[1]) > limit * 5:
			entry[2] = int(entry[2]) + 1
		else:
			entry[2] = 0
		entry[0] = now
		entry[1] = 0
	entry[1] = int(entry[1]) + 1
	per[key] = entry
	if int(entry[2]) >= 2:
		_kick(peer, "flooding '%s' (over %d/s)" % [key, limit * 5])
		return false
	return int(entry[1]) <= limit


func _kick(peer: int, reason: String) -> void:
	last_kick = "peer %d: %s" % [peer, reason]
	print("[net] kicking ", last_kick)
	_rl.erase(peer)
	if players.has(peer) and peer != 1 and is_inside_tree() and multiplayer.get_peers().has(peer):
		var mp: MultiplayerPeer = multiplayer.multiplayer_peer
		if mp != null and not (mp is OfflineMultiplayerPeer):
			mp.disconnect_peer(peer)


## Host: note a malformed / spoofed / impossible message from `peer`; enough of them means a kick.
func _strike(peer: int, reason: String, weight: int = 1) -> void:
	if peer == 1 or _mode != Mode.HOST:
		return
	if _strikes.add(peer, Time.get_ticks_msec(), weight):
		_strikes.clear(peer)
		_kick(peer, "too many bad messages (last: %s)" % reason)


## Host: every client RPC spends one token from the peer's shared budget first.
func _spend(peer: int) -> bool:
	if peer == 1 or _mode != Mode.HOST:
		return true
	var bucket: Sec.TokenBucket = _budget.get(peer)
	if bucket == null:
		bucket = Sec.TokenBucket.new(BUDGET_BURST, BUDGET_RATE)
		_budget[peer] = bucket
	if bucket.take(Time.get_ticks_msec()):
		return true
	_strike(peer, "message budget exceeded")
	return false


## Host: entry gate for every client RPC except the hello: a known peer that finished the handshake
## and is inside its message budget.
func _joined(sender: int) -> bool:
	if sender == 1:
		return true
	if not players.has(sender) or not _hello_done.has(sender):
		if sender > 1:
			_strike(sender, "message before handshake")
		return false
	return _spend(sender)


## Host: drop peers that never finished the handshake, and refused ones once their notice went out.
func _check_hello_timeouts() -> void:
	if _hello_deadline.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	for id: int in _hello_deadline.keys():
		if now < int(_hello_deadline[id]):
			continue
		_hello_deadline.erase(id)
		if _hello_done.has(id):
			continue
		last_kick = "peer %d: %s" % [id, String(_hello_rejected.get(id, "no handshake within %d s" % (HELLO_TIMEOUT_MS / 1000)))]
		print("[net] dropping ", last_kick)
		if is_inside_tree() and multiplayer.get_peers().has(id):
			var mp: MultiplayerPeer = multiplayer.multiplayer_peer
			if mp != null and not (mp is OfflineMultiplayerPeer):
				mp.disconnect_peer(id)


## Host: may this snapshot position follow the last one? Handles respawn grace, map bounds and resync.
func _move_ok(sender: int, pos: Vector3) -> bool:
	if sender == 1 or _mode != Mode.HOST:
		return true
	if not Sec.in_map(pos, map_half_extent):
		_strike(sender, "position outside the map")
		return false
	var now: int = Time.get_ticks_msec()
	var prev: Dictionary = _latest.get(sender, {})
	var last_ms: int = int(_state_ms.get(sender, -1))
	var grace: bool = now < _teleport_all_until or now < int(_teleport_until.get(sender, 0)) or (int(prev.get("flags", 0)) & 4) != 0
	if prev.is_empty() or last_ms < 0 or grace:
		_tp_rejects.erase(sender)
		_state_ms[sender] = now
		return true
	if Sec.step_ok(prev.get("pos", pos), pos, float(now - last_ms) / 1000.0):
		_tp_rejects.erase(sender)
		_state_ms[sender] = now
		return true
	var rejects: int = int(_tp_rejects.get(sender, 0)) + 1
	_tp_rejects[sender] = rejects
	if rejects >= TELEPORT_RESYNC:
		# Legit rare teleports (stuck-car recovery) end up here once; a speed hacker keeps striking.
		_tp_rejects.erase(sender)
		_state_ms[sender] = now
		_strike(sender, "teleport")
		return true
	return false


## Let `peer` (0 = everyone) jump once, e.g. after a respawn or round reset.
func allow_teleport(peer: int = 0) -> void:
	var until: int = Time.get_ticks_msec() + TELEPORT_GRACE_MS
	if peer == 0:
		_teleport_all_until = until
	else:
		_teleport_until[peer] = until


# ---------------------------------------------------------------- peer plumbing

func _attach_peer(peer: MultiplayerPeer) -> void:
	multiplayer.multiplayer_peer = peer
	var scene_mp: SceneMultiplayer = multiplayer as SceneMultiplayer
	if scene_mp != null:
		# Never let remote peers send Objects or scripts: only plain Variants are decoded.
		scene_mp.allow_object_decoding = false
		# Clients never reach each other directly: the host validates and re-broadcasts (see _relay_*).
		scene_mp.server_relay = false


func _reset_state() -> void:
	players = {}
	in_match = false
	_latest.clear()
	_dead_until.clear()
	_death_ms.clear()
	_claim_ok.clear()
	_hello_done.clear()
	_rl.clear()
	_seats.clear()
	_hello_deadline.clear()
	_hello_rejected.clear()
	_budget.clear()
	_strikes.reset()
	_state_ms.clear()
	_tp_rejects.clear()
	_teleport_until.clear()
	_teleport_all_until = 0
	_last_phase = ""
	_last_hitter.clear()


func _on_peer_connected(id: int) -> void:
	if _mode != Mode.HOST:
		return
	if players.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	players[id] = _new_entry("Player %d" % id)
	_hello_deadline[id] = Time.get_ticks_msec() + HELLO_TIMEOUT_MS


func _on_peer_disconnected(id: int) -> void:
	if _mode != Mode.HOST or not players.has(id):
		return
	var had_hello: bool = _hello_done.has(id)
	players.erase(id)
	_latest.erase(id)
	_dead_until.erase(id)
	_death_ms.erase(id)
	_claim_ok.erase(id)
	_hello_done.erase(id)
	_rl.erase(id)
	_voice_radio_until.erase(id)
	_hello_deadline.erase(id)
	_hello_rejected.erase(id)
	_budget.erase(id)
	_strikes.clear(id)
	_state_ms.erase(id)
	_tp_rejects.erase(id)
	_teleport_until.erase(id)
	_last_hitter.erase(id)
	for key: Vector2i in _seats.keys():
		if int(_seats[key]) == id:
			host_seat_leave.emit(id, key.x, key.y)
			_seats.erase(key)
	if had_hello:
		_peer_gone.rpc(id)
	_broadcast_lobby()
	if had_hello:
		peer_left.emit(id)


func _on_connected_to_server() -> void:
	if _mode != Mode.CLIENT:
		return
	_connected = true
	_host_hello.rpc_id(1, clean_name(local_name), build_tag)
	connected.emit()
	lobby_changed.emit()


func _on_connection_failed() -> void:
	if _mode != Mode.CLIENT:
		return
	var message: String = "Could not connect to %s:%d — is the host running and the port open?" % [_address, _port]
	if transport == "steam":
		message = "Could not reach the host over Steam. Ask them to invite you again."
	leave()
	connection_failed.emit(message)


func _on_server_disconnected() -> void:
	if _mode != Mode.CLIENT:
		return
	leave()
	server_closed.emit()


func _broadcast_lobby() -> void:
	if _mode != Mode.HOST:
		return
	# Peers still in (or refused at) the handshake are not announced to the others.
	var public: Dictionary = {}
	for id: int in players.keys():
		if _hello_done.has(id):
			public[id] = players[id]
	_sync_lobby.rpc(public, in_match)
	lobby_changed.emit()


func _can_send() -> bool:
	return _mode == Mode.HOST or (_mode == Mode.CLIENT and _connected)


# ---------------------------------------------------------------- lobby RPCs

@rpc("any_peer", "reliable", "call_remote", 0)
func _host_hello(display_name: String, version: String) -> void:
	if _mode != Mode.HOST:
		return
	_h_hello(multiplayer.get_remote_sender_id(), display_name, version)


## Host handshake: name + build tag. Returns "" when accepted, else the refusal reason.
func _h_hello(sender: int, display_name: String, version: String) -> String:
	if not players.has(sender) or _hello_done.has(sender) or _hello_rejected.has(sender):
		_strike(sender, "repeated hello")
		return "repeated"
	if not _rate_ok(sender, "hello", LIMIT_HELLO) or not _spend(sender):
		return "flood"
	var problem: String = Sec.check_version(version, build_tag)
	if not problem.is_empty():
		_hello_rejected[sender] = problem
		# Tell them why, then drop them shortly after (the notice needs a moment to leave).
		_hello_deadline[sender] = Time.get_ticks_msec() + 500
		if sender != 1 and is_inside_tree() and multiplayer.get_peers().has(sender):
			_hello_refused.rpc_id(sender, problem)
		return problem
	_hello_done[sender] = true
	_hello_deadline.erase(sender)
	(players[sender] as Dictionary)["name"] = clean_name(display_name)
	_broadcast_lobby()
	peer_joined.emit(sender)
	return ""


@rpc("authority", "reliable", "call_remote", 0)
func _hello_refused(reason: String) -> void:
	if _mode != Mode.CLIENT:
		return
	var message: String = "The host refused the connection: %s. Both players need the same game build." % clean_text(reason, 96)
	leave()
	connection_failed.emit(message)


@rpc("any_peer", "reliable", "call_remote", 0)
func _host_request_crew(crew: String) -> void:
	if _mode != Mode.HOST or not _joined(multiplayer.get_remote_sender_id()):
		return
	_h_set_crew(multiplayer.get_remote_sender_id(), crew)


func _h_set_crew(sender: int, crew: String) -> void:
	if not players.has(sender) or in_match or not Factions.DATA.has(crew):
		return
	if not _rate_ok(sender, "req", LIMIT_REQUEST):
		return
	(players[sender] as Dictionary)["crew"] = crew
	_broadcast_lobby()


@rpc("authority", "reliable", "call_remote", 0)
func _sync_lobby(list: Dictionary, match_on: bool) -> void:
	if _mode != Mode.CLIENT:
		return
	var clean: Dictionary = {}
	for key: Variant in list.keys():
		var value: Variant = list[key]
		if typeof(key) != TYPE_INT or typeof(value) != TYPE_DICTIONARY or clean.size() >= MAX_PLAYERS:
			continue
		var crew: String = String((value as Dictionary).get("crew", ""))
		if not Factions.DATA.has(crew):
			crew = Factions.ORDER[0]
		clean[int(key)] = {
			"name": clean_name(String((value as Dictionary).get("name", ""))),
			"crew": crew,
			"ready": bool((value as Dictionary).get("ready", false)),
			"in_match": bool((value as Dictionary).get("in_match", false)),
		}
	var old_ids: Array = players.keys()
	players = clean
	var me: int = my_id()
	for id: int in clean.keys():
		if id != me and not old_ids.has(id):
			peer_joined.emit(id)
	for id: int in old_ids:
		if not clean.has(id):
			_latest.erase(id)
			peer_left.emit(id)
	lobby_changed.emit()
	if match_on and not in_match:
		in_match = true
		match_started.emit()
	elif not match_on and in_match:
		in_match = false
		match_ended.emit()


@rpc("authority", "reliable", "call_local", 0)
func _match_started() -> void:
	if in_match or _mode == Mode.OFFLINE:
		return
	in_match = true
	allow_teleport()
	for entry: Dictionary in players.values():
		entry["in_match"] = true
	match_started.emit()


@rpc("authority", "reliable", "call_local", 0)
func _match_ended() -> void:
	if not in_match or _mode == Mode.OFFLINE:
		return
	in_match = false
	for entry: Dictionary in players.values():
		entry["in_match"] = false
	_dead_until.clear()
	match_ended.emit()


@rpc("authority", "reliable", "call_remote", 0)
func _peer_gone(id: int) -> void:
	if _mode != Mode.CLIENT or id == my_id():
		return
	players.erase(id)
	_latest.erase(id)
	for key: Vector2i in _seats.keys():
		if int(_seats[key]) == id:
			_seats.erase(key)
	peer_left.emit(id)
	lobby_changed.emit()


# ---------------------------------------------------------------- snapshots
#
# Clients send snapshots / fx / glass / world events to the host only (server relay is off). The host
# validates, uses them, and re-broadcasts to the other clients through the authority-only `_relay_*`
# RPCs, stamping the real sender id. Clients accept these messages from the host (peer 1) only.

## Host: peers that should receive a relay of `sender`'s message.
func _relay_targets(sender: int) -> Array[int]:
	var out: Array[int] = []
	if _mode != Mode.HOST or not is_inside_tree():
		return out
	var live: PackedInt32Array = multiplayer.get_peers()
	for id: int in _hello_done.keys():
		if id != 1 and id != sender and live.has(id):
			out.append(id)
	return out


## Common gate for the any_peer broadcast RPCs: on a client only the host may send; on the host the
## sender must have joined, be inside its budget and under the per-kind rate.
func _gate(sender: int, key: String, limit: int) -> bool:
	if _mode == Mode.CLIENT:
		return sender == 1
	if _mode != Mode.HOST or sender <= 1:
		return false
	return _joined(sender) and _rate_ok(sender, key, limit)


func _check_state(sender: int, pos: Vector3, yaw: float, pitch: float, flags: int, weapon: String, car: int, seat: int, health: float) -> Dictionary:
	if not finite_v(pos) or not finite_f(yaw) or not finite_f(pitch) or not finite_f(health):
		_strike(sender, "non-finite snapshot")
		return {}
	if not Sec.string_ok(weapon, 32) or not weapon_ok(weapon) or car < -1 or car >= max_cars or seat < -1 or seat >= MAX_SEAT:
		_strike(sender, "bad snapshot fields")
		return {}
	return {
		"pos": pos, "yaw": wrapf(yaw, -TAU, TAU), "pitch": clampf(pitch, -PI, PI), "flags": clampi(flags, 0, 255), "weapon": weapon,
		"car": car, "seat": seat, "health": clampf(health, 0.0, 1000.0),
	}


func send_state(pos: Vector3, yaw: float, pitch: float, flags: int, weapon: String, car: int, seat: int, health: float) -> void:
	var me: int = my_id()
	if me == 0:
		return
	_latest[me] = {"pos": pos, "yaw": yaw, "pitch": pitch, "flags": flags, "weapon": weapon, "car": car, "seat": seat, "health": health}
	if _mode == Mode.HOST:
		_state.rpc(pos, yaw, pitch, flags, weapon, car, seat, health)
	elif _can_send():
		_state.rpc_id(1, pos, yaw, pitch, flags, weapon, car, seat, health)


@rpc("any_peer", "unreliable_ordered", "call_remote", 1)
func _state(pos: Vector3, yaw: float, pitch: float, flags: int, weapon: String, car: int, seat: int, health: float) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not _gate(sender, "state", LIMIT_STATE):
		return
	var state: Dictionary = _check_state(sender, pos, yaw, pitch, flags, weapon, car, seat, health)
	if state.is_empty() or not _move_ok(sender, pos):
		return
	_latest[sender] = state
	remote_state.emit(sender, state)
	for id: int in _relay_targets(sender):
		_relay_state.rpc_id(id, sender, pos, float(state["yaw"]), float(state["pitch"]), int(state["flags"]), weapon, car, seat, float(state["health"]))


@rpc("authority", "unreliable_ordered", "call_remote", 1)
func _relay_state(id: int, pos: Vector3, yaw: float, pitch: float, flags: int, weapon: String, car: int, seat: int, health: float) -> void:
	if _mode != Mode.CLIENT or id <= 1 or id == my_id():
		return
	var state: Dictionary = _check_state(id, pos, yaw, pitch, flags, weapon, car, seat, health)
	if state.is_empty():
		return
	_latest[id] = state
	remote_state.emit(id, state)


func send_car_state(car: int, xform: Transform3D, vel: Vector3, steer: float, speed: float, flags: int) -> void:
	if _mode == Mode.HOST:
		_car_state.rpc(car, xform, vel, steer, speed, flags)
	elif _can_send():
		_car_state.rpc_id(1, car, xform, vel, steer, speed, flags)


func _car_fields_ok(sender: int, car: int, xform: Transform3D, vel: Vector3, steer: float, speed: float) -> bool:
	if not _car_ok(car) or not finite_t(xform) or not finite_v(vel) or not finite_f(steer) or not finite_f(speed):
		_strike(sender, "bad car state")
		return false
	if _mode == Mode.HOST and sender != 1 and not Sec.in_map(xform.origin, map_half_extent):
		_strike(sender, "car outside the map")
		return false
	return true


@rpc("any_peer", "unreliable_ordered", "call_remote", 1)
func _car_state(car: int, xform: Transform3D, vel: Vector3, steer: float, speed: float, flags: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not _gate(sender, "car", LIMIT_CAR) or not _car_fields_ok(sender, car, xform, vel, steer, speed):
		return
	if not _driver_ok(sender, car):
		# Somebody else's car: silently ignored (seat changes race snapshots), no strike.
		return
	var clean_flags: int = clampi(flags, 0, 255)
	remote_car.emit(car, {"from": sender, "xform": xform, "vel": vel, "steer": steer, "speed": speed, "flags": clean_flags})
	for id: int in _relay_targets(sender):
		_relay_car.rpc_id(id, sender, car, xform, vel, steer, speed, clean_flags)


@rpc("authority", "unreliable_ordered", "call_remote", 1)
func _relay_car(from_id: int, car: int, xform: Transform3D, vel: Vector3, steer: float, speed: float, flags: int) -> void:
	if _mode != Mode.CLIENT or from_id <= 1 or from_id == my_id() or not _car_fields_ok(from_id, car, xform, vel, steer, speed):
		return
	if not _driver_ok(from_id, car):
		return
	remote_car.emit(car, {"from": from_id, "xform": xform, "vel": vel, "steer": steer, "speed": speed, "flags": clampi(flags, 0, 255)})


# ---------------------------------------------------------------- shots and damage

func send_shot_fx(origin: Vector3, end: Vector3, weapon: String, quiet: bool) -> void:
	if _mode == Mode.HOST:
		_shot_fx.rpc(origin, end, weapon, quiet)
	elif _can_send():
		_shot_fx.rpc_id(1, origin, end, weapon, quiet)


func _fx_ok(sender: int, origin: Vector3, end: Vector3, weapon: String) -> bool:
	if not finite_v(origin) or not finite_v(end) or not Sec.string_ok(weapon, 32) or not weapon_ok(weapon):
		_strike(sender, "bad shot fx")
		return false
	return origin.distance_to(end) <= MAX_HIT_RANGE * 2.0


@rpc("any_peer", "reliable", "call_remote", 0)
func _shot_fx(origin: Vector3, end: Vector3, weapon: String, quiet: bool) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not _gate(sender, "fx", LIMIT_HIT) or not _fx_ok(sender, origin, end, weapon):
		return
	remote_shot.emit(sender, origin, end, weapon, quiet)
	for id: int in _relay_targets(sender):
		_relay_shot_fx.rpc_id(id, sender, origin, end, weapon, quiet)


@rpc("authority", "reliable", "call_remote", 0)
func _relay_shot_fx(from_id: int, origin: Vector3, end: Vector3, weapon: String, quiet: bool) -> void:
	if _mode != Mode.CLIENT or from_id <= 1 or from_id == my_id() or not _fx_ok(from_id, origin, end, weapon):
		return
	remote_shot.emit(from_id, origin, end, weapon, quiet)


func send_claim_hit(victim: int, amount: float, head: bool, origin: Vector3, point: Vector3, weapon: String) -> void:
	if _mode == Mode.HOST:
		_h_claim_hit(1, victim, amount, head, origin, point, weapon)
	elif _can_send():
		_host_claim_hit.rpc_id(1, victim, amount, head, origin, point, weapon)


@rpc("any_peer", "reliable", "call_remote", 0)
func _host_claim_hit(victim: int, amount: float, head: bool, origin: Vector3, point: Vector3, weapon: String) -> void:
	if _mode != Mode.HOST or not _joined(multiplayer.get_remote_sender_id()):
		return
	_h_claim_hit(multiplayer.get_remote_sender_id(), victim, amount, head, origin, point, weapon)


## Host validation of a hit claim: alive, phase, rate, range, point near the victim's latest position, damage cap.
## Returns true when damage was sent to the victim.
func _h_claim_hit(sender: int, victim: int, amount: float, head: bool, origin: Vector3, point: Vector3, weapon: String) -> bool:
	if _mode != Mode.HOST or not accept_hits:
		return false
	if not players.has(sender) or not players.has(victim) or sender == victim:
		return false
	if not _rate_ok(sender, "claim", LIMIT_HIT * 2):
		return false
	if not finite_f(amount) or amount <= 0.0 or not finite_v(origin) or not finite_v(point) or not Sec.string_ok(weapon, 32) or not weapon_ok(weapon):
		_strike(sender, "malformed hit claim")
		return false
	# The claimed weapon must be the one the shooter is holding (when their snapshot says so). The host
	# is the referee in the listen-server model, so its own claims skip the client-only checks.
	var held: String = String((_latest.get(sender, {}) as Dictionary).get("weapon", weapon))
	if sender != 1 and not weapon.is_empty() and not held.is_empty() and held != weapon:
		return false
	# Accepted claims are capped at 25 per second per peer (one per 40 ms).
	var now: int = Time.get_ticks_msec()
	if now - int(_claim_ok.get(sender, -1000)) < 1000 / LIMIT_HIT:
		return false
	if is_dead(sender) or is_dead(victim):
		return false
	if not _latest.has(victim):
		return false
	if origin.distance_to(point) > MAX_HIT_RANGE:
		return false
	if point.distance_to(latest_pos(victim)) > HIT_POINT_SLACK:
		return false
	# The shot must start near where the shooter actually is.
	if sender != 1 and _latest.has(sender) and origin.distance_to(latest_pos(sender)) > HIT_ORIGIN_SLACK:
		_strike(sender, "hit claim from far away")
		return false
	# Optional line-of-sight hook set by the lead: `los_check(from: Vector3, to: Vector3) -> bool`.
	if los_check.is_valid() and not bool(los_check.call(origin, point)):
		return false
	_claim_ok[sender] = now
	_last_hitter[victim] = [sender, now]
	var dealt: float = minf(amount, Sec.max_claim_damage(weapon, FastPlayer.WEAPONS, MAX_HIT_DAMAGE))
	hit_validated.emit(sender, victim, dealt, head, weapon)
	if victim == 1:
		damage_received.emit(dealt, origin, sender)
	else:
		_apply_damage.rpc_id(victim, dealt, origin, sender)
	return true


@rpc("authority", "reliable", "call_remote", 0)
func _apply_damage(amount: float, source: Vector3, attacker: int) -> void:
	if _mode != Mode.CLIENT or not finite_f(amount) or not finite_v(source):
		return
	damage_received.emit(clampf(amount, 0.0, MAX_HIT_DAMAGE), source, attacker)


func send_report_death(killer: int, pos: Vector3) -> void:
	if _mode == Mode.HOST:
		_h_report_death(1, killer, pos)
	elif _can_send():
		_host_report_death.rpc_id(1, killer, pos)


@rpc("any_peer", "reliable", "call_remote", 0)
func _host_report_death(killer: int, pos: Vector3) -> void:
	if _mode != Mode.HOST or not _joined(multiplayer.get_remote_sender_id()):
		return
	# The sender IS the victim: nobody can report another peer's death.
	_h_report_death(multiplayer.get_remote_sender_id(), killer, pos)


func _h_report_death(sender: int, killer: int, pos: Vector3) -> void:
	if _mode != Mode.HOST or not players.has(sender) or not finite_v(pos):
		return
	if not _rate_ok(sender, "req", LIMIT_REQUEST):
		return
	var now: int = Time.get_ticks_msec()
	if now - int(_death_ms.get(sender, -10000)) < 2000:
		return
	_death_ms[sender] = now
	if killer != 0 and not players.has(killer):
		killer = 0
	# A client can only blame the player whose hit the host validated on it in the last 15 s
	# (otherwise it could fake kills between crews and wipe their clean-deal bonus).
	if sender != 1 and killer != 0:
		var last: Array = _last_hitter.get(sender, [0, -100000])
		if int(last[0]) != killer or now - int(last[1]) > 15000:
			killer = 0
	_player_died.rpc(sender, killer, pos)


@rpc("authority", "reliable", "call_local", 0)
func _player_died(id: int, killer: int, pos: Vector3) -> void:
	if _mode == Mode.OFFLINE or not finite_v(pos):
		return
	_dead_until[id] = Time.get_ticks_msec() + 1000
	if _mode == Mode.HOST:
		# They respawn at HQ after the timer: allow that jump.
		_teleport_until[id] = Time.get_ticks_msec() + 30000
	player_died.emit(id, killer, pos)


# ---------------------------------------------------------------- seats and cars

func send_request_seat(car: int, seat: int) -> void:
	if _mode == Mode.HOST:
		_h_request_seat(1, car, seat)
	elif _can_send():
		_host_request_seat.rpc_id(1, car, seat)


@rpc("any_peer", "reliable", "call_remote", 0)
func _host_request_seat(car: int, seat: int) -> void:
	if _mode == Mode.HOST and _joined(multiplayer.get_remote_sender_id()):
		_h_request_seat(multiplayer.get_remote_sender_id(), car, seat)


func _h_request_seat(sender: int, car: int, seat: int) -> void:
	if not players.has(sender) or not _car_ok(car) or seat < 0 or seat >= MAX_SEAT:
		return
	if _rate_ok(sender, "req", LIMIT_REQUEST):
		host_seat_request.emit(sender, car, seat)


func send_leave_seat(car: int, seat: int) -> void:
	if _mode == Mode.HOST:
		_h_leave_seat(1, car, seat)
	elif _can_send():
		_host_leave_seat.rpc_id(1, car, seat)


@rpc("any_peer", "reliable", "call_remote", 0)
func _host_leave_seat(car: int, seat: int) -> void:
	if _mode == Mode.HOST and _joined(multiplayer.get_remote_sender_id()):
		_h_leave_seat(multiplayer.get_remote_sender_id(), car, seat)


func _h_leave_seat(sender: int, car: int, seat: int) -> void:
	if not players.has(sender) or not _car_ok(car) or seat < 0 or seat >= MAX_SEAT:
		return
	# Only the peer that holds the seat may free it.
	if seat_holder(car, seat) != sender:
		_strike(sender, "leaving a seat it does not hold")
		return
	if _rate_ok(sender, "req", LIMIT_REQUEST):
		host_seat_leave.emit(sender, car, seat)


## Host: announce who sits where (peer 0 = empty).
func broadcast_seat(car: int, seat: int, peer: int) -> void:
	if _mode == Mode.HOST:
		_seat_update.rpc(car, seat, peer)


@rpc("authority", "reliable", "call_local", 0)
func _seat_update(car: int, seat: int, peer: int) -> void:
	if _mode == Mode.OFFLINE or not _car_ok(car) or seat < 0 or seat >= MAX_SEAT or peer < 0:
		return
	if peer == 0:
		_seats.erase(Vector2i(car, seat))
	else:
		_seats[Vector2i(car, seat)] = peer
	seat_update.emit(car, seat, peer)


func send_car_damage(car: int, amount: float) -> void:
	if _mode == Mode.HOST:
		_h_car_damage(1, car, amount)
	elif _can_send():
		_host_car_damage.rpc_id(1, car, amount)


@rpc("any_peer", "reliable", "call_remote", 0)
func _host_car_damage(car: int, amount: float) -> void:
	if _mode == Mode.HOST and _joined(multiplayer.get_remote_sender_id()):
		_h_car_damage(multiplayer.get_remote_sender_id(), car, amount)


func _h_car_damage(sender: int, car: int, amount: float) -> void:
	if not players.has(sender) or not _car_ok(car) or not finite_f(amount) or amount <= 0.0:
		return
	if _rate_ok(sender, "req", LIMIT_REQUEST):
		host_car_damage.emit(sender, car, minf(amount, 1000.0))


## Host: announce a car's health.
func broadcast_car_health(car: int, health: float, disabled: bool) -> void:
	if _mode == Mode.HOST:
		_car_health.rpc(car, health, disabled)


@rpc("authority", "reliable", "call_local", 0)
func _car_health(car: int, health: float, disabled: bool) -> void:
	if _mode == Mode.OFFLINE or not _car_ok(car) or not finite_f(health):
		return
	car_health.emit(car, health, disabled)


func send_glass(car: int, index: int) -> void:
	if _mode == Mode.HOST:
		_glass.rpc(car, index)
	elif _can_send():
		_glass.rpc_id(1, car, index)


@rpc("any_peer", "reliable", "call_remote", 0)
func _glass(car: int, index: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not _gate(sender, "car", LIMIT_CAR):
		return
	if not _car_ok(car) or index < 0 or index > 255:
		_strike(sender, "bad glass index")
		return
	remote_glass.emit(car, index)
	for id: int in _relay_targets(sender):
		_relay_glass.rpc_id(id, sender, car, index)


@rpc("authority", "reliable", "call_remote", 0)
func _relay_glass(from_id: int, car: int, index: int) -> void:
	if _mode != Mode.CLIENT or from_id <= 1 or from_id == my_id() or not _car_ok(car) or index < 0 or index > 255:
		return
	remote_glass.emit(car, index)


# ---------------------------------------------------------------- items, round, money

func send_item_request(action: String, item: int, pos: Vector3) -> void:
	if _mode == Mode.HOST:
		_h_item_request(1, action, item, pos)
	elif _can_send():
		_host_item_request.rpc_id(1, action, item, pos)


@rpc("any_peer", "reliable", "call_remote", 0)
func _host_item_request(action: String, item: int, pos: Vector3) -> void:
	if _mode == Mode.HOST and _joined(multiplayer.get_remote_sender_id()):
		_h_item_request(multiplayer.get_remote_sender_id(), action, item, pos)


func _h_item_request(sender: int, action: String, item: int, pos: Vector3) -> void:
	if not players.has(sender) or not ITEM_ACTIONS.has(action) or item < 0 or item >= max_items or not finite_v(pos):
		_strike(sender, "bad item request")
		return
	if _rate_ok(sender, "req", LIMIT_REQUEST):
		host_item_request.emit(sender, action, item, pos)


## Host: announce an item's new state (holder, position, banked...).
func broadcast_item(item: int, data: Dictionary) -> void:
	if _mode == Mode.HOST:
		_item_update.rpc(item, data)


@rpc("authority", "reliable", "call_local", 0)
func _item_update(item: int, data: Dictionary) -> void:
	if _mode == Mode.OFFLINE or item < 0 or item >= max_items:
		return
	item_update.emit(item, _clean_dict(data))


## Host: announce the round (phase, time_left, round, roles, bank).
func broadcast_round(data: Dictionary) -> void:
	if _mode == Mode.HOST:
		_round_state.rpc(data)


@rpc("authority", "reliable", "call_local", 0)
func _round_state(data: Dictionary) -> void:
	if _mode == Mode.OFFLINE:
		return
	var phase: String = str(data.get("phase", "")) if data.size() <= 64 else ""
	if phase != _last_phase:
		# A new phase resets everyone to their HQ: let those jumps through.
		_last_phase = phase
		allow_teleport()
	round_state.emit(_clean_dict(data))


## Host: pay one peer (the host itself included).
func grant_to(peer: int, amount: int, reason: String) -> void:
	if _mode != Mode.HOST or not players.has(peer):
		return
	if peer == 1:
		_receive_grant(amount, reason)
	else:
		_grant.rpc_id(peer, amount, reason)


@rpc("authority", "reliable", "call_remote", 0)
func _grant(amount: int, reason: String) -> void:
	if _mode != Mode.CLIENT:
		return
	_receive_grant(amount, reason)


func _receive_grant(amount: int, reason: String) -> void:
	grant.emit(clampi(amount, -100000, 100000), clean_text(reason, REASON_MAX))


# ---------------------------------------------------------------- world events

const WORLD_KINDS: PackedStringArray = ["door", "lift"]


func send_world_event(kind: String, index: int, value: int) -> void:
	if _mode == Mode.HOST:
		_world_event.rpc(kind, index, value)
	elif _can_send():
		_world_event.rpc_id(1, kind, index, value)


static func world_event_ok(kind: String, index: int, value: int) -> bool:
	return kind.length() <= 8 and WORLD_KINDS.has(kind) and index >= 0 and index <= 1023 and value >= -1 and value <= 255


@rpc("any_peer", "reliable", "call_remote", 0)
func _world_event(kind: String, index: int, value: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not _gate(sender, "req", LIMIT_REQUEST):
		return
	if not world_event_ok(kind, index, value):
		_strike(sender, "bad world event")
		return
	world_event.emit(kind, index, value)
	for id: int in _relay_targets(sender):
		_relay_world_event.rpc_id(id, sender, kind, index, value)


@rpc("authority", "reliable", "call_remote", 0)
func _relay_world_event(from_id: int, kind: String, index: int, value: int) -> void:
	if _mode != Mode.CLIENT or from_id <= 1 or from_id == my_id() or not world_event_ok(kind, index, value):
		return
	world_event.emit(kind, index, value)


# ---------------------------------------------------------------- chat

## Channels: "all", "crew", or "call:<crew_id>" (that crew plus the sender).
func send_chat(channel: String, text: String) -> void:
	if _mode == Mode.HOST:
		_h_chat(1, channel, text)
	elif _can_send():
		_host_chat.rpc_id(1, channel, text)


@rpc("any_peer", "reliable", "call_remote", 0)
func _host_chat(channel: String, text: String) -> void:
	if _mode == Mode.HOST and _joined(multiplayer.get_remote_sender_id()):
		_h_chat(multiplayer.get_remote_sender_id(), channel, text)


func _h_chat(sender: int, channel: String, text: String) -> void:
	if not players.has(sender) or not Sec.string_ok(channel, 32) or not channel_ok(channel):
		return
	var clean: String = clean_text(text, CHAT_MAX)
	if clean.is_empty() or not _rate_ok(sender, "chat", LIMIT_CHAT):
		return
	if channel.begins_with("call:") and call_gate.is_valid() and not bool(call_gate.call(sender)):
		return
	var sender_crew: String = crew_of(sender)
	for id: int in players.keys():
		var crew: String = crew_of(id)
		var wanted: bool = id == sender or channel == "all"
		if channel == "crew" and crew == sender_crew:
			wanted = true
		elif channel.begins_with("call:") and crew == channel.substr(5):
			wanted = true
		if not wanted:
			continue
		if id == 1:
			chat.emit(sender, channel, clean)
		else:
			_chat.rpc_id(id, sender, channel, clean)


@rpc("authority", "reliable", "call_remote", 0)
func _chat(from_id: int, channel: String, text: String) -> void:
	if _mode != Mode.CLIENT or not channel_ok(channel):
		return
	var clean: String = clean_text(text, CHAT_MAX)
	if not clean.is_empty():
		chat.emit(from_id, channel, clean)


# ---------------------------------------------------------------- voice
#
# Clients send ADPCM frames (scripts/voice_codec.gd) to the host on transfer channel 2, unreliable.
# The host validates sender / mode / size / rate, decides who may hear it (scripts/voice_relay.gd:
# proximity = within voice_range metres by the HOST'S view of positions, crew = the talker's crew only)
# and relays with the real sender id stamped in. Clients accept voice from the host only.

func send_voice(mode: int, frame: PackedByteArray) -> void:
	if _mode == Mode.HOST:
		_h_voice(1, mode, frame)
	elif _can_send():
		_host_voice.rpc_id(1, mode, frame)


@rpc("any_peer", "unreliable_ordered", "call_remote", 2)
func _host_voice(mode: int, frame: PackedByteArray) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if _gate(sender, "voice", LIMIT_VOICE):
		_h_voice(sender, mode, frame)


## Host: validate and route one frame. Returns how many listeners it went to (0 when dropped).
func _h_voice(sender: int, mode: int, frame: PackedByteArray) -> int:
	if not players.has(sender) or not VoiceRelayS.valid_mode(mode):
		_strike(sender, "bad voice mode")
		return 0
	if frame.size() < VoiceCodecS.MIN_FRAME_BYTES or frame.size() > VoiceCodecS.MAX_FRAME_BYTES:
		_strike(sender, "bad voice frame size")
		return 0
	var now: int = Time.get_ticks_msec()
	if mode == VoiceRelayS.Mode.CREW:
		_voice_radio_until[sender] = now + VOICE_RADIO_HOLD_MS
	elif now < int(_voice_radio_until.get(sender, 0)):
		# Holding the squad key mutes you in proximity: the same mic can't go out both ways.
		return 0
	var peers: Dictionary = {}
	for id: int in players.keys():
		var pos: Vector3 = Vector3.INF
		var state: Dictionary = _latest.get(id, {})
		if state.has("pos"):
			pos = state["pos"]
		var space: int = -1
		if voice_space.is_valid() and pos.is_finite():
			space = int(voice_space.call(pos))
		peers[id] = {"crew": crew_of(id), "pos": pos, "dead": is_dead(id), "space": space}
	var doors: Array = []
	if voice_doors.is_valid():
		doors = voice_doors.call()
	var sent: int = 0
	for entry: Array in VoiceRelayS.targets(sender, mode, peers, voice_range, doors):
		var id: int = int(entry[0])
		var dist: float = float(entry[1])
		var muffled: bool = bool(entry[2])
		if voice_tap.is_valid():
			voice_tap.call(id, sender, mode, dist, frame, muffled)
			sent += 1
		elif id == 1:
			voice_frame.emit(sender, mode, frame, dist, muffled)
			sent += 1
		elif is_inside_tree() and multiplayer.get_peers().has(id) and _hello_done.has(id):
			_relay_voice.rpc_id(id, sender, mode, dist, frame, muffled)
			sent += 1
	return sent


@rpc("authority", "unreliable_ordered", "call_remote", 2)
func _relay_voice(from_id: int, mode: int, dist: float, frame: PackedByteArray, muffled: bool) -> void:
	if _mode != Mode.CLIENT or multiplayer.get_remote_sender_id() != 1 or from_id <= 1 or from_id == my_id():
		return
	if not VoiceRelayS.valid_mode(mode) or not is_finite(dist) or frame.size() < VoiceCodecS.MIN_FRAME_BYTES or frame.size() > VoiceCodecS.MAX_FRAME_BYTES:
		return
	voice_frame.emit(from_id, mode, frame, clampf(dist, 0.0, 9999.0), muffled)


# ---------------------------------------------------------------- UPnP (worker threads)

func _start_upnp(port: int) -> void:
	if not use_upnp:
		upnp_status = "UPnP skipped: forward UDP %d or use Tailscale" % port
		return
	_upnp_gen += 1
	upnp_status = "Opening port %d on your router..." % port
	var thread := Thread.new()
	if thread.start(_upnp_worker.bind(port, _upnp_gen)) == OK:
		_threads.append(thread)
		set_process(true)
	else:
		upnp_status = "Could not open port: forward UDP %d or use Tailscale" % port


## Runs on a worker thread; reports back with call_deferred.
func _upnp_worker(port: int, gen: int) -> void:
	var upnp: UPNP = UPNP.new()
	var ok: bool = false
	var external: String = ""
	if upnp.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS:
		var gateway: UPNPDevice = upnp.get_gateway() if upnp.get_device_count() > 0 else null
		if gateway != null and gateway.is_valid_gateway():
			if upnp.add_port_mapping(port, port, "Fast Talkers", "UDP") == UPNP.UPNP_RESULT_SUCCESS:
				ok = true
				external = upnp.query_external_address()
	call_deferred("_upnp_finished", gen, upnp, port, ok, external)


func _upnp_finished(gen: int, upnp: UPNP, port: int, ok: bool, external: String) -> void:
	if gen != _upnp_gen:
		# We left before the router answered: undo the mapping if one was made.
		if ok:
			_start_unmap(upnp, port)
		return
	if ok:
		_upnp_obj = upnp
		_upnp_port = port
		upnp_status = "Port %d opened on router" % port
		if not external.is_empty():
			upnp_status += " (external IP %s)" % external
	else:
		upnp_status = "Could not open port: forward UDP %d or use Tailscale" % port
	upnp_done.emit(upnp_status)


func _release_upnp() -> void:
	_upnp_gen += 1
	if _upnp_obj != null:
		_start_unmap(_upnp_obj, _upnp_port)
	_upnp_obj = null
	upnp_status = ""


func _start_unmap(upnp: UPNP, port: int) -> void:
	var thread := Thread.new()
	if thread.start(_upnp_unmap_worker.bind(upnp, port)) == OK:
		_threads.append(thread)
		if is_inside_tree():
			set_process(true)


func _upnp_unmap_worker(upnp: UPNP, port: int) -> void:
	upnp.delete_port_mapping(port, "UDP")


func _reap_threads() -> void:
	for thread: Thread in _threads.duplicate():
		if not thread.is_alive():
			thread.wait_to_finish()
			_threads.erase(thread)
	if _threads.is_empty():
		set_process(false)
