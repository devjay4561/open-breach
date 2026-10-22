class_name BreachWorld
extends Node3D
## Presentation only. All enemy nodes originate from the filtered display snapshot.

## RD (plan 2-2 색약 팔레트 / bridge `palette`): operator/threat/path/fx colors
## for 'default'|'deutan'|'protan'|'tritan'. Hex values are kept identical to
## the web CSS tokens (--friendly/--threat/--civilian in web/style.css
## body[data-palette=...]) so the 3D render and the HUD agree. deutan/protan
## share one blue-friendly/amber-threat scheme (both are red-green
## deficiencies); tritan swaps to an orange-friendly/magenta-threat/teal-
## civilian scheme since it confuses blue and yellow instead.
const PALETTES: Dictionary = {
	"default": {"unit": ["a1d6c3", "92b9e3", "d2bc87", "c2a5d4"], "enemy": "e3483b", "civilian": "cbb588", "door": "dd9566", "signal": {"A": "f0c75e", "B": "74cbd6", "C": "c79ee0"}},
	"deutan": {"unit": ["3fa7ff", "79c4ff", "1f6fb8", "bcdcff"], "enemy": "ffb000", "civilian": "c9a6ff", "door": "caa06a", "signal": {"A": "ffe29a", "B": "3fa7ff", "C": "c9a6ff"}},
	"protan": {"unit": ["3fa7ff", "79c4ff", "1f6fb8", "bcdcff"], "enemy": "ffb000", "civilian": "c9a6ff", "door": "caa06a", "signal": {"A": "ffe29a", "B": "3fa7ff", "C": "c9a6ff"}},
	"tritan": {"unit": ["ff7a3d", "ffa36b", "d85f22", "ffc79e"], "enemy": "e4457e", "civilian": "3fd6c9", "door": "c9643a", "signal": {"A": "ff9f6b", "B": "e4457e", "C": "3fd6c9"}},
}
var UNIT_COLORS := [Color("a1d6c3"), Color("92b9e3"), Color("d2bc87"), Color("c2a5d4")]
const INK := Color("263033")
const PALE := Color("e6e1cc")
var DOOR_COLOR := Color("dd9566")
var SIGNAL_COLORS := {"A": Color("f0c75e"), "B": Color("74cbd6"), "C": Color("c79ee0")}
## Threat/civilian marker colors (plan 2-2); were inline literals in
## _make_actor, now palette-swappable alongside the colors above.
var ENEMY_COLOR := Color("e3483b")
var CIVILIAN_COLOR := Color("cbb588")
var _palette_name := "default"
## RD (plan 2-5 영어 문자열 분리): `settings.language` ('ko'|'en') switches the
## Godot-rendered 3D labels (route badges, door labels, unit/enemy/civilian
## status text, hover-hint labels) to English. Room names in game/data/*.json
## are already authored in English (e.g. "01 / ENTRY") so no lookup is needed
## for those. Keyed by the exact Korean source text rather than a code, since
## these strings never leave the engine (contrast with the `kind` codes main.gd
## sends to the web event log for its own messages).
var _language := "ko"
const TRANSLATIONS: Dictionary = {
	"대기": "WAIT", "열기": "OPEN", "표적 · 반격 없음": "TARGET · NO RETURN FIRE",
	"투항 · 체포 필요": "SURRENDERED · ARREST NEEDED", "체포 완료": "ARRESTED",
	"공황 · 확보 필요": "PANIC · SECURE NEEDED", "호송 · %s": "ESCORT · %s",
	"재장전": "RELOAD", "통로 대기": "BLOCKED", "문 열기": "OPENING DOOR", "문 대기": "WAITING ON DOOR",
	"기절 %.1f초": "STUN %.1fs",
	"확보": "SECURE", "체포": "ARREST", "연막": "SMOKE", "섬광": "STUN",
	"↗ 열기": "↗ OPEN", "열고 섬광": "OPEN + FLASH", "카메라": "CAMERA", "무기 전환": "SWITCH WEAPON", "폭발 대기": "WAIT FOR FLASH", "◉ 카메라": "◉ CAMERA", "↯ 차기": "↯ KICK", "◉ 보기": "◉ PEEK", "✓ 확보": "✓ SECURE",
	"→ 호송": "→ ESCORT", "✓ 체포": "✓ ARREST", "↻ 장전": "↻ RELOAD", "→ 주시": "→ FACE",
	"◷ 대기": "◷ WAIT", "A 신호": "SIGNAL A",
	"산탄 돌파": "SHOTGUN BREACH",
	"진입 드릴": "ENTRY DRILL", "짧은 방": "SHORT ROOM", "깊이 진입": "GO LONG",
	"회수": "RECOVER", "무력화": "DISABLE", "확인": "INSPECT", "탑승": "BOARD", "완료": "COMPLETE",
	"교전": "CONTACT", "지배": "DOMINATED", "정리": "CLEAR", "표식": "MARKED",
	"이상 없음": "CLEAR", "방 정리 완료": "ROOM CLEAR", "재장전 중": "RELOADING", "사격 준비": "GUN UP", "대원 부상": "MAN DOWN",
	"문 조작 대원이 행동 불능이 되어 진입을 안전하게 중단했습니다": "Entry was halted safely because the door operator became incapacitated.",
	"사상자 발생 후 진입 재편성": "Entry reformed after a casualty.",
	"사상자 발생 후 진입 지점을 안전하게 재편성할 수 없습니다": "Entry positions cannot be reformed safely after a casualty.",
	"파편": "FRAG", "인접 벽 정보 없음": "No adjacent wall information",
	"미지정 재질": "Unspecified material", "얇은 벽": "Thin wall",
	"소총 관통 가능": "Rifle penetrable", "소총 관통 불가": "Rifle blocked",
	"목재": "Wood", "유리": "Glass", "석고": "Plaster", "금속": "Metal", "벽돌": "Brick", "콘크리트": "Concrete", "천": "Fabric", "식생": "Foliage",
}
const ROOM_STATE_LABELS := {"CONTACT": "교전", "DOMINATED": "지배", "CLEAR": "정리", "MARKED": "표식"}
const CALL_LABELS := {"CALL_CLEAR": "이상 없음", "CALL_ROOM_CLEAR": "방 정리 완료", "CALL_SHORT_ROOM": "짧은 방", "CALL_RELOADING": "재장전 중", "CALL_GUN_UP": "사격 준비", "CALL_MAN_DOWN": "대원 부상"}
const CALL_LABEL_SECONDS := 1.2

func _t(text: String) -> String:
	return str(TRANSLATIONS.get(text, text)) if _language == "en" else text
## Extra clearance (viewport px) kept between the mission frame and the raw
## safe-area rectangle so the frame never sits flush against the HTML panels.
const SAFE_AREA_MARGIN_PX: float = 16.0
## Menu diorama drift: slow orbit angular speed (rad/s) and radius as a
## fraction of camera.size, disabled under reduced motion.
const MENU_DRIFT_SPEED: float = 0.02
const MENU_DRIFT_RADIUS_FRACTION: float = 0.045
## Plan 2-1 combat fx (presentation only, derived from the same state.events
## list _update_effects already reads for shot/stun flashes): breach shake,
## room_clear floor flash and the mission_end freeze-frame hold.
const SHAKE_DURATION: float = 0.15
const SHAKE_MAGNITUDE: float = 0.14
const MISSION_END_FREEZE: float = 0.4
## Phase 2 world-space hit feedback. Everything below is derived from observed events
## plus the presentation clock and drawn into the shared `_event_mesh` (no extra nodes).
const TRACER_TRAVEL: float = 0.05 # muzzle-to-target flight
const TRACER_LIFE: float = 0.09 # tail catches the head: fully gone
const TRACER_STREAK: float = 2.6 # visible streak length while in flight (m)
## Every target-side reaction (burst, confirm ring, impact puff, kill stamp, camera kick) starts when the
## tracer ARRIVES, never at the trigger pull. Single source of truth: `_hit_reaction_delay()` =
## HIT_REACTION_DELAY (50 ms) scaled by REDUCED_FLASH_TIMING (0.7 -> 35 ms) under reduced flash.
const HIT_REACTION_DELAY: float = TRACER_TRAVEL
const REDUCED_FLASH_TIMING: float = 0.7
const MISS_OVERRUN_MIN: float = 1.5
const MISS_OVERRUN_SPAN: float = 1.0
const BURST_LIFE: float = 0.16
const SPARK_LIFE: float = 0.12
const STAMP_POP: float = 0.06
const STAMP_SETTLE: float = 0.15
const STAMP_LIFE: float = 0.8
const MUZZLE_POP: float = 0.03
const MUZZLE_FLOOR_LIGHT: float = 0.05
## Phase 3: casualty kicks are 4x the phase-2 values (they measured ~1 px, imperceptible). Directional kicks
## are additionally clamped on screen to the safe-area margin (see `_current_kick_offset`).
const KILL_KICK_DURATION: float = 0.09 # 70 ms left only three non-zero 60 fps frames at 4x
const KILL_KICK_MAGNITUDE: float = SHAKE_MAGNITUDE / 3.0 * 4.0
const DOWN_KICK_DURATION: float = 0.12
const DOWN_KICK_MAGNITUDE: float = SHAKE_MAGNITUDE * 0.7 * 4.0
const ROOM_CLEAR_FLASH_DURATION: float = 0.6
## H1 fix: a room only reads as "observed" once at least this fraction of its
## floor sample grid has ever been inside current sight, or its center is in
## sight right now (is_room_sufficiently_observed below).
const ROOM_OBSERVED_FRACTION: float = 0.6
const ROOM_SAMPLE_STEP: float = 1.0

const VisibilityField = preload("res://scripts/visibility_field.gd")
const Navigation = preload("res://scripts/navigation.gd")
const EquipmentCatalog = preload("res://scripts/equipment_catalog.gd")
var _visibility = VisibilityField.new()
var _preview_nav = Navigation.new()
var _flash_projectile_nodes: Dictionary = {}
var _frag_projectile_nodes: Dictionary = {}
var _glass_pane_nodes: Dictionary = {}
var _glass_door_surfaces: Dictionary = {}
var _operator_preview_layer: CanvasLayer
var _operator_preview_container: SubViewportContainer
var _operator_preview_viewport: SubViewport
var _operator_preview_visual: Dictionary = {}
var _fog_material: ShaderMaterial
const VisibilityMask = preload("res://scripts/visibility_mask.gd")
var _fog_viewport: SubViewport
var _memory_viewport: SubViewport
var _fog_canvas: Node2D
var _memory_canvas: Node2D
var _fog_time: float = -1.0
var _fog_layer: MeshInstance3D
var _observation_revealed := false
# Fog is ONE full-screen multiply pass in the transparent pass (render_priority
# FOG_PRIORITY) instead of a material_overlay on every world mesh. It rebuilds each
# opaque pixel's true world XZ from the depth buffer, so tall props and elevated
# decks are fogged at their real position. Actors stay opaque and are kept bright by
# a small bubble around each displayed actor (see observation.gdshader). Only real
# overlays (marks, wall caps, plates, backdrop) sort after the fog.
const FOG_PRIORITY := 1
const OVERLAY_PRIORITY := 2
const LABEL_OUTLINE_PRIORITY := 3 # strictly below the glyph so the halo never covers it
const LABEL_PRIORITY := 4
const FOG_ACTOR_LIMIT := 24
## A newly visible enemy waits (at most this long) until the fog polygons actually cover it, so it never stands
## on a still-unlit floor. Root cause is a stale PUBLIC door state (see first_sighting_probe.gd); the sim has
## already engaged, so information is never withheld longer than this.
const SIGHTING_GRACE := 0.12
const SIGHTING_MEMORY := 0.5 # a dropped sighting is remembered this long: flicker never re-holds a shown enemy
const DOOR_RECENT := 0.5 # a public door counts as "recently moved" this long after its progress last changed
const DOOR_LINE_MARGIN := 1.8 # a moving door this close to the unit->enemy line can explain a stale fog
const POOL_RADIUS := 1.3
const POOL_RAYS := 20
const POOL_CORE := 0.5 # fraction of the fan radius that is fully lit before the soft falloff
const COVER_OFFSETS: Array[Vector2] = [Vector2.ZERO, Vector2(0.3, 0.0), Vector2(-0.3, 0.0), Vector2(0.0, 0.3), Vector2(0.0, -0.3)]
var _blob_mesh: ArrayMesh
var _blob_material: StandardMaterial3D

var camera: Camera3D
var _mission: Dictionary = {}
var _state: Dictionary = {}
var _world: Node3D
var _actors: Node3D
var _marks: Node3D
var _entity_nodes: Dictionary = {}
var _ghost_nodes: Dictionary = {}
var _effect_time := 0.0
var _door_nodes: Dictionary = {}
var _interactive_target_nodes: Dictionary = {}
var _materials: Dictionary = {}
var _label_font: FontVariation
var _box_mesh: BoxMesh
var _cylinder_mesh: CylinderMesh
var _sphere_mesh: SphereMesh
var _path_mesh: ImmediateMesh
var _prior_attempt_mesh: ImmediateMesh
var _prior_attempt_node: MeshInstance3D
var _prior_attempt: Dictionary = {}
var _prior_attempt_visible: bool = true
var _cone_mesh: ImmediateMesh
var _event_mesh: ImmediateMesh
var _interaction_mesh: ImmediateMesh
var _door_frame_mesh: ImmediateMesh
var _drill_mesh: ImmediateMesh
var _drill_mesh_node: MeshInstance3D
var _drill_preview: Dictionary = {}
var _formation_preview: Dictionary = {}
var _drill_draw_inputs: Array = []
var _drill_labels: Array[Label3D] = []
var _smoke_mesh: ImmediateMesh
var _sound_mesh: ImmediateMesh
## RD (plan 2-3 게임패드): the virtual map cursor the left stick drives.
var _gamepad_mesh: ImmediateMesh
var _smoke_nodes: Array[Dictionary] = []
var _door_sound_events: Array[Dictionary] = []
var _sound_mark_time := -1.0
var _interaction_label: Label3D
var _interaction: Dictionary = {}
var _interaction_dirty: bool = true
var _selected_waypoint: int = -1
var _waypoint_unit: String = ""
var _waypoint_nodes: Array[Label3D] = []
var _focus := Vector2(12.0, 10.0)
var _pan := Vector2.ZERO
var _zoom := 1.0
var _view_size := Vector2.ZERO
var _selected := ""
var _selected_units: Array = []
var _clock := 0.0
var _draw_timer := 0.0
var _last_tick := -1
var _paused_path_inputs: Array = []
var _cone_inputs: Array = []
var _line_width := 1.0
var _menu_preview := false
var _menu_drift_time := 0.0
## Survey-mark corner ticks and the "INSERTION // 01" caption read as tactical
## map chrome during gameplay but make the menu diorama look like a framed
## picture instead of a full-bleed background. Hidden while _menu_preview.
var _chrome_nodes: Array[Node3D] = []
var _show_fov := true
var _show_facing := true
var _motion_reduced := false
var _flash_reduced := false
var _bounds := Vector2(24.0, 20.0)
var _frame_rect := Rect2(0, 0, 24, 20)
var _ui_scale := 1.0
var _obstacles: Array[Rect2] = []
var _elevated_surfaces: Array[Dictionary] = []
var _safe_area: Dictionary = {}
var _last_event_seq := -1
var _flashes: Array[Dictionary] = []
var _sprite_pool: Array[Sprite3D] = []
const EFFECT_SPRITE_POOL := 24
var _screen_shake_enabled := true
var _shake_remaining := 0.0
var _shake_duration := SHAKE_DURATION
var _shake_magnitude := SHAKE_MAGNITUDE
var _shake_direction := Vector2.ZERO # ZERO = breach-style random jitter; else a directional kick
var _last_shot_direction := Vector2.ZERO
var _last_hit_shot := {"time": -1.0, "to": Vector2(-1000.0, -1000.0)}
var _seen_signature := 0
var _cover_cache: Dictionary = {} # enemy id -> [fog revision, position, covered]
var _held_enemies: Dictionary = {} # enemies currently held back by the sighting grace: nothing of theirs is drawn
var _fog_pools: Dictionary = {} # displayed enemies the sight polygons do not cover: id -> position of their local sight fan
var _pool_polygons: Array[PackedVector2Array] = [] # the fans last drawn (CurrentSight only), world coordinates
var _pool_node: MeshInstance2D
var _pool_mesh := ArrayMesh.new()
var _pool_rings: Dictionary = {} # enemy id -> {key, ring, centre}
var _pool_rebuilds := 0 # mesh rebuilds (CurrentSight re-renders); a test hook for the 30 Hz throttle
var _sighting: Dictionary = {} # enemy id -> {since, waited, cleared, last_seen}
var _door_motion: Dictionary = {} # public door id -> {progress, moved_at}
var _remembered_bodies: Dictionary = {} # neutralized enemies drawn from memory (fogged, never in the actor bubble)
var _last_observed_gear: Dictionary = {} # enemy id -> loadout last seen while visible (the memory record carries none)
var _neutralized_at: Dictionary = {} # enemy id -> public position of its INCAPACITATED/ARREST event
var _casualty_hold: Dictionary = {} # entity id -> event time; keeps a shot-down actor's disc until the tracer lands
var _freeze_remaining := 0.0
## Authored geometry and observed simulation control. No second kill/room
## predicate: the floor exploration grid below remains visibility only.
var _room_threat_map: Dictionary = {}
var _room_cleared: Dictionary = {}
var _room_state_labels: Dictionary = {}
var _room_control_inputs: Array = []
var _call_events: Dictionary = {}
## Existing death-event bookkeeping remains independent of room control.
var _room_neutralized_ids: Dictionary = {}
var _room_clear_flashes: Array[Dictionary] = []
## H1 fix: per-room floor sample grid (world-space points) and a parallel
## "has this point ever been in current sight" mask, accumulated over the
## whole mission so room_observed_fraction reflects everything explored so
## far, not just the current frame's sight polygons.
var _room_sample_points: Dictionary = {}
var _room_seen_mask: Dictionary = {}
var _room_seen_count: Dictionary = {}
var _elevated_rooms: Array = []
var _shake_offset := Vector3.ZERO
var _freeze_zoom_factor := 1.0
## L2 fix: the camera position/size _fit_camera() last computed, before the
## per-frame shake/freeze-zoom are layered on top. Shake/zoom are derived
## from these every frame instead of incrementally undoing/redoing a prior
## frame's offset, so a _fit_camera() call mid-shake/zoom (resize, pan, zoom)
## can never leave a stale offset baked into camera.position/size.
var _camera_base_position := Vector3.ZERO
var _camera_base_size := 1.0
const SMOKE_TEXTURE = preload("res://assets/vfx/smoke_05.png")
const DoorGeometry = preload("res://scripts/door_geometry.gd")
const ActorVisual = preload("res://scripts/actor_visual.gd")
const EnvironmentAssets = preload("res://scripts/environment_assets.gd")
const HistoricalAssets = preload("res://scripts/historical_assets.gd")
const Spatial = preload("res://scripts/spatial_profile.gd")
const FLASH_TEXTURE = preload("res://assets/vfx/fire_01.png")

func _ready() -> void:
	_label_font = FontVariation.new()
	_label_font.base_font = preload("res://assets/fonts/NotoSansKR.ttf")
	_label_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 650.0}
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3.ONE
	_cylinder_mesh = CylinderMesh.new()
	_cylinder_mesh.top_radius = 1.0
	_cylinder_mesh.bottom_radius = 1.0
	_cylinder_mesh.height = 1.0
	_cylinder_mesh.radial_segments = 12
	_sphere_mesh = SphereMesh.new()
	_sphere_mesh.radius = 1.0
	_sphere_mesh.height = 2.0
	_sphere_mesh.radial_segments = 12
	_sphere_mesh.rings = 6
	camera = Camera3D.new()
	camera.name = "TacticalCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 140.0
	camera.current = true
	add_child(camera)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("172123")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b1c3c0")
	env.ambient_light_energy = 0.58
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "AfternoonKey"
	sun.rotation_degrees = Vector3(-53, -32, 0)
	sun.light_color = Color("fff0d6")
	# Compat renders an unshadowed sun ~half as bright as a shadowed one, so energy is raised to keep the look.
	sun.light_energy = 1.9
	# No realtime shadows: furniture gets a cheap batched contact blob instead (_build_contact_shadow).
	sun.shadow_enabled = false
	add_child(sun)

func build(mission: Dictionary) -> void:
	_mission = mission.duplicate(true)
	_prior_attempt.clear()
	_elevated_surfaces.clear()
	_elevated_rooms.clear()
	for room: Dictionary in mission.get("rooms", []):
		var offset := float(room.get("base_height", 0.0))
		if offset > 0.0:
			_elevated_rooms.append(room)
			_elevated_surfaces.append({"rect": _rect_from(room), "offset": offset})
	_state = {}
	_drill_preview.clear()
	_formation_preview.clear()
	_drill_draw_inputs.clear()
	_drill_labels.clear()
	_selected_units.clear()
	_interaction = {}
	_selected_waypoint = -1
	_waypoint_unit = ""
	_interaction_dirty = true
	_entity_nodes.clear()
	_ghost_nodes.clear()
	_effect_time = 0.0
	_door_nodes.clear()
	_interactive_target_nodes.clear()
	_waypoint_nodes.clear()
	_smoke_nodes.clear()
	_door_sound_events.clear()
	_sound_mark_time = -1.0
	_obstacles.clear()
	_clear_flashes()
	_chrome_nodes.clear()
	_last_event_seq = -1
	_last_tick = -1
	_paused_path_inputs.clear()
	_cone_inputs.clear()
	_observation_revealed = false
	_shake_remaining = 0.0
	_freeze_remaining = 0.0
	_reset_hit_links()
	_reset_sightings() # seeks reset sightings before the enemy loop (`resetting`); a new mission must do it explicitly
	_seen_signature = 0
	_door_motion.clear()
	_pool_rings.clear()
	_pool_mesh.clear_surfaces()
	_remembered_bodies.clear()
	_last_observed_gear.clear()
	_neutralized_at.clear()
	_room_clear_flashes.clear()
	_room_state_labels.clear()
	_room_control_inputs.clear()
	_call_events.clear()
	_glass_pane_nodes.clear()
	_glass_door_surfaces.clear()
	_flash_projectile_nodes.clear()
	_frag_projectile_nodes.clear()
	_build_room_threat_map(mission)
	for node in [_world, _actors, _marks]:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	_world = Node3D.new()
	_world.name = "Architecture"
	add_child(_world)
	_actors = Node3D.new()
	_actors.name = "ObservedEntities"
	add_child(_actors)
	_marks = Node3D.new()
	_marks.name = "TacticalOverlay"
	add_child(_marks)
	var bounds: Array = mission.get("bounds", [24, 20])
	_bounds = Vector2(float(bounds[0]), float(bounds[1]))
	var focus: Array = mission.get("focus", [_bounds.x * 0.5, _bounds.y * 0.5])
	_focus = Vector2(float(focus[0]), float(focus[1]))
	_frame_rect = Rect2(_focus, Vector2.ZERO)
	for room in mission.get("rooms", []):
		_frame_rect = _frame_rect.merge(_rect_from(room))
	for wall in mission.get("walls", []):
		_frame_rect = _frame_rect.merge(_rect_from(wall))
	for unit in mission.get("units", []):
		_frame_rect = _frame_rect.expand(Vector2(float(unit.x), float(unit.z)))
	_frame_rect = _frame_rect.grow_individual(0.75, 0.75, 0.75, 0.8)
	if _is_metre_map():
		# Full-size airfields, compounds and ships keep their complete footprint
		# on reset/Home. Actors keep their physical size when the user zooms in.
		_frame_rect = Rect2(Vector2.ZERO, _bounds).grow(1.0)
	_build_ground()
	for room in mission.get("rooms", []):
		_build_room(room)
	for wall in mission.get("walls", []):
		_build_wall(wall)
	for door in mission.get("doors", []):
		_build_door(door)
	for prop in mission.get("props", []):
		_build_prop(prop)
	for scenery in mission.get("scenery", []):
		HistoricalAssets.create_scenery(_world, scenery)
	for target in mission.get("interactive_targets", []):
		_build_interactive_target(target)
	_sync_interactive_targets(mission.get("interactive_targets", []))
	_batch_static_geometry()
	_visibility.build(mission)
	_preview_nav.build(mission, [])
	for old_viewport in [_fog_viewport, _memory_viewport, _fog_layer]:
		if is_instance_valid(old_viewport):
			remove_child(old_viewport)
			old_viewport.queue_free()
	_fog_viewport = _make_visibility_viewport(false)
	_memory_viewport = _make_visibility_viewport(true)
	_fog_canvas = _fog_viewport.get_child(0)
	_memory_canvas = _memory_viewport.get_child(0)
	# Local sight fans of enemies the polygons do not cover: CurrentSight only, never the exploration memory.
	_pool_node = MeshInstance2D.new()
	_pool_node.name = "SightPools"
	_pool_node.mesh = _pool_mesh
	_fog_viewport.add_child(_pool_node)
	_fog_material = ShaderMaterial.new()
	_fog_material.shader = preload("res://shaders/observation.gdshader")
	_fog_material.set_shader_parameter("observation", _fog_viewport.get_texture())
	_fog_material.set_shader_parameter("exploration", _memory_viewport.get_texture())
	_fog_material.set_shader_parameter("map_size", _visibility.bounds)
	_fog_material.render_priority = FOG_PRIORITY
	_build_fog_layer()
	_fog_time = -1.0
	_path_mesh = ImmediateMesh.new()
	_prior_attempt_mesh = ImmediateMesh.new()
	_prior_attempt_node = MeshInstance3D.new()
	_prior_attempt_node.name = "PriorOwnedAttempt"
	_prior_attempt_node.mesh = _prior_attempt_mesh
	_prior_attempt_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marks.add_child(_prior_attempt_node)
	_prior_attempt_node.visible = false
	_cone_mesh = ImmediateMesh.new()
	_event_mesh = ImmediateMesh.new()
	_interaction_mesh = ImmediateMesh.new()
	_drill_mesh = ImmediateMesh.new()
	_smoke_mesh = ImmediateMesh.new()
	_sound_mesh = ImmediateMesh.new()
	_gamepad_mesh = ImmediateMesh.new()
	_door_frame_mesh = ImmediateMesh.new()
	for entry in [[_door_frame_mesh, "DoorFrames"], [_path_mesh, "Routes"], [_cone_mesh, "FieldOfView"], [_event_mesh, "ActionFeedback"], [_interaction_mesh, "InputPreview"], [_drill_mesh, "RoomDrillPreview"], [_smoke_mesh, "SmokeCoverage"], [_sound_mesh, "SoundObservation"], [_gamepad_mesh, "GamepadCursor"]]:
		var mesh_node := MeshInstance3D.new()
		mesh_node.name = entry[1]
		mesh_node.mesh = entry[0]
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_marks.add_child(mesh_node)
		if entry[0] == _drill_mesh: _drill_mesh_node = mesh_node
	_draw_door_frames()
	_interaction_label = _label("", Color("f4d69b"), 32, 0.008)
	_interaction_label.no_depth_test = true
	_interaction_label.visible = false
	_marks.add_child(_interaction_label)
	reset_camera()

func _make_visibility_viewport(remember: bool) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "ExplorationMemory" if remember else "CurrentSight"
	var pixels_per_metre := 2048.0 / maxf(_visibility.bounds.x, _visibility.bounds.y)
	viewport.size = Vector2i(Vector2(_visibility.bounds * pixels_per_metre).ceil())
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE if remember else SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	viewport.add_child(VisibilityMask.new())
	return viewport

func _build_fog_layer() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0) # the vertex shader writes clip space directly: one full-screen triangle pair
	_fog_layer = MeshInstance3D.new()
	_fog_layer.name = "ObservationFog"
	_fog_layer.mesh = quad
	_fog_layer.material_override = _fog_material
	_fog_layer.extra_cull_margin = 16384.0 # never frustum-culled
	_fog_layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fog_layer.visible = not _observation_revealed
	add_child(_fog_layer)

## Actors are opaque and always in their own sight, but the cone only starts at the unit, so the
## shader brightens the above-floor pixels (disc, body, gear) near every displayed actor instead of exempting their meshes.
func _update_fog_actors() -> void:
	var discs := PackedVector4Array()
	for id: String in _entity_nodes:
		if discs.size() >= FOG_ACTOR_LIMIT: break
		if _remembered_bodies.has(id): continue
		var entry: Dictionary = _entity_nodes[id]
		var node: Node3D = entry.node
		if is_instance_valid(node) and node.visible: discs.append(Vector4(node.position.x, node.position.z, node.position.y, 0.0))
	var count := discs.size()
	discs.resize(FOG_ACTOR_LIMIT)
	_fog_material.set_shader_parameter("actors", discs)
	_fog_material.set_shader_parameter("actor_count", count)

func _set_observation_revealed(revealed: bool) -> void:
	if _observation_revealed == revealed:
		return
	_observation_revealed = revealed
	_fog_layer.visible = not revealed

## Sorts a material after the fog multiply. Opaque ones move to the alpha pass but keep opaque-equivalent depth writes.
func _draw_after_fog(material: BaseMaterial3D) -> void:
	if material.render_priority >= OVERLAY_PRIORITY: return
	if material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	material.render_priority = OVERLAY_PRIORITY

