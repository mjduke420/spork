extends RefCounted

## Per-player game state: biomass, evolution progress (including the branching
## endgame lineages), HP, upgrades, and derived stats. Instantiable so each future
## player (local or networked) can own an independent copy — today only
## GameState.local exists, but hostiles/food already interact with whichever
## PlayerState a given PlayerCell owns rather than a hardcoded singleton.

const EvolutionData := preload("res://scripts/evolution_data.gd")
const UpgradeData := preload("res://scripts/upgrade_data.gd")
const SaveSystem := preload("res://scripts/save_system.gd")

signal biomass_changed(amount: float)
signal evolved()
signal hp_changed(hp: float, max_hp: float)
signal upgrades_changed()
signal biome_changed(index: int)
signal died()
signal won()

const BASE_REGEN := 3.0    # hp/sec recovered while not at full
const BASE_SPIKE := 4.0    # spike contact damage before upgrades
const BIOMES: Array[String] = ["Primordial Pool", "Tide Pool", "Open Ocean"]

var player_name: String = "Player"
var biomass: float = 0.0
var stage_index: int = 0
var lineage: String = ""    # "", "crab", "octopus", "whale"
var branch_step: int = -1   # -1 until a lineage is chosen, then 0..2 within its path
var hp: float = 20.0
var has_won: bool = false
var upgrade_levels: Dictionary = {}   # upgrade id -> int level

# Scoreboard counters. These accumulate for the whole match and are only
# zeroed by reset_for_new_match() — a PvP-death reset (see take_damage())
# wipes evolution progress but keeps the running tally.
var kills_hostiles: int = 0
var kills_players: int = 0
var deaths: int = 0
var food_eaten: int = 0

# Opt-in PvP (Phase 4): a player can only be attacked by another player if BOTH
# have this set — see Net.request_attack_player().
var pvp_enabled: bool = false

# Derived from the current stage + upgrades (kept in sync by _recalc).
var click_value: float = 1.0
var idle_rate: float = 0.0
var max_hp: float = 20.0
var move_speed: float = 60.0
var regen_rate: float = BASE_REGEN
var spike_damage: float = BASE_SPIKE
var dodge_chance: float = 0.0

func _init() -> void:
	_recalc()
	if hp <= 0.0:
		hp = max_hp

## Loads user://spork_save.json into this instance. Call this ONLY for the true
## local human player — a PlayerState created for a remote peer (GameState.add_player
## on the server, for anyone other than the server's own local_id) must NOT load the
## local machine's save file; it starts blank and gets populated by that peer's own
## periodic state broadcast instead.
func load_local_save() -> void:
	_load_save()
	_recalc()
	if hp <= 0.0:
		hp = max_hp

func tick(delta: float) -> void:
	if idle_rate > 0.0:
		add_biomass(idle_rate * delta)
	if hp < max_hp:
		var healed: float = minf(max_hp, hp + regen_rate * delta)
		if not is_equal_approx(healed, hp):
			hp = healed
			hp_changed.emit(hp, max_hp)

# ---- biomes ----

func biome_index() -> int:
	@warning_ignore("integer_division")
	var group := stage_index / 3   # 3 stages per biome (intended integer division)
	return clampi(group, 0, BIOMES.size() - 1)

func biome_name() -> String:
	return BIOMES[biome_index()]

# ---- biomass / damage ----

func add_biomass(amount: float) -> void:
	biomass = maxf(0.0, biomass + amount)
	biomass_changed.emit(biomass)

## Apply combat damage. Reaching 0 HP from a hostile is a forgiving setback:
## you lose half your biomass and get restored to full HP, but keep your
## evolution progress. Reaching 0 HP from ANOTHER PLAYER is harsher — you
## restart entirely (a fresh spawn) — to make PvP kills feel consequential.
## Either way, the death counts toward the scoreboard's running total.
## Returns true if this call was the killing blow — hp gets restored to
## max_hp as PART of the death handling either way, so a caller can't tell
## by inspecting hp afterward (net.gd's kill-credit logic relies on this).
func take_damage(dmg: float, from_player: bool = false) -> bool:
	if dmg <= 0.0:
		return false
	hp = maxf(0.0, hp - dmg)
	var killed := false
	if hp <= 0.0:
		killed = true
		deaths += 1
		if from_player:
			_clear_progress()
			evolved.emit()
		else:
			biomass = floorf(biomass * 0.5)
			hp = max_hp
		died.emit()
		biomass_changed.emit(biomass)
	hp_changed.emit(hp, max_hp)
	return killed

