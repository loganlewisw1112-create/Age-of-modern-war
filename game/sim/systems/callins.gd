extends RefCounted
## Callins (owner: MECH6c). CONTRACTS_G6 §4, §9: JTAC designation, the aerostat, Drone Control Center
## bonuses and the AWACS air-picture share. Numbers: rules.g6_support.callins + the defs' own blocks.
##
## Commands:
##   designate {issuer, unit_id, target_id?, cell?}  a unit whose def has `designator {range}` (JTAC) marks a
##     visible enemy (or a ground cell) within range for designate_s. Friendly artillery / strike shooters get
##     accuracy x designate_acc_mult on it (designated_mult, via G6Hooks.accuracy_mult) and strikes on it a delay
##     x designate_delay_mult (strike_delay_mult, for Strikes / MECH6b). One designation per JTAC. It ends early
##     when the JTAC dies, the target dies or leaves range + designate_slack (checked every check_every ticks).
##   aerostat {issuer, unit_id, on}  a unit whose def has `deploy {sight_bonus, setup_s}` stops and rises for
##     setup_s, then adds sight_bonus to its fog reveal radius (sight_bonus, via G6Hooks.sight_bonus) while
##     deployed. Moving packs it at once (it is tethered).
## Drone CC: built buildings whose def has `drone_cc {radius, charge_cap_bonus, range_mult, restock_mult}` boost
##   friendly-team drone teams within radius: drone_cap_bonus / drone_range_mult / drone_restock_mult (AIRDEF6
##   wires them into g5_mech.gd, CR drone_cc_bonus). No CC on the map = neutral at once.
## AWACS: AIRDEF6 reveals enemy aircraft within the AWACS radius (airdef.gd _awacs_pass). The call-in hook on top:
##   every awacs_share_every ticks a side with an airborne AWACS (the data link) shares its WHOLE air picture
##   (Airdef.air_picture(w, fid): radar stations + AWACS) with its team through the G5 mark rule
##   (e.marked_until / e.marked_team, honoured by Fog.entity_visible). Without an airborne AWACS a radar picture
##   stays a minimap / SAM picture only. awacs_picture() is the radius-only helper (UI / AI).
## State (saved, hashed; created on the first designate/aerostat command, so G5 hashes stay equal):
##   w.sys_state.callins = {ver, aerostats: {uid: {owner, bonus}} (deployed only: the G6Hooks SIGHT mask key),
##     rising: {uid: ready_tick}, marks: {tid: {team, by, owner, until}}, cells: {"x,y": {team, by, owner, until, cell}}}
##   Entity: e.aerostat = "rising" | "up" (render hint; erased when packed).
## Runtime caches (never saved, rebuilt from state): w.cache.callins_scan {next, ccs, awacs} (candidate ids,
##   incremental by id), w.cache.callins_cc [tick, entries].
## Determinism: ascending ids, no randomness. Never preload g6_hooks.gd / movement.gd here (cycle: Movement ->
## G6Hooks -> Callins); Movement, HotState and Airdef are loaded lazily.

static var _mv = null
static var _hs = null
static var _ad = null
static var _fs_cache := {}     # def id -> bool (artillery / strike shooter)
static var _kind_cache := {}   # def id -> 0 none, 1 drone CC building, 2 AWACS unit


static func rules() -> Dictionary:
	return Content.rules().get("g6_support", {}).get("callins", {})


static func _rf(k: String, d: float) -> float:
	return float(rules().get(k, d))


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("callins"):
		w.sys_state["callins"] = {"ver": 1, "aerostats": {}, "rising": {}, "marks": {}, "cells": {}}
	return w.sys_state.callins


static func _team(w: SimWorld, fid: int) -> int:
	var f = w.factions.get(fid)
	return int(f.get("team", fid)) if f != null else fid


static func _cell_arg(c):
	if typeof(c) == TYPE_VECTOR2I:
		return c
	if typeof(c) == TYPE_VECTOR2:
		return Vector2i(floori(c.x), floori(c.y))
	if (typeof(c) == TYPE_ARRAY or typeof(c) == TYPE_PACKED_INT32_ARRAY or typeof(c) == TYPE_PACKED_FLOAT32_ARRAY) and c.size() >= 2:
		return Vector2i(int(c[0]), int(c[1]))
	return null


