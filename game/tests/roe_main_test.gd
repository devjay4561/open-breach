extends SceneTree
## Real controller/renderer integration. JSON intentions and physical input
## share the public command API; only bridge transport is recorded.
const MainScene = preload("res://main.tscn")
const Fixture = preload("res://tests/roe_browser_preflight_test.gd")
const STEP := 1.0 / 30.0
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
	# Deferred loading needs scene frames, never elapsed gameplay time.
	for _frame: int in range(8):
		await process_frame
		session._process(0.0)
		if session._loading_request.is_empty() and not session._loading_finished: return
	check(false,"JSON import settles within bounded zero-delta scene frames")

func load_fixture(session: Node, roe: String) -> void:
	bridge(session,{"action":"import_mission","data":Fixture.fixture(roe)})
	await settle_loading(session)
	check(session.mode=="PLANNING" and session.sim.tick==0,"Authored ROE mission imports into actual planning")
	check(last(session,"state").get("roe","")==roe,"Public state acknowledges actual authored ROE")
	bridge(session,{"action":"select","unit_id":"alpha"})

func run() -> void:
	var session: Node = MainScene.instantiate()
	session.set_script(RecordingMain)
	root.add_child(session)
	session.set_process(false)
	await process_frame
	await load_fixture(session,"precision")
	_precision(session)
	await load_fixture(session,"high_intensity")
	_wall_info(session)
	await _high_intensity(session)
	await _legacy_and_cache(session)
	session.queue_free()
	await process_frame
	print("BREACH_ROE_MAIN_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _precision(session: Node) -> void:
	check(session._equipment_cycle()==["stun","smoke","breach"],"Precision preserves the original equipment-key cycle")
	var before: Dictionary = session.sim.snapshot(true)
	bridge(session,{"action":"settings","settings":{"language":"en"}})
	bridge(session,{"action":"tool","tool":"frag"})
	check(session.tool=="frag","Frag intention remains frag even when unavailable under ROE")
	session.gamepad_cursor=Vector2(Fixture.TARGET[0],Fixture.TARGET[1])
	session.gamepad_cursor_active=true
	session._handle_gamepad_button(JOY_BUTTON_A)
	check(session.sim.snapshot(true)==before,"Gamepad frag rejection cannot fall through to MOVE or change the plan")
	check(last(session,"toast").get("i18n_key","")=="frag.forbidden" and last(session,"toast").get("message","")=="Fragmentation grenades are unavailable under precision ROE.","Native rejection keeps the paired English message and i18n key")
	bridge(session,{"action":"command","type":"THROW_FRAG","args":{"target":Fixture.TARGET}})
	check(session.sim.snapshot(true)==before,"Direct primitive rejection preserves the full authority state")
	bridge(session,{"action":"insert","unit_id":"alpha","index":0,"type":"THROW_FRAG","args":{"target":Fixture.TARGET}})
	check(session.sim.snapshot(true)==before,"Insertion obeys the same precision restriction atomically")
	bridge(session,{"action":"command","type":"THROW_STUN","args":{"target":Fixture.TARGET}})
	check(session.sim.units[0].commands.size()==1 and session.sim.units[0].commands[0].type=="THROW_STUN","Existing flash command remains available under precision")

func _wall_info(session: Node) -> void:
	var info: Dictionary = session._door_info("entry")
	check(info.walls.size()==2 and info.walls[0].id=="jamb_concrete" and info.walls[1].id=="jamb_thin","Authored jamb wall cache has a stable ID order")
	check(info.rifle_budget==session.sim._weapon_penetration({"weapon":"standard","current_weapon":"standard"}),"Structural UI reads the actual production rifle wall budget")
	for wall: Dictionary in info.walls:
		var authored: Dictionary = session.active_mission.walls.filter(func(record: Dictionary)->bool:return record.id==wall.id)[0]
		check(wall.resistance==session.sim.nav.obstacle_resistance(authored) and wall.rifle_penetrable==(wall.resistance<=info.rifle_budget),"Wall overrides and thin defaults come from Navigation")
	check(info.walls[1].material=="" and info.walls[1].thin and info.walls[1].rifle_penetrable and not info.walls[0].rifle_penetrable,"Unspecified thin wall is explicit and concrete remains blocked")
	info.walls[0].material="mutated"
	check(session._door_info("entry").walls[0].material=="concrete","Returned structural info owns its nested dictionaries")
	session._open_context({"target":"door","id":"entry"},Vector2(30,30))
	check(last(session,"context").get("door_info",{})==session._door_info("entry"),"Door context carries exactly the cached structural payload")
	session._close_context()
	session.world.set_interaction({"kind":"hover","target":"door","id":"entry","actions":["OPEN_DOOR"],"door_info":session._door_info("entry")})
	session.world.display(session.shown,"alpha",true,0.0)
	check(session.world._door_wall_hint(session._door_info("entry")).contains("Thin wall") and session.world._door_wall_hint(session._door_info("entry")).contains("Rifle blocked"),"Native English label uses the same explicit wall information")
	var screen: Vector2 = session.world.camera.unproject_position(session.world.surface_position(Vector2(10,5.8),0.1))
	var motion := InputEventMouseMotion.new()
	motion.position=screen
	session._mouse_motion(motion)
	check(last(session,"hover").get("door_info",{})==session._door_info("entry"),"Physical door hover carries the same structural payload as context")
	check(not JSON.stringify(session._door_info("entry")).contains("unseen") and not JSON.stringify(session._door_info("entry")).contains("state"),"Structural information cannot carry hidden NPC or live leaf state")
	var raised: Dictionary = Fixture.fixture("high_intensity")
	for room: Dictionary in raised.rooms: room["base_height"]=6.0
	for wall: Dictionary in raised.walls: wall["base_height"]=6.0
	session._build_door_wall_info(raised)
	check(session._door_info("entry").walls.size()==2,"An authored raised room supplies rifle floor height when a door omits its optional base")
	session._build_door_wall_info(session.active_mission)

func _high_intensity(session: Node) -> void:
	check(session._equipment_cycle()==["stun","smoke","breach","frag"],"High intensity appends frag to the preserved legacy cycle")
	bridge(session,{"action":"tool","tool":"frag"})
	var screen: Vector2 = session.world.camera.unproject_position(session.world.surface_position(Vector2(Fixture.TARGET[0],Fixture.TARGET[1]),0.0))
	var motion := InputEventMouseMotion.new()
	motion.position=screen
	var before: Dictionary = session.sim.snapshot(true)
	session._mouse_motion(motion)
	check(session.sim.snapshot(true)==before,"Native frag hover is read-only")
	check(session.world._interaction.get("tool","")=="frag" and session.world._interaction.get("valid",false) and session.world._interaction.radius==session.sim.EquipmentCatalog.frag_stats().radius,"Native hover renders the authoritative profile preview")
	var click := InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_LEFT
	click.pressed=true
	click.position=screen
	session._apply_unhandled_input(click)
	check(session.sim.units[0].commands.size()==1 and session.sim.units[0].commands[0].type=="THROW_FRAG" and session.tool=="select","Physical pointer commits the new primitive and exits the tool")
	bridge(session,{"action":"update","unit_id":"alpha","index":0,"args":{"target":[8.0,5.8]}})
	check(session.sim.units[0].commands[0].args.target==[8.0,5.8],"Actual queue editor changes the pending grenade landing point")
	before=session.sim.snapshot(true)
	bridge(session,{"action":"update","unit_id":"alpha","index":0,"args":{"target":[19.0,5.8]}})
	check(session.sim.snapshot(true)==before and last(session,"toast").get("i18n_key","")=="frag.range","Invalid grenade edit leaves the complete plan intact")
	var plan: Dictionary = session._export_plan()
	check(plan.schema_version==1 and plan.units[0].commands[0].type=="THROW_FRAG" and plan.units[0].commands[0].args.keys()==["target"],"Saved plan retains schema 1 and only canonical primitive arguments")
	bridge(session,{"action":"load_plan","data":plan})
	await settle_loading(session)
	check(Fixture.canonical(session._export_plan())==Fixture.canonical(plan),"Actual saved plan import/export preserves the grenade exactly")
	bridge(session,{"action":"toggle"})
	var saw_projectile := false
	for _tick: int in range(90):
		session._process(STEP)
		if not session.world._frag_projectile_nodes.is_empty():
			saw_projectile=true
			check(session.world._flash_projectile_nodes.is_empty(),"Frag projectile uses a separate presentation collection")
	check(saw_projectile,"Actual fixed-step controller execution renders the own projectile")
	check(session.sim.units[0].commands[0].state=="SUCCEEDED" and session.sim.units[0].frags==0 and session.world._frag_projectile_nodes.is_empty(),"Detonation completes the primitive and removes its own projectile marker")
	var effects: Array = session.messages.filter(func(message: Dictionary)->bool:return message.get("type","")=="fx" and message.get("kind","")=="frag")
	check(effects.size()==1 and effects[0].radius==session.sim.EquipmentCatalog.frag_stats().radius,"Own detonation produces exactly one profile-sized bridge FX")
	check(not JSON.stringify(effects).contains("unseen") and not JSON.stringify(effects).contains("affected"),"Own blast FX never exposes hidden victims")
	var event: Dictionary = session.sim.snapshot(false).events.filter(func(record: Dictionary)->bool:return record.type=="FRAG")[0]
	var message_count: int = effects.size()
	session._dispatch_fx(session.sim.snapshot(false))
	check(session.messages.filter(func(message: Dictionary)->bool:return message.get("type","")=="fx" and message.get("kind","")=="frag").size()==message_count,"Repeated snapshot cannot duplicate grenade FX")
	# A replay/seek owns its clock. Future occurrence stays pending, then
	# becomes visible once; its own height/radius need no NPC reconstruction.
	session.last_fx_seq=0
	session._dispatch_fx({"events":[event],"presentation_time":float(event.time)-STEP})
	check(session.last_fx_seq==0,"Future grenade occurrence is held by the presentation clock")
	session._dispatch_fx({"events":[event],"presentation_time":float(event.time)})
	check(session.last_fx_seq==int(event.seq),"Grenade occurrence releases at its recorded clock")
	session.world._clear_flashes()
	session.world._clock=float(event.time)+0.1
	session.world._restore_flash_visuals({"events":[event]})
	check(session.world._flashes.size()==1 and session.world._flashes[0].type=="frag" and session.world._flashes[0].target_height==event.target_height,"Seek reconstructs only the currently active own blast at its recorded height")
	session.world._clear_flashes()
	session.world._clock=float(event.time)+0.6
	session.world._restore_flash_visuals({"events":[event]})
	check(session.world._flashes.is_empty(),"Seek past blast lifetime creates no historical effect")

func _legacy_and_cache(session: Node) -> void:
	var data: Dictionary = Fixture.fixture("high_intensity")
	data.id="ROE_CACHE_UI"
	data.walls[0]["material"]="drywall"
	data.walls[0]["resistance"]=1.0
	data.walls[0]["penetration_resistance"]=0.1
	data.walls[1]["base_height"]=3.0
	bridge(session,{"action":"import_mission","data":data})
	await settle_loading(session)
	var info: Dictionary = session._door_info("entry")
	check(info.walls.size()==1 and info.walls[0].resistance==1.0 and not info.walls[0].rifle_penetrable,"Mission reload invalidates the cache, honors resistance precedence and excludes walls above the rifle")
	data=Fixture.fixture("precision")
	data.id="ROE_LEGACY_UI"
	data.schema_version=1
	data.erase("roe")
	for unit: Dictionary in data.units: unit.equipment={"stun":1}
	bridge(session,{"action":"import_mission","data":data})
	await settle_loading(session)
	check(last(session,"state").get("roe","")=="precision" and session._equipment_cycle()==["stun","smoke","breach"],"Missing legacy ROE safely displays precision and retains the original cycle")
	check(not session.sim.snapshot(false).has("frag_projectiles") and not session.sim.snapshot(false).units[0].has("frags"),"Legacy simulation shape does not gain synthetic grenade fields")