# ---- evolution: linear trunk, then a chosen branching lineage ----

func current_stage() -> Dictionary:
	if lineage == "":
		return EvolutionData.stage(stage_index)
	return EvolutionData.lineage_stage(lineage, branch_step)

func next_stage() -> Dictionary:
	if lineage == "":
		if stage_index + 1 >= EvolutionData.count():
			return {}
		return EvolutionData.stage(stage_index + 1)
	var path: Array = EvolutionData.lineage_path(lineage)
	if branch_step + 1 >= path.size():
		return {}
	return path[branch_step + 1]

func is_max_stage() -> bool:
	if lineage == "":
		return false   # reaching the fish is a fork, not an end — see awaiting_lineage_choice()
	var path: Array = EvolutionData.lineage_path(lineage)
	return branch_step >= path.size() - 1

func awaiting_lineage_choice() -> bool:
	return lineage == "" and stage_index >= EvolutionData.count() - 1

func lineage_choices() -> Array[String]:
	return EvolutionData.lineage_ids()

func can_evolve() -> bool:
	if awaiting_lineage_choice() or is_max_stage():
		return false
	return biomass >= float(next_stage().get("cost", INF))

func evolve() -> bool:
	if not can_evolve():
		return false
	var old_biome := biome_index()
	if lineage == "":
		stage_index += 1
	else:
		branch_step += 1
	biomass -= float(current_stage().get("cost", 0.0))
	_recalc()
	# Growing restores you to full and lifts your HP ceiling.
	hp = max_hp
	biomass_changed.emit(biomass)
	evolved.emit()
	hp_changed.emit(hp, max_hp)
	if biome_index() != old_biome:
		biome_changed.emit(biome_index())
	if is_max_stage() and not has_won:
		has_won = true
		won.emit()
	autosave()
	return true

## Locks in one of the three endgame lineages once the trunk is maxed. Spends the
## cost of that lineage's first ("smaller") evolution.
func choose_lineage(id: String) -> bool:
	if not awaiting_lineage_choice() or id not in EvolutionData.lineage_ids():
		return false
	var first: Dictionary = EvolutionData.lineage_stage(id, 0)
	if biomass < float(first.get("cost", INF)):
		return false
	lineage = id
	branch_step = 0
	biomass -= float(first.get("cost", 0.0))
	_recalc()
	hp = max_hp
	biomass_changed.emit(biomass)
	evolved.emit()
	hp_changed.emit(hp, max_hp)
	autosave()
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

## Sum of every upgrade's level — the scoreboard's "Level" stat, a distinct
## measure of investment from the evolution stage (already shown as "form").
func total_upgrade_levels() -> int:
	var total := 0
	for lvl in upgrade_levels.values():
		total += int(lvl)
	return total

func buy_upgrade(id: String) -> bool:
	if not can_buy_upgrade(id):
		return false
	biomass -= upgrade_cost(id)
	upgrade_levels[id] = upgrade_level(id) + 1
	_recalc()
	biomass_changed.emit(biomass)
	upgrades_changed.emit()
	hp_changed.emit(hp, max_hp)
	autosave()
	return true

func _recalc() -> void:
	var s: Dictionary = current_stage()
	click_value = float(s.get("click_value", 1.0)) + UpgradeData.total_bonus("click", upgrade_level("click"))
	idle_rate = float(s.get("idle", 0.0)) + UpgradeData.total_bonus("idle", upgrade_level("idle"))
	max_hp = float(s.get("max_hp", 20.0)) + UpgradeData.total_bonus("hp", upgrade_level("hp"))
	move_speed = float(s.get("move_speed", 60.0))
	regen_rate = BASE_REGEN + UpgradeData.total_bonus("regen", upgrade_level("regen"))
	spike_damage = BASE_SPIKE + UpgradeData.total_bonus("spike", upgrade_level("spike"))
	var swim := 0.10 if has_trait("flagellum") else 0.0
	dodge_chance = clampf(swim + UpgradeData.total_bonus("dodge", upgrade_level("dodge")), 0.0, 0.75)
	hp = minf(hp, max_hp)

# ---- network snapshot (Phase 1 groundwork; not persisted to disk) ----

