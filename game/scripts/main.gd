extends Node
## Browser input, simulation clock and application state. Game rules live in Simulation.

const MissionCatalog = preload("res://scripts/mission_catalog.gd")
const Simulation = preload("res://scripts/simulation.gd")
const World = preload("res://scripts/world_view.gd")
const Replay = preload("res://scripts/replay.gd")
const PresentationState = preload("res://scripts/presentation_state.gd")
const MovementAudio = preload("res://scripts/movement_audio.gd")
const EquipmentCatalog = preload("res://scripts/equipment_catalog.gd")
const RoomControl = preload("res://scripts/room_control.gd")
const Formation = preload("res://scripts/formation_drill.gd")
const PriorAttempt = preload("res://scripts/prior_attempt.gd")
const STEP: float = 1.0 / 30.0
const BUILD_ID: String = "0.1.0"
const COMMAND_TYPES: Array[String] = ["MOVE", "FACE", "WAIT", "OPEN_DOOR", "OPEN_AND_FLASH", "KICK_DOOR", "PEEK_DOOR", "PEEK_CAMERA", "BREACH_DOOR", "SHOTGUN_BREACH", "SWITCH_WEAPON", "RELOAD", "THROW_STUN", "THROW_SMOKE", "THROW_FRAG", "WAIT_FOR_SIGNAL", "SECURE_CIVILIAN", "ARREST", "CANCEL_PENDING"]
const DRAG_THRESHOLD: float = 6.0
## RD (plan 2-2 조작 탭 / bridge `bindings`): action -> DOM KeyboardEvent.code
## string, matching web/app.js's DEFAULT_BINDINGS exactly so a fresh settings
## payload (or none at all) reproduces the current F/R defaults. "face" and
## "reload" keep their pre-existing physical keys; move/door/equipment/
## secure/wait/signal had no dedicated key before and now default to the
## bridge contract's Q/E/G/C/T/Z.
const DEFAULT_BINDINGS: Dictionary = {"face": "KeyF", "reload": "KeyR", "move": "KeyQ", "door": "KeyE", "equipment": "KeyG", "secure": "KeyC", "wait": "KeyT", "signal": "KeyZ"}
## Reserved physical keys the plan forbids rebinding onto (WASD camera pan,
## Space toggle, Esc, 1-4 unit select, Home camera reset). Matches web's
## RESERVED_CODES plus Home, which the web list omits but the orchestration
## brief explicitly reserves.
const RESERVED_KEYCODES: Array[int] = [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_ESCAPE, KEY_1, KEY_2, KEY_3, KEY_4, KEY_HOME]
## M3 fix: the exact whitelist of DOM KeyboardEvent.code strings a bindings
## payload may use -- every letter except WASD, Digit0 plus Digit5-9 (1-4 are
## reserved for unit select), and the punctuation Godot can map. Every one of
## these codes maps to a real keycode via dom_code_to_keycode above.
const ALLOWED_BINDING_CODES: Array[String] = [
	"KeyB", "KeyC", "KeyE", "KeyF", "KeyG", "KeyH", "KeyI", "KeyJ", "KeyK", "KeyL", "KeyM",
	"KeyN", "KeyO", "KeyP", "KeyQ", "KeyR", "KeyT", "KeyU", "KeyV", "KeyX", "KeyY", "KeyZ",
	"Digit0", "Digit5", "Digit6", "Digit7", "Digit8", "Digit9",
	"Comma", "Period", "Semicolon", "Quote", "BracketLeft", "BracketRight", "Minus", "Equal", "Backquote",
]
## DOM KeyboardEvent.code -> Godot physical keycode, covering every code a
## settings.bindings payload may legally contain (letters + digit row). A
## static pure function so the headless bindings test can exercise it without
## a live keyboard or DOM layer.
static func dom_code_to_keycode(code: String) -> int:
	if code.begins_with("Key") and code.length() == 4:
		var letter: String = code.substr(3, 1)
		if letter.length() == 1 and letter >= "A" and letter <= "Z":
			return KEY_A + (letter.unicode_at(0) - "A".unicode_at(0))
	if code.begins_with("Digit") and code.length() == 6:
		var digit: String = code.substr(5, 1)
		if digit.length() == 1 and digit >= "0" and digit <= "9":
			return KEY_0 + (digit.unicode_at(0) - "0".unicode_at(0))
	match code:
		"Space": return KEY_SPACE
		"Escape": return KEY_ESCAPE
		"Home": return KEY_HOME
		"Tab": return KEY_TAB
		"Backquote": return KEY_QUOTELEFT
		"Minus": return KEY_MINUS
		"Equal": return KEY_EQUAL
		"Semicolon": return KEY_SEMICOLON
		"Quote": return KEY_APOSTROPHE
		"Comma": return KEY_COMMA
		"Period": return KEY_PERIOD
		"Slash": return KEY_SLASH
		"Backslash": return KEY_BACKSLASH
		"BracketLeft": return KEY_BRACKETLEFT
		"BracketRight": return KEY_BRACKETRIGHT
	return KEY_NONE

var sim: RefCounted
var world: Node3D
var recorder: RefCounted
var mode: String = "MENU"
var selected: String = "alpha"
var selected_units: Array[String] = ["alpha"]
var tool: String = "select"
var _formation_hover_cache: Dictionary = {}
var _formation_hover_target: Array = []
var mission_id: String = "T01"
var accumulator: float = 0.0
var hud_elapsed: float = 0.0
var shown: Dictionary = {}
var maps: Dictionary = {}
var js_ui: JavaScriptObject
var js_callback: JavaScriptObject
var replay_time: float = 0.0
var replay_playing: bool = false
var replay_speed: float = 1.0
var replay_reveal: bool = false
var replay_follow: String = ""
## See the REPLAY branch of the tick loop: captured before replay_playing can
## flip to false partway through a frame, so the frame where playback
## reaches the end still dispatches sound/fx for events at that exact
## timestamp (e.g. mission_end) instead of silently skipping them.
var replay_dispatch_eligible: bool = false
var last_event_seq: int = 0
## Plan 2-1 combat fx (web bridge {type:'fx',...}): a separate seq cursor from
## last_event_seq so sound and fx dispatch can evolve independently, but reset
## at the exact same points (mission load, replay restart, replay seek) so
## neither replays stale history.
var last_fx_seq: int = 0
## H1 fix: room geometry only, computed once per mission load from the room
## rects (no enemy membership here -- which enemies "belong" to a room is
## never known from spawn position, only from where the player has actually
## observed them, computed fresh at check time against the live/replay
## state). room_id -> {"rect": Rect2, "name": String, "pos": Vector2}.
var _fx_room_map: Dictionary = {}
## room_id -> bool, whether the room_clear fx already fired for this room
## this playthrough.
var _fx_room_cleared: Dictionary = {}
var _fx_room_clear_seq: Dictionary = {}
## Running set of enemy ids confirmed INCAPACITATED/ARRESTED, built up in
## event order inside _dispatch_fx (M4 fix: this, not a snapshot of
## state.enemies statuses at the end of the current frame, is what
## room_clear is evaluated against, so batching multiple deaths into one
## frame -- e.g. a 4x replay -- cannot change which event the stamp fires on).
var _fx_neutralized_ids: Dictionary = {}
var _fx_last_hit_shot: Dictionary = {}
var _fx_unit_hp: Dictionary = {}
var _fx_unit_shot_damage: Dictionary = {}
var _fx_frag_pending: Array = []
var _web_react_until := -1.0
var _web_presentation_time := 0.0
# Keep aligned with world_view.gd TRACER_TRAVEL, without a runtime dependency.
const HIT_REACTION_DELAY := 0.05
var result_saved: bool = false
var settings: Dictionary = {"fov": true, "line_width": 1.0, "screen_shake": true, "palette": "default", "language": "ko", "auto_pause_man_down": false, "bindings": DEFAULT_BINDINGS.duplicate()}
## action -> Godot physical keycode, rebuilt from settings.bindings by
## _rebuild_bindings() whenever a "settings" message arrives. _unhandled_input
## reverse-looks-up the pressed physical_keycode against this each frame.
var _binding_keycodes: Dictionary = {}
## Plan 2-3 `ui_focus` bridge contract: true while a DOM menu/overlay owns
## input. Gamepad input is ignored entirely while this is true; keyboard/mouse
## already have their own `input_focus`/`keyboard_blocked` gate.
var ui_focus_active: bool = false
## Virtual map cursor driven by the gamepad left stick (plan 2-3), in world
## (ground-plane) coordinates. Only meaningful/drawn while a joypad is
## connected and has been moved at least once.
var gamepad_cursor: Vector2 = Vector2.ZERO
var gamepad_cursor_active: bool = false
## Equipment-key cycle order for the "equipment" binding (plan 2-2): repeated
## presses step through the same three throwables the web's equipment
## submenu offers, since there is no DOM submenu to open on the engine side.
const EQUIPMENT_CYCLE: Array[String] = ["stun", "smoke", "breach"]
const GAMEPAD_DEADZONE: float = 0.25
const GAMEPAD_CURSOR_SPEED: float = 7.0
const GAMEPAD_ZOOM_SPEED: float = 1.6
## Plan 2-3 게임패드 button layout. A pure lookup (static, no device access)
## so the headless test can exercise every mapping without a connected pad.
## Godot's JOY_BUTTON_* constants already match the standard SDL/XInput
## layout the plan describes (A/B/X/Y, LB/RB, Back/Start).
const GAMEPAD_BUTTON_ACTIONS: Dictionary = {
	JOY_BUTTON_A: "move_to_cursor", JOY_BUTTON_B: "cancel_tool",
	JOY_BUTTON_X: "door_at_cursor", JOY_BUTTON_Y: "equipment_at_cursor",
	JOY_BUTTON_LEFT_SHOULDER: "cycle_prev", JOY_BUTTON_RIGHT_SHOULDER: "cycle_next",
	JOY_BUTTON_START: "toggle_execute", JOY_BUTTON_BACK: "pause_menu",
}

static func gamepad_action_for_button(button_index: int) -> String:
	return str(GAMEPAD_BUTTON_ACTIONS.get(button_index, ""))
var ui_inbox: Array[Dictionary] = []
var recorded_limit_notice: bool = false
var initial_plan: Dictionary = {}
var presentation: RefCounted = PresentationState.new()
var movement_audio: RefCounted = MovementAudio.new()
var lab: Node3D
var keyboard_blocked: bool = false
var js_quality: JavaScriptObject
var quality_pending: Array[String] = []
var quality_rendered: Array[String] = []
var mission_options: Dictionary = {}
var active_mission: Dictionary = {}
var custom_maps: Dictionary = {}
var selected_command: int = -1
var door_mode: String = "OPEN_DOOR"
var door_fallback: String = ""
var tool_insert_index: int = -1
var tool_origin: Array = []
var context_open: bool = false
var drag: Dictionary = {}
var camera_drag_button: int = 0
var camera_drag_position := Vector2.ZERO
var hover: Dictionary = {}
var _door_wall_info: Dictionary = {}
var _last_hover_key: String = ""
## menu_focus debounce: rebuilding the diorama's static geometry via
## _load_mission is not cheap (hundreds of ms), so rapid successive requests
## (e.g. hovering across a mission list) must not each trigger a rebuild.
## Instead of gating on time-since-last-switch (which the rebuild cost itself
## can satisfy), we wait for requests to go quiet for MENU_FOCUS_DEBOUNCE_MS
## before actually switching, coalescing a burst into a single rebuild.
const MENU_FOCUS_DEBOUNCE_MS: int = 350
var _menu_focus_pending_id: String = ""
var _menu_focus_requested_ms: int = -1
const LOADING_ACTIONS := ["start", "preview", "retry", "retry_plan", "load_plan", "import_replay", "replay", "custom_mission", "import_mission", "lab"]
var _loading_request: Dictionary = {}
var _loading_frame: int = 0
var _loading_id: String = ""
var _loading_finished: bool = false
var _loading_sequence: int = 0
var _state_batch_depth: int = 0
var _state_pending: bool = false
var _shown_dirty: bool = true
var _shown_sim: RefCounted
var _shown_tick: int = -1
var _shown_time: float = -1.0
var _shown_reveal: bool = false
var _replay_sample_time: float = -1.0
var _replay_sample_reveal: bool = false
var _replay_sample_recorder: RefCounted
var _replay_sample_revision: int = -1
var _replay_seek_pending: bool = false
var _replay_reset_neutralized_ids: Array = []
var prior_attempt: Dictionary = {}
var prior_attempt_visible: bool = true
const IDLE_FPS := 20
const IDLE_DELAY := 1.0
var _render_quiet := 0.0
var _render_signature: Variant = null
var _render_last_shown: Dictionary = {}
var _render_revision := 0
var _active_max_fps: int = 0
var _applied_max_fps: int = 0

func _ready() -> void:
	_active_max_fps = Engine.max_fps
	_applied_max_fps = Engine.max_fps
	get_viewport().size_changed.connect(_wake_render)
	# Command gestures need the original key/mouse order, including F + click
	# and Escape + release arriving between two rendered frames.
	Input.use_accumulated_input = false
	_rebuild_bindings()
	maps = MissionCatalog.missions()
	if not maps.has("T01") or not maps.has("M01"):
		push_error("Mission data missing or invalid")
		return
	sim = Simulation.new()
	recorder = Replay.new()
	world = World.new()
	add_child(world)
	_load_mission("T01", false)
	if OS.has_feature("web"):
		js_ui = JavaScriptBridge.get_interface("BreachUI")
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface("BreachBridge")
		# Diagnostics are opt-in. Godot logs an error when get_interface is used
		# for a missing global, so normal play must not probe that interface.
		if bridge != null and bool(bridge.qualityEnabled):
			js_quality = JavaScriptBridge.get_interface("BreachQuality")
		js_callback = JavaScriptBridge.create_callback(_on_web_message)
		if bridge != null:
			bridge.send = js_callback
		_emit({"type": "ready", "build": BUILD_ID, "catalog": _public_catalog(), "briefings": MissionCatalog.briefings(maps)})
	else:
		mode = "PLANNING"
	_send_state()

func _process(delta: float) -> void:
	_state_batch_depth += 1
	_advance_frame(delta)
	_end_state_batch()
	_update_idle_throttle(delta)

func _set_render_limit(limit: int) -> void:
	# Preserve the configured cap, including changes made while throttled.
	if Engine.max_fps != _applied_max_fps:
		_active_max_fps = Engine.max_fps
	_applied_max_fps = mini(_active_max_fps, limit) if limit > 0 and _active_max_fps > 0 else (limit if limit > 0 else _active_max_fps)
	Engine.max_fps = _applied_max_fps

func _wake_render() -> void:
	_render_quiet = 0.0
	_set_render_limit(0)

func _input(_event: InputEvent) -> void:
	_wake_render()

func _exit_tree() -> void:
	_set_render_limit(0)

func _update_idle_throttle(delta: float) -> void:
	if not _loading_request.is_empty() or _loading_finished or not ui_inbox.is_empty() or not quality_pending.is_empty():
		_wake_render()
		return
	if mode == "MENU":
		_render_quiet = 0.0
		_set_render_limit(30)
		return
	if not mode in ["PLANNING", "RESULT", "REPLAY"] or (mode == "REPLAY" and replay_playing) or world == null:
		_wake_render()
		return
	# Snapshots are replaced on refresh/seek; actions/input revise in-place edits
	# (including settings). Never walk the snapshot just to detect idle changes.
	# Camera changes include held-key/stick pan, zoom, follow and effect motion.
	# Other combat effects age on the frozen presentation clock, not real delta.
	var signature: int = hash([mode, _render_revision, _shown_dirty, recorder.content_revision, selected, selected_units, tool, replay_time, replay_reveal,
		world.camera.global_transform, world.camera.size, get_viewport().get_visible_rect().size, gamepad_cursor])
	if not is_same(shown, _render_last_shown) or signature != _render_signature or world._shake_remaining > 0.0 or world._freeze_remaining > 0.0:
		_render_last_shown = shown
		_render_signature = signature
		_wake_render()
		return
	_render_quiet += maxf(0.0, delta)
	_set_render_limit(IDLE_FPS if _render_quiet >= IDLE_DELAY else 0)

