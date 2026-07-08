extends Node

## Headless sanity check for the evolution/biomass/movement/lineage logic. Run via:
##   run_project scene=res://tests/sanity.tscn
## Drives GameState.local through the trunk, all three endgame lineages, upgrades,
## biomes, and save/load. Prints "SANITY: PASS" / "SANITY: FAIL ..." then quits.

const EvolutionData := preload("res://scripts/evolution_data.gd")
const UpgradeData := preload("res://scripts/upgrade_data.gd")
const SaveSystem := preload("res://scripts/save_system.gd")
const PlayerState := preload("res://scripts/player_state.gd")

var _failures: int = 0
var _won_fired: bool = false

func _ready() -> void:
	var state := GameState.local
	state.reset()   # isolate from any real save file on disk
	state.won.connect(func(): _won_fired = true)

	_check(state.stage_index == 0, "starts at protocell")
	_check(state.current_stage()["name"] == "Protocell", "stage 0 name")
	_check(not state.has_trait("eyes"), "no eyes at start")

	# First evolution must be the googly eyes (the comedic requirement).
	_check(state.next_stage()["name"] == "Googly Eyes", "first evolution is googly eyes")

	# Not affordable yet, then affordable after feeding.
	_check(not state.can_evolve(), "cannot evolve with 0 biomass")
	state.add_biomass(EvolutionData.stage(1)["cost"])
	_check(state.can_evolve(), "can evolve once cost is met")
	_check(state.evolve(), "evolve to googly eyes succeeds")
	_check(state.has_trait("eyes"), "eyes trait present after first evolution")

	# Walk the rest of the trunk, checking derived stats (including move_speed) track
	# the table and that movement speed strictly increases stage over stage.
	var prev_speed := state.move_speed
	while not state.awaiting_lineage_choice():
		var next: Dictionary = state.next_stage()
		state.add_biomass(next["cost"])
		var ok: bool = state.evolve()
		_check(ok, "evolve to %s" % next["name"])
		_check(is_equal_approx(state.click_value, next["click_value"]), "click_value for %s" % next["name"])
		_check(is_equal_approx(state.idle_rate, next["idle"]), "idle_rate for %s" % next["name"])
		_check(is_equal_approx(state.max_hp, next["max_hp"]), "max_hp for %s" % next["name"])
		_check(is_equal_approx(state.move_speed, next["move_speed"]), "move_speed for %s" % next["name"])
		_check(state.move_speed >= prev_speed, "move_speed non-decreasing at %s" % next["name"])
		prev_speed = state.move_speed

	_check(state.current_stage()["name"] == "Googly Fish", "trunk ends at the fish")
	_check(state.has_trait("fish") and state.has_trait("eyes"), "fish keeps googly eyes")
	_check(state.awaiting_lineage_choice(), "awaiting_lineage_choice true at maxed trunk")
	_check(not state.can_evolve(), "cannot evolve trunk further while awaiting a lineage choice")
	_check(not state.has_won, "not won yet — fish is a fork, not an ending")

	_test_lineages()
	_test_upgrades()
	_test_biomes()
	_test_save()
	_test_pvp_snapshot()
	_test_pvp_combat()

	if _failures == 0:
		print("SANITY: PASS (%d stages)" % EvolutionData.count())
	else:
		print("SANITY: FAIL (%d checks failed)" % _failures)
	get_tree().quit()

## Drives each of the 3 lineages to its giant apex form from an isolated reset,
## verifying traits, is_max_stage(), and the won signal.
func _test_lineages() -> void:
	for id in EvolutionData.lineage_ids():
		var state := GameState.local
		state.reset()
		_won_fired = false
		state.add_biomass(EvolutionData.stage(EvolutionData.count() - 1)["cost"])
		_drive_to_max_trunk(state)
		_check(state.awaiting_lineage_choice(), "[%s] awaiting choice before picking" % id)

		var first: Dictionary = EvolutionData.lineage_stage(id, 0)
		_check(not state.choose_lineage(id), "[%s] cannot choose lineage without enough biomass" % id)
		state.add_biomass(first["cost"])
		_check(state.choose_lineage(id), "[%s] choose_lineage succeeds once affordable" % id)
		_check(state.lineage == id, "[%s] lineage recorded" % id)
		_check(state.branch_step == 0, "[%s] branch_step starts at 0" % id)
		_check(not state.awaiting_lineage_choice(), "[%s] no longer awaiting choice" % id)

		var path: Array = EvolutionData.lineage_path(id)
		while not state.is_max_stage():
			var next: Dictionary = state.next_stage()
			state.add_biomass(next["cost"])
			_check(state.evolve(), "[%s] evolve to %s" % [id, next["name"]])

		var giant: Dictionary = path[path.size() - 1]
		_check(state.current_stage()["name"] == giant["name"], "[%s] reaches %s" % [id, giant["name"]])
		var giant_traits: Array = giant["traits"]
		_check(state.has_trait(giant_traits[giant_traits.size() - 1]), "[%s] has its giant trait" % id)
		_check(state.has_trait("eyes"), "[%s] giant form keeps googly eyes" % id)
		_check(state.is_max_stage(), "[%s] is_max_stage true at giant form" % id)
		_check(state.has_won, "[%s] has_won true at giant form" % id)
		_check(_won_fired, "[%s] won signal fired" % id)
		_check(not state.can_evolve(), "[%s] cannot evolve past the giant form" % id)

func _drive_to_max_trunk(state) -> void:
	while not state.awaiting_lineage_choice():
		var next: Dictionary = state.next_stage()
		state.add_biomass(next["cost"])
		state.evolve()

