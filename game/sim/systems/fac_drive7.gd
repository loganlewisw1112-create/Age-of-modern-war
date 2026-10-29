extends RefCounted
## G7 (APCMOV7, owner note 13.9c-16): facility traffic controller for the counter-nanite facility's APCs.
## Smooth, realistic driving inside the compound: APCs follow the lane centre-lines of the layout
## (content/g7/defs_g7_facility.json _g7_facility: lanes, zones, garages, gates; read at runtime, nothing hard-coded),
## corners are filleted arcs fitted so the body clears every building footprint (turning radius R_MIN..R_MAX, no
## pivots, no heading snaps), speed ramps with ACC / BRK and slows for curves, garages are backed into (nose out),
## two nose-south staging bays on the loading pad (top of the compound; `apc_bays` in the json, else derived from
## the pad, PROVISIONAL) hold 2 APCs, a third waits in its garage. Departures leave one after another (convoy order =
## order seq) through the gate lane; the two-way lanes and the gate lane are directional reservations (no head-on),
## every APC keeps a safe gap to the others (path look-ahead, priority by distance to the conflict, then seq).
## Used by CnFacility's flows (hook in _order_slots: launch / return / wash / garages) and by player orders: a plain
## move order given to a managed APC is taken over (target in its garage -> its garage, on the pad / staging -> a bay,
## outside the compound -> out through the gates then on to the point); command fd7_go {ids, to, target} too.
## Runs right after Movement (SYSTEM_ORDER): it re-asserts pose / facing / order of the APCs it drives.
## State: w.sys_state.fac_drive7 {v: {"<id>": V}, seq} created only when a facility APC is first driven, so a match
## without a facility is untouched and costs nothing. Routes are saved as raw polylines (exact layout points); the
## filleted geometry is rebuilt from them (pure function of the layout) into w.cache. Floats saved snapped to 1/4096.

const KEY := "fac_drive7"
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")

# vehicle footprint for clearance (PROVISIONAL: a 6.2 m x 2.7 m APC hull, 1 tile = 4 m)
const HL := 0.78
const HW := 0.34
const R_MAX := 2.0          # largest fillet radius tried (tiles)
const R_MIN := 1.0          # smallest acceptable turning radius (4 m: tight compound turn, no pivot)
const V_FWD := 1.4          # tiles/s forward inside the compound (~20 km/h)
const V_REV := 0.5          # tiles/s reversing
const A_LAT := 0.6          # tiles/s^2 lateral (curve speed sqrt(A_LAT * R))
const ACC := 0.6            # tiles/s^2
const BRK := 1.0            # tiles/s^2
const D_SAFE := 1.95        # centre spacing kept between two APCs (radius 0.9 each)
const GEAR_TICKS := 10      # pause at a forward / reverse change
const NODE_STEP := 0.8
const PLAN_M := 0.06        # planning margin around the hull (tiles)
const Q := 1.0 / 4096.0
const DRIVE_ZONES := ["gate_outer", "apc_wash", "gate_inner", "staging", "pad", "helipad", "fuel_point", "approach"]
const PLAZAS := ["pad", "staging"]
const PLAZA_COST := 1.5     # open-ground hops cost more than lane centre-lines (routes keep to the lanes)

static var _G: Dictionary = {}
static var _fit_cache: Dictionary = {}


static func _snap(v: float) -> float:
	return snappedf(v, Q)


# ================================================================ layout -> clearance raster + lane graph
static func _rect(a) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


static func garage_park(c: Dictionary, i: int) -> Vector2:
	var g: Array = c.garages[i]
	return Vector2(float(g[0]) + 0.5, float(g[1]) + 0.5)


## +1 / -1: the x direction a garage's door opens to (west row opens east).
static func garage_out(c: Dictionary, i: int) -> Vector2:
	return Vector2(1, 0) if float(c.garages[i][0]) < float(c.compound) * 0.5 else Vector2(-1, 0)


static func bays(c: Dictionary) -> Array:
	var out := []
	var b = c.get("apc_bays")
	if b is Array and not (b as Array).is_empty():
		for q in b:
			out.append([Vector2(float(q[0]), float(q[1])), deg_to_rad(float(q[2]) if (q as Array).size() > 2 else 90.0)])
		return out
	var pad := _rect(c.get("pad", [8, 2, 7, 6]))   # PROVISIONAL default: two nose-south bays on the loading pad
	out.append([pad.position + Vector2(1.8, 3.6), PI * 0.5])
	out.append([pad.position + Vector2(4.5, 3.6), PI * 0.5])
	return out


static func _solid_at(G: Dictionary, q: Vector2, gar: int) -> bool:
	var cs := int(G.cs)
	var x := floori(q.x)
	var y := floori(q.y)
	if x < 0 or y < 0 or x >= cs or y >= cs:
		return false   # outside the compound: the cleared gate apron
	var v := int((G.grid as PackedByteArray)[y * cs + x])
	return v == 1 or (v >= 10 and v - 10 != gar)


## Body clear of every footprint at pose (p, h); garage `gar` (own garage) may be entered.
## m: extra margin around the hull (the router plans with PLAN_M so sampled checks never graze a corner).
static func pose_clear(G: Dictionary, p: Vector2, h: float, gar: int = -1, m := 0.0) -> bool:
	var fx := Vector2(cos(h), sin(h))
	var fy := Vector2(-fx.y, fx.x)
	var hl := HL + m
	var hw := HW + m
	for i in 5:
		var a := -hl + hl * 0.5 * float(i)
		for j in 3:
			if _solid_at(G, p + fx * a + fy * (-hw + hw * float(j)), gar):
				return false
	return true


static func _seg_clear(G: Dictionary, a: Vector2, b: Vector2, gar: int) -> bool:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return true
	var h := d.angle()
	var n := maxi(1, ceili(l / 0.2))
	for k in n + 1:
		if not pose_clear(G, a + d * (float(k) / float(n)), h, gar, PLAN_M):
			return false
	return true


## Centre-line and body width clear (no length): graph edges; the router checks the full body on the driven geometry.
static func _lane_clear(G: Dictionary, a: Vector2, b: Vector2, gar: int) -> bool:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return not _solid_at(G, a, gar)
	var fy := Vector2(-d.y, d.x) / l
	var n := maxi(1, ceili(l / 0.2))
	for k in n + 1:
		var q := a + d * (float(k) / float(n))
		if _solid_at(G, q, gar) or _solid_at(G, q + fy * HW, gar) or _solid_at(G, q - fy * HW, gar):
			return false
	return true


static func _layout_sig(c: Dictionary) -> String:
	var s := ""
	for k in ["compound", "lanes", "garages", "pad", "staging", "gate_outer", "apc_wash", "gate_inner", "apc_bays", "link_walls", "towers", "lockers", "baffles"]:
		s += str(c.get(k, "")) + "|"
	for z in CnFacility.ZONES:
		s += str(c.get(z, "")) + ";"
	return s


static func _raster(c: Dictionary) -> PackedByteArray:
	var cs := int(c.compound)
	var grid := PackedByteArray()
	grid.resize(cs * cs)
	var put := func(r: Rect2, v: int) -> void:
		for y in range(maxi(0, floori(r.position.y)), mini(cs, ceili(r.end.y))):
			for x in range(maxi(0, floori(r.position.x)), mini(cs, ceili(r.end.x))):
				grid[y * cs + x] = v
	for x in cs:   # the wall ring (2 thick) except the outer gate opening
		for y in cs:
			if x < 2 or y < 2 or x >= cs - 2 or y >= cs - 2:
				grid[y * cs + x] = 1
	var go := _rect(c.get("gate_outer", [0, 0, 0, 0]))
	put.call(go, 0)
	for z in CnFacility.ZONES:
		if DRIVE_ZONES.has(z) or not c.has(z) or not (c[z] is Array) or (c[z] as Array).size() != 4:
			continue
		put.call(_rect(c[z]), 1)
	var co: Array = c.get("core_offset", [3, 3])
	var csz := int(Content.building("a_cn_facility").get("size", 4)) if not Content.building("a_cn_facility").is_empty() else 4
	put.call(Rect2(float(co[0]), float(co[1]), float(csz), float(csz)), 1)
	for k in ["link_walls"]:
		for r in c.get(k, []):
			put.call(_rect(r), 1)
	for t in c.get("towers", []):
		put.call(Rect2(float(t[0]), float(t[1]), 2, 2), 1)
	var cp: Array = c.get("checkpoint", [])
	if cp.size() == 2:
		put.call(Rect2(float(cp[0]), float(cp[1]), 2, 2), 1)
	for k in ["lockers", "baffles"]:
		for q in c.get(k, []):
			put.call(Rect2(float(q[0]), float(q[1]), 1, 1), 1)
	var gz: Array = c.get("garage_size", [3, 3])
	for i in (c.get("garages", []) as Array).size():
		var p := garage_park(c, i)
		put.call(Rect2(p - Vector2(float(gz[0]), float(gz[1])) * 0.5, Vector2(float(gz[0]), float(gz[1]))), 10 + i)
	return grid


## Lane centre-lines: [a, b, oneway (a->b only)]. Lanes 3.5+ tiles wide carry two one-way lanes (right-hand traffic).
static func _lines(c: Dictionary) -> Array:
	var out := []
	for l in c.get("lanes", []):
		var r := _rect(l)
		if maxf(r.size.x, r.size.y) < 2.0:
			continue
		if r.size.x >= r.size.y:
			var cy := r.get_center().y
			if r.size.y >= 3.5:
				out.append([Vector2(r.position.x, cy + 1.0), Vector2(r.end.x, cy + 1.0), true])   # eastbound (right = south)
				out.append([Vector2(r.end.x, cy - 1.0), Vector2(r.position.x, cy - 1.0), true])
			else:
				out.append([Vector2(r.position.x, cy), Vector2(r.end.x, cy), false])
		else:
			var cx := r.get_center().x
			if r.size.x >= 3.5:
				out.append([Vector2(cx - 1.0, r.position.y), Vector2(cx - 1.0, r.end.y), true])   # southbound (right = west)
				out.append([Vector2(cx + 1.0, r.end.y), Vector2(cx + 1.0, r.position.y), true])
			else:
				out.append([Vector2(cx, r.position.y), Vector2(cx, r.end.y), false])
	return out


static func _node(G: Dictionary, idx: Dictionary, p: Vector2) -> int:
	var k := Vector2i(roundi(p.x * 100.0), roundi(p.y * 100.0))
	if idx.has(k):
		return int(idx[k])
	(G.pos as Array).append(p)
	(G.adj as Array).append([])
	idx[k] = (G.pos as Array).size() - 1
	return int(idx[k])


static func _edge(G: Dictionary, a: int, b: int, tag: int = -1, check := true, cost := 1.0) -> void:
	if a == b:
		return
	var pa: Vector2 = G.pos[a]
	var pb: Vector2 = G.pos[b]
	for e in G.adj[a]:
		if int(e[0]) == b:
			return
	if check and not _lane_clear(G, pa, pb, tag):
		return
	(G.adj[a] as Array).append([b, pa.distance_to(pb) * cost, tag])


static func _nearest(G: Dictionary, p: Vector2) -> int:
	var best := -1
	var bd := 1e9
	for i in (G.pos as Array).size():
		var d := p.distance_to(G.pos[i])
		if d < bd:
			bd = d
			best = i
	return best


static func _free2(G: Dictionary, p: Vector2, side: Vector2) -> bool:
	return not _solid_at(G, p + side * 0.4, -1) and not _solid_at(G, p - side * 0.4, -1)


## The first lane centre-line across direction d (axis aligned) that point p meets moving along d: distance, or -1.
static func _cross_at(lines: Array, p: Vector2, d: Vector2, maxd: float, skip: int) -> float:
	var best := -1.0
	for i in lines.size():
		if i == skip:
			continue
		var L: Array = lines[i]
		var ld := ((L[1] as Vector2) - (L[0] as Vector2)).normalized()
		if absf(ld.dot(d)) > 0.01:
			continue
		var t := ((L[0] as Vector2) - p).dot(d)
		var q := p + d * t
		var u := (q - (L[0] as Vector2)).dot(ld)
		if t > 0.3 and t <= maxd and u >= -0.01 and u <= (L[0] as Vector2).distance_to(L[1]) + 0.01 and (best < 0.0 or t < best):
			best = t
	return best


## Extra centre-lines derived from the layout: the gate column runs on north over open drive ground to the first cross
## lane (vehicles turn there, clear of the yard buildings' corners); each staging bay gets a lead-in line across its
## approach (the U over the open pad) and an exit line straight ahead to the first cross lane.
static func _extra_lines(c: Dictionary, G: Dictionary, lines: Array, gate_line: int) -> void:
	var gl: Array = lines[gate_line]
	var top: Vector2 = gl[0]
	var dn := Vector2(0, -1)
	var cr := _cross_at(lines, top, dn, 6.0, gate_line)
	if cr > 0.0:
		var k := 0.0
		while k < cr and _free2(G, top + dn * (k + 0.25), Vector2(1, 0)):
			k += 0.25
		if k >= cr - 0.26:
			gl[0] = top + dn * cr
	var leads := {}
	for b in bays(c):
		var bp: Vector2 = b[0]
		var bd := Vector2.from_angle(float(b[1])).round()
		var pd := Vector2(-bd.y, bd.x)
		var un := bp - bd * 2.6
		var ends := []
		var xs := []
		for sg in [-1.0, 1.0]:
			var k := 0.0
			var cx := _cross_at(lines, un, pd * sg, 10.0, -1)
			while k < 10.0 and _free2(G, un + pd * sg * (k + 0.25), bd):
				k += 0.25
				if cx > 0.0 and k >= cx:
					k = cx
					break
			ends.append(un + pd * sg * k)
			xs.append(cx > 0.0 and k >= cx - 0.001)
		var key := "%d" % roundi(un.dot(bd.abs()) * 100.0)
		if leads.has(key):
			var L0: Array = leads[key]
			var ax := ((L0[1] as Vector2) - (L0[0] as Vector2)).normalized()
			for q in ends:
				if (q - (L0[0] as Vector2)).dot(ax) < 0.0:
					L0[0] = q
				if (q - (L0[1] as Vector2)).dot(ax) > 0.0:
					L0[1] = q
		else:   # one way, in from the end that meets a lane (two-way when both or neither do)
			if bool(xs[1]) and not bool(xs[0]):
				leads[key] = [ends[1], ends[0], true, "lead"]
			elif bool(xs[0]) and not bool(xs[1]):
				leads[key] = [ends[0], ends[1], true, "lead"]
			else:
				leads[key] = [ends[0], ends[1], false, "lead"]
			lines.append(leads[key])
		var xc := _cross_at(lines, bp, bd, 4.0, -1)
		if xc > 0.0:
			lines.append([bp, bp + bd * xc, true, "exit"])


