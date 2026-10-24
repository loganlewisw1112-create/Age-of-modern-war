extends RefCounted
## G4 fort art helpers (agent ART-F, CONTRACTS_G4 s6): geometry shared by the three faction drawers
## (g4_fort_a/_b/_m.gd). A fort cell is drawn as a core (post / gate / tower) at the cell centre plus
## one "arm" per connected neighbour, running from the core to the cell edge. Every arm of a faction has
## the same cross-section (half-thickness F.T, height F.H) and ends exactly on the shared cell edge, so
## neighbouring sprites meet without a seam; the outline pass skips the connecting cut planes.
## Deterministic: integer hashes only (P.hn / P.hi), no RNG.
const P = preload("res://tools/art/pix.gd")
const FX = preload("res://tools/art/fx_ui.gd")
const G = preload("res://tools/art/g3b_lib.gd")
const L = preload("res://tools/art/faction_m_lib.gd")

## N E S W = conn bits 1 2 4 8 (sim/systems/fortify.gd DIRS). Local tile coords, cell centre = (0, 0).
const DIRS := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
const POLE := Color8(140, 116, 78)
const REBAR := Color8(84, 62, 46)


## Variant flags handed to the faction drawers: hk = height factor (1 = finished), raw = under
## construction (bare material, no dressing), open = gate open.
static func vf(hk := 1.0, raw := false, open := false) -> Dictionary:
	return {"hk": hk, "raw": raw, "open": open}


## Gate run axis from the conn mask: 0 = along world x (E-W run), 1 = along world y (N-S run).
static func gate_axis(mask: int) -> int:
	if (mask & 10) != 0 or (mask & 5) == 0:
		return 0
	return 1


## [centre (z = z0), hx, hy] of the box spanning s0..s1 from the cell centre along DIRS[i].
static func arm_dims(i: int, s0: float, s1: float, t: float, z0: float) -> Array:
	var d: Vector2 = DIRS[i]
	var m := (s0 + s1) * 0.5
	var hl := (s1 - s0) * 0.5
	var along_x := absf(d.x) > 0.5
	return [Vector3(d.x * m, d.y * m, z0), hl if along_x else t, t if along_x else hl]


static func arm_box(cv, o: Vector2, i: int, s0: float, s1: float, t: float, z0: float, hz: float,
		col: Color, tex := 0.08, s := 1) -> Dictionary:
	var a := arm_dims(i, s0, s1, t, z0)
	return P.box(cv, o, a[0], a[1], a[2], hz, 0.0, col, tex, s)


## World point at distance `s` along DIRS[i], pushed `off` tiles toward the arm's visible long face
## (+y for x-running arms, +x for y-running arms).
static func on_face(i: int, s: float, off: float) -> Vector2:
	var d: Vector2 = DIRS[i]
	var p := Vector2(0, 1) if absf(d.x) > 0.5 else Vector2(1, 0)
	return d * s + p * off


## Quad on the visible long face of an arm, s0..s1 along DIRS[i], z from zb to zt.
static func face_quad(o: Vector2, i: int, s0: float, s1: float, t: float, zb: float, zt: float) -> PackedVector2Array:
	var a := on_face(i, s0, t)
	var b := on_face(i, s1, t)
	return PackedVector2Array([P.proj(o, Vector3(a.x, a.y, zb)), P.proj(o, Vector3(b.x, b.y, zb)),
		P.proj(o, Vector3(b.x, b.y, zt)), P.proj(o, Vector3(a.x, a.y, zt))])


static func face_band(cv, o: Vector2, i: int, s0: float, s1: float, t: float, zb: float, zt: float,
		col: Color, team := false) -> void:
	cv.team = team
	cv.poly(face_quad(o, i, s0, s1, t, zb, zt), col)
	cv.team = false


## Vertical joint line on the visible face plus across the top, at distance s along DIRS[i].
static func joint(cv, o: Vector2, i: int, s: float, t: float, z0: float, hz: float, col: Color) -> void:
	var f := on_face(i, s, t)
	var b := on_face(i, s, -t)
	cv.line_v(P.proj(o, Vector3(f.x, f.y, z0)), P.proj(o, Vector3(f.x, f.y, z0 + hz)), col)
	cv.line_v(P.proj(o, Vector3(f.x, f.y, z0 + hz)), P.proj(o, Vector3(b.x, b.y, z0 + hz)), col)


