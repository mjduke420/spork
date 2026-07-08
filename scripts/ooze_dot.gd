extends Node2D

## A single fading ooze droplet dropped behind a moving organism — purely
## decorative flavor (the game's comedic/gross tone). Shrinks and fades out
## over its lifetime, then frees itself. Spawned by player_cell.gd as a
## sibling in the world so it stays put while the player swims away.

const LIFETIME := 1.6

var _age: float = 0.0
var _start_radius: float = 6.0
var _color: Color = Color(0.5, 0.85, 0.55, 0.45)

func setup(start_radius: float, color: Color) -> void:
	_start_radius = start_radius
	_color = color

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var f := _age / LIFETIME
	var r := _start_radius * (1.0 - f * 0.65)
	var c := _color
	c.a *= (1.0 - f)
	draw_circle(Vector2.ZERO, r, c)
