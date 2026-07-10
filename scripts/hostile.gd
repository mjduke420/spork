extends Node2D

## A hostile microbe. Drifts toward the player (predators/apex) or wanders (grazers),
## bites biomass + HP on contact, takes damage from clicks and from the player's spikes,
## and drops biomass when killed. Drawn procedurally.

enum Kind { GRAZER, PREDATOR, APEX }

var kind: int = Kind.PREDATOR
var radius: float = 18.0
var speed: float = 45.0
var hp: float = 10.0
var max_hp: float = 10.0
var bite_hp: float = 4.0        # HP damage dealt per bite
var bite_biomass: float = 6.0   # biomass stolen per bite
var reward: float = 8.0         # biomass dropped when killed
var color: Color = Color(0.9, 0.42, 0.42)

var _player: Node2D
var _t: float = 0.0
var _bite_cd: float = 0.0
var _flash: float = 0.0
var _wander: Vector2 = Vector2.ZERO
var _knock: Vector2 = Vector2.ZERO
var _retarget_cd: float = 0.0

func setup(config: Dictionary) -> void:
	kind = int(config.get("kind", Kind.PREDATOR))
	radius = float(config.get("radius", 18.0))
	speed = float(config.get("speed", 45.0))
	max_hp = float(config.get("hp", 10.0))
	hp = max_hp
	bite_hp = float(config.get("bite_hp", 4.0))
	bite_biomass = float(config.get("bite_biomass", 6.0))
	reward = float(config.get("reward", 8.0))
	color = config.get("color", color)
	_wander = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()

func _ready() -> void:
	add_to_group("hostiles")
	_retarget()

func _process(delta: float) -> void:
	_t += delta
	_bite_cd = maxf(0.0, _bite_cd - delta)
	_flash = maxf(0.0, _flash - delta * 4.0)
	global_position += _knock * delta
	_knock = _knock.lerp(Vector2.ZERO, clampf(delta * 6.0, 0.0, 1.0))
	global_position = global_position.limit_length(GameState.ARENA_RADIUS)

	_retarget_cd -= delta
	if _retarget_cd <= 0.0 or not is_instance_valid(_player):
		_retarget_cd = 1.0
		_retarget()
	if is_instance_valid(_player):
		_move_and_bite(delta)
	queue_redraw()

## Picks the closest node in the "players" group so hostiles naturally split their
## attention once more than one player exists (only one exists today).
func _retarget() -> void:
	var nearest: Node2D = null
	var best_dist := INF
	for p in get_tree().get_nodes_in_group("players"):
		var node2d := p as Node2D
		if node2d == null:
			continue
		var d: float = node2d.global_position.distance_to(global_position)
		if d < best_dist:
			best_dist = d
			nearest = node2d
	_player = nearest

func _move_and_bite(delta: float) -> void:
	var to_player: Vector2 = _player.global_position - global_position
	var dist := to_player.length()
	var contact: float = radius + _player.radius
	if kind == Kind.GRAZER:
		if _t > 1.5 and randf() < delta:
			_wander = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
		global_position += _wander * speed * delta
	elif dist > contact:
		global_position += to_player.normalized() * speed * delta

	if dist <= contact and _bite_cd <= 0.0 and kind != Kind.GRAZER:
		_bite_cd = 0.8
		var target_state = _player.state
		if randf() < target_state.dodge_chance:
			return   # the player swam clear of the bite
		_flash = 1.0
		target_state.add_biomass(-bite_biomass)
		target_state.take_damage(bite_hp)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if get_global_mouse_position().distance_to(global_position) <= radius * 1.25:
			take_damage(maxf(GameState.local.click_value, 2.0))
			get_viewport().set_input_as_handled()

func take_damage(dmg: float) -> void:
	hp -= dmg
	_flash = 1.0
	if hp <= 0.0:
		# reward whichever player this hostile was engaging (falls back to the
		# local player if it died before ever acquiring a target)
		var payee = _player.state if is_instance_valid(_player) else GameState.local
		payee.add_biomass(reward)
		payee.kills_hostiles += 1
		Sfx.play_bloop()
		queue_free()

func knockback(impulse: Vector2) -> void:
	_knock += impulse

func _draw() -> void:
	var c: Color = color.lerp(Color.WHITE, _flash * 0.7)
	var pts := PackedVector2Array()
	var n := 16
	for i in n:
		var a := TAU * float(i) / float(n)
		var spike := 1.0 if i % 2 == 0 else 0.78   # jagged bacterial rim
		pts.append(Vector2(cos(a), sin(a)) * radius * spike)
	draw_colored_polygon(pts, c)
	draw_circle(Vector2.ZERO, radius * 0.35, c.darkened(0.3))
	if hp < max_hp:
		var w := radius * 1.6
		draw_rect(Rect2(-w * 0.5, -radius - 10.0, w, 4.0), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(-w * 0.5, -radius - 10.0, w * (hp / max_hp), 4.0), Color(0.4, 1.0, 0.5))
