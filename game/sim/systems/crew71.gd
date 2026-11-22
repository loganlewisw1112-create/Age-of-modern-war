extends RefCounted
## G7.1 ARMY71 B3 CREW-SERVED WEAPONS (docs/G71_SCOPE.md B3; roster 5A: Q1 Last Protocol only, Q12 new LP defs in
## content/g71/defs_g71_army.json, G6/G7 units untouched). Rules: rules.g71_crew (same file, every number PROVISIONAL).
## A unit is a crew when its def carries "crew71": {"kind": "mg" | "at" | "am" | "gren"}. Crews are G5 squad entities
## (one entity = squad_size soldiers, G5Mech squad_alive): the loader / assistant gunner / spotter is "alive" while
## squad_alive >= 2.
##   MG nest   sustained / rapid / cyclic rates (cooldown x, heat per burst), barrel heat that cools with time, a barrel
##             swap at full heat (assistant alive: swap_s; alone: jam_s), a beaten zone (ellipse along the line of
##             fire at range) that traverses (sideways) and searches (in depth) burst by burst: every hostile
##             soldier inside is suppressed, every hostile Machine inside takes dmg_frac x the round (max_hit, ids up); during an FPF of its wall face (Fires71.fpf_aim) the zone lies on the FPF
##             strip and the gun goes cyclic.
##   AT team   gunner + loader (alone: slower reload), backblast danger zone behind the tube that hurts ANY soldier
##             in it (our own too), top-attack mode vs heavy armour at range (damage x, longer flight).
##   .50 team  the spotter (alive, range >= min) calls corrections (accuracy x) and marks the target's weakest live
##             part (core > cell > sensor > weapon, Parts71.part_state; damage x weak_mult), event SpotMark71.
##   grenadier frag (default) | thermite on an armoured Machine (thermite_armor) with a part layout (Parts71.ignite: stops nanite regrowth) |
##             airburst over a swarm (>= n hostiles near the target: bigger splash, ignores cover) | smoke when the
##             team is suppressed (Senses7.add_smoke between it and the target, little damage).
## Hooks (Combat._fire, under the per-tick LP flag _d71, so skirmish / benches never reach this file):
##   s = Crew71.shot(w, e, s, t)            weapon mode for this shot (a copy of s when changed; no rng)
##   cd = Crew71.on_shot(w, e, s, t, cd)    heat / swap / loader / backblast / beaten zone (no rng)
##   Crew71.on_hit(w, e, s, t)              thermite ignite
## State: per crew entity e.c71 {k, rate, auto, top, heat, ht, swap, n, z, zt, bb, bbt, mark, gren, ta} (saved +
## hashed with the entity; ints / snapped floats / strings / arrays only). Iteration over units: ids ascending.
## Commands (registration: CR to ORCH): crew_rate {issuer, unit_ids, rate 0..2 | -1 = auto}, crew_top {issuer,
## unit_ids, on}.
##   is_crew(e) -> bool                    crew(e) also initialises e.c71 from the def
##   mg_rate(e) -> int                     0 sustained, 1 rapid, 2 cyclic (the chosen rate)
##   set_rate(w, eid, rate) -> bool        -1 = auto
##   heat(e) -> float                      stored barrel heat 0..1; heat_now(w, e) cooled to this tick
##   swapping(w, e) -> bool                barrel swap in progress
##   cd_mult(w, e, s) -> float             cooldown mult for rate / loader (1.0 = none; read-only, for the UI)
##   beaten_zone(w, e) -> Dictionary       {} none, else {c [x,y], len, wid, ang, fpf}
##   backblast(w, e) -> Dictionary         {} none, else {a [x,y], ang, len, half_w}
##   spot_mark(w, e) -> Dictionary         {} none, else {tid, part}
##   grenade(e) -> String                  "frag" | "airburst" | "smoke" | "thermite" ("" = not fired yet)

