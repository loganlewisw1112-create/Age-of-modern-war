extends RefCounted
## CN facility buildings (owner: ARTCN7; ART7E redraw 2026-10-27, G7_REFERENCE 6.2, 6.9, 13.9b). Modelled in real
## metres and rasterised by the faceted renderer with per-pixel depth (M.render_z), at the ONE real-world scale
## (fact art.scale: 4 m per 64x32 tile, 9.8 px per metre of height). Buildings (g7_cn_lib.bld rot schema):
##   g7_cn_gate     armoured vehicle gate for the 4x2 gate zone: wall line along x, lane along y (inside = -y);
##                  piers with hazard jambs, sliding leaves (closed) / swung in (open), gantry with lane signal,
##                  cameras, floodlights, wedge barrier, remote weapon station (fire) + counter-drone emitter
##   g7_cn_decon    drive-through decontamination: grated wash bay, two spray portals, splash walls, side
##                  walkways with foot-wash grates, control booth, CN agent tank   (+ active: spray, mist, beacons)
##   g7_cn_garage   12 m APC bay, framed roll-up door on +x (rot_2 = door on -x)    (+ open = occupied, lockdown)
##   g7_cn_helipad  6x6 pad fitted to the dropships, kerb lip, inset lights, fan blast circles   (+ lit)
##   g7_cn_pad      loading-pad TILE sheet (any w x h): see pad_frame() for the cell -> frame rule
const P = preload("res://tools/art/pix.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")
const H = preload("res://tools/art/g6_lib.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const M = preload("res://tools/art/g7_cn_mesh.gd")
const GR = preload("res://tools/art/g7_cn_gear.gd")
const RO = preload("res://tools/art/g7_rollout.gd")

const CONC := Color8(150, 148, 138)
const CONC_D := Color8(118, 116, 108)
const STEEL := Color8(84, 90, 96)
const DARK := Color8(46, 50, 52)
const ASPH := Color8(74, 76, 78)
const PAD := Color8(104, 106, 104)
const YEL := Color8(226, 184, 40)
const SIGN := Color8(38, 42, 44)
const STENCIL := Color8(226, 226, 214)
const CN_BLUE := Color8(110, 180, 255)
const AMBER := Color8(246, 178, 60)
const WATER := Color(0.62, 0.80, 0.98, 0.42)
const MIST := Color(0.85, 0.92, 1.0, 0.30)
const POOL := Color(1.0, 0.95, 0.78, 0.14)
const LAMP_G := Color8(150, 255, 170)
const LAMP_R := Color8(255, 70, 50)
const LAMP_W := Color8(255, 244, 210)
const DIM := Color8(96, 92, 80)
const X := Vector3(1, 0, 0)
const Y := Vector3(0, 1, 0)
const Z := Vector3(0, 0, 1)


static func _fin(cv, S: Array, o: Vector2, seed: int) -> void:
	M.shadow(cv, S, o)
	M.render_z(cv, S, o, seed)


## Alternating hazard stripes from a to b (n segments) on the surface with normal nl.
static func _hz(pt: Dictionary, T: Dictionary, a: Vector3, b: Vector3, nl: Vector3, n: int) -> void:
	for i in n:
		M.dline(pt, T, a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), GR.HAZ if i % 2 == 0 else GR.HAZ_D, nl)


## Diagonal hazard chevrons on a door jamb face (normal nl) centred at p, from z0 to z1, half width hw.
static func _jamb(pt: Dictionary, T: Dictionary, p: Vector3, nl: Vector3, hw: float, z0: float, z1: float) -> void:
	var al := RO._along(nl)
	var n := int((z1 - z0) / 0.5)
	for i in n:
		var z := z0 + i * 0.5
		M.dline(pt, T, p + nl * 0.01 - al * hw + Z * z, p + nl * 0.01 + al * hw + Z * (z + 0.3), GR.HAZ if i % 2 == 0 else GR.HAZ_D, nl)


## Wall face dressing: dark plinth, vertical panel joints, rain streaks and grime. c = face centre at z 0.
static func _wall(pt: Dictionary, T: Dictionary, c: Vector3, al: Vector3, ln: float, h: float, nl: Vector3, rp: Array,
		seed: int, step := 2.0) -> void:
	var c1 := c + nl * 0.012
	RO.quad(pt, T, c1 + Z * 0.3, al * ln * 0.5, Z * 0.3, C.ramp(P.mul(rp[2], 0.7))[1], nl)
	M.dline(pt, T, c1 + Z * 0.62 - al * ln * 0.5, c1 + Z * 0.62 + al * ln * 0.5, C.ca(rp[4], 0.5), nl)
	var np := maxi(1, int(ln / step))
	for i in range(1, np):
		var r := -ln * 0.5 + ln * float(i) / np
		M.dline(pt, T, c1 + al * r + Z * 0.65, c1 + al * r + Z * (h - 0.15), C.ca(rp[1], 0.8), nl)
	for j in int(ln * 6.0):
		var u := P.hn(j, seed, 41) - 0.5
		var z := 0.7 + (h - 0.9) * P.hn(j, seed, 43)
		if j % 3 == 0:
			M.dline(pt, T, c1 + al * u * ln + Z * (h - 0.1), c1 + al * u * ln + Z * (h - 0.5 - 1.1 * P.hn(j, seed, 3)), Color(0.22, 0.21, 0.18, 0.2), nl)
		else:
			M.dpx(pt, T, c1 + al * u * ln + Z * z, C.ca(rp[4], 0.45) if P.hn(j, seed, 47) < 0.3 else Color(0.2, 0.19, 0.16, 0.22 + 0.2 * (1.0 - z / h)), nl)


## Stencil blocks (n characters) centred at c on a face (along al, normal nl), character height hz.
static func _stencil(pt: Dictionary, T: Dictionary, c: Vector3, al: Vector3, nl: Vector3, n: int, hz: float, col := STENCIL) -> void:
	for i in n:
		var a := c + nl * 0.004 + al * (-0.5 * (n - 1) * 0.36 + i * 0.36)
		M.dline(pt, T, a - al * 0.1 + Z * hz * 0.5, a + al * 0.1 + Z * hz * 0.5, col, nl)
		M.dline(pt, T, a - al * 0.1 - Z * hz * 0.5, a + al * 0.06 - Z * hz * 0.5, col, nl)
		M.dpx(pt, T, a - al * 0.1, col, nl)


## Ground oil stains / tyre wear on part pa around c (spread r), z surface.
static func _stains(pa: Dictionary, T: Dictionary, c: Vector3, r: Vector2, n: int, seed: int) -> void:
	for j in n:
		var p := c + Vector3((P.hn(j, seed, 61) - 0.5) * 2.0 * r.x, (P.hn(j, seed, 67) - 0.5) * 2.0 * r.y, 0.003)
		var s := 0.2 + 0.4 * P.hn(j, seed, 71)
		M.dpoly(pa, T, [p + Vector3(-s, -s * 0.5, 0), p + Vector3(s * 0.8, -s * 0.7, 0), p + Vector3(s, s * 0.4, 0), p + Vector3(-s * 0.4, s * 0.8, 0)],
			Color(0.08, 0.08, 0.07, 0.14 + 0.1 * P.hn(j, seed, 73)), Z)


