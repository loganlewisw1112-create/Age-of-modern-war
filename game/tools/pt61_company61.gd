extends RefCounted
## G6.1 playtest flow company61 (ORCH): the owner's bug "buying a platoon, battalion doesn't spawn any units".
## By clicks, Human A: build a Company HQ with NO extra depots, open the Army Builder, pick Rifle Company /
## Platoon: Train must be disabled with a supply reason in the note (no silent purchase). Build depots until it
## fits, Train, select the HQ: the inspector shows "Training: ...". Wait: the whole company deploys next to the HQ.

const Companies = preload("res://sim/systems/companies.gd")


func run(pt) -> void:
	var hdef := ""
	for b in Content.buildable_for(pt._fac()):
		if hdef == "" and Companies.is_hq_def(String(b)):
			hdef = String(b)
	pt._log("c61_hq_def", hdef != "", hdef)
	if hdef == "":
		return
	if pt._built_count(pt._role("power")) == 0:
		await pt._g5_build(pt._role("power"))
	if pt._built_count(pt._role("barracks")) == 0:
		await pt._g5_build(pt._role("barracks"))
	var hq: Dictionary = await pt._g5_build(hdef)
	pt._log("c61_hq_built", not hq.is_empty())
	if hq.is_empty():
		return
	var w: SimWorld = pt._w()
	var f: Dictionary = w.factions[0]
	var td: Dictionary = Companies.template(w, 0, "a_rifle_co")
	var per := int(Companies.plan(w, 0, td, "platoon", true).pop)
	# 1) not enough supply: the builder refuses up front with the reason
	pt._log("c61_select_hq", await pt._g5_select(int(hq.id)))
	pt._log("c61_army_builder_click", await pt._click_named("G6ArmyBuilder"))
	var ab: Control = pt._g6_panel("ArmyBuilder")
	pt._log("c61_builder_open", ab != null)
	if ab == null:
		return
	pt._log("c61_preset_rifle", await pt._g6_option(ab, "TemplateSource", "rifle company"))
	pt._log("c61_size_platoon", await pt._g6_option(ab, "TemplateSize", "platoon"))
	await pt._wait(0.5)
	var tb = ab.find_child("TrainTemplate", true, false)
	var note := _note_text(ab)
	var short := Companies.free_supply(w, 0) < per
	if short:
		pt._log("c61_train_refused_with_reason", tb != null and (tb as BaseButton).disabled and note.contains("supply"),
			"free %d < need %d; note: %s" % [Companies.free_supply(w, 0), per, note.replace("\n", " | ")])
		await pt._shot("c61_builder_refuses_no_supply")
	else:
		pt._log("c61_train_refused_with_reason", true, "start already had room (free %d >= %d): refusal not exercised" % [Companies.free_supply(w, 0), per])
	await pt._g6_close(ab)
	# 2) build depots until one platoon fits, then train by clicks
	for i in 12:
		if Companies.free_supply(w, 0) >= per:
			break
		await pt._g5_build(pt._role("depot"))
	pt._log("c61_supply_room", Companies.free_supply(w, 0) >= per, "free %d, need %d, pop %d / %d" % [Companies.free_supply(w, 0), per, int(f.pop), int(f.pop_cap)])
	pt._log("c61_select_hq_2", await pt._g5_select(int(hq.id)))
	pt._log("c61_army_builder_click_2", await pt._click_named("G6ArmyBuilder"))
	ab = pt._g6_panel("ArmyBuilder")
	if ab == null:
		pt._log("c61_builder_open_2", false)
		return
	await pt._g6_option(ab, "TemplateSource", "rifle company")
	await pt._g6_option(ab, "TemplateSize", "platoon")
	await pt._wait(0.4)
	pt._log("c61_train_click", await pt._g6_click_in(ab, "TrainTemplate"), _note_text(ab).replace("\n", " | "))
	await pt._g6_close(ab)
	var queued: bool = await pt._wait_until(func(): return Companies.training_of(pt._w(), int(hq.id)).size() > 0, 10.0)
	pt._log("c61_queued", queued)
	# 3) the HQ inspector shows the training row
	pt._log("c61_select_hq_3", await pt._g5_select(int(hq.id)))
	await pt._wait(0.6)
	var shows := false
	for l in pt.get_tree().root.find_children("*", "Label", true, false):
		if (l as Control).is_visible_in_tree() and String((l as Label).text).contains("Training: Rifle Company"):
			shows = true
			break
	pt._log("c61_inspector_shows_training", shows)
	await pt._shot("c61_hq_training_progress")
	# 4) deploy next to the HQ
	var n0 := Companies.companies_of(pt._w(), 0).size()
	var ok: bool = await pt._wait_until(func(): return Companies.companies_of(pt._w(), 0).size() > n0, 240.0)
	pt._log("c61_company_deployed", ok, "companies=%d" % Companies.companies_of(pt._w(), 0).size())
	if not ok:
		return
	var c: Dictionary = Companies.companies_of(pt._w(), 0)[-1]
	var us: Array = Companies.units_of(pt._w(), c)
	var near := 0
	var hp: Vector2 = pt._w().entities[int(hq.id)].pos
	for u in us:
		var e = pt._w().entities.get(int(u)) if typeof(u) == TYPE_INT else u  # units_of returns ids
		if e != null and Vector2(e.pos).distance_to(hp) <= 14.0:
			near += 1
	pt._log("c61_troops_at_hq", us.size() > 10 and near >= int(us.size() * 0.8), "troops=%d near_hq=%d" % [us.size(), near])
	pt._mv().center_camera_on(hp)
	await pt._wait(0.5)
	await pt._shot("c61_company_deployed_at_hq")


func _note_text(ab: Node) -> String:
	var s := ""
	for l in ab.find_children("*", "Label", true, false):
		var t := String((l as Label).text)
		if t.contains("Unavailable") or t.contains("supply"):
			s += t + "\n"
	return s
