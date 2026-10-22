extends SceneTree
## P2: real controller, input, saved primitives and map presentation. Only
## the outgoing browser transport is replaced by a recording test sink.
const MainScene = preload("res://main.tscn")
const STEP: float = 1.0 / 30.0
const IDS: Array[String] = ["alpha", "bravo", "charlie", "delta"]
var checks: int = 0
var failures: Array[String] = []

class RecordingMain extends "res://scripts/main.gd":
	var messages: Array[Dictionary] = []
	func _emit(message: Dictionary) -> void:
		messages.append(message.duplicate(true))

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _last(session: Node, type: String) -> Dictionary:
	for index: int in range(session.messages.size() - 1, -1, -1):
		if str(session.messages[index].get("type", "")) == type:
			return session.messages[index]
	return {}

func _bridge(session: Node, action: Dictionary) -> void:
	session._on_web_message([JSON.stringify(action)])
	session._flush_inputs()

func _group(session: Node, ids: Array) -> void:
	_bridge(session, {"action": "select", "id": ""})
	for id: String in ids: _bridge(session, {"action": "select", "unit_id": id, "extend": true})

func _key(code: int, shift: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.shift_pressed = shift
	return event

func _click(session: Node, unit_id: String, shift: bool) -> InputEventMouseButton:
	var unit: Dictionary = session.sim._find(session.sim.units, unit_id)
	var event := InputEventMouseButton.new()
	event.position = session.world.camera.unproject_position(session.world.surface_position(Vector2(float(unit.x), float(unit.z)), 0.95))
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.shift_pressed = shift
	return event

func _rngs(session: Node) -> Array:
	return [session.sim._rng.state, session.sim._hit_region_rng.state, session.sim._breach_rng.state, session.sim._surrender_rng.state]

func _queues(session: Node) -> String:
	var rows: Array = []
	for unit: Dictionary in session.sim.units: rows.append(unit.commands)
	return JSON.stringify(rows)

func _same_point(a: Array, b: Array) -> bool:
	# JSON transport and Godot Vector2 have different float storage precision.
	return a.size() == 2 and b.size() == 2 and Vector2(float(a[0]), float(a[1])).distance_to(Vector2(float(b[0]), float(b[1]))) <= 0.00001

func _preview(session: Node, order: Array = IDS, options: Dictionary = {}) -> Dictionary:
	_bridge(session, {"action": "room_drill_preview", "door_id": "d1", "method": "OPEN_DOOR", "order": order, "options": options, "preview_id": "test-preview"})
	return _last(session, "room_drill_preview").get("data", {})

func _command_index(session: Node, id: String, type: String, stage: String) -> int:
	var unit: Dictionary = session.sim._find(session.sim.units, id)
	for index: int in range(unit.commands.size() - 1, -1, -1):
		var command: Dictionary = unit.commands[index]
		if command.type == type and str(command.args.get("drill", {}).get("stage", "")) == stage:
			return index
	return -1

func _run() -> void:
	# This is the packed production scene with its actual inherited controller.
	var session: Node = MainScene.instantiate()
	session.set_script(RecordingMain)
	root.add_child(session)
	session.set_process(false)
	await process_frame # Initialization only; simulation always uses fixed STEP.
	session._action({"action": "start", "mission": "M01", "seed": 7401})
	session._process(STEP)
	check(session.mode == "PLANNING" and session.mission_id == "M01", "Production MainScene did not initialize M01")
	check(session.sim._door_observations.has("d1"), "M01 entrance is not observed by its starting squad")
	check(not Input.use_accumulated_input, "Native input gestures are still accumulated")
	_selection(session)
	_context(session)
	_pure_preview(session)
	_macro_and_render(session)
	session.queue_free()
	await process_frame # Flush scene disposal only.
	print("BREACH_ROOM_DRILL_MAIN_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _selection(session: Node) -> void:
	_bridge(session, {"action": "select", "unit_id": "alpha"})
	_bridge(session, {"action": "select", "unit_id": "bravo", "extend": true})
	check(session.selected_units == ["alpha", "bravo"] and session.selected == "bravo", "Shift-card bridge did not append the clicked own operator")
	check(_last(session, "state").get("selected_units", []) == ["alpha", "bravo"], "Public state did not publish the selected own group")
	_bridge(session, {"action": "select", "unit_id": "alpha", "extend": true})
	check(session.selected_units == ["bravo"] and session.selected == "bravo", "Shift-card removal lost the focused group member")
	_bridge(session, {"action": "select", "unit_id": "bravo", "extend": true})
	check(session.selected_units.is_empty() and session.selected.is_empty(), "Toggling the last selected card did not clear selection")
	session._unhandled_input(_key(KEY_1))
	session._unhandled_input(_key(KEY_2, true))
	session._unhandled_input(_key(KEY_3, true))
	session._unhandled_input(_key(KEY_4, true))
	check(session.selected_units == IDS and session.selected == "delta", "Native Shift-Digit selection did not retain 1–4 order")
	session._unhandled_input(_key(KEY_4, true))
	check(session.selected_units == ["alpha", "bravo", "charlie"] and session.selected == "charlie", "Native Shift-Digit toggle did not focus the remaining member")
	session._unhandled_input(_key(KEY_1))
	check(session.selected_units == ["alpha"], "Plain Digit selection did not replace the group")
	_bridge(session, {"action": "select", "unit_id": "hidden_enemy", "extend": true})
	check(session.selected_units == ["alpha"], "A non-owned ID entered the own-unit selection group")
	# Shift-LMB is handled before tools and drag arming, even with MOVE active.
	session._process(STEP)
	var press := _click(session, "bravo", true)
	check(session.world.pick_unit(press.position) == "bravo", "Actual projected BRAVO screen point did not pick BRAVO")
	var before := _queues(session)
	session.tool = "move"
	session._unhandled_input(press)
	check(session.selected_units == ["alpha", "bravo"] and session.drag.is_empty() and _queues(session) == before, "Shift-LMB armed a path drag or issued MOVE instead of toggling selection")
	session._unhandled_input(press)
	check(session.selected_units == ["alpha"] and session.drag.is_empty(), "Second Shift-LMB did not toggle the own map actor off")
	session.tool = "select"
	session._unhandled_input(_click(session, "bravo", false))
	check(session.selected_units == ["bravo"] and str(session.drag.get("kind", "")) == "path", "Plain own-map selection did not reset the group and arm its normal path gesture")
	session._cancel_drag()
	_group(session, IDS)
	var group: Array = session.selected_units.duplicate()
	_bridge(session, {"action": "command", "unit_id": "bravo", "type": "WAIT", "args": {"duration": 1.0}})
	_bridge(session, {"action": "command", "unit_id": "bravo", "type": "WAIT", "args": {"duration": 2.0}})
	check(session.selected == "bravo" and session.selected_units == group and session.sim.units[1].commands.size() == 2 and session.sim.units[0].commands.is_empty(), "Command-row unit_id targeted the wrong actor or collapsed the group")
	_bridge(session, {"action": "select_command", "unit_id": "bravo", "index": 0})
	check(session.selected_command == 0 and session.world._waypoint_unit == "bravo" and session.selected_units == group, "Row selection lost its explicit operator or the selected group")
	_bridge(session, {"action": "tool", "unit_id": "charlie", "tool": "face", "index": 0})
	check(session.selected == "charlie" and session.tool == "face" and session.selected_units == group, "Row face tool did not preserve group focus")
	_bridge(session, {"action": "reorder", "unit_id": "bravo", "index": 1, "direction": -1})
	check(float(session.sim.units[1].commands[0].args.duration) == 2.0 and session.selected_units == group, "Row reorder did not act on BRAVO while preserving the group")
	_bridge(session, {"action": "update", "unit_id": "bravo", "index": 0, "args": {"duration": 2.5}})
	check(float(session.sim.units[1].commands[0].args.duration) == 2.5 and session.selected_units == group, "Row argument edit lost its explicit unit_id")
	_bridge(session, {"action": "remove", "unit_id": "bravo", "index": 0})
	check(session.sim.units[1].commands.size() == 1 and float(session.sim.units[1].commands[0].args.duration) == 1.0 and session.selected_units == group, "Row removal changed the wrong queue or collapsed the group")
	_bridge(session, {"action": "select", "unit_id": "alpha"})
	check(session.selected_units == ["alpha"], "Plain browser card selection did not replace the group")
	session._action({"action": "retry"})

func _context(session: Node) -> void:
	var hidden := ""
	for door: Dictionary in session.shown.doors:
		if not bool(door.get("observed", false)): hidden = str(door.id)
	check(not hidden.is_empty(), "M01 contains no hidden door for its privacy contract")
	_group(session, IDS)
	session.messages.clear()
	var before := _queues(session)
	session._open_context({"target": "door", "id": hidden}, Vector2(320, 240))
	check(not session.context_open and _last(session, "context").is_empty() and _queues(session) == before, "A hidden door exposed a native context or changed a queue")
	for count: int in range(1, 5):
		_group(session, IDS.slice(0, count))
		session.messages.clear()
		session._open_context({"target": "door", "id": "d1"}, Vector2(320, 240))
		var context := _last(session, "context")
		check(session.context_open and context.get("selected_units", []) == IDS.slice(0, count), "Observed door context lost its selected own roster")
		check(context.get("actions", []).has("ENTER_ROOM") == (count >= 2), "ENTER_ROOM visibility did not follow the selected 2–4 operator requirement")
		_bridge(session, {"action": "context_close"})
	_group(session, IDS)
	_bridge(session, {"action": "room_drill_preview", "door_id": hidden, "method": "OPEN_DOOR", "order": IDS})
	check(not bool(_last(session, "room_drill_preview").get("data", {}).get("ok", false)) and session.world._drill_preview.is_empty() and _queues(session) == before, "Hidden door preview exposed static entry detail or mutated queues")
	var sequence: int = session.sim._command_sequence
	_bridge(session, {"action": "room_drill", "door_id": "d1", "method": "OPEN_DOOR", "order": ["alpha", "alpha"]})
	check(_queues(session) == before and session.sim._command_sequence == sequence and session.world._drill_preview.is_empty(), "Invalid roster macro partially appended commands or retained a misleading preview")
	for count: int in range(2, 5):
		var preview := _preview(session, IDS.slice(0, count))
		check(bool(preview.get("ok", false)) and preview.get("slots", []).size() == count, "M01 observed door did not preview its %d-person roster: %s" % [count, str(preview.get("reason_code", ""))])

func _pure_preview(session: Node) -> void:
	var baseline := ""
	for trial: int in range(30):
		# Reinitialize the authoritative model with 30 fixed mission seeds while
		# retaining the real scene and identical authored map presentation.
		var configured: Dictionary = session._configured_mission("M01", session._canonical_options("M01", {"seed": 7401 + trial}))
		session.sim.load_mission(configured)
		session._shown_dirty = true
		session._send_state()
		var before := JSON.stringify(session.sim.snapshot(true))
		var rng_before := _rngs(session)
		var sequence: int = session.sim._command_sequence
		var preview := _preview(session)
		check(bool(preview.get("ok", false)) and preview.get("slots", []).size() == 4, "Seed %d: actual bridge did not produce the M01 4-person preview: %s" % [trial, str(preview.get("reason_code", preview.get("message_key", "")))])
		check(_last(session, "room_drill_preview").get("preview_id", "") == "test-preview", "Seed %d: preview response lost its request correlation" % trial)
		check(JSON.stringify(session.sim.snapshot(true)) == before and _rngs(session) == rng_before and session.sim._command_sequence == sequence and session.sim.time == 0.0 and session.sim.tick == 0, "Seed %d: preview consumed time, RNG, command IDs or authoritative state" % trial)
		var encoded := JSON.stringify(preview)
		if trial == 0: baseline = encoded
		check(encoded == baseline, "Seed %d: hidden seeded NPC choices changed the static preview" % trial)
		check(not encoded.contains('"enemies"') and not encoded.contains('"civilians"') and not encoded.contains('"e1"') and not encoded.contains('"c1"'), "Seed %d: preview serialized hidden actor fields or IDs" % trial)
		check(JSON.stringify(session.world._drill_preview) == encoded, "Seed %d: world preview diverged from the public bridge response" % trial)
	# Moving hidden actors and replacing a hidden live door's state cannot
	# influence a planning result derived from the known authored floor plan.
	var enemies: Array = session.sim.enemies.duplicate(true)
	var civilians: Array = session.sim.civilians.duplicate(true)
	var doors: Array = session.sim.doors.duplicate(true)
	for enemy: Dictionary in session.sim.enemies:
		enemy.x = 0.8
		enemy.z = 0.8
		enemy.hp = 1.0
		enemy.status = "SURRENDERED"
	for civilian: Dictionary in session.sim.civilians:
		civilian.x = 0.9
		civilian.z = 0.9
	for door: Dictionary in session.sim.doors:
		if not session.sim._door_observations.has(door.id):
			door.state = "OPEN"
			door.progress = 1.0
			door.destroyed = true
	check(JSON.stringify(_preview(session)) == baseline, "Live hidden actor positions, status or door states leaked into the preview")
	session.sim.enemies = enemies
	session.sim.civilians = civilians
	session.sim.doors = doors
	session._action({"action": "retry"})
	_group(session, IDS)

func _macro_and_render(session: Node) -> void:
	var preview := _preview(session, IDS, {"append": false, "go_long": true})
	check(bool(preview.get("ok", false)), "M01 macro fixture did not produce a valid GO_LONG preview: %s" % JSON.stringify(preview))
	if not bool(preview.get("ok", false)): return
	var before_rng := _rngs(session)
	_bridge(session, {"action": "room_drill", "door_id": "d1", "method": "OPEN_DOOR", "order": IDS, "options": {"append": false, "go_long": true}})
	var sync_id: String = str(session.world._drill_preview.get("sync_id", ""))
	check(not sync_id.is_empty() and _rngs(session) == before_rng and session.sim.time == 0.0, "Applying the macro did not create an owned sync ID or consumed simulation time/RNG")
	if sync_id.is_empty(): return
	var door_count := 0
	for unit: Dictionary in session.sim.units:
		check(unit.commands.size() >= 6 and unit.commands.size() <= 32, "%s macro did not expand to ordinary editable primitives" % unit.id)
		for command: Dictionary in unit.commands:
			check(session.sim.COMMANDS.has(str(command.type)) and command.type != "ENTER_ROOM", "Macro emitted a new primitive or unsupported command")
			check(str(command.args.get("drill", {}).get("sync_id", "")) == sync_id, "Expanded command lost its saved drill metadata")
			if command.type == "OPEN_DOOR": door_count += 1
	check(door_count == 1, "Macro assigned door handling to more than one operator")
	_bridge(session, {"action": "sync_delay", "sync_id": sync_id + ":ready", "delay_ticks": 15})
	for unit: Dictionary in session.sim.units:
		var ready: int = _command_index(session, str(unit.id), "WAIT_FOR_SIGNAL", "ready")
		check(ready >= 0 and int(unit.commands[ready].args.delay_ticks) == 15, "Sync delay did not update every participant atomically")
	var before := _queues(session)
	for bad: Variant in [-1, 3601, 2.5, "15"]:
		_bridge(session, {"action": "sync_delay", "sync_id": sync_id + ":ready", "delay_ticks": bad})
		check(_queues(session) == before, "Invalid sync delay partially changed participant queues")
	var active_index := _command_index(session, "delta", "WAIT_FOR_SIGNAL", "ready")
	session.sim.units[3].commands[active_index].state = "RUNNING"
	before = _queues(session)
	_bridge(session, {"action": "sync_delay", "sync_id": sync_id + ":ready", "delay_ticks": 20})
	check(_queues(session) == before, "A running participant allowed a partial sync-delay update")
	session.sim.units[3].commands[active_index].state = "PENDING"
	session._shown_dirty = true
	session._process(STEP)
	check(session.world._selected_units == IDS, "World did not render the selected group from public own state")
	for id: String in IDS:
		check(bool(session.world._entity_nodes[id].selection.visible), "%s selected-group ring was not rendered" % id)
	check(session.world._drill_mesh_node.visible and session.world._drill_mesh.get_surface_count() == 1, "Planning did not draw the entry preview mesh")
	check(session.world._drill_labels.size() == 10, "Four stack badges, four ghosts and two GO_LONG badges were not rendered")
	var label_counts: Dictionary = {}
	for label: Label3D in session.world._drill_labels:
		label_counts[label.text] = int(label_counts.get(label.text, 0)) + 1
		check(label.visible, "Planning preview badge is hidden")
	for index: int in range(1, 5): check(int(label_counts.get(str(index), 0)) == 2, "Stack/ghost number %d did not appear at both owned planned points" % index)
	var mesh_arrays: Array = session.world._drill_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = mesh_arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = mesh_arrays[Mesh.ARRAY_COLOR]
	var hatches := false
	var entry_fans := false
	var arrival_fans := false
	var ghosts := false
	# ImmediateMesh packs vertex colors into RGBA8; a single encoded channel
	# step is the exact storage bound, rather than a visual test tolerance.
	var channel_step := 1.0 / 255.0 + 0.00001
	for color: Color in colors:
		hatches = hatches or absf(color.a - 0.45) <= channel_step
		entry_fans = entry_fans or absf(color.a - 0.18) <= channel_step
		arrival_fans = arrival_fans or absf(color.a - 0.2) <= channel_step
		ghosts = ghosts or absf(color.a - 0.35) <= channel_step
	check(vertices.size() > 300 and hatches and entry_fans and arrival_fans and ghosts, "Actual preview mesh omitted funnel hatching, entry/arrival fans or ghost silhouettes")
	# Executing a single fixed tick hides planning overlays. Pausing renders
	# the same owned primitive plan again without a timing-based assertion.
	_bridge(session, {"action": "toggle"})
	session._process(STEP)
	check(session.mode == "EXECUTING" and not session.world._drill_mesh_node.visible, "Executing mode left planning drill geometry visible")
	for label: Label3D in session.world._drill_labels: check(not label.visible, "Executing mode left a planning drill badge visible")
	_bridge(session, {"action": "pause"})
	session._process(STEP)
	check(session.mode == "PLANNING" and session.world._drill_mesh_node.visible, "Pausing failed to restore the owned drill preview")
	# Editing the ordinary command rows must move the real rendered ghost
	# and rotate its fan, without recalculating from undiscovered actors.
	var entry_index := _command_index(session, "alpha", "MOVE", "domination")
	if entry_index < 0: entry_index = _command_index(session, "alpha", "MOVE", "entry")
	check(entry_index >= 0, "ALPHA has no expanded entry MOVE to edit")
	if entry_index < 0: return
	var move_args: Dictionary = session.sim.units[0].commands[entry_index].args.duplicate(true)
	var edited_target: Array = [float(move_args.target[0]), float(move_args.target[1]) - 0.15]
	move_args.target = edited_target
	_bridge(session, {"action": "update", "unit_id": "alpha", "index": entry_index, "args": move_args})
	check(session.sim.units[0].commands[entry_index].args.target == edited_target, "Ordinary row update rejected a reachable edited entry MOVE")
	var face_index := _command_index(session, "alpha", "FACE", "domination")
	check(face_index >= 0, "ALPHA has no expanded domination FACE to edit")
	if face_index < 0: return
	var face_args: Dictionary = session.sim.units[0].commands[face_index].args.duplicate(true)
	face_args.target = [12.5, 13.5]
	_bridge(session, {"action": "update", "unit_id": "alpha", "index": face_index, "args": face_args})
	session._process(STEP)
	var resolved: Dictionary = session.world._resolved_room_drill_preview()
	var slot: Dictionary = resolved.slots[0]
	check(slot.domination == edited_target and slot.face_target == face_args.target, "Edited MOVE/FACE arguments were not reflected in the resolved world preview")
	var fan: Dictionary = slot.sector_domination
	var span := fposmod(float(fan.end) - float(fan.start), TAU)
	var center := wrapf(float(fan.start) + span * 0.5, -PI, PI)
	var expected := (Vector2(float(face_args.target[0]), float(face_args.target[1])) - Vector2(float(edited_target[0]), float(edited_target[1]))).angle()
	check(absf(wrapf(center - expected, -PI, PI)) < 0.0001, "Edited FACE did not rotate the actual domination fan")
	var long_move := _command_index(session, "alpha", "MOVE", "go_long")
	var long_face := _command_index(session, "alpha", "FACE", "go_long")
	check(long_move >= 0 and long_face >= 0, "GO_LONG did not expand into editable ordinary MOVE/FACE rows")
	if long_move >= 0 and long_face >= 0:
		var long_args: Dictionary = session.sim.units[0].commands[long_move].args.duplicate(true)
		var long_point := Vector2(float(long_args.target[0]), float(long_args.target[1]))
		for offset: Vector2 in [Vector2(0, 0.10), Vector2(0.10, 0), Vector2(-0.10, 0), Vector2(0, -0.10)]:
			if session.sim.nav.walkable(long_point + offset):
				long_args.target = [long_point.x + offset.x, long_point.y + offset.y]
				break
		_bridge(session, {"action": "update", "unit_id": "alpha", "index": long_move, "args": long_args})
		check(_same_point(session.sim.units[0].commands[long_move].args.target, long_args.target), "Ordinary GO_LONG MOVE update rejected the reachable edited point")
		var long_face_args: Dictionary = session.sim.units[0].commands[long_face].args.duplicate(true)
		long_face_args.target = [12.0, 13.0]
		_bridge(session, {"action": "update", "unit_id": "alpha", "index": long_face, "args": long_face_args})
		session._process(STEP)
		resolved = session.world._resolved_room_drill_preview()
		var long_goal: Dictionary = resolved.go_long[0]
		check(_same_point(long_goal.target, long_args.target) and _same_point(long_goal.face_target, long_face_args.target), "Edited GO_LONG MOVE/FACE did not update its resolved world goal")
		fan = long_goal.sector
		span = fposmod(float(fan.end) - float(fan.start), TAU)
		center = wrapf(float(fan.start) + span * 0.5, -PI, PI)
		expected = (Vector2(float(long_face_args.target[0]), float(long_face_args.target[1])) - Vector2(float(long_args.target[0]), float(long_args.target[1]))).angle()
		check(absf(wrapf(center - expected, -PI, PI)) < 0.0001, "Edited GO_LONG FACE did not rotate its resolved sector")
	# The on-disk format remains v1 and consists solely of expanded primitives.
	var exported: Dictionary = session._export_plan()
	check(int(exported.schema_version) == 1 and exported.kind == "breach-plan", "Drill changed the existing plan file envelope")
	# Existing controller tests load through _action, avoiding the browser's
	# paint-gap scheduler, whose timing is unrelated to the drill contract.
	session._action({"action": "load_plan", "data": exported})
	check(session.sim.time == 0.0 and not session.world._drill_preview.is_empty() and str(session.world._drill_preview.get("sync_id", "")) == sync_id, "Saved primitive plan did not reconstruct its owned room preview")
	var loaded: Dictionary = session._export_plan()
	check(loaded.units == exported.units, "Saving/loading edited drill primitives changed their authored arguments")
	session._process(STEP)
	resolved = session.world._resolved_room_drill_preview()
	check(not resolved.is_empty() and resolved.get("slots", [])[0].domination == edited_target, "Loaded plan preview did not follow the edited ordinary MOVE")
	# Remove every ALPHA entry checkpoint through the same row bridge. Other
	# participants and the stack/door orders remain ordinary independent rows.
	var loaded_group: Array = session.selected_units.duplicate()
	long_move = _command_index(session, "alpha", "MOVE", "go_long")
	if long_move >= 0:
		_bridge(session, {"action": "remove", "unit_id": "alpha", "index": long_move})
		session._process(STEP)
		resolved = session.world._resolved_room_drill_preview()
		var alpha_long := false
		for goal: Dictionary in resolved.get("go_long", []): alpha_long = alpha_long or str(goal.unit_id) == "alpha"
		check(not alpha_long and resolved.get("go_long", []).size() == 1, "Removing GO_LONG MOVE retained the deleted deeper goal or removed another operator's goal")
	for index: int in range(session.sim.units[0].commands.size() - 1, -1, -1):
		var command: Dictionary = session.sim.units[0].commands[index]
		if command.type == "MOVE" and str(command.args.get("drill", {}).get("stage", "")) in ["entry", "domination"]:
			_bridge(session, {"action": "remove", "unit_id": "alpha", "index": index})
	session._process(STEP)
	resolved = session.world._resolved_room_drill_preview()
	check(bool(resolved.slots[0].get("deleted_entry", false)), "Deleting ordinary entry rows left ALPHA's obsolete arrival ghost active")
	check(session.selected_units == loaded_group, "Removing expanded macro rows collapsed the selected group")
	var queues_before_cancel := _queues(session)
	_bridge(session, {"action": "room_drill_preview", "clear": true, "preview_id": "cancel-preview"})
	session._process(STEP)
	check(session.world._drill_preview.is_empty() and not session.world._drill_mesh_node.visible, "Cancelling the preview left its mesh visible")
	check(_last(session, "room_drill_preview").get("data", {"stale": true}).is_empty(), "Preview cancellation did not publish an empty response")
	check(_queues(session) == queues_before_cancel, "Cancelling presentation deleted authorized expanded plan commands")
	for label: Label3D in session.world._drill_labels: check(not label.visible, "Cancelling the preview left an owned badge visible")
	session._action({"action": "start", "mission": "T01", "seed": 7401})
	check(session.world._drill_preview.is_empty() and session.world._drill_labels.is_empty() and session.selected_units == ["alpha"] and session.drag.is_empty(), "Mission load retained the previous drill/group presentation")