## Lightweight dict for a server -> client broadcast of this player's public state.
func to_snapshot() -> Dictionary:
	return {
		"player_name": player_name,
		"biomass": biomass,
		"stage_index": stage_index,
		"lineage": lineage,
		"branch_step": branch_step,
		"hp": hp,
		"max_hp": max_hp,
		"upgrades": upgrade_levels.duplicate(),
		"kills_hostiles": kills_hostiles,
		"kills_players": kills_players,
		"deaths": deaths,
		"food_eaten": food_eaten,
		"pvp_enabled": pvp_enabled,
	}

## Applied on a client to absorb a server snapshot for this player (itself or a
## remote peer). Re-emits the normal signals so HUD/roster listeners refresh via
## the same reactive wiring used for local mutations.
func apply_snapshot(data: Dictionary) -> void:
	player_name = str(data.get("player_name", player_name))
	biomass = float(data.get("biomass", biomass))
	stage_index = clampi(int(data.get("stage_index", stage_index)), 0, EvolutionData.count() - 1)
	lineage = str(data.get("lineage", lineage))
	branch_step = int(data.get("branch_step", branch_step))
	hp = float(data.get("hp", hp))
	var saved_upgrades: Variant = data.get("upgrades", upgrade_levels)
	if typeof(saved_upgrades) == TYPE_DICTIONARY:
		upgrade_levels = saved_upgrades
	kills_hostiles = int(data.get("kills_hostiles", kills_hostiles))
	kills_players = int(data.get("kills_players", kills_players))
	deaths = int(data.get("deaths", deaths))
	food_eaten = int(data.get("food_eaten", food_eaten))
	pvp_enabled = bool(data.get("pvp_enabled", pvp_enabled))
	_recalc()
	biomass_changed.emit(biomass)
	evolved.emit()
	hp_changed.emit(hp, max_hp)
	upgrades_changed.emit()

# ---- persistence ----

func to_save() -> Dictionary:
	return {
		"biomass": biomass,
		"stage_index": stage_index,
		"lineage": lineage,
		"branch_step": branch_step,
		"hp": hp,
		"has_won": has_won,
		"upgrades": upgrade_levels.duplicate(),
	}

func autosave() -> void:
	SaveSystem.save(to_save())

func _load_save() -> void:
	var data := SaveSystem.load_state()
	if data.is_empty():
		return
	# Never trust the file: clamp/validate every field.
	biomass = maxf(0.0, float(data.get("biomass", 0.0)))
	stage_index = clampi(int(data.get("stage_index", 0)), 0, EvolutionData.count() - 1)
	var loaded_lineage: String = str(data.get("lineage", ""))
	if loaded_lineage in EvolutionData.lineage_ids():
		lineage = loaded_lineage
		var path_size: int = EvolutionData.lineage_path(lineage).size()
		branch_step = clampi(int(data.get("branch_step", 0)), 0, path_size - 1)
	else:
		lineage = ""
		branch_step = -1
	has_won = bool(data.get("has_won", false))
	hp = maxf(0.0, float(data.get("hp", 0.0)))
	upgrade_levels = {}
	var saved: Variant = data.get("upgrades", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for id in saved:
			upgrade_levels[str(id)] = maxi(0, int(saved[id]))

## Wipes evolution progress (stage/lineage/biomass/upgrades) without touching
## the scoreboard counters (kills/deaths/food_eaten) — those are per-match
## totals that only reset_for_new_match() clears. Shared by the "Reset
## progress" button, a PvP death, and a full match restart. Emits nothing
## itself; callers emit whatever signals fit their own context.
func _clear_progress() -> void:
	biomass = 0.0
	stage_index = 0
	lineage = ""
	branch_step = -1
	has_won = false
	upgrade_levels = {}
	_recalc()
	hp = max_hp
	SaveSystem.clear()

func reset() -> void:
	_clear_progress()
	biomass_changed.emit(biomass)
	evolved.emit()
	hp_changed.emit(hp, max_hp)
	upgrades_changed.emit()
	biome_changed.emit(biome_index())

## Called when the 10-minute match timer expires and a new match begins:
## wipes progress AND the scoreboard totals for a clean new round, unlike a
## PvP death (which only wipes progress, keeping the running tally).
func reset_for_new_match() -> void:
	_clear_progress()
	kills_hostiles = 0
	kills_players = 0
	deaths = 0
	food_eaten = 0
	biomass_changed.emit(biomass)
	evolved.emit()
	hp_changed.emit(hp, max_hp)
	upgrades_changed.emit()
	biome_changed.emit(biome_index())
