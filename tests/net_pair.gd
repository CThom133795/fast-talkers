extends SceneTree
## Two-process network harness (docs/NET_M1_SPEC.md section 5). Run one copy as host and one as client:
##   godot --headless --path . --script res://tests/net_pair.gd -- --role=host   --port=24651 --steps=lobby
##   godot --headless --path . --script res://tests/net_pair.gd -- --role=client --port=24651 --steps=lobby
## tests/run_net_pair.sh (or .cmd) starts both and prints the RESULT lines.
##
## Steps: a comma separated list run in order (default "lobby"). After the last step the harness always
## runs the "disconnect" teardown. To add a step, add a `match` arm in `_run_step` and two small functions
## (`_step_<name>_host` / `_step_<name>_client`) that use the _check / _wait_until / _wait_seconds helpers.
## The host and client of a step must agree on their message order: each side waits for what the other
## sends. Exit code 0 = all checks passed, 1 = a failure or the watchdog fired.

const WATCHDOG_SECONDS: float = 45.0
## The "round" step drives a whole online round (seats, a lethal hit and a 10 s respawn), so it gets longer.
const ROUND_WATCHDOG_SECONDS: float = 120.0
const Factions = preload("res://scripts/factions.gd")
const HOST_NAME: String = "HostTester"
const CLIENT_NAME: String = "ClientTester"
const CLIENT_CREW: String = "solnegro"

var role: String = ""
var port: int = 24651
var steps: PackedStringArray = PackedStringArray(["lobby"])
var game: Variant
var net: Variant
var checks: int = 0
var failures: int = 0
var finished: bool = false
var watchdog_seconds: float = WATCHDOG_SECONDS
var _last_chat_ms: int = 0
var died_log: Array = []  # each: {"id": int, "killer": int}

# Event log filled by the net signals.
var connected_seen: bool = false
var failed_reason: String = ""
var match_started_seen: bool = false
var server_closed_seen: bool = false
var joined_ids: Array = []
var left_ids: Array = []
var chats: Array = []  # each: {"from": int, "channel": String, "text": String}


func _initialize() -> void:
	call_deferred("_run")


# ---------------------------------------------------------------- helpers

func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
		push_error("FAIL: " + label)


func _frames(count: int) -> void:
	for index: int in range(count):
		await process_frame


func _wait_seconds(seconds: float) -> void:
	var end_ms: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end_ms:
		await process_frame


## Polls `cond` every frame until it returns true or `timeout` seconds pass. Returns the final value.
func _wait_until(cond: Callable, timeout: float) -> bool:
	var end_ms: int = Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end_ms:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _fail_and_quit(message: String) -> void:
	_check(false, message)
	_finish()


func _finish() -> void:
	if finished:
		return
	finished = true
	print("NET PAIR %s RESULT: %d checks, %d failures" % [role.to_upper(), checks, failures])
	quit(0 if failures == 0 else 1)


func _api_missing(names: Array) -> Array:
	var missing: Array = []
	for api_name: String in names:
		if not net.has_method(api_name):
			missing.append(api_name)
	return missing


func _players() -> Dictionary:
	var value: Variant = net.get("players")
	return value if value is Dictionary else {}


func _other_id() -> int:
	## The id of the other participant: the host sees the client's id, the client sees 1.
	if role == "client":
		return 1
	for id: Variant in _players().keys():
		if int(id) != 1:
			return int(id)
	return 0


func _got_chat(text: String, from_id: int) -> bool:
	for entry: Dictionary in chats:
		if entry["text"] == text and int(entry["from"]) == from_id:
			return true
	return false


func _send_chat(text: String) -> bool:
	if net.has_method("send_chat"):
		_last_chat_ms = Time.get_ticks_msec()
		net.call("send_chat", "all", text)
		return true
	return false


# ---------------------------------------------------------------- signals

