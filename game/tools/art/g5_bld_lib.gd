extends RefCounted
## G5 building art helpers (agent ART-BLD, CONTRACTS_G5 s3.4). Shared by g5_bld_air / _hangar / _sea / _med.
## A building is a list of parts in a LOCAL frame (u along the facing axis AX[f], v along its left-hand
## perpendicular PP[f] = (-ax.y, ax.x), exactly sim/systems/airfield.gd AXES / strip_points), so one part
## list renders in all 4 rotations. Part = [u, v, z, hu, hv, hz, colour, role] (tiles, px, px).
## Roles: box (default), team (team-masked box), cyl (hu = radius), hex (hu = radius), tent (ridge on u),
## arch (quonset roof on u), glass, slab, mat (flat ground layer), pole. Anything else is a box that the
## drawer's dress callback may decorate. Same canvas / pivot conventions as buildings.gd:
## w = size*64+12, pivot = footprint centre, h = pivot.y + size*16 + 6. Deterministic (P.hn hashes only).
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")
const L = preload("res://tools/art/faction_m_lib.gd")
const FX = preload("res://tools/art/fx_ui.gd")
const FL = preload("res://tools/art/g4_fort_lib.gd")

const AX := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
const RAW := Color8(150, 146, 136)
const FIRE := Color8(246, 150, 52)
const FIRE_HI := Color8(255, 226, 120)
const SMOKE := Color(0.16, 0.15, 0.14, 0.55)
const RED := Color8(204, 44, 40)
const WHITE := Color8(232, 230, 222)
const PAL := {
	"a": {"slab": Color8(112, 110, 102), "wall": Color8(134, 130, 118), "trim": Color8(98, 100, 72),
		"roof": Color8(92, 96, 98), "mark": Color8(230, 226, 210), "dark": Color8(52, 54, 48), "tarmac": Color8(70, 72, 70),
		"canvas": Color8(112, 116, 78), "metal": Color8(120, 124, 120)},
	"b": {"slab": Color8(104, 100, 92), "wall": Color8(138, 76, 56), "trim": Color8(134, 78, 46),
		"roof": Color8(120, 122, 116), "mark": Color8(230, 188, 70), "dark": Color8(58, 50, 44), "tarmac": Color8(66, 62, 58),
		"canvas": Color8(150, 132, 96), "metal": Color8(112, 106, 96)},
	"m": {"slab": L.SLAB, "wall": L.GRAPH, "trim": L.PANEL, "roof": L.GRAPH_D, "mark": L.CYAN,
		"dark": L.JOINT, "tarmac": Color8(46, 50, 54), "canvas": L.PANEL_D, "metal": L.PANEL},
}


static func pal(fk: String, key: String) -> Color:
	return PAL[fk][key]


static func pp(f: int) -> Vector2:
	var a: Vector2 = AX[f % 4]
	return Vector2(-a.y, a.x)


static func rot(f: int) -> float:
	var a: Vector2 = AX[f % 4]
	return atan2(a.y, a.x)


## Local (u, v) -> world tiles relative to the footprint centre.
static func wp(f: int, u: float, v: float) -> Vector2:
	return AX[f % 4] * u + pp(f) * v


static func pt(o: Vector2, f: int, u: float, v: float, z: float) -> Vector2:
	var q := wp(f, u, v)
	return P.proj(o, Vector3(q.x, q.y, z))


## Flat quad on the ground plane (or at height z) spanning u0..u1 x v0..v1 in the local frame.
static func gquad(cv, o: Vector2, f: int, u0: float, v0: float, u1: float, v1: float, z: float, col: Color, team := false) -> void:
	cv.team = team
	cv.poly(PackedVector2Array([pt(o, f, u0, v0, z), pt(o, f, u1, v0, z), pt(o, f, u1, v1, z), pt(o, f, u0, v1, z)]), col)
	cv.team = false


static func gline(cv, o: Vector2, f: int, u0: float, v0: float, u1: float, v1: float, z: float, col: Color) -> void:
	cv.line_v(pt(o, f, u0, v0, z), pt(o, f, u1, v1, z), col)


## Canvas for a size-N footprint with `top` px of headroom. Returns [canvas, pivot].
static func canvas(size: int, top: int) -> Array:
	var w := size * 64 + 12
	var o := Vector2(w / 2, top + size * 16)
	return [P.Canvas.new(w, int(o.y) + size * 16 + 6), o]


