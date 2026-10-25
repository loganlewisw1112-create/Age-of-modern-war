extends RefCounted
## G6 proposal art, module g6_turrets (agent art-turrets): 15 fixed emplacements / turrets for Human A,
## Human B and Machine. Building-type assets (H.bld, rotations f = 0, 1), drawn with the game's own part
## renderer (g5_bld_lib), dressing helpers (bdetail, faction_b_veh rivets/patches/streaks, faction_m_lib
## seams/eyes/team panels) and the coastal-battery recipe (g5_bld_sea): a turret on a base.
## Local frame per rotation: +u = facing (weapon) axis K.AX[f], +v = its left perpendicular K.pp(f).
## Weapons are aimed along +u (yawed a little) so they point at the camera in both rotations; tilted
## launchers / rails use _tbox (an elevated box in the local frame), barrels use _rod. Fire effects stay
## inside the canvas; beams, arcs, fields and smoke are kept below alpha 0.6 so the outline skips them.
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")
const L = preload("res://tools/art/faction_m_lib.gd")
const BD = preload("res://tools/art/faction_m_bdress.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")
const V = preload("res://tools/art/faction_b_veh.gd")
const VH = preload("res://tools/art/vehicles.gd")
const D = preload("res://tools/art/vdetail.gd")
const U4 = preload("res://tools/art/g4_units_lib.gd")
const H = preload("g6_lib.gd")

const SHOW := {
	"a_atgm_bunker": {"row": 0, "ground": "grass"},
	"a_sam_site": {"row": 1, "ground": "grass"},
	"a_laser_ciws": {"row": 1, "ground": "road"},
	"a_howitzer_pit": {"row": 1, "ground": "dirt"},
	"a_popup_turret": {"row": 0, "ground": "grass"},
	"b_pak_nest": {"row": 0, "ground": "dirt"},
	"b_flak_battery": {"row": 0, "ground": "road"},
	"b_net_post": {"row": 0, "ground": "grass"},
	"b_mortar_pit": {"row": 0, "ground": "dirt"},
	"b_pillbox": {"row": 0, "ground": "grass"},
	"m_arc_pylon": {"row": 0, "ground": "grass"},
	"m_pulse_spire2": {"row": 0, "ground": "grass"},
	"m_jammer_obelisk": {"row": 0, "ground": "grass"},
	"m_mass_driver": {"row": 1, "ground": "road"},
	"m_sentry_mine": {"row": 0, "ground": "dirt"},
}

# Human A
const OLIVE := VH.HULL
const OLIVE_D := VH.HULL_D
const GUN_A := VH.GUNMETAL
const CONC_A := Color8(140, 136, 124)
const SAND := Color8(150, 134, 98)
# Human B
const KHAKI := V.HULL
const KHAKI_D := Color8(88, 76, 52)
const GUN_B := V.GUNMETAL
const CONC_B := Color8(128, 124, 112)
const STEEL_B := Color8(92, 94, 92)
const SAND_B := Color8(146, 128, 92)
const WOOD := Color8(122, 98, 66)
# shared
const EARTH := Color8(96, 82, 58)
const EARTH_D := Color8(72, 60, 44)
const BRASS := Color8(184, 148, 72)
const ROPE := Color8(200, 184, 140)
const LASER := Color8(255, 84, 60)
const LASER_HOT := Color8(255, 236, 214)
const YAW := 0.35

# box face index lists (corner index = along + 2*side + 4*up), ordered so q[0]->q[1] / q[0]->q[3]
# follow (along|side, up|side) like P.box quads; FLIP folds the winding back to outward-facing.
const FACES := {"back": [0, 2, 6, 4], "front": [1, 3, 7, 5], "left": [0, 1, 5, 4], "right": [2, 3, 7, 6],
	"bottom": [0, 1, 3, 2], "top": [4, 5, 7, 6]}
const FLIP := {"back": -1.0, "front": 1.0, "left": 1.0, "right": -1.0, "bottom": -1.0, "top": 1.0}
const FN := {"back": Vector3(-1, 0, 0), "front": Vector3(1, 0, 0), "left": Vector3(0, -1, 0),
	"right": Vector3(0, 1, 0), "bottom": Vector3(0, 0, -1), "top": Vector3(0, 0, 1)}


static func build(out: Dictionary) -> void:
	print("T> a_atgm_bunker"); H.bld(out, "a_atgm_bunker", 2, 30, atgm_bunker)
	print("T> a_sam_site"); H.bld(out, "a_sam_site", 2, 46, sam_site)
	print("T> a_laser_ciws"); H.bld(out, "a_laser_ciws", 1, 31, laser_ciws)
	print("T> a_howitzer_pit"); H.bld(out, "a_howitzer_pit", 2, 26, howitzer_pit)
	print("T> a_popup_turret"); H.bld(out, "a_popup_turret", 1, 22, popup_turret)
	print("T> b_pak_nest"); H.bld(out, "b_pak_nest", 1, 22, pak_nest)
	print("T> b_flak_battery"); H.bld(out, "b_flak_battery", 2, 44, flak_battery)
	print("T> b_net_post"); H.bld(out, "b_net_post", 1, 31, net_post)
	print("T> b_mortar_pit"); H.bld(out, "b_mortar_pit", 1, 22, mortar_pit)
	print("T> b_pillbox"); H.bld(out, "b_pillbox", 1, 22, pillbox)
	print("T> m_arc_pylon"); H.bld(out, "m_arc_pylon", 1, 31, arc_pylon)
	print("T> m_pulse_spire2"); H.bld(out, "m_pulse_spire2", 1, 64, pulse_spire2)
	print("T> m_jammer_obelisk"); H.bld(out, "m_jammer_obelisk", 1, 31, jammer_obelisk)
	print("T> m_mass_driver"); H.bld(out, "m_mass_driver", 2, 40, mass_driver)
	print("T> m_sentry_mine"); H.bld(out, "m_sentry_mine", 1, 18, sentry_mine)


# ================================================================ shared helpers
## Part-list renderer (K.render semantics) with hooks: [u, v, z, Callable(cv)] entries are sorted into the
## draw order like parts (so a gun can sit between back and front sandbags). Role "shadow" parts only
## cast a shadow.
static func _render(cv, o: Vector2, f: int, ps: Array, fk: String, hooks: Array = []) -> void:
	var rt := K.rot(f)
	for p in ps:
		var role := String(p[7])
		if role in ["slab", "mat"] or float(p[5]) <= 0.5:
			continue
		var c := K.wp(f, p[0], p[1])
		if role in ["cyl", "hex"]:
			P.box_shadow(cv, o, Vector3(c.x, c.y, p[2]), p[3] * 0.8, p[3] * 0.8, p[5], 0.0)
		elif role != "pole":
			P.box_shadow(cv, o, Vector3(c.x, c.y, p[2]), p[3], p[4], p[5], rt)
	cv.flush_shadow()
	var flat: Array = []
	var up: Array = []
	for p in ps:
		if String(p[7]) in ["slab", "mat"]:
			flat.append(p)
		elif String(p[7]) != "shadow":
			up.append(p)
	for hk in hooks:
		up.append([hk[0], hk[1], hk[2], 0, 0, 0, Color.BLACK, "hook", hk[3]])
	up.sort_custom(func(a, b):
		var la := 1 if float(a[2]) > 4.0 else 0
		var lb := 1 if float(b[2]) > 4.0 else 0
		if la != lb:
			return la < lb
		var wa := K.wp(f, a[0], a[1])
		var wb := K.wp(f, b[0], b[1])
		return wa.x + wa.y + float(a[2]) * 0.001 < wb.x + wb.y + float(b[2]) * 0.001)
	for p in flat + up:
		if String(p[7]) == "hook":
			(p[8] as Callable).call(cv)
			continue
		var r := K.part(cv, o, f, p, 1.0, false)
		if not r.is_empty():
			_dress(cv, o, f, p, r, fk)


