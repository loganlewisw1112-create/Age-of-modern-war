extends RefCounted
## General (owner: GEN61). G6.1 "Field Command": an AI Commander slot with objective {type: "auto"} is a
## full general. It reads its side's BELIEF of the enemy (CHAIN61 Intel when it lands, else Fog-visible
## enemies + last-seen buildings: never the truth), re-plans on a cadence and picks an operation by score:
##   strike       concentrated attack on a weak / valuable enemy group
##   infil        spec-ops infiltration: in by one flank avoiding contact, hit, out by the other flank
##   attack       deliberate attack: recon > fix > flank > assault > consolidate (main / fixing / reserve)
##   defend       defence in depth of its base when threatened
##   counter      counter-attack on an enemy group that came close and is beatable
##   recon        recon in force toward the last known / expected enemy
##   screen       screen / delay between a stronger enemy and the base, bounding back
##   raid_supply  raid on enemy supply trucks / depots, then exfil
##   refit        pull back to the rally point to resupply, heal and take replacements
## Scores use force ratio from belief, own losses, ammo, distance, height, playstyle, stance and leader
## traits (REAL61, neutral until it lands). Mission memory: a failed target/axis is not repeated at once;
## tempo: pauses to consolidate after a success; breaks off at the stance loss limit; disperses under enemy
## air; slots of one side never pick the same target. Orders go through Commanders.send (the normal command
## path, override window respected); the war effort (budget, replacements, fire support, logistics) is in
## general_war.gd.
## State: slot S.gen = {ver, op {id, type, tgt, tid, phase, t0, pt, p0, from, side, els {name: [ids]},
##   wp_in, wp_out, trail_in, trail_out, flank_deg, why}, next_plan, pause_until, hist [{type, tgt, ok, tick,
##   dir}], ops {type: n}, seq, status, air_tick, last_flank_deg}. Saved and hashed with the slot.
## Events: AiGeneralOp {fid, slot, op, phase, target, reason}.

const Doctrine = preload("res://sim/ai/doctrine/doctrine.gd")
const DU = preload("res://sim/ai/doctrine/doc_util.gd")
const U = preload("res://sim/ai/ai_util.gd")
const L = preload("res://sim/ai/ai_g6_lib.gd")
const Sq7D = preload("res://sim/systems/sq7_display.gd")   # G7 (REGRESS7-7): SQUAD7 display hook after a raid gait write

const OPS := ["strike", "infil", "attack", "defend", "counter", "recon_force", "screen", "raid_supply", "refit"]
const OP_LABEL := {"strike": "STRIKE", "infil": "INFIL/EXFIL", "attack": "DELIBERATE ATTACK", "defend": "DEFEND",
	"counter": "COUNTER-ATTACK", "recon_force": "RECON IN FORCE", "screen": "SCREEN/DELAY", "raid_supply": "SUPPLY RAID",
	"refit": "REGROUP/REFIT"}
## PROVISIONAL balance fixtures; content/rules.json ai_cmd.general overrides any key.
const RULES := {
	"plan_ticks": 200, "cluster_cell": 8.0, "base_threat_radius": 20.0, "strike_ratio": 1.8, "attack_ratio": 1.0,
	"refit_strength": 0.5, "refit_done": 0.8, "refit_ticks": 1200, "refit_ammo": 0.25, "op_timeout": 3000,
	"consolidate_ticks": 300, "memory_ticks": 3000, "memory_radius": 8.0, "coord_radius": 7.0,
	"loss_limit": {"cautious": 0.3, "balanced": 0.45, "aggressive": 0.65}, "flank_deg": 90.0, "flank_min": 6.0,
	"flank_max": 14.0, "infil_deg": 70.0, "hit_ticks": 400, "arrive": 3.5, "recon_ticks": 120, "fix_ticks": 1400,
	"air_radius": 10.0, "air_ticks": 300, "screen_ticks": 1200, "defend_quiet": 300, "trail_max": 12,
	"repeat_penalty": 0.25, "danger_close": 7.0,
	"form_r": 8.0, "form_ticks": 1600,   # G7 (REGRESS7-6): an infil / supply raid forms up first (PROVISIONAL)
	# G7 (REGRESS7-7, ORCH ruling iv on need 2919): stealthy raids (PROVISIONAL). A known armed enemy's detection
	# circle = its def sight (sneak_sight when unknown) x sneak_sil (a moving raider: crouch-walking does not cut the
	# silhouette while moving, Senses7) + sneak_margin. Route grid: ~sneak_grid cells a side (>= sneak_cell tiles);
	# a cell inside a circle costs 1 + sneak_pen x (1..2 by depth) per step. Raiders crouch-walk (in) / duck-run
	# (out, home) within sneak_band of a circle; exfil point >= out_sep from the way in; leg timeouts grow by
	# leg_tpt ticks per tile of planned route. The assault position also prices the spot sneak_fire_r short of the
	# target the raiders will fire from (a hit from inside a known defender's sight brings him onto them). On the way
	# in, every replan_ticks, a route that now crosses a known circle (a defender seen or reported since) is re-planned.
	# At each waypoint the team closes up (every man within form_r) or waits wp_wait ticks for stragglers.
	"sneak_cell": 2.0, "sneak_grid": 64, "sneak_sil": 1.0, "sneak_margin": 3.0, "sneak_pen": 8.0, "sneak_sight": 10.0,
	"sneak_band": 6.0, "out_sep": 10.0, "leg_tpt": 16, "sneak_fire_r": 6.0, "replan_ticks": 80, "wp_wait": 300,
	"style": {
		"defensive": {"defend": 1.4, "screen": 1.3, "counter": 1.1, "refit": 1.1},
		"aggressive": {"strike": 1.3, "attack": 1.1, "counter": 1.3, "recon_force": 1.1},
		"specops": {"infil": 1.7, "raid_supply": 1.5, "recon_force": 1.2, "attack": 0.7},
		"combined": {"attack": 1.4, "strike": 1.1, "recon_force": 1.1}},
	"stance_ratio": {"cautious": 1.3, "balanced": 1.0, "aggressive": 0.75},
}
static var _r: Dictionary = {}
static var _r_src = null


## Rule value (rules.json ai_cmd.general over RULES).
static func G(key: String):
	var ac = Content.rules().get("ai_cmd", null)
	var src = ac.get("general", null) if ac is Dictionary else null
	if _r.is_empty() or not is_same(_r_src, src):
		_r = RULES.duplicate(true)
		_r_src = src
		if src is Dictionary:
			for k in src:
				_r[k] = src[k]
	return _r.get(key)


## A fresh general state for a slot.
static func new_gen(w: SimWorld) -> Dictionary:
	return {"ver": 1, "op": {}, "next_plan": w.tick, "pause_until": 0, "hist": [], "ops": {}, "seq": 0,
		"status": "Assessing the situation.", "air_tick": -100000, "last_flank_deg": 0.0}


# ================================================================ belief
## Combat weight of a unit / building def (hp-scaled; unarmed things count little).
static func power_of(def_id: String, kind: String, hp_frac: float = 1.0) -> float:
	var d: Dictionary = Content.unit(def_id) if kind == "unit" else Content.building(def_id)
	var p := float(d.get("hp", 100)) / 100.0
	if String(d.get("weapon", "")) == "":
		p = 0.2 if kind == "building" else p * 0.25
	elif kind == "building":
		p *= 0.6
	return maxf(0.05, p * clampf(hp_frac, 0.05, 1.0))


## How much a target is worth hitting: artillery / strike units, officers, supply, HQs score high.
static func value_of(def_id: String, kind: String) -> float:
	if kind == "building":
		return 3.0 if U.is_hq_def(def_id) else 1.5
	var d := Content.unit(def_id)
	if d.has("strike") or U.is_artillery(def_id):
		return 3.0
	if bool(d.get("is_officer", false)) or bool(d.get("is_commander", false)):
		return 2.5
	if bool(d.get("is_supply", false)):
		return 2.0
	return 1.0


## The side's belief of the enemy now: [{id, pos, def, kind, power, value, air, supply}] (ascending id).
## CHAIN61 Intel.believed_enemies(w, fid) when present (entries with id/pos/def/kind), else Fog-visible
## enemies plus last-seen enemy buildings (fair). Cached per tick in w.cache (runtime only).
static func belief(w: SimWorld, fid: int) -> Array:
	var k := "gen61_bel_%d" % fid
	var c = w.cache.get(k)
	if c is Array and int(c[0]) == w.tick:
		return c[1]
	var raw: Array = w.visible_enemies(fid).duplicate()
	var seen := {}
	for e in raw:
		seen[int(e.id)] = true
	for m in DU.known_buildings(w, fid):
		if not seen.has(int(m.id)):
			seen[int(m.id)] = true
			raw.append(m)
	# CHAIN61 Intel belief (reports, recon, decoys, ageing contacts) on top of what is seen now
	var got = L.callf(L.sys("intel"), "contacts", [w, fid, Rect2(0, 0, float(w.map.w), float(w.map.h)), 0.0], [])
	if got is Array:
		var anon := 0
		for ct in got:
			if not (ct is Dictionary) or not ct.has("pos"):
				continue
			var cid := int(ct.get("id", 0))
			if cid != 0 and seen.has(cid):
				continue
			anon += 1
			var cc: Dictionary = (ct as Dictionary).duplicate()
			cc.id = cid if cid != 0 else -anon
			if String(cc.get("def", "")) == "" and String(cc.get("guess", "")) != "":
				cc.def = String(cc.guess)
			raw.append(cc)
	var out := []
	for e in raw:
		if not (e is Dictionary) or not e.has("pos"):
			continue
		var kind := String(e.get("kind", "unit"))
		var def_id := String(e.get("def", ""))
		var hpf := 1.0
		if e.has("hp") and kind == "unit":
			var mx := float(Content.unit(def_id).get("hp", 100))
			hpf = float(e.hp) / maxf(1.0, mx)
		var ud := Content.unit(def_id) if kind == "unit" else {}
		var pw := power_of(def_id, kind, hpf)
		if e.has("strength") and float(e.strength) > 0.0 and e.has("conf"):  # an Intel belief contact (not seen now)
			pw = float(e.strength) * clampf(float(e.get("conf", 1.0)), 0.1, 1.0)
		var armed := String((ud if kind == "unit" else Content.building(def_id)).get("weapon", "")) != "" or def_id == ""
		out.append({"id": int(e.get("id", -1)), "pos": Vector2(e.pos), "def": def_id, "kind": kind, "armed": armed,
			"power": pw, "value": value_of(def_id, kind),
			"air": String(ud.get("move_class", "")).begins_with("air"), "supply": bool(ud.get("is_supply", false))
				or (kind == "building" and (bool(Content.building(def_id).get("is_supply_point", false))
				or bool(Content.building(def_id).get("supply_point", false)) or bool(Content.building(def_id).get("refines", false))))})
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	w.cache[k] = [w.tick, out]
	return out


