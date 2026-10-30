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
## ---- G6 airfield v2 (owner: ECON-AIRF6; CONTRACTS_G6 section 13, D25/D26; rules g5_air.v2) ----
## Layout (layout_for): the field building is the main base (a_airfield / b_aerodrome 2x2); beside it, on
##   the facing's perp side, a tarmac apron of hangar slots (2 rows of 2x2 slots, slot k = column k / 2,
##   row k mod 2), then the runway(s) beyond the apron along the facing axis (strip_len tiles: airfield 12,
##   airstrip 8, forward strip 6, launch rail 6). slots_base 6 (+2 per extra strip, each extra strip also
##   adds one runway). build_hangar auto-fills the lowest free slot. Runways are virtual (no cells).
## hangars[i].slot = apron slot index (saved). Fields with no hangar slots keep the G5 strip geometry.
## Mobile fields (register_mobile_field, NAVAL6 carriers): kind "carrier", one deck strip along the
##   unit's facing, `slots` virtual light hangar slots whose hangar bid is the carrier itself.
## Migration (sys_state.airfield.ver 1 -> 2, on first scan after a G5 load): bases resized to the def
##   size around their old centre, strips re-laid (count = strips + extra_strips, state kept), hangars
##   re-slotted in order (moved onto slot k when its square is free, else left in place).

