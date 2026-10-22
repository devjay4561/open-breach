extends SceneTree

const Navigation = preload("res://scripts/navigation.gd")
const Replay = preload("res://scripts/replay.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Simulation = preload("res://scripts/simulation.gd")
const MainScene = preload("res://main.tscn")
var checks: int = 0
var failures: Array[String] = []
var cover_completed: bool = false
var replay_completed: bool = false
var legacy_completed: bool = false
var custom_completed: bool = false
var catalog_completed: bool = false
var controller_completed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	_test_cover()
	_test_replay()
	_test_existing_record()
	_test_custom_record()
	_test_catalog_snapshots()
	await _test_main_legacy_replay()
	check(cover_completed and replay_completed and legacy_completed and custom_completed and catalog_completed and controller_completed, "Every focused case must reach its final assertion")
	print("BREACH_SUSTAINED_REPLAY_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_cover() -> void:
	var nav := Navigation.new()
	var props: Array = [{"type":"desk","cover":"low","x":4.0,"z":4.0,"w":1.0,"d":2.0}, {"type":"crate","cover":"low","x":6.0,"z":4.0,"w":1.0,"d":2.0}, {"type":"rug","cover":"none","solid":true,"x":3.0,"z":7.0,"w":1.0,"d":1.0}]
	nav.build({"bounds":[12,10],"walls":[],"props":props}, [])
	check(not nav.walkable(Vector2(4,4)), "Low cover must block actors")
	check(not nav.segment_clear(Vector2(2,4),Vector2(8,4),Navigation.RADIUS), "Low cover must block movement segments")
	check(nav.segment_clear(Vector2(2,4),Vector2(8,4)), "Low cover must permit observation")
	check(nav.shot_clear(Vector2(2,4),Vector2(8,4)), "Low cover must permit shots")
	check(nav.cover_count(Vector2(2,4),Vector2(8,4)) == 2, "Every intersected low cover must count exactly once")
	check(nav.cover_count(Vector2(2,7),Vector2(8,7)) == 0, "A ray beside cover must receive no cover penalty")
	check(nav.walkable(Vector2(3,7)), "Explicit cover none must override legacy solid")
	var path: Array = nav.path(Vector2(2,4),Vector2(8,4))
	check(not path.is_empty(), "Navigation must route around low cover")
	var previous := Vector2(2,4)
	for waypoint: Array in path:
		var point := Vector2(float(waypoint[0]),float(waypoint[1]))
		check(nav.segment_clear(previous,point,Navigation.RADIUS), "Smoothed route must not cross low cover")
		previous = point
	props[0].cover = "full"
	nav.build({"bounds":[12,10],"walls":[],"props":props}, [])
	check(not nav.segment_clear(Vector2(2,4),Vector2(8,4)), "Full cover must block sight")
	check(not nav.shot_clear(Vector2(2,4),Vector2(8,4)), "Full cover must block shots")
	nav.build({"bounds":[12,10],"walls":[{"x":4.0,"z":4.0,"w":0.25,"d":2.0,"thin":true}],"props":[]}, [])
	check(not nav.segment_clear(Vector2(2,4),Vector2(8,4)), "Thin walls must conceal actors")
	check(not nav.segment_clear(Vector2(2,4),Vector2(8,4),Navigation.RADIUS), "Thin walls must block movement")
	check(nav.shot_clear(Vector2(2,4),Vector2(8,4)), "Explicit thin walls must allow selective penetration")
	nav.build({"bounds":[12,10],"walls":[],"props":[{"type":"desk","solid":true,"x":4.0,"z":4.0,"w":1.0,"d":2.0}]}, [])
	check(nav.cover_count(Vector2(2,4),Vector2(8,4)) == 1, "Legacy desk must receive default low classification")
	nav.build({"bounds":[12,10],"walls":[],"props":[]}, [])
	check(nav.cover_count(Vector2(2,4),Vector2(8,4)) == 0, "Rebuilding must clear previous cover")
	cover_completed = true

func state_for(mission: Dictionary) -> Dictionary:
	var units: Array = []
	for source: Dictionary in mission.units:
		units.append({"id":source.id,"kind":"unit","x":source.x,"z":source.z,"hp":100.0,"ammo":8,"stuns":1,"smokes":1,"breaches":1,"weapon":"shotgun","status":"PEEKING","peek_remaining":1.5,"suppressed":false,"suppression_remaining":0.0,"trait":"door_specialist","base_id":source.id,"roster_id":"rook","commands":[]})
	var enemy: Dictionary = mission.enemies[0]
	var civilian: Dictionary = mission.civilians[0]
	return {"time":0.0,"tick":0,"units":units,"enemies":[{"id":enemy.id,"kind":"enemy","x":enemy.x,"z":enemy.z,"hp":72.0,"status":"SURRENDERED","visible":true,"surrendered":true,"arrested":false,"surrender_remaining":5.0,"enemy_type":"sentry","suppressed":true,"suppression_remaining":1.5}],"civilians":[{"id":civilian.id,"kind":"civilian","x":civilian.x,"z":civilian.z,"hp":100.0,"state":"FOLLOW","status":"FOLLOW","visible":true,"secured":true,"follow_unit_id":units[0].id}],"doors":[],"events":[],"result":{},"seed":int(mission.seed),"variant":mission.variant,"modifiers":mission.modifiers.duplicate(),"win":mission.win.duplicate(true),"fail":mission.fail.duplicate(true),"stars":mission.stars.duplicate(true),"sound_zones":[],"smoke_zones":[{"x":4.0,"z":4.0,"radius":2.0,"remaining":4.0}],"stuns_used":1,"reloads":2,"hits_taken":3,"units_deployed":1,"first_alert_time":-1.0,"arrests":0,"kills":0,"unlawful_shots":0,"smokes_used":1,"breaches_used":2}

func _test_replay() -> void:
	var mission: Dictionary = Catalog.load("M01_ARREST")
	mission.seed = 2147483647
	mission.modifiers = ["night","low_ammo"]
	mission["loadout"] = {str(mission.units[0].id):{"weapon":"shotgun","equipment":["smoke","breach"]}}
	mission["roster"] = [{"id":"rook","base_id":str(mission.units[0].id),"name":"ROOK","trait":"breacher"}]
	var state: Dictionary = state_for(mission)
	state.units[0]["peek_origin"] = [4.0,4.0]
	state.units[0]["peek_facing"] = -PI / 2.0
	var unit_id: String = mission.units[0].id
	var enemy_id: String = mission.enemies[0].id
	var civilian_id: String = mission.civilians[0].id
	var door_id: String = mission.doors[0].id
	var door: Dictionary = mission.doors[0]
	state.doors = [{"id":door_id,"x":door.x,"z":door.z,"w":door.w,"d":door.d,"axis":door.axis,"state":"OPENING","progress":0.5,"owner_id":enemy_id,"owner_command_id":"enemy-"+enemy_id}]
	var command_inputs: Array = [["KICK_DOOR",{"door_id":door_id}],["PEEK_DOOR",{"door_id":door_id}],["BREACH_DOOR",{"door_id":door_id}],["HOLD_AT_DOOR",{"door_id":door_id}],["ARREST",{"enemy_id":enemy_id}],["THROW_SMOKE",{"target":[4.0,4.0]}],["ESCORT_CIVILIAN",{"civilian_id":civilian_id}]]
	for index: int in command_inputs.size():
		state.units[0].commands.append({"id":"alpha-%04d" % index,"type":command_inputs[index][0],"args":command_inputs[index][1],"state":"PENDING","owner_id":unit_id})
	var record := Replay.new()
	record.begin(mission)
	record.capture(state)
	state.time = 1.0
	state.tick = 30
	state.enemies[0].status = "ARRESTED"
	state.enemies[0].arrested = true
	state.arrests = 1
	state.result = {"success":true,"status":"SUCCESS","score":100,"time":1.0,"seed":mission.seed,"variant":mission.variant,"modifiers":mission.modifiers,"stuns_used":1,"reloads":2,"hits_taken":3,"units_deployed":1,"first_alert_time":-1.0,"arrests":1,"kills":0,"unlawful_shots":0,"smokes_used":1,"breaches_used":2}
	state.events = [{"seq":1,"tick":30,"time":1.0,"type":"ARREST","unit_id":unit_id,"enemy_id":enemy_id},{"seq":2,"tick":30,"time":1.0,"type":"SMOKE","from":[4.0,4.0],"radius":2.0}]
	record.finish(state)
	var candidate: Dictionary = JSON.parse_string(JSON.stringify(record.export_data()))
	var restored := Replay.new()
	var response: Dictionary = restored.load_data(candidate)
	check(bool(response.get("ok",false)), "Extended operation replay rejected: " + str(response.get("message","")))
	if not response.get("ok",false): return
	var final: Dictionary = restored.seek(1.0,true)
	check(final.result == JSON.parse_string(JSON.stringify(state.result)), "Extended result statistics must survive round trip")
	check(final.smoke_zones == JSON.parse_string(JSON.stringify(state.smoke_zones)), "Smoke zones must survive round trip")
	check(final.smokes_used == 1 and final.breaches_used == 2 and final.result.smokes_used == 1 and final.result.breaches_used == 2, "Campaign consumable statistics must survive round trip")
	check(final.enemies[0].arrested and final.enemies[0].status == "ARRESTED", "Arrested status must survive round trip")
	check(final.civilians[0].follow_unit_id == unit_id, "Civilian escort owner must survive round trip")
	check(final.units[0].commands.size() == command_inputs.size(), "All new commands must survive round trip")
	check(restored.data.seed == mission.seed and restored.data.modifiers == mission.modifiers, "Replay header must preserve configured operation")
	check(final.loadout == mission.loadout and final.roster == mission.roster, "Equipment and roster must survive round trip")
	check(final.units[0].peek_origin == [4.0,4.0] and is_equal_approx(final.units[0].peek_facing,-PI/2.0), "Door observation origin and direction must survive round trip")
	check(final.doors[0].owner_id == enemy_id, "Challenge enemy door ownership must survive round trip")
	var before: String = JSON.stringify(restored.export_data())
	for mutation: String in ["seed","modifier","smoke","follow","rule","command","status","statistics","equipment","door_owner"]:
		var corrupt: Dictionary = candidate.duplicate(true)
		match mutation:
			"seed": corrupt.seed = -1
			"modifier": corrupt.modifiers = ["invisible_enemies"]
			"smoke": corrupt.metadata[0].smoke_zones[0].remaining = -1
			"follow":
				for definition: Dictionary in corrupt.states:
					if definition.base.has("follow_unit_id"): definition.base.follow_unit_id = "missing_unit"
			"rule": corrupt.metadata[0].win[0].type = "unrecognized_rule"
			"command": corrupt.commands[0].args.door_id = "missing_door"
			"status": corrupt.states[0].base.status = "GROWING_LEVEL"
			"statistics": corrupt.metadata[-1].result.first_alert_time = -2
			"equipment": corrupt.loadout = {"script":"unsafe"}
			"door_owner":
				for definition: Dictionary in corrupt.states:
					if definition.group == "doors": definition.base.owner_id = civilian_id
		check(not restored.load_data(corrupt).get("ok",true), "Malformed new replay field accepted: " + mutation)
		check(JSON.stringify(restored.export_data()) == before, "Rejected replay must preserve existing record: " + mutation)
	# Old v1 files have all original fields but omit operation configuration.
	var legacy: Dictionary = candidate.duplicate(true)
	for key: String in ["seed","variant","modifiers","loadout","roster"]: legacy.erase(key)
	check(restored.load_data(legacy).get("ok",false), "Missing optional operation configuration must remain readable in schema v1")
	check(restored.data.seed == Catalog.load("M01_ARREST").seed, "Old recordings must receive the authored seed default")
	replay_completed = true

func _test_existing_record() -> void:
	var path: String = "res://../tests/artifacts/playthrough/roundtrip.breach-replay.json"
	if not FileAccess.file_exists(path):
		legacy_completed = true
		return
	var candidate: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var record := Replay.new()
	check(candidate is Dictionary and record.load_data(candidate).get("ok",false), "Actual original schema v1 replay artifact must remain readable")
	legacy_completed = true

func _test_custom_record() -> void:
	var mission: Dictionary = {"schema_version":1,"id":"EDIT_ROUND_TRIP","revision":7,"title":"사용자 작전","seed":42,"custom":true,"variant":"normal","modifiers":[],"bounds":[12,10],"focus":[6,5],"rooms":[{"id":"room","x":6,"z":5,"w":12,"d":10,"label":"구역"}],"walls":[],"props":[],"doors":[],"units":[{"id":"alpha","name":"ALPHA","role":"선봉","x":2,"z":5,"facing":0,"weapon":"standard"}],"enemies":[{"id":"e1","x":8,"z":5,"facing":PI}],"civilians":[{"id":"c1","x":7,"z":7}],"objectives":["모든 위협 처리"],"win":[{"type":"neutralize_all"}],"fail":[{"type":"no_civilian_loss"}],"stars":[]}
	var validation: Dictionary = Catalog.validate_custom(mission)
	check(validation.get("ok",false), "Custom replay fixture must pass authored geometry validation: " + str(validation))
	if not validation.get("ok",false): return
	var recording := Replay.new()
	recording.begin(mission)
	var state: Dictionary = state_for(mission)
	recording.capture(state)
	state.time = 1.0
	state.tick = 30
	recording.finish(state)
	var candidate: Dictionary = JSON.parse_string(JSON.stringify(recording.export_data()))
	var restored := Replay.new()
	var response: Dictionary = restored.load_data(candidate)
	check(response.get("ok",false), "Embedded custom replay rejected: " + str(response.get("message","")))
	if not response.get("ok",false): return
	check(restored.data.mission_data == JSON.parse_string(JSON.stringify(mission)), "Custom map geometry and revision must survive file sharing")
	check(restored.seek(1,true).units[0].id == "alpha", "Custom replay must resolve actors against embedded map")
	var before: String = JSON.stringify(restored.export_data())
	for mutation: String in ["map_id","revision","geometry","actor"]:
		var corrupt: Dictionary = candidate.duplicate(true)
		match mutation:
			"map_id": corrupt.mission_data.id = "EDIT_DIFFERENT"
			"revision": corrupt.mission_data.revision = 8
			"geometry": corrupt.mission_data.units[0].x = -1
			"actor": corrupt.states[0].base.id = "unknown_actor"
		check(not restored.load_data(corrupt).get("ok",true), "Malformed embedded map accepted: " + mutation)
		check(JSON.stringify(restored.export_data()) == before, "Rejected custom map must preserve current replay: " + mutation)
	mission.units[0]["charges"] = 1
	mission.enemies[0]["training"] = true
	var sim := Simulation.new()
	sim.load_mission(mission)
	var custom_record := Replay.new()
	custom_record.begin(mission)
	custom_record.capture(sim.snapshot(true))
	custom_record.finish(sim.snapshot(true))
	check(restored.load_data(JSON.parse_string(JSON.stringify(custom_record.export_data()))).get("ok",false), "Every accepted custom actor field must remain readable in an actual simulation replay")
	custom_completed = true

func _test_catalog_snapshots() -> void:
	for id: String in Catalog.MAPS:
		var mission: Dictionary = Catalog.load(id)
		mission.modifiers = ["night","low_ammo"]
		mission["loadout"] = {str(mission.units[0].id):{"weapon":"suppressed","equipment":["smoke","breach"]}}
		var sim := Simulation.new()
		sim.load_mission(mission)
		var recording := Replay.new()
		recording.begin(mission)
		recording.capture(sim.snapshot(true))
		sim.step(1.0/30.0)
		recording.finish(sim.snapshot(true))
		var restored := Replay.new()
		var exported: Dictionary = JSON.parse_string(JSON.stringify(recording.export_data()))
		var response: Dictionary = restored.load_data(exported)
		check(response.get("ok",false), id+": actual simulation snapshot must produce a readable replay: "+str(response.get("message","")))
		if id == "CQB06":
			exported.bounds[0] += 0.01
			check(not restored.load_data(exported).get("ok",true), "Floating-point tolerance still rejects changed map dimensions")
	catalog_completed = true

func _test_main_legacy_replay() -> void:
	var session: Node = MainScene.instantiate()
	root.add_child(session)
	session.set_process(false)
	await process_frame
	var legacy: Dictionary = session.recorder.export_data()
	var artifact: String = "res://../tests/artifacts/playthrough/roundtrip.breach-replay.json"
	if FileAccess.file_exists(artifact): legacy = JSON.parse_string(FileAccess.get_file_as_string(artifact))
	for key: String in ["seed","variant","modifiers","loadout","roster"]: legacy.erase(key)
	session._load_mission("M01",true)
	session._import_replay(legacy)
	check(session.mode == "REPLAY" and session.mission_id == legacy.map_id, "Actual main scene imports the original v1 file on its own map")
	check(session.recorder.data.roster is Array and session.recorder.data.roster.is_empty(), "Old replay roster defaults to the same array contract as new files")
	var exported: Dictionary = JSON.parse_string(JSON.stringify(session.recorder.export_data()))
	session._load_mission("M03",true)
	session._import_replay(exported)
	check(session.mode == "REPLAY" and session.mission_id == legacy.map_id, "Actual main scene reimports the exported legacy replay")
	check(session.world._mission.id == legacy.map_id, "Reimported legacy record uses its correct world geometry")
	session._load_mission("M01",true)
	var recorder_before: RefCounted = session.recorder
	var world_before: String = JSON.stringify(session.world._mission)
	var state_before: String = JSON.stringify(session.sim.snapshot(true))
	var incompatible: Dictionary = exported.duplicate(true)
	incompatible.roster = []
	for index: int in range(5): incompatible.roster.append({"id":"operator%d"%index,"base_id":"alpha"})
	var parsed := Replay.new()
	check(parsed.load_data(incompatible).get("ok",false), "Oversized preparation fixture reaches main option validation after valid replay parsing")
	session._import_replay(incompatible)
	check(session.mode == "PLANNING" and session.mission_id == "M01", "Rejected replay preparation preserves controller mode and mission")
	check(session.recorder == recorder_before, "Rejected replay preparation preserves current recorder")
	check(JSON.stringify(session.world._mission) == world_before and JSON.stringify(session.sim.snapshot(true)) == state_before, "Rejected replay preparation preserves actual world and simulation")
	session.queue_free()
	await process_frame
	await process_frame
	controller_completed = true