static func _dress(cv, o: Vector2, f: int, p: Array, r: Dictionary, fk: String) -> void:
	var role := String(p[7])
	var col: Color = p[6]
	var s := int(absf(p[0] * 37.0 + p[1] * 91.0 + p[2] * 7.0)) + 300
	match role:
		"conc":  # cast concrete: firing slit + lip on every visible face, primer/streaks for Human B
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				cv.poly(P.sub(q, 0.22, 0.5, 0.78, 0.68), Color8(20, 20, 18))
				cv.line_v(P.sub(q, 0.2, 0.72, 0.8, 0.72)[0], P.sub(q, 0.2, 0.72, 0.8, 0.72)[1], P.mul(col, 1.3))
				if fk == "b":
					V.patch(cv, q, 0.04, 0.12, 0.2, 0.44, V.PRIMER, s)
					V.streaks(cv, q, s + 3)
		"bags":
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				cv.line_v(P.sub(q, 0, 0.5, 1, 0.5)[0], P.sub(q, 0, 0.5, 1, 0.5)[1], P.mul(col, 0.76))
			cv.px(int(r.top[0].x + r.top[2].x) / 2, int(r.top[0].y + r.top[2].y) / 2, P.mul(col, 1.18))
		"scrap", "plate":  # welded scrap plate: rivets, a patch, rust streaks
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				V.rivets(cv, q, 0.85, maxi(2, int(q[0].distance_to(q[1]) / 4.0)), col)
				if role == "scrap":
					V.rivets(cv, q, 0.18, maxi(2, int(q[0].distance_to(q[1]) / 4.0)), col)
					V.patch(cv, q, 0.55, 0.3, 0.9, 0.7, V.PRIMER if P.hn(s, 1, 7) > 0.5 else V.RUST, s)
				V.streaks(cv, q, s + 5)
		"crate":
			var t: PackedVector2Array = r.top
			cv.line_v(t[0].lerp(t[2], 0.0).lerp(t[1], 0.5), t[3].lerp(t[2], 0.5), P.mul(col, 0.75))
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				cv.line_v(P.sub(q, 0, 0.5, 1, 0.5)[0], P.sub(q, 0, 0.5, 1, 0.5)[1], P.mul(col, 0.72))
				var m := P.sub(q, 0.4, 0.55, 0.6, 0.8)[0]
				cv.px(int(m.x), int(m.y), Color8(214, 186, 70))
				break
		"turret", "head":  # turret band: team stripe around the visible faces
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				cv.team = true
				cv.poly(P.sub(q, 0.08, 0.5, 0.92, 0.78), Color(0.64, 0.64, 0.64))
				cv.team = false
				cv.line_v(P.sub(q, 0, 0.3, 1, 0.3)[0], P.sub(q, 0, 0.3, 1, 0.3)[1], P.mul(col, 0.8))
				if fk == "b":
					V.rivets(cv, q, 0.9, 4, col)
			if fk == "a":
				D.hatch(cv, r.top, 0.15, 0.2, 0.45, 0.5, col)
		"cabin":
			for sd in r.sides:
				B.door(cv, sd.quad, 0.3, 0.6, 0.7, col)
				break
			L.team_panel(cv, r.top, 0.2, 0.2, 0.8, 0.8, 0.7)
		"hex":
			if not r.has("top") or (r.top as PackedVector2Array).size() < 6:
				return
			var t: PackedVector2Array = r.top
			var c := (t[0] + t[3]) * 0.5
			if fk == "m":
				if float(p[3]) <= 0.13:  # capacitor column: stacked glowing rings, hot top
					for sd in r.sides:
						L.seam(cv, sd.quad, 0.78)
						L.joints(cv, sd.quad, [0.5], col)
					L.hex_plate(cv, t, 0.5, 0.5, 2.0, L.TEAL, true)
					cv.px(int(c.x), int(c.y), L.CYAN_HOT)
				else:
					for sd in r.sides:
						L.seam(cv, sd.quad, 0.5)
					cv.team = true
					cv.poly(PackedVector2Array([t[4].lerp(c, 0.3), t[5].lerp(c, 0.3), t[0].lerp(c, 0.3)]), Color(0.75, 0.75, 0.75))
					cv.team = false
			elif float(p[2]) < 6.0:  # pillbox body: a firing slit on each face, team band, weathering
				var n := 0
				for sd in r.sides:
					var q: PackedVector2Array = sd.quad
					cv.poly(P.sub(q, 0.18, 0.52, 0.82, 0.68), Color8(18, 18, 16))
					cv.line_v(P.sub(q, 0.15, 0.71, 0.85, 0.71)[0], P.sub(q, 0.15, 0.71, 0.85, 0.71)[1], P.mul(col, 1.3))
					V.patch(cv, q, 0.06, 0.1, 0.3, 0.4, V.PRIMER, s + n)
					V.streaks(cv, q, s + 11 + n)
					if n == 1:
						cv.team = true
						cv.poly(P.sub(q, 0.32, 0.12, 0.68, 0.4), Color(0.66, 0.66, 0.66))
						cv.team = false
					n += 1
			else:  # riveted steel roof plate
				for i in 6:
					var a: Vector2 = t[i]
					var b: Vector2 = t[(i + 1) % 6]
					for k in 3:
						var m: Vector2 = a.lerp(b, (k + 0.5) / 3.0).lerp(c, 0.16)
						cv.px(int(m.x), int(m.y), P.mul(col, 1.38))
						cv.px(int(m.x), int(m.y) + 1, P.mul(col, 0.6))
				for sd in r.sides:
					V.streaks(cv, sd.quad, s + 21, 0.7)
		"mhex":  # machine plinth: team panels on every face + cyan seam
			for sd in r.sides:
				L.team_panel(cv, sd.quad, 0.15, 0.25, 0.85, 0.6)
				L.seam(cv, sd.quad, 0.85)
			if r.has("top") and (r.top as PackedVector2Array).size() >= 6:
				var t2: PackedVector2Array = r.top
				L.eye(cv, (t2[0] + t2[3]) * 0.5 + Vector2(0, 1), false)
		"ring":
			for sd in r.sides:
				L.seam(cv, sd.quad, 0.5)
		"coil":
			var t3: PackedVector2Array = r.top
			for sd in r.sides:
				for i in 4:
					var v := 0.2 + i * 0.2
					cv.line_v(P.sub(sd.quad, 0, v, 1, v)[0], P.sub(sd.quad, 0, v, 1, v)[1], L.CYAN if i % 2 == 0 else L.TEAL)
			cv.px(int((t3[0].x + t3[2].x) * 0.5), int((t3[0].y + t3[2].y) * 0.5) - 1, L.CYAN_HOT)


## Local point on an elevated axis: pivot piv (u, v, z px), axis yawed by `yaw` in the u-v plane and
## elevated by `el`; L tiles along it, `side` tiles across, `upo` px perpendicular (up).
static func _lp(o: Vector2, f: int, piv: Vector3, el: float, l: float, yaw := YAW, side := 0.0, upo := 0.0) -> Vector2:
	var fd := Vector2(cos(yaw), sin(yaw))
	var sd := Vector2(-sin(yaw), cos(yaw))
	var along := l * cos(el) - (upo / 32.0) * sin(el)
	var zz := piv.z + l * sin(el) * 32.0 + upo * cos(el)
	var uv := Vector2(piv.x, piv.y) + fd * along + sd * side
	return K.pt(o, f, uv.x, uv.y, zz)


## Elevated box: spans [l0, l1] tiles along the axis, [s0, s1] tiles across, [c0, c1] px up. Draws the
## camera-facing faces, returns {name: {pts, vis}} (names in FACES) plus "tip" (front face centre).
static func _tbox(cv, o: Vector2, f: int, piv: Vector3, el: float, l0: float, l1: float, s0: float, s1: float,
		c0: float, c1: float, col: Color, yaw := YAW, team := false, sd := 1) -> Dictionary:
	var cs: Array = []
	for zi in 2:
		for yi in 2:
			for xi in 2:
				cs.append(_lp(o, f, piv, el, [l0, l1][xi], yaw, [s0, s1][yi], [c0, c1][zi]))
	var fdv := Vector2(cos(yaw), sin(yaw))
	var sdv := Vector2(-sin(yaw), cos(yaw))
	var res := {}
	for nm in FACES:
		var q := PackedVector2Array()
		for i in FACES[nm]:
			q.append(cs[i])
		var area := 0.0
		for i in 4:
			area += q[i].x * q[(i + 1) % 4].y - q[(i + 1) % 4].x * q[i].y
		var vis: bool = area * float(FLIP[nm]) > 0.5
		res[nm] = {"pts": q, "vis": vis}
		if not vis:
			continue
		var n: Vector3 = FN[nm]
		var hor: Vector2 = fdv * (n.x * cos(el) - n.z * sin(el)) + sdv * n.y
		var nz := n.x * sin(el) + n.z * cos(el)
		var w2 := K.wp(f, hor.x, hor.y)
		var k := 1.04
		if w2.length() > 0.01:
			k = lerpf(P.side_shade(w2), 1.04, clampf(nz, 0.0, 1.0))
		cv.team = team
		cv.poly(q, P.mul(col, k), P.speckle(0.06, sd + q.size() + int(nz * 10)))
		cv.team = false
	var tp: PackedVector2Array = res.front.pts
	res["tip"] = (tp[0] + tp[1] + tp[2] + tp[3]) * 0.25
	res["corners"] = cs
	return res


## Barrel: `th` px thick, lit top line, from l0 to l1 along the elevated axis. Returns the muzzle point.
static func _rod(cv, o: Vector2, f: int, piv: Vector3, el: float, l0: float, l1: float, th: int, col: Color,
		yaw := YAW, side := 0.0) -> Vector2:
	var a := _lp(o, f, piv, el, l0, yaw, side)
	var b := _lp(o, f, piv, el, l1, yaw, side)
	for t in th:
		var k := 0.78 if t == 0 else (1.28 if t == th - 1 else 1.0)
		cv.line_v(a + Vector2(0, -t), b + Vector2(0, -t), P.mul(col, k))
	return b + Vector2(0, -(th - 1) * 0.5)


## Emissive pixel that never becomes an outline seed: over the sprite it paints opaque, over empty
## canvas it stays at alpha < 0.6 (the H.bld outline only rings pixels with alpha >= 0.6).
static func _glow(cv, x: int, y: int, c: Color, a := 0.56) -> void:
	if x < 0 or y < 0 or x >= cv.w or y >= cv.h:
		return
	var e: Color = cv.get_px(x, y)
	if e.a >= 0.6:
		cv.img.set_pixel(x, y, e.blend(Color(c.r, c.g, c.b, minf(1.0, a + 0.3))))
		cv.mask.set_pixel(x, y, Color(0, 0, 0, 0))
	else:
		var na := maxf(e.a, a)
		cv.img.set_pixel(x, y, Color(c.r, c.g, c.b, minf(na, 0.58)))


static func _gline(cv, a: Vector2, b: Vector2, c: Color, al := 0.56) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
	for i in n + 1:
		var p := a.lerp(b, float(i) / maxf(1.0, n))
		_glow(cv, int(floor(p.x)), int(floor(p.y)), c, al)


## Beam: hot core with a coloured halo either side (screen space).
static func _beam(cv, a: Vector2, b: Vector2, core: Color, halo: Color) -> void:
	var d := (b - a).normalized()
	var pr := Vector2(-d.y, d.x)
	_gline(cv, a + pr, b + pr, halo, 0.4)
	_gline(cv, a - pr, b - pr, halo, 0.4)
	_gline(cv, a, b, core, 0.58)


## Jagged lightning between two screen points (deterministic), cyan halo + hot core.
static func _bolt(cv, a: Vector2, b: Vector2, s: int, jag := 3.0, core := L.CYAN_HOT, halo := L.CYAN) -> void:
	var n := maxi(3, int(a.distance_to(b) / 5.0))
	var d := (b - a)
	var pr := Vector2(-d.y, d.x).normalized()
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / n
		var off := 0.0 if i == n else (P.hn(i, s, 811) - 0.5) * 2.0 * jag
		var p := a.lerp(b, t) + pr * off
		_gline(cv, prev + Vector2(1, 0), p + Vector2(1, 0), halo, 0.36)
		_gline(cv, prev + Vector2(-1, 0), p + Vector2(-1, 0), halo, 0.3)
		_gline(cv, prev, p, core, 0.58)
		if P.hn(i, s, 812) > 0.62 and i < n:  # forked spark
			var fp := p + pr * (P.hn(i, s, 813) - 0.5) * 8.0 + d.normalized() * 3.0
			_gline(cv, p, fp, halo, 0.45)
		prev = p


## Soft ring (ellipse outline) in screen space; part = "all" | "back" | "front" half.
static func _ring(cv, c: Vector2, rx: float, ry: float, col: Color, a: float, part := "all", dash := 0) -> void:
	var n := int(maxf(rx, ry) * 6.0)
	for i in n:
		var t := TAU * i / n
		var p := c + Vector2(cos(t) * rx, sin(t) * ry)
		if part == "back" and sin(t) > 0.0:
			continue
		if part == "front" and sin(t) <= 0.0:
			continue
		if dash > 0 and (i / dash) % 2 == 1:
			continue
		_glow(cv, int(floor(p.x)), int(floor(p.y)), col, a)


