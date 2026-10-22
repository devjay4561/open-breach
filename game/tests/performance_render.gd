extends SceneTree
const World=preload("res://tests/perf/world_profile.gd")
const Replay=preload("res://scripts/replay.gd")
const Catalog=preload("res://scripts/mission_catalog.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1440,900)
	var replay:=Replay.new()
	var loaded:=replay.load_data(JSON.parse_string(FileAccess.get_file_as_string("res://../tests/artifacts/combat-benchmark.breach-replay.json")))
	if not loaded.ok:push_error(str(loaded));quit(1);return
	var world:=World.new();root.add_child(world);world.build(Catalog.load("M01"))
	var result: Dictionary={}
	for phase in ["moving","paused"]:
		world.timings.clear()
		var displays: Array=[];var seeks: Array=[]
		for i in range(240):
			var start:=Time.get_ticks_usec()
			var state:=replay.seek(1.0+i/60.0 if phase=="moving" else 8.0,true)
			var seek_us:=Time.get_ticks_usec()-start
			state["presentation_reveal"]=true
			state["presentation_paused"]=phase=="paused"
			start=Time.get_ticks_usec();world.display(state,"alpha",phase=="paused",1.0/60.0)
			if i==59:world.timings.clear()
			if i>=60:displays.append((Time.get_ticks_usec()-start)/1000.0);seeks.append(seek_us/1000.0)
		displays.sort();seeks.sort()
		var sum:=0.0
		for n in displays:sum+=n
		result[phase]={"display_mean_ms":sum/displays.size(),"display_p95_ms":displays[int(displays.size()*.95)],"seek_p95_ms":seeks[int(seeks.size()*.95)],"calls_inclusive_us":world.timings.duplicate(true)}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));world.queue_free();await process_frame;quit()
