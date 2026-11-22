extends RefCounted
## G7.1 FIRES71 B6: the CONDUCTOR command gunship (docs/G71_SCOPE.md B6; roster 5A Q19: the radial "gunship" entry and
## the FO team "call the Conductor" both land here through Fires71). Last Protocol only. Numbers PROVISIONAL
## (rules.g71_conductor in content/g71/rules_g71_fires.json).
## Flight goes through Air's public orders only: an orbit is an `air_patrol` polygon (n points on a circle, order by
## side) for the gunship + its wingmen (they fly the same loop spread out = the rotating formation); going home is
## Air `land_at` on the Conductor's own pad (registered in Pads71 as kind "conductor71" at the first orbit).
## While on station (gunship within radius + slack of the orbit centre), every PULSE ticks:
##   side cannon (orbit fire)   : the enemy ground target nearest the centre inside the orbit, Strikes._impact
##   missile cells              : the heaviest non-infantry target near the orbit, limited cells (hot-pit refills)
##   laser CIWS                 : up to ciws_n enemy drones within ciws_r of the gunship per pulse are burned down
##   wingman sacrifice-block    : a drone inside block_r that the CIWS could not take is blocked by the nearest free
##                                wingman (drone destroyed, wingman takes block_dmg)
##   target hand-off            : free wingmen get a target each (non-infantry first), peel off, strike after a flight
##                                time from their distance and speed, then rejoin
## The chin rotary railgun is the gunship def's own weapon (Combat fires it). Flares: decoy(w, target_id) -> bool,
## for the AA hit path (Combat, ARMY71) to ask before a missile hits the gunship.
## Commands: conductor_orbit {issuer, at [x, y], radius?, side? (1 = ccw, -1 = cw), alt?}, conductor_home {issuer},
## conductor_kamikaze {issuer, unit_id (a wingman), target_id}.
## State sys_state.conductor71 = {ver, o: {"<fid>": {g, wing [ids], cx, cy, r, side, alt, on, pid, hx, hy, pad,
## cells, flares, cd {c, m, l, f, h}, peel {"<wid>": {tgt, hit}}, svc}}} (saved + hashed with sys_state).

const KEY := "conductor71"
const VER := 1
const COMMANDS := ["conductor_orbit", "conductor_home", "conductor_kamikaze"]
const Air = preload("res://sim/systems/air.gd")
const Pads71 = preload("res://sim/systems/pads71.gd")
const Strikes = preload("res://sim/systems/strikes.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Counterdrone = preload("res://sim/systems/counterdrone.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")


static func R() -> Dictionary:
	return Content.rules().get("g71_conductor", {})


static func _rf(k: String, d: float) -> float:
	return float(R().get(k, d))


static func _t(secs: float) -> int:
	return maxi(1, int(round(secs * float(SimWorld.TICK_RATE))))


static func lp_on(w: SimWorld) -> bool:
	return SimWorld.LastProtocol.active(w)


static func _role(e) -> String:
	if e == null or e.kind != "unit":
		return ""
	return String(Content.unit(String(e.def)).get("conductor71", {}).get("role", ""))


## Lowest-id live gunship of fid (-1 = none) and its wingmen (ids ascending, up to wing_max).
static func gunship(w: SimWorld, fid: int) -> int:
	var best := -1
	for u in SimIndex.units_by_owner(w).get(fid, []):
		if _role(u) == "gunship" and (best < 0 or int(u.id) < best):
			best = int(u.id)
	return best


static func wingmen(w: SimWorld, fid: int) -> Array:
	var out := []
	for u in SimIndex.units_by_owner(w).get(fid, []):
		if _role(u) == "wingman":
			out.append(int(u.id))
	out.sort()
	return out.slice(0, int(R().get("wing_max", 4)))


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"ver": VER, "o": {}}
	return w.sys_state[KEY]


static func record(w: SimWorld, fid: int) -> Dictionary:
	var st = w.sys_state.get(KEY)
	return st.o.get(str(fid), {}) if st != null else {}


# ---------------------------------------------------------------- API used by Fires71 (radial gunship / fo_call)
static func orbit_reason(w: SimWorld, fid: int, p: Vector2) -> String:
	if not lp_on(w):
		return "Only in Last Protocol."
	if gunship(w, fid) < 0:
		return "The Conductor gunship is not available."
	if not w.in_bounds(w.cell_of(p)):
		return "The orbit centre is outside the map."
	return ""


