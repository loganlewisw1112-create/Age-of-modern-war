extends RefCounted
## G7.1 DAMAGE71 (scope B2 + J3 half-dead, Last Protocol only, roster 5A Q1): Machine component damage, armour plates
## + ricochets, nanite self-repair, burning state, half-dead machines, heavy death physics.
## Data: rules.g71_damage (content/g71/rules_g71_damage.json), layouts rules.g71_parts* (content/g71/defs_g71_parts.json,
##   keyed by Machine def id; later waves add a rules key starting with "g71_parts" = data-only registration).
## Gate: the system state w.sys_state.parts71 exists only in Last Protocol (Parts71.tick creates it there; tests call
##   enable). Damage.apply_hit asks `on(w)` (one dict lookup) before anything else, so other modes are untouched.
## Per hit (Damage.apply_hit -> hit): one w.rng draw picks the part (weights by hit side). A part behind an intact
##   plate meets the plate: effective thickness t / cos(obliquity) (horizontal angle x plate slope); kinetic rounds at
##   a steep angle that cannot beat pen_k x that thickness ricochet (no damage, event Ricochet71). Otherwise the
##   ballistics8 round model runs against the plate (or the bare part's own thickness when exposed) instead of the
##   def's class thickness, so a square hit on the glacis equals the G7 number, flanks / joints / sheared plates are
##   weaker and weak spots (joints, sensors, cores, cells) take x weak. Plates wear and shear (PlateShear71).
##   Part hp shares come off as the unit's vitality (hp) drops; destroyed parts: legs -> leg_speed (limp / stop),
##   all weapons -> silent, sensors -> accuracy down, blind = wild fire, core -> killed, cell -> cook-off.
## State (saved + hashed): entity fields p71 (Array: part hp then plate hp, layout order), p71spd / p71acc / p71ws /
##   p71wild (effects, absent = neutral), p71burn (tick the fire goes out), p71hd (tick it went half-dead),
##   p71rep (1 while regrowing: the view's silver flow); w.sys_state.parts71 = {ver, burn: {id: 1},
##   rep: [EVERY buckets of {id: 1}]}.
## RNG: one w.rng.randf() per hit on a layout Machine (G2 _component_roll is skipped for those). Ids ascending.
## Events: Ricochet71, PlateShear71, PartDestroyed71, CellCookoff71, NaniteRegrow71, HalfDead71, Topple71.

const Ballistics8 = preload("res://sim/systems/ballistics8.gd")
const Gore71 = preload("res://sim/systems/gore71.gd")

const KEY := "parts71"
const Q := 1.0 / 1024.0
const FACE := {"front": 0, "side": 1, "rear": 2, "all": 3}
const SIDES := ["front", "side", "rear"]

static var _rref = null
static var _R: Dictionary = {}
static var _L: Dictionary = {}       # def id -> compiled layout ({} = none)
static var _scr: Dictionary = {}     # armour class name -> scratch copy used per hit (no allocation per shot)
static var _noric: Dictionary = {}
static var _dmg = null   # damage.gd, loaded lazily (damage.gd preloads this file: no preload cycle)


static func _damage():
	if _dmg == null:
		_dmg = load("res://sim/systems/damage.gd")
	return _dmg


static func R() -> Dictionary:
	_sync()
	return _R


static func _sync() -> void:
	var r: Dictionary = Content.rules()
	if is_same(r, _rref):
		return
	_rref = r
	_R = r.get("g71_damage", {})
	_L.clear()
	_scr.clear()
	_noric.clear()
	for rid in (_R.get("ricochet", {}) as Dictionary).get("no_ric_rounds", []):
		_noric[String(rid)] = true


