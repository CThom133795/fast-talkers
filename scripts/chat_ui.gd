class_name FastChat
extends Control
## In-match text chat overlay: a fading feed at the bottom-left plus a one-line input box.
## The lead wires it up: `add_message()` for every received chat/system line, `open_chat()` on the
## chat key, `send_requested` out to the network layer, and mouse/controls on `typing_changed`.
## Channels: "all", "crew", "call:<crew_id>" (phone another crew) and "system" (game events).

## Emitted when the input box opens (true) or closes (false).
signal typing_changed(typing: bool)
## Emitted on Enter with non-empty trimmed text. The box closes right after.
signal send_requested(channel: String, text: String)

const MAX_LENGTH: int = 160
const MAX_STORED: int = 20
const MAX_VISIBLE: int = 7
const FADE_AFTER: float = 12.0
const FADE_TIME: float = 1.5
const MAX_NAME_LENGTH: int = 24
const FONT_SIZE: int = 15

const TEXT_COLOR: Color = Color("#f1e9d6")
const MUTED_COLOR: Color = Color("#93a29f")
const GOLD_COLOR: Color = Color("#edb965")
const TEAL_COLOR: Color = Color("#76c8bd")

var crew_names: Dictionary = {}
var my_crew: String = ""
## Stored lines, oldest first: {name, crew, channel, text, color, t}.
var messages: Array[Dictionary] = []
var feed_label: RichTextLabel
var line_edit: LineEdit
var tag_label: Label

var _channel: String = "all"
var _typing: bool = false
var _clock: float = 0.0
var _panel: PanelContainer
var _input_row: HBoxContainer
var _last_bbcode: String = ""
var _style_typing: StyleBoxFlat
var _style_idle: StyleBoxEmpty


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh_tag()
	_refresh_feed()


## Tell the chat which crews exist (id -> display name) and which one we belong to.
func setup(names: Dictionary, my: String) -> void:
	crew_names = names.duplicate()
	my_crew = my
	if not _channel_list().has(_channel):
		_channel = "all"
	_refresh_tag()
	_refresh_feed()


func set_my_crew(crew: String) -> void:
	my_crew = crew
	if not _channel_list().has(_channel):
		_channel = "all"
	_refresh_tag()
	_refresh_feed()


## Append a line to the feed. `channel` is "all", "crew", "call:<crew_id>" or "system".
func add_message(sender_name: String, sender_crew: String, channel: String, text: String, sender_color: Color) -> void:
	var clean_text: String = _sanitize(text, MAX_LENGTH)
	if clean_text.is_empty():
		return
	messages.append({
		"name": _sanitize(sender_name, MAX_NAME_LENGTH),
		"crew": sender_crew,
		"channel": channel,
		"text": clean_text,
		"color": sender_color,
		"t": _clock,
	})
	while messages.size() > MAX_STORED:
		messages.pop_front()
	_refresh_feed()


func open_chat() -> void:
	if _typing:
		return
	_typing = true
	line_edit.text = ""
	_set_input_visible(true)
	_apply_panel_style()
	_refresh_tag()
	_refresh_feed()
	if line_edit.is_inside_tree():
		line_edit.grab_focus()
	typing_changed.emit(true)


func close_chat() -> void:
	if not _typing:
		return
	_typing = false
	line_edit.text = ""
	line_edit.release_focus()
	_set_input_visible(false)
	_apply_panel_style()
	_refresh_feed()
	typing_changed.emit(false)


func is_typing() -> bool:
	return _typing


## The channel the next message will go to ("all", "crew" or "call:<crew_id>").
func current_channel() -> String:
	return _channel


## Number of stored lines (capped at MAX_STORED).
func stored_count() -> int:
	return messages.size()


## Number of lines currently shown in the feed.
func visible_line_count() -> int:
	return _visible_lines().size()


## Advance the fade clock. `_process` calls this; tests call it directly.
func _tick(seconds: float) -> void:
	_clock += seconds
	_refresh_feed()