func _connect_signals() -> void:
	for sig: String in ["connected", "connection_failed", "peer_joined", "peer_left", "server_closed", "match_started", "chat"]:
		if not net.has_signal(sig):
			print("NOTE: net has no signal '%s'" % sig)
	if net.has_signal("connected"):
		net.connect("connected", func() -> void: connected_seen = true)
	if net.has_signal("connection_failed"):
		net.connect("connection_failed", func(reason: String) -> void: failed_reason = reason)
	if net.has_signal("peer_joined"):
		net.connect("peer_joined", func(id: int) -> void: joined_ids.append(id))
	if net.has_signal("peer_left"):
		net.connect("peer_left", func(id: int) -> void: left_ids.append(id))
	if net.has_signal("server_closed"):
		net.connect("server_closed", func() -> void: server_closed_seen = true)
	if net.has_signal("match_started"):
		net.connect("match_started", func() -> void: match_started_seen = true)
	if net.has_signal("player_died"):
		net.connect("player_died", func(id: int, killer: int, _pos: Vector3) -> void:
			died_log.append({"id": id, "killer": killer}))
	if net.has_signal("chat"):
		net.connect("chat", func(from_id: int, channel: String, text: String) -> void:
			chats.append({"from": from_id, "channel": channel, "text": text}))


# ---------------------------------------------------------------- entry

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.substr(7)
		elif arg.begins_with("--port="):
			port = int(arg.substr(7))
		elif arg.begins_with("--steps=") or arg.begins_with("--script-steps="):
			steps = arg.substr(arg.find("=") + 1).split(",", false)
	if role != "host" and role != "client":
		role = "host" if role == "" else role
		print("NET PAIR %s RESULT: 1 checks, 1 failures (bad --role, use host|client)" % role.to_upper())
		quit(1)
		return

	if steps.has("round"):
		watchdog_seconds = ROUND_WATCHDOG_SECONDS
	create_timer(watchdog_seconds).timeout.connect(func() -> void:
		if finished:
			return
		print("WATCHDOG: net_pair %s did not finish in %d s" % [role, int(watchdog_seconds)])
		_check(false, "watchdog: finished within %d s" % int(watchdog_seconds))
		if net != null and net.has_method("leave"):
			net.call("leave")
		_finish())

	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.pause_on_focus_loss = false
	game.settings_path = "user://netpair_%s_settings.cfg" % role
	root.add_child(game)
	await _frames(5)

	net = game.get("net")
	_check(net != null, "game.net exists")
	if net == null:
		_finish()
		return
	_check(net.get_path() == NodePath("/root/FastTalkers/Net"), "net node path is /root/FastTalkers/Net (got %s)" % str(net.get_path()))

	var missing: Array = _api_missing(["host", "join", "leave", "is_online", "is_host", "my_id", "request_crew", "request_start"])
	if not missing.is_empty():
		_fail_and_quit("net API missing (still the stub?): %s" % ", ".join(PackedStringArray(missing)))
		return

	_connect_signals()
	net.set("local_name", HOST_NAME if role == "host" else CLIENT_NAME)

	for step: String in steps:
		if finished:
			return
		print("STEP: ", step)
		await _run_step(step)
	if finished:
		return
	await _run_step("disconnect")
	_finish()


func _run_step(step: String) -> void:
	match step:
		"lobby":
			if role == "host":
				await _step_lobby_host()
			else:
				await _step_lobby_client()
		"disconnect":
			if role == "host":
				await _step_disconnect_host()
			else:
				await _step_disconnect_client()
		"round":
			await _step_round()
		_:
			_check(false, "unknown step '%s'" % step)


# ---------------------------------------------------------------- step: lobby

