extends SceneTree

const Schema = preload("res://scripts/mission_schema.gd")
const Replay = preload("res://scripts/replay.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
var checks: int = 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func fixture() -> Dictionary:
	return {"schema_version":1,"id":"EDIT_REALISM_CONTRACT","revision":1,"title":"Contract fixture","seed":42,"custom":true,"bounds":[12,10],"focus":[6,5],"environment":{"time_of_day":"dim","lighting":0.45},"rooms":[{"id":"room","x":6,"z":5,"w":12,"d":10,"indoor":true,"lighting":0.6,"floor_surface":"tile"}],"walls":[{"id":"wall","x":6,"z":2,"w":3,"d":0.2,"height":2.6,"base_height":0.0,"material":"concrete","opacity":1.0,"resistance":4.0}],"props":[{"id":"desk","type":"desk","x":4,"z":8,"w":1,"d":1,"height":0.8,"base_height":0.0,"material":"wood","cover":"low","opacity":1.0,"resistance":1.0}],"doors":[{"id":"door","x":6,"z":5,"w":1.6,"d":0.2,"axis":"x","state":"AJAR","progress":0.52,"hinge_side":1,"swing_sign":-1,"locked":false,"hp":70,"durability":100,"destroyed":false,"height":2.1,"material":"wood","opacity":1.0,"resistance":1.0,"initial_states":["AJAR","CLOSED","OPEN"]}],"units":[{"id":"alpha","name":"ALPHA","role":"lead","x":2,"z":5,"facing":0,"weapon":"standard","reserve_ammo":48,"stance":"crouched","movement_mode":"careful","hold_position":true}],"enemies":[{"id":"enemy","x":10,"z":5,"facing":PI,"reserve_ammo":24}],"civilians":[{"id":"civilian","x":9,"z":8,"secured":false}],"objectives":["Complete"],"win":[{"type":"neutralize_all"}],"fail":[{"type":"no_civilian_loss"}],"stars":[],"modifiers":["dim"]}

func _initialize() -> void:
	_test_schema()
	_test_replay()
	_test_legacy()
	_test_known_revision()
	print("BREACH_REALISM_CONTRACT_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_schema() -> void:
	var mission: Dictionary = fixture()
	var valid: Dictionary = Schema.check(mission)
	check(valid.get("ok",false),"All authored realism fields must validate: " + str(valid))
	if not valid.get("ok",false): return
	check(valid.data == mission,"Validation must preserve authored settings without modifying input")
	for material: String in Schema.MATERIALS:
		var candidate: Dictionary = mission.duplicate(true)
		candidate.walls[0].material = material
		check(Schema.check(candidate).get("ok",false),"Known material must validate: " + material)
	for state: String in ["CLOSED","AJAR","OPEN","DESTROYED"]:
		var candidate: Dictionary = mission.duplicate(true)
		candidate.doors[0].state = state
		if state == "DESTROYED": candidate.doors[0].hp = 0
		check(Schema.check(candidate).get("ok",false),"Authored door state must validate: " + state)
	for mutation: String in ["height","opacity","reserve_fraction","reserve_negative","stance","movement","hold","material","hinge","progress","door_candidates","environment","lighting","surface","velocity","awareness","source","unknown"]:
		var candidate: Dictionary = mission.duplicate(true)
		match mutation:
			"height": candidate.props[0].height = INF
			"opacity": candidate.walls[0].opacity = 1.1
			"reserve_fraction": candidate.units[0].reserve_ammo = 2.5
			"reserve_negative": candidate.units[0].reserve_ammo = -1
			"stance": candidate.units[0].stance = "invisible"
			"movement": candidate.units[0].movement_mode = "teleport"
			"hold": candidate.units[0].hold_position = "yes"
			"material": candidate.walls[0].material = "magic"
			"hinge": candidate.doors[0].hinge_side = 0
			"progress": candidate.doors[0].progress = 0
			"door_candidates": candidate.doors[0].initial_states = ["INVALID"]
			"environment": candidate.environment.weather = "rain"
			"lighting": candidate.environment.lighting = NAN
			"surface": candidate.rooms[0].floor_surface = "lava"
			"velocity": candidate.units[0].velocity_x = INF
			"awareness": candidate.units[0].awareness_state = "OMNISCIENT"
			"source": candidate.units[0].observation_source = "omniscient"
			"unknown": candidate.units[0].private_field = true
		check(not Schema.check(candidate).get("ok",true),"Invalid authored realism field must be rejected: " + mutation)

func replay_state() -> Dictionary:
	var unit := {"id":"alpha","kind":"unit","x":2.0,"z":5.0,"facing":0.0,"body_facing":0.4,"aim_facing":0.2,"status":"YIELDING","hp":55.0,"ammo":7,"reserve_ammo":31,"stance":"crouched","movement_mode":"careful","hold_position":true,"aim_progress":0.6,"injury_status":"wounded","mobility_multiplier":0.75,"velocity_x":-0.5,"velocity_z":0.3,"awareness_state":"IDENTIFIED","awareness_confidence":0.8,"observation_source":"sight","exposure":0.4,"aim_state":"acquiring","action_multiplier":1.3,"reload_duration":2.0,"current_weapon_height":0.9,"weapon_origin":[2.1,5.1,0.9],"_sensory_memory":{"enemy":{"x":10,"z":5}},"commands":[{"id":"alpha-0001","type":"MOVE","args":{"target":[3,5]},"state":"SUCCEEDED","resolved_target":[2.5,5],"completion_reason":"Occupied destination adjusted","_progress_best":0.1}]}
	unit["suppressed"] = 1.5
	return {"time":0.0,"tick":0,"units":[unit],"enemies":[{"id":"enemy","kind":"enemy","x":10.0,"z":5.0,"visible":false,"status":"ALERT","hp":80.0,"awareness_state":"TRACKING","awareness_confidence":0.75,"observation_source":"report"}],"civilians":[{"id":"civilian","kind":"civilian","x":9.0,"z":8.0,"visible":true,"status":"IDLE","hp":100.0}],"doors":[{"id":"door","x":6.0,"z":5.0,"w":1.6,"d":0.2,"axis":"x","state":"AJAR","progress":0.52,"hinge_side":1,"swing_sign":-1,"locked":true,"hp":70.0,"durability":100.0,"destroyed":false,"height":2.1,"material":"wood","opacity":1.0,"resistance":1.0}],"events":[{"seq":0,"tick":0,"time":0.0,"type":"DESTINATION_ADJUSTED","unit_id":"alpha","requested":[3,5],"resolved":[2.5,5]}],"result":{}}

func encoded() -> Dictionary:
	var record := Replay.new()
	record.begin(fixture())
	var state: Dictionary = replay_state()
	record.capture(state)
	state.time = 1.0
	state.tick = 30
	state.units[0].x = 3.0
	state.units[0].body_facing = 0.8
	state.units[0].aim_progress = 0.9
	state.units[0].weapon_origin = [3.1,5.1,1.1]
	state.doors[0].state = "OPEN"
	state.doors[0].progress = 1.0
	state.doors[0].destroyed = true
	state.doors[0].hp = 0
	state.events.append({"seq":1,"tick":30,"time":1.0,"type":"DOOR_DESTROYED","door_id":"door","unit_id":"alpha"})
	state.events.append({"seq":2,"tick":30,"time":1.0,"type":"SHOT","attacker_id":"alpha","target_id":"enemy","hostile":false,"hit":false,"weapon_origin":[3.1,5.1,1.1],"target_height":0.9,"transmission":0.6})
	record.finish(state)
	return JSON.parse_string(JSON.stringify(record.export_data()))

func set_sample(candidate: Dictionary, field: String, value: Variant) -> void:
	var packed: Array = candidate.frames[0][2]
	var definition: Dictionary = candidate.states[int(packed[1])]
	var index: int = definition.fields.find(field)
	check(index >= 0,"Mutation fixture must include numeric field " + field)
	if index >= 0: packed[index+2] = value

func _test_replay() -> void:
	var candidate: Dictionary = encoded()
	check(Schema.check(candidate.mission_data).get("ok",false),"Serialized custom mission must pass schema: " + str(Schema.check(candidate.mission_data)))
	var restored := Replay.new()
	var response: Dictionary = restored.load_data(candidate)
	check(response.get("ok",false),"Realism replay must import: " + str(response))
	if not response.get("ok",false): return
	var final: Dictionary = restored.seek(1.0,true)
	var expected: Dictionary = replay_state().units[0]
	for key: String in ["stance","movement_mode","hold_position","reserve_ammo","injury_status","mobility_multiplier","velocity_x","velocity_z","awareness_state","awareness_confidence","observation_source","exposure","aim_state","action_multiplier","reload_duration"]:
		check(final.units[0][key] == expected[key],"Authoritative state must round trip: " + key)
	check(final.units[0].weapon_origin == [3.1,5.1,1.1],"Weapon position must round trip without static JSON churn")
	check(final.units[0].commands[0].resolved_target == [2.5,5.0] and final.units[0].commands[0].completion_reason == expected.commands[0].completion_reason,"Adjusted destination and explanation must survive replay")
	check(final.doors[0].destroyed and final.doors[0].state == "OPEN" and final.doors[0].hp == 0 and final.doors[0].hinge_side == 1,"Destroyed fixed-hinge door must round trip")
	check(restored.data.environment == fixture().environment,"Lighting environment must round trip")
	check(final.events[-1].weapon_origin == [3.1,5.1,1.1] and final.events[-1].target_height == 0.9 and final.events[-1].transmission == 0.6,"Physical shot origin, body height and transmission must survive replay")
	check(not JSON.stringify(candidate).contains("_sensory_memory") and not JSON.stringify(candidate).contains("_progress_best"),"Private cognition and path state must not be exported")
	var middle: Dictionary = restored.seek(0.5,true)
	check(is_equal_approx(middle.units[0].body_facing,0.6) and is_equal_approx(middle.units[0].aim_progress,0.75),"Body direction and aim acquisition must interpolate")
	check(is_equal_approx(middle.units[0].weapon_origin[0],2.6),"World weapon position must interpolate numerically")
	check(restored.seek(0.5,false).enemies.is_empty(),"Observed replay must not expose unobserved awareness or position")
	var before: String = JSON.stringify(restored.export_data())
	for mutation: String in ["reserve","confidence","velocity","weapon","hinge","stance","injury","source","awareness","destroyed","environment","private","resolved","event","shot_origin","transmission"]:
		var corrupt: Dictionary = candidate.duplicate(true)
		match mutation:
			"reserve": set_sample(corrupt,"reserve_ammo",-1)
			"confidence": set_sample(corrupt,"awareness_confidence",1.1)
			"velocity": set_sample(corrupt,"velocity_x",NAN)
			"weapon": set_sample(corrupt,"weapon_origin_height",-1)
			"hinge":
				for definition: Dictionary in corrupt.states:
					if definition.group == "doors": definition.fields.append("hinge_side")
			"stance": corrupt.states[0].base.stance = "floating"
			"injury": corrupt.states[0].base.injury_status = "invulnerable"
			"source": corrupt.states[0].base.observation_source = "wallhack"
			"awareness": corrupt.states[0].base.awareness_state = "OMNISCIENT"
			"destroyed":
				for definition: Dictionary in corrupt.states:
					if definition.group == "doors": definition.base.destroyed = "yes"
			"environment": corrupt.environment.lighting = INF
			"private": corrupt.states[0].base._sensory_memory = {}
			"resolved": corrupt.commands[0].resolved_target = [-1,0]
			"event": corrupt.events[0].resolved = [1,INF]
			"shot_origin": corrupt.events[-1].weapon_origin[2] = NAN
			"transmission": corrupt.events[-1].transmission = 1.1
		check(not restored.load_data(corrupt).get("ok",true),"Corrupt realism replay must reject: " + mutation)
		check(JSON.stringify(restored.export_data()) == before,"Rejected import must preserve current replay: " + mutation)
	var bounded := Replay.new()
	bounded.begin(fixture())
	var moving: Dictionary = replay_state()
	for i: int in range(301):
		moving.time = float(i)*0.1
		moving.tick = i*3
		moving.units[0].x = 2.0 + sin(float(i)*0.01)
		moving.units[0].weapon_origin = [moving.units[0].x+0.1,5.1,0.9+float(i)*0.0001]
		moving.units[0].awareness_confidence = float(i%100)*0.01
		bounded.capture(moving)
	check(bounded.export_data().states.size() == 4,"Changing weapon position and confidence must reuse one definition per actor/door")
	check(bounded.estimate_memory_bytes() < 2*1024*1024,"Numeric realism samples must remain below the bounded replay budget")

func _test_legacy() -> void:
	var mission: Dictionary = fixture()
	for key: String in ["environment","modifiers"]: mission.erase(key)
	for group: String in Schema.GROUPS:
		for entity: Dictionary in mission[group]:
			for key: String in Schema.ACTOR_FIELDS + Schema.GEOMETRY_FIELDS + ["indoor","lighting","floor_surface","hinge_side","locked","hp","durability","destroyed","progress","initial_states"]:
				if group == "units" and key == "hp": continue
				entity.erase(key)
			if group == "doors": entity.state = "CLOSED"
	check(Schema.check(mission).get("ok",false),"Old authored missions must remain valid without new optional fields")
	var state := {"time":0.0,"tick":0,"units":[{"id":"alpha","kind":"unit","x":2.0,"z":5.0,"facing":0.3,"hp":100.0,"status":"IDLE","commands":[]}],"enemies":[],"civilians":[],"doors":[{"id":"door","x":6.0,"z":5.0,"axis":"x","state":"CLOSED","progress":0.0}],"events":[],"result":{}}
	var record := Replay.new()
	record.begin(mission)
	record.finish(state)
	var candidate: Dictionary = JSON.parse_string(JSON.stringify(record.export_data()))
	candidate.erase("environment")
	var restored := Replay.new()
	var response: Dictionary = restored.load_data(candidate)
	check(response.get("ok",false),"Legacy record with omitted realism fields must import: " + str(response))
	if not response.get("ok",false): return
	var loaded: Dictionary = restored.seek(0,true)
	check(loaded.units[0].stance == "standing" and loaded.units[0].movement_mode == "normal" and not loaded.units[0].hold_position,"Legacy actor defaults must preserve original posture and controls")
	check(is_equal_approx(loaded.units[0].body_facing,0.3),"Legacy body direction must follow the recorded direction")
	check(loaded.doors[0].hinge_side == -1 and loaded.doors[0].swing_sign == -1 and not loaded.doors[0].destroyed,"Legacy doors must retain the original hinge and intact leaf")

func _test_known_revision() -> void:
	var mission: Dictionary = Catalog.load("T01")
	var source: Dictionary = mission.units[0]
	var record := Replay.new()
	record.begin(mission)
	record.finish({"time":0.0,"tick":0,"units":[{"id":source.id,"kind":"unit","x":source.x,"z":source.z,"status":"IDLE"}],"enemies":[],"civilians":[],"doors":[],"events":[],"result":{}})
	var candidate: Dictionary = JSON.parse_string(JSON.stringify(record.export_data()))
	var restored := Replay.new()
	check(restored.load_data(candidate).get("ok",false),"Installed current authored revision must import")
	var legacy: Dictionary = candidate.duplicate(true)
	legacy.map_revision = 1
	check(restored.load_data(legacy).get("ok",false),"Original revision 1 fixture must remain readable")
	var before: String = JSON.stringify(restored.export_data())
	for mutation: String in ["future_revision","unknown_map","wrong_bounds"]:
		var corrupt: Dictionary = candidate.duplicate(true)
		match mutation:
			"future_revision": corrupt.map_revision = int(mission.revision)+1
			"unknown_map": corrupt.map_id = "UNKNOWN_MAP"
			"wrong_bounds": corrupt.bounds = [1,1]
		check(not restored.load_data(corrupt).get("ok",true),"Map incompatibility must reject: " + mutation)
		check(JSON.stringify(restored.export_data()) == before,"Rejected map mismatch must preserve loaded record: " + mutation)
