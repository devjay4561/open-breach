extends SceneTree
## Formation remains a planning macro over existing commands. Every runtime
## comparison advances a fixed STEP; elapsed wall time never accepts a case.
const Simulation = preload("res://scripts/simulation.gd")
const Navigation = preload("res://scripts/navigation.gd")
const STEP := 1.0 / 30.0
const IDS: Array[String] = ["alpha","bravo","charlie","delta"]

class RecoveryProbe extends "res://scripts/simulation.gd":
	var refreshed_routes: Array = []
	var lane_departures: Array = []
	func _recover_formation_lane_hold(actor: Dictionary, command: Dictionary) -> bool:
		var origin := _position(actor)
		var before_rng: Array = [_rng.state,_hit_region_rng.state,_breach_rng.state,_surrender_rng.state]
		var original: Dictionary = {"id":command.id,"args":command.args.duplicate(true)}
		var answer: bool = super._recover_formation_lane_hold(actor,command)
		if answer:
			lane_departures.append({"tick":tick,"unit_id":str(actor.id),"move_zero":origin==_position(actor),"rng_unchanged":before_rng==[_rng.state,_hit_region_rng.state,_breach_rng.state,_surrender_rng.state],"primitive_unchanged":original=={"id":command.id,"args":command.args.duplicate(true)},"route_clear":_movement_route_clear(actor,command.path),"exact_goal":_point(command.path.back()).distance_to(_point(command.args.target))<0.00001})
		return answer
	func _movement_dynamic_route(actor: Dictionary, target: Vector2) -> Array:
		var stale: bool = not actor.get("_movement_detour",[]).is_empty()
		var answer: Array = super._movement_dynamic_route(actor,target)
		if stale and not answer.is_empty():
			refreshed_routes.append({"tick":tick,"unit_id":str(actor.id),"target":[target.x,target.y],"route":answer.duplicate(true)})
		return answer

# Frozen primitive fixture from the pre-shortest square-valid early return and
# circular fallback selector, reconstructed for one static calculation. This
# is authored test data, independent of the current planner and /tmp files.
const FIXED_ROLLING_PLAN: Array = [
	{"unit_id":"delta","goal":[7.650000095367432,5.0],"hand_ready":[8.0,11.299999237060547],"nodes":[
		{"type":"FACE","args":{"target":[11.576814651489258,10.211592674255371],"persistent":true,"sector":{"start":0.0,"end":0.0,"duration":0.0},"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":1,"stage":"stack","source_unit_id":"charlie"}}},
		{"type":"MOVE","args":{"target":[7.375,11.875],"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":1,"stage":"stack","source_unit_id":"charlie"}}},
		{"type":"MOVE","args":{"target":[7.375,9.875],"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":1,"stage":"stack","source_unit_id":"charlie"}}},
		{"type":"MOVE","args":{"target":[7.650000095367432,9.899999618530273],"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":1,"stage":"stack","source_unit_id":"charlie"}}},
		{"type":"FACE","args":{"target":[11.226814270019531,8.111592292785645],"persistent":true,"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":1,"stage":"ready","source_unit_id":"charlie"}}},
		{"type":"WAIT_FOR_SIGNAL","args":{"signal":"A","sync_id":"formation-refresh:ready","auto_signal":true,"delay_ticks":3,"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":1,"stage":"ready","source_unit_id":"charlie"}}},
		{"type":"FACE","args":{"target":[11.226814270019531,8.111592292785645],"persistent":true,"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":1,"stage":"move","source_unit_id":"charlie"}}},
		{"type":"MOVE","args":{"target":[7.650000095367432,5.0],"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":1,"stage":"move","source_unit_id":"charlie"}}},
		{"type":"FACE","args":{"target":[11.226814270019531,3.21159291267395],"persistent":true,"sector":{"start":-1.4235786627832063,"end":0.4962835144105562,"duration":12.0},"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":1,"stage":"cover","source_unit_id":"charlie"}}}
	]},
	{"unit_id":"bravo","goal":[8.350000381469727,5.0],"hand_ready":[8.0,11.299999237060547],"nodes":[
		{"type":"FACE","args":{"target":[4.423185348510742,10.911592483520508],"persistent":true,"sector":{"start":0.0,"end":0.0,"duration":0.0},"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":2,"stage":"stack","source_unit_id":"charlie"}}},
		{"type":"MOVE","args":{"target":[8.625,12.625],"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":2,"stage":"stack","source_unit_id":"charlie"}}},
		{"type":"MOVE","args":{"target":[8.625,9.875],"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":2,"stage":"stack","source_unit_id":"charlie"}}},
		{"type":"MOVE","args":{"target":[8.350000381469727,9.899999618530273],"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":2,"stage":"stack","source_unit_id":"charlie"}}},
		{"type":"FACE","args":{"target":[4.773185729980469,8.111592292785645],"persistent":true,"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":2,"stage":"ready","source_unit_id":"charlie"}}},
		{"type":"WAIT_FOR_SIGNAL","args":{"signal":"A","sync_id":"formation-refresh:ready","auto_signal":true,"delay_ticks":3,"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":2,"stage":"ready","source_unit_id":"charlie"}}},
		{"type":"FACE","args":{"target":[4.773185729980469,8.111592292785645],"persistent":true,"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":2,"stage":"move","source_unit_id":"charlie"}}},
		{"type":"MOVE","args":{"target":[8.350000381469727,5.0],"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":2,"stage":"move","source_unit_id":"charlie"}}},
		{"type":"FACE","args":{"target":[4.773185729980469,3.211592674255371],"persistent":true,"sector":{"start":2.6453093199773585,"end":-1.7180138100084654,"duration":12.0},"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":2,"stage":"cover","source_unit_id":"charlie"}}}
	]},
	{"unit_id":"alpha","goal":[8.0,5.699999809265137],"hand_ready":[8.0,11.299999237060547],"nodes":[
		{"type":"FACE","args":{"target":[8.0,9.400999069213867],"persistent":true,"sector":{"start":0.0,"end":0.0,"duration":0.0},"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":3,"stage":"stack","source_unit_id":"charlie"}}},
		{"type":"MOVE","args":{"target":[8.625,13.125],"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":3,"stage":"stack","source_unit_id":"charlie"}}},
		{"type":"MOVE","args":{"target":[8.625,10.625],"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":3,"stage":"stack","source_unit_id":"charlie"}}},
		{"type":"MOVE","args":{"target":[8.0,10.59999942779541],"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":3,"stage":"stack","source_unit_id":"charlie"}}},
		{"type":"FACE","args":{"target":[8.0,6.600999355316162],"persistent":true,"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":3,"stage":"ready","source_unit_id":"charlie"}}},
		{"type":"WAIT_FOR_SIGNAL","args":{"signal":"A","sync_id":"formation-refresh:ready","auto_signal":true,"delay_ticks":3,"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":3,"stage":"ready","source_unit_id":"charlie"}}},
		{"type":"FACE","args":{"target":[8.0,6.600999355316162],"persistent":true,"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":3,"stage":"move","source_unit_id":"charlie"}}},
		{"type":"MOVE","args":{"target":[8.0,5.699999809265137],"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":3,"stage":"move","source_unit_id":"charlie"}}},
		{"type":"FACE","args":{"target":[8.0,1.7009997367858887],"persistent":true,"sector":{"start":-2.5307274591031677,"end":-0.6108652819094054,"duration":12.0},"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":3,"stage":"cover","source_unit_id":"charlie"}}}
	]},
	{"unit_id":"charlie","goal":[8.0,6.400000095367432],"hand_ready":[7.999999046325684,7.300999164581299],"nodes":[
		{"type":"FACE","args":{"target":[8.0,18.099000930786133],"persistent":true,"sector":{"start":0.0,"end":0.0,"duration":0.0},"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":4,"stage":"stack","source_unit_id":"charlie"}}},
		{"type":"MOVE","args":{"target":[8.625,13.875],"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":4,"stage":"stack","source_unit_id":"charlie"}}},
		{"type":"MOVE","args":{"target":[8.625,11.375],"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":4,"stage":"stack","source_unit_id":"charlie"}}},
		{"type":"MOVE","args":{"target":[8.0,11.299999237060547],"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":4,"stage":"stack","source_unit_id":"charlie"}}},
		{"type":"FACE","args":{"target":[8.0,15.298999786376953],"persistent":true,"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":4,"stage":"ready","source_unit_id":"charlie"}}},
		{"type":"WAIT_FOR_SIGNAL","args":{"signal":"A","sync_id":"formation-refresh:ready","auto_signal":true,"delay_ticks":3,"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":4,"stage":"ready","source_unit_id":"charlie"}}},
		{"type":"FACE","args":{"target":[8.0,15.298999786376953],"persistent":true,"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":4,"stage":"move","source_unit_id":"charlie"}}},
		{"type":"MOVE","args":{"target":[8.0,6.400000095367432],"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":4,"stage":"move","source_unit_id":"charlie"}}},
		{"type":"FACE","args":{"target":[8.0,10.39900016784668],"persistent":true,"sector":{"start":0.6108652819094054,"end":2.5307274591031677,"duration":12.0},"formation":{"sync_id":"formation-refresh","kind":"ROLLING_T","order":4,"stage":"cover","source_unit_id":"charlie"}}}
	]}
]