## Every raw layout entry for def_id across the rules.g71_parts* keys (sorted key order; first hit wins).
static func _raw_layout(def_id: String) -> Dictionary:
	var r: Dictionary = Content.rules()
	var ks := []
	for k in r.keys():
		if String(k).begins_with("g71_parts"):
			ks.append(String(k))
	ks.sort()
	for k in ks:
		var pk: Dictionary = r[k]
		var dd = (pk.get("defs", {}) as Dictionary).get(def_id)
		if dd == null:
			continue
		var out: Dictionary = {}
		var tpl := String((dd as Dictionary).get("tpl", ""))
		if tpl != "":
			for kk in ks:
				var t = ((r[kk] as Dictionary).get("templates", {}) as Dictionary).get(tpl)
				if t != null:
					out = (t as Dictionary).duplicate(true)
					break
		for f in dd:
			if String(f) != "tpl":
				out[f] = dd[f]
		return out
	return {}


## Compiled layout of a def ({} = no layout: the old damage path).
static func layout_of(def_id: String) -> Dictionary:
	_sync()
	var c = _L.get(def_id)
	if c != null:
		return c
	var raw := _raw_layout(def_id)
	var L := {}
	if not raw.is_empty() and bool(_R.get("enabled", true)):
		L = _compile(def_id, raw)
	_L[def_id] = L
	return L


static func _compile(def_id: String, raw: Dictionary) -> Dictionary:
	var ud: Dictionary = Content.unit(def_id)
	var dhp := float(ud.get("hp", 100.0))
	var plates := []
	var pidx := {}
	var parts := []
	for pl in raw.get("plates", []):
		var t = pl.get("t", 0)
		var p := {"id": String(pl.id), "face": int(FACE.get(String(pl.get("face", "all")), 3)),
			"t": float(t[0]) if t is Array else float(t), "cov": float(t[1]) if t is Array else 1.0,
			"cs": cos(deg_to_rad(float(pl.get("slope", 0.0)))), "max": snappedf(float(pl.get("hp", 0.2)) * dhp, Q)}
		pidx[p.id] = plates.size()
		plates.append(p)
	var tot := [0.0, 0.0, 0.0]
	var legs := []
	var weps := []
	var sens := []
	var core := -1
	var names := {}
	for pr in raw.get("parts", []):
		var t = pr.get("t", 0)
		var ww: Array = pr.get("w", [1.0, 1.0, 1.0])
		var p := {"id": String(pr.id), "kind": String(pr.get("kind", "hull")), "w": [float(ww[0]), float(ww[1]), float(ww[2])],
			"max": snappedf(float(pr.get("hp", 0.1)) * dhp, Q), "weak": float(pr.get("weak", 1.0)),
			"t": float(t[0]) if t is Array else float(t), "cov": float(t[1]) if t is Array else 1.0,
			"plate": int(pidx.get(String(pr.get("plate", "")), -1))}
		var i := parts.size()
		names[p.id] = i
		match p.kind:
			"leg":
				legs.append(i)
			"weapon":
				weps.append(i)
			"sensor":
				sens.append(i)
			"core":
				core = i
		for s in 3:
			tot[s] = float(tot[s]) + float(p.w[s])
		parts.append(p)
	for j in plates.size():
		names["plate:" + String(plates[j].id)] = parts.size() + j
	return {"def": def_id, "parts": parts, "plates": plates, "tot": tot, "legs": legs, "weps": weps, "sens": sens,
		"core": core, "names": names, "np": parts.size(), "leg_speed": raw.get("leg_speed", [1.0, 0.0]),
		"heavy": bool(raw.get("heavy", false)), "topple": float(raw.get("topple", 2.0)),
		"half_dead": bool(raw.get("half_dead", false)), "dhp": dhp}


static func on(w: SimWorld) -> bool:
	return w.sys_state.has(KEY)


static func _every() -> int:
	return maxi(1, int((R().get("repair", {}) as Dictionary).get("every", 10)))


