extends RefCounted
## G6 sea + air proposals (agent art-seaair), built only from the game's own art libraries.
##   Ships  vehicle sheets (8 facings): convex hull prisms shaded exactly like pix.gd P.box (side_shade +
##          speckle), superstructure from P.box / faction_m_lib hex prisms, hull colours from g5_bld_sea
##          (HULL_A grey, HULL_B rust-brown, Machine graphite + cyan seams). Water interaction (darker halo,
##          wake, waterline foam, bow spray) is translucent and only paints outside the hull.
##   Aircraft  g5_air_mesh models rasterised by g5_air_raster (the G5 aircraft pipeline, faction palettes
##          and surface styles from g5_air_parts) inside a veh_sheet; SHOW adds alt + shadow.
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const VH = preload("res://tools/art/vehicles.gd")
const V = preload("res://tools/art/faction_b_veh.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")
const ML = preload("res://tools/art/faction_m_lib.gd")
const MS = preload("res://tools/art/g5_air_mesh.gd")
const R = preload("res://tools/art/g5_air_raster.gd")
const AP = preload("res://tools/art/g5_air_parts.gd")
const SH = preload("res://tools/art/g5_air_sheet.gd")

const OUTL := Color(0.09, 0.09, 0.07, 1)
const OUTL_M := Color(0.04, 0.05, 0.07, 1)
const HULL_A := Color8(118, 126, 132)   # g5_bld_sea.HULL_A
const HULL_B := Color8(124, 80, 54)     # g5_bld_sea.HULL_B
const DECK_A := Color8(84, 90, 92)
const SUP_A := Color8(132, 136, 126)
const DECK_B := Color8(98, 86, 64)
const BOOT := Color8(128, 48, 40)
const GLASS := Color8(38, 62, 80)
const SAND := Color8(150, 134, 98)
const RUBBER := Color8(46, 46, 44)
const FOAM := Color(0.9, 0.95, 0.96, 0.75)
const WAKE := Color(0.9, 0.95, 0.97, 0.5)
const DEEPW := Color(0.02, 0.06, 0.1, 0.28)
const OIL := Color(0.05, 0.05, 0.06, 0.5)
const SPRAY := Color(0.93, 0.96, 0.97)
const SMOKE := Color(0.3, 0.29, 0.27)
const ORANGE := Color8(214, 112, 40)
const MINE := Color8(54, 52, 46)
const WAKE_LEN := 0.24

const SHIP_FR := ["idle", "move", "fire"]
const AIR_FR := ["idle", "move", "fire", "idle_b", "move_b", "landing", "parked"]

const SHOW := {
	"a_supply_ship_a": {"row": 0, "frame": "work", "ground": "water"},
	"b_supply_ship_b": {"row": 0, "frame": "move", "ground": "water"},
	"m_charge_tender": {"row": 0, "frame": "work", "ground": "water"},
	"a_minesweeper": {"row": 0, "frame": "sweep", "ground": "water"},
	"b_mine_barge": {"row": 0, "frame": "lay", "ground": "water"},
	"a_hovercraft": {"row": 0, "frame": "loaded", "ground": "water|beach"},
	"b_aa_barge": {"row": 0, "frame": "fire", "ground": "water"},
	"m_lance_cruiser": {"row": 0, "frame": "fire", "ground": "deep"},
	"a_carrier": {"row": 0, "frame": "launch", "ground": "deep"},
	"a_submarine": {"row": 0, "frame": "move", "ground": "deep"},
	"b_recon_plane": {"row": 0, "frame": "move", "ground": "grass", "alt": 26, "shadow": [13, 5]},
	"a_awacs": {"row": 0, "frame": "fire", "ground": "grass", "alt": 26, "shadow": [22, 9]},
	"a_airlift": {"row": 3, "frame": "drop", "ground": "grass", "alt": 26, "shadow": [22, 9]},
	"m_stealth_drone": {"row": 0, "frame": "fire", "ground": "grass", "alt": 26, "shadow": [14, 6]},
}


static func build(out: Dictionary) -> void:
	_ship(out, "a_supply_ship_a", ["idle", "move", "fire", "work"], supply_a)
	_ship(out, "b_supply_ship_b", ["idle", "move", "fire", "work"], tender_b)
	_ship(out, "m_charge_tender", ["idle", "move", "fire", "work"], charge_m)
	_ship(out, "a_minesweeper", ["idle", "move", "fire", "sweep"], sweeper)
	_ship(out, "b_mine_barge", ["idle", "move", "fire", "lay"], mine_barge)
	_ship(out, "a_hovercraft", ["idle", "move", "fire", "loaded", "unload"], hovercraft)
	_ship(out, "b_aa_barge", SHIP_FR, aa_barge)
	_ship(out, "m_lance_cruiser", SHIP_FR, lance)
	_ship(out, "a_carrier", ["idle", "move", "fire", "launch"], carrier)
	_ship(out, "a_submarine", ["idle", "move", "fire", "dive"], submarine)
	_air(out, "b_recon_plane", m_recon, {"style": "b", "pal": AP.PAL_B, "zc": 9.0, "shadow_r": 10.0, "break_x": -8.0}, AIR_FR)
	_air(out, "a_awacs", m_awacs, {"style": "a", "pal": AP.PAL_A, "zc": 9.0, "shadow_r": 16.0, "break_x": -14.0}, AIR_FR, _awacs_scan)
	_air(out, "a_airlift", m_airlift, {"style": "a", "pal": AP.PAL_A, "zc": 10.0, "shadow_r": 16.0, "break_x": -13.0},
		["idle", "move", "fire", "idle_b", "move_b", "landing", "parked", "drop"])
	_air(out, "m_stealth_drone", m_stealth, {"style": "m", "pal": AP.PAL_M, "zc": 7.0, "shadow_r": 11.0, "break_x": -6.0}, AIR_FR)


