extends RefCounted
## DL7-3 sample vehicles (owner: ARTCN7; rev3 = owner rev2 decision "complete design overhaul ... dynamic and
## realistic", G7_REFERENCE 6.5, 6.6). Modelled in real metres on the ONE scale (fact art.scale: 4 m per tile,
## 9.8 px per metre of height) through g7_cn_mesh.gd, so the hulls are true faceted armour:
##   g7_cn_strike_apc   8.0 x 2.9 m 8x8 (Boxer-class): V-hull, two-plane glacis, sponsons over the wheels, a tall
##                      troop module; front + rear shielded manned .50 pods (sealed-suit gunners seated in them),
##                      side pop-out launcher panels, rear ramp, and the pop-out 6-tube rocket pod at the roof's
##                      rear right, right behind the rear gunner pod (6 canister colours on the tube mouths).
##   g7_op_tactical_apc 7.0 x 2.7 m 8x8 (LAV / AMV-class): long low wedge nose, steeper faceted sides, a remote
##                      twin .50 weapon station, the same rocket pod (rear right, behind the RWS).
## Motion: wheels turn (hub lugs + tread phase per frame), suspension travel (hull bob / pitch / roll over the
## wheels, one wheel riding a bump), gun pods traverse. Team mask: roof ID panel + side chevrons.
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const M = preload("res://tools/art/g7_cn_mesh.gd")
const GR = preload("res://tools/art/g7_cn_gear.gd")

const HULL_CN := Color8(104, 112, 100)
const LOW_CN := Color8(84, 90, 80)
const HULL_OP := Color8(92, 96, 62)
const LOW_OP := Color8(70, 74, 50)
const BURNT := Color8(56, 50, 46)
const DARK := Color8(46, 50, 52)
const TIRE := Color8(40, 40, 38)
const HUB := Color8(92, 96, 90)
const GLASS := Color8(70, 120, 140)
const CAN := Color8(92, 98, 64)
const TARP := Color8(120, 110, 82)
const TEAMG := Color8(152, 152, 152)
const SUIT := Color8(152, 154, 134)
const VISOR := Color8(246, 178, 60)
const LAMP := Color8(255, 236, 170)
const DOME := Color(0.62, 0.84, 1.0, 0.20)
const DOME_RIM := Color(0.80, 0.94, 1.0, 0.75)
const DUST := Color(0.55, 0.50, 0.40, 0.40)
const SMOKE := Color(0.78, 0.76, 0.72, 0.55)
## Rocket-pod canister colours (6.5, PROVISIONAL): tandem, EMP, thermite, HE-frag, disruptor, smoke.
const CANISTERS := [Color8(214, 64, 52), Color8(110, 180, 255), Color8(240, 130, 40), Color8(232, 204, 70),
	Color8(90, 236, 210), Color8(226, 226, 220)]
const STRIKE_FRAMES := ["idle", "move", "fire", "move_1", "fire_r", "traverse", "panels_open", "launch", "dome",
	"doors_open", "rockets_up", "rockets_fire"]
const TAC_FRAMES := ["idle", "move", "fire", "move_1", "traverse", "panels_open", "dome", "doors_open",
	"rockets_up", "rockets_fire"]
## Real dimensions (metres): length, width, roof height, wheel radius, axle f positions, wheel track (r).
const SPEC := {
	true: {"L": 8.0, "W": 2.9, "roof": 2.3, "wr": 0.64, "axles": [2.55, 1.15, -0.85, -2.25], "track": 1.18},
	false: {"L": 7.0, "W": 2.7, "roof": 2.05, "wr": 0.56, "axles": [2.3, 0.95, -0.8, -2.05], "track": 1.08}}
const FW := {true: 128, false: 120}
const FH := {true: 112, false: 104}
const PIV := {true: Vector2i(64, 80), false: Vector2i(60, 74)}


## Kept for older callers: local (u forward, v right) tiles -> world tile offset at yaw a.
static func lw(a: float, u: float, v: float) -> Vector2:
	return Vector2(cos(a) * u - sin(a) * v, sin(a) * u + cos(a) * v)


static func lp(o: Vector2, a: float, u: float, v: float, z: float) -> Vector2:
	var w := lw(a, u, v)
	return P.proj(o, Vector3(w.x, w.y, z))


