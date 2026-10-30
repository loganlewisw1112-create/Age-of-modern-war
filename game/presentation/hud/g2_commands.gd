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
	"echelon_right": "Echelon right", "file": "File", "spread": "Spread (skirmish)",
	"staggered_column": "Staggered column", "diamond": "Diamond"}   # G7 SQUAD7
const FORM_KEYS := {"line": "L", "wedge": "E", "column": "C", "box": "B", "echelon_left": "J", "echelon_right": "K",
	"file": "I", "spread": "X", "staggered_column": "V", "diamond": "N"}
## G7 (SQUAD7): movement technique + tactic buttons on the formation page, keys rebindable in Hotkeys (group squad7).
const TECH_BTNS := [["auto", "tech_auto", "Technique: automatic by threat (traveling / overwatch / bounding)."],
	["traveling", "tech_traveling", "Traveling: everyone moves (contact unlikely)."],
	["traveling_overwatch", "tech_overwatch", "Traveling overwatch: the trailing team hangs back to cover."],
	["bounding_overwatch", "tech_bounding", "Bounding overwatch: teams A and B cover and move in turns."]]
const GarrisonSys = preload("res://sim/systems/garrison.gd")
var _w: SimWorld = null
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
		_add_span_button(ids)   # G7 (FISSURE7 CR 710)
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
	_add_casualty_buttons()
	_add_span_button(_ids)   # G7 (FISSURE7 CR 710): repair units (can_repair) on a units card
	_add_cn_buttons()        # G7 (CNSIM7-3 CR 557): counter-nanite team orders
	_add_so_buttons()        # G7 SPECOPS8 (13.9c-44): spec-ops missions for a tactical operator squad
	_add_vanta_buttons()     # G7 (AIRV7, CR 4527 part 5): CN Vanta hardpoints + return to pad
	# G6.1 (INTEG61, BEARER61 CR seq 332): ammo bearer card. Join arms a click on an own squad member;
	# right-clicking one with only bearers selected does the same (G2Input.smart).
	_bearers = _ids.filter(func(x): return AB.is_bearer(_ent(int(x))))
	if not _bearers.is_empty():
		var jb = _btn2("Join squad", "click a squad", "bearer_join", "bearer_join", "Click an own squad member: the selected ammo bearers follow that squad and restock it.\nRight-click a squad member does the same.")
		jb.btn.pressed.connect(func(): _mv().g2.arm("bearer_join", {"unit_ids": _bearers.duplicate()}))
		var lb = _btn2("Leave squad", "", "bearer_leave", "bearer_leave", "The selected ammo bearers leave their squad.")
		lb.btn.pressed.connect(func(): hud._issue({"type": "leave_squad", "unit_ids": _bearers.duplicate()}))


## G7 (WOUND7 CR via ORCH): First aid [Shift+T] for any selected soldier who can give care, Evacuate casualty [Shift+E] for a
## selected carrier (ambulance / APC / helicopter / stretcher team: Medical.capacity > 0). Each picks the nearest
## own casualty the sim accepts (Wounds.validate_command), one per carer; the sim validates again on submit.
## (A click-to-target mode needs a G2Input arm mode: change request to ORCH.)
const WoundsSys = preload("res://sim/systems/wounds.gd")
const MedicalSys = preload("res://sim/systems/medical.gd")
const CARE_R := 25.0


func _add_casualty_buttons() -> void:
	var carers: Array = []
	var carriers: Array = []
	for id in _ids:
		var e = _ent(int(id))
		if e == null or e.kind != "unit":
			continue
		if MedicalSys.capacity(String(e.def)) > 0:
			carriers.append(int(id))
		elif WoundsSys._can_care(e):
			carers.append(int(id))
	if not carers.is_empty():
		var tb = _btn2("First aid", "nearest wounded", "treat_casualty", "treat_casualty", "First aid: the selected soldiers treat the nearest wounded own soldier (stops bleeding; a downed one is stabilised).")
		tb.btn.pressed.connect(_casualty_orders.bind("treat_casualty", carers))
	if not carriers.is_empty():
		var eb = _btn2("Evacuate", "nearest downed", "evacuate_casualty", "evacuate_casualty", "Evacuate casualty: the selected ambulance / APC / helicopter / stretcher team picks up the nearest downed own soldier.")
		eb.btn.pressed.connect(_casualty_orders.bind("evacuate_casualty", carriers))


