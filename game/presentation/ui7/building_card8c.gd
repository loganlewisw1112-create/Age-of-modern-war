extends "res://presentation/ui7/card8b_base.gd"
## G7 CARDS8C (13.9c-48): the remaining facility building cards, one script, four instances (kind):
##  bar  SENTINEL BARRACKS (barracks building / zone selected): watch roster + ROTATE a post, TRAIN by role,
##       rest & readiness + STAND TO, PATROL PLAN (pick one of the generated set; no drawing).
##  air  HELIPADS / VTOL PAD (helipad or pad zone): air roster + SERVICE (home pad rearm / refuel / repair), LAUNCH one /
##       LAUNCH ALL (click a point), RECALL ALL (own pads), AIR PATROL over a point (click) / END PATROL.
##  aid  AID STATION (aid station zone): casualty board, TREAT FIRST, EVACUATE (most critical), MEDICS (click a point).
##  lab  PACKAGE LAB (lab zone): research queue (packages, lab tier) and field upgrades (operator specialisations).
## Same rules as the CARDS8B cards (card8b_base.gd): shown only while that part is selected, world read only between
## sim steps, never writes the sim (MatchView.issue), every button pre-checked by the sim's own reason function
## (Cards8c.reason, CnFacility / CnProgress7 validate_command) and disabled with the reason as tooltip. Hotkeys: page
## groups bar8c / air8c / aid8c / lab8c in presentation/ui5/panels/hotkeys.gd (Shift chords).
## Hook (presentation/hud/hud.gd): preload("res://presentation/ui7/building_card8c.gd").attach(self, left)

const Cards8c = preload("res://sim/systems/cards8c.gd")
const KINDS := ["bar", "air", "aid", "lab"]
const TITLES := {"bar": "SENTINEL BARRACKS", "air": "HELIPADS + VTOL PAD", "aid": "AID STATION", "lab": "PACKAGE LAB"}
const PARTS := {"bar": "barracks", "air": "air", "aid": "aid", "lab": "lab"}

var kind := "bar"
var cur := 0          # picked post / aircraft / casualty / package (card-local)
var cur2 := 0         # picked role / plan / team
var cur3 := 0         # picked specialisation path
var picking := ""     # "" | "launch" | "launch_all" | "cap" | "medics": the next map click is the point
var _l1: Label
var _l2: Label
var _l3: Label
var _l4: Label


## Attaches all four cards; returns the barracks card.
static func attach(h, left_stack: Control) -> Control:
	var first: Control = null
	for k in KINDS:
		var c = (load("res://presentation/ui7/building_card8c.gd") as GDScript).new()
		c.kind = k
		c._setup(h, left_stack)
		if first == null:
			first = c
	return first


static func make(k: String):
	var c = (load("res://presentation/ui7/building_card8c.gd") as GDScript).new()
	c.kind = k
	return c


func defaults() -> Dictionary:
	match kind:
		"bar":
			return {"bar8c_post": ["SHIFT+P", "Next watch post"], "bar8c_rotate": ["SHIFT+R", "Rotate the post"],
				"bar8c_role": ["SHIFT+T", "Next Sentinel role"], "bar8c_train": ["SHIFT+B", "Train the role"],
				"bar8c_plan": ["SHIFT+L", "Next patrol plan"], "bar8c_adopt": ["SHIFT+A", "Adopt the patrol plan"],
				"bar8c_standto": ["SHIFT+S", "Stand to"]}
		"air":
			return {"air8c_pick": ["SHIFT+N", "Next aircraft"], "air8c_service": ["SHIFT+E", "Service (home pad)"],
				"air8c_launch": ["SHIFT+L", "Launch (click a point)"], "air8c_launch_all": ["SHIFT+A", "Launch all (click a point)"],
				"air8c_recall": ["SHIFT+H", "Recall all"], "air8c_cap": ["SHIFT+P", "Air patrol (click a point)"],
				"air8c_cap_end": ["SHIFT+X", "End air patrol"]}
		"aid":
			return {"aid8c_pick": ["SHIFT+N", "Next casualty"], "aid8c_first": ["SHIFT+F", "Treat first"],
				"aid8c_evac": ["SHIFT+E", "Evacuate"], "aid8c_medics": ["SHIFT+M", "Medics to a point"]}
	return {"lab8c_pkg": ["SHIFT+N", "Next package"], "lab8c_queue": ["SHIFT+Q", "Queue package"],
		"lab8c_tier": ["SHIFT+U", "Upgrade the lab"], "lab8c_team": ["SHIFT+T", "Next team"],
		"lab8c_path": ["SHIFT+P", "Next specialisation"], "lab8c_spec": ["SHIFT+S", "Specialise"]}


