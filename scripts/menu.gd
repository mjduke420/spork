extends Control

## Host/Join/Solo menu — gates scenes/main.tscn. Mirrors godot-rpg's name-entry +
## Host/Join flow. "Play Solo" needs no Net call at all: GameState already seeds a
## local PlayerState on boot, so going straight to main.tscn is the same
## single-player experience the game has always had.

const MAIN_SCENE := "res://scenes/main.tscn"

var _name_field: LineEdit
var _ip_field: LineEdit
var _status: Label
var _host_btn: Button
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
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.10, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(360, 0)
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var title := Label.new()
	title.text = "SPORK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.7, 1.0, 0.8))
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "an idle evolution battle arena"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.75, 0.8))
	box.add_child(subtitle)

	box.add_child(HSeparator.new())

	_name_field = _labeled_field(box, "Name", "Player")

	var solo_btn := Button.new()
	solo_btn.text = "Play Solo"
	solo_btn.custom_minimum_size = Vector2(0, 44)
	solo_btn.pressed.connect(_on_solo_pressed)
	box.add_child(solo_btn)

	box.add_child(HSeparator.new())

	_host_btn = Button.new()
	_host_btn.text = "Host Game (this machine, port %d)" % Net.PORT
	_host_btn.custom_minimum_size = Vector2(0, 44)
	_host_btn.pressed.connect(_on_host_pressed)
	box.add_child(_host_btn)

	box.add_child(HSeparator.new())

	var ip_label := Label.new()
	ip_label.text = "Host address"
	ip_label.add_theme_font_size_override("font_size", 14)
	ip_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.95))
	box.add_child(ip_label)
	_ip_field = LineEdit.new()
	_ip_field.text = "127.0.0.1"
	_ip_field.custom_minimum_size = Vector2(0, 36)
	box.add_child(_ip_field)

	_join_btn = Button.new()
	_join_btn.text = "Join Game"
	_join_btn.custom_minimum_size = Vector2(0, 44)
	_join_btn.pressed.connect(_on_join_pressed)
	box.add_child(_join_btn)

	# In a browser the server is whatever host served the page (via Caddy's /ws
	# proxy, see Caddyfile) — there's nothing to "host" locally and no address to
	# type, so collapse straight to a one-click "Play".
	if OS.has_feature("web"):
		_host_btn.visible = false
		ip_label.visible = false
		_ip_field.visible = false
		_join_btn.text = "Play"

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	box.add_child(_status)

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

func _on_host_pressed() -> void:
	_status.text = ""
	if Net.host_game(_player_name()):
		get_tree().change_scene_to_file(MAIN_SCENE)
	else:
		_status.text = "Could not start server (port %d busy?)" % Net.PORT

func _on_join_pressed() -> void:
	_status.text = "Connecting..."
	_join_btn.disabled = true
	Net.joined_ok.connect(_on_join_ok, CONNECT_ONE_SHOT)
	Net.connection_failed.connect(_on_join_failed, CONNECT_ONE_SHOT)
	var target: String = _web_server_url() if OS.has_feature("web") else _ip_field.text
	if not Net.join_game(target, _player_name()):
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
