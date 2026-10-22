extends RefCounted
## Runtime authoring boundary for imported operation and replay files.
## Geometry uses the same navigation implementation as the running simulation.
const Navigation = preload("res://scripts/navigation.gd")
const EquipmentCatalog = preload("res://scripts/equipment_catalog.gd")
const GROUPS: Array[String] = ["rooms","walls","doors","props","units","enemies","civilians"]
## RD (plan 2-5 영어 문자열 분리): optional English counterparts to title/
## description, exposed in MissionCatalog.briefings() so the web can show
## them when settings.language === 'en'. Korean stays the single source of
## truth; these are nullable translations, not a replacement schema.
const OPTIONAL: Array[String] = ["briefing","subtitle","description","title_en","description_en","win","fail","stars","variant","modifiers","default_seed","base_id","challenge","custom","loadout","roster","environment"]
const V2_OPTIONAL: Array[String] = ["historical","scenery","walkable_areas","interactive_targets"]
const V5_OPTIONAL: Array[String] = ["noise_discipline"]
const V6_OPTIONAL: Array[String] = ["roe"]
const CURRENT_SCHEMA_VERSION: int = 6
const V3_DOOR_FIELDS: Array[String] = ["kick_resistance","reinforced"]
const REQUIRED: Array[String] = ["schema_version","id","revision","title","seed","bounds","focus","rooms","walls","doors","props","units","enemies","civilians","objectives"]
const RECT: Array[String] = ["id","x","z","w","d"]
const GEOMETRY_FIELDS: Array[String] = ["height","base_height","material","opacity","resistance","opaque","penetration_resistance"]
const ACTOR_FIELDS: Array[String] = ["stance","movement_mode","hold_position","reserve_ammo","body_facing","aim_progress","injury","injury_status","mobility_multiplier","velocity_x","velocity_z","awareness_state","awareness_confidence","observation_source","exposure","aim_state","action_multiplier","reload_duration","weapon_height"]
const MATERIALS: Array[String] = ["wood","concrete","metal","fabric","glass","masonry","plaster","foliage","steel","drywall","brick","cloth"]
const SURFACES: Array[String] = ["concrete","tile","wood","carpet","gravel"]
const AWARENESS: Array[String] = ["UNAWARE","DETECTED","IDENTIFIED","TRACKING","SUSPICIOUS"]
const SOURCES: Array[String] = ["none","sight","sound","report"]
const FIELDS: Dictionary = {
	"rooms":["id","x","z","w","d","label","color","indoor","lighting","floor_surface"],
	"walls":["id","x","z","w","d","thin"] + GEOMETRY_FIELDS,
	"doors":["id","x","z","w","d","axis","label","state","swing_sign","hinge_side","locked","hp","durability","destroyed","progress","initial_states"] + GEOMETRY_FIELDS,
	"props":["id","x","z","w","d","type","rotation","solid","cover"] + GEOMETRY_FIELDS,
	"units":["id","name","role","x","z","facing","weapon","hp","ammo","stuns","smokes","breaches","charges","cameras","vision_range","fov","trait","roster_id","base_id","equipment","sidearm","armor","helmet","attachments","appearance","preset"] + ACTOR_FIELDS,
	"enemies":["id","name","x","z","facing","weapon","hp","ammo","vision_range","fov","patrol","target","passive","training","strength","enemy_type","response_role","spawns"] + ACTOR_FIELDS,
	"civilians":["id","name","x","z","facing","hp","secured"] + ACTOR_FIELDS,
}
const LIMITS: Dictionary = {"rooms":64,"walls":512,"doors":64,"props":512,"units":4,"enemies":32,"civilians":32}
const COVER: Dictionary = {"table":"low","desk":"low","sofa":"low","bed":"low","cabinet":"full","bookshelf":"full","plant":"none","chair":"none","crate":"low","rug":"none","vehicle":"full","pillar":"full"}
const RULES: Array[String] = ["neutralize_all","secure_all_civilians","reach_zone","before_alert","time_limit","escort_to_zone","no_civilian_loss"]
const V2_RULES: Array[String] = ["targets_complete","no_shots"]
const V4_RULES: Array[String] = ["rooms_cleared"]
const STATS: Array[String] = ["plan_revisions","stuns_used","hits_taken","units_deployed","reloads","kills","arrests","shots_fired","command_failures","losses","duration","time","civilian_losses"]
const V6_STATS: Array[String] = ["civilian_damage","unit_damage"]
var errors: Array[String] = []
var bounds: Array = [24.0,20.0]
var ids: Dictionary = {}
var identifier: RegEx = RegEx.new()
var version: int = 1
var max_extent: float = 32.0

static func check(data: Variant) -> Dictionary:
	var validator := new()
	return validator.validate(data)

func reject(label: String, message: String) -> void:
	if errors.size() < 32: errors.append(label + ": " + message)

func require(ok: bool, label: String, message: String) -> void:
	if not ok: reject(label,message)

func numeric(value: Variant, low: float = -1.0e15, high: float = 1.0e15) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) >= low and float(value) <= high

func integer(value: Variant, low: int, high: int) -> bool:
	return numeric(value,float(low),float(high)) and float(value) == floor(float(value))

