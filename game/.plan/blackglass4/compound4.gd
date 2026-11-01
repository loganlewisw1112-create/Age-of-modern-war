extends RefCounted
## Site Blackglass v4: the compound in front of the mountain, drawn ONLY from site.json (the audited site plan).
## Every footprint, door, road, rail line, gate, turret, pad, rack and safety distance shown here is the same data
## audit.py checked (overlaps, blocked doors / roads, aprons, low-loader swept paths, turret fields of fire, helipad
## approach surfaces, QD rings, rack clearances, perimeter, one-way hazard flow). Draw order comes from the plan's
## painter ranking ("draw").

const M = preload("res://tools/art/g7_cn_mesh.gd")
const P = preload("res://tools/art/pix.gd")
const L = preload("res://.plan/blackglass4/lib.gd")
const IN = preload("res://.plan/blackglass4/interior.gd")
const RO = preload("res://tools/art/g7_rollout.gd")
const MD = preload("res://.plan/blackglass4/models.gd")

const RED := Color8(255, 70, 50)
const BLUE := Color8(90, 170, 255)
const WT := 3.0

static var SITE: Dictionary = IN.SITE


static func _fp(id: String) -> Dictionary:
	for f in SITE.footprints:
		if String(f.id) == id:
			return f
	return {}


static func _turret_on(id: String) -> Dictionary:
	for t in SITE.turrets:
		if String(t.on) == id:
			return t
	return {}


static func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), 0.0)


static func list(g) -> Array:
	var out: Array = []
	out.append({"name": "ground", "b": [-44, -66, 264, 296], "z": 1.0, "layer": "under", "ord": -110, "build": func(S, T): ground(S, T, g)})
	for d in SITE.draw:
		var r: Array = d.rect
		var id := String(d.id)
		var kind := String(d.kind)
		var zt := 30.0
		if kind == "fp":
			var f := _fp(id)
			zt = float(f.h) + 9.0
			if String(f.kind) in ["flood", "mast"]:
				zt = float(f.h) + 3.0
		elif kind == "prop":
			zt = 12.0
		out.append({"name": "c_" + id.replace("#", "_"), "b": [float(r[0]) - 7, float(r[1]) - 7, float(r[2]) + 7, float(r[3]) + 7], "z": zt, "layer": "under",
			"ord": int(d.ord), "build": func(S, T): draw_item(S, T, g, d)})
	out.append({"name": "outer", "b": [186, -62, 262, 292], "z": 10.0, "layer": "under", "ord": 900, "build": func(S, T): outer(S, T, g)})
	out.append({"name": "outer_n", "b": [-44, -62, 236, -40], "z": 10.0, "layer": "under", "ord": 5, "build": func(S, T): outer_n(S, T, g)})
	out.append({"name": "outer_s", "b": [-44, 248, 236, 292], "z": 10.0, "layer": "under", "ord": 899, "build": func(S, T): outer_s(S, T, g)})
	out.append({"name": "air", "b": [60, 0, 250, 140], "zmin": 0.0, "z": 50.0, "layer": "air", "ord": 2000, "noshadow": true, "build": func(S, T): air(S, T, g)})
	out.append({"name": "overlay", "b": [-100, -66, 262, 296], "z": 2.0, "layer": "air", "ord": 4000, "view": "overlay", "noshadow": true, "build": func(S, T): overlay(S, T, g)})
	return out


static func draw_item(S: Array, T: Dictionary, g, d: Dictionary) -> void:
	match String(d.kind):
		"fp":
			building(S, T, g, _fp(String(d.id)))
		"gate":
			gate(S, T, g, String(d.id))
		"rack":
			rack(S, T, g, d)
		"medevac":
			medevac_station(S, T, g)
		"prop":
			for pr in SITE.props:
				if String(pr.id) == String(d.id):
					prop(S, T, g, pr)


# ================================================================== GROUND (one decal layer: surfaces, roads, rail, markings, pads)
static func _quad_rect(pt: Dictionary, T: Dictionary, r: Array, col: Color, z := 0.01) -> void:
	L.quad(pt, T, Vector3((float(r[0]) + float(r[2])) * 0.5, (float(r[1]) + float(r[3])) * 0.5, z), L.X * (float(r[2]) - float(r[0])) * 0.5, L.Y * (float(r[3]) - float(r[1])) * 0.5, col)


static func _seg_quads(pt: Dictionary, T: Dictionary, pts: Array, w: float, col: Color, z: float) -> void:
	for i in pts.size() - 1:
		var a := _v(pts[i])
		var b := _v(pts[i + 1])
		var d := b - a
		var ln := d.length()
		if ln < 0.01:
			continue
		var dir := d / ln
		var side := Vector3(-dir.y, dir.x, 0)
		L.quad(pt, T, (a + b) * 0.5 + L.Z * z, dir * (ln * 0.5 + 0.35), side * w * 0.5, col)


static func _poly_line(pt: Dictionary, T: Dictionary, pts: Array, off: float, col: Color, z: float, dash := 0.0) -> void:
	var acc := 0.0
	for i in pts.size() - 1:
		var a := _v(pts[i])
		var b := _v(pts[i + 1])
		var d := b - a
		var ln := d.length()
		if ln < 0.01:
			continue
		var dir := d / ln
		var side := Vector3(-dir.y, dir.x, 0)
		if dash <= 0.0:
			M.dline(pt, T, a + side * off + L.Z * z, b + side * off + L.Z * z, col, L.Z)
			continue
		var t := 0.0
		while t < ln:
			var ph := fmod(acc + t, dash * 2.0)
			var t1 := minf(ln, t + (dash - ph if ph < dash else dash * 2.0 - ph))
			if ph < dash:
				M.dline(pt, T, a + dir * t + side * off + L.Z * z, a + dir * t1 + side * off + L.Z * z, col, L.Z)
			t = t1 + 0.001
		acc += ln


