extends RefCounted
const MissionSchema = preload("res://scripts/mission_schema.gd")
const CQBSeed = preload("res://scripts/cqb_seed.gd")
## Every operation reuses an authored floor plan and its validated spawn choices.
## FILES stays compatible with schema version 1 callers; MAPS is the menu catalog.
const FILES: Dictionary = {"T01":"tutorial", "M01":"house", "M02":"archive", "M03":"depot", "M01H":"house_challenge", "M02H":"archive_challenge", "M03H":"depot_challenge", "M04":"motel", "M05":"offices", "M06":"terminal", "M04H":"motel", "M05H":"offices", "M06H":"terminal", "M07":"garage", "M08":"shops", "M09":"courtyard", "M07H":"garage", "M08H":"shops", "M09H":"courtyard", "H01":"historical/H01", "H02":"historical/H02", "H03":"historical/H03", "H04":"historical/H04", "H06":"historical/H06", "H07":"historical/H07", "H09":"historical/H09", "H11":"historical/H11", "H16":"historical/H16", "H26":"historical/H26", "H29":"historical/H29", "H36":"historical/H36", "M01_PRECISION":"house", "M01_HIGH_INTENSITY":"house", "SH01":"cqb/SH01", "SH02":"cqb/SH02", "SH03":"cqb/SH03", "SH04":"cqb/SH04", "SH05_PRECISION":"cqb/SH05_PRECISION", "SH05_HIGH_INTENSITY":"cqb/SH05_HIGH_INTENSITY", "CQB01":"cqb/CQB01", "CQB02":"cqb/CQB02", "CQB03":"cqb/CQB03", "CQB04":"cqb/CQB04", "CQB05":"cqb/CQB05", "CQB06":"cqb/CQB06", "CQB07":"cqb/CQB07", "CQB08":"cqb/CQB08", "CQB09":"cqb/CQB09", "CQB10":"cqb/CQB10", "CQB11":"cqb/CQB11", "CQB12":"cqb/CQB12"}
const BASE_IDS: Array[String] = ["M01", "M02", "M03", "M04", "M05", "M06", "M07", "M08", "M09"]
const HISTORICAL_IDS: Array[String] = ["H01", "H02", "H03", "H04", "H06", "H07", "H09", "H11", "H16", "H26", "H29", "H36"]
const MAPS: Dictionary = {
	"H01":"historical/H01", "H02":"historical/H02", "H03":"historical/H03", "H04":"historical/H04", "H06":"historical/H06", "H07":"historical/H07", "H09":"historical/H09", "H11":"historical/H11", "H16":"historical/H16", "H26":"historical/H26", "H29":"historical/H29", "H36":"historical/H36",
	"M04":"motel", "M05":"offices", "M06":"terminal", "M04H":"motel", "M05H":"offices", "M06H":"terminal", "M07":"garage", "M08":"shops", "M09":"courtyard", "M07H":"garage", "M08H":"shops", "M09H":"courtyard",
	"T01":"tutorial", "M01":"house", "M02":"archive", "M03":"depot", "M01H":"house_challenge", "M02H":"archive_challenge", "M03H":"depot_challenge",
	"M01_HOSTAGE":"house", "M01_ESCORT":"house", "M01_INFILTRATION":"house", "M01_TIMED":"house", "M01_ARREST":"house",
	"M02_HOSTAGE":"archive", "M02_ESCORT":"archive", "M02_INFILTRATION":"archive", "M02_TIMED":"archive", "M02_ARREST":"archive",
	"M03_HOSTAGE":"depot", "M03_ESCORT":"depot", "M03_INFILTRATION":"depot", "M03_TIMED":"depot", "M03_ARREST":"depot",
	"M01_PRECISION":"house", "M01_HIGH_INTENSITY":"house",
	"SH01":"cqb/SH01", "SH02":"cqb/SH02", "SH03":"cqb/SH03", "SH04":"cqb/SH04", "SH05_PRECISION":"cqb/SH05_PRECISION", "SH05_HIGH_INTENSITY":"cqb/SH05_HIGH_INTENSITY",
	"CQB01":"cqb/CQB01", "CQB02":"cqb/CQB02", "CQB03":"cqb/CQB03", "CQB04":"cqb/CQB04", "CQB05":"cqb/CQB05", "CQB06":"cqb/CQB06",
	"CQB07":"cqb/CQB07", "CQB08":"cqb/CQB08", "CQB09":"cqb/CQB09", "CQB10":"cqb/CQB10", "CQB11":"cqb/CQB11", "CQB12":"cqb/CQB12",
}
const ROE_IDS: Dictionary = {"M01_PRECISION":"precision", "M01_HIGH_INTENSITY":"high_intensity"}
const ROE_OBJECTIVES_EN: Dictionary = {
	"precision":["Neutralize every hostile and secure both civilians.", "Flashbangs are allowed; fragmentation grenades are prohibited. Protect civilians and capture surrendered hostiles."],
	"high_intensity":["Neutralize every hostile. No civilians are present in this operation.", "Fragmentation grenades are allowed; fragments can penetrate plaster walls and injure operators in adjacent rooms."],
}
const CHALLENGE_IDS: Array[String] = ["M01H", "M02H", "M03H", "M04H", "M05H", "M06H", "M07H", "M08H", "M09H"]
const NORMAL: Dictionary = {"reaction_min":0.22,"reaction_max":0.38,"interval":0.85,"accuracy":0.66,"damage":18.0,"patrol_speed":1.0}
## Independent of behavior (sentry/rusher/etc.). Missing strength keeps legacy weak stats.
const ENEMY_STRENGTHS: Dictionary = {
	"weak": {"damage":18.0,"interval":0.85,"accuracy":0.66,"reaction_min":0.22,"reaction_max":0.38},
	"medium": {"damage":30.0,"interval":0.60,"accuracy":0.78,"reaction_min":0.16,"reaction_max":0.26},
	"strong": {"damage":44.0,"interval":0.45,"accuracy":0.90,"reaction_min":0.10,"reaction_max":0.18},
}
const CHALLENGE: Dictionary = {"reaction_min":0.16,"reaction_max":0.26,"interval":0.65,"accuracy":0.76,"damage":24.0,"patrol_speed":1.15}
const MODIFIERS: Dictionary = {
	"night":{"label":"야간"},
	"dim":{"label":"낮은 조도"},
	"low_ammo":{"label":"탄약 절반","ammo_scale":0.5},
	"fast_reaction":{"label":"빠른 반응","reaction_min":0.16,"reaction_max":0.26},
	"no_stun":{"label":"스턴 금지","stuns":0},
}
const COVER_DEFAULTS: Dictionary = {"table":"low","desk":"low","sofa":"low","bed":"low","cabinet":"full","bookshelf":"full","plant":"none","chair":"none","crate":"low","rug":"none","vehicle":"full","pillar":"full"}
const TYPE_LABELS: Dictionary = {"normal":"위협 처리","challenge":"도전","hostage":"인질 구출","escort":"호송","infiltration":"잠입","timed":"시간 제한","arrest":"체포 작전"}
## RD (plan 2-5 영어 문자열 분리): English counterparts for the generated
## variant titles/objectives below, exposed as title_en/description_en in
## missions()/briefings() alongside the Korean source. Base mission
## title_en/description_en come from game/data/*.json itself (optional
## schema fields); only the variant suffix/objectives generated here need an
## English table of their own.
const TYPE_LABELS_EN: Dictionary = {"normal":"Threat Clearance","challenge":"Challenge","hostage":"Hostage Rescue","escort":"Escort","infiltration":"Infiltration","timed":"Time Limit","arrest":"Arrest Operation"}
const OBJECTIVES_EN: Dictionary = {
	"hostage": ["Secure the hostage before the captor attacks the civilian.", "Every civilian must survive."],
	"escort": ["Secure the civilian, then move them with an escort order.", "Bring every civilian to the extraction zone outside the entrance."],
	"infiltration": ["Reach the marked zone without putting the enemy on alert.", "Completes once any operator enters the zone."],
	"timed": ["Reach the marked zone within 25 seconds.", "Plan your route and door handling together."],
	"arrest": ["Arrest every surrendered threat to clear the mission.", "Star objective: finish without killing any enemy."],
}
const GOAL_ZONES: Dictionary = {"M01":[12.0,15.4,1.2,1.2], "M02":[6.0,12.5,1.2,1.2], "M03":[12.0,14.5,1.2,1.2]}
const TIMED_ZONES: Dictionary = {"M01":[19.8,4.7,1.2,1.2],"M02":[19.0,4.5,1.2,1.2],"M03":[19.5,4.5,1.2,1.2]}
const EXTRACTION_ZONES: Dictionary = {"M01":[12.0,18.5,3.5,1.8],"M02":[6.0,17.8,3.5,1.8],"M03":[12.0,18.5,3.5,1.8]}
const HOSTAGES: Dictionary = {
	"M01":{"e5":[[7.55,5.5],[7.55,6.2]],"e6":[[19.8,5.65],[19.8,6.35]]},
	"M02":{"a_e3":[[19.0,5.5],[18.8,5.8]]},
	"M03":{"b_e4":[[19.5,4.5],[18.8,4.6]]},
}

