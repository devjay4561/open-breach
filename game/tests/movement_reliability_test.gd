extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Navigation = preload("res://scripts/navigation.gd")
const STEP := 1.0 / 30.0
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture() -> Dictionary:
	return {"id":"MOVEMENT_RELIABILITY", "seed":51, "bounds":[12,12], "walls":[], "props":[], "doors":[], "rooms":[], "units":[{"id":"alpha","x":2.0,"z":6.0,"facing":0.0,"ammo":0}], "enemies":[], "civilians":[], "win":[{"type":"reach_zone","zone":[11,11,0.2,0.2]}], "fail":[]}

func simulation(data: Dictionary) -> RefCounted:
	var sim := Simulation.new()
	sim.load_mission(data)
	for actor: Dictionary in sim.units + sim.enemies + sim.civilians:
		actor["ammo"] = 0
		actor["reserve_ammo"] = 0
	return sim

func separated(sim: RefCounted) -> bool:
	var actors: Array = sim.units + sim.enemies + sim.civilians
	for i: int in range(actors.size()):
		for j: int in range(i + 1, actors.size()):
			if float(actors[i].hp) > 0 and float(actors[j].hp) > 0 and sim._position(actors[i]).distance_to(sim._position(actors[j])) < Navigation.RADIUS * 2.0 - 0.00001:
				return false
	return true

func advance(sim: RefCounted, frames: int) -> bool:
	var safe := true
	for i: int in range(frames):
		sim.step(STEP)
		safe = safe and separated(sim)
	return safe

func finished(sim: RefCounted, index: int = 0) -> bool:
	return sim.units[index].commands[0].state == "SUCCEEDED"

