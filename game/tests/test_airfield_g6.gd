extends "res://tests/test_base.gd"
## G6 acceptance (owner: ECON-AIRF6). CONTRACTS_G6 section 13 (D25, D26): airfield v2 geometry, apron
## slots, short runways, the G5 flight logic on the new geometry, G5 save / map migration.

const Airfield = preload("res://sim/systems/airfield.gd")
const Air = preload("res://sim/systems/air.gd")
const Movement = preload("res://sim/systems/movement.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const MapIO = preload("res://sim/map_io.gd")
const Helper = preload("res://tests/test_airfield.gd")
const TMP_DIR := "user://test_airfield_g6"

var h = Helper.new()


func _seg_len(seg: Array) -> float:
	return (seg[0] as Vector2).distance_to(seg[1])


func _overlap(a: Rect2i, b: Rect2i) -> bool:
	return a.intersects(b)


## Checks the v2 shape of one layout: base, a contiguous apron of `cap` 2x2 slots beside it (no overlaps),
## `nrw` runways of `len` tiles beyond the apron, parallel to the facing axis.
func _check_layout(lo: Dictionary, size: int, cap: int, nrw: int, rlen: int, tag: String) -> void:
	check_eq((lo.base as Rect2i).size, Vector2i(size, size), tag + ": base size")
	check_eq((lo.slots as Array).size(), cap, tag + ": slot count")
	check_eq((lo.runways as Array).size(), nrw, tag + ": runway count")
	var base: Rect2i = lo.base
	var rects := []
	for c in lo.slots:
		var r := Rect2i(c, Vector2i(2, 2))
		check(not _overlap(r, base), tag + ": slot clear of the base")
		for o in rects:
			check(not _overlap(r, o), tag + ": slots do not overlap")
		rects.append(r)
	if not rects.is_empty():
		var touch := false
		var grown: Rect2i = base.grow(1)
		for r in rects:
			if grown.intersects(r):
				touch = true
		check(touch, tag + ": the apron adjoins the base")
	var axis: Vector2 = Airfield.AXES[int(lo.facing_i)]
	var bc := Vector2(base.position) + Vector2(base.size) * 0.5
	for seg in lo.runways:
		check(absf(_seg_len(seg) - float(rlen)) < 0.001, tag + ": runway %d tiles (got %.2f)" % [rlen, _seg_len(seg)])
		var dir: Vector2 = ((seg[1] as Vector2) - (seg[0] as Vector2)).normalized()
		check(dir.distance_to(axis) < 0.001, tag + ": runway along the facing axis")
		var perp := Vector2(-axis.y, axis.x)
		var rv: float = ((seg[0] as Vector2) - bc).dot(perp)
		for r in rects:
			var sc := Vector2(r.position) + Vector2(1, 1)
			check((sc - bc).dot(perp) < rv - 1.0, tag + ": the runway lies beyond the apron")


func test_layout_base_apron_runway_12() -> void:
	for def in ["a_airfield", "b_aerodrome"]:
		for f in 4:
			_check_layout(Airfield.layout_for(def, Vector2i(40, 40), f, 0), 2, 6, 1, 12, "%s facing %d" % [def, f])
	var w := h._w()
	var fb := h._field(w)
	var b: Dictionary = w.entities[fb]
	check_eq(int(b.size), 2, "the main base is 2x2")
	var lo := Airfield.layout(w, fb)
	_check_layout(lo, 2, 6, 1, 12, "live a_airfield")
	var sp := Airfield.strip_points(w, fb, 0)
	check((sp[0] as Vector2).distance_to(lo.runways[0][0]) < 0.001 and (sp[1] as Vector2).distance_to(lo.runways[0][1]) < 0.001, "strip_points = layout runway")
	check_eq(Airfield.site_ok(w, "a_airfield", b.cell, int(b.get("facing_i", 0))), "", "site_ok for the placed field")
	check_eq(Airfield.slots(w, fb).size(), 6, "slots(): 6 apron slots")


func test_hangars_auto_fill_6_slots() -> void:
	var w := h._w()
	var fb := h._field(w)
	var cells: Array = Airfield.layout(w, fb).slots
	var hids := []
	for k in 6:
		var ev := do_cmd(w, 0, {"type": "build_hangar", "building_id": fb, "class": "heavy" if k == 3 else "light"})
		check_eq(rejected_reason(ev), "", "hangar %d accepted" % k)
		var row: Dictionary = Airfield.slots(w, fb)[k]
		check(int(row.hangar) > 0, "slot %d filled" % k)
		if int(row.hangar) > 0:
			check_eq(Vector2i(w.entities[int(row.hangar)].cell), Vector2i(cells[k]), "hangar %d stands on apron slot %d" % [k, k])
			hids.append(int(row.hangar))
	check_eq(String(Airfield.slots(w, fb)[3]["class"]), "heavy", "slot 3 holds the heavy hangar")
	var ev7 := do_cmd(w, 0, {"type": "build_hangar", "building_id": fb, "class": "light"})
	check(rejected_reason(ev7).contains("No free hangar slot"), "a 7th hangar needs an extra strip (%s)" % rejected_reason(ev7))
	# a destroyed hangar frees its slot; the next one auto-fills the lowest free slot
	w.destroy(hids[2], "test")
	w.step()
	check_eq(int(Airfield.slots(w, fb)[2].hangar), -1, "slot 2 free after its hangar died")
	do_cmd(w, 0, {"type": "build_hangar", "building_id": fb, "class": "light"})
	var nh := int(Airfield.slots(w, fb)[2].hangar)
	check(nh > 0 and not hids.has(nh), "the new hangar fills slot 2")
	if nh > 0:
		check_eq(Vector2i(w.entities[nh].cell), Vector2i(cells[2]), "on slot 2's square")
	# hangars finish building and take aircraft as in G5
	h._run(w, 800, func() -> bool: return bool(w.entities[nh].built))
	check(bool(w.entities[nh].built), "the slotted hangar finishes")
	check(int(Airfield.free_slots(w, fb).light) >= 1, "built slot hangars offer home slots")


func test_extra_strip_adds_runway_and_2_slots() -> void:
	var w := h._w()
	var fb := h._field(w)
	check_eq(Airfield.slot_cap(w, fb), 6, "6 slots before")
	var ev := do_cmd(w, 0, {"type": "upgrade_airfield", "building_id": fb, "kind": "extra_strip"})
	check_eq(rejected_reason(ev), "", "extra strip accepted")
	check(h._run(w, 2000, func() -> bool: return int(w.entities[fb].get("extra_strips", 0)) == 1) > 0, "upgrade completes")
	check_eq(Airfield.slot_cap(w, fb), 8, "+2 slots")
	check_eq((Airfield.field(w, fb).strips as Array).size(), 2, "+1 strip state")
	var lo := Airfield.layout(w, fb)
	_check_layout(lo, 2, 8, 2, 12, "after 1 extra strip")
	check((lo.runways[0][0] as Vector2).distance_to(lo.runways[1][0]) >= 3.0, "the two runways are apart")
	for k in 8:
		check_eq(rejected_reason(do_cmd(w, 0, {"type": "build_hangar", "building_id": fb, "class": "light"})), "", "hangar %d of 8" % k)
	var filled := 0
	for row in Airfield.slots(w, fb):
		if int(row.hangar) > 0:
			filled += 1
	check_eq(filled, 8, "all 8 slots filled")
	check(rejected_reason(do_cmd(w, 0, {"type": "build_hangar", "building_id": fb})).contains("No free hangar slot"), "9th rejected")


func test_short_runway_lengths_8_6_6() -> void:
	var want := {"a_airfield": 12, "b_aerodrome": 12, "a_airstrip": 8, "b_airstrip": 8, "a_forward_strip": 6,
		"b_forward_strip": 6, "m_launch_rail": 6}
	for def in want:
		var lo := Airfield.layout_for(def, Vector2i(30, 30), 0, 0)
		check_eq((lo.runways as Array).size(), 1, def + ": one runway")
		check(absf(_seg_len(lo.runways[0]) - float(want[def])) < 0.001, "%s runway %d tiles" % [def, want[def]])
	var w := h._w()
	var off := Vector2i(12, 0)
	for def in ["a_airstrip", "a_forward_strip"]:
		var fb := h._field(w, def, off)
		off += Vector2i(0, 14)
		check(absf(_seg_len(Airfield.strip_points(w, fb, 0)) - float(want[def])) < 0.001, "%s live strip %d tiles" % [def, want[def]])
	var wm := h._w()
	var rail := h._field(wm, "m_launch_rail", Vector2i(12, 0), 0)
	check(absf(_seg_len(Airfield.strip_points(wm, rail, 0)) - 6.0) < 0.001, "launch rail strip 6 tiles")
	_check_layout(Airfield.layout(wm, rail), int(Content.building("m_launch_rail").size), 4, 1, 6, "launch rail")


func test_takeoff_land_holding_craters_on_v2() -> void:
	var w := h._w()
	var fb := h._field(w)
	var hid := h._hangar(w, fb)
	var hid2 := h._hangar(w, fb)
	var j := h._jet(w, "a_strike_jet", hid)
	var j2 := h._jet(w, "a_interceptor", hid2)
	var rw := Airfield.strip_points(w, fb, 0)
	check(w.submit({"type": "take_off", "issuer": 0, "unit_ids": [j]}).ok, "take_off accepted")
	var on_runway := true
	var rolled := false
	for i in 400:
		w.step()
		if Air.phase(w, j) == "roll":
			rolled = true
			var p := Vector2(w.entities[j].pos)
			if Geometry2D.get_closest_point_to_segment(p, rw[0], rw[1]).distance_to(p) > 0.01:
				on_runway = false
		if Air.phase(w, j) == "air":
			break
	check(rolled and on_runway, "the take-off roll runs along the v2 runway")
	check_eq(Air.phase(w, j), "air", "airborne")
	# holding: the strip is busy, so the arrival circles the field
	var strip: Dictionary = Airfield.field(w, fb).strips[0]
	strip.busy_id = int(h._hq(w, 0).id)
	w.submit({"type": "rebase", "issuer": 0, "unit_ids": [j], "building_id": fb})
	check(h._run(w, 900, func() -> bool: return Air.phase(w, j) == "holding") > 0, "holds while the runway is busy")
	strip.busy_id = -1
	var app := [0, 0]   # [approach ticks after the first, off-axis ones]
	var first := [true]
	h._run(w, 900, func() -> bool:
		if Air.phase(w, j) == "approach":
			if first[0]:
				first[0] = false   # cleared from the circle this tick; the glide starts next tick
			else:
				app[0] += 1
				var ap := Airfield.strip_points(w, fb, 0)
				var dir: Vector2 = ((ap[1] as Vector2) - (ap[0] as Vector2)).normalized()
				var rel: Vector2 = Vector2(w.entities[j].pos) - (ap[0] as Vector2)
				if absf(rel.cross(dir)) > 0.01:
					app[1] += 1
		return Air.phase(w, j) == "parked")
	check(app[0] > 0 and app[1] == 0, "the approach glides along the v2 runway axis (%s)" % str(app))
	check_eq(Air.phase(w, j), "parked", "lands and taxis in")
	check_eq(int(w.entities[j].air_at), hid, "back in its slot hangar")
	# craters: a cratering hit on the v2 runway closes it and blocks take-off
	var mid: Vector2 = ((rw[0] as Vector2) + (rw[1] as Vector2)) * 0.5
	Airfield.on_impact(w, Content.unit("a_strike_jet").payload, mid)
	check_eq(Airfield.open_strips(w, fb), 0, "the v2 runway is cratered")
	w.submit({"type": "take_off", "issuer": 0, "unit_ids": [j2]})
	w.run_ticks(60)
	check_eq(Air.phase(w, j2), "parked", "no take-off from the cratered runway")
	var eng := w.spawn_unit("a_airfield_engineers", 0, Vector2(w.entities[fb].pos) + Vector2(0, 3))
	w.step()
	check(w.submit({"type": "assign_engineers", "issuer": 0, "unit_ids": [eng], "building_id": fb}).ok, "engineers assigned")
	check(h._run(w, 1500, func() -> bool: return Airfield.open_strips(w, fb) == 1) > 0, "engineers repair the runway")
	# divert: with the only field gone an airborne jet diverts to another field
	var fb2 := h._field(w, "a_airfield", Vector2i(-14, 10))
	h._hangar(w, fb2)
	w.submit({"type": "take_off", "issuer": 0, "unit_ids": [j2]})
	check(h._run(w, 400, func() -> bool: return Air.phase(w, j2) == "air") > 0, "second jet airborne")
	w.destroy(fb, "test")
	w.submit({"type": "rebase", "issuer": 0, "unit_ids": [j2], "building_id": fb2})
	check(h._run(w, 1500, func() -> bool: return Air.phase(w, j2) == "parked") > 0, "lands at the other v2 field")
	check_eq(Airfield.field_of(w, int(w.entities[j2].air_at)), fb2, "parked at the second field")


## Rewrites a v2 world's field into its G5 shape (6x6 apron building, ring-placed hangars, no slot
## indices, sys_state.airfield.ver 1), as a G5 save would hold it.
func _to_g5(w: SimWorld, fb: int) -> void:
	var b: Dictionary = w.entities[fb]
	var fr: Dictionary = Airfield.field(w, fb)
	for hg in fr.hangars:
		var he: Dictionary = w.entities[int(hg.bid)]
		Movement.on_footprint_changed(w, he.cell, 2, false)
		he.cell = Vector2i(-50, -50)   # parked off-map while the base grows
	w.cache.erase("bld_occ")
	Movement.on_footprint_changed(w, b.cell, int(b.size), false)
	b.cell = Vector2i(b.cell) - Vector2i(2, 2)
	b.size = 6
	b.pos = Vector2(b.cell) + Vector2(3, 3)
	Movement.on_footprint_changed(w, b.cell, 6, true)
	for hg in fr.hangars:
		w.cache.erase("bld_occ")
		var he: Dictionary = w.entities[int(hg.bid)]
		var c := Airfield._ring_cell(w, b, 2)
		he.cell = c
		he.pos = Vector2(c) + Vector2(1, 1)
		Movement.on_footprint_changed(w, c, 2, true)
		hg.erase("slot")
	w.cache.erase("bld_occ")
	w.sys_state.airfield.ver = 1


func test_g5_save_migrates_to_v2() -> void:
	var w := h._w()
	var fb := h._field(w)
	var hids := [h._hangar(w, fb), h._hangar(w, fb, "heavy"), h._hangar(w, fb)]
	var j := h._jet(w, "a_strike_jet", hids[1])
	w.run_ticks(5)
	var c0: Vector2i = w.entities[fb].cell
	_to_g5(w, fb)
	w.step()   # unsaved world: the scan migrates in place too
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var w5 := h._w()
	var fb5 := h._field(w5)
	var h5 := [h._hangar(w5, fb5), h._hangar(w5, fb5, "heavy"), h._hangar(w5, fb5)]
	var j5 := h._jet(w5, "a_strike_jet", h5[1])
	w5.run_ticks(5)
	_to_g5(w5, fb5)
	var old_cells := []
	for id in h5:
		old_cells.append(Vector2i(w5.entities[id].cell))
	var path := TMP_DIR + "/g5.sav"
	check_eq(SaveSystem.save(w5, path), "", "G5-shaped save written")
	var l: SimWorld = SaveSystem.load(path)
	var l2: SimWorld = SaveSystem.load(path)
	check(l != null and l2 != null, "G5 save loads")
	if l == null or l2 == null:
		return
	l.step()
	l2.step()
	check_eq(int(l.sys_state.airfield.ver), 2, "migrated to v2")
	check_eq(l.state_hash(), l2.state_hash(), "migration is deterministic")
	var b: Dictionary = l.entities[fb5]
	check_eq(int(b.size), 2, "base resized to 2x2")
	check_eq(Vector2i(b.cell), c0, "base keeps its centre")
	var cells: Array = Airfield.layout(l, fb5).slots
	for k in 3:
		var hg: Dictionary = Airfield.field(l, fb5).hangars[k]
		check_eq(int(hg.slot), k, "hangar %d re-slotted in order" % k)
		check_eq(Vector2i(l.entities[int(hg.bid)].cell), Vector2i(cells[k]), "hangar %d moved onto slot %d" % [k, k])
	check_eq((Airfield.field(l, fb5).strips as Array).size(), 1, "strips re-laid")
	var home5 := int(l.entities[j5].get("air_at", -1))
	check(h5.has(home5), "still parked in one of its field's hangars (%d)" % home5)
	if h5.has(home5):
		check_eq(Vector2(l.entities[j5].pos), Vector2(l.entities[home5].pos), "the parked jet moved with its hangar")
	var freed := 0
	for c in old_cells:
		if not (cells.slice(0, 3) as Array).has(c) and Movement.is_passable(l, c, "vehicle"):
			freed += 1
	check(freed > 0, "old hangar squares are passable again (%d)" % freed)
	# the migrated field works: the jet flies from the re-laid runway and lands back in its slot hangar
	l.submit({"type": "take_off", "issuer": 0, "unit_ids": [j5]})
	check(h._run(l, 400, func() -> bool: return Air.phase(l, j5) == "air") > 0, "takes off after migration")
	l.submit({"type": "rebase", "issuer": 0, "unit_ids": [j5], "building_id": fb5})
	check(h._run(l, 1500, func() -> bool: return Air.phase(l, j5) == "parked") > 0, "lands after migration")
	# the in-place (unsaved) world migrated the same way
	check_eq(int(w.entities[fb].size), 2, "in-place migration resized the base")
	check_eq(int(Airfield.field(w, fb).hangars[0].slot), 0, "in-place migration re-slotted")
	# G5 maps: field entries with hangars place them onto the apron slots in order
	var wm := h._w()
	var mb := wm.spawn_building("a_airfield", 0, h._site(wm, "a_airfield", Vector2i(12, 0)), true)   # map load: no scan yet
	var map_e := {"def": "a_airfield", "kind": "building", "hangars": ["light", "heavy", "light"], "extra_strips": 1}
	check_eq(MapIO.field_reason(map_e), "", "G5 map field entry still valid")
	MapIO._place_field(wm, map_e, mb, 0)
	wm.step()
	var mcells: Array = Airfield.layout(wm, mb).slots
	check_eq(mcells.size(), 8, "map extra strip: 8 slots")
	for k in 3:
		var row: Dictionary = Airfield.slots(wm, mb)[k]
		check(int(row.hangar) > 0, "map hangar %d slotted" % k)
		if int(row.hangar) > 0:
			check_eq(Vector2i(wm.entities[int(row.hangar)].cell), Vector2i(mcells[k]), "map hangar %d on slot %d" % [k, k])
	check_eq((Airfield.field(wm, mb).strips as Array).size(), 2, "map extra strip re-laid as a 2nd runway")


func test_register_mobile_field_for_carriers() -> void:
	var w := h._w()
	var fb := h._field(w)
	var cid := w.spawn_unit("rifleman", 0, Vector2(w.entities[fb].pos) + Vector2(-6, -6))   # stand-in hull
	w.step()
	Airfield.register_mobile_field(w, cid, 4)
	check(Airfield.fields(w).has(cid), "carrier registered as a field")
	check_eq(Airfield.slot_cap(w, cid), 4, "4 light hangar slots")
	check_eq(Airfield.slots(w, cid).size(), 4, "slots() lists them")
	check_eq(int(Airfield.free_slots(w, cid).light), 4, "4 free light homes")
	check(Airfield.usable(w, cid), "usable as a field")
	var sp := Airfield.strip_points(w, cid, 0)
	check(_seg_len(sp) > 0.0, "a deck strip")
	Airfield.register_mobile_field(w, cid, 4)
	check_eq(Airfield.slot_cap(w, cid), 4, "re-register is idempotent")
	w.step()
	w.destroy(cid, "test")
	w.step()
	check(not Airfield.fields(w).has(cid), "a lost carrier drops its field")


# ---------------------------------------------------------------- CR air_out_of_bounds (ECON-AIRF6-2)
## Origin of a 2x2 base whose square and apron slot 0 are free, scanned from `start` along `step`.
func _edge_site(w: SimWorld, def: String, start: Vector2i, step: Vector2i, facing_i: int) -> Vector2i:
	for i in 60:
		for sgn in [1, -1]:
			var c: Vector2i = start + step * i * sgn
			if not Airfield._square_free(w, c, 2):
				continue
			var sl: Array = Airfield.layout_for(def, c, facing_i, 0).get("slots", [])
			if not sl.is_empty() and w.in_bounds(sl[0]) and Airfield._square_free(w, sl[0], 2):
				return c
	return start


## Every aircraft of w is inside the map; offenders are appended to bad.
func _air_in_map(w: SimWorld, bad: Array) -> void:
	for raw in Air.flights(w):
		var e = w.entities.get(int(raw))
		if e != null and not w.in_bounds(w.cell_of(e.pos)):
			bad.append("t=%d id=%d %s %s" % [w.tick, int(raw), Air.phase(w, int(raw)), str(e.pos)])


## A b_aerodrome built at the map border (bottom: the runway lies past the edge beyond the apron; right:
## the runway runs off the map along its axis; both: the holding circle crosses the edge). A b_bomber
## sortie, the return, holding, the approach and the taxi-in must stay inside the map on every tick.
func test_edge_field_flights_stay_in_map() -> void:
	var w := h._w()
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var cases := [["bottom", Vector2i(mw / 2 - 1, mh - 6), Vector2i(1, 0)], ["right", Vector2i(mw - 3, mh / 2 - 12), Vector2i(0, 1)]]
	for cs in cases:
		var tag: String = cs[0]
		var cell := _edge_site(w, "b_aerodrome", cs[1], cs[2], 0)
		var fb := w.spawn_building("b_aerodrome", 1, cell, true)
		w.entities[fb].facing_i = 0
		w.step()
		var b: Dictionary = w.entities[fb]
		var raw_rw := Airfield._runway("b_aerodrome", Vector2(b.pos), int(b.size), 0, 0, 0)
		var off := false
		for p in raw_rw:
			off = off or not w.in_bounds(w.cell_of(p))
		check(off, tag + ": the unclamped v2 runway crosses the map edge (the case is real)")
		var rw := Airfield.strip_points(w, fb, 0)
		check(w.in_bounds(w.cell_of(rw[0])) and w.in_bounds(w.cell_of(rw[1])), tag + ": strip_points are clamped into the map %s" % str(rw))
		var sc: Vector2i = Airfield.layout(w, fb).slots[0]
		var hid := w.spawn_building(Airfield._hangar_def(b, "heavy"), 1, sc, true)
		w.step()
		check_eq(int(Airfield.slots(w, fb)[0].hangar), hid, tag + ": heavy hangar on apron slot 0")
		var j := h._jet(w, "b_bomber", hid, 1)
		check_eq(Air.phase(w, j), "parked", tag + ": bomber parked at the border field")
		var tp := Vector2(b.pos) + (Vector2(0, -24) if tag == "bottom" else Vector2(-24, 0))
		var t := w.spawn_unit("mbt", 0, tp)
		w.step()
		check(w.submit({"type": "sortie", "issuer": 1, "unit_ids": [j], "target_id": t}).ok, tag + ": sortie accepted")
		var seen := {}
		var bad := []
		var held := [0]
		var strip: Dictionary = Airfield.field(w, fb).strips[0]
		for i in 3000:
			w.step()
			_air_in_map(w, bad)
			if not w.entities.has(j):
				break
			var ph := Air.phase(w, j)
			seen[ph] = true
			if ph == "ret" and not seen.has("holding"):
				strip.busy_id = int(hid)   # runway busy: the bomber must circle the border field
			if ph == "holding":
				held[0] += 1
				if held[0] >= 120:
					strip.busy_id = -1
			if ph == "parked" and seen.has("approach"):
				break
		for k in ["taxi", "roll", "sortie", "ret", "holding", "approach", "taxi_in"]:
			check(seen.has(k), "%s: phase %s flown (%s)" % [tag, k, str(seen.keys())])
		check_eq(Air.phase(w, j), "parked", tag + ": landed back at the border field")
		check(bad.is_empty(), "%s: every aircraft stayed inside the map every tick (%d off: %s)" % [tag, bad.size(), str(bad.slice(0, 3))])
		if w.entities.has(t):
			w.destroy(t, "test")