static func cover_default(kind: String) -> String:
	return str(COVER_DEFAULTS.get(kind, "none"))

static func roe(data: Dictionary) -> String:
	# Legacy missions keep precision without changing their authored shape.
	return "high_intensity" if data.get("roe", "precision") == "high_intensity" else "precision"

## The authoring name is preserved from the doctrine plan, but this value is
## a success probability: 0 never opens, 1 always opens on a completed kick.
static func kick_success_probability(door: Dictionary, rooms: Array = []) -> float:
	if door.has("kick_resistance"):
		return clampf(float(door.kick_resistance),0.0,1.0)
	if bool(door.get("locked",false)) or bool(door.get("reinforced",false)): return 0.25
	var x: float = float(door.get("x",0.0))
	var z: float = float(door.get("z",0.0))
	var axis_x: bool = str(door.get("axis","x")) == "x"
	var offset: float = maxf(0.25,float(door.get("d" if axis_x else "w",0.24))*0.5+0.05)
	var front_indoor: bool = _indoor_at(rooms,x if axis_x else x-offset,z-offset if axis_x else z)
	var back_indoor: bool = _indoor_at(rooms,x if axis_x else x+offset,z+offset if axis_x else z)
	return 0.8 if front_indoor and back_indoor else 0.5

static func _indoor_at(rooms: Array, x: float, z: float) -> bool:
	for room: Dictionary in rooms:
		if not bool(room.get("indoor",true)): continue
		if absf(x-float(room.x)) <= float(room.w)*0.5 and absf(z-float(room.z)) <= float(room.d)*0.5: return true
	return false

