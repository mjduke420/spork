extends Node

## Net — autoload. Multiplayer transport for Spork, modeled directly on
## godot-rpg/scripts/net.gd: WebSocketMultiplayerPeer, server-authoritative for
## the player roster; trusted-client for movement/economy state (each client owns
## and mutates its own PlayerState locally, then periodically broadcasts a
## snapshot — appropriate for a casual game with friends, not a competitive one
## with anti-cheat requirements; see the plan file for the full phase breakdown).
##
## Phase 2: GameState.players is kept in sync on EVERY peer (not just the server) —
## announce_joined/announce_left both create/erase the roster entry before emitting
## their UI signal, and a newly-joined client is caught up on the existing roster
## before its own announce_joined goes out. Position (~20Hz) and full state (~2Hz)
## are relayed client -> server -> everyone via report_position/report_state.

signal player_joined(peer_id: int, player_name: String)
signal player_left(peer_id: int)
signal joined_ok
signal connection_failed
signal server_disconnected
signal position_updated(peer_id: int, pos: Vector2)
signal state_updated(peer_id: int, snapshot: Dictionary)

const PlayerState := preload("res://scripts/player_state.gd")
const PORT := 8766

var local_id: int = 1
var is_dedicated_server: bool = false

var _pending_name: String = "Player"

# ---- match timer ----
#
# Whoever is "authoritative" (the server, or the local client in solo play —
# there's no server there at all) ticks GameState.match_time_remaining down
# every frame and, on hitting zero, resets everyone for a new 10-minute round.
# Non-authoritative clients just wait for periodic sync_match_timer broadcasts
# rather than ticking their own copy, so displayed time doesn't drift.

const MATCH_TIMER_BROADCAST_INTERVAL := 1.0
var _match_broadcast_cd: float = 0.0

func _process(delta: float) -> void:
	var authoritative := multiplayer.multiplayer_peer == null or multiplayer.is_server()
	if not authoritative:
		return
	GameState.match_time_remaining = maxf(0.0, GameState.match_time_remaining - delta)
	if GameState.match_time_remaining <= 0.0:
		_restart_match()
		return
	if multiplayer.multiplayer_peer == null:
		return
	_match_broadcast_cd -= delta
	if _match_broadcast_cd <= 0.0:
		_match_broadcast_cd = MATCH_TIMER_BROADCAST_INTERVAL
		sync_match_timer.rpc(GameState.match_time_remaining)

@rpc("authority", "call_local", "reliable")
func sync_match_timer(remaining: float) -> void:
	GameState.match_time_remaining = remaining

## Server-only (or solo-local): wipes every player back to a fresh start and
## a new random spawn (player_cell.gd's _on_evolved() notices the stage
## regression and teleports), keeping the running roster/timer going.
func _restart_match() -> void:
	for peer_id in GameState.players.keys():
		var p: PlayerState = GameState.players[peer_id]
		p.reset_for_new_match()
		if multiplayer.multiplayer_peer != null:
			apply_player_reset.rpc(peer_id, p.to_snapshot())
	GameState.match_time_remaining = GameState.MATCH_DURATION

@rpc("authority", "call_local", "reliable")
func apply_player_reset(peer_id: int, snapshot: Dictionary) -> void:
	if GameState.players.has(peer_id):
		GameState.players[peer_id].apply_snapshot(snapshot)

# ---- connection setup ----

func host_game(pname: String) -> bool:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(PORT)
	if err != OK:
		push_error("Spork Net: failed to host (err %d)" % err)
		return false
	multiplayer.multiplayer_peer = peer
	local_id = multiplayer.get_unique_id()   # 1 for the server
	GameState.local_id = local_id
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	var p := GameState.add_player(local_id)
	p.load_local_save()
	p.player_name = pname
	return true

## Dedicated headless server (Docker): hosts the world without the server itself
## being a player — matches godot-rpg's Docker deployment shape.
func start_dedicated_server() -> bool:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(PORT)
	if err != OK:
		push_error("Spork Net: failed to start dedicated server (err %d)" % err)
		return false
	multiplayer.multiplayer_peer = peer
	local_id = multiplayer.get_unique_id()
	GameState.local_id = local_id
	# The dedicated server also self-assigns peer id 1, same as GameState's
	# single-player seed created at boot (GameState._ready()) — discard that seed
	# so the server itself never shows up as a phantom player in the roster.
	GameState.players.clear()
	is_dedicated_server = true
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("Spork dedicated server listening on ws port %d" % PORT)
	return true

