extends Node2D

## The player organism. Drawn entirely procedurally from the current stage's trait
## list, so evolving simply flips traits on and the body grows new parts. Clicking
## the body earns biomass, squishes the cell, and makes the googly eyes wobble.
## WASD moves the cell around the arena at a speed set by the current stage.
##
## Owns a `state` reference rather than reading the GameState autoload directly, so
## a future networked peer can be given its own PlayerState and this same script
## keeps working unmodified — today `state` just defaults to the local player.

const GooglyEye := preload("res://scripts/googly_eye.gd")
const EvolutionData := preload("res://scripts/evolution_data.gd")
const PlayerState := preload("res://scripts/player_state.gd")

const BODY_START := Color(0.45, 0.85, 0.55)   # protocell green
const BODY_END := Color(0.36, 0.62, 0.96)     # fish blue

var state: PlayerState
var player_id: int = 0
var is_local: bool = true

var radius: float = 34.0
var _t: float = 0.0
var _squish: float = 0.0
var _eyes: Array[Node2D] = []
var _body_plan: String = "blob"   # "blob", "fish", "crab", "octopus", "whale"
var _spike_timer: float = 0.0
var _last_hp: float = 0.0

const SPIKE_TICK := 0.4       # seconds between spike ticks
const SPIKE_REACH := 1.45     # multiple of radius the spikes cover

const POSITION_REPORT_INTERVAL := 0.05   # ~20Hz
const STATE_REPORT_INTERVAL := 0.5       # ~2Hz — biomass/hp/stage for remote viewers
const REMOTE_LERP_SPEED := 12.0

var _position_report_cd: float = 0.0
var _state_report_cd: float = 0.0
var _remote_target: Vector2 = Vector2.ZERO
var _has_remote_target: bool = false

func _ready() -> void:
	if state == null:
		state = GameState.local
	add_to_group("players")
	state.evolved.connect(_on_evolved)
	state.hp_changed.connect(_on_hp_changed)
	state.died.connect(_on_died)
	_last_hp = state.hp
	_apply_stage()

func _process(delta: float) -> void:
	_t += delta
	_squish = move_toward(_squish, 0.0, delta * 3.5)
	var breathe := 1.0 + sin(_t * 2.0) * 0.02
	scale = Vector2(breathe + _squish * 0.18, breathe - _squish * 0.15)
	if is_local:
		_move(delta)
		_report_network(delta)
	elif _has_remote_target:
		global_position = global_position.lerp(_remote_target, clampf(delta * REMOTE_LERP_SPEED, 0.0, 1.0))
	_update_spikes(delta)
	queue_redraw()

func _move(delta: float) -> void:
	var dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if dir.length() > 1.0:
		dir = dir.normalized()
	if dir == Vector2.ZERO:
		return
	global_position += dir * state.move_speed * delta
	global_position = global_position.limit_length(GameState.ARENA_RADIUS - radius * 0.5)

## Broadcasts this (local) player's position at ~20Hz and full economy/evolution
## state at ~2Hz so remote peers see us move and evolve. No-ops in single-player
## (Net.send_* already checks multiplayer.multiplayer_peer == null).
func _report_network(delta: float) -> void:
	_position_report_cd -= delta
	if _position_report_cd <= 0.0:
		_position_report_cd = POSITION_REPORT_INTERVAL
		Net.send_position(global_position)
	_state_report_cd -= delta
	if _state_report_cd <= 0.0:
		_state_report_cd = STATE_REPORT_INTERVAL
		Net.send_state(state.to_snapshot())

## Called on a REMOTE player's cell when a fresh position arrives over the network.
func sync_position(pos: Vector2) -> void:
	_remote_target = pos
	_has_remote_target = true