func _casualty_orders(typ: String, who: Array) -> void:
	var w: SimWorld = hud._world()
	var taken := {}
	var n := 0
	for uid in who:
		var u = w.entities.get(int(uid))
		if u == null:
			continue
		var best := -1
		var bd := CARE_R
		for c in w.entities.values():
			if c.kind != "unit" or int(c.owner) != int(u.owner) or taken.has(int(c.id)) or int(c.id) == int(uid):
				continue
			var d := Vector2(u.pos).distance_to(Vector2(c.pos))
			if d >= bd:
				continue
			var cmd := {"type": typ, "issuer": int(u.owner), "unit_id": int(uid), "target": int(c.id)}
			if WoundsSys.validate_command(w, cmd) == "":
				bd = d
				best = int(c.id)
		if best >= 0:
			taken[best] = true
			hud._issue({"type": typ, "unit_id": int(uid), "target": best})
			n += 1
	if n == 0 and _mv().get("g2") != null:
		_mv().g2.flash("No wounded own soldier in reach." if typ == "treat_casualty" else "No downed own soldier to evacuate in reach.")


## G7 (FISSURE7 CR 710, SQUAD7-6): Span fissure [Shift+J] for selected engineers (Fissures7.is_engineer: can_build or
## can_repair) on a map with fissures. Arms the G2Input click-a-tile mode "cell_cmd": hovering previews the span the
## engineers would build (Fissures7.span_plan: green tiles and the bank-to-bank line; a red cross where nothing can be
## spanned), a click on a valid tile submits {type: fissure_span, unit_ids, cell: [x, y]} (the sim validates again).
const Fissures7 = preload("res://sim/systems/fissures7.gd")
var _span_ids: Array = []


func _add_span_button(ids: Array) -> void:
	var w: SimWorld = hud._world()
	if w == null or Fissures7.st(w) == null:
		return   # no fissures on this map: no button
	_span_ids = []
	for id in ids:
		var e = _ent(int(id))
		if e != null and int(e.owner) == int(hud._pf()) and Fissures7.is_engineer(e):
			_span_ids.append(int(id))
	if _span_ids.is_empty():
		return
	var sb = _btn2("Span fissure", "click a fissure", "fissure_span", "fissure_span", "Engineers bridge a fissure or canyon: click an open tile; they build the shortest straight 2-wide span across it (bank to bank), which fissures never reopen.")
	sb.btn.pressed.connect(_arm_span)


func _arm_span() -> void:
	var g2 = _mv().get("g2")
	if g2 == null:
		return
	if not (g2.get("on_cell") is Callable):
		g2.flash("Span fissure: click-target mode unavailable in this build.")
		return
	g2.arm("cell_cmd", {"unit_ids": _span_ids.duplicate(), "on_cell": _span_click,
		"status": "SPAN FISSURE: click an open fissure / canyon tile. Esc cancels.", "preview": _span_preview})


static func span_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))


## Click handler (world joined by MatchView before click handlers). true = issued (the mode ends).
func _span_click(p: Vector2) -> bool:
	var w: SimWorld = hud._world()
	var c := span_cell(p)
	if w == null or Fissures7.span_plan(w, c).is_empty():
		if _mv().get("g2") != null:
			_mv().g2.flash("No fissure to span here (or too wide).")
		return false
	var live: Array = _span_ids.filter(func(x): return w.entities.has(int(x)))
	if live.is_empty():
		return true
	hud._issue({"type": "fissure_span", "unit_ids": live, "cell": [c.x, c.y]})
	var fx = _mv().get("fx_layer")
	if fx != null:
		fx.add_marker(Vector2(c) + Vector2(0.5, 0.5), Color(0.45, 0.85, 1.0))
	return true


