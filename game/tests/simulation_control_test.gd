extends SceneTree
## Control regressions: real command execution, ownership, interruption and recovery.
const Simulation = preload("res://scripts/simulation.gd")
const Replay = preload("res://scripts/replay.gd")
const Door = preload("res://scripts/door_geometry.gd")
const DT: float = 1.0 / 30.0
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func actor(id: String, x: float, z: float) -> Dictionary:
	return {"id": id, "name": id.to_upper(), "x": x, "z": z, "facing": -PI * 0.5, "weapon": "standard"}

func fixture() -> Dictionary:
	return {"id": "CONTROL", "seed": 42, "bounds": [16, 12], "walls": [], "props": [], "doors": [], "units": [actor("alpha", 2, 5)], "enemies": [], "civilians": []}

func doorway() -> Dictionary:
	var data: Dictionary = fixture()
	data.walls = [{"x": 3.05, "z": 6.0, "w": 6.1, "d": 0.24}, {"x": 11.95, "z": 6.0, "w": 8.1, "d": 0.24}]
	# This ownership fixture opens away from its operator. Pull-side physical
	# retreat is exercised separately by door_realism_test from both sides.
	data.doors = [{"id": "d1", "x": 7.0, "z": 6.0, "w": 1.8, "d": 0.24, "axis": "x", "swing_sign": 1.0}]
	var handle: Vector2 = Door.handle_floor(data.doors[0])
	data.units = [actor("alpha", handle.x, handle.y + Door.APPROACH_DISTANCE), actor("bravo", 4.5, 10.0)]
	return data

func simulation(data: Dictionary) -> BreachSimulation:
	var sim: BreachSimulation = Simulation.new()
	sim.load_mission(data)
	return sim

func advance(sim: BreachSimulation, seconds: float) -> void:
	for i: int in range(ceili(seconds / DT)):
		sim.step(DT)

func pos(entity: Dictionary) -> Vector2:
	return Vector2(float(entity.x), float(entity.z))