static func _sorted(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k


static func _movement():
	if _mv == null:
		_mv = load("res://sim/systems/movement.gd")
	return _mv


static func _hot():
	if _hs == null:
		_hs = load("res://sim/hot_state.gd")
	return _hs


static func _airdef():
	if _ad == null:
		_ad = load("res://sim/systems/airdef.gd")
	return _ad


## The G6Hooks activity mask is cached per tick; drop it when the SIGHT key changes mid-tick.
static func _invalidate_mask(w: SimWorld) -> void:
	w.cache.erase("g6_hooks_mask")


static func _def(def_id: String) -> Dictionary:
	var u: Dictionary = Content.table("units").get(def_id, {})
	return u if not u.is_empty() else Content.table("buildings").get(def_id, {})


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get("callins")
	if st != null:
		if not (st.rising as Dictionary).is_empty() or not (st.aerostats as Dictionary).is_empty():
			_tick_aerostats(w, st)
		if w.tick % maxi(int(rules().get("check_every", 10)), 1) == 0 \
				and (not (st.marks as Dictionary).is_empty() or not (st.cells as Dictionary).is_empty()):
			_tick_marks(w, st)
	var every := maxi(int(rules().get("awacs_share_every", 10)), 1)
	if w.tick % every == 0:
		_share_air(w, every)


static func _tick_aerostats(w: SimWorld, st: Dictionary) -> void:
	var changed := false
	for id in _sorted(st.rising):
		var e = w.entities.get(int(id))
		if e == null or bool(e.get("moving", false)):
			st.rising.erase(id)
			if e != null:
				e.erase("aerostat")
				w.emit("AerostatPacked", {"id": int(id), "owner": int(e.owner)})
			continue
		if w.tick >= int(st.rising[id]):
			st.rising.erase(id)
			var dep: Dictionary = _def(String(e.def)).get("deploy", {})
			st.aerostats[int(id)] = {"owner": int(e.owner), "bonus": float(dep.get("sight_bonus", 12.0))}
			e.aerostat = "up"
			changed = true
			w.emit("AerostatDeployed", {"id": int(id), "owner": int(e.owner), "bonus": float(dep.get("sight_bonus", 12.0))})
	for id in _sorted(st.aerostats):
		var e = w.entities.get(int(id))
		if e == null or bool(e.get("moving", false)):
			st.aerostats.erase(id)
			changed = true
			if e != null:
				e.erase("aerostat")
				w.emit("AerostatPacked", {"id": int(id), "owner": int(e.owner)})
	if changed:
		_invalidate_mask(w)


static func _tick_marks(w: SimWorld, st: Dictionary) -> void:
	var slack := _rf("designate_slack", 2.0)
	for key in _sorted(st.marks):
		var m: Dictionary = st.marks[key]
		var t = w.entities.get(int(key))
		var j = w.entities.get(int(m.by))
		var drop: bool = t == null or j == null or w.tick >= int(m.until)
		if not drop:
			var rng := float(_def(String(j.def)).get("designator", {}).get("range", 14.0))
			drop = Vector2(j.pos).distance_to(Vector2(t.pos)) > rng + slack
		if drop:
			st.marks.erase(key)
			w.emit("DesignationEnded", {"target": int(key), "by": int(m.by), "owner": int(m.owner)})
	for key in _sorted(st.cells):
		var m: Dictionary = st.cells[key]
		if w.tick >= int(m.until) or not w.entities.has(int(m.by)):
			st.cells.erase(key)
			w.emit("DesignationEnded", {"cell": m.cell, "by": int(m.by), "owner": int(m.owner)})


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -1))
	var e = w.entities.get(int(cmd.get("unit_id", -1)))
	if e == null or e.kind != "unit" or int(e.owner) != fid:
		return "Not your unit."
	var d := _def(String(e.def))
	match String(cmd.get("type", "")):
		"designate":
			if not d.has("designator"):
				return "Only a JTAC can designate targets."
			var rng := float(d.designator.get("range", 14.0))
			if int(cmd.get("target_id", -1)) >= 0:
				var t = w.entities.get(int(cmd.target_id))
				if t == null or not w.is_enemy(fid, int(t.owner)):
					return "Designate an enemy target."
				if not w.is_visible(fid, Vector2(t.pos)):
					return "Target not visible."
				if Vector2(e.pos).distance_to(Vector2(t.pos)) > rng:
					return "Target out of designator range."
				return ""
			if not cmd.has("cell"):
				return "No target given."
			var c = _cell_arg(cmd.cell)
			if c == null or not w.in_bounds(c):
				return "Outside the map."
			if Vector2(e.pos).distance_to(Vector2(c) + Vector2(0.5, 0.5)) > rng:
				return "Out of designator range."
			return ""
		"aerostat":
			if not d.has("deploy"):
				return "Only an aerostat can deploy."
			return ""
	return "Unknown command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var e: Dictionary = w.entities[int(cmd.unit_id)]
	var fid := int(e.owner)
	var st := _st(w)
	match String(cmd.type):
		"designate":
			_clear_by(st, int(e.id))
			var until := w.tick + roundi(_rf("designate_s", 30.0) * SimWorld.TICK_RATE)
			var rec := {"team": _team(w, fid), "by": int(e.id), "owner": fid, "until": until}
			if int(cmd.get("target_id", -1)) >= 0:
				st.marks[int(cmd.target_id)] = rec
				w.emit("TargetDesignated", {"id": int(e.id), "owner": fid, "target": int(cmd.target_id), "until": until})
			else:
				var c: Vector2i = _cell_arg(cmd.cell)
				rec.cell = [c.x, c.y]
				st.cells["%d,%d" % [c.x, c.y]] = rec
				w.emit("TargetDesignated", {"id": int(e.id), "owner": fid, "cell": [c.x, c.y], "until": until})
		"aerostat":
			_set_aerostat(w, st, e, bool(cmd.get("on", true)))