## Human team flag on a pole (buildings.gd built-state flag, smaller).
static func _flag(cv, base: Vector2, ph: int, fw := 9) -> void:
	cv.line(int(base.x), int(base.y), int(base.x), int(base.y) - ph, Color8(60, 60, 56))
	cv.team = true
	for yy in 5:
		for xx in fw:
			var wave := int(round(sin(xx * 0.7) * 0.8))
			cv.px(int(base.x) + 1 + xx, int(base.y) - ph + yy + wave, Color(0.85, 0.85, 0.85) if yy > 0 else Color(1, 1, 1))
	cv.team = false


## Ring of sandbags (part list) around (cu, cv0): radii ru/rv tiles, n bags per layer, gap centred at
## angle ga (local, 0 = +u) of half-width gw radians.
static func _bag_ring(ps: Array, cu: float, cv0: float, ru: float, rv: float, n: int, layers: int, col: Color,
		ga := PI, gw := 0.45, bag := 0.09, bh := 3.0) -> void:
	for layer in layers:
		for i in n:
			var a := TAU * (i + 0.5 * layer) / n
			var da := absf(wrapf(a - ga, -PI, PI))
			if da < gw:
				continue
			var c := P.mul(col, 0.9 + 0.14 * P.hn(i, layer, 77))
			ps.append([cu + ru * cos(a), cv0 + rv * sin(a), layer * bh, bag, bag, bh, c, "bags"])


## Machine foundation slab with the hex tiling (faction_m_bld built look).
static func _m_slab(cv, o: Vector2, size: int) -> void:
	var half := size * 0.5 - 0.05
	var slab: Dictionary = P.box(cv, o, Vector3(0, 0, 0), half, half, 2.0, 0.0, L.SLAB, 0.1, 5)
	BD.slab_pattern(cv, slab.top, size, false)
	B.edges(cv, slab, L.SLAB)


## Missile in flight: body from tail to nose (screen), fins, exhaust flame, smoke trail back to `from`.
static func _missile(cv, from: Vector2, tail: Vector2, nose: Vector2, body: Color, s: int) -> void:
	var n := int(from.distance_to(tail) / 3.0)
	for i in n:
		var t := float(i) / maxf(1.0, n)
		var p := from.lerp(tail, t) + Vector2((P.hn(i, s, 5) - 0.5) * 2.0, (P.hn(i, s, 6) - 0.5) * 2.0)
		U4.puff(cv, p, 1.4 + 2.2 * t, 0.3 + 0.24 * t, Color(0.86, 0.85, 0.8))
	var d := (nose - tail).normalized()
	U4.flame(cv, tail, -d, 5.0, s)
	cv.line_v(tail, nose, P.mul(body, 0.72))
	cv.line_v(tail + Vector2(0, -1), nose + Vector2(0, -1), body)
	cv.line_v(tail + Vector2(0, -2), nose + Vector2(0, -2), P.mul(body, 1.22))
	var pr := Vector2(-d.y, d.x)
	for k in [-2.0, 2.0]:  # tail fins
		cv.px(int(tail.x + pr.x * k), int(tail.y - 1 + pr.y * k), P.mul(body, 0.62))
	cv.px(int(nose.x), int(nose.y) - 1, Color8(40, 40, 38))
	cv.px(int(nose.x + d.x), int(nose.y + d.y) - 1, Color8(40, 40, 38))


# ================================================================ Human A
## a_atgm_bunker: low cast-concrete bunker (slits, roof hatch), roof turntable with a twin ATGM launcher,
## one missile climbing out for a top-attack shot.
static func atgm_bunker(cv, o: Vector2, f: int) -> void:
	var slab := K.pal("a", "slab")
	var ps: Array = [[0, 0, 0, 0.95, 0.95, 2, slab, "slab"],
		[0.0, 0.0, 0, 0.82, 0.78, 0, P.mul(EARTH, 0.95), "mat"],
		[-0.05, 0.0, 2, 0.6, 0.56, 12, CONC_A, "conc"],
		[-0.05, 0.0, 14, 0.62, 0.58, 2, P.mul(CONC_A, 0.9), "box"],
		[-0.42, 0.28, 16, 0.12, 0.12, 2, Color(0.8, 0.8, 0.8), "team"],
		[0.06, 0.0, 16, 0.22, 0.2, 3, GUN_A, "box"],
		[0.06, 0.0, 19, 0.2, 0.18, 7, OLIVE, "turret"],
		[-0.42, -0.36, 16, 0.02, 0.02, 18, Color8(52, 54, 50), "pole"],
		[-0.4, -0.1, 16, 0.1, 0.08, 3, P.mul(CONC_A, 0.8), "box"],
		[0.72, -0.42, 2, 0.1, 0.28, 5, SAND, "bags"], [0.72, 0.4, 2, 0.1, 0.28, 5, SAND, "bags"],
		[-0.7, 0.66, 2, 0.13, 0.09, 5, OLIVE_D, "crate"], [-0.5, 0.7, 2, 0.08, 0.08, 4, OLIVE_D, "crate"]]
	_render(cv, o, f, ps, "a")
	var piv := Vector3(0.06, 0.0, 27.0)
	var el := 0.42
	for sv in [-0.1, 0.1]:
		var tb := _tbox(cv, o, f, piv, el, -0.34, 0.4, sv - 0.075, sv + 0.075, -3.5, 3.5, OLIVE, YAW, false, 11)
		for nm in ["left", "top"]:
			if tb[nm].vis:
				var q: PackedVector2Array = tb[nm].pts
				cv.line_v(P.sub(q, 0.12, 0, 0.12, 1)[0], P.sub(q, 0.12, 0, 0.12, 1)[3], P.mul(OLIVE, 0.7))
				cv.line_v(P.sub(q, 0.88, 0, 0.88, 1)[0], P.sub(q, 0.88, 0, 0.88, 1)[3], P.mul(OLIVE, 0.7))
	var sight := _tbox(cv, o, f, piv, el, -0.12, 0.1, -0.26, -0.18, -2.0, 3.0, GUN_A, YAW, false, 12)
	if sight.front.vis:
		cv.poly(P.sub(sight.front.pts, 0.2, 0.3, 0.8, 0.8), D.VISION)
	var t0 := _lp(o, f, piv, el, 0.41, YAW, -0.1)
	var t1 := _lp(o, f, piv, el, 0.41, YAW, 0.1)
	cv.ellipse(t0.x, t0.y, 2.2, 2.4, Color8(24, 24, 22))  # empty (fired) tube
	cv.ellipse(t1.x, t1.y, 2.2, 2.4, P.mul(OLIVE, 1.2))  # sealed tube cap
	cv.px(int(t1.x), int(t1.y), P.mul(OLIVE, 0.8))
	_flag(cv, K.pt(o, f, -0.82, 0.82, 2), 22)
	var e2 := 0.66
	var from := _lp(o, f, piv, el, 0.44, YAW, -0.1)
	var tail := _lp(o, f, piv, e2, 0.86, YAW + 0.05, -0.1, 6)
	var nose := _lp(o, f, piv, e2, 1.16, YAW + 0.05, -0.1, 6)
	_missile(cv, from, tail, nose, Color8(118, 124, 96), 41 + f)


## a_sam_site: concrete pad, launcher bed with turntable and a four-canister pack raised at 45 degrees,
## one missile launching (flame + smoke cloud), control cabin with team roof, cable.
static func sam_site(cv, o: Vector2, f: int) -> void:
	var slab := K.pal("a", "slab")
	var ps: Array = [[0, 0, 0, 0.95, 0.95, 2, slab, "slab"],
		[0.0, 0.0, 2, 0.62, 0.62, 0, P.mul(slab, 0.9), "mat"],
		[-0.05, 0.0, 2, 0.4, 0.34, 6, OLIVE_D, "box"],
		[-0.05, 0.0, 8, 0.24, 0.24, 4, GUN_A, "cyl"],
		[-0.08, 0.0, 12, 0.2, 0.22, 6, OLIVE, "turret"],
		[-0.68, -0.62, 2, 0.2, 0.16, 10, OLIVE, "cabin"],
		[-0.4, -0.68, 2, 0.02, 0.02, 22, Color8(52, 54, 50), "pole"],
		[0.66, 0.66, 2, 0.12, 0.12, 6, OLIVE_D, "crate"]]
	_render(cv, o, f, ps, "a")
	# pad markings
	for u in [-0.55, 0.55]:
		K.gline(cv, o, f, u, -0.55, u, 0.55, 2, Color8(214, 186, 70))
	B.cable(cv, K.pt(o, f, -0.5, -0.55, 6), K.pt(o, f, -0.25, -0.3, 6), 2.0)
	var piv := Vector3(-0.2, 0.0, 18.0)
	var el := 0.72
	var pk := _tbox(cv, o, f, piv, el, -0.12, 0.7, -0.2, 0.2, -7.0, 7.0, OLIVE, YAW, false, 21)
	# canister divisions + team band on the long faces
	for nm in ["left", "right", "top"]:
		if not pk[nm].vis:
			continue
		var q: PackedVector2Array = pk[nm].pts
		if nm == "right":
			q = PackedVector2Array([q[0], q[3], q[2], q[1]])  # right face is (side, up)-ordered: make u = along
		cv.line_v(P.sub(q, 0, 0.5, 1, 0.5)[0], P.sub(q, 0, 0.5, 1, 0.5)[1], P.mul(OLIVE, 0.7))
		cv.team = true
		cv.poly(P.sub(q, 0.52, 0.0, 0.66, 1.0), Color(0.68, 0.68, 0.68))
		cv.team = false
	var fq: PackedVector2Array = pk.front.pts
	var caps := [[0.27, 0.27], [0.73, 0.27], [0.27, 0.73], [0.73, 0.73]]
	if pk.front.vis:
		for i in 4:
			var cp: Vector2 = P.sub(fq, caps[i][0], caps[i][1], caps[i][0], caps[i][1])[0]
			cv.ellipse(cp.x, cp.y, 2.4, 2.2, Color8(30, 30, 28))
			if i != 3:
				cv.ellipse(cp.x - 0.3, cp.y - 0.3, 1.6, 1.5, P.mul(OLIVE, 1.22))
	cv.line_v(K.pt(o, f, -0.2, 0.0, 12), _lp(o, f, piv, el, 0.2, YAW, 0, -7), GUN_A)  # elevation ram
	_flag(cv, K.pt(o, f, -0.82, 0.82, 2), 22)
	# launch: the upper near canister fires
	var src := _lp(o, f, piv, el, 0.72, YAW, 0.1, 3.5)
	var tail := _lp(o, f, piv, el, 1.05, YAW, 0.1, 3.5)
	var nose := _lp(o, f, piv, el, 1.32, YAW, 0.1, 3.5)
	for i in 6:
		var pp := _lp(o, f, piv, el, -0.15 - i * 0.05, YAW, 0.1 + (P.hn(i, f, 31) - 0.5) * 0.5, 0) + Vector2(0, 6 + i)
		U4.puff(cv, pp, 3.0 + i * 0.6, 0.42)
	_missile(cv, src, tail, nose, Color8(226, 224, 214), 53 + f)


