extends SceneTree
const Catalog = preload("res://scripts/mission_catalog.gd")
const Simulation = preload("res://scripts/simulation.gd")
const World = preload("res://scripts/world_view.gd")
const Visibility = preload("res://scripts/visibility_field.gd")
const Replay = preload("res://scripts/replay.gd")
func _initialize() -> void: call_deferred("run")
func stats(values: Array) -> Dictionary:
	values.sort()
	var total := 0.0
	for value in values: total += value
	return {"mean_ms":total / values.size(), "p95_ms":values[int(values.size()*0.95)], "max_ms":values[-1]}
func run() -> void:
	root.size = Vector2i(1440,900)
	var report := {"kind":"native headless CPU stages; excludes GPU rendering", "missions":{}}
	for id in ["M01", "M06"]:
		var data: Dictionary = Catalog.load(id)
		var sim := Simulation.new()
		sim.load_mission(data)
		var world := World.new()
		root.add_child(world)
		world.build(data)
		var record := Replay.new()
		record.begin(data)
		var samples := {"simulation":[],"snapshots":[],"recorder":[],"display":[],"moving_visibility":[]}
		var field := Visibility.new()
		field.build(data)
		var output: Array = []
		for i in range(180):
			var start := Time.get_ticks_usec()
			sim.step(1.0/30.0)
			samples.simulation.append((Time.get_ticks_usec()-start)/1000.0)
			start=Time.get_ticks_usec()
			var full: Dictionary=sim.snapshot(true)
			var visible: Dictionary=sim.snapshot(false)
			samples.snapshots.append((Time.get_ticks_usec()-start)/1000.0)
			start=Time.get_ticks_usec()
			record.capture(full)
			samples.recorder.append((Time.get_ticks_usec()-start)/1000.0)
			start=Time.get_ticks_usec()
			world.display(visible,"alpha",false,1.0/30.0)
			samples.display.append((Time.get_ticks_usec()-start)/1000.0)
			var observers: Array=visible.units.duplicate(true)
			for unit: Dictionary in observers:
				unit.x += sin(i*0.07)*2.0
				unit.facing += i*0.03
			start=Time.get_ticks_usec()
			field.update(observers, visible.doors, visible.smoke_zones)
			samples.moving_visibility.append((Time.get_ticks_usec()-start)/1000.0)
			output.append(field.polygons.duplicate())
		var result := {"visibility_hash":hash(output)}
		for key in samples: result[key]=stats(samples[key])
		report.missions[id]=result
		world.queue_free()
		await process_frame
	var args := OS.get_cmdline_user_args()
	var path: String=args[0] if not args.is_empty() else "res://../tests/artifacts/performance-current/native.json"
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit()
