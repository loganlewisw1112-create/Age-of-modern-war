extends RefCounted
## G2 command-card buttons (owner: agent D2), added to the G1 card by hud.gd:
##   units:    Patrol [Q], Guard [G], Formation [F] (cycles line/wedge/column; combat units only)
##   officer + units: Assign to officer
##   officer alone:   Mission panel (Secure/Hold/Attack/Patrol route, Risk cycle, Cancel mission)
##   engineers: Repair [R]
## G6.1 (SQUAD61): Formation [F] cycles all 8 formations (Orders.PLAYER_FORMATIONS); new buttons Formations [;] (page:
## one button per formation + Group pace on/off), Stance [,] (page: aggressive / defensive / hold fire /
## hold position / default + Teams panel), Regroup [/]. Keys come from Hotkeys (rebindable, group squad61).
## Every action goes through match_view.issue() or arms a MatchView.g2 order mode.

const G2 = preload("res://presentation/view/g2_data.gd")
const Orders = preload("res://sim/systems/orders.gd")
const Hotkeys = preload("res://presentation/ui5/panels/hotkeys.gd")
const FORM_NAMES := {"line": "Line", "wedge": "Wedge", "column": "Column", "box": "Box", "echelon_left": "Echelon left",
	"echelon_right": "Echelon right", "file": "File", "spread": "Spread (skirmish)"}
const FORM_KEYS := {"line": "L", "wedge": "E", "column": "C", "box": "B", "echelon_left": "J", "echelon_right": "K",
	"file": "I", "spread": "X"}
const STANCES := [["aggressive", "Aggressive", "Z", "Pursue and engage at max range."],
	["defensive", "Defensive", "X", "Hold the area, return fire, chase only a short way."],
	["hold_fire", "Hold fire", "C", "Only shoot back when shot at."],
	["hold_position", "Hold position", "V", "Never move; fire at enemies in range."],
	["default", "Default", "B", "Normal behaviour (engage what comes into sight)."]]
const STANCE_NAME := {"": "Default", "aggressive": "Aggressive", "defensive": "Defensive", "hold_fire": "Hold fire",
	"hold_position": "Hold position"}

var hud
var risk_idx := 1               # index into G2.RISKS (medium)
var _recs: Array = []           # {btn, kind, ...} added by this module for the current card
var _ids: Array = []
var _combat: Array = []
var _officer := -1
var _others: Array = []
var page := ""                 # G6.1: "" | "formation" | "stance" (a sub-card for the selection in _page_ids)
var _page_ids: Array = []
var _bearers: Array = []        # G6.1 (INTEG61): selected ammo bearers (Join / Leave squad)
const AB = preload("res://sim/systems/ammo_bearer.gd")


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
	_bearers = []
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
		# G3a (ORCH): a mixed selection with builders still lets the officer take the combat units
		if _officer >= 0 and not _others.is_empty():
			var ab2 = _btn("Assign to officer", "%d units" % _others.size(), "", "assign", "Put the selected combat units under this officer's command (builders keep working).")
			ab2.btn.pressed.connect(func(): hud._issue({"type": "assign_officer", "officer_id": _officer, "unit_ids": _others.duplicate()}))
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
		var fb = _btn("Formation", "line", "F", "formation", "Cycle formation: line, wedge, column, box, echelon left/right, file, spread.")
		fb.btn.pressed.connect(_cycle_formation)
		# G6.1 (SQUAD61)
		var fp = _btn2("Formations", "pick one", "formations_page", "formations_page", "One button per formation, and Group pace (move at the slowest unit's speed).")
		fp.btn.pressed.connect(_open_page.bind("formation"))
		var sp = _btn2("Stance", "default", "stance_page", "stance", "Aggressive, defensive, hold fire, hold position.")
		sp.btn.pressed.connect(_open_page.bind("stance"))
		var rg = _btn2("Regroup", "on leader", "regroup", "regroup", "Selected squads and platoons reform on their leader.")
		rg.btn.pressed.connect(func(): hud._issue({"type": "regroup", "unit_ids": _combat.duplicate()}))
	# G6.1 (INTEG61, BEARER61 CR seq 332): ammo bearer card. Join arms a click on an own squad member;
	# right-clicking one with only bearers selected does the same (G2Input.smart).
	_bearers = _ids.filter(func(x): return AB.is_bearer(_ent(int(x))))
	if not _bearers.is_empty():
		var jb = _btn2("Join squad", "click a squad", "bearer_join", "bearer_join", "Click an own squad member: the selected ammo bearers follow that squad and restock it.\nRight-click a squad member does the same.")
		jb.btn.pressed.connect(func(): _mv().g2.arm("bearer_join", {"unit_ids": _bearers.duplicate()}))
		var lb = _btn2("Leave squad", "", "bearer_leave", "bearer_leave", "The selected ammo bearers leave their squad.")
		lb.btn.pressed.connect(func(): hud._issue({"type": "leave_squad", "unit_ids": _bearers.duplicate()}))


