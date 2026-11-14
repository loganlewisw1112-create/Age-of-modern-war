extends RefCounted
## G7.1 CONTROL71 playtest (windowed): hover outline on a unit and a building, the roster panel (narrow / centre / all),
## zoom-to-cursor with the real wheel, edge scroll, the bigger minimap with incoming-wave markers (survival waves) and
## click-drag. Screenshots: control71_*.png.
const MatchViewScript = preload("res://presentation/match_view.gd")


func _minimap(root: Node):
	for n in root.find_children("*", "Control", true, false):
		var s = n.get_script()
		if s != null and String(s.resource_path).ends_with("hud/minimap.gd"):
			return n
	return null


func _wheel(pt, p: Vector2, up: bool) -> void:
	await pt._move(p)
	for pressed in [true, false]:
		var b := InputEventMouseButton.new()
		b.position = p
		b.global_position = p
		b.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		b.pressed = pressed
		pt._push(b)
		await pt.get_tree().process_frame


func run(pt) -> void:
	var cfg := SimWorld.default_config()
	cfg.survival = {"attacker": 1}
	cfg.sides[1].ai = true
	if not pt.main.start_match(cfg):
		pt._log("control71_start", false, "start_match failed")
		return
	await pt._wait(2.0)
	var mv = pt._mv()
	var w: SimWorld = pt._w()
	mv.join_sim()
	var hq = mv._player_hq()
	var base: Vector2 = hq.pos if hq != null else Vector2(w.factions[0].spawn)
	var ids: Array = []
	for i in 24:
		ids.append(w.spawn_unit("rifleman", 0, base + Vector2(4 + (i % 6) * 0.9, 4 + (i / 6) * 0.9)))
	for i in 4:
		ids.append(w.spawn_unit("mbt", 0, base + Vector2(11 + i * 1.6, 6)))
	mv.center_camera_on(base + Vector2(6, 6))
	mv.camera.set_zoom_level(1.0)
	await pt._wait(1.0)
	# ---- hover outline on a unit
	var u: Dictionary = w.entities[ids[3]]
	var sp: Vector2 = pt._to_screen(u.pos) + Vector2(0, -16)
	mv.demo_mouse_world = u.pos   # the harness mouse does not move the real cursor: use the view's own override
	await pt._wait(0.4)
	var ho = mv.hover_outline
	var hit: Dictionary = ho._last_hit if ho != null else {}
	pt._log("control71_hover_unit", not hit.is_empty() and int(hit.get("id", -1)) != -1 and String(hit.kind) == "unit", "hover=%s" % str(hit.get("id", -1)))
	await pt._shot("control71_hover_unit")
	var bsp: Vector2 = pt._to_screen(hq.pos + Vector2(1, 1)) if hq != null else Vector2(300, 300)
	mv.demo_mouse_world = hq.pos + Vector2(1, 1) if hq != null else base
	await pt._wait(0.4)
	hit = ho._last_hit
	pt._log("control71_hover_building", String(hit.get("kind", "")) == "building", "hover=%s" % str(hit))
	await pt._shot("control71_hover_building")
	mv.demo_mouse_world = null
	# ---- roster
	mv.select_ids(ids)
	await pt._wait(0.8)
	var ro = mv.get_node_or_null("Roster71")
	var rp = ro.panel if ro != null else null
	pt._log("control71_roster_visible", rp != null and rp.visible and ro._groups.size() == 2, "groups=%d" % (ro._groups.size() if ro != null else -1))
	await pt._shot("control71_roster")
	if rp != null and rp.visible:
		var row = null
		for c in ro._rows_box.get_children():
			if c.has_meta("roster_def") and String(c.get_meta("roster_def")) == "mbt":
				row = c
		if row != null:
			await pt._click(row.get_global_rect().get_center())
			await pt._wait(0.3)
			pt._log("control71_roster_narrow", mv.selection.size() == 4, "selected=%d" % mv.selection.size())
			var cam0: Vector2 = mv.camera.position
			mv.center_camera_on(base - Vector2(10, 10))
			var c1: Vector2 = mv.camera.position
			var row2 = ro._rows_box.get_children()[0]
			await pt._click(row2.get_global_rect().get_center(), MOUSE_BUTTON_LEFT, true)
			await pt._wait(0.3)
			pt._log("control71_roster_centre", mv.camera.position.distance_to(c1) > 50.0, "moved=%.0f" % mv.camera.position.distance_to(c1))
			await pt._shot("control71_roster_narrow")
			ro._restore_all()
			await pt._wait(0.3)
			pt._log("control71_roster_all", mv.selection.size() == 28, "selected=%d" % mv.selection.size())
	# ---- zoom to cursor (real wheel)
	mv.center_camera_on(base + Vector2(6, 6))
	await pt._wait(0.3)
	var vs: Vector2 = mv.get_viewport().get_visible_rect().size
	var cur := Vector2(vs.x * 0.7, vs.y * 0.35)
	await pt._move(cur)
	await pt._wait(0.2)
	var before: Vector2 = mv.pick_world(mv.get_viewport().get_canvas_transform().affine_inverse() * cur)
	for i in 4:
		await _wheel(pt, cur, false)
	await pt._wait(0.2)
	var after: Vector2 = mv.pick_world(mv.get_viewport().get_canvas_transform().affine_inverse() * cur)
	pt._log("control71_zoom_to_cursor", before.distance_to(after) < 0.1, "zoom=%.2f drift=%.3f tiles" % [mv.camera.zoom.x, before.distance_to(after)])
	# ---- edge scroll
	mv.center_camera_on(base + Vector2(6, 6))
	await pt._wait(0.2)
	var p0: Vector2 = mv.camera.position
	Input.warp_mouse(Vector2(2, vs.y * 0.5))
	await pt._wait(0.6)
	var moved: float = mv.camera.position.x - p0.x
	pt._log("control71_edge_scroll", moved < -50.0 or not mv.get_window().has_focus(), "dx=%.0f focus=%s" % [moved, str(mv.get_window().has_focus())])
	await pt._move(vs * 0.5)
	# ---- minimap: bigger, incoming waves, click-drag
	var mm = _minimap(pt.main)
	pt._log("control71_minimap_size", mm != null and mm.size.x >= 208.0, "size=%s" % str(mm.size if mm != null else "-"))
	mv.camera.set_zoom_level(0.6)
	w.sys_state.get("waves", {})
	await pt._wait(1.0)
	var wm: Array = mm._waves if mm != null else []
	pt._log("control71_minimap_waves", mm != null and not wm.is_empty(), "markers=%d" % wm.size())
	if mm != null:
		var c0: Vector2 = mv.camera.position
		var r: Rect2 = mm.get_global_rect()
		await pt._move(r.position + r.size * 0.3)
		await pt._button(r.position + r.size * 0.3, MOUSE_BUTTON_LEFT, true)
		await pt._move(r.position + r.size * 0.7)
		await pt._button(r.position + r.size * 0.7, MOUSE_BUTTON_LEFT, false)
		await pt._wait(0.3)
		pt._log("control71_minimap_drag", mv.camera.position.distance_to(c0) > 100.0, "moved=%.0f" % mv.camera.position.distance_to(c0))
	await pt._shot("control71_minimap")
