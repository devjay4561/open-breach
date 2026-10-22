extends SceneTree
const Actor = preload("res://scripts/actor_visual.gd")
const Replay = preload("res://scripts/replay.gd")
const Presentation = preload("res://scripts/presentation_state.gd")
var checks := 0
var failures: Array[String] = []
var bodies: Array[Node3D] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and failures.size() < 30: failures.append(message)
func actor() -> Dictionary:
	var body := Node3D.new()
	root.add_child(body)
	bodies.append(body)
	return Actor.create(body, false)
func reference(value: Dictionary, entity: Dictionary, events: Array, clock: float) -> void:
	if value.is_empty() or clock < float(value.last_clock):
		value.assign({"last_shot":-100.0,"last_hit":-100.0,"last_hit_protection":"","last_hit_direction":Vector3.ZERO,"last_throw":-100.0,"death_time":-1.0,"last_clock":-1.0})
	# Original full scan, including its accumulated maxima and last death row.
	for event: Dictionary in events:
		var time := float(event.get("time", -100.0))
		if time > clock + 0.001: continue
		if event.get("type", "") == "SHOT":
			if event.get("attacker_id", "") == entity.id: value.last_shot = maxf(value.last_shot, time)
			if event.get("target_id", "") == entity.id and event.get("hit", false) and time >= float(value.last_hit):
				value.last_hit = time
				value.last_hit_protection = str(event.get("protection", ""))
				value.last_hit_direction = Vector3.ZERO
				var origin: Array = event.get("from", [])
				var target: Array = event.get("to", [])
				if origin.size() == 2 and target.size() == 2:
					value.last_hit_direction = Vector3(float(target[0]) - float(origin[0]), 0.0, float(target[1]) - float(origin[1])).normalized()
		elif (event.get("type", "") in ["FLASH_RELEASE", "GRENADE_RELEASED"] or (event.get("type", "") == "STUN" and not event.has("projectile_id"))) and event.get("unit_id", "") == entity.id:
			value.last_throw = maxf(value.last_throw, time)
		elif event.get("type", "") == "INCAPACITATED" and event.get("entity_id", "") == entity.id:
			value.death_time = time
	if float(entity.get("hp", 100.0)) <= 0.0 and value.death_time < 0.0: value.death_time = clock - 5.0
	value.last_clock = clock
func sample(visual: Dictionary, expected: Dictionary, entity: Dictionary, events: Array, clock: float) -> void:
	reference(expected, entity, events, clock)
	Actor.sync(visual, entity, events, clock, 0.0, false)
	for key: String in ["last_shot", "last_hit", "last_hit_protection", "last_hit_direction", "last_throw", "death_time"]:
		check(visual[key] == expected[key], "%s %s at %.4f: incremental=%s reference=%s" % [entity.id, key, clock, visual[key], expected[key]])
func replay_frames(replay: RefCounted, source: String, reveal: bool) -> void:
	var visuals: Dictionary = {}
	var expected: Dictionary = {}
	var presentation := Presentation.new()
	var sequence := -1
	var last_clock := -1.0
	var times: Array[float] = []
	for frame: int in range(1201): times.append(frame / 30.0)
	# Both directions, repeated frozen samples and a seek to the final frame.
	times.append_array([8.0, 8.0, 8.0333, 31.0, 31.0, 2.0, 40.0])
	for clock: float in times:
		var state: Dictionary = replay.seek(clock, reveal)
		var events: Array = state.events
		if source != "window":
			if clock < last_clock: sequence = -1
			events = replay.events_since(sequence, clock, reveal)
			for event: Dictionary in events: sequence = maxi(sequence, int(event.seq))
		if source == "presentation":
			presentation.capture(state, events)
			state = presentation.sample(0.5) if clock > last_clock and clock - last_clock <= Presentation.STEP + Presentation.EPSILON else presentation.settle(state)
			events = state.get("presentation_events", state.events)
		var render_clock: float = float(state.get("presentation_time", state.time))
		for entity: Dictionary in state.units + state.enemies + state.civilians:
			if not visuals.has(entity.id):
				visuals[entity.id] = actor()
				expected[entity.id] = {}
			sample(visuals[entity.id], expected[entity.id], entity, events, render_clock)
		last_clock = clock
	for visual: Dictionary in visuals.values(): visual.model.get_parent().queue_free()
