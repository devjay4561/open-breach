extends SceneTree
## Public counters and terminal stars must depend only on saved observations.
const Metrics = preload("res://scripts/doctrine_metrics.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _known(score: int = 80) -> Dictionary:
	return {"neutralized":1,"rescued":1,"kills":0,"arrests":1,"civilian_damage":0.0,"civilian_losses":0,"unlawful_shots":0,"score":score}

func _record(hidden_damage: float, score: int = 80, success: bool = true) -> Dictionary:
	var known := _known(score)
	return {"tick":60,"time":2.0,"kills":2,"arrests":1,"civilian_damage":hidden_damage,"unit_damage":3.25,"frags_used":1,"stats_observed":known,
		"objectives":{"neutralized":3,"total":4,"rescued":1,"civilians_total":2},
		"result":{"success":success,"score":100,"rank":"S","neutralized":3,"enemies_total":4,"rescued":1,"civilians_total":2,"kills":2,"arrests":1,"civilian_damage":hidden_damage,"civilian_losses":1 if hidden_damage>0 else 0,"unit_damage":3.25,"unlawful_shots":2,"frags_used":1,
			"stars":{"safe_civilians":hidden_damage==0,"safe_squad":false,"arrest":success},"stats_observed":known.duplicate(true),"stars_observed":{"safe_civilians":false,"safe_squad":false,"arrest":success}}}

func _run() -> void:
	for seed_value: int in range(30):
		var unharmed := _record(0.0)
		var harmed := _record(float(seed_value+1)*0.125)
		var unharmed_bytes := var_to_bytes(unharmed)
		var harmed_bytes := var_to_bytes(harmed)
		var public_unharmed := unharmed.duplicate(false)
		var public_harmed := harmed.duplicate(false)
		Metrics.filter_observed_statistics(public_unharmed)
		Metrics.filter_observed_statistics(public_harmed)
		check(public_unharmed==public_harmed,"Hidden outcome cannot change public counters/stars seed%d" % seed_value)
		check(var_to_bytes(unharmed)==unharmed_bytes and var_to_bytes(harmed)==harmed_bytes,"Raw recording remains byte-exact seed%d" % seed_value)
		check(public_harmed.objectives=={"neutralized":1,"total":4,"rescued":1,"civilians_total":2},"Observed objectives keep the briefed population")
		check(public_harmed.result.score==80 and public_harmed.result.rank=="A","Rank follows the observed score")
		check(public_harmed.result.unit_damage==3.25 and public_harmed.result.frags_used==1,"Own damage and consumed equipment stay exact")
		check(not public_harmed.has("stats_observed") and not public_harmed.result.has("stats_observed") and not public_harmed.result.has("stars_observed"),"Private projection fields are removed")
		var before := var_to_bytes(public_harmed)
		Metrics.filter_observed_statistics(public_harmed)
		check(var_to_bytes(public_harmed)==before,"Repeated filtering is idempotent")
	for pair: Array in [[0,"C"],[64,"C"],[65,"B"],[79,"B"],[80,"A"],[94,"A"],[95,"S"],[100,"S"]]:
		var state := _record(1.0,int(pair[0]))
		Metrics.filter_observed_statistics(state)
		check(state.result.rank==pair[1],"Observed rank boundary %d" % int(pair[0]))
	var failed := _record(1.0,100,false)
	Metrics.filter_observed_statistics(failed)
	check(failed.result.rank=="—" and failed.result.stars.arrest==false,"Failure never earns a rank or star")
	var legacy := {"tick":1,"objectives":{"neutralized":2,"total":4},"kills":2,"result":{"success":true,"score":90,"rank":"A","kills":2}}
	var legacy_before := var_to_bytes(legacy)
	Metrics.filter_observed_statistics(legacy)
	check(var_to_bytes(legacy)==legacy_before,"Legacy absent fields preserve exact public shape")
	var full := _record(3.0)
	full.time_to_dominate={"known":{"observed":true,"seconds":2.0},"hidden":{"observed":false,"seconds":1.0}}
	full.result.time_to_dominate=full.time_to_dominate.duplicate(true)
	var full_bytes := var_to_bytes(full)
	var shown := full.duplicate(false)
	Metrics.filter_observed_statistics(shown)
	check(shown.time_to_dominate.keys()==["known"] and shown.result.time_to_dominate.keys()==["known"],"P0 observed door metric still filters at both levels")
	check(var_to_bytes(full)==full_bytes,"P0 and P5 shared filters retain original recording")
	print("BREACH_OBSERVED_STATISTICS_FILTER_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
