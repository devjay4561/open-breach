extends SceneTree
## Real cabin metre heights, input projection, and operator/civilian visibility.
## Native execution also emits close review images of the mission geometry.
const World = preload("res://scripts/world_view.gd")
const Historical = preload("res://scripts/historical_assets.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	root.size = Vector2i(1600, 900)
	for id in ["H04", "H06", "H07"]:
		var mission: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/historical/" + id + ".json"))
		var room: Dictionary = {}
		for item: Dictionary in mission.rooms:
			if item.id == "passenger_cabin": room = item
		check(not room.is_empty(), id + " has a measured passenger cabin")
		if room.is_empty(): continue
		var floor_base := float(room.base_height)
		var world := World.new()
		root.add_child(world)
		world.build(mission)
		var point := Vector2(float(room.x), float(room.z))
		check(is_equal_approx(world.surface_offset(point), floor_base), id + " elevated cabin wins over the overlapping apron")
		var unit: Dictionary = mission.units[0].duplicate(true)
		unit.id = "floor_review"
		unit.x = point.x
		unit.z = point.y
		unit.hp = 100.0
		unit.base_height = floor_base
		unit.commands = [{"type":"MOVE","state":"PENDING","args":{"target":[point.x + 1.0, point.y]}}]
		var civilians: Array = mission.get("civilians", []).duplicate(true)
		for civilian: Dictionary in civilians:
			civilian.visible = true
			civilian.hp = 100.0
		# This explicit art-review fixture uses authored passenger positions;
		# production gameplay still consumes only its filtered snapshot.
		world.display({"units":[unit],"civilians":civilians,"doors":mission.doors,"time":0.0,"presentation_reveal":true},str(unit.id),true,0.0)
		world.zoom(-24.0)
		world.follow_position(point)
		var actor: Dictionary = world._entity_nodes[unit.id]
		check(is_equal_approx(actor.body.global_position.y, floor_base + 0.2), id + " operator feet are on the actual exported cabin floor")
		check(is_equal_approx(actor.selection.global_position.y, floor_base + 0.23), id + " selection disc is above the cabin floor")
		for civilian: Dictionary in civilians:
			var passenger: Dictionary = world._entity_nodes[civilian.id]
			var expected := world.surface_offset(Vector2(float(civilian.x),float(civilian.z))) + 0.2
			check(is_equal_approx(passenger.body.global_position.y,expected),id + " passenger " + str(civilian.id) + " stands on the same floor")
		var screen := world.camera.unproject_position(world.surface_position(point))
		check(world.screen_to_ground(screen).distance_to(point) < 0.002,id + " raised-floor screen/input projection roundtrips")
		check(world.pick_unit(world.camera.unproject_position(world.surface_position(point,0.95))) == str(unit.id),id + " elevated operator can be selected")
		var waypoint := point + Vector2(1.0,0.0)
		check(not world.pick_waypoint(world.camera.unproject_position(world.surface_position(waypoint,0.25)),str(unit.id)).is_empty(),id + " elevated waypoint can be edited")
		for door: Dictionary in mission.doors:
			if float(door.get("base_height",0.0)) > 0.0:
				var door_screen := world.camera.unproject_position(Vector3(float(door.x),floor_base + 0.7,float(door.z)))
				check(world._door_pick_distance(door_screen,door) < 0.01,id + " elevated cabin door has a matching click anchor")
				break
		var hidden_seats := 0
		for mesh: MeshInstance3D in world._world.find_children("*","MeshInstance3D",true,false):
			if str(mesh.name).begins_with("CabinSeats"):
				hidden_seats += 1
				check(not mesh.visible,id + " embedded four-column seats remain hidden after static batching")
		check(hidden_seats > 0,id + " authoritative mission seats replace embedded display seats")
		# The exploration cache must equal the exact sight query for every grid
		# point, preserve memory after movement, and clear it on replay rewind.
		var previous_masks: Dictionary = {}
		for room_id: String in world._room_sample_points:
			var expected_seen := 0
			var exact := true
			var points: Array = world._room_sample_points[room_id]
			var mask: Array = world._room_seen_mask[room_id]
			for index in range(points.size()):
				var expected := world._visibility.contains(points[index])
				if bool(mask[index]) != expected: exact = false
				if expected: expected_seen += 1
			previous_masks[room_id] = mask.duplicate()
			check(exact,id + " exploration skips distant rooms without changing any visible sample")
			check(is_equal_approx(world.room_observed_fraction(room_id),float(expected_seen)/float(points.size())),id + " cached explored fraction equals the metre-grid oracle")
		if DisplayServer.get_name() != "headless":
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("../tests/artifacts/historical-" + id + "-cabin-floor.png")
		unit.x = point.x + 2.0
		world.display({"units":[unit],"civilians":civilians,"doors":mission.doors,"time":0.2,"tick":6,"presentation_reveal":true},str(unit.id),true,0.0)
		for room_id: String in world._room_sample_points:
			var exact := true
			var points: Array = world._room_sample_points[room_id]
			var mask: Array = world._room_seen_mask[room_id]
			for index in range(points.size()):
				var expected := bool(previous_masks[room_id][index]) or world._visibility.contains(points[index])
				if bool(mask[index]) != expected: exact = false
			check(exact,id + " exploration keeps the exact union of past and current sight")
		world.display({"units":[unit],"civilians":civilians,"doors":mission.doors,"time":0.0,"tick":0,"presentation_reveal":true},str(unit.id),true,0.0)
		for room_id: String in world._room_sample_points:
			var expected_seen := 0
			var exact := true
			var points: Array = world._room_sample_points[room_id]
			var mask: Array = world._room_seen_mask[room_id]
			for index in range(points.size()):
				var expected := world._visibility.contains(points[index])
				if bool(mask[index]) != expected: exact = false
				if expected: expected_seen += 1
			check(exact and is_equal_approx(world.room_observed_fraction(room_id),float(expected_seen)/float(points.size())),id + " replay rewind resets both remembered sight and its fraction cache")
		world.free()
		await process_frame
	print("BREACH_HISTORICAL_SURFACE_RENDER_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
