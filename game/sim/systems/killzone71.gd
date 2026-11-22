extends RefCounted
## G7.1 FIRES71 (docs/G71_SCOPE.md D5 KILLZONE + the B4 FPF strips): fire sectors, auto zones, FPF strips.
## Last Protocol only (roster 5A Q1): commands are refused outside LP; with no state every query is one dict lookup.
##
## Sectors (painted, hard): a sector is a GROUND AREA (apex, centre angle c, width aw (rad), rmin..rmax tiles). A unit /
##   building with a painted sector engages only targets inside it (allow), except in self-defence (target within
##   rules.g71_killzone.self_defence_r tiles of the shooter). The area stays where it was painted when the unit moves.
##   kz_paint {issuer, unit_ids?, building_ids?, at [x, y] (drag end), apex? [x, y] (drag start; default: the members'
##     centroid), arc_deg? (default arc_deg_default), rmin? (tiles)}: every own member with a weapon gets a slice.
##   Group split (PROVISIONAL): members sorted by their signed angle around the apex relative to the drag direction
##     (then id) are dealt into S = min(N, max_slices) equal sub-arcs left to right (member k -> slice k * S / N), each
##     widened by overlap_frac on both sides so neighbours overlap. One member = the whole sector.
##   kz_clear {issuer, unit_ids?, building_ids?}: drops the members' painted sectors (auto zones apply again).
## Auto zones (advisory, PROVISIONAL rules.g71_killzone.auto.restrict = false): anything unset reports a sensible zone
##   (sector_of(...).auto = true): defences on the LP outer ring cover their wall face (apex = the defence, centre = the
##   face normal, auto.turret_arc_deg wide so neighbours overlap); other units cover their LP compass sector (apex = the
##   base centre, 8 sectors of 45 deg + overlap = auto.squad_arc_deg). Auto zones never override a painted sector and
##   never restrict fire while auto.restrict is false (so an unpainted LP army fights exactly as before).
## FPF strips (B4): one per face of the LP outer ring (face m: 0 +x E, 1 +y S, 2 -x W, 3 -y N, the WallTurret7 mount
##   convention). Default: the centre line runs parallel to the face fpf.out_tiles outside it along the whole face,
##   fpf.depth_tiles deep. fpf_paint {issuer, face, a [x, y], b [x, y]} repaints the line (the player's own strip).
##
## API (fact killzone71.api; BASTION71 turret retarget + ARMY71 squad / MG target choice call it through a guard):
##   allow(w, shooter, target_pos) -> bool, sector_of(w, eid) -> Dictionary, fpf_strip(w, face) -> Dictionary,
##   face_of(w, pos) -> int (-1 outside LP), faces(w) -> Array, strip_points(w, face, n) -> Array, in_strip(w, face, p),
##   on(w) -> bool.
## State (saved, hashed; created by the first kz_paint / fpf_paint only): w.sys_state.killzone71 = {ver, v (bumped
##   on every change), sec: {"id": {c, aw, r0, r1, ax, ay, g}}, strips: {"m": {ax, ay, bx, by}}, next_g}.
## Runtime cache (never saved; rebuilt from state when st.v changes): w.cache.kz71 = {v, m: {int id: rec}}.
## Cost: allow() for a shooter without a painted sector = one null check + one int-keyed lookup. tick() runs only with
##   state, every PRUNE_EVERY ticks (drops sectors of dead members). Determinism: sorted ids, no randomness, floats
##   snapped to 1/1024.

const KEY := "killzone71"
const VER := 1
const Q := 1.0 / 1024.0
const PRUNE_EVERY := 40
const COMMANDS := ["kz_paint", "kz_clear", "fpf_paint"]


static func R() -> Dictionary:
	return Content.rules().get("g71_killzone", {})


static func FR() -> Dictionary:
	return Content.rules().get("g71_fires", {}).get("fpf", {})


static func _rf(d: Dictionary, k: String, dflt: float) -> float:
	return float(d.get(k, dflt))


static func on(w: SimWorld) -> bool:
	return w.sys_state.has(KEY)


static func lp_on(w: SimWorld) -> bool:
	return SimWorld.LastProtocol.active(w)


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"ver": VER, "v": 0, "sec": {}, "strips": {}, "next_g": 1}
	return w.sys_state[KEY]


