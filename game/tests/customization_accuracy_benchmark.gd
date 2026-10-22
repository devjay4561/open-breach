extends SceneTree
## Controlled current-runtime comparison. The baseline subclass changes only
## friendly base accuracy and movement multipliers to their documented prior
## values; it does not reproduce or claim to measure a complete earlier build.
const Simulation = preload("res://scripts/simulation.gd")
const STEP := 1.0 / 30.0
const SEEDS := [1, 7, 42, 97, 313, 713, 1049, 8191]
var checks := 0
var failures: Array[String] = []

class PreviousAccuracy:
	extends BreachSimulation
	func _shot_accuracy(attacker: Dictionary, target: Dictionary, hostile: bool) -> float:
		var current: float = super._shot_accuracy(attacker, target, hostile)
		if hostile: return current
		var weapon: String = str(attacker.weapon)
		var prior: float = 0.91 if weapon == "light" else 0.94
		var ratio: float = prior / float(WEAPONS[weapon].accuracy)
		if _combat_moving(attacker):
			var mode: String = str(attacker.get("movement_mode", "normal"))
			ratio *= float({"careful":0.88,"normal":0.76,"fast":0.60}.get(mode,0.76)) / float({"careful":0.94,"normal":0.84,"fast":0.68}.get(mode,0.84))
		return clampf(current * ratio, 0.0, 1.0)

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture(seed_value: int) -> Dictionary:
	return {"schema_version":1,"id":"ACCURACY_INTEGRATION_QA","revision":1,"custom":true,"title":"Accuracy comparison","variant":"normal","seed":seed_value,"bounds":[20,14],"focus":[10,7],"walls":[],"props":[],"doors":[],"rooms":[{"id":"qa","x":10,"z":7,"w":20,"d":14}],"units":[{"id":"alpha","name":"Alpha","role":"Assault","weapon":"standard","x":3.0,"z":7.0,"facing":0.0}],"enemies":[{"id":"e1","x":9.0,"z":6.0,"facing":PI,"vision_range":14.0,"hold_position":true},{"id":"e2","x":12.0,"z":8.0,"facing":PI,"vision_range":14.0,"hold_position":true}],"civilians":[],"stars":[],"objectives":["Neutralize both hostile actors"],"win":[{"type":"neutralize_all"}],"fail":[]}

func probability_checks() -> Array:
	var rows: Array = []
	for moving: bool in [false,true]:
		for mode: String in ["careful","normal","fast"]:
			var current := Simulation.new()
			var baseline := PreviousAccuracy.new()
			current.load_mission(fixture(42))
			baseline.load_mission(fixture(42))
			for sim: BreachSimulation in [current,baseline]:
				sim.units[0].movement_mode = mode
				if moving:
					sim.units[0].velocity_x = 1.0
					sim.units[0].velocity_z = 0.0
					sim.units[0]._combat_moving_until = 1.0
			var proposed: float = current._shot_accuracy(current.units[0],current.enemies[0],false)
			var prior: float = baseline._shot_accuracy(baseline.units[0],baseline.enemies[0],false)
			var expected_proposed: float = 0.97 * (float({"careful":0.94,"normal":0.84,"fast":0.68}[mode]) if moving else 1.0)
			var expected_prior: float = 0.94 * (float({"careful":0.88,"normal":0.76,"fast":0.60}[mode]) if moving else 1.0)
			check(is_equal_approx(proposed,expected_proposed), "Fully exposed proposed accuracy matches table " + mode + "/" + str(moving))
			check(is_equal_approx(prior,expected_prior), "Only documented prior accuracy values are reconstructed " + mode + "/" + str(moving))
			check(is_equal_approx(current._shot_accuracy(current.enemies[0],current.units[0],true),baseline._shot_accuracy(baseline.enemies[0],baseline.units[0],true)), "Hostile accuracy remains identical " + mode + "/" + str(moving))
			for sim: BreachSimulation in [current,baseline]: sim.units[0].suppressed = 1.0
			check(current._shot_accuracy(current.units[0],current.enemies[0],false) < proposed * 0.51, "Suppression still reduces friendly accuracy")
			rows.append({"moving":moving,"mode":mode,"prior":prior,"proposed":proposed,"delta_percentage_points":100.0*(proposed-prior)})
	return rows