static func _rail(pt: Dictionary, T: Dictionary, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var ln := d.length()
	if ln < 0.01:
		return
	var dir := d / ln
	var side := Vector3(-dir.y, dir.x, 0)
	L.quad(pt, T, (a + b) * 0.5 + L.Z * 0.03, dir * (ln * 0.5 + 0.2), side * 2.0, L.GRAVEL)
	for i in int(ln / 0.65):
		var c := a + dir * (i * 0.65 + 0.3) + L.Z * 0.04
		M.dline(pt, T, c - side * 1.35, c + side * 1.35, Color8(76, 60, 46), L.Z)
	for s: float in [-0.72, 0.72]:
		M.dline(pt, T, a + side * s + L.Z * 0.06, b + side * s + L.Z * 0.06, Color8(178, 182, 186), L.Z)
		M.dline(pt, T, a + side * (s + 0.06) + L.Z * 0.055, b + side * (s + 0.06) + L.Z * 0.055, Color8(60, 62, 64), L.Z)


static func ground(S: Array, T: Dictionary, g) -> void:
	var b: Dictionary = SITE.bounds
	var fc: Dictionary = SITE.fence
	var pa := M.part(S, -3)
	# outside: grass; kill zone: cleared, graded dirt; inside: hardstanding concrete; hazard zone: sealed slab
	# ground is painted ONLY on the graded platform (the terrain mesh owns everything else: no overlap with rock)
	var kz: Array = [float(fc.xw), float(fc.yn), float(fc.x), float(fc.ys)]
	for r in SITE.platform:
		var rr: Array = [float(r[0]), float(r[1]), minf(float(r[2]), 264.0), float(r[3])]
		_quad_rect(pa, T, rr, Color8(118, 116, 100), 0.005)   # graded verge (compacted gravel)
		var ki: Array = [maxf(rr[0], kz[0]), maxf(rr[1], kz[1]), minf(rr[2], kz[2]), minf(rr[3], kz[3])]
		if ki[2] > ki[0] and ki[3] > ki[1]:
			_quad_rect(pa, T, ki, Color8(124, 110, 86), 0.007)   # kill zone: churned, cleared earth
	_ground_art(S, T, g)
	_quad_rect(pa, T, [0, float(b.wn), float(b.wx), float(b.ws)], Color8(132, 132, 124), 0.009)
	_quad_rect(pa, T, [0, 20.4, float(b.wx) - 3, 93.6], Color8(128, 120, 116), 0.010)
	var pg := M.part(S, -2.8)
	for i in range(1, 47):
		M.dline(pg, T, Vector3(i * 4.0, float(b.wn), 0.012), Vector3(i * 4.0, float(b.ws), 0.012), Color(0.25, 0.25, 0.23, 0.16), L.Z)
	for i in range(1, 62):
		M.dline(pg, T, Vector3(0, float(b.wn) + i * 4.0, 0.012), Vector3(float(b.wx), float(b.wn) + i * 4.0, 0.012), Color(0.25, 0.25, 0.23, 0.16), L.Z)
	for k in 260:
		var p := Vector3(4 + 184 * P.hn(k, 1, 7), -8 + 246 * P.hn(k, 2, 7), 0.013)
		var r := 0.3 + 1.3 * P.hn(k, 3, 7)
		L.quad(pg, T, p, L.X * r * 1.4, L.Y * r, Color(0.1, 0.1, 0.08, 0.12))
	L.quad(pg, T, Vector3(96, 92.6, 0.014), L.X * 90, L.Y * 1.0, Color(1.0, 0.27, 0.2, 0.55))
	L.quad(pg, T, Vector3(96, 95.4, 0.014), L.X * 90, L.Y * 1.0, Color(0.35, 0.67, 1.0, 0.55))
	# hardstands / aprons (aprons: yellow keep-clear hatching)
	var ph := M.part(S, -2.6)
	for rd in SITE.roads:
		if String(rd.cls) != "hard":
			continue
		var rr: Array = rd.rect
		_quad_rect(ph, T, rr, Color8(150, 150, 146), 0.016)
		var x0 := float(rr[0])
		var y0 := float(rr[1])
		var x1 := float(rr[2])
		var y1 := float(rr[3])
		for e in [[Vector3(x0, y0, 0.02), Vector3(x1, y0, 0.02)], [Vector3(x1, y0, 0.02), Vector3(x1, y1, 0.02)], [Vector3(x1, y1, 0.02), Vector3(x0, y1, 0.02)], [Vector3(x0, y1, 0.02), Vector3(x0, y0, 0.02)]]:
			M.dline(ph, T, e[0], e[1], L.YEL, L.Z)
		if String(rd.id).begins_with("apron_"):
			var n := int(((x1 - x0) + (y1 - y0)) / 2.2)
			for k in n:
				var t := k * 2.2
				var a := Vector3(x0 + minf(t, x1 - x0), y0 + maxf(0.0, t - (x1 - x0)), 0.021)
				var q := Vector3(x0 + maxf(0.0, t - (y1 - y0)), y0 + minf(t, y1 - y0), 0.021)
				M.dline(ph, T, a, q, Color(0.89, 0.72, 0.16, 0.55), L.Z)
	# roads: asphalt, edge lines, centre line (two-way) or chevrons (one-way), hazard red edges, slot drains
	var pr := M.part(S, -2.4)
	for rd in SITE.roads:
		var cls := String(rd.cls)
		if cls in ["hard", "rail"]:
			continue
		var w := float(rd.w)
		var pts: Array = rd.pts
		if cls == "foot":
			_seg_quads(pr, T, pts, w, Color8(176, 170, 156), 0.022)
			_poly_line(pr, T, pts, w * 0.5, Color8(120, 116, 106), 0.024)
			_poly_line(pr, T, pts, -w * 0.5, Color8(120, 116, 106), 0.024)
			continue
		_seg_quads(pr, T, pts, w, L.ASPH, 0.02)
		var edge := RED if String(rd.zone) == "hazard" else Color8(226, 226, 216)
		_poly_line(pr, T, pts, w * 0.5 - 0.3, edge, 0.025)
		_poly_line(pr, T, pts, -w * 0.5 + 0.3, edge, 0.025)
		_poly_line(pr, T, pts, w * 0.5 + 0.35, Color8(52, 54, 56), 0.023, 0.6)
		if not bool(rd.oneway):
			_poly_line(pr, T, pts, 0.0, L.YEL, 0.026, 2.0)
		else:
			_chevrons(pr, T, pts, w, Color8(240, 240, 232) if String(rd.zone) != "hazard" else Color8(255, 150, 130))
	var pl := M.part(S, -2.2)
	for rd in SITE.roads:
		if String(rd.cls) != "rail":
			continue
		var pts: Array = rd.pts
		for i in pts.size() - 1:
			_rail(pl, T, _v(pts[i]), _v(pts[i + 1]))
	for pd in SITE.pads:
		if String(pd.level) == "ground":
			_ground_pad(S, T, g, pd)
	# drainage channel + grated sump along the foot of the engineered face
	L.quad(pl, T, Vector3(0.9, 97.0, 0.03), L.X * 0.7, L.Y * 107.0, Color8(46, 48, 50))
	for k in 70:
		M.dline(pl, T, Vector3(0.3, -10.0 + k * 3.05, 0.035), Vector3(1.5, -10.0 + k * 3.05, 0.035), Color8(110, 114, 116), L.Z)
	L.hazard(pl, T, Vector3(44, 74.5, 0.03), Vector3(52, 74.5, 0.03), L.Z, 0.7)
	L.hazard(pl, T, Vector3(44, 103.5, 0.03), Vector3(52, 103.5, 0.03), L.Z, 0.7)


## Weathering + life on the platform: contact shadows under every structure, tyre tracks, puddles, grass at the
## cut toes, crater pocks and wire debris in the kill zone, toe drains along the cove walls.
static func _ground_art(S: Array, T: Dictionary, g) -> void:
	var fc: Dictionary = SITE.fence
	var b: Dictionary = SITE.bounds
	var pa := M.part(S, -2.9)
	for f in SITE.footprints:   # ambient-occlusion skirt
		if String(f.level) != "ground" or String(f.kind) in ["flood", "zfence", "portal"]:
			continue
		var r: Array = f.rect
		for k in 3:
			var e := 0.5 + k * 0.6
			_quad_rect(pa, T, [float(r[0]) - e, float(r[1]) - e, float(r[2]) + e, float(r[3]) + e], Color(0.05, 0.05, 0.04, 0.10), 0.0125)
	for k in 90:   # kill-zone crater pocks + debris
		var side := k % 3
		var p := Vector3.ZERO
		if side == 0:
			p = Vector3(float(b.wx) + 4 + 30 * P.hn(k, 1, 31), float(fc.yn) + (float(fc.ys) - float(fc.yn)) * P.hn(k, 2, 31), 0.013)
		elif side == 1:
			p = Vector3(-40 + 266 * P.hn(k, 3, 31), float(fc.yn) + 2 + 30 * P.hn(k, 4, 31), 0.013)
		else:
			p = Vector3(-40 + 266 * P.hn(k, 5, 31), float(b.ws) + 4 + 30 * P.hn(k, 6, 31), 0.013)
		var r := 0.8 + 1.8 * P.hn(k, 7, 31)
		L.quad(pa, T, p, L.X * r, L.Y * r * 0.8, Color(0.22, 0.18, 0.13, 0.35))
		L.quad(pa, T, p + Vector3(0.2, 0.2, 0.001), L.X * r * 0.55, L.Y * r * 0.45, Color(0.12, 0.1, 0.08, 0.35))
	for k in 40:   # puddles on the hardstanding
		var p := Vector3(10 + 170 * P.hn(k, 8, 33), -4 + 236 * P.hn(k, 9, 33), 0.0135)
		var r := 0.6 + 1.6 * P.hn(k, 10, 33)
		L.quad(pa, T, p, L.X * r * 1.6, L.Y * r, Color(0.35, 0.42, 0.5, 0.28))
	for k in 260:   # grass + weeds along the cove wall toes and the verge
		var t := P.hn(k, 11, 35)
		var p := Vector3.ZERO
		match k % 4:
			0: p = Vector3(-40 + 300 * t, -60.5 + 2.0 * P.hn(k, 12, 35), 0.014)
			1: p = Vector3(-40 + 300 * t, 289.0 + 2.5 * P.hn(k, 12, 35), 0.014)
			2: p = Vector3(-40.5 + 2.0 * P.hn(k, 12, 35), 208 + 82 * t, 0.014)
			_: p = Vector3(-40.5 + 2.0 * P.hn(k, 12, 35), -60 + 46 * t, 0.014)
		for j in 3:
			var o := Vector3(P.hn(k, j, 37) - 0.5, P.hn(k, j, 39) - 0.5, 0) * 1.2
			M.dline(pa, T, p + o, p + o + Vector3(0.1, -0.1, 0.45), Color8(84, 108, 62), L.Y)
	for e in [[Vector3(220, 40, 0), Vector3(300, 40, 0)], [Vector3(220, 132, 0), Vector3(300, 132, 0)]]:   # tyre tracks on the approach
		for s: float in [-1.6, 1.6]:
			M.dline(pa, T, e[0] + Vector3(0, s, 0.03), e[1] + Vector3(0, s, 0.03), Color(0.1, 0.09, 0.08, 0.35), L.Z)


static func _chevrons(pt: Dictionary, T: Dictionary, pts: Array, w: float, col: Color) -> void:
	var acc := 0.0
	for i in pts.size() - 1:
		var a := _v(pts[i])
		var b := _v(pts[i + 1])
		var ln := (b - a).length()
		if ln < 0.01:
			continue
		var dir := (b - a) / ln
		var side := Vector3(-dir.y, dir.x, 0)
		var t := fmod(8.0 - acc, 8.0)
		while t < ln:
			var c := a + dir * t + L.Z * 0.027
			M.dline(pt, T, c - side * w * 0.3 - dir * 1.2, c, col, L.Z)
			M.dline(pt, T, c + side * w * 0.3 - dir * 1.2, c, col, L.Z)
			t += 8.0
		acc = fmod(acc + ln, 8.0)


static func _ground_pad(S: Array, T: Dictionary, g, pd: Dictionary) -> void:
	var c := _v(pd.c)
	var r := float(pd.r)
	var pg := M.part(S, -2.0)
	var oct: Array = []
	var tl: Array = []
	for k in 16:
		var a := TAU * k / 16.0
		oct.append(c + Vector3(cos(a), sin(a), 0) * r + L.Z * 0.03)
		tl.append(c + Vector3(cos(a), sin(a), 0) * r * 0.6 + L.Z * 0.032)
	M.dpoly(pg, T, oct, Color8(112, 114, 116), L.Z)
	M.dpoly(pg, T, tl, Color8(90, 92, 96), L.Z)
	for k in 16:
		M.dline(pg, T, oct[k], oct[(k + 1) % 16], Color8(240, 240, 232), L.Z)
		M.dline(pg, T, tl[k], tl[(k + 1) % 16], L.YEL, L.Z)
	if String(pd.use) == "medevac":
		L.quad(pg, T, c + L.Z * 0.034, L.X * 4.2, L.Y * 1.3, Color8(230, 50, 44))
		L.quad(pg, T, c + L.Z * 0.034, L.X * 1.3, L.Y * 4.2, Color8(230, 50, 44))
	else:
		for s: float in [-2.2, 2.2]:
			L.quad(pg, T, c + Vector3(s, 0, 0.034), L.X * 0.5, L.Y * 3.2, Color8(250, 250, 246))
		L.quad(pg, T, c + L.Z * 0.034, L.X * 2.2, L.Y * 0.5, Color8(250, 250, 246))
	for k in 16:
		var a := TAU * (k + 0.5) / 16.0
		g.lamp(T, c + Vector3(cos(a), sin(a), 0.1) * r, L.L_GRN if String(pd.use) == "medevac" else L.L_AMB, 4.0, true, pg)
	var h := _v(pd.heading)
	var sd := Vector3(-h.y, h.x, 0)
	for k in 3:
		var q := c + h * (r * 0.75 + k * 1.2) + L.Z * 0.036
		M.dline(pg, T, q - sd * 1.4 - h * 0.8, q, Color8(250, 250, 246), L.Z)
		M.dline(pg, T, q + sd * 1.4 - h * 0.8, q, Color8(250, 250, 246), L.Z)
	g.pool(T, c, r * 0.8, r * 0.8, Color(0.75, 0.9, 1.0, 0.22))


# ================================================================== BUILDINGS (by kind; all positions from the plan)
static func _doors_for(f: Dictionary) -> Array:
	## site doors on the camera-facing faces (x1 / y1) -> lib building() door specs
	var r: Array = f.rect
	var cx := (float(r[0]) + float(r[2])) * 0.5
	var cy := (float(r[1]) + float(r[3])) * 0.5
	var outd: Array = []
	for d in SITE.doors:
		if String(d.bld) != String(f.id):
			continue
		var kind := String(d.kind)
		if kind == "bay":
			continue
		var lk := "person" if kind == "person" else ("open" if String(d.dir) == "in" or kind == "heavy" else "roll")
		if String(d.side) == "x1":
			outd.append(["x", float(d.at) - cy, float(d.w), float(d.h), lk])
		elif String(d.side) == "y1":
			outd.append(["y", float(d.at) - cx, float(d.w), float(d.h), lk])
	return outd


static func building(S: Array, T: Dictionary, g, f: Dictionary) -> void:
	var r: Array = f.rect
	var x0 := float(r[0])
	var y0 := float(r[1])
	var x1 := float(r[2])
	var y1 := float(r[3])
	var h := float(f.h)
	var cx := (x0 + x1) * 0.5
	var cy := (y0 + y1) * 0.5
	var id := String(f.id)
	match String(f.kind):
		"wall":
			for w in SITE.walls:
				if String(w.id) == id:
					_wall(S, T, g, _v(w.a), _v(w.b), _v(w.out), float(w.h))
			if id == "w_n":   # rock-anchor buttress tying the wall into the cliff
				var pa := M.part(S, 0)
				M.box(pa, T, Vector3(0.0, -8.5, 6.0), Vector3(2.0, 2.2, 6.0), L.rp(L.BRUT_D), Vector3(0.6, 0.6, 0.0))
				M.box(pa, T, Vector3(-0.5, -8.5, 13.0), Vector3(1.5, 2.6, 1.0), L.rp(L.BRUT))
				for k in 4:
					L.quad(pa, T, Vector3(2.02, -9.6 + k * 0.7, 4.0 + k * 2.0), L.Y * 0.18, L.Z * 0.18, Color8(70, 72, 74), L.X)
		"sallywall":
			_swall(S, T, g, x0, y0, x1, y1, h)
		"tower":
			var t := _turret_on(id)
			_tower(S, T, g, Vector3(cx, cy, 0), (x1 - x0) * 0.5, h, String(t.kind), float(t.yaw), absi(id.hash()) % 97)
		"zfence":
			_fence(S, T, g, x0, y0, x1, y1, h)
		"gantry":
			if id == "gantry_a":
				_gantry(S, T, g)
		"intake":
			L.building(S, T, g, x0, y0, x1, y1, h, {"style": "brut", "floors": 3, "lit": 0.3, "seed": 11, "doors": _doors_for(f), "sign": RED})
			_intake_detail(S, T, g, f)
			_roof_laser(S, T, g, id)
		"tube":
			_tube(S, T, g, x0, y0, x1, y1, h)
		"hzairlock":
			_hz_airlock(S, T, g, x0, y0, x1, y1, h)
		"containers":
			_containers(S, T, g, x0, y0, x1, y1)
		"frame":
			_frame(S, T, g, Vector3(cx, cy, 0), id)
		"hzpost":
			L.building(S, T, g, x0, y0, x1, y1, h, {"style": "panel", "floors": 2, "lit": 0.7, "seed": 51, "doors": _doors_for(f), "sign": RED, "roof": false})
			_roof_laser(S, T, g, id)
		"wash":
			_wash(S, T, g, x0, y0, x1, y1, h)
		"pdecon":
			L.building(S, T, g, x0, y0, x1, y1, h, {"style": "panel", "floors": 1, "lit": 0.8, "seed": 41, "doors": _doors_for(f), "sign": Color8(120, 220, 255)})
			var pz := M.part(S, -0.5)
			L.quad(pz, T, Vector3(cx, y0 - 1.0, 0.04), L.X * (x1 - x0) * 0.5, L.Y * 0.8, RED)
			L.quad(pz, T, Vector3(cx, y1 + 1.0, 0.04), L.X * (x1 - x0) * 0.5, L.Y * 0.8, BLUE)
		"genhall":
			L.building(S, T, g, x0, y0, x1, y1, h, {"style": "brut", "floors": 2, "lit": 0.2, "seed": 61, "doors": _doors_for(f), "roof": false})
			_genhall_detail(S, T, g, x0, y0, x1, y1, h)
		"xfmr":
			_xfmr(S, T, g, x0, y0, x1, y1)
		"aid":
			L.building(S, T, g, x0, y0, x1, y1, h, {"style": "panel", "floors": 2, "lit": 0.8, "seed": 71, "doors": _doors_for(f), "sign": Color8(230, 50, 44), "roof": false})
			var pc := M.part(S, 1.2)
			L.quad(pc, T, Vector3(cx, cy, h + 0.5), L.X * 3.0, L.Y * 0.9, Color8(230, 50, 44))
			L.quad(pc, T, Vector3(cx, cy, h + 0.5), L.X * 0.9, L.Y * 3.0, Color8(230, 50, 44))
		"hq":
			L.building(S, T, g, x0, y0, x1, y1, h, {"style": "brut", "floors": 3, "lit": 0.55, "seed": 81, "doors": _doors_for(f), "sign": BLUE, "roof": false})
			_hq_detail(S, T, g, x0, y0, x1, y1, h)
			_roof_laser(S, T, g, id)
		"staff":
			L.building(S, T, g, x0, y0, x1, y1, h, {"style": "panel", "floors": 6, "lit": 0.6, "seed": 131 + int(y0), "doors": _doors_for(f), "sign": L.YEL})
		"barracks":
			L.building(S, T, g, x0, y0, x1, y1, h, {"style": "panel", "floors": 4, "lit": 0.65, "seed": 31, "doors": _doors_for(f), "sign": L.YEL, "roof": false})
			_roof_laser(S, T, g, id)
		"mast":
			_lattice(S, T, g, Vector3(cx, cy, 0), h)
		"flood":
			L.floodmast(S, T, g, Vector3(cx, cy, 0), h, Vector3(0.6, 0.6, 0))
		"depot":
			L.vault_shelter(S, T, g, x0, y0, x1, y1, h, true)
			_roof_laser(S, T, g, id)
			for k in 3:
				_dog(S, T, g, Vector3(x1 + 1.5, cy - 2.0 + k * 2.0, 0), 0.0)
		"dronefort":
			L.building(S, T, g, x0, y0, x1, y1, h, {"style": "brut", "floors": 2, "lit": 0.3, "seed": 91, "doors": _doors_for(f), "roof": false})
			_dronefort_roof(S, T, g, x0, y0, x1, y1, h)
			_roof_laser(S, T, g, id)
		"motorpool":
			_motorpool(S, T, g, x0, y0, x1, y1, h)
		"fuel":
			_fuel(S, T, g, x0, y0, x1, y1)
		"igloo":
			L.igloo(S, T, g, x0, y0, x1, y1)
		"berm":
			_berm_block(S, T, x0, y0, x1, y1, h)
		"sponson":
			_sponson(S, T, g, f)


## Wall sponson: an octagonal hardened gun drum built out from the wall face, twin autocannon on top, stair hatch,
## searchlight, armour skirt. One per tower span; fields of fire audited (outward +-80 deg).
static func _sponson(S: Array, T: Dictionary, g, f: Dictionary) -> void:
	var t := _turret_on(String(f.id))
	var r: Array = f.rect
	var c := Vector3((float(r[0]) + float(r[2])) * 0.5, (float(r[1]) + float(r[3])) * 0.5, 0)
	var h := float(f.h)
	var pt := M.part(S, 0)
	M.cyl(pt, T, c + L.Z * h * 0.5, L.Z, 2.5, h * 0.5, 8, L.rp(L.BRUT), {"cap_t": 2}, 0.0, 2.2)
	for k in 3:
		M.cyl(pt, T, c + L.Z * (2.6 + k * 2.4), L.Z, 2.52, 0.08, 8, L.rp(L.BRUT_D), {"caps": false})
	var pr := M.part(S, 1)
	M.cyl(pr, T, c + L.Z * (h + 0.4), L.Z, 2.7, 0.4, 8, L.rp(L.BRUT_D), {"cap_t": 2}, 0.0, 2.4)
	var ov := Vector3(float(t.out[0]), float(t.out[1]), 0)
	L.t_flak(S, T, g, c + L.Z * (h + 0.8), atan2(ov.y, ov.x), 1.25)
	M.box(pr, T, c - ov * 1.6 + L.Z * (h + 1.0), Vector3(0.5, 0.5, 0.2), L.rp(L.GUN))
	L.flood(g, pr, T, c + ov * 2.4 + L.Z * (h - 0.6), ov, 12.0)
	g.lamp(T, c + L.Z * (h + 2.6), L.L_RED, 6.0, true, pr)
	L.plate(pt, T, c + ov * 2.5 + L.Z * 3.6, ov if absf(ov.x) > 0.5 else L.Y, 2.0, 0.5, L.RED, int(c.x + c.y))


## Cliff lift: glazed 50 m lift tower against the face, landings onto each gun gallery, skybridge onto the rampart.
static func _clifflift(S: Array, T: Dictionary, g, x0: float, y0: float, x1: float, y1: float, h: float) -> void:
	var cx := (x0 + x1) * 0.5
	var cy := (y0 + y1) * 0.5
	var pf := M.part(S, 0)
	for c: Vector2 in [Vector2(x0 + 0.3, y0 + 0.3), Vector2(x1 - 0.3, y0 + 0.3), Vector2(x1 - 0.3, y1 - 0.3), Vector2(x0 + 0.3, y1 - 0.3)]:
		M.box(pf, T, Vector3(c.x, c.y, h * 0.5), Vector3(0.3, 0.3, h * 0.5), L.rp(L.STEEL))
	var pg := M.part(S, 0.4)
	for nl: Vector3 in [L.X, L.Y]:
		var fc := Vector3(x1, cy, 0) if nl == L.X else Vector3(cx, y1, 0)
		var al := L.along(nl)
		L.quad(pg, T, fc + nl * 0.02 + L.Z * h * 0.5, al * ((y1 - y0) * 0.5 - 0.3), L.Z * h * 0.5, Color(0.35, 0.55, 0.7, 0.55), nl)
		for k in int(h / 4.0):
			M.dline(pg, T, fc + nl * 0.03 - al * 2.2 + L.Z * (k * 4.0), fc + nl * 0.03 + al * 2.2 + L.Z * (k * 4.0 + 4.0), L.STEEL, nl)
			M.dline(pg, T, fc + nl * 0.03 + al * 2.2 + L.Z * (k * 4.0), fc + nl * 0.03 - al * 2.2 + L.Z * (k * 4.0 + 4.0), L.STEEL, nl)
	var pc := M.part(S, 1)
	M.box(pc, T, Vector3(cx, cy, 25.0), Vector3(1.4, 1.4, 1.3), L.rp(Color8(220, 222, 220)))   # cab mid-travel
	g.lamp(T, Vector3(x1 + 0.1, cy, 25.0), L.L_WARM, 8.0)
	for gz: float in [12.0, 24.0, 36.0]:   # landings onto the galleries
		M.box(pc, T, Vector3(-0.5 + x0 * 0.5, cy, gz - 0.2), Vector3(0.6 + x0 * 0.5, 1.4, 0.2), L.rp(L.BRUT_D))
	M.box(pc, T, Vector3(cx, cy, h + 1.5), Vector3((x1 - x0) * 0.5 + 0.6, (y1 - y0) * 0.5 + 0.6, 1.5), L.rp(L.BRUT))   # head house
	M.box(pc, T, Vector3(-1.0, cy, 48.6), Vector3(1.2 + x0 * 0.5, 1.3, 0.25), L.rp(L.STEEL))   # skybridge to the rampart
	L.railing(pc, T, Vector3(-2.2, cy + 1.3, 48.85), Vector3(x0, cy + 1.3, 48.85), 1.0, Color8(200, 200, 196))
	g.lamp(T, Vector3(x1 + 0.2, cy, h + 3.2), L.L_RED, 8.0, true, pc)
	_lattice(S, T, g, Vector3(cx, cy, h + 3.0), 14.0)   # site comms mast on the head house
	L.plate(pc, T, Vector3(x1 + 0.61, cy, h + 1.5), L.X, 2.0, 0.6, BLUE, 5)


static func _roof_laser(S: Array, T: Dictionary, g, on: String) -> void:
	for t in SITE.turrets:
		if String(t.on) == on and String(t.kind) == "pdl":
			var f := _fp(on)
			var p := Vector3(float(t.pos[0]), float(t.pos[1]), float(f.h) + 0.45)
			if String(f.kind) == "depot":
				p.z = float(f.h)
			var pb := M.part(S, 1.3)
			M.box(pb, T, p + L.Z * 0.4, Vector3(1.4, 1.4, 0.4), L.rp(L.BRUT_D))
			L.railing(pb, T, p + Vector3(-1.4, 1.4, 0.8), p + Vector3(1.4, 1.4, 0.8), 0.8, Color8(170, 172, 168))
			L.t_laser(S, T, g, p + L.Z * 0.8, 0.6, 1.0)


static func _intake_detail(S: Array, T: Dictionary, g, f: Dictionary) -> void:
	var r: Array = f.rect
	var x1 := float(r[2])
	var h := float(f.h)
	# overhead cage-hoist runway projecting over the drive-in apron (8.5 m clear: low-loader + cage = 5.6 m)
	var pc := M.part(S, 2)
	for s: float in [-5.6, 5.6]:
		M.box(pc, T, Vector3(x1 + 6.0, 40.0 + s, 5.0), Vector3(0.25, 0.25, 5.0), L.rp(L.YEL))
	M.box(pc, T, Vector3(x1 + 3.0, 40.0, 10.2), Vector3(3.2, 5.9, 0.3), L.rp(L.YEL))
	M.box(pc, T, Vector3(x1 + 4.0, 40.0, 9.5), Vector3(0.8, 1.0, 0.5), L.rp(L.GUN))
	M.dline(pc, T, Vector3(x1 + 4.0, 40.0, 9.0), Vector3(x1 + 4.0, 40.0, 8.6), Color8(30, 30, 30))
	g.lamp(T, Vector3(x1 + 6.2, 45.9, 9.6), L.L_AMB, 9.0, true, pc)
	var ps := M.part(S, 1.4)
	M.box(ps, T, Vector3(36.0, 30.0, h + 1.6), Vector3(2.2, 2.2, 1.2), L.rp(L.BRUT))
	M.cyl(ps, T, Vector3(36.0, 30.0, h + 5.0), L.Z, 0.8, 2.6, 10, L.rp(Color8(176, 178, 180)))
	g.lamp(T, Vector3(36.0, 30.0, h + 7.9), L.L_RED, 5.0, true, ps)


static func _tube(S: Array, T: Dictionary, g, x0: float, y0: float, x1: float, y1: float, h: float) -> void:
	var pt := M.part(S, 0)
	var yc := (y0 + y1) * 0.5
	var hw := (y1 - y0) * 0.5
	var sec := PackedVector2Array()
	for i in 9:
		var a := PI * float(i) / 8.0
		sec.append(Vector2(yc - cos(a) * hw, sin(a) * h))
	M.loft(pt, T, [[x0, sec], [x0 + 0.001, sec], [x1 - 0.001, sec], [x1, sec]], L.rp(Color8(138, 136, 132)))
	for k in int((x1 - x0) / 2.5):
		var xx := x0 + 1.0 + k * 2.5
		for i in 8:
			var a0 := PI * float(i) / 8.0
			var a1 := PI * float(i + 1) / 8.0
			M.dline(pt, T, Vector3(xx, yc - cos(a0) * (hw + 0.05), sin(a0) * (h + 0.05)), Vector3(xx, yc - cos(a1) * (hw + 0.05), sin(a1) * (h + 0.05)), Color(0.2, 0.2, 0.2, 0.5))
	for k in 5:
		var xx := x0 + 3.0 + k * 5.0
		g.lamp(T, Vector3(xx, yc - cos(PI * 0.7) * (hw + 0.1), sin(PI * 0.7) * (h + 0.1)), L.L_RED, 4.0, true, pt)
	L.plate(pt, T, Vector3((x0 + x1) * 0.5, y1, 3.2), L.Y, 6.0, 0.7, RED, 61)


## Sealed airlock gatehouse where the specimen tube enters the mountain: armoured block the tube passes through,
## round tube collar, decon spray ring, rotating beacons, hazard banding, airlock-cycle panel.
static func _hz_airlock(S: Array, T: Dictionary, g, x0: float, y0: float, x1: float, y1: float, h: float) -> void:
	var cy := (y0 + y1) * 0.5
	var pb := M.part(S, 0)
	M.box(pb, T, Vector3((x0 + x1) * 0.5, cy, h * 0.5), Vector3((x1 - x0) * 0.5, (y1 - y0) * 0.5, h * 0.5), L.rp(L.BRUT), Vector3(0.3, 0.3, 0.3))
	M.box(pb, T, Vector3((x0 + x1) * 0.5, cy, h + 0.4), Vector3((x1 - x0) * 0.5 + 0.4, (y1 - y0) * 0.5 + 0.4, 0.4), L.rp(L.BRUT_D))
	for nl: Vector3 in [L.X, L.Y]:
		var fc := Vector3(x1, cy, 0) if nl == L.X else Vector3((x0 + x1) * 0.5, y1, 0)
		var al := L.along(nl)
		var ln := (y1 - y0) if nl == L.X else (x1 - x0)
		L.hazard(pb, T, fc + nl * 0.02 - al * ln * 0.5 + L.Z * 1.0, fc + nl * 0.02 + al * ln * 0.5 + L.Z * 1.0, nl, 0.8)
		L.hazard(pb, T, fc + nl * 0.02 - al * ln * 0.5 + L.Z * (h - 1.0), fc + nl * 0.02 + al * ln * 0.5 + L.Z * (h - 1.0), nl, 0.8)
	var pc := M.part(S, 1)
	for k in 16:   # round collar + decon spray ring around the tube on the +x face
		var a0 := PI * float(k) / 16.0
		var am := a0 + PI / 32.0
		M.box(pc, T, Vector3(x1 + 0.3, cy - cos(am) * 4.5, sin(am) * 6.1), Vector3(0.3, 0.5, 0.5), L.rp(L.BRUT_D))
		M.dline(pc, T, Vector3(x1 + 0.65, cy - cos(am) * 4.8, sin(am) * 6.4), Vector3(x1 + 1.8, cy - cos(am) * 4.2, sin(am) * 5.6), Color(0.5, 0.85, 1.0, 0.7))
		if k % 4 == 0:
			g.lamp(T, Vector3(x1 + 0.7, cy - cos(am) * 4.8, sin(am) * 6.4), L.L_CYAN, 4.0, true, pc)
	for s2: float in [-1.0, 1.0]:
		M.cyl(pc, T, Vector3(x1 - 1.0, cy + s2 * ((y1 - y0) * 0.5 - 1.0), h + 1.3), L.Z, 0.35, 0.5, 8, L.rp(Color8(200, 60, 50)))
		g.lamp(T, Vector3(x1 - 1.0, cy + s2 * ((y1 - y0) * 0.5 - 1.0), h + 1.9), L.L_RED, 9.0, true, pc)
	L.quad(pc, T, Vector3(x1 + 0.03, cy + (y1 - y0) * 0.5 - 1.4, 2.4), L.Y * 0.6, L.Z * 0.8, Color8(70, 200, 120), L.X)
	L.plate(pc, T, Vector3(x1 + 0.03, cy, h - 2.4), L.X, 6.0, 0.9, RED, 61)


static func _containers(S: Array, T: Dictionary, g, x0: float, y0: float, x1: float, y1: float) -> void:
	var pb := M.part(S, -0.5)
	L.quad(pb, T, Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.04), L.X * (x1 - x0) * 0.5, L.Y * (y1 - y0) * 0.5, Color8(96, 92, 88))
	L.hazard(pb, T, Vector3(x0, y1 - 0.2, 0.05), Vector3(x1, y1 - 0.2, 0.05), L.Z)
	var nx := int((x1 - x0) / 4.8)
	for i in nx:
		for j in 2:
			if i == nx / 2:
				continue
			var pc := M.part(S, 1)
			var c := Vector3(x0 + 2.4 + i * 4.8, y0 + 2.0 + j * 3.6, 1.3)
			var col: Color = [Color8(200, 60, 50), Color8(226, 184, 40), Color8(110, 116, 120)][(i + j) % 3]
			M.box(pc, T, c, Vector3(2.1, 1.2, 1.3), L.rp(col))
			for k in 4:
				M.dline(pc, T, c + Vector3(-1.8 + k * 1.2, 1.21, -1.2), c + Vector3(-1.8 + k * 1.2, 1.21, 1.2), P.mul(col, 0.7), L.Y)
			if (i + j) % 2 == 0:
				M.box(pc, T, c + L.Z * 2.6, Vector3(2.1, 1.2, 1.3), L.rp(P.mul(col, 0.92)))


