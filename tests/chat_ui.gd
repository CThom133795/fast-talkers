extends SceneTree
## Headless checks for the in-match chat overlay (scripts/chat_ui.gd).
## Run: godot --headless --path . --script res://tests/chat_ui.gd

var checks: int = 0
var failures: int = 0
var chat: FastChat
var typing_log: Array[bool] = []
var sent_log: Array[Array] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _key(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func _press(code: Key) -> void:
	chat._input(_key(code))


func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void:
		push_error("chat_ui did not finish in 30 s")
		quit(2))
	var holder: Control = Control.new()
	holder.size = Vector2(1280, 720)
	root.add_child(holder)
	chat = FastChat.new()
	holder.add_child(chat)
	await process_frame
	chat.setup({
		"morris": "MORRIS MAFIA",
		"kingsway": "KINGSWAY ROYALS",
		"solnegro": "CARTEL SOL NEGRO",
		"kojimoto": "KOJIMOTO893",
	}, "morris")
	chat.typing_changed.connect(func(typing: bool) -> void: typing_log.append(typing))
	chat.send_requested.connect(func(channel: String, text: String) -> void: sent_log.append([channel, text]))
	await process_frame

	# Layout basics.
	_check(chat.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Root ignores the mouse")
	_check(chat.feed_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Feed ignores the mouse")
	_check(chat.feed_label.bbcode_enabled, "Feed uses bbcode")
	_check(not chat.line_edit.visible, "Input hidden while closed")
	_check(chat.line_edit.max_length == 160, "Input max length is 160")

	# Open / close.
	_check(not chat.is_typing(), "Starts closed")
	chat.open_chat()
	_check(chat.is_typing() and chat.line_edit.visible, "open_chat opens the box")
	_check(chat.line_edit.has_focus(), "Input box gets focus")
	chat.close_chat()
	_check(not chat.is_typing() and not chat.line_edit.visible, "close_chat closes the box")
	_check(typing_log == [true, false], "typing_changed emitted true then false")
	chat.open_chat()
	chat.open_chat()
	_check(typing_log.size() == 3, "Second open_chat does not re-emit")
	chat.close_chat()
	typing_log.clear()

	# Tab cycling.
	chat.open_chat()
	var seen: Array[String] = [chat.current_channel()]
	for i: int in range(5):
		_press(KEY_TAB)
		seen.append(chat.current_channel())
	_check(seen == ["all", "crew", "call:kingsway", "call:solnegro", "call:kojimoto", "all"], "Tab cycles all, crew, calls, all (got %s)" % str(seen))
	_press(KEY_TAB)
	_press(KEY_TAB)
	_check(chat.tag_label.text == "CALL KINGSWAY ROYALS", "Call tag shows the crew name (got %s)" % chat.tag_label.text)
	chat.close_chat()
	chat.open_chat()
	_check(chat.current_channel() == "call:kingsway", "Last channel is remembered on reopen")
	sent_log.clear()
	chat.line_edit.text = "  hello  "
	_press(KEY_ENTER)
	_check(sent_log == [["call:kingsway", "hello"]], "Enter sends trimmed text on the current channel (got %s)" % str(sent_log))
	_check(not chat.is_typing(), "Box closes after send")
	_check(typing_log == [true, false, true, false], "typing_changed sequence across the session (got %s)" % str(typing_log))

	# Empty text and Escape.
	sent_log.clear()
	chat.open_chat()
	chat.line_edit.text = "    "
	_press(KEY_ENTER)
	_check(sent_log.is_empty() and not chat.is_typing(), "Blank text does not send but closes")
	chat.open_chat()
	chat.line_edit.text = "never sent"
	_press(KEY_ESCAPE)
	_check(sent_log.is_empty() and not chat.is_typing(), "Escape cancels without sending")
	chat.open_chat()
	_check(chat.line_edit.text == "", "Input is empty after reopening")
	chat.close_chat()
	_press(KEY_TAB)
	_check(chat.current_channel() == "call:kingsway", "Keys are ignored while closed")

	# my_crew change drops an invalid remembered channel.
	chat.set_my_crew("kingsway")
	_check(chat.current_channel() == "all", "Channel resets when it becomes my own crew")
	chat.open_chat()
	seen = [chat.current_channel()]
	for i: int in range(5):
		_press(KEY_TAB)
		seen.append(chat.current_channel())
	_check(seen == ["all", "crew", "call:morris", "call:solnegro", "call:kojimoto", "all"], "Cycle excludes my crew after set_my_crew (got %s)" % str(seen))
	chat.close_chat()
	chat.set_my_crew("morris")

	# Lines and formats.
	chat.add_message("Vinny", "morris", "all", "hello world", Color("#c04040"))
	chat.add_message("Vinny", "morris", "crew", "flank left", Color("#c04040"))
	chat.add_message("Vinny", "morris", "call:kingsway", "we talk?", Color("#c04040"))
	chat.add_message("", "", "system", "Kojimoto grabbed the Ledger", Color.WHITE)
	var parsed: String = chat.feed_label.get_parsed_text()
	_check(parsed.contains("Vinny: hello world"), "All line format (got %s)" % parsed)
	_check(parsed.contains("[CREW] Vinny: flank left"), "Crew line format")
	_check(parsed.contains("[CALL→KINGSWAY] Vinny: we talk?"), "Call line format")
	_check(parsed.contains("Kojimoto grabbed the Ledger"), "System line shown")
	_check(not parsed.contains("system"), "System line has no sender tag")

	# bbcode injection.
	var evil: String = "[color=red]x[/color][url]y[/url]"
	chat.add_message("[b]Mallory[/b]", "kingsway", "all", evil, Color.WHITE)
	parsed = chat.feed_label.get_parsed_text()
	_check(parsed.contains(evil), "Injected bbcode in text stays literal (got %s)" % parsed)
	_check(parsed.contains("[b]Mallory[/b]: "), "Injected bbcode in name stays literal")

	# Control characters stripped.
	chat.add_message("Eve", "kingsway", "all", "a" + char(10) + "b" + char(9) + "c" + char(7) + "d" + char(0x202E) + "e", Color.WHITE)
	_check(chat.feed_label.get_parsed_text().contains("Eve: abcde"), "Control and bidi characters are stripped")
	_check(FastChat._sanitize("x".repeat(500), 160).length() == 160, "Sanitize clamps length")

	# Caps: 20 stored, 7 visible.
	chat.messages.clear()
	chat._tick(100.0)
	for i: int in range(30):
		chat.add_message("P", "morris", "all", "line %d" % i, Color.WHITE)
	_check(chat.stored_count() == 20, "Only 20 lines stored (got %d)" % chat.stored_count())
	_check(chat.visible_line_count() == 7, "Only 7 lines visible while closed (got %d)" % chat.visible_line_count())
	_check(chat.feed_label.get_parsed_text().contains("line 29") and not chat.feed_label.get_parsed_text().contains("line 22"), "Visible lines are the newest")
	chat.open_chat()
	_check(chat.visible_line_count() == 20, "20 lines visible while typing (got %d)" % chat.visible_line_count())
	_check(chat.feed_label.get_parsed_text().contains("line 10") and not chat.feed_label.get_parsed_text().contains("line 9\n"), "Typing view shows the last 20")
	chat.close_chat()

	# Fade after 12 s.
	chat.messages.clear()
	chat._tick(1000.0)
	chat.add_message("P", "morris", "all", "old news", Color.WHITE)
	chat._tick(8.0)
	chat.add_message("P", "morris", "all", "fresh", Color.WHITE)
	_check(chat.visible_line_count() == 2, "Both lines visible at 8 s")
	chat._tick(3.9)
	_check(chat.visible_line_count() == 2, "Old line still visible at 11.9 s")
	chat._tick(0.2)
	_check(chat.visible_line_count() == 1 and not chat.feed_label.get_parsed_text().contains("old news"), "Old line gone after 12 s")
	_check(chat.feed_label.get_parsed_text().contains("fresh"), "Newer line still shown")
	chat.open_chat()
	_check(chat.visible_line_count() == 2 and chat.feed_label.get_parsed_text().contains("old news"), "Typing brings back recent lines at full opacity")
	chat.close_chat()
	chat._tick(20.0)
	_check(chat.visible_line_count() == 0 and not chat.feed_label.visible, "Everything faded, feed hidden")
	_check(chat.stored_count() == 2, "Faded lines stay stored for the typing view")

	print("CHAT UI RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
