extends SceneTree
## Reuse must still react to edits at a frozen clock and preserve world geometry.
class ProbeWorld extends "res://scripts/world_view.gd":
	var path_draws := 0
	var cone_draws := 0
	func _draw_paths(units: Array) -> void:
		path_draws += 1
		super._draw_paths(units)
	func _draw_cone(units: Array) -> void:
		cone_draws += 1
		super._draw_cone(units)

const World = preload("res://scripts/world_view.gd")
var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _initialize() -> void:
	call_deferred("_run")

func fixture() -> Dictionary:
	return {"id":"RENDER_CACHE", "bounds":[24,20], "rooms":[{"id":"room", "x":12,"z":10,"w":20,"d":18}], "walls":[],"doors":[],"props":[], "units":[{"id":"alpha","x":4.0,"z":10.0,"hp":100.0,"facing":0.0,"commands":[{"type":"MOVE","state":"PENDING","args":{"target":[8.0,10.0]},"path":[[4.0,10.0],[8.0,10.0]]}]}],"enemies":[],"civilians":[]}

## Fog is one layer, never a per-mesh overlay: no world/actor/overlay mesh may carry material_overlay.
func overlays_absent(node: Node) -> bool:
	if node is GeometryInstance3D and (node as GeometryInstance3D).material_overlay != null: return false
	for child in node.get_children():
		if not overlays_absent(child): return false
	return true

func fog_matches(world: Node, revealed: bool) -> bool:
	var layer: MeshInstance3D = world._fog_layer
	if not is_instance_valid(layer) or layer.material_override != world._fog_material or layer.get_parent() != world: return false
	if not (overlays_absent(world._world) and overlays_absent(world._actors) and overlays_absent(world._marks)): return false
	return layer.visible == (not revealed) and world._observation_revealed == revealed

