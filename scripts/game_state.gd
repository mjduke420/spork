extends Node

## Autoload singleton holding all game state. UI and gameplay nodes subscribe to
## these signals rather than polling. All mutations flow through the helper methods
## below so state stays consistent and observable.

const EvolutionData := preload("res://scripts/evolution_data.gd")
const UpgradeData := preload("res://scripts/upgrade_data.gd")
const SaveSystem := preload("res://scripts/save_system.gd")

signal biomass_changed(amount: float)
signal evolved(stage_index: int)
signal hp_changed(hp: float, max_hp: float)
signal upgrades_changed()
signal biome_changed(index: int)
signal died()
signal won()

const BASE_REGEN := 3.0    # hp/sec recovered while not at full
const BASE_SPIKE := 4.0    # spike contact damage before upgrades
const BIOMES: Array[String] = ["Primordial Pool", "Tide Pool", "Open Ocean"]

var biomass: float = 0.0
var stage_index: int = 0
var hp: float = 20.0
var has_won: bool = false
var upgrade_levels: Dictionary = {}   # upgrade id -> int level

# Derived from the current stage + upgrades (kept in sync by _recalc).
var click_value: float = 1.0
var idle_rate: float = 0.0
var max_hp: float = 20.0
var regen_rate: float = BASE_REGEN
var spike_damage: float = BASE_SPIKE
var dodge_chance: float = 0.0

func _ready() -> void:
	_load_save()
	_recalc()
	if hp <= 0.0:
		hp = max_hp

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		_autosave()

# ---- biomes ----

func biome_index() -> int:
	@warning_ignore("integer_division")
	var group := stage_index / 3   # 3 stages per biome (intended integer division)
	return clampi(group, 0, BIOMES.size() - 1)

func biome_name() -> String:
	return BIOMES[biome_index()]

func _process(delta: float) -> void:
	if idle_rate > 0.0:
		add_biomass(idle_rate * delta)
	if hp < max_hp:
		var healed: float = minf(max_hp, hp + regen_rate * delta)
		if not is_equal_approx(healed, hp):
			hp = healed
			hp_changed.emit(hp, max_hp)

func add_biomass(amount: float) -> void:
	biomass = maxf(0.0, biomass + amount)
	biomass_changed.emit(biomass)

## Apply combat damage. Reaching 0 HP is a forgiving setback: you lose half your
## biomass and get restored to full HP, but keep your evolution stage.
func take_damage(dmg: float) -> void:
	if dmg <= 0.0:
		return
	hp = maxf(0.0, hp - dmg)
	if hp <= 0.0:
		biomass = floorf(biomass * 0.5)
		hp = max_hp
		died.emit()
		biomass_changed.emit(biomass)
	hp_changed.emit(hp, max_hp)

func current_stage() -> Dictionary:
	return EvolutionData.stage(stage_index)

func next_stage() -> Dictionary:
	if stage_index + 1 >= EvolutionData.count():
		return {}
	return EvolutionData.stage(stage_index + 1)

func is_max_stage() -> bool:
	return stage_index + 1 >= EvolutionData.count()

func can_evolve() -> bool:
	if is_max_stage():
		return false
	return biomass >= float(next_stage().get("cost", INF))

func evolve() -> bool:
	if not can_evolve():
		return false
	var old_biome := biome_index()
	stage_index += 1
	biomass -= float(current_stage().get("cost", 0.0))
	_recalc()
	# Growing restores you to full and lifts your HP ceiling.
	hp = max_hp
	biomass_changed.emit(biomass)
	evolved.emit(stage_index)
	hp_changed.emit(hp, max_hp)
	if biome_index() != old_biome:
		biome_changed.emit(biome_index())
	if stage_index == EvolutionData.count() - 1 and not has_won:
		has_won = true
		won.emit()
	_autosave()
	return true

func has_trait(trait_name: String) -> bool:
	return trait_name in current_stage().get("traits", [])

# ---- upgrades ----

func upgrade_level(id: String) -> int:
	return int(upgrade_levels.get(id, 0))

func upgrade_cost(id: String) -> float:
	return UpgradeData.cost(id, upgrade_level(id))

func can_buy_upgrade(id: String) -> bool:
	return biomass >= upgrade_cost(id)

func buy_upgrade(id: String) -> bool:
	if not can_buy_upgrade(id):
		return false
	biomass -= upgrade_cost(id)
	upgrade_levels[id] = upgrade_level(id) + 1
	_recalc()
	biomass_changed.emit(biomass)
	upgrades_changed.emit()
	hp_changed.emit(hp, max_hp)
	_autosave()
	return true

func _recalc() -> void:
	var s: Dictionary = current_stage()
	click_value = float(s.get("click_value", 1.0)) + upgrade_level("click") * UpgradeData.per_level("click")
	idle_rate = float(s.get("idle", 0.0)) + upgrade_level("idle") * UpgradeData.per_level("idle")
	max_hp = float(s.get("max_hp", 20.0)) + upgrade_level("hp") * UpgradeData.per_level("hp")
	regen_rate = BASE_REGEN + upgrade_level("regen") * UpgradeData.per_level("regen")
	spike_damage = BASE_SPIKE + upgrade_level("spike") * UpgradeData.per_level("spike")
	var swim := 0.10 if has_trait("flagellum") else 0.0
	dodge_chance = clampf(swim + upgrade_level("dodge") * UpgradeData.per_level("dodge"), 0.0, 0.75)
	hp = minf(hp, max_hp)

# ---- persistence ----

func _to_save() -> Dictionary:
	return {
		"biomass": biomass,
		"stage_index": stage_index,
		"hp": hp,
		"has_won": has_won,
		"upgrades": upgrade_levels.duplicate(),
	}

func _autosave() -> void:
	SaveSystem.save(_to_save())

func _load_save() -> void:
	var data := SaveSystem.load_state()
	if data.is_empty():
		return
	# Never trust the file: clamp/validate every field.
	biomass = maxf(0.0, float(data.get("biomass", 0.0)))
	stage_index = clampi(int(data.get("stage_index", 0)), 0, EvolutionData.count() - 1)
	has_won = bool(data.get("has_won", false))
	hp = maxf(0.0, float(data.get("hp", 0.0)))
	upgrade_levels = {}
	var saved: Variant = data.get("upgrades", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for id in saved:
			upgrade_levels[str(id)] = maxi(0, int(saved[id]))

func reset_progress() -> void:
	biomass = 0.0
	stage_index = 0
	has_won = false
	upgrade_levels = {}
	_recalc()
	hp = max_hp
	SaveSystem.clear()
	biomass_changed.emit(biomass)
	evolved.emit(stage_index)
	hp_changed.emit(hp, max_hp)
	upgrades_changed.emit()
	biome_changed.emit(biome_index())