## The lane graph of the current layout (static cache, rebuilt when the layout json changes).
static func graph() -> Dictionary:
	var c := CnFacility.conf()
	var sig := _layout_sig(c)
	if not _G.is_empty() and String(_G.sig) == sig:
		return _G
	_fit_cache.clear()
	var cs := float(c.compound)
	var G := {"sig": sig, "cs": int(c.compound), "grid": _raster(c), "pos": [], "adj": [], "zones": [],
		"gacc": [], "park": [], "door": [], "bay": [], "bayh": [], "wash": [], "exit": -1, "entry": -1, "keep": []}
	var idx := {}
	var lines := _lines(c)
	var go := _rect(c.get("gate_outer", [0, 0, 0, 0]))
	var gi := _rect(c.get("gate_inner", c.get("gate_outer", [0, 0, 0, 0])))
	var gx := go.get_center().x
	lines.append([Vector2(gx, gi.position.y), Vector2(gx, cs + 6.6), false])
	var gate_line := lines.size() - 1
	for L in lines:   # extend ends up to 1 tile over free ground so lanes meeting edge to edge join
		for e in 2:
			var p: Vector2 = L[e]
			var d := (p - (L[1 - e] as Vector2)).normalized()
			var ext := 0.0
			while ext < 1.0 and not _solid_at(G, p + d * (ext + 0.25), -1):
				ext += 0.25
			L[e] = p + d * ext
	_extra_lines(c, G, lines, gate_line)
	var params := []
	for L in lines:
		params.append([0.0, (L[0] as Vector2).distance_to(L[1])])
	for i in lines.size():
		for j in range(i + 1, lines.size()):
			var A: Array = lines[i]
			var B: Array = lines[j]
			var ah := absf((A[1] - A[0]).y) < 0.01
			var bh := absf((B[1] - B[0]).y) < 0.01
			if ah == bh:
				continue
			var H: Array = A if ah else B
			var V: Array = B if ah else A
			var X := Vector2((V[0] as Vector2).x, (H[0] as Vector2).y)
			if X.x < minf(H[0].x, H[1].x) - 0.01 or X.x > maxf(H[0].x, H[1].x) + 0.01 or X.y < minf(V[0].y, V[1].y) - 0.01 or X.y > maxf(V[0].y, V[1].y) + 0.01:
				continue
			params[i].append((A[0] as Vector2).distance_to(X))
			params[j].append((B[0] as Vector2).distance_to(X))
	for gi2 in (c.get("garages", []) as Array).size():   # exact lane points in front of each garage door (back-in turn)
		var P2 := garage_park(c, gi2)
		var o2 := garage_out(c, gi2)
		for i in lines.size():
			var A2: Array = lines[i]
			if absf((A2[1] - A2[0]).x) > 0.01:
				continue
			var dx2 := ((A2[0] as Vector2).x - P2.x) * o2.x
			if dx2 < 1.5 or dx2 > 3.5 or P2.y < minf(A2[0].y, A2[1].y) or P2.y > maxf(A2[0].y, A2[1].y):
				continue
			params[i].append(absf(P2.y - (A2[0] as Vector2).y))
	for b in bays(c):   # exact bay lead-in points on their lines
		var u3: Vector2 = (b[0] as Vector2) - Vector2.from_angle(float(b[1])).round() * 2.6
		for i in lines.size():
			var A3: Array = lines[i]
			var la := (A3[0] as Vector2).distance_to(A3[1])
			var t3 := ((u3 - (A3[0] as Vector2)).dot(((A3[1] as Vector2) - (A3[0] as Vector2)) / maxf(la, 0.001)))
			if t3 >= -0.01 and t3 <= la + 0.01 and ((A3[0] as Vector2) + ((A3[1] as Vector2) - (A3[0] as Vector2)) / maxf(la, 0.001) * t3).distance_to(u3) < 0.01:
				params[i].append(t3)
	var g0y := (lines[gate_line][0] as Vector2).y
	var gate_extra := [cs + 2.5 - g0y]
	var wz := _rect(c.get("apc_wash", [0, 0, 0, 0]))
	for k in 2:   # two wash stops nose to tail (CnFacility "decon" slots)
		gate_extra.append(wz.get_center().y + (float(k) - 0.5) * 2.05 - g0y)
	params[gate_line].append_array(gate_extra)
	var xnodes := {}   # bay lead-in / exit line nodes: not joined to the plaza grid
	for i in lines.size():
		var L: Array = lines[i]
		var a: Vector2 = L[0]
		var ln := a.distance_to(L[1])
		var d := ((L[1] as Vector2) - a) / maxf(ln, 0.001)
		var ts: Array = params[i].duplicate()
		var n := ceili(ln / NODE_STEP)
		for k in n:
			var tk := ln * float(k) / float(n)
			var near := false
			for t0 in params[i]:
				if absf(float(t0) - tk) < 0.3:
					near = true
			if not near:
				ts.append(tk)
		ts.sort()
		var prev := -1
		var last := -1.0
		for t in ts:
			if float(t) - last < 0.05:
				continue
			last = float(t)
			var nd := _node(G, idx, a + d * float(t))
			if L.size() > 3:
				xnodes[nd] = true
			if prev >= 0:
				_edge(G, prev, nd)
				if not bool(L[2]):
					_edge(G, nd, prev)
			prev = nd
		if not bool(L[2]):   # two-way lanes are directional reservations
			var r := Rect2(a, Vector2.ZERO).expand(L[1]).grow_individual(0.6 if absf(d.y) > 0.5 else 0.0, 0.6 if absf(d.x) > 0.5 else 0.0, 0.6 if absf(d.y) > 0.5 else 0.0, 0.6 if absf(d.x) > 0.5 else 0.0)
			(G.zones as Array).append({"r": r, "ax": Vector2(absf(d.x), absf(d.y)).round()})
	G.exit = _nearest(G, Vector2(gx, cs + 2.5))
	G.entry = _nearest(G, Vector2(gx, cs + 6.6))
	for k in 2:
		(G.wash as Array).append(_nearest(G, Vector2(gx, wz.get_center().y + (float(k) - 0.5) * 2.05)))
	# plazas (pad, staging): open ground, a 1-tile node grid joined to everything within 1.5 tiles
	var plaza := []
	var keep_out := []   # the bays and their lead-ins: through traffic never crosses them
	for b in bays(c):
		var bd2 := Vector2.from_angle(float(b[1])).round()
		var pd2 := Vector2(-bd2.y, bd2.x)
		keep_out.append(Rect2((b[0] as Vector2) - bd2 * 2.0 - pd2 * 1.2, Vector2.ZERO).expand((b[0] as Vector2) + bd2 * 1.4 + pd2 * 1.2))
	G.keep = keep_out
	for z in PLAZAS:
		if c.has(z):
			var r := _rect(c[z])
			for y in int(r.size.y):
				for x in int(r.size.x):
					var q := r.position + Vector2(float(x) + 0.5, float(y) + 0.5)
					var out_ok := true
					for ko in keep_out:
						if (ko as Rect2).has_point(q):
							out_ok = false
					if out_ok:
						plaza.append(_node(G, idx, q))
	var bnodes := []
	var shut := []   # bay and bay-front nodes: reached only through their own lead-in
	for b in bays(c):   # a bay is entered nose first down a 2.6-tile lead-in (a U over the open pad) and left straight ahead
		var bd := Vector2.from_angle(float(b[1]))
		var un := _node(G, idx, (b[0] as Vector2) - bd * 2.6)
		var fn := _node(G, idx, (b[0] as Vector2) - bd * 1.6)
		var bn := _node(G, idx, b[0])
		shut.append(fn)
		shut.append(bn)
		bnodes.append([un, fn, bn])
		(G.bay as Array).append(bn)
		(G.bayh as Array).append(float(b[1]))
	var np := (G.pos as Array).size()
	for pn in plaza:
		for o in np:
			if o != pn and not shut.has(o) and not xnodes.has(o) and not xnodes.has(pn) and (G.pos[pn] as Vector2).distance_to(G.pos[o]) <= 1.5:
				_edge(G, pn, o, -1, true, PLAZA_COST)
				_edge(G, o, pn, -1, true, PLAZA_COST)
	for t3 in bnodes:
		_edge(G, int(t3[0]), int(t3[1]))
		_edge(G, int(t3[1]), int(t3[2]))
	# garages: park P -> door D -> any lane node within 2.6 ahead (departure); entry = back in from the lane node Gacc
	for i in (c.get("garages", []) as Array).size():
		var P := garage_park(c, i)
		var out := garage_out(c, i)
		var pn := _node(G, idx, P)
		var dn := _node(G, idx, P + out * 1.5)
		_edge(G, pn, dn, i)
		var best := -1
		var bd := 1e9
		for o in np:
			var q: Vector2 = G.pos[o]
			var v := q - (P + out * 1.5)
			var thd := acos(clampf(v.normalized().dot(out), -1.0, 1.0)) if v.length() > 0.3 else PI
			if v.length() <= 2.6 and thd <= deg_to_rad(50.0) and R_MIN * tan(thd * 0.5) <= minf(1.5 - GAR_STRAIGHT, v.length() * 0.5) + 0.001:
				_edge(G, dn, o, i)
			var dd := q.distance_to(P + out * 2.5)
			if dd < bd:
				bd = dd
				best = o
		(G.park as Array).append(pn)
		(G.door as Array).append(dn)
		(G.gacc as Array).append(best)
	G.pos = PackedVector2Array(G.pos)
	_G = G
	return G


# ================================================================ geometry: filleted polylines
## Corner at b of a->b->c with radius R: [tangent length, centre, start angle, signed turn] ([] when straight).
static func _fillet(a: Vector2, b: Vector2, c: Vector2, R: float) -> Array:
	var d1 := (b - a).normalized()
	var d2 := (c - b).normalized()
	var th := atan2(d1.cross(d2), d1.dot(d2))
	if absf(th) < 0.002:
		return []
	var t := R * tan(absf(th) * 0.5)
	var p1 := b - d1 * t
	var sg := 1.0 if th > 0.0 else -1.0
	var cc := p1 + Vector2(-d1.y * sg, d1.x * sg) * R
	return [t, cc, (p1 - cc).angle(), th]


static func _arc_clear(G: Dictionary, f: Array, R: float, rev: bool, gar: int) -> bool:
	var th := float(f[3])
	var n := maxi(2, ceili(absf(th) * R / 0.15))
	for k in n + 1:
		var a := float(f[2]) + th * float(k) / float(n)
		var h := a + (PI * 0.5 if th > 0.0 else -PI * 0.5) + (PI if rev else 0.0)
		if not pose_clear(G, (f[1] as Vector2) + Vector2(cos(a), sin(a)) * R, h, gar, PLAN_M):
			return false
	return true


## Straight the body keeps at a garage end of a route (the arc starts / ends no deeper than 0.5 inside the door).
const GAR_STRAIGHT := 1.0


static func _is_park(G: Dictionary, p: Vector2) -> bool:
	var pos: PackedVector2Array = G.pos
	for pn in G.park:
		if p.distance_to(pos[int(pn)]) < 0.05:
			return true
	return false


## Corner b of a -> b -> c: the largest radius (R_MAX down to 0.6, steps of 0.1) whose fillet fits the tangent budgets
## (bp on a-b, bn on b-c) and keeps the body clear of every footprint; 0.0 when none does. Straight: R_MAX.
## Budgets: a segment shared by two corners is split half and half, so corners never interfere (the router and
## build_prims use the same rule, the route geometry is a pure function of its polyline).
static func _corner(G: Dictionary, a: Vector2, b: Vector2, c: Vector2, bp: float, bn: float, rev: bool, gar: int) -> float:
	var f0 := _fillet(a, b, c, 1.0)
	if f0.is_empty():
		return R_MAX
	var tn := float(f0[0])
	var rb := minf(R_MAX, minf(bp, bn) / tn)
	if rb < 0.6 - 0.001:
		return 0.0
	var key := "%s|%s|%s|%d|%d|%d" % [b, (b - a).normalized().snappedf(0.001), (c - b).normalized().snappedf(0.001), int(rev), gar, int(rb * 1000.0)]
	if _fit_cache.has(key):
		return float(_fit_cache[key])
	var R := floorf(rb * 10.0 + 0.0001) / 10.0
	var best := 0.0
	while R >= 0.6 - 0.001:
		if _arc_clear(G, _fillet(a, b, c, R), R, rev, gar):
			best = R
			break
		R -= 0.1
	_fit_cache[key] = best
	return best


## Tangent budgets of corner i of polyline pts: [on the segment before, on the segment after].
static func _budgets(G: Dictionary, pts: PackedVector2Array, i: int) -> Array:
	var n := pts.size()
	var lp := pts[i - 1].distance_to(pts[i])
	var ln := pts[i].distance_to(pts[i + 1])
	var bp := lp - (GAR_STRAIGHT if _is_park(G, pts[0]) else 0.0) if i == 1 else lp * 0.5
	var bn := ln - (GAR_STRAIGHT if _is_park(G, pts[n - 1]) else 0.0) if i == n - 2 else ln * 0.5
	return [bp, bn]