func _advance_frame(delta: float) -> void:
	if sim == null:
		return
	# JavaScript callbacks queue intentions; no re-entrant game mutation during serialization.
	if _loading_finished:
		_loading_finished = false
		_emit({"type":"loading", "active":false, "id":_loading_id})
		_loading_id = ""
		delta = 0.0 # Loading time must not become simulation catch-up time.
	_flush_inputs(true)
	if not _loading_request.is_empty(): return
	if not _menu_focus_pending_id.is_empty():
		if mode != "MENU" or _menu_focus_pending_id == mission_id:
			_menu_focus_pending_id = ""
		elif Time.get_ticks_msec() - _menu_focus_requested_ms >= MENU_FOCUS_DEBOUNCE_MS:
			var settled_id := _menu_focus_pending_id
			_menu_focus_pending_id = ""
			_queue_loading({"action":"preview", "mission":settled_id})
			return
	if mode == "LAB" and is_instance_valid(lab):
		lab.tick(delta)
		_quality_render_complete()
		hud_elapsed += delta
		if hud_elapsed >= 0.1:
			hud_elapsed = 0.0
			_send_state()
		return
	if mode == "EXECUTING":
		accumulator += minf(delta, 0.12)
		while accumulator >= STEP and mode == "EXECUTING":
			accumulator -= STEP
			sim.step(STEP)
			var snapshots: Dictionary = sim.snapshot_pair()
			var tick_events: Array = sim.take_record_events()
			recorder.capture(snapshots.record, tick_events)
			shown = snapshots.observed
			_remember_shown()
			presentation.capture(shown, RoomControl.filter_observed_call_events(tick_events))
			if bool(shown.get("pause_requested", false)):
				_acknowledge_simulation_pause(shown)
			if not sim.result.is_empty():
				_finish_mission()
			if (sim.time >= 600.0 or recorder.is_partial()) and not recorded_limit_notice:
				recorded_limit_notice = true
				_toast("리플레이 기록 한도에 도달했습니다. 게임은 계속되며 %.1f초까지 부분 기록으로 보관됩니다." % recorder.duration, "warning")
	elif mode == "REPLAY":
		# Captured before replay_playing can flip to false below: the frame
		# where playback reaches the end must still dispatch sound/fx for
		# events that land exactly at that final timestamp (e.g. mission_end),
		# or they are silently skipped because by the time the dispatch gate
		# below runs, replay_playing already reads false.
		replay_dispatch_eligible = replay_playing
		if replay_playing:
			replay_time = minf(replay_time + minf(delta, 0.12) * replay_speed, recorder.duration)
			if replay_time >= recorder.duration:
				replay_playing = false
		_sample_replay()
	else:
		accumulator = 0.0
		_refresh_shown()
	if world != null and not shown.is_empty():
		var render_state: Dictionary
		if mode == "EXECUTING":
			render_state = presentation.sample(accumulator / STEP)
		else:
			# Pause settles at the exact authoritative pose. Replay already samples
			# its own continuous timeline and must not acquire another tick of lag.
			render_state = presentation.settle(shown)
			if mode == "REPLAY":
				render_state["presentation_reset"] = _replay_seek_pending
				render_state["presentation_reset_neutralized_ids"] = _replay_reset_neutralized_ids
				render_state["presentation_event_cursor"] = mini(last_event_seq, last_fx_seq)
				render_state["presentation_events"] = RoomControl.filter_observed_call_events(recorder.events_since(mini(last_event_seq, last_fx_seq), replay_time, replay_reveal)) if replay_dispatch_eligible else []
		render_state["settings"] = settings
		render_state["selected_units"] = selected_units.duplicate()
		render_state["presentation_mode"] = mode
		render_state["presentation_reveal"] = mode == "REPLAY" and replay_reveal
		render_state["presentation_paused"] = mode in ["MENU", "PLANNING", "RESULT"] or (mode == "REPLAY" and not replay_playing)
		if mode in ["PLANNING", "EXECUTING", "RESULT"] or (mode == "REPLAY" and replay_dispatch_eligible):
			_dispatch_sounds(render_state)
			_dispatch_fx(render_state)
		for contact: Dictionary in movement_audio.collect(render_state, mode == "EXECUTING" or (mode == "REPLAY" and replay_playing)):
			_emit_positional_sound(contact.name, contact.event, contact.point)
		world.display(render_state, selected, mode == "PLANNING", delta)
		_dispatch_feedback_clock(render_state)
		_replay_seek_pending = false
		_quality_render_complete()
		if mode == "REPLAY" and not replay_follow.is_empty():
			_follow_replay_unit()
	if not keyboard_blocked and (not ui_focus_active or mode == "REPLAY") and mode in ["PLANNING", "EXECUTING", "REPLAY"]:
		var direction: Vector2 = Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_W): direction.y -= 1
		if Input.is_physical_key_pressed(KEY_S): direction.y += 1
		if Input.is_physical_key_pressed(KEY_A): direction.x -= 1
		if Input.is_physical_key_pressed(KEY_D): direction.x += 1
		if direction.length_squared() > 0:
			replay_follow = ""
			world.pan(direction.normalized(), delta)
	if world != null:
		if not ui_focus_active and mode in ["PLANNING", "EXECUTING"]:
			_process_gamepad(delta)
		else:
			world.set_gamepad_cursor(gamepad_cursor, false)
	hud_elapsed += delta
	if hud_elapsed >= 0.1:
		hud_elapsed = 0.0
		_send_state()

func _acknowledge_simulation_pause(state: Dictionary) -> void:
	var reason := str(state.get("pause_reason", "command_failure"))
	mode = "PLANNING"
	sim.set("pause_requested", false)
	sim.set("pause_reason", "")
	sim.set("pause_unit_id", "")
	# Keep the casualty/CALL events from the first capture, then replace only
	# the same-tick frame with the controller's acknowledged pause state.
	recorder.capture(sim.snapshot(true), [])
	if reason == "man_down":
		var alive_ids: Array[String] = []
		for unit: Dictionary in sim.units:
			if float(unit.get("hp", 0.0)) > 0.0: alive_ids.append(str(unit.id))
		var surviving_selection: Array[String] = []
		for id: String in selected_units:
			if id in alive_ids: surviving_selection.append(id)
		if selected not in alive_ids: selected = alive_ids[0] if not alive_ids.is_empty() else ""
		if surviving_selection.is_empty() and not selected.is_empty(): surviving_selection.append(selected)
		selected_units.assign(surviving_selection)
		_emit({"type": "toast", "message": _tr("대원이 쓰러져 남은 진입 계획을 재편성하고 정지했습니다."), "i18n_key": "team.man_down_paused", "kind": "warning"})
	else:
		for unit: Dictionary in sim.units:
			for command: Dictionary in unit.get("commands", []):
				if str(command.get("state", "")) == "FAILED":
					selected = str(unit.id)
					selected_units.assign([selected])
					_emit({"type": "command_failed", "unit_id": selected})
		_toast("명령을 완료할 수 없어 정지했습니다. 명령 목록에서 실패 명령을 삭제한 뒤 다시 계획하세요.", "warning")
	shown = sim.snapshot(false)
	_remember_shown()
	_restore_room_drill_preview()
	_restore_formation_preview()

func _load_mission(id: String, play: bool = true, options: Dictionary = {}, prepared_sim: RefCounted = null) -> void:
	_shown_dirty = true
	camera_drag_button = 0
	if not maps.has(id):
		_toast("알 수 없는 임무입니다.", "error")
		return
	var options_error: String = _options_error(options)
	if not options_error.is_empty():
		_toast(options_error, "error")
		return
	_close_lab()
	world.set_operator_preview({}, {})
	# Copy the previous run before begin() replaces its recording. Only owned
	# operator samples enter this planning overlay; NPC records are never read.
	if recorder != null and recorder.duration > 0.0 and not active_mission.is_empty():
		prior_attempt = PriorAttempt.capture(recorder, mission_id, active_mission, active_mission.get("roster", []))
	mission_id = id
	mission_options = _canonical_options(id, options)
	active_mission = _configured_mission(id, mission_options)
	_build_fx_room_map(active_mission)
	if prepared_sim != null:
		sim = prepared_sim
	else:
		sim.load_mission(active_mission)
	sim.configure_team_settings({"auto_pause_man_down": settings.get("auto_pause_man_down", false)})
	active_mission = sim.mission.duplicate(true)
	_build_door_wall_info(active_mission)
	world.build(active_mission)
	if not PriorAttempt.matches(prior_attempt, mission_id, active_mission, active_mission.get("roster", [])):
		prior_attempt = {}
	world.set_prior_attempt(prior_attempt, prior_attempt_visible)
	_formation_hover_cache.clear()
	_formation_hover_target.clear()
	gamepad_cursor = world.bounds() * 0.5
	gamepad_cursor_active = false
	movement_audio.configure(active_mission)
	recorder.begin(active_mission)
	_replay_sample_recorder = null
	recorder.capture(sim.snapshot(true), sim.take_record_events())
	selected = str(sim.units[0].id) if not sim.units.is_empty() else ""
	selected_units.assign([selected] if not selected.is_empty() else [])
	tool = "select"
	door_mode = "OPEN_DOOR"
	door_fallback = ""
	tool_insert_index = -1
	tool_origin = []
	mode = "PLANNING" if play else "MENU"
	accumulator = 0.0
	last_event_seq = 0
	last_fx_seq = 0
	result_saved = false
	recorded_limit_notice = false
	initial_plan = {}
	replay_playing = false
	replay_follow = ""
	selected_command = -1
	context_open = false
	drag.clear()
	hover.clear()
	_last_hover_key = ""
	world.set_interaction({})
	shown = sim.snapshot(false)
	_remember_shown()
	_restore_room_drill_preview()
	_restore_formation_preview()
	presentation.reset(shown)
	_reset_friendly_health(shown)
	_send_state()

func _canonical_options(id: String, options: Dictionary) -> Dictionary:
	var base: Dictionary = maps[id]
	var out: Dictionary = {"seed": _seed_value(options.get("seed", base.get("seed", 42))),
		"variant": str(options.get("variant", base.get("variant", "base"))),
		"modifiers": [], "loadout": {}, "roster": []}
	if options.get("modifiers", []) is Array:
		out.modifiers = options.get("modifiers", []).duplicate(true)
	if options.get("loadout", {}) is Dictionary:
		out.loadout = options.get("loadout", {}).duplicate(true)
	if options.get("roster", []) is Array:
		out.roster = options.get("roster", []).duplicate(true)
	return out

func _public_catalog() -> Dictionary:
	var catalog: Dictionary = {}
	for id: String in maps: catalog[id] = _public_mission(maps[id])
	return catalog

func _public_mission(data: Dictionary) -> Dictionary:
	var public: Dictionary = data.duplicate(true)
	public["enemy_count"] = data.get("enemies", []).size()
	public["civilian_count"] = data.get("civilians", []).size()
	public.erase("enemies")
	public.erase("civilians")
	public.erase("spawns")
	return public