static func _clear_by(st: Dictionary, by: int) -> void:
	for key in _sorted(st.marks):
		if int(st.marks[key].by) == by:
			st.marks.erase(key)
	for key in _sorted(st.cells):
		if int(st.cells[key].by) == by:
			st.cells.erase(key)


static func _set_aerostat(w: SimWorld, st: Dictionary, e: Dictionary, on: bool) -> void:
	var id := int(e.id)
	if on:
		if st.aerostats.has(id) or st.rising.has(id):
			return
		_movement().stop_path(e)
		e.order = {"type": "idle"}
		_hot().touch(w, id)
		var dep: Dictionary = _def(String(e.def)).get("deploy", {})
		st.rising[id] = w.tick + maxi(roundi(float(dep.get("setup_s", 6.0)) * SimWorld.TICK_RATE), 1)
		e.aerostat = "rising"
		w.emit("AerostatRising", {"id": id, "owner": int(e.owner), "ready": int(st.rising[id])})
		return
	var was: bool = st.aerostats.has(id) or st.rising.has(id)
	st.aerostats.erase(id)
	st.rising.erase(id)
	e.erase("aerostat")
	if was:
		_invalidate_mask(w)
		w.emit("AerostatPacked", {"id": id, "owner": int(e.owner)})


# ================================================================ hook delegates (G6Hooks)
## Accuracy factor for src firing at t: x designate_acc_mult when src is an artillery / strike shooter and
## t (or its cell area) is designated by src's team. 1.0 at once while nothing is designated.
static func designated_mult(w: SimWorld, src: Dictionary, t: Dictionary) -> float:
	var st = w.sys_state.get("callins")
	if st == null or ((st.marks as Dictionary).is_empty() and (st.cells as Dictionary).is_empty()):
		return 1.0
	if not _fire_support(String(src.get("def", ""))):
		return 1.0
	return _rf("designate_acc_mult", 1.25) if _designated_for(w, st, _team(w, int(src.owner)), int(t.get("id", -1)), Vector2(t.pos)) else 1.0