static func _load_data(id: String, parsed: Dictionary) -> Dictionary:
	if not MAPS.has(id): return {}
	var path: String = str(MAPS[id])
	var value: Variant = parsed.get(path)
	if not parsed.has(path):
		value = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % path))
		parsed[path] = value
	if not value is Dictionary: return {}
	var data: Dictionary = value.duplicate(true)
	for key: String in ["schema_version","revision","seed"]: data[key] = int(data[key])
	for group: String in ["units","enemies"]:
		for actor: Dictionary in data[group]:
			for key: String in ["ammo","reserve_ammo","stuns","smokes","breaches"]:
				if actor.has(key): actor[key] = int(actor[key])
	data["id"] = id
	data["default_seed"] = int(data.get("seed", 42))
	data["challenge"] = CHALLENGE_IDS.has(id)
	data["variant"] = "challenge" if data.challenge else str(data.get("variant", "normal"))
	if data.challenge and id.substr(0,3) in ["M04", "M05", "M06", "M07", "M08", "M09"]:
		data["title"] += " · 도전"
		data["title_en"] += " · Challenge"
	data["modifiers"] = data.get("modifiers", []).duplicate()
	if ROE_IDS.has(id): _configure_roe_pair(data, id)
	if not FILES.has(id):
		var base: String = id.substr(0,3)
		var variant: String = id.substr(4).to_lower()
		data["id"] = id
		data["base_id"] = base
		data["variant"] = variant
		data["title"] = str(data.title) + " · " + str(TYPE_LABELS[variant])
		data["title_en"] = str(data.get("title_en", data.title)) + " · " + str(TYPE_LABELS_EN[variant])
		data["subtitle"] = str(TYPE_LABELS[variant])
		data["fail"] = [{"type":"no_civilian_loss"}]
		match variant:
			"hostage":
				data["win"] = [{"type":"secure_all_civilians"}]
				data["objectives"] = ["인질범이 민간인을 공격하기 전에 확보하세요.", "모든 민간인이 살아 있어야 합니다."]
				for enemy: Dictionary in data.enemies:
					if not HOSTAGES[base].has(enemy.id): continue
					var positions: Array = HOSTAGES[base][enemy.id]
					enemy["enemy_type"] = "hostage_taker"
					enemy["x"] = positions[0][0]
					enemy["z"] = positions[0][1]
					enemy["patrol"] = []
					enemy["spawns"] = []
					for position: Array in positions:
						enemy.spawns.append({"x":position[0],"z":position[1],"facing":enemy.get("facing",0.0),"patrol":[]})
			"escort":
				data["win"] = [{"type":"escort_to_zone","zone":EXTRACTION_ZONES[base].duplicate()}]
				data["objectives"] = ["민간인을 확보한 뒤 호송 명령으로 합류시키세요.", "모든 민간인을 입구 바깥 추출 구역으로 데려오세요."]
				data.enemies[0]["enemy_type"] = "rusher"
			"infiltration":
				data["win"] = [{"type":"reach_zone","zone":GOAL_ZONES[base].duplicate()},{"type":"before_alert"}]
				data["fail"].append({"type":"before_alert"})
				data["objectives"] = ["적을 경계 상태로 만들지 않고 지정 구역에 도달하세요.", "한 명 이상의 대원이 지정 구역에 들어가면 완료됩니다."]
				if base == "M03":
					# The clearance staging is directly visible to the loading guard.
					# Stealth starts outside that sightline rather than failing while idle.
					for index: int in range(data.units.size()):
						data.units[index].x = 19.0 + float(index)*1.3
						data.units[index].z = 18.8
					data.objectives.append("남동쪽 집결 지점에서 시작합니다. 진입 전에 연막 장비와 이동 자세를 선택할 수 있습니다.")
			"timed":
				data["win"] = [{"type":"reach_zone","zone":TIMED_ZONES[base].duplicate()},{"type":"time_limit","seconds":25.0}]
				data["fail"].append({"type":"time_limit","seconds":25.0})
				data["objectives"] = ["25초 안에 지정 구역에 도달하세요.", "이동 경로와 문 처리 시간을 함께 계획하세요."]
			"arrest":
				data["win"] = [{"type":"neutralize_all"}]
				data["objectives"] = ["투항한 적에게 체포 명령을 내려 모든 위협을 처리하세요.", "무사살 별 과제: 적을 사살하지 않고 완료하세요."]
				data.enemies[0]["enemy_type"] = "sentry"
		data["description"] = " · ".join(data.objectives)
		data["description_en"] = " · ".join(OBJECTIVES_EN.get(variant, data.objectives))
		data["briefing"] = {"difficulty":"보통","estimated_minutes":"3–8","threat":str(TYPE_LABELS[variant]),"tip":str(data.objectives[0])}
	# P1 restores capture goals in current operations. Retired arrest variants
	# retain their old catalog contract and remain hidden from briefings().
	data["stars"] = data.get("stars",[])
	if id.ends_with("_ARREST"):
		data["stars"] = data.get("stars", []).filter(func(star: Dictionary) -> bool: return str(star.get("stat", "")) not in ["kills", "arrests"])
	elif (BASE_IDS.has(id) or CHALLENGE_IDS.has(id)) and not data.stars.any(func(star: Dictionary) -> bool: return str(star.get("id","")) == "no_kills"):
		# Existing JSON had already retired this mission_authoring.py goal.
		# Restore it at catalog load without rewriting authored mission files.
		data.stars.append({"id":"no_kills","label":"무사살","stat":"kills","op":"eq","value":0})
	return data

