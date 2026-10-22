extends SceneTree
## P5 catalog identities reuse authored house data; no state/RNG injection.
const Catalog = preload("res://scripts/mission_catalog.gd")
const Equipment = preload("res://scripts/equipment_catalog.gd")
const Schema = preload("res://scripts/mission_schema.gd")
const Navigation = preload("res://scripts/navigation.gd")
const CQBSeed = preload("res://scripts/cqb_seed.gd")
const PAIR := ["M01_PRECISION", "M01_HIGH_INTENSITY"]
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	call_deferred("run")

func canonical(value: Variant) -> Variant:
	# JSON parses numbers as floats; the existing catalog normalizes actor
	# ammo counts to ints. Compare their complete serialized values exactly.
	return JSON.parse_string(JSON.stringify(value))

func run() -> void:
	var history: Array = []
	history.append_array(Catalog.HISTORICAL_IDS)
	var old_files: Array = ["T01","M01","M02","M03","M01H","M02H","M03H","M04","M05","M06","M04H","M05H","M06H","M07","M08","M09","M07H","M08H","M09H"] + history
	var old_maps: Array = history + ["M04","M05","M06","M04H","M05H","M06H","M07","M08","M09","M07H","M08H","M09H","T01","M01","M02","M03","M01H","M02H","M03H"]
	for base: String in ["M01","M02","M03"]:
		for suffix: String in ["HOSTAGE","ESCORT","INFILTRATION","TIMED","ARREST"]: old_maps.append(base+"_"+suffix)
	# P7 appends 18 standalone maps after the P5 pair. Preserve every original
	# ID and both prior pair positions, then require the exact new suffix.
	check(old_files.size() == 31 and old_maps.size() == 46, "Frozen legacy catalog prefix is complete")
	check(Catalog.FILES.keys() == old_files + PAIR + CQBSeed.IDS, "Authored lookup retains the curated 33 IDs before the exact CQB suffix")
	check(Catalog.MAPS.keys() == old_maps + PAIR + CQBSeed.IDS, "Menu and replay lookup retain the curated 48 IDs before the exact CQB suffix")
	check(Catalog.MAPS.size() == Catalog.FILES.size()+15, "Original derived-variant count remains intact")
	check(Catalog.HISTORICAL_IDS == history, "Historical identities remain unchanged")
	var parsed: Dictionary = {}
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json"))
	check(Catalog.roe(source) == "precision" and not source.has("roe"), "Legacy ROE default does not rewrite original mission data")
	var precision: Dictionary = Catalog._load_data(PAIR[0], parsed)
	var high: Dictionary = Catalog._load_data(PAIR[1], parsed)
	check(parsed.size() == 1 and parsed.house == source, "Both pair identities share one unmodified parsed house")
	for mission: Dictionary in [precision, high]:
		check(mission.schema_version == 6 and mission.variant == "normal" and not mission.challenge, "ROE authoring does not change difficulty")
		check(mission.base_id == "M01" and mission.seed == 1049 and mission.default_seed == 1049, "Same authored house and spawn seed")
		for field: String in ["revision","bounds","focus","rooms","walls","doors","props","units","enemies","environment","modifiers"]:
			check(canonical(mission[field]) == canonical(source[field]), str(mission.id)+": exact authored "+field)
		check(not mission.has("walkable_areas"), "No room-only floor mask blocks the original exterior staging")
		check(mission.title != source.title and mission.title_en.contains("Operation") and not mission.description_en.is_empty(), "ROE title and guidance have English counterparts")
		var answer: Dictionary = Schema.check(mission)
		check(bool(answer.get("ok", false)), str(mission.id)+": runtime schema/geometry "+str(answer.get("message", "")))
		check(Catalog.rules_for(mission) == Catalog.rules_for(Catalog.load("M01")), "Pair keeps original normal enemy rules")
		var nav := Navigation.new()
		nav.build(mission, mission.doors)
		for actor: Dictionary in mission.units + mission.enemies + mission.civilians:
			check(nav.walkable(Vector2(float(actor.x),float(actor.z))), str(mission.id)+": original body starts on usable floor "+str(actor.id))
	check(precision.roe == "precision" and high.roe == "high_intensity", "Pair has distinct explicit ROE")
	check(Catalog.roe(precision) == "precision" and Catalog.roe(high) == "high_intensity", "Authoritative ROE lookup preserves the explicit pair")
	check(precision.civilians == source.civilians and high.civilians.is_empty(), "Only high intensity removes the two original civilians")
	check(precision.win == [{"type":"neutralize_all"},{"type":"secure_all_civilians"}] and high.win == [{"type":"neutralize_all"}], "Pair victory rules match its declared civilian presence")
	check(precision.fail == source.fail and high.fail == source.fail, "Existing civilian-loss constraint stays explicit")
	check(precision.stars == [{"id":"no_civilian_damage","label":"비전투원 피해 0","stat":"civilian_damage","op":"eq","value":0},{"id":"capture_surrendered","label":"투항자 생포","stat":"arrests","op":"gte","value":1}], "Precision rewards actual civilian protection and a capture")
	# Existing house par time is 240 seconds; P5 does not invent a new map.
	check(high.stars == [{"id":"no_unit_damage","label":"아군 부상 0","stat":"unit_damage","op":"eq","value":0},{"id":"roe_time","label":"240초 이내 완료","stat":"time","op":"lte","value":240}], "High intensity rewards an uninjured squad and original house par time")
	var before: Dictionary = source.duplicate(true)
	precision.units[0].x = -999.0
	precision.enemies.clear()
	check(parsed.house == before and canonical(high.units) == canonical(source.units) and canonical(high.enemies) == canonical(source.enemies), "Pair callers own nested data and cannot mutate each other/source")
	check(canonical(Catalog.load(PAIR[0]).units) == canonical(source.units), "Fresh pair load cannot retain caller mutations")
	var entries: Array = Catalog.briefings()
	check(entries.size() == 63 and entries.slice(0,43).all(func(entry: Dictionary)->bool:return not PAIR.has(entry.id)), "Curated 43 briefings remain the prefix before the P5 pair and 18 CQB cards")
	check(entries[43].id == PAIR[0] and entries[44].id == PAIR[1] and entries.slice(45).map(func(entry: Dictionary)->String:return entry.id) == CQBSeed.IDS, "ROE cards retain their exact positions before the appended CQB cards")
	for entry: Dictionary in entries.slice(43,45):
		check(entry.roe in ["precision","high_intensity"] and entry.base_id == "M01" and entry.objectives_en.size() == entry.objectives.size(), "Public ROE card includes both languages without hidden actors")
		check(not entry.has("enemies") and not entry.has("civilians") and not entry.has("spawns"), "ROE briefing exposes no NPC rows")
	var tools: Dictionary = Equipment.catalog()
	check(tools.version == 1 and canonical(tools.slots) == canonical({"small":2,"large":1,"legacy_total":2}), "Equipment version and legacy slot limits remain unchanged")
	check(canonical(tools.defaults.equipment) == canonical({"stun":1}), "ROE equipment does not replace default flashbang")
	check(tools.equipment.map(func(tool: Dictionary)->String:return tool.id) == ["stun","smoke","breach","probe_c1","frag"], "Frag appends after every original tool")
	var frag: Dictionary = Equipment.definition("frag")
	var profile: Dictionary = Equipment.frag_stats()
	check(profile == {"prepare":0.6,"range":8.0,"flight_speed":12.0,"fuse":1.2,"radius":4.0,"core_radius":1.0,"damage":120.0,"wall_penetration":0.6,"armor_penetration":14.0,"sound":14.0}, "Authoritative fragmentation profile is exact and complete")
	profile.damage = -1.0
	check(Equipment.frag_stats().damage == 120.0, "Gameplay profile callers cannot mutate the shared catalog")
	check(frag.slot == "small" and frag.weight == 0.4 and frag.stars == 0 and not frag.has("model"), "One frag uses one small slot without an unlock or new asset")
	check(not frag.label.is_empty() and not frag.label_en.is_empty() and not frag.note.is_empty() and not frag.note_en.is_empty(), "Frag metadata has Korean and English copy")
	for gear: Variant in ["frag",["frag"],{"frag":1},{"frag":1,"stun":1,"breach":1},{"frag":2},{"breach":2}]:
		check(Equipment.equipment_error(gear).is_empty(), "Valid new/legacy tool shape accepted: "+str(gear))
	for gear: Variant in [{"frag":3},{"frag":1,"stun":2},{"frag":1.5},{"frag":true},{"frag":-1}]:
		check(not Equipment.equipment_error(gear).is_empty(), "Invalid quantity or three small tools rejected: "+str(gear))
	check(Equipment.resolve_loadout({"equipment":["frag","stun"]}).equipment == {"frag":1,"stun":1}, "Frag survives authoritative array normalization")
	print("BREACH_ROE_CATALOG_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
