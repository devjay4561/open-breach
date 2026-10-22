extends SceneTree
## P4 policy authoring is optional, strict, and never migrates old source data.
const Schema = preload("res://scripts/mission_schema.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Communication = preload("res://scripts/team_communication.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _fixture(version: int = 5, seed_value: int = 0) -> Dictionary:
	return {"schema_version":version,"id":"NOISE_POLICY_SCHEMA","revision":1,"title":"Communication policy contract","seed":seed_value,"bounds":[12,12],"focus":[6,6],
		"rooms":[{"id":"front","x":3,"z":6,"w":6,"d":12,"indoor":false},{"id":"back","x":9,"z":6,"w":6,"d":12,"indoor":true}],
		"walls":[],"doors":[],"props":[],"units":[{"id":"alpha","name":"ALPHA","role":"entry","x":3,"z":3,"facing":0,"weapon":"standard"}],
		"enemies":[],"civilians":[],"objectives":["Reach the designated room"],"win":[{"type":"reach_zone","zone":[9,9,1,1]}],"fail":[]}

func _accept(data: Dictionary, label: String) -> Dictionary:
	var before := JSON.stringify(data)
	var answer: Dictionary = Schema.check(data)
	check(bool(answer.get("ok",false)),label+": "+str(answer.get("message","")))
	check(JSON.stringify(data) == before,label+" leaves authored source unchanged")
	if answer.get("ok",false): check(JSON.stringify(answer.data) == before,label+" returns the same authoring shape")
	return answer

func _reject(data: Dictionary, label: String) -> void:
	# Preserve invalid Variant types/NaN bits as well: JSON would turn NaN
	# into null and could hide an accidental mutation in the rejected source.
	var before := var_to_bytes(data)
	var answer: Dictionary = Schema.check(data)
	check(not bool(answer.get("ok",true)),label)
	check(var_to_bytes(data) == before,label+" leaves rejected source unchanged")

func _run() -> void:
	_versions_and_defaults()
	_explicit_policy()
	_malformed_policy()
	_inherited_contracts()
	_authored_missions()
	_no_global_random_draw()
	print("BREACH_NOISE_DISCIPLINE_SCHEMA_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _versions_and_defaults() -> void:
	# P5 moves only the current/future boundary. All authored P4 v5 fixtures
	# and their older-version rejection expectations retain their meaning.
	check(Schema.CURRENT_SCHEMA_VERSION == 6,"P5 introduces v6 while retaining P4 communication v5")
	for seed_value: int in range(30):
		for version: int in [1,2,3,4,5]:
			var source := _fixture(version,seed_value)
			var answer := _accept(source,"Absent noise policy v%d seed%d" % [version,seed_value])
			check(Communication.discipline(source) == "verbal","Absent policy keeps spoken runtime default")
			check(not source.has("noise_discipline") and (not answer.get("ok",false) or not answer.data.has("noise_discipline")),"Default does not inject a field into source or validated output")
	for version: Variant in [0,Schema.CURRENT_SCHEMA_VERSION+1,4.5,true,null]:
		var source := _fixture()
		source.schema_version = version
		_reject(source,"Unsupported authoring version "+str(version))

func _explicit_policy() -> void:
	for mode: String in ["verbal","hand_signals"]:
		for seed_value: int in range(30):
			var source := _fixture(5,seed_value)
			source.noise_discipline = mode
			var answer := _accept(source,"Explicit policy %s seed%d" % [mode,seed_value])
			check(Communication.discipline(source) == mode,"Runtime reads exact authored policy "+mode)
			if answer.get("ok",false):
				answer.data.noise_discipline = "hand_signals" if mode == "verbal" else "verbal"
				check(source.noise_discipline == mode,"Validated copy remains detached from original source")
		for version: int in [1,2,3,4]:
			var legacy := _fixture(version)
			legacy.noise_discipline = mode
			_reject(legacy,"Policy field requires v5, not v%d (%s)" % [version,mode])

func _malformed_policy() -> void:
	for value: Variant in [null,true,false,0,1,1.5,NAN,INF,[],["verbal"],{}, {"mode":"verbal"},"","Verbal","HAND_SIGNALS","hand_signal","quiet"," verbal","verbal "]:
		var source := _fixture()
		source.noise_discipline = value
		_reject(source,"Invalid policy must be rejected: "+str(value))
		check(Communication.discipline(source).is_empty(),"Invalid explicit policy has no spoken fallback: "+str(value))
	for key: String in ["noise_dicipline","signal_mode","signal_radius","receiver_unit_ids"]:
		var source := _fixture()
		source[key] = "verbal"
		_reject(source,"Runtime provenance/unknown field is not mission authoring: "+key)

func _inherited_contracts() -> void:
	var source := _fixture()
	source.noise_discipline = "hand_signals"
	source.win = [{"type":"rooms_cleared","room_ids":["back"]},{"type":"no_shots"}]
	_accept(source,"v5 inherits v4 target list and v2 no_shots")
	source.win = [{"type":"rooms_cleared","room_ids":[]}]
	_reject(source,"v5 retains nonempty room selection")
	source.win = [{"type":"rooms_cleared","room_ids":["alpha"]}]
	_reject(source,"v5 retains actual room cross-reference")
	source = _fixture()
	source.noise_discipline = "verbal"
	source.doors = [{"id":"door","x":6,"z":6,"w":0.24,"d":1.6,"axis":"z","state":"CLOSED","locked":false,"kick_resistance":0.8,"reinforced":true}]
	_accept(source,"v5 inherits optional v3 door mechanics")
	source.doors[0].kick_resistance = 1.01
	_reject(source,"v5 keeps kick success probability bound")
	for mode: String in ["verbal","hand_signals"]:
		var upper := _fixture()
		upper.noise_discipline = mode
		upper.bounds = [512,512]
		upper.focus = [480,480]
		upper.rooms = [{"id":"upper","x":480,"z":480,"w":8,"d":8,"base_height":64}]
		upper.units[0].x = 478
		upper.units[0].z = 478
		upper.environment = {"water":true,"water_level":-1,"ground_surface":"ship_deck"}
		upper.walkable_areas = [{"id":"deck","x":480,"z":480,"w":8,"d":8}]
		upper.win = [{"type":"rooms_cleared","room_ids":["upper"]},{"type":"no_shots"}]
		_accept(upper,"v5 preserves 512m floor64 water union with "+mode)
		upper.walkable_areas = []
		_reject(upper,"v5 preserves explicit water-floor requirement")

func _authored_missions() -> void:
	for id: String in ["T01","M01","H02"]:
		var authored: Dictionary = Catalog.load(id)
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % Catalog.MAPS[id]))
		for seed_value: int in range(30):
			var source: Dictionary = authored.duplicate(true)
			source.seed = seed_value
			check(not source.is_empty(),"Catalog loads old mission "+id)
			check(int(source.get("schema_version",0)) == int(raw.schema_version),"Catalog preserves the authored mission version "+id)
			var before := JSON.stringify(source)
			check(Communication.discipline(source) == "verbal","Old mission runtime defaults to spoken policy "+id)
			check(not source.has("noise_discipline") and JSON.stringify(source) == before,"Default lookup preserves catalog payload seed%d %s" % [seed_value,id])
	# Strict re-import of old payloads exercises the same boundary as replay.
	for id: String in ["T01","M01","H02"]:
		_accept(Catalog.load(id),"Old catalog payload remains strictly re-importable "+id)

func _no_global_random_draw() -> void:
	seed(52024)
	var expected := randi()
	seed(52024)
	var source := _fixture()
	source.noise_discipline = "hand_signals"
	Schema.check(source)
	Communication.discipline(source)
	check(randi() == expected,"Schema/default lookup does not consume global RNG")