## G6.1: a card button whose key comes from the Hotkeys table (badge shows the printable character).
func _btn2(title: String, sub: String, action: String, kind: String, tip: String) -> Dictionary:
	var k := Hotkeys.key(action)
	var b: Button = hud._card_button(title, sub, Hotkeys.badge(k), "")
	b.name = "G6_" + action   # panel_probe finds squad61 actions by G6_<action>
	var rec := {"btn": b, "kind": "g2", "g2": kind, "tip": tip}
	hud._card_buttons.append(rec)
	_recs.append(rec)
	hud._register_hotkey(k, b)
	return rec


func _open_page(p: String) -> void:
	page = p
	_page_ids = _combat.duplicate()
	hud._card_sig = "?"
	hud._refresh()


func _close_page() -> void:
	page = ""
	hud._card_sig = "?"
	hud._refresh()


## Called first by hud._add_unit_buttons: when a G6.1 sub-card is open for this selection it fills the card
## and returns true (the normal unit buttons are skipped). A changed selection closes the page.
func add_page(ids: Array) -> bool:
	if page == "":
		return false
	var a := ids.duplicate()
	var b := _page_ids.duplicate()
	a.sort()
	b.sort()
	if a != b:
		page = ""
		return false
	_recs.clear()
	_ids = ids.duplicate()
	_combat = ids.duplicate()
	if page == "formation":
		hud._card_title.text = "FORMATION   (the group faces its move direction; armour leads mixed groups)"
		for f in Orders.PLAYER_FORMATIONS:
			var r = _btn(String(FORM_NAMES.get(f, f)), "", String(FORM_KEYS.get(f, "")), "form_" + String(f), "Set formation: " + String(FORM_NAMES.get(f, f)))
			r.btn.pressed.connect(func(): hud._issue({"type": "set_formation", "unit_ids": _combat.duplicate(), "formation": String(f)}))
		var pc = _btn("Group pace", "off", "Z", "pace", "Move as a group at the slowest unit's speed (toggle).")
		pc.btn.pressed.connect(_toggle_pace)
	else:
		hud._card_title.text = "STANCE"
		for s in STANCES:
			var r = _btn(String(s[1]), "", String(s[2]), "stance_" + String(s[0]), String(s[3]))
			r.btn.pressed.connect(func(): hud._issue({"type": "set_stance", "unit_ids": _combat.duplicate(), "stance": String(s[0])}))
		var tb = _btn("Teams panel", "F2", "T", "teams", "Open the Teams panel (groups, squads, platoons, companies).")
		tb.btn.pressed.connect(func():
			if hud.get("teams") != null:
				hud.teams.toggle())
	var bk = _btn("Back", "", "BACKSPACE", "back", "Back to the orders card.")
	bk.btn.pressed.connect(_close_page)
	return true


func _pace_on() -> bool:
	for id in _combat:
		var e = _ent(int(id))
		if e != null and e.has("pace_grp"):
			return true
	return false


func _toggle_pace() -> void:
	hud._issue({"type": "set_formation", "unit_ids": _combat.duplicate(), "pace": not _pace_on()})


func _current_stance() -> String:
	for id in _combat:
		var e = _ent(int(id))
		if e != null:
			return String(e.get("stance", ""))
	return ""


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
	var nxt: String = Orders.PLAYER_FORMATIONS[(Orders.PLAYER_FORMATIONS.find(cur) + 1) % Orders.PLAYER_FORMATIONS.size()]
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
				b.text = "[F] Formation\n%s" % String(FORM_NAMES.get(_current_formation(), _current_formation()))
				reason = w.preview_command({"type": "set_formation", "issuer": pf, "unit_ids": _combat, "formation": "line"})
			"stance":
				b.text = "Stance\n%s" % String(STANCE_NAME.get(_current_stance(), _current_stance()))
			"pace":
				b.text = "Group pace\n%s" % ("ON" if _pace_on() else "off")
			"regroup":
				reason = w.preview_command({"type": "regroup", "issuer": pf, "unit_ids": _combat})
			"bearer_leave":
				reason = w.preview_command({"type": "leave_squad", "issuer": pf, "unit_ids": _bearers})
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