func _update_spikes(delta: float) -> void:
	if not state.has_trait("spikes"):
		return
	_spike_timer -= delta
	if _spike_timer > 0.0:
		return
	_spike_timer = SPIKE_TICK
	var reach := radius * SPIKE_REACH
	for h in get_tree().get_nodes_in_group("hostiles"):
		if not is_instance_valid(h):
			continue
		if h.global_position.distance_to(global_position) <= reach + h.radius:
			h.take_damage(state.spike_damage)
			h.knockback((h.global_position - global_position).normalized() * 120.0)
	# Opt-in PvP: only the LOCAL player's own spike tick initiates attacks (each
	# client only acts on its own input/timers), and only against players who —
	# like us — have PvP enabled. The server has final say either way.
	if is_local and state.pvp_enabled:
		for p in get_tree().get_nodes_in_group("players"):
			var other := p as Node2D
			if other == null or other == self or not is_instance_valid(other):
				continue
			if other.state == null or not other.state.pvp_enabled:
				continue
			if other.global_position.distance_to(global_position) <= reach + other.radius:
				Net.send_attack(other.player_id, true)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if get_global_mouse_position().distance_to(global_position) > radius * 1.25:
		return
	if is_local:
		_on_clicked()
	else:
		_try_attack()

## A LOCAL player clicked on ANOTHER player's cell (this one). Only meaningful
## when both sides have opted into PvP; the server re-validates regardless.
func _try_attack() -> void:
	var local_state: PlayerState = GameState.local
	if local_state == null or not local_state.pvp_enabled or not state.pvp_enabled:
		return
	Net.send_attack(player_id, false)

func _on_clicked() -> void:
	state.add_biomass(state.click_value)
	_squish = 1.0
	_kick_eyes(340.0)

func _on_evolved() -> void:
	_apply_stage()
	_squish = 1.0
	_kick_eyes(520.0)

func _on_hp_changed(hp: float, _max_hp: float) -> void:
	# only jolt the eyes when HP actually drops (a hit), not on passive regen
	if hp < _last_hp - 0.01:
		_kick_eyes(220.0)
	_last_hp = hp

func _on_died() -> void:
	_squish = 1.0
	_kick_eyes(800.0)

func _kick_eyes(power: float) -> void:
	for e in _eyes:
		e.bounce(Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, -0.2)).normalized() * power)

# ---------------------------------------------------------------------------

func _apply_stage() -> void:
	var s: Dictionary = state.current_stage()
	radius = float(s.get("radius", 34.0))
	_body_plan = _resolve_body_plan()
	_rebuild_eyes()
	queue_redraw()

func _resolve_body_plan() -> String:
	if state.has_trait("giant_crab") or state.has_trait("crab1"):
		return "crab"
	if state.has_trait("giant_octo") or state.has_trait("octo1"):
		return "octopus"
	if state.has_trait("giant_whale") or state.has_trait("whale1"):
		return "whale"
	if state.has_trait("protofish") or state.has_trait("fish"):
		return "fish"
	return "blob"

func _rebuild_eyes() -> void:
	for e in _eyes:
		e.queue_free()
	_eyes.clear()
	if not state.has_trait("eyes"):
		return
	var sclera := clampf(radius * 0.3, 9.0, 24.0)
	var pupil := sclera * 0.5
	for offset in _eye_offsets():
		var eye := GooglyEye.new()
		eye.position = offset
		add_child(eye)
		eye.setup(sclera, pupil)
		_eyes.append(eye)

func _eye_offsets() -> Array[Vector2]:
	match _body_plan:
		"fish":
			# both eyes crowd the front (right) of the head, comically large
			return [Vector2(radius * 0.42, -radius * 0.28), Vector2(radius * 0.74, -radius * 0.16)]
		"crab":
			# perched high on eye-stalks poking up from the front of the shell
			return [Vector2(radius * 0.3, -radius * 1.15), Vector2(radius * 0.55, -radius * 1.15)]
		"octopus":
			# big and forward on the bulbous head
			return [Vector2(-radius * 0.28, -radius * 0.55), Vector2(radius * 0.28, -radius * 0.55)]
		"whale":
			# small relative to the huge body, low on the sides near the front
			return [Vector2(radius * 0.55, -radius * 0.1), Vector2(radius * 0.78, radius * 0.02)]
		_:
			return [Vector2(-radius * 0.42, -radius * 0.34), Vector2(radius * 0.42, -radius * 0.34)]

# ---------------------------------------------------------------------------

func _draw() -> void:
	var body := BODY_START.lerp(BODY_END, _stage_ratio())
	if state.has_trait("flagellum") and _body_plan != "whale":
		_draw_flagellum(body)
	if state.has_trait("spikes") and _body_plan == "blob":
		_draw_spikes(body.darkened(0.25))
	match _body_plan:
		"fish": _draw_fish(body)
		"crab": _draw_crab(body)
		"octopus": _draw_octopus(body)
		"whale": _draw_whale(body)
		_: _draw_blob(body)
	if state.has_trait("mito") and _body_plan == "blob":
		_draw_mitochondria()

