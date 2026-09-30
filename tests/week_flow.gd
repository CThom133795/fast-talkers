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


func _monday() -> void:
	_check(int(online.day) == 1 and online.day_name() == "MONDAY", "Day 1 is MONDAY (got %d %s)" % [int(online.day), online.day_name()])
	_check(int(online.week) == 1 and int(online.week_days) == 5, "Week 1 of 5 Days")
	_check(int(online.contract_value(0)) == 5400 and int(online.contract_value(1)) == 3600, "Monday values the Ledger at $5,400 and the cash at $3,600 (x0.6)")
	online.update_hud()
	_check(str(game.top_left.text).contains("MONDAY"), "the HUD names the weekday ('%s')" % str(game.top_left.text))
	_check(online.briefing().contains("MONDAY, DAY 1 OF 5"), "the objective board opens with the weekday")
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
	await _teleport(_item(0).get("pos", Vector3.ZERO))
	_check(not bool(online.interact()) and int(_item(0).get("holder", 0)) == 0, "trade items can't be picked up in the buy phase")
	# Buy a primary, then open the doors.
	game.player.equip("smg")
	online.time_left = 0.0
	var live: bool = await _wait_until(func() -> bool: return str(online.phase) == "live", 3.0)
	_check(live, "the doors open when the buy timer runs out")
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
	_check(int(online.bank.get(_crew(), -1)) == 0, "the crew bank resets for the new Week")
	_check(int(game.cash) == int(online.START_CASH), "money resets to the starting $%d (got %d)" % [int(online.START_CASH), int(game.cash)])
	_check(game.player.owned.size() == 1 and game.player.owned.has("pistol"), "gear resets to the pistol for the new Week")
	_check(online.recap.size() > 0, "the new Week's first morning paper shows last Week's standings")