func run_case(seed_value: int, moving: bool, prior_accuracy: bool) -> Dictionary:
	var sim: BreachSimulation = PreviousAccuracy.new() if prior_accuracy else Simulation.new()
	sim.load_mission(fixture(seed_value))
	if moving: check(bool(sim.issue("alpha","MOVE",{"target":[8.0,7.0]},true).get("ok",false)), "Controlled moving route accepted")
	var hostile_shots: int = 0
	var first_hit: float = -1.0
	var first_contact_hp: float = 100.0
	var first_contact: float = -1.0
	for tick_index: int in range(30 * 25):
		var ammunition: Array = sim.enemies.map(func(enemy: Dictionary) -> int: return int(enemy.ammo))
		sim.step(STEP)
		for index: int in range(sim.enemies.size()): hostile_shots += maxi(0,int(ammunition[index])-int(sim.enemies[index].ammo))
		if first_contact < 0.0 and sim.enemies.any(func(enemy: Dictionary) -> bool: return bool(enemy.get("visible",false))):
			first_contact = sim.time
			first_contact_hp = float(sim.units[0].hp)
		if first_hit < 0.0 and sim.hits_taken > 0: first_hit = sim.time
		if not sim.result.is_empty(): break
	return {"seed":seed_value,"moving":moving,"prior_accuracy":prior_accuracy,"success":bool(sim.result.get("success",false)),"survived":float(sim.units[0].hp)>0.0,"hp":float(sim.units[0].hp),"casualties":int(float(sim.units[0].hp)<=0.0),"friendly_shots":sim.shots_fired,"hostile_shots":hostile_shots,"hits_taken":sim.hits_taken,"first_hit_time":first_hit,"first_contact_time":first_contact,"first_contact_hp":first_contact_hp,"time":sim.time,"command_failures":sim.command_failures}

func totals(rows: Array) -> Dictionary:
	var result := {"cases":rows.size(),"successes":0,"survivors":0,"casualties":0,"friendly_shots":0,"hostile_shots":0,"hits_taken":0,"remaining_hp":0.0}
	for row: Dictionary in rows:
		result.successes += int(row.success)
		result.survivors += int(row.survived)
		result.casualties += int(row.casualties)
		result.friendly_shots += int(row.friendly_shots)
		result.hostile_shots += int(row.hostile_shots)
		result.hits_taken += int(row.hits_taken)
		result.remaining_hp += float(row.hp)
	return result

func run() -> void:
	var probabilities := probability_checks()
	var prior: Array = []
	var proposed: Array = []
	for moving: bool in [false,true]:
		for seed_value: int in SEEDS:
			prior.append(run_case(seed_value,moving,true))
			proposed.append(run_case(seed_value,moving,false))
	var baseline_totals := totals(prior)
	var current_totals := totals(proposed)
	check(baseline_totals.friendly_shots > 0 and current_totals.friendly_shots > 0, "Both controlled variants produce actual shots")
	check(prior.all(func(row: Dictionary) -> bool: return int(row.command_failures)==0) and proposed.all(func(row: Dictionary) -> bool: return int(row.command_failures)==0), "Accuracy-only change does not fail movement commands")
	var report := {"scope":"Current runtime with an isolated subclass restoring only prior friendly accuracy and movement multipliers; not a comparison against an entire prior build.","seeds":SEEDS,"probabilities":probabilities,"prior_accuracy":baseline_totals,"proposed_accuracy":current_totals,"paired_cases":{"prior":prior,"proposed":proposed},"checks":checks,"failures":failures}
	DirAccess.make_dir_recursive_absolute("res://../tests/artifacts/operator-customization")
	var output := FileAccess.open("res://../tests/artifacts/operator-customization/accuracy-benchmark.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  ")+"\n")
	output.close()
	print("BREACH_CUSTOMIZATION_ACCURACY " + JSON.stringify({"prior":baseline_totals,"proposed":current_totals}))
	print("BREACH_CUSTOMIZATION_ACCURACY_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
