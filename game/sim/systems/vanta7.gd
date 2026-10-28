extends RefCounted
## G7 AIRV7: the CN Vanta rotorless stealth gunship (docs/G7_REFERENCE.md 13.9c-14, 13.9c-15; numbers rules.g7_vanta in
## content/g7/defs_g7_vanta.json, all PROVISIONAL). Counter-nanite teams only (Human A cn_vanta_a / Human B cn_vanta_b).
##
## - Basing: trained at the Sentinel barracks (production facility cn_sentinel_barracks); a new Vanta is set down on
##   its facility's barracks roof pad (CnFacility.roof_pad, FACB7-4). One Vanta per pad. Landed on the pad it is
##   refuelled by CnFacility's services (roof pad is one of its air service rects) and rearmed / re-equipped here.
## - Flight: an ordinary G5 "vtol" aircraft (Air owns lift-off, hover, flight, fuel burn). Vanta7 adds the roof-pad
##   landing (Air's land_at refuses building cells), return-to-pad (command vanta_rtb, low fuel, AI calm), and a
##   slow pivot toward its target while hovering (attack runs keep the Movement facing).
## - Hardpoints (13.9c-15): nose (main) + one mirrored side pair (both sides carry and fire the same item) + rear.
##   Items per slot: rules.slots. Every shot leaves its own mount (ShotFired.from = the mount's world point, `vt`
##   = mount key) inside that mount's arc. Combat only ACQUIRES targets for the Vanta (fire-control weapon
##   g7_vanta_fc; e.ammo held at 0 so Combat never fires it itself); Vanta7 fires each hardpoint.
##   cannon / missiles / gun: e.target, the attack order's target, else (on a cadence) the nearest visible enemy
##   in that mount's arc and range. anti_drone: nearest enemy drone in range (any arc of its mount). drones:
##   launches the facility defence drones (cn_gun_drone, one per side) at the target; they expire after life_s.
##   flares / deterrents: passive, through shot_blocked (a G6Hooks SHOT delegate): flares decoy one guided /
##   anti-air missile per charge (gap_s apart); deterrents (DIRCM dazzler + decoys) defeat one every cooldown s.
## - Stealth: def.stealth radar_invisible (Airdef: radar / AWACS see it only within reveal_range) and a lock
##   failure for guided shots fired from beyond stealth_lock_frac of their range (pure hash, no rng draw).
## - Loadout: command vanta_loadout {unit_ids, nose?, side?, rear?, cycle?} only while landed on its roof pad;
##   applied after swap_s (mags full). Rearm: rearm_s after landing on the pad, every mag and flare charge refilled.
## - AI commander (AI factions only: never a player's Vanta): an enemy within ai_defend_r of the pad -> lift and
##   attack it; nothing near for ai_calm_s -> back to the pad.
## State (saved, hashed; created only when the first Vanta exists, so other matches keep their hashes):
##   w.sys_state.vanta7 = {ver, v: {"id": rec}, pads: {"fac id": vanta id}, dr: [[drone id, expire tick]]}
##   rec = {n, s, r (items), fac, mag {nose, sl, sr, rear}, rdy {mount: tick}, fl (flare charges), fg, dg,
##          rr (rearm due tick, -1 off pad), pend {n, s, r}?, sw, rtb, calm, at (auto target), att (its tick)}
## Entity fields (saved): e.art_def = "g7_vanta_<n>_<s>_<r>" (the loadout sheet), e.vt_deck = display altitude
##   fraction while standing on the barracks deck (render_snap CR), e.ammo = 0.
## Events: VantaReady, VantaLoadout, VantaRearmed, VantaFlares, VantaDeterrent, VantaLockLost, VantaDrones,
##   VantaRTB, plus ShotFired per hardpoint shot (flares: indirect arcs from the tail).
## Determinism: ascending ids, integer ticks, w.rng only for hit rolls, pure hash for lock loss.

const SimIndex = preload("res://sim/systems/sim_index.gd")
const HotState = preload("res://sim/hot_state.gd")

const KEY := "vanta7"
const VER := 1
const SLOTS := ["nose", "side", "rear"]
const MOUNTS := ["nose", "sl", "sr", "rear"]
const PATHS := {"cnf": "res://sim/systems/cn_facility.gd", "air": "res://sim/systems/air.gd", "dmg": "res://sim/systems/damage.gd",
	"mov": "res://sim/systems/movement.gd", "cbt": "res://sim/systems/combat.gd", "fog": "res://sim/systems/fog.gd",
	"ad": "res://sim/systems/airdef.gd", "cd": "res://sim/systems/counterdrone.gd"}