func _step_lobby_host() -> void:
	var err: int = net.call("host", port)
	_check(err == OK, "host(%d) returns OK (got %d)" % [port, err])
	if err != OK:
		_finish()
		return
	_check(net.call("is_online"), "host is_online()")
	_check(net.call("is_host"), "host is_host()")
	_check(int(net.call("my_id")) == 1, "host my_id() == 1")
	_check(_players().has(1), "host is in its own players list")

	var joined: bool = await _wait_until(func() -> bool: return _players().size() == 2, 20.0)
	_check(joined, "host sees 2 players (got %d)" % _players().size())
	if not joined:
		return
	var client_id: int = _other_id()
	_check(client_id > 1, "client id is not 1 (got %d)" % client_id)
	# The host lists a placeholder on connect and renames it when the client's hello lands.
	await _wait_until(func() -> bool: return str(_players().get(client_id, {}).get("name", "")) == CLIENT_NAME, 5.0)
	_check(str(_players().get(client_id, {}).get("name", "")) == CLIENT_NAME, "client name arrived at host (got '%s')" % str(_players().get(client_id, {}).get("name", "")))
	_check(str(_players().get(1, {}).get("name", "")) == HOST_NAME, "host's own name is in players")
	var host_crew: String = str(_players().get(1, {}).get("crew", ""))
	var client_crew: String = str(_players().get(client_id, {}).get("crew", ""))
	_check(host_crew != "" and client_crew != "", "both players have a crew (host '%s', client '%s')" % [host_crew, client_crew])
	_check(host_crew != client_crew, "default crews differ (both '%s')" % host_crew)

	var switched: bool = await _wait_until(func() -> bool: return str(_players().get(client_id, {}).get("crew", "")) == CLIENT_CREW, 10.0)
	_check(switched, "client changed crew to %s (host view: '%s')" % [CLIENT_CREW, str(_players().get(client_id, {}).get("crew", ""))])

	var host_text: String = "chat from host"
	_check(_send_chat(host_text), "host can send chat (net.send_chat exists)")
	var got: bool = await _wait_until(func() -> bool: return _got_chat("chat from client", client_id), 10.0)
	_check(got, "host received the client's chat on 'all'")

	net.call("request_start")
	var started: bool = await _wait_until(func() -> bool: return bool(net.get("in_match")), 5.0)
	_check(started, "host in_match after request_start()")
	_check(match_started_seen, "host got match_started")


func _step_lobby_client() -> void:
	var err: int = net.call("join", "127.0.0.1", port)
	_check(err == OK, "join(127.0.0.1, %d) returns OK (got %d)" % [port, err])
	if err != OK:
		_finish()
		return
	var up: bool = await _wait_until(func() -> bool: return connected_seen or failed_reason != "", 15.0)
	_check(up and connected_seen, "client got 'connected' (failure reason: '%s')" % failed_reason)
	if not connected_seen:
		return
	_check(net.call("is_online"), "client is_online()")
	_check(not net.call("is_host"), "client is not host")
	var my_id: int = int(net.call("my_id"))
	_check(my_id > 1, "client my_id() is not 1 (got %d)" % my_id)

	var mirrored: bool = await _wait_until(func() -> bool: return _players().size() == 2, 5.0)
	_check(mirrored, "client mirrors 2 players (got %d)" % _players().size())
	_check(_players().has(1), "mirrored players include host id 1")
	_check(_players().has(my_id), "mirrored players include the client's own id")
	_check(str(_players().get(1, {}).get("name", "")) == HOST_NAME, "host name arrived at client (got '%s')" % str(_players().get(1, {}).get("name", "")))

	# Let the host record the default crews before we change ours.
	await _wait_seconds(0.5)
	net.call("request_crew", CLIENT_CREW)
	var switched: bool = await _wait_until(func() -> bool: return str(_players().get(my_id, {}).get("crew", "")) == CLIENT_CREW, 5.0)
	_check(switched, "client mirror shows own crew %s (got '%s')" % [CLIENT_CREW, str(_players().get(my_id, {}).get("crew", ""))])

	_check(_send_chat("chat from client"), "client can send chat (net.send_chat exists)")
	var got: bool = await _wait_until(func() -> bool: return _got_chat("chat from host", 1), 10.0)
	_check(got, "client received the host's chat on 'all'")

	var started: bool = await _wait_until(func() -> bool: return match_started_seen, 20.0)
	_check(started, "client got match_started")
	_check(bool(net.get("in_match")), "client in_match after match_started")


