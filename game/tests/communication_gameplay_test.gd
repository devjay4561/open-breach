extends SceneTree
## P4 communication and wall noise use public commands and real 30 Hz steps.
## The sound observer passes every normal stimulus through exactly once.
const Simulation = preload("res://scripts/simulation.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const STEP := 1.0 / 30.0
const SEEDS := 30

class PassiveSoundProbe extends "res://scripts/simulation.gd":
	var emitted: Array = []
	func _emit_sound(origin: Vector2, radius: float, label: String, source_kind: String, context: Dictionary = {}) -> void:
		super._emit_sound(origin,radius,label,source_kind,context)
		var heard: Dictionary = {}
		for enemy: Dictionary in enemies:
			var memory: Dictionary = enemy.get("_heard_memory",{})
			heard[str(enemy.id)] = {"heard":str(memory.get("label",""))==label and is_equal_approx(float(memory.get("time",-1.0)),time),"memory":memory.duplicate(true)}
		emitted.append({"tick":tick,"time":time,"origin":[origin.x,origin.y],"radius":radius,"label":label,"kind":source_kind,
			"source_floor":float(context.get("source_floor",0.0)),"wall_contact":not context.get("wall_contact",{}).is_empty(),"heard":heard})

var checks := 0
var failures: Array[String] = []
var report: Dictionary = {"step":STEP,"seeds":[0,29],"scope":"Actual named waits/CALLs, physical body FOV/LOS/smoke/floors, real locomotion foot contacts and ordinary enemy fire. No sound, shot, damage, NPC aim or private receipt injection."}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func point(raw: Array) -> Vector2:
	return Vector2(float(raw[0]),float(raw[1]))

func position(actor: Dictionary) -> Vector2:
	return Vector2(float(actor.x),float(actor.z))

func simulation(data: Dictionary) -> RefCounted:
	var sim: RefCounted = PassiveSoundProbe.new()
	sim.load_mission(data)
	sim.enemy_rules = Catalog.NORMAL.duplicate(true)
	return sim

func issue(sim: RefCounted, id: String, type: String, args: Dictionary = {}, append: bool = true) -> Dictionary:
	var answer: Dictionary = sim.issue(id,type,args,append)
	check(bool(answer.get("ok",false)),"%s actual %s accepted: %s" % [id,type,str(answer.get("message",""))])
	return answer

func advance(sim: RefCounted, ticks: int) -> void:
	for _tick: int in range(ticks): sim.step(STEP)

func fingerprint(sim: RefCounted) -> String:
	return JSON.stringify({"state":sim.snapshot(true),"units":sim.units,"rng":[sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state],"requests":sim._sync_requests,"sources":sim._sync_sources,"waits":sim._sync_waits,"sequence":sim._sequence,"command_sequence":sim._command_sequence,"revisions":sim.plan_revisions}).sha256_text()

func signal_fixture(seed_value: int, mode: String = "verbal", obstruction: String = "") -> Dictionary:
	var data := {"id":"P4_COMMUNICATION","seed":seed_value,"variant":"normal","bounds":[12,12],"walls":[],"props":[],"doors":[],"rooms":[],
		"units":[{"id":"alpha","x":6.0,"z":6.0,"facing":PI},{"id":"delta","x":4.0,"z":6.0,"facing":0.0,"smokes":1},{"id":"charlie","x":5.0,"z":7.0,"facing":-PI*0.5}],
		"enemies":[{"id":"listener","x":5.0,"z":8.0,"facing":PI*0.5,"ammo":0,"reserve_ammo":0,"response_role":"guard"}],"civilians":[],"win":[{"type":"reach_zone","zone":[11.5,11.5,0.1,0.1]}],"fail":[]}
	# The legacy absence of this field must retain default verbal behaviour.
	if mode!="default": data["noise_discipline"] = mode
	if obstruction=="rotate": data.units[0].facing = 0.0
	if obstruction=="wall":
		data.walls = [{"id":"partition","x":5.0,"z":6.0,"w":0.2,"d":3.0,"height":2.6}]
		data.units[2].x = 4.0
	if obstruction=="floor": data.units[0]["base_height"] = 3.0
	if obstruction=="dead_sender": data.units[1]["hp"] = 0.0
	return data

func _queue_waits(sim: RefCounted, grouped: bool = false, delay: int = 0) -> void:
	for id: String in ["alpha","delta"]:
		var args := {"signal":"A"}
		if grouped:
			args["sync_id"] = "P4_TEST_READY"
			args["auto_signal"] = false
			args["delay_ticks"] = delay
		issue(sim,id,"WAIT_FOR_SIGNAL",args)
		issue(sim,id,"MOVE",{"target":[6.0 if id=="alpha" else 4.0,4.5]})
	advance(sim,2)
	check(sim.units[0].commands[0].state=="WAITING" and sim.units[1].commands[0].state=="WAITING","Both actual named waits become active before a public signal")

func signal_case(seed_value: int, mode: String = "verbal", explicit_sender: String = "") -> Dictionary:
	var sim := simulation(signal_fixture(seed_value,mode))
	_queue_waits(sim)
	var initial_enemy: Dictionary = sim.enemies[0].get("_heard_memory",{}).duplicate(true)
	var answered: Dictionary = sim.release_signal("A",explicit_sender)
	var memory: Dictionary = sim.enemies[0].get("_heard_memory",{}).duplicate(true)
	var occurrences: Array = sim.events.filter(func(event: Dictionary) -> bool: return str(event.type)=="SIGNAL")
	check(bool(answered.get("ok",false)) and int(answered.get("released",0))==2,"seed %d %s signal reaches both actually eligible waits" % [seed_value,mode])
	check(occurrences.size()==1,"seed %d one actual delivery creates one SIGNAL occurrence" % seed_value)
	var occurrence: Dictionary = occurrences[0] if not occurrences.is_empty() else {}
	var verbal := mode in ["verbal","default"]
	check(str(occurrence.get("source_unit_id",""))==("delta" if explicit_sender.is_empty() else explicit_sender),"Signal preserves the actual default/explicit live source")
	check(occurrence.get("receiver_unit_ids",[])==["alpha","delta"] and str(occurrence.get("signal_mode",""))==("verbal" if verbal else "hand_signals") and float(occurrence.get("signal_radius",-1.0))==(6.0 if verbal else 0.0),"Signal carries exact source/mode/received IDs and six-metre or silent provenance")
	if verbal:
		check(str(memory.get("label",""))=="팀 신호 감지" and memory!=initial_enemy,"Actual six-metre spoken signal reaches an unobserving ordinary enemy")
	else:
		check(memory==initial_enemy and not sim.emitted.any(func(event: Dictionary)->bool:return event.label=="팀 신호 감지"),"Received hand signal emits no sound or enemy hearing stimulus")
	advance(sim,4)
	check(sim.units[0].commands[0].state=="SUCCEEDED" and sim.units[1].commands[0].state=="SUCCEEDED" and position(sim.units[0]).distance_to(Vector2(6.0,6.0))>0.0 and position(sim.units[1]).distance_to(Vector2(4.0,6.0))>0.0,"Received waits release real subsequent movement")
	return {"seed":seed_value,"mode":mode,"sender":explicit_sender,"occurrence":occurrence,"heard_after_signal":memory,"state_hash":fingerprint(sim)}

func _blocked_signal_contracts() -> void:
	for obstruction: String in ["rotate","wall","floor","smoke"]:
		var sim := simulation(signal_fixture(0,"hand_signals",obstruction))
		if obstruction=="smoke":
			issue(sim,"delta","THROW_SMOKE",{"target":[5.0,6.0]})
			for _tick: int in range(120):
				sim.step(STEP)
				if not sim._smoke_zones.is_empty() and sim.units[1].commands[0].state=="SUCCEEDED": break
			check(not sim._smoke_zones.is_empty() and sim.units[1].commands[0].state=="SUCCEEDED","Actual public smoke throw supplies the blocked hand-signal segment")
		# The sender need not itself wait. Only the actual blocked receiver is
		# queued, so self-delivery cannot be mistaken for successful handoff.
		issue(sim,"alpha","WAIT_FOR_SIGNAL",{"signal":"B"})
		issue(sim,"alpha","MOVE",{"target":[6.0,4.5]})
		advance(sim,2)
		var waiting: Dictionary = sim.units[0].commands[0]
		var before := fingerprint(sim)
		var answered: Dictionary = sim.release_signal("B","delta")
		check(bool(answered.get("ok",false)) and int(answered.get("released",-1))==0 and waiting.state=="WAITING" and fingerprint(sim)==before,"Actual %s blockage leaves wait, requests, poses, revisions and all RNG streams unchanged" % obstruction)
		var here := position(sim.units[0])
		advance(sim,6)
		check(waiting.state=="WAITING" and position(sim.units[0]).is_equal_approx(here) and sim.units[0].commands[1].state=="PENDING","Blocked %s hand signal never starts the future MOVE" % obstruction)
	var named := simulation(signal_fixture(0,"hand_signals","rotate"))
	_queue_waits(named,true)
	var before := fingerprint(named)
	var receipt: Dictionary = named.release_signal("A","delta")
	check(bool(receipt.get("ok",false)) and named.units[0].commands[0].state=="WAITING" and named.units[1].commands[0].state=="WAITING" and fingerprint(named)==before,"A named two-person hand cohort is atomic when one actual body FOV blocks delivery")
	for wrong: String in ["missing","listener"]:
		var sim := simulation(signal_fixture(0,"verbal"))
		_queue_waits(sim)
		var old := fingerprint(sim)
		var rejected: Dictionary = sim.release_signal("A",wrong)
		check(not bool(rejected.get("ok",false)) and str(rejected.get("message_key",""))=="team.invalid_sender" and fingerprint(sim)==old,"Explicit non-own source %s is rejected without a fallback broadcaster" % wrong)
	var dead := simulation(signal_fixture(0,"verbal","dead_sender"))
	issue(dead,"alpha","WAIT_FOR_SIGNAL",{"signal":"A"})
	advance(dead,2)
	var old := fingerprint(dead)
	var rejected: Dictionary = dead.release_signal("A","delta")
	check(not bool(rejected.get("ok",false)) and fingerprint(dead)==old and dead.units[0].commands[0].state=="WAITING","An explicit dead source cannot silently fall back to another live own unit")

func _reused_sync_contract() -> void:
	var sim := simulation(signal_fixture(0,"verbal"))
	for id: String in ["alpha","delta"]: issue(sim,id,"WAIT_FOR_SIGNAL",{"signal":"C","sync_id":"REUSED","auto_signal":false,"delay_ticks":100})
	advance(sim,2)
	var requested: Dictionary = sim.release_signal("C","delta")
	check(bool(requested.get("ok",false)) and sim.units[0].commands[0].state=="WAITING" and sim.units[1].commands[0].state=="WAITING","Manual delayed signal request remains latched only to its original active waits")
	# Removing an executing WAIT first preserves its CANCELLED history. Remove
	# that terminal node through the same public API before reusing the ID.
	for id: String in ["alpha","delta"]:
		sim.remove_command(id,0)
		sim.remove_command(id,0)
	check(sim.units[0].commands.is_empty() and sim.units[1].commands.is_empty(),"Public removal cancels the original delayed waiting cohort")
	for id: String in ["alpha","delta"]: issue(sim,id,"WAIT_FOR_SIGNAL",{"signal":"C","sync_id":"REUSED","auto_signal":false,"delay_ticks":0})
	advance(sim,105)
	check(sim.units[0].commands[0].state=="WAITING" and sim.units[1].commands[0].state=="WAITING" and not sim._sync_requests.has("REUSED"),"Reusing a cancelled sync ID cannot inherit the previous occurrence's delayed receipt")
	var fresh: Dictionary = sim.release_signal("C","alpha")
	check(bool(fresh.get("ok",false)) and sim.units[0].commands[0].state=="SUCCEEDED" and sim.units[1].commands[0].state=="SUCCEEDED","A fresh actual sender releases the new occurrence after cancellation")

func foot_fixture(seed_value: int, close: bool) -> Dictionary:
	return {"id":"P4_WALL_CONTACT","seed":seed_value,"bounds":[12,12],"walls":[{"id":"partition","x":6.0,"z":6.0,"w":0.2,"d":12.0,"height":2.6}],"props":[],"doors":[],
		"rooms":[{"id":"left","x":3.0,"z":6.0,"w":6.0,"d":12.0,"floor_surface":"concrete"},{"id":"right","x":9.0,"z":6.0,"w":6.0,"d":12.0,"floor_surface":"concrete"},{"id":"upper","x":9.0,"z":6.0,"w":6.0,"d":12.0,"base_height":3.0,"floor_surface":"concrete"}],
		"units":[{"id":"alpha","x":5.61 if close else 5.59,"z":4.0,"facing":PI*0.5,"movement_mode":"normal","stance":"standing"}],
		"enemies":[{"id":"same","x":4.8,"z":4.7,"facing":PI,"ammo":0,"reserve_ammo":0},{"id":"opposite","x":6.6,"z":4.7,"facing":0.0,"ammo":0,"reserve_ammo":0},{"id":"upper","x":6.6,"z":4.7,"facing":0.0,"base_height":3.0,"ammo":0,"reserve_ammo":0}],"civilians":[],"win":[{"type":"reach_zone","zone":[11.5,11.5,0.1,0.1]}],"fail":[]}

func foot_case(seed_value: int, close: bool) -> Dictionary:
	var sim := simulation(foot_fixture(seed_value,close))
	issue(sim,"alpha","MOVE",{"target":[5.61 if close else 5.59,6.0]})
	advance(sim,60)
	var steps: Array = sim.emitted.filter(func(event: Dictionary) -> bool: return event.label=="발소리 감지" and event.kind=="unit")
	check(not steps.is_empty() and float(sim.units[0].travel_distance)>0.4,"seed %d actual normal locomotion crosses real foot-contact events" % seed_value)
	var step_event: Dictionary = steps[0] if not steps.is_empty() else {}
	check(is_equal_approx(float(step_event.get("radius",0.0)),3.1*(1.5 if close else 1.0)) and bool(step_event.get("wall_contact",false))==close,"seed %d wall surface %.2fm applies exactly the 1.5 contact multiplier" % [seed_value,0.29 if close else 0.31])
	var hearing: Dictionary = step_event.get("heard",{})
	check(bool(hearing.get("same",{}).get("heard",false)),"Actual foot stimulus reaches the same-floor listener on the source side")
	check(bool(hearing.get("opposite",{}).get("heard",false))==close,"Actual close-wall contact crosses into the opposite neighbor; ordinary far foot noise does not")
	check(not bool(hearing.get("upper",{}).get("heard",false)),"Wall contact cannot transfer foot sound to a different physical floor")
	return {"seed":seed_value,"close":close,"first_foot":step_event,"foot_contacts":steps.size(),"travel":sim.units[0].travel_distance,"state_hash":fingerprint(sim)}

func _reload_contracts() -> void:
	for configuration: String in ["received","blocked","far_received"]:
		var data := signal_fixture(0,"hand_signals")
		data.enemies = []
		data.units = [{"id":"alpha","x":4.0,"z":6.0,"facing":0.0,"ammo":0,"reserve_ammo":24},{"id":"bravo","x":6.0,"z":6.0,"facing":PI if configuration=="received" else 0.0}]
		if configuration=="far_received": data.units.append({"id":"delta","x":7.0,"z":6.0,"facing":PI})
		var sim := simulation(data)
		issue(sim,"alpha","FACE",{"target":[7.0,6.0],"persistent":true,"sector":{"start":-0.4,"end":0.4,"duration":20.0}})
		for actor: Dictionary in sim.units.slice(1): issue(sim,str(actor.id),"FACE",{"target":[4.0,6.0] if configuration=="received" or actor.id=="delta" else [9.0,6.0],"persistent":true,"sector":{"start":2.8,"end":-2.8,"duration":20.0}})
		advance(sim,1)
		var cover_id := "bravo" if configuration=="received" else ("delta" if configuration=="far_received" else "")
		var cover: Dictionary = sim._find(sim.units,cover_id)
		var previous: Dictionary = {}
		if not cover.is_empty(): previous = {"facing":cover.facing,"locked":cover.facing_locked,"persistent":cover.facing_persistent,"sector":cover.sector.duplicate(true),"commands":cover.commands.duplicate(true),"ammo":cover.ammo,"reserve":cover.reserve_ammo}
		issue(sim,"alpha","RELOAD")
		advance(sim,1)
		check(sim._reload_covers.has("alpha") and str(sim._reload_covers.alpha.cover_unit_id)==cover_id,"Actual %s hand reload selects only an ally that received the call before the lease" % configuration)
		var calls: Array = sim.events.filter(func(event: Dictionary)->bool:return event.type=="CALL_RELOADING")
		check(calls.size()==1 and (cover_id.is_empty() or calls[0].receiver_unit_ids.has(cover_id)),"Actual reload-cover candidate is present in the original occurrence receipt")
		if not cover.is_empty():
			check(absf(angle_difference(float(cover.facing),float(sim.units[0].facing)))<0.0001 and cover.commands==previous.commands,"A received lease really turns the ally without editing its queue")
		var completed := false
		for _tick: int in range(180):
			sim.step(STEP)
			if sim.units[0].commands.back().state=="SUCCEEDED":
				completed = true
				break
		check(completed and int(sim.units[0].ammo)==int(sim.units[0].max_ammo) and not sim._reload_covers.has("alpha"),"Actual %s reload completes and releases its temporary lease" % configuration)
		if not cover.is_empty(): check(cover.facing==previous.facing and cover.facing_locked==previous.locked and cover.facing_persistent==previous.persistent and cover.sector==previous.sector and cover.commands==previous.commands and cover.ammo==previous.ammo and cover.reserve_ammo==previous.reserve,"Reload completion restores pre-handoff facing, sector, queue and resources even after lease turning blocks mutual hand LOS")
		var up: Array = sim.events.filter(func(event: Dictionary)->bool:return event.type=="CALL_GUN_UP")
		check(up.size()==1 and str(up[0].signal_mode)=="hand_signals" and float(up[0].signal_radius)==0.0,"Actual reload completion emits one silent gun-up occurrence")

func man_down_case(seed_value: int, mode: String) -> Dictionary:
	# One authored wounded point man still requires ordinary enemy observation,
	# aim, accuracy and damage. The other live receiver deliberately faces away
	# from the actual reporting witness, so hand delivery is not an authority gate.
	var data := {"id":"P4_CALL_MAN_DOWN","seed":seed_value,"noise_discipline":mode,"bounds":[12,12],"rooms":[],"walls":[],"props":[],"doors":[],
		"units":[{"id":"alpha","x":4.0,"z":6.0,"facing":PI,"hp":1.0,"ammo":0,"reserve_ammo":0},{"id":"bravo","x":4.0,"z":8.0,"facing":-PI*0.5,"ammo":0,"reserve_ammo":0},{"id":"charlie","x":2.0,"z":8.0,"facing":PI,"ammo":0,"reserve_ammo":0}],
		"enemies":[{"id":"shooter","x":6.0,"z":6.0,"facing":PI,"response_role":"guard"}],"civilians":[],"win":[{"type":"reach_zone","zone":[11.5,11.5,0.1,0.1]}],"fail":[]}
	var sim := simulation(data)
	check(bool(sim.configure_team_settings({"auto_pause_man_down":true}).get("ok",false)),"Actual MAN_DOWN authority pause is enabled through the public setting")
	issue(sim,"bravo","FACE",{"target":[4.0,6.0],"persistent":true})
	issue(sim,"charlie","FACE",{"target":[0.0,8.0],"persistent":true})
	var first_death := -1
	for _tick: int in range(180):
		sim.step(STEP)
		if float(sim.units[0].hp)<=0.0:
			first_death = sim.tick
			break
	var calls: Array = sim.events.filter(func(event: Dictionary)->bool:return event.type=="CALL_MAN_DOWN")
	check(first_death>0 and sim.hits_taken>0 and calls.size()==1 and int(calls[0].tick)==first_death,"seed %d %s ordinary hostile fire causes actual death and one same-tick MAN_DOWN" % [seed_value,mode])
	check(sim.pause_requested and sim.pause_reason=="man_down" and sim._man_down_handled.has("alpha"),"Loss authority and explicit pause occur independently of signal delivery")
	var call: Dictionary = calls[0] if not calls.is_empty() else {}
	check(str(call.get("unit_id",""))=="alpha" and str(call.get("source_unit_id",""))=="bravo","Death subject and actual living witness source have distinct identities")
	check(call.get("receiver_unit_ids",[]).has("charlie")==(mode=="verbal") and float(call.get("signal_radius",-1.0))==(6.0 if mode=="verbal" else 0.0),"Verbal delivery reaches the ally while mutually blocked hand delivery leaves the same casualty authority intact")
	return {"seed":seed_value,"mode":mode,"death_tick":first_death,"hits":sim.hits_taken,"call":call,"state_hash":fingerprint(sim)}

func _benchmark() -> void:
	var signals: Array = []
	var footsteps: Array = []
	var losses: Array = []
	for seed_value: int in range(SEEDS):
		for mode: String in ["verbal","hand_signals"]:
			var signal_row := signal_case(seed_value,mode)
			check(JSON.stringify(signal_row)==JSON.stringify(signal_case(seed_value,mode)),"seed %d %s public signal repeats full state/RNG and actual occurrence" % [seed_value,mode])
			signals.append(signal_row)
			var casualty := man_down_case(seed_value,mode)
			check(JSON.stringify(casualty)==JSON.stringify(man_down_case(seed_value,mode)),"seed %d %s real casualty and delivery repeat exactly" % [seed_value,mode])
			losses.append(casualty)
		for close: bool in [true,false]:
			var foot := foot_case(seed_value,close)
			check(JSON.stringify(foot)==JSON.stringify(foot_case(seed_value,close)),"seed %d actual near/far wall foot contacts repeat full state and four RNG streams" % seed_value)
			footsteps.append(foot)
	report["signals"] = signals
	report["footsteps"] = footsteps
	report["man_down"] = losses

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or "--signals-only" in args or "--contracts-only" in args:
		signal_case(0,"default")
		signal_case(0,"verbal","charlie")
		signal_case(0,"hand_signals","charlie")
		_blocked_signal_contracts()
		_reused_sync_contract()
	if args.is_empty() or "--reload-only" in args or "--contracts-only" in args: _reload_contracts()
	if "--footsteps-only" in args:
		print("COMMUNICATION_FOOT_PROBE " + JSON.stringify({"close":foot_case(0,true),"far":foot_case(0,false)}))
	if "--man-down-only" in args:
		print("COMMUNICATION_MAN_DOWN_PROBE " + JSON.stringify({"verbal":man_down_case(0,"verbal"),"hand":man_down_case(0,"hand_signals")}))
	if args.is_empty() or "--benchmarks-only" in args: _benchmark()
	if args.is_empty():
		var directory := ProjectSettings.globalize_path("res://../tests/artifacts/cqb-p4")
		DirAccess.make_dir_recursive_absolute(directory)
		var artifact := FileAccess.open(directory.path_join("communication-gameplay.json"),FileAccess.WRITE)
		check(artifact!=null,"P4 actual communication fixed-seed evidence is writable")
		report.checks = checks
		report.failures = failures.duplicate()
		if artifact!=null: artifact.store_string(JSON.stringify(report,"\t")+"\n")
	print("BREACH_COMMUNICATION_GAMEPLAY_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