static var _deps := {}


static func _d(n: String):
	var s = _deps.get(n)
	if s == null:
		s = load(String(PATHS[n]))   # lazy: G6Hooks preloads this file (no preload cycle through Air / Combat)
		_deps[n] = s
	return s


static func R() -> Dictionary:
	return Content.rules().get("g7_vanta", {})


static func rf(k: String, d: float) -> float:
	return float(R().get(k, d))


static func items() -> Dictionary:
	return R().get("items", {})


static func is_vanta(e) -> bool:
	return e != null and String(e.get("kind", "")) == "unit" and bool(Content.unit(String(e.def)).get("cn_vanta", false))


static func active(w: SimWorld) -> bool:
	return w.sys_state.has(KEY)


static func st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"ver": VER, "v": {}, "pads": {}, "dr": []}
	return w.sys_state[KEY]


static func rec(w: SimWorld, id: int) -> Dictionary:
	var s = w.sys_state.get(KEY)
	return s.v.get(str(id), {}) if s != null else {}


static func loadout(w: SimWorld, id: int) -> Dictionary:
	var r := rec(w, id)
	return {} if r.is_empty() else {"nose": String(r.n), "side": String(r.s), "rear": String(r.r)}


static func art_id(n: String, s: String, r: String) -> String:
	return "g7_vanta_%s_%s_%s" % [n, s, r]


static func _sorted_ids(d: Dictionary) -> Array:
	var ks := []
	for k in d:
		ks.append(int(k))
	ks.sort()
	return ks


# ================================================================ pad
## The roof pad of facility fac_id: {rect, centre, z, heading_deg, ok} ({} none).
static func pad_of(w: SimWorld, fac_id: int) -> Dictionary:
	if fac_id <= 0:
		return {}
	var F: Dictionary = _d("cnf").fac(w, fac_id)
	return {} if F.is_empty() else _d("cnf").roof_pad(w, F)


## True when e stands on its own roof pad.
static func on_pad(w: SimWorld, e: Dictionary, r: Dictionary) -> bool:
	if not bool(e.get("air_landed", false)):
		return false
	var p := pad_of(w, int(r.get("fac", 0)))
	return not p.is_empty() and (p.rect as Rect2).grow(0.05).has_point(Vector2(e.pos))


## Facility id of fid whose barracks is building bid (else the nearest facility of fid with a free pad), 0 none.
static func _pick_fac(w: SimWorld, fid: int, bid: int, near: Vector2) -> int:
	var cnf = _d("cnf")
	if not cnf.active(w):
		return 0
	var pads: Dictionary = st(w).pads
	var best := 0
	var bd := INF
	for k in cnf.facilities(w, fid):
		var F: Dictionary = cnf.fac(w, int(k))
		var rp: Dictionary = cnf.roof_pad(w, F)
		if rp.is_empty() or not bool(rp.ok):
			continue
		var occ := int(pads.get(str(int(k)), 0))
		if occ != 0 and w.entities.has(occ):
			continue
		if bid > 0 and int(F.get("bar", 0)) == bid:
			return int(k)
		var dd := Vector2(rp.centre).distance_to(near)
		if dd < bd:
			bd = dd
			best = int(k)
	return best


## Production gate (Production CR): one Vanta per roof pad, counting the ones already queued.
static func can_produce(w: SimWorld, fid: int, item: String) -> String:
	var p := Content.production(item)
	var sp: Array = p.get("spawns", [])
	if sp.is_empty() or not bool(Content.unit(String(sp[0])).get("cn_vanta", false)):
		return ""
	var cnf = _d("cnf")
	var free := 0
	if cnf.active(w):
		var pads: Dictionary = st(w).pads if active(w) else {}
		for k in cnf.facilities(w, fid):
			var rp: Dictionary = cnf.roof_pad(w, cnf.fac(w, int(k)))
			var occ := int(pads.get(str(int(k)), 0))
			if not rp.is_empty() and bool(rp.ok) and (occ == 0 or not w.entities.has(occ)):
				free += 1
	for b in w.buildings_of(fid):
		for it in b.get("queue", []):
			var s2: Array = Content.production(String(it.item)).get("spawns", [])
			if not s2.is_empty() and bool(Content.unit(String(s2[0])).get("cn_vanta", false)):
				free -= 1
	return "" if free > 0 else "every barracks roof pad already has its Vanta"


