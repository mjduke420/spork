extends CanvasLayer

## Heads-up display. Purely reactive: it binds to GameState.local signals and never
## polls. Shows biomass, the current stage, a growth meter toward the next
## evolution, and an Evolve button that lights up when affordable. Once the trunk
## ladder is maxed (Googly Fish) it swaps the evolve bar for a 3-button lineage
## picker (Crab / Octopus / Whale).

const EvolutionData := preload("res://scripts/evolution_data.gd")

var _biomass_label: Label
var _stage_label: Label
var _bar: ProgressBar
var _bar_label: Label
var _evolve_btn: Button
var _win_banner: Label
var _hp_bar: ProgressBar
var _pvp_btn: Button
var _toast: Label
var _toast_time: float = 0.0
var _help: Label
var _help_time: float = 7.0
var _lineage_row: HBoxContainer
var _lineage_buttons: Dictionary = {}   # id -> Button
var _bar_stack: VBoxContainer

func _ready() -> void:
	layer = 10
	_build_ui()
	GameState.local.biomass_changed.connect(_on_biomass_changed)
	GameState.local.evolved.connect(_on_evolved)
	GameState.local.hp_changed.connect(_on_hp_changed)
	GameState.local.died.connect(_on_died)
	GameState.local.won.connect(_on_won)
	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)
	_refresh()
	_on_hp_changed(GameState.local.hp, GameState.local.max_hp)

func _build_ui() -> void:
	_biomass_label = _add_label(Vector2(24, 20), 30, Color(0.85, 1.0, 0.9))
	_stage_label = _add_label(Vector2(24, 58), 20, Color(0.7, 0.85, 0.95))

	_hp_bar = ProgressBar.new()
	_hp_bar.position = Vector2(24, 92)
	_hp_bar.custom_minimum_size = Vector2(240, 18)
	_hp_bar.size = Vector2(240, 18)
	_hp_bar.show_percentage = false
	_hp_bar.min_value = 0.0
	add_child(_hp_bar)

	_pvp_btn = Button.new()
	_pvp_btn.position = Vector2(280, 88)
	_pvp_btn.custom_minimum_size = Vector2(130, 26)
	_pvp_btn.toggle_mode = true
	_pvp_btn.button_pressed = GameState.local.pvp_enabled
	_pvp_btn.pressed.connect(_on_pvp_toggled)
	add_child(_pvp_btn)
	_refresh_pvp_button()

	_toast = _add_label(Vector2(24, 118), 20, Color(1.0, 0.5, 0.45))
	_toast.visible = false

	_help = Label.new()
	_help.text = "WASD to move. Click the blob to feed it and grow.  Click enemies to fight them off.\nEvolve googly eyes first!"
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_help.offset_left = -400
	_help.offset_right = 400
	_help.offset_top = 60
	_help.add_theme_font_size_override("font_size", 20)
	_help.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	add_child(_help)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -96
	panel.offset_left = 0
	panel.offset_right = 0
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)

	_bar_stack = VBoxContainer.new()
	_bar_stack.custom_minimum_size = Vector2(560, 0)
	row.add_child(_bar_stack)
	_bar_label = _child_label(_bar_stack, 16, Color(0.9, 0.95, 1.0))
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(560, 26)
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar_stack.add_child(_bar)

	_evolve_btn = Button.new()
	_evolve_btn.custom_minimum_size = Vector2(220, 60)
	_evolve_btn.pressed.connect(_on_evolve_pressed)
	row.add_child(_evolve_btn)

	_lineage_row = HBoxContainer.new()
	_lineage_row.add_theme_constant_override("separation", 16)
	_lineage_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_lineage_row.visible = false
	panel.add_child(_lineage_row)
	for id in EvolutionData.lineage_ids():
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(240, 70)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(_on_choose_lineage.bind(id))
		_lineage_row.add_child(btn)
		_lineage_buttons[id] = btn

	_win_banner = Label.new()
	_win_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_win_banner.offset_top = 120
	_win_banner.add_theme_font_size_override("font_size", 40)
	_win_banner.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
	_win_banner.visible = false
	add_child(_win_banner)

