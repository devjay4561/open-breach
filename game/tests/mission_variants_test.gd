extends SceneTree
## Real T01/M01 data and public planning API; no actor or door state changes.
## Checks input order and recovery, not tactical success or a score target.
const Simulation = preload("res://scripts/simulation.gd")
const STEP := 1.0 / 30.0
var checks := 0
var failures: Array[String] = []
var cases: Array = []
var rejections: Array = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _run() -> void:
	# Prescribed order: fully planned, pause/edit, live edit.
	for filename: String in ["tutorial", "house"]:
		_preplanned(filename)
	for filename: String in ["tutorial", "house"]:
		await _pause_and_edit(filename)
	for filename: String in ["tutorial", "house"]:
		_live_edit(filename)
	var report := {"kind": "headless_command_flow", "checks": checks, "failures": failures, "cases": cases, "rejections": rejections, "passed": failures.is_empty()}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var file := FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			if file:
				file.store_string(JSON.stringify(report, "  ") + "\n")
			else:
				check(false, "Cannot write report: " + argument)
	print("BREACH_MISSION_VARIANTS_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for message: String in failures:
		push_error(message)
	quit(0 if failures.is_empty() else 1)

func load_mission(filename: String) -> RefCounted:
	var instance: RefCounted = Simulation.new()
	instance.load_mission(JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % filename)))
	return instance

func route(filename: String) -> Dictionary:
	return {"near": [6.0, 14.0], "far": [11.8, 11.8], "edit": [10.8, 12.4]} if filename == "tutorial" else {"near": [11.6, 18.8], "far": [12.2, 14.6], "edit": [11.2, 14.8]}

func plan(sim: RefCounted, target: Array, append: bool, label: String) -> Dictionary:
	var answer: Dictionary = sim.plan_move("alpha", {"target": target}, append)
	check(bool(answer.get("ok", false)), label + ": valid movement rejected: " + str(answer.get("message", "")))
	return answer

func issue(sim: RefCounted, type: String, args: Dictionary, label: String) -> void:
	var answer: Dictionary = sim.issue("alpha", type, args, true)
	check(bool(answer.get("ok", false)), label + ": valid " + type + " rejected")

func position(unit: Dictionary) -> Vector2:
	return Vector2(float(unit.x), float(unit.z))

func command_by_id(sim: RefCounted, id: String) -> Dictionary:
	for command: Dictionary in sim.snapshot().units[0].commands:
		if command.id == id:
			return command
	return {}

func all_finished(sim: RefCounted) -> bool:
	for command: Dictionary in sim.snapshot().units[0].commands:
		if command.state not in ["SUCCEEDED", "CANCELLED"]:
			return false
	return true

func run_orders(sim: RefCounted, label: String, target: Array) -> void:
	for tick: int in range(30 * 40):
		if all_finished(sim) or sim.pause_requested or not sim.result.is_empty():
			break
		sim.step(STEP)
	check(not sim.pause_requested, label + ": valid route requested failure pause")
	check(all_finished(sim), label + ": commands remained pending/waiting after 40 simulation seconds")
	check(sim.command_failures == 0, label + ": valid route failed")
	check(position(sim.snapshot().units[0]).distance_to(Vector2(target[0], target[1])) < 0.18, label + ": final destination not reached")
	check(sim.doors[0].state == "OPEN", label + ": route did not actually open its door")
	var completed: int = -1
	for command: Dictionary in sim.snapshot().units[0].commands:
		if command.state == "SUCCEEDED":
			check(int(command.completed_tick) >= completed, label + ": completion order reversed")
			completed = int(command.completed_tick)

func reject_preserves_plan(sim: RefCounted, label: String) -> void:
	var before: String = JSON.stringify(sim.snapshot())
	var answer: Dictionary = sim.plan_move("alpha", {"target": [3.0, 10.0]}, false)
	check(not bool(answer.get("ok", true)), label + ": wall-interior replacement was accepted")
	check(not str(answer.get("message", "")).is_empty(), label + ": invalid input omitted a reason")
	check(JSON.stringify(sim.snapshot()) == before, label + ": rejected input changed queue, time or actor state")
	rejections.append({"case":label, "target":[3.0,10.0], "message":answer.get("message", ""), "preserved_state":JSON.stringify(sim.snapshot()) == before})
	answer = sim.plan_move("alpha", {"target": [100.0, 10.0]}, true)
	check(not bool(answer.get("ok", true)) and not str(answer.get("message", "")).is_empty(), label + ": outside-map input missing rejection/reason")
	check(JSON.stringify(sim.snapshot()) == before, label + ": rejected outside-map append changed the valid plan")
	rejections.append({"case":label, "target":[100.0,10.0], "message":answer.get("message", ""), "preserved_state":JSON.stringify(sim.snapshot()) == before})