# ================================================================ registration
static func _scan(w: SimWorld) -> void:
	var from := int(w.cache.get("vt_next", 1))
	if from >= w.next_id:
		return
	var prod := {}
	for ev in w.events:
		if String(ev.type) == "ProductionCompleted":
			for uid in ev.get("unit_ids", []):
				prod[int(uid)] = int(ev.get("building_id", -1))
	for id in range(from, w.next_id):
		var e = w.entities.get(id)
		if is_vanta(e) and rec(w, id).is_empty():
			register(w, e, int(prod.get(id, -1)))
	w.cache["vt_next"] = w.next_id


## Registers a Vanta (default loadout, full mags) and sets it down on its roof pad when one is free.
static func register(w: SimWorld, e: Dictionary, producer := -1) -> void:
	var s := st(w)
	var dl: Dictionary = R().get("default", {"nose": "cannon", "side": "missiles", "rear": "flares"})
	var r := {"n": String(dl.nose), "s": String(dl.side), "r": String(dl.rear), "fac": 0, "mag": {}, "rdy": {},
		"fl": 0, "fg": 0, "dg": 0, "rr": -1, "sw": 0, "rtb": false, "calm": w.tick, "at": -1, "att": -1000}
	_fill(r)
	s.v[str(int(e.id))] = r
	e.ammo = 0
	e.unhackable = true
	e.art_def = art_id(r.n, r.s, r.r)
	var fk := _pick_fac(w, int(e.owner), producer, Vector2(e.pos))
	if fk > 0:
		r.fac = fk
		s.pads[str(fk)] = int(e.id)
		var rp := pad_of(w, fk)
		e.facing = deg_to_rad(float(rp.get("heading_deg", 90.0)))
		_land(w, e, Vector2(rp.centre))
	w.emit("VantaReady", {"id": int(e.id), "owner": int(e.owner), "fac": fk})


static func _fill(r: Dictionary) -> void:
	var it := items()
	for m in MOUNTS:
		var item := String(r.n if m == "nose" else (r.r if m == "rear" else r.s))
		r.mag[m] = int((it.get(item, {}) as Dictionary).get("mag", 0))
	r.fl = int((it.get("flares", {}) as Dictionary).get("charges", 0)) if String(r.r) == "flares" else 0


static func _land(w: SimWorld, e: Dictionary, p: Vector2) -> void:
	var Air = _d("air")
	var f: Dictionary = Air._ensure(w, e)
	e.air_landed = true
	e.air_at = -1
	_d("mov").stop_path(e)
	e.order = {"type": "idle"}
	e.target = -1
	f.phase = "landed"
	for k in ["land_cell", "dest", "mission", "goal", "loiter", "next"]:
		f.erase(k)
	f.svc = 0.0
	f.pin = p
	e.pos = p
	HotState.touch(w, int(e.id))
	w.emit("AircraftLanded", {"id": int(e.id), "at": -1, "owner": int(e.owner), "vanta_pad": true})


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	_scan(w)
	var s = w.sys_state.get(KEY)
	if s == null:
		return
	for id in _sorted_ids(s.v):
		var e = w.entities.get(id)
		if e == null:
			_forget(w, s, id)
			continue
		_tick_one(w, s, e, s.v[str(id)])
	if not (s.dr as Array).is_empty():
		var keep := []
		for d in s.dr:
			if not w.entities.has(int(d[0])):
				continue
			if w.tick >= int(d[1]):
				var de: Dictionary = w.entities[int(d[0])]
				w.destroy(int(d[0]), "vanta_drone_spent", int(de.owner))
				continue
			keep.append(d)
		s.dr = keep


static func _forget(w: SimWorld, s: Dictionary, id: int) -> void:
	var r: Dictionary = s.v[str(id)]
	if int(s.pads.get(str(int(r.fac)), 0)) == id:
		s.pads.erase(str(int(r.fac)))
	s.v.erase(str(id))


