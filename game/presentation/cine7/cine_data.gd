extends RefCounted
## G7 (CINE7): read-only data for the Last Protocol cinematics and the end-of-run screen (master scope 13.1, 13.5,
## section 10, 6.4 / 13.4). Everything here READS the world (LastProtocol state, Cores, Creep, CnProgress7 records)
## and returns plain dictionaries the cinematic modules turn into shot lists. Nothing here writes the sim.
##
## Which cinematic plays for which ending (one module per cinematic, presentation/cine7/cine_*.gd):
##   opening -> cine_opening.gd; total_purge -> cine_purge.gd; pyrrhic -> cine_pyrrhic.gd; capture_core ->
##   cine_capture.gd; victory -> cine_victory.gd; defeat_creep -> cine_defeat_creep.gd; defeat_countdown ->
##   cine_defeat_countdown.gd; defeat_facility -> cine_defeat_facility.gd.

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const Cores = preload("res://sim/systems/cores.gd")
const Creep = preload("res://sim/systems/creep.gd")
const CN_PROG_PATH := "res://sim/systems/cn_progress7.gd"

const MODULES := {
	"opening": "res://presentation/cine7/cine_opening.gd",
	"total_purge": "res://presentation/cine7/cine_purge.gd",
	"pyrrhic": "res://presentation/cine7/cine_pyrrhic.gd",
	"capture_core": "res://presentation/cine7/cine_capture.gd",
	"victory": "res://presentation/cine7/cine_victory.gd",
	"defeat_creep": "res://presentation/cine7/cine_defeat_creep.gd",
	"defeat_countdown": "res://presentation/cine7/cine_defeat_countdown.gd",
	"defeat_facility": "res://presentation/cine7/cine_defeat_facility.gd",
}

const ROLE_LABELS := {"leader": "Team leader", "team_leader": "Team leader", "second": "Second-in-command",
	"radio": "Radio operator", "deploy": "Deployment specialist", "deployment": "Deployment specialist",
	"scanner": "Scanner technician", "ew": "EW specialist", "security": "Security gunner", "gunner": "Security gunner",
	"medic": "Combat medic", "engineer": "Combat engineer", "medic_engineer": "Combat medic / engineer",
	"operator": "Tactical operator", "driver": "APC driver"}

## Core positions seen this session (seed -> {ix: Vector2}): a destroyed core leaves no entity, so the HUD notes them
## while they live and the endings can still frame where they stood. Presentation memory only.
static var _core_seen: Dictionary = {}


static func module_path(id: String) -> String:
	return String(MODULES.get(id, MODULES.victory if not id.begins_with("defeat") else MODULES.defeat_creep))


static func module(id: String) -> Script:
	return load(module_path(id)) as Script


## Called by the HUD refresh (cheap: 3 cores).
static func note_cores(w: SimWorld) -> void:
	if w == null:
		return
	var m: Dictionary = _core_seen.get(w.seed_value, {})
	for c in Cores.list(w):
		if bool(c.alive) and c.pos != Vector2.ZERO:
			m[int(c.ix)] = Vector2(c.pos)
	_core_seen[w.seed_value] = m


static func _v2(p) -> Vector2:
	if p is Vector2:
		return p
	if p is Vector2i:
		return Vector2(p) + Vector2(0.5, 0.5)
	if p is Array and (p as Array).size() >= 2:
		return Vector2(float(p[0]), float(p[1])) + Vector2(0.5, 0.5)
	if p is Dictionary and (p as Dictionary).has("x"):
		return Vector2(float(p.x), float(p.y))
	return Vector2(-1, -1)


## Everything a cinematic needs, read once (positions in world tiles).
static func gather(w: SimWorld, result: Dictionary = {}) -> Dictionary:
	var d := {"map_w": 128, "map_h": 128, "center": Vector2(64, 64), "rings": [], "facility": Vector2(64, 64),
		"cores": [], "nests": [], "creep": [], "creep_cov": 0.0, "seed": 0, "result": result, "remembered": [],
		"base_ok": false, "cd_left": 0.0, "teams_total": 0, "teams_lost": 0, "rings_fallen": 0, "captured": false,
		"origin_found": false, "minutes": 0}
	if w == null:
		return d
	d.map_w = int(w.map.w)
	d.map_h = int(w.map.h)
	d.seed = w.seed_value
	d.center = Vector2(d.map_w, d.map_h) * 0.5
	var s = LastProtocol.st(w)
	if s is Dictionary and (s as Dictionary).has("base"):
		d.base_ok = true
		d.center = _v2(s.base.center)
		for r in s.base.rings:
			var rc: Rect2i = r.rect
			d.rings.append({"name": String(r.get("name", "")), "rect": Rect2(rc), "fallen": bool(r.get("fallen", false))})
		var fe = w.entities.get(int(s.get("facility", -1)))
		d.facility = Vector2(fe.pos) if fe != null else d.center
		d.cd_left = float(s.get("cd_left", 0.0))
		d.teams_total = int(s.get("teams_total", 0))
		d.teams_lost = int(s.get("teams_lost", 0))
		d.rings_fallen = int(s.get("rings_fallen", 0))
		d.captured = bool(s.get("captured", false))
		d.origin_found = bool(s.get("origin_found", false))
		d.minutes = int(float(w.tick - int(s.get("t0", 0))) * SimWorld.DT / 60.0)
	# cores: live ones from Cores, dead ones from what the HUD saw, then the map's core zones
	note_cores(w)
	var seen: Dictionary = _core_seen.get(w.seed_value, {})
	var zones: Array = []
	var lpd = w.map.get("lp", {}) if w.map is Dictionary else {}
	if lpd is Dictionary:
		zones = lpd.get("cores", [])
	var cl := Cores.list(w)
	for c in cl:
		var p: Vector2 = Vector2(c.pos)
		if not bool(c.alive) or p == Vector2.ZERO:
			p = seen.get(int(c.ix), _v2(zones[int(c.ix)]) if int(c.ix) < zones.size() else Vector2(-1, -1))
		if p.x < 0.0:
			continue
		d.cores.append({"ix": int(c.ix), "pos": p, "alive": bool(c.alive), "walking": bool(c.walking)})
	if (d.cores as Array).is_empty():
		for i in zones.size():
			d.cores.append({"ix": i, "pos": _v2(zones[i]), "alive": true, "walking": false})
	# seed nests (one point per nest cluster) and a coarse creep field
	var np: Array = []
	for sd in Creep.seeds(w):
		if String(sd.get("kind", "")) != "nest":
			continue
		var p2 := Vector2(sd.pos)
		var near := false
		for q in np:
			if (q as Vector2).distance_to(p2) < 10.0:
				near = true
				break
		if not near:
			np.append(p2)
	d.nests = np
	d.creep = creep_field(w, 8)
	d.creep_cov = Creep.coverage(w)
	if not result.is_empty():
		d.remembered = remembered_rows(w, result.get("remembered", []))
	return d


