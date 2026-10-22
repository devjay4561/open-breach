extends SceneTree
const MovementAudio = preload("res://scripts/movement_audio.gd")
const Gait = preload("res://scripts/locomotion_profile.gd")
var first_contact: float = Gait.STRIDES.RifleRun * Gait.CONTACT_PHASES.RifleRun[0]
var second_contact: float = Gait.STRIDES.RifleRun * Gait.CONTACT_PHASES.RifleRun[1]
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _state(time: float, distance: float, x: float = -1.0) -> Dictionary:
	return {"presentation_time": time, "presentation_mode": "EXECUTING", "units": [{"id": "alpha", "kind": "unit", "x": 2.0 + distance if x < 0.0 else x, "z": 3.0, "hp": 100.0, "travel_distance": distance}], "enemies": [], "civilians": [], "doors": [{"id": "d1", "x": 5.0, "z": 4.0, "progress": 0.0}]}

func _run() -> void:
	_test_distance_contacts()
	_test_pause_seek_and_observation()
	_test_door_contacts()
	_test_authored_gait_contacts()
	print("BREACH_MOVEMENT_AUDIO_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_distance_contacts() -> void:
	var audio = MovementAudio.new()
	audio.configure({"id": "M01", "rooms": [{"x": 5.0, "z": 3.0, "w": 8.0, "d": 4.0}]})
	_check(audio.collect(_state(0.0, 0.0), true).is_empty(), "First observation does not invent a footfall")
	_check(audio.collect(_state(0.1, first_contact * 0.5), true).is_empty(), "Walking less than one contact interval stays silent")
	_check(audio.collect(_state(0.2, first_contact - 0.01), true).is_empty(), "Footstep waits for the actual distance threshold")
	var sounds: Array = audio.collect(_state(0.21, first_contact + 0.01), true)
	_check(sounds.size() == 1 and sounds[0].name == "footstep_wood", "Interior contact selects the prepared wood recordings")
	_check(sounds[0].event.attacker_id == "alpha" and sounds[0].event.seq == 1, "Actor and contact index give deterministic sample variation")
	_check(is_equal_approx(float(sounds[0].point[0]), 2.0 + first_contact + 0.01) and is_equal_approx(float(sounds[0].point[1]), 3.0), "Contact position follows the displayed actor")
	_check(audio.collect(_state(0.21, first_contact + 0.01), true).is_empty(), "Repeated render of the same contact never duplicates it")
	_check(audio.collect(_state(0.35, second_contact - 0.01), true).is_empty(), "Intermediate travel does not create timer-driven extra steps")
	sounds = audio.collect(_state(0.36, second_contact + 0.01), true)
	_check(sounds.size() == 1 and sounds[0].event.seq == 2, "Second contact follows the measured opposite-foot landing")
	audio.configure({"id": "M01", "rooms": []})
	audio.collect(_state(0.0, 0.0), true)
	sounds = audio.collect(_state(0.2, first_contact + 0.01), true)
	_check(sounds.size() == 1 and sounds[0].name == "footstep_concrete", "Exterior floor selects concrete recordings")
	audio.configure({"id": "M01", "rooms": [{"x": 5.0, "z": 3.0, "w": 8.0, "d": 4.0, "floor_surface": "concrete"}]})
	audio.collect(_state(0.0, 0.0), true)
	sounds = audio.collect(_state(0.2, first_contact + 0.01), true)
	_check(sounds.size() == 1 and sounds[0].name == "footstep_concrete", "An explicit room surface overrides the map default")
	audio.reset()
	audio.collect(_state(0.0, 0.0), true)
	sounds = audio.collect(_state(0.3, 2.4), true)
	_check(sounds.size() == 1, "A slow render frame emits at most one contact per actor instead of a backlog burst")

func _test_pause_seek_and_observation() -> void:
	var audio = MovementAudio.new()
	audio.collect(_state(0.0, 0.0), true)
	_check(audio.collect(_state(0.2, first_contact + 0.01), false).is_empty(), "Pausing at a footfall suppresses the sound")
	_check(audio.collect(_state(0.2, first_contact + 0.01), false).is_empty(), "Paused snapshots remain silent")
	_check(audio.collect(_state(0.23, second_contact - 0.01), true).is_empty(), "Resume does not replay the paused footfall")
	_check(audio.collect(_state(0.33, second_contact + 0.01), true).size() == 1, "Resume permits the next newly traveled footfall")
	_check(audio.collect(_state(0.0, 0.0), true).is_empty(), "Rewind never produces past contacts")
	_check(audio.collect(_state(0.1, 0.94), true, true).is_empty(), "Small explicit forward seek also suppresses contacts")
	_check(audio.collect(_state(8.0, 15.0), true).is_empty(), "Large seek or frame discontinuity refreshes baseline without a burst")
	_check(audio.collect(_state(8.1, 15.1, 20.0), true).is_empty(), "Teleporting actors do not make traversal sounds")
	var dead: Dictionary = _state(8.2, 15.8)
	dead.units[0].hp = 0.0
	_check(audio.collect(dead, true).is_empty(), "Incapacitated actors cannot emit footsteps")
	audio.reset()
	var state: Dictionary = _state(0.0, 0.0)
	state.enemies = [{"id": "target1", "x": 5.0, "z": 4.0, "hp": 100.0, "visible": false, "travel_distance": 0.0}]
	audio.collect(state, true)
	state.presentation_time = 0.2
	state.enemies[0].travel_distance = 0.9
	state.enemies[0].x = 5.9
	_check(audio.collect(state, true).is_empty(), "Unobserved enemy movement never leaks through footsteps")
	state.presentation_time = 0.3
	state.enemies[0].visible = true
	_check(audio.collect(state, true).is_empty(), "New contact does not play the enemy's hidden movement history")
	state.presentation_time = 0.4
	state.enemies[0].travel_distance = 1.7
	state.enemies[0].x = 6.7
	var sounds: Array = audio.collect(state, true)
	_check(sounds.size() == 1 and sounds[0].event.attacker_id == "target1", "Only newly observed enemy travel becomes audible")
	state.presentation_time = 0.5
	state.enemies[0].visible = false
	state.enemies[0].travel_distance = 2.5
	state.enemies[0].x = 7.5
	_check(audio.collect(state, true).is_empty(), "Enemy footsteps stop on the frame sight is lost")
	audio.reset()
	state = _state(0.0, 0.0)
	state.units[0].erase("travel_distance")
	audio.collect(state, true)
	state.presentation_time = 0.2
	state.units[0].x = 2.0 + first_contact + 0.01
	_check(audio.collect(state, true).size() == 1, "Older replays can derive contacts from observed positional travel")

func _test_door_contacts() -> void:
	var audio = MovementAudio.new()
	var state: Dictionary = _state(0.0, 0.0)
	state.units[0].status = "OPENING"
	state.units[0].commands = [{"type": "OPEN_DOOR", "state": "RUNNING"}]
	audio.collect(state, true)
	state.presentation_time = 0.1
	_check(audio.collect(state, true).is_empty(), "Door intention or waiting operator alone makes no door contact")
	state.presentation_time = 0.2
	state.doors[0].progress = 0.04
	var sounds: Array = audio.collect(state, true)
	_check(sounds.size() == 1 and sounds[0].name == "door_latch", "Latch contact follows the first actual door motion")
	_check(sounds[0].point == [5.0, 4.0], "Door contact is positioned at the door, not the waiting operator")
	state.presentation_time = 0.3
	state.doors[0].progress = 0.2
	_check(audio.collect(state, true).is_empty(), "Continuing door swing does not repeat the latch")
	state.presentation_time = 0.4
	state.doors[0].progress = 1.0
	_check(audio.collect(state, true).is_empty(), "Movement helper does not duplicate the authoritative DOOR_OPEN completion sound")
	audio.reset()
	state = _state(0.0, 0.0)
	state.doors.append({"id": "d2", "x": 8.0, "z": 4.0, "progress": 0.0})
	audio.collect(state, true)
	state.presentation_time = 0.1
	state.doors[0].progress = 0.1
	state.doors[1].progress = 0.1
	sounds = audio.collect(state, true)
	_check(sounds.size() == 2 and sounds[0].event.attacker_id != sounds[1].event.attacker_id, "Two moving doors each produce one distinct contact")
	audio.reset()
	audio.collect(_state(0.0, 0.0), true)
	state = _state(0.1, 0.0)
	state.doors[0].progress = 0.2
	_check(audio.collect(state, true, true).is_empty(), "Replay seek across a latch threshold remains silent")

func _test_authored_gait_contacts() -> void:
	var profile = preload("res://scripts/locomotion_profile.gd")
	for example: Dictionary in [{"kind": "unit", "angle": 0.0, "clip": "RifleRun"}, {"kind": "enemy", "angle": 0.0, "clip": "RifleWalk"}, {"kind": "unit", "angle": PI, "clip": "RifleWalkBack"}, {"kind": "unit", "angle": PI * 0.5, "clip": "RifleStrafeRight"}, {"kind": "unit", "angle": -PI * 0.5, "clip": "RifleStrafeLeft"}]:
		var audio = MovementAudio.new()
		var state: Dictionary = _state(0.0, 0.0)
		state.units[0].kind = example.kind
		state.units[0].aim_facing = 0.0
		state.units[0].move_facing = example.angle
		audio.collect(state, true)
		var phases: Array = profile.CONTACT_PHASES[example.clip].duplicate()
		if float(phases[0]) == 0.0:
			phases = [phases[1], 1.0]
		var threshold: float = float(profile.STRIDES[example.clip]) * float(phases[0])
		state.presentation_time = 0.2
		state.units[0].travel_distance = threshold - 0.005
		state.units[0].x = 2.0 + threshold - 0.005
		_check(audio.collect(state, true).is_empty(), example.clip + " waits for its own measured contact distance")
		state.presentation_time = 0.21
		state.units[0].travel_distance = threshold + 0.005
		state.units[0].x = 2.0 + threshold + 0.005
		_check(audio.collect(state, true).size() == 1, example.clip + " contact follows its measured first foot landing")
		threshold = float(profile.STRIDES[example.clip]) * float(phases[1])
		state.presentation_time = 0.4
		state.units[0].travel_distance = threshold - 0.005
		state.units[0].x = 2.0 + threshold - 0.005
		_check(audio.collect(state, true).is_empty(), example.clip + " waits through the airborne interval before the opposite landing")
		state.presentation_time = 0.41
		state.units[0].travel_distance = threshold + 0.005
		state.units[0].x = 2.0 + threshold + 0.005
		_check(audio.collect(state, true).size() == 1, example.clip + " opposite foot uses its own measured landing phase")
	var audio = MovementAudio.new()
	audio.collect(_state(0.0, 0.0), true)
	audio.collect(_state(0.1, first_contact * 0.5), true)
	var state: Dictionary = _state(0.2, 0.5)
	state.units[0].aim_facing = 0.0
	state.units[0].move_facing = PI * 0.5
	_check(audio.collect(state, true).is_empty(), "Changing stride at a direction transition cannot manufacture a footfall")
