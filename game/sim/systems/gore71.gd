extends RefCounted
## G7.1 DAMAGE71 (scope J1 + B2 heavy death physics, Last Protocol only): sim gore outcome records and the persistent
## bodies / wrecks list. The view never decides an outcome: it draws these records (snapshot provider + gore71_layer).
## On: the state exists only in Last Protocol (tick creates it there; tests call enable). Off LP every hook is one
## dictionary lookup (on(w) false) and nothing is written: skirmish and the 2k / 10k benches stay hash-identical.
## Outcomes (rules.g71_gore.rounds, keyed by ballistics8 round id, PROVISIONAL): out id, sever chance (a limb lost on a
##   kill, or on a surviving limb hit with sev >= sever_sev), throw tiles (body thrown away from the shot), char, line
##   (railgun: the slug goes on through soldiers behind the target). Splash callers set ctx_rc for the call.
## Rolls: a pure hash of (entity id, tick, salt): no w.rng draw, so LP gameplay rng streams are unchanged.
## State (saved + hashed): w.sys_state.gore71 = {ver, next: int, bodies: {body id: {id, kind ("body" | "wreck"), def,
##   owner, pos: Vector2, rot, out (outcome id), t (tick), sz (radius tiles), drag (dragger id or -1), lost (limb bits),
##   ch (charred), tr (trampled), rc (round id)}}}. Entity fields (LP only): g71rc (last round id that hit it), g71fr
##   (where that hit came from), g71lost (limb bits lost while alive: 1 arm_l, 2 arm_r, 4 leg_l, 8 leg_r).
## Events: Gore71 {body, id, out, pos, from, lost, ch}, LimbLost71 {id, limb, pos}, RailLine71 {by, ids}, Trampled71
##   {body, by}. Consumers: medics recover ours (Care71), harvesters (J4, wave 3) drag, dozers (BASTION71 G2) remove,
##   C6 wrecks as cover.

const KEY := "gore71"
const Q := 1.0 / 1024.0
const LIMBS := ["arm_l", "arm_r", "leg_l", "leg_r"]
const LIMB_BIT := {"arm_l": 1, "arm_r": 2, "leg_l": 4, "leg_r": 8}
const LEG_BITS := 12

static var ctx_rc := ""        # splash round class for the duration of one Blast8 / Shrapnel call (transient)
static var _rref = null
static var _r: Dictionary = {}
static var _heavy: Dictionary = {}   # def -> bool (tramples bodies)
static var _dmg = null               # damage.gd, loaded lazily (damage.gd preloads parts71 -> no cycle here)
static var _p71 = null


static func R() -> Dictionary:
	var r: Dictionary = Content.rules()
	if not is_same(r, _rref):
		_rref = r
		_r = r.get("g71_gore", {})
		_heavy.clear()
	return _r


static func on(w: SimWorld) -> bool:
	return w.sys_state.has(KEY)


static func _st(w: SimWorld):
	return w.sys_state.get(KEY)


