extends SceneTree
const Sim = preload("res://tests/perf/movement_profile.gd")
const Nav = preload("res://tests/perf/navigation_profile.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Replay = preload("res://scripts/replay.gd")
func _initialize() -> void: call_deferred("run")
func stats(values: Array) -> Dictionary:
	values.sort()
	var total := 0.0
	for value in values: total += value
	return {"mean_ms":total/values.size(),"p95_ms":values[int(values.size()*.95)],"max_ms":values[-1]}
func run() -> void:
	var data := Catalog.load("M06")
	var sim := Sim.new()
	sim.nav=Nav.new()
	var start := Time.get_ticks_usec()
	sim.load_mission(data)
	var load_ms := (Time.get_ticks_usec()-start)/1000.0
	var startup: Dictionary=sim.nav.timings.duplicate(true)
	sim.nav.timings.clear()
	start=Time.get_ticks_usec()
	var orders: Array=[]
	for i in range(4):
		var x: float=[7.1,8.6,24.1,25.6][i]
		for z in [27.2,23.0,14.0]: orders.append(sim.plan_move(sim.units[i].id,{"target":[25.0 if i == 2 and z == 14.0 else x,z]},true))
	var plan_ms := (Time.get_ticks_usec()-start)/1000.0
	var plan: Dictionary=sim.nav.timings.duplicate(true)
	sim.nav.timings.clear()
	var record:=Replay.new()
	record.begin(data)
	var step_times: Array=[]
	var record_times: Array=[]
	var snapshots: Array=[]
	var hashes: Array=[]
	var memory: Array=[]
	var max_moving := 0
	for i in range(900):
		start=Time.get_ticks_usec();sim.step(1.0/30.0);step_times.append((Time.get_ticks_usec()-start)/1000.0)
		start=Time.get_ticks_usec();var state: Dictionary=sim.snapshot(true);snapshots.append((Time.get_ticks_usec()-start)/1000.0)
		hashes.append(hash(state))
		max_moving=maxi(max_moving,sim.units.filter(func(u):return u.status=="MOVING").size())
		start=Time.get_ticks_usec();record.capture(state);record_times.append((Time.get_ticks_usec()-start)/1000.0)
		if i%300==0: memory.append({"tick":i,"native_static_bytes":OS.get_static_memory_usage(),"replay_estimated_bytes":record.estimate_memory_bytes()})
	var seek_times: Array=[]
	for i in range(240):
		start=Time.get_ticks_usec();record.seek(fmod(i*0.127,record.duration),true);seek_times.append((Time.get_ticks_usec()-start)/1000.0)
	var report: Dictionary={"movement_peaks":sim.movement_peaks,"load_ms":load_ms,"plan_ms":plan_ms,"startup_nav_inclusive_us":startup,"planning_nav_inclusive_us":plan,"simulation_inclusive_us":sim.timings,"navigation_inclusive_us":sim.nav.timings,"tick":stats(step_times),"snapshot":stats(snapshots),"record":stats(record_times),"seek":stats(seek_times),"state_hash":hash(hashes),"memory":memory,"max_moving":max_moving,"shots":sim.shots_fired,"time":sim.time,"command_failures":sim.command_failures,"orders":orders}
	var path:=OS.get_cmdline_user_args()[0]
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report));quit()
