extends SceneTree
const Navigation = preload("res://scripts/navigation.gd")
const Door = preload("res://scripts/door_geometry.gd")
const Simulation = preload("res://scripts/simulation.gd")
const World = preload("res://scripts/world_view.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func run() -> void:
	for axis: String in ["x","z"]:
		for sign_value: float in [-1.0,1.0]:
			var door := {"id":"door","axis":axis,"x":6.0,"z":6.0,"w":1.8 if axis == "x" else 0.24,"d":0.24 if axis == "x" else 1.8,"state":"OPEN","progress":1.0,"swing_sign":sign_value}
			var nav = Navigation.new()
			nav.build({"bounds":[12,12],"walls":[],"props":[]},[door])
			var obstacle := Door.movement_obstacle(door)
			var center := Vector2(obstacle.x,obstacle.z)
			var normal := Vector2.UP.rotated(float(obstacle.leaf_angle))
			var a := center + normal * 0.8
			var b := center - normal * 0.8
			check(not nav.walkable(center), "Open leaf blocks destination "+axis)
			check(not nav.walkable(center,["door"]), "Assumed-open cannot remove an actual open leaf")
			check(not nav.segment_clear(a,b,nav.RADIUS), "Body segment cannot cross open leaf")
			check(nav.walkable(Vector2(door.x,door.z)), "Clear doorway remains passable")
			var path: Array = nav.path(a,b)
			check(path.size() >= 2, "Path detours around open leaf")
			var previous := a
			for waypoint: Array in path:
				var point := Vector2(waypoint[0],waypoint[1])
				check(nav.segment_clear(previous,point,nav.RADIUS), "Every smoothed segment respects rotated leaf")
				previous = point
			check(previous.distance_to(b) < 0.001, "Detour reaches intended destination")
			# Compare the renderer's imported mesh placement with collision space.
			var world = World.new()
			root.add_child(world)
			world.build({"id":"COLLISION","bounds":[12,12],"focus":[6,6],"rooms":[],"walls":[],"doors":[door],"props":[],"units":[],"enemies":[],"civilians":[]})
			for progress: float in [0.0,0.3,0.6,1.0]:
				door.progress = progress
				door.state = "OPEN" if progress >= 1 else "OPENING"
				world.display({"time":progress,"units":[],"enemies":[],"civilians":[],"doors":[door],"events":[]},"",false,0.0)
				var leaf: Node3D = world._door_nodes.door.hinge.get_child(0)
				var physical := Door.movement_obstacle(door)
				var rendered := leaf.global_transform * Vector3(0.5,0,0)
				check(Vector2(rendered.x,rendered.z).distance_to(Vector2(physical.x,physical.z)) < 0.00001, "Rendered and collision leaf centers agree")
				var endpoint := leaf.global_transform * Vector3(1,0,0)
				var expected := Door.hinge_transform(door,progress) * Vector3(Door.width(door),0,0)
				check(endpoint.distance_to(expected) < 0.00001, "Rendered and collision hinge rotation agree")
			world.queue_free()
	# A person in the swing area must stop the leaf; clearing it resumes opening.
	var sim = Simulation.new()
	sim.load_mission(JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json")))
	var door: Dictionary = sim.doors[0]
	# Opening is now owned by a living, adjacent operator; create that state
	# through the public command API before checking the swept-leaf guard.
	var handle := Door.handle_floor(door)
	sim.units[0].x = handle.x
	sim.units[0].z = handle.y + Door.APPROACH_DISTANCE
	sim.issue("alpha", "OPEN_DOOR", {"door_id": door.id})
	sim.step(1.0 / 30.0)
	var future := Door.movement_obstacle(door,0.65)
	sim.units[1].x = future.x
	sim.units[1].z = future.z
	sim.units[1]["hold_position"] = true
	for frame in range(30): sim._advance_doors(0.1)
	check(door.state == "OPENING" and door.progress < 0.65, "Door stops before a person in its swept area")
	check(not Door.overlaps_actor(door,door.progress,Vector2(future.x,future.z),Navigation.RADIUS), "Stopped leaf does not overlap the person")
	sim.units[1].x = 2.0
	sim.units[1].z = 19.0
	for frame in range(30): sim._advance_doors(0.1)
	check(door.state == "OPEN", "Opening resumes after swing area clears")
	# Exercise the real automatic two-door command chain, checking every step.
	sim.load_mission(JSON.parse_string(FileAccess.get_file_as_string("res://data/tutorial.json")))
	# Keep combat victory from stopping the route before its final waypoint.
	for unit: Dictionary in sim.units:
		unit.ammo = 0
		unit.reserve_ammo = 0
	check(sim.plan_move("alpha",{"target":[18.0,10.3]},false).ok, "Automatic two-door plan accepted")
	var collision := false
	for frame in range(900):
		var previous := Vector2(sim.units[0].x,sim.units[0].z)
		sim.step(1.0/30.0)
		var current := Vector2(sim.units[0].x,sim.units[0].z)
		if previous.distance_to(current)>0.00001 and not sim.nav.segment_clear(previous,current,Navigation.RADIUS): collision = true
		if sim.units[0].commands.back().state in ["SUCCEEDED","FAILED"]: break
	check(not collision, "Executed route never crosses a leaf")
	check(sim.units[0].commands.back().state == "SUCCEEDED", "Automatic two-door route still completes")
	await process_frame
	await process_frame
	print("BREACH_DOOR_COLLISION_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