static func orbit_at(w: SimWorld, fid: int, p: Vector2, radius: float = -1.0, side: int = 0, alt: float = -1.0) -> void:
	if orbit_reason(w, fid, p) != "":
		return
	var g := gunship(w, fid)
	var o := record(w, fid)
	if o.is_empty():
		var ge: Dictionary = w.entities[g]
		o = {"g": g, "wing": [], "cx": 0.0, "cy": 0.0, "r": 0.0, "side": 1, "alt": 0.0, "on": false, "pid": -1,
			"hx": float(ge.pos.x), "hy": float(ge.pos.y), "pad": "cond71:%d" % fid,
			"cells": int(R().get("cells", 8)), "flares": int(R().get("flares", 6)),
			"cd": {"c": 0, "m": 0, "l": 0, "f": 0, "h": 0}, "peel": {}, "svc": -1}
		_st(w).o[str(fid)] = o
		Pads71.register(w, String(o.pad), "conductor71", fid, Vector2(o.hx, o.hy), 2.0, -1, 0.0, 1)
		Pads71.set_home(w, g, String(o.pad))
	var r := clampf(radius if radius > 0.0 else _rf("radius", 9.0), _rf("radius_min", 5.0), _rf("radius_max", 18.0))
	o.g = g
	o.wing = wingmen(w, fid)
	o.cx = snappedf(p.x, 1.0 / 1024.0)
	o.cy = snappedf(p.y, 1.0 / 1024.0)
	o.r = r
	o.side = -1 if side < 0 else 1
	o.alt = alt if alt > 0.0 else _rf("alt", 3.0)
	o.on = true
	o.svc = -1
	o.peel = {}
	var n := int(R().get("orbit_points", 8))
	var pts := []
	for i in n:
		var a := float(o.side) * TAU * float(i) / float(n)
		var q := Vector2(o.cx, o.cy) + Vector2(cos(a), sin(a)) * r
		var qc := w.cell_of(q)
		if not w.in_bounds(qc):
			q = Vector2(o.cx, o.cy) + Vector2(cos(a), sin(a)) * minf(r, 2.0)
		pts.append([snappedf(q.x, 1.0 / 64.0), snappedf(q.y, 1.0 / 64.0)])
	var ids: Array = [g] + (o.wing as Array)
	var cmd := {"type": "air_patrol", "issuer": fid, "unit_ids": ids, "points": pts, "min_on_station": ids.size()}
	if Air.validate_command(w, cmd) == "":
		Air.apply_command(w, cmd)
		o.pid = int(Air._st(w).get("pat_next71", 1)) - 1
	w.emit("ConductorOrbit", {"owner": fid, "gunship": g, "wing": (o.wing as Array).duplicate(), "pos": Vector2(o.cx, o.cy), "r": r, "side": int(o.side)})


## Flares / decoys: true = this AA missile aimed at the gunship is decoyed (one flare spent, cooldown).
static func decoy(w: SimWorld, target_id: int) -> bool:
	var st = w.sys_state.get(KEY)
	if st == null:
		return false
	var ks: Array = (st.o as Dictionary).keys()
	ks.sort()
	for k in ks:
		var o: Dictionary = st.o[k]
		if int(o.g) == target_id and int(o.flares) > 0 and w.tick >= int(o.cd.f):
			o.flares = int(o.flares) - 1
			o.cd.f = w.tick + _t(_rf("flare_cd_s", 4.0))
			w.emit("ConductorFlares", {"owner": int(k), "gunship": target_id, "left": int(o.flares)})
			return true
	return false


