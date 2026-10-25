extends RefCounted
## UI6a (G6): company and army cards (CONTRACTS_G6 section 8; vision 05 "Infantry Company (Group 3)").
## A card = header (icon, name, AI-commander badge), HP bar, a battle-status line (what the formation
## is doing, strength, losses, cohesion, refill) and a unit grid (one icon per element / leader, the
## captain and lieutenants marked). model()/army_model() are pure reads of Companies + AiCommand
## (render_snap is not needed: the HUD only reads while sim_busy() is false, CONTRACTS_G6 0.7).

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const U = preload("res://presentation/ui6/a/ui6a_util.gd")
const Companies = preload("res://sim/systems/companies.gd")
const AiCommand = preload("res://sim/systems/ai_command.gd")

const GRID_MAX := 48
const ORDER_WORDS := {"idle": "Idle", "move": "Moving", "attack_move": "Advancing", "attack": "Attacking",
	"hold": "Holding", "patrol": "Patrolling", "guard": "Guarding", "gather": "Working", "build": "Building"}


## The company whose units make up the whole selection (ids), else {}.
static func selection_company(w: SimWorld, ids: Array) -> Dictionary:
	var c := {}
	for id in ids:
		var cc := Companies.company_of(w, int(id))
		if cc.is_empty() or (not c.is_empty() and int(cc.id) != int(c.id)):
			return {}
		c = cc
	return c


## AI-commander slot driving any of these units (-1 = none): e.ai_cmd "p<slot>".
static func ai_slot(w: SimWorld, ids: Array) -> int:
	for id in ids:
		var e = w.entities.get(int(id))
		if e != null and String(e.get("ai_cmd", "")).begins_with("p"):
			return int(String(e.ai_cmd).substr(1))
	return -1


## "Attacking", "Moving", ... from the units' orders (attack wins, then the most common order).
static func activity(w: SimWorld, ids: Array) -> String:
	var counts := {}
	for id in ids:
		var e = w.entities.get(int(id))
		if e == null:
			continue
		var t := String(e.get("order", {}).get("type", "idle"))
		if t == "attack":
			return "Attacking"
		counts[t] = int(counts.get(t, 0)) + 1
	var best := "idle"
	var bn := -1
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		if int(counts[k]) > bn:
			best = String(k)
			bn = int(counts[k])
	return String(ORDER_WORDS.get(best, U.pretty(best)))


## {id, title, status, units: [{id, def, role, hp, max_hp}], hp, max_hp, count, losses, refill, army,
##  ai_slot, cohesion (0..1)} for a company dict.
static func model(w: SimWorld, c: Dictionary) -> Dictionary:
	var ids := Companies.units_of(w, c)
	var units := []
	var hp := 0.0
	var mhp := 0.0
	var inco := 0
	for id in ids:
		var e: Dictionary = w.entities[int(id)]
		units.append({"id": int(id), "def": String(e.def), "role": String(e.get("rank_role", "")),
			"hp": float(e.hp), "max_hp": float(e.max_hp)})
		hp += float(e.hp)
		mhp += float(e.max_hp)
		if Companies.in_cohesion(w, e):
			inco += 1
	var nm := String(c.get("name", ""))
	if nm == "":
		nm = String(Companies.template(w, int(c.owner), String(c.get("template", ""))).get("name", "Company"))
	var title := "%s  (Company %d)" % [nm, int(c.id)]
	var parts: Array = [activity(w, ids)]
	if int(c.get("confused_until", -1)) > w.tick:
		parts[0] = "Confused (captain lost)"
	parts.append("%d units" % ids.size())
	if int(c.get("losses", 0)) > 0:
		parts.append("losses %d" % int(c.losses))
	parts.append("cohesion %d%%" % int(round(100.0 * float(inco) / float(maxi(1, ids.size())))))
	parts.append("refill on" if bool(c.get("refill", false)) else "refill off")
	var sl := ai_slot(w, ids)
	if sl >= 0:
		parts.append("AI commander C%d" % (sl + 1))
	return {"id": int(c.id), "title": title, "status": "  |  ".join(PackedStringArray(parts)), "units": units,
		"hp": hp, "max_hp": mhp, "count": ids.size(), "losses": int(c.get("losses", 0)),
		"refill": bool(c.get("refill", false)), "army": int(c.get("army", -1)), "ai_slot": sl,
		"cohesion": float(inco) / float(maxi(1, ids.size()))}


