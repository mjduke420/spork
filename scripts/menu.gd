extends Control

## Entry menu — gates scenes/main.tscn. Desktop is Solo-only; multiplayer is
## hosted entirely via Docker/Portainer (see DOCKER.md), reached through the Web
## export's one-click "Play". "Play Solo" needs no Net call at all: GameState
## already seeds a local PlayerState on boot, so going straight to main.tscn is
## the same single-player experience the game has always had.

const MAIN_SCENE := "res://scenes/main.tscn"
const GooglyEye := preload("res://scripts/googly_eye.gd")

# Matches the in-game ocean gradient (see main.gd's BG_TOP/BG_BOTTOM) so the menu
# doesn't feel like a different app from the game it launches into.
const BG_TOP := Color(0.06, 0.16, 0.20)
const BG_BOTTOM := Color(0.03, 0.08, 0.12)
const ACCENT := Color(0.45, 0.85, 0.55)   # protocell green, same as player_cell.gd's BODY_START

const EYE_VIEWPORT_SIZE := Vector2i(150, 64)

var _name_field: LineEdit
var _status: Label
var _join_btn: Button

func _ready() -> void:
	# Dedicated-server mode (Docker headless, see Dockerfile's `server` stage):
	# host the world with no menu and no host player, then stop building UI —
	# clients connect over WebSocket from a browser (or another desktop client).
	if _is_server_mode():
		Net.start_dedicated_server()
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _is_server_mode() -> bool:
	return "--server" in OS.get_cmdline_args() or "--server" in OS.get_cmdline_user_args()

func _build_ui() -> void:
	_build_background()

	# CenterContainer (not a raw anchor preset on the box itself) keeps the card
	# truly centered regardless of its size, including the desktop/web difference
	# below (desktop is Solo-only; web adds a "Play" button).
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	center.add_child(card)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)

	_build_eyes(box)

	var title := Label.new()
	title.text = "SPORK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", ACCENT)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "The Amoeba MOBA"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.65, 0.85, 0.9))
	box.add_child(subtitle)

	box.add_child(HSeparator.new())

	_name_field = _labeled_field(box, "Name", "Player")

	var solo_btn := _styled_button("Play Solo")
	solo_btn.pressed.connect(_on_solo_pressed)
	box.add_child(solo_btn)

	# Multiplayer is hosted entirely via Docker/Portainer now (see DOCKER.md) —
	# there's no desktop "Host Game" listen-server anymore, and no manual address
	# to join by hand. The Web export (served by that same Docker deployment) is
	# the only build that needs a join path, and it derives the server address
	# from the page itself via Caddy's /ws proxy, so it's a single click.
	if OS.has_feature("web"):
		box.add_child(HSeparator.new())
		_join_btn = _styled_button("Play")
		_join_btn.pressed.connect(_on_join_pressed)
		box.add_child(_join_btn)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	box.add_child(_status)

## A pair of jiggly googly eyes above the title — reuses googly_eye.gd exactly as
## it's drawn in-game (same trick as mini_avatar.gd), rendered into a small
## SubViewport since this menu is Control-based UI, not a Node2D world.
func _build_eyes(parent: Node) -> void:
	var eyes_center := CenterContainer.new()
	parent.add_child(eyes_center)

	var vp_container := SubViewportContainer.new()
	vp_container.custom_minimum_size = Vector2(EYE_VIEWPORT_SIZE)
	vp_container.stretch = true
	eyes_center.add_child(vp_container)

	var vp := SubViewport.new()
	vp.size = EYE_VIEWPORT_SIZE
	vp.transparent_bg = true
	vp_container.add_child(vp)

	var mid := Vector2(EYE_VIEWPORT_SIZE) * 0.5
	for dx in [-34.0, 34.0]:
		var eye := GooglyEye.new()
		eye.position = mid + Vector2(dx, 4.0)
		vp.add_child(eye)
		eye.setup(28.0, 14.0)

func _build_background() -> void:
	var grad := Gradient.new()
	grad.set_color(0, BG_TOP)
	grad.set_color(1, BG_BOTTOM)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	var bg := TextureRect.new()
	bg.texture = tex
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.13, 0.15, 0.85)
	sb.border_color = Color(0.3, 0.55, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(28)
	return sb

func _styled_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color(0.9, 1.0, 0.95))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.55, 0.55))
	b.add_theme_stylebox_override("normal", _button_style(Color(0.09, 0.22, 0.22), Color(0.35, 0.65, 0.55)))
	b.add_theme_stylebox_override("hover", _button_style(Color(0.13, 0.30, 0.28), Color(0.55, 0.9, 0.7)))
	b.add_theme_stylebox_override("pressed", _button_style(Color(0.07, 0.18, 0.18), Color(0.45, 0.8, 0.65)))
	b.add_theme_stylebox_override("disabled", _button_style(Color(0.08, 0.1, 0.1), Color(0.2, 0.25, 0.25)))
	return b

func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	return sb

func _labeled_field(parent: Node, label_text: String, default_value: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.95))
	parent.add_child(label)
	var field := LineEdit.new()
	field.text = default_value
	field.custom_minimum_size = Vector2(0, 36)
	parent.add_child(field)
	return field

func _player_name() -> String:
	var n := _name_field.text.strip_edges()
	return n if n != "" else "Player"

func _on_solo_pressed() -> void:
	GameState.local.player_name = _player_name()
	get_tree().change_scene_to_file(MAIN_SCENE)

func _on_join_pressed() -> void:
	_status.text = "Connecting..."
	_join_btn.disabled = true
	Net.joined_ok.connect(_on_join_ok, CONNECT_ONE_SHOT)
	Net.connection_failed.connect(_on_join_failed, CONNECT_ONE_SHOT)
	if not Net.join_game(_web_server_url(), _player_name()):
		_on_join_failed()

func _on_join_ok() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)

func _on_join_failed() -> void:
	_status.text = "Connection failed."
	_join_btn.disabled = false

## On web, the game server lives behind the same origin via the Caddy proxy at
## /ws (see Caddyfile) — derive ws(s)://<host>/ws from the page so no manual
## address entry is needed, mirroring godot-rpg's approach exactly.
func _web_server_url() -> String:
	var host := str(JavaScriptBridge.eval("location.host", true))
	var proto := str(JavaScriptBridge.eval("location.protocol", true))
	var scheme := "wss" if proto == "https:" else "ws"
	return "%s://%s/ws" % [scheme, host]
