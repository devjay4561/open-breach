extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Acoustic = preload("res://scripts/acoustic_model.gd")
const Navigation = preload("res://scripts/navigation.gd")
class PartialSimulation extends Simulation:
	var fraction: float = 0.2
	func visual_exposure(_observer: Dictionary, _subject: Dictionary) -> float:
		return fraction
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func fixture() -> Dictionary:
	return {"id": "SENSE", "seed": 42, "bounds": [20, 16], "rooms": [], "walls": [], "props": [], "doors": [], "units": [{"id": "alpha", "x": 4.0, "z": 6.0, "facing": 0.0, "ammo": 0, "reserve_ammo": 0}], "enemies": [{"id": "guard", "x": 8.0, "z": 6.0, "facing": PI, "ammo": 0, "reserve_ammo": 0}], "civilians": [], "win": [{"type": "reach_zone", "zone": [18, 14, 1, 1]}], "fail": []}
func make(data: Dictionary) -> BreachSimulation:
	var sim := Simulation.new()
	sim.load_mission(data)
	return sim
func advance(sim: BreachSimulation, seconds: float) -> void:
	for i: int in range(roundi(seconds * 30.0)): sim.step(1.0 / 30.0)
func run() -> void:
	var data: Dictionary = fixture()
	var partial := PartialSimulation.new()
	partial.load_mission(data)
	check(partial.units[0].awareness_state == "IDENTIFIED" and partial.observation_ready(partial.units[0], partial.enemies[0]), "Operators identify even brief partial exposure immediately")
	check(partial.enemies[0].awareness_state == "DETECTED" and not partial.observation_ready(partial.enemies[0], partial.units[0]), "Enemy identification retains its observation and reaction delay")
	advance(partial, 0.5)
	check(partial.enemies[0].awareness_state == "DETECTED", "Enemy partial exposure needs sustained observation")
	advance(partial, 0.7)
	check(partial.enemies[0].awareness_state == "IDENTIFIED" and partial.observation_ready(partial.enemies[0], partial.units[0]), "Enemy sustained partial exposure identifies after accumulation and reaction")
	var remembered: Array = partial.units[0]._sensory_memory.guard.position.duplicate()
	var previous_confidence: float = float(partial.units[0].awareness_confidence)
	partial.fraction = 0.0
	partial.enemies[0].x = 14.0
	advance(partial, 1.0)
	check(partial.units[0].awareness_state == "TRACKING" and float(partial.units[0].awareness_confidence) < previous_confidence, "Lost sight decays confidence into tracking")
	check(partial.units[0]._sensory_memory.guard.position == remembered and not partial.observation_ready(partial.units[0], partial.enemies[0]), "Tracking retains the observed point without following hidden live motion or permitting fire")
	advance(partial, 20.0)
	check(partial.units[0]._sensory_memory.is_empty(), "Unconfirmed visual memories are bounded and eventually expire")
	data = fixture()
	data.units.append({"id": "bravo", "x": 5.0, "z": 7.0, "facing": 0.0, "ammo": 0, "reserve_ammo": 0})
	var first := make(data)
	data.units.reverse()
	var reverse := make(data)
	check(first.enemies[0]._target == reverse.enemies[0]._target, "Target selection is invariant to actor array ordering")
	advance(first, 0.5)
	check(first.enemies[0]._target == "bravo", "Distance and retained observation determine target choice")
	data = fixture()
	data.units[0].facing = PI
	data.enemies[0].facing = 0.0
	var sound := make(data)
	sound._emit_sound(Vector2(7, 6), 4.0, "발소리 감지", "unit")
	check(sound.enemies[0].observation_source == "sound" and sound.enemies[0]._observed.is_empty() and sound.enemies[0]._target == "", "Hearing creates uncertainty without a target identity")
	sound._receive_combat_alert(sound.enemies[0], Vector2(6, 6), 2)
	check(sound.enemies[0].observation_source == "report" and sound.enemies[0]._observed.is_empty(), "Reported information stays separate from direct sight")
	check(not sound.enemies[0]._heard_memory.is_empty() and not sound.enemies[0]._report_memory.is_empty() and not sound.enemies[0]._heard_memory.has("id") and not sound.enemies[0]._report_memory.has("id"), "Heard and reported snapshots retain separate uncertain regions without hidden target IDs")
	var before: float = float(sound.enemies[0]._alert_until)
	advance(sound, 1.0)
	sound._receive_combat_alert(sound.enemies[0], Vector2(6, 6), 2)
	check(float(sound.enemies[0]._alert_until) > before and int(sound.enemies[0]._alert_repetitions) > 0, "Repeated alerts prolong memory instead of rigid expiry")
	sound.units[0].travel_distance = 0.7
	sound.units[0].x = 6.5
	sound.enemies[0]._observed = []
	sound._update_footstep_stimuli(1.0 / 30.0)
	check(sound.enemies[0]._detect_reason == "sound" and sound.enemies[0].observation_source == "sound", "Authoritative movement emits footsteps that affect enemy hearing")
	data = fixture()
	data.rooms = [{"id": "left", "x": 5, "z": 8, "w": 10, "d": 16}, {"id": "right", "x": 15, "z": 8, "w": 10, "d": 16}]
	data.walls = [{"x": 10, "z": 3, "w": 0.3, "d": 6}, {"x": 10, "z": 11, "w": 0.3, "d": 10}]
	data.doors = [{"id": "door", "x": 10, "z": 6.5, "w": 0.24, "d": 1.0, "axis": "z", "state": "CLOSED", "progress": 0.0}]
	var navigation := Navigation.new()
	navigation.build(data, data.doors)
	var acoustic := Acoustic.new()
	acoustic.build(data, data.doors, navigation)
	var closed: float = acoustic.audibility(Vector2(8, 6.5), Vector2(12, 6.5), 12.0)
	data.doors[0].state = "OPEN"; data.doors[0].progress = 1.0
	var opened: float = acoustic.audibility(Vector2(8, 6.5), Vector2(12, 6.5), 12.0)
	check(opened > closed and closed > 0.0, "Closed doors attenuate sound and open portals restore the room route")
	# A bent route can carry sound even when source and listener share no sightline.
	data.rooms = [{"id": "left", "x": 5, "z": 5, "w": 10, "d": 10}, {"id": "hall", "x": 10, "z": 13, "w": 20, "d": 6}, {"id": "right", "x": 15, "z": 5, "w": 10, "d": 10}]
	data.walls = [{"x": 10, "z": 5, "w": 0.3, "d": 10}, {"x": 2, "z": 10, "w": 4, "d": 0.3}, {"x": 10, "z": 10, "w": 8, "d": 0.3}, {"x": 18, "z": 10, "w": 4, "d": 0.3}]
	data.doors = [{"id": "leftdoor", "x": 5, "z": 10, "w": 2, "d": 0.24, "axis": "x", "state": "OPEN", "progress": 1.0}, {"id": "rightdoor", "x": 15, "z": 10, "w": 2, "d": 0.24, "axis": "x", "state": "OPEN", "progress": 1.0}]
	navigation.build(data, data.doors); acoustic.build(data, data.doors, navigation)
	var indirect_open: float = acoustic.audibility(Vector2(5, 8), Vector2(15, 8), 18.0)
	data.doors[0].state = "CLOSED"; data.doors[0].progress = 0.0
	data.doors[1].state = "CLOSED"; data.doors[1].progress = 0.0
	check(indirect_open > 0.0 and acoustic.audibility(Vector2(5, 8), Vector2(15, 8), 18.0) == 0.0, "Sound follows two open portals around a wall and is attenuated when both portals close")
	# Compare observable audibility around the range boundary with the exact
	# propagation calculation, including blocked and indirect portal routes.
	for strength: float in [0.01, 3.1, 12.0, 18.0]:
		for ratio: float in [0.99999, 1.0, 1.000001, 1.01]:
			var source := Vector2(5, 8)
			var listener: Vector2 = source + Vector2(strength * ratio, 0.0)
			var reference: float = clampf(1.0 - acoustic.travel_cost(source, listener) / strength, 0.0, 1.0)
			var actual: float = acoustic.audibility(source, listener, strength)
			check(is_equal_approx(actual, reference) and (actual > 0.0) == (reference > 0.0), "Distance prefilter preserves exact audibility at strength %s, ratio %s" % [strength, ratio])
	data = fixture()
	data.units[0].facing = PI; data.enemies[0].facing = 0.0
	data.units[0].x = 6.0
	data.rooms = [{"id": "carpet", "x": 10, "z": 8, "w": 20, "d": 16, "floor_surface": "carpet"}]
	var quiet := make(data)
	quiet.units[0].travel_distance = 0.7; quiet._update_footstep_stimuli(1.0 / 30.0)
	check(quiet.enemies[0].observation_source == "none", "Carpet reduces authoritative footstep propagation")
	data.rooms[0].floor_surface = "tile"
	var tile := make(data)
	tile.units[0].travel_distance = 0.7; tile._update_footstep_stimuli(1.0 / 30.0)
	check(tile.enemies[0].observation_source == "sound", "The same movement on tile produces a detectable contact")
	data.enemies[0].x = 8.3
	data.units[0].movement_mode = "careful"
	var careful := make(data)
	careful.units[0].travel_distance = 0.7; careful._update_footstep_stimuli(1.0 / 30.0)
	check(careful.enemies[0].observation_source == "none", "Careful movement reduces gameplay footstep strength")
	data = fixture()
	data.units[0].x = 2; data.units[0].z = 2; data.units[0].facing = PI
	data.enemies = [{"id": "guard", "x": 12, "z": 12, "facing": 0, "ammo": 0, "reserve_ammo": 0}, {"id": "other", "x": 12, "z": 13, "facing": 0, "ammo": 0, "reserve_ammo": 0}]
	data.props = [{"id": "crate", "type": "crate", "cover": "low", "x": 12, "z": 10, "w": 1.4, "d": 1.4, "height": 0.95}]
	var cover := make(data)
	cover._take_enemy_cover(cover.enemies[0], Vector2(6, 10))
	var selected: Array = cover.enemies[0]._cover_target.duplicate()
	check(selected.size() == 2 and cover.enemies[0].stance == "crouched", "Low cover is selected using body exposure and a useful crouched posture")
	cover.time = 3.0; cover._take_enemy_cover(cover.enemies[0], Vector2(6.1, 10))
	check(cover.enemies[0]._cover_target == selected, "Small threat motion does not oscillate a useful cover decision")
	cover._take_enemy_cover(cover.enemies[1], Vector2(6, 10))
	var other_cover: Array = cover.enemies[1]._cover_target
	check(other_cover.is_empty() or Vector2(float(other_cover[0]), float(other_cover[1])).distance_to(Vector2(float(selected[0]), float(selected[1]))) >= 0.8, "Cover reservations prevent two enemies selecting the same position")
	data = fixture()
	data.units[0].facing = PI; data.enemies[0].facing = 0.0
	data.civilians = [{"id": "civilian", "x": 6.0, "z": 9.0}]
	var civilian := make(data)
	civilian._emit_sound(Vector2(5, 9), 10.0, "총성 감지", "unit")
	var start := Vector2(float(civilian.civilians[0].x), float(civilian.civilians[0].z))
	advance(civilian, 0.1)
	check(Vector2(float(civilian.civilians[0].x), float(civilian.civilians[0].z)).distance_to(start) < 0.01 and civilian.civilians[0].status == "PANIC", "A civilian briefly pauses before moving after a frightening event")
	advance(civilian, 1.0)
	check(Vector2(float(civilian.civilians[0].x), float(civilian.civilians[0].z)).distance_to(start) > 0.1, "A frightened civilian moves toward a reachable refuge")
	advance(civilian, 6.0)
	check(civilian.civilians[0].status == "IDLE", "Quiet conditions let civilian panic subside")
	civilian.civilians[0].secured = true; civilian.civilians[0].follow_unit_id = "alpha"
	civilian._emit_sound(Vector2(5, 9), 14.0, "총성 감지", "unit")
	advance(civilian, 1.0)
	check(civilian.civilians[0].status == "FOLLOW", "A secured civilian resumes escorting after a short frightened pause")
	# P1 restores automatic surrender; sensory/acoustic assertions above keep
	# their original meaning and the dedicated combat suite checks eligibility.
	check(Simulation.AUTO_SURRENDER_ENABLED, "Automatic surrender is restored")
	print("BREACH_COGNITION_ACOUSTIC_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
