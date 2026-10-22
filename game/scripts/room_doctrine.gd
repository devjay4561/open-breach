class_name BreachRoomDoctrine
extends RefCounted
## Passive, occurrence-owned room receipts. No RNG, actors or private outcomes
## are serialized: public rows are gated by RoomControl's observed memory.
const DoorGeometry = preload("res://scripts/door_geometry.gd")
const ROWS := ["stealth","doorway_dwell","time_to_dominate","threat_order_violations","identification","control","marked","rear_hits"]
var initialized := false
var _rows: Dictionary = {}
var _known: Dictionary = {}
var _ready: Dictionary = {}
var _actors: Dictionary = {}
var _people: Dictionary = {}
var _damage_occurrences: Dictionary = {}
var _dwell: Dictionary = {}
var _dominated: Dictionary = {}
var _floors: Dictionary = {}
var _last_tick := -1

func reset(mission: Dictionary = {}) -> void:
	initialized = not mission.is_empty()
	_rows.clear()
	_known.clear()
	_ready.clear()
	_actors.clear()
	_people.clear()
	_damage_occurrences.clear()
	_dwell.clear()
	_dominated.clear()
	_floors.clear()
	_last_tick = -1
	for room: Dictionary in mission.get("rooms", []):
		var rows: Dictionary = {}
		for key: String in ROWS: rows[key] = {"value":null,"tick":null,"time":null}
		_rows[str(room.id)] = rows
		_people[str(room.id)] = {}
		_floors[str(room.id)] = float(room.get("base_height",0.0))

func record_stack(context: Dictionary) -> void:
	var room_id := str(context.get("room_id", ""))
	if not _valid_fact(context): return
	var key := str(context.get("sync_id", "")) + JSON.stringify(context.get("command_ids", []))
	if _ready.has(key): return
	_ready[key] = true
	# Unknown enemies are not a zero-alert observation. The first preparation
	# epoch is immutable even if a later sight/contact makes this room known.
	var category := -1
	for enemy: Dictionary in context.get("observed_enemies", []):
		if str(enemy.get("status", "")) in ["INCAPACITATED","ARRESTED","SURRENDERED"]: continue
		var awareness: String = str(enemy.get("awareness_state", "UNAWARE"))
		var value := 0 if awareness == "UNAWARE" else (1 if awareness == "SUSPICIOUS" else 2)
		if bool(enemy.get("door_ready", false)) or str(enemy.get("status", "")) in ["ALERT","REACTING","ENGAGING"]: value = 2
		category = maxi(category, value)
	if category < 0 or _rows[room_id].stealth.value != null: return
	var extra := {"door_id":str(context.get("door_id", ""))}
	var ids: Array = context.get("unit_ids", [])
	if not ids.is_empty(): extra["unit_id"] = str(ids[0])
	_set_row(room_id,"stealth",category,context,extra)

func record_observation(fact: Dictionary) -> void:
	if not _valid_fact(fact): return
	var id := str(fact.get("id", ""))
	var kind := str(fact.get("kind", ""))
	if id.is_empty() or kind not in ["enemy","civilian"]: return
	# First sight never infers injury from private maximum health. A later
	# observed health decrease is newly learned at this discovery tick.
	var health := maxf(0.0,float(fact.get("hp",0.0)))
	if not is_finite(health): return
	var prior: Dictionary = _actors.get(id,{})
	if not prior.is_empty() and int(prior.tick)==int(fact.tick): health = minf(health,float(prior.hp))
	if kind == "civilian" and not prior.is_empty() and health < float(prior.hp):
		_identification_evidence(str(fact.room_id),fact)
		var row: Dictionary = _rows[str(fact.room_id)].identification
		row["civilian_damage"] = float(row.civilian_damage)+float(prior.hp)-health
		if float(row.value)==0.0: _identification_failure(str(fact.room_id),fact)
	_actors[id] = {"kind":kind,"room_id":str(fact.room_id),"hp":health,"tick":int(fact.tick)}
	var people: Dictionary = _people[str(fact.room_id)]
	var person: Dictionary = people.get(id, {"kind":kind,"surrendered":false,"arrested":false,"secured":false})
	person["surrendered"] = bool(person.surrendered) or bool(fact.get("surrendered", false))
	people[id] = person
	if kind == "civilian": _identification_evidence(str(fact.room_id),fact)
	_control_row(str(fact.room_id),fact)