static func _collapse(raw: PackedVector2Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for q in raw:
		if pts.is_empty() or q.distance_to(pts[pts.size() - 1]) > 0.001:
			pts.append(q)
	var k := PackedVector2Array()
	if not pts.is_empty():
		k.append(pts[0])
	for i in range(1, pts.size() - 1):
		var a := k[k.size() - 1]
		var d1 := pts[i] - a
		var d2 := pts[i + 1] - pts[i]
		if absf(d1.normalized().cross(d2.normalized())) > 0.002 or d1.dot(d2) < 0.0:
			k.append(pts[i])
	if pts.size() > 1:
		k.append(pts[pts.size() - 1])
	return k


## Polyline -> primitives: line [0, a, b, rev, len] / arc [1, centre, R, a0, turn, rev, len]; also the smallest radius.
static func build_prims(G: Dictionary, raw: PackedVector2Array, rev: bool, gar: int) -> Dictionary:
	var pts := _collapse(raw)
	var n := pts.size()
	var Rs := PackedFloat64Array()
	var ts := PackedFloat64Array()
	Rs.resize(n)
	ts.resize(n)
	for i in range(1, n - 1):
		# ORCH (CNROLE7 hang, board sim.hang.walkers): a route that doubles straight back (a cusp) has no fillet: the
		# tangent length tan(theta/2) goes to infinity and the route became ~1.6e15 tiles long, so the zone / gate-mark
		# walks never ended. A cusp is a stop-and-reverse point: drawn as two straight lines meeting at it.
		if (pts[i] - pts[i - 1]).normalized().dot((pts[i + 1] - pts[i]).normalized()) < -0.95:
			continue
		var bg: Array = _budgets(G, pts, i)
		var f1 := _fillet(pts[i - 1], pts[i], pts[i + 1], 1.0)
		if f1.is_empty():
			continue
		var R := _corner(G, pts[i - 1], pts[i], pts[i + 1], float(bg[0]), float(bg[1]), rev, gar)
		if R <= 0.0:   # nothing clears: the largest radius the budgets allow (the route test reports it)
			R = maxf(0.05, minf(R_MAX, minf(float(bg[0]), float(bg[1])) / float(f1[0])))
		Rs[i] = R
		ts[i] = float(f1[0]) * R
	var prims := []
	var rmin := 99.0
	if n < 2:
		return {"prims": prims, "rmin": rmin}
	var cur := pts[0]
	for i in range(1, n):
		if i < n - 1 and ts[i] > 0.0:
			var f := _fillet(pts[i - 1], pts[i], pts[i + 1], Rs[i])
			var p1 := pts[i] - (pts[i] - pts[i - 1]).normalized() * float(f[0])
			if cur.distance_to(p1) > 0.001:
				prims.append([0, cur, p1, rev, cur.distance_to(p1)])
			prims.append([1, f[1], Rs[i], f[2], f[3], rev, absf(float(f[3])) * Rs[i]])
			rmin = minf(rmin, Rs[i])
			cur = pts[i] + (pts[i + 1] - pts[i]).normalized() * float(f[0])
		elif i == n - 1 or (pts[i] - pts[i - 1]).normalized().dot((pts[i + 1] - pts[i]).normalized()) < -0.95:
			if cur.distance_to(pts[i]) > 0.001:   # end point, or a cusp (ORCH: stop-and-reverse point, see above)
				prims.append([0, cur, pts[i], rev, cur.distance_to(pts[i])])
			cur = pts[i]
	return {"prims": prims, "rmin": rmin}


## Pose on primitive pr at local arc length s: [pos, heading].
static func prim_pose(pr: Array, s: float) -> Array:
	if int(pr[0]) == 0:
		var a: Vector2 = pr[1]
		var b: Vector2 = pr[2]
		var L := maxf(float(pr[4]), 0.0001)
		return [a + (b - a) * clampf(s / L, 0.0, 1.0), (b - a).angle() + (PI if bool(pr[3]) else 0.0)]
	var th := float(pr[4])
	var R := float(pr[2])
	var ang := float(pr[3]) + clampf(s / R, 0.0, absf(th)) * (1.0 if th > 0.0 else -1.0)
	return [(pr[1] as Vector2) + Vector2(cos(ang), sin(ang)) * R, ang + (PI * 0.5 if th > 0.0 else -PI * 0.5) + (PI if bool(pr[5]) else 0.0)]


static func prim_len(pr: Array) -> float:
	return float(pr[4]) if int(pr[0]) == 0 else float(pr[6])


# ================================================================ routing (Dijkstra over (node, came-from))
static func _hpush(h: Array, it: Array) -> void:
	h.append(it)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if float(h[p][0]) <= float(h[i][0]):
			break
		var t = h[p]
		h[p] = h[i]
		h[i] = t
		i = p


static func _hpop(h: Array) -> Array:
	var top: Array = h[0]
	var last = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < h.size() and float(h[l][0]) < float(h[m][0]):
				m = l
			if r < h.size() and float(h[r][0]) < float(h[m][0]):
				m = r
			if m == i:
				break
			var t = h[m]
			h[m] = h[i]
			h[i] = t
			i = m
	return top


static func _dijkstra(G: Dictionary, start: int, dir0: Vector2, gar: int, goal: Callable, banned := {}) -> PackedInt32Array:
	var pos: PackedVector2Array = G.pos
	var heap := []
	var best := {}
	var par := {}
	var maxth := deg_to_rad(100.0)
	_hpush(heap, [0.0, start, -1, -1])
	while not heap.is_empty():
		var it := _hpop(heap)
		var n := int(it[1])
		var pv := int(it[2])
		var key := n * 4096 + pv + 1
		if best.has(key):
			continue
		best[key] = true
		par[key] = int(it[3])
		var din := dir0 if pv < 0 else (pos[n] - pos[pv]).normalized()
		if pv >= 0 and goal.call(n, din):
			var out := PackedInt32Array()
			var k := key
			while k >= 0:
				out.append(k / 4096)
				k = int(par[k])
			out.reverse()
			return out
		for e in G.adj[n]:
			var m := int(e[0])
			var tag := int(e[2])
			if m == pv or (tag >= 0 and tag != gar) or best.has(m * 4096 + n + 1) or banned.has(n * 65536 + m):
				continue
			var th := acos(clampf(din.dot((pos[m] - pos[n]).normalized()), -1.0, 1.0))
			if th > maxth:
				continue
			_hpush(heap, [float(it[0]) + float(e[1]) + 0.8 * th, m, n, key])
	return PackedInt32Array()


## Place names (compound-local): "g<i>" garage i, "b<j>" staging bay j, "w<k>" wash stop k, "x" out past the outer gate,
## "e" the gate apron entry. Returns legs [[rev 0/1, PackedVector2Array raw polyline], ...] ([] = no route).
## pre: extra leading points (a vehicle joining at the entry from its own pose).
static func plan(from: String, to: String, gar: int, pre := PackedVector2Array()) -> Array:
	var G := graph()
	var c := CnFacility.conf()
	var pos: PackedVector2Array = G.pos
	var start := -1
	var dir0 := Vector2(0, -1)
	var ix := int(from.substr(1)) if from.length() > 1 else 0
	match from.left(1):
		"g":
			if ix >= (G.park as Array).size():
				return []
			start = int(G.park[ix])
			dir0 = garage_out(c, ix)
		"b":
			if ix >= (G.bay as Array).size():
				return []
			start = int(G.bay[ix])
			dir0 = Vector2.from_angle(float(G.bayh[ix]))
		"w":
			start = int(G.wash[mini(ix, 1)])
		"n":   # a lane node, reached from pre[0] (re-route while driving)
			start = ix
			if not pre.is_empty():
				dir0 = (pos[start] - pre[0]).normalized()
		_:
			start = int(G.entry)
			if pre.size() >= 1:
				dir0 = (pos[start] - pre[pre.size() - 1]).normalized()
	var jx := int(to.substr(1)) if to.length() > 1 else 0
	var goal: Callable
	match to.left(1):
		"b":
			if jx >= (G.bay as Array).size():
				return []
			var bn := int(G.bay[jx])
			var bd := Vector2.from_angle(float(G.bayh[jx]))
			goal = func(n: int, din: Vector2) -> bool: return n == bn and din.dot(bd) > 0.95
		"g":
			if jx >= (G.gacc as Array).size():
				return []
			var gn := int(G.gacc[jx])
			var out := garage_out(c, jx)
			var gj := jx
			goal = func(n: int, din: Vector2) -> bool:
				return n == gn and absf(din.dot(out)) < 0.3 and _seg_clear(G, pos[n], pos[n] + din * 1.5, gj)
		"w":
			var wn := int(G.wash[mini(jx, 1)])
			goal = func(n: int, din: Vector2) -> bool: return n == wn and din.y < -0.9
		_:
			var xn := int(G.exit)
			goal = func(n: int, din: Vector2) -> bool: return n == xn and din.y > 0.9
	var banned := {}
	var pulled := PackedVector2Array()
	var gp := Vector2.ZERO
	for attempt in 12:   # a lane-node path the radius pull cannot drive: ban the edge it got stuck on, search again
		var path := _dijkstra(G, start, dir0, gar, goal, banned)
		if path.is_empty():
			return []
		var pts := pre.duplicate()
		var pin := []
		for q in pre:
			pin.append(true)
		for i in path.size():
			pts.append(pos[path[i]])
			pin.append(i == 0 or (i == path.size() - 1 and to.left(1) != "g"))   # start and goal stay exact
		gp = pos[path[path.size() - 1]]
		var din := (gp - pos[path[path.size() - 2]]).normalized()
		var dirn := din
		if to.left(1) == "g":   # back in: pull 1.5 past the lane point, stop, reverse into the garage (nose out)
			pts.append(gp + din * 1.5)
			pin.append(true)
		elif to.left(1) == "b":
			dirn = Vector2.from_angle(float(G.bayh[jx]))
		elif to.left(1) == "w":
			dirn = Vector2(0, -1)
		elif to.left(1) == "x" or to == "":
			dirn = Vector2(0, 1)
		var d0 := dir0 if pre.size() < 2 else (pre[1] - pre[0]).normalized()
		pulled = _pull(G, pts, pin, gar, d0, dirn)
		if not pulled.is_empty():
			break
		var k := clampi(_dbg_deep - pre.size(), 1, path.size() - 1)
		banned[path[k - 1] * 65536 + path[k]] = true
		if OS.has_environment("FD7_DBG"):
			var sdb := ""
			for q in pts:
				sdb += "(%.1f,%.1f)" % [q.x, q.y]
			print("FD7 no radius cut ", from, "->", to, " try ", attempt, " deepest ", pts[_dbg_deep], " ", sdb)
		if attempt == 11:
			pulled = _pull_plain(G, pts, pin, gar)
	if to.left(1) == "g":
		var P := garage_park(c, jx)
		var S := pulled[pulled.size() - 1]
		return [[0, pulled], [1, PackedVector2Array([S, gp, P + garage_out(c, jx) * 1.0, P])]]
	return [[0, pulled]]


## Plans are a pure function of the layout: cached per (from, to, garage) until the layout changes.
static var _plan_cache: Dictionary = {}
static var _dbg_deep := 0


static func plan_cached(from: String, to: String, gar: int) -> Array:
	var G := graph()
	var key := "%s|%s|%d" % [from, to, gar]
	if String(_plan_cache.get("sig", "")) != String(G.sig):
		_plan_cache = {"sig": String(G.sig)}
	if not _plan_cache.has(key):
		_plan_cache[key] = plan(from, to, gar)
	return _plan_cache[key]


## String pulling with a turning radius: picks the fewest, longest straights over the route's lane nodes such that
## every straight keeps the body clear and every corner takes a fillet of R >= R_MIN that clears every footprint
## (depth-first, farthest cut first, failed (prev, here) pairs remembered). The first straight follows the start
## heading d0 and the last one arrives on the goal heading dn (no heading snaps). [] when no such cut exists.
static func _pull(G: Dictionary, pts: PackedVector2Array, pin: Array, gar: int, d0: Vector2, dn: Vector2) -> PackedVector2Array:
	var n := pts.size()
	if n < 2:
		return pts
	var own := []   # keep-out boxes of the start / goal bay (a route may only cross its own bay's box)
	for kr in G.keep:
		if (kr as Rect2).has_point(pts[0]) or (kr as Rect2).has_point(pts[n - 1]):
			own.append(kr)
	var ctx := {"G": G, "pts": pts, "pin": pin, "gar": gar, "d0": d0, "dn": dn, "memo": {}, "sp": _is_park(G, pts[0]), "ep": _is_park(G, pts[n - 1]), "own": own}
	var chain := PackedInt32Array([0])
	_dbg_deep = 0
	if not _pull_from(ctx, -1, 0, 0.0, chain):
		return PackedVector2Array()
	var out := PackedVector2Array()
	for k in chain:
		out.append(pts[k])
	return out


static func _crosses_keep(G: Dictionary, a: Vector2, b: Vector2, own: Array) -> bool:
	var n := maxi(1, ceili(a.distance_to(b) / 0.2))
	for kr in G.keep:
		if own.has(kr):
			continue
		var r: Rect2 = (kr as Rect2).grow(0.35)
		for k in n + 1:
			if r.has_point(a.lerp(b, float(k) / float(n))):
				return true
	return false


## Straight part of a -> b between the tangent points (ta from a, tb before b): the full body stays clear.
static func _straight_clear(G: Dictionary, a: Vector2, b: Vector2, ta: float, tb: float, gar: int) -> bool:
	var d := (b - a).normalized()
	return _seg_clear(G, a + d * ta, b - d * tb, gar)


## State: came from p to i, the corner at p used tp of p -> i. Picks the next vertex j (farthest first).
static func _pull_from(ctx: Dictionary, p: int, i: int, tp: float, chain: PackedInt32Array) -> bool:
	var G: Dictionary = ctx.G
	var pts: PackedVector2Array = ctx.pts
	var pin: Array = ctx.pin
	var gar := int(ctx.gar)
	var n := pts.size()
	if i > _dbg_deep:
		_dbg_deep = i
	if i == n - 1:
		return p < 0 or _straight_clear(G, pts[p], pts[i], tp, 0.0, gar)
	var mkey := "%d|%d|%d" % [p, i, roundi(tp * 1000.0)]
	if ctx.memo.has(mkey):
		return false
	var jmax := mini(n - 1, i + 14)
	for k in range(i + 1, jmax):
		if bool(pin[k]):
			jmax = k
			break
	var d0: Vector2 = ctx.d0
	var dn: Vector2 = ctx.dn
	for j in range(jmax, i, -1):
		var L := pts[i].distance_to(pts[j])
		if L > 7.0 and j > i + 1:
			continue
		var d := (pts[j] - pts[i]) / maxf(L, 0.0001)
		if p < 0 and d0 != Vector2.ZERO and d.dot(d0) < 0.9987:
			continue
		if j == n - 1 and dn != Vector2.ZERO and d.dot(dn) < 0.9987:
			continue
		if not _lane_clear(G, pts[i], pts[j], gar) or _crosses_keep(G, pts[i], pts[j], ctx.own):
			continue
		var ti := 0.0
		if p >= 0:
			var lp := pts[p].distance_to(pts[i])
			var bp := lp - (GAR_STRAIGHT if bool(ctx.sp) else 0.0) if p == 0 else lp * 0.5
			var bn := L - (GAR_STRAIGHT if bool(ctx.ep) else 0.0) if j == n - 1 else L * 0.5
			var R := _corner(G, pts[p], pts[i], pts[j], bp, bn, false, gar)
			if R < R_MIN - 0.001:
				continue
			var f1 := _fillet(pts[p], pts[i], pts[j], 1.0)
			ti = 0.0 if f1.is_empty() else float(f1[0]) * R
			if not _straight_clear(G, pts[p], pts[i], tp, ti, gar):
				continue
		chain.append(j)
		if _pull_from(ctx, i, j, ti, chain):
			return true
		chain.resize(chain.size() - 1)
	ctx.memo[mkey] = true
	return false


## Plain string pulling (no radius check): only when no cut with a turning radius exists (the route test reports it).
static func _pull_plain(G: Dictionary, pts: PackedVector2Array, pin: Array, gar: int) -> PackedVector2Array:
	var n := pts.size()
	if n < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	var i := 0
	while i < n - 1:
		var best := i + 1
		for j in range(i + 2, mini(n, i + 12)):
			if bool(pin[j - 1]) or pts[i].distance_to(pts[j]) > 7.0 or not _seg_clear(G, pts[i], pts[j], gar):
				break
			best = j
		out.append(pts[best])
		i = best
	return out


static func _flat(p: PackedVector2Array) -> Array:
	var out := []
	for q in p:
		out.append(_snap(q.x))
		out.append(_snap(q.y))
	return out


static func _unflat(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, a.size() - 1, 2):
		out.append(Vector2(float(a[i]), float(a[i + 1])))
	return out


# ================================================================ state + orders
static var force_on := false   # tests: drive before ORCH has put this system in SimWorld.SYSTEM_ORDER
static var _reg := -1


static func registered() -> bool:
	if _reg < 0:
		_reg = 0
		for s in SimWorld.SYSTEM_ORDER:
			if s is Script and (s as Script).resource_path == "res://sim/systems/fac_drive7.gd":
				_reg = 1
	return _reg == 1 or force_on


static func st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"v": {}, "seq": 0}
	return w.sys_state[KEY]