## Kept for g7_turrets.gd: oriented box at local (u, v) tiles of yaw a (lib C.box).
static func vbox(cv, o: Vector2, a: float, u: float, v: float, z: float, hx: float, hy: float, hz: float,
		rp: Array, top_t := 3, team_top := false, inset := Vector2.ZERO) -> Dictionary:
	var w := lw(a, u, v)
	return C.box(cv, o, Vector3(w.x, w.y, z), hx, hy, hz, a, rp, top_t, true, team_top, inset)


## Right half of a section (r >= 0, bottom to top) -> the full closed section mirrored about r = 0.
static func mir(pts: Array) -> PackedVector2Array:
	var s := PackedVector2Array()
	for i in range(pts.size() - 1, -1, -1):
		s.append(Vector2(-(pts[i] as Vector2).x, (pts[i] as Vector2).y))
	for q in pts:
		s.append(q)
	return s


# ------------------------------------------------------------------ running gear and mounts
## One road wheel: tyre prism, hub disk, lug nuts and tread blocks turned by spin (rad).
static func wheel(S: Array, T: Dictionary, f: float, r: float, z: float, wr: float, spin: float, wreck: bool) -> void:
	var pt := M.part(S, 0)
	var s := signf(r)
	var tr: Array = C.ramp(BURNT if wreck else TIRE)
	M.cyl(pt, T, Vector3(f, r, z), Vector3(0, 1, 0), wr, 0.23, 12, tr, {"cap_t": 1, "edge": false}, spin)
	var hb: Array = C.ramp(Color8(50, 46, 42) if wreck else HUB)
	M.cyl(pt, T, Vector3(f, r + s * 0.235, z), Vector3(0, 1, 0), wr * 0.52, 0.012, 8, hb, {"cap_t": 2}, spin)
	for i in 4:
		var t := spin + TAU * i / 4.0
		M.dpx(pt, T, Vector3(f + cos(t) * wr * 0.3, r + s * 0.25, z + sin(t) * wr * 0.3), hb[4] if i == 0 else hb[0],
			Vector3(0, s, 0))
	M.dpx(pt, T, Vector3(f, r + s * 0.25, z), hb[0], Vector3(0, s, 0))
	for i in 6:
		var t := spin * 2.0 + TAU * i / 6.0
		M.dpx(pt, T, Vector3(f + cos(t) * wr, r + s * 0.1, z + sin(t) * wr), tr[2], Vector3(cos(t), 0, sin(t)))


## Seated gunner (sealed suit, amber faceplate, team armbands) at local point g of pod pose Tp.
static func gunner(pt: Dictionary, Tp: Dictionary, g: Vector3, burnt := false) -> void:
	var su: Array = C.ramp(BURNT if burnt else SUIT)
	M.box(pt, Tp, g + Vector3(0, 0, 0.18), Vector3(0.14, 0.24, 0.18), su, Vector3(0.0, 0.0, 0.06))
	M.cyl(pt, Tp, g + Vector3(0.02, 0, 0.47), Vector3(0, 0, 1), 0.15, 0.13, 8, su, {"cap_t": 3}, 0.2)
	if burnt:
		return
	M.dpx(pt, Tp, g + Vector3(0.17, 0.0, 0.47), VISOR, Vector3(1, 0, 0))
	M.dpx(pt, Tp, g + Vector3(0.16, -0.07, 0.45), C.ramp(VISOR)[1], Vector3(1, 0, 0))
	for s in [-1.0, 1.0]:
		M.dpx(pt, Tp, g + Vector3(0.0, s * 0.25, 0.26), TEAMG, Vector3(0, s, 0), true)


## Shielded .50 pod: ring, three-plate faceted shield with vision slot, M2 receiver + barrel, seated gunner.
static func pod(S: Array, T: Dictionary, at: Vector3, yaw: float, hull: Array, fire: bool, burnt := false) -> void:
	var Tp := M.sub(T, at, yaw)
	var pt := M.part(S, 2)
	var dk: Array = C.ramp(DARK)
	M.cyl(pt, Tp, Vector3(0, 0, 0.08), Vector3(0, 0, 1), 0.56, 0.08, 10, hull, {"cap_t": 2})
	gunner(pt, Tp, Vector3(-0.2, 0, 0.16), burnt)
	if not burnt:
		M.box(pt, Tp, Vector3(0.28, 0, 0.62), Vector3(0.2, 0.07, 0.07), dk)
		M.cyl(pt, Tp, Vector3(0.95, 0, 0.64), Vector3(1, 0, 0), 0.035, 0.55, 4, dk, {"edge": false})
		M.cyl(pt, Tp, Vector3(0.6, 0, 0.64), Vector3(1, 0, 0), 0.06, 0.1, 6, dk, {"edge": false})
		M.box(pt, Tp, Vector3(0.12, 0.14, 0.55), Vector3(0.1, 0.06, 0.07), C.ramp(CAN))
	M.box(pt, Tp, Vector3(0.42, 0, 0.52), Vector3(0.035, 0.36, 0.34), hull)
	for s in [-1.0, 1.0]:
		M.box(pt, M.sub(Tp, Vector3(0.29, s * 0.48, 0.5), s * 0.62), Vector3.ZERO, Vector3(0.03, 0.17, 0.31), hull)
	M.dline(pt, Tp, Vector3(0.46, -0.12, 0.68), Vector3(0.46, 0.12, 0.68), Color8(24, 26, 26), Vector3(1, 0, 0))
	if fire:
		_flash(pt, Tp, Vector3(1.55, 0, 0.64))