# Complete mission and public primitive arguments captured from the original
# side-patrol run. The real NPC, normal loadouts and owned starting positions
# remain authored inputs; no private hold, detour or combat state is injected.
const FIXED_SIDE_DATA := '''
{"mission":{"bounds":[16,16],"civilians":[],"doors":[{"axis":"z","d":1.8,"hinge_side":-1.0,"id":"d2","material":"wood","state":"OPEN","swing_sign":-1.0,"w":0.2,"x":10.0,"z":7.0}],"enemies":[{"enemy_type":"normal","facing":0.0,"id":"e2","movement_mode":"normal","name":"무장 인원","patrol":[[10.35,7.0],[10.35,6.4],[11.7,6.4],[11.7,8.2]],"reserve_ammo":72.0,"response_role":"patrol","stance":"standing","x":8.0,"z":7.0}],"fail":[],"id":"P4_SIDE_PATROL","props":[],"rooms":[{"d":14.0,"floor_surface":"wood","id":"corridor","w":4.0,"x":12.0,"z":8.0},{"d":4.0,"floor_surface":"wood","id":"side","w":5.0,"x":7.5,"z":7.0}],"seed":0,"units":[{"facing":-1.5707963267949,"id":"alpha","movement_mode":"normal","name":"ALPHA","reserve_ammo":72.0,"role":"선봉","stance":"standing","weapon":"standard","x":11.4,"z":13.6},{"facing":-1.5707963267949,"id":"bravo","movement_mode":"normal","name":"BRAVO","reserve_ammo":72.0,"role":"지원","stance":"standing","weapon":"standard","x":12.1,"z":13.6},{"facing":-1.5707963267949,"id":"charlie","movement_mode":"normal","name":"CHARLIE","reserve_ammo":96.0,"role":"돌입","stance":"standing","weapon":"light","x":12.8,"z":13.6},{"facing":-1.5707963267949,"id":"delta","movement_mode":"normal","name":"DELTA","reserve_ammo":96.0,"role":"엄호","stance":"standing","weapon":"light","x":13.5,"z":13.6}],"variant":"normal","walls":[{"d":5.1,"id":"west_north","w":0.2,"x":10.0,"z":3.55},{"d":7.1,"id":"west_south","w":0.2,"x":10.0,"z":11.45},{"d":14.0,"id":"east","w":0.2,"x":14.0,"z":8.0},{"d":0.2,"id":"side_north","w":5.0,"x":7.5,"z":5.0},{"d":0.2,"id":"side_south","w":5.0,"x":7.5,"z":9.0},{"d":4.0,"id":"side_west","w":0.2,"x":5.0,"z":7.0},{"d":8.2,"id":"screen","w":0.2,"x":10.8,"z":10.9}],"win":[{"type":"reach_zone","zone":[15.5,15.5,0.1,0.1]}]},"plan":[{"unit_id":"alpha","nodes":[{"type":"FACE","args":{"formation":{"kind":"ROLLING_T","order":1,"source_unit_id":"delta","stage":"stack","sync_id":"formation-0001"},"persistent":true,"sector":{"duration":0.0,"end":0.0,"start":0.0},"target":[15.0705099105835,12.012752532959]}},{"type":"MOVE","args":{"formation":{"kind":"ROLLING_T","order":1,"source_unit_id":"delta","stage":"stack","sync_id":"formation-0001"},"target":[11.7717304229736,11.4672594070435]}},{"type":"MOVE","args":{"formation":{"kind":"ROLLING_T","order":1,"source_unit_id":"delta","stage":"stack","sync_id":"formation-0001"},"target":[11.8853616714478,11.1731863021851]}},{"type":"FACE","args":{"formation":{"kind":"ROLLING_T","order":1,"source_unit_id":"delta","stage":"ready","sync_id":"formation-0001"},"persistent":true,"target":[15.555871963501,9.58593940734863]}},{"type":"WAIT_FOR_SIGNAL","args":{"auto_signal":true,"delay_ticks":0,"formation":{"kind":"ROLLING_T","order":1,"source_unit_id":"delta","stage":"ready","sync_id":"formation-0001"},"signal":"A","sync_id":"formation-0001:ready"}},{"type":"FACE","args":{"formation":{"kind":"ROLLING_T","order":1,"source_unit_id":"delta","stage":"move","sync_id":"formation-0001"},"persistent":true,"target":[15.4107570648193,9.28543949127197]}},{"type":"MOVE","args":{"formation":{"kind":"ROLLING_T","order":1,"source_unit_id":"delta","stage":"move","sync_id":"formation-0001"},"target":[11.650538444519,2.78058552742004]}},{"type":"FACE","args":{"formation":{"kind":"ROLLING_T","order":1,"source_unit_id":"delta","stage":"cover","sync_id":"formation-0001"},"persistent":true,"sector":{"duration":12.0,"end":0.551782084614337,"start":-1.36808009257943},"target":[15.3210487365723,1.19333815574646]}}]},{"unit_id":"bravo","nodes":[{"type":"FACE","args":{"formation":{"kind":"ROLLING_T","order":2,"source_unit_id":"delta","stage":"stack","sync_id":"formation-0001"},"persistent":true,"sector":{"duration":0.0,"end":0.0,"start":0.0},"target":[8.62789630889893,11.6159400939941]}},{"type":"MOVE","args":{"formation":{"kind":"ROLLING_T","order":2,"source_unit_id":"delta","stage":"stack","sync_id":"formation-0001"},"target":[12.5814294815063,13.0147094726562]}},{"type":"MOVE","args":{"formation":{"kind":"ROLLING_T","order":2,"source_unit_id":"delta","stage":"stack","sync_id":"formation-0001"},"target":[12.795994758606,11.8915233612061]}},{"type":"MOVE","args":{"formation":{"kind":"ROLLING_T","order":2,"source_unit_id":"delta","stage":"stack","sync_id":"formation-0001"},"target":[12.5842847824097,11.2120161056519]}},{"type":"FACE","args":{"formation":{"kind":"ROLLING_T","order":2,"source_unit_id":"delta","stage":"ready","sync_id":"formation-0001"},"persistent":true,"target":[9.11218070983887,9.22795677185059]}},{"type":"WAIT_FOR_SIGNAL","args":{"auto_signal":true,"delay_ticks":0,"formation":{"kind":"ROLLING_T","order":2,"source_unit_id":"delta","stage":"ready","sync_id":"formation-0001"},"signal":"A","sync_id":"formation-0001:ready"}},{"type":"FACE","args":{"formation":{"kind":"ROLLING_T","order":2,"source_unit_id":"delta","stage":"move","sync_id":"formation-0001"},"persistent":true,"target":[8.95884990692139,9.52434730529785]}},{"type":"MOVE","args":{"formation":{"kind":"ROLLING_T","order":2,"source_unit_id":"delta","stage":"move","sync_id":"formation-0001"},"target":[12.349461555481,2.81941437721252]}},{"type":"FACE","args":{"formation":{"kind":"ROLLING_T","order":2,"source_unit_id":"delta","stage":"cover","sync_id":"formation-0001"},"persistent":true,"sector":{"duration":12.0,"end":-1.66251544842094,"start":2.70080768156488},"target":[8.87735748291016,0.835354566574097]}}]},{"unit_id":"charlie","nodes":[{"type":"FACE","args":{"formation":{"kind":"ROLLING_T","order":3,"source_unit_id":"delta","stage":"stack","sync_id":"formation-0001"},"persistent":true,"sector":{"duration":0.0,"end":0.0,"start":0.0},"target":[13.021824836731,9.60715770721436]}},{"type":"MOVE","args":{"formation":{"kind":"ROLLING_T","order":3,"source_unit_id":"delta","stage":"stack","sync_id":"formation-0001"},"target":[12.5814294815063,12.1661815643311]}},{"type":"MOVE","args":{"formation":{"kind":"ROLLING_T","order":3,"source_unit_id":"delta","stage":"stack","sync_id":"formation-0001"},"target":[12.1959943771362,11.8915233612061]}},{"type":"FACE","args":{"formation":{"kind":"ROLLING_T","order":3,"source_unit_id":"delta","stage":"ready","sync_id":"formation-0001"},"persistent":true,"target":[12.4178190231323,7.89868068695068]}},{"type":"WAIT_FOR_SIGNAL","args":{"auto_signal":true,"delay_ticks":0,"formation":{"kind":"ROLLING_T","order":3,"source_unit_id":"delta","stage":"ready","sync_id":"formation-0001"},"signal":"A","sync_id":"formation-0001:ready"}},{"type":"FACE","args":{"formation":{"kind":"ROLLING_T","order":3,"source_unit_id":"delta","stage":"move","sync_id":"formation-0001"},"persistent":true,"target":[12.0841464996338,7.89408779144287]}},{"type":"MOVE","args":{"formation":{"kind":"ROLLING_T","order":3,"source_unit_id":"delta","stage":"move","sync_id":"formation-0001"},"target":[11.9611711502075,3.49892210960388]}},{"type":"FACE","args":{"formation":{"kind":"ROLLING_T","order":3,"source_unit_id":"delta","stage":"cover","sync_id":"formation-0001"},"persistent":true,"sector":{"duration":12.0,"end":-0.555366681903302,"start":-2.47522885909706},"target":[12.1555004119873,0.00099849700927734]}}]},{"unit_id":"delta","nodes":[{"type":"FACE","args":{"formation":{"kind":"ROLLING_T","order":4,"source_unit_id":"delta","stage":"stack","sync_id":"formation-0001"},"persistent":true,"sector":{"duration":0.0,"end":0.0,"start":0.0},"target":[13.3667221069336,15.9990015029907]}},{"type":"MOVE","args":{"formation":{"kind":"ROLLING_T","order":4,"source_unit_id":"delta","stage":"stack","sync_id":"formation-0001"},"target":[13.2242641448975,13.1757364273071]}},{"type":"MOVE","args":{"formation":{"kind":"ROLLING_T","order":4,"source_unit_id":"delta","stage":"stack","sync_id":"formation-0001"},"target":[12.1571655273438,12.5904455184937]}},{"type":"FACE","args":{"formation":{"kind":"ROLLING_T","order":4,"source_unit_id":"delta","stage":"ready","sync_id":"formation-0001"},"persistent":true,"target":[11.9678010940552,15.9990015029907]}},{"type":"WAIT_FOR_SIGNAL","args":{"auto_signal":true,"delay_ticks":0,"formation":{"kind":"ROLLING_T","order":4,"source_unit_id":"delta","stage":"ready","sync_id":"formation-0001"},"signal":"A","sync_id":"formation-0001:ready"}},{"type":"FACE","args":{"formation":{"kind":"ROLLING_T","order":4,"source_unit_id":"delta","stage":"move","sync_id":"formation-0001"},"persistent":true,"target":[12.2525358200073,15.9990005493164]}},{"type":"MOVE","args":{"formation":{"kind":"ROLLING_T","order":4,"source_unit_id":"delta","stage":"move","sync_id":"formation-0001"},"target":[11.922342300415,4.19784450531006]}},{"type":"FACE","args":{"formation":{"kind":"ROLLING_T","order":4,"source_unit_id":"delta","stage":"cover","sync_id":"formation-0001"},"persistent":true,"sector":{"duration":12.0,"end":2.58622593989998,"start":0.666363762706219},"target":[11.7005176544189,8.19068717956543]}}]}]}
'''

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func position(actor: Dictionary) -> Vector2:
	return Vector2(float(actor.x),float(actor.z))

