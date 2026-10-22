extends "res://tests/mission_playthrough.gd"
## A/B only: candidate code is compiled in memory, never written to simulation.gd.

var variant: String = "baseline"
var route: String = ""
var candidates: Dictionary = {}
var report: Dictionary = {"variants": {}}

func mission(filename: String) -> RefCounted:
	var sim: RefCounted = Simulation.new() if variant == "baseline" else candidates[variant].new()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % filename))
	sim.load_mission(data)
	return sim

func result_check(sim: RefCounted, expected_threats: int, expected_civilians: int) -> void:
	super.result_check(sim, expected_threats, expected_civilians)
	var health: Dictionary = {}
	var total_health: float = 0.0
	for unit: Dictionary in sim.units:
		health[unit.id] = unit.hp
		total_health += float(unit.hp)
	var summary: Dictionary = sim.result.duplicate(true)
	summary["health"] = health
	summary["total_health"] = total_health
	summary["seed"] = sim.mission.seed
	report.variants[variant].missions[route] = summary

func _crossing_time(weapon: String, enemy_patrol: bool = false) -> Dictionary:
	var sim: RefCounted = Simulation.new() if variant == "baseline" else candidates[variant].new()
	var data: Dictionary = {"id": "PACING", "seed": 42, "bounds": [24, 16], "rooms": [], "walls": [], "doors": [], "props": [], "units": [{"id": "alpha", "x": 2.0, "z": 5.0, "facing": 0.0, "weapon": weapon}], "enemies": [], "civilians": []}
	if enemy_patrol:
		data.units[0].x = 21.0
		data.units[0].z = 14.0
		data.enemies = [{"id": "patrol", "x": 2.0, "z": 5.0, "facing": 0.0, "patrol": [[12.3, 5.0], [2.0, 5.0]]}]
	sim.load_mission(data)
	if not enemy_patrol:
		sim.issue("alpha", "MOVE", {"target": [12.3, 5.0]})
	var actor: Dictionary = sim.enemies[0] if enemy_patrol else sim.units[0]
	var elapsed: float = -1.0
	for index: int in range(900):
		var previous_x: float = float(actor.x)
		sim.step(STEP)
		if float(actor.x) >= 12.0:
			elapsed = sim.time - STEP + STEP * (12.0 - previous_x) / (float(actor.x) - previous_x)
			break
	check(elapsed > 0.0, "%s/%s: 10m crossing completed" % [variant, weapon])
	return {"seconds": elapsed, "measured_speed_mps": 10.0 / elapsed, "definition": "Start x=2 to first interpolated x=12 crossing; destination x=12.3 avoids command arrival tolerance."}

func _run() -> void:
	var original: String = FileAccess.get_file_as_string("res://scripts/simulation.gd")
	if not original.contains('var speed: float = 1.8 if unit["weapon"] == "standard" else 2.0') or not original.contains('minf(0.7 * dt, direction.length())'):
		push_error("Pacing baseline has changed. Update the A/B fixture before regenerating its report.")
		quit(2)
		return
	var edited: String = original.replace("class_name BreachSimulation\n", "")
	edited = edited.replace('var speed: float = 1.8 if unit["weapon"] == "standard" else 2.0', 'var speed: float = 2.16 if unit["weapon"] == "standard" else 2.4')
	var operators_only := GDScript.new()
	operators_only.source_code = edited
	check(operators_only.reload() == OK, "Operator-only sensitivity candidate compiled")
	candidates["plus20_operators"] = operators_only
	edited = edited.replace('minf(0.7 * dt, direction.length())', 'minf(0.84 * dt, direction.length())')
	check(edited != original and edited.contains('var speed: float = 2.16') and edited.contains('minf(0.84 * dt'), "Candidate replaces only movement rates")
	var candidate := GDScript.new()
	candidate.source_code = edited
	check(candidate.reload() == OK, "Transient candidate compiled")
	candidates["plus20"] = candidate
	report["production_simulation_sha256"] = original.sha256_text()
	report["candidate_change"] = {"standard_mps": [1.8, 2.16], "light_mps": [2.0, 2.4], "enemy_patrol_mps": [0.7, 0.84], "simulation_step_seconds": STEP, "timers_and_combat": "unchanged"}
	for current_variant: String in ["baseline", "plus20", "plus20_operators"]:
		variant = current_variant
		report.variants[variant] = {"missions": {}, "ten_metre": {}}
		route = "T01_squad"
		_tutorial()
		route = "T01_single_operator"
		_tutorial_browser_controls()
		route = "M01_squad"
		_house()
		report.variants[variant].ten_metre.standard = _crossing_time("standard")
		report.variants[variant].ten_metre.light = _crossing_time("light")
		report.variants[variant].ten_metre.enemy_patrol = _crossing_time("standard", true)
	check(FileAccess.get_file_as_string("res://scripts/simulation.gd") == original, "Production simulation source remains unchanged after A/B")
	report["checks"] = checks
	report["failures"] = failures
	var output := FileAccess.open(ProjectSettings.globalize_path("res://../tests/artifacts/movement-pacing-report.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  ") + "\n")
	output.close()
	print("BREACH_MOVEMENT_PACING_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