## Creep sampled every `step` tiles: [Vector3(x, y, value 0..1)] for cells with creep (pure read).
static func creep_field(w: SimWorld, step: int = 8) -> Array:
	var out := []
	if Creep.st(w) == null:
		return out
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	for y in range(step / 2, mh, step):
		for x in range(step / 2, mw, step):
			var v := Creep.at(w, Vector2i(x, y))
			if v > 0.2:
				out.append(Vector3(x, y, v))
	return out


## Every dead named operator of the Last Protocol side: the result's call signs (LastProtocol's roster: operators
## seen on the field) plus any operator CnProgress7 recorded as dead who never got onto that roster (crews killed
## inside their APC before they ever dismounted). Order: the result's order, then the extras by unit id.
static func remembered_call_signs(w: SimWorld, call_signs: Array) -> Array:
	var out: Array = []
	for cs in call_signs:
		if not out.has(String(cs)):
			out.append(String(cs))
	if w == null:
		return out
	var st = w.sys_state.get("cnprog7")
	var s = LastProtocol.st(w)
	if not (st is Dictionary) or not (s is Dictionary):
		return out
	var fid := int(s.get("fid", 0))
	var keys: Array = (st.get("ops", {}) as Dictionary).keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for k in keys:
		var o: Dictionary = st.ops[k]
		var cs2 := String(o.get("cs", ""))
		if cs2 != "" and not bool(o.get("alive", true)) and int(o.get("fid", fid)) == fid and not out.has(cs2):
			out.append(cs2)
	return out


## The Remembered list with names (remembered_call_signs), enriched from CnProgress7's operator records.
static func remembered_rows(w: SimWorld, call_signs: Array) -> Array:
	call_signs = remembered_call_signs(w, call_signs)
	var ops: Dictionary = {}
	if w != null:
		var st = w.sys_state.get("cnprog7")
		if st is Dictionary:
			ops = st.get("ops", {})
	var by_cs := {}
	var keys := ops.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for k in keys:
		var o: Dictionary = ops[k]
		var cs := String(o.get("cs", ""))
		if cs != "" and (not by_cs.has(cs) or not bool(o.get("alive", true))):
			by_cs[cs] = o
	var teams: Dictionary = {}
	if w != null and w.sys_state.get("cnprog7") is Dictionary:
		teams = w.sys_state.cnprog7.get("teams", {})
	var out := []
	for cs in call_signs:
		var row := {"cs": String(cs), "name": "", "role": "", "team": "", "kills": 0, "missions": 0}
		if by_cs.has(String(cs)):
			var o: Dictionary = by_cs[String(cs)]
			row.name = String(o.get("name", ""))
			row.role = String(ROLE_LABELS.get(String(o.get("role", "")), String(o.get("role", "")).capitalize()))
			row.kills = int(o.get("kills", 0))
			row.missions = int(o.get("missions", 0))
			var tr: Dictionary = teams.get(str(int(o.get("team", -1))), {})
			row.team = String(tr.get("name", ""))
		out.append(row)
	return out


static func row_text(r: Dictionary) -> String:
	var t := String(r.get("cs", ""))
	if String(r.get("name", "")) != "":
		t += "  -  " + String(r.name)
	return t


static func row_sub(r: Dictionary) -> String:
	var parts := PackedStringArray()
	if String(r.get("role", "")) != "":
		parts.append(String(r.role))
	if String(r.get("team", "")) != "":
		parts.append(String(r.team))
	return "  /  ".join(parts)


## The map tile at the middle of a list of points (fallback: center).
static func mid(pts: Array, fallback: Vector2) -> Vector2:
	if pts.is_empty():
		return fallback
	var acc := Vector2.ZERO
	for p in pts:
		acc += Vector2(p)
	return acc / float(pts.size())


static func core_pts(d: Dictionary, alive_only: bool = false) -> Array:
	var out := []
	for c in d.cores:
		if not alive_only or bool(c.alive):
			out.append(Vector2(c.pos))
	return out


## Zoom that fits a tile span (diamond width ~ 64 px per tile) into a 1280-wide view.
static func zoom_for_span(tiles: float) -> float:
	return clampf(1280.0 / maxf(tiles * 64.0, 1.0), 0.08, 2.0)