func _title() -> String:
	return String(TITLES[kind])


func _ready() -> void:
	_base_ready({"bar": "BarracksCard8c", "air": "AirCard8c", "aid": "AidCard8c", "lab": "LabCard8c"}[kind])
	match kind:
		"bar":
			_l1 = _line("Roster")
			_new_grid()
			_mk("bar8c_post", "PostButton", "POST", "Pick a watch post on the roster.", func(): _bump(1))
			_mk("bar8c_rotate", "RotateButton", "ROTATE", "Relieve this post now: fresh men take it, the men on it go off watch (never left empty).", func(): _issue(_cmd("bar8c_rotate")), func(): return _cmd("bar8c_rotate"))
			_l2 = _line("Rest")
			_new_grid()
			_mk("bar8c_role", "RoleButton", "ROLE", "Pick the Sentinel role to train.", func(): _bump(2))
			_mk("bar8c_train", "TrainButton", "TRAIN", "Drill every Sentinel of this role (credits, then experience).", func(): _issue(_cmd("bar8c_train")), func(): return _cmd("bar8c_train"))
			_mk("bar8c_standto", "StandToButton", "STAND TO", "Wake every resting soldier inside the walls; the Sentinels man the stand-to points.", func(): _issue(_cmd("bar8c_standto")), func(): return _cmd("bar8c_standto"))
			_l3 = _line("Plan")
			_new_grid()
			_mk("bar8c_plan", "PlanButton", "PLAN", "Look at the next generated patrol / positioning plan.", func(): _bump(2, true))
			_mk("bar8c_adopt", "AdoptButton", "ADOPT", "Put this patrol plan in force (the watch board re-deals its posts).", func(): _issue(_cmd("bar8c_adopt")), func(): return _cmd("bar8c_adopt"))
		"air":
			_l1 = _line("Roster")
			_new_grid()
			_mk("air8c_pick", "AircraftButton", "AIRCRAFT", "Pick an aircraft on the roster.", func(): _bump(1))
			_mk("air8c_service", "ServiceButton", "SERVICE", "Send it home to its own pad to rearm, refuel and repair.", func(): _issue(_cmd("air8c_service")), func(): return _cmd("air8c_service"))
			_mk("air8c_launch", "LaunchButton", "LAUNCH", "Launch this aircraft: click where it flies.", func(): _arm("launch"), func(): return _cmd("air8c_launch"))
			_mk("air8c_launch_all", "LaunchAllButton", "LAUNCH ALL", "Launch every aircraft on the pads: click where they fly.", func(): _arm("launch_all"), func(): return _cmd("air8c_launch_all"))
			_mk("air8c_recall", "RecallButton", "RECALL ALL", "Every aircraft back to its own pad.", func(): _issue(_cmd("air8c_recall")), func(): return _cmd("air8c_recall"))
			_mk("air8c_cap", "PatrolButton", "AIR PATROL", "Standing combat air patrol: click the point to guard.", func(): _arm("cap"), func(): return _cmd("air8c_cap"))
			_mk("air8c_cap_end", "PatrolEndButton", "END PATROL", "Stand the air patrol down.", func(): _issue(_cmd("air8c_cap_end")), func(): return _cmd("air8c_cap_end"))
			_l2 = _line("Patrol")
		"aid":
			_l1 = _line("Casualties")
			_new_grid()
			_mk("aid8c_pick", "CasualtyButton", "CASUALTY", "Pick a casualty on the board.", func(): _bump(1))
			_mk("aid8c_first", "FirstButton", "TREAT FIRST", "The facility menders treat this casualty first.", func(): _issue(_cmd("aid8c_first")), func(): return _cmd("aid8c_first"))
			_mk("aid8c_evac", "EvacButton", "EVACUATE", "Nearest free ambulance / APC / helicopter picks this casualty up.", func(): _issue(_cmd("aid8c_evac")), func(): return _cmd("aid8c_evac"))
			_mk("aid8c_medics", "MedicsButton", "MEDICS", "Send the facility menders to a point: click it.", func(): _arm("medics"), func(): return _cmd("aid8c_medics"))
			_l2 = _line("Medics")
		"lab":
			_l1 = _line("Research")
			_new_grid()
			_mk("lab8c_pkg", "PackageButton", "PACKAGE", "Pick a counter-nanite package.", func(): _bump(1))
			_mk("lab8c_queue", "QueueButton", "QUEUE", "Queue this package at the lab.", func(): _issue(_cmd("lab8c_queue")), func(): return _cmd("lab8c_queue"))
			_mk("lab8c_tier", "TierButton", "LAB TIER", "Upgrade the package lab to the next tier (new package types).", func(): _issue(_cmd("lab8c_tier")), func(): return _cmd("lab8c_tier"))
			# G7.1 CNOPS71-9 H8 facility upgrades (fac_upgrade): airlock bays (faster turnaround heal / decon), suit foundry
			_mk("lab8c_bays", "BaysButton", "BAYS", "Upgrade the airlock bays: the turnaround wash heals and decontaminates returning teams faster.", func(): _issue(_cmd("lab8c_bays")), func(): return _cmd("lab8c_bays"))
			_mk("lab8c_foundry", "FoundryButton", "FOUNDRY", "Upgrade the suit foundry: suits are built faster.", func(): _issue(_cmd("lab8c_foundry")), func(): return _cmd("lab8c_foundry"))
			_l2 = _line("Field")
			_new_grid()
			_mk("lab8c_team", "TeamButton", "TEAM", "Pick a counter-nanite team.", func(): _bump(2))
			_mk("lab8c_path", "PathButton", "PATH", "Pick the specialisation path.", func(): _bump(3))
			_mk("lab8c_spec", "SpecButton", "SPECIALISE", "Specialise the next operator of this team on this path.", func(): _issue(_cmd("lab8c_spec")), func(): return _cmd("lab8c_spec"))
	_l4 = _line("Hint")
	visible = false


func _bump(which: int, _plan := false) -> void:
	if which == 1:
		cur += 1
	elif which == 2:
		cur2 += 1
	else:
		cur3 += 1
	_after_local()


func _arm(what: String) -> void:
	if mv != null and mv.has_method("begin_point_pick"):
		picking = what
		mv.begin_point_pick(point_at)
		_after_local()


## The map click while a point pick is armed.
func point_at(p: Vector2) -> void:
	var what := picking
	picking = ""
	match what:
		"launch":
			_issue({"type": "c8c_air_launch", "unit_id": _pick(ids("air"), cur), "pos": [p.x, p.y]})
		"launch_all":
			_issue({"type": "c8c_air_launch", "unit_id": -1, "pos": [p.x, p.y]})
		"cap":
			_issue({"type": "c8c_air_cap", "pos": [p.x, p.y]})
		"medics":
			_issue({"type": "c8c_medics", "pos": [p.x, p.y]})


static func _pick(a: Array, i: int):
	return a[i % a.size()] if not a.is_empty() else null


## The ids the pick buttons cycle through.
func ids(what: String) -> Array:
	var w := world()
	if w == null or fac < 0:
		return []
	match what:
		"post":
			var out := []
			for j in Cards8c.posts(w, fac):
				out.append(String(j.id))
			return out
		"role":
			return Cards8c.roles(w, pf())
		"plan":
			return Cards8c.R().plan_order
		"air":
			return Cards8c.aircraft(w, pf())
		"cas":
			return Cards8c.casualties(w, CnFac.fac(w, fac))
		"pkg":
			var ks: Array = CnFac.conf().get("packages", {}).keys()
			ks.sort()
			return ks
		"team":
			var st = SimWorld.CnProgress7.state(w)
			var out := []
			if st != null:
				for k in st.ops:
					var o: Dictionary = st.ops[k]
					if int(o.fid) == pf() and bool(o.alive) and not out.has(int(o.team)):
						out.append(int(o.team))
			out.sort()
			return out
		"path":
			var ks: Array = SimWorld.CnProgress7.R().get("spec_paths", {}).keys()
			ks.sort()
			return ks
	return []


