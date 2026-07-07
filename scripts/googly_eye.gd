extends Node2D

## A single googly eye: a white sclera with a black pupil simulated as a damped
## spring point. Gravity drags the pupil down and clicks/hits add impulses, so it
## lags, sways and jiggles. This is the comedic centerpiece and rides along onto
## every later form (including the fish).

@export var sclera_radius: float = 11.0
@export var pupil_radius: float = 5.0

const GRAVITY := 900.0        # pulls the pupil toward the bottom of the eye
const SPRING := 55.0          # pulls it back toward center
const DAMPING := 6.0          # velocity decay per second
const RIM_BOUNCE := 0.35      # energy kept when the pupil hits the sclera rim

var _pupil: Vector2 = Vector2.ZERO
var _vel: Vector2 = Vector2.ZERO

func setup(sclera: float, pupil: float) -> void:
	sclera_radius = sclera
	pupil_radius = pupil
	queue_redraw()

func bounce(impulse: Vector2) -> void:
	_vel += impulse

func _process(delta: float) -> void:
	_vel.y += GRAVITY * delta
	_vel -= _pupil * SPRING * delta
	_vel *= 1.0 - clampf(DAMPING * delta, 0.0, 1.0)
	_pupil += _vel * delta

	var max_off := sclera_radius - pupil_radius
	if _pupil.length() > max_off:
		var n := _pupil.normalized()
		_pupil = n * max_off
		_vel = _vel.bounce(n) * RIM_BOUNCE
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, sclera_radius, Color.WHITE)
	draw_circle(Vector2.ZERO, sclera_radius, Color(0, 0, 0, 0.55), false, 2.0, true)
	draw_circle(_pupil, pupil_radius, Color(0.05, 0.05, 0.08))
	# tiny catch-light so the eye reads as glassy
	draw_circle(_pupil + Vector2(-pupil_radius * 0.3, -pupil_radius * 0.3), pupil_radius * 0.35, Color(1, 1, 1, 0.7))
