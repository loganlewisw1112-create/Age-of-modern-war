extends "res://presentation/ui7/card8b_base.gd"
## G7 CARDS8B (13.9c-48): ARMORY + SUIT FOUNDRY card, shown only while the player has the facility's Suit Foundry
## (cn_armory part) selected. Owner picks: loadout presets per team role, suit build & repair queue (rush for more
## cost), weapon upgrades (AP / incendiary rounds, optics, suppressors, heavier plates; LETHAL8 round model).
##   ROLE (Sh+T)  next team role (strike / tactical)     PRESET (Sh+L)  next loadout preset for that role (c8b_preset)
##   SUIT (Sh+S)  next suit role                         BUILD (Sh+B)   queue that suit (c8b_suit_build)
##   RUSH (Sh+R)  rush the head suit (c8b_suit_rush)     REPAIR (Sh+E)  damaged suits to the bay (c8b_suit_repair)
##   UPG (Sh+I)   next weapon upgrade                    RESEARCH (Sh+U) research it (c8b_upgrade)
## Hook (ORCH, presentation/hud/hud.gd, after the lpreserve_card attach line):
##   preload("res://presentation/ui7/armory_card8.gd").attach(self, left)

var role_i := 0
var suit_i := 0
var up_i := 0
var _pre: Label
var _queue: Label
var _rep: Label
var _up: Label


static func attach(h, left_stack: Control) -> Control:
	var c = (load("res://presentation/ui7/armory_card8.gd") as GDScript).new()
	c._setup(h, left_stack)
	return c


func defaults() -> Dictionary:
	return {"arm8b_role": ["SHIFT+T", "Next team role"], "arm8b_preset": ["SHIFT+L", "Next loadout preset"],
		"arm8b_suit_role": ["SHIFT+S", "Next suit role"], "arm8b_build": ["SHIFT+B", "Build suit"],
		"arm8b_rush": ["SHIFT+R", "Rush suit"], "arm8b_repair": ["SHIFT+E", "Repair damaged suits"],
		"arm8b_up_pick": ["SHIFT+I", "Next weapon upgrade"], "arm8b_upgrade": ["SHIFT+U", "Research upgrade"]}


func _title() -> String:
	return "ARMORY + SUIT FOUNDRY"


func _ready() -> void:
	_base_ready("ArmoryCard8")
	_pre = _line("Presets")
	_new_grid()
	_mk("arm8b_role", "RoleButton", "ROLE", "Pick the team role whose loadout preset you set.", _on_role)
	_mk("arm8b_preset", "PresetButton", "PRESET", "Next loadout preset for this role; teams pick it up when they rearm in their garage.", _on_preset, _preset_cmd)
	_queue = _line("SuitQueue")
	_new_grid()
	_mk("arm8b_suit_role", "SuitRoleButton", "SUIT", "Pick the armoured suit role to build.", _on_suit_role)
	_mk("arm8b_build", "BuildButton", "BUILD", "Queue this armoured suit at the Suit Foundry.", _on_build, _build_cmd)
	_mk("arm8b_rush", "RushButton", "RUSH", "Rush the suit in production (extra cost).", _on_rush, func(): return {"type": "c8b_suit_rush"})
	_mk("arm8b_repair", "RepairButton", "REPAIR", "Send every damaged suit to the foundry bay for repair (credits per hp).", _on_repair, func(): return {"type": "c8b_suit_repair", "unit_id": -1})
	_rep = _line("SuitRepair")
	_up = _line("Upgrades")
	_new_grid()
	_mk("arm8b_up_pick", "UpgradePickButton", "UPG", "Pick the weapon upgrade.", _on_up_pick)
	_mk("arm8b_upgrade", "ResearchButton", "RESEARCH", "Research the weapon upgrade for every counter-nanite unit (one at a time).", _on_upgrade, _up_cmd)
	visible = false


func roles() -> Array:
	return Cards8b.R().get("roles", ["strike", "tactical"])


func role() -> String:
	var r := roles()
	return String(r[role_i % r.size()]) if not r.is_empty() else "strike"


func suit_role() -> String:
	var r: Array = Cards8b.R().get("suit_roles", ["bastion"])
	return String(r[suit_i % r.size()]) if not r.is_empty() else "bastion"


func up_key() -> String:
	var r: Array = Cards8b.R().get("upgrade_order", [])
	return String(r[up_i % r.size()]) if not r.is_empty() else ""


func next_preset() -> String:
	var order: Array = Cards8b.R().get("preset_order", [])
	if order.is_empty():
		return ""
	var cur := String(last.get("presets", {}).get(role(), ""))
	var i := order.find(cur)
	return String(order[(i + 1) % order.size()])


func _preset_cmd() -> Dictionary:
	return {"type": "c8b_preset", "role": role(), "preset": next_preset()}


