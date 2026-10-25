extends RefCounted
## Doctrine shared helpers (owner: AI7-DOC). CONTRACTS_G6 section 16 (D40), section 3.6 reason tags.
## Fairness (same rules as players): own entities by id with the owner checked, enemy information only
## from ctx.visible (= w.visible_enemies(fid)) and w.memory[fid]; every order goes through U.submit.
## Numbers: doctrine_rules.json next to this file (PROVISIONAL), or Content.rules().g6_doctrine once ORCH
## adopts the block. State: w.ai_state[fid].doctrine (CONTRACTS_G6 section 6), created on first use only,
## so a side that never fields a formation keeps its G5 state (and hash) unchanged.

const U = preload("res://sim/ai/ai_util.gd")

const TAGS := ["overwatch_set", "high_ground_taken", "flank", "assault_phase", "suppress", "breach",
	"reserve_commit", "retreat", "regroup", "raid", "sabotage", "officer_hunt", "exfil_done", "defence_depth"]
const RULES_PATH := "res://sim/ai/doctrine/doctrine_rules.json"
const LOG_MAX := 12
const DEFAULTS := {"phase_line_spacing": 9.0, "arrive_dist": 3.5, "standoff": 9.0, "contact_range": 11.0,
	"objective_radius": 6.0, "key_terrain_radius": 10.0, "position_radius": 5.0, "flank_angle_deg": 55.0,
	"flank_dist": 9.0, "axis_offset": 8.0, "recon_ticks": 160, "suppress_ticks": 200, "assault_timeout": 2400,
	"advance_timeout": 6000, "consolidate_ticks": 400, "reorder_ticks": 120, "launch_ratio": 1.3,
	"launch_strength": 0.75, "commit_strength": 0.6, "stall_ticks": 1200, "retreat_strength": 0.4,
	"retreat_ratio": 0.45, "regroup_strength": 0.7, "regroup_ticks": 1800, "hold_depth": 12.0,
	"mission_every": 1800, "mission_first_tick": 600, "raid_ticks": 400, "observe_ticks": 200,
	"mission_timeout": 4800, "exfil_radius": 5.0, "safe_radius": 6.0, "officer_hunt_range": 40.0,
	"mine_avoid": 2.0, "breach_width": 2, "breach_timeout": 900, "score_height": 3.0, "score_cover": 2.0,
	"score_los": 1.5, "score_dist": 0.15, "score_mine": 6.0}

static var _r := {}


## Rules with defaults filled in (read once; static content).
static func R() -> Dictionary:
	if _r.is_empty():
		var out: Dictionary = DEFAULTS.duplicate(true)
		var src = Content.rules().get("g6_doctrine", null)
		if typeof(src) != TYPE_DICTIONARY and FileAccess.file_exists(RULES_PATH):
			src = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
		if typeof(src) == TYPE_DICTIONARY:
			for k in src:
				if String(k) != "_meta":
					out[k] = src[k]
		_r = out
	return _r


static func num(key: String) -> float:
	return float(R().get(key, DEFAULTS.get(key, 0.0)))


static func ticks(key: String) -> int:
	return int(num(key))


# ================================================================ state + decisions
## st.doctrine, created on demand.
static func dstate(st: Dictionary) -> Dictionary:
	if not st.has("doctrine"):
		st.doctrine = {"ver": 1, "forms": {}, "missions": {}, "detached": {}, "tags": {}, "log": [], "front": {},
			"next_mission": 0, "decisions": 0}
	return st.doctrine


## Every doctrine decision: event AiDecision {fid, tag, unit_ids, reason} (soak gates count the tags),
## a per-tag counter and a short log line for the inspector.
static func decide(w: SimWorld, fid: int, st: Dictionary, tag: String, ids: Array, reason: String) -> void:
	var d := dstate(st)
	var tags: Dictionary = d.tags
	tags[tag] = int(tags.get(tag, 0)) + 1
	d.decisions = int(d.decisions) + 1
	var idl := []
	for i in ids:
		idl.append(int(i))
	idl.sort()
	w.emit("AiDecision", {"fid": fid, "tag": tag, "unit_ids": idl, "reason": reason})
	var lg: Array = d.log
	lg.append("t=%d %s: %s" % [w.tick, tag, reason])
	while lg.size() > LOG_MAX:
		lg.pop_front()