func fixture(seed_value: int = 0, count: int = 4, width: float = 3.2) -> Dictionary:
	var data := {"id":"FORMATION_CORE","schema_version":5,"seed":seed_value,"noise_discipline":"verbal","bounds":[20.0,24.0],
		"rooms":[{"id":"corridor","x":8.0,"z":12.0,"w":width,"d":20.0}],
		"walls":[{"id":"west","x":8.0-width*0.5-0.1,"z":12.0,"w":0.2,"d":20.0},
			{"id":"east","x":8.0+width*0.5+0.1,"z":12.0,"w":0.2,"d":20.0},
			{"id":"north","x":8.0,"z":2.0,"w":width,"d":0.2},{"id":"south","x":8.0,"z":22.0,"w":width,"d":0.2}],
		"props":[],"doors":[],"units":[],"enemies":[],"civilians":[],"fail":[],
		"win":[{"type":"reach_zone","zone":[19.0,1.0,0.1,0.1]}]}
	for index: int in range(count): data.units.append({"id":IDS[index],"x":8.0,"z":14.0+float(index)*0.7,"facing":-1.57,"ammo":0,"reserve_ammo":0})
	return data

func make(data: Dictionary) -> RefCounted:
	var sim := Simulation.new()
	sim.load_mission(data.duplicate(true))
	return sim