## Preview while the mode is armed (drawn by the G2 overlay; reads the world only when it is readable).
func _span_preview(ci: CanvasItem, cur: Vector2) -> void:
	var mv = _mv()
	if not mv.world_readable():
		return
	var w: SimWorld = hud._world()
	var c := span_cell(cur)
	var plan: Dictionary = Fissures7.span_plan(w, c) if w != null else {}
	if plan.is_empty():
		var cs: Vector2 = mv.world_to_screen(Vector2(c) + Vector2(0.5, 0.5))
		ci.draw_line(cs + Vector2(-7, -4), cs + Vector2(7, 4), Color(1.0, 0.3, 0.2), 2.0)
		ci.draw_line(cs + Vector2(-7, 4), cs + Vector2(7, -4), Color(1.0, 0.3, 0.2), 2.0)
		return
	var mw := int(w.map.w)
	for i in plan.tiles:
		var tc := Vector2(int(i) % mw, int(i) / mw)
		var poly := PackedVector2Array([mv.world_to_screen(tc), mv.world_to_screen(tc + Vector2(1, 0)),
			mv.world_to_screen(tc + Vector2(1, 1)), mv.world_to_screen(tc + Vector2(0, 1))])
		ci.draw_colored_polygon(poly, Color(0.3, 1.0, 0.35, 0.35))
	var a: Vector2 = mv.world_to_screen(Vector2(plan.a) + Vector2(0.5, 0.5))
	var b: Vector2 = mv.world_to_screen(Vector2(plan.b) + Vector2(0.5, 0.5))
	ci.draw_line(a, b, Color(0.3, 1.0, 0.35), 2.0)
	ci.draw_circle(a, 4.0, Color(0.3, 1.0, 0.35))
	ci.draw_circle(b, 4.0, Color(0.3, 1.0, 0.35))


## G7 (CNSIM7-3 CR seq 557, SQUAD7-6): counter-nanite team card buttons. Pincer [Shift+P] sends the selected teams
## on the anti-walker pincer against the nearest heavy Machine walker in reach (CounterNanite.pincer_target, target_id
## -1); Break contact [Shift+B] orders the formed withdrawal. One command per selected team (a team is resolved from
## any of its members' cn_team); the sim validates each again.
const CounterNanite = preload("res://sim/systems/counter_nanite.gd")
var _cn_teams: Dictionary = {}   # team id -> [selected member ids]


func _add_cn_buttons() -> void:
	_cn_teams = {}
	for id in _ids:
		var e = _ent(int(id))
		if e == null or e.kind != "unit":
			continue
		var tid := CounterNanite.team_of(e)
		if tid < 0:
			continue
		if not _cn_teams.has(tid):
			_cn_teams[tid] = []
		_cn_teams[tid].append(int(id))
	if _cn_teams.is_empty():
		return
	var pb = _btn2("Pincer", "nearest walker", "cn_pincer", "cn_pincer", "Anti-walker pincer: the selected counter-nanite team splits its APCs round the nearest heavy Machine walker in reach and hits it from both sides.")
	pb.btn.pressed.connect(_cn_orders.bind("cn_pincer"))
	var bb = _btn2("Break contact", "formed withdrawal", "cn_break_contact", "cn_break_contact", "Break contact: the selected counter-nanite team withdraws in bounds, covering itself, away from the threat.")
	bb.btn.pressed.connect(_cn_orders.bind("cn_break_contact"))
	_add_cn8_buttons()   # G7 CNMISSION8 (13.9c-44): PURGE MISSION + the team-orders page


func _cn_cmd(typ: String, tid: int) -> Dictionary:
	var c := {"type": typ, "unit_ids": (_cn_teams[tid] as Array).duplicate()}
	if typ == "cn_pincer":
		c["target_id"] = -1
	return c


func _cn_orders(typ: String) -> void:
	var tids: Array = _cn_teams.keys()
	tids.sort()
	for tid in tids:
		hud._issue(_cn_cmd(typ, int(tid)))


## "" when at least one selected team would accept typ, else the first refusal.
func _cn_reason(w: SimWorld, typ: String) -> String:
	var first := ""
	var tids: Array = _cn_teams.keys()
	tids.sort()
	for tid in tids:
		var c := _cn_cmd(typ, int(tid))
		c["issuer"] = int(hud._pf())
		var r := w.preview_command(c)
		if r == "":
			return ""
		if first == "":
			first = r
	return first


## G7 (AIRV7): CN Vanta card. Hardpoint buttons cycle that slot's item (nose, the mirrored side pair, rear; applied
## on the roof pad after the swap time); the sub line shows the current / queued item. The sim validates each order.
const Vanta7 = preload("res://sim/systems/vanta7.gd")
const VANTA_NAMES := {"cannon": "30 mm cannon", "missiles": "Missiles", "gun": "Gun pods", "anti_drone": "Anti-drone",
	"drones": "Drone launchers", "flares": "Flares", "deterrents": "Deterrents"}
var _vantas: Array = []