static func _raw_col(c: Color) -> Color:
	return P.mix(c, RAW, 0.55)


## Renders a part list. hk = height factor (1 = finished), raw = construction material, no dressing.
## dress: Callable(cv, o, f, part, result) for finished parts; may be invalid.
static func render(cv, o: Vector2, f: int, ps: Array, hk: float, raw: bool, dress: Callable) -> void:
	var rt := rot(f)
	for p in ps:
		var hz: float = float(p[5]) * (hk if not String(p[7]) in ["slab", "mat"] else 1.0)
		if hz <= 0.5 or String(p[7]) in ["slab", "mat"]:
			continue
		var c := wp(f, p[0], p[1])
		var hu: float = p[3]
		var hv: float = p[4]
		if String(p[7]) in ["cyl", "hex"]:
			P.box_shadow(cv, o, Vector3(c.x, c.y, p[2]), hu * 0.8, hu * 0.8, hz, 0.0)
		elif String(p[7]) != "pole":
			P.box_shadow(cv, o, Vector3(c.x, c.y, p[2]), hu, hv, hz, rt)
	cv.flush_shadow()
	var flat: Array = []
	var up: Array = []
	for p in ps:
		if String(p[7]) in ["slab", "mat"]:
			flat.append(p)
		else:
			up.append(p)
	up.sort_custom(func(a, b):
		var la := 1 if float(a[2]) > 4.0 else 0
		var lb := 1 if float(b[2]) > 4.0 else 0
		if la != lb:
			return la < lb
		var wa := wp(f, a[0], a[1])
		var wb := wp(f, b[0], b[1])
		return wa.x + wa.y + float(a[2]) * 0.001 < wb.x + wb.y + float(b[2]) * 0.001)
	for p in flat + up:
		var r := part(cv, o, f, p, hk, raw)
		if not raw and dress.is_valid() and not r.is_empty():
			dress.call(cv, o, f, p, r)


static func part(cv, o: Vector2, f: int, p: Array, hk: float, raw: bool) -> Dictionary:
	var role := String(p[7])
	var col: Color = p[6]
	if raw and role != "team":
		col = _raw_col(col)
	var hz: float = float(p[5]) * (hk if not role in ["slab", "mat"] else 1.0)
	var c2 := wp(f, p[0], p[1])
	var c := Vector3(c2.x, c2.y, p[2])
	var hu: float = p[3]
	var hv: float = p[4]
	var rt := rot(f)
	match role:
		"slab":
			return P.box(cv, o, c, hu, hv, hz, rt, col, 0.12, 5)
		"mat":
			gquad(cv, o, f, p[0] - hu, p[1] - hv, p[0] + hu, p[1] + hv, p[2], col)
			return {}
		"cyl":
			if hz <= 0.5:
				return {}
			var top := B.cyl(cv, o, c, hu, hz, col, 31, 0.7 if not raw else -1.0, 2)
			return {"tip": top, "top": PackedVector2Array(), "sides": []}
		"hex":
			if hz <= 0.5:
				return {}
			return L.hexp(cv, o, c, hu, hz, rt, col, 17)
		"tent":
			if hz <= 0.5:
				return {}
			tent(cv, o, f, p[0], p[1], p[2], hu, hv, hz, col)
			return {}
		"arch":
			if hz <= 0.5:
				return {}
			return arch(cv, o, f, p[0], p[1], p[2], hu, hv, hz, col)
		"pole":
			if hz <= 0.5:
				return {}
			cv.line_v(P.proj(o, c), P.proj(o, c + Vector3(0, 0, hz)), col)
			return {"tip": P.proj(o, c + Vector3(0, 0, hz)), "top": PackedVector2Array(), "sides": []}
	if hz <= 0.5:
		return {}
	cv.team = role == "team" and not raw
	var r := P.box(cv, o, c, hu, hv, hz, rt, col, 0.07 if role != "glass" else 0.02, 3)
	cv.team = false
	if not raw and role != "team":
		B.wall_ao(cv, r, 0.26)
		B.edges(cv, r, col)
	return r


