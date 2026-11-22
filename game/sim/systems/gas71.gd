extends RefCounted
## G7.1 J10 GAS71 (docs/G71_SCOPE.md J10; roster Q7 PROVISIONAL): counter-nanite gas, gas masks and filters, Last
## Protocol only. Numbers: rules.g71_gas (content/g71/rules_g71_gas.json), all PROVISIONAL.
##
## - Field: a sparse coarse grid (CELL tiles per cell) of integer concentrations (1000 = a full-strength cloud), keyed by
##   cell index. Every EVERY ticks (one global cadence) each live cell decays, diffuses to its 4 neighbours and drifts
##   downwind; cells under MIN_C drop out. No cloud = no live cells = tick returns at once.
## - Wind (minimal, deterministic; I3 in wave 5 shows it and drives smoke / fire with it): {a: degrees, s: 0..1000}
##   changed every WIND_EVERY ticks by a saved LCG (never w.rng), seeded from the match seed at the first release.
## - Sources (Q7): CN gas munitions (grenades / canister launchers call release) and facility gas vents during a breach
##   lockdown (CnFacility calls vent). Command gas_release is the test / debug entry.
## - Effects (every EVERY ticks, offset): Machine units in gas lose hp (and die: cause "cn_gas"); our foot soldiers
##   without a working mask lose hp; vehicles and sealed CN suits are immune. Masks go on by themselves when gas is
##   within NEAR cells (e.g71mk.on, visible through the g71 snapshot), come off after OFF_S without gas; a masked unit
##   pays acc_mult / sight_mult (ARMY71 places the accuracy factor in accuracy8 on CR; sight on CR to ORCH).
## - Filters wear with exposure (f 1000 -> 0); a spent filter gives no protection. Fresh masks / filters come from
##   sources (CN facility armory, barracks lockers, crates near the gates: add_source / LP-base hook) within GRAB_R,
##   and ammo bearers carry SPARES masks for nearby units plus their own. An idle unit with a spent filter or no
##   mask walks to the nearest source within FETCH_R (never over a player order: AiCommand override window).
## State: w.sys_state.gas71 = {ver, c: {cell key: conc}, wind {a, s, r}, src: [{id, x, y, kind, m, f}], ns}, created by
## the first release; saved + hashed. Entity field (saved): e.g71mk = {h: has mask 0/1, on: 0/1, f: filter 0..1000,
## t: last tick gas was near}. Events: GasReleased, GasMask {id, on}, GasFilterSpent, GasResupply, GasKill.

const SimIndex = preload("res://sim/systems/sim_index.gd")
const Creep = preload("res://sim/systems/creep.gd")
const AmmoBearer = preload("res://sim/systems/ammo_bearer.gd")
const Transport = preload("res://sim/systems/transport.gd")

const KEY := "gas71"
const VER := 1
const RULES := "g71_gas"
const DFLT := {"cell": 2, "every": 10, "fx_off": 5, "wind_every": 600, "decay_pm": 30, "decay_min": 2, "diff_pm": 160,
	"adv_pm": 220, "min_c": 8, "release_c": 900, "release_r": 1, "near_cells": 2, "near_c": 40, "off_s": 10.0,
	"machine_dps": 60.0, "human_dps": 6.0, "harm_c": 60, "filter_wear": 36.0, "acc_cost": 0.08, "sight_cost": 0.15,
	"grab_r": 3.0, "fetch_r": 40.0, "spares": 3, "give_r": 5.0, "default_mask": true, "vent_c": 700,
	"src_masks": 40, "src_filters": 80}

static var _rules_cache: Dictionary = {}


static func R() -> Dictionary:
	if _rules_cache.is_empty():
		var r: Dictionary = DFLT.duplicate()
		var c = Content.rules().get(RULES, {})
		if c is Dictionary:
			for k in c:
				r[k] = c[k]
		_rules_cache = r
	return _rules_cache


static func ri(k: String) -> int:
	return int(R().get(k, DFLT.get(k, 0)))


static func rf(k: String) -> float:
	return float(R().get(k, DFLT.get(k, 0.0)))


