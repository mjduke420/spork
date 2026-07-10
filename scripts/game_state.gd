extends Node

## Session/match-level autoload. Owns every connected player's PlayerState plus the
## constants that describe the shared world (arena size, player cap). `local` is a
## computed property over `players[local_id]` so every existing `GameState.local.*`
## call site keeps working unchanged whether running single-player (players has one
## entry, local_id == 1) or as a networked client/server (Net.gd populates/clears
## `players` as peers join/leave — see scripts/net.gd).

const PlayerState := preload("res://scripts/player_state.gd")

const MAX_PLAYERS := 8
const ARENA_RADIUS := 1400.0
const MATCH_DURATION := 600.0   # 10 minutes; see Net.gd for the countdown/restart logic

var match_time_remaining: float = MATCH_DURATION

signal player_added(peer_id: int)
signal player_removed(peer_id: int)

var players: Dictionary = {}   # peer_id (int) -> PlayerState
var local_id: int = 1

var local: PlayerState:
	get: return players.get(local_id)

func _ready() -> void:
	var p := PlayerState.new()
	p.load_local_save()
	players[local_id] = p

func _process(delta: float) -> void:
	for p in players.values():
		p.tick(delta)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if local != null:
			local.autosave()

## Called by Net (on every peer, server and clients alike, via the announce_joined
## RPC) whenever a player's roster entry needs to exist. Returns the existing
## PlayerState if one is already registered. Idempotent.
func add_player(peer_id: int) -> PlayerState:
	if players.has(peer_id):
		return players[peer_id]
	var p := PlayerState.new()
	players[peer_id] = p
	player_added.emit(peer_id)
	return p

## Called by Net when a peer disconnects (or its roster entry is otherwise dropped).
func remove_player(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	players.erase(peer_id)
	player_removed.emit(peer_id)
