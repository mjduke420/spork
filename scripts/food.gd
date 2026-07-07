extends Node2D

## A harmless biomass pellet. Drifts gently and is eaten (biomass + removed) when
## clicked. Expires after a while so pellets don't pile up.

var radius: float = 9.0
var value: float = 5.0
var color: Color = Color(0.55, 0.9, 0.6)

var _drift: Vector2 = Vector2.ZERO
var _t: float = 0.0
var _life: float = 14.0

func setup(pellet_value: float) -> void:
	value = pellet_value
	_drift = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(8.0, 22.0)

func _ready() -> void:
	add_to_group("food")

func _process(delta: float) -> void:
	_t += delta
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	global_position += _drift * delta
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if get_global_mouse_position().distance_to(global_position) <= radius * 1.6:
			GameState.add_biomass(value)
			get_viewport().set_input_as_handled()
			queue_free()

func _draw() -> void:
	var pulse := 1.0 + sin(_t * 4.0) * 0.12
	var fade := clampf(_life / 3.0, 0.2, 1.0)   # dim as it is about to expire
	draw_circle(Vector2.ZERO, radius * pulse, Color(color, fade))
	draw_circle(Vector2(-radius * 0.25, -radius * 0.25), radius * 0.3, Color(1, 1, 1, 0.6 * fade))