func _stage_ratio() -> float:
	return float(state.stage_index) / float(maxi(EvolutionData.count() - 1, 1))

func _blob_points(r: float, lobes := 3.0, amp := 0.06) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 40
	for i in n:
		var a := TAU * float(i) / float(n)
		var wob := 1.0 + sin(a * lobes + _t * 2.0) * amp
		pts.append(Vector2(cos(a), sin(a)) * r * wob)
	return pts

func _draw_blob(body: Color) -> void:
	if state.has_trait("multi"):
		# extra lobes around the main body for a cell cluster look
		for ang in [0.6, 2.1, 3.7, 5.2]:
			var c := Vector2(cos(ang), sin(ang)) * radius * 0.72
			draw_colored_polygon(_offset(_blob_points(radius * 0.5, 3.0, 0.08), c), body)
	draw_colored_polygon(_blob_points(radius), body)
	if state.has_trait("membrane"):
		draw_polyline(_closed(_blob_points(radius)), body.darkened(0.35), 4.0, true)
	# nucleus
	draw_circle(Vector2.ZERO, radius * 0.28, body.darkened(0.2))

func _draw_fish(body: Color) -> void:
	# elongated body pointing right (+x)
	var pts := PackedVector2Array()
	var n := 44
	for i in n:
		var a := TAU * float(i) / float(n)
		var stretch := Vector2(cos(a) * 1.4, sin(a) * 0.85)
		var wob := 1.0 + sin(a * 2.0 + _t * 2.0) * 0.03
		pts.append(stretch * radius * wob)
	draw_colored_polygon(pts, body)
	if state.has_trait("membrane"):
		draw_polyline(_closed(pts), body.darkened(0.35), 4.0, true)
	# tail fin at the back (-x)
	var tail := radius * 1.35
	var fin := PackedVector2Array([
		Vector2(-tail * 0.9, 0.0),
		Vector2(-tail * 1.5, -radius * 0.7),
		Vector2(-tail * 1.5, radius * 0.7),
	])
	draw_colored_polygon(fin, body.darkened(0.1))
	# top fin
	draw_colored_polygon(PackedVector2Array([
		Vector2(-radius * 0.1, -radius * 0.8), Vector2(radius * 0.5, -radius * 0.8),
		Vector2(radius * 0.2, -radius * 1.25)]), body.darkened(0.1))

func _draw_crab(body: Color) -> void:
	# wide flat shell
	var pts := PackedVector2Array()
	var n := 36
	for i in n:
		var a := TAU * float(i) / float(n)
		var stretch := Vector2(cos(a) * 1.25, sin(a) * 0.75)
		var wob := 1.0 + sin(a * 4.0 + _t * 1.5) * 0.02
		pts.append(stretch * radius * wob)
	draw_colored_polygon(pts, body)
	draw_polyline(_closed(pts), body.darkened(0.35), 3.0, true)
	# claws: an arm line ending in a pincer blob, one per side, snap open/closed slowly
	var snap := 0.15 + absf(sin(_t * 1.6)) * 0.1
	for side in [-1.0, 1.0]:
		var shoulder := Vector2(radius * 1.05 * side, -radius * 0.15)
		var hand := shoulder + Vector2(radius * 0.55 * side, -radius * 0.1)
		draw_line(Vector2(radius * 0.55 * side, -radius * 0.1), shoulder, body.darkened(0.15), 6.0)
		draw_line(shoulder, hand, body.darkened(0.15), 6.0)
		draw_circle(hand, radius * 0.24, body.darkened(0.1))
		var pincer_tip := hand + Vector2(radius * 0.32 * side, -radius * 0.18 - snap * radius)
		draw_line(hand, pincer_tip, body.darkened(0.3), 5.0)
	# eye stalks up to the eye sockets
	for e_off in _eye_offsets():
		draw_line(Vector2(e_off.x, -radius * 0.7), e_off, body.darkened(0.2), 4.0)
	# short legs along the sides
	for i in 3:
		var t := float(i) / 2.0
		var y := lerpf(-radius * 0.35, radius * 0.55, t)
		for side in [-1.0, 1.0]:
			var base := Vector2(radius * 0.9 * side, y)
			var tip := base + Vector2(radius * 0.4 * side, radius * 0.22)
			draw_line(base, tip, body.darkened(0.2), 4.0)

