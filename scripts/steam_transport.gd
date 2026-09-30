extends Node
## Optional Steam transport (docs/NETWORK_SECURITY_AND_STEAM.md). UNVALIDATED: written against the
## GodotSteam GDExtension API (Steam singleton + SteamMultiplayerPeer) without a Steam client to test on.
##
## Everything goes through dynamic access (Engine.get_singleton / ClassDB.instantiate / call / connect by
## name), so this file parses and runs with NO extension installed: `available()` is then false and
## `unavailable_reason()` says why in plain words.
##
## Flow (one click each side):
##   host:  host_lobby() -> Steam friends-only lobby tagged game=fast_talkers + build -> SteamMultiplayerPeer
##          host -> FastNet attaches it -> the Steam invite overlay opens so friends can be picked.
##   join:  friend accepts the Steam invite (or right-click > Join Game in the friends list, or the game
##          is launched with +connect_lobby <id>) -> join_requested -> join_lobby(id) -> lobby checks ->
##          SteamMultiplayerPeer client to the lobby owner -> FastNet attaches it.
## The resulting MultiplayerPeer goes through the same FastNet code as ENet: handshake, validation,
## rate limits and kicks all apply unchanged.

## Emitted when a peer is ready to attach (`hosting` true on the host).
signal peer_ready(peer: MultiplayerPeer, hosting: bool)
## Something went wrong; `reason` is plain words for the player.
signal failed(reason: String)
## A Steam invite / "Join Game" was accepted while the game runs (or at launch): FastNet joins it.
signal invite_accepted(lobby_id: int)

## Valve's shared test app "Spacewar". Development only: release builds need your own App ID.
const DEV_APP_ID: int = 480
const GAME_KEY: String = "game"
const GAME_VALUE: String = "fast_talkers"
const BUILD_KEY: String = "build"
## GodotSteam enum values (Steam SDK): LOBBY_TYPE_FRIENDS_ONLY = 1, LOBBY_TYPE_PUBLIC = 2.
const LOBBY_FRIENDS_ONLY: int = 1
const LOBBY_PUBLIC: int = 2

var app_id: int = DEV_APP_ID
var build_tag: String = ""
var max_members: int = 8
var lobby_id: int = 0
var is_lobby_host: bool = false

var _steam: Object = null
var _initialized: bool = false
var _init_error: String = ""
var _peer: MultiplayerPeer = null
var _pending_host: bool = false
var _pending_join: int = 0


## Is the GodotSteam extension present at all?
static func extension_present() -> bool:
	return Engine.has_singleton("Steam") and ClassDB.class_exists("SteamMultiplayerPeer")


## Ready to use: extension present, Steam running and logged in, init succeeded.
func available() -> bool:
	return extension_present() and _ensure_init()


## Plain-language reason Steam cannot be used ("" when it can).
func unavailable_reason() -> String:
	if not Engine.has_singleton("Steam"):
		return "Steam add-on not installed"
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		return "Steam multiplayer add-on not installed"
	if not _ensure_init():
		return _init_error if not _init_error.is_empty() else "Steam not running"
	return ""


func _ensure_init() -> bool:
	if _initialized:
		return true
	if not Engine.has_singleton("Steam"):
		return false
	if not _init_error.is_empty():
		return false
	_steam = Engine.get_singleton("Steam")
	# Dev builds: the Steam API reads the app id from steam_appid.txt next to the exe or from these.
	if OS.get_environment("SteamAppId").is_empty():
		OS.set_environment("SteamAppId", str(app_id))
		OS.set_environment("SteamGameId", str(app_id))
	var result: Variant = _call_init()
	var status: int = -1
	if result is Dictionary:
		status = int((result as Dictionary).get("status", -1))
	elif result is bool:
		status = 0 if bool(result) else 1
	elif result is int:
		status = int(result)
	# steamInitEx status 0 = OK; 1 = failed generic; 2 = no Steam client; 3 = client too old.
	if status != 0:
		match status:
			2: _init_error = "Steam not running"
			3: _init_error = "Steam needs an update"
			_: _init_error = "Steam not running (or not logged in)"
		if result is Dictionary and (result as Dictionary).has("verbal"):
			print("[steam] init failed: ", (result as Dictionary)["verbal"])
		return false
	if _steam.call("loggedOn") == false:
		_init_error = "Steam not logged in"
		return false
	_initialized = true
	_connect_signal("lobby_created", _on_lobby_created)
	_connect_signal("lobby_joined", _on_lobby_joined)
	_connect_signal("join_requested", _on_join_requested)
	set_process(true)
	return true


## steamInitEx changed signature across GodotSteam versions: (retrieve_stats, app_id, embed) in older
## 4.x builds, (app_id, embed) in newer ones. Pick by the first argument's name.
func _call_init() -> Variant:
	for method: Dictionary in _steam.get_method_list():
		if String(method.get("name", "")) != "steamInitEx":
			continue
		var args: Array = method.get("args", [])
		if not args.is_empty() and String((args[0] as Dictionary).get("name", "")).contains("stat"):
			return _steam.call("steamInitEx", false, app_id, false)
		return _steam.call("steamInitEx", app_id, false)
	if _steam.has_method("steamInit"):
		return _steam.call("steamInit")
	return -1