# ---------------------------------------------------------------- step: disconnect (always last)

func _step_disconnect_host() -> void:
	var gone: bool = await _wait_until(func() -> bool: return not left_ids.is_empty(), 10.0)
	_check(gone, "host saw the client leave (peer_left)")
	net.call("leave")
	_check(not bool(net.call("is_online")), "host is offline after leave()")


func _step_disconnect_client() -> void:
	# Give the host a moment to finish its own checks before we drop.
	await _wait_seconds(1.0)
	net.call("leave")
	_check(not bool(net.call("is_online")), "client is offline after leave()")
	await _frames(3)


# ---------------------------------------------------------------- step: round (lobby must have run first)
# Both processes run the same sequence and meet at `_sync` barriers (a chat "sync <tag>" each way).
# The seller crew is the first crew in Factions.ORDER that has a player, the buyer the next one.
# Everything is driven through the public game / online API; nothing here edits production code.

var _seller_id: int = 0
var _buyer_id: int = 0
var _seller_crew: String = ""
var _buyer_crew: String = ""


func _online() -> Variant:
	return game.get("online")


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _item(item: int) -> Dictionary:
	return _online().items.get(item, {})


func _item_holder(item: int) -> int:
	return int(_item(item).get("holder", 0))


func _my_id() -> int:
	return int(net.call("my_id"))


func _crew_spawn(crew_id: String) -> Vector3:
	return (game.world.crew_spawns.get(crew_id, {}) as Dictionary).get("spawn", Vector3.ZERO)


## Says something on "all", keeping under the host's 3-chats-a-second limit.
func _say(text: String) -> void:
	var wait_ms: int = _last_chat_ms + 450 - Time.get_ticks_msec()
	if wait_ms > 0:
		await _wait_seconds(wait_ms / 1000.0)
	_send_chat(text)


## Barrier: tell the peer we reached `tag` and wait until it says the same. Only failures are logged.
func _sync(tag: String, timeout: float = 20.0) -> bool:
	await _say("sync " + tag)
	var ok: bool = await _wait_until(func() -> bool: return _got_chat("sync " + tag, _other_id()), timeout)
	if not ok:
		_check(false, "peer reached barrier '%s' within %d s" % [tag, int(timeout)])
	return ok


func _find_chat(prefix: String) -> String:
	for entry: Dictionary in chats:
		if int(entry["from"]) == _other_id() and str(entry["text"]).begins_with(prefix):
			return str(entry["text"])
	return ""


func _chat_from_other(prefix: String, timeout: float) -> String:
	await _wait_until(func() -> bool: return _find_chat(prefix) != "", timeout)
	return _find_chat(prefix)


func _teleport(pos: Vector3) -> void:
	game.player.global_position = pos
	game.player.velocity = Vector3.ZERO
	# Let a few snapshots reach the host: it validates pickups and seats against the last one it saw.
	await _wait_seconds(0.6)


func _step_round() -> void:
	if not await _round_begin():
		return
	await _round_remotes()
	await _round_ledger()
	await _round_seats()
	await _round_damage()
	await _round_cash_and_settle()


