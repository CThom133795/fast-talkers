class_name FastLobby
extends Control
## Online lobby panel (docs/NET_M1_SPEC.md §3). Main adds it under its HUD canvas and shows it from the
## title menu: `lobby.setup(net)`, then show/hide it. It has two screens: connect (name, HOST GAME,
## address + JOIN) and lobby (players, crew picker, host info, START MATCH / LEAVE). Match start is
## announced by `net.match_started`, not by this panel. It keeps working while hidden.

const Factions = preload("res://scripts/factions.gd")

const CONFIG_PATH: String = "user://net.cfg"
const GOLD: Color = Color("edb965")
const INK: Color = Color("f1e9d6")
const MUTED: Color = Color("93a29f")
const TEAL: Color = Color("76c8bd")
const ALERT: Color = Color("e8806a")
const PANEL_BG: Color = Color(0.05, 0.06, 0.07, 0.94)

## The player pressed BACK on the connect screen (or Esc / B).
signal back_requested()

var net: FastNet = null
## Overrides where name and address are stored (tests point this elsewhere).
var config_path: String = CONFIG_PATH
var status_text: String = ""
var status_is_error: bool = false

var _panel: PanelContainer
var _connect_box: VBoxContainer
var _lobby_box: VBoxContainer
var _name_edit: LineEdit
var _address_edit: LineEdit
var _host_button: Button
var _join_button: Button
var _back_button: Button
## Steam (optional): hidden unless GodotSteam is installed and Steam is running.
var _steam_host_button: Button
var _steam_note: Label
var _invite_button: Button
var _connect_status: Label
var _connect_hint: Label
var _lobby_title: Label
var _lobby_status: Label
var _player_list: VBoxContainer
var _crew_buttons: Dictionary = {}
var _start_button: Button
## Host only: a 3-Day Week instead of 5 (net.week_days).
var _week_toggle: CheckButton
var _leave_button: Button
var _info_label: Label
var _wait_label: Label
var _built: bool = false


## Bind to the network node and build the panel.
func setup(net_node: FastNet) -> void:
	net = net_node
	_load_config()
	if not _built:
		_build()
	net.lobby_changed.connect(_refresh)
	net.upnp_done.connect(_on_upnp_done)
	net.connected.connect(_on_connected)
	net.connection_failed.connect(_on_connection_failed)
	net.server_closed.connect(_on_server_closed)
	net.peer_joined.connect(_on_peer_changed)
	net.peer_left.connect(_on_peer_changed)
	visibility_changed.connect(_on_visibility_changed)
	_refresh()


## Show the panel and put pad focus on its first control.
func open() -> void:
	show()
	_refresh()
	_focus_first.call_deferred()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_on_back_pressed()


# ---------------------------------------------------------------- building

func _build() -> void:
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size.x = 560
	_panel.add_theme_stylebox_override("panel", _style(PANEL_BG, GOLD, 24))
	center.add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	_panel.add_child(root)
	_build_connect(root)
	_build_lobby(root)


func _build_connect(parent: Control) -> void:
	_connect_box = VBoxContainer.new()
	_connect_box.add_theme_constant_override("separation", 10)
	parent.add_child(_connect_box)
	_connect_box.add_child(_label("PLAY ONLINE", 26, GOLD))
	_connect_box.add_child(_label("Host a game for friends, or join theirs. Two to eight players, no bots.", 14, MUTED, true))
	_connect_box.add_child(_label("YOUR NAME", 12, MUTED))
	_name_edit = _line_edit("Player", FastNet.NAME_MAX)
	_name_edit.text_changed.connect(func(_text: String) -> void: _save_config())
	_connect_box.add_child(_name_edit)
	_steam_host_button = _button("HOST ON STEAM  (INVITE FRIENDS)", _on_steam_host_pressed)
	_steam_host_button.visible = false
	_connect_box.add_child(_steam_host_button)
	_steam_note = _label("", 13, MUTED, true)
	_steam_note.visible = false
	_connect_box.add_child(_steam_note)
	_host_button = _button("HOST BY IP  (LAN / DIRECT)", _on_host_pressed)
	_connect_box.add_child(_host_button)
	_connect_box.add_child(HSeparator.new())
	_connect_box.add_child(_label("HOST ADDRESS", 12, MUTED))
	_address_edit = _line_edit("192.168.1.20 or 100.x.x.x  (port 24650 by default)", 64)
	_address_edit.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	_address_edit.text_changed.connect(func(_text: String) -> void: _save_config())
	_connect_box.add_child(_address_edit)
	_join_button = _button("JOIN", _on_join_pressed)
	_connect_box.add_child(_join_button)
	_connect_status = _label("", 14, ALERT, true)
	_connect_box.add_child(_connect_status)
	_connect_hint = _label("No Steam? Same network: join the host's LAN address. Over the internet: the host forwards UDP %d (or both use a VPN such as Tailscale)." % FastNet.PORT, 13, MUTED, true)
	_connect_box.add_child(_connect_hint)
	_back_button = _button("BACK", _on_back_pressed)
	_connect_box.add_child(_back_button)


