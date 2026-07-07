extends CanvasLayer

## Left-side panel listing every connected player: a mini avatar (rendered by
## MiniAvatar inside a small SubViewport, so it always matches their real evolved
## form), name, an HP bar, and their current stage/lineage name. Rebuilds
## reactively off GameState.player_added/player_removed and keeps each row fresh
## via that player's own PlayerState signals.

const MiniAvatar := preload("res://scripts/mini_avatar.gd")
const PlayerState := preload("res://scripts/player_state.gd")

const AVATAR_SIZE := 48

var _box: VBoxContainer
var _rows: Dictionary = {}   # peer_id -> {row, name, hp, stage, state}

func _ready() -> void:
	layer = 9
	_build_ui()
	GameState.player_added.connect(_add_row)
	GameState.player_removed.connect(_remove_row)
	for peer_id in GameState.players.keys():
		_add_row(peer_id)

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 24
	panel.offset_top = 148
	add_child(panel)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	_box.custom_minimum_size = Vector2(260, 0)
	panel.add_child(_box)

func _add_row(peer_id: int) -> void:
	if _rows.has(peer_id) or not GameState.players.has(peer_id):
		return
	var state: PlayerState = GameState.players[peer_id]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)

	var vp_container := SubViewportContainer.new()
	vp_container.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	vp_container.stretch = true
	row.add_child(vp_container)

	var vp := SubViewport.new()
	vp.size = Vector2i(AVATAR_SIZE, AVATAR_SIZE)
	vp.transparent_bg = true
	vp_container.add_child(vp)

	var avatar := MiniAvatar.new()
	avatar.state = state
	avatar.position = Vector2(AVATAR_SIZE, AVATAR_SIZE) * 0.5
	vp.add_child(avatar)

	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(180, 0)
	row.add_child(info)

	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	info.add_child(name_label)

	var hp_bar := ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(0, 10)
	hp_bar.show_percentage = false
	info.add_child(hp_bar)

	var stage_label := Label.new()
	stage_label.add_theme_font_size_override("font_size", 12)
	stage_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.9))
	info.add_child(stage_label)

	_rows[peer_id] = {
		"row": row, "name": name_label, "hp": hp_bar, "stage": stage_label, "state": state,
	}
	state.hp_changed.connect(func(_h, _m): _refresh_row(peer_id))
	state.evolved.connect(func(): _refresh_row(peer_id))
	state.biomass_changed.connect(func(_b): _refresh_row(peer_id))
	_refresh_row(peer_id)

func _remove_row(peer_id: int) -> void:
	if not _rows.has(peer_id):
		return
	var e: Dictionary = _rows[peer_id]
	_rows.erase(peer_id)
	if is_instance_valid(e["row"]):
		e["row"].queue_free()

func _refresh_row(peer_id: int) -> void:
	if not _rows.has(peer_id):
		return
	var e: Dictionary = _rows[peer_id]
	var state: PlayerState = e["state"]
	var suffix := "  (you)" if peer_id == GameState.local_id else ""
	e["name"].text = "%s%s" % [state.player_name, suffix]
	e["hp"].max_value = maxf(state.max_hp, 1.0)
	e["hp"].value = state.hp
	e["stage"].text = str(state.current_stage().get("name", "?"))