static func _frame(S: Array, T: Dictionary, g, ec: Vector3, id: String) -> void:
	var pe := M.part(S, 1)
	L.emp_grid(pe, T, ec.x - 5.4, ec.y - 4.4, ec.x + 5.4, ec.y + 4.4, 0.06)
	for d: Vector2 in [Vector2(-5.2, -4.2), Vector2(5.2, -4.2), Vector2(5.2, 4.2), Vector2(-5.2, 4.2)]:
		var p := ec + Vector3(d.x, d.y, 0)
		M.box(pe, T, p + L.Z * 2.9, Vector3(0.32, 0.32, 2.9), L.rp(L.STEEL))
		M.cyl(pe, T, p + L.Z * 4.0, L.Z, 0.75, 0.2, 12, L.rp(Color8(60, 90, 140)), {"caps": false})
		g.lamp(T, p + Vector3(0.4, 0.4, 4.0), L.L_CYAN, 9.0, true, pe)
	for yy: float in [-4.2, 4.2]:
		M.box(pe, T, ec + Vector3(0, yy, 6.0), Vector3(5.5, 0.25, 0.25), L.rp(L.YEL))
	if id == "frame_a":
		L.spec(S, T, "g7_threats", "g7_m_packhunter", "idle", 3, ec + L.Z * 0.1, L.MACH)
	else:
		L.spec(S, T, "g7_threats2", "g7_m_spitter", "idle", 2, ec + L.Z * 0.1, L.MACH)
	for p: Vector3 in [ec + Vector3(-1.4, -0.8, 0.3), ec + Vector3(1.6, 0.6, 0.3), ec + Vector3(-0.4, 1.4, 0.3)]:
		L.foam(pe, T, p, 0.6)
	for p: Vector3 in [ec + Vector3(-2.4, -1.8, 0), ec + Vector3(2.4, 1.8, 0), ec + Vector3(-2.4, 1.8, 0), ec + Vector3(2.4, -1.8, 0)]:
		L.clamp_pad(pe, T, p)
	g.pool(T, ec, 5.0, 4.0, Color(0.45, 0.8, 1.0, 0.45))