func _round_begin() -> bool:
	var online: Variant = _online()
	_check(online != null and bool(online.active), "online round is active after match_started")
	if online == null or not bool(online.active):
		return false
	var buy: bool = await _wait_until(func() -> bool: return str(online.phase) == "buy", 15.0)
	_check(buy, "round_state phase 'buy' arrived (got '%s')" % str(online.phase))
	_check(game.phase == game.Phase.BUY, "game.phase is BUY")
	var range_closed: bool = game.world.mode == "online" and not game.armory.is_open()
	for index: int in game.world.gun_doors:
		range_closed = range_closed and game.world.is_door_locked(index) and not bool(game.world.interactable_doors[index]["open"])
	for target: StaticBody3D in game.armory.targets:
		range_closed = range_closed and not bool(target.get("active")) and target.collision_layer == 0
	_check(range_closed, "The online round hides practice targets and locks the range on this peer")

	var crews: Array[String] = []
	for crew_id: String in Factions.ORDER:
		for id: Variant in _players().keys():
			if str((_players()[id] as Dictionary).get("crew", "")) == crew_id and not crews.has(crew_id):
				crews.append(crew_id)
	_check(crews.size() == 2, "two distinct crews in the match (got %s)" % str(crews))
	if crews.size() < 2:
		return false
	_seller_crew = crews[0]
	_buyer_crew = crews[1]
	_check(str(online.seller) == _seller_crew, "seller is the first crew in Factions.ORDER (%s, got '%s')" % [_seller_crew, str(online.seller)])
	_check(str(online.buyer) == _buyer_crew, "buyer is the next crew (%s, got '%s')" % [_buyer_crew, str(online.buyer)])
	_seller_id = int(net.call("members_of", _seller_crew)[0])
	_buyer_id = int(net.call("members_of", _buyer_crew)[0])
	_check(int(online.round_number) == 1, "round number is 1 (got %d)" % int(online.round_number))

	var items_ok: bool = await _wait_until(func() -> bool: return online.items.has(0) and online.items.has(1), 5.0)
	_check(items_ok, "items 0 (Ledger) and 1 (cash) exist")
	_check(_item_holder(0) == 0 and _item_holder(1) == 0, "both items start on the ground (holder 0)")
	if items_ok:
		_check(_flat(_item(0).get("pos", Vector3.INF), _crew_spawn(_seller_crew)) < 3.0, "Ledger starts at the seller HQ doorstep")
		_check(_flat(_item(1).get("pos", Vector3.INF), _crew_spawn(_buyer_crew)) < 3.0, "cash case starts at the buyer HQ doorstep")

	# Skip the 30 s buy wait: the host jumps to the live phase, the client follows its broadcast.
	if role == "host":
		online.call("_host_set_phase", "live", 600.0)
	var live: bool = await _wait_until(func() -> bool: return str(online.phase) == "live" and game.phase == game.Phase.LIVE, 8.0)
	_check(live, "phase is live and game.phase is LIVE (online '%s')" % str(online.phase))
	_check(not bool(game.armory.targets[0].get("active")), "Going live cannot reactivate the practice range")
	await _sync("live")
	return live


func _round_remotes() -> void:
	var online: Variant = _online()
	var other: int = _other_id()
	_check(online.remotes.size() == 1, "exactly one FastRemote (got %d)" % online.remotes.size())
	_check(online.remotes.has(other), "remote avatar exists for the other peer (%d)" % other)
	var mine: Vector3 = game.player.global_position
	await _say("pos %.2f %.2f" % [mine.x, mine.z])
	var text: String = await _chat_from_other("pos ", 10.0)
	_check(text != "", "received the other player's position by chat")
	if text == "" or not online.remotes.has(other):
		return
	var parts: PackedStringArray = text.split(" ")
	var theirs: Vector3 = Vector3(float(parts[1]), 0.0, float(parts[2]))
	var near: bool = await _wait_until(func() -> bool: return _flat((online.remotes[other] as Node3D).global_position, theirs) < 1.5, 3.0)
	_check(near, "remote avatar is within 1.5 m of the other player (%.2f m)" % _flat((online.remotes[other] as Node3D).global_position, theirs))
	await _sync("remotes")