# ================================================================ own units
## Own live unit by id, or null.
static func unit(w: SimWorld, fid: int, id: int):
	var e = w.entities.get(id)  # AI-FAIR: own (owner checked on the next line)
	if e == null or e.kind != "unit" or int(e.owner) != fid:
		return null
	return e


## Own live units that can manoeuvre now (not wounded, broken, garrisoned or a launched drone).
static func movers(w: SimWorld, fid: int, ids: Array) -> Array:
	var out := []
	for id in ids:
		var e = unit(w, fid, int(id))
		if e == null or bool(e.get("wounded", false)) or bool(e.get("broken", false)):
			continue
		if int(e.get("garrisoned_in", -1)) >= 0 or bool(Content.unit(String(e.def)).get("launched_drone", false)):
			continue
		out.append(e)
	return out


static func alive_count(w: SimWorld, fid: int, ids: Array) -> int:
	var n := 0
	for id in ids:
		if unit(w, fid, int(id)) != null:
			n += 1
	return n


static func ids_of(us: Array) -> Array:
	var out := []
	for e in us:
		out.append(int(e.id))
	return out


static func centroid(us: Array, dflt: Vector2 = Vector2.ZERO) -> Vector2:
	if us.is_empty():
		return dflt
	var s := Vector2.ZERO
	for e in us:
		s += e.pos
	return s / float(us.size())


static func idle(e: Dictionary) -> bool:
	return not bool(e.get("moving", false)) and ["idle", "hold"].has(String(e.order.get("type", "idle")))


static func power(us: Array) -> float:
	var p := 0.0
	for e in us:
		p += float(maxi(U.pop_of(String(e.def)), 1))
	return p


# ================================================================ intel (fair)
static func visible(w: SimWorld, fid: int, ctx: Dictionary) -> Array:
	if ctx.has("visible"):
		return ctx.visible
	return w.visible_enemies(fid)


static func near(list: Array, p: Vector2, r: float) -> Array:
	var out := []
	for e in list:
		var q: Vector2 = e.pos
		if q.distance_to(p) <= r:
			out.append(e)
	return out


## Last-seen enemy buildings of this side (fog memory), ascending id: [{id, def, pos}].
static func known_buildings(w: SimWorld, fid: int) -> Array:
	var out := []
	var mem: Dictionary = w.memory.get(fid, {})
	var keys := mem.keys()
	keys.sort()
	for k in keys:
		var m: Dictionary = mem[k]
		out.append({"id": int(k), "def": String(m.get("def", "")), "pos": m.get("pos", Vector2.ZERO)})
	return out


# ================================================================ orders
## Submits one order for ids, unless the same order (type + target cell) went out within reorder_ticks
## and the units are still busy with it. mem keeps the last order per key (inside the formation state).
static func order(w: SimWorld, fid: int, st: Dictionary, mem: Dictionary, key: String, us: Array, type: String,
		target: Vector2, extra: Dictionary = {}) -> bool:
	if us.is_empty():
		return false
	var cell := Vector2i(floori(target.x), floori(target.y))
	var last: Dictionary = mem.get(key, {})
	if not last.is_empty() and String(last.t) == type and int(last.x) == cell.x and int(last.y) == cell.y:
		var busy := false
		for e in us:
			if not idle(e):
				busy = true
				break
		if busy or w.tick - int(last.tick) < ticks("reorder_ticks"):
			return false
	var cmd := {"type": type, "unit_ids": ids_of(us), "target": target}
	cmd.merge(extra, true)
	if not U.submit(w, fid, st, cmd, "doc:" + key):
		return false
	mem[key] = {"t": type, "x": cell.x, "y": cell.y, "tick": w.tick}
	return true


static func formation(w: SimWorld, fid: int, st: Dictionary, mem: Dictionary, key: String, us: Array, f: String) -> void:
	if us.is_empty() or String(mem.get(key + ":f", "")) == f:
		return
	if U.submit(w, fid, st, {"type": "set_formation", "unit_ids": ids_of(us), "formation": f}, "doc:f:" + key):
		mem[key + ":f"] = f
