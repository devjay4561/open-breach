extends SceneTree
## Native/headless repeatable render-side cost survey for all active battlefields.
## Run natively for GPU draw counts; headless still measures build/display CPU.
const Catalog = preload("res://scripts/mission_catalog.gd")
const World = preload("res://tests/perf/world_profile.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1600, 900)
	var results: Array = []
	var ids: Array[String] = []
	var destination := "../tests/artifacts/historical-render-performance.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("H"):
			ids.append(argument)
		else:
			destination = argument
	if ids.is_empty():
		ids.append_array(Catalog.HISTORICAL_IDS)
	for mission_id in ids:
		var path := "res://data/historical/" + mission_id + ".json"
		if not FileAccess.file_exists(path):
			push_error("Missing " + path)
			quit(1)
			return
		var mission: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var world := World.new()
		root.add_child(world)
		var start := Time.get_ticks_usec()
		world.build(mission)
		var build_ms := float(Time.get_ticks_usec() - start) / 1000.0
		var units: Array = mission.units.duplicate(true)
		for unit: Dictionary in units:
			unit["hp"] = 100.0
		var display_ms: Array[float] = []
		for frame in range(90):
			var time := float(frame) / 60.0
			for unit_index in range(units.size()):
				units[unit_index].x = float(mission.units[unit_index].x) + sin(time) * 0.15
			var state := {"units": units, "doors": mission.doors, "enemies": [], "civilians": [], "events": [], "time": time, "tick": frame, "presentation_reveal": true}
			start = Time.get_ticks_usec()
			world.display(state, str(units[0].id), false, 1.0 / 60.0)
			if frame >= 30:
				display_ms.append(float(Time.get_ticks_usec() - start) / 1000.0)
			if frame % 30 == 0:
				await process_frame
		display_ms.sort()
		await process_frame
		var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var primitives := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		var record := {"id": mission_id, "bounds_m": mission.bounds, "build_ms": build_ms, "display_p95_ms": display_ms[int(display_ms.size() * 0.95)], "draw_calls": draws, "primitives": primitives, "scenery_count": mission.get("scenery", []).size(), "stage_timings_usec": world.timings}
		results.append(record)
		print(JSON.stringify(record))
		world.free()
		await process_frame
	FileAccess.open(destination, FileAccess.WRITE).store_string(JSON.stringify({"missions": results, "resolution": [1600, 900], "headless": DisplayServer.get_name() == "headless"}, "\t"))
	quit()