const Movement = preload("res://sim/systems/movement.gd")
const Construction = preload("res://sim/systems/construction.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const HotState = preload("res://sim/hot_state.gd")  # core.hot_writer_rule

const FIELD_KINDS := ["airfield", "airstrip", "rail", "forward_strip", "helipad", "forward_helipad"]
const STRIP_KINDS := ["airfield", "airstrip", "rail", "forward_strip", "carrier"]
const MOBILE_KIND := "carrier"
const VER := 2
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
		w.sys_state["airfield"] = {"fields": {}, "ver": VER}
	return w.sys_state.airfield


static func V(key: String, dflt: float) -> float:
	return float((R().get("v2", {}) as Dictionary).get(key, dflt))


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
	return b != null and bool(b.get("built", true)) and fields(w).has(fid_bid) and (b.kind == "building" or is_mobile(w, fid_bid))


static func is_mobile(w: SimWorld, bid: int) -> bool:
	return String(field(w, bid).get("kind", "")) == MOBILE_KIND


static func open_strips(w: SimWorld, bid: int) -> int:
	var n := 0
	for s in field(w, bid).get("strips", []):
		if bool(s.open):
			n += 1
	return n


## World-space ends [start, end] of strip k of field bid (v2: beyond the apron; carriers: the deck).
## Both ends are clamped into the map (a field built near the border would otherwise put its runway, and
## every aircraft rolling or landing on it, past the edge; ECON-AIRF6-2, CR air_out_of_bounds).
static func strip_points(w: SimWorld, bid: int, k: int) -> Array:
	var b = w.entities.get(bid)
	if b == null:
		return [Vector2.ZERO, Vector2.ZERO]
	if b.kind != "building":
		var ax := Vector2.from_angle(float(b.get("facing", 0.0)))
		var dl := V("carrier_deck_len", 4.0)
		var st: Vector2 = Vector2(b.pos) - ax * dl * 0.5
		return [clamp_in(w, st), clamp_in(w, st + ax * dl)]
	var rw := _runway(String(b.def), Vector2(b.pos), int(b.size), int(b.get("facing_i", 0)), int(b.get("extra_strips", 0)), k)
	return [clamp_in(w, rw[0]), clamp_in(w, rw[1])]


## p unchanged when it lies inside the map ([0, w) x [0, h)); else the nearest point just inside it.
## In-map positions are returned as-is, so flights that never reach the border keep their exact hashes.
static func clamp_in(w: SimWorld, p: Vector2) -> Vector2:
	var mw := float(w.map.get("w", 0))
	var mh := float(w.map.get("h", 0))
	if (p.x >= 0.0 and p.y >= 0.0 and p.x < mw and p.y < mh) or mw <= 0.0 or mh <= 0.0:
		return p
	return Vector2(clampf(p.x, 0.0, mw - 0.01), clampf(p.y, 0.0, mh - 0.01))


## Runway k of a field def placed with centre pos / size / facing (shared by strip_points and layout_for).
static func _runway(def_id: String, pos: Vector2, size: int, facing_i: int, extra: int, k: int) -> Array:
	var d := Content.building(def_id)
	var axis: Vector2 = AXES[facing_i % 4]
	var perp := Vector2(-axis.y, axis.x)
	var s := float(size)
	var v := s + _apron_depth(d) + V("runway_offset", 1.5) + V("runway_gap", 4.0) * float(k)
	var start: Vector2 = pos + axis * (-s * 0.5) + perp * (v - s * 0.5)
	return [start, start + axis * float(d.get("strip_len", 10))]


static func _apron_depth(d: Dictionary) -> float:
	if int(d.get("slots_base", 0)) <= 0 or not HANGAR_FIELDS.has(String(d.get("air_field", ""))):
		return 0.0
	return V("apron_rows", 2.0) * V("slot_size", 2.0)


static func _cap_for(d: Dictionary, extra: int) -> int:
	if not HANGAR_FIELDS.has(String(d.get("air_field", ""))):
		return 0
	return int(d.get("slots_base", 0)) + int(d.get("slots_per_strip", 0)) * extra


## Pure v2 layout of field def_id with origin cell / facing / extra strips (placement previews, AI, editor):
## {base: Rect2i, apron: Rect2 (world), slots: [Vector2i slot origins, slot order], runways: [[a, b]],
##  strip_len, slot_size, facing_i}. Empty for a def that is not a field.
static func layout_for(def_id: String, cell: Vector2i, facing_i: int, extra: int = 0) -> Dictionary:
	var d := Content.building(def_id)
	var kind := String(d.get("air_field", ""))
	if not FIELD_KINDS.has(kind):
		return {}
	var size := int(d.get("size", 1))
	var s := float(size)
	var pos := Vector2(cell) + Vector2(s, s) * 0.5
	var f := facing_i % 4
	var axis: Vector2 = AXES[f]
	var perp := Vector2(-axis.y, axis.x)
	var ss := int(V("slot_size", 2.0))
	var rows := maxi(1, int(V("apron_rows", 2.0)))
	var cap := _cap_for(d, extra)
	var slot_cells := []
	for k in cap:
		var lc := Vector2(float(ss * (k / rows)) + ss * 0.5, s + float(ss * (k % rows)) + ss * 0.5)
		var pc: Vector2 = pos + axis * (lc.x - s * 0.5) + perp * (lc.y - s * 0.5)
		slot_cells.append(Vector2i(roundi(pc.x - ss * 0.5), roundi(pc.y - ss * 0.5)))
	var cols := ceili(float(cap) / float(rows))
	var a0: Vector2 = pos + axis * (-s * 0.5) + perp * (s * 0.5)
	var a1: Vector2 = a0 + axis * float(cols * ss) + perp * _apron_depth(d)
	var runways := []
	if STRIP_KINDS.has(kind):
		for k in int(d.get("strips", 1)) + extra:
			runways.append(_runway(def_id, pos, size, f, extra, k))
	return {"base": Rect2i(cell, Vector2i(size, size)), "apron": Rect2(a0, Vector2.ZERO).expand(a1),
		"slots": slot_cells, "runways": runways, "strip_len": int(d.get("strip_len", 0)), "slot_size": ss, "facing_i": f}


## v2 layout of an existing field building (see layout_for).
static func layout(w: SimWorld, bid: int) -> Dictionary:
	var b = w.entities.get(bid)
	if b == null or b.kind != "building":
		return {}
	return layout_for(String(b.def), b.cell, int(b.get("facing_i", 0)), int(b.get("extra_strips", 0)))


## "" when every apron slot and runway cell of a field placed at cell / facing is on passable ground
## (placement helper for UI, AI and editor; the base footprint itself is checked by construction).
static func site_ok(w: SimWorld, def_id: String, cell: Vector2i, facing_i: int) -> String:
	var lo := layout_for(def_id, cell, facing_i, 0)
	if lo.is_empty():
		return ""
	for c in lo.slots:
		for y in int(lo.slot_size):
			for x in int(lo.slot_size):
				var q: Vector2i = c + Vector2i(x, y)
				if not w.in_bounds(q) or not Movement.is_passable(w, q, "vehicle"):
					return "No room for the apron here."
	for rw in lo.runways:
		var n := maxi(1, int(lo.strip_len))
		for i in n + 1:
			var p: Vector2 = (rw[0] as Vector2).lerp(rw[1], float(i) / float(n))
			var q := Vector2i(floori(p.x), floori(p.y))
			if not w.in_bounds(q) or not Movement.is_passable(w, q, "vehicle"):
				return "No room for the runway here."
	return ""


## Apron slots of field bid in slot order: [{slot, cell, hangar (bid or -1), class, level, occupant}].
static func slots(w: SimWorld, bid: int) -> Array:
	var fb := field_of(w, bid)
	var out := []
	if fb < 0:
		return out
	var fr := field(w, fb)
	var cells: Array = []
	if is_mobile(w, fb):
		for i in (fr.hangars as Array).size():
			cells.append(Vector2i(Vector2(w.entities[fb].pos)))
	else:
		cells = layout(w, fb).get("slots", [])
	for k in maxi(cells.size(), slot_cap(w, fb)):
		var row := {"slot": k, "cell": cells[k] if k < cells.size() else Vector2i(-1, -1), "hangar": -1, "class": "", "level": 0, "occupant": -1}
		for h in fr.hangars:
			if int(h.get("slot", -1)) == k:
				row.hangar = int(h.bid)
				row["class"] = String(h["class"])
				row.level = int(h.level)
				row.occupant = int(h.occupant)
		out.append(row)
	return out


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
		var hcls := String(Content.building(String(b.def)).get("hangar_class", "light"))
		for fb0 in _sorted(fields(w)):
			var fe0 = w.entities.get(int(fb0))
			if fe0 == null or fe0.kind != "building" or int(fe0.owner) != int(b.owner) or not HANGAR_FIELDS.has(String(fields(w)[fb0].kind)):
				continue
			var k0 := (layout(w, int(fb0)).get("slots", []) as Array).find(b.cell)
			if k0 >= 0 and not _slot_used(field(w, int(fb0)), k0) and _class_ok(w, int(fb0), hcls):
				_attach_hangar(w, int(fb0), b, k0)
				return
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


static func _attach_hangar(w: SimWorld, fbid: int, h: Dictionary, slot: int = -1) -> void:
	var cls := String(Content.building(String(h.def)).get("hangar_class", "light"))
	h.air_parent = fbid
	h["class"] = String(h.get("class", cls))
	h.level = int(h.get("level", 0))
	if slot < 0:
		slot = _free_index(w, fbid)
	(field(w, fbid).hangars as Array).append({"bid": int(h.id), "class": String(h["class"]), "level": int(h.level), "occupant": -1, "slot": slot})


static func _slot_used(fr: Dictionary, k: int) -> bool:
	for h in fr.get("hangars", []):
		if int(h.get("slot", -1)) == k:
			return true
	return false


## Lowest slot index no attached hangar uses.
static func _free_index(w: SimWorld, fbid: int) -> int:
	var fr := field(w, fbid)
	var k := 0
	while _slot_used(fr, k):
		k += 1
	return k


## NAVAL6 (D39): carrier_id (a unit) acts as an air field with `slot_count` virtual light hangar slots
## and one deck strip (the G5 hangar + sortie model at sea). Idempotent: re-registering resizes the
## slots (never dropping an occupied one). The field is dropped when the carrier is destroyed.
static func register_mobile_field(w: SimWorld, carrier_id: int, slot_count: int) -> void:
	var e = w.entities.get(carrier_id)
	if e == null or e.kind == "building":
		return
	var flds: Dictionary = _st(w).fields
	if not flds.has(carrier_id):
		flds[carrier_id] = {"kind": MOBILE_KIND, "owner": int(e.owner), "strips": [{"open": true, "crater_t": 0.0, "busy_id": -1}],
			"hangars": [], "pads": [], "engineers": []}
	var hs: Array = flds[carrier_id].hangars
	while hs.size() < slot_count:
		hs.append({"bid": carrier_id, "class": "light", "level": 0, "occupant": -1, "slot": hs.size()})
	while hs.size() > maxi(0, slot_count) and int(hs[hs.size() - 1].occupant) < 0:
		hs.remove_at(hs.size() - 1)


## Scans ids created since the last call (cheap: only new ids). Runtime cursor in w.cache.
static func scan_new(w: SimWorld) -> void:
	var s0 = w.sys_state.get("airfield")
	if s0 != null and int(s0.get("ver", 1)) < VER:
		_migrate(w)
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
	if is_mobile(w, bid):
		return (field(w, bid).hangars as Array).size()
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
		if int(h.occupant) < 0 and he != null and bool(he.get("built", true)):
			out[String(h["class"])] = int(out.get(String(h["class"]), 0)) + 1
	var fe = w.entities.get(fb)
	if bid == fb and fe != null and bool(fe.get("built", true)) and bool(Content.building(String(fe.def)).get("home_ok", true)):
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
		if fe == null or int(fe.owner) != fid or not bool(fe.get("built", true)) or not HANGAR_FIELDS.has(String(fields(w)[fb].kind)):
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
				if not bool(fe.get("built", true)) or not bool(Content.building(String(fe.def)).get("home_ok", true)):
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
					if he == null or not bool(he.get("built", true)) or int(h.occupant) >= 0 or String(h["class"]) != cls:
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
		if fe == null or int(fr.owner) != fid or not bool(fe.get("built", true)):
			continue
		var r := float(sr.get(String(fr.kind), 2.0)) + float(fe.size) * 0.5
		if Vector2(fe.pos).distance_to(pos) <= r:
			return int(fb)
	return -1


## VTOL8 (13.9c-42): a regular (non counter-nanite) VTOL dropship (aircraft "vtol", no cn_dropship) never takes a pad
## field smaller than its landing square (the 2x2 helicopter helipads); airfield / strip fields and pads at least
## lz_size wide still serve it. Every other aircraft: true (unchanged).
static func pad_fits(w: SimWorld, bid: int, def: Dictionary) -> bool:
	if String(def.get("aircraft", "")) != "vtol" or bool(def.get("cn_dropship", false)):
		return true
	var b = w.entities.get(bid)
	if b == null:
		return false
	if HANGAR_FIELDS.has(String(field(w, bid).get("kind", ""))):
		return true
	return int(b.get("size", 1)) >= maxi(1, int(def.get("lz_size", 2)))


## Nearest of fid's pads with a free landing spot: {bid, slot} or {}. def (optional): only pads that fit it (pad_fits).
static func free_pad_near(w: SimWorld, fid: int, pos: Vector2, def: Dictionary = {}) -> Dictionary:
	var best := {}
	var bd := INF
	for fb in _sorted(fields(w)):
		var fr: Dictionary = fields(w)[fb]
		var fe = w.entities.get(int(fb))
		if fe == null or int(fr.owner) != fid or not bool(fe.get("built", true)):
			continue
		if not def.is_empty() and not pad_fits(w, int(fb), def):
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
			var slot := _next_slot(w, b, int(hd.get("size", 2)))
			if slot < 0 or not w.spend(fid, hd.get("cost", {}), "build_hangar"):
				return
			var cell: Vector2i = layout(w, int(b.id)).slots[slot]
			var hid := w.spawn_building(hdef, fid, cell, false)
			var h: Dictionary = w.entities[hid]
			h["class"] = "bay" if hdef == "m_drone_bay" else cls
			h.air_build = float((R().get("hangar_build_s", {}) as Dictionary).get(String(h["class"]), 20.0))
			_attach_hangar(w, int(b.id), h, slot)
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


## v2: origin of the lowest free apron slot of field b (no attached hangar on it and its square clear),
## or (-1, -1). map_io (G5 map fields) and tests call this to place hangars.
static func _hangar_cell(w: SimWorld, b: Dictionary, size: int) -> Vector2i:
	var k := _next_slot(w, b, size)
	if k < 0:
		return Vector2i(-1, -1)
	return layout(w, int(b.id)).slots[k]


## Index of the lowest free apron slot of field b (see _hangar_cell), or -1.
static func _next_slot(w: SimWorld, b: Dictionary, size: int) -> int:
	var cells: Array = layout(w, int(b.id)).get("slots", [])
	var fr := field(w, int(b.id))
	for k in mini(cells.size(), slot_cap(w, int(b.id)) if not fr.is_empty() else cells.size()):
		if _slot_used(fr, k):
			continue
		if _square_free(w, cells[k], size):
			return k
	return -1


## G5 ring search: first free square of `size` around the field (ring order: margin, then
## Construction.ring_cells order). For non-hangar helpers (towers, tests).
static func _ring_cell(w: SimWorld, b: Dictionary, size: int) -> Vector2i:
	var apron := []
	for sc in layout(w, int(b.id)).get("slots", []):
		apron.append(Rect2i(sc, Vector2i(2, 2)))
	for margin in range(1, 9):
		for c in Construction.ring_cells(b.cell, int(b.size), margin):
			if not _square_free(w, c, size):
				continue
			var r := Rect2i(c, Vector2i(size, size))
			var on_apron := false
			for a in apron:
				if r.intersects(a):
					on_apron = true
			if not on_apron:
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
	if fe.kind == "building" and STRIP_KINDS.has(String(fr.kind)):
		var want := int(Content.building(String(fe.def)).get("strips", 1)) + int(fe.get("extra_strips", 0))
		while (fr.strips as Array).size() < want:   # v2: extra_strips set outside the upgrade (maps, editor)
			fr.strips.append({"open": true, "crater_t": 0.0, "busy_id": -1})
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
		if b != null and bool(b.get("built", true)) and float(b.hp) < float(b.max_hp):
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
	if String(fr.get("kind", "")) == MOBILE_KIND:
		for h in fr.hangars:
			var occ := int(h.occupant)
			var a = w.entities.get(occ)
			if a != null and bool(a.get("air_landed", false)) and int(a.get("air_at", -1)) == fb:
				w.destroy(occ, "carrier_lost")
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
		if String(fr.kind) == MOBILE_KIND:
			continue
		for k in (fr.strips as Array).size():
			var pts := strip_points(w, int(fb), k)
			if Geometry2D.get_closest_point_to_segment(pos, pts[0], pts[1]).distance_to(pos) <= reach:
				var s: Dictionary = fr.strips[k]
				s.open = false
				s.crater_t = rf("crater_repair_s", 15.0)
				w.emit("StripCratered", {"building_id": int(fb), "strip": k, "owner": int(fr.owner)})


# ================================================================ G5 -> v2 migration
## CONTRACTS_G6 section 13: G5 saves load into v2. Bases resize to the def size around their old centre,
## strips are re-laid (count = strips + extra_strips, open/crater state kept, geometry is derived), and
## each field's hangars are re-slotted in order (moved onto the lowest free slot whose square is clear,
## else left where they stand with the lowest unused slot index). Runs once (ver 1 -> 2).
static func _migrate(w: SimWorld) -> void:
	var st: Dictionary = w.sys_state.airfield
	st.ver = VER
	for fb in _sorted(st.fields):
		var b = w.entities.get(int(fb))
		var fr: Dictionary = st.fields[fb]
		if b == null or b.kind != "building":
			continue
		var d := Content.building(String(b.def))
		var ns := int(d.get("size", b.size))
		if ns != int(b.size):
			var os := int(b.size)
			Movement.on_footprint_changed(w, b.cell, os, false)
			var c: Vector2i = Vector2i(b.cell) + Vector2i((os - ns) / 2, (os - ns) / 2)
			b.cell = c
			b.size = ns
			b.pos = Vector2(c) + Vector2(ns, ns) * 0.5
			b.rally = Vector2(c) + Vector2(ns * 0.5, ns + 1.0)
			Movement.on_footprint_changed(w, c, ns, true)
		if STRIP_KINDS.has(String(fr.kind)):
			var want := int(d.get("strips", 1)) + int(b.get("extra_strips", 0))
			while (fr.strips as Array).size() < want:
				fr.strips.append({"open": true, "crater_t": 0.0, "busy_id": -1})
		_reslot(w, int(fb))
	w.cache.erase("bld_occ")


static func _reslot(w: SimWorld, fb: int) -> void:
	var fr := field(w, fb)
	var cells: Array = layout(w, fb).get("slots", [])
	var hs: Array = fr.hangars
	var mine := {}
	for h in hs:
		mine[int(h.bid)] = true
		h.erase("slot")
	for h in hs:
		var he = w.entities.get(int(h.bid))
		if he != null:
			Movement.on_footprint_changed(w, he.cell, int(he.size), false)
	var occ := {}
	for id in _sorted(w.entities):
		var o: Dictionary = w.entities[id]
		if o.kind != "building" or mine.has(int(id)):
			continue
		for y in int(o.size):
			for x in int(o.size):
				occ[Vector2i(o.cell) + Vector2i(x, y)] = true
	for h in hs:
		var he = w.entities.get(int(h.bid))
		if he == null:
			continue
		var sz := int(he.size)
		var k := -1
		for i in cells.size():
			if not _slot_used(fr, i) and _free_in(w, occ, cells[i], sz):
				k = i
				break
		if k >= 0:
			he.cell = cells[k]
			he.pos = Vector2(he.cell) + Vector2(sz, sz) * 0.5
			he.rally = Vector2(he.cell) + Vector2(sz * 0.5, sz + 1.0)
		else:
			k = _free_index(w, fb)
		h.slot = k
		for y in sz:
			for x in sz:
				occ[Vector2i(he.cell) + Vector2i(x, y)] = true
	for h in hs:
		var he = w.entities.get(int(h.bid))
		if he != null:
			Movement.on_footprint_changed(w, he.cell, int(he.size), true)


static func _free_in(w: SimWorld, occ: Dictionary, origin: Vector2i, size: int) -> bool:
	for y in size:
		for x in size:
			var c := origin + Vector2i(x, y)
			if not w.in_bounds(c) or occ.has(c) or not Movement.is_passable(w, c, "vehicle"):
				return false
	return true