func run() -> void:
	_open_blocker()
	_all_factions()
	_occupied_target()
	_held_actor()
	_opposing_traffic()
	_lane_traffic()
	_wait_recovery()
	_hidden_destination()
	_held_alternative_route()
	_late_occupied_destination()
	_door_queue()
	_modes()
	_swept_geometry()
	check(checks >= 49, "All movement behavior fixtures executed")
	print("BREACH_MOVEMENT_RELIABILITY_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _open_blocker() -> void:
	var data := fixture()
	data.units.append({"id":"bravo","x":5.0,"z":6.0,"ammo":0})
	var sim := simulation(data)
	check(bool(sim.issue("alpha", "MOVE", {"target":[9,6]}).ok), "Open floor move accepted")
	check(advance(sim, 450), "Stationary teammate detour never overlaps bodies")
	check(finished(sim), "Stopped teammate on open floor is bypassed")
	check(sim.command_failures == 0, "Ordinary teammate traffic causes no command failure")

func _all_factions() -> void:
	for kind: String in ["enemies", "civilians"]:
		var data := fixture()
		data[kind].append({"id":"body","x":5.0,"z":6.0,"ammo":0,"hold_position":true,"role":"target"})
		var sim := simulation(data)
		var actor: Dictionary = sim[kind][0]
		actor["hold_position"] = true
		sim.issue("alpha", "MOVE", {"target":[9,6]})
		check(advance(sim, 450), "Moving unit never crosses " + kind + " body")
		check(finished(sim), "Unit bypasses " + kind + " on open floor")
		check(sim._position(actor).distance_to(Vector2(5,6)) < 0.00001, "Other faction is not involuntarily moved")

func _occupied_target() -> void:
	var data := fixture()
	data.units.append({"id":"bravo","x":7.0,"z":6.0,"ammo":0,"hold_position":true})
	var sim := simulation(data)
	sim.units[1]["hold_position"] = true
	sim.issue("alpha", "MOVE", {"target":[7,6]})
	check(advance(sim, 300), "Occupied destination stays physically separated")
	check(finished(sim), "Occupied destination resolves to adjacent legal position")
	var command: Dictionary = sim.units[0].commands[0]
	check(command.has("resolved_target") and command.has("completion_reason"), "Adjusted destination retains user-visible explanation")
	check(sim._position(sim.units[0]).distance_to(Vector2(7,6)) >= 0.46, "Resolved destination does not intersect the holder")
	check(sim.events.any(func(event: Dictionary) -> bool: return event.type == "DESTINATION_ADJUSTED"), "Destination adjustment has an event")

func _held_actor() -> void:
	var data := fixture()
	data.units.append({"id":"bravo","x":5.0,"z":6.0,"ammo":0,"hold_position":true})
	var sim := simulation(data)
	sim.units[1]["hold_position"] = true
	sim.issue("alpha", "MOVE", {"target":[9,6]})
	check(advance(sim, 450) and finished(sim), "Held teammate is avoided in open floor")
	check(sim._position(sim.units[1]) == Vector2(5,6), "Explicit hold never automatically yields")
	data.walls = [{"x":6,"z":5.4,"w":12,"d":0.2},{"x":6,"z":6.6,"w":12,"d":0.2}]
	sim = simulation(data)
	sim.units[1]["hold_position"] = true
	sim.issue("alpha", "MOVE", {"target":[9,6]})
	check(advance(sim, 720), "Held narrow passage remains body-safe")
	check(sim.command_failures == 0 and not sim.pause_requested, "Long temporary body obstruction does not auto-fail or pause")
	check(sim.units[0].commands[0].state == "WAITING" and "위치 유지" in str(sim.units[0].commands[0].reason), "Held passage explains the waiting reason")

func _opposing_traffic() -> void:
	var data := fixture()
	data.units[0].x = 3
	data.units.append({"id":"bravo","x":8.0,"z":6.0,"ammo":0})
	data.walls = [{"x":3,"z":5.4,"w":6,"d":0.2},{"x":10.5,"z":5.4,"w":3,"d":0.2},{"x":6,"z":6.6,"w":12,"d":0.2}]
	var first := simulation(data)
	var second := simulation(data)
	for sim: RefCounted in [first, second]:
		sim.issue("alpha", "MOVE", {"target":[10,6]})
		sim.issue("bravo", "MOVE", {"target":[2,6]})
		check(advance(sim, 900), "Opposing passage uses a bay without overlap")
		check(finished(sim, 0) and finished(sim, 1), "Opposing narrow traffic clears both routes")
		check(sim.command_failures == 0, "Opposing traffic does not spuriously fail")
	check(JSON.stringify(first.snapshot(true)) == JSON.stringify(second.snapshot(true)), "Traffic recovery is deterministic")

func _door_queue() -> void:
	var data := fixture()
	data.units[0].x = 6
	data.units[0].z = 8.3
	data.units.append({"id":"bravo","x":6.0,"z":9.0,"ammo":0})
	data.doors = [{"id":"d1","x":6.0,"z":6.0,"axis":"x","w":1.6,"d":0.2,"state":"OPEN"}]
	data.walls = [{"x":2.5,"z":6,"w":5,"d":0.2},{"x":9.5,"z":6,"w":5,"d":0.2}]
	var sim := simulation(data)
	sim.issue("alpha", "MOVE", {"target":[6,3]})
	sim.issue("bravo", "MOVE", {"target":[6,2]})
	check(advance(sim, 600), "Queued doorway movement respects body spacing")
	check(finished(sim, 0) and finished(sim, 1), "Both queued actors pass the door")
	check(sim._reservations.is_empty(), "Passage reservations release after completion")

func _lane_traffic() -> void:
	var data := fixture()
	data.walls = [{"x":5,"z":6,"w":0.3,"d":10},{"x":6.4,"z":6,"w":0.3,"d":10}]
	data.units = [{"id":"alpha","x":5.7,"z":3,"ammo":0},{"id":"bravo","x":5.7,"z":9,"ammo":0}]
	var sim := simulation(data)
	sim.issue("alpha","MOVE",{"target":[5.7,9]})
	sim.issue("bravo","MOVE",{"target":[5.7,3]})
	check(advance(sim, 360), "Two-body lane negotiation never overlaps")
	check(finished(sim, 0) and finished(sim, 1), "Opposing narrow traffic without a nearby bay passes when width permits")
	check(sim._position(sim.units[0]).distance_to(Vector2(5.7,9)) < 0.1 and sim._position(sim.units[1]).distance_to(Vector2(5.7,3)) < 0.1, "Moving initial target occupants do not shorten exchanged destinations")

func _wait_recovery() -> void:
	var data := fixture()
	data.walls = [{"x":5,"z":6,"w":0.3,"d":10},{"x":6.15,"z":6,"w":0.3,"d":10}]
	data.units = [{"id":"alpha","x":5.575,"z":8,"ammo":0},{"id":"bravo","x":5.575,"z":5,"ammo":0}]
	var sim := simulation(data)
	sim.issue("alpha","MOVE",{"target":[5.575,3]})
	sim.issue("bravo","WAIT",{"duration":10})
	sim.issue("bravo","MOVE",{"target":[5.575,1]})
	check(advance(sim, 435), "Following a departing teammate never overlaps")
	check(finished(sim) and sim.units[1].commands[1].state == "SUCCEEDED", "Long explicit wait clears and follower resumes promptly")
	check(sim.command_failures == 0, "Following traffic causes no automatic failure")

func _hidden_destination() -> void:
	var data := fixture()
	data.enemies = [{"id":"e1","x":9,"z":6,"ammo":0,"hold_position":true,"target":true}]
	var sim := simulation(data)
	sim.enemies[0]["visible"] = false
	sim.issue("alpha","MOVE",{"target":[9,6]})
	sim._advance_command(sim.units[0], STEP)
	check(not sim.units[0].commands[0].has("resolved_target"), "Hidden remote occupancy does not adjust a public destination")
	check(not sim.events.any(func(event: Dictionary) -> bool: return event.type == "DESTINATION_ADJUSTED"), "Hidden remote body position cannot leak through adjustment events")

func _held_alternative_route() -> void:
	var data := fixture()
	data.walls = [{"x":5,"z":6,"w":0.3,"d":6},{"x":6.15,"z":6,"w":0.3,"d":6}]
	data.units = [{"id":"alpha","x":5.575,"z":8,"ammo":0},{"id":"bravo","x":5.575,"z":6,"ammo":0,"hold_position":true}]
	var sim := simulation(data)
	sim.units[1]["hold_position"] = true
	sim.issue("alpha","MOVE",{"target":[5.575,4]})
	check(advance(sim, 900), "Global recovery route remains body-safe around a held narrow blocker")
	check(finished(sim), "Held narrow blocker triggers a legal alternate corridor route")
	check(sim._position(sim.units[1]) == Vector2(5.575,6), "Alternate route preserves explicit held actor position")

func _late_occupied_destination() -> void:
	var data := fixture()
	data.walls = [{"x":6,"z":6,"w":0.6,"d":3}]
	data.units.append({"id":"bravo","x":10,"z":10,"ammo":0,"hold_position":true})
	var sim := simulation(data)
	sim.units[1]["hold_position"] = true
	sim.issue("alpha","MOVE",{"target":[10,6]})
	advance(sim, 30)
	sim._set_position(sim.units[1], Vector2(10,6))
	check(advance(sim, 450), "A newly occupied final waypoint stays body-safe")
	check(finished(sim) and sim.units[0].commands[0].has("resolved_target"), "Late occupancy recalculates the final approach")
	check(sim._position(sim.units[0]).distance_to(sim._point(sim.units[0].commands[0].resolved_target)) < 0.1, "Multi-waypoint replacement resets cursor and actually reaches the adjusted point")

func _modes() -> void:
	var positions: Dictionary = {}
	for mode: String in ["careful", "normal", "fast"]:
		var sim := simulation(fixture())
		sim.units[0]["movement_mode"] = mode
		sim.issue("alpha", "MOVE", {"target":[10,6]})
		advance(sim, 60)
		positions[mode] = float(sim.units[0].x)
	check(positions.careful < positions.normal and positions.normal < positions.fast, "Movement modes alter actual mobility")
	var sim := simulation(fixture())
	sim.units[0]["hp"] = 40.0
	sim.issue("alpha", "MOVE", {"target":[10,6]})
	advance(sim, 60)
	check(float(sim.units[0].x) < positions.normal, "Injury multiplier affects actual displacement")
	check(absf(float(sim.units[0].velocity_x)) > 0 and sim.units[0].has("body_facing"), "Movement exposes velocity and body direction")

func _swept_geometry() -> void:
	var data := fixture()
	data.civilians = [{"id":"c1","x":5.0,"z":6.0}]
	var sim := simulation(data)
	check(not sim._unit_space_clear(sim.units[0], Vector2(8,6)), "Long candidate segment cannot tunnel through a civilian")
	check(not sim._tactical_actor_space_clear(sim.civilians[0], Vector2(1,6)), "Tactical caller uses the same swept-body geometry")