## fog_exempt: stays undarkened (wall caps, plates, backdrop). Shared cached materials are cloned, never mutated.
func _fog_exempt(node: GeometryInstance3D) -> void:
	node.set_meta("fog_exempt", true)
	var source := node.material_override as BaseMaterial3D
	if source == null or source.render_priority >= OVERLAY_PRIORITY: return
	var key := "after_fog:" + str(source.get_instance_id())
	if not _materials.has(key):
		var clone: BaseMaterial3D = source.duplicate()
		_draw_after_fog(clone)
		_materials[key] = clone
	node.material_override = _materials[key]

func _build_ground() -> void:
	if _is_metre_map():
		_build_metre_ground()
		return
	_box(_world, Vector3(_bounds.x * 0.5, -0.47, _bounds.y * 0.5), Vector3(_bounds.x + 60, 0.5, _bounds.y + 60), Color("192326"))
	_box(_world, Vector3(_bounds.x * 0.5, -0.17, _bounds.y * 0.5), Vector3(_bounds.x + 1.2, 0.48, _bounds.y + 1.2), Color("303a3a"))
	_box(_world, Vector3(_bounds.x * 0.5, 0.085, _bounds.y * 0.5), Vector3(_bounds.x + 0.5, 0.04, _bounds.y + 0.5), Color("3e4744"))
	var grid := ImmediateMesh.new()
	grid.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(Color("414943")))
	for x in range(int(_bounds.x) + 1):
		_flat_line(grid, Vector2(x, 0), Vector2(x, _bounds.y), 0.008, 0.112, Color.WHITE)
	for z in range(int(_bounds.y) + 1):
		_flat_line(grid, Vector2(0, z), Vector2(_bounds.x, z), 0.008, 0.112, Color.WHITE)
	grid.surface_end()
	var grid_node := MeshInstance3D.new()
	grid_node.mesh = grid
	grid_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(grid_node)
	# Survey marks set the operation on a measured, physical architectural model.
	# This is tactical-map chrome: during the menu diorama it reads as a framed
	# picture rather than a full-bleed background, so it is hidden whenever
	# _menu_preview is active (see set_menu_preview()). Flagged "dynamic_geometry"
	# so _batch_static_geometry() leaves these as individually toggleable
	# MeshInstance3D nodes instead of sweeping them into a shared, unhideable
	# MultiMeshInstance3D batch with unrelated static boxes of the same color.
	for point in [Vector2(-0.25, -0.25), Vector2(_bounds.x + 0.25, -0.25), Vector2(-0.25, _bounds.y + 0.25), Vector2(_bounds.x + 0.25, _bounds.y + 0.25)]:
		var tick_a := _box(_world, Vector3(point.x, 0.12, point.y), Vector3(0.65, 0.012, 0.035), Color("a4aa91"))
		var tick_b := _box(_world, Vector3(point.x, 0.12, point.y), Vector3(0.035, 0.012, 0.65), Color("a4aa91"))
		tick_a.set_meta("dynamic_geometry", true)
		tick_b.set_meta("dynamic_geometry", true)
		_chrome_nodes.append(tick_a)
		_chrome_nodes.append(tick_b)
	var insertion_label := _label("I N S E R T I O N  / /  0 1", Color("aebba5"), 36, 0.01)
	insertion_label.position = Vector3(_bounds.x * 0.5, 0.15, _bounds.y - 0.45)
	insertion_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	insertion_label.rotation_degrees.x = -90
	_world.add_child(insertion_label)
	_chrome_nodes.append(insertion_label)
	for i in range(4):
		var deploy_tick := _box(_world, Vector3(_bounds.x * 0.5 - 2.0 + i * 1.3, 0.125, _bounds.y - 1.05), Vector3(0.62, 0.015, 0.055), Color("d1bb82"))
		deploy_tick.set_meta("dynamic_geometry", true)
		_chrome_nodes.append(deploy_tick)
	for node in _chrome_nodes:
		node.visible = not _menu_preview

func _is_metre_map() -> bool:
	return int(_mission.get("schema_version", 1)) >= 2

func surface_offset(point: Vector2) -> float:
	return Spatial.floor_base_at(_elevated_rooms, point)

func surface_position(point: Vector2, above_floor: float = 0.2) -> Vector3:
	return Vector3(point.x, surface_offset(point) + above_floor, point.y)

func _build_metre_ground() -> void:
	var environment: Dictionary = _mission.get("environment", {})
	var biome := str(environment.get("biome", "urban"))
	var ground_color := Color(str(environment.get("ground_color", {
		"urban": "68716a", "desert": "b6a17b", "jungle": "66764a",
		"forest": "657050", "mountain": "777c6b", "alpine": "c6d1ce",
		"snow": "ced7d3", "coastal": "9b9d7e", "sea": "647978",
		"industrial": "73776f", "airfield": "848b85",
	}.get(biome, "6f7966"))))
	var water := bool(environment.get("water", false))
	var water_level := float(environment.get("water_level", -0.35)) if water else 0.0
	var backdrop_color := Color("1d4653") if water else ground_color.darkened(0.15)
	var backdrop := _box(_world, Vector3(_bounds.x * 0.5, water_level - 0.25, _bounds.y * 0.5), Vector3(_bounds.x + 600.0, 0.5, _bounds.y + 600.0), backdrop_color)
	backdrop.name = "Sea" if water else "Landscape"
	_fog_exempt(backdrop)
	backdrop.set_meta("dynamic_geometry", true)
	if water:
		# A continuous sea plane sits below the navigable deck/shore. None of
		# these visual streaks grants movement across water.
		var water_lines := ImmediateMesh.new()
		water_lines.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(Color("3c6470"), false, true))
		for index in range(62):
			var x := fposmod(float(index) * 37.7 + 11.0, _bounds.x + 140.0) - 70.0
			var z := fposmod(float(index) * 19.1 + 23.0, _bounds.y + 140.0) - 70.0
			_flat_line(water_lines, Vector2(x, z), Vector2(x + 4.0 + float(index % 7), z + 0.3), 0.045, water_level + 0.018, Color.WHITE)
		water_lines.surface_end()
		var water_node := MeshInstance3D.new()
		water_node.name = "SeaSurfaceRipples"
		water_node.mesh = water_lines
		water_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_fog_exempt(water_node)
		_world.add_child(water_node)
	var areas: Array = _mission.get("walkable_areas", [])
	if areas.is_empty():
		areas = [{"x": _bounds.x * 0.5, "z": _bounds.y * 0.5, "w": _bounds.x, "d": _bounds.y}]
	# A vessel's real hull/deck mesh already defines its visible contour.
	# Drawing its collision envelopes as solid rectangles would turn a bow
	# into a square platform. Keep those envelopes simulation-only.
	if str(environment.get("ground_surface", "")) == "ship_deck":
		_build_scale_bar()
		return
	var grid := ImmediateMesh.new()
	var grid_started := false
	# Five-metre surveying lines give a scale cue without the dense 1m lattice
	# covering a large battlefield. Clip them to each actual land/deck area.
	for area: Dictionary in areas:
		var rect := _rect_from(area)
		var floor := _box(_world, Vector3(rect.get_center().x, 0.09, rect.get_center().y), Vector3(rect.size.x, 0.06, rect.size.y), ground_color)
		floor.name = "WalkableGround"
		var x := ceilf(rect.position.x / 5.0) * 5.0
		while x <= rect.end.x:
			if not grid_started:
				grid.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(ground_color.lightened(0.055)))
				grid_started = true
			_flat_line(grid, Vector2(x, rect.position.y), Vector2(x, rect.end.y), 0.012, 0.125, Color.WHITE)
			x += 5.0
		var z := ceilf(rect.position.y / 5.0) * 5.0
		while z <= rect.end.y:
			if not grid_started:
				grid.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(ground_color.lightened(0.055)))
				grid_started = true
			_flat_line(grid, Vector2(rect.position.x, z), Vector2(rect.end.x, z), 0.012, 0.125, Color.WHITE)
			z += 5.0
	if grid_started:
		grid.surface_end()
		var grid_node := MeshInstance3D.new()
		grid_node.name = "FiveMetreGroundSurvey"
		grid_node.mesh = grid
		grid_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(grid_node)
	_build_scale_bar()

func _build_scale_bar() -> void:
	var length := 20.0 if maxf(_bounds.x, _bounds.y) >= 96.0 else 10.0
	var origin := Vector2(3.0, _bounds.y - 3.0)
	var ruler := ImmediateMesh.new()
	ruler.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(Color("dfdbc0"), true, true))
	_flat_line(ruler, origin, origin + Vector2(length, 0), 0.10, 0.23, Color.WHITE)
	for tick in [0.0, length * 0.5, length]:
		_flat_line(ruler, origin + Vector2(tick, -0.35), origin + Vector2(tick, 0.35), 0.10, 0.23, Color.WHITE)
	ruler.surface_end()
	var ruler_node := MeshInstance3D.new()
	ruler_node.name = "PhysicalMetreScaleBar"
	ruler_node.mesh = ruler
	_fog_exempt(ruler_node)
	ruler_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(ruler_node)
	_chrome_nodes.append(ruler_node)
	var text := _label("0     %d     %d m" % [int(length * 0.5), int(length)], Color("f3eed5"), 36, 0.035)
	text.position = Vector3(origin.x + length * 0.5, 0.24, origin.y - 1.0)
	text.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	text.rotation_degrees.x = -90
	text.no_depth_test = true
	_world.add_child(text)
	_chrome_nodes.append(text)
	for node in _chrome_nodes:
		node.visible = not _menu_preview

func _build_room(room: Dictionary) -> void:
	var floor_offset := float(room.get("base_height", 0.0))
	var pos := Vector3(float(room.x), 0.155 + floor_offset, float(room.z))
	var width := float(room.w)
	var depth := float(room.d)
	var light: float = minf(clampf(float(room.get("lighting", 1.0)), 0.0, 1.0), clampf(float(_mission.get("environment", {}).get("lighting", 1.0)), 0.0, 1.0))
	var base := Color(str(room.get("color", "#716f60"))).darkened(0.18 + (1.0 - light) * 0.42)
	if not bool(room.get("indoor", true)): base = base.lerp(Color("61735a"), 0.18)
	var room_rect := _rect_from(room)
	var floor_rects: Array[Rect2] = [room_rect]
	if _is_metre_map() and not bool(room.get("indoor", true)):
		var walkable: Array = _mission.get("walkable_areas", [])
		if not walkable.is_empty():
			floor_rects.clear()
			for area: Dictionary in walkable:
				var intersection := room_rect.intersection(_rect_from(area))
				if intersection.has_area():
					floor_rects.append(intersection)
		if str(_mission.get("environment", {}).get("ground_surface", "")) == "ship_deck":
			floor_rects.clear()
	# Recessed seam detail, batched in a single mesh per room.
	var seams := ImmediateMesh.new()
	var seams_started := false
	var tile := 5.0 if _is_metre_map() and not bool(room.get("indoor", true)) else 1.15
	for rect: Rect2 in floor_rects:
		_box(_world, Vector3(rect.get_center().x, pos.y, rect.get_center().y), Vector3(rect.size.x, 0.06, rect.size.y), base)
		var x := rect.position.x + tile
		while x < rect.end.x:
			if not seams_started:
				seams.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(base.darkened(0.13)))
				seams_started = true
			_flat_line(seams, Vector2(x, rect.position.y), Vector2(x, rect.end.y), 0.016, 0.189 + floor_offset, Color.WHITE)
			x += tile
		var z := rect.position.y + tile
		while z < rect.end.y:
			if not seams_started:
				seams.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(base.darkened(0.13)))
				seams_started = true
			_flat_line(seams, Vector2(rect.position.x, z), Vector2(rect.end.x, z), 0.016, 0.189 + floor_offset, Color.WHITE)
			z += tile
	if seams_started:
		seams.surface_end()
		var seam_node := MeshInstance3D.new()
		seam_node.mesh = seams
		seam_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(seam_node)
	var label_text := str(room.get("label", ""))
	var label_anchor := Vector3(pos.x - width * 0.5 + 0.45, 0.198 + floor_offset, pos.z - depth * 0.5 + 0.43)
	if not label_text.is_empty():
		# A dark plate under the room name keeps it legible on both the light
		# floor tint and the desaturated fog-of-war colors, without revealing
		# anything the floor tile itself doesn't already show.
		var plate_width := maxf(1.0, label_text.length() * 0.145 + 0.26)
		var plate := _box(_world, Vector3(label_anchor.x + plate_width * 0.5 - 0.12, 0.192 + floor_offset, label_anchor.z - 0.02), Vector3(plate_width, 0.01, 0.36), Color(0.055, 0.075, 0.075, 0.6))
		_fog_exempt(plate)
	var label := _label(label_text, Color("f4f6e8"), 32, 0.0085)
	label.outline_size = 9
	label.outline_modulate = Color(0.04, 0.05, 0.05, 1.0)
	label.position = label_anchor
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.rotation_degrees.x = -90
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.no_depth_test = true
	_world.add_child(label)

func _build_wall(wall: Dictionary) -> void:
	# Accurate models may use an invisible logical wall proxy for navigation,
	# sight and cover. A proxy never becomes a second visible rock/fuselage.
	if not bool(wall.get("render", true)):
		return
	var width := float(wall.w)
	var depth := float(wall.d)
	var logical_height := maxf(0.001, float(wall.get("height", 2.6)))
	var height := minf(logical_height, 0.79)
	var placement := Node3D.new()
	placement.position = Vector3(float(wall.x), 0.2 + float(wall.get("base_height", 0.0)), float(wall.z))
	placement.rotation.y = float(wall.get("rotation", 0.0))
	placement.set_meta("logical_height", logical_height)
	_world.add_child(placement)
	var material: String = str(wall.get("material", "plaster"))
	var color: Color = {"wood":Color("8c785d"), "metal":Color("687977"), "steel":Color("687977"), "glass":Color("8daeb7"), "brick":Color("9d7d6b"), "masonry":Color("9d7d6b")}.get(material, Color("8b8d7e"))
	var opacity: float = clampf(float(wall.get("opacity", 0.0 if material == "glass" else 1.0)), 0.0, 1.0)
	if not wall.has("opacity") and wall.has("opaque"): opacity = 1.0 if bool(wall.opaque) else 0.0
	if opacity < 0.5: color.a = maxf(0.20, opacity)
	var pane := _box(placement, Vector3(0, height * 0.5, 0), Vector3(width, height, depth), color)
	if material == "glass":
		pane.set_meta("dynamic_geometry", true)
		var index: int = _mission.get("walls", []).find(wall)
		_glass_pane_nodes["wall:" + str(wall.get("id", "wall-" + str(index)))] = pane
	# Cutaway caps retain the authored floor layout while logical wall height
	# controls eye and weapon rays. Rotation and base elevation are shared.
	var cap := _box(placement, Vector3(0, height + 0.035, 0), Vector3(width + 0.045, 0.07, depth + 0.045), Color("858778"))
	cap.material_override = _material(Color("e4e6d8"), true, true)
	_fog_exempt(cap)
	_box(placement, Vector3(0, minf(height * 0.15, 0.07), 0), Vector3(width + 0.025, minf(height, 0.14), depth + 0.025), Color("505b52"))

func _build_door(door: Dictionary) -> void:
	var root := Node3D.new()
	root.position = Vector3(float(door.x), 0.2 + float(door.get("base_height", 0.0)), float(door.z))
	root.set_meta("dynamic_geometry", true)
	_world.add_child(root)
	var across_x := str(door.get("axis", "x")) == "x"
	var width := float(door.w) if across_x else float(door.d)
	if width < 0.5:
		width = 1.6
	var hinge := Node3D.new()
	hinge.position = Vector3(-width * 0.5, 0, 0) if across_x else Vector3(0, 0, -width * 0.5)
	root.add_child(hinge)
	var leaf: Node3D = DoorGeometry.LEAF.instantiate()
	hinge.add_child(leaf)
	leaf.scale.x = width
	leaf.set_meta("logical_height", float(door.get("height", 2.1)))
	hinge.transform = root.transform.affine_inverse() * DoorGeometry.hinge_transform(door, 0.0)
	for mesh: MeshInstance3D in leaf.find_children("*", "MeshInstance3D", true, false):
		for surface in range(mesh.mesh.get_surface_count()):
			var original: Material = mesh.mesh.surface_get_material(surface)
			var name: String = original.resource_name if original else "wood"
			var material_name: String = str(door.get("material", "wood"))
			var color: Color = {"glass":Color("8daeb7"), "metal":Color("647977"), "steel":Color("647977")}.get(material_name, Color("946e48"))
			var opacity: float = clampf(float(door.get("opacity", 0.0 if material_name == "glass" else 1.0)), 0.0, 1.0)
			if not door.has("opacity") and door.has("opaque"): opacity = 1.0 if bool(door.opaque) else 0.0
			if opacity < 0.5: color.a = maxf(0.20, opacity)
			mesh.set_surface_override_material(surface, _material(color) if name == "wood" else EnvironmentAssets._material(name))
			if material_name == "glass" and name == "wood":
				var key := "door:" + str(door.id)
				if not _glass_door_surfaces.has(key): _glass_door_surfaces[key] = []
				_glass_door_surfaces[key].append({"mesh": mesh, "surface": surface, "intact": mesh.get_surface_override_material(surface), "broken": _material(Color(0.5, 0.7, 0.75, 0.015))})
	var threshold := Vector3(width, 0.012, 0.27) if across_x else Vector3(0.27, 0.012, width)
	var marker := _box(root, Vector3(0, 0.01, 0), threshold, DOOR_COLOR)
	var label := _label(str(door.get("id", "D")).to_upper(), Color("f5c796"), 30, 0.0085)
	label.position = Vector3(-width * 0.5 - 0.18, 1.25, 0) if across_x else Vector3(0, 1.25, -width * 0.5 - 0.18)
	label.no_depth_test = true
	root.add_child(label)
	_door_nodes[str(door.id)] = {"node": root, "hinge": hinge, "label": label, "marker": marker, "across_x": across_x, "leaf": leaf}

## Static map information only (where a door is, never its open/closed state): a thin
## threshold line with jamb ticks, drawn after the fog so doors stay findable in the dark.
func _draw_door_frames() -> void:
	if _door_frame_mesh == null: return
	_door_frame_mesh.clear_surfaces()
	var doors: Array = _mission.get("doors", [])
	if doors.is_empty(): return
	var color := Color(DOOR_COLOR.lightened(0.38), 0.72)
	_door_frame_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _vertex_material())
	_triangle(_door_frame_mesh, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Color.TRANSPARENT)
	for door: Dictionary in doors:
		var across_x := str(door.get("axis", "x")) == "x"
		var width := float(door.get("w", 1.6)) if across_x else float(door.get("d", 1.6))
		if width < 0.5: width = 1.6
		var centre := Vector2(float(door.x), float(door.z))
		var along := Vector2.RIGHT if across_x else Vector2.DOWN
		var across := along.orthogonal()
		var height := 0.226 + float(door.get("base_height", 0.0))
		_flat_line(_door_frame_mesh, centre - along * width * 0.5, centre + along * width * 0.5, 0.045, height, color)
		for sign_value: float in [-1.0, 1.0]:
			var jamb := centre + along * width * 0.5 * sign_value
			_flat_line(_door_frame_mesh, jamb - across * 0.26, jamb + across * 0.26, 0.09, height, Color(color, 0.8))
	_door_frame_mesh.surface_end()

func _build_prop(prop: Dictionary) -> void:
	if str(prop.get("material", "")) == "glass" or str(prop.get("type", "")) == "window":
		var center := Vector3(float(prop.x), float(prop.get("base_height", 0.0)) + 0.2, float(prop.z))
		var holder := Node3D.new()
		holder.position = center
		holder.rotation.y = float(prop.get("rotation", 0.0))
		_world.add_child(holder)
		var width := float(prop.get("w", 1.2))
		var depth := float(prop.get("d", 0.12))
		var height := minf(float(prop.get("height", 1.8)), 0.79)
		var pane := _box(holder, Vector3(0, height * 0.5, 0), Vector3(width, height, depth), Color(0.50, 0.69, 0.73, 0.25))
		pane.set_meta("dynamic_geometry", true)
		_glass_pane_nodes["prop:" + str(prop.get("id", "prop-" + str(_mission.get("props", []).find(prop))))] = pane
		_box(holder, Vector3(0, 0.035, 0), Vector3(width + 0.05, 0.07, depth + 0.04), Color("748179"))
		_box(holder, Vector3(0, height + 0.035, 0), Vector3(width + 0.05, 0.07, depth + 0.04), Color("748179"))
		return
	if str(prop.get("type", "")) != "rug": _build_contact_shadow(prop)
	if EnvironmentAssets.create_prop(_world, prop, _is_metre_map()):
		return
	var root := Node3D.new()
	root.position = Vector3(float(prop.x), 0.2 + float(prop.get("base_height", 0.0)), float(prop.z))
	root.rotation.y = float(prop.get("rotation", 0.0))
	_world.add_child(root)
	var w := float(prop.get("w", 1.2))
	var d := float(prop.get("d", 1.0))
	match str(prop.get("type", "crate")):
		"pillar":
			var h: float = float(prop.get("height", 2.6))
			_box(root, Vector3(0, h * 0.5, 0), Vector3(w, h, d), Color("7d8580"))
			_box(root, Vector3(0, minf(h * 0.4, 0.85), 0), Vector3(w + 0.012, minf(h * 0.18, 0.3), d + 0.012), Color("baa869"))
		"vehicle":
			var h: float = float(prop.get("height", 1.5)) / 0.94
			_box(root, Vector3(0, h * 0.37, 0), Vector3(w, h * 0.49, d), Color("5c7276"))
			_box(root, Vector3(0, h * 0.74, -d * 0.07), Vector3(w * 0.84, h * 0.40, d * 0.49), Color("8faaa9"))
			_box(root, Vector3(0, h * 0.76, d * 0.19), Vector3(w * 0.82, h * 0.25, 0.05), Color("263b43"))
			for sx: int in [-1, 1]:
				for sz: int in [-1, 1]:
					var wheel := _cylinder(root, Vector3(sx * w * 0.45, h * 0.19, sz * d * 0.30), Vector3(h * 0.36, w * 0.09, h * 0.36), Color("303636"))
					wheel.rotation.z = PI * 0.5
		"rug":
			_box(root, Vector3(0, 0.018, 0), Vector3(w, 0.035, d), Color("8b6752"))
			_box(root, Vector3(0, 0.039, 0), Vector3(maxf(0.1, w - 0.16), 0.008, maxf(0.1, d - 0.16)), Color("aa8662"))
			for side in [-1, 1]:
				_box(root, Vector3(side * (w * 0.5 - 0.21), 0.045, 0), Vector3(0.035, 0.009, d - 0.2), Color("cdb18a"))
		"table", "desk":
			_box(root, Vector3(0, 0.66, 0), Vector3(w, 0.13, d), Color("ad8a5d"))
			_box(root, Vector3(0, 0.735, 0), Vector3(w - 0.04, 0.025, d - 0.04), Color("c19d70"))
			for sx in [-1, 1]:
				for sz in [-1, 1]:
					_box(root, Vector3(sx * (w * 0.5 - 0.12), 0.31, sz * (d * 0.5 - 0.12)), Vector3(0.12, 0.6, 0.12), Color("5b5142"))
			_box(root, Vector3(-w * 0.18, 0.77, 0), Vector3(minf(0.32, w * 0.3), 0.025, minf(0.43, d * 0.5)), Color("ded8ba"))
			_cylinder(root, Vector3(w * 0.22, 0.8, 0.04), Vector3(0.085, 0.13, 0.085), Color("d9d8c5"))
		"sofa":
			_box(root, Vector3(0, 0.28, 0), Vector3(w, 0.44, d), Color("536b61"))
			_box(root, Vector3(0, 0.67, -d * 0.36), Vector3(w, 0.47, d * 0.28), Color("6c8070"))
			for sx in [-1, 1]:
				_box(root, Vector3(sx * (w * 0.5 - 0.12), 0.5, 0.03), Vector3(0.24, 0.5, d), Color("718574"))
			for i in range(3):
				_box(root, Vector3((i - 1) * (w - 0.55) / 3.0, 0.54, d * 0.09), Vector3((w - 0.58) / 3.0 - 0.025, 0.17, d * 0.65), Color("859583"))
			var pillow := _box(root, Vector3(-w * 0.27, 0.75, -d * 0.02), Vector3(0.35, 0.23, 0.4), Color("c7b58a"))
			pillow.rotation.z = 0.18
		"bed":
			_box(root, Vector3(0, 0.2, 0), Vector3(w, 0.32, d), Color("73604c"))
			_box(root, Vector3(0, 0.42, 0), Vector3(w - 0.06, 0.25, d - 0.05), Color("d5d0b9"))
			_box(root, Vector3(0, 0.62, -d * 0.48), Vector3(w + 0.05, 0.85, 0.13), Color("9b805c"))
			_box(root, Vector3(0, 0.56, d * 0.13), Vector3(w - 0.04, 0.06, d * 0.7), Color("859287"))
			_box(root, Vector3(0, 0.605, d * 0.3), Vector3(w - 0.035, 0.035, d * 0.22), Color("657c73"))
			for sx in [-1, 1]:
				_box(root, Vector3(sx * w * 0.24, 0.6, -d * 0.33), Vector3(w * 0.4, 0.15, d * 0.22), Color("f0e7ce"))
		"cabinet", "bookshelf":
			_box(root, Vector3(0, 0.57, 0), Vector3(w, 1.14, d), Color("836e53"))
			_box(root, Vector3(0, 1.17, 0), Vector3(w + 0.06, 0.07, d + 0.04), Color("b39a70"))
			for level in [0.23, 0.59, 0.95]:
				_box(root, Vector3(0, level, d * 0.5 + 0.013), Vector3(w - 0.1, 0.29, 0.035), Color("a38c66"))
				_box(root, Vector3(0, level + 0.05, d * 0.5 + 0.038), Vector3(0.2, 0.035, 0.035), Color("414b46"))
		"plant":
			_cylinder(root, Vector3(0, 0.22, 0), Vector3(w * 0.31, 0.43, d * 0.31), Color("b08a69"))
			_cylinder(root, Vector3(0, 0.435, 0), Vector3(w * 0.28, 0.025, d * 0.28), Color("4b4f36"))
			_cylinder(root, Vector3(0, 0.74, 0), Vector3(0.055, 0.67, 0.055), Color("7a7550"))
			for i in range(7):
				var angle := i * TAU / 7.0
				var leaf := _sphere(root, Vector3(cos(angle) * w * 0.23, 0.94 + (i % 3) * 0.14, sin(angle) * d * 0.23), Vector3(w * 0.27, 0.13, d * 0.23), Color("75936b") if i % 2 == 0 else Color("577b60"))
				leaf.rotation.z = cos(angle) * 0.5
		"chair":
			_box(root, Vector3(0, 0.43, 0), Vector3(w, 0.12, d), Color("aa8b61"))
			_box(root, Vector3(0, 0.75, -d * 0.45), Vector3(w, 0.53, 0.1), Color("b79a6b"))
			for sx in [-1, 1]:
				for sz in [-1, 1]:
					_box(root, Vector3(sx * w * 0.38, 0.21, sz * d * 0.38), Vector3(0.07, 0.4, 0.07), Color("595648"))
		_:
			_box(root, Vector3(0, 0.34, 0), Vector3(w, 0.68, d), Color("78816b"))
			_box(root, Vector3(0, 0.72, 0), Vector3(w + 0.05, 0.09, d + 0.05), Color("90977c"))
			for sx in [-1, 1]:
				_box(root, Vector3(sx * w * 0.3, 0.37, d * 0.5 + 0.015), Vector3(0.06, 0.61, 0.035), Color("465247"))

