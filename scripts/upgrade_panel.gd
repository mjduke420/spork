extends CanvasLayer

## Right-side panel listing repeatable upgrades. Reactive: rebinds to GameState signals
## and refreshes button labels/affordability whenever biomass or upgrade levels change.

const UpgradeData := preload("res://scripts/upgrade_data.gd")

var _buttons: Dictionary = {}   # id -> Button

func _ready() -> void:
	layer = 10
	_build_ui()
	GameState.biomass_changed.connect(func(_a): _refresh())
	GameState.upgrades_changed.connect(_refresh)
	GameState.evolved.connect(func(_s): _refresh())
	_refresh()

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -288
	panel.offset_right = -12
	panel.offset_top = 12
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.custom_minimum_size = Vector2(276, 0)
	panel.add_child(box)

	var title := Label.new()
	title.text = "UPGRADES"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.85, 1.0, 0.9))
	box.add_child(title)

	for upg in UpgradeData.UPGRADES:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(276, 46)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(_on_buy.bind(upg["id"]))
		box.add_child(btn)
		_buttons[upg["id"]] = btn

	box.add_child(HSeparator.new())
	var reset := Button.new()
	reset.text = "Reset progress"
	reset.custom_minimum_size = Vector2(276, 32)
	reset.pressed.connect(func(): GameState.reset_progress())
	box.add_child(reset)

func _on_buy(id: String) -> void:
	GameState.buy_upgrade(id)

func _refresh() -> void:
	for upg in UpgradeData.UPGRADES:
		var id: String = upg["id"]
		var btn: Button = _buttons[id]
		var level: int = GameState.upgrade_level(id)
		var cost: float = GameState.upgrade_cost(id)
		btn.text = "%s  (Lv.%d)\n%s  —  %s" % [upg["name"], level, upg["desc"], _fmt(cost)]
		btn.disabled = not GameState.can_buy_upgrade(id)

func _fmt(v: float) -> String:
	return "%s biomass" % String.num(floorf(v), 0)
