extends SceneTree

const Simulation = preload("res://scripts/simulation.gd")
const STEP: float = 1.0 / 30.0
var checks: int = 0
var failures: Array[String] = []

# Only foot-turn metadata remains presentation-only. Body and weapon aiming
# are authoritative simulation state and must stay enabled in the baseline.
class GameplayBaseline extends BreachSimulation:
	func _update_presentation_turn(_entity: Dictionary) -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _fixture() -> Dictionary:
	return {"id": "T01", "revision": 1, "seed": 42, "bounds": [16, 12], "rooms": [], "walls": [], "doors": [], "props": [], "units": [{"id": "alpha", "x": 2.0, "z": 5.0, "facing": 0.0, "weapon": "standard"}], "enemies": [], "civilians": [], "objectives": []}

func _position(entity: Dictionary) -> Vector2:
	return Vector2(float(entity.x), float(entity.z))

func _gameplay_snapshot(sim: BreachSimulation) -> Dictionary:
	var state: Dictionary = sim.snapshot(true)
	for group: String in ["units", "enemies", "civilians"]:
		for entity: Dictionary in state[group]:
			for field: String in ["turn_started_at", "turn_delta"]:
				entity.erase(field)
	return state

func _run() -> void:
	var sim: BreachSimulation = Simulation.new()
	sim.load_mission(_fixture())
	var unit: Dictionary = sim.units[0]
	_check(unit.travel_distance == 0.0 and unit.aim_facing == unit.facing and unit.move_facing == unit.facing, "Mission starts with consistent zero-distance presentation")
	sim.plan_move("alpha", {"target": [8.0, 5.0]}, false)
	for index: int in range(60):
		sim.step(STEP)
	_check(float(unit.travel_distance) > 3.9 and float(unit.travel_distance) < 4.25, "Standard movement accelerates toward 2.16 m/s without an instantaneous start")
	_check(is_equal_approx(float(unit.travel_distance), float(unit.x) - 2.0), "Straight path distance drives stride in world meters")
	_check(absf(float(unit.move_facing)) < 0.001, "Movement orientation follows travel direction")
	var paused: Dictionary = sim.snapshot()
	sim.step(0.0)
	_check(sim.snapshot() == paused, "Paused simulation cannot advance presentation motion")

	sim.load_mission(_fixture())
	sim.issue("alpha", "FACE", {"target": [2.0, 10.0], "persistent": true})
	sim.plan_move("alpha", {"target": [8.0, 5.0]}, true)
	for index: int in range(20):
		sim.step(STEP)
	unit = sim.units[0]
	_check(is_equal_approx(float(unit.aim_facing), PI * 0.5) and absf(float(unit.move_facing)) < 0.001, "FACE lock supports travel independent of aim")

	var combat: Dictionary = _fixture()
	combat.enemies = [{"id": "target", "x": 6.0, "z": 7.0, "hp": 9999.0, "training": true}]
	sim.load_mission(combat)
	sim.plan_move("alpha", {"target": [8.0, 5.0]}, false)
	var stable_aim: bool = true
	var separate_axes: bool = false
	for index: int in range(60):
		sim.step(STEP)
		unit = sim.units[0]
		var target_angle: float = (_position(sim.enemies[0]) - _position(unit)).angle()
		if unit.aim_state == "ready":
			stable_aim = stable_aim and absf(angle_difference(float(unit.aim_facing), target_angle)) < deg_to_rad(6.0)
		separate_axes = separate_axes or absf(angle_difference(float(unit.aim_facing), float(unit.facing))) > 0.1
	_check(stable_aim and sim.shots_fired >= 2, "Aim stays on the observed target through multiple moving-fire cooldowns")
	_check(separate_axes, "Presentation aim does not overwrite authoritative movement/FOV facing")
	var observed: Dictionary = sim.snapshot().units[0]
	_check(observed.has("aim_facing") and observed.has("move_facing") and observed.has("travel_distance"), "Observed state includes replayable motion metadata")
	_check(not observed.has("_aim_target") and not observed.has("_aim_position"), "Private aim tracking never enters observed state")

	combat.walls = [{"x": 8.0, "z": 6.0, "w": 0.4, "d": 12.0}]
	sim.load_mission(combat)
	for index: int in range(30):
		sim.step(STEP)
	var remembered: Vector2 = _position(sim.enemies[0])
	sim.enemies[0].x = 10.0
	sim.enemies[0].z = 9.0
	sim.enemies[0].travel_distance = 900.0
	for index: int in range(5):
		sim.step(STEP)
	unit = sim.units[0]
	_check(unit._aim_position == [remembered.x, remembered.y] and absf(angle_difference(float(unit.aim_facing), (remembered - _position(unit)).angle())) < deg_to_rad(6.0), "Lost contact holds the frozen identified point without tracking hidden movement")
	var hidden: Dictionary = sim.snapshot().enemies[0]
	_check(not bool(hidden.visible) and not hidden.has("travel_distance") and not hidden.has("aim_facing") and not hidden.has("move_facing"), "Hidden contact record cannot leak live motion metadata")
	unit.facing = -PI * 0.5
	for index: int in range(36):
		sim.step(STEP)
	_check(is_equal_approx(float(unit.aim_facing), float(unit.facing)) and unit.aim_state == "idle", "Unobserved combat aim expires and physically turns back after the short hold")

	var baseline: BreachSimulation = GameplayBaseline.new()
	for mission_name: String in ["tutorial", "house"]:
		var mission: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % mission_name))
		sim.load_mission(mission)
		baseline.load_mission(mission)
		var destination: Array = [18.0, 10.3] if mission_name == "tutorial" else [12.0, 15.5]
		sim.plan_move("alpha", {"target": destination}, false)
		baseline.plan_move("alpha", {"target": destination}, false)
		var unchanged: bool = true
		for index: int in range(900):
			sim.step(STEP)
			baseline.step(STEP)
			if _gameplay_snapshot(sim) != _gameplay_snapshot(baseline):
				unchanged = false
				break
		_check(unchanged, mission_name + ": foot-turn metadata leaves 30 seconds of authoritative aim, gameplay and random outcomes unchanged")
	print("BREACH_PRESENTATION_MOTION_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