func _add_label(pos: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	add_child(l)
	return l

func _child_label(parent: Node, size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l

# ---- reactions ----

func _on_biomass_changed(_amount: float) -> void:
	_refresh()

func _on_evolved() -> void:
	_refresh()

func _on_won() -> void:
	var display_name: String = GameState.local.current_stage().get("name", "your final form")
	_win_banner.text = "YOU EVOLVED INTO A %s!" % display_name.to_upper()
	_win_banner.visible = true

func _on_hp_changed(hp: float, max_hp: float) -> void:
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp
	_hp_bar.modulate = Color(0.4, 1.0, 0.5).lerp(Color(1.0, 0.4, 0.4), 1.0 - clampf(hp / max_hp, 0.0, 1.0))

func _on_pvp_toggled() -> void:
	GameState.local.pvp_enabled = _pvp_btn.button_pressed
	_refresh_pvp_button()

func _refresh_pvp_button() -> void:
	_pvp_btn.text = "PvP: ON" if GameState.local.pvp_enabled else "PvP: OFF"
	_pvp_btn.modulate = Color(1.0, 0.55, 0.5) if GameState.local.pvp_enabled else Color(0.7, 0.9, 0.8)

func _on_died() -> void:
	_toast.text = "Devoured! Lost half your biomass."
	_toast.visible = true
	_toast_time = 2.5

func _on_player_joined(peer_id: int, pname: String) -> void:
	if peer_id == GameState.local_id:
		return   # don't toast yourself joining
	_toast.text = "%s joined the arena" % pname
	_toast.visible = true
	_toast_time = 3.0

func _on_player_left(_peer_id: int) -> void:
	_toast.text = "A player left the arena"
	_toast.visible = true
	_toast_time = 3.0

func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast.visible = false
	if _help != null and _help_time > 0.0:
		_help_time -= delta
		_help.modulate.a = clampf(_help_time / 2.0, 0.0, 1.0)
		if _help_time <= 0.0:
			_help.queue_free()
			_help = null

func _on_evolve_pressed() -> void:
	GameState.local.evolve()

func _on_choose_lineage(id: String) -> void:
	GameState.local.choose_lineage(id)

func _refresh() -> void:
	var state := GameState.local
	_biomass_label.text = "Biomass: %s" % _fmt(state.biomass)
	_stage_label.text = "Stage: %s   •   %s" % [state.current_stage().get("name", "?"), state.biome_name()]

	if state.awaiting_lineage_choice():
		_bar_stack.visible = false
		_evolve_btn.visible = false
		_lineage_row.visible = true
		_refresh_lineage_buttons()
		return
	_lineage_row.visible = false
	_bar_stack.visible = true
	_evolve_btn.visible = true

	if state.is_max_stage():
		_bar_label.text = "Apex form reached"
		_bar.value = 1.0
		_evolve_btn.text = "MAX"
		_evolve_btn.disabled = true
		return
	var next: Dictionary = state.next_stage()
	var cost := float(next.get("cost", 1.0))
	_bar.value = clampf(state.biomass / cost, 0.0, 1.0)
	_bar_label.text = "Next: %s  (%s / %s)" % [next.get("name", "?"), _fmt(state.biomass), _fmt(cost)]
	_evolve_btn.text = "EVOLVE\n%s" % next.get("name", "?")
	_evolve_btn.disabled = not state.can_evolve()

func _refresh_lineage_buttons() -> void:
	var state := GameState.local
	for id in EvolutionData.lineage_ids():
		var first: Dictionary = EvolutionData.lineage_stage(id, 0)
		var btn: Button = _lineage_buttons[id]
		btn.text = "%s\n%s  —  %s" % [EvolutionData.lineage_display(id), first.get("name", "?"), _fmt(float(first.get("cost", 0.0)))]
		btn.disabled = state.biomass < float(first.get("cost", INF))

func _fmt(v: float) -> String:
	return String.num(floorf(v), 0)