## Fake contact shadow replacing the realtime sun shadow: one shared soft footprint quad + material,
## so _batch_static_geometry merges every prop's blob into a single MultiMesh draw.
func _build_contact_shadow(prop: Dictionary) -> void:
	var width := float(prop.get("w", 1.2))
	var depth := float(prop.get("d", 1.0))
	if maxf(width, depth) > 6.0: return # vehicles/hulls on metre maps: a rectangular blob would read as a slab
	var margin := clampf(0.2 + 0.15 * minf(width, depth), 0.25, 0.45)
	if _blob_mesh == null:
		var quad := QuadMesh.new()
		quad.orientation = PlaneMesh.FACE_Y
		_blob_mesh = ArrayMesh.new()
		_blob_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, quad.get_mesh_arrays())
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
		gradient.colors = PackedColorArray([Color(0, 0, 0, 0.42), Color(0, 0, 0, 0.42), Color(0, 0, 0, 0.0)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_SQUARE
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 64
		texture.height = 64
		_blob_material = StandardMaterial3D.new()
		_blob_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blob_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blob_material.albedo_texture = texture
		_blob_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var blob := MeshInstance3D.new()
	blob.name = "ContactShadow"
	blob.mesh = _blob_mesh
	blob.material_override = _blob_material
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Offset along the old sun's shadow direction (+x, -z) and rotate with the prop.
	blob.position = Vector3(float(prop.x) + 0.07, 0.204 + float(prop.get("base_height", 0.0)), float(prop.z) - 0.05)
	blob.rotation.y = float(prop.get("rotation", 0.0))
	blob.scale = Vector3(width + margin, 1.0, depth + margin)
	_world.add_child(blob)

func _build_interactive_target(target: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Objective_" + str(target.id)
	root.position = surface_position(Vector2(float(target.x), float(target.z)), 0.0)
	root.set_meta("dynamic_geometry", true)
	_world.add_child(root)
	var rect := Rect2(-Vector2(float(target.w), float(target.d)) * 0.5, Vector2(float(target.w), float(target.d)))
	var border := ImmediateMesh.new()
	border.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(Color("d5bc76"), true, true))
	var corners := [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)]
	for index in range(4):
		_flat_line(border, corners[index], corners[(index + 1) % 4], 0.055, 0.235, Color.WHITE)
	border.surface_end()
	var outline := MeshInstance3D.new()
	outline.mesh = border
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fog_exempt(outline)
	root.add_child(outline)
	var label := _label("", Color("ead6a1"), 32, 0.015)
	label.position = Vector3(0, 0.5, -rect.size.y * 0.5 - 0.3)
	label.no_depth_test = true
	root.add_child(label)
	var bar_width := minf(3.0, maxf(1.0, rect.size.x))
	var background := _box(root, Vector3(0, 0.25, rect.size.y * 0.5 + 0.3), Vector3(bar_width, 0.02, 0.12), Color("353f39"))
	_fog_exempt(background)
	var progress := _box(root, Vector3(0, 0.265, rect.size.y * 0.5 + 0.3), Vector3(bar_width, 0.025, 0.10), Color("e8c36e"))
	_fog_exempt(progress)
	_interactive_target_nodes[str(target.id)] = {"label": label, "progress": progress, "outline": outline, "bar_width": bar_width, "ordinal": _interactive_target_nodes.size() + 1}

func _sync_interactive_targets(targets: Array) -> void:
	var active_id := ""
	for target: Dictionary in targets:
		if not bool(target.get("completed", false)):
			active_id = str(target.get("id", ""))
			break
	for target: Dictionary in targets:
		var target_id := str(target.get("id", ""))
		if not _interactive_target_nodes.has(target_id):
			continue
		var entry: Dictionary = _interactive_target_nodes[target_id]
		var complete := bool(target.get("completed", false))
		var active := target_id == active_id and not complete
		var color := Color("a1d6c3") if complete else (Color("f0c75e") if active else Color("848e8b"))
		var fraction := 1.0 if complete else clampf(float(target.get("progress", 0.0)) / maxf(0.001, float(target.get("duration", 1.0))), 0.0, 1.0)
		var verb := _t(str({"recover": "회수", "disable": "무력화", "inspect": "확인", "board": "탑승"}.get(str(target.get("action", "inspect")), "확인")))
		var text := "%02d · %s · %s" % [int(entry.ordinal), str(target.get("label", target_id)), _t("완료") if complete else verb]
		if fraction > 0.0 and not complete:
			text += " %d%%" % int(fraction * 100.0)
		var label: Label3D = entry.label
		label.text = text
		label.modulate = color
		var outline: MeshInstance3D = entry.outline
		outline.material_override = _material(color, true, true)
		var bar: MeshInstance3D = entry.progress
		bar.material_override = _material(color, true, true)
		bar.scale.x = maxf(0.001, fraction)
		bar.position.x = -float(entry.bar_width) * (1.0 - fraction) * 0.5
		bar.visible = fraction > 0.0

func display(state: Dictionary, selected_id: String, planning: bool, delta: float) -> void:
	if not is_instance_valid(_actors):
		return
	_state = state
	if is_instance_valid(_prior_attempt_node): _prior_attempt_node.visible = planning and _prior_attempt_visible and not _prior_attempt.is_empty()
	_sync_interactive_targets(state.get("interactive_targets", _mission.get("interactive_targets", [])))
	# This preview sees the same remembered door observations as the renderer.
	# It never reads authoritative enemies or hidden door state.
	_preview_nav.doors = state.get("doors", [])
	var presentation_paused := planning or bool(state.get("presentation_paused", false))
	if state.has("presentation_mode"):
		set_menu_preview(str(state.presentation_mode) == "MENU")
	var next_selected: Array = state.get("selected_units", [selected_id])
	var selection_changed := selected_id != _selected or next_selected != _selected_units
	_selected = selected_id
	_selected_units = next_selected.duplicate()
	if state.has("settings"):
		set_settings(state.settings)
	_clock = float(state.get("presentation_time", state.get("time", 0.0)))
	var viewport_size := get_viewport().get_visible_rect().size
	if _menu_preview and not _motion_reduced:
		# The menu diorama is otherwise static (sim time is paused in MENU
		# mode), so drive its slow cinematic drift off real delta instead.
		_menu_drift_time += delta
		_fit_camera()
	elif viewport_size != _view_size:
		_fit_camera()
	var present: Dictionary = {}
	var units: Array = state.get("units", [])
	for index in range(units.size()):
		_sync_actor(units[index], "unit", index, selected_id, delta, presentation_paused)
		present[str(units[index].id)] = true
	var reveal := bool(state.get("presentation_reveal", false))
	# Seeks, scrubs and mission resets are decided BEFORE enemies are laid out, so a reset frame can never start
	# (or leave running) a sighting hold on an enemy that is already known.
	var rewound := _clock < _fog_time
	var tick_probe := int(state.get("tick", 0))
	var resetting := rewound or bool(state.get("presentation_reset", false)) or tick_probe < _last_tick or (not state.has("presentation_events") and _last_tick >= 0 and tick_probe - _last_tick > 15)
	if resetting: _reset_sightings()
	var reveal_changed := (reveal or _menu_preview) != _observation_revealed
	_set_observation_revealed(reveal or _menu_preview)
	_track_door_motion(state.get("doors", []))
	if rewound:
		_visibility.build(_mission)
		_cone_inputs.clear()
		_door_motion.clear()
		_memory_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
		_fog_time = -1.0
		# H1 fix: a backward seek/rewind already clears the GPU "remembered"
		# fog texture above, so the CPU-side room exploration grid must reset
		# the same way or room_observed_fraction would stay "explored" for
		# ground the replay has since rewound past.
		for room_id: String in _room_seen_mask:
			(_room_seen_mask[room_id] as Array).fill(false)
			_room_seen_count[room_id] = 0
	# A newly visible (or lost) enemy refreshes the fog in the SAME frame instead of waiting up to a
	# 30 Hz throttle step, so a spotted enemy never stands on a still-dark floor. `update` itself
	# returns false when nothing moved, so steady state keeps the throttle's savings.
	var seen_signature := 0
	for enemy: Dictionary in state.get("enemies", []):
		if enemy.get("visible", true): seen_signature = seen_signature * 31 + str(enemy.get("id", "")).hash()
	var seen_changed := seen_signature != _seen_signature
	_seen_signature = seen_signature
	var fog_refreshed := _fog_time < 0.0 or seen_changed or _clock - _fog_time >= 1.0 / 30.0
	if fog_refreshed:
		if _visibility.update(units, state.get("doors", []), state.get("smoke_zones", [])):
			var pixel_scale: Vector2 = Vector2(_fog_viewport.size) / _visibility.bounds
			var mask_mesh: ArrayMesh = _fog_canvas.set_polygons(_visibility.polygons, pixel_scale)
			_memory_canvas.set_mesh(mask_mesh)
			_fog_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			_update_room_exploration()
			_memory_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_fog_time = _clock
	for ghost in _ghost_nodes.values():
		ghost.node.visible = false
	_remembered_bodies.clear()
	_fog_pools.clear()
	_held_enemies.clear()
	var sighted := {}
	var bypass_hold := presentation_paused or resetting or reveal_changed or reveal
	for enemy in state.get("enemies", []):
		var enemy_id := str(enemy.get("id", ""))
		var is_visible: bool = reveal or enemy.get("visible", true)
		if is_visible:
			_remember_gear(enemy_id, enemy)
		var unseen: bool = not reveal and not enemy.get("visible", true) and enemy.has("last_seen")
		if unseen:
			# A remembered body is drawn only from what was observed: the record says neutralized, or an
			# observed INCAPACITATED/ARREST event gave the public position of a kill made out of sight.
			var body := _remembered_body(enemy, state)
			if not body.is_empty():
				_remembered_bodies[enemy_id] = true
				_sync_actor(body, "enemy", 0, selected_id, delta, presentation_paused)
				present[enemy_id] = true
				continue
			# Known neutralized with no observed position: draw nothing rather than an old "alive" ghost.
			if not _room_neutralized_ids.has(enemy_id):
				_sync_last_seen(enemy)
		if is_visible:
			var holding := false
			var uncovered := false
			var at := Vector2(float(enemy.get("x", 0.0)), float(enemy.get("z", 0.0)))
			if float(enemy.get("hp", 0.0)) > 0.0 and enemy.get("visible", true):
				sighted[enemy_id] = true
				uncovered = not reveal and not _fog_covers(at, enemy_id)
				var may_lag := uncovered and not bypass_hold and not (_sighting.has(enemy_id) and bool(_sighting[enemy_id].cleared)) and _door_may_lag(at, units, state.get("doors", []))
				holding = _sighting_hold(enemy_id, not uncovered, delta, may_lag, bypass_hold)
			if holding:
				_held_enemies[enemy_id] = true
			else:
				_sync_actor(enemy, "enemy", 0, selected_id, delta, presentation_paused)
				present[enemy_id] = true
				# An enemy the sim reports as seen is never left standing on unlit floor: it gets its own local sight fan.
				if uncovered: _fog_pools[enemy_id] = at
	for known: String in _sighting.keys():
		if not sighted.has(known) and (_clock - float(_sighting[known].last_seen) > SIGHTING_MEMORY or _clock < float(_sighting[known].last_seen)):
			_sighting.erase(known)
			_cover_cache.erase(known)
	_update_sight_pools(fog_refreshed)
	for civilian in state.get("civilians", []):
		if not reveal and not civilian.get("visible", false):
			continue
		_sync_actor(civilian, "civilian", 0, selected_id, delta, presentation_paused)
		present[str(civilian.id)] = true
	# Hide entire root including weapon, label and shadow the moment LOS is lost.
	for id in _entity_nodes:
		_entity_nodes[id].node.visible = present.has(id)
		# A remembered body is fogged like the map: its bright disc label and status text stay hidden.
		var remembered := _remembered_bodies.has(id)
		_entity_nodes[id].label.visible = not remembered
		if remembered: _entity_nodes[id].status.visible = false
	_update_fog_actors()
	for door in state.get("doors", []):
		var id := str(door.get("id", ""))
		if _door_nodes.has(id):
			var entry: Dictionary = _door_nodes[id]
			var progress := float(door.get("progress", 0.0))
			if str(door.get("state", "CLOSED")) == "OPEN":
				progress = 1.0
			entry.hinge.transform = entry.node.transform.affine_inverse() * DoorGeometry.hinge_transform(door, progress)
			entry.leaf.visible = not bool(door.get("destroyed", false))
			var blocked := bool(door.get("blocked", false))
			var opening := str(door.get("state", "")) == "OPENING"
			entry.label.text = _t("대기" if blocked else "열기") if opening else str(door.id).to_upper()
			entry.label.modulate = Color("efbb72") if blocked else (UNIT_COLORS[0] if progress >= 1.0 else Color("f5c796"))
			entry.label.visible = (progress < 1.0 or opening) and (reveal or _menu_preview or bool(door.get("observed", true)))
			entry.marker.material_override = _material(Color("9bd0bb") if progress >= 1.0 else DOOR_COLOR)
	_draw_timer += delta
	var tick := int(state.get("tick", 0))
	var presentation_reset := bool(state.get("presentation_reset", false))
	var legacy_jump := not state.has("presentation_events") and _last_tick >= 0 and tick - _last_tick > 15
	if presentation_reset or tick < _last_tick or legacy_jump:
		_clear_flashes()
		_last_event_seq = int(state.get("presentation_event_cursor", int(state.get("events", []).back().get("seq", -1)) if not state.get("events", []).is_empty() else -1))
		_room_clear_flashes.clear()
		var reset_state := state
		if state.has("presentation_reset_neutralized_ids"):
			reset_state = state.duplicate()
			reset_state["neutralized_ids"] = state.presentation_reset_neutralized_ids
		_resync_room_cleared(reset_state)
		_effect_time = _clock
		_restore_flash_visuals(state)
		_shake_remaining = 0.0
		_freeze_remaining = 0.0
		_reset_hit_links()
	if _draw_timer >= 0.08 or selection_changed or tick < _last_tick:
		_draw_timer = 0.0
		if presentation_paused:
			var path_inputs: Array = [units, _selected, _selected_units, _waypoint_unit, _selected_waypoint, camera.size, _view_size, _line_width, _palette_name, _language]
			if _paused_path_inputs != path_inputs:
				_draw_paths(units)
				_paused_path_inputs = path_inputs.duplicate(true)
		else:
			_paused_path_inputs.clear()
			_draw_paths(units)
		var cone_inputs: Array = [_visibility.revision, _selected, _show_fov]
		if _cone_inputs != cone_inputs:
			_draw_cone(units)
			_cone_inputs = cone_inputs
		_last_tick = tick
	if _interaction_dirty or selection_changed:
		_draw_interaction()
		_interaction_dirty = false
	_update_room_drill_preview(planning)
	_sync_broken_glass(state.get("broken_glass", []))
	_sync_flash_projectiles(state.get("flash_projectiles", []))
	_sync_frag_projectiles(state.get("frag_projectiles", []))
	_sync_camera_memory(units, present)
	_sync_smoke_zones(state.get("smoke_zones", []))
	_sync_sound_marks(state)
	_update_effects(state, delta, presentation_paused)
	_sync_room_control_labels(state)
	_sync_call_labels(state)
	# Plan 5 breach camera shake / mission_end punch-in: L2 fix -- both are
	# computed from _camera_base_position/_camera_base_size (the values
	# _fit_camera() last set, saved there) every frame, instead of
	# undoing/redoing the previous frame's offset on top of camera.position/
	# camera.size directly. The old undo-redo approach assumed nothing else
	# touched the camera between frames; if _fit_camera() ran mid-shake/zoom
	# (resize, pan, zoom) it left a stale offset baked in. Deriving fresh from
	# the saved base every frame cannot accumulate drift regardless of when
	# _fit_camera() last ran.
	if is_instance_valid(camera):
		if _shake_remaining > 0.0 and not _motion_reduced:
			_shake_remaining = maxf(0.0, _shake_remaining - delta)
			_shake_offset = _current_kick_offset()
		else:
			_shake_remaining = 0.0
			_shake_offset = Vector3.ZERO
		camera.position = _camera_base_position + _shake_offset
		# Plan 5 mission_end punctuation: see the MISSION_END comment in
		# _update_effects for why this is a camera punch-in rather than an
		# actual slow-mo or freeze.
		if _freeze_remaining > 0.0:
			_freeze_remaining = maxf(0.0, _freeze_remaining - delta)
			var progress := 1.0 - _freeze_remaining / MISSION_END_FREEZE
			_freeze_zoom_factor = 1.0 - 0.02 * sin(progress * PI)
		else:
			_freeze_zoom_factor = 1.0
		camera.size = _camera_base_size * _freeze_zoom_factor

func _make_actor(kind: String, index: int) -> Dictionary:
	var root := Node3D.new()
	_actors.add_child(root)
	var body := Node3D.new()
	root.add_child(body)
	var color: Color = UNIT_COLORS[index % UNIT_COLORS.size()] if kind == "unit" else ENEMY_COLOR
	if kind == "civilian":
		color = CIVILIAN_COLOR
	var uniform := Color("53675e") if kind == "unit" else Color("785b4a")
	if kind == "civilian":
		uniform = Color("c3b58b")
	var visual: Dictionary = {}
	var left_leg: Node3D
	var right_leg: Node3D
	if kind != "civilian":
		visual = ActorVisual.create(body, kind == "enemy", color if kind == "unit" else Color(0.0, 0.0, 0.0, 0.0))
	else:
		left_leg = Node3D.new()
		right_leg = Node3D.new()
		# Model faces +X. Equipment silhouette remains readable from a steep camera.
		left_leg.position = Vector3(0, 0.58, -0.15)
		body.add_child(left_leg)
		right_leg.position = Vector3(0, 0.58, 0.15)
		body.add_child(right_leg)
		for leg in [left_leg, right_leg]:
			_box(leg, Vector3(0, -0.2, 0), Vector3(0.22, 0.42, 0.22), uniform.darkened(0.08))
			_box(leg, Vector3(0.08, -0.45, 0), Vector3(0.36, 0.16, 0.25), Color("29332f"))
			_box(leg, Vector3(0.115, -0.23, 0), Vector3(0.06, 0.19, 0.21), Color("414d41"))
		_box(body, Vector3(0, 0.88, 0), Vector3(0.42, 0.59, 0.6), uniform)
		if kind != "civilian":
			_box(body, Vector3(0.085, 0.92, 0), Vector3(0.47, 0.48, 0.52), Color("323f36"))
			_box(body, Vector3(-0.285, 0.93, 0), Vector3(0.21, 0.43, 0.43), Color("69725a"))
			for offset in [-0.16, 0.0, 0.16]:
				_box(body, Vector3(0.34, 0.84, offset), Vector3(0.12, 0.21, 0.115), Color("75806a"))
			_box(body, Vector3(-0.26, 1.23, -0.15), Vector3(0.04, 0.35, 0.035), Color("2c332e"))
		_box(body, Vector3(0.1, 1.34, 0), Vector3(0.28, 0.29, 0.3), Color("c59e75"))
		if kind == "unit":
			_sphere(body, Vector3(0.055, 1.51, 0), Vector3(0.285, 0.23, 0.29), Color("6e8068"))
			_box(body, Vector3(0.255, 1.43, 0), Vector3(0.14, 0.12, 0.36), Color("273b37"))
			_box(body, Vector3(-0.02, 1.715, 0), Vector3(0.12, 0.025, 0.15), color)
		elif kind == "enemy":
			_sphere(body, Vector3(0.035, 1.47, 0), Vector3(0.265, 0.22, 0.265), Color("4b493e"))
			_box(body, Vector3(0.21, 1.38, 0), Vector3(0.13, 0.18, 0.31), Color("6e6655"))
		else:
			_sphere(body, Vector3(-0.015, 1.47, 0), Vector3(0.24, 0.19, 0.25), Color("494237"))
		for side in [-1, 1]:
			var arm := _box(body, Vector3(0.13, 0.98, side * 0.35), Vector3(0.44, 0.22, 0.22), uniform)
			arm.rotation.z = -0.22 if kind != "civilian" else -0.75
			_box(body, Vector3(0.4, 0.99, side * 0.23), Vector3(0.19, 0.16, 0.15), Color("a9916c") if kind == "civilian" else Color("414b3e"))
		if kind != "civilian":
			_box(body, Vector3(0.55, 1.02, 0.18), Vector3(0.84, 0.14, 0.14), Color("202a27"))
			_box(body, Vector3(0.94, 1.035, 0.18), Vector3(0.37, 0.07, 0.07), Color("394744"))
			_box(body, Vector3(0.49, 0.86, 0.18), Vector3(0.16, 0.25, 0.12), Color("25322d"))
			_box(body, Vector3(0.51, 1.15, 0.18), Vector3(0.16, 0.11, 0.1), Color("44544b"))
		_merge_actor_geometry(body)
		_merge_actor_geometry(left_leg)
		_merge_actor_geometry(right_leg)
	# Opaque base disc (was a thin translucent ring): reads as a solid,
	# team-colored foothold even before a unit is selected.
	var ring := _disc_mesh(0.4, color, 28)
	ring.position.y = 0.225
	root.add_child(ring)
	var selection := _ring_mesh(0.47, 0.535, color.lightened(0.18), 40)
	selection.position.y = 0.23
	root.add_child(selection)
	# Threats carry a faint wider halo so a hostile reads at a glance even while the disc is small.
	var threat_halo: MeshInstance3D = null
	if kind == "enemy":
		threat_halo = _ring_mesh(0.4, 0.62, Color(color.r, color.g, color.b, 0.4), 40)
		threat_halo.position.y = 0.222
		root.add_child(threat_halo)
	# Always-on facing tick on the disc rim, independent of the longer aim
	# arrow below (which only appears on the selected unit).
	var tick_mesh := ImmediateMesh.new()
	tick_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(PALE, true))
	_triangle(tick_mesh, Vector3(0.46, 0.236, 0), Vector3(0.3, 0.236, -0.07), Vector3(0.3, 0.236, 0.07), Color.WHITE)
	tick_mesh.surface_end()
	var tick := MeshInstance3D.new()
	tick.mesh = tick_mesh
	tick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(tick)
	var arrow_mesh := ImmediateMesh.new()
	arrow_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(color, true))
	_triangle(arrow_mesh, Vector3(0.78, 0.235, 0), Vector3(0.56, 0.235, -0.11), Vector3(0.56, 0.235, 0.11), Color.WHITE)
	arrow_mesh.surface_end()
	var arrow := MeshInstance3D.new()
	arrow.mesh = arrow_mesh
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(arrow)
	# Printed flat on the base disc instead of floating above the head, so it
	# never overlaps the model's silhouette at any facing or default zoom.
	var label := _label(str(index + 1) if kind == "unit" else ("!" if kind == "enemy" else "C"), INK, 56, 0.0082)
	label.outline_size = 10
	label.outline_modulate = color.lightened(0.45) if kind == "unit" else PALE
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.rotation_degrees.x = -90
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector3(0, 0.237, 0)
	label.no_depth_test = true
	root.add_child(label)
	var status := _label("", PALE, 30, 0.0085)
	status.position = Vector3(0, 2.5, 0)
	status.no_depth_test = true
	root.add_child(status)
	var call_label: Label3D = null
	if kind == "unit":
		call_label = _label("", PALE, 28, 0.0085)
		call_label.position = Vector3(0, 3.0, 0)
		call_label.no_depth_test = true
		call_label.visible = false
		root.add_child(call_label)
	return {"visual": visual, "node": root, "body": body, "left_leg": left_leg, "right_leg": right_leg, "ring": ring, "selection": selection, "threat_halo": threat_halo, "tick": tick, "arrow": arrow, "label": label, "status": status, "call_label": call_label, "kind": kind, "index": index, "pos": Vector2.ZERO, "phase": 0.0, "last_time": -1.0}

func _sync_actor(entity: Dictionary, kind: String, index: int, selected_id: String, _delta: float, planning: bool) -> void:
	var id := str(entity.id)
	if not _entity_nodes.has(id):
		_entity_nodes[id] = _make_actor(kind, index)
	var entry: Dictionary = _entity_nodes[id]
	var root: Node3D = entry.node
	var pos := Vector2(float(entity.get("x", 0.0)), float(entity.get("z", 0.0)))
	var facing := float(entity.get("aim_facing", entity.get("facing", 0.0)))
	var body_facing := float(entity.get("body_facing", facing))
	var movement: float = pos.distance_to(entry.pos) if float(entry.last_time) >= 0.0 else 0.0
	entry.pos = pos
	root.position = surface_position(pos, 0.0)
	# Godot +Y rotation sends +X toward -Z, while simulation atan2 sends it +Z.
	entry.body.rotation.y = -body_facing
	entry.arrow.rotation.y = -facing
	entry.tick.rotation.y = -facing
	var alive := float(entity.get("hp", 100.0)) > 0
	var selected := kind == "unit" and (id == selected_id or _selected_units.has(id))
	entry.selection.visible = selected and alive
	entry.selection.scale = Vector3.ONE * (1.0 + (0.0 if _motion_reduced else sin(_clock * 6.0) * 0.07)) if selected and alive else Vector3.ONE
	var disc_shown := alive or _casualty_held(id)
	entry.ring.visible = disc_shown and not selected
	entry.tick.visible = disc_shown
	if is_instance_valid(entry.threat_halo): entry.threat_halo.visible = disc_shown
	entry.arrow.visible = alive and _show_facing and selected
	entry.label.modulate.a = 1.0 if selected or kind != "unit" else 0.75
	if not entry.visual.is_empty():
		entry.body.position = Vector3(0, 0.2, 0)
		var interaction: Dictionary = {}
		if entity.get("status", "") == "OPENING":
			for command: Dictionary in entity.get("commands", []):
				if command.get("type", "") in ["OPEN_DOOR", "OPEN_AND_FLASH", "KICK_DOOR", "PEEK_DOOR", "PEEK_CAMERA", "BREACH_DOOR"] and command.get("state", "") == "RUNNING":
					for door: Dictionary in _state.get("doors", []):
						if door.id == command.get("args", {}).get("door_id", ""):
							var progress: float = float(door.get("progress", 0.0))
							var handle: Vector3 = DoorGeometry.handle_world(door, progress)
							var palm_offset := (Vector3(pos.x, handle.y, pos.y) - handle).normalized() * 0.10 + Vector3.UP * 0.08
							interaction = {"progress": progress, "handle": handle + palm_offset}
		entry.visual["hit_delay"] = _hit_reaction_delay() # single source of truth for actor_visual's reaction timing
		ActorVisual.sync(entry.visual, entity, _state.get("presentation_events", _state.get("events", [])), _clock, movement, _motion_reduced, interaction)
		if not alive:
			entry.label.modulate.a = 0.35
	else:
		if alive:
			entry.body.rotation.z = 0.0
			entry.body.position.x = 0.0
			entry.body.position.z = 0.0
			if not _motion_reduced:
				for effect: Dictionary in _flashes:
					if effect.get("attacker", "") == id and effect.type == "shot":
						var recoil_age: float = float(effect.lifetime) - float(effect.remaining)
						var kick: float = exp(-recoil_age * 23.0) * 0.055
						entry.body.position.x = -cos(facing) * kick
						entry.body.position.z = -sin(facing) * kick
						entry.body.rotation.z = -kick * 0.6
			if not planning or float(entry.last_time) < 0.0:
				entry.body.position.y = 0.2
			if movement > 0.002 and not planning and not _motion_reduced:
				entry.phase = float(entry.phase) + movement * 9.0
				entry.left_leg.rotation.z = sin(float(entry.phase)) * 0.48
				entry.right_leg.rotation.z = -sin(float(entry.phase)) * 0.48
				entry.body.position.y += absf(sin(float(entry.phase))) * 0.035
			elif not planning and _clock > float(entry.last_time):
				entry.left_leg.rotation.z = 0.0
				entry.right_leg.rotation.z = 0.0
		else:
			entry.body.rotation.z = PI * 0.5
			entry.body.position.y = 0.4
			entry.label.modulate.a = 0.35
	var status_text := ""
	if not alive:
		status_text = "DOWN"
	elif float(entity.get("stunned", 0.0)) > 0.0:
		status_text = _t("기절 %.1f초") % float(entity.stunned)
	elif bool(entity.get("target", false)) or bool(entity.get("passive", false)):
		status_text = _t("표적 · 반격 없음")
	elif str(entity.get("status", "")) == "SURRENDERED":
		status_text = _t("투항 · 체포 필요")
	elif str(entity.get("status", "")) == "ARRESTED":
		status_text = _t("체포 완료")
	elif kind == "civilian" and str(entity.get("status", "")) == "PANIC":
		status_text = _t("공황 · 확보 필요")
	elif kind == "civilian" and str(entity.get("status", "")) == "FOLLOW":
		status_text = _t("호송 · %s") % str(entity.get("follow_unit_id", "")).to_upper()
	elif bool(entity.get("secured", false)):
		status_text = "SECURED"
	elif kind == "unit":
		var state_name := str(entity.get("status", ""))
		if state_name in ["WAITING", "RELOADING", "BLOCKED", "OPENING", "SWITCHING", "CAMERA_PEEK", "CAMERA"]:
			status_text = _t({"WAITING": "대기", "RELOADING": "재장전", "BLOCKED": "통로 대기", "OPENING": "문 열기", "SWITCHING": "무기 전환", "CAMERA_PEEK": "카메라", "CAMERA": "카메라"}[state_name])
			if state_name == "WAITING":
				for command in entity.get("commands", []):
					if str(command.get("state", "")) in ["RUNNING", "WAITING"]:
						if str(command.get("type", "")) in ["OPEN_DOOR", "OPEN_AND_FLASH"]:
							status_text = _t("문 대기")
						break
	if kind == "unit":
		for command: Dictionary in entity.get("commands", []):
			if command.get("state", "") in ["RUNNING", "WAITING"] and command.get("phase", "") == "WAIT_EXPLOSION": status_text = _t("폭발 대기")
	entry.status.text = status_text
	entry.status.font_size = 36 if float(entity.get("stunned", 0.0)) > 0.0 else 30
	entry.status.visible = not status_text.is_empty() and (selected or kind == "civilian" or float(entity.get("stunned", 0.0)) > 0.0 or str(entity.get("status", "")) in ["OPENING", "BLOCKED", "WAITING", "SURRENDERED", "ARRESTED"])
	if str(entity.get("status", "")) in ["SURRENDERED", "ARRESTED", "FOLLOW", "PANIC"]:
		entry.label.text = {"SURRENDERED": "↑", "ARRESTED": "✓", "FOLLOW": "→", "PANIC": "!"}[str(entity.status)]
		entry.label.modulate = Color("a1d6c3") if str(entity.status) in ["ARRESTED", "FOLLOW"] else Color("e6c992")
	else:
		entry.label.text = str(index + 1) if kind == "unit" else ("!" if kind == "enemy" else "C")
	entry.last_time = _clock
	root.visible = true

