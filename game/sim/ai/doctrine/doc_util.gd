extends RefCounted
## Doctrine shared helpers (owner: AI7-DOC). CONTRACTS_G6 section 16 (D40), section 3.6 reason tags.
## Fairness (same rules as players): own entities by id with the owner checked, enemy information only
## from ctx.visible (= w.visible_enemies(fid)) and w.memory[fid]; every order goes through U.submit.
## Numbers: doctrine_rules.json next to this file (PROVISIONAL), or Content.rules().g6_doctrine once ORCH
## adopts the block. State: w.ai_state[fid].doctrine (CONTRACTS_G6 section 6), created on first use only,
## so a side that never fields a formation keeps its G5 state (and hash) unchanged.

const U = preload("res://sim/ai/ai_util.gd")
const L = preload("res://sim/ai/ai_g6_lib.gd")

const TAGS := ["overwatch_set", "high_ground_taken", "flank", "assault_phase", "suppress", "breach",
	"reserve_commit", "retreat", "regroup", "raid", "sabotage", "officer_hunt", "exfil_done", "defence_depth",
	"contact", "smoke", "travelling"]  # G6.1 OFF61: react-to-contact, smoke and travelling tags
const RULES_PATH := "res://sim/ai/doctrine/doctrine_rules.json"
const LOG_MAX := 12
const DEFAULTS := {"phase_line_spacing": 9.0, "arrive_dist": 3.5, "standoff": 9.0, "contact_range": 11.0,
	"objective_radius": 6.0, "key_terrain_radius": 10.0, "position_radius": 5.0, "flank_angle_deg": 65.0,
	"flank_dist": 9.0, "axis_offset": 8.0, "recon_ticks": 160, "suppress_ticks": 200, "assault_timeout": 2400,
	"advance_timeout": 6000, "consolidate_ticks": 400, "reorder_ticks": 120, "launch_ratio": 1.3,
	"launch_strength": 0.75, "commit_strength": 0.6, "stall_ticks": 1200, "retreat_strength": 0.4,
	"retreat_ratio": 0.45, "regroup_strength": 0.7, "regroup_ticks": 1800, "hold_depth": 12.0,
	"mission_every": 1800, "mission_retry": 200, "mission_first_tick": 600, "raid_ticks": 400, "observe_ticks": 200,
	"mission_timeout": 4800, "exfil_radius": 5.0, "safe_radius": 6.0, "officer_hunt_range": 40.0,
	"mine_avoid": 2.0, "breach_width": 2, "breach_timeout": 900, "score_height": 3.0, "score_cover": 2.0,
	"score_los": 1.5, "score_dist": 0.15, "score_mine": 6.0,
	# G6.1 OFF61 battle drills (PROVISIONAL)
	"stack_dist": 3.0, "stack_radius": 4.0, "stack_ratio": 0.7, "stack_timeout": 500, "breach_search": 9.0,
	"enter_dist": 2.0, "react_ticks": 60, "contact_cooldown": 300, "assault_odds": 0.6, "flank_odds": 1.5,
	"break_ticks": 300, "break_dist": 8.0, "contact_flank_dist": 8.0, "flank_timeout": 500,
	"officer_back": 3.0, "leaderless_ticks": 100, "player_override_ticks": 400, "route_cell": 4,
	"route_mine_cost": 60.0, "route_exposure_cost": 6.0, "route_cover_bonus": 1.5, "route_height_bonus": 1.0,
	"phase_halt_ticks": 40, "regroup_radius": 5.0, "tempo_strength": 0.6, "resupply_ammo": 0.25,
	"resupply_strength": 0.35, "counter_attack_odds": 0.8, "fallback_strength": 0.55, "alt_offset": 6.0,
	"arty_spread": 1.6, "narrow_width": 3, "drill_every": 10, "report_every": 200, "travel_dist": 22.0,
	"arty_range": 36.0, "pinned_hold_frac": 0.5, "fit_assault_frac": 0.5}

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
		if e.has("player_order_tick") and player_held(w, e):
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
	if not last.is_empty() and String(last.t) == type and int(last.x) == cell.x and int(last.y) == cell.y 			and int(last.get("n", us.size())) == us.size():
		var busy := false
		for e in us:
			if not idle(e):
				busy = true
				break
		if busy or w.tick - int(last.tick) < ticks("reorder_ticks"):
			return false
	var cmd := {"type": type, "unit_ids": ids_of(us), "target": target}
	cmd.merge(extra, true)
	if not submit(w, fid, st, cmd, "doc:" + key):
		return false
	mem[key] = {"t": type, "x": cell.x, "y": cell.y, "tick": w.tick, "n": us.size()}
	return true


