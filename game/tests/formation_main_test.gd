extends SceneTree
## P4 tests the actual controller/scene, queued JSON intentions, own-command
## restoration and fixed-step execution. Only browser transport is recorded.
const MainScene = preload("res://main.tscn")
const Fixture = preload("res://tests/formation_browser_preflight_test.gd")
const Simulation = preload("res://scripts/simulation.gd")
const Schema = preload("res://scripts/mission_schema.gd")
const World = preload("res://scripts/world_view.gd")
const STEP := 1.0 / 30.0
const IDS := ["alpha", "bravo", "charlie", "delta"]
var checks := 0
var failures: Array[String] = []

class RecordingMain extends "res://scripts/main.gd":
	var messages: Array[Dictionary] = []
	func _emit(message: Dictionary) -> void:
		messages.append(message.duplicate(true))

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func last(session: Node, type: String) -> Dictionary:
	for index: int in range(session.messages.size()-1,-1,-1):
		if str(session.messages[index].get("type",""))==type: return session.messages[index]
	return {}

func bridge(session: Node, action: Dictionary) -> void:
	session._on_web_message([JSON.stringify(action)])
	session._flush_inputs()

func settle_loading(session: Node) -> void:
	# The controller deliberately paints two scene frames before expensive
	# imports. These bounded zero-delta frames initialize UI/scene work only;
	# all gameplay below advances with the fixed STEP.
	for _frame: int in range(8):
		await process_frame
		session._process(0.0)
		if session._loading_request.is_empty() and not session._loading_finished: return
	check(false,"Real deferred import settles within its bounded scene frames")

func group(session: Node) -> void:
	bridge(session,{"action":"select","id":""})
	for id: String in IDS: bridge(session,{"action":"select","unit_id":id,"extend":true})

func queues(session: Node) -> Variant:
	return Fixture.canonical(session.sim.snapshot(false).units.map(func(unit: Dictionary)->Dictionary:return {"id":unit.id,"commands":unit.commands}))

func rngs(session: Node) -> Array:
	return [session.sim._rng.state,session.sim._hit_region_rng.state,session.sim._breach_rng.state,session.sim._surrender_rng.state]

func request(session: Node, id: String = "main-preview", options: Dictionary = {}) -> Dictionary:
	bridge(session,{"action":"formation_preview","target":Fixture.destination("wide"),"kind":"AUTO","order":IDS,"options":options,"preview_id":id})
	var message := last(session,"formation_preview")
	check(str(message.get("preview_id",""))==id,"Preview echoes the exact editor request correlation")
	return message.get("data",{})

func load_fixture(session: Node) -> bool:
	var data := Fixture.fixture("wide","verbal")
	var probe := Simulation.new()
	probe.load_mission(data)
	var preview: Dictionary = probe.formation_preview(Fixture.destination("wide"),"AUTO",IDS,{})
	check(bool(preview.get("ok",false)),"Main fixture's authored route accepts a public static preview")
	if not bool(preview.get("ok",false)): return false
	data.interactive_targets = []
	var target_ids: Array = []
	for slot: Dictionary in preview.slots:
		var id := "finish_"+str(slot.unit_id)
		target_ids.append(id)
		data.interactive_targets.append({"id":id,"x":slot.target[0],"z":slot.target[1],"w":0.25,"d":0.25,"label":id.to_upper(),"action":"inspect","duration":2.0})
	data.win = [{"type":"targets_complete","targets":target_ids}]
	check(bool(Schema.check(data).get("ok",false)),"Actual controller fixture passes the authored mission schema")
	bridge(session,{"action":"import_mission","data":data})
	await settle_loading(session)
	check(session.mode=="PLANNING" and session.sim.tick==0 and session.sim.time==0.0,"Actual JSON import initializes planning with no catch-up gameplay")
	group(session)
	return true

