extends SceneTree
## P7 precision ROE metadata inherits metre geometry. Runtime room-control
## state stays outside authored JSON; original hash expectations predate P7.
const Catalog = preload("res://scripts/mission_catalog.gd")
const Schema = preload("res://scripts/mission_schema.gd")
const Simulation = preload("res://scripts/simulation.gd")
const STEP := 1.0 / 30.0
# Active maps use approved compact-layout baselines (2026-10-14).
const ORIGINAL_SHA256 := {
    "game/data/archive.json": "d64a1ae17d9aeeca4023b73f6a7622144b14ae93b5fcd70726ffe1db2115e616",
    "game/data/archive_challenge.json": "3542af72b8847bb0fb370e8764820bdbaef932064e20a29270e9d8e58215dd6f",
    "game/data/courtyard.json": "77a7e28b94a5746deccbfb8180e3e16e1b33401f2f3ca40d91d0e71ef2348648",
    "game/data/depot.json": "b150f80194235d6ae6ea7540562c8748754a57be08abf6e18b2fe9d9106dc261",
    "game/data/depot_challenge.json": "0f6c92ce0ea20fd6b0c4b4778177da996db260f6bd6ff5eaaba7a282c8311255",
    "game/data/garage.json": "6591412faff11f3b238a3b5f3168d7c65b89642332e6b23902ae54cb380aeeac",
    "game/data/historical/H01.json": "90cb5378fa472fc7aed14ad5c7f530d5b7915a3a7e328fa73066d4209f5ef00d",
    "game/data/historical/H02.json": "7ecc7bb4aa7efbe911a217f2f4a8e89ac5c27a8737add08f1e665f5f847efc55",
    "game/data/historical/H03.json": "2fbcf9d156ad112115321d5e7d09c82f62ef7d3b7f1a93b31868a87854da6e2c",
    "game/data/historical/H04.json": "1837a58eb2bdcaf09b9c40f9ba89322fcc01eb596795645aa87a6a23c81362c6",
    "game/data/historical/H06.json": "10e4f929707e658fcf6eadf9db742e7e551688de19c153f4d725c8cfaf95faeb",
    "game/data/historical/H07.json": "93288cd5dd7fb44b9704407580c86d305c0e3313dd352bf0edd47e5f2834e697",
    "game/data/historical/H09.json": "3c9cd59c0181da919f2541868804f29dccfd4f0a1e5374b5cb88eb7354b608d9",
    "game/data/historical/H11.json": "84b195c733a50da8b595995dd1cdbce0993910767c4a48fa864b6736cbe4bf48",
    "game/data/historical/H16.json": "9f7d05448012f3b34960416d6d0231b79538b45b3a5c0e91673700330fca75f0",
    "game/data/historical/H26.json": "949dfd9a3a6be7572f7615c360acd88f6a1bb37784333c840ed39495613934c5",
    "game/data/historical/H29.json": "16dc85dbec8e1cba7fd78f13b5e0c93882868606d15d9f3f06cf8bb06a8f1e12",
    "game/data/historical/H36.json": "653f8e81d63fe17e38edccb79c93e34226bc6c02554e928f3d8dc46ad17ab98d",
    "game/data/house.json": "fc8bfa5e90479812cc5709d3a135d105409446669ab3df5e61f2d7e78df0fe5d",
    "game/data/house_challenge.json": "7b81a658c943d41123d8cf0e2a6489265caab885c7b941b6444e0edafaf090dc",
    "game/data/motel.json": "5055958db82d4ee9558aa5f763fca0f7eac18531aa59c89934a2779c64d9bf9b",
    "game/data/offices.json": "79cec900eca0fcee4794400badc78fecb4d8b5c1624fdd8dd9819aec4899c3d7",
    "game/data/shops.json": "bbd46017b8e931dab596cc11db9ec28defb22a40260ab780a36142d8f26be0ad",
    "game/data/terminal.json": "3133d32375cad70d7534d655c040161c1509deba0f306e5b0d7584a67db4a7ae",
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
	for path: String in ORIGINAL_SHA256:
		var text: String = FileAccess.get_file_as_string("res://" + path.trim_prefix("game/"))
		check(not text.is_empty(), path+": original authored JSON exists")
		var historical: bool = path.contains("/historical/")
		var restored: String = text.replace('  "schema_version": 6,\n', '  "schema_version": 2,\n').replace('  "roe": "precision",\n', '') if historical else text
		check(restored.sha256_text() == ORIGINAL_SHA256[path], path+": all original bytes outside the two metadata lines remain exact")
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
