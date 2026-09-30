extends SceneTree
## Headless self-test for scripts/net_security.gd and the host-side hardening in scripts/net.gd:
## handshake / version check, pre-handshake gating, spoofing, NaN and oversized input, rate limits,
## strikes and kicks, movement bounds, hit-claim checks, and the optional Steam layer reporting
## "unavailable" cleanly while ENet keeps working.
## Run: godot --headless --path . --script res://tests/net_security.gd

const Sec = preload("res://scripts/net_security.gd")
const SteamTransportScript = preload("res://scripts/steam_transport.gd")
const PORT: int = 24690

var checks: int = 0
var failures: int = 0
var net: FastNet


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("net_security did not finish in 60 s")
		quit(2))
	_pure_helpers()
	net = FastNet.new()
	net.name = "Net"
	net.use_upnp = false
	root.add_child(net)
	_steam_absent()
	_check(net.host(PORT) == OK, "ENet host starts (default transport)")
	_check(net.transport == "enet" and net.is_host(), "transport is enet after host()")
	var scene_mp: SceneMultiplayer = net.multiplayer as SceneMultiplayer
	_check(scene_mp != null and not scene_mp.server_relay and not scene_mp.allow_object_decoding, "server relay and object decoding are off")
	_handshake()
	_gating_and_spoofing()
	_movement()
	_hits()
	_budget_and_kicks()
	net.leave()
	_check(not net.is_online() and net.transport == "enet", "leave() resets to offline ENet")
	await _end_to_end()
	print("NET SECURITY RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _pure_helpers() -> void:
	# Text
	_check(Sec.clean_text("[b]hi[/b]" + String.chr(7) + String.chr(0x202E) + "x", 40) == "(b)hi(/b)x", "clean_text strips control/bidi chars and neutralises BBCode brackets")
	var huge: String = "A".repeat(1000000)
	var started: int = Time.get_ticks_msec()
	var clipped: String = Sec.clean_text(huge, 160)
	_check(clipped.length() == 160 and Time.get_ticks_msec() - started < 500, "1 MB string is clipped fast (%d ms)" % (Time.get_ticks_msec() - started))
	_check(FastNet.clean_name("\u0001") == "Player", "empty name falls back to Player")
	_check(not Sec.string_ok("x".repeat(600)) and Sec.string_ok("ok"), "oversized wire strings rejected")
	# Version
	_check(Sec.check_version(Sec.build_tag(), Sec.build_tag()).is_empty(), "same build tag accepted")
	_check(not Sec.check_version("1|0.1", Sec.build_tag()).is_empty(), "different build tag refused")
	_check(not Sec.check_version("x".repeat(200), Sec.build_tag()).is_empty(), "oversized build tag refused")
	_check(Sec.build_tag().begins_with("%d|" % Sec.PROTOCOL), "build tag carries the protocol number")
	# Numbers and vectors
	_check(not Sec.finite_v(Vector3(NAN, 0, 0), 1e5) and not Sec.finite_v(Vector3(0, INF, 0), 1e5) and Sec.finite_v(Vector3(1, 2, 3), 1e5), "finite_v rejects NaN/INF")
	_check(not Sec.finite_f(-INF, 10.0) and not Sec.finite_f(11.0, 10.0) and Sec.finite_f(-9.0, 10.0), "finite_f rejects INF and out-of-range")
	_check(Sec.int_in(3, 0, 5) and not Sec.int_in(-1, 0, 5) and not Sec.int_in(6, 0, 5), "int_in bounds")
	_check(Sec.in_map(Vector3(100, 5, -300)) and not Sec.in_map(Vector3(1e6, 0, 0)) and not Sec.in_map(Vector3(0, -5000, 0)) and not Sec.in_map(Vector3(NAN, 0, 0)), "in_map bounds")
	_check(Sec.step_ok(Vector3.ZERO, Vector3(5, 0, 0), 0.05) and not Sec.step_ok(Vector3.ZERO, Vector3(500, 0, 0), 0.05), "step_ok caps speed per snapshot")
	_check(not Sec.step_ok(Vector3.ZERO, Vector3(900, 0, 0), 100.0), "step_ok clamps huge time gaps")
	# Weapons
	var pistol: Dictionary = FastPlayer.WEAPONS["pistol"]
	var cap: float = Sec.max_claim_damage("pistol", FastPlayer.WEAPONS, 250.0)
	_check(cap >= float(pistol["damage"]) * 2.0 and cap <= 250.0, "pistol claim cap is headshot-sized (%.0f)" % cap)
	_check(Sec.max_claim_damage("", FastPlayer.WEAPONS, 250.0) == 250.0, "weapon '' (car hit) uses the fallback cap")
	_check(Sec.weapon_range("pistol", FastPlayer.WEAPONS, 320.0) <= 320.0 and Sec.weapon_range("pistol", FastPlayer.WEAPONS, 320.0) >= 60.0, "weapon range bounded")
	# Dictionaries
	var big: Dictionary = {}
	for index: int in range(80):
		big["k%d" % index] = index
	_check(not Sec.dict_ok(big) and Sec.dict_ok({"phase": "live"}) and not Sec.dict_ok({Vector3.ZERO: 1}), "dict_ok size and key-type caps")
	# Token bucket
	var bucket: Sec.TokenBucket = Sec.TokenBucket.new(3.0, 2.0)
	var passed: int = 0
	for index: int in range(10):
		if bucket.take(1000):
			passed += 1
	_check(passed == 3, "token bucket allows its burst of 3 (got %d)" % passed)
	_check(not bucket.take(1100) and bucket.take(1600), "token bucket refills at 2/s")
	# Strikes
	var strikes: Sec.Strikes = Sec.Strikes.new(3, 1000)
	_check(not strikes.add(5, 0) and not strikes.add(5, 10), "two strikes are below the limit")
	_check(strikes.add(5, 20), "third strike reaches the limit")
	strikes.clear(5)
	strikes.add(5, 0)
	strikes.add(5, 0)
	_check(not strikes.add(5, 2500), "strikes decay over time")
	# Steam lobby filter
	_check(SteamTransportScript.check_lobby_data("fast_talkers", "b1", "b1").is_empty(), "own Steam lobby with same build accepted")
	_check(not SteamTransportScript.check_lobby_data("spacewar", "b1", "b1").is_empty(), "other Spacewar lobbies filtered out")
	_check(not SteamTransportScript.check_lobby_data("fast_talkers", "b0", "b1").is_empty(), "Steam lobby from a different build refused")


func _steam_absent() -> void:
	var present: bool = SteamTransportScript.extension_present()
	if present:
		print("NOTE: GodotSteam is installed here; skipping the 'Steam absent' checks")
		return
	_check(net.steam_unavailable_reason() == "Steam add-on not installed", "Steam reports 'add-on not installed' cleanly")
	_check(not net.steam_available(), "steam_available() is false")
	_check(net.host_steam() == ERR_UNAVAILABLE and not net.is_online() and net.transport == "enet", "host_steam() returns ERR_UNAVAILABLE and changes nothing")
	_check(net.join_steam(109775240000000000) == ERR_UNAVAILABLE and not net.is_connecting(), "join_steam() returns ERR_UNAVAILABLE")
	_check(net.join_steam(0) == ERR_INVALID_PARAMETER, "join_steam(0) rejected")
	net.steam_autostart()
	_check(net.steam_status == "Steam add-on not installed" and not net.is_online(), "steam_autostart() is a clean no-op")
	var lobby: FastLobby = FastLobby.new()
	lobby.config_path = "user://net_security_lobby.cfg"
	root.add_child(lobby)
	lobby.setup(net)
	lobby.open()
	var steam_button: Button = lobby.get("_steam_host_button")
	var note: Label = lobby.get("_steam_note")
	_check(steam_button != null and not steam_button.visible, "HOST ON STEAM button hidden without Steam")
	_check(note != null and note.visible and note.text.contains("Steam add-on not installed"), "one plain line says why (%s)" % (note.text if note != null else "?"))
	_check((lobby.get("_host_button") as Button).visible, "ENet HOST GAME still offered")
	lobby.queue_free()


func _handshake() -> void:
	var joins: Array = []
	net.peer_joined.connect(func(id: int) -> void: joins.append(id))
	net.players[5] = net._new_entry("Player 5")
	net._hello_deadline[5] = Time.get_ticks_msec() + FastNet.HELLO_TIMEOUT_MS
	_check(not net._joined(5), "peer without a handshake cannot send game messages")
	var refused: String = net._h_hello(5, "Mallory", "0|old-build")
	_check(not refused.is_empty() and refused.contains("version mismatch"), "mismatched build refused at the handshake (%s)" % refused)
	_check(not net._hello_done.has(5) and joins.is_empty(), "refused peer never joins")
	_check(not net._h_hello(5, "Mallory", net.build_tag).is_empty(), "a refused peer cannot retry on the same connection")
	net.players[6] = net._new_entry("Player 6")
	_check(net._h_hello(6, "Bob[color=red]", net.build_tag).is_empty(), "matching build accepted")
	_check(net._hello_done.has(6) and joins == [6] and net.name_of(6) == "Bob(color=red)", "joined with a sanitised name")
	_check(not net._h_hello(6, "Bob again", net.build_tag).is_empty(), "second hello ignored")
	# Timeout
	net.players[7] = net._new_entry("Player 7")
	net._hello_deadline[7] = Time.get_ticks_msec() - 1
	net._check_hello_timeouts()
	_check(net.last_kick.begins_with("peer 7") and net.last_kick.contains("no handshake"), "silent peer dropped after the hello timeout (%s)" % net.last_kick)
	net._hello_deadline[5] = Time.get_ticks_msec() - 1
	net._check_hello_timeouts()
	_check(net.last_kick.begins_with("peer 5") and net.last_kick.contains("version"), "refused peer dropped after its notice (%s)" % net.last_kick)
	net.players.erase(5)
	net.players.erase(7)


func _gating_and_spoofing() -> void:
	_check(net._joined(6) and net._joined(1), "joined peer and host pass the gate")
	_check(not net._joined(42), "unknown peer id blocked")
	# Spoofed seat release: peer 6 tries to free a seat peer 1 holds.
	net.max_cars = 10
	net.broadcast_seat(3, 0, 1)
	var leaves: Array = []
	net.host_seat_leave.connect(func(f: int, c: int, s: int) -> void: leaves.append([f, c, s]))
	var before: int = net._strikes.count(6)
	net._h_leave_seat(6, 3, 0)
	_check(leaves.is_empty() and net._strikes.count(6) == before + 1, "cannot free someone else's seat (and earns a strike)")
	# Driver check: only the seat-0 holder may send car state.
	net.seat_owner = func(car: int) -> int: return net.seat_holder(car, 0)
	_check(not net._driver_ok(6, 3) and net._driver_ok(1, 3), "only the driver may send a car's state")
	# Snapshot field checks
	_check(net._check_state(6, Vector3(NAN, 0, 0), 0, 0, 0, "", -1, -1, 100.0).is_empty(), "NaN position snapshot rejected")
	_check(net._check_state(6, Vector3.ZERO, INF, 0, 0, "", -1, -1, 100.0).is_empty(), "INF yaw snapshot rejected")
	_check(net._check_state(6, Vector3.ZERO, 0, 0, 0, "railgun", -1, -1, 100.0).is_empty(), "unknown weapon snapshot rejected")
	_check(net._check_state(6, Vector3.ZERO, 0, 0, 0, "", 999, -1, 100.0).is_empty() and net._check_state(6, Vector3.ZERO, 0, 0, 0, "", 1, 99, 100.0).is_empty(), "out-of-range car / seat rejected")
	var ok_state: Dictionary = net._check_state(6, Vector3.ZERO, 0, 0, 9999, "", -1, -1, 99999.0)
	_check(int(ok_state.get("flags", -1)) == 255 and float(ok_state.get("health", -1)) == 1000.0, "flags and health clamped")
	_check(int(net._check_state(6, Vector3.ZERO, 0, 0, 128 | 64, "", -1, -1, 100.0).get("flags", -1)) == 192, "hands-up flag (128) survives validation")
	_check(not net._car_fields_ok(6, 99, Transform3D(), Vector3.ZERO, 0, 0) and not net._car_fields_ok(6, 1, Transform3D(Basis(), Vector3(9e6, 0, 0)), Vector3.ZERO, 0, 0), "bad car index / far car position rejected")
	_check(not net._fx_ok(6, Vector3.ZERO, Vector3(NAN, 0, 0), "pistol") and not net._fx_ok(6, Vector3.ZERO, Vector3(5000, 0, 0), "pistol") and net._fx_ok(6, Vector3.ZERO, Vector3(10, 0, 0), "pistol"), "shot fx: NaN and absurd length rejected")
	_check(FastNet.world_event_ok("door", 3, 1) and not FastNet.world_event_ok("nuke", 3, 1) and not FastNet.world_event_ok("door", -1, 1) and not FastNet.world_event_ok("door", 3, 999), "world event kind / index / value checks")
	# Item and chat abuse
	var items: Array = []
	net.host_item_request.connect(func(f: int, a: String, i: int, p: Vector3) -> void: items.append(i))
	net._h_item_request(6, "pickup", -3, Vector3.ZERO)
	net._h_item_request(6, "pickup", 0, Vector3(0, NAN, 0))
	_check(items.is_empty(), "negative item id / NaN position item requests dropped")
	var chats: Array = []
	net.chat.connect(func(f: int, c: String, t: String) -> void: chats.append(t))
	net._h_chat(6, "x".repeat(600), "hi")
	_check(chats.is_empty(), "oversized channel string dropped")
	net._strikes.clear(6)


func _movement() -> void:
	net._latest.erase(6)
	net._state_ms.erase(6)
	net._teleport_all_until = 0
	net._teleport_until.erase(6)
	_check(net._move_ok(6, Vector3(10, 1, 10)), "first snapshot accepted")
	net._latest[6] = {"pos": Vector3(10, 1, 10), "flags": 0}
	_check(not net._move_ok(6, Vector3(10, 1, 3000)), "impossible jump rejected")
	_check(not net._move_ok(6, Vector3(99999, 1, 10)), "position outside the map rejected")
	var accepted: bool = false
	for index: int in range(FastNet.TELEPORT_RESYNC):
		accepted = net._move_ok(6, Vector3(10, 1, 3000))
		if accepted:
			break
	_check(accepted and net._strikes.count(6) >= 1, "persistent jump resyncs after %d snapshots with a strike" % FastNet.TELEPORT_RESYNC)
	net._latest[6] = {"pos": Vector3(10, 1, 3000), "flags": 0}
	net.allow_teleport(6)
	_check(net._move_ok(6, Vector3(0, 1, 0)), "allowed teleport (respawn) accepted")
	net._teleport_until.erase(6)
	net._latest[6] = {"pos": Vector3(0, 1, 0), "flags": 4}
	_check(net._move_ok(6, Vector3(500, 1, 0)), "a dead player's respawn jump is accepted")
	net._strikes.clear(6)


func _hits() -> void:
	net.accept_hits = true
	net._latest[1] = {"pos": Vector3(0, 0, 0), "flags": 0, "weapon": "pistol"}
	net._latest[6] = {"pos": Vector3(0, 0, 10), "flags": 0, "weapon": "pistol"}
	var origin: Vector3 = Vector3(0, 1.5, 10)
	var point: Vector3 = Vector3(0, 1.0, 0)
	var dealt: Array = []
	net.hit_validated.connect(func(sh: int, v: int, a: float, h: bool, w: String) -> void: dealt.append(a))
	_check(not net._h_claim_hit(6, 1, 30.0, false, origin, point, "rifle"), "claim with a weapon the shooter is not holding rejected")
	net._claim_ok[6] = -100000
	_check(net._h_claim_hit(6, 1, 9999.0, true, origin, point, "pistol"), "valid pistol claim accepted")
	_check(not dealt.is_empty() and float(dealt[-1]) <= Sec.max_claim_damage("pistol", FastPlayer.WEAPONS, 250.0), "pistol damage capped per weapon (%.0f)" % (float(dealt[-1]) if not dealt.is_empty() else -1.0))
	net._claim_ok[6] = -100000
	_check(not net._h_claim_hit(6, 1, 30.0, false, Vector3(0, 1.5, 80), point, "pistol"), "claim fired from far away from the shooter rejected")
	net._claim_ok[6] = -100000
	net.los_check = func(_a: Vector3, _b: Vector3) -> bool: return false
	_check(not net._h_claim_hit(6, 1, 30.0, false, origin, point, "pistol"), "blocked line of sight (lead hook) rejects the claim")
	net.los_check = Callable()
	net._claim_ok[6] = -100000
	_check(not net._h_claim_hit(6, 1, -5.0, false, origin, point, "pistol"), "negative damage rejected")
	net.accept_hits = false
	net._claim_ok[6] = -100000
	_check(not net._h_claim_hit(6, 1, 30.0, false, origin, point, "pistol"), "claims outside the live phase rejected")
	net.accept_hits = true
	# Death attribution: peer 6 was last validly hit by nobody, so blaming the host is dropped.
	var deaths: Array = []
	net.player_died.connect(func(i: int, k: int, p: Vector3) -> void: deaths.append([i, k]))
	net._last_hitter.erase(6)
	net._death_ms.erase(6)
	net._h_report_death(6, 1, Vector3(0, 0, 10))
	_check(deaths.size() == 1 and int(deaths[0][1]) == 0, "client cannot blame a player that never hit it (killer %s)" % str(deaths[0][1] if not deaths.is_empty() else "?"))
	net._last_hitter[6] = [1, Time.get_ticks_msec()]
	net._death_ms.erase(6)
	net._h_report_death(6, 1, Vector3(0, 0, 10))
	_check(deaths.size() == 2 and int(deaths[1][1]) == 1, "killer kept when the host validated that hit")
	net._strikes.clear(6)


func _budget_and_kicks() -> void:
	var spent: int = 0
	for index: int in range(400):
		if net._spend(6):
			spent += 1
	_check(spent >= int(FastNet.BUDGET_BURST) - 10 and spent < 400, "shared message budget stops a flood (%d of 400 passed)" % spent)
	_check(net.last_kick.contains("too many bad messages"), "budget flood ends in a kick (%s)" % net.last_kick)
	net._strikes.clear(7)
	net.players[7] = net._new_entry("Player 7")
	net._hello_done[7] = true
	for index: int in range(FastNet.STRIKE_LIMIT):
		net._strike(7, "test")
	_check(net.last_kick.begins_with("peer 7") and net.last_kick.contains("test"), "%d strikes kick the peer" % FastNet.STRIKE_LIMIT)
	net._strike(1, "host")
	_check(net._strikes.count(1) == 0, "the host never strikes itself")


# ---------------------------------------------------------------- real ENet on localhost, one process
# Each FastNet lives under its own root with its own SceneMultiplayer, so node paths ("Net") match.

func _make_net(label: String) -> FastNet:
	var holder := Node.new()
	holder.name = label
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var node: FastNet = FastNet.new()
	node.name = "Net"
	node.use_upnp = false
	node.local_name = label
	holder.add_child(node)
	return node


func _wait(cond: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await process_frame
	return bool(cond.call())


func _end_to_end() -> void:
	var port: int = PORT + 1
	var host: FastNet = _make_net("H")
	_check(host.host(port) == OK, "e2e: host listening on %d" % port)
	# 1. Wrong build: refused with a readable reason, never joins.
	var bad: FastNet = _make_net("Bad")
	bad.build_tag = "0|someone-elses-build"
	var bad_reason: Array = [""]
	bad.connection_failed.connect(func(reason: String) -> void: bad_reason[0] = reason)
	_check(bad.join("127.0.0.1", port) == OK, "e2e: mismatched client starts connecting")
	var refused: bool = await _wait(func() -> bool: return not String(bad_reason[0]).is_empty(), 6.0)
	_check(refused and String(bad_reason[0]).contains("same game build"), "e2e: mismatched build refused with a message (%s)" % bad_reason[0])
	var gone: bool = await _wait(func() -> bool: return host.players.size() == 1, 4.0)
	_check(gone and not bad.is_online(), "e2e: refused peer dropped from the host's lobby")
	# 2. Two good clients join; snapshots are relayed by the host with the real sender id.
	var alice: FastNet = _make_net("Alice")
	var bob: FastNet = _make_net("Bob")
	alice.join("127.0.0.1", port)
	bob.join("127.0.0.1", port)
	var joined: bool = await _wait(func() -> bool: return host.players.size() == 3 and alice.players.size() == 3 and bob.players.size() == 3, 8.0)
	_check(joined, "e2e: two matching clients join (host sees %d)" % host.players.size())
	var seen: Array = []
	bob.remote_state.connect(func(id: int, state: Dictionary) -> void: seen.append([id, state.get("pos", Vector3.ZERO)]))
	var alice_id: int = alice.my_id()
	for index: int in range(5):
		alice.send_state(Vector3(1, 0, 2 + index * 0.1), 0.0, 0.0, 0, "", -1, -1, 100.0)
		await process_frame
	var relayed: bool = await _wait(func() -> bool: return not seen.is_empty(), 4.0)
	_check(relayed and int(seen[0][0]) == alice_id, "e2e: Bob receives Alice's snapshot via the host, stamped with Alice's id")
	var garbage_before: int = seen.size()
	alice.send_state(Vector3(9e7, 0, 0), 0.0, 0.0, 0, "", -1, -1, 100.0)
	await _wait(func() -> bool: return false, 0.4)
	_check(seen.size() == garbage_before, "e2e: an out-of-bounds snapshot is not relayed")
	# 3. A peer that skips the handshake and sends game messages is kicked.
	var sneak: FastNet = _make_net("Sneak")
	sneak.multiplayer.connected_to_server.disconnect(sneak._on_connected_to_server)
	sneak.join("127.0.0.1", port)
	var linked: bool = await _wait(func() -> bool: return host.players.size() == 4, 6.0)
	_check(linked, "e2e: the sneaky peer connects (no hello)")
	for index: int in range(FastNet.STRIKE_LIMIT + 4):
		sneak._state.rpc_id(1, Vector3.ZERO, 0.0, 0.0, 0, "", -1, -1, 100.0)
		sneak._host_chat.rpc_id(1, "all", "spam before hello")
		await process_frame
	var kicked: bool = await _wait(func() -> bool: return host.players.size() == 3, 6.0)
	_check(kicked and host.last_kick.contains("before handshake"), "e2e: pre-handshake messages get the peer kicked (%s)" % host.last_kick)
	for node: FastNet in [sneak, bob, alice, bad, host]:
		node.leave()
	await _wait(func() -> bool: return false, 0.2)