func _build_cmd() -> Dictionary:
	return {"type": "c8b_suit_build", "role": suit_role()}


func _up_cmd() -> Dictionary:
	return {"type": "c8b_upgrade", "key": up_key()}


func _shown(w: SimWorld, f: int) -> bool:
	if mv == null:
		return false
	var ap = Cards8b.armory_part(w, CnFac.fac(w, f))
	if ap != null:
		var sel = mv.get("selection")
		if sel != null and (sel as Array).has(int(ap.id)):
			return true
	return mv.has_method("part_selected") and bool(mv.part_selected(f, "armory"))


static func pname(k: String) -> String:
	return String(Cards8b.R().get("presets", {}).get(k, {}).get("name", "default")) if k != "" else "default"


## G7.1 H8 (CNOPS71-11): the CN kit a preset carries (rules.g71_cn.gear_presets; no preset / no row = the full kit).
static func gear_txt(k: String) -> String:
	var c = Content.rules().get("g71_cn", {})
	if not (c is Dictionary) or not (c as Dictionary).has("gear_presets"):
		return ""
	var g = (c.gear_presets as Dictionary).get(k, {}) if k != "" else {}
	if not (g is Dictionary):
		g = {}
	var bits := ["%d nanite gren." % int(g.get("gr", ((c as Dictionary).get("mission", {}) as Dictionary).get("gr_n", 4)))]
	if int(g.get("sd", 1)) > 0:
		bits.append("shield drone")
	if int(g.get("pc", 1)) > 0:
		bits.append("purge cannon")
	return " (" + ", ".join(PackedStringArray(bits)) + ")"


func _fill(w: SimWorld) -> void:
	var sm := Cards8b.armory_summary(w, fac)
	last = sm
	var pr: Dictionary = sm.get("presets", {})
	var parts := []
	for r in roles():
		parts.append("%s: %s%s" % [String(r).to_upper(), pname(String(pr.get(r, ""))), gear_txt(String(pr.get(r, "")))])
	_pre.text = "Loadouts  " + "   ".join(PackedStringArray(parts))
	var q := []
	for it in sm.get("queue", []):
		q.append("%s %s" % [String(it.name).replace(" Suit", ""), pct(float(it.progress), 1.0)])
	_queue.text = "Suits: " + (", ".join(PackedStringArray(q)) if not q.is_empty() else "queue empty")
	var dm: Array = sm.get("damaged", [])
	var nq := 0
	var worst := ""
	for d in dm:
		if bool(d.queued):
			nq += 1
		if worst == "":
			worst = "%s #%d %s" % [String(d.name).replace(" Suit", ""), int(d.id), pct(float(d.hp), float(d.max))]
	_rep.text = "Damaged suits %d (%d in repair)%s" % [dm.size(), nq, ("  " + worst) if worst != "" else ""]
	_rep.add_theme_color_override("font_color", S.AMBER if not dm.is_empty() else S.PHOS)
	var ups := []
	var U: Dictionary = Cards8b.R().get("upgrades", {})
	for k in sm.get("up", {}):
		var st := String(sm.up[k])
		var nm := String(U.get(k, {}).get("name", k))
		if st == "on":
			ups.append(nm + " ON")
		elif st == "research":
			ups.append("%s %s" % [nm, pct(float(sm.res_frac), 1.0)])
	_up.text = "Upgrades: " + (", ".join(PackedStringArray(ups)) if not ups.is_empty() else "none")
	_set_btn("arm8b_role", "ROLE " + role().to_upper(), "")
	_set_btn("arm8b_preset", "PRESET " + pname(next_preset()), why("arm8b_preset"))
	_set_btn("arm8b_suit_role", "SUIT " + suit_role().to_upper(), "")
	_set_btn("arm8b_build", "BUILD", why("arm8b_build"))
	_set_btn("arm8b_rush", "RUSH", why("arm8b_rush"))
	_set_btn("arm8b_repair", "REPAIR", why("arm8b_repair"))
	_set_btn("arm8b_up_pick", "UPG " + String(U.get(up_key(), {}).get("name", up_key())), "")
	_set_btn("arm8b_upgrade", "RESEARCH", why("arm8b_upgrade"))


func _after_local() -> void:
	var w := world()
	if w != null and fac >= 0:
		_fill(w)


func _on_role() -> void:
	role_i += 1
	_after_local()


func _on_suit_role() -> void:
	suit_i += 1
	_after_local()


func _on_up_pick() -> void:
	up_i += 1
	_after_local()


func _on_preset() -> void:
	_issue(_preset_cmd())


func _on_build() -> void:
	_issue(_build_cmd())


func _on_rush() -> void:
	_issue({"type": "c8b_suit_rush"})


func _on_repair() -> void:
	_issue({"type": "c8b_suit_repair", "unit_id": -1})


func _on_upgrade() -> void:
	_issue(_up_cmd())