# ---------------------------------------------------------------- commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if not lp_on(w):
		return "Only in Last Protocol."
	var fid := int(cmd.get("issuer", -1))
	match String(cmd.get("type", "")):
		"conductor_orbit":
			var a = cmd.get("at")
			if not (a is Array and (a as Array).size() >= 2):
				return "Pick an orbit centre."
			return orbit_reason(w, fid, Vector2(float(a[0]), float(a[1])))
		"conductor_home":
			if record(w, fid).is_empty():
				return "The Conductor is not flying."
			return ""
		"conductor_kamikaze":
			var o := record(w, fid)
			if o.is_empty() or not (o.wing as Array).has(int(cmd.get("unit_id", -1))) or not w.entities.has(int(cmd.get("unit_id", -1))):
				return "Pick a Conductor wingman."
			var t = w.entities.get(int(cmd.get("target_id", -1)))
			if t == null or not w.is_enemy(fid, int(t.owner)):
				return "Pick an enemy target."
			return ""
	return "Unknown Conductor command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	if validate_command(w, cmd) != "":
		return
	var fid := int(cmd.issuer)
	match String(cmd.type):
		"conductor_orbit":
			orbit_at(w, fid, Vector2(float(cmd.at[0]), float(cmd.at[1])), float(cmd.get("radius", -1.0)), int(cmd.get("side", 0)), float(cmd.get("alt", -1.0)))
		"conductor_home":
			var o := record(w, fid)
			o.on = false
			o.peel = {}
			var ids := []
			for id in [int(o.g)] + (o.wing as Array):
				if w.entities.has(int(id)):
					ids.append(int(id))
			# One landing cell each (gunship on its pad cell, wingmen on the nearest free landing-ok cells around it,
			# rings scanned in a fixed order): one shared cell let the first wingman down block the gunship.
			var home := w.cell_of(Vector2(o.hx, o.hy))
			var used := {}
			for id in ids:
				var e: Dictionary = w.entities[int(id)]
				var d := Content.unit(String(e.def))
				var n := Air.lz_size(d)
				var cell := Vector2i(-1, -1)
				for r in 9:
					for dy in range(-r, r + 1):
						for dx in range(-r, r + 1):
							var q := home + Vector2i(dx, dy)
							if cell.x >= 0 or maxi(absi(dx), absi(dy)) != r or not Air.landing_ok(w, q, d, int(id)):
								continue
							var clear := true
							for u in used:   # landing squares of the craft already sent never overlap
								if maxi(absi(q.x - u.x), absi(q.y - u.y)) < maxi(n, int(used[u])):
									clear = false
							if clear:
								cell = q
					if cell.x >= 0:
						break
				if cell.x < 0:
					continue
				used[cell] = n
				var lc := {"type": "land_at", "issuer": fid, "unit_ids": [int(id)], "cell": [cell.x, cell.y]}
				if Air.validate_command(w, lc) == "":
					Air.apply_command(w, lc)
			w.emit("ConductorHome", {"owner": fid, "gunship": int(o.g)})
		"conductor_kamikaze":
			var o := record(w, fid)
			var wid := int(cmd.unit_id)
			var t: Dictionary = w.entities[int(cmd.target_id)]
			var at := Vector2(t.pos)
			var hits := Strikes._impact(w, fid, wid, at, {"weapon": "g71_wing_kamikaze", "damage": _rf("kamikaze_dmg", 260.0), "cls": "artillery", "splash": _rf("kamikaze_splash", 1.2)})
			if t.get("is_air", false) or Content.unit(String(t.get("def", ""))).get("is_air", false):
				Damage.apply_hit(w, w.entities[wid], t, {"weapon": "g71_wing_kamikaze", "damage": _rf("kamikaze_dmg", 260.0), "cls": "artillery", "splash": 0.0}, true)
			var we: Dictionary = w.entities[wid]
			Damage.apply_hit(w, we, we, {"weapon": "g71_wing_kamikaze", "damage": float(we.get("hp", 1)) * 20.0 + 1000.0, "cls": "artillery", "splash": 0.0}, true)
			(o.wing as Array).erase(wid)
			(o.peel as Dictionary).erase(str(wid))
			w.emit("WingmanKamikaze", {"owner": fid, "unit": wid, "target": int(cmd.target_id), "pos": at, "hits": hits})


# ---------------------------------------------------------------- tick
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get(KEY)
	if st == null or not lp_on(w):
		return
	var ks: Array = (st.o as Dictionary).keys()
	ks.sort()
	for k in ks:
		var o: Dictionary = st.o[k]
		var fid := int(k)
		_peel_step(w, fid, o)
		if (w.tick + int(o.g)) % int(R().get("pulse", 5)) != 0:
			continue
		var g = w.entities.get(int(o.g))
		if g == null:
			if bool(o.on):
				o.on = false
				w.emit("ConductorLost", {"owner": fid, "gunship": int(o.g)})
			continue
		var live := []
		for id in o.wing:
			if w.entities.has(int(id)):
				live.append(int(id))
		o.wing = live
		if not bool(o.on):
			_service(w, fid, o, g)
			continue
		var c := Vector2(o.cx, o.cy)
		_defend(w, fid, o, g)
		if Vector2(g.pos).distance_to(c) > float(o.r) + _rf("station_slack", 2.5):
			continue
		_cannon(w, fid, o, c)
		_missiles(w, fid, o, c)
		_handoff(w, fid, o, c)


static func _impact(w: SimWorld, fid: int, src: int, at: Vector2, wpn: String, dmg: float, spl: float) -> int:
	return Strikes._impact(w, fid, src, at, {"weapon": wpn, "damage": dmg, "cls": "artillery", "splash": spl})