static func st(w: SimWorld):
	return w.sys_state.get(KEY)


static func on(w: SimWorld) -> bool:
	var s = st(w)
	return s != null and not (s.c as Dictionary).is_empty()


static func _lp(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _ensure(w: SimWorld) -> Dictionary:
	var s = st(w)
	if s == null:
		var seed := absi(int(w.seed_value) * 2654435761 + 97) & 0x7fffffff
		s = {"ver": VER, "c": {}, "wind": {"a": seed % 360, "s": 300 + (seed >> 9) % 500, "r": seed}, "src": [], "ns": 1}
		w.sys_state[KEY] = s
	return s


# ================================================================ field
static func _key(w: SimWorld, cx: int, cy: int) -> int:
	return cy * _gw(w) + cx


static func _gw(w: SimWorld) -> int:
	return int(ceil(float(w.map.w) / float(ri("cell"))))


static func _gh(w: SimWorld) -> int:
	return int(ceil(float(w.map.h) / float(ri("cell"))))


static func cell_of(w: SimWorld, pos: Vector2) -> Vector2i:
	var cs := float(ri("cell"))
	return Vector2i(clampi(int(floor(pos.x / cs)), 0, _gw(w) - 1), clampi(int(floor(pos.y / cs)), 0, _gh(w) - 1))


## Concentration 0..~1 at a world point (1.0 = a fresh full-strength cloud).
static func conc_at(w: SimWorld, pos: Vector2) -> float:
	var s = st(w)
	if s == null or (s.c as Dictionary).is_empty():
		return 0.0
	var c := cell_of(w, pos)
	return float(s.c.get(_key(w, c.x, c.y), 0)) / 1000.0


## Highest concentration within n cells of pos (the "gas is near" test).
static func near_at(w: SimWorld, pos: Vector2, n: int) -> int:
	var s = st(w)
	if s == null:
		return 0
	var cd: Dictionary = s.c
	if cd.is_empty():
		return 0
	var c := cell_of(w, pos)
	var gw := _gw(w)
	var gh := _gh(w)
	var best := 0
	for dy in range(-n, n + 1):
		var y := c.y + dy
		if y < 0 or y >= gh:
			continue
		for dx in range(-n, n + 1):
			var x := c.x + dx
			if x < 0 or x >= gw:
				continue
			best = maxi(best, int(cd.get(y * gw + x, 0)))
	return best


## Put gas into the field: amount 1.0 = one grenade / canister (release_c at the centre cell, spread over release_r).
static func release(w: SimWorld, pos: Vector2, amount: float, src: String) -> void:
	if amount <= 0.0:
		return
	var s := _ensure(w)
	var c := cell_of(w, pos)
	var rr := ri("release_r")
	var base := int(round(float(ri("release_c")) * amount))
	var gw := _gw(w)
	var gh := _gh(w)
	for dy in range(-rr, rr + 1):
		for dx in range(-rr, rr + 1):
			var x := c.x + dx
			var y := c.y + dy
			if x < 0 or y < 0 or x >= gw or y >= gh:
				continue
			var dd := maxi(absi(dx), absi(dy))
			var add := base if dd == 0 else base / (2 * dd)
			var k := y * gw + x
			s.c[k] = mini(int(s.c.get(k, 0)) + add, 4000)
	w.emit("GasReleased", {"pos": [pos.x, pos.y], "amount": amount, "src": src})


## Facility gas vents (breach lockdown, Q7): gas over a rect (each cell vent_c x amount).
static func vent(w: SimWorld, rect: Rect2, amount: float, src: String = "vent") -> void:
	var s := _ensure(w)
	var a := cell_of(w, rect.position)
	var b := cell_of(w, rect.end)
	var gw := _gw(w)
	var v := int(round(float(ri("vent_c")) * amount))
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			var k := y * gw + x
			s.c[k] = mini(int(s.c.get(k, 0)) + v, 4000)
	w.emit("GasReleased", {"pos": [rect.get_center().x, rect.get_center().y], "amount": amount, "src": src, "vent": true})


static func wind(w: SimWorld) -> Vector2:
	var s = st(w)
	if s == null:
		return Vector2.ZERO
	return Vector2.RIGHT.rotated(deg_to_rad(float(s.wind.a))) * float(s.wind.s) / 1000.0


static func _tick_wind(w: SimWorld, s: Dictionary) -> void:
	var W: Dictionary = s.wind
	var r := (int(W.r) * 1103515245 + 12345) & 0x7fffffff
	W.r = r
	W.a = posmod(int(W.a) + (r >> 8) % 61 - 30, 360)
	W.s = clampi(int(W.s) + (r >> 16) % 201 - 100, 150, 900)


static func _tick_field(w: SimWorld, s: Dictionary) -> void:
	var cd: Dictionary = s.c
	var ks: Array = cd.keys()
	ks.sort()
	var gw := _gw(w)
	var gh := _gh(w)
	var dpm := ri("decay_pm")
	var dmin := ri("decay_min")
	var fpm := ri("diff_pm")
	var apm := ri("adv_pm")
	var minc := ri("min_c")
	var wa := deg_to_rad(float(s.wind.a))
	var ws := int(s.wind.s)
	var wx := cos(wa)
	var wy := sin(wa)
	var sx := 1 if wx >= 0.0 else -1
	var sy := 1 if wy >= 0.0 else -1
	var fx := int(round(absf(wx) * 1000.0))
	var out := {}
	for k in ks:
		var c := int(cd[k])
		c -= c * dpm / 1000 + dmin
		if c <= 0:
			continue
		var x := int(k) % gw
		var y := int(k) / gw
		var q := c * fpm / 4000
		var adv := c * apm / 1000 * ws / 1000
		var ax := adv * fx / 1000
		var ay := adv - ax
		var keep := c - 4 * q - adv
		out[k] = int(out.get(k, 0)) + keep
		for n in [[x + 1, y, q], [x - 1, y, q], [x, y + 1, q], [x, y - 1, q], [x + sx, y, ax], [x, y + sy, ay]]:
			var v := int(n[2])
			if v <= 0:
				continue
			var nx := int(n[0])
			var ny := int(n[1])
			if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
				continue   # gas blown off the map edge is gone
			var nk := ny * gw + nx
			out[nk] = int(out.get(nk, 0)) + v
	var ok: Array = out.keys()
	ok.sort()
	var nd := {}
	for k in ok:
		if int(out[k]) >= minc:
			nd[k] = mini(int(out[k]), 4000)
	s.c = nd


# ================================================================ masks + filters
static func mask_of(e: Dictionary) -> Dictionary:
	return e.get("g71mk", {})


## True when the unit wears a mask now (on and a filter left).
static func masked(e) -> bool:
	if e == null:
		return false
	var m: Dictionary = e.get("g71mk", {})
	return not m.is_empty() and int(m.get("on", 0)) == 1 and int(m.get("h", 0)) == 1


static func acc_mult(e) -> float:
	return 1.0 - rf("acc_cost") if masked(e) else 1.0


static func sight_mult(e) -> float:
	return 1.0 - rf("sight_cost") if masked(e) else 1.0


## Sealed against the gas: vehicles / aircraft (crews inside) and counter-nanite suits.
static func sealed(e: Dictionary) -> bool:
	var d := Content.unit(String(e.def))
	if bool(d.get("is_air", false)) or Transport.cargo_class_of(String(e.def)) != "foot":
		return true   # vehicles / aircraft: crews inside
	return String(d.get("cn_role", "")) != "" or bool(d.get("g71_sealed", false))   # CN suits (PROVISIONAL)


static func _mk(e: Dictionary) -> Dictionary:
	if not e.has("g71mk"):
		e.g71mk = {"h": 1 if bool(R().get("default_mask", true)) else 0, "on": 0, "f": 1000, "t": -1}
	return e.g71mk


## Bearer spares: masks an ammo bearer carries for others (own mask not counted).
static func spares(e: Dictionary) -> int:
	return int(e.get("g71sp", ri("spares"))) if AmmoBearer.is_bearer(e) else 0


static func add_source(w: SimWorld, pos: Vector2, kind: String, masks: int = -1, filters: int = -1) -> int:
	var s := _ensure(w)
	var id := int(s.ns)
	s.ns = id + 1
	(s.src as Array).append({"id": id, "x": pos.x, "y": pos.y, "kind": kind,
		"m": masks if masks >= 0 else ri("src_masks"), "f": filters if filters >= 0 else ri("src_filters")})
	return id


static func _nearest_src(s: Dictionary, p: Vector2, r: float, need_mask: bool) -> Dictionary:
	var best := {}
	var bd := r
	for S in s.src:
		if (need_mask and int(S.m) <= 0) or (not need_mask and int(S.f) <= 0 and int(S.m) <= 0):
			continue
		var d := p.distance_to(Vector2(float(S.x), float(S.y)))
		if d <= bd:
			bd = d
			best = S
	return best


static func _resupply(w: SimWorld, s: Dictionary, e: Dictionary, m: Dictionary) -> void:
	var p := Vector2(e.pos)
	var need_mask := int(m.h) == 0
	if not need_mask and int(m.f) > 200:
		return
	var S := _nearest_src(s, p, rf("grab_r"), need_mask)
	if not S.is_empty():
		if need_mask:
			S.m = int(S.m) - 1
			m.h = 1
		elif int(S.f) > 0:
			S.f = int(S.f) - 1
		else:
			S.m = int(S.m) - 1
		m.f = 1000
		w.emit("GasResupply", {"id": int(e.id), "src": int(S.id), "kind": String(S.kind), "mask": need_mask})
		return
	if need_mask:   # an ammo bearer nearby hands over a spare
		for bid in SimIndex.units_by_owner(w).get(int(e.owner), []):
			var b = bid if bid is Dictionary else w.entities.get(int(bid))   # the index holds entity dicts
			if b == null or int(b.id) == int(e.id) or not w.entities.has(int(b.id)) or spares(b) <= 0:
				continue
			if Vector2(b.pos).distance_to(p) <= rf("give_r"):
				b.g71sp = spares(b) - 1
				m.h = 1
				m.f = 1000
				w.emit("GasResupply", {"id": int(e.id), "bearer": int(b.id), "kind": "bearer", "mask": true})
				return
	# idle units walk to the nearest source (never over a player order)
	if String(e.get("order", {}).get("type", "")) in ["", "idle", "stop"] and not bool(e.get("moving", false)):
		var F := _nearest_src(s, p, rf("fetch_r"), need_mask)
		if not F.is_empty():
			e.order = {"type": "move", "target": Vector2(float(F.x), float(F.y)), "sq": "gas71"}
			preload("res://sim/systems/movement.gd").order_path(w, e, Vector2(float(F.x), float(F.y)))


static func _tick_fx(w: SimWorld, s: Dictionary) -> void:
	var dt := float(ri("every")) / float(SimWorld.TICK_RATE)
	var near_n := ri("near_cells")
	var near_c := ri("near_c")
	var harm_c := ri("harm_c")
	var off_t := int(rf("off_s") * float(SimWorld.TICK_RATE))
	var cd: Dictionary = s.c
	var live := not cd.is_empty()
	var ids := SimIndex.unit_ids(w)
	for id in ids:
		var e = w.entities.get(int(id))
		if e == null or float(e.get("hp", 0.0)) <= 0.0:
			continue
		var has_mk: bool = e.has("g71mk")
		if not live and not has_mk:
			continue
		var p := Vector2(e.pos)
		var c := cell_of(w, p)
		var conc := int(cd.get(c.y * _gw(w) + c.x, 0)) if live else 0
		if Creep.is_machine(w, int(e.owner)):
			if conc >= harm_c:
				e.hp = float(e.hp) - rf("machine_dps") * float(conc) / 1000.0 * dt
				if float(e.hp) <= 0.0:
					w.emit("GasKill", {"id": int(e.id), "def": String(e.def)})
					w.destroy(int(e.id), "cn_gas")
			continue
		if sealed(e):
			continue
		var near := near_at(w, p, near_n) if live else 0
		if near < near_c and not has_mk:
			continue
		var m := _mk(e)
		if near >= near_c:
			m.t = w.tick
			if int(m.on) == 0 and int(m.h) == 1:
				m.on = 1
				w.emit("GasMask", {"id": int(e.id), "on": true})
		elif int(m.on) == 1 and w.tick - int(m.t) >= off_t:
			m.on = 0
			w.emit("GasMask", {"id": int(e.id), "on": false})
		if conc >= harm_c:
			if int(m.on) == 1 and int(m.h) == 1 and int(m.f) > 0:
				m.f = maxi(0, int(m.f) - int(ceil(rf("filter_wear") * float(conc) / 1000.0 * dt)))   # per mille / s at conc 1000
				if int(m.f) == 0:
					w.emit("GasFilterSpent", {"id": int(e.id)})
			else:
				e.hp = float(e.hp) - rf("human_dps") * float(conc) / 1000.0 * dt
				if float(e.hp) <= 0.0:
					w.destroy(int(e.id), "cn_gas")
					continue
		if int(m.h) == 0 or int(m.f) <= 200:
			_resupply(w, s, e, m)
		elif int(m.on) == 0 and not live and int(m.f) >= 1000 and int(m.h) == 1:
			e.erase("g71mk")   # back to the default issue: no field


# ================================================================ tick / commands
static func tick(w: SimWorld) -> void:
	var s = st(w)
	if s == null:
		return
	var ev := ri("every")
	if w.tick % ri("wind_every") == 0:
		_tick_wind(w, s)
	if not (s.c as Dictionary).is_empty() and w.tick % ev == 0:
		_tick_field(w, s)
	if w.tick % ev == ri("fx_off"):
		_tick_fx(w, s)


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if not _lp(w):
		return "Gas is a Last Protocol weapon."
	match String(cmd.get("type", "")):
		"gas_release":
			var p = cmd.get("pos")
			if not (p is Array and (p as Array).size() == 2) and typeof(p) != TYPE_VECTOR2:
				return "Gas release needs a position."
			return ""
		"mask_on":
			for raw in cmd.get("unit_ids", []):
				var e = w.entities.get(int(raw))
				if e != null and int(e.owner) == int(cmd.get("issuer", -1)) and not sealed(e):
					return ""
			return "Select soldiers on foot."
	return "Unknown gas command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	match String(cmd.get("type", "")):
		"gas_release":
			var p = cmd.pos
			var v: Vector2 = p if typeof(p) == TYPE_VECTOR2 else Vector2(float(p[0]), float(p[1]))
			release(w, v, float(cmd.get("amount", 1.0)), String(cmd.get("src", "order")))
		"mask_on":
			_ensure(w)
			for raw in cmd.get("unit_ids", []):
				var e = w.entities.get(int(raw))
				if e == null or int(e.owner) != int(cmd.get("issuer", -1)) or sealed(e):
					continue
				var m := _mk(e)
				m.on = 1 if bool(cmd.get("on", true)) and int(m.h) == 1 else 0
				m.t = w.tick
				w.emit("GasMask", {"id": int(e.id), "on": int(m.on) == 1})


# ================================================================ view
## RenderSnap g71 provider: {cells: PackedInt32Array [key, conc]..., cell, gw, wind [x, y], masked: PackedInt32Array ids}.
static func snap(w: SimWorld, _sn: Dictionary):
	var s = st(w)
	if s == null:
		return null
	var cd: Dictionary = s.c
	var cells := PackedInt32Array()
	for k in cd:
		cells.append(int(k))
		cells.append(int(cd[k]))
	var mk := PackedInt32Array()
	if not cd.is_empty():
		for id in SimIndex.unit_ids(w):
			var e = w.entities.get(int(id))
			if e != null and masked(e):
				mk.append(int(id))
	var wv := wind(w)
	return {"cells": cells, "cell": ri("cell"), "gw": _gw(w), "wind": [wv.x, wv.y], "masked": mk}