func _round_ledger() -> void:
	var online: Variant = _online()
	var me: int = _my_id()
	var i_sell: bool = me == _seller_id
	var i_buy: bool = me == _buyer_id
	# 1. The seller walks onto the Ledger and picks it up.
	if i_sell:
		await _teleport(_item(0).get("pos", Vector3.ZERO))
		_check(bool(online.interact()), "seller interact() handled the pickup")
	var picked: bool = await _wait_until(func() -> bool: return _item_holder(0) == _seller_id, 5.0)
	_check(picked, "Ledger holder is the seller (%d), saw %d" % [_seller_id, _item_holder(0)])
	await _sync("ledger_picked")
	# 2. The seller drops it again.
	if i_sell:
		_check(bool(online.drop()), "seller drop() handled")
	var dropped: bool = await _wait_until(func() -> bool: return _item_holder(0) == 0 and str(_item(0).get("banked", "")) == "", 5.0)
	_check(dropped, "Ledger is on the ground again after the drop")
	await _sync("ledger_dropped")
	# 3. The buyer picks it up from where it lies.
	if i_buy:
		await _teleport(_item(0).get("pos", Vector3.ZERO))
		_check(bool(online.interact()), "buyer interact() handled the pickup")
	var taken: bool = await _wait_until(func() -> bool: return _item_holder(0) == _buyer_id, 5.0)
	_check(taken, "Ledger holder is the buyer (%d), saw %d" % [_buyer_id, _item_holder(0)])
	await _sync("ledger_taken")
	# 4. The buyer carries it home and banks it: +$9,000 to the buyer crew.
	var cash_before: int = int(game.cash)
	if i_buy:
		await _teleport(game.hq_spawn)
		_check(_flat(game.player.global_position, game.HOME) < 5.5, "buyer's HQ spawn is inside the 5.5 m bank radius")
		_check(bool(online.interact()), "buyer interact() handled the bank request")
	var banked: bool = await _wait_until(func() -> bool: return str(_item(0).get("banked", "")) == _buyer_crew, 5.0)
	_check(banked, "Ledger banked by the buyer crew '%s' (saw '%s')" % [_buyer_crew, str(_item(0).get("banked", ""))])
	var bank_ok: bool = await _wait_until(func() -> bool: return int(online.bank.get(_buyer_crew, 0)) == 9000, 3.0)
	_check(bank_ok, "round bank shows $9000 for the buyer crew (got %d)" % int(online.bank.get(_buyer_crew, 0)))
	if i_buy:
		var paid: bool = await _wait_until(func() -> bool: return int(game.cash) == cash_before + 9000, 5.0)
		_check(paid, "buyer's cash rose by 9000 (%d -> %d)" % [cash_before, int(game.cash)])
	else:
		await _wait_seconds(0.5)
		_check(int(game.cash) == cash_before, "the seller's cash did not change (%d -> %d)" % [cash_before, int(game.cash)])
	await _sync("ledger_banked")


