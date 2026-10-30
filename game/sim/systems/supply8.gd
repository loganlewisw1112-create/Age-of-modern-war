extends RefCounted
## Supply8 (owner: SUPPLY8). G7_REFERENCE 13.9c-48: the magazine / ammo + fuel bay card and its AIRDROP RETRIEVAL OP.
## Owner: "air dropped come via airdrop pod in front of gates about 4-6 tiles outwards in open space ... once its
## dropped facility must dispatch 4 engineers per drop + 2 support sentinel squads (7 man defensive specialized GO
## teams) to fastly execute the retrieval of the drop(s) and bring it back to armory/mag ammo fuel bay /// go teams
## execute defensive positioning and escort the four engineers to pick up each drop [one drop at a time with cooldown
## period] + engineers utilize a tracked drone cargo truck bed that is quick/hardened with small ray shield defense
## (returns to a parked location or ... give the magazine ammo and fuel bay armour a garage for it)".
## The op (one per facility at a time, rules.g8_supply, every number PROVISIONAL):
##   order (sup8_order, credits; the next order is free after a failed op = retry) ->
##   DROP    the pod falls (fall_s) onto a deterministic open-ground spot 4-6 tiles outside the gate (never on a road,
##           a lane, the approach or a building); the two GO teams (2 x 7 Sentinels taken off the watch, posts /
##           towers last) move out first on the Sentinels7 stand-to drill and settle in a ring around the spot;
##   SECURE  the pod lands (unit g8_supply_pod); once secure_frac of the GO men are in position (or secure_max_s)
##   OUT     the tracked cargo carrier rolls out of its garage by the magazine with the 4 Facility Engineers;
##   LOAD    carrier + 2 engineers at the pod for load_s: the pod is loaded (removed);
##   RETURN  the carrier drives home, the GO teams escort it (their posts follow the carrier), engineers walk back;
##   the carrier reaches its garage: stock (rules.load ammo / fuel) is added, the carrier parks INSIDE the garage
##   (stored like Transport cargo, out of w.entities), engineers and GO men go back to automatic duty / the watch.
## Fail: pod or carrier destroyed, or op_max_s: everyone goes home, the drop can be retried free after the cooldown.
## Ray shield: the carrier's hull losses are refunded from a small shield pool (shield.hp) that recharges after
## shield.quiet_s without a hit. A destroyed carrier is rebuilt in its garage after rebuild_s.
## Card options (13.9c-48): stock levels + low-stock alerts, resupply priority (Supply8.prio, read by the Sentinels7
## restock / locker jobs and the Engineer7 fuel jobs), ammo type mix (AP / HE / incendiary / counter-nanite share of
## delivered rounds; round_share for LETHAL8's round model), order delivery.
## State (saved, hashed): w.sys_state.supply8 = {ver, seeded [fac], m {"uid": fac} (units held by an op), facs
## {"fac": Rf}, sides {"fid": {first, mix, typed, low}}}; created only once a counter-nanite facility exists.
## No facility: tick returns after one dictionary lookup; prio() = 1.0 and round_share() = -1 without a player choice.

const KEY := "supply8"
const VER := 1
const PHASES := ["drop", "secure", "out", "load", "return"]
const CLASSES := ["walls", "teams", "vehicles", "aircraft"]
const MIX_KEYS := ["ap", "he", "inc", "cn"]

static var _s7 = null
static var _e7 = null
static var _cf = null
static var _mv = null
static var _fd = null


static func S7():
	if _s7 == null:
		_s7 = load("res://sim/systems/sentinels7.gd")
	return _s7


static func E7():
	if _e7 == null:
		_e7 = load("res://sim/systems/engineer7.gd")
	return _e7


static func CF():
	if _cf == null:
		_cf = load("res://sim/systems/cn_facility.gd")
	return _cf


static func MV():
	if _mv == null:
		_mv = load("res://sim/systems/movement.gd")
	return _mv


## FACFLOW8C (13.9c-50): the facility vehicle controller (gates / airlock / lanes); loaded lazily like the others.
static func FD():
	if _fd == null:
		_fd = load("res://sim/systems/fac_drive7.gd")
	return _fd


## FACFLOW8C: the carrier is being driven through the compound + gates by FacDrive7 (supply8 leaves it alone meanwhile:
## a plain move order would be reclassified by FacDrive7._intercept, an inside target -> a pad bay).
static func _fd_busy(w: SimWorld, car: Dictionary) -> bool:
	return not FD().vstate(w, int(car.id)).is_empty()


## FACFLOW8C: back home through the hardened gates: FacDrive7 drives the carrier from outside to the lane node nearest
## its garage door ("n<node>", released there); supply8 drives the last metres. False = not possible (plain move).
static func _fd_home(w: SimWorld, Rf: Dictionary, car: Dictionary) -> bool:
	var F: Dictionary = CF().fac(w, int(Rf.fac))
	if F.is_empty() or CF().compound_rect(F).has_point(Vector2(car.pos)) or not FD().registered():
		return false
	var dl := Vector2(Rf.door) - Vector2(CF().origin(F))
	return FD().order(w, car, int(Rf.fac), "n%d" % FD()._nearest(FD().graph(), dl), "fac")


static func R() -> Dictionary:
	return Content.rules().get("g8_supply", {})


static func ticks(sec: float) -> int:
	return maxi(roundi(sec * SimWorld.TICK_RATE), 1)


static func state(w: SimWorld):
	return w.sys_state.get(KEY)