static func _sn(x: float) -> float:
	return snappedf(x, Q)


static func _wrap(a: float) -> float:
	return wrapf(a, -PI, PI)


# ================================================================ geometry: the LP outer ring and its faces
## The LP outer ring rect (Rect2i), or an empty rect outside LP / before the base exists.
static func ring_rect(w: SimWorld) -> Rect2i:
	var s = SimWorld.LastProtocol.st(w)
	if s == null or not (s as Dictionary).has("base"):
		return Rect2i()
	var rings: Array = s.base.get("rings", [])
	if rings.is_empty():
		return Rect2i()
	var r = rings[0].get("rect")
	return r if r is Rect2i else Rect2i()


static func base_centre(w: SimWorld) -> Vector2:
	var r := ring_rect(w)
	return Vector2(r.position) + Vector2(r.size) * 0.5


## Outward normal of face m.
static func normal(m: int) -> Vector2:
	return [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)][m & 3]


## [a, b]: the wall line of face m (world tiles, outer edge of the ring rect).
static func face_line(w: SimWorld, m: int) -> Array:
	var r := ring_rect(w)
	var p0 := Vector2(r.position)
	var p1 := Vector2(r.end)
	match m & 3:
		0:
			return [Vector2(p1.x, p0.y), Vector2(p1.x, p1.y)]
		1:
			return [Vector2(p0.x, p1.y), Vector2(p1.x, p1.y)]
		2:
			return [Vector2(p0.x, p0.y), Vector2(p0.x, p1.y)]
	return [Vector2(p0.x, p0.y), Vector2(p1.x, p0.y)]


static func faces(w: SimWorld) -> Array:
	return [] if ring_rect(w).size == Vector2i.ZERO else [0, 1, 2, 3]


## Nearest outer-ring face to pos (ties: lower m); -1 without an LP ring.
static func face_of(w: SimWorld, pos: Vector2) -> int:
	var r := ring_rect(w)
	if r.size == Vector2i.ZERO:
		return -1
	var d := [absf(pos.x - float(r.end.x)), absf(pos.y - float(r.end.y)), absf(pos.x - float(r.position.x)), absf(pos.y - float(r.position.y))]
	var best := 0
	for m in range(1, 4):
		if float(d[m]) < float(d[best]):
			best = m
	return best


## Distance from pos to the outer ring wall of face m (signed: + outside).
static func out_dist(w: SimWorld, m: int, pos: Vector2) -> float:
	var ln := face_line(w, m)
	return (pos - Vector2(ln[0])).dot(normal(m))


# ================================================================ FPF strips
## {face, a [x, y], b [x, y], depth, out, painted} or {} (no LP ring / bad face).
static func fpf_strip(w: SimWorld, face) -> Dictionary:
	if typeof(face) != TYPE_INT and typeof(face) != TYPE_FLOAT:
		return {}
	var m := int(face)
	if m < 0 or m > 3 or ring_rect(w).size == Vector2i.ZERO:
		return {}
	var depth := _rf(FR(), "depth_tiles", 3.0)
	var st = w.sys_state.get(KEY)
	if st != null and (st.strips as Dictionary).has(str(m)):
		var s: Dictionary = st.strips[str(m)]
		var a := Vector2(float(s.ax), float(s.ay))
		var b := Vector2(float(s.bx), float(s.by))
		return {"face": m, "a": [a.x, a.y], "b": [b.x, b.y], "depth": depth, "out": _sn(out_dist(w, m, (a + b) * 0.5)), "painted": true}
	var out := _rf(FR(), "out_tiles", 10.0)
	var ln := face_line(w, m)
	var off := normal(m) * out
	var a2: Vector2 = Vector2(ln[0]) + off
	var b2: Vector2 = Vector2(ln[1]) + off
	return {"face": m, "a": [_sn(a2.x), _sn(a2.y)], "b": [_sn(b2.x), _sn(b2.y)], "depth": depth, "out": out, "painted": false}