static func _nearest(list: Array, c: Vector2, armoured_first: bool) -> Variant:
	var best = null
	var bk := []
	for t in list:
		var arm := 0 if (armoured_first and t.kind == "unit" and String(Content.unit(String(t.def)).get("armor", "")) != "infantry") else 1
		var key := [arm, c.distance_squared_to(Vector2(t.pos)), int(t.id)]
		if best == null or key < bk:
			best = t
			bk = key
	return best


static func _cannon(w: SimWorld, fid: int, o: Dictionary, c: Vector2) -> void:
	if w.tick < int(o.cd.c):
		return
	var t = _nearest(Strikes._ground_targets(w, fid, c, float(o.r)), c, false)
	if t == null:
		return
	o.cd.c = w.tick + _t(_rf("cannon_s", 2.0))
	var sc := _rf("cannon_scatter", 0.6)
	var at := Vector2(t.pos) + Vector2(w.rng.randf_range(-sc, sc), w.rng.randf_range(-sc, sc))
	var hits := _impact(w, fid, int(o.g), at, "g71_cond_cannon", _rf("cannon_dmg", 90.0), _rf("cannon_splash", 1.0))
	w.emit("ConductorCannon", {"owner": fid, "gunship": int(o.g), "pos": at, "target": int(t.id), "hits": hits})


static func _missiles(w: SimWorld, fid: int, o: Dictionary, c: Vector2) -> void:
	if w.tick < int(o.cd.m) or int(o.cells) <= 0:
		return
	var cand := []
	for t in Strikes._ground_targets(w, fid, c, float(o.r) + _rf("missile_reach", 4.0)):
		if t.kind == "building" or String(Content.unit(String(t.def)).get("armor", "")) != "infantry":
			cand.append(t)
	var t = _nearest(cand, c, true)
	if t == null:
		return
	o.cd.m = w.tick + _t(_rf("missile_s", 6.0))
	o.cells = int(o.cells) - 1
	var hits := _impact(w, fid, int(o.g), Vector2(t.pos), "g71_cond_missile", _rf("missile_dmg", 320.0), _rf("missile_splash", 0.8))
	w.emit("ConductorMissile", {"owner": fid, "gunship": int(o.g), "pos": Vector2(t.pos), "target": int(t.id), "hits": hits, "cells": int(o.cells)})


static func is_drone(w: SimWorld, e: Dictionary) -> bool:
	if e.kind != "unit":
		return false
	var d := Content.unit(String(e.def))
	return bool(d.get("launched_drone", false)) or String(d.get("aircraft", "")) == "micro" or Counterdrone.is_drone(w, e)


static func _defend(w: SimWorld, fid: int, o: Dictionary, g: Dictionary) -> void:
	var gp := Vector2(g.pos)
	var br := _rf("block_r", 2.5)
	var cr := _rf("ciws_r", 5.0)
	var drones := []
	var byo: Dictionary = SimIndex.units_by_owner(w)
	var owners: Array = byo.keys()
	owners.sort()
	for ow in owners:
		if not w.is_enemy(fid, int(ow)):
			continue
		for u in byo[ow]:
			if gp.distance_squared_to(Vector2(u.pos)) <= cr * cr and is_drone(w, u):
				drones.append(u)
	if drones.is_empty():
		return
	drones.sort_custom(func(a, b): return [gp.distance_squared_to(Vector2(a.pos)), int(a.id)] < [gp.distance_squared_to(Vector2(b.pos)), int(b.id)])
	var shots := int(R().get("ciws_n", 2)) if w.tick >= int(o.cd.l) else 0
	if shots > 0:
		o.cd.l = w.tick + _t(_rf("ciws_s", 1.0))
	for d in drones:
		if not w.entities.has(int(d.id)):
			continue
		if shots > 0:
			shots -= 1
			Damage.apply_hit(w, g, d, {"weapon": "g71_cond_ciws", "damage": _rf("ciws_dmg", 400.0), "cls": "laser", "splash": 0.0}, true)
			w.emit("ConductorCiws", {"owner": fid, "gunship": int(g.id), "drone": int(d.id), "pos": Vector2(d.pos)})
			continue
		if gp.distance_squared_to(Vector2(d.pos)) > br * br:
			continue
		var wb := -1
		var wd := INF
		for wid in o.wing:
			if (o.peel as Dictionary).has(str(wid)) or not w.entities.has(int(wid)):
				continue
			var dd := Vector2(w.entities[int(wid)].pos).distance_squared_to(Vector2(d.pos))
			if dd < wd:
				wd = dd
				wb = int(wid)
		if wb < 0:
			continue
		var we: Dictionary = w.entities[wb]
		var dp := Vector2(d.pos)
		Damage.apply_hit(w, we, d, {"weapon": "g71_wing_block", "damage": 2000.0, "cls": "artillery", "splash": 0.0}, true)
		Damage.apply_hit(w, d, we, {"weapon": "g71_wing_block", "damage": _rf("block_dmg", 160.0), "cls": "artillery", "splash": 0.0}, true)
		w.emit("WingmanBlock", {"owner": fid, "unit": wb, "drone": int(d.id), "pos": dp, "survived": w.entities.has(wb)})


