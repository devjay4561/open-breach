extends SceneTree
const Field = preload("res://scripts/visibility_field.gd")
const Simulation = preload("res://scripts/simulation.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/archive.json"))
	var field = Field.new()
	field.build(data)
	var sim = Simulation.new()
	sim.load_mission(data)
	var unit: Dictionary = sim.units[0]
	unit.x = 17.0
	unit.z = 12.0
	unit.facing = -PI / 2.0
	field.update([unit], sim.doors)
	var near_point := Vector2(17, 11)
	var office_point := Vector2(17, 8)
	check(field.contains(near_point), "Front floor visible")
	check(not field.contains(office_point), "Closed door conceals unvisited office")
	unit.facing = PI / 2.0
	field.update([unit], sim.doors)
	check(not field.contains(near_point), "Looking away removes current sight")
	var other: Dictionary = unit.duplicate(true)
	other.facing = -PI / 2.0
	field.update([unit, other], sim.doors)
	check(field.contains(near_point), "Squad combines both observers")
	other.hp = 0
	field.update([unit, other], sim.doors)
	check(not field.contains(near_point), "Incapacitated observer contributes no vision")
	unit.facing = -PI / 2.0
	sim.doors[1].state = "OPEN"
	sim.doors[1].progress = 1.0
	field.update([unit], sim.doors)
	check(field.contains(office_point), "Opening door reveals office")
	# Compare continuous geometry with the authoritative line test across rooms
	# and multiple leaf angles. Sample sub-cell coordinates, not raster centers.
	for progress: float in [0.0, 0.35, 0.65, 1.0]:
		sim.doors[1].state = "OPEN" if progress == 1.0 else "OPENING"
		sim.doors[1].progress = progress
		field.update([unit], sim.doors)
		for y in range(27, 67, 3):
			for x in range(55, 82, 3):
				var point := Vector2(x * 0.23 + 0.037, y * 0.21 + 0.019)
				check(field.contains(point) == sim.can_see(unit, {"x": point.x, "z": point.y}), "Polygon matches LOS at %s, leaf %.2f" % [point, progress])
	# An unobstructed FOV side must stay one continuous straight edge. Test
	# points only one centimetre apart on opposite sides at arbitrary distances.
	var empty: Dictionary = {"bounds": [24, 20], "walls": [], "props": []}
	field.build(empty)
	unit.x = 12.0
	unit.z = 10.0
	unit.facing = -0.73
	field.update([unit], [])
	var side_angle: float = float(unit.facing) + deg_to_rad(float(unit.fov)) * 0.5
	for distance: float in [1.173, 2.719, 5.137, 8.213]:
		var edge := Vector2(12, 10) + Vector2.from_angle(side_angle) * distance
		var normal := Vector2.from_angle(side_angle + PI / 2.0) * 0.005
		check(field.contains(edge - normal) and not field.contains(edge + normal), "Sub-cell straight edge at %.3f" % distance)
	field.build(data)
	check(field.polygons.is_empty(), "New mission clears exploration")
	sim.load_mission(data)
	check(sim.snapshot(false).doors[1].get("observed", true) == false, "Unseen door has no live observation")
	sim.doors[1].state = "OPEN"
	sim.doors[1].progress = 1.0
	check(sim.snapshot(false).doors[1].state == "CLOSED", "Hidden door change does not leak")
	check(sim.snapshot(true).doors[1].state == "OPEN", "Full replay capture retains actual state")
	for u: Dictionary in sim.units:
		u.hp = 0
	sim.civilians[0]["last_seen"] = [19, 4.5]
	sim.civilians[0].visible = false
	check(sim.snapshot(false).civilians.is_empty(), "Out of sight civilian does not leak latest state")
	print("BREACH_VISIBILITY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
