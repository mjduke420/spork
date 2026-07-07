extends "res://scripts/player_cell.gd"

## A small, non-interactive portrait of a player's current evolved form, used in
## the roster HUD (scripts/roster_hud.gd) inside a small SubViewport per row.
##
## Inherits EVERY procedural body/eye drawing routine from PlayerCell unchanged —
## _apply_stage, _rebuild_eyes, _eye_offsets, _draw, and all the _draw_blob/_fish/
## _crab/_octopus/_whale methods are not duplicated here, only overridden away
## from movement/input/combat/networking. A portrait always looks exactly like
## the real in-world avatar because it IS the same drawing code.
##
## Scale is normalized to THUMB_RADIUS regardless of the player's actual evolved
## radius (34 at Protocell up past 140 for a giant) so every roster thumbnail
## reads at a consistent size.

const THUMB_RADIUS := 26.0

func _ready() -> void:
	if state == null:
		state = GameState.local
	is_local = false
	state.evolved.connect(_on_evolved)
	state.hp_changed.connect(_on_hp_changed)
	state.died.connect(_on_died)
	_last_hp = state.hp
	_apply_stage()

func _process(delta: float) -> void:
	_t += delta
	_squish = move_toward(_squish, 0.0, delta * 3.5)
	var norm: float = THUMB_RADIUS / maxf(radius, 1.0)
	var breathe := 1.0 + sin(_t * 2.0) * 0.02
	scale = Vector2.ONE * norm * (breathe + _squish * 0.06)
	queue_redraw()

func _unhandled_input(_event: InputEvent) -> void:
	pass   # portraits don't take clicks
