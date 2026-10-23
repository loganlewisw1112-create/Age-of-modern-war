extends RefCounted
## G2 command-card buttons (owner: agent D2), added to the G1 card by hud.gd:
##   units:    Patrol [Q], Guard [G], Formation [F] (cycles line/wedge/column; combat units only)
##   officer + units: Assign to officer
##   officer alone:   Mission panel (Secure/Hold/Attack/Patrol route, Risk cycle, Cancel mission)
##   engineers: Repair [R]
## Every action goes through match_view.issue() or arms a MatchView.g2 order mode.

const G2 = preload("res://presentation/view/g2_data.gd")

var hud
var risk_idx := 1               # index into G2.RISKS (medium)
var _recs: Array = []           # {btn, kind, ...} added by this module for the current card
var _ids: Array = []
var _combat: Array = []
var _officer := -1
var _others: Array = []


func _mv():
	return hud.mv


func _ent(id: int):
	return hud._world().entities.get(id)


## Called by hud._add_unit_buttons after Stop/Hold. ids are the selected own units.
func add_buttons(mode: String, ids: Array) -> void:
	_recs.clear()
	_ids = ids.duplicate()
	_combat.clear()
	_others.clear()
	_officer = -1
	var engineers: Array = []
	for id in ids:
		var e = _ent(int(id))
		if e == null:
			continue
		if G2.is_engineer(e):
			engineers.append(int(id))
		elif G2.is_officer(e):
			if _officer < 0:
				_officer = int(id)
			else:
				_others.append(int(id))
		else:
			_combat.append(int(id))
			_others.append(int(id))
	if mode == "engineer":
		var rb = _btn("Repair", "salvage", "R", "repair", "Engineers repair an own damaged vehicle or building, or the ruined bridge.\nRight-click a damaged target does the same.")
		rb.btn.pressed.connect(func(): _mv().g2.arm("repair", {"unit_ids": engineers}))
		return
	if _officer >= 0 and _others.is_empty():
		hud._card_title.text = "OFFICER  -  MISSION   (pick a mission, then click the target)"
		for m in G2.MISSIONS:
			var r = _btn(G2.mission_name(String(m)), "", "", "mission", _mission_tip(String(m)))
			r.btn.pressed.connect(_arm_mission.bind(String(m)))
		var rk = _btn("Risk: " + G2.RISKS[risk_idx], "click to cycle", "", "risk", "Withdraw when losses exceed: low 25%, medium 50%, high 75%.")
		rk.btn.pressed.connect(_cycle_risk)
		var cm = _btn("Cancel mission", "", "", "cancel_mission", "The group stops its mission and idles.")
		cm.btn.pressed.connect(func(): hud._issue({"type": "cancel_mission", "officer_id": _officer}))
		return
	if _officer >= 0:
		var ab = _btn("Assign to officer", "%d units" % _others.size(), "", "assign", "Put the selected units under this officer's command.")
		ab.btn.pressed.connect(func(): hud._issue({"type": "assign_officer", "officer_id": _officer, "unit_ids": _others.duplicate()}))
	if _combat.is_empty() and _others.is_empty():
		return
	var orders: Array = _others if not _others.is_empty() else _combat
	var pb = _btn("Patrol", "click points", "Q", "patrol", "Click waypoints (Shift+click to add more); right-click or Enter to finish.")
	pb.btn.pressed.connect(func(): _mv().g2.arm("patrol", {"unit_ids": orders}))
	var gb = _btn("Guard", "click a friendly", "G", "guard", "Follow and protect a friendly unit or building; engage enemies in sight.")
	gb.btn.pressed.connect(func(): _mv().g2.arm("guard", {"unit_ids": orders}))
	if not _combat.is_empty():
		var fb = _btn("Formation", "line", "F", "formation", "Cycle formation: line, wedge, column.")
		fb.btn.pressed.connect(_cycle_formation)


func _btn(title: String, sub: String, hotkey: String, kind: String, tip: String) -> Dictionary:
	var b: Button = hud._card_button(title, sub, hotkey, "")
	var rec := {"btn": b, "kind": "g2", "g2": kind, "tip": tip}
	hud._card_buttons.append(rec)
	_recs.append(rec)
	hud._register_hotkey(hotkey, b)
	return rec


func _mission_tip(m: String) -> String:
	match m:
		"secure_point": return "Take a point and hold it: no visible enemies within the radius, most of the group inside."
		"hold_zone": return "Defend a zone around the target."
		"attack_area": return "Attack-move into the area and clear it."
		"patrol_route": return "Shift+click route points, then Enter. The group loops the route."
	return ""


func _arm_mission(m: String) -> void:
	_mv().g2.arm("mission", {"mission": m, "officer_id": _officer, "risk": G2.RISKS[risk_idx]})


func _cycle_risk() -> void:
	risk_idx = (risk_idx + 1) % G2.RISKS.size()
	_mv().g2.risk = G2.RISKS[risk_idx]


func _current_formation() -> String:
	for id in _combat:
		var e = _ent(int(id))
		if e != null:
			return String(e.get("formation", "line"))
	return "line"


func _cycle_formation() -> void:
	var cur := _current_formation()
	var nxt: String = G2.FORMATIONS[(G2.FORMATIONS.find(cur) + 1) % G2.FORMATIONS.size()]
	hud._issue({"type": "set_formation", "unit_ids": _combat.duplicate(), "formation": nxt})


## Refresh labels / disabled state (called from hud._update_card_state every refresh).
func update_state(w: SimWorld) -> void:
	var pf: int = hud._pf()
	for rec in _recs:
		var b: Button = rec.btn
		if not is_instance_valid(b):
			continue
		var reason := ""
		match String(rec.g2):
			"formation":
				b.text = "[F] Formation\n%s" % _current_formation()
				reason = w.preview_command({"type": "set_formation", "issuer": pf, "unit_ids": _combat, "formation": "line"})
			"risk":
				b.text = "Risk: %s\nclick to cycle" % String(G2.RISKS[risk_idx]).to_upper()
			"assign":
				reason = w.preview_command({"type": "assign_officer", "issuer": pf, "officer_id": _officer, "unit_ids": _others})
			"cancel_mission":
				if G2.mission_type(G2.group_of(w, _officer)) == "":
					reason = "This officer has no mission."
		rec["reason"] = reason
		b.disabled = reason != ""
		b.tooltip_text = String(rec.tip) + ("\nUnavailable: " + reason if reason != "" else "")


## Hint line for the command card while a G2 order mode is armed (or a context hint flashes).
func hint() -> String:
	var mv = _mv()
	if mv == null or mv.get("g2") == null:
		return ""
	return mv.g2.status_text()


## Fit cards with more than 8 buttons (engineer build card + Repair) into two rows of five
## (the card widens; the inspector column is SIZE_EXPAND_FILL and gives up the space).
func compact(grid: GridContainer) -> void:
	grid.columns = 5 if grid.get_child_count() > 8 else 4
