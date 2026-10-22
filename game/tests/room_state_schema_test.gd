extends SceneTree
## P3 authoring contract: validation is pure, with thirty fixed mission seeds.
## Runtime room searches and combat clocks are covered by simulation suites.
const Schema = preload("res://scripts/mission_schema.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _fixture(version: int = 4, seed_value: int = 0) -> Dictionary:
	return {"schema_version":version,"id":"ROOM_STATE_SCHEMA","revision":1,"title":"Room goal contract","seed":seed_value,"bounds":[12,12],"focus":[6,6],
		"rooms":[{"id":"front","x":3,"z":6,"w":6,"d":12,"indoor":false},{"id":"back","x":9,"z":6,"w":6,"d":12,"indoor":true}],
		"walls":[],"doors":[],"props":[],"units":[{"id":"alpha","name":"ALPHA","role":"entry","x":3,"z":3,"facing":0,"weapon":"standard"}],
		"enemies":[],"civilians":[],"objectives":["Search the designated room"],"win":[{"type":"reach_zone","zone":[9,9,1,1]}],"fail":[]}

func _accept(data: Dictionary, label: String) -> Dictionary:
	var before := JSON.stringify(data)
	var answer: Dictionary = Schema.check(data)
	check(bool(answer.get("ok",false)),label+": "+str(answer.get("message","")))
	check(JSON.stringify(data) == before,label+" keeps authored input unchanged")
	if bool(answer.get("ok",false)):
		check(JSON.stringify(answer.data) == before,label+" returns the original authoring shape without injected defaults")
	return answer

func _reject(data: Dictionary, label: String) -> void:
	var before := JSON.stringify(data)
	var answer: Dictionary = Schema.check(data)
	check(not bool(answer.get("ok",true)),label)
	check(JSON.stringify(data) == before,label+" leaves invalid source unchanged")

func _run() -> void:
	_versions_and_defaults()
	_room_targets()
	_invalid_targets()
	_existing_roles_and_spawns()
	_historical_bounds_and_floor()
	_authored_missions()
	_no_global_random_draw()
	print("BREACH_ROOM_STATE_SCHEMA_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _versions_and_defaults() -> void:
	# P5 adds v6 ROE, damage statistics and gte; the v4 room-goal fixtures and
	# legacy rejection expectations below retain their original P3 contract.
	check(Schema.CURRENT_SCHEMA_VERSION == 6,"P5 extends authoring to v6 while retaining room-goal v4")
	for seed_value: int in range(30):
		for version: int in [1,2,3,4]:
			var data := _fixture(version,seed_value)
			data.erase("win")
			data.erase("fail")
			var answer := _accept(data,"Absent legacy rules v%d seed%d" % [version,seed_value])
			if answer.get("ok",false):
				check(not answer.data.has("win") and not answer.data.has("fail"),"Schema does not replace old default win/fail rules")
			if version < 4:
				for field: String in ["win","fail"]:
					for explicit: bool in [false,true]:
						var old := _fixture(version,seed_value)
						var rule := {"type":"rooms_cleared"}
						if explicit: rule.room_ids = ["back"]
						old[field] = [rule]
						_reject(old,"New room goal requires v4 (%s v%d seed%d explicit=%s)" % [field,version,seed_value,explicit])
	for version: Variant in [0,Schema.CURRENT_SCHEMA_VERSION+1,3.5,true,null]:
		var data := _fixture()
		data.schema_version = version
		_reject(data,"Current/future version boundary rejects "+str(version))

func _room_targets() -> void:
	for field: String in ["win","fail"]:
		for selection: Variant in [null,["back"],["front","back"],["back","front"]]:
			var data := _fixture()
			var rule := {"type":"rooms_cleared"}
			if selection != null: rule.room_ids = selection
			data[field] = [rule]
			_accept(data,"Optional room targets in "+field+" "+str(selection))
	var only_rooms := _fixture()
	only_rooms.win = [{"type":"rooms_cleared"}]
	_accept(only_rooms,"An empty-threat room search is an actual completion objective")
	var limit := _fixture()
	limit.rooms = []
	var target_ids: Array[String] = []
	for index: int in range(64):
		var id := "room_%02d" % index
		limit.rooms.append({"id":id,"x":6,"z":6,"w":12,"d":12})
		target_ids.append(id)
	limit.win = [{"type":"rooms_cleared","room_ids":target_ids}]
	_accept(limit,"Inclusive 64-room target limit")
	limit.win[0].room_ids.append("room_64")
	_reject(limit,"Room target count above 64 is rejected")

func _invalid_targets() -> void:
	var values: Array = [null,true,1,1.5,"back",{},[],[null],[true],[1],[{}],[[]],[""],["bad room"],["x".repeat(65)],["unknown"],["alpha"],["front","front"]]
	for field: String in ["win","fail"]:
		for value: Variant in values:
			var data := _fixture()
			data[field] = [{"type":"rooms_cleared","room_ids":value}]
			_reject(data,"Invalid room targets in "+field+": "+str(value))
	var empty := _fixture()
	empty.rooms = []
	empty.win = [{"type":"rooms_cleared"}]
	_reject(empty,"An omitted target list cannot turn zero authored rooms into success")
	for key: String in ["targets","room_id","zone","seconds","unit_id"]:
		var data := _fixture()
		data.win = [{"type":"rooms_cleared",key:["back"]}]
		_reject(data,"Room goal rejects unrelated field "+key)
	for kind: String in ["neutralize_all","secure_all_civilians","reach_zone","before_alert","time_limit","escort_to_zone","no_civilian_loss","targets_complete","no_shots"]:
		var data := _fixture()
		var rule := {"type":kind,"room_ids":["back"]}
		if kind in ["reach_zone","escort_to_zone"]: rule.zone = [9,9,1,1]
		if kind == "time_limit": rule.seconds = 30
		if kind == "targets_complete":
			data.interactive_targets = [{"id":"inspect","x":9,"z":9,"w":1,"d":1,"label":"Inspect","action":"inspect","duration":1}]
			rule.targets = ["inspect"]
		data.win = [rule]
		_reject(data,"room_ids cannot alter existing rule "+kind)
	for runtime_key: String in ["room_states","room_states_observed"]:
		var data := _fixture()
		data[runtime_key] = {"back":"CLEAR"}
		_reject(data,"Runtime room authority is not mission authoring: "+runtime_key)

func _enemy() -> Dictionary:
	return {"id":"enemy","x":9,"z":3,"facing":0,"patrol":[]}

func _existing_roles_and_spawns() -> void:
	for version: int in [1,2,3,4]:
		for role: String in ["guard","patrol","reserve"]:
			var data := _fixture(version)
			var enemy := _enemy()
			enemy.response_role = role
			enemy.spawns = [{"x":9,"z":3,"facing":0,"patrol":[]},{"x":10,"z":4,"facing":0,"patrol":[[10,5]]}]
			data.enemies = [enemy]
			_accept(data,"Existing role/candidate-zero contract v%d %s" % [version,role])
	for role: Variant in [null,true,1,[],{},"reinforcements"]:
		var data := _fixture()
		var enemy := _enemy()
		enemy.response_role = role
		data.enemies = [enemy]
		_reject(data,"Invalid response role returns a validation error: "+str(role))
	for candidates: Variant in [null,true,{},[],[{}],[{"x":10,"z":3,"facing":0}]]:
		var data := _fixture()
		var enemy := _enemy()
		enemy.spawns = candidates
		data.enemies = [enemy]
		_reject(data,"Spawn candidates preserve their original shape/default: "+str(candidates))

func _historical_bounds_and_floor() -> void:
	for version: int in [2,3,4]:
		var data := _fixture(version)
		data.bounds = [512,512]
		data.focus = [480,480]
		data.rooms = [{"id":"upper","x":480,"z":480,"w":8,"d":8,"base_height":64,"indoor":true}]
		data.walkable_areas = [{"id":"deck_floor","x":480,"z":480,"w":8,"d":8}]
		data.units[0].x = 478
		data.units[0].z = 478
		data.environment = {"time_of_day":"day","lighting":1,"water":true,"water_level":-1,"ground_surface":"ship_deck"}
		data.interactive_targets = [{"id":"inspect","x":481,"z":481,"w":1,"d":1,"label":"Inspect","action":"inspect","duration":1}]
		data.win = [{"type":"targets_complete","targets":["inspect"]},{"type":"no_shots"}]
		if version == 4: data.win.append({"type":"rooms_cleared","room_ids":["upper"]})
		_accept(data,"Historical 512m/64m floor/target/no_shots contract v"+str(version))
		data.rooms[0].base_height = 64.01
		_reject(data,"Historical height limit stays strict v"+str(version))
	var door := _fixture()
	door.doors = [{"id":"door","x":6,"z":6,"w":0.24,"d":1.6,"axis":"z","state":"CLOSED","kick_resistance":0.25,"reinforced":true}]
	_accept(door,"V4 preserves the v3 door extension")
	door.doors[0].kick_resistance = 1.01
	_reject(door,"V4 preserves v3 door probability validation")

func _authored_missions() -> void:
	for id: String in ["T01","M01","H02"]:
		var authored: Dictionary = Catalog.load(id)
		var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % Catalog.MAPS[id]))
		check(int(authored.schema_version) == int(source.schema_version),"Catalog preserves the authored mission version: "+id)
		check(not (authored.get("win",[])+authored.get("fail",[])).any(func(rule: Dictionary) -> bool: return str(rule.get("type","")) == "rooms_cleared"),"Catalog does not inject room goals: "+id)
		for seed_value: int in range(30):
			var data: Dictionary = authored.duplicate(true)
			data.seed = seed_value
			_accept(data,"Existing mission "+id+" fixed seed "+str(seed_value))

func _no_global_random_draw() -> void:
	seed(73021)
	var expected := randi()
	seed(73021)
	var data := _fixture()
	data.win = [{"type":"rooms_cleared","room_ids":["back"]}]
	Schema.check(data)
	check(randi() == expected,"Room-goal schema validation never consumes global randomness")