func _test_upgrades() -> void:
	var state := GameState.local
	state.reset()
	# "click" upgrade: buying a level should raise click_value and the next cost.
	var before_click := state.click_value
	var lvl0_cost := state.upgrade_cost("click")
	state.add_biomass(lvl0_cost)
	_check(state.buy_upgrade("click"), "buy click upgrade")
	_check(state.upgrade_level("click") == 1, "click level is 1")
	_check(is_equal_approx(state.click_value, before_click + UpgradeData.per_level("click")), "click_value increased")
	_check(state.upgrade_cost("click") > lvl0_cost, "click cost scaled up")
	_check(not state.buy_upgrade("hp"), "cannot buy upgrade you cannot afford")

	# "hp" upgrade raises max HP; "dodge" raises dodge chance.
	var before_hp := state.max_hp
	state.add_biomass(state.upgrade_cost("hp"))
	_check(state.buy_upgrade("hp"), "buy hp upgrade")
	_check(state.max_hp > before_hp, "max_hp increased")
	state.add_biomass(state.upgrade_cost("dodge"))
	_check(state.buy_upgrade("dodge"), "buy dodge upgrade")
	_check(state.dodge_chance > 0.0, "dodge_chance increased")

func _test_biomes() -> void:
	var state := GameState.local
	state.reset()
	state.add_biomass(EvolutionData.stage(EvolutionData.count() - 1)["cost"])
	_drive_to_max_trunk(state)
	# At the fish stage (8) the biome index is 8/3 = 2 -> Open Ocean.
	_check(state.biome_index() == 2, "open ocean biome at fish stage")
	_check(state.biome_name() == "Open Ocean", "biome name at fish stage")

func _test_save() -> void:
	# Roundtrip a snapshot (including a lineage in progress) through the save file.
	var snapshot := {
		"biomass": 777.0, "stage_index": 8, "lineage": "octopus", "branch_step": 1,
		"hp": 30.0, "has_won": false, "upgrades": {"click": 2},
	}
	SaveSystem.save(snapshot)
	var loaded := SaveSystem.load_state()
	_check(int(loaded.get("stage_index", -1)) == 8, "save roundtrip: stage")
	_check(str(loaded.get("lineage", "")) == "octopus", "save roundtrip: lineage")
	_check(int(loaded.get("branch_step", -1)) == 1, "save roundtrip: branch_step")
	_check(is_equal_approx(float(loaded.get("biomass", 0.0)), 777.0), "save roundtrip: biomass")

	# Reset clears state and deletes the save file.
	var state := GameState.local
	state.reset()
	_check(state.stage_index == 0, "reset returns to protocell")
	_check(state.lineage == "", "reset clears lineage")
	_check(state.branch_step == -1, "reset clears branch_step")
	_check(state.biomass == 0.0, "reset clears biomass")
	_check(state.upgrade_level("click") == 0, "reset clears upgrades")
	_check(SaveSystem.load_state().is_empty(), "reset deletes the save file")

## Data-layer coverage for Phase 4 (PvP). The actual request_attack_player RPC
## flag-gating on Net.gd needs a live 2-peer connection to exercise for real
## (blocked in this sandbox by a local firewall — see the plan file); this checks
## the PlayerState side is structurally correct: default off, and it round-trips
## through the same snapshot mechanism the network relay uses.
func _test_pvp_snapshot() -> void:
	var state := GameState.local
	state.reset()
	_check(not state.pvp_enabled, "pvp_enabled defaults to false")

	state.pvp_enabled = true
	state.kills_players = 2
	state.deaths = 1
	var snap := state.to_snapshot()
	_check(bool(snap.get("pvp_enabled", false)) == true, "to_snapshot includes pvp_enabled")
	_check(int(snap.get("kills_players", -1)) == 2, "to_snapshot includes kills_players")

	var other := PlayerState.new()
	other.apply_snapshot(snap)
	_check(other.pvp_enabled, "apply_snapshot restores pvp_enabled")
	_check(other.kills_players == 2, "apply_snapshot restores kills_players")
	_check(other.deaths == 1, "apply_snapshot restores deaths")

	state.reset()

## Direct coverage for Net.gd's combat resolution (_resolve_attack/_resolve_contact)
## — these are plain functions, so they can be exercised without a live 2-peer
## connection (which this sandbox's firewall blocks — see the plan file).
## Registers two synthetic players in GameState.players, drives combat directly,
## then removes them. This is the exact bug report: touching PvP-enabled players
## must hurt BOTH of them, not just whoever initiated a click/spike.
func _test_pvp_combat() -> void:
	var a_id := 9001
	var b_id := 9002
	var a := GameState.add_player(a_id)
	var b := GameState.add_player(b_id)
	a.pvp_enabled = true
	b.pvp_enabled = true

	var a_hp_before: float = a.hp
	var b_hp_before: float = b.hp
	Net._resolve_attack(a_id, b_id, false)
	_check(b.hp < b_hp_before, "one-directional attack damages the target")
	_check(is_equal_approx(a.hp, a_hp_before), "one-directional attack leaves the attacker unhurt")

	var a_hp_before_contact: float = a.hp
	var b_hp_before_contact: float = b.hp
	Net._resolve_contact(a_id, b_id)
	_check(a.hp < a_hp_before_contact, "mutual contact damages player A")
	_check(b.hp < b_hp_before_contact, "mutual contact damages player B")

	b.pvp_enabled = false
	var a_hp_before_off: float = a.hp
	var b_hp_before_off: float = b.hp
	Net._resolve_contact(a_id, b_id)
	_check(is_equal_approx(a.hp, a_hp_before_off) and is_equal_approx(b.hp, b_hp_before_off),
		"contact does nothing once either side turns pvp off")

	GameState.remove_player(a_id)
	GameState.remove_player(b_id)

func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error("SANITY check failed: %s" % label)
		print("  FAIL: %s" % label)