static func _flash(pt: Dictionary, Tp: Dictionary, m: Vector3) -> void:
	pt.dec.append({"k": "px", "a": M.wm(Tp, m), "col": GR.FLASH, "n": Vector3.ZERO})
	for i in 4:
		var q := M.wm(Tp, m + Vector3(0.1 + i * 0.1, (i % 3 - 1) * 0.07, (i % 2) * 0.06))
		pt.dec.append({"k": "px", "a": q, "col": GR.FLASH_O if i % 2 == 1 else GR.FLASH, "n": Vector3.ZERO})
	pt.dec.append({"k": "line", "a": M.wm(Tp, m + Vector3(0.2, 0, 0)), "b": M.wm(Tp, m + Vector3(2.2, 0, 0.06)),
		"col": Color(1.0, 0.86, 0.5, 0.8), "n": Vector3.ZERO})


## Remote twin .50 weapon station (tactical APC): turret ring, armoured cradle, sensor head, two barrels.
static func rws(S: Array, T: Dictionary, at: Vector3, yaw: float, hull: Array, fire: bool) -> void:
	var Tp := M.sub(T, at, yaw)
	var pt := M.part(S, 2)
	var dk: Array = C.ramp(DARK)
	M.cyl(pt, Tp, Vector3(0, 0, 0.07), Vector3(0, 0, 1), 0.5, 0.07, 10, hull, {"cap_t": 2})
	M.box(pt, Tp, Vector3(0.0, 0, 0.36), Vector3(0.36, 0.3, 0.2), hull, Vector3(0.12, 0.05, 0.06))
	M.box(pt, Tp, Vector3(-0.05, -0.4, 0.5), Vector3(0.14, 0.09, 0.13), dk)
	M.dpx(pt, Tp, Vector3(0.1, -0.4, 0.52), GLASS, Vector3(1, 0, 0))
	M.dpx(pt, Tp, Vector3(0.1, -0.36, 0.53), C.ramp(GLASS)[4], Vector3(1, 0, 0))
	for s in [-1.0, 1.0]:
		M.cyl(pt, Tp, Vector3(0.95, s * 0.11, 0.44), Vector3(1, 0, 0), 0.035, 0.6, 4, dk, {"edge": false})
	M.box(pt, Tp, Vector3(-0.25, 0.32, 0.32), Vector3(0.13, 0.08, 0.1), C.ramp(CAN))
	if fire:
		for s in [-1.0, 1.0]:
			_flash(pt, Tp, Vector3(1.58, s * 0.11, 0.44))