func _add_vanta_buttons() -> void:
	_vantas = []
	var w = hud._world()
	for id in _ids:
		var e = _ent(int(id))
		if e != null and Vanta7.is_vanta(e) and int(e.owner) == int(hud._pf()):
			_vantas.append(int(id))
	if _vantas.is_empty() or w == null:
		return
	var r: Dictionary = Vanta7.rec(w, int(_vantas[0]))
	var cur: Dictionary = r.get("pend", {"n": r.get("n", ""), "s": r.get("s", ""), "r": r.get("r", "")})
	var hb = _btn2("Return to pad", "land on the roof", "vanta_rtb", "vanta_rtb", "Fly back to its barracks roof pad and land: refuel, rearm, change hardpoints there.")
	hb.btn.pressed.connect(func(): hud._issue({"type": "vanta_rtb", "unit_ids": _vantas.duplicate()}))
	for sl in [["nose", "n", "Nose"], ["side", "s", "Sides"], ["rear", "r", "Rear"]]:
		var nm := String(VANTA_NAMES.get(String(cur.get(sl[1], "")), String(cur.get(sl[1], ""))))
		var b = _btn2(String(sl[2]), nm, "vanta_cycle_" + String(sl[0]), "vanta_loadout",
			"Next item for the %s hardpoint%s (only while landed on its roof pad; fitted after the swap time)." % [String(sl[0]), "s - both sides carry the same item" if sl[0] == "side" else ""])
		b.btn.pressed.connect(func(): hud._issue({"type": "vanta_loadout", "unit_ids": _vantas.duplicate(), "cycle": String(sl[0])}))


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
	if page.begins_with("cn8_"):
		return _cn8_page()
	if page == "formation":
		hud._card_title.text = "FORMATION   (the group faces its move direction; armour leads mixed groups)"
		for f in Orders.PLAYER_FORMATIONS:
			var r = _btn(String(FORM_NAMES.get(f, f)), "", String(FORM_KEYS.get(f, "")), "form_" + String(f), "Set formation: " + String(FORM_NAMES.get(f, f)))
			r.btn.pressed.connect(func(): hud._issue({"type": "set_formation", "unit_ids": _combat.duplicate(), "formation": String(f)}))
		var pc = _btn("Group pace", "off", "Z", "pace", "Move as a group at the slowest unit's speed (toggle).")
		pc.btn.pressed.connect(_toggle_pace)
		for t in TECH_BTNS:
			var tr = _btn(Hotkeys.label(String(t[1])), "", Hotkeys.key(String(t[1])), "tech_" + String(t[0]), String(t[2]))
			tr.btn.pressed.connect(func(): hud._issue({"type": "set_technique", "unit_ids": _combat.duplicate(), "technique": String(t[0])}))
		var fb = _btn("Fall back", "", Hotkeys.key("fall_back"), "fall_back", "Fall back 10 tiles: walk backwards facing the enemy and keep firing.")
		fb.btn.pressed.connect(_fall_back)
		var su = _btn("Suppress", "", Hotkeys.key("suppress"), "suppress", "Suppressive fire on the last known enemy position.")
		su.btn.pressed.connect(_suppress)
		var cb = _btn("Clear building", "", Hotkeys.key("clear_building"), "clear_building", "Stack up, grenade first, clear the nearest building room by room.")
		cb.btn.pressed.connect(_clear_building)
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


## G7 (SQUAD7) tactic buttons: the group's centre and facing (formation facing of the first unit).
func _group_frame() -> Array:
	var cen := Vector2.ZERO
	var n := 0
	var fwd := Vector2(0, -1)
	for id in _combat:
		var e = _ent(int(id))
		if e != null:
			cen += Vector2(e.pos)
			n += 1
			if e.has("f7_f"):
				fwd = Vector2.RIGHT.rotated(deg_to_rad(float(e.f7_f)))
	return [cen / float(maxi(n, 1)), fwd]


func _fall_back() -> void:
	var fr := _group_frame()
	hud._issue({"type": "fall_back", "unit_ids": _combat.duplicate(), "target": Vector2(fr[0]) - Vector2(fr[1]) * 10.0})


func _last_known() -> Variant:
	for id in _combat:
		var e = _ent(int(id))
		if e != null and e.has("f7_lk"):
			return Vector2(e.f7_lk[0])
	return null


func _suppress() -> void:
	var p = _last_known()
	if p != null:
		hud._issue({"type": "suppress_area", "unit_ids": _combat.duplicate(), "target": p})