func _round_seats() -> void:
	var online: Variant = _online()
	var ride: Node3D = game.cars[0]
	var start: Vector3 = ride.global_position
	# A parked car must have settled on the road on both sides (a puppet that coasted on a mid-fall snapshot ends up underground).
	_check(start.y > -0.1 and start.y < 0.3, "car 0 rests on the road on this side (y = %.3f, vel.y %.2f, puppet %s)" % [start.y, float(ride.get("velocity").y), str(ride.get("net_puppet"))])
	var client_id: int = _my_id() if role == "client" else _other_id()
	var driver: bool = role == "client"
	if driver:
		await _teleport(ride.call("door_position", 0))
		game._enter_vehicle(ride, 0)
		var seated: bool = await _wait_until(func() -> bool: return game.vehicle == ride and game.seat == 0, 5.0)
		_check(seated, "client is in the driver seat after the host grant")
		_check(int(net.call("seat_holder", 0, 0)) == client_id, "client's mirror lists it as the driver of car 0")
	else:
		var granted: bool = await _wait_until(func() -> bool: return int(net.call("seat_holder", 0, 0)) == client_id, 5.0)
		_check(granted, "host granted car 0 seat 0 to the client")
		_check(bool(ride.get("net_puppet")), "host's copy of the car is a puppet while the client drives")
		var remote_seated: bool = await _wait_until(func() -> bool: return online.remotes.has(client_id) and bool(online.remotes[client_id].is_seated()), 3.0)
		_check(remote_seated, "the client's FastRemote on the host is seated")
	await _sync("seated")
	if driver:
		Input.action_press("move_forward")
		await _wait_seconds(2.0)
		Input.action_release("move_forward")
		_check(ride.global_position.distance_to(start) > 3.0, "client's own car moved > 3 m (%.1f m)" % ride.global_position.distance_to(start))
	else:
		var moved: bool = await _wait_until(func() -> bool: return ride.global_position.distance_to(start) > 3.0, 8.0)
		_check(moved, "host's copy of the car moved > 3 m (%.1f m)" % ride.global_position.distance_to(start))
		if online.remotes.has(client_id):
			var rider_gap: float = (online.remotes[client_id] as Node3D).global_position.distance_to(ride.global_position)
			_check(rider_gap < 6.0, "client's remote avatar travels with the car (%.1f m away)" % rider_gap)
	await _sync("drove")
	# Get out again: the seat frees on both sides and the host takes the car back.
	if driver:
		game._exit_vehicle(true)
		_check(game.vehicle == null, "client left the car")
	var freed: bool = await _wait_until(func() -> bool: return int(net.call("seat_holder", 0, 0)) == 0, 5.0)
	_check(freed, "seat 0 of car 0 is empty on both sides again")
	if not driver:
		var released: bool = await _wait_until(func() -> bool: return not bool(ride.get("net_puppet")), 3.0)
		_check(released, "host's car is no longer a puppet once the seat is empty")
	await _sync("seat_done")


func _round_damage() -> void:
	var online: Variant = _online()
	var client_id: int = _my_id() if role == "client" else _other_id()
	var hp_before: float = 0.0
	var expected_loss: float = 0.0
	if role == "client":
		# Arrange a known state: driving into a wall costs the driver 15-45 health per crash, which would
		# otherwise make the expected loss depend on the drive.
		game.player.health = 100.0
		game.player.armor = 0.0
		await _wait_seconds(0.6)
		hp_before = game.player.health
		expected_loss = 30.0 - minf(game.player.armor, 30.0 * 0.65)
	await _sync("dmg_ready")
	if role == "host":
		var remote: Node3D = online.remotes.get(client_id)
		_check(remote != null, "host has the client's remote to aim at")
		if remote != null:
			var origin: Vector3 = game.player.global_position + Vector3(0, 1.6, 0)
			net.call("send_claim_hit", client_id, 30.0, false, origin, remote.global_position + Vector3(0, 1.0, 0), "pistol")
	else:
		var hurt: bool = await _wait_until(func() -> bool: return game.player.health < hp_before, 5.0)
		_check(hurt, "client took damage from the host's validated claim (health %.1f -> %.1f)" % [hp_before, game.player.health])
		_check(absf((hp_before - game.player.health) - expected_loss) < 0.6, "damage 30 through armor: expected -%.1f health, got -%.1f" % [expected_loss, hp_before - game.player.health])
	await _sync("dmg_one")
	# A lethal claim: the client dies, drops nothing (it carries nothing) and respawns at its HQ after ~10 s.
	if role == "host":
		var remote: Node3D = online.remotes.get(client_id)
		var tries: int = 0
		while remote != null and tries < 30 and not bool(net.call("is_dead", client_id)):
			tries += 1
			var origin: Vector3 = game.player.global_position + Vector3(0, 1.6, 0)
			net.call("send_claim_hit", client_id, 250.0, false, origin, remote.global_position + Vector3(0, 1.0, 0), "pistol")
			await _wait_seconds(0.15)
		_check(bool(net.call("is_dead", client_id)), "host sees the client dead after a lethal claim (%d claims)" % tries)
		var seen: bool = await _wait_until(func() -> bool: return _died(client_id) != {}, 3.0)
		_check(seen and int(_died(client_id).get("killer", -1)) == 1, "host got player_died for the client with the host as killer")
		var back: bool = await _wait_until(func() -> bool: return not bool(net.call("is_dead", client_id)), 15.0)
		_check(back, "host sees the client alive again after the respawn timer")
		if back:
			var spawn: Vector3 = _crew_spawn(str(_players().get(client_id, {}).get("crew", "")))
			var gap: float = _flat(net.call("latest_pos", client_id), spawn)
			_check(gap < 3.0, "client respawned at its HQ spawn as the host sees it (%.1f m off)" % gap)
	else:
		var dead: bool = await _wait_until(func() -> bool: return game.player.is_dead(), 5.0)
		_check(dead, "client died from the lethal claim")
		var seen: bool = await _wait_until(func() -> bool: return _died(_my_id()) != {}, 3.0)
		_check(seen and int(_died(_my_id()).get("killer", -1)) == 1, "client got player_died for itself with the host as killer")
		var alive: bool = await _wait_until(func() -> bool: return not game.player.is_dead(), 14.0)
		_check(alive, "client respawned (is_dead() false again)")
		if alive:
			await _wait_seconds(0.3)
			_check(_flat(game.player.global_position, game.hq_spawn) < 3.0, "client is back at its HQ spawn (%.1f m off)" % _flat(game.player.global_position, game.hq_spawn))
			_check(game.player.health >= 99.0, "client respawned with full health (%.1f)" % game.player.health)
	await _sync("respawned")