## Pop-out 6-tube micro rocket pod. state 0 stowed (flush roof hatch), 1 raised, 2 raised + firing.
static func rocket_pod(S: Array, T: Dictionary, at: Vector3, hull: Array, state: int) -> void:
	var pt := M.part(S, 2)
	var dk: Array = C.ramp(DARK)
	if state == 0:
		M.box(pt, T, at + Vector3(0, 0, 0.05), Vector3(0.5, 0.34, 0.05), hull, Vector3(0.03, 0.03, 0.03))
		for s in [-1.0, 1.0]:
			M.dline(pt, T, at + Vector3(0.44, s * 0.29, 0.11), at + Vector3(-0.44, s * 0.29, 0.11), C.ca(hull[0], 0.9), Vector3(0, 0, 1))
		return
	for s in [-1.0, 1.0]:   # scissor lift arms
		M.box(pt, T, at + Vector3(-0.15, s * 0.22, 0.38), Vector3(0.05, 0.04, 0.36), dk)
	var Tr := M.sub(T, at + Vector3(0.0, 0, 0.8), 0.0, 0.42)
	M.box(pt, Tr, Vector3.ZERO, Vector3(0.5, 0.34, 0.24), hull)
	M.dline(pt, Tr, Vector3(0.3, -0.35, 0.18), Vector3(-0.45, -0.35, 0.18), C.ca(hull[4], 0.6), Vector3(0, -1, 0))
	for i in 6:   # tube mouths: 2 rows x 3, each ringed with its canister colour
		var rr := (float(i % 3) - 1.0) * 0.22
		var zz := 0.1 if i < 3 else -0.1
		M.dpx(pt, Tr, Vector3(0.51, rr, zz), Color8(14, 14, 16), Vector3(1, 0, 0))
		M.dpx(pt, Tr, Vector3(0.51, rr + 0.1, zz), CANISTERS[i], Vector3(1, 0, 0))
	if state == 2:
		var a := M.wm(Tr, Vector3(0.6, -0.22, 0.1))
		var b := M.wm(Tr, Vector3(3.4, -0.22, 0.1))
		pt.dec.append({"k": "line", "a": a, "b": b, "col": Color(1.0, 0.92, 0.7, 0.9), "n": Vector3.ZERO})
		pt.dec.append({"k": "px", "a": b, "col": GR.FLASH, "n": Vector3.ZERO})
		for i in 6:   # backblast
			var q := M.wm(Tr, Vector3(-0.6 - i * 0.2, (i % 3 - 1) * 0.14, -0.08 - i * 0.06))
			pt.dec.append({"k": "px", "a": q, "col": SMOKE if i > 1 else GR.FLASH_O, "n": Vector3.ZERO})


## Translucent hex shield dome over the hull (dome frame).
static func dome(cv, c: Vector2, rx: float, ry: float, hz: float) -> void:
	for y in range(int(c.y - hz), int(c.y + ry) + 1):
		for x in range(int(c.x - rx), int(c.x + rx) + 1):
			var dx := (x + 0.5 - c.x) / rx
			var dy := (y + 0.5 - c.y) / (hz if y < c.y else ry)
			var d := dx * dx + dy * dy
			if d <= 1.0:
				var hex := (posmod(x + int(y * 0.5), 7) == 0 or posmod(y, 6) == 0) and d < 0.88
				cv.px(x, y, DOME_RIM if d > 0.88 else (Color(DOME_RIM, 0.30) if hex else DOME))


# ------------------------------------------------------------------ the hull
## Hull sections (right halves, bottom to top) along f: [f, [Vector2(r, z) ...]].
static func _upper(big: bool) -> Array:
	if big:
		return [[4.05, [Vector2(1.2, 0.75), Vector2(1.28, 0.98), Vector2(1.05, 1.08)]],
			[3.8, [Vector2(1.42, 0.85), Vector2(1.45, 1.25), Vector2(1.12, 1.38)]],
			[2.0, [Vector2(1.45, 1.1), Vector2(1.45, 1.8), Vector2(1.12, 2.3)]],
			[-3.82, [Vector2(1.45, 1.1), Vector2(1.45, 1.8), Vector2(1.12, 2.3)]],
			[-4.0, [Vector2(1.38, 1.12), Vector2(1.38, 1.74), Vector2(1.07, 2.2)]]]
	return [[3.5, [Vector2(1.0, 0.7), Vector2(1.05, 0.84), Vector2(0.92, 0.92)]],
		[3.28, [Vector2(1.22, 0.8), Vector2(1.3, 1.04), Vector2(1.0, 1.16)]],
		[1.6, [Vector2(1.35, 1.0), Vector2(1.35, 1.52), Vector2(1.0, 1.95)]],
		[1.2, [Vector2(1.35, 1.0), Vector2(1.35, 1.58), Vector2(0.98, 2.05)]],
		[-3.3, [Vector2(1.35, 1.0), Vector2(1.35, 1.58), Vector2(0.98, 2.05)]],
		[-3.5, [Vector2(1.28, 1.02), Vector2(1.28, 1.52), Vector2(0.94, 1.97)]]]


static func _lower(big: bool) -> Array:
	var z0 := 0.42 if big else 0.38
	var full := [Vector2(0.45, z0), Vector2(0.92, z0 + 0.2), Vector2(0.92, 1.15)]
	if big:
		return [[3.85, [Vector2(0.4, 0.66), Vector2(0.85, 0.8), Vector2(0.85, 1.0)]], [3.3, full], [-3.6, full],
			[-3.95, [Vector2(0.4, 0.6), Vector2(0.9, 0.72), Vector2(0.9, 1.15)]]]
	return [[3.32, [Vector2(0.35, 0.6), Vector2(0.75, 0.72), Vector2(0.75, 0.85)]], [2.85, full], [-3.15, full],
		[-3.45, [Vector2(0.4, 0.55), Vector2(0.85, 0.68), Vector2(0.85, 1.05)]]]