func rngs(sim: RefCounted) -> Array:
	return [sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state]

func fingerprint(sim: RefCounted) -> String:
	return JSON.stringify({"state":sim.snapshot(true),"units":sim.units,"doors":sim.doors,"commands":sim._command_sequence,
		"drills":sim._drill_sequence,"requests":sim._requests,"dirty":sim._preview_dirty_units,"depth":sim._preview_batch_depth,
		"reservations":sim._reservations,"barriers":sim._flash_door_barriers,"sync_waits":sim._sync_waits,
		"sync_requests":sim._sync_requests,"sync_sources":sim._sync_sources,"sync_members":sim._sync_members,"rng":rngs(sim)})

func accepted(sim: RefCounted, id: String, type: String, args: Dictionary, append: bool = true) -> Dictionary:
	var answer: Dictionary = sim.issue(id,type,args,append)
	check(bool(answer.get("ok",false)),"Public "+type+" accepted: "+str(answer))
	return answer

func _draft_and_transaction_contracts() -> void:
	var sim := make(fixture())
	sim.configure_unit("alpha",{"stance":"crouched"})
	var before := fingerprint(sim)
	var draft: Dictionary = sim.formation_preview([8.0,10.0],"AUTO",IDS,{})
	check(bool(draft.get("ok",false)) and draft.kind=="ROLLING_T","Wide physical corridor resolves AUTO to rolling T")
	check(fingerprint(sim)==before,"Preview preserves full authority, commands, private requests and all RNG streams")
	if not bool(draft.get("ok",false)): return
	check(draft.slots[0].stance=="crouched" and draft.noise_discipline=="verbal","Public draft retains each owned posture and authored noise policy")
	var planned: Dictionary = sim.plan_formation([8.0,10.0],"AUTO",["delta","bravo","alpha","charlie"],{})
	check(bool(planned.get("ok",false)),"Shuffled tactical order expands atomically")
	if not bool(planned.get("ok",false)): return
	check(rngs(sim)==rngs(make(fixture())),"Planning consumes no AI, hit, breach or surrender random values")
	var last_id := 0
	for unit: Dictionary in sim.units:
		for command: Dictionary in unit.commands:
			check(command.type in ["MOVE","FACE","WAIT_FOR_SIGNAL"] and Simulation.COMMANDS.has(str(command.type)),"Only existing primitives are persisted")
			var metadata: Dictionary = command.args.formation
			check(metadata.keys().size()==5 and metadata.sync_id==planned.sync_id and metadata.kind=="ROLLING_T" and metadata.source_unit_id=="charlie","Every primitive has independent exact five-field metadata")
			check(int(metadata.order)==["delta","bravo","alpha","charlie"].find(str(unit.id))+1,"Tactical order remains distinct from canonical roster issuance")
			check(not command.args.has("drill") and not command.args.has("stance"),"Corridor primitive preserves future operator stance changes")
			var sequence := int(str(command.id).get_slice("-",1))
			check(sequence>last_id,"Command IDs are issued in canonical mission roster order")
			last_id = sequence
		check(unit.commands[0].type=="FACE" and unit.commands[0].args.persistent and unit.commands[1].type=="MOVE","Initial role FACE executes before any stack movement")
		check(unit.commands[0].args.sector=={"start":0.0,"end":0.0,"duration":0.0},"Initial role FACE explicitly clears the prior assignment through the existing sector primitive")
	var crowded := make(fixture())
	for index: int in range(30): accepted(crowded,"alpha","WAIT",{"duration":0.0})
	before = fingerprint(crowded)
	var rejected: Dictionary = crowded.plan_formation([8.0,10.0],"AUTO",IDS,{})
	check(not bool(rejected.get("ok",false)) and rejected.message_key=="formation.error.capacity","Whole prospective queue enforces 32 unfinished primitives per actor")
	check(fingerprint(crowded)==before,"Capacity rejection restores every participant and private counter exactly")
	for invalid: Dictionary in [{"target":[NAN,10.0],"kind":"AUTO","order":IDS,"options":{}},
		{"target":[8.0,10.0],"kind":"INVALID","order":IDS,"options":{}},
		{"target":[8.0,10.0],"kind":"AUTO","order":["alpha","alpha"],"options":{}},
		{"target":[8.0,10.0],"kind":"T_JUNCTION","order":IDS.slice(0,3),"options":{}},
		{"target":[8.0,10.0],"kind":"AUTO","order":IDS,"options":{"kind":"SERPENTINE"}},
		{"target":[8.0,10.0],"kind":"AUTO","order":IDS,"options":{"delay_ticks":0.5}}]:
		before = fingerprint(sim)
		rejected = sim.plan_formation(invalid.target,invalid.kind,invalid.order,invalid.options)
		check(not bool(rejected.get("ok",false)) and str(rejected.message_key).begins_with("formation.error."),"Malformed macro returns a stable translated error")
		check(fingerprint(sim)==before,"Malformed macro does not partially cancel or append another operator's plan")
	accepted(sim,"alpha","WAIT",{"duration":0.1},false)
	sim.step(STEP)
	before = fingerprint(sim)
	rejected = sim.plan_formation([8.0,10.0],"AUTO",IDS,{"append":false})
	check(not bool(rejected.get("ok",false)) and rejected.message_key=="formation.error.active" and fingerprint(sim)==before,"Active actor replacement is rejected without mutating its command or team")

