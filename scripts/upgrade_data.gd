extends RefCounted

## Repeatable stat upgrades bought with biomass. Each level multiplies the cost by
## `growth`. Referenced via preload (const UpgradeData) by GameState and the
## upgrade panel.
##
## The EFFECT isn't flat per level — each level's own marginal gain grows by
## `step` over the last (e.g. Bigger Bite: level 1 grants +3, level 2 grants
## +5, level 3 grants +7, ...), so upgrades stay worth buying instead of
## flattening out late-game. `per_level` is level 1's own gain (the arithmetic
## series' starting term). `step` is 2/3 of `per_level` for every upgrade —
## the same ratio Bigger Bite's own +3/+2 example implies — rounded to a clean
## number per upgrade rather than applying a flat +2 everywhere: dodge is a
## 0..1 fractional stat (capped at 0.75 in PlayerState._recalc), so a literal
## +2 absolute step would blow past its cap by level 2 and waste every level
## after that.

const UPGRADES: Array[Dictionary] = [
	{"id": "click", "name": "Bigger Bite", "unit": "biomass per click", "base_cost": 50.0, "growth": 1.55, "per_level": 3.0, "step": 2.0},
	{"id": "idle", "name": "Metabolism", "unit": "idle biomass/sec", "base_cost": 150.0, "growth": 1.6, "per_level": 3.0, "step": 2.0},
	{"id": "hp", "name": "Tough Membrane", "unit": "max HP", "base_cost": 120.0, "growth": 1.55, "per_level": 10.0, "step": 6.0},
	{"id": "regen", "name": "Fast Healing", "unit": "HP regen/sec", "base_cost": 180.0, "growth": 1.6, "per_level": 1.0, "step": 1.0},
	{"id": "spike", "name": "Sharper Spikes", "unit": "spike damage", "base_cost": 260.0, "growth": 1.6, "per_level": 2.0, "step": 1.0},
	{"id": "dodge", "name": "Faster Swim", "unit": "dodge chance", "base_cost": 300.0, "growth": 1.7, "per_level": 0.05, "step": 0.03},
]

static func get_def(id: String) -> Dictionary:
	for u in UPGRADES:
		if u["id"] == id:
			return u
	return {}

## Level 1's own gain — the starting term of the growing series below.
static func per_level(id: String) -> float:
	return float(get_def(id).get("per_level", 0.0))

static func step(id: String) -> float:
	return float(get_def(id).get("step", 0.0))

## The gain from owning exactly this level (1-indexed) — what buying level N
## actually grants on top of level N-1, i.e. the arithmetic series' Nth term.
static func marginal_gain(id: String, level: int) -> float:
	if level <= 0:
		return 0.0
	return per_level(id) + step(id) * float(level - 1)

## The cumulative bonus applied to the base stat once `level` levels are
## owned — the sum of marginal_gain(id, 1..level), i.e. the arithmetic
## series' partial sum: level*per_level + step*level*(level-1)/2.
static func total_bonus(id: String, level: int) -> float:
	if level <= 0:
		return 0.0
	var n := float(level)
	return n * per_level(id) + step(id) * n * (n - 1.0) * 0.5

static func cost(id: String, level: int) -> float:
	var u := get_def(id)
	if u.is_empty():
		return INF
	return floorf(float(u["base_cost"]) * pow(float(u["growth"]), level))