func record_case(sim: RefCounted, label: String, previous_failures: int) -> void:
	var state: Dictionary = sim.snapshot()
	var commands: Array = []
	for command: Dictionary in state.units[0].commands:
		commands.append({"id":command.id, "type":command.type, "state":command.state, "reason":command.reason, "started_tick":command.get("started_tick", -1), "completed_tick":command.get("completed_tick", -1)})
	var entry := {"mission":sim.mission.id, "input_mode":label, "passed":failures.size() == previous_failures, "simulation_seconds":sim.time, "commands":commands, "position":[state.units[0].x,state.units[0].z], "command_failures":sim.command_failures}
	cases.append(entry)
	print("MISSION_INPUT_VARIANT " + JSON.stringify(entry))

func _preplanned(filename: String) -> void:
	var sim: RefCounted = load_mission(filename)
	var destinations: Dictionary = route(filename)
	var label := filename + "/fully_preplanned"
	var before := failures.size()
	plan(sim, destinations.near, true, label)
	plan(sim, destinations.far, true, label)
	issue(sim, "FACE", {"target":[destinations.far[0], float(destinations.far[1])-3.0]}, label)
	issue(sim, "WAIT", {"duration":0.4}, label)
	check(sim.tick == 0, label + ": planning advanced simulation")
	var door_count := 0
	for command: Dictionary in sim.snapshot().units[0].commands:
		if command.type == "OPEN_DOOR": door_count += 1
	check(door_count == 1, label + ": expected one automatic door before cross-room movement")
	reject_preserves_plan(sim, label)
	run_orders(sim, label, destinations.far)
	record_case(sim, label, before)

func _pause_and_edit(filename: String) -> void:
	var sim: RefCounted = load_mission(filename)
	var destinations: Dictionary = route(filename)
	var label := filename + "/pause_and_edit"
	var before := failures.size()
	var original: Dictionary = plan(sim, destinations.near, true, label)
	for tick: int in range(9): sim.step(STEP)
	var frozen := JSON.stringify(sim.snapshot())
	await create_timer(0.06).timeout
	check(JSON.stringify(sim.snapshot()) == frozen, label + ": wall-clock pause changed simulation")
	reject_preserves_plan(sim, label)
	var pause_tick: int = sim.tick
	plan(sim, destinations.far, false, label)
	issue(sim, "WAIT", {"duration":0.25}, label)
	check(sim.tick == pause_tick, label + ": editing while paused advanced time")
	check(command_by_id(sim, str(original.get("id", ""))).get("state", "") == "CANCELLED", label + ": active old move was not cancelled by replacement")
	run_orders(sim, label, destinations.far)
	record_case(sim, label, before)

func _live_edit(filename: String) -> void:
	var sim: RefCounted = load_mission(filename)
	var destinations: Dictionary = route(filename)
	var label := filename + "/edit_during_execution"
	var before := failures.size()
	var original: Dictionary = plan(sim, destinations.far, false, label)
	var running := false
	for tick: int in range(30 * 20):
		if sim.pause_requested: break
		sim.step(STEP)
		var movement: Dictionary = command_by_id(sim, str(original.get("id", "")))
		if movement.get("state", "") == "RUNNING":
			running = true
			break
	check(running, label + ": never reached movement after opening its door")
	if running:
		reject_preserves_plan(sim, label)
		var tick_before: int = sim.tick
		plan(sim, destinations.edit, false, label)
		issue(sim, "WAIT", {"duration":0.2}, label)
		check(command_by_id(sim, str(original.get("id", ""))).get("state", "") == "CANCELLED", label + ": running move survived explicit replacement")
		sim.step(STEP)
		check(sim.tick == tick_before + 1, label + ": command edit interrupted the next execution tick")
		run_orders(sim, label, destinations.edit)
	record_case(sim, label, before)