func _known_geometry_contracts() -> void:
	var data := fixture()
	data.doors = [{"id":"known","x":8.0,"z":11.0,"w":1.8,"d":0.24,"axis":"x","state":"CLOSED"},
		{"id":"hidden","x":18.0,"z":3.0,"w":1.8,"d":0.24,"axis":"x","state":"CLOSED"}]
	var sim := make(data)
	# This is a knowledge projection test, not an artificial runtime contact:
	# fixture evidence identifies one portal; live hidden transforms are varied.
	sim._door_observations = {"known":{"state":"OPEN","progress":1.0,"destroyed":false,"hp":35.0,"locked":false,"hinge_side":1.0,"swing_sign":1.0}}
	var geometry: Dictionary = sim._formation_geometry()
	check(geometry.doors[0].state=="OPEN" and geometry.doors[0].progress==1.0,"Every actually known route portal uses its last observed physical pose")
	sim.doors[1].state = "OPEN"
	sim.doors[1].progress = 1.0
	sim.doors[1].destroyed = true
	check(JSON.stringify(sim._formation_geometry())==JSON.stringify(geometry),"Hidden current portal changes cannot alter the static draft")
	geometry.doors[0].state = "CLOSED"
	check(sim._door_observations.known.state=="OPEN" and data.doors[0].state=="CLOSED","Returned geometry owns its nested door rows")

func _primitive_edit_contracts() -> void:
	var sim := make(fixture())
	var answer := accepted(sim,"alpha","FACE",{"target":[8.0,10.0],"persistent":true,"stance":"crouched"})
	check(sim.units[0].stance=="standing","Queued FACE posture does not immediately change the operator")
	sim.step(STEP)
	check(sim.units[0].stance=="crouched" and sim.units[0].commands[0].state=="SUCCEEDED","Posture applies at the actual FACE execution tick")
	var before := fingerprint(sim)
	check(not bool(sim.issue("alpha","FACE",{"unlock":true,"stance":"standing"}).get("ok",false)) and fingerprint(sim)==before,"Unlock plus stance remains an invalid immutable edit")
	check(not bool(sim.issue("alpha","FACE",{"target":[8.0,10.0],"stance":"prone"}).get("ok",false)) and fingerprint(sim)==before,"Unsupported posture cannot create a primitive")
	var meta := {"sync_id":"formation-edit","kind":"SERPENTINE","order":1,"stage":"move","source_unit_id":"delta"}
	accepted(sim,"alpha","MOVE",{"target":[8.0,13.0],"formation":meta})
	check(bool(sim.update_command_args("alpha",1,{"target":[8.0,12.0],"formation":meta}).get("ok",false)),"An expanded formation waypoint remains individually editable")
	check(bool(sim.update_command_args("alpha",1,{"target":[8.0,11.9]}).get("ok",false)) and sim.units[0].commands[1].args.formation==meta,"Native target-only waypoint dragging retains the original formation cohort metadata")
	before = fingerprint(sim)
	check(not bool(sim.update_command_args("alpha",1,{"target":[8.0,11.9],"formation":null}).get("ok",false)) and fingerprint(sim)==before,"Explicit invalid formation metadata is rejected without changing the drag target or private planning state")
	var malformed := meta.duplicate(true)
	malformed["unknown"] = true
	check(not bool(sim.update_command_args("alpha",1,{"target":[8.0,12.0],"formation":malformed}).get("ok",false)) and fingerprint(sim)==before,"Unknown formation metadata is rejected atomically")
	malformed = meta.duplicate(true)
	malformed["order"] = 1.5
	check(not bool(sim.insert_command("bravo",0,"FACE",{"target":[8.0,10.0],"formation":malformed}).get("ok",false)) and fingerprint(sim)==before,"Inserted primitive cannot add a fractional tactical rank")
	var old_sector := make(fixture())
	accepted(old_sector,"alpha","FACE",{"target":[8.0,10.0],"sector":{"start":0.1,"end":0.5,"duration":12.0}})
	old_sector.step(STEP)
	check(not old_sector.units[0].sector.is_empty(),"A previous real FACE assigns a still-active sector")
	var formation: Dictionary = old_sector.plan_formation([8.0,10.0],"AUTO",IDS,{})
	check(bool(formation.get("ok",false)),"Formation can follow an already-finished sector assignment")
	old_sector.step(STEP)
	check(old_sector.units[0].sector.is_empty(),"First formation FACE clears the old sector at execution, without changing ordinary FACE")