func _configured_mission(id: String, options: Dictionary) -> Dictionary:
	var configured: Dictionary = maps[id].duplicate(true)
	for key: String in ["seed", "variant", "modifiers", "loadout", "roster"]:
		var value: Variant = options.get(key, configured.get(key))
		configured[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return configured

func _seed_value(value: Variant) -> int:
	if _finite(value): return int(value) & 0x7fffffff
	var string_seed: String = str(value).strip_edges()
	if string_seed.is_valid_int(): return int(string_seed) & 0x7fffffff
	# Stable across browser/native platforms, unlike locale or runtime hash APIs.
	var derived: int = 2166136261
	for byte: int in string_seed.to_utf8_buffer():
		derived = ((derived ^ byte) * 16777619) & 0x7fffffff
	return derived

func _options_error(options: Dictionary) -> String:
	var modifiers: Variant = options.get("modifiers", [])
	if not modifiers is Array or modifiers.size() > 4: return "변형 조건 목록이 올바르지 않습니다."
	var seen_modifiers: Dictionary = {}
	for modifier: Variant in modifiers:
		if not modifier is String or not MissionCatalog.MODIFIERS.has(modifier): return "알 수 없는 변형 조건입니다."
		if seen_modifiers.has(modifier): return "변형 조건이 중복되었습니다."
		seen_modifiers[modifier] = true
	var loadout: Variant = options.get("loadout", {})
	if not loadout is Dictionary or loadout.size() > 8: return "장비 목록이 올바르지 않습니다."
	for id: Variant in loadout:
		var choice: Variant = loadout[id]
		if not id is String or not choice is Dictionary: return "대원별 장비 정보가 올바르지 않습니다."
		var gear_error: String = EquipmentCatalog.loadout_error(choice)
		if not gear_error.is_empty(): return gear_error
	var roster: Variant = options.get("roster", [])
	if not roster is Array or roster.size() > 4: return "대원 명부는 최대 4명입니다."
	var ids: Dictionary = {}
	for member: Variant in roster:
		if not member is Dictionary or not member.get("id") is String or not member.get("base_id", member.get("id")) is String: return "대원 명부 정보가 올바르지 않습니다."
		var id: String = str(member.id)
		if not _identifier(id) or ids.has(id): return "대원 명부의 ID가 중복되거나 올바르지 않습니다."
		ids[id] = true
		if not member.get("name", id) is String or str(member.get("name", id)).length() > 128: return "대원 이름이 올바르지 않습니다."
		if not str(member.get("trait", "")) in ["", "breacher", "marksman", "cautious", "rescuer"]: return "알 수 없는 대원 특성입니다."
	return ""

func _on_web_message(args: Array) -> void:
	_wake_render()
	if args.is_empty() or not args[0] is String:
		return
	var serialized: String = args[0]
	if serialized.length() > 21 * 1024 * 1024:
		_toast("파일 크기가 20MB 제한을 초과했습니다.", "error")
		return
	var parsed: Variant = JSON.parse_string(serialized)
	if parsed is Dictionary and ui_inbox.size() < 64:
		ui_inbox.append(parsed)

func _queue_loading(intent: Dictionary) -> void:
	_wake_render()
	_loading_sequence += 1
	_loading_id = str(intent.get("_loading_id", "engine-%d" % _loading_sequence))
	_loading_request = intent
	_loading_frame = Engine.get_process_frames() + 2
	_menu_focus_pending_id = ""
	camera_drag_button = 0
	_release_camera_keys()
	_emit({"type":"loading", "active":true, "id":_loading_id, "action":intent.get("action", "start")})

func _flush_inputs(allow_loading_work: bool = false) -> void:
	if _loading_finished: return
	if not _loading_request.is_empty():
		# Only process-loop frames may do expensive work. Pointer/keyboard
		# callbacks also flush intentions, but must not bypass the paint gap.
		if not allow_loading_work or Engine.get_process_frames() < _loading_frame: return
		var intent := _loading_request
		_loading_request = {}
		_action(intent)
		_loading_finished = true # Complete on the next frame, after world.display.
		return
	# UI state callbacks may enqueue more intentions; keep this flush bounded
	# to the batch present on entry, as before scene loading was deferred.
	var pending_count := ui_inbox.size()
	for i in range(pending_count):
		var intent: Dictionary = ui_inbox.pop_front()
		if str(intent.get("action", "")) in LOADING_ACTIONS:
			_queue_loading(intent)
			return
		_action(intent)

func _action(data: Dictionary) -> void:
	_render_revision += 1
	_wake_render()
	_shown_dirty = true
	_state_batch_depth += 1
	_apply_action(data)
	_end_state_batch()

func _end_state_batch() -> void:
	_state_batch_depth -= 1
	if _state_batch_depth == 0 and _state_pending:
		_state_pending = false
		_send_state()

func _apply_action(data: Dictionary) -> void:
	_quality_track(str(data.get("_quality_token", "")))
	var action: String = str(data.get("action", ""))
	match action:
		"input_focus":
			keyboard_blocked = bool(data.get("blocked", false))
			if keyboard_blocked:
				_release_camera_keys()
				camera_drag_button = 0
			return
		"escape":
			if not keyboard_blocked and mode in ["PLANNING", "EXECUTING", "REPLAY"]: _escape()
		"lab":
			if mode != "MENU": return
			world.set_operator_preview({}, {})
			world.hide()
			lab = preload("res://scripts/presentation_lab.gd").new()
			add_child(lab)
			mode = "LAB"
		"lab_control":
			if mode == "LAB" and is_instance_valid(lab): lab.configure(data)
		"start":
			_load_mission(str(data.get("id", data.get("mission", "T01"))), true, data)
			_emit({"type": "sound", "name": "select"})
		"custom_mission", "import_mission":
			var custom: Dictionary = _register_custom(data.get("data"))
			if not custom.is_empty(): _load_mission(str(custom.id), true, data)
		"editor_catalog":
			if mode == "MENU": _emit({"type": "editor_catalog", "catalog": maps.duplicate(true)})
		"preview_operator":
			if mode not in ["MENU", "RESULT"]: return
			var profile: Variant = data.get("profile")
			if profile == null:
				world.set_operator_preview({}, {})
			elif profile is Dictionary:
				var gear_error: String = EquipmentCatalog.loadout_error(profile)
				var preview_rect: Variant = data.get("rect", {})
				if not preview_rect is Dictionary: return
				for key: Variant in preview_rect:
					if key not in ["x", "y", "width", "height"] or not _finite(preview_rect[key]) or absf(float(preview_rect[key])) > 32768.0: return
				if gear_error.is_empty(): world.set_operator_preview(EquipmentCatalog.resolve_loadout(profile), preview_rect)
				else: _toast(gear_error, "warning")
		"preview":
			if mode == "MENU": _load_mission(str(data.get("id", data.get("mission", "T01"))), false, data)
		"menu_focus":
			# Switch the menu diorama to another mission's map through the same
			# already-static preview path as "preview" above (no sim step, no
			# replay recording beyond the initial capture). Record the request
			# and let it settle in _process() (see MENU_FOCUS_DEBOUNCE_MS)
			# instead of rebuilding immediately, so a burst of rapid requests
			# only pays for one rebuild once input quiets down.
			if mode == "MENU":
				# M1: primary contract shape is data.data.mission_id; also
				# accept a legacy top-level mission_id/id for robustness.
				var focus_payload: Dictionary = data.get("data", {}) if data.get("data", {}) is Dictionary else {}
				var focus_id: String = str(focus_payload.get("mission_id", focus_payload.get("id", data.get("mission_id", data.get("id", "")))))
				if maps.has(focus_id) and focus_id != mission_id:
					_menu_focus_pending_id = focus_id
					_menu_focus_requested_ms = Time.get_ticks_msec()
		"toggle": _toggle()
		"pause":
			if mode == "EXECUTING":
				mode = "PLANNING"
				accumulator = 0.0
			if mode == "REPLAY": replay_playing = false
		"select": _select(str(data.get("unit_id", data.get("id", ""))), bool(data.get("extend", false)), bool(data.get("preserve_group", false)))
		"select_command":
			if data.has("unit_id"): _select(str(data.unit_id), false, true)
			_select_waypoint(int(data.get("index", -1)))
		"context_close": _close_context()
		"tool":
			if data.has("unit_id"): _select(str(data.unit_id), false, true)
			var requested: String = str(data.get("tool", "select"))
			var changing_face_mode: bool = tool in ["face", "face_lock"] and requested in ["face", "face_lock"] and not data.has("index")
			if requested != tool: _clear_formation_preview()
			if requested in ["select", "pan", "move", "face", "face_lock", "flash_target", "door", "stun", "smoke", "frag", "breach", "secure", "escort", "arrest", "formation"] and (requested != "formation" or mode == "PLANNING"):
				tool = requested
				if requested == "formation" and is_instance_valid(world): world.set_room_drill_preview({})
			if not changing_face_mode:
				tool_insert_index = int(data.get("index", -1)) if requested in ["face", "face_lock", "flash_target"] else -1
				tool_origin = data.get("origin", []).duplicate() if data.get("origin", []) is Array else []
			var requested_door: String = str(data.get("door_mode", "OPEN_DOOR"))
			if requested_door in ["OPEN_DOOR", "OPEN_AND_FLASH", "KICK_DOOR", "PEEK_DOOR", "PEEK_CAMERA", "BREACH_DOOR", "SHOTGUN_BREACH"]: door_mode = requested_door
			door_fallback = "breach" if door_mode == "KICK_DOOR" and str(data.get("door_fallback", "")) == "breach" else ""
			_close_context()
		"command":
			_close_context()
			if data.has("unit_id"): _select(str(data.unit_id), false, true)
			if data.get("args", {}) is Dictionary:
				_issue(str(data.get("type", "")), data.get("args", {}), true)
		"insert":
			_close_context()
			if data.has("unit_id"): _select(str(data.unit_id), false, true)
			if _can_edit() and data.get("args", {}) is Dictionary:
				_command_response(sim.insert_command(selected, int(data.get("index", -1)), str(data.get("type", "")), data.get("args", {})))
		"update":
			_close_context()
			if data.has("unit_id"): _select(str(data.unit_id), false, true)
			if _can_edit() and data.get("args", {}) is Dictionary:
				_command_response(sim.update_command_args(selected, int(data.get("index", -1)), data.get("args", {})))
		"unit_posture":
			if data.has("unit_id"): _select(str(data.unit_id), false, true)
			if _can_edit() and data.get("settings", {}) is Dictionary:
				_command_response(sim.configure_unit(selected, data.get("settings", {})))
		"unlock_facing":
			if _can_edit(): sim.unlock_facing(selected)
		"clear":
			if _can_edit():
				sim.cancel_pending(selected)
				_select_waypoint(-1)
		"remove":
			if data.has("unit_id"): _select(str(data.unit_id), false, true)
			if _can_edit():
				sim.remove_command(selected, int(data.get("index", -1)))
				_select_waypoint(-1)
		"reorder":
			if data.has("unit_id"): _select(str(data.unit_id), false, true)
			if _can_edit():
				sim.reorder_command(selected, int(data.get("index", -1)), int(data.get("direction", 0)))
				_select_waypoint(-1)
		"room_drill_preview", "room_drill":
			_room_drill_action(data)
		"formation_preview", "formation":
			_formation_action(data)
		"sync_delay":
			if mode == "PLANNING" and _finite(data.get("delay_ticks")) and float(data.delay_ticks) == floorf(float(data.delay_ticks)):
				_command_response(sim.update_room_drill_delay(str(data.get("sync_id", "")), int(data.delay_ticks)))
		"signal":
			if mode in ["PLANNING", "EXECUTING"] and str(data.get("channel", "")) in ["A", "B", "C"]:
				var response: Dictionary = sim.release_signal(str(data.channel), str(data.get("sender_id", "")))
				if not bool(response.get("ok", false)): _command_response(response)
		"retry": _load_mission(mission_id, true, mission_options)
		"retry_plan":
			if mode in ["PLANNING", "EXECUTING", "RESULT", "REPLAY"] and not initial_plan.is_empty():
				_import_plan(initial_plan.duplicate(true), false)
		"menu":
			_clear_formation_preview()
			_cancel_drag()
			_close_context()
			_close_lab()
			mode = "MENU"
			replay_playing = false
			tool = "select"
		"replay":
			if mode == "RESULT" or (mode == "REPLAY" and recorder.duration > 0):
				_start_replay()
		"replay_toggle":
			if mode == "REPLAY": _toggle()
		"replay_seek":
			var requested_time: Variant = data.get("time")
			if data.has("tick"):
				if not _finite(data.tick) or float(data.tick) != floorf(float(data.tick)) or float(data.tick) < 0.0 or float(data.tick) > floorf(recorder.duration / STEP + 0.00001): return
				requested_time = float(data.tick) * STEP
			if mode == "REPLAY" and _finite(requested_time):
				_emit({"type": "fx_reset"})
				_web_react_until = -1.0
				movement_audio.reset()
				_replay_seek_pending = true
				replay_time = clampf(float(requested_time), 0.0, recorder.duration)
				if data.has("tick"): replay_playing = false
				last_event_seq = 2147483647
				last_fx_seq = 2147483647
				_sample_replay()
				_replay_reset_neutralized_ids = shown.get("neutralized_ids", []).duplicate(false)
				_reset_event_cursor(shown)
				_reset_fx_cursor(shown)
		"prior_attempt_visible":
			if mode == "PLANNING" and data.get("value") is bool:
				prior_attempt_visible = data.value
				world.set_prior_attempt(prior_attempt, prior_attempt_visible)
		"replay_speed":
			var speed: float = float(data.get("speed", 1))
			if speed in [0.5, 1.0, 2.0, 4.0]: replay_speed = speed
		"replay_reveal":
			if mode == "REPLAY": replay_reveal = bool(data.get("value", false))
		"replay_follow": replay_follow = str(data.get("id", ""))
		"export_replay":
			if mode in ["RESULT", "REPLAY"]:
				_emit_replay_data("export")
		"import_replay":
			_import_replay(data.get("data"))
		"get_plan":
			if mode in ["PLANNING", "EXECUTING"]:
				var plan: Dictionary = _export_plan() if sim.time <= 0.0 else initial_plan
				_emit({"type": "plan_data", "data": plan})
				if sim.time > 0.0:
					_toast("임무 시작 전 초기 계획을 저장합니다. 진행 중 상태는 리플레이에 기록됩니다.")
		"load_plan": _import_plan(data.get("data"))
		"settings":
			if data.get("settings") is Dictionary:
				var incoming: Dictionary = data.settings
				settings["fov"] = bool(incoming.get("fov", true))
				settings["line_width"] = clampf(float(incoming.get("line_width", 1.0)), 1.0, 2.0)
				settings["reduced_motion"] = bool(incoming.get("reduced_flash", false))
				settings["reduced_flash"] = bool(incoming.get("reduced_flash", false))
				settings["screen_shake"] = bool(incoming.get("screen_shake", true))
				settings["palette"] = str(incoming.get("palette", "default")) if str(incoming.get("palette", "default")) in ["default", "deutan", "protan", "tritan"] else "default"
				settings["language"] = str(incoming.get("language", "ko")) if str(incoming.get("language", "ko")) in ["ko", "en"] else "ko"
				settings["bindings"] = _validated_bindings(incoming.get("bindings", {}))
				if incoming.has("auto_pause_man_down"):
					if incoming.auto_pause_man_down is bool:
						settings["auto_pause_man_down"] = incoming.auto_pause_man_down
						if sim != null: sim.configure_team_settings({"auto_pause_man_down": incoming.auto_pause_man_down})
					else:
						_emit({"type": "toast", "message": _tr("팀 설정이 올바르지 않습니다."), "i18n_key": "team.invalid_settings", "kind": "warning"})
				_rebuild_bindings()
		"ui_focus":
			# M1 fix: the bridge contract nests `active` under `data.data`
			# like every other action's payload; also accept the legacy
			# top-level shape (what the web currently sends) for robustness.
			var focus_data: Dictionary = data.get("data", {}) if data.get("data", {}) is Dictionary else {}
			ui_focus_active = bool(focus_data.get("active", data.get("active", false)))
			if ui_focus_active: camera_drag_button = 0
		"cancel_camera_drag": camera_drag_button = 0
		"reset_camera":
			replay_follow = ""
			camera_drag_button = 0
			world.reset_camera()
		"set_safe_area":
			if data.get("data") is Dictionary:
				world.set_safe_area(_safe_area_to_viewport_px(data.data))
	_send_state()

## The web layer sends insets in CSS px; convert to viewport px (the units
## get_viewport().get_visible_rect().size is measured in) so the camera fit
## math only ever deals with one unit system.
func _safe_area_to_viewport_px(insets: Dictionary) -> Dictionary:
	var scale := 1.0
	if OS.has_feature("web"):
		var inner_width: Variant = JavaScriptBridge.eval("window.innerWidth", true)
		var viewport_width: float = get_viewport().get_visible_rect().size.x
		if (inner_width is float or inner_width is int) and float(inner_width) > 0.0:
			scale = viewport_width / float(inner_width)
	return {
		"left": float(insets.get("left", 0.0)) * scale,
		"top": float(insets.get("top", 0.0)) * scale,
		"right": float(insets.get("right", 0.0)) * scale,
		"bottom": float(insets.get("bottom", 0.0)) * scale,
	}

## M3 fix: every code must be in the exact ALLOWED_BINDING_CODES whitelist
## (an action left unspecified keeps its default code) and no two actions
## may end up on the same code. Unlike the old per-action fallback -- which
## silently dropped just the offending action to its default, risking a
## result where e.g. an imported {"face":"KeyR"} leaves both face AND reload
## on KeyR -- any invalid code or duplicate anywhere now rejects the WHOLE
## incoming bindings object and keeps every default, never a partial mix.
func _validated_bindings(incoming: Variant) -> Dictionary:
	if not incoming is Dictionary:
		return DEFAULT_BINDINGS.duplicate()
	var merged: Dictionary = {}
	var used: Dictionary = {}
	for action: String in DEFAULT_BINDINGS:
		var code: Variant = incoming.get(action, DEFAULT_BINDINGS[action])
		if not code is String or not ALLOWED_BINDING_CODES.has(code) or used.has(code):
			return DEFAULT_BINDINGS.duplicate()
		merged[action] = code
		used[code] = true
	return merged

func _rebuild_bindings() -> void:
	_binding_keycodes.clear()
	var bindings: Dictionary = settings.get("bindings", DEFAULT_BINDINGS)
	for action: String in DEFAULT_BINDINGS:
		var code: String = str(bindings.get(action, DEFAULT_BINDINGS[action]))
		var keycode: int = dom_code_to_keycode(code)
		if keycode == KEY_NONE: keycode = dom_code_to_keycode(DEFAULT_BINDINGS[action])
		_binding_keycodes[action] = keycode

## Reverse lookup: which bound action (if any) the given physical keycode
## currently triggers.
func _binding_action_for_keycode(keycode: int) -> String:
	for action: String in _binding_keycodes:
		if int(_binding_keycodes[action]) == keycode:
			return action
	return ""

## The "signal" binding releases whichever channel A/B/C has a unit actually
## WAITING on it right now (checked in that order), rather than a fixed
## channel -- there is no DOM submenu on the engine side to ask the player
## which one they mean.
func _next_pending_signal_channel() -> String:
	for channel: String in ["A", "B", "C"]:
		for unit: Dictionary in sim.units:
			for command: Dictionary in unit.get("commands", []):
				if str(command.get("type", "")) == "WAIT_FOR_SIGNAL" and str(command.get("state", "")) == "WAITING" and str(command.get("args", {}).get("signal", "A")) == channel:
					return channel
	return ""

## RD (plan 2-2): dispatches the rebindable actions (everything except the
## reserved WASD/Space/Esc/1-4/Home keys, which _unhandled_input still
## matches directly). Defaults reproduce the pre-existing F=face/R=reload
## behavior; move/door/equipment/secure/wait/signal are new.
func _handle_binding_key(keycode: int) -> void:
	if keyboard_blocked or context_open: return
	var action := _binding_action_for_keycode(keycode)
	if action in ["face", "move", "door", "secure"]: _clear_formation_preview()
	match action:
		"face":
			tool = "face"
			tool_insert_index = -1
			tool_origin = []
		"reload": _issue("RELOAD", {})
		"move": tool = "move"
		"door": tool = "door"
		"equipment": _cycle_equipment_tool()
		"secure": tool = "secure"
		"wait": _issue("WAIT", {})
		"signal":
			var channel: String = _next_pending_signal_channel()
			if not channel.is_empty(): sim.release_signal(channel)
			else: _toast("대기 중인 신호가 없습니다.", "warning")

## Steps through the same stun/smoke/breach throwables the web's equipment
## submenu offers, since the engine has no DOM submenu of its own to open.
func _cycle_equipment_tool() -> void:
	_clear_formation_preview()
	var cycle: Array[String] = _equipment_cycle()
	var index: int = cycle.find(tool)
	tool = cycle[(index + 1) % cycle.size()] if index >= 0 else cycle[0]

func _equipment_cycle() -> Array[String]:
	var cycle: Array[String] = EQUIPMENT_CYCLE.duplicate()
	if str(active_mission.get("roe", "precision")) == "high_intensity": cycle.append("frag")
	return cycle

## RD (plan 2-3): executes the action a gamepad face/shoulder/menu button maps
## to, against the virtual cursor driven by _process_gamepad. Ignored
## entirely while ui_focus_active (a DOM overlay owns input) -- the call site
## in _unhandled_input already gates on that before reaching here.
## M5 fix: Y (equipment_at_cursor) now only cycles to the next equipment
## item -- it used to cycle AND immediately throw/breach in the same press,
## so there was no way to pick an item without also committing to use it. A
## (move_to_cursor) now confirms (throws/breaches) at the cursor when an
## equipment tool is already active, and otherwise moves, matching the
## existing tool UI. A/X/Y (move/door/equipment at cursor) are all ignored
## until the left stick has moved the cursor at least once this mission, so
## a stray press before the player has touched the stick can no longer issue
## a MOVE/throw to the map center where the cursor starts.
func _handle_gamepad_button(button_index: int) -> void:
	var action: String = gamepad_action_for_button(button_index)
	if action in ["move_to_cursor", "door_at_cursor", "equipment_at_cursor"] and not gamepad_cursor_active:
		return
	var screen: Vector2 = world.camera.unproject_position(world.surface_position(gamepad_cursor, 0.7))
	match action:
		"move_to_cursor":
			if tool in EQUIPMENT_CYCLE or tool == "frag":
				match tool:
					"stun": _issue("THROW_STUN", {"target": _point_array(gamepad_cursor)})
					"smoke": _issue("THROW_SMOKE", {"target": _point_array(gamepad_cursor)})
					"frag": _issue("THROW_FRAG", {"target": _point_array(gamepad_cursor)})
					"breach":
						var door_id: String = world.pick_door(screen)
						if not door_id.is_empty(): _issue("BREACH_DOOR", {"door_id": door_id})
			else:
				_issue("MOVE", {"target": _point_array(gamepad_cursor)})
		"cancel_tool":
			_clear_formation_preview()
			tool = "select"
			tool_insert_index = -1
			tool_origin = []
			world.set_interaction({})
		"door_at_cursor":
			var door_id: String = world.pick_door(screen)
			if not door_id.is_empty(): _issue("OPEN_DOOR", {"door_id": door_id})
		"equipment_at_cursor": _cycle_equipment_tool()
		"cycle_prev": _cycle_selected(-1)
		"cycle_next": _cycle_selected(1)
		"toggle_execute": _toggle()
		"pause_menu": _escape()

func _cycle_selected(direction: int) -> void:
	if sim.units.is_empty(): return
	var index: int = 0
	for i: int in range(sim.units.size()):
		if str(sim.units[i].id) == selected:
			index = i
			break
	index = (index + direction + sim.units.size()) % sim.units.size()
	_select(str(sim.units[index].id))

## RD (plan 2-3): left stick moves the virtual map cursor, right stick pans
## the camera, triggers zoom. Polled (not event-driven) like the WASD camera
## pan a few lines above in _process, since analog magnitude needs a
## per-frame delta rather than a discrete press.
func _process_gamepad(delta: float) -> void:
	var pads: Array = Input.get_connected_joypads()
	if pads.is_empty():
		world.set_gamepad_cursor(gamepad_cursor, false)
		return
	var device: int = pads[0]
	var move_axis := Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
	if move_axis.length() > GAMEPAD_DEADZONE:
		gamepad_cursor += move_axis * GAMEPAD_CURSOR_SPEED * delta
		var map_bounds: Vector2 = world.bounds()
		gamepad_cursor.x = clampf(gamepad_cursor.x, 0.0, map_bounds.x)
		gamepad_cursor.y = clampf(gamepad_cursor.y, 0.0, map_bounds.y)
		gamepad_cursor_active = true
	var pan_axis := Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
	if pan_axis.length() > GAMEPAD_DEADZONE: world.pan(pan_axis, delta)
	var zoom_in: float = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)
	var zoom_out: float = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)
	if zoom_in > 0.15: world.zoom(-zoom_in * GAMEPAD_ZOOM_SPEED * delta)
	if zoom_out > 0.15: world.zoom(zoom_out * GAMEPAD_ZOOM_SPEED * delta)
	world.set_gamepad_cursor(gamepad_cursor, gamepad_cursor_active)