## Extra fog reveal radius: the deployed aerostat's sight_bonus. 0.0 for everything else.
static func sight_bonus(w: SimWorld, e: Dictionary) -> float:
	var st = w.sys_state.get("callins")
	if st == null:
		return 0.0
	var a = st.aerostats.get(int(e.id))
	return float(a.bonus) if a != null else 0.0


## True while tid is designated (by any team).
static func is_designated(w: SimWorld, tid: int) -> bool:
	var st = w.sys_state.get("callins")
	return st != null and (st.marks as Dictionary).has(tid)


## For Strikes (MECH6b CR): delay factor for a strike by side fid on target_id (or at pos). 0.7 when designated.
static func strike_delay_mult(w: SimWorld, fid: int, target_id: int, pos: Vector2) -> float:
	var st = w.sys_state.get("callins")
	if st == null:
		return 1.0
	return _rf("designate_delay_mult", 0.7) if _designated_for(w, st, _team(w, fid), target_id, pos) else 1.0


## For Strikes (MECH6b CR): accuracy factor for a strike by side fid on target_id (or at pos).
static func strike_acc_mult(w: SimWorld, fid: int, target_id: int, pos: Vector2) -> float:
	var st = w.sys_state.get("callins")
	if st == null:
		return 1.0
	return _rf("designate_acc_mult", 1.25) if _designated_for(w, st, _team(w, fid), target_id, pos) else 1.0


static func _designated_for(w: SimWorld, st: Dictionary, team: int, tid: int, pos: Vector2) -> bool:
	var m = st.marks.get(tid) if tid >= 0 else null
	if m != null and int(m.team) == team:
		return true
	var cells: Dictionary = st.cells
	if cells.is_empty():
		return false
	var r := _rf("designate_cell_radius", 2.0)
	for c: Dictionary in cells.values():   # any-match: order does not matter (no per-shot sort)
		if int(c.team) == team and pos.distance_to(Vector2(float(c.cell[0]) + 0.5, float(c.cell[1]) + 0.5)) <= r:
			return true
	return false


## Artillery / strike shooters: indirect or artillery-class weapon, or a strike / payload def (cached per def).
static func _fire_support(def_id: String) -> bool:
	var v = _fs_cache.get(def_id)
	if v != null:
		return v
	var d := _def(def_id)
	var fs := d.has("strike") or d.has("payload")
	if not fs and d.has("weapon"):
		var wd: Dictionary = Content.weapon(String(d.weapon))
		fs = bool(wd.get("indirect", false)) or String(wd.get("class", "")) == "artillery"
	_fs_cache[def_id] = fs
	return fs


# ================================================================ Drone CC + AWACS candidates
## Candidate ids (drone CC buildings, AWACS units), found incrementally by id; a full pass once per world load.
static func _scan(w: SimWorld) -> Dictionary:
	var sc = w.cache.get("callins_scan")
	var nid := int(w.next_id)
	if sc == null:
		sc = {"next": nid, "ccs": [], "awacs": []}
		w.cache["callins_scan"] = sc
		var ids := w.entities.keys()
		ids.sort()
		for id in ids:
			_consider(sc, w.entities[id])
	elif nid > int(sc.next):
		for id in range(int(sc.next), nid):
			var e = w.entities.get(id)
			if e != null:
				_consider(sc, e)
		sc.next = nid
	return sc


static func _consider(sc: Dictionary, e: Dictionary) -> void:
	var def_id := String(e.get("def", ""))
	var k = _kind_cache.get(def_id)
	if k == null:
		var d := _def(def_id)
		k = 1 if d.has("drone_cc") else (2 if d.has("awacs") else 0)
		_kind_cache[def_id] = k
	if int(k) == 1 and e.kind == "building":
		sc.ccs.append(int(e.id))
	elif int(k) == 2 and e.kind == "unit":
		sc.awacs.append(int(e.id))


