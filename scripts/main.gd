extends Node2D

## World root. Builds the background, camera, HUD, and one PlayerCell per entry in
## GameState.players in code so the scene tree stays trivial and everything is
## driven by GameState/Net. Owns the biome-reactive background tint, camera shake
## on death, camera-follow (of the LOCAL player only), and the arena boundary.
## Player spawning/despawning is reactive to GameState.player_added/player_removed,
## and remote players' positions/state arrive via Net.position_updated/state_updated
## (see scripts/net.gd) — this is what makes the world genuinely multiplayer-ready
## rather than just architecturally prepared for it.

const PlayerCell := preload("res://scripts/player_cell.gd")
const Hud := preload("res://scripts/hud.gd")
const Spawner := preload("res://scripts/spawner.gd")
const UpgradePanel := preload("res://scripts/upgrade_panel.gd")
const RosterHud := preload("res://scripts/roster_hud.gd")
const ScoreboardPanel := preload("res://scripts/scoreboard_panel.gd")

const BG_TOP := Color(0.06, 0.16, 0.20)
const BG_BOTTOM := Color(0.03, 0.08, 0.12)

# One tint per biome (Primordial Pool, Tide Pool, Open Ocean).
const BIOME_TINTS: Array[Color] = [
	Color(0.55, 0.85, 0.6),
	Color(0.5, 0.85, 0.95),
	Color(0.55, 0.65, 1.0),
]

# 8 evenly-spaced positions around the arena, reserved for up to GameState.MAX_PLAYERS
# players.
var _spawn_points: Array[Vector2] = []

var _cells: Dictionary = {}   # peer_id -> PlayerCell
var _cam: Camera2D
var _bg: TextureRect
var _player: Node2D   # the LOCAL player's cell, followed by the camera
var _shake: float = 0.0

func _ready() -> void:
	_spawn_points = _build_spawn_points()
	_build_background()

	_cam = Camera2D.new()
	_cam.position = _spawn_points[0]
	add_child(_cam)
	_cam.make_current()

	var spawner := Spawner.new()
	spawner.name = "Spawner"
	add_child(spawner)

	add_child(Hud.new())
	add_child(UpgradePanel.new())
	add_child(RosterHud.new())
	add_child(ScoreboardPanel.new())

	GameState.player_added.connect(_spawn_player)
	GameState.player_removed.connect(_despawn_player)
	for peer_id in GameState.players.keys():
		_spawn_player(peer_id)

	Net.position_updated.connect(_on_position_updated)
	Net.state_updated.connect(_on_state_updated)

	GameState.local.biome_changed.connect(_on_biome_changed)
	GameState.local.died.connect(func(): _shake = 1.0)
	_apply_biome_tint(GameState.local.biome_index())
	queue_redraw()

func _build_spawn_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	var ring := GameState.ARENA_RADIUS * 0.5
	for i in GameState.MAX_PLAYERS:
		var a := TAU * float(i) / float(GameState.MAX_PLAYERS)
		points.append(Vector2(cos(a), sin(a)) * ring)
	return points

func _spawn_player(peer_id: int) -> void:
	if _cells.has(peer_id) or not GameState.players.has(peer_id):
		return
	var idx: int = _cells.size() % _spawn_points.size()
	var cell := PlayerCell.new()
	# Assigned BEFORE add_child: PlayerCell._ready() reads these immediately.
	cell.state = GameState.players[peer_id]
	cell.player_id = peer_id
	cell.is_local = (peer_id == GameState.local_id)
	cell.position = _spawn_points[idx]
	cell.name = "PlayerCell_%d" % peer_id
	_cells[peer_id] = cell
	add_child(cell)
	if cell.is_local:
		_player = cell

func _despawn_player(peer_id: int) -> void:
	if not _cells.has(peer_id):
		return
	var cell: Node2D = _cells[peer_id]
	_cells.erase(peer_id)
	if cell == _player:
		_player = null
	if is_instance_valid(cell):
		cell.queue_free()

func _on_position_updated(peer_id: int, pos: Vector2) -> void:
	if _cells.has(peer_id):
		_cells[peer_id].sync_position(pos)

func _on_state_updated(peer_id: int, snapshot: Dictionary) -> void:
	if GameState.players.has(peer_id):
		GameState.players[peer_id].apply_snapshot(snapshot)

func _process(delta: float) -> void:
	if is_instance_valid(_player):
		_cam.global_position = _player.global_position
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.0)
		_cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 14.0
	elif _cam.offset != Vector2.ZERO:
		_cam.offset = Vector2.ZERO

## A visible ring at ARENA_RADIUS so the movement clamp isn't an invisible wall.
func _draw() -> void:
	draw_arc(Vector2.ZERO, GameState.ARENA_RADIUS, 0.0, TAU, 96, Color(1.0, 1.0, 1.0, 0.25), 6.0, true)

func _on_biome_changed(index: int) -> void:
	_apply_biome_tint(index)

func _apply_biome_tint(index: int) -> void:
	if _bg != null:
		var t: Color = BIOME_TINTS[clampi(index, 0, BIOME_TINTS.size() - 1)]
		create_tween().tween_property(_bg, "modulate", t, 1.0)

func _build_background() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	add_child(layer)
	var grad := Gradient.new()
	grad.set_color(0, BG_TOP)
	grad.set_color(1, BG_BOTTOM)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	_bg = TextureRect.new()
	_bg.texture = tex
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.modulate = BIOME_TINTS[0]
	layer.add_child(_bg)