func _toggle() -> void:
	_cancel_drag()
	_close_context()
	_clear_formation_preview()
	if mode == "PLANNING":
		if sim.time <= 0.0:
			initial_plan = _export_plan()
			var initial_events: Array = recorder.data.get("events", []).duplicate(false)
			initial_events.append_array(sim.take_record_events())
			recorder.begin(active_mission)
			recorder.capture(sim.snapshot(true), initial_events)
		mode = "EXECUTING"
		tool = "select"
		accumulator = 0.0
		_refresh_shown()
		presentation.reset(shown)
	elif mode == "EXECUTING":
		mode = "PLANNING"
		accumulator = 0.0
	elif mode == "REPLAY":
		if replay_time >= recorder.duration:
			replay_time = 0.0
			_replay_seek_pending = true
			_emit({"type":"fx_reset"})
			last_event_seq = 0
			last_fx_seq = 0
			_reset_fx_rooms()
			_sample_replay()
			_reset_friendly_health(shown)
			_replay_reset_neutralized_ids = shown.get("neutralized_ids", []).duplicate(false)
		replay_playing = not replay_playing

func _select(id: String, extend: bool = false, preserve_group: bool = false) -> void:
	if not id.is_empty():
		var found := false
		for unit: Dictionary in shown.get("units", []):
			if str(unit.id) == id:
				found = true
				break
		if not found: return
	var previous: Array[String] = selected_units.duplicate()
	if id.is_empty():
		selected_units.clear()
	elif extend:
		if selected_units.has(id):
			selected_units.erase(id)
			id = (selected_units.back() if not selected_units.is_empty() else "") if selected == id else selected
		else: selected_units.append(id)
	elif not preserve_group or not selected_units.has(id):
		selected_units.assign([id])
	if selected != id:
		selected_command = -1
		if world != null: world.set_selected_waypoint(id, -1)
	selected = id
	if previous != selected_units and world != null:
		world.set_room_drill_preview({})
		_clear_formation_preview()
	if not id.is_empty(): _emit({"type": "sound", "name": "select"})

func _room_drill_action(data: Dictionary) -> void:
	if str(data.get("action", "")) == "room_drill_preview" and bool(data.get("clear", false)):
		if world != null: world.set_room_drill_preview({})
		_emit({"type": "room_drill_preview", "data": {}, "preview_id": str(data.get("preview_id", ""))})
		return
	if mode != "PLANNING": return
	_clear_formation_preview()
	var order: Array = data.get("order", selected_units) if data.get("order", selected_units) is Array else []
	var options: Dictionary = data.get("options", {}) if data.get("options", {}) is Dictionary else {}
	var preview: Dictionary = sim.room_entry_preview(str(data.get("door_id", "")), str(data.get("method", "OPEN_DOOR")), order, options)
	if world != null: world.set_room_drill_preview(preview if bool(preview.get("ok", false)) else {})
	_emit({"type": "room_drill_preview", "data": preview, "preview_id": str(data.get("preview_id", ""))})
	if str(data.get("action", "")) != "room_drill": return
	if not bool(preview.get("ok", false)):
		_command_response(preview)
		return
	_close_context()
	var response: Dictionary = sim.plan_room_entry(str(data.get("door_id", "")), str(data.get("method", "OPEN_DOOR")), order, options)
	if bool(response.get("ok", false)):
		preview["sync_id"] = str(response.get("sync_id", ""))
		if world != null: world.set_room_drill_preview(preview)
	_command_response(response)

func _clear_formation_preview() -> void:
	_formation_hover_cache.clear()
	_formation_hover_target.clear()
	if is_instance_valid(world): world.set_formation_preview({})

func _formation_action(data: Dictionary) -> void:
	if str(data.get("action", "")) == "formation_preview" and bool(data.get("clear", false)):
		_clear_formation_preview()
		_emit({"type": "formation_preview", "data": {}, "preview_id": str(data.get("preview_id", ""))})
		return
	if mode != "PLANNING": return
	if is_instance_valid(world): world.set_room_drill_preview({})
	if data.has("options") and not data.options is Dictionary:
		_clear_formation_preview()
		var rejected := {"ok": false, "message_key": "formation.error.options", "message": "대형 설정이 올바르지 않습니다"}
		_emit({"type": "formation_preview", "data": rejected, "preview_id": str(data.get("preview_id", ""))})
		if str(data.get("action", "")) == "formation": _command_response(rejected)
		return
	var target: Array = data.get("target", []) if data.get("target", []) is Array else []
	var order: Array = data.get("order", selected_units) if data.get("order", selected_units) is Array else []
	var options: Dictionary = data.get("options", {}) if data.get("options", {}) is Dictionary else {}
	var kind := str(data.get("kind", "AUTO"))
	var preview: Dictionary = sim.formation_preview(target, kind, order, options)
	if is_instance_valid(world): world.set_formation_preview(preview)
	_emit({"type": "formation_preview", "data": preview, "preview_id": str(data.get("preview_id", ""))})
	if str(data.get("action", "")) != "formation": return
	if not bool(preview.get("ok", false)):
		_command_response(preview)
		return
	_close_context()
	var response: Dictionary = sim.plan_formation(target, kind, order, options)
	if bool(response.get("ok", false)):
		preview["sync_id"] = str(response.get("sync_id", ""))
		if is_instance_valid(world): world.set_formation_preview(preview)
		tool = "select"
	_command_response(response)

func _formation_hover(point: Vector2) -> void:
	# Freeze authored/remembered geometry and owned approaches until a plan or
	# observation changes. Cursor motion is pure calculation, with no bridge
	# traffic, command mutation, NPC lookup or simulation step.
	var inputs: Array = [selected_units, int(shown.get("plan_revisions", 0)), shown.get("doors", [])]
	if _formation_hover_cache.get("inputs", []) != inputs:
		var geometry: Dictionary = sim._formation_geometry()
		var planning_nav := Simulation.Navigation.new()
		var planning_doors: Array = geometry.get("doors", [])
		planning_nav.build(geometry, planning_doors)
		var approaches: Dictionary = {}
		for id: String in selected_units:
			var unit: Dictionary = sim._find(sim.units, id)
			if unit.is_empty() or float(unit.get("hp", 0.0)) <= 0.0: continue
			var origin: Dictionary = sim._drill_origin(unit, true, planning_nav, planning_doors)
			if bool(origin.get("ok", false)): approaches[id] = origin.origin.duplicate()
		_formation_hover_cache = {"inputs": inputs.duplicate(true), "geometry": geometry, "approaches": approaches}
		_formation_hover_target.clear()
	var target := _point_array(point)
	if target == _formation_hover_target: return
	_formation_hover_target = target.duplicate()
	var preview: Dictionary = Formation.calculate(_formation_hover_cache.geometry, selected_units, _formation_hover_cache.approaches, target, {"kind": "AUTO"})
	world.set_formation_preview(preview)
	world.set_interaction({})

func _restore_formation_preview() -> void:
	# Expanded primitives are the saved format. Rebuild from owned queues so
	# edited routes, deleted stages and casualties survive import exactly.
	var base := ""
	for unit: Dictionary in shown.get("units", []):
		if str(unit.id) != selected: continue
		for command: Dictionary in unit.get("commands", []):
			var args: Dictionary = command.get("args", {})
			if args.has("formation"): base = str(args.formation.get("sync_id", ""))
			elif args.has("drill"): base = ""
	if base.is_empty() or not is_instance_valid(world): return
	var fallback := {"slots": []}
	for unit: Dictionary in active_mission.get("units", []):
		fallback.slots.append({"unit_id": str(unit.id), "approach": [float(unit.x), float(unit.z)]})
	var preview: Dictionary = World.formation_from_commands(shown, base, fallback)
	if bool(preview.get("ok", false)): world.set_formation_preview(preview)

func _restore_room_drill_preview() -> void:
	# Plan files store only expanded primitives. Reconstruct their presentation
	# from the same static geometry and owned stack targets after a fresh load.
	var base := ""
	for unit: Dictionary in shown.get("units", []):
		if str(unit.id) != selected: continue
		for command: Dictionary in unit.get("commands", []):
			base = str(command.get("args", {}).get("drill", {}).get("sync_id", base))
	if base.is_empty(): return
	var ranked: Array[Dictionary] = []
	var approaches: Dictionary = {}
	var door_id := ""
	var room_id := ""
	var method := "OPEN_DOOR"
	var operator_id := ""
	var go_long := false
	for unit: Dictionary in shown.get("units", []):
		for command: Dictionary in unit.get("commands", []):
			var args: Dictionary = command.get("args", {})
			var drill: Dictionary = args.get("drill", {})
			if str(drill.get("sync_id", "")) != base: continue
			door_id = str(drill.get("door_id", ""))
			room_id = str(drill.get("room_id", ""))
			if command.type == "MOVE" and str(drill.get("stage", "")) == "stack":
				if not approaches.has(unit.id): ranked.append({"id": str(unit.id), "order": int(drill.get("order", 0))})
				approaches[unit.id] = args.target.duplicate()
			elif str(drill.get("stage", "")) == "door":
				method = str(command.type)
				operator_id = str(unit.id)
			elif str(drill.get("stage", "")) == "go_long": go_long = true
	if ranked.size() < 2 or ranked.size() > 4 or operator_id.is_empty(): return
	var known := false
	for door: Dictionary in shown.get("doors", []):
		if str(door.id) == door_id and bool(door.get("observed", false)): known = true
	if not known: return
	if is_instance_valid(world):
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.order) < int(b.order))
		var order: Array = ranked.map(func(slot: Dictionary) -> String: return str(slot.id))
		var preview: Dictionary = Simulation.RoomDrill.calculate(sim._drill_geometry(), door_id, order, approaches, {"method": method, "room_id": room_id, "operator_id": operator_id, "go_long": go_long})
		if bool(preview.get("ok", false)):
			preview["sync_id"] = base
			world.set_room_drill_preview(preview)

func _select_waypoint(index: int) -> void:
	selected_command = index
	world.set_selected_waypoint(selected, index)
	_emit({"type": "waypoint_select", "unit_id": selected, "index": index})

func _command_response(response: Dictionary) -> void:
	_shown_dirty = true
	_formation_hover_cache.clear()
	_formation_hover_target.clear()
	if not bool(response.get("ok", false)):
		var message: String = str(response.get("message", "명령을 등록할 수 없습니다."))
		if int(response.get("accepted", 0)) > 0: message = "%d개 경유점까지 적용했습니다. %s" % [int(response.accepted), message]
		if response.has("message_key"):
			_emit({"type": "toast", "message": _tr(message), "message_key": str(response.message_key), "i18n_key": str(response.message_key), "kind": "warning"})
		else: _toast(message, "warning")
	else:
		_emit({"type": "sound", "name": "order"})
		_command_warning(response)
	_send_state()

func _command_warning(response: Dictionary) -> void:
	if str(response.get("warning", "")) == "breach_safety":
		_emit({"type": "toast", "message": _tr("장약 안전거리 안에 대원이 있습니다. 기폭 전에 팀을 물러나게 하세요."), "kind": "warning", "i18n_key": "door.breach_safety"})

func _can_edit() -> bool:
	if not mode in ["PLANNING", "EXECUTING"]: return false
	if selected.is_empty():
		_toast("먼저 대원을 선택하세요.", "warning")
		return false
	for unit: Dictionary in sim.units:
		if str(unit.id) == selected and float(unit.get("hp", 0)) <= 0:
			_toast("행동 불능 대원에게 명령할 수 없습니다.", "warning")
			return false
	return true

func _issue(type: String, args: Dictionary, append: bool = true) -> void:
	_shown_dirty = true
	if not _can_edit(): return
	if type == "HOLD_AT_DOOR":
		_command_response(sim.plan_hold(selected, args, append))
		return
	if type in ["ESCORT", "ESCORT_CIVILIAN"]: type = "SECURE_CIVILIAN"
	if not type in COMMAND_TYPES:
		_toast("지원하지 않는 명령입니다.", "error")
		return
	var response: Dictionary = sim.plan_move(selected, args, append) if type == "MOVE" else sim.issue(selected, type, args, append)
	if not bool(response.get("ok", false)):
		if type == "THROW_FRAG":
			_command_response(response)
			return
		else: _toast(str(response.get("message", "명령을 등록할 수 없습니다.")), "warning")
	else:
		_emit({"type": "sound", "name": "order"})
		_command_warning(response)
		if type == "OPEN_AND_FLASH":
			for unit: Dictionary in sim.units:
				if str(unit.id) == selected:
					tool_insert_index = unit.get("commands", []).size() - 1
					_select_waypoint(tool_insert_index)
					tool = "flash_target"
					break
	_send_state()