func _runtime_contracts() -> void:
	for mode: String in ["verbal","hand_signals"]:
		for count: int in range(2,5):
			var data := fixture(17,count)
			data.noise_discipline = mode
			var sim := make(data)
			var ids: Array = IDS.slice(0,count)
			var planned: Dictionary = sim.plan_formation([8.0,10.0],"AUTO",ids,{})
			check(bool(planned.get("ok",false)),"Actual %s team%d draft accepted"%[mode,count])
			if not bool(planned.get("ok",false)): continue
			var safe := true
			var fixed_budget := true
			for frame: int in range(300):
				var previous: Array = sim.units.map(func(unit: Dictionary)->Vector2:return position(unit))
				sim.step(STEP)
				for index: int in range(count):
					var unit: Dictionary = sim.units[index]
					fixed_budget = fixed_budget and previous[index].distance_to(position(unit))<=0.121
					safe = safe and sim.nav.segment_clear(previous[index],position(unit),Navigation.RADIUS)
					for other: int in range(index): safe = safe and position(unit).distance_to(position(sim.units[other]))>=sim._movement_body_spacing()-0.000001
			check(safe and fixed_budget,"Actual formation retains swept geometry, body spacing and one STEP movement budget")
			check(sim.units.all(func(unit: Dictionary)->bool:return unit.commands.all(func(command: Dictionary)->bool:return command.state=="SUCCEEDED")),"Every actual formation primitive completes without a timer shortcut")
			check(sim.command_failures==0 and sim.units.all(func(unit: Dictionary)->bool:return unit.facing_persistent),"Final role-facing cover is retained after real movement")
			var signals: Array = sim.events.filter(func(event: Dictionary)->bool:return event.type=="SIGNAL")
			check(signals.size()==1 and int(signals[0].released)==count and signals[0].receiver_unit_ids.size()==count,"One whole-cohort ready signal releases the actual commands")
			if not signals.is_empty(): check(signals[0].signal_mode==mode and float(signals[0].signal_radius)==(6.0 if mode=="verbal" else 0.0),"Signal provenance carries actual acoustic policy")

func _junction_contracts() -> void:
	var data := fixture(2)
	data.rooms = [{"id":"stem","x":8.0,"z":15.1,"w":2.4,"d":13.8},{"id":"branches","x":8.0,"z":7.0,"w":12.0,"d":2.4}]
	data.walls = [{"id":"forward","x":8.0,"z":5.7,"w":12.0,"d":0.2},
		{"id":"west_end","x":1.9,"z":7.0,"w":0.2,"d":2.6},{"id":"east_end","x":14.1,"z":7.0,"w":0.2,"d":2.6},
		{"id":"west_bottom","x":4.4,"z":8.3,"w":4.8,"d":0.2},{"id":"east_bottom","x":11.6,"z":8.3,"w":4.8,"d":0.2},
		{"id":"stem_west","x":6.7,"z":15.1,"w":0.2,"d":13.8},{"id":"stem_east","x":9.3,"z":15.1,"w":0.2,"d":13.8},
		{"id":"south","x":8.0,"z":22.0,"w":2.4,"d":0.2}]
	var order: Array = ["delta","bravo","alpha","charlie"]
	for unit: Dictionary in data.units: unit.z = 12.0+float(order.find(str(unit.id)))*0.7
	for mode: String in ["verbal","hand_signals"]:
		data.noise_discipline = mode
		var sim := make(data)
		var planned: Dictionary = sim.plan_formation([8.0,7.0],"T_JUNCTION",order,{"signal":"B","delay_ticks":3})
		check(bool(planned.get("ok",false)),"Physical T accepts four prescribed roles in "+mode)
		if not bool(planned.get("ok",false)): continue
		check(sim.units.all(func(unit: Dictionary)->bool:return unit.stance=="standing"),"T posture stays unchanged until each actual ready FACE")
		var pressed := false
		var physical := true
		var ready_tick := -1
		for frame: int in range(600):
			var prior: Array = sim.units.map(func(unit: Dictionary)->Vector2:return position(unit))
			sim.step(STEP)
			for index: int in range(4):
				physical = physical and sim.nav.segment_clear(prior[index],position(sim.units[index]),Navigation.RADIUS) and prior[index].distance_to(position(sim.units[index]))<=0.121
				for other: int in range(index): physical = physical and position(sim.units[index]).distance_to(position(sim.units[other]))>=sim._movement_body_spacing()-0.000001
			if not pressed and sim.units.all(func(unit: Dictionary)->bool:return sim._active(unit).get("type","")=="WAIT_FOR_SIGNAL" and sim._active(unit).get("state","")=="WAITING"):
				ready_tick = sim.tick
				for unit: Dictionary in sim.units:
					var rank := order.find(str(unit.id))+1
					check(unit.stance==("crouched" if rank in [1,3] else "standing"),"Actual T ready FACE applies low/high posture before the single signal")
				check(bool(sim.release_signal("B").get("ok",false)),"One real manual gesture latches the T group delay")
				pressed = true
		check(pressed and ready_tick>0 and physical,"T setup reaches real shared readiness with continuous body/leaf-safe movement")
		check(sim.units.all(func(unit: Dictionary)->bool:return unit.commands.all(func(command: Dictionary)->bool:return command.state=="SUCCEEDED")),"Reciprocal T detours recover and all original slot primitives actually complete")
		for slot: Dictionary in planned.slots:
			var unit: Dictionary = sim._find(sim.units,str(slot.unit_id))
			check(position(unit).distance_to(Vector2(float(slot.target[0]),float(slot.target[1])))<=0.1,"T final slot is preserved instead of silently choosing a nearby free destination")
		var signals: Array = sim.events.filter(func(event: Dictionary)->bool:return event.type=="SIGNAL")
		check(signals.size()==1 and int(signals[0].released)==4 and signals[0].source_unit_id=="charlie" and int(signals[0].tick)>=ready_tick+3,"T uses one delayed four-member receipt from the actual rear source")