## Ridge tent: ridge along local u at height z+hz, eaves at z+hz*0.25 (low walls).
static func tent(cv, o: Vector2, f: int, u: float, v: float, z: float, hu: float, hv: float, hz: float, col: Color) -> void:
	var e := z + hz * 0.25
	var t := z + hz
	var faces := [
		[[u - hu, v - hv, e], [u + hu, v - hv, e], [u + hu, v, t], [u - hu, v, t]],
		[[u - hu, v + hv, e], [u + hu, v + hv, e], [u + hu, v, t], [u - hu, v, t]],
		[[u - hu, v - hv, e], [u - hu, v + hv, e], [u - hu, v, t]],
		[[u + hu, v - hv, e], [u + hu, v + hv, e], [u + hu, v, t]],
		[[u - hu, v + hv, z], [u + hu, v + hv, z], [u + hu, v + hv, e], [u - hu, v + hv, e]],
		[[u + hu, v - hv, z], [u + hu, v + hv, z], [u + hu, v + hv, e], [u + hu, v - hv, e]],
	]
	var normals := [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0)]
	var order: Array = []
	for i in faces.size():
		var n: Vector2 = normals[i]
		var wn: Vector2 = AX[f % 4] * n.x + pp(f) * n.y
		order.append([wn.x + wn.y, i, wn])
	order.sort_custom(func(a, b): return a[0] < b[0])
	for it in order:
		if float(it[0]) <= 0.0:
			continue
		var pts := PackedVector2Array()
		for q in faces[int(it[1])]:
			pts.append(pt(o, f, q[0], q[1], q[2]))
		var k := P.side_shade(it[2]) * (1.08 if int(it[1]) < 2 else 0.96)
		cv.poly(pts, P.mul(col, k), P.speckle(0.05, 61 + int(it[1])))
	cv.line_v(pt(o, f, u - hu, v, t), pt(o, f, u + hu, v, t), P.mul(col, 1.28))


## Quonset-style arched roof on a box base: 3 stepped, narrowing bands along u. Returns the base box.
static func arch(cv, o: Vector2, f: int, u: float, v: float, z: float, hu: float, hv: float, hz: float, col: Color) -> Dictionary:
	var rt := rot(f)
	var base_h := hz * 0.38
	var c := wp(f, u, v)
	var r := P.box(cv, o, Vector3(c.x, c.y, z), hu, hv, base_h, rt, col, 0.05, 7)
	var steps := [[0.86, 0.24], [0.62, 0.22], [0.34, 0.16]]
	var zz := z + base_h
	for s in steps:
		var h: float = hz * float(s[1])
		P.box(cv, o, Vector3(c.x, c.y, zz), hu, hv * float(s[0]), h, rt, P.mul(col, 1.04), 0.05, 9)
		zz += h
	return r


## Battle damage for a size-N building: scorch blotches, cracks, chipped silhouette, rubble chips and
## small fires with smoke. Only darkens / removes existing pixels except fires, smoke and rubble.
static func damage(cv, o: Vector2, size: int, seed: int) -> void:
	var sx := float(size) * 26.0
	for k in 2 + size * 2:
		var cx := o.x + (P.hn(k, seed, 1) - 0.5) * sx * 1.6
		var cy := o.y - 2.0 - P.hn(k, seed, 2) * (size * 12.0 + 16.0)
		var rx := 3.5 + P.hn(k, seed, 3) * (2.0 + size * 1.5)
		for y in range(int(cy - rx), int(cy + rx) + 1):
			for x in range(int(cx - rx), int(cx + rx) + 1):
				var dx := (x - cx) / rx
				var dy := (y - cy) / (rx * 0.7)
				var c: Color = cv.get_px(x, y)
				if dx * dx + dy * dy <= 1.0 and c.a > 0.6:
					cv.img.set_pixel(x, y, P.mul(c, 0.45 + 0.2 * P.hn(x, y, seed)))
	for k in size + 2:
		var x := int(o.x + (P.hn(k, seed, 5) - 0.5) * sx * 1.4)
		var y := int(o.y - 4.0 - P.hn(k, seed, 6) * (size * 10.0 + 10.0))
		for s in 6 + size * 3:
			var c: Color = cv.get_px(x, y)
			if c.a > 0.6:
				cv.img.set_pixel(x, y, P.mul(c, 0.32))
			x += P.hi(k * 31 + s, seed, 7, 3) - 1
			y += 1 if P.hn(k * 31 + s, seed, 8) > 0.3 else -1
	for k in 4 + size * 3:
		var x := int(o.x + (P.hn(k, seed, 9) - 0.5) * sx * 1.8)
		for y in cv.h:
			if cv.get_px(x, y).a > 0.6:
				for d in 1 + P.hi(k, seed, 10, 4):
					if y + d < cv.h:
						cv.img.set_pixel(x, y + d, Color(0, 0, 0, 0))
						cv.mask.set_pixel(x, y + d, Color(0, 0, 0, 0))
				break
	var hs := float(size) * 0.5
	for k in 6 + size * 4:
		var q := P.proj(o, Vector3((P.hn(k, seed, 12) - 0.5) * hs * 2.1, (P.hn(k, seed, 13) - 0.5) * hs * 2.1, 0))
		cv.rect(int(q.x), int(q.y), 2, 1, Color8(96, 92, 84) if k % 2 == 0 else Color8(64, 60, 56))
	for k in 1 + size / 2:
		var x := int(o.x + (P.hn(k, seed, 14) - 0.5) * sx)
		for y in cv.h:
			if cv.get_px(x, y).a > 0.6 and y > 6:
				fire(cv, x, y, seed + k)
				break


