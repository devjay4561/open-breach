extends SceneTree
const Catalog = preload("res://scripts/mission_catalog.gd")
const Replay = preload("res://scripts/replay.gd")
const Sim = preload("res://scripts/simulation.gd")
const Presentation = preload("res://scripts/presentation_state.gd")
const World = preload("res://scripts/world_view.gd")
class CountingSim extends "res://scripts/simulation.gd":
	var snapshots := 0
	var loads := 0
	func snapshot(reveal: bool = false) -> Dictionary:
		snapshots += 1
		return super.snapshot(reveal)
	func load_mission(mission: Dictionary) -> void:
		loads += 1
		super.load_mission(mission)
class CountingReplay extends "res://scripts/replay.gd":
	var seeks := 0
	func seek(at_time: float, reveal: bool = false) -> Dictionary:
		seeks += 1
		return super.seek(at_time, reveal)
class CountingWorld extends "res://scripts/world_view.gd":
	var displays := 0
	var last_events: Array = []
	func display(state: Dictionary, selected_id: String, planning: bool, delta: float) -> void:
		displays += 1
		last_events = state.get("presentation_events", []).duplicate(false)
		super.display(state,selected_id,planning,delta)
class Harness extends "res://scripts/main.gd":
	var messages: Array = []
	var ack_display_counts: Array = []
	func _ready() -> void: pass
	func _emit(message: Dictionary) -> void:
		messages.append(message.duplicate(true))
		if message.get("type","") == "state" and not quality_rendered.is_empty(): ack_display_counts.append(world.displays)
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func run() -> void:
	var map := Catalog.load("T01")
	var sim := Sim.new()
	sim.load_mission(map)
	var initial: Dictionary = sim.snapshot(true)
	var record := Replay.new()
	record.begin(map)
	record.capture(initial)
	var unchanged := initial.duplicate(true)
	unchanged.time = 0.01
	unchanged.tick = 1
	record.capture(unchanged)
	check(record.frames.size() == 1, "Typed discrete comparison keeps the original 0.1s sample skip")
	unchanged.enemies[0].hp = float(unchanged.enemies[0].hp) - 1.0
	record.capture(unchanged)
	check(record.frames.size() == 2, "An event-free HP change still records its exact tick")
	var result_state := initial.duplicate(true)
	result_state.result = {"success":false,"reason":"before"}
	var signature := record._discrete_signature(result_state)
	result_state.result.reason = "after"
	check(signature != record._discrete_signature(result_state), "Retained discrete values cannot alias a caller's mutable result")
	var full_events: Array = [{"seq":2,"tick":1,"time":0.1,"type":"INCAPACITATED","kind":"enemy","entity_id":"target1","to":[6.4,7.5],"message":"fixture"}]
	for i in range(3,67):
		full_events.append({"seq":i,"tick":i,"time":0.1+float(i)/100.0,"type":"SHOT","attacker_id":"alpha","target_id":"target2","hit":false,"hostile":false,"message":"fixture"})
	var ending := initial.duplicate(true)
	ending.time = 1.0
	ending.tick = 70
	ending.enemies[0].visible = true
	ending.enemies[0].hp = 0.0
	ending.enemies[0].status = "INCAPACITATED"
	ending.events = full_events.slice(-40)
	record = Replay.new()
	record.begin(map)
	record.capture(initial)
	record.finish(ending) # Legacy caller still accepts the recent-event window.
	var streamed := Replay.new()
	streamed.begin(map)
	streamed.capture(initial)
	streamed.capture(ending, full_events)
	streamed.finish(ending)
	check(streamed.data.events.size() == 66, "Recorder keeps every event in a batch larger than the HUD window")
	var loaded := Replay.new()
	var response := loaded.load_data(JSON.parse_string(JSON.stringify(streamed.export_data())))
	check(bool(response.ok), "The complete event stream remains schema-v1 compatible: "+str(response))
	var landed := loaded.seek(1.0,false)
	check(landed.events.size() == 40 and landed.neutralized_ids == ["target1"], "Seek preserves bounded HUD events and all earlier neutralizations")
	var main := Harness.new()
	main._reset_fx_cursor(landed)
	check(main._fx_neutralized_ids.has("target1"), "Controller seek resync restores a death outside the last 40 events")
	var all_new: Array = loaded.events_since(1,1.0)
	check(all_new.size() == 65 and all_new[0].seq == 2 and all_new[-1].seq == 66, "Replay dispatch returns the whole ordered sequence range")
	landed.neutralized_ids.clear()
	check(loaded.seek(0.0,false).neutralized_ids.is_empty(), "Rewind clears the accumulated neutralized prefix")
	check(loaded.seek(1.0,false).neutralized_ids == ["target1"], "Returned prefix arrays do not mutate replay caches")
	var presentation := Presentation.new()
	presentation.reset(initial)
	var first := ending.duplicate(true)
	first.time = 1.0/30.0
	for event: Dictionary in full_events: event.time = first.time
	first.events = full_events.slice(-40)
	presentation.capture(first,full_events)
	check(presentation.sample(0.0).presentation_events.is_empty(), "The event stream waits for the presentation clock")
	var settled := presentation.settle(first)
	check(settled.presentation_events.size() == 65, "Pausing releases every delayed event once, without HUD duplicates")
	check(not presentation.settle(first).has("presentation_events"), "A second paused frame cannot replay the pending stream")
	main.free()
	await test_controller(map)
	print("BREACH_REPLAY_MAIN_OPTIMIZATION_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
func test_controller(map: Dictionary) -> void:
	var app := Harness.new()
	root.add_child(app)
	app.set_process(false)
	app.set_process_unhandled_input(false)
	app.maps = {"T01":map}
	app.sim = CountingSim.new()
	app.recorder = CountingReplay.new()
	app.world = CountingWorld.new()
	app.add_child(app.world)
	app._load_mission("T01",true)
	app.sim.snapshots = 0
	for i in range(6): app._process(0.0)
	check(app.sim.snapshots == 0, "Unchanged planning frames reuse the observed snapshot")
	app.messages.clear()
	app._action({"action":"command","type":"WAIT","args":{"duration":1.0}})
	var states := app.messages.filter(func(message): return message.type == "state")
	check(states.size() == 1 and states[0].units[0].commands.back().type == "WAIT", "A command sends one final state with the edited queue")
	check(app.sim.snapshots == 1, "Nested command state requests create one snapshot")
	app._action({"action":"unit_posture","settings":{"stance":"crouched"}})
	check(app.shown.units[0].stance == "crouched", "A paused posture edit refreshes the cached authoritative observation")
	app._action({"action":"input_focus","blocked":true})
	check(app._state_batch_depth == 0, "Early callback returns always close the state batch")
	app._action({"action":"input_focus","blocked":false})
	var displayed_before: int = app.world.displays
	app._action({"action":"tool","tool":"face","_quality_token":"test-ack"})
	check(app.ack_display_counts.is_empty(), "An action response cannot claim a render before world.display")
	app._process(0.0)
	check(app.ack_display_counts == [displayed_before+1] and app._state_batch_depth == 0, "The frame closes its batch and sends the acknowledgement after display")
	app.messages.clear()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_DELETE
	key.pressed = true
	app._unhandled_input(key)
	states = app.messages.filter(func(message): return message.type == "state")
	check(states.size() == 1 and states[0].units[0].commands.back().state == "CANCELLED", "Direct keyboard mutations invalidate the cached state")
	var candidate := CountingSim.new()
	candidate.load_mission(map)
	app._load_mission("T01",true,{},candidate)
	check(app.sim == candidate and candidate.loads == 1, "A validated prepared simulation is committed without another load")
	for i in range(64): app._action({"action":"signal","channel":"A"})
	check(app.sim._pending_record_events.is_empty() and app.sim.events.size() == 40, "Paused action flushes drain the subscriber while keeping the HUD window bounded")
	check(app.recorder.data.events.size() == 65 and app.recorder.data.events.back().released == 0, "Every planning signal remains recorded, including signals with no waiting unit")
	app._process(0.0)
	check(app.world.last_events.size() == 64, "The next paused display receives every planning event outside the HUD window")
	app._action({"action":"toggle"})
	check(app.recorder.data.events.size() == 65 and app.sim._pending_record_events.is_empty(), "First execution preserves the full drained planning prefix")
	app._action({"action":"pause"})
	app.recorder.capture(app.sim.snapshot(true))
	var changed: Dictionary = app.sim.snapshot(true)
	changed.time = 1.0
	changed.tick = 30
	app.recorder.finish(changed)
	app._start_replay()
	app.replay_playing = false
	app.recorder.seeks = 0
	for i in range(6): app._process(0.0)
	check(app.recorder.seeks == 0, "Repeated paused replay frames reuse their exact seek result")
	app._action({"action":"replay_reveal","value":true})
	check(app.recorder.seeks == 1 and app.shown.enemies.size() == map.enemies.size(), "Reveal changes invalidate paused replay samples")
	app._action({"action":"replay_seek","time":0.5})
	check(app.recorder.seeks == 2 and app.shown.time == 0.5, "An explicit seek updates immediately while paused")
	var replacement: Dictionary = JSON.parse_string(JSON.stringify(app.recorder.export_data()))
	for meta: Dictionary in replacement.metadata: meta.plan_revisions = 999
	var imported: Dictionary = app.recorder.load_data(replacement)
	check(bool(imported.ok), "The same recorder object can load a replacement recording")
	app._process(0.0)
	check(app.recorder.seeks == 3 and app.shown.plan_revisions == 999, "Same-object load_data invalidates an otherwise identical seek key")
	var corrupt := replacement.duplicate(true)
	corrupt.duration = 9999.0
	check(not bool(app.recorder.load_data(corrupt).ok), "A corrupt replacement is rejected")
	app._process(0.0)
	check(app.recorder.seeks == 3 and app.shown.plan_revisions == 999, "A failed import keeps the current replay and its sample")
	app.recorder.begin(map)
	app.recorder.capture(app.sim.snapshot(true))
	app._process(0.0)
	check(app.recorder.seeks == 4 and app.shown.time == 0.0, "Same-object begin invalidates the old paused sample")
	var samples: Array = []
	for i in range(180): samples.append([float(i)*0.05,sin(float(i))])
	var simplified: Array = app._simplify_points(samples,0.05)
	check(simplified.size() <= 32 and simplified[0] == samples[0] and simplified[-1] == samples[-1], "Shared iterative simplification keeps endpoints and the command limit")
	app.queue_free()
	await process_frame
	await process_frame
