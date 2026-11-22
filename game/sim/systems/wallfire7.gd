extends RefCounted
## WallFire7 (owner: WALLFIRE7). G7_REFERENCE 13.9c-35, owner: "NO unit can shoot from inside outside the walls UNLESS
## they are on the wall walkways our outside the wall(s)", with the owner's "Realistic exemptions" answer.
## Direct fire whose line crosses a facility wall cell (counter-nanite facility parts with cn_part wall / tower /
## checkpoint / link_wall, or a def with "blocks_fire": true; "blocks_fire": false opts out) is blocked both ways.
## A closed vehicle gate (F.gate o / i == "closed") blocks like the wall; an open gate cell is a gap; a destroyed wall
## piece is a gap. Fortify walls / gates (LP rings, player walls) keep Fortify.fire_blocked's rule (built wall and gate
## cells block, fort towers fire over) under the same exemptions.
## Exempt (fire over / past the wall): indirect fire (s.indirect: mortars, howitzers, artillery), anything airborne
## shooting or being shot (Elevation.is_air), raised mounts (a building shooter whose def has tower / ciws /
## wall_turret / roof / rooftop / raised, a cn_part tower / checkpoint / wall / link_wall, e.cn_sentry, or
## "fires_over_walls": true on any def), a shooter on the wall-walk (WallWalk7.on_wall) and a target up on the
## wall-walk (exposed to fire from outside). The shooter's own cell and the target's own cell / footprint never block
## (a wall can always be shot at).
## Cost: no facility -> one dictionary lookup. Per query and facility: a bounding-box reject, then an O(1) side test
## (interior <-> outside while the ring is whole and the outer gate shut = blocked); only a holed ring, an open outer
## gate or an endpoint on the wall band walks the compound's own cell mask (supercover, cells inside the compound only).
## State: none saved. The cell mask is a pure function of the facility parts (w.cache, rebuilt when the parts list
## changes; part liveness and gate state are read live), so the rule is deterministic and save / load safe.

const Elevation = preload("res://sim/systems/elevation.gd")
const WallWalk7 = preload("res://sim/systems/wallwalk7.gd")
const Fortify = preload("res://sim/systems/fortify.gd")
const FAC_KEY := "cn_facility"
const CKEY := "wallfire7"
const BAND := 2   # wall ring thickness in tiles (CnFacility lays the ring in 2x2 pieces)
const WALL_PARTS := ["wall", "tower", "checkpoint", "link_wall"]
const RAISED_PARTS := ["tower", "checkpoint", "wall", "link_wall"]
const RAISED_KEYS := ["tower", "ciws", "wall_turret", "roof", "rooftop", "raised"]
const GATE_O := -1
const GATE_I := -2

static var _cf = null
static var _raised_cache := {}
static var enabled := true   # probe / bench switch only (false = the pre-13.9c-35 rule: Fortify walls only)


static func _cnfac():
	if _cf == null:
		_cf = load("res://sim/systems/cn_facility.gd")
	return _cf


## True while a facility wall can block anything (else every check below is neutral).
static func any(w: SimWorld) -> bool:
	if not enabled:
		return false
	var S = w.sys_state.get(FAC_KEY)
	return S != null and not (S.get("facs", {}) as Dictionary).is_empty()


## True when building / unit def d fires over a wall (raised mount or explicit opt-in).
static func _raised_def(def_id: String, is_bld: bool) -> bool:
	var k := ("b:" if is_bld else "u:") + def_id
	var v = _raised_cache.get(k)
	if v != null:
		return v
	var d: Dictionary = Content.building(def_id) if is_bld else Content.unit(def_id)
	var r := false
	if d.has("fires_over_walls"):
		r = bool(d.fires_over_walls)
	elif is_bld:
		r = RAISED_PARTS.has(String(d.get("cn_part", "")))
		for key in RAISED_KEYS:
			if r:
				break
			var x = d.get(key)
			r = x != null and not (x is bool and not x) and not (x is String and x == "")
	_raised_cache[k] = r
	return r


## Shooter-side exemptions (indirect, airborne, raised mount, on the wall-walk).
static func shooter_exempt(w: SimWorld, e: Dictionary, s: Dictionary) -> bool:
	if bool(s.get("indirect", false)) or Elevation.is_air(e):
		return true
	if SimWorld.Walls71.port_exempt(w, e):   # G7.1 BASTION71 G3: hidden firing port / pop-out slit (no walls71 state = false)
		return true
	var kind := String(e.get("kind", ""))
	if kind == "building":
		return bool(e.get("cn_sentry", false)) or _raised_def(String(e.get("def", "")), true)
	if _raised_def(String(e.get("def", "")), false):
		return true
	return WallWalk7.on_wall(w, e)


