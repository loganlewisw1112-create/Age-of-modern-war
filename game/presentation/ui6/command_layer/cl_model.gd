extends RefCounted
## G6.1 command layer model (owner: PLAN61): world snapshot for drawing (formations as NATO symbols,
## plans) and the draft plan being drawn. Pure functions of the world; read only while the world is
## readable (HUD update). Drawing code never touches the world.

const Plans = preload("res://sim/systems/plans.gd")
const Companies = preload("res://sim/systems/companies.gd")

## Plan colours (per plan id).
const COLS := [Color("e3a83a"), Color("6fa8dc"), Color("86c85e"), Color("e0605a"), Color("c38be0"),
	Color("4fc3d9"), Color("e8d25a"), Color("d08a4a")]
## NATO echelon marks: platoon ●●●, company I, army XX.
const ECHELON := {"platoon": "•••", "company": "I", "army": "XX"}
const TIMING_LABELS := ["Go now", "On signal", "H + 30 s"]
const INTENT_LABELS := ["attack", "defend", "raid", "screen", "withdraw"]

var formations: Array = []   # [{f: {kind, id}, pos: Vector2 (world), label, officer, units}]
var plans: Array = []        # deep copies of the side's plans (newest last)
var fid := 0
var draft := {}              # {formation, intent, objectives: [Vector2i], axis: [Vector2i], phase_lines: [...], timing, main_effort}


static func col(pid: int) -> Color:
	return COLS[absi(pid) % COLS.size()]


static func fname(f: Dictionary) -> String:
	if f.is_empty():
		return ""
	return "%s %d" % [String(f.kind).capitalize(), int(f.id)]


## Rebuilds the snapshot from the world (side fid).
func refresh(w: SimWorld, side: int) -> void:
	fid = side
	formations = []
	for a in Companies.armies_of(w, side):
		_add(w, {"kind": "army", "id": int(a.id)}, int(a.get("commander", -1)), "Army %d" % int(a.id))
	for c in Companies.companies_of(w, side):
		_add(w, {"kind": "company", "id": int(c.id)}, int(c.get("captain", -1)), String(c.get("name", "Company %d" % int(c.id))))
	if w.sys_state.has("ops"):
		var gids: Array = w.sys_state.ops.groups.keys()
		gids.sort()
		for gid in gids:
			var g: Dictionary = w.sys_state.ops.groups[gid]
			if int(g.owner) == side:
				_add(w, {"kind": "platoon", "id": int(gid)}, int(g.officer), "Platoon %d" % int(gid))
	plans = []
	for p in Plans.plans_of(w, side):
		var q: Dictionary = p.duplicate(true)
		q.line = Plans.status_line(p)
		plans.append(q)
	if not draft.is_empty() and Plans.formation_owner(w, draft.formation) != side:
		draft = {}


func _add(w: SimWorld, f: Dictionary, officer: int, label: String) -> void:
	var units := Plans.formation_units(w, f)
	if units.is_empty():
		return
	var e = w.entities.get(officer)
	var pos: Vector2 = e.pos if e != null and e.kind == "unit" else w.entities[units[0]].pos
	formations.append({"f": f, "pos": pos, "label": label, "officer": officer, "units": units.size()})


## Formation symbol nearest world point p within r tiles ({} when none). Platoons win ties (drawn on top).
func formation_at(p: Vector2, r: float = 1.6) -> Dictionary:
	var best := {}
	var bd := r
	for fm in formations:
		var d := (fm.pos as Vector2).distance_to(p)
		if d <= bd:
			bd = d
			best = fm
	return best


func begin_draft(f: Dictionary) -> void:
	draft = {"formation": f.duplicate(), "intent": "attack", "objectives": [], "axis": [], "phase_lines": [],
		"timing": 0, "main_effort": false}


func has_draft() -> bool:
	return not draft.is_empty()


func add_objective(c: Vector2i) -> void:
	if (draft.objectives as Array).size() < Plans.MAX_OBJ:
		draft.objectives.append(c)


func add_axis_point(c: Vector2i) -> void:
	var ax: Array = draft.axis
	if ax.size() < Plans.MAX_AXIS and (ax.is_empty() or Vector2(ax[ax.size() - 1]).distance_to(Vector2(c)) >= 2.0):
		ax.append(c)


func add_phase_line(a: Vector2i, b: Vector2i) -> void:
	var n := (draft.phase_lines as Array).size()
	if n < Plans.MAX_PL and a != b:
		draft.phase_lines.append({"name": "PL " + Plans.PL_NAMES[n], "points": [a, b]})


func clear_draft_marks() -> void:
	if has_draft():
		draft.objectives = []
		draft.axis = []
		draft.phase_lines = []


## The issue_plan payload for the draft.
func draft_plan() -> Dictionary:
	var tm := {"mode": "now"}
	match int(draft.timing):
		1:
			tm = {"mode": "signal"}
		2:
			tm = {"mode": "at", "t": 30.0}
	var pls := []
	for pl in draft.phase_lines:
		pls.append({"name": String(pl.name), "points": _arr(pl.points)})
	return {"formation": draft.formation.duplicate(), "intent": String(draft.intent), "objectives": _arr(draft.objectives),
		"axis": _arr(draft.axis), "phase_lines": pls, "timing": tm, "main_effort": bool(draft.main_effort)}


static func _arr(cells: Array) -> Array:
	var out := []
	for c in cells:
		out.append([int(c.x), int(c.y)])
	return out


## Quick officer order -> issue_plan payload. kind: attack | hold | withdraw | screen; a/b cells (b for screen).
static func quick_plan(f: Dictionary, kind: String, a: Vector2i, b: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var p := {"formation": f.duplicate(), "objectives": [[a.x, a.y]], "axis": [], "phase_lines": [], "timing": {"mode": "now"}}
	match kind:
		"attack":
			p.intent = "attack"
		"hold":
			p.intent = "defend"
		"withdraw":
			p.intent = "withdraw"
		"screen":
			p.intent = "screen"
			p.objectives = []
			p.phase_lines = [{"name": "SCREEN", "points": [[a.x, a.y], [b.x, b.y]]}]
	return p