## n aim points spread evenly along the strip centre line (i + 0.5 spacing), rows alternating across the depth.
static func strip_points(w: SimWorld, face: int, n: int) -> Array:
	var s := fpf_strip(w, face)
	var out := []
	if s.is_empty() or n <= 0:
		return out
	var a := Vector2(float(s.a[0]), float(s.a[1]))
	var b := Vector2(float(s.b[0]), float(s.b[1]))
	var nrm := normal(face)
	var dep := float(s.depth)
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var row := (float(i % 3) - 1.0) * dep / 3.0
		var p := a.lerp(b, t) + nrm * row
		out.append(Vector2(_sn(p.x), _sn(p.y)))
	return out


## True when pos lies inside face m's strip (centre line +- depth / 2).
static func in_strip(w: SimWorld, face: int, pos: Vector2) -> bool:
	var s := fpf_strip(w, face)
	if s.is_empty():
		return false
	var a := Vector2(float(s.a[0]), float(s.a[1]))
	var b := Vector2(float(s.b[0]), float(s.b[1]))
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.0001:
		return false
	var t := (pos - a).dot(ab) / l2
	if t < 0.0 or t > 1.0:
		return false
	return (a + ab * t).distance_to(pos) <= float(s.depth) * 0.5 + 0.0001


# ================================================================ sectors
static func _cache(w: SimWorld, st: Dictionary) -> Dictionary:
	var c = w.cache.get("kz71")
	if c != null and int(c.v) == int(st.v):
		return c
	var m := {}
	for k in st.sec:
		m[int(k)] = st.sec[k]
	c = {"v": int(st.v), "m": m}
	w.cache["kz71"] = c
	return c


static func in_sector(rec: Dictionary, p: Vector2) -> bool:
	var d := p - Vector2(float(rec.ax), float(rec.ay))
	var l2 := d.length_squared()
	var r0 := float(rec.r0)
	var r1 := float(rec.r1)
	if l2 < r0 * r0 or l2 > r1 * r1:
		return false
	if l2 <= 0.0001:
		return true
	return absf(_wrap(d.angle() - float(rec.c))) <= float(rec.aw) * 0.5 + 0.0001


## true = shooter may engage at target_pos. No state / no painted sector = true (one lookup).
static func allow(w: SimWorld, shooter: Dictionary, target_pos: Vector2) -> bool:
	var st = w.sys_state.get(KEY)
	if st == null or (st.sec as Dictionary).is_empty():
		return true
	var rec = _cache(w, st).m.get(int(shooter.get("id", -1)))
	if rec == null:
		return true
	if in_sector(rec, target_pos):
		return true
	var sd := _rf(R(), "self_defence_r", 3.0)
	return Vector2(shooter.pos).distance_squared_to(target_pos) <= sd * sd


## Painted sector of eid, else its auto zone, else {}: {arc_c, arc_w (rad), rmin, rmax, origin [x, y], auto, group}.
static func sector_of(w: SimWorld, eid: int) -> Dictionary:
	var st = w.sys_state.get(KEY)
	if st != null:
		var rec = st.sec.get(str(eid))
		if rec != null:
			return {"arc_c": float(rec.c), "arc_w": float(rec.aw), "rmin": float(rec.r0), "rmax": float(rec.r1),
				"origin": [float(rec.ax), float(rec.ay)], "auto": false, "group": int(rec.g)}
	return auto_zone(w, eid)


static func _wrange(e: Dictionary) -> float:
	var d := Content.building(String(e.def)) if e.kind == "building" else Content.unit(String(e.def))
	var wid := String(d.get("weapon", ""))
	if wid == "" and e.kind == "building":
		# FIRES71-8 (BASTION71 CR seq 3107): turrets keep their weapon in their t7 / t71 / wt7 block, not def.weapon
		for blk in ["t7", "t71", "wt7"]:
			if d.has(blk):
				wid = String((d[blk] as Dictionary).get("weapon", ""))
				break
	if wid == "":
		return 0.0
	return float(Content.weapon(wid).get("range", 0.0))