func _nearest_building() -> Variant:
	if _w == null:
		return null
	var cen: Vector2 = _group_frame()[0]
	var best = null
	var bd := 15.0
	for b in _w.entities.values():
		if b.kind != "building" or GarrisonSys.slots_of(String(b.def)) <= 0:
			continue
		var d := cen.distance_to(Vector2(b.pos))
		if d < bd:
			bd = d
			best = b
	return best


func _clear_building() -> void:
	var b = _nearest_building()
	if b != null:
		hud._issue({"type": "clear_building", "unit_ids": _combat.duplicate(), "building_id": int(b.id)})


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
	_w = w
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
			"tech_auto", "tech_traveling", "tech_traveling_overwatch", "tech_bounding_overwatch":
				reason = w.preview_command({"type": "set_technique", "issuer": pf, "unit_ids": _combat, "technique": String(rec.g2).trim_prefix("tech_")})
			"fall_back":
				reason = w.preview_command({"type": "fall_back", "issuer": pf, "unit_ids": _combat, "target": _group_frame()[0]})
			"suppress":
				reason = "No known enemy position." if _last_known() == null else ""
			"clear_building":
				reason = "No building nearby." if _nearest_building() == null else ""
			"regroup":
				reason = w.preview_command({"type": "regroup", "issuer": pf, "unit_ids": _combat})
			"cn_pincer", "cn_break_contact":
				reason = _cn_reason(w, String(rec.g2))
			"cn8_purge", "cn8_team", "cn8_drive", "cn8_fly", "cn8_mount", "cn8_move", "cn8_dismount", "cn8_deploy", "cn8_hero", "cn8_loadout", "cn8_extract", "cn8_cancel", "cn8_hold":
				reason = cn8_reason(w, String(rec.g2))
			"so8_escort", "so8_raid", "so8_recon", "so8_rescue", "so8_insert", "so8_cancel":
				reason = so8_reason(w, String(rec.g2))
				if String(rec.g2) == "so8_insert":
					b.text = "[%s] Insert
%s" % [Hotkeys.badge(Hotkeys.key("so_insert")), so8_mode.to_upper()]
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


# ================================================================ G7 CNMISSION8 (master scope 13.9c-44)
## PURGE MISSION [Shift+A]: select a strike team (a member or its APC), press, click a creep area or a core; the card
## then asks Drive [Shift+R] or Fly [Shift+F] and submits cn_mission (CnMission8). Team orders [Shift+O] opens the
## step page: Mount, Move (click), Dismount, Deploy (click ground), Hero detonate, Loadout (cycles presets),
## Extract / Return, Cancel mission, Hold site. Every button is pre-checked with the sim's own reason function
## (CnMission8 team_reason / mission_reason / step_reason, or world.preview_command) and disabled with the reason as
## its tooltip. Keys: Hotkeys (cn_purge_mission / cn_team_orders in cn7; the page keys in the page group cn8p).
const M8 = preload("res://sim/systems/cn_mission8.gd")
const CN8_STEPS := [["Mount", "board the APCs", "cn_mount_team", "cn8_mount", "mount", "Every operator on foot boards his squad APC."],
	["Move", "click a point", "cn_move_team", "cn8_move", "move", "One order moves the whole team (motorcade convoy)."],
	["Dismount", "everyone out", "cn_dismount_team", "cn8_dismount", "dismount", "Everyone gets out of the APCs where they stand."],
	["Deploy", "click the ground", "cn_deploy_here", "cn8_deploy", "deploy", "Deploy a counter-nanite package at the clicked site (the APCs must be within 7 tiles)."],
	["Hero detonate", "one stays behind", "cn_hero_detonate", "cn8_hero", "hero", "One operator stays and detonates the package by hand: instant arming, certain death."],
	["Loadout", "next preset", "cn_loadout_cycle", "cn8_loadout", "loadout", "Cycle the package loadout preset (only at the facility; locked in the field)."],
	["Extract", "return home", "cn_extract", "cn8_extract", "extract", "Remount and return to the facility (by dropship when the mission flew in)."],
	["Cancel mission", "stop here", "cn_mission_cancel", "cn8_cancel", "cancel", "Stop the purge mission: the team stays where it is."],
	["Hold site", "off", "cn_mission_hold", "cn8_hold", "hold", "Hold the site after the purge instead of coming home (toggle)."]]
var _cn8_target := Vector2(-1, -1)
var cn8_last := {}   # last command a CNMISSION8 button submitted (playtest evidence)