static func vstate(w: SimWorld, id: int) -> Dictionary:
	if not w.sys_state.has(KEY):
		return {}
	return w.sys_state[KEY].v.get(str(id), {})


static func _origin(w: SimWorld, fid: int) -> Vector2:
	var F := CnFacility.fac(w, fid)
	return Vector2(CnFacility.origin(F)) if not F.is_empty() else Vector2.ZERO


## Compound-local pose of a place: [pos, heading].
static func place_pose(place: String) -> Array:
	var G := graph()
	var c := CnFacility.conf()
	var i := int(place.substr(1)) if place.length() > 1 else 0
	match place.left(1):
		"g":
			return [garage_park(c, i), garage_out(c, i).angle()]
		"b":
			return [G.pos[int(G.bay[i])], float(G.bayh[i])]
		"w":
			return [G.pos[int(G.wash[mini(i, 1)])], -PI * 0.5]
	return [G.pos[int(G.exit)], PI * 0.5]


## Where a vehicle at compound-local p stands: "g<i>" / "b<j>" / "w<k>", "out" outside the compound, "" elsewhere.
static func place_at(p: Vector2) -> String:
	var G := graph()
	var c := CnFacility.conf()
	for i in (c.get("garages", []) as Array).size():
		if p.distance_to(garage_park(c, i)) < 0.7:
			return "g%d" % i
	for j in (G.bay as Array).size():
		if p.distance_to(G.pos[int(G.bay[j])]) < 0.7:
			return "b%d" % j
	for k in 2:
		if p.distance_to(G.pos[int(G.wash[k])]) < 0.7:
			return "w%d" % k
	var cs := float(c.compound)
	return "out" if not Rect2(0, 0, cs, cs).has_point(p) else ""


static func _bay_taken(S: Dictionary, j: int, me: int) -> bool:
	var b := "b%d" % j
	for k in S.v:
		var V: Dictionary = S.v[k]
		if int(V.id) == me:
			continue
		if (String(V.st) == "park" and String(V.at) == b) or String(V.to) == b or String(V.get("rel", "")) == b:
			return true
	return false


static func _free_bay(S: Dictionary, me: int) -> int:
	var nb := (graph().bay as Array).size()
	for j in range(nb - 1, -1, -1):   # the front bay (nearest the spine) first
		if not _bay_taken(S, j, me):
			return j
	return -1


## Registers / re-targets APC e: to = "g<i>" | "b" (any bay) | "b<j>" | "w<k>" | "x" (out; tgt world point or []).
## who = "fac" (CnFacility flow) | "player". False when the vehicle cannot be driven by the controller.
static func order(w: SimWorld, e: Dictionary, fid: int, to: String, who: String, tgt: Array = [], then := "", gar := -2, loose := false) -> bool:
	var S := st(w)
	var key := str(int(e.id))
	var o := _origin(w, fid)
	var V: Dictionary = S.v.get(key, {})
	if V.is_empty():
		var at := place_at(Vector2(e.pos) - o)
		if at == "" and (loose or _by_gate(Vector2(e.pos) - o)):
			at = "out"   # REGFIX7: between places (gate mouth / ECP after a hand-off): managed like an APC outside, so it is rinsed
		if at == "":
			# FLOWC7 (facint7): inside the compound but between places (e.g. just unloaded down the stealth dropship's
			# ramp at the helipad): join the lanes at the nearest lane node (route starts at its own pose, see _go)
			# instead of refusing; fd7_go garage / bays was accepted and silently did nothing.
			var pl := Vector2(e.pos) - o
			var csz := float(CnFacility.conf().compound)
			var nn := _nearest(graph(), pl) if Rect2(0, 0, csz, csz).has_point(pl) else -1
			if nn >= 0 and (graph().pos[nn] as Vector2).distance_to(pl) < 2.5:
				at = "n%d" % nn
		if at == "":
			return false
		V = {"id": int(e.id), "fac": fid, "seq": 0, "st": "park" if at != "out" else "out", "at": at, "to": "", "then": "",
			"tgt": [], "gar": -1, "who": who, "legs": [], "rv": 0, "leg": 0, "s": 0.0, "v": 0.0, "gw": 0, "t0": w.tick, "rel": ""}
		S.v[key] = V
	if gar >= -1:
		V.gar = gar
	if to == "g" or (to.left(1) == "g" and to.length() == 1):
		to = "g%d" % int(V.gar) if int(V.gar) >= 0 else "b"
	S.seq = int(S.seq) + 1
	V.seq = int(S.seq)
	V.who = who
	V.tgt = tgt.duplicate()
	V.then = then
	V.t0 = w.tick
	if to == "b":
		var j := _free_bay(S, int(e.id))
		to = "b%d" % j if j >= 0 else "bq"
	V.to = to
	var stn := String(V.st)
	if stn == "hold" and not (V.legs as Array).is_empty():   # stopped mid-route: roll on and re-route at the next straight
		V.st = "drive"
		stn = "drive"
		_set_order(w, e, Vector2(e.pos), false)
	if stn == "drive" or stn == "approach":
		V.pend = true   # re-planned when the current route ends at its place (approach: right away below)
		if stn == "approach":
			V.erase("pend")
		return true
	_go(w, V, e)
	return true


## G7 REGFIX7: compound-local p is in the gate mouth (between the gate exit node and the apron), where _handoff leaves APCs.
static func _by_gate(p: Vector2) -> bool:
	var G := graph()
	var ex: Vector2 = G.pos[int(G.exit)]
	var en: Vector2 = G.pos[int(G.entry)]
	return p.distance_to(ex) < 7.0 or p.distance_to(en + Vector2(0, 2.0)) < 7.0


## Starts V towards V.to from where it stands (parked place, or outside -> approach the gate apron first).
static func _go(w: SimWorld, V: Dictionary, e: Dictionary) -> void:
	V.erase("pend")
	var to := String(V.to)
	var o := _origin(w, int(V.fac))
	if to == "bq":   # both bays taken: wait where it is, in order
		V.st = "queue"
		_set_order(w, e, o + Vector2(place_pose(String(V.at))[0]) if String(V.at) != "out" else Vector2(e.pos), false)
		return
	var at := String(V.at)
	if at == "out" or at == "":
		if to == "x":
			_handoff(w, V, e)
			return
		V.st = "approach"
		V.ap = 0
		_approach(w, V, e)
		return
	if at == to:
		_arrive(w, V, e)
		return
	var legs := plan(at, to, int(V.gar), PackedVector2Array([Vector2(e.pos) - o])) if at.left(1) == "n" else plan_cached(at, to, int(V.gar))   # FLOWC7: "n<node>" = joining from its own pose
	if legs.is_empty():
		V.st = "park"
		return
	_set_legs(V, legs)
	V.rto = to
	if at.left(1) == "b":
		V.rel = at   # the bay stays taken until the APC has pulled clear of it
	V.st = "drive"
	_set_order(w, e, o + Vector2(place_pose(to)[0]), false)


static func _ap() -> Vector2:   # approach point on the gate apron (compound-local), Movement brings APCs here
	var G := graph()
	return (G.pos[int(G.entry)] as Vector2) + Vector2(0, 1.6)


static func _set_legs(V: Dictionary, legs: Array) -> void:
	var out := []
	for l in legs:
		out.append([int(l[0]), _flat(l[1])])
	V.legs = out
	V.rv = int(V.rv) + 1
	V.leg = 0
	V.s = 0.0
	V.v = 0.0
	V.gw = 0


## The controller's own order on a driven APC. While it rolls, a never-served path request marks it as "waiting" for
## Movement (which then neither moves it nor resets the order), so a player stop / hold shows up as a changed order.
const PATH_WAIT := 1 << 30


static func _set_order(w: SimWorld, e: Dictionary, dest: Vector2, mv: bool) -> void:
	Movement.stop_path(e)
	e.moving = mv
	if mv:
		e.path_req = PATH_WAIT
	e.order = {"type": "move", "target": dest, "fd7": 1}
	HotState.touch(w, int(e.id))


static func _arrive(w: SimWorld, V: Dictionary, e: Dictionary) -> void:
	var to := String(V.get("rto", V.to))
	V.at = to
	V.legs = []
	V.v = 0.0
	V.s = 0.0
	if to == "x":
		if String(V.to) != "x" and String(V.to) != "":   # re-targeted on the way out (one-way gate lane): turn round outside
			V.at = "out"
			V.erase("rto")
			_go(w, V, e)
			return
		_handoff(w, V, e)
		return
	var o := _origin(w, int(V.fac))
	var pp: Array = place_pose(to)
	HotState.set_pos(w, int(e.id), _wsnap(o + Vector2(pp[0])))
	e.facing = snappedf(wrapf(float(pp[1]), -PI, PI), 0.001)
	if String(V.to) != to and String(V.to) != "":   # re-targeted while driving
		_go(w, V, e)
		return
	if to.left(1) == "w" and String(V.then) != "":
		V.st = "rinse"
		V.rt = w.tick
		_set_order(w, e, o + Vector2(pp[0]), false)
		return
	V.st = "park"
	Movement.stop_path(e)
	e.order = {"type": "idle"}
	HotState.touch(w, int(e.id))
	if String(V.who) == "player":
		_sync_team(w, int(e.get("cn_team", 0)))


static func _wsnap(p: Vector2) -> Vector2:
	return Vector2(snappedf(p.x, 1.0 / 1024.0), snappedf(p.y, 1.0 / 1024.0))


## Out past the outer gate: hand the APC back to Movement (on to its target, or a dispersal spot clear of the gate lane).
static func _handoff(w: SimWorld, V: Dictionary, e: Dictionary) -> void:
	var o := _origin(w, int(V.fac))
	st(w).v.erase(str(int(V.id)))
	var tg: Array = V.tgt
	if tg.size() == 2:
		Movement.order_move(w, e, Vector2(float(tg[0]), float(tg[1])))
	else:
		var dx: float = [-3.0, 3.0, -6.0, 6.0][int(V.seq) % 4]
		Movement.order_move(w, e, o + Vector2(graph().pos[int(graph().exit)]) + Vector2(dx, 3.0))
	if String(V.who) == "player":
		_sync_team(w, int(e.get("cn_team", 0)))


## Player-driven APCs keep their CnFacility team phase honest: all out -> "out"; all parked in garages -> "garage".
static func _sync_team(w: SimWorld, tid: int) -> void:
	var T := CnFacility.team(w, tid)
	if T.is_empty():
		return
	var S := st(w)
	var all_out := true
	var all_home := true
	for aid in T.apcs:
		var V: Dictionary = S.v.get(str(int(aid)), {})
		if not V.is_empty():
			all_out = false
		if V.is_empty() or String(V.st) != "park" or String(V.at).left(1) != "g":
			all_home = false
	if all_out and String(T.phase) in ["garage", "to_pad", "loading", "to_gate"]:
		T.phase = "out"
		w.emit("CnTeamOut", {"team": tid, "fac": int(T.fac), "owner": int(T.owner)})
	elif all_home and String(T.phase) == "out":
		T.phase = "garage"
		w.emit("CnTeamParked", {"team": tid, "fac": int(T.fac), "owner": int(T.owner)})


## Destination of a plain move order to world point p for APC V: own garage, a bay, or out to the point.
static func classify(w: SimWorld, V: Dictionary, p: Vector2) -> Array:
	var c := CnFacility.conf()
	var lt := p - _origin(w, int(V.fac))
	var cs := float(c.compound)
	if not Rect2(0, 0, cs, cs).has_point(lt):
		return ["x", [_snap(p.x), _snap(p.y)]]
	var gz: Array = c.get("garage_size", [3, 3])
	for i in (c.get("garages", []) as Array).size():
		if Rect2(garage_park(c, i) - Vector2(float(gz[0]), float(gz[1])) * 0.5, Vector2(float(gz[0]), float(gz[1]))).has_point(lt):
			return ["g%d" % (int(V.gar) if int(V.gar) >= 0 else i), []]
	for z in PLAZAS:
		if c.has(z) and _rect(c[z]).grow(0.5).has_point(lt):
			return ["b", []]
	return ["g%d" % int(V.gar) if int(V.gar) >= 0 else "b", []]


## CnFacility hook (_order_slots): drives a team's APCs to `where` (pad | gate | decon | inner | garage).
## False = not handled (system not registered, unknown facility): CnFacility then uses Movement as before.
static func order_team(w: SimWorld, T: Dictionary, aps: Array, where: String) -> bool:
	if not registered() or CnFacility.fac(w, int(T.fac)).is_empty():
		return false
	var sl: Array = T.get("slots", [])
	var o := _origin(w, int(T.fac))
	var gx := Vector2(graph().pos[int(graph().exit)]) + o
	var order_i := range(aps.size())
	if where == "gate":   # convoy order: the APC nearest the gate leaves first
		order_i.sort_custom(func(a, b): return Vector2(aps[a].pos).distance_to(gx) < Vector2(aps[b].pos).distance_to(gx) or (Vector2(aps[a].pos).distance_to(gx) == Vector2(aps[b].pos).distance_to(gx) and int(aps[a].id) < int(aps[b].id)))
	var any := false
	for i in order_i:
		var a: Dictionary = aps[i]
		var gar := int(sl[mini(i, sl.size() - 1)]) if not sl.is_empty() else -1
		var to := "b"
		match where:
			"gate":
				to = "x"
			"decon":
				to = "w%d" % mini(i, 1)
			"inner", "garage":
				to = "g%d" % gar if gar >= 0 else "b"
		var V := vstate(w, int(a.id))
		if not V.is_empty() and String(V.get("rto", "")) == to and String(V.st) == "drive":
			any = true
			continue   # already on its way there (inner -> garage is one drive)
		if order(w, a, int(T.fac), to, "fac", [], "", gar, where == "decon"):   # REGFIX7: a recalled APC is always taken in
			any = true
		else:
			Movement.order_move(w, a, CnFacility._slot_pos(CnFacility.fac(w, int(T.fac)), T, where, i))
	return any


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var ids: Array = cmd.get("ids", [])
	if ids.is_empty():
		return "No APC selected."
	for id in ids:
		var e = w.entities.get(int(id))
		if e == null or int(e.owner) != int(cmd.get("issuer", -1)) or int(e.get("cn_fac", 0)) == 0:
			return "Only your facility APCs."
	if not ["out", "garage", "bays", "point"].has(String(cmd.get("to", ""))):
		return "Unknown destination."
	return ""


