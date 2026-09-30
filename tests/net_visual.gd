extends SceneTree
## Windowed two-instance visual smoke test: saves screenshots of the online slice from both sides.
##   godot --path . --resolution 1280x720 --script res://tests/net_visual.gd -- --role=host   --port=24700 --out=<dir>
##   godot --path . --resolution 1280x720 --script res://tests/net_visual.gd -- --role=client --port=24700 --out=<dir>
## tests/run_net_visual.sh starts both. Not a pass/fail test: it prints "NET VISUAL <ROLE> DONE: n shots".
## Host and client meet at chat barriers exactly like tests/net_pair.gd.

const WATCHDOG_SECONDS: float = 150.0
const DEFAULT_OUT: String = "C:/Users/CThom/Documents/Codex/2026-09-28/i-want-to-create-a-game/work/captures/net/"
const HOST_NAME: String = "HostTester"
const CLIENT_NAME: String = "ClientTester"
const CLIENT_CREW: String = "solnegro"

var role: String = ""
var port: int = 24700
var out_dir: String = DEFAULT_OUT
var game: Variant
var net: Variant
var shots: int = 0
var finished: bool = false
var chats: Array = []
var _last_chat_ms: int = 0
var _stand: Vector3 = Vector3.ZERO
var _stand_yaw: float = 0.0  # the yaw the host faces (towards the client)


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for index: int in range(count):
		await process_frame


func _wait_seconds(seconds: float) -> void:
	var end_ms: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end_ms:
		await process_frame


func _wait_until(cond: Callable, timeout: float) -> bool:
	var end_ms: int = Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end_ms:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var err: int = image.save_png(out_dir.path_join(file_name))
	shots += 1
	print("SHOT %s (err %d)" % [file_name, err])


func _players() -> Dictionary:
	var value: Variant = net.get("players")
	return value if value is Dictionary else {}


func _other_id() -> int:
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


func _find_chat(prefix: String) -> String:
	for entry: Dictionary in chats:
		if int(entry["from"]) == _other_id() and str(entry["text"]).begins_with(prefix):
			return str(entry["text"])
	return ""


func _say(text: String) -> void:
	var wait_ms: int = _last_chat_ms + 450 - Time.get_ticks_msec()
	if wait_ms > 0:
		await _wait_seconds(wait_ms / 1000.0)
	_last_chat_ms = Time.get_ticks_msec()
	net.call("send_chat", "all", text)


func _sync(tag: String, timeout: float = 25.0) -> bool:
	await _say("sync " + tag)
	var ok: bool = await _wait_until(func() -> bool: return _got_chat("sync " + tag, _other_id()), timeout)
	if not ok:
		print("WARN: barrier '%s' timed out" % tag)
	return ok


func _chat_from_other(prefix: String, timeout: float) -> String:
	await _wait_until(func() -> bool: return _find_chat(prefix) != "", timeout)
	return _find_chat(prefix)


func _online() -> Variant:
	return game.get("online")


func _teleport(pos: Vector3) -> void:
	game.player.global_position = pos
	game.player.velocity = Vector3.ZERO
	await _wait_seconds(0.6)


func _yaw_to(from: Vector3, to: Vector3) -> float:
	var dx: float = to.x - from.x
	var dz: float = to.z - from.z
	return atan2(-dx, -dz)


func _quit_all() -> void:
	if finished:
		return
	finished = true
	print("NET VISUAL %s DONE: %d shots" % [role.to_upper(), shots])
	quit(0)


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.substr(7)
		elif arg.begins_with("--port="):
			port = int(arg.substr(7))
		elif arg.begins_with("--out="):
			out_dir = arg.substr(6)
	if role != "host" and role != "client":
		print("NET VISUAL: bad --role")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	create_timer(WATCHDOG_SECONDS).timeout.connect(func() -> void:
		if finished:
			return
		print("WATCHDOG: net_visual %s did not finish in %d s" % [role, int(WATCHDOG_SECONDS)])
		finished = true
		print("NET VISUAL %s DONE: %d shots (WATCHDOG)" % [role.to_upper(), shots])
		quit(1))

	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.pause_on_focus_loss = false
	game.settings_path = "user://netvisual_%s_settings.cfg" % role
	root.add_child(game)
	await _frames(20)
	net = game.get("net")
	net.set("local_name", HOST_NAME if role == "host" else CLIENT_NAME)
	net.connect("chat", func(from_id: int, channel: String, text: String) -> void:
		chats.append({"from": from_id, "channel": channel, "text": text}))

	await _step_lobby()
	await _step_buy()
	await _step_live()
	await _step_standing()
	await _step_aiming()
	await _step_carrying()
	await _step_driving()
	await _step_chat()
	await _step_map()
	await _sync("finish", 10.0)
	await _wait_seconds(0.5)
	net.call("leave")
	await _frames(3)
	_quit_all()