static func _secs(src: Array) -> Array:
	var out: Array = []
	for s in src:
		out.append([float(s[0]), mir(s[1])])
	return out


## The whole vehicle into scene S at ground pose T. fname picks the state; wreck = burnt hull.
static func model(S: Array, T: Dictionary, big: bool, fname: String, wreck := false) -> void:
	var sp: Dictionary = SPEC[big]
	var hull: Array = C.ramp(BURNT if wreck else (HULL_CN if big else HULL_OP))
	var low: Array = C.ramp(P.mul(BURNT, 0.8) if wreck else (LOW_CN if big else LOW_OP))
	var dk: Array = C.ramp(DARK)
	var roof: float = sp.roof
	var wr: float = sp.wr
	var ph := {"move": 1.0, "move_1": 2.0}.get(fname, 0.0) as float
	var spin := ph * TAU / 12.0
	var bob := {"move": 0.06, "move_1": -0.04}.get(fname, 0.0) as float
	var pitch := {"move": 0.02, "move_1": -0.015}.get(fname, 0.0) as float
	var roll := {"move": 0.015, "move_1": -0.02}.get(fname, 0.0) as float
	if wreck:
		bob = -0.2
		pitch = -0.035
		roll = 0.06
	var Th := M.sub(T, Vector3(0, 0, bob), 0.0, pitch, roll)
	var ax: Array = sp.axles
	for i in ax.size():   # running gear: 4 axles, the front pair steered by nothing (straight), one wheel on a bump
		for s in [-1.0, 1.0]:
			if wreck and ((i == 0 and s > 0) or (i == 3 and s < 0)):
				continue
			var bump := 0.08 if (fname == "move" and i == 1 and s > 0) or (fname == "move_1" and i == 2 and s < 0) else 0.0
			wheel(S, T, float(ax[i]), s * float(sp.track), wr + bump, wr, spin + i * 0.7, wreck)
	if big and not wreck:   # driver's hatch cupola on the glacis (front left)
		var cu := M.part(S, 2)
		M.box(cu, Th, Vector3(2.75, -0.62, 1.86), Vector3(0.32, 0.3, 0.12), hull, Vector3(0.1, 0.02, 0.06))
	var lo := M.part(S, 0, -0.05)
	M.loft(lo, Th, _secs(_lower(big)), low)
	var hw: float = float(sp.W) * 0.5
	for s in [-1.0, 1.0]:   # skirt plates between the wheel pairs and behind the last axle: the wheel arches
		var g0 := float(ax[1]) - wr - 0.05
		var g1 := float(ax[2]) + wr + 0.05
		M.box(lo, Th, Vector3((g0 + g1) * 0.5, s * (hw - 0.06), 0.93), Vector3((g0 - g1) * 0.5, 0.05, 0.2), low)
		M.box(lo, Th, Vector3((g0 + g1) * 0.5, s * (hw - 0.2), 0.8), Vector3(0.28, 0.12, 0.2), low)
		var r0 := float(ax[3]) - wr - 0.05
		var r1 := (-3.95 if big else -3.45)
		M.box(lo, Th, Vector3((r0 + r1) * 0.5, s * (hw - 0.06), 0.93), Vector3((r0 - r1) * 0.5, 0.05, 0.2), low)
	var up := M.part(S, 1)
	M.loft(up, Th, _secs(_upper(big)), hull)
	_details(up, S, Th, big, hull, dk, wreck)
	var at_r: Vector3
	if big:
		pod(S, Th, Vector3(1.15, 0, roof), 0.9 if fname == "traverse" else 0.0, hull, fname == "fire", wreck)
		pod(S, Th, Vector3(-2.0, -0.38, roof), PI - (1.3 if fname == "traverse" else 0.0), hull, fname == "fire_r", wreck)
		at_r = Vector3(-3.1, 0.72, roof)
	else:
		if not wreck:
			rws(S, Th, Vector3(0.7, -0.1, roof), 0.9 if fname == "traverse" else 0.0, hull, fname == "fire")
		at_r = Vector3(-2.55, 0.62, roof)
	rocket_pod(S, Th, at_r, hull, 0 if wreck else {"rockets_up": 1, "rockets_fire": 2}.get(fname, 0))
	if fname == "panels_open" or fname == "launch":
		_panels(S, Th, big, hull, fname == "launch")
	if fname == "doors_open":
		_ramp(S, Th, big, low)
	if fname.begins_with("move"):
		var du := M.part(S, -1)
		for i in 7:
			var q := Vector3(float(ax[3]) - wr - 0.2 - P.hn(i, int(ph), 3) * 1.2, (P.hn(i, 5, int(ph)) - 0.5) * 3.0, P.hn(i, 9, 2) * 0.3)
			du.dec.append({"k": "px", "a": M.wm(T, q), "col": DUST, "n": Vector3.ZERO})