func _unhandled_input(event: InputEvent) -> void:
	_render_revision += 1
	_wake_render()
	_state_batch_depth += 1
	_apply_unhandled_input(event)
	_end_state_batch()

func _apply_unhandled_input(event: InputEvent) -> void:
	# Apply toolbar intentions before a map click, even within one render frame.
	_flush_inputs()
	if not _loading_request.is_empty() or _loading_finished: return
	if world == null or not mode in ["PLANNING", "EXECUTING", "REPLAY"]:
		return
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed and not event.echo):
		if js_quality != null: _quality_track(str(js_quality.latestInputToken))
	if event is InputEventMouseMotion:
		if camera_drag_button != 0:
			if event.button_mask & (1 << (camera_drag_button - 1)):
				world.drag_pan(camera_drag_position, event.position)
				camera_drag_position = event.position
			else:
				camera_drag_button = 0
			return
		if mode != "REPLAY" and not context_open:
			_mouse_motion(event)
		return
	if event is InputEventJoypadButton:
		if ui_focus_active or not event.pressed or context_open or not mode in ["PLANNING", "EXECUTING"]: return
		_shown_dirty = true
		_handle_gamepad_button(event.button_index)
		_send_state()
		return
	if event is InputEventKey:
		if keyboard_blocked or not event.pressed or event.echo: return
		_shown_dirty = true
		if event.physical_keycode == KEY_ESCAPE:
			_escape()
			_send_state()
			return
		if context_open: return
		match event.physical_keycode:
			KEY_SPACE: _toggle()
			KEY_1, KEY_2, KEY_3, KEY_4:
				var index: int = event.physical_keycode - KEY_1
				if index < sim.units.size(): _select(str(sim.units[index].id), event.shift_pressed)
			KEY_DELETE, KEY_BACKSPACE:
				if _can_edit():
					sim.cancel_pending(selected)
					_select_waypoint(-1)
			KEY_HOME:
				replay_follow = ""
				world.reset_camera()
			_:
				_handle_binding_key(event.physical_keycode)
		_send_state()
		return
	if not event is InputEventMouseButton: return
	if not event.pressed:
		if camera_drag_button == event.button_index:
			camera_drag_button = 0
			return
		_mouse_release(event)
		return
	if keyboard_blocked or (ui_focus_active and mode != "REPLAY"): return
	if event.button_index == MOUSE_BUTTON_MIDDLE or (event.button_index == MOUSE_BUTTON_LEFT and (event.alt_pressed or tool == "pan")):
		_close_context()
		_cancel_drag()
		replay_follow = ""
		camera_drag_button = event.button_index
		camera_drag_position = event.position
		return
	if context_open:
		_close_context()
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		world.zoom(-1.0)
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		world.zoom(1.0)
		return
	if mode == "REPLAY":
		if event.button_index == MOUSE_BUTTON_LEFT:
			var replay_unit: String = world.pick_unit(event.position)
			if not replay_unit.is_empty(): _select(replay_unit)
		return
	var point: Vector2 = world.screen_to_ground(event.position)
	if not is_finite(point.x) or not is_finite(point.y): return
	var target: Array = _point_array(point)
	if event.button_index == MOUSE_BUTTON_LEFT and event.shift_pressed:
		var group_unit: String = world.pick_unit(event.position)
		if not group_unit.is_empty():
			_select(group_unit, true)
			_send_state()
			return
	var waypoint: Dictionary = world.pick_waypoint(event.position, selected)
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if not waypoint.is_empty():
			_select_waypoint(int(waypoint.index))
			_arm_drag("face", event, waypoint)
			return
		var hit: Dictionary = _pick_context(event.position, false)
		if not hit.is_empty():
			if str(hit.target) == "unit": _select(str(hit.id))
			_open_context(hit, event.position)
		else:
			_issue("MOVE", {"target": target}, event.shift_pressed)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if tool == "select" and not waypoint.is_empty():
			_select_waypoint(int(waypoint.index))
			_arm_drag("waypoint", event, waypoint)
		elif tool in ["face", "face_lock"]:
			var face_args: Dictionary = {"target": target}
			if tool == "face_lock": face_args["persistent"] = true
			if tool_insert_index >= 0 and _can_edit(): _command_response(sim.insert_command(selected, tool_insert_index, "FACE", face_args))
			else: _issue("FACE", face_args)
			tool = "select"
			tool_insert_index = -1
			tool_origin = []
		elif tool == "flash_target":
			if _can_edit() and not _flash_target_command().is_empty():
				var preview: Dictionary = sim.flash_target_preview(selected, tool_insert_index, target)
				if not bool(preview.get("ok", false)):
					_toast(str(preview.get("message", "투척할 수 없는 위치입니다. 기존 착지점을 유지합니다.")), "warning")
					return
				var flash_args: Dictionary = _flash_target_command().get("args", {}).duplicate(true)
				flash_args["target"] = target
				var response: Dictionary = sim.update_command_args(selected, tool_insert_index, flash_args)
				_command_response(response)
				if bool(response.get("ok", false)):
					tool = "select"
					tool_insert_index = -1
					world.set_interaction({})
			else: _toast("미실행 문·섬광탄 명령을 선택하세요.", "warning")
		elif tool == "move":
			_issue("MOVE", {"target": target})
		elif tool == "formation":
			if mode == "PLANNING":
				# Publish the tool/group acknowledgement before its target so
				# even a fast click can pass the editor's stale-event guard.
				_send_state()
				_emit({"type": "formation_target", "target": target, "order": selected_units.duplicate()})
		elif tool in ["stun", "smoke", "frag"]:
			_issue({"stun": "THROW_STUN", "smoke": "THROW_SMOKE", "frag": "THROW_FRAG"}[tool], {"target": target})
			tool = "select"
			world.set_interaction({})
		elif tool in ["door", "breach"]:
			var door_id: String = world.pick_door(event.position)
			if door_id.is_empty(): _toast("관측한 문을 클릭하세요.", "warning")
			else:
				var door_command: String = "BREACH_DOOR" if tool == "breach" else door_mode
				var door_args: Dictionary = {"door_id": door_id}
				if door_command == "KICK_DOOR" and door_fallback == "breach": door_args["fallback"] = "breach"
				_issue(door_command, door_args)
			tool = "select"
		elif tool in ["secure", "escort"]:
			var civilian_id: String = world.pick_civilian(event.position)
			if civilian_id.is_empty(): _toast("관측한 민간인을 클릭하세요.", "warning")
			else: _issue("SECURE_CIVILIAN", {"civilian_id": civilian_id})
			tool = "select"
		elif tool == "arrest":
			var enemy_id: String = world.pick_enemy(event.position)
			if enemy_id.is_empty(): _toast("관측한 투항 적을 클릭하세요.", "warning")
			else: _issue("ARREST", {"enemy_id": enemy_id})
			tool = "select"
		else:
			var unit_id: String = world.pick_unit(event.position)
			if not unit_id.is_empty():
				_select(unit_id, event.shift_pressed)
				if not event.shift_pressed: _arm_drag("path", event, {"point": _point_array(point)})
			else:
				var door_id: String = world.pick_door(event.position)
				var civilian_id: String = world.pick_civilian(event.position)
				var enemy_id: String = world.pick_enemy(event.position)
				if not door_id.is_empty() and not selected.is_empty():
					_issue("OPEN_DOOR", {"door_id": door_id})
				elif not civilian_id.is_empty() and not selected.is_empty():
					_issue("SECURE_CIVILIAN", {"civilian_id": civilian_id})
				elif not enemy_id.is_empty() and not selected.is_empty():
					_open_context({"target": "enemy", "id": enemy_id}, event.position)
				else: _select("")
	_send_state()

func _point_array(point: Vector2) -> Array:
	return [snappedf(point.x, 0.01), snappedf(point.y, 0.01)]

func _pick_context(screen_pos: Vector2, include_waypoint: bool = true) -> Dictionary:
	if include_waypoint:
		var waypoint: Dictionary = world.pick_waypoint(screen_pos, selected)
		if not waypoint.is_empty(): return {"target": "waypoint", "id": selected, "index": waypoint.index, "point": waypoint.target}
	return world.pick_context(screen_pos)

func _pause_for_edit() -> void:
	if mode == "EXECUTING":
		mode = "PLANNING"
		accumulator = 0.0
		_send_state()

func _open_context(hit: Dictionary, screen_pos: Vector2) -> void:
	if mode == "REPLAY" or not _can_edit(): return
	_pause_for_edit()
	var actions: Dictionary = sim.context_actions(selected, str(hit.get("target", "ground")), str(hit.get("id", "")), int(hit.get("index", -1)))
	if str(hit.get("target", "")) == "door" and not actions.get("actions", []).is_empty() and selected_units.size() >= 2 and selected_units.size() <= 4:
		actions.actions.append("ENTER_ROOM")
	if actions.get("actions", []).is_empty():
		if str(hit.get("target", "")) == "waypoint": _toast("미실행 경유점만 편집할 수 있습니다.", "warning")
		return
	var message: Dictionary = actions.duplicate(true)
	message.merge(hit, true)
	message["type"] = "context"
	message["unit_id"] = selected
	message["selected_units"] = selected_units.duplicate()
	message["screen"] = [screen_pos.x, screen_pos.y]
	if str(hit.get("target", "")) == "door": message["door_info"] = _door_info(str(hit.get("id", "")))
	for action_type: String in message.get("disabled", {}):
		message.disabled[action_type] = _tr(str(message.disabled[action_type]))
	context_open = true
	_emit(message)

func _build_door_wall_info(data: Dictionary) -> void:
	# Structural floor-plan data only. Live leaf progress and actors never
	# participate in this cache, and hover/context share the same owned value.
	_door_wall_info.clear()
	var rifle: Dictionary = {"kind": "unit", "weapon": "standard", "current_weapon": "standard", "weapon_length": float(EquipmentCatalog.weapon_stats("standard").get("length", 0.86)), "stance": "standing"}
	var budget: float = sim._weapon_penetration(rifle)
	for door: Dictionary in data.get("doors", []):
		var axis: String = str(door.get("axis", "x"))
		var centre := Vector2(float(door.x), float(door.z))
		var offset := Vector2(float(door.w) * 0.5, 0.0) if axis == "x" else Vector2(0.0, float(door.d) * 0.5)
		rifle["base_height"] = float(door.get("base_height", Simulation.CombatSpatial.floor_base_at(data.get("rooms", []), centre)))
		var height: float = Simulation.CombatSpatial.weapon_height(rifle)
		var walls: Array[Dictionary] = []
		for wall: Dictionary in data.get("walls", []):
			var rect := Rect2(Vector2(float(wall.x) - float(wall.w) * 0.5, float(wall.z) - float(wall.d) * 0.5), Vector2(float(wall.w), float(wall.d))).grow(0.01)
			if not (rect.has_point(centre - offset) or rect.has_point(centre + offset)): continue
			var base: float = float(wall.get("base_height", 0.0))
			if height < base or height > base + sim.nav.obstacle_height(wall): continue
			var resistance: float = sim.nav.obstacle_resistance(wall)
			walls.append({"id": str(wall.id), "material": str(wall.get("material", "")), "thin": bool(wall.get("thin", false)), "resistance": resistance, "rifle_penetrable": resistance <= budget})
		walls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
		_door_wall_info[str(door.id)] = {"walls": walls, "rifle_budget": budget}

func _door_info(door_id: String) -> Dictionary:
	return _door_wall_info.get(door_id, {"walls": [], "rifle_budget": sim._weapon_penetration({"weapon": "standard", "current_weapon": "standard"})}).duplicate(true)

func _close_context() -> void:
	if not context_open: return
	context_open = false
	_emit({"type": "context_close"})

func _arm_drag(kind: String, event: InputEventMouseButton, hit: Dictionary) -> void:
	drag = {"kind": kind, "press": event.position, "button": event.button_index,
		"active": false, "append": event.shift_pressed, "unit_id": selected,
		"index": int(hit.get("index", -1)), "origin": hit.get("target", hit.get("point", _point_array(world.screen_to_ground(event.position)))),
		"points": [], "screen": event.position}
	if kind == "path":
		for unit: Dictionary in shown.get("units", []):
			if str(unit.id) == selected:
				drag.origin = [float(unit.x), float(unit.z)]
				break

func _mouse_motion(event: InputEventMouseMotion) -> void:
	var point: Vector2 = world.screen_to_ground(event.position)
	if not is_finite(point.x) or not is_finite(point.y): return
	if tool == "formation" and mode == "PLANNING" and not ui_focus_active and not keyboard_blocked:
		_formation_hover(point)
		return
	if not drag.is_empty():
		if not bool(drag.active) and event.position.distance_to(drag.press) >= DRAG_THRESHOLD:
			drag.active = true
			_pause_for_edit()
		if not bool(drag.active): return
		drag.screen = event.position
		if str(drag.kind) == "path":
			var samples: Array = drag.points
			if samples.is_empty() or Vector2(float(samples[-1][0]), float(samples[-1][1])).distance_to(point) >= 0.18:
				samples.append(_point_array(point))
			if samples.size() > 256:
				drag.points = _simplify_points(samples, 0.12)
		world.set_interaction({"kind": drag.kind, "origin": drag.origin, "target": _point_array(point), "points": drag.points, "unit_id": selected, "index": drag.index})
		return
	var hit: Dictionary = _pick_context(event.position)
	var interaction: Dictionary = hit.duplicate(true)
	if not hit.is_empty():
		var actions: Dictionary = sim.context_actions(selected, str(hit.target), str(hit.id), int(hit.get("index", -1)))
		if str(hit.target) == "door" and not actions.get("actions", []).is_empty() and selected_units.size() >= 2 and selected_units.size() <= 4: actions.actions.append("ENTER_ROOM")
		interaction.merge(actions, true)
		interaction["kind"] = "hover"
		if str(hit.target) == "door": interaction["door_info"] = _door_info(str(hit.id))
	if tool in ["stun", "smoke"] and not selected.is_empty():
		for unit: Dictionary in shown.get("units", []):
			if str(unit.id) == selected:
				var source: Vector2 = Vector2(float(unit.x), float(unit.z))
				var stock: int = int(unit.get("smokes", 0)) if tool == "smoke" else int(unit.get("stuns", 0))
				interaction = {"kind": "throw", "origin": _point_array(source), "target": _point_array(point), "valid": stock > 0 and source.distance_to(point) <= 8.0 and world.preview_throw_clear(source, point), "radius": 2.5 if tool == "smoke" else 3.0}
				break
	elif tool == "frag" and not selected.is_empty():
		var preview: Dictionary = sim.frag_target_preview(selected, _point_array(point))
		var source: Array = preview.get("source", [])
		var origin: Array = source.slice(0, 2) if source.size() >= 2 else _point_array(point)
		interaction = {"kind": "throw", "tool": "frag", "origin": origin, "target": _point_array(point), "valid": bool(preview.get("ok", false)), "radius": float(preview.get("radius", 0.0)), "core_radius": float(preview.get("core_radius", 0.0)), "available_frags": int(preview.get("available_frags", 0)), "message": str(preview.get("message", "")), "message_key": str(preview.get("message_key", ""))}
	elif tool == "flash_target":
		var command: Dictionary = _flash_target_command()
		if not command.is_empty():
			var preview: Dictionary = sim.flash_target_preview(selected, tool_insert_index, _point_array(point))
			var origin: Array = preview.get("source", _point_array(_flash_preview_origin(command)))
			interaction = {"kind": "throw", "origin": origin, "target": _point_array(point), "valid": bool(preview.get("ok", false)), "radius": 3.0, "message": str(preview.get("message", ""))}
	elif tool in ["face", "face_lock"] and tool_insert_index >= 0 and tool_origin.size() == 2:
		interaction = {"kind": "face", "origin": tool_origin, "target": _point_array(point)}
	world.set_interaction(interaction)
	var hover_key: String = JSON.stringify(hit) + tool + JSON.stringify(interaction.get("actions", [])) + str(interaction.get("valid", ""))
	if hover_key != _last_hover_key:
		_last_hover_key = hover_key
		hover = hit
		var message: Dictionary = interaction.duplicate(true)
		message["type"] = "hover"
		message["screen"] = [event.position.x, event.position.y]
		_emit(message)