func _cn8_tid() -> int:
	var tids: Array = _cn_teams.keys()
	tids.sort()
	var w = hud._world()
	for tid in tids:
		var t = CounterNanite.team(w, int(tid)) if w != null else null
		if t != null and String(t.kind) == "strike":
			return int(tid)
	return int(tids[0]) if not tids.is_empty() else -1


func _collect_cn_teams() -> void:
	_cn_teams = {}
	for id in _ids:
		var e = _ent(int(id))
		if e == null or e.kind != "unit":
			continue
		var tid := CounterNanite.team_of(e)
		if tid >= 0:
			if not _cn_teams.has(tid):
				_cn_teams[tid] = []
			_cn_teams[tid].append(int(id))


func _add_cn8_buttons() -> void:
	var pm = _btn2("PURGE MISSION", "click creep / core", "cn_purge_mission", "cn8_purge", "Purge mission: the strike team boards, leaves the facility, drives or flies to the creep area or core you click, deploys counter-nanites, holds until it is purged, then comes home. Any order you give the team takes over.")
	pm.btn.pressed.connect(cn8_arm_purge)
	var to = _btn2("Team orders", "step by step", "cn_team_orders", "cn8_team", "Step buttons: Mount, Move, Dismount, Deploy, Hero detonate, Loadout, Extract / Return, Cancel mission, Hold site.")
	to.btn.pressed.connect(_cn8_open.bind("cn8_team"))


func _cn8_open(p: String) -> void:
	page = p
	_page_ids = _ids.duplicate()
	hud._card_sig = "?"
	hud._refresh()


func cn8_arm_purge() -> void:
	var tid := _cn8_tid()
	_mv().g2.arm("cell_cmd", {"unit_ids": _ids.duplicate(), "on_cell": _cn8_on_purge_cell.bind(tid),
		"status": "PURGE MISSION: click a creep area or a core. Esc cancels."})


## The clicked tile: refused (flash, stay armed) when there is no creep or core there; else the Drive / Fly page.
func cn8_on_purge_cell(p: Vector2) -> bool:
	return _cn8_on_purge_cell(p, _cn8_tid())


func _cn8_on_purge_cell(p: Vector2, tid: int) -> bool:
	var w = hud._world()
	if w == null:
		return true
	var why: String = M8.mission_reason(w, int(hud._pf()), tid, p, "drive")
	if why == "No creep or core there to purge." or why == "Pick a creep area or a core on the map.":
		_mv().g2.flash(why)
		return false
	_cn8_target = p
	_cn8_open("cn8_purge")
	return true


## Click-a-tile step orders (Move / Deploy).
func _cn8_arm_cell(kind: String) -> void:
	var tid := _cn8_tid()
	var st := "MOVE TEAM: click the destination. Esc cancels." if kind == "move" else "DEPLOY: click the ground for the package site. Esc cancels."
	_mv().g2.arm("cell_cmd", {"unit_ids": _ids.duplicate(), "on_cell": _cn8_on_cell.bind(kind, tid), "status": st})


func _cn8_on_cell(p: Vector2, kind: String, tid: int) -> bool:
	var w = hud._world()
	if w == null:
		return true
	var c := _cn8_cmd(kind, tid, p)
	c["issuer"] = int(hud._pf())
	var why: String = w.preview_command(c)
	if why != "":
		_mv().g2.flash(why)
		return false
	c.erase("issuer")
	cn8_last = c.duplicate()
	hud._issue(c)
	return true


func _cn8_pkg(tid: int) -> String:
	var w = hud._world()
	var t = CounterNanite.team(w, tid) if w != null else null
	if t == null:
		return "purge"
	var pk := M8.packages(w, t)
	for k in ["purge", "seed_hunter", "barrier", "core_breaker"]:
		if pk.has(k):
			return k
	return "purge"


## The sim command a CNMISSION8 button submits (target only for move / deploy).
func _cn8_cmd(kind: String, tid: int, p: Vector2 = Vector2(-1, -1)) -> Dictionary:
	var w = hud._world()
	match kind:
		"drive", "fly":
			return {"type": "cn_mission", "team_id": tid, "target": [_cn8_target.x, _cn8_target.y], "mode": kind}
		"mount":
			return {"type": "cn_mount", "team_id": tid}
		"dismount":
			return {"type": "cn_dismount", "team_id": tid}
		"move":
			return {"type": "cn_move", "team_id": tid, "target": [p.x, p.y]}
		"deploy":
			return {"type": "cn_deploy", "team_id": tid, "target": [p.x, p.y], "package": _cn8_pkg(tid)}
		"hero":
			return {"type": "cn_hero_detonate", "team_id": tid, "unit_id": -1}
		"loadout":
			return {"type": "cn_set_loadout", "team_id": tid, "packages": M8.next_loadout(w, tid) if w != null else []}
		"extract":
			return {"type": "cn_extract", "team_id": tid}
		"cancel":
			return {"type": "cn_mission_cancel", "team_id": tid}
		"hold":
			return {"type": "cn_mission_hold", "team_id": tid, "on": (not bool(M8.mission_of(w, tid).get("hold", false))) if w != null else true}
	return {}


