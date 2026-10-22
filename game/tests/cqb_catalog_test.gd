extends SceneTree
## P7 appends authored identities; schema/navigation checks belong to the
## content suite, while this boundary verifies complete catalog preservation.
const Catalog = preload("res://scripts/mission_catalog.gd")
const Seed = preload("res://scripts/cqb_seed.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func canonical(value: Variant) -> Variant: return JSON.parse_string(JSON.stringify(value))

func old_files() -> Array:
	var result: Array = ["T01","M01","M02","M03","M01H","M02H","M03H","M04","M05","M06","M04H","M05H","M06H","M07","M08","M09","M07H","M08H","M09H"]
	result.append_array(Catalog.HISTORICAL_IDS)
	return result+["M01_PRECISION","M01_HIGH_INTENSITY"]

func old_maps() -> Array:
	var result: Array = []
	result.append_array(Catalog.HISTORICAL_IDS)
	result += ["M04","M05","M06","M04H","M05H","M06H","M07","M08","M09","M07H","M08H","M09H","T01","M01","M02","M03","M01H","M02H","M03H"]
	for base: String in ["M01","M02","M03"]:
		for suffix: String in ["HOSTAGE","ESCORT","INFILTRATION","TIMED","ARREST"]: result.append(base+"_"+suffix)
	return result+["M01_PRECISION","M01_HIGH_INTENSITY"]

func run() -> void:
	check(Catalog.FILES.keys()==old_files()+Seed.IDS,"Curated 33 file identities remain the exact prefix before all 18 new IDs")
	check(Catalog.MAPS.keys()==old_maps()+Seed.IDS,"Curated 48 menu identities remain the exact prefix before all 18 new IDs")
	check(Catalog.FILES.size()==51 and Catalog.MAPS.size()==66,"P7 adds exactly eighteen file/menu identities")
	check(Catalog.BASE_IDS==["M01","M02","M03","M04","M05","M06","M07","M08","M09"],"Standalone CQB cannot join the old campaign or generate old variants")
	var parsed: Dictionary = {}
	var loaded: Dictionary = {}
	for id: String in Seed.IDS:
		check(Catalog.FILES.get(id)=="cqb/"+id and Catalog.MAPS.get(id)=="cqb/"+id,"Exact uppercase authored path for "+id)
		var file: String = "res://data/cqb/%s.json"%id
		check(FileAccess.file_exists(file),"Authored CQB file exists: "+id)
		var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
		if not source is Dictionary:
			check(false,"CQB file parses as a mission dictionary: "+id)
			continue
		var mission: Dictionary = Catalog._load_data(id,parsed)
		loaded[id]=mission
		check(mission.id==id and mission.schema_version==6 and not mission.challenge,"Exact standalone identity preserves schema and ordinary difficulty")
		check(mission.seed==source.seed and mission.default_seed==source.seed,"Original authored seed owns the default zero placement candidate")
		# Runtime catalog has always normalized integer actor resources. Compare
		# all authored fields through that same JSON numeric representation.
		for field: String in source:
			check(canonical(mission.get(field))==canonical(source[field]),id+": complete authored "+field+" survives catalog normalization")
		check(not str(mission.get("title_en","")).is_empty() and not str(mission.get("description_en","")).is_empty(),"Authored CQB title and guidance include English")
		check(mission.roe in ["precision","high_intensity"],"Authored ROE reaches the full mission without variant replacement")
		var original: Dictionary = source.duplicate(true)
		mission.units[0].x=-999.0
		check(parsed["cqb/"+id]==original,"Catalog callers own nested actors and cannot edit cached authoring")
		loaded[id]=Catalog._load_data(id,parsed)
	check(parsed.size()==18,"Each new authored map is parsed exactly once through the catalog cache")
	var entries: Array = Catalog.briefings()
	var original_briefings: Array = old_maps().filter(func(id: String)->bool:return not id.ends_with("_ARREST"))
	check(entries.size()==63 and entries.slice(0,45).map(func(row: Dictionary)->String:return row.id)==original_briefings,"Curated 45 briefing IDs retain their full order")
	check(entries.slice(45).map(func(row: Dictionary)->String:return row.id)==Seed.IDS,"Every new briefing appends in the specified six/twelve order")
	for entry: Dictionary in entries.slice(45):
		var authored: Dictionary = loaded[entry.id]
		check(entry.roe==authored.roe,"Public briefing carries explicit ROE so high intensity gear stays usable")
		if authored.has("base_id"): check(entry.base_id==authored.base_id,"Authored base identity remains public without campaign remapping")
		check(entry.seed==authored.seed and entry.enemy_count==authored.enemies.size() and entry.civilian_count==authored.civilians.size(),"Public operation counts and shared seed match the authored map")
		check(not entry.has("enemies") and not entry.has("civilians") and not entry.has("spawns"),"New briefing reveals no NPC row or candidate location")
		check(canonical(entry.units)==canonical(authored.units),"Public preparation preserves only the complete own roster")
	if loaded.has("SH05_PRECISION") and loaded.has("SH05_HIGH_INTENSITY"):
		var precision: Dictionary = loaded.SH05_PRECISION
		var high: Dictionary = loaded.SH05_HIGH_INTENSITY
		for field: String in ["seed","default_seed","bounds","rooms","walls","doors","props","enemies"]:
			check(canonical(precision[field])==canonical(high[field]),"SH05 comparison preserves exact authored "+field)
		check(precision.roe=="precision" and high.roe=="high_intensity" and not precision.civilians.is_empty() and high.civilians.is_empty(),"SH05 authored civilian/ROE difference is explicit")
		for seed: int in range(30):
			var first: Dictionary = precision.duplicate(true)
			var second: Dictionary = high.duplicate(true)
			first.seed=seed
			second.seed=seed
			check(Seed.materialize(first).enemies==Seed.materialize(second).enemies,"SH05 keeps actual candidate positions identical for shared seed %d"%seed)
	print("BREACH_CQB_CATALOG_RESULT checks=%d failures=%d"%[checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