func _flash_target_command() -> Dictionary:
	for unit: Dictionary in sim.units:
		if str(unit.id) != selected: continue
		var commands: Array = unit.get("commands", [])
		if tool_insert_index >= 0 and tool_insert_index < commands.size():
			var command: Dictionary = commands[tool_insert_index]
			if str(command.get("type", "")) == "OPEN_AND_FLASH" and str(command.get("state", "")) == "PENDING": return command
	return {}

func _flash_preview_origin(command: Dictionary) -> Vector2:
	var route: Array = command.get("path", [])
	if not route.is_empty(): return Vector2(float(route[-1][0]), float(route[-1][1]))
	for unit: Dictionary in shown.get("units", []):
		if str(unit.id) == selected: return Vector2(float(unit.x), float(unit.z))
	return Vector2.ZERO

func _mouse_release(event: InputEventMouseButton) -> void:
	if drag.is_empty() or int(drag.button) != event.button_index: return
	var pending: Dictionary = drag.duplicate(true)
	_cancel_drag()
	if mode == "REPLAY" or context_open: return
	if not bool(pending.active):
		if str(pending.kind) == "face":
			_open_context({"target": "waypoint", "id": selected, "index": pending.index, "point": pending.origin}, event.position)
		return
	var target: Array = _point_array(world.screen_to_ground(event.position))
	if not _can_edit(): return
	match str(pending.kind):
		"waypoint": _command_response(sim.update_command_args(selected, int(pending.index), {"target": target}))
		"face": _command_response(sim.insert_command(selected, int(pending.index) + 1, "FACE", {"target": target}))
		"path":
			var points: Array = pending.points
			points.append(target)
			points = _simplify_points(points, 0.22)
			_command_response(sim.plan_drag(selected, points, bool(pending.append)))

func _escape() -> void:
	_clear_formation_preview()
	if camera_drag_button != 0:
		camera_drag_button = 0
		return
	if not drag.is_empty():
		_cancel_drag()
		return
	if context_open:
		_close_context()
		return
	if tool != "select": tool = "select"
	else:
		if mode == "EXECUTING": mode = "PLANNING"
		_emit({"type": "menu_request"})

func _cancel_drag() -> void:
	drag.clear()
	if world != null: world.set_interaction({})

func _simplify_points(points: Array, tolerance: float) -> Array:
	if points.size() < 3: return points.duplicate(true)
	var simplified: Array = Simulation.simplify_path(points, tolerance)
	while simplified.size() > 32:
		tolerance *= 1.4
		simplified = Simulation.simplify_path(points, tolerance)
	return simplified

func _finish_mission() -> void:
	_cancel_drag()
	_close_context()
	mode = "RESULT"
	recorder.finish(sim.snapshot(true))
	shown = sim.snapshot(false)
	_remember_shown()
	if not result_saved:
		result_saved = true
		_emit({"type": "sound", "name": "win" if bool(sim.result.get("success", false)) else "fail"})
		_emit_replay_data("save")
	_send_state()

func _start_replay() -> void:
	_cancel_drag()
	_close_context()
	movement_audio.reset()
	mode = "REPLAY"
	replay_time = 0.0
	_replay_seek_pending = true
	replay_playing = true
	replay_speed = 1.0
	replay_reveal = false
	replay_follow = ""
	last_event_seq = 0
	last_fx_seq = 0
	_reset_fx_rooms()
	world.reset_camera()
	_replay_sample_recorder = null
	_sample_replay()
	_reset_friendly_health(shown)
	_replay_reset_neutralized_ids = shown.get("neutralized_ids", []).duplicate(false)

func _import_replay(input: Variant) -> void:
	if not input is Dictionary:
		_toast("올바른 리플레이 JSON 파일이 아닙니다.", "error")
		return
	if input.has("mission_data"):
		if _register_custom(input.mission_data).is_empty(): return
	var candidate: RefCounted = Replay.new()
	var check: Dictionary = candidate.load_data(input)
	if not bool(check.get("ok", false)):
		_toast(str(check.get("message", "리플레이를 읽을 수 없습니다.")), "error")
		return
	var id: String = str(input.get("map_id", ""))
	if not maps.has(id):
		_toast("이 게임 버전에서 지원하지 않는 맵입니다.", "error")
		return
	# Check the normalized version 1 defaults before any world/recorder change.
	var options_error: String = _options_error(candidate.data)
	if not options_error.is_empty():
		_toast(options_error, "error")
		return
	_load_mission(id, false, candidate.data)
	recorder = candidate
	_start_replay()
	_toast("리플레이를 불러왔습니다.")

func _export_plan() -> Dictionary:
	var plans: Array = []
	for unit: Dictionary in sim.units:
		var commands: Array = []
		for command: Dictionary in unit.get("commands", []):
			# Saved plans are fresh starts, never serialized mid-simulation states.
			if str(command.get("state", "")) in ["SUCCEEDED", "CANCELLED"]:
				continue
			commands.append({"type": str(command.type), "args": command.get("args", {}).duplicate(true)})
		plans.append({"id": str(unit.id), "commands": commands, "stance": str(unit.get("stance", "standing")), "movement_mode": str(unit.get("movement_mode", "normal")), "hold_position": bool(unit.get("hold_position", false))})
	var exported: Dictionary = {"schema_version": 1, "kind": "breach-plan", "game_build_id": BUILD_ID,
		"map_id": mission_id, "map_revision": 1, "units": plans,
		"seed": active_mission.get("seed", 42), "variant": active_mission.get("variant", "base"),
		"modifiers": mission_options.get("modifiers", []).duplicate(true),
		"loadout": mission_options.get("loadout", {}).duplicate(true), "roster": mission_options.get("roster", []).duplicate(true)}
	if custom_maps.has(mission_id): exported["mission_data"] = maps[mission_id].duplicate(true)
	return exported

func _import_plan(input: Variant, notify_loaded: bool = true) -> void:
	if not input is Dictionary:
		_toast("계획 파일 형식이 올바르지 않습니다.", "error")
		return
	if input.has("mission_data"):
		if _register_custom(input.mission_data).is_empty(): return
	if not _finite(input.get("schema_version")) or not _finite(input.get("map_revision")):
		_toast("계획 파일의 버전 형식이 올바르지 않습니다.", "error")
		return
	if float(input.schema_version) != 1.0 or str(input.get("game_build_id", "")) != BUILD_ID or float(input.map_revision) != 1.0 or not maps.has(str(input.get("map_id", ""))):
		_toast("계획 파일의 버전 또는 임무가 일치하지 않습니다.", "error")
		return
	if not input.get("units") is Array or input.units.size() > 4:
		_toast("계획의 대원 목록이 올바르지 않습니다.", "error")
		return
	if not input.get("modifiers", []) is Array or not input.get("loadout", {}) is Dictionary or not input.get("roster", []) is Array:
		_toast("계획의 장비·명부·변형 정보가 올바르지 않습니다.", "error")
		return
	var options_error: String = _options_error(input)
	if not options_error.is_empty():
		_toast(options_error, "error")
		return
	var imported_options: Dictionary = _canonical_options(str(input.map_id), input)
	var candidate: RefCounted = Simulation.new()
	candidate.load_mission(_configured_mission(str(input.map_id), imported_options))
	var ids: Array[String] = []
	var known_ids: Array[String] = []
	for unit: Dictionary in candidate.units:
		known_ids.append(str(unit.id))
	for unit_plan: Variant in input.units:
		if not unit_plan is Dictionary or not unit_plan.get("commands") is Array or unit_plan.commands.size() > 32:
			_toast("계획의 명령 개수 또는 형식이 올바르지 않습니다.", "error")
			return
		var id: String = str(unit_plan.get("id", ""))
		if not known_ids.has(id):
			_toast("계획에 존재하지 않는 대원이 있습니다.", "error")
			return
		if ids.has(id):
			_toast("계획에 중복 대원이 있습니다.", "error")
			return
		ids.append(id)
		for field: Variant in unit_plan:
			if field not in ["id", "commands", "stance", "movement_mode", "hold_position"]:
				_toast("계획에 지원하지 않는 대원 설정이 있습니다.", "error")
				return
		var posture: Dictionary = {}
		for field: String in ["stance", "movement_mode", "hold_position"]:
			if unit_plan.has(field): posture[field] = unit_plan[field]
		var configured: Dictionary = candidate.configure_unit(id, posture)
		if not bool(configured.get("ok", false)):
			_toast(str(configured.message), "error")
			return
		for command: Variant in unit_plan.commands:
			if not command is Dictionary or not command.get("args", {}) is Dictionary:
				_toast("계획의 명령 데이터가 올바르지 않습니다.", "error")
				return
			var validation: Dictionary = candidate.issue(id, str(command.get("type", "")), command.get("args", {}), true)
			if not bool(validation.get("ok", false)):
				_toast("계획을 불러올 수 없습니다: " + str(validation.get("message", "잘못된 명령")), "error")
				return
	_load_mission(str(input.map_id), true, imported_options, candidate)
	initial_plan = input.duplicate(true)
	if notify_loaded: _toast("저장된 계획으로 임무를 처음부터 준비했습니다.")

func _register_custom(input: Variant) -> Dictionary:
	var check: Dictionary = MissionCatalog.validate_custom(input)
	if not bool(check.get("ok", false)):
		_toast(str(check.get("message", "커스텀 임무를 불러올 수 없습니다.")), "error")
		return {}
	var data: Dictionary = check.get("data", {})
	var id: String = str(data.get("id", ""))
	if MissionCatalog.MAPS.has(id):
		_toast("기본 임무와 다른 ID를 지정하세요.", "error")
		return {}
	data["custom"] = true
	maps[id] = data.duplicate(true)
	custom_maps[id] = true
	var update: Dictionary = {}
	update[id] = _public_mission(data)
	_emit({"type": "catalog_update", "catalog": update})
	return data

func _dispatch_sounds(state: Dictionary) -> void:
	var newest: int = last_event_seq
	var played: Dictionary = {}
	for event: Dictionary in state.get("presentation_events", state.get("events", [])):
		var seq: int = int(event.get("seq", 0))
		if seq <= last_event_seq: continue
		newest = maxi(newest, seq)
		var name: String = ""
		match str(event.get("type", "")).to_lower():
			"shot", "attack", "fire":
				# Each event represents one real shot, including simultaneous shooters.
				_emit_positional_sound("shot", event, event.get("from", []))
				if bool(event.get("hit", false)):
					_emit_positional_sound("hit", event, event.get("to", []))
				continue
			"hit": name = "hit"
			"door", "door_open", "door_opened":
				_emit_positional_sound("door", event, event.get("from", event.get("to", [])))
				continue
			"door_action", "door_kick", "door_breach", "kick_failed":
				if float(event.get("radius", 0.0)) > 0.0:
					_emit_positional_sound("door", event, event.get("from", []))
				continue
			"stun", "stun_thrown": name = "stun"
			"frag":
				if event.get("observed", false) == true: name = "stun"
		if not name.is_empty() and not played.has(name):
			played[name] = true
			_emit_positional_sound(name, event, event.get("from", event.get("to", [])))
	last_event_seq = newest

func _emit_positional_sound(name: String, event: Dictionary, point: Array) -> void:
	if name == "hit" and str(event.get("protection", "")) == "blocked": name = "armour_block"
	var message: Dictionary = {"type": "sound", "name": name, "event_seq": int(event.get("seq", 0)), "attacker_id": str(event.get("attacker_id", "")), "protection": str(event.get("protection", "")), "radius": float(event.get("radius", 0.0)), "pan": 0.0, "gain": 1.0}
	message["react_at"] = _web_reaction_at(float(event.get("time", 0.0)), name in ["hit", "armour_block"] and (bool(event.get("after_shot", false)) or (str(event.get("type", "")).to_upper() in ["SHOT", "ATTACK", "FIRE"] and bool(event.get("hit", false)))))
	if point.size() == 2 and world != null:
		var view_camera: Camera3D = world.get("camera")
		if is_instance_valid(view_camera):
			var viewport_size: Vector2 = get_viewport().get_visible_rect().size
			var screen: Vector2 = view_camera.unproject_position(world.surface_position(Vector2(float(point[0]), float(point[1])), 1.0))
			message["pan"] = clampf((screen.x / maxf(viewport_size.x, 1.0) * 2.0 - 1.0) * 0.8, -0.8, 0.8)
			# A modest screen-distance falloff keeps remote contacts audible.
			var screen_distance: float = ((screen - viewport_size * 0.5) / maxf(viewport_size.y, 1.0)).length()
			message["gain"] = clampf(1.0 - screen_distance * 0.35, 0.55, 1.0)
	_emit(message)

func _reset_event_cursor(state: Dictionary) -> void:
	last_event_seq = 0
	for event: Dictionary in state.get("events", []):
		last_event_seq = maxi(last_event_seq, int(event.get("seq", 0)))

## Authored geometry only. Simulation's observed room authority supplies
## status; no NPC roster, kill count or exploration mask can clear a room.
func _build_fx_room_map(mission: Dictionary) -> void:
	_fx_room_map.clear()
	var rooms: Array = mission.get("rooms", [])
	for room: Dictionary in rooms:
		var room_id: String = str(room.get("id", room.get("label", "")))
		if room_id.is_empty():
			continue
		var half := Vector2(float(room.get("w", 1.0)), float(room.get("d", 1.0))) * 0.5
		var pos := Vector2(float(room.get("x", 0.0)), float(room.get("z", 0.0)))
		_fx_room_map[room_id] = {"rect": Rect2(pos - half, half * 2.0), "name": str(room.get("label", room_id)), "pos": pos, "floor_height": float(room.get("base_height", 0.0))}
	_reset_fx_rooms()

func _reset_fx_rooms() -> void:
	_fx_last_hit_shot.clear()
	_fx_unit_hp.clear()
	_fx_unit_shot_damage.clear()
	_fx_frag_pending.clear()
	_web_react_until = -1.0
	_fx_neutralized_ids.clear()
	_fx_room_cleared.clear()
	_fx_room_clear_seq.clear()
	for room_id: String in _fx_room_map:
		_fx_room_cleared[room_id] = false

## Which room (if any) contains a player-visible point, by room rect -- used
## both to find an observed enemy's current room and to find the room a
## neutralization event actually happened in.
func _fx_room_id_at(point: Vector2) -> String:
	for room_id: String in _fx_room_map:
		if (_fx_room_map[room_id]["rect"] as Rect2).has_point(point):
			return room_id
	return ""

func _observed_room_rows(state: Dictionary) -> Dictionary:
	var memory: Variant = state.get("room_states_observed", state.get("room_states", {}))
	return memory if memory is Dictionary else {}

## The optional final argument is now the actual authority transition event.
## Legacy kill-only callers remain harmless. Do not infer a transition from
## the final room map: a fast replay can batch the preceding deaths with it.
func _check_room_clear(_enemy_id: String, position: Array, time: float, state: Dictionary, transition: Variant = null) -> void:
	if not transition is Dictionary or str(transition.get("type", "")) != "CALL_ROOM_CLEAR" or transition.get("observed", false) != true: return
	var room_id := str(transition.get("room_id", ""))
	var unit_id := str(transition.get("unit_id", ""))
	var seq := int(transition.get("seq", 0))
	if not _fx_room_map.has(room_id) or seq <= int(_fx_room_clear_seq.get(room_id, 0)): return
	if position.size() != 2 or not _finite(position[0]) or not _finite(position[1]): return
	if not (_fx_room_map[room_id].rect as Rect2).has_point(Vector2(float(position[0]), float(position[1]))): return
	if not is_finite(time) or time > float(state.get("presentation_time", state.get("time", INF))) + 0.000001: return
	var own := false
	for unit: Dictionary in active_mission.get("units", state.get("units", [])):
		if str(unit.get("id", "")) == unit_id: own = true
	if not own: return
	_fx_room_cleared[room_id] = true
	_fx_room_clear_seq[room_id] = seq
	var info: Dictionary = _fx_room_map[room_id]
	var pos: Vector2 = info.pos
	_emit_fx("room_clear", time, {"room_id": room_id, "room_name": str(info.get("name", ""))}, [pos.x, pos.y])