## {id, title, status, commander, companies: [company model]} for an army dict.
static func army_model(w: SimWorld, a: Dictionary) -> Dictionary:
	var cms := []
	var n := 0
	var cs: Dictionary = w.sys_state.get("companies", {}).get("companies", {})
	for cid in a.get("companies", []):
		var c: Dictionary = cs.get(int(cid), {})
		if not c.is_empty():
			var cm := model(w, c)
			cms.append(cm)
			n += int(cm.count)
	var cmd = w.entities.get(int(a.get("commander", -1)))
	var cname := "Commander"
	if cmd != null:
		cname = String(Content.unit(String(cmd.def)).get("name", "Commander"))
	var ids: Array = []
	for cm in cms:
		for u in cm.units:
			ids.append(int(u.id))
	var status := "%s  |  %d companies, %d units  |  led by %s" % [activity(w, ids), cms.size(), n, cname]
	return {"id": int(a.id), "title": "Army %d" % int(a.id), "status": status, "commander": int(a.get("commander", -1)),
		"companies": cms}


# ------------------------------------------------------------------ widgets
## Unit grid: one icon per unit (cap GRID_MAX), captain / lieutenants outlined in amber.
static func unit_grid(units: Array, px: float = 24.0) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.name = "UnitGrid"
	flow.add_theme_constant_override("h_separation", 3)
	flow.add_theme_constant_override("v_separation", 3)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in mini(units.size(), GRID_MAX):
		var u: Dictionary = units[i]
		var cell := PanelContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lead := String(u.role) != ""
		var frac := float(u.hp) / maxf(1.0, float(u.max_hp))
		var edge := UiKit.AMBER if lead else (UiKit.GREEN if frac > 0.66 else (UiKit.YELLOW if frac > 0.33 else UiKit.RED))
		cell.add_theme_stylebox_override("panel", UiKit.flat(UiKit.INSET, edge, 2 if lead else 1, 1.0))
		var ic := U.icon_rect(String(u.def), px)
		ic.tooltip_text = "%s%s  HP %d/%d" % [String(Content.unit(String(u.def)).get("name", u.def)),
			" (%s)" % String(u.role) if lead else "", int(u.hp), int(u.max_hp)]
		cell.add_child(ic)
		flow.add_child(cell)
	if units.size() > GRID_MAX:
		flow.add_child(UiKit.label("+%d" % (units.size() - GRID_MAX), "dim"))
	return flow


## A full card for the forces panel: {box, refill: Button, select: Button, pick: CheckBox}.
static func card(cm: Dictionary, with_pick: bool) -> Dictionary:
	var box := UiKit.panel("card")
	box.name = "Company_%d" % int(cm.id)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	box.add_child(v)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	v.add_child(hb)
	if not (cm.units as Array).is_empty():
		hb.add_child(U.icon_rect(String(cm.units[0].def), 26))
	var t := UiKit.label(String(cm.title), "header")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hb.add_child(t)
	if int(cm.ai_slot) >= 0:
		var bd := UiKit.label("AI C%d" % (int(cm.ai_slot) + 1), "small")
		bd.name = "AiBadge"
		bd.add_theme_color_override("font_color", U.slot_color(int(cm.ai_slot)))
		hb.add_child(bd)
	var pick: CheckBox = null
	if with_pick:
		pick = CheckBox.new()
		pick.name = "Pick"
		pick.text = "Army"
		pick.tooltip_text = "Pick this company for a new army (2-4 companies + a Commander)"
		pick.disabled = int(cm.army) >= 0
		hb.add_child(pick)
	var bar := UiKit.bar("hp")
	bar.max_value = maxf(1.0, float(cm.max_hp))
	bar.value = float(cm.hp)
	v.add_child(bar)
	var st := UiKit.label(String(cm.status), "small")
	st.name = "StatusLine"
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.custom_minimum_size = Vector2(200, 0)
	v.add_child(st)
	v.add_child(unit_grid(cm.units, 22.0))
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 6)
	v.add_child(br)
	var sel := U.small_button(br, "Select", "Select this company's units", 80)
	var refill := U.small_button(br, "Refill: %s" % ("ON" if bool(cm.refill) else "OFF"),
		"Refill: every lost element is re-queued at the Company HQ (normal cost)", 110)
	refill.name = "Refill"
	return {"box": box, "refill": refill, "select": sel, "pick": pick}