func cn8_issue(kind: String) -> void:
	var c := _cn8_cmd(kind, _cn8_tid())
	if c.is_empty():
		return
	cn8_last = c.duplicate()
	hud._issue(c)
	if kind == "drive" or kind == "fly":
		if _mv() != null and _mv().get("fx_layer") != null:
			_mv().fx_layer.add_marker(_cn8_target, Color(0.35, 1.0, 0.6))
		_close_page()


## "" or the refusal for a CNMISSION8 button (rec kind cn8_*), from the sim's own reason functions.
func cn8_reason(w: SimWorld, kind: String) -> String:
	var tid := _cn8_tid()
	var pf := int(hud._pf())
	match kind:
		"cn8_purge":
			return M8.team_reason(w, pf, tid)
		"cn8_team":
			return "" if tid >= 0 else "Select a counter-nanite team."
		"cn8_drive", "cn8_fly":
			return M8.mission_reason(w, pf, tid, _cn8_target, kind.trim_prefix("cn8_"))
		"cn8_mount", "cn8_dismount", "cn8_deploy":
			return M8.step_reason(w, pf, tid, kind.trim_prefix("cn8_"))
		"cn8_move":
			return "" if CounterNanite.team(w, tid) != null else "Select a counter-nanite team."
		"cn8_hero", "cn8_loadout", "cn8_extract", "cn8_cancel", "cn8_hold":
			var c := _cn8_cmd(kind.trim_prefix("cn8_"), tid)
			c["issuer"] = pf
			return w.preview_command(c)
	return ""


func _cn8_page() -> bool:
	_collect_cn_teams()
	if _cn_teams.is_empty():
		page = ""
		return false
	var w = hud._world()
	var tid := _cn8_tid()
	var t = CounterNanite.team(w, tid) if w != null else null
	var nm := String(t.name) if t != null else "team"
	if page == "cn8_purge":
		hud._card_title.text = "PURGE MISSION - %s   (Drive or Fly?)" % nm.to_upper()
		var db = _btn2("Drive", "APCs by road", "cn_mission_drive", "cn8_drive", "Drive: the APCs leave the facility through the gates and drive to the target.")
		db.btn.pressed.connect(cn8_issue.bind("drive"))
		var fb = _btn2("Fly", "dropship insert", "cn_mission_fly", "cn8_fly", "Fly: the team loads into the stealth dropship (or a VTOL dropship) on its pad and lands near the target on open ground.")
		fb.btn.pressed.connect(cn8_issue.bind("fly"))
	else:
		hud._card_title.text = "%s - TEAM ORDERS" % nm.to_upper()
		for s in CN8_STEPS:
			var r = _btn2(String(s[0]), String(s[1]), String(s[2]), String(s[3]), String(s[5]))
			if s[4] == "move" or s[4] == "deploy":
				r.btn.pressed.connect(_cn8_arm_cell.bind(String(s[4])))
			else:
				r.btn.pressed.connect(cn8_issue.bind(String(s[4])))
	var bk = _btn("Back", "", "BACKSPACE", "back", "Back to the orders card.")
	bk.btn.pressed.connect(_close_page)
	return true