## Full built look of one fort cell: shadows, back arms, core, front arms, optional damage, then the
## seam-safe outline. F = faction drawer script, kind = "wall" | "gate" | "tower".
static func built(cv, o: Vector2, F, kind: String, mask: int, open: bool, dmg: bool, seed: int) -> void:
	var v := vf(1.0, false, open)
	var core: float = F.core_half(kind)
	var ax := gate_axis(mask)
	var items: Array = []
	for i in 4:
		if (mask & (1 << i)) == 0:
			continue
		var s0 := core
		if kind == "gate":
			s0 = F.GATE_OUT if (i % 2 == 1) == (ax == 0) else 0.06
		var d: Vector2 = DIRS[i]
		items.append([(d.x + d.y) * 0.3, i, s0])
	items.append([0.0, -1, 0.0])
	items.sort_custom(func(a, b): return a[0] < b[0])
	for it in items:
		if int(it[1]) >= 0:
			var a := arm_dims(int(it[1]), float(it[2]), 0.5, F.T, 0.0)
			P.box_shadow(cv, o, a[0], a[1], a[2], F.H, 0.0)
		else:
			var hx: float = core if kind != "gate" or ax == 0 else 0.1
			var hy: float = core if kind != "gate" or ax == 1 else 0.1
			P.box_shadow(cv, o, Vector3(0, 0, 0), hx, hy, F.core_h(kind), 0.0)
	cv.flush_shadow()
	for it in items:
		if int(it[1]) >= 0:
			F.arm(cv, o, int(it[1]), float(it[2]), v)
		else:
			F.core(cv, o, kind, mask, v)
	if dmg:
		damage(cv, o, seed)
	outline_ex(cv, o, mask, F.T + 0.05, F.H + 4.0)


## Construction stage st (0..2) of a fort cell: footing slab + rebar, core at 0 / 45 / 85 % height in
## raw material, scaffold (Human) or holographic lattice (Machine), team stake.
static func stage(cv, o: Vector2, F, kind: String, st: int) -> void:
	var hk: float = [0.0, 0.45, 0.85][st]
	var half: float = F.core_half(kind) + 0.06
	var ch: float = F.core_h(kind)
	if hk > 0.0:
		P.box_shadow(cv, o, Vector3(0, 0, 2), half - 0.06, half - 0.06, ch * hk, 0.0)
	cv.flush_shadow()
	var slab: Dictionary = P.box(cv, o, Vector3(0, 0, 0), half, half, 2.0, 0.0, P.mul(F.SLAB, 0.9), 0.12, 5)
	for k in 8 + st * 3:
		var q := P.sub(slab.top, P.hn(k, st, 41), P.hn(k, st, 42), P.hn(k, st, 41) + 0.02, P.hn(k, st, 42) + 0.02)
		cv.px(int(q[0].x), int(q[0].y), REBAR)
		cv.px(int(q[0].x), int(q[0].y) - 1, P.mul(REBAR, 1.2))
	if hk > 0.0:
		F.core(cv, o, kind, 0, vf(hk, true, false))
	if st > 0:
		if F.HOLO:
			L.holo_box(cv, o, Vector3(0, 0, 2), half, half, ch, 0.45 + 0.15 * st)
		else:
			_scaffold(cv, o, half, ch * minf(1.0, hk + 0.15))
	var base := P.proj(o, Vector3(-half + 0.06, half - 0.06, 2))
	cv.line(int(base.x), int(base.y), int(base.x), int(base.y) - 12, Color8(60, 60, 56))
	cv.team = true
	for yy in 4:
		for xx in 5:
			cv.px(int(base.x) + 1 + xx, int(base.y) - 12 + yy, Color(0.85, 0.85, 0.85) if yy > 0 else Color(1, 1, 1))
	cv.team = false
	cv.outline(P.OUTLINE)


static func _scaffold(cv, o: Vector2, half: float, hz: float) -> void:
	var cs := [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]
	for c in cs:
		var cc: Vector2 = c
		if cc.x + cc.y < -0.5:
			continue  # back pole hidden behind the core
		cv.line_v(P.proj(o, Vector3(cc.x, cc.y, 2)), P.proj(o, Vector3(cc.x, cc.y, 2 + hz)), POLE)
	for z in [hz * 0.45, hz * 0.9]:
		for k in [[1, 2], [2, 3]]:
			var a: Vector2 = cs[k[0]]
			var b: Vector2 = cs[k[1]]
			cv.line_v(P.proj(o, Vector3(a.x, a.y, 2 + z)), P.proj(o, Vector3(b.x, b.y, 2 + z)), P.mul(POLE, 0.85))