## Auto zone (advisory): ring defences cover their face, everything else its LP compass sector. {} outside LP.
static func auto_zone(w: SimWorld, eid: int) -> Dictionary:
	var e = w.entities.get(eid)
	if e == null or ring_rect(w).size == Vector2i.ZERO:
		return {}
	var rg := _wrange(e)
	if rg <= 0.0:
		return {}
	var A: Dictionary = R().get("auto", {})
	var pos: Vector2 = e.pos
	if e.kind == "building":
		var m := face_of(w, pos)
		if absf(out_dist(w, m, pos)) <= _rf(A, "wall_band", 3.0):
			return {"arc_c": _sn(normal(m).angle()), "arc_w": _sn(deg_to_rad(_rf(A, "turret_arc_deg", 110.0))), "rmin": 0.0,
				"rmax": rg, "origin": [_sn(pos.x), _sn(pos.y)], "auto": true, "group": 0, "face": m}
	var c := base_centre(w)
	var ang := (pos - c).angle() if pos.distance_squared_to(c) > 0.01 else 0.0
	var k := posmod(floori((ang + PI / 8.0) / (PI / 4.0)), 8)
	return {"arc_c": _sn(_wrap(float(k) * PI / 4.0)), "arc_w": _sn(deg_to_rad(_rf(A, "squad_arc_deg", 75.0))), "rmin": 0.0,
		"rmax": _sn(pos.distance_to(c) + rg), "origin": [_sn(c.x), _sn(c.y)], "auto": true, "group": 0, "sector": k}


# ================================================================ commands
static func _members(w: SimWorld, cmd: Dictionary) -> Array:
	var fid := int(cmd.get("issuer", -1))
	var ids := []
	for k in ["unit_ids", "building_ids"]:
		for raw in cmd.get(k, []):
			if not ids.has(int(raw)):
				ids.append(int(raw))
	ids.sort()
	var out := []
	for id in ids:
		var e = w.entities.get(int(id))
		if e != null and int(e.owner) == fid and (e.kind == "unit" or e.kind == "building") and _wrange(e) > 0.0:
			out.append(e)
	return out


static func _pt(v):
	if v is Vector2:
		return v
	if v is Vector2i:
		return Vector2(v)
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return null


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var t := String(cmd.get("type", ""))
	if not COMMANDS.has(t):
		return "unknown_command"
	if not lp_on(w):
		return "Kill zones are a Last Protocol feature."
	match t:
		"kz_paint":
			var mem := _members(w, cmd)
			if mem.is_empty():
				return "Select your own armed units or defences."
			var at = _pt(cmd.get("at"))
			if at == null or not w.in_bounds(w.cell_of(at)):
				return "Drag the sector on the map."
			if mem.size() > int(R().get("max_group", 400)):
				return "Too many units in one sector."
		"kz_clear":
			if _members(w, cmd).is_empty():
				return "Select your own armed units or defences."
		"fpf_paint":
			var m := int(cmd.get("face", -1))
			if m < 0 or m > 3 or ring_rect(w).size == Vector2i.ZERO:
				return "Pick a wall face."
			var a = _pt(cmd.get("a"))
			var b = _pt(cmd.get("b"))
			if a == null or b == null or not w.in_bounds(w.cell_of(a)) or not w.in_bounds(w.cell_of(b)):
				return "Draw the strip on the map."
			if (a as Vector2).distance_to(b) < 2.0:
				return "Draw a longer strip."
			var od := out_dist(w, m, ((a as Vector2) + (b as Vector2)) * 0.5)
			if od < _rf(FR(), "paint_min_out", 2.0) or od > _rf(FR(), "paint_max_out", 30.0):
				return "Keep the strip in front of that wall face."
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	if validate_command(w, cmd) != "":
		return
	var st := _st(w)
	var fid := int(cmd.issuer)
	match String(cmd.type):
		"kz_paint":
			_paint(w, st, cmd, _members(w, cmd))
		"kz_clear":
			var ids := []
			for e in _members(w, cmd):
				if (st.sec as Dictionary).erase(str(int(e.id))):
					ids.append(int(e.id))
			st.v = int(st.v) + 1
			w.emit("KillZoneCleared", {"owner": fid, "ids": ids})
		"fpf_paint":
			var a: Vector2 = _pt(cmd.a)
			var b: Vector2 = _pt(cmd.b)
			st.strips[str(int(cmd.face))] = {"ax": _sn(a.x), "ay": _sn(a.y), "bx": _sn(b.x), "by": _sn(b.y)}
			st.v = int(st.v) + 1
			w.emit("FpfPainted", {"owner": fid, "face": int(cmd.face), "a": [_sn(a.x), _sn(a.y)], "b": [_sn(b.x), _sn(b.y)]})