static func _tick_one(w: SimWorld, s: Dictionary, e: Dictionary, r: Dictionary) -> void:
	if int(e.get("ammo", 0)) != 0:
		e.ammo = 0   # Combat acquires, Vanta7 fires: Combat's own shot never happens (Status NO_AMMO)
	var landed := bool(e.get("air_landed", false))
	var onp := landed and on_pad(w, e, r)
	var deck := rf("deck_alt", 0.76) if onp else 0.0
	if float(e.get("vt_deck", 0.0)) != deck:
		if deck > 0.0:
			e.vt_deck = deck
		else:
			e.erase("vt_deck")
	if onp:
		_service(w, e, r)
	elif int(r.rr) >= 0:
		r.rr = -1
	if not landed:
		_fly(w, e, r)
	if (w.tick + int(e.id)) % maxi(1, int(rf("think_every", 10))) == 0:
		_think(w, e, r, landed)
	if not landed and (w.tick + int(e.id)) % maxi(1, int(rf("fire_every", 2))) == 0:
		_fire_all(w, s, e, r)


## On the pad: rearm after rearm_s, apply a queued loadout after swap_s.
static func _service(w: SimWorld, e: Dictionary, r: Dictionary) -> void:
	var tr := SimWorld.TICK_RATE
	var fm := float(Content.unit(String(e.def)).get("fuel_max", 0.0))
	if e.has("fuel") and float(e.fuel) < fm:   # rooftop hot-refuel line (the facility bowser cannot reach the roof)
		e.fuel = minf(fm, float(e.fuel) + rf("roof_fuel_s", 30.0) * SimWorld.DT)
	if r.has("pend") and w.tick >= int(r.sw):
		var p: Dictionary = r.pend
		r.n = String(p.n)
		r.s = String(p.s)
		r.r = String(p.r)
		r.erase("pend")
		_fill(r)
		r.rr = w.tick
		e.art_def = art_id(r.n, r.s, r.r)
		w.emit("VantaLoadout", {"id": int(e.id), "owner": int(e.owner), "nose": r.n, "side": r.s, "rear": r.r})
		return
	if int(r.rr) < 0:
		r.rr = w.tick + int(round(rf("rearm_s", 8.0) * tr))
		return
	if w.tick >= int(r.rr) and not _full(r):
		_fill(r)
		w.emit("VantaRearmed", {"id": int(e.id), "owner": int(e.owner)})


static func _full(r: Dictionary) -> bool:
	var it := items()
	for m in MOUNTS:
		var item := String(r.n if m == "nose" else (r.r if m == "rear" else r.s))
		if int(r.mag.get(m, 0)) < int((it.get(item, {}) as Dictionary).get("mag", 0)):
			return false
	return String(r.r) != "flares" or int(r.fl) >= int((it.get("flares", {}) as Dictionary).get("charges", 0))


## Airborne: return-to-pad landing, low-fuel return, pivot toward the target while hovering.
static func _fly(w: SimWorld, e: Dictionary, r: Dictionary) -> void:
	var d := Content.unit(String(e.def))
	var p := pad_of(w, int(r.fac))
	if not p.is_empty() and bool(p.ok):
		var c: Vector2 = p.centre
		if not bool(r.rtb) and float(e.get("fuel", 1e9)) <= rf("rtb_fuel_frac", 0.35) * float(d.get("fuel_max", 1.0)):
			_start_rtb(w, e, r)
		if bool(r.rtb):
			var ot := String(e.order.get("type", "idle"))
			if ot != "idle" and not (ot == "move" and Vector2(e.order.get("target", Vector2.INF)) == c):
				r.rtb = false   # a fresh player / AI order wins
			else:
				var occ := int(st(w).pads.get(str(int(r.fac)), 0))
				var dist := Vector2(e.pos).distance_to(c)
				if dist <= rf("land_r", 0.8) and (occ == int(e.id) or occ == 0 or not w.entities.has(occ)):
					r.rtb = false
					e.facing = deg_to_rad(float(p.heading_deg))
					_land(w, e, c)
					return
				var f: Dictionary = _d("air")._ensure(w, e)
				f.land_cell = w.cell_of(c)   # keeps Air's low-fuel pad search from diverting it to another pad
				if String(f.get("phase", "")) == "ret":
					f.phase = "air"
					f.erase("dest")
				if not bool(e.moving):
					e.order = {"type": "move", "target": c}
					_d("mov").order_path(w, e, c)
	elif bool(r.rtb):
		r.rtb = false
	if not bool(e.moving):
		var t = _target(w, e)
		if t != null and ["cannon", "missiles"].has(String(r.n)):
			var want := (Vector2(t.pos) - Vector2(e.pos)).angle()
			var dl := wrapf(want - float(e.facing), -PI, PI)
			var stp := deg_to_rad(rf("turn_deg_s", 90.0)) * SimWorld.DT
			if absf(dl) > 0.0001:
				e.facing = wrapf(float(e.facing) + clampf(dl, -stp, stp), -PI, PI)