static func _wash(S: Array, T: Dictionary, g, x0: float, y0: float, x1: float, y1: float, h: float) -> void:
	## Drive-through vehicle decontamination: side walls, roof, spray arches, under-chassis jets, sump grates.
	var cx := (x0 + x1) * 0.5
	var pw := M.part(S, 0)
	for s: float in [x0, x1 - 0.5]:
		M.box(pw, T, Vector3(s + 0.25, (y0 + y1) * 0.5, h * 0.5), Vector3(0.25, (y1 - y0) * 0.5, h * 0.5), L.rp(Color8(176, 180, 182)))
	var pr := M.part(S, 1)
	M.box(pr, T, Vector3(cx, (y0 + y1) * 0.5, h + 0.2), Vector3((x1 - x0) * 0.5 + 0.3, (y1 - y0) * 0.5 + 0.3, 0.2), L.rp(Color8(150, 154, 156)))
	for k in 3:
		var yy := y0 + 5.0 + k * 8.0
		M.box(pr, T, Vector3(cx, yy, h - 0.4), Vector3((x1 - x0) * 0.5 - 0.5, 0.2, 0.2), L.rp(L.STEEL))
		for i in 6:
			M.dline(pr, T, Vector3(x0 + 1.5 + i * 1.8, yy, h - 0.6), Vector3(x0 + 1.5 + i * 1.8, yy, 0.4), Color(0.5, 0.85, 1.0, 0.55))
			g.lamp(T, Vector3(x0 + 1.5 + i * 1.8, yy + 0.3, h - 0.7), L.L_CYAN, 4.0, true, pr)
	var pg := M.part(S, -0.4)
	for k in 8:
		L.quad(pg, T, Vector3(cx, y0 + 2.0 + k * 3.0, 0.03), L.X * 3.0, L.Y * 0.35, Color8(40, 44, 48))
	L.quad(pg, T, Vector3(cx, y0 + 0.8, 0.035), L.X * (x1 - x0) * 0.5, L.Y * 0.6, RED)
	L.quad(pg, T, Vector3(cx, y1 - 0.8, 0.035), L.X * (x1 - x0) * 0.5, L.Y * 0.6, BLUE)
	L.plate(pr, T, Vector3(x1, (y0 + y1) * 0.5, h - 1.2), L.X, 6.0, 0.8, Color8(120, 220, 160), 21)
	g.pool(T, Vector3(cx, (y0 + y1) * 0.5, 0), 4.0, 10.0, Color(0.45, 0.8, 1.0, 0.35))


static func _genhall_detail(S: Array, T: Dictionary, g, x0: float, y0: float, x1: float, y1: float, h: float) -> void:
	var pr := M.part(S, 1.2)
	for k in 3:
		var p := Vector3(x0 + 3.0 + k * 5.0, y0 + 4.0, h + 0.45)
		M.cyl(pr, T, p + L.Z * 2.5, L.Z, 0.45, 2.5, 8, L.rp(Color8(150, 146, 140)))
		M.cyl(pr, T, p + L.Z * 5.2, L.Z, 0.55, 0.2, 8, L.rp(L.DARK), {"cap_t": 0})
		M.box(pr, T, Vector3(x0 + 3.0 + k * 5.0, y1 - 5.0, h + 1.0), Vector3(2.0, 2.4, 0.55), L.rp(Color8(110, 116, 120)))
		for i in 3:
			M.cyl(pr, T, Vector3(x0 + 3.0 + k * 5.0, y1 - 6.4 + i * 1.4, h + 1.6), L.Z, 0.55, 0.03, 10, L.rp(L.DARK), {"cap_t": 0})
	var pd := M.part(S, 1)
	L.plate(pd, T, Vector3(x1, (y0 + y1) * 0.5, h - 1.2), L.X, 5.0, 0.7, L.ORANGE, 66)