func text(value: Variant, limit: int = 128) -> bool:
	return value is String and not value.is_empty() and value.length() <= limit

func shape(value: Variant, allowed: Array, required: Array, label: String) -> bool:
	if not value is Dictionary:
		reject(label,"객체가 필요합니다")
		return false
	for key: Variant in value:
		require((key is String or key is StringName) and allowed.has(str(key)),label,"알 수 없는 필드 " + str(key))
	for key: String in required:
		require(value.has(key),label,"필수 필드 누락 " + key)
	return required.all(func(key: String) -> bool: return value.has(key))

func point(value: Variant, label: String) -> bool:
	var valid: bool = value is Array and value.size() == 2 and numeric(value[0],0,float(bounds[0])) and numeric(value[1],0,float(bounds[1]))
	require(valid,label,"지도 안의 유한 좌표 [x,z]가 필요합니다")
	return valid

func rectangle(value: Dictionary, label: String) -> void:
	require(numeric(value.w,0.01,max_extent) and numeric(value.d,0.01,max_extent),label,"버전에 맞는 양수 크기가 필요합니다")
	if not numeric(value.w) or not numeric(value.d) or not numeric(value.x) or not numeric(value.z): return
	var width: float = float(value.w)
	var depth: float = float(value.d)
	if numeric(value.get("rotation",0)) and absf(sin(float(value.get("rotation",0)))) > 0.7:
		width = float(value.d)
		depth = float(value.w)
	require(float(value.x)-width*0.5 >= 0 and float(value.z)-depth*0.5 >= 0 and float(value.x)+width*0.5 <= float(bounds[0]) and float(value.z)+depth*0.5 <= float(bounds[1]),label,"사각형이 지도 밖에 있습니다")

func patrol(value: Variant, label: String) -> void:
	if not value is Array or value.size() > 64:
		reject(label,"최대 64개의 좌표가 필요합니다")
		return
	for i: int in range(value.size()): point(value[i],label+"["+str(i)+"]")

func equipment(value: Variant, label: String) -> void:
	var problem: String = EquipmentCatalog.equipment_error(value)
	require(problem.is_empty(),label,problem)

func obstacle_rect(obj: Dictionary) -> Rect2:
	var size := Vector2(float(obj.w),float(obj.d))
	if absf(sin(float(obj.get("rotation",0)))) > 0.7: size = Vector2(size.y,size.x)
	return Rect2(Vector2(float(obj.x),float(obj.z))-size*0.5,size)

func overlap(a: Dictionary, b: Dictionary) -> bool:
	# Vector2/Rect2 uses single precision in this Godot build. Converting
	# imported metre coordinates to Rect2 can make a doorway's exact wall
	# endpoint appear to overlap by several micrometres on a large map.
	# Keep the authored double precision through this schema calculation,
	# matching the Python validator without increasing the overlap tolerance.
	var aw: float = float(a.w)
	var ad: float = float(a.d)
	var bw: float = float(b.w)
	var bd: float = float(b.d)
	if absf(sin(float(a.get("rotation",0)))) > 0.7:
		var original: float = aw
		aw = ad
		ad = original
	if absf(sin(float(b.get("rotation",0)))) > 0.7:
		var original: float = bw
		bw = bd
		bd = original
	return minf(float(a.x)+aw*0.5,float(b.x)+bw*0.5)-maxf(float(a.x)-aw*0.5,float(b.x)-bw*0.5) > 1e-6 and minf(float(a.z)+ad*0.5,float(b.z)+bd*0.5)-maxf(float(a.z)-ad*0.5,float(b.z)-bd*0.5) > 1e-6

func rules(value: Variant, label: String) -> void:
	if not value is Array or value.size() > 16 or (label == "win" and value.is_empty()):
		reject(label,"승리 규칙 1–16개 또는 실패 규칙 0–16개가 필요합니다")
		return
	for i: int in range(value.size()):
		var location: String = label+"["+str(i)+"]"
		var rule: Variant = value[i]
		if not rule is Dictionary:
			reject(location,"규칙 객체가 필요합니다")
			continue
		var kind: Variant = rule.get("type","")
		require(kind is String and (RULES.has(kind) or (version >= 2 and V2_RULES.has(kind)) or (version >= 4 and V4_RULES.has(kind))),location,"알 수 없는 규칙")
		var allowed: Array = ["type"]
		if kind in ["reach_zone","escort_to_zone"]:
			allowed.append("zone")
			var zone: Variant = rule.get("zone")
			var valid: bool = zone is Array and zone.size() == 4 and zone.all(func(n: Variant) -> bool: return numeric(n))
			require(valid,location,"zone은 [x,z,w,d]여야 합니다")
			if valid: rectangle({"x":zone[0],"z":zone[1],"w":zone[2],"d":zone[3]},location+".zone")
		if kind == "time_limit":
			allowed.append("seconds")
			require(numeric(rule.get("seconds"),0.001,3600),location,"제한 시간은 0초 초과 3600초 이하여야 합니다")
		if kind == "targets_complete":
			allowed.append("targets")
			var targets: Variant = rule.get("targets")
			require(targets is Array and not targets.is_empty() and targets.size() <= 64 and targets.all(func(id: Variant) -> bool: return text(id,64) and identifier.search(str(id)) != null),location,"1–64개의 목표 ID가 필요합니다")
			if targets is Array:
				var unique: Array = []
				for id: Variant in targets:
					require(not unique.has(id),location,"목표 ID가 중복됩니다")
					unique.append(id)
		if kind == "rooms_cleared" and version >= 4:
			allowed.append("room_ids")
			if rule.has("room_ids"):
				var rooms: Variant = rule.room_ids
				require(rooms is Array and not rooms.is_empty() and rooms.size() <= 64 and rooms.all(func(id: Variant) -> bool: return text(id,64) and identifier.search(str(id)) != null),location+".room_ids","1–64개의 방 ID가 필요합니다")
				if rooms is Array:
					var unique: Array = []
					for id: Variant in rooms:
						require(not unique.has(id),location+".room_ids","방 ID가 중복됩니다")
						unique.append(id)
		# Unlike targets_complete, a room goal may omit its target list: that
		# explicitly means every authored room, without rewriting old missions.
		shape(rule,allowed,["type"] if kind == "rooms_cleared" else allowed,location)