func _delay_occurrence_contracts() -> void:
	var sim := make(fixture(0,2))
	for id: String in IDS.slice(0,2): accepted(sim,id,"WAIT_FOR_SIGNAL",{"signal":"A","sync_id":"reused:ready","auto_signal":true,"delay_ticks":8})
	for _frame: int in range(2): sim.step(STEP)
	check(sim.units.all(func(unit: Dictionary)->bool:return unit.commands[0].state=="WAITING"),"The original ready occurrence has an unfinished positive delay")
	for id: String in IDS.slice(0,2):
		sim.remove_command(id,0)
		sim.remove_command(id,0)
	sim.step(STEP)
	for id: String in IDS.slice(0,2): accepted(sim,id,"WAIT_FOR_SIGNAL",{"signal":"A","sync_id":"reused:ready","auto_signal":true,"delay_ticks":8})
	sim.step(STEP)
	var ready_tick: int = sim.tick
	var release_tick := -1
	for _frame: int in range(10):
		sim.step(STEP)
		if sim.units[0].commands[0].state=="SUCCEEDED": release_tick = sim.tick; break
	check(release_tick==ready_tick+8,"A reused sync ID starts a fresh delay at the new actual command cohort's ready tick")

func _occupied_detour_contracts() -> void:
	# Keep the old selected waypoints as public primitive input: the improved
	# planner now avoids this congestion before runtime. Original normal owned
	# starting positions, goals and actual occupied-lane recovery stay fixed;
	# no private detour, actor pose, hit, aim or random state is supplied.
	var data := fixture(1)
	var order: Array = ["delta","bravo","alpha","charlie"]
	data.bounds = [20.0,20.0]
	data.rooms = [{"id":"corridor","x":8.0,"z":10.0,"w":3.2,"d":16.0}]
	data.walls = [{"id":"west","x":6.3,"z":10.0,"w":0.2,"d":16.0},
		{"id":"east_top","x":9.7,"z":5.65,"w":0.2,"d":7.3},{"id":"east_bottom","x":9.7,"z":14.35,"w":0.2,"d":7.3},
		{"id":"north","x":8.0,"z":2.0,"w":3.2,"d":0.2},{"id":"south","x":8.0,"z":18.0,"w":3.2,"d":0.2}]
	data.doors = [{"id":"side","x":9.7,"z":10.0,"w":0.24,"d":1.4,"axis":"z","state":"CLOSED","locked":false}]
	for unit: Dictionary in data.units: unit.z = 12.0+float(order.find(str(unit.id)))*0.7
	for mode: String in ["verbal","hand_signals"]:
		data.noise_discipline = mode
		var sim := RecoveryProbe.new()
		sim.load_mission(data.duplicate(true))
		var planned: Dictionary = {"slots":FIXED_ROLLING_PLAN.map(func(row: Dictionary)->Dictionary:return {"unit_id":row.unit_id,"target":row.goal})}
		var accepted_plan := true
		for unit: Dictionary in sim.units:
			for row: Dictionary in FIXED_ROLLING_PLAN:
				if row.unit_id!=unit.id: continue
				for node: Dictionary in row.nodes:
					var args: Dictionary = node.args.duplicate(true)
					if mode=="hand_signals" and node.type=="FACE" and args.formation.stage=="ready": args.target = row.hand_ready.duplicate()
					accepted_plan = bool(sim.issue(str(unit.id),str(node.type),args).get("ok",false)) and accepted_plan
		check(accepted_plan,"Occupied rolling-T authored primitives are accepted through public issue in "+mode)
		if not accepted_plan: continue
		var original_args: Array = sim.units.map(func(unit: Dictionary)->Array:return unit.commands.map(func(command: Dictionary)->Dictionary:return {"id":command.id,"args":command.args.duplicate(true)}))
		var physical := true
		for _frame: int in range(600):
			var prior: Array = sim.units.map(func(unit: Dictionary)->Vector2:return position(unit))
			sim.step(STEP)
			for index: int in range(4):
				physical = physical and sim.nav.segment_clear(prior[index],position(sim.units[index]),Navigation.RADIUS) and prior[index].distance_to(position(sim.units[index]))<=0.121
				for other: int in range(index): physical = physical and position(sim.units[index]).distance_to(position(sim.units[other]))>=sim._movement_body_spacing()-0.000001
		check(not sim.refreshed_routes.is_empty(),"Actual occupied temporary lanes exercise bounded route refresh")
		check(physical and sim.command_failures==0,"Refreshing an occupied detour preserves swept body/leaf clearance and the fixed movement budget")
		check(sim.units.all(func(unit: Dictionary)->bool:return unit.commands.all(func(command: Dictionary)->bool:return command.state=="SUCCEEDED")),"All original rolling-T primitives finish after actual occupied-lane recovery")
		var current_args: Array = sim.units.map(func(unit: Dictionary)->Array:return unit.commands.map(func(command: Dictionary)->Dictionary:return {"id":command.id,"args":command.args.duplicate(true)}))
		check(current_args==original_args,"Recovery changes only execution paths while original command IDs, goals and metadata remain immutable")
		for slot: Dictionary in planned.slots:
			check(position(sim._find(sim.units,str(slot.unit_id))).distance_to(Vector2(float(slot.target[0]),float(slot.target[1])))<=0.1,"Recovered rolling-T member reaches its exact original final slot")
		var signals: Array = sim.events.filter(func(event: Dictionary)->bool:return event.type=="SIGNAL")
		check(signals.size()==1 and int(signals[0].released)==4,"Recovered rolling-T releases one complete actual cohort")

