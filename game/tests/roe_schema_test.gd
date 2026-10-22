extends SceneTree
## P5 authoring changes do not migrate historical missions or consume RNG.
const Schema = preload("res://scripts/mission_schema.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Equipment = preload("res://scripts/equipment_catalog.gd")
var checks := 0
var failures: Array[String] = []
var contracts: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _fixture(version: int = 6, seed_value: int = 0) -> Dictionary:
	return {"schema_version":version,"id":"ROE_SCHEMA","revision":1,"title":"ROE authoring contract","seed":seed_value,"bounds":[12,12],"focus":[6,6],
		"rooms":[{"id":"front","x":3,"z":6,"w":6,"d":12,"indoor":false},{"id":"back","x":9,"z":6,"w":6,"d":12,"indoor":true}],
		"walls":[],"doors":[],"props":[],"units":[{"id":"alpha","name":"ALPHA","role":"entry","x":3,"z":3,"facing":0,"weapon":"standard"}],
		"enemies":[],"civilians":[],"objectives":["Reach the designated room"],"win":[{"type":"reach_zone","zone":[9,9,1,1]}],"fail":[]}

func _star(stat: Variant, operation: Variant = "eq", value: Variant = 0) -> Dictionary:
	return {"id":"contract_star","label":"Contract star","stat":stat,"op":operation,"value":value}

func _accept(source: Dictionary, label: String) -> Dictionary:
	var before := var_to_bytes(source)
	var answer: Dictionary = Schema.check(source)
	check(bool(answer.get("ok",false)),label+": "+str(answer.get("message","")))
	check(var_to_bytes(source) == before,label+" preserves authored source")
	if answer.get("ok",false): check(var_to_bytes(answer.data) == before,label+" returns an unchanged authoring copy")
	return answer

func _reject(source: Dictionary, label: String) -> void:
	var before := var_to_bytes(source)
	check(not bool(Schema.check(source).get("ok",true)),label)
	check(var_to_bytes(source) == before,label+" preserves rejected source")

func _contract(source: Dictionary, accepted: bool, label: String) -> void:
	contracts.append({"label":label,"source":source.duplicate(true),"accepted":accepted})
	if accepted: _accept(source,label)
	else: _reject(source,label)

func _run() -> void:
	_versions_and_policy()
	_star_contracts()
	_equipment_contracts()
	_inherited_contracts()
	_authored_missions()
	_no_random_draw()
	_export_contracts()
	print("BREACH_ROE_SCHEMA_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _versions_and_policy() -> void:
	check(Schema.CURRENT_SCHEMA_VERSION == 6,"P5 introduces authoring v6")
	for seed_value: int in range(30):
		for version: int in [1,2,3,4,5,6]:
			var source := _fixture(version,seed_value)
			var answer := _accept(source,"Absent ROE v%d seed%d" % [version,seed_value])
			check(not source.has("roe") and (not answer.get("ok",false) or not answer.data.has("roe")),"Runtime defaults do not inject ROE into authored v%d" % version)
	for mode: String in ["precision","high_intensity"]:
		for seed_value: int in range(30):
			var source := _fixture(6,seed_value)
			source.roe = mode
			var answer := _accept(source,"Explicit ROE %s seed%d" % [mode,seed_value])
			if answer.get("ok",false):
				answer.data.roe = "high_intensity" if mode == "precision" else "precision"
				check(source.roe == mode,"Validated copy is detached from source")
		for version: int in [1,2,3,4,5]:
			var source := _fixture(version)
			source.roe = mode
			_contract(source,false,"ROE %s requires v6, not v%d" % [mode,version])
	for value: Variant in [null,true,false,0,1,1.5,[],["precision"],{}, {"mode":"precision"},"","Precision","HIGH_INTENSITY","high-intensity","verbal"," precision","precision "]:
		var source := _fixture()
		source.roe = value
		_contract(source,false,"Malformed explicit ROE "+str(value))
	for value: Variant in [NAN,INF,-INF]:
		var source := _fixture()
		source.roe = value
		_reject(source,"Nonfinite ROE must be rejected")
	for version: Variant in [0,Schema.CURRENT_SCHEMA_VERSION+1,5.5,true,null]:
		var source := _fixture()
		source.schema_version = version
		_contract(source,false,"Unsupported schema version "+str(version))
	for key: String in ["rules_of_engagement","frags","civilian_damage","unit_damage","stats_observed","result","stars_observed"]:
		var source := _fixture()
		source[key] = "precision"
		_contract(source,false,"Runtime/unknown top-level field is not authored: "+key)
	for key: String in ["frags","available_frags","civilian_damage","unit_damage"]:
		var source := _fixture()
		source.units[0][key] = 1
		_contract(source,false,"Runtime unit field is not authored: "+key)

func _star_contracts() -> void:
	for stat: String in ["civilian_damage","unit_damage"]:
		for operation: String in ["eq","lte","gte"]:
			for value: Variant in [0,0.0,0.5,1,1e9]:
				var source := _fixture()
				source.stars = [_star(stat,operation,value)]
				_contract(source,true,"v6 %s %s %s" % [stat,operation,value])
		for version: int in [1,2,3,4,5]:
			var source := _fixture(version)
			source.stars = [_star(stat)]
			_contract(source,false,"Damage statistic %s requires v6, not v%d" % [stat,version])
		for value: Variant in [null,true,false,-0.001,"0",[],{},1e9+1]:
			var source := _fixture()
			source.stars = [_star(stat,"eq",value)]
			_contract(source,false,"Malformed damage target %s %s" % [stat,value])
		for value: Variant in [NAN,INF,-INF]:
			var source := _fixture()
			source.stars = [_star(stat,"eq",value)]
			_reject(source,"Nonfinite damage target "+stat)
	for version: int in [1,2,3,4,5,6]:
		for operation: String in ["eq","lte","gte"]:
			var source := _fixture(version)
			source.stars = [_star("arrests",operation,1)]
			_contract(source,version >= 6 or operation != "gte","Arrests %s v%d" % [operation,version])
		for operation: Variant in ["gt","lt","GTE",null,true,1,[],{}]:
			var source := _fixture(version)
			source.stars = [_star("arrests",operation,1)]
			_contract(source,false,"Unsupported operation %s v%d" % [operation,version])
	for stat: Variant in ["frags_used","damage","civilian_injuries","unit_injuries","unknown",null,true,1,[],{}]:
		var source := _fixture()
		source.stars = [_star(stat)]
		_contract(source,false,"Unknown/non-authored statistic "+str(stat))
	for version: int in [1,2,3,4,5,6]:
		var source := _fixture(version)
		source.stars = [_star("civilian_losses"),{"id":"legacy_completion","label":"Completion","type":"completion"},{"id":"legacy_time","label":"Time","type":"par_time","value":240}]
		_contract(source,true,"Historical loss/medal contract v%d" % version)
	var source := _fixture()
	source.stars = [_star("arrests","gte",1),_star("civilian_damage")]
	_reject(source,"New objectives keep unique authored star IDs")
	source.stars = [{"id":"legacy","label":"Completion","type":"completion","stat":"unit_damage","op":"eq","value":0}]
	_contract(source,false,"Legacy medals cannot also contain a statistic predicate")

func _inherited_contracts() -> void:
	for mode: String in ["precision","high_intensity"]:
		var source := _fixture()
		source.roe = mode
		source.noise_discipline = "hand_signals"
		source.win = [{"type":"rooms_cleared","room_ids":["back"]},{"type":"no_shots"}]
		source.doors = [{"id":"door","x":6,"z":6,"w":0.24,"d":1.6,"axis":"z","state":"CLOSED","kick_resistance":0.8,"reinforced":true}]
		_contract(source,true,"v6 inherits communication, rooms, no_shots and door contract: "+mode)
		source.win[0].room_ids = ["alpha"]
		_contract(source,false,"ROE does not change room cross-references: "+mode)
		var upper := _fixture()
		upper.roe = mode
		upper.bounds = [512,512]
		upper.focus = [480,480]
		upper.rooms = [{"id":"upper","x":480,"z":480,"w":8,"d":8,"base_height":64}]
		upper.units[0].x = 478
		upper.units[0].z = 478
		upper.environment = {"water":true,"water_level":-1,"ground_surface":"ship_deck"}
		upper.walkable_areas = [{"id":"deck","x":480,"z":480,"w":8,"d":8}]
		upper.win = [{"type":"rooms_cleared","room_ids":["upper"]},{"type":"no_shots"}]
		_contract(upper,true,"ROE preserves 512m/floor64/water/no_shots: "+mode)
		upper.walkable_areas = []
		_contract(upper,false,"ROE preserves the explicit water-floor requirement: "+mode)

func _authored_missions() -> void:
	for id: String in ["T01","M01","H02"]:
		var authored: Dictionary = Catalog.load(id)
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % Catalog.MAPS[id]))
		_accept(authored,"Existing catalog payload remains strictly re-importable "+id)
		for seed_value: int in range(30):
			var source := authored.duplicate(true)
			source.seed = seed_value
			var before := var_to_bytes(source)
			check(int(source.get("schema_version",0)) == int(raw.schema_version),"Catalog preserves the authored mission version "+id)
			check(source.has("roe") == raw.has("roe") and Catalog.roe(source) == str(raw.get("roe","precision")),"Catalog preserves authored ROE and defaults omitted policy to precision "+id)
			check(var_to_bytes(source) == before,"Runtime policy lookup preserves old mission %s seed%d" % [id,seed_value])