func historical_fields(data: Dictionary) -> void:
	if data.has("historical") and shape(data.historical,["location","location_en","accuracy_note","accuracy_note_en"],["location","accuracy_note"],"historical"):
		var history: Dictionary = data.historical
		for key: String in history:
			require(text(history[key],256 if key.begins_with("location") else 2000),"historical."+key,"가상 장소 또는 작전 기록이 필요합니다")
	for field: String in ["scenery","walkable_areas","interactive_targets"]:
		if not data.has(field): continue
		var limit: int = 512 if field == "scenery" else (128 if field == "walkable_areas" else 64)
		if not data[field] is Array or data[field].size() > limit or (field == "walkable_areas" and data[field].is_empty()):
			reject(field,"배열 크기 제한을 초과했거나 허용 바닥이 없습니다")
			continue
		var registry: Variant = {}
		if field == "scenery" and not data[field].is_empty():
			if FileAccess.file_exists("res://assets/historical/registry.json"):
				registry = JSON.parse_string(FileAccess.get_file_as_string("res://assets/historical/registry.json"))
			if not registry is Dictionary: registry = {}
		for i: int in range(data[field].size()):
			var label := field+"["+str(i)+"]"
			var allowed: Array = ["id","asset","x","z","rotation","scale","height","cutaway"] if field == "scenery" else RECT.duplicate()
			var needed: Array = ["id","asset","x","z"] if field == "scenery" else RECT.duplicate()
			if field == "interactive_targets":
				allowed.append_array(["label","action","duration"])
				needed.append_array(["label","action","duration"])
			if not shape(data[field][i],allowed,needed,label): continue
			var obj: Dictionary = data[field][i]
			require(text(obj.id,64) and identifier.search(str(obj.id)) != null and not ids.has(obj.id),label+".id","중복 없는 안전한 ID가 필요합니다")
			ids[str(obj.id)] = true
			point([obj.x,obj.z],label)
			if field != "scenery": rectangle(obj,label)
			else:
				require(obj.asset is String and registry.has(obj.asset),label+".asset","등록되지 않은 작전 에셋입니다")
				if obj.has("cutaway"): require(typeof(obj.cutaway) == TYPE_BOOL,label+".cutaway","불리언이 필요합니다")
				if obj.has("rotation"): require(numeric(obj.rotation),label+".rotation","유한 라디안 각도가 필요합니다")
				if obj.has("scale"): require(numeric(obj.scale,0.01,10),label+".scale","균일 배율은 0.01–10이어야 합니다")
				if obj.has("height"): require(numeric(obj.height,-64,64),label+".height","배치 높이는 -64–64m여야 합니다")
			if field == "interactive_targets":
				require(text(obj.label,128),label+".label","목표 이름이 필요합니다")
				require(obj.action in ["recover","disable","inspect","board"],label+".action","알 수 없는 목표 동작")
				require(numeric(obj.duration,0.001,60),label+".duration","작업 시간은 0초 초과 60초 이하여야 합니다")

func actor_geometry(nav: RefCounted, actor: Dictionary, opened: Array, origin: Vector2, label: String, challenge: bool) -> void:
	var start := Vector2(float(actor.x),float(actor.z))
	require(nav.walkable(start),label,"시작 위치가 벽, 가구 또는 닫힌 문에 막혔습니다")
	route(nav,origin,start,opened,label)
	var previous: Vector2 = start
	for raw: Array in actor.get("patrol",[]):
		var target := Vector2(float(raw[0]),float(raw[1]))
		require(nav.walkable(target),label,"순찰 지점이 처음 문 상태에서 막혔습니다")
		route(nav,previous,target,opened,label+" 순찰")
		if challenge: route(nav,previous,target,opened,label+" 열린 문 순찰")
		previous = target
	if not actor.get("patrol",[]).is_empty():
		route(nav,previous,start,opened,label+" 순찰 복귀")
		if challenge: route(nav,previous,start,opened,label+" 열린 문 순찰 복귀")

