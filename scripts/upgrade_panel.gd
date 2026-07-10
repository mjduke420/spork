extends CanvasLayer

## Right-side panel listing repeatable upgrades. Reactive: rebinds to GameState signals
## and refreshes button labels/affordability whenever biomass or upgrade levels change.
## Collapsible — clicking the header toggles the button list beneath it.
##
## Each upgrade has its own accent color; a button's background/border lerp from
## a neutral base toward that accent as its level climbs from 0 to MAX_COLOR_LEVEL
## (100), fully solid from there on — a cheap, level-legible way to stop the panel
## from reading as one flat gray block.

const UpgradeData := preload("res://scripts/upgrade_data.gd")

const MAX_COLOR_LEVEL := 100.0
const BASE_BG := Color(0.08, 0.17, 0.17)
const BASE_BORDER := Color(0.28, 0.4, 0.38)

const UPGRADE_COLORS := {
	"click": Color(0.95, 0.55, 0.2),    # Bigger Bite — warm orange, aggression
	"idle": Color(0.4, 0.85, 0.45),     # Metabolism — green, growth
	"hp": Color(0.9, 0.3, 0.3),         # Tough Membrane — red, toughness
	"regen": Color(0.95, 0.45, 0.7),    # Fast Healing — rose, mending
	"spike": Color(0.95, 0.85, 0.25),   # Sharper Spikes — yellow, sharp
	"dodge": Color(0.35, 0.75, 0.95),   # Faster Swim — cyan, water/speed
}

const PANEL_WIDTH := 235

var _buttons: Dictionary = {}   # id -> Button
var _header_btn: Button
var _content: VBoxContainer
var _collapsed: bool = false

func _ready() -> void:
	layer = 10
	_build_ui()
	GameState.local.biomass_changed.connect(func(_a): _refresh())
	GameState.local.upgrades_changed.connect(_refresh)
	GameState.local.evolved.connect(_refresh)
	_refresh()

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -PANEL_WIDTH - 12
	panel.offset_right = -12
	panel.offset_top = 12
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.add_child(box)

	_header_btn = Button.new()
	_header_btn.custom_minimum_size = Vector2(PANEL_WIDTH, 30)
	_header_btn.add_theme_font_size_override("font_size", 17)
	_header_btn.add_theme_color_override("font_color", Color(0.85, 1.0, 0.9))
	_header_btn.pressed.connect(_toggle_collapsed)
	box.add_child(_header_btn)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 5)
	box.add_child(_content)

	for upg in UpgradeData.UPGRADES:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(PANEL_WIDTH, 40)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", Color(0.92, 1.0, 0.95))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		btn.add_theme_color_override("font_disabled_color", Color(0.6, 0.68, 0.66))
		btn.pressed.connect(_on_buy.bind(upg["id"]))
		_content.add_child(btn)
		_buttons[upg["id"]] = btn

	_content.add_child(HSeparator.new())
	var reset := Button.new()
	reset.text = "Reset progress"
	reset.custom_minimum_size = Vector2(PANEL_WIDTH, 28)
	reset.add_theme_font_size_override("font_size", 13)
	reset.pressed.connect(func(): GameState.local.reset())
	_content.add_child(reset)

	_apply_collapsed()

func _toggle_collapsed() -> void:
	_collapsed = not _collapsed
	_apply_collapsed()

func _apply_collapsed() -> void:
	_content.visible = not _collapsed
	_header_btn.text = "%s  UPGRADES" % ("▶" if _collapsed else "▼")

func _on_buy(id: String) -> void:
	GameState.local.buy_upgrade(id)

func _refresh() -> void:
	for upg in UpgradeData.UPGRADES:
		var id: String = upg["id"]
		var btn: Button = _buttons[id]
		var level: int = GameState.local.upgrade_level(id)
		var cost: float = GameState.local.upgrade_cost(id)
		btn.text = "%s  (Lv.%d)\n%s  —  %s" % [upg["name"], level, upg["desc"], _fmt(cost)]
		btn.disabled = not GameState.local.can_buy_upgrade(id)
		btn.add_theme_stylebox_override("normal", _upgrade_stylebox(id, level, "normal"))
		btn.add_theme_stylebox_override("hover", _upgrade_stylebox(id, level, "hover"))
		btn.add_theme_stylebox_override("pressed", _upgrade_stylebox(id, level, "pressed"))
		btn.add_theme_stylebox_override("disabled", _upgrade_stylebox(id, level, "disabled"))

func _upgrade_stylebox(id: String, level: int, variant: String) -> StyleBoxFlat:
	var accent: Color = UPGRADE_COLORS.get(id, Color(0.5, 0.7, 0.6))
	var t := clampf(float(level) / MAX_COLOR_LEVEL, 0.0, 1.0)
	var bg := BASE_BG.lerp(accent.darkened(0.2), t)
	var border := BASE_BORDER.lerp(accent, t)
	match variant:
		"hover":
			bg = bg.lightened(0.12)
			border = border.lightened(0.15)
		"pressed":
			bg = bg.darkened(0.15)
		"disabled":
			bg = bg.darkened(0.35)
			border = border.darkened(0.35)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	return sb

func _fmt(v: float) -> String:
	return "%s biomass" % String.num(floorf(v), 0)
