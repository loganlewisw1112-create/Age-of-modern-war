extends RefCounted
## Site Blackglass v3: the mountain's interior in section (cut plane y = YS), engineered as a working base.
## Zoning (biosafety logic): HAZARD (red) = the one-way specimen spine; CLEAN (blue) = people, command, research,
## aircraft; UTILITY (orange) = power, air, water. The two sides never share a route: the hazard side has its own
## portal, intake airlock and specimen lift; the clean side has the personnel / freight core. The only crossing is
## the parts-decon airlock (dissection -> prototype works). Every chamber has a sector blast door coloured by zone.
## Levels: A hangar + air plant (z 32..44) | B command, labs, nanite culture, medical, quarters (z 16..28) |
## C intake airlock, dissection, parts decon, prototype works (z 0..14) | D containment cells, giant pit (z -14..-3)
## | E vault, incinerator, power plant (z -30..-12). Vertical: core (clean), specimen lift (hazard), 2 aircraft lifts,
## air-plant vent shaft.

const M = preload("res://tools/art/g7_cn_mesh.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const P = preload("res://tools/art/pix.gd")
const L = preload("res://.plan/blackglass4/lib.gd")
const V = preload("res://tools/art/g7_vanta.gd")

const H := "hazard"
const CL := "clean"
const U := "utility"
const OLD := [
	{"k": "hangar", "z": CL, "x0": -62.0, "x1": -27.0, "z0": 32.0, "z1": 44.0, "yb": 108.0},
	{"k": "shaft_w", "z": CL, "x0": -39.5, "x1": -28.5, "z0": 44.0, "z1": 48.5, "yb": 121.5},
	{"k": "shaft_v", "z": CL, "x0": -59.5, "x1": -48.5, "z0": 44.0, "z1": 48.5, "yb": 121.5},
	{"k": "airplant", "z": U, "x0": -88.0, "x1": -66.0, "z0": 30.0, "z1": 44.0, "yb": 112.0},
	{"k": "vent", "z": U, "x0": -79.0, "x1": -75.0, "z0": 44.0, "z1": 60.0, "yb": 128.0},
	{"k": "ops", "z": CL, "x0": -19.5, "x1": -5.5, "z0": 16.0, "z1": 28.0, "yb": 122.0},
	{"k": "core", "z": CL, "x0": -25.0, "x1": -21.0, "z0": -30.0, "z1": 44.0, "yb": 130.0},
	{"k": "labs", "z": CL, "x0": -41.0, "x1": -26.5, "z0": 16.0, "z1": 28.0, "yb": 122.0},
	{"k": "nanite", "z": U, "x0": -55.0, "x1": -42.5, "z0": 16.0, "z1": 29.0, "yb": 122.0},
	{"k": "medical", "z": CL, "x0": -65.0, "x1": -56.5, "z0": 16.0, "z1": 27.0, "yb": 124.0},
	{"k": "quarters", "z": CL, "x0": -88.0, "x1": -66.5, "z0": 16.0, "z1": 27.0, "yb": 118.0},
	{"k": "airlock", "z": H, "x0": -13.5, "x1": -3.0, "z0": 0.0, "z1": 9.0, "yb": 118.0},
	{"k": "slift", "z": H, "x0": -19.0, "x1": -15.0, "z0": -30.0, "z1": 13.0, "yb": 128.0},
	{"k": "dissect", "z": H, "x0": -47.0, "x1": -27.0, "z0": 0.0, "z1": 13.0, "yb": 116.0},
	{"k": "pdecon", "z": H, "x0": -54.0, "x1": -48.5, "z0": 0.0, "z1": 9.0, "yb": 122.0},
	{"k": "proto", "z": CL, "x0": -88.0, "x1": -55.5, "z0": 0.0, "z1": 14.0, "yb": 110.0},
	{"k": "cellsA", "z": H, "x0": -13.5, "x1": -3.0, "z0": -14.0, "z1": -3.0, "yb": 126.0},
	{"k": "cellsB", "z": H, "x0": -46.0, "x1": -27.0, "z0": -14.0, "z1": -3.0, "yb": 126.0},
	{"k": "pit", "z": H, "x0": -68.0, "x1": -48.0, "z0": -30.0, "z1": -3.0, "yb": 114.0},
	{"k": "vault", "z": H, "x0": -46.0, "x1": -27.0, "z0": -30.0, "z1": -18.0, "yb": 124.0},
	{"k": "burn", "z": H, "x0": -13.5, "x1": -3.0, "z0": -30.0, "z1": -18.0, "yb": 122.0},
	{"k": "power", "z": U, "x0": -88.0, "x1": -70.0, "z0": -30.0, "z1": -12.0, "yb": 108.0},
]
static var SITE: Dictionary = _load_site()
static var ROOMS: Array = SITE.interior.rooms
static var CORR: Array = SITE.interior.corridors


static func _load_site() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://.plan/blackglass4/site.json"))


static func _old(k: String) -> Dictionary:
	for r in OLD:
		if r.k == k:
			return r
	return {}


static func _room_by(k: String) -> Dictionary:
	for r in ROOMS:
		if r.k == k:
			return r
	return {}
const LINE := 0.9
const ZB := -32.0
const XW := -96.0
const ZCOL := {"hazard": Color8(255, 70, 50), "clean": Color8(90, 170, 255), "utility": Color8(255, 150, 40), "cp": Color8(250, 210, 60)}


static func _in_room(x: float, z: float, grow := 0.0) -> int:
	for i in ROOMS.size():
		var r: Dictionary = ROOMS[i]
		if x > r.x0 - grow and x < r.x1 + grow and z > r.z0 - grow and z < r.z1 + grow:
			return i
	for i in CORR.size():
		var c: Dictionary = CORR[i]
		if x > c.x0 - grow and x < c.x1 + grow and z > c.z - grow and z < c.z + c.h + grow:
			return 100 + i
	return -1


static func _top(g, x: float, ys: float) -> float:
	return g.mh(x, ys) if x <= 0.0 else 0.0


static func section(S: Array, T0: Dictionary, g, ys: float) -> void:
	var T := T0
	var rock: Array = L.rp(Color8(98, 92, 84))
	var rock2: Array = L.rp(Color8(86, 82, 76))
	var soil: Array = L.rp(Color8(104, 86, 64))
	var lining: Array = L.rp(Color8(168, 166, 158))
	var NL := Vector3(0, 1, 0)
	for zi in range(int(ZB), 96):
		var z0 := float(zi)
		var z1 := z0 + 1.0
		var pt := M.part(S, 1)
		var run_m := ""
		var run_x0 := 0.0
		var xa := -112.0
		while xa < 36.0:
			var xc := xa + 0.5
			var top := _top(g, xc, ys)
			var mat := ""
			if z0 < top and not (xc < XW and z0 < 0.0) and not (xc > 0.0 and z0 >= 0.0):
				if _in_room(xc, z0 + 0.5) >= 0:
					mat = ""
				elif _in_room(xc, z0 + 0.5, LINE) >= 0:
					mat = "lin"
				elif z0 >= -3.0 and z0 < 0.0:
					mat = "soil"
				elif z1 > top:
					mat = "topcell"
				else:
					mat = "rock" if int(floor(z0 / 6.0)) % 2 == 0 else "rock2"
			if mat == "topcell":
				_flush(pt, T, run_m, run_x0, xa, z0, z1, ys, rock, rock2, soil, lining)
				run_m = ""
				var ta := _top(g, xa, ys)
				var tb := _top(g, xa + 1.0, ys)
				if minf(ta, tb) > z0:
					M.face(pt, T, [Vector3(xa, ys, z0), Vector3(xa + 1.0, ys, z0), Vector3(xa + 1.0, ys, minf(tb, z1)), Vector3(xa, ys, minf(ta, z1))], Vector3(xa + 0.5, ys - 2, z0), rock, {"edge": false})
					M.dline(pt, T, Vector3(xa, ys + 0.02, minf(ta, z1)), Vector3(xa + 1.0, ys + 0.02, minf(tb, z1)), Color8(30, 28, 26), NL)
				xa += 1.0
				continue
			if mat != run_m:
				_flush(pt, T, run_m, run_x0, xa, z0, z1, ys, rock, rock2, soil, lining)
				run_m = mat
				run_x0 = xa
			xa += 1.0
		_flush(pt, T, run_m, run_x0, xa, z0, z1, ys, rock, rock2, soil, lining)
	var ph := M.part(S, 1.05)
	for k in range(-60, 40):
		var x0 := k * 4.0
		for s in 40:
			var za := ZB + s * 3.2
			var xm := x0 + 0.8
			var zm := za + 0.8
			if xm < -112.0 or xm > 36.0 or zm >= _top(g, xm, ys) - 0.6 or _in_room(xm, zm, LINE + 0.4) >= 0:
				continue
			if (xm < XW and zm < 0.0) or (xm > 0.0 and zm >= 0.0):
				continue
			M.dline(ph, T, Vector3(x0, ys + 0.02, za), Vector3(x0 + 1.6, ys + 0.02, za + 1.6), Color(0.18, 0.16, 0.14, 0.4), NL)
	for r in ROOMS:
		var col: Color = ZCOL[r.z]
		var a := Vector3(r.x0 - LINE, ys + 0.03, r.z0 - LINE)
		var b := Vector3(r.x1 + LINE, ys + 0.03, r.z1 + LINE)
		for e in [[Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z)], [Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z)], [Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z)], [Vector3(a.x, a.y, b.z), Vector3(a.x, a.y, a.z)]]:
			M.dline(ph, T, e[0], e[1], Color8(26, 28, 30), NL)
		M.dline(ph, T, Vector3(a.x + 0.4, ys + 0.035, a.z + 0.3), Vector3(b.x - 0.4, ys + 0.035, a.z + 0.3), col, NL)
	for k in 5:   # seismic bores under the plain in front of the mountain (anti-burrow grid)
		var bx := 4.0 + k * 7.0
		M.dline(ph, T, Vector3(bx, ys + 0.03, -1.0), Vector3(bx, ys + 0.03, -28.0), Color8(60, 200, 110), NL)
		for j in 4:
			M.box(ph, T, Vector3(bx, ys + 0.12, -6.0 - j * 6.0), Vector3(0.25, 0.1, 0.25), L.rp(Color8(60, 200, 110)))
			g.lamp(T, Vector3(bx, ys + 0.2, -6.0 - j * 6.0), L.L_GRN, 4.0)
	M.dline(ph, T, Vector3(XW, ys + 0.03, 0.0), Vector3(36, ys + 0.03, 0.0), Color8(70, 96, 50), NL)
	var pf := M.part(S, -1)
	L.quad(pf, T, Vector3((XW + 36.0) * 0.5, ys + 26, ZB), L.X * (36.0 - XW) * 0.5, L.Y * 26.0, Color8(70, 66, 60))
	for k in 70:
		var rc := Vector3(XW + 2.0 + (34.0 - XW) * P.hn(k, 1, 91), ys + 2 + 48 * P.hn(k, 2, 91), ZB + 0.3)
		M.box(M.part(S, 0), T, rc, Vector3(0.5 + P.hn(k, 3, 91), 0.4 + P.hn(k, 4, 91), 0.3 + 0.4 * P.hn(k, 5, 91)), L.rp(Color8(96, 90, 82)), Vector3(0.2, 0.2, 0.2))
	var pw := M.part(S, 0.8)
	M.face(pw, T, [Vector3(XW, ys, ZB), Vector3(XW, ys + 52, ZB), Vector3(XW, ys + 52, -3), Vector3(XW, ys, -3)], Vector3(XW - 2, ys + 20, -10), rock2, {"edge": false})
	M.face(pw, T, [Vector3(XW, ys, -3), Vector3(XW, ys + 52, -3), Vector3(XW, ys + 52, 0), Vector3(XW, ys, 0)], Vector3(XW - 2, ys + 20, -1), soil, {"edge": false})
	for r in ROOMS:
		_room(S, T, g, r, ys)
	_corridors(S, T, g, ys)
	for rn in ROOMS:
		var r: Dictionary = _old(String(rn.k))
		if r.is_empty():
			match String(rn.k):
				"freight": _c_freight(S, T, g, rn, ys)
				"wstair": _c_wstair(S, T, g, rn, ys)
			continue
		var dx: float = (float(rn.x0) + float(rn.x1)) * 0.5 - (float(r.x0) + float(r.x1)) * 0.5
		var dz: float = 0.0 if rn.get("vertical", false) or String(rn.k) in ["vent"] else float(rn.z0) - float(r.z0)
		if String(rn.k) == "core":
			dz = 0.0
		T = M.sub(T0, Vector3(dx, 0, dz))
		match String(r.k):
			"hangar": _c_hangar(S, T, g, r, ys)
			"shaft_w", "shaft_v": _c_shaft(S, T, g, r, ys)
			"airplant": _c_airplant(S, T, g, r, ys)
			"vent": _c_vent(S, T, g, r, ys)
			"ops": _c_ops(S, T, g, r, ys)
			"core": _c_core(S, T, g, r, ys)
			"labs": _c_labs(S, T, g, r, ys)
			"nanite": _c_nanite(S, T, g, r, ys)
			"medical": _c_medical(S, T, g, r, ys)
			"quarters": _c_quarters(S, T, g, r, ys)
			"airlock": _c_airlock(S, T, g, r, ys)
			"slift": _c_slift(S, T, g, r, ys)
			"dissect": _c_dissect(S, T, g, r, ys)
			"pdecon": _c_pdecon(S, T, g, r, ys)
			"proto": _c_proto(S, T, g, r, ys)
			"cellsA", "cellsB": _c_cells(S, T, g, r, ys)
			"pit": _c_pit(S, T, g, r, ys)
			"vault": _c_vault(S, T, g, r, ys)
			"burn": _c_burn(S, T, g, r, ys)
			"power": _c_power(S, T, g, r, ys)