## The operator of the picked team that can take the picked path now (-1 none).
func spec_unit() -> int:
	var w := world()
	var tm = _pick(ids("team"), cur2)
	var path = _pick(ids("path"), cur3)
	if w == null or tm == null or path == null:
		return -1
	var st = SimWorld.CnProgress7.state(w)
	var ks: Array = st.ops.keys()
	ks.sort_custom(func(a, b): return int(a) < int(b))
	var first := -1
	for k in ks:
		var o: Dictionary = st.ops[k]
		if int(o.team) != int(tm) or int(o.fid) != pf() or not bool(o.alive):
			continue
		if first < 0:
			first = int(k)
		if SimWorld.CnProgress7.spec_reason(w, pf(), int(k), String(path)) == "":
			return int(k)
	return first


func _cmd(action: String) -> Dictionary:
	match action:
		"bar8c_rotate":
			var p = _pick(ids("post"), cur)
			return {} if p == null else {"type": "c8c_rotate", "post": String(p)}
		"bar8c_train":
			var r = _pick(ids("role"), cur2)
			return {} if r == null else {"type": "c8c_train", "role": String(r)}
		"bar8c_standto":
			return {"type": "c8c_standto"}
		"bar8c_adopt":
			return {"type": "c8c_plan", "plan": String(_pick(ids("plan"), cur2))}
		"air8c_service":
			var a = _pick(ids("air"), cur)
			return {} if a == null else {"type": "c8c_air_service", "unit_id": int(a)}
		"air8c_launch":
			var a = _pick(ids("air"), cur)
			return {} if a == null else {"type": "c8c_air_launch", "unit_id": int(a)}
		"air8c_launch_all":
			return {"type": "c8c_air_launch", "unit_id": -1}
		"air8c_recall":
			return {"type": "c8c_air_recall"}
		"air8c_cap":
			var w := world()
			var c := CnFac.zone(CnFac.fac(w, fac), "helipad").get_center() if w != null else Vector2.ZERO
			return {"type": "c8c_air_cap", "pos": [c.x, c.y]}
		"air8c_cap_end":
			return {"type": "c8c_air_cap", "clear": true}
		"aid8c_first":
			var c = _pick(ids("cas"), cur)
			return {} if c == null else {"type": "c8c_cas_first", "target": int(c)}
		"aid8c_evac":
			var c = _pick(ids("cas"), cur)
			return {} if c == null else {"type": "c8c_evac", "target": int(c)}
		"aid8c_medics":
			var w := world()
			var c := CnFac.zone(CnFac.fac(w, fac), "aid_station").get_center() if w != null else Vector2.ZERO
			return {"type": "c8c_medics", "pos": [c.x, c.y]}
		"lab8c_queue":
			var p = _pick(ids("pkg"), cur)
			return {} if p == null else {"type": "cn_lab_queue", "package": String(p)}
		"lab8c_tier":
			return {"type": "cn_lab_upgrade"}
		"lab8c_bays":
			return {"type": "fac_upgrade", "kind": "bays"}
		"lab8c_foundry":
			return {"type": "fac_upgrade", "kind": "foundry"}
		"lab8c_spec":
			var u := spec_unit()
			var path = _pick(ids("path"), cur3)
			return {} if u < 0 or path == null else {"type": "cn_specialize", "unit_id": u, "path": String(path)}
	return {}