## fd7_go {issuer, ids, to: out | garage | bays | point, target (point)}: one after another in the given order.
static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	for id in cmd.get("ids", []):
		var e: Dictionary = w.entities[int(id)]
		var fid := int(e.get("cn_fac", 0))
		var to := String(cmd.to)
		var tg := []
		var tv = cmd.get("target")
		if tv is Vector2:
			tg = [_snap(tv.x), _snap(tv.y)]
		elif tv is Array and (tv as Array).size() == 2:
			tg = [_snap(float(tv[0])), _snap(float(tv[1]))]
		var V := vstate(w, int(id))
		var gar := int(V.get("gar", _team_garage(w, e)))
		match to:
			"out":
				order(w, e, fid, "x", "player", tg, "", gar)
			"garage":
				order(w, e, fid, "g%d" % gar if gar >= 0 else "b", "player", [], "", gar)
			"bays":
				order(w, e, fid, "b", "player", [], "", gar)
			"point":
				if tg.size() == 2:
					var cl := classify(w, {"fac": fid, "gar": gar}, Vector2(float(tg[0]), float(tg[1])))
					order(w, e, fid, String(cl[0]), "player", cl[1], "", gar)


static func _team_garage(w: SimWorld, e: Dictionary) -> int:
	var T := CnFacility.team(w, int(e.get("cn_team", 0)))
	if T.is_empty():
		return -1
	var i: int = (T.apcs as Array).find(int(e.id))
	var sl: Array = T.get("slots", [])
	return int(sl[mini(maxi(i, 0), sl.size() - 1)]) if not sl.is_empty() else -1


# ================================================================ route cache (rebuilt from the saved polylines)
static func _route(w: SimWorld, V: Dictionary) -> Dictionary:
	if not w.cache.has("fd7_rt"):
		w.cache["fd7_rt"] = {}
	var C: Dictionary = w.cache["fd7_rt"]
	var k := str(int(V.id))
	var G := graph()
	var R: Dictionary = C.get(k, {})
	if not R.is_empty() and int(R.rv) == int(V.rv) and String(R.sig) == String(G.sig):
		return R
	var prims := []
	var off := PackedFloat64Array()
	var ends := PackedFloat64Array()
	var tot := 0.0
	var rmin := 99.0
	for l in V.legs:
		var b := build_prims(G, _unflat(l[1]), int(l[0]) == 1, int(V.gar))
		rmin = minf(rmin, float(b.rmin))
		for pr in b.prims:
			prims.append(pr)
			off.append(tot)
			tot += prim_len(pr)
		ends.append(tot)
	if ends.is_empty():
		ends.append(0.0)
	R = {"rv": int(V.rv), "sig": String(G.sig), "prims": prims, "off": off, "ends": ends, "len": tot, "zones": [], "rmin": rmin}
	var zs: Array = G.zones
	var s_in := []
	var p_in := []
	s_in.resize(zs.size())
	p_in.resize(zs.size())
	s_in.fill(-1.0)
	var s := 0.0
	var zg := 0
	while true:
		zg += 1
		if zg > 20000:
			push_error("FacDrive7: route walk bound hit (len %s)" % str(tot))   # ORCH: never spin forever on a bad route
			break
		var p: Vector2 = pose_at(R, minf(s, tot))[0]
		for zi in zs.size():
			var hit := (zs[zi].r as Rect2).has_point(p) and s <= tot
			if hit and float(s_in[zi]) < 0.0:
				s_in[zi] = minf(s, tot)
				p_in[zi] = p
			elif not hit and float(s_in[zi]) >= 0.0:
				var d := (p - (p_in[zi] as Vector2)).dot(zs[zi].ax)
				R.zones.append([float(s_in[zi]), minf(s, tot), zi, 0 if absf(d) < 1.2 else (1 if d > 0.0 else -1)])
				s_in[zi] = -1.0
		if s > tot:
			break
		s += 0.2
	R.gates = _gate_marks(R)
	C[k] = R
	return R


static func _prim_at(R: Dictionary, s: float) -> int:
	var off: PackedFloat64Array = R.off
	var i := 0
	while i + 1 < off.size() and off[i + 1] <= s + 0.000001:
		i += 1
	return i


## [compound-local pos, heading] at arc length s along the route.
static func pose_at(R: Dictionary, s: float) -> Array:
	if (R.prims as Array).is_empty():
		return [Vector2.ZERO, 0.0]
	var i := _prim_at(R, s)
	return prim_pose(R.prims[i], s - float(R.off[i]))


static func _gate_zone(G: Dictionary) -> int:
	if not G.has("gate_zi"):
		G.gate_zi = -1
		for zi in (G.zones as Array).size():
			if (G.zones[zi].r as Rect2).has_point(G.pos[int(G.exit)]):
				G.gate_zi = zi
	return int(G.gate_zi)


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var SI = SimWorld.SimIndex
	var tq := Time.get_ticks_usec() if SI.profiling else 0   # bench only (PERF7F); never touches state
	if GATES_ON and CnFacility.active(w) and registered():
		_gates(w)
		if SI.profiling:
			tq = SI.pt("fd7.gates", tq)
		_suits(w)
		if SI.profiling:
			tq = SI.pt("fd7.suits", tq)
	if not w.sys_state.has(KEY):
		if CnFacility.active(w) and w.tick % 10 == 0 and registered():
			_discover(w)
		return
	var S: Dictionary = w.sys_state[KEY]
	if w.tick % 10 == 0:
		_discover(w)
	_watch_out(w, S)
	if SI.profiling:
		tq = SI.pt("fd7.discover_watch", tq)
	var ids := []
	for k in S.v:
		ids.append(int(k))
	ids.sort()
	var drivers := []
	for id in ids:
		var V: Dictionary = S.v.get(str(id), {})
		if V.is_empty():
			continue
		var e = w.entities.get(id)
		if e == null or CnFacility.fac(w, int(V.fac)).is_empty():
			S.v.erase(str(id))
			continue
		_intercept(w, V, e)
		if not S.v.has(str(id)):
			continue
		match String(V.st):
			"park":
				_pin(w, V, e)
			"queue":
				var j := _free_bay(S, id)
				if j >= 0:
					V.to = "b%d" % j
					_go(w, V, e)
				else:
					_pin(w, V, e)
			"approach":
				_approach(w, V, e)
			"rinse":
				var o := _origin(w, int(V.fac))
				if int(e.get("cn_rinsed", -1)) >= int(V.t0) or w.tick - int(V.rt) >= CnFacility.secs(float(CnFacility.conf().get("rinse_time", 5)) + 4.0):
					V.to = String(V.then)
					V.then = ""
					_go(w, V, e)
				else:
					_set_order(w, e, o + Vector2(place_pose(String(V.at))[0]), false)
			"drive", "hold":
				drivers.append(V)
	if SI.profiling:
		tq = SI.pt("fd7.vloop", tq)
	if not drivers.is_empty():
		_drive(w, S, drivers)
	if SI.profiling:
		SI.pt("fd7.drive", tq)


## Team APCs standing in their garages are taken under control (nose out), cheap: every 10 ticks, facility matches only.
static func _discover(w: SimWorld) -> void:
	var CS := CnFacility.st(w)
	for tk in CnFacility._sorted(CS.teams):
		var T: Dictionary = CS.teams[str(tk)]
		if String(T.phase) != "garage":
			continue
		var sl: Array = T.get("slots", [])
		for i in (T.apcs as Array).size():
			var a = w.entities.get(int(T.apcs[i]))
			if a == null or not vstate(w, int(a.id)).is_empty():
				continue
			var gar := int(sl[mini(i, sl.size() - 1)]) if not sl.is_empty() else -1
			var o := _origin(w, int(T.fac))
			if gar < 0 or Vector2(a.pos).distance_to(o + garage_park(CnFacility.conf(), gar)) > 0.7:
				continue
			var S := st(w)
			S.v[str(int(a.id))] = {"id": int(a.id), "fac": int(T.fac), "seq": 0, "st": "park", "at": "g%d" % gar, "to": "g%d" % gar,
				"rto": "g%d" % gar, "then": "", "tgt": [], "gar": gar, "who": "fac", "legs": [], "rv": 0, "leg": 0, "s": 0.0, "v": 0.0,
				"gw": 0, "t0": w.tick, "rel": ""}
			a.facing = snappedf(garage_out(CnFacility.conf(), gar).angle(), 0.001)


## Team APCs that are out (unmanaged) and get a move order into their compound are driven home through the gate.
static func _watch_out(w: SimWorld, S: Dictionary) -> void:
	var CS := CnFacility.st(w)
	if CS.is_empty():
		return
	for tk in CnFacility._sorted(CS.teams):
		var T: Dictionary = CS.teams[str(tk)]
		if String(T.phase) != "out":
			continue
		for aid in T.apcs:
			var a = w.entities.get(int(aid))
			if a == null or S.v.has(str(int(aid))):
				continue
			var od: Dictionary = a.order
			if String(od.get("type", "")) != "move" or od.has("fd7") or not (od.get("target") is Vector2):
				continue
			var lt: Vector2 = Vector2(od.target) - _origin(w, int(T.fac))
			var cs := float(CnFacility.conf().compound)
			if Rect2(0, 0, cs, cs).has_point(lt):
				var gar := _team_garage(w, a)
				var cl := classify(w, {"fac": int(T.fac), "gar": gar}, Vector2(od.target))
				order(w, a, int(T.fac), String(cl[0]), "player", [], "", gar)


## A plain move / attack-move order (player or AI) on a managed APC: take it over and drive it on the lanes.
static func _intercept(w: SimWorld, V: Dictionary, e: Dictionary) -> void:
	var od: Dictionary = e.order
	var t := String(od.get("type", ""))
	if t == "board" and (String(V.st) == "park" or String(V.st) == "queue"):
		# FLOWC7 (facint7): a load order (Transport: drive up a carrier's ramp, e.g. the stealth dropship on its helipad)
		# takes a parked APC off the controller; _pin snapped it back onto its bay pose every tick and it never boarded.
		# It is re-taken (_discover) when it is next parked in its garage, like any APC the controller lost.
		st(w).v.erase(str(int(e.id)))
		return
	if String(V.st) == "drive" and not od.has("fd7") and t != "move" and t != "attack_move":
		V.st = "hold"   # player stop / hold: brake to a standstill where it is
		V.erase("pend")
		return
	if (t != "move" and t != "attack_move") or od.has("fd7") or not (od.get("target") is Vector2):
		return
	var cl := classify(w, V, Vector2(od.target))
	var R0 := _route(w, V) if String(V.st) == "drive" else {}
	if not R0.is_empty():   # undo Movement's step of this tick: back onto the route
		var pp: Array = pose_at(R0, float(V.s))
		HotState.set_pos(w, int(e.id), _wsnap(_origin(w, int(V.fac)) + Vector2(pp[0])))
	order(w, e, int(V.fac), String(cl[0]), "player", cl[1], "", int(V.gar))
	if String(V.st) == "drive" or String(V.st) == "queue":
		_set_order(w, e, Vector2(od.target), String(V.st) == "drive")
	elif String(V.st) == "park":
		_pin(w, V, e)


static func _pin(w: SimWorld, V: Dictionary, e: Dictionary) -> void:
	if String(V.at) == "" or String(V.at) == "out" or String(V.at) == "e":
		return
	var pp := _wsnap(_origin(w, int(V.fac)) + Vector2(place_pose(String(V.at))[0]))
	var d := Vector2(e.pos).distance_to(pp)
	if d > 1.2:   # moved away by something else (loaded, teleported): no longer ours
		st(w).v.erase(str(int(V.id)))
	elif d > 0.0005:
		HotState.set_pos(w, int(e.id), pp)
	if bool(e.get("moving", false)):
		HotState.set_moving(w, int(e.id), false)


## Outside the compound: Movement brings the APC to the gate apron, then the controller drives it in (wash first).
static func _approach(w: SimWorld, V: Dictionary, e: Dictionary) -> void:
	var o := _origin(w, int(V.fac))
	if String(V.to) == "x":
		_handoff(w, V, e)
		return
	var G := graph()
	var en: Vector2 = G.pos[int(G.entry)]
	var p := Vector2(e.pos)
	var od: Dictionary = e.order
	var idle := String(od.get("type", "")) != "move"
	if int(V.get("ap", 0)) == 0:   # stage 0: Movement brings it to its waiting spot out on the gate axis (one per APC, in order)
		var k := 0
		for kk in st(w).v:
			var X: Dictionary = st(w).v[kk]
			if int(X.id) != int(V.id) and int(X.fac) == int(V.fac) and String(X.st) == "approach" and int(X.seq) < int(V.seq):
				k += 1
		var far := o + en + Vector2(0, 5.0 + 2.6 * float(mini(k, 4)))
		if not Movement.is_passable_e(w, e, w.cell_of(far)):
			_approach_blocked(w, V, e, o + en + Vector2(0, 2.0))   # REGFIX7: no room out on the gate axis (map edge, cliff, water)
			return
		if p.distance_to(far) > 1.0 and not (idle and p.distance_to(far) <= 3.0):
			if idle or not (od.get("target") is Vector2) or Vector2(od.target).distance_to(far) > 0.01:
				Movement.order_move(w, e, far)
				e.order["fd7"] = 1
			return
		if k > 0:
			return   # waits its turn
		for kk in st(w).v:   # the apron is clear of the APC ahead
			var X2: Dictionary = st(w).v[kk]
			var xe = w.entities.get(int(X2.id))
			if int(X2.id) != int(V.id) and xe != null and int(X2.fac) == int(V.fac) and (Vector2(xe.pos) - o).distance_to(en + Vector2(0, 2.0)) < 3.5:
				return
		V.ap = 1
		Movement.order_move(w, e, o + en + Vector2(0, 2.0))
		e.order["fd7"] = 1
		return
	var ap := o + en + Vector2(0, 2.0)   # stage 1: rolling north up the gate axis to the apron, then the controller drives
	var inner := int(V.get("apq", 0)) == 1
	if inner:   # REGFIX7: the apron itself is off the map / blocked: line up on the gate axis just inside the entry instead
		ap = o + en + Vector2(0, -1.0)
	var tol := 0.25
	if int(V.get("apb", 0)) == 1:   # REGFIX7 blocked-queue path only (normal layouts unchanged): an APC waiting next to the
		tol = 1.0                    # apron can keep Movement from reaching the exact point; stalled 1.5 s within 2.5 -> go
		var la: Array = V.get("apl", [-999.0, -999.0])   # plain floats: the state is saved and hashed
		if p.distance_to(Vector2(float(la[0]), float(la[1]))) > 0.05:
			V.apl = [p.x, p.y]
			V.apw = w.tick
		elif w.tick - int(V.apw) >= SimWorld.TICK_RATE * 3 / 2:
			tol = 2.5
	if p.distance_to(ap) > tol and not (idle and p.distance_to(ap) <= 2.5):
		if idle:
			Movement.order_move(w, e, ap)
			e.order["fd7"] = 1
		return
	var want := ((o + en) - p).angle() if not inner else -PI * 0.5
	var df := wrapf(want - float(e.facing), -PI, PI)
	if absf(df) > 0.002:   # line up on the gate axis before rolling in (Movement's arrival leaves it a few degrees off)
		var step := V_FWD / float(SimWorld.TICK_RATE) / R_MIN
		e.facing = snappedf(wrapf(float(e.facing) + clampf(df, -step, step), -PI, PI), 0.001)
		Movement.stop_path(e)
		e.order = {"type": "move", "target": ap, "fd7": 1}
		return
	var to := String(V.to)
	var first := to
	if to.left(1) != "w":   # every APC coming in is rinsed in the wash on the way (13.9c-2)
		first = "w0"
		V.then = to
	var legs := plan("e", first, int(V.gar), PackedVector2Array([p - o])) if not inner else plan("n%d" % _axis_node(p - o), first, int(V.gar), PackedVector2Array([p - o]))
	if legs.is_empty():
		st(w).v.erase(str(int(V.id)))
		Movement.order_move(w, e, o + Vector2(place_pose(first)[0]))
		return
	V.erase("ap")
	V.erase("apb")
	V.erase("apq")
	V.erase("apl")
	V.erase("apw")
	_set_legs(V, legs)
	V.rto = first
	V.to = first
	V.at = "e"
	V.st = "drive"
	V.t0 = w.tick
	_set_order(w, e, o + Vector2(place_pose(first)[0]), false)


# ================================================================ driving
## G7 REGFIX7: stage 0 when the waiting spot out on the gate axis is not passable (a compound whose gate faces the map
## edge, a cliff or water: pt7_seq7's facility). The returning APCs used to be sent to that spot forever and never reached
## the wash. Instead they wait where they stand and go in nearest-to-the-apron first (ties: order sequence); only an APC
## that already left the queue (stage 1 or driving) has to clear the apron first. Layouts with room outside the gate
## never reach this path (behaviour and hashes unchanged there).
static func _approach_blocked(w: SimWorld, V: Dictionary, e: Dictionary, ap: Vector2) -> void:
	var p := Vector2(e.pos)
	var inner := not Movement.is_passable_e(w, e, w.cell_of(ap))   # the apron itself is off the map / blocked
	if inner:
		ap += Vector2(0, -3.0)   # entry - 1 on the gate axis: the APC lines up inside the gate mouth instead
	if int(V.get("ap", 0)) == 0 and not e.order.has("fd7"):   # waiting: drop the leftover order (the hand-off move out of the
		Movement.stop_path(e)                                    # gate), else _intercept takes it for a new player order
		e.order = {"type": "idle", "fd7": 1}
	var d := p.distance_to(ap)
	for kk in st(w).v:
		var X: Dictionary = st(w).v[kk]
		var xe = w.entities.get(int(X.id))
		if int(X.id) == int(V.id) or xe == null or int(X.fac) != int(V.fac):
			continue
		var xd := Vector2(xe.pos).distance_to(ap)
		if String(X.st) == "approach" and int(X.get("ap", 0)) == 0:
			if xd < d or (xd == d and int(X.seq) < int(V.seq)):
				return   # another queued APC is nearer the apron: it goes first
		elif String(X.st) == "approach" or xd < 3.5:   # one at a time onto the apron
			return   # the APC ahead has not cleared the apron yet
	V.ap = 1
	V.apb = 1   # stage 1 takes a looser apron stop: a queued APC may stand next to the apron (Movement stops short of it)
	if inner:
		V.apq = 1
	Movement.order_move(w, e, ap)
	e.order["fd7"] = 1


## G7 REGFIX7: the gate-axis lane node just north of compound-local p (the route start for an APC lined up inside the
## gate mouth because the apron is off the map); the entry node when there is none.
static func _axis_node(p: Vector2) -> int:
	var G := graph()
	var en: Vector2 = G.pos[int(G.entry)]
	var best := int(G.entry)
	var by := -INF
	for i in (G.pos as Array).size():
		var q: Vector2 = G.pos[i]
		if absf(q.x - en.x) < 0.05 and q.y < p.y - 0.5 and q.y > by:
			by = q.y
			best = i
	return best


## G7 APCMOV7-4: convoy deadlock breaker. The APC X ordered earlier normally enters the gate lane before V, but when V is
## physically ahead of it on the shared lane (two APCs sent out of their garages at once: V's shorter route reaches the merge
## first) X stands still behind V (spacing) while V waits for X to enter first: neither can move. X is "held behind" V when it
## is stopped, within a spacing of V, and farther from the gate-lane entry than V; V then goes first.
static func _held_behind(w: SimWorld, V: Dictionary, X: Dictionary, RX: Dictionary, z: Array) -> bool:
	if float(X.get("v", 0.0)) > 0.02:
		return false
	var xe = w.entities.get(int(X.id))
	var ve = w.entities.get(int(V.id))
	if xe == null or ve == null or Vector2(xe.pos).distance_to(Vector2(ve.pos)) > D_SAFE + 0.8:
		return false
	for zx in RX.zones:
		if int(zx[2]) == int(z[2]):
			return (float(zx[0]) - 1.4) - float(X.s) > (float(z[0]) - 1.4) - float(V.s) + 0.5
	return false


static func _zone_blocked(w: SimWorld, S: Dictionary, V: Dictionary, z: Array, gate_zi: int) -> bool:
	var zi := int(z[2])
	var dir := int(z[3])
	for k in S.v:
		var X: Dictionary = S.v[k]
		if int(X.id) == int(V.id) or int(X.fac) != int(V.fac):
			continue
		var xs := String(X.st)
		if zi == gate_zi and dir == 1 and (xs == "park" or xs == "rinse") and String(X.at).left(1) == "w":
			return true   # an APC standing in the wash holds the gate lane inbound
		if xs != "drive" and xs != "hold":
			continue
		var RX := _route(w, X)
		var sx := float(X.s)
		var held := zi == gate_zi and dir == 1 and _held_behind(w, V, X, RX, z)   # APCMOV7-4: X waits behind me: I go first
		for zx in RX.zones:
			if int(zx[2]) != zi:
				continue
			var hx := float(zx[0]) - 1.4
			if sx < hx - 0.05 or sx > float(zx[1]) + 0.9:
				continue
			if dir != 0 and int(zx[3]) == -dir:
				if sx > hx + 0.05 or int(X.seq) < int(V.seq):
					return true
			if zi == gate_zi and dir == 1 and String(X.get("rto", "")) == "x" and int(zx[3]) == 1 and sx <= hx + 0.05 and int(X.seq) < int(V.seq) and not held:
				return true   # convoy: the APC ordered earlier enters the gate lane first
		if zi == gate_zi and dir == 1 and String(X.get("rto", "")) == "x" and int(X.seq) < int(V.seq) and not held:
			var passed := false
			for zx in RX.zones:
				if int(zx[2]) == zi and sx > float(zx[0]) - 1.4 + 0.05:
					passed = true
			if not passed:
				return true
	return false


static func _drive(w: SimWorld, S: Dictionary, drivers: Array) -> void:
	var dt := 1.0 / float(SimWorld.TICK_RATE)
	var G := graph()
	var gate_zi := _gate_zone(G)
	var pos_of := {}
	for k in S.v:
		var X: Dictionary = S.v[k]
		var xe = w.entities.get(int(X.id))
		if xe != null and String(X.st) != "approach":
			pos_of[int(X.id)] = Vector2(xe.pos) - _origin(w, int(X.fac))
	var c0 := CnFacility.conf()
	var sally := _rect(c0.get("gate_inner", [0, 0, 0, 0])).merge(_rect(c0.get("apc_wash", [0, 0, 0, 0]))).merge(_rect(c0.get("gate_outer", [0, 0, 0, 0])))
	var info := {}
	for V in drivers:
		var R := _route(w, V)
		var s := float(V.s)
		var v := float(V.v)
		var look := v * v / (2.0 * BRK) + 2.4
		var smp := []
		var k := 1
		while float(k) * 0.4 <= look and s + float(k) * 0.4 <= float(R.len) + 0.4:
			if k > 20000:
				push_error("FacDrive7: look-ahead bound hit")   # ORCH: never spin forever on a bad route
				break
			var sk := minf(s + float(k) * 0.4, float(R.len))
			smp.append([sk, pose_at(R, sk)[0]])
			k += 1
		info[int(V.id)] = {"R": R, "smp": smp}
	var lim := {}
	for V in drivers:
		var id := int(V.id)
		var I: Dictionary = info[id]
		var R: Dictionary = I.R
		var s := float(V.s)
		var ends: PackedFloat64Array = R.ends
		var send := ends[mini(int(V.leg), ends.size() - 1)]
		var pi := _prim_at(R, s)
		var pr: Array = R.prims[pi] if not (R.prims as Array).is_empty() else [0, Vector2.ZERO, Vector2.ZERO, false, 0.0]
		var rev := bool(pr[3]) if int(pr[0]) == 0 else bool(pr[5])
		var L := V_REV if rev else V_FWD
		var cap := send
		if String(V.st) == "hold":   # brake to a standstill
			lim[id] = [0.0, s + float(V.v) * float(V.v) / (2.0 * BRK) + 0.01]
			continue
		if int(V.gw) > 0:
			lim[id] = [0.0, s]
			continue
		for j in range(pi, (R.prims as Array).size()):
			var o0 := float(R.off[j])
			if o0 > s + 6.0 or o0 >= send:
				break
			var q: Array = R.prims[j]
			if int(q[0]) == 1:
				var va := sqrt(A_LAT * float(q[2]))
				L = minf(L, sqrt(va * va + 2.0 * BRK * maxf(0.0, o0 - s)))
		L = minf(L, sqrt(2.0 * BRK * maxf(0.0, send - s)))
		for z in R.zones:
			var h := float(z[0]) - 1.4
			if s > h + 0.05 or h - s > 6.0 or (int(z[3]) == 0 and int(z[2]) != gate_zi):
				continue
			if _zone_blocked(w, S, V, z, gate_zi):
				L = minf(L, sqrt(2.0 * BRK * maxf(0.0, h - s)))
				cap = minf(cap, maxf(s, h))
		var me: Vector2 = pos_of.get(id, Vector2.ZERO)
		var GT: Dictionary = CnFacility.fac(w, int(V.fac)).get("gate", {})
		if not GT.is_empty():   # 13.9c-22: wait at a gate that is not open; ask it to cycle (sally port, SALLY_CAP at a time)
			for gm in R.gates:
				var gin := float(gm[0])
				# committed: the nose is through the door frame (gin = centre at a half-length + 0.1 out), or the route starts
				# so near the band's far edge (PATH7-2: an APC re-routed from inside the wash, gin 0 / gout 0.2) that it is
				# through already; without this it kept asking the outer gate every tick, the outer never closed and the
				# inner (which opens only behind a shut outer) never opened: deadlock with the APC ahead
				if s > minf(gin + 0.3, float(gm[1]) - 0.3):
					continue
				if gin - s > 10.0:
					break
				var gk := "o" if int(gm[2]) == 0 else "i"
				var ok := String(GT[gk]) == "open"
				var full := false
				if bool(GT.hard) and not sally.has_point(me):
					var nin := 0
					for k3 in pos_of:
						if int(k3) != id and sally.has_point(pos_of[k3]):
							nin += 1
					full = nin >= SALLY_CAP
				if _suits_busy(w, int(V.fac)) and not sally.grow(0.5).has_point(me):
					full = true   # 13.9c-25: armoured suits are using the wash
				if not full:
					GT["w" + gk] = w.tick
				if not ok or full:
					L = minf(L, sqrt(2.0 * BRK * maxf(0.0, gin - s)))
					cap = minf(cap, maxf(s, gin))
				break
		elif _suits_busy(w, int(V.fac)) and not sally.grow(0.5).has_point(me):   # 13.9c-25: suits in the wash, gates open
			for gm in R.gates:
				var gin2 := float(gm[0])
				if s > gin2 + 0.3:
					continue
				if gin2 - s > 10.0:
					break
				L = minf(L, sqrt(2.0 * BRK * maxf(0.0, gin2 - s)))
				cap = minf(cap, maxf(s, gin2))
				break
		for k2 in pos_of:
			if int(k2) == id:
				continue
			var X: Dictionary = S.v[str(k2)]
			if int(X.fac) != int(V.fac):
				continue
			var px: Vector2 = pos_of[k2]
			if px.distance_to(me) > 12.0:
				continue
			var stop := -1.0
			for sm in I.smp:
				var p: Vector2 = sm[1]
				var dpx := p.distance_to(px)
				if dpx < D_SAFE and dpx < me.distance_to(px) - 0.01:
					stop = float(sm[0])
					break
			if stop >= 0.0 and bool(GT.get("hard", false)) and sally.has_point(me):
				stop = _sally_follow_stop(R, s, stop, px, c0)
			if stop < 0.0 and info.has(int(k2)):
				var XI: Dictionary = info[int(k2)]
				var sx := float(X.s)
				for sm in I.smp:
					var hit := false
					for sq in XI.smp:
						if (sm[1] as Vector2).distance_to(sq[1]) < D_SAFE:
							var da := float(sm[0]) - s
							var dx := float(sq[0]) - sx
							if da > dx + 0.05 or (absf(da - dx) <= 0.05 and int(V.seq) > int(X.seq)):
								stop = float(sm[0])
							hit = true
							break
					if hit:
						break
			if stop >= 0.0:
				L = minf(L, sqrt(2.0 * BRK * maxf(0.0, stop - 0.45 - s)))
				cap = minf(cap, maxf(s, stop - 0.45))
		lim[id] = [L, cap]
	for V in drivers:
		var id := int(V.id)
		var e: Dictionary = w.entities[id]
		var R: Dictionary = info[id].R
		var l: Array = lim[id]
		var v := float(V.v)
		var tv := float(l[0])
		v = maxf(tv, v - 2.0 * BRK * dt) if tv < v else minf(tv, v + ACC * dt)
		var s0 := float(V.s)
		var s := maxf(s0, minf(s0 + v * dt, float(l[1])))
		if s0 + v * dt > float(l[1]) + 0.0001:
			v = maxf(0.0, (s - s0) / dt)
		var ends: PackedFloat64Array = R.ends
		var leg := mini(int(V.leg), ends.size() - 1)
		var done := false
		if s >= ends[leg] - 0.0005:
			s = ends[leg]
			v = 0.0
			if leg < ends.size() - 1:
				V.gw = int(V.gw) + 1
				if int(V.gw) >= GEAR_TICKS:
					V.gw = 0
					V.leg = leg + 1
			else:
				done = true
		V.s = _snap(s)
		V.v = _snap(v)
		if String(V.get("rel", "")) != "" and s > 3.5:
			V.rel = ""
		var o := _origin(w, int(V.fac))
		var pp: Array = pose_at(R, float(V.s))
		HotState.set_pos(w, id, _wsnap(o + Vector2(pp[0])))
		e.facing = snappedf(wrapf(float(pp[1]), -PI, PI), 0.001)
		if done:
			_arrive(w, V, e)
			continue
		if String(V.st) == "hold":   # the player's stop / hold order stays; only the rolling flag follows the brake
			if v > 0.005:
				e.moving = true
				e.path_req = PATH_WAIT
			else:
				Movement.stop_path(e)
			HotState.touch(w, id)
			continue
		if bool(V.get("pend", false)) and _reroute(w, V, e, R):
			continue
		_set_order(w, e, o + Vector2(place_pose(String(V.get("rto", V.to)))[0]), v > 0.005)


