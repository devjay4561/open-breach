extends RefCounted
## Shared, deterministic equipment rules. New profiles use catalog defaults;
## legacy actors without the new slots retain no additional protection.
static var _data: Dictionary = {}
const LOADOUT_FIELDS: Array[String] = ["weapon","equipment","sidearm","armor","helmet","attachments","appearance","preset"]

static func frag_stats() -> Dictionary:
	# Fixed P5 gameplay profile; no RNG draw or mutable shared result.
	return {"prepare":0.6,"range":8.0,"flight_speed":12.0,"fuse":1.2,"radius":4.0,"core_radius":1.0,"damage":120.0,"wall_penetration":0.6,"armor_penetration":14.0,"sound":14.0}

static func catalog() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment_catalog.json"))
		if parsed is Dictionary: _data = parsed
	return _data

static func definition(id: String) -> Dictionary:
	for group: String in ["weapons","sidearms","armor","helmets","attachments","equipment","presets"]:
		for entry: Dictionary in catalog().get(group,[]):
			if entry.id == id: return entry.duplicate(true)
	return {}

static func _has(group: String, id: Variant) -> bool:
	if not id is String: return false
	for entry: Dictionary in catalog().get(group,[]):
		if entry.id == id: return true
	return false

static func _finite_integer(value: Variant, maximum: int) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= 0 and float(value) <= maximum

static func equipment_error(value: Variant) -> String:
	var counts: Dictionary = {}
	if value is String:
		if value != "none": counts[value] = 1
	elif value is Array:
		for id: Variant in value:
			if not id is String: return "장비 ID가 필요합니다"
			counts[id] = int(counts.get(id,0))+1
	elif value is Dictionary: counts = value
	else: return "장비 배열 또는 수량 객체가 필요합니다"
	var small: int = 0
	var large: int = 0
	for id: Variant in counts:
		if not _has("equipment",id): return "알 수 없는 장비"
		if not _finite_integer(counts[id],2): return "장비 수량은 0–2여야 합니다"
		if definition(str(id)).slot == "large": large += int(counts[id])
		else: small += int(counts[id])
	# Two-slot legacy loadouts, including two breach charges, remain valid.
	if small+large <= int(catalog().slots.legacy_total): return ""
	if small > int(catalog().slots.small) or large > int(catalog().slots.large): return "소형 장비 2개·대형 장비 1개까지 사용할 수 있습니다"
	return ""

static func loadout_error(raw: Variant) -> String:
	if not raw is Dictionary: return "장비 객체가 필요합니다"
	for key: Variant in raw:
		if not str(key) in LOADOUT_FIELDS: return "알 수 없는 장비 필드 " + str(key)
	if raw.has("weapon") and not _has("weapons",raw.weapon): return "알 수 없는 주무기"
	for field: String in ["sidearm","armor","helmet"]:
		var group: String = {"sidearm":"sidearms","armor":"armor","helmet":"helmets"}[field]
		if raw.has(field) and raw[field] != "none" and not _has(group,raw[field]): return "알 수 없는 " + field
	if raw.has("equipment"):
		var problem: String = equipment_error(raw.equipment)
		if not problem.is_empty(): return problem
	if raw.has("attachments"):
		if not raw.attachments is Array or raw.attachments.size() > 3: return "부착물은 최대 3개입니다"
		var slots: Array = []
		for id: Variant in raw.attachments:
			if not _has("attachments",id): return "알 수 없는 부착물"
			var entry: Dictionary = definition(str(id))
			if slots.has(entry.slot): return "같은 장착 슬롯의 부착물이 중복됩니다"
			if not str(raw.get("weapon","standard")) in entry.weapons: return "무기에 호환되지 않는 부착물"
			slots.append(entry.slot)
	if raw.has("preset") and raw.preset != "custom" and not _has("presets",raw.preset): return "알 수 없는 프리셋"
	if raw.has("appearance"):
		if not raw.appearance is Dictionary: return "외형 객체가 필요합니다"
		for key: Variant in raw.appearance:
			if not str(key) in ["name","callsign","color","patch"]: return "알 수 없는 외형 필드"
		for field: String in ["name","callsign"]:
			if raw.appearance.has(field):
				var value: Variant = raw.appearance[field]
				if not value is String or value.length() > (48 if field == "name" else 32): return "이름 또는 콜사인이 너무 깁니다"
				for i: int in range(value.length()):
					if value.unicode_at(i) < 32 or value.unicode_at(i) == 127: return "이름에 제어 문자를 사용할 수 없습니다"
		if raw.appearance.has("color"):
			var expression := RegEx.new()
			expression.compile("^#[0-9a-fA-F]{6}$")
			if not raw.appearance.color is String or expression.search(raw.appearance.color) == null: return "색상은 #RRGGBB여야 합니다"
		if raw.appearance.has("patch") and not raw.appearance.patch in catalog().appearance.patches: return "알 수 없는 패치"
	return ""