## Seek restores observed authority silently. The independent death cursor
## remains useful for existing combat FX, but never determines room control.
func _reset_fx_cursor(state: Dictionary) -> void:
	_reset_friendly_health(state)
	_fx_last_hit_shot.clear()
	last_fx_seq = 0
	for event: Dictionary in state.get("events", []):
		last_fx_seq = maxi(last_fx_seq, int(event.get("seq", 0)))
	_fx_neutralized_ids.clear()
	if state.get("neutralized_ids") is Array:
		for id: String in state.neutralized_ids: _fx_neutralized_ids[id] = true
	else:
		for event: Dictionary in state.get("events", []):
			var type := str(event.get("type", ""))
			if type == "INCAPACITATED" and str(event.get("kind", "")) == "enemy":
				_fx_neutralized_ids[str(event.get("entity_id", ""))] = true
			elif type == "ARREST":
				_fx_neutralized_ids[str(event.get("enemy_id", ""))] = true
	_fx_room_clear_seq.clear()
	var rows := _observed_room_rows(state)
	for room_id: String in _fx_room_map:
		var row: Dictionary = rows.get(room_id, {})
		_fx_room_cleared[room_id] = row.get("observed", false) == true and str(row.get("state", "UNKNOWN")) in ["CLEAR", "MARKED"]

## Plan 2-1 combat fx dispatch: {type:'fx', kind, time, ...} messages derived
## from the same deterministic simulation event log _dispatch_sounds already
## reads, so live play and replay (including after a seek) produce the same
## fx sequence for the same mission/plan. last_fx_seq is the dedup cursor,
## reset at every point last_event_seq is (see call sites above).
func _dispatch_fx(state: Dictionary) -> void:
	var clock := float(state.get("presentation_time", state.get("time", 0.0)))
	# Keep unmatched explosions for the next dispatch, independent of replay speed.
	var frags := _fx_frag_pending
	_fx_frag_pending = []
	var hit_units: Dictionary = {}
	var newest: int = last_fx_seq
	for event: Dictionary in state.get("presentation_events", state.get("events", [])):
		var seq: int = int(event.get("seq", 0))
		if seq <= last_fx_seq:
			continue
		var time: float = float(event.get("time", 0.0))
		if (str(event.get("type", "")) in RoomControl.CALL_TYPES or str(event.get("type", "")) == "FRAG") and time > float(state.get("presentation_time", state.get("time", INF))) + 0.000001: continue
		newest = maxi(newest, seq)
		match str(event.get("type", "")):
			"DOOR_ACTION":
				if str(event.get("kind", "")) in ["KICK_DOOR", "BREACH_DOOR", "SHOTGUN_BREACH"]:
					_emit_fx("breach", time, {"door_id": str(event.get("door_id", ""))}, event.get("from", []))
			"CONTACT":
				_emit_fx("enemy_spotted", time, {}, event.get("to", []))
			"FRAG":
				if event.get("observed", false) == true:
					frags.append(event)
					_fx_frag_pending.append(event)
					_emit_fx("frag", time, {"projectile_id": str(event.get("projectile_id", "")), "radius": float(event.get("radius", 0.0)), "target_height": float(event.get("target_height", 0.0))}, event.get("to", []))
			"SHOT":
				if bool(event.get("hit", false)):
					_fx_last_hit_shot = {"time":time,"to":event.get("to", [])}
					var target_id := str(event.get("target_id", ""))
					hit_units[target_id] = true
					var friendly := _fx_is_friendly(target_id, state)
					if friendly and float(event.get("damage", 0.0)) > 0.0:
						var credit: Dictionary = _fx_unit_shot_damage.get(target_id, {})
						var prior := float(credit.get("damage", 0.0)) if time - float(credit.get("time", -100.0)) <= 2.0 * STEP + 0.000001 else 0.0
						_fx_unit_shot_damage[target_id] = {"damage":prior + float(event.damage), "time":time}
					_emit_fx("hit", time, {"target_id": target_id, "friendly": friendly, "protection": str(event.get("protection", "")), "event_seq": seq, "react_at":_web_reaction_at(time, true)}, event.get("to", []))
			"INCAPACITATED":
				var entity_id: String = str(event.get("entity_id", ""))
				var point: Array = event.get("to", [])
				var last_point: Array = _fx_last_hit_shot.get("to", [])
				var after_shot: bool = point.size() == 2 and last_point.size() == 2 and absf(time - float(_fx_last_hit_shot.get("time", -100.0))) < 0.001 and Vector2(float(point[0]), float(point[1])).distance_to(Vector2(float(last_point[0]), float(last_point[1]))) < 0.05
				var extra := {"id":entity_id,"event_seq":seq,"after_shot":after_shot,"react_at":_web_reaction_at(time, after_shot),"cause":"casualty"}
				if str(event.get("kind", "")) == "enemy":
					extra["friendly"] = false
					_emit_fx("neutralized", time, extra, point)
					_fx_neutralized_ids[entity_id] = true
				else:
					_emit_fx("unit_down", time, extra, point)
			"ARREST":
				var enemy_id: String = str(event.get("enemy_id", ""))
				_emit_fx("neutralized", time, {"id": enemy_id, "friendly": false, "event_seq": seq, "after_shot":false,"cause":"arrest"}, event.get("to", []))
				_fx_neutralized_ids[enemy_id] = true
			"CALL_ROOM_CLEAR":
				_check_room_clear(str(event.get("unit_id", "")), event.get("from", []), time, state, event)
			"MISSION_END":
				_emit_fx("mission_end", time, {"success": bool(state.get("result", {}).get("success", false))}, [])
	# Unseen shooters have no public SHOT; frag damage has no per-victim event.
	# Only compare own public health, never infer an unseen attacker's position.
	var feedback_units: Array = state.get("units", []).duplicate(false)
	for index: int in range(feedback_units.size()):
		var unit: Dictionary = feedback_units[index]
		var id := str(unit.id)
		var hp := float(unit.get("hp", 0.0))
		var loss := maxf(0.0, float(_fx_unit_hp.get(id, hp)) - hp)
		var credit: Dictionary = _fx_unit_shot_damage.get(id, {})
		var covered := float(credit.get("damage", 0.0)) if clock - float(credit.get("time", -100.0)) <= 2.0 * STEP + 0.000001 else 0.0
		if covered > loss:
			credit["damage"] = covered - loss
		else:
			_fx_unit_shot_damage.erase(id)
		if loss > covered + 0.000001 and not hit_units.has(id):
			var tick := int(floor(clock / STEP + 0.000001))
			var time := float(tick) * STEP
			var point: Array = [float(unit.get("x", 0.0)), float(unit.get("z", 0.0))]
			var frag := false
			for explosion: Dictionary in frags:
				var center: Array = explosion.get("to", [])
				if center.size() == 2 and Vector2(float(point[0]), float(point[1])).distance_to(Vector2(float(center[0]), float(center[1]))) <= float(explosion.get("radius", 0.0)):
					frag = true
					_fx_frag_pending.erase(explosion)
			var protection := "" if frag else str(unit.get("last_hit_protection", ""))
			# Casualties without an observed hit shot react immediately in world_view too.
			var after_shot := not frag and hp > 0.0
			var key := "hp:%s:%d" % [id, tick]
			unit = unit.duplicate(false)
			unit["_feedback_hit"] = {"time":time,"protection":protection,"after_shot":after_shot}
			feedback_units[index] = unit
			_emit_fx("hit", time, {"target_id":id,"friendly":true,"protection":protection,"event_seq":key,"react_at":_web_reaction_at(time, after_shot)}, point)
			_emit_positional_sound("hit", {"type":"HIT","time":time,"protection":protection,"after_shot":after_shot}, point)
		_fx_unit_hp[id] = hp
	state["units"] = feedback_units
	last_fx_seq = newest

func _reset_friendly_health(state: Dictionary) -> void:
	_fx_unit_hp.clear()
	_fx_unit_shot_damage.clear()
	_fx_frag_pending.clear()
	for unit: Dictionary in state.get("units", []): _fx_unit_hp[str(unit.id)] = float(unit.get("hp", 0.0))

func _fx_is_friendly(id: String, state: Dictionary) -> bool:
	for unit: Dictionary in state.get("units", active_mission.get("units", [])):
		if str(unit.get("id", "")) == id: return true
	return false

## The inverse of _safe_area_to_viewport_px: Camera3D.unproject_position
## returns viewport px, but the web layer positions DOM stamps/pings in CSS
## px, so fx screen coordinates must be converted the same way set_safe_area
## is converted in the other direction.
func _viewport_px_to_css(point: Vector2) -> Vector2:
	var scale := 1.0
	if OS.has_feature("web"):
		var inner_width: Variant = JavaScriptBridge.eval("window.innerWidth", true)
		var viewport_width: float = get_viewport().get_visible_rect().size.x
		if (inner_width is float or inner_width is int) and float(inner_width) > 0.0 and viewport_width > 0.0:
			scale = viewport_width / float(inner_width)
	return point / maxf(scale, 0.0001)

func _dispatch_feedback_clock(state: Dictionary) -> void:
	_web_presentation_time = float(state.get("presentation_time", state.get("time", 0.0)))
	if _web_react_until >= 0.0 and not bool(state.get("presentation_paused", false)):
		_emit({"type":"fx_clock", "time":_web_presentation_time, "paused":false})
		if _web_presentation_time >= _web_react_until: _web_react_until = -1.0
	elif str(state.get("presentation_mode", mode)) not in ["EXECUTING", "PLANNING", "REPLAY"]:
		_web_react_until = -1.0

func _web_reaction_at(time: float, after_shot: bool) -> float:
	if not after_shot: return 0.0
	var react_at: float = time + HIT_REACTION_DELAY * (0.7 if bool(settings.get("reduced_flash", false)) else 1.0)
	_web_react_until = maxf(_web_react_until, react_at)
	return react_at

func _emit_fx(kind: String, time: float, extra: Dictionary, point: Array) -> void:
	var message: Dictionary = {"type": "fx", "kind": kind, "time": time, "react_at":0.0}
	for key: String in extra:
		message[key] = extra[key]
	if point.size() == 2 and world != null:
		var view_camera: Camera3D = world.get("camera")
		if is_instance_valid(view_camera):
			var viewport_size: Vector2 = get_viewport().get_visible_rect().size
			var scene_point: Vector3 = world.surface_position(Vector2(float(point[0]), float(point[1])), 1.0)
			if kind == "room_clear" and _fx_room_map.has(str(extra.get("room_id", ""))):
				scene_point.y = float(_fx_room_map[str(extra.room_id)].floor_height) + 1.0
			elif kind == "frag": scene_point.y = float(extra.get("target_height", 0.0)) + 0.35
			var screen: Vector2 = view_camera.unproject_position(scene_point)
			if screen.x >= 0.0 and screen.y >= 0.0 and screen.x <= viewport_size.x and screen.y <= viewport_size.y:
				var css: Vector2 = _viewport_px_to_css(screen)
				message["screen"] = [css.x, css.y]
	_emit(message)

func _follow_replay_unit() -> void:
	for unit: Dictionary in shown.get("units", []):
		if str(unit.get("id", "")) == replay_follow:
			if world.has_method("follow_position"):
				world.call("follow_position", Vector2(float(unit.x), float(unit.z)))
			return

func _close_lab() -> void:
	if is_instance_valid(lab):
		remove_child(lab)
		lab.queue_free()
		lab = null
		world.show()
		world.camera.make_current()

func _quality_track(token: String) -> void:
	if token.is_empty() or token == "null" or token.length() > 100: return
	if not quality_pending.has(token) and quality_pending.size() < 64:
		quality_pending.append(token)

func _quality_render_complete() -> void:
	if quality_pending.is_empty(): return
	quality_rendered.assign(quality_pending)
	quality_pending.clear()
	_send_state()

func _quality_payload() -> Dictionary:
	var payload: Dictionary = {"ack_tokens": quality_rendered.duplicate(), "render_frame": Engine.get_process_frames(),
		"render_nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"render_entities": world._entity_nodes.size() if world != null else 0,
		"active_effects": world._flashes.size() if world != null else 0}
	quality_rendered.clear()
	return payload

func _send_state() -> void:
	if _state_batch_depth > 0:
		_state_pending = true
		return
	if mode == "LAB" and is_instance_valid(lab):
		var lab_state: Dictionary = lab.payload()
		if js_quality != null: lab_state["quality"] = _quality_payload()
		_emit(lab_state)
		return
	if sim == null: return
	if mode != "REPLAY":
		_refresh_shown()
		if mode != "EXECUTING":
			var paused_events: Array = sim.take_record_events()
			if not paused_events.is_empty():
				recorder.capture(sim.snapshot(true), paused_events)
				presentation.queue_events(RoomControl.filter_observed_call_events(paused_events))
	else:
		_sample_replay()
	var payload: Dictionary = shown.duplicate(false)
	# A full replay remains recordable; public room information always uses
	# occurrence-time observations, including the completed result.
	if payload.has("room_states_observed") or payload.get("result", {}).has("room_states_observed"):
		RoomControl.project_observed_state(payload)
	if payload.has("events"): payload["events"] = RoomControl.filter_observed_call_events(payload.events)
	if mode == "RESULT":
		Simulation.DoctrineMetrics.filter_observed_statistics(payload)
	payload["type"] = "state"
	payload["mode"] = mode
	payload["presentation_time"] = _web_presentation_time
	payload["mission"] = mission_id
	payload["noise_discipline"] = str(active_mission.get("noise_discipline", "verbal"))
	payload["roe"] = str(payload.get("roe", active_mission.get("roe", "precision")))
	payload["selected"] = selected
	payload["selected_units"] = selected_units.duplicate()
	payload["selected_command"] = selected_command
	payload["context_open"] = context_open
	payload["tool"] = tool
	payload["door_mode"] = door_mode
	payload["door_fallback"] = door_fallback
	for key: String in ["seed", "variant", "modifiers", "stars", "win", "fail", "loadout", "roster"]:
		if not payload.has(key): payload[key] = active_mission.get(key)
	payload["fps"] = Engine.get_frames_per_second()
	payload["can_retry_plan"] = not initial_plan.is_empty()
	payload["prior_attempt_available"] = not prior_attempt.is_empty()
	payload["prior_attempt_visible"] = prior_attempt_visible
	if js_quality != null: payload["quality"] = _quality_payload()
	payload["replay"] = {"time": replay_time, "duration": recorder.duration, "playing": replay_playing,
		"speed": replay_speed, "reveal": replay_reveal, "complete": recorder.complete, "follow": replay_follow}
	_emit(payload)

func _remember_shown() -> void:
	_shown_dirty = false
	_shown_sim = sim
	_shown_tick = int(sim.tick)
	_shown_time = float(sim.time)
	_shown_reveal = false

func _refresh_shown() -> void:
	if _shown_dirty or _shown_sim != sim or _shown_tick != int(sim.tick) or _shown_time != float(sim.time) or _shown_reveal:
		shown = sim.snapshot(false)
		_remember_shown()

func _sample_replay() -> void:
	if _replay_sample_recorder != recorder or _replay_sample_revision != int(recorder.content_revision) or _replay_sample_time != replay_time or _replay_sample_reveal != replay_reveal:
		shown = recorder.seek(replay_time, replay_reveal)
		_replay_sample_recorder = recorder
		_replay_sample_revision = int(recorder.content_revision)
		_replay_sample_time = replay_time
		_replay_sample_reveal = replay_reveal