static func _xfmr(S: Array, T: Dictionary, g, x0: float, y0: float, x1: float, y1: float) -> void:
	var pb := M.part(S, -0.4)
	L.quad(pb, T, Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.04), L.X * (x1 - x0) * 0.5, L.Y * (y1 - y0) * 0.5, L.GRAVEL)
	for k in 3:
		var c := Vector3((x0 + x1) * 0.5, y0 + 3.0 + k * 5.0, 0)
		var pt := M.part(S, 1)
		M.box(pt, T, c + L.Z * 0.2, Vector3(2.6, 1.8, 0.2), L.rp(L.CONC))
		M.box(pt, T, c + L.Z * 1.5, Vector3(1.8, 1.2, 1.1), L.rp(Color8(110, 124, 112)))
		for i in 6:
			M.dline(pt, T, c + Vector3(-1.6 + i * 0.64, 1.21, 0.5), c + Vector3(-1.6 + i * 0.64, 1.21, 2.5), Color8(80, 92, 82), L.Y)
		for s: float in [-0.8, 0.0, 0.8]:
			M.cyl(pt, T, c + Vector3(s, 0, 3.0), L.Z, 0.16, 0.45, 6, L.rp(Color8(150, 110, 70)))
		L.plate(pt, T, c + Vector3(1.81, 0, 1.6), L.X, 1.6, 0.4, L.YEL, k)
	_fence(S, T, g, x0, y0, x1, y1, 3.0, true)


static func _hq_detail(S: Array, T: Dictionary, g, x0: float, y0: float, x1: float, y1: float, h: float) -> void:
	var pr := M.part(S, 1.3)
	for k in 2:
		var c := Vector3(x0 + 4.0 + k * 5.0, y1 - 4.0, h + 0.45)
		M.cyl(pr, T, c + L.Z * 0.6, L.Z, 0.2, 0.6, 6, L.rp(L.STEEL))
		M.cyl(pr, T, c + L.Z * 1.5, Vector3(0.6, 0.6, 0.5), 1.2, 0.12, 14, L.rp(Color8(226, 226, 220)), {}, 0.0, 1.0)
	for k in 3:
		M.cyl(pr, T, Vector3(x1 - 2.0, y0 + 2.0 + k * 1.2, h + 4.0), L.Z, 0.05, 3.5, 4, L.rp(L.STEEL), {"edge": false})
		g.lamp(T, Vector3(x1 - 2.0, y0 + 2.0 + k * 1.2, h + 7.6), L.L_RED, 5.0, true, pr)


static func _lattice(S: Array, T: Dictionary, g, c: Vector3, h: float) -> void:
	var pm := M.part(S, 1)
	var legs := [Vector3(-1.2, -1.2, 0), Vector3(1.2, -1.2, 0), Vector3(0, 1.3, 0)]
	for i in 3:
		var a: Vector3 = legs[i]
		var b: Vector3 = legs[(i + 1) % 3]
		M.dline(pm, T, c + a, c + a * 0.25 + L.Z * h, Color8(200, 60, 50))
		for k in int(h / 3.0):
			var t0 := k * 3.0 / h
			var t1 := (k + 1) * 3.0 / h
			M.dline(pm, T, c + a * (1.0 - 0.75 * t0) + L.Z * h * t0, c + b * (1.0 - 0.75 * t1) + L.Z * h * t1, Color8(220, 220, 214))
	for k in 3:
		M.cyl(pm, T, c + Vector3(0.6, 0.6, h * (0.55 + k * 0.15)), Vector3(1, 0.4, 0), 0.7, 0.12, 12, L.rp(Color8(226, 226, 220)))
		g.lamp(T, c + L.Z * h * (0.35 + k * 0.32), L.L_RED, 6.0, true, pm)


static func _dronefort_roof(S: Array, T: Dictionary, g, x0: float, y0: float, x1: float, y1: float, h: float) -> void:
	for k in 4:
		var Tr := M.sub(T, Vector3(x0 + 4.0 + k * 6.0, (y0 + y1) * 0.5 + 3.0, h + 0.5), PI * 0.35, 0.6)
		var pr := M.part(S, 1.3)
		for j in 3:
			M.cyl(pr, Tr, Vector3(1.2, -1.0 + j * 1.0, 0.6), L.X, 0.45, 1.4, 8, L.rp(L.GUN), {"cap_t": 2})
			M.cyl(pr, Tr, Vector3(2.62, -1.0 + j * 1.0, 0.6), L.X, 0.36, 0.02, 8, L.rp(Color8(26, 28, 30)), {"cap_t": 4})
		M.box(pr, Tr, Vector3(0.2, 0, 0.2), Vector3(0.6, 1.6, 0.2), L.rp(L.GUN))
		g.lamp(Tr, Vector3(2.7, 1.4, 0.6), L.L_AMB, 4.0, true, pr)
	IN.drone(S, T, g, Vector3((x0 + x1) * 0.5, y1 - 2.0, h + 6.0), PI * 0.3)


static func _motorpool(S: Array, T: Dictionary, g, x0: float, y0: float, x1: float, y1: float, h: float) -> void:
	## Open-fronted vehicle shed (bays open to the west yard), steel portal frames, roof sheeting.
	var pc := M.part(S, 1)
	var n := int((y1 - y0) / 5.0)
	for k in n + 1:
		var yy := y0 + k * (y1 - y0) / n
		for xx: float in [x0 + 0.2, x1 - 0.2]:
			M.box(pc, T, Vector3(xx, yy, h * 0.5), Vector3(0.18, 0.18, h * 0.5), L.rp(L.STEEL))
	M.box(pc, T, Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, h + 0.1), Vector3((x1 - x0) * 0.5 + 0.4, (y1 - y0) * 0.5, 0.15), L.rp(Color8(104, 110, 106)))
	for k in n * 2:
		M.dline(pc, T, Vector3(x0 - 0.4, y0 + k * 2.5, h + 0.26), Vector3(x1 + 0.4, y0 + k * 2.5, h + 0.26), Color8(80, 86, 84), L.Z)
	var pw := M.part(S, 0)
	M.box(pw, T, Vector3(x1 - 0.3, (y0 + y1) * 0.5, h * 0.5), Vector3(0.3, (y1 - y0) * 0.5, h * 0.5), L.rp(L.CONC))
	for k in n:
		g.lamp(T, Vector3((x0 + x1) * 0.5, y0 + 2.5 + k * 5.0, h - 0.4), L.L_WARM, 7.0)
	for k in 2:
		L.vehicle(S, T, g, Vector3((x0 + x1) * 0.5, y0 + 9.0 + k * 10.0, 0), PI, "apc")
	L.plate(pw, T, Vector3(x1, (y0 + y1) * 0.5, h - 1.2), L.X, 6.0, 0.7, L.YEL, 44)


static func _fuel(S: Array, T: Dictionary, g, x0: float, y0: float, x1: float, y1: float) -> void:
	## Bunded fuel farm: bund wall, four horizontal tanks on saddles, pump island, foam monitor, placards.
	var pb := M.part(S, 0)
	for e in [[Vector3((x0 + x1) * 0.5, y0 + 0.3, 0.7), Vector3((x1 - x0) * 0.5, 0.3, 0.7)], [Vector3((x0 + x1) * 0.5, y1 - 0.3, 0.7), Vector3((x1 - x0) * 0.5, 0.3, 0.7)],
			[Vector3(x0 + 0.3, (y0 + y1) * 0.5, 0.7), Vector3(0.3, (y1 - y0) * 0.5, 0.7)], [Vector3(x1 - 0.3, (y0 + y1) * 0.5, 0.7), Vector3(0.3, (y1 - y0) * 0.5, 0.7)]]:
		M.box(pb, T, e[0], e[1], L.rp(L.CONC))
	L.quad(M.part(S, -0.4), T, Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.04), L.X * (x1 - x0) * 0.5, L.Y * (y1 - y0) * 0.5, Color8(110, 108, 100))
	for k in 4:
		var pt := M.part(S, 1)
		var c := Vector3(x0 + 14.0, y0 + 4.0 + k * 5.6, 0)
		M.cyl(pt, T, c + L.Z * 2.2, L.X, 1.9, 9.0, 14, L.rp(Color8(226, 222, 206)))
		for s: float in [-6.0, 6.0]:
			M.box(pt, T, c + Vector3(s, 0, 0.5), Vector3(0.4, 1.6, 0.5), L.rp(L.BRUT))
		L.quad(pt, T, c + Vector3(9.03, 0, 2.2), L.Y * 0.8, L.Z * 0.8, L.RED, L.X)
	var pp := M.part(S, 1)
	M.box(pp, T, Vector3(x0 + 2.0, y0 + 6.0, 1.0), Vector3(0.9, 1.4, 1.0), L.rp(Color8(200, 60, 50)))
	M.box(pp, T, Vector3(x0 + 2.0, y0 + 6.0, 2.6), Vector3(1.6, 2.4, 0.12), L.rp(Color8(200, 60, 50)))
	g.lamp(T, Vector3(x0 + 2.0, y0 + 6.0, 2.4), L.L_WARM, 8.0)
	M.cyl(pp, T, Vector3(x1 - 1.6, y1 - 1.6, 1.2), L.Z, 0.3, 1.2, 8, L.rp(L.RED))
	L.plate(pp, T, Vector3(x1, (y0 + y1) * 0.5, 1.0), L.X, 6.0, 0.6, L.RED, 41)


static func _berm_block(S: Array, T: Dictionary, x0: float, y0: float, x1: float, y1: float, h: float) -> void:
	var pb := M.part(S, 0)
	var cx := (x0 + x1) * 0.5
	var cy := (y0 + y1) * 0.5
	if (x1 - x0) > (y1 - y0):
		M.face(pb, T, [Vector3(x0, y0, 0), Vector3(x1, y0, 0), Vector3(x1, cy, h), Vector3(x0, cy, h)], Vector3(cx, y0 - 2, -1), L.rp(Color8(102, 112, 74)))
		M.face(pb, T, [Vector3(x0, cy, h), Vector3(x1, cy, h), Vector3(x1, y1, 0), Vector3(x0, y1, 0)], Vector3(cx, y1 + 2, -1), L.rp(Color8(110, 120, 80)))
	else:
		M.face(pb, T, [Vector3(x0, y0, 0), Vector3(cx, y0, h), Vector3(cx, y1, h), Vector3(x0, y1, 0)], Vector3(x0 - 2, cy, -1), L.rp(Color8(102, 112, 74)))
		M.face(pb, T, [Vector3(cx, y0, h), Vector3(x1, y0, 0), Vector3(x1, y1, 0), Vector3(cx, y1, h)], Vector3(x1 + 2, cy, -1), L.rp(Color8(110, 120, 80)))


static func _fence(S: Array, T: Dictionary, g, x0: float, y0: float, x1: float, y1: float, h: float, ring := false) -> void:
	var pf := M.part(S, 1)
	var runs: Array = []
	if ring:
		runs = [[Vector3(x0, y0, 0), Vector3(x1, y0, 0)], [Vector3(x1, y0, 0), Vector3(x1, y1, 0)], [Vector3(x1, y1, 0), Vector3(x0, y1, 0)], [Vector3(x0, y1, 0), Vector3(x0, y0, 0)]]
	elif (x1 - x0) > (y1 - y0):
		runs = [[Vector3(x0, (y0 + y1) * 0.5, 0), Vector3(x1, (y0 + y1) * 0.5, 0)]]
	else:
		runs = [[Vector3((x0 + x1) * 0.5, y0, 0), Vector3((x0 + x1) * 0.5, y1, 0)]]
	for rr in runs:
		var a: Vector3 = rr[0]
		var b: Vector3 = rr[1]
		var nl := L.Y if absf(a.y - b.y) < 0.1 else L.X
		var n := maxi(1, int(a.distance_to(b) / 3.0))
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			M.cyl(pf, T, p + L.Z * h * 0.5, L.Z, 0.06, h * 0.5, 4, L.rp(L.STEEL), {"edge": false})
		M.dpoly(pf, T, [a + L.Z * 0.1, b + L.Z * 0.1, b + L.Z * h, a + L.Z * h], Color(0.62, 0.66, 0.7, 0.2), nl)
		M.dline(pf, T, a + L.Z * h, b + L.Z * h, Color8(150, 156, 160), nl)
		RO.wire(pf, T, a, b, h + 0.25)