## a_laser_ciws: pedestal laser on a small pad: concrete column, olive head with team band, sensor
## block, emitter with glowing lens and a beam burning a drone out of the air.
static func laser_ciws(cv, o: Vector2, f: int) -> void:
	var slab := K.pal("a", "slab")
	var ps: Array = [[0, 0, 0, 0.46, 0.46, 2, slab, "slab"],
		[0, 0, 2, 0.17, 0.17, 12, P.mul(CONC_A, 0.95), "cyl"],
		[0, 0, 14, 0.15, 0.15, 2, GUN_A, "cyl"],
		[-0.02, 0, 16, 0.15, 0.13, 8, OLIVE, "turret"],
		[-0.36, 0.3, 2, 0.08, 0.1, 6, OLIVE_D, "box"],
		[0.34, -0.34, 2, 0.05, 0.05, 7, P.mul(CONC_A, 0.8), "box"]]
	_render(cv, o, f, ps, "a")
	for u in [-0.4, 0.4]:
		K.gline(cv, o, f, u, -0.4, u, 0.4, 2, Color8(214, 186, 70))
	B.cable(cv, K.pt(o, f, -0.3, 0.3, 6), K.pt(o, f, -0.1, 0.12, 8), 1.5)
	var piv := Vector3(0.0, 0.0, 22.0)
	var el := 0.62
	var em := _tbox(cv, o, f, piv, el, -0.12, 0.24, -0.06, 0.06, -3.5, 3.5, GUN_A, YAW, false, 31)
	var sens := _tbox(cv, o, f, piv, el, -0.06, 0.12, 0.09, 0.15, -2.0, 2.0, OLIVE_D, YAW, false, 32)
	if sens.front.vis:
		cv.px(int(sens.tip.x), int(sens.tip.y), D.VISION)
	var lens: Vector2 = em.tip
	cv.ellipse(lens.x, lens.y, 2.2, 2.0, Color8(60, 30, 28))
	cv.px(int(lens.x), int(lens.y), LASER)
	# beam to a drone in the air
	var tgt := _lp(o, f, piv, el, 0.98, YAW, 0)
	tgt.x = clampf(tgt.x, 6.0, cv.w - 7.0)
	tgt.y = maxf(tgt.y, 5.0)
	_beam(cv, lens, tgt, LASER_HOT, LASER)
	_glow(cv, int(lens.x), int(lens.y), LASER_HOT, 0.58)
	# drone silhouette breaking up
	cv.rect(int(tgt.x) - 2, int(tgt.y) - 1, 5, 2, Color8(46, 48, 46))
	cv.px(int(tgt.x) - 3, int(tgt.y) - 2, Color8(46, 48, 46))
	cv.px(int(tgt.x) + 3, int(tgt.y) - 2, Color8(46, 48, 46))
	U4.flash(cv, tgt + Vector2(1, 0), 0.9)
	U4.puff(cv, tgt + Vector2(3, -3), 2.6, 0.4, Color(0.3, 0.29, 0.27))
	for i in 3:
		cv.px(int(tgt.x) + 4 + i, int(tgt.y) + 2 + i * 2, Color8(255, 196, 80))


## a_howitzer_pit: dug-in 155 behind a two-layer sandbag ring; split trails with spades, wheels,
## team-marked shield, long elevated barrel firing, ready rounds and crates in the pit.
static func howitzer_pit(cv, o: Vector2, f: int) -> void:
	var ps: Array = [[0, 0, 0, 0.9, 0.86, 0, EARTH, "mat"], [0.02, 0, 0, 0.66, 0.62, 0, EARTH_D, "mat"]]
	_bag_ring(ps, 0.0, 0.0, 0.76, 0.72, 18, 2, SAND, PI, 0.4)
	ps.append([-0.42, 0.42, 0, 0.12, 0.09, 5, OLIVE_D, "crate"])
	ps.append([-0.42, 0.22, 0, 0.1, 0.08, 4, OLIVE_D, "crate"])
	ps.append([0.0, 0.0, 0, 0.3, 0.26, 10, OLIVE, "shadow"])
	var gun := func(c) -> void: _howitzer(c, o, f)
	var rounds := func(c) -> void:
		for i in 4:
			var b := K.pt(o, f, -0.5 + i * 0.07, -0.3, 0)
			c.rect(int(b.x), int(b.y) - 6, 2, 6, BRASS)
			c.px(int(b.x), int(b.y) - 7, Color8(90, 96, 70))
			c.px(int(b.x), int(b.y) - 6, P.mul(BRASS, 1.25))
	_render(cv, o, f, ps, "a", [[0.0, 0.0, 0.0, gun], [-0.5, -0.3, 0.0, rounds]])
	_flag(cv, K.pt(o, f, -0.86, 0.86, 0), 22)


static func _howitzer(cv, o: Vector2, f: int) -> void:
	var piv := Vector3(0.05, 0.0, 10.0)
	var el := 0.52
	var fd := Vector2(cos(YAW), sin(YAW))
	var sdv := Vector2(-sin(YAW), cos(YAW))
	for s in [-1.0, 1.0]:  # split trails with spades
		var a: Vector2 = Vector2(0.0, 0.0) + sdv * 0.06 * s
		var b: Vector2 = Vector2(0.0, 0.0) - fd * 0.62 + sdv * 0.3 * s
		var pa := K.pt(o, f, a.x, a.y, 2)
		var pb := K.pt(o, f, b.x, b.y, 1)
		cv.line_v(pa, pb, OLIVE_D)
		cv.line_v(pa + Vector2(0, 1), pb + Vector2(0, 1), P.mul(OLIVE_D, 0.7))
		cv.rect(int(pb.x) - 1, int(pb.y), 3, 2, GUN_A)
	for s in [-1.0, 1.0]:  # road wheels
		var w: Vector2 = Vector2(0.02, 0.0) + sdv * 0.22 * s
		var pw := K.pt(o, f, w.x, w.y, 4)
		cv.ellipse(pw.x, pw.y, 2.6, 3.4, D.RUBBER)
		cv.px(int(pw.x), int(pw.y), D.RIM)
	_tbox(cv, o, f, Vector3(0.0, 0.0, 4.0), 0.0, -0.16, 0.14, -0.13, 0.13, 0.0, 6.0, OLIVE, YAW, false, 41)  # carriage
	_rod(cv, o, f, piv, el, -0.36, 0.25, 2, P.mul(GUN_A, 1.1), YAW, 0.0)  # recoil slide
	var sh := _tbox(cv, o, f, Vector3(0.0, 0.0, 6.0), 0.12, 0.14, 0.17, -0.24, 0.24, 0.0, 9.0, OLIVE, YAW, false, 42)
	for nm in ["front", "back"]:
		if sh[nm].vis:
			var q: PackedVector2Array = sh[nm].pts
			cv.team = true
			cv.poly(P.sub(q, 0.12, 0.45, 0.88, 0.72), Color(0.66, 0.66, 0.66))
			cv.team = false
	var tip := _rod(cv, o, f, piv, el, -0.2, 1.28, 3, GUN_A, YAW, 0.0)
	var ev := _lp(o, f, piv, el, 0.62, YAW)
	cv.rect(int(ev.x) - 1, int(ev.y) - 2, 3, 3, P.mul(GUN_A, 1.1))  # bore evacuator
	cv.rect(int(tip.x) - 1, int(tip.y) - 2, 3, 4, P.mul(GUN_A, 0.9))  # muzzle brake
	U4.flash(cv, tip + Vector2(1, -1), 1.5)
	U4.puff(cv, tip + Vector2(4, -4), 3.2, 0.5)
	U4.puff(cv, tip + Vector2(8, -7), 2.4, 0.36)
	U4.puff(cv, tip + Vector2(-3, -2), 2.4, 0.3)


## a_popup_turret: flush concrete hatch ring with the lid flipped up, telescoping column raised, RWS head
## (team band, optics block, ammo can) firing an MG burst with tracer; turf kicked up around the ring.
static func popup_turret(cv, o: Vector2, f: int) -> void:
	var ps: Array = [[0, 0, 0, 0.34, 0.32, 0, P.mul(EARTH, 1.0), "mat"]]
	ps.append([0, 0, 0, 0.26, 0.26, 2, CONC_A, "cyl"])
	_render(cv, o, f, ps, "a")
	var c := K.pt(o, f, 0, 0, 2)
	cv.ellipse(c.x, c.y, 8.0, 4.0, Color8(26, 26, 24))  # open shaft
	cv.ellipse(c.x, c.y + 1, 7.0, 3.0, Color8(40, 40, 36))
	for i in 8:  # kicked turf / dirt chips
		var a := TAU * i / 8.0 + 0.3
		var pt := c + Vector2(cos(a) * 13.0, sin(a) * 6.5)
		cv.rect(int(pt.x), int(pt.y), 2, 1, Color8(84, 96, 52) if i % 2 == 0 else EARTH_D)
	# lid hinged at the rear edge, flipped up
	_tbox(cv, o, f, Vector3(-0.24, 0.0, 2.0), 1.25, 0.0, 0.3, -0.16, 0.16, 0.0, 1.5, P.mul(CONC_A, 0.85), YAW, false, 51)
	B.cyl(cv, o, Vector3(0, 0, 1), 0.08, 11.0, GUN_A, 52, -1.0, 2)
	B.cyl(cv, o, Vector3(0, 0, 7), 0.1, 2.0, P.mul(GUN_A, 1.2), 53)
	var hd: Dictionary = K.part(cv, o, f, [0.0, 0.0, 12, 0.12, 0.1, 6, OLIVE, "box"], 1.0, false)
	_dress(cv, o, f, [0.0, 0.0, 12, 0.12, 0.1, 6, OLIVE, "turret"], hd, "a")
	var opt := _tbox(cv, o, f, Vector3(0.0, 0.0, 13.0), 0.0, -0.05, 0.07, 0.11, 0.17, 0.0, 5.0, GUN_A, YAW, false, 54)
	if opt.front.vis:
		cv.poly(P.sub(opt.front.pts, 0.2, 0.35, 0.8, 0.8), D.VISION)
	_tbox(cv, o, f, Vector3(0.0, 0.0, 12.5), 0.0, -0.06, 0.04, -0.17, -0.11, 0.0, 3.5, OLIVE_D, YAW, false, 55)
	var tip := _rod(cv, o, f, Vector3(0.06, -0.02, 15.0), 0.06, 0.0, 0.36, 2, GUN_A)
	U4.flash(cv, tip + Vector2(1, 0), 1.0)
	var t2 := _lp(o, f, Vector3(0.06, -0.02, 15.0), 0.06, 0.95)
	_gline(cv, tip + (t2 - tip) * 0.25, tip + (t2 - tip) * 0.6, Color8(255, 210, 110), 0.56)
	_gline(cv, tip + (t2 - tip) * 0.72, t2, Color8(255, 210, 110), 0.5)
	var ej := _lp(o, f, Vector3(0.0, 0.0, 15.0), 0.0, 0.0, YAW, 0.16)
	for i in 3:
		cv.px(int(ej.x) - i * 2 - 1, int(ej.y) - 1 + i, BRASS)


