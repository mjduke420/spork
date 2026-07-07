extends Node2D

## World root. Builds the background, camera, player cell and HUD in code so the
## scene tree stays trivial and everything is driven by GameState. Also owns the
## biome-reactive background tint and camera shake on death.

const PlayerCell := preload("res://scripts/player_cell.gd")
const Hud := preload("res://scripts/hud.gd")
const Spawner := preload("res://scripts/spawner.gd")
const UpgradePanel := preload("res://scripts/upgrade_panel.gd")

const WORLD_CENTER := Vector2(640, 360)
const BG_TOP := Color(0.06, 0.16, 0.20)
const BG_BOTTOM := Color(0.03, 0.08, 0.12)

# One tint per biome (Primordial Pool, Tide Pool, Open Ocean).
const BIOME_TINTS: Array[Color] = [
	Color(0.55, 0.85, 0.6),
	Color(0.5, 0.85, 0.95),
	Color(0.55, 0.65, 1.0),
]

var _cam: Camera2D
var _bg: TextureRect
var _shake: float = 0.0

func _ready() -> void:
	_build_background()

	_cam = Camera2D.new()
	_cam.position = WORLD_CENTER
	add_child(_cam)
	_cam.make_current()

	var player := PlayerCell.new()
	player.position = WORLD_CENTER
	player.name = "PlayerCell"
	add_child(player)

	var spawner := Spawner.new()
	spawner.name = "Spawner"
	add_child(spawner)

	add_child(Hud.new())
	add_child(UpgradePanel.new())

	GameState.biome_changed.connect(_on_biome_changed)
	GameState.died.connect(func(): _shake = 1.0)
	_apply_biome_tint(GameState.biome_index())

func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.0)
		_cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 14.0
	elif _cam.offset != Vector2.ZERO:
		_cam.offset = Vector2.ZERO

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
