extends Node2D

## Spawns hostiles and food pellets on a ring around the players' current position
## (not the viewport, since the world is a bigger arena the camera pans around).
## Composition and rate scale with the local player's evolution stage so the world
## gets more dangerous as you grow.

const Hostile := preload("res://scripts/hostile.gd")
const Food := preload("res://scripts/food.gd")

const SPAWN_MARGIN := 260.0   # spawn just outside the player's current view
const MAX_HOSTILES := 14

var _hostile_cd: float = 2.0
var _food_cd: float = 1.0

func _process(delta: float) -> void:
	_hostile_cd -= delta
	if _hostile_cd <= 0.0:
		_hostile_cd = randf_range(1.4, 2.8) * _rate_scale()
		if get_tree().get_nodes_in_group("hostiles").size() < MAX_HOSTILES:
			_spawn_hostile()
	_food_cd -= delta
	if _food_cd <= 0.0:
		_food_cd = randf_range(1.0, 2.2)
		if get_tree().get_nodes_in_group("food").size() < 10:
			_spawn_food()

func _rate_scale() -> float:
	# higher stages spawn a little faster (never below ~0.6x interval)
	return maxf(0.6, 1.0 - GameState.local.stage_index * 0.05)

func _spawn_hostile() -> void:
	var h: Node2D = Hostile.new()
	h.position = _spawn_position()
	add_child(h)
	h.setup(_pick_config())

func _spawn_food() -> void:
	var f: Node2D = Food.new()
	f.position = _spawn_position()
	add_child(f)
	f.setup(3.0 + GameState.local.stage_index * 2.0)

func _pick_config() -> Dictionary:
	var stage: int = GameState.local.stage_index
	var roll := randf()
	# apex only starts appearing once you have some defenses
	if stage >= 4 and roll < 0.2:
		return _scaled({
			"kind": Hostile.Kind.APEX, "radius": 34.0, "speed": 34.0,
			"hp": 40.0, "bite_hp": 10.0, "bite_biomass": 30.0, "reward": 45.0,
			"color": Color(0.75, 0.25, 0.45),
		})
	if stage >= 2 and roll < 0.65:
		return _scaled({
			"kind": Hostile.Kind.PREDATOR, "radius": 20.0, "speed": 48.0,
			"hp": 12.0, "bite_hp": 4.0, "bite_biomass": 10.0, "reward": 14.0,
			"color": Color(0.9, 0.42, 0.42),
		})
	return _scaled({
		"kind": Hostile.Kind.GRAZER, "radius": 13.0, "speed": 30.0,
		"hp": 5.0, "bite_hp": 0.0, "bite_biomass": 0.0, "reward": 7.0,
		"color": Color(0.85, 0.8, 0.4),
	})

func _scaled(cfg: Dictionary) -> Dictionary:
	# grow hp/reward gently with stage so late hostiles stay relevant
	var f := 1.0 + GameState.local.stage_index * 0.18
	cfg["hp"] = float(cfg["hp"]) * f
	cfg["reward"] = float(cfg["reward"]) * f
	cfg["bite_biomass"] = float(cfg["bite_biomass"]) * f
	return cfg

## Spawns on a ring just outside the current viewport around the players' average
## position (falls back to the arena center if no player exists yet), clamped
## inside the arena so nothing appears beyond the boundary.
func _spawn_position() -> Vector2:
	var origin := _players_center()
	var view := get_viewport_rect().size
	var dist: float = view.length() * 0.5 + SPAWN_MARGIN
	var ang := randf() * TAU
	var pos := origin + Vector2(cos(ang), sin(ang)) * dist
	return pos.limit_length(GameState.ARENA_RADIUS)

func _players_center() -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for p in get_tree().get_nodes_in_group("players"):
		var node2d := p as Node2D
		if node2d == null:
			continue
		total += node2d.global_position
		count += 1
	if count == 0:
		return Vector2.ZERO
	return total / float(count)
