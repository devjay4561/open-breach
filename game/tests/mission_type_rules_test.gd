extends SceneTree
const Catalog = preload("res://scripts/mission_catalog.gd")
const Simulation = preload("res://scripts/simulation.gd")
const Replay = preload("res://scripts/replay.gd")
var checks: int = 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	# Objective scenarios isolate rule evaluation from combat and actor movement.
	# Runtime catalog validation separately proves all authored paths exist.
	for base: String in ["M01","M02","M03"]:
		for variant: String in ["HOSTAGE","ESCORT","INFILTRATION","TIMED","ARREST"]:
			var id: String = base+"_"+variant
			var mission: Dictionary = Catalog.load(id)
			var sim := Simulation.new()
			sim.load_mission(mission)
			sim._check_result()
			check(sim.result.is_empty(),id+" starts incomplete")
			var replay := Replay.new()
			replay.begin(mission)
			replay.capture(sim.snapshot(true))
			match variant:
				"HOSTAGE":
					for civilian: Dictionary in sim.civilians: civilian.secured = true
				"ESCORT":
					var zone: Array = mission.win[0].zone
					for civilian: Dictionary in sim.civilians:
						civilian.x = zone[0]
						civilian.z = zone[1]
						civilian.secured = true
						civilian.status = "FOLLOW"
				"INFILTRATION","TIMED":
					var zone: Array = mission.win[0].zone
					sim.units[0].x = zone[0]
					sim.units[0].z = zone[1]
				"ARREST":
					for enemy: Dictionary in sim.enemies:
						enemy.arrested = true
						enemy.status = "ARRESTED"
						sim.arrests += 1
			sim._check_result()
			check(bool(sim.result.get("success",false)),id+" specified objectives complete without extra rules")
			if variant == "ARREST": check(sim.result.kills == 0 and sim.result.arrests == sim.enemies.size(),id+" arrest completion has no kills")
			replay.capture(sim.snapshot(true))
			var loaded := Replay.new()
			var imported: Dictionary = loaded.load_data(JSON.parse_string(JSON.stringify(replay.export_data())))
			check(bool(imported.get("ok",false)),id+" objective replay round trip: "+str(imported))
			var failed := Simulation.new()
			failed.load_mission(mission)
			match variant:
				"HOSTAGE","ESCORT","ARREST": failed.civilians[0].hp = 0.0
				"INFILTRATION": failed.first_alert_time = 0.0
				"TIMED": failed.time = 25.0 + 1.0/30.0
			failed._check_result()
			check(not failed.result.is_empty() and not bool(failed.result.get("success",true)),id+" mandatory constraint fails")
	# Existing base maps keep their original two completion targets.
	for id: String in ["T01", "M01", "M02", "M03", "M01H", "M02H", "M03H"]:
		var mission: Dictionary = Catalog.load(id)
		var sim := Simulation.new()
		sim.load_mission(mission)
		for enemy: Dictionary in sim.enemies: enemy.hp = 0.0
		for civilian: Dictionary in sim.civilians: civilian.secured = true
		sim._check_result()
		check(bool(sim.result.get("success",false)),id+" old completion semantics")
	# Play the reachable variants through ordinary public movement commands.
	# No runtime positions, health or enemy rules are altered. The exposed
	# archive approach uses the selectable smoke loadout before advancing.
	for base: String in ["M01","M02","M03"]:
		for variant: String in ["INFILTRATION","TIMED"]:
			var id: String = base+"_"+variant
			var mission: Dictionary = Catalog.load(id)
			if base == "M02" or (base == "M03" and variant == "INFILTRATION"): mission["loadout"] = {"alpha":{"weapon":"standard","equipment":{"smoke":1}}}
			var sim := Simulation.new()
			sim.load_mission(mission)
			var replay := Replay.new()
			replay.begin(mission)
			replay.capture(sim.snapshot(true))
			if (base == "M01" and variant == "TIMED") or (base == "M03" and variant == "INFILTRATION"):
				check(bool(sim.configure_unit("alpha",{"movement_mode":"fast","stance":"standing"}).get("ok",false)),id+" player selects a fast traversal")
			if base == "M03" and variant == "INFILTRATION":
				for tick: int in range(30):
					sim.step(1.0/30.0)
					replay.capture(sim.snapshot(true))
				check(sim.result.is_empty() and sim.first_alert_time < 0.0,id+" initial staging does not fail while the squad waits")
				check(bool(sim.issue("alpha","THROW_SMOKE",{"target":[12,17.8]},true).get("ok",false)),id+" smoke is thrown onto the visible outside entrance floor")
			if base == "M02":
				check(bool(sim.issue("alpha","THROW_SMOKE",{"target":[6,16]},true).get("ok",false)),id+" smoke covers the exposed entrance")
			if base == "M02" and variant == "TIMED":
				check(bool(sim.plan_move("bravo",{"target":[6,13.5]},true).get("ok",false)),id+" covering operator enters the lobby")
				sim.issue("bravo","FACE",{"target":[9,12]},true)
			var zone: Array = mission.win[0].zone
			check(bool(sim.plan_move("alpha",{"target":[zone[0],zone[1]]},true).get("ok",false)),id+" ordinary route accepted")
			replay.capture(sim.snapshot(true))
			for tick: int in range(30*26):
				sim.step(1.0/30.0)
				replay.capture(sim.snapshot(true))
				if not sim.result.is_empty(): break
			check(bool(sim.result.get("success",false)),id+" ordinary commands can complete: "+str(sim.result))
			check(sim.command_failures == 0,id+" ordinary route has no execution failures")
			var loaded := Replay.new()
			var imported: Dictionary = loaded.load_data(JSON.parse_string(JSON.stringify(replay.export_data())))
			check(bool(imported.get("ok",false)),id+" full movement replay round trip: "+str(imported))
	print("BREACH_MISSION_TYPE_RULES_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
