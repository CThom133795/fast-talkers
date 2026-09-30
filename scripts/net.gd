class_name FastNet
extends Node
## Networking layer (stub). Agent A replaces this file with the full implementation
## described in docs/NET_M1_SPEC.md §3. main.gd creates it as the child named "Net".

const PORT: int = 24650
const MAX_PLAYERS: int = 8

var players: Dictionary = {}
var local_name: String = "Player"
var upnp_status: String = ""
var in_match: bool = false


func is_online() -> bool:
	return false


func is_host() -> bool:
	return false
