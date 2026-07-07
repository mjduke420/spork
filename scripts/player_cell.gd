extends Node2D

## The player organism. Drawn entirely procedurally from the current stage's trait
## list, so evolving simply flips traits on and the body grows new parts. Clicking
## the body earns biomass, squishes the cell, and makes the googly eyes wobble.

const GooglyEye := preload("res://scripts/googly_eye.gd")
const EvolutionData := preload("res://scripts/evolution_data.gd")

const BODY_START := Color(0.45, 0.85, 0.55)   # protocell green
const BODY_END := Color(0.36, 0.62, 0.96)     # fish blue

var radius: float = 34.0
var _t: float = 0.0
var _squish: float = 0.0
var _eyes: Array[Node2D] = []
var _is_fish: bool = false
var _spike_timer: float = 0.0
var _last_hp: float = 0.0

const SPIKE_TICK := 0.4       # seconds between spike ticks
const SPIKE_REACH := 1.45     # multiple of radius the spikes cover

func _ready() -> void:
	add_to_group("player")
	GameState.evolved.connect(_on_evolved)
	GameState.hp_changed.connect(_on_hp_changed)
	GameState.died.connect(_on_died)
	_last_hp = GameState.hp
	_apply_stage()

func _process(delta: float) -> void:
	_t += delta
	_squish = move_toward(_squish, 0.0, delta * 3.5)
	var breathe := 1.0 + sin(_t * 2.0) * 0.02
	scale = Vector2(breathe + _squish * 0.18, breathe - _squish * 0.15)
	_update_spikes(delta)
	queue_redraw()

func _update_spikes(delta: float) -> void:
	if not GameState.has_trait("spikes"):
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
			h.take_damage(GameState.spike_damage)
			h.knockback((h.global_position - global_position).normalized() * 120.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if get_global_mouse_position().distance_to(global_position) <= radius * 1.25:
			_on_clicked()

func _on_clicked() -> void:
	GameState.add_biomass(GameState.click_value)
	_squish = 1.0
	_kick_eyes(340.0)

func _on_evolved(_stage: int) -> void:
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
	var s: Dictionary = GameState.current_stage()
	radius = float(s.get("radius", 34.0))
	_is_fish = GameState.has_trait("protofish") or GameState.has_trait("fish")
	_rebuild_eyes()
	queue_redraw()

func _rebuild_eyes() -> void:
	for e in _eyes:
		e.queue_free()
	_eyes.clear()
	if not GameState.has_trait("eyes"):
		return
	var sclera := clampf(radius * 0.34, 9.0, 22.0)
	var pupil := sclera * 0.5
	for offset in _eye_offsets():
		var eye := GooglyEye.new()
		eye.position = offset
		add_child(eye)
		eye.setup(sclera, pupil)
		_eyes.append(eye)

func _eye_offsets() -> Array[Vector2]:
	if _is_fish:
		# both eyes crowd the front (right) of the head, comically large
		return [Vector2(radius * 0.42, -radius * 0.28), Vector2(radius * 0.74, -radius * 0.16)]
	return [Vector2(-radius * 0.42, -radius * 0.34), Vector2(radius * 0.42, -radius * 0.34)]

# ---------------------------------------------------------------------------

func _draw() -> void:
	var body := BODY_START.lerp(BODY_END, _stage_ratio())
	if GameState.has_trait("flagellum"):
		_draw_flagellum(body)
	if GameState.has_trait("spikes"):
		_draw_spikes(body.darkened(0.25))
	if _is_fish:
		_draw_fish(body)
	else:
		_draw_blob(body)
	if GameState.has_trait("mito"):
		_draw_mitochondria()

func _stage_ratio() -> float:
	return float(GameState.stage_index) / float(maxi(EvolutionData.count() - 1, 1))

func _blob_points(r: float, lobes := 3.0, amp := 0.06) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 40
	for i in n:
		var a := TAU * float(i) / float(n)
		var wob := 1.0 + sin(a * lobes + _t * 2.0) * amp
		pts.append(Vector2(cos(a), sin(a)) * r * wob)
	return pts

func _draw_blob(body: Color) -> void:
	if GameState.has_trait("multi"):
		# extra lobes around the main body for a cell cluster look
		for ang in [0.6, 2.1, 3.7, 5.2]:
			var c := Vector2(cos(ang), sin(ang)) * radius * 0.72
			draw_colored_polygon(_offset(_blob_points(radius * 0.5, 3.0, 0.08), c), body)
	draw_colored_polygon(_blob_points(radius), body)
	if GameState.has_trait("membrane"):
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
	if GameState.has_trait("membrane"):
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

func _draw_flagellum(body: Color) -> void:
	var pts := PackedVector2Array()
	var base_x := -radius * (1.35 if _is_fish else 0.95)
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