## A new destination while driving: once the APC rolls on a straight, the rest of the route is re-planned from the
## lane node that straight leads to (the APC keeps its speed and heading; no stop, no snap). False: not yet.
static func _reroute(w: SimWorld, V: Dictionary, e: Dictionary, R: Dictionary) -> bool:
	var to := String(V.to)
	if to == "" or to == "bq" or (V.legs as Array).is_empty():
		return false
	var s := float(V.s)
	var pi := _prim_at(R, s)
	var pr: Array = R.prims[pi]
	if int(pr[0]) != 0 or bool(pr[3]) or float(R.off[pi]) + float(pr[4]) - s < 0.6:
		return false
	var rk := "%d:%d" % [int(V.rv), pi]
	if String(V.get("rrk", "")) == rk:
		return false   # tried on this straight already: next straight (or re-planned at the route's end)
	V.rrk = rk
	var G := graph()
	var p: Vector2 = pose_at(R, s)[0]
	var dir := ((pr[2] as Vector2) - (pr[1] as Vector2)).normalized()
	var leg := mini(int(V.leg), (V.legs as Array).size() - 1)
	var raw := _collapse(_unflat(V.legs[leg][1]))
	var rem := float(R.off[pi]) + float(pr[4]) - s
	var node := -1
	for q in raw:
		var dq := q - p
		if dq.length() >= rem - 0.001 and dq.normalized().dot(dir) > 0.9999:
			var nn := _nearest(G, q)
			if nn >= 0 and (G.pos[nn] as Vector2).distance_to(q) < 0.01:
				node = nn
			break
	if node < 0:
		return false
	var legs := plan("n%d" % node, to, int(V.gar), PackedVector2Array([p]))
	if legs.is_empty():
		return false
	var v := float(V.v)
	_set_legs(V, legs)
	V.v = v
	V.rto = to
	V.erase("pend")
	_set_order(w, e, _origin(w, int(V.fac)) + Vector2(place_pose(to)[0]), v > 0.005)
	return true


# ================================================================ hardened outer gate (owner note 13.9c-22)
## Whenever enemy units are near the base (within THREAT_PAD tiles of the compound), the outer APC gate closes and locks
## (hardened); it opens only to let own APCs that the controller drives (player orders, or the facility launch / return
## flows the player started) pass: the wash is a sally port, so the inner gate closes first, the outer opens, the APCs
## pass, the outer closes behind them, then the inner opens again; outer and inner are never open at once. Opening and
## closing take GATE_S seconds each, a gate only closes when nothing stands in it, a closed gate is a locked nav gate
## (nobody paths through; enemies must breach), and the gate stands down STAND_DOWN_S after the last enemy left.
## State F.gate {o, ot, i, it, hard, seen, wo, wi} in CnFacility's facility record (saved, hashed); created on the first
## threat, so a facility that never sees an enemy is unchanged.
const GATES_ON := true
const GATE_S := 4.0
const THREAT_PAD := 16.0
const STAND_DOWN_S := 20.0
const THREAT_EVERY := 10
const SALLY_CAP := 2


## Outer / inner gate state of facility record F: [outer, inner, hardened] with outer in open | closing | hardened |
## opening and inner in open | closing | closed | opening (display, UI).
static func gate_view(F: Dictionary) -> Array:
	var GT: Dictionary = F.get("gate", {})
	if GT.is_empty():
		return ["open", "open", false]
	var o := String(GT.o)
	return ["hardened" if o == "closed" else o, String(GT.i), bool(GT.hard)]


static func gate_state(w: SimWorld, fid: int) -> String:
	var F := CnFacility.fac(w, fid)
	return String(gate_view(F)[0]) if not F.is_empty() else ""


static func _threat(w: SimWorld, F: Dictionary) -> bool:
	var r := CnFacility.compound_rect(F).grow(THREAT_PAD)
	var own := int(F.owner)
	var by: Dictionary = SimIndex.units_by_owner(w)
	for ow in by:
		if not w.is_enemy(own, int(ow)):
			continue
		for e in by[ow]:
			if r.has_point(e.pos) and float(e.get("hp", 1.0)) > 0.0 and w.entities.has(int(e.id)):   # DET7 CR 6999: skip destroyed entries still in the SimIndex (a loaded world's index has none)
				return true
	return false


static func _gate_cells(F: Dictionary, zn: String) -> Array:
	var r := CnFacility.zone(F, zn)
	var out := []
	for y in range(int(r.position.y), int(r.end.y)):
		for x in range(int(r.position.x), int(r.end.x)):
			out.append(Vector2i(x, y))
	return out


static func _fac_team(w: SimWorld, F: Dictionary) -> int:
	var f = w.factions.get(int(F.owner))
	return int(f.get("team", int(F.owner))) if f != null else int(F.owner)


## 13.9c-25: the gate cells stay vehicle-only gates of the owner's team; shut = locked (nobody passes).
static func _nav_gate(w: SimWorld, F: Dictionary, zn: String, shut: bool) -> void:
	Movement.set_gate(w, _gate_cells(F, zn), _fac_team(w, F), shut, true)


## 13.9c-25 (owner): "NO infantry or ground units can enter through the facilities apc entrance/wash area [except the
## armoured suits]". gate_outer, apc_wash and gate_inner are vehicle-only nav gates of the owner's team: the team's
## vehicles (APCs, armoured suits) path through while a gate is open, foot units of every team never do (they are routed
## round to the foot entry), other teams never. Checked every THREAT_EVERY ticks with one probe cell (a captured facility
## re-registers for the new team); a shut gate keeps its lock.
static func _vg_register(w: SimWorld, F: Dictionary) -> void:
	var tm := _fac_team(w, F)
	var wash := _gate_cells(F, "apc_wash")
	if wash.is_empty():
		return
	Movement.gate_at(w, wash[0])   # builds the nav when needed
	var pc: Vector2i = wash[0]
	var g = (w.nav.gates as Dictionary).get(pc.y * int(w.nav.w) + pc.x)
	if g != null and Movement._is_vg(g) and int(g[0]) == tm:
		return
	var GT: Dictionary = F.get("gate", {})
	var so := not GT.is_empty() and String(GT.o) != "open" and String(GT.o) != "opening"
	var si := not GT.is_empty() and String(GT.i) != "open" and String(GT.i) != "opening"
	Movement.set_gate(w, _gate_cells(F, "gate_outer"), tm, so, true)
	Movement.set_gate(w, wash, tm, false, true)
	Movement.set_gate(w, _gate_cells(F, "gate_inner"), tm, si, true)


## Nothing stands in the gate: no unit body overlaps the opening, and no vehicle centre is within an APC half-length
## of it along the gate axis (y). A soldier posted beside the door frame (outside the opening's x span) does not hold
## the door open.
static func _gate_clear(w: SimWorld, F: Dictionary, zn: String) -> bool:
	var tq := Time.get_ticks_usec() if SimIndex.profiling else 0
	var r := _gate_clear0(w, F, zn)
	if SimIndex.profiling:
		SimIndex.pt("fd7x.gate_clear", tq)
	return r


## PERF7F (exact, an existence test does not depend on scan order): (1) the unit that blocked this gate last time is
## tested first (a live unit is always in the SimIndex unit list), (2) the full scan skips, with plain float compares,
## every unit outside the zone grown by the largest body any unit can have (_gc_bound), before the per-unit test.
## The blocker id lives in w.cache (never saved): after a load the first call simply scans.
static func _gate_clear0(w: SimWorld, F: Dictionary, zn: String) -> bool:
	var z := CnFacility.zone(F, zn)
	var gc = w.cache.get("fd7_gc")
	if gc == null:
		gc = {}
		w.cache["fd7_gc"] = gc
	var ck := "%d:%s" % [int(F.id), zn]
	var lb = w.entities.get(int(gc.get(ck, -1)))
	if lb != null and lb.kind == "unit" and _gate_blocks(w, z, lb):
		return false
	var u := _gc_bound() + 0.01
	var x0 := z.position.x - u
	var x1 := z.end.x + u
	var y0 := z.position.y - u
	var y1 := z.end.y + u
	for e in SimIndex.of(w, "unit"):
		var p: Vector2 = e.pos
		if p.x < x0 or p.x > x1 or p.y < y0 or p.y > y1:
			continue
		if not w.entities.has(int(e.id)):   # DET7 CR 6999: skip destroyed entries still in the SimIndex (a loaded world's index has none)
			continue
		if _gate_blocks(w, z, e):
			gc[ck] = int(e.id)
			return false
	gc.erase(ck)
	return true


## FLOWB7 (suite 2026-10-28, gate7 sally deadlock): the follow stop is quantised to the 0.4-tile look-ahead samples
## less a 0.45 margin, so the second APC of a hardened sally (SALLY_CAP 2) could stop up to 0.85 tile further back than
## D_SAFE behind the one waiting at the outer gate: centre at y 22.85 with the inner gate's keep-clear band reaching
## 22.88 (gate y 20..22 + HL + 0.1). The inner gate then never closed, so the outer never opened: deadlock. Only when
## that stop would leave the APC inside the inner gate's keep-clear band, the exact D_SAFE boundary is found (bisection
## on the route between the last free sample and the first close one) and the APC closes up to it less 0.05; every
## other stop is unchanged. Pure function of the route and positions (deterministic).
static func _sally_follow_stop(R: Dictionary, s: float, stop: float, px: Vector2, c0: Dictionary) -> float:
	var gi := _rect(c0.get("gate_inner", [0, 0, 0, 0]))
	if gi.size.x <= 0.0:
		return stop
	var band := gi.grow_individual(HW, HL + 0.1, HW, HL + 0.1)
	var at: Vector2 = pose_at(R, maxf(s, stop - 0.45))[0]
	if not band.has_point(at):
		return stop
	var lo := maxf(s, stop - 0.4)
	var hi := stop
	for i in 12:
		var mid := (lo + hi) * 0.5
		if (pose_at(R, mid)[0] as Vector2).distance_to(px) >= D_SAFE:
			lo = mid
		else:
			hi = mid
	return maxf(stop - 0.4, lo + 0.40)   # the caller stops at stop - 0.45: lo - 0.05


## The original per-unit gate test (body radius across x, APC half-length along the gate axis for vehicles).
## FLOWB7 (suite 2026-10-28, gate7 sally deadlock): nothing airborne (a drone-bay interceptor loitering over the gate,
## move class air_low, was counted as a vehicle and held the inner gate open) and nobody up on the wall-walk (a
## Sentinel of the 13.9c-38 watch at the end of a south wall run, on the wall piece beside the gate, overlapped the
## opening by his body radius and held the outer gate open) stands in the gate's door.
static func _gate_blocks(w: SimWorld, z: Rect2, e: Dictionary) -> bool:
	var mc := Movement.move_class(e)
	if Movement.is_air(mc):
		return false
	if mc == "foot" and Movement.wallwalk_team(w, w.cell_of(e.pos)) >= 0:
		return false
	var rad := float(Movement.udef(String(e.def)).get("radius", 0.3))
	var ry := HL + 0.1 if mc != "foot" else rad
	return z.grow_individual(rad, ry, rad, ry).has_point(e.pos)


static var _gc_u := 0.0
static var _gc_k := -1


## Upper bound of the per-unit grow in _gate_blocks: HL + 0.1 or the largest unit radius (content defs and the
## Movement.udef cache, default 0.3). Recomputed when either table changes size.
static func _gc_bound() -> float:
	var tbl: Dictionary = Content.table("units")
	var k: int = tbl.size() * 1000003 + Movement._udefs.size()
	if k == _gc_k:
		return _gc_u
	var m := maxf(HL + 0.1, 0.3)
	for d in tbl.values():
		if d is Dictionary:
			m = maxf(m, float(d.get("radius", 0.3)))
	for d in Movement._udefs.values():
		m = maxf(m, float(d.get("radius", 0.3)))
	_gc_u = m
	_gc_k = k
	return m


static func _gates(w: SimWorld) -> void:
	var CS := CnFacility.st(w)
	for fk in CnFacility._sorted(CS.facs):
		var F: Dictionary = CS.facs[str(fk)]
		var fid := int(fk)
		var tq := Time.get_ticks_usec() if SimIndex.profiling else 0
		if (w.tick + fid) % THREAT_EVERY == 1:
			_vg_register(w, F)
		if SimIndex.profiling:
			tq = SimIndex.pt("fd7x.vg_register", tq)
		var GT: Dictionary = F.get("gate", {})
		if (w.tick + fid) % THREAT_EVERY == 0 and _threat(w, F):
			if GT.is_empty():
				GT = {"o": "open", "ot": 0, "i": "open", "it": 0, "hard": false, "seen": w.tick, "wo": -100, "wi": -100}
				F.gate = GT
			GT.seen = w.tick
			if not bool(GT.hard):
				GT.hard = true
				w.emit("CnGateHarden", {"fac": fid, "owner": int(F.owner), "on": true})
		if GT.is_empty():
			continue
		if bool(GT.hard) and w.tick - int(GT.seen) > CnFacility.secs(STAND_DOWN_S):
			GT.hard = false
			w.emit("CnGateHarden", {"fac": fid, "owner": int(F.owner), "on": false})
		_gate_step(w, F, GT)