## spacing (SQUAD61 set_formation spacing 1.0..2.5): wider under artillery; 1.0 resets a widened one.
static func formation(w: SimWorld, fid: int, st: Dictionary, mem: Dictionary, key: String, us: Array, f: String,
		spacing: float = 1.0) -> void:
	f = formation_ok(f)
	var tag := f if spacing == 1.0 else "%s@%.1f" % [f, spacing]
	var had := String(mem.get(key + ":f", ""))
	if us.is_empty() or had == tag:
		return
	var cmd := {"type": "set_formation", "unit_ids": ids_of(us), "formation": f}
	if spacing != 1.0 or had.contains("@"):
		cmd.spacing = clampf(spacing, 1.0, 2.5)
	if submit(w, fid, st, cmd, "doc:f:" + key):
		mem[key + ":f"] = tag


# ================================================================ G6.1 OFF61 helpers
## U.submit for an AI side (st with the AI bookkeeping); a direct w.submit for a side driven only by
## orders (the player's AI generals, CommandNet orders to a side without an AI controller).
static func submit(w: SimWorld, fid: int, st: Dictionary, cmd: Dictionary, key: String) -> bool:
	if st.has("pending"):
		return U.submit(w, fid, st, cmd, key)
	cmd.issuer = fid
	cmd.ai_cmd = "doctrine"
	var r: Dictionary = w.submit(cmd)
	return bool(r.get("ok", false))


static var _forms := []


## A formation the order system accepts: SQUAD61 may add echelon / file; until then they fall back to
## wedge / column (Orders.FORMATIONS read at run time, never preloaded).
static func formation_ok(f: String) -> String:
	if _forms.is_empty():
		var s = load("res://sim/systems/orders.gd")
		var m: Dictionary = s.get_script_constant_map() if s != null else {}
		_forms = Array(m.get("FORMATIONS", ["line", "wedge", "column"]))
	if _forms.has(f):
		return f
	return {"echelon": "wedge", "file": "column", "travel": "column", "vee": "wedge"}.get(f, "wedge")


## True while the player's own order to e is fresher than the override window, or the player put the
## unit on Hold Position: the doctrine never moves such a unit (G61_COMMON player control first).
static func player_held(w: SimWorld, e: Dictionary) -> bool:
	if not e.has("player_order_tick"):
		return false
	if w.tick - int(e.player_order_tick) < ticks("player_override_ticks"):
		return true
	return String(e.get("order", {}).get("type", "")) == "hold"


static func is_officer(e: Dictionary) -> bool:
	var r := String(e.get("rank_role", ""))
	return r == "lieutenant" or r == "captain" or r == "commander" or bool(Content.unit(String(e.def)).get("is_officer", false))


## REAL61 leader traits of unit id (Array of trait names; [] = neutral until REAL61 posts its API).
static func traits(w: SimWorld, id: int) -> Array:
	var e = w.entities.get(id)  # AI-FAIR: own officer
	if e == null:
		return []
	var s = _sys("veterancy")
	if s != null:
		for fn in ["traits", "traits_of", "leader_traits"]:
			if _has(s, fn):
				var t = s.callv(fn, [w, id])
				if typeof(t) == TYPE_ARRAY:
					return t
				if typeof(t) == TYPE_DICTIONARY:
					return (t as Dictionary).keys()
	var t2 = e.get("traits", [])
	return t2 if typeof(t2) == TYPE_ARRAY else []


## REAL61 experience level of unit id (0 = green; neutral 0 until REAL61 posts its API).
static func vet(w: SimWorld, id: int) -> int:
	var e = w.entities.get(id)  # AI-FAIR: own unit
	if e == null:
		return 0
	var s = _sys("veterancy")
	if s != null:
		for fn in ["rank", "level_of", "vet_level"]:
			if _has(s, fn):
				return int(s.callv(fn, [w, id]))
	return int(e.get("vet", e.get("veterancy", 0)))