static func _ensure(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get(KEY)
	if st == null:
		st = {"ver": 1, "next": 1, "bodies": {}}
		w.sys_state[KEY] = st
	return st


## Creates the state (tick does this in Last Protocol; tests call it directly).
static func enable(w: SimWorld) -> Dictionary:
	return _ensure(w)


## Pure roll in [0, 1) from (id, tick, salt).
static func roll(id: int, tick: int, salt: int) -> float:
	var h := hash([id, tick, salt, 71]) & 0xFFFFFF
	return float(h) / 16777216.0


static func outcome(rc: String) -> Dictionary:
	var rs: Dictionary = R().get("rounds", {})
	if rs.has(rc):
		return rs[rc]
	return rs.get("default", {"out": "bleed"})


# ================================================================ hooks (called by damage.gd / wounds.gd / medical.gd)
## A hit on unit e by round rc from `from` (LP only: callers check on(w)).
static func note_hit(e: Dictionary, rc: String, from: Vector2) -> void:
	e["g71rc"] = rc
	e["g71fr"] = from


## A surviving soldier's limb hit (Wounds zone `zone`, severity sev = zone damage / max hp): a high-calibre round
## (rounds[rc].sever > 0) with sev >= sever_sev takes the limb off. A lost leg = crawl only (Wounds.crawling).
static func limb_hit(w: SimWorld, e: Dictionary, zone: String, sev: float) -> void:
	if not LIMB_BIT.has(zone):
		return
	var o := outcome(String(e.get("g71rc", "")))
	var p := float(o.get("sever", 0.0))
	if p <= 0.0 or sev < float(R().get("sever_sev", 0.35)):
		return
	if roll(int(e.id), w.tick, 3) >= p:
		return
	var bits := int(e.get("g71lost", 0))
	if bits & int(LIMB_BIT[zone]):
		return
	e["g71lost"] = bits | int(LIMB_BIT[zone])
	w.emit("LimbLost71", {"id": int(e.id), "limb": zone, "pos": e.pos, "owner": int(e.owner)})


## A unit died (cause as w.destroy's): records its body with the outcome of the last round that hit it.
## Soldiers and squads only (vehicles / Machines leave wrecks through Parts71 / the G6 wreck registry).
static func on_death(w: SimWorld, e: Dictionary, cause: String) -> int:
	if e.kind != "unit" or e.has("comp") or not e.has("morale"):
		return -1
	var id := int(e.id)
	var rc := String(e.get("g71rc", ctx_rc))
	var o := outcome(rc)
	var out := String(o.get("out", "bleed"))
	if cause == "bled_out" or cause == "died_of_wounds":
		out = "bled"
	elif cause == "expectant":
		out = "comfort"
	var ch := bool(o.get("char", false))
	if _p71 == null:
		_p71 = load("res://sim/systems/parts71.gd")
	if _p71.burning(e):
		ch = true
		out = "charred"
	var pos := Vector2(e.pos)
	var from := Vector2(e.get("g71fr", pos))
	var dir := pos - from
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT.rotated(TAU * roll(id, w.tick, 1))
	var off := 0.0
	if out != "bled" and out != "comfort":
		off = float(o.get("throw", 0.0)) * (0.5 + 0.5 * roll(id, w.tick, 2))
		if ch:
			off += float(R().get("burn_run", 0.0))   # burning soldiers run a few steps, then fall
	if off > 0.0:
		var to := pos + dir * off
		var mw := float(w.map.get("w", 0))
		var mh := float(w.map.get("h", 0))
		if mw > 0.0 and mh > 0.0:
			to = Vector2(clampf(to.x, 0.5, mw - 0.5), clampf(to.y, 0.5, mh - 0.5))
		pos = Vector2(snappedf(to.x, Q), snappedf(to.y, Q))
	var lost := int(e.get("g71lost", 0))
	var sp := float(o.get("sever", 0.0))
	if sp > 0.0 and out != "bled" and out != "comfort" and roll(id, w.tick, 4) < sp:
		lost |= int(LIMB_BIT[LIMBS[int(roll(id, w.tick, 5) * 4.0) % 4]])
	var bid := add_body(w, {"kind": "body", "def": String(e.def), "owner": int(e.owner), "pos": pos,
		"rot": snappedf(dir.angle(), Q), "out": out, "t": w.tick, "sz": 0.4, "lost": lost, "ch": ch, "tr": 0, "rc": rc})
	w.emit("Gore71", {"body": bid, "id": id, "out": out, "pos": pos, "from": Vector2(e.pos), "lost": lost, "ch": ch})
	return bid


## Railgun line-through (rounds[rc].line): after the slug hits `target`, it goes on along the shot line and hits up to
## line.n more units of other sides behind it (within line.len tiles, line.w half-width), nearest first, ties by id;
## each takes dmg x line.falloff^k through Damage.wound_hit. Air units are skipped.
static func rail_line(w: SimWorld, shooter: Dictionary, target: Dictionary, rc: String, dmg: float) -> void:
	var ln = outcome(rc).get("line")
	if not ln is Dictionary or shooter.is_empty():
		return
	var a := Vector2(target.pos)
	var dir := a - Vector2(shooter.pos)
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	var L := float(ln.get("len", 8.0))
	var hw := float(ln.get("w", 0.45))
	var b := a + dir * L
	var mid := (a + b) * 0.5
	var cand := []
	var ng = w.cache.get("combat_ng")
	if ng != null:
		for cid in ng.grid.query_radius(mid, L * 0.5 + 1.0):
			cand.append(int(cid))
	else:
		for id in w.entities:
			var u0 = w.entities[id]
			if u0.kind == "unit" and Vector2(u0.pos).distance_to(mid) <= L * 0.5 + 1.0:
				cand.append(int(id))
	var hits := []
	for cid in cand:
		var u = w.entities.get(int(cid))
		if u == null or u.kind != "unit" or int(u.id) == int(target.id) or int(u.owner) == int(shooter.owner):
			continue
		if String(Content.unit(String(u.def)).get("move_class", "foot")).begins_with("air"):
			continue
		var p := Vector2(u.pos) - a
		var along := p.dot(dir)
		if along <= 0.0 or along > L or absf(p.cross(dir)) > hw:
			continue
		hits.append([snappedf(along, Q), int(u.id)])
	if hits.is_empty():
		return
	hits.sort()
	var n := mini(int(ln.get("n", 3)), hits.size())
	var f := float(ln.get("falloff", 0.7))
	if _dmg == null:
		_dmg = load("res://sim/systems/damage.gd")
	var ids := []
	var d := dmg
	var prev := ctx_rc
	ctx_rc = rc   # Damage.wound_hit notes this round on each unit it hits
	for i in n:
		var u = w.entities.get(int(hits[i][1]))
		if u == null:
			continue
		d = snappedf(d * f, Q)
		ids.append(int(u.id))
		_dmg.wound_hit(w, shooter, u, d)
	ctx_rc = prev
	w.emit("RailLine71", {"by": int(shooter.id), "ids": ids, "from": a, "to": b})


# ================================================================ bodies API (fact gore71.api)
## Records one settled body / wreck; returns its body id. (Internal to DAMAGE71's pipeline; public for tests.)
static func add_body(w: SimWorld, rec: Dictionary) -> int:
	var st := _ensure(w)
	var bid := int(st.next)
	st.next = bid + 1
	var b := rec.duplicate()
	b["id"] = bid
	if not b.has("drag"):
		b["drag"] = -1
	(st.bodies as Dictionary)[bid] = b
	return bid


## Bodies / wrecks within r tiles of pos, ascending body id (each a dict as stored; read-only for callers).
static func bodies_near(w: SimWorld, pos: Vector2, r: float) -> Array:
	var st = _st(w)
	var out := []
	if st == null:
		return out
	var r2 := r * r
	var ids: Array = (st.bodies as Dictionary).keys()
	ids.sort()
	for bid in ids:
		var b: Dictionary = st.bodies[bid]
		if Vector2(b.pos).distance_squared_to(pos) <= r2:
			out.append(b)
	return out


## Every body / wreck (the stored dict keyed by body id; read-only for callers: snapshot provider, tests).
static func bodies(w: SimWorld) -> Dictionary:
	var st = _st(w)
	return {} if st == null else st.bodies


## Moves body body_id to `to` (a dragger walking it there sets b.drag itself). false = no such body.
static func drag(w: SimWorld, body_id: int, to: Vector2) -> bool:
	var st = _st(w)
	if st == null or not (st.bodies as Dictionary).has(body_id):
		return false
	var b: Dictionary = st.bodies[body_id]
	b.pos = to
	b["t"] = w.tick
	return true


## Removes body body_id (dragged into the tide, cleared by a dozer, recovered). false = no such body.
static func remove(w: SimWorld, body_id: int) -> bool:
	var st = _st(w)
	if st == null or not (st.bodies as Dictionary).has(body_id):
		return false
	(st.bodies as Dictionary).erase(body_id)
	return true


# ================================================================ tick: trample
static func _is_heavy(def_id: String) -> bool:
	if _heavy.has(def_id):
		return bool(_heavy[def_id])
	var tr: Dictionary = R().get("trample", {})
	var d := Content.unit(def_id)
	var mc := String(d.get("move_class", "foot"))
	var h := false
	for c in tr.get("classes", ["tracked"]):
		if mc.begins_with(String(c)):
			h = true
	if float(d.get("radius", 0.4)) < float(tr.get("min_radius", 0.0)):
		h = false
	if (tr.get("defs", []) as Array).has(def_id):
		h = true
	_heavy[def_id] = h
	return h


## Last Protocol: creates the state; then every trample.every ticks one slice (body id % slices == phase) of the
## bodies not yet trampled checks for a heavy unit (tracked vehicle, heavy Machine) on top of it: trampled (tr 1).
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get(KEY)
	if st == null:
		if not SimWorld.LastProtocol.active(w) or not bool(R().get("enabled", true)):
			return
		st = _ensure(w)
	var bd: Dictionary = st.bodies
	if bd.is_empty():
		return
	var tr: Dictionary = R().get("trample", {})
	var every := maxi(int(tr.get("every", 15)), 1)
	if w.tick % every != 7:
		return
	var ng = w.cache.get("combat_ng")
	if ng == null:
		return
	var slices := maxi(int(tr.get("slices", 4)), 1)
	var phase := int(w.tick / every) % slices
	var ids: Array = []
	for bid in bd:
		if int(bid) % slices == phase and int(bd[bid].get("tr", 0)) == 0 and String(bd[bid].kind) == "body":
			ids.append(bid)
	ids.sort()
	var rr := float(tr.get("r", 0.9))
	for bid in ids:
		var b: Dictionary = bd[bid]
		var best := -1
		for cid in ng.grid.query_radius(Vector2(b.pos), rr):
			var u = w.entities.get(int(cid))
			if u != null and u.kind == "unit" and _is_heavy(String(u.def)) and (best < 0 or int(cid) < best):
				best = int(cid)
		if best >= 0:
			b["tr"] = 1
			w.emit("Trampled71", {"body": int(bid), "by": best, "pos": b.pos})


static func validate_command(_w: SimWorld, _cmd: Dictionary) -> String:
	return "unknown command"


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass
