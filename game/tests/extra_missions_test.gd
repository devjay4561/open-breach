extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Replay = preload("res://scripts/replay.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func run() -> void:
	for filename: String in ["archive", "depot"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % filename))
		var sim := Simulation.new()
		sim.load_mission(data)
		var replay := Replay.new()
		replay.begin(data)
		replay.capture(sim.snapshot(true))
		# Traversal and observed surrender arrests use ordinary player commands; no actor buffs.
		var points: Array = [[7.5,12],[7.5,8],[9.5,6],[15,6],[17.5,7],[19,4.5]] if filename == "archive" else [[12,13],[8,13],[8,8],[4.3,7.5],[8,3.5],[12,3.5],[12,6],[17,6],[19.5,3.5]]
		for point: Array in points:
			for i: int in range(sim.units.size()):
				var unit: Dictionary = sim.units[i]
				if unit.hp <= 0: continue
				sim.issue(unit.id, "FACE", {"unlock":true})
				var answer: Dictionary = sim.plan_move(unit.id, {"target":[point[0],point[1]+float(i)*0.65]}, false)
				check(bool(answer.get("ok",false)), filename + ": route rejected " + str(point) + str(answer))
			for tick: int in range(30*12):
				arrest_observed(sim)
				secure_observed(sim)
				sim.step(1.0/30.0)
				replay.capture(sim.snapshot(true))
				if not sim.result.is_empty(): break
			for unit: Dictionary in sim.units:
				if unit.hp <= 0: continue
				if unit.ammo < 10: sim.issue(unit.id,"RELOAD",{})
			# Rotate through the authored room while stationary to exercise detection.
			for direction: Array in [[1,0],[0,-1],[-1,0],[0,1]]:
				for unit: Dictionary in sim.units:
					if unit.hp > 0: sim.issue(unit.id,"FACE",{"target":[unit.x+direction[0],unit.z+direction[1]]})
				for tick: int in range(60):
					arrest_observed(sim)
					secure_observed(sim)
					sim.step(1.0/30.0)
					replay.capture(sim.snapshot(true))
			if not sim.result.is_empty(): break
		secure_observed(sim)
		for tick: int in range(30*20):
			arrest_observed(sim)
			secure_observed(sim)
			sim.step(1.0/30.0)
			replay.capture(sim.snapshot(true))
		check(sim.command_failures == 0, filename+": command execution failed")
		check(bool(sim.result.get("success",false)),filename+": traversal did not complete "+JSON.stringify(sim.result)+" objectives "+JSON.stringify(sim.snapshot().objectives))
		var imported := Replay.new()
		check(bool(imported.load_data(replay.export_data()).get("ok",false)),filename+": replay round trip failed")
		print("EXTRA_MISSION "+filename+" "+JSON.stringify(sim.result))
		if sim.result.is_empty(): print("EXTRA_DIAGNOSTIC " + filename + " " + JSON.stringify(sim.snapshot(true)))
	print("BREACH_EXTRA_MISSIONS_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func arrest_observed(sim: RefCounted) -> void:
	if not sim.result.is_empty():
		return
	var state: Dictionary = sim.snapshot()
	for enemy: Dictionary in state.enemies:
		if not bool(enemy.get("visible", false)) or enemy.get("status", "") != "SURRENDERED" or bool(enemy.get("arrested", false)):
			continue
		var already_planned: bool = false
		for unit: Dictionary in state.units:
			for command: Dictionary in unit.commands:
				if command.type == "ARREST" and command.args.get("enemy_id", "") == enemy.id and command.state in ["PENDING", "RUNNING", "WAITING"]:
					already_planned = true
		if already_planned:
			continue
		var operator: Dictionary = {}
		var shortest: float = INF
		for unit: Dictionary in state.units:
			if float(unit.hp) <= 0.0 or float(unit.get("stunned", 0.0)) > 0.0:
				continue
			var busy: bool = false
			for command: Dictionary in unit.commands:
				if command.state == "FAILED" or (command.type == "ARREST" and command.state in ["PENDING", "RUNNING", "WAITING"]):
					busy = true
			if busy:
				continue
			var origin := Vector2(float(unit.x), float(unit.z))
			var route: Array = sim.nav.approach(origin, enemy, 1.0)
			if route.is_empty():
				continue
			var length: float = 0.0
			for coordinate: Array in route:
				var next := Vector2(float(coordinate[0]), float(coordinate[1]))
				length += origin.distance_to(next)
				origin = next
			if length < shortest:
				shortest = length
				operator = unit
		if not operator.is_empty():
			# These are the currently observed coordinates, and every action goes
			# through the same commands available in the player's context menu.
			var face_answer: Dictionary = sim.issue(operator.id, "FACE", {"target": [enemy.x, enemy.z]})
			var arrest_answer: Dictionary = sim.issue(operator.id, "ARREST", {"enemy_id": enemy.id})
			check(bool(face_answer.get("ok", false)) and bool(arrest_answer.get("ok", false)), "%s: observed surrender arrest rejected" % sim.mission.id)

func secure_observed(sim: RefCounted) -> void:
	if not sim.result.is_empty():
		return
	var state: Dictionary = sim.snapshot()
	for civilian: Dictionary in state.civilians:
		if not bool(civilian.get("visible", false)) or bool(civilian.get("secured", false)) or float(civilian.hp) <= 0.0:
			continue
		var planned: bool = false
		for unit: Dictionary in state.units:
			for command: Dictionary in unit.commands:
				if command.type == "SECURE_CIVILIAN" and command.args.get("civilian_id", "") == civilian.id and command.state in ["PENDING", "RUNNING", "WAITING"]:
					planned = true
		if planned:
			continue
		var operator: Dictionary = {}
		var shortest: float = INF
		for unit: Dictionary in state.units:
			if float(unit.hp) <= 0.0 or float(unit.get("stunned", 0.0)) > 0.0:
				continue
			var busy: bool = false
			for command: Dictionary in unit.commands:
				if command.state == "FAILED" or (command.type in ["ARREST", "SECURE_CIVILIAN"] and command.state in ["PENDING", "RUNNING", "WAITING"]):
					busy = true
			if busy:
				continue
			var origin := Vector2(float(unit.x), float(unit.z))
			var route: Array = sim.nav.approach(origin, civilian, 0.8)
			if route.is_empty():
				continue
			var length: float = 0.0
			for coordinate: Array in route:
				var next := Vector2(float(coordinate[0]), float(coordinate[1]))
				length += origin.distance_to(next)
				origin = next
			if length < shortest:
				shortest = length
				operator = unit
		if not operator.is_empty():
			var answer: Dictionary = sim.issue(operator.id, "SECURE_CIVILIAN", {"civilian_id": civilian.id})
			check(bool(answer.get("ok", false)), "%s: observed civilian rescue rejected" % sim.mission.id)
