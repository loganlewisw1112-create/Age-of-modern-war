extends RefCounted
## G6.1 playtest flow "gen61" (owner: GEN61): give a company + a budget to an auto general from the AI
## Commanders panel, run at 3x, then shots of the panel log and the battle.

const Companies = preload("res://sim/systems/companies.gd")
const AiCommand = preload("res://sim/systems/ai_command.gd")


func _slot0(pt) -> Dictionary:
	for s in AiCommand.slots(pt._w(), 0):
		if int(s.get("slot", -1)) == 0:
			return s
	return {}


func run(pt) -> void:
	var hq: Dictionary = await pt._g6_company_hq()
	if hq.is_empty() or not await pt._g6_train_companies(hq, 1):
		pt._log("gen_company_trained", false, "no Company HQ / company")
		return
	var c: Dictionary = Companies.companies_of(pt._w(), 0)[0]
	pt._log("gen_panel_button_click", await pt._click_named("CommandersButton"))
	var cp = pt._g6_panel("CommandersPanel")
	var s1 = cp.find_child("Slot1", true, false) if cp != null else null
	if s1 == null:
		pt._log("gen_slot1", false)
		return
	var cname := String(c.get("name", "company"))
	pt._log("gen_target_click", await pt._g6_option(s1, "Target", cname) or await pt._g6_option(s1, "Target", "Company"), cname)
	pt._log("gen_objective_auto", await pt._g6_option(s1, "Objective", "Auto"))
	pt._log("gen_budget_click", await pt._g6_option(s1, "Budget", "2000"))
	await pt._shot("gen61_panel_setup")
	pt._log("gen_assign_click", await pt._g6_click_in(s1, "Assign"))
	var on: bool = await pt._wait_until(func(): return String((_slot0(pt).get("objective", {}) as Dictionary).get("type", "")) == "auto", 10.0)
	var sl := _slot0(pt)
	var bud: Dictionary = (sl.get("general", {}) as Dictionary).get("budget", {})
	pt._log("gen_assigned_auto", on, "units=%d budget=%s" % [(sl.get("units", []) as Array).size(), str(bud)])
	pt._log("gen_budget_granted", int(bud.get("credits", 0)) >= 2000, str(bud))
	await pt._g6_close(cp)
	pt._mv().speed = 3.0
	var acted: bool = await pt._wait_until(func():
		var g: Dictionary = _slot0(pt).get("general", {})
		return String(g.get("op", "")) != "" or not (g.get("ops", {}) as Dictionary).is_empty(), 60.0)
	await pt._wait(20.0)
	var g: Dictionary = _slot0(pt).get("general", {})
	pt._log("gen_general_acts", acted, "op=%s phase=%s ops=%s" % [str(g.get("op")), str(g.get("phase")), str(g.get("ops"))])
	await pt._shot("gen61_battle")
	pt._log("gen_panel_button_click_2", await pt._click_named("CommandersButton"))
	cp = pt._g6_panel("CommandersPanel")
	s1 = cp.find_child("Slot1", true, false) if cp != null else null
	var lbl = s1.find_child("GeneralLog", true, false) if s1 != null else null
	var txt := String(lbl.text) if lbl != null else ""
	pt._log("gen_panel_log", lbl != null and bool(lbl.visible) and txt.contains("Op") , txt.left(200).replace("\n", " / "))
	await pt._shot("gen61_panel_log")
	await pt._g6_close(cp)