static func validate_loadout(raw: Variant) -> Dictionary:
	var message: String = loadout_error(raw)
	return {"ok":message.is_empty(),"message":message}

static func resolve_loadout(raw: Dictionary = {}, fresh: bool = false) -> Dictionary:
	var result: Dictionary = catalog().defaults.duplicate(true)
	if not fresh:
		result.sidearm = "none"
		result.armor = "none"
		result.helmet = "none"
	if _has("weapons",raw.get("weapon")): result.weapon = raw.weapon
	for field: String in ["sidearm","armor","helmet"]:
		var group: String = {"sidearm":"sidearms","armor":"armor","helmet":"helmets"}[field]
		if raw.has(field) and (raw[field] == "none" or _has(group,raw[field])): result[field] = raw[field]
	if raw.has("equipment"):
		var value: Variant = raw.equipment
		var counts: Dictionary = {}
		if value is String:
			if _has("equipment",value): counts[value] = 1
		elif value is Array:
			for id: Variant in value:
				if _has("equipment",id): counts[id] = mini(2,int(counts.get(id,0))+1)
		elif value is Dictionary:
			for id: Variant in value:
				if _has("equipment",id) and _finite_integer(value[id],2): counts[id] = int(value[id])
		result.equipment = counts
	var slots: Array = []
	result.attachments = []
	for entry: Dictionary in catalog().attachments:
		if raw.get("attachments",[]) is Array and raw.get("attachments",[]).has(entry.id) and entry.weapons.has(result.weapon) and not slots.has(entry.slot):
			result.attachments.append(entry.id)
			slots.append(entry.slot)
	if raw.get("appearance") is Dictionary:
		for field: String in ["name","callsign","color","patch"]:
			if raw.appearance.has(field):
				var test: Dictionary = {"appearance":{field:raw.appearance[field]}}
				if loadout_error(test).is_empty(): result.appearance[field] = raw.appearance[field]
	if raw.get("preset","custom") == "custom" or _has("presets",raw.get("preset")): result.preset = raw.get("preset","custom")
	return result

static func weapon_stats(id: String, attachments: Array = []) -> Dictionary:
	var entry: Dictionary = definition(id)
	if not entry.has("stats"): entry = definition("standard")
	var stats: Dictionary = entry.stats.duplicate(true)
	for key: String in ["id","label","label_en","model","weight"]: stats[key] = entry.get(key,0)
	var slots: Array = []
	for attachment: Dictionary in catalog().attachments:
		if not attachments.has(attachment.id) or not attachment.weapons.has(entry.id) or slots.has(attachment.slot): continue
		slots.append(attachment.slot)
		stats.weight = float(stats.weight)+float(attachment.weight)
		for modifier: String in attachment.modifiers:
			var value: float = float(attachment.modifiers[modifier])
			if modifier.ends_with("_add"):
				var key: String = modifier.trim_suffix("_add")
				stats[key] = float(stats.get(key,0))+value
			elif modifier.ends_with("_multiplier"):
				var key: String = modifier.trim_suffix("_multiplier")
				stats[key] = float(stats.get(key,0))*value
	stats.accuracy = clampf(float(stats.accuracy),0,0.99)
	stats.ammo = int(stats.ammo)
	return stats

