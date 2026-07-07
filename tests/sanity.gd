extends Node

## Headless sanity check for the evolution/biomass logic. Run via:
##   run_project scene=res://tests/sanity.tscn
## Drives GameState through every stage and asserts the derived stats and win signal.
## Prints "SANITY: PASS" / "SANITY: FAIL ..." then quits.

const EvolutionData := preload("res://scripts/evolution_data.gd")
const UpgradeData := preload("res://scripts/upgrade_data.gd")
const SaveSystem := preload("res://scripts/save_system.gd")

var _failures: int = 0
var _won_fired: bool = false

func _ready() -> void:
	GameState.reset_progress()   # isolate from any real save file on disk
	GameState.won.connect(func(): _won_fired = true)

	_check(GameState.stage_index == 0, "starts at protocell")
	_check(GameState.current_stage()["name"] == "Protocell", "stage 0 name")
	_check(not GameState.has_trait("eyes"), "no eyes at start")

	# First evolution must be the googly eyes (the comedic requirement).
	_check(GameState.next_stage()["name"] == "Googly Eyes", "first evolution is googly eyes")

	# Not affordable yet, then affordable after feeding.
	_check(not GameState.can_evolve(), "cannot evolve with 0 biomass")
	GameState.add_biomass(EvolutionData.stage(1)["cost"])
	_check(GameState.can_evolve(), "can evolve once cost is met")
	_check(GameState.evolve(), "evolve to googly eyes succeeds")
	_check(GameState.has_trait("eyes"), "eyes trait present after first evolution")

	# Walk the rest of the ladder, checking derived stats track the table.
	while not GameState.is_max_stage():
		var next: Dictionary = GameState.next_stage()
		GameState.add_biomass(next["cost"])
		var ok: bool = GameState.evolve()
		_check(ok, "evolve to %s" % next["name"])
		_check(is_equal_approx(GameState.click_value, next["click_value"]), "click_value for %s" % next["name"])
		_check(is_equal_approx(GameState.idle_rate, next["idle"]), "idle_rate for %s" % next["name"])
		_check(is_equal_approx(GameState.max_hp, next["max_hp"]), "max_hp for %s" % next["name"])

	_check(GameState.current_stage()["name"] == "Googly Fish", "final stage is the fish")
	_check(GameState.has_trait("fish") and GameState.has_trait("eyes"), "fish keeps googly eyes")
	_check(GameState.has_won, "won flag set at final stage")
	_check(_won_fired, "won signal fired")
	_check(not GameState.can_evolve(), "cannot evolve past the fish")

	_test_upgrades()
	_test_biomes()
	_test_save()

	if _failures == 0:
		print("SANITY: PASS (%d stages)" % EvolutionData.count())
	else:
		print("SANITY: FAIL (%d checks failed)" % _failures)
	get_tree().quit()

func _test_upgrades() -> void:
	# "click" upgrade: buying a level should raise click_value and the next cost.
	var before_click := GameState.click_value
	var lvl0_cost := GameState.upgrade_cost("click")
	GameState.add_biomass(lvl0_cost)
	_check(GameState.buy_upgrade("click"), "buy click upgrade")
	_check(GameState.upgrade_level("click") == 1, "click level is 1")
	_check(is_equal_approx(GameState.click_value, before_click + UpgradeData.per_level("click")), "click_value increased")
	_check(GameState.upgrade_cost("click") > lvl0_cost, "click cost scaled up")
	_check(not GameState.buy_upgrade("hp"), "cannot buy upgrade you cannot afford")

	# "hp" upgrade raises max HP; "dodge" raises dodge chance.
	var before_hp := GameState.max_hp
	GameState.add_biomass(GameState.upgrade_cost("hp"))
	_check(GameState.buy_upgrade("hp"), "buy hp upgrade")
	_check(GameState.max_hp > before_hp, "max_hp increased")
	GameState.add_biomass(GameState.upgrade_cost("dodge"))
	_check(GameState.buy_upgrade("dodge"), "buy dodge upgrade")
	_check(GameState.dodge_chance > 0.0, "dodge_chance increased")

func _test_biomes() -> void:
	# At the fish stage (8) the biome index is 8/3 = 2 -> Open Ocean.
	_check(GameState.biome_index() == 2, "open ocean biome at fish stage")
	_check(GameState.biome_name() == "Open Ocean", "biome name at fish stage")

func _test_save() -> void:
	# Roundtrip a snapshot through the save file.
	var snapshot := {"biomass": 777.0, "stage_index": 3, "hp": 30.0, "has_won": false, "upgrades": {"click": 2}}
	SaveSystem.save(snapshot)
	var loaded := SaveSystem.load_state()
	_check(int(loaded.get("stage_index", -1)) == 3, "save roundtrip: stage")
	_check(is_equal_approx(float(loaded.get("biomass", 0.0)), 777.0), "save roundtrip: biomass")

	# Reset clears state and deletes the save file.
	GameState.reset_progress()
	_check(GameState.stage_index == 0, "reset returns to protocell")
	_check(GameState.biomass == 0.0, "reset clears biomass")
	_check(GameState.upgrade_level("click") == 0, "reset clears upgrades")
	_check(SaveSystem.load_state().is_empty(), "reset deletes the save file")

func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error("SANITY check failed: %s" % label)
		print("  FAIL: %s" % label)
