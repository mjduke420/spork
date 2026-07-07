extends CanvasLayer

## Tab-toggled scoreboard: every connected player's name, current form, biomass
## (a proxy for "who has grown the most"), and kill/death counters. Sorted by
## biomass descending. Rebuilds off GameState.player_added/player_removed and any
## player's biomass/evolved/hp_changed signals (kills/deaths ride along on the
## biomass_changed emitted right beside them — see hostile.gd's take_damage()).

const PlayerState := preload("res://scripts/player_state.gd")

const COL_WIDTHS := [170, 150, 100, 70, 90, 70]

var _panel: PanelContainer
var _list: VBoxContainer
var _open: bool = false

func _ready() -> void:
	layer = 11
	_build_ui()
	GameState.player_added.connect(_on_player_added)
	GameState.player_removed.connect(func(_id): _refresh())
	for peer_id in GameState.players.keys():
		_on_player_added(peer_id)
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		_open = not _open
		_panel.visible = _open
		if _open:
			_refresh()
		get_viewport().set_input_as_handled()

func _on_player_added(peer_id: int) -> void:
	var state: PlayerState = GameState.players.get(peer_id)
	if state == null:
		return
	state.biomass_changed.connect(func(_b): _refresh())
	state.evolved.connect(_refresh)
	state.hp_changed.connect(func(_h, _m): _refresh())
	_refresh()

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(620, 0)
	_panel.visible = false
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "SCOREBOARD   (Tab to close)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 1.0, 0.8))
	vbox.add_child(title)

	vbox.add_child(_make_row(["Name", "Form", "Biomass", "Kills", "PvP Kills", "Deaths"], true))
	vbox.add_child(HSeparator.new())

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	vbox.add_child(_list)

func _make_row(cols: Array, header: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	for i in cols.size():
		var l := Label.new()
		l.text = str(cols[i])
		l.custom_minimum_size = Vector2(COL_WIDTHS[i], 0)
		l.add_theme_font_size_override("font_size", 15 if header else 14)
		var col: Color = Color(0.85, 0.95, 1.0) if header else Color(0.75, 0.85, 0.9)
		l.add_theme_color_override("font_color", col)
		row.add_child(l)
	return row

func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var entries: Array = []
	for peer_id in GameState.players.keys():
		entries.append([peer_id, GameState.players[peer_id]])
	entries.sort_custom(func(a, b): return a[1].biomass > b[1].biomass)
	for pair in entries:
		var peer_id: int = pair[0]
		var state: PlayerState = pair[1]
		var name_str: String = state.player_name
		if peer_id == GameState.local_id:
			name_str += " (you)"
		var form: String = str(state.current_stage().get("name", "?"))
		_list.add_child(_make_row([
			name_str, form, String.num(floorf(state.biomass), 0),
			str(state.kills_hostiles), str(state.kills_players), str(state.deaths),
		], false))