func _sync_broken_glass(panes: Array) -> void:
	var broken: Dictionary = {}
	for pane: Dictionary in panes:
		if float(pane.get("broken_at", 0.0)) <= _clock + 0.000001: broken[str(pane.get("object_kind", "")) + ":" + str(pane.get("object_id", ""))] = true
	for id: String in _glass_door_surfaces:
		for entry: Dictionary in _glass_door_surfaces[id]:
			if is_instance_valid(entry.mesh): entry.mesh.set_surface_override_material(int(entry.surface), entry.broken if broken.has(id) else entry.intact)
	for id: String in _glass_pane_nodes:
		var node: Node3D = _glass_pane_nodes[id]
		if is_instance_valid(node): node.visible = not broken.has(id)

func _sync_flash_projectiles(projectiles: Array) -> void:
	var present: Dictionary = {}
	for projectile: Dictionary in projectiles:
		var id := str(projectile.get("id", ""))
		var point: Array = projectile.get("position", [])
		if id.is_empty() or point.size() != 3: continue
		if not _flash_projectile_nodes.has(id) or not is_instance_valid(_flash_projectile_nodes[id]):
			var marker := Node3D.new()
			_marks.add_child(marker)
			_box(marker, Vector3.ZERO, Vector3(0.08, 0.13, 0.08), Color("535e50"), true)
			_sphere(marker, Vector3(0, 0.065, 0), Vector3(0.05, 0.035, 0.05), Color("d7c087"), true)
			_flash_projectile_nodes[id] = marker
		var node: Node3D = _flash_projectile_nodes[id]
		node.position = Vector3(float(point[0]), float(point[2]), float(point[1]))
		node.rotation.z = (_clock - float(projectile.get("released_at", _clock))) * 9.0 if projectile.get("phase", "") == "FLIGHT" else 0.0
		present[id] = true
	for id: String in _flash_projectile_nodes.keys():
		if not present.has(id):
			if is_instance_valid(_flash_projectile_nodes[id]): _flash_projectile_nodes[id].queue_free()
			_flash_projectile_nodes.erase(id)

func _sync_frag_projectiles(projectiles: Array) -> void:
	# Only the public sampled own-projectile list reaches the renderer.
	var present: Dictionary = {}
	for projectile: Dictionary in projectiles:
		var id: String = str(projectile.get("id", ""))
		var point: Array = projectile.get("position", [])
		if id.is_empty() or point.size() != 3: continue
		if not _frag_projectile_nodes.has(id) or not is_instance_valid(_frag_projectile_nodes[id]):
			var marker := Node3D.new()
			_marks.add_child(marker)
			_sphere(marker, Vector3.ZERO, Vector3(0.10, 0.13, 0.10), Color("63714f"), true)
			_box(marker, Vector3(0.0, 0.07, 0.0), Vector3(0.04, 0.03, 0.06), Color("ceba83"), true)
			_frag_projectile_nodes[id] = marker
		var node: Node3D = _frag_projectile_nodes[id]
		node.position = Vector3(float(point[0]), float(point[2]), float(point[1]))
		node.rotation.z = (_clock - float(projectile.get("released_at", _clock))) * 7.0 if projectile.get("phase", "") == "FLIGHT" else 0.0
		present[id] = true
	for id: String in _frag_projectile_nodes.keys():
		if not present.has(id):
			if is_instance_valid(_frag_projectile_nodes[id]): _frag_projectile_nodes[id].queue_free()
			_frag_projectile_nodes.erase(id)

func _sync_camera_memory(units: Array, visible: Dictionary) -> void:
	var newest: Dictionary = {}
	for unit: Dictionary in units:
		for observation: Dictionary in unit.get("camera_observations", []):
			var id := str(observation.get("id", ""))
			if visible.has(id): continue
			if not newest.has(id) or float(observation.get("observed_at", 0.0)) > float(newest[id].get("observed_at", 0.0)): newest[id] = observation
	for id: String in newest:
		var observation: Dictionary = newest[id]
		var ghost_id := "camera:" + id
		_sync_last_seen({"id": ghost_id, "last_seen": [observation.x, observation.z], "last_seen_time": observation.get("observed_at", _clock)})
		_ghost_nodes[ghost_id].label.text = "CAM · %ds" % int(maxf(0.0, _clock - float(observation.get("observed_at", _clock))))
		_ghost_nodes[ghost_id].label.modulate = Color("89c3ce")

## A separate World3D keeps briefing previews out of mission fog and recordings.
## The web panel supplies its transparent preview rectangle in CSS pixels.
func set_operator_preview(profile: Dictionary, rect: Dictionary) -> void:
	if profile.is_empty():
		if is_instance_valid(_operator_preview_layer):
			_operator_preview_layer.visible = false
			_operator_preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if not is_instance_valid(_operator_preview_layer):
		_operator_preview_layer = CanvasLayer.new()
		_operator_preview_layer.layer = 8
		add_child(_operator_preview_layer)
		_operator_preview_container = SubViewportContainer.new()
		_operator_preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_operator_preview_container.stretch = false
		_operator_preview_layer.add_child(_operator_preview_container)
		_operator_preview_viewport = SubViewport.new()
		_operator_preview_viewport.own_world_3d = true
		# Cover the mission viewport beneath this isolated equipment portrait.
		_operator_preview_viewport.transparent_bg = false
		_operator_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_operator_preview_container.add_child(_operator_preview_viewport)
		var stage := Node3D.new()
		_operator_preview_viewport.add_child(stage)
		var environment := WorldEnvironment.new()
		var light_environment := Environment.new()
		light_environment.background_mode = Environment.BG_COLOR
		light_environment.background_color = Color("cbd4c5")
		light_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		light_environment.ambient_light_color = Color("f0f2e9")
		light_environment.ambient_light_energy = 1.1
		environment.environment = light_environment
		stage.add_child(environment)
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-35, -45, 0)
		key.light_energy = 1.8
		stage.add_child(key)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-20, 135, 0)
		fill.light_color = Color("d6e3ed")
		fill.light_energy = 0.8
		stage.add_child(fill)
		var holder := Node3D.new()
		holder.position.y = 0.2
		stage.add_child(holder)
		_operator_preview_visual = ActorVisual.create(holder, false, Color("8fd0b2"))
		var portrait_camera := Camera3D.new()
		portrait_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		portrait_camera.size = 2.55
		portrait_camera.position = Vector3(3.0, 2.35, 4.0)
		stage.add_child(portrait_camera)
		portrait_camera.look_at(Vector3(0, 1.0, 0), Vector3.UP)
		portrait_camera.current = true
	var view_size := get_viewport().get_visible_rect().size
	var width := clampf(float(rect.get("width", 320.0)), 80.0, view_size.x)
	var height := clampf(float(rect.get("height", 240.0)), 80.0, view_size.y)
	_operator_preview_container.position = Vector2(clampf(float(rect.get("x", view_size.x - width - 30.0)), 0.0, view_size.x - width), clampf(float(rect.get("y", view_size.y - height - 30.0)), 0.0, view_size.y - height))
	_operator_preview_container.size = Vector2(width, height)
	_operator_preview_viewport.size = Vector2i(roundi(width), roundi(height))
	_operator_preview_layer.visible = true
	var entity := profile.duplicate(true)
	entity.merge({"id": "briefing-preview", "kind": "unit", "current_weapon": profile.get("weapon", "standard"), "active_weapon": "primary", "hp": 100.0, "status": "IDLE", "animation": "idle", "x": 0.0, "z": 0.0, "facing": 0.0, "aim_facing": 0.0, "stance": "standing", "movement_mode": "normal"}, true)
	ActorVisual.sync(_operator_preview_visual, entity, [], 0.0, 0.0, true, {})
	_operator_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _sync_smoke_zones(zones: Array) -> void:
	_smoke_mesh.clear_surfaces()
	if not zones.is_empty():
		_smoke_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _vertex_material())
		_triangle(_smoke_mesh, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Color.TRANSPARENT)
	for index: int in range(zones.size()):
		while _smoke_nodes.size() <= index:
			var smoke_root: Node3D = Node3D.new()
			smoke_root.name = "SmokeZone"
			_marks.add_child(smoke_root)
			var sprites: Array[Sprite3D] = []
			for cloud: int in range(5):
				var sprite: Sprite3D = Sprite3D.new()
				sprite.texture = SMOKE_TEXTURE
				sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				sprite.shaded = false
				sprite.render_priority = 3
				smoke_root.add_child(sprite)
				sprites.append(sprite)
			var label: Label3D = _label("", Color("d4dbd0"), 29, 0.008)
			label.position.y = 1.8
			label.no_depth_test = true
			smoke_root.add_child(label)
			_smoke_nodes.append({"node": smoke_root, "sprites": sprites, "label": label})
		var zone: Dictionary = zones[index]
		var entry: Dictionary = _smoke_nodes[index]
		var point: Vector2 = Vector2(float(zone.x), float(zone.z))
		var radius: float = float(zone.get("radius", 2.0))
		var remaining: float = float(zone.get("remaining", 0.0))
		entry.node.position = surface_position(point, 0.0)
		entry.node.visible = remaining > 0
		entry.label.text = "연막 %.1fs" % remaining
		for cloud: int in range(entry.sprites.size()):
			var angle: float = float(cloud) * TAU / 5.0 + (0.0 if _motion_reduced else _clock * 0.08)
			var sprite: Sprite3D = entry.sprites[cloud]
			sprite.position = Vector3(cos(angle) * radius * 0.35, 0.75 + float(cloud % 2) * 0.30, sin(angle) * radius * 0.35)
			sprite.pixel_size = radius * 1.6 / 512.0
			sprite.modulate = Color(0.65, 0.70, 0.68, minf(1.0, remaining) * 0.40)
		_flat_ring(_smoke_mesh, point, radius, 0.025, 0.265, Color(0.67, 0.78, 0.71, 0.65), 48)
	for index: int in range(zones.size(), _smoke_nodes.size()): _smoke_nodes[index].node.visible = false
	if not zones.is_empty(): _smoke_mesh.surface_end()

func _sync_sound_marks(state: Dictionary) -> void:
	# A complete event batch can exceed the HUD window. Keep public door
	# sounds for their existing visual lifetime, including subsequent empty batches.
	var reset := bool(state.get("presentation_reset", false)) or _clock < _sound_mark_time
	if reset:
		_door_sound_events.clear()
	for index in range(_door_sound_events.size() - 1, -1, -1):
		var age := _clock - float(_door_sound_events[index].get("time", _clock))
		if age < 0.0 or age >= 1.2: _door_sound_events.remove_at(index)
	var sound_events: Array = state.get("presentation_events", state.get("events", []))
	if state.has("presentation_events") and (reset or _sound_mark_time < 0.0):
		sound_events = sound_events.duplicate()
		sound_events.append_array(state.get("events", []))
	for event: Dictionary in sound_events:
		if str(event.get("type", "")) not in ["DOOR_ACTION", "DOOR_KICK", "DOOR_BREACH", "KICK_FAILED"] or float(event.get("radius", 0.0)) <= 0: continue
		var age := _clock - float(event.get("time", _clock))
		if age >= 0.0 and age < 1.2 and event not in _door_sound_events:
			_door_sound_events.append(event.duplicate(true))
	_sound_mark_time = _clock
	_sound_mesh.clear_surfaces()
	_sound_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _vertex_material())
	_triangle(_sound_mesh, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Color.TRANSPARENT)
	for zone: Dictionary in state.get("sound_zones", []):
		var age: float = _clock - float(zone.get("time", _clock))
		if age < 0 or age >= 3.0: continue
		var point: Vector2 = Vector2(float(zone.x), float(zone.z))
		_flat_ring(_sound_mesh, point, float(zone.get("radius", 2.8)), 0.025, 0.259, Color(0.87, 0.80, 0.61, (1.0 - age / 3.0) * 0.40), 48)
	for event: Dictionary in _door_sound_events:
		var age: float = _clock - float(event.get("time", _clock))
		var source: Variant = event.get("from", [])
		if age < 0 or age >= 1.2 or not source is Array or source.size() != 2: continue
		var point: Vector2 = Vector2(float(source[0]), float(source[1]))
		_flat_ring(_sound_mesh, point, float(event.radius), 0.028, 0.26, Color(0.90, 0.67, 0.38, (1.0 - age / 1.2) * 0.38), 64)
	_sound_mesh.surface_end()

## The record itself says the enemy is down or arrested.
func _record_neutralized(enemy: Dictionary) -> bool:
	return float(enemy.get("hp", 100.0)) <= 0.0 or str(enemy.get("status", "")) in ["INCAPACITATED", "ARRESTED"]

## Public position of an observed kill/arrest of this enemy: remembered from earlier events, or read from the
## events of the current frame (events are processed after the actors are synced).
func _neutral_position(id: String, state: Dictionary) -> Variant:
	if _neutralized_at.has(id): return _neutralized_at[id]
	for event: Dictionary in state.get("presentation_events", state.get("events", [])):
		var type := str(event.get("type", ""))
		if type == "INCAPACITATED" and str(event.get("kind", "")) == "enemy" and str(event.get("entity_id", "")) == id and event.has("to"):
			return Vector2(float(event.to[0]), float(event.to[1]))
		if type == "ARREST" and str(event.get("enemy_id", "")) == id and event.has("to"):
			return Vector2(float(event.to[0]), float(event.to[1]))
	return null

const GEAR_KEYS := ["weapon", "current_weapon", "active_weapon", "armor", "helmet", "sidearm", "attachments", "appearance", "equipment"]
func _remember_gear(id: String, enemy: Dictionary) -> void:
	var gear := {}
	for key: String in GEAR_KEYS:
		if enemy.has(key): gear[key] = enemy[key]
	_last_observed_gear[id] = gear

## Builds the dictionary a remembered corpse is drawn from, or {} when there is nothing observed to draw.
## Gear comes from the last time the enemy was seen (the memory record carries none), never operator defaults.
func _remembered_body(enemy: Dictionary, state: Dictionary) -> Dictionary:
	var id := str(enemy.get("id", ""))
	var at: Variant = null
	if not _record_neutralized(enemy):
		at = _neutral_position(id, state)
		if at == null: return {}
	var body: Dictionary = (_last_observed_gear[id] as Dictionary).duplicate() if _last_observed_gear.has(id) else {"armor": "none", "helmet": "none", "sidearm": "none", "weapon": str(enemy.get("weapon", "standard"))}
	for key: String in ["id", "name", "kind", "x", "z", "facing", "last_seen", "last_seen_time"]:
		if enemy.has(key): body[key] = enemy[key]
	body["commands"] = []
	if at == null:
		body["hp"] = float(enemy.get("hp", 0.0))
		body["status"] = str(enemy.get("status", "INCAPACITATED"))
	else:
		body["x"] = (at as Vector2).x
		body["z"] = (at as Vector2).y
		body["hp"] = 0.0
		body["status"] = "INCAPACITATED"
	return body

func _sync_last_seen(enemy: Dictionary) -> void:
	var id := str(enemy.id)
	var point: Array = enemy.last_seen
	if point.size() != 2:
		return
	if not _ghost_nodes.has(id):
		var node := Node3D.new()
		_marks.add_child(node)
		var ring := _ring_mesh(0.35, 0.385, Color("a78e70"), 24, true)
		ring.position.y = 0.235
		node.add_child(ring)
		var label := _label("?", Color("c3a88d"), 33, 0.009)
		label.position.y = 0.72
		node.add_child(label)
		_ghost_nodes[id] = {"node": node, "label": label}
	var entry: Dictionary = _ghost_nodes[id]
	entry.node.position = surface_position(Vector2(float(point[0]), float(point[1])), 0.0)
	entry.label.text = "?  %ds" % int(maxf(0.0, _clock - float(enemy.get("last_seen_time", _clock))))
	entry.node.visible = true

func set_prior_attempt(attempt: Dictionary, visible: bool = true) -> void:
	_prior_attempt = attempt.duplicate(true)
	_prior_attempt_visible = visible
	_draw_prior_attempt()
	if is_instance_valid(_prior_attempt_node): _prior_attempt_node.visible = false

func _draw_prior_attempt() -> void:
	if _prior_attempt_mesh == null: return
	_prior_attempt_mesh.clear_surfaces()
	if _prior_attempt.is_empty(): return
	_prior_attempt_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _vertex_material())
	_triangle(_prior_attempt_mesh, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Color.TRANSPARENT)
	var colors: Dictionary = {}
	for index: int in range(_mission.get("units", []).size()):
		colors[str(_mission.units[index].id)] = Color(UNIT_COLORS[index % UNIT_COLORS.size()], 0.27)
	for path: Dictionary in _prior_attempt.get("paths", []):
		if not colors.has(str(path.get("unit_id", ""))): continue
		var points: Array = path.get("points", [])
		for segment: Array in path.get("segments", []):
			if segment.size() != 2 or int(segment[0]) < 0 or int(segment[1]) < 0 or int(segment[0]) >= points.size() or int(segment[1]) >= points.size(): continue
			var a: Dictionary = points[int(segment[0])]
			var b: Dictionary = points[int(segment[1])]
			var from := Vector2(float(a.x), float(a.z))
			var to := Vector2(float(b.x), float(b.z))
			if from.distance_squared_to(to) < 0.000001: continue
			var normal := (to - from).normalized().orthogonal() * 0.025
			var low := float(a.get("base_height", 0.0)) + 0.26
			var high := float(b.get("base_height", 0.0)) + 0.26
			var av := Vector3(from.x + normal.x, low, from.y + normal.y)
			var bv := Vector3(to.x + normal.x, high, to.y + normal.y)
			var cv := Vector3(to.x - normal.x, high, to.y - normal.y)
			var dv := Vector3(from.x - normal.x, low, from.y - normal.y)
			_triangle(_prior_attempt_mesh, av, bv, cv, colors[str(path.unit_id)])
			_triangle(_prior_attempt_mesh, av, cv, dv, colors[str(path.unit_id)])
	for fallen: Dictionary in _prior_attempt.get("fallen", []):
		if not colors.has(str(fallen.get("unit_id", ""))): continue
		var center := Vector2(float(fallen.x), float(fallen.z))
		var height := float(fallen.get("base_height", 0.0)) + 0.28
		var color := Color(colors[str(fallen.unit_id)], 0.45)
		_flat_ring(_prior_attempt_mesh, center, 0.25, 0.04, height, color, 20)
		_flat_line(_prior_attempt_mesh, center - Vector2(0.14, 0.14), center + Vector2(0.14, 0.14), 0.04, height, color)
		_flat_line(_prior_attempt_mesh, center - Vector2(0.14, -0.14), center + Vector2(0.14, -0.14), 0.04, height, color)
	_prior_attempt_mesh.surface_end()

func _draw_paths(units: Array) -> void:
	_path_mesh.clear_surfaces()
	_path_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _vertex_material())
	_triangle(_path_mesh, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Color.TRANSPARENT)
	# Screen-constant route thickness: ~3px for any operator's route at
	# default zoom, 1.5x (~4.5px) for the selected operator, regardless of
	# camera zoom (world-units-per-pixel scales with camera.size). Every
	# route (not just the selected one) gets a darker underlay so the dashes
	# stay legible over the light floor tiles.
	var px_to_world := camera.size / maxf(_view_size.y, 1.0)
	var route_width_other := 3.0 * px_to_world * _line_width
	var route_width_selected := route_width_other * 1.5
	var route_halo_width := route_width_selected * 2.2
	var route_halo_width_other := route_width_other * 2.1
	# Compact icon/chip/text badges replace stacked route-command text labels.
	# "kind" drives the mesh drawn under each badge: door/aim/wait/signal get a
	# dark plate with an operator-colored ring and glyph; "chip" is a filled
	# operator-colored waypoint-number disc with a dark number; "text" is a
	# plain colored label for the rarer command types, unchanged from before.
	var badges: Array[Dictionary] = []
	for index in range(units.size()):
		var unit: Dictionary = units[index]
		if float(unit.get("hp", 100.0)) <= 0:
			continue
		var current := Vector2(float(unit.x), float(unit.z))
		var color: Color = UNIT_COLORS[index % UNIT_COLORS.size()]
		var selected := str(unit.id) == _selected or _selected_units.has(str(unit.id))
		color.a = 0.96 if selected else 0.18
		var command_index: int = -1
		var last_badge_key := ""
		for command in unit.get("commands", []):
			command_index += 1
			if str(command.get("state", "")) in ["SUCCEEDED", "FAILED", "CANCELLED"]:
				continue
			var args: Dictionary = command.get("args", {})
			var type := str(command.get("type", ""))
			var route: Array = command.get("path", args.get("path", []))
			if (type == "MOVE" and args.has("target")) or (type in ["OPEN_DOOR", "OPEN_AND_FLASH", "KICK_DOOR", "PEEK_DOOR", "PEEK_CAMERA", "BREACH_DOOR", "SHOTGUN_BREACH", "SECURE_CIVILIAN", "ARREST"] and not route.is_empty()):
				var target_data: Array = args.target if type == "MOVE" else route.back()
				var target := Vector2(float(target_data[0]), float(target_data[1]))
				var route_color := color
				if bool(command.get("conditional", false)):
					route_color.a *= 0.82
				var underlay_color := Color(0.07, 0.11, 0.1, 0.72 if selected else 0.4)
				var underlay_width := route_halo_width if selected else route_halo_width_other
				if route.is_empty():
					_dashed_line(_path_mesh, current, target, underlay_width, 0.240, underlay_color)
					_dashed_line(_path_mesh, current, target, route_width_selected if selected else route_width_other, 0.242, route_color)
				else:
					var previous := current
					for point in route.slice(int(command.get("path_cursor", 0))):
						var next := Vector2(float(point[0]), float(point[1]))
						_dashed_line(_path_mesh, previous, next, underlay_width, 0.240, underlay_color)
						_dashed_line(_path_mesh, previous, next, route_width_selected if selected else route_width_other, 0.242, route_color)
						previous = next
				if selected:
					_flat_ring(_path_mesh, target, 0.16, 0.04, 0.245, color, 20)
					if type == "MOVE":
						var selected_node: bool = str(unit.id) == _waypoint_unit and command_index == _selected_waypoint
						if selected_node:
							_flat_ring(_path_mesh, target, 0.31, 0.055, 0.255, Color("ffe7aa"), 28)
						_add_badge(badges, target + Vector2(0.0, 0.34), "chip", Color("ffe7aa") if selected_node else color, "%02d" % (command_index + 1))
				current = target
				last_badge_key = ""
			if not selected:
				continue
			match type:
				"OPEN_DOOR", "OPEN_AND_FLASH", "KICK_DOOR", "PEEK_DOOR", "PEEK_CAMERA", "BREACH_DOOR", "SHOTGUN_BREACH":
					var key := "door:%s" % str(args.get("door_id", ""))
					var door_point := current
					var door_found := false
					for door in _state.get("doors", _mission.get("doors", [])):
						if str(door.get("id", "")) == str(args.get("door_id", "")):
							door_point = Vector2(float(door.x), float(door.z))
							door_found = true
							break
					if key != last_badge_key:
						# Push the badge back toward the approaching unit (away from
						# the door) so its plate clears the door's standing geometry
						# instead of rendering hidden behind it.
						var away := current - door_point
						var offset := away.normalized() * 0.55 + away.normalized().orthogonal() * 0.16 if away.length() > 0.2 else Vector2(0.34, -0.3)
						_add_badge(badges, current + offset, "door", color)
					last_badge_key = key
					# A short connector identifies the intended door without widening
					# the collision proxy or changing its opening state.
					if door_found and current.distance_to(door_point) <= 1.8:
						_dashed_line(_path_mesh, current, door_point, 0.025 * _line_width, 0.25, Color(DOOR_COLOR, 0.72))
					if type == "OPEN_AND_FLASH" and args.get("target") is Array and args.target.size() == 2:
						var landing := Vector2(float(args.target[0]), float(args.target[1]))
						var flash_color := Color("efca81")
						_dashed_line(_path_mesh, current, landing, 0.035 * _line_width, 0.25, flash_color)
						_flat_ring(_path_mesh, landing, 3.0, 0.03, 0.25, Color(flash_color, 0.48), 48)
						_flat_ring(_path_mesh, landing, 0.22, 0.05, 0.26, flash_color, 24)
						_add_badge(badges, landing + Vector2(0.3, -0.3), "text", flash_color, _t("열고 섬광"))
					elif type == "PEEK_CAMERA":
						_add_badge(badges, current + Vector2(0.3, -0.3), "text", color, _t("카메라"))
				"SECURE_CIVILIAN":
					_add_badge(badges, current + Vector2(0.34, -0.34), "text", color, _t("확보"))
					last_badge_key = ""
				"ARREST":
					_add_badge(badges, current + Vector2(0.34, -0.34), "text", color, _t("체포"))
					last_badge_key = ""
				"FACE":
					var aim_color: Color = Color("e5c177") if bool(args.get("persistent", false)) else color
					var key := "aim:%s:%s" % [str(args.get("target", [])), str(args.get("persistent", false))]
					if args.has("target"):
						var target := Vector2(float(args.target[0]), float(args.target[1]))
						var end := current + current.direction_to(target) * minf(1.6, current.distance_to(target))
						_flat_line(_path_mesh, current, end, 0.038 * _line_width, 0.252, aim_color)
						_arrow_head(_path_mesh, current, end, 0.18, 0.252, aim_color)
					if key != last_badge_key:
						_add_badge(badges, current + Vector2(0.34, -0.3), "aim", aim_color)
					last_badge_key = key
				"WAIT", "WAIT_FOR_SIGNAL":
					var channel := str(args.get("signal", "A"))
					var key := "wait:%.2f:%.2f" % [current.x, current.y] if type == "WAIT" else "signal:%s:%.2f:%.2f" % [channel, current.x, current.y]
					if key != last_badge_key:
						if type == "WAIT":
							_add_badge(badges, current + Vector2(0.34, -0.3), "wait", color)
						else:
							_add_badge(badges, current + Vector2(0.34, -0.3), "signal", color, channel)
					last_badge_key = key
				"SWITCH_WEAPON":
					_add_badge(badges, current + Vector2(0.34, -0.34), "text", color, _t("무기 전환"))
					last_badge_key = ""
				"RELOAD":
					_add_badge(badges, current + Vector2(0.34, -0.34), "text", color, _t("재장전"))
					last_badge_key = ""
				"THROW_STUN", "THROW_SMOKE":
					if args.has("target"):
						var target := Vector2(float(args.target[0]), float(args.target[1]))
						_flat_ring(_path_mesh, target, 3.0, 0.025, 0.245, Color(0.95, 0.76, 0.41, 0.5), 48)
					_add_badge(badges, current + Vector2(0.34, -0.34), "text", color, _t("연막" if type == "THROW_SMOKE" else "섬광"))
					last_badge_key = ""
				"THROW_FRAG":
					if args.has("target"):
						var target := Vector2(float(args.target[0]), float(args.target[1]))
						_flat_ring(_path_mesh, target, float(EquipmentCatalog.frag_stats().radius), 0.025, 0.245, Color(0.92, 0.45, 0.25, 0.5), 48)
						_add_badge(badges, current + Vector2(0.34, -0.34), "text", color, _t("파편"))
					last_badge_key = ""
	# Badges at nearby positions are pushed apart so they never overlap,
	# regardless of how close their source commands are in world space.
	badges = _resolve_badge_overlap(badges, 0.78)
	for badge in badges:
		_draw_badge(_path_mesh, badge)
	_path_mesh.surface_end()
	_sync_badge_labels(badges)

## Appends a route badge descriptor. `kind` selects the plate/glyph drawn by
## _draw_badge; `label` (door/aim/wait have none) is rendered by
## _sync_badge_labels on top of the mesh.
func _add_badge(list: Array[Dictionary], point: Vector2, kind: String, color: Color, label: String = "") -> void:
	list.append({"point": point, "kind": kind, "color": color, "label": label})

## Nudges later badges away from earlier ones along the vector between them
## (or a deterministic fallback angle when they land on the same spot) until
## no pair is closer than min_dist. Returns a new array (badge dicts are
## copied) so callers always see the resolved positions.
func _resolve_badge_overlap(badges: Array[Dictionary], min_dist: float) -> Array[Dictionary]:
	var resolved: Array[Dictionary] = []
	for badge in badges:
		resolved.append(badge.duplicate())
	for i in range(resolved.size()):
		for _attempt in range(6):
			var moved := false
			var point: Vector2 = resolved[i].point
			for j in range(i):
				var delta: Vector2 = point - (resolved[j].point as Vector2)
				var dist := delta.length()
				if dist < min_dist:
					var dir := delta.normalized() if dist > 0.001 else Vector2.RIGHT.rotated(float(i) * 2.4)
					point += dir * (min_dist - dist + 0.03)
					moved = true
			resolved[i].point = point
			if not moved:
				break
	return resolved

func _draw_badge(mesh: ImmediateMesh, badge: Dictionary) -> void:
	var point: Vector2 = badge.point
	var color: Color = badge.color
	match str(badge.kind):
		"door", "aim", "wait", "signal":
			_flat_disc(mesh, point, 0.24, 0.258, Color(0.07, 0.08, 0.085, 0.92), 20)
			_flat_ring(mesh, point, 0.24, 0.03, 0.2585, color, 20)
			match str(badge.kind):
				"door":
					var frame_top := point + Vector2(-0.1, -0.13)
					var frame_bottom := point + Vector2(-0.1, 0.13)
					_flat_line(mesh, frame_top, frame_bottom, 0.032, 0.259, color)
					_flat_line(mesh, frame_top, point + Vector2(0.13, -0.06), 0.032, 0.259, color)
					_flat_disc(mesh, point + Vector2(0.08, 0.04), 0.026, 0.2595, color, 10)
				"aim":
					_flat_ring(mesh, point, 0.1, 0.024, 0.259, color, 16)
					_flat_line(mesh, point + Vector2(-0.17, 0), point + Vector2(-0.08, 0), 0.022, 0.259, color)
					_flat_line(mesh, point + Vector2(0.08, 0), point + Vector2(0.17, 0), 0.022, 0.259, color)
					_flat_line(mesh, point + Vector2(0, -0.17), point + Vector2(0, -0.08), 0.022, 0.259, color)
					_flat_line(mesh, point + Vector2(0, 0.08), point + Vector2(0, 0.17), 0.022, 0.259, color)
				"wait":
					_flat_ring(mesh, point, 0.13, 0.024, 0.259, color, 20)
					_flat_line(mesh, point, point + Vector2(0, -0.09), 0.022, 0.2595, color)
					_flat_line(mesh, point, point + Vector2(0.06, 0.02), 0.022, 0.2595, color)
				"signal":
					var flag_color: Color = SIGNAL_COLORS.get(str(badge.label), color)
					var mast_bottom := point + Vector2(0, 0.14)
					var mast_top := point + Vector2(0, -0.14)
					_flat_line(mesh, mast_bottom, mast_top, 0.024, 0.259, flag_color)
					_triangle(mesh, Vector3(mast_top.x, 0.2595, mast_top.y), Vector3(mast_top.x + 0.17, 0.2595, mast_top.y + 0.05), Vector3(mast_top.x, 0.2595, mast_top.y + 0.12), flag_color)
		"chip":
			_flat_disc(mesh, point, 0.2, 0.258, color, 20)
			_flat_ring(mesh, point, 0.2, 0.026, 0.2585, Color(0.07, 0.08, 0.085, 0.95), 20)
		"text":
			pass

## Reuses the pooled Label3D nodes for the text each badge needs on top of
## its mesh: a dark number on numbered-waypoint chips, a channel letter on
## signal badges, or the plain word for the rarer command types. Door/aim/
## wait badges are icon-only and get no label.
func _sync_badge_labels(badges: Array[Dictionary]) -> void:
	for index in range(badges.size()):
		while _waypoint_nodes.size() <= index:
			var label := _label("", Color.WHITE, 36, 0.009)
			label.outline_size = 6
			label.no_depth_test = true
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_marks.add_child(label)
			_waypoint_nodes.append(label)
		var badge: Dictionary = badges[index]
		var node: Label3D = _waypoint_nodes[index]
		var text := str(badge.label)
		if text.is_empty():
			node.visible = false
			continue
		node.text = text
		var point: Vector2 = badge.point
		match str(badge.kind):
			"chip":
				# No outline: at this on-screen size an outline this thick
				# swallows the thin digit strokes entirely, so plain dark fill
				# against the light chip carries the contrast instead. The
				# label is nudged slightly off the chip's exact (x,z) center:
				# under this orthogonal top-down camera a Label3D exactly
				# coincident with the opaque mesh beneath it gets hidden by a
				# render-order quirk, even with no_depth_test enabled.
				node.font_size = 32
				node.outline_size = 0
				node.modulate = Color(0.05, 0.05, 0.05)
				node.outline_modulate = Color(0.05, 0.05, 0.05)
				node.position = surface_position(point + Vector2(0.1, 0), 0.68)
			"signal":
				node.font_size = 26
				node.outline_size = 0
				node.modulate = Color(0.97, 0.96, 0.92)
				node.outline_modulate = Color(0.97, 0.96, 0.92)
				node.position = surface_position(point + Vector2(0.08, -0.07), 0.71)
			_:
				node.font_size = 36
				node.outline_size = 6
				node.modulate = badge.color
				node.outline_modulate = Color(0.04, 0.05, 0.05, 1.0)
				node.position = surface_position(point + Vector2(0, -0.28), 0.68)
		node.visible = true
	for index in range(badges.size(), _waypoint_nodes.size()):
		_waypoint_nodes[index].visible = false

func _rebuild_obstacles() -> void:
	_obstacles.clear()
	for wall in _mission.get("walls", []):
		_obstacles.append(_rect_from(wall))
	for prop in _mission.get("props", []):
		if str(prop.get("cover", Navigation.cover_default(str(prop.get("type", "")), prop.get("solid")))) == "full":
			_obstacles.append(_rect_from(prop))

func _draw_cone(_units: Array) -> void:
	_cone_mesh.clear_surfaces()
	if not _show_fov: return
	# Reuse the exact occluded sight polygon already computed for the fog.
	# Casting another fan here duplicated the most expensive visibility work.
	var polygon: PackedVector2Array = _visibility.polygon_for(_selected)
	if polygon.size() < 3: return
	var origin := polygon[0]
	_cone_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _vertex_material())
	for i in range(1, polygon.size()):
		var end := polygon[i]
		if i > 1:
			var previous := polygon[i - 1]
			_triangle(_cone_mesh, Vector3(origin.x, 0.217, origin.y), Vector3(previous.x, 0.217, previous.y), Vector3(end.x, 0.217, end.y), Color(0.64, 0.85, 0.68, 0.075))
			_flat_line(_cone_mesh, previous, end, 0.035, 0.222, Color(0.86, 1.0, 0.9, 0.6))
		if i == 1 or i == polygon.size() - 1:
			_flat_line(_cone_mesh, origin, end, 0.05, 0.222, Color(0.9, 1.0, 0.94, 0.92))
	_cone_mesh.surface_end()

func _ray_distance(origin: Vector2, direction: Vector2, maximum: float, rects: Variant = null, doors: Variant = null) -> float:
	var result := maximum
	for rect: Rect2 in (_obstacles if rects == null else rects):
		var near := 0.0
		var far := maximum
		var hit := true
		for axis in range(2):
			var o: float = origin[axis]
			var d: float = direction[axis]
			var low: float = rect.position[axis]
			var high: float = rect.end[axis]
			if absf(d) < 0.00001:
				if o < low or o > high:
					hit = false
					break
			else:
				var t1 := (low - o) / d
				var t2 := (high - o) / d
				near = maxf(near, minf(t1, t2))
				far = minf(far, maxf(t1, t2))
				if near > far:
					hit = false
					break
		if hit and far >= 0.0:
			result = minf(result, maxf(0.0, near - 0.015))
	for door in (_state.get("doors", _mission.get("doors", [])) if doors == null else doors):
		var leaf_distance: float = DoorGeometry.ray_distance(door, origin, direction, result)
		if leaf_distance < result:
			result = maxf(0.0, leaf_distance - 0.015)
	return result

func _restore_flash_visuals(state: Dictionary) -> void:
	# A seek reconstructs only the flash already active at the landed clock.
	# It does not replay sounds, shots or earlier flashes on a new timeline.
	for event: Dictionary in state.get("events", []):
		var age := _clock - float(event.get("time", _clock))
		if event.get("type", "") == "STUN" and event.has("to") and age >= 0.0 and age < 0.38:
			_flashes.append({"to": event.to.duplicate(), "remaining": 0.38 - age, "fresh": true, "type": "stun", "seq": int(event.get("seq", 0)), "event_time": event.time, "radius": float(event.get("radius", 3.0)), "smoke_sprite": _effect_sprite(SMOKE_TEXTURE), "flash_sprite": _effect_sprite(FLASH_TEXTURE)})
		elif event.get("type", "") == "FRAG" and event.get("observed", false) == true and event.has("to") and age >= 0.0 and age < 0.5:
			_append_frag_effect(event)

func _append_frag_effect(event: Dictionary) -> void:
	_flashes.append({"to": event.to.duplicate(), "remaining": maxf(0.0, 0.5 - (_clock - float(event.time))), "lifetime": 0.5, "fresh": true, "type": "frag", "seq": int(event.get("seq", 0)), "event_time": float(event.time), "radius": float(event.get("radius", 0.0)), "target_height": float(event.get("target_height", 0.0)), "smoke_sprite": _effect_sprite(SMOKE_TEXTURE), "flash_sprite": _effect_sprite(FLASH_TEXTURE)})

func _update_effects(state: Dictionary, _delta: float, planning: bool) -> void:
	var effect_delta := maxf(_clock - _effect_time, 0.0)
	# Scrubbing backwards must not re-fire the historical event list. Subsequent
	# forward events are still accepted as their new sequence numbers arrive.
	if _clock < _effect_time - 0.0001:
		_clear_flashes()
		_last_event_seq = -1
		for event in state.get("events", []):
			_last_event_seq = maxi(_last_event_seq, int(event.get("seq", -1)))
		_room_clear_flashes.clear()
		_resync_room_cleared(state)
		_shake_remaining = 0.0
		_freeze_remaining = 0.0
		_reset_hit_links()
	_effect_time = _clock
	for event in state.get("presentation_events", state.get("events", [])):
		var seq := int(event.get("seq", -1))
		if seq <= _last_event_seq:
			continue
		var event_time := float(event.get("time", _clock))
		# Display interpolation can trail the simulation by one tick. Do not fire
		# the flash before the actor's presentation clock reaches the shot.
		if event_time > _clock + 0.0001:
			continue
		_last_event_seq = seq
		var type := str(event.get("type", "")).to_upper()
		if event.has("from") and event.has("to") and type in ["SHOT", "FIRE", "ATTACK", "HIT"]:
			if _clock - event_time > 0.42:
				continue
			# Snapshot the observed muzzle once: smoke must not chase a moving gun,
			# and an actor hidden by fog of war must not leak its current position.
			var origin := Vector2(float(event.from[0]), float(event.from[1]))
			var target := Vector2(float(event.to[0]), float(event.to[1]))
			var direction := (target - origin).normalized()
			var side := Vector2(-direction.y, direction.x)
			var fallback := origin + direction * 1.12 + side * 0.18
			var muzzle := surface_position(fallback, 1.23)
			var attacker := str(event.get("attacker_id", ""))
			_last_shot_direction = direction
			if bool(event.get("hit", false)): _last_hit_shot = {"time": event_time, "to": target}
			if _entity_nodes.has(attacker):
				var actor: Dictionary = _entity_nodes[attacker]
				var visual: Dictionary = actor.get("visual", {})
				var socket: Node3D = visual.get("muzzle")
				if is_instance_valid(socket) and socket.is_visible_in_tree():
					muzzle = to_local(socket.global_position)
			# Back-dated to the event time (like the frag effect) so every layer measures tracer
			# arrival from the same instant, even when the clock jumps a whole frame at 4x replay.
			var late := clampf(_clock - event_time, 0.0, 0.42)
			var hit := bool(event.get("hit", false))
			var pellets := (3 + seq % 3) if str(event.get("weapon", "")) == "shotgun" else 1
			var shot := {"from": event.from.duplicate(), "to": event.to.duplicate(), "muzzle": muzzle, "impact": surface_position(target, 1.1), "remaining": 0.42 - late, "lifetime": 0.42, "late": late, "fresh": true, "type": "shot", "seq": seq, "event_time": event_time, "attacker": attacker, "hit": hit, "protection": str(event.get("protection", "unprotected")), "hostile": bool(event.get("hostile", false)), "pellets": pellets, "dir": direction, "plan": _plan_tracers(seq, pellets, hit, Vector2(muzzle.x, muzzle.z), target), "smoke_sprite": _effect_sprite(SMOKE_TEXTURE)}
			if not _flash_reduced: shot["flash_sprite"] = _effect_sprite(FLASH_TEXTURE)
			if hit: shot["impact_sprite"] = _effect_sprite(SMOKE_TEXTURE)
			_flashes.append(shot)
		elif event.has("from") and type == "GLASS_BREAK":
			if _clock - event_time <= 0.45: _flashes.append({"to": event.from.duplicate(), "remaining": 0.45, "lifetime": 0.45, "fresh": true, "type": "glass", "seq": seq, "event_time": event_time})
		elif event.has("to") and type in ["STUN", "STUN_DETONATED", "GRENADE"]:
			if _clock - event_time <= 0.38:
				# Like gunfire, a newly received blast gets a visible first frame even after a slow render.
				_flashes.append({"to": event.to.duplicate(), "remaining": 0.38, "fresh": true, "type": "stun", "seq": seq, "event_time": event_time, "radius": float(event.get("radius", 3.0)), "smoke_sprite": _effect_sprite(SMOKE_TEXTURE), "flash_sprite": _effect_sprite(FLASH_TEXTURE)})
		elif event.has("to") and type == "FRAG" and event.get("observed", false) == true:
			if _clock - event_time < 0.5: _append_frag_effect(event)
		elif event.has("from") and type == "DOOR_ACTION" and str(event.get("kind", "")) in ["KICK_DOOR", "BREACH_DOOR", "SHOTGUN_BREACH"]:
			# Plan 2-1 breach fx: a brief camera shake (gated by the screen_shake
			# setting and reduced motion) plus a dust burst at the door.
			if _screen_shake_enabled and not _motion_reduced:
				_request_kick(SHAKE_DURATION, SHAKE_MAGNITUDE, Vector2.ZERO)
			if _clock - event_time <= 0.5:
				_flashes.append({"to": event.from.duplicate(), "remaining": 0.5, "lifetime": 0.5, "fresh": true, "type": "dust", "seq": seq, "event_time": event_time, "smoke_sprite": _effect_sprite(SMOKE_TEXTURE)})
		elif event.has("to") and type == "CONTACT":
			if _clock - event_time <= 0.6:
				_flashes.append({"to": event.to.duplicate(), "remaining": 0.6, "lifetime": 0.6, "fresh": true, "type": "spotted", "seq": seq, "event_time": event_time, "enemy_id": str(event.get("enemy_id", ""))})
		elif event.has("to") and type == "INCAPACITATED":
			var down_kind := str(event.get("kind", ""))
			var down_at := Vector2(float(event.to[0]), float(event.to[1]))
			# A casualty caused by an observed hit waits for that shot's tracer to arrive.
			var after_shot: bool = absf(float(_last_hit_shot.time) - event_time) < 0.001 and (_last_hit_shot.to as Vector2).distance_to(down_at) < 0.05
			if after_shot and event.has("entity_id"):
				_casualty_hold[str(event.entity_id)] = event_time
				_hold_casualty_disc(str(event.entity_id))
			if _clock - event_time <= STAMP_LIFE:
				var lifetime := STAMP_LIFE + (_hit_reaction_delay() if after_shot else 0.0)
				# An observed enemy kill gets the crisp stamp; other casualties keep the plain mark.
				var casualty := {"to": event.to.duplicate(), "remaining": lifetime - clampf(_clock - event_time, 0.0, lifetime), "lifetime": lifetime, "fresh": true, "type": "kill_stamp" if down_kind == "enemy" else "neutralized_mark", "seq": seq, "event_time": event_time, "after_shot": after_shot}
				if _screen_shake_enabled and not _motion_reduced and down_kind in ["enemy", "unit"]:
					casualty["kick"] = {"duration": KILL_KICK_DURATION if down_kind == "enemy" else DOWN_KICK_DURATION, "magnitude": KILL_KICK_MAGNITUDE if down_kind == "enemy" else DOWN_KICK_MAGNITUDE, "direction": _last_shot_direction if after_shot else Vector2.from_angle(_fx_rand(seq, 77) * TAU)}
				_flashes.append(casualty)
			if down_kind == "enemy":
				var entity_id := str(event.get("entity_id", ""))
				_room_neutralized_ids[entity_id] = true
				_neutralized_at[entity_id] = down_at
		elif event.has("to") and type == "ARREST":
			if _clock - event_time <= 0.8:
				_flashes.append({"to": event.to.duplicate(), "remaining": 0.8 - clampf(_clock - event_time, 0.0, 0.8), "lifetime": 0.8, "fresh": true, "type": "neutralized_mark", "seq": seq, "event_time": event_time, "after_shot": false})
			var enemy_id := str(event.get("enemy_id", ""))
			_room_neutralized_ids[enemy_id] = true
			_neutralized_at[enemy_id] = Vector2(float(event.to[0]), float(event.to[1]))
		elif CALL_LABELS.has(type):
			_remember_call(event, state)
			if type == "CALL_ROOM_CLEAR": _mark_room_clear(str(event.get("unit_id", "")), event.get("from", []), state, event)
		elif type == "MISSION_END":
			# 0.4s slow-mo before the result screen (plan 5). presentation_time
			# is clock-driven from simulation state (see _clock above), not
			# delta-integrated, and RESULT mode already holds it static the
			# instant main.gd flips mode -- so the scene is already a de facto
			# freeze-frame with nothing left to visibly slow down. Per the
			# plan's documented fallback ("freeze-frame hold" when slow-mo
			# can't be done safely), this drives a brief camera punch-in
			# instead (see the camera.size adjustment in display()): a
			# presentation-only beat that punctuates the final kill without
			# touching simulation or replay timing at all.
			_freeze_remaining = MISSION_END_FREEZE
	_event_mesh.clear_surfaces()
	if _flashes.is_empty() and _room_clear_flashes.is_empty():
		return
	_event_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _vertex_material())
	_triangle(_event_mesh, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Color.TRANSPARENT)
	for index in range(_flashes.size() - 1, -1, -1):
		var effect: Dictionary = _flashes[index]
		# The red "spotted" ping marks the enemy's position, so it waits for the enemy itself (sighting hold).
		if effect.type == "spotted" and _held_enemies.has(str(effect.get("enemy_id", ""))):
			effect["fresh"] = true
			continue
		# Always present a newly received shot once, even after a slow frame.
		if not planning and not bool(effect.get("fresh", false)):
			effect.remaining = float(effect.remaining) - effect_delta
		effect["fresh"] = false
		if float(effect.remaining) <= 0:
			_free_effect(effect)
			_flashes.remove_at(index)
			continue
		var target := Vector2(float(effect.to[0]), float(effect.to[1]))
		if effect.type == "shot":
			var origin := Vector2(float(effect.from[0]), float(effect.from[1]))
			var age: float = float(effect.lifetime) - float(effect.remaining)
			var direction: Vector2 = (target - origin).normalized()
			var side: Vector2 = Vector2(-direction.y, direction.x)
			var muzzle_3d: Vector3 = effect.muzzle
			var muzzle := Vector2(muzzle_3d.x, muzzle_3d.z)
			var seed_value: float = float(int(effect.seq) % 7) / 7.0
			var flash_age := maxf(age - float(effect.get("late", 0.0)), 0.0) # the muzzle flash always plays once, even when first seen late
			var flash: Sprite3D = effect.get("flash_sprite")
			if flash != null:
				flash.position = muzzle_3d
				# The first frames pop larger so the muzzle reads at the default zoom.
				flash.pixel_size = (1.45 + seed_value * 0.20) * (1.0 + 0.4 * clampf(1.0 - flash_age / MUZZLE_POP, 0.0, 1.0)) / 512.0
				flash.visible = not _flash_reduced and flash_age < 0.075
				flash.modulate = Color(1.0, 0.87, 0.62, clampf(1.0 - flash_age / 0.075, 0.0, 1.0))
			if flash_age < MUZZLE_FLOOR_LIGHT and not _flash_reduced:
				# Floor light goes over the fog, so shooting in the dark still reads.
				var pulse := 1.0 - flash_age / MUZZLE_FLOOR_LIGHT
				_glow_disc(Vector3(muzzle.x, 0.24, muzzle.y), 0.85 + 0.35 * (1.0 - pulse), Color(1.0, 0.86, 0.56, 0.5 * pulse), Color(1.0, 0.7, 0.32, 0.0), 16)
			_draw_tracers(effect, muzzle_3d, age)
			var reaction_age := age - _hit_reaction_delay()
			if bool(effect.hit): _draw_impact_burst(effect, reaction_age)
			var smoke: Vector2 = muzzle + direction * age * 0.30 + side * age * 0.10
			var smoke_sprite: Sprite3D = effect.smoke_sprite
			smoke_sprite.position = Vector3(smoke.x, muzzle_3d.y + age * 0.32, smoke.y)
			smoke_sprite.pixel_size = (0.36 + age * 0.95) / 512.0
			smoke_sprite.modulate = Color(0.68, 0.69, 0.65, (1.0 - age / 0.42) * 0.40)
			# Brass follows a short arc from a port behind the captured muzzle.
			var brass: Vector2 = muzzle - direction * 0.42 + side * (0.07 + age * 1.2)
			var brass_height: float = maxf(surface_offset(brass) + 0.22, muzzle_3d.y - 0.02 + age * 0.7 - 6.5 * age * age)
			_flat_line(_event_mesh, brass, brass + Vector2(cos(age * 35.0), sin(age * 35.0)) * 0.055, 0.022, brass_height, Color(0.69, 0.53, 0.26, 0.80))
			var impact_sprite: Sprite3D = effect.get("impact_sprite") # only allocated for hits: a miss has no validated wall endpoint
			if impact_sprite != null:
				impact_sprite.visible = reaction_age > 0.018 and reaction_age < 0.22
				impact_sprite.position = (effect.impact as Vector3) + Vector3(direction.x * reaction_age * 0.65, reaction_age * 0.35, direction.y * reaction_age * 0.65)
				impact_sprite.pixel_size = (0.65 + reaction_age * 1.1) / 512.0
				impact_sprite.modulate = Color(0.68, 0.56, 0.43, maxf(0.0, 1.0 - reaction_age / 0.22) * 0.82)
			# Confirmed-hit cue remains subtle when reduced flash is enabled.
			if bool(effect.hit) and reaction_age >= 0.0 and reaction_age < 0.30:
				var impact_alpha: float = (1.0 - reaction_age / 0.30) * (0.20 if _flash_reduced else 0.65)
				_flat_ring(_event_mesh, target, 0.28 + reaction_age * 0.55, 0.035, 0.24, Color(0.53, 0.85, 0.82, impact_alpha) if effect.get("protection", "") == "blocked" else Color(0.91, 0.54, 0.35, impact_alpha), 20)
		elif effect.type == "dust":
			var age: float = float(effect.lifetime) - float(effect.remaining)
			var sprite: Sprite3D = effect.smoke_sprite
			sprite.position = surface_position(target, 0.9 + age * 0.55)
			sprite.pixel_size = (0.5 + age * 1.6) / 512.0
			sprite.modulate = Color(0.78, 0.74, 0.62, (1.0 - age / 0.5) * 0.45)
		elif effect.type == "spotted" and not _flash_reduced:
			# Brief red ground ping at a freshly spotted threat (plan 5).
			var age: float = float(effect.lifetime) - float(effect.remaining)
			var radius := 0.4 + age * 1.6
			_flat_ring(_event_mesh, target, radius, 0.06, 0.2, Color(0.88, 0.28, 0.24, maxf(0.0, 1.0 - age / 0.6) * 0.7), 24)
		elif effect.type == "kill_stamp" or effect.type == "neutralized_mark":
			var casualty_age: float = float(effect.lifetime) - float(effect.remaining) - (_hit_reaction_delay() if bool(effect.get("after_shot", false)) else 0.0)
			if casualty_age >= 0.0 and effect.has("kick"):
				# The camera kick lands with the stamp, once, when the tracer arrives (skipped if first seen far too late).
				var kick: Dictionary = effect.kick
				effect.erase("kick")
				if _screen_shake_enabled and not _motion_reduced and casualty_age <= 0.1: _request_kick(float(kick.duration), float(kick.magnitude), kick.direction)
			if casualty_age < 0.0: continue
			if effect.type == "kill_stamp":
				_draw_kill_stamp(target, casualty_age, STAMP_LIFE - casualty_age)
				continue
			if _flash_reduced: continue
			# A short-lived X marker over a neutralized/arrested threat (plan 5).
			var alpha := clampf(1.0 - casualty_age / 0.8, 0.0, 1.0)
			var color := Color(0.95, 0.91, 0.84, alpha * 0.85)
			var arm := 0.26
			_flat_line(_event_mesh, target + Vector2(-arm, -arm), target + Vector2(arm, arm), 0.05, 0.3, color)
			_flat_line(_event_mesh, target + Vector2(-arm, arm), target + Vector2(arm, -arm), 0.05, 0.3, color)
		elif effect.type == "glass":
			var age := 0.45 - float(effect.remaining)
			for shard: int in range(8):
				var direction := Vector2.RIGHT.rotated(float(shard) * 2.399963)
				var point := target + direction * age * (0.8 + float(shard % 3) * 0.4)
				var size := 0.035 + float(shard % 2) * 0.025
				_triangle(_event_mesh, surface_position(point, 0.24), surface_position(point + direction * size, 0.25), surface_position(point + direction.orthogonal() * size, 0.25), Color(0.65, 0.85, 0.86, maxf(0.0, 1.0 - age / 0.45) * 0.75))
		elif effect.type == "frag":
			var age := 0.5 - float(effect.remaining)
			var center := Vector3(target.x, float(effect.target_height) + 0.12, target.y)
			var blast: Sprite3D = effect.flash_sprite
			blast.position = center
			blast.pixel_size = (1.0 + age * 5.0) / 512.0
			blast.visible = not _flash_reduced and age < 0.08
			blast.modulate = Color(1.0, 0.62, 0.24, maxf(0.0, 1.0 - age / 0.08))
			var residue: Sprite3D = effect.smoke_sprite
			residue.position = center + Vector3.UP * age * 0.65
			residue.pixel_size = (0.65 + age * 4.0) / 512.0
			residue.modulate = Color(0.45, 0.43, 0.38, maxf(0.0, 1.0 - age / 0.5) * 0.65)
			var radius := maxf(0.05, float(effect.radius) * minf(age / 0.20, 1.0))
			_flat_ring(_event_mesh, target, radius, 0.04, float(effect.target_height) + 0.02, Color(0.89, 0.49, 0.24, maxf(0.0, 1.0 - age / 0.5) * (0.18 if _flash_reduced else 0.55)), 40)
		elif effect.type == "stun":
			var age := 0.38 - float(effect.remaining)
			var center := surface_position(target, 0.35)
			var blast: Sprite3D = effect.flash_sprite
			blast.position = center
			blast.pixel_size = (2.5 + age * 5.0) / 512.0
			blast.visible = not _flash_reduced and age < 0.18
			blast.modulate = Color(1.0, 0.98, 0.85, maxf(0.0, 1.0 - age / 0.18))
			var residue: Sprite3D = effect.smoke_sprite
			residue.position = center + Vector3.UP * age * 0.8
			residue.pixel_size = (0.55 + age * 3.5) / 512.0
			residue.modulate = Color(0.78, 0.80, 0.75, maxf(0.0, 1.0 - age / 0.38) * 0.35)
			var radius := maxf(0.05, float(effect.get("radius", 3.0)) * minf(age / 0.22, 1.0))
			_flat_ring(_event_mesh, target, radius, 0.04, 0.28, Color(0.95, 0.87, 0.65, maxf(0.0, 1.0 - age / 0.38) * (0.20 if _flash_reduced else 0.62)), 40)
		elif not _flash_reduced:
			var radius := (1.0 - float(effect.remaining) / 0.38) * 2.0
			_flat_ring(_event_mesh, target, maxf(0.05, radius), 0.075, 0.28, Color(0.95, 0.87, 0.65, float(effect.remaining) / 0.38), 32)
	# Plan 5: a 0.6s operator-colored floor outline flash marking a cleared room.
	for index in range(_room_clear_flashes.size() - 1, -1, -1):
		var flash: Dictionary = _room_clear_flashes[index]
		if bool(flash.get("fresh", false)):
			flash.erase("fresh")
		else:
			flash.remaining = float(flash.remaining) - effect_delta
		if float(flash.remaining) <= 0.0:
			_room_clear_flashes.remove_at(index)
			continue
		if _flash_reduced:
			continue
		var rect: Rect2 = flash.rect
		var alpha: float = clampf(float(flash.remaining) / ROOM_CLEAR_FLASH_DURATION, 0.0, 1.0)
		var color := Color(UNIT_COLORS[0].r, UNIT_COLORS[0].g, UNIT_COLORS[0].b, alpha * 0.8)
		var h := float(flash.get("floor_height", 0.0)) + 0.22
		var top_left := rect.position
		var top_right := Vector2(rect.end.x, rect.position.y)
		var bottom_right := rect.end
		var bottom_left := Vector2(rect.position.x, rect.end.y)
		_room_control_line(top_left, top_right, 0.09, h, color)
		_room_control_line(top_right, bottom_right, 0.09, h, color)
		_room_control_line(bottom_right, bottom_left, 0.09, h, color)
		_room_control_line(bottom_left, top_left, 0.09, h, color)
	_event_mesh.surface_end()