func _run() -> void:
	root.size = Vector2i(1440,900)
	var world := ProbeWorld.new()
	root.add_child(world)
	world.build(fixture())
	var state := {"units":fixture().units,"doors":[],"enemies":[],"civilians":[],"events":[],"time":0.0,"tick":0,"presentation_paused":true}
	world.display(state,"alpha",true,0.08)
	check(world.path_draws == 1 and world.cone_draws == 1,"First frozen display draws routes and FOV")
	check(world._fog_canvas._mesh == world._memory_canvas._mesh,"Current and remembered sight share one polygon mesh")
	for frame in range(5): world.display(state,"alpha",true,0.08)
	check(world.path_draws == 1 and world.cone_draws == 1,"Unchanged frozen display never rewrites routes or FOV")
	state.units[0].commands[0].args.target = [9.0,10.0]
	state.units[0].commands[0].path[1] = [9.0,10.0]
	world.display(state,"alpha",true,0.08)
	check(world.path_draws == 2,"In-place command edit at the same clock redraws routes")
	world.set_selected_waypoint("alpha",0)
	world.display(state,"alpha",true,0.0)
	check(world.path_draws == 3,"Waypoint selection at the same clock redraws routes")
	world.zoom(-1.0)
	world.display(state,"alpha",true,0.08)
	check(world.path_draws == 4,"Zoom redraws routes to preserve their pixel thickness")
	state.settings = {"line_width":1.7,"language":"en","palette":"tritan","fov":false}
	world.display(state,"alpha",true,0.08)
	check(world.path_draws == 5,"Line width, language and palette changes invalidate frozen routes")
	check(world.cone_draws == 2 and world._cone_mesh.get_surface_count() == 0,"FOV disable clears the cached cone")
	world.display(state,"",true,0.0)
	check(world.path_draws == 6 and world.cone_draws == 3,"Selection change updates frozen overlays immediately")
	check(fog_matches(world,false),"Normal display keeps one visible fog layer and no per-mesh overlay")
	state.presentation_reveal = true
	world.display(state,"alpha",true,0.08)
	check(fog_matches(world,true),"Reveal hides the fog layer")
	state.presentation_reveal = false
	world.display(state,"alpha",true,0.08)
	check(fog_matches(world,false),"Disabling reveal restores the fog layer")
	state.presentation_mode = "MENU"
	world.display(state,"alpha",true,0.08)
	check(fog_matches(world,true),"Menu hides the fog layer")
	state.presentation_mode = "PLANNING"
	world.display(state,"alpha",true,0.08)
	check(fog_matches(world,false),"Leaving menu restores the fog layer")
	state.result = {"success":true}
	world.display(state,"alpha",true,0.08)
	# P3 preserves observation limits after completion; RESULT is not reveal.
	check(fog_matches(world,false),"Result preserves the fog layer")
	state.result = {}
	state.time = 1.0
	state.tick = 30
	world.display(state,"alpha",true,0.08)
	state.time = 0.0
	state.tick = 0
	var cone_before := world.cone_draws
	world.display(state,"alpha",true,0.0)
	check(world.cone_draws == cone_before + 1,"Rewind invalidates FOV even if the rebuilt field revision repeats")
	check(fog_matches(world,false),"Rewind preserves hidden observation state")
	var room_mask: Array = world._room_seen_mask.room
	room_mask.fill(true)
	# P3 seeks restore recorded observed room control, independent of deaths.
	world._resync_room_cleared({"room_states":{"room":{"state":"MARKED","observed":true,"changed_tick":15,"changed_at":0.5}},"neutralized_ids":["old"],"events":[],"enemies":[{"id":"old","x":12.0,"z":10.0,"hp":0.0}]})
	check(world._room_cleared.room,"Seek restores observed room control outside the recent event window")
	world._resync_room_cleared({"neutralized_ids":[],"events":[],"enemies":[{"id":"old","x":12.0,"z":10.0,"hp":0.0}]})
	check(not world._room_cleared.room,"Earlier seek does not import future neutralization from the entity snapshot")
	var burst: Array = []
	for index in range(50): burst.append({"seq":index+1,"type":"CONTACT","time":2.0,"to":[12.0,10.0]})
	state.presentation_events = burst
	state.events = burst.slice(10)
	state.time = 2.0
	state.tick = 60
	world.display(state,"alpha",false,0.08)
	check(world._flashes.size() == 50,"A continuous slow replay frame displays all 50 new events beyond the HUD window")
	world.display(state,"alpha",false,0.08)
	check(world._flashes.size() == 50,"Repeating the event batch never emits duplicate flashes")
	state.presentation_reset = true
	state.presentation_event_cursor = 50
	state.presentation_events = []
	world.display(state,"alpha",true,0.08)
	check(world._flashes.is_empty(),"Explicit replay seek clears prior flashes without replaying recent HUD events")
	state.presentation_reset = false
	state.presentation_events = [{"seq":51,"type":"DOOR_ACTION","time":2.0,"from":[12.0,10.0],"radius":4.0}]
	world.display(state,"alpha",false,0.08)
	check(world._door_sound_events.size() == 1,"A public door sound outside the HUD window gets its visual ring")
	state.presentation_events = []
	state.time = 2.2
	world.display(state,"alpha",false,0.08)
	check(world._door_sound_events.size() == 1,"Door sound rings persist through subsequent empty event batches")
	state.time = 3.21
	world.display(state,"alpha",false,0.08)
	check(world._door_sound_events.is_empty(),"Door sound rings expire at the original 1.2 second lifetime")
	state.time = 2.3
	state.presentation_events = [{"seq":52,"type":"DOOR_ACTION","time":2.3,"from":[12.0,10.0],"radius":4.0}]
	world.display(state,"alpha",false,0.08)
	state.presentation_reset = true
	state.presentation_events = []
	world.display(state,"alpha",true,0.08)
	check(world._door_sound_events.is_empty(),"Explicit seek clears sounds from the prior presentation timeline")
	world.free()
	await _test_static_batches()
	await _test_fog_and_shadow_contract()
	for failure: String in failures: push_error(failure)
	print("BREACH_RENDER_OPTIMIZATION_RESULT checks=%d failures=%d" % [checks,failures.size()])
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _test_static_batches() -> void:
	var world := World.new()
	root.add_child(world)
	var mission := fixture()
	mission.props = [{"type":"chair","x":6.0,"z":6.0,"w":0.8,"d":0.8},{"type":"chair","x":8.0,"z":6.0,"w":0.8,"d":0.8}]
	world.build(mission)
	await process_frame
	var furniture_batches := 0
	for batch: MultiMeshInstance3D in world._world.find_children("*","MultiMeshInstance3D",true,false):
		if batch.multimesh.mesh.get_surface_count() == 2:
			furniture_batches += 1
			check(batch.multimesh.instance_count == 2,"Legacy furniture is instanced together")
			for surface in range(2):
				var material: StandardMaterial3D = batch.multimesh.mesh.surface_get_material(surface)
				check(material != null and is_equal_approx(material.roughness,1.0),"Legacy furniture retains each palette surface override")
	check(furniture_batches == 1,"Legacy map has one repeated-chair batch")
	mission.schema_version = 2
	mission.bounds = [256,192]
	mission.rooms = []
	mission.props = [{"type":"chair","x":5.0,"z":8.0,"w":0.8,"d":0.8},{"type":"chair","x":6.0,"z":8.0,"w":0.8,"d":0.8},{"type":"chair","x":130.0,"z":8.0,"w":0.8,"d":0.8},{"type":"chair","x":131.0,"z":8.0,"w":0.8,"d":0.8}]
	world.build(mission)
	await process_frame
	furniture_batches = 0
	var instance_positions: Array[float] = []
	for batch: MultiMeshInstance3D in world._world.find_children("*","MultiMeshInstance3D",true,false):
		if batch.multimesh.mesh.get_surface_count() != 2: continue
		furniture_batches += 1
		check(batch.multimesh.instance_count == 4,"Distant repeated furniture remains in one material batch")
		# The dummy headless renderer does not retain MultiMesh transforms.
		if DisplayServer.get_name() == "headless": continue
		for index in range(batch.multimesh.instance_count):
			var position := batch.multimesh.get_instance_transform(index).origin
			instance_positions.append(position.x)
	check(furniture_batches == 1,"Distant repeated furniture creates one batch")
	instance_positions.sort()
	if DisplayServer.get_name() != "headless": check(instance_positions.size() == 4,"All authored furniture instances survive batching")
	if instance_positions.size() == 4:
		# MultiMesh stores its transforms in float32, including the 130m origin.
		check(absf(instance_positions[1]-instance_positions[0]-1.0) < 0.0001 and absf(instance_positions[2]-instance_positions[0]-125.0) < 0.0001,"Batches preserve authored furniture positions " + str(instance_positions))
	world.free()