static func _handoff(w: SimWorld, fid: int, o: Dictionary, c: Vector2) -> void:
	if w.tick < int(o.cd.h) or (o.wing as Array).is_empty():
		return
	o.cd.h = w.tick + _t(_rf("handoff_s", 3.0))
	var taken := {}
	for k in o.peel:
		taken[int(o.peel[k].tgt)] = true
	var pool := []
	for t in Strikes._ground_targets(w, fid, c, float(o.r)):
		if t.kind == "unit" and not taken.has(int(t.id)):
			pool.append(t)
	for wid in o.wing:
		if pool.is_empty():
			return
		if (o.peel as Dictionary).has(str(wid)):
			continue
		var we: Dictionary = w.entities[int(wid)]
		var t = _nearest(pool, Vector2(we.pos), true)
		pool.erase(t)
		var spd := maxf(float(Content.unit(String(we.def)).get("speed", 5.0)), 0.5)
		var fly := int(ceil(Vector2(we.pos).distance_to(Vector2(t.pos)) / spd * float(SimWorld.TICK_RATE)))
		o.peel[str(wid)] = {"tgt": int(t.id), "hit": w.tick + maxi(fly, 1)}
		w.emit("WingmanHandoff", {"owner": fid, "gunship": int(o.g), "unit": int(wid), "target": int(t.id), "hit": w.tick + maxi(fly, 1)})


static func _peel_step(w: SimWorld, fid: int, o: Dictionary) -> void:
	if (o.peel as Dictionary).is_empty():
		return
	var ks: Array = (o.peel as Dictionary).keys()
	ks.sort()
	for k in ks:
		var P: Dictionary = o.peel[k]
		if w.tick < int(P.hit):
			continue
		o.peel.erase(k)
		var t = w.entities.get(int(P.tgt))
		if t == null or not w.entities.has(int(k)):
			continue
		var hits := _impact(w, fid, int(k), Vector2(t.pos), "g71_wing_missile", _rf("wing_dmg", 120.0), _rf("wing_splash", 0.6))
		w.emit("WingmanStrike", {"owner": fid, "unit": int(k), "target": int(P.tgt), "pos": Vector2(t.pos), "hits": hits})


## Home: once the gunship is down within 2.5 tiles of its pad, hot-pit service (rules.g71_conductor.hot_pit_s,
## default = AIRFIX71's A2 hot_pit_s) refills missile cells and flares.
static func _service(w: SimWorld, fid: int, o: Dictionary, g: Dictionary) -> void:
	var full := int(o.cells) >= int(R().get("cells", 8)) and int(o.flares) >= int(R().get("flares", 6))
	if full or not Air.is_landed(g) or Vector2(g.pos).distance_to(Vector2(o.hx, o.hy)) > 2.5:
		return
	if int(o.svc) < 0:
		o.svc = w.tick + _t(_rf("hot_pit_s", 6.0))
		return
	if w.tick >= int(o.svc):
		o.cells = int(R().get("cells", 8))
		o.flares = int(R().get("flares", 6))
		o.svc = -1
		w.emit("ConductorServiced", {"owner": fid, "gunship": int(g.id)})


## Display data for the player's side (RenderSnap g71 provider via fires71_view.gd).
static func snap71(w: SimWorld, fid: int) -> Dictionary:
	var o := record(w, fid)
	if o.is_empty():
		return {}
	var peel := []
	for k in o.peel:
		peel.append([int(k), int(o.peel[k].tgt)])
	return {"on": bool(o.on), "c": [float(o.cx), float(o.cy)], "r": float(o.r), "side": int(o.side), "g": int(o.g),
		"wing": (o.wing as Array).duplicate(), "cells": int(o.cells), "flares": int(o.flares), "peel": peel}
