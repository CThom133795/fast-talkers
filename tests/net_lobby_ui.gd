extends SceneTree
## Single-process self-test for scripts/net.gd and scripts/lobby_ui.gd (no second peer needed):
## offline safety, hosting, lobby UI states, chat routing, host-side validation of bad input,
## broadcast helpers and clean UPnP thread shutdown.
## Run: godot --headless --path . --script res://tests/net_lobby_ui.gd

var checks: int = 0
var failures: int = 0
var net: FastNet
var lobby: FastLobby


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _frames(count: int) -> void:
	for index: int in range(count):
		await process_frame


func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("net_lobby_ui did not finish in 60 s")
		quit(2))
	net = FastNet.new()
	net.name = "Net"
	net.use_upnp = false
	root.add_child(net)
	lobby = FastLobby.new()
	lobby.config_path = "user://net_lobby_test.cfg"
	root.add_child(lobby)
	lobby.setup(net)
	await _frames(2)

	# ---- offline
	_check(not net.is_online() and not net.is_host(), "offline: not online, not host")
	_check(net.my_id() == 0, "offline: my_id is 0")
	net.leave()
	net.leave()
	_check(not net.is_online(), "leave() is safe offline (twice)")
	_check(net.join("", 24650) != OK, "join with empty address is rejected")
	_check(net.join("1.2.3.4:notaport") != OK, "join with a bad port is rejected")
	_check(not net.is_online() and not net.is_connecting(), "failed join leaves us offline")
	_check(lobby.get("_connect_box").visible and not lobby.get("_lobby_box").visible, "lobby UI shows the connect screen offline")
	_check((lobby.get("_host_button") as Button).custom_minimum_size.y >= 44.0, "buttons are at least 44 px tall")
	var addresses: PackedStringArray = net.local_addresses()
	_check(addresses is PackedStringArray, "local_addresses returns an array (%d found)" % addresses.size())
	var addresses_clean: bool = true
	for address: String in addresses:
		if address.begins_with("127.") or address.begins_with("169.254."):
			addresses_clean = false
	_check(addresses_clean, "local_addresses has no loopback / link-local entries")

	# ---- host
	var port: int = 20000 + randi() % 20000
	var lobby_events: Array[int] = [0]
	net.lobby_changed.connect(func() -> void: lobby_events[0] += 1)
	net.local_name = "Tester"
	_check(net.host(port) == OK, "host() on port %d returns OK" % port)
	await _frames(2)
	_check(net.is_host() and net.is_online() and net.my_id() == 1, "hosting: is_host, is_online, my_id 1")
	_check(net.players.has(1), "players contains the host (id 1)")
	_check(net.crew_of(1) == FastNet.Factions.ORDER[0], "host got the first crew by default")
	_check(String(net.players[1]["name"]) == "Tester", "host name is stored")
	_check(lobby_events[0] > 0, "lobby_changed fired when hosting")
	_check(lobby.showing_lobby() and lobby.get("_lobby_box").visible, "lobby UI switched to the lobby screen")
	var start: Button = lobby.get("_start_button")
	_check(start.visible and not start.disabled, "START MATCH is visible and enabled for the host")
	_check((lobby.get("_player_list") as Control).get_child_count() == 1, "lobby lists one player")
	_check(net.upnp_status.begins_with("UPnP skipped"), "upnp skipped status when use_upnp is false")
	# Crew picker.
	net.request_crew("kojimoto")
	await _frames(1)
	_check(net.crew_of(1) == "kojimoto", "request_crew applies on the host")
	net.request_crew("nonsense")
	_check(net.crew_of(1) == "kojimoto", "unknown crew is ignored")
	(lobby.get("_crew_buttons")["solnegro"] as Button).pressed.emit()
	await _frames(1)
	_check(net.crew_of(1) == "solnegro", "pressing a crew button changes the crew")
	lobby.open()
	await _frames(3)
	_check(start.has_focus(), "START MATCH takes pad focus when the lobby opens")

	# ---- chat routing and sanitising (host echo)
	var chats: Array = []
	net.chat.connect(func(from_id: int, channel: String, text: String) -> void: chats.append([from_id, channel, text]))
	net.send_chat("all", "  hello [b]world[/b]  ")
	_check(chats.size() == 1 and chats[0][2] == "hello (b)world(/b)", "chat echoes locally with brackets neutralised")
	net.send_chat("crew", "x".repeat(500))
	_check(chats.size() == 2 and String(chats[1][2]).length() == 160, "chat is trimmed to 160 characters")
	net.send_chat("call:kojimoto", "ring")
	_check(chats.size() == 3, "call channel echoes to the sender")
	net.send_chat("nonsense", "nope")
	net.send_chat("call:nobody", "nope")
	_check(chats.size() == 3, "bad chat channels are dropped")
	net.send_chat("all", "\u0007\u0001")
	_check(chats.size() == 3, "control-only chat is dropped")

	# ---- sanitising helpers
	_check(FastNet.clean_name(("  A" + String.chr(1) + "B" + String.chr(0x202E) + "CD [x] ").repeat(3)).length() <= 24, "names are clamped to 24 chars")
	_check(FastNet.clean_name("\u0001\u0002") == "Player", "unprintable name falls back to Player")
	_check(not FastNet.finite_v(Vector3(NAN, 0, 0)) and not FastNet.finite_v(Vector3(INF, 0, 0)) and FastNet.finite_v(Vector3(1, 2, 3)), "finite_v rejects NAN/INF")
	_check(not FastNet.finite_f(NAN) and FastNet.finite_f(12.5), "finite_f rejects NAN")
	_check(not FastNet.finite_t(Transform3D(Basis(), Vector3(NAN, 0, 0))), "finite_t rejects NAN origin")
	_check(FastNet.weapon_ok("") and not FastNet.weapon_ok("nuke") and FastNet.weapon_ok(String(FastPlayer.WEAPONS.keys()[0])), "weapon ids must exist in FastPlayer.WEAPONS or be empty")
	_check(FastNet.channel_ok("all") and FastNet.channel_ok("crew") and FastNet.channel_ok("call:morris") and not FastNet.channel_ok("call:zzz") and not FastNet.channel_ok("x"), "chat channel patterns")

	# ---- host handlers: bad input never reaches game code
	net.max_cars = 10
	net.max_items = 4
	net.players[2] = {"name": "Fake", "crew": "morris", "ready": false, "in_match": false}
	var seats: Array = []
	var items: Array = []
	var dmg: Array = []
	net.host_seat_request.connect(func(f: int, c: int, s: int) -> void: seats.append([f, c, s]))
	net.host_item_request.connect(func(f: int, a: String, i: int, p: Vector3) -> void: items.append([f, a, i, p]))
	net.host_car_damage.connect(func(f: int, c: int, a: float) -> void: dmg.append([f, c, a]))
	net._h_request_seat(2, 3, 1)
	net._h_request_seat(2, 99, 1)
	net._h_request_seat(2, 3, 99)
	net._h_request_seat(77, 3, 1)
	_check(seats.size() == 1, "seat request: only the valid one passes (car/seat range, unknown sender)")
	net._h_item_request(2, "pickup", 1, Vector3(1, 0, 1))
	net._h_item_request(2, "steal", 1, Vector3.ZERO)
	net._h_item_request(2, "pickup", 400, Vector3.ZERO)
	net._h_item_request(2, "pickup", 1, Vector3(NAN, 0, 0))
	_check(items.size() == 1, "item request: only the valid one passes (action, id, NAN)")
	net._h_car_damage(2, 3, 40.0)
	net._h_car_damage(2, 3, NAN)
	net._h_car_damage(2, 3, -5.0)
	net._h_car_damage(2, 50, 5.0)
	net._h_car_damage(2, 3, 99999.0)
	_check(dmg.size() == 2 and is_equal_approx(float(dmg[1][2]), 1000.0), "car damage: NAN/negative/out-of-range dropped, huge clamped to 1000")
	# Only the holder may leave a seat.
	var leaves: Array = []
	net.host_seat_leave.connect(func(f: int, c: int, s: int) -> void: leaves.append([f, c, s]))
	net._h_leave_seat(2, 3, 1)
	_check(leaves.is_empty(), "leave seat by a non-holder is dropped")
	# Driver identity via the seat_owner callable.
	net.seat_owner = func(car: int) -> int: return 2 if car == 3 else 0
	_check(net._driver_ok(2, 3) and not net._driver_ok(1, 3) and not net._driver_ok(4, 3), "only the seat owner may send car state")
	_check(net._driver_ok(1, 5) and not net._driver_ok(2, 5), "host may drive an unoccupied car")
	net.seat_owner = Callable()
	_check(net._driver_ok(9, 3), "no seat_owner callable means allow")

	# ---- hit claim validation
	var hits: Array = []
	var validated: Array = []
	net.damage_received.connect(func(a: float, s: Vector3, at: int) -> void: hits.append([a, s, at]))
	net.hit_validated.connect(func(sh: int, v: int, a: float, h: bool, w: String) -> void: validated.append([sh, v, a]))
	net._latest[1] = {"pos": Vector3(0, 0, 0), "flags": 0}
	net._latest[2] = {"pos": Vector3(0, 0, 10), "flags": 0}
	var origin: Vector3 = Vector3(0, 1.5, 10)
	var point: Vector3 = Vector3(0, 1.0, 0)
	_check(net._h_claim_hit(2, 1, 30.0, false, origin, point, ""), "valid hit claim on the host is accepted")
	_check(hits.size() == 1 and is_equal_approx(float(hits[0][0]), 30.0) and int(hits[0][2]) == 2, "victim receives damage_received with the shooter id")
	_check(not net._h_claim_hit(2, 1, 30.0, false, origin, point, ""), "second claim inside 40 ms is rate limited")
	net._claim_ok[2] = int(net._claim_ok.get(2, 0)) - 100
	_check(net._h_claim_hit(2, 1, 9999.0, true, origin, point, ""), "claim accepted again after 40 ms")
	_check(is_equal_approx(float(validated[1][2]), 250.0), "damage is clamped to 250")
	net._claim_ok[2] = int(net._claim_ok.get(2, 0)) - 100
	_check(not net._h_claim_hit(2, 1, 30.0, false, Vector3(0, 1, 400), point, ""), "claim beyond 320 m is rejected")
	net._claim_ok[2] = int(net._claim_ok.get(2, 0)) - 100
	_check(not net._h_claim_hit(2, 1, 30.0, false, origin, Vector3(0, 1, 8), ""), "claim point far from the victim's position is rejected")
	_check(not net._h_claim_hit(2, 2, 30.0, false, origin, point, ""), "cannot claim a hit on yourself")
	_check(not net._h_claim_hit(2, 1, NAN, false, origin, point, ""), "NAN damage rejected")
	_check(not net._h_claim_hit(2, 1, 30.0, false, origin, Vector3(NAN, 0, 0), ""), "NAN point rejected")
	_check(not net._h_claim_hit(2, 1, 30.0, false, origin, point, "nuke"), "unknown weapon id rejected")
	_check(not net._h_claim_hit(2, 42, 30.0, false, origin, point, ""), "unknown victim rejected")
	net._latest[1]["flags"] = 4
	_check(not net._h_claim_hit(2, 1, 30.0, false, origin, point, ""), "dead victim rejected")
	net._latest[1]["flags"] = 0
	net.accept_hits = false
	net._claim_ok[2] = int(net._claim_ok.get(2, 0)) - 100
	_check(not net._h_claim_hit(2, 1, 30.0, false, origin, point, ""), "hits ignored while accept_hits is off")
	net.accept_hits = true
	_check(hits.size() == 2, "no damage leaked through the rejected claims")

	# ---- death report and broadcasts (host, no clients)
	var deaths: Array = []
	net.player_died.connect(func(i: int, k: int, p: Vector3) -> void: deaths.append([i, k, p]))
	net._h_report_death(1, 2, Vector3(1, 0, 1))
	net._h_report_death(1, 2, Vector3(1, 0, 1))
	_check(deaths.size() == 1 and int(deaths[0][0]) == 1 and int(deaths[0][1]) == 2, "death report broadcasts once (duplicate ignored)")
	net._h_report_death(1, 2, Vector3(NAN, 0, 0))
	_check(deaths.size() == 1, "NAN death position rejected")
	var seat_events: Array = []
	var health_events: Array = []
	var item_events: Array = []
	var round_events: Array = []
	var grants: Array = []
	net.seat_update.connect(func(c: int, s: int, p: int) -> void: seat_events.append([c, s, p]))
	net.car_health.connect(func(c: int, h: float, d: bool) -> void: health_events.append([c, h, d]))
	net.item_update.connect(func(i: int, d: Dictionary) -> void: item_events.append([i, d]))
	net.round_state.connect(func(d: Dictionary) -> void: round_events.append(d))
	net.grant.connect(func(a: int, r: String) -> void: grants.append([a, r]))
	net.broadcast_seat(3, 1, 1)
	net.broadcast_car_health(3, 55.0, false)
	net.broadcast_item(1, {"holder": 1})
	net.broadcast_round({"phase": "street"})
	net.grant_to(1, 500, "test [x]")
	_check(seat_events.size() == 1 and net.seat_holder(3, 1) == 1, "broadcast_seat reaches the host and is tracked")
	_check(health_events.size() == 1 and item_events.size() == 1 and round_events.size() == 1, "broadcast car health / item / round reach the host")
	_check(grants.size() == 1 and int(grants[0][0]) == 500 and grants[0][1] == "test (x)", "grant_to the host emits grant")
	net._h_leave_seat(1, 3, 1)
	_check(leaves.size() == 1 and int(leaves[0][0]) == 1, "the seat holder may leave its seat")
	net.broadcast_seat(3, 1, 0)
	_check(net.seat_holder(3, 1) == 0, "seat freed on peer 0")
	net.send_state(Vector3(5, 0, 5), 0.5, 0.1, 0, "", -1, -1, 100.0)
	_check(net.has_latest(1) and net.latest_pos(1).is_equal_approx(Vector3(5, 0, 5)), "send_state records our own latest position")

	# ---- rate limiter
	var passes: int = 0
	for index: int in range(8):
		if net._rate_ok(2, "chat", 3):
			passes += 1
	_check(passes == 3, "rate limiter lets 3 chat messages per second through (got %d)" % passes)
	var faux: FastNet = net
	faux._rl.clear()
	var kicked: bool = false
	# Simulate two consecutive windows at more than 5x the limit.
	for window: int in range(3):
		for index: int in range(20):
			faux._rate_ok(2, "chat", 3)
		var per: Dictionary = faux._rl.get(2, {})
		if per.has("chat"):
			(per["chat"] as Array)[0] = int((per["chat"] as Array)[0]) - 1100
	kicked = faux.last_kick.begins_with("peer 2")
	_check(kicked, "a peer at over 5x the limit for 2 s is kicked (%s)" % faux.last_kick)

	# ---- match start
	var started: Array[int] = [0]
	net.match_started.connect(func() -> void: started[0] += 1)
	net.players.erase(2)
	net.request_start()
	await _frames(1)
	_check(net.in_match and started[0] == 1, "request_start sets in_match and emits match_started once")
	net.request_start()
	_check(started[0] == 1, "request_start twice does not re-emit")
	net.request_crew("morris")
	_check(net.crew_of(1) == "solnegro", "crew changes are ignored during a match")
	net.end_match()
	_check(not net.in_match, "end_match returns to the lobby")

	# ---- leave restores offline
	net.leave()
	await _frames(2)
	_check(not net.is_online() and not net.is_host() and net.players.is_empty() and not net.in_match, "leave() restores the offline state")
	_check(lobby.get("_connect_box").visible and not lobby.get("_lobby_box").visible, "lobby UI returned to the connect screen")
	lobby.open()
	await _frames(3)
	_check((lobby.get("_host_button") as Button).has_focus(), "HOST GAME takes pad focus on the connect screen")
	var backs: Array[int] = [0]
	lobby.back_requested.connect(func() -> void: backs[0] += 1)
	(lobby.get("_back_button") as Button).pressed.emit()
	_check(backs[0] == 1, "BACK emits back_requested")
	_check(net.host(port) == OK, "host() works again after leave()")
	net.leave()

	# ---- persistence
	(lobby.get("_name_edit") as LineEdit).text = "Saved Name"
	(lobby.get("_address_edit") as LineEdit).text = "10.0.0.7"
	lobby.call("_save_config")
	var cfg := ConfigFile.new()
	_check(cfg.load("user://net_lobby_test.cfg") == OK and cfg.get_value("net", "name", "") == "Saved Name" and cfg.get_value("net", "address", "") == "10.0.0.7", "name and address are saved to the config file")

	# ---- UPnP with the real thread (skipped if the router probe is slow)
	var net2: FastNet = FastNet.new()
	net2.name = "Net2"
	net2.use_upnp = true
	root.add_child(net2)
	var upnp_seen: Array[String] = []
	net2.upnp_done.connect(func(status: String) -> void: upnp_seen.append(status))
	var port2: int = port + 1
	_check(net2.host(port2) == OK, "second FastNet hosts with UPnP enabled")
	_check(net2.upnp_status.begins_with("Opening port"), "upnp status shows progress while probing")
	var started_ms: int = Time.get_ticks_msec()
	while upnp_seen.is_empty() and Time.get_ticks_msec() - started_ms < 5000:
		await process_frame
	if upnp_seen.is_empty():
		print("SKIP: UPnP probe took longer than 5 s; testing shutdown while it runs")
	else:
		print("UPnP status: ", net2.upnp_status)
		_check(net2.upnp_status.begins_with("Port ") or net2.upnp_status.begins_with("Could not open port"), "UPnP finished with a human status line")
	var before: int = Time.get_ticks_msec()
	net2.leave()
	_check(Time.get_ticks_msec() - before < 1000, "leave() with UPnP does not block the main thread for 1 s")
	await _frames(2)
	net2.queue_free()
	await _frames(3)
	_check(not is_instance_valid(net2), "FastNet with UPnP threads frees cleanly (threads joined in _exit_tree)")

	print("NET LOBBY UI RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