## Refusal of the command a button would issue now ("" = allowed), from the system that owns the command.
func why(action: String) -> String:
	var w := world()
	if w == null or not _cmds.has(action):
		return "No command."
	var c: Dictionary = (_cmds[action] as Callable).call()
	if c.is_empty():
		return {"bar8c_rotate": "No watch posts yet.", "bar8c_train": "No Sentinels to train.", "air8c_service": "No helicopters / VTOLs.",
			"air8c_launch": "No helicopters / VTOLs.", "aid8c_first": "No casualties.", "aid8c_evac": "No casualties.",
			"lab8c_queue": "No packages.", "lab8c_spec": "No counter-nanite operators."}.get(action, "Nothing to do.")
	c.issuer = pf()
	c.building_id = fac
	var ty := String(c.type)
	if ty.begins_with("c8c_"):
		return Cards8c.reason(w, c)
	if ty == "cn_specialize":
		return SimWorld.CnProgress7.validate_command(w, c)
	return SimWorld.CnFacility.validate_command(w, c)


func _shown(w: SimWorld, f: int) -> bool:
	if mv == null:
		return false
	if mv.has_method("part_selected") and bool(mv.part_selected(f, String(PARTS[kind]))):
		return true
	if kind == "bar":
		var sel = mv.get("selection")
		if sel != null:
			for b in SimWorld.Sentinels7._parts_of(w, CnFac.fac(w, f), "cn_sentinel_barracks"):
				if (sel as Array).has(int(b.id)):
					return true
	return false


static func _secs(s: float) -> String:
	return "%dm%02ds" % [int(s) / 60, int(s) % 60] if s >= 60.0 else "%ds" % int(s)


func _fill(w: SimWorld) -> void:
	match kind:
		"bar":
			_fill_bar(w)
		"air":
			_fill_air(w)
		"aid":
			_fill_aid(w)
		"lab":
			_fill_lab(w)
	_l4.text = ("Click a point on the map..." if picking != "" else "")
	_l4.visible = picking != ""


func _fill_bar(w: SimWorld) -> void:
	var sm := Cards8c.barracks_summary(w, fac)
	last = sm
	var lines := []
	var pick = _pick(ids("post"), cur)
	for r in sm.get("posts", []):
		var who := []
		for u in r.who:
			who.append("%s %d%%%s" % [String(u.type).left(4).capitalize(), int(100.0 * float(u.fat)), " rot" if bool(u.rot) else ""])
		var tag := "> " if pick != null and String(r.id) == String(pick) else "  "
		lines.append("%s%s %d/%d  %s" % [tag, String(r.id).to_upper(), (r.who as Array).size(), int(r.slots), ", ".join(PackedStringArray(who.slice(0, 3)))])
	var vis := lines.slice(0, 6)
	if lines.size() > 6:
		vis.append("  ... %d more posts" % (lines.size() - 6))
	_l1.text = "WATCH ROSTER  shift change in %s%s\n%s" % [_secs(float(sm.get("shift_left_s", 0.0))), "  ALARM" if bool(sm.get("alarm", false)) else "", "\n".join(PackedStringArray(vis)) if not vis.is_empty() else "  no posts manned yet"]
	var tr: Dictionary = sm.get("train", {})
	var lv: Dictionary = sm.get("levels", {})
	var lvs := []
	for k in lv:
		lvs.append("%s %d" % [String(k).capitalize(), int(lv[k])])
	_l2.text = "Resting %d (%d in beds) / beds %d%s\nTraining: %s%s" % [int(sm.get("resting", 0)), int(sm.get("inside", 0)), int(sm.get("beds", 0)),
		"   STANDING TO" if bool(sm.get("standing_to", false)) else "",
		("%s %s" % [String(tr.role).capitalize(), pct(float(tr.total) - float(tr.left), float(tr.total))]) if not tr.is_empty() else "none",
		("   drilled: " + ", ".join(PackedStringArray(lvs))) if not lvs.is_empty() else ""]
	var opts := Cards8c.plan_options(w, fac)
	var po = opts[cur2 % opts.size()] if not opts.is_empty() else {}
	var men := []
	for k in ["entry", "gate", "post", "wall", "int", "qrf"]:
		if (po.get("men", {}) as Dictionary).has(k):
			men.append("%s %d" % [{"entry": "core", "gate": "gate", "post": "towers", "wall": "walls", "int": "inner", "qrf": "QRF"}[k], int(po.men[k])])
	_l3.text = "PATROL PLAN in force: %s\n> %s: %s\n  %s" % [String(Cards8c.R().plans[String(sm.get("plan", "balanced"))].name), String(po.get("name", "")), String(po.get("about", "")), "  ".join(PackedStringArray(men))]
	var r = _pick(ids("role"), cur2)
	_set_btn("bar8c_post", "POST " + (String(pick).to_upper() if pick != null else "-"), "" if pick != null else "No watch posts yet.")
	_set_btn("bar8c_rotate", "ROTATE", why("bar8c_rotate"))
	_set_btn("bar8c_role", "ROLE " + (String(r).to_upper() if r != null else "-"), "" if r != null else "No Sentinels yet.")
	_set_btn("bar8c_train", "TRAIN", why("bar8c_train"))
	_set_btn("bar8c_standto", "STAND TO", why("bar8c_standto"))
	_set_btn("bar8c_plan", "PLAN " + String(po.get("name", "-")).to_upper(), "")
	_set_btn("bar8c_adopt", "ADOPT", why("bar8c_adopt"))