static func _gantry(S: Array, T: Dictionary, g) -> void:
	## Rail inspection gantry over the specimen line: radiation / bio portal scanner (7.5 m clear).
	var pg := M.part(S, 1)
	var a := _fp("gantry_a")
	var b := _fp("gantry_b")
	var xa := (float(a.rect[0]) + float(a.rect[2])) * 0.5
	for f in [a, b]:
		var yy := (float(f.rect[1]) + float(f.rect[3])) * 0.5
		M.box(pg, T, Vector3(xa, yy, 4.25), Vector3(0.6, 0.6, 4.25), L.rp(L.STEEL))
	M.box(pg, T, Vector3(xa, 9.0, 8.0), Vector3(0.7, 9.6, 0.5), L.rp(L.YEL))
	for k in 6:
		M.dline(pg, T, Vector3(xa + 0.71, 2.0 + k * 1.2, 7.5), Vector3(xa + 0.71, 2.0 + k * 1.2, 1.0), Color(0.5, 0.9, 1.0, 0.5), L.X)
		g.lamp(T, Vector3(xa + 0.8, 2.0 + k * 1.2, 7.4), L.L_CYAN, 5.0, true, pg)
	L.plate(pg, T, Vector3(xa + 0.71, 9.0, 8.0), L.X, 5.0, 0.6, RED, 3)


static func _swall(S: Array, T: Dictionary, g, x0: float, y0: float, x1: float, y1: float, h: float) -> void:
	var pt := M.part(S, 0)
	var c := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, h * 0.5)
	M.box(pt, T, c, Vector3((x1 - x0) * 0.5, (y1 - y0) * 0.5, h * 0.5), L.rp(L.BRUT))
	for k in int((x1 - x0) / 3.0):
		M.box(pt, T, Vector3(x0 + 1.5 + k * 3.0, c.y, h + 0.5), Vector3(0.7, (y1 - y0) * 0.5, 0.5), L.rp(L.BRUT_D))
	for k in int((x1 - x0) / 6.0):
		g.lamp(T, Vector3(x0 + 3.0 + k * 6.0, y1 + 0.1, h - 1.0), L.L_WARM, 6.0)
	L.hazard(pt, T, Vector3(x0, y1 + 0.02, 0.6), Vector3(x1, y1 + 0.02, 0.6), L.Y)


# ================================================================== WALLS, TOWERS, GATES (v3 detail, plan positions)
static func _wall(S: Array, T: Dictionary, g, a: Vector3, b: Vector3, outward: Vector3, h: float) -> void:
	var d := b - a
	var ln := d.length()
	var dir := d / ln
	var n := maxi(1, int(ceil(ln / 8.0)))
	for i in n:
		var s0 := ln * i / n
		var s1 := ln * (i + 1) / n
		var c := a + dir * (s0 + s1) * 0.5 - outward * WT * 0.5
		var half := (dir * (s1 - s0) * 0.5).abs() + (outward * WT * 0.5).abs() + Vector3(0, 0, h * 0.5)
		var pt := M.part(S, 0)
		M.box(pt, T, c + L.Z * h * 0.5, half, L.rp(L.BRUT))
		var fo := c + outward * WT * 0.5
		var u := dir * (s1 - s0) * 0.5
		M.face(pt, T, [fo + u + L.Z * 2.6, fo - u + L.Z * 2.6, fo - u + outward * 1.8, fo + u + outward * 1.8], c, L.rp(L.BRUT_D))
		M.dline(pt, T, fo - u + outward * 0.02 + L.Z * 2.6, fo - u + outward * 0.02 + L.Z * h, Color(0.12, 0.12, 0.12, 0.5), outward)
		for z: float in [4.5, 6.8]:
			M.dline(pt, T, fo - u + outward * 0.02 + L.Z * z, fo + u + outward * 0.02 + L.Z * z, Color(0.15, 0.15, 0.14, 0.3), outward)
		if i % 2 == 0:
			L.plate(pt, T, fo + outward * 0.02 + L.Z * 3.6, outward, 3.0, 0.6, L.RED, i)
		var pl := M.part(S, 1)
		M.box(pl, T, c + outward * (WT * 0.5 + 0.35) + L.Z * (h - 0.25), (dir * (s1 - s0) * 0.5).abs() + (outward * 0.45).abs() + Vector3(0, 0, 0.25), L.rp(L.BRUT_D))
		M.dline(pl, T, c + outward * (WT * 0.5 + 0.8) - u + L.Z * (h - 0.5), c + outward * (WT * 0.5 + 0.8) + u + L.Z * (h - 0.5), Color8(120, 200, 255), outward)
		for k in 2:
			var mc := a + dir * (s0 + (s1 - s0) * (k * 0.5 + 0.25)) - outward * 0.5 + L.Z * (h + 0.7)
			M.box(pl, T, mc, (dir * (s1 - s0) * 0.15).abs() + (outward * 0.5).abs() + Vector3(0, 0, 0.7), L.rp(L.BRUT))
		L.railing(pl, T, a + dir * s0 - outward * (WT - 0.2) + L.Z * h, a + dir * s1 - outward * (WT - 0.2) + L.Z * h, 1.0, Color8(170, 172, 168))
		if i % 2 == 1:
			g.lamp(T, a + dir * (s0 + s1) * 0.5 - outward * 0.3 + L.Z * (h + 1.6), L.L_RED, 6.0, true, pl)
		else:
			L.flood(g, pl, T, a + dir * (s0 + s1) * 0.5 + L.Z * (h - 1.0), outward, 10.0)


static func _tower(S: Array, T: Dictionary, g, at: Vector3, half: float, h: float, turret: String, yaw: float, seed: int) -> void:
	var pt := M.part(S, 0)
	var conc: Array = L.rp(L.BRUT)
	M.box(pt, T, at + L.Z * 1.2, Vector3(half + 0.8, half + 0.8, 1.2), L.rp(L.BRUT_D), Vector3(0.6, 0.6, 0.6))
	M.box(pt, T, at + L.Z * (h * 0.5 + 1.2), Vector3(half, half, h * 0.5 - 1.2), conc, Vector3(0.3, 0.3, 0.3))
	for nl: Vector3 in [L.X, L.Y]:
		var al := L.along(nl)
		for f in 4:
			var z := 3.6 + f * 3.4
			if z > h - 1.5:
				break
			L.quad(pt, T, at + nl * (half - 0.22) + L.Z * z, al * half * 0.5, L.Z * 0.16, Color8(12, 12, 13), nl)
			if f == 3 or (f == 2 and seed % 2 == 0):
				g.lamp(T, at + nl * (half - 0.1) + L.Z * z, Color(1.0, 0.75, 0.45, 0.4), 5.0)
		L.plate(pt, T, at + nl * (half - 0.2) + L.Z * 2.4, nl, half * 0.9, 0.55, L.RED, seed)
	var pr := M.part(S, 1)
	M.box(pr, T, at + L.Z * (h + 0.9), Vector3(half + 0.7, half + 0.7, 0.9), conc)
	for nl: Vector3 in [L.X, L.Y]:
		var al := L.along(nl)
		for k in 3:
			L.quad(pr, T, at + nl * (half + 0.72) + al * (-half * 0.6 + k * half * 0.6) + L.Z * (h + 1.0), al * 0.45, L.Z * 0.12, Color8(10, 10, 11), nl)
	M.box(pr, T, at + L.Z * (h + 2.0), Vector3(half + 0.9, half + 0.9, 0.2), L.rp(L.BRUT_D))
	L.railing(pr, T, at + Vector3(-half - 0.8, half + 0.8, h + 2.2), at + Vector3(half + 0.8, half + 0.8, h + 2.2), 0.9, Color8(170, 172, 168))
	L.railing(pr, T, at + Vector3(half + 0.8, -half - 0.8, h + 2.2), at + Vector3(half + 0.8, half + 0.8, h + 2.2), 0.9, Color8(170, 172, 168))
	var top := at + L.Z * (h + 2.2)
	match turret:
		"rail":
			L.t_railgun(S, T, g, top, yaw, 1.35, seed % 3 == 0)
		"laser":
			L.t_laser(S, T, g, top, yaw, 1.3)
		"flak":
			L.t_flak(S, T, g, top, yaw, 1.25)
		"sam":
			L.t_sam(S, T, g, top, yaw, 1.1)
	M.cyl(pr, T, at + Vector3(-half * 0.7, half * 0.7, h + 2.7), Vector3(0.7, 0.7, -0.1), 0.45, 0.4, 8, L.rp(L.DARK))
	g.lamp(T, at + Vector3(-half * 0.7, half * 0.7, h + 2.7) + Vector3(0.45, 0.45, 0), Color(1, 0.97, 0.85, 1.0), 12.0, true, pr)
	M.cyl(pr, T, at + Vector3(half * 0.6, -half * 0.6, h + 3.6), L.Z, 0.05, 1.4, 4, L.rp(L.STEEL), {"edge": false})
	g.lamp(T, at + Vector3(half * 0.6, -half * 0.6, h + 5.1), L.L_RED, 8.0, true, pr)


static func gate(S: Array, T: Dictionary, g, id: String) -> void:
	for gt in SITE.gates:
		if String(gt.id) != id:
			continue
		var gx := float(gt.x)
		var y0 := float(gt.y0)
		var y1 := float(gt.y1)
		var yc := (y0 + y1) * 0.5
		var half := (y1 - y0) * 0.5
		var col := RED if String(gt.zone) == "hazard" else L.YEL
		var pg := M.part(S, 1)
		var outer := String(gt.line) == "east"
		var x := gx - 1.5 if outer else gx
		var bz := 8.6 if outer else 7.6
		M.box(pg, T, Vector3(x, y0 - 0.4, 3.6), Vector3(0.45, 0.4, 3.6), L.rp(L.GUN))
		M.box(pg, T, Vector3(x, y1 + 0.4, 3.6), Vector3(0.45, 0.4, 3.6), L.rp(L.GUN))
		M.box(pg, T, Vector3(x, yc, bz), Vector3(0.8, half + 1.0, 0.8), L.rp(L.BRUT))
		L.hazard(pg, T, Vector3(x + 0.81, y0, bz - 0.7), Vector3(x + 0.81, y1, bz - 0.7), L.X, 0.9)
		L.plate(pg, T, Vector3(x + 0.81, yc, bz), L.X, half * 0.8, 0.9, col, 77)
		for s: float in [-1.0, 1.0]:
			g.lamp(T, Vector3(x + 0.9, yc + s * (half - 1.0), bz - 1.0), L.L_RED if col == RED else L.L_GRN, 9.0, true, pg)
		M.box(pg, T, Vector3(x - 2.0, y0 + 0.6, 1.0), Vector3(0.25, 0.25, 1.0), L.rp(L.CONC))
		M.box(pg, T, Vector3(x - 2.0, yc, 1.9), Vector3(0.08, half - 0.4, 0.08), L.rp(Color8(230, 60, 50)))
		L.hazard(pg, T, Vector3(x - 3.0, y0 + 0.4, 0.04), Vector3(x - 3.0, y1 - 0.4, 0.04), L.Z, 0.5)