## Belief grouped into clusters (cluster_cell buckets, ascending bucket key): [{pos, power, n, value,
## ids, supply, building, air}]. value = the best target value in it.
static func clusters(bel: Array) -> Array:
	var cs := float(G("cluster_cell"))
	var by := {}
	for b in bel:
		if bool(b.air):
			continue
		var key := Vector2i(floori(b.pos.x / cs), floori(b.pos.y / cs))
		var kk := key.y * 4096 + key.x
		if not by.has(kk):
			by[kk] = {"sum": Vector2.ZERO, "power": 0.0, "n": 0, "value": 0.0, "ids": [], "supply": false,
				"building": false, "air": false, "armed": false}
		var g: Dictionary = by[kk]
		g.sum += Vector2(b.pos)
		g.power = float(g.power) + float(b.power)
		g.n = int(g.n) + 1
		g.value = maxf(float(g.value), float(b.value))
		g.ids.append(int(b.id))
		if bool(b.supply):
			g.supply = true
		if bool(b.get("armed", true)):
			g.armed = true
		if String(b.kind) == "building":
			g.building = true
	var keys := by.keys()
	keys.sort()
	var out := []
	for kk in keys:
		var g: Dictionary = by[kk]
		g.pos = (g.sum as Vector2) / float(maxi(1, int(g.n)))
		g.erase("sum")
		out.append(g)
	return out


## Belief power within r of p.
static func power_near(bel: Array, p: Vector2, r: float) -> float:
	var s := 0.0
	for b in bel:
		if not bool(b.air) and (b.pos as Vector2).distance_to(p) <= r:
			s += float(b.power)
	return s


## Believed ARMED power within r of p (an objective with only unarmed buildings left counts as clear).
static func armed_near(bel: Array, p: Vector2, r: float) -> float:
	var s := 0.0
	for b in bel:
		if not bool(b.air) and bool(b.get("armed", true)) and (b.pos as Vector2).distance_to(p) <= r:
			s += float(b.power)
	return s


## Mop-up on an objective: the nearest believed enemy (unit or building) within r of tgt gets a direct
## attack order (buildings are not engaged by attack-move). Returns true when an order went out.
static func mop_up(w: SimWorld, fid: int, s: Dictionary, badge: String, ids: Array, bel: Array, tgt: Vector2, r: float) -> bool:
	var best = null
	var bd := INF
	for b in bel:
		var d := (b.pos as Vector2).distance_to(tgt)
		if bool(b.air) or d > r or not seen_now(w, fid).has(int(b.id)):  # only what the side sees right now
			continue
		if d < bd:
			bd = d
			best = b
	if best == null:
		return false
	if int(C().send(w, fid, s, badge, {"type": "attack", "unit_ids": ids, "target": Vector2(best.pos), "target_id": int(best.id)})) > 0:
		if String(best.kind) == "building":
			C().tag(w, fid, s, "sabotage", ids, "Mop-up: demolishing the enemy %s at (%d, %d)." % [String(best.def), int(best.pos.x), int(best.pos.y)], false)
	return true


## Own combat power of units us (hp-scaled).
static func own_power(us: Array) -> float:
	var s := 0.0
	for e in us:
		var mx := float(Content.unit(String(e.def)).get("hp", 100))
		s += power_of(String(e.def), "unit", float(e.get("hp", mx)) / maxf(1.0, mx))
	return s


## Average ammo fraction of the units that carry ammo (1.0 when none do).
static func ammo_frac(us: Array) -> float:
	var s := 0.0
	var n := 0
	for e in us:
		var mx := int(Content.unit(String(e.def)).get("ammo", 0))
		if mx > 0 and e.has("ammo"):
			s += clampf(float(e.ammo) / float(mx), 0.0, 1.0)
			n += 1
	return s / float(n) if n > 0 else 1.0


# ================================================================ scoring
## Leader-trait multipliers per op (REAL61 Veterancy.trait_bias(w, fid, ids) -> {op: mult}); neutral ({})
## until it lands.
static func trait_bias(w: SimWorld, fid: int, ids: Array, slot: int = -1) -> Dictionary:
	var got = L.callf(L.sys("veterancy"), "trait_bias", [w, fid, ids], null)
	if got is Dictionary:
		return got
	var v := L.sys("veterancy")
	if slot < 0 or not L.api(v, "slot_trait_weight"):
		return {}
	var out := {}
	var keys := {"strike": "aggression", "attack": "aggression", "counter": "aggression", "defend": "caution",
		"screen": "caution", "recon_force": "scouting", "refit": "logistics", "infil": "flank", "raid_supply": "flank"}
	for op in keys:
		var wt = v.call("slot_trait_weight", w, fid, "p%d" % slot, String(keys[op]))
		var f := float(wt) if (wt is float or wt is int) else 0.0
		out[op] = clampf(1.0 + 0.3 * f, 0.5, 1.6)
	return out


## Targets other auto slots of side fid are working on now (coordination: no two slots on one target).
static func taken_targets(w: SimWorld, fid: int, my_slot: int) -> Array:
	var out := []
	if not w.sys_state.has("ai_cmd"):
		return out
	var ss: Dictionary = (w.sys_state.ai_cmd.slots as Dictionary).get(fid, {})
	var keys := ss.keys()
	keys.sort()
	for k in keys:
		if int(k) == my_slot:
			continue
		var g = (ss[k] as Dictionary).get("gen", null)
		if g is Dictionary and not (g.op as Dictionary).is_empty() and (g.op as Dictionary).has("tgt"):
			if ["strike", "attack", "infil", "raid_supply", "counter"].has(String(g.op.type)):
				out.append(Vector2(g.op.tgt))
	return out


## Mission memory penalty: a recent failed op on (about) this target from (about) this direction.
static func memory_penalty(w: SimWorld, g: Dictionary, tgt: Vector2, from: Vector2) -> float:
	var pen := 0.0
	var dir := (tgt - from).normalized()
	for h in g.hist:
		if bool(h.ok) or w.tick - int(h.tick) > int(G("memory_ticks")):
			continue
		if (Vector2(h.tgt)).distance_to(tgt) > float(G("memory_radius")):
			continue
		var hd: Vector2 = h.dir
		pen += 1.5 if hd.dot(dir) > 0.7 else 0.6
	return pen


## Height bonus of a target area for the attacker: attacking uphill costs, downhill helps (Elevation API
## when ready, flat otherwise).
static func height_term(w: SimWorld, from: Vector2, tgt: Vector2) -> float:
	var el := L.sys("elevation")
	var a = L.callf(el, "height_at", [w, from], null)
	var b = L.callf(el, "height_at", [w, tgt], null)
	if a == null or b == null:
		return 0.0
	return clampf((float(a) - float(b)) * 0.1, -0.4, 0.4)