# ================================================================ sheet plumbing
## Ship sheet: frame size + pivot fitted to every facing x frame + wreck (2 px margin).
static func _ship(out: Dictionary, id: String, frames: Array, draw: Callable) -> void:
	var dr := func(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
		draw.call(cv, rot, String(frames[f]), wreck, o)
	var W := 230
	var HH := 180
	var o := Vector2(115, 100)
	var box := Rect2i()
	var first := true
	for k in 8:
		for f in frames.size():  # live frames only; the wreck is drawn to stay inside this box
			var cv = P.Canvas.new(W, HH)
			dr.call(cv, k * PI / 4.0, f, false, o)
			var img: Image = cv.img
			var u: Rect2i = img.get_used_rect()
			if u.size.x == 0:
				continue
			box = u if first else box.merge(u)
			first = false
	var mg := 2
	var sp := {"fw": box.size.x + mg * 2, "fh": box.size.y + mg * 2,
		"pivot": [int(o.x) - box.position.x + mg, int(o.y) - box.position.y + mg]}
	SL.veh_sheet(out, id, sp, dr, frames, {"naval": true})


## Aircraft sheet through the G5 aircraft rasteriser. Frames outside the jet set are "special" (st.f).
static func _air(out: Dictionary, id: String, model: Callable, look: Dictionary, frames: Array, post := Callable()) -> void:
	var jet: Array = SH.FRAMES["jet"]
	var specials: Array = []
	for fn: String in frames:
		if not jet.has(fn):
			specials.append(fn)
	var fitm := func(m, st: Dictionary) -> void:
		model.call(m, st)
		for sf: String in specials:
			var s2: Dictionary = st.duplicate()
			s2["f"] = sf
			model.call(m, s2)
	var sp: Dictionary = SH.fit(fitm, look, "jet")
	sp["fw"] = int(sp["fw"]) + 8
	sp["fh"] = int(sp["fh"]) + 8
	sp["pivot"] = [int(sp["pivot"][0]) + 4, int(sp["pivot"][1]) + 4]
	var gf: Array = []
	for fn: String in frames:
		if SH.GROUND.has(fn):
			gf.append(fn)
	var ex := {"air": true, "altitude": SH.ALT["jet"], "bob": 1, "aircraft": "jet", "ground_frames": gf, "anim_fps": 10,
		"anim": {"air": ["idle", "idle_b"], "move": ["move", "move_b"]}, "alt_scale": {"landing": 0.35},
		"shadow": SH._blob(out, id, float(look.get("shadow_r", 8.0)))}
	SL.veh_sheet(out, id, sp, func(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
		if wreck:
			SH._wreck(cv, o, rot, model, look, "jet")
			return
		var fn: String = frames[f]
		var st: Dictionary = SH.state("jet", fn if jet.has(fn) else "idle")
		st["f"] = fn
		var m = SH._mesh(model, st, look)
		R.render(cv, o, rot, m, {"style": look.style, "pal": look.pal, "ground": st.ground, "seed": int(rot * 100.0)})
		if post.is_valid():
			post.call(cv, o, rot, fn), frames, ex)


# ================================================================ ship helpers
## Convex prism from a CCW local outline pts (fwd, right in tiles: stern-left -> bow -> stern-right), centre
## c (world tiles, z = bottom px), height hz px. Shaded exactly like P.box. Returns {top, sides:[{quad, n, nl}]}.
static func prism(cv, o: Vector2, c: Vector3, pts: Array, hz: float, rot: float, col: Color, tex := 0.07,
		s := 1, top_col = null) -> Dictionary:
	var gb: Array = []
	var gt: Array = []
	for l: Vector2 in pts:
		var p3 := Vector3(c.x, c.y, 0) + D.w(rot, l.x, l.y)
		gb.append(P.proj(o, Vector3(p3.x, p3.y, c.z)))
		gt.append(P.proj(o, Vector3(p3.x, p3.y, c.z + hz)))
	var res := {"sides": [], "top": PackedVector2Array(gt)}
	var n := pts.size()
	for i in n:
		var j := (i + 1) % n
		var e: Vector2 = pts[j] - pts[i]
		var nl := Vector2(e.y, -e.x).normalized()
		var n3 := D.w(rot, nl.x, nl.y)
		var nw := Vector2(n3.x, n3.y)
		if nw.x + nw.y <= 0.001 or hz <= 0.0:
			continue
		var q := PackedVector2Array([gb[i], gb[j], gt[j], gt[i]])
		cv.poly(q, P.mul(col, P.side_shade(nw)), P.speckle(tex, s + i))
		res.sides.append({"quad": q, "n": nw, "nl": nl})
	var tc: Color = col if top_col == null else top_col
	cv.poly(res.top, tc, P.speckle(tex, s + 17))
	return res


## Ship hull outline: half length hl, half beam hw, bow taper length bow, stern width fraction st.
static func hull_pts(hl: float, hw: float, bow: float, st := 0.82, sh := 0.06) -> Array:
	return [Vector2(-hl, -hw * st), Vector2(-hl + sh, -hw), Vector2(hl - bow, -hw), Vector2(hl - bow * 0.4, -hw * 0.66),
		Vector2(hl, 0), Vector2(hl - bow * 0.4, hw * 0.66), Vector2(hl - bow, hw), Vector2(-hl + sh, hw), Vector2(-hl, hw * st)]


## Rounded rectangle (hovercraft skirt, barges with chamfered corners), CCW like hull_pts.
static func rrect(hl: float, hw: float, c: float) -> Array:
	return [Vector2(-hl, -hw + c), Vector2(-hl + c, -hw), Vector2(hl - c, -hw), Vector2(hl, -hw + c),
		Vector2(hl, hw - c), Vector2(hl - c, hw), Vector2(-hl + c, hw), Vector2(-hl, hw - c)]


static func bx(cv, o: Vector2, rot: float, f: float, r: float, z: float, hx: float, hy: float, hz: float, col: Color,
		s: int, top = null) -> Dictionary:
	return P.box(cv, o, D.w(rot, f, r, z), hx, hy, hz, rot, col, 0.06, s, top)


static func _dep(rot: float, f: float, r: float) -> float:
	var v := D.w(rot, f, r)
	return v.x + v.y


## Draw deck items far-to-near. items: [[fwd, right, Callable], ...].
static func _paint(rot: float, items: Array) -> void:
	items.sort_custom(func(a: Array, b: Array) -> bool: return _dep(rot, a[0], a[1]) < _dep(rot, b[0], b[1]))
	for it: Array in items:
		(it[2] as Callable).call()


## Screen direction of the local forward axis.
static func _fdir(o: Vector2, rot: float) -> Vector2:
	return (D.sp(o, rot, 1.0, 0.0, 0.0) - D.sp(o, rot, 0.0, 0.0, 0.0)).normalized()


## Water pixel: only where nothing solid is drawn yet (outside the hull and its outline).
static func _wp(cv, x: int, y: int, c: Color) -> void:
	var b: Color = cv.get_px(x, y)
	if b.a < 0.6:
		cv.px(x, y, c)


static func _outside(cv) -> Callable:
	return func(x: int, y: int, c: Color) -> Color:
		var b: Color = cv.get_px(x, y)
		return c if b.a < 0.6 else Color(0, 0, 0, 0)


## Water interaction around a hull (after outline): darker halo, idle ripples or a V wake behind the stern.
static func _water(cv, o: Vector2, rot: float, pts: Array, off: Vector2, hl: float, hw: float, moving: bool, s: int,
		wl := WAKE_LEN) -> void:
	var halo := PackedVector2Array()
	for l: Vector2 in pts:
		halo.append(D.sp(o, rot, off.x + l.x * 1.07, off.y + l.y * 1.45, 0))
	cv.poly(halo, DEEPW, _outside(cv))
	if moving:
		var n := 22
		for i in n:
			var t := float(i) / n
			var fw := off.x - hl + 0.02 - t * wl
			var spread := hw * (0.8 + t * 1.9)
			var a := 0.75 * (1.0 - t * 0.8)
			for sg: float in [-1.0, 1.0]:
				var p := D.sp(o, rot, fw, off.y + spread * sg, 0)
				_wp(cv, int(p.x), int(p.y), Color(WAKE.r, WAKE.g, WAKE.b, a))
				_wp(cv, int(p.x) + 1, int(p.y), Color(WAKE.r, WAKE.g, WAKE.b, a * 0.5))
			if P.hn(i, s, 51) > 0.25:
				var c := D.sp(o, rot, fw, off.y + (P.hn(i, s, 52) - 0.5) * hw * (0.8 + t), 0)
				var rr := 1.8 - t
				for yy in range(int(c.y - 1), int(c.y + 2)):
					for xx in range(int(c.x - rr), int(c.x + rr) + 1):
						if P.hn(xx, yy, s + 3) > 0.35:
							_wp(cv, xx, yy, Color(WAKE.r, WAKE.g, WAKE.b, 0.42 * (1.0 - t)))
		# bow waves peeling off both sides
		for i in 8:
			var t := float(i) / 8.0
			for sg: float in [-1.0, 1.0]:
				var p := D.sp(o, rot, off.x + hl - 0.04 - t * hl * 0.9, off.y + sg * (hw * 0.9 + t * hw * 0.9), 0)
				_wp(cv, int(p.x), int(p.y), Color(WAKE.r, WAKE.g, WAKE.b, 0.5 * (1.0 - t)))
	else:
		for i in 14:
			var a := i * TAU / 14.0 + P.hn(i, s, 61) * 0.3
			var p := D.sp(o, rot, off.x + cos(a) * hl * 1.12, off.y + sin(a) * hw * 1.9, 0)
			var al := 0.3 + 0.15 * P.hn(i, s, 62)
			_wp(cv, int(p.x), int(p.y), Color(WAKE.r, WAKE.g, WAKE.b, al))
			_wp(cv, int(p.x) + 1, int(p.y), Color(WAKE.r, WAKE.g, WAKE.b, al * 0.6))


## Waterline foam along the bottom of the visible hull sides (over the outline row).
static func _foam(cv, r: Dictionary) -> void:
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		cv.line_v(q[0] + Vector2(0, 1), q[1] + Vector2(0, 1), FOAM)


static func _spray(cv, o: Vector2, rot: float, off: Vector2, hl: float, s: int, big := 1.0) -> void:
	var p := D.sp(o, rot, off.x + hl, off.y, 2)
	L.puff(cv, p + Vector2(0, -1), 2.2 * big, 0.55, SPRAY)
	for i in 5:
		var q := p + Vector2((P.hn(i, s, 71) - 0.5) * 7.0 * big, -1.0 - P.hn(i, s, 72) * 4.0 * big)
		cv.px(int(q.x), int(q.y), Color(SPRAY.r, SPRAY.g, SPRAY.b, 0.8))


## Faction dressing of the hull sides: boot topping, deck-edge light, A hull-number team plate, B rivets +
## rust streaks + primer patch, Machine cyan seam + team panel.
static func _hull_sides(cv, r: Dictionary, fk: String, col: Color, s: int, boot := true) -> void:
	var i := 0
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		var nl: Vector2 = sd.nl
		var long := absf(nl.x) < 0.3
		if boot:
			cv.poly(P.sub(q, 0, 0, 1, 0.2), P.mul(BOOT if fk != "m" else ML.GRAPH_D, P.side_shade(sd.n)))
		cv.line_v(q[3], q[2], P.mul(col, 1.24))
		match fk:
			"a":
				if long:
					cv.team = true
					cv.poly(P.sub(q, 0.72, 0.45, 0.84, 0.8), Color(0.62, 0.62, 0.62) * P.side_shade(sd.n))
					cv.team = false
			"b":
				V.rivets(cv, q, 0.82, 10 if long else 3, col)
				V.streaks(cv, q, s + i * 7)
				if long:
					V.patch(cv, q, 0.3 + 0.2 * P.hn(i, s, 3), 0.35, 0.45 + 0.2 * P.hn(i, s, 3), 0.7, V.PRIMER, s + i)
			"m":
				ML.seam(cv, q, 0.55)
				if long:
					ML.team_panel(cv, q, 0.66, 0.62, 0.8, 0.88, 0.66 * P.side_shade(sd.n))
		i += 1


static func _band(cv, r: Dictionary, v0: float, v1: float, lum := 0.64) -> void:
	cv.team = true
	for sd in r.sides:
		cv.poly(P.sub(sd.quad, 0.0, v0, 1.0, v1), Color(lum, lum, lum) * P.side_shade(sd.n))
	cv.team = false


static func _windows(cv, r: Dictionary, v0: float, v1: float, n: int, wreck := false) -> void:
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		cv.poly(P.sub(q, 0.08, v0, 0.92, v1), GLASS if not wreck else D.DARK)
		if wreck:
			continue
		for i in n:
			var u := 0.08 + (i + 0.5) / n * 0.84
			var p: Vector2 = P.sub(q, u, v1, u, v1)[0]
			cv.px(int(p.x), int(p.y) + 1, D.VISION)


static func _mast(cv, o: Vector2, rot: float, f: float, r: float, z: float, h: float, wreck: bool, radar := true) -> void:
	var b := D.sp(o, rot, f, r, z)
	var hh := h if not wreck else h * 0.35
	var t := b + Vector2(0, -hh)
	cv.line_v(b, t, Color8(60, 64, 66))
	cv.line_v(b + Vector2(1, 0), t + Vector2(1, 0), Color8(40, 42, 44))
	if wreck:
		return
	var ya := D.sp(o, rot, f, r - 0.07, z + hh * 0.7)
	var yb := D.sp(o, rot, f, r + 0.07, z + hh * 0.7)
	cv.line_v(ya, yb, Color8(52, 56, 58))
	if radar:
		var ra := D.sp(o, rot, f + 0.03, r - 0.06, z + hh)
		var rb := D.sp(o, rot, f - 0.03, r + 0.06, z + hh)
		cv.line_v(ra, rb, Color8(92, 96, 98))
		cv.line_v(ra + Vector2(0, 1), rb + Vector2(0, 1), Color8(50, 54, 56))
	cv.px(int(t.x), int(t.y) - 1, Color8(150, 150, 140))


static func _tracer(cv, a: Vector2, dir: Vector2, ln: float) -> void:
	L.flash(cv, a, 0.7)
	cv.line_v(a + dir * 3.0, a + dir * (3.0 + ln), Color(1.0, 0.88, 0.45, 0.85))


## Sagging transfer hose from a deck point out over the side (resupply "work" frames).
static func _hose(cv, o: Vector2, rot: float, f: float, z: float, side: float, col: Color) -> void:
	var a := D.w(rot, f, side * 0.16, z)
	var b := D.w(rot, f - 0.08, side * 0.7, 3.0)
	var prev := P.proj(o, a)
	for i in range(1, 13):
		var t := i / 12.0
		var p3 := a.lerp(b, t)
		p3.z -= sin(t * PI) * 5.0
		var p := P.proj(o, p3)
		cv.line_v(prev, p, col)
		cv.line_v(prev + Vector2(0, -1), p + Vector2(0, -1), P.mul(col, 1.5))
		prev = p
	cv.rect(int(prev.x) - 1, int(prev.y) - 1, 3, 2, Color8(200, 168, 60))


## Generic sunk wreck: low scorched hull, broken stubs, oil slick, fire and smoke.
static func _wreck(cv, o: Vector2, rot: float, pts: Array, hz: float, col: Color, hl: float, hw: float, s: int,
		stubs: Array, outl := OUTL) -> void:
	var r := prism(cv, o, Vector3.ZERO, pts, hz * 0.45, rot, P.mul(col, 0.62), 0.1, s, P.mul(VH.BURNT, 0.95))
	V.scorch(cv, r.top)
	for sd in r.sides:
		V.scorch(cv, P.sub(sd.quad, 0.0, 0.5, 1.0, 1.0))
	for st: Array in stubs:
		var b := bx(cv, o, rot, st[0], st[1], hz * 0.45, st[2], st[3], st[4], VH.BURNT, s + 5)
		V.scorch(cv, b.top)
	cv.outline(outl)
	var slick := PackedVector2Array()
	for l: Vector2 in pts:
		slick.append(D.sp(o, rot, l.x * 1.08 - 0.03, l.y * 1.55, 0))
	cv.poly(slick, OIL, _outside(cv))
	_foam(cv, r)
	var c := D.sp(o, rot, 0.0, 0.0, hz * 0.45 + 2)
	V.soot(cv, c, 6.0, s + 9)
	L.flame(cv, c + Vector2(-2, 0), Vector2(0.15, -1.0), 5.0, s)
	for i in 3:
		L.puff(cv, c + Vector2(i * 2.0, -3.0 - i * 3.0), 2.2 + i * 0.6, 0.55 - i * 0.12, SMOKE)


# ================================================================ a_supply_ship_a
static func supply_a(cv, rot: float, fn: String, wreck: bool, o: Vector2) -> void:
	var hl := 0.9
	var hw := 0.19
	var pts := hull_pts(hl, hw, 0.28)
	if wreck:
		_wreck(cv, o, rot, pts, 8.0, HULL_A, hl, hw, 1101, [[-0.58, 0.0, 0.16, 0.15, 6.0], [0.3, 0.05, 0.08, 0.06, 3.0]])
		return
	var r := prism(cv, o, Vector3.ZERO, pts, 8.0, rot, HULL_A, 0.06, 1101, DECK_A)
	_hull_sides(cv, r, "a", HULL_A, 1101)
	var t: PackedVector2Array = r.top
	var z := 8.0
	var items: Array = []
	var cols := [VH.HULL, SAND, Color8(110, 116, 118), VH.HULL_D]
	for bay in 2:
		for side in 2:
			var ff := 0.44 - bay * 0.2
			var rr := -0.075 + side * 0.15
			var ci: int = (bay * 2 + side) % 4
			items.append([ff, rr, func() -> void:
				var b := bx(cv, o, rot, ff, rr, z, 0.085, 0.065, 5.0, cols[ci], 1110 + ci)
				D.box_edges(cv, b, cols[ci], 1111)
				for sd in b.sides:
					D.grille(cv, sd.quad, 0.1, 0.15, 0.9, 0.85, cols[ci], 4)
				if bay == 0 and side == 1:
					var b2 := bx(cv, o, rot, ff, rr, z + 5.0, 0.085, 0.065, 5.0, Color8(150, 150, 146), 1115)
					_band(cv, b2, 0.0, 1.0, 0.7)
					D.box_edges(cv, b2, Color8(150, 150, 146), 1116)])
	for side in [-1.0, 1.0]:
		var rr: float = 0.075 * side
		items.append([0.0, rr, func() -> void:
			var tk: Dictionary = ML.hexp(cv, o, D.w(rot, 0.0, rr, z), 0.065, 7.0, rot, Color8(176, 176, 166), 1120)
			for sd in tk.sides:
				cv.line_v(P.sub(sd.quad, 0, 0.7, 1, 0.7)[0], P.sub(sd.quad, 0, 0.7, 1, 0.7)[1], Color8(150, 50, 40))])
	var work := fn == "work"
	items.append([0.66, 0.0, func() -> void:
		var pb := D.sp(o, rot, 0.66, 0.0, z)
		var pt := pb + Vector2(0, -16)
		cv.line_v(pb, pt, Color8(206, 168, 52))
		cv.line_v(pb + Vector2(1, 0), pt + Vector2(1, 0), Color8(160, 128, 40))
		var tip := D.sp(o, rot, 0.64 if work else 0.3, 0.42 if work else 0.0, z + 14.0)
		cv.line_v(pt + Vector2(0, 4), tip, Color8(206, 168, 52))
		if work:
			var hook := tip + Vector2(0, 8)
			cv.line_v(tip, hook, Color8(40, 40, 38))
			var c3 := D.w(rot, 0.64, 0.42, z - 2.0)
			var cb := P.box(cv, o, c3, 0.07, 0.05, 4.0, rot, VH.HULL, 0.06, 1125)
			D.box_edges(cv, cb, VH.HULL, 1126)])
	items.append([-0.55, 0.0, func() -> void:
		var s1 := bx(cv, o, rot, -0.58, 0.0, z, 0.17, 0.16, 10.0, SUP_A, 1130)
		D.box_edges(cv, s1, SUP_A, 1131)
		_windows(cv, s1, 0.55, 0.7, 5)
		var s2 := bx(cv, o, rot, -0.5, 0.0, z + 10.0, 0.08, 0.2, 5.0, SUP_A, 1132)
		_windows(cv, s2, 0.35, 0.75, 6)
		D.hatch(cv, s2.top, 0.2, 0.3, 0.6, 0.7, SUP_A)
		var fu := bx(cv, o, rot, -0.74, 0.0, z + 10.0, 0.05, 0.065, 9.0, SUP_A, 1133, P.mul(D.DARK, 1.2))
		_band(cv, fu, 0.45, 0.75)
		_mast(cv, o, rot, -0.5, 0.0, z + 15.0, 10.0, false)])
	_paint(rot, items)
	if work:
		_hose(cv, o, rot, 0.0, z + 6.0, 1.0, Color8(40, 40, 38))
	cv.outline(OUTL)
	var mv := fn == "move"
	_water(cv, o, rot, pts, Vector2.ZERO, hl, hw, mv, 1101)
	_foam(cv, r)
	if mv:
		_spray(cv, o, rot, Vector2.ZERO, hl, 1101)
	if fn == "fire":
		_tracer(cv, D.sp(o, rot, -0.45, 0.21, z + 13.0), (_fdir(o, rot) + Vector2(0.4, 0.2)).normalized(), 12.0)


# ================================================================ b_supply_ship_b (fuel tender)
static func tender_b(cv, rot: float, fn: String, wreck: bool, o: Vector2) -> void:
	var hl := 0.85
	var hw := 0.2
	var pts := hull_pts(hl, hw, 0.2, 0.9)
	if wreck:
		_wreck(cv, o, rot, pts, 7.0, HULL_B, hl, hw, 1201, [[-0.6, 0.0, 0.13, 0.14, 7.0], [0.2, 0.0, 0.09, 0.09, 3.0]])
		return
	var r := prism(cv, o, Vector3.ZERO, pts, 7.0, rot, HULL_B, 0.09, 1201, DECK_B)
	_hull_sides(cv, r, "b", HULL_B, 1201)
	var t: PackedVector2Array = r.top
	cv.line_v(t[0].lerp(t[8], 0.5), t[4], P.mul(DECK_B, 0.7))  # centre pipe run
	var z := 7.0
	var items: Array = []
	var i := 0
	for ff: float in [0.44, 0.17, -0.1]:
		var k := i
		items.append([ff, 0.0, func() -> void:
			var tc := V.PRIMER if k != 1 else P.mix(V.PRIMER, V.RUST, 0.25)
			var tk: Dictionary = ML.hexp(cv, o, D.w(rot, ff, 0.0, z), 0.115, 8.0, rot, tc, 1210 + k, P.mul(tc, 1.08))
			for sd in tk.sides:
				V.rivets(cv, sd.quad, 0.85, 3, tc)
				V.streaks(cv, sd.quad, 1215 + k, 0.7)
			var tt: PackedVector2Array = tk.top
			var c: Vector2 = (tt[0] + tt[3]) * 0.5
			cv.ellipse(c.x, c.y, 2.5, 1.4, P.mul(tc, 0.7))  # filler dome
			cv.px(int(c.x) - 1, int(c.y) - 1, P.mul(tc, 1.35))
			if k == 1:
				V.patch(cv, tt, 0.2, 0.2, 0.5, 0.5, V.RUST, 1219)])
		i += 1
	items.append([0.66, 0.0, func() -> void:
		var pb := D.sp(o, rot, 0.66, 0.0, z)
		cv.line_v(pb, pb + Vector2(0, -13), Color8(70, 62, 50))
		cv.line_v(pb + Vector2(0, -12), D.sp(o, rot, 0.4, 0.0, z + 9.0), Color8(70, 62, 50))
		cv.px(int(pb.x), int(pb.y) - 14, Color8(120, 110, 90))])
	items.append([-0.6, 0.0, func() -> void:
		var wh := bx(cv, o, rot, -0.6, 0.0, z, 0.13, 0.15, 11.0, V.HULL, 1230)
		for sd in wh.sides:
			V.rivets(cv, sd.quad, 0.9, 5, V.HULL)
			V.streaks(cv, sd.quad, 1231)
		_windows(cv, wh, 0.55, 0.75, 4)
		D.box_edges(cv, wh, V.HULL, 1232)
		ML.team_panel(cv, wh.top, 0.15, 0.2, 0.85, 0.8, 0.62)
		var stk: Dictionary = ML.hexp(cv, o, D.w(rot, -0.73, 0.0, z + 11.0), 0.045, 12.0, rot, V.GUNMETAL, 1233, D.DARK)
		for sd in stk.sides:
			cv.line_v(P.sub(sd.quad, 0, 0.8, 1, 0.8)[0], P.sub(sd.quad, 0, 0.8, 1, 0.8)[1], V.RUST)
		V.soot(cv, D.sp(o, rot, -0.73, 0.0, z + 22.0), 3.0, 1234)])
	_paint(rot, items)
	var work := fn == "work"
	if work:
		_hose(cv, o, rot, 0.17, z + 8.0, 1.0, Color8(36, 32, 28))
	cv.outline(OUTL)
	var mv := fn == "move"
	_water(cv, o, rot, pts, Vector2.ZERO, hl, hw, mv, 1201)
	_foam(cv, r)
	var top := D.sp(o, rot, -0.73, 0.0, z + 24.0)
	for k in (4 if mv else 2):
		L.puff(cv, top + Vector2(-k * 2.5 if mv else 0.0, -2.0 - k * 3.5), 1.8 + k * 0.7, 0.6 - k * 0.1, SMOKE)
	if mv:
		_spray(cv, o, rot, Vector2.ZERO, hl, 1201)
	if fn == "fire":
		_tracer(cv, D.sp(o, rot, -0.55, 0.0, z + 13.0), (_fdir(o, rot) + Vector2(-0.3, 0.3)).normalized(), 12.0)


# ================================================================ m_charge_tender (catamaran)
static func charge_m(cv, rot: float, fn: String, wreck: bool, o: Vector2) -> void:
	var hl := 0.78
	var hw := 0.065
	var pts := hull_pts(hl, hw, 0.32, 0.7, 0.03)
	var sides := [-0.17, 0.17]
	if _dep(rot, 0.0, 0.17) < _dep(rot, 0.0, -0.17):
		sides = [0.17, -0.17]
	if wreck:
		for rr: float in sides:
			var wr := prism(cv, o, D.w(rot, 0.0, rr, 0.0), pts, 3.0, rot, ML.DEAD, 0.08, 1301, ML.DEAD_D)
			for sd in wr.sides:
				ML.seam(cv, sd.quad, 0.5, true)
		var dk := bx(cv, o, rot, -0.05, 0.0, 3.0, 0.4, 0.22, 2.0, ML.DEAD, 1302, ML.DEAD_D)
		V.scorch(cv, dk.top)
		cv.outline(OUTL_M)
		var c := D.sp(o, rot, 0.0, 0.0, 6)
		V.soot(cv, c, 6.0, 1303)
		for k in 3:
			L.puff(cv, c + Vector2(k * 2.0, -4.0 - k * 4.0), 2.2 + k * 0.8, 0.5 - k * 0.1, SMOKE)
		return
	var hulls: Array = []
	for rr: float in sides:
		var h := prism(cv, o, D.w(rot, 0.0, rr, 0.0), pts, 7.0, rot, ML.GRAPH, 0.06, 1301, ML.GRAPH_D)
		_hull_sides(cv, h, "m", ML.GRAPH, 1301)
		hulls.append(h)
	var z := 7.0
	var dk := bx(cv, o, rot, -0.08, 0.0, z - 1.0, 0.5, 0.24, 3.0, ML.GRAPH_D, 1305, ML.SLAB)
	for sd in dk.sides:
		ML.seam(cv, sd.quad, 0.5)
		ML.joints(cv, sd.quad, [0.25, 0.5, 0.75], ML.GRAPH_D)
	ML.team_panel(cv, dk.top, 0.04, 0.1, 0.18, 0.9, 0.62)
	var zt := z + 2.0
	var items: Array = []
	var glow := fn == "work"
	for row in 2:
		for col in 3:
			var ff := 0.24 - col * 0.17
			var rr := -0.08 + row * 0.16
			items.append([ff, rr, func() -> void:
				var cell := bx(cv, o, rot, ff, rr, zt, 0.06, 0.055, 5.0, ML.PANEL, 1310 + row * 3 + col, ML.PANEL_D)
				for sd in cell.sides:
					ML.seam(cv, sd.quad, 0.7)
				var ct: PackedVector2Array = cell.top
				ML.hex_plate(cv, ct, 0.5, 0.5, 2.0, ML.GRAPH_D, true)
				if glow:
					cv.px(int((ct[0].x + ct[2].x) * 0.5), int((ct[0].y + ct[2].y) * 0.5), ML.CYAN_HOT)])
	items.append([-0.45, 0.0, func() -> void:
		var py: Dictionary = ML.hexp(cv, o, D.w(rot, -0.45, 0.0, zt), 0.07, 14.0, rot, ML.GRAPH, 1320, ML.GRAPH_D)
		for sd in py.sides:
			ML.seam(cv, sd.quad, 0.3)
			ML.seam(cv, sd.quad, 0.75)
		var cap: Dictionary = ML.hexp(cv, o, D.w(rot, -0.45, 0.0, zt + 14.0), 0.045, 3.0, rot, ML.PANEL, 1321)
		ML.rims(cv, cap, ML.PANEL)])
	_paint(rot, items)
	cv.outline(OUTL_M)
	var mv := fn == "move"
	for rr: float in sides:
		_water(cv, o, rot, pts, Vector2(0.0, rr), hl, hw, mv, 1301)
		if mv:
			_spray(cv, o, rot, Vector2(0.0, rr), hl, 1301, 0.7)
	for h: Dictionary in hulls:
		_foam(cv, h)
	var tip := D.sp(o, rot, -0.45, 0.0, zt + 18.0)
	ML.eye(cv, tip, true)
	if glow:
		var end := D.sp(o, rot, -0.3, 0.75, 6.0)
		var prev := tip
		for k in range(1, 9):
			var t := k / 8.0
			var p := tip.lerp(end, t) + Vector2((P.hn(k, 7, 1331) - 0.5) * 5.0, (P.hn(k, 8, 1331) - 0.5) * 4.0) * (1.0 if k < 8 else 0.0)
			cv.line_v(prev, p, ML.CYAN)
			cv.line_v(prev + Vector2(0, 1), p + Vector2(0, 1), Color(ML.TEAL.r, ML.TEAL.g, ML.TEAL.b, 0.6))
			prev = p
		cv.ellipse(end.x, end.y, 3.0, 1.6, Color(ML.CYAN.r, ML.CYAN.g, ML.CYAN.b, 0.45))
		cv.px(int(end.x), int(end.y), ML.CYAN_HOT)
	if fn == "fire":
		var d := (_fdir(o, rot) + Vector2(0, -0.6)).normalized()
		cv.line_v(tip + d * 2.0, tip + d * 12.0, Color8(120, 245, 255))
		cv.px(int(tip.x + d.x * 12.0), int(tip.y + d.y * 12.0), Color8(230, 255, 255))


# ================================================================ a_minesweeper
static func sweeper(cv, rot: float, fn: String, wreck: bool, o: Vector2) -> void:
	var hl := 0.62
	var hw := 0.14
	var pts := hull_pts(hl, hw, 0.24, 0.85, 0.04)
	if wreck:
		_wreck(cv, o, rot, pts, 6.0, HULL_A, hl, hw, 1401, [[0.08, 0.0, 0.13, 0.11, 6.0]])
		return
	var r := prism(cv, o, Vector3.ZERO, pts, 6.0, rot, HULL_A, 0.06, 1401, DECK_A)
	_hull_sides(cv, r, "a", HULL_A, 1401)
	var z := 6.0
	var items: Array = []
	var sweep := fn == "sweep"
	items.append([0.42, 0.0, func() -> void:
		var mt := bx(cv, o, rot, 0.42, 0.0, z, 0.04, 0.04, 3.0, VH.HULL, 1410)
		D.box_edges(cv, mt, VH.HULL, 1411)
		var a := D.sp(o, rot, 0.44, 0.0, z + 4.0)
		var b := D.sp(o, rot, 0.6, 0.0, z + 6.0)
		cv.line_v(a, b, VH.GUNMETAL)
		cv.line_v(a + Vector2(0, -1), b + Vector2(0, -1), P.mul(VH.GUNMETAL, 1.3))])
	items.append([0.08, 0.0, func() -> void:
		var s1 := bx(cv, o, rot, 0.08, 0.0, z, 0.15, 0.12, 8.0, SUP_A, 1420)
		D.box_edges(cv, s1, SUP_A, 1421)
		_windows(cv, s1, 0.5, 0.68, 4)
		var s2 := bx(cv, o, rot, 0.13, 0.0, z + 8.0, 0.07, 0.13, 4.0, SUP_A, 1422)
		_windows(cv, s2, 0.3, 0.75, 5)
		var fu := bx(cv, o, rot, -0.07, 0.0, z + 8.0, 0.04, 0.05, 6.0, SUP_A, 1423, D.DARK)
		_band(cv, fu, 0.4, 0.75)
		_mast(cv, o, rot, 0.05, 0.0, z + 12.0, 11.0, false)])
	items.append([-0.3, 0.0, func() -> void:
		var reel := bx(cv, o, rot, -0.3, 0.0, z, 0.06, 0.09, 5.0, D.DARK, 1430)
		for sd in reel.sides:
			cv.line_v(P.sub(sd.quad, 0, 0.5, 1, 0.5)[0], P.sub(sd.quad, 0, 0.5, 1, 0.5)[1], Color8(150, 140, 110))
		if not sweep:
			for k in 2:
				var fl := D.sp(o, rot, -0.45, -0.07 + k * 0.14, z + 2.0)
				cv.ellipse(fl.x, fl.y, 2.4, 1.6, ORANGE)
				cv.px(int(fl.x) - 1, int(fl.y) - 1, Color8(250, 170, 90))])
	items.append([-0.58, 0.0, func() -> void:
		var l0 := D.sp(o, rot, -0.58, -0.11, z)
		var r0 := D.sp(o, rot, -0.58, 0.11, z)
		var top := D.sp(o, rot, -0.64, 0.0, z + 11.0)
		cv.line_v(l0, top, VH.HULL)
		cv.line_v(r0, top, VH.HULL)
		cv.line_v(top + Vector2(-2, 0), top + Vector2(2, 0), VH.HULL_D)])
	_paint(rot, items)
	cv.outline(OUTL)
	var mv := fn == "move" or sweep
	_water(cv, o, rot, pts, Vector2.ZERO, hl, hw, mv, 1401)
	_foam(cv, r)
	if mv:
		_spray(cv, o, rot, Vector2.ZERO, hl, 1401, 0.8)
	if sweep:
		var top := D.sp(o, rot, -0.64, 0.0, z + 11.0)
		var fl := D.sp(o, rot, -hl - 0.36, 0.16, 0.0)
		var mid := D.sp(o, rot, -hl - 0.18, 0.08, 0.0)
		cv.line_v(top, mid, Color8(36, 36, 34))
		cv.line_v(mid, fl, Color(0.14, 0.14, 0.13, 0.7))
		cv.ellipse(fl.x, fl.y - 1.0, 2.4, 1.5, ORANGE)
		cv.px(int(fl.x), int(fl.y) - 3, Color8(240, 220, 120))
		_wp(cv, int(fl.x) - 3, int(fl.y), Color(WAKE.r, WAKE.g, WAKE.b, 0.5))
		_wp(cv, int(fl.x) + 3, int(fl.y), Color(WAKE.r, WAKE.g, WAKE.b, 0.5))
	if fn == "fire":
		var b := D.sp(o, rot, 0.62, 0.0, z + 6.0)
		L.flash(cv, b, 0.8)
		L.puff(cv, b + Vector2(2, -2), 1.8, 0.4)


# ================================================================ b_mine_barge
static func _mine(cv, p: Vector2, wreck := false) -> void:
	var c := MINE if not wreck else VH.BURNT
	cv.ellipse(p.x, p.y - 2.0, 2.4, 2.2, c)
	cv.px(int(p.x) - 1, int(p.y) - 3, P.mul(c, 1.6))
	cv.px(int(p.x), int(p.y) - 5, Color8(150, 146, 130))      # contact horns
	cv.px(int(p.x) - 3, int(p.y) - 3, Color8(150, 146, 130))
	cv.px(int(p.x) + 2, int(p.y) - 3, Color8(150, 146, 130))
	cv.px(int(p.x), int(p.y), P.mul(c, 0.6))


static func mine_barge(cv, rot: float, fn: String, wreck: bool, o: Vector2) -> void:
	var hl := 0.74
	var hw := 0.22
	var pts := hull_pts(hl, hw, 0.12, 1.0, 0.04)
	if wreck:
		_wreck(cv, o, rot, pts, 5.0, HULL_B, hl, hw, 1501, [[0.58, 0.0, 0.1, 0.13, 6.0]])
		return
	var r := prism(cv, o, Vector3.ZERO, pts, 5.0, rot, HULL_B, 0.09, 1501, DECK_B)
	_hull_sides(cv, r, "b", HULL_B, 1501)
	var z := 5.0
	for rr: float in [-0.1, 0.1]:
		var a := D.sp(o, rot, 0.45, rr, z)
		var b := D.sp(o, rot, -hl, rr, z)
		cv.line_v(a, b, Color8(58, 54, 48))
		cv.line_v(a + Vector2(0, -1), b + Vector2(0, -1), Color8(120, 112, 96))
	var items: Array = []
	var lay := fn == "lay"
	for rr: float in [-0.1, 0.1]:
		for k in 5:
			if lay and k == 4 and rr > 0.0:
				continue
			var ff := 0.36 - k * 0.2
			items.append([ff, rr, func() -> void: _mine(cv, D.sp(o, rot, ff, rr, z))])
	items.append([0.58, 0.0, func() -> void:
		var wh := bx(cv, o, rot, 0.58, 0.0, z, 0.1, 0.14, 10.0, V.HULL, 1520)
		for sd in wh.sides:
			V.rivets(cv, sd.quad, 0.88, 4, V.HULL)
			V.streaks(cv, sd.quad, 1521)
		_windows(cv, wh, 0.55, 0.75, 3)
		D.box_edges(cv, wh, V.HULL, 1522)
		ML.team_panel(cv, wh.top, 0.15, 0.2, 0.85, 0.8, 0.62)
		var stk: Dictionary = ML.hexp(cv, o, D.w(rot, 0.52, 0.08, z + 10.0), 0.03, 7.0, rot, V.GUNMETAL, 1523, D.DARK)
		V.soot(cv, D.sp(o, rot, 0.52, 0.08, z + 17.0), 2.0, 1524)])
	_paint(rot, items)
	cv.outline(OUTL)
	var mv := fn == "move" or lay
	_water(cv, o, rot, pts, Vector2.ZERO, hl, hw, mv, 1501)
	_foam(cv, r)
	if mv:
		_spray(cv, o, rot, Vector2.ZERO, hl, 1501, 0.8)
	if lay:
		var p := D.sp(o, rot, -hl - 0.1, 0.1, 0.0)
		cv.ellipse(p.x, p.y, 4.5, 2.2, Color(WAKE.r, WAKE.g, WAKE.b, 0.35))
		_mine(cv, p + Vector2(0, 1))
		L.puff(cv, p + Vector2(-2, -3), 1.8, 0.5, SPRAY)
		L.puff(cv, p + Vector2(3, -2), 1.4, 0.45, SPRAY)
	if fn == "fire":
		_tracer(cv, D.sp(o, rot, 0.58, 0.0, z + 12.0), (_fdir(o, rot) + Vector2(0.3, -0.2)).normalized(), 12.0)


# ================================================================ a_hovercraft
static func _duct(cv, o: Vector2, rot: float, f: float, r: float, z: float, rad: float, spin: bool) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := i * TAU / 16.0
		pts.append(D.sp(o, rot, f, r + cos(a) * rad / 32.0, z + sin(a) * rad))
	cv.poly(pts, Color(0.16, 0.17, 0.16, 0.92) if spin else Color8(40, 42, 40))
	if not spin:
		var c := D.sp(o, rot, f, r, z)
		for k in 3:
			var a := 0.4 + k * TAU / 3.0
			cv.line_v(c, D.sp(o, rot, f, r + cos(a) * rad * 0.8 / 32.0, z + sin(a) * rad * 0.8), Color8(70, 72, 68))
	for i in 16:
		var j := (i + 1) % 16
		cv.line_v(pts[i], pts[j], VH.HULL)
		cv.line_v(pts[i] + Vector2(0, -1), pts[j] + Vector2(0, -1), P.mul(VH.HULL, 1.15))
	var hub := D.sp(o, rot, f, r, z)
	cv.px(int(hub.x), int(hub.y), Color8(110, 112, 104))


static func _tank(cv, o: Vector2, rot: float, f: float, z: float) -> void:
	var hl := bx(cv, o, rot, f, 0.0, z, 0.21, 0.11, 5.0, VH.HULL, 1640)
	D.box_edges(cv, hl, VH.HULL, 1641)
	var front := D.faces_cam(rot, 1.0, 0.0)
	var a := D.sp(o, rot, f + 0.05, 0.0, z + 9.0)
	var b := D.sp(o, rot, f + 0.34, 0.0, z + 9.0)
	if not front:
		cv.line_v(a, b, VH.GUNMETAL)
	var tu := bx(cv, o, rot, f - 0.03, 0.0, z + 5.0, 0.1, 0.085, 4.0, VH.HULL, 1642)
	_band(cv, tu, 0.2, 0.7)
	D.hatch(cv, tu.top, 0.2, 0.2, 0.5, 0.5, VH.HULL)
	if front:
		cv.line_v(a, b, VH.GUNMETAL)


static func hovercraft(cv, rot: float, fn: String, wreck: bool, o: Vector2) -> void:
	var hl := 0.58
	var hw := 0.3
	var pts := rrect(hl, hw, 0.12)
	if wreck:
		_wreck(cv, o, rot, pts, 6.0, RUBBER, hl, hw, 1601, [[-0.05, 0.22, 0.38, 0.06, 4.0]])
		return
	var r := prism(cv, o, Vector3.ZERO, pts, 4.0, rot, RUBBER, 0.1, 1601)
	for sd in r.sides:
		for k in 6:
			var u := (k + 0.5) / 6.0
			var q: PackedVector2Array = sd.quad
			cv.line_v(q[0].lerp(q[1], u), q[3].lerp(q[2], u), P.mul(RUBBER, 0.7))
	var dk := prism(cv, o, Vector3(0, 0, 4), rrect(hl * 0.95, hw * 0.9, 0.1), 3.0, rot, VH.HULL, 0.07, 1602, VH.HULL_D)
	for sd in dk.sides:
		cv.line_v(sd.quad[3], sd.quad[2], P.mul(VH.HULL, 1.25))
	var z := 7.0
	var items: Array = []
	var ld := fn == "loaded" or fn == "unload"
	var unload := fn == "unload"
	for sg: float in [-1.0, 1.0]:
		var rr := 0.2 * sg
		items.append([0.0, rr, func() -> void:
			var cab := bx(cv, o, rot, 0.0, rr, z, 0.38, 0.06, 6.0 if sg > 0 else 4.5, VH.HULL, 1610 + int(sg))
			D.box_edges(cv, cab, VH.HULL, 1612)
			_windows(cv, cab, 0.5, 0.72, 6)
			if sg > 0:
				var br := bx(cv, o, rot, 0.2, rr, z + 6.0, 0.1, 0.055, 4.0, VH.HULL, 1613)
				_windows(cv, br, 0.3, 0.8, 3)
				_band(cv, cab, 0.15, 0.35)
				D.antenna(cv, D.sp(o, rot, 0.1, rr, z + 10.0), 9, false)
			else:
				D.stowage(cv, o, rot, -0.1, rr, z + 4.5, 0.12, 0.04, 2.0, false, false)])
	items.append([0.58 if not unload else 0.7, 0.0, func() -> void:
		if unload:
			var rp := bx(cv, o, rot, 0.68, 0.0, 0.0, 0.12, 0.13, 1.5, VH.HULL_D, 1620)
			for k in 4:
				var u := (k + 0.5) / 4.0
				var tq: PackedVector2Array = rp.top
				cv.line_v(tq[0].lerp(tq[1], u), tq[3].lerp(tq[2], u), P.mul(VH.HULL_D, 0.75))
		else:
			var rp2 := bx(cv, o, rot, 0.55, 0.0, z - 3.0, 0.02, 0.14, 6.0, VH.HULL_D, 1621)
			D.box_edges(cv, rp2, VH.HULL_D, 1622)])
	if ld:
		var tf := 0.05 if not unload else 0.38
		items.append([tf, 0.0, func() -> void: _tank(cv, o, rot, tf, z if not unload else 2.0)])
	var spin := fn != "idle"
	for sg: float in [-1.0, 1.0]:
		var rr := 0.12 * sg
		items.append([-0.46, rr, func() -> void:
			var eh := bx(cv, o, rot, -0.42, rr, z, 0.05, 0.05, 6.0, VH.HULL_D, 1630)
			_duct(cv, o, rot, -0.47, rr, z + 7.0, 5.5, spin)
			var ra := D.sp(o, rot, -0.55, rr, z + 3.0)
			cv.line_v(ra, ra + Vector2(0, -8), VH.HULL)])
	_paint(rot, items)
	cv.outline(OUTL)
	var mv := fn == "move"
	_water(cv, o, rot, pts, Vector2.ZERO, hl, hw, mv, 1601, 0.18)
	_foam(cv, r)
	if mv:
		for i in 9:
			var a := i * TAU / 9.0
			var p := D.sp(o, rot, cos(a) * hl * 1.05, sin(a) * hw * 1.05, 1)
			L.puff(cv, p, 2.0 + P.hn(i, 3, 1650) * 1.2, 0.35, SPRAY)
	if fn == "fire":
		_tracer(cv, D.sp(o, rot, 0.2, 0.2, z + 11.0), _fdir(o, rot), 12.0)


# ================================================================ b_aa_barge
static func aa_barge(cv, rot: float, fn: String, wreck: bool, o: Vector2) -> void:
	var hl := 0.72
	var hw := 0.24
	var pts := hull_pts(hl, hw, 0.1, 1.0, 0.05)
	if wreck:
		_wreck(cv, o, rot, pts, 5.0, HULL_B, hl, hw, 1701, [[0.4, 0.0, 0.09, 0.09, 4.0], [-0.4, 0.0, 0.09, 0.09, 4.0]])
		return
	var r := prism(cv, o, Vector3.ZERO, pts, 5.0, rot, HULL_B, 0.09, 1701, DECK_B)
	_hull_sides(cv, r, "b", HULL_B, 1701)
	var z := 5.0
	var fire := fn == "fire"
	var tips: Array = []
	var items: Array = []
	var az := [0.35, 0.0, -0.35]
	var k := 0
	for ff: float in [0.42, 0.0, -0.42]:
		var kk := k
		var a: float = az[k]
		items.append([ff, 0.0, func() -> void:
			var tub: Dictionary = ML.hexp(cv, o, D.w(rot, ff, 0.0, z), 0.11, 4.0, rot, V.HULL, 1710 + kk, P.mul(DECK_B, 0.8))
			for sd in tub.sides:
				V.rivets(cv, sd.quad, 0.75, 3, V.HULL)
			var base := D.w(rot, ff, 0.0, 0.0)
			var cra := P.box(cv, o, Vector3(base.x, base.y, z + 2.0), 0.035, 0.05, 4.0, rot + a, V.GUNMETAL, 0.06, 1715)
			var el := 9.0 if not fire else 8.0
			for sg: float in [-1.0, 1.0]:
				var b0 := D.w(rot + a, 0.0, 0.018 * sg)
				var b1 := D.w(rot + a, 0.15, 0.018 * sg)
				var pa := P.proj(o, Vector3(base.x + b0.x, base.y + b0.y, z + 5.0))
				var pb := P.proj(o, Vector3(base.x + b1.x, base.y + b1.y, z + 5.0 + el))
				cv.line_v(pa, pb, V.GUNMETAL)
				cv.line_v(pa + Vector2(0, -1), pb + Vector2(0, -1), P.mul(V.GUNMETAL, 1.4))
				tips.append(pb)
			var sh := D.w(rot + a, 0.05, 0.0)
			P.box(cv, o, Vector3(base.x + sh.x, base.y + sh.y, z + 3.0), 0.01, 0.06, 4.0, rot + a, V.PRIMER, 0.08, 1716)])
		k += 1
	items.append([0.66, 0.15, func() -> void:
		D.stowage(cv, o, rot, 0.62, 0.15, z, 0.04, 0.04, 3.0, false, false)
		D.stowage(cv, o, rot, -0.64, -0.15, z, 0.04, 0.05, 3.0, false, false)])
	_paint(rot, items)
	var bitt := D.sp(o, rot, hl - 0.06, 0.0, z)
	cv.rect(int(bitt.x) - 1, int(bitt.y) - 2, 2, 2, D.DARK)
	cv.outline(OUTL)
	var mv := fn == "move"
	_water(cv, o, rot, pts, Vector2.ZERO, hl, hw, mv, 1701)
	_foam(cv, r)
	if mv:
		_spray(cv, o, rot, Vector2.ZERO, hl, 1701, 0.7)
	if fire:
		var i := 0
		for p: Vector2 in tips:
			L.flash(cv, p + Vector2(0, -1), 0.6)
			i += 1
		for j in 3:
			var c: Vector2 = tips[j * 2] + Vector2(-2 + j * 3, -16 - j * 3)
			L.puff(cv, c, 2.2, 0.6, Color(0.22, 0.21, 0.2))
			cv.px(int(c.x), int(c.y), Color8(255, 200, 110))


# ================================================================ m_lance_cruiser
static func lance(cv, rot: float, fn: String, wreck: bool, o: Vector2) -> void:
	var hl := 1.2
	var hw := 0.2
	var pts := hull_pts(hl, hw, 0.55, 0.72, 0.05)
	if wreck:
		_wreck(cv, o, rot, pts, 8.0, ML.DEAD, hl, hw, 1801, [[-0.35, 0.0, 0.15, 0.13, 6.0]], OUTL_M)
		return
	var r := prism(cv, o, Vector3.ZERO, pts, 8.0, rot, ML.GRAPH, 0.06, 1801, ML.GRAPH_D)
	_hull_sides(cv, r, "m", ML.GRAPH, 1801)
	var t: PackedVector2Array = r.top
	cv.line_v(t[0].lerp(t[8], 0.5), t[4], P.mul(ML.GRAPH_D, 0.75))
	var z := 8.0
	var fire := fn == "fire"
	var items: Array = []
	items.append([-0.38, 0.0, func() -> void:
		var s1: Dictionary = ML.hexp(cv, o, D.w(rot, -0.38, 0.0, z), 0.2, 8.0, rot, ML.GRAPH, 1810, ML.SLAB, 0.75)
		for sd in s1.sides:
			ML.seam(cv, sd.quad, 0.6)
		ML.rims(cv, s1, ML.GRAPH)
		var s2: Dictionary = ML.hexp(cv, o, D.w(rot, -0.36, 0.0, z + 8.0), 0.12, 6.0, rot, ML.PANEL, 1811, ML.PANEL_D, 0.8)
		for sd in s2.sides:
			ML.team_panel(cv, sd.quad, 0.15, 0.25, 0.85, 0.6, 0.62)
		var ms: Dictionary = ML.hexp(cv, o, D.w(rot, -0.4, 0.0, z + 14.0), 0.04, 10.0, rot, ML.GRAPH_D, 1812)
		for sd in ms.sides:
			ML.seam(cv, sd.quad, 0.5)])
	items.append([-0.78, 0.0, func() -> void:
		var vls := bx(cv, o, rot, -0.8, 0.0, z, 0.16, 0.12, 2.0, ML.GRAPH_D, 1820, ML.SLAB)
		for u: float in [0.25, 0.75]:
			for v: float in [0.3, 0.7]:
				ML.hex_plate(cv, vls.top, u, v, 2.0, ML.JOINT, u < 0.5)])
	items.append([0.45, 0.0, func() -> void:
		for pf: float in [0.08, 0.5, 0.9]:
			bx(cv, o, rot, pf, 0.0, z, 0.03, 0.05, 5.0, ML.GRAPH_D, 1830)
		var cap: Dictionary = ML.hexp(cv, o, D.w(rot, 0.0, 0.0, z), 0.08, 6.0, rot, ML.PANEL_D, 1831)
		for sd in cap.sides:
			ML.seam(cv, sd.quad, 0.5)
		for sg: float in [-1.0, 1.0]:
			var rl := bx(cv, o, rot, 0.52, 0.045 * sg, z + 5.0, 0.52, 0.022, 2.5, ML.PANEL_D, 1832, ML.PANEL)
			ML.rims(cv, rl, ML.PANEL_D)
		var a := D.sp(o, rot, 0.02, 0.0, z + 6.5)
		var b := D.sp(o, rot, 1.04, 0.0, z + 6.5)
		cv.line_v(a, b, ML.CYAN_HOT if fire else ML.CYAN)])
	_paint(rot, items)
	cv.outline(OUTL_M)
	ML.eye(cv, D.sp(o, rot, -0.4, 0.0, z + 25.0), true)
	ML.eye(cv, D.sp(o, rot, -0.2, 0.0, z + 12.0))
	var mv := fn == "move"
	_water(cv, o, rot, pts, Vector2.ZERO, hl, hw, mv, 1801, 0.2)
	_foam(cv, r)
	if mv:
		_spray(cv, o, rot, Vector2.ZERO, hl, 1801)
	if fire:
		var tip := D.sp(o, rot, 1.06, 0.0, z + 7.5)
		var d := _fdir(o, rot)
		cv.ellipse(tip.x, tip.y, 3.5, 2.5, Color(ML.CYAN.r, ML.CYAN.g, ML.CYAN.b, 0.45))
		cv.line_v(tip, tip + d * 22.0, Color8(120, 245, 255))
		cv.line_v(tip + Vector2(0, 1), tip + d * 18.0 + Vector2(0, 1), Color(ML.TEAL.r, ML.TEAL.g, ML.TEAL.b, 0.7))
		cv.px(int(tip.x + d.x * 22.0), int(tip.y + d.y * 22.0), Color8(230, 255, 255))
		cv.px(int(tip.x), int(tip.y), ML.CYAN_HOT)


# ================================================================ a_carrier
static func _deck_jet(cv, o: Vector2, rot: float, f: float, r: float, z: float, hdg: float) -> void:
	var a := rot + hdg
	var base := D.w(rot, f, r, 0.0)
	var pt := func(jf: float, jr: float, dz: float) -> Vector2:
		var v := D.w(a, jf * 1.35, jr * 1.35)
		return P.proj(o, Vector3(base.x + v.x, base.y + v.y, z + dz))
	var body: Color = AP.PAL_A["body"]
	cv.poly(PackedVector2Array([pt.call(0.04, 0.0, 1.0), pt.call(-0.05, 0.085, 1.0), pt.call(-0.07, 0.08, 1.0),
		pt.call(-0.06, 0.0, 1.0), pt.call(-0.07, -0.08, 1.0), pt.call(-0.05, -0.085, 1.0)]), P.mul(body, 0.92))
	cv.poly(PackedVector2Array([pt.call(-0.08, 0.0, 1.0), pt.call(-0.11, 0.045, 1.0), pt.call(-0.115, -0.045, 1.0)]), P.mul(body, 0.85))
	cv.line_v(pt.call(0.12, 0.0, 1.5), pt.call(-0.11, 0.0, 1.5), body)
	cv.line_v(pt.call(0.1, 0.0, 2.5), pt.call(-0.09, 0.0, 2.5), P.mul(body, 1.12))
	var cp: Vector2 = pt.call(0.07, 0.0, 3.0)
	cv.px(int(cp.x), int(cp.y), GLASS)
	cv.team = true
	cv.line_v(pt.call(-0.08, 0.0, 3.0), pt.call(-0.11, 0.0, 7.0), Color(0.62, 0.62, 0.62))
	cv.team = false


static func carrier(cv, rot: float, fn: String, wreck: bool, o: Vector2) -> void:
	var hl := 1.32
	var hw := 0.23
	var pts := hull_pts(hl, hw, 0.42, 0.85, 0.05)
	var dpts := [Vector2(-1.36, -0.24), Vector2(-0.2, -0.36), Vector2(0.5, -0.31), Vector2(1.22, -0.15), Vector2(1.36, -0.02),
		Vector2(1.36, 0.1), Vector2(1.12, 0.28), Vector2(-1.32, 0.28)]
	if wreck:
		_wreck(cv, o, rot, pts, 9.0, HULL_A, hl, hw, 1901, [[-0.25, 0.22, 0.17, 0.05, 8.0]])
		return
	var r := prism(cv, o, Vector3.ZERO, pts, 9.0, rot, HULL_A, 0.06, 1901)
	_hull_sides(cv, r, "a", HULL_A, 1901)
	var z := 9.0
	var deck := Color8(72, 76, 78)
	var dk := prism(cv, o, Vector3(0, 0, z), dpts, 2.5, rot, HULL_A, 0.05, 1902, deck)
	for sd in dk.sides:
		cv.line_v(sd.quad[3], sd.quad[2], P.mul(HULL_A, 1.25))
	var zt := z + 2.5
	var wht := Color(0.86, 0.86, 0.82, 0.9)
	for i in 10:  # angled landing deck centreline, dashed
		var t0 := i / 10.0
		var t1 := t0 + 0.05
		var a0 := Vector2(-1.3, -0.1).lerp(Vector2(0.48, -0.29), t0)
		var a1 := Vector2(-1.3, -0.1).lerp(Vector2(0.48, -0.29), t1)
		cv.line_v(D.sp(o, rot, a0.x, a0.y, zt), D.sp(o, rot, a1.x, a1.y, zt), wht)
	cv.line_v(D.sp(o, rot, -1.3, -0.22, zt), D.sp(o, rot, 0.45, -0.34, zt), Color(0.86, 0.86, 0.82, 0.5))
	cv.line_v(D.sp(o, rot, -1.3, 0.02, zt), D.sp(o, rot, 0.5, -0.17, zt), Color(0.86, 0.86, 0.82, 0.5))
	for rr: float in [-0.04, 0.12]:  # bow catapult tracks
		cv.line_v(D.sp(o, rot, 0.55, rr, zt), D.sp(o, rot, 1.3, rr - 0.02, zt), Color8(46, 48, 50))
	var y := Color8(212, 180, 60)
	cv.line_v(D.sp(o, rot, 0.9, 0.22, zt), D.sp(o, rot, -0.9, 0.24, zt), Color(y.r, y.g, y.b, 0.6))
	cv.team = true  # hull number painted on the bow deck
	cv.poly(PackedVector2Array([D.sp(o, rot, 1.05, -0.06, zt), D.sp(o, rot, 1.18, -0.06, zt), D.sp(o, rot, 1.18, 0.08, zt),
		D.sp(o, rot, 1.05, 0.08, zt)]), Color(0.66, 0.66, 0.66))
	cv.team = false
	var el := PackedVector2Array([D.sp(o, rot, -0.72, 0.14, zt), D.sp(o, rot, -0.52, 0.14, zt), D.sp(o, rot, -0.52, 0.27, zt),
		D.sp(o, rot, -0.72, 0.27, zt)])
	for i in 4:
		cv.line_v(el[i], el[(i + 1) % 4], Color8(56, 58, 60))
	var items: Array = []
	var launch := fn == "launch"
	for jp: Array in [[-1.14, 0.16, 2.3], [-0.9, 0.17, 2.3], [0.22, 0.19, 2.3], [0.78, 0.19, 2.3], [1.0, 0.18, 2.3], [-0.3, -0.24, 0.9]]:
		var jf: float = jp[0]
		var jr: float = jp[1]
		var hd: float = jp[2]
		items.append([jf, jr, func() -> void: _deck_jet(cv, o, rot, jf, jr, zt, hd)])
	if launch:
		items.append([1.05, -0.04, func() -> void: _deck_jet(cv, o, rot, 1.05, -0.04, zt, 0.0)])
	items.append([-0.25, 0.22, func() -> void:
		var is1 := bx(cv, o, rot, -0.25, 0.23, zt, 0.17, 0.05, 14.0, SUP_A, 1910)
		D.box_edges(cv, is1, SUP_A, 1911)
		_band(cv, is1, 0.15, 0.38)
		_windows(cv, is1, 0.55, 0.7, 5)
		var is2 := bx(cv, o, rot, -0.18, 0.23, zt + 14.0, 0.1, 0.055, 5.0, SUP_A, 1912)
		_windows(cv, is2, 0.3, 0.78, 4)
		_mast(cv, o, rot, -0.27, 0.23, zt + 19.0, 11.0, false)
		D.antenna(cv, D.sp(o, rot, -0.38, 0.23, zt + 14.0), 8, false)])
	for cp: Array in [[1.12, 0.27], [-1.22, -0.22]]:
		var cf: float = cp[0]
		var cr: float = cp[1]
		items.append([cf, cr, func() -> void:
			var ci := bx(cv, o, rot, cf, cr, zt, 0.03, 0.03, 4.0, Color8(200, 200, 194), 1920)
			D.box_edges(cv, ci, Color8(200, 200, 194), 1921)])
	_paint(rot, items)
	cv.outline(OUTL)
	var mv := fn == "move" or launch
	_water(cv, o, rot, pts, Vector2.ZERO, hl, hw, mv, 1901, 0.18)
	_foam(cv, r)
	if mv:
		_spray(cv, o, rot, Vector2.ZERO, hl, 1901, 1.2)
	if launch:
		var d := _fdir(o, rot)
		var tail := D.sp(o, rot, 0.93, -0.04, zt + 2.0)
		L.flame(cv, tail, -d, 7.0, 1930)
		for i in 5:
			L.puff(cv, D.sp(o, rot, 0.85 - i * 0.07, -0.04, zt + 1.0), 1.8 + i * 0.3, 0.4 - i * 0.05, Color(0.92, 0.93, 0.92))
	if fn == "fire":
		for cp: Array in [[1.12, 0.27, 0.9], [-1.22, -0.22, -0.8]]:
			var p := D.sp(o, rot, cp[0], cp[1], zt + 4.0)
			var side := (D.sp(o, rot, 0.0, float(cp[2]), 0.0) - D.sp(o, rot, 0.0, 0.0, 0.0)).normalized()
			_tracer(cv, p, (side + Vector2(0, -0.8)).normalized(), 14.0)


# ================================================================ a_submarine
static func submarine(cv, rot: float, fn: String, wreck: bool, o: Vector2) -> void:
	var hl := 0.82
	var hw := 0.105
	var pts: Array = []
	for i in 16:
		var a := -PI + i * TAU / 16.0
		var cx := cos(a)
		var tap := 1.0 if cx > -0.3 else 0.7 + 0.3 * (1.0 + cx) / 0.7
		pts.append(Vector2(hl * cx, hw * sin(a) * tap))
	var hull := Color8(52, 58, 64)
	var dive := fn == "dive"
	if wreck:
		_wreck(cv, o, rot, pts, 4.0, hull, hl, hw, 2001, [[0.28, 0.0, 0.12, 0.04, 5.0]])
		return
	var mv := fn == "move" or dive
	if dive:
		var gh := PackedVector2Array()
		for l: Vector2 in pts:
			gh.append(D.sp(o, rot, l.x, l.y, 0))
		cv.poly(gh, Color(0.04, 0.08, 0.1, 0.4))
		var pb := D.sp(o, rot, 0.3, 0.0, 0)
		cv.line_v(pb, pb + Vector2(0, -6), Color8(40, 44, 48))
		cv.px(int(pb.x), int(pb.y) - 6, Color8(90, 96, 100))
		cv.outline(OUTL)
		for i in 8:
			var t := i / 8.0
			for sg: float in [-1.0, 1.0]:
				var p := D.sp(o, rot, 0.28 - t * 0.35, sg * (0.015 + t * 0.06), 0)
				_wp(cv, int(p.x), int(p.y), Color(WAKE.r, WAKE.g, WAKE.b, 0.5 * (1.0 - t)))
		return
	var r := prism(cv, o, Vector3.ZERO, pts, 4.0, rot, hull, 0.05, 2001, Color8(66, 72, 78))
	var items: Array = []
	items.append([-0.74, 0.0, func() -> void:
		bx(cv, o, rot, -0.74, 0.0, 3.0, 0.05, 0.01, 5.0, hull, 2010)
		bx(cv, o, rot, -0.74, 0.0, 3.0, 0.035, 0.09, 1.0, hull, 2011)])
	items.append([0.3, 0.0, func() -> void:
		var sl := bx(cv, o, rot, 0.28, 0.0, 4.0, 0.13, 0.045, 10.0, Color8(58, 64, 70), 2020, Color8(70, 76, 82))
		D.box_edges(cv, sl, Color8(58, 64, 70), 2021)
		_band(cv, sl, 0.55, 0.8)
		bx(cv, o, rot, 0.31, 0.0, 10.5, 0.03, 0.13, 0.8, Color8(58, 64, 70), 2022)
		var mt := D.sp(o, rot, 0.24, 0.0, 14.0)
		cv.line_v(mt, mt + Vector2(0, -5), Color8(40, 44, 48))
		var mt2 := D.sp(o, rot, 0.31, 0.0, 14.0)
		cv.line_v(mt2, mt2 + Vector2(0, -3), Color8(40, 44, 48))])
	_paint(rot, items)
	cv.outline(OUTL)
	# awash: water washes over the lower hull, foam along the deck line
	for sd in r.sides:
		cv.poly(P.sub(sd.quad, 0.0, -0.3, 1.0, 0.6), Color(0.16, 0.3, 0.36, 0.6))
	_water(cv, o, rot, pts, Vector2.ZERO, hl, hw, mv, 2001, 0.26)
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		var a: Vector2 = P.sub(q, 0, 0.6, 1, 0.6)[0]
		var b: Vector2 = P.sub(q, 0, 0.6, 1, 0.6)[1]
		for k in 6:
			var p := a.lerp(b, (k + P.hn(k, 2, 2030)) / 6.0)
			cv.px(int(p.x), int(p.y), FOAM)
	if mv:
		_spray(cv, o, rot, Vector2.ZERO, hl, 2001, 0.7)
	if fn == "fire":
		var d := _fdir(o, rot)
		var bow := D.sp(o, rot, hl, 0.0, 0)
		L.puff(cv, bow, 2.2, 0.5, SPRAY)
		for k in 5:
			var p := bow + d * (5.0 + k * 3.0)
			_wp(cv, int(p.x), int(p.y), Color(WAKE.r, WAKE.g, WAKE.b, 0.75 - k * 0.07))
			_wp(cv, int(p.x) + 1, int(p.y), Color(WAKE.r, WAKE.g, WAKE.b, 0.45))


# ================================================================ aircraft models (g5_air_mesh)
## b_recon_plane: rusty high-wing single-prop spotter, strut-braced wing, fixed gear, belly camera pod.
static func m_recon(m, st: Dictionary) -> void:
	MS.loft(m, [[-17, 0.5, 9.5, 11.0], [-10, 1.6, 8.0, 11.6], [-2, 2.8, 6.0, 12.4], [6, 3.0, 5.6, 12.4],
		[9.5, 2.8, 6.2, 11.6], [12, 2.2, 7.0, 10.6]], "body", 0.55, "engine")
	MS.box(m, Vector3(5.0, 0, 12.0), Vector3(3.2, 2.9, 0.9), "glass")
	for s: float in [-1.0, 1.0]:
		MS.slab(m, [Vector2(7.5, 2.0 * s), Vector2(7.5, 13.5 * s), Vector2(1.5, 13.5 * s), Vector2(1.0, 2.0 * s)], 13.4, 1.0, "body", 0.02)
		MS.slab(m, [Vector2(7.5, 13.5 * s), Vector2(7.3, 15.5 * s), Vector2(1.6, 15.5 * s), Vector2(1.5, 13.5 * s)], 13.4, 1.0, "team", 0.02)
		MS.slab(m, [Vector2(7.3, 15.5 * s), Vector2(6.5, 19.0 * s), Vector2(2.5, 19.0 * s), Vector2(1.6, 15.5 * s)], 13.4, 1.0, "body", 0.02)
		m.line(Vector3(4.5, 3.0 * s, 6.5), Vector3(5.5, 10.5 * s, 13.2), "metal")
		m.line(Vector3(2.5, 3.0 * s, 6.5), Vector3(2.2, 10.5 * s, 13.2), "metal")
		AP.wheel(m, 6.0, 4.4 * s, 1.4, 6.0)
	AP.wheel(m, -15.0, 0.0, 0.7, 9.6)
	MS.wings(m, -12.0, -16.5, -14.5, -17.0, 0.5, 7.0, 10.6, 0.6, "body2")
	MS.fin(m, [Vector2(-17.5, 10.8), Vector2(-12.5, 11.2), Vector2(-15.5, 18.0), Vector2(-18.0, 18.0)], 0.0, 0.8, "team")
	MS.cyl(m, Vector3(-1.0, 0, 5.0), Vector3(3.5, 0, 5.0), 1.5, "dark", 1.3, 6)
	MS.box(m, Vector3(3.8, 0, 4.8), Vector3(0.4, 0.9, 0.8), "glass")
	MS.cyl(m, Vector3(11.8, 0, 8.8), Vector3(13.4, 0, 8.8), 1.2, "dark", 0.3, 6)
	m.disc(Vector3(13.0, 0, 8.8), Vector3(1, 0, 0), 6.5, 2, SH.blade_ph(st, 2), st.spin)
	AP.nav(m, 4.5, 19.0, 13.8)
	if String(st.f) == "fire":
		m.mark(Vector3(1.5, 0, 3.2), "flash", Vector3(0, 0, -1), 0.6)
	if float(st.ab) > 0.0:
		m.mark(Vector3(9.0, 3.2, 7.0), "heat", Vector3(-1, 0, 0), 0.5)


## a_awacs: four-engine radar jet with a rotodome (team band round the dome).
static func m_awacs(m, st: Dictionary) -> void:
	MS.loft(m, [[-27, 1.0, 10.5, 12.5], [-21, 2.8, 7.5, 13.5], [-10, 3.6, 5.0, 13.0], [12, 3.6, 5.0, 13.0],
		[20, 3.2, 5.6, 12.2], [25, 2.0, 6.8, 10.8], [28, 0.6, 8.0, 9.2]], "body", 1.0, "body")
	MS.box(m, Vector3(23.0, 0, 11.6), Vector3(1.6, 2.2, 0.7), "glass")
	MS.wings(m, 7.0, -5.0, -10.0, -14.0, 3.0, 27.0, 6.6, 1.2, "body", 0.05)
	for s: float in [-1.0, 1.0]:
		for ny: Array in [[9.0, 2.5], [17.0, -2.8]]:
			var y: float = ny[0] * s
			var x: float = ny[1]
			MS.cyl(m, Vector3(x + 2.0, y, 4.6), Vector3(x - 6.0, y, 4.6), 1.7, "engine", 1.3, 6)
			MS.cyl(m, Vector3(x + 2.0, y, 4.6), Vector3(x + 2.4, y, 4.6), 1.5, "dark", 1.5, 6)
			if float(st.ab) > 0.0:
				m.mark(Vector3(x - 6.5, y, 4.6), "heat", Vector3(-1, 0, 0), 0.6)
	MS.fin(m, [Vector2(-27.5, 12.5), Vector2(-19.5, 13.0), Vector2(-24.0, 25.0), Vector2(-28.0, 25.0)], 0.0, 1.0, "team")
	MS.wings(m, -20.0, -25.5, -25.5, -28.5, 1.0, 11.0, 12.0, 0.8, "body2")
	MS.box(m, Vector3(-9.0, 0, 15.8), Vector3(2.4, 0.7, 3.0), "body2")
	MS.cyl(m, Vector3(-9.0, 0, 18.4), Vector3(-9.0, 0, 19.6), 10.5, "team", 10.5, 14)
	MS.cyl(m, Vector3(-9.0, 0, 19.6), Vector3(-9.0, 0, 20.8), 10.5, "dark", 9.0, 14)
	AP.gear(m, st, 21.0, -2.0, 4.5, 5.2)
	AP.nav(m, -14.0, 27.0, 7.9)


## AWACS "fire" = radar sweep pulse: faint rings round the rotodome.
static func _awacs_scan(cv, o: Vector2, rot: float, fn: String) -> void:
	if fn != "fire":
		return
	var c := MS.sp(o, rot, Vector3(-9.0, 0, 21.0))
	for k in 2:
		var rx := 13.0 + k * 5.0
		for i in 28:
			var a := i * TAU / 28.0
			if P.hn(i, k, 3301) < 0.3:
				continue
			cv.px(int(c.x + cos(a) * rx), int(c.y + sin(a) * rx * 0.5), Color(0.86, 0.95, 0.9, 0.55 - k * 0.2))
	cv.px(int(c.x), int(c.y) - 1, Color8(255, 240, 200))


## a_airlift: four-turboprop high-wing cargo plane; "drop" = ramp open, pallet extracted under a chute.
static func m_airlift(m, st: Dictionary) -> void:
	MS.loft(m, [[-25, 1.0, 12.5, 15.5], [-19, 3.2, 9.0, 15.8], [-12, 4.6, 4.2, 15.6], [14, 4.6, 4.0, 15.4],
		[19, 3.8, 4.6, 13.8], [23, 2.4, 6.0, 12.0], [25.5, 0.8, 7.4, 9.6]], "body", 0.75, "body")
	MS.box(m, Vector3(21.0, 0, 13.0), Vector3(1.8, 2.8, 0.8), "glass")
	MS.wings(m, 5.0, -6.0, 2.5, -3.5, 4.0, 31.0, 16.2, 1.3, "body", 0.0)
	for s: float in [-1.0, 1.0]:
		for y0: float in [10.0, 19.5]:
			var y := y0 * s
			MS.cyl(m, Vector3(8.5, y, 15.0), Vector3(-4.0, y, 15.0), 1.9, "engine", 1.3, 6)
			MS.cyl(m, Vector3(8.5, y, 15.0), Vector3(9.8, y, 15.0), 0.9, "dark", 0.3, 5)
			m.disc(Vector3(9.6, y, 15.0), Vector3(1, 0, 0), 5.0, 4, SH.blade_ph(st, 4, 0.3 + y0 * 0.1), st.spin)
		MS.box(m, Vector3(-1.0, 4.5 * s, 5.0), Vector3(6.0, 1.1, 1.8), "body2")
	MS.fin(m, [Vector2(-25.0, 15.0), Vector2(-15.0, 15.5), Vector2(-21.0, 29.0), Vector2(-25.5, 29.0)], 0.0, 1.0, "team")
	MS.wings(m, -18.0, -25.0, -23.0, -26.0, 1.0, 13.0, 15.2, 0.8, "body2")
	AP.gear(m, st, 18.0, -1.0, 4.5, 4.2)
	AP.nav(m, 3.5, 31.0, 16.2)
	if String(st.f) == "drop":
		AP.with(m, AP.at(Vector3(-18.5, 0, 8.8), Basis(Vector3(0, 1, 0), -0.45)), func() -> void:
			MS.box(m, Vector3(-4.5, 0, 0), Vector3(4.5, 3.4, 0.5), "body2"))
		MS.box(m, Vector3(-31.0, 0, 6.0), Vector3(3.0, 2.6, 2.0), "cargo")
		MS.box(m, Vector3(-31.0, 0, 8.1), Vector3(0.6, 2.7, 0.2), "team")
		MS.cyl(m, Vector3(-38.5, 0, 9.0), Vector3(-43.5, 0, 10.0), 6.5, "under", 2.2, 10)
		MS.cyl(m, Vector3(-43.5, 0, 10.0), Vector3(-44.5, 0, 10.0), 2.2, "team", 0.6, 8)
		for c: Vector3 in [Vector3(-38.5, 5.5, 13.0), Vector3(-38.5, -5.5, 13.0), Vector3(-38.5, 5.5, 5.0), Vector3(-38.5, -5.5, 5.0)]:
			m.line(Vector3(-33.5, 0, 7.5), c, "cable", true)
	if String(st.f) == "fire":  # defensive flares
		for k in 3:
			m.mark(Vector3(-14.0 - k * 4.0, (k - 1) * 5.0, 2.0 - k * 2.0), "glow")
			m.mark(Vector3(-14.0 - k * 4.0, (k - 1) * 5.0, 3.0 - k * 2.0), "fire", Vector3(1, 0, 0), 0.3)


## m_stealth_drone: graphite flying wing with sawtooth trailing edge, buried intakes, cyan exhaust slots.
static func m_stealth(m, st: Dictionary) -> void:
	MS.slab(m, [Vector2(12.0, 0.0), Vector2(4.0, 6.5), Vector2(-7.0, 5.5), Vector2(-9.0, 0.0), Vector2(-7.0, -5.5), Vector2(4.0, -6.5)], 6.5, 2.4, "body")
	for s: float in [-1.0, 1.0]:
		MS.slab(m, [Vector2(4.0, 6.5 * s), Vector2(-8.0, 21.0 * s), Vector2(-11.0, 20.0 * s), Vector2(-7.0, 5.5 * s)], 6.5, 1.2, "body")
		MS.slab(m, [Vector2(-8.0, 21.0 * s), Vector2(-9.0, 23.0 * s), Vector2(-11.5, 21.5 * s), Vector2(-11.0, 20.0 * s)], 6.5, 1.0, "team")
		MS.slab(m, [Vector2(-7.0, 5.5 * s), Vector2(-9.0, 9.5 * s), Vector2(-12.0, 8.0 * s), Vector2(-9.0, 2.0 * s)], 6.5, 1.0, "body2")
		MS.box(m, Vector3(2.5, 2.8 * s, 8.4), Vector3(1.2, 1.0, 0.5), "dark")
		MS.box(m, Vector3(-7.6, 2.4 * s, 7.6), Vector3(0.5, 1.4, 0.3), "cyan")
	MS.loft(m, [[-7.0, 1.0, 7.0, 8.0], [-2.0, 3.2, 7.0, 9.6], [5.0, 2.4, 7.0, 9.0], [10.0, 0.6, 7.0, 7.6]], "body2", 1.0, "body2")
	m.mark(Vector3(10.8, 0, 7.4), "cyanpx")
	AP.gear(m, st, 6.0, -3.0, 4.0, 5.3, 1.0)
	if String(st.f) == "fire":
		MS.box(m, Vector3(0.0, 0, 5.1), Vector3(3.0, 1.8, 0.2), "dark")
		m.mark(Vector3(2.0, 0, 3.5), "missile", Vector3(1, 0, -0.1), 1.0)