# ================================================================ G7 SPECOPS8 (master scope 13.9c-44)
## Spec-ops missions for a selected tactical operator squad (a member or its APC): Escort [Shift+G] (click a strike
## team on a purge mission), Core raid [Shift+C] (click a nanite core / Machine structure), Recon & mark [Shift+K]
## (click an area), Rescue [Shift+M] (click a downed team, a lost squad or its beacon). Insert [Shift+I] toggles Drive /
## Fly for the next mission; Cancel [Shift+Z]. Buttons are pre-checked with SpecOps8.team_reason / cancel_reason
## (disabled + the reason as tooltip); the click is checked with the sim's own validation (refusal flashes, the mode
## stays armed). Keys: Hotkeys group so8.
const SO8 = preload("res://sim/systems/specops8.gd")
const SO8_BTNS := [["Escort", "click a strike team", "so_escort", "so8_escort", "escort", "Escort: the squad joins a strike team's purge mission, drives or flies with it, screens the purge site and comes home with it. Click the strike team."],
	["Core raid", "click a core", "so_raid", "so8_raid", "raid", "Core raid: the squad travels to a nanite core or Machine structure, plants demolition charges, withdraws and detonates them. Click the target."],
	["Recon & mark", "click an area", "so_recon", "so8_recon", "recon", "Recon & mark: the squad scouts the area, reveals it and marks creep areas and Machine targets for fire support. Click the area."],
	["Rescue", "click survivors", "so_rescue", "so8_rescue", "rescue", "Rescue / extract: the squad goes to a downed team, lost squad or beacon, recovers the survivors (wounded carried) and brings them home. Click the place."]]
var so8_mode := "drive"
var so8_last := {}   # last so_* command a SPECOPS8 button submitted (playtest evidence)


func _so8_tid() -> int:
	var w = hud._world()
	if w == null:
		return -1
	var tids: Array = _cn_teams.keys()
	tids.sort()
	for tid in tids:
		var t = CounterNanite.team(w, int(tid))
		if t != null and String(t.kind) == "tactical":
			return int(tid)
	return -1


func _add_so_buttons() -> void:
	if _so8_tid() < 0:
		return
	for s in SO8_BTNS:
		var r = _btn2(String(s[0]), String(s[1]), String(s[2]), String(s[3]), String(s[5]))
		r.btn.pressed.connect(so8_arm.bind(String(s[4])))
	var ib = _btn2("Insert", so8_mode.to_upper(), "so_insert", "so8_insert", "Insert: how the next spec-ops mission goes in - DRIVE (the APC leaves through the gates) or FLY (the stealth / VTOL dropship from its pad, landing on open ground near the target). Click to switch.")
	ib.btn.pressed.connect(so8_toggle)
	var cb = _btn2("Cancel spec-ops", "stop here", "so_cancel", "so8_cancel", "Stop the spec-ops mission: the squad stays where it is.")
	cb.btn.pressed.connect(so8_issue_cancel)


func so8_toggle() -> void:
	so8_mode = "fly" if so8_mode == "drive" else "drive"


func so8_arm(kind: String) -> void:
	var tid := _so8_tid()
	var what: String = {"escort": "click the strike team to escort", "raid": "click a nanite core or Machine structure",
		"recon": "click the area to scout", "rescue": "click the downed team, lost squad or beacon"}.get(kind, "click the target")
	_mv().g2.arm("cell_cmd", {"unit_ids": _ids.duplicate(), "on_cell": so8_on_cell.bind(kind, tid),
		"status": "%s (%s): %s. Esc cancels." % [String(SO8.KIND_NAME.get(kind, kind)), so8_mode.to_upper(), what]})


## The clicked point: the sim's refusal flashes and the mode stays armed; else so_mission is submitted.
func so8_on_cell(p: Vector2, kind: String, tid: int = -1) -> bool:
	var w = hud._world()
	if w == null:
		return true
	if tid < 0:
		tid = _so8_tid()
	var c: Dictionary = SO8.cmd_for(w, int(hud._pf()), tid, kind, so8_mode, p)
	c["issuer"] = int(hud._pf())
	var why: String = w.preview_command(c)
	if why != "":
		_mv().g2.flash(why)
		return false
	c.erase("issuer")
	so8_last = c.duplicate()
	hud._issue(c)
	if _mv() != null and _mv().get("fx_layer") != null:
		_mv().fx_layer.add_marker(p, Color(1.0, 0.75, 0.3))
	return true


func so8_issue_cancel() -> void:
	var c := {"type": "so_cancel", "team_id": _so8_tid()}
	so8_last = c.duplicate()
	hud._issue(c)


## "" or the refusal for a SPECOPS8 button (rec kind so8_*), from the sim's own reason functions.
func so8_reason(w: SimWorld, kind: String) -> String:
	var tid := _so8_tid()
	var pf := int(hud._pf())
	match kind:
		"so8_cancel":
			return SO8.cancel_reason(w, pf, tid)
		"so8_insert":
			return SO8.team_reason(w, pf, tid, "drive")
	return SO8.team_reason(w, pf, tid, so8_mode)