const KEY := "crew71"
const RATES := ["sustained", "rapid", "cyclic"]
const Parts71 = preload("res://sim/systems/parts71.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Q := 0.001
const SPOT_ORDER := ["core", "cell", "sensor", "weapon"]

static var _rref = null
static var _c: Dictionary = {}
static var _dk: Dictionary = {}
static var _cmb = null
static var _f71 = null
static var _sen = null


static func cfg() -> Dictionary:
	var r: Dictionary = Content.rules()
	if is_same(r, _rref):
		return _c
	_rref = r
	_c = r.get("g71_crew", {})
	_dk = {}
	return _c


static func _C():
	if _cmb == null:
		_cmb = load("res://sim/systems/combat.gd")
	return _cmb


static func _F():
	if _f71 == null:
		_f71 = load("res://sim/systems/fires71.gd")
	return _f71


static func _S():
	if _sen == null:
		_sen = load("res://sim/systems/senses7.gd")
	return _sen


## LP = the discipline71 state exists (Combat._d71 reads the same key).
static func on(w: SimWorld) -> bool:
	return w.sys_state.has("discipline71")


static func _ticks(secs: float) -> int:
	return maxi(roundi(secs * SimWorld.TICK_RATE), 1)


static func kind_of_def(def_id: String) -> String:
	cfg()
	var k = _dk.get(def_id)
	if k == null:
		var c = Content.unit(def_id).get("crew71")
		k = String(c.get("kind", "")) if c is Dictionary else ""
		_dk[def_id] = k
	return String(k)


static func is_crew(e: Dictionary) -> bool:
	return e.has("c71")


## true when e is a crew; creates e.c71 the first time (LP callers only).
static func crew(e: Dictionary) -> bool:
	if e.has("c71"):
		return true
	if String(e.get("kind", "")) != "unit":
		return false
	var k := kind_of_def(String(e.get("def", "")))
	if k == "":
		return false
	var M: Dictionary = cfg().get("mg", {})
	e["c71"] = {"k": k, "rate": int(M.get("default_rate", 1)), "auto": true, "top": true, "heat": 0.0, "ht": 0, "swap": 0, "n": 0}
	return true


static func alive(e: Dictionary) -> int:
	var n := int(e.get("squad_size", int(Content.unit(String(e.get("def", ""))).get("squad_size", 1))))
	return int(e.get("squad_alive", n))


static func mg_rate(e: Dictionary) -> int:
	return int((e.get("c71", {}) as Dictionary).get("rate", 0))


static func set_rate(w: SimWorld, eid: int, rate: int) -> bool:
	var e = w.entities.get(eid)
	if e == null or not crew(e) or String(e.c71.k) != "mg" or rate < -1 or rate > 2:
		return false
	if rate < 0:
		e.c71.auto = true
	else:
		e.c71.auto = false
		e.c71.rate = rate
	return true


static func heat(e: Dictionary) -> float:
	return float((e.get("c71", {}) as Dictionary).get("heat", 0.0))


static func heat_now(w: SimWorld, e: Dictionary) -> float:
	var c = e.get("c71")
	if c == null:
		return 0.0
	var cool := float(cfg().get("mg", {}).get("cool_per_s", 0.06))
	var dt := float(maxi(w.tick - int(c.ht), 0)) / SimWorld.TICK_RATE
	return snappedf(maxf(float(c.heat) - cool * dt, 0.0), Q)


static func swapping(w: SimWorld, e: Dictionary) -> bool:
	return int((e.get("c71", {}) as Dictionary).get("swap", 0)) > w.tick


## The rate this burst uses: FPF -> cyclic; auto drops to sustained when hot, else the chosen rate.
static func _eff_rate(w: SimWorld, e: Dictionary, fpf: bool) -> int:
	var c: Dictionary = e.c71
	if fpf:
		return 2
	if bool(c.get("auto", true)) and heat_now(w, e) >= float(cfg().get("mg", {}).get("auto_sustain_heat", 0.7)):
		return 0
	return int(c.rate)


static func cd_mult(w: SimWorld, e: Dictionary, s: Dictionary) -> float:
	var c = e.get("c71")
	if c == null:
		return 1.0
	var C := cfg()
	match String(c.k):
		"mg":
			var R: Dictionary = C.get("mg", {}).get("rates", {}).get(RATES[_eff_rate(w, e, false)], {})
			return float(R.get("cd", 1.0))
		"at":
			var A: Dictionary = C.get("at", {})
			return float(A.get("loader_cd", 1.0)) if alive(e) >= 2 else float(A.get("alone_cd", 2.0))
	return 1.0


static func beaten_zone(w: SimWorld, e: Dictionary) -> Dictionary:
	var c = e.get("c71")
	if c == null or not c.has("z"):
		return {}
	if w.tick - int(c.zt) > _ticks(float(cfg().get("mg", {}).get("zone", {}).get("keep_s", 1.5))):
		return {}
	return c.z


static func backblast(w: SimWorld, e: Dictionary) -> Dictionary:
	var c = e.get("c71")
	if c == null or not c.has("bb"):
		return {}
	if w.tick - int(c.bbt) > _ticks(float(cfg().get("at", {}).get("backblast", {}).get("show_s", 0.6))):
		return {}
	return c.bb


static func spot_mark(w: SimWorld, e: Dictionary) -> Dictionary:
	var c = e.get("c71")
	if c == null or not c.has("mark"):
		return {}
	if not w.entities.has(int(c.mark.tid)):
		return {}
	return c.mark


static func grenade(e: Dictionary) -> String:
	return String((e.get("c71", {}) as Dictionary).get("gren", ""))


# ================================================================ spatial helper

## Live units within r of `at`, ids ascending (combat's tick grids when present, else a scan).
static func _units_in(w: SimWorld, at: Vector2, r: float) -> Array:
	var out := []
	var r2 := r * r
	var ng = w.cache.get("combat_ng")
	if ng != null:
		for cid in ng.grid.query_radius(at, r + 0.05):
			var u = w.entities.get(cid)
			if u != null and String(u.kind) == "unit" and Vector2(u.pos).distance_squared_to(at) <= r2:
				out.append(int(cid))
	elif w.cache.has("combat_grid"):
		var CB = _C()
		var grid: Dictionary = w.cache.combat_grid
		for o in grid:
			var g: Dictionary = grid[o]
			for yy in range(floori((at.y - r) / CB.BUCKET), floori((at.y + r) / CB.BUCKET) + 1):
				for xx in range(floori((at.x - r) / CB.BUCKET), floori((at.x + r) / CB.BUCKET) + 1):
					var arr = g.get(xx + yy * CB.GRID_STRIDE)
					if arr == null:
						continue
					for u in arr:
						if String(u.kind) == "unit" and w.entities.has(int(u.id)) and Vector2(u.pos).distance_squared_to(at) <= r2:
							out.append(int(u.id))
	else:
		for id in w.entities:
			var u: Dictionary = w.entities[id]
			if String(u.kind) == "unit" and Vector2(u.pos).distance_squared_to(at) <= r2:
				out.append(int(id))
	out.sort()
	return out


static func _armor(t: Dictionary) -> String:
	return String(t.get("armor", Content.unit(String(t.get("def", ""))).get("armor", "")))


# ================================================================ Combat._fire hooks (LP only)

static func shot(w: SimWorld, e: Dictionary, s: Dictionary, t: Dictionary) -> Dictionary:
	if not crew(e):
		return s
	var c: Dictionary = e.c71
	var C := cfg()
	var d := Vector2(e.pos).distance_to(Vector2(t.pos))
	match String(c.k):
		"at":
			var T: Dictionary = C.get("at", {}).get("top", {})
			c.ta = 0
			if bool(c.get("top", true)) and (T.get("armor", ["heavy"]) as Array).has(_armor(t)) and d >= float(T.get("min_range", 4.0)):
				c.ta = 1
				s = s.duplicate()
				s.damage = float(s.damage) * float(T.get("mult", 1.6))
		"am":
			var A: Dictionary = C.get("am", {})
			if alive(e) >= 2 and d >= float(A.get("min_range", 7.0)):
				s = s.duplicate()
				s.accuracy = float(s.accuracy) * float(A.get("acc_mult", 1.25))
				var part := _weak_part(t)
				if part != "":
					s.damage = float(s.damage) * float(A.get("weak_mult", 1.5))
					var old = c.get("mark")
					if old == null or int(old.tid) != int(t.id) or String(old.part) != part:
						w.emit("SpotMark71", {"shooter": int(e.id), "target": int(t.id), "part": part, "owner": int(e.owner)})
					c.mark = {"tid": int(t.id), "part": part}
				else:
					c.erase("mark")
			else:
				c.erase("mark")
		"gren":
			var G: Dictionary = C.get("gren", {})
			var g := "frag"
			if (G.get("thermite_armor", ["heavy"]) as Array).has(_armor(t)) and not Parts71.layout_of(String(t.get("def", ""))).is_empty():
				g = "thermite"
			elif _hostiles_near(w, e, Vector2(t.pos), float(G.get("airburst_r", 2.0))) >= int(G.get("airburst_n", 4)):
				g = "airburst"
			elif e.has("morale") and SimWorld.Morale.is_suppressed(w, e):
				g = "smoke"
			c.gren = g
			if g == "airburst":
				s = s.duplicate()
				s.splash = float(G.get("airburst_splash", 2.0))
				s.ignore_cover = true
			elif g == "smoke":
				s = s.duplicate()
				s.damage = float(s.damage) * float(G.get("smoke_dmg", 0.3))
	return s


static func _hostiles_near(w: SimWorld, e: Dictionary, at: Vector2, r: float) -> int:
	var n := 0
	for id in _units_in(w, at, r):
		if not w.is_ally(int(e.owner), int(w.entities[id].owner)):
			n += 1
	return n


## The spotter's call: the weakest live part by kind order (core > cell > sensor > weapon), first in layout order.
static func _weak_part(t: Dictionary) -> String:
	var L := Parts71.layout_of(String(t.get("def", "")))
	if L.is_empty():
		return ""
	for k in SPOT_ORDER:
		for p in L.parts:
			if String(p.kind) == k and Parts71.part_state(t, String(p.id)) > 0.0:
				return String(p.id)
	return ""


static func on_shot(w: SimWorld, e: Dictionary, s: Dictionary, t: Dictionary, cd: int) -> int:
	if not e.has("c71"):
		return cd
	var c: Dictionary = e.c71
	c.n = int(c.n) + 1
	var C := cfg()
	match String(c.k):
		"mg":
			cd = _mg(w, e, c, C.get("mg", {}), s, t, cd)
		"at":
			var A: Dictionary = C.get("at", {})
			var m := float(A.get("loader_cd", 1.0)) if alive(e) >= 2 else float(A.get("alone_cd", 2.0))
			if int(c.get("ta", 0)) == 1:
				m *= float(A.get("top", {}).get("cd", 1.25))
			cd = maxi(roundi(float(cd) * m), 1)
			_backblast(w, e, c, A.get("backblast", {}), Vector2(t.pos))
		"gren":
			if String(c.get("gren", "")) == "smoke":
				var G: Dictionary = C.get("gren", {})
				var mid := (Vector2(e.pos) + Vector2(t.pos)) * 0.5
				_S().add_smoke(w, mid, float(G.get("smoke_r", 3.0)), float(G.get("smoke_s", 10.0)))
	return cd


static func _mg(w: SimWorld, e: Dictionary, c: Dictionary, M: Dictionary, s: Dictionary, t: Dictionary, cd: int) -> int:
	var aim: Vector2 = t.pos
	var fpf := false
	if w.sys_state.has("fires71"):
		var fa = _F().fpf_aim(w, e)
		if fa is Vector2:
			aim = fa
			fpf = true
	var r := _eff_rate(w, e, fpf)
	var R: Dictionary = M.get("rates", {}).get(RATES[r], {})
	cd = maxi(roundi(float(cd) * float(R.get("cd", 1.0))), 1)
	var h := heat_now(w, e) + float(R.get("heat", 0.04))
	if h >= 1.0:
		var sw := _ticks(float(M.get("swap_s", 5.0)) if alive(e) >= 2 else float(M.get("jam_s", 9.0)))
		cd = maxi(cd, sw)
		c.swap = w.tick + sw
		h = float(M.get("swap_heat_after", 0.2))
		w.emit("BarrelSwap71", {"unit": int(e.id), "ticks": sw, "alone": alive(e) < 2, "owner": int(e.owner)})
	c.heat = snappedf(h, Q)
	c.ht = w.tick
	# beaten zone: an ellipse along the line of fire, traversing sideways and searching in depth burst by burst
	var Z: Dictionary = M.get("zone", {})
	var v := aim - Vector2(e.pos)
	var d := v.length()
	if d <= 0.0 or d < float(Z.get("min_range", 5.0)):
		c.erase("z")
		return cd
	var dir := v / d
	var perp := Vector2(-dir.y, dir.x)
	var zl := snappedf(d * float(Z.get("len_per_tile", 0.14)), Q)
	var zw := snappedf(maxf(d * float(Z.get("wid_per_tile", 0.04)), 0.3), Q)
	var tv: Array = Z.get("traverse", [0, 1, -1, 0])
	var sv: Array = Z.get("search", [0, 0.5, -0.5])
	var n := int(c.n)
	var cen := aim + perp * (float(tv[n % tv.size()]) * zw) + dir * (float(sv[(n / tv.size()) % sv.size()]) * zl)
	cen = Vector2(snappedf(cen.x, 0.01), snappedf(cen.y, 0.01))
	c.z = {"c": [cen.x, cen.y], "len": zl, "wid": zw, "ang": snappedf(dir.angle(), Q), "fpf": fpf}
	c.zt = w.tick
	var supp := float(Z.get("supp", 6.0))
	var zd := snappedf(float(s.damage) * float(Z.get("dmg_frac", 0.25)), Q)
	var mx := int(Z.get("max_hit", 6))
	var hitn := 0
	var inz := []
	for id in _units_in(w, cen, maxf(zl, zw)):
		var u: Dictionary = w.entities[id]
		if id == int(t.id) or w.is_ally(int(e.owner), int(u.owner)):
			continue
		var q: Vector2 = Vector2(u.pos) - cen
		var a := q.dot(dir) / maxf(zl, 0.01)
		var b := q.dot(perp) / maxf(zw, 0.01)
		if a * a + b * b > 1.0:
			continue
		inz.append(id)
		hitn += 1
		if hitn >= mx:
			break
	for id in inz:   # soldiers are suppressed; Machines (no morale) take the rounds falling in the zone
		var u = w.entities.get(id)
		if u == null:
			continue
		if u.has("morale"):
			Damage.suppress(w, u, supp)
		elif zd > 0.0:
			Damage.wound_hit(w, e, u, zd)
	return cd


static func _backblast(w: SimWorld, e: Dictionary, c: Dictionary, B: Dictionary, aim: Vector2) -> void:
	var v := aim - Vector2(e.pos)
	if v.length_squared() <= 0.0:
		return
	var dir := v.normalized()
	var ln := float(B.get("len", 3.0))
	var hw := float(B.get("half_w", 0.7))
	var back := Vector2(e.pos) - dir * (ln * 0.5)
	c.bb = {"a": [snappedf(back.x, 0.01), snappedf(back.y, 0.01)], "ang": snappedf((-dir).angle(), Q), "len": ln, "half_w": hw}
	c.bbt = w.tick
	var hurt := []
	var side := Vector2(-dir.y, dir.x)
	for id in _units_in(w, back, ln * 0.5 + hw):
		if id == int(e.id):
			continue
		var u: Dictionary = w.entities[id]
		var q: Vector2 = Vector2(u.pos) - Vector2(e.pos)
		var al := q.dot(-dir)
		if al <= 0.0 or al > ln or absf(q.dot(side)) > hw:
			continue
		hurt.append(id)
	for id in hurt:
		var u = w.entities.get(id)
		if u == null:
			continue
		if u.has("morale"):
			Damage.suppress(w, u, float(B.get("supp", 20.0)))
		Damage.wound_hit(w, e, u, float(B.get("dmg", 25.0)))
	w.emit("Backblast71", {"shooter": int(e.id), "hurt": hurt, "owner": int(e.owner)})


static func on_hit(w: SimWorld, e: Dictionary, s: Dictionary, t: Dictionary) -> void:
	var c = e.get("c71")
	if c == null:
		return
	if String(c.k) == "gren" and String(c.get("gren", "")) == "thermite":
		Parts71.ignite(w, t, float(cfg().get("gren", {}).get("thermite_s", 6.0)))


# ================================================================ commands (registration: CR to ORCH)

static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if not on(w):
		return "crew71: Last Protocol only"
	var ty := String(cmd.get("type", ""))
	if ty == "crew_rate":
		var r := int(cmd.get("rate", -2))
		if r < -1 or r > 2:
			return "crew_rate: rate -1..2"
	elif ty != "crew_top":
		return "crew71: unknown command"
	for id in cmd.get("unit_ids", []):
		var e = w.entities.get(int(id))
		if e != null and int(e.owner) == int(cmd.get("issuer", -1)) and kind_of_def(String(e.def)) != "":
			return ""
	return "crew71: no own crew in unit_ids"


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var ids: Array = cmd.get("unit_ids", []).duplicate()
	ids.sort()
	for id in ids:
		var e = w.entities.get(int(id))
		if e == null or int(e.owner) != int(cmd.get("issuer", -1)) or not crew(e):
			continue
		if String(cmd.type) == "crew_rate":
			set_rate(w, int(id), int(cmd.rate))
		elif String(e.c71.k) == "at":
			e.c71.top = bool(cmd.get("on", true))
