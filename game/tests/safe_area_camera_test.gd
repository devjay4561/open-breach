extends SceneTree
## Headless coverage for BreachWorld._fit_camera()'s safe-area math (plan 1-1):
## the mission frame must fit inside the safe rectangle (viewport minus the
## HTML panel insets), centered within that rectangle, with reserved_height
## kept as the fallback until a safe area has been received.

const World = preload("res://scripts/world_view.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _fixture() -> Dictionary:
	return {"id": "T01", "seed": 1, "bounds": [16, 12], "focus": [8, 6], "rooms": [{"x": 8, "z": 6, "w": 10, "d": 8, "label": "01 / TEST"}], "walls": [], "doors": [], "props": [], "units": [{"id": "alpha", "x": 4, "z": 6, "facing": 0}], "enemies": [], "civilians": []}

func _run() -> void:
	# The headless runner's default window is a tiny 64x64 placeholder, which
	# is fine for the formula-consistency checks below (they derive their
	# expectations from the actual view_size) but makes the plan-round-C
	# pixel-margin regression check meaningless: realistic CSS-px insets like
	# a 48px top bar would consume most or all of a 64px-tall canvas and
	# saturate the fraction clamps, producing failures unrelated to the
	# camera-fit math under test. Size the window like a real 1600x900 canvas
	# so that check reflects an actual screen.
	root.size = Vector2i(1600, 900)
	var world: Node3D = World.new()
	root.add_child(world)
	world.build(_fixture())
	var view_size: Vector2 = world.get_viewport().get_visible_rect().size
	_check(view_size.x > 0.0 and view_size.y > 0.0, "Headless viewport has a non-zero size")

	# --- Fallback: no safe area received yet -> identical to the pre-1-1
	# symmetric, centered fit (reserved_height only shrinks the frame, it does
	# not lens-shift it), so existing framing/readability checks keep passing.
	var fallback_size: float = world.camera.size
	_check(world.camera.h_offset == 0.0, "No safe area keeps h_offset at zero")
	_check(world.camera.v_offset == 0.0, "No safe area keeps v_offset at zero (centered, not shifted)")

	# --- A real safe area replaces the fallback and must shrink available space.
	var insets := {"left": 280.0, "top": 56.0, "right": 300.0, "bottom": 80.0}
	world.set_safe_area(insets)
	_check(world.camera.size > fallback_size, "A larger safe-area reservation than the fallback zooms out (larger ortho size) to still fit the frame")

	# --- The frustum must be lens-shifted toward the side with more room,
	# reproducing the exact formula used by _fit_camera so a regression in the
	# sign or scale of the shift fails this test.
	var aspect: float = view_size.x / maxf(view_size.y, 1.0)
	var world_per_px_x: float = (world.camera.size * aspect) / maxf(view_size.x, 1.0)
	var world_per_px_y: float = world.camera.size / maxf(view_size.y, 1.0)
	var expected_h: float = -((insets.left - insets.right) * 0.5) * world_per_px_x
	var expected_v: float = ((insets.top - insets.bottom) * 0.5) * world_per_px_y
	_check(is_equal_approx(world.camera.h_offset, expected_h), "h_offset matches the safe-area centering formula (left=%s right=%s -> got %s want %s)" % [insets.left, insets.right, world.camera.h_offset, expected_h])
	_check(is_equal_approx(world.camera.v_offset, expected_v), "v_offset matches the safe-area centering formula (top=%s bottom=%s -> got %s want %s)" % [insets.top, insets.bottom, world.camera.v_offset, expected_v])
	# Right inset (300) exceeds left (280): the safe rectangle's center sits
	# left of the full canvas center, which (per the _fit_camera formula this
	# reproduces above) is a positive h_offset.
	_check(world.camera.h_offset > 0.0, "Right inset larger than left offsets the frame away from zero (h_offset sign matches (left-right))")
	# Top inset (56) is smaller than bottom (80): the safe rectangle's center
	# sits above the full canvas center, a negative v_offset.
	_check(world.camera.v_offset < 0.0, "Top inset smaller than bottom offsets the frame away from zero (v_offset sign matches (top-bottom))")

	# --- Symmetric insets center the frame with no lens shift at all.
	world.set_safe_area({"left": 120.0, "top": 40.0, "right": 120.0, "bottom": 40.0})
	_check(is_equal_approx(world.camera.h_offset, 0.0), "Symmetric left/right insets produce zero h_offset")
	_check(is_equal_approx(world.camera.v_offset, 0.0), "Symmetric top/bottom insets produce zero v_offset")

	# --- Pan, zoom and Home (reset_camera) keep working with a safe area set.
	var centered_size: float = world.camera.size
	world.zoom(1.0)
	_check(world.camera.size != centered_size, "zoom() still changes camera.size with a safe area active")
	world.pan(Vector2(1, 0), 1.0)
	var panned_position: Vector3 = world.camera.position
	world.reset_camera()
	_check(not world.camera.position.is_equal_approx(panned_position), "reset_camera() (Home) restores framing after pan/zoom")
	_check(is_equal_approx(world.camera.size, centered_size), "reset_camera() restores the pre-zoom camera size")

	# --- The mission frame must keep a small fixed margin inside the safe
	# rectangle (plan round B): the raw insets alone fit the frame exactly to
	# the safe-rect edge (margin == 0), which visually sits flush against the
	# HTML panel. World.SAFE_AREA_MARGIN_PX pads every side before the
	# fraction math, so the resulting camera.size must be strictly larger
	# than the zero-margin fit (a larger ortho size reserves extra clearance).
	var margin_insets := {"left": 260.0, "top": 48.0, "right": 300.0, "bottom": 72.0}
	world.set_safe_area(margin_insets)
	var margin_size: float = world.camera.size
	var padded_left: float = margin_insets.left + World.SAFE_AREA_MARGIN_PX
	var padded_top: float = margin_insets.top + World.SAFE_AREA_MARGIN_PX
	var padded_right: float = margin_insets.right + World.SAFE_AREA_MARGIN_PX
	var padded_bottom: float = margin_insets.bottom + World.SAFE_AREA_MARGIN_PX
	_check(padded_left > margin_insets.left and padded_top > margin_insets.top, "SAFE_AREA_MARGIN_PX is a positive clearance added on top of the raw insets")
	# Symmetric margin padding must not change the lens-shift sign/scale: the
	# margin is added equally to both sides of each axis, so (left-right) and
	# (top-bottom) are unchanged and the offset formula still matches exactly.
	var margin_aspect: float = view_size.x / maxf(view_size.y, 1.0)
	var margin_world_per_px_x: float = (world.camera.size * margin_aspect) / maxf(view_size.x, 1.0)
	var margin_world_per_px_y: float = world.camera.size / maxf(view_size.y, 1.0)
	var margin_expected_h: float = -((margin_insets.left - margin_insets.right) * 0.5) * margin_world_per_px_x
	var margin_expected_v: float = ((margin_insets.top - margin_insets.bottom) * 0.5) * margin_world_per_px_y
	_check(is_equal_approx(world.camera.h_offset, margin_expected_h), "Margin padding keeps h_offset matching the (left-right) formula")
	_check(is_equal_approx(world.camera.v_offset, margin_expected_v), "Margin padding keeps v_offset matching the (top-bottom) formula")

	# --- Plan round C regression check: the frame's bounding-box corners
	# (converted to screen pixels the same way the renderer does: target pixel
	# position from h_offset/v_offset, then each corner offset from the target
	# by its world-space delta) must stay strictly inside the padded safe
	# rectangle. This is the direct check for the top-wall-under-the-topbar
	# bug: a frame that overflows the intended safe fraction projects past the
	# margin-padded safe-rect edge on at least one side.
	var proj_insets := {"left": 260.0, "top": 48.0, "right": 300.0, "bottom": 85.0}
	world.set_safe_area(proj_insets)
	var proj_world_per_px_x: float = (world.camera.size * aspect) / maxf(view_size.x, 1.0)
	var proj_world_per_px_y: float = world.camera.size / maxf(view_size.y, 1.0)
	var target_px_x: float = view_size.x * 0.5 - world.camera.h_offset / proj_world_per_px_x
	var target_px_y: float = view_size.y * 0.5 + world.camera.v_offset / proj_world_per_px_y
	var target_world: Vector2 = world._frame_rect.get_center() + world._pan
	var frame_min_px_x: float = target_px_x + (world._frame_rect.position.x - target_world.x) / proj_world_per_px_x
	var frame_max_px_x: float = target_px_x + (world._frame_rect.end.x - target_world.x) / proj_world_per_px_x
	var frame_min_px_y: float = target_px_y + (world._frame_rect.position.y - target_world.y) / proj_world_per_px_y
	var frame_max_px_y: float = target_px_y + (world._frame_rect.end.y - target_world.y) / proj_world_per_px_y
	var safe_min_x: float = proj_insets.left + World.SAFE_AREA_MARGIN_PX
	var safe_max_x: float = view_size.x - proj_insets.right - World.SAFE_AREA_MARGIN_PX
	var safe_min_y: float = proj_insets.top + World.SAFE_AREA_MARGIN_PX
	var safe_max_y: float = view_size.y - proj_insets.bottom - World.SAFE_AREA_MARGIN_PX
	_check(frame_min_px_x >= safe_min_x - 0.5, "Frame left edge (%spx) stays >= the safe rect's left margin (%spx)" % [frame_min_px_x, safe_min_x])
	_check(frame_max_px_x <= safe_max_x + 0.5, "Frame right edge (%spx) stays <= the safe rect's right margin (%spx)" % [frame_max_px_x, safe_max_x])
	_check(frame_min_px_y >= safe_min_y - 0.5, "Frame top edge (%spx) stays >= the safe rect's top margin (%spx) -- regression check for the top wall/cap hidden under the top bar" % [frame_min_px_y, safe_min_y])
	_check(frame_max_px_y <= safe_max_y + 0.5, "Frame bottom edge (%spx) stays <= the safe rect's bottom margin (%spx)" % [frame_max_px_y, safe_max_y])

	# --- Menu diorama must also respect set_safe_area (orchestrator round B
	# addendum): the title/mission-select/briefing menus send asymmetric
	# insets so the diorama fills a specific region (e.g. right ~65% on the
	# title screen), and the diorama must lens-shift into that rectangle the
	# same way gameplay does, instead of staying centered with h_offset/
	# v_offset locked at zero.
	world.set_menu_preview(true)
	var title_insets := {"left": 640.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	world.set_safe_area(title_insets)
	var menu_aspect: float = view_size.x / maxf(view_size.y, 1.0)
	var menu_world_per_px_x: float = (world.camera.size * menu_aspect) / maxf(view_size.x, 1.0)
	var menu_world_per_px_y: float = world.camera.size / maxf(view_size.y, 1.0)
	var menu_expected_h: float = -((title_insets.left - title_insets.right) * 0.5) * menu_world_per_px_x
	var menu_expected_v: float = ((title_insets.top - title_insets.bottom) * 0.5) * menu_world_per_px_y
	_check(not is_equal_approx(world.camera.h_offset, 0.0), "Menu diorama with an asymmetric safe area no longer forces h_offset to zero")
	_check(is_equal_approx(world.camera.h_offset, menu_expected_h), "Menu diorama h_offset matches the same (left-right) formula gameplay uses")
	_check(is_equal_approx(world.camera.v_offset, menu_expected_v), "Menu diorama v_offset matches the same (top-bottom) formula gameplay uses")
	world.set_menu_preview(false)

	# --- A fresh world that has never received a safe area at all (not even
	# the symmetric-zero case above) must still fall back to the pre-addendum
	# menu framing: centered lens (h_offset/v_offset zero) with the legacy
	# decorative right-bias (menu_shift) applied to the look-at target.
	var fresh_world: Node3D = World.new()
	root.add_child(fresh_world)
	fresh_world.build(_fixture())
	fresh_world.set_menu_preview(true)
	_check(fresh_world.camera.h_offset == 0.0, "Menu diorama with no safe area received keeps h_offset at zero (legacy fallback)")
	_check(fresh_world.camera.v_offset == 0.0, "Menu diorama with no safe area received keeps v_offset at zero (legacy fallback)")

	# --- Survey-mark corner ticks and the "INSERTION // 01" caption are
	# tactical-map chrome that makes the diorama look like a framed picture
	# instead of a full-bleed background; they must be hidden in menu preview
	# and restored for gameplay (orchestrator round B addendum).
	_check(not fresh_world._chrome_nodes.is_empty(), "build() populates chrome nodes (survey marks + insertion caption) to toggle")
	var all_hidden := true
	for chrome_node in fresh_world._chrome_nodes:
		if chrome_node.visible:
			all_hidden = false
	_check(all_hidden, "Survey marks and insertion caption are hidden while the menu diorama is active")
	fresh_world.set_menu_preview(false)
	var all_visible := true
	for chrome_node in fresh_world._chrome_nodes:
		if not chrome_node.visible:
			all_visible = false
	_check(all_visible, "Survey marks and insertion caption are restored for gameplay")

	# --- Menu diorama drift: a slow orbit that moves the camera's look-at
	# target over (simulated) time, and must be fully inert under reduced
	# motion so it never fights a user's motion-sensitivity setting.
	world.set_menu_preview(true)
	world.set_settings({"reduced_motion": false})
	world._menu_drift_time = 0.0
	world._fit_camera()
	var drift_start_position: Vector3 = world.camera.position
	world._menu_drift_time = 40.0
	world._fit_camera()
	var drift_later_position: Vector3 = world.camera.position
	_check(not drift_start_position.is_equal_approx(drift_later_position), "Menu diorama camera drifts over time when motion is not reduced")
	world.set_settings({"reduced_motion": true})
	world._menu_drift_time = 0.0
	world._fit_camera()
	var reduced_start_position: Vector3 = world.camera.position
	world._menu_drift_time = 40.0
	world._fit_camera()
	var reduced_later_position: Vector3 = world.camera.position
	_check(reduced_start_position.is_equal_approx(reduced_later_position), "Menu diorama camera does not drift when reduced_motion is set")
	world.set_menu_preview(false)
	world.set_settings({"reduced_motion": false})

	# --- L1: set_safe_area only accepts finite numeric insets. null/array/
	# string/non-finite values used to raise a script error (float(null)
	# etc.) and abort the caller's _action before _send_state; they must now
	# be silently ignored (that side keeps its previous value) instead of
	# crashing or zeroing the whole safe area out.
	var l1_world: Node3D = World.new()
	root.add_child(l1_world)
	l1_world.build(_fixture())
	l1_world.set_safe_area({"left": 50.0, "top": 20.0, "right": 60.0, "bottom": 30.0})
	var l1_before_h: float = l1_world.camera.h_offset
	var l1_before_v: float = l1_world.camera.v_offset
	var l1_before_size: float = l1_world.camera.size
	l1_world.set_safe_area({"left": null, "top": [1, 2], "right": "oops", "bottom": 1.0 / 0.0})
	_check(is_equal_approx(l1_world.camera.h_offset, l1_before_h), "set_safe_area ignores a null left inset instead of crashing or zeroing h_offset")
	_check(is_equal_approx(l1_world.camera.v_offset, l1_before_v), "set_safe_area ignores array/non-finite top/bottom insets instead of crashing or zeroing v_offset")
	_check(is_equal_approx(l1_world.camera.size, l1_before_size), "set_safe_area with every inset invalid (null/array/string/non-finite) leaves camera framing unchanged")
	l1_world.set_safe_area({"left": 999999.0, "top": 999999.0, "right": 999999.0, "bottom": 999999.0})
	_check(l1_world.camera.size > l1_before_size, "set_safe_area clamps out-of-range insets to the viewport instead of rejecting them, still shrinking available space")

	print("BREACH_SAFE_AREA_CAMERA_TEST_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		print("  - ", failure)
	quit(1 if not failures.is_empty() else 0)
