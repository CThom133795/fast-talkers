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

	create_timer(WATCHDOG_SECONDS).timeout.connect(func() -> void:
		if finished:
			return
		print("WATCHDOG: net_pair %s did not finish in %d s" % [role, int(WATCHDOG_SECONDS)])
		_check(false, "watchdog: finished within %d s" % int(WATCHDOG_SECONDS))
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
		# Append round steps here, e.g. "round": await _step_round_host() / _step_round_client().
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
