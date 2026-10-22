extends SceneTree
## Physical-scale contract: complete large grounds, close inspection, uniform
## scenery/furniture transforms and preservation of the original PBR surfaces.
const World = preload("res://scripts/world_view.gd")
const Historical = preload("res://scripts/historical_assets.gd")
const Furniture = preload("res://scripts/environment_assets.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _fixture() -> Dictionary:
	return {"id": "H_RENDER", "schema_version": 2, "seed": 1, "bounds": [240, 100], "focus": [120, 50], "environment": {"biome": "sea", "water": true, "water_level": -3.45}, "walkable_areas": [{"x": 120, "z": 50, "w": 145.5, "d": 23.7}], "rooms": [], "walls": [], "doors": [], "props": [], "scenery": [], "interactive_targets": [{"id": "target", "x": 80, "z": 50, "w": 2, "d": 2, "label": "TEST", "action": "recover", "duration": 4}], "units": [{"id": "alpha", "x": 60, "z": 50, "facing": 0}], "enemies": [], "civilians": []}

func _run() -> void:
	root.size = Vector2i(1600, 900)
	var world := World.new()
	root.add_child(world)
	world.build(_fixture())
	_check(world._frame_rect.encloses(Rect2(0, 0, 240, 100)), "Home frames the entire 240m battlefield")
	_check(world.camera.far > 700.0, "The far plane cannot clip the aft end of a full-size ship")
	_check(world._chrome_nodes.size() == 2, "Large maps render an actual metre ruler")
	var world_nodes := world._world.get_child_count()
	world._build_wall({"x": 90, "z": 50, "w": 3, "d": 2, "height": 1.2, "render": false})
	_check(world._world.get_child_count() == world_nodes, "Invisible collision proxies never add duplicate visible geometry")
	world._build_room({"x": 90, "z": 50, "w": 0.5, "d": 0.5})
	_check(world._world.get_child_count() == world_nodes + 2, "A room smaller than one seam tile gets its floor and label without an empty mesh surface")
	var sea: Node3D = world._world.get_node("Sea")
	_check(is_equal_approx(sea.position.y + sea.scale.y * 0.5, -3.45), "The published hull/freeboard reconstruction keeps water below the deck")
	world._sync_interactive_targets([{"id": "target", "action": "recover", "label": "TEST", "duration": 4, "progress": 2}])
	_check(is_equal_approx(world._interactive_target_nodes.target.progress.scale.x, 0.5), "A target's elapsed seconds produce the correct progress fraction")
	_check("50%" in world._interactive_target_nodes.target.label.text, "Target progress is readable in the world")
	world._build_interactive_target({"id": "future", "x": 90, "z": 50, "w": 2, "d": 2, "action": "inspect", "duration": 4})
	world._sync_interactive_targets([{"id": "target"}, {"id": "future"}])
	_check(world._interactive_target_nodes.target.label.text.begins_with("01 ·") and world._interactive_target_nodes.future.label.text.begins_with("02 ·"), "Objective order is visible before visiting a target")
	_check(world._interactive_target_nodes.target.label.modulate == Color("f0c75e") and world._interactive_target_nodes.future.label.modulate == Color("848e8b"), "The next objective is yellow and future objectives are grey")
	world._sync_interactive_targets([{"id": "target", "completed": true}, {"id": "future"}])
	_check(is_equal_approx(world._interactive_target_nodes.target.progress.scale.x, 1.0), "Completed targets have a full progress bar")
	_check(world._interactive_target_nodes.target.label.modulate == Color("a1d6c3") and world._interactive_target_nodes.future.label.modulate == Color("f0c75e"), "Completion turns green and advances the yellow current objective")
	var overview_size := world.camera.size
	for step in range(32):
		world.zoom(-1.0)
	_check(world.camera.size < overview_size * 0.1, "A large map supports close inspection without enlarging the actors")
	world.reset_camera()
	_check(is_equal_approx(world.camera.size, overview_size), "Home restores the whole field")
	var environment := Node3D.new()
	root.add_child(environment)
	_check(Furniture.create_prop(environment, {"type": "chair", "x": 0, "z": 0, "w": 2.0, "d": 1.0, "height": 0.92}, true), "Metre furniture is available")
	var chair: Node3D = environment.get_child(0).get_child(0)
	_check(is_equal_approx(chair.scale.x, chair.scale.y) and is_equal_approx(chair.scale.y, chair.scale.z), "Furniture never stretches to an inconsistent mission footprint")
	for mesh: MeshInstance3D in chair.find_children("*", "MeshInstance3D", true, false):
		for surface in range(mesh.mesh.get_surface_count()):
			_check(mesh.get_surface_override_material(surface) == null, "Historical furniture preserves the supplied material")
	_check(not Historical.create_scenery(environment, {"asset": "../../characters/combat-swat", "x": 0, "z": 0}), "Missions cannot load arbitrary model paths")
	var registry := Historical.registry()
	_check(not registry.is_empty(), "Historical registry is shipped")
	for asset_id: String in registry:
		var entry: Dictionary = registry[asset_id]
		_check(entry.get("dimensions_m", []).size() == 3, "%s has metre dimensions" % asset_id)
		var previous := environment.get_child_count()
		var loaded := Historical.create_scenery(environment, {"asset": asset_id, "id": asset_id, "x": 0, "z": 0, "scale": 1.0})
		_check(loaded, "%s has an imported, renderable GLB" % asset_id)
		if not loaded:
			continue
		var placement: Node3D = environment.get_child(previous)
		_check(placement.scale.is_equal_approx(Vector3.ONE), "%s remains authored 1:1 metre scale" % asset_id)
		for mesh: MeshInstance3D in placement.find_children("*", "MeshInstance3D", true, false):
			for surface in range(mesh.mesh.get_surface_count()):
				_check(mesh.get_surface_override_material(surface) == null, "%s original PBR surface retained" % asset_id)
			if str(mesh.name).begins_with("Roof") or str(mesh.name).begins_with("UpperShell") or str(mesh.name).begins_with("CabinSeats"):
				_check(not mesh.visible, "%s cutaway keeps the ground interior visible" % asset_id)
		placement.free()
		if not entry.get("cutaway_hide_meshes", []).is_empty():
			previous = environment.get_child_count()
			Historical.create_scenery(environment, {"asset": asset_id, "id": asset_id + "_background", "cutaway": false})
			placement = environment.get_child(previous)
			for mesh: MeshInstance3D in placement.find_children("*", "MeshInstance3D", true, false):
				_check(mesh.visible, "%s background retains its full silhouette" % asset_id)
			placement.free()
	world.free()
	environment.free()
	for failure in failures:
		push_error(failure)
	print("BREACH_HISTORICAL_RENDER_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)
