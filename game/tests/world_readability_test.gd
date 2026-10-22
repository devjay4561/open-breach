extends SceneTree
const World = preload("res://scripts/world_view.gd")
const Simulation = preload("res://scripts/simulation.gd")
const Door = preload("res://scripts/door_geometry.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _run() -> void:
	var stage := SubViewport.new()
	stage.size = Vector2i(1440, 900)
	root.add_child(stage)
	var world := World.new()
	stage.add_child(world)
	var mission: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json"))
	var sim := Simulation.new()
	sim.load_mission(mission)
	world.build(mission)
	var state := sim.snapshot()
	world.display(state, "alpha", true, 0.1)
	var selected: Dictionary = world._entity_nodes.alpha
	_check(selected.selection.visible and not selected.ring.visible, "Selected actor has one strong ring instead of two concentric rings")
	_check(selected.arrow.visible and selected.label.text == "1", "Selected actor retains clear aim marker and short index")
	_check(not world._entity_nodes.bravo.arrow.visible and not world._entity_nodes.bravo.selection.visible, "Unselected actor does not compete with selected aim marker")
	var weight_tag := TextServerManager.get_primary_interface().name_to_tag("wght")
	_check(float(world._label_font.variation_opentype.get(weight_tag, 0.0)) >= 600.0, "Variable map font uses readable semibold weight")
	for viewport: Vector2i in [Vector2i(1280,720), Vector2i(1440,900), Vector2i(1920,1080)]:
		stage.size = viewport
		await process_frame
		for scale: float in [1.0, 1.5]:
			world.set_settings({"ui_scale": scale})
			world._fit_camera()
			var top := 64.0 if scale >= 1.5 else 56.0
			var bottom := float(viewport.y) - (132.0 if scale >= 1.5 else 116.0)
			for point: Vector3 in [Vector3(3,1.05,3), Vector3(21,1.05,3), Vector3(10.8,0.2,19.15), Vector3(13,0.2,19.15)]:
				var screen := world.camera.unproject_position(point)
				_check(screen.x > 20.0 and screen.x < viewport.x - 20.0 and screen.y > top and screen.y < bottom, "%s at %.1f UI: initial actors and house fit between fixed HUD panels" % [viewport, scale])
	# The visible door model, cone and click region must describe the same leaf.
	var door: Dictionary = {"id":"d1","x":6.0,"z":6.0,"w":1.8,"d":0.24,"axis":"x","state":"CLOSED","progress":0.0,"swing_sign":-1.0}
	var room := {"bounds":[12,12],"focus":[6,6],"walls":[],"rooms":[],"props":[],"units":[],"doors":[door]}
	world.build(room)
	world._state = {"doors":[door]}
	world._rebuild_obstacles()
	_check(world._obstacles.is_empty(), "FOV no longer has a closed-door threshold proxy")
	_check(world._ray_distance(Vector2(6,8), Vector2.UP, 4.0) < 2.0, "Closed leaf blocks the center ray")
	door.state = "OPEN"
	door.progress = 1.0
	world._state = {"doors":[door]}
	world._rebuild_obstacles()
	_check(is_equal_approx(world._ray_distance(Vector2(6,8), Vector2.UP, 4.0), 4.0), "Open doorway center passes the ray")
	var side_hit := world._ray_distance(Vector2(3,6.9), Vector2.RIGHT, 6.0)
	_check(side_hit > 1.9 and side_hit < 2.2, "Swung-out open leaf still occludes from the side")
	for progress: float in [0.0, 0.4, 0.8, 1.0]:
		door.progress = progress
		door.state = "OPEN" if progress >= 1.0 else "OPENING"
		world.display({"doors":[door],"units":[],"enemies":[],"civilians":[],"events":[],"tick":1,"time":0.0}, "", true, 0.1)
		var actual: Transform3D = world._door_nodes.d1.hinge.global_transform
		var expected := Door.hinge_transform(door, progress)
		_check(actual.is_equal_approx(expected), "Door model follows shared hinge at %.1f progress" % progress)
		var screen := world.camera.unproject_position(expected * Vector3(Door.width(door) * 0.95, 0.68, 0))
		_check(world.pick_door(screen) == "d1", "Visible door edge can be clicked at %.1f progress" % progress)
	world.queue_free()
	print("BREACH_WORLD_READABILITY_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