# ================================================================ Human B
## b_pak_nest: towed AT gun dug in behind welded scrap plates and sandbags; primer-grey riveted shield
## with team panel, spoked wheels, split trails, wooden ammo boxes, firing (flash + dust).
static func pak_nest(cv, o: Vector2, f: int) -> void:
	var ps: Array = [[0, 0, 0, 0.47, 0.45, 0, EARTH, "mat"], [0.02, 0, 0, 0.34, 0.32, 0, EARTH_D, "mat"]]
	var plates := [[0.37, -0.31, 0.09, 8.0, V.RUST], [0.4, -0.15, 0.06, 10.0, KHAKI], [0.4, 0.16, 0.07, 9.0, V.PRIMER],
		[0.37, 0.32, 0.09, 7.0, V.RUST]]
	for pl in plates:
		ps.append([pl[0], pl[1], 0, 0.025, pl[2], pl[3], pl[4], "scrap"])
	for v in [-0.34, -0.17, 0.17, 0.34]:
		ps.append([0.45, v, 0, 0.05, 0.08, 4.0, SAND_B, "bags"])
	for u in [-0.3, -0.1, 0.1]:
		ps.append([u, 0.41, 0, 0.09, 0.05, 4.0, P.mul(SAND_B, 0.95), "bags"])
		ps.append([u, -0.41, 0, 0.09, 0.05, 4.0, P.mul(SAND_B, 1.03), "bags"])
	ps.append([-0.36, -0.24, 0, 0.07, 0.05, 4, WOOD, "crate"])
	ps.append([-0.36, -0.24, 4, 0.06, 0.045, 3, P.mul(WOOD, 0.9), "crate"])
	ps.append([0.0, 0.0, 0, 0.18, 0.18, 8, KHAKI, "shadow"])
	var gun := func(c) -> void: _pak(c, o, f)
	_render(cv, o, f, ps, "b", [[0.02, 0.0, 0.0, gun]])
	_flag(cv, K.pt(o, f, -0.44, 0.42, 0), 18, 7)


static func _pak(cv, o: Vector2, f: int) -> void:
	var yaw := 0.12
	var fd := Vector2(cos(yaw), sin(yaw))
	var sdv := Vector2(-sin(yaw), cos(yaw))
	for s in [-1.0, 1.0]:  # split trails
		var pa := K.pt(o, f, sdv.x * 0.04 * s, sdv.y * 0.04 * s, 3)
		var b: Vector2 = -fd * 0.3 + sdv * 0.15 * s
		var pb := K.pt(o, f, b.x, b.y, 1)
		cv.line_v(pa, pb, P.mul(KHAKI, 1.1))
		cv.line_v(pa + Vector2(0, 1), pb + Vector2(0, 1), P.mul(KHAKI_D, 0.8))
		cv.rect(int(pb.x) - 1, int(pb.y), 3, 2, GUN_B)
	for s in [-1.0, 1.0]:  # spoked wheels
		var w: Vector2 = sdv * 0.15 * s
		var pw := K.pt(o, f, w.x, w.y, 4)
		cv.ellipse(pw.x, pw.y, 2.4, 3.8, D.RUBBER)
		cv.ellipse(pw.x, pw.y, 1.4, 2.6, P.mul(KHAKI, 0.95))
		cv.px(int(pw.x), int(pw.y), D.RUBBER)
	var piv := Vector3(0.02, 0.0, 8.0)
	_tbox(cv, o, f, Vector3(0.0, 0.0, 4.0), 0.0, -0.1, 0.08, -0.06, 0.06, 0.0, 5.0, KHAKI, yaw, false, 61)
	var sh := _tbox(cv, o, f, Vector3(0.05, 0.0, 2.0), 0.1, 0.0, 0.025, -0.2, 0.2, 0.0, 10.0, Color8(112, 112, 102), yaw, false, 62)
	for nm in ["front", "back"]:
		if sh[nm].vis:
			var q: PackedVector2Array = sh[nm].pts
			V.rivets(cv, q, 0.86, 6, Color8(112, 112, 102))
			V.patch(cv, q, 0.04, 0.1, 0.3, 0.5, KHAKI, 63)
			cv.team = true
			cv.poly(P.sub(q, 0.6, 0.3, 0.92, 0.64), Color(0.66, 0.66, 0.66))
			cv.team = false
			V.streaks(cv, q, 64)
			cv.poly(P.sub(q, 0.44, 0.45, 0.56, 0.62), Color8(24, 24, 22))  # sight window
	_tbox(cv, o, f, piv, 0.03, -0.2, 0.18, -0.04, 0.04, -2.0, 2.0, P.mul(GUN_B, 1.15), yaw, false, 65)  # recoil cylinder
	var tip := _rod(cv, o, f, piv, 0.03, 0.15, 0.64, 2, P.mul(GUN_B, 1.35), yaw)
	cv.rect(int(tip.x) - 1, int(tip.y) - 2, 3, 4, P.mul(GUN_B, 1.1))  # muzzle brake
	U4.flash(cv, tip + Vector2(2, 0), 1.2)
	U4.puff(cv, tip + Vector2(5, -2), 2.6, 0.45)
	for i in 3:  # dust kicked up in front of the nest
		U4.puff(cv, K.pt(o, f, 0.5, -0.2 + i * 0.2, 2), 2.0, 0.32, Color(0.62, 0.52, 0.38))


## b_flak_battery: twin-barrel flak gun on a riveted cross base with jack pads, carriage with team
## panel, clip racks and spent casings; the barrels fire and three flak bursts hang in the sky.
static func flak_battery(cv, o: Vector2, f: int) -> void:
	var slab := K.pal("b", "slab")
	var ps: Array = [[0, 0, 0, 0.92, 0.92, 2, slab, "slab"],
		[0, 0, 2, 0.74, 0.07, 3, KHAKI_D, "plate"], [0, 0, 2, 0.07, 0.74, 3, KHAKI_D, "plate"]]
	for d in [Vector2(0.74, 0), Vector2(-0.74, 0), Vector2(0, 0.74), Vector2(0, -0.74)]:
		ps.append([d.x, d.y, 2, 0.09, 0.09, 4, GUN_B, "box"])
	ps.append([0, 0, 5, 0.18, 0.18, 5, GUN_B, "cyl"])
	ps.append([-0.04, 0, 10, 0.24, 0.2, 8, KHAKI, "turret"])
	ps.append([-0.6, 0.55, 2, 0.14, 0.09, 6, V.RUST, "crate"])
	ps.append([-0.6, 0.32, 2, 0.12, 0.08, 5, WOOD, "crate"])
	ps.append([0.55, -0.62, 2, 0.12, 0.1, 5, WOOD, "crate"])
	_bag_ring(ps, 0.0, 0.0, 0.86, 0.86, 22, 1, SAND_B, PI * 0.75, 0.5, 0.07, 4.0)
	_render(cv, o, f, ps, "b")
	for i in 7:  # spent casings
		var cp := K.pt(o, f, 0.2 + P.hn(i, 1, 91) * 0.4, -0.45 + P.hn(i, 2, 91) * 0.9, 2)
		cv.px(int(cp.x), int(cp.y), BRASS)
	var piv := Vector3(0.02, 0.0, 17.0)
	var el := 1.0
	var yaw := 0.3
	_tbox(cv, o, f, piv, el, -0.12, 0.16, -0.05, 0.05, -2.5, 2.5, GUN_B, yaw, false, 71)  # cradle
	var tips: Array = []
	for sv in [-0.08, 0.08]:
		tips.append(_rod(cv, o, f, piv, el, -0.08, 0.82, 2, GUN_B, yaw, sv))
		var fh := _lp(o, f, piv, el, 0.78, yaw, sv)
		cv.rect(int(fh.x) - 1, int(fh.y) - 1, 3, 2, P.mul(GUN_B, 1.2))  # flash hider
	# gunner seat + sight
	var seat := _lp(o, f, Vector3(-0.15, -0.18, 18), 0.0, 0.0, yaw)
	cv.rect(int(seat.x) - 1, int(seat.y) - 1, 3, 2, Color8(60, 54, 46))
	var sg := _lp(o, f, piv, el, 0.15, yaw, -0.16)
	cv.rect(int(sg.x), int(sg.y), 2, 2, P.mul(KHAKI, 1.2))
	for t in tips:
		U4.flash(cv, t + Vector2(0, -1), 1.0)
	# flak bursts in the sky (inside the canvas headroom)
	var bursts := [Vector2(0.18, 0.12), Vector2(0.5, 0.06), Vector2(0.78, 0.2)]
	for i in bursts.size():
		var bp := Vector2(cv.w * bursts[i].x, cv.h * bursts[i].y + 4)
		_flak_burst(cv, bp, 6.0 - i * 0.7, 90 + i)


static func _flak_burst(cv, c: Vector2, r: float, s: int) -> void:
	for k in 4:  # lumpy black-smoke ball, lit top-left rim, hot core
		var off := Vector2((P.hn(k, s, 1) - 0.5) * r * 1.2, (P.hn(k, s, 2) - 0.5) * r * 0.9)
		var rr := r * (0.6 + 0.35 * P.hn(k, s, 3))
		cv.ellipse(c.x + off.x, c.y + off.y, rr, rr * 0.85, Color8(52, 48, 46))
	cv.ellipse(c.x - r * 0.3, c.y - r * 0.35, r * 0.45, r * 0.35, Color8(92, 88, 82))
	cv.px(int(c.x), int(c.y), Color8(255, 226, 140))
	cv.px(int(c.x) + 1, int(c.y), Color8(246, 150, 52))
	cv.px(int(c.x), int(c.y) + 1, Color8(246, 150, 52))
	U4.puff(cv, c + Vector2(r * 0.8, -r * 0.6), r * 0.8, 0.3, Color(0.4, 0.38, 0.36))