## Every candidate op with its score, best first: [{type, score, tgt, tid, why}]. Pure function of state.
static func candidates(w: SimWorld, fid: int, s: Dictionary, us: Array, home: Vector2, slot: int) -> Array:
	var g: Dictionary = s.gen
	var bel := belief(w, fid)
	var cl := clusters(bel)
	var cen := DU.centroid(us, home)
	var mine := own_power(us)
	var peak := maxf(float(s.get("peak_power", mine)), 0.01)
	var strength := mine / peak
	var ammo := ammo_frac(us)
	var stance := String(s.stance)
	var sr := float((G("stance_ratio") as Dictionary).get(stance, 1.0))
	var diag := Vector2(w.map.w, w.map.h).length()
	var taken := taken_targets(w, fid, slot)
	var out := []
	# refit when depleted
	if strength < float(G("refit_strength")) or ammo < float(G("refit_ammo")):
		out.append({"type": "refit", "score": 2.6 + (1.0 - strength), "tgt": home, "tid": -1,
			"why": "strength %d%%, ammo %d%%" % [roundi(strength * 100.0), roundi(ammo * 100.0)]})
	# base threat
	var threat := power_near(bel, home, float(G("base_threat_radius")))
	if threat > 0.0:
		var tp := home
		var bd := INF
		for c in cl:
			var d := (c.pos as Vector2).distance_to(home)
			if d <= float(G("base_threat_radius")) and d < bd:
				bd = d
				tp = c.pos
		out.append({"type": "defend", "score": 2.7 + minf(threat / maxf(mine, 0.1), 2.0) * 0.5, "tgt": tp, "tid": -1,
			"why": "enemy at the base (%d, %d), threat %.1f vs %.1f" % [int(tp.x), int(tp.y), threat, mine]})
	# counter-attack: right after a successful defence, hit the attackers falling back if they are beatable
	var hl: Array = g.hist
	if threat <= 0.0 and not hl.is_empty() and String(hl.back().type) == "defend" and bool(hl.back().ok) 			and w.tick - int(hl.back().tick) <= 1200 and strength >= 0.5:
		var rb := float(G("base_threat_radius")) * 2.0
		var tc = null
		var td := INF
		for c in cl:
			var d := (c.pos as Vector2).distance_to(home)
			if d <= rb and d < td:
				td = d
				tc = c
		if tc != null:
			var lp := power_near(bel, tc.pos, float(G("cluster_cell")) * 1.2)
			if mine / maxf(lp, 0.01) >= 1.3 * sr:
				out.append({"type": "counter", "score": 2.4 + minf(mine / maxf(lp, 0.01), 4.0) * 0.15, "tgt": Vector2(tc.pos), "tid": -1,
					"why": "attackers falling back at (%d, %d) are beatable %.1f:1" % [int(tc.pos.x), int(tc.pos.y), mine / maxf(lp, 0.01)]})
	for c in cl:
		var p: Vector2 = c.pos
		var skip := false
		for t in taken:
			if (t as Vector2).distance_to(p) <= float(G("coord_radius")):
				skip = true
		if skip:
			continue
		var local := power_near(bel, p, float(G("cluster_cell")) * 1.2)
		var ratio := mine / maxf(local, 0.05)
		var dterm := p.distance_to(cen) / maxf(diag, 1.0)
		var mem := memory_penalty(w, g, p, cen)
		var ht := height_term(w, cen, p)
		var v := float(c.value)
		if ratio >= float(G("strike_ratio")) * sr and bool(c.get("armed", true)):
			out.append({"type": "strike", "score": 1.0 + minf(ratio, 4.0) * 0.3 + v * 0.4 - dterm * 1.5 - mem + ht, "tgt": p,
				"tid": int(c.ids[0]), "why": "%d enemies at (%d, %d), weak escort %.1f:1" % [int(c.n), int(p.x), int(p.y), ratio]})
		if ratio >= float(G("attack_ratio")) * sr and us.size() >= 4:
			out.append({"type": "attack", "score": 0.9 + minf(ratio, 3.0) * 0.25 + v * 0.35 + (0.3 if bool(c.building) else 0.0) - dterm - mem + ht,
				"tgt": p, "tid": int(c.ids[0]), "why": "%d enemies dug in at (%d, %d), %.1f:1" % [int(c.n), int(p.x), int(p.y), ratio]})
		if v >= 2.0 and us.size() >= 2:
			out.append({"type": "infil", "score": 0.7 + v * 0.35 - dterm * 0.6 - mem, "tgt": p, "tid": int(c.ids[0]),
				"why": "high-value target at (%d, %d) (value %.1f)" % [int(p.x), int(p.y), v]})
		if bool(c.supply):
			out.append({"type": "raid_supply", "score": 0.85 + v * 0.3 - dterm * 0.6 - mem, "tgt": p, "tid": int(c.ids[0]),
				"why": "enemy supply at (%d, %d)" % [int(p.x), int(p.y)]})
		if ratio < 0.9 and p.distance_to(home) < diag * 0.6:
			var sp := home + (p - home) * 0.5
			out.append({"type": "screen", "score": 0.7 + (1.0 - ratio) * 0.5 - mem * 0.5, "tgt": sp, "tid": -1,
				"why": "stronger enemy (%.1f vs %.1f) at (%d, %d)" % [local, mine, int(p.x), int(p.y)]})
	# recon in force when the picture is thin or stale
	var rt := U.enemy_spawn(w, fid)
	if not cl.is_empty():
		rt = (cl[cl.size() - 1].pos as Vector2) if (cl[cl.size() - 1].pos as Vector2).distance_to(cen) > 12.0 else rt
	out.append({"type": "recon_force", "score": (0.8 if cl.is_empty() else 0.35) - memory_penalty(w, g, rt, cen) * 0.3, "tgt": rt,
		"tid": -1, "why": "picture thin (%d contacts)" % bel.size()})
	# playstyle, traits, repetition
	var sty: Dictionary = (G("style") as Dictionary).get(String(s.playstyle), {})
	var tb := trait_bias(w, fid, DU.ids_of(us), slot)
	var last := String((g.hist as Array).back().type) if not (g.hist as Array).is_empty() else ""
	for o in out:
		var m := float(sty.get(String(o.type), 1.0)) * float(tb.get(String(o.type), 1.0))
		o.score = float(o.score) * m
		if String(o.type) == last and not ["defend", "refit"].has(last):
			o.score = float(o.score) - float(G("repeat_penalty"))
		o.score = snappedf(float(o.score), 0.001)
	out.sort_custom(func(a, b):
		if float(a.score) != float(b.score):
			return float(a.score) > float(b.score)
		return OPS.find(String(a.type)) < OPS.find(String(b.type)))
	return out


# ================================================================ op helpers
static var _cs: Script = null


## Commanders script, loaded lazily (it preloads this file).
static func C() -> Script:
	if _cs == null:
		_cs = load("res://sim/ai/commanders.gd")
	return _cs


## One order through the normal command path (override window, de-dup): Commanders.send.
static func order(w: SimWorld, fid: int, s: Dictionary, badge: String, o: Dictionary) -> int:
	if (o.get("unit_ids", []) as Array).is_empty():
		return 0
	var hd := GNet.held(w, fid, s)  # GEN61-2: a company acts once its captain has the general's order (CommandNet)
	if not hd.is_empty():
		var keep := []
		for id in o.unit_ids:
			if not hd.has(int(id)):
				keep.append(id)
		if keep.is_empty():
			return 0
		o = o.duplicate()
		o.unit_ids = keep
	return int(C().send(w, fid, s, badge, o))


## AiDecision with a CONTRACTS_G6 3.6 tag + the slot log (Commanders.tag).
static func tag(w: SimWorld, fid: int, s: Dictionary, t: String, ids: Array, reason: String) -> void:
	C().tag(w, fid, s, t, ids, reason, false)


## A line in the slot log only.
static func log_line(w: SimWorld, s: Dictionary, msg: String) -> void:
	var lg: Array = s.log
	lg.append("t=%d %s" % [w.tick, msg])
	while lg.size() > int(C().R("log_max")):
		lg.pop_front()


static func clamp_map(w: SimWorld, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 1.0, float(w.map.w) - 2.0), clampf(p.y, 1.0, float(w.map.h) - 2.0))


## Point d short of tgt on the line from `from`.
static func short_of(from: Vector2, tgt: Vector2, d: float) -> Vector2:
	var v := from - tgt
	if v.length() < 0.01:
		return tgt
	return tgt + v.normalized() * minf(d, v.length())


## Flank / infil waypoint: deg off the direct axis (tgt -> from), on side +1 / -1, dist d from tgt.
static func off_axis(w: SimWorld, from: Vector2, tgt: Vector2, deg: float, side: int, d: float) -> Vector2:
	var v := from - tgt
	if v.length() < 0.01:
		v = Vector2(-1, 0)
	return clamp_map(w, tgt + v.normalized().rotated(deg_to_rad(deg) * float(side)) * d)


## Angle (deg) between (p - tgt) and (from - tgt).
static func axis_deg(from: Vector2, tgt: Vector2, p: Vector2) -> float:
	var a := from - tgt
	var b := p - tgt
	if a.length() < 0.01 or b.length() < 0.01:
		return 0.0
	return rad_to_deg(absf(a.angle_to(b)))


## The flank side (+1 / -1) with less believed enemy power around its waypoint (ties: +1).
static func pick_side(w: SimWorld, bel: Array, from: Vector2, tgt: Vector2, deg: float, d: float) -> int:
	var a := power_near(bel, off_axis(w, from, tgt, deg, 1, d), d * 0.6)
	var b := power_near(bel, off_axis(w, from, tgt, deg, -1, d), d * 0.6)
	return -1 if b < a else 1


## Elements for a deliberate attack: {fix, main, reserve} unit-id lists. By company when the slot holds
## several (main = the largest), else by Doctrine.split, else halves by id.
static func elements(w: SimWorld, fid: int, s: Dictionary, ids: Array) -> Dictionary:
	var groups := []
	var spec: Dictionary = s.spec
	var cids: Array = spec.get("companies", [])
	if cids.size() >= 2:
		var cs: Dictionary = w.sys_state.get("companies", {}).get("companies", {})
		var idset := {}
		for id in ids:
			idset[int(id)] = true
		for cid in cids:
			var c = cs.get(int(cid))
			if c is Dictionary:
				var gl := []
				for id in C().company_units(w, fid, c):
					if idset.has(int(id)):
						gl.append(int(id))
				if not gl.is_empty():
					groups.append(gl)
	if groups.size() < 2:
		groups = Doctrine.split(w, fid, ids)
	if groups.size() < 2:
		var srt := ids.duplicate()
		srt.sort()
		var h := srt.size() / 2
		groups = [srt.slice(0, h), srt.slice(h)]
	groups.sort_custom(func(a, b):
		if (a as Array).size() != (b as Array).size():
			return (a as Array).size() > (b as Array).size()
		return int(a[0]) < int(b[0]))
	var out := {"main": groups[0], "fix": groups[1], "reserve": []}
	for i in range(2, groups.size()):
		out.reserve.append_array(groups[i])
	return out


## The ids of element `name` still alive and free (not player-fresh).
static func el_ids(op: Dictionary, name: String, free_set: Dictionary) -> Array:
	var out := []
	for id in (op.els as Dictionary).get(name, []):
		if free_set.has(int(id)):
			out.append(int(id))
	return out


static func centroid_of(w: SimWorld, ids: Array, dflt: Vector2) -> Vector2:
	var s := Vector2.ZERO
	var n := 0
	for id in ids:
		var e = w.entities.get(int(id))  # AI-FAIR: own element units only
		if e != null:
			s += Vector2(e.pos)
			n += 1
	return s / float(n) if n > 0 else dflt


static func _trail(g_op: Dictionary, key: String, p: Vector2) -> void:
	var t: Array = g_op[key]
	if t.is_empty() or (t.back() as Vector2).distance_to(p) >= 2.0:
		t.append(p)
	while t.size() > int(G("trail_max")):
		t.remove_at(1)