## Target-side exemptions (airborne, up on the wall-walk).
static func target_exempt(w: SimWorld, t: Dictionary) -> bool:
	return Elevation.is_air(t) or WallWalk7.on_wall(w, t)


## Full direct-fire rule for shooter e (weapon stats s) at target t: true = the wall stops the shot.
static func blocked(w: SimWorld, e: Dictionary, s: Dictionary, t: Dictionary) -> bool:
	if not enabled:
		return Fortify.fire_blocked(w, e, t)
	var fac := any(w)
	if not fac and Fortify._los_mask(w) == null:
		return false   # no facility and no built fort wall / gate: nothing to block (cheap exit)
	if shooter_exempt(w, e, s) or target_exempt(w, t):
		return false
	if fac and fac_blocked(w, e, t):
		return true
	return Fortify.fire_blocked(w, e, t)


## Target picking: true when shooter e may consider candidate c (facility walls only; Fortify walls keep their
## fire-time check). Callers check shooter_exempt once per search and skip this for exempt shooters.
static func cand_ok(w: SimWorld, e: Dictionary, c: Dictionary) -> bool:
	return target_exempt(w, c) or not fac_blocked(w, e, c)


## True when the segment shooter -> target crosses a live wall cell / closed gate of any facility (no exemptions).
static func fac_blocked(w: SimWorld, e: Dictionary, t: Dictionary) -> bool:
	var S = w.sys_state.get(FAC_KEY)
	if S == null:
		return false
	var facs: Dictionary = S.get("facs", {})
	if facs.is_empty():
		return false
	var a: Vector2 = e.pos
	var b: Vector2 = t.pos
	var skip := Rect2i(Vector2i(floori(b.x), floori(b.y)), Vector2i(1, 1))
	if String(t.get("kind", "")) == "building" and t.has("cell"):
		skip = Rect2i(Vector2i(t.cell), Vector2i(int(t.get("size", 1)), int(t.get("size", 1))))
	for k in facs:
		if _seg_blocked(w, facs[k], a, b, skip):
			return true
	return false


## Mask of facility F: {o: Vector2i, cs, m: PackedInt32Array (part id, GATE_O / GATE_I, 0), ring: [part ids],
## holed: bool (a band cell no part / gate covers), ib: Rect2 (interior walls' box, local), n: parts count}.
static func _mask(w: SimWorld, F: Dictionary) -> Dictionary:
	var C = w.cache.get(CKEY)
	if C == null:
		C = {}
		w.cache[CKEY] = C
	var fid := int(F.get("id", -1))
	var parts: Array = F.get("parts", [])
	var M = C.get(fid)
	if M != null and int(M.n) == parts.size():
		return M
	var CF = _cnfac()
	var O: Vector2i = CF.origin(F)
	var cs := int(CF.conf().compound)
	var m := PackedInt32Array()
	m.resize(cs * cs)
	var ring := []
	var ib := Rect2()
	var ib_set := false
	for pid in parts:
		var p = w.entities.get(int(pid))
		if p == null or String(p.get("kind", "")) != "building":
			continue
		var d: Dictionary = Content.building(String(p.def))
		var bf = d.get("blocks_fire")
		var isw: bool = bool(bf) if bf != null else WALL_PARTS.has(String(d.get("cn_part", "")))
		if not isw:
			continue
		var c0 := Vector2i(p.cell) - O
		var sz := int(p.size)
		var in_band := false
		for y in sz:
			for x in sz:
				var q := c0 + Vector2i(x, y)
				if q.x < 0 or q.y < 0 or q.x >= cs or q.y >= cs:
					continue
				m[q.y * cs + q.x] = int(pid)
				if _region(Vector2(q) + Vector2(0.5, 0.5), cs) == 2:
					in_band = true
		if in_band:
			ring.append(int(pid))
		else:
			var r := Rect2(Vector2(c0), Vector2(sz, sz))
			ib = r if not ib_set else ib.merge(r)
			ib_set = true
	for zn in [["gate_outer", GATE_O], ["gate_inner", GATE_I]]:
		var z: Rect2 = CF.zone(F, String(zn[0]))
		for y in range(int(z.position.y), int(z.end.y)):
			for x in range(int(z.position.x), int(z.end.x)):
				var q := Vector2i(x, y) - O
				if q.x >= 0 and q.y >= 0 and q.x < cs and q.y < cs and m[q.y * cs + q.x] == 0:
					m[q.y * cs + q.x] = int(zn[1])
	var holed := false
	for y in cs:
		for x in cs:
			if m[y * cs + x] == 0 and _region(Vector2(x, y) + Vector2(0.5, 0.5), cs) == 2:
				holed = true
	ring.sort()
	M = {"o": O, "cs": cs, "m": m, "ring": ring, "holed": holed, "ib": ib, "ib_set": ib_set, "n": parts.size(), "it": -1, "whole": false}
	C[fid] = M
	return M