# ---------------------------------------------------------------- 1. lobby

func _step_lobby() -> void:
	_online().show_lobby()
	await _frames(10)
	if role == "host":
		var err: int = net.call("host", port)
		print("host() -> %d" % err)
		await _wait_until(func() -> bool: return _players().size() == 2, 30.0)
		await _wait_until(func() -> bool: return str(_players().get(_other_id(), {}).get("name", "")) == CLIENT_NAME, 5.0)
		await _wait_until(func() -> bool: return str(_players().get(_other_id(), {}).get("crew", "")) == CLIENT_CREW, 10.0)
	else:
		var err: int = net.call("join", "127.0.0.1", port)
		print("join() -> %d" % err)
		await _wait_until(func() -> bool: return _players().size() == 2 and str(_players().get(1, {}).get("name", "")) == HOST_NAME, 20.0)
		await _wait_seconds(0.5)
		net.call("request_crew", CLIENT_CREW)
		await _wait_until(func() -> bool: return str(_players().get(net.call("my_id"), {}).get("crew", "")) == CLIENT_CREW, 5.0)
	await _wait_seconds(1.0)
	await _shot("lobby_%s.png" % role)
	await _sync("lobby_shot")


# ---------------------------------------------------------------- 2. buy phase

func _step_buy() -> void:
	if role == "host":
		net.call("request_start")
	var online: Variant = _online()
	await _wait_until(func() -> bool: return bool(online.active) and str(online.phase) == "buy" and game.phase == game.Phase.BUY, 20.0)
	await _wait_seconds(1.2)
	await _shot("buy_%s.png" % role)
	await _sync("buy_shot")


# ---------------------------------------------------------------- 3. live + standing

func _step_live() -> void:
	var online: Variant = _online()
	if role == "host":
		online.call("_host_set_phase", "live", 600.0)
	await _wait_until(func() -> bool: return str(online.phase) == "live" and game.phase == game.Phase.LIVE, 10.0)
	if game.get("buy_menu_open") or game.menu.visible:
		game._close_buy_menu()
	await _wait_seconds(0.5)
	await _sync("live")


## Host picks a clear spot 6 m away and tells the client; both face each other.
func _step_standing() -> void:
	if role == "host":
		var origin: Vector3 = game.player.global_position
		var eye: Vector3 = origin + Vector3(0, 1.4, 0)
		var best_yaw: float = float(game.hq_yaw)
		var space: PhysicsDirectSpaceState3D = game.player.get_world_3d().direct_space_state
		for k: int in range(16):
			var yaw: float = float(game.hq_yaw) + k * TAU / 16.0
			var fwd: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(eye, eye + fwd * 7.5)
			query.exclude = [game.player.get_rid()]
			if space.intersect_ray(query).is_empty():
				best_yaw = yaw
				print("clear direction found at k=%d" % k)
				break
		_stand_yaw = best_yaw
		_stand = origin + Vector3(-sin(best_yaw), 0.0, -cos(best_yaw)) * 6.0
		game.player.face(_stand_yaw)
		await _say("stand %.2f %.2f %.2f %.4f" % [_stand.x, _stand.y, _stand.z, _stand_yaw])
	else:
		var text: String = await _chat_from_other("stand ", 10.0)
		var p: PackedStringArray = text.split(" ")
		_stand = Vector3(float(p[1]), float(p[2]), float(p[3]))
		_stand_yaw = float(p[4])
		await _teleport(_stand)
		game.player.face(_stand_yaw + PI)
	await _wait_seconds(1.5)
	await _shot("remote_standing_%s.png" % role)
	await _sync("standing")


# ---------------------------------------------------------------- 4. aiming

func _step_aiming() -> void:
	if role == "client":
		Input.action_press("aim")
	await _wait_seconds(1.5)
	if role == "host":
		await _shot("remote_aiming_host.png")
	else:
		await _shot("aiming_client.png")
	await _sync("aiming")
	if role == "client":
		Input.action_release("aim")


# ---------------------------------------------------------------- 5. carrying the ledger

func _step_carrying() -> void:
	var online: Variant = _online()
	if role == "client":
		var item: Dictionary = online.items.get(0, {})
		print("ledger item: %s" % str(item))
		await _teleport(item.get("pos", _stand))
		print("interact -> %s" % str(online.interact()))
		var ok: bool = await _wait_until(func() -> bool: return int(online.items.get(0, {}).get("holder", 0)) == int(net.call("my_id")), 5.0)
		print("ledger picked: %s" % str(ok))
		await _teleport(_stand)
		game.player.face(_stand_yaw + PI)
	await _wait_seconds(1.5)
	if role == "host":
		await _shot("remote_carrying_host.png")
	else:
		await _shot("carrying_client.png")
	await _sync("carrying")