func edits_and_future() -> void:
	var visual := actor()
	var expected: Dictionary = {}
	var entity := {"id":"alpha","hp":100.0,"status":"READY","commands":[]}
	var events: Array = [{"seq":1,"time":0.5,"type":"SHOT","attacker_id":"alpha"}, {"seq":2,"time":2.0,"type":"FLASH_RELEASE","unit_id":"alpha"}]
	for clock: float in [0.0, 0.5, 1.0, 2.0, 2.0]: sample(visual, expected, entity, events, clock)
	check(visual._event_seq == 2, "Cursor consumes future events only once their presentation time arrives")
	events[0].time = 2.0
	events[0].target_id = "alpha"
	events[0].hit = true
	events[0].protection = "blocked"
	events[0].from = [0, 0]
	events[0].to = [1, 0]
	sample(visual, expected, entity, events, 2.0)
	check(visual.last_hit == 2.0, "Frozen nested edits behind the cursor are rescanned")
	check(visual.last_hit_protection == "blocked" and visual.last_hit_direction == Vector3.RIGHT, "Frozen hit edits update protection and shot direction together")
	events = [{"seq":1,"time":2.1,"type":"GRENADE_RELEASED","unit_id":"alpha"}]
	sample(visual, expected, entity, events, 2.1)
	check(visual.last_throw == 2.1, "Replacing/truncating the sequence rescans the new stream")
	events.append({"seq":2,"time":2.2,"type":"INCAPACITATED","entity_id":"alpha"})
	entity.hp = 0.0
	sample(visual, expected, entity, events, 2.2)
	sample(visual, expected, entity, events.duplicate(true), 2.3)
	sample(visual, expected, entity, [], 0.0)
	events = [{"time":1.0,"type":"STUN","unit_id":"alpha"}, {"time":0.2,"type":"SHOT","attacker_id":"alpha"}]
	for clock: float in [0.2, 0.4, 1.0]: sample(visual, expected, entity, events, clock)
func new_batch_order() -> void:
	for missing_seq: bool in [false, true]:
		var visual := actor()
		var expected: Dictionary = {}
		var entity := {"id":"alpha","hp":100.0,"status":"READY","commands":[]}
		sample(visual, expected, entity, [{"seq":1,"time":1.0,"type":"SHOT","attacker_id":"alpha"}], 1.0)
		var middle := {"seq":0,"time":2.0,"type":"FLASH_RELEASE","unit_id":"alpha"}
		if missing_seq: middle.erase("seq")
		var events: Array = [{"seq":3,"time":2.0,"type":"SHOT","attacker_id":"alpha"}, middle, {"seq":4,"time":2.0,"type":"INCAPACITATED","entity_id":"alpha"}]
		sample(visual, expected, entity, events, 2.0)
		check(visual.last_shot == 2.0 and visual.last_throw == 2.0, "A new batch starts at zero despite an out-of-order or missing middle seq")
func run() -> void:
	var replay := Replay.new()
	var loaded: Dictionary = replay.load_data(JSON.parse_string(FileAccess.get_file_as_string("res://../tests/artifacts/combat-benchmark.breach-replay.json")))
	check(bool(loaded.ok), "Real combat replay fixture loads")
	if loaded.ok:
		for reveal: bool in [false, true]:
			for source: String in ["window", "batch", "presentation"]: replay_frames(replay, source, reveal)
	edits_and_future()
	new_batch_order()
	for body: Node3D in bodies:
		if is_instance_valid(body): body.queue_free()
	await process_frame
	await process_frame
	print("BREACH_ACTOR_EVENT_CURSOR_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