## Hull furniture: optics, lights, smoke dischargers, antennas, stowage, tow points, seams, hatches, team marks.
static func _details(up: Dictionary, S: Array, T: Dictionary, big: bool, hull: Array, dk: Array, wreck: bool) -> void:
	var sp: Dictionary = SPEC[big]
	var roof: float = sp.roof
	var hw: float = float(sp.W) * 0.5
	var nose: float = 4.0 if big else 3.5
	var rear: float = -4.0 if big else -3.5
	var seam := C.ca(hull[0], 0.75)
	var top := Vector3(0, 0, 1)
	for s in [-1.0, 1.0]:
		var n := Vector3(0, s, 0)
		for f in ([2.2, 0.55, -1.1, -2.7] if big else [1.0, -0.6, -2.1]):   # vertical armour seams
			M.dline(up, T, Vector3(f, s * (hw + 0.005), 1.14), Vector3(f, s * (hw + 0.005), 1.5), seam, n)
		M.dline(up, T, Vector3(nose - 0.6, s * (hw + 0.005), 1.12), Vector3(rear + 0.2, s * (hw + 0.005), 1.12), C.ca(hull[0], 0.9), n)
		if not wreck:   # team chevron on each side, rear quarter
			var cf := rear + 1.1
			var ch := [Vector3(cf + 0.35, s * (hw + 0.01), 1.36), Vector3(cf, s * (hw + 0.01), 1.6),
				Vector3(cf - 0.3, s * (hw + 0.01), 1.6), Vector3(cf + 0.05, s * (hw + 0.01), 1.36),
				Vector3(cf - 0.3, s * (hw + 0.01), 1.14), Vector3(cf, s * (hw + 0.01), 1.14)]
			M.dpoly(up, T, ch, TEAMG, n, true)
		# headlights with guards, tow shackles
		M.dpx(up, T, Vector3(nose - 0.05, s * (hw - 0.3), 1.05 if big else 0.86), LAMP if not wreck else dk[0], Vector3(1, 0, 0))
		M.dpx(up, T, Vector3(nose - 0.05, s * (hw - 0.22), 1.05 if big else 0.86), dk[0], Vector3(1, 0, 0))
		M.dpx(up, T, Vector3(nose - 0.02, s * 0.55, 0.88 if big else 0.74), Color8(196, 60, 40), Vector3(1, 0, 0))
		M.dpx(up, T, Vector3(rear + 0.02, s * 0.62, 1.2), Color8(200, 40, 30) if not wreck else dk[0], Vector3(-1, 0, 0))
		if wreck:
			continue
		var g := M.part(S, 2)   # smoke grenade dischargers: 3 tubes per front corner, aimed forward-up-out
		for i in 3:
			var c := Vector3((2.15 if big else 1.0) - i * 0.12, s * (hw - 0.42 + i * 0.03), roof + 0.07)
			M.cyl(g, T, c, Vector3(0.7, s * 0.4, 0.6), 0.065, 0.13, 5, dk, {"edge": false, "cap_t": 0})
		var an := M.part(S, 3)   # whip antennas at the rear corners
		var b := Vector3(rear + 0.35, s * (hw - 0.35), roof)
		var tip := b + Vector3(-0.25, s * 0.08, 1.45)
		M.box(an, T, b + Vector3(0, 0, 0.08), Vector3(0.06, 0.06, 0.08), dk)
		an.dec.append({"k": "line", "a": M.wm(T, b + Vector3(0, 0, 0.15)), "b": M.wm(T, tip), "col": C.ca(dk[2], 0.55), "n": Vector3.ZERO})
		an.dec.append({"k": "px", "a": M.wm(T, tip), "col": dk[2], "n": Vector3.ZERO})
		var cn := M.part(S, 2)   # jerry cans on the rear plate
		M.box(cn, T, Vector3(rear - 0.1, s * (hw - 0.35), 1.45), Vector3(0.09, 0.17, 0.24), C.ramp(CAN))
		M.box(cn, T, Vector3(nose - 1.2 if big else 0.2, s * (hw - 0.28), roof + 0.06), Vector3(0.12, 0.08, 0.06), dk)   # APS sensor
	# roof: hatches, commander sight, driver vision blocks, ID panel (team), exhaust grille, rear door outline
	var hz := roof + 0.004
	for hf in ([0.15, -1.0] if big else [-0.4, -1.5]):
		var q := [Vector3(hf + 0.28, -0.75, hz), Vector3(hf + 0.28, -0.2, hz), Vector3(hf - 0.28, -0.2, hz), Vector3(hf - 0.28, -0.75, hz)]
		for i in 4:
			M.dline(up, T, q[i], q[(i + 1) % 4], seam, top)
	if not wreck:
		var idf := -0.9 if big else -1.0
		M.dpoly(up, T, [Vector3(idf + 0.45, 0.15, hz), Vector3(idf + 0.45, 0.85, hz), Vector3(idf - 0.45, 0.85, hz),
			Vector3(idf - 0.45, 0.15, hz)], TEAMG, top, true)
		var sg := M.part(S, 2)
		M.box(sg, T, Vector3(1.85 if big else 1.25, 0.62, roof + 0.16), Vector3(0.16, 0.14, 0.16), hull, Vector3(0.04, 0.0, 0.02))
		M.dpx(sg, T, Vector3((1.85 if big else 1.25) + 0.17, 0.62, roof + 0.2), GLASS, Vector3(1, 0, 0))
		M.dpx(sg, T, Vector3((1.85 if big else 1.25) + 0.17, 0.55, roof + 0.22), C.ramp(GLASS)[4], Vector3(1, 0, 0))
		var st := M.part(S, 2)   # stowage: rolled tarp + kit bags on the roof's rear left
		M.cyl(st, T, Vector3(rear + 0.6, -0.75, roof + 0.13), Vector3(1, 0, 0), 0.13, 0.42, 6, C.ramp(TARP), {"edge": false})
		M.box(st, T, Vector3(rear + 1.35, -0.85, roof + 0.12), Vector3(0.22, 0.2, 0.12), C.ramp(Color8(84, 88, 70)), Vector3(0.04, 0.04, 0.04))
	var gn := Vector3(0.6, 0, 0.8).normalized() if big else Vector3(0.45, 0, 0.89).normalized()
	for i in 3:   # driver's vision blocks on the glacis (front left)
		var vf := 3.08 if big else 1.77
		M.dpx(up, T, Vector3(vf, (-0.8 if big else -0.85) + i * 0.16, (1.94 if big else 1.9)), GLASS if i != 1 else C.ramp(GLASS)[4], gn)
	for i in 4:   # engine exhaust grille, right side front
		var ef := (3.0 if big else 2.4) - i * 0.14
		M.dline(up, T, Vector3(ef, hw + 0.006, 1.3), Vector3(ef, hw + 0.006, 1.6), C.ca(dk[0], 0.9), Vector3(0, 1, 0))
	var dr := [Vector3(rear - 0.004, -0.8, 1.15), Vector3(rear - 0.004, 0.8, 1.15), Vector3(rear - 0.004, 0.8, roof - 0.25),
		Vector3(rear - 0.004, -0.8, roof - 0.25)]
	for i in 4:
		M.dline(up, T, dr[i], dr[(i + 1) % 4], seam, Vector3(-1, 0, 0))
	if wreck:   # scorch, a penetration hole, buckled plate
		M.dpoly(up, T, [Vector3(0.6, hw + 0.01, 1.3), Vector3(0.1, hw + 0.01, 1.7), Vector3(-0.4, hw + 0.01, 1.4)], Color8(18, 16, 14), Vector3(0, 1, 0))
		M.dpoly(up, T, [Vector3(-1.2, -0.4, hz), Vector3(-0.4, 0.3, hz), Vector3(-1.4, 0.6, hz)], Color8(24, 20, 18), top)


