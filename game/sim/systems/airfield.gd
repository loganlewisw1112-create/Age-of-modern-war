extends RefCounted
## Airfield (owner: AIRSYS). CONTRACTS_G5 sections 3.4, 3.5, 4, 5, 6, 7.
## Commands: build_hangar, upgrade_hangar, upgrade_airfield, assign_engineers.
## Fields are buildings whose def has `air_field` in FIELD_KINDS (airfield | airstrip | rail |
## forward_strip | helipad | forward_helipad). Hangars / drone bays (`air_field: "hangar"`) are
## separate building entities bought into a field's slots with build_hangar.
## State (saved, hashed): w.sys_state.airfield = {fields: {bid: {kind, owner, strips: [{open, crater_t,
##   busy_id}], hangars: [{bid, class, level, occupant}], pads: [{occupant, landed}], engineers: [ids]}}, ver}.
##   occupant = home aircraft id (-1 free); pads[i].landed = helicopter currently on that pad.
## G5 entity fields (AIRSYS, saved): building.extra_strips (0..3; rail: extra_rails mirrors it),
##   building.level (0..3) and building.class (light|heavy|bay) on hangars, building.air_parent (hangar ->
##   field id), building.air_build (seconds of hangar construction left), building.air_upg ({kind, t});
##   unit.air_assign (engineer -> assigned field/hangar id).
## Created lazily: a world without air buildings never gets sys_state.airfield (G4 hashes unchanged).
## This file never preloads air.gd / combat.gd / damage.gd (they preload this one).

const Movement = preload("res://sim/systems/movement.gd")
const Construction = preload("res://sim/systems/construction.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const HotState = preload("res://sim/hot_state.gd")  # core.hot_writer_rule

const FIELD_KINDS := ["airfield", "airstrip", "rail", "forward_strip", "helipad", "forward_helipad"]
const STRIP_KINDS := ["airfield", "airstrip", "rail", "forward_strip"]
const HANGAR_FIELDS := ["airfield", "airstrip", "rail"]
const ENGINEER_DEFS := ["a_airfield_engineers", "b_airfield_engineers", "m_maint_swarm"]
const AXES := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]


static func R() -> Dictionary:
	return Content.rules().get("g5_air", {})


static func rf(key: String, dflt: float) -> float:
	return float(R().get(key, dflt))


static func kind_of(def_id: String) -> String:
	return String(Content.building(def_id).get("air_field", ""))


# ================================================================ state
static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("airfield"):
		w.sys_state["airfield"] = {"fields": {}, "ver": 1}
	return w.sys_state.airfield