# ================================================================== UTILITIES (elevated racks / trays)
static func _near_road(p: Vector3) -> bool:
	for rd in SITE.roads:
		if String(rd.cls) == "rail":
			continue
		if String(rd.cls) == "hard":
			var r: Array = rd.rect
			if p.x > float(r[0]) - 0.8 and p.x < float(r[2]) + 0.8 and p.y > float(r[1]) - 0.8 and p.y < float(r[3]) + 0.8:
				return true
			continue
		var pts: Array = rd.pts
		for i in pts.size() - 1:
			var a := _v(pts[i])
			var b := _v(pts[i + 1])
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			if (a + ab * t).distance_to(p) < float(rd.w) * 0.5 + 0.8:
				return true
	for f in SITE.footprints:
		if String(f.level) != "ground":
			continue
		var r: Array = f.rect
		if p.x > float(r[0]) - 0.5 and p.x < float(r[2]) + 0.5 and p.y > float(r[1]) - 0.5 and p.y < float(r[3]) + 0.5:
			return true
	return false


static func rack(S: Array, T: Dictionary, g, d: Dictionary) -> void:
	var u: Dictionary = {}
	for x in SITE.utilities:
		if String(x.id) == String(d.u):
			u = x
	var a := _v(d.a)
	var b := _v(d.b)
	var h := float(u.h)
	var ln := a.distance_to(b)
	if ln < 0.01:
		return
	var dir := (b - a) / ln
	var side := Vector3(-dir.y, dir.x, 0)
	var pr := M.part(S, 1)
	var pipe := String(u.kind) == "pipe"
	var cols: Array = [L.YEL, Color8(70, 130, 200), Color8(200, 200, 196)]
	for k in (3 if pipe else 1):
		var col: Color = cols[k] if pipe else Color8(130, 136, 140)
		var off := -0.45 + k * 0.45 if pipe else 0.0
		M.cyl(pr, T, (a + b) * 0.5 + side * off + L.Z * (h + 0.6), dir, 0.16 if pipe else 0.08, ln * 0.5, 6, L.rp(col), {"edge": false})
	if not pipe:
		for s: float in [-0.35, 0.35]:
			M.dline(pr, T, a + side * s + L.Z * (h + 0.55), b + side * s + L.Z * (h + 0.55), Color8(90, 96, 100))
	var n := maxi(1, int(ln / 6.0))
	var bridge := false
	for k in n + 1:
		var p := a + dir * (ln * k / n)
		if _near_road(p):
			bridge = true
			continue
		M.box(pr, T, p + L.Z * h * 0.5, Vector3(0.18, 0.18, h * 0.5 + 0.3), L.rp(L.STEEL))
		M.box(pr, T, p + L.Z * (h + 0.3), (side * 0.75).abs() + Vector3(0.12, 0.12, 0.08), L.rp(L.STEEL))
	if bridge:
		for s: float in [-0.7, 0.7]:
			M.dline(pr, T, a + side * s + L.Z * (h + 1.4), b + side * s + L.Z * (h + 1.4), L.STEEL)
		for k in int(ln / 2.0):
			M.dline(pr, T, a + dir * (k * 2.0) + L.Z * h, a + dir * (k * 2.0 + 2.0) + L.Z * (h + 1.4), Color8(110, 116, 120))


## Ground medevac drone station (garrison, beside the medevac FATO): two red-cross pads, charging pedestals,
## stretcher carts, a ready-room kiosk; the two medium casualty drones sit ON their pads (audited).
static func medevac_station(S: Array, T: Dictionary, g) -> void:
	var AF: Dictionary = SITE.airfield
	var ms: Array = AF.medevac_station
	var pa := M.part(S, -0.8)
	_quad_rect(pa, T, [float(ms[0]), float(ms[1]), float(ms[2]), float(ms[3])], Color8(118, 120, 122), 0.04)
	for e in [[Vector3(ms[0], ms[1], 0.05), Vector3(ms[2], ms[1], 0.05)], [Vector3(ms[2], ms[1], 0.05), Vector3(ms[2], ms[3], 0.05)], [Vector3(ms[2], ms[3], 0.05), Vector3(ms[0], ms[3], 0.05)], [Vector3(ms[0], ms[3], 0.05), Vector3(ms[0], ms[1], 0.05)]]:
		M.dline(pa, T, e[0], e[1], Color8(220, 40, 36), L.Z)
	for mp in AF.medevac_pads:
		var c := Vector3(float(mp[0]), float(mp[1]), 0.0)
		var rr := float(mp[2])
		var ring: Array = []
		var ring2: Array = []
		for k in 16:
			var a0 := TAU * k / 16.0
			ring.append(c + Vector3(cos(a0), sin(a0), 0) * rr + L.Z * 0.06)
			ring2.append(c + Vector3(cos(a0), sin(a0), 0) * (rr - 0.6) + L.Z * 0.065)
		M.dpoly(pa, T, ring, Color8(232, 232, 228), L.Z)
		M.dpoly(pa, T, ring2, Color8(90, 92, 96), L.Z)
		L.quad(pa, T, c + L.Z * 0.07, L.X * 2.4, L.Y * 0.8, Color8(220, 40, 36))
		L.quad(pa, T, c + L.Z * 0.07, L.X * 0.8, L.Y * 2.4, Color8(220, 40, 36))
		for k in 8:
			var a0 := TAU * (k + 0.5) / 8.0
			g.lamp(T, c + Vector3(cos(a0), sin(a0), 0) * rr + L.Z * 0.2, L.L_GRN, 3.0, true, pa)
		var pc := M.part(S, 1)
		M.box(pc, T, c + Vector3(rr + 1.2, 0, 0.6), Vector3(0.3, 0.4, 0.6), L.rp(Color8(176, 180, 182)))
		g.lamp(T, c + Vector3(rr + 0.9, 0, 1.0), L.L_GRN, 3.0, true, pc)
		M.box(pc, T, c + Vector3(rr + 2.6, 2.0, 0.5), Vector3(1.0, 0.35, 0.08), L.rp(Color8(230, 230, 228)))
	L.building(S, T, g, float(ms[2]) - 6.0, (float(ms[1]) + float(ms[3])) * 0.5 - 3.0, float(ms[2]) - 0.6, (float(ms[1]) + float(ms[3])) * 0.5 + 3.0, 3.2, {"style": "panel", "floors": 1, "lit": 0.9, "seed": 77, "roof": false, "sign": Color8(220, 40, 36)})
	for cr in AF.craft:
		if String(cr.type) == "medevac":
			MD.medevac_drone(S, T, g, Vector3(float(cr.at[0]), float(cr.at[1]), float(cr.z)), float(cr.yaw))


# ================================================================== PROPS (vehicles, specimens, aircraft)
static func prop(S: Array, T: Dictionary, g, pr: Dictionary) -> void:
	var at := _v(pr.at)
	var yaw := float(pr.yaw)
	match String(pr.kind):
		"cage_truck":
			IN.cage_truck(S, T, g, at, yaw, String(pr.spec[0]), String(pr.spec[1]))
		"skycrane":
			IN.skycrane(S, T, g, Vector3(at.x, at.y, float(pr.get("z", 2.08))), yaw, true)   # skids ON the pad surface (audited)
		"truck", "apc":
			L.vehicle(S, T, g, at, yaw, String(pr.kind))
		"vtol":
			L.spec(S, T, "g7_cn", "g7_cn_stealth_dropship", "ramp_down", 1, Vector3(at.x, at.y, float(pr.get("z", 0.05))), Color8(60, 66, 74))


static func _dog(S: Array, T: Dictionary, g, at: Vector3, yaw: float) -> void:
	var Td := M.sub(T, at, yaw)
	var pt := M.part(S, 1)
	M.box(pt, Td, Vector3(0, 0, 0.75), Vector3(0.65, 0.22, 0.16), L.rp(Color8(176, 178, 170)), Vector3(0.1, 0.1, 0.05))
	M.box(pt, Td, Vector3(0.78, 0, 0.82), Vector3(0.2, 0.15, 0.12), L.rp(L.DARK))
	for fx: float in [-0.5, 0.5]:
		for s: float in [-0.2, 0.2]:
			M.dline(pt, Td, Vector3(fx, s, 0.65), Vector3(fx + 0.15, s, 0.32), Color8(60, 62, 64))
			M.dline(pt, Td, Vector3(fx + 0.15, s, 0.32), Vector3(fx, s, 0.0), Color8(60, 62, 64))
	g.lamp(Td, Vector3(0.98, 0, 0.84), L.L_CYAN, 3.0, true, pt)


# ================================================================== OUTER LAYERS: kill zone, fence, berm, ECPs
static func _road_gap(y: float) -> bool:
	for rd in SITE.roads:
		if String(rd.cls) in ["hard", "foot"]:
			continue
		var pts: Array = rd.pts
		var p0: Array = pts[0]
		if float(p0[0]) > 200.0 and absf(float(p0[1]) - y) < float(rd.w) * 0.5 + 2.0:
			return true
	return false