# ---------------------------------------------------------------- 6. driving

func _step_driving() -> void:
	var car_index: int = -1
	if role == "host":
		var best: float = 1.0e9
		for i: int in range(game.cars.size()):
			var d: float = (game.cars[i] as Node3D).global_position.distance_to(game.player.global_position)
			if d < best:
				best = d
				car_index = i
		print("nearest car %d at %.1f m" % [car_index, best])
		await _say("car %d" % car_index)
	else:
		var text: String = await _chat_from_other("car ", 10.0)
		car_index = int(text.split(" ")[1])
	var ride: Node3D = game.cars[car_index]
	if role == "client":
		await _teleport(ride.call("door_position", 0))
		game._enter_vehicle(ride, 0)
		var seated: bool = await _wait_until(func() -> bool: return game.vehicle == ride and game.seat == 0, 6.0)
		print("client seated: %s" % str(seated))
	else:
		# The nearest car can be around a corner: walk the host to a clear viewing spot beside it first.
		var spot: Variant = _find_view_spot(ride)
		print("host view spot: %s (car at %s)" % [str(spot), str(ride.global_position)])
		if spot != null:
			await _teleport(spot)
		game.player.face(_yaw_to(game.player.global_position, ride.global_position))
	await _wait_seconds(1.0)
	await _sync("seated")
	if role == "client":
		Input.action_press("move_forward")
	var end_ms: int = Time.get_ticks_msec() + 1200
	while Time.get_ticks_msec() < end_ms:
		if role == "host":
			game.player.face(_yaw_to(game.player.global_position, ride.global_position))
		await process_frame
	if role == "host":
		await _shot("remote_driving_host.png")
	else:
		await _shot("driving_client.png")
	if role == "client":
		Input.action_release("move_forward")
	await _sync("drove")
	await _wait_seconds(1.0)
	if role == "host":
		game.player.face(_yaw_to(game.player.global_position, ride.global_position))
		await _wait_seconds(0.3)
		await _shot("remote_driving_stopped_host.png")
	else:
		await _shot("driving_stopped_client.png")
	await _sync("drove2")
	if role == "client":
		game._exit_vehicle(true)
		await _wait_seconds(0.5)
	await _sync("exited")


## A ground point 9-15 m from the car (right, left, behind, front) with a clear line to it, or null.
func _find_view_spot(ride: Node3D) -> Variant:
	var space: PhysicsDirectSpaceState3D = game.player.get_world_3d().direct_space_state
	var basis: Basis = ride.global_transform.basis
	var center: Vector3 = ride.global_position + Vector3(0, 1.0, 0)
	for dist: float in [9.0, 12.0, 15.0]:
		for dir: Vector3 in [basis.x, -basis.x, basis.z, -basis.z]:
			var flat: Vector3 = Vector3(dir.x, 0.0, dir.z).normalized()
			var p: Vector3 = ride.global_position + flat * dist
			var down: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(p + Vector3(0, 3, 0), p + Vector3(0, -3, 0))
			down.exclude = [game.player.get_rid(), ride.get_rid()]
			var ground: Dictionary = space.intersect_ray(down)
			if ground.is_empty() or (ground["normal"] as Vector3).y < 0.8 or absf((ground["position"] as Vector3).y - ride.global_position.y) > 0.6:
				continue
			var spot: Vector3 = (ground["position"] as Vector3) + Vector3(0, 0.1, 0)
			var los: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(spot + Vector3(0, 1.5, 0), center)
			los.exclude = [game.player.get_rid()]
			var hit: Dictionary = space.intersect_ray(los)
			if hit.is_empty() or hit["collider"] == ride:
				return spot
	return null


# ---------------------------------------------------------------- 7. chat

func _step_chat() -> void:
	await _wait_seconds(6.0)  # let the barrier lines fade from the feed
	await _sync("chat_ready")
	if role == "client":
		await _say("hello from the client")
	await _wait_until(func() -> bool: return _got_chat("hello from the client", _other_id()) or role == "client", 8.0)
	await _wait_seconds(0.5)
	await _shot("chat_%s.png" % role)
	await _sync("chat_shot")


# ---------------------------------------------------------------- 8. full map

func _step_map() -> void:
	game.map_open = true
	await _frames(2)
	await _wait_seconds(0.5)
	await _shot("map_%s.png" % role)
	game.map_open = false
	await _frames(2)
	await _sync("map_shot")
