extends SceneTree
const Schema = preload("res://scripts/mission_schema.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Equipment = preload("res://scripts/equipment_catalog.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture(version: int = 3, seed_value: int = 0) -> Dictionary:
	return {
		"schema_version":version,"id":"DOCTRINE_SCHEMA","revision":1,"title":"Schema contract","seed":seed_value,
		"bounds":[12.0,12.0],"focus":[6.0,6.0],"objectives":["Validate the authored door"],
		"rooms":[{"id":"front","x":6.0,"z":3.0,"w":12.0,"d":6.0},{"id":"back","x":6.0,"z":9.0,"w":12.0,"d":6.0}],
		"walls":[{"id":"west","x":2.6,"z":6.0,"w":5.2,"d":0.24},{"id":"east","x":9.4,"z":6.0,"w":5.2,"d":0.24}],
		"doors":[{"id":"door","x":6.0,"z":6.0,"w":1.6,"d":0.24,"axis":"x","state":"CLOSED"}],
		"props":[],"units":[{"id":"alpha","name":"ALPHA","role":"entry","x":3.0,"z":3.0,"facing":0.0,"weapon":"standard"}],
		"enemies":[],"civilians":[],"win":[{"type":"neutralize_all"}],"fail":[]
	}

func reject(data: Dictionary, label: String) -> void:
	check(not bool(Schema.check(data).get("ok",false)),label)

func run() -> void:
	_schema_contracts()
	_historical_contracts()
	_default_contracts()
	_equipment_contracts()
	_capture_goals()
	print("BREACH_CQB_DOCTRINE_SCHEMA_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _schema_contracts() -> void:
	# P5 adds v6 ROE, damage statistics and gte. The P1 v3 fixtures below
	# still check their original contract; only the current/future boundary moves.
	check(Schema.CURRENT_SCHEMA_VERSION == 6,"ROE extends doctrine schema to version 6")
	for seed_value: int in range(30):
		for version: int in [1,2,3]:
			var source: Dictionary = fixture(version,seed_value)
			var before: String = JSON.stringify(source)
			var answer: Dictionary = Schema.check(source)
			check(bool(answer.get("ok",false)),"Legacy/default door loads at version %d seed %d: %s" % [version,seed_value,answer.get("message","")])
			check(JSON.stringify(source) == before,"Schema validation preserves authored data at version %d seed %d" % [version,seed_value])
	for probability: float in [0.0,0.25,0.5,0.8,1.0]:
		var data: Dictionary = fixture()
		data.doors[0].kick_resistance = probability
		data.doors[0].reinforced = true
		check(bool(Schema.check(data).get("ok",false)),"Version 3 accepts finite kick probability %s" % probability)
	for probability: Variant in [-0.01,1.01,NAN,INF,true,"0.5"]:
		var data: Dictionary = fixture()
		data.doors[0].kick_resistance = probability
		reject(data,"Invalid kick probability rejected: "+str(probability))
	for reinforcement: Variant in [0,1,"true",null]:
		var data: Dictionary = fixture()
		data.doors[0].reinforced = reinforcement
		reject(data,"Reinforcement requires a boolean: "+str(reinforcement))
	for version: int in [1,2]:
		var data: Dictionary = fixture(version)
		data.doors[0].kick_resistance = 0.5
		reject(data,"Kick probability requires version 3, not version "+str(version))
		data = fixture(version)
		data.doors[0].reinforced = false
		reject(data,"Reinforcement requires version 3, not version "+str(version))
	for version: Variant in [0,Schema.CURRENT_SCHEMA_VERSION+1,3.5,true]:
		var data: Dictionary = fixture()
		data.schema_version = version
		reject(data,"Unsupported schema version rejected: "+str(version))
	var unknown: Dictionary = fixture()
	unknown.doors[0].kick_resistence = 0.5
	reject(unknown,"Unknown door field remains rejected")

func _historical_contracts() -> void:
	for version: int in [2,3]:
		var data: Dictionary = fixture(version)
		data.bounds = [48.0,48.0]
		data.rooms[0].base_height = 0.0
		data.walls[0].height = 20.0
		data.walls[0].render = false
		data.environment = {"ground_surface":"ship_deck","biome":"urban","ground_color":"#555555","water":false}
		data.historical = {"location":"Schema fixture","accuracy_note":"Synthetic validation fixture"}
		data.interactive_targets = [{"id":"inspect","x":3.0,"z":9.0,"w":1.0,"d":1.0,"label":"Inspect","action":"inspect","duration":1.0}]
		data.win = [{"type":"targets_complete","targets":["inspect"]},{"type":"no_shots"}]
		var answer: Dictionary = Schema.check(data)
		check(bool(answer.get("ok",false)),"Version %d preserves historical bounds, heights, environment and objectives: %s" % [version,answer.get("message","")])
		data.interactive_targets[0].duration = INF
		reject(data,"Historical field validation still runs at version "+str(version))

func _default_contracts() -> void:
	for seed_value: int in range(30):
		var data: Dictionary = fixture(1,seed_value)
		var door: Dictionary = data.doors[0]
		var before: String = JSON.stringify(data)
		check(is_equal_approx(Catalog.kick_success_probability(door,data.rooms),0.8),"Internal legacy door default seed "+str(seed_value))
		check(is_equal_approx(Catalog.kick_success_probability(door,[data.rooms[0]]),0.5),"External legacy door default seed "+str(seed_value))
		check(is_equal_approx(Catalog.kick_success_probability(door,[]),0.5),"Unmapped legacy door default seed "+str(seed_value))
		check(JSON.stringify(data) == before,"Default resolution does not rewrite old mission seed "+str(seed_value))
		var locked: Dictionary = door.duplicate(true)
		locked.locked = true
		check(is_equal_approx(Catalog.kick_success_probability(locked,data.rooms),0.25),"Locked door default seed "+str(seed_value))
		var reinforced: Dictionary = door.duplicate(true)
		reinforced.reinforced = true
		check(is_equal_approx(Catalog.kick_success_probability(reinforced,data.rooms),0.25),"Reinforced door default seed "+str(seed_value))
		locked.kick_resistance = 1.0
		check(is_equal_approx(Catalog.kick_success_probability(locked,data.rooms),1.0),"Authored probability overrides category seed "+str(seed_value))
	var data: Dictionary = fixture()
	data.rooms[1].indoor = false
	check(is_equal_approx(Catalog.kick_success_probability(data.doors[0],data.rooms),0.5),"Authored outdoor room counts as exterior")
	var axis_z: Dictionary = {"x":6.0,"z":6.0,"w":0.24,"d":1.6,"axis":"z"}
	var rooms: Array = [{"x":3.0,"z":6.0,"w":6.0,"d":12.0},{"x":9.0,"z":6.0,"w":6.0,"d":12.0}]
	check(is_equal_approx(Catalog.kick_success_probability(axis_z,rooms),0.8),"Internal default follows either door axis")

func _equipment_contracts() -> void:
	var profile: Dictionary = Equipment.shotgun_breach_stats()
	check(profile == {"duration":1.2,"sound":14.0,"success":0.9},"Shotgun breach profile matches P1 tuning")
	profile.duration = 99.0
	check(Equipment.shotgun_breach_stats().duration == 1.2,"Shotgun profile calls return independent data")
	var shotgun: Dictionary = {"weapon":"shotgun","current_weapon":"shotgun","active_weapon":"primary","ammo":1}
	check(Equipment.can_shotgun_breach(shotgun),"Loaded active primary shotgun can breach")
	shotgun.ammo = 0
	check(not Equipment.can_shotgun_breach(shotgun),"Empty shotgun cannot breach")
	shotgun.ammo = 8
	shotgun.active_weapon = "secondary"
	check(not Equipment.can_shotgun_breach(shotgun),"A holstered shotgun cannot breach")
	shotgun.active_weapon = "primary"
	shotgun.current_weapon = "standard"
	check(not Equipment.can_shotgun_breach(shotgun),"Active weapon must actually be a shotgun")
	check(Equipment.can_shotgun_breach({"weapon":"shotgun","ammo":1}),"Legacy shotgun actor receives primary defaults")

func _capture_goals() -> void:
	var restored: int = 0
	for id: String in Catalog.BASE_IDS:
		var mission: Dictionary = Catalog.load(id)
		var authored: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % Catalog.FILES[id]))
		var expected: Array = authored.get("stars",[]).duplicate(true)
		if not expected.any(func(goal: Dictionary) -> bool: return str(goal.get("id","")) == "no_kills"):
			expected.append({"id":"no_kills","label":"무사살","stat":"kills","op":"eq","value":0})
		check(mission.stars == expected,id+" preserves authored goals and restores the retired authoring no-kill goal")
		for goal: Dictionary in mission.stars:
			if str(goal.get("stat","")) in ["kills","arrests"]: restored += 1
	check(restored > 0,"Current operations expose authored capture/no-kill goals")
	check(not Catalog.briefings().any(func(mission: Dictionary) -> bool: return str(mission.id).ends_with("_ARREST")),"Retired arrest variants remain hidden")
	check(not Catalog.load("M01_ARREST").stars.any(func(goal: Dictionary) -> bool: return str(goal.get("stat","")) in ["kills","arrests"]),"Retired arrest goal contract is preserved")
