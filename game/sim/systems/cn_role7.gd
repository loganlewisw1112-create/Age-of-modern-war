extends RefCounted
## CnRole7 (G7 CNROLE7, owner note 13.9c-29 + B16): counter-nanite strike teams and tactical / spec-ops squads are
## NEVER on base defence. This file is the one place that says who they are and when they are "parked"; every
## automatic system that hands out defence / garrison / reserve / QRF / escort jobs asks it first.
##
## Who: any entity with e.cn_team (set on the team's soldiers and APCs by CnFacility / CounterNanite.spawn_team), or a
## unit whose def carries cn_line (g7_cn_* strike, g7_op_* operator, and the g7_b_ copies), an apc7 block of kind
## strike / tactical (their APCs), or cn_suit (the team's armoured suits). Never a def-id prefix: "g7_b_" also names the
## Human B Sentinels, drones and facility engineers, which are not teams.
## Parked: a CN unit standing inside the compound of one of its own side's facilities (garages, pad, staging, decon,
## barracks). Between missions it holds there: Combat lets an idle parked unit fire at what is in range but never
## chase or sally (like a soldier on the wall-walk). Outside the compound (on a mission) nothing changes.
## Player orders are never touched: this only filters automatic systems, and a parked unit still obeys any order.
##
## Pure functions of state, no saved state, no RNG. A match without a facility pays one dictionary lookup.
## Preloads nothing (Combat and Movement load this file): CnFacility is loaded lazily.

const CF_PATH := "res://sim/systems/cn_facility.gd"
const FAC_KEY := "cn_facility"
## The compound rect is grown by this many tiles: the gate apron and the staging smoke belong to "home".
const HOME_PAD := 1.5

static var _cf = null
## def id -> bool. A pure function of the content tables; an unknown def is never cached (fragments load late).
static var _dc := {}


## True for the defs of a strike-team / operator soldier, a CN APC or a CN armoured suit.
static func is_cn_def(def_id: String) -> bool:
	var c = _dc.get(def_id)
	if c != null:
		return bool(c)
	var d: Dictionary = Content.unit(def_id)
	if d.is_empty():
		return false
	var ap = d.get("apc7")
	var v := d.has("cn_line") or String(d.get("cn_suit", "")) != ""
	if not v and ap is Dictionary:
		var k := String((ap as Dictionary).get("kind", ""))
		v = k == "strike" or k == "tactical"
	_dc[def_id] = v
	return v


## True when e is a strike-team / tactical-squad unit (soldier, APC or suit). Accepts any entity dictionary.
static func is_cn(e) -> bool:
	if not (e is Dictionary):
		return false
	if e.has("cn_team"):
		return true
	return String(e.get("kind", "")) == "unit" and is_cn_def(String(e.get("def", "")))


## The units of an array that are not CN (same order). Used by the AI paths that build their own rosters.
static func without_cn(us: Array) -> Array:
	var out := []
	for e in us:
		if not is_cn(e):
			out.append(e)
	return out


static func _cnfac():
	if _cf == null:
		_cf = load(CF_PATH)
	return _cf


## Compound rects (grown by HOME_PAD) of fid's facilities, rebuilt at most once per tick.
static func _homes(w: SimWorld, fid: int) -> Array:
	var c = w.cache.get("cnr7_homes")
	if c == null or int(c.t) != w.tick:
		c = {"t": w.tick, "by": {}}
		w.cache["cnr7_homes"] = c
	var by: Dictionary = c.by
	var r = by.get(fid)
	if r == null:
		r = []
		var cf = _cnfac()
		for id in cf.facilities(w, fid):
			var F: Dictionary = cf.fac(w, int(id))
			if not F.is_empty():
				r.append((cf.compound_rect(F) as Rect2).grow(HOME_PAD))
		by[fid] = r
	return r


## True when e stands inside the compound of a facility of its own side.
static func at_home(w: SimWorld, e: Dictionary) -> bool:
	if not w.sys_state.has(FAC_KEY) or not e.has("pos"):
		return false
	var p: Vector2 = e.pos
	for rc in _homes(w, int(e.owner)):
		if (rc as Rect2).has_point(p):
			return true
	return false


## True for a CN unit at home between missions: it holds its post (Combat: no chase, no sally; SquadAI: no
## support moves). One dictionary lookup when no facility exists.
static func parked(w: SimWorld, e: Dictionary) -> bool:
	return w.sys_state.has(FAC_KEY) and is_cn(e) and at_home(w, e)
