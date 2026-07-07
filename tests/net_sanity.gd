extends Node

## Two-instance networking smoke test (temporary, not part of the shipped game).
## Run via:
##   Godot.exe --headless --path . res://tests/net_sanity.tscn -- --host
##   Godot.exe --headless --path . res://tests/net_sanity.tscn -- --join
## Exercises the real WebSocketMultiplayerPeer host/join roundtrip and the
## request_join -> announce_joined -> GameState.players sync path built in Phase 2.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--host" in args:
		_run_host()
	elif "--join" in args:
		_run_join()
	else:
		print("NET_SANITY: FAIL (pass -- --host or -- --join)")
		get_tree().quit(1)

func _run_host() -> void:
	Net.player_joined.connect(func(id, pname): print("NET_SANITY: host saw player_joined %d %s" % [id, pname]))
	if not Net.host_game("Host"):
		print("NET_SANITY: FAIL (host_game failed)")
		get_tree().quit(1)
		return
	print("NET_SANITY: hosting on port %d" % Net.PORT)
	await get_tree().create_timer(6.0).timeout
	if GameState.players.size() >= 2:
		print("NET_SANITY: PASS (host roster has %d players)" % GameState.players.size())
	else:
		print("NET_SANITY: FAIL (host roster only has %d players)" % GameState.players.size())
	get_tree().quit()

func _run_join() -> void:
	await get_tree().create_timer(1.0).timeout   # give the host a head start
	Net.joined_ok.connect(func(): print("NET_SANITY: client joined_ok, local_id=%d" % Net.local_id))
	Net.connection_failed.connect(func():
		print("NET_SANITY: FAIL (connection_failed)")
		get_tree().quit(1)
	)
	if not Net.join_game("127.0.0.1", "Guest"):
		print("NET_SANITY: FAIL (join_game failed)")
		get_tree().quit(1)
		return
	await get_tree().create_timer(4.0).timeout
	if GameState.players.size() >= 2:
		print("NET_SANITY: PASS (client roster has %d players)" % GameState.players.size())
	else:
		print("NET_SANITY: FAIL (client roster only has %d players)" % GameState.players.size())
	get_tree().quit()