func _process(delta: float) -> void:
	_tick(delta)


func _input(event: InputEvent) -> void:
	if not _typing:
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ESCAPE:
			close_chat()
			get_viewport().set_input_as_handled()
		KEY_TAB:
			_cycle_channel()
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			_submit()
			get_viewport().set_input_as_handled()


func _submit() -> void:
	if not _typing:
		return
	var text: String = _sanitize(line_edit.text, MAX_LENGTH).strip_edges()
	var channel: String = _channel
	close_chat()
	if text.is_empty():
		return
	send_requested.emit(channel, text)


func _on_text_submitted(_text: String) -> void:
	_submit()


func _cycle_channel() -> void:
	var list: PackedStringArray = _channel_list()
	var index: int = list.find(_channel)
	_channel = list[(index + 1) % list.size()]
	_refresh_tag()


## all -> crew -> call:<each other crew, in crew_names order> -> all.
func _channel_list() -> PackedStringArray:
	var list: PackedStringArray = PackedStringArray(["all", "crew"])
	for id: Variant in crew_names.keys():
		if str(id) != my_crew:
			list.append("call:" + str(id))
	return list


func _crew_display(id: String) -> String:
	return str(crew_names.get(id, id.to_upper()))


func _refresh_tag() -> void:
	if tag_label == null:
		return
	if _channel == "crew":
		tag_label.text = "CREW"
		tag_label.add_theme_color_override("font_color", TEAL_COLOR)
	elif _channel.begins_with("call:"):
		tag_label.text = "CALL " + _crew_display(_channel.substr(5))
		tag_label.add_theme_color_override("font_color", GOLD_COLOR)
	else:
		tag_label.text = "ALL"
		tag_label.add_theme_color_override("font_color", TEXT_COLOR)


## Strip control characters (and bidi overrides), then clamp the length.
static func _sanitize(text: String, max_len: int) -> String:
	var out: String = ""
	for i: int in range(text.length()):
		var code: int = text.unicode_at(i)
		if code < 32 or code == 127 or (code >= 0x80 and code < 0xA0):
			continue
		if (code >= 0x202A and code <= 0x202E) or (code >= 0x2066 and code <= 0x2069) or code == 0x200E or code == 0x200F:
			continue
		out += text[i]
		if out.length() >= max_len:
			break
	return out


## Make user text safe for a bbcode RichTextLabel: "[" can never open a tag.
static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _age(message: Dictionary) -> float:
	return _clock - float(message["t"])


## The lines that should be on screen right now, oldest first.
func _visible_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _typing:
		var start: int = maxi(0, messages.size() - MAX_STORED)
		for i: int in range(start, messages.size()):
			out.append(messages[i])
		return out
	for message: Dictionary in messages:
		if _age(message) < FADE_AFTER:
			out.append(message)
	while out.size() > MAX_VISIBLE:
		out.pop_front()
	return out


func _line_bbcode(message: Dictionary, alpha: float) -> String:
	var text_c: String = _tint(TEXT_COLOR, alpha)
	var text: String = _escape(str(message["text"]))
	var channel: String = str(message["channel"])
	if channel == "system":
		return "[i][color=%s]%s[/color][/i]" % [_tint(GOLD_COLOR.lerp(MUTED_COLOR, 0.35), alpha), text]
	var prefix: String = ""
	if channel == "crew":
		prefix = "[color=%s][lb]CREW][/color] " % _tint(TEAL_COLOR, alpha)
	elif channel.begins_with("call:"):
		var short: String = _crew_display(channel.substr(5)).split(" ")[0]
		prefix = "[color=%s][lb]CALL→%s][/color] " % [_tint(GOLD_COLOR, alpha), _escape(short)]
	var name_c: String = _tint(message["color"] as Color, alpha)
	return "%s[color=%s]%s[/color]: [color=%s]%s[/color]" % [prefix, name_c, _escape(str(message["name"])), text_c, text]