static func _configure_roe_pair(data: Dictionary, id: String) -> void:
	# Two identities reuse the exact authored house, actor order and seed.
	# Their ROE does not change the normal/challenge variant or AI rules.
	var precision: bool = ROE_IDS[id] == "precision"
	data["schema_version"] = 6
	data["base_id"] = "M01"
	data["roe"] = ROE_IDS[id]
	data["variant"] = "normal"
	data["title"] += " · 정밀 작전" if precision else " · 고강도 작전"
	data["title_en"] = str(data.get("title_en", "Quiet House")) + (" · Precision Operation" if precision else " · High Intensity Operation")
	data["subtitle"] = "PRECISION" if precision else "HIGH INTENSITY"
	data["win"] = [{"type":"neutralize_all"}]
	data["fail"] = [{"type":"no_civilian_loss"}]
	if precision:
		data.win.append({"type":"secure_all_civilians"})
		data["objectives"] = ["모든 위협을 무력화하고 민간인 두 명을 확보하세요.", "섬광탄은 허용되며 파편 수류탄은 금지됩니다. 민간인을 보호하고 투항자를 생포하세요."]
		data["stars"] = [{"id":"no_civilian_damage","label":"비전투원 피해 0","stat":"civilian_damage","op":"eq","value":0}, {"id":"capture_surrendered","label":"투항자 생포","stat":"arrests","op":"gte","value":1}]
	else:
		data["civilians"] = []
		data["objectives"] = ["모든 위협을 무력화하세요. 이번 작전에는 민간인이 없습니다.", "파편 수류탄이 허용됩니다. 파편은 석고 내벽을 관통해 옆방의 아군을 다치게 할 수 있습니다."]
		# 240 seconds is the existing house par time, with the same floorplan.
		data["stars"] = [{"id":"no_unit_damage","label":"아군 부상 0","stat":"unit_damage","op":"eq","value":0}, {"id":"roe_time","label":"240초 이내 완료","stat":"time","op":"lte","value":240}]
	data["description"] = " · ".join(data.objectives)
	data["description_en"] = " · ".join(ROE_OBJECTIVES_EN[data.roe])
	data["briefing"] = {"difficulty":"보통","estimated_minutes":"5–10","threat":"무장 인원 · 민간인 혼재" if precision else "무장 인원 · 민간인 없음","tip":data.objectives[1]}

