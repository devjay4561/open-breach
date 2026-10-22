extends SceneTree
## Public catalog, metre dimensions, real door apertures and ordered objective
## replay coverage. Unknown historic interiors remain identified as reconstruction.
const Catalog = preload("res://scripts/mission_catalog.gd")
const Schema = preload("res://scripts/mission_schema.gd")
const Historical = preload("res://scripts/historical_assets.gd")
const Simulation = preload("res://scripts/simulation.gd")
const Replay = preload("res://scripts/replay.gd")
const STEP := 1.0 / 30.0
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var seen: Dictionary = {}
	var briefs: Dictionary = {}
	for briefing: Dictionary in Catalog.briefings(): briefs[str(briefing.id)] = briefing
	check(Catalog.HISTORICAL_IDS.size() == 12, "Catalog contains the curated 12 historic operations")
	for id: String in Catalog.HISTORICAL_IDS:
		check(Catalog.HISTORICAL_IDS.has(id) and Catalog.MAPS.has(id) and Catalog.FILES.has(id), id+": public menu and replay catalog registration")
		var mission := Catalog.load(id)
		check(not mission.is_empty() and str(mission.get("id", "")) == id, id+": loads its own authored identity")
		if mission.is_empty(): continue
		check(not seen.has(mission.id), id+": unique operation identity")
		seen[mission.id] = true
		# P7 adds only precision ROE metadata, which requires mission schema6.
		# Metre geometry and the independent legacy-v2 replay fixture stay intact.
		check(int(mission.schema_version) == 6 and maxf(float(mission.bounds[0]),float(mission.bounds[1])) > 32, id+": uses a large physical battlefield, not a scaled legacy room")
		var history: Dictionary = mission.get("historical", {})
		for key: String in ["location", "location_en", "accuracy_note", "accuracy_note_en"]:
			check(history.has(key), id+": historical provenance field "+key)
		check(not history.has("year") and not history.has("source_urls"), id+": fictional dossiers omit real event dates and citations")
		check(not str(history.get("accuracy_note", "")).is_empty(), id+": reconstruction limits are disclosed")
		check(briefs.has(id) and briefs[id].historical == history, id+": briefing preserves source context")
		var validated := Schema.check(mission)
		check(bool(validated.ok), id+": authored movement geometry and objectives validate: "+str(validated.get("message", "")))
		for door: Dictionary in mission.doors:
			var aperture := float(door.w) if str(door.axis)=="x" else float(door.d)
			var thickness := float(door.d) if str(door.axis)=="x" else float(door.w)
			check(aperture >= .8, id+": door admits an actual human width: "+str(door.id))
			check(thickness >= .04 and thickness <= .35, id+": door thickness remains in metres: "+str(door.id))
		for prop: Dictionary in mission.get("scenery", []):
			check(Historical.registry().has(str(prop.asset)), id+": scenery resolves to a real model "+str(prop.asset))
			var entry: Dictionary = Historical.registry().get(str(prop.asset),{})
			if not entry.get("verified_dimensions_m",{}).is_empty():
				check(is_equal_approx(float(prop.get("scale",1)),1.0), id+": verified historic object retains its actual metre dimensions: "+str(prop.asset))
	check(seen.size()==12 and seen.has("H36"), "Twelve distinct operations include RED VERANDA rather than repeating earlier maps")
	check(Catalog.load("H01").title_en == "SALT MERIDIAN", "First special operation has its fictional identity")
	# Existing authored tactical missions retain the explicit v1 limits. These
	# invariants continue to cover the old content when the catalog grows.
	for id: String in ["T01"] + Catalog.BASE_IDS + Catalog.CHALLENGE_IDS:
		var legacy := Catalog.load(id)
		check(int(legacy.schema_version)==1 and float(legacy.bounds[0])<=32 and float(legacy.bounds[1])<=32, id+": legacy authoring remains version1 and 32m")
	_test_dimensions()
	_test_lighting_modifiers()
	_test_ordered_objective_replay()
	_test_map_revision_replay()
	print("BREACH_HISTORICAL_CATALOG_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_dimensions() -> void:
	var registry := Historical.registry()
	var expected: Dictionary = {
		"tanker_ship_hull":[145.5,23.7],
		"airliner_twinjet":[30.53,28.35],
		"airliner_reartwin":[36.4,28.4],
		"airliner_quadjet":[46.61,43.4],}
	for id: String in expected:
		check(registry.has(id), id+": registered verified outer dimensions")
		if not registry.has(id): continue
		var dimensions: Array = registry[id].dimensions_m
		check(is_equal_approx(float(dimensions[0]),float(expected[id][0])) and is_equal_approx(float(dimensions[2]),float(expected[id][1])), id+": metre length / beam or wingspan")
		check(registry[id].forward=="+X" and registry[id].up=="+Y", id+": common placement axes")
	var tanker := Catalog.load("H01")
	var deck_found := false
	for room: Dictionary in tanker.rooms:
		if is_equal_approx(float(room.w),145.5) and is_equal_approx(float(room.d),23.7): deck_found=true
	check(deck_found, "Salt Meridian map preserves the tanker footprint instead of fitting the whole ship into 32 metres")
	check(float(tanker.environment.water_level) < 0, "Salt Meridian water sits below the physical playable deck")
	check(not tanker.get("walkable_areas",[]).is_empty(), "Salt Meridian navigation explicitly restricts movement to deck surfaces")
	for operation: String in ["H04", "H06", "H07"]:
		var mission := Catalog.load(operation)
		var aircraft: Dictionary = {}
		for scenery: Dictionary in mission.get("scenery", []):
			if str(scenery.asset) in ["airliner_twinjet", "airliner_reartwin", "airliner_quadjet"]:
				aircraft = scenery
		check(not aircraft.is_empty(), operation+": playable aircraft has a measured cabin model")
		if aircraft.is_empty(): continue
		var entry: Dictionary = registry[str(aircraft.asset)]
		check(entry.get("cutaway_hide_meshes", []).has("CabinSeats_Cutaway"), operation+": model seats are hidden where playable seat props occupy the cabin")
		var model_floor := float(entry.cabin_floor_y_m) + float(entry.floor_offset) + float(aircraft.get("height", 0.0))
		var cabin_rooms := 0
		for room: Dictionary in mission.rooms:
			if float(room.get("base_height", 0.0)) <= 0.0: continue
			cabin_rooms += 1
			check(is_equal_approx(float(room.base_height) + 0.2, model_floor), operation+": actor and playable room floor meet the original GLB cabin surface: "+str(room.id))
		check(cabin_rooms > 0, operation+": playable cabin is raised above the landing gear and apron")

func _test_lighting_modifiers() -> void:
	for modifier: String in ["night", "dim"]:
		var expected_light := 0.25 if modifier == "night" else 0.55
		var ship := Catalog.load("H01")
		var original_environment: Dictionary = ship.environment.duplicate(true)
		ship["modifiers"] = [modifier]
		var configured := Catalog.apply_modifiers(ship)
		check(bool(configured.environment.water), modifier+": Salt Meridian retains the ocean")
		check(configured.environment.ground_surface == "ship_deck", modifier+": Salt Meridian retains the physical deck surface")
		check(is_equal_approx(float(configured.environment.water_level),float(original_environment.water_level)), modifier+": the water does not rise to the operator's feet")
		check(configured.environment.biome == original_environment.biome, modifier+": the maritime environment remains intact")
		check(configured.environment.time_of_day == modifier and is_equal_approx(float(configured.environment.lighting), expected_light), modifier+": requested lighting is applied")
		check(ship.environment == original_environment, modifier+": configuring lighting leaves the source mission intact")
		var legacy := Catalog.load("M01")
		legacy["modifiers"] = [modifier]
		var legacy_configured := Catalog.apply_modifiers(legacy)
		check(legacy_configured.environment.time_of_day == modifier and is_equal_approx(float(legacy_configured.environment.lighting), expected_light), modifier+": legacy version1 brightness remains the same")

func _ordered_fixture() -> Dictionary:
	return {"schema_version":2,"id":"HISTORICAL_ORDER_QA","revision":1,"custom":true,"title":"Ordered historical objective replay","seed":17,
		"bounds":[128,80],"focus":[64,40],"rooms":[{"id":"ground","x":64,"z":40,"w":128,"d":80}],
		"walls":[],"doors":[],"props":[],"units":[{"id":"alpha","name":"Alpha","role":"Assault","weapon":"standard","x":4,"z":40,"facing":0}],"enemies":[],"civilians":[],
		"interactive_targets":[{"id":"records","x":112,"z":40,"w":2,"d":2,"label":"Recover records","action":"recover","duration":1.2},
			{"id":"extraction","x":4,"z":40,"w":2,"d":2,"label":"Return to extraction","action":"board","duration":1.0}],
		"win":[{"type":"targets_complete","targets":["records","extraction"]}],"fail":[],"objectives":["Recover the distant records then return"]}

func _test_ordered_objective_replay() -> void:
	var fixture := _ordered_fixture()
	check(bool(Schema.check(fixture).ok), "Ordered stage fixture validates without direct state mutation")
	var sim := Simulation.new()
	sim.load_mission(fixture)
	var recording := Replay.new()
	recording.begin(fixture)
	recording.capture(sim.snapshot(true))
	for tick in range(60): sim.step(STEP)
	check(float(sim.interactive_targets[1].progress)==0 and not bool(sim.interactive_targets[1].completed), "Extraction at the insertion point cannot complete before the distant first stage")
	check(bool(sim.issue("alpha","MOVE",{"target":[112,40]},true).ok), "Ordinary movement orders reach the distant objective")
	for tick in range(4500):
		sim.step(STEP)
		recording.capture(sim.snapshot(true))
		if float(sim.interactive_targets[0].progress) >= .4: break
	var partial := sim.snapshot(true)
	var progress := float(partial.interactive_targets[0].progress)
	check(progress>0 and progress<1.2 and not bool(partial.interactive_targets[0].completed), "A partial objective is earned only after the operator reaches it")
	check(float(partial.interactive_targets[1].progress)==0, "Later extraction stage remains pending during partial recovery")
	recording.finish(partial)
	var restored := Replay.new()
	var loaded := restored.load_data(JSON.parse_string(JSON.stringify(recording.export_data())))
	check(bool(loaded.ok), "Partially completed ordered objectives survive replay JSON export/import: "+str(loaded.get("message","")))
	if loaded.ok:
		var ending := restored.seek(restored.duration,true)
		check(ending.interactive_targets == JSON.parse_string(JSON.stringify(partial.interactive_targets)), "Replay preserves partial seconds, order and the untouched extraction stage")
	for tick in range(90): sim.step(STEP)
	check(bool(sim.interactive_targets[0].completed) and float(sim.interactive_targets[1].progress)==0 and sim.result.is_empty(), "Finishing recovery alone cannot remotely finish extraction")
	check(bool(sim.issue("alpha","MOVE",{"target":[4,40]},true).ok), "Return uses the public movement command")
	for tick in range(4500):
		sim.step(STEP)
		if not sim.result.is_empty(): break
	check(bool(sim.result.get("success",false)), "Returning and remaining in the extraction zone completes the ordered operation")
	var events: Array = sim.snapshot(true).events.filter(func(event: Dictionary) -> bool: return event.type=="TARGET_COMPLETE")
	check(events.size()==2 and events[0].target_id=="records" and events[1].target_id=="extraction", "Replayable target events follow recovery then extraction exactly once")

func _test_map_revision_replay() -> void:
	var mission := Catalog.load("H02")
	var sim := Simulation.new()
	sim.load_mission(mission)
	var recording := Replay.new()
	recording.begin(mission)
	recording.capture(sim.snapshot(true))
	sim.step(STEP)
	recording.finish(sim.snapshot(true))
	var current: Dictionary = JSON.parse_string(JSON.stringify(recording.export_data()))
	check(bool(Replay.new().load_data(current).ok), "Compact terminal replay uses its current authored revision")
	current.map_revision = 1
	check(not bool(Replay.new().load_data(current).ok), "Old terminal coordinates cannot silently play against the compact floor plan")
