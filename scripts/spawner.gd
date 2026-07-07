extends Node2D

## Spawns hostiles and food pellets from the screen edges. Composition and rate scale
## with the player's current evolution stage so the world gets more dangerous as you grow.

const Hostile := preload("res://scripts/hostile.gd")
const Food := preload("res://scripts/food.gd")

const MARGIN := 40.0
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
	return maxf(0.6, 1.0 - GameState.stage_index * 0.05)

func _spawn_hostile() -> void:
	var h: Node2D = Hostile.new()
	h.position = _edge_position()
	add_child(h)
	h.setup(_pick_config())

func _spawn_food() -> void:
	var f: Node2D = Food.new()
	f.position = _edge_position()
	add_child(f)
	f.setup(3.0 + GameState.stage_index * 2.0)

func _pick_config() -> Dictionary:
	var stage: int = GameState.stage_index
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
	var f := 1.0 + GameState.stage_index * 0.18
	cfg["hp"] = float(cfg["hp"]) * f
	cfg["reward"] = float(cfg["reward"]) * f
	cfg["bite_biomass"] = float(cfg["bite_biomass"]) * f
	return cfg

func _edge_position() -> Vector2:
	var size := get_viewport_rect().size
	var side := randi() % 4
	match side:
		0: return Vector2(randf() * size.x, -MARGIN)                 # top
		1: return Vector2(size.x + MARGIN, randf() * size.y)         # right
		2: return Vector2(randf() * size.x, size.y + MARGIN)         # bottom
		_: return Vector2(-MARGIN, randf() * size.y)                 # left
