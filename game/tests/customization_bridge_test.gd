extends SceneTree
const Main = preload("res://main.tscn")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	var session: Node = Main.instantiate()
	root.add_child(session)
	session.set_process(false)
	await process_frame
	var profile := {"weapon": "light", "sidearm": "pico_p1", "armor": "swift_v3", "helmet": "crown_h2", "attachments": ["dot", "extended_mag"], "equipment": {"stun": 1, "probe_c1": 1}, "appearance": {"name": "핀치", "callsign": "F-2", "color": "#40516c", "patch": "arrow"}, "preset": "custom"}
	session.mode = "MENU"
	var before := JSON.stringify(session.sim.snapshot(true))
	session._action({"action": "preview_operator", "roster_id": "finch", "profile": profile, "rect": {"x": 100, "y": 80, "width": 240, "height": 200}})
	check(JSON.stringify(session.sim.snapshot(true)) == before, "Briefing gear preview mutated live simulation state")
	check(is_instance_valid(session.world._operator_preview_layer) and session.world._operator_preview_layer.visible, "3D operator preview did not appear")
	var preview = session.world._operator_preview_viewport
	check(preview.own_world_3d and preview.size == Vector2i(mini(240, int(root.size.x)), mini(200, int(root.size.y))), "Operator preview did not use its isolated, bounded viewport")
	check(not preview.transparent_bg, "Equipment portrait exposes the live mission behind the selected operator")
	session.mode = "RESULT"
	session._action({"action":"preview_operator","profile":null})
	check(not session.world._operator_preview_layer.visible, "Closing a result-screen portrait hides the preview")
	session._action({"action":"preview_operator","profile":profile,"rect":{"x":100,"y":80,"width":240,"height":200}})
	check(session.mode == "RESULT" and session.world._operator_preview_layer.visible and JSON.stringify(session.sim.snapshot(true)) == before, "Result-screen gear preview appears without replacing the completed mission")
	session.mode = "MENU"
	session._action({"action": "preview_operator", "profile": profile, "rect": {"x": 105, "y": 85, "width": 250, "height": 210}})
	check(session.world._operator_preview_viewport == preview and preview.size == Vector2i(mini(250, int(root.size.x)), mini(210, int(root.size.y))), "Scrolling a preview rebuilt its 3D scene")
	session._action({"action": "preview_operator", "profile": profile, "rect": {"x": "unsafe", "width": 250}})
	check(preview.size == Vector2i(mini(250, int(root.size.x)), mini(210, int(root.size.y))), "Malformed preview coordinates changed the renderer")
	session._action({"action": "start", "mission": "M01", "loadout": {"alpha": profile}})
	check(not session.world._operator_preview_layer.visible, "Briefing preview remained visible after deployment")
	var unit: Dictionary = session.sim.units[0]
	check(unit.weapon == "light" and unit.armor == "swift_v3" and unit.helmet == "crown_h2" and unit.sidearm == "pico_p1", "Bridge discarded preparation gear slots")
	check(unit.attachments == ["dot", "extended_mag"] and unit.max_ammo == 40 and unit.appearance.callsign == "F-2", "Attachment capacity or individual identity was lost at deployment")
	var door_id := ""
	for door: Dictionary in session.shown.doors:
		if bool(door.get("observed", false)) and not bool(door.get("locked", false)):
			door_id = str(door.id)
			break
	check(not door_id.is_empty(), "Bridge fixture has no observed door")
	if not door_id.is_empty():
		session._action({"action": "command", "type": "OPEN_AND_FLASH", "args": {"door_id": door_id}})
		var index: int = unit.commands.size() - 1
		check(index >= 0 and unit.commands[index].type == "OPEN_AND_FLASH" and session.tool == "flash_target" and session.tool_insert_index == index, "Composite command did not open its landing adjustment tool")
		if index >= 0:
			var target: Array = unit.commands[index].args.target.duplicate()
			var bad_click := InputEventMouseButton.new()
			bad_click.button_index = MOUSE_BUTTON_LEFT
			bad_click.pressed = true
			bad_click.position = session.world.camera.unproject_position(session.world.surface_position(Vector2(23.0, 1.0)))
			session._unhandled_input(bad_click)
			check(unit.commands[index].args.target == target and session.tool == "flash_target", "Invalid landing click replaced the saved target or left edit mode")
			var motion := InputEventMouseMotion.new()
			motion.position = session.world.camera.unproject_position(session.world.surface_position(Vector2(float(target[0]), float(target[1]))))
			session._mouse_motion(motion)
			check(session.world._interaction.kind == "throw" and float(session.world._interaction.radius) == 3.0, "Composite target did not show its actual effect radius")
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = motion.position
			session._unhandled_input(click)
			check(session.tool == "select" and unit.commands[index].type == "OPEN_AND_FLASH" and unit.commands.size() == index + 1, "Landing adjustment added an unrelated move or throw command")
		session._action({"action": "command", "type": "SWITCH_WEAPON", "args": {"slot": "secondary"}})
		session._action({"action": "command", "type": "PEEK_CAMERA", "args": {"door_id": door_id}})
		var plan: Dictionary = session._export_plan()
		check(plan.loadout.alpha.armor == "swift_v3" and plan.units[0].commands[-1].type == "PEEK_CAMERA", "Saved plan lost gear or camera commands")
		session._import_plan(plan)
		check(session.sim.units[0].armor == "swift_v3" and session.sim.units[0].commands[0].type == "OPEN_AND_FLASH", "Imported plan did not restore composite actions and armor")
	var seek_state: Dictionary = session.sim.snapshot(true)
	seek_state["time"] = 2.15
	seek_state["tick"] = 64
	seek_state["presentation_reset"] = true
	seek_state["events"] = [{"seq": 10, "time": 2.0, "type": "STUN", "to": [unit.x, unit.z], "radius": 3.0}]
	session.world.display(seek_state, session.selected, true, 0.0)
	check(session.world._flashes.size() == 1 and absf(float(session.world._flashes[0].remaining) - 0.23) < 0.0001, "Seeking did not restore the flash visual at its actual age")
	session.queue_free()
	await process_frame
	print("BREACH_CUSTOMIZATION_BRIDGE_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