static func _st(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get(KEY)
	if st == null:
		st = {"ver": VER, "seeded": [], "m": {}, "facs": {}, "sides": {}}
		w.sys_state[KEY] = st
	return st


## True while unit uid is held by a running op (Sentinels7 / Engineer7 leave it alone).
static func held(w: SimWorld, uid: int) -> bool:
	var st = w.sys_state.get(KEY)
	return st != null and (st.m as Dictionary).has(str(uid))


static func rec(w: SimWorld, fac: int) -> Dictionary:
	var st = state(w)
	return st.facs.get(str(fac), {}) if st != null else {}


## Facility ids of side fid that have a supply record (sorted).
static func facs_of(w: SimWorld, fid: int) -> Array:
	var out := []
	var st = state(w)
	if st == null:
		return out
	for k in st.facs:
		if int(st.facs[k].owner) == fid:
			out.append(int(k))
	out.sort()
	return out


## The facility whose magazine is building bid (-1 when none).
static func fac_of_magazine(w: SimWorld, bid: int) -> int:
	var st = state(w)
	if st == null:
		return -1
	for k in st.facs:
		var Rf: Dictionary = st.facs[k]
		if int(Rf.mag) == bid or int(Rf.gar) == bid:
			return int(k)
	return -1


static func _side(w: SimWorld, fid: int) -> Dictionary:
	var st := _st(w)
	var k := str(fid)
	if not st.sides.has(k):
		var md: Dictionary = R().get("mix_default", {"ap": 40, "he": 30, "inc": 15, "cn": 15})
		st.sides[k] = {"first": "", "mix": md.duplicate(), "mix_set": false, "typed": {"ap": 0, "he": 0, "inc": 0, "cn": 0}, "low": {}}
	return st.sides[k]


## Resupply priority weight for class cls ("walls" | "teams" | "vehicles" | "aircraft") of side fid: 1.0 unless the
## player put that class first on the magazine card (then rules.prio_first). Pure read; never creates state.
static func prio(w: SimWorld, fid: int, cls: String) -> float:
	var st = w.sys_state.get(KEY)
	if st == null:
		return 1.0
	var sd = st.sides.get(str(fid))
	if sd == null or String(sd.first) != cls:
		return 1.0
	return float(R().get("prio_first", 1.8))


## Share (0..1) of round type key ("ap" | "he" | "inc" | "cn") in side fid's ammo mix; -1.0 while the player never
## set a mix (LETHAL8's round model then keeps its own defaults).
static func round_share(w: SimWorld, fid: int, key: String) -> float:
	var st = w.sys_state.get(KEY)
	if st == null:
		return -1.0
	var sd = st.sides.get(str(fid))
	if sd == null or not bool(sd.get("mix_set", false)):
		return -1.0
	var tot := 0
	for k in MIX_KEYS:
		tot += int(sd.mix.get(k, 0))
	return float(sd.mix.get(key, 0)) / float(maxi(tot, 1))


# ================================================================ layout (pure functions of the facility layout)
static func _rects_of(F: Dictionary) -> Array:
	var c: Dictionary = CF().conf()
	var O := Vector2(CF().origin(F))
	var out := []
	for n in CF().ZONES:
		out.append(CF().zone(F, n))
	for k in ["approach", "fuel_bay"]:
		var a = c.get(k)
		if a is Array and a.size() >= 4:
			out.append(Rect2(O + Vector2(float(a[0]), float(a[1])), Vector2(float(a[2]), float(a[3]))))
	var gs: Array = c.get("garage_size", [3, 3])
	for g in c.get("garages", []):
		out.append(Rect2(O + Vector2(float(g[0]), float(g[1])), Vector2(float(gs[0]), float(gs[1]))))
	for l in c.get("lanes", []) + c.get("link_walls", []):
		out.append(Rect2(O + Vector2(float(l[0]), float(l[1])), Vector2(float(l[2]), float(l[3]))))
	return out


## Points that keep a 1-tile clearance (doors, popups, lockers, the checkpoint / mantrap).
static func _points_of(F: Dictionary) -> Array:
	var c: Dictionary = CF().conf()
	var O := Vector2i(CF().origin(F))
	var out := []
	var ds: Dictionary = c.get("doors", {})
	for k in ds:
		for d in ds[k]:
			out.append(O + Vector2i(int(d[0]), int(d[1])))
	for k in ["popups", "lockers", "mantrap"]:
		for p in c.get(k, []):
			out.append(O + Vector2i(int(p[0]), int(p[1])))
	return out


static func _lane_cell(F: Dictionary, cell: Vector2i) -> bool:
	var c: Dictionary = CF().conf()
	var O := Vector2i(CF().origin(F))
	for l in c.get("lanes", []):
		if Rect2i(O + Vector2i(int(l[0]), int(l[1])), Vector2i(int(l[2]), int(l[3]))).has_point(cell):
			return true
	return false


static func _bcells(w: SimWorld) -> Dictionary:
	var occ := {}
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "building":
			var sz := int(e.get("size", 1))
			for yy in sz:
				for xx in sz:
					occ[Vector2i(e.cell) + Vector2i(xx, yy)] = true
	return occ


## The carrier garage cell of facility F: the free compound cell nearest the magazine that is outside every zone,
## lane, APC garage, the approach and the bowser bay, 1 tile clear of every door / pop-up / locker, not a building,
## and has a lane cell beside it (its door: the carrier drives straight out onto the lane). [cell, door] or [].
static func garage_spot(w: SimWorld, F: Dictionary) -> Array:
	var cs := int(CF().conf().compound)
	var O := Vector2i(CF().origin(F))
	var mz: Rect2 = CF().zone(F, "magazine")
	var rects := _rects_of(F)
	var pts := _points_of(F)
	var occ := _bcells(w)
	var team := _team(w, int(F.owner))
	var cand := []
	for y in range(2, cs - 2):
		for x in range(2, cs - 2):
			var c := O + Vector2i(x, y)
			var d := (Vector2(c) + Vector2(0.5, 0.5)).distance_squared_to(mz.get_center())
			cand.append([d, y, x])
	cand.sort()
	for q in cand:
		var c := O + Vector2i(int(q[2]), int(q[1]))
		var cc := Vector2(c) + Vector2(0.5, 0.5)
		if occ.has(c):
			continue
		var bad := false
		for r in rects:
			if (r as Rect2).has_point(cc):
				bad = true
				break
		if bad:
			continue
		for p in pts:
			if absi(p.x - c.x) <= 1 and absi(p.y - c.y) <= 1:
				bad = true
				break
		if bad or not MV().is_passable(w, c, "foot", team):
			continue
		for dv in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			var dc: Vector2i = c + dv
			if _lane_cell(F, dc) and not occ.has(dc) and MV().is_passable(w, dc, "vehicle", team):
				return [c, dc]
	return []


static func _team(w: SimWorld, fid: int) -> int:
	return int(S7()._team(w, fid))


static func _carrier_def(w: SimWorld, fid: int) -> String:
	var fd := String(w.factions[fid].get("faction_def", "")) if w.factions.has(fid) else ""
	return "g8_b_cargo_carrier" if fd == "human_b" else "g8_cargo_carrier"


## The pod's landing point for facility F: open ground 4-6 tiles (rules.drop) outside the outer gate, straight out
## from the gate first, then stepping sideways; never on a road / rail / bridge / water, a lane, the approach, a
## building or next to one (the paved approach road may run beside it). Vector2 (cell centre) or Vector2(-1, -1).
static func pod_spot(w: SimWorld, F: Dictionary) -> Vector2:
	var c: Dictionary = CF().conf()
	var O := Vector2(CF().origin(F))
	var cs := float(c.compound)
	var g: Array = c.get("gate_outer", c.get("gate", [12, 26, 4, 2]))
	var gr := Rect2(O + Vector2(float(g[0]), float(g[1])), Vector2(float(g[2]), float(g[3])))
	var cen := O + Vector2(cs, cs) * 0.5
	var dv := gr.get_center() - cen
	var out := Vector2(signf(dv.x), 0.0) if absf(dv.x) > absf(dv.y) else Vector2(0.0, signf(dv.y))
	var side := Vector2(-out.y, out.x)
	var edge := gr.get_center() + out * (absf(out.x) * gr.size.x + absf(out.y) * gr.size.y) * 0.5
	var rects := _rects_of(F)
	var occ := _bcells(w)
	var team := _team(w, int(F.owner))
	var dr: Dictionary = R().get("drop", {})
	var dmin := int(dr.get("min", 4))
	var dmax := int(dr.get("max", 6))
	var ds := []
	var mid := (dmin + dmax) / 2
	ds.append(mid)
	for k in range(1, dmax - dmin + 1):
		if mid - k >= dmin:
			ds.append(mid - k)
		if mid + k <= dmax:
			ds.append(mid + k)
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var bad_t := [Terrain.ROAD, Terrain.RAIL, Terrain.BRIDGE, Terrain.WATER, Terrain.SHALLOW, Terrain.DEEP, Terrain.FORD, Terrain.CLIFF, Terrain.CHASM, Terrain.BUILDING]
	for o in [0, -1, 1, -2, 2, -3, 3, -4, 4, -5, 5, -6, 6, -7, 7, -8, 8]:
		for d in ds:
			var p: Vector2 = edge + out * (float(d) - 0.5) + side * float(o)
			var cell := Vector2i(floori(p.x), floori(p.y))
			if cell.x < 1 or cell.y < 1 or cell.x >= mw - 1 or cell.y >= mh - 1:
				continue
			var ok := true
			for r in rects:
				if (r as Rect2).has_point(Vector2(cell) + Vector2(0.5, 0.5)):
					ok = false
					break
			if not ok:
				continue
			for yy in range(-1, 2):
				for xx in range(-1, 2):
					var n := cell + Vector2i(xx, yy)
					var t := int(w.map.terrain[n.y * mw + n.x])
					if occ.has(n) or (n == cell and bad_t.has(t)) or not MV().is_passable(w, n, "vehicle", team):
						ok = false
			if ok:
				return Vector2(cell) + Vector2(0.5, 0.5)
	return Vector2(-1, -1)


## Sets up facility fac (once): the carrier garage beside the magazine, the carrier parked inside, the engineer crew
## topped up to rules.engineers (the carrier's crew). Waits until Engineer7 seeded the facility's starting crew.
static func _seed(w: SimWorld, st: Dictionary, fac: int) -> void:
	var F: Dictionary = CF().fac(w, fac)
	if F.is_empty():
		return
	var es = E7().state(w)
	if es != null and not (es.seeded as Array).has(fac):
		return   # the starting crew is not out yet
	st.seeded.append(fac)
	st.seeded.sort()
	var fid := int(F.owner)
	var mag := int(F.get("mag", 0))
	if mag <= 0 or not w.entities.has(mag) or Content.unit(_carrier_def(w, fid)).is_empty():
		return
	var gs := garage_spot(w, F)
	var Rf := {"fac": fac, "owner": fid, "mag": mag, "gar": -1, "door": Vector2.ZERO, "car": -1, "stored": {},
		"cd": -1, "retry": false, "op": {}, "n_ok": 0, "n_fail": 0, "sh": float(R().get("shield", {}).get("hp", 260.0)),
		"sh_t": -100000, "hp0": -1.0, "reb": -1, "last": ""}
	st.facs[str(fac)] = Rf
	if gs.is_empty():
		w.emit("Supply8NoGarage", {"fac": fac, "owner": fid})
	else:
		var gid := w.spawn_building("cn_carrier_garage", fid, gs[0], true)
		Rf.gar = gid
		Rf.door = Vector2(gs[1]) + Vector2(0.5, 0.5)
		_new_carrier(w, Rf)
	_side(w, fid)
	if es != null:
		var have: int = E7().engineers_of(w, fac).size()
		var dd: String = E7().def_for(w, fid)
		for i in maxi(int(R().get("engineers", 4)) - have, 0):
			if dd == "" or Content.unit(dd).is_empty():
				break
			var at: Vector2 = Rf.door if int(Rf.gar) >= 0 else CF().zone(F, "workshop").get_center()
			var uid := w.spawn_unit(dd, fid, at)
			w.entities[uid].order = {"type": "idle"}
			E7().enlist(w, w.entities[uid], fac)
	w.emit("Supply8Ready", {"fac": fac, "owner": fid, "garage": int(Rf.gar), "carrier": int(Rf.car)})


static func _invalidate(w: SimWorld) -> void:
	w.cache.erase("sim_index")
	w.cache.erase("unit_subsets")


## A fresh carrier, parked inside the garage (stored out of w.entities, like Transport cargo).
static func _new_carrier(w: SimWorld, Rf: Dictionary) -> void:
	var uid := w.spawn_unit(_carrier_def(w, int(Rf.owner)), int(Rf.owner), Vector2(Rf.door))
	var e: Dictionary = w.entities[uid]
	e.order = {"type": "idle"}
	e.squad = -1
	e.sup8 = int(Rf.fac)
	Rf.car = uid
	Rf.sh = float(R().get("shield", {}).get("hp", 260.0))
	_park(w, Rf)


static func _park(w: SimWorld, Rf: Dictionary) -> void:
	var e = w.entities.get(int(Rf.car))
	if e == null:
		return
	MV().stop_path(e)
	e.order = {"type": "idle"}
	e.target = -1
	w.entities.erase(int(Rf.car))
	Rf.stored = e
	_invalidate(w)
	w.emit("Supply8CarrierParked", {"fac": int(Rf.fac), "owner": int(Rf.owner), "carrier": int(Rf.car), "garage": int(Rf.gar)})


static func _unpark(w: SimWorld, Rf: Dictionary) -> Dictionary:
	if (Rf.stored as Dictionary).is_empty():
		return w.entities.get(int(Rf.car), {})
	var e: Dictionary = Rf.stored
	e.pos = Vector2(Rf.door)
	e.order = {"type": "idle"}
	w.entities[int(e.id)] = e
	Rf.stored = {}
	_invalidate(w)
	SimWorld.HotState.touch(w, int(e.id))
	return e


# ================================================================ commands
static func _rf_for(w: SimWorld, cmd: Dictionary) -> Dictionary:
	var fid := int(cmd.get("issuer", -1))
	var bid := int(cmd.get("building_id", -1))
	var fac := fac_of_magazine(w, bid) if bid >= 0 else -1
	if fac < 0:
		var l := facs_of(w, fid)
		fac = int(l[0]) if not l.is_empty() else -1
	var Rf := rec(w, fac)
	return Rf if not Rf.is_empty() and int(Rf.owner) == fid else {}


## "" when facility fac of side fid can take a delivery order now, else the reason (the card's tooltip).
static func order_reason(w: SimWorld, fid: int, fac: int) -> String:
	var Rf := rec(w, fac)
	if Rf.is_empty() or int(Rf.owner) != fid:
		return "No magazine of yours."
	if not w.entities.has(int(Rf.mag)):
		return "The magazine is destroyed."
	if int(Rf.gar) < 0 or not w.entities.has(int(Rf.gar)):
		return "The carrier garage is gone."
	if not (Rf.op as Dictionary).is_empty():
		return "A retrieval is already running (one drop at a time)."
	if int(Rf.cd) > w.tick:
		return "Cooldown: next drop in %ds." % int(ceil(float(int(Rf.cd) - w.tick) / float(SimWorld.TICK_RATE)))
	if int(Rf.reb) >= 0:
		return "The cargo carrier is being rebuilt (%ds)." % int(ceil(float(maxi(int(Rf.reb) - w.tick, 0)) / float(SimWorld.TICK_RATE)))
	var cost := int(R().get("cost", {}).get("credits", 900))
	if not bool(Rf.retry) and int(w.factions[fid].credits) < cost:
		return "Needs %d credits." % cost
	var F: Dictionary = CF().fac(w, int(Rf.fac))
	if pod_spot(w, F).x < 0.0:
		return "No open ground outside the gate for the pod."
	var need_go := int(R().get("teams", 2)) * int(R().get("team_size", 7))
	var go := _pick_go(w, Rf, need_go)
	if go.size() < need_go:
		return "Needs %d Sentinels free for the GO teams (%d free)." % [need_go, go.size()]
	var ne := int(R().get("engineers", 4))
	var en := _pick_eng(w, Rf, ne)
	if en.size() < ne:
		return "Needs %d Facility Engineers free (%d free)." % [ne, en.size()]
	return ""


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var Rf := _rf_for(w, cmd)
	if Rf.is_empty():
		return "No magazine of yours."
	match String(cmd.get("type", "")):
		"sup8_order":
			return order_reason(w, int(Rf.owner), int(Rf.fac))
		"sup8_prio":
			var f := String(cmd.get("first", ""))
			return "" if f == "" or CLASSES.has(f) else "Unknown resupply class."
		"sup8_mix":
			var k := String(cmd.get("key", ""))
			if not MIX_KEYS.has(k):
				return "Unknown round type."
			var sd: Dictionary = state(w).sides.get(str(int(Rf.owner)), {})
			var v := int(sd.get("mix", {}).get(k, 0))
			var dlt := int(cmd.get("delta", 0))
			if dlt > 0 and v >= 100:
				return "Already 100%."
			if dlt < 0 and v <= 0:
				return "Already 0%."
			return "" if dlt != 0 else "No change."
	return "Unknown supply command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var Rf := _rf_for(w, cmd)
	if Rf.is_empty():
		return
	var fid := int(Rf.owner)
	match String(cmd.get("type", "")):
		"sup8_order":
			_start(w, Rf)
		"sup8_prio":
			var sd := _side(w, fid)
			sd.first = String(cmd.get("first", ""))
			w.emit("Supply8Priority", {"owner": fid, "first": String(sd.first)})
		"sup8_mix":
			_mix(_side(w, fid), String(cmd.key), int(cmd.delta))
			w.emit("Supply8Mix", {"owner": fid, "mix": (_side(w, fid).mix as Dictionary).duplicate()})


## Moves rules.mix_step points of share to / from round type k (taken from the largest other share, given to the
## smallest); the shares always total 100.
static func _mix(sd: Dictionary, k: String, dlt: int) -> void:
	var step := int(R().get("mix_step", 10))
	var m: Dictionary = sd.mix
	var o := ""
	for kk in MIX_KEYS:
		if kk == k:
			continue
		if o == "" or (dlt > 0 and int(m[kk]) > int(m[o])) or (dlt < 0 and int(m[kk]) < int(m[o])):
			o = kk
	var n := mini(step, int(m[o])) if dlt > 0 else mini(step, int(m[k]))
	if dlt > 0:
		n = mini(n, 100 - int(m[k]))
		m[k] = int(m[k]) + n
		m[o] = int(m[o]) - n
	else:
		m[k] = int(m[k]) - n
		m[o] = int(m[o]) + n
	sd.mix_set = true


# ================================================================ the op: crew
const GO_RANK := {"rest": 0, "auto": 0, "free": 0, "int": 1, "patrol": 1, "wall": 2, "qrf": 2, "standto": 3, "post": 4, "tower": 4, "entry": 5, "gate": 5}


static func _gate_pt(F: Dictionary) -> Vector2:
	return CF().zone(F, "gate_outer").get_center()


## The n Sentinels of the facility that can best be spared for the GO teams: fit (not down, hp > half), not a bearer,
## not on a player order / casualty / ammo run, not a Last Protocol reserve man; resting / interior men first, the
## towers and the entry last, then nearest the gate.
static func _pick_go(w: SimWorld, Rf: Dictionary, n: int) -> Array:
	var S = S7().state(w)
	if S == null:
		return []
	var F: Dictionary = CF().fac(w, int(Rf.fac))
	var gp := _gate_pt(F) if not F.is_empty() else Vector2.ZERO
	var lr = w.sys_state.get("lpres7")
	var c := []
	for id in S.ids:
		var uid := int(id)
		var e = w.entities.get(uid)
		if e == null or int(e.owner) != int(Rf.owner) or String(e.get("s7", "")) == "bearer" or held(w, uid):
			continue
		if SimWorld.Wounds.is_down(e) or float(e.hp) < float(e.max_hp) * 0.5:
			continue
		if lr != null and (lr.m as Dictionary).has(str(uid)):
			continue
		var job: Dictionary = S.jobs.get(str(uid), {})
		var k := String(job.get("k", "auto"))
		if int(job.get("fac", Rf.fac)) != int(Rf.fac) or ["player", "casualty", "ammo"].has(k) or bool(job.get("wd", false)):
			continue
		c.append([int(GO_RANK.get(k, 3)), snappedf(Vector2(e.pos).distance_to(gp), 0.01), uid])
	c.sort()
	var out := []
	for q in c:
		if out.size() >= n:
			break
		out.append(int(q[2]))
	return out


static func _pick_eng(w: SimWorld, Rf: Dictionary, n: int) -> Array:
	var es = E7().state(w)
	if es == null:
		return []
	var c := []
	for uid in E7().engineers_of(w, int(Rf.fac)):
		var e = w.entities.get(int(uid))
		if e == null or held(w, int(uid)) or SimWorld.Wounds.is_down(e) or int(e.owner) != int(Rf.owner):
			continue
		var rc: Dictionary = S7().job_of(w, int(uid))
		var run: Dictionary = es.run.get(str(uid), {})
		if String(rc.get("k", "auto")) == "player" or E7().DRIVE_PHASES.has(String(run.get("ph", ""))):
			continue
		c.append([snappedf(Vector2(e.pos).distance_to(Vector2(Rf.door)), 0.01), int(uid)])
	c.sort()
	var out := []
	for q in c:
		if out.size() >= n:
			break
		out.append(int(q[1]))
	return out


static func _free_pt(w: SimWorld, p: Vector2, team: int, mc: String = "foot") -> Vector2:
	var c := Vector2i(floori(p.x), floori(p.y))
	if MV().is_passable(w, c, mc, team):
		return p
	var n: Vector2i = MV().nearest_free_cell(w, c, mc, team)
	return Vector2(n) + Vector2(0.5, 0.5)


## Ring post i of n around centre p (outward = away from the facility; the first half of the ring faces out).
static func _ring(p: Vector2, out: Vector2, i: int, n: int, r: float) -> Vector2:
	var a := out.angle() - PI * 0.5 + TAU * (float(i) + 0.5) / float(maxi(n, 1))
	return p + Vector2(cos(a), sin(a)) * r


static func _move(w: SimWorld, e: Dictionary, goal: Vector2) -> void:
	e.order = {"type": "move", "target": goal}
	MV().order_path(w, e, goal)
	SimWorld.HotState.touch(w, int(e.id))


## Moves e toward goal unless it is already going there or standing within tol of it.
static func _move_if(w: SimWorld, e: Dictionary, goal: Vector2, tol: float) -> void:
	if Vector2(e.pos).distance_to(goal) <= tol:
		return
	var o: Dictionary = e.order
	if String(o.get("type", "")) == "move" and o.get("target") is Vector2 and Vector2(o.target).distance_to(goal) < 0.05:
		return
	_move(w, e, goal)


static func _start(w: SimWorld, Rf: Dictionary) -> void:
	var st := _st(w)
	var fid := int(Rf.owner)
	var fac := int(Rf.fac)
	var F: Dictionary = CF().fac(w, fac)
	var free := bool(Rf.retry)
	if not free:
		w.factions[fid].credits = int(w.factions[fid].credits) - int(R().get("cost", {}).get("credits", 900))
	Rf.retry = false
	var spot := pod_spot(w, F)
	var go := _pick_go(w, Rf, int(R().get("teams", 2)) * int(R().get("team_size", 7)))
	var en := _pick_eng(w, Rf, int(R().get("engineers", 4)))
	var num := int(Rf.n_ok) + int(Rf.n_fail) + 1
	var out: Vector2 = (spot - CF().compound_rect(F).get_center()).normalized()
	var team := _team(w, fid)
	var S := S7()._st(w) as Dictionary
	var posts := {}
	var ring := float(R().get("go_ring", 2.6))
	for i in go.size():
		var uid := int(go[i])
		var mate := int(go[i + 1]) if i % 2 == 0 and i + 1 < go.size() else (int(go[i - 1]) if i % 2 == 1 else -1)
		var pt := _free_pt(w, _ring(spot, out, i, go.size(), ring), team)
		posts[str(uid)] = pt
		S.jobs[str(uid)] = {"k": "standto", "j": "sup8:%d" % num, "fac": fac, "bid": -1, "pos": pt, "in": false, "bud": mate, "hand": true}
		st.m[str(uid)] = fac
	var es = E7().state(w)
	for i in en.size():
		var uid := int(en[i])
		var e: Dictionary = w.entities[uid]
		if es != null and es.run.has(str(uid)):
			E7()._drive(w, e, "")
			es.run.erase(str(uid))
		S7().set_worker_job(w, uid, {"k": "free", "fac": fac, "sup8": true})
		st.m[str(uid)] = fac
		_move(w, e, _free_pt(w, Vector2(Rf.door) + Vector2(0.6 * float(i % 2) - 0.3, 0.6 * float(i / 2) - 0.3), team))
	var fall := ticks(float(R().get("drop", {}).get("fall_s", 8.0)))
	Rf.op = {"ph": "drop", "n": num, "t0": w.tick, "tp": w.tick, "land": w.tick + fall, "spot": spot, "out": out, "pod": -1,
		"go": go, "eng": en, "post": posts, "lt": 0, "esc": 0, "free": free}
	Rf.last = ""
	w.emit("Supply8Order", {"fac": fac, "owner": fid, "spot": spot, "eta_s": float(fall) / float(SimWorld.TICK_RATE),
		"go": go.duplicate(), "eng": en.duplicate(), "retry": free, "op": num})


# ================================================================ system
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get(KEY)
	if st == null:
		var cn = w.sys_state.get("cn_facility")
		if cn == null or w.tick % 20 != 0 or (cn.get("facs", {}) as Dictionary).is_empty():
			return
		st = _st(w)
	if w.tick % 20 == 0:
		var cn = w.sys_state.get("cn_facility")
		if cn != null:
			var ks := []
			for k in cn.facs:
				ks.append(int(k))
			ks.sort()
			for k in ks:
				if not (st.seeded as Array).has(k):
					_seed(w, st, k)
	var ev := ticks(float(R().get("every_s", 0.5)))
	var fs := []
	for k in st.facs:
		fs.append(int(k))
	fs.sort()
	for k in fs:
		if (w.tick + k) % ev == 0:
			_step(w, st, st.facs[str(k)])
	if w.tick % ticks(4.0) == 0:
		_alerts(w, st)


static func _alerts(w: SimWorld, st: Dictionary) -> void:
	var lo: Dictionary = R().get("low", {})
	var ks := []
	for k in st.sides:
		ks.append(int(k))
	ks.sort()
	for fid in ks:
		if not w.factions.has(fid):
			continue
		var sd: Dictionary = st.sides[str(fid)]
		for res in ["ammo", "fuel"]:
			var have := int(w.factions[fid].stock.get(res, 0))
			var thr := int(lo.get(res, 0))
			if have < thr and not bool(sd.low.get(res, false)):
				sd.low[res] = true
				w.emit("Supply8Low", {"owner": fid, "res": res, "stock": have, "below": thr})
			elif have >= thr and bool(sd.low.get(res, false)):
				sd.low.erase(res)


static func _shield(w: SimWorld, Rf: Dictionary, ev: int) -> void:
	var e = w.entities.get(int(Rf.car))
	if e == null:
		Rf.hp0 = -1.0
		return
	var sh: Dictionary = R().get("shield", {})
	var mx := float(sh.get("hp", 260.0))
	var hp := float(e.hp)
	if float(Rf.hp0) >= 0.0 and hp < float(Rf.hp0) and hp > 0.0:
		var back := minf(float(Rf.hp0) - hp, float(Rf.sh))
		if back > 0.0:
			e.hp = hp + back
			Rf.sh = snappedf(float(Rf.sh) - back, 1.0 / 64.0)
			w.emit("Supply8Shield", {"id": int(e.id), "owner": int(e.owner), "absorbed": back, "left": float(Rf.sh)})
		Rf.sh_t = w.tick
	elif w.tick - int(Rf.sh_t) > ticks(float(sh.get("quiet_s", 6.0))) and float(Rf.sh) < mx:
		Rf.sh = minf(mx, snappedf(float(Rf.sh) + mx * float(ev) / float(SimWorld.TICK_RATE) / float(sh.get("regen_s", 20.0)), 1.0 / 64.0))
	Rf.hp0 = float(e.hp)


static func _step(w: SimWorld, st: Dictionary, Rf: Dictionary) -> void:
	var ev := ticks(float(R().get("every_s", 0.5)))
	_shield(w, Rf, ev)
	var out_car := (Rf.stored as Dictionary).is_empty()
	if int(Rf.reb) >= 0:
		if w.tick >= int(Rf.reb) and int(Rf.gar) >= 0 and w.entities.has(int(Rf.gar)):
			Rf.reb = -1
			_new_carrier(w, Rf)
			w.emit("Supply8CarrierRebuilt", {"fac": int(Rf.fac), "owner": int(Rf.owner), "carrier": int(Rf.car)})
	elif out_car and int(Rf.car) >= 0 and not w.entities.has(int(Rf.car)):
		Rf.reb = w.tick + ticks(float(R().get("rebuild_s", 60.0)))   # the carrier was destroyed: a new one is built
		Rf.car = -1
	if (Rf.op as Dictionary).is_empty():
		if out_car and w.entities.has(int(Rf.car)):   # back from a failed op: drive home and park
			var e: Dictionary = w.entities[int(Rf.car)]
			if Vector2(e.pos).distance_to(Vector2(Rf.door)) < 0.9:
				_park(w, Rf)
			elif not _fd_busy(w, e) and not _fd_home(w, Rf, e):
				_move_if(w, e, Vector2(Rf.door), 0.5)
		return
	_op(w, st, Rf, ev)


static func _alive(w: SimWorld, ids: Array) -> Array:
	var out := []
	for id in ids:
		var e = w.entities.get(int(id))
		if e != null and not SimWorld.Wounds.is_down(e):
			out.append(int(id))
	return out


static func _near(w: SimWorld, ids: Array, p: Vector2, r: float) -> int:
	var n := 0
	for id in ids:
		var e = w.entities.get(int(id))
		if e != null and Vector2(e.pos).distance_to(p) <= r:
			n += 1
	return n


static func _op(w: SimWorld, st: Dictionary, Rf: Dictionary, ev: int) -> void:
	var op: Dictionary = Rf.op
	var fac := int(Rf.fac)
	var team := _team(w, int(Rf.owner))
	var spot: Vector2 = op.spot
	var lr := float(R().get("load_r", 1.6))
	if w.tick - int(op.t0) > ticks(float(R().get("op_max_s", 300.0))):
		_end(w, st, Rf, false, "timeout")
		return
	var ph := String(op.ph)
	var pod_ok := int(op.pod) >= 0 and w.entities.has(int(op.pod))
	if (ph == "secure" or ph == "out" or ph == "load") and not pod_ok:
		_end(w, st, Rf, false, "pod destroyed")
		return
	if (ph == "out" or ph == "load" or ph == "return") and not w.entities.has(int(Rf.car)):
		_end(w, st, Rf, false, "carrier destroyed")
		return
	var eng := _alive(w, op.eng)
	match ph:
		"drop":
			if w.tick >= int(op.land):
				var pid := w.spawn_unit("g8_supply_pod", int(Rf.owner), spot)
				var pe: Dictionary = w.entities[pid]
				pe.order = {"type": "idle"}
				pe.squad = -1
				pe.sup8 = fac
				op.pod = pid
				op.ph = "secure"
				op.tp = w.tick
				w.emit("Supply8PodLanded", {"fac": fac, "owner": int(Rf.owner), "pod": pid, "pos": spot})
		"secure":
			var go := _alive(w, op.go)
			var inpos := 0
			for uid in go:
				if Vector2(w.entities[uid].pos).distance_to(Vector2(op.post.get(str(uid), spot))) <= 1.6:
					inpos += 1
			var lead := w.tick - int(op.tp) >= ticks(float(R().get("go_lead_s", 4.0)))
			var need := ceili(float(R().get("secure_frac", 0.7)) * float(go.size()))
			if lead and (inpos >= need or w.tick - int(op.tp) > ticks(float(R().get("secure_max_s", 30.0)))):
				var car := _unpark(w, Rf)
				if car.is_empty():
					_end(w, st, Rf, false, "no carrier")
					return
				Rf.hp0 = float(car.hp)
				op.ph = "out"
				op.tp = w.tick
				op.inpos = inpos
				var g0 := _free_pt(w, spot - Vector2(op.out) * 0.9, team, "vehicle")
				# FACFLOW8C (13.9c-50): FacDrive7 drives it out through the airlock (hardened gate), then hands it to Movement
				if not (FD().registered() and FD().order(w, car, fac, "x", "fac", [g0.x, g0.y])):
					_move(w, car, g0)
				w.emit("Supply8CarrierOut", {"fac": fac, "owner": int(Rf.owner), "carrier": int(Rf.car), "in_position": inpos, "go": go.size()})
		"out":
			var car: Dictionary = w.entities[int(Rf.car)]
			var cgoal := _free_pt(w, spot - Vector2(op.out) * 0.9, team, "vehicle")
			if not _fd_busy(w, car):
				_move_if(w, car, cgoal, 0.4)
			for i in eng.size():
				var e: Dictionary = w.entities[int(eng[i])]
				_move_if(w, e, _free_pt(w, _ring(spot, Vector2(op.out), i, maxi(eng.size(), 1), 0.8), team), 0.3)
			if Vector2(car.pos).distance_to(spot) <= lr and _near(w, eng, spot, lr) >= mini(2, eng.size()) and not eng.is_empty():
				MV().stop_path(car)
				car.order = {"type": "idle"}
				op.ph = "load"
				op.tp = w.tick
				w.emit("Supply8Loading", {"fac": fac, "owner": int(Rf.owner), "pod": int(op.pod), "carrier": int(Rf.car), "engineers": eng.duplicate()})
		"load":
			if _near(w, eng, spot, lr + 0.4) >= mini(2, maxi(eng.size(), 1)) and not eng.is_empty():
				op.lt = int(op.lt) + ev
			if int(op.lt) >= ticks(float(R().get("load_s", 8.0))):
				w.entities.erase(int(op.pod))
				_invalidate(w)
				w.emit("Supply8PodLoaded", {"fac": fac, "owner": int(Rf.owner), "pod": int(op.pod), "carrier": int(Rf.car)})
				op.pod = -1
				op.loaded = true
				op.ph = "return"
				op.tp = w.tick
				var car: Dictionary = w.entities[int(Rf.car)]
				car.sup8_load = true
				if not _fd_home(w, Rf, car):
					_move(w, car, Vector2(Rf.door))
				for i in eng.size():
					_move(w, w.entities[int(eng[i])], _free_pt(w, Vector2(Rf.door) + Vector2(0.6 * float(i % 2) - 0.3, 0.6 * float(i / 2) + 0.6), team))
		"return":
			var car: Dictionary = w.entities[int(Rf.car)]
			if not _fd_busy(w, car) and not _fd_home(w, Rf, car):
				_move_if(w, car, Vector2(Rf.door), 0.3)
			if w.tick - int(op.esc) >= ticks(float(R().get("escort_every_s", 2.0))):
				op.esc = w.tick
				_escort(w, Rf, op, car, team)
			if Vector2(car.pos).distance_to(Vector2(Rf.door)) <= 0.8:
				_deliver(w, st, Rf)
				_end(w, st, Rf, true, "delivered")


## GO teams escort the carrier home: their stand-to posts follow it (a ring of escort_r around the carrier, the
## outward half behind it) until it is back inside the compound.
static func _escort(w: SimWorld, Rf: Dictionary, op: Dictionary, car: Dictionary, team: int) -> void:
	var S = S7().state(w)
	if S == null:
		return
	var F: Dictionary = CF().fac(w, int(Rf.fac))
	var inside: bool = not F.is_empty() and CF().compound_rect(F).grow(-1.0).has_point(Vector2(car.pos))
	var go := _alive(w, op.go)
	var r := float(R().get("escort_r", 2.0))
	var dirv: Vector2 = (CF().compound_rect(F).get_center() - Vector2(car.pos)).normalized() if not F.is_empty() else Vector2.UP
	for i in go.size():
		var j: Dictionary = S.jobs.get(str(go[i]), {})
		if String(j.get("k", "")) != "standto" or String(j.get("j", "")) != "sup8:%d" % int(op.n):
			continue
		if inside:
			j.pos = _free_pt(w, Vector2(Rf.door) + Vector2(float(i % 4) * 0.5 - 0.75, float(i / 4) * 0.5 + 0.8), team)
		else:
			j.pos = _free_pt(w, _ring(Vector2(car.pos), -dirv, i, go.size(), r), team)


static func _deliver(w: SimWorld, st: Dictionary, Rf: Dictionary) -> void:
	var fid := int(Rf.owner)
	var ld: Dictionary = R().get("load", {"ammo": 600, "fuel": 400})
	var stock: Dictionary = w.factions[fid].stock
	for res in ["ammo", "fuel"]:
		stock[res] = int(stock.get(res, 0)) + int(ld.get(res, 0))
	var sd := _side(w, fid)
	var am := int(ld.get("ammo", 0))
	var tot := 0
	for k in MIX_KEYS:
		tot += int(sd.mix.get(k, 0))
	var given := 0
	for i in MIX_KEYS.size():
		var k: String = MIX_KEYS[i]
		var n := am - given if i == MIX_KEYS.size() - 1 else (am * int(sd.mix.get(k, 0))) / maxi(tot, 1)
		sd.typed[k] = int(sd.typed.get(k, 0)) + n
		given += n
	Rf.n_ok = int(Rf.n_ok) + 1
	var car = w.entities.get(int(Rf.car))
	if car != null:
		car.erase("sup8_load")
	w.emit("Supply8Delivered", {"fac": int(Rf.fac), "owner": fid, "ammo": int(ld.get("ammo", 0)), "fuel": int(ld.get("fuel", 0)),
		"mix": (sd.mix as Dictionary).duplicate(), "op": int(Rf.op.n)})
	_park(w, Rf)


## Ends the running op: every held unit goes back to automatic duty / the watch, the cooldown starts; a failed op
## leaves the drop owed (next order free) and sends the carrier home.
static func _end(w: SimWorld, st: Dictionary, Rf: Dictionary, ok: bool, why: String) -> void:
	var op: Dictionary = Rf.op
	var fac := int(Rf.fac)
	var S = S7().state(w)
	for id in op.go:
		st.m.erase(str(id))
		if S != null and w.entities.has(int(id)):
			var j: Dictionary = S.jobs.get(str(id), {})
			if String(j.get("j", "")) == "sup8:%d" % int(op.n):
				S.jobs[str(id)] = {"k": "auto", "fac": fac}
	for id in op.eng:
		st.m.erase(str(id))
		var e = w.entities.get(int(id))
		if e != null:
			MV().stop_path(e)
			e.order = {"type": "idle"}
			S7().set_worker_job(w, int(id), {})
	if not ok:
		Rf.n_fail = int(Rf.n_fail) + 1
		Rf.retry = true
		if int(op.pod) >= 0 and w.entities.has(int(op.pod)):
			w.entities.erase(int(op.pod))   # the pod is scuttled; the drop is owed (retry free)
			_invalidate(w)
		var car = w.entities.get(int(Rf.car))
		if car != null:
			car.erase("sup8_load")
	Rf.cd = w.tick + ticks(float(R().get("cooldown_s", 90.0)))
	Rf.last = "delivered" if ok else why
	Rf.op = {}
	w.emit("Supply8OpEnded", {"fac": fac, "owner": int(Rf.owner), "ok": ok, "why": why, "op": int(op.n)})


# ================================================================ card read-out
## Everything the magazine card shows for facility fac (pure read).
static func summary(w: SimWorld, fac: int) -> Dictionary:
	var Rf := rec(w, fac)
	if Rf.is_empty():
		return {}
	var fid := int(Rf.owner)
	var st = state(w)
	var sd: Dictionary = st.sides.get(str(fid), {})
	var stock: Dictionary = w.factions[fid].stock if w.factions.has(fid) else {}
	var op: Dictionary = Rf.op
	var car = w.entities.get(int(Rf.car))
	var cs := "IN GARAGE"
	if int(Rf.reb) >= 0:
		cs = "REBUILDING %ds" % int(ceil(float(maxi(int(Rf.reb) - w.tick, 0)) / float(SimWorld.TICK_RATE)))
	elif car != null:
		cs = "OUT"
	var cd := maxi(int(Rf.cd) - w.tick, 0)
	var prog := ""
	match String(op.get("ph", "")):
		"drop":
			prog = "POD INBOUND %ds - GO teams moving out" % int(ceil(float(maxi(int(op.land) - w.tick, 0)) / float(SimWorld.TICK_RATE)))
		"secure":
			prog = "POD DOWN - GO teams securing"
		"out":
			prog = "CARRIER + ENGINEERS TO THE POD"
		"load":
			prog = "LOADING %d%%" % mini(100, int(100.0 * float(op.lt) / float(ticks(float(R().get("load_s", 8.0))))))
		"return":
			prog = "RETURNING UNDER ESCORT"
	var cstored: Dictionary = Rf.stored
	var cd_e = car if car != null else (cstored if not cstored.is_empty() else null)
	return {"fac": fac, "owner": fid, "mag": int(Rf.mag), "gar": int(Rf.gar), "ammo": int(stock.get("ammo", 0)), "fuel": int(stock.get("fuel", 0)),
		"low": (sd.get("low", {}) as Dictionary).duplicate(), "low_thr": (R().get("low", {}) as Dictionary).duplicate(),
		"first": String(sd.get("first", "")), "mix": (sd.get("mix", {}) as Dictionary).duplicate(), "typed": (sd.get("typed", {}) as Dictionary).duplicate(),
		"ph": String(op.get("ph", "")), "prog": prog, "cd_s": int(ceil(float(cd) / float(SimWorld.TICK_RATE))), "retry": bool(Rf.retry),
		"reason": order_reason(w, fid, fac), "n_ok": int(Rf.n_ok), "n_fail": int(Rf.n_fail), "last": String(Rf.last), "car": cs,
		"car_hp": float(cd_e.hp) if cd_e != null else 0.0, "car_max": float(cd_e.max_hp) if cd_e != null else 0.0,
		"sh": float(Rf.sh), "sh_max": float(R().get("shield", {}).get("hp", 260.0)), "cost": int(R().get("cost", {}).get("credits", 900)),
		"go": _alive(w, op.get("go", [])).size(), "eng": _alive(w, op.get("eng", [])).size(), "spot": op.get("spot", Vector2(-1, -1)), "pod": int(op.get("pod", -1))}