static func loadout_stats(raw: Dictionary, trait_id: String = "") -> Dictionary:
	var loadout: Dictionary = resolve_loadout(raw)
	var stats: Dictionary = weapon_stats(loadout.weapon,loadout.attachments)
	var armor: Dictionary = definition(loadout.armor)
	if armor.is_empty(): armor = {"id":"none","weight":0,"panels":[],"movement_multiplier":1,"action_multiplier":1}
	var helmet: Dictionary = definition(loadout.helmet)
	if helmet.is_empty(): helmet = {"id":"none","weight":0,"resistance":0,"reduction":0}
	var sidearm: Dictionary = definition(loadout.sidearm)
	var tool_weight: float = 0
	for tool: Dictionary in catalog().equipment: tool_weight += float(tool.weight)*float(loadout.equipment.get(tool.id,0))
	stats.weapon_weight = stats.weight
	stats.normal_moving_accuracy = float(stats.accuracy)*float(catalog().friendly_movement_accuracy.normal)
	stats.weight = float(stats.weight)+float(armor.weight)+float(helmet.weight)+float(sidearm.get("weight",0))+tool_weight
	stats.movement_multiplier = float(armor.get("movement_multiplier",1))*float(helmet.get("movement_multiplier",1))
	stats.action_multiplier = float(armor.get("action_multiplier",1))*float(helmet.get("action_multiplier",1))
	stats.armor = armor
	stats.helmet = helmet
	stats.sidearm_stats = weapon_stats(loadout.sidearm) if not sidearm.is_empty() else {}
	var handling: Dictionary = catalog().handling
	var length_factor: float = 1.0 + maxf(0.0, float(stats.length) - float(handling.reference_length)) * float(handling.length_aim_penalty)
	stats.final_aim_time = float(stats.aim_time) * length_factor * float(stats.action_multiplier)
	stats.final_reload_time = float(stats.reload) * float(stats.action_multiplier)
	stats.primary_switch_time = float(stats.switch_time) * float(stats.action_multiplier)
	stats.secondary_switch_time = float(stats.sidearm_stats.get("switch_time", 0.0)) * float(stats.action_multiplier)
	var selected_trait: String = trait_id if not trait_id.is_empty() else str(raw.get("trait", ""))
	var trait_effects: Dictionary = catalog().traits.get(selected_trait, {})
	stats.range = float(stats.range) + float(trait_effects.get("range_add", 0.0))
	stats.interval = float(stats.interval) * float(trait_effects.get("interval_multiplier", 1.0))
	stats.loadout = loadout
	return stats

static func effective_stats(entity: Dictionary) -> Dictionary:
	return loadout_stats(entity)

static func shotgun_breach_stats() -> Dictionary:
	return {"duration":1.2,"sound":14.0,"success":0.9}

static func can_shotgun_breach(entity: Dictionary) -> bool:
	return str(entity.get("active_weapon","primary")) == "primary" and str(entity.get("current_weapon",entity.get("weapon","standard"))) == "shotgun" and int(entity.get("ammo",0)) > 0

static func _within_arc(angle: float, arc: Array) -> bool:
	var span: float = float(arc[1])-float(arc[0])
	return span >= 360 or fposmod(rad_to_deg(angle)-float(arc[0]),360) <= span+0.00001

## incoming_angle is measured relative to body facing: 0 front, PI rear.
static func protection(raw: Dictionary, hit_region: String, incoming_angle: float, penetration: float) -> Dictionary:
	var loadout: Dictionary = resolve_loadout(raw)
	var region: String = "torso" if hit_region in ["torso","chest","body"] else hit_region
	var item: Dictionary = definition(loadout.helmet if region == "head" else loadout.armor)
	var result: Dictionary = {"protected":false,"reduction":0.0,"armor_id":item.get("id","none"),"panel":"none","resistance":0.0}
	if region == "head" and not item.is_empty():
		result.panel = "helmet"
		result.resistance = float(item.resistance)
		result.protected = penetration <= float(item.resistance)
		result.reduction = float(item.reduction) if result.protected else 0.0
	elif not item.is_empty():
		for panel: Dictionary in item.get("panels",[]):
			if not panel.regions.has(region) or not _within_arc(incoming_angle,panel.arc): continue
			if float(panel.resistance) > float(result.resistance):
				result.panel = panel.panel
				result.resistance = float(panel.resistance)
				result.protected = penetration <= float(panel.resistance)
				result.reduction = float(panel.reduction) if result.protected else 0.0
	return result
