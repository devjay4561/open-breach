extends SceneTree
## Precision ROE metadata inherits metre geometry. Runtime room-control
## state stays outside authored JSON; preserve the reviewed public authoring.
const Catalog = preload("res://scripts/mission_catalog.gd")
const Schema = preload("res://scripts/mission_schema.gd")
const Simulation = preload("res://scripts/simulation.gd")
const STEP := 1.0 / 30.0
# Baseline: public release aa1fabf, with fictional dossiers and current combat data.
const RELEASE_SHA256 := {
    "game/data/archive.json": "f0ba6dd35afe48c4805d18cb8e3bd76734dd3e4993facecdc769039b9fefe9dc",
    "game/data/archive_challenge.json": "c008104b66ff20367053ac37b8b934e82cb878b5d81f759c444adbd268acbef2",
    "game/data/courtyard.json": "cd6496da9a74aeae10bb9a4e5d51c73496f259c14793edbcdc32cba431e7d601",
    "game/data/depot.json": "f0326e8a29f00664cd1a118ae21f0588bbff815adf812fd3b045583e3f11460a",
    "game/data/depot_challenge.json": "38de0f85263f92c3000ffa5645b194a18c824aedb09fe7dc759e519a563d2ec7",
    "game/data/garage.json": "0fa276fec28fbea71b192a3dbfdb69a437c917dcb72092a690ea74146b40293d",
    "game/data/historical/H01.json": "99d63756718f5bbb781458c2720cb30f371ea7585fa2d9ece14eb7f3fb48475e",
    "game/data/historical/H02.json": "66e6df997789d1cb699c357fd88915913cf2e7cc99a8f4fb497da3683827cee3",
    "game/data/historical/H03.json": "e2a373323f924d8e2e04b196981324d22d296afbceb9b202210902e108001b0f",
    "game/data/historical/H04.json": "372a5a2e336fe33f692722b40d4bcc99287608d31fdeef4b1b2c08396f7c54a3",
    "game/data/historical/H06.json": "a087fa5cbf4cf215c7258e4c3ed88c1108f79602cda5efda255fdf5827f5b469",
    "game/data/historical/H07.json": "e270d2043c05f580affa040fc7d12f8eb74ca090bb7290a8f8c02942f11f87f9",
    "game/data/historical/H09.json": "07b6c4682e968e605fa4e1a9516f14fd2e032d9d2273ac2bf4d6966be2826b21",
    "game/data/historical/H11.json": "57bb3f9de02c45d981feb65dc94511e6fb1ff11ac7391351aded13cb1bd140f9",
    "game/data/historical/H16.json": "0829690929a2d9b8938a202a92d616a9da01fd0edf45322324e6290d4d859b2d",
    "game/data/historical/H26.json": "32f3fadc72bc28e0a38402d96b94221d55852ac6d239a63e620e20ab75930745",
    "game/data/historical/H29.json": "df2d3818de17946e5239b36866297ffe210eb543cdf2d9fefc53cc7482ecfa1e",
    "game/data/historical/H36.json": "1926562ce4b06a7ea751b6ab2aa8efcd355a18380e2720df94557428d3dbcc11",
    "game/data/house.json": "d7e87311a5bcb14db104524452adf8b9a975bcc6d6247283f75d35d881937a91",
    "game/data/house_challenge.json": "0f5afa6e601990fcb308b94d00dffc4be80c2e5447a08b447e0cd46ac66b5ca6",
    "game/data/motel.json": "0d8f95141dfae1114f7586e7a2fc4aaa1dbd36a393c4ccb10a01cc45a5b3133c",
    "game/data/offices.json": "13f661f4e3157df1e5207c87117b386b82038156656c6ea039f35fd105c188e4",
    "game/data/shops.json": "b6203b86a45776c67d2df4c0ebb5958a8b8efc2327ecf630c85684d64d6896ff",
    "game/data/terminal.json": "d2d95569935d74117c074c545334efbd57d5e9f275489062e39ea136e36d610e",
    "game/data/tutorial.json": "0f81acef660bb24e54900d4868f974d7a0237a52594890b9b3dd51d736b2d163"
}
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	check(Catalog.HISTORICAL_IDS.size() == 12, "Curated historical identities stay catalogued")
	for path: String in RELEASE_SHA256:
		var text: String = FileAccess.get_file_as_string("res://" + path.trim_prefix("game/"))
		check(not text.is_empty(), path+": original authored JSON exists")
		var historical: bool = path.contains("/historical/")
		check(text.sha256_text() == RELEASE_SHA256[path], path+": reviewed public mission bytes remain exact")
		var document: Dictionary = JSON.parse_string(text)
		if historical:
			check(document.schema_version == 6 and document.roe == "precision", path+": historical mission opts into precision schema6")
			check(not document.has("room_states") and not document.has("room_states_observed") and not document.has("room_doctrine"), path+": room state is supplied by the runtime FSM")
			var validated := Schema.check(document)
			check(validated.get("ok",false), path+": schema6 inherits historical physical geometry: "+str(validated.get("message","")))
			var mission := Catalog.load(document.id)
			# Catalog intentionally canonicalizes fictional dossier text to an int;
			# raw JSON numbers are floats. Compare all provenance after the same
			# JSON boundary, without dropping any original field or value.
			check(mission.get("roe") == "precision" and mission.get("schema_version") == 6 and JSON.parse_string(JSON.stringify(mission.historical)) == document.historical, path+": catalog retains metadata and complete provenance")
		else:
			check(document.schema_version == 1 and not document.has("roe"), path+": original fictional authoring remains unchanged")
	# One fixed STEP on representative ship, raised cabin and open terrain.
	# No scripted victory, rendering, path traversal, sleeps or fake casualty.
	for id: String in ["H01", "H04", "H36"]: _runtime_smoke(id)
	print("BREACH_HISTORICAL_DOCTRINE_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _runtime_smoke(id: String) -> void:
	var mission := Catalog.load(id)
	var sim := Simulation.new()
	sim.load_mission(mission)
	var initial := sim.snapshot(true)
	check(initial.get("roe") == "precision" and initial.room_states.size() == mission.rooms.size(), id+": precision metadata initializes existing RoomControl for authored rooms")
	for row: Dictionary in initial.room_states.values():
		check(row.state == "UNKNOWN" and row.changed_tick == 0 and row.changed_at == 0 and not row.observed, id+": authored room starts UNKNOWN without hidden clearance")
	var repeat := Simulation.new()
	repeat.load_mission(mission)
	check(JSON.stringify(initial) == JSON.stringify(repeat.snapshot(true)), id+": initial metadata load is deterministic")
	sim.step(STEP)
	repeat.step(STEP)
	check(sim.tick == 1 and sim.time == STEP and JSON.stringify(sim.snapshot(true)) == JSON.stringify(repeat.snapshot(true)), id+": one fixed authoritative STEP repeats exactly")
	var observed := sim.snapshot(false)
	var known_enemy_ids: Array = observed.enemies.filter(func(enemy: Dictionary) -> bool: return bool(enemy.get("visible",false))).map(func(enemy: Dictionary) -> String: return str(enemy.id))
	for enemy: Dictionary in sim.enemies:
		if not bool(enemy.visible): check(not known_enemy_ids.has(enemy.id), id+": hidden enemy remains outside current observed actors")
	check(not observed.has("room_states_observed") and observed.room_states == sim.snapshot(true).room_states_observed, id+": public room state is independent observed memory")
