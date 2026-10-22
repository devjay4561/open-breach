extends SceneTree
## Authored ROE fixtures for native/browser integration. Gameplay uses only
## public issue/edit APIs and the fixed simulation step.
const Simulation = preload("res://scripts/simulation.gd")
const Schema = preload("res://scripts/mission_schema.gd")
const Equipment = preload("res://scripts/equipment_catalog.gd")
const STEP := 1.0 / 30.0
const TARGET := [7.5, 5.8]
var checks := 0
var failures: Array[String] = []

static func fixture(roe: String = "high_intensity") -> Dictionary:
	return {"schema_version":6,"id":"ROE_%s_UI" % roe.to_upper(),"revision":1,"title":"교전수칙 검증","title_en":"ROE Check","seed":42,"bounds":[20,12],"focus":[8,6],"custom":true,"roe":roe,
		"rooms":[{"id":"own_room","x":5.0,"z":6.0,"w":10.0,"d":12.0,"indoor":true},{"id":"hidden_room","x":15.0,"z":6.0,"w":10.0,"d":12.0,"indoor":true}],
		"walls":[{"id":"jamb_thin","x":10.0,"z":2.45,"w":0.2,"d":4.9,"thin":true,"height":2.6},{"id":"jamb_concrete","x":10.0,"z":9.35,"w":0.2,"d":5.3,"material":"concrete","height":2.6}],
		"doors":[{"id":"entry","x":10.0,"z":5.8,"w":0.2,"d":1.8,"axis":"z","state":"CLOSED","material":"wood","hinge_side":-1.0,"swing_sign":-1.0}],"props":[],
		"units":[{"id":"alpha","name":"ALPHA","role":"TEST","x":2.0,"z":5.8,"facing":0.0,"weapon":"standard","ammo":24,"hp":100.0,"equipment":{"frag":1,"stun":1},"armor":"none","helmet":"none"},{"id":"bravo","name":"BRAVO","role":"TEST","x":2.0,"z":7.0,"facing":0.0,"weapon":"standard","ammo":24,"hp":100.0,"equipment":{"frag":1,"stun":1},"armor":"none","helmet":"none"}],
		"enemies":[{"id":"unseen","name":"UNSEEN","x":17.0,"z":9.0,"facing":0.0,"weapon":"standard","ammo":24,"hp":100.0,"enemy_type":"sentry","passive":true}],"civilians":[],"objectives":["교전수칙을 검증하세요."],"win":[{"type":"reach_zone","zone":[18.0,1.0,0.5,0.5]}],"fail":[],"stars":[]}

static func canonical(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func run() -> void:
	var report := {"step":STEP,"seed":42,"cases":[]}
	for roe: String in ["precision","high_intensity"]:
		var data := fixture(roe)
		check(bool(Schema.check(data).ok),"ROE browser fixture passes the actual mission schema")
		var sim := Simulation.new()
		sim.load_mission(data)
		var before: Dictionary = sim.snapshot(true)
		var rngs := [sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state]
		var preview: Dictionary = sim.frag_target_preview("alpha",TARGET)
		check(sim.snapshot(true)==before and rngs==[sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state] and sim.tick==0,"Frag hover never changes plan, clock or random streams")
		var answer: Dictionary = sim.issue("alpha","THROW_FRAG",{"target":TARGET})
		if roe=="precision":
			check(not bool(answer.ok) and answer.get("message_key","")=="frag.forbidden","Precision rejects the actual primitive with a translated reason")
			check(sim.snapshot(true)==before,"Precision rejection preserves the complete plan")
			check(bool(sim.issue("alpha","THROW_STUN",{"target":TARGET}).ok),"Precision retains the existing flash primitive")
		else:
			check(bool(preview.get("ok",false)) and bool(answer.ok),"High intensity accepts the actual preview and primitive")
			check(preview.radius==Equipment.frag_stats().radius and preview.core_radius==Equipment.frag_stats().core_radius and preview.available_frags==1,"Preview reads the production profile and unreserved inventory")
			check(sim.snapshot(false).units[0].available_frags==0,"Queued frag is reserved in the public inventory")
			for _tick: int in range(90): sim.step(STEP)
			var events: Array = sim.snapshot(false).events
			check(events.filter(func(event: Dictionary)->bool:return event.type=="FRAG_RELEASE").size()==1 and events.filter(func(event: Dictionary)->bool:return event.type=="FRAG").size()==1,"Fixed steps generate one own release and one detonation")
			check(sim.units[0].commands[0].state=="SUCCEEDED" and sim.units[0].frags==0,"Actual flight/fuse completes and consumes exactly one frag")
			check(sim.snapshot(false).enemies.is_empty(),"Hidden hostile stays absent after an own grenade outside its room")
		report.cases.append({"roe":roe,"mission":data,"target":TARGET,"preview":preview})
	var directory := ProjectSettings.globalize_path("res://../tests/artifacts/roe-browser")
	check(DirAccess.make_dir_recursive_absolute(directory)==OK,"ROE fixture evidence directory is writable")
	var file := FileAccess.open(directory.path_join("preflight.json"),FileAccess.WRITE)
	check(file!=null,"ROE browser fixture evidence can be written")
	if file!=null: file.store_string(JSON.stringify(report,"\t")+"\n")
	print("BREACH_ROE_BROWSER_PREFLIGHT_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