func _fill_air(w: SimWorld) -> void:
	var sm := Cards8c.air_summary(w, fac)
	last = sm
	var pick = _pick(ids("air"), cur)
	var lines := []
	for r in (sm.get("rows", []) as Array).slice(0, 6):
		lines.append("%s%s #%d %s  fuel %d%% ammo %s hull %d%%%s" % ["> " if pick != null and int(r.id) == int(pick) else "  ", String(r.name), int(r.id), String(r.phase),
			int(100.0 * float(r.fuel)), ("%d%%" % int(100.0 * float(r.ammo))) if float(r.ammo) >= 0.0 else "-", int(100.0 * float(r.hp)), "  CAP" if bool(r.cap) else ""])
	_l1.text = "AIR ROSTER\n" + ("\n".join(PackedStringArray(lines)) if not lines.is_empty() else "  no helicopters / VTOLs")
	var cap: Dictionary = sm.get("cap", {})
	_l2.text = "Air patrol: " + ("over %d,%d (r %d)" % [int(cap.pos[0]), int(cap.pos[1]), int(cap.r)] if not cap.is_empty() else "none")
	_set_btn("air8c_pick", "AIRCRAFT " + (("#%d" % int(pick)) if pick != null else "-"), "" if pick != null else "No helicopters / VTOLs.")
	_set_btn("air8c_service", "SERVICE", why("air8c_service"))
	_set_btn("air8c_launch", "PICK POINT" if picking == "launch" else "LAUNCH", why("air8c_launch"))
	_set_btn("air8c_launch_all", "PICK POINT" if picking == "launch_all" else "LAUNCH ALL", why("air8c_launch_all"))
	_set_btn("air8c_recall", "RECALL ALL", why("air8c_recall"))
	_set_btn("air8c_cap", "PICK POINT" if picking == "cap" else "AIR PATROL", why("air8c_cap"))
	_set_btn("air8c_cap_end", "END PATROL", why("air8c_cap_end"))