## Phase change of the current op (+ AiGeneralOp event and a log line).
static func phase(w: SimWorld, fid: int, s: Dictionary, ph: String, why: String) -> void:
	var op: Dictionary = s.gen.op
	op.phase = ph
	op.pt = w.tick
	w.emit("AiGeneralOp", {"fid": fid, "slot": int(s.get("slot", -1)), "op": String(op.type), "phase": ph,
		"target": Vector2(op.tgt), "reason": why})
	log_line(w, s, "Op %s: %s - %s" % [OP_LABEL.get(String(op.type), String(op.type)), ph, why])
	GNet.send_intent(w, fid, s)  # GEN61-2: the intent goes down the chain of command (radio delay)


## Ends the current op: mission memory entry, tempo pause after a success.
static func finish(w: SimWorld, fid: int, s: Dictionary, ok: bool, why: String) -> void:
	var g: Dictionary = s.gen
	var op: Dictionary = g.op
	if op.is_empty():
		return
	phase(w, fid, s, "done" if ok else "failed", why)
	_unsneak(w, fid, s, op)
	var hist: Array = g.hist
	hist.append({"type": String(op.type), "tgt": Vector2(op.tgt), "ok": ok, "tick": w.tick,
		"dir": (Vector2(op.tgt) - Vector2(op.from)).normalized()})
	while hist.size() > 10:
		hist.pop_front()
	g.last = op.duplicate(true)
	g.last.erase("els")
	g.op = {}
	g.next_plan = w.tick
	if ok and ["strike", "attack", "counter", "infil", "raid_supply"].has(String(op.type)):
		g.pause_until = w.tick + int(G("consolidate_ticks"))


## Starts op cand {type, score, tgt, tid, why} for the free units.
static func start(w: SimWorld, fid: int, s: Dictionary, cand: Dictionary, x: Dictionary) -> void:
	var g: Dictionary = s.gen
	g.seq = int(g.seq) + 1
	var t := String(cand.type)
	var tgt: Vector2 = cand.tgt
	var cen: Vector2 = x.cen
	var op := {"id": int(g.seq), "type": t, "tgt": tgt, "tid": int(cand.tid), "phase": "", "t0": w.tick, "pt": w.tick,
		"p0": float(x.mine), "from": cen, "rally": Vector2(x.rally), "side": 1, "els": {}, "trail_in": [cen],
		"trail_out": [], "flank_deg": 0.0, "why": String(cand.why), "bounds": 0, "quiet": w.tick}
	var d := clampf(cen.distance_to(tgt) * 0.6, float(G("flank_min")), float(G("flank_max")))
	match t:
		"attack":
			op.els = elements(w, fid, s, x.ids)
			op.side = pick_side(w, x.bel, cen, tgt, float(G("flank_deg")), d)
			op.wp_in = off_axis(w, cen, tgt, float(G("flank_deg")), int(op.side), d)
		"infil", "raid_supply":
			_infil_route(w, x.bel, op, cen)
	g.op = op
	g.ops[t] = int((g.ops as Dictionary).get(t, 0)) + 1
	var spec: Dictionary = s.spec
	var nco := (spec.get("companies", []) as Array).size()
	var force := ("%d coys" % nco) if nco >= 2 else ("1 coy" if nco == 1 else "%d units" % (x.ids as Array).size())
	var first := {"strike": "move", "attack": "scouting", "infil": "in", "raid_supply": "in", "defend": "hold",
		"counter": "move", "recon_force": "probe", "screen": "hold", "refit": "fall_back"}
	var ph := String(first.get(t, "move"))
	if (t == "infil" or t == "raid_supply") and spread(w, x.ids, cen) > float(G("form_r")):
		ph = "form"   # G7: a scattered force forms up at the rally point before it goes in (see _ex_infil)
	phase(w, fid, s, ph, "%s, %s (score %.2f)" % [String(cand.why), force, float(cand.score)])
	if ph == "in" and (t == "infil" or t == "raid_supply"):
		_hold_fire(w, fid, s, x, op, true)


## G7 (REGRESS7-6): infil / raid route from centroid cen: flank side, wp_in, wp_out (exfil by the other flank).
static func _infil_route(w: SimWorld, bel: Array, op: Dictionary, cen: Vector2) -> void:
	var tgt: Vector2 = op.tgt
	var d := clampf(cen.distance_to(tgt) * 0.6, float(G("flank_min")), float(G("flank_max")))
	op.side = pick_side(w, bel, cen, tgt, float(G("infil_deg")), d)
	op.wp_in = off_axis(w, cen, tgt, float(G("infil_deg")), int(op.side), d)
	op.wp_out = off_axis(w, cen, tgt, float(G("infil_deg")), -int(op.side), d)
	op.path_in = [op.wp_in]
	op.pi = 0
	op.erase("in_t")
	op.erase("piw")
	op.erase("path_home")
	op.erase("home_t")
	# G7 (REGRESS7-7): with known armed defenders, plan around their sight (none known: the G6.1 route)
	var thr := _threats(bel)
	if thr.is_empty():
		return
	var gr := _sneak_grid(w, thr)
	var dj := _dijkstra(gr, cen)
	var gi := _ring_goal(gr, dj, tgt, d, Vector2(op.wp_in), Vector2(INF, INF), float(G("sneak_fire_r")))
	if gi < 0:
		return
	op.path_in = _pull(gr, _cells_to(dj, gi))
	op.wp_in = Vector2(op.path_in.back())
	op.in_t = maxi(1200, int(_plen(cen, op.path_in) * float(G("leg_tpt"))))
	_plan_out(w, gr, op, d)


## G7 (REGRESS7-7): the rest of the way in crosses a known defender's detection circle that the plan avoided (the
## picture changed): plan again from here (the in-leg clock keeps running; the allowance is extended by the new route).
static func _replan_in(w: SimWorld, x: Dictionary, op: Dictionary, cen: Vector2) -> void:
	var thr := _threats(x.bel)
	if thr.is_empty():
		return
	var wps: Array = op.path_in
	var a := cen
	var hit := false
	for k in range(mini(int(op.get("pi", 0)), wps.size() - 1), wps.size() - 1):   # the assault leg itself excluded
		var b := Vector2(wps[k])
		for c in thr:
			if Geometry2D.get_closest_point_to_segment(c[0], a, b).distance_to(c[0]) < float(c[1]):
				hit = true
				break
		if hit:
			break
		a = b
	if not hit:
		return
	var el := w.tick - int(op.pt)
	var old_out = op.wp_out
	var gr := _sneak_grid(w, thr)
	var gi := _cell_of(gr, Vector2(op.wp_in))
	var tgt: Vector2 = op.tgt
	var pen: PackedFloat32Array = gr.pen
	if pen[gi] <= 0.0 and pen[_cell_of(gr, tgt + (Vector2(op.wp_in) - tgt).normalized() * float(G("sneak_fire_r")))] <= 0.0:
		var dj := _dijkstra(gr, cen)   # the assault position is still out of sight: only the way there changes
		if float(dj[0][gi]) < 1e29:
			op.path_in = _pull(gr, _cells_to(dj, gi))
			op.path_in[op.path_in.size() - 1] = Vector2(op.wp_in)
			op.pi = 0
			op.erase("piw")
			op.in_t = el + maxi(1200, int(_plen(cen, op.path_in) * float(G("leg_tpt"))))
			return
	_infil_route(w, x.bel, op, cen)
	if op.has("in_t"):
		op.in_t = el + int(op.in_t)
	if old_out != null and not op.has("path_home"):
		op.wp_out = old_out


## G7 (REGRESS7-7): a raid already pulling out (out / home) is falling back to the rally point; a refit (pull back
## to resupply) does not call it off on the way (it would only send the same men to the same place).
static func _exfiltrating(op: Dictionary) -> bool:
	return ["infil", "raid_supply"].has(String(op.type)) and ["out", "home"].has(String(op.phase))


## G7 (REGRESS7-7): on the way home, a route that now crosses a known defender's detection circle (one seen or
## reported since it was planned) is re-planned from here to the rally point.
static func _replan_home(w: SimWorld, x: Dictionary, op: Dictionary, cen: Vector2) -> void:
	var thr := _threats(x.bel)
	if thr.is_empty() or not op.has("path_home"):
		return
	var hp: Array = op.path_home
	var a := cen
	var hit := false
	for k in range(mini(int(op.get("hi", 0)), hp.size() - 1), hp.size()):
		var b := Vector2(hp[k])
		for c in thr:
			if Geometry2D.get_closest_point_to_segment(c[0], a, b).distance_to(c[0]) < float(c[1]):
				hit = true
				break
		if hit:
			break
		a = b
	if not hit:
		return
	var gr := _sneak_grid(w, thr)
	var r: Vector2 = op.rally
	var dj := _dijkstra(gr, cen)
	var gi := _cell_of(gr, r)
	if float(dj[0][gi]) >= 1e29:
		return
	var np := _pull(gr, _cells_to(dj, gi))
	if np.is_empty():
		return
	np[np.size() - 1] = r
	op.path_home = np
	op.hi = 0
	op.erase("hiw")
	op.home_t = (w.tick - int(op.pt)) + maxi(1600, int(_plen(cen, np) * float(G("leg_tpt"))))


## G7 (REGRESS7-7): re-plans the exfil (exfil point >= out_sep from the way in, route home around the known
## defenders' sight) from the belief at the moment the raid pulls out. No known defenders: unchanged.
static func _exfil_route(w: SimWorld, bel: Array, op: Dictionary, cen: Vector2) -> void:
	var thr := _threats(bel)
	if thr.is_empty():
		return
	var tgt: Vector2 = op.tgt
	var d := clampf(Vector2(op.from).distance_to(tgt) * 0.6, float(G("flank_min")), float(G("flank_max")))
	_plan_out(w, _sneak_grid(w, thr), op, d, cen)