func _run() -> void:
	_test_exclusive_owner()
	_test_four_reservations()
	_test_cancel_and_resume()
	_test_owner_incapacitated()
	_test_owner_stunned()
	_test_swing_recovery()
	_test_move_replacement()
	_test_future_leaf_rejection()
	_test_crossing()
	_test_front_wait_recovery()
	_test_stationary_turn_metadata()
	_test_replay_owner()
	_test_instant_unlock()
	_test_facing_modes()
	print("BREACH_SIMULATION_CONTROL_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_exclusive_owner() -> void:
	var sim: BreachSimulation = simulation(doorway())
	sim.issue("alpha", "OPEN_DOOR", {"door_id": "d1"})
	sim.issue("bravo", "OPEN_DOOR", {"door_id": "d1"})
	advance(sim, 0.2)
	check(sim.doors[0].owner_id == "alpha", "Only the nearby operator owns the opening door")
	check(sim.units[0].status == "OPENING", "Owner has the opening interaction status")
	check(sim.units[1].status == "MOVING", "Distant duplicate operator approaches instead of opening remotely")
	check(float(sim.units[1].commands[0].remaining) == 0.0, "Non-owner does not receive another operator's interaction countdown")
	check(str(sim.units[0].status_reason).contains("담당"), "Opening status explains who performs the action")
	advance(sim, 1.0)
	check(sim.doors[0].state == "OPEN", "Owner completes opening")
	check(sim.doors[0].owner_id == "" and sim.doors[0].owner_command_id == "", "Completed door releases its owner token")
	check(sim.units[1].commands[0].state == "SUCCEEDED", "Duplicate OPEN succeeds idempotently after actual opening")

func _test_four_reservations() -> void:
	var data: Dictionary = doorway()
	data.units.append(actor("charlie", 3.8, 8.5))
	data.units.append(actor("delta", 10.5, 9.0))
	var sim: BreachSimulation = simulation(data)
	for index: int in range(4):
		var id: String = sim.units[index].id
		check(bool(sim.plan_move(id, {"target": [5.0 + index, 3.0]}, true).ok), "Automatic opening accepted for " + id)
		advance(sim, 0.1)
	var ownership_consistent: bool = true
	var separation: bool = true
	for i: int in range(450):
		sim.step(DT)
		for unit: Dictionary in sim.units:
			if unit.status == "OPENING" and unit.id != sim.doors[0].owner_id:
				ownership_consistent = false
		for a: int in range(4):
			for b: int in range(a + 1, 4):
				if pos(sim.units[a]).distance_to(pos(sim.units[b])) < 0.459:
					separation = false
	check(ownership_consistent, "Four reservations never create two simultaneous operators")
	check(separation, "Four crossing operators never overlap")
	for unit: Dictionary in sim.units:
		check(unit.commands.back().state == "SUCCEEDED", "Four-reservation route finishes: " + str(unit.id) + " / " + JSON.stringify(unit.commands.back()))
	var opened: int = 0
	for event: Dictionary in sim.events:
		if event.type == "DOOR_OPEN":
			opened += 1
	check(opened == 1, "Repeated reservations emit only one completed opening")

func _test_cancel_and_resume() -> void:
	var sim: BreachSimulation = simulation(doorway())
	sim.issue("alpha", "OPEN_DOOR", {"door_id": "d1"})
	advance(sim, 0.3)
	var partial: float = sim.doors[0].progress
	sim.remove_command("alpha", 0)
	check(sim.units[0].commands[0].state == "CANCELLED", "An active door interaction can be safely cancelled")
	check(sim.doors[0].owner_id == "", "Cancel immediately releases door ownership")
	advance(sim, 0.3)
	check(is_equal_approx(partial, float(sim.doors[0].progress)), "Unowned partial opening freezes without refund or autonomous continuation")
	sim.plan_move("alpha", {"target": [10.0, 9.0]}, false)
	sim.issue("bravo", "OPEN_DOOR", {"door_id": "d1"})
	advance(sim, 5.0)
	check(sim.doors[0].state == "OPEN", "Another operator reaches and resumes a cancelled partial opening")
	check(sim.units[1].commands[0].state == "SUCCEEDED", "Replacement operator completes its command")
	check(int(sim.command_failures) == 0, "Owner handover does not create a failed command")

func _test_owner_incapacitated() -> void:
	var sim: BreachSimulation = simulation(doorway())
	sim.issue("alpha", "OPEN_DOOR", {"door_id": "d1"})
	advance(sim, 0.3)
	sim.units[0].hp = 0.0
	var progress: float = sim.doors[0].progress
	sim.step(DT)
	check(sim.doors[0].owner_id == "", "Incapacitated owner is released on the next authoritative tick")
	check(is_equal_approx(progress, float(sim.doors[0].progress)), "Incapacitated owner cannot advance the leaf")
	sim.issue("bravo", "OPEN_DOOR", {"door_id": "d1"})
	advance(sim, 5.0)
	check(sim.doors[0].state == "OPEN", "Another living operator can finish an incapacitated owner's door")

func _test_owner_stunned() -> void:
	var sim: BreachSimulation = simulation(doorway())
	sim.issue("alpha", "OPEN_DOOR", {"door_id": "d1"})
	advance(sim, 0.3)
	sim.units[0].stunned = 0.7
	var progress: float = sim.doors[0].progress
	advance(sim, 0.4)
	check(sim.doors[0].owner_id == "" and is_equal_approx(progress, float(sim.doors[0].progress)), "Stunned operator releases and pauses the interaction")
	advance(sim, 1.5)
	check(sim.doors[0].state == "OPEN", "Recovered operator resumes its still-valid command")

func _test_swing_recovery() -> void:
	var data: Dictionary = doorway()
	data.doors[0].swing_sign = 1.0
	var obstruction: Dictionary = Door.movement_obstacle(data.doors[0], 0.65)
	data.units[1].x = obstruction.x
	data.units[1].z = obstruction.z
	data.units[1]["hold_position"] = true
	var sim: BreachSimulation = simulation(data)
	sim.issue("alpha", "OPEN_DOOR", {"door_id": "d1"})
	advance(sim, 1.5)
	check(sim.doors[0].blocked and sim.doors[0].state == "OPENING", "Occupied swing area pauses the leaf")
	check(sim.units[0].status == "WAITING" and str(sim.units[0].status_reason).contains("회전"), "Blocked operator reports the actual obstruction")
	check(not Door.overlaps_actor(sim.doors[0], float(sim.doors[0].progress), pos(sim.units[1]), 0.23), "Blocked leaf never intersects the occupant")
	sim.units[1]["hold_position"] = false
	check(bool(sim.plan_move("bravo", {"target": [4.0, 3.0]}, false).ok), "Swing occupant receives a valid move away")
	advance(sim, 3.0)
	check(sim.doors[0].state == "OPEN", "Cleared swing area resumes without issuing OPEN again")

func _test_move_replacement() -> void:
	var data: Dictionary = fixture()
	data.walls = [{"x": 10.0, "z": 5.0, "w": 1.0, "d": 1.0}]
	var sim: BreachSimulation = simulation(data)
	sim.plan_move("alpha", {"target": [8.0, 5.0]}, false)
	advance(sim, 0.5)
	var before: String = JSON.stringify(sim.units[0].commands)
	check(not bool(sim.plan_move("alpha", {"target": [10.0, 5.0]}, false).ok), "Solid destination is rejected during movement")
	check(before == JSON.stringify(sim.units[0].commands), "Rejected replacement preserves the existing active plan exactly")
	check(bool(sim.plan_move("alpha", {"target": [3.0, 9.0]}, false).ok), "Valid replacement is accepted while moving")
	check(sim.units[0].commands[0].state == "CANCELLED", "Valid replacement safely cancels prior active movement")
	advance(sim, 3.0)
	check(pos(sim.units[0]).distance_to(Vector2(3, 9)) < 0.15, "Replacement route reaches its new target")
	sim.plan_move("alpha", {"target": [6.0, 9.0]}, true)
	sim.step(DT)
	sim.remove_command("alpha", sim.units[0].commands.size() - 1)
	var stopped: Vector2 = pos(sim.units[0])
	advance(sim, 0.4)
	check(pos(sim.units[0]).distance_to(stopped) < 0.001, "Cancel interrupts active movement without residual displacement")

func _test_crossing() -> void:
	var data: Dictionary = fixture()
	data.walls = [{"x": 5.0, "z": 6.0, "w": 0.3, "d": 10.0}, {"x": 6.4, "z": 6.0, "w": 0.3, "d": 10.0}]
	data.units = [actor("alpha", 5.7, 3.0), actor("bravo", 5.7, 9.0)]
	var sim: BreachSimulation = simulation(data)
	sim.issue("alpha", "MOVE", {"target": [5.7, 9.0]})
	sim.issue("bravo", "MOVE", {"target": [5.7, 3.0]})
	var overlap: bool = false
	for i: int in range(360):
		sim.step(DT)
		if pos(sim.units[0]).distance_to(pos(sim.units[1])) < 0.459:
			overlap = true
	check(not overlap, "Opposing traffic preserves actor separation")
	check(sim.units[0].commands[0].state == "SUCCEEDED" and sim.units[1].commands[0].state == "SUCCEEDED", "Opposing routes recover and pass in a narrow corridor")

func _test_future_leaf_rejection() -> void:
	for side: float in [1.0, -1.0]:
		var data: Dictionary = doorway()
		data.units[0].z = 6.0 + side * Door.APPROACH_DISTANCE
		# Author the leaf into the destination-side room so this plan really
		# requires opening. A fixed leaf's future room is not operator-dependent.
		data.doors[0].swing_sign = side
		var predicted: Dictionary = data.doors[0].duplicate(true)
		predicted.swing_sign = Door.opening_sign(predicted, pos(data.units[0]))
		var future: Dictionary = Door.movement_obstacle(predicted, 1.0)
		var sim: BreachSimulation = simulation(data)
		sim.issue("alpha", "WAIT", {"duration": 2.0})
		var before: String = JSON.stringify(sim.units[0].commands)
		var response: Dictionary = sim.plan_move("alpha", {"target": [future.x, future.z]}, false)
		check(not bool(response.ok), "Future open-leaf destination is rejected before automatic opening, side " + str(side))
		check(str(response.message).contains("문짝"), "Future-leaf rejection identifies the obstacle")
		check(before == JSON.stringify(sim.units[0].commands), "Impossible future-leaf replacement preserves the prior plan")
		sim.cancel_pending("alpha")
		sim.issue("alpha", "OPEN_DOOR", {"door_id": "d1"})
		var queue: String = JSON.stringify(sim.units[0].commands)
		response = sim.plan_move("alpha", {"target": [future.x, future.z]}, true)
		check(not bool(response.ok) and queue == JSON.stringify(sim.units[0].commands), "Explicit queued OPEN also validates its future leaf before appending MOVE")

func _test_front_wait_recovery() -> void:
	var data: Dictionary = fixture()
	data.walls = [{"x": 5.0, "z": 6.0, "w": 0.3, "d": 10.0}, {"x": 6.15, "z": 6.0, "w": 0.3, "d": 10.0}]
	data.units = [actor("alpha", 5.575, 8.0), actor("bravo", 5.575, 5.0)]
	var sim: BreachSimulation = simulation(data)
	sim.issue("alpha", "MOVE", {"target": [5.575, 3.0]})
	sim.issue("bravo", "WAIT", {"duration": 10.0})
	sim.issue("bravo", "MOVE", {"target": [5.575, 1.0]})
	advance(sim, 9.5)
	check(sim.units[0].commands[0].state != "FAILED", "A temporary ten-second obstruction does not permanently fail the following route")
	advance(sim, 5.0)
	check(sim.units[0].commands[0].state == "SUCCEEDED", "Following actor resumes after the front actor moves")
	check(int(sim.command_failures) == 0, "Temporary traffic recovery needs no plan repair")

func _test_replay_owner() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json"))
	var sim: BreachSimulation = simulation(map)
	var record: BreachReplay = Replay.new()
	record.begin(map)
	sim.issue("alpha", "OPEN_DOOR", {"door_id": "d1"})
	record.capture(sim.snapshot(true))
	var owned_at: float = -1.0
	var owner: String = ""
	for i: int in range(90):
		sim.step(DT)
		record.capture(sim.snapshot(true))
		if not str(sim.doors[0].owner_id).is_empty():
			owned_at = sim.time
			owner = sim.doors[0].owner_id
	record.finish(sim.snapshot(true))
	check(owned_at > 0.0, "Real mission records an owner interaction")
	var exported: Dictionary = JSON.parse_string(JSON.stringify(record.export_data()))
	var imported: BreachReplay = Replay.new()
	var validation: Dictionary = imported.load_data(exported)
	check(bool(validation.ok), "Door ownership/reasons pass strict replay validation: " + str(validation.message))
	if bool(validation.ok):
		var state: Dictionary = imported.seek(owned_at, true)
		check(state.doors[0].owner_id == owner, "Replay seek restores the recorded operator")
		check(state.units[0].status_reason == "담당 대원이 문을 조작하는 중", "Replay seek restores the interaction explanation")
		check(imported.seek(imported.duration, true).doors[0].owner_id == "", "Replay final state releases completed ownership")

func _test_stationary_turn_metadata() -> void:
	var sim: BreachSimulation = simulation(fixture())
	sim.issue("alpha", "FACE", {"target": [8.0, 5.0]})
	sim.step(DT)
	check(is_equal_approx(float(sim.units[0].turn_started_at), sim.time), "Stationary turn starts at the authoritative simulation timestamp")
	var first_turn: float = float(sim.units[0].turn_delta)
	check(first_turn > 0.0 and first_turn <= 5.2 * DT + 0.00001 and is_equal_approx(first_turn, angle_difference(-PI * 0.5, float(sim.units[0].body_facing))), "Stationary turn metadata preserves the signed bounded authoritative body turn")
	var frozen: Dictionary = sim.snapshot()
	check(frozen.units[0].turn_delta == sim.snapshot().units[0].turn_delta, "Paused snapshots do not advance authored turn phase")
	advance(sim, 0.9)
	check(absf(angle_difference(float(sim.units[0].body_facing), 0.0)) < 0.001, "Bounded body turn reaches the requested watch direction")
	check(is_zero_approx(float(sim.units[0].turn_delta)), "Presentation turn ends after the authored clip window")
	sim.issue("alpha", "FACE", {"target": [2.0, 10.0]})
	sim.step(DT)
	sim.issue("alpha", "MOVE", {"target": [4.0, 5.0]})
	sim.step(DT)
	check(is_zero_approx(float(sim.units[0].turn_delta)), "Moving gait takes precedence over a stationary turn clip")

func _test_instant_unlock() -> void:
	var sim: BreachSimulation = simulation(fixture())
	sim.issue("alpha", "FACE", {"target": [2.0, 2.0]})
	sim.step(DT)
	check(sim.units[0].facing_locked, "Facing test begins locked")
	var frozen_time: float = sim.time
	check(sim.unlock_facing("alpha"), "HUD unlock accepts a living unit")
	check(not sim.units[0].facing_locked and sim.time == frozen_time, "HUD unlock applies while paused without advancing time")
	check(bool(sim.plan_move("alpha", {"target": [8.0, 5.0]}, false).ok), "Immediate move after HUD unlock is accepted")
	advance(sim, 0.2)
	check(not sim.units[0].facing_locked, "Movement replacement must not cancel HUD unlock")
	check(not sim.unlock_facing("missing"), "Unknown unit cannot be unlocked")

func _test_facing_modes() -> void:
	var sim := simulation(fixture())
	sim.issue("alpha", "FACE", {"target": [2, 1]})
	sim.step(DT)
	check(sim.units[0].facing_locked and not sim.units[0].facing_persistent, "Default FACE is a temporary look")
	sim.issue("alpha", "WAIT", {"duration": 0.5})
	sim.issue("alpha", "MOVE", {"target": [6, 5]})
	check(sim.units[0].facing_locked, "Queuing a move does not release facing while paused")
	advance(sim, 0.3)
	check(sim.units[0].facing_locked and is_equal_approx(sim.units[0].facing, -PI/2), "A normal look remains during a wait")
	advance(sim, 1.0)
	check(not sim.units[0].facing_locked and absf(sim.units[0].facing)<0.05, "Normal facing releases when movement begins and follows the route")
	advance(sim, 2.0)
	sim.issue("alpha", "FACE", {"target": [6, 1]})
	advance(sim, 0.1)
	check(sim.units[0].facing_locked, "A look after arrival remains at the destination")
	# A deliberate strafe retains one angle through multiple movement segments.
	var data := fixture()
	sim=simulation(data)
	sim.issue("alpha", "FACE", {"target": [2, 10], "persistent": true})
	sim.issue("alpha", "MOVE", {"target": [6, 5]})
	sim.issue("alpha", "MOVE", {"target": [6, 2]})
	# Persistent watch includes lateral and reverse travel, whose mobility is
	# now slower than forward travel. Verify arrival after a bounded 6s window.
	advance(sim, 6.0)
	check(pos(sim.units[0]).distance_to(Vector2(6,2))<0.15, "Persistent facing does not block path movement")
	check(sim.units[0].facing_locked and sim.units[0].facing_persistent and is_equal_approx(sim.units[0].facing, PI/2), "Explicit strafe retains its angle through a path bend")
	check(is_equal_approx(sim.units[0].aim_facing, PI/2), "Persistent facing also drives the weapon presentation")
	# Round-trip a real installed mission, including the queued FACE argument.
	var replay_map: Dictionary = preload("res://scripts/mission_catalog.gd").load("T01")
	var replay_sim := simulation(replay_map)
	replay_sim.issue("alpha", "FACE", {"target": [5.7, 10], "persistent": true})
	replay_sim.issue("alpha", "MOVE", {"target": [3.5, 17.65]})
	var record := Replay.new()
	record.begin(replay_map)
	record.capture(replay_sim.snapshot(true))
	for i: int in range(30):
		replay_sim.step(DT)
		record.capture(replay_sim.snapshot(true))
	var restored:=Replay.new()
	var exported:Dictionary=record.export_data()
	var imported:Dictionary=restored.load_data(exported)
	check(bool(imported.get("ok",false)), "Both the persistent FACE argument and actor state import in replay: "+str(imported))
	if bool(imported.get("ok",false)):check(bool(restored.seek(restored.duration,true).units[0].get("facing_persistent",false)), "Replay seeking preserves persistent facing")
	sim.issue("alpha", "FACE", {"target": [6, 10]})
	sim.step(DT)
	check(not sim.units[0].facing_persistent, "An ordinary FACE replaces an earlier persistent mode")
	sim.issue("alpha", "MOVE", {"target": [9, 2]})
	advance(sim, 0.5)
	check(not sim.units[0].facing_locked and absf(sim.units[0].facing)<0.05, "Normal facing after strafe releases on the next move")
	sim.issue("alpha", "FACE", {"target": [9, 10], "persistent": true},false)
	sim.step(DT)
	check(sim.unlock_facing("alpha") and not sim.units[0].facing_locked and not sim.units[0].facing_persistent, "Immediate release clears persistent mode as well")
	check(not bool(sim.issue("alpha","FACE",{"target":[9,10],"persistent":"yes"}).get("ok",false)), "Persistent mode rejects a non-boolean command argument")
	check(not bool(sim.issue("alpha","FACE",{"unlock":true,"persistent":true}).get("ok",false)), "Unlock cannot also enable persistent mode")
	sim=simulation(doorway())
	sim.issue("alpha","FACE",{"target":[7,11]})
	sim.step(DT)
	sim.issue("alpha","OPEN_DOOR",{"door_id":"d1"})
	sim.step(DT)
	check(not sim.units[0].facing_locked, "Approaching a door also releases an ordinary look")