static func _flush(pt: Dictionary, T: Dictionary, m: String, x0: float, x1: float, z0: float, z1: float, ys: float, rock: Array, rock2: Array, soil: Array, lining: Array) -> void:
	if m == "" or x1 <= x0:
		return
	var rpp: Array = rock if m == "rock" else (rock2 if m == "rock2" else (soil if m == "soil" else lining))
	M.face(pt, T, [Vector3(x0, ys, z0), Vector3(x1, ys, z0), Vector3(x1, ys, z1), Vector3(x0, ys, z1)], Vector3((x0 + x1) * 0.5, ys - 2, (z0 + z1) * 0.5), rpp, {"edge": false})


static func _room(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	var zone: String = r.z
	var k: String = r.k
	var zc: Color = ZCOL[zone]
	var wallc := L.LAB if zone == CL else (Color8(196, 192, 188) if zone == H else Color8(140, 138, 132))
	var floorc := Color8(178, 182, 186) if zone == CL else (Color8(150, 148, 146) if zone == H else Color8(100, 102, 104))
	var x0: float = r.x0
	var x1: float = r.x1
	var z0: float = r.z0
	var z1: float = r.z1
	var yb: float = r.yb
	var pr := M.part(S, 0)
	M.face(pr, T, [Vector3(x0, yb, z0), Vector3(x1, yb, z0), Vector3(x1, ys, z0), Vector3(x0, ys, z0)], Vector3((x0 + x1) * 0.5, (yb + ys) * 0.5, z0 - 2), L.rp(floorc), {"edge": false})
	M.face(pr, T, [Vector3(x0, yb, z0), Vector3(x1, yb, z0), Vector3(x1, yb, z1), Vector3(x0, yb, z1)], Vector3((x0 + x1) * 0.5, yb - 2, (z0 + z1) * 0.5), L.rp(wallc), {"edge": false})
	M.face(pr, T, [Vector3(x0, yb, z0), Vector3(x0, ys, z0), Vector3(x0, ys, z1), Vector3(x0, yb, z1)], Vector3(x0 - 2, (yb + ys) * 0.5, (z0 + z1) * 0.5), L.rp(P.mul(wallc, 0.9)), {"edge": false})
	for i in range(1, int((x1 - x0) / 2.4)):
		M.dline(pr, T, Vector3(x0 + i * 2.4, yb + 0.02, z0), Vector3(x0 + i * 2.4, yb + 0.02, z1), Color(0.3, 0.32, 0.34, 0.3), L.Y)
	for i in range(1, int((x1 - x0) / 2.0)):
		M.dline(pr, T, Vector3(x0 + i * 2.0, yb, z0 + 0.02), Vector3(x0 + i * 2.0, ys, z0 + 0.02), Color(0.3, 0.3, 0.32, 0.18), L.Z)
	if k == "core" or k == "slift" or k == "vent" or k.begins_with("shaft"):
		return
	if zone == H:
		L.hazard(pr, T, Vector3(x0 + 0.3, ys - 0.8, z0 + 0.03), Vector3(x1 - 0.3, ys - 0.8, z0 + 0.03), L.Z, 0.7)
		for i in int((x1 - x0) / 1.4):
			M.dline(pr, T, Vector3(x0 + 0.5 + i * 1.4, ys - 2.4, z0 + 0.03), Vector3(x0 + 1.2 + i * 1.4, ys - 1.4, z0 + 0.03), Color(1, 0.3, 0.2, 0.5), L.Z)
	else:
		M.dline(pr, T, Vector3(x0 + 0.3, ys - 0.8, z0 + 0.03), Vector3(x1 - 0.3, ys - 0.8, z0 + 0.03), zc, L.Z)
	for i in range(0, int((x1 - x0) / 5.0)):
		var lp := Vector3(x0 + 2.5 + i * 5.0, yb + 0.03, z1 - 0.6)
		M.dline(pr, T, lp - L.X * 1.2, lp + L.X * 1.2, L.LAMP_W, L.Y)
		g.lamp(T, lp + L.Y * 0.4, L.L_COLD if zone == CL else (Color(1.0, 0.75, 0.7, 0.55) if zone == H else L.L_WARM), 8.0)
	g.pool(T, Vector3((x0 + x1) * 0.5, (yb + ys) * 0.5, z0 + 0.1), (x1 - x0) * 0.45, (ys - yb) * 0.4, Color(0.9, 0.95, 1.0, 0.32) if zone != H else Color(1.0, 0.7, 0.65, 0.32))
	M.box(pr, T, Vector3((x0 + x1) * 0.5, yb + 0.35, z1 - 1.2), Vector3((x1 - x0) * 0.5 - 0.3, 0.25, 0.06), L.rp(Color8(110, 114, 118)))
	M.cyl(pr, T, Vector3((x0 + x1) * 0.5, yb + 0.7, z1 - 0.4), L.X, 0.06, (x1 - x0) * 0.5 - 0.3, 4, L.rp(Color8(200, 60, 50)), {"edge": false})
	L.plate(pr, T, Vector3(x0 + minf(4.0, (x1 - x0) * 0.3), yb + 0.02, z1 - 1.8), L.Y, minf(5.0, (x1 - x0) * 0.4), 0.7, zc, int(x0))


static func _crew(S: Array, T: Dictionary, ids: Array, frames: Array, pts: Array) -> void:
	for i in pts.size():
		L.spec(S, T, "g7_cn", ids[i % ids.size()], frames[i % frames.size()], (i * 3 + 1) % 8, pts[i], L.TEAM)


# ================================================================== CONTENTS
static func _c_hangar(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	var ph := M.part(S, 0.5)
	for e in [[Vector3(-61, 127, 32.03), Vector3(-28, 127, 32.03)], [Vector3(-44, 110, 32.03), Vector3(-44, 139, 32.03)]]:
		M.dline(ph, T, e[0], e[1], L.YEL, L.Z)
	var pv := M.part(S, 0.6)
	M.box(pv, T, Vector3(-54, 127, 32.2), Vector3(5.8, 5.8, 0.2), L.rp(Color8(96, 98, 102)))
	L.hazard(pv, T, Vector3(-59.8, 132.8, 32.42), Vector3(-48.2, 132.8, 32.42), L.Z)
	for xx: float in [-60.2, -47.8, -40.2, -27.8]:
		M.box(pv, T, Vector3(xx, 132.4, 40.2), Vector3(0.25, 0.25, 8.2), L.rp(L.YEL))
	L.spec(S, T, "g7_cn", "g7_cn_stealth_dropship", "ramp_down", 1, Vector3(-54, 127, 32.4), Color8(60, 66, 74))
	for s: float in [-1.0, 1.0]:
		g.lamp(T, Vector3(-54 + s * 6.0, 133.0, 36.0), L.L_AMB, 9.0, true, pv)
	M.box(pv, T, Vector3(-34, 127, 47.4), Vector3(5.6, 5.6, 0.25), L.rp(Color8(70, 74, 78)))
	for xx: float in [-36.0, -32.0]:
		M.cyl(pv, T, Vector3(xx, 130.0, 39.8), L.Z, 0.35, 7.6, 8, L.rp(Color8(190, 194, 198)))
	var pg := M.part(S, 1.2)
	for xx: float in [-50.0, -38.0]:
		M.box(pg, T, Vector3(xx, 113.0, 37.5), Vector3(0.3, 0.3, 5.5), L.rp(L.YEL))
	M.box(pg, T, Vector3(-44.0, 113.0, 43.2), Vector3(6.3, 0.35, 0.3), L.rp(L.YEL))
	L.spec(S, T, "g7_vanta", "cn_vanta_a", "landed", 1, Vector3(-44, 115.5, 32.1), L.TEAM)
	for i in 2:
		var pr := M.part(S, 0.7)
		var rx := -60.0 + i * 5.5
		for lv in 3:
			M.box(pr, T, Vector3(rx, 109.4, 33.0 + lv * 2.6), Vector3(2.4, 0.8, 0.08), L.rp(L.STEEL))
			for d in 2:
				drone(S, T, g, Vector3(rx - 1.0 + d * 2.0, 109.6, 33.15 + lv * 2.6), 0.0, 0.55)
	L.vehicle(S, T, g, Vector3(-30, 114, 32.0), PI * 0.5, "truck")
	_crew(S, T, ["g7_cn_deploy", "g7_cn_radio", "g7_cn_scanner"], ["act_0", "idle", "act_1"], [Vector3(-58, 136, 32.1), Vector3(-47, 133, 32.1), Vector3(-38, 136, 32.1), Vector3(-31, 133, 32.1)])


static func _c_shaft(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	var ps := M.part(S, 0.4)
	var cx := (float(r.x0) + float(r.x1)) * 0.5
	for k in 4:
		M.dline(ps, T, Vector3(cx - 5.4, 121.6, 44.5 + k), Vector3(cx + 5.4, 121.6, 44.5 + k), Color(1, 0.8, 0.3, 0.4), L.Y)


static func _c_airplant(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	for k in 3:
		var pf := M.part(S, 0.8)
		var c := Vector3(-85.0 + k * 6.6, 120.0, 34.6)
		M.box(pf, T, c, Vector3(2.6, 3.2, 2.6), L.rp(Color8(150, 120, 80)))
		M.cyl(pf, T, c + Vector3(0, 3.25, 0), L.Y, 2.1, 0.05, 16, L.rp(Color8(40, 42, 44)), {"cap_t": 0})
		for b in 6:
			var a := TAU * b / 6.0
			M.dline(pf, T, c + Vector3(0, 3.32, 0), c + Vector3(cos(a) * 1.9, 3.32, sin(a) * 1.9), Color8(150, 154, 158), L.Y)
		M.cyl(pf, T, c + Vector3(0, 0, 4.2), L.Z, 0.9, 1.6, 10, L.rp(Color8(176, 178, 180)))
	for k in 4:
		var pb := M.part(S, 0.7)
		M.box(pb, T, Vector3(-86.0 + k * 5.2, 135.0, 32.5), Vector3(2.2, 1.2, 2.5), L.rp(Color8(200, 200, 196)))
		for j in 5:
			M.dline(pb, T, Vector3(-87.8 + k * 5.2 + j * 0.9, 136.22, 30.4), Vector3(-87.8 + k * 5.2 + j * 0.9, 136.22, 34.6), Color8(130, 134, 138), L.Y)
		g.lamp(T, Vector3(-86.0 + k * 5.2, 136.3, 34.8), L.L_GRN, 3.0)
	var pd := M.part(S, 1.0)
	M.cyl(pd, T, Vector3(-77.0, 124.0, 42.0), L.X, 1.0, 8.5, 10, L.rp(Color8(176, 178, 180)))
	_crew(S, T, ["g7_cn_deploy"], ["act_0"], [Vector3(-70, 136, 30.1)])


static func _c_vent(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	var pv := M.part(S, 0.8)
	M.cyl(pv, T, Vector3(-77.0, 131.0, 52.0), L.Z, 1.4, 8.0, 10, L.rp(Color8(176, 178, 180)))
	for k in 3:
		M.box(pv, T, Vector3(-77.0, 131.0, 46.0 + k * 5.0), Vector3(1.6, 1.6, 0.12), L.rp(Color8(150, 120, 80)))
	for k in 10:
		M.dline(pv, T, Vector3(-75.3, 134.0, 44.6 + k * 1.5), Vector3(-75.3, 135.0, 44.6 + k * 1.5), L.YEL, L.X)


static func _c_ops(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	var po := M.part(S, 0.6)
	L.quad(po, T, Vector3(-12.5, 122.05, 22.6), L.X * 6.0, L.Z * 3.6, Color8(22, 38, 58), L.Y)
	for i in 16:
		var a := Vector3(-18 + 11.0 * P.hn(i, 1, 101), 122.08, 19.6 + 5.8 * P.hn(i, 2, 101))
		M.dline(po, T, a, a + Vector3(1.4 * P.hn(i, 3, 101), 0, 0.6 * (P.hn(i, 4, 101) - 0.5)), Color8(100, 200, 255), L.Y)
	M.dpoly(po, T, [Vector3(-15.0, 122.09, 20.5), Vector3(-11.0, 122.09, 21.4), Vector3(-9.0, 122.09, 23.8), Vector3(-13.0, 122.09, 24.6)], Color(0.95, 0.3, 0.25, 0.55), L.Y)
	g.lamp(T, Vector3(-12.5, 122.6, 22.6), Color(0.4, 0.75, 1.0, 0.9), 26.0)
	for row in 3:
		var pc := M.part(S, 0.8)
		var cy := 125.5 + row * 3.8
		M.box(pc, T, Vector3(-12.5, cy, 16.6), Vector3(5.2, 0.5, 0.6), L.rp(L.GUN))
		for k in 5:
			L.quad(pc, T, Vector3(-16.6 + k * 2.05, cy - 0.3, 17.6), L.X * 0.75, L.Z * 0.35, Color8(90, 190, 240), Vector3(0, -1, 0))
			M.box(pc, T, Vector3(-16.6 + k * 2.05, cy - 0.2, 17.5), Vector3(0.75, 0.05, 0.35), L.rp(L.DARK))
			g.lamp(T, Vector3(-16.6 + k * 2.05, cy + 0.2, 17.6), L.L_CYAN, 4.0)
	var ph := M.part(S, 0.9)
	M.cyl(ph, T, Vector3(-9.0, 136.0, 16.6), L.Z, 1.4, 0.6, 12, L.rp(L.DARK))
	g.lamp(T, Vector3(-9.0, 136.0, 17.6), Color(0.4, 0.9, 1.0, 0.85), 14.0)
	_crew(S, T, ["g7_cn_team_leader", "g7_cn_radio", "g7_op_leader", "g7_cn_ew"], ["idle"], [Vector3(-17, 127, 16.1), Vector3(-13, 127, 16.1), Vector3(-9, 130.8, 16.1), Vector3(-15, 134.6, 16.1), Vector3(-10.5, 137.5, 16.1)])
	g.lamp(T, Vector3(-6.0, 123.0, 27.0), L.L_RED, 8.0)


static func _c_core(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	var pk := M.part(S, 0.6)
	for xx: float in [-24.6, -21.4]:
		M.box(pk, T, Vector3(xx, 131.0, 7.0), Vector3(0.12, 0.12, 37.0), L.rp(L.STEEL))
	for zz: float in [32.0, 16.0, 0.0, -14.0, -30.0]:
		L.quad(pk, T, Vector3(-23.0, 130.04, zz + 1.4), L.X * 1.2, L.Z * 1.4, Color8(150, 156, 160), L.Y)
		M.dline(pk, T, Vector3(-23.0, 130.05, zz), Vector3(-23.0, 130.05, zz + 2.8), Color8(40, 44, 48), L.Y)
		g.lamp(T, Vector3(-21.8, 130.2, zz + 3.2), L.L_CYAN, 4.0, true, pk)
	M.box(pk, T, Vector3(-23.0, 133.0, 1.5), Vector3(1.6, 2.6, 1.5), L.rp(Color8(180, 184, 186)))
	L.quad(pk, T, Vector3(-23.0, 135.62, 1.7), L.X * 1.0, L.Z * 0.9, Color8(240, 225, 170), L.Y)
	g.lamp(T, Vector3(-23.0, 135.7, 1.7), L.L_WARM, 8.0)
	for xx: float in [-23.6, -22.4]:
		M.dline(pk, T, Vector3(xx, 133.0, 3.0), Vector3(xx, 133.0, 43.8), Color8(40, 42, 44))


static func _c_labs(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	for k in 3:
		var pb := M.part(S, 0.7)
		var bx := -39.0 + k * 4.4
		M.box(pb, T, Vector3(bx, 128.0, 16.5), Vector3(1.8, 0.8, 0.5), L.rp(Color8(190, 194, 196)))
		L.quad(pb, T, Vector3(bx, 127.6, 17.5), L.X * 0.6, L.Z * 0.35, Color8(90, 190, 240), Vector3(0, -1, 0))
		M.box(pb, T, Vector3(bx, 127.7, 17.5), Vector3(0.6, 0.05, 0.35), L.rp(L.DARK))
		g.lamp(T, Vector3(bx, 128.2, 17.5), L.L_CYAN, 4.0)
	var pcs := M.part(S, 0.7)
	for k in 4:
		M.box(pcs, T, Vector3(-39.0 + k * 3.2, 122.8, 18.0), Vector3(1.3, 0.6, 2.0), L.rp(Color8(70, 74, 78)))
		for j in 3:
			M.cyl(pcs, T, Vector3(-39.6 + k * 3.2 + j * 0.6, 123.45, 18.6), L.Z, 0.15, 0.15, 6, L.rp(Color8(180, 60, 50)))
			g.lamp(T, Vector3(-39.6 + k * 3.2 + j * 0.6, 123.5, 18.8), Color(1, 0.3, 0.25, 0.7), 3.0)
		L.quad(pcs, T, Vector3(-39.0 + k * 3.2, 123.42, 18.0), L.X * 1.2, L.Z * 1.8, L.GLASS, L.Y)
	var pt := M.part(S, 0.8)
	M.box(pt, T, Vector3(-30.0, 133.0, 17.2), Vector3(2.2, 1.4, 1.2), L.rp(Color8(176, 180, 184)))
	M.cyl(pt, T, Vector3(-30.0, 133.0, 19.6), L.Z, 1.2, 1.2, 12, L.rp(Color8(160, 210, 230)), {"caps": false})
	L.spec(S, T, "g7_threats2", "g7_m_leech", "idle", 1, Vector3(-30.0, 133.0, 18.5), L.MACH)
	for s: float in [-1.0, 1.0]:
		M.cyl(pt, T, Vector3(-30.0 + s * 0.8, 134.2, 18.0), Vector3(0, 1, 0.4), 0.12, 0.6, 6, L.rp(L.GUN))
	g.lamp(T, Vector3(-30.0, 134.4, 19.6), L.L_CYAN, 8.0)
	M.cyl(pt, T, Vector3(-37.0, 136.0, 16.6), L.Z, 1.2, 0.6, 12, L.rp(L.DARK))
	g.lamp(T, Vector3(-37.0, 136.0, 17.6), Color(0.4, 0.9, 1.0, 0.8), 12.0)
	_crew(S, T, ["g7_op_purge", "g7_cn_scanner"], ["act_0", "idle", "act_1"], [Vector3(-38, 131.5, 16.1), Vector3(-33.5, 136, 16.1), Vector3(-28, 136, 16.1)])


static func _c_nanite(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	for k in 3:
		var pn := M.part(S, 0.8)
		var c := Vector3(-52.5 + k * 4.6, 128.0, 16.0)
		M.cyl(pn, T, c + L.Z * 4.8, L.Z, 1.8, 4.6, 14, L.rp(Color8(176, 182, 188)), {"cap_t": 4})
		for b in 3:
			M.cyl(pn, T, c + L.Z * (1.4 + b * 3.4), L.Z, 1.85, 0.08, 14, L.rp(L.STEEL), {"caps": false})
		M.dpoly(pn, T, [c + L.Y * 1.82 + Vector3(-0.55, 0, 1.6), c + L.Y * 1.82 + Vector3(0.55, 0, 1.6), c + L.Y * 1.82 + Vector3(0.55, 0, 8.0), c + L.Y * 1.82 + Vector3(-0.55, 0, 8.0)], Color8(160, 225, 245), L.Y)
		g.lamp(T, c + L.Y * 2.0 + L.Z * 5.0, Color(0.6, 0.95, 1.0, 1.0), 14.0)
	var pp := M.part(S, 1.0)
	M.cyl(pp, T, Vector3(-48.0, 128.0, 26.2), L.X, 0.25, 6.5, 6, L.rp(Color8(200, 70, 50)))
	L.railing(pp, T, Vector3(-54.5, 131.0, 26.0), Vector3(-43.0, 131.0, 26.0))
	M.box(pp, T, Vector3(-48.75, 131.0, 25.9), Vector3(5.75, 0.8, 0.08), L.rp(Color8(70, 74, 78)))


static func _c_medical(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	for k in 3:
		var pb := M.part(S, 0.7)
		M.box(pb, T, Vector3(-63.5 + k * 2.6, 127.0, 16.7), Vector3(0.9, 1.6, 0.25), L.rp(Color8(220, 224, 226)))
		M.box(pb, T, Vector3(-63.5 + k * 2.6, 125.7, 17.6), Vector3(0.9, 0.12, 0.7), L.rp(Color8(210, 214, 216)))
		g.lamp(T, Vector3(-63.5 + k * 2.6, 125.9, 18.6), L.L_GRN, 3.0, true, pb)
	var ps := M.part(S, 0.8)
	for yy: float in [133.0, 137.5]:
		M.box(ps, T, Vector3(-60.5, yy, 18.6), Vector3(3.4, 0.12, 2.6), L.rp(Color8(176, 196, 210)))
	for k in 4:
		g.lamp(T, Vector3(-63.0 + k * 1.7, 135.2, 20.8), L.L_CYAN, 4.0, true, ps)
	M.dpoly(ps, T, [Vector3(-63.8, 135.2, 16.2), Vector3(-57.2, 135.2, 16.2), Vector3(-57.2, 135.2, 20.8), Vector3(-63.8, 135.2, 20.8)], Color(0.8, 0.95, 1.0, 0.2), L.Y)
	_crew(S, T, ["g7_cn_medic"], ["act_0", "idle"], [Vector3(-61.0, 129.5, 16.1), Vector3(-58.5, 136.0, 16.1)])


static func _c_quarters(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	for k in 5:
		var pq := M.part(S, 0.7)
		var bx := -86.0 + k * 3.4
		for lv in 2:
			M.box(pq, T, Vector3(bx, 124.0, 16.6 + lv * 1.6), Vector3(1.0, 1.8, 0.2), L.rp(Color8(86, 96, 80)))
			M.box(pq, T, Vector3(bx, 124.0, 16.85 + lv * 1.6), Vector3(0.9, 1.7, 0.08), L.rp(Color8(176, 170, 150)))
		M.box(pq, T, Vector3(bx + 1.2, 122.5, 17.6), Vector3(0.12, 0.12, 1.6), L.rp(L.STEEL))
	var pm := M.part(S, 0.8)
	M.box(pm, T, Vector3(-74.0, 133.0, 16.8), Vector3(3.6, 1.0, 0.1), L.rp(Color8(150, 130, 100)))
	g.lamp(T, Vector3(-74.0, 133.0, 19.6), L.L_WARM, 14.0)
	var pe := M.part(S, 0.6)
	L.quad(pe, T, Vector3(-69.5, 118.04, 18.0), L.X * 1.6, L.Z * 2.0, Color8(10, 11, 12), L.Y)
	for k in 4:
		g.lamp(T, Vector3(-69.5, 118.2, 19.6 - k * 0.2), Color(0.3, 1.0, 0.45, 0.7 - k * 0.15), 5.0 - k)
	L.quad(pe, T, Vector3(-69.5, 118.05, 20.8), L.X * 1.0, L.Z * 0.3, Color8(60, 200, 90), L.Y)
	g.lamp(T, Vector3(-69.5, 118.3, 20.8), L.L_GRN, 6.0)
	_crew(S, T, ["g7_cn_gunner", "g7_cn_medic", "g7_cn_deploy"], ["crouch", "idle"], [Vector3(-76, 135.5, 16.1), Vector3(-73, 136.5, 16.1), Vector3(-70, 135, 16.1)])


static func _c_airlock(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	var pa := M.part(S, 0.8)
	L.quad(pa, T, Vector3(-8.2, 118.04, 3.4), L.X * 3.4, L.Z * 3.4, Color8(80, 84, 88), L.Y)
	for i in 6:
		M.dline(pa, T, Vector3(-11.4, 118.06, 0.6 + i * 1.1), Vector3(-5.0, 118.06, 1.2 + i * 1.1), Color8(226, 184, 40) if i % 2 == 0 else Color8(40, 38, 34), L.Y)
	g.lamp(T, Vector3(-8.2, 118.3, 7.2), L.L_RED, 9.0, true, pa)
	for xx: float in [-12.6, -3.9]:
		M.box(pa, T, Vector3(xx, 128.0, 3.8), Vector3(0.35, 0.5, 3.8), L.rp(L.BRUT))
	M.box(pa, T, Vector3(-8.25, 128.0, 7.8), Vector3(4.7, 0.5, 0.4), L.rp(L.BRUT))
	for k in 6:
		M.dline(pa, T, Vector3(-11.6 + k * 1.35, 128.52, 7.3), Vector3(-11.6 + k * 1.35, 128.52, 0.4), Color(0.45, 0.8, 1.0, 0.7), L.Y)
		g.lamp(T, Vector3(-11.6 + k * 1.35, 128.8, 7.3), L.L_CYAN, 5.0, true, pa)
	cage_truck(S, T, g, Vector3(-8.0, 133.0, 0.0), PI * 0.5, "g7_threats2", "g7_m_burrower")
	_crew(S, T, ["g7_op_emp", "g7_op_purge"], ["idle", "fire"], [Vector3(-12.6, 137.0, 0.1), Vector3(-3.8, 137.0, 0.1)])


static func _c_slift(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	var pl := M.part(S, 0.6)
	for xx: float in [-18.6, -15.4]:
		M.box(pl, T, Vector3(xx, 129.0, -8.5), Vector3(0.12, 0.12, 21.5), L.rp(L.YEL))
	M.box(pl, T, Vector3(-17.0, 133.0, -13.8), Vector3(1.7, 3.6, 0.15), L.rp(Color8(96, 98, 102)))
	for d: Vector2 in [Vector2(-1.5, -3.2), Vector2(1.5, -3.2), Vector2(1.5, 3.2), Vector2(-1.5, 3.2)]:
		M.box(pl, T, Vector3(-17.0 + d.x, 133.0 + d.y, -12.1), Vector3(0.08, 0.08, 1.6), L.rp(L.STEEL))
	for k in 6:
		M.dline(pl, T, Vector3(-15.5, 130.0 + k * 1.2, -13.6), Vector3(-15.5, 130.0 + k * 1.2, -10.5), Color8(70, 76, 82), L.X)
	L.spec(S, T, "g7_threats2", "g7_m_spitter", "idle", 2, Vector3(-17.0, 133.0, -13.6), L.MACH, 0.9)
	for zz: float in [10.0, -2.0, -16.0, -26.0]:
		g.lamp(T, Vector3(-15.2, 136.0, zz), L.L_RED, 5.0, true, pl)
	for xx: float in [-17.6, -16.4]:
		M.dline(pl, T, Vector3(xx, 133.0, -13.6), Vector3(xx, 133.0, 12.8), Color8(40, 42, 44))


static func _c_dissect(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	var pdh := M.part(S, 1.0)
	for xx: float in [-45.0, -29.0]:
		M.box(pdh, T, Vector3(xx, 126.0, 5.8), Vector3(0.3, 0.3, 5.8), L.rp(L.YEL))
	M.box(pdh, T, Vector3(-37.0, 126.0, 11.8), Vector3(8.3, 0.4, 0.35), L.rp(L.YEL))
	M.box(pdh, T, Vector3(-41.0, 126.0, 11.2), Vector3(0.8, 0.6, 0.35), L.rp(L.DARK))
	for s: float in [-0.5, 0.5]:
		M.dline(pdh, T, Vector3(-41.0 + s, 126.0, 10.8), Vector3(-41.0 + s * 1.6, 126.0, 6.4), Color8(40, 42, 44))
	L.spec(S, T, "g7_threats", "g7_m_packhunter", "walk_a", 2, Vector3(-41.0, 126.0, 4.2), L.MACH)
	M.box(pdh, T, Vector3(-33.0, 131.0, 0.9), Vector3(3.6, 2.0, 0.9), L.rp(Color8(150, 156, 162)))
	L.spec(S, T, "g7_threats2", "g7_m_walker_topple", "down", 1, Vector3(-33.0, 131.0, 1.8), L.MACH)
	for a in 3:
		var pa := M.part(S, 1.1)
		var base := Vector3(-37.5 + a * 4.5, 134.8, 0.0)
		var tip := Vector3(-34.5 + a * 1.4, 131.4, 2.4)
		var j1 := base + L.Z * 3.0
		var j2 := (j1 + tip) * 0.5 + L.Z * 1.6
		M.cyl(pa, T, base + L.Z * 0.5, L.Z, 0.5, 0.5, 8, L.rp(L.ORANGE))
		M.cyl(pa, T, (base + j1) * 0.5 + L.Z * 0.5, L.Z, 0.25, 1.2, 6, L.rp(L.ORANGE))
		M.cyl(pa, T, (j1 + j2) * 0.5, (j2 - j1).normalized(), 0.2, (j2 - j1).length() * 0.5, 6, L.rp(L.ORANGE))
		M.cyl(pa, T, (j2 + tip) * 0.5, (tip - j2).normalized(), 0.14, (tip - j2).length() * 0.5, 6, L.rp(Color8(200, 204, 208)))
		g.lamp(T, tip, Color(0.7, 0.9, 1.0, 1.0) if a % 2 == 0 else Color(1.0, 0.8, 0.4, 1.0), 7.0, true, pa)
	for k in 4:
		var psh := M.part(S, 0.7)
		var sx := -46.0 + k * 2.6
		for lv in 4:
			M.box(psh, T, Vector3(sx, 116.8, 0.5 + lv * 1.6), Vector3(1.1, 0.6, 0.06), L.rp(L.STEEL))
			for j in 2:
				var pc := Vector3(sx - 0.45 + j * 0.9, 117.0, 0.8 + lv * 1.6)
				if (k + lv + j) % 3 == 0:
					M.cyl(psh, T, pc, L.Z, 0.25, 0.2, 6, L.rp(Color8(120, 40, 36)))
					g.lamp(T, pc + Vector3(0, 0.3, 0.2), Color(1, 0.25, 0.2, 0.7), 3.0)
				else:
					M.box(psh, T, pc, Vector3(0.32, 0.26, 0.24), L.rp(Color8(196, 204, 214)))
	L.quad(pdh, T, Vector3(-37.0, 116.05, 11.4), L.X * 8.0, L.Z * 0.7, Color8(70, 120, 150), L.Y)
	_crew(S, T, ["g7_op_purge"], ["act_0", "act_1", "idle"], [Vector3(-36.5, 135.5, 0.1), Vector3(-33.5, 134.7, 0.1), Vector3(-30.5, 136.4, 0.1)])


static func _c_pdecon(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	var pc := M.part(S, 0.8)
	M.box(pc, T, Vector3(-51.25, 130.0, 0.6), Vector3(2.6, 7.0, 0.25), L.rp(L.STEEL))
	for k in 14:
		M.dline(pc, T, Vector3(-53.6, 123.6 + k, 0.87), Vector3(-48.9, 123.6 + k, 0.87), Color8(150, 156, 160), L.Z)
	for yy: float in [126.0, 134.0]:
		for xx: float in [-53.6, -48.9]:
			M.box(pc, T, Vector3(xx, yy, 3.6), Vector3(0.15, 0.15, 3.0), L.rp(L.STEEL))
		M.box(pc, T, Vector3(-51.25, yy, 6.6), Vector3(2.5, 0.2, 0.2), L.rp(L.STEEL))
		for k in 4:
			g.lamp(T, Vector3(-53.2 + k * 1.3, yy + 0.3, 6.3), L.L_CYAN, 5.0, true, pc)
	for k in 3:
		M.box(pc, T, Vector3(-51.25, 125.0 + k * 4.4, 1.5), Vector3(1.0, 0.8, 0.6), L.rp(Color8(232, 230, 218)), Vector3(0.1, 0.1, 0.1))
		L.hazard(pc, T, Vector3(-52.2, 125.82 + k * 4.4, 1.5), Vector3(-50.3, 125.82 + k * 4.4, 1.5), L.Y)


static func _c_proto(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	var prg := M.part(S, 0.7)
	L.quad(prg, T, Vector3(-62.0, 110.03, 3.5), L.X * 2.6, L.Z * 3.2, Color8(10, 11, 12), L.Y)
	for k in 5:
		g.lamp(T, Vector3(-62.0, 110.2, 6.4 - k * 0.15), Color(1, 0.85, 0.6, 0.6 - k * 0.1), 5.0 - k * 0.6)
	heavy_mech(S, T, g, Vector3(-80.0, 124.0, 0.0), PI * 0.5)
	light_mech(S, T, g, Vector3(-70.0, 132.0, 0.0), PI * 0.5)
	light_mech(S, T, g, Vector3(-74.0, 134.0, 0.0), PI * 0.5)
	var pps := M.part(S, 1.0)
	M.box(pps, T, Vector3(-62.0, 124.0, 0.6), Vector3(0.6, 0.6, 0.6), L.rp(L.DARK))
	M.cyl(pps, T, Vector3(-62.0, 122.2, 1.4), Vector3(0, -1, 0), 0.45, 1.8, 10, L.rp(Color8(70, 76, 90)))
	for k in 4:
		M.cyl(pps, T, Vector3(-62.0, 123.2 - k * 0.7, 1.4), L.Y, 0.58, 0.08, 10, L.rp(Color8(150, 110, 220)), {"caps": false})
	g.lamp(T, Vector3(-62.0, 120.3, 1.4), Color(0.75, 0.55, 1.0, 1.0), 12.0, true, pps)
	for k in 4:
		M.box(pps, T, Vector3(-59.0 + k * 0.7, 112.0, 1.4), Vector3(0.12, 0.6, 1.2), L.rp(L.GUN))
	_crew(S, T, ["g7_cn_scanner", "g7_op_leader", "g7_cn_deploy"], ["idle", "act_0"], [Vector3(-66, 137, 0.1), Vector3(-59, 136, 0.1), Vector3(-85, 132, 0.1)])


static func _c_cells(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	var specs := [["g7_threats2", "g7_m_mimic", "reveal", "agitated"], ["g7_threats2", "g7_m_spitter", "idle", "stable"],
		["g7_threats2", "g7_m_leech", "idle", "stable"], ["g7_threats", "g7_m_packhunter", "idle", "breaching"], ["g7_threats2", "g7_m_burrower", "idle", "purged"]]
	var states := {"stable": L.L_GRN, "agitated": L.L_AMB, "breaching": L.L_RED, "purged": L.L_CYAN}
	var x0: float = r.x0
	var x1: float = r.x1
	var n := 2 if (x1 - x0) < 12.0 else 4
	var cw := (x1 - x0) / n
	for i in n:
		var cx0 := x0 + i * cw
		var cx1 := cx0 + cw
		var si := (i + (0 if n == 2 else 2)) % specs.size()
		var st: String = specs[si][3]
		var pc := M.part(S, 0.6)
		L.emp_grid(pc, T, cx0 + 0.3, 127.0, cx1 - 0.3, 137.5, -13.92)
		if i < n - 1:
			M.box(pc, T, Vector3(cx1, 132.0, -13.6), Vector3(0.18, 6.0, 0.4), L.rp(L.LAB))
			L.quad(pc, T, Vector3(cx1, 132.0, -8.4), L.Y * 6.0, L.Z * 4.8, L.GLASS, L.X)
			for k in 4:
				M.box(pc, T, Vector3(cx1, 126.6 + k * 3.6, -8.4), Vector3(0.08, 0.08, 4.8), L.rp(L.STEEL))
		for k in 2:
			L.clamp_pad(pc, T, Vector3((cx0 + cx1) * 0.5 + (k - 0.5) * 2.0, 131.0 + k * 2.0, -14.0))
		for k in 3:
			M.cyl(pc, T, Vector3(cx0 + 1.0 + k * (cw - 2.0) * 0.5, 126.2, -5.0), L.Y, 0.15, 0.2, 6, L.rp(L.STEEL))
		L.spec(S, T, specs[si][0], specs[si][1], specs[si][2], 1, Vector3((cx0 + cx1) * 0.5, 131.5, -13.9), L.MACH, 0.65 if st == "purged" else 1.0)
		var pgl := M.part(S, 1.3)
		L.quad(pgl, T, Vector3((cx0 + cx1) * 0.5, 138.0, -8.6), L.X * (cw * 0.5 - 0.1), L.Z * 5.3, L.GLASS, L.Y)
		M.box(pgl, T, Vector3((cx0 + cx1) * 0.5, 138.0, -3.4), Vector3(cw * 0.5, 0.25, 0.3), L.rp(Color8(60, 64, 68)))
		g.lamp(T, Vector3((cx0 + cx1) * 0.5, 138.3, -3.4), states[st], 11.0, true, pgl)
		g.pool(T, Vector3((cx0 + cx1) * 0.5, 132.0, -13.9), 2.0, 4.0, Color(states[st].r, states[st].g, states[st].b, 0.35))
		if st == "purged":
			L.quad(pgl, T, Vector3((cx0 + cx1) * 0.5, 137.95, -8.6), L.X * (cw * 0.5 - 0.1), L.Z * 5.3, Color(0.92, 0.97, 1.0, 0.3), L.Y)


static func _c_pit(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	var pp := M.part(S, 0.6)
	L.emp_grid(pp, T, -67.6, 115.0, -48.4, 139.0, -29.9)
	for k in 6:
		M.dline(pp, T, Vector3(-68.0, 114.03, -26 + k * 3.8), Vector3(-48.0, 114.03, -26 + k * 3.8), Color(0.3, 0.3, 0.3, 0.4), L.Y)
		for j in 5:
			M.cyl(pp, T, Vector3(-65.0 + j * 4.2, 114.25, -26 + k * 3.8), L.Y, 0.18, 0.22, 6, L.rp(L.STEEL))
	L.spec(S, T, "g7_threats", "g7_m_weaver", "fire", 1, Vector3(-58.0, 128.0, -29.8), L.MACH)
	g.pool(T, Vector3(-58.0, 128.0, -29.8), 9.0, 10.0, Color(1.0, 0.25, 0.18, 0.45))
	for k in 4:
		g.lamp(T, Vector3(-67.6, 116.0 + k * 6.5, -8.0), L.L_RED, 9.0, true, pp)
	var pcr := M.part(S, 1.2)
	M.box(pcr, T, Vector3(-58.0, 127.0, -4.0), Vector3(9.8, 0.5, 0.4), L.rp(L.YEL))
	M.box(pcr, T, Vector3(-58.0, 127.0, -4.8), Vector3(1.0, 0.9, 0.5), L.rp(L.DARK))
	for s: float in [-0.6, 0.6]:
		M.dline(pcr, T, Vector3(-58.0 + s, 127.0, -5.2), Vector3(-58.0 + s * 2.2, 128.0, -24.0), Color8(40, 42, 44))
	M.box(pcr, T, Vector3(-58.0, 128.0, -24.2), Vector3(3.0, 0.25, 0.2), L.rp(L.YEL))
	M.box(pcr, T, Vector3(-58.0, 118.5, -12.0), Vector3(9.8, 1.0, 0.1), L.rp(Color8(70, 74, 78)))
	L.railing(pcr, T, Vector3(-67.8, 119.5, -12.0), Vector3(-48.2, 119.5, -12.0))
	L.spec(S, T, "g7_cn", "g7_op_emp", "fire", 1, Vector3(-55.0, 118.9, -11.9), L.TEAM)
	L.spec(S, T, "g7_cn", "g7_op_purge", "idle", 1, Vector3(-61.0, 118.9, -11.9), L.TEAM)


static func _c_vault(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	var pva := M.part(S, 0.8)
	M.cyl(pva, T, Vector3(-45.6, 131.0, -24.5), L.X, 3.2, 0.4, 18, L.rp(Color8(156, 150, 120)), {"cap_t": 3})
	for k in 8:
		var a := TAU * k / 8.0
		M.dline(pva, T, Vector3(-45.18, 131.0 + cos(a) * 0.8, -24.5 + sin(a) * 0.8), Vector3(-45.18, 131.0 + cos(a) * 2.8, -24.5 + sin(a) * 2.8), Color8(80, 76, 60), L.X)
	M.cyl(pva, T, Vector3(-45.1, 131.0, -24.5), L.X, 0.6, 0.15, 10, L.rp(L.STEEL))
	for k in 4:
		var pc := Vector3(-41.0 + k * 3.6, 131.0, -30.0)
		M.cyl(pva, T, pc + L.Z * 0.6, L.Z, 0.7, 0.6, 8, L.rp(L.GUN))
		var core_col: Color = [Color8(220, 70, 60), Color8(180, 90, 255), Color8(90, 220, 255), Color8(255, 200, 80)][k]
		M.cyl(pva, T, pc + L.Z * 1.7, L.Z, 0.45, 0.45, 8, L.rp(core_col), {"cap_t": 4})
		g.lamp(T, pc + L.Z * 1.8, Color(core_col.r, core_col.g, core_col.b, 1.0), 12.0, true, pva)
		L.quad(pva, T, pc + Vector3(0, 0.85, 1.6), L.X * 0.8, L.Z * 1.1, L.GLASS, L.Y)
	for k in 5:
		M.dline(pva, T, Vector3(-44.5, 137.5, -29.6 + k * 1.6), Vector3(-27.5, 137.5, -29.6 + k * 1.6), Color(1, 0.15, 0.1, 0.8), L.Y)
	L.spec(S, T, "g7_cn", "g7_cn_gunner", "idle", 2, Vector3(-29.0, 136.0, -29.9), L.TEAM)


static func _c_burn(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	var pb := M.part(S, 0.8)
	M.box(pb, T, Vector3(-8.0, 126.0, -26.5), Vector3(4.0, 3.0, 3.5), L.rp(Color8(110, 104, 98)), Vector3(0.2, 0.2, 0.2))
	L.quad(pb, T, Vector3(-8.0, 129.02, -27.6), L.X * 1.6, L.Z * 1.4, Color8(255, 130, 40), L.Y)
	g.lamp(T, Vector3(-8.0, 129.4, -27.6), Color(1, 0.5, 0.15, 1.0), 16.0)
	g.pool(T, Vector3(-8.0, 133.0, -29.9), 3.0, 3.0, Color(1, 0.5, 0.15, 0.6))
	M.cyl(pb, T, Vector3(-5.0, 123.0, -21.0), L.Z, 0.9, 3.0, 10, L.rp(Color8(122, 120, 114)))
	for k in 3:
		M.box(pb, T, Vector3(-11.5, 133.0 + k * 1.8, -29.4), Vector3(0.7, 0.7, 0.6), L.rp(Color8(70, 72, 74)))
	L.hazard(pb, T, Vector3(-12.0, 129.03, -24.0), Vector3(-4.0, 129.03, -24.0), L.Y)
	L.spec(S, T, "g7_cn", "g7_op_purge", "act_0", 1, Vector3(-5.5, 135.5, -29.9), L.TEAM)


static func _c_power(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	for k in 2:
		var pgn := M.part(S, 0.8)
		var c := Vector3(-84.0 + k * 7.0, 124.0, -27.6)
		M.box(pgn, T, c, Vector3(2.6, 6.0, 2.2), L.rp(Color8(176, 140, 60)))
		for j in 5:
			M.dline(pgn, T, c + Vector3(-2.0, 6.02, -1.4 + j * 0.6), c + Vector3(2.0, 6.02, -1.4 + j * 0.6), Color8(90, 70, 30), L.Y)
		M.cyl(pgn, T, c + Vector3(0, -3.0, 3.4), L.Z, 0.5, 1.4, 8, L.rp(L.STEEL))
		g.lamp(T, c + Vector3(2.0, 6.1, 1.6), L.L_GRN, 4.0, true, pgn)
	var px := M.part(S, 0.8)
	M.cyl(px, T, Vector3(-74.0, 120.0, -25.0), L.Z, 2.2, 4.8, 12, L.rp(Color8(200, 70, 50)), {"cap_t": 4})
	for b in 3:
		M.cyl(px, T, Vector3(-74.0, 120.0, -28.0 + b * 3.0), L.Z, 2.25, 0.1, 12, L.rp(L.STEEL), {"caps": false})
	L.quad(px, T, Vector3(-79.0, 108.05, -19.0), L.X * 8.0, L.Z * 3.0, Color8(60, 64, 68), L.Y)
	for i in 8:
		for j in 3:
			g.lamp(T, Vector3(-86.0 + i * 2.0, 108.2, -21.0 + j * 1.6), L.L_GRN if (i + j) % 4 else L.L_AMB, 2.5, true, px)
	M.box(px, T, Vector3(-79.0, 109.0, -13.4), Vector3(8.6, 0.4, 0.1), L.rp(Color8(110, 114, 118)))
	L.spec(S, T, "g7_cn", "g7_cn_deploy", "act_0", 3, Vector3(-77.0, 134.0, -29.9), L.TEAM)


# ================================================================== VEHICLES + AIRCRAFT (shared)
static func cage_truck(S: Array, T: Dictionary, g, at: Vector3, yaw: float, group: String, id: String) -> void:
	var Tt := M.sub(T, at, yaw)
	var pt := M.part(S, 1)
	var hull: Array = L.rp(Color8(98, 106, 96))
	M.box(pt, Tt, Vector3(5.6, 0, 1.9), Vector3(1.3, 1.4, 1.3), hull, Vector3(0.4, 0.1, 0.2))
	L.quad(pt, Tt, Vector3(6.92, 0, 2.4), L.Y * 1.0, L.Z * 0.4, Color8(70, 110, 130), L.X)
	M.box(pt, Tt, Vector3(-0.6, 0, 0.9), Vector3(4.6, 1.5, 0.3), L.rp(Color8(60, 62, 64)))
	for k in 5:
		for s: float in [-1.35, 1.35]:
			M.cyl(pt, Tt, Vector3(-4.0 + k * 2.2, s, 0.55), L.Y, 0.55, 0.2, 8, L.rp(Color8(30, 30, 30)), {"cap_t": 1})
	g.lamp(Tt, Vector3(7.0, 0.9, 1.6), Color(1, 0.95, 0.8, 1.0), 7.0, true, pt)
	g.lamp(Tt, Vector3(5.6, 0, 3.3), L.L_AMB, 6.0, true, pt)
	var pc := M.part(S, 1.5)
	var c0 := Vector3(-0.6, 0, 1.2)
	for d: Vector2 in [Vector2(-4.0, -1.4), Vector2(4.0, -1.4), Vector2(4.0, 1.4), Vector2(-4.0, 1.4)]:
		M.box(pc, Tt, c0 + Vector3(d.x, d.y, 1.9), Vector3(0.1, 0.1, 1.9), L.rp(L.STEEL))
	for k in 9:
		M.dline(pc, Tt, c0 + Vector3(-4.0 + k, 1.4, 0), c0 + Vector3(-4.0 + k, 1.4, 3.8), Color8(70, 76, 82))
		M.dline(pc, Tt, c0 + Vector3(-4.0 + k, -1.4, 0), c0 + Vector3(-4.0 + k, -1.4, 3.8), Color8(70, 76, 82))
	M.dline(pc, Tt, c0 + Vector3(-4, 1.4, 3.8), c0 + Vector3(4, 1.4, 3.8), Color8(120, 126, 132))
	L.spec(S, Tt, group, id, "idle", 2, c0 + L.Z * 0.05, L.MACH, 0.9)


static func heavy_mech(S: Array, T: Dictionary, g, at: Vector3, yaw: float) -> void:
	var Tm := M.sub(T, at, yaw)
	var hull: Array = L.rp(Color8(96, 104, 112))
	var dk: Array = L.rp(Color8(52, 56, 60))
	var pl := M.part(S, 1)
	for s: float in [-1.0, 1.0]:
		M.box(pl, Tm, Vector3(0.4, s * 1.6, 0.35), Vector3(1.4, 0.9, 0.35), dk)
		M.box(pl, Tm, Vector3(0.2, s * 1.6, 1.9), Vector3(0.6, 0.6, 1.3), hull, Vector3(0.1, 0.1, 0.1))
		M.box(pl, Tm, Vector3(-0.1, s * 1.6, 3.4), Vector3(0.75, 0.5, 0.4), dk)
		M.box(pl, Tm, Vector3(-0.2, s * 1.5, 4.9), Vector3(0.7, 0.65, 1.2), hull)
	var pt := M.part(S, 2)
	M.box(pt, Tm, Vector3(0, 0, 7.6), Vector3(1.9, 2.3, 1.5), hull, Vector3(0.3, 0.2, 0.2))
	M.box(pt, Tm, Vector3(0.3, 0, 9.4), Vector3(1.3, 1.6, 0.5), hull, Vector3(0.3, 0.2, 0.2))
	L.quad(pt, Tm, Vector3(1.62, 0, 9.4), L.Y * 1.0, L.Z * 0.22, Color8(70, 140, 190), L.X)
	g.lamp(Tm, Vector3(1.7, 0, 9.4), L.L_CYAN, 6.0)
	for s: float in [-1.0, 1.0]:
		M.box(pt, Tm, Vector3(0.2, s * 3.0, 7.6), Vector3(0.9, 0.7, 1.2), dk)
		M.box(pt, Tm, Vector3(1.2, s * 3.2, 6.6), Vector3(1.4, 0.55, 0.55), hull)
		M.cyl(pt, Tm, Vector3(3.6, s * 3.2, 6.6), L.X, 0.28, 1.2, 8, dk)
		M.box(pt, Tm, Vector3(-0.6, s * 2.0, 9.9), Vector3(1.0, 0.9, 0.6), hull)
	M.cyl(pt, Tm, Vector3(-1.6, 0, 10.2), L.Z, 0.4, 0.3, 8, L.rp(L.STEEL))
	var pg := M.part(S, 2.5)
	for s: float in [-1.0, 1.0]:
		M.box(pg, Tm, Vector3(-0.5, s * 4.6, 5.6), Vector3(0.18, 0.18, 5.6), L.rp(L.YEL))
	M.box(pg, Tm, Vector3(-0.5, 0, 11.3), Vector3(0.2, 4.8, 0.2), L.rp(L.YEL))
	g.lamp(Tm, Vector3(-0.5, 0, 11.0), L.L_WARM, 9.0)


static func light_mech(S: Array, T: Dictionary, g, at: Vector3, yaw: float) -> void:
	var Tm := M.sub(T, at, yaw)
	var hull: Array = L.rp(Color8(104, 110, 100))
	var dk: Array = L.rp(Color8(52, 56, 60))
	var pt := M.part(S, 1)
	for s: float in [-1.0, 1.0]:
		M.box(pt, Tm, Vector3(0.3, s * 0.8, 0.2), Vector3(0.8, 0.45, 0.2), dk)
		M.box(pt, Tm, Vector3(0.1, s * 0.8, 1.2), Vector3(0.32, 0.3, 0.8), hull)
		M.box(pt, Tm, Vector3(-0.2, s * 0.75, 2.6), Vector3(0.4, 0.35, 0.7), hull)
	M.box(pt, Tm, Vector3(0, 0, 3.8), Vector3(1.0, 1.2, 0.8), hull, Vector3(0.15, 0.15, 0.15))
	L.quad(pt, Tm, Vector3(1.02, 0, 4.0), L.Y * 0.6, L.Z * 0.18, Color8(70, 140, 190), L.X)
	M.cyl(pt, Tm, Vector3(1.2, 1.4, 3.6), L.X, 0.18, 1.1, 6, dk)
	g.lamp(Tm, Vector3(1.1, 0, 4.0), L.L_CYAN, 5.0)


static func drone(S: Array, T: Dictionary, g, at: Vector3, yaw: float, s := 1.0) -> void:
	var Td := M.sub(T, at, yaw)
	var pt := M.part(S, 2)
	M.box(pt, Td, Vector3(0, 0, 0.2) * s, Vector3(0.45, 0.3, 0.15) * s, L.rp(Color8(70, 76, 82)))
	for k in 4:
		var a := PI * 0.25 + PI * 0.5 * k
		var arm := Vector3(cos(a), sin(a), 0) * 0.75 * s
		M.cyl(pt, Td, arm * 0.5 + Vector3(0, 0, 0.25) * s, Vector3(cos(a), sin(a), 0), 0.04 * s, 0.38 * s, 4, L.rp(L.DARK), {"edge": false})
		M.cyl(pt, Td, arm + Vector3(0, 0, 0.32) * s, L.Z, 0.32 * s, 0.02 * s, 10, L.rp(Color8(40, 44, 48)), {"cap_t": 1})
	M.cyl(pt, Td, Vector3(0.2, 0, 0.0) * s, L.Z, 0.12 * s, 0.1 * s, 6, L.rp(L.DARK))
	g.lamp(Td, Vector3(0.48, 0, 0.2) * s, L.L_RED, 3.0, true, pt)


static func warden(S: Array, T: Dictionary, g, at: Vector3, yaw: float, flying := true) -> void:
	var Tc := M.pose(T.o, yaw, at, -0.04 if flying else 0.0, 0.12 if flying else 0.0)
	var rpp: Array = L.rp(Color8(58, 62, 70))
	var S2: Array = []
	V.airframe(S2, Tc, rpp, PI * 0.32 if flying else 0.0, 3, "flight" if flying else "landed")
	if not flying:
		V.gear(S2, Tc)
	V.item(S2, M.sub(Tc, V.NOSE_M), "nose", "cannon", rpp, flying)
	for s: float in [-1.0, 1.0]:
		V.item(S2, M.sub(Tc, Vector3(V.SIDE_M.x, s * V.SIDE_M.y, V.SIDE_M.z)), "side", "gun", rpp, false)
	var pe := M.part(S2, 2)
	var Te := M.sub(Tc, Vector3(3.2, 0, 0.1))
	M.cyl(pe, Te, Vector3(0.6, 0, 0), L.X, 0.32, 1.1, 10, L.rp(Color8(60, 70, 90)))
	for k in 3:
		M.cyl(pe, Te, Vector3(0.2 + k * 0.45, 0, 0), L.X, 0.42, 0.06, 10, L.rp(Color8(110, 180, 255)), {"caps": false})
	g.lamp(Te, Vector3(1.8, 0, 0), L.L_CYAN, 10.0, true, pe)
	g.lamp(Tc, Vector3(-6.4, 0, 1.6), L.L_RED, 7.0, true, pe)
	g.lamp(Tc, Vector3(0.6, 2.6, 1.0), L.L_GRN, 5.0, true, pe)
	g.lamp(Tc, Vector3(0.6, -2.6, 1.0), L.L_RED, 5.0, true, pe)
	for p in S2:
		S.append(p)


static func skycrane(S: Array, T: Dictionary, g, at: Vector3, yaw: float, landed := false, group := "g7_threats", id := "g7_m_packhunter") -> void:
	var Tc := M.pose(T.o, yaw, at)
	var hull: Array = L.rp(Color8(88, 96, 104))
	var dk: Array = L.rp(Color8(50, 54, 58))
	var pt := M.part(S, 2)
	M.box(pt, Tc, Vector3(0, 0, 0), Vector3(7.5, 0.95, 0.95), hull, Vector3(0.6, 0.3, 0.3))
	M.box(pt, Tc, Vector3(8.2, 0, 0.3), Vector3(1.4, 1.2, 1.05), hull, Vector3(0.9, 0.0, 0.45))
	L.quad(pt, Tc, Vector3(9.15, 0, 0.75), L.Y * 0.85, L.Z * 0.38, Color8(70, 120, 150), L.X)
	M.box(pt, Tc, Vector3(-8.0, 0, 1.7), Vector3(1.0, 0.12, 1.3), hull, Vector3(0.45, 0, 0))
	M.dline(pt, Tc, Vector3(-6, 0.97, 0.3), Vector3(6, 0.97, 0.3), L.ORANGE, L.Y)
	for fx: float in [4.4, -4.4]:
		M.box(pt, Tc, Vector3(fx, 0, 0.5), Vector3(0.35, 4.4, 0.18), dk)
		for s: float in [-1.0, 1.0]:
			var fc := Vector3(fx, s * 4.6, 0.6)
			M.cyl(pt, Tc, fc, L.Z, 1.9, 0.48, 16, hull, {"caps": false})
			M.cyl(pt, Tc, fc - L.Z * 0.05, L.Z, 1.62, 0.05, 16, L.rp(Color8(40, 44, 48)), {"cap_t": 0})
			M.cyl(pt, Tc, fc, L.Z, 0.35, 0.3, 6, dk)
	if landed:
		for s: float in [-1.0, 1.0]:
			M.box(pt, Tc, Vector3(0, s * 1.4, -1.9), Vector3(5.0, 0.12, 0.12), dk)
			for fx: float in [-3.0, 3.0]:
				M.dline(pt, Tc, Vector3(fx, s * 0.9, -0.9), Vector3(fx, s * 1.4, -1.85), Color8(60, 64, 68))
	M.box(pt, Tc, Vector3(0, 0, -1.25), Vector3(1.2, 1.0, 0.4), dk)
	g.lamp(Tc, Vector3(-8.6, 0, 3.0), Color(1, 0.95, 0.9, 1.0), 8.0, true, pt)
	g.lamp(Tc, Vector3(4.4, 6.6, 0.6), L.L_GRN, 5.0, true, pt)
	g.lamp(Tc, Vector3(4.4, -6.6, 0.6), L.L_RED, 5.0, true, pt)
	if not landed:
		g.lamp(Tc, Vector3(0, 0, -1.8), Color(1, 0.95, 0.85, 1.0), 10.0, true, pt)
		var cg := at
		cg.z = at.z - minf(at.z - 3.0, 12.0)
		var pc := M.part(S, 2.2)
		for d: Vector2 in [Vector2(-2.2, -1.6), Vector2(2.2, -1.6), Vector2(2.2, 1.6), Vector2(-2.2, 1.6)]:
			M.dline(pc, T, at + Vector3(0, 0, -1.6), cg + Vector3(d.x, d.y, 3.4), Color8(36, 38, 40))
			M.box(pc, T, cg + Vector3(d.x, d.y, 1.7), Vector3(0.09, 0.09, 1.7), L.rp(L.STEEL))
		M.box(pc, T, cg + Vector3(0, 0, 0.08), Vector3(2.3, 1.7, 0.08), L.rp(Color8(60, 62, 64)))
		for k in 6:
			M.dline(pc, T, cg + Vector3(2.2, -1.6 + k * 0.64, 0), cg + Vector3(2.2, -1.6 + k * 0.64, 3.4), Color8(80, 86, 92), L.X)
			M.dline(pc, T, cg + Vector3(-2.2 + k * 0.88, 1.6, 0), cg + Vector3(-2.2 + k * 0.88, 1.6, 3.4), Color8(80, 86, 92), L.Y)
		L.spec(S, T, group, id, "walk_b", 2, cg + Vector3(0, 0, 0.16), L.MACH)


# ================================================================== CORRIDOR NETWORK (v4): tunnels, blast doors, checkpoints
static func _zone_of(k: String) -> String:
	var r := _room_by(k)
	return String(r.z) if not r.is_empty() else "clean"


static func _corridors(S: Array, T: Dictionary, g, ys: float) -> void:
	for c in CORR:
		var x0: float = c.x0
		var x1: float = c.x1
		var z: float = c.z
		var h: float = c.h
		var yb := ys - (12.0 if String(c.kind) == "tunnel" else 9.0)
		var za := _zone_of(String(c.a))
		var zb := _zone_of(String(c.b))
		var zc: Color = ZCOL[za] if za == zb else ZCOL["cp"]
		var pc := M.part(S, 0)
		var floorc := Color8(150, 152, 150) if String(c.kind) != "tunnel" else Color8(78, 80, 82)
		M.face(pc, T, [Vector3(x0, yb, z), Vector3(x1, yb, z), Vector3(x1, ys, z), Vector3(x0, ys, z)], Vector3((x0 + x1) * 0.5, (yb + ys) * 0.5, z - 2), L.rp(floorc), {"edge": false})
		M.face(pc, T, [Vector3(x0, yb, z), Vector3(x1, yb, z), Vector3(x1, yb, z + h), Vector3(x0, yb, z + h)], Vector3((x0 + x1) * 0.5, yb - 2, z + h * 0.5), L.rp(Color8(176, 172, 162)), {"edge": false})
		# arched ribs (shotcrete tunnel lining) + ceiling light strip + cable tray + zone floor stripe
		var nr := maxi(1, int((x1 - x0) / 1.6))
		for i in nr + 1:
			var xx := x0 + (x1 - x0) * i / nr
			M.dline(pc, T, Vector3(xx, yb + 0.02, z), Vector3(xx, yb + 0.02, z + h), Color(0.3, 0.3, 0.3, 0.35), L.Y)
		M.dline(pc, T, Vector3(x0 + 0.3, yb + 0.03, z + h - 0.4), Vector3(x1 - 0.3, yb + 0.03, z + h - 0.4), L.LAMP_W, L.Y)
		g.lamp(T, Vector3((x0 + x1) * 0.5, yb + 0.6, z + h - 0.5), L.L_COLD, 7.0)
		M.box(pc, T, Vector3((x0 + x1) * 0.5, yb + 0.3, z + h - 1.1), Vector3((x1 - x0) * 0.5, 0.25, 0.06), L.rp(Color8(110, 114, 118)))
		M.dline(pc, T, Vector3(x0, ys - 1.0, z + 0.03), Vector3(x1, ys - 1.0, z + 0.03), zc, L.Z)
		M.dline(pc, T, Vector3(x0, yb + 1.0, z + 0.03), Vector3(x1, yb + 1.0, z + 0.03), zc, L.Z)
		if String(c.kind) == "tunnel":
			for i in int((x1 - x0) / 1.2):
				M.dline(pc, T, Vector3(x0 + 0.3 + i * 1.2, (yb + ys) * 0.5, z + 0.04), Vector3(x0 + 0.9 + i * 1.2, (yb + ys) * 0.5, z + 0.04), L.YEL, L.Z)
		# blast doors at both ends (open, slab drawn back), framed in the zone colour of the room behind
		for e in [[x0, za], [x1, zb]]:
			_blast_door(S, T, g, float(e[0]), z, minf(h - 0.6, 3.4) if String(c.kind) != "tunnel" else h - 1.2, (yb + ys) * 0.5, 1.4 if String(c.kind) != "tunnel" else 4.0, ZCOL[e[1]])
		if c.cp:
			_checkpoint(S, T, g, (x0 + x1) * 0.5, z, h, yb, ys)


static func _blast_door(S: Array, T: Dictionary, g, x: float, z: float, dh: float, yc: float, hw: float, col: Color) -> void:
	var pd := M.part(S, 1)
	for s: float in [-1.0, 1.0]:
		M.box(pd, T, Vector3(x, yc + s * (hw + 0.35), z + dh * 0.5 + 0.2), Vector3(0.35, 0.3, dh * 0.5 + 0.2), L.rp(L.BRUT_D))
	M.box(pd, T, Vector3(x, yc, z + dh + 0.55), Vector3(0.35, hw + 0.65, 0.3), L.rp(L.BRUT_D))
	M.box(pd, T, Vector3(x + 0.1, yc - hw - 1.2, z + dh * 0.5), Vector3(0.25, hw * 0.55, dh * 0.5), L.rp(L.GUN))   # slab rolled aside
	L.hazard(pd, T, Vector3(x + 0.36, yc - hw - 1.2 - hw * 0.5, z + 0.3), Vector3(x + 0.36, yc - hw - 1.2 + hw * 0.5, z + 0.3), L.X, 0.4)
	for s: float in [-1.0, 1.0]:
		M.dline(pd, T, Vector3(x + 0.36, yc + s * (hw + 0.05), z), Vector3(x + 0.36, yc + s * (hw + 0.05), z + dh), col, L.X)
	M.dline(pd, T, Vector3(x + 0.36, yc - hw, z + dh + 0.05), Vector3(x + 0.36, yc + hw, z + dh + 0.05), col, L.X)
	g.lamp(T, Vector3(x + 0.5, yc + hw + 0.5, z + dh + 0.3), Color(col.r, col.g, col.b, 1.0), 6.0, true, pd)


static func _checkpoint(S: Array, T: Dictionary, g, xc: float, z: float, h: float, yb: float, ys: float) -> void:
	var pk := M.part(S, 1.2)
	var yc := (yb + ys) * 0.5
	# scanner arch across the corridor + guard booth against the back wall + barrier arm + stop line
	for s: float in [-1.0, 1.0]:
		M.box(pk, T, Vector3(xc, yc + s * 2.2, z + 1.3), Vector3(0.2, 0.25, 1.3), L.rp(Color8(200, 204, 206)))
	M.box(pk, T, Vector3(xc, yc, z + 2.75), Vector3(0.2, 2.45, 0.18), L.rp(Color8(200, 204, 206)))
	for k in 4:
		M.dline(pk, T, Vector3(xc + 0.21, yc - 2.0 + k * 1.3, z + 0.4), Vector3(xc + 0.21, yc - 2.0 + k * 1.3, z + 2.5), Color(0.5, 0.9, 1.0, 0.7), L.X)
	g.lamp(T, Vector3(xc + 0.3, yc, z + 2.9), L.L_AMB, 5.0, true, pk)
	M.box(pk, T, Vector3(xc - 0.4, yb + 1.3, z + 1.2), Vector3(0.9, 0.9, 1.2), L.rp(Color8(176, 180, 182)))
	L.quad(pk, T, Vector3(xc - 0.4, yb + 2.21, z + 1.5), L.X * 0.7, L.Z * 0.45, L.GLASS_D, L.Y)
	g.lamp(T, Vector3(xc - 0.4, yb + 2.3, z + 1.5), L.L_WARM, 5.0)
	M.box(pk, T, Vector3(xc + 0.9, yc + 0.2, z + 1.0), Vector3(0.08, 2.0, 0.06), L.rp(L.YEL))
	L.hazard(pk, T, Vector3(xc + 1.6, yb + 0.5, z + 0.04), Vector3(xc + 1.6, ys - 0.5, z + 0.04), L.Z, 0.5)
	L.plate(pk, T, Vector3(xc, yb + 0.05, z + h - 1.2), L.Y, 1.2, 0.45, ZCOL["cp"], int(xc))
	_crew(S, T, ["g7_cn_team_leader", "g7_cn_scanner"], ["idle"], [Vector3(xc - 0.4, yb + 3.2, z + 0.1)])


## Freight hall at the clean main tunnel: trucks unloading, pallet racks, forklift.
static func _c_freight(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	var x0: float = r.x0
	var x1: float = r.x1
	var z: float = r.z0
	var yb: float = r.yb
	L.vehicle(S, T, g, Vector3(x1 - 4.0, (yb + ys) * 0.5 + 4.0, z), PI, "truck")
	L.vehicle(S, T, g, Vector3(x0 + 5.0, (yb + ys) * 0.5 - 2.0, z), 0.0, "apc")
	for k in 3:
		var pr := M.part(S, 0.7)
		for lv in 3:
			M.box(pr, T, Vector3(x0 + 2.0 + k * 3.6, yb + 1.0, z + 0.3 + lv * 2.0), Vector3(1.5, 0.7, 0.08), L.rp(L.ORANGE))
			M.box(pr, T, Vector3(x0 + 2.0 + k * 3.6, yb + 1.0, z + 0.9 + lv * 2.0), Vector3(1.2, 0.55, 0.5), L.rp(Color8(150, 128, 92)))
	M.dline(M.part(S, 0.5), T, Vector3(x0, ys - 3.0, z + 0.03), Vector3(x1, ys - 3.0, z + 0.03), L.YEL, L.Z)
	_crew(S, T, ["g7_cn_deploy", "g7_cn_radio"], ["act_0", "idle"], [Vector3(x0 + 6.0, ys - 4.0, z + 0.1), Vector3(x1 - 8.0, ys - 6.0, z + 0.1)])


## Utility stair + switchback ramp (west emergency / service core).
static func _c_wstair(S: Array, T: Dictionary, g, r: Dictionary, ys: float) -> void:
	var x0: float = r.x0
	var x1: float = r.x1
	var ps := M.part(S, 0.6)
	var z := float(r.z0)
	var k := 0
	while z < float(r.z1) - 1.0:
		var a := Vector3(x0 + 0.3 if k % 2 == 0 else x1 - 0.3, ys - 3.0, z + 0.2)
		var b := Vector3(x1 - 0.3 if k % 2 == 0 else x0 + 0.3, ys - 3.0, z + 3.4)
		M.dline(ps, T, a, b, Color8(220, 220, 214), L.Y)
		M.dline(ps, T, a + L.Z * 1.0, b + L.Z * 1.0, L.YEL, L.Y)
		z += 3.6
		k += 1
	g.lamp(T, Vector3((x0 + x1) * 0.5, ys - 2.0, float(r.z1) - 1.0), L.L_WARM, 6.0)