func join_game(address: String, pname: String) -> bool:
	var peer := WebSocketMultiplayerPeer.new()
	var url := _normalize_url(address)
	var err := peer.create_client(url)
	if err != OK:
		push_error("Spork Net: failed to join %s (err %d)" % [url, err])
		return false
	multiplayer.multiplayer_peer = peer
	_pending_name = pname
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func(): connection_failed.emit())
	multiplayer.server_disconnected.connect(func(): server_disconnected.emit())
	return true

func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null

func _normalize_url(address: String) -> String:
	var url := address.strip_edges()
	if url.begins_with("ws://") or url.begins_with("wss://"):
		return url
	if url.contains(":"):
		return "ws://" + url
	return "ws://%s:%d" % [url, PORT]

# ---- roster join/leave ----

func _on_connected_to_server() -> void:
	# Discard the single-player seed entry (keyed under the OLD local_id, likely 1
	# — which may well collide with the server's own real peer id) before we learn
	# our real assigned id and the real roster from the server.
	GameState.players.clear()
	local_id = multiplayer.get_unique_id()
	GameState.local_id = local_id
	request_join.rpc_id(1, _pending_name)

@rpc("any_peer", "reliable")
func request_join(pname: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if GameState.players.size() >= GameState.MAX_PLAYERS:
		return   # arena full — the requester simply never gets an entry
	# Catch the newcomer up on everyone already present, and on the match
	# clock already in progress, before announcing them.
	for existing_id in GameState.players.keys():
		announce_joined.rpc_id(sender, existing_id, GameState.players[existing_id].player_name)
	sync_match_timer.rpc_id(sender, GameState.match_time_remaining)
	GameState.add_player(sender)
	announce_joined.rpc(sender, pname)

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	announce_left.rpc(peer_id)

@rpc("authority", "call_local", "reliable")
func announce_joined(peer_id: int, pname: String) -> void:
	var p := GameState.add_player(peer_id)
	p.player_name = pname
	player_joined.emit(peer_id, pname)
	if peer_id == local_id:
		joined_ok.emit()

@rpc("authority", "call_local", "reliable")
func announce_left(peer_id: int) -> void:
	GameState.remove_player(peer_id)
	player_left.emit(peer_id)

# ---- movement + state relay (client -> server -> everyone) ----
#
# send_position()/send_state() are what player_cell.gd calls; they branch so a
# playing host (server + player at once) broadcasts directly instead of routing
# an RPC to itself — Godot short-circuits self-targeted rpc_id() calls into a
# bare local invocation where get_remote_sender_id() is meaningless (0), so the
# host can't rely on report_*() the same way a real remote client does.

func send_position(pos: Vector2) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		relay_position.rpc(local_id, pos)
	else:
		report_position.rpc_id(1, pos)

func send_state(snapshot: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		relay_state.rpc(local_id, snapshot)
	else:
		report_state.rpc_id(1, snapshot)

@rpc("any_peer", "unreliable_ordered")
func report_position(pos: Vector2) -> void:
	if not multiplayer.is_server():
		return
	relay_position.rpc(multiplayer.get_remote_sender_id(), pos)

@rpc("authority", "call_local", "unreliable_ordered")
func relay_position(peer_id: int, pos: Vector2) -> void:
	if peer_id != local_id:
		position_updated.emit(peer_id, pos)

@rpc("any_peer", "reliable")
func report_state(snapshot: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	# The server's own GameState.players copy has no other way to learn a
	# client's reported fields (pvp_enabled, biomass, etc.) — main.gd normally
	# applies state_updated, but a dedicated server never loads main.tscn, so
	# without this the server's copy of every client stays stuck at defaults
	# forever (pvp_enabled=false), silently blocking _resolve_attack/_resolve_contact.
	if GameState.players.has(sender):
		GameState.players[sender].apply_snapshot(snapshot)
	relay_state.rpc(sender, snapshot)

@rpc("authority", "call_local", "reliable")
func relay_state(peer_id: int, snapshot: Dictionary) -> void:
	if peer_id != local_id:
		state_updated.emit(peer_id, snapshot)

# ---- opt-in PvP (Phase 4) ----
#
# Unlike movement/economy state (trusted-client, self-authoritative), combat
# damage is resolved ONLY on the server: it directly touches ANOTHER player's
# state, so the two flags (both sides must have pvp_enabled) are checked here,
# not on the attacking client. send_attack() has the same self-targeted-RPC
# wrapper as send_position()/send_state() for the playing-host case.

func send_attack(target_id: int, via_spike: bool) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_resolve_attack(local_id, target_id, via_spike)
	else:
		request_attack_player.rpc_id(1, target_id, via_spike)

@rpc("any_peer", "reliable")
func request_attack_player(target_id: int, via_spike: bool) -> void:
	if not multiplayer.is_server():
		return
	_resolve_attack(multiplayer.get_remote_sender_id(), target_id, via_spike)

## Server-only: validates both players opted in, applies damage (spike_damage for
## the aura, click_value for a direct click — mirrors how hostiles take damage),
## credits a kill/death on a killing blow, and broadcasts the result to everyone
## (including the attacker, whose own kill count is a server-side mutation they
## have no other way to learn about — see apply_combat_result()).
func _resolve_attack(attacker_id: int, target_id: int, via_spike: bool) -> void:
	if attacker_id == target_id:
		return
	var attacker: PlayerState = GameState.players.get(attacker_id)
	var target: PlayerState = GameState.players.get(target_id)
	if attacker == null or target == null:
		return
	if not attacker.pvp_enabled or not target.pvp_enabled:
		return
	var dmg: float = attacker.spike_damage if via_spike else maxf(attacker.click_value, 2.0)
	_apply_pvp_damage(attacker, target, dmg)
	apply_combat_result.rpc(attacker_id, attacker.to_snapshot(), target_id, target.to_snapshot())

func send_contact(other_id: int) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_resolve_contact(local_id, other_id)
	else:
		request_contact.rpc_id(1, other_id)

@rpc("any_peer", "reliable")
func request_contact(other_id: int) -> void:
	if not multiplayer.is_server():
		return
	_resolve_contact(multiplayer.get_remote_sender_id(), other_id)

## Server-only: mutual body-contact damage between two touching PvP-enabled
## players (distinct from _resolve_attack's one-directional click/spike-aura
## damage — "they should do damage when they touch each other" doesn't require
## either side to click or have spikes). Each side's own spike_damage stat hurts
## the other; both can die from the same contact tick. Only one of the two
## touching clients ever calls this for a given pair (player_cell.gd's
## _update_contact only reports when its own player_id is the lower of the two),
## so contact isn't double-resolved.
func _resolve_contact(a_id: int, b_id: int) -> void:
	if a_id == b_id:
		return
	var a: PlayerState = GameState.players.get(a_id)
	var b: PlayerState = GameState.players.get(b_id)
	if a == null or b == null:
		return
	if not a.pvp_enabled or not b.pvp_enabled:
		return
	_apply_pvp_damage(a, b, a.spike_damage)
	_apply_pvp_damage(b, a, b.spike_damage)
	apply_combat_result.rpc(a_id, a.to_snapshot(), b_id, b.to_snapshot())

## Applies damage from one PlayerState to another and credits a kill on a
## killing blow. Shared by _resolve_attack (one-directional) and _resolve_contact
## (mutual). take_damage() itself restores hp to max_hp as part of any death,
## so its return value — not a before/after hp comparison — is the only
## reliable way to tell whether this specific hit was the killing blow.
func _apply_pvp_damage(attacker: PlayerState, target: PlayerState, dmg: float) -> void:
	if target.take_damage(dmg, true):
		attacker.kills_players += 1

## Broadcast to everyone (call_local so the server/attacker/target all apply it
## the same way) — unlike relay_state, this does NOT skip the local player, since
## a PvP result mutates state neither side computed for themselves.
@rpc("authority", "call_local", "reliable")
func apply_combat_result(attacker_id: int, attacker_snapshot: Dictionary, target_id: int, target_snapshot: Dictionary) -> void:
	if GameState.players.has(attacker_id):
		GameState.players[attacker_id].apply_snapshot(attacker_snapshot)
	if GameState.players.has(target_id):
		GameState.players[target_id].apply_snapshot(target_snapshot)
