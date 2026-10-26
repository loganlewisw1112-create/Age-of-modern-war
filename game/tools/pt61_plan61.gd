extends RefCounted
## G6.1 playtest flow "plan61" (owner: PLAN61): enter Command mode, draw an axis, two phase lines and an
## objective for a company with real mouse input, issue the plan, watch it advance (shots at each phase
## line, Go signals from the plan card), then a quick officer order for a second company and cancel it.

const Plans = preload("res://sim/systems/plans.gd")
const ClModel = preload("res://presentation/ui6/command_layer/cl_model.gd")
const Companies = preload("res://sim/systems/companies.gd")


func _hub(pt):
	var h = pt.main.get("hud")
	return h.get("cmd_layer") if h != null else null


## Viewport point of world cell c through the overlay's own projection.
func _vp(hub, c: Vector2i) -> Vector2:
	var ov: Control = hub.overlay
	return ov.get_global_transform_with_canvas() * ov.to_local_pt(Vector2(c) + Vector2(0.5, 0.5))


## INTEG61-2: a click target must be on screen and clear of the HUD panels. The objective (19 tiles out) and the
## quick-order target were sometimes off the 1600x900 window (r3: quick click at y=929), so centre the camera on
## the cell before clicking it. Plans are in world cells, so moving the camera never changes the draft.
func _focus(pt, hub, c: Vector2i) -> Vector2:
	pt._mv().center_camera_on(Vector2(c) + Vector2(0.5, 0.5))
	await pt._wait(0.4)
	return _vp(hub, c)


func _cen(w: SimWorld, f: Dictionary) -> Vector2:
	var s := Vector2.ZERO
	var ids := Plans.formation_units(w, f)
	for id in ids:
		s += w.entities[id].pos
	return s / maxf(1.0, float(ids.size()))


func _cell(w: SimWorld, p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x), 1, int(w.map.w) - 2), clampi(int(p.y), 1, int(w.map.h) - 2))


func _newest_plan(w: SimWorld) -> Dictionary:
	var ps := Plans.plans_of(w, 0)
	return ps[ps.size() - 1] if not ps.is_empty() else {}