## Exfil point on the ring round the target (cheapest way home, >= out_sep from wp_in) + the route home after it.
## With from (the raid's position as it pulls out) the exfil point also prices the way there, and path_out is set.
static func _plan_out(w: SimWorld, gr: Dictionary, op: Dictionary, d: float, from = null) -> void:
	var r: Vector2 = op.rally
	var dh := _dijkstra(gr, r)
	var cost: PackedFloat32Array = dh[0]
	var dc := []
	if from is Vector2:
		dc = _dijkstra(gr, from)
		cost = cost.duplicate()
		var c2: PackedFloat32Array = dc[0]
		for i in cost.size():
			cost[i] = cost[i] + c2[i]
	var go := _ring_goal(gr, [cost], Vector2(op.tgt), d, Vector2(op.wp_out), Vector2(op.wp_in), 0.0)
	if go < 0:
		return
	if not dc.is_empty():
		op.path_out = _pull(gr, _cells_to(dc, go))
		op.oi = 0
		op.out_t = maxi(1200, int(_plen(from, op.path_out) * float(G("leg_tpt"))))
	var back := _cells_to(dh, go)   # rally .. exfil point
	back.reverse()                  # exfil point .. rally
	var hp := _pull(gr, back)
	if hp.is_empty():
		hp = [r]
	hp[hp.size() - 1] = r
	op.wp_out = _cell_pos(gr, go)
	op.path_home = hp
	op.hi = 0
	op.home_t = maxi(1600, int(_plen(Vector2(op.wp_out), hp) * float(G("leg_tpt"))))


## Detection circles [[pos, r]] of the known armed ground enemies (belief: this side's fair picture).
static func _threats(bel: Array) -> Array:
	var out := []
	var sil := float(G("sneak_sil"))
	var mg := float(G("sneak_margin"))
	for b in bel:
		if bool(b.air) or not bool(b.get("armed", true)):
			continue
		var sg := float(G("sneak_sight"))
		var def_id := String(b.def)
		if def_id != "":
			var dd: Dictionary = Content.unit(def_id) if String(b.kind) == "unit" else Content.building(def_id)
			sg = float(dd.get("sight", sg))
		out.append([Vector2(b.pos), sg * sil + mg])
	return out


## Coarse route grid: {cs, gw, gh, ok (foot-passable somewhere in the cell), pen (0 outside every circle, else
## 1..2 by depth into the deepest one)}.
static func _sneak_grid(w: SimWorld, thr: Array) -> Dictionary:
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var cs := maxf(float(G("sneak_cell")), ceilf(float(maxi(mw, mh)) / float(G("sneak_grid"))))
	var gw := ceili(float(mw) / cs)
	var gh := ceili(float(mh) / cs)
	var ok := PackedByteArray()
	ok.resize(gw * gh)
	var pen := PackedFloat32Array()
	pen.resize(gw * gh)
	var t: PackedByteArray = w.map.terrain
	var ci := int(cs)
	var sps := [Vector2i(ci / 2, ci / 2), Vector2i(0, 0), Vector2i(ci - 1, 0), Vector2i(0, ci - 1), Vector2i(ci - 1, ci - 1)]
	for cy in gh:
		for cx in gw:
			var x0 := int(float(cx) * cs)
			var y0 := int(float(cy) * cs)
			for sp in sps:
				var tx := mini(x0 + int(sp.x), mw - 1)
				var ty := mini(y0 + int(sp.y), mh - 1)
				if Terrain.passable(t[ty * mw + tx], "foot"):
					ok[cy * gw + cx] = 1
					break
	for c in thr:
		var p: Vector2 = c[0]
		var rr: float = c[1]
		for cy in range(maxi(0, floori((p.y - rr) / cs)), mini(gh, ceili((p.y + rr) / cs) + 1)):
			for cx in range(maxi(0, floori((p.x - rr) / cs)), mini(gw, ceili((p.x + rr) / cs) + 1)):
				var dq := Vector2((float(cx) + 0.5) * cs, (float(cy) + 0.5) * cs).distance_to(p)
				if dq < rr:
					var i := cy * gw + cx
					pen[i] = maxf(pen[i], 2.0 - dq / rr)
	return {"cs": cs, "gw": gw, "gh": gh, "ok": ok, "pen": pen}


static func _cell_of(gr: Dictionary, p: Vector2) -> int:
	var cs: float = gr.cs
	return clampi(floori(p.y / cs), 0, int(gr.gh) - 1) * int(gr.gw) + clampi(floori(p.x / cs), 0, int(gr.gw) - 1)


static func _cell_pos(gr: Dictionary, i: int) -> Vector2:
	var cs: float = gr.cs
	return Vector2((float(i % int(gr.gw)) + 0.5) * cs, (float(i / int(gr.gw)) + 0.5) * cs)


## Dijkstra over the route grid from p (8-neighbour, no corner cutting): [cost PackedFloat32Array, parent
## PackedInt32Array]. Deterministic: binary heap ordered by (cost, cell index).
static func _dijkstra(gr: Dictionary, p: Vector2) -> Array:
	var gw: int = gr.gw
	var gh: int = gr.gh
	var n := gw * gh
	var ok: PackedByteArray = gr.ok
	var pen: PackedFloat32Array = gr.pen
	var kp := float(G("sneak_pen"))
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(1e30)
	var par := PackedInt32Array()
	par.resize(n)
	par.fill(-1)
	var src := _cell_of(gr, p)
	dist[src] = 0.0
	var hc := PackedFloat32Array([0.0])
	var hx := PackedInt32Array([src])
	var dxs := [1, -1, 0, 0, 1, -1, 1, -1]
	var dys := [0, 0, 1, -1, 1, 1, -1, -1]
	while not hx.is_empty():
		var c: float = hc[0]
		var u: int = hx[0]
		var last := hx.size() - 1
		hc[0] = hc[last]
		hx[0] = hx[last]
		hc.resize(last)
		hx.resize(last)
		var k := 0
		while true:   # sift down
			var l := k * 2 + 1
			if l >= last:
				break
			var m := l
			if l + 1 < last and (hc[l + 1] < hc[l] or (hc[l + 1] == hc[l] and hx[l + 1] < hx[l])):
				m = l + 1
			if hc[m] < hc[k] or (hc[m] == hc[k] and hx[m] < hx[k]):
				var tc: float = hc[k]
				hc[k] = hc[m]
				hc[m] = tc
				var ti: int = hx[k]
				hx[k] = hx[m]
				hx[m] = ti
				k = m
			else:
				break
		if c > dist[u]:
			continue
		var ux := u % gw
		var uy := u / gw
		for q in 8:
			var vx: int = ux + int(dxs[q])
			var vy: int = uy + int(dys[q])
			if vx < 0 or vy < 0 or vx >= gw or vy >= gh:
				continue
			var v := vy * gw + vx
			if ok[v] == 0:
				continue
			var step := 1.0
			if q >= 4:
				if ok[uy * gw + vx] == 0 or ok[vy * gw + ux] == 0:
					continue
				step = 1.41421
			var nc: float = c + step * (1.0 + kp * pen[v])
			if nc < dist[v]:
				dist[v] = nc
				par[v] = u
				var j := hc.size()   # push + sift up
				hc.append(nc)
				hx.append(v)
				while j > 0:
					var pj := (j - 1) / 2
					if hc[j] < hc[pj] or (hc[j] == hc[pj] and hx[j] < hx[pj]):
						var tc2: float = hc[j]
						hc[j] = hc[pj]
						hc[pj] = tc2
						var ti2: int = hx[j]
						hx[j] = hx[pj]
						hx[pj] = ti2
						j = pj
					else:
						break
	return [dist, par]


## Best reachable cell on the ring (radius d +- one cell) round tgt: route cost + exposure there (sneak_pen x pen x
## d; with fire_r > 0 the worse of that cell and the firing spot fire_r from tgt on the same bearing), ties: nearer
## pref, then lower index. Cells within out_sep of avoid are skipped (exfil point). -1 when none.
static func _ring_goal(gr: Dictionary, dj: Array, tgt: Vector2, d: float, pref: Vector2, avoid: Vector2, fire_r: float) -> int:
	var cs: float = gr.cs
	var dist: PackedFloat32Array = dj[0]
	var pen: PackedFloat32Array = gr.pen
	var kp := float(G("sneak_pen"))
	var sep := float(G("out_sep"))
	var best := -1
	var bs := INF
	for cy in range(maxi(0, floori((tgt.y - d - cs) / cs)), mini(int(gr.gh), ceili((tgt.y + d + cs) / cs) + 1)):
		for cx in range(maxi(0, floori((tgt.x - d - cs) / cs)), mini(int(gr.gw), ceili((tgt.x + d + cs) / cs) + 1)):
			var i := cy * int(gr.gw) + cx
			if dist[i] >= 1e29:
				continue
			var q := _cell_pos(gr, i)
			if absf(q.distance_to(tgt) - d) > cs or (avoid.x < INF and q.distance_to(avoid) < sep):
				continue
			var ex: float = pen[i]
			if fire_r > 0.0 and q.distance_to(tgt) > 0.01:
				ex = maxf(ex, pen[_cell_of(gr, tgt + (q - tgt).normalized() * fire_r)])
			var sc := float(dist[i]) + kp * ex * d + q.distance_to(pref) * 0.01
			if sc < bs:
				bs = sc
				best = i
	return best


## Cells from the Dijkstra source to cell gi (source first).
static func _cells_to(dj: Array, gi: int) -> Array:
	var par: PackedInt32Array = dj[1]
	var out := []
	var c := gi
	while c >= 0:
		out.append(c)
		c = par[c]
	out.reverse()
	return out


## Waypoints (cell centres, source dropped) for a cell path: a straight leg is kept while every cell it crosses
## is passable and never more exposed than the leg's end or the least exposed spot behind it on the leg.
static func _pull(gr: Dictionary, cells: Array) -> Array:
	if cells.size() <= 1:
		return [_cell_pos(gr, int(cells.back()))] if not cells.is_empty() else []
	var out := []
	var a := 0
	while a < cells.size() - 1:
		var b := a + 1
		while b + 1 < cells.size() and _clear(gr, int(cells[a]), int(cells[b + 1])):
			b += 1
		out.append(_cell_pos(gr, int(cells[b])))
		a = b
	return out