func _held_lane_contracts() -> void:
	# This full original primitive plan reached an actual yield lane and then
	# renewed its hold every STEP. Keep the strong completion/goal checks and
	# prove recovery through public issue with the real side-room patrol.
	var fixed: Dictionary = JSON.parse_string(FIXED_SIDE_DATA)
	var sim := RecoveryProbe.new()
	sim.load_mission(fixed.mission)
	var accepted_plan := true
	for row: Dictionary in fixed.plan:
		for node: Dictionary in row.nodes:
			accepted_plan = bool(sim.issue(str(row.unit_id),str(node.type),node.args).get("ok",false)) and accepted_plan
	check(accepted_plan,"Actual side-patrol held-lane primitive plan is accepted through public issue")
	if not accepted_plan: return
	var originals: Array = sim.units.map(func(unit: Dictionary)->Array:return unit.commands.map(func(command: Dictionary)->Dictionary:return {"id":command.id,"args":command.args.duplicate(true)}))
	var physical := true
	var crossed := false
	for _frame: int in range(600):
		var prior: Array = sim.units.map(func(unit: Dictionary)->Vector2:return position(unit))
		sim.step(STEP)
		crossed = crossed or float(sim.enemies[0].x)>=10.0
		for index: int in range(4):
			physical = physical and sim.nav.segment_clear(prior[index],position(sim.units[index]),Navigation.RADIUS) and prior[index].distance_to(position(sim.units[index]))<=0.121
			for other: int in range(index): physical = physical and position(sim.units[index]).distance_to(position(sim.units[other]))>=sim._movement_body_spacing()-0.000001
	check(crossed,"The original normal patrol actually crosses the authored side-door plane")
	check(sim.lane_departures.all(func(row: Dictionary)->bool:return row.move_zero and row.rng_unchanged and row.primitive_unchanged and row.route_clear and row.exact_goal),"Each lane departure preserves full live sweep, exact goal, IDs, all RNG streams and zero movement that STEP")
	check(physical and sim.command_failures==0,"Side-patrol recovery keeps body/leaf clearance and the original one-STEP movement budget")
	check(sim.units.all(func(unit: Dictionary)->bool:return unit.commands.all(func(command: Dictionary)->bool:return command.state=="SUCCEEDED")),"All four living side-patrol formation participants actually complete their original primitives")
	check(originals==sim.units.map(func(unit: Dictionary)->Array:return unit.commands.map(func(command: Dictionary)->Dictionary:return {"id":command.id,"args":command.args.duplicate(true)})),"Held-lane recovery leaves every original public primitive unchanged")
	for unit: Dictionary in sim.units:
		var moves: Array = unit.commands.filter(func(command: Dictionary)->bool:return command.type=="MOVE" and command.args.formation.stage=="move")
		check(not moves.is_empty() and position(unit).distance_to(sim._point(moves[-1].args.target))<=0.1,"Side-patrol member reaches its real original final formation slot")
	var signals: Array = sim.events.filter(func(event: Dictionary)->bool:return event.type=="SIGNAL")
	check(signals.size()==1 and int(signals[0].released)==4,"Held-lane recovery releases one complete actual four-member ready cohort")

func _held_lane_unit_contract() -> void:
	# Recovery coverage is independent of whether a complete public plan
	# still needs this particular branch after avoidance improvements.
	var data := fixture(0,2,6.0)
	data.units[0].x = 7.6
	data.units[1].x = 8.4
	for unit: Dictionary in data.units: unit.z = 12.0
	var sim := RecoveryProbe.new()
	sim.load_mission(data)
	for index: int in range(2):
		var unit: Dictionary = sim.units[index]
		accepted(sim,str(unit.id),"MOVE",{"target":[unit.x,8.0],"formation":{"kind":"SERPENTINE","sync_id":"held-lane-unit","order":index+1,"stage":"stack","source_unit_id":"alpha"}})
		var command: Dictionary = sim._active(unit)
		sim._start_command(unit,command)
		command.state = "WAITING"
		command["_traffic_wait"] = 2.0
	sim.tick = 60
	sim.time = 2.0
	var actor: Dictionary = sim.units[1]
	actor["_movement_lane_goal"] = [actor.x,actor.z]
	actor["_movement_lane_requester"] = "alpha"
	actor["_movement_lane_hold_until"] = sim.time + 0.8
	actor.hold_position = true
	var before := fingerprint(sim)
	check(not sim._recover_formation_lane_hold(actor,sim._active(actor)) and fingerprint(sim)==before,"A player hold rejects lane departure without changing authority or RNG")
	actor.hold_position = false
	check(sim._recover_formation_lane_hold(actor,sim._active(actor)),"A stopped same-cohort stack can leave its reached yield lane")
	check(sim.lane_departures.size()==1 and sim.lane_departures.all(func(row: Dictionary)->bool:return row.move_zero and row.rng_unchanged and row.primitive_unchanged and row.route_clear and row.exact_goal),"The isolated departure preserves full live sweep, exact goal, primitive, RNG and zero movement")

func _recovery_floor_contracts() -> void:
	var data := fixture(0,1,6.0)
	data.rooms.append({"id":"raised_island","x":8.0,"z":10.0,"w":2.0,"d":1.0,"base_height":2.022})
	var sim := make(data)
	var before := rngs(sim)
	var route: Array = [[8.0,6.0]]
	check(sim._movement_route_clear(sim.units[0],route),"Flat navigation alone accepts equal-height endpoints across the authored raised island")
	check(not sim._formation_recovery_route_clear(sim.units[0],route),"Named formation recovery rejects every leg crossing an intervening authored floor jump")
	check(sim._formation_recovery_route_clear(sim.units[0],[[10.5,14.0],[10.5,6.0],[8.0,6.0]]),"Named formation recovery retains an actually clear same-floor route around the raised island")
	check(rngs(sim)==before,"Both accepted and rejected recovery floor queries preserve all four RNG streams")
	data = fixture(0,1,6.0)
	data.rooms[0]["base_height"] = 2.022
	sim = make(data)
	before = rngs(sim)
	check(sim._formation_recovery_route_clear(sim.units[0],route),"Whole-route recovery on one continuous elevated authored floor remains legal")
	check(rngs(sim)==before,"Continuous elevated-floor validation consumes no randomness")

func _repeat_contracts() -> void:
	for seed_value: int in range(30):
		var left := make(fixture(seed_value,2))
		var right := make(fixture(seed_value,2))
		var order: Array = ["bravo","alpha"]
		var a: Dictionary = left.plan_formation([8.0,11.0],"SERPENTINE",order,{"signal":"B","delay_ticks":3})
		var b: Dictionary = right.plan_formation([8.0,11.0],"SERPENTINE",order,{"signal":"B","delay_ticks":3})
		check(a==b and bool(a.get("ok",false)) and fingerprint(left)==fingerprint(right),"Seed%d repeats the exact primitive plan and all private planning state"%seed_value)
		for frame: int in range(90):
			left.step(STEP)
			right.step(STEP)
			if frame==60:
				check(left.release_signal("B")==right.release_signal("B"),"Repeated public manual signals return identical receipts")
			check(JSON.stringify(left.snapshot(true))==JSON.stringify(right.snapshot(true)) and rngs(left)==rngs(right),"Seed%d fixed tick%d repeats complete authority and all RNG streams"%[seed_value,frame])

func run() -> void:
	_draft_and_transaction_contracts()
	_known_geometry_contracts()
	_primitive_edit_contracts()
	_runtime_contracts()
	_junction_contracts()
	_delay_occurrence_contracts()
	_occupied_detour_contracts()
	_held_lane_contracts()
	_held_lane_unit_contract()
	_recovery_floor_contracts()
	if not "--contracts-only" in OS.get_cmdline_user_args(): _repeat_contracts()
	for failure: String in failures: print("FAIL "+failure)
	print("BREACH_FORMATION_RESULT checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