## b_net_post: rusty scaffold tower (braced legs, plank deck, corrugated parapet, ladder), triple
## net-launcher tubes on a pivot, one weighted net in flight wrapping a drone, a netted drone salvaged
## at the foot; team flag on the deck.
static func net_post(cv, o: Vector2, f: int) -> void:
	var dz := 20.0
	var legs := [Vector2(-0.24, -0.24), Vector2(0.24, -0.24), Vector2(0.24, 0.24), Vector2(-0.24, 0.24)]
	for lg in legs:
		var c := K.wp(f, lg.x, lg.y)
		P.box_shadow(cv, o, Vector3(c.x, c.y, 0), 0.04, 0.04, dz, 0.0)
	P.box_shadow(cv, o, Vector3(0, 0, dz), 0.34, 0.34, 8, K.rot(f))
	cv.flush_shadow()
	var ps: Array = [[0.42, 0.3, 0, 0.12, 0.1, 5, P.mul(SAND_B, 0.95), "bags"],
		[-0.36, 0.4, 0, 0.1, 0.09, 6, Color8(150, 132, 96), "box"]]
	_render(cv, o, f, ps, "b")
	# faces: [leg i, leg j], outward normal sign; draw back braces, legs, then front braces
	var faces := [[0, 1], [1, 2], [2, 3], [3, 0]]
	var back: Array = []
	var front: Array = []
	for fc in faces:
		var mid: Vector2 = (legs[fc[0]] + legs[fc[1]]) * 0.5
		var wm := K.wp(f, mid.x, mid.y)
		if wm.x + wm.y < 0.0:
			back.append(fc)
		else:
			front.append(fc)
	for fc in back:
		_braces(cv, o, f, legs[fc[0]], legs[fc[1]], dz, P.mul(V.RUST, 0.7))
	var order := [0, 1, 2, 3]
	order.sort_custom(func(a, b):
		var wa := K.wp(f, legs[a].x, legs[a].y)
		var wb := K.wp(f, legs[b].x, legs[b].y)
		return wa.x + wa.y < wb.x + wb.y)
	for i in order:
		var c3 := K.wp(f, legs[i].x, legs[i].y)
		var r := P.box(cv, o, Vector3(c3.x, c3.y, 0), 0.035, 0.035, dz, 0.0, STEEL_B if i % 2 == 0 else V.RUST, 0.08, 80 + i)
		B.edges(cv, r, STEEL_B)
	for fc in front:
		_braces(cv, o, f, legs[fc[0]], legs[fc[1]], dz, V.RUST)
	# ladder on the left leg pair
	var la := K.pt(o, f, 0.3, 0.12, 0)
	var lb := K.pt(o, f, 0.3, 0.12, dz)
	for s in [0, 3]:
		cv.line_v(la + Vector2(s, 0), lb + Vector2(s, 0), Color8(70, 66, 58))
	for k in 6:
		var y := la.y - 2 - k * 3
		cv.line(int(la.x), int(y), int(la.x) + 3, int(y), Color8(96, 90, 80))
	# deck + parapet
	var dk: Dictionary = K.part(cv, o, f, [0, 0, dz, 0.34, 0.34, 2, P.mul(WOOD, 0.9), "box"], 1.0, false)
	for i in 5:
		var u := 0.1 + i * 0.2
		cv.line_v(dk.top[0].lerp(dk.top[1], u), dk.top[3].lerp(dk.top[2], u), P.mul(WOOD, 0.72))
	K.part(cv, o, f, [-0.3, 0.0, dz + 2, 0.03, 0.32, 5, V.PRIMER, "box"], 1.0, false)
	K.part(cv, o, f, [0.0, -0.3, dz + 2, 0.3, 0.03, 5, V.RUST, "box"], 1.0, false)
	# launcher pivot + tubes
	B.cyl(cv, o, Vector3(K.wp(f, -0.04, 0.0).x, K.wp(f, -0.04, 0.0).y, dz + 2), 0.07, 5.0, GUN_B, 85)
	var piv := Vector3(-0.04, 0.0, dz + 9.0)
	var el := 0.5
	_tbox(cv, o, f, piv, el, -0.18, 0.06, -0.12, 0.12, -3.0, 3.0, KHAKI, YAW, false, 86)
	var tips: Array = []
	for sv in [-0.08, 0.0, 0.08]:
		tips.append(_rod(cv, o, f, piv, el, -0.1, 0.24, 3, P.mul(GUN_B, 1.15), YAW, sv))
	for t in tips:
		cv.px(int(t.x), int(t.y) - 1, Color8(22, 22, 20))
	var ph := K.pt(o, f, 0.0, 0.0, dz + 2)
	cv.team = true
	cv.poly(PackedVector2Array([ph + Vector2(-5, 0), ph + Vector2(5, 0), ph + Vector2(5, 3), ph + Vector2(-5, 3)]), Color(0.66, 0.66, 0.66))
	cv.team = false
	K.part(cv, o, f, [0.3, 0.0, dz + 2, 0.03, 0.32, 5, KHAKI, "box"], 1.0, false)
	K.part(cv, o, f, [0.0, 0.3, dz + 2, 0.3, 0.03, 5, V.PRIMER, "scrap"], 1.0, false)
	_flag(cv, K.pt(o, f, -0.3, -0.3, dz + 6), 16, 8)
	# net in flight around a drone
	var tp: Vector2 = tips[1]
	var nc := _lp(o, f, piv, el + 0.15, 0.75)
	nc.x = clampf(nc.x, 10.0, cv.w - 11.0)
	nc.y = clampf(nc.y, 9.0, cv.h)
	for k in 4:
		var t := (k + 0.5) / 4.0
		var p := tp.lerp(nc, t)
		cv.px(int(p.x), int(p.y), Color(ROPE.r, ROPE.g, ROPE.b, 0.55))
	cv.rect(int(nc.x) - 3, int(nc.y) - 1, 7, 2, Color8(48, 50, 48))  # caught drone
	cv.px(int(nc.x) - 4, int(nc.y) - 2, Color8(48, 50, 48))
	cv.px(int(nc.x) + 4, int(nc.y) - 2, Color8(48, 50, 48))
	var corners := [nc + Vector2(-8, -1), nc + Vector2(0, -7), nc + Vector2(8, 0), nc + Vector2(0, 6)]
	for k in 5:
		var t := k / 4.0
		var a: Vector2 = corners[0].lerp(corners[1], t)
		var b: Vector2 = corners[3].lerp(corners[2], t)
		_gline(cv, a, b, ROPE, 0.55)
		var c2: Vector2 = corners[0].lerp(corners[3], t)
		var d2: Vector2 = corners[1].lerp(corners[2], t)
		_gline(cv, c2, d2, ROPE, 0.55)
	for cn in corners:
		cv.rect(int(cn.x), int(cn.y), 2, 2, Color8(40, 40, 38))  # lead weights
	# netted drone salvaged at the foot
	var g := K.pt(o, f, 0.4, -0.38, 0)
	cv.rect(int(g.x) - 3, int(g.y) - 2, 6, 2, Color8(52, 54, 52))
	for k in 4:
		cv.px(int(g.x) - 4 + k * 3, int(g.y) - 3 + (k % 2), ROPE)


static func _braces(cv, o: Vector2, f: int, a: Vector2, b: Vector2, dz: float, col: Color) -> void:
	for h in [[0.0, dz * 0.5], [dz * 0.5, dz]]:
		cv.line_v(K.pt(o, f, a.x, a.y, h[0]), K.pt(o, f, b.x, b.y, h[1]), col)
		cv.line_v(K.pt(o, f, b.x, b.y, h[0]), K.pt(o, f, a.x, a.y, h[1]), col)
	cv.line_v(K.pt(o, f, a.x, a.y, dz * 0.5), K.pt(o, f, b.x, b.y, dz * 0.5), P.mul(col, 1.2))


## b_mortar_pit: sandbag ring around a dark pit, baseplate + bipod mortar firing (flash, smoke, round
## leaving), wooden ammo crates and ready bombs, team stake.
static func mortar_pit(cv, o: Vector2, f: int) -> void:
	var ps: Array = [[0, 0, 0, 0.44, 0.42, 0, EARTH, "mat"], [0.02, 0, 0, 0.3, 0.28, 0, EARTH_D, "mat"]]
	_bag_ring(ps, 0.02, 0.0, 0.36, 0.34, 12, 2, SAND_B, PI, 0.38, 0.065, 3.0)
	ps.append([-0.2, 0.17, 0, 0.07, 0.05, 4, WOOD, "crate"])
	ps.append([-0.2, 0.17, 4, 0.06, 0.045, 3, P.mul(WOOD, 0.9), "crate"])
	var mortar := func(c) -> void: _mortar(c, o, f)
	var bombs := func(c) -> void:
		for i in 3:
			var b := K.pt(o, f, -0.18 + i * 0.05, -0.16, 0)
			c.rect(int(b.x), int(b.y) - 4, 2, 4, Color8(86, 92, 66))
			c.px(int(b.x), int(b.y) - 5, Color8(64, 68, 50))
	_render(cv, o, f, ps, "b", [[0.03, 0.0, 0.0, mortar], [-0.15, -0.16, 0.0, bombs]])
	K.stake(cv, o, f, -0.42, 0.42, 16.0)


static func _mortar(cv, o: Vector2, f: int) -> void:
	var piv := Vector3(-0.02, 0.0, 2.0)
	var el := 1.12
	K.gquad(cv, o, f, -0.08, -0.07, 0.06, 0.07, 1, Color8(52, 50, 46))  # baseplate
	var mid := _lp(o, f, piv, el, 0.2)
	for s in [-1.0, 1.0]:
		var ft := K.pt(o, f, 0.14, 0.09 * s, 1)
		cv.line_v(mid, ft, Color8(60, 58, 54))
	var tip := _rod(cv, o, f, piv, el, 0.0, 0.42, 2, GUN_B)
	var sg := _lp(o, f, piv, el, 0.16, YAW, 0.06)
	cv.rect(int(sg.x), int(sg.y), 2, 2, P.mul(KHAKI, 1.15))
	U4.flash(cv, tip + Vector2(0, -2), 1.1)
	U4.puff(cv, tip + Vector2(1, -5), 3.0, 0.45)
	U4.puff(cv, tip + Vector2(-2, -3), 2.2, 0.35)
	cv.rect(int(tip.x) + 2, int(tip.y) - 12, 1, 2, Color8(40, 40, 36))  # round leaving


