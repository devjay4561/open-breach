extends SceneTree
## P5 gameplay contracts use public commands and the fixed simulation clock.
## All damage and casualties below come from actual released projectiles.
const Simulation = preload("res://scripts/simulation.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const ObservedStatistics = preload("res://scripts/observed_statistics.gd")
const STEP := 1.0 / 30.0
const TICKS := 90
const SEEDS := 30
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _fixture(seed_value: int = 0, roe: String = "high_intensity", material: String = "", wall_height: float = 2.6) -> Dictionary:
	var walls: Array = []
	if not material.is_empty(): walls.append({"id":"divider","x":9.0,"z":8.0,"w":0.2,"d":16.0,"height":wall_height,"material":material})
	return {"schema_version":6,"id":"ROE_GAMEPLAY","seed":seed_value,"roe":roe,"bounds":[16,16],
		"rooms":[{"id":"source","x":4.5,"z":8.0,"w":9.0,"d":16.0},{"id":"neighbor","x":12.5,"z":8.0,"w":7.0,"d":16.0}],
		"walls":walls,"props":[],"doors":[],"civilians":[],"enemies":[],
		"units":[{"id":"alpha","x":3.0,"z":8.0,"facing":0.0,"armor":"none","helmet":"none","equipment":{"frag":2},"stuns":0},
			{"id":"bravo","x":10.0,"z":8.0,"facing":PI,"armor":"none","helmet":"none","equipment":{},"ammo":0,"reserve_ammo":0,"hold_position":true}],
		"win":[{"type":"reach_zone","zone":[15.0,1.0,0.1,0.1]}],"fail":[]}

func _simulation(data: Dictionary) -> BreachSimulation:
	var sim := Simulation.new()
	sim.load_mission(data)
	sim.enemy_rules = Catalog.NORMAL.duplicate(true)
	return sim

func _issue(sim: BreachSimulation, id: String, type: String, args: Dictionary = {}, append: bool = true) -> Dictionary:
	var answer := sim.issue(id,type,args,append)
	check(bool(answer.get("ok",false)),"Public %s %s is accepted: %s" % [id,type,answer.get("message","")])
	return answer

func _rng(sim: BreachSimulation) -> Array:
	return [sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state]

func _state(sim: BreachSimulation) -> String:
	return JSON.stringify({"snapshot":sim.snapshot(true),"rng":_rng(sim)})

func _planning_state(sim: BreachSimulation) -> String:
	return JSON.stringify({"snapshot":sim.snapshot(true),"units":sim.units,"rng":_rng(sim),
		"command_sequence":sim._command_sequence,"event_sequence":sim._sequence,"revisions":sim.plan_revisions,
		"requests":sim._requests,"reservations":sim._reservations,"insert_resource_index":sim._insert_resource_index,
		"preview_batch_depth":sim._preview_batch_depth,"preview_dirty_units":sim._preview_dirty_units})

func _events(sim: BreachSimulation, type: String) -> Array:
	return sim.events.filter(func(event: Dictionary) -> bool: return str(event.type)==type)

func _advance(sim: BreachSimulation, frames: int) -> void:
	for _frame: int in range(frames): sim.step(STEP)

func _roe_and_resources() -> void:
	var data := _fixture(0,"precision")
	data.units[0].equipment = {"frag":1,"stun":1}
	data.units[0].stuns = 1
	var sim := _simulation(data)
	var preview_before := _planning_state(sim)
	var forbidden_preview := sim.frag_target_preview("alpha",[8.0,8.0])
	check(not bool(forbidden_preview.get("ok",false)) and _planning_state(sim)==preview_before,"Precision preview is rejected without changing plans, inventory or RNG")
	_issue(sim,"alpha","WAIT",{"duration":1.0})
	for append: bool in [true,false]:
		var before := _planning_state(sim)
		var rejected := sim.issue("alpha","THROW_FRAG",{"target":[8.0,8.0]},append)
		check(not bool(rejected.get("ok",false)) and _planning_state(sim)==before,"Precision rejects FRAG atomically without replacing the existing plan")
	var before := _planning_state(sim)
	check(not bool(sim.insert_command("alpha",0,"THROW_FRAG",{"target":[8.0,8.0]}).get("ok",false)) and _planning_state(sim)==before,"Precision rejects inserted FRAG without IDs, reservations or RNG changes")
	_issue(sim,"alpha","THROW_STUN",{"target":[8.0,8.0]})
	_advance(sim,TICKS)
	check(_events(sim,"FLASH_RELEASE").size()==1 and int(sim.units[0].stuns)==0,"Precision still permits an actual FLASH release and one inventory consumption")
	data = _fixture()
	data.erase("roe")
	var legacy := _simulation(data)
	before = _planning_state(legacy)
	check(not bool(legacy.issue("alpha","THROW_FRAG",{"target":[8.0,8.0]}).get("ok",false)) and _planning_state(legacy)==before,"Missing ROE defaults to precision with an atomic FRAG rejection")
	var reserved := _simulation(_fixture())
	before = _planning_state(reserved)
	var preview := reserved.frag_target_preview("alpha",[8.0,8.0])
	check(bool(preview.get("ok",false)) and int(preview.get("available_frags",-1))==2 and _planning_state(reserved)==before,"High-intensity preview is a pure query of actual owned inventory and static throw geometry")
	_issue(reserved,"alpha","THROW_FRAG",{"target":[8.0,8.0]})
	_issue(reserved,"alpha","THROW_FRAG",{"target":[7.5,8.0]})
	before = _planning_state(reserved)
	check(not bool(reserved.issue("alpha","THROW_FRAG",{"target":[7.0,8.0]}).get("ok",false)) and _planning_state(reserved)==before,"Queued FRAG commands reserve the finite owned inventory")
	check(not bool(reserved.insert_command("alpha",0,"THROW_FRAG",{"target":[7.0,8.0]}).get("ok",false)) and _planning_state(reserved)==before,"Inserted FRAG cannot borrow inventory reserved by queued throws")
	check(bool(reserved.update_command_args("alpha",0,{"target":[8.0,7.5]}).get("ok",false)),"Editing the same queued FRAG retains its own reservation")
	reserved.remove_command("alpha",1)
	_issue(reserved,"alpha","THROW_FRAG",{"target":[7.0,8.0]})
	check(int(reserved.units[0].get("frags",-1))==2,"Pending plan edits do not consume physical grenade inventory")
	_issue(reserved,"alpha","CANCEL_PENDING")
	_issue(reserved,"alpha","THROW_FRAG",{"target":[8.0,8.0]})
	before = _planning_state(reserved)
	for target: Array in [[15.9,15.9],[INF,8.0],[true,8.0]]:
		check(not bool(reserved.issue("alpha","THROW_FRAG",{"target":target}).get("ok",false)) and _planning_state(reserved)==before,"Invalid or unreachable FRAG target preserves the valid pending plan")

func _fuse_and_cancel() -> void:
	var sim := _simulation(_fixture())
	var rng_before := _rng(sim)
	_issue(sim,"alpha","THROW_FRAG",{"target":[8.0,8.0]})
	var initial_hp := float(sim.units[1].hp)
	var release: Dictionary = {}
	var explosion: Dictionary = {}
	var pre_fuse_intact := true
	var saw_flight := false
	var saw_fuse := false
	for _frame: int in range(TICKS):
		sim.step(STEP)
		var releases := _events(sim,"FRAG_RELEASE")
		if not releases.is_empty(): release = releases[0]
		var explosions := _events(sim,"FRAG")
		if not explosions.is_empty(): explosion = explosions[0]
		for projectile: Dictionary in sim.snapshot(true).get("frag_projectiles",[]):
			saw_flight = saw_flight or str(projectile.phase)=="FLIGHT"
			saw_fuse = saw_fuse or str(projectile.phase)=="FUSE"
		if not release.is_empty() and sim.time<float(release.get("detonate_at",INF)):
			pre_fuse_intact = pre_fuse_intact and is_equal_approx(float(sim.units[1].hp),initial_hp)
	check(_events(sim,"FRAG_RELEASE").size()==1 and _events(sim,"FRAG").size()==1,"Actual FRAG has exactly one release and one detonation")
	check(saw_flight and saw_fuse and sim.snapshot(true).get("frag_projectiles",[]).is_empty(),"Authoritative projectile advances through real flight and fuse phases, then disappears on detonation")
	check(not release.is_empty() and float(release.get("time",0.0))>=0.6 and float(release.get("time",INF))<=0.6+STEP+0.00001,"FRAG preparation lasts the fixed 0.6-second action before actual release")
	check(pre_fuse_intact and not explosion.is_empty() and float(explosion.get("time",0.0))+0.00001>=float(release.get("detonate_at",INF)),"No blast damage occurs before the authoritative fuse deadline")
	check(not explosion.is_empty() and float(explosion.time)-float(release.get("detonate_at",0.0))<=STEP+0.00001,"FRAG detonates on the first eligible fixed STEP")
	check(float(sim.units[1].hp)<initial_hp and is_equal_approx(float(sim.units[0].hp),100.0),"Actual blast hurts the nearby teammate while the distant thrower remains safe")
	check(int(sim.units[0].get("frags",-1))==1 and int(sim.snapshot(true).get("frags_used",-1))==1,"Release consumes and counts exactly one FRAG")
	check(_rng(sim)==rng_before,"A grenade-only mission consumes no AI, accuracy/body, breach or surrender RNG")
	for after_release: bool in [false,true]:
		var cancelled := _simulation(_fixture())
		_issue(cancelled,"alpha","THROW_FRAG",{"target":[8.0,8.0]})
		for _frame: int in range(45):
			cancelled.step(STEP)
			if not after_release or not _events(cancelled,"FRAG_RELEASE").is_empty(): break
		cancelled.remove_command("alpha",0)
		_advance(cancelled,TICKS)
		check(str(cancelled.units[0].commands[0].state)=="CANCELLED","Public removal can cancel an active FRAG command")
		check(_events(cancelled,"FRAG_RELEASE").size()==int(after_release) and _events(cancelled,"FRAG").size()==int(after_release),"Cancellation before release prevents explosion; cancellation after release preserves the independent projectile")
		check(int(cancelled.units[0].get("frags",-1))==2-int(after_release),"Cancellation cannot refund a grenade already released or consume one still held")

func _damage_case(seed_value: int, material: String = "drywall", wall_height: float = 2.6, armor: String = "none") -> Dictionary:
	var data := _fixture(seed_value,"high_intensity",material,wall_height)
	data.units[1].armor = armor
	var sim := _simulation(data)
	var initial_rng := _rng(sim)
	var hp_before := float(sim.units[1].hp)
	_issue(sim,"alpha","THROW_FRAG",{"target":[8.0,8.0]})
	_advance(sim,TICKS)
	var damage := hp_before-float(sim.units[1].hp)
	check(sim.tick==TICKS and _events(sim,"FRAG").size()==1,"Every damage sample runs its fixed 90 STEP and actual detonation")
	check(is_equal_approx(float(sim.units[0].hp),100.0),"A five-metre standoff preserves the actual thrower's health")
	check(_rng(sim)==initial_rng,"Material/armor blast attenuation does not consume unrelated RNG")
	check(is_equal_approx(float(sim.snapshot(true).get("unit_damage",-1.0)),damage),"Owned injury statistics equal the actual HP delta rather than attempted or absorbed damage")
	return {"seed":seed_value,"damage":damage,"state":_state(sim),"stats":sim.snapshot(true)}

func _walls_armor_and_repeat(repeat: bool = true) -> void:
	var open := _damage_case(0,"")
	var drywall := _damage_case(0,"drywall")
	var plaster := _damage_case(0,"plaster")
	var concrete := _damage_case(0,"concrete")
	var metal := _damage_case(0,"metal")
	check(float(open.damage)>float(drywall.damage) and float(drywall.damage)>0.0,"Physical drywall attenuates fragments but still hurts an actual neighboring-room teammate")
	check(is_equal_approx(float(drywall.damage),float(plaster.damage)),"Drywall and plaster use the same existing material resistance")
	check(is_zero_approx(float(concrete.damage)) and is_zero_approx(float(metal.damage)),"Concrete and metal stop the same actual blast ray")
	var low := _damage_case(0,"concrete",0.05)
	check(float(low.damage)>0.0,"An obstacle below the actual fragment ray does not act as a full-height wall")
	var armored := _damage_case(0,"",2.6,"frame_v2")
	check(float(armored.damage)>0.0 and float(armored.damage)<float(open.damage),"Actual torso armor reduces fragment injury without making the teammate immune")
	if not repeat: return
	for seed_value: int in range(SEEDS):
		var first := _damage_case(seed_value)
		var second := _damage_case(seed_value)
		check(float(first.damage)>0.0 and first==second,"Seed%d repeated actual wall penetration preserves HP deltas, full state and all four RNG streams" % seed_value)

func _released_projectile_survives_actual_death() -> void:
	var data := _fixture()
	data.units[0].hp = 1.0
	data.units[0].equipment = {"frag":1}
	# Two ordinary throws isolate the lifecycle without injecting injury. B's
	# earlier grenade really kills A after A's release but before A's fuse.
	data.units.append({"id":"charlie","x":3.0,"z":13.0,"facing":-PI*0.5,"armor":"none","helmet":"none","equipment":{"frag":1}})
	var sim := _simulation(data)
	_issue(sim,"alpha","WAIT",{"duration":0.4})
	_issue(sim,"alpha","THROW_FRAG",{"target":[8.0,8.0]})
	_issue(sim,"charlie","THROW_FRAG",{"target":[3.0,8.0]})
	var release: Dictionary = {}
	var death_tick := -1
	var projectile_after_death := false
	var hp_at_death := 100.0
	for _frame: int in range(120):
		sim.step(STEP)
		for event: Dictionary in _events(sim,"FRAG_RELEASE"):
			if str(event.unit_id)=="alpha": release = event
		if death_tick<0 and float(sim.units[0].hp)<=0.0:
			death_tick = sim.tick
			hp_at_death = float(sim.units[1].hp)
			projectile_after_death = not release.is_empty() and sim.snapshot(true).get("frag_projectiles",[]).any(func(projectile: Dictionary) -> bool: return str(projectile.unit_id)=="alpha")
	var explosions := _events(sim,"FRAG").filter(func(event: Dictionary) -> bool: return str(event.unit_id)=="alpha")
	check(death_tick>0 and not release.is_empty() and int(release.tick)<death_tick,"A real earlier grenade incapacitates the second thrower after its actual release")
	check(projectile_after_death and explosions.size()==1 and int(explosions[0].tick)>death_tick,"An already released projectile detonates once after its thrower becomes incapacitated")
	check(is_equal_approx(hp_at_death,100.0) and float(sim.units[1].hp)<hp_at_death,"The surviving independent projectile causes the later actual teammate HP delta")
	check(int(sim.snapshot(true).get("frags_used",-1))==2,"Two real released grenades consume exactly two inventories even across a casualty")

func _hidden_damage_observation() -> void:
	var data := _fixture(0,"high_intensity","drywall")
	data.units = data.units.slice(0,1)
	data.enemies = [{"id":"hidden_enemy","x":10.0,"z":8.0,"facing":0.0,"ammo":0,"reserve_ammo":0,"can_surrender":false}]
	data.civilians = [{"id":"hidden_civilian","x":10.0,"z":9.3}]
	var sim := _simulation(data)
	check(not bool(sim.enemies[0].visible) and not bool(sim.civilians[0].visible),"Opaque partition hides both authored NPCs before the actual throw")
	_issue(sim,"alpha","THROW_FRAG",{"target":[8.0,8.0]})
	_advance(sim,TICKS)
	var record := sim.snapshot(true)
	var observed := sim.snapshot(false)
	var paired := sim.snapshot_pair()
	check(float(sim.enemies[0].hp)<100.0 and float(sim.civilians[0].hp)<100.0,"Actual fragment penetration injures hidden enemy and civilian without forced damage")
	check(not bool(sim.enemies[0].visible) and not bool(sim.civilians[0].visible),"Penetration does not turn opaque walls into observation")
	check(float(record.get("civilian_damage",0.0))>0.0,"Authority records actual hidden civilian HP damage rather than only deaths")
	for state: Dictionary in [observed,paired.observed]:
		var encoded := JSON.stringify(state)
		check(not encoded.contains("hidden_enemy") and not encoded.contains("hidden_civilian"),"Player snapshots and paired observation disclose no hidden victim identity or current position")
		check(is_zero_approx(float(state.get("civilian_damage",0.0))),"Player damage statistics do not reveal unobserved civilian injury")
	check(JSON.stringify(paired.record)==JSON.stringify(record),"Paired recording retains exactly the authoritative fragment and damage state")

func _observed_star_receipts() -> void:
	# These are pure evidence-policy contracts. Actual blast damage above is
	# still produced only by public THROW_FRAG and normal fixed STEP execution.
	var definitions := [{"id":"civilian_safe","stat":"civilian_damage","op":"eq","value":0}]
	var mission := {"enemies":[],"civilians":[{"id":"civilian"}]}
	var units := [{"hp":100.0,"max_hp":100.0}]
	var unknown := ObservedStatistics.new()
	unknown.reset(mission)
	var clean := unknown.stars(definitions,{"civilian_damage":0.0},units,true,1)
	var hidden_hurt := unknown.stars(definitions,{"civilian_damage":50.0},units,true,1)
	check(bool(clean.actual.civilian_safe) and not bool(hidden_hurt.actual.civilian_safe),"Authority distinguishes clean and damaged civilians")
	check(clean.observed==hidden_hurt.observed and not bool(clean.observed.civilian_safe),"Unknown hidden damage cannot change the public zero-damage star")
	var injured_first := ObservedStatistics.new()
	injured_first.reset(mission)
	injured_first.observe({"id":"civilian","kind":"civilian","hp":50.0,"max_hp":100.0},1)
	var sighted := injured_first.stars(definitions,{"civilian_damage":50.0},units,true,1)
	check(is_zero_approx(float(injured_first.bundle(units).civilian_damage)) and not bool(sighted.observed.civilian_safe),"First sight of an injured civilian does not import hidden cumulative damage or establish a healthy baseline")
	var healthy := ObservedStatistics.new()
	healthy.reset(mission)
	healthy.observe({"id":"civilian","kind":"civilian","hp":100.0,"max_hp":100.0},1)
	check(not bool(healthy.stars(definitions,{"civilian_damage":0.0},units,true,2).observed.civilian_safe),"An old health observation cannot prove zero damage at a later completion tick")
	healthy.observe({"id":"civilian","kind":"civilian","hp":100.0,"max_hp":100.0},2)
	check(bool(healthy.stars(definitions,{"civilian_damage":0.0},units,true,2).observed.civilian_safe),"Healthy baseline and fresh terminal health jointly prove the zero-damage star")
	var preexisting := ObservedStatistics.new()
	preexisting.reset({"enemies":[{"id":"dead","hp":0.0}],"civilians":[]})
	preexisting.observe({"id":"dead","kind":"enemy","hp":0.0,"max_hp":72.0},1)
	check(int(preexisting.bundle(units).kills)==0 and int(preexisting.bundle(units).neutralized)==1,"A casualty already present in mission data is observable but is not a player kill")
	check(clean.actual.size()==1 and clean.observed.size()==1 and clean.actual.civilian_safe is bool and clean.observed.civilian_safe is bool,"Star receipt maps contain exactly the authored IDs and Boolean values")
	# Existing courtyard/garage/etc. define these reserved IDs with eq 0.
	# Their established meaning is mission success and surviving own roster,
	# rather than a synthetic Boolean value compared against that zero target.
	var standard := [{"id":"complete","stat":"command_failures","op":"eq","value":0},
		{"id":"survival","stat":"losses","op":"eq","value":0}]
	var standard_success := unknown.stars(standard,{"command_failures":0,"losses":0},units,true,1)
	check(standard_success.actual=={"complete":true,"survival":true} and standard_success.observed==standard_success.actual,"Existing zero-valued complete and survival definitions award both known own-side stars on successful completion")
	var standard_failed := unknown.stars(standard,{"command_failures":0,"losses":0},units,false,1)
	check(standard_failed.actual=={"complete":false,"survival":false} and standard_failed.observed==standard_failed.actual,"Failed missions award neither reserved star even when command failures and losses are zero")
	var standard_loss := unknown.stars(standard,{"command_failures":0,"losses":1},[{"hp":0.0,"max_hp":100.0}],true,1)
	check(standard_loss.actual=={"complete":true,"survival":false} and standard_loss.observed==standard_loss.actual,"A completed mission with an actual own casualty retains complete and fails survival")
	var standard_empty := unknown.stars(standard,{"command_failures":0,"losses":0},[],true,1)
	check(standard_empty.actual=={"complete":true,"survival":false} and standard_empty.observed==standard_empty.actual,"An empty own roster cannot prove all-unit survival")

func run() -> void:
	if not OS.get_cmdline_user_args().has("--stars-only"):
		_roe_and_resources()
		_fuse_and_cancel()
		_walls_armor_and_repeat(not OS.get_cmdline_user_args().has("--probe-only"))
		_released_projectile_survives_actual_death()
		_hidden_damage_observation()
	_observed_star_receipts()
	print("BREACH_ROE_GAMEPLAY_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