static func outer(S: Array, T: Dictionary, g) -> void:
	var fc: Dictionary = SITE.fence
	var bm: Dictionary = SITE.berm
	var b: Dictionary = SITE.bounds
	var fx := float(fc.x)
	var bx := float(bm.x)
	var pw := M.part(S, 0)
	var y := float(fc.yn)
	while y < float(fc.ys):
		var y1 := minf(y + 6.0, float(fc.ys))
		if not _road_gap((y + y1) * 0.5):
			for xx: float in [fx, fx + 1.2]:
				RO.wire(pw, T, Vector3(xx, y, 0), Vector3(xx, y1, 0), 2.4)
			M.cyl(pw, T, Vector3(fx, y, 1.3), L.Z, 0.06, 1.3, 4, L.rp(L.STEEL), {"edge": false})
		y = y1
	var y2 := float(bm.yn)
	while y2 < float(bm.ys) + 4.0:
		var yy := y2 + 2.0
		if not _road_gap(yy):
			var pb := M.part(S, 0)
			M.face(pb, T, [Vector3(bx, y2, 0), Vector3(bx + 2.0, y2, float(bm.h)), Vector3(bx + 2.0, y2 + 4.0, float(bm.h)), Vector3(bx, y2 + 4.0, 0)], Vector3(bx - 2, yy, -1), L.rp(Color8(110, 98, 70)))
			M.face(pb, T, [Vector3(bx + 2.0, y2, float(bm.h)), Vector3(bx + 4.0, y2, 0), Vector3(bx + 4.0, y2 + 4.0, 0), Vector3(bx + 2.0, y2 + 4.0, float(bm.h))], Vector3(bx + 6, yy, -1), L.rp(Color8(126, 112, 80)))
		y2 += 4.0
	for k in 64:
		var ty := float(b.wn) - 30.0 + k * 4.6
		if ty > float(b.ws) + 30.0 or _road_gap(ty):
			continue
		var pd := M.part(S, 0)
		for row in 2:
			var tx := float(b.wx) + 14.0 + row * 3.0
			var oy := row * 2.3
			M.prism(pd, T, [Vector3(tx, ty - 0.7 + oy, 1.4), Vector3(tx + 0.7, ty + 0.6 + oy, 1.4), Vector3(tx - 0.7, ty + 0.6 + oy, 1.4)], Vector3(0, 0, -1.4), L.rp(L.CONC))
		if k % 3 == 0:
			var sp := Vector3(float(b.wx) + 26.0, ty, 0)
			M.cyl(pd, T, sp + L.Z * 0.9, L.Z, 0.06, 0.9, 4, L.rp(L.STEEL), {"edge": false})
			M.box(pd, T, sp + L.Z * 1.9, Vector3(0.24, 0.24, 0.18), L.rp(Color8(60, 72, 60)))
			g.lamp(T, sp + L.Z * 2.15, L.L_GRN, 4.0, true, pd)
		if k % 2 == 0:
			var wp := Vector3(fx - 2.0, ty + 2.0, 0)
			M.cyl(pd, T, wp + L.Z * 0.7, L.Z, 0.05, 0.7, 4, L.rp(L.STEEL), {"edge": false})
			M.face(pd, T, [wp + Vector3(0.06, -0.35, 1.0), wp + Vector3(0.06, 0.35, 1.0), wp + Vector3(0.06, 0, 1.6)], wp - L.X, L.rp(Color8(200, 50, 40)))
	# entry control points beyond the berm: search booth with overwatch roof, drop barrier at the fence, speed table
	for rd in SITE.roads:
		if String(rd.cls) in ["hard", "foot"]:
			continue
		var p0: Array = rd.pts[0]
		if float(p0[0]) < 200.0:
			continue
		var yc := float(p0[1])
		var hw := float(rd.w) * 0.5
		var pe := M.part(S, 1)
		var bxp := bx + 12.0
		M.box(pe, T, Vector3(bxp, yc - hw - 2.6, 1.5), Vector3(1.8, 1.4, 1.5), L.rp(L.CONC))
		L.quad(pe, T, Vector3(bxp + 1.82, yc - hw - 2.6, 1.9), L.Y * 1.0, L.Z * 0.6, L.GLASS_D, L.X)
		M.box(pe, T, Vector3(bxp, yc - hw - 2.6, 3.15), Vector3(2.2, 1.8, 0.15), L.rp(L.BRUT_D))
		g.lamp(T, Vector3(bxp + 1.9, yc - hw - 2.6, 1.9), L.L_WARM, 6.0)
		M.box(pe, T, Vector3(bxp - 4.0, yc, 0.12), Vector3(0.3, hw, 0.12), L.rp(L.YEL))
		M.box(pe, T, Vector3(fx - 1.0, yc - hw + 0.4, 1.0), Vector3(0.25, 0.25, 1.0), L.rp(L.CONC))
		M.box(pe, T, Vector3(fx - 1.0, yc, 1.9), Vector3(0.08, hw - 0.4, 0.08), L.rp(Color8(230, 60, 50)))
		L.hazard(pe, T, Vector3(fx - 3.0, yc - hw, 0.04), Vector3(fx - 3.0, yc + hw, 0.04), L.Z, 0.5)
		RO.hesco(S, T, Vector3(bxp + 4.0, yc + hw + 1.6, 0), L.X, 4, 1.4, int(yc))
	L.floodmast(S, T, g, Vector3(fx + 4.0, 60.0, 0), 10.0, Vector3(1, 0.4, 0))
	L.floodmast(S, T, g, Vector3(fx + 4.0, 160.0, 0), 10.0, Vector3(1, -0.4, 0))


static func _outer_band(S: Array, T: Dictionary, g, y_fence: float, y_berm: float, sgn: float) -> void:
	var fc: Dictionary = SITE.fence
	var bm: Dictionary = SITE.berm
	var b: Dictionary = SITE.bounds
	var x0 := float(fc.xw)
	var x1 := float(fc.x)
	var pw := M.part(S, 0)
	RO.wire(pw, T, Vector3(x0, y_fence, 0), Vector3(x1, y_fence, 0), 2.4)
	RO.wire(pw, T, Vector3(x0, y_fence - sgn * 1.2, 0), Vector3(x1, y_fence - sgn * 1.2, 0), 2.4)
	var xb := x0
	while xb < float(bm.x) + 4.0:
		var pb := M.part(S, 0)
		var ya := y_berm
		M.face(pb, T, [Vector3(xb, ya, 0), Vector3(xb + 4.0, ya, 0), Vector3(xb + 4.0, ya + sgn * 2.0, float(bm.h)), Vector3(xb, ya + sgn * 2.0, float(bm.h))], Vector3(xb + 2.0, ya - sgn * 2.0, -1), L.rp(Color8(110, 98, 70)))
		M.face(pb, T, [Vector3(xb, ya + sgn * 2.0, float(bm.h)), Vector3(xb + 4.0, ya + sgn * 2.0, float(bm.h)), Vector3(xb + 4.0, ya + sgn * 4.0, 0), Vector3(xb, ya + sgn * 4.0, 0)], Vector3(xb + 2.0, ya + sgn * 6.0, -1), L.rp(Color8(126, 112, 80)))
		xb += 4.0
	var wall_y := float(b.wn) if sgn < 0 else float(b.ws)
	for k in 48:
		var tx := -20.0 + k * 4.6
		if tx > float(b.wx) + 30.0:
			break
		var pd := M.part(S, 0)
		var ty := wall_y + sgn * 14.0
		M.prism(pd, T, [Vector3(tx - 0.7, ty, 1.4), Vector3(tx + 0.6, ty + 0.7, 1.4), Vector3(tx + 0.6, ty - 0.7, 1.4)], Vector3(0, 0, -1.4), L.rp(L.CONC))
		if k % 3 == 0:
			var sp := Vector3(tx, wall_y + sgn * 26.0, 0)
			M.cyl(pd, T, sp + L.Z * 0.9, L.Z, 0.06, 0.9, 4, L.rp(L.STEEL), {"edge": false})
			g.lamp(T, sp + L.Z * 2.15, L.L_GRN, 4.0, true, pd)


static func outer_n(S: Array, T: Dictionary, g) -> void:
	_outer_band(S, T, g, float(SITE.fence.yn), float(SITE.berm.yn), -1.0)


static func outer_s(S: Array, T: Dictionary, g) -> void:
	_outer_band(S, T, g, float(SITE.fence.ys), float(SITE.berm.ys), 1.0)


# ================================================================== AIRCRAFT IN FLIGHT
static func air(S: Array, T: Dictionary, g) -> void:
	IN.warden(S, T, g, Vector3(176, 40, 32.0), PI * 1.15, true)
	for k in 3:
		IN.drone(S, T, g, Vector3(150 + k * 12.0, 70 + k * 14.0, 16.0 + k * 3.0), PI * 0.2 + k * 0.3, 1.3)


# ================================================================== AUDIT OVERLAY (its own view): the checked engineering layer
static func _ring(pt: Dictionary, T: Dictionary, c: Vector3, r: float, col: Color, fill := 0.05, dash := false) -> void:
	var n := 64
	var pts: Array = []
	for k in n:
		var a := TAU * k / n
		pts.append(c + Vector3(cos(a), sin(a), 0) * r)
	if fill > 0.0:
		M.dpoly(pt, T, pts, Color(col.r, col.g, col.b, fill), L.Z)
	for k in n:
		if dash and k % 2 == 1:
			continue
		M.dline(pt, T, pts[k], pts[(k + 1) % n], Color(col.r, col.g, col.b, 0.8), L.Z)


static func _rect_line(pt: Dictionary, T: Dictionary, r: Array, col: Color, z := 0.5) -> void:
	var x0 := float(r[0])
	var y0 := float(r[1])
	var x1 := float(r[2])
	var y1 := float(r[3])
	for e in [[Vector3(x0, y0, z), Vector3(x1, y0, z)], [Vector3(x1, y0, z), Vector3(x1, y1, z)], [Vector3(x1, y1, z), Vector3(x0, y1, z)], [Vector3(x0, y1, z), Vector3(x0, y0, z)]]:
		M.dline(pt, T, e[0], e[1], col, L.Z)


static func overlay(S: Array, T: Dictionary, g) -> void:
	var pt := M.part(S, -2)
	var TC := {"rail": Color8(255, 110, 80), "laser": Color8(80, 210, 255), "flak": Color8(255, 200, 80), "sam": Color8(200, 140, 255), "pdl": Color8(60, 255, 230), "rws": Color8(240, 240, 240), "ac": Color8(255, 160, 60)}
	for t in SITE.turrets:
		if String(t.mount) == "summit":
			continue
		_ring(pt, T, Vector3(float(t.pos[0]), float(t.pos[1]), 0.4), float(t.range), TC[String(t.kind)], 0.0)
	for q in SITE.qd:
		var f := _fp(String(q.src))
		var r: Array = f.rect
		var c := Vector3((float(r[0]) + float(r[2])) * 0.5, (float(r[1]) + float(r[3])) * 0.5, 0.45)
		var ext := maxf(float(r[2]) - float(r[0]), float(r[3]) - float(r[1])) * 0.5
		var col := Color8(255, 140, 30) if String(q.type) == "mag" else Color8(230, 80, 200)
		_ring(pt, T, c, (50.0 if String(q.type) == "mag" else 25.0) + ext, col, 0.03, true)
		_ring(pt, T, c, (30.0 if String(q.type) == "mag" else 15.0) + ext, col, 0.0, true)
	for pd in SITE.pads:
		if String(pd.level) != "ground":
			continue
		var c := _v(pd.c) + L.Z * 0.5
		var h := _v(pd.heading)
		var r := float(pd.r)
		var sd := Vector3(-h.y, h.x, 0)
		var a0 := c + h * r
		var a1 := c + h * (r + 150.0)
		M.dpoly(pt, T, [a0 - sd * r, a0 + sd * r, a1 + sd * (r + 15.0), a1 - sd * (r + 15.0)], Color(0.3, 1.0, 0.45, 0.14), L.Z)
		_ring(pt, T, c, r, Color8(80, 255, 120), 0.1)
	for d in SITE.doors:
		var f := _fp(String(d.bld))
		var r: Array = f.rect
		var at := float(d.at)
		var w := float(d.w)
		var a := float(d.apron)
		var m: float = {"heavy": 2.0, "std": 1.5, "person": 0.8, "bay": 0.5}[String(d.kind)]
		var ap: Array = []
		match String(d.side):
			"x0": ap = [float(r[0]) - a, at - w / 2 - m, float(r[0]), at + w / 2 + m]
			"x1": ap = [float(r[2]), at - w / 2 - m, float(r[2]) + a, at + w / 2 + m]
			"y0": ap = [at - w / 2 - m, float(r[1]) - a, at + w / 2 + m, float(r[1])]
			_: ap = [at - w / 2 - m, float(r[3]), at + w / 2 + m, float(r[3]) + a]
		M.dpoly(pt, T, [Vector3(ap[0], ap[1], 0.5), Vector3(ap[2], ap[1], 0.5), Vector3(ap[2], ap[3], 0.5), Vector3(ap[0], ap[3], 0.5)], Color(0.2, 1.0, 0.4, 0.28), L.Z)
		_rect_line(pt, T, ap, Color8(60, 255, 120))
	var ZC := {"hazard": Color8(255, 80, 60), "clean": Color8(90, 170, 255), "cp": Color8(255, 210, 60), "defence": Color8(200, 200, 200)}
	for f in SITE.footprints:
		if String(f.level) != "ground":
			continue
		_rect_line(pt, T, f.rect, ZC.get(String(f.zone), Color8(220, 220, 220)), 0.55)
	for u in SITE.utilities:
		var pts: Array = u.pts
		for i in pts.size() - 1:
			M.dline(pt, T, _v(pts[i]) + L.Z * 0.6, _v(pts[i + 1]) + L.Z * 0.6, Color8(230, 60, 230), L.Z)
	for rd in SITE.roads:
		if String(rd.cls) in ["hard", "rail", "foot"]:
			continue
		var pts: Array = rd.pts
		var col := Color(1.0, 0.35, 0.25, 0.9) if String(rd.zone) == "hazard" else Color(0.35, 0.65, 1.0, 0.9)
		for i in pts.size() - 1:
			M.dline(pt, T, _v(pts[i]) + L.Z * 0.6, _v(pts[i + 1]) + L.Z * 0.6, col, L.Z)
		if bool(rd.oneway):
			_chevrons(pt, T, pts, float(rd.w), col)
