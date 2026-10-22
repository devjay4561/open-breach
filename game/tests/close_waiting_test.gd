extends "res://tests/door_traffic_test.gd"

func run() -> void:
	for axis: String in ["x", "z"]:
		for drill: bool in [false, true]: _close_wait(axis, drill)
	print("BREACH_CLOSE_WAITING_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _close_wait(axis: String, drill: bool) -> void:
	var data := fixture(axis)
	data.units = data.units.slice(0, 2)
	data.rooms = [{"id":"room","x":3 if axis == "z" else 6,"z":3 if axis == "x" else 6,"w":4,"d":4}]
	var normal := Vector2.DOWN if axis == "x" else Vector2.RIGHT
	var center := Vector2(6,6)
	var sim := simulation(data)
	for index: int in range(2):
		sim._set_position(sim.units[index], center + normal * (0.9 if index == 0 else 3.5))
		var target := center - normal * (2.5 if index == 0 else 1.5)
		sim.issue(str(sim.units[index].id), "MOVE", {"target":[target.x,target.y]})
		if drill:
			sim.units[index].commands.back().args["drill"] = {"stage":"entry","door_id":"d1","room_id":"room","sync_id":"test","order":index}
	sim.units[0].hold_position = true
	var safe := true
	for frame: int in range(150):
		sim.step(STEP)
		safe = safe and sim._position(sim.units[0]).distance_to(sim._position(sim.units[1])) >= Navigation.RADIUS*2.0-0.00001
		safe = safe and (sim._position(sim.units[1])-center).dot(normal) > 0.0
	var gap: float = sim._position(sim.units[0]).distance_to(sim._position(sim.units[1]))
	var label := "%s drill=%s" % [axis,drill]
	print(label, " gap=",gap," follower=",sim._position(sim.units[1])," reason=",sim.units[1].commands.back().get("reason","")," queue=",sim.units[1].get("_movement_queue_point",[])," door=",sim.doors[0].state)
	check(gap < 0.75 and gap >= sim._movement_body_spacing()-0.001, label + " closes to body-safe waiting gap: " + str(gap))
	check(safe, label + " stays outside the portal without body overlap")
	sim.units[0].hold_position = false
	for frame: int in range(300):
		sim.step(STEP)
		if sim.units[1].commands.back().state == "SUCCEEDED": break
	print("released ",label," front=",sim._position(sim.units[0])," follower=",sim._position(sim.units[1])," state=",sim.units[1].commands.back().state," reason=",sim.units[1].commands.back().get("reason",""))
	check(sim.units[1].commands.back().state == "SUCCEEDED", label + " follows as soon as space opens")