func _connect_signal(signal_name: String, callable: Callable) -> void:
	if _steam != null and _steam.has_signal(signal_name) and not _steam.is_connected(signal_name, callable):
		_steam.connect(signal_name, callable)


func _process(_delta: float) -> void:
	if _initialized and _steam != null:
		_steam.call("run_callbacks")


## Launched from an invite: Steam passes "+connect_lobby <id>" on the command line.
func launch_lobby() -> int:
	var args: PackedStringArray = OS.get_cmdline_args()
	for index: int in range(args.size() - 1):
		if args[index] == "+connect_lobby" and args[index + 1].is_valid_int():
			return args[index + 1].to_int()
	return 0


# ------------------------------------------------------------------ host

## Create a lobby and, once Steam confirms it, a hosting SteamMultiplayerPeer.
func host_lobby(friends_only: bool = true) -> Error:
	if not available():
		return ERR_UNAVAILABLE
	close()
	_pending_host = true
	_steam.call("createLobby", LOBBY_FRIENDS_ONLY if friends_only else LOBBY_PUBLIC, max_members)
	return OK


func _on_lobby_created(result: int, new_lobby_id: int) -> void:
	if not _pending_host:
		return
	_pending_host = false
	if result != 1:
		failed.emit("Steam could not create a lobby (code %d)" % result)
		return
	lobby_id = new_lobby_id
	is_lobby_host = true
	_steam.call("setLobbyData", lobby_id, GAME_KEY, GAME_VALUE)
	_steam.call("setLobbyData", lobby_id, BUILD_KEY, build_tag)
	_steam.call("setLobbyJoinable", lobby_id, true)
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	if peer == null:
		failed.emit("Steam multiplayer add-on not installed")
		return
	var err: Variant = peer.call("create_host", 0)
	if err is int and int(err) != OK:
		failed.emit("Steam could not start hosting (error %d)" % int(err))
		return
	_peer = peer
	peer_ready.emit(peer, true)
	invite_friends()


## Open the Steam overlay's "invite friends" dialog for the current lobby.
func invite_friends() -> void:
	if _initialized and lobby_id != 0:
		_steam.call("activateGameOverlayInviteDialog", lobby_id)


# ------------------------------------------------------------------ join

func join_lobby(target_lobby: int) -> Error:
	if target_lobby <= 0:
		return ERR_INVALID_PARAMETER
	if not available():
		return ERR_UNAVAILABLE
	close()
	_pending_join = target_lobby
	_steam.call("joinLobby", target_lobby)
	return OK


func _on_join_requested(target_lobby: int, _friend_id: int) -> void:
	invite_accepted.emit(target_lobby)


func _on_lobby_joined(joined_lobby: int, _permissions: int, _locked: bool, response: int) -> void:
	if joined_lobby != _pending_join:
		return
	_pending_join = 0
	# 1 = k_EChatRoomEnterResponseSuccess
	if response != 1:
		failed.emit("Could not join the Steam lobby (it may be full or closed)")
		return
	lobby_id = joined_lobby
	is_lobby_host = false
	var why: String = check_lobby_data(str(_steam.call("getLobbyData", lobby_id, GAME_KEY)), str(_steam.call("getLobbyData", lobby_id, BUILD_KEY)), build_tag)
	if not why.is_empty():
		failed.emit(why)
		close()
		return
	var owner_id: int = int(_steam.call("getLobbyOwner", lobby_id))
	var my_steam_id: int = int(_steam.call("getSteamID"))
	if owner_id == 0 or owner_id == my_steam_id:
		failed.emit("That Steam lobby has no host")
		close()
		return
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	if peer == null:
		failed.emit("Steam multiplayer add-on not installed")
		return
	var err: Variant = peer.call("create_client", owner_id, 0)
	if err is int and int(err) != OK:
		failed.emit("Could not connect to the host over Steam (error %d)" % int(err))
		close()
		return
	_peer = peer
	peer_ready.emit(peer, false)


## Pure lobby filter (tested headlessly): "" when the lobby is ours and the same build.
static func check_lobby_data(game_value: String, lobby_build: String, our_build: String) -> String:
	if game_value != GAME_VALUE:
		return "That Steam lobby is not a Fast Talkers game"
	if lobby_build != our_build:
		return "Your friend is on a different version of the game — both need the same build"
	return ""


## Leave the lobby. The MultiplayerPeer itself is closed by FastNet.leave().
func close() -> void:
	_pending_host = false
	_pending_join = 0
	if _initialized and lobby_id != 0:
		_steam.call("leaveLobby", lobby_id)
	lobby_id = 0
	is_lobby_host = false
	_peer = null
