extends SceneTree
## The Week (docs/LEAD_DESIGN_DECISIONS.md §1–3): a solo host plays a whole Week on short timers.
##   godot --headless --path . --script res://tests/week_flow.gd
## Checks weekday names and contract values, the crew phone (buy-phase pickup, call gate, K drop),
## one trade item at a time with the sidearm rule, gear carry-over (survivors keep, the dead restart
## with a pistol), the Friday Dead Drop, END OF WEEK standings, and the new-Week reset.

const PORT: int = 24761

var game: Variant
var net: Variant
var online: Variant
var checks: int = 0
var failures: int = 0
var finished: bool = false


func _initialize() -> void:
	create_timer(170.0).timeout.connect(func() -> void:
		if not finished:
			_check(false, "watchdog: week_flow finished within 170 s")
			_finish())
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
		push_error("FAIL: " + label)


func _finish() -> void:
	if finished:
		return
	finished = true
	if net != null:
		net.call("leave")
	print("WEEK FLOW RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _frames(count: int) -> void:
	for index: int in range(count):
		await process_frame


func _wait_until(cond: Callable, timeout: float) -> bool:
	var end_ms: int = Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end_ms:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _teleport(pos: Vector3) -> void:
	game.player.global_position = pos
	game.player.velocity = Vector3.ZERO
	# The host checks pickups against my last state snapshot (sent every 0.05 s): let one go out.
	var end_ms: int = Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < end_ms:
		await process_frame


func _item(item: int) -> Dictionary:
	return online.items.get(item, {})


func _crew() -> String:
	return str(game.crew)


func _run() -> void:
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.pause_on_focus_loss = false
	game.settings_path = "user://week_flow_settings.cfg"
	root.add_child(game)
	await _frames(5)
	net = game.get("net")
	online = game.get("online")
	_check(online != null and net != null, "game.online and game.net exist")
	if online == null or net == null:
		_finish()
		return
	_pure_checks()
	# Long buy and street timers so the test drives every transition itself; short settle screens.
	online.buy_seconds = 60.0
	online.live_seconds = 120.0
	online.settle_seconds = 0.3
	online.week_end_seconds = 0.3
	# The title menu's SOLO WEEK: a localhost-only host (no firewall prompt, no UPnP) that starts at once.
	online.start_solo_week()
	_check(bool(net.call("is_host")), "SOLO WEEK hosts a match on this PC")
	# Steam signs in only when the online lobby opens, so offline play keeps the controller (Steam Input).
	_check(not bool(online.get("_steam_started")), "SOLO WEEK never signs in to Steam")
	var started: bool = await _wait_until(func() -> bool: return bool(online.active) and str(online.phase) == "buy", 5.0)
	_check(started, "the solo host's Week starts in the buy phase")
	if not started:
		_finish()
		return
	await _monday()
	for expected: int in [2, 3, 4]:
		await _plain_day(expected)
	await _friday()
	await _new_week()
	_finish()


func _pure_checks() -> void:
	var script: GDScript = online.get_script()
	_call_machine_checks()
	# Doors sync online by index: every door in the (much bigger) city must fit the host's world-event check.
	var last_door: int = (game.world.interactable_doors as Array).size() - 1
	_check(FastNet.world_event_ok("door", last_door, 1) and FastNet.world_event_ok("lift", last_door, 1), "all %d doors fit the network's door index limit" % (last_door + 1))
	_check(script.weekday_index_of(1, 5) == 0 and script.weekday_index_of(5, 5) == 4, "a 5-Day Week runs Monday to Friday")
	var blood: Array = script.blood_lines({"kingsway>morris": 2, "morris>kingsway": 1, "bogus": 3})
	_check(blood.size() == 2 and str(blood[0]).contains("ROYALS dropped MORRIS x2") and str(blood[1]).contains("MORRIS dropped ROYALS."), "the morning paper names who shot whom (%s)" % str(blood))
	_check(script.weekday_index_of(1, 3) == 2 and script.weekday_index_of(3, 3) == 4, "a 3-Day Week runs Wednesday to Friday, so it still ends on the Dead Drop")
	# The Dead Drop always lands on a road, near a neutral landmark, and never inside a building footprint.
	var bad: int = 0
	var far: int = 0
	for pick: int in range(40):
		var spot: Dictionary = script.dead_drop_spot(game.world, pick)
		var at: Vector3 = spot["at"]
		for rect: Rect2 in game.world.footprints:
			if rect.has_point(Vector2(at.x, at.z)):
				bad += 1
				break
		var nearest: float = INF
		for mark: Dictionary in game.world.landmarks:
			if str(mark["name"]) == str(spot["name"]):
				nearest = Vector2(at.x, at.z).distance_to(Vector2((mark["at"] as Vector3).x, (mark["at"] as Vector3).z))
		if nearest > 80.0:
			far += 1
	_check(bad == 0, "Dead Drop spots never sit inside a building footprint (%d of 40 did)" % bad)
	_check(far == 0, "Dead Drop spots are within 80 m of their landmark (%d of 40 were not)" % far)


## The call state machine on its own (scripts/phone_calls.gd).
func _call_machine_checks() -> void:
	var Calls: GDScript = load("res://scripts/phone_calls.gd")
	var machine: RefCounted = Calls.new()
	_check(machine.dial(2, 3) == "" and machine.is_busy(2) and machine.is_busy(3), "dialling rings both ends of a fresh call")
	_check(machine.dial(4, 2) == "Line busy." and machine.dial(3, 5) == "Line busy.", "a busy phone, caller or callee, gives 'Line busy.'")
	_check(machine.dial(4, 4) == "Wrong number." and machine.dial(-1, 4) == "Wrong number.", "a phone cannot dial itself or a bad number")
	_check(not machine.answer(2) and not machine.answer(9), "only the ringing callee can answer (not the caller, not a stranger)")
	_check(machine.answer(3) and int(machine.call_of(2)["state"]) == Calls.State.LIVE and machine.partner_of(2) == 3, "the callee answers: the call is LIVE")
	_check(not machine.answer(3), "a live call cannot be answered again")
	var ended: Dictionary = machine.hang_up(3)
	_check(not ended.is_empty() and not machine.is_busy(2) and not machine.is_busy(3), "either end hangs up and both phones are free")
	_check(machine.dial(2, 3) == "" and machine.tick(19.0).is_empty(), "a call still rings at 19 s")
	var timeout: Array = machine.tick(1.5)
	_check(timeout.size() == 1 and str(timeout[0]["reason"]) == "noanswer" and not machine.is_busy(3), "an unanswered call ends at 20 s as 'noanswer'")
	machine.dial(2, 3)
	machine.answer(3)
	_check(machine.tick(179.0).is_empty(), "a live call lasts 179 s")
	var cut: Array = machine.tick(2.0)
	_check(cut.size() == 1 and str(cut[0]["reason"]) == "timeout" and float(cut[0]["live_seconds"]) >= 180.0, "a live call is cut at 3 minutes")
	machine.dial(2, 3)
	machine.dial(4, 5)
	machine.answer(5)
	var wire: Array = machine.to_wire()
	_check(wire.size() == 2 and Calls.from_wire(wire).size() == 2 and int(Calls.from_wire(wire)[1]["state"]) == Calls.State.LIVE, "calls survive the wire round trip")
	_check(machine.clear("day").size() == 2 and machine.calls.is_empty(), "the Day ending clears every call")
	_check(Calls.from_wire("junk").is_empty() and Calls.from_wire([[1, 2, 9, 0.0], [1, 1, 0, 0.0], [1, 2], [1, 2, 0, NAN], [-1, 2, 0, 0.0], ["a", 2, 0, 0.0], [70, 2, 0, 0.0]]).is_empty(), "malformed wire rows are dropped")
	var many: Array = []
	for index: int in range(20):
		many.append([1, 2, 0, 0.0])
	_check(Calls.from_wire(many).size() == Calls.MAX_CALLS, "a flood of call rows is capped")


## Host-side call flow with fake peers (no network): dial needs a phone, the dial strip keys, busy lines, ring
## timeout, pick-up answers, hang-up, a stolen phone dials as its owners, a holder leaving, the 3-minute cut and
## the Day ending. I hold my crew's phone (buy phase) when this runs, and hold it again when it returns.
func _phone_calls(mine: int) -> void:
	var other_crew: String = ""
	var third_crew: String = ""
	for crew_id: String in online.Factions.ORDER:
		if crew_id == _crew():
			continue
		if other_crew.is_empty():
			other_crew = crew_id
		elif third_crew.is_empty():
			third_crew = crew_id
	var other: int = online.phone_item(other_crew)
	var third: int = online.phone_item(third_crew)
	var notes: Array = []
	net.phone_notice_tap = func(peer: int, text: String) -> void: notes.append([peer, text])
	var at: Vector3 = game.hq_spawn + Vector3(60, 0.3, 0)
	# Two other crews join on the host (fake peers), their phones on the ground 6 m apart.
	for fake: Array in [[98, third_crew, third], [99, other_crew, other]]:
		var pid: int = fake[0]
		net.players[pid] = net._new_entry("Fake%d" % pid)
		net.players[pid]["crew"] = fake[1]
		net._latest[pid] = {"pos": at + Vector3(0, -0.3, float(pid - 98) * 6.0), "flags": 0}
		net.broadcast_item(int(fake[2]), {"kind": "phone", "holder": 0, "pos": at + Vector3(0, 0, float(pid - 98) * 6.0), "banked": "", "msg": ""})
	await _wait_until(func() -> bool: return online._loose(other) and online._loose(third), 2.0)
	_check(online._loose(other) and online._loose(third), "the other crews' phones are on the ground")
	var press: Callable = func(key: int) -> bool:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = key as Key
		event.pressed = true
		return bool(online.phone_input(event))
	# P with no phone shows the existing hint.
	_check(bool(online.drop_phone()), "I drop my phone to test the no-phone key")
	await _wait_until(func() -> bool: return int(_item(mine).get("holder", 0)) == 0, 2.0)
	_check(bool(press.call(KEY_P)) and str(game.feed_label.text).begins_with("No phone in hand"), "P with no phone shows the 'No phone in hand' hint ('%s')" % str(game.feed_label.text))
	await _teleport(_item(mine).get("pos", Vector3.ZERO))
	online.interact()
	await _wait_until(func() -> bool: return int(_item(mine).get("holder", 0)) == 1, 2.0)
	_check(online._phone_item_of(1) == mine, "I hold my phone again")
	# Dial needs a phone.
	online._host_phone_request(99, "dial", mine)
	_check(online._calls.calls.is_empty() and notes.size() > 0 and int(notes[-1][0]) == 99 and str(notes[-1][1]).begins_with("No phone in hand"), "a player with no phone cannot dial")
	# The dial strip: P opens it, a number picks, P dials; ESC and a timeout close it.
	_check(bool(press.call(KEY_P)) and online._dial_until > 0.0 and online._dial_targets.size() >= 2, "P with a phone opens the dial strip (%d phones listed)" % online._dial_targets.size())
	_check(online._dial_targets.has(other) and not online._dial_targets.has(mine), "the strip lists other crews' phones, never my own")
	await _frames(2)
	_check(str(online._phone_label.text).begins_with("DIAL") and online._phone_label.visible, "the HUD shows the dial strip ('%s')" % str(online._phone_label.text))
	_check(bool(press.call(KEY_ESCAPE)) and online._dial_until == 0.0, "ESC closes the strip")
	press.call(KEY_P)
	online._dial_until = online._now() - 0.1
	await _frames(2)
	_check(online._dial_until == 0.0, "the strip closes by itself after a few seconds")
	press.call(KEY_P)
	var pick: int = online._dial_targets.find(other)
	press.call(KEY_1 + pick)
	_check(online._dial_index == pick, "a number key picks a phone")
	press.call(KEY_P)
	await _wait_until(func() -> bool: return not online._view_call_of(mine).is_empty(), 2.0)
	var call: Dictionary = online._calls.call_of(mine)
	_check(not call.is_empty() and int(call["a"]) == mine and int(call["b"]) == other and int(call["state"]) == 0, "P, pick, P rings the other crew's phone")
	await _frames(3)
	_check(str(online._phone_label.text).begins_with("CALLING %s" % str(online._phone_name(other))), "the caller's HUD says who is being called ('%s')" % str(online._phone_label.text))
	_check(int(online._view_call_of(other)["state"]) == 0, "the ringing state is replicated to every peer")
	# Busy lines: my own, and a ringing callee.
	notes.clear()
	online._host_phone_request(1, "dial", third)
	_check(notes.size() == 1 and str(notes[0][1]) == "Line busy.", "my phone is in a call: 'Line busy.'")
	online._host_item_request(98, "pickup", third, at)
	await _frames(2)
	notes.clear()
	online._host_phone_request(98, "dial", other)
	_check(notes.size() == 1 and int(notes[0][0]) == 98 and str(notes[0][1]) == "Line busy.", "dialling a phone that is already ringing: 'Line busy.'")
	# No answer in 20 s.
	notes.clear()
	online._host_tick_calls(19.0)
	_check(not online._calls.calls.is_empty(), "still ringing at 19 s")
	online._host_tick_calls(1.5)
	_check(online._calls.calls.is_empty() and notes.any(func(n: Array) -> bool: return int(n[0]) == 1 and str(n[1]) == "No answer."), "no answer in 20 s: the call ends and the caller is told 'No answer.'")
	# Picking up a ringing phone answers it.
	online._host_phone_request(1, "dial", other)
	await _frames(2)
	online._host_item_request(99, "pickup", other, at + Vector3(0, 0, 6.0))
	var answered: bool = await _wait_until(func() -> bool: return not online._view_call_of(other).is_empty() and int(online._view_call_of(other)["state"]) == 1, 2.0)
	_check(answered and int(online._day_stats.get("voice_calls", 0)) >= 1, "picking up a ringing phone answers it (and counts a voice call)")
	var lines: Array = online._host_live_lines()
	_check(lines.size() == 1 and (lines[0]["a"] as Vector3).distance_to(game.player.global_position) < 0.5 and (lines[0]["b"] as Vector3).distance_to(net.latest_pos(99)) < 0.5, "a live call hands the voice relay both phone positions (a held phone is at its holder)")
	await _frames(3)
	_check(str(online._phone_label.text).begins_with("ON CALL: %s" % str(online._phone_name(other))), "the HUD shows 'ON CALL: <phone> m:ss' ('%s')" % str(online._phone_label.text))
	# Hang up from the far end.
	notes.clear()
	online._host_phone_request(99, "hangup", -1)
	await _frames(2)
	_check(online._calls.calls.is_empty() and online.phone_view.is_empty() and notes.any(func(n: Array) -> bool: return int(n[0]) == 1 and str(n[1]).ends_with("hung up.")), "hanging up ends the call for everyone and tells the other end")
	# A stolen phone dials as its owners: I drop mine, 98 takes it and dials the other crew.
	_check(bool(online.drop_phone()), "I drop my phone so a rival can take it")
	await _wait_until(func() -> bool: return int(_item(mine).get("holder", 0)) == 0, 2.0)
	online._host_item_request(98, "drop", third, at)
	await _wait_until(func() -> bool: return int(_item(third).get("holder", 0)) == 0, 2.0)
	net._latest[98] = {"pos": (_item(mine).get("pos", Vector3.ZERO) as Vector3) + Vector3(0, -0.3, 0), "flags": 0}
	online._host_item_request(98, "pickup", mine, _item(mine).get("pos", Vector3.ZERO))
	await _wait_until(func() -> bool: return int(_item(mine).get("holder", 0)) == 98, 2.0)
	online._host_item_request(99, "drop", other, at)
	await _wait_until(func() -> bool: return int(_item(other).get("holder", 0)) == 0, 2.0)
	online._host_phone_request(98, "dial", other)
	var stolen: Dictionary = online._calls.call_of(mine)
	_check(not stolen.is_empty() and int(stolen["a"]) == mine and online.phone_crew(int(stolen["a"])) == _crew(), "a stolen phone dials as its owning crew (the call is from %s)" % str(online.phone_crew(mine)))
	# The thief disconnects: the call ends.
	online._on_peer_left(98)
	_check(online._calls.calls.is_empty(), "a holder disconnecting ends the call")
	net.players.erase(98)
	net._latest.erase(98)
	# 3 minutes: a live call between two phones lying on the ground keeps working, then is cut.
	net.broadcast_item(mine, {"kind": "phone", "holder": 0, "pos": at + Vector3(3, 0, 0), "banked": "", "msg": ""})
	await _wait_until(func() -> bool: return online._loose(mine), 2.0)
	online._calls.dial(mine, other)
	online._calls.answer(other)
	var seconds_before: int = int(online._day_stats.get("voice_call_seconds", 0))
	online._host_tick_calls(170.0)
	_check(not online._calls.calls.is_empty() and online._host_live_lines().size() == 1, "a live call between two dropped phones still works at 170 s (a speakerphone on the table)")
	online._host_tick_calls(11.0)
	_check(online._calls.calls.is_empty() and int(online._day_stats.get("voice_call_seconds", 0)) >= seconds_before + 180, "a live call is cut at 3 minutes and its seconds are tallied (%d)" % int(online._day_stats.get("voice_call_seconds", 0)))
	# The morning reset of the phones ends every call.
	online._calls.dial(mine, other)
	online._calls.answer(other)
	net.players.erase(99)
	net._latest.erase(99)
	online._host_place_phones(online._active_crews())
	_check(online._calls.calls.is_empty(), "the morning reset of the phones ends every call")
	await _wait_until(func() -> bool: return online._loose(mine), 2.0)
	net.phone_notice_tap = Callable()
	# Take my phone back for the rest of Monday.
	await _teleport(_item(mine).get("pos", Vector3.ZERO))
	online.interact()
	await _wait_until(func() -> bool: return int(_item(mine).get("holder", 0)) == 1, 2.0)
	_check(int(_item(mine).get("holder", 0)) == 1, "I have my phone back after the reset")


func _monday() -> void:
	_check(int(online.day) == 1 and online.day_name() == "MONDAY", "Day 1 is MONDAY (got %d %s)" % [int(online.day), online.day_name()])
	_check(int(online.week) == 1 and int(online.week_days) == 5, "Week 1 of 5 Days")
	_check(int(online.contract_value(0)) == 5400 and int(online.contract_value(1)) == 3600, "Monday values the Ledger at $5,400 and the cash at $3,600 (x0.6)")
	online.update_hud()
	_check(str(game.top_left.text).contains("MONDAY"), "the HUD names the weekday ('%s')" % str(game.top_left.text))
	_check(online.briefing().contains("MONDAY, DAY 1 OF 5"), "the objective board opens with the weekday")
	# First morning: the one-screen rules card sits beside the buy menu.
	var card: Node = online._week_card
	_check(card != null and is_instance_valid(card) and card.is_inside_tree(), "the first Monday shows the HOW THE WEEK WORKS card")
	var card_text: String = online.week_card_text()
	_check(card_text.contains("MONDAY TO FRIDAY") and card_text.contains("BANKED") and card_text.contains("Kills pay nothing") and card_text.contains("DEAD DROP"), "the card covers the Week, banking, no kill pay and the Dead Drop")
	_check(card_text.contains("[P]") == false and card_text.contains(str(game._glyph("phone_call"))), "the card names the phone key for this device")
	# The crew phone waits at the HQ spawn during the buy phase.
	var phone: int = online.phone_item(_crew())
	_check(phone >= 2 and online._loose(phone), "my crew's phone is on the ground at the HQ spawn")
	var phone_at: Vector3 = _item(phone).get("pos", Vector3.INF)
	_check(Vector2(phone_at.x, phone_at.z).distance_to(Vector2(game.hq_spawn.x, game.hq_spawn.z)) < 6.0, "the phone is within 6 m of the spawn")
	_check(not bool(net.call_gate.call(1)), "without a phone the host refuses my calls")
	await _teleport(phone_at)
	_check(bool(online.interact()), "E picks up the phone in the buy phase")
	var held: bool = await _wait_until(func() -> bool: return int(_item(phone).get("holder", 0)) == 1, 2.0)
	_check(held, "I hold my crew's phone")
	_check(bool(net.call_gate.call(1)), "holding a phone, the host lets me call other crews")
	online.update_hud()
	_check(str(game.marker_label.text).contains("PHONE: %s" % str(online.Factions.get_crew(_crew())["short"])), "the HUD phone slot shows the crew ('%s')" % str(game.marker_label.text))
	_check(bool(online.drop_phone()), "K drops the phone")
	var dropped: bool = await _wait_until(func() -> bool: return int(_item(phone).get("holder", 0)) == 0, 2.0)
	_check(dropped, "the phone is on the ground again")
	await _teleport(_item(phone).get("pos", Vector3.ZERO))
	online.interact()
	await _wait_until(func() -> bool: return int(_item(phone).get("holder", 0)) == 1, 2.0)
	# The strip hides under the buy menu; with the menu closed it is on screen.
	var menu_was_open: bool = game.buy_menu_open
	game.buy_menu_open = false
	await _frames(2)
	_check(str(game.action_label.text).contains("CALL A CREW"), "the HUD action strip is on screen with the buy menu closed ('%s')" % str(game.action_label.text))
	game.buy_menu_open = menu_was_open
	_check(online.action_prompts().contains("[%s] CALL A CREW" % str(game._glyph("phone_call"))) and online.action_prompts().contains("DROP PHONE"), "holding the phone, the action strip shows CALL and DROP PHONE ('%s')" % online.action_prompts())
	await _phone_calls(phone)
	await _teleport(_item(0).get("pos", Vector3.ZERO))
	_check(not bool(online.interact()) and int(_item(0).get("holder", 0)) == 0, "trade items can't be picked up in the buy phase")
	# Buy a primary, then open the doors.
	game.player.equip("smg")
	online.time_left = 0.0
	var live: bool = await _wait_until(func() -> bool: return str(online.phase) == "live", 3.0)
	_check(live, "the doors open when the buy timer runs out")
	_check(online._week_card == null, "the rules card goes away when the doors open")
	_check(online.action_prompts().contains("HANDS UP") and online.action_prompts().contains("CREW RADIO"), "on the street the action strip shows hands up and the radio ('%s')" % online.action_prompts())
	# One trade item at a time; sidearm only while carrying. The cases start on my own HQ doorstep
	# (inside the bank radius), so first carry the cash case out to a street and leave it there.
	var street: Vector3 = (online.get_script().dead_drop_spot(game.world, 0) as Dictionary)["at"] + Vector3(0, 0.2, 0)
	await _teleport(_item(1).get("pos", Vector3.ZERO))
	online.interact()
	await _wait_until(func() -> bool: return int(_item(1).get("holder", 0)) == 1, 2.0)
	await _teleport(street)
	_check(bool(online.drop()), "G drops the cash case on the street")
	await _wait_until(func() -> bool: return int(_item(1).get("holder", 0)) == 0, 2.0)
	await _teleport(_item(0).get("pos", Vector3.ZERO))
	_check(bool(online.interact()), "E picks up the Ledger")
	await _wait_until(func() -> bool: return int(_item(0).get("holder", 0)) == 1, 2.0)
	_check(int(_item(0).get("holder", 0)) == 1, "I hold the Ledger")
	_check(int(_item(phone).get("holder", 0)) == 1, "the phone stays in its own slot while I carry the Ledger")
	await _frames(2)
	if game.player.get("sidearm_only") != null:
		_check(bool(game.player.sidearm_only), "carrying the Ledger sets sidearm_only on the player")
		_check(not game.player.call("is_primary", str(game.player.weapon_id)), "the drawn weapon is a sidearm while carrying (got %s)" % str(game.player.weapon_id))
	await _teleport(_item(1).get("pos", Vector3.ZERO))
	_check(str(online.prompt_text()).begins_with("HANDS FULL"), "the prompt says HANDS FULL ('%s')" % str(online.prompt_text()))
	online.interact()
	await _frames(20)
	_check(int(_item(1).get("holder", 0)) == 0 and int(_item(0).get("holder", 0)) == 1, "hands full: the cash case is refused while I carry the Ledger")
	# The host refuses a forged second pickup too.
	net.send_item_request("pickup", 1, game.player.global_position)
	await _frames(10)
	_check(int(_item(1).get("holder", 0)) == 0, "the host refuses a second trade item even when asked directly")
	await _teleport(game.hq_spawn)
	_check(bool(online.interact()), "E banks the Ledger at HQ")
	var banked: bool = await _wait_until(func() -> bool: return int(online.bank.get(_crew(), 0)) == 5400, 2.0)
	_check(banked, "Monday bank is $5,400 (got %d)" % int(online.bank.get(_crew(), 0)))
	await _frames(2)
	if game.player.get("sidearm_only") != null:
		_check(not bool(game.player.sidearm_only), "hands free again: sidearm_only clears")
	await _bank_cash()
	var settled: bool = await _wait_until(func() -> bool: return str(online.phase) == "settle", 3.0)
	_check(settled, "both goods banked: the Day settles")
	# Host telemetry: one JSON line per Day.
	var log_path: String = str(online.telemetry_path)
	_check(not log_path.is_empty() and FileAccess.file_exists(log_path), "the host writes a telemetry line for the Day (%s)" % log_path)
	if FileAccess.file_exists(log_path):
		var lines: PackedStringArray = FileAccess.get_file_as_string(log_path).strip_edges().split("\n")
		var entry: Variant = JSON.parse_string(lines[lines.size() - 1])
		_check(entry is Dictionary and str(entry.get("weekday", "")) == "MONDAY" and int(entry.get("banks", 0)) == 2 and int(entry.get("pickups", 0)) >= 2, "Monday's telemetry counts two banks and the pickups (%s)" % str(entry))


func _bank_cash() -> void:
	await _teleport(_item(1).get("pos", Vector3.ZERO))
	online.interact()
	await _wait_until(func() -> bool: return int(_item(1).get("holder", 0)) == 1, 2.0)
	await _teleport(game.hq_spawn)
	online.interact()
	await _wait_until(func() -> bool: return not str(_item(1).get("banked", "")).is_empty(), 2.0)


func _plain_day(expected: int) -> void:
	var buy: bool = await _wait_until(func() -> bool: return str(online.phase) == "buy" and int(online.day) == expected, 5.0)
	_check(buy, "Day %d starts (%s)" % [expected, online.day_name()])
	_check(online.recap.size() > 0 and online.morning_paper().size() > 1, "the morning paper carries yesterday's results")
	var names: Array = ["", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY"]
	_check(online.day_name() == names[expected], "Day %d is %s" % [expected, names[expected]])
	var phone: int = online.phone_item(_crew())
	_check(online._loose(phone), "each morning the phone is back at the HQ spawn")
	if expected == 2:
		_check(game.player.owned.has("smg"), "a survivor keeps yesterday's SMG")
		# Die today: tomorrow starts with the pistol only.
		online.time_left = 0.0
		await _wait_until(func() -> bool: return str(online.phase) == "live", 3.0)
		game.player.take_damage(1000.0)
		await _frames(5)
		_check(game.player.is_dead(), "the player died on Tuesday")
	elif expected == 4:
		# Nobody touches the goods: the client gets nervous and the contract loses 10% (never on Friday).
		online.nervous_after = 0.3
		online.time_left = 0.0
		await _wait_until(func() -> bool: return str(online.phase) == "live", 3.0)
		var nervous: bool = await _wait_until(func() -> bool: return int(online.nervous_steps) == 1, 3.0)
		_check(nervous, "an untouched contract makes the client nervous (steps %d)" % int(online.nervous_steps))
		_check(int(online.contract_value(0)) == 10100, "Thursday's Ledger drops 10%% to $10,100 (got %d)" % int(online.contract_value(0)))
		_check(int(online.contract_value(-1)) == int(round(1500 * 1.25 / 100.0)) * 100, "the clean-deal bonus is not cut by nerves")
	else:
		online.time_left = 0.0
		await _wait_until(func() -> bool: return str(online.phase) == "live", 3.0)
	if expected == 3:
		_check(game.player.owned.size() == 1 and game.player.owned.has("pistol"), "the dead restart the next Day with the pistol only (%s)" % str(game.player.owned))
	var value: int = int(online.contract_value(0))
	var before: int = int(online.bank.get(_crew(), 0))
	await _wait_until(func() -> bool: return not game.player.is_dead(), 12.0)
	await _teleport(_item(0).get("pos", Vector3.ZERO))
	online.interact()
	await _wait_until(func() -> bool: return int(_item(0).get("holder", 0)) == 1, 2.0)
	await _teleport(game.hq_spawn)
	online.interact()
	var paid: bool = await _wait_until(func() -> bool: return int(online.bank.get(_crew(), 0)) == before + value, 2.0)
	_check(paid, "%s pays $%d for the Ledger" % [online.day_name(), value])
	if expected == 4:
		online.nervous_after = 240.0
		await _frames(5)
		_check(int(online.nervous_steps) == 1, "once the goods move, the lost value stays lost but stops falling")
	await _bank_cash()
	await _wait_until(func() -> bool: return str(online.phase) == "settle", 3.0)


func _friday() -> void:
	var buy: bool = await _wait_until(func() -> bool: return str(online.phase) == "buy" and int(online.day) == 5, 5.0)
	_check(buy, "Day 5 starts")
	_check(online.day_name() == "FRIDAY" and online.is_dead_drop(), "Day 5 is FRIDAY, the Dead Drop")
	_check(str(online.seller).is_empty() and str(online.buyer).is_empty(), "Friday has no seller or buyer")
	_check(bool(_item(0).get("hidden", false)) and bool(_item(1).get("hidden", false)), "the goods stay hidden during Friday's buy phase")
	_check(not online.briefing().contains("Clean deal"), "no clean-deal bonus on Friday")
	_check(int(online.nervous_steps) == 0, "each morning the client starts calm")
	online.time_left = 0.0
	var revealed: bool = await _wait_until(func() -> bool: return str(online.phase) == "live" and not bool(_item(0).get("hidden", false)), 3.0)
	_check(revealed, "the doors open and the Dead Drop appears")
	_check(not str(online.drop_site).is_empty(), "the Dead Drop site is named ('%s')" % str(online.drop_site))
	var at: Vector3 = _item(0).get("pos", Vector3.ZERO)
	_check(Vector2(at.x, at.z).distance_to(Vector2(game.hq_spawn.x, game.hq_spawn.z)) > 20.0, "the Dead Drop is away from my HQ")
	var before: int = int(online.bank.get(_crew(), 0))
	await _teleport(at)
	online.interact()
	await _wait_until(func() -> bool: return int(_item(0).get("holder", 0)) == 1, 2.0)
	await _teleport(game.hq_spawn)
	online.interact()
	var paid: bool = await _wait_until(func() -> bool: return int(online.bank.get(_crew(), 0)) == before + 14400, 2.0)
	_check(paid, "Friday pays $14,400 for the Ledger (x1.6)")
	await _bank_cash()
	_check(int(online.bank.get(_crew(), 0)) == before + 14400 + 9600, "anyone banking the Friday cash is paid $9,600")
	var week_end: bool = await _wait_until(func() -> bool: return str(online.phase) == "week_end", 4.0)
	_check(week_end, "after Friday comes END OF WEEK")
	var text: String = "\n".join(PackedStringArray(online.results))
	_check(text.contains("WIN WEEK 1"), "the standings name the Week's winner ('%s')" % text)


func _new_week() -> void:
	var monday: bool = await _wait_until(func() -> bool: return str(online.phase) == "buy" and int(online.week) == 2, 4.0)
	_check(monday, "Week 2 starts")
	_check(int(online.day) == 1 and online.day_name() == "MONDAY", "Week 2 starts on MONDAY")
	_check(online._week_card == null, "the rules card shows only on the first Monday of a session")
	_check(int(online.bank.get(_crew(), -1)) == 0, "the crew bank resets for the new Week")
	_check(int(game.cash) == int(online.START_CASH), "money resets to the starting $%d (got %d)" % [int(online.START_CASH), int(game.cash)])
	_check(game.player.owned.size() == 1 and game.player.owned.has("pistol"), "gear resets to the pistol for the new Week")
	_check(online.recap.size() > 0, "the new Week's first morning paper shows last Week's standings")