static func _gate_step(w: SimWorld, F: Dictionary, GT: Dictionary) -> void:
	var T := CnFacility.secs(GATE_S)
	for k in ["o", "i"]:
		var sk := String(GT[k])
		if sk == "opening" or sk == "closing":
			GT[k + "t"] = int(GT[k + "t"]) - 1
			if int(GT[k + "t"]) <= 0:
				GT[k] = "open" if sk == "opening" else "closed"
				GT[k + "t"] = 0
				if sk == "opening":
					_nav_gate(w, F, "gate_outer" if k == "o" else "gate_inner", false)
				w.emit("CnGate", {"fac": int(F.id), "owner": int(F.owner), "gate": "outer" if k == "o" else "inner", "state": String(GT[k])})
	var hard := bool(GT.hard)
	var want_o := w.tick - int(GT.wo) <= 2
	var want_i := w.tick - int(GT.wi) <= 2
	var to_open := true
	var ti_open := true
	if hard:
		to_open = want_o and String(GT.i) == "closed"
		ti_open = want_i or not want_o   # (it only re-opens once the outer is shut: _gate_drive)
	_gate_drive(w, F, GT, "o", "gate_outer", to_open, T)
	_gate_drive(w, F, GT, "i", "gate_inner", ti_open, T)


static func _gate_drive(w: SimWorld, F: Dictionary, GT: Dictionary, k: String, zn: String, want_open: bool, T: int) -> void:
	var sk := String(GT[k])
	if want_open and sk == "closed":
		if k == "o" and bool(GT.hard) and String(GT.i) != "closed":
			return
		if k == "i" and bool(GT.hard) and String(GT.o) != "closed":
			return
		GT[k] = "opening"
		GT[k + "t"] = T
		w.emit("CnGate", {"fac": int(F.id), "owner": int(F.owner), "gate": "outer" if k == "o" else "inner", "state": "opening"})
	elif not want_open and sk == "open" and _gate_clear(w, F, zn):
		GT[k] = "closing"
		GT[k + "t"] = T
		_nav_gate(w, F, zn, true)
		w.emit("CnGate", {"fac": int(F.id), "owner": int(F.owner), "gate": "outer" if k == "o" else "inner", "state": "closing"})


## Gate crossings of route R (compound-local): [[s_in, s_out, 0 outer / 1 inner], ...] (rects grown by the half-length).
static func _gate_marks(R: Dictionary) -> Array:
	var c := CnFacility.conf()
	var rs := [_rect(c.get("gate_outer", [0, 0, 0, 0])).grow(HL + 0.1), _rect(c.get("gate_inner", [0, 0, 0, 0])).grow(HL + 0.1)]
	var out := []
	var tot := float(R.len)
	for gi in 2:
		var s := 0.0
		var sin := -1.0
		var gg := 0
		while s <= tot + 0.2:
			gg += 1
			if gg > 20000:
				push_error("FacDrive7: gate-mark bound hit (len %s)" % str(tot))   # ORCH: never spin forever on a bad route
				break
			var p: Vector2 = pose_at(R, minf(s, tot))[0]
			var hit: bool = (rs[gi] as Rect2).has_point(p) and s <= tot
			if hit and sin < 0.0:
				sin = s
			elif not hit and sin >= 0.0:
				out.append([sin, minf(s, tot), gi])
				sin = -1.0
			s += 0.2
	out.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	return out


# ================================================================ armoured suits through the wash (owner note 13.9c-25)
## The team's armoured suits (unit defs with exo_suit / cn_suit) enter and leave the compound only through the APC entry.
## A suit given a move order across the compound wall (from within SUIT_NEAR tiles outside to a point inside, or from
## inside to a point outside) is taken over:
## - entering: it queues outside the outer gate in order (qin), moves into one of WASH_CAP wash slots when there is room
##   and no APC is in the wash (win), decontaminates for the rinse time (decon), then goes on to its point through the
##   inner gate (go);
## - leaving: it queues inside the inner gate (qout), takes a wash slot (wout), waits for the outer gate (hout), goes out.
## While the outer gate is hardened (13.9c-22) the suits ask the gates to cycle like the APCs (sally port: one gate at a
## time). A fresh player order (another move, hold, attack ...) releases the suit at once. APCs wait at the gates while
## suits use the wash and suits wait while an APC is in it. State w.sys_state.fac_suits7 {s: {"<id>": R}, n: seq},
## created on the first suit taken over (no suit, no state, no cost beyond a scan every SUIT_SCAN ticks).
const SUIT_KEY := "fac_suits7"
const WASH_CAP := 4
const SUIT_SCAN := 10
const SUIT_NEAR := 14.0
const SUIT_GO_S := 30.0
const IN_STATES := ["win", "decon", "wout", "hout", "go"]
static var _suit_defs := {}


static func is_suit(def_id: String) -> bool:
	var v = _suit_defs.get(def_id)
	if v == null:
		var d := Content.unit(def_id)
		v = bool(d.get("exo_suit", false)) or String(d.get("cn_suit", "")) != ""
		_suit_defs[def_id] = v
	return bool(v)


## Suit records of facility fid in the wash / the gates (APCs wait for them).
static func _suits_busy(w: SimWorld, fid: int) -> bool:
	var SS: Dictionary = w.sys_state.get(SUIT_KEY, {})
	if SS.is_empty():
		return false
	for k in SS.s:
		var R: Dictionary = SS.s[k]
		if int(R.fac) == fid and IN_STATES.has(String(R.st)):
			return true
	return false


## Number of suits of fid in the wash or on their way into / out of it (the WASH_CAP count).
static func suits_in_wash(w: SimWorld, fid: int) -> int:
	var SS: Dictionary = w.sys_state.get(SUIT_KEY, {})
	var n := 0
	for k in SS.get("s", {}):
		var R: Dictionary = SS.s[k]
		if int(R.fac) == fid and ["win", "decon", "wout", "hout"].has(String(R.st)):
			n += 1
	return n


## Suit state for tests / UI: "" when the controller does not hold it, else qin | win | decon | go | qout | wout | hout.
static func suit_state(w: SimWorld, id: int) -> String:
	var SS: Dictionary = w.sys_state.get(SUIT_KEY, {})
	return String(SS.get("s", {}).get(str(id), {}).get("st", ""))


## Wash slots (world): the wash's four quarter centres; entering fills the inner row first, leaving the outer row first.
static func _wash_slot(F: Dictionary, j: int, entering: bool) -> Vector2:
	var r := CnFacility.zone(F, "apc_wash")
	var fx := [0.25, 0.75, 0.25, 0.75]
	var fy := [0.25, 0.25, 0.75, 0.75] if entering else [0.75, 0.75, 0.25, 0.25]
	return _wsnap(r.position + r.size * Vector2(float(fx[j]), float(fy[j])))


## Queue spot k (world): outside the outer gate (entering) or inside the inner gate (leaving), two abreast.
static func _suit_queue(F: Dictionary, k: int, entering: bool) -> Vector2:
	var go := CnFacility.zone(F, "gate_outer")
	var gi := CnFacility.zone(F, "gate_inner")
	var x := go.get_center().x - 1.0 + 2.0 * float(k % 2)
	var y := go.end.y + 1.5 + 1.6 * float(k / 2) if entering else gi.position.y - 1.5 - 1.6 * float(k / 2)
	return _wsnap(Vector2(x, y))


static func _suits(w: SimWorld) -> void:
	var CS := CnFacility.st(w)
	if w.tick % SUIT_SCAN == 3:
		for fk in CnFacility._sorted(CS.facs):
			_suit_scan(w, CS.facs[str(fk)])
	var SS: Dictionary = w.sys_state.get(SUIT_KEY, {})
	if SS.is_empty():
		return
	var ids := []
	for k in SS.s:
		ids.append(int(k))
	ids.sort()
	for id in ids:
		var R: Dictionary = SS.s.get(str(id), {})
		if not R.is_empty():
			_suit_step(w, SS, R)
	if (SS.s as Dictionary).is_empty():
		w.sys_state.erase(SUIT_KEY)


## Takes over the team's suits whose move order crosses facility F's wall.
static func _suit_scan(w: SimWorld, F: Dictionary) -> void:
	var tm := _fac_team(w, F)
	var cr := CnFacility.compound_rect(F)
	var near := cr.grow(SUIT_NEAR)
	var inner := cr.grow(-2.0)
	var by: Dictionary = SimIndex.units_by_owner(w)
	var owners := by.keys()
	owners.sort()
	for ow in owners:
		var f = w.factions.get(int(ow))
		if (int(f.get("team", int(ow))) if f != null else int(ow)) != tm:
			continue
		for e in by[ow]:
			if not w.entities.has(int(e.id)):   # DET7 CR 6999: skip destroyed entries still in the SimIndex (a loaded world's index has none)
				continue
			if not is_suit(String(e.def)) or float(e.get("hp", 1.0)) <= 0.0:
				continue
			var o: Dictionary = e.get("order", {})
			if String(o.get("type", "")) != "move" or not near.has_point(e.pos):
				continue
			var tg := Vector2(o.target)
			var dir := 0
			if not cr.has_point(e.pos) and inner.has_point(tg):
				dir = 1
			elif inner.has_point(e.pos) and not cr.has_point(tg):
				dir = -1
			if dir == 0:
				continue
			var SS: Dictionary = w.sys_state.get(SUIT_KEY, {})
			if SS.is_empty():
				SS = {"s": {}, "n": 0}
				w.sys_state[SUIT_KEY] = SS
			if SS.s.has(str(int(e.id))):
				continue
			SS.n = int(SS.n) + 1
			SS.s[str(int(e.id))] = {"id": int(e.id), "fac": int(F.id), "st": "qin" if dir > 0 else "qout",
				"dest": [_snap(tg.x), _snap(tg.y)], "seq": int(SS.n), "my": [], "t0": w.tick, "slot": -1, "done": 0}


static func _suit_order(w: SimWorld, R: Dictionary, e: Dictionary, p: Vector2) -> void:
	R.my = [_snap(p.x), _snap(p.y)]
	R.t0 = w.tick
	Movement.order_move(w, e, Vector2(float(R.my[0]), float(R.my[1])))


static func _suit_step(w: SimWorld, SS: Dictionary, R: Dictionary) -> void:
	var id := int(R.id)
	var e = w.entities.get(id)
	var F := CnFacility.fac(w, int(R.fac))
	if e == null or F.is_empty() or float(e.get("hp", 1.0)) <= 0.0:
		SS.s.erase(str(id))
		return
	var o: Dictionary = e.get("order", {})
	var ot := String(o.get("type", ""))
	if not (R.my as Array).is_empty():   # a fresh player order releases the suit (arriving leaves it idle: not an order)
		var mine := Vector2(float(R.my[0]), float(R.my[1]))
		if (ot == "move" and Vector2(o.target).distance_to(mine) > 0.01) or (ot != "move" and ot != "idle" and ot != ""):
			SS.s.erase(str(id))
			return
	var fid := int(R.fac)
	var GT: Dictionary = F.get("gate", {})
	var st := String(R.st)
	var p := Vector2(e.pos)
	var dest := Vector2(float(R.dest[0]), float(R.dest[1]))
	var o_open := GT.is_empty() or String(GT.o) == "open"
	var i_open := GT.is_empty() or String(GT.i) == "open"
	var hard := not GT.is_empty() and bool(GT.hard)
	match st:
		"qin", "qout":
			var entering := st == "qin"
			var rank := 0
			var other_first := false   # suits in the wash waiting for the other gate go first (no gate tug of war)
			for k in SS.s:
				var X: Dictionary = SS.s[k]
				if int(X.fac) != fid:
					continue
				if String(X.st) == st and int(X.seq) < int(R.seq):
					rank += 1
				if String(X.st) == "hout" or (String(X.st) == "decon" and int(X.done) == 1):
					other_first = true
			var room := suits_in_wash(w, fid) < WASH_CAP and not _apc_in_sally(w, F)
			var gate_ok := o_open if entering else i_open
			if rank == 0 and room and gate_ok and not (hard and other_first):
				var used := {}
				for k in SS.s:
					var X: Dictionary = SS.s[k]
					if int(X.fac) == fid and int(X.slot) >= 0:
						used[int(X.slot)] = true
				for j in 4:
					if not used.has(j):
						R.slot = j
						break
				R.st = "win" if entering else "wout"
				_suit_order(w, R, e, _wash_slot(F, int(R.slot), entering))
				return
			if rank == 0 and room and hard and not other_first:
				GT["wo" if entering else "wi"] = w.tick
			var q := _suit_queue(F, rank, entering)
			var mine_q := not (R.my as Array).is_empty() and Vector2(float(R.my[0]), float(R.my[1])).distance_to(q) <= 0.01
			if not mine_q or (ot != "move" and p.distance_to(q) > 0.6 and w.tick - int(R.t0) > 40):
				_suit_order(w, R, e, q)
		"win", "wout":
			var entering := st == "win"
			if hard:
				GT["wo" if entering else "wi"] = w.tick
			var sp := _wash_slot(F, int(R.slot), entering)
			if p.distance_to(sp) < 0.35:
				R.st = "decon" if entering else "hout"
				R.t0 = w.tick
				if entering:
					w.emit("CnSuitDecon", {"id": id, "fac": fid, "on": true})
			elif ot != "move" and w.tick - int(R.t0) > 40:
				_suit_order(w, R, e, sp)
		"decon":
			if int(R.done) == 0 and w.tick - int(R.t0) >= CnFacility.secs(float(CnFacility.conf().get("rinse_time", 5))):
				R.done = 1
				e["cn_rinsed"] = w.tick
				w.emit("CnSuitDecon", {"id": id, "fac": fid, "on": false})
			if int(R.done) == 1:
				if i_open:
					R.st = "go"
					R.slot = -1
					_suit_order(w, R, e, dest)
				elif hard:
					GT.wi = w.tick
		"hout":
			if o_open:
				R.st = "go"
				R.slot = -1
				_suit_order(w, R, e, dest)
			elif hard:
				GT.wo = w.tick
		"go":
			var sally := CnFacility.zone(F, "gate_inner").merge(CnFacility.zone(F, "gate_outer")).grow(0.8)
			if not sally.has_point(p) or w.tick - int(R.t0) > CnFacility.secs(SUIT_GO_S):
				SS.s.erase(str(id))


static func _apc_in_sally(w: SimWorld, F: Dictionary) -> bool:
	if not w.sys_state.has(KEY):
		return false
	var sally := CnFacility.zone(F, "gate_inner").merge(CnFacility.zone(F, "gate_outer")).grow(1.2)
	for k in w.sys_state[KEY].v:
		var V: Dictionary = w.sys_state[KEY].v[k]
		var xe = w.entities.get(int(V.id))
		if int(V.fac) == int(F.id) and xe != null and sally.has_point(xe.pos):
			return true
	return false