## Effect sprites are recycled: a sustained firefight reuses a handful of nodes instead of
## creating and freeing three per shot.
func _effect_sprite(texture: Texture2D) -> Sprite3D:
	var sprite: Sprite3D
	while not _sprite_pool.is_empty() and sprite == null:
		var pooled: Sprite3D = _sprite_pool.pop_back()
		if is_instance_valid(pooled): sprite = pooled
	if sprite == null:
		sprite = Sprite3D.new()
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.no_depth_test = false
		sprite.shaded = false
		sprite.render_priority = LABEL_PRIORITY
		add_child(sprite)
	sprite.texture = texture
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)
	sprite.visible = true
	return sprite

func _free_effect(effect: Dictionary) -> void:
	for key: String in ["smoke_sprite", "flash_sprite", "impact_sprite"]:
		if effect.has(key) and is_instance_valid(effect[key]):
			var sprite: Sprite3D = effect[key]
			if _sprite_pool.size() < EFFECT_SPRITE_POOL:
				sprite.visible = false
				_sprite_pool.append(sprite)
			else:
				sprite.queue_free()
		effect.erase(key)

func _clear_flashes() -> void:
	for effect: Dictionary in _flashes:
		_free_effect(effect)
	_flashes.clear()

func _reset_sightings() -> void:
	_cover_cache.clear()
	_sighting.clear()

## True when the current sight polygons cover the point (centre or a ring of the body footprint).
func _fog_covers(at: Vector2, id: String = "") -> bool:
	# Static enemies (planning, holding positions) reuse the answer until the polygons or the enemy change.
	var cached: Array = _cover_cache.get(id, []) if id != "" else []
	if not cached.is_empty() and int(cached[0]) == _visibility.revision and (cached[1] as Vector2).distance_squared_to(at) < 0.0004:
		return bool(cached[2])
	var covered := _fog_covers_uncached(at)
	if id != "": _cover_cache[id] = [_visibility.revision, at, covered]
	return covered

func _fog_covers_uncached(at: Vector2) -> bool:
	var bounds := _visibility.polygon_bounds()
	var polygons: Array[PackedVector2Array] = _visibility.polygons
	for offset: Vector2 in COVER_OFFSETS:
		var point := at + offset
		for index in range(polygons.size()):
			if index < bounds.size() and not bounds[index].has_point(point): continue
			if Geometry2D.is_point_in_polygon(point, polygons[index]): return true
	return false

## Tracks when each public door's progress last changed (a moving door is where the stale public state comes from).
func _track_door_motion(doors: Array) -> void:
	for door: Dictionary in doors:
		var id := str(door.get("id", ""))
		var progress := float(door.get("progress", 0.0))
		var entry: Dictionary = _door_motion.get(id, {})
		if entry.is_empty():
			_door_motion[id] = {"progress": progress, "moved_at": -INF} # a first look is not motion
		elif not is_equal_approx(float(entry.progress), progress):
			_door_motion[id] = {"progress": progress, "moved_at": _clock}
		elif float(entry.moved_at) > _clock:
			entry["moved_at"] = _clock

## Only a moving public door near the line from one of our units to the enemy can make the fog trail the
## simulation's line of sight (the proven cause). Everything else goes straight to display plus floor light.
func _door_may_lag(at: Vector2, units: Array, doors: Array) -> bool:
	for door: Dictionary in doors:
		var id := str(door.get("id", ""))
		var moving := str(door.get("state", "")) == "OPENING" or (_door_motion.has(id) and _clock - float(_door_motion[id].moved_at) < DOOR_RECENT)
		if not moving: continue
		var centre := Vector2(float(door.get("x", 0.0)), float(door.get("z", 0.0)))
		for unit: Dictionary in units:
			if float(unit.get("hp", 0.0)) <= 0.0: continue
			var from := Vector2(float(unit.get("x", 0.0)), float(unit.get("z", 0.0)))
			if Geometry2D.get_closest_point_to_segment(centre, from, at).distance_to(centre) <= DOOR_LINE_MARGIN: return true
	return false

## Holds a just-sighted enemy back until the floor under it is lit, for at most SIGHTING_GRACE of presentation
## clock or real time (whichever passes first, so a frozen clock cannot hold it). Never on reset, paused or
## reveal frames, and never for an enemy shown within SIGHTING_MEMORY: a flickering sighting is not re-held.
func _sighting_hold(id: String, covered: bool, delta: float, may_lag: bool, bypass: bool) -> bool:
	var rec: Dictionary = _sighting.get(id, {})
	if rec.is_empty() or _clock - float(rec.last_seen) > SIGHTING_MEMORY or _clock < float(rec.last_seen):
		rec = {"since": _clock, "waited": 0.0, "cleared": false, "last_seen": _clock}
		_sighting[id] = rec
	rec["last_seen"] = _clock
	if bool(rec.cleared): return false
	if covered or bypass or not may_lag:
		rec["cleared"] = true
		return false
	rec["waited"] = float(rec.waited) + maxf(delta, 0.0)
	if maxf(_clock - float(rec.since), float(rec.waited)) < SIGHTING_GRACE: return true
	rec["cleared"] = true
	return false

## Draws a small, wall-clipped sight fan under each displayed enemy the polygons do not cover. It goes into the
## CurrentSight viewport only; the exploration memory and room-seen grid never see it.
func _update_sight_pools(fog_refreshed: bool) -> void:
	# A fan depends only on static walls, its own centre and the few doors within reach. An existing fan is
	# rebuilt only on frames where the fog itself refreshes (the 30 Hz CurrentSight throttle), a new one at once;
	# the mesh is rebuilt only when some fan or the set of fans changed. No fan inside smoke (the sight polygons
	# deliberately cut smoke out).
	var changed := false
	var eligible := {}
	for id: String in _fog_pools:
		var centre: Vector2 = _fog_pools[id]
		var in_smoke := false
		for smoke: Dictionary in _state.get("smoke_zones", []):
			if centre.distance_to(Vector2(float(smoke.get("x", 0.0)), float(smoke.get("z", 0.0)))) <= float(smoke.get("radius", 0.0)): in_smoke = true
		if in_smoke: continue
		eligible[id] = true
		if _pool_rings.has(id) and not fog_refreshed: continue
		var near_doors: Array = []
		var door_key: Array = []
		for door: Dictionary in _state.get("doors", _mission.get("doors", [])):
			if Vector2(float(door.get("x", 0.0)), float(door.get("z", 0.0))).distance_to(centre) <= POOL_RADIUS + 1.5:
				near_doors.append(door)
				door_key.append([door.get("state", ""), door.get("progress", 0.0)])
		var ring_key: Array = [snappedf(centre.x, 0.05), snappedf(centre.y, 0.05), door_key]
		if _pool_rings.has(id) and _pool_rings[id].key == ring_key: continue
		var box := Rect2(centre - Vector2.ONE * POOL_RADIUS, Vector2.ONE * POOL_RADIUS * 2.0)
		var near_walls: Array[Rect2] = []
		for rect: Rect2 in _obstacles:
			if rect.intersects(box): near_walls.append(rect)
		var ring := PackedVector2Array()
		var clipped := PackedByteArray()
		for ray in range(POOL_RAYS):
			var direction := Vector2.from_angle(TAU * float(ray) / float(POOL_RAYS))
			var reach := _ray_distance(centre, direction, POOL_RADIUS, near_walls, near_doors)
			ring.append(centre + direction * reach)
			clipped.append(1 if reach < POOL_RADIUS - 0.001 else 0)
		_pool_rings[id] = {"key": ring_key, "ring": ring, "clipped": clipped, "centre": centre}
		changed = true
	for id: String in _pool_rings.keys():
		if not eligible.has(id):
			_pool_rings.erase(id)
			changed = true
	if not changed: return
	_pool_rebuilds += 1
	# Per-vertex alpha in the CurrentSight mask: a lit core, then a soft falloff to the rim (the 4-tap fog sampling
	# reads this alpha as the same "sight" as the real cone). Rays cut by a wall keep a firmer rim so the floor up
	# to the wall stays lit; overlapping fans combine like one soft pool.
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	_pool_polygons.clear()
	var pixel_scale: Vector2 = Vector2(_fog_viewport.size) / _visibility.bounds
	for id: String in _pool_rings:
		var entry: Dictionary = _pool_rings[id]
		var centre: Vector2 = entry.centre
		var ring: PackedVector2Array = entry.ring
		var clipped: PackedByteArray = entry.clipped
		var fan := PackedVector2Array([centre])
		fan.append_array(ring)
		_pool_polygons.append(fan)
		var inner := PackedVector2Array()
		for ray in range(POOL_RAYS): inner.append(centre.lerp(ring[ray], POOL_CORE))
		for ray in range(POOL_RAYS):
			var next := (ray + 1) % POOL_RAYS
			var rim_a := Color(1.0, 1.0, 1.0, 0.7 if clipped[ray] == 1 else 0.0)
			var rim_b := Color(1.0, 1.0, 1.0, 0.7 if clipped[next] == 1 else 0.0)
			var lit := Color.WHITE
			vertices.append_array([centre * pixel_scale, inner[ray] * pixel_scale, inner[next] * pixel_scale])
			colors.append_array([lit, lit, lit])
			vertices.append_array([inner[ray] * pixel_scale, ring[ray] * pixel_scale, ring[next] * pixel_scale])
			colors.append_array([lit, rim_a, rim_b])
			vertices.append_array([inner[ray] * pixel_scale, ring[next] * pixel_scale, inner[next] * pixel_scale])
			colors.append_array([lit, rim_b, lit])
	_pool_mesh.clear_surfaces()
	if not vertices.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		_pool_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	_fog_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

## A seek/reset forgets which shot caused which casualty and any held disc.
func _reset_hit_links() -> void:
	_last_observed_gear.clear()
	_last_hit_shot = {"time": -1.0, "to": Vector2(-1000.0, -1000.0)}
	_last_shot_direction = Vector2.ZERO
	_casualty_hold.clear()

## Shot-down actors keep their disc, halo and tick until the tracer arrives.
func _hold_casualty_disc(id: String) -> void:
	if not _entity_nodes.has(id): return
	var entry: Dictionary = _entity_nodes[id]
	entry.tick.visible = true
	if not bool(entry.selection.visible): entry.ring.visible = true
	if is_instance_valid(entry.threat_halo): entry.threat_halo.visible = true

func _casualty_held(id: String) -> bool:
	return _casualty_hold.has(id) and _clock < float(_casualty_hold[id]) + _hit_reaction_delay()

## Effective tracer-arrival time: 50 ms normally, 35 ms with reduced flash (same factor as the flight itself).
func _hit_reaction_delay() -> float:
	return HIT_REACTION_DELAY * (REDUCED_FLASH_TIMING if _flash_reduced else 1.0)

## One shared camera impulse for breaches and casualties. A weaker request never restarts or
## extends one already in flight, so a burst of kills cannot stack into a long shake.
func _request_kick(duration: float, magnitude: float, direction: Vector2) -> void:
	# While a kick is running, an equal or weaker request is dropped (no restart, no extension).
	if _shake_remaining > 0.0 and magnitude <= _shake_magnitude:
		return
	_shake_remaining = duration
	_shake_duration = duration
	_shake_magnitude = magnitude
	_shake_direction = direction

## World-space camera offset for the running shake. Breaches keep their random jitter. Casualty kicks are
## directional with a quadratic decay and never push the frame further than the safe-area margin on screen.
func _current_kick_offset() -> Vector3:
	var decay := clampf(_shake_remaining / _shake_duration, 0.0, 1.0)
	var direction := _shake_direction
	# Only breach jitter is random. A casualty-sized kick always takes the clamped, deterministic branch.
	if direction == Vector2.ZERO and _shake_magnitude > SHAKE_MAGNITUDE: direction = Vector2.DOWN
	if direction == Vector2.ZERO:
		return Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * _shake_magnitude * decay
	var offset := Vector3(direction.x, 0.0, direction.y) * _shake_magnitude * decay * decay
	return offset.limit_length(SAFE_AREA_MARGIN_PX * _camera_base_size / maxf(_view_size.y, 1.0))

## Deterministic 0..1 noise from the event sequence so replays and seeks redraw identical effects.
func _fx_rand(seq: int, salt: int) -> float:
	return float(((seq * 73856093) ^ (salt * 19349663)) & 0xffff) / 65535.0

func _threat_glow() -> Color:
	return Color(1.0, 0.30, 0.12) if _palette_name == "default" else ENEMY_COLOR.lightened(0.1)

## Tapered, soft-edged ribbon: the centre line carries `mid`, both edges `edge`, tail and head end colours differ (comet).
func _glow_ribbon(a: Vector3, b: Vector3, width: float, mid_a: Color, mid_b: Color, edge_a: Color, edge_b: Color) -> void:
	var flat := Vector2(b.x - a.x, b.z - a.z)
	if flat.length_squared() < 0.000001: return
	var n := flat.normalized().orthogonal() * width * 0.5
	var nv := Vector3(n.x, 0.0, n.y)
	_triangle_c(_event_mesh, a + nv, a, b, edge_a, mid_a, mid_b)
	_triangle_c(_event_mesh, a + nv, b, b + nv, edge_a, mid_b, edge_b)
	_triangle_c(_event_mesh, a, a - nv, b - nv, mid_a, edge_a, edge_b)
	_triangle_c(_event_mesh, a, b - nv, b, mid_a, edge_b, mid_b)

func _glow_disc(center: Vector3, radius: float, mid: Color, edge: Color, segments: int) -> void:
	for i in range(segments):
		var a := i * TAU / segments
		var b := (i + 1) * TAU / segments
		_triangle_c(_event_mesh, center, center + Vector3(cos(a), 0.0, sin(a)) * radius, center + Vector3(cos(b), 0.0, sin(b)) * radius, mid, edge, edge)

## Per-pellet (angle, length) chosen once per shot. A miss runs on past the target but stops at the
## first wall or door leaf, never passing through geometry; a hit ends at the target.
func _plan_tracers(seq: int, pellets: int, hit: bool, origin: Vector2, target: Vector2) -> Array[Vector2]:
	var plan: Array[Vector2] = []
	var span := origin.distance_to(target)
	if span < 0.1: return plan
	var direction := (target - origin) / span
	for pellet in range(pellets):
		var angle := 0.0 if pellets == 1 else (float(pellet) / float(pellets - 1) - 0.5) * 0.34 + (_fx_rand(seq, pellet) - 0.5) * 0.05
		var length := span
		if not hit:
			var overrun := MISS_OVERRUN_MIN + _fx_rand(seq, 11 + pellet) * MISS_OVERRUN_SPAN
			length = maxf(span, _ray_distance(origin, direction.rotated(angle), span + overrun))
		plan.append(Vector2(angle, length))
	return plan

## A bright comet from the muzzle: hot core over a soft glow, ~50 ms in flight, gone by ~90 ms.
## Hits end at the target; a miss runs on past it and simply fades (no invented wall impact).
func _draw_tracers(effect: Dictionary, muzzle_3d: Vector3, age: float) -> void:
	var travel := _hit_reaction_delay()
	var life := TRACER_LIFE * (0.75 if _flash_reduced else 1.0)
	if age >= life: return
	var target := Vector2(float(effect.to[0]), float(effect.to[1]))
	var origin := Vector2(muzzle_3d.x, muzzle_3d.z)
	var span := origin.distance_to(target)
	if span < 0.1: return
	var direction := (target - origin) / span
	var hostile := bool(effect.get("hostile", false))
	var core := Color(1.0, 0.86, 0.66) if hostile else Color(1.0, 1.0, 0.95)
	var glow := _threat_glow() if hostile else Color(1.0, 0.93, 0.52)
	var dim := 0.55 if _flash_reduced else 1.0
	var plan: Array = effect.get("plan", [])
	var post := clampf((age - travel) / (life - travel), 0.0, 1.0)
	var flight := clampf(age / travel, 0.0, 1.0)
	var alpha := (1.0 - post * post) * dim
	var width_scale := (0.55 if _flash_reduced else 1.0) * (0.6 if plan.size() > 1 else 1.0)
	var end_y: float = (effect.impact as Vector3).y
	for pellet_plan: Vector2 in plan:
		var length := pellet_plan.y
		var pellet_direction := direction.rotated(pellet_plan.x)
		var head_d := length * lerpf(0.12, 1.0, flight)
		var tail_d := lerpf(maxf(0.0, head_d - TRACER_STREAK), length, post)
		if head_d - tail_d < 0.04: continue
		var tail := Vector3(origin.x + pellet_direction.x * tail_d, lerpf(muzzle_3d.y, end_y, minf(tail_d / span, 1.0)), origin.y + pellet_direction.y * tail_d)
		var head := Vector3(origin.x + pellet_direction.x * head_d, lerpf(muzzle_3d.y, end_y, minf(head_d / span, 1.0)), origin.y + pellet_direction.y * head_d)
		_glow_ribbon(tail, head, 0.4 * width_scale, Color(glow, 0.0), Color(glow, 0.8 * alpha), Color(glow, 0.0), Color(glow, 0.0))
		_glow_ribbon(tail, head, 0.125 * width_scale, Color(core, 0.0), Color(core, alpha), Color(core, 0.0), Color(core, 0.55 * alpha))
		if flight < 1.0:
			_glow_disc(head, 0.18 * width_scale, Color(core, alpha), Color(glow, 0.0), 8)

## Short directional burst on a confirmed hit. Transient only: dark-red spray on unprotected
## hits, steel-blue sparks thrown back off armour. Nothing for misses.
func _draw_impact_burst(effect: Dictionary, age: float) -> void:
	if age < 0.0: return # `age` is time since the tracer arrived
	var blocked: bool = effect.get("protection", "") == "blocked"
	var life := (SPARK_LIFE if blocked else BURST_LIFE) * (0.7 if _flash_reduced else 1.0)
	if age >= life: return
	var t := age / life
	var seq := int(effect.seq)
	var centre: Vector3 = effect.impact
	var forward: Vector2 = effect.get("dir", Vector2.RIGHT)
	var dim := 0.5 if _flash_reduced else 1.0
	var count := (4 if _flash_reduced else 8) if blocked else (5 if _flash_reduced else 8)
	var ease_out := 1.0 - (1.0 - t) * (1.0 - t)
	if blocked:
		var flash_alpha := clampf(1.0 - age / 0.045, 0.0, 1.0) * dim
		if flash_alpha > 0.0:
			_glow_disc(centre, 0.3, Color(0.85, 0.95, 1.0, 0.85 * flash_alpha), Color(0.4, 0.65, 1.0, 0.0), 10)
	else:
		_glow_disc(centre, 0.2 + 0.3 * ease_out, Color(0.45, 0.02, 0.03, 0.5 * (1.0 - t) * dim), Color(0.3, 0.0, 0.02, 0.0), 10)
	for i in range(count):
		var spread := 2.3 if blocked else 1.0
		var angle := (float(i) / float(count - 1) - 0.5) * spread + (_fx_rand(seq, 40 + i) - 0.5) * 0.3
		var reach := (0.6 + _fx_rand(seq, 60 + i) * 0.5) * (1.0 if blocked else 0.85)
		var spoke := (-forward if blocked else forward).rotated(angle)
		var tip_d := reach * ease_out
		var base_d := tip_d * (0.55 if blocked else 0.3)
		if tip_d - base_d < 0.02: continue
		var side := spoke.orthogonal() * (0.045 if blocked else 0.05)
		var base := Vector3(centre.x + spoke.x * base_d, centre.y, centre.z + spoke.y * base_d)
		var tip := Vector3(centre.x + spoke.x * tip_d, centre.y, centre.z + spoke.y * tip_d)
		var fade := (1.0 - t * t) * dim
		if blocked:
			_triangle_c(_event_mesh, base + Vector3(side.x, 0.0, side.y), base - Vector3(side.x, 0.0, side.y), tip, Color(0.45, 0.72, 1.0, fade), Color(0.45, 0.72, 1.0, fade), Color(0.95, 0.99, 1.0, fade))
		else:
			var tone := Color(0.55, 0.03, 0.04) if i % 2 == 0 else Color(0.36, 0.01, 0.03)
			_triangle_c(_event_mesh, base + Vector3(side.x, 0.0, side.y), base - Vector3(side.x, 0.0, side.y), tip, Color(tone, 0.92 * fade), Color(tone, 0.92 * fade), Color(tone, 0.55 * fade))

## Kill punctuation: a bold X that pops past full size, settles within ~150 ms, then fades.
func _draw_kill_stamp(target: Vector2, age: float, remaining: float) -> void:
	var pop := 1.0
	if not _motion_reduced:
		if age < STAMP_POP: pop = lerpf(0.5, 1.4, age / STAMP_POP)
		elif age < STAMP_SETTLE: pop = lerpf(1.4, 1.0, (age - STAMP_POP) / (STAMP_SETTLE - STAMP_POP))
	var alpha := 1.0 if age < STAMP_SETTLE else clampf(remaining / (STAMP_LIFE - STAMP_SETTLE), 0.0, 1.0)
	if alpha <= 0.0: return
	var arm := 0.4 * pop
	var height := surface_offset(target) + 1.5 # above 0.8, so `_triangle` will not offset it a second time
	if not _flash_reduced and not _motion_reduced and age < 0.1:
		_flat_ring(_event_mesh, target, 0.2 + age * 5.0, 0.05, height - 0.1, Color(1.0, 0.95, 0.85, (1.0 - age / 0.1) * 0.7), 20)
	for pass_index in range(2):
		var color := Color(0.08, 0.04, 0.04, alpha * 0.85) if pass_index == 0 else Color(1.0, 0.93, 0.84, alpha)
		var width := 0.2 if pass_index == 0 else 0.11
		var h := height if pass_index == 1 else height - 0.01
		_flat_line(_event_mesh, target + Vector2(-arm, -arm), target + Vector2(arm, arm), width, h, color)
		_flat_line(_event_mesh, target + Vector2(-arm, arm), target + Vector2(arm, -arm), width, h, color)

func screen_to_ground(screen_pos: Vector2) -> Vector2:
	if not is_instance_valid(camera):
		return Vector2.ZERO
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	if absf(direction.y) < 0.0001:
		return _focus
	var hit := origin + direction * ((0.2 - origin.y) / direction.y)
	var nearest := (0.2 - origin.y) / direction.y
	for surface: Dictionary in _elevated_surfaces:
		var distance := (float(surface.offset) + 0.2 - origin.y) / direction.y
		var elevated_hit := origin + direction * distance
		if distance >= 0.0 and distance < nearest and (surface.rect as Rect2).has_point(Vector2(elevated_hit.x, elevated_hit.z)):
			hit = elevated_hit
			nearest = distance
	return Vector2(hit.x, hit.z)

func pick_unit(screen_pos: Vector2) -> String:
	return _pick_entity(screen_pos, _state.get("units", []), 30.0)

func pick_civilian(screen_pos: Vector2) -> String:
	return _pick_entity(screen_pos, _state.get("civilians", []), 29.0)

func pick_enemy(screen_pos: Vector2) -> String:
	var surrendered: Array = []
	for enemy: Dictionary in _state.get("enemies", []):
		if bool(enemy.get("visible", false)) and str(enemy.get("status", enemy.get("state", ""))) == "SURRENDERED":
			surrendered.append(enemy)
	return _pick_entity(screen_pos, surrendered, 29.0)

func _pick_entity(screen_pos: Vector2, entities: Array, tolerance: float) -> String:
	var nearest := tolerance
	var result := ""
	for entity in entities:
		if not bool(entity.get("visible", true)) or float(entity.get("hp", 100.0)) <= 0.0: continue
		var distance: float = _entity_pick_distance(screen_pos, entity)
		if distance < nearest:
			nearest = distance
			result = str(entity.id)
	return result

func _entity_pick_distance(screen_pos: Vector2, entity: Dictionary) -> float:
	var point := Vector2(float(entity.get("x", 0.0)), float(entity.get("z", 0.0)))
	var world := surface_position(point, 0.95)
	var body_screen: Vector2 = camera.unproject_position(world)
	var ground_screen: Vector2 = camera.unproject_position(surface_position(point))
	return minf(body_screen.distance_to(screen_pos), ground_screen.distance_to(screen_pos))

func pick_door(screen_pos: Vector2) -> String:
	var nearest := 22.0
	var result := ""
	for door in _state.get("doors", _mission.get("doors", [])):
		if not bool(door.get("observed", true)): continue
		var distance: float = _door_pick_distance(screen_pos, door)
		if distance < nearest:
			nearest = distance
			result = str(door.id)
	return result

func _door_pick_distance(screen_pos: Vector2, door: Dictionary) -> float:
	var screen: Vector2 = camera.unproject_position(Vector3(float(door.x), 0.7 + float(door.get("base_height", 0.0)), float(door.z)))
	var distance: float = screen.distance_to(screen_pos)
	var progress: float = 1.0 if str(door.get("state", "CLOSED")) == "OPEN" else float(door.get("progress", 0.0))
	var hinge: Transform3D = DoorGeometry.hinge_transform(door, progress)
	var start: Vector2 = camera.unproject_position(hinge * Vector3(0, 0.68, 0))
	var end: Vector2 = camera.unproject_position(hinge * Vector3(DoorGeometry.width(door), 0.68, 0))
	distance = minf(distance, Geometry2D.get_closest_point_to_segment(screen_pos, start, end).distance_to(screen_pos))
	if _door_nodes.has(str(door.id)):
		var label: Label3D = _door_nodes[str(door.id)].label
		if label.visible: distance = minf(distance, camera.unproject_position(label.global_position).distance_to(screen_pos))
	return distance

func pick_context(screen_pos: Vector2) -> Dictionary:
	# Open door leaves and labels can overlap an actor. Resolve the nearest
	# visible target so a precise click on that actor reaches its own actions.
	var nearest: float = 30.0
	var result: Dictionary = {}
	for group: Dictionary in [{"target": "civilian", "entities": _state.get("civilians", [])}, {"target": "enemy", "entities": _state.get("enemies", [])}, {"target": "unit", "entities": _state.get("units", [])}]:
		for entity: Dictionary in group.entities:
			if not bool(entity.get("visible", true)) or float(entity.get("hp", 100.0)) <= 0: continue
			if str(group.target) == "enemy" and str(entity.get("status", "")) != "SURRENDERED": continue
			var distance: float = _entity_pick_distance(screen_pos, entity)
			if distance < nearest and distance < (30.0 if str(group.target) == "unit" else 29.0):
				nearest = distance
				result = {"target": group.target, "id": str(entity.id)}
	for door: Dictionary in _state.get("doors", _mission.get("doors", [])):
		if not bool(door.get("observed", true)): continue
		var distance: float = _door_pick_distance(screen_pos, door)
		if distance < nearest and distance < 22.0:
			nearest = distance
			result = {"target": "door", "id": str(door.id)}
	return result

func pick_waypoint(screen_pos: Vector2, unit_id: String) -> Dictionary:
	if unit_id.is_empty() or not is_instance_valid(camera): return {}
	var nearest: float = 22.0
	var picked: Dictionary = {}
	for unit: Dictionary in _state.get("units", []):
		if str(unit.id) != unit_id or float(unit.get("hp", 0)) <= 0: continue
		var commands: Array = unit.get("commands", [])
		for index: int in range(commands.size()):
			var command: Dictionary = commands[index]
			var target: Variant = command.get("args", {}).get("target")
			if str(command.get("type", "")) != "MOVE" or not str(command.get("state", "")) in ["PENDING", "RUNNING", "WAITING"] or not target is Array or target.size() != 2: continue
			var screen: Vector2 = camera.unproject_position(surface_position(Vector2(float(target[0]), float(target[1])), 0.25))
			var distance: float = screen.distance_to(screen_pos)
			if distance < nearest:
				nearest = distance
				picked = {"unit_id": unit_id, "index": index, "target": target.duplicate(), "state": command.get("state", "PENDING")}
	return picked

func set_selected_waypoint(unit_id: String, index: int) -> void:
	_waypoint_unit = unit_id
	_selected_waypoint = index
	_draw_timer = 0.08
	_interaction_dirty = true

func set_interaction(data: Dictionary) -> void:
	_interaction = data.duplicate(true)
	_interaction_dirty = true
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if str(data.get("kind", "")) == "hover" else (Input.CURSOR_CROSS if not data.is_empty() else Input.CURSOR_ARROW))

func preview_flash_clear(source: Vector2, target: Vector2, door_id: String) -> bool:
	# Planned opening of remembered geometry, with no authoritative hidden data.
	var observed_doors: Array = _preview_nav.doors
	var planned_doors: Array = observed_doors.duplicate(true)
	var known := false
	for door: Dictionary in planned_doors:
		if str(door.get("id", "")) != door_id or not bool(door.get("observed", true)): continue
		door["state"] = "OPEN"
		door["progress"] = 1.0
		known = true
	_preview_nav.doors = planned_doors
	var clear := known and preview_throw_clear(source, target)
	_preview_nav.doors = observed_doors
	return clear

func preview_throw_clear(source: Vector2, target: Vector2) -> bool:
	return target.x >= 0 and target.y >= 0 and target.x <= _bounds.x and target.y <= _bounds.y and _preview_nav.segment_clear(source, target)

func set_room_drill_preview(data: Dictionary) -> void:
	# A planning result contains static map geometry and owned orders only.
	_drill_preview = data.duplicate(true) if bool(data.get("ok", false)) else {}
	if not _drill_preview.is_empty(): _formation_preview.clear()
	_drill_draw_inputs.clear()