func _fill_aid(w: SimWorld) -> void:
	var sm := Cards8c.aid_summary(w, fac)
	last = sm
	var pick = _pick(ids("cas"), cur)
	var lines := []
	var first: Array = sm.get("first", [])
	for r in (sm.get("rows", []) as Array).slice(0, 7):
		lines.append("%s%s #%d  %s%s%s" % ["> " if pick != null and int(r.id) == int(pick) else "  ", String(r.name), int(r.id),
			{3: "CRITICAL", 2: String(r.state), 1: "wounded"}[int(r.sev)] if int(r.sev) != 2 else String(r.state),
			"  FIRST" if first.has(int(r.id)) else "", "  evac" if bool(r.evac) else ""])
	_l1.text = "CASUALTY BOARD (%d)\n%s" % [(sm.get("rows", []) as Array).size(), "\n".join(PackedStringArray(lines)) if not lines.is_empty() else "  no casualties"]
	var md: Dictionary = sm.get("med", {})
	_l2.text = "Menders %d%s" % [int(sm.get("menders", 0)), ("   sent to %d,%d" % [int(md.pos[0]), int(md.pos[1])]) if not md.is_empty() else ""]
	_set_btn("aid8c_pick", "CASUALTY " + (("#%d" % int(pick)) if pick != null else "-"), "" if pick != null else "No casualties.")
	_set_btn("aid8c_first", "TREAT FIRST", why("aid8c_first"))
	_set_btn("aid8c_evac", "EVACUATE", why("aid8c_evac"))
	_set_btn("aid8c_medics", "PICK POINT" if picking == "medics" else "MEDICS", why("aid8c_medics"))


func _fill_lab(w: SimWorld) -> void:
	var F := CnFac.fac(w, fac)
	var lab: Dictionary = F.get("lab", {})
	var P: Dictionary = CnFac.conf().get("packages", {})
	var q := []
	for it in lab.get("queue", []):
		q.append("%s %ds" % [String(P.get(String(it.pkg), {}).get("name", it.pkg)), int(float(it.left) / SimWorld.TICK_RATE)])
	var pk = _pick(ids("pkg"), cur)
	var tiers: Array = CnFac.conf().get("lab_tiers", [])
	last = {"tier": int(lab.get("tier", 0)), "queue": q.size()}
	_l1.text = "RESEARCH  lab tier %d/%d%s\nQueue: %s" % [int(lab.get("tier", 0)), tiers.size(), "  (upgrading)" if float(lab.get("up", -1.0)) >= 0.0 else "",
		", ".join(PackedStringArray(q)) if not q.is_empty() else "empty"]
	var tm = _pick(ids("team"), cur2)
	var path = _pick(ids("path"), cur3)
	var u := spec_unit()
	var on := ""
	if u >= 0:
		var o := SimWorld.CnProgress7.op(w, u)
		on = "  next: #%d %s%s" % [u, String(o.get("role", "")), (" (%s %d)" % [String(o.path), int(o.tier)]) if String(o.get("path", "")) != "" else ""]
	_l2.text = "FIELD UPGRADES  team %s, path %s%s" % [str(tm) if tm != null else "-", String(SimWorld.CnProgress7.R().get("spec_paths", {}).get(str(path), {}).get("label", path)) if path != null else "-", on]
	_set_btn("lab8c_pkg", "PKG " + (String(P.get(String(pk), {}).get("name", pk)).to_upper() if pk != null else "-"), "" if pk != null else "No packages.")
	_set_btn("lab8c_queue", "QUEUE", why("lab8c_queue"))
	_set_btn("lab8c_tier", "LAB TIER", why("lab8c_tier"))
	for k in ["bays", "foundry"]:
		var n := (CnFac._ups().get(k, []) as Array).size() if CnFac._ups().get(k) is Array else 0
		var uq: Dictionary = F.get("g71upq", {})
		var lbl := "%s %d/%d" % [k.to_upper(), CnFac.up_tier(F, k), n]
		if String(uq.get("kind", "")) == k:
			lbl = "%s %ds" % [k.to_upper(), int(float(uq.left) / SimWorld.TICK_RATE)]
		_set_btn("lab8c_" + k, lbl, why("lab8c_" + k))
	_set_btn("lab8c_team", "TEAM " + (str(tm) if tm != null else "-"), "" if tm != null else "No counter-nanite teams.")
	_set_btn("lab8c_path", "PATH " + (String(path).to_upper() if path != null else "-"), "")
	_set_btn("lab8c_spec", "SPECIALISE", why("lab8c_spec"))


func _after_local() -> void:
	var w := world()
	if w != null and fac >= 0:
		_fill(w)