static func _paint(w: SimWorld, st: Dictionary, cmd: Dictionary, mem: Array) -> void:
	var at: Vector2 = _pt(cmd.at)
	var apex = _pt(cmd.get("apex"))
	if apex == null:
		var s := Vector2.ZERO
		for e in mem:
			s += Vector2(e.pos)
		apex = s / float(mem.size())
	apex = Vector2(_sn(apex.x), _sn(apex.y))
	var dirv: Vector2 = at - apex
	var dir := dirv.angle() if dirv.length_squared() > 0.0001 else 0.0
	var r1 := maxf(dirv.length(), _rf(R(), "min_rmax", 2.0))
	var r0 := clampf(float(cmd.get("rmin", 0.0)), 0.0, r1 - 0.5)
	var arc := deg_to_rad(clampf(float(cmd.get("arc_deg", _rf(R(), "arc_deg_default", 60.0))), _rf(R(), "arc_min", 10.0), _rf(R(), "arc_max", 180.0)))
	var g := int(st.next_g)
	st.next_g = g + 1
	var order := split_order(mem, apex, dir)
	var n := order.size()
	var S := mini(n, int(R().get("max_slices", 12)))
	var ov := _rf(R(), "overlap_frac", 0.15)
	var ids := []
	for k in n:
		var e: Dictionary = order[k]
		var sl := (k * S) / n
		var c := dir
		var aw := arc
		if S > 1:
			c = dir - arc * 0.5 + (float(sl) + 0.5) * arc / float(S)
			aw = minf(arc / float(S) * (1.0 + 2.0 * ov), TAU)
		st.sec[str(int(e.id))] = {"c": _sn(_wrap(c)), "aw": _sn(aw), "r0": _sn(r0), "r1": _sn(r1), "ax": apex.x, "ay": apex.y, "g": g}
		ids.append(int(e.id))
	st.v = int(st.v) + 1
	w.emit("KillZonePainted", {"owner": int(cmd.issuer), "group": g, "ids": ids, "apex": [apex.x, apex.y],
		"dir": _sn(dir), "arc": _sn(arc), "rmin": _sn(r0), "rmax": _sn(r1)})


## Members sorted by signed angle around apex relative to dir (left to right), ties by id. Pure function.
static func split_order(mem: Array, apex: Vector2, dir: float) -> Array:
	var rows := []
	for e in mem:
		var d: Vector2 = Vector2(e.pos) - apex
		var a := _sn(_wrap(d.angle() - dir)) if d.length_squared() > 0.0001 else 0.0
		rows.append([a, int(e.id), e])
	rows.sort_custom(func(x, y): return float(x[0]) < float(y[0]) or (float(x[0]) == float(y[0]) and int(x[1]) < int(y[1])))
	var out := []
	for r in rows:
		out.append(r[2])
	return out


# ================================================================ tick (only with state)
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get(KEY)
	if st == null or w.tick % PRUNE_EVERY != 11 or (st.sec as Dictionary).is_empty():
		return
	var ks: Array = (st.sec as Dictionary).keys()
	ks.sort()
	var gone := false
	for k in ks:
		if not w.entities.has(int(k)):
			st.sec.erase(k)
			gone = true
	if gone:
		st.v = int(st.v) + 1


# ================================================================ display provider (render_snap g71 hook)
## Plain data for presentation/view/fires71_view.gd: painted sectors of side fid + the 4 strips.
static func snap71(w: SimWorld, fid: int) -> Dictionary:
	var out := {"sec": [], "strips": []}
	var st = w.sys_state.get(KEY)
	if st != null:
		var ks: Array = (st.sec as Dictionary).keys()
		ks.sort()
		for k in ks:
			var e = w.entities.get(int(k))
			if e == null or int(e.owner) != fid:
				continue
			var r: Dictionary = st.sec[k]
			out.sec.append([int(k), float(r.ax), float(r.ay), float(r.c), float(r.aw), float(r.r0), float(r.r1), int(r.g)])
	for m in faces(w):
		out.strips.append(fpf_strip(w, m))
	return out
