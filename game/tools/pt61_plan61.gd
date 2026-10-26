extends RefCounted
## G6.1 playtest flow "plan61" (owner: PLAN61): enter Command mode, draw an axis, two phase lines and an
## objective for a company with real mouse input, issue the plan, watch it advance (shots at each phase
## line, Go signals from the plan card), then a quick officer order for a second company and cancel it.

const Plans = preload("res://sim/systems/plans.gd")
const Companies = preload("res://sim/systems/companies.gd")


func _hub(pt):
	var h = pt.main.get("hud")
	return h.get("cmd_layer") if h != null else null


## Viewport point of world cell c through the overlay's own projection.
func _vp(hub, c: Vector2i) -> Vector2:
	var ov: Control = hub.overlay
	return ov.get_global_transform_with_canvas() * ov.to_local_pt(Vector2(c) + Vector2(0.5, 0.5))


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
	await pt._click(_vp(hub, capc))
	await pt._wait(0.3)
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
	await pt._click(_vp(hub, _cell(w, c0 + dir * 19.0)))
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
	pt._mv().center_camera_on(cb)
	await pt._wait(0.4)
	await pt._click(_vp(hub, _cell(pt._w(), cb + dir * 10.0)))
	ok = await pt._wait_until(func(): return _newest_plan(pt._w()).get("formation", {}) == fb, 5.0)
	var p2 := _newest_plan(pt._w())
	pt._log("plan_quick_order", ok, str(p2.get("line", "")))
	await pt._wait(1.0)
	pt._log("plan_cancel_click", await pt._click_named("Plan%d_Cancel" % int(p2.get("id", -1))))
	ok = await pt._wait_until(func(): return String(Plans.get_plan(pt._w(), int(p2.get("id", -1))).get("status", "")) == "cancelled", 5.0)
	pt._log("plan_cancelled", ok)
	await pt._shot("plan61_cancelled")
	pt._log("plan_mode_exit_click", await pt._click_named("CommandModeButton"))
	pt._log("plan_mode_off", not bool(hub.active))