## Side pop-out launcher panels: hinged at the shoulder, swung up and out over a recess of interceptor cells.
static func _panels(S: Array, T: Dictionary, big: bool, hull: Array, launch: bool) -> void:
	var sp: Dictionary = SPEC[big]
	var hw: float = float(sp.W) * 0.5
	var f0 := -0.3 if big else -0.5
	for s in [-1.0, 1.0]:
		var pt := M.part(S, 2)
		M.dpoly(pt, T, [Vector3(f0 + 0.55, s * (hw + 0.01), 1.25), Vector3(f0 - 0.55, s * (hw + 0.01), 1.25),
			Vector3(f0 - 0.55, s * (hw + 0.01), 1.72), Vector3(f0 + 0.55, s * (hw + 0.01), 1.72)], Color8(22, 24, 24), Vector3(0, s, 0))
		for i in 3:
			M.dpx(pt, T, Vector3(f0 - 0.35 + i * 0.35, s * (hw + 0.012), 1.5), Color8(240, 170, 60), Vector3(0, s, 0))
		var Tf := M.sub(T, Vector3(f0, s * (hw + 0.02), 1.78), 0.0, 0.0, -s * 1.15)
		M.box(pt, Tf, Vector3(0, s * 0.0, -0.24), Vector3(0.55, 0.025, 0.24), hull)
	if launch:
		var dr := M.part(S, 3)
		var c := Vector3(f0, hw + 1.0, 2.6)
		M.box(dr, T, c, Vector3(0.18, 0.18, 0.05), C.ramp(Color8(60, 64, 66)))
		for i in 4:
			var q := c + Vector3((i % 2) * 0.36 - 0.18, (i / 2) * 0.36 - 0.18, 0.08)
			dr.dec.append({"k": "px", "a": M.wm(T, q), "col": Color(0.8, 0.85, 0.8, 0.8), "n": Vector3.ZERO})
		for i in 5:
			dr.dec.append({"k": "px", "a": M.wm(T, Vector3(f0 + (i - 2) * 0.12, hw + 0.4 + i * 0.1, 1.9 + i * 0.12)), "col": SMOKE, "n": Vector3.ZERO})