static func missions() -> Dictionary:
	var result: Dictionary = {}
	var parsed: Dictionary = {}
	for id: String in MAPS:
		result[id] = _load_data(id, parsed)
	return result

static func briefings(catalog: Dictionary = {}) -> Array:
	if catalog.is_empty(): catalog = missions()
	var result: Array = []
	for id: String in MAPS:
		if id.ends_with("_ARREST"): continue
		var data: Dictionary = catalog[id]
		var strengths := {"weak":0,"medium":0,"strong":0}
		for enemy: Dictionary in data.enemies:
			if not bool(enemy.get("training",false)) and not bool(enemy.get("target",false)) and not bool(enemy.get("passive",false)):
				strengths[str(enemy.get("strength","weak"))] += 1
		result.append({"id":id,"title":data.title,"name":data.title,"title_en":data.get("title_en",data.title),"variant":data.variant,"seed":data.seed,"stars":data.get("stars",[]),"win":data.get("win",[]),"fail":data.get("fail",[]),"units":data.units,"rooms":data.rooms.size(),"environment":data.get("environment",{}),"objectives":data.objectives,"briefing":data.get("briefing",{}),"description":data.get("description",""),"description_en":data.get("description_en",data.get("description","")),"historical":data.get("historical",{}),"bounds":data.bounds,"interactive_targets":data.get("interactive_targets",[]),"enemy_count":data.enemies.size(),"enemy_strengths":strengths,"civilian_count":data.civilians.size(),"challenge":data.challenge}.duplicate(true))
		if ROE_IDS.has(id):
			var entry: Dictionary = result.back()
			entry["roe"] = data.roe
			entry["base_id"] = data.base_id
			entry["objectives_en"] = ROE_OBJECTIVES_EN[data.roe].duplicate()
		elif CQBSeed.is_mission(id):
			# P7 standalone preparation must receive its authored ROE without
			# changing the established public shape of any legacy briefing.
			var entry: Dictionary = result.back()
			entry["roe"] = roe(data)
			if data.has("base_id"): entry["base_id"] = data.base_id
	return result

static func rules_for(data: Dictionary) -> Dictionary:
	var challenge: bool = bool(data.get("challenge",CHALLENGE_IDS.has(str(data.get("id","")))))
	var rules: Dictionary = (CHALLENGE if challenge else NORMAL).duplicate(true)
	rules["enemy_opens_doors"] = true
	for modifier: Variant in data.get("modifiers",[]):
		if not MODIFIERS.has(str(modifier)): continue
		for key: String in MODIFIERS[str(modifier)]:
			if key != "label": rules[key] = MODIFIERS[str(modifier)][key]
	return rules

static func apply_modifiers(data: Dictionary) -> Dictionary:
	var configured: Dictionary = data.duplicate(true)
	if bool(configured.get("_modifiers_applied", false)): return configured
	var modifiers: Array = configured.get("modifiers",[])
	if not modifiers.is_empty(): configured["_modifiers_applied"] = true
	if modifiers.has("night"):
		configured["environment"] = configured.get("environment", {}).duplicate(true)
		configured.environment.merge({"time_of_day":"night","lighting":0.25}, true)
	elif modifiers.has("dim"):
		configured["environment"] = configured.get("environment", {}).duplicate(true)
		configured.environment.merge({"time_of_day":"dim","lighting":0.55}, true)
	for unit: Dictionary in configured.get("units",[]):
		if modifiers.has("low_ammo"):
			var capacity: int = 32 if unit.get("weapon","standard") == "light" else (8 if unit.get("weapon","") == "shotgun" else (18 if unit.get("weapon","") == "suppressed" else 24))
			unit["ammo"] = maxi(0, floori(float(unit.get("ammo",capacity))*0.5))
			unit["reserve_ammo"] = maxi(0, floori(float(unit.get("reserve_ammo",capacity*3))*0.5))
		if modifiers.has("no_stun"): unit["stuns"] = 0
	return configured

static func validate_custom(data: Variant) -> Dictionary:
	return MissionSchema.check(data)

static func load(id: String) -> Dictionary:
	return _load_data(id, {})
