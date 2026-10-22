extends SceneTree
const Actor = preload("res://scripts/actor_visual.gd")
class Harness extends "res://scripts/main.gd":
	var emitted: Array = []
	func _ready() -> void: pass
	func _emit(message: Dictionary) -> void: emitted.append(message)
	func _sample_replay() -> void: pass
	func _send_state() -> void: pass
class MaterialProbe extends RefCounted:
	var writes := 0
	var albedo_color: Color = Color.WHITE:
		set(value):
			albedo_color = value
			writes += 1
class CameraWorld extends Node3D:
	var camera: Camera3D
	func surface_position(point: Vector2, above_floor: float = 0.2) -> Vector3:
		return Vector3(point.x, above_floor, point.y)
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func restored(visual: Dictionary) -> bool:
	for entry: Dictionary in visual.hit_materials:
		if entry.material.albedo_color != entry.rest: return false
	return true
func render_sample() -> void:
	root.size = Vector2i(1000, 560)
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("242b2b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-30,0)
	scene.add_child(light)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.0
	camera.position = Vector3(0,5,7)
	camera.look_at(Vector3(0,0.8,0))
	camera.make_current()
	for index: int in range(4):
		var holder := Node3D.new()
		scene.add_child(holder)
		holder.position.x = (float(index) - 1.5) * 1.6
		var actor := Actor.create(holder, index != 2)
		var event: Array = [{"seq":1,"type":"SHOT","time":1.0,"target_id":"sample","hit":true,"protection":"blocked" if index == 3 else "","from":[0,0],"to":[0,1]}] if index > 0 else []
		Actor.sync(actor,{"id":"sample","hp":100.0,"status":"READY"},event,1.07,0.0,false)
		var label := Label3D.new()
		holder.add_child(label)
		label.text = ["REST", "ENEMY CONTACT +20ms", "FRIENDLY CONTACT +20ms", "BLOCKED CONTACT +20ms"][index]
		label.position.y = 2.05
		label.font_size = 22
		label.pixel_size = 0.0025
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../.omc/phase2/w2-r3-actor-hit-render.png")
	scene.free()
func run() -> void:
	var body := Node3D.new()
	var other_body := Node3D.new()
	root.add_child(body)
	root.add_child(other_body)
	body.rotation.y = PI * 0.5
	var visual := Actor.create(body, true)
	var other := Actor.create(other_body, false)
	var delayed_hit_sample: float = visual.player.get_animation(visual.names.RifleHit).length * (0.02 / 0.30)
	var entity := {"id":"enemy","hp":100.0,"status":"READY","appearance":{"color":"#718255"}}
	var friendly := {"id":"alpha","hp":100.0,"status":"READY","appearance":{"color":"#718255"}}
	var events: Array = [{"seq":1,"time":1.0,"type":"SHOT","attacker_id":"alpha","target_id":"enemy","hit":true,"from":[0,0],"to":[1,0]}]
	Actor.sync(visual, entity, [], 0.0, 0.0, false)
	Actor.sync(other, friendly, [], 0.0, 0.0, false)
	for index: int in range(visual.hit_materials.size()):
		check(visual.hit_materials[index].material != other.hit_materials[index].material, "Every body material is per actor")
	for clock: float in [1.0, 1.02, 1.049]:
		Actor.sync(visual, entity, events, clock, 0.0, false)
		check(restored(visual) and visual.model.position.is_zero_approx() and not str(visual.clip).begins_with("RifleHit:"), "Tint, punch and hit clip wait for tracer arrival at %.3f" % clock)
	Actor.sync(visual, entity, events, 1.07, 0.0, false)
	check(not restored(visual), "Confirmed enemy hit tints the body")
	check(str(visual.clip).begins_with("RifleHit:") and is_equal_approx(visual.player.current_animation_position, delayed_hit_sample), "Hit clip samples the delayed age")
	check(restored(other), "Enemy flash never modifies another actor's materials")
	var flashed: Color = visual.hit_materials[0].material.albedo_color
	check((visual.model.global_position - body.global_position).is_equal_approx(Vector3(0.0352,0,0)), "Punch follows world shot direction through a rotated parent")
	Actor.sync(visual, entity, events, 1.16, 0.0, false)
	check(restored(visual) and visual.model.position.is_zero_approx(), "Tint and punch expire exactly to their resting values")
	Actor.sync(visual, entity, events, 1.07, 0.0, false)
	check(visual.hit_materials[0].material.albedo_color == flashed, "Explicit historical hit input reproduces its exact tint after a seek")
	Actor.sync(visual, entity, events, 1.049, 0.0, false)
	check(restored(visual) and visual.model.position.is_zero_approx() and not str(visual.clip).begins_with("RifleHit:"), "Seeking into tracer flight restores the unhit actor")
	Actor.sync(visual, entity, events, 0.5, 0.0, false)
	check(restored(visual) and visual.model.position.is_zero_approx() and visual.last_hit_protection == "", "Seeking before the hit clears future feedback")
	Actor.sync(visual, entity, events, 1.034, 0.0, true)
	check(restored(visual) and not str(visual.clip).begins_with("RifleHit:"), "Reduced feedback waits 35ms")
	Actor.sync(visual, entity, events, 1.055, 0.0, true)
	var subtle: Color = visual.hit_materials[0].material.albedo_color
	check(subtle.r < flashed.r and subtle.g < flashed.g and visual.model.position.is_zero_approx(), "Reduced feedback keeps a subtle tint and suppresses punch")
	var blocked: Array = events.duplicate(true)
	blocked[0].protection = "blocked"
	Actor.sync(visual, entity, blocked, 1.07, 0.0, false)
	var steel: Color = visual.hit_materials[0].material.albedo_color
	check(steel.b > steel.r and steel.r < flashed.r, "Blocked hit uses steel rather than white")
	blocked[0].target_id = "alpha"
	blocked[0].protection = "penetrated"
	Actor.sync(other, friendly, blocked, 1.07, 0.0, false)
	var hot: Color = other.hit_materials[0].material.albedo_color
	check(hot.r > hot.g and hot.r > hot.b, "Friendly hit uses hot red white")
	friendly.appearance.color = "#998844"
	Actor.sync(other, friendly, blocked, 1.2, 0.0, false)
	check(restored(other), "Loadout recolor during feedback restores the new resting color")
	Actor.sync(visual, entity, events, 1.349, 0.0, false)
	check(str(visual.clip).begins_with("RifleHit:"), "Delayed reaction retains its full 300ms window")
	Actor.sync(visual, entity, events, 1.351, 0.0, false)
	check(not str(visual.clip).begins_with("RifleHit:"), "Delayed reaction expires after its full window")
	var dead: Dictionary = entity.duplicate(true)
	dead.hp = 0.0
	var death_events: Array = [{"seq":2,"type":"SHOT","target_id":"enemy","hit":true,"time":2.0}, {"seq":3,"type":"INCAPACITATED","entity_id":"enemy","time":2.0}]
	Actor.sync(visual, dead, death_events, 2.01, 0.0, false)
	check(str(visual.clip).begins_with("Death:") and visual.player.current_animation_position == 0.0 and visual.death_time == 2.0 and dead.hp == 0.0, "Death sample waits without changing dead status or event time")
	Actor.sync(visual, dead, death_events, 2.049, 0.0, false)
	check(visual.player.current_animation_position == 0.0, "Death clip does not advance during tracer flight")
	Actor.sync(visual, dead, death_events, 2.07, 0.0, false)
	check(is_equal_approx(visual.player.current_animation_position, 0.02), "Death sample uses the same 50ms delay")
	Actor.sync(visual, dead, death_events, 2.02, 0.0, false)
	check(visual.player.current_animation_position == 0.0, "Seek restores the delayed death sample")
	Actor.sync(visual, dead, death_events, 2.034, 0.0, true)
	check(visual.player.current_animation_position == 0.0, "Reduced death sample waits 35ms")
	Actor.sync(visual, dead, death_events, 2.055, 0.0, true)
	check(is_equal_approx(visual.player.current_animation_position, 0.02), "Reduced death uses the same shortened travel")
	var blast: Array = [{"seq":4,"type":"INCAPACITATED","entity_id":"enemy","time":3.0}]
	Actor.sync(visual, dead, blast, 3.01, 0.0, false)
	check(is_equal_approx(visual.player.current_animation_position, 0.01), "Frag/unlinked death begins immediately without tracer delay")
	Actor.sync(visual, entity, [], 0.5, 0.0, false)
	check(restored(visual) and visual.model.position.is_zero_approx(), "Production-style seek with an empty event batch clears stale future feedback")
	check(not visual.has("hit_after_shot"), "Rewind erases stale hit timing classification")
	var timing_world := preload("res://scripts/world_view.gd").new()
	for reduced_flash: bool in [false, true]:
		timing_world._flash_reduced = reduced_flash
		var delay: float = timing_world._hit_reaction_delay()
		check(is_equal_approx(delay, 0.035 if reduced_flash else 0.05), "World delay matches the agreed normal/reduced values")
		for motion: bool in [false, true]:
			visual.hit_delay = delay
			Actor.sync(visual, entity, events, 1.0 + delay - 0.001, 0.0, motion)
			check(restored(visual) and not str(visual.clip).begins_with("RifleHit:"), "Explicit visual delay overrides independent motion flag before contact")
			Actor.sync(visual, entity, events, 1.0 + delay + 0.02, 0.0, motion)
			check(not restored(visual) and is_equal_approx(visual.player.current_animation_position, delayed_hit_sample), "Actor and world delay agree regardless of reduced motion")
	timing_world.free()
	visual.erase("hit_delay")
	var probe := MaterialProbe.new()
	visual.hit_materials = [{"material":probe,"rest":Color.WHITE}]
	Actor.sync(visual, entity, events, 1.07, 0.0, false)
	check(probe.writes > 0, "Active feedback writes its per-actor material")
	Actor.sync(visual, entity, events, 1.2, 0.0, false)
	var restored_writes: int = probe.writes
	check(probe.albedo_color == Color.WHITE, "Transition back to rest restores the material")
	for index: int in range(5): Actor.sync(visual, entity, [], 1.3 + float(index) * 0.02, 0.0, false)
	check(probe.writes == restored_writes, "Resting actor makes no repeated material writes")
	Actor.sync(visual, dead, death_events, 8.0, 0.0, false)
	var corpse_writes: int = probe.writes
	for index: int in range(5): Actor.sync(visual, dead, [], 8.1 + float(index) * 0.02, 0.0, false)
	check(probe.writes == corpse_writes, "Settled corpse makes no per-frame material writes")
	var app := Harness.new()
	root.add_child(app)
	var world := CameraWorld.new()
	root.add_child(world)
	world.camera = Camera3D.new()
	world.add_child(world.camera)
	world.camera.position = Vector3(0,20,10)
	world.camera.look_at(Vector3.ZERO)
	app.world = world
	app._dispatch_fx({"events":[{"seq":1,"time":1.0,"type":"SHOT","target_id":"enemy","hit":true,"hostile":false,"protection":"blocked","to":[0,0]}, {"seq":2,"time":1.0,"type":"INCAPACITATED","entity_id":"enemy","kind":"enemy","to":[0,0]}]})
	check(app.emitted.size() == 2 and app.emitted[0].screen.size() == 2 and app.emitted[1].screen.size() == 2, "Hit and neutralized messages carry screen points")
	check(app.emitted[0].protection == "blocked" and not app.emitted[0].friendly and app.emitted[0].event_seq == 1, "Hit payload preserves protection, team and sequence")
	check(app.emitted[1].kind == "neutralized" and not app.emitted[1].friendly and app.emitted[1].event_seq == 2 and app.emitted[1].after_shot and is_equal_approx(app.emitted[1].react_at, 1.05), "Shot casualty uses the same tracer arrival")
	app._dispatch_fx({"events":[{"seq":1,"time":1.0,"type":"SHOT","hit":true}]})
	check(app.emitted.size() == 2, "Re-delivered historical hit does not emit again")
	app.settings.reduced_flash = true
	app._dispatch_fx({"events":[{"seq":3,"time":2.0,"type":"SHOT","hit":true,"target_id":"alpha","to":[1,0]}, {"seq":4,"time":2.0,"type":"INCAPACITATED","entity_id":"alpha","kind":"unit","to":[1,0]}, {"seq":5,"time":3.0,"type":"INCAPACITATED","entity_id":"frag_victim","kind":"enemy","to":[1,0]}, {"seq":6,"time":4.0,"type":"ARREST","enemy_id":"captured","to":[1,0]}]})
	check(app.emitted[3].kind == "unit_down" and app.emitted[3].after_shot and is_equal_approx(app.emitted[3].react_at, 2.035), "Shot unit-down banner shares shortened arrival")
	check(not app.emitted[4].after_shot and app.emitted[4].react_at == 0.0, "Frag/unlinked casualty has no tracer delay")
	check(app.emitted[5].cause == "arrest" and not app.emitted[5].after_shot and app.emitted[5].react_at == 0.0, "Arrest has an explicit immediate non-kill cause")
	var before_clock: int = app.emitted.size()
	app._dispatch_feedback_clock({"presentation_time":2.02,"presentation_paused":true,"presentation_mode":"REPLAY"})
	check(app.emitted.size() == before_clock and app._web_react_until > 0.0, "Paused engine holds the reaction clock horizon")
	app._dispatch_feedback_clock({"presentation_time":2.034,"presentation_paused":false,"presentation_mode":"REPLAY"})
	check(app.emitted[-1].type == "fx_clock" and app.emitted[-1].time == 2.034, "Engine sends the actual presentation time during flight")
	app._dispatch_feedback_clock({"presentation_time":2.035,"presentation_paused":false,"presentation_mode":"REPLAY"})
	check(app.emitted[-1].time == 2.035 and app._web_react_until < 0.0, "Engine sends contact then stops per-frame web clock messages")
	app._dispatch_feedback_clock({"presentation_time":3.0,"presentation_paused":false,"presentation_mode":"REPLAY"})
	check(app.emitted.size() == before_clock + 2, "No web clock messages are emitted at rest")
	var before_seek: int = app.emitted.size()
	app.recorder = preload("res://scripts/replay.gd").new()
	app.recorder.duration = 10.0
	app.mode = "REPLAY"
	app._apply_action({"action":"replay_seek","time":0.0})
	check(app.emitted.size() == before_seek + 1 and app.emitted[-1].type == "fx_reset", "Accepted seek immediately notifies web to cancel pending feedback")
	app._apply_action({"action":"replay_seek","time":"invalid"})
	check(app.emitted.size() == before_seek + 1, "Invalid seek cannot cancel current feedback")
	app.world = null
	app.free()
	world.free()
	body.free()
	other_body.free()
	if "--render" in OS.get_cmdline_user_args(): await render_sample()
	print("BREACH_ACTOR_HIT_FEEDBACK_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