## This tick's built drone CCs: [[team, pos, r2, cap_bonus, range_mult, restock_mult], ...] (ascending id).
static func _cc_entries(w: SimWorld) -> Array:
	var c = w.cache.get("callins_cc")
	if c != null and int(c[0]) == w.tick and int(c[2]) == int(w.next_id):
		return c[1]
	var out := []
	for id in _scan(w).ccs:
		var b = w.entities.get(int(id))
		if b == null or not bool(b.get("built", true)):
			continue
		var dc: Dictionary = _def(String(b.def)).get("drone_cc", {})
		var r := float(dc.get("radius", 14.0))
		out.append([_team(w, int(b.owner)), Vector2(b.pos), r * r, int(dc.get("charge_cap_bonus", 1)),
			float(dc.get("range_mult", 1.5)), float(dc.get("restock_mult", 1.5))])
	w.cache["callins_cc"] = [w.tick, out, int(w.next_id)]
	return out


static func _cc_for(w: SimWorld, e: Dictionary) -> Array:
	var ents := _cc_entries(w)
	if ents.is_empty() or not bool(_def(String(e.get("def", ""))).get("drone_team", false)):
		return []
	var tm := _team(w, int(e.owner))
	var p: Vector2 = e.pos
	for en in ents:
		if int(en[0]) == tm and p.distance_squared_to(en[1]) <= float(en[2]):
			return en
	return []


## Drone team charge cap bonus from a friendly Drone CC in range (0 when none).
static func drone_cap_bonus(w: SimWorld, e: Dictionary) -> int:
	var en := _cc_for(w, e)
	return int(en[3]) if not en.is_empty() else 0


## Drone team launch range factor from a friendly Drone CC in range (1.0 when none).
static func drone_range_mult(w: SimWorld, e: Dictionary) -> float:
	var en := _cc_for(w, e)
	return float(en[4]) if not en.is_empty() else 1.0


## Drone team restock speed factor from a friendly Drone CC in range (1.0 when none).
static func drone_restock_mult(w: SimWorld, e: Dictionary) -> float:
	var en := _cc_for(w, e)
	return float(en[5]) if not en.is_empty() else 1.0


## Enemy aircraft ids within radius of side fid's airborne AWACS (the fallback picture, ascending).
static func awacs_picture(w: SimWorld, fid: int) -> Array:
	var out := {}
	var fl = w.sys_state.get("air")
	if fl == null:
		return []
	var air_ids := _sorted(fl.flights)
	for id in _scan(w).awacs:
		var a = w.entities.get(int(id))
		if a == null or int(a.owner) != fid or bool(a.get("air_landed", false)):
			continue
		var r := float(_def(String(a.def)).get("awacs", {}).get("radius", 24.0))
		var p: Vector2 = a.pos
		for tid in air_ids:
			var t = w.entities.get(int(tid))
			if t != null and w.is_enemy(fid, int(t.owner)) and p.distance_squared_to(Vector2(t.pos)) <= r * r:
				out[int(tid)] = true
	var k := out.keys()
	k.sort()
	return k


## Every `every` ticks: each side with an airborne AWACS shares its air picture with its team (G5 mark rule).
static func _share_air(w: SimWorld, every: int) -> void:
	var sc := _scan(w)
	if (sc.awacs as Array).is_empty():
		return
	var sides := {}
	for id in sc.awacs:
		var a = w.entities.get(int(id))
		if a != null and not bool(a.get("air_landed", false)):
			sides[int(a.owner)] = true
	if sides.is_empty():
		return
	var until := w.tick + every + 1
	for fid in _sorted(sides):
		var pic := {}
		for tid in _airdef().air_picture(w, int(fid)):
			pic[int(tid)] = true   # radar stations + AWACS (AIRDEF6 marks the AWACS radius itself)
		var tm := _team(w, int(fid))
		var n := 0
		for tid in _sorted(pic):
			var t = w.entities.get(int(tid))
			if t == null or not w.is_enemy(int(fid), int(t.owner)):
				continue
			t.marked_until = maxi(int(t.get("marked_until", 0)), until)
			t.marked_team = tm
			n += 1
		if n > 0:
			w.emit("AirPictureShared", {"owner": int(fid), "team": tm, "n": n, "until": until})