## Battle damage near the core only (never on the connecting edges): scorch, cracks, chipped top,
## flickering field bands (translucent cyan pixels), rubble at the foot.
static func damage(cv, o: Vector2, seed: int) -> void:
	for k in 3:
		var cx := o.x + (P.hn(k, seed, 1) - 0.5) * 18.0
		var cy := o.y - 4.0 - P.hn(k, seed, 2) * 22.0
		var rx := 3.5 + P.hn(k, seed, 3) * 3.5
		for y in range(int(cy - rx), int(cy + rx) + 1):
			for x in range(int(cx - rx), int(cx + rx) + 1):
				var dx := (x - cx) / rx
				var dy := (y - cy) / (rx * 0.7)
				var c: Color = cv.get_px(x, y)
				if dx * dx + dy * dy <= 1.0 and c.a > 0.6:
					cv.img.set_pixel(x, y, P.mul(c, 0.5 + 0.2 * P.hn(x, y, seed)))
	for k in 2:
		var x := int(o.x + (P.hn(k, seed, 5) - 0.5) * 16.0)
		var y := int(o.y - 6.0 - P.hn(k, seed, 6) * 16.0)
		for s in 7:
			var c: Color = cv.get_px(x, y)
			if c.a > 0.6:
				cv.img.set_pixel(x, y, P.mul(c, 0.35))
			x += P.hi(k * 7 + s, seed, 7, 3) - 1
			y += 1 if P.hn(k * 7 + s, seed, 8) > 0.3 else -1
	for k in 6:
		var x := int(o.x + (P.hn(k, seed, 9) - 0.5) * 20.0)
		for y in cv.h:
			if cv.get_px(x, y).a > 0.6:
				for d in 1 + P.hi(k, seed, 10, 3):
					cv.img.set_pixel(x, y + d, Color(0, 0, 0, 0))
					cv.mask.set_pixel(x, y + d, Color(0, 0, 0, 0))
				break
	for y in cv.h:
		if P.hn(y, seed, 11) < 0.3:
			for x in cv.w:
				var c: Color = cv.get_px(x, y)
				if c.a > 0.05 and c.a < 0.6 and c.b > 0.5 and absf(x - o.x) < 13.0:
					cv.img.set_pixel(x, y, Color(0, 0, 0, 0))
	for k in 7:
		var p := P.proj(o, Vector3((P.hn(k, seed, 12) - 0.3) * 0.7, (P.hn(k, seed, 13) - 0.3) * 0.7, 0))
		cv.rect(int(p.x), int(p.y), 2, 1, Color8(96, 92, 84) if k % 2 == 0 else Color8(70, 66, 60))


## P.Canvas.outline, except no outline is added within 1 px of a connected cut plane (the shared cell
## edge cross-section of half-width `t`, height `hmax`): the neighbour sprite continues the wall there.
static func outline_ex(cv, o: Vector2, mask: int, t: float, hmax: float) -> void:
	var ex = P.Canvas.new(cv.w, cv.h)
	for i in 4:
		if (mask & (1 << i)) == 0:
			continue
		var d: Vector2 = DIRS[i]
		var p := Vector2(-d.y, d.x)
		var a := d * 0.5 + p * t
		var b := d * 0.5 - p * t
		ex.poly(PackedVector2Array([P.proj(o, Vector3(a.x, a.y, -2)), P.proj(o, Vector3(b.x, b.y, -2)),
			P.proj(o, Vector3(b.x, b.y, hmax)), P.proj(o, Vector3(a.x, a.y, hmax))]), Color.BLACK, Callable(), true)
	var src: Image = cv.img.duplicate()
	var nb := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in cv.h:
		for x in cv.w:
			if src.get_pixel(x, y).a >= 0.6:
				continue
			var hit := false
			var near: bool = ex.sh.get_pixel(x, y).a > 0.5
			for dd in nb:
				var q: Vector2i = dd
				var xx: int = x + q.x
				var yy: int = y + q.y
				if xx < 0 or yy < 0 or xx >= cv.w or yy >= cv.h:
					continue
				if src.get_pixel(xx, yy).a >= 0.6:
					hit = true
				if ex.sh.get_pixel(xx, yy).a > 0.5:
					near = true
			if hit and not near:
				cv.img.set_pixel(x, y, src.get_pixel(x, y).blend(P.OUTLINE))
				cv.mask.set_pixel(x, y, Color(0, 0, 0, 0))


## 32x32 build-button icon from a state image (fx_ui panel + faction accent strip, team-tinted).
static func icon(out: Dictionary, id: String, file: String, mask: String, accent: String) -> String:
	var im := G.panel(accent)
	FX._fit(im, FX.tint(out.images[file], out.images[mask], FX.ICON_TEAM), 29)
	var path := "icons/%s.png" % id
	out.images[path] = im
	return path