static func fire(cv, x: int, y: int, s: int) -> void:
	for i in 5:
		var dx := P.hi(i, s, 21, 5) - 2
		var h := 2 + P.hi(i, s, 22, 4)
		for d in h:
			cv.img.set_pixel(clampi(x + dx, 0, cv.w - 1), clampi(y - d, 0, cv.h - 1), FIRE_HI if d < h / 2 else FIRE)
	for i in 7:
		var px := clampi(x + P.hi(i, s, 23, 5) - 2 + i / 2, 0, cv.w - 1)
		var py := clampi(y - 6 - i * 2, 0, cv.h - 1)
		var c: Color = cv.img.get_pixel(px, py)
		cv.img.set_pixel(px, py, c.blend(SMOKE) if c.a > 0.0 else SMOKE)
		if px + 1 < cv.w:
			cv.img.set_pixel(px + 1, py, SMOKE)


## Construction dressing: human scaffold poles around the biggest part, or Machine holo lattice.
static func scaffold(cv, o: Vector2, f: int, ps: Array, fk: String, hk: float) -> void:
	for p in ps:
		if String(p[7]) in ["slab", "mat", "pole"] or float(p[5]) < 10.0:
			continue
		var c := wp(f, p[0], p[1])
		if fk == "m":
			L.holo_box(cv, o, Vector3(c.x, c.y, p[2]), p[3], p[4], float(p[5]), 0.5)
			continue
		var top := float(p[2]) + float(p[5]) * maxf(hk, 0.3) + 4.0
		for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var q := wp(f, float(p[0]) + s.x * (float(p[3]) + 0.06), float(p[1]) + s.y * (float(p[4]) + 0.06))
			cv.line_v(P.proj(o, Vector3(q.x, q.y, 0)), P.proj(o, Vector3(q.x, q.y, top)), FL.POLE)
		gline(cv, o, f, float(p[0]) - p[3], float(p[1]) + p[4] + 0.06, float(p[0]) + p[3], float(p[1]) + p[4] + 0.06,
			top * 0.5, FL.POLE)


## Team stake / flag on a short pole at (u, v): makes every construction stage carry team pixels.
static func stake(cv, o: Vector2, f: int, u: float, v: float, h := 16.0) -> void:
	var b := pt(o, f, u, v, 0)
	var t := pt(o, f, u, v, h)
	cv.line_v(b, t, Color8(60, 58, 52))
	cv.team = true
	cv.poly(PackedVector2Array([t, t + Vector2(7, 2), t + Vector2(0, 5)]), Color(0.8, 0.8, 0.8))
	cv.team = false


## Red cross on a white square on a top quad (u, v centre, s = half size in quad units).
static func cross(cv, top: PackedVector2Array, u: float, v: float, s: float) -> void:
	cv.poly(P.sub(top, u - s, v - s, u + s, v + s), WHITE)
	cv.poly(P.sub(top, u - s * 0.7, v - s * 0.22, u + s * 0.7, v + s * 0.22), RED)
	cv.poly(P.sub(top, u - s * 0.22, v - s * 0.7, u + s * 0.22, v + s * 0.7), RED)


static func lamp(cv, p: Vector2, col: Color) -> void:
	cv.px(int(p.x), int(p.y), col)
	cv.px(int(p.x) + 1, int(p.y), P.mul(col, 0.7))