func _tint(color: Color, alpha: float) -> String:
	return Color(color.r, color.g, color.b, color.a * alpha).to_html(true)


func _refresh_feed() -> void:
	if feed_label == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	for message: Dictionary in _visible_lines():
		var alpha: float = 1.0
		if not _typing:
			alpha = clampf((FADE_AFTER - _age(message)) / FADE_TIME, 0.0, 1.0)
			alpha = roundf(alpha * 16.0) / 16.0
		lines.append(_line_bbcode(message, alpha))
	var bbcode: String = "\n".join(lines)
	if bbcode == _last_bbcode:
		return
	_last_bbcode = bbcode
	feed_label.text = bbcode
	feed_label.visible = not lines.is_empty()


func _set_input_visible(shown: bool) -> void:
	tag_label.visible = shown
	line_edit.visible = shown


func _apply_panel_style() -> void:
	_panel.add_theme_stylebox_override("panel", _style_typing if _typing else _style_idle)


func _build() -> void:
	_style_typing = StyleBoxFlat.new()
	_style_typing.bg_color = Color(0.03, 0.04, 0.05, 0.62)
	_style_typing.set_corner_radius_all(4)
	_style_typing.set_content_margin_all(8)
	_style_idle = StyleBoxEmpty.new()
	_style_idle.set_content_margin_all(8)

	# Bottom-left block: ~x 8..544, feed lines end near y 600 in a 1280x720 canvas, input row below.
	_panel = PanelContainer.new()
	_panel.name = "ChatPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 8.0
	_panel.offset_right = 544.0
	_panel.offset_top = -288.0
	_panel.offset_bottom = -80.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", 4)
	_panel.add_child(column)

	feed_label = RichTextLabel.new()
	feed_label.name = "Feed"
	feed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed_label.bbcode_enabled = true
	feed_label.fit_content = true
	feed_label.scroll_active = false
	feed_label.selection_enabled = false
	feed_label.context_menu_enabled = false
	feed_label.shortcut_keys_enabled = false
	feed_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed_label.add_theme_color_override("default_color", TEXT_COLOR)
	feed_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	feed_label.add_theme_constant_override("outline_size", 3)
	for font_size_name: String in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		feed_label.add_theme_font_size_override(font_size_name, FONT_SIZE)
	column.add_child(feed_label)

	_input_row = HBoxContainer.new()
	_input_row.name = "InputRow"
	_input_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_input_row.custom_minimum_size = Vector2(0, 28)
	_input_row.add_theme_constant_override("separation", 8)
	column.add_child(_input_row)

	tag_label = Label.new()
	tag_label.name = "ChannelTag"
	tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag_label.add_theme_font_size_override("font_size", FONT_SIZE)
	tag_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	tag_label.add_theme_constant_override("outline_size", 3)
	_input_row.add_child(tag_label)

	line_edit = LineEdit.new()
	line_edit.name = "Input"
	line_edit.max_length = MAX_LENGTH
	line_edit.placeholder_text = "Say something (Tab: channel, Enter: send, Esc: cancel)"
	line_edit.context_menu_enabled = false
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.add_theme_font_size_override("font_size", FONT_SIZE)
	line_edit.add_theme_color_override("font_color", TEXT_COLOR)
	line_edit.add_theme_color_override("font_placeholder_color", MUTED_COLOR)
	line_edit.add_theme_color_override("caret_color", GOLD_COLOR)
	var edit_style: StyleBoxFlat = StyleBoxFlat.new()
	edit_style.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	edit_style.border_color = GOLD_COLOR
	edit_style.set_border_width_all(1)
	edit_style.set_content_margin_all(4)
	line_edit.add_theme_stylebox_override("normal", edit_style)
	line_edit.add_theme_stylebox_override("focus", edit_style)
	line_edit.text_submitted.connect(_on_text_submitted)
	_input_row.add_child(line_edit)

	_set_input_visible(false)
	_apply_panel_style()