func _no_random_draw() -> void:
	seed(63025)
	var expected := randi()
	seed(63025)
	var source := _fixture()
	source.roe = "high_intensity"
	source.stars = [_star("arrests","gte",1)]
	Schema.check(source)
	check(randi() == expected,"ROE schema validation does not consume global RNG")

func _equipment_contracts() -> void:
	check(Equipment.resolve_loadout().equipment.get("frag",0) == 0,"Legacy default grants no frag resource")
	for version: int in [1,2,3,4,5,6]:
		for amount: int in [0,1,2]:
			var source := _fixture(version)
			source.units[0].equipment = {"frag":amount}
			_contract(source,true,"Catalog frag equipment count%d v%d" % [amount,version])
	for mode: String in ["precision","high_intensity"]:
		var source := _fixture()
		source.roe = mode
		source.loadout = {"alpha":{"equipment":{"frag":1,"stun":1,"breach":1}}}
		_contract(source,true,"ROE authoring uses existing two small/one large slots: "+mode)
	for value: Variant in [true,false,-1,3,1.5,"1",null,[],{}]:
		var source := _fixture()
		source.units[0].equipment = {"frag":value}
		_contract(source,false,"Malformed frag count "+str(value))
	for equipment: Dictionary in [{"frag":2,"stun":1},{"frag":1,"probe_c1":1,"smoke":1},{"frag":1,"breach":2},{"frag_unknown":1}]:
		var source := _fixture()
		source.units[0].equipment = equipment
		_contract(source,false,"Frag keeps existing capacity/allowlist "+str(equipment))

func _export_contracts() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--contract-output="): continue
		var file := FileAccess.open(argument.trim_prefix("--contract-output="),FileAccess.WRITE)
		check(file != null,"Shared JSON contract output is writable")
		if file != null: file.store_string(JSON.stringify(contracts))
