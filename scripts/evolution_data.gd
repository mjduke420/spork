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
		"traits": [],
	},
	{
		"name": "Googly Eyes",
		"cost": 25.0,
		"radius": 36.0,
		"click_value": 2.0,
		"idle": 0.0,
		"max_hp": 20.0,
		"traits": ["eyes"],
	},
	{
		"name": "Membrane",
		"cost": 100.0,
		"radius": 42.0,
		"click_value": 3.0,
		"idle": 0.0,
		"max_hp": 40.0,
		"traits": ["eyes", "membrane"],
	},
	{
		"name": "Flagellum",
		"cost": 300.0,
		"radius": 46.0,
		"click_value": 6.0,
		"idle": 0.0,
		"max_hp": 45.0,
		"traits": ["eyes", "membrane", "flagellum"],
	},
	{
		"name": "Spikes",
		"cost": 800.0,
		"radius": 50.0,
		"click_value": 9.0,
		"idle": 0.0,
		"max_hp": 60.0,
		"traits": ["eyes", "membrane", "flagellum", "spikes"],
	},
	{
		"name": "Mitochondria",
		"cost": 2000.0,
		"radius": 54.0,
		"click_value": 12.0,
		"idle": 3.0,
		"max_hp": 70.0,
		"traits": ["eyes", "membrane", "flagellum", "spikes", "mito"],
	},
	{
		"name": "Multicellular",
		"cost": 6000.0,
		"radius": 64.0,
		"click_value": 20.0,
		"idle": 8.0,
		"max_hp": 100.0,
		"traits": ["eyes", "membrane", "flagellum", "spikes", "mito", "multi"],
	},
	{
		"name": "Proto-fish",
		"cost": 15000.0,
		"radius": 74.0,
		"click_value": 35.0,
		"idle": 18.0,
		"max_hp": 140.0,
		"traits": ["eyes", "membrane", "flagellum", "spikes", "mito", "multi", "protofish"],
	},
	{
		"name": "Googly Fish",
		"cost": 40000.0,
		"radius": 86.0,
		"click_value": 60.0,
		"idle": 40.0,
		"max_hp": 200.0,
		"traits": ["eyes", "membrane", "flagellum", "spikes", "mito", "multi", "protofish", "fish"],
	},
]

static func stage(index: int) -> Dictionary:
	var i: int = clampi(index, 0, STAGES.size() - 1)
	return STAGES[i]

static func count() -> int:
	return STAGES.size()
