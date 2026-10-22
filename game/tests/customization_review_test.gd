extends SceneTree
## Independent regressions found while reviewing composite-command editing.
const Simulation = preload("res://scripts/simulation.gd")
const Replay = preload("res://scripts/replay.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func fixture() -> Dictionary:
	return {
		"id": "CUSTOM_REVIEW", "seed": 71, "bounds": [20, 16],
		"walls": [{"x": 3.0, "z": 6.0, "w": 6.0, "d": 0.3}, {"x": 12.0, "z": 6.0, "w": 8.0, "d": 0.3}, {"x": 8.0, "z": 9.0, "w": 2.0, "d": 1.0}],
		"props": [], "rooms": [],
		"doors": [{"id": "entry", "x": 7.0, "z": 6.0, "w": 2.0, "d": 0.3, "axis": "x", "state": "CLOSED", "progress": 0.0}],
		"units": [{"id": "alpha", "x": 7.0, "z": 4.0, "facing": PI / 2, "ammo": 0, "reserve_ammo": 0}],
		"enemies": [], "civilians": [],
		"win": [{"type": "reach_zone", "zone": [18, 14, 1, 1]}], "fail": []
	}

func _run() -> void:
	var sim := Simulation.new()
	sim.load_mission(fixture())
	var issued: Dictionary = sim.issue("alpha", "OPEN_AND_FLASH", {"door_id": "entry"}, true)
	check(bool(issued.get("ok", false)), "Valid composite fixture must accept the default landing point")
	if bool(issued.get("ok", false)):
		var original: Dictionary = sim.units[0].commands[0].args.duplicate(true)
		var blocked: Dictionary = sim.update_command_args("alpha", 0, {"door_id": "entry", "target": [8.0, 9.0]})
		check(not bool(blocked.get("ok", false)), "Retargeting flash inside opaque wall must reject before execution")
		check(sim.units[0].commands[0].args == original, "Rejected blocked landing must preserve the original composite target")
		var distant: Dictionary = sim.update_command_args("alpha", 0, {"door_id": "entry", "target": [18.0, 14.0]})
		check(not bool(distant.get("ok", false)), "Out-of-range retarget must reject before the door is opened")
		check(sim.units[0].commands[0].args == original, "Rejected distant landing must preserve the original composite target")
	_muzzle_protection()
	_hidden_door_preview()
	_legacy_tool_string()
	_authored_tools_and_half_ammo()
	_exhausted_sidearm_replay()
	print("BREACH_CUSTOMIZATION_REVIEW_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _muzzle_protection() -> void:
	var data: Dictionary = fixture()
	data.walls = []
	data.doors = []
	data.units = [{"id":"alpha", "x":2.0, "z":5.0, "facing":0.0}, {"id":"bravo", "x":2.50, "z":5.0, "facing":0.0, "ammo":0, "reserve_ammo":0}]
	data.enemies = [{"id":"target", "x":6.0, "z":5.0, "facing":PI, "training":true, "hp":10000.0, "ammo":0, "reserve_ammo":0}]
	var sim := Simulation.new()
	sim.load_mission(data)
	var solution: Dictionary = sim._shot_solution(sim.units[0], sim.enemies[0])
	check(not solution.is_empty(), "Clear room produces a usable shot solution")
	check(not sim.fire_line_clear(sim.units[0], sim.enemies[0], solution), "Friendly standing between body and extended muzzle must prevent firing")
	data.walls = [{"x":2.5, "z":5.0, "w":0.1, "d":4.0, "material":"concrete", "height":2.6}]
	data.units.resize(1)
	sim.load_mission(data)
	sim._refresh_weapon_state(sim.units[0])
	check(absf(float(sim.units[0].weapon_origin[0])-2.0) < 0.001, "Opaque geometry must retract the extended muzzle to the body")
	check(sim._shot_solution(sim.units[0], sim.enemies[0]).is_empty(), "Retracted muzzle must not shoot through opaque concrete")

func _hidden_door_preview() -> void:
	var data: Dictionary = fixture()
	data.walls.pop_back()
	data.doors.append({"id":"hidden", "x":7.0, "z":8.0, "w":2.0, "d":0.3, "axis":"x", "state":"CLOSED", "progress":0.0})
	var closed := Simulation.new()
	closed.load_mission(data)
	check(bool(closed.issue("alpha", "OPEN_AND_FLASH", {"door_id":"entry"}, true).get("ok", false)), "Closed hidden-door fixture accepts its observed entry command")
	data.doors[1].state = "OPEN"
	data.doors[1].progress = 1.0
	var opened := Simulation.new()
	opened.load_mission(data)
	check(bool(opened.issue("alpha", "OPEN_AND_FLASH", {"door_id":"entry"}, true).get("ok", false)), "Open hidden-door fixture accepts the same observed entry command")
	check(not closed._door_observations.has("hidden") and not opened._door_observations.has("hidden"), "The secondary door is unobserved in both preview fixtures")
	var closed_preview: Dictionary = closed.flash_target_preview("alpha", 0, [7.0, 9.5])
	var opened_preview: Dictionary = opened.flash_target_preview("alpha", 0, [7.0, 9.5])
	check(bool(closed_preview.get("ok", false)) == bool(opened_preview.get("ok", false)), "Preview validity must not reveal an unobserved door opening")

func _legacy_tool_string() -> void:
	var data: Dictionary = fixture()
	data.loadout = {"alpha":{"weapon":"standard", "equipment":"smoke"}}
	var sim := Simulation.new()
	sim.load_mission(data)
	check(sim.units.size() == 1, "Legacy tool-string mission must finish loading its operator")
	if sim.units.is_empty(): return
	check(int(sim.units[0].stuns) == 0 and int(sim.units[0].smokes) == 1, "Accepted legacy single-tool string must deploy the selected smoke instead of mission-default flashbangs")
	data.loadout.alpha.equipment = "none"
	sim.load_mission(data)
	check(int(sim.units[0].stuns) == 0 and int(sim.units[0].smokes) == 0 and int(sim.units[0].breaches) == 0, "Accepted legacy empty tool string must not grant mission-default throwables")

func _authored_tools_and_half_ammo() -> void:
	var data: Dictionary = fixture()
	data.units[0].equipment = {"smoke":1, "probe_c1":1}
	var sim := Simulation.new()
	sim.load_mission(data)
	check(int(sim.units[0].stuns) == 0 and int(sim.units[0].smokes) == 1 and int(sim.units[0].cameras) == 1, "Authored unit equipment must deploy matching consumables and camera")
	data.units[0].erase("equipment")
	data.units[0].ammo = 24
	data.units[0].reserve_ammo = 72
	data.modifiers = ["low_ammo"]
	data.loadout = {"alpha":{"weapon":"standard", "sidearm":"pico_p1"}}
	sim.load_mission(data)
	check(int(sim.units[0].primary_ammo) == 12 and int(sim.units[0].primary_reserve_ammo) == 36, "Half-ammo modifier halves primary ammo once")
	check(int(sim.units[0].secondary_ammo) == 6 and int(sim.units[0].secondary_reserve_ammo) == 18, "Half-ammo modifier must also halve the new sidearm ammunition")

func _exhausted_sidearm_replay() -> void:
	var data: Dictionary = Catalog.load("M01")
	data.loadout = {"alpha":{"weapon":"standard", "sidearm":"pico_p1"}}
	var sim := Simulation.new()
	sim.load_mission(data)
	var record := Replay.new()
	record.begin(data)
	record.capture(sim.snapshot(true))
	var unit: Dictionary = sim.units[0]
	sim._switch_weapon_slot(unit, "secondary")
	unit.ammo = 0
	unit.reserve_ammo = 0
	for index: int in range(6):
		sim.step(1.0/30.0)
		record.capture(sim.snapshot(true))
	check(unit.status == "OUT_OF_AMMO", "Exhausted sidearm reaches the real public ammunition status")
	record.finish(sim.snapshot(true))
	var imported := Replay.new()
	var response: Dictionary = imported.load_data(JSON.parse_string(JSON.stringify(record.export_data())))
	check(bool(response.get("ok", false)), "Actual replay containing exhausted sidearm must import: " + str(response.get("message", "")))