func _died(id: int) -> Dictionary:
	for entry: Dictionary in died_log:
		if int(entry["id"]) == id:
			return entry
	return {}


func _round_cash_and_settle() -> void:
	var online: Variant = _online()
	var me: int = _my_id()
	var i_sell: bool = me == _seller_id
	var cash_before: int = int(game.cash)
	# The seller takes the buyer's cash case home: a non-buyer crew banking it earns $6,000.
	if i_sell:
		await _teleport(_item(1).get("pos", Vector3.ZERO))
		_check(bool(online.interact()), "seller interact() picked up the cash case")
	var held: bool = await _wait_until(func() -> bool: return _item_holder(1) == _seller_id, 5.0)
	_check(held, "cash case holder is the seller (saw %d)" % _item_holder(1))
	await _sync("cash_held")
	if i_sell:
		await _teleport(game.hq_spawn)
		_check(bool(online.interact()), "seller interact() handled banking the cash case")
	var banked: bool = await _wait_until(func() -> bool: return str(_item(1).get("banked", "")) == _seller_crew, 5.0)
	_check(banked, "cash case banked by the seller crew '%s' (saw '%s')" % [_seller_crew, str(_item(1).get("banked", ""))])
	if i_sell:
		var paid: bool = await _wait_until(func() -> bool: return int(game.cash) == cash_before + 6000, 5.0)
		_check(paid, "seller's cash rose by 6000 (%d -> %d)" % [cash_before, int(game.cash)])
	# Both items banked: the round settles. A kill happened, so there is no clean-deal bonus.
	var settled: bool = await _wait_until(func() -> bool: return str(online.phase) == "settle" and game.phase == game.Phase.RESULT, 8.0)
	_check(settled, "round settled once both items were banked (online '%s')" % str(online.phase))
	var lines: String = "\n".join(PackedStringArray(online.results))
	_check(not online.results.is_empty(), "settle results were broadcast (%d lines)" % online.results.size())
	_check(lines.find("CLEAN DEAL") == -1, "no clean-deal bonus after the host killed the client")
	await _sync("settled")
