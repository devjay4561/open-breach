extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Door = preload("res://scripts/door_geometry.gd")
const Navigation = preload("res://scripts/navigation.gd")
const STEP := 1.0 / 30.0
var checks := 0
var failures: Array[String] = []
var scenarios: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func run() -> void:
	for id: String in ["M01", "M01H"]:
		for shared_target: bool in [false, true]:
			_squad_entry(id, shared_target)
	var report := {"checks":checks, "failures":failures, "scenarios":scenarios}
	var output := FileAccess.open("res://../tests/artifacts/door-entry/native-report.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  ") + "\n")
	output.close()
	print("BREACH_DOOR_ENTRY_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _squad_entry(id: String, shared_target: bool) -> void:
	var data := Catalog.load(id)
	data.seed = 2130704788
	# Keep the actual doorway, furniture and spawns; isolate movement from combat.
	data.enemies = []
	data.civilians = []
	data.win = [{"type":"reach_zone", "zone":[22,2,0.2,0.2]}]
	data.fail = []
	for index: int in range(data.units.size()):
		data.units[index].weapon = "standard"
		data.units[index].trait = ["breacher", "marksman", "cautious", "rescuer"][index]
	var sim := Simulation.new()
	sim.load_mission(data)
	var label := "%s/%s" % [id, "shared" if shared_target else "spread"]
	var targets: Array = [[11.0,14.7], [12.0,13.8], [13.0,14.7], [12.0,15.5]]
	for index: int in range(sim.units.size()):
		var response: Dictionary = sim.plan_move(str(sim.units[index].id), {"target":[12.0,15.5] if shared_target else targets[index]})
		check(bool(response.ok), label + " entry command accepted")
	var separated := true
	var leaf_clear := true
	var continuous := true
	var complete := false
	for frame: int in range(900):
		var before: Array = sim.units.map(func(unit: Dictionary) -> Vector2: return sim._position(unit))
		sim.step(STEP)
		complete = true
		for index: int in range(sim.units.size()):
			var unit: Dictionary = sim.units[index]
			var position: Vector2 = sim._position(unit)
			continuous = continuous and position.distance_to(before[index]) <= 0.10
			leaf_clear = leaf_clear and not Door.overlaps_actor(sim.doors[0], -1.0, position, Navigation.RADIUS)
			for other: int in range(index):
				separated = separated and position.distance_to(sim._position(sim.units[other])) >= Navigation.RADIUS * 2.0 - 0.0001
			complete = complete and unit.commands.back().state == "SUCCEEDED"
		if complete or sim.command_failures > 0: break
	var rows: Array = sim.units.map(func(unit: Dictionary) -> Dictionary: return {"id":unit.id, "position":[unit.x,unit.z], "status":unit.status, "commands":unit.commands.map(func(command: Dictionary) -> Dictionary: return {"type":command.type,"state":command.state,"reason":command.get("reason", ""),"resolved_target":command.get("resolved_target", [])})})
	scenarios.append({"scenario":label,"time":sim.time,"complete":complete,"command_failures":sim.command_failures,"door":sim.doors[0].duplicate(true),"units":rows})
	print("DOOR_ENTRY %s time=%.2f complete=%s failures=%d" % [label,sim.time,complete,sim.command_failures])
	check(complete, label + " all four operators enter without manual replanning")
	check(sim.command_failures == 0, label + " crowding does not fail the door command")
	check(separated, label + " live bodies never overlap")
	check(leaf_clear, label + " door leaf never crosses a body")
	check(continuous, label + " movement remains continuous")
	check(sim._reservations.is_empty(), label + " finished entry releases passage reservations")