static func _start_rtb(w: SimWorld, e: Dictionary, r: Dictionary) -> void:
	var p := pad_of(w, int(r.fac))
	if p.is_empty():
		return
	r.rtb = true
	var c: Vector2 = p.centre
	var f: Dictionary = _d("air")._ensure(w, e)
	f.land_cell = w.cell_of(c)   # Air's low-fuel search for another pad stays off while it heads home
	if String(f.get("phase", "")) == "ret":
		f.phase = "air"
		f.erase("dest")
	e.order = {"type": "move", "target": c}
	e.target = -1
	_d("mov").order_path(w, e, c)
	w.emit("VantaRTB", {"id": int(e.id), "owner": int(e.owner), "fac": int(r.fac)})


# ================================================================ targets / fire
static func _alive_enemy(w: SimWorld, e: Dictionary, t) -> bool:
	return t != null and (String(t.kind) == "unit" or String(t.kind) == "building") and w.is_enemy(int(e.owner), int(t.owner)) \
		and float(t.get("hp", 1.0)) > 0.0


## The Vanta's ordered / acquired target (attack order first), or null.
static func _target(w: SimWorld, e: Dictionary):
	var t = null
	if String(e.order.get("type", "")) == "attack":
		t = w.entities.get(int(e.order.get("target_id", -1)))
	if not _alive_enemy(w, e, t):
		t = w.entities.get(int(e.get("target", -1)))
	return t if _alive_enemy(w, e, t) else null


static func _wstats(wid: String) -> Dictionary:
	var wd := Content.weapon(wid)
	return {"weapon": wid, "range": float(wd.get("range", 0)), "cooldown": float(wd.get("cooldown", 1)),
		"accuracy": float(wd.get("accuracy", 0)), "damage": float(wd.get("damage", 0)), "cls": String(wd.get("class", "")),
		"aa": bool(wd.get("anti_air", false)) or bool(wd.get("anti_air_low", false)) or bool(wd.get("anti_air_high", false)),
		"aa_low": bool(wd.get("anti_air_low", false)) or bool(wd.get("anti_air", false)), "aa_high": bool(wd.get("anti_air_high", false)),
		"naval_only": false, "anti_drone": bool(wd.get("anti_drone", false)), "indirect": false, "min_range": 0.0,
		"guided": bool(wd.get("guided", false)), "splash": float(wd.get("splash", 0)), "is_air": true, "setup": 0,
		"ignite": false, "ignore_cover": false}


## Mount world point (tiles) of mount m for e (local metres from rules.mounts; the left side mirrors the right).
static func mount_pos(e: Dictionary, m: String) -> Vector2:
	var mt: Dictionary = R().get("mounts", {})
	var v: Array = mt.get("side" if m == "sl" or m == "sr" else m, [0.0, 0.0, 0.0])
	var f := float(v[0])
	var rr := float(v[1]) * (-1.0 if m == "sl" else 1.0)
	var a := float(e.get("facing", 0.0))
	return Vector2(e.pos) + Vector2(f * cos(a) - rr * sin(a), f * sin(a) + rr * cos(a)) / 4.0


## True when world point p is inside mount m's arc for e.
static func in_arc(e: Dictionary, m: String, p: Vector2) -> bool:
	var ar: Dictionary = R().get("arcs", {})
	var a: Array = ar.get("side" if m == "sl" or m == "sr" else m, [0.0, 180.0])
	var c := deg_to_rad(float(a[0])) * (-1.0 if m == "sl" else 1.0)
	var rel := wrapf((p - Vector2(e.pos)).angle() - float(e.get("facing", 0.0)) - c, -PI, PI)
	return absf(rel) <= deg_to_rad(float(a[1])) + 0.0001