func route(nav: RefCounted, start: Vector2, target: Vector2, opened: Array, label: String) -> void:
	var path: Array = nav.path(start,target,opened)
	require(not path.is_empty(),label,"도달 가능한 경로가 없습니다")
	var previous: Vector2 = start
	for raw: Array in path:
		var current := Vector2(float(raw[0]),float(raw[1]))
		require(nav.segment_clear(previous,current,Navigation.RADIUS,opened),label,"경로가 장애물을 통과합니다")
		previous = current

func reachable_zone(nav: RefCounted, zone: Array, opened: Array, origin: Vector2, label: String) -> void:
	# Most large outdoor zones have an unobstructed center. Try it before
	# sampling up to a million quarter-metre cells along their boundary.
	var center := Vector2(float(zone[0]), float(zone[1]))
	if nav.walkable(center,opened) and not nav.path(origin,center,opened).is_empty(): return
	var nx: int = maxi(1,ceili(float(zone[2])/Navigation.CELL))
	var nz: int = maxi(1,ceili(float(zone[3])/Navigation.CELL))
	for x: int in range(nx):
		for z: int in range(nz):
			var target := Vector2(float(zone[0])-float(zone[2])*0.5+(x+0.5)*float(zone[2])/nx,float(zone[1])-float(zone[3])*0.5+(z+0.5)*float(zone[3])/nz)
			if nav.walkable(target,opened) and not nav.path(origin,target,opened).is_empty(): return
	reject(label,"도달 가능한 구역 바닥이 없습니다")

func open_passage(nav: RefCounted, door: Dictionary, opened: Array) -> bool:
	var normal := Vector2.DOWN if door.axis == "x" else Vector2.RIGHT
	var across := Vector2.RIGHT if door.axis == "x" else Vector2.DOWN
	var span: float = float(door.w) if door.axis == "x" else float(door.d)
	var fronts: Array[Vector2] = []
	var backs: Array[Vector2] = []
	for distance: float in [0.55,0.8,1.1]:
		for shift: float in [0.0,-0.2,0.2]:
			var center := Vector2(float(door.x),float(door.z)) + across*span*shift
			if nav.walkable(center+normal*distance,opened): fronts.append(center+normal*distance)
			if nav.walkable(center-normal*distance,opened): backs.append(center-normal*distance)
	for front: Vector2 in fronts:
		for back: Vector2 in backs:
			if not nav.path(front,back,opened).is_empty():
				route(nav,front,back,opened,str(door.id)+" 열린 문")
				return true
	return false

func validate(value: Variant) -> Dictionary:
	identifier.compile("^[A-Za-z][A-Za-z0-9_-]{0,63}$")
	if not value is Dictionary: reject("mission","객체가 필요합니다"); return answer(value)
	version = int(value.schema_version) if integer(value.get("schema_version"),1,CURRENT_SCHEMA_VERSION) else 1
	max_extent = 512.0 if version >= 2 else 32.0
	if not shape(value,REQUIRED+OPTIONAL+(V2_OPTIONAL if version >= 2 else [])+(V5_OPTIONAL if version >= 5 else [])+(V6_OPTIONAL if version >= 6 else []),REQUIRED,"mission"): return answer(value)
	var data: Dictionary = value
	require(integer(data.schema_version,1,CURRENT_SCHEMA_VERSION),"schema_version","버전 1–6이 필요합니다")
	if data.has("noise_discipline"):
		require(data.noise_discipline is String and data.noise_discipline in ["verbal","hand_signals"],"noise_discipline","verbal 또는 hand_signals 문자열이 필요합니다")
	if data.has("roe"):
		require(data.roe is String and data.roe in ["precision","high_intensity"],"roe","precision 또는 high_intensity 문자열이 필요합니다")
	require(integer(data.revision,1,2147483647),"revision","양수 정수가 필요합니다")
	require(integer(data.seed,0,2147483647),"seed","안전한 비음수 정수가 필요합니다")
	require(text(data.id,64) and identifier.search(str(data.id)) != null,"id","안전한 ASCII ID가 필요합니다")
	for field: String in ["title","subtitle","description","title_en","description_en"]:
		if data.has(field): require(text(data[field],2000 if field in ["description","description_en"] else 128),field,"텍스트 길이가 올바르지 않습니다")
	if not data.bounds is Array or data.bounds.size() != 2 or not data.bounds.all(func(n: Variant) -> bool: return numeric(n,1,max_extent)):
		reject("bounds","지도 크기는 버전별 제한 이하의 숫자 두 개여야 합니다: "+str(max_extent))
		return answer(value)
	bounds = data.bounds
	point(data.focus,"focus")
	if data.has("default_seed"): require(integer(data.default_seed,0,2147483647),"default_seed","안전한 정수가 필요합니다")
	if data.has("base_id"): require(text(data.base_id,64) and identifier.search(str(data.base_id)) != null,"base_id","안전한 ID가 필요합니다")
	if data.has("challenge"): require(typeof(data.challenge) == TYPE_BOOL,"challenge","불리언이 필요합니다")
	if data.has("custom"): require(typeof(data.custom) == TYPE_BOOL,"custom","불리언이 필요합니다")
	if version >= 2: historical_fields(data)
	var environment_fields: Array = ["time_of_day","lighting"] + (["biome","ground_color","water","ground_surface","water_level"] if version >= 2 else [])
	if data.has("environment") and shape(data.environment,environment_fields,[],"environment"):
		if data.environment.has("time_of_day"): require(data.environment.time_of_day in ["day","dim","night"],"environment.time_of_day","알 수 없는 조명 환경")
		if data.environment.has("lighting"): require(numeric(data.environment.lighting,0,1),"environment.lighting","조명은 0–1이어야 합니다")
		if data.environment.has("biome"): require(text(data.environment.biome,64),"environment.biome","지형 이름이 필요합니다")
		if data.environment.has("ground_surface"): require(data.environment.ground_surface in SURFACES or (version >= 2 and data.environment.ground_surface == "ship_deck"),"environment.ground_surface","알 수 없는 바닥 재질")
		if data.environment.has("water"): require(typeof(data.environment.water) == TYPE_BOOL,"environment.water","불리언이 필요합니다")
		if data.environment.has("water_level"): require(numeric(data.environment.water_level,-16,0),"environment.water_level","수면 높이는 -16–0m여야 합니다")
		if data.environment.get("water",false) == true: require(data.has("walkable_areas") and data.walkable_areas is Array and not data.walkable_areas.is_empty(),"walkable_areas","수면이 있는 지도에는 명시적인 허용 바닥이 필요합니다")
		if data.environment.has("ground_color"):
			var color_regex := RegEx.new()
			color_regex.compile("^#[0-9A-Fa-f]{6}$")
			require(data.environment.ground_color is String and color_regex.search(str(data.environment.ground_color)) != null,"environment.ground_color","#RRGGBB 색상이 필요합니다")
	if data.has("loadout"):
		if not data.loadout is Dictionary or data.loadout.size() > 8:
			reject("loadout","최대 8개 대원 장비 객체가 필요합니다")
		else:
			for key: Variant in data.loadout:
				var choice: Variant = data.loadout[key]
				require(text(key,64) and identifier.search(str(key)) != null,"loadout","안전한 대원 ID가 필요합니다")
				var problem: String = EquipmentCatalog.loadout_error(choice)
				require(problem.is_empty(),"loadout."+str(key),problem)
	if data.has("roster"):
		if not data.roster is Array or data.roster.size() > 8:
			reject("roster","최대 8개 명부 항목이 필요합니다")
		else:
			for member: Variant in data.roster:
				if not shape(member,["id","base_id","name","trait"],["id"],"roster"): continue
				require(text(member.id,64) and identifier.search(str(member.id)) != null,"roster.id","안전한 ID가 필요합니다")
				if member.has("base_id"): require(text(member.base_id,64) and identifier.search(str(member.base_id)) != null,"roster.base_id","안전한 ID가 필요합니다")
				if member.has("name"): require(text(member.name),"roster.name","이름이 필요합니다")
				if member.has("trait"): require(member.trait in ["","breacher","marksman","cautious","rescuer","hold_after_hit"],"roster.trait","알 수 없는 고정 특성")
	if data.has("variant"): require(data.variant in ["normal","standard","base","challenge","hostage","escort","infiltration","timed","arrest"],"variant","알 수 없는 유형")
	if data.has("modifiers"):
		var modifiers: Variant = data.modifiers
		if not modifiers is Array or modifiers.size() > 5:
			reject("modifiers","최대 5개 변형 ID가 필요합니다")
		else:
			var used: Array = []
			for modifier: Variant in modifiers:
				require(modifier in ["night","dim","low_ammo","fast_reaction","no_stun"] and not used.has(modifier),"modifiers","알 수 없거나 중복된 변형 ID")
				used.append(modifier)
	for field: String in ["win","fail"]:
		if data.has(field): rules(data[field],field)
	if not data.objectives is Array or data.objectives.is_empty() or data.objectives.size() > 16:
		reject("objectives","1–16개 목표 문구가 필요합니다")
	else:
		for objective: Variant in data.objectives: require(text(objective,500),"objectives","목표 문구가 올바르지 않습니다")
	if data.has("briefing") and shape(data.briefing,["difficulty","estimated_minutes","threat","tip"],[],"briefing"):
		for field: String in data.briefing: require(text(data.briefing[field],1000),"briefing."+field,"문구가 올바르지 않습니다")
	if data.has("stars"):
		if not data.stars is Array or data.stars.size() > 16:
			reject("stars","최대 16개 별 과제가 필요합니다")
		else:
			var star_ids: Array = []
			for raw: Variant in data.stars:
				if not shape(raw,["id","label","stat","op","value","type"],["id","label"],"stars"): continue
				var star: Dictionary = raw
				require(text(star.id,64) and identifier.search(str(star.id)) != null and not star_ids.has(star.id),"stars.id","중복 없는 안전한 ID가 필요합니다")
				star_ids.append(star.id)
				require(text(star.label),"stars.label","문구가 필요합니다")
				if star.has("type"):
					require(star.type in ["completion","survivors","par_time"] and not star.has("stat") and not star.has("op"),"stars.type","알 수 없는 기존 메달 종류")
					if star.type == "par_time": require(numeric(star.get("value"),0.001,3600),"stars.value","양수 시간이 필요합니다")
				else:
					var allowed_stats: Array = STATS + (V6_STATS if version >= 6 else [])
					var allowed_ops: Array = ["eq","lte","gte"] if version >= 6 else ["eq","lte"]
					require(star.get("stat") is String and star.get("op") is String and allowed_stats.has(star.stat) and allowed_ops.has(star.op) and numeric(star.get("value"),0,1e9),"stars","stat/op/value가 올바르지 않습니다")
	var combinations: int = 1
	for group: String in GROUPS:
		if not data[group] is Array or data[group].size() > LIMITS[group]:
			reject(group,"개체 배열 크기 제한을 초과했습니다")
			continue
		if group in ["rooms","units"]: require(not data[group].is_empty(),group,"최소 한 개가 필요합니다")
		for i: int in range(data[group].size()):
			var label: String = group+"["+str(i)+"]"
			var required: Array = RECT.duplicate() if group in ["rooms","walls","doors","props"] else ["id","x","z"]
			if group == "doors": required.append("axis")
			if group == "props": required.append("type")
			if group == "units": required.append_array(["name","role","facing","weapon"])
			var raw: Variant = data[group][i]
			var allowed_fields: Array = FIELDS[group] + (["render"] if version >= 2 and group == "walls" else (["base_height"] if version >= 2 and group == "rooms" else []))
			if version >= 3 and group == "doors": allowed_fields += V3_DOOR_FIELDS
			if not shape(raw,allowed_fields,required,label): continue
			var obj: Dictionary = raw
			require(text(obj.id,64) and identifier.search(str(obj.id)) != null and not ids.has(obj.id),label+".id","중복 없는 안전한 ID가 필요합니다")
			ids[str(obj.id)] = true
			point([obj.x,obj.z],label)
			if group in ["rooms","walls","doors","props"]: rectangle(obj,label)
			for field: String in ["facing","rotation","body_facing"]:
				if obj.has(field): require(numeric(obj[field]),label+"."+field,"유한 각도가 필요합니다")
			for field: String in ["solid","thin","secured","target","training","passive","hold_position","locked","destroyed","indoor","opaque","render","reinforced"]:
				if obj.has(field): require(typeof(obj[field]) == TYPE_BOOL,label+"."+field,"불리언이 필요합니다")
			for field: String in ["name","role","label","roster_id"]:
				if obj.has(field): require(text(obj[field]),label+"."+field,"텍스트가 필요합니다")
			if obj.has("trait"): require(obj.trait in ["","breacher","marksman","cautious","rescuer","hold_after_hit"],label+".trait","알 수 없는 고정 특성")
			if obj.has("equipment"): equipment(obj.equipment,label+".equipment")
			if group == "units":
				var gear: Dictionary = {}
				for field: String in EquipmentCatalog.LOADOUT_FIELDS:
					if obj.has(field): gear[field] = obj[field]
				var problem: String = EquipmentCatalog.loadout_error(gear)
				require(problem.is_empty(),label+".loadout",problem)
			for field: String in ["hp","vision_range","fov"]:
				if obj.has(field): require(numeric(obj[field],0.0 if field == "hp" and group == "doors" else 0.1,1000 if field == "hp" else (360 if field == "fov" else 32)),label+"."+field,"유한 가상 수치가 필요합니다")
			for field: String in ["height","base_height","weapon_height"]:
				var height_limit: float = 64.0 if version >= 2 and group in ["rooms","walls","doors","props"] and field != "weapon_height" else 8.0
				if obj.has(field): require(numeric(obj[field],0,height_limit),label+"."+field,"허용 높이는 0–"+str(height_limit)+"m입니다")
			for field: String in ["opacity","lighting","progress","aim_progress","mobility_multiplier","awareness_confidence","exposure"]:
				if obj.has(field): require(numeric(obj[field],0,1),label+"."+field,"유한 0–1 수치가 필요합니다")
			for field: String in ["resistance","durability","penetration_resistance"]:
				if obj.has(field): require(numeric(obj[field],0,1000),label+"."+field,"유한 0–1000 수치가 필요합니다")
			for field: String in ["velocity_x","velocity_z"]:
				if obj.has(field): require(numeric(obj[field],-32,32),label+"."+field,"속도 범위를 벗어났습니다")
			if obj.has("reserve_ammo"): require(integer(obj.reserve_ammo,0,10000),label+".reserve_ammo","예비 탄약은 0–10000 정수여야 합니다")
			if obj.has("action_multiplier"): require(numeric(obj.action_multiplier,1,4),label+".action_multiplier","행동 배율은 1–4이어야 합니다")
			if obj.has("reload_duration"): require(numeric(obj.reload_duration,0,600),label+".reload_duration","재장전 시간이 올바르지 않습니다")
			if obj.has("material"): require(obj.material in MATERIALS,label+".material","알 수 없는 재질")
			if obj.has("floor_surface"): require(obj.floor_surface in SURFACES,label+".floor_surface","알 수 없는 바닥 재질")
			if obj.has("stance"): require(obj.stance in ["standing","crouched"],label+".stance","알 수 없는 자세")
			if obj.has("movement_mode"): require(obj.movement_mode in ["careful","normal","fast"],label+".movement_mode","알 수 없는 이동 방식")
			for field: String in ["injury","injury_status"]:
				if obj.has(field): require(obj[field] in ["none","hurt","wounded"],label+"."+field,"알 수 없는 부상 상태")
			if obj.has("aim_state"): require(obj.aim_state in ["idle","acquiring","ready","lowered"],label+".aim_state","알 수 없는 조준 상태")
			if obj.has("awareness_state"): require(obj.awareness_state in AWARENESS,label+".awareness_state","알 수 없는 인지 상태")
			if obj.has("observation_source"): require(obj.observation_source in SOURCES,label+".observation_source","알 수 없는 관측 출처")
			if obj.has("weapon"): require(obj.weapon in ["standard","light","shotgun","suppressed"],label+".weapon","알 수 없는 무기")
			for field: String in ["ammo","stuns","smokes","charges","breaches","cameras"]:
				var maximum: int = 32 if field == "ammo" else (2 if field == "cameras" else 8)
				if field == "ammo" and group == "units":
					var attachments: Array = obj.get("attachments",[]) if obj.get("attachments",[]) is Array else []
					maximum = maxi(32,int(EquipmentCatalog.weapon_stats(str(obj.get("weapon","standard")),attachments).ammo))
				if obj.has(field): require(integer(obj[field],0,maximum),label+"."+field,"장비 수량이 올바르지 않습니다")
			if group == "props":
				require(COVER.has(obj.type),label+".type","알 수 없는 가구")
				if obj.has("cover"): require(obj.cover in ["none","low","full"],label+".cover","알 수 없는 엄폐 분류")
				if numeric(obj.get("rotation",0)): require(absf(float(obj.get("rotation",0))/(PI/2)-roundf(float(obj.get("rotation",0))/(PI/2))) < 1e-5,label+".rotation","90도 단위 회전이 필요합니다")
			if group == "doors":
				if obj.has("kick_resistance"): require(numeric(obj.kick_resistance,0,1),label+".kick_resistance","문 차기 성공확률은 유한 0–1 수치여야 합니다")
				require(obj.axis in ["x","z"],label+".axis","x 또는 z가 필요합니다")
				if obj.axis in ["x","z"] and numeric(obj.w) and numeric(obj.d): require((float(obj.w) if obj.axis == "x" else float(obj.d)) > maxf(Navigation.RADIUS*2,float(obj.d) if obj.axis == "x" else float(obj.w)),label,"출입구 폭이 너무 좁습니다")
				if obj.has("state"): require(obj.state in ["CLOSED","AJAR","OPEN","DESTROYED"],label+".state","초기 문 상태가 올바르지 않습니다")
				for field: String in ["swing_sign","hinge_side"]:
					if obj.has(field): require(numeric(obj[field]) and absf(float(obj[field])) == 1.0,label+"."+field,"-1 또는 1이 필요합니다")
				if obj.get("state","CLOSED") == "AJAR" and obj.has("progress"): require(numeric(obj.progress,0.001,0.999),label+".progress","부분 개방은 0과 1 사이여야 합니다")
				if obj.has("initial_states"):
					require(obj.initial_states is Array and not obj.initial_states.is_empty() and obj.initial_states.size() <= 3 and obj.initial_states.all(func(state: Variant) -> bool: return state in ["OPEN","CLOSED","AJAR"]),label+".initial_states","초기 문 상태 후보가 올바르지 않습니다")
			if obj.has("patrol"): patrol(obj.patrol,label+".patrol")
			if obj.has("response_role"): require(obj.response_role is String and obj.response_role in ["guard","patrol","reserve"],label+".response_role","알 수 없는 대응 역할")
			if obj.has("strength"): require(obj.strength in ["weak","medium","strong"],label+".strength","적 전투 등급은 weak, medium, strong 중 하나여야 합니다")
			if obj.has("enemy_type"): require(obj.enemy_type in ["normal","sentry","guard","rusher","hostage_taker"],label+".enemy_type","알 수 없는 적 유형")
			if obj.has("spawns"):
				if not obj.spawns is Array or obj.spawns.is_empty() or obj.spawns.size() > 8:
					reject(label+".spawns","1–8개 후보가 필요합니다")
					continue
				combinations *= obj.spawns.size()
				for spawn: Variant in obj.spawns:
					if not shape(spawn,["x","z","facing","patrol"],["x","z","facing"],label+".spawns"): continue
					point([spawn.x,spawn.z],label+".spawns")
					require(numeric(spawn.facing),label+".spawns.facing","유한 각도가 필요합니다")
					patrol(spawn.get("patrol",[]),label+".spawns.patrol")
				var first: Variant = obj.spawns[0]
				if first is Dictionary: require(first.get("x") == obj.x and first.get("z") == obj.z and first.get("facing") == obj.get("facing") and first.get("patrol",[]) == obj.get("patrol",[]),label+".spawns[0]","첫 후보는 기본 배치를 보존해야 합니다")
	require(combinations <= 65536,"spawns","전체 후보 조합은 최대 65536개입니다")
	if not errors.is_empty(): return answer(value)
	for rule: Variant in data.get("win",[])+data.get("fail",[]):
		if rule is Dictionary and rule.get("type") == "rooms_cleared":
			var room_ids: Array = data.rooms.map(func(room: Dictionary) -> String: return str(room.id))
			var targets: Array = rule.get("room_ids",room_ids)
			require(not targets.is_empty(),"rooms_cleared","정리할 방이 하나 이상 필요합니다")
			for room_id: Variant in targets: require(room_ids.has(room_id),"rooms_cleared","존재하지 않는 방 "+str(room_id))
		if not rule is Dictionary or rule.get("type") != "targets_complete" or not rule.get("targets") is Array: continue
		var target_ids: Array = []
		for target: Variant in data.get("interactive_targets",[]):
			if target is Dictionary: target_ids.append(target.get("id"))
		for target_id: Variant in rule.targets: require(target_ids.has(target_id),"targets_complete","존재하지 않는 상호작용 목표 "+str(target_id))
	if not errors.is_empty(): return answer(value)
	var blockers: Array = data.walls.duplicate(true)
	for prop: Dictionary in data.props:
		if prop.get("cover","full" if prop.get("solid",false) else COVER.get(prop.type,"none")) != "none": blockers.append(prop)
	for i: int in range(data.doors.size()):
		var door: Dictionary = data.doors[i]
		for obstacle: Dictionary in blockers: require(not overlap(door,obstacle),str(door.id),"닫힌 출입구가 장애물 "+str(obstacle.id)+"와 겹칩니다")
		for j: int in range(i+1,data.doors.size()): require(not overlap(door,data.doors[j]),str(door.id),"출입구가 겹칩니다")
	if not errors.is_empty(): return answer(value)
	var doors: Array = data.doors.duplicate(true)
	var opened: Array = []
	for door: Dictionary in doors:
		door["state"] = door.get("state","CLOSED")
		if door.state == "DESTROYED":
			door["destroyed"] = true
			door["state"] = "OPEN"
		door["progress"] = 1.0 if door.state == "OPEN" else (float(door.get("progress",0.52)) if door.state == "AJAR" else 0.0)
		opened.append(door.id)
	var nav: RefCounted = Navigation.new()
	nav.build(data,doors)
	var origin := Vector2(float(data.units[0].x),float(data.units[0].z))
	var choices: Array = []
	var challenge: bool = bool(data.get("challenge",str(data.id).ends_with("H")))
	for actor: Dictionary in data.units+data.enemies+data.civilians:
		var options: Array = []
		for spawn: Dictionary in actor.get("spawns",[actor]):
			var placed: Dictionary = actor.duplicate(true)
			for key: String in spawn: placed[key] = spawn[key]
			actor_geometry(nav,placed,opened,origin,str(actor.id),challenge)
			options.append(placed)
		choices.append(options)
	# Since actors are absent from nav obstacles, reachability factors by actor.
	# Checking every cross-pair of candidates proves no full Cartesian member
	# can overlap, without blocking the browser by building 65536 full states.
	for i: int in range(choices.size()):
		for j: int in range(i+1,choices.size()):
			for a: Dictionary in choices[i]:
				for b: Dictionary in choices[j]: require(Vector2(float(a.x),float(a.z)).distance_to(Vector2(float(b.x),float(b.z))) >= Navigation.RADIUS*2,str(a.id)+"/"+str(b.id),"후보 시작 위치가 겹칩니다")
	for room: Dictionary in data.rooms: reachable_zone(nav,[room.x,room.z,room.w,room.d],opened,origin,str(room.id))
	for target: Dictionary in data.get("interactive_targets",[]): reachable_zone(nav,[target.x,target.z,target.w,target.d],opened,origin,str(target.id))
	for door: Dictionary in doors:
		require(not nav.approach(origin,door,0.85,opened).is_empty(),str(door.id),"도달 가능한 문 조작 위치가 없습니다")
		var initial_state: String = str(door.state)
		var initial_progress: float = float(door.progress)
		var initial_sign: float = float(door.get("swing_sign",-1))
		var other_open: Array = opened.duplicate()
		other_open.erase(door.id)
		# Authored hinges only need their fixed opening direction. Legacy files
		# omit it and retain the previous validation of both possible directions.
		for sign: float in ([initial_sign] if door.has("swing_sign") else [-1.0,1.0]):
			door.state = "OPEN"
			door.progress = 1.0
			door.swing_sign = sign
			nav.rebuild()
			require(open_passage(nav,door,other_open),str(door.id),"열린 문짝을 통과하는 경로가 없습니다")
		door.state = initial_state
		door.progress = initial_progress
		door.swing_sign = initial_sign
		nav.rebuild()
	for rule: Dictionary in data.get("win",[]):
		if rule.type in ["reach_zone","escort_to_zone"]: reachable_zone(nav,rule.zone,opened,origin,str(rule.type))
	return answer(value)

func answer(data: Variant) -> Dictionary:
	if errors.is_empty(): return {"ok":true,"message":"","data":data.duplicate(true)}
	return {"ok":false,"message":"\n".join(errors),"errors":errors.duplicate()}
