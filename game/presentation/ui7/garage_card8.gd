extends "res://presentation/ui7/card8b_base.gd"
## G7 CARDS8B (13.9c-48): GARAGES / WORKSHOP / DECON WASH card, shown only while the player has a facility garage or the
## wash selected (part "garage": a click on a garage bay or the decon wash, match_view._select_facility_part_at).
## Owner picks: vehicle roster + repair (damage, fuel, ammo, repair priority), launch / recall convoy, upgrade vehicles
## (armour kit, dome shield, rocket pod, engines), wash / decon control (force decon, skip under fire, who is contaminated).
##   TEAM (Sh+T)     next vehicle team                  REPAIR (Sh+R)  priority repair on / off (c8b_veh_repair)
##   KIT (Sh+I)      next vehicle upgrade                FIT (Sh+U)     fit it to the team's APCs (c8b_veh_upgrade)
##   CONVOY (Sh+V)   team in / out of the convoy         LAUNCH (Sh+C)  click a destination: convoy rolls out (c8b_convoy)
##   RECALL (Sh+H)   every team out comes home (c8b_recall)
##   DECON (Sh+D)    contaminated units to the wash (c8b_decon_force)   SKIP WASH (Sh+W) under fire on / off (c8b_decon_skip)
## Hook (ORCH, presentation/hud/hud.gd, after the lpreserve_card attach line):
##   preload("res://presentation/ui7/garage_card8.gd").attach(self, left)

var team_i := 0
var kit_i := 0
var convoy: Array = []                  # team ids picked for the next convoy (card-local, not sim state)
var picking := false                    # LAUNCH armed: the next map click is the destination
var _roster: Label
var _team: Label
var _conv: Label
var _decon: Label


static func attach(h, left_stack: Control) -> Control:
	var c = (load("res://presentation/ui7/garage_card8.gd") as GDScript).new()
	c._setup(h, left_stack)
	return c


func defaults() -> Dictionary:
	return {"gar8b_team": ["SHIFT+T", "Next vehicle team"], "gar8b_repair": ["SHIFT+R", "Priority repair"],
		"gar8b_up_pick": ["SHIFT+I", "Next vehicle upgrade"], "gar8b_upgrade": ["SHIFT+U", "Fit vehicle upgrade"],
		"gar8b_pick": ["SHIFT+V", "Team in / out of the convoy"], "gar8b_convoy": ["SHIFT+C", "Launch convoy"],
		"gar8b_recall": ["SHIFT+H", "Recall all home"], "gar8b_decon": ["SHIFT+D", "Force decon"],
		"gar8b_skip": ["SHIFT+W", "Skip wash under fire"]}


func _title() -> String:
	return "GARAGES + WORKSHOP + WASH"


func _ready() -> void:
	_base_ready("GarageCard8")
	_roster = _line("Roster")
	_team = _line("TeamLine")
	_new_grid()
	_mk("gar8b_team", "TeamButton", "TEAM", "Pick the vehicle team.", _on_team)
	_mk("gar8b_repair", "RepairButton", "REPAIR", "Workshop crew repairs this team first (credits per hp); press again to take it off the queue.", _on_repair, func(): return {"type": "c8b_veh_repair", "team": team_id()})
	_mk("gar8b_up_pick", "KitPickButton", "KIT", "Pick the vehicle upgrade.", _on_kit)
	_mk("gar8b_upgrade", "FitButton", "FIT", "Fit the upgrade to every APC of this team (parked in its garage).", _on_fit, func(): return {"type": "c8b_veh_upgrade", "team": team_id(), "key": kit_key()})
	_conv = _line("ConvoyLine")
	_new_grid()
	_mk("gar8b_pick", "ConvoyPickButton", "CONVOY +", "Add / remove this team in the convoy (none picked = every parked team).", _on_pick)
	_mk("gar8b_convoy", "LaunchButton", "LAUNCH", "Then click the destination on the map: the convoy rolls out through the gate.", _on_launch, func(): return {"type": "c8b_convoy", "teams": convoy.duplicate(), "target": [0.0, 0.0]})
	_mk("gar8b_recall", "RecallButton", "RECALL ALL", "Every team out drives home through the decon wash.", _on_recall, func(): return {"type": "c8b_recall"})
	_decon = _line("DeconLine")
	_new_grid()
	_mk("gar8b_decon", "DeconButton", "DECON", "Contaminated soldiers walk to the wash; contaminated teams in the field return.", _on_decon, func(): return {"type": "c8b_decon_force"})
	_mk("gar8b_skip", "SkipButton", "SKIP WASH", "Returning vehicles skip the wash while the base is under fire.", _on_skip, func(): return {"type": "c8b_decon_skip", "on": not bool(last.get("skip", false))})
	visible = false


func _shown(_w: SimWorld, f: int) -> bool:
	return mv != null and mv.has_method("part_selected") and (bool(mv.part_selected(f, "garage")))


func teams_l() -> Array:
	return last.get("teams", [])


func cur_team() -> Dictionary:
	var tl := teams_l()
	return tl[team_i % tl.size()] if not tl.is_empty() else {}


func team_id() -> int:
	return int(cur_team().get("id", -1))


func kit_key() -> String:
	var r: Array = Cards8b.R().get("veh_upgrade_order", [])
	return String(r[kit_i % r.size()]) if not r.is_empty() else ""