## b_pillbox: hexagonal cast pillbox, a firing slit on each of the 6 faces (3 visible), riveted steel
## roof cap with periscope, team panel over a slit, MG firing from the front slit, sandbag shoulders.
static func pillbox(cv, o: Vector2, f: int) -> void:
	var ps: Array = [[0, 0, 0, 0.48, 0.46, 0, EARTH, "mat"],
		[0, 0, 0, 0.4, 0.4, 13, CONC_B, "hex"],
		[0, 0, 13, 0.43, 0.43, 3, Color8(112, 100, 86), "hex"],
		[0, 0, 16, 0.05, 0.05, 4, STEEL_B, "cyl"],
		[-0.38, -0.36, 0, 0.08, 0.1, 4, SAND_B, "bags"], [-0.38, 0.36, 0, 0.1, 0.08, 4, SAND_B, "bags"]]
	_render(cv, o, f, ps, "b")
	var pz := K.pt(o, f, 0, 0, 20)
	cv.rect(int(pz.x) - 1, int(pz.y) - 1, 3, 1, B.GLASS_HI)
	var mz := K.pt(o, f, 0.34, 0.06, 7)
	var tip := mz + (K.pt(o, f, 0.6, 0.12, 6) - mz)
	cv.line_v(mz, tip, Color8(40, 40, 36))
	cv.line_v(mz + Vector2(0, -1), tip + Vector2(0, -1), Color8(70, 70, 64))
	U4.flash(cv, tip + Vector2(1, 0), 0.9)
	_gline(cv, tip + (tip - mz) * 0.4, tip + (tip - mz) * 1.0, Color8(255, 210, 110), 0.5)


# ================================================================ Machine
## m_arc_pylon: hex plinth (team panels), stacked coil column with cyan rings, capacitor sphere on top,
## lightning chaining from the sphere to two hit points and between them.
static func arc_pylon(cv, o: Vector2, f: int) -> void:
	_m_slab(cv, o, 1)
	var rt := K.rot(f)
	L.hex_shadow(cv, o, Vector3(0, 0, 0), 0.26, 40.0, 0.0)
	for d in [Vector2(-0.33, 0.33), Vector2(0.33, -0.33)]:
		var dw := K.wp(f, d.x, d.y)
		P.box_shadow(cv, o, Vector3(dw.x, dw.y, 2), 0.05, 0.05, 12, rt)
	cv.flush_shadow()
	for d in [Vector2(-0.33, 0.33), Vector2(0.33, -0.33)]:  # corner emitter posts (flank the plinth)
		var dw := K.wp(f, d.x, d.y)
		var pr: Dictionary = P.box(cv, o, Vector3(dw.x, dw.y, 2), 0.045, 0.045, 12, rt, L.GRAPH_D, 0.06, 181)
		for sd in pr.sides:
			L.seam(cv, sd.quad, 0.8)
		var tq := K.pt(o, f, d.x, d.y, 14)
		cv.px(int(tq.x), int(tq.y), L.CYAN_HOT)
	var base: Dictionary = L.hexp(cv, o, Vector3(0, 0, 2), 0.28, 8.0, rt, L.GRAPH, 182)
	for sd in base.sides:
		L.team_panel(cv, sd.quad, 0.15, 0.25, 0.85, 0.62)
	B.wall_ao(cv, base, 0.3)
	L.rims(cv, base, L.GRAPH)
	for i in 3:  # coil column: graphite segments, light panel collars, one seam each
		var seg: Dictionary = L.hexp(cv, o, Vector3(0, 0, 10 + i * 9), 0.1, 7.0, rt, L.GRAPH_D, 183 + i)
		for sd in seg.sides:
			L.seam(cv, sd.quad, 0.5)
		var col: Dictionary = L.hexp(cv, o, Vector3(0, 0, 17 + i * 9), 0.16 - i * 0.015, 2.0, rt, L.PANEL, 187 + i)
		L.rims(cv, col, L.PANEL)
	var c := K.pt(o, f, 0, 0, 41)
	cv.ellipse(c.x, c.y, 6.0, 5.2, L.GRAPH)
	cv.ellipse(c.x - 1.0, c.y - 1.0, 4.4, 3.6, L.PANEL_D)
	cv.ellipse(c.x - 2.0, c.y - 2.0, 2.0, 1.5, L.PANEL)
	cv.line_v(c + Vector2(-6, 1), c + Vector2(6, 1), L.TEAL)
	L.eye(cv, c + Vector2(1, 1), true)
	var h1 := K.pt(o, f, -0.42, 0.42, 2)
	var h2 := K.pt(o, f, 0.42, -0.42, 2)
	var h3 := K.pt(o, f, 0.44, 0.44, 2)
	h1.x = clampf(h1.x, 4.0, cv.w - 5.0)
	h2.x = clampf(h2.x, 4.0, cv.w - 5.0)
	_bolt(cv, c + Vector2(-4, 0), h1, 7 + f, 3.0)
	_bolt(cv, c + Vector2(4, 0), h2, 17 + f, 3.0)
	_bolt(cv, h1, h3, 27 + f, 2.0)
	for h in [h1, h2, h3]:  # hit points: scorch + spark ring
		cv.ellipse(h.x, h.y + 1, 3.0, 1.4, Color(0.1, 0.1, 0.1, 0.4))
		_ring(cv, h, 3.5, 1.6, L.CYAN, 0.45)
		_glow(cv, int(h.x), int(h.y), L.CYAN_HOT, 0.58)


## m_pulse_spire2: taller Spire (base with team panels, seamed mid shaft, slim upper shaft) with a
## rotating emitter ring carrying 4 nodes, a large crystal head and a pulse beam with wave rings.
static func pulse_spire2(cv, o: Vector2, f: int) -> void:
	_m_slab(cv, o, 1)
	var rt := K.rot(f)
	L.hex_shadow(cv, o, Vector3(0, 0, 0), 0.32, 66.0, 0.0)
	cv.flush_shadow()
	var base: Dictionary = L.hexp(cv, o, Vector3(0, 0, 2), 0.33, 10.0, rt, L.GRAPH, 142)
	for sd in base.sides:
		L.team_panel(cv, sd.quad, 0.15, 0.3, 0.85, 0.6)
	B.wall_ao(cv, base, 0.3)
	var mid: Dictionary = L.hexp(cv, o, Vector3(0, 0, 12), 0.22, 24.0, rt, L.PANEL, 143)
	for sd in mid.sides:
		L.seam(cv, sd.quad, 0.3)
		L.seam(cv, sd.quad, 0.62)
		L.joints(cv, sd.quad, [0.5], L.PANEL)
	var collar: Dictionary = L.hexp(cv, o, Vector3(0, 0, 36), 0.25, 3.0, rt, L.GRAPH_D, 145)
	L.rims(cv, collar, L.GRAPH_D)
	var rc := K.pt(o, f, 0, 0, 46)
	var rx := 14.0
	var ry := 6.5
	var spin := 0.5 + f * 0.6
	_emitter_ring(cv, rc, rx, ry, spin, true)
	var up: Dictionary = L.hexp(cv, o, Vector3(0, 0, 39), 0.13, 16.0, rt, L.GRAPH, 144)
	for sd in up.sides:
		var q: PackedVector2Array = sd.quad
		cv.line_v(q[0].lerp(q[1], 0.5), q[3].lerp(q[2], 0.5), L.CYAN)
	_emitter_ring(cv, rc, rx, ry, spin, false)
	var c := K.pt(o, f, 0, 0, 55)
	cv.ellipse(c.x, c.y - 8, 8.0, 10.0, Color(L.CYAN.r, L.CYAN.g, L.CYAN.b, 0.18))
	cv.poly(PackedVector2Array([c + Vector2(0, 1), c + Vector2(5, -7), c + Vector2(0, -17), c + Vector2(-5, -7)]), L.CYAN)
	cv.poly(PackedVector2Array([c + Vector2(0, -1), c + Vector2(2, -7), c + Vector2(0, -14), c + Vector2(-2, -7)]), L.CYAN_HOT)
	cv.line_v(c + Vector2(-5, -7), c + Vector2(0, -17), Color8(150, 240, 236))
	# pulse beam up and out, with wave rings
	var a := c + Vector2(0, -17)
	var b := Vector2(clampf(a.x + 22.0, 0, cv.w - 3.0), 2.0)
	_beam(cv, a, b, L.CYAN_HOT, L.CYAN)
	for k in 3:
		var p := a.lerp(b, 0.3 + k * 0.28)
		_ring(cv, p, 2.5 + k * 1.3, 1.6 + k * 0.8, L.CYAN, 0.45)


static func _emitter_ring(cv, c: Vector2, rx: float, ry: float, spin: float, back: bool) -> void:
	var n := 64
	for i in n:
		var t := TAU * i / n
		if (sin(t) <= 0.0) != back:
			continue
		var p := c + Vector2(cos(t) * rx, sin(t) * ry)
		var k := 0.8 + 0.3 * cos(t + 2.4)
		cv.rect(int(p.x), int(p.y), 2, 2, P.mul(L.PANEL_D, k * (0.8 if back else 1.0)))
		cv.px(int(p.x), int(p.y) + 2, L.JOINT)
		if i % 4 == 0:
			cv.px(int(p.x), int(p.y) + 1, L.TEAL)
	for j in 4:
		var t := spin + j * TAU / 4.0
		if (sin(t) <= 0.0) != back:
			continue
		var p := c + Vector2(cos(t) * rx, sin(t) * ry)
		cv.rect(int(p.x) - 1, int(p.y) - 2, 4, 4, L.GRAPH)
		cv.px(int(p.x), int(p.y) - 1, L.CYAN_HOT if not back else L.CYAN)
		cv.px(int(p.x) + 1, int(p.y) - 1, L.CYAN)