func set_formation_preview(data: Dictionary) -> void:
	_formation_preview = data.duplicate(true) if bool(data.get("ok", false)) else {}
	if not _formation_preview.is_empty(): _drill_preview.clear()
	_drill_draw_inputs.clear()

static func formation_from_commands(state: Dictionary, sync_id: String, fallback: Dictionary = {}) -> Dictionary:
	var data := fallback.duplicate(true)
	data["sync_id"] = sync_id
	var slots: Array[Dictionary] = []
	for unit: Dictionary in state.get("units", []):
		if float(unit.get("hp", 0.0)) <= 0.0: continue
		var slot: Dictionary = {}
		for original: Dictionary in fallback.get("slots", []):
			if str(original.get("unit_id", "")) == str(unit.id): slot = original.duplicate(true)
		var found := false
		var stack_route: Array = []
		var move_route: Array = []
		var move_faces: Array = []
		var initial_found := false
		var cover_found := false
		var cursor: Array = slot.get("approach", [float(unit.x), float(unit.z)]).duplicate()
		for command: Dictionary in unit.get("commands", []):
			var args: Dictionary = command.get("args", {})
			var formation: Dictionary = args.get("formation", {})
			if str(formation.get("sync_id", "")) != sync_id:
				if not found and command.type == "MOVE" and args.get("target", []) is Array and args.target.size() == 2:
					cursor = args.target.duplicate()
				continue
			if command.get("state", "") in ["FAILED", "CANCELLED"]: continue
			if not found: slot["approach"] = cursor.duplicate()
			found = true
			data["kind"] = str(formation.get("kind", ""))
			data["resolved"] = str(formation.get("kind", ""))
			data["source_unit_id"] = str(formation.get("source_unit_id", ""))
			slot["unit_id"] = str(unit.id)
			slot["index"] = int(formation.get("order", 0))
			slot["order"] = int(formation.get("order", 0))
			if args.has("stance"): slot["stance"] = str(args.stance)
			var stage := str(formation.get("stage", ""))
			if command.type == "MOVE":
				if stage == "stack":
					stack_route.append(args.target.duplicate())
					slot["stack"] = args.target.duplicate()
				elif stage == "move":
					move_route.append(args.target.duplicate())
					slot["target"] = args.target.duplicate()
			elif command.type == "FACE":
				if stage == "stack" and not initial_found:
					slot["initial_face_target"] = args.target.duplicate()
					initial_found = true
				elif stage == "ready": slot["ready_face_target"] = args.target.duplicate()
				elif stage == "move": move_faces.append(args.target.duplicate())
				elif stage == "cover":
					slot["face_target"] = args.target.duplicate()
					var sector: Dictionary = slot.get("sector", {}).duplicate(true)
					sector.merge(args.get("sector", {}), true)
					if not sector.has("radius"): sector["radius"] = 4.0
					slot["sector"] = sector
					cover_found = true
		if not found: continue
		slot["stack_route"] = stack_route
		slot["move_route"] = move_route
		slot["move_face_targets"] = move_faces
		slot["deleted_move"] = move_route.is_empty()
		if stack_route.is_empty(): slot["stack"] = slot.get("approach", [float(unit.x), float(unit.z)]).duplicate()
		if not slot.has("target"): slot["target"] = slot.stack.duplicate()
		if not cover_found:
			slot["face_target"] = move_faces.back().duplicate() if not move_faces.is_empty() else slot.get("ready_face_target", slot.target).duplicate()
			slot["sector"] = {}
		if str(slot.get("stance", "")).is_empty(): slot["stance"] = str(unit.get("stance", "standing"))
		if not slot.has("floor_height"): slot["floor_height"] = float(unit.get("base_height", 0.0))
		slots.append(slot)
	slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.index) < int(b.index))
	data["slots"] = slots
	data["order_ids"] = slots.map(func(slot: Dictionary) -> String: return str(slot.unit_id))
	data["ok"] = not slots.is_empty()
	return data

func _resolved_room_drill_preview() -> Dictionary:
	var data := _drill_preview.duplicate(true)
	var sync_id := str(data.get("sync_id", ""))
	if sync_id.is_empty(): return data
	var survivors: Array = []
	for slot: Dictionary in data.get("slots", []):
		var entry_found := false
		var face_found := false
		var alive := true
		for unit: Dictionary in _state.get("units", []):
			if str(unit.id) != str(slot.unit_id): continue
			if unit.has("hp") and float(unit.hp) <= 0.0:
				alive = false
				break
			for command: Dictionary in unit.get("commands", []):
				var args: Dictionary = command.get("args", {})
				var drill: Dictionary = args.get("drill", {})
				if str(drill.get("sync_id", "")) != sync_id or command.get("state", "") in ["CANCELLED", "FAILED"]: continue
				if command.get("state", "") in ["PENDING", "RUNNING"] and drill.has("order"): slot["order"] = int(drill.order)
				var stage := str(drill.get("stage", ""))
				if stage == "stack" and command.type == "MOVE": slot["stack"] = args.target.duplicate()
				elif stage in ["entry", "domination"] and command.type == "MOVE":
					entry_found = true
					slot["domination"] = args.target.duplicate()
					if args.has("sector"):
						slot.sector_entry.merge(args.sector, true)
				elif stage in ["domination", "guard"] and command.type == "FACE":
					face_found = true
					slot["face_target"] = args.target.duplicate()
					if args.get("sector", {}) is Dictionary and args.has("sector"):
						slot.sector_domination["start"] = args.sector.start
						slot.sector_domination["end"] = args.sector.end
		if not alive: continue
		if bool(slot.get("entry", false)): slot["deleted_entry"] = not entry_found
		var goal := _drill_point(slot.get("domination", []))
		if not face_found:
			var entry_sector: Dictionary = slot.get("sector_entry", {})
			slot.sector_domination.merge(entry_sector, true)
			var entry_center := float(entry_sector.get("start", 0.0)) + fposmod(float(entry_sector.get("end", 0.0)) - float(entry_sector.get("start", 0.0)), TAU) * 0.5
			slot["face_target"] = [goal.x + cos(entry_center) * 2.0, goal.y + sin(entry_center) * 2.0]
		var face := _drill_point(slot.get("face_target", []))
		if goal != face:
			var fan: Dictionary = slot.get("sector_domination", {})
			var span := fposmod(float(fan.get("end", 0.0)) - float(fan.get("start", 0.0)), TAU)
			var center := (face - goal).angle()
			fan["start"] = wrapf(center - span * 0.5, -PI, PI)
			fan["end"] = wrapf(center + span * 0.5, -PI, PI)
		survivors.append(slot)
	data["slots"] = survivors
	data["entry_count"] = survivors.filter(func(slot: Dictionary) -> bool: return bool(slot.get("entry", false))).size()
	var long_goals: Array = []
	for long_goal: Dictionary in data.get("go_long", []):
		var move_found := false
		var face_found := false
		for unit: Dictionary in _state.get("units", []):
			if str(unit.id) != str(long_goal.unit_id): continue
			if unit.has("hp") and float(unit.hp) <= 0.0: break
			for command: Dictionary in unit.get("commands", []):
				var args: Dictionary = command.get("args", {})
				var drill: Dictionary = args.get("drill", {})
				if str(drill.get("sync_id", "")) != sync_id or str(drill.get("stage", "")) != "go_long" or command.get("state", "") in ["CANCELLED", "FAILED"]: continue
				if command.type == "MOVE":
					move_found = true
					long_goal["target"] = args.target.duplicate()
					if args.has("sector"): long_goal.sector.merge(args.sector, true)
				elif command.type == "FACE":
					face_found = true
					long_goal["face_target"] = args.target.duplicate()
					if args.has("sector"): long_goal.sector.merge(args.sector, true)
		if move_found:
			var fan: Dictionary = long_goal.get("sector", {})
			var span := fposmod(float(fan.get("end", 0.0)) - float(fan.get("start", 0.0)), TAU)
			var heading := (_drill_point(long_goal.face_target) - _drill_point(long_goal.target)).angle() if face_found else float(fan.get("start", 0.0)) + span * 0.5
			fan["start"] = wrapf(heading - span * 0.5, -PI, PI)
			fan["end"] = wrapf(heading + span * 0.5, -PI, PI)
			long_goals.append(long_goal)
	data["go_long"] = long_goals
	return data

func _update_room_drill_preview(planning: bool) -> void:
	if not is_instance_valid(_drill_mesh_node): return
	_drill_mesh_node.visible = planning and (not _drill_preview.is_empty() or not _formation_preview.is_empty())
	for label: Label3D in _drill_labels:
		if is_instance_valid(label): label.visible = _drill_mesh_node.visible
	if not _drill_mesh_node.visible: return
	var is_formation := not _formation_preview.is_empty()
	var data: Dictionary = _formation_preview.duplicate(true) if is_formation else _resolved_room_drill_preview()
	if is_formation and not str(data.get("sync_id", "")).is_empty():
		data = formation_from_commands(_state, str(data.sync_id), data)
	var inputs: Array = [data, _palette_name, _language, is_formation]
	if inputs == _drill_draw_inputs: return
	_drill_draw_inputs = inputs.duplicate(true)
	if is_formation: _draw_formation_preview(data)
	else: _draw_room_drill_preview(data)

func _draw_formation_preview(data: Dictionary) -> void:
	_drill_mesh.clear_surfaces()
	for label: Label3D in _drill_labels:
		if is_instance_valid(label):
			label.visible = false
			label.queue_free()
	_drill_labels.clear()
	_drill_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _vertex_material())
	_triangle(_drill_mesh, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Color.TRANSPARENT)
	for slot: Dictionary in data.get("slots", []):
		var color_index := 0
		var owned_stance := "standing"
		for index: int in range(_state.get("units", []).size()):
			if str(_state.units[index].id) == str(slot.unit_id):
				color_index = index
				owned_stance = str(_state.units[index].get("stance", "standing"))
		var color: Color = UNIT_COLORS[color_index % UNIT_COLORS.size()]
		# Shared _triangle adds the authored floor offset at each vertex.
		# These overlay heights are relative, just like the entry-drill mesh.
		var height := 0.0
		var stack := _drill_point(slot.get("stack", []))
		var goal := _drill_point(slot.get("target", []))
		var route: Array = slot.get("stack_route", []).duplicate(true)
		route.append_array(slot.get("move_route", []))
		var previous := _drill_point(slot.get("approach", slot.get("stack", [])))
		for point: Array in route:
			var destination := _drill_point(point)
			_flat_line(_drill_mesh, previous, destination, 0.035, height + 0.32, Color(color, 0.65))
			previous = destination
		_flat_disc(_drill_mesh, stack, 0.25, height + 0.35, Color(0.08, 0.13, 0.12, 0.95), 24)
		_flat_ring(_drill_mesh, stack, 0.26, 0.04, height + 0.36, color, 24)
		_drill_badge(str(slot.get("index", "")), stack, color, 0.64)
		if bool(slot.get("deleted_move", false)): continue
		var face := _drill_point(slot.get("face_target", []))
		var heading := (face - goal).normalized()
		if heading.length_squared() < 0.001: heading = Vector2.UP
		var side := heading.orthogonal()
		var crouched := str(slot.get("stance", owned_stance)) == "crouched" if not str(slot.get("stance", "")).is_empty() else owned_stance == "crouched"
		var silhouette := 0.17 if crouched else 0.23
		_flat_disc(_drill_mesh, goal, silhouette, height + 0.39, Color(color, 0.35), 24)
		_flat_disc(_drill_mesh, goal + heading * 0.15, 0.10, height + 0.40, Color(color, 0.8), 16)
		_flat_line(_drill_mesh, goal - side * 0.22, goal + side * 0.22, 0.10, height + 0.40, Color(color, 0.8))
		_flat_ring(_drill_mesh, goal, 0.34, 0.035, height + 0.40, color, 28)
		_drill_badge(str(slot.get("index", "")), goal, color, 0.77)
		_draw_drill_fan(goal, slot.get("sector", {}), Color(color, 0.18), height + 0.32, Rect2())
	_drill_mesh.surface_end()

func _drill_point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1])) if value.size() == 2 else Vector2.ZERO

func _draw_room_drill_preview(data: Dictionary) -> void:
	_drill_mesh.clear_surfaces()
	for label: Label3D in _drill_labels:
		if is_instance_valid(label):
			label.visible = false
			label.queue_free()
	_drill_labels.clear()
	_drill_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _vertex_material())
	_triangle(_drill_mesh, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Color.TRANSPARENT)
	var funnel: Array = data.get("funnel", [])
	if funnel.size() == 4:
		var rect := Rect2(float(funnel[0]), float(funnel[1]), float(funnel[2]), float(funnel[3]))
		var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		for index: int in range(4): _flat_line(_drill_mesh, corners[index], corners[(index + 1) % 4], 0.035, 0.30, Color("e49978"))
		var hatch := -rect.size.y
		while hatch <= rect.size.x:
			var low := maxf(0.0, -hatch)
			var high := minf(rect.size.y, rect.size.x - hatch)
			if high > low:
				_flat_line(_drill_mesh, rect.position + Vector2(hatch + low, low), rect.position + Vector2(hatch + high, high), 0.025, 0.30, Color(0.9, 0.45, 0.28, 0.45))
			hatch += 0.32
	var room_rect := Rect2()
	for room: Dictionary in _mission.get("rooms", []):
		if str(room.id) == str(data.get("room_id", "")):
			room_rect = _rect_from(room)
			break
	for slot: Dictionary in data.get("slots", []):
		var color_index := 0
		for index: int in range(_state.get("units", []).size()):
			if str(_state.units[index].id) == str(slot.unit_id):
				color_index = index
				break
		var color: Color = UNIT_COLORS[color_index % UNIT_COLORS.size()]
		var stack := _drill_point(slot.stack)
		var goal := _drill_point(slot.domination)
		_flat_disc(_drill_mesh, stack, 0.25, 0.35, Color(0.08, 0.13, 0.12, 0.95), 24)
		_flat_ring(_drill_mesh, stack, 0.26, 0.04, 0.36, color, 24)
		_drill_badge(str(slot.get("index", "")), stack, color, 0.64)
		_draw_drill_fan(stack, slot.get("sector_entry", {}), Color(color, 0.18), 0.31, Rect2())
		if bool(slot.get("entry", false)) and not bool(slot.get("deleted_entry", false)):
			# A floor silhouette is independent of actors, skins, and contacts.
			var face := _drill_point(slot.get("face_target", []))
			var heading := (face - goal).normalized()
			if heading.length_squared() < 0.001: heading = Vector2.UP
			var side := heading.orthogonal()
			_flat_disc(_drill_mesh, goal, 0.23, 0.39, Color(color, 0.35), 24)
			_flat_disc(_drill_mesh, goal + heading * 0.15, 0.10, 0.40, Color(color, 0.8), 16)
			_flat_line(_drill_mesh, goal - side * 0.22, goal + side * 0.22, 0.10, 0.40, Color(color, 0.8))
			_flat_line(_drill_mesh, goal, goal - heading * 0.26 - side * 0.13, 0.08, 0.40, color)
			_flat_line(_drill_mesh, goal, goal - heading * 0.26 + side * 0.13, 0.08, 0.40, color)
			_flat_ring(_drill_mesh, goal, 0.34, 0.035, 0.40, color, 28)
			_drill_badge(str(slot.get("index", "")), goal, color, 0.77)
			_draw_drill_fan(goal, slot.get("sector_domination", {}), Color(color, 0.2), 0.32 + float(slot.get("index", 0)) * 0.008, room_rect)
	for long_goal: Dictionary in data.get("go_long", []):
		var point := _drill_point(long_goal.target)
		var color_index := 0
		for index: int in range(_state.get("units", []).size()):
			if str(_state.units[index].id) == str(long_goal.unit_id): color_index = index
		_draw_drill_fan(point, long_goal.get("sector", {}), Color(UNIT_COLORS[color_index % UNIT_COLORS.size()], 0.13), 0.38, room_rect)
		_flat_ring(_drill_mesh, point, 0.30, 0.035, 0.39, Color("f4d69b"), 24)
		_drill_badge(_t("깊이 진입"), point, Color("f4d69b"), 0.77)
	if bool(data.get("short_room", false)) and funnel.size() == 4:
		_drill_badge(_t("짧은 방"), Vector2(float(funnel[0]) + float(funnel[2]) * 0.5, float(funnel[1]) + float(funnel[3]) * 0.5), Color("f4d69b"), 1.2)
	_drill_mesh.surface_end()

func _drill_badge(text: String, point: Vector2, color: Color, height: float) -> void:
	var label := _label(text, color, 30, 0.009)
	label.position = surface_position(point, height)
	_marks.add_child(label)
	_drill_labels.append(label)

func _draw_drill_fan(origin: Vector2, sector: Dictionary, color: Color, height: float, room_rect: Rect2) -> void:
	if sector.is_empty(): return
	var start := float(sector.get("start", 0.0))
	var span := fposmod(float(sector.get("end", start)) - start, TAU)
	var radius := clampf(float(sector.get("radius", 1.0)), 0.05, 12.0)
	var polygon := PackedVector2Array([origin])
	for index: int in range(33):
		var angle := start + span * float(index) / 32.0
		polygon.append(origin + Vector2(cos(angle), sin(angle)) * radius)
	var polygons: Array[PackedVector2Array] = [polygon]
	if room_rect.has_area():
		var boundary := PackedVector2Array([room_rect.position, Vector2(room_rect.end.x, room_rect.position.y), room_rect.end, Vector2(room_rect.position.x, room_rect.end.y)])
		polygons = Geometry2D.intersect_polygons(polygon, boundary)
	for clipped: PackedVector2Array in polygons:
		var indices := Geometry2D.triangulate_polygon(clipped)
		for index: int in range(0, indices.size(), 3):
			var a := clipped[indices[index]]
			var b := clipped[indices[index + 1]]
			var c := clipped[indices[index + 2]]
			_triangle(_drill_mesh, Vector3(a.x, height, a.y), Vector3(b.x, height, b.y), Vector3(c.x, height, c.y), color)

func _draw_interaction() -> void:
	if _interaction_mesh == null: return
	_interaction_mesh.clear_surfaces()
	if is_instance_valid(_interaction_label): _interaction_label.visible = false
	if _interaction.is_empty(): return
	_interaction_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _vertex_material())
	_triangle(_interaction_mesh, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Color.TRANSPARENT)
	var kind: String = str(_interaction.get("kind", ""))
	var color: Color = Color("ffe1a0")
	if kind == "hover":
		var point: Vector2 = Vector2.ZERO
		var found: bool = false
		var target: String = str(_interaction.get("target", ""))
		var id: String = str(_interaction.get("id", ""))
		if target == "waypoint" and _interaction.get("point") is Array:
			point = Vector2(float(_interaction.point[0]), float(_interaction.point[1]))
			found = true
		else:
			var group: String = {"door": "doors", "unit": "units", "civilian": "civilians", "enemy": "enemies"}.get(target, "")
			for entity: Dictionary in _state.get(group, []):
				if str(entity.get("id", "")) == id and bool(entity.get("visible", entity.get("observed", true))):
					point = Vector2(float(entity.x), float(entity.z))
					found = true
					if target == "door":
						var rect: Rect2 = _rect_from(entity).grow(0.12)
						var corners: Array[Vector2] = [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)]
						for i: int in range(4): _flat_line(_interaction_mesh, corners[i], corners[(i + 1) % 4], 0.05, 0.27, color)
					break
		if found:
			_flat_ring(_interaction_mesh, point, 0.48 if target in ["unit", "civilian", "enemy"] else 0.28, 0.055, 0.265, color, 32)
			var hints: Array[String] = []
			var labels: Dictionary = {"ENTER_ROOM": "진입 드릴", "OPEN_DOOR": "↗ 열기", "OPEN_AND_FLASH": "열고 섬광", "PEEK_CAMERA": "◉ 카메라", "KICK_DOOR": "↯ 차기", "PEEK_DOOR": "◉ 보기", "SHOTGUN_BREACH": "산탄 돌파", "SECURE_CIVILIAN": "✓ 확보", "ESCORT": "→ 호송", "ARREST": "✓ 체포", "RELOAD": "↻ 장전", "FACE": "→ 주시", "WAIT": "◷ 대기", "WAIT_3": "◷ 대기", "WAIT_FOR_SIGNAL_A": "A 신호"}
			for action: Variant in _interaction.get("actions", []).slice(0, 3):
				var action_type: String = str(action.get("type", "")) if action is Dictionary else str(action)
				hints.append(_t(str(labels.get(action_type, action_type))))
			if target == "door" and _interaction.get("door_info") is Dictionary:
				var wall_hint: String = _door_wall_hint(_interaction.door_info)
				if not wall_hint.is_empty(): hints.append(wall_hint)
			if not hints.is_empty():
				_interaction_label.text = " · ".join(hints)
				_interaction_label.position = surface_position(point, 1.7)
				_interaction_label.visible = true
	else:
		var origin_data: Array = _interaction.get("origin", [0, 0])
		var target_data: Array = _interaction.get("target", origin_data)
		var origin: Vector2 = Vector2(float(origin_data[0]), float(origin_data[1]))
		var target_point: Vector2 = Vector2(float(target_data[0]), float(target_data[1]))
		if kind == "path":
			var previous: Vector2 = origin
			for point_data: Array in _interaction.get("points", []):
				var point: Vector2 = Vector2(float(point_data[0]), float(point_data[1]))
				_flat_line(_interaction_mesh, previous, point, 0.07, 0.27, color)
				previous = point
			_flat_line(_interaction_mesh, previous, target_point, 0.07, 0.27, color)
		elif kind == "face":
			_flat_line(_interaction_mesh, origin, target_point, 0.06, 0.27, color)
			_arrow_head(_interaction_mesh, origin, target_point, 0.32, 0.27, color)
		elif kind == "throw":
			color = Color("a1d6c3") if bool(_interaction.get("valid", false)) else Color("dd796b")
			_dashed_line(_interaction_mesh, origin, target_point, 0.055, 0.27, color)
			_flat_ring(_interaction_mesh, target_point, float(_interaction.get("radius", 3.0)), 0.025, 0.27, Color(color, 0.65), 48)
		_flat_ring(_interaction_mesh, target_point, 0.27, 0.05, 0.28, color, 28)
	_interaction_mesh.surface_end()

func _door_wall_hint(info: Dictionary) -> String:
	var walls: Array = info.get("walls", [])
	if walls.is_empty(): return _t("인접 벽 정보 없음")
	var names := {"wood": "목재", "glass": "유리", "plaster": "석고", "drywall": "석고", "metal": "금속", "steel": "금속", "brick": "벽돌", "masonry": "벽돌", "concrete": "콘크리트", "fabric": "천", "cloth": "천", "foliage": "식생"}
	var labels: Array[String] = []
	for wall: Dictionary in walls:
		var material: String = str(wall.get("material", ""))
		var name: String = str(names.get(material, "미지정 재질"))
		if material.is_empty() and bool(wall.get("thin", false)): name = "얇은 벽"
		labels.append("%s · %s" % [_t(name), _t("소총 관통 가능" if bool(wall.get("rifle_penetrable", false)) else "소총 관통 불가")])
	return " / ".join(labels)

func drag_pan(previous: Vector2, current: Vector2) -> void:
	# Grab the ground under the cursor; scale stays exact at every zoom level.
	var offset := screen_to_ground(previous) - screen_to_ground(current)
	if not offset.is_finite(): return
	_pan += offset
	_clamp_pan()

func pan(direction: Vector2, delta: float) -> void:
	_pan += direction * delta * 12.0 * _zoom
	_clamp_pan()

func _clamp_pan() -> void:
	_pan.x = clampf(_pan.x, -_bounds.x * 0.65, _bounds.x * 0.65)
	_pan.y = clampf(_pan.y, -_bounds.y * 0.65, _bounds.y * 0.65)
	_fit_camera()

func zoom(amount: float) -> void:
	if _is_metre_map():
		_zoom = clampf(_zoom * pow(1.12, amount), 0.075, 1.75)
	else:
		_zoom = clampf(_zoom + amount * 0.1, 0.5, 1.5)
	_fit_camera()

func reset_camera() -> void:
	_pan = Vector2.ZERO
	_zoom = 1.0
	_fit_camera()

func bounds() -> Vector2:
	return _bounds

## RD (plan 2-3 게임패드): draws the left-stick-driven virtual map cursor as a
## world-space reticle (two concentric rings), reusing the same immediate-mesh
## pattern as _draw_interaction above. Hidden (no draw call at all) while
## inactive, matching how _draw_interaction clears when `_interaction` is
## empty.
func set_gamepad_cursor(pos: Vector2, active: bool) -> void:
	_gamepad_mesh.clear_surfaces()
	if not active: return
	_gamepad_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _vertex_material())
	_triangle(_gamepad_mesh, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Color.TRANSPARENT)
	var color := Color("ffe1a0")
	_flat_ring(_gamepad_mesh, pos, 0.42, 0.05, 0.27, color, 24)
	_flat_ring(_gamepad_mesh, pos, 0.16, 0.035, 0.27, color, 16)
	_gamepad_mesh.surface_end()

func set_menu_preview(enabled: bool) -> void:
	if _menu_preview != enabled:
		_menu_preview = enabled
		for node in _chrome_nodes:
			if is_instance_valid(node):
				node.visible = not enabled
		_fit_camera()

func follow_position(point: Vector2) -> void:
	_pan = point - (_focus if _menu_preview else _frame_rect.get_center())
	_fit_camera()

## CSS-px insets of the map viewport from the window edges, as sent by the
## web `set_safe_area` bridge action (already converted to viewport px by the
## caller). Replaces the hardcoded bottom reservation once received.
## L1 fix: `float(null)`/an array/a string used to raise a script error and
## abort the caller's _action before _send_state. Each inset is now only
## accepted when it is a finite number; otherwise that side keeps whatever
## value it already had (defaulting to 0.0 the first time), instead of
## crashing or silently defaulting the whole dictionary to zero.
func set_safe_area(insets: Dictionary) -> void:
	var next: Dictionary = {
		"left": float(_safe_area.get("left", 0.0)),
		"top": float(_safe_area.get("top", 0.0)),
		"right": float(_safe_area.get("right", 0.0)),
		"bottom": float(_safe_area.get("bottom", 0.0)),
	}
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	for key: String in ["left", "top", "right", "bottom"]:
		var value: Variant = insets.get(key)
		if not (value is float or value is int) or not is_finite(float(value)):
			continue
		var axis_limit: float = viewport_size.x if key in ["left", "right"] else viewport_size.y
		next[key] = clampf(float(value), 0.0, maxf(axis_limit, 0.0))
	_safe_area = next
	_fit_camera()

func set_settings(settings: Dictionary) -> void:
	var next_ui_scale := clampf(float(settings.get("ui_scale", _ui_scale)), 1.0, 1.5)
	if not is_equal_approx(next_ui_scale, _ui_scale):
		_ui_scale = next_ui_scale
		_fit_camera()
	_line_width = clampf(float(settings.get("line_width", _line_width)), 0.7, 2.5)
	_show_fov = bool(settings.get("fov", _show_fov))
	_show_facing = bool(settings.get("facing", _show_facing))
	_motion_reduced = bool(settings.get("reduced_motion", _motion_reduced))
	_flash_reduced = bool(settings.get("reduced_flash", _flash_reduced))
	_screen_shake_enabled = bool(settings.get("screen_shake", _screen_shake_enabled))
	_apply_palette(str(settings.get("palette", _palette_name)))
	_language = str(settings.get("language", _language)) if str(settings.get("language", _language)) in ["ko", "en"] else _language

## RD (plan 2-2): swap operator/threat/civilian/door/signal colors for a
## colorblind-safe set. Route/path lines (_draw_paths), door connectors, and
## the room-clear flash re-read UNIT_COLORS/DOOR_COLOR fresh every frame, so
## those recolor immediately. L6 fix: each actor's body/ring tint used to be
## baked into its mesh materials once in _make_actor at spawn time and never
## re-read, so an operator/enemy/civilian already on the map kept its
## pre-swap color while newly revealed actors used the new one, mixing both
## palettes on screen mid-mission. _recolor_actor below now re-reads and
## reapplies the current palette to every already-spawned actor's ring/
## selection/arrow/label/outline materials right here.
func _apply_palette(name: String) -> void:
	if not PALETTES.has(name) or name == _palette_name:
		return
	_palette_name = name
	var palette: Dictionary = PALETTES[name]
	UNIT_COLORS = (palette.unit as Array).map(func(hex: String) -> Color: return Color(hex))
	ENEMY_COLOR = Color(str(palette.enemy))
	CIVILIAN_COLOR = Color(str(palette.civilian))
	DOOR_COLOR = Color(str(palette.door))
	var signal_palette: Dictionary = palette.signal
	SIGNAL_COLORS = {"A": Color(str(signal_palette.A)), "B": Color(str(signal_palette.B)), "C": Color(str(signal_palette.C))}
	_draw_prior_attempt()
	_draw_door_frames()
	for id in _entity_nodes:
		_recolor_actor(_entity_nodes[id])