static func _clear(gr: Dictionary, ia: int, ib: int) -> bool:
	var ok: PackedByteArray = gr.ok
	var pen: PackedFloat32Array = gr.pen
	var run: float = pen[ia]   # leaving exposure is fine; getting more exposed again than the leg's end is not
	var pe: float = pen[ib]
	var a := _cell_pos(gr, ia)
	var b := _cell_pos(gr, ib)
	var n := maxi(1, ceili(a.distance_to(b) / (float(gr.cs) * 0.5)))
	for k in range(1, n):
		var i := _cell_of(gr, a.lerp(b, float(k) / float(n)))
		if ok[i] == 0 or pen[i] > maxf(run, pe) + 0.001:
			return false
		run = minf(run, pen[i])
	return true


## Index of the waypoint the raid heads for: the next one once the centroid is within arr of the current one and the
## team has closed up there (_closed). key = the op's index field (pi / oi / hi); key + "w" = arrival tick.
static func _wp_at(w: SimWorld, x: Dictionary, op: Dictionary, wps: Array, key: String, cen: Vector2, arr: float) -> int:
	var i := mini(int(op.get(key, 0)), wps.size() - 1)
	if cen.distance_to(Vector2(wps[i])) > arr:
		op.erase(key + "w")
		return i
	if not op.has(key + "w"):
		op[key + "w"] = w.tick
	if i < wps.size() - 1 and _closed(w, x, op, key, Vector2(wps[i])):
		i += 1
		op[key] = i
		op.erase(key + "w")
	return i


## The centroid reached waypoint p (key + "w" set) and every man is within form_r of it, or wp_wait ticks passed.
static func _closed(w: SimWorld, x: Dictionary, op: Dictionary, key: String, p: Vector2) -> bool:
	if not op.has(key + "w"):
		return false
	return spread(w, x.ids, p) <= float(G("form_r")) or w.tick - int(op[key + "w"]) >= int(G("wp_wait"))


static func _plen(from: Vector2, wps: Array) -> float:
	var l := 0.0
	var p := from
	for q in wps:
		l += p.distance_to(Vector2(q))
		p = Vector2(q)
	return l


## G7 (REGRESS7-7): raiders outside a squad (SquadAI sets a squad's gait itself) take gait g (1 crouch-walk on the
## way in, 2 duck-run on the way out) while within sneak_band of a known defender's detection circle, else walk.
## Keeps SQUAD7's display hook (Sq7D.put after every gait write). Own units only.
static func _sneak_gait(w: SimWorld, x: Dictionary, op: Dictionary, g: int) -> void:
	var thr := _threats(x.bel) if g > 0 else []
	var band := float(G("sneak_band"))
	var sg: Dictionary = op.get("sg", {})
	for id in x.ids:
		var e = w.entities.get(int(id))  # AI-FAIR: own force units only (raid gait)
		if e == null or not e.has("morale") or int(e.get("squad", -1)) >= 0:
			continue
		var want := 0
		for c in thr:
			if Vector2(e.pos).distance_to(c[0]) <= float(c[1]) + band:
				want = g
				break
		if int(e.get("gait", 0)) == want:
			continue
		if want == 0:
			if not sg.has(int(id)):
				continue   # a gait this op did not set stays
			e.erase("gait")
		else:
			e.gait = want
			sg[int(id)] = 1
		Sq7D.put(w, e)
	if not sg.is_empty():
		op.sg = sg


## G7 (REGRESS7-7): the raid holds its fire on the way in (hold_fire stance through the normal command path, so a
## fresh player order is never overridden); released at the objective. Only units with no stance of their own.
static func _hold_fire(w: SimWorld, fid: int, s: Dictionary, x: Dictionary, op: Dictionary, on: bool) -> void:
	if on:
		var ids := []
		for id in x.ids:
			var e = w.entities.get(int(id))  # AI-FAIR: own force units only (raid stance)
			if e != null and String(e.get("stance", "")) == "":
				ids.append(int(id))
		if order(w, fid, s, x.badge, {"type": "set_stance", "unit_ids": ids, "stance": "hold_fire"}) > 0:
			op.hf = ids
			op.hfb = String(x.badge)
	else:
		_lift_hold(w, fid, s, op)


static func _lift_hold(w: SimWorld, fid: int, s: Dictionary, op: Dictionary) -> void:
	if not op.has("hf"):
		return
	var back := []
	for id in op.hf:
		var e = w.entities.get(int(id))  # AI-FAIR: own force units only (raid stance)
		if e != null and String(e.get("stance", "")) == "hold_fire":
			back.append(int(id))
	order(w, fid, s, String(op.get("hfb", "")), {"type": "set_stance", "unit_ids": back, "stance": "default"})
	op.erase("hf")
	op.erase("hfb")


## Op end: the raid's hold-fire stance and sneak gait are lifted (own units only).
static func _unsneak(w: SimWorld, fid: int, s: Dictionary, op: Dictionary) -> void:
	_lift_hold(w, fid, s, op)
	for id in op.get("sg", {}):
		var e = w.entities.get(int(id))  # AI-FAIR: own force units only (raid gait)
		if e != null and e.has("gait") and int(e.get("squad", -1)) < 0:
			e.erase("gait")
			Sq7D.put(w, e)
	op.erase("sg")


## Largest distance of a live unit of ids from p (0 when none).
static func spread(w: SimWorld, ids: Array, p: Vector2) -> float:
	var m := 0.0
	for id in ids:
		var e = w.entities.get(int(id))  # AI-FAIR: own force units only (spread)
		if e != null:
			m = maxf(m, Vector2(e.pos).distance_to(p))
	return m


# ================================================================ op execution
static func _ex_strike(w: SimWorld, fid: int, s: Dictionary, x: Dictionary) -> void:
	var op: Dictionary = s.gen.op
	var tgt: Vector2 = op.tgt
	var near := armed_near(x.bel, tgt, float(G("cluster_cell")))
	if String(op.phase) == "move":
		if near <= 0.0 and w.tick - int(op.t0) > 60:
			phase(w, fid, s, "consolidate", "objective (%d, %d) clear" % [int(tgt.x), int(tgt.y)])
		elif w.tick - int(op.t0) > int(G("op_timeout")):
			finish(w, fid, s, false, "strike on (%d, %d) stalled" % [int(tgt.x), int(tgt.y)])
		elif (x.cen as Vector2).distance_to(tgt) <= float(G("cluster_cell")) and mop_up(w, fid, s, x.badge, x.ids, x.bel, tgt, float(G("cluster_cell"))):
			pass
		elif order(w, fid, s, x.badge, {"type": "attack_move", "unit_ids": x.ids, "target": tgt}) > 0:
			tag(w, fid, s, "assault_phase", x.ids, "Op STRIKE: %d units hit (%d, %d) together." % [x.ids.size(), int(tgt.x), int(tgt.y)])
		return
	if not mop_up(w, fid, s, x.badge, x.ids, x.bel, tgt, float(G("cluster_cell"))):
		C().plan(w, fid, s, x.free, x.badge, "hold", tgt, x.rally)
	if w.tick - int(op.pt) >= int(G("consolidate_ticks")):
		finish(w, fid, s, true, "strike complete, consolidated on (%d, %d)" % [int(tgt.x), int(tgt.y)])


static func _ex_attack(w: SimWorld, fid: int, s: Dictionary, x: Dictionary) -> void:
	var op: Dictionary = s.gen.op
	var tgt: Vector2 = op.tgt
	var from: Vector2 = op.from
	var fset: Dictionary = x.fset
	var fix := el_ids(op, "fix", fset)
	var main := el_ids(op, "main", fset)
	var res := el_ids(op, "reserve", fset)
	var wp: Vector2 = op.wp_in
	match String(op.phase):
		"scouting":
			if not fix.is_empty():
				order(w, fid, s, x.badge, {"type": "attack_move", "unit_ids": [fix[0]], "target": short_of(from, tgt, 7.0)})
			if w.tick - int(op.pt) >= int(G("recon_ticks")):
				tag(w, fid, s, "overwatch_set", fix, "Op ATTACK: recon done, fixing force moves up on (%d, %d)." % [int(tgt.x), int(tgt.y)])
				phase(w, fid, s, "fix", "fixing force on the direct axis, main effort flanks %s" % ("left" if int(op.side) > 0 else "right"))
		"fix":
			order(w, fid, s, x.badge, {"type": "attack_move", "unit_ids": fix, "target": short_of(from, tgt, 5.0)})
			order(w, fid, s, x.badge, {"type": "move", "unit_ids": main, "target": wp})
			order(w, fid, s, x.badge, {"type": "move", "unit_ids": res, "target": short_of(from, tgt, 11.0)})
			var mc := centroid_of(w, main, from)
			_trail(op, "trail_in", mc)
			if main.is_empty() or mc.distance_to(wp) <= float(G("arrive")) * 1.5 or w.tick - int(op.pt) > int(G("fix_ticks")):
				op.flank_deg = snappedf(axis_deg(from, tgt, mc), 0.1)
				s.gen.last_flank_deg = op.flank_deg
				tag(w, fid, s, "flank", main, "Op ATTACK: main effort in position %d deg off the axis, assault." % roundi(float(op.flank_deg)))
				phase(w, fid, s, "assault", "flank %d deg, fix + main + reserve go in" % roundi(float(op.flank_deg)))
		"assault":
			var all := fix + main + res
			if order(w, fid, s, x.badge, {"type": "attack_move", "unit_ids": all, "target": tgt}) > 0 and not res.is_empty():
				tag(w, fid, s, "reserve_commit", res, "Op ATTACK: reserve (%d) committed." % res.size())
			if armed_near(x.bel, tgt, float(G("cluster_cell"))) <= 0.0:
				phase(w, fid, s, "consolidate", "objective (%d, %d) taken" % [int(tgt.x), int(tgt.y)])
			elif w.tick - int(op.t0) > int(G("op_timeout")):
				finish(w, fid, s, false, "attack stalled at (%d, %d)" % [int(tgt.x), int(tgt.y)])
		_:
			if not mop_up(w, fid, s, x.badge, x.ids, x.bel, tgt, float(G("cluster_cell"))):
				C().plan(w, fid, s, x.free, x.badge, "hold", tgt, x.rally)
			if w.tick - int(op.pt) >= int(G("consolidate_ticks")):
				finish(w, fid, s, true, "objective (%d, %d) consolidated" % [int(tgt.x), int(tgt.y)])