func _test_fog_and_shadow_contract() -> void:
	var world := World.new()
	root.add_child(world)
	var mission := fixture()
	mission.walls = [{"x":12.0,"z":4.0,"w":6.0,"d":0.2}]
	mission.props = [{"type":"chair","x":6.0,"z":6.0,"w":0.8,"d":0.8},{"type":"chair","x":8.0,"z":6.0,"w":0.8,"d":0.8},{"type":"table","x":10.0,"z":8.0,"w":1.4,"d":0.9},{"type":"rug","x":14.0,"z":8.0,"w":2.0,"d":1.4}]
	world.build(mission)
	await process_frame
	var sun: DirectionalLight3D = world.get_node("AfternoonKey")
	check(not sun.shadow_enabled,"Mission world renders no realtime sun shadow")
	check(world._fog_layer.get_parent() == world and world._fog_material.render_priority == world.FOG_PRIORITY,"One fog layer sits at the fog sort priority")
	check(world._fog_layer.mesh is QuadMesh and world._fog_layer.material_override == world._fog_material,"The fog layer is a single full-screen multiply quad")
	check(world.OVERLAY_PRIORITY > world.FOG_PRIORITY and world.LABEL_OUTLINE_PRIORITY > world.OVERLAY_PRIORITY and world.LABEL_PRIORITY > world.LABEL_OUTLINE_PRIORITY,"Overlays, label halos and label glyphs sort after the fog layer in that order")
	var caps := 0
	var blobs := 0
	var blob_batches := 0
	for node: GeometryInstance3D in world._world.find_children("*","GeometryInstance3D",true,false):
		var material := node.material_override as BaseMaterial3D
		if node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh.mesh == world._blob_mesh:
			blob_batches += 1
			check((node as MultiMeshInstance3D).multimesh.instance_count == 3,"Chairs and table share one contact-shadow batch; the rug has none")
			check(node.material_override == world._blob_material,"All contact shadows share one material")
		elif node is MeshInstance3D and (node as MeshInstance3D).mesh == world._blob_mesh:
			blobs += 1
		if node.has_meta("fog_exempt"):
			caps += 1
			check(material != null and material.render_priority >= world.OVERLAY_PRIORITY,"fog_exempt geometry sorts after the fog layer")
			check(material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED,"fog_exempt geometry draws in the pass that follows the fog layer")
	check(caps > 0,"The fixture wall contributes fog_exempt cap geometry")
	check(blob_batches == 1 and blobs == 0,"Contact shadows merge into exactly one MultiMesh")
	var overlay_label: Label3D = world._label("x",Color.WHITE,32,0.01)
	check(overlay_label.render_priority == world.LABEL_PRIORITY and overlay_label.outline_render_priority == world.LABEL_OUTLINE_PRIORITY,"Labels draw their halo then glyph over actor discs and bodies")
	var state := {"units":mission.units,"doors":[],"enemies":[],"civilians":[],"events":[],"time":0.0,"tick":0,"presentation_paused":true}
	world.display(state,"alpha",true,0.08)
	var actor_surfaces := 0
	for node: MeshInstance3D in world._actors.find_children("*","MeshInstance3D",true,false):
		for surface in range(node.mesh.get_surface_count()):
			var actor_material := node.get_active_material(surface) as BaseMaterial3D
			if actor_material == null: continue
			actor_surfaces += 1
			check(actor_material.render_priority < world.FOG_PRIORITY and actor_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,"Actor surfaces stay in their natural opaque pass")
	check(actor_surfaces > 0,"The actor exposes materials for the opaque-pass check")
	check(int(world._fog_material.get_shader_parameter("actor_count")) == 1,"Fog brightens a bubble around each displayed actor")
	check(world._material(Color("123456"),true).render_priority < world.FOG_PRIORITY and world._material(Color("123456"),true,true).render_priority == world.OVERLAY_PRIORITY,"Unshaded is not implicitly fog-exempt; overlay is explicit")
	overlay_label.free()
	world.free()