## L6 fix: reapplies the current UNIT_COLORS/ENEMY_COLOR/CIVILIAN_COLOR to an
## already-spawned actor's team-color cues (base disc, selection ring, aim
## arrow, label outline, and -- for operators -- the model's rim outline
## materials collected in actor_visual.gd), so a mid-mission palette change
## is retroactive instead of only affecting actors spawned afterward.
func _recolor_actor(entry: Dictionary) -> void:
	var kind: String = str(entry.get("kind", ""))
	var index: int = int(entry.get("index", 0))
	var color: Color = UNIT_COLORS[index % UNIT_COLORS.size()] if kind == "unit" else ENEMY_COLOR
	if kind == "civilian":
		color = CIVILIAN_COLOR
	var ring: MeshInstance3D = entry.get("ring")
	if is_instance_valid(ring):
		ring.material_override = _material(color, true)
	var halo: MeshInstance3D = entry.get("threat_halo")
	if is_instance_valid(halo):
		halo.material_override = _material(Color(color.r, color.g, color.b, 0.4), true)
	var selection: MeshInstance3D = entry.get("selection")
	if is_instance_valid(selection):
		selection.material_override = _material(color.lightened(0.18), true)
	var arrow: MeshInstance3D = entry.get("arrow")
	if is_instance_valid(arrow):
		arrow.material_override = _material(color, true)
	var label: Label3D = entry.get("label")
	if is_instance_valid(label):
		label.outline_modulate = color.lightened(0.45) if kind == "unit" else PALE
	var visual: Dictionary = entry.get("visual", {})
	if kind == "unit" and visual is Dictionary and visual.has("outline_rims"):
		var opaque := Color(color.r, color.g, color.b, 1.0)
		for rim: StandardMaterial3D in visual.outline_rims:
			rim.albedo_color = opaque

func _fit_camera() -> void:
	if not is_instance_valid(camera):
		return
	_view_size = get_viewport().get_visible_rect().size
	var aspect := _view_size.x / maxf(_view_size.y, 1.0)
	var frame := Rect2(Vector2.ZERO, _bounds) if _menu_preview else _frame_rect
	var height_size: float
	var width_size: float
	var safe_left := 0.0
	var safe_top := 0.0
	var safe_right := 0.0
	var safe_bottom := 0.0
	if _safe_area.is_empty():
		# No safe area received yet: identical to the pre-1-1 behavior, a
		# symmetric, centered fit with only the legacy bottom reservation.
		var reserved_height := 214.0 if _ui_scale >= 1.5 else 190.0
		var vertical_fraction := clampf((_view_size.y - reserved_height) / maxf(_view_size.y, 1.0), 0.4, 0.87)
		height_size = (frame.size.y * 0.905 + 1.1) / vertical_fraction
		width_size = (frame.size.x + 0.75) / maxf(aspect - 0.12, 0.65)
	else:
		# Pad the raw safe-area insets by a small fixed margin so the frame
		# always keeps clearance from the HTML panels instead of sitting
		# flush against them (the raw insets alone fit the frame exactly to
		# the edge, with no margin).
		safe_left = float(_safe_area.get("left", 0.0)) + SAFE_AREA_MARGIN_PX
		safe_top = float(_safe_area.get("top", 0.0)) + SAFE_AREA_MARGIN_PX
		safe_right = float(_safe_area.get("right", 0.0)) + SAFE_AREA_MARGIN_PX
		safe_bottom = float(_safe_area.get("bottom", 0.0)) + SAFE_AREA_MARGIN_PX
		var safe_width := maxf(_view_size.x - safe_left - safe_right, 1.0)
		var safe_height := maxf(_view_size.y - safe_top - safe_bottom, 1.0)
		var vertical_fraction := clampf(safe_height / maxf(_view_size.y, 1.0), 0.25, 0.97)
		var horizontal_fraction := clampf(safe_width / maxf(_view_size.x, 1.0), 0.25, 0.97)
		# Exact fit (no legacy breathing-room fudge): camera.size is chosen so
		# the frame's pixel footprint equals vertical_fraction/horizontal_fraction
		# of the viewport exactly, i.e. the frame's outer edge lands precisely on
		# the padded safe-rect edge (which already carries SAFE_AREA_MARGIN_PX of
		# clearance from the raw HTML-panel insets). The legacy *0.905+1.1/+0.75
		# padding and the final 0.90 zoom-in multiplier below are tuned for the
		# no-safe-area fallback's looser framing; reapplying them here ate the
		# margin this formula is supposed to guarantee (frame overflowing past
		# the safe rect, e.g. the top wall sitting flush under the top bar).
		height_size = frame.size.y / vertical_fraction
		width_size = frame.size.x / maxf(aspect * horizontal_fraction, 0.1)
	var fit_multiplier := 1.0 if not _safe_area.is_empty() else (1.04 if _menu_preview else 0.90)
	camera.size = maxf(height_size, width_size) * _zoom * fit_multiplier
	# The legacy fallback pushes the look-at target slightly south (center_bias)
	# to compensate for reserving space only at the bottom of the screen. A real
	# safe area already centers the frame correctly via h_offset/v_offset below
	# (independent top/bottom/left/right insets), so applying this extra bias on
	# top of that double-compensates and eats into the top margin.
	var center_bias := (camera.size * 0.030 / 0.905) if _safe_area.is_empty() else 0.0
	# The old fixed 16%-of-screen right bias was a decorative stand-in for a
	# real safe area: it only applies once a real safe area has arrived
	# (below), menu preview no longer needs this legacy nudge.
	var menu_shift := camera.size * aspect * 0.16 if _menu_preview and _safe_area.is_empty() and _view_size.x >= 900 else 0.0
	# Slow cinematic drift for the menu diorama: a gentle orbit around the
	# mission focus point, disabled under reduced motion. Off in regular play.
	var drift := Vector2.ZERO
	if _menu_preview and not _motion_reduced:
		var drift_angle := _menu_drift_time * MENU_DRIFT_SPEED
		var drift_radius := camera.size * MENU_DRIFT_RADIUS_FRACTION
		drift = Vector2(cos(drift_angle), sin(drift_angle)) * drift_radius
	# Once a real safe area has arrived, the menu diorama frames the whole
	# mission map the same way gameplay does (centered on the frame, lens-
	# shifted below into the safe rectangle) instead of panning to the
	# mission's gameplay focus point with the legacy decorative bias.
	var center := (_focus if _safe_area.is_empty() else frame.get_center()) if _menu_preview else frame.get_center()
	var target := Vector3(center.x + _pan.x - menu_shift + drift.x, 0, center.y + _pan.y + center_bias + drift.y)
	var camera_distance := maxf(37.4, maxf(_bounds.x, _bounds.y) * 1.4) if _is_metre_map() else 37.4
	camera.position = target + Vector3(0, 34.0, 15.5).normalized() * camera_distance
	camera.far = maxf(140.0, camera_distance * 3.0 + maxf(_bounds.x, _bounds.y) * 2.0) if _is_metre_map() else 140.0
	camera.look_at(target, Vector3.UP)
	# Lens-shift the orthogonal frustum so the mission frame centers inside the
	# safe rectangle instead of the full canvas, only once a real safe area has
	# arrived. Under orthogonal projection a camera-space h_offset/v_offset is
	# a pure translation of the view plane (no perspective skew), so it maps
	# linearly from the pixel offset between the safe rect's center and the
	# full viewport's center. Applies identically in menu preview and gameplay.
	if _safe_area.is_empty():
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	else:
		var world_per_px_x := (camera.size * aspect) / maxf(_view_size.x, 1.0)
		var world_per_px_y := camera.size / maxf(_view_size.y, 1.0)
		camera.h_offset = -((safe_left - safe_right) * 0.5) * world_per_px_x
		camera.v_offset = ((safe_top - safe_bottom) * 0.5) * world_per_px_y
	# L2 fix: snapshot the just-computed position/size as the base the
	# per-frame shake/freeze-zoom in display() derives from, so those never
	# layer on top of a value _fit_camera() has since moved on from.
	_camera_base_position = camera.position
	_camera_base_size = camera.size

func _rect_from(data: Dictionary) -> Rect2:
	var size := Vector2(float(data.get("w", 0.25)), float(data.get("d", 0.25)))
	return Rect2(Vector2(float(data.get("x", 0.0)), float(data.get("z", 0.0))) - size * 0.5, size)

## H1 fix: room geometry only, rebuilt on every build(). Enemy membership is
## never computed from spawn position any more (see _room_members) -- that
## leaked which rooms held threats the player never saw, and misattributed
## kills made outside a room's walls to whichever room the enemy spawned in.
## Also (re)builds the per-room exploration sample grid used by
## room_observed_fraction/is_room_sufficiently_observed.
func _build_room_threat_map(mission: Dictionary) -> void:
	_room_threat_map.clear()
	_room_sample_points.clear()
	_room_seen_mask.clear()
	_room_seen_count.clear()
	_room_neutralized_ids.clear()
	_neutralized_at.clear()
	var rooms: Array = mission.get("rooms", [])
	for room: Dictionary in rooms:
		var room_id: String = str(room.get("id", room.get("label", "")))
		if room_id.is_empty():
			continue
		var rect := _rect_from(room)
		_room_threat_map[room_id] = {"rect": rect, "floor_height": float(room.get("base_height", 0.0))}
		var points: Array[Vector2] = []
		# A full-size apron is not a small interior room. Bound its observation
		# sampling cost while preserving the original 1m samples in CQB rooms.
		var sample_step := maxf(ROOM_SAMPLE_STEP, sqrt(rect.get_area() / 1024.0)) if int(mission.get("schema_version", 1)) >= 2 else ROOM_SAMPLE_STEP
		var x := rect.position.x + sample_step * 0.5
		while x < rect.end.x:
			var z := rect.position.y + sample_step * 0.5
			while z < rect.end.y:
				points.append(Vector2(x, z))
				z += sample_step
			x += sample_step
		if points.is_empty():
			points.append(rect.get_center())
		_room_sample_points[room_id] = points
		var mask: Array = []
		mask.resize(points.size())
		mask.fill(false)
		_room_seen_mask[room_id] = mask
		_room_seen_count[room_id] = 0
	_room_cleared.clear()
	for room_id: String in _room_threat_map:
		_room_cleared[room_id] = false

## Which room (if any) contains a player-visible point -- used to find the
## room an enemy is actually in right now/was last seen in, and the room a
## neutralization event actually happened in.
func _room_id_at(point: Vector2) -> String:
	for room_id: String in _room_threat_map:
		if (_room_threat_map[room_id]["rect"] as Rect2).has_point(point):
			return room_id
	return ""

## H1 fix: accumulates "has this sample point ever been inside current
## sight" into _room_seen_mask. Called whenever _visibility.update() reports
## new polygons, so exploration persists across the whole mission even as
## current sight comes and goes.
func _update_room_exploration() -> void:
	# Reject entire distant rooms before testing their metre grid. A polygon
	# bounding rectangle is conservative, so every visible sample is retained.
	var sight_rects: Array[Rect2] = _visibility.polygon_bounds()
	for room_id: String in _room_sample_points:
		var points: Array = _room_sample_points[room_id]
		if int(_room_seen_count[room_id]) == points.size(): continue
		var room_rect: Rect2 = _room_threat_map[room_id].rect
		var intersects := false
		for sight_rect: Rect2 in sight_rects:
			if room_rect.intersects(sight_rect):
				intersects = true
				break
		if not intersects: continue
		var mask: Array = _room_seen_mask[room_id]
		var newly_seen := 0
		for i in range(points.size()):
			if not mask[i] and _visibility.contains(points[i]):
				mask[i] = true
				newly_seen += 1
		_room_seen_count[room_id] = int(_room_seen_count[room_id]) + newly_seen

## Fraction of the unchanged metre sample grid seen over the whole mission.
func room_observed_fraction(room_id: String) -> float:
	var mask: Array = _room_seen_mask.get(room_id, [])
	if mask.is_empty(): return 0.0
	# Legacy authoring/test tools may edit their small grid directly.
	if not _is_metre_map():
		var seen := 0
		for value: bool in mask:
			if value: seen += 1
		return float(seen) / float(mask.size())
	return float(_room_seen_count.get(room_id, 0)) / float(mask.size())

## Whether room_id's own center point is inside current sight right now.
func is_room_center_observed(room_id: String) -> bool:
	if not _room_threat_map.has(room_id):
		return false
	return _visibility.contains((_room_threat_map[room_id]["rect"] as Rect2).get_center())

## H1 fix: a room reads as "observed" once enough of its floor has ever been
## seen, or its center is in sight right now -- never for a room the player
## has not actually been in or looked into.
func is_room_sufficiently_observed(room_id: String) -> bool:
	return room_observed_fraction(room_id) >= ROOM_OBSERVED_FRACTION or is_room_center_observed(room_id)

## Seek restores only observed control and recent owned CALL labels, silently.
func _resync_room_cleared(state: Dictionary) -> void:
	_room_neutralized_ids.clear()
	_neutralized_at.clear()
	if state.has("neutralized_ids"):
		for enemy_id: String in state.neutralized_ids:
			_room_neutralized_ids[enemy_id] = true
	else:
		for event: Dictionary in state.get("events", []):
			var type := str(event.get("type", ""))
			if type == "INCAPACITATED" and str(event.get("kind", "")) == "enemy":
				_room_neutralized_ids[str(event.get("entity_id", ""))] = true
				if event.has("to"): _neutralized_at[str(event.get("entity_id", ""))] = Vector2(float(event.to[0]), float(event.to[1]))
			elif type == "ARREST":
				_room_neutralized_ids[str(event.get("enemy_id", ""))] = true
				if event.has("to"): _neutralized_at[str(event.get("enemy_id", ""))] = Vector2(float(event.to[0]), float(event.to[1]))
	var rows := _observed_room_rows(state)
	for room_id: String in _room_threat_map:
		var row: Dictionary = rows.get(room_id, {})
		_room_cleared[room_id] = row.get("observed", false) == true and str(row.get("state", "UNKNOWN")) in ["CLEAR", "MARKED"]
	_room_control_inputs.clear()
	_call_events.clear()
	for event: Dictionary in state.get("events", []): _remember_call(event, state)

func _observed_room_rows(state: Dictionary) -> Dictionary:
	var memory: Variant = state.get("room_states_observed", state.get("room_states", {}))
	return memory if memory is Dictionary else {}

func _is_own_unit(id: String, state: Dictionary) -> bool:
	if id.is_empty(): return false
	for unit: Dictionary in state.get("units", _mission.get("units", [])):
		if str(unit.get("id", "")) == id: return true
	return false

func _remember_call(event: Dictionary, state: Dictionary) -> void:
	var type := str(event.get("type", ""))
	var id := str(event.get("unit_id", ""))
	var time := float(event.get("time", INF))
	if not CALL_LABELS.has(type) or event.get("observed", false) != true or not _is_own_unit(id, state): return
	if not is_finite(time) or time > _clock + 0.000001 or _clock - time > CALL_LABEL_SECONDS: return
	if int(event.get("seq", 0)) <= int(_call_events.get(id, {}).get("seq", 0)): return
	_call_events[id] = {"type": type, "time": time, "seq": int(event.seq)}

func _sync_call_labels(state: Dictionary) -> void:
	for id: String in _entity_nodes:
		var entry: Dictionary = _entity_nodes[id]
		var label: Label3D = entry.get("call_label")
		if not is_instance_valid(label): continue
		var call: Dictionary = _call_events.get(id, {})
		label.visible = _is_own_unit(id, state) and not call.is_empty() and _clock - float(call.get("time", -INF)) <= CALL_LABEL_SECONDS
		if label.visible: label.text = _t(str(CALL_LABELS[call.type]))

func _sync_room_control_labels(state: Dictionary) -> void:
	var rows := _observed_room_rows(state)
	var inputs: Array = [rows, _language, _palette_name]
	if _room_control_inputs == inputs: return
	_room_control_inputs = inputs.duplicate(true)
	for room_id: String in _room_threat_map:
		var row: Dictionary = rows.get(room_id, {})
		var status := str(row.get("state", "UNKNOWN"))
		var observed: bool = row.get("observed", false) == true and ROOM_STATE_LABELS.has(status)
		_room_cleared[room_id] = observed and status in ["CLEAR", "MARKED"]
		if not observed:
			if _room_state_labels.has(room_id): _room_state_labels[room_id].visible = false
			continue
		if not _room_state_labels.has(room_id):
			var label := _label("", PALE, 28, 0.0085)
			var center: Vector2 = (_room_threat_map[room_id].rect as Rect2).get_center()
			label.position = Vector3(center.x, float(_room_threat_map[room_id].floor_height) + 0.4, center.y)
			_marks.add_child(label)
			_room_state_labels[room_id] = label
		var label: Label3D = _room_state_labels[room_id]
		label.visible = true
		label.text = _t(str(ROOM_STATE_LABELS[status]))
		label.modulate = ENEMY_COLOR if status == "CONTACT" else (UNIT_COLORS[0] if status in ["CLEAR", "MARKED"] else PALE)

## Only this event can flash a newly cleared room. Current rows may contain
## a later transition when several simulation ticks share one render frame.
func _mark_room_clear(unit_id: String, position: Array, state: Dictionary, transition: Variant = null) -> void:
	if not transition is Dictionary or str(transition.get("type", "")) != "CALL_ROOM_CLEAR" or transition.get("observed", false) != true: return
	var room_id := str(transition.get("room_id", ""))
	if not _room_threat_map.has(room_id) or not _is_own_unit(unit_id, state): return
	if position.size() != 2 or not (position[0] is int or position[0] is float) or not (position[1] is int or position[1] is float): return
	if not (_room_threat_map[room_id].rect as Rect2).has_point(Vector2(float(position[0]), float(position[1]))): return
	var age := _clock - float(transition.get("time", INF))
	if not is_finite(age) or age < -0.000001: return
	_room_cleared[room_id] = true
	if age < ROOM_CLEAR_FLASH_DURATION:
		_room_clear_flashes.append({"rect": _room_threat_map[room_id].rect, "floor_height": _room_threat_map[room_id].floor_height, "remaining": ROOM_CLEAR_FLASH_DURATION - age, "fresh": true})

func _room_control_line(from: Vector2, to: Vector2, width: float, height: float, color: Color) -> void:
	if from.distance_squared_to(to) < 0.0000001: return
	var normal := (to - from).normalized().orthogonal() * width * 0.5
	var a := Vector3(from.x + normal.x, height, from.y + normal.y)
	var b := Vector3(to.x + normal.x, height, to.y + normal.y)
	var c := Vector3(to.x - normal.x, height, to.y - normal.y)
	var d := Vector3(from.x - normal.x, height, from.y - normal.y)
	_event_mesh.surface_set_color(color)
	_event_mesh.surface_set_normal(Vector3.UP)
	# Explicit authored floor: generic overlays select the highest overlapping
	# surface, which could otherwise stamp the wrong floor's room.
	for point: Vector3 in [a, b, c, a, c, d]: _event_mesh.surface_add_vertex(point)

func _batch_static_geometry() -> void:
	var groups: Dictionary = {}
	_collect_static(_world, groups)
	for key in groups:
		var members: Array = groups[key]
		var first: MeshInstance3D = members[0]
		if first.mesh is ArrayMesh and members.size() < 2: continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		var shared_mesh: Mesh = first.mesh
		# MultiMesh has no per-surface overrides. Preserve each authored PBR
		# surface by copying only a mesh that actually has node-level overrides.
		for surface in range(first.mesh.get_surface_count()):
			var override := first.get_surface_override_material(surface)
			if override != null:
				if shared_mesh == first.mesh: shared_mesh = first.mesh.duplicate()
				shared_mesh.surface_set_material(surface, override)
		multimesh.mesh = shared_mesh
		multimesh.instance_count = members.size()
		for index in range(members.size()):
			var member: MeshInstance3D = members[index]
			multimesh.set_instance_transform(index, _world.global_transform.affine_inverse() * member.global_transform)
			member.visible = false
			member.queue_free()
		var batch := MultiMeshInstance3D.new()
		batch.multimesh = multimesh
		batch.material_override = first.material_override
		batch.cast_shadow = first.cast_shadow
		if first.has_meta("fog_exempt"): batch.set_meta("fog_exempt", true)
		_world.add_child(batch)

func _collect_static(node: Node, groups: Dictionary) -> void:
	if node.has_meta("dynamic_geometry") or (node is Node3D and not node.visible):
		return
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var primitive := mesh_node.mesh == _box_mesh or mesh_node.mesh == _sphere_mesh or mesh_node.mesh == _cylinder_mesh
		var imported_static := mesh_node.mesh is ArrayMesh and mesh_node.skin == null
		if primitive or imported_static:
			var material_id := mesh_node.material_override.get_instance_id() if mesh_node.material_override != null else 0
			var key := str(mesh_node.mesh.get_instance_id()) + ":" + str(material_id) + ":" + str(mesh_node.cast_shadow) + ":" + str(mesh_node.has_meta("fog_exempt"))
			for surface in range(mesh_node.mesh.get_surface_count()):
				var override := mesh_node.get_surface_override_material(surface)
				key += ":" + str(override.get_instance_id() if override != null else 0)
			if not groups.has(key): groups[key] = []
			groups[key].append(mesh_node)
	for child in node.get_children():
		_collect_static(child, groups)

func _merge_actor_geometry(parent: Node3D) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var found := false
	for child in parent.get_children():
		if not child is MeshInstance3D:
			continue
		var source := child as MeshInstance3D
		var arrays := source.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var color: Color = source.material_override.albedo_color
		var normal_basis := source.transform.basis.inverse().transposed()
		if indices.is_empty():
			for i in range(vertices.size()):
				surface.set_color(color)
				surface.set_normal((normal_basis * normals[i]).normalized())
				surface.add_vertex(source.transform * vertices[i])
		else:
			for i in indices:
				surface.set_color(color)
				surface.set_normal((normal_basis * normals[i]).normalized())
				surface.add_vertex(source.transform * vertices[i])
		source.visible = false
		source.queue_free()
		found = true
	if found:
		var merged := MeshInstance3D.new()
		merged.mesh = surface.commit()
		var material: StandardMaterial3D
		if _materials.has("__actor_vertex"):
			material = _materials["__actor_vertex"]
		else:
			material = StandardMaterial3D.new()
			material.vertex_color_use_as_albedo = true
			material.roughness = 0.9
			_materials["__actor_vertex"] = material
		merged.material_override = material
		parent.add_child(merged)

## `overlay` materials (marks, caps, objective chrome) sort after the fog layer; everything else is fogged.
func _material(color: Color, unshaded: bool = false, overlay: bool = false) -> StandardMaterial3D:
	var key := color.to_html(true) + ("u" if unshaded else "l") + ("o" if overlay else "")
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 0.99:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED if unshaded else BaseMaterial3D.CULL_BACK
	if overlay: _draw_after_fog(material)
	_materials[key] = material
	return material

func _vertex_material() -> StandardMaterial3D:
	var key := "__vertex_overlay"
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	_draw_after_fog(material)
	_materials[key] = material
	return material

func _box(parent: Node3D, position_value: Vector3, size: Vector3, color: Color, overlay: bool = false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _box_mesh
	mesh.material_override = _material(color, false, overlay)
	mesh.position = position_value
	mesh.scale = size
	parent.add_child(mesh)
	return mesh

func _cylinder(parent: Node3D, position_value: Vector3, size: Vector3, color: Color, overlay: bool = false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _cylinder_mesh
	mesh.material_override = _material(color, false, overlay)
	mesh.position = position_value
	mesh.scale = size
	parent.add_child(mesh)
	return mesh

func _sphere(parent: Node3D, position_value: Vector3, size: Vector3, color: Color, overlay: bool = false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _sphere_mesh
	mesh.material_override = _material(color, false, overlay)
	mesh.position = position_value
	mesh.scale = size
	parent.add_child(mesh)
	return mesh

func _label(value: String, color: Color, font_size_value: int, pixel: float) -> Label3D:
	var label := Label3D.new()
	label.font = _label_font
	label.text = value
	label.modulate = color
	label.font_size = font_size_value
	label.pixel_size = pixel
	label.outline_size = 7
	label.outline_modulate = Color("202a29")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.shaded = false
	label.outline_render_priority = LABEL_OUTLINE_PRIORITY
	label.render_priority = LABEL_PRIORITY
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return label

func _disc_mesh(radius: float, color: Color, segments: int) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(color, true))
	_flat_disc(mesh, Vector2.ZERO, radius, 0, Color.WHITE, segments)
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func _flat_disc(mesh: ImmediateMesh, center: Vector2, radius: float, height: float, color: Color, segments: int) -> void:
	for i in range(segments):
		var a := i * TAU / segments
		var b := (i + 1) * TAU / segments
		var p1 := center + Vector2(cos(a), sin(a)) * radius
		var p2 := center + Vector2(cos(b), sin(b)) * radius
		_triangle(mesh, Vector3(center.x, height, center.y), Vector3(p1.x, height, p1.y), Vector3(p2.x, height, p2.y), color)

func _ring_mesh(inner: float, outer: float, color: Color, segments: int, overlay: bool = false) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(color, true, overlay))
	_flat_ring(mesh, Vector2.ZERO, (inner + outer) * 0.5, outer - inner, 0, Color.WHITE, segments)
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func _triangle(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	# Only world-space overlays follow the walking surface. Actor-local rings,
	# room slabs and model vertices already carry their own node elevation.
	if not _elevated_rooms.is_empty():
		var ground_overlay := mesh in [_path_mesh, _cone_mesh, _interaction_mesh, _drill_mesh, _smoke_mesh, _sound_mesh, _gamepad_mesh]
		if ground_overlay or (mesh == _event_mesh and maxf(a.y, maxf(b.y, c.y)) < 0.8):
			a.y += surface_offset(Vector2(a.x, a.z))
			b.y += surface_offset(Vector2(b.x, b.z))
			c.y += surface_offset(Vector2(c.x, c.z))
	mesh.surface_set_color(color)
	mesh.surface_set_normal(Vector3.UP)
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)
	mesh.surface_add_vertex(c)

## Same as `_triangle` but each vertex carries its own colour (soft glows).
func _triangle_c(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, color_a: Color, color_b: Color, color_c: Color) -> void:
	if not _elevated_rooms.is_empty() and mesh == _event_mesh and maxf(a.y, maxf(b.y, c.y)) < 0.8:
		a.y += surface_offset(Vector2(a.x, a.z))
		b.y += surface_offset(Vector2(b.x, b.z))
		c.y += surface_offset(Vector2(c.x, c.z))
	mesh.surface_set_normal(Vector3.UP)
	mesh.surface_set_color(color_a)
	mesh.surface_add_vertex(a)
	mesh.surface_set_color(color_b)
	mesh.surface_add_vertex(b)
	mesh.surface_set_color(color_c)
	mesh.surface_add_vertex(c)

func _flat_line(mesh: ImmediateMesh, from: Vector2, to: Vector2, width: float, height: float, color: Color) -> void:
	if from.distance_squared_to(to) < 0.0000001:
		return
	var normal := (to - from).normalized().orthogonal() * width * 0.5
	var a := Vector3(from.x + normal.x, height, from.y + normal.y)
	var b := Vector3(to.x + normal.x, height, to.y + normal.y)
	var c := Vector3(to.x - normal.x, height, to.y - normal.y)
	var d := Vector3(from.x - normal.x, height, from.y - normal.y)
	_triangle(mesh, a, b, c, color)
	_triangle(mesh, a, c, d, color)

func _dashed_line(mesh: ImmediateMesh, from: Vector2, to: Vector2, width: float, height: float, color: Color) -> void:
	var distance := from.distance_to(to)
	if distance < 0.001:
		return
	var direction := from.direction_to(to)
	var progress := 0.0
	while progress < distance:
		_flat_line(mesh, from + direction * progress, from + direction * minf(progress + 0.23, distance), width, height, color)
		progress += 0.35
	_arrow_head(mesh, from, to, 0.16, height, color)

func _arrow_head(mesh: ImmediateMesh, from: Vector2, to: Vector2, width: float, height: float, color: Color) -> void:
	if from.distance_squared_to(to) < 0.0001:
		return
	var direction := from.direction_to(to)
	var side := direction.orthogonal() * width
	var back := to - direction * width * 1.7
	_triangle(mesh, Vector3(to.x, height, to.y), Vector3(back.x + side.x, height, back.y + side.y), Vector3(back.x - side.x, height, back.y - side.y), color)

func _flat_ring(mesh: ImmediateMesh, center: Vector2, radius: float, width: float, height: float, color: Color, segments: int) -> void:
	for i in range(segments):
		var a := i * TAU / segments
		var b := (i + 1) * TAU / segments
		var p0 := center + Vector2(cos(a), sin(a)) * (radius - width * 0.5)
		var p1 := center + Vector2(cos(b), sin(b)) * (radius - width * 0.5)
		var p2 := center + Vector2(cos(b), sin(b)) * (radius + width * 0.5)
		var p3 := center + Vector2(cos(a), sin(a)) * (radius + width * 0.5)
		_triangle(mesh, Vector3(p0.x, height, p0.y), Vector3(p1.x, height, p1.y), Vector3(p2.x, height, p2.y), color)
		_triangle(mesh, Vector3(p0.x, height, p0.y), Vector3(p2.x, height, p2.y), Vector3(p3.x, height, p3.y), color)