static func _slot_of(m: String) -> String:
	return "side" if m == "sl" or m == "sr" else m


static func _item(r: Dictionary, m: String) -> String:
	return String(r.n if m == "nose" else (r.r if m == "rear" else r.s))


static func _fire_all(w: SimWorld, s: Dictionary, e: Dictionary, r: Dictionary) -> void:
	var t = _target(w, e)
	var it := items()
	var cbt = _d("cbt")
	for m in MOUNTS:
		var item := _item(r, m)
		var spec: Dictionary = it.get(item, {})
		if int(r.rdy.get(m, 0)) > w.tick:
			continue
		if item == "drones":
			if m == "sl" and t != null and int(r.mag.get("sl", 0)) > 0 and Vector2(t.pos).distance_to(e.pos) <= float(spec.get("range", 12.0)):
				_launch_drones(w, s, e, r, t, spec)
			continue
		if not spec.has("weapon") or int(r.mag.get(m, 0)) <= 0:
			continue
		var ws := _wstats(String(spec.weapon))
		var tg = null
		if bool(spec.get("drones_only", false)):
			tg = _nearest_drone(w, e, m, float(ws.range))
		else:
			if t != null and Vector2(t.pos).distance_to(mount_pos(e, m)) <= float(ws.range) and in_arc(e, m, Vector2(t.pos)) and cbt.can_target(ws, t):
				tg = t
			else:
				tg = _auto_target(w, e, r, m, ws)
		if tg == null:
			continue
		_shoot(w, e, r, m, ws, tg)


static func _shoot(w: SimWorld, e: Dictionary, r: Dictionary, m: String, ws: Dictionary, tg: Dictionary) -> void:
	var acc := float(ws.accuracy) * (0.85 if bool(e.get("moving", false)) else 1.0)
	var hit := w.rng.randf() < acc
	var from := mount_pos(e, m)
	r.mag[m] = int(r.mag.get(m, 0)) - 1
	r.rdy[m] = w.tick + maxi(1, int(round(float(ws.cooldown) * SimWorld.TICK_RATE)))
	e.firing = 6
	w.emit("ShotFired", {"shooter": int(e.id), "target": int(tg.id), "weapon": String(ws.weapon), "hit": hit, "from": from,
		"to": Vector2(tg.pos), "indirect": false, "vt": m})
	_d("dmg").apply_hit(w, e, tg, ws, hit)


## Nearest enemy drone within rng of e inside mount m's arc (Airdef's drone list, ascending ids).
static func _nearest_drone(w: SimWorld, e: Dictionary, m: String, rng: float):
	var cd = _d("cd")
	var sub: Dictionary = _d("ad").sub_state(w)
	var best = null
	var bd := rng
	for did in sub.get("drone", []):
		var d = w.entities.get(int(did))
		if d == null or not w.is_enemy(int(e.owner), int(d.owner)) or not cd.is_drone(w, d):
			continue
		var dd := Vector2(d.pos).distance_to(e.pos)
		if dd <= bd and in_arc(e, m, Vector2(d.pos)):
			bd = dd
			best = d
	return best


## Nearest visible enemy in mount m's arc and range (searched every 8 ticks per Vanta, cached in rec.at).
static func _auto_target(w: SimWorld, e: Dictionary, r: Dictionary, m: String, ws: Dictionary):
	var cached = w.entities.get(int(r.at))
	if w.tick - int(r.att) < 8:
		if _alive_enemy(w, e, cached) and Vector2(cached.pos).distance_to(mount_pos(e, m)) <= float(ws.range) \
				and in_arc(e, m, Vector2(cached.pos)) and _d("cbt").can_target(ws, cached):
			return cached
		if m != "nose":
			return null
	r.att = w.tick
	r.at = -1
	var fog = _d("fog")
	var best = null
	var bd := float(ws.range) + 1.0
	var p0 := Vector2(e.pos)
	for id in SimIndex.unit_ids(w):
		var c = w.entities.get(int(id))
		if c == null or not w.is_enemy(int(e.owner), int(c.owner)):
			continue
		var dd := Vector2(c.pos).distance_to(p0)
		if dd >= bd or not fog.is_visible(w, int(e.owner), c.pos):
			continue
		if not _d("cbt").can_target(ws, c) or not in_arc(e, m, Vector2(c.pos)):
			continue
		bd = dd
		best = c
	if best != null:
		r.at = int(best.id)
	return best


