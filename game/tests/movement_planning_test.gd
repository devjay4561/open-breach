extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
func _run() -> void:
	for mission: String in ["tutorial", "house"]:
		var sim: BreachSimulation = Simulation.new()
		sim.load_mission(JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % mission)))
		var target: Array = [12.0, 10.5] if mission == "tutorial" else [12.0, 15.5]
		var initial: Array = [6.0, 17.5] if mission == "tutorial" else [12.0, 19.0]
		_check(sim.plan_move("alpha", {"target": initial}, false).ok, mission + ": accessible paused move")
		var before: String = JSON.stringify(sim.units[0].commands)
		_check(sim.plan_move("alpha", {"target": target}, false).ok, mission + ": closed door automatically planned")
		_check(sim.units[0].commands[-2].type == "OPEN_DOOR", mission + ": automatic door precedes move")
		sim.cancel_pending("alpha")
		sim.units[0].commands.clear()
		sim.plan_move("alpha", {"target": initial}, false)
		sim.issue("alpha", "OPEN_DOOR", {"door_id": "d1"})
		var response: Dictionary = sim.plan_move("alpha", {"target": target}, false)
		_check(response.ok and response.get("preserved_door_plan", false), mission + ": right click preserves explicit door plan")
		_check(sim.units[0].commands[1].state == "PENDING", mission + ": door remains pending")
		_check(sim.tick == 0, mission + ": planning never advances time")
		before = JSON.stringify(sim.units[0].commands)
		_check(not sim.plan_move("alpha", {"target": [3.0, 4.0]}, false).ok, mission + ": wall target rejected")
		_check(JSON.stringify(sim.units[0].commands) == before, mission + ": invalid target preserves door sequence")
		# Isolate navigation execution from combat interruptions.
		for enemy: Dictionary in sim.enemies:
			enemy["training"] = true
		for i: int in range(1200):
			sim.step(1.0 / 30.0)
			if sim.units[0].commands.back().state in ["SUCCEEDED", "FAILED"]:
				break
		_check(sim.units[0].commands.back().state == "SUCCEEDED", mission + ": planned door traversal executes")
		_check(sim.doors[0].state == "OPEN", mission + ": door actually opened")
	for mission: String in ["archive", "archive_challenge"]:
		for reverse: bool in [false, true]:
			var loop: BreachSimulation = Simulation.new()
			loop.load_mission(JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % mission)))
			loop.units[0]["x"] = 17.0
			loop.units[0]["z"] = 12.5 if reverse else 8.0
			for door: Dictionary in loop.doors:
				if door.id != "a2":
					door.state = "OPEN"
					door["open_progress"] = 1.0
			loop.nav.invalidate_dynamic()
			for enemy: Dictionary in loop.enemies:
				enemy["training"] = true
			var destination: Array = [17.0, 8.0 if reverse else 12.5]
			var label: String = mission + (" reverse" if reverse else " office exit")
			_check(loop.plan_move("alpha", {"target": destination}, false).ok, label + ": accepted")
			var orders: Array = loop.units[0].commands
			_check(orders.size() == 2 and orders[0].type == "OPEN_DOOR" and orders[0].args.get("door_id") == "a2", label + ": direct door preferred over open detour")
			var min_x: float = 17.0
			for i: int in range(900):
				loop.step(1.0 / 30.0)
				min_x = minf(min_x, float(loop.units[0].x))
				if orders.back().state in ["SUCCEEDED", "FAILED"]:
					break
			_check(orders.back().state == "SUCCEEDED", label + ": traversal completes")
			_check(min_x > 14.0, label + ": never detours through archive")
	var chain: BreachSimulation = Simulation.new()
	chain.load_mission(JSON.parse_string(FileAccess.get_file_as_string("res://data/tutorial.json")))
	# Navigation must finish even when faster shooting would end the tutorial early.
	for unit: Dictionary in chain.units:
		unit.ammo = 0
		unit.reserve_ammo = 0
	var answer: Dictionary = chain.plan_move("alpha", {"target": [18.0, 10.3], "request_id": "auto-doors"}, false)
	_check(answer.ok, "Multiple closed doors accepted")
	_check(chain.units[0].commands.size() == 3, "Exactly two doors plus move")
	_check(chain.units[0].commands[0].args.door_id == "d1" and chain.units[0].commands[1].args.door_id == "d2", "Doors in crossing order")
	_check(chain.plan_move("alpha", {"target": [18.0, 10.3], "request_id": "auto-doors"}, false) == answer and chain.units[0].commands.size() == 3, "Automatic plan request idempotent")
	for enemy: Dictionary in chain.enemies:
		enemy["training"] = true
	for i: int in range(1500):
		chain.step(1.0 / 30.0)
		if chain.units[0].commands.back().state in ["SUCCEEDED", "FAILED"]:
			break
	_check(chain.units[0].commands.back().state == "SUCCEEDED", "Two-door automatic route completes")
	chain.load_mission(JSON.parse_string(FileAccess.get_file_as_string("res://data/tutorial.json")))
	for i: int in range(30):
		chain.issue("alpha", "WAIT", {"duration": 1})
	var unchanged: String = JSON.stringify(chain.units[0].commands)
	_check(not chain.plan_move("alpha", {"target": [18.0, 10.3]}, true).ok, "Auto-door queue capacity checked")
	_check(unchanged == JSON.stringify(chain.units[0].commands), "Capacity failure is atomic")
	print("BREACH_MOVEMENT_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