## Spec-ops infiltration / supply raid: in by wp_in (move, avoiding contact), hit, out by wp_out, home.
static func _ex_infil(w: SimWorld, fid: int, s: Dictionary, x: Dictionary) -> void:
	var op: Dictionary = s.gen.op
	var tgt: Vector2 = op.tgt
	var cen: Vector2 = x.cen
	var arr := float(G("arrive")) * 1.5
	match String(op.phase):
		"form":
			# G7 (REGRESS7-6, ORCH ruling on need 2881): a spread force (e.g. one probe survivor at the enemy base,
			# the rest at home) gathers at the rally point first; success no longer hinges on a lone man going in.
			# The route is planned from where it formed; not formed within form_ticks -> the op is called off.
			var r: Vector2 = op.rally
			order(w, fid, s, x.badge, {"type": "move", "unit_ids": x.ids, "target": r})
			if spread(w, x.ids, cen) <= float(G("form_r")):
				op.from = cen
				op.trail_in = [cen]
				op.p0 = float(x.mine)   # G7 (REGRESS7-7): the raid's loss budget counts from the formed team going in
				_infil_route(w, x.bel, op, cen)
				phase(w, fid, s, "in", "formed up at (%d, %d), going in" % [int(cen.x), int(cen.y)])
				_hold_fire(w, fid, s, x, op, true)
			elif w.tick - int(op.pt) > int(G("form_ticks")):
				finish(w, fid, s, false, "could not form up for the %s" % OP_LABEL[String(op.type)])
		"in":
			_trail(op, "trail_in", cen)
			# G7 (REGRESS7-7): waypoint by waypoint around the known defenders' sight, crouched near them, fire held
			if op.has("in_t") and w.tick - int(op.get("rp", op.pt)) >= int(G("replan_ticks")):
				op.rp = w.tick
				_replan_in(w, x, op, cen)
			var wps: Array = op.get("path_in", [Vector2(op.wp_in)])
			var pi := _wp_at(w, x, op, wps, "pi", cen, arr)
			order(w, fid, s, x.badge, {"type": "move", "unit_ids": x.ids, "target": Vector2(wps[pi])})
			_sneak_gait(w, x, op, 1)
			if (pi == wps.size() - 1 and _closed(w, x, op, "pi", Vector2(op.wp_in))) or w.tick - int(op.pt) > int(op.get("in_t", 1200)):
				_hold_fire(w, fid, s, x, op, false)
				_sneak_gait(w, x, op, 0)
				tag(w, fid, s, "raid", x.ids, "Op %s: in position at (%d, %d), hitting (%d, %d)." % [
					OP_LABEL[String(op.type)], int(op.wp_in.x), int(op.wp_in.y), int(tgt.x), int(tgt.y)])
				phase(w, fid, s, "hit", "infiltrated undetected, strike")
		"hit":
			_trail(op, "trail_in", cen)
			var best = null
			var bv := -1.0
			for b in x.bel:
				if (b.pos as Vector2).distance_to(tgt) > float(G("cluster_cell")) or bool(b.air):
					continue
				var v := float(b.value) + (2.0 if String(op.type) == "raid_supply" and bool(b.supply) else 0.0)
				if v > bv:
					bv = v
					best = b
			if best == null or w.tick - int(op.pt) >= int(G("hit_ticks")):
				tag(w, fid, s, "retreat", x.ids, "Op %s: exfil by a different route via (%d, %d)." % [
					OP_LABEL[String(op.type)], int(op.wp_out.x), int(op.wp_out.y)])
				phase(w, fid, s, "out", "target hit, exfil by the other flank")
				_exfil_route(w, x.bel, op, cen)
				return
			var o := {"type": "attack", "unit_ids": x.ids, "target": Vector2(best.pos), "target_id": int(best.id)} \
				if seen_now(w, fid).has(int(best.id)) else {"type": "attack_move", "unit_ids": x.ids, "target": Vector2(best.pos)}
			if order(w, fid, s, x.badge, o) > 0 and bool(best.supply):
				tag(w, fid, s, "sabotage", x.ids, "Op %s: hitting enemy supply at (%d, %d)." % [OP_LABEL[String(op.type)], int(best.pos.x), int(best.pos.y)])
		"out":
			_trail(op, "trail_out", cen)
			var po: Array = op.get("path_out", [Vector2(op.wp_out)])   # G7 (REGRESS7-7): out around the known sight
			var oi := _wp_at(w, x, op, po, "oi", cen, arr)
			order(w, fid, s, x.badge, {"type": "move", "unit_ids": x.ids, "target": Vector2(po[oi])})
			_sneak_gait(w, x, op, 2)
			if (oi == po.size() - 1 and cen.distance_to(op.wp_out) <= arr) or w.tick - int(op.pt) > int(op.get("out_t", 1200)):
				phase(w, fid, s, "home", "clear of the objective, back to the rally point")
		_:
			_trail(op, "trail_out", cen)
			var r: Vector2 = op.rally
			if op.has("path_home") and w.tick - int(op.get("rp", op.pt)) >= int(G("replan_ticks")):
				op.rp = w.tick
				_replan_home(w, x, op, cen)
			var hp: Array = op.get("path_home", [r])   # G7 (REGRESS7-7): home around the known defenders' sight
			var hi := _wp_at(w, x, op, hp, "hi", cen, arr)
			order(w, fid, s, x.badge, {"type": "move", "unit_ids": x.ids, "target": Vector2(hp[hi])})
			_sneak_gait(w, x, op, 2)
			if cen.distance_to(r) <= arr or w.tick - int(op.pt) > int(op.get("home_t", 1600)):
				tag(w, fid, s, "exfil_done", x.ids, "Op %s: %d survivors back at (%d, %d)." % [OP_LABEL[String(op.type)], x.ids.size(), int(r.x), int(r.y)])
				finish(w, fid, s, true, "exfil complete, %d survivors at the rally point" % x.ids.size())


## Nearest believed (ground) enemy to p within r, or null.
static func nearest_bel(bel: Array, p: Vector2, r: float):
	var best = null
	var bd := INF
	for b in bel:
		var d := (b.pos as Vector2).distance_to(p)
		if not bool(b.air) and d <= r and d < bd:
			bd = d
			best = b
	return best


## Defence in depth: fight intruders inside the base radius, else hold the base; done after a quiet spell.
static func _ex_defend(w: SimWorld, fid: int, s: Dictionary, x: Dictionary) -> void:
	var op: Dictionary = s.gen.op
	var home: Vector2 = x.home
	var t = nearest_bel(x.bel, home, float(G("base_threat_radius")))
	if t != null:
		op.quiet = w.tick
		op.tgt = Vector2(t.pos)
		if order(w, fid, s, x.badge, {"type": "attack_move", "unit_ids": x.ids, "target": Vector2(t.pos)}) > 0:
			tag(w, fid, s, "defence_depth", x.ids, "Op DEFEND: engaging intruders at (%d, %d) near the base." % [int(t.pos.x), int(t.pos.y)])
		return
	C().plan(w, fid, s, x.free, x.badge, "hold", home, x.rally)
	if w.tick - int(op.quiet) >= int(G("defend_quiet")):
		finish(w, fid, s, true, "base secure")


static func _ex_counter(w: SimWorld, fid: int, s: Dictionary, x: Dictionary) -> void:
	var op: Dictionary = s.gen.op
	var t = nearest_bel(x.bel, Vector2(op.tgt), float(G("cluster_cell")) * 1.5)
	if t == null:
		if w.tick - int(op.t0) > 100:
			finish(w, fid, s, true, "attackers thrown back")
		return
	op.tgt = Vector2(t.pos)
	if order(w, fid, s, x.badge, {"type": "attack_move", "unit_ids": x.ids, "target": Vector2(t.pos)}) > 0:
		tag(w, fid, s, "assault_phase", x.ids, "Op COUNTER-ATTACK on (%d, %d)." % [int(t.pos.x), int(t.pos.y)])
	if w.tick - int(op.t0) > int(G("op_timeout")):
		finish(w, fid, s, false, "counter-attack stalled")


## Recon in force: the first half (min 1) probes toward the target, the rest holds; done on contact.
static func _ex_recon(w: SimWorld, fid: int, s: Dictionary, x: Dictionary) -> void:
	var op: Dictionary = s.gen.op
	var tgt: Vector2 = op.tgt
	var ids: Array = x.ids
	var n := maxi(1, ids.size() / 2)
	var probe := ids.slice(0, n)
	var rest := ids.slice(n)
	order(w, fid, s, x.badge, {"type": "attack_move", "unit_ids": probe, "target": tgt})
	if not rest.is_empty():
		order(w, fid, s, x.badge, {"type": "move", "unit_ids": _away(w, rest, Vector2(op.from)), "target": Vector2(op.from)})
	var pc := centroid_of(w, probe, Vector2(op.from))
	var contact = nearest_bel(x.bel, pc, 12.0)
	if contact != null and w.tick - int(op.t0) > 40:
		tag(w, fid, s, "overwatch_set", probe, "Op RECON: contact at (%d, %d)." % [int(contact.pos.x), int(contact.pos.y)])
		finish(w, fid, s, true, "contact gained at (%d, %d)" % [int(contact.pos.x), int(contact.pos.y)])
	elif pc.distance_to(tgt) <= float(G("arrive")) * 2.0:
		finish(w, fid, s, true, "area (%d, %d) clear" % [int(tgt.x), int(tgt.y)])
	elif w.tick - int(op.t0) > int(G("op_timeout")):
		finish(w, fid, s, false, "recon made no contact")