## Creates the system state (Parts71.tick does this in Last Protocol; tests call it directly).
static func enable(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get(KEY)
	if st == null:
		var rep := []
		for i in _every():
			rep.append({})
		st = {"ver": 1, "burn": {}, "rep": rep}
		w.sys_state[KEY] = st
	return st


## Gives e its part state when its def has a layout (first hit). false = no layout (old path).
static func adopt(w: SimWorld, e: Dictionary) -> bool:
	if e.has("p71"):
		return true
	if e.kind != "unit":
		return false
	var L := layout_of(String(e.def))
	if L.is_empty():
		return false
	var a := []
	for p in L.parts:
		a.append(float(p.max))
	for p in L.plates:
		a.append(float(p.max))
	e["p71"] = a
	return true


static func _side_i(from: Vector2, e: Dictionary) -> int:
	var v := from - Vector2(e.pos)
	if v.length_squared() < 1e-9:
		return 0
	var a := absf(angle_difference(float(e.get("facing", 0.0)), v.angle()))
	if a <= PI / 4.0 + 1e-9:
		return 0
	if a >= PI - PI / 4.0 - 1e-9:
		return 2
	return 1


## cos of the impact obliquity on plate pl of e for a shot from `from` (horizontal angle x plate slope).
static func _plate_cos(from: Vector2, e: Dictionary, pl: Dictionary, side: int) -> float:
	var v := from - Vector2(e.pos)
	if v.length_squared() < 1e-9:
		return float(pl.cs)
	var f := float(e.get("facing", 0.0))
	var face := int(pl.face)
	if face == 3:
		face = side
	var n := f
	if face == 2:
		n = f + PI
	elif face == 1:
		var dl := angle_difference(f + PI / 2.0, v.angle())
		var dr := angle_difference(f - PI / 2.0, v.angle())
		n = f + PI / 2.0 if absf(dl) <= absf(dr) else f - PI / 2.0
	var ch := cos(minf(absf(angle_difference(n, v.angle())), PI / 2.0))
	return maxf(ch, 0.0) * float(pl.cs)


static func _scratch(a8: Dictionary) -> Dictionary:
	var k := String(a8.get("name", "")) + "|" + String(a8.get("up", ""))
	var s = _scr.get(k)
	if s == null:
		s = a8.duplicate(true)
		s.erase("t_side")
		s.erase("zones")
		_scr[k] = s
	return s


static func _ric_deg(r8: Dictionary) -> float:
	var rc: Dictionary = R().get("ricochet", {})
	var pen := float(r8.get("pen", 0.0))
	if pen >= float(rc.get("pen_rail", 700.0)):
		return float(rc.get("deg_rail", 80.0))
	if pen >= float(rc.get("pen_ap", 30.0)):
		return float(rc.get("deg_ap", 72.0))
	return float(rc.get("deg_small", 62.0))


## One hit on layout Machine e (adopted). r8 / a8 = ballistics8 round + armour class ({} / null = no round model),
## old = the pre-armour damage (armor table x facing), dmg = the damage Damage computed the old way, mods = s.damage /
## the round's content damage. Returns the damage to take off e's hp (may be 0 on a ricochet).
static func hit(w: SimWorld, shooter: Dictionary, e: Dictionary, r8, a8: Dictionary, old: float, dmg: float, mods: float) -> float:
	var L := layout_of(String(e.def))
	var hp: Array = e.p71
	var from := Vector2(shooter.get("pos", e.pos))
	var side := _side_i(from, e)
	var x := w.rng.randf() * float(L.tot[side])
	var pi := 0
	var parts: Array = L.parts
	var n := parts.size()
	while pi < n - 1:
		x -= float(parts[pi].w[side])
		if x < 0.0:
			break
		pi += 1
	var p: Dictionary = parts[pi]
	var pl = null
	var pli := int(p.plate)
	if pli >= 0:
		var pd: Dictionary = L.plates[pli]
		if float(hp[L.np + pli]) > 0.0 and (int(pd.face) == 3 or int(pd.face) == side):
			pl = pd
	var R0 := R()
	var out := dmg
	var weak := 1.0 if pl != null else float(p.weak)
	if r8 != null and not a8.is_empty():
		var t := float(p.t)
		var cov := float(p.cov)
		if pl != null:
			var c := maxf(_plate_cos(from, e, pl, side), float((R0.get("plate", {}) as Dictionary).get("min_cos", 0.2)))
			t = float(pl.t) / c
			cov = float(pl.cov)
			if not bool(r8.get("chem", false)) and not _noric.has(String(r8.get("id", ""))):
				var obl := rad_to_deg(acos(clampf(c, 0.0, 1.0)))
				var vr := Ballistics8.vel_ratio(r8, Ballistics8.tiles_between(shooter, e))
				if obl >= _ric_deg(r8) and Ballistics8.pen_at(r8, vr) < float((R0.get("ricochet", {}) as Dictionary).get("pen_k", 1.5)) * t:
					_wear(w, e, L, pli, old * float((R0.get("plate", {}) as Dictionary).get("ric_wear", 0.25)))
					w.emit("Ricochet71", {"id": int(e.id), "pos": Vector2(e.pos), "from": from, "part": String(p.id),
						"plate": String(pl.id), "round": String(r8.get("id", ""))})
					_mark_rep(w, e)
					return 0.0
		var s := _scratch(a8)
		var tiles := Ballistics8.tiles_between(shooter, e)
		if bool(a8.get("body", false)):
			s["avg"] = [t, cov]
			out = Ballistics8.body_damage(r8, s, e, tiles, "", mods)
		else:
			s["t"] = t
			out = Ballistics8.vehicle_damage(r8, s, e, tiles, SIDES[side], old, mods)
	out = snappedf(out * weak, Q)
	if pl != null:
		_wear(w, e, L, pli, old * float((R0.get("plate", {}) as Dictionary).get("wear", 1.0)))
	var before := float(hp[pi])
	if before > 0.0:
		var after := snappedf(maxf(before - out, 0.0), Q)
		hp[pi] = after
		if after <= 0.0:
			w.emit("PartDestroyed71", {"id": int(e.id), "part": String(p.id), "kind": String(p.kind), "pos": Vector2(e.pos)})
			match String(p.kind):
				"core":
					out = maxf(out, float(e.hp))
				"cell":
					out = snappedf(out + float(R0.get("cell_cook_frac", 0.2)) * float(L.dhp), Q)
					w.emit("CellCookoff71", {"id": int(e.id), "part": String(p.id), "pos": Vector2(e.pos)})
			_effects(e, L)
	_mark_rep(w, e)
	return out


static func _wear(w: SimWorld, e: Dictionary, L: Dictionary, pli: int, amt: float) -> void:
	var hp: Array = e.p71
	var k: int = int(L.np) + pli
	var before := float(hp[k])
	if before <= 0.0:
		return
	var after := snappedf(maxf(before - amt, 0.0), Q)
	hp[k] = after
	if after <= 0.0:
		var pd: Dictionary = L.plates[pli]
		w.emit("PlateShear71", {"id": int(e.id), "plate": String(pd.id), "face": SIDES[mini(int(pd.face), 2)] if int(pd.face) < 3 else "all",
			"pos": Vector2(e.pos), "facing": float(e.get("facing", 0.0))})


## Damage.wound_hit (splash / crush / frag) on an adopted Machine: it may regrow after the lull.
static func note_damage(w: SimWorld, e: Dictionary) -> void:
	_mark_rep(w, e)


static func _mark_rep(w: SimWorld, e: Dictionary) -> void:
	if e.has("p71hd"):
		return
	var st = w.sys_state.get(KEY)
	if st == null:
		return
	var rep: Array = st.rep
	(rep[int(e.id) % rep.size()] as Dictionary)[int(e.id)] = 1


## Recomputes the effect fields of e from its part hp (absent field = neutral).
static func _effects(e: Dictionary, L: Dictionary) -> void:
	var hp: Array = e.p71
	var dead := 0
	for i in L.legs:
		if float(hp[i]) <= 0.0:
			dead += 1
	var ls: Array = L.leg_speed
	var spd := float(ls[mini(dead, ls.size() - 1)]) if not ls.is_empty() else 1.0
	var acc := 1.0
	var sdead := 0
	for i in L.sens:
		if float(hp[i]) <= 0.0:
			sdead += 1
	var R0 := R()
	if not (L.sens as Array).is_empty() and sdead >= (L.sens as Array).size():
		acc = float(R0.get("sensor_blind_acc", 0.35))
		e["p71wild"] = true
	else:
		e.erase("p71wild")
		for i in sdead:
			acc *= float(R0.get("sensor_part_acc", 0.75))
	var wdead := 0
	for i in L.weps:
		if float(hp[i]) <= 0.0:
			wdead += 1
	if not (L.weps as Array).is_empty() and wdead >= (L.weps as Array).size():
		e["p71ws"] = true
	else:
		e.erase("p71ws")
	if e.has("p71hd"):
		var hd: Dictionary = R0.get("half_dead", {})
		spd *= float(hd.get("speed", 0.2))
		if spd <= 0.0:
			spd = float(hd.get("speed", 0.2)) * 0.5   # no legs left: drags its torso
		acc *= float(hd.get("acc", 0.5))
	if spd == 1.0:
		e.erase("p71spd")
	else:
		e["p71spd"] = snappedf(spd, Q)
	if acc == 1.0:
		e.erase("p71acc")
	else:
		e["p71acc"] = snappedf(acc, Q)


## Damage's 0 hp path for a layout Machine. true = it lives on half-dead (J3); false = it dies (a heavy one topples
## first: crush + wreck; every one leaves a Gore71 wreck record).
static func on_zero(w: SimWorld, shooter: Dictionary, e: Dictionary) -> bool:
	if not e.has("p71"):
		return false
	var L := layout_of(String(e.def))
	if L.is_empty():
		return false
	var hp: Array = e.p71
	var core_ok := int(L.core) < 0 or float(hp[int(L.core)]) > 0.0
	if bool(L.half_dead) and core_ok and not e.has("p71hd"):
		var hd: Dictionary = R().get("half_dead", {})
		e["p71hd"] = w.tick
		e.hp = snappedf(maxf(float(e.get("max_hp", L.dhp)) * float(hd.get("hp_frac", 0.12)), Q), Q)
		e.erase("p71rep")
		var st = w.sys_state.get(KEY)
		if st != null:
			(st.rep[int(e.id) % (st.rep as Array).size()] as Dictionary).erase(int(e.id))
		_effects(e, L)
		w.emit("HalfDead71", {"id": int(e.id), "def": String(e.def), "pos": Vector2(e.pos), "legs": _legs_left(e, L)})
		return false if float(e.hp) <= 0.0 else true
	_death(w, shooter, e, L)
	return false


static func _legs_left(e: Dictionary, L: Dictionary) -> int:
	var n := 0
	for i in L.legs:
		if float(e.p71[i]) > 0.0:
			n += 1
	return n


static func _moving(e: Dictionary) -> bool:
	var o = e.get("order")
	if o == null:
		return false
	var p = e.get("path")
	return ["move", "attack_move", "attack"].has(String((o as Dictionary).get("type", ""))) and p != null and not (p as Array).is_empty()


static func _death(w: SimWorld, shooter: Dictionary, e: Dictionary, L: Dictionary) -> void:
	var ud: Dictionary = Content.unit(String(e.def))
	var rad := float(ud.get("radius", 0.5))
	var pos := Vector2(e.pos)
	var mv := _moving(e)
	var dir := Vector2.from_angle(float(e.get("facing", 0.0)))
	if not mv and shooter.has("pos"):
		var v := pos - Vector2(shooter.pos)
		if v.length_squared() > 1e-6:
			dir = v.normalized()
	var rest := pos
	var crushed := []
	var wall := false
	var out := "wreck"
	if bool(L.heavy):
		var T: Dictionary = R().get("topple", {})
		var step := maxf(float(T.get("step", 0.5)), 0.1)
		var flen := float(L.topple) * rad
		var s := step
		var reach := flen
		while s <= flen + 1e-6:
			var c := Vector2i(floori(pos.x + dir.x * s), floori(pos.y + dir.y * s))
			if not w.in_bounds(c) or SimWorld.Construction.building_at_cell(w, c):
				reach = maxf(s - step, 0.0)
				wall = true
				break
			s += step
		out = "wall" if wall else "topple"
		var slide := 0.0
		if mv and not wall:
			slide = float(ud.get("speed", 0.0)) * float(T.get("slide_s", 0.6)) * float(e.get("p71spd", 1.0))
		rest = pos + dir * (reach * 0.5 + slide)
		crushed = _crush(w, e, pos, pos + dir * (reach + slide), rad, float(T.get("crush_frac", 0.35)) * float(L.dhp))
		w.emit("Topple71", {"id": int(e.id), "def": String(e.def), "pos": pos, "to": rest, "dir": dir, "len": reach + slide,
			"wall": wall, "crushed": crushed})
	if w.sys_state.has(Gore71.KEY) or on(w):
		Gore71.add_body(w, {"kind": "wreck", "def": String(e.def), "owner": int(e.owner), "pos": rest, "rot": dir.angle(),
			"sz": rad, "out": out, "t": w.tick, "from": pos})


## Units under a fallen hull from a to b (half-width rad): ids ascending, air excluded, the hulk itself excluded.
static func _crush(w: SimWorld, e: Dictionary, a: Vector2, b: Vector2, rad: float, dmg: float) -> Array:
	var ids := []
	var mid := (a + b) * 0.5
	var rr := a.distance_to(b) * 0.5 + rad + 1.0
	var cand := []
	var ng = w.cache.get("combat_ng")
	if ng != null:
		cand = ng.grid.query_radius(mid, rr)
	else:
		for id in w.entities:
			var u = w.entities[id]
			if u.kind == "unit" and Vector2(u.pos).distance_to(mid) <= rr:
				cand.append(int(id))
	for cid in cand:
		if int(cid) == int(e.id):
			continue
		var u = w.entities.get(int(cid))
		if u == null or u.kind != "unit":
			continue
		var mc := String(Content.unit(String(u.def)).get("move_class", "foot"))
		if mc.begins_with("air"):
			continue
		var p := Vector2(u.pos)
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		if p.distance_to(q) <= rad + 0.5 * float(Content.unit(String(u.def)).get("radius", 0.4)):
			ids.append(int(cid))
	ids.sort()
	for cid in ids:
		var u = w.entities.get(cid)
		if u != null:
			_damage().wound_hit(w, e, u, dmg, "torso")
	return ids


## Sets entity e burning for `secs` seconds (fire stops nanite self-repair, B1 / B2). Callers: FIRES71 incendiary /
## thermobaric, ARMY71 flame tank, BASTION71 fire-pour points. Extends a longer burn, never shortens one.
static func ignite(w: SimWorld, e: Dictionary, secs: float) -> void:
	if e.is_empty() or secs <= 0.0 or not e.has("id"):
		return
	var end_t := w.tick + maxi(roundi(secs * SimWorld.TICK_RATE), 1)
	if int(e.get("p71burn", -1)) >= end_t:
		return
	e["p71burn"] = end_t
	e.erase("p71rep")
	var st = w.sys_state.get(KEY)
	if st == null:
		st = enable(w)
	(st.burn as Dictionary)[int(e.id)] = 1


## true while e is burning (the field is cleared by Parts71.tick when the fire goes out).
static func burning(e: Dictionary) -> bool:
	return e.has("p71burn")


## Hp fraction left of one part (or "plate:<id>") of e (1.0 = intact or no layout; 0.0 = destroyed).
static func part_state(e: Dictionary, part: String) -> float:
	var a = e.get("p71")
	if a == null:
		return 1.0
	var L := layout_of(String(e.def))
	var i = (L.get("names", {}) as Dictionary).get(part)
	if i == null:
		return 1.0
	var mx: float
	if int(i) < int(L.np):
		mx = float(L.parts[int(i)].max)
	else:
		mx = float(L.plates[int(i) - int(L.np)].max)
	return clampf(float(a[int(i)]) / maxf(mx, 0.001), 0.0, 1.0)


## false when every weapon part of e is destroyed ("weapons go silent"). No layout: true.
static func can_fire(e: Dictionary) -> bool:
	return not e.has("p71ws")


## Accuracy multiplier from sensor damage / half-dead (blind = wild fire). No layout: 1.0.
static func acc_mult(e: Dictionary) -> float:
	return float(e.get("p71acc", 1.0))


## Speed multiplier from leg damage / half-dead (limp / stop / drag). No layout: 1.0.
static func speed_mult(e: Dictionary) -> float:
	return float(e.get("p71spd", 1.0))


static func half_dead(e: Dictionary) -> bool:
	return e.has("p71hd")


static func _stunned(w: SimWorld, id: int) -> bool:
	var s = w.sys_state.get("machine_ew7")
	if s == null:
		return false
	var h = (s.get("held", {}) as Dictionary).get(id)
	return h != null and String(h.get("k", "")) == "emp" and int(h.get("until", 0)) > w.tick


static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get(KEY)
	if st == null:
		if not SimWorld.LastProtocol.active(w) or not bool(R().get("enabled", true)):
			return
		st = enable(w)
	var burn: Dictionary = st.burn
	if not burn.is_empty():
		var ids := burn.keys()
		ids.sort()
		for id in ids:
			var e = w.entities.get(id)
			if e == null or int(e.get("p71burn", -1)) <= w.tick:
				if e != null:
					e.erase("p71burn")
				burn.erase(id)
	var rep: Array = st.rep
	var bk: Dictionary = rep[w.tick % rep.size()]
	if bk.is_empty():
		return
	_repair_pass(w, bk, float(rep.size()) / float(SimWorld.TICK_RATE))


static func _repair_pass(w: SimWorld, bk: Dictionary, dt: float) -> void:
	var rr: Dictionary = R().get("repair", {})
	var delay := roundi(float(rr.get("delay_s", 4.0)) * SimWorld.TICK_RATE)
	var ids := bk.keys()
	ids.sort()
	for id in ids:
		var e = w.entities.get(id)
		if e == null or not e.has("p71") or e.has("p71hd"):
			bk.erase(id)
			if e != null:
				e.erase("p71rep")
			continue
		if e.has("p71burn") or _stunned(w, int(id)) or w.tick - int(e.get("last_hit_tick", -100000)) < delay:
			e.erase("p71rep")
			continue
		var L := layout_of(String(e.def))
		var a: Array = e.p71
		var full := true
		var restored := false
		var np := int(L.np)
		for i in a.size():
			var mx: float = float(L.parts[i].max) if i < np else float(L.plates[i - np].max)
			var cur := float(a[i])
			if cur >= mx:
				continue
			if cur <= 0.0 and not bool(rr.get("regrow_destroyed", true)):
				continue
			var rate := float(rr.get("part_per_s", 0.05)) if i < np else float(rr.get("plate_per_s", 0.02))
			var nv := snappedf(minf(cur + rate * mx * dt, mx), Q)
			a[i] = nv
			if cur <= 0.0 and nv > 0.0:
				restored = true
				w.emit("NaniteRegrow71", {"id": int(id), "part": String(L.parts[i].id) if i < np else "plate:" + String(L.plates[i - np].id),
					"pos": Vector2(e.pos)})
			if nv < mx:
				full = false
		var mh := float(e.get("max_hp", L.dhp))
		if float(e.hp) < mh:
			e.hp = snappedf(minf(float(e.hp) + float(rr.get("hp_per_s", 0.012)) * mh * dt, mh), Q)
			if float(e.hp) < mh:
				full = false
		if restored:
			_effects(e, L)
		if full:
			e.erase("p71rep")
			bk.erase(id)
		else:
			e["p71rep"] = 1


static func validate_command(_w: SimWorld, _cmd: Dictionary) -> String:
	return "unknown command"


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass
