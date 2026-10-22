extends SceneTree
const MainScene = preload("res://main.tscn")
const Assets = preload("res://scripts/environment_assets.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	var session: Node = MainScene.instantiate()
	root.add_child(session)
	session.set_process(false)
	await process_frame
	session._action({"action":"start","mission":"T01"})
	var id: String = str(session.sim.units[0].id)
	var actor: Dictionary = session.sim.units[0]
	var origin := Vector2(actor.x, actor.z)
	session._action({"action":"unit_posture","unit_id":id,"settings":{"stance":"crouched","movement_mode":"careful","hold_position":true}})
	check(actor.stance == "crouched" and actor.movement_mode == "careful" and actor.hold_position, "Controller failed to apply actor behavior")
	check(float(actor.weapon_origin[2]) < 1.1, "Paused stance did not update physical muzzle height")
	var plan: Dictionary = session._export_plan()
	check(plan.units[0].stance == "crouched" and plan.units[0].hold_position, "Saved plan discarded actor behavior")
	var unchanged: String = JSON.stringify(session.sim.snapshot(true))
	session._action({"action":"unit_posture","settings":{"stance":"flying","hold_position":false}})
	check(JSON.stringify(session.sim.snapshot(true)) == unchanged, "Invalid mixed settings partially changed the actor")
	var target: Array = [origin.x + 1.0, origin.y]
	check(session.sim.issue(id,"MOVE",{"target":target},true).ok, "Legal held movement order was rejected")
	for tick: int in range(60): session.sim.step(1.0 / 30.0)
	check(Vector2(actor.x,actor.z).distance_to(origin) < 0.001, "Hold moved actor while the queue was retained")
	session._action({"action":"unit_posture","settings":{"hold_position":false}})
	for tick: int in range(150): session.sim.step(1.0 / 30.0)
	check(Vector2(actor.x,actor.z).distance_to(Vector2(target[0],target[1])) < 0.15, "Released actor did not resume queued movement")
	session._import_plan(plan)
	check(session.sim.time == 0.0 and session.sim.units[0].stance == "crouched" and session.sim.units[0].hold_position, "Plan import did not restore a fresh actor posture")
	var bad: Dictionary = plan.duplicate(true)
	bad.units[0].movement_mode = "teleport"
	unchanged = JSON.stringify(session.sim.snapshot(true))
	session._import_plan(bad)
	check(JSON.stringify(session.sim.snapshot(true)) == unchanged, "Invalid plan damaged the active mission")
	for map_id: String in ["M07","M08","M09"]:
		session._action({"action":"start","mission":map_id})
		check(session.mission_id == map_id and session.mode == "PLANNING", map_id + " controller did not load")
		check(session.world._door_nodes.size() == session.sim.doors.size(), map_id + " missing visible door geometry")
		check(session.sim.units.size() == 4, map_id + " squad missing")
		for tick: int in range(30): session.sim.step(1.0 / 30.0)
		session.world.display(session.sim.snapshot(), str(session.sim.units[0].id), false, 1.0 / 30.0)
		check(session.world._entity_nodes.size() >= 4, map_id + " failed actor rendering")
	var parent := Node3D.new()
	root.add_child(parent)
	check(Assets.create_prop(parent, {"type":"cabinet","x":2.0,"z":3.0,"w":1.0,"d":0.6,"height":2.0,"base_height":0.3}), "Authored height model failed")
	check(absf(parent.get_child(0).position.y - 0.5) < 0.0001, "Prop base height diverges from physical height")
	parent.queue_free()
	session.queue_free()
	await process_frame
	print("BREACH_REALISM_INTEGRATION_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for message: String in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