## RD (plan 2-5 영어 문자열 분리): a starter set of the most common toasts
## (tool-usage hints, the new "no pending signal" message below). Full
## coverage of every Korean toast in this file is not done -- this
## demonstrates the mechanism (settings.language gate + lookup table) rather
## than exhaustively translating every call site; anything not in the table
## below still shows Korean under 'en'.
const TOAST_TRANSLATIONS: Dictionary = {
	"리플레이 파편탄 궤적 시각이 샘플과 일치하지 않습니다.": "The replay fragmentation trajectory time does not match its sample.",
	"리플레이 파편탄 명령이 올바르지 않습니다.": "The replay fragmentation grenade command is invalid.",
	"리플레이 파편탄 궤적 정보가 올바르지 않습니다.": "The replay fragmentation trajectory metadata is invalid.",
	"리플레이 교전수칙이 올바르지 않습니다.": "The replay rules of engagement are invalid.",
	"리플레이 파편탄 관측 통계가 누락되었습니다.": "The replay observed fragmentation statistics are missing.",
	"리플레이 관측 통계 구조가 올바르지 않습니다.": "The replay observed statistics structure is invalid.",
	"리플레이 관측 피해 수치가 올바르지 않습니다.": "The replay observed damage value is invalid.",
	"리플레이 관측 통계 수치가 올바르지 않습니다.": "The replay observed statistics value is invalid.",
	"리플레이 파편탄 피해 통계가 올바르지 않습니다.": "The replay fragmentation damage statistics are invalid.",
	"리플레이 관측 별 과제 결과가 올바르지 않습니다.": "The replay observed star objective results are invalid.",
	"리플레이 파편탄 사건의 공개 정보가 올바르지 않습니다.": "The replay fragmentation event public metadata is invalid.",
	"리플레이 방 교범 구조가 올바르지 않습니다.": "The replay room doctrine structure is invalid.",
	"리플레이 방 교범의 공개 참조가 올바르지 않습니다.": "The replay room doctrine public reference is invalid.",
	"리플레이 방 교범 수치가 올바르지 않습니다.": "The replay room doctrine value is invalid.",
	"리플레이 방 교범 증거 시각이 올바르지 않습니다.": "The replay room doctrine evidence time is invalid.",
	"리플레이 방 교범 증거가 샘플 시각보다 앞서 있습니다.": "The replay room doctrine evidence occurs after its sample time.",
	"정밀 교전수칙에서는 파편 수류탄을 사용할 수 없습니다": "Fragmentation grenades are unavailable under precision ROE.",
	"예약분을 제외한 파편 수류탄이 없습니다": "No unreserved fragmentation grenades remain.",
	"파편 수류탄 투척 범위 8m를 벗어났습니다": "The target is outside the 8 m fragmentation grenade range.",
	"벽 또는 닫힌 문이 파편 수류탄 투척 경로를 막습니다": "A wall or closed door blocks the fragmentation grenade trajectory.",
	"파편 수류탄 재고 또는 투척 경로가 변경되었습니다": "Fragmentation grenade inventory or trajectory has changed.",
	"파편 수류탄 폭발까지 대기": "Waiting for fragmentation grenade detonation.",
	"먼저 대원을 선택하세요.": "Select an operator first.",
	"행동 불능 대원에게 명령할 수 없습니다.": "Cannot command an incapacitated operator.",
	"관측한 문을 클릭하세요.": "Click an observed door.",
	"관측한 민간인을 클릭하세요.": "Click an observed civilian.",
	"관측한 투항 적을 클릭하세요.": "Click a surrendered enemy you can see.",
	"지원하지 않는 명령입니다.": "Unsupported command.",
	"대기 중인 신호가 없습니다.": "No signal is currently being waited on.",
	"명령 목록에서 실패 명령을 삭제한 뒤 다시 계획하세요.": "Delete the failed command in the queue, then revise the plan.",
	"명령을 완료할 수 없어 정지했습니다. 명령 목록에서 실패 명령을 삭제한 뒤 다시 계획하세요.": "Stopped because a command failed. Delete the failed command in the queue, then revise the plan.",
	"장약 안전거리 안에 대원이 있습니다. 기폭 전에 팀을 물러나게 하세요.": "Operators are inside the charge safety distance. Move the team back before detonation.",
	"차기 실패 분기는 장약으로만 지정할 수 있습니다": "A failed kick can fall back to a breach charge only.",
	"이미 열린 문입니다": "The door is already open.",
	"활성 주무기 산탄총과 탄약이 필요합니다": "An active primary shotgun and ammunition are required.",
	"활성 주무기 산탄총과 예약분을 제외한 탄약이 필요합니다": "Requires an active primary shotgun with unreserved ammunition.",
	"예약분을 제외한 문 파괴 장비가 없습니다": "No unreserved breach charges remain.",
	"문 차기에 실패했습니다. 다시 차거나 다른 방법을 선택하세요": "The kick failed. Try again or choose another method.",
	"산탄총 브리칭에 실패했습니다. 다른 방법을 선택하세요": "Shotgun breaching failed. Choose another method.",
	"브리칭 뒤 안전하게 물러날 경로가 없습니다": "There is no safe retreat route after breaching.",
	"안전거리 안 대원의 후퇴를 기다리는 중": "Waiting for operators inside the safety radius to retreat.",
	"예약분을 제외한 섬광탄이 없습니다": "No unreserved flashbangs remain.",
	"잠긴 문입니다. 강제 개방이 필요합니다": "The door is locked. Force it open.",
	"리플레이 문 처리 단계의 명령 종류가 올바르지 않습니다.": "The replay door-action phase does not match its command.",
	"리플레이 장약 전환 단계의 실패 분기가 올바르지 않습니다.": "The replay charge phase requires a failed-kick charge fallback.",
	"리플레이 문 차기 인수가 올바르지 않습니다.": "The replay kick arguments are invalid.",
	"리플레이 문 차기 실패 분기가 올바르지 않습니다.": "The replay kick fallback is invalid.",
	"리플레이 문틀 경계 상태가 올바르지 않습니다.": "The replay doorway readiness state is invalid.",
	"리플레이 브리칭 예약 정보의 대원 종류가 올바르지 않습니다.": "The replay breach reservation belongs to an invalid actor group.",
	"리플레이 문 처리 사건의 문·대원·방법이 올바르지 않습니다.": "The replay door-action event has an invalid door, operator, or method.",
	"리플레이 진입 드릴 정보가 올바르지 않습니다.": "The replay entry-drill metadata is invalid.",
	"리플레이 사격 구역 명령이 올바르지 않습니다.": "The replay sector command is invalid.",
	"리플레이 드릴 동기화 ID가 올바르지 않습니다.": "The replay drill synchronization ID is invalid.",
	"리플레이 자동 신호 상태가 올바르지 않습니다.": "The replay automatic signal state is invalid.",
	"리플레이 신호 지연이 올바르지 않습니다.": "The replay signal delay is invalid.",
	"리플레이 자동·지연 신호에 동기화 ID가 없습니다.": "The replay automatic or delayed signal has no synchronization ID.",
	"리플레이 신호와 드릴 그룹이 일치하지 않습니다.": "The replay signal does not match its drill group.",
	"리플레이 진입 안전 신호는 자동이어야 합니다.": "The replay entry safety signal must be automatic.",
	"리플레이 대원 사격 구역이 올바르지 않습니다.": "The replay operator sector is invalid.",
	"리플레이 신호 사건의 동기화 ID가 올바르지 않습니다.": "The replay signal event synchronization ID is invalid.",
	"리플레이 신호 사건의 자동 상태가 올바르지 않습니다.": "The replay signal event automatic state is invalid.",
	"리플레이 동기화 그룹의 설정이 일치하지 않습니다.": "The replay synchronization group settings do not match.",
	"종료된 작전에는 진입 드릴을 계획할 수 없습니다": "Cannot plan an entry drill after the operation ends.",
	"유효한 문 개방 방법을 선택하세요": "Select a valid door-opening method.",
	"서로 다른 대원 2~4명을 선택하세요": "Select two to four different operators.",
	"진입 드릴 설정이 올바르지 않습니다": "The entry-drill options are invalid.",
	"드릴 신호는 자동 또는 A, B, C로 지정하세요": "Set the drill signal to AUTO, A, B, or C.",
	"동기화 지연은 0~3600 틱으로 지정하세요": "Set the synchronization delay to 0–3600 ticks.",
	"유효한 문을 선택하세요": "Select a valid door.",
	"관측한 문에만 진입 드릴을 계획할 수 있습니다": "Plan entry drills only at observed doors.",
	"실행 중인 대원의 드릴은 계획할 수 없습니다": "Cannot plan a drill for an operator with an active command.",
	"앞선 실패 명령을 먼저 수정하세요": "Fix the preceding failed command first.",
	"앞선 이동 경로가 막혀 있습니다": "The preceding movement route is blocked.",
	"문 처리 담당은 선택한 대원이어야 합니다": "The door operator must belong to the selected team.",
	"미실행 준비 신호만 함께 수정할 수 있습니다": "Only pending ready signals can be edited together.",
	"앞 대원의 진입 간격 유지 중": "Maintaining entry spacing behind the preceding operator.",
	"대원이 쓰러져 남은 진입 계획을 재편성하고 정지했습니다.": "An operator is down. The remaining entry plan was reformed and paused.",
	"팀 설정이 올바르지 않습니다.": "Invalid team settings.",
	"문 조작 대원이 행동 불능이 되어 진입을 안전하게 중단했습니다": "Entry was halted safely because the door operator became incapacitated.",
	"사상자 발생 후 진입 재편성": "Entry reformed after a casualty.",
	"사상자 발생 후 진입 지점을 안전하게 재편성할 수 없습니다": "Entry positions cannot be reformed safely after a casualty.",
	"리플레이 방 상태가 올바르지 않습니다.": "Invalid replay room state.",
	"리플레이 결과 방 상태가 올바르지 않습니다.": "Invalid replay result room state.",
	"리플레이 방 전이가 샘플 시각보다 앞서 있습니다.": "Replay room transition occurs after its sample.",
	"리플레이 정지 사유가 올바르지 않습니다.": "Invalid replay pause reason.",
	"리플레이 정지 대원 ID가 올바르지 않습니다.": "Invalid replay paused operative ID.",
	"리플레이 방 정리 규칙이 올바르지 않습니다.": "Invalid replay room clearance rule.",
	"리플레이 팀 신호의 대원 또는 관측 상태가 올바르지 않습니다.": "Invalid replay team call operative or observation state.",
	"리플레이 팀 신호의 엄호 대원 ID가 올바르지 않습니다.": "Invalid replay team call cover operative ID.",
	"리플레이 팀 신호의 방 ID가 올바르지 않습니다.": "Invalid replay team call room ID.",
	"리플레이 팀 신호 정보의 사건 종류가 올바르지 않습니다.": "Invalid replay event type for team call metadata.",
	"리플레이 대형 정보가 올바르지 않습니다.": "Invalid replay formation metadata.",
	"리플레이 계획 자세가 올바르지 않습니다.": "Invalid replay planned stance.",
	"리플레이 신호와 대형 그룹이 일치하지 않습니다.": "The replay signal does not match its formation group.",
	"리플레이 신호 전달 정보가 완전하지 않습니다.": "Incomplete replay signal delivery metadata.",
	"리플레이 신호 방식 또는 소리 범위가 올바르지 않습니다.": "Invalid replay signal mode or sound radius.",
	"리플레이 신호 발신 대원 ID가 올바르지 않습니다.": "Invalid replay signal sender ID.",
	"리플레이 신호 수신 대원 목록이 올바르지 않습니다.": "Invalid replay signal receiver list.",
}

const REPLAY_ERROR_I18N: Dictionary = {
	"리플레이 파편탄 궤적 시각이 샘플과 일치하지 않습니다.": "replay.error.frag_clock",
	"리플레이 파편탄 명령이 올바르지 않습니다.": "replay.error.frag_command",
	"리플레이 파편탄 궤적 정보가 올바르지 않습니다.": "replay.error.frag_projectiles",
	"리플레이 교전수칙이 올바르지 않습니다.": "replay.error.roe",
	"리플레이 파편탄 관측 통계가 누락되었습니다.": "replay.error.observed_stats_missing",
	"리플레이 관측 통계 구조가 올바르지 않습니다.": "replay.error.observed_stats_shape",
	"리플레이 관측 피해 수치가 올바르지 않습니다.": "replay.error.observed_damage",
	"리플레이 관측 통계 수치가 올바르지 않습니다.": "replay.error.observed_stats_value",
	"리플레이 파편탄 피해 통계가 올바르지 않습니다.": "replay.error.frag_statistics",
	"리플레이 관측 별 과제 결과가 올바르지 않습니다.": "replay.error.observed_stars",
	"리플레이 파편탄 사건의 공개 정보가 올바르지 않습니다.": "replay.error.frag_event",
	"리플레이 방 교범 구조가 올바르지 않습니다.": "replay.error.room_doctrine_shape",
	"리플레이 방 교범의 공개 참조가 올바르지 않습니다.": "replay.error.room_doctrine_reference",
	"리플레이 방 교범 수치가 올바르지 않습니다.": "replay.error.room_doctrine_value",
	"리플레이 방 교범 증거 시각이 올바르지 않습니다.": "replay.error.room_doctrine_evidence",
	"리플레이 방 교범 증거가 샘플 시각보다 앞서 있습니다.": "replay.error.room_doctrine_future",
	"리플레이 방 상태가 올바르지 않습니다.": "replay.error.room_states",
	"리플레이 결과 방 상태가 올바르지 않습니다.": "replay.error.result_room_states",
	"리플레이 방 전이가 샘플 시각보다 앞서 있습니다.": "replay.error.room_transition_time",
	"리플레이 정지 사유가 올바르지 않습니다.": "replay.error.pause_reason",
	"리플레이 정지 대원 ID가 올바르지 않습니다.": "replay.error.pause_unit",
	"리플레이 방 정리 규칙이 올바르지 않습니다.": "replay.error.rooms_cleared_rule",
	"리플레이 팀 신호의 대원 또는 관측 상태가 올바르지 않습니다.": "replay.error.call_unit_observed",
	"리플레이 팀 신호의 엄호 대원 ID가 올바르지 않습니다.": "replay.error.call_cover_unit",
	"리플레이 팀 신호의 방 ID가 올바르지 않습니다.": "replay.error.call_room",
	"리플레이 팀 신호 정보의 사건 종류가 올바르지 않습니다.": "replay.error.call_type",
	"리플레이 대형 정보가 올바르지 않습니다.": "replay.error.formation",
	"리플레이 계획 자세가 올바르지 않습니다.": "replay.error.planned_stance",
	"리플레이 신호와 대형 그룹이 일치하지 않습니다.": "replay.error.formation_signal",
	"리플레이 신호 전달 정보가 완전하지 않습니다.": "replay.error.signal_delivery",
	"리플레이 신호 방식 또는 소리 범위가 올바르지 않습니다.": "replay.error.signal_mode",
	"리플레이 신호 발신 대원 ID가 올바르지 않습니다.": "replay.error.signal_sender",
	"리플레이 신호 수신 대원 목록이 올바르지 않습니다.": "replay.error.signal_receivers",
}

func _tr(text: String) -> String:
	return str(TOAST_TRANSLATIONS.get(text, text)) if str(settings.get("language", "ko")) == "en" else text

func _toast(message: String, kind: String = "info") -> void:
	var toast := {"type": "toast", "message": _tr(message), "kind": kind}
	if REPLAY_ERROR_I18N.has(message): toast["i18n_key"] = REPLAY_ERROR_I18N[message]
	_emit(toast)

func _emit(message: Dictionary) -> void:
	if js_ui != null:
		js_ui.receive(JSON.stringify(message))
	elif str(message.get("type", "")) == "toast":
		print(message.get("message", ""))

func _emit_replay_data(purpose: String) -> void:
	# receive serializes synchronously; bridge callbacks only queue intentions.
	recorder.data["duration"] = recorder.duration
	recorder.data["complete"] = recorder.complete
	_emit({"type":"replay_data", "data":recorder.data, "purpose":purpose})

func _finite(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _identifier(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 64:
		return false
	for i in value.length():
		var c: int = value.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c in [45, 46, 58, 95]):
			return false
	return true

func _release_camera_keys() -> void:
	# Clear the four continuous camera keys after a focus change. A missed key-up
	# must never keep panning the map when the player returns from a dialog/tab.
	for key: int in [KEY_W, KEY_A, KEY_S, KEY_D]:
		if Input.is_physical_key_pressed(key):
			var release := InputEventKey.new()
			release.physical_keycode = key
			release.keycode = key
			release.pressed = false
			Input.parse_input_event(release)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		camera_drag_button = 0
		_release_camera_keys()
		if mode == "EXECUTING":
			mode = "PLANNING"
			accumulator = 0.0
		if mode == "REPLAY": replay_playing = false
