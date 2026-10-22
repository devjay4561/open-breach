extends SceneTree
## Regression: accepted plans must produce replay files the importer can read.

const Simulation = preload("res://scripts/simulation.gd")
const Replay = preload("res://scripts/replay.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _run() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tutorial.json"))
	var sim: BreachSimulation = Simulation.new()
	sim.load_mission(map)
	_check(bool(sim.issue("alpha", "WAIT", {})["ok"]), "WAIT omitted duration must use documented default")
	_check(sim.units[0]["commands"][0]["args"] == {"duration": 1.0}, "WAIT default must be persisted canonically")
	_check(bool(sim.issue("alpha", "WAIT_FOR_SIGNAL", {})["ok"]), "Signal omitted channel must use A")
	_check(sim.units[0]["commands"][1]["args"] == {"signal": "A"}, "Signal default must be persisted canonically")
	_check(bool(sim.issue("alpha", "FACE", {"unlock": true})["ok"]), "FACE unlock must remain supported")
	var invalid: Array = [
		["WAIT", {"duration": 1.0, "script": "res://example.gd"}],
		["WAIT_FOR_SIGNAL", {"signal": "A", "target": [4, 4]}],
		["RELOAD", {"duration": 0}],
		["FACE", {"unlock": true, "target": [4, 4]}],
		["FACE", {"unlock": false}],
		["FACE", {"unlock": "true"}],
		["WAIT", {"request_id": 45}],
		["WAIT", {"request_id": "../../script"}],
		["WAIT", {"request_id": ""}],
		["WAIT", {"request_id": "a".repeat(65)}],
		["CANCEL_PENDING", {"unexpected": true}],
	]
	var before: int = sim.units[0]["commands"].size()
	for attempt: Array in invalid:
		_check(not bool(sim.issue("alpha", str(attempt[0]), attempt[1])["ok"]), "Unsupported arguments accepted: " + JSON.stringify(attempt))
	_check(sim.units[0]["commands"].size() == before, "Rejected command mutated queue")
	var first: Dictionary = sim.issue("alpha", "RELOAD", {"request_id": "safe-request:001"})
	var duplicate: Dictionary = sim.issue("alpha", "RELOAD", {"request_id": "safe-request:001"})
	_check(bool(first["ok"]) and first == duplicate, "Request idempotency must preserve first result")
	_check(sim.units[0]["commands"].size() == before + 1, "Repeated request duplicated command")
	var recorder: BreachReplay = Replay.new()
	recorder.begin(map)
	recorder.capture(sim.snapshot(true))
	for i: int in range(45):
		sim.step(1.0 / 30.0)
		recorder.capture(sim.snapshot(true))
	sim.release_signal("A")
	for i: int in range(8):
		sim.step(1.0 / 30.0)
		recorder.capture(sim.snapshot(true))
	recorder.finish(sim.snapshot(true))
	var exported: Dictionary = JSON.parse_string(JSON.stringify(recorder.export_data()))
	var imported: BreachReplay = Replay.new()
	var response: Dictionary = imported.load_data(exported)
	_check(bool(response.get("ok", false)), "Canonical command replay rejected: " + str(response.get("message", "")))
	print("BREACH_COMMAND_SCHEMA_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