## Rear ramp lowered to the ground, the lit troop compartment behind it.
static func _ramp(S: Array, T: Dictionary, big: bool, low: Array) -> void:
	var rear: float = -4.0 if big else -3.5
	var pt := M.part(S, 2, 0.4)
	M.dpoly(pt, T, [Vector3(rear - 0.01, -0.78, 0.62), Vector3(rear - 0.01, 0.78, 0.62), Vector3(rear - 0.01, 0.78, 1.95),
		Vector3(rear - 0.01, -0.78, 1.95)], Color8(30, 32, 30), Vector3(-1, 0, 0))
	M.dpx(pt, T, Vector3(rear - 0.02, 0.0, 1.85), Color8(250, 214, 140), Vector3(-1, 0, 0))
	var Tr := M.sub(T, Vector3(rear - 0.05, 0, 0.6), PI, -0.45)
	M.box(pt, Tr, Vector3(0.68, 0, -0.03), Vector3(0.68, 0.8, 0.04), low)
	for i in 4:
		M.dline(pt, Tr, Vector3(0.25 + i * 0.3, -0.7, 0.012), Vector3(0.25 + i * 0.3, 0.7, 0.012), C.ca(low[0], 0.8), Vector3(0, 0, 1))


static func apc(cv, k: int, fname: String, o: Vector2, big: bool, wreck := false) -> void:
	var S: Array = []
	var T := M.pose(o, k * PI / 4.0)
	model(S, T, big, fname, wreck)
	M.shadow(cv, S, o)
	M.render(cv, S, o, 31 + k)
	if fname == "dome":
		dome(cv, o + Vector2(0, -4), 60.0 if big else 56.0, 28.0, 54.0)


static func build(out: Dictionary) -> void:
	for big in [true, false]:
		var id := "g7_cn_strike_apc" if big else "g7_op_tactical_apc"
		var frames: Array = STRIKE_FRAMES if big else TAC_FRAMES
		var b: bool = big
		C.unit_sheet(out, id, "vehicles", "vehicle", int(FW[b]), int(FH[b]), PIV[b], frames,
			func(cv, k, f, o): apc(cv, k, f, o, b),
			{"sample": "vehicle", "line": "strike_team" if b else "operators",
			"capacity": "10 + packages (PROVISIONAL)" if b else 8, "key_frames": frames.duplicate(),
			"size_m": [SPEC[b].L, SPEC[b].W, SPEC[b].roof], "scale": "4 m/tile, 9.8 px/m (fact art.scale)",
			"anim_strip": ["idle", "move", "move_1", "traverse", "fire", "panels_open", "rockets_up", "rockets_fire", "dome", "doors_open"]},
			func(cv, k, o): apc(cv, k, "idle", o, b, true))