## Report one short readable line up the chain from officer from_id (CHAIN61 CommandNet.report when
## present: report(w, fid, from_id, kind, text, data)).
static func report_up(w: SimWorld, fid: int, from_id: int, kind: String, line: String, data: Dictionary = {}) -> void:
	var s = _sys("command_net")
	if s != null and _has(s, "report"):
		s.callv("report", [w, fid, from_id, kind, line, data])


## Believed enemy strength near pos: what this side sees (pop-weighted power) or, when higher, what
## CHAIN61 Intel believes is there (strength_at); the AI acts on belief, not on the truth.
static func belief_power(w: SimWorld, fid: int, vis: Array, pos: Vector2, r: float) -> float:
	var seen := 0.0
	for e in near(vis, pos, r):
		if String(e.get("kind", "unit")) == "unit":
			seen += float(maxi(U.pop_of(String(e.def)), 1))
		else:
			seen += 2.0
	var s = _sys("intel")
	if s != null and _has(s, "strength_at"):
		seen = maxf(seen, float(s.callv("strength_at", [w, fid, pos, r])))
	return seen


## Ammo fraction left across units (1.0 when none tracks ammo).
static func ammo_frac(us: Array) -> float:
	var have := 0.0
	var cap := 0.0
	for e in us:
		if not e.has("ammo"):
			continue
		var d: Dictionary = Content.unit(String(e.def))
		var mx := float(d.get("ammo_max", d.get("ammo", 0)))
		if mx <= 0.0:
			continue
		have += minf(float(e.ammo), mx)
		cap += mx
	return have / cap if cap > 0.0 else 1.0


# ================================================================ G6.1 OFF61-2: REAL61 human factors
## True when REAL61 says e is pinned by suppression (Morale.is_pinned; e.pinned before it lands): a
## pinned element can't bound or manoeuvre, it fires from where it is.
static func pinned(w: SimWorld, e: Dictionary) -> bool:
	var s = _sys("morale")
	if s != null and _has(s, "is_pinned"):
		return bool(s.is_pinned(w, e))
	return bool(e.get("pinned", false))


## True when e is fresh enough to assault (REAL61 Fatigue.can_assault; neutral true until it lands).
static func can_assault(w: SimWorld, e: Dictionary) -> bool:
	var s = _sys("fatigue")
	if s != null and _has(s, "can_assault"):
		return bool(s.can_assault(w, e))
	return true


## The units of us free to move (not pinned).
static func unpinned(w: SimWorld, us: Array) -> Array:
	return us.filter(func(e) -> bool: return not pinned(w, e))


## The units of us able to assault (not pinned, not exhausted). The rest support by fire from where they are.
static func fresh(w: SimWorld, us: Array) -> Array:
	return us.filter(func(e) -> bool: return not pinned(w, e) and can_assault(w, e))


## Fraction of us able to assault (1.0 for an empty list).
static func fit_frac(w: SimWorld, us: Array) -> float:
	if us.is_empty():
		return 1.0
	return float(fresh(w, us).size()) / float(us.size())


## Echelon toward the exposed flank: echelon_right when the threat at v lies right of axis, else left
## (screen coordinates, y down). "echelon" when the order system has no sided echelon.
static func echelon_for(axis: Vector2, v: Vector2) -> String:
	var side := "echelon_right" if axis.x * v.y - axis.y * v.x > 0.0 else "echelon_left"
	return side if formation_ok(side) == side else "echelon"


## True when a visible enemy artillery piece can reach p (arty_range): formations open their spacing.
static func under_arty(vis: Array, p: Vector2) -> bool:
	var r := num("arty_range")
	for e in vis:
		if String(e.get("kind", "unit")) == "unit" and U.is_artillery(String(e.def)) and (e.pos as Vector2).distance_to(p) <= r:
			return true
	return false


static func _sys(name: String) -> Script:
	return L.sys(name)


static func _has(s: Script, fn: String) -> bool:
	return L.api(s, fn)