func run(pt) -> void:
	var hq: Dictionary = await pt._g6_company_hq()
	if hq.is_empty() or not await pt._g6_train_companies(hq, 2):
		pt._log("plan_companies_trained", false, "no Company HQ / companies")
		return
	var w: SimWorld = pt._w()
	var cos := Companies.companies_of(w, 0)
	pt._log("plan_companies_trained", cos.size() >= 2, "companies=%d" % cos.size())
	if cos.size() < 2:
		return
	var fa := {"kind": "company", "id": int(cos[0].id)}
	var fb := {"kind": "company", "id": int(cos[1].id)}
	var hub = _hub(pt)
	if hub == null:
		pt._log("plan_hub", false, "hud.cmd_layer missing")
		return
	pt._log("plan_mode_button_click", await pt._click_named("CommandModeButton"))
	pt._log("plan_mode_active", bool(hub.active))
	# geometry: from company A toward the map centre
	var c0 := _cen(w, fa)
	var mid := Vector2(float(w.map.w), float(w.map.h)) * 0.5
	var dir := (mid - c0).normalized() if mid.distance_to(c0) > 1.0 else Vector2(1, 0)
	var perp := dir.orthogonal()
	pt._mv().center_camera_on(c0 + dir * 9.0)
	await pt._wait(0.5)
	await pt._shot("plan61_command_mode")
	# select company A by clicking its captain on the map
	var cap := int(cos[0].captain)
	var capc := _cell(w, w.entities[cap].pos) if w.entities.has(cap) else _cell(w, c0)
	# INTEG61: click the captain's exact position (company symbols sit within a tile of each other; a cell-centre
	# click could be nearer company B's symbol). capc stays for the fallback when the captain is gone.
	var ovc: Control = hub.overlay
	var clickp: Vector2 = ovc.get_global_transform_with_canvas() * ovc.to_local_pt(w.entities[cap].pos) if w.entities.has(cap) else _vp(hub, capc)
	await pt._click(clickp)
	await pt._wait(0.3)
	if not hub.model.has_draft():   # INTEG61 diagnostics: where the click went vs the formation symbols
		var ov: Control = hub.overlay
		var loc: Vector2 = ov.get_global_transform_with_canvas().affine_inverse() * clickp
		var gp: Vector2 = ov.get_global_transform() * loc
		var blockers := []
		var stack: Array = [ov.get_parent()]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for ch in n.get_children():
				stack.append(ch)
			if n is Control and n != ov and (n as Control).is_visible_in_tree() and (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE \
					and (n as Control).get_global_rect().has_point(gp):
				blockers.append("%s(%s)" % [n.name, n.get_class()])
		print("PLAYTEST-DBG plan_select blockers=%s ov_rect=%s" % [str(blockers), str(ov.get_global_rect())])
		var fms := []
		for fm in hub.model.formations:
			fms.append("%s@%s" % [str(fm.f), str(fm.pos)])
		print("PLAYTEST-DBG plan_select cap=%d cap_pos=%s click=%s to_world=%s hovered=%s ov_vis=%s tool=%s fms=%s" % [cap,
			str(w.entities[cap].pos) if w.entities.has(cap) else "-", str(clickp), str(ov.to_world(loc)),
			str(ov.get_viewport().gui_get_hovered_control()), str(ov.is_visible_in_tree()), str(hub.tool), str(fms)])
	pt._log("plan_select_company", hub.model.has_draft() and hub.model.draft.formation == fa, str(hub.model.draft.get("formation", {})))
	# axis (default tool after selecting): drag from the company toward the objective
	var a0 := _cell(w, c0 + dir * 2.0)
	var a1 := _cell(w, c0 + dir * 20.0)
	await pt._drag(_vp(hub, a0), _vp(hub, a1))
	pt._log("plan_draw_axis", (hub.model.draft.get("axis", []) as Array).size() >= 2, str(hub.model.draft.get("axis", [])))
	pt._log("plan_tool_phase_click", await pt._click_named("Tool_phase"))
	for k in [7.0, 13.0]:
		await pt._drag(_vp(hub, _cell(w, c0 + dir * k - perp * 6.0)), _vp(hub, _cell(w, c0 + dir * k + perp * 6.0)))
	pt._log("plan_draw_phase_lines", (hub.model.draft.get("phase_lines", []) as Array).size() == 2, str((hub.model.draft.get("phase_lines", []) as Array).size()))
	pt._log("plan_tool_objective_click", await pt._click_named("Tool_objective"))
	await pt._click(await _focus(pt, hub, _cell(w, c0 + dir * 19.0)))
	pt._log("plan_draw_objective", (hub.model.draft.get("objectives", []) as Array).size() == 1)
	await pt._wait(0.5)
	await pt._shot("plan61_draft")
	pt._log("plan_ready", hub.reason == "", hub.reason)
	pt._log("plan_issue_click", await pt._click_named("IssuePlanButton"))
	var ok: bool = await pt._wait_until(func(): return not _newest_plan(pt._w()).is_empty(), 5.0)
	var pl := _newest_plan(pt._w())
	pt._log("plan_issued", ok and pl.formation == fa, str(pl.get("line", "")))
	if not ok:
		return
	var pid := int(pl.id)
	pt._mv().speed = 3.0
	ok = await pt._wait_until(func(): return int(Plans.get_plan(pt._w(), pid).get("pl_reached", 0)) >= 1, 90.0)
	pt._log("plan_reached_pl1", ok, Plans.status_line(Plans.get_plan(pt._w(), pid)))
	await pt._wait(1.0)
	pt._log("plan_halted_pl1", String(Plans.get_plan(pt._w(), pid).status) == "halted", String(Plans.get_plan(pt._w(), pid).status))
	await pt._shot("plan61_pl1")
	pt._log("plan_go_click", await pt._click_named("Plan%d_Go" % pid))
	ok = await pt._wait_until(func(): return int(Plans.get_plan(pt._w(), pid).get("pl_reached", 0)) >= 2, 90.0)
	pt._log("plan_reached_pl2", ok, Plans.status_line(Plans.get_plan(pt._w(), pid)))
	await pt._wait(1.0)
	await pt._shot("plan61_pl2")
	pt._log("plan_go2_click", await pt._click_named("Plan%d_Go" % pid))
	ok = await pt._wait_until(func(): return String(Plans.get_plan(pt._w(), pid).status) in ["holding", "on_objective"], 90.0)
	pt._log("plan_objective", ok, Plans.status_line(Plans.get_plan(pt._w(), pid)))
	await pt._shot("plan61_objective")
	# quick officer order for company B, then cancel it from the plan card
	var cb := _cen(pt._w(), fb)
	hub.arm_quick(fb, "attack")
	var qcell := _cell(pt._w(), cb + dir * 10.0)
	var qp: Vector2 = await _focus(pt, hub, qcell)
	await pt._click(qp)
	ok = await pt._wait_until(func(): return _newest_plan(pt._w()).get("formation", {}) == fb, 5.0)
	if not ok:  # INTEG61-2 PLAYTEST-DBG: why the quick order did not land
		var qov: Control = hub.overlay
		var qblk := []
		var qst: Array = [hub.root]
		while not qst.is_empty():
			var qn: Node = qst.pop_back()
			for ch in qn.get_children():
				qst.append(ch)
			if qn is Control and qn != qov and (qn as Control).is_visible_in_tree() and (qn as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE 					and (qn as Control).get_global_rect().has_point(qp):
				qblk.append("%s(%s)" % [qn.name, qn.get_class()])
		print("PLAYTEST-DBG quick fb=%s qcell=%s click=%s vp=%s quick_left=%s hint=%s blockers=%s valid=%s plans=%s" % [str(fb), str(qcell), str(qp),
			str(qov.get_viewport_rect().size), str(hub.quick), str(hub.hint), str(qblk),
			Plans.validate_plan(pt._w(), 0, ClModel.quick_plan(fb, "attack", qcell)), str(Plans.plans_of(pt._w(), 0).map(func(x): return [x.id, x.formation, x.status]))])
	var p2 := _newest_plan(pt._w())
	pt._log("plan_quick_order", ok, str(p2.get("line", "")))
	await pt._wait(1.0)
	pt._log("plan_cancel_click", await pt._click_named("Plan%d_Cancel" % int(p2.get("id", -1))))
	ok = await pt._wait_until(func(): return String(Plans.get_plan(pt._w(), int(p2.get("id", -1))).get("status", "")) == "cancelled", 5.0)
	pt._log("plan_cancelled", ok)
	await pt._shot("plan61_cancelled")
	pt._log("plan_mode_exit_click", await pt._click_named("CommandModeButton"))
	pt._log("plan_mode_off", not bool(hub.active))