## 0 outside the compound, 1 interior, 2 on the wall band (local tile coordinates).
static func _region(q: Vector2, cs: int) -> int:
	if q.x < 0.0 or q.y < 0.0 or q.x >= float(cs) or q.y >= float(cs):
		return 0
	if q.x >= float(BAND) and q.y >= float(BAND) and q.x < float(cs - BAND) and q.y < float(cs - BAND):
		return 1
	return 2


static func _gate_shut(F: Dictionary, code: int) -> bool:
	var GT = F.get("gate")
	if not GT is Dictionary or (GT as Dictionary).is_empty():
		return false
	return String(GT.get("o" if code == GATE_O else "i", "open")) == "closed"


## Ring whole this tick: every ring piece stands, no uncovered band cell, outer gate shut (cached per tick).
static func _whole(w: SimWorld, F: Dictionary, M: Dictionary) -> bool:
	if int(M.it) == w.tick:
		return bool(M.whole)
	var ok: bool = not bool(M.holed) and _gate_shut(F, GATE_O)
	if ok:
		for pid in M.ring:
			if not w.entities.has(int(pid)):
				ok = false
				break
	M.it = w.tick
	M.whole = ok
	return ok


static func _seg_blocked(w: SimWorld, F: Dictionary, a: Vector2, b: Vector2, skip: Rect2i) -> bool:
	var M := _mask(w, F)
	var O: Vector2i = M.o
	var cs := int(M.cs)
	var la := a - Vector2(O)
	var lb := b - Vector2(O)
	if maxf(la.x, lb.x) < 0.0 or maxf(la.y, lb.y) < 0.0 or minf(la.x, lb.x) >= float(cs) or minf(la.y, lb.y) >= float(cs):
		return false
	var ra := _region(la, cs)
	var rb := _region(lb, cs)
	if ra == 1 and rb == 1:
		if not bool(M.ib_set):
			return false
		var ib: Rect2 = M.ib
		if maxf(la.x, lb.x) < ib.position.x or minf(la.x, lb.x) > ib.end.x or maxf(la.y, lb.y) < ib.position.y or minf(la.y, lb.y) > ib.end.y:
			return false
	elif ra + rb == 1 and _whole(w, F, M):
		return true   # interior <-> outside across a whole ring with the outer gate shut
	return _walk(w, F, M, la, lb, Rect2i(skip.position - O, skip.size))


static func _hit(w: SimWorld, F: Dictionary, m: PackedInt32Array, cs: int, c: Vector2i, skip: Rect2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= cs or c.y >= cs or skip.has_point(c):
		return false
	var v := m[c.y * cs + c.x]
	if v > 0:
		return w.entities.has(v)
	if v < 0:
		return _gate_shut(F, v)
	return false


## Supercover walk (as Damage.line_clear / Fortify._walk_blocked) in compound-local tiles; the start cell never blocks.
static func _walk(w: SimWorld, F: Dictionary, M: Dictionary, from: Vector2, to: Vector2, skip: Rect2i) -> bool:
	var m: PackedInt32Array = M.m
	var cs := int(M.cs)
	var c := Vector2i(floori(from.x), floori(from.y))
	var end := Vector2i(floori(to.x), floori(to.y))
	var d := to - from
	var sx := 1 if d.x > 0.0 else -1
	var sy := 1 if d.y > 0.0 else -1
	var tdx := INF if d.x == 0.0 else absf(1.0 / d.x)
	var tdy := INF if d.y == 0.0 else absf(1.0 / d.y)
	var tmx := INF
	if d.x > 0.0:
		tmx = (float(c.x + 1) - from.x) * tdx
	elif d.x < 0.0:
		tmx = (from.x - float(c.x)) * tdx
	var tmy := INF
	if d.y > 0.0:
		tmy = (float(c.y + 1) - from.y) * tdy
	elif d.y < 0.0:
		tmy = (from.y - float(c.y)) * tdy
	var n := absi(end.x - c.x) + absi(end.y - c.y)
	while n > 0:
		if absf(tmx - tmy) < 1e-9:
			if _hit(w, F, m, cs, c + Vector2i(sx, 0), skip) or _hit(w, F, m, cs, c + Vector2i(0, sy), skip):
				return true
			c += Vector2i(sx, sy)
			tmx += tdx
			tmy += tdy
			n -= 2
		elif tmx < tmy:
			c.x += sx
			tmx += tdx
			n -= 1
		else:
			c.y += sy
			tmy += tdy
			n -= 1
		if _hit(w, F, m, cs, c, skip):
			return true
	return false