func record_damage(fact: Dictionary) -> void:
	if not _valid_fact(fact) or str(fact.get("kind", "")) != "civilian": return
	var before := maxf(0.0,float(fact.get("before",0.0)))
	var after := maxf(0.0,float(fact.get("after",before)))
	if not is_finite(before) or not is_finite(after): return
	var key := "%s:%d:%s:%s" % [str(fact.get("id","")),int(fact.tick),str(before),str(after)]
	if _damage_occurrences.has(key): return
	_damage_occurrences[key] = true
	# Both endpoints are currently observed by the core. Passing them through
	# the same health ledger keeps a following observation from counting this
	# occurrence again, including a first-ever damage/contact receipt.
	var observed: Dictionary = fact.duplicate(true)
	observed["hp"] = before
	record_observation(observed)
	observed["hp"] = after
	record_observation(observed)

func record_control(fact: Dictionary) -> void:
	if not _valid_fact(fact): return
	var id := str(fact.get("id", ""))
	var action := str(fact.get("action", ""))
	if id.is_empty() or action not in ["arrest","secure"]: return
	var people: Dictionary = _people[str(fact.room_id)]
	var person: Dictionary = people.get(id,{"kind":"enemy" if action == "arrest" else "civilian","surrendered":false,"arrested":false,"secured":false})
	if action == "arrest":
		person["surrendered"] = true
		person["arrested"] = true
	else:
		person["secured"] = true
		_identification_evidence(str(fact.room_id),fact)
	people[id] = person
	_control_row(str(fact.room_id),fact)

func record_unlawful(fact: Dictionary) -> void:
	if not _valid_fact(fact): return
	_identification_evidence(str(fact.room_id),fact)
	var row: Dictionary = _rows[str(fact.room_id)].identification
	row["unlawful_shots"] = int(row.unlawful_shots) + 1
	if float(row.value) == 0.0: _identification_failure(str(fact.room_id),fact)

func record_threat(sim: RefCounted, unit: Dictionary) -> void:
	_counter(sim,unit,"threat_order_violations")

func record_rear_hit(sim: RefCounted, unit: Dictionary) -> void:
	_counter(sim,unit,"rear_hits")

func update(sim: RefCounted, dt: float) -> void:
	if not initialized or int(sim.tick) <= _last_tick: return
	_last_tick = int(sim.tick)
	_known = sim.room_control.snapshot(false).duplicate(true)
	var fact := {"tick":sim.tick,"time":sim.time}
	for room_id: String in _known:
		if not _rows.has(room_id) or _known[room_id].get("observed",false) != true: continue
		var state: Dictionary = _known[room_id]
		var marked := 1 if str(state.get("state","")) == "MARKED" else 0
		if _rows[room_id].marked.value == null or int(_rows[room_id].marked.value) != marked:
			var receipt := {"tick":int(state.get("changed_tick",sim.tick)),"time":float(state.get("changed_at",sim.time))}
			if str(state.get("state","UNKNOWN")) == "UNKNOWN": receipt = fact
			var extra: Dictionary = {"door_id":str(state.door_id)} if marked == 1 and state.has("door_id") else {}
			_set_row(room_id,"marked",marked,receipt,extra)
	var inside: Dictionary = {}
	for unit: Dictionary in sim.units:
		if float(unit.get("hp",0.0)) <= 0.0: continue
		var room_id: String = sim.room_control.room_at(sim._position(unit),float(unit.get("base_height",0.0)))
		if _rows.has(room_id):
			for metric: String in ["doorway_dwell","threat_order_violations","rear_hits"]:
				if _rows[room_id][metric].value == null: _set_row(room_id,metric,0,fact,{"unit_id":str(unit.id)})
		for door: Dictionary in sim.doors:
			if absf(float(door.get("base_height",0.0))-float(unit.get("base_height",0.0)))>0.01 or not DoorGeometry.funnel_rect(door).has_point(sim._position(unit)): continue
			var target_room := _funnel_room(sim,unit,door,room_id)
			if not _rows.has(target_room): continue
			var key := target_room+":"+str(unit.id)
			if inside.has(key): continue # Two overlapping leaves cannot count a STEP twice.
			inside[key] = {"room_id":target_room,"unit_id":str(unit.id),"door_id":str(door.id)}
	_update_dwell(inside,fact,dt)
	for door_id: String in sim.doctrine.time_to_dominate:
		var entry: Dictionary = sim.doctrine.time_to_dominate[door_id]
		if float(entry.get("seconds",-1.0)) < 0.0: continue
		var signature := door_id+":"+str(entry.get("opened_at",0.0))
		if not _dominated.has(signature):
			# Capture membership at completion, before delayed observation or a
			# later MOVE can attribute the unchanged P0 timer to another floor.
			var door: Dictionary = {}
			for candidate: Dictionary in sim.doors:
				if str(candidate.id)==door_id: door=candidate; break
			var arrival: Dictionary = fact
			for evidence: Dictionary in sim.doctrine.evidence:
				if str(evidence.get("type","")) == "DOMINATED" and str(evidence.get("door_id","")) == door_id and absf(float(evidence.get("time",-1.0))-(float(entry.opened_at)+float(entry.seconds)))<0.000001:
					arrival = evidence
					break
			_dominated[signature] = {"room_id":_entry_room(sim,entry,door),"arrival":arrival.duplicate(true),"published":false}
		var completed: Dictionary = _dominated[signature]
		if completed.published or entry.get("observed",false)!=true: continue
		completed["published"] = true
		var target_room: String = str(completed.room_id)
		if not _rows.has(target_room): continue
		if _rows[target_room].time_to_dominate.value == null or float(entry.seconds) > float(_rows[target_room].time_to_dominate.value):
			_set_row(target_room,"time_to_dominate",float(entry.seconds),completed.arrival,{"door_id":door_id})

func _valid_fact(fact: Dictionary) -> bool:
	return _rows.has(str(fact.get("room_id",""))) and fact.has("tick") and fact.has("time") and int(fact.tick)>=0 and is_finite(float(fact.time)) and float(fact.time)>=0.0

func _set_row(room_id: String, metric: String, value: Variant, fact: Dictionary, extra: Dictionary = {}) -> void:
	var row := {"value":value,"tick":int(fact.tick),"time":float(fact.time)}
	row.merge(extra)
	_rows[room_id][metric] = row

func _identification_evidence(room_id: String, fact: Dictionary) -> void:
	if _rows[room_id].identification.value != null: return
	var extra := {"civilian_damage":0.0,"unlawful_shots":0}
	if not str(fact.get("unit_id","")).is_empty(): extra["unit_id"] = str(fact.unit_id)
	_set_row(room_id,"identification",0,fact,extra)

func _identification_failure(room_id: String, fact: Dictionary) -> void:
	var row: Dictionary = _rows[room_id].identification
	row["value"] = 1
	row["tick"] = int(fact.tick)
	row["time"] = float(fact.time)
	if not str(fact.get("unit_id","")).is_empty(): row["unit_id"] = str(fact.unit_id)

func _control_row(room_id: String, fact: Dictionary) -> void:
	var counts := {"arrested":0,"surrendered":0,"secured":0,"civilians":0}
	for person: Dictionary in _people[room_id].values():
		if person.kind == "civilian":
			counts.civilians += 1
			if bool(person.secured): counts.secured += 1
		elif bool(person.surrendered):
			counts.surrendered += 1
			if bool(person.arrested): counts.arrested += 1
	var denominator: int = counts.surrendered + counts.civilians
	if denominator == 0: return
	var previous: Dictionary = _rows[room_id].control
	if previous.get("arrested",-1)==counts.arrested and previous.get("surrendered",-1)==counts.surrendered and previous.get("secured",-1)==counts.secured and previous.get("civilians",-1)==counts.civilians: return
	if not str(fact.get("unit_id","")).is_empty(): counts["unit_id"] = str(fact.unit_id)
	_set_row(room_id,"control",float(counts.arrested+counts.secured)/float(denominator),fact,counts)

func _counter(sim: RefCounted, unit: Dictionary, metric: String) -> void:
	var room_id: String = sim.room_control.room_at(sim._position(unit),float(unit.get("base_height",0.0)))
	if not _rows.has(room_id): return
	var row: Dictionary = _rows[room_id][metric]
	var count := 0 if row.value == null else int(row.value)
	if count == 0: _set_row(room_id,metric,1,{"tick":sim.tick,"time":sim.time},{"unit_id":str(unit.id)})
	else: row["value"] = count+1