## m_jammer_obelisk: tapered stacked-hex obelisk with cyan glyph seams and a pyramid cap eye; field
## rings on the ground and floating around the shaft; a drone losing its link and tumbling.
static func jammer_obelisk(cv, o: Vector2, f: int) -> void:
	_m_slab(cv, o, 1)
	var rt := K.rot(f)
	var g := K.pt(o, f, 0, 0, 2)
	for k in 3:  # ground field rings
		_ring(cv, g, 14.0 + k * 8.0, 7.0 + k * 4.0, L.CYAN, 0.42 - k * 0.07, "all", 3)
	L.hex_shadow(cv, o, Vector3(0, 0, 0), 0.26, 46.0, 0.0)
	cv.flush_shadow()
	var rings := [[K.pt(o, f, 0, 0, 20), 15.0, 6.0], [K.pt(o, f, 0, 0, 33), 11.0, 4.5]]
	for r in rings:
		_ring(cv, r[0], r[1], r[2], L.CYAN, 0.5, "back")
	var s0: Dictionary = L.hexp(cv, o, Vector3(0, 0, 2), 0.27, 10.0, rt, L.GRAPH, 151)
	for sd in s0.sides:
		L.team_panel(cv, sd.quad, 0.15, 0.3, 0.85, 0.62)
	B.wall_ao(cv, s0, 0.3)
	var s1: Dictionary = L.hexp(cv, o, Vector3(0, 0, 12), 0.2, 15.0, rt, L.PANEL_D, 152)
	for sd in s1.sides:
		var q: PackedVector2Array = sd.quad
		cv.line_v(q[0].lerp(q[1], 0.5).lerp(q[3].lerp(q[2], 0.5), 0.15), q[0].lerp(q[1], 0.5).lerp(q[3].lerp(q[2], 0.5), 0.85), L.CYAN)
		L.seam(cv, q, 0.9)
	var s2: Dictionary = L.hexp(cv, o, Vector3(0, 0, 27), 0.15, 12.0, rt, L.GRAPH, 153)
	for sd in s2.sides:
		L.seam(cv, sd.quad, 0.5)
		L.joints(cv, sd.quad, [0.3, 0.7], L.GRAPH)
	var top: PackedVector2Array = s2.top
	var apex := K.pt(o, f, 0, 0, 47)
	for i in 6:  # pyramid cap
		var a: Vector2 = top[i]
		var b: Vector2 = top[(i + 1) % 6]
		var mid := (a + b) * 0.5 - P.proj(Vector2.ZERO, Vector3(0, 0, 39))
		var n := Vector2(mid.x, mid.y * 2.0).normalized()
		if (a + b).y * 0.5 >= top[0].lerp(top[3], 0.5).y - 0.5:
			cv.poly(PackedVector2Array([a, b, apex]), P.mul(L.PANEL, P.side_shade(n) * 1.05))
	cv.line_v(apex, apex + Vector2(0, 5), L.CYAN)
	L.eye(cv, apex + Vector2(0, 4), true)
	for r in rings:
		_ring(cv, r[0], r[1], r[2], L.CYAN, 0.55, "front")
	# drone losing link: tilted, rotors stopped, static sparks
	var dp := Vector2(cv.w - 13.0, 12.0 + f * 2.0)
	cv.line(int(dp.x) - 4, int(dp.y) - 2, int(dp.x) + 4, int(dp.y) + 2, Color8(48, 50, 48))
	cv.line(int(dp.x) - 4, int(dp.y) - 1, int(dp.x) + 4, int(dp.y) + 3, Color8(70, 72, 70))
	cv.px(int(dp.x) - 5, int(dp.y) - 4, Color8(48, 50, 48))
	cv.px(int(dp.x) + 5, int(dp.y), Color8(48, 50, 48))
	for k in 4:
		_glow(cv, int(dp.x) - 6 + P.hi(k, f, 3, 12), int(dp.y) - 6 + P.hi(k, f, 4, 10), L.CYAN_HOT, 0.55)
	for k in 3:
		cv.px(int(dp.x) - 2 + k, int(dp.y) + 6 + k * 3, Color(0.3, 0.3, 0.3, 0.45))


## m_mass_driver: graphite slab with hex tiling, team-panelled turntable, two banks of glowing capacitor
## columns, breech block and long rail with cyan collars elevated on struts; a slug leaving the muzzle.
static func mass_driver(cv, o: Vector2, f: int) -> void:
	_m_slab(cv, o, 2)
	var ps: Array = [[-0.05, 0, 2, 0.5, 0.5, 6, L.GRAPH, "mhex"], [-0.05, 0, 8, 0.36, 0.36, 4, L.PANEL_D, "hex"]]
	for u in [-0.62, -0.34, -0.06]:
		for v in [-0.72, 0.72]:
			ps.append([u, v, 2, 0.11, 0.11, 14, L.GRAPH_D, "hex"])
	ps.append([0.66, 0.66, 2, 0.14, 0.14, 8, L.GRAPH_D, "coil"])
	_render(cv, o, f, ps, "m")
	for v in [-0.72, 0.72]:  # bus bars from the banks to the turntable
		B.pipe(cv, o, Vector3(K.wp(f, -0.06, v).x, K.wp(f, -0.06, v).y, 10), Vector3(K.wp(f, -0.06, v * 0.45).x, K.wp(f, -0.06, v * 0.45).y, 10), L.PANEL_D)
	var piv := Vector3(-0.1, 0.0, 16.0)
	var el := 0.38
	var yaw := 0.25
	for l in [0.15, 0.5]:  # struts
		var a := K.pt(o, f, -0.1, 0.0, 12)
		cv.line_v(a, _lp(o, f, piv, el, l, yaw, 0.0, -3.0), L.JOINT)
	var br := _tbox(cv, o, f, piv, el, -0.62, -0.25, -0.17, 0.17, -6.0, 6.0, L.PANEL_D, yaw, false, 161)
	for nm in ["left", "right"]:
		if br[nm].vis:
			var q: PackedVector2Array = br[nm].pts
			if nm == "right":
				q = PackedVector2Array([q[0], q[3], q[2], q[1]])
			L.team_panel(cv, q, 0.15, 0.2, 0.85, 0.7)
	if br.top.vis:
		L.seam(cv, br.top.pts, 0.5)
	var rail := _tbox(cv, o, f, piv, el, -0.25, 1.22, -0.12, 0.12, -3.5, 3.5, L.GRAPH, yaw, false, 162)
	if rail.top.vis:
		var q2: PackedVector2Array = rail.top.pts
		cv.poly(P.sub(q2, 0.0, 0.25, 1.0, 0.75), L.PANEL)
		cv.line_v(q2[0].lerp(q2[3], 0.28), q2[1].lerp(q2[2], 0.28), L.JOINT)
		cv.line_v(q2[0].lerp(q2[3], 0.72), q2[1].lerp(q2[2], 0.72), L.JOINT)
		cv.line_v(q2[0].lerp(q2[3], 0.5), q2[1].lerp(q2[2], 0.5), L.CYAN)
	for nm in ["left", "right"]:
		if rail[nm].vis:
			var q3: PackedVector2Array = rail[nm].pts
			if nm == "right":
				q3 = PackedVector2Array([q3[0], q3[3], q3[2], q3[1]])
			L.joints(cv, q3, [0.25, 0.5, 0.75], L.GRAPH)
	for l in [0.05, 0.5, 0.95]:
		var col := _tbox(cv, o, f, piv, el, l, l + 0.05, -0.14, 0.14, -4.5, 4.5, L.PANEL_D, yaw, false, 163)
		for nm in ["left", "right"]:
			if col[nm].vis:
				L.seam(cv, col[nm].pts, 0.5)
	var muz := _lp(o, f, piv, el, 1.23, yaw)
	cv.ellipse(muz.x, muz.y, 2.2, 2.2, L.JOINT)
	cv.px(int(muz.x), int(muz.y), L.CYAN_HOT)
	BD.beacon(cv, o, 0.95, false)
	# slug + streak + shock ring
	var s1 := _lp(o, f, piv, el, 1.32, yaw)
	var s2 := _lp(o, f, piv, el, 1.72, yaw)
	_beam(cv, s1, s2, L.CYAN_HOT, L.CYAN)
	_beam(cv, s1 + Vector2(0, -1), s2 + Vector2(0, -1), L.CYAN_HOT, L.TEAL)
	cv.rect(int(s2.x) - 2, int(s2.y) - 2, 4, 3, L.PANEL)
	cv.px(int(s2.x) - 1, int(s2.y) - 2, L.CYAN_HOT)
	_ring(cv, _lp(o, f, piv, el, 1.27, yaw), 3.0, 5.0, L.CYAN, 0.45)
	_ring(cv, _lp(o, f, piv, el, 1.4, yaw), 4.5, 7.0, L.CYAN, 0.3)


## m_sentry_mine: buried hex disc in disturbed soil, risen: column + seamed head with a big eye and twin
## stub barrels firing cyan bolts; a dormant buried disc beside it (they are laid in fields).
static func sentry_mine(cv, o: Vector2, f: int) -> void:
	var rt := K.rot(f)
	K.gquad(cv, o, f, -0.36, -0.34, 0.36, 0.34, 0, P.mul(EARTH_D, 1.05))
	var c := K.pt(o, f, 0, 0, 0)
	for i in 10:  # displaced soil
		var a := TAU * i / 10.0 + 0.2
		cv.rect(int(c.x + cos(a) * 16.0), int(c.y + sin(a) * 8.0), 2, 1, EARTH if i % 2 else Color8(110, 94, 66))
	var dorm := K.wp(f, -0.32, -0.28)
	var dd: Dictionary = L.hexp(cv, o, Vector3(dorm.x, dorm.y, 0), 0.11, 1.5, rt, L.GRAPH_D, 171)
	cv.px(int((dd.top[0].x + dd.top[3].x) * 0.5), int((dd.top[0].y + dd.top[3].y) * 0.5), L.TEAL)
	L.hex_shadow(cv, o, Vector3(0, 0, 0), 0.2, 14.0, 0.0)
	cv.flush_shadow()
	var disc: Dictionary = L.hexp(cv, o, Vector3(0, 0, 0), 0.3, 3.0, rt, L.GRAPH, 172)
	var t: PackedVector2Array = disc.top
	var tc := (t[0] + t[3]) * 0.5
	for sd in disc.sides:
		L.seam(cv, sd.quad, 0.5)
	cv.team = true
	for i in [0, 2, 4]:
		cv.poly(PackedVector2Array([t[i].lerp(tc, 0.15), t[(i + 1) % 6].lerp(tc, 0.15), t[(i + 1) % 6].lerp(tc, 0.45), t[i].lerp(tc, 0.45)]), Color(0.74, 0.74, 0.74))
	cv.team = false
	var col: Dictionary = L.hexp(cv, o, Vector3(0, 0, 3), 0.09, 6.0, rt, L.JOINT, 173)
	for sd in col.sides:
		L.seam(cv, sd.quad, 0.4)
	var hd: Dictionary = L.hexp(cv, o, Vector3(0, 0, 9), 0.17, 6.0, rt, L.PANEL, 174)
	for sd in hd.sides:
		L.seam(cv, sd.quad, 0.3)
	L.rims(cv, hd, L.PANEL)
	var piv := Vector3(0.0, 0.0, 12.0)
	var tips: Array = []
	for sv in [-0.06, 0.06]:
		tips.append(_rod(cv, o, f, piv, 0.06, 0.08, 0.3, 2, L.GRAPH_D, YAW, sv))
	L.eye(cv, _lp(o, f, piv, 0.0, 0.1, YAW, 0.0, 1.0) + Vector2(0, -2), true)
	for tp in tips:
		cv.px(int(tp.x), int(tp.y), L.CYAN_HOT)
		var far: Vector2 = tp + (_lp(o, f, piv, 0.06, 0.7) - _lp(o, f, piv, 0.06, 0.3))
		_gline(cv, tp + (far - tp) * 0.2, tp + (far - tp) * 0.55, L.CYAN_HOT, 0.58)
		_gline(cv, tp + (far - tp) * 0.7, far, L.CYAN, 0.5)