static func _launch_drones(w: SimWorld, s: Dictionary, e: Dictionary, r: Dictionary, t: Dictionary, spec: Dictionary) -> void:
	var ids := []
	for m in ["sl", "sr"]:
		if int(r.mag.get(m, 0)) <= 0:
			continue
		var did := w.spawn_unit(String(spec.get("drone_def", "cn_gun_drone")), int(e.owner), mount_pos(e, m))
		var d: Dictionary = w.entities[did]
		d.unhackable = true
		_d("cbt").apply_command(w, {"type": "attack", "issuer": int(e.owner), "unit_ids": [did], "target_id": int(t.id)})
		s.dr.append([did, w.tick + int(round(float(spec.get("life_s", 45.0)) * SimWorld.TICK_RATE))])
		r.mag[m] = int(r.mag[m]) - 1
		r.rdy[m] = w.tick + int(round(float(spec.get("cooldown", 6.0)) * SimWorld.TICK_RATE))
		ids.append(did)
	if not ids.is_empty():
		e.firing = 6
		w.emit("VantaDrones", {"id": int(e.id), "owner": int(e.owner), "drones": ids, "target": int(t.id)})


# ================================================================ countermeasures (G6Hooks SHOT delegate)
## True when a shot from src (stats s) at Vanta t is lost: flares / deterrents decoy a guided or anti-air missile,
## or a guided shot from far out fails to lock the stealth airframe. Cheap reject when no Vanta exists.
static func shot_blocked(w: SimWorld, src: Dictionary, s: Dictionary, t: Dictionary, at: Vector2) -> bool:
	var sv = w.sys_state.get(KEY)
	if sv == null or t == null or String(t.get("kind", "")) != "unit":
		return false
	var r = sv.v.get(str(int(t.id)))
	if r == null or bool(t.get("air_landed", false)):
		return false
	var missile := bool(s.get("guided", false)) or (bool(s.get("aa", false)) and String(s.get("cls", "")) == "at")
	if not missile:
		return false
	var tr := SimWorld.TICK_RATE
	if String(r.r) == "flares" and int(r.fl) > 0 and w.tick >= int(r.fg):
		r.fl = int(r.fl) - 1
		r.fg = w.tick + int(round(float((items().get("flares", {}) as Dictionary).get("gap_s", 0.6)) * tr))
		_flare_fx(w, t, int(src.get("id", -1)))
		w.emit("VantaFlares", {"id": int(t.id), "owner": int(t.owner), "by": int(src.get("id", -1)), "left": int(r.fl)})
		return true
	if String(r.r) == "deterrents" and w.tick >= int(r.dg):
		r.dg = w.tick + int(round(float((items().get("deterrents", {}) as Dictionary).get("cooldown", 3.0)) * tr))
		_flare_fx(w, t, int(src.get("id", -1)))
		w.emit("VantaDeterrent", {"id": int(t.id), "owner": int(t.owner), "by": int(src.get("id", -1))})
		return true
	if bool(s.get("guided", false)):
		var dist := Vector2(src.get("pos", t.pos)).distance_to(t.pos)
		if dist > rf("stealth_lock_frac", 0.6) * float(s.get("range", 0.0)):
			var h := (int(src.get("id", 0)) * 73856093) ^ (w.tick * 19349663) ^ (int(t.id) * 83492791)
			if float(h & 0xFFFF) / 65536.0 < rf("stealth_lock_fail", 0.35):
				w.emit("VantaLockLost", {"id": int(t.id), "owner": int(t.owner), "by": int(src.get("id", -1))})
				return true
	return false


## Three flare / decoy cartridges arcing out of the tail (ShotFired indirect: fx_layer draws them as lobbed glows).
static func _flare_fx(w: SimWorld, t: Dictionary, by: int) -> void:
	var a := float(t.get("facing", 0.0))
	var from := mount_pos(t, "rear")
	for i in 3:
		var aa := a + PI + (float(i) - 1.0) * 0.55
		var to := from + Vector2(cos(aa), sin(aa)) * (1.4 + 0.3 * float(i % 2))
		w.emit("ShotFired", {"shooter": int(t.id), "target": -1, "weapon": "g7_vanta_flare", "hit": false, "from": from,
			"to": to, "indirect": true, "vt": "rear", "decoy_for": by})


