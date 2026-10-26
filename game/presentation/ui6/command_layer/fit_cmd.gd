extends RefCounted
## G6.1 command layer fit-test screens (owner: PLAN61), for presentation/ui5/kit/fit_screens.gd:
##   cmd61_mode  = Command mode on, a draft plan for the first company on the card;
##   cmd61_plans = Command mode on with two issued plans listed on the card (longest status lines).
## Reuses UI6a's g6_world (two trained companies, an army) and HUD builder.

const FitUi6a = preload("res://presentation/ui6/a/fit_ui6a.gd")
const Companies = preload("res://sim/systems/companies.gd")

const NAMES := ["cmd61_mode", "cmd61_plans"]


static func _plan(cid: int, kind: String = "company") -> Dictionary:
	return {"formation": {"kind": kind, "id": cid}, "intent": "attack", "objectives": [[40, 30]], "axis": [],
		"phase_lines": [{"points": [[30, 20], [36, 26]]}, {"points": [[34, 22], [40, 28]]}], "timing": {"mode": "signal"}}


static func build(nm: String, vp: SubViewport, sc: float, tree: SceneTree) -> bool:
	if not NAMES.has(nm):
		return false
	var w: SimWorld = FitUi6a.g6_world()
	var pair: Array = FitUi6a._hud(vp, sc, w)
	var hud = pair[1]
	await tree.process_frame
	var cl = hud.get("cmd_layer")
	if cl == null:
		return false
	var cos := Companies.companies_of(w, 0)
	if nm == "cmd61_plans":
		for c in cos:
			w.submit({"type": "issue_plan", "issuer": 0, "plan": _plan(int(c.id))})
		w.step()
	cl.set_active(true)
	cl.update(w, 0)
	if nm == "cmd61_mode" and not cos.is_empty():
		cl.model.begin_draft({"kind": "company", "id": int(cos[0].id)})
		cl.model.add_phase_line(Vector2i(30, 20), Vector2i(36, 26))
	await tree.process_frame
	hud._refresh()
	await tree.process_frame
	cl.update(w, 0)
	return true
