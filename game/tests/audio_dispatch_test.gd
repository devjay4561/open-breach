extends SceneTree

class AudioHarness extends "res://scripts/main.gd":
	var emitted: Array = []
	func _ready() -> void:
		pass
	func _emit(message: Dictionary) -> void:
		emitted.append(message)

class CameraWorld extends Node3D:
	var camera: Camera3D
	func surface_position(point: Vector2, above_floor: float = 0.2) -> Vector3:
		return Vector3(point.x, above_floor, point.y)

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _run() -> void:
	var app := AudioHarness.new()
	root.add_child(app)
	var events: Array = [
		{"seq": 1, "type": "SHOT", "attacker_id": "alpha", "from": [-5, 0], "to": [5, 0], "hit": true},
		{"seq": 2, "type": "SHOT", "attacker_id": "bravo", "from": [5, 0], "to": [-5, 0], "hit": false},
		{"seq": 3, "type": "INCAPACITATED", "entity_id": "enemy", "to": [5, 0]},
	]
	app._dispatch_sounds({"events": events})
	_check(app.emitted.size() == 3, "Simultaneous shooters each produce one shot; only validated hit produces contact")
	_check(app.emitted[0].name == "shot" and app.emitted[1].name == "hit" and app.emitted[2].name == "shot", "Contact follows its shot without duplicate incapacitation sound or invented miss impact")
	_check(app.emitted[0].event_seq == 1 and app.emitted[2].event_seq == 2 and app.emitted[2].attacker_id == "bravo", "Stable event and shooter IDs reach the sample variation selector")
	_check(is_equal_approx(app.emitted[1].react_at, 0.05) and app.emitted[0].react_at == 0.0, "Positional hit sound waits for tracer arrival; shot sound stays immediate")
	app._dispatch_sounds({"events": events})
	_check(app.emitted.size() == 3, "Repeated snapshot cannot replay old sounds")
	app._reset_event_cursor({"events": events})
	app._dispatch_sounds({"events": events})
	_check(app.emitted.size() == 3, "Replay seek cursor prevents a burst of historical sounds")
	var door_events: Array = [
		{"seq": 4, "type": "DOOR_OPEN", "door_id": "d1", "from": [4, 0]},
		{"seq": 5, "type": "DOOR_OPEN", "door_id": "d2", "from": [-4, 0]},
	]
	app._dispatch_sounds({"events": door_events})
	_check(app.emitted.size() == 5 and app.emitted[-2].name == "door" and app.emitted[-1].name == "door", "Two doors finishing in the same frame each produce their contact")
	app._dispatch_sounds({"events": door_events})
	_check(app.emitted.size() == 5, "Repeated door completion snapshot does not duplicate contacts")
	var camera_world := CameraWorld.new()
	root.add_child(camera_world)
	camera_world.camera = Camera3D.new()
	camera_world.add_child(camera_world.camera)
	camera_world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_world.camera.size = 20.0
	camera_world.camera.position = Vector3(0, 20, 10)
	camera_world.camera.look_at(Vector3.ZERO)
	app.world = camera_world
	app._emit_positional_sound("shot", events[0], [-5, 0])
	app._emit_positional_sound("shot", events[1], [5, 0])
	_check(app.emitted[-2].pan < 0.0 and app.emitted[-1].pan > 0.0, "Stereo pan follows the actual camera's left and right")
	_check(app.emitted[-1].gain >= 0.55 and app.emitted[-1].gain <= 1.0, "Off-centre attenuation keeps tactical sounds audible")
	app._emit_positional_sound("shot", events[0], [500, 500])
	_check(absf(app.emitted[-1].pan) <= 0.8 and app.emitted[-1].gain >= 0.55, "Offscreen sound pan and gain remain bounded")
	app.settings.reduced_flash = true
	app._emit_positional_sound("hit", {"type":"SHOT","hit":true,"time":1.0}, [0,0])
	_check(is_equal_approx(app.emitted[-1].react_at, 1.035), "Reduced flash gives the positional hit sound the same 35ms arrival")
	app._dispatch_sounds({"events":[{"seq":6,"type":"SHOT","time":2.0,"hit":true,"protection":"blocked","from":[0,0],"to":[1,0]}, {"seq":7,"type":"SHOT","time":2.0,"hit":true,"protection":"unprotected","from":[0,0],"to":[1,0]}]})
	_check(app.emitted[-3].name == "armour_block" and app.emitted[-1].name == "hit", "Only blocked contact selects procedural armour cue")
	_check(is_equal_approx(app.emitted[-3].react_at, 2.035) and app.emitted[-3].protection == "blocked", "Armour cue retains protection and tracer arrival")
	app.world = null
	camera_world.free()
	app.free()
	print("BREACH_AUDIO_DISPATCH_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
