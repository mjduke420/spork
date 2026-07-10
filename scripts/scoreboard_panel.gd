extends CanvasLayer

## Tab-toggled scoreboard: every connected player's total upgrade level, kills
## (hostiles + players combined), deaths, and food eaten — sorted by kills
## descending, classic scoreboard-style. A live match countdown sits above the
## table (see GameState.match_time_remaining / net.gd for who ticks it and
## what happens at zero). Rebuilds off GameState.player_added/player_removed
## and any player's biomass/evolved/hp_changed/upgrades_changed signals (kills/
## deaths/food_eaten all ride along on one of those — see hostile.gd's
## take_damage(), food.gd, and player_state.gd's take_damage()).

const PlayerState := preload("res://scripts/player_state.gd")

const COL_WIDTHS := [170, 90, 90, 90, 100]

var _panel: PanelContainer
var _timer_label: Label
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

func _process(_delta: float) -> void:
	if _open:
		_timer_label.text = _format_time(GameState.match_time_remaining)

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
	state.upgrades_changed.connect(_refresh)
	_refresh()

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(560, 0)
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

	_timer_label = Label.new()
	_timer_label.text = _format_time(GameState.match_time_remaining)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 16)
	_timer_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	vbox.add_child(_timer_label)

	vbox.add_child(_make_row(["Name", "Level", "Kills", "Deaths", "Food Eaten"], true))
	vbox.add_child(HSeparator.new())

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	vbox.add_child(_list)

func _format_time(seconds: float) -> String:
	var s := maxi(0, int(ceil(seconds)))
	@warning_ignore("integer_division")
	return "Match ends in %02d:%02d" % [s / 60, s % 60]

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
	entries.sort_custom(func(a, b):
		var ka: int = a[1].kills_hostiles + a[1].kills_players
		var kb: int = b[1].kills_hostiles + b[1].kills_players
		return ka > kb)
	for pair in entries:
		var peer_id: int = pair[0]
		var state: PlayerState = pair[1]
		var name_str: String = state.player_name
		if peer_id == GameState.local_id:
			name_str += " (you)"
		var total_kills := state.kills_hostiles + state.kills_players
		_list.add_child(_make_row([
			name_str, str(state.total_upgrade_levels()), str(total_kills),
			str(state.deaths), str(state.food_eaten),
		], false))