func _funnel_room(sim: RefCounted, unit: Dictionary, door: Dictionary, fallback: String) -> String:
	var floor := float(unit.get("base_height",0.0))
	for command: Dictionary in unit.get("commands",[]):
		if str(command.get("state","")) in ["CANCELLED","FAILED"]: continue
		var drill: Dictionary = command.get("args",{}).get("drill",{})
		if str(drill.get("door_id","")) == str(door.id) and _room_on_floor(str(drill.get("room_id","")),floor): return str(drill.room_id)
	var entry: Dictionary = sim.doctrine.time_to_dominate.get(str(door.id),{})
	if entry.has("targets"):
		var target_room := _entry_room(sim,entry,door)
		if not target_room.is_empty(): return target_room
	var old_room := str(entry.get("room_id",""))
	return old_room if _room_on_floor(old_room,floor) else fallback

func _room_on_floor(room_id: String, floor: float) -> bool:
	return _floors.has(room_id) and absf(float(_floors[room_id])-floor)<=0.01

func _entry_room(sim: RefCounted, entry: Dictionary, door: Dictionary) -> String:
	if door.is_empty() or entry.get("participants",[]).is_empty(): return ""
	var selected := ""
	for id: String in entry.participants:
		var participant: Dictionary = {}
		for unit: Dictionary in sim.units:
			if str(unit.id)==id: participant=unit; break
		if participant.is_empty(): return ""
		var floor := float(participant.get("base_height",0.0))
		if absf(floor-float(door.get("base_height",0.0)))>0.01: return ""
		var position: Vector2 = sim._position(participant)
		if entry.has("targets"):
			if not entry.targets.has(id): return ""
			position=sim._point(entry.targets[id])
		var room_id: String = sim.room_control.room_at(position,floor)
		if not _room_on_floor(room_id,floor) or (not selected.is_empty() and selected!=room_id): return ""
		selected=room_id
	return selected

func _update_dwell(inside: Dictionary, fact: Dictionary, dt: float) -> void:
	if dt <= 0.0 or not is_finite(dt): return
	for key: String in inside:
		var current: Dictionary = inside[key]
		var receipt: Dictionary = _dwell.get(key,{"total":0.0,"run":0.0,"last_tick":-2,"start_tick":int(fact.tick),"start_time":float(fact.time),"worst":0.0,"worst_tick":int(fact.tick),"worst_time":float(fact.time),"door_id":str(current.door_id)})
		if int(receipt.last_tick)!=int(fact.tick)-1:
			receipt["run"] = 0.0
			receipt["start_tick"] = int(fact.tick)
			receipt["start_time"] = float(fact.time)
		receipt["total"] = float(receipt.total)+dt
		receipt["run"] = float(receipt.run)+dt
		receipt["last_tick"] = int(fact.tick)
		if float(receipt.run)>float(receipt.worst):
			receipt["worst"] = receipt.run
			receipt["worst_tick"] = receipt.start_tick
			receipt["worst_time"] = receipt.start_time
			receipt["door_id"] = str(current.door_id)
		_dwell[key] = receipt
	var summaries: Dictionary = {}
	for key: String in _dwell:
		var room_id: String = key.get_slice(":",0)
		if not summaries.has(room_id): summaries[room_id] = {"total":0.0,"worst":-1.0,"receipt":{},"unit_id":""}
		var summary: Dictionary = summaries[room_id]
		var receipt: Dictionary = _dwell[key]
		summary["total"] = maxf(float(summary.total),float(receipt.total))
		if float(receipt.worst)>float(summary.worst):
			summary["worst"] = receipt.worst
			summary["receipt"] = receipt
			summary["unit_id"] = key.get_slice(":",1)
	for room_id: String in summaries:
		var summary: Dictionary = summaries[room_id]
		var receipt: Dictionary = summary.receipt
		_set_row(room_id,"doorway_dwell",summary.total,{"tick":receipt.worst_tick,"time":receipt.worst_time},{"unit_id":summary.unit_id,"door_id":receipt.door_id})

func snapshot() -> Dictionary:
	var result: Dictionary = {}
	for id: String in _known:
		if _known[id].get("observed", false) == true and _rows.has(id): result[id] = _rows[id].duplicate(true)
	return result
