extends SceneTree
## RD (plan 2-2 조작 탭 / 2-3 게임패드 / 2-5 영어 문자열 분리): rebindable
## keyboard actions, gamepad input mapping, the palette/language presentation
## settings, and the mission title_en/description_en i18n fields. Exercises
## the same real controller entry points (_unhandled_input, _action) as
## context_input_test.gd, with no hidden enemy fixture data.
const MainScene = preload("res://main.tscn")
const MainScript = preload("res://scripts/main.gd")
const MissionCatalog = preload("res://scripts/mission_catalog.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func key_event(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	return event

func pad_event(button_index: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	event.pressed = true
	return event

func _run() -> void:
	# Pure mapping functions: no live keyboard/DOM/device needed.
	check(MainScript.dom_code_to_keycode("KeyQ") == KEY_Q, "AC: DOM code KeyQ did not map to KEY_Q")
	check(MainScript.dom_code_to_keycode("KeyG") == KEY_G, "AC: DOM code KeyG did not map to KEY_G")
	check(MainScript.dom_code_to_keycode("Digit3") == KEY_3, "AC: DOM code Digit3 did not map to KEY_3")
	check(MainScript.dom_code_to_keycode("Space") == KEY_SPACE, "AC: DOM code Space did not map to KEY_SPACE")
	check(MainScript.dom_code_to_keycode("NotARealCode") == KEY_NONE, "AC: an unrecognized DOM code mapped to a real keycode")
	check(MainScript.gamepad_action_for_button(JOY_BUTTON_A) == "move_to_cursor", "AC: gamepad A did not map to move_to_cursor")
	check(MainScript.gamepad_action_for_button(JOY_BUTTON_B) == "cancel_tool", "AC: gamepad B did not map to cancel_tool")
	check(MainScript.gamepad_action_for_button(JOY_BUTTON_X) == "door_at_cursor", "AC: gamepad X did not map to door_at_cursor")
	check(MainScript.gamepad_action_for_button(JOY_BUTTON_Y) == "equipment_at_cursor", "AC: gamepad Y did not map to equipment_at_cursor")
	check(MainScript.gamepad_action_for_button(JOY_BUTTON_LEFT_SHOULDER) == "cycle_prev", "AC: gamepad LB did not map to cycle_prev")
	check(MainScript.gamepad_action_for_button(JOY_BUTTON_RIGHT_SHOULDER) == "cycle_next", "AC: gamepad RB did not map to cycle_next")
	check(MainScript.gamepad_action_for_button(JOY_BUTTON_START) == "toggle_execute", "AC: gamepad Start did not map to toggle_execute")
	check(MainScript.gamepad_action_for_button(JOY_BUTTON_BACK) == "pause_menu", "AC: gamepad Back did not map to pause_menu")
	check(MainScript.gamepad_action_for_button(99) == "", "AC: an unmapped gamepad button returned a nonempty action")

	# Mission i18n: title_en/description_en ride along the existing Korean
	# fields (bridge contract documented in main.gd/mission_catalog.gd).
	var catalog: Dictionary = MissionCatalog.missions()
	check(str(catalog.M01.get("title_en", "")) == "Quiet House", "AC: base mission M01 lost its authored title_en")
	check(str(catalog.M01_HOSTAGE.get("title_en", "")) == "Quiet House · Hostage Rescue", "AC: generated hostage variant title_en did not combine the base title_en with the English type label")
	check(not str(catalog.M01_HOSTAGE.get("description_en", "")).is_empty(), "AC: generated variant mission had no description_en")

	var session: Node = MainScene.instantiate()
	root.add_child(session)
	session.set_process(false)
	await process_frame
	session._action({"action": "start", "mission": "M01", "seed": "bindings-test"})
	var unit_id: String = str(session.sim.units[0].id)
	session._select(unit_id)

	# Default bindings still reproduce the pre-existing F=face/R=reload keys.
	session.tool = "select"
	session._unhandled_input(key_event(KEY_F))
	check(session.tool == "face", "AC: default KeyF binding no longer selects the face tool")
	session.tool = "select"
	var before_commands: int = session.sim.units[0].commands.size()
	session._unhandled_input(key_event(KEY_R))
	check(session.sim.units[0].commands.size() == before_commands + 1 and session.sim.units[0].commands.back().type == "RELOAD", "AC: default KeyR binding did not issue RELOAD")

	# New default bindings for move/door/equipment/secure/wait/signal.
	session.tool = "select"
	session._unhandled_input(key_event(KEY_Q))
	check(session.tool == "move", "AC: default KeyQ (move) binding did not select the move tool")
	session.tool = "select"
	session._unhandled_input(key_event(KEY_E))
	check(session.tool == "door", "AC: default KeyE (door) binding did not select the door tool")
	session.tool = "select"
	session._unhandled_input(key_event(KEY_C))
	check(session.tool == "secure", "AC: default KeyC (secure) binding did not select the secure tool")
	before_commands = session.sim.units[0].commands.size()
	session._unhandled_input(key_event(KEY_T))
	check(session.sim.units[0].commands.size() == before_commands + 1 and session.sim.units[0].commands.back().type == "WAIT", "AC: default KeyT (wait) binding did not issue WAIT")
	session.tool = "select"
	session._unhandled_input(key_event(KEY_G))
	check(session.tool == "stun", "AC: first KeyG (equipment) press did not select the first equipment tool")
	session._unhandled_input(key_event(KEY_G))
	check(session.tool == "smoke", "AC: second KeyG (equipment) press did not cycle to the next equipment tool")
	session._unhandled_input(key_event(KEY_G))
	check(session.tool == "breach", "AC: third KeyG (equipment) press did not cycle to the last equipment tool")
	session._unhandled_input(key_event(KEY_G))
	check(session.tool == "stun", "AC: fourth KeyG (equipment) press did not wrap back to the first equipment tool")

	# Rebinding: a legal custom code takes effect for an otherwise-untouched
	# bindings object.
	session._action({"action": "settings", "settings": {"bindings": {"move": "KeyJ"}}})
	check(str(session.settings.bindings.move) == "KeyJ", "AC: a legal custom binding (move=KeyJ) was accepted")
	check(str(session.settings.bindings.door) == "KeyE", "AC: an unspecified action (door) kept its default alongside an accepted custom binding")
	session.tool = "select"
	session._unhandled_input(key_event(KEY_J))
	check(session.tool == "move", "AC: the rebound KeyJ did not trigger the move action")
	session._action({"action": "settings", "settings": {"bindings": {}}})

	# M3 fix: any invalid code (not on the exact Key[A-Z]\WASD/Digit[0,5-9]/
	# punctuation whitelist, e.g. the reserved WASD key W) or any duplicate
	# code rejects the WHOLE incoming bindings object back to every default,
	# never a partial per-action fallback (which could leave two actions on
	# the same key, e.g. a reserved/duplicate "face" silently colliding with
	# "reload" both landing on KeyR).
	session._action({"action": "settings", "settings": {"bindings": {"move": "KeyJ", "door": "KeyJ", "face": "KeyW"}}})
	check(str(session.settings.bindings.move) == "KeyQ", "AC: a duplicate code (door=KeyJ, already claimed by move) rejected the WHOLE bindings object, not just that action")
	check(str(session.settings.bindings.door) == "KeyE", "AC: the whole-object rejection restored door's default too")
	check(str(session.settings.bindings.face) == "KeyF", "AC: a reserved/disallowed code (face=KeyW) rejected the whole bindings object")
	session.tool = "select"
	session._unhandled_input(key_event(KEY_J))
	check(session.tool == "select", "AC: KeyJ no longer triggers move once the whole bindings object was rejected")
	session.tool = "select"
	session._unhandled_input(key_event(KEY_Q))
	check(session.tool == "move", "AC: KeyQ (the restored default) triggers move after the whole-object rejection")
	session._action({"action": "settings", "settings": {"bindings": {}}})

	# Signal: the binding releases whichever channel is actually WAITING,
	# not a fixed channel, and does nothing when no unit is waiting. Uses a
	# second, still-idle operator since unit 0 already has queued RELOAD/WAIT
	# commands from the binding tests above that would otherwise delay
	# WAIT_FOR_SIGNAL from starting.
	check(session._next_pending_signal_channel() == "", "AC: an idle mission reported a pending signal channel")
	var signal_unit_id: String = str(session.sim.units[1].id)
	session._select(signal_unit_id)
	session._action({"action": "command", "type": "WAIT_FOR_SIGNAL", "args": {"signal": "B"}})
	for _tick: int in range(6): session.sim.step(session.STEP)
	check(session._next_pending_signal_channel() == "B", "AC: a unit WAITING on signal B was not detected")
	session._unhandled_input(key_event(KEY_Z))
	session.sim.step(session.STEP)
	check(session.sim.units[1].commands.back().state == "SUCCEEDED", "AC: the signal binding did not release the waiting command")
	session._select(unit_id)

	# Gamepad: ui_focus gates every button/axis action, matching the bridge
	# contract (Godot ignores gamepad entirely while a DOM overlay owns input).
	session._action({"action": "ui_focus", "active": true})
	check(session.ui_focus_active, "AC: the ui_focus bridge action did not set ui_focus_active")
	session.tool = "select"
	session.gamepad_cursor = Vector2(12.2, 14.6)
	session._unhandled_input(pad_event(JOY_BUTTON_B))
	check(session.tool == "select", "AC: a gamepad button acted while ui_focus_active was true")
	session._action({"action": "ui_focus", "active": false})
	check(not session.ui_focus_active, "AC: ui_focus_active did not clear when the web sent active=false")
	session.tool = "door"
	session._unhandled_input(pad_event(JOY_BUTTON_B))
	check(session.tool == "select", "AC: gamepad B (cancel_tool) did not restore the select tool once ui_focus cleared")

	# M5 fix: A/X/Y (move/door/equipment at cursor) must be ignored until the
	# left stick has actually moved the cursor at least once -- otherwise a
	# stray press before the player touches the stick could MOVE/throw to
	# the cursor's unmoved starting position. gamepad_cursor_active is false
	# here (only _process_gamepad's stick polling sets it true; this test
	# drives _handle_gamepad_button directly).
	check(not session.gamepad_cursor_active, "AC: gamepad_cursor_active starts false before the stick has moved")
	before_commands = session.sim.units[0].commands.size()
	session._unhandled_input(pad_event(JOY_BUTTON_A))
	check(session.sim.units[0].commands.size() == before_commands, "AC: gamepad A (move_to_cursor) was ignored before the cursor had ever moved")

	session.gamepad_cursor_active = true
	session.gamepad_cursor = Vector2(12.2, 14.6)
	before_commands = session.sim.units[0].commands.size()
	session._unhandled_input(pad_event(JOY_BUTTON_A))
	# plan_move may auto-insert an OPEN_DOOR ahead of the MOVE if the path to
	# the cursor crosses a closed door, so check the queue grew with a
	# trailing MOVE to the right place rather than assuming exactly 1 command.
	var move_target: Vector2 = Vector2(float(session.sim.units[0].commands.back().args.target[0]), float(session.sim.units[0].commands.back().args.target[1]))
	check(session.sim.units[0].commands.size() > before_commands and session.sim.units[0].commands.back().type == "MOVE" and move_target.is_equal_approx(session.gamepad_cursor), "AC: gamepad A (move_to_cursor) issued a MOVE to the virtual cursor once the cursor had moved and no equipment tool is active")

	# M5 fix: Y only cycles to the next equipment item; it must NOT also
	# throw/breach in the same press (the old behavior left no way to choose
	# which item to use). A then confirms (throws) at the cursor once an
	# equipment tool is active, instead of moving.
	session.tool = "select"
	before_commands = session.sim.units[0].commands.size()
	session._unhandled_input(pad_event(JOY_BUTTON_Y))
	check(session.tool == "stun", "AC: gamepad Y selected the first equipment tool (stun)")
	check(session.sim.units[0].commands.size() == before_commands, "AC: gamepad Y did not also throw -- it only selects the item")
	session._unhandled_input(pad_event(JOY_BUTTON_A))
	check(session.sim.units[0].commands.size() == before_commands + 1 and session.sim.units[0].commands.back().type == "THROW_STUN", "AC: gamepad A confirmed the throw at the cursor once the stun tool was active")
	session.tool = "select"

	var first_selected: String = session.selected
	session._unhandled_input(pad_event(JOY_BUTTON_RIGHT_SHOULDER))
	check(session.selected != first_selected, "AC: gamepad RB (cycle_next) did not change the selected operator")

	# Palette: swaps the 3D presentation colors to the documented hex set and
	# keeps them until changed again. settings flow to world_view through
	# render_state["settings"] each _process() frame in real play; call
	# world.set_settings directly here (same public entry point
	# safe_area_camera_test.gd/world_readability_test.gd already use) so this
	# test does not depend on a full presentation frame.
	session._action({"action": "settings", "settings": {"palette": "deutan"}})
	session.world.set_settings(session.settings)
	check(session.world.UNIT_COLORS[0].is_equal_approx(Color("3fa7ff")), "AC: deutan palette did not recolor the first operator")
	check(session.world.ENEMY_COLOR.is_equal_approx(Color("ffb000")), "AC: deutan palette did not recolor the enemy/threat marker")
	session._action({"action": "settings", "settings": {"palette": "default"}})
	session.world.set_settings(session.settings)
	check(session.world.UNIT_COLORS[0].is_equal_approx(Color("a1d6c3")), "AC: switching back to the default palette did not restore the original operator color")

	# Language: Godot-rendered 3D status/badge text and a sample toast switch
	# to English; Korean source strings not in the small starter table pass
	# through unchanged rather than erroring.
	session._action({"action": "settings", "settings": {"language": "en"}})
	session.world.set_settings(session.settings)
	check(session.world._t("확보") == "SECURE", "AC: world_view status/badge translation table missed a known key under language=en")
	check(session._tr("먼저 대원을 선택하세요.") == "Select an operator first.", "AC: main.gd toast translation table missed a known key under language=en")
	check(session.world._t("알 수 없는 텍스트") == "알 수 없는 텍스트", "AC: an untranslated string was corrupted instead of passed through")
	session._action({"action": "settings", "settings": {"language": "ko"}})
	session.world.set_settings(session.settings)
	check(session.world._t("확보") == "확보", "AC: switching back to language=ko did not restore the Korean status text")

	session.queue_free()
	await process_frame
	print("BREACH_BINDINGS_INPUT_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
