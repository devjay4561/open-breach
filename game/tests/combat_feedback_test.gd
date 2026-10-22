extends SceneTree
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
func _run() -> void:
	var world = preload("res://scripts/world_view.gd").new()
	root.add_child(world)
	world.build(JSON.parse_string(FileAccess.get_file_as_string("res://data/tutorial.json")))
	var actor := Node3D.new()
	world.add_child(actor)
	actor.position = Vector3(6, 0, 12)
	var muzzle := Marker3D.new()
	actor.add_child(muzzle)
	muzzle.position = Vector3(0.31, 1.37, -0.92)
	world._entity_nodes["alpha"] = {"node": actor, "visual": {"muzzle": muzzle}}
	var state: Dictionary = {"events": [{"seq": 1, "type": "SHOT", "time": 5.0, "from": [6,12], "to": [6,8], "attacker_id": "alpha", "hit": true}]}
	world._clock = 5.0
	world._update_effects(state, 0.15, false)
	_check(world._flashes.size() == 1, "Shot creates one effect")
	var effect: Dictionary = world._flashes[0]
	var captured_muzzle := world.to_local(muzzle.global_position)
	_check(effect.seq == 1 and is_equal_approx(effect.event_time, 5.0), "Effect preserves event sequence and simulation timestamp")
	_check(effect.flash_sprite.position.is_equal_approx(captured_muzzle), "New flash begins at the imported weapon muzzle socket")
	_check(effect.flash_sprite.modulate.a > 0.99, "New shot survives a slow initial frame at full intensity")
	_check(effect.flash_sprite.pixel_size * 512.0 >= 1.1, "Brief flash remains readable at tactical camera distance")
	actor.position.x += 2.0
	world._clock += 0.02
	world._update_effects(state, 0.02, false)
	_check(world._flashes.size() == 1, "Repeating a snapshot never creates duplicate shot effects")
	_check(effect.flash_sprite.position.is_equal_approx(captured_muzzle), "A moving actor does not drag an already emitted flash")
	_check(effect.flash_sprite.visible and effect.flash_sprite.modulate.a > 0.5, "Flash has a short visible envelope after the guaranteed first frame")
	# Target-side feedback (impact puff, confirm ring) starts when the tracer arrives (35-50 ms), so let it land first.
	world._clock += 0.04
	world._update_effects(state, 0.04, false)
	world._flash_reduced = true
	world._update_effects(state, 0, true)
	_check(not effect.flash_sprite.visible, "Reduced flash suppresses the flash")
	_check(effect.smoke_sprite.visible and effect.smoke_sprite.modulate.a > 0 and effect.impact_sprite.visible, "Reduced flash retains subtle smoke and confirmed-hit feedback")
	var remaining: float = effect.remaining
	world._clock += 0.1
	world._update_effects(state, 0.1, true)
	_check(effect.remaining == remaining, "Pause freezes effect age")
	world._flash_reduced = false
	world._clock += 0.06
	world._update_effects(state, 0.06, false)
	_check(not effect.flash_sprite.visible and effect.flash_sprite.modulate.a == 0.0, "Flash expires within 75 milliseconds of presentation time")
	_check(effect.smoke_sprite.modulate.a > 0, "Residual smoke can outlive the muzzle flash")
	world._clock += 0.35
	world._update_effects(state, 0.35, false)
	_check(world._flashes.is_empty(), "Smoke expires at 420 milliseconds without replaying consumed events")
	# A hidden actor's stale scene node must not become an enemy-position side channel.
	actor.visible = false
	world._clock = 6.0
	state.events = [{"seq": 2, "type": "SHOT", "time": 6.0, "from": [6,12], "to": [6,8], "attacker_id": "alpha", "hit": false}]
	world._update_effects(state, 0, false)
	effect = world._flashes[0]
	_check(effect.flash_sprite.position.is_equal_approx(Vector3(6.18, 1.23, 10.88)), "Hidden actor uses the observed event origin, never its live socket")
	world._clock += 0.03
	world._update_effects(state, 0.03, false)
	_check(not effect.has("impact_sprite"), "A miss does not invent a wall or body impact (no impact sprite is even allocated)")
	# Rewinding clears active effects and consumes only the snapshot's own history.
	world._clock = 4.0
	state.events = []
	world._update_effects(state, 0, true)
	_check(world._flashes.is_empty(), "Replay rewind clears shots from the future")
	state.events = [{"seq": 1, "type": "SHOT", "time": 4.05, "from": [6,12], "to": [6,8], "attacker_id": "alpha", "hit": true}]
	world._clock = 4.02
	world._update_effects(state, 0, false)
	_check(world._flashes.is_empty(), "An interpolated display waits for the event time before firing")
	world._clock = 4.05
	world._update_effects(state, 0, false)
	_check(world._flashes.size() == 1 and world._flashes[0].seq == 1, "Forward playback after rewind accepts the new timeline's sequence")
	world._clock = 5.0
	state.events.append({"seq": 2, "type": "SHOT", "time": 4.1, "from": [6,12], "to": [6,8], "hit": true})
	world._update_effects(state, 0, false)
	_check(world._flashes.is_empty(), "An old snapshot event does not flash again when a large frame gap arrives")
	# A slow frame must not skip the entire flashbang burst before its first draw.
	world._clock = 6.16
	state.events = [{"seq": 3, "type": "STUN", "time": 6.0, "to": [6,8], "radius": 3.0}]
	world._update_effects(state, 0.16, false)
	effect = world._flashes[0]
	_check(effect.flash_sprite.visible and effect.flash_sprite.modulate.a > 0.9, "Late first presentation still draws a bright flashbang burst")
	_check(effect.flash_sprite.pixel_size * 512.0 >= 2.0, "Flashbang burst is readable at the whole-map camera scale")
	world._clock += 0.1
	world._update_effects(state, 0.1, false)
	_check(effect.flash_sprite.visible and effect.flash_sprite.modulate.a > 0.2, "Flashbang remains readable beyond one 10Hz state update")
	world._flash_reduced = true
	world._update_effects(state, 0, true)
	_check(not effect.flash_sprite.visible and effect.smoke_sprite.modulate.a > 0, "Reduced flash retains smoke without the bright burst")
	world._flash_reduced = false
	world._clock += 0.3
	world._update_effects(state, 0.3, false)
	_check(world._flashes.is_empty(), "Flashbang feedback expires without repeating the event")
	var stunned: Dictionary = {"id": "flash-target", "x": 6.0, "z": 8.0, "hp": 100.0, "stunned": 1.8, "status": "STUNNED"}
	world._sync_actor(stunned, "enemy", 0, "", 0, true)
	var label: Label3D = world._entity_nodes["flash-target"].status
	_check(label.visible and label.text == "기절 1.8초", "Observed stunned enemy shows the remaining duration")
	world._language = "en"
	world._sync_actor(stunned, "enemy", 0, "", 0, true)
	_check(label.text == "STUN 1.8s", "Stun duration follows the selected language")
	stunned.stunned = 0.0
	stunned.status = "IDLE"
	world._sync_actor(stunned, "enemy", 0, "", 0, true)
	_check(not label.visible, "Stun label disappears when the actual stun expires")
	world.queue_free()
	print("BREACH_FEEDBACK_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