func _draw_octopus(body: Color) -> void:
	# bulbous mantle/head
	var pts := PackedVector2Array()
	var n := 36
	for i in n:
		var a := TAU * float(i) / float(n)
		var stretch := Vector2(cos(a) * 0.95, sin(a) * 1.05)
		var wob := 1.0 + sin(a * 3.0 + _t * 2.0) * 0.04
		pts.append((stretch * radius * wob) + Vector2(0, -radius * 0.15))
	draw_colored_polygon(pts, body)
	if state.has_trait("membrane"):
		draw_polyline(_closed(pts), body.darkened(0.35), 3.0, true)
	# fan of wavy tentacles hanging below the head
	var tentacle_count := 6
	for i in tentacle_count:
		var base_a := lerpf(-1.2, 1.2, float(i) / float(tentacle_count - 1))
		var base := Vector2(sin(base_a) * radius * 0.6, radius * 0.3)
		var tpts := PackedVector2Array()
		var segs := 8
		for s in segs + 1:
			var f := float(s) / float(segs)
			var wave := sin(f * 5.0 - _t * 6.0 + i) * radius * 0.22 * f
			tpts.append(base + Vector2(sin(base_a) * radius * 0.9 * f + wave, radius * 1.1 * f))
		draw_polyline(tpts, body.darkened(0.1), 5.0, true)

func _draw_whale(body: Color) -> void:
	# large rounded elongated body pointing right (+x)
	var pts := PackedVector2Array()
	var n := 44
	for i in n:
		var a := TAU * float(i) / float(n)
		var stretch := Vector2(cos(a) * 1.55, sin(a) * 0.95)
		var wob := 1.0 + sin(a * 2.0 + _t * 1.2) * 0.02
		pts.append(stretch * radius * wob)
	draw_colored_polygon(pts, body)
	if state.has_trait("membrane"):
		draw_polyline(_closed(pts), body.darkened(0.35), 4.0, true)
	# horizontal tail flukes at the back (-x), flattened
	var tail := radius * 1.5
	var fluke_wave := sin(_t * 3.0) * radius * 0.15
	var fin := PackedVector2Array([
		Vector2(-tail * 0.85, 0.0),
		Vector2(-tail * 1.35, -radius * 0.5 + fluke_wave),
		Vector2(-tail * 1.35, radius * 0.5 + fluke_wave),
	])
	draw_colored_polygon(fin, body.darkened(0.1))
	# side flippers
	for side in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([
			Vector2(radius * 0.1, radius * 0.7 * side),
			Vector2(-radius * 0.35, radius * 1.25 * side),
			Vector2(radius * 0.45, radius * 0.85 * side),
		]), body.darkened(0.12))
	# blowhole
	draw_circle(Vector2(radius * 0.55, -radius * 0.85), radius * 0.06, body.darkened(0.4))

func _draw_flagellum(body: Color) -> void:
	var pts := PackedVector2Array()
	var base_x := -radius * 1.1
	var segs := 12
	for i in segs + 1:
		var f := float(i) / float(segs)
		var x := base_x - f * radius * 1.4
		var y := sin(f * 6.0 - _t * 8.0) * radius * 0.4 * f
		pts.append(Vector2(x, y))
	draw_polyline(pts, body.darkened(0.15), 5.0, true)

func _draw_spikes(col: Color) -> void:
	var n := 12
	for i in n:
		var a := TAU * float(i) / float(n)
		var dir := Vector2(cos(a), sin(a))
		var base_a := a + 0.12
		var base_b := a - 0.12
		draw_colored_polygon(PackedVector2Array([
			dir * radius * 1.35,
			Vector2(cos(base_a), sin(base_a)) * radius * 0.95,
			Vector2(cos(base_b), sin(base_b)) * radius * 0.95,
		]), col)

func _draw_mitochondria() -> void:
	var col := Color(0.95, 0.55, 0.35)
	for ang in [0.9, 2.4, 4.0, 5.5]:
		var c := Vector2(cos(ang), sin(ang)) * radius * 0.45
		draw_circle(c, radius * 0.12, col)

# ---- small geometry helpers ----

func _offset(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + by)
	return out

func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	if out.size() > 0:
		out.append(out[0])
	return out