func _build_lobby(parent: Control) -> void:
	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 10)
	parent.add_child(_lobby_box)
	_lobby_title = _label("LOBBY", 26, GOLD)
	_lobby_box.add_child(_lobby_title)
	_lobby_status = _label("", 14, MUTED, true)
	_lobby_box.add_child(_lobby_status)
	_lobby_box.add_child(_label("PLAYERS", 12, MUTED))
	_player_list = VBoxContainer.new()
	_player_list.add_theme_constant_override("separation", 4)
	_lobby_box.add_child(_player_list)
	_lobby_box.add_child(_label("YOUR CREW", 12, MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_lobby_box.add_child(grid)
	for crew: String in Factions.ORDER:
		var button: Button = _button(String(Factions.get_crew(crew)["name"]), _on_crew_pressed.bind(crew))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(button)
		_crew_buttons[crew] = button
	_week_toggle = CheckButton.new()
	_week_toggle.text = "Quick Week: Wednesday to Friday (3 Days)"
	_week_toggle.add_theme_font_size_override("font_size", 14)
	_week_toggle.toggled.connect(func(on: bool) -> void:
		if net != null:
			net.week_days = 3 if on else 5)
	_lobby_box.add_child(_week_toggle)
	_start_button = _button("START THE WEEK", _on_start_pressed)
	_lobby_box.add_child(_start_button)
	_wait_label = _label("Waiting for the host to start the match...", 14, TEAL, true)
	_lobby_box.add_child(_wait_label)
	_info_label = _label("", 13, MUTED, true)
	_lobby_box.add_child(_info_label)
	_invite_button = _button("INVITE STEAM FRIENDS", _on_invite_pressed)
	_invite_button.visible = false
	_lobby_box.add_child(_invite_button)
	_leave_button = _button("LEAVE", _on_leave_pressed)
	_lobby_box.add_child(_leave_button)


func _label(content: String, font_size: int, color: Color, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 510
	return label


func _line_edit(placeholder: String, max_len: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.max_length = max_len
	edit.custom_minimum_size.y = 44
	edit.add_theme_font_size_override("font_size", 16)
	edit.add_theme_color_override("font_color", INK)
	edit.add_theme_color_override("font_placeholder_color", Color("5d6866"))
	edit.add_theme_stylebox_override("normal", _style(Color("142023"), Color("53645d"), 10))
	edit.add_theme_stylebox_override("focus", _style(Color("142023"), GOLD, 10))
	return edit


func _button(content: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = content
	button.custom_minimum_size.y = 44
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_disabled_color", Color("5d6866"))
	button.add_theme_stylebox_override("normal", _style(Color("1c2d30"), Color("53645d"), 12))
	button.add_theme_stylebox_override("hover", _style(Color("35453d"), GOLD, 12))
	button.add_theme_stylebox_override("focus", _style(Color("35453d"), GOLD, 12))
	button.add_theme_stylebox_override("pressed", _style(Color("4c5040"), GOLD, 12))
	button.add_theme_stylebox_override("disabled", _style(Color("142023"), Color("2c3634"), 12))
	button.pressed.connect(callback)
	return button


func _style(background: Color, border: Color, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


# ---------------------------------------------------------------- refresh

## True when the lobby screen is showing (hosting, or connected as a client).
func showing_lobby() -> bool:
	return net != null and net.is_online()


func _refresh() -> void:
	if net == null or not _built:
		return
	var in_lobby: bool = showing_lobby()
	var was_lobby: bool = _lobby_box.visible
	_connect_box.visible = not in_lobby
	_lobby_box.visible = in_lobby
	if in_lobby:
		_refresh_lobby()
	else:
		_refresh_connect()
	if is_visible_in_tree() and was_lobby != in_lobby:
		_focus_first.call_deferred()


func _refresh_connect() -> void:
	var connecting: bool = net.is_connecting()
	_host_button.disabled = connecting
	_join_button.disabled = connecting
	_name_edit.editable = not connecting
	_address_edit.editable = not connecting
	_join_button.text = "CONNECTING..." if connecting else "JOIN"
	if not connecting and not status_is_error and status_text.begins_with("Connected to"):
		status_text = ""
	if connecting and status_text.is_empty():
		status_text = "Connecting..."
	_connect_status.text = status_text
	_connect_status.add_theme_color_override("font_color", ALERT if status_is_error else TEAL)
	_connect_status.visible = not status_text.is_empty()
	# One Steam button when Steam can be used; otherwise one plain line saying why.
	var steam_reason: String = net.steam_unavailable_reason() if net.has_method("steam_unavailable_reason") else "Steam add-on not installed"
	_steam_host_button.visible = steam_reason.is_empty()
	_steam_host_button.disabled = connecting
	_steam_note.visible = true
	_steam_note.text = "Steam: friends accept your Steam invite, no addresses or ports." if steam_reason.is_empty() else "Steam play unavailable: %s." % steam_reason


func _refresh_lobby() -> void:
	var hosting: bool = net.is_host()
	var me: int = net.my_id()
	_lobby_title.text = "LOBBY" if not net.in_match else "MATCH IN PROGRESS"
	var on_steam: bool = String(net.get("transport")) == "steam"
	if on_steam:
		_lobby_status.text = "You are hosting on Steam." if hosting else "Connected to the host over Steam."
	else:
		_lobby_status.text = "You are hosting on port %d." % _net_port() if hosting else "Connected to the host."
	_invite_button.visible = hosting and on_steam
	if status_text.begins_with("Starting a Steam lobby"):
		status_text = ""
	if not status_text.is_empty():
		_lobby_status.text = status_text
	# Players list.
	for child: Node in _player_list.get_children():
		_player_list.remove_child(child)
		child.queue_free()
	var ids: Array = net.players.keys()
	ids.sort()
	for id: int in ids:
		var entry: Dictionary = net.players[id]
		var crew: String = String(entry.get("crew", Factions.ORDER[0]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var swatch := ColorRect.new()
		swatch.color = Factions.color(crew)
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var text: String = "%s  -  %s" % [String(entry.get("name", "Player")), String(Factions.get_crew(crew)["name"])]
		if id == 1:
			text += "  (host)"
		if id == me:
			text += "  (you)"
		row.add_child(_label(text, 15, INK if id == me else Color("d6cfbd")))
		_player_list.add_child(row)
	# Crew picker highlights the current crew.
	var mine: String = net.crew_of(me)
	for crew: String in _crew_buttons.keys():
		var button: Button = _crew_buttons[crew]
		var color: Color = Factions.color(crew)
		var selected: bool = crew == mine
		button.disabled = net.in_match
		button.add_theme_color_override("font_color", color.lightened(0.25) if selected else INK)
		button.add_theme_stylebox_override("normal", _style(Color("35453d") if selected else Color("1c2d30"), color if selected else Color("53645d"), 12))
	_start_button.visible = hosting
	_week_toggle.visible = hosting and not net.in_match
	_week_toggle.set_pressed_no_signal(net.week_days == 3)
	_start_button.disabled = net.players.size() < 1 or net.in_match
	_wait_label.visible = not hosting
	_wait_label.text = "Match in progress." if net.in_match else "Waiting for the host to start the match..."
	# Host info: addresses, UPnP, hint.
	_info_label.visible = hosting
	if hosting and on_steam:
		_info_label.text = "Friends join by accepting your Steam invite (or right-click you in Steam > Join Game). No addresses or ports needed."
	elif hosting:
		var addresses: PackedStringArray = net.local_addresses()
		var lines: PackedStringArray = PackedStringArray()
		if addresses.is_empty():
			lines.append("Tell friends your address (none found on this PC).")
		else:
			lines.append("Friends join: " + ",  ".join(addresses) + "   (port %d)" % _net_port())
		if not net.upnp_status.is_empty():
			lines.append(net.upnp_status)
		lines.append("Playing over the internet? Both install Tailscale and join the host's 100.x address, or forward UDP %d." % _net_port())
		_info_label.text = "\n".join(lines)


func _focus_first() -> void:
	if not is_visible_in_tree() or net == null or not _built:
		return
	if _lobby_box.visible:
		if _start_button.visible and not _start_button.disabled:
			_start_button.grab_focus()
		else:
			var mine: String = net.crew_of(net.my_id())
			var target: Button = _crew_buttons.get(mine, _leave_button) as Button
			if target.disabled:
				target = _leave_button
			target.grab_focus()
	elif net.is_connecting():
		_back_button.grab_focus()
	elif _steam_host_button.visible and not _steam_host_button.disabled:
		_steam_host_button.grab_focus()
	else:
		_host_button.grab_focus()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_refresh()
		_focus_first.call_deferred()


func _on_upnp_done(_status: String) -> void:
	_refresh()


## The port the network node is actually using (host or client), falling back to the default.
func _net_port() -> int:
	if net != null:
		var used: int = int(net.get("_port"))
		if used > 0:
			return used
	return FastNet.PORT


## The connect-screen "Connecting..." line is replaced once we are in the lobby.
func _on_connected() -> void:
	if net != null and not net.is_host() and not status_is_error:
		var address: String = String(net.get("_address"))
		_set_status("Connected to %s." % address if not address.is_empty() else "Connected to the host.")
	_refresh()


func _on_peer_changed(_id: int) -> void:
	_refresh()


func _on_connection_failed(reason: String) -> void:
	status_text = reason
	status_is_error = true
	_refresh()


func _on_server_closed() -> void:
	status_text = "The host closed the lobby."
	status_is_error = true
	_refresh()


# ---------------------------------------------------------------- actions

func _on_steam_host_pressed() -> void:
	if net == null:
		return
	_apply_name()
	_save_config()
	var err: Error = net.host_steam(true)
	if err == OK:
		_set_status("Starting a Steam lobby... the Steam invite window opens next.")
	else:
		_set_status("Could not host on Steam: %s." % (net.steam_status if not net.steam_status.is_empty() else error_string(err)), true)
	_refresh()


func _on_invite_pressed() -> void:
	if net != null:
		net.invite_steam_friends()


func _on_host_pressed() -> void:
	if net == null:
		return
	_apply_name()
	_save_config()
	var err: Error = net.host()
	if err == OK:
		_set_status("")
	elif err == ERR_CANT_CREATE:
		_set_status("Could not host: port %d is already in use. Is another copy of the game running?" % FastNet.PORT, true)
	else:
		_set_status("Could not start hosting (%s)." % error_string(err), true)
	_refresh()


func _on_join_pressed() -> void:
	if net == null or net.is_connecting():
		return
	var address: String = _address_edit.text.strip_edges()
	if address.is_empty():
		_set_status("Type the host's address first (for example 192.168.1.20).", true)
		_refresh()
		return
	_apply_name()
	_save_config()
	var err: Error = net.join(address)
	if err == OK:
		_set_status("Connecting to %s..." % address)
	else:
		_set_status("That address does not look right (%s)." % error_string(err), true)
	_refresh()


func _on_crew_pressed(crew: String) -> void:
	if net != null:
		net.request_crew(crew)


func _on_start_pressed() -> void:
	if net != null and net.is_host():
		net.request_start()


func _on_leave_pressed() -> void:
	if net != null:
		net.leave()
	_set_status("")
	_refresh()


func _on_back_pressed() -> void:
	if net != null and (net.is_online() or net.is_connecting()):
		# Inside a lobby or mid-connect, back means leave (and stay on the connect screen).
		_on_leave_pressed()
		return
	back_requested.emit()


func _set_status(text: String, is_error: bool = false) -> void:
	status_text = text
	status_is_error = is_error


func _apply_name() -> void:
	net.local_name = FastNet.clean_name(_name_edit.text)
	_name_edit.text = net.local_name


# ---------------------------------------------------------------- persistence

func _load_config() -> void:
	var cfg := ConfigFile.new()
	var saved_name: String = ""
	var saved_address: String = ""
	if cfg.load(config_path) == OK:
		saved_name = String(cfg.get_value("net", "name", ""))
		saved_address = String(cfg.get_value("net", "address", ""))
	if saved_name.is_empty():
		saved_name = OS.get_environment("USERNAME")
	saved_name = FastNet.clean_name(saved_name)
	if not _built:
		_build()
	_name_edit.text = saved_name
	_address_edit.text = saved_address
	net.local_name = saved_name


func _save_config() -> void:
	if not _built:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("net", "name", FastNet.clean_name(_name_edit.text))
	cfg.set_value("net", "address", _address_edit.text.strip_edges())
	cfg.save(config_path)