## G7 (REGRESS7-6): the ids of `ids` farther than G("arrive") from p (already there: no re-order). A recon's rest
## waits where it is; re-sending its fall-back move to a unit a passing probe had shoved aside turned it back head-on
## into that probe (test_gen61 deliberate attack: the two deadlocked for the rest of the run).
static func _away(w: SimWorld, ids: Array, p: Vector2) -> Array:
	var out := []
	for id in ids:
		var e = w.entities.get(int(id))  # AI-FAIR: own recon rest units only (_away)
		if e != null and Vector2(e.pos).distance_to(p) > float(G("arrive")):
			out.append(id)
	return out


## Screen / delay: hold a line toward the stronger enemy; bound back when it closes in.
static func _ex_screen(w: SimWorld, fid: int, s: Dictionary, x: Dictionary) -> void:
	var op: Dictionary = s.gen.op
	var tgt: Vector2 = op.tgt
	var cen: Vector2 = x.cen
	var close := power_near(x.bel, cen, 8.0)
	if close > float(x.mine) and int(op.bounds) < 3:
		op.bounds = int(op.bounds) + 1
		op.tgt = cen + (Vector2(x.home) - cen) * 0.4
		tag(w, fid, s, "defence_depth", x.ids, "Op SCREEN: delaying, bound %d back to (%d, %d)." % [int(op.bounds), int(op.tgt.x), int(op.tgt.y)])
		phase(w, fid, s, "delay", "enemy %.1f vs %.1f closing, bound back" % [close, float(x.mine)])
	if cen.distance_to(op.tgt) > float(G("arrive")):
		order(w, fid, s, x.badge, {"type": "move", "unit_ids": x.ids, "target": Vector2(op.tgt)})
	else:
		C().plan(w, fid, s, x.free, x.badge, "hold", Vector2(op.tgt), x.rally)
	if w.tick - int(op.t0) > int(G("screen_ticks")) or int(op.bounds) >= 3:
		finish(w, fid, s, true, "screen held %d s" % ((w.tick - int(op.t0)) / SimWorld.TICK_RATE))


## Regroup / refit at the rally point (replacements and resupply come from general_war.gd).
static func _ex_refit(w: SimWorld, fid: int, s: Dictionary, x: Dictionary) -> void:
	var op: Dictionary = s.gen.op
	var r: Vector2 = op.rally
	var cen: Vector2 = x.cen
	if cen.distance_to(r) > float(G("arrive")) * 2.0:
		if order(w, fid, s, x.badge, {"type": "move", "unit_ids": x.ids, "target": r}) > 0:
			tag(w, fid, s, "regroup", x.ids, "Op REFIT: pulling back to (%d, %d) to resupply." % [int(r.x), int(r.y)])
		if w.tick - int(op.t0) < int(G("refit_ticks")) * 2:
			return
	elif String(op.phase) != "refit":
		phase(w, fid, s, "refit", "at the rally point, resupplying")
	var strength := float(x.mine) / maxf(float(s.get("peak_power", x.mine)), 0.01)
	if (strength >= float(G("refit_done")) and ammo_frac(x.us) >= 0.6) or w.tick - int(op.t0) >= int(G("refit_ticks")):
		s.peak_power = float(x.mine)
		finish(w, fid, s, true, "refit done at %d%% strength" % roundi(strength * 100.0))


## Disperses under enemy air (believed aircraft near the force): each unit steps out on its own bearing.
static func _air_check(w: SimWorld, fid: int, s: Dictionary, x: Dictionary) -> bool:
	var g: Dictionary = s.gen
	if w.tick - int(g.air_tick) < int(G("air_ticks")):
		return false
	var cen: Vector2 = x.cen
	var n := 0
	for b in x.bel:
		if bool(b.air) and (b.pos as Vector2).distance_to(cen) <= float(G("air_radius")):
			n += 1
	if n == 0:
		return false
	g.air_tick = w.tick
	var i := 0
	for id in x.ids:
		var p := clamp_map(w, cen + Vector2.RIGHT.rotated(float(i) * 2.39996) * (2.5 + float(i % 3)))
		order(w, fid, s, x.badge, {"type": "move", "unit_ids": [id], "target": p})
		i += 1
	tag(w, fid, s, "regroup", x.ids, "Enemy air overhead (%d): the force disperses." % n)
	return true


const War = preload("res://sim/ai/general_war.gd")
const War2 = preload("res://sim/ai/general_war2.gd")  # GEN61-2: production, air / call-ins, medevac, bearers
const GNet = preload("res://sim/ai/general_net.gd")  # GEN61-2: intent down CommandNet, reports up
const LOSS_OPS := ["strike", "attack", "infil", "raid_supply", "counter", "recon_force"]


## One think of an auto general (called by Commanders.drive for objective type "auto"): us = the slot's
## live units (badged), free = those not player-fresh, rally = its fall-back point (home), slot = index.
static func think(w: SimWorld, fid: int, s: Dictionary, us: Array, free: Array, badge: String, rally: Vector2, slot: int) -> void:
	if not (s.get("gen", null) is Dictionary):
		s.gen = new_gen(w)
	var g: Dictionary = s.gen
	var mine := own_power(us)
	s.peak_power = snappedf(maxf(float(s.get("peak_power", 0.0)), mine), 0.001)
	War.tick(w, fid, s, us, badge, rally, slot)
	War2.tick(w, fid, s, us, badge, rally)
	GNet.consume(w, fid, s)
	GNet.read_reports(w, fid, s, us)
	if free.is_empty():
		g.status = "Waiting: every unit is under the player's own orders."
		return
	var fset := {}
	for e in free:
		fset[int(e.id)] = true
	var home := U.base_pos(w, fid)
	var x := {"us": us, "free": free, "ids": DU.ids_of(free), "fset": fset, "cen": DU.centroid(free, rally),
		"mine": mine, "bel": belief(w, fid), "home": home, "rally": rally, "badge": badge}
	if _air_check(w, fid, s, x):
		return
	var op: Dictionary = g.op
	# break off at the stance's loss limit
	if not op.is_empty() and LOSS_OPS.has(String(op.type)):
		var lim := float((G("loss_limit") as Dictionary).get(String(s.stance), 0.45))
		var lost := 1.0 - mine / maxf(float(op.p0), 0.01)
		if lost >= lim:
			tag(w, fid, s, "retreat", x.ids, "Op %s broken off: %d%% losses past the %s limit." % [
				OP_LABEL[String(op.type)], roundi(lost * 100.0), String(s.stance)])
			finish(w, fid, s, false, "broke off at %d%% losses" % roundi(lost * 100.0))
			op = g.op
	# (re)plan: no op, or the cadence came round and something urgent (defend / refit) outranks it
	if w.tick >= int(g.next_plan) and w.tick >= int(g.pause_until):
		var cands := candidates(w, fid, s, us, home, slot)
		g.next_plan = w.tick + int(G("plan_ticks"))
		if not cands.is_empty():
			var top: Dictionary = cands[0]
			if op.is_empty():
				start(w, fid, s, top, x)
			elif ["defend", "refit"].has(String(top.type)) and not ["defend", "refit", "counter"].has(String(op.type)) 					and not (String(top.type) == "refit" and _exfiltrating(op)):
				finish(w, fid, s, false, "called off: %s" % String(top.why))
				g.next_plan = w.tick + int(G("plan_ticks"))
				g.pause_until = 0
				start(w, fid, s, top, x)
	op = g.op
	if op.is_empty():
		g.status = "Consolidating." if w.tick < int(g.pause_until) else "Assessing the situation."
		return
	match String(op.type):
		"strike":
			_ex_strike(w, fid, s, x)
		"attack":
			_ex_attack(w, fid, s, x)
		"infil", "raid_supply":
			_ex_infil(w, fid, s, x)
		"defend":
			_ex_defend(w, fid, s, x)
		"counter":
			_ex_counter(w, fid, s, x)
		"recon_force":
			_ex_recon(w, fid, s, x)
		"screen":
			_ex_screen(w, fid, s, x)
		_:
			_ex_refit(w, fid, s, x)
	if not (g.op as Dictionary).is_empty() and w.tick - int(g.op.t0) > int(G("op_timeout")) * 2:
		finish(w, fid, s, false, "op timed out")
	status_line(w, s, mine)


## Short status of a general: "Op STRIKE (move), strength 82%, budget 1200 cr".
static func status_line(w: SimWorld, s: Dictionary, mine: float) -> void:
	var g: Dictionary = s.gen
	var op: Dictionary = g.op
	var st := roundi(100.0 * mine / maxf(float(s.get("peak_power", mine)), 0.01))
	var bl := War.budget_left(w, s)
	var bud := (", budget %d cr %d salvage %d ore" % [int(bl.credits), int(bl.salvage), int(bl.ore)]) if not bl.is_empty() else ""
	if op.is_empty():
		g.status = "Assessing the situation, strength %d%%%s." % [st, bud]
	else:
		g.status = "Op %s (%s), strength %d%%%s." % [OP_LABEL.get(String(op.type), String(op.type)), String(op.phase), st, bud]


## Panel / API view of a general slot: {op, phase, status, strength, budget, ops, log (last 3)}.
static func view(w: SimWorld, s: Dictionary) -> Dictionary:
	var g = s.get("gen", null)
	if not (g is Dictionary):
		return {}
	var op: Dictionary = g.op
	var lg: Array = s.get("log", [])
	return {"op": String(op.get("type", "")), "phase": String(op.get("phase", "")), "status": String(g.status),
		"ops": (g.ops as Dictionary).duplicate(), "budget": War.budget_left(w, s),
		"log": lg.slice(maxi(0, lg.size() - 3))}


## Ids of enemies side fid can see right now (its own fog view), cached per tick. G6.1 fairness fix: the general
## used to test w.entities for believed contacts (knowing about deaths it never saw).
static func seen_now(w: SimWorld, fid: int) -> Dictionary:
	var k := "gen61_seen_%d" % fid
	var c = w.cache.get(k)
	if c != null and int(c[0]) == w.tick:
		return c[1]
	var d := {}
	for e in w.visible_enemies(fid):  # the side's own fog view
		d[int(e.id)] = true
	w.cache[k] = [w.tick, d]
	return d