static func phase_text(p: String) -> String:
	return {"garage": "parked", "out": "out", "returning": "at the wash", "to_pad": "to pad", "loading": "loading",
		"to_gate": "rolling out", "to_inner": "coming in", "to_garage": "to garage"}.get(p, p)


func _fill(w: SimWorld) -> void:
	var sm := Cards8b.garage_summary(w, fac)
	last = sm
	var tl := teams_l()
	var parked := 0
	var out := 0
	for T in tl:
		if String(T.phase) == "garage":
			parked += 1
		elif String(T.phase) == "out":
			out += 1
	var vq: Array = sm.get("vq", [])
	_roster.text = "Teams %d: %d parked, %d out   repair queue %s" % [tl.size(), parked, out,
		", ".join(PackedStringArray(vq.map(func(x): return "T%d" % int(x)))) if not vq.is_empty() else "-"]
	var T := cur_team()
	if T.is_empty():
		_team.text = "No vehicle team yet."
	else:
		var al := []
		for a in T.apcs:
			var s := "APC %s hp %s fuel %s" % [str(int(a.id)), pct(float(a.hp), float(a.max)), pct(float(a.fuel), float(a.fuel_max))]
			if float(a.ammo_max) > 0.0:
				s += " ammo " + pct(float(a.ammo), float(a.ammo_max))
			if int(a.rockets) > 0:
				s += " rkt %d" % int(a.rockets)
			if not (a.ups as Array).is_empty():
				s += " [" + ",".join(PackedStringArray((a.ups as Array).map(func(x): return String(x).replace("_", " ")))) + "]"
			al.append(s)
		_team.text = "T%d %s - %s\n%s" % [int(T.id), String(T.role).to_upper(), phase_text(String(T.phase)), "\n".join(PackedStringArray(al))]
	var keep := []
	for tid in convoy:
		for t2 in tl:
			if int(t2.id) == int(tid):
				keep.append(int(tid))
	convoy = keep
	_conv.text = "Convoy: " + (", ".join(PackedStringArray(convoy.map(func(x): return "T%d" % int(x)))) if not convoy.is_empty() else "all parked teams") \
		+ ("   click the destination..." if picking else "")
	var cl: Array = sm.get("contaminated", [])
	var names := []
	for c in cl.slice(0, 3):
		names.append("%s #%d" % [String(c.name), int(c.id)])
	_decon.text = "Wash: %s   contaminated %d%s" % [String(sm.get("state", "secure")).replace("_", " ").to_upper(), cl.size(),
		(": " + ", ".join(PackedStringArray(names))) if not names.is_empty() else ""]
	_decon.add_theme_color_override("font_color", S.AMBER if not cl.is_empty() else S.PHOS)
	var V: Dictionary = Cards8b.R().get("veh_upgrades", {})
	_set_btn("gar8b_team", "TEAM T%d" % team_id() if team_id() >= 0 else "TEAM", "" if not tl.is_empty() else "No vehicle team yet.")
	_set_btn("gar8b_repair", "UNQUEUE" if vq.has(team_id()) else "REPAIR", why("gar8b_repair"))
	_set_btn("gar8b_up_pick", "KIT " + String(V.get(kit_key(), {}).get("name", kit_key())), "")
	_set_btn("gar8b_upgrade", "FIT", why("gar8b_upgrade"))
	_set_btn("gar8b_pick", ("CONVOY -" if convoy.has(team_id()) else "CONVOY +"), "" if team_id() >= 0 else "No vehicle team yet.")
	var lw := why("gar8b_convoy")
	_set_btn("gar8b_convoy", "PICK POINT" if picking else "LAUNCH", "" if lw == "Pick a destination." else lw)
	_set_btn("gar8b_recall", "RECALL ALL", why("gar8b_recall"))
	_set_btn("gar8b_decon", "DECON", why("gar8b_decon"))
	_set_btn("gar8b_skip", "SKIP WASH ON" if bool(sm.get("skip", false)) else "SKIP WASH OFF", why("gar8b_skip"))


func _after_local() -> void:
	var w := world()
	if w != null and fac >= 0:
		_fill(w)


func _on_team() -> void:
	team_i += 1
	_after_local()


func _on_kit() -> void:
	kit_i += 1
	_after_local()


func _on_pick() -> void:
	var t := team_id()
	if t < 0:
		return
	if convoy.has(t):
		convoy.erase(t)
	else:
		convoy.append(t)
	_after_local()


func _on_repair() -> void:
	_issue({"type": "c8b_veh_repair", "team": team_id()})


func _on_fit() -> void:
	_issue({"type": "c8b_veh_upgrade", "team": team_id(), "key": kit_key()})


## LAUNCH arms a map point pick (MatchView.begin_point_pick); the click issues the convoy order.
func _on_launch() -> void:
	if mv != null and mv.has_method("begin_point_pick"):
		picking = true
		mv.begin_point_pick(launch_to)
		_after_local()


func launch_to(p: Vector2) -> void:
	picking = false
	_issue({"type": "c8b_convoy", "teams": convoy.duplicate(), "target": [p.x, p.y]})
	convoy = []


func _on_recall() -> void:
	_issue({"type": "c8b_recall"})


func _on_decon() -> void:
	_issue({"type": "c8b_decon_force"})


func _on_skip() -> void:
	_issue({"type": "c8b_decon_skip", "on": not bool(last.get("skip", false))})