func run() -> void:
	var session: Node = MainScene.instantiate()
	session.set_script(RecordingMain)
	root.add_child(session)
	session.set_process(false)
	await process_frame
	if await load_fixture(session):
		await _elevation(session)
		_preview_and_input(session)
		var baseline: Dictionary = await _commit_and_restore(session)
		if not baseline.is_empty():
			await _edits(session,baseline)
			await _execution(session,baseline,false)
			await _execution(session,baseline,true)
	session.queue_free()
	await process_frame
	print("BREACH_FORMATION_MAIN_RESULT checks=%d failures=%d"%[checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _elevation(session: Node) -> void:
	var data: Dictionary = session.active_mission.duplicate(true)
	var preview := request(session,"floor-zero")
	session.world.display(session.shown,"alpha",true,0.0)
	var arrays: Array = session.world._drill_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays.size()>Mesh.ARRAY_VERTEX else PackedVector3Array()
	var labels: Array = session.world._drill_labels.map(func(label: Label3D)->Vector3:return label.position)
	check(not vertices.is_empty() and labels.size()==8,"Actual planning display builds mesh vertices and labels before elevation")
	var raised: Dictionary = data.duplicate(true)
	raised.rooms=[{"id":"raised_floor","x":10.0,"z":9.0,"w":20.0,"d":18.0,"indoor":true,"base_height":9.0}]
	check(bool(Schema.check(raised).get("ok",false)),"Nine-metre indoor floor is authored schema-valid geometry")
	session.world.build(raised)
	for slot: Dictionary in preview.slots: slot.floor_height=9.0
	session.world.set_formation_preview(preview)
	session.world.display(session.shown,"alpha",true,0.0)
	arrays=session.world._drill_mesh.surface_get_arrays(0)
	var elevated: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays.size()>Mesh.ARRAY_VERTEX else PackedVector3Array()
	check(elevated.size()==vertices.size() and not elevated.is_empty(),"Actual raised planning display retains the full formation mesh")
	if elevated.size()==vertices.size():
		for index: int in range(vertices.size()):
			# Vector3 is the renderer's binary32 representation. The expected
			# single floor addition uses the identical representation, no epsilon.
			check(elevated[index]==vertices[index]+Vector3(0.0,9.0,0.0),"Every formation vertex receives the authored elevation exactly once")
	check(session.world._drill_labels.size()==labels.size(),"Raised display retains every actual slot label")
	for index: int in range(mini(labels.size(),session.world._drill_labels.size())):
		check(session.world._drill_labels[index].position==labels[index]+Vector3(0.0,9.0,0.0),"Formation label uses the same single floor elevation as its mesh")
	session.world.build(data)
	session.world.display(session.shown,"alpha",true,0.0)
	# A corridor macro preserves an independently configured own posture.
	bridge(session,{"action":"unit_posture","unit_id":"alpha","settings":{"stance":"crouched"}})
	var crouched := request(session,"owned-crouch")
	check(crouched.slots[0].stance=="crouched","Public non-T preview retains the actual owned crouched stance")
	bridge(session,{"action":"unit_posture","unit_id":"alpha","settings":{"stance":"standing"}})

func _preview_and_input(session: Node) -> void:
	var before: Variant = queues(session)
	var rng := rngs(session)
	var sequence: int = session.sim._command_sequence
	var preview := request(session)
	check(bool(preview.get("ok",false)) and preview.slots.size()==4 and preview.source_unit_id=="delta","Actual bridge returns the resolved four-person preview and last-rank source")
	check(queues(session)==before and rngs(session)==rng and session.sim._command_sequence==sequence and session.sim.tick==0,"Preview leaves all command IDs, random streams and clock unchanged")
	check(Fixture.canonical(session.world._formation_preview)==Fixture.canonical(preview),"World renders exactly the public preview data")
	check(not JSON.stringify(preview).contains("unseen") and not JSON.stringify(preview).contains("enemies") and not JSON.stringify(preview).contains("room_states"),"Preview cannot carry hidden actors or private room control")
	bridge(session,{"action":"select","unit_id":"alpha","preserve_group":true})
	check(session.selected=="alpha" and session.selected_units==IDS,"Primary focus changes without replacing the selected own group")
	bridge(session,{"action":"select","unit_id":"unseen","extend":true})
	check(session.selected_units==IDS,"A hidden non-owned ID cannot join the formation group")
	# A queued toolbar intention must precede a same-frame map gesture.
	session._on_web_message([JSON.stringify({"action":"tool","tool":"formation"})])
	var location := Vector2(8.0,4.0)
	var point: Vector2 = session.world.camera.unproject_position(session.world.surface_position(location,0.03))
	var motion := InputEventMouseMotion.new();motion.position=point
	session._unhandled_input(motion)
	check(session.tool=="formation" and not session.world._formation_preview.is_empty() and queues(session)==before,"Native formation hover processes FIFO tool selection and remains a pure preview")
	var click := InputEventMouseButton.new();click.position=point;click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	session._unhandled_input(click)
	var target := last(session,"formation_target")
	check(target.get("target") is Array and target.target.size()==2 and target.get("order",[])==IDS and queues(session)==before,"Actual floor click opens an editor target with the own group and no primitive mutation")
	bridge(session,{"action":"formation_preview","clear":true,"preview_id":"cancel-preview"})
	check(last(session,"formation_preview").get("preview_id","")=="cancel-preview" and last(session,"formation_preview").get("data",{}).is_empty() and session.world._formation_preview.is_empty(),"Editor cancellation correlates its ACK and clears the native ghost")
	request(session,"switch-preview")
	bridge(session,{"action":"tool","tool":"move"})
	check(session.world._formation_preview.is_empty(),"Switching tools cannot retain a stale formation ghost")
	for key: int in [KEY_F,KEY_Q,KEY_E,KEY_C,KEY_G]:
		request(session,"native-key-"+str(key))
		var event := InputEventKey.new();event.physical_keycode=key;event.pressed=true
		session._unhandled_input(event)
		check(session.world._formation_preview.is_empty() and queues(session)==before,"A real native binding clears the formation ghost without issuing macro commands")
	request(session,"malformed-options")
	bridge(session,{"action":"formation_preview","target":[8.0,4.0],"kind":"AUTO","order":IDS,"options":[],"preview_id":"bad-options"})
	check(session.world._formation_preview.is_empty() and queues(session)==before,"Malformed preview options clear the stale ghost and preserve every queue")
	request(session,"group-preview")
	bridge(session,{"action":"select","unit_id":"alpha"})
	check(session.selected_units==["alpha"] and session.world._formation_preview.is_empty(),"A plain card selection collapses the group and clears stale preview")
	group(session)
	before=queues(session)
	bridge(session,{"action":"formation","target":[8.0,4.0],"kind":"ROLLING_T","order":["alpha","alpha"],"options":{},"preview_id":"invalid-team"})
	check(queues(session)==before and session.world._formation_preview.is_empty(),"An invalid macro atomically preserves queues and clears its invalid ghost")
	request(session,"mode-preview")
	session.mode="REPLAY"
	bridge(session,{"action":"formation_preview","target":[8.0,4.0],"kind":"AUTO","order":IDS,"preview_id":"wrong-mode"})
	check(queues(session)==before and last(session,"formation_preview").get("preview_id","")!="wrong-mode","Replay cannot authorize planning mutation")
	session.mode="PLANNING"
	bridge(session,{"action":"formation_preview","clear":true,"preview_id":"mode-clear"})

func _commit_and_restore(session: Node) -> Dictionary:
	var before_rng := rngs(session)
	bridge(session,{"action":"formation","target":[8.0,4.0],"kind":"AUTO","order":IDS,"options":{"append":true,"signal":"B","delay_ticks":3},"preview_id":"commit"})
	check(session.sim.units.all(func(unit: Dictionary)->bool:return not unit.commands.is_empty()),"Actual controller commits the full primitive draft for every member")
	check(session.tool=="select" and not session.world._formation_preview.is_empty(),"Successful commit returns to selection while preserving its editable ghost")
	check(session.sim.tick==0 and rngs(session)==before_rng,"Planning commit consumes neither simulation time nor random streams")
	var plan: Dictionary = Fixture.canonical(session._export_plan())
	check(plan.schema_version==1 and plan.kind=="breach-plan" and plan.units.all(func(unit: Dictionary)->bool:return unit.commands.all(func(command: Dictionary)->bool:return command.type in ["MOVE","FACE","WAIT_FOR_SIGNAL"] and command.args.has("formation"))),"Plan schema remains version 1 and stores only expanded existing primitives")
	# Canonicalize the initial baseline through the same real roster-grouped
	# import as retry. Full ID/sequence/state comparisons below remain strict.
	bridge(session,{"action":"load_plan","data":plan})
	await settle_loading(session)
	check(session.mode=="PLANNING" and session.sim.tick==0 and session.sim.units.all(func(unit: Dictionary)->bool:return unit.commands.all(func(command: Dictionary)->bool:return command.state=="PENDING")),"Real imported primitive plan is a fresh canonical baseline")
	check(Fixture.canonical(session._export_plan().units)==plan.units,"Whole primitive args and per-unit settings survive the actual JSON import")
	session._restore_formation_preview()
	var restored: Dictionary = session.world._formation_preview
	check(bool(restored.get("ok",false)) and restored.get("slots",[]).size()==4 and restored.source_unit_id=="delta","Controller restores formation presentation from owned expanded commands")
	check(Fixture.canonical(restored)==Fixture.canonical(World.formation_from_commands(session.shown,str(restored.sync_id))),"Restored preview matches every actual primitive route and FACE")
	return plan

func _edits(session: Node, baseline: Dictionary) -> void:
	var unit: Dictionary = session.sim.units[1]
	var face_index := -1
	var move_index := -1
	for index: int in range(unit.commands.size()):
		if unit.commands[index].args.formation.stage=="cover": face_index=index
		if unit.commands[index].type=="MOVE" and unit.commands[index].args.formation.stage=="move": move_index=index
	check(face_index>=0 and move_index>=0,"Actual expanded queue exposes editable final MOVE and FACE primitives")
	if face_index<0 or move_index<0: return
	var face_args: Dictionary = unit.commands[face_index].args.duplicate(true)
	face_args.target = [float(face_args.target[0])+0.2,float(face_args.target[1])]
	bridge(session,{"action":"update","unit_id":"bravo","index":face_index,"args":face_args})
	var move_args: Dictionary = unit.commands[move_index].args.duplicate(true)
	move_args.target = [float(move_args.target[0])+0.1,float(move_args.target[1])]
	bridge(session,{"action":"update","unit_id":"bravo","index":move_index,"args":move_args})
	session._restore_formation_preview()
	var slot: Dictionary = session.world._formation_preview.slots.filter(func(row: Dictionary)->bool:return row.unit_id=="bravo")[0]
	check(slot.face_target==Fixture.canonical(face_args.target) and slot.target==Fixture.canonical(move_args.target),"Preview restoration preserves edited primitive targets instead of recalculating geometry")
	check(slot.sector.radius==4.0 and slot.sector.start==face_args.sector.start and slot.sector.end==face_args.sector.end,"Edited FACE preserves the full four-metre fan radius and exact angle args")
	# Main's real waypoint release sends only {target}. The public update API
	# must preserve the independent macro metadata as it already does for drill.
	var partial_target := [float(move_args.target[0])+0.05,float(move_args.target[1])-0.025]
	var expected_partial: Dictionary = move_args.duplicate(true)
	expected_partial.target=partial_target
	var before_rng := rngs(session)
	bridge(session,{"action":"update","unit_id":"bravo","index":move_index,"args":{"target":partial_target}})
	check(Fixture.canonical(unit.commands[move_index].args)==Fixture.canonical(expected_partial),"Target-only public waypoint edit retains the entire exact formation metadata and updated target")
	check(rngs(session)==before_rng and session.sim.tick==0,"Target-only waypoint edit consumes neither clock nor any RNG stream")
	session._restore_formation_preview()
	slot=session.world._formation_preview.slots.filter(func(row: Dictionary)->bool:return row.unit_id=="bravo")[0]
	check(slot.target==Fixture.canonical(partial_target) and slot.unit_id=="bravo" and slot.index==2,"Partial waypoint edit remains visible in its same owned formation rank")
	# Removing every stack MOVE must use the actual own approach consistently,
	# both with a cached preview and after importing only primitive commands.
	var alpha: Dictionary = session.sim.units[0]
	for index: int in range(alpha.commands.size()-1,-1,-1):
		if alpha.commands[index].type=="MOVE" and alpha.commands[index].args.formation.stage=="stack":
			bridge(session,{"action":"remove","unit_id":"alpha","index":index})
	session._restore_formation_preview()
	var removed_stack: Dictionary = session.world._formation_preview.slots.filter(func(row: Dictionary)->bool:return row.unit_id=="alpha")[0]
	check(removed_stack.stack_route.is_empty() and removed_stack.stack==removed_stack.approach and removed_stack.stack==[8.0,11.0],"Deleting all stack MOVE nodes restores the actual own approach")
	# Delete only DELTA's advance MOVE nodes, preserving its ready/cover history.
	var removed := 0
	var delta: Dictionary = session.sim.units[3]
	for index: int in range(delta.commands.size()-1,-1,-1):
		if delta.commands[index].type=="MOVE" and delta.commands[index].args.formation.stage=="move":
			bridge(session,{"action":"remove","unit_id":"delta","index":index})
			removed+=1
	session._restore_formation_preview()
	slot=session.world._formation_preview.slots.filter(func(row: Dictionary)->bool:return row.unit_id=="delta")[0]
	check(removed>0 and slot.deleted_move and slot.move_route.is_empty() and slot.target==slot.stack,"Deleted movement remains deleted in restored presentation")
	var edited: Dictionary = Fixture.canonical(session._export_plan())
	bridge(session,{"action":"load_plan","data":edited})
	await settle_loading(session)
	check(Fixture.canonical(session._export_plan().units)==edited.units,"Edited/deleted primitive plan survives full exact JSON roundtrip")
	session._restore_formation_preview()
	var imported_stack: Dictionary = session.world._formation_preview.slots.filter(func(row: Dictionary)->bool:return row.unit_id=="alpha")[0]
	check(imported_stack.stack==removed_stack.stack and imported_stack.approach==removed_stack.approach and imported_stack.stack_route.is_empty(),"All-stack deletion retains exactly the same approach after real primitive import")
	var imported_partial: Dictionary = session.world._formation_preview.slots.filter(func(row: Dictionary)->bool:return row.unit_id=="bravo")[0]
	check(imported_partial.target==Fixture.canonical(partial_target) and imported_partial.index==2,"Target-only edited formation survives actual primitive plan import and World restoration")
	var imported_move: Dictionary = session.sim.units[1].commands.filter(func(command: Dictionary)->bool:return command.type=="MOVE" and command.args.get("formation",{}).get("stage","")=="move").back()
	check(Fixture.canonical(imported_move.args)==Fixture.canonical(expected_partial),"Imported target-only edit preserves every macro metadata field exactly")
	bridge(session,{"action":"load_plan","data":baseline})
	await settle_loading(session)

func _waiting(session: Node) -> bool:
	var waits: Array = []
	for unit: Dictionary in session.sim.units: waits.append_array(unit.commands.filter(func(command: Dictionary)->bool:return command.type=="WAIT_FOR_SIGNAL"))
	return waits.size()==4 and waits.all(func(command: Dictionary)->bool:return command.state=="WAITING")

func _execution(session: Node, baseline: Dictionary, explicit_sender: bool) -> void:
	bridge(session,{"action":"load_plan","data":baseline})
	await settle_loading(session)
	group(session)
	bridge(session,{"action":"select","unit_id":"alpha","preserve_group":true})
	var initial: Variant = queues(session)
	bridge(session,{"action":"toggle"})
	var ready_tick := -1
	for _frame: int in range(900):
		session._process(STEP)
		if _waiting(session): ready_tick=session.sim.tick;break
	check(ready_tick>0 and session.mode=="EXECUTING","Real controller reaches the shared ready barrier: "+JSON.stringify({"mode":session.mode,"tick":session.sim.tick,"result":session.sim.result,"units":session.sim.units.map(func(unit: Dictionary)->Dictionary:return {"id":unit.id,"x":unit.x,"z":unit.z,"commands":unit.commands.map(func(command: Dictionary)->Dictionary:return {"type":command.type,"state":command.state,"args":command.args})})}))
	if ready_tick<0: return
	var before: Variant = queues(session)
	var events: Variant = Fixture.canonical(session.sim.events)
	var rng := rngs(session)
	bridge(session,{"action":"signal","channel":"B","sender_id":"unseen"})
	check(queues(session)==before and Fixture.canonical(session.sim.events)==events and rngs(session)==rng,"Explicit invalid sender cannot fall back to the selected or last-rank operator")
	var intent := {"action":"signal","channel":"B"}
	if explicit_sender: intent["sender_id"]="alpha"
	bridge(session,intent)
	for _frame: int in range(1800):
		session._process(STEP)
		if session.mode=="RESULT": break
	check(session.mode=="RESULT" and bool(session.sim.result.get("success",false)) and session.sim.command_failures==0,"Actual Main finishes the complete real formation without failures")
	check(session.sim.units.all(func(unit: Dictionary)->bool:return unit.commands.all(func(command: Dictionary)->bool:return command.state=="SUCCEEDED")),"Every actual MOVE/FACE/barrier succeeds before RESULT")
	var signals: Array = session.sim.events.filter(func(event: Dictionary)->bool:return event.type=="SIGNAL")
	check(signals.size()==1 and signals[0].get("source_unit_id","")==("alpha" if explicit_sender else "delta"),"Actual source obeys explicit valid sender or stable last rank independently of selected primary")
	var state := last(session,"state")
	check(state.get("enemies",[]).all(func(enemy: Dictionary)->bool:return enemy.id!="unseen") and state.room_states.sealed.state=="UNKNOWN" and not state.room_states.sealed.observed,"Native RESULT retains hidden-room privacy")
	var full: Dictionary = session.recorder.seek(session.recorder.duration,true)
	check(full.enemies.any(func(enemy: Dictionary)->bool:return enemy.id=="unseen"),"Full recording retains the hidden entity for explicit replay reveal")
	var final_units: Variant = Fixture.canonical(session.sim.snapshot(false).units)
	# Numeric-state-v1 has always filled missing legacy numeric realism keys.
	# This quiet fixture has no exposure property in its live own rows; retain
	# every original field and explicitly require the decoder's exposure=1.
	check(final_units.all(func(unit: Dictionary)->bool:return not unit.has("exposure")),"Quiet live own rows omit the optional legacy exposure property")
	var replay_units: Array = final_units.map(func(unit: Dictionary)->Dictionary:
		var expected: Dictionary = unit.duplicate(true)
		expected["exposure"] = 1.0
		return expected)
	var final_tick: int = session.sim.tick
	bridge(session,{"action":"replay"})
	await settle_loading(session)
	bridge(session,{"action":"pause"})
	bridge(session,{"action":"replay_seek","time":session.recorder.duration})
	check(session.mode=="REPLAY" and Fixture.canonical(session.shown.units)==Fixture.canonical(replay_units) and int(session.shown.tick)==final_tick,"Exact final replay seek retains every live command ID, sequence, posture, value and declared legacy exposure default")
	bridge(session,{"action":"retry_plan"})
	await settle_loading(session)
	check(queues(session)==initial and session.sim.tick==0 and session.sim.time==0.0,"Retry reconstructs the identical canonical whole-unit primitive baseline with IDs")