# ================================================================ AI commander
static func _think(w: SimWorld, e: Dictionary, r: Dictionary, landed: bool) -> void:
	if not w.ai_state.has(int(e.owner)):
		return   # player-owned Vantas are flown by the player only
	var p := pad_of(w, int(r.fac))
	if p.is_empty():
		return
	var c: Vector2 = p.centre
	var rad := rf("ai_defend_r", 18.0)
	var fog = _d("fog")
	var best = null
	var bd := rad
	for id in SimIndex.unit_ids(w):
		var u = w.entities.get(int(id))
		if u == null or not w.is_enemy(int(e.owner), int(u.owner)):
			continue
		var dd := Vector2(u.pos).distance_to(c)
		if dd < bd and fog.is_visible(w, int(e.owner), u.pos):
			bd = dd
			best = u
	if best != null:
		r.calm = w.tick
		var fuel_ok := float(e.get("fuel", 1.0)) > 0.5 * float(Content.unit(String(e.def)).get("fuel_max", 1.0))
		if landed and not fuel_ok:
			return
		if String(e.order.get("type", "")) != "attack" or int(e.order.get("target_id", -1)) != int(best.id):
			var cmd := {"type": "attack", "issuer": int(e.owner), "unit_ids": [int(e.id)], "target_id": int(best.id)}
			if _d("cbt").validate_command(w, cmd) == "":
				r.rtb = false
				_d("cbt").apply_command(w, cmd)
				if landed:
					e.moving = true   # Air lifts a landed aircraft that has somewhere to go
	elif not landed and not bool(r.rtb) and w.tick - int(r.calm) > int(rf("ai_calm_s", 20.0) * SimWorld.TICK_RATE):
		_start_rtb(w, e, r)


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var t := String(cmd.get("type", ""))
	var any := false
	for raw in cmd.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if e == null or int(e.owner) != int(cmd.get("issuer", -1)) or not is_vanta(e):
			continue
		var r := rec(w, int(e.id))
		if r.is_empty():
			continue
		any = true
		match t:
			"vanta_loadout":
				if not on_pad(w, e, r):
					return "Land the Vanta on its roof pad to change the loadout."
				var sl: Dictionary = R().get("slots", {})
				for k in SLOTS:
					if cmd.has(k) and not (sl.get(k, []) as Array).has(String(cmd[k])):
						return "That %s hardpoint cannot take %s." % [k, String(cmd[k])]
				if cmd.has("cycle") and not SLOTS.has(String(cmd.cycle)):
					return "Unknown hardpoint."
			"vanta_rtb":
				if pad_of(w, int(r.fac)).is_empty():
					return "This Vanta has no roof pad."
			_:
				return "Unknown Vanta command."
	return "" if any else "Select a CN Vanta."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var t := String(cmd.get("type", ""))
	var sl: Dictionary = R().get("slots", {})
	for raw in cmd.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if e == null or int(e.owner) != int(cmd.get("issuer", -1)) or not is_vanta(e):
			continue
		var r := rec(w, int(e.id))
		if r.is_empty():
			continue
		match t:
			"vanta_loadout":
				if not on_pad(w, e, r):
					continue
				var cur: Dictionary = r.get("pend", {"n": r.n, "s": r.s, "r": r.r})
				var nx := {"n": String(cmd.get("nose", cur.n)), "s": String(cmd.get("side", cur.s)), "r": String(cmd.get("rear", cur.r))}
				if cmd.has("cycle"):
					var k := String(cmd.cycle)
					var kk: String = {"nose": "n", "side": "s", "rear": "r"}[k]
					var opts: Array = sl.get(k, [])
					if not opts.is_empty():
						nx[kk] = String(opts[(opts.find(String(nx[kk])) + 1) % opts.size()])
				r.pend = nx
				r.sw = w.tick + int(round(rf("swap_s", 10.0) * SimWorld.TICK_RATE))
				w.emit("VantaLoadoutQueued", {"id": int(e.id), "owner": int(e.owner), "nose": nx.n, "side": nx.s, "rear": nx.r})
			"vanta_rtb":
				if bool(e.get("air_landed", false)):
					if on_pad(w, e, r):
						continue
					_d("air")._lift(w, e, _d("air")._ensure(w, e))
				_start_rtb(w, e, r)