# ------------------------------------------------------------------ gate (4 x 2 tiles = 16 x 8 m)
static func gate(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	var S: Array = []
	var T := M.pose(o, float(f) * PI / 2.0)
	var open := bool(opt.get("open", false))
	var conc: Array = C.ramp(CONC)
	var cd: Array = C.ramp(CONC_D)
	var st: Array = C.ramp(STEEL)
	var dk: Array = C.ramp(DARK)
	var zs := 0.125
	# --- apron + lane: asphalt, kerbs, centre dashes, stop line, gate-line hazard strip, ruts, drain
	var pa := M.part(S, -2)
	M.box(pa, T, Vector3(0, 0, 0.06), Vector3(7.9, 3.9, 0.06), cd, Vector3(0.04, 0.04, 0.04))
	RO.quad(pa, T, Vector3(0, 0, zs + 0.001), X * 4.6, Y * 3.88, ASPH, Z)
	for s in [-1.0, 1.0]:
		M.dline(pa, T, Vector3(s * 4.6, -3.85, zs + 0.002), Vector3(s * 4.6, 3.85, zs + 0.002), C.ca(conc[4], 0.8), Z)
		for k in 2:   # tyre ruts
			M.dline(pa, T, Vector3(s * (1.0 + k * 1.3), -3.8, zs + 0.002), Vector3(s * (1.0 + k * 1.3), 3.8, zs + 0.002), Color(0.1, 0.1, 0.09, 0.2), Z)
	for i in 4:
		M.dline(pa, T, Vector3(0, -3.6 + i * 2.0, zs + 0.003), Vector3(0, -2.7 + i * 2.0, zs + 0.003), STENCIL, Z)
	M.dline(pa, T, Vector3(-4.4, 1.55, zs + 0.003), Vector3(4.4, 1.55, zs + 0.003), STENCIL, Z)
	M.dline(pa, T, Vector3(-4.4, 1.62, zs + 0.003), Vector3(4.4, 1.62, zs + 0.003), STENCIL, Z)
	_hz(pa, T, Vector3(-4.5, 0.3, zs + 0.003), Vector3(4.5, 0.3, zs + 0.003), Z, 18)
	M.dline(pa, T, Vector3(-4.7, 0.0, zs + 0.003), Vector3(4.7, 0.0, zs + 0.003), Color8(36, 38, 40), Z)   # leaf track
	RO.quad(pa, T, Vector3(-3.0, -2.6, zs + 0.003), X * 0.5, Y * 0.18, Color8(40, 42, 42), Z)   # drain grate
	_stains(pa, T, Vector3(0, 0, zs), Vector2(3.5, 3.4), 7, 11 + f)
	# --- piers with hazard jambs, caps, signal lamps, floodlights, cameras
	for s in [-1.0, 1.0]:
		var pp := M.part(S, 0)
		M.box(pp, T, Vector3(s * 6.3, 0, 1.9), Vector3(1.5, 1.3, 1.9), conc, Vector3(0.1, 0.1, 0.1))
		_wall(pp, T, Vector3(s * 6.3, 1.3, 0), X, 3.0, 3.8, Y, conc, 21 + int(s), 1.0)
		_wall(pp, T, Vector3(s * 6.3, -1.3, 0), X, 3.0, 3.8, -Y, conc, 23 + int(s), 1.0)
		_wall(pp, T, Vector3(s * 7.8, 0, 0), Y, 2.6, 3.8, X * s, conc, 25 + int(s), 1.3)
		_jamb(pp, T, Vector3(s * 4.8, 0, 0), -X * s, 0.9, 0.3, 3.5)
		M.box(pp, T, Vector3(s * 6.3, 0, 3.92), Vector3(1.6, 1.4, 0.12), cd)
		M.box(pp, T, Vector3(s * 5.25, 1.36, 3.0), Vector3(0.18, 0.06, 0.4), dk)   # signal head
		M.dpx(pp, T, Vector3(s * 5.25, 1.43, 3.2), LAMP_R if not open else Color8(90, 40, 34), Y)
		M.dpx(pp, T, Vector3(s * 5.25, 1.43, 2.8), LAMP_G if open else Color8(40, 80, 50), Y)
		RO.flood(pp, pa, T, Vector3(s * 6.3, 1.3, 3.4), Y)
		M.box(pp, T, Vector3(s * 6.6, 1.32, 2.3), Vector3(0.45, 0.02, 0.28), conc, Vector3.ZERO, {"team": true})   # team plate
		var pc := M.part(S, 2)   # security camera on the cap, looking out
		M.box(pc, T, Vector3(s * 6.9, 1.0, 4.18), Vector3(0.12, 0.25, 0.1), C.ramp(Color8(200, 200, 194)))
		M.dpx(pc, T, Vector3(s * 6.9, 1.27, 4.18), Color8(20, 24, 30), Y)
		M.dpx(pc, T, Vector3(s * 6.98, 1.1, 4.3), LAMP_R)
	# --- leaves: closed = two sliding armoured leaves on the wall line; open = swung inside (-y) against the jambs
	for s in [-1.0, 1.0]:
		var pl := M.part(S, 1)
		var c := Vector3(s * 2.4, 0, 1.55) if not open else Vector3(s * 4.5, -2.45, 1.55)
		var hh := Vector3(2.32, 0.14, 1.5) if not open else Vector3(0.14, 2.32, 1.5)
		M.box(pl, T, c, hh, st, Vector3(0.02, 0.02, 0.02))
		var nl: Vector3 = Y if not open else -X * s
		var al := RO._along(nl)
		var fc: Vector3 = c + nl * (hh.y if not open else hh.x) + nl * 0.01
		for i in 8:   # ribs
			var r := -2.0 + i * 0.57
			M.dline(pl, T, fc + al * r - Z * 1.3, fc + al * r + Z * 1.35, C.ca(st[1], 0.95), nl)
			M.dline(pl, T, fc + al * (r + 0.06) - Z * 1.3, fc + al * (r + 0.06) + Z * 1.35, C.ca(st[3], 0.45), nl)
		_hz(pl, T, fc - al * 2.25 - Z * 1.15, fc + al * 2.25 - Z * 1.15, nl, 12)
		_hz(pl, T, fc - al * 2.25 - Z * 1.25, fc + al * 2.25 - Z * 1.25, nl, 12)
		M.dline(pl, T, fc - al * 2.3 + Z * 1.45, fc + al * 2.3 + Z * 1.45, C.ca(st[4], 0.6), nl)
		if not open and s < 0.0:   # STOP plate
			RO.quad(pl, T, fc + al * 1.0 + Z * 0.45, al * 0.32, Z * 0.32, Color8(190, 40, 34), nl)
			M.dline(pl, T, fc + nl * 0.005 + al * 0.8 + Z * 0.45, fc + nl * 0.005 + al * 1.2 + Z * 0.45, STENCIL, nl)
	# --- overhead gantry: beam on the caps, ID sign with lane signal, downlights
	var pg := M.part(S, 2)
	M.box(pg, T, Vector3(0, 0, 4.42), Vector3(4.9, 0.28, 0.32), st, Vector3(0.02, 0.02, 0.02))
	var sg := Vector3(0, 0.3, 4.42)
	RO.quad(pg, T, sg, X * 3.2, Z * 0.26, SIGN, Y)
	M.dline(pg, T, sg + Vector3(-3.1, 0.005, -0.18), sg + Vector3(3.1, 0.005, -0.18), CN_BLUE, Y)
	_stencil(pg, T, sg + Vector3(-1.5, 0, 0.04), X, Y, 5, 0.22)
	var lc := sg + Vector3(1.9, 0.006, 0.02)
	if open:   # green down arrow
		M.dline(pg, T, lc + Z * 0.18, lc - Z * 0.14, LAMP_G, Y)
		M.dline(pg, T, lc - Z * 0.14 - X * 0.16 + Z * 0.14, lc - Z * 0.14, LAMP_G, Y)
		M.dline(pg, T, lc - Z * 0.14 + X * 0.16 + Z * 0.14, lc - Z * 0.14, LAMP_G, Y)
	else:   # red X
		M.dline(pg, T, lc - X * 0.16 + Z * 0.16, lc + X * 0.16 - Z * 0.16, LAMP_R, Y)
		M.dline(pg, T, lc - X * 0.16 - Z * 0.16, lc + X * 0.16 + Z * 0.16, LAMP_R, Y)
	for s in [-1.0, 1.0]:   # downlights + their pools on the lane
		M.dpx(pg, T, Vector3(s * 2.2, 0.2, 4.08), LAMP_W)
		M.dpoly(pa, T, [Vector3(s * 2.2 - 1.5, -1.0, zs + 0.004), Vector3(s * 2.2 + 1.5, -1.0, zs + 0.004), Vector3(s * 2.2 + 1.2, 1.4, zs + 0.004), Vector3(s * 2.2 - 1.2, 1.4, zs + 0.004)], POOL, Z)
	# --- anti-vehicle wedge barrier outside the gate: raised (closed) / flush (open)
	var pw := M.part(S, 0)
	if not open:
		M.box(pw, T, Vector3(0, 2.75, 0.42), Vector3(3.9, 0.4, 0.3), dk, Vector3(0.0, 0.25, 0.0))
		_hz(pw, T, Vector3(-3.85, 3.16, 0.4), Vector3(3.85, 3.16, 0.4), Y, 16)
		_hz(pw, T, Vector3(-3.85, 3.16, 0.3), Vector3(3.85, 3.16, 0.3), Y, 16)
	else:
		RO.quad(pa, T, Vector3(0, 2.75, zs + 0.004), X * 3.9, Y * 0.4, dk[2], Z)
		_hz(pa, T, Vector3(-3.85, 2.4, zs + 0.005), Vector3(3.85, 2.4, zs + 0.005), Z, 16)
	# --- remote weapon station (west pier) + counter-drone emitter (east pier)
	var pr := M.part(S, 3)
	M.box(pr, T, Vector3(-6.3, 0.0, 4.32), Vector3(0.45, 0.45, 0.28), C.ramp(Color8(76, 82, 74)), Vector3(0.06, 0.06, 0.06))
	M.box(pr, T, Vector3(-6.3, 0.1, 4.75), Vector3(0.28, 0.3, 0.16), C.ramp(Color8(70, 76, 70)))
	M.cyl(pr, T, Vector3(-6.3, 0.95, 4.72), Y, 0.06, 0.6, 5, C.ramp(GR.GUNM), {"edge": false})
	M.dpx(pr, T, Vector3(-6.05, 0.42, 4.78), Color8(60, 140, 200), Y)
	if bool(opt.get("fire", false)):
		var mz := Vector3(-6.3, 1.65, 4.72)
		for k in 6:
			M.dpx(pr, T, mz + Vector3((k % 3 - 1) * 0.08, 0.08 * k, (k / 3) * 0.08), GR.FLASH if k < 3 else GR.FLASH_O)
	M.cyl(pr, T, Vector3(6.3, 0, 4.6), Z, 0.08, 0.6, 4, dk, {"edge": false})
	M.box(pr, T, Vector3(6.3, 0.1, 5.3), Vector3(0.1, 0.4, 0.28), C.ramp(Color8(196, 200, 204)))
	for k in 3:
		M.dpx(pr, T, Vector3(6.41, -0.15 + k * 0.25, 5.3), CN_BLUE, X)
	M.dpx(pr, T, Vector3(6.3, 0.1, 5.62), LAMP_R)
	_fin(cv, S, o, 31 + f)


# ------------------------------------------------------------------ decontamination (3 x 3 tiles = 12 m)
static func decon(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	var S: Array = []
	var T := M.pose(o, float(f) * PI / 2.0)
	var on := bool(opt.get("active", false))
	var conc: Array = C.ramp(CONC)
	var cd: Array = C.ramp(CONC_D)
	var st: Array = C.ramp(STEEL)
	var yb: Array = C.ramp(Color8(214, 176, 52))
	var zs := 0.125
	# --- slab, grated wash bay with drain channels, entry/exit hazard bars, side walkways with foot-wash grates
	var pa := M.part(S, -2)
	M.box(pa, T, Vector3(0, 0, 0.06), Vector3(5.9, 5.9, 0.06), cd, Vector3(0.04, 0.04, 0.04))
	RO.quad(pa, T, Vector3(0, 0, zs + 0.001), X * 3.5, Y * 5.6, Color8(66, 72, 74), Z)
	for i in 23:
		M.dline(pa, T, Vector3(-3.4, -5.5 + i * 0.5, zs + 0.002), Vector3(3.4, -5.5 + i * 0.5, zs + 0.002), Color(0.12, 0.14, 0.15, 0.55), Z)
	for s in [-1.0, 1.0]:
		RO.quad(pa, T, Vector3(s * 3.3, 0, zs + 0.003), X * 0.12, Y * 5.5, Color8(34, 40, 44), Z)
		_hz(pa, T, Vector3(-3.5, s * 5.55, zs + 0.003), Vector3(3.5, s * 5.55, zs + 0.003), Z, 14)
		RO.quad(pa, T, Vector3(s * 4.85, 0, zs + 0.001), X * 0.95, Y * 5.7, conc[2], Z)
		M.dline(pa, T, Vector3(s * 3.9, -5.7, zs + 0.003), Vector3(s * 3.9, 5.7, zs + 0.003), YEL, Z)
		M.dline(pa, T, Vector3(s * 5.75, -5.7, zs + 0.003), Vector3(s * 5.75, 5.7, zs + 0.003), YEL, Z)
		for k in 2:
			RO.quad(pa, T, Vector3(s * 4.85, -2.6 + k * 5.2, zs + 0.003), X * 0.7, Y * 0.5, Color8(46, 70, 84), Z)
			for j in 4:
				M.dline(pa, T, Vector3(s * 4.85 - 0.6, -2.95 + k * 5.2 + j * 0.23, zs + 0.004), Vector3(s * 4.85 + 0.6, -2.95 + k * 5.2 + j * 0.23, zs + 0.004), Color8(30, 46, 56), Z)
	if on:   # wet floor sheen + puddles
		RO.quad(pa, T, Vector3(0, 0, zs + 0.004), X * 3.3, Y * 3.0, Color(0.55, 0.72, 0.9, 0.22), Z)
		for j in 6:
			var p := Vector3(-2.8 + 5.6 * P.hn(j, 5, 3), -4.5 + 9.0 * P.hn(j, 5, 7), zs + 0.005)
			M.dpoly(pa, T, [p + Vector3(-0.5, 0, 0), p + Vector3(0, -0.3, 0), p + Vector3(0.6, 0, 0), p + Vector3(0, 0.35, 0)], Color(0.7, 0.85, 1.0, 0.3), Z)
	else:
		_stains(pa, T, Vector3(0, 0, zs), Vector2(3.0, 5.0), 6, 17 + f)
	# --- splash walls between the portals
	for s in [-1.0, 1.0]:
		var pw := M.part(S, 0)
		M.box(pw, T, Vector3(s * 3.62, 0, 0.7), Vector3(0.08, 2.4, 0.6), st)
		for i in 5:
			M.dline(pw, T, Vector3(s * 3.71, -2.4 + i * 1.2, 0.15), Vector3(s * 3.71, -2.4 + i * 1.2, 1.25), C.ca(st[1], 0.9), X * s)
		_hz(pw, T, Vector3(s * 3.71, -2.35, 1.2), Vector3(s * 3.71, 2.35, 1.2), X * s, 10)
	# --- spray portals (yellow gantry, steel posts, spray manifold + nozzles, beacons, ready lamps)
	for k in 2:
		var py := -2.6 + k * 5.2
		var pp := M.part(S, 1)
		for s in [-1.0, 1.0]:
			M.box(pp, T, Vector3(s * 3.85, py, 2.3), Vector3(0.2, 0.2, 2.3), st)
			M.dline(pp, T, Vector3(s * 3.63, py, 0.5), Vector3(s * 3.63, py, 4.1), C.ramp(Color8(170, 176, 180))[2], -X * s)
			for z in [0.8, 1.6, 2.4, 3.2]:
				M.dpx(pp, T, Vector3(s * 3.62, py, z), CN_BLUE if on else Color8(70, 100, 130), -X * s)
			M.dpx(pp, T, Vector3(s * 3.85, py + 0.21, 2.0), (AMBER if on else LAMP_G), Y)
			M.dpx(pp, T, Vector3(s * 3.9, py, 4.98), AMBER if on else DIM)
		M.box(pp, T, Vector3(0, py, 4.72), Vector3(4.1, 0.24, 0.2), yb)
		M.cyl(pp, T, Vector3(0, py, 4.36), X, 0.07, 3.55, 5, C.ramp(Color8(170, 176, 180)), {"edge": false})
		for i in 8:
			M.dpx(pp, T, Vector3(-3.15 + i * 0.9, py, 4.26), CN_BLUE if on else Color8(70, 100, 130))
		if k == 1:   # front sign: DECON plate with the CN stripe
			RO.quad(pp, T, Vector3(0, py + 0.245, 4.72), X * 1.6, Z * 0.16, SIGN, Y)
			_stencil(pp, T, Vector3(0, py + 0.246, 4.74), X, Y, 5, 0.16)
			M.dline(pp, T, Vector3(-1.5, py + 0.25, 4.6), Vector3(1.5, py + 0.25, 4.6), CN_BLUE, Y)
		if on:   # spray sheets from the manifold
			var pv := M.part(S, 2)
			M.dpoly(pv, T, [Vector3(-3.5, py, 4.2), Vector3(3.5, py, 4.2), Vector3(3.5, py + 0.5, 0.2), Vector3(-3.5, py + 0.5, 0.2)], WATER, Y)
			for i in 12:
				var u := -3.3 + i * 0.6
				M.dline(pv, T, Vector3(u, py, 4.2), Vector3(u + 0.1, py + 0.5, 0.3), Color(0.85, 0.94, 1.0, 0.5), Y)
	# --- control booth (back left) with lit window, CN agent tank (back right) feeding the manifolds
	var pb := M.part(S, 0)
	M.box(pb, T, Vector3(-4.9, -4.7, 1.3), Vector3(0.9, 0.9, 1.3), conc, Vector3(0.05, 0.05, 0.05))
	M.box(pb, T, Vector3(-4.9, -4.7, 2.68), Vector3(1.05, 1.05, 0.08), st)
	RO.window(pb, T, Vector3(-4.0, -4.7, 1.6), 1.1, 0.6, X, true)
	RO.window(pb, T, Vector3(-4.9, -3.8, 1.6), 0.9, 0.6, Y, true)
	_wall(pb, T, Vector3(-4.9, -3.8, 0), X, 1.8, 2.6, Y, conc, 51, 0.9)
	M.dpx(pb, T, Vector3(-4.3, -3.78, 2.3), LAMP_W, Y)
	M.box(M.part(S, 1), T, Vector3(-4.9, -4.7, 2.8), Vector3(0.6, 0.6, 0.04), conc, Vector3.ZERO, {"team": true})   # roof ID panel
	var pt := M.part(S, 1)
	var tk: Array = C.ramp(Color8(196, 200, 196))
	M.cyl(pt, T, Vector3(4.9, -4.7, 1.35), Z, 0.75, 1.2, 12, tk, {"cap_t": 3})
	M.cyl(pt, T, Vector3(4.9, -4.7, 2.62), Z, 0.5, 0.07, 10, tk, {"cap_t": 4}, 0.0, 0.25)
	for zz in [0.6, 2.1]:
		M.cyl(pt, T, Vector3(4.9, -4.7, zz), Z, 0.78, 0.05, 12, st, {"caps": false})
	M.dline(pt, T, Vector3(5.45, -4.15, 0.9), Vector3(5.45, -4.15, 1.9), CN_BLUE, Vector3(0.7, 0.7, 0))
	M.dpx(pt, T, Vector3(5.47, -4.13, 2.1), STENCIL, Vector3(0.7, 0.7, 0))
	M.cyl(pt, T, Vector3(4.4, -3.4, 2.3), Y, 0.08, 0.9, 5, st, {"edge": false})
	M.cyl(pt, T, Vector3(4.15, -2.6, 3.5), Z, 0.08, 1.2, 5, st, {"edge": false})
	RO.flood(pb, pa, T, Vector3(-4.0, -5.3, 2.4), X)
	_fin(cv, S, o, 41 + f)
	if on:   # drifting mist over the bay (2D overlay after the render)
		for i in 12:
			var w := M.scr(T, Vector3(-2.8 + 5.6 * P.hn(i, 3, 5), -4.0 + 8.0 * P.hn(i, 3, 9), 1.2 + 2.6 * P.hn(i, 3, 13)))
			cv.ellipse(w.x, w.y, 5.0 + 3.0 * P.hn(i, 4, 1), 2.6, MIST)


# ------------------------------------------------------------------ garage (3 x 3 tiles; 12 m APC bay)
## DL7-3 scale: bay shell x -5.4..4.2, y +-3.3, 4.9 m high; a 1 m deep door reveal (x 3.2..4.2) with hazard jambs and
## a 3.8 m x 3.9 m opening, so the 8 m x 2.9 m strike APC (3.3 m over its pods) drives in. Door on local +x.
## closed: roll-up door down, green status lamp. open (occupied): door rolled into its drum, lit bay, the parked
## APC nose in the doorway, amber beacon. lockdown: armoured blast shutter sealed flush, red beacons.
static func garage(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	var S: Array = []
	var T := M.pose(o, float(f) * PI / 2.0)
	var lock := bool(opt.get("lockdown", false))
	var open := bool(opt.get("open", false)) and not lock
	var conc: Array = C.ramp(CONC)
	var cd: Array = C.ramp(CONC_D)
	var st: Array = C.ramp(STEEL)
	var dk: Array = C.ramp(DARK)
	var zs := 0.125
	# --- slab + apron: asphalt lead-in, lane edges, threshold chevrons, drain, stains
	var pa := M.part(S, -2)
	M.box(pa, T, Vector3(0, 0, 0.06), Vector3(5.9, 5.9, 0.06), cd, Vector3(0.04, 0.04, 0.04))
	RO.quad(pa, T, Vector3(5.05, 0, zs + 0.001), X * 0.85, Y * 2.4, ASPH, Z)
	for s in [-1.0, 1.0]:
		M.dline(pa, T, Vector3(4.25, s * 2.0, zs + 0.002), Vector3(5.9, s * 2.0, zs + 0.002), AMBER, Z)
	for i in 8:
		var y0 := -1.9 + i * 0.475
		M.dline(pa, T, Vector3(4.3, y0, zs + 0.003), Vector3(4.65, y0 + 0.24, zs + 0.003), GR.HAZ if i % 2 == 0 else GR.HAZ_D, Z)
	RO.quad(pa, T, Vector3(5.6, 0, zs + 0.003), X * 0.12, Y * 1.6, Color8(40, 42, 42), Z)
	_stains(pa, T, Vector3(4.9, 0, zs), Vector2(0.7, 1.6), 5, 7 + f)
	# --- shell: main block + front reveal (two pilasters and a header)
	var pm := M.part(S, 0)
	M.box(pm, T, Vector3(-1.1, 0, 2.45), Vector3(4.3, 3.3, 2.45), conc, Vector3(0.1, 0.1, 0.1))
	for s in [-1.0, 1.0]:
		M.box(pm, T, Vector3(3.7, s * 2.6, 2.45), Vector3(0.5, 0.7, 2.45), conc)
	M.box(pm, T, Vector3(3.7, 0, 4.4), Vector3(0.5, 1.9, 0.5), conc)
	_wall(pm, T, Vector3(-1.1, 3.3, 0), X, 8.6, 4.9, Y, conc, 61 + f)
	_wall(pm, T, Vector3(-1.1, -3.3, 0), X, 8.6, 4.9, -Y, conc, 63 + f)
	_wall(pm, T, Vector3(-5.4, 0, 0), Y, 6.6, 4.9, -X, conc, 65 + f)
	for s in [-1.0, 1.0]:   # pilaster fronts: plinth + hazard jambs on the reveal edges
		RO.quad(pm, T, Vector3(4.212, s * 2.6, 0.3), Y * 0.7, Z * 0.3, C.ramp(P.mul(CONC, 0.7))[1], X)
		_jamb(pm, T, Vector3(4.2, s * 2.12, 0), X, 0.18, 0.25, 3.9)
		_jamb(pm, T, Vector3(3.7, s * 1.9, 0), -Y * s, 0.45, 0.25, 3.8)
	M.dline(pm, T, Vector3(4.212, -1.9, 3.92), Vector3(4.212, 1.9, 3.92), C.ca(cd[0], 0.9), X)
	RO.quad(pm, T, Vector3(4.212, 0, 4.45), Y * 1.7, Z * 0.2, SIGN, X)   # bay sign
	M.dline(pm, T, Vector3(4.216, -1.6, 4.3), Vector3(4.216, 1.6, 4.3), CN_BLUE, X)
	_stencil(pm, T, Vector3(4.212, -0.3, 4.5), Y, X, 5, 0.16)
	M.box(pm, T, Vector3(4.3, 1.45, 4.5), Vector3(0.1, 0.22, 0.14), dk)
	M.dpx(pm, T, Vector3(4.41, 1.45, 4.5), LAMP_R if lock else (AMBER if open else LAMP_G), X)
	# side door, louvres, wall pack, conduit (+y face)
	RO.quad(pm, T, Vector3(-3.6, 3.312, 1.05), X * 0.5, Z * 1.05, st[1], Y)
	M.dline(pm, T, Vector3(-3.3, 3.316, 0.95), Vector3(-3.2, 3.316, 0.95), C.ca(st[4], 0.9), Y)
	M.dpx(pm, T, Vector3(-3.0, 3.316, 1.3), GR.LED_G, Y)
	M.box(pm, T, Vector3(-3.6, 3.55, 2.3), Vector3(0.65, 0.25, 0.05), st)
	M.dpx(pm, T, Vector3(-3.6, 3.62, 2.22), LAMP_W)
	for k in 2:
		var vx := -0.6 + k * 2.6
		RO.quad(pm, T, Vector3(vx, 3.314, 3.9), X * 0.55, Z * 0.35, Color8(52, 56, 60), Y)
		for j in 4:
			M.dline(pm, T, Vector3(vx - 0.5, 3.318, 3.65 + j * 0.17), Vector3(vx + 0.5, 3.318, 3.65 + j * 0.17), Color8(92, 98, 102), Y)
	M.cyl(pm, T, Vector3(2.6, 3.38, 2.4), Z, 0.07, 2.2, 4, st, {"edge": false})
	M.box(pm, T, Vector3(2.6, 3.42, 0.9), Vector3(0.25, 0.1, 0.3), st)
	RO.flood(pm, pa, T, Vector3(1.4, 3.3, 4.3), Y)
	RO.flood(pm, pa, T, Vector3(4.2, -2.6, 4.6), X)
	# --- door states
	var pd := M.part(S, 1)
	if lock:   # armoured blast shutter sealed flush with the pilasters, hazard X, red seal lamps
		M.box(pd, T, Vector3(4.24, 0, 1.97), Vector3(0.06, 1.95, 1.95), C.ramp(Color8(122, 70, 58)))
		for i in 6:
			M.dline(pd, T, Vector3(4.31, -1.9, 0.3 + i * 0.62), Vector3(4.31, 1.9, 0.3 + i * 0.62), C.ca(dk[1], 0.7), X)
		_hz(pd, T, Vector3(4.31, -1.85, 0.2), Vector3(4.31, 1.85, 3.75), X, 14)
		_hz(pd, T, Vector3(4.31, -1.85, 3.75), Vector3(4.31, 1.85, 0.2), X, 14)
		for s in [-1.0, 1.0]:
			M.dpx(pd, T, Vector3(4.31, s * 1.7, 3.6), LAMP_R, X)
	elif open:   # bay lit inside, door rolled up into its drum, the parked APC nose in the doorway
		RO.quad(pd, T, Vector3(3.212, 0, 1.95), Y * 1.9, Z * 1.95, Color8(30, 32, 34), X)
		M.dline(pd, T, Vector3(3.215, -1.8, 3.75), Vector3(3.215, 1.8, 3.75), Color8(220, 210, 170), X)
		for s in [-1.0, 1.0]:
			M.dpx(pd, T, Vector3(3.215, s * 1.0, 3.7), LAMP_W, X)
		M.dpoly(pa, T, [Vector3(3.2, -1.9, zs + 0.004), Vector3(4.2, -1.9, zs + 0.004), Vector3(5.6, -1.4, zs + 0.004), Vector3(5.6, 1.4, zs + 0.004), Vector3(4.2, 1.9, zs + 0.004), Vector3(3.2, 1.9, zs + 0.004)], POOL, Z)
		M.box(pd, T, Vector3(3.95, 0, 3.72), Vector3(0.22, 1.92, 0.18), st)
		var pv := M.part(S, 1)
		var hull: Array = C.ramp(P.mul(Color8(104, 112, 100), 0.62))
		M.box(pv, T, Vector3(3.55, 0, 1.45), Vector3(0.35, 1.42, 0.85), hull)
		M.box(pv, T, Vector3(3.9, 0, 1.05), Vector3(0.12, 1.3, 0.38), hull, Vector3(0.0, 0.0, 0.12))
		M.box(pv, T, Vector3(3.4, 0, 2.55), Vector3(0.3, 0.9, 0.28), hull)
		RO.quad(pv, T, Vector3(3.91, 0, 2.05), Y * 1.0, Z * 0.18, Color8(40, 64, 78), X)
		for s in [-1.0, 1.0]:
			M.cyl(pv, T, Vector3(3.7, s * 1.25, 0.5), Y, 0.45, 0.16, 8, C.ramp(Color8(36, 38, 38)), {"cap_t": 1})
			M.dpx(pv, T, Vector3(4.03, s * 1.0, 1.3), LAMP_W, X)
			M.dpx(pv, T, Vector3(4.03, s * 1.1, 1.3), Color8(255, 220, 160), X)
	else:   # roll-up door down: slats, vision panels, bottom seal
		M.box(pd, T, Vector3(3.24, 0, 1.95), Vector3(0.04, 1.9, 1.95), st)
		for i in 12:
			var z := 0.25 + i * 0.3
			M.dline(pd, T, Vector3(3.285, -1.88, z), Vector3(3.285, 1.88, z), C.ca(st[1], 0.95), X)
			M.dline(pd, T, Vector3(3.285, -1.88, z + 0.08), Vector3(3.285, 1.88, z + 0.08), C.ca(st[3], 0.5), X)
		for i in 4:
			RO.quad(pd, T, Vector3(3.285, -1.2 + i * 0.8, 2.55), Y * 0.22, Z * 0.1, Color8(36, 52, 62), X)
		M.dline(pd, T, Vector3(3.285, -1.88, 0.08), Vector3(3.285, 1.88, 0.08), Color8(24, 24, 24), X)
	# --- roof: parapet, membrane seams, skylights, exhaust fans, beacon, ID panel
	var pr := M.part(S, 2)
	for e in [[Vector3(-0.6, -3.18, 5.02), Vector3(4.8, 0.12, 0.12)], [Vector3(-0.6, 3.18, 5.02), Vector3(4.8, 0.12, 0.12)],
			[Vector3(-5.28, 0, 5.02), Vector3(0.12, 3.3, 0.12)], [Vector3(4.08, 0, 5.02), Vector3(0.12, 3.3, 0.12)]]:
		M.box(pr, T, e[0], e[1], cd)
	var rf := M.part(S, 1)
	for i in range(1, 5):
		M.dline(rf, T, Vector3(-5.2 + i * 1.85, -3.0, 4.905), Vector3(-5.2 + i * 1.85, 3.0, 4.905), C.ca(cd[1], 0.7), Z)
	for k in 2:
		RO.quad(rf, T, Vector3(-3.4 + k * 3.4, 0, 4.91), X * 0.5, Y * 2.2, Color8(70, 104, 120), Z)
		M.dline(rf, T, Vector3(-3.85 + k * 3.4, -2.1, 4.915), Vector3(-3.85 + k * 3.4, 2.1, 4.915), Color(1, 1, 1, 0.45), Z)
	for j in 18:
		M.dpx(rf, T, Vector3(-5.0 + 8.8 * P.hn(j, f, 71), -3.0 + 6.0 * P.hn(j, f, 73), 4.906), Color(0.2, 0.2, 0.18, 0.25), Z)
	M.box(rf, T, Vector3(-1.7, -1.9, 4.92), Vector3(0.9, 0.9, 0.012), conc, Vector3.ZERO, {"team": true})
	for k in 2:
		var fc := Vector3(-4.2 + k * 2.3, 2.1, 5.15)
		M.box(pr, T, fc, Vector3(0.45, 0.45, 0.25), st, Vector3(0.04, 0.04, 0.04))
		M.cyl(pr, T, fc + Z * 0.27, Z, 0.32, 0.03, 8, dk, {"cap_t": 0})
	var bc := Vector3(3.4, -2.4, 5.2)
	M.cyl(pr, T, bc, Z, 0.16, 0.18, 6, C.ramp(LAMP_R if lock else (AMBER if open else Color8(150, 120, 70))), {"cap_t": 4})
	if lock or open:
		M.dpx(pr, T, bc + Vector3(0.0, 0.1, 0.1), LAMP_W)
	for s in [-1.0, 1.0]:   # bollards at the door
		var pbo := M.part(S, 1)
		M.cyl(pbo, T, Vector3(4.65, s * 2.45, 0.55), Z, 0.14, 0.45, 6, C.ramp(GR.HAZ), {"cap_t": 3})
		M.dline(pbo, T, Vector3(4.79, s * 2.45, 0.5), Vector3(4.79, s * 2.45, 0.7), Color8(30, 30, 28), X)
	_fin(cv, S, o, 61 + f)


# ------------------------------------------------------------------ helipad (6 x 6 tiles = 24 m, flat)
## Sized to the DL7-3 dropships: the craft (nose +x to +9.8 m, ramp foot -9.8 m, span +-9.4 m) sits centred on the
## painted outline. Kerb lip, safety + TLOF lines, scorched lift-fan blast circles, tie-downs, inset edge lights and
## four low corner floodlights (lit: lights on, pools inward). Everything stays under ~0.6 m: the pad sorts flat.
## Drawn rotation-symmetric (rot_1..3 alias rot_0).
static func helipad(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	var S: Array = []
	var T := M.pose(o, 0.0)
	var lit := bool(opt.get("lit", false))
	var conc: Array = C.ramp(CONC)
	var cd: Array = C.ramp(CONC_D)
	var pd: Array = C.ramp(PAD)
	var zs := 0.125
	var pa := M.part(S, -2)
	M.box(pa, T, Vector3(0, 0, 0.06), Vector3(11.9, 11.9, 0.06), cd, Vector3(0.04, 0.04, 0.04))
	RO.quad(pa, T, Vector3(0, 0, zs + 0.001), X * 11.3, Y * 11.3, pd[2], Z)
	for i in range(1, 6):   # expansion joints every 4 m
		var t := -11.3 + i * 22.6 / 6.0
		M.dline(pa, T, Vector3(t, -11.3, zs + 0.002), Vector3(t, 11.3, zs + 0.002), C.ca(pd[0], 0.6), Z)
		M.dline(pa, T, Vector3(-11.3, t, zs + 0.002), Vector3(11.3, t, zs + 0.002), C.ca(pd[0], 0.6), Z)
	for j in 160:   # surface wear speckle
		M.dpx(pa, T, Vector3(-11.0 + 22.0 * P.hn(j, 9, 3), -11.0 + 22.0 * P.hn(j, 9, 5), zs + 0.002), C.ca(pd[4], 0.35) if j % 3 == 0 else Color(0.1, 0.1, 0.09, 0.25), Z)
	for i in 24:   # white safety line, dashed
		var a := -10.9 + i * 0.91
		for e in [[Vector3(a, -10.9, 0), Vector3(a + 0.5, -10.9, 0)], [Vector3(a, 10.9, 0), Vector3(a + 0.5, 10.9, 0)],
				[Vector3(-10.9, a, 0), Vector3(-10.9, a + 0.5, 0)], [Vector3(10.9, a, 0), Vector3(10.9, a + 0.5, 0)]]:
			M.dline(pa, T, (e[0] as Vector3) + Z * (zs + 0.003), (e[1] as Vector3) + Z * (zs + 0.003), STENCIL, Z)
	var tl := 10.3
	for e in [[Vector3(-tl, -tl, 0), Vector3(tl, -tl, 0)], [Vector3(tl, -tl, 0), Vector3(tl, tl, 0)], [Vector3(tl, tl, 0), Vector3(-tl, tl, 0)], [Vector3(-tl, tl, 0), Vector3(-tl, -tl, 0)]]:
		M.dline(pa, T, (e[0] as Vector3) + Z * (zs + 0.003), (e[1] as Vector3) + Z * (zs + 0.003), YEL, Z)
	# scorched blast circles under the lift fans (craft-local, metres)
	var fans := [Vector3(5.28, -4.44, 1.0), Vector3(5.28, 4.44, 1.0), Vector3(-2.4, -7.12, 1.24), Vector3(-2.4, 7.12, 1.24)]
	for fc in fans:
		var ring: Array = []
		var soot: Array = []
		for i in 16:
			var t := TAU * i / 16.0
			ring.append(Vector3(fc.x + cos(t) * fc.z * 1.05, fc.y + sin(t) * fc.z * 1.05, zs + 0.004))
			soot.append(Vector3(fc.x + cos(t) * fc.z * 1.55, fc.y + sin(t) * fc.z * 1.55, zs + 0.003))
		M.dpoly(pa, T, soot, Color(0.08, 0.08, 0.07, 0.2), Z)
		M.dpoly(pa, T, ring, Color(0.06, 0.06, 0.05, 0.18), Z)
		for i in 16:
			M.dline(pa, T, ring[i], ring[(i + 1) % 16], YEL, Z)
	var shape := [Vector2(2.45, 0), Vector2(1.55, -0.62), Vector2(1.15, -0.75), Vector2(0.75, -0.75), Vector2(-0.33, -1.46),
		Vector2(-0.88, -1.46), Vector2(-1.4, -0.75), Vector2(-1.5, -0.75), Vector2(-1.5, -0.45), Vector2(-2.45, -0.45),
		Vector2(-2.45, 0.45), Vector2(-1.5, 0.45), Vector2(-1.5, 0.75), Vector2(-1.4, 0.75), Vector2(-0.88, 1.46),
		Vector2(-0.33, 1.46), Vector2(0.75, 0.75), Vector2(1.15, 0.75), Vector2(1.55, 0.62)]
	for i in shape.size():   # DL7-3 dropship + lowered-ramp outline (tile units x 4 m)
		var a: Vector2 = shape[i] * 4.0
		var b: Vector2 = shape[(i + 1) % shape.size()] * 4.0
		M.dline(pa, T, Vector3(a.x, a.y, zs + 0.004), Vector3(b.x, b.y, zs + 0.004), YEL, Z)
	for i in 5:   # ramp chevrons
		var u := -6.6 - i * 0.68
		M.dline(pa, T, Vector3(u + 0.4, -1.4, zs + 0.004), Vector3(u, 0.0, zs + 0.004), YEL, Z)
		M.dline(pa, T, Vector3(u, 0.0, zs + 0.004), Vector3(u + 0.4, 1.4, zs + 0.004), YEL, Z)
	M.dline(pa, T, Vector3(-1.6, 0, zs + 0.004), Vector3(1.6, 0, zs + 0.004), STENCIL, Z)
	M.dline(pa, T, Vector3(0, -1.6, zs + 0.004), Vector3(0, 1.6, zs + 0.004), STENCIL, Z)
	for c in [Vector2(-9.6, -9.6), Vector2(9.6, -9.6), Vector2(9.6, 9.6), Vector2(-9.6, 9.6)]:   # corner brackets
		M.dline(pa, T, Vector3(c.x, c.y, zs + 0.004), Vector3(c.x - signf(c.x) * 1.6, c.y, zs + 0.004), STENCIL, Z)
		M.dline(pa, T, Vector3(c.x, c.y, zs + 0.004), Vector3(c.x, c.y - signf(c.y) * 1.6, zs + 0.004), STENCIL, Z)
	for tp in [Vector2(3.0, -3.0), Vector2(3.0, 3.0), Vector2(-4.0, -3.0), Vector2(-4.0, 3.0), Vector2(7.5, 0), Vector2(-8.5, -5.5), Vector2(-8.5, 5.5)]:
		M.dpx(pa, T, Vector3(tp.x, tp.y, zs + 0.005), Color8(30, 32, 32), Z)   # tie-down rings
		M.dpx(pa, T, Vector3(tp.x + 0.12, tp.y + 0.12, zs + 0.005), Color8(176, 178, 170), Z)
	_stains(pa, T, Vector3(0, 0, zs), Vector2(6.0, 4.0), 8, 23)
	var ptm := M.part(S, -1)
	for c in [Vector2(-8.6, 8.6), Vector2(8.6, -8.6)]:   # team ID squares
		M.box(ptm, T, Vector3(c.x, c.y, zs + 0.09), Vector3(0.7, 0.7, 0.06), pd, Vector3.ZERO, {"team": true})
	# kerb lip
	var pk := M.part(S, -1)
	for e in [[Vector3(0, -11.65, 0.2), Vector3(11.9, 0.25, 0.08)], [Vector3(0, 11.65, 0.2), Vector3(11.9, 0.25, 0.08)],
			[Vector3(-11.65, 0, 0.2), Vector3(0.25, 11.4, 0.08)], [Vector3(11.65, 0, 0.2), Vector3(0.25, 11.4, 0.08)]]:
		M.box(pk, T, e[0], e[1], conc)
	# inset edge lights (green, every ~2 m) + soft halos when lit
	var lc := LAMP_G if lit else Color8(70, 100, 76)
	for i in 12:
		var a := -11.0 + i * 2.0
		for p in [Vector3(a, -11.65, 0.29), Vector3(a, 11.65, 0.29), Vector3(-11.65, a, 0.29), Vector3(11.65, a, 0.29)]:
			M.dpx(pk, T, p, lc)
			M.dpx(pk, T, p + Vector3(0.12, -0.12, 0.0), lc)
			if lit:
				M.dpoly(pa, T, [p + Vector3(-1.0, 0, -0.16), p + Vector3(0, -1.0, -0.16), p + Vector3(1.0, 0, -0.16), p + Vector3(0, 1.0, -0.16)], Color(0.6, 1.0, 0.7, 0.28), Z)
	# low corner floodlights aimed at the centre
	for c in [Vector2(-11.0, -11.0), Vector2(11.0, -11.0), Vector2(11.0, 11.0), Vector2(-11.0, 11.0)]:
		var pf := M.part(S, 0)
		M.box(pf, T, Vector3(c.x, c.y, 0.45), Vector3(0.3, 0.3, 0.2), C.ramp(STEEL))
		M.dpx(pf, T, Vector3(c.x - signf(c.x) * 0.31, c.y - signf(c.y) * 0.31, 0.5), LAMP_W if lit else DIM)
		if lit:
			var d := Vector3(-signf(c.x), -signf(c.y), 0).normalized()
			var g := Vector3(c.x, c.y, zs + 0.005)
			var q := Vector3(-d.y, d.x, 0)
			M.dpoly(pa, T, [g + d * 0.6, g + d * 6.0 + q * 2.6, g + d * 7.5, g + d * 6.0 - q * 2.6], POOL, Z)
	_fin(cv, S, o, 71)


# ------------------------------------------------------------------ loading pad tile sheet (any w x h)
## One flat 64x32 iso tile per cell (fw 64, fh 44, pivot [32, 24] = cell centre). Columns (pad_frame()):
## 0..2 plain slab variants, 3 tie-down ring, 4 bay divider on the cell's west edge, 13 bay divider through the
## cell centre, 5..8 kerb edge N (y min) / E (x max) / S (y max) / W (x min), 9..12 corners NW / NE / SE / SW
## (kerb + flush lamp). Row 0 = normal (white lamps lit, light pools), row 1 = lockdown (red lamps).
const PAD_COLS := 14
const PAD_FW := 64
const PAD_FH := 44
const PAD_PIV := Vector2i(32, 24)


## Frame column for cell (x, y) of a pad spanning cells x0..x1, y0..y1 (inclusive). Bay dividers fall on the
## loading-slot boundaries of CnFacility._slot_pos (slots 3 tiles apart around the pad centre, 2-APC team).
static func pad_frame(x: int, y: int, x0: int, y0: int, x1: int, y1: int) -> int:
	var w := x == x0
	var e := x == x1
	var n := y == y0
	var s := y == y1
	if n and w:
		return 9
	if n and e:
		return 10
	if s and e:
		return 11
	if s and w:
		return 12
	if n:
		return 5
	if e:
		return 6
	if s:
		return 7
	if w:
		return 8
	var sm := x0 + x1 + 1   # twice the pad centre
	if posmod(2 * x - sm, 6) == 0:
		return 4
	if posmod(2 * x + 1 - sm, 6) == 0:
		return 13
	if posmod(x - x0, 3) == 2 and (y - y0) % 2 == 1:
		return 3
	return posmod(x * 7 + y * 13, 3)


static func _pg(o: Vector2, x: float, y: float, z := 0.0) -> Vector2:
	return o + Vector2(8.0 * (x - y), 4.0 * (x + y) - 9.8 * z)


## Kerb along one edge (side 0 N y=-2, 1 E x=+2, 2 S y=+2, 3 W x=-2) of the tile centred at o.
static func _pad_kerb(cv, o: Vector2, side: int, lock: bool) -> void:
	var a: Vector2
	var b: Vector2
	var inn: Vector2   # inward unit (tile metres)
	match side:
		0:
			a = Vector2(-2, -2); b = Vector2(2, -2); inn = Vector2(0, 1)
		1:
			a = Vector2(2, -2); b = Vector2(2, 2); inn = Vector2(-1, 0)
		2:
			a = Vector2(-2, 2); b = Vector2(2, 2); inn = Vector2(0, -1)
		_:
			a = Vector2(-2, -2); b = Vector2(-2, 2); inn = Vector2(1, 0)
	var kt := C.ramp(Color8(176, 174, 164))
	var a2 := a + inn * 0.4
	var b2 := b + inn * 0.4
	var hz := 0.15
	cv.poly(PackedVector2Array([_pg(o, a.x, a.y, hz), _pg(o, b.x, b.y, hz), _pg(o, b2.x, b2.y, hz), _pg(o, a2.x, a2.y, hz)]), kt[3])
	if side == 0 or side == 3:   # inner face visible (faces +y / +x)
		cv.poly(PackedVector2Array([_pg(o, a2.x, a2.y, hz), _pg(o, b2.x, b2.y, hz), _pg(o, b2.x, b2.y, 0), _pg(o, a2.x, a2.y, 0)]), kt[1])
	else:   # outer face visible
		cv.poly(PackedVector2Array([_pg(o, a.x, a.y, hz), _pg(o, b.x, b.y, hz), _pg(o, b.x, b.y, 0), _pg(o, a.x, a.y, 0)]), kt[1])
	cv.line_v(_pg(o, a.x, a.y, hz), _pg(o, b.x, b.y, hz), kt[4])
	for i in 4:   # hazard line just inside the kerb
		var p0 := a.lerp(b, i / 4.0) + inn * 0.6
		var p1 := a.lerp(b, (i + 1) / 4.0) + inn * 0.6
		cv.line_v(_pg(o, p0.x, p0.y), _pg(o, p1.x, p1.y), GR.HAZ if i % 2 == 0 else GR.HAZ_D)
	var m := (a + b) * 0.5 + inn * 0.2
	_pad_lamp(cv, o, m, inn, lock)


static func _pad_lamp(cv, o: Vector2, m: Vector2, inn: Vector2, lock: bool) -> void:
	var lc := LAMP_R if lock else Color8(225, 240, 255)
	var g := _pg(o, m.x + inn.x * 0.9, m.y + inn.y * 0.9)
	cv.ellipse(g.x, g.y, 11.0, 5.5, Color(lc.r, lc.g, lc.b, 0.12))
	cv.ellipse(g.x, g.y, 6.0, 3.0, Color(lc.r, lc.g, lc.b, 0.16))
	var p := _pg(o, m.x, m.y, 0.16)
	cv.px(int(p.x), int(p.y), Color8(30, 32, 34))
	cv.px(int(p.x) + 1, int(p.y), Color8(30, 32, 34))
	cv.px(int(p.x), int(p.y) - 1, lc)
	cv.px(int(p.x) + 1, int(p.y) - 1, lc)


static func pad_tile(cv, o: Vector2, col: int, lock: bool) -> void:
	var base := Color8(134, 134, 127)
	var sd := 101 + col
	for py in 32:
		for px in 64:
			var dd := absf(float(px) - 31.5) / 32.0 + absf(float(py) - 15.5) / 16.0
			if dd <= 1.0:
				var v := 0.97 + 0.06 * P.hn(px, py, 7) - 0.03 * P.hn(px / 3, py / 2, 11)
				if col <= 2 and P.hn(px, py, sd) < 0.04:
					v -= 0.08
				var c := P.mul(base, v)
				cv.px(int(o.x) - 32 + px, int(o.y) - 16 + py, Color(c.r, c.g, c.b, 1.0))
	# joints on the west (x = -2) and north (y = -2) edges: each shared joint drawn once
	cv.line_v(_pg(o, -2, -2), _pg(o, -2, 2), Color(0.22, 0.22, 0.2, 0.55))
	cv.line_v(_pg(o, -2, -2), _pg(o, 2, -2), Color(0.22, 0.22, 0.2, 0.55))
	match col:
		1:   # oil stain
			var g := _pg(o, 0.4, -0.3)
			cv.ellipse(g.x, g.y, 8.0, 3.5, Color(0.07, 0.07, 0.06, 0.2))
			cv.ellipse(g.x + 3, g.y + 1, 4.0, 2.0, Color(0.07, 0.07, 0.06, 0.18))
		2:   # tyre marks along x
			for r in [-0.75, 0.75]:
				cv.line_v(_pg(o, -2, r), _pg(o, 2, r), Color(0.08, 0.08, 0.07, 0.2))
		3:   # tie-down ring (flush cup + bar)
			var g := _pg(o, 0, 0)
			cv.ellipse(g.x, g.y, 3.0, 1.6, Color8(44, 46, 46))
			cv.px(int(g.x) - 1, int(g.y), Color8(180, 182, 174))
			cv.px(int(g.x), int(g.y), Color8(180, 182, 174))
			cv.px(int(g.x) + 1, int(g.y) - 1, Color8(120, 122, 118))
		4, 13:   # white bay divider along y (west edge or through the centre)
			var bx := -1.85 if col == 4 else 0.0
			for k in [0.0, 0.12]:
				cv.line_v(_pg(o, bx + k, -2), _pg(o, bx + k, 2), Color(0.92, 0.92, 0.86, 0.9))
	var sides: Array = []
	match col:
		5: sides = [0]
		6: sides = [1]
		7: sides = [2]
		8: sides = [3]
		9: sides = [0, 3]
		10: sides = [0, 1]
		11: sides = [2, 1]
		12: sides = [2, 3]
	for sdx in sides:
		_pad_kerb(cv, o, int(sdx), lock)
	if sides.size() == 2:   # corner lamp post stub with a bigger pool
		var cx := 2.0 if (col == 10 or col == 11) else -2.0
		var cy := 2.0 if (col == 11 or col == 12) else -2.0
		var m := Vector2(cx * 0.8, cy * 0.8)
		var g := _pg(o, m.x * 0.3, m.y * 0.3)
		var lc := LAMP_R if lock else LAMP_W
		cv.ellipse(g.x, g.y, 16.0, 8.0, Color(lc.r, lc.g, lc.b, 0.12))
		var b0 := _pg(o, m.x, m.y, 0.15)
		cv.rect(int(b0.x) - 1, int(b0.y) - 5, 3, 5, Color8(70, 74, 78))
		cv.px(int(b0.x), int(b0.y) - 6, lc)
		cv.px(int(b0.x), int(b0.y) - 5, lc)


static func build_pad(out: Dictionary) -> void:
	var man: Dictionary = out.manifest.get("buildings", {})
	var cv := P.Canvas.new(PAD_FW * PAD_COLS, PAD_FH * 2)
	for row in 2:
		for col in PAD_COLS:
			pad_tile(cv, Vector2(col * PAD_FW + PAD_PIV.x, row * PAD_FH + PAD_PIV.y), col, row == 1)
	var entry := {"size": 1, "pivot": [PAD_PIV.x, PAD_PIV.y], "fw": PAD_FW, "fh": PAD_FH, "states": {}}
	var bytes := C._bput(out, entry, "g7_cn_pad", "tiles", cv)
	entry.states["built"] = (entry.states["tiles"] as Dictionary).duplicate()
	entry["g7"] = {"detail_level": C.VERSION, "class": "building", "bytes": bytes, "budget": int(C.BUDGET.building),
		"sample": "facility", "art": "ART7E", "key_frames": ["built"], "anim_strip": ["built"],
		"tiles": {"cols": PAD_COLS, "rows": ["normal", "lockdown"], "rule": "g7_cn_facility.gd pad_frame(x, y, x0, y0, x1, y1)",
			"frames": ["slab_a", "slab_b", "slab_c", "tiedown", "divider_w", "edge_n", "edge_e", "edge_s", "edge_w",
				"corner_nw", "corner_ne", "corner_se", "corner_sw", "divider_mid"]}}
	man["g7_cn_pad"] = entry
	out.manifest["buildings"] = man


## C.bld + extra states drawn on another rotation: Array of [state name, opt, rotation].
static func _rot_extras(out: Dictionary, id: String, size: int, top: int, draw: Callable, ex: Array) -> void:
	var entry: Dictionary = out.manifest.buildings[id]
	var o: Vector2 = K.canvas(size, top)[1]
	var bytes := 0
	for e in ex:
		var cx = K.canvas(size, top)[0]
		draw.call(cx, o, int(e[2]), e[1])
		C.selout(cx)
		bytes += C._bput(out, entry, id, String(e[0]), cx)
	entry.g7["bytes"] = int(entry.g7.bytes) + bytes


static func build(out: Dictionary) -> void:
	var g := {"sample": "facility", "art": "ART7E"}
	C.bld(out, "g7_cn_gate", 3, 44, "building", func(cv, o, f, opt): gate(cv, o, f, opt), [["open", {"open": true}]],
		g.merged({"key_frames": ["built", "open", "fire", "damaged"], "anim_strip": ["build_0", "build_1", "build_2", "built", "open", "fire", "rot_1", "rot_2", "rot_3", "damaged"],
		"fits": "gate zone 4x2 tiles (16 m along x, 8 m along y) centred on the zone; wall line along x, lane along y, inside = -y (rot_0)"}))
	C.bld(out, "g7_cn_decon", 3, 34, "building", func(cv, o, f, opt): decon(cv, o, f, opt), [["active", {"active": true}]],
		g.merged({"key_frames": ["built", "active"], "anim_strip": ["build_0", "build_1", "build_2", "built", "active", "built", "active", "rot_1", "rot_2", "damaged"],
		"fits": "3x3 drive-through wash portal centred on the decon zone, lane along y (rot_0)"}))
	var gdraw := func(cv, o, f, opt): garage(cv, o, f, opt)
	C.bld(out, "g7_cn_garage", 3, 64, "building", gdraw,
		[["open", {"open": true}], ["lockdown", {"lockdown": true}]], g.merged({"key_frames": ["built", "open", "lockdown"], "anim_strip": ["build_0", "build_1", "build_2", "built", "open", "built", "lockdown", "rot_1", "rot_3", "damaged"],
		"fits": "door on +x at rot_0 (west-side garages); rot_2 / rot_2_open / rot_2_lockdown = door on -x (east-side garages)"}))
	_rot_extras(out, "g7_cn_garage", 3, 64, gdraw, [["rot_2_open", {"open": true}, 2], ["rot_2_lockdown", {"lockdown": true}, 2]])
	C.bld(out, "g7_cn_helipad", 6, 20, "building", func(cv, o, f, opt): helipad(cv, o, f, opt), [["lit", {"lit": true}]],
		g.merged({"key_frames": ["built", "lit"], "anim_strip": ["build_0", "build_1", "build_2", "built", "lit", "built", "lit", "rot_1", "rot_2", "damaged"],
		"fits": "g7_cn_stealth_dropship / g7_a_vtol_dropship_xl, craft centre (sprite pivot) at the pad centre (0, 0), nose +u to +2.45, ramp foot at -2.45, fans at (+1.32, +-1.11) and (-0.6, +-1.78) tiles (DL7-3)"}), true)
	build_pad(out)
