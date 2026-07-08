extends RefCounted

## Referenced via `preload` (const EvolutionData) rather than a global class_name so
## it resolves reliably on a fresh headless launch before the editor has scanned.

## Data table for the evolution ladder. Each stage lists cumulative traits so the
## PlayerCell can simply check "is this trait present on my current stage".
## Costs are in biomass and are tunable. `click_value` is the biomass earned per
## click at that stage. `idle` is passive biomass/sec granted once reached.

const STAGES: Array[Dictionary] = [
	{
		"name": "Protocell",
		"cost": 0.0,
		"radius": 34.0,
		"click_value": 1.0,
		"idle": 0.0,
		"max_hp": 20.0,
		"move_speed": 60.0,
		"traits": [],
	},
	{
		"name": "Googly Eyes",
		"cost": 25.0,
		"radius": 36.0,
		"click_value": 2.0,
		"idle": 0.0,
		"max_hp": 20.0,
		"move_speed": 62.0,
		"traits": ["eyes"],
	},
	{
		"name": "Membrane",
		"cost": 100.0,
		"radius": 42.0,
		"click_value": 3.0,
		"idle": 0.0,
		"max_hp": 40.0,
		"move_speed": 68.0,
		"traits": ["eyes", "membrane"],
	},
	{
		"name": "Flagellum",
		"cost": 300.0,
		"radius": 46.0,
		"click_value": 6.0,
		"idle": 0.0,
		"max_hp": 45.0,
		"move_speed": 95.0,
		"traits": ["eyes", "membrane", "flagellum"],
	},
	{
		"name": "Spikes",
		"cost": 800.0,
		"radius": 50.0,
		"click_value": 9.0,
		"idle": 0.0,
		"max_hp": 60.0,
		"move_speed": 98.0,
		"traits": ["eyes", "membrane", "flagellum", "spikes"],
	},
	{
		"name": "Mitochondria",
		"cost": 2000.0,
		"radius": 54.0,
		"click_value": 12.0,
		"idle": 3.0,
		"max_hp": 70.0,
		"move_speed": 102.0,
		"traits": ["eyes", "membrane", "flagellum", "spikes", "mito"],
	},
	{
		"name": "Multicellular",
		"cost": 6000.0,
		"radius": 64.0,
		"click_value": 20.0,
		"idle": 8.0,
		"max_hp": 100.0,
		"move_speed": 108.0,
		"traits": ["eyes", "membrane", "flagellum", "spikes", "mito", "multi"],
	},
]

## Diverging endgame lineages, chosen once the trunk above is maxed (Multicellular) —
## the branch point comes before ever reaching a fish form; each lineage's own path
## carries the fish traits below plus its own tags, so a chosen lineage looks like a
## fish (or crab/octopus) from its very first step.
## Each path is two "smaller" evolutions followed by a giant apex form. Traits are
## cumulative (like STAGES): every entry lists the full base fish traits plus its
## own lineage tags, so has_trait() works identically for trunk and branch stages.
const FISH_TRAITS: Array[String] = ["eyes", "membrane", "flagellum", "spikes", "mito", "multi", "protofish", "fish"]

const LINEAGES: Dictionary = {
	"crab": {
		"display": "Crab Lineage",
		"path": [
			{"id": "crab_1", "name": "Shell Crawler", "cost": 60000.0, "radius": 92.0, "click_value": 70.0, "idle": 45.0, "max_hp": 260.0, "move_speed": 120.0, "traits": FISH_TRAITS + ["crab1"]},
			{"id": "crab_2", "name": "Reef Crab", "cost": 150000.0, "radius": 100.0, "click_value": 85.0, "idle": 55.0, "max_hp": 340.0, "move_speed": 115.0, "traits": FISH_TRAITS + ["crab1", "crab2"]},
			{"id": "crab_3", "name": "Giant Crab", "cost": 400000.0, "radius": 120.0, "click_value": 110.0, "idle": 70.0, "max_hp": 480.0, "move_speed": 110.0, "traits": FISH_TRAITS + ["crab1", "crab2", "giant_crab"]},
		],
	},
	"octopus": {
		"display": "Octopus Lineage",
		"path": [
			{"id": "octo_1", "name": "Tentacled Fish", "cost": 60000.0, "radius": 88.0, "click_value": 90.0, "idle": 40.0, "max_hp": 220.0, "move_speed": 165.0, "traits": FISH_TRAITS + ["octo1"]},
			{"id": "octo_2", "name": "Reef Octopus", "cost": 150000.0, "radius": 96.0, "click_value": 115.0, "idle": 50.0, "max_hp": 280.0, "move_speed": 180.0, "traits": FISH_TRAITS + ["octo1", "octo2"]},
			{"id": "octo_3", "name": "Giant Octopus", "cost": 400000.0, "radius": 116.0, "click_value": 150.0, "idle": 65.0, "max_hp": 380.0, "move_speed": 200.0, "traits": FISH_TRAITS + ["octo1", "octo2", "giant_octo"]},
		],
	},
	"whale": {
		"display": "Whale Lineage",
		"path": [
			{"id": "whale_1", "name": "Whale Calf", "cost": 60000.0, "radius": 100.0, "click_value": 75.0, "idle": 60.0, "max_hp": 300.0, "move_speed": 145.0, "traits": FISH_TRAITS + ["whale1"]},
			{"id": "whale_2", "name": "Young Whale", "cost": 150000.0, "radius": 112.0, "click_value": 90.0, "idle": 80.0, "max_hp": 420.0, "move_speed": 160.0, "traits": FISH_TRAITS + ["whale1", "whale2"]},
			{"id": "whale_3", "name": "Giant Whale", "cost": 400000.0, "radius": 140.0, "click_value": 120.0, "idle": 110.0, "max_hp": 650.0, "move_speed": 175.0, "traits": FISH_TRAITS + ["whale1", "whale2", "giant_whale"]},
		],
	},
}

static func stage(index: int) -> Dictionary:
	var i: int = clampi(index, 0, STAGES.size() - 1)
	return STAGES[i]

static func count() -> int:
	return STAGES.size()

static func lineage_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in LINEAGES:
		ids.append(id)
	return ids

static func lineage_path(id: String) -> Array:
	return LINEAGES.get(id, {}).get("path", [])

static func lineage_display(id: String) -> String:
	return LINEAGES.get(id, {}).get("display", id)

static func lineage_stage(id: String, step: int) -> Dictionary:
	var path: Array = lineage_path(id)
	if path.is_empty():
		return {}
	return path[clampi(step, 0, path.size() - 1)]
