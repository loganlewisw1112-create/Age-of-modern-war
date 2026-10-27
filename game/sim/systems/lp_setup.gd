extends RefCounted
## G7 (LPMODE7): Last Protocol start state. Reads LPMAP7's map.lp layout (agreed on the board, seq 475) or builds a
## scaled fallback layout around map.spawns[0], then pre-builds the 3-ring base, the army, the Machine cores, nests,
## Machine structures and pre-spread creep. Everything here runs once (LastProtocol.setup) and only in Last Protocol.
## Rules: rules.g7_lastprotocol (content/g7/rules_g7_lastprotocol.json), all PROVISIONAL.

const Terrain = preload("res://sim/terrain.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
const CounterNanite = preload("res://sim/systems/counter_nanite.gd")

const RING_NAMES := ["outer", "economy", "core"]


static func R() -> Dictionary:
	return Content.rules().get("g7_lastprotocol", {})


static func _v2i(v) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Vector2:
		return Vector2i(int(v.x), int(v.y))
	if v is Array and (v as Array).size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i(-1, -1)


## Square ring rect of half-size h around c.
static func _sq(c: Vector2i, h: int) -> Rect2i:
	return Rect2i(c - Vector2i(h, h), Vector2i(h * 2 + 1, h * 2 + 1))


## The layout used by the mode: {center, rings [{name, rect}], facility, airfield, scale, from_map}.
## Ring rects are the wall squares; a point is "in ring i" when inside rings[i].rect and outside rings[i+1].rect.
static func layout(w: SimWorld) -> Dictionary:
	var lp = w.map.get("lp")
	if lp is Dictionary and (lp as Dictionary).has("base"):
		var b: Dictionary = lp.base
		var rings := []
		for i in (b.get("rings", []) as Array).size():
			var r: Dictionary = b.rings[i]
			var rr = r.get("rect")
			rings.append({"name": String(r.get("name", RING_NAMES[mini(i, 2)])), "rect": rr if rr is Rect2i else Rect2i()})
		return {"center": _v2i(b.get("center")), "rings": rings, "facility": _v2i(b.get("facility")),
			"airfield": b.get("airfield", {}), "scale": 1.0, "from_map": true}
	var lf: Dictionary = R().get("layout_fallback", {})
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var margin := int(lf.get("margin", 8))
	var want := int(lf.get("outer", 70))
	var sp: Vector2i = w.factions[0].spawn if w.factions.has(0) else Vector2i(mw / 2, mh / 2)
	var far := 0.0
	for f in w.factions:
		far = maxf(far, Vector2(w.factions[f].spawn).distance_to(Vector2(sp)))
	var ho := mini(want, maxi(mini(mini(mw, mh) / 2 - margin, int(far * 0.35)), 6))
	var sc := float(ho) / float(want)
	var c := Vector2i(clampi(sp.x, ho + 2, mw - ho - 3), clampi(sp.y, ho + 2, mh - ho - 3))
	var he := maxi(int(round(float(lf.get("economy", 55)) * sc)), 4)
	var hc := maxi(int(round(float(lf.get("core", 35)) * sc)), 3)
	return {"center": c, "rings": [{"name": "outer", "rect": _sq(c, ho)}, {"name": "economy", "rect": _sq(c, he)},
		{"name": "core", "rect": _sq(c, hc)}], "facility": c - Vector2i(2, 2),
		"airfield": {}, "scale": sc, "from_map": false}


## Ring index of a position: 0 outer, 1 economy, 2 core, -1 outside the base.
static func ring_of(L: Dictionary, p: Vector2) -> int:
	var cell := Vector2i(int(floor(p.x)), int(floor(p.y)))
	var out := -1
	for i in (L.rings as Array).size():
		if (L.rings[i].rect as Rect2i).has_point(cell):
			out = i
	return out


# ================================================================ placement helpers
static func _occ(w: SimWorld) -> Dictionary:
	var occ := {}
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "building":
			var o := _v2i(e.cell)
			for dy in int(e.size):
				for dx in int(e.size):
					occ[o + Vector2i(dx, dy)] = true
		elif e.kind == "resource" or e.kind == "structure":
			occ[w.cell_of(e.pos)] = true
	return occ


static func _free(w: SimWorld, occ: Dictionary, o: Vector2i, size: int) -> bool:
	for dy in size:
		for dx in size:
			var c := o + Vector2i(dx, dy)
			if not w.in_bounds(c) or occ.has(c) or not Terrain.buildable(w.terrain_at(c)):
				return false
	return true


## Spawns def at origin when the footprint is free and the def exists. Returns the id or -1.
static func place(w: SimWorld, occ: Dictionary, def: String, fid: int, o: Vector2i) -> int:
	var d := Content.building(def)
	if d.is_empty():
		return -1
	var size := int(d.get("size", 1))
	if not _free(w, occ, o, size):
		return -1
	var id := w.spawn_building(def, fid, o, true)
	for dy in size:
		for dx in size:
			occ[o + Vector2i(dx, dy)] = true
	return id


## Places def at the first free origin on a small spiral around o.
static func place_near(w: SimWorld, occ: Dictionary, def: String, fid: int, o: Vector2i, reach: int = 6) -> int:
	for r in reach + 1:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var id := place(w, occ, def, fid, o + Vector2i(dx, dy))
				if id >= 0:
					return id
	return -1


## Perimeter cells of a rect (clockwise from the top-left).
static func perimeter(r: Rect2i) -> Array:
	var out := []
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x - 1
	var y1 := r.end.y - 1
	for x in range(x0, x1 + 1):
		out.append(Vector2i(x, y0))
	for y in range(y0 + 1, y1 + 1):
		out.append(Vector2i(x1, y))
	for x in range(x1 - 1, x0 - 1, -1):
		out.append(Vector2i(x, y1))
	for y in range(y1 - 1, y0, -1):
		out.append(Vector2i(x0, y))
	return out


static func gate_cells(r: Rect2i) -> Array:
	var c := r.get_center()
	return [Vector2i(c.x, r.position.y), Vector2i(r.end.x - 1, c.y), Vector2i(c.x, r.end.y - 1), Vector2i(r.position.x, c.y)]


# ================================================================ start state
const L = preload("res://sim/ai/ai_g6_lib.gd")
const PData = preload("res://sim/systems/progression_data.gd")
const Air = preload("res://sim/systems/air.gd")
const T7_PATH := "res://sim/systems/turrets7.gd"
const PLOT_DEFS := {"company_hq": "a_company_hq", "artillery": "a_howitzer_pit", "airfield": "a_airfield",
	"hangar": "a_hangar_heavy", "helipad": "a_helipad", "sam": "a_sam_site", "radar": "a_radar_station",
	"repair_bay": "a_repair_bay", "hospital": "a_hospital", "exo_garage": "a_exo_garage"}


static func _plot_def(kind: String) -> String:
	if PLOT_DEFS.has(kind):
		return String(PLOT_DEFS[kind])
	return kind


## Points spread evenly on the square of half-size h around c (n points).
static func square_points(c: Vector2i, h: int, n: int) -> Array:
	var per := perimeter(_sq(c, maxi(h, 1)))
	var out := []
	if n <= 0 or per.is_empty():
		return out
	for i in n:
		out.append(per[(i * per.size()) / n])
	return out


static func _turret_defs() -> Array:
	var st: Dictionary = R().get("start", {})
	var out := []
	for d in st.get("turrets_g7", []):
		if not Content.building(String(d)).is_empty():
			out.append(String(d))
	if out.is_empty():
		for d in st.get("turret_placeholders", []):
			if not Content.building(String(d)).is_empty():
				out.append(String(d))
	return out


static func _turret(w: SimWorld, occ: Dictionary, def: String, fid: int, o: Vector2i) -> int:
	var t7 = load(T7_PATH) if ResourceLoader.exists(T7_PATH) else null
	if t7 != null and L.api(t7, "place") and _free(w, occ, o, int(Content.building(def).get("size", 1))):
		var bid = t7.callv("place", [w, fid, def, o])
		if typeof(bid) == TYPE_INT and int(bid) >= 0 and w.entities.has(int(bid)):
			var e: Dictionary = w.entities[int(bid)]
			for dy in int(e.size):
				for dx in int(e.size):
					occ[_v2i(e.cell) + Vector2i(dx, dy)] = true
			return int(bid)
	return place(w, occ, def, fid, o)


## Walls, gates, towers and turrets of every ring. Returns {walls, gates, towers, turrets} id lists per ring.
static func build_rings(w: SimWorld, occ: Dictionary, L0: Dictionary, fid: int) -> Array:
	var lf: Dictionary = R().get("layout_fallback", {})
	var lp = w.map.get("lp")
	var mrings: Array = lp.base.get("rings", []) if lp is Dictionary and lp.has("base") else []
	var tdefs := _turret_defs()
	var out := []
	var ti := 0
	for i in (L0.rings as Array).size():
		var rect: Rect2i = L0.rings[i].rect
		var md: Dictionary = mrings[i] if i < mrings.size() else {}
		var gates: Array = md.get("gates", gate_cells(rect))
		var gset := {}
		for g in gates:
			gset[_v2i(g)] = true
		var towers: Array = md.get("towers", [])
		var tset := {}
		for t in towers:
			tset[_v2i(t)] = true
		var cells: Array = md.get("wall", perimeter(rect))
		var every := int(lf.get("tower_every", 10))
		var rec := {"walls": [], "gates": [], "towers": [], "turrets": [], "bunkers": []}
		var k := 0
		for c0 in cells:
			var c := _v2i(c0)
			if gset.has(c):
				continue
			var tower := tset.has(c) or (towers.is_empty() and i == 0 and k % every == every / 2)
			var id := place(w, occ, "a_wall_tower" if tower else "a_wall", fid, c)
			if id >= 0:
				(rec.towers if tower else rec.walls).append(id)
			k += 1
		for g in gset:
			var gid := place(w, occ, "a_gate", fid, g)
			if gid >= 0:
				rec.gates.append(gid)
		var tslots: Array = md.get("turrets", [])
		if tslots.is_empty() and i == 0 and not tdefs.is_empty():
			var h := rect.size.x / 2 - 3
			tslots = square_points(rect.get_center(), h, maxi(perimeter(_sq(rect.get_center(), h)).size() / int(lf.get("turret_every", 14)), 4))
		for s in tslots:
			if tdefs.is_empty():
				break
			var tid := _turret(w, occ, String(tdefs[ti % tdefs.size()]), fid, _v2i(s))
			ti += 1
			if tid >= 0:
				rec.turrets.append(tid)
		for b in md.get("bunkers", []):
			var bid := place(w, occ, "a_atgm_bunker", fid, _v2i(b))
			if bid >= 0:
				rec.bunkers.append(bid)
		out.append(rec)
	return out


## Economy and military plots (map.lp plots or the rules lists on fallback squares).
static func build_plots(w: SimWorld, occ: Dictionary, L0: Dictionary, fid: int) -> Array:
	var st: Dictionary = R().get("start", {})
	var lp = w.map.get("lp")
	var mrings: Array = lp.base.get("rings", []) if lp is Dictionary and lp.has("base") else []
	var ids := []
	var c: Vector2i = L0.center
	for i in [1, 2]:
		if i >= (L0.rings as Array).size():
			break
		var md: Dictionary = mrings[i] if i < mrings.size() else {}
		var plots: Array = md.get("plots", [])
		if plots.is_empty():
			var defs: Array = st.get("economy_plots" if i == 1 else "core_plots", [])
			var hi: int = (L0.rings[i].rect as Rect2i).size.x / 2
			var lo: int = (L0.rings[i + 1].rect as Rect2i).size.x / 2 if i + 1 < (L0.rings as Array).size() else 6
			var pts := square_points(c, (hi + lo) / 2, defs.size())
			for j in defs.size():
				plots.append({"cell": pts[j], "kind": String(defs[j])})
		for p in plots:
			var id := place_near(w, occ, _plot_def(String(p.get("kind", ""))), fid, _v2i(p.get("cell")), 4)
			if id >= 0:
				ids.append(id)
	return ids


## The main army: units per ring (rules start.army), spread on a square just inside each ring; aircraft at the
## airfield. Every unit carries e.lp_ring (home ring) and e.lp_home (home cell) for the defence commander.
static func build_army(w: SimWorld, L0: Dictionary, fid: int) -> Array:
	var army: Dictionary = R().get("start", {}).get("army", {})
	var c: Vector2i = L0.center
	var ids := []
	var ring_ix := {"outer": 0, "economy": 1, "core": 2, "air": 2}
	for key in ["outer", "economy", "core", "air"]:
		var spec: Dictionary = army.get(key, {})
		var names := spec.keys()
		names.sort()
		var list := []
		for n in names:
			if Content.unit(String(n)).is_empty():
				continue
			for k in int(spec[n]):
				list.append(String(n))
		var ri: int = mini(int(ring_ix[key]), (L0.rings as Array).size() - 1)
		var h: int = (L0.rings[ri].rect as Rect2i).size.x / 2 - (3 if key != "air" else 6)
		if key == "core" or key == "air":
			h = maxi(h / 2, 3)
		var pts := square_points(c, maxi(h, 2), list.size())
		for j in list.size():
			var p := Vector2(pts[j]) + Vector2(0.5, 0.5)
			var id := w.spawn_unit(String(list[j]), fid, p)
			var e: Dictionary = w.entities[id]
			e.lp_ring = ri
			e.lp_home = Vector2(p)
			ids.append(id)
	return ids


## Two VTOL dropships parked at the airfield (map.lp airfield pads or near the core ring).
static func build_vtols(w: SimWorld, L0: Dictionary, fid: int) -> Array:
	var st: Dictionary = R().get("start", {})
	var def := String(st.get("vtol_def", "a_vtol_dropship"))
	if Content.unit(def).is_empty():
		return []
	var pads: Array = (L0.airfield as Dictionary).get("pads", []) if L0.airfield is Dictionary else []
	var ids := []
	var c: Vector2i = L0.center
	for i in int(st.get("vtols", 2)):
		var p := Vector2(_v2i(pads[i])) + Vector2(0.5, 0.5) if i < pads.size() else Vector2(c) + Vector2(-8.0 + 4.0 * i, 8.0)
		var id := w.spawn_unit(def, fid, p)
		var e: Dictionary = w.entities[id]
		Air.land_now(w, e)
		e.lp_ring = 2
		e.lp_home = p
		ids.append(id)
	return ids


## Machine side: 3 cores (map.lp.cores or fallback points toward the Machine spawn; the last one walks), seed nests,
## Machine structures and garrisons.
static func build_machine(w: SimWorld, occ: Dictionary, L0: Dictionary, mfid: int) -> Dictionary:
	var st: Dictionary = R().get("start", {}).get("machine", {})
	var lp = w.map.get("lp")
	var lpd: Dictionary = lp if lp is Dictionary else {}
	var c := Vector2(L0.center)
	var m := Vector2(w.factions[mfid].spawn)
	var dir := (m - c).normalized() if m.distance_to(c) > 1.0 else Vector2.RIGHT
	var perp := Vector2(-dir.y, dir.x)
	var span := m.distance_to(c)
	var cores: Array = lpd.get("cores", [])
	if cores.is_empty():
		var sc := float(L0.get("scale", 1.0))
		for f in [[0.62, 0.3], [0.75, -0.3], [0.92, 0.0]]:
			cores.append(Vector2i(c + dir * span * float(f[0]) + perp * span * float(f[1]) * 0.5 * sc))
	var ids := []
	var cdef := String(st.get("core_def", "m_core"))
	for cc in cores:
		var o := _v2i(cc)
		var size := int(Content.building(cdef).get("size", 3))
		var bid := -1
		for r in 8:
			if _free(w, occ, o + Vector2i(r, 0), size):
				bid = Cores.place(w, mfid, o + Vector2i(r, 0), cdef)
				break
		if bid >= 0:
			var b: Dictionary = w.entities[bid]
			for dy in size:
				for dx in size:
					occ[_v2i(b.cell) + Vector2i(dx, dy)] = true
			ids.append(bid)
	var nests: Array = lpd.get("nests", [])
	if nests.is_empty():
		for i in 4:
			var t := 0.45 + 0.12 * i
			nests.append({"center": c + dir * span * t + perp * span * (0.25 if i % 2 == 0 else -0.25), "count": 5, "radius": 3.0})
	for n in nests:
		Creep.add_nest(w, Vector2(n.get("center", Vector2.ZERO)), int(n.get("count", 5)), float(n.get("radius", 3.0)), mfid)
	var bases: Array = lpd.get("machine_bases", [])
	var bdefs: Array = st.get("bases", [])
	if bases.is_empty():
		for b in ids:
			bases.append(_v2i(w.entities[b].cell) + Vector2i(5, 0))
	var bi := 0
	for b in bases:
		if bdefs.is_empty():
			break
		place_near(w, occ, String(bdefs[bi % bdefs.size()]), mfid, _v2i(b), 5)
		bi += 1
	var gar: Dictionary = st.get("garrison", {})
	var gk := gar.keys()
	gk.sort()
	for b in ids:
		var bp: Vector2 = w.entities[b].pos
		var k := 0
		for d in gk:
			if Content.unit(String(d)).is_empty():
				continue
			for j in int(gar[d]):
				var a := float(k) * 0.7
				w.spawn_unit(String(d), mfid, bp + Vector2(cos(a), sin(a)) * (4.0 + float(k % 3)))
				k += 1
	return {"cores": ids, "nests": nests.size()}


## Creep pre-spread at start (map.lp.creep blobs, or blobs around every Machine building).
static func prespread(w: SimWorld, mfid: int) -> int:
	var s := Creep.enable(w)
	var blobs: Array = (w.map.get("lp", {}) as Dictionary).get("creep", []) if w.map.get("lp") is Dictionary else []
	if blobs.is_empty():
		for id in w.entities:
			var e: Dictionary = w.entities[id]
			if e.kind == "building" and int(e.owner) == mfid:
				blobs.append({"center": e.pos, "radius": 18.0})
	var val := int(R().get("creep", {}).get("prespread_value", 200))
	var on := int(Creep.RC().get("on", 64))
	var cs := int(s.cs)
	var cw := int(s.cw)
	var ch := int(s.ch)
	var v: PackedByteArray = s.v
	var fl: PackedByteArray = s.fl
	var on_n := int(s.on_n)
	for b in blobs:
		var ctr: Vector2 = Vector2(b.get("center", Vector2.ZERO)) / float(cs)
		var rr := float(b.get("radius", 10.0)) / float(cs)
		for y in range(maxi(int(ctr.y - rr), 0), mini(int(ctr.y + rr) + 1, ch)):
			for x in range(maxi(int(ctr.x - rr), 0), mini(int(ctr.x + rr) + 1, cw)):
				if Vector2(x + 0.5, y + 0.5).distance_to(ctr) > rr:
					continue
				var k := y * cw + x
				if int(fl[k]) & Creep.F_BLOCK != 0 or int(v[k]) >= val:
					continue
				if int(v[k]) < on and val >= on:
					on_n += 1
				v[k] = val
	s.v = v
	s.on_n = on_n
	s.dv = int(s.get("dv", 0)) + 1
	return on_n


## Everything researched for the side's faction (Stage 10 comes from the config).
static func research_all(w: SimWorld, fid: int) -> int:
	var f: Dictionary = w.factions[fid]
	var done: Array = f.research.done
	for id in PData.project_ids():
		var p := PData.project(id)
		if not (p.get("factions", []) as Array).is_empty() and not (p.factions as Array).has(String(f.faction_def)):
			continue
		if not done.has(id):
			done.append(id)
	return done.size()


## Pre-builds the whole start state. Returns a summary stored in the mode state.
static func build(w: SimWorld, fid: int, mfid: int) -> Dictionary:
	var L0 := layout(w)
	var occ := _occ(w)
	var st: Dictionary = R().get("start", {})
	research_all(w, fid)
	var fac := place_near(w, occ, String(st.get("facility_def", "a_cn_facility")), fid, L0.facility, 8)
	var hq := place_near(w, occ, String(st.get("hq_def", "a_company_hq")), fid, L0.center + Vector2i(8, 8), 8)
	var rings := build_rings(w, occ, L0, fid)
	var plots := build_plots(w, occ, L0, fid)
	var army := build_army(w, L0, fid)
	var vtols := build_vtols(w, L0, fid)
	var mach := build_machine(w, occ, L0, mfid)
	var on_n := prespread(w, mfid)
	CounterNanite.set_tac_cap(w, fid, -1)
	var rr := []
	for i in (L0.rings as Array).size():
		var r: Rect2i = L0.rings[i].rect
		rr.append({"name": String(L0.rings[i].name), "rect": r, "walls": rings[i].walls if i < rings.size() else [],
			"gates": rings[i].gates if i < rings.size() else [], "towers": rings[i].towers if i < rings.size() else [],
			"turrets": rings[i].turrets if i < rings.size() else [], "fallen": false, "breach_t": 0})
	return {"center": L0.center, "rings": rr, "facility": fac, "hq": hq, "plots": plots, "army": army, "vtols": vtols,
		"cores": mach.cores, "nests": mach.nests, "creep_cells": on_n, "scale": L0.scale, "from_map": L0.from_map}


## Fills the raised facility: strike teams, tactical squads and the stealth dropship on its helipad (CNFAC7's own
## training finisher, so garages, helipad and dropship sizes all come from content). True once done.
static func fill_facility(w: SimWorld, fid: int) -> bool:
	var CnF = load("res://sim/systems/cn_facility.gd")
	var facs: Array = CnF.facilities(w, fid)
	if facs.is_empty():
		return false
	var F: Dictionary = CnF.fac(w, int(facs[0]))
	if F.is_empty() or not L.api(CnF, "_finish_train"):
		return false
	var st: Dictionary = R().get("start", {})
	CounterNanite.set_tac_cap(w, fid, -1)
	for i in int(st.get("strike_teams", 2)):
		CnF.callv("_finish_train", [w, F, "strike_team"])
	for i in int(st.get("tactical_squads", 4)):
		CnF.callv("_finish_train", [w, F, "tactical_squad"])
	CnF.callv("_finish_train", [w, F, "stealth_dropship"])
	return true
