extends Node

## Sound effects — autoload. A tiny pool of AudioStreamPlayers so overlapping
## triggers (two hostiles dying in the same frame, say) don't cut each other
## off. Currently just the one "bloop" (a reversed pitch-sweep, played on
## eating, killing something, and taking damage), but built to take more
## sounds later without changing the call sites.

const BLOOP := preload("res://sounds/bloop.wav")

const POOL_SIZE := 6

var _pool: Array[AudioStreamPlayer] = []
var _pool_index: int = 0

func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)

## Slight per-play pitch variance keeps repeated bloops (rapid clicking, a
## chain of kills) from sounding like a machine-gunned loop.
func play_bloop(pitch_variance: float = 0.08) -> void:
	var player := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool.size()
	player.stream = BLOOP
	player.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	player.play()
