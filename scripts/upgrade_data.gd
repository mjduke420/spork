extends RefCounted

## Repeatable stat upgrades bought with biomass. Each level multiplies the cost by
## `growth`. `per_level` is how much of the effect one level grants. Referenced via
## preload (const UpgradeData) by GameState and the upgrade panel.

const UPGRADES: Array[Dictionary] = [
	{"id": "click", "name": "Bigger Bite", "desc": "+1 biomass per click", "base_cost": 50.0, "growth": 1.55, "per_level": 1.0},
	{"id": "idle", "name": "Metabolism", "desc": "+3 idle biomass/sec", "base_cost": 150.0, "growth": 1.6, "per_level": 3.0},
	{"id": "hp", "name": "Tough Membrane", "desc": "+10 max HP", "base_cost": 120.0, "growth": 1.55, "per_level": 10.0},
	{"id": "regen", "name": "Fast Healing", "desc": "+1 HP regen/sec", "base_cost": 180.0, "growth": 1.6, "per_level": 1.0},
	{"id": "spike", "name": "Sharper Spikes", "desc": "+2 spike damage", "base_cost": 260.0, "growth": 1.6, "per_level": 2.0},
	{"id": "dodge", "name": "Faster Swim", "desc": "+5% dodge chance", "base_cost": 300.0, "growth": 1.7, "per_level": 0.05},
]

static func get_def(id: String) -> Dictionary:
	for u in UPGRADES:
		if u["id"] == id:
			return u
	return {}

static func per_level(id: String) -> float:
	return float(get_def(id).get("per_level", 0.0))

static func cost(id: String, level: int) -> float:
	var u := get_def(id)
	if u.is_empty():
		return INF
	return floorf(float(u["base_cost"]) * pow(float(u["growth"]), level))