static func fields(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get("airfield")
	return s.fields if s != null else {}


static func field(w: SimWorld, bid: int) -> Dictionary:
	return fields(w).get(bid, {})


static func _sorted(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k


## Field id owning building bid (a field itself, or a hangar's parent); -1 if none.
static func field_of(w: SimWorld, bid: int) -> int:
	if fields(w).has(bid):
		return bid
	var b = w.entities.get(bid)
	if b != null and b.has("air_parent") and fields(w).has(int(b.air_parent)):
		return int(b.air_parent)
	return -1


static func usable(w: SimWorld, fid_bid: int) -> bool:
	var b = w.entities.get(fid_bid)
	return b != null and b.kind == "building" and bool(b.built) and fields(w).has(fid_bid)


static func open_strips(w: SimWorld, bid: int) -> int:
	var n := 0
	for s in field(w, bid).get("strips", []):
		if bool(s.open):
			n += 1
	return n


## World-space ends [start, end] of strip k of field bid (virtual strips beside the apron building).
static func strip_points(w: SimWorld, bid: int, k: int) -> Array:
	var b = w.entities.get(bid)
	if b == null:
		return [Vector2.ZERO, Vector2.ZERO]
	var d := Content.building(String(b.def))
	var f := int(b.get("facing_i", 0)) % 4
	var axis: Vector2 = AXES[f]
	var perp := Vector2(-axis.y, axis.x)
	var start: Vector2 = Vector2(b.pos) + perp * (float(b.size) * 0.5 + 1.5 + 4.0 * float(k)) - axis * float(b.size) * 0.5
	return [start, start + axis * float(d.get("strip_len", 10))]


# ================================================================ registration
static func _register(w: SimWorld, b: Dictionary) -> void:
	var kind := kind_of(String(b.def))
	var bid := int(b.id)
	if FIELD_KINDS.has(kind):
		var flds: Dictionary = _st(w).fields
		if flds.has(bid):
			return
		var d := Content.building(String(b.def))
		var strips := []
		if STRIP_KINDS.has(kind):
			for i in int(d.get("strips", 1)) + int(b.get("extra_strips", 0)):
				strips.append({"open": true, "crater_t": 0.0, "busy_id": -1})
		var pads := []
		for i in int(d.get("pad_slots", 0)):
			pads.append({"occupant": -1, "landed": -1})
		flds[bid] = {"kind": kind, "owner": int(b.owner), "strips": strips, "hangars": [], "pads": pads, "engineers": []}
		if not b.has("extra_strips") and STRIP_KINDS.has(kind):
			b.extra_strips = 0
	elif kind == "hangar" and not b.has("air_parent"):
		var best := -1
		var bd := 12.0
		for fb in _sorted(fields(w)):
			var fe = w.entities.get(int(fb))
			var fr: Dictionary = fields(w)[fb]
			if fe == null or int(fe.owner) != int(b.owner) or not HANGAR_FIELDS.has(String(fr.kind)):
				continue
			if not _class_ok(w, int(fb), String(Content.building(String(b.def)).get("hangar_class", "light"))):
				continue
			if (fr.hangars as Array).size() >= slot_cap(w, int(fb)):
				continue
			var dd: float = Vector2(fe.pos).distance_to(b.pos)
			if dd < bd:
				bd = dd
				best = int(fb)
		if best >= 0:
			_attach_hangar(w, best, b)


static func _attach_hangar(w: SimWorld, fbid: int, h: Dictionary) -> void:
	var cls := String(Content.building(String(h.def)).get("hangar_class", "light"))
	h.air_parent = fbid
	h["class"] = String(h.get("class", cls))
	h.level = int(h.get("level", 0))
	(field(w, fbid).hangars as Array).append({"bid": int(h.id), "class": String(h["class"]), "level": int(h.level), "occupant": -1})


## Scans ids created since the last call (cheap: only new ids). Runtime cursor in w.cache.
static func scan_new(w: SimWorld) -> void:
	var from := int(w.cache.get("af_next", 1))
	if from >= w.next_id:
		return
	for id in range(from, w.next_id):
		var b = w.entities.get(id)
		if b != null and b.kind == "building" and kind_of(String(b.def)) != "":
			_register(w, b)
	w.cache["af_next"] = w.next_id


## Hangar slots of a field: base + per extra strip.
static func slot_cap(w: SimWorld, bid: int) -> int:
	var b = w.entities.get(bid)
	if b == null:
		return 0
	var d := Content.building(String(b.def))
	return int(d.get("slots_base", 0)) + int(d.get("slots_per_strip", 0)) * int(b.get("extra_strips", 0))


static func _class_ok(w: SimWorld, fbid: int, cls: String) -> bool:
	var b = w.entities.get(fbid)
	if b == null:
		return false
	var d := Content.building(String(b.def))
	if String(d.get("hangar_light", "")) == "m_drone_bay":
		return cls == "bay" or cls == "light" or cls == "heavy"
	if cls == "bay":
		return false
	return cls == "light" or not bool(d.get("light_only", false))


static func is_engineer(e) -> bool:
	if e == null or e.kind != "unit":
		return false
	return ENGINEER_DEFS.has(String(e.def)) or bool(Content.unit(String(e.def)).get("airfield_engineer", false))


## Engineers assigned to field bid that are still on the job and within range of it.
static func engineers_at(w: SimWorld, bid: int) -> Array:
	var out := []
	var fr := field(w, bid)
	var b = w.entities.get(bid)
	if fr.is_empty() or b == null:
		return out
	var rng := rf("engineer_range", 10.0)
	for raw in fr.engineers:
		var e = w.entities.get(int(raw))
		if e != null and Vector2(e.pos).distance_to(b.pos) <= rng + float(b.size) * 0.5:
			out.append(e)
	return out


# ================================================================ slots, gating, homes
## Free home slots of building bid: {"light", "heavy", "pad", "bay"} (a hangar id counts itself only).
static func free_slots(w: SimWorld, bid: int) -> Dictionary:
	var out := {"light": 0, "heavy": 0, "pad": 0, "bay": 0}
	var fb := field_of(w, bid)
	if fb < 0:
		return out
	var fr := field(w, fb)
	for h in fr.hangars:
		if bid != fb and int(h.bid) != bid:
			continue
		var he = w.entities.get(int(h.bid))
		if int(h.occupant) < 0 and he != null and bool(he.built):
			out[String(h["class"])] = int(out.get(String(h["class"]), 0)) + 1
	var fe = w.entities.get(fb)
	if bid == fb and fe != null and bool(fe.built) and bool(Content.building(String(fe.def)).get("home_ok", true)):
		for p in fr.pads:
			if int(p.occupant) < 0:
				out.pad = int(out.pad) + 1
	return out


static func _faction_free(w: SimWorld, fid: int) -> Dictionary:
	var out := {"light": 0, "heavy": 0, "pad": 0, "bay": 0}
	for fb in _sorted(fields(w)):
		if int(fields(w)[fb].owner) != fid or not w.entities.has(int(fb)):
			continue
		var s := free_slots(w, int(fb))
		for k in out:
			out[k] = int(out[k]) + int(s[k])
	return out


static func _hangar_class_of_item(item: String) -> String:
	var sp: Array = Content.production(item).get("spawns", [])
	if sp.is_empty():
		return ""
	return String(Content.unit(String(sp[0])).get("hangar", ""))


## Production gate (production.gd validate). "" = ok, else no_free_hangar | no_free_pad | no_air_tower.
## Counts aircraft already queued anywhere in fid's buildings as reserved slots.
static func can_produce(w: SimWorld, fid: int, def_id: String) -> String:
	var hc := _hangar_class_of_item(def_id)
	if hc == "":
		return ""
	var free := _faction_free(w, fid)
	var q := {"light": 0, "heavy": 0, "pad": 0, "bay": 0}
	for b in w.buildings_of(fid):
		for it in b.get("queue", []):
			var c := _hangar_class_of_item(String(it.item))
			if q.has(c):
				q[c] = int(q[c]) + 1
	match hc:
		"pad":
			if int(free.pad) - int(q.pad) <= 0:
				return "no_free_pad"
		"bay":
			if int(free.bay) + int(free.light) + int(free.heavy) - int(q.bay) <= 0:
				return "no_free_hangar"
		"heavy":
			if int(free.heavy) - int(q.heavy) <= 0:
				return "no_free_hangar"
		_:
			if int(free.light) + int(free.heavy) - int(q.light) - int(q.heavy) <= 0 or int(free.heavy) - int(q.heavy) < 0:
				return "no_free_hangar"
	var sp: Array = Content.production(def_id).get("spawns", [])
	if String(Content.unit(String(sp[0])).get("move_class", "")) == "air_high" and not _tower_ok(w, fid):
		return "no_air_tower"
	return ""


## An air_high-producing faction needs a built *_air_tower within tower_range of a built field.
static func _tower_ok(w: SimWorld, fid: int) -> bool:
	var rng := rf("tower_range", 20.0)
	for fb in _sorted(fields(w)):
		var fe = w.entities.get(int(fb))
		if fe == null or int(fe.owner) != fid or not bool(fe.built) or not HANGAR_FIELDS.has(String(fields(w)[fb].kind)):
			continue
		if String(Content.building(String(fe.def)).get("hangar_light", "")) == "m_drone_bay":
			return true   # Machine rails need no tower
		for t in w.buildings_of(fid):
			if kind_of(String(t.def)) == "tower" and bool(t.built) and Vector2(t.pos).distance_to(fe.pos) <= rng:
				return true
	return false


## Binds aircraft e to the nearest free home slot of its class within max_d of near (bid > 0: only that
## building). Returns the home building id (hangar, or pad field) or -1. Sets e.air_home / e.air_slot.
static func bind_home(w: SimWorld, e: Dictionary, near: Vector2, max_d: float, only_bid: int = -1) -> int:
	var hc := String(Content.unit(String(e.def)).get("hangar", ""))
	if hc == "":
		return -1
	var best := -1
	var best_slot := -1
	var bd := max_d
	var pass_classes := [hc]
	if hc == "light":
		pass_classes = ["light", "heavy"]
	elif hc == "bay":
		pass_classes = ["bay", "light", "heavy"]
	for cls in pass_classes:
		for fb in _sorted(fields(w)):
			var fr: Dictionary = fields(w)[fb]
			if int(fr.owner) != int(e.owner) or not w.entities.has(int(fb)):
				continue
			if hc == "pad":
				var fe = w.entities.get(int(fb))
				if only_bid >= 0 and int(fb) != only_bid:
					continue
				if not bool(fe.built) or not bool(Content.building(String(fe.def)).get("home_ok", true)):
					continue
				for i in (fr.pads as Array).size():
					var dd: float = Vector2(fe.pos).distance_to(near)
					if int(fr.pads[i].occupant) < 0 and dd < bd:
						bd = dd
						best = int(fb)
						best_slot = i
			else:
				for i in (fr.hangars as Array).size():
					var h: Dictionary = fr.hangars[i]
					var he = w.entities.get(int(h.bid))
					if he == null or not bool(he.built) or int(h.occupant) >= 0 or String(h["class"]) != cls:
						continue
					if only_bid >= 0 and int(h.bid) != only_bid and int(fb) != only_bid:
						continue
					var dh: float = Vector2(he.pos).distance_to(near)
					if dh < bd:
						bd = dh
						best = int(h.bid)
						best_slot = i
		if best >= 0:
			break
	if best < 0:
		return -1
	var fbid := field_of(w, best)
	if hc == "pad":
		field(w, fbid).pads[best_slot].occupant = int(e.id)
	else:
		field(w, fbid).hangars[best_slot].occupant = int(e.id)
	e.air_home = best
	e.air_slot = best_slot
	return best


static func release_home(w: SimWorld, aid: int, home: int) -> void:
	var fb := field_of(w, home)
	if fb < 0:
		return
	var fr := field(w, fb)
	for h in fr.hangars:
		if int(h.occupant) == aid:
			h.occupant = -1
	for p in fr.pads:
		if int(p.occupant) == aid:
			p.occupant = -1
		if int(p.landed) == aid:
			p.landed = -1


## Hangar level of home building bid (0 for pads / unknown).
static func hangar_level(w: SimWorld, bid: int) -> int:
	var b = w.entities.get(bid)
	return int(b.get("level", 0)) if b != null else 0


## Id of fid's service point (helipad / forward pad / strip / airfield) serving pos, or -1.
static func service_point_at(w: SimWorld, fid: int, pos: Vector2) -> int:
	var sr: Dictionary = R().get("service_radius", {})
	for fb in _sorted(fields(w)):
		var fr: Dictionary = fields(w)[fb]
		var fe = w.entities.get(int(fb))
		if fe == null or int(fr.owner) != fid or not bool(fe.built):
			continue
		var r := float(sr.get(String(fr.kind), 2.0)) + float(fe.size) * 0.5
		if Vector2(fe.pos).distance_to(pos) <= r:
			return int(fb)
	return -1


## Nearest of fid's pads with a free landing spot: {bid, slot} or {}.
static func free_pad_near(w: SimWorld, fid: int, pos: Vector2) -> Dictionary:
	var best := {}
	var bd := INF
	for fb in _sorted(fields(w)):
		var fr: Dictionary = fields(w)[fb]
		var fe = w.entities.get(int(fb))
		if fe == null or int(fr.owner) != fid or not bool(fe.built):
			continue
		for i in (fr.pads as Array).size():
			var dd: float = Vector2(fe.pos).distance_to(pos)
			if int(fr.pads[i].landed) < 0 and dd < bd:
				bd = dd
				best = {"bid": int(fb), "slot": i}
	return best


# ================================================================ commands
static func _upg(key: String) -> Dictionary:
	return (R().get("upgrades", {}) as Dictionary).get(key, {})


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	scan_new(w)
	var fid := int(cmd.issuer)
	var b: Dictionary = w.entities[int(cmd.building_id)]
	var d := Content.building(String(b.def))
	match String(cmd.type):
		"build_hangar":
			var fr := field(w, int(b.id))
			if fr.is_empty() or not HANGAR_FIELDS.has(String(fr.kind)):
				return "Hangars are bought at an airfield."
			if not bool(b.built):
				return "The airfield is still under construction."
			var cls := String(cmd.get("class", "light"))
			if cls != "light" and cls != "heavy":
				return "Unknown hangar class."
			if not _class_ok(w, int(b.id), cls):
				return "This airstrip takes light hangars only."
			if (fr.hangars as Array).size() >= slot_cap(w, int(b.id)):
				return "No free hangar slot (add an extra strip)."
			if _hangar_cell(w, b, 2).x < 0:
				return "No room for another hangar."
			return w.can_afford(fid, Content.building(_hangar_def(b, cls)).get("cost", {}))
		"upgrade_hangar":
			if kind_of(String(b.def)) != "hangar" or field_of(w, int(b.id)) < 0:
				return "Select a hangar."
			if not bool(b.built) or b.has("air_upg"):
				return "The hangar is busy."
			var kind := String(cmd.get("kind", "level"))
			if kind == "level":
				if int(b.get("level", 0)) >= 3:
					return "The hangar is at its top level."
				return w.can_afford(fid, _upg("hangar_level").get("cost", {}))
			if kind == "to_heavy":
				if String(b.get("class", "light")) != "light":
					return "Only a light hangar can become heavy."
				if not _class_ok(w, field_of(w, int(b.id)), "heavy"):
					return "This airstrip takes light hangars only."
				return w.can_afford(fid, _upg("to_heavy").get("cost", {}))
			return "Unknown hangar upgrade."
		"upgrade_airfield":
			var k := String(cmd.get("kind", "extra_strip"))
			if not fields(w).has(int(b.id)) or not STRIP_KINDS.has(kind_of(String(b.def))):
				return "Select an airfield."
			if k != "extra_strip" and k != "extra_rail":
				return "Unknown airfield upgrade."
			if not bool(b.built) or b.has("air_upg"):
				return "The airfield is busy."
			if int(b.get("extra_strips", 0)) >= int(d.get("max_extra", 0)):
				return "No more strips can be added here."
			return w.can_afford(fid, _upg("extra_strip").get("cost", {}))
		"assign_engineers":
			if field_of(w, int(b.id)) < 0:
				return "Assign engineers to an airfield, hangar or helipad."
			for raw in cmd.get("unit_ids", []):
				if is_engineer(w.entities.get(int(raw))):
					return ""
			return "Select airfield engineers."
	return "Unknown airfield command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var fid := int(cmd.issuer)
	var b: Dictionary = w.entities[int(cmd.building_id)]
	match String(cmd.type):
		"build_hangar":
			var cls := String(cmd.get("class", "light"))
			var hdef := _hangar_def(b, cls)
			var hd := Content.building(hdef)
			if not w.spend(fid, hd.get("cost", {}), "build_hangar"):
				return
			var cell := _hangar_cell(w, b, int(hd.get("size", 2)))
			var hid := w.spawn_building(hdef, fid, cell, false)
			var h: Dictionary = w.entities[hid]
			h["class"] = "bay" if hdef == "m_drone_bay" else cls
			h.air_build = float((R().get("hangar_build_s", {}) as Dictionary).get(String(h["class"]), 20.0))
			_attach_hangar(w, int(b.id), h)
			w.cache["af_next"] = maxi(int(w.cache.get("af_next", 1)), w.next_id)
			w.emit("HangarStarted", {"building_id": int(b.id), "hangar_id": hid, "class": String(h["class"]), "owner": fid})
		"upgrade_hangar":
			var kind := String(cmd.get("kind", "level"))
			var u := _upg("hangar_level" if kind == "level" else "to_heavy")
			if w.spend(fid, u.get("cost", {}), "upgrade_hangar"):
				b.air_upg = {"kind": kind, "t": float(u.get("time_s", 20.0))}
		"upgrade_airfield":
			var u2 := _upg("extra_strip")
			if w.spend(fid, u2.get("cost", {}), "upgrade_airfield"):
				b.air_upg = {"kind": "extra_strip", "t": float(u2.get("time_s", 30.0))}
		"assign_engineers":
			var fb := field_of(w, int(b.id))
			var ids := []
			for raw in cmd.get("unit_ids", []):
				if not ids.has(int(raw)):
					ids.append(int(raw))
			ids.sort()
			for id in ids:
				var e = w.entities.get(id)
				if not is_engineer(e):
					continue
				_unassign(w, e)
				(field(w, fb).engineers as Array).append(id)
				e.air_assign = int(b.id)
				var goal: Vector2 = Construction.approach_goal(w, e, b)
				e.order = {"type": "move", "target": goal, "air_assign": int(b.id)}
				e.target = -1
				Movement.order_path(w, e, goal)
			w.emit("EngineersAssigned", {"building_id": int(b.id), "unit_ids": ids, "owner": fid})


static func _hangar_def(field_b: Dictionary, cls: String) -> String:
	var d := Content.building(String(field_b.def))
	return String(d.get("hangar_heavy" if cls == "heavy" else "hangar_light", ""))


## First free square of `size` around the field (ring order: margin, then Construction.ring_cells order).
static func _hangar_cell(w: SimWorld, b: Dictionary, size: int) -> Vector2i:
	for margin in range(1, 9):
		for c in Construction.ring_cells(b.cell, int(b.size), margin):
			if _square_free(w, c, size):
				return c
	return Vector2i(-1, -1)


static func _square_free(w: SimWorld, origin: Vector2i, size: int) -> bool:
	for y in size:
		for x in size:
			var c := origin + Vector2i(x, y)
			if not w.in_bounds(c) or Construction.building_at_cell(w, c) or not Movement.is_passable(w, c, "vehicle"):
				return false
	return true


static func _unassign(w: SimWorld, e: Dictionary) -> void:
	if not e.has("air_assign"):
		return
	var fb := field_of(w, int(e.air_assign))
	if fb >= 0:
		(field(w, fb).engineers as Array).erase(int(e.id))
	e.erase("air_assign")


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	scan_new(w)
	if not w.sys_state.has("airfield"):
		return
	var flds := fields(w)
	for fb in _sorted(flds):
		if not w.entities.has(int(fb)):
			_field_lost(w, int(fb))
		else:
			_tick_field(w, int(fb))


static func _tick_field(w: SimWorld, fb: int) -> void:
	var fr := field(w, fb)
	var fe: Dictionary = w.entities[fb]
	fr.owner = int(fe.owner)
	for raw in (fr.engineers as Array).duplicate():
		var e = w.entities.get(int(raw))
		var keep: bool = e != null and int(e.get("air_assign", -1)) >= 0 and field_of(w, int(e.air_assign)) == fb
		if keep and String(e.order.get("type", "idle")) != "idle" and int(e.order.get("air_assign", -1)) != int(e.air_assign):
			keep = false   # given another order: no longer assigned
		if not keep:
			fr.engineers.erase(int(raw))
			if e != null and int(e.get("air_assign", -1)) >= 0 and field_of(w, int(e.air_assign)) == fb:
				e.erase("air_assign")
	var present := engineers_at(w, fb)
	var speed := rf("engineer_speed", 1.5) if not present.is_empty() else 1.0
	if fe.has("air_upg"):
		fe.air_upg.t = float(fe.air_upg.t) - SimWorld.DT * speed
		if float(fe.air_upg.t) <= 0.0:
			fe.erase("air_upg")
			fe.extra_strips = int(fe.get("extra_strips", 0)) + 1
			if String(fe.def) == "m_launch_rail":
				fe.extra_rails = int(fe.extra_strips)
			(fr.strips as Array).append({"open": true, "crater_t": 0.0, "busy_id": -1})
			w.emit("AirfieldUpgraded", {"building_id": fb, "extra_strips": int(fe.extra_strips), "owner": int(fe.owner)})
	for s in fr.strips:
		if int(s.busy_id) >= 0 and not w.entities.has(int(s.busy_id)):
			s.busy_id = -1
	var hs: Array = fr.hangars
	var i := 0
	while i < hs.size():
		var h: Dictionary = hs[i]
		var he = w.entities.get(int(h.bid))
		if he == null:
			_hangar_lost(w, h)
			hs.remove_at(i)
			continue
		if int(h.occupant) >= 0 and not w.entities.has(int(h.occupant)):
			h.occupant = -1
		_tick_hangar(w, h, he, speed)
		i += 1
	for p in fr.pads:
		if int(p.occupant) >= 0 and not w.entities.has(int(p.occupant)):
			p.occupant = -1
		if int(p.landed) >= 0:
			var l = w.entities.get(int(p.landed))
			if l == null or not bool(l.get("air_landed", false)) or int(l.get("air_at", -1)) != fb:
				p.landed = -1
	if not present.is_empty():
		repair_crater(w, present[0], fb)
		_upkeep(w, fr, fe, present)


static func _tick_hangar(w: SimWorld, h: Dictionary, he: Dictionary, speed: float) -> void:
	if he.has("air_build"):
		var total := float((R().get("hangar_build_s", {}) as Dictionary).get(String(h["class"]), 20.0))
		he.air_build = float(he.air_build) - SimWorld.DT * speed
		he.progress = clampf(1.0 - float(he.air_build) / maxf(total, 0.001), 0.0, 1.0)
		he.hp = maxf(float(he.hp), snappedf(float(he.max_hp) * (0.1 + 0.9 * float(he.progress)), 0.01))
		if float(he.air_build) <= 0.0:
			he.erase("air_build")
			he.built = true
			he.progress = 1.0
			w.emit("HangarReady", {"hangar_id": int(he.id), "class": String(h["class"]), "owner": int(he.owner)})
	elif he.has("air_upg"):
		he.air_upg.t = float(he.air_upg.t) - SimWorld.DT * speed
		if float(he.air_upg.t) <= 0.0:
			var kind := String(he.air_upg.kind)
			he.erase("air_upg")
			if kind == "level":
				he.level = mini(3, int(he.get("level", 0)) + 1)
			else:
				he["class"] = "heavy"
			h.level = int(he.get("level", 0))
			h["class"] = String(he["class"])
			w.emit("HangarUpgraded", {"hangar_id": int(he.id), "level": int(h.level), "class": String(h["class"]), "owner": int(he.owner)})


## Engineers on site: repair damage (their assigned hangar first, then the field, then the hangars).
static func _upkeep(w: SimWorld, fr: Dictionary, fe: Dictionary, present: Array) -> void:
	var order := []
	for e in present:
		var a := int(e.get("air_assign", -1))
		if a != int(fe.id) and not order.has(a):
			order.append(a)
	order.append(int(fe.id))
	for h in fr.hangars:
		if not order.has(int(h.bid)):
			order.append(int(h.bid))
	var amt := rf("engineer_repair_hp_s", 15.0) * SimWorld.DT
	for bid in order:
		var b = w.entities.get(int(bid))
		if b != null and bool(b.built) and float(b.hp) < float(b.max_hp):
			b.hp = minf(float(b.max_hp), snappedf(float(b.hp) + amt, 0.001))
			return


static func _hangar_lost(w: SimWorld, h: Dictionary) -> void:
	var occ := int(h.occupant)
	w.emit("HangarDestroyed", {"hangar_id": int(h.bid), "occupant": occ})
	if occ < 0:
		return
	var e = w.entities.get(occ)
	if e == null or not bool(e.get("air_landed", false)) or int(e.get("air_at", -1)) != int(h.bid):
		return
	e.air_home = -1
	e.air_at = -1   # stays on the ground where the hangar stood (Air pins it there)
	if int(h.level) >= 3:
		e.hp = snappedf(float(e.hp) - float(e.max_hp) * rf("roof_damage_frac", 0.5), 0.001)
		HotState.touch(w, occ)
		if float(e.hp) > 0.0:
			return
	w.destroy(occ, "hangar_destroyed")


static func _field_lost(w: SimWorld, fb: int) -> void:
	var fr := field(w, fb)
	for raw in fr.engineers:
		var e = w.entities.get(int(raw))
		if e != null:
			e.erase("air_assign")
	fields(w).erase(fb)
	w.emit("AirfieldLost", {"building_id": fb, "owner": int(fr.owner)})


# ================================================================ craters
## Engineer eng works one tick on the first crater of field bid (must be within engineer_range).
## Returns true while a crater remains.
static func repair_crater(w: SimWorld, eng: Dictionary, bid: int) -> bool:
	var fb := field_of(w, bid)
	var b = w.entities.get(fb)
	if fb < 0 or b == null or Vector2(eng.pos).distance_to(b.pos) > rf("engineer_range", 10.0) + float(b.size) * 0.5:
		return false
	var fr := field(w, fb)
	var k := 0
	for s in fr.strips:
		if not bool(s.open):
			s.crater_t = float(s.crater_t) - SimWorld.DT
			if float(s.crater_t) <= 0.0:
				s.open = true
				s.crater_t = 0.0
				w.emit("StripRepaired", {"building_id": fb, "strip": k, "owner": int(fr.owner)})
			break
		k += 1
	for s in fr.strips:
		if not bool(s.open):
			return true
	return false


## A weapon impact at pos: `cratering` weapons close every strip whose centre line is within splash + 1.
static func on_impact(w: SimWorld, weapon: Dictionary, pos: Vector2) -> void:
	if not bool(weapon.get("cratering", false)) or not w.sys_state.has("airfield"):
		return
	var reach := float(weapon.get("splash", 1.0)) + 1.0
	for fb in _sorted(fields(w)):
		var fr: Dictionary = fields(w)[fb]
		for k in (fr.strips as Array).size():
			var pts := strip_points(w, int(fb), k)
			if Geometry2D.get_closest_point_to_segment(pos, pts[0], pts[1]).distance_to(pos) <= reach:
				var s: Dictionary = fr.strips[k]
				s.open = false
				s.crater_t = rf("crater_repair_s", 15.0)
				w.emit("StripCratered", {"building_id": int(fb), "strip": k, "owner": int(fr.owner)})
