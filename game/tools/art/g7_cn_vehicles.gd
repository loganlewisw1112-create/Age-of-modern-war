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
const BRASS := Color8(214, 176, 84)
const ROOF := {true: Color8(88, 95, 84), false: Color8(76, 80, 52)}   # darker non-skid roof coat (rev4: pale roofs)
## Rocket-pod canister colours (6.5, PROVISIONAL): tandem, EMP, thermite, HE-frag, disruptor, smoke.
const CANISTERS := [Color8(214, 64, 52), Color8(110, 180, 255), Color8(240, 130, 40), Color8(232, 204, 70),
	Color8(90, 236, 210), Color8(226, 226, 220)]
const STRIKE_FRAMES := ["idle", "move", "fire", "move_1", "fire_r", "traverse", "panels_open", "launch", "dome",
	"doors_open", "rockets_up", "rockets_fire"]
const TAC_FRAMES := ["idle", "move", "fire", "move_1", "traverse", "panels_open", "dome", "doors_open",
	"rockets_up", "rockets_fire"]
## rev4 weapon animation sheets (<id>_gun, <id>_rkt): same cell / pivot as the main sheet, so the sim swaps sheets.
const GUN_STRIKE := ["fire_0", "fire_1", "fire_2", "fire_3", "fire_r_0", "fire_r_1", "fire_r_2", "fire_r_3",
	"reload_0", "reload_1", "reload_2", "reload_r_0", "reload_r_1", "reload_r_2"]
const GUN_TAC := ["fire_0", "fire_1", "fire_2", "fire_3", "reload_0", "reload_1", "reload_2"]
const RKT := ["rk_raise_0", "rk_raise_1", "rk_fire_0", "rk_fire_1", "rk_fire_2", "rk_fire_3", "rk_fire_4", "rk_fire_5",
	"rk_reload_0", "rk_reload_1", "rk_reload_2", "rk_reload_3"]
const RKT_ALIAS := {"rk_aim": "rk_raise_1", "rk_stow_0": "rk_raise_1", "rk_stow_1": "rk_raise_0"}
## Real dimensions (metres): length, width, roof height, wheel radius, axle f positions, wheel track (r).
const SPEC := {
	true: {"L": 8.0, "W": 2.9, "roof": 2.3, "wr": 0.64, "axles": [2.55, 1.15, -0.85, -2.25], "track": 1.18},
	false: {"L": 7.0, "W": 2.7, "roof": 2.05, "wr": 0.56, "axles": [2.3, 0.95, -0.8, -2.05], "track": 1.08}}
## ART7D: G6.1 vehicle frames rendered by the model itself (appended after the frozen columns; g7_anim adds anim61).
const ANIM61 := ["track_1", "track_2", "recoil", "damaged"]
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


## Thin limb / rod between two local points of pose T (arms, lift rams, struts).
static func rod(pt: Dictionary, T: Dictionary, a: Vector3, b: Vector3, r: float, rp: Array, n := 4) -> void:
	if a.distance_to(b) < 0.01:
		return
	M.cyl(pt, T, (a + b) * 0.5, b - a, r, a.distance_to(b) * 0.5, n, rp, {"edge": false})


## Seated gunner (sealed suit, amber faceplate, team armbands) at local point g of pod pose Tp. lean: forward
## pitch (rad, + = toward the gun), roll (+ = to the right); hands: two local points of Tp the arms reach to.
static func gunner(pt: Dictionary, Tp: Dictionary, g: Vector3, burnt := false, lean := 0.0, roll := 0.0, hands: Array = []) -> void:
	var su: Array = C.ramp(BURNT if burnt else SUIT)
	var Tg := M.sub(Tp, g, 0.0, -lean, roll)
	M.box(pt, Tg, Vector3(0, 0, 0.18), Vector3(0.14, 0.24, 0.18), su, Vector3(0.0, 0.0, 0.06))
	M.cyl(pt, Tg, Vector3(0.02, 0, 0.47), Vector3(0, 0, 1), 0.15, 0.13, 8, su, {"cap_t": 3}, 0.2)
	if burnt:
		return
	M.dpx(pt, Tg, Vector3(0.17, 0.0, 0.47), VISOR, Vector3(1, 0, 0))
	M.dpx(pt, Tg, Vector3(0.16, -0.07, 0.45), C.ramp(VISOR)[1], Vector3(1, 0, 0))
	for s in [-1.0, 1.0]:
		M.dpx(pt, Tg, Vector3(0.0, s * 0.25, 0.26), TEAMG, Vector3(0, s, 0), true)
	for i in hands.size():   # arms: shoulder -> hand (gloves dark)
		var s := -1.0 if i == 0 else 1.0
		var sh := M.wm(Tg, Vector3(0.03, s * 0.21, 0.31))
		var hw: Vector3 = M.wm(Tp, hands[i])
		var Tw := M.pose(Tp.o, 0.0)
		rod(pt, Tw, sh, hw, 0.045, su)
		M.cyl(pt, Tw, hw, Vector3(0, 0, 1), 0.04, 0.03, 4, C.ramp(DARK), {"edge": false})


## Muzzle flash (kept for g7_turrets2.gd): a bright core with a forward tongue and a tracer streak.
static func _flash(pt: Dictionary, Tp: Dictionary, m: Vector3) -> void:
	pt.dec.append({"k": "px", "a": M.wm(Tp, m), "col": GR.FLASH, "n": Vector3.ZERO})
	for i in 4:
		var q := M.wm(Tp, m + Vector3(0.1 + i * 0.1, (i % 3 - 1) * 0.07, (i % 2) * 0.06))
		pt.dec.append({"k": "px", "a": q, "col": GR.FLASH_O if i % 2 == 1 else GR.FLASH, "n": Vector3.ZERO})
	pt.dec.append({"k": "line", "a": M.wm(Tp, m + Vector3(0.2, 0, 0)), "b": M.wm(Tp, m + Vector3(2.2, 0, 0.06)),
		"col": Color(1.0, 0.86, 0.5, 0.8), "n": Vector3.ZERO})


## .50 cal firing cycle effects at muzzle m of gun pose Tg, phase 0..3 (0/2 full flash, 1 flash dying, 3 smoke),
## ejected brass on the right of the receiver (falling through the cycle) in pod pose Tp.
static func _burst(pt: Dictionary, Tg: Dictionary, Tp: Dictionary, m: Vector3, ph: int, ej: Vector3) -> void:
	var W := func(q: Vector3): return M.wm(Tg, q)
	if ph == 0 or ph == 2:
		var sp := 1.0 if ph == 0 else 0.7
		pt.dec.append({"k": "px", "a": W.call(m), "col": Color8(255, 255, 230), "n": Vector3.ZERO})
		for i in 3:   # forward tongue
			pt.dec.append({"k": "px", "a": W.call(m + Vector3(0.09 + i * 0.09, 0, 0)), "col": GR.FLASH if i < 2 else GR.FLASH_O, "n": Vector3.ZERO})
		for s in [-1.0, 1.0]:   # muzzle-brake side jets (star)
			pt.dec.append({"k": "px", "a": W.call(m + Vector3(0.02, s * 0.11 * sp, 0.0)), "col": GR.FLASH, "n": Vector3.ZERO})
			pt.dec.append({"k": "px", "a": W.call(m + Vector3(0.05, s * 0.07, s * 0.09 * sp)), "col": GR.FLASH_O, "n": Vector3.ZERO})
		pt.dec.append({"k": "line", "a": W.call(m + Vector3(0.35, 0, 0)), "b": W.call(m + Vector3(2.3 if ph == 0 else 1.6, 0, 0.04)),
			"col": Color(1.0, 0.86, 0.5, 0.75), "n": Vector3.ZERO})
	elif ph == 1:
		pt.dec.append({"k": "px", "a": W.call(m + Vector3(0.05, 0, 0)), "col": GR.FLASH_O, "n": Vector3.ZERO})
		pt.dec.append({"k": "px", "a": W.call(m + Vector3(0.14, 0, 0.03)), "col": Color(1.0, 0.6, 0.25, 0.6), "n": Vector3.ZERO})
	var ns := 0 if ph == 0 else (2 if ph == 1 else 3)
	for i in ns:   # muzzle smoke drifting up
		pt.dec.append({"k": "px", "a": W.call(m + Vector3(0.05 + i * 0.07, 0.03 * i, 0.06 + i * 0.07 + ph * 0.03)),
			"col": Color(0.82, 0.8, 0.76, 0.5 - i * 0.12), "n": Vector3.ZERO})
	var brass: Array = [[Vector3(0.0, 0.08, 0.06)], [Vector3(-0.02, 0.2, 0.12), Vector3(0.02, 0.12, 0.05)],
		[Vector3(-0.05, 0.32, -0.05), Vector3(0.0, 0.1, 0.07)], [Vector3(-0.08, 0.4, -0.3), Vector3(-0.02, 0.22, 0.1)]][ph]
	for q in brass:
		pt.dec.append({"k": "px", "a": M.wm(Tp, ej + q), "col": BRASS, "n": Vector3.ZERO})


## M2 .50 on its cradle in pod pose Tp: receiver with feed cover (open while reloading), spade grips, ventilated
## barrel jacket, heavy barrel and muzzle brake, reflex sight, ammo can + belt on the left. Returns the gun pose.
static func m2(pt: Dictionary, Tp: Dictionary, at: Vector3, recoil: float, elev: float, cover_open: bool, can: int) -> Dictionary:
	var gm: Array = C.ramp(GR.GUNM)
	var dk: Array = C.ramp(DARK)
	rod(pt, Tp, Vector3(at.x - 0.05, 0, 0.12), Vector3(at.x - 0.02, 0, at.z - 0.05), 0.05, dk, 5)   # pintle post
	var Tg := M.sub(Tp, at + Vector3(-recoil, 0, 0), 0.0, elev)
	M.box(pt, Tg, Vector3(0, 0, 0), Vector3(0.22, 0.065, 0.07), gm)
	if cover_open:
		M.box(pt, M.sub(Tg, Vector3(0.18, 0, 0.075), 0.0, 1.1), Vector3(-0.17, 0, 0.012), Vector3(0.17, 0.06, 0.012), gm)
	else:
		M.box(pt, Tg, Vector3(0.02, 0, 0.082), Vector3(0.17, 0.06, 0.012), gm)
		M.box(pt, Tg, Vector3(-0.02, 0, 0.12), Vector3(0.05, 0.025, 0.03), dk)   # sight
		M.dpx(pt, Tg, Vector3(0.035, 0, 0.12), GLASS, Vector3(1, 0, 0))
	for s in [-1.0, 1.0]:   # spade grips
		M.box(pt, Tg, Vector3(-0.27, s * 0.05, 0.0), Vector3(0.03, 0.014, 0.045), dk)
	M.cyl(pt, Tg, Vector3(0.33, 0, 0.0), Vector3(1, 0, 0), 0.045, 0.11, 6, gm, {"edge": false})   # barrel jacket
	for i in 3:
		M.dpx(pt, Tg, Vector3(0.28 + i * 0.05, 0, 0.046), Color8(18, 18, 20), Vector3(0, 0, 1))
	M.cyl(pt, Tg, Vector3(0.78, 0, 0.0), Vector3(1, 0, 0), 0.026, 0.34, 4, gm, {"edge": false})
	M.cyl(pt, Tg, Vector3(1.15, 0, 0.0), Vector3(1, 0, 0), 0.042, 0.04, 6, gm, {"edge": false, "cap_t": 0})
	M.dpx(pt, Tg, Vector3(0.52, 0, 0.04), dk[3], Vector3(0, 0, 1))   # carry handle
	# ammo can on the left bracket: 0 fitted, 1 empty can lifted out, 2 fresh can going in (-1 = none)
	var cans := {0: Vector3(0.0, -0.2, -0.04), 1: Vector3(-0.22, -0.4, 0.16), 2: Vector3(-0.08, -0.3, 0.1)}
	if cans.has(can):
		var cc: Vector3 = cans[can]
		M.box(pt, Tg, cc, Vector3(0.13, 0.055, 0.085), C.ramp(CAN), Vector3(0.0, 0.0, 0.01))
		M.dline(pt, Tg, cc + Vector3(-0.1, -0.056, 0.03), cc + Vector3(0.1, -0.056, 0.03), C.ca(C.ramp(CAN)[4], 0.6), Vector3(0, -1, 0))
		if can == 0:
			for i in 3:   # brass belt from the can into the feed tray
				M.dpx(pt, Tg, cc + Vector3(-0.04 + i * 0.05, 0.07 + i * 0.03, 0.09), BRASS)
	if can == 2 or cover_open:   # belt end held up to the open tray
		M.dpx(pt, Tg, Vector3(0.0, -0.07, 0.09), BRASS)
	return Tg


## Shielded .50 pod (manned): ring, three-plate faceted shield with a glazed vision block and bolt heads, the M2
## on its cradle, the seated gunner whose arms hold the spade grips. st: fire (-1 or phase 0..3), reload (-1 or
## 0..2: cover open + empty can out, fresh can in, cover shut + charge), burnt.
static func pod(S: Array, T: Dictionary, at: Vector3, yaw: float, hull: Array, st, burnt := false) -> void:
	var fire := -1
	var rl := -1
	if typeof(st) == TYPE_BOOL:
		fire = 0 if st else -1
	elif typeof(st) == TYPE_DICTIONARY:
		fire = int(st.get("fire", -1))
		rl = int(st.get("reload", -1))
	var jit: float = 0.0 if fire < 0 else [0.025, -0.01, -0.02, 0.0][fire]
	var Tp := M.sub(T, at, yaw + jit)
	var pt := M.part(S, 2)
	var dk: Array = C.ramp(DARK)
	M.cyl(pt, Tp, Vector3(0, 0, 0.08), Vector3(0, 0, 1), 0.56, 0.08, 10, hull, {"cap_t": 2})
	for i in 8:   # ring bolts
		var t := TAU * i / 8.0
		M.dpx(pt, Tp, Vector3(cos(t) * 0.5, sin(t) * 0.5, 0.165), hull[0], Vector3(0, 0, 1))
	var recoil: float = 0.0 if fire < 0 else [0.06, 0.02, 0.05, 0.0][fire]
	var lean := 0.0
	var roll := 0.0
	var hands: Array = [Vector3(0.0 - recoil, -0.05, 0.62), Vector3(0.0 - recoil, 0.05, 0.62)]
	if rl == 0:
		lean = -0.1
		roll = -0.25
		hands = [Vector3(0.02, -0.4, 0.75), Vector3(0.1, -0.32, 0.7)]
	elif rl == 1:
		lean = 0.15
		roll = -0.15
		hands = [Vector3(0.2, -0.33, 0.7), Vector3(0.25, -0.1, 0.72)]
	elif rl == 2:
		lean = -0.2
		hands = [Vector3(0.05, 0.08, 0.66), Vector3(0.02, 0.05, 0.62)]
	if not burnt:
		var can := 0
		if rl == 0:
			can = 1
		elif rl == 1:
			can = 2
		var Tg := m2(pt, Tp, Vector3(0.27, 0, 0.62), recoil, 0.04, rl == 0 or rl == 1, can)
		if fire >= 0:
			_burst(pt, Tg, Tp, Vector3(1.2, 0, 0), fire, Vector3(0.27, 0.1, 0.62))
	gunner(pt, Tp, Vector3(-0.22, 0, 0.16), burnt, lean, roll, hands if not burnt else [])
	M.box(pt, Tp, Vector3(0.46, 0, 0.5), Vector3(0.035, 0.25, 0.33), hull, Vector3(0.0, 0.0, 0.03))   # centre plate
	for s in [-1.0, 1.0]:
		M.box(pt, M.sub(Tp, Vector3(0.33, s * 0.42, 0.5), s * 0.62), Vector3.ZERO, Vector3(0.03, 0.17, 0.31), hull)
		M.dpx(pt, Tp, Vector3(0.5, s * 0.18, 0.74), hull[0], Vector3(1, 0, 0))
		M.dpx(pt, Tp, Vector3(0.5, s * 0.18, 0.26), hull[0], Vector3(1, 0, 0))
	M.box(pt, Tp, Vector3(0.5, 0.13, 0.76), Vector3(0.02, 0.07, 0.04), C.ramp(GLASS))   # vision block
	M.dline(pt, Tp, Vector3(0.5, -0.2, 0.5), Vector3(0.5, -0.04, 0.5), Color8(24, 26, 26), Vector3(1, 0, 0))


## Remote twin .50 weapon station (tactical APC): turret ring, armoured cradle, sensor head with day/thermal
## windows, two barrels with brakes, an ammo bin each side. st: fire phase (barrels alternate), reload 0..2 (the
## commander's hatch behind it opens, a crewman swaps the right-hand bin).
static func rws(S: Array, T: Dictionary, at: Vector3, yaw: float, hull: Array, st) -> void:
	var fire := -1
	var rl := -1
	if typeof(st) == TYPE_BOOL:
		fire = 0 if st else -1
	elif typeof(st) == TYPE_DICTIONARY:
		fire = int(st.get("fire", -1))
		rl = int(st.get("reload", -1))
	var Tp := M.sub(T, at, yaw + (0.0 if fire < 0 else [0.02, -0.01, -0.02, 0.0][fire]))
	var pt := M.part(S, 2)
	var dk: Array = C.ramp(DARK)
	var gm: Array = C.ramp(GR.GUNM)
	M.cyl(pt, Tp, Vector3(0, 0, 0.07), Vector3(0, 0, 1), 0.5, 0.07, 10, hull, {"cap_t": 2})
	M.box(pt, Tp, Vector3(0.0, 0, 0.34), Vector3(0.34, 0.24, 0.18), hull, Vector3(0.12, 0.05, 0.05))   # armoured cradle
	M.box(pt, Tp, Vector3(-0.05, -0.4, 0.5), Vector3(0.15, 0.1, 0.14), dk, Vector3(0.03, 0.0, 0.02))   # sensor head
	M.box(pt, Tp, Vector3(0.11, -0.43, 0.5), Vector3(0.012, 0.035, 0.035), C.ramp(GLASS))
	M.box(pt, Tp, Vector3(0.11, -0.35, 0.53), Vector3(0.012, 0.03, 0.03), C.ramp(Color8(150, 60, 50)))
	M.box(pt, Tp, Vector3(-0.05, -0.3, 0.5), Vector3(0.05, 0.03, 0.05), dk)   # sensor arm
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var rc := 0.0 if fire < 0 or (fire % 2) != i else 0.05
		var Tg := M.sub(Tp, Vector3(0.3 - rc, s * 0.11, 0.42), 0.0, 0.04)
		M.cyl(pt, Tg, Vector3(0.12, 0, 0), Vector3(1, 0, 0), 0.04, 0.1, 6, gm, {"edge": false})
		M.cyl(pt, Tg, Vector3(0.6, 0, 0), Vector3(1, 0, 0), 0.026, 0.38, 4, gm, {"edge": false})
		M.cyl(pt, Tg, Vector3(1.0, 0, 0), Vector3(1, 0, 0), 0.04, 0.04, 6, gm, {"edge": false, "cap_t": 0})
		if fire >= 0 and (fire % 2) == i:
			_burst(pt, Tg, Tp, Vector3(1.05, 0, 0), [0, 1, 2, 3][fire], Vector3(0.1, s * 0.3, 0.42))
		elif fire >= 0:
			_burst(pt, Tg, Tp, Vector3(1.05, 0, 0), 3, Vector3(0.1, s * 0.3, 0.42))
	var bins := {0: Vector3(-0.2, 0.33, 0.33), 1: Vector3(-0.55, 0.62, 0.62), 2: Vector3(-0.42, 0.5, 0.5)}
	M.box(pt, Tp, Vector3(-0.2, -0.33, 0.3), Vector3(0.13, 0.08, 0.1), C.ramp(CAN))
	var b: int = 0 if rl < 0 else [1, 2, 0][rl]
	M.box(pt, Tp, bins[b], Vector3(0.13, 0.08, 0.1), C.ramp(CAN))
	if rl >= 0:   # crewman out of the hatch behind the RWS
		M.box(pt, Tp, Vector3(-0.85, 0.15, 0.03), Vector3(0.3, 0.3, 0.03), hull)
		gunner(pt, Tp, Vector3(-0.85, 0.15, -0.18), false, 0.2, 0.0, [bins[b] + Vector3(0.0, -0.06, 0.08), bins[b] + Vector3(0.1, 0.0, 0.08)])


## Pop-out 6-tube micro rocket pod at roof point `at`. st (int, for old callers): 0 stowed, 1 raised, 2 firing.
## st (Dictionary): {"raise": 0..1} half / fully raised, {"fire": n} tube n launching (ripple 0..5: tubes already
## fired are sooty, the previous rocket is still in the air), {"reload": n} canister swap 0..3 (launcher levels,
## spent 6-pack slides out of the back, a fresh one slides in, locks and starts to rise).
static func rocket_pod(S: Array, T: Dictionary, at: Vector3, hull: Array, st) -> void:
	var d := {}
	if typeof(st) == TYPE_DICTIONARY:
		d = st
	elif int(st) == 1:
		d = {"raise": 1}
	elif int(st) == 2:
		d = {"fire": 2}
	var pt := M.part(S, 2)
	var dk: Array = C.ramp(DARK)
	var h := 0.0
	var pitch := 0.0
	var door := 0.0
	var slide := 0.0
	var fresh := true
	var fired := -1
	if d.has("raise"):
		h = 0.38 if int(d.raise) == 0 else 0.78
		pitch = 0.0 if int(d.raise) == 0 else 0.42
		door = 1.0 if int(d.raise) == 0 else 1.75
	elif d.has("fire"):
		fired = int(d.fire)
		h = 0.78
		pitch = 0.42 + (0.025 if fired % 2 == 0 else -0.015)
		door = 1.75
	elif d.has("reload"):
		var n := int(d.reload)
		h = [0.45, 0.45, 0.45, 0.6][n]
		pitch = [0.0, 0.0, 0.0, 0.18][n]
		door = 1.75
		slide = [0.0, -0.55, -0.35, 0.0][n]
		fresh = n >= 2
	# roof hatch: two doors hinged on their outer edges (flush when stowed)
	for s in [-1.0, 1.0]:
		var Td := M.sub(T, at + Vector3(0, s * 0.36, 0.0), 0.0, 0.0, s * door)
		M.box(pt, Td, Vector3(0, -s * 0.18, 0.04), Vector3(0.52, 0.18, 0.04), hull)
	if h <= 0.0:
		for s in [-1.0, 1.0]:
			M.dline(pt, T, at + Vector3(0.5, s * 0.02, 0.085), at + Vector3(-0.5, s * 0.02, 0.085), C.ca(hull[0], 0.9), Vector3(0, 0, 1))
		return
	M.box(pt, T, at + Vector3(0, 0, 0.02), Vector3(0.5, 0.34, 0.02), dk)   # open well
	for s in [-1.0, 1.0]:   # lift rams
		rod(pt, T, at + Vector3(-0.3, s * 0.2, 0.03), at + Vector3(-0.1, s * 0.2, h - 0.05), 0.045, dk)
		rod(pt, T, at + Vector3(0.25, s * 0.2, 0.03), at + Vector3(0.05, s * 0.2, h - 0.08), 0.035, C.ramp(Color8(150, 154, 150)))
	var Tr := M.sub(T, at + Vector3(0.0, 0, h + 0.05), 0.0, pitch)
	M.box(pt, Tr, Vector3(-0.05, 0, -0.27), Vector3(0.42, 0.3, 0.03), dk)   # cradle
	var Tc := M.sub(Tr, Vector3(slide, 0, 0))
	var gm: Array = C.ramp(P.mul(hull[2], 0.92))
	for i in 6:   # tubes: 2 rows x 3
		var c := Vector3(0, (float(i % 3) - 1.0) * 0.21, 0.1 if i < 3 else -0.1)
		M.cyl(pt, Tc, c, Vector3(1, 0, 0), 0.098, 0.48, 6, gm, {"edge": false, "cap_t": 0}, PI / 6.0)
		var spent := (not fresh) or (fired >= 0 and i <= fired)
		M.dpx(pt, Tc, c + Vector3(0.485, 0.0, 0.07), Color8(40, 36, 32) if spent else CANISTERS[i], Vector3(1, 0, 0))
		M.dpx(pt, Tc, c + Vector3(0.485, 0.05, 0.05), Color8(40, 36, 32) if spent else C.ramp(CANISTERS[i])[1], Vector3(1, 0, 0))
	for s in [-1.0, 1.0]:   # armour side plates + top plate with a stencil band
		M.box(pt, Tc, Vector3(0, s * 0.33, 0), Vector3(0.46, 0.02, 0.22), hull)
	M.box(pt, Tc, Vector3(0, 0, 0.215), Vector3(0.46, 0.33, 0.015), hull)
	M.dline(pt, Tc, Vector3(0.3, -0.25, 0.232), Vector3(0.3, 0.25, 0.232), C.ca(Color8(230, 200, 60), 0.8), Vector3(0, 0, 1))
	M.box(pt, Tr, Vector3(-0.2, 0.4, 0.05), Vector3(0.08, 0.05, 0.07), dk)   # fire-control optic
	M.dpx(pt, Tr, Vector3(-0.115, 0.4, 0.07), GLASS, Vector3(1, 0, 0))
	if fired >= 0:
		var c := Vector3(0, (float(fired % 3) - 1.0) * 0.21, 0.1 if fired < 3 else -0.1)
		var W := func(q: Vector3): return M.wm(Tc, q)
		pt.dec.append({"k": "px", "a": W.call(c + Vector3(0.55, 0, 0)), "col": Color8(255, 255, 230), "n": Vector3.ZERO})
		for i in 3:   # tube flash
			pt.dec.append({"k": "px", "a": W.call(c + Vector3(0.62 + i * 0.08, (i - 1) * 0.06, 0.02)), "col": GR.FLASH if i != 1 else GR.FLASH_O, "n": Vector3.ZERO})
		var rk := c + Vector3(1.05, 0, 0)   # the rocket just out of the tube, motor lit
		pt.dec.append({"k": "line", "a": W.call(rk), "b": W.call(rk + Vector3(0.22, 0, 0)), "col": Color8(70, 74, 70), "n": Vector3.ZERO})
		pt.dec.append({"k": "px", "a": W.call(rk + Vector3(-0.05, 0, 0)), "col": GR.FLASH, "n": Vector3.ZERO})
		for i in 6:   # backblast cone + smoke behind the tube
			var q := c + Vector3(-0.6 - i * 0.16, (P.hn(i, fired, 7) - 0.5) * (0.1 + i * 0.07), -0.04 - i * 0.04 + P.hn(i, fired, 9) * 0.08)
			pt.dec.append({"k": "px", "a": W.call(q), "col": (GR.FLASH if i == 0 else GR.FLASH_O) if i < 2 else Color(0.8, 0.78, 0.74, 0.62 - i * 0.07), "n": Vector3.ZERO})
		if fired > 0:   # the previous rocket further out, a smoke trail behind it
			var pc := Vector3(0, (float((fired - 1) % 3) - 1.0) * 0.21, 0.1 if fired - 1 < 3 else -0.1)
			var a := pc + Vector3(2.4, 0, 0.1)
			pt.dec.append({"k": "line", "a": W.call(pc + Vector3(0.7, 0, 0)), "b": W.call(a), "col": Color(0.86, 0.84, 0.8, 0.45), "n": Vector3.ZERO})
			pt.dec.append({"k": "px", "a": W.call(a), "col": GR.FLASH, "n": Vector3.ZERO})
			pt.dec.append({"k": "px", "a": W.call(a + Vector3(-0.1, 0, 0)), "col": GR.FLASH_O, "n": Vector3.ZERO})


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


## Weapon states for frame fname: front pod / RWS, rear pod and rocket pod (see pod(), rws(), rocket_pod()).
static func wpn_state(fname: String) -> Dictionary:
	var n := int(fname.get_slice("_", fname.get_slice_count("_") - 1)) if fname.get_slice_count("_") > 1 else 0
	var r := {"pod": {}, "pod_r": {}, "rk": 0}
	if fname == "fire":
		r.pod = {"fire": 0}
	elif fname == "fire_r":
		r.pod_r = {"fire": 0}
	elif fname.begins_with("fire_r_"):
		r.pod_r = {"fire": n}
	elif fname.begins_with("fire_"):
		r.pod = {"fire": n}
	elif fname.begins_with("reload_r_"):
		r.pod_r = {"reload": n}
	elif fname.begins_with("reload_"):
		r.pod = {"reload": n}
	elif fname == "rockets_up":
		r.rk = {"raise": 1}
	elif fname == "rockets_fire":
		r.rk = {"fire": 2}
	elif fname.begins_with("rk_raise_"):
		r.rk = {"raise": n}
	elif fname.begins_with("rk_fire_"):
		r.rk = {"fire": n}
	elif fname.begins_with("rk_reload_"):
		r.rk = {"reload": n}
	return r


## The whole vehicle into scene S at ground pose T. fname picks the state; wreck = burnt hull.
static func model(S: Array, T: Dictionary, big: bool, fname: String, wreck := false, stowed := false) -> void:
	var sp: Dictionary = SPEC[big]
	var dmg := fname == "damaged"   # ART7D: G6.1 damaged state (hp < 50 %): scorched, smoking, still running
	var hull: Array = C.ramp(BURNT if wreck else ((HULL_CN if big else HULL_OP).lerp(BURNT, 0.38) if dmg else (HULL_CN if big else HULL_OP)))
	var low: Array = C.ramp(P.mul(BURNT, 0.8) if wreck else (LOW_CN if big else LOW_OP))
	var dk: Array = C.ramp(DARK)
	var roof: float = sp.roof
	var wr: float = sp.wr
	# ART7D: track_1 / track_2 = G6.1 wheel phases after "move" (spin, suspension bob); recoil = hull kick after a shot
	var ph := {"move": 1.0, "move_1": 2.0, "track_1": 1.5, "track_2": 2.5}.get(fname, 0.0) as float
	var spin := ph * TAU / 12.0
	var bob := {"move": 0.06, "move_1": -0.04, "track_1": 0.0, "track_2": -0.06, "recoil": -0.04}.get(fname, 0.0) as float
	var pitch := {"move": 0.02, "move_1": -0.015, "track_1": -0.01, "track_2": 0.025, "recoil": 0.045}.get(fname, 0.0) as float
	var roll := {"move": 0.015, "move_1": -0.02, "track_1": -0.01, "track_2": 0.02}.get(fname, 0.0) as float
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
			var bump := 0.08 if (fname == "move" and i == 1 and s > 0) or (fname == "move_1" and i == 2 and s < 0) 				or (fname == "track_1" and i == 3 and s > 0) or (fname == "track_2" and i == 0 and s < 0) else 0.0
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
	var mats := {}
	var rf: Array = C.ramp(BURNT if wreck else ROOF[big])
	for i in _upper(big).size() - 1:
		mats["%d,5" % i] = rf
	M.loft(up, Th, _secs(_upper(big)), hull, {"mats": mats})
	var ws := wpn_state(fname)
	_details(up, S, Th, big, hull, dk, wreck, stowed)
	var at_r: Vector3
	if big:
		pod(S, Th, Vector3(1.15, 0, roof), 0.9 if fname == "traverse" else 0.0, hull, ws.pod, wreck)
		pod(S, Th, Vector3(-2.0, -0.38, roof), PI - (1.3 if fname == "traverse" else 0.0), hull, ws.pod_r, wreck)
		at_r = Vector3(-3.1, 0.72, roof)
	else:
		if not wreck:
			rws(S, Th, Vector3(0.7, -0.1, roof), 0.9 if fname == "traverse" else 0.0, hull, ws.pod)
		at_r = Vector3(-2.55, 0.62, roof)
	rocket_pod(S, Th, at_r, hull, 0 if wreck else ws.rk)
	if fname == "panels_open" or fname == "launch":
		_panels(S, Th, big, hull, fname == "launch")
	if fname == "doors_open":
		_ramp(S, Th, big, low)
	if dmg:   # scorch blotches on the roof and flanks, smoke curling off the engine deck
		var sc := M.part(S, 3)
		for i in 14:
			var q := Vector3((P.hn(i, 3, 7) - 0.5) * float(sp.L) * 0.8, (P.hn(i, 11, 2) - 0.5) * float(sp.W) * 0.9, roof + 0.02)
			sc.dec.append({"k": "px", "a": M.wm(Th, q), "col": Color(0.10, 0.09, 0.08, 0.85), "n": Vector3.ZERO})
		var du2 := M.part(S, 4)
		for i in 9:
			var q := Vector3(-float(sp.L) * 0.3 + P.hn(i, 4, 1) * 0.6, 0.4 + (P.hn(i, 8, 5) - 0.5) * 0.6, roof + 0.3 + i * 0.32)
			du2.dec.append({"k": "px", "a": M.wm(Th, q), "col": Color(0.30, 0.29, 0.27, 0.75 - i * 0.06), "n": Vector3.ZERO})
			du2.dec.append({"k": "px", "a": M.wm(Th, q + Vector3(0.12, 0.1, 0.05)), "col": Color(0.42, 0.40, 0.37, 0.6 - i * 0.05), "n": Vector3.ZERO})
	if fname.begins_with("move") or fname.begins_with("track"):
		var du := M.part(S, -1)
		for i in 7:
			var q := Vector3(float(ax[3]) - wr - 0.2 - P.hn(i, int(ph), 3) * 1.2, (P.hn(i, 5, int(ph)) - 0.5) * 3.0, P.hn(i, 9, 2) * 0.3)
			du.dec.append({"k": "px", "a": M.wm(T, q), "col": DUST, "n": Vector3.ZERO})


## Hull furniture: optics, lights, smoke dischargers, antennas, stowage, tow points, seams, hatches, team marks.
## stowed: whip antennas folded back flat along the roof (inside a dropship bay).
static func _details(up: Dictionary, S: Array, T: Dictionary, big: bool, hull: Array, dk: Array, wreck: bool, stowed := false) -> void:
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
		var tip := b + (Vector3(1.4, -s * 0.05, 0.22) if stowed else Vector3(-0.25, s * 0.08, 1.45))
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


## ART7D (ORCH / CNFAC7-3 finding): rows 1 and 5 face straight down / up the screen, where the 30 deg camera saw only
## the roof and the long glacis (wheels tucked under the sponsons): "a grey box". Those two rows turn the hull by
## HEAD_TWIST inside their 45 deg facing bin, so the head-on / tail-on view shows the nose or rear face, one flank
## and its wheels (a three-quarter view). Cells, pivots and frame names are unchanged.
const HEAD_TWIST := 0.36


static func row_yaw(k: int) -> float:
	return k * PI / 4.0 + (HEAD_TWIST if k == 1 or k == 5 else 0.0)


static func apc(cv, k: int, fname: String, o: Vector2, big: bool, wreck := false) -> void:
	var S: Array = []
	var T := M.pose(o, row_yaw(k))
	model(S, T, big, fname, wreck)
	M.shadow(cv, S, o)
	M.render_z(cv, S, o, 31 + k)
	if fname == "dome":
		dome(cv, o + Vector2(0, -4), 60.0 if big else 56.0, 28.0, 54.0)


static func build(out: Dictionary) -> void:
	for big in [true, false]:
		var id := "g7_cn_strike_apc" if big else "g7_op_tactical_apc"
		var frames: Array = (STRIKE_FRAMES if big else TAC_FRAMES) + ANIM61   # ART7D: + native G6.1 frames (appended)
		var b: bool = big
		C.unit_sheet(out, id, "vehicles", "vehicle", int(FW[b]), int(FH[b]), PIV[b], frames,
			func(cv, k, f, o): apc(cv, k, f, o, b),
			{"sample": "vehicle", "line": "strike_team" if b else "operators",
			"capacity": "10 + packages (PROVISIONAL)" if b else 8, "key_frames": frames.duplicate(),
			"size_m": [SPEC[b].L, SPEC[b].W, SPEC[b].roof], "scale": "4 m/tile, 9.8 px/m (fact art.scale)",
			"anim_strip": ["idle", "move", "move_1", "traverse", "fire", "panels_open", "rockets_up", "rockets_fire", "dome", "doors_open"]},
			func(cv, k, o): apc(cv, k, "idle", o, b, true))
		var gun: Array = GUN_STRIKE if b else GUN_TAC
		var ex := {"sample": "vehicle_anim", "line": "strike_team" if b else "operators", "scale": "4 m/tile, 9.8 px/m (fact art.scale)",
			"weapon_sheet_of": id, "pivot_note": "same cell and pivot as the main sheet"}
		var loops := {"fire": "fire_0..3 (burst loop, 12 fps)", "fire_r": "fire_r_0..3", "reload": "reload_0..2 then idle (box change)",
			"reload_r": "reload_r_0..2"}
		if not b:
			loops = {"fire": "fire_0..3 (barrels alternate)", "reload": "reload_0..2 then idle (crewman swaps a bin from the hatch)"}
		C.unit_sheet(out, id + "_gun", "vehicles", "vehicle", int(FW[b]), int(FH[b]), PIV[b], gun,
			func(cv, k, f, o): apc(cv, k, f, o, b),
			ex.merged({"key_frames": gun.duplicate(), "anim_strip": gun.duplicate(), "loops": loops}))
		C.unit_sheet(out, id + "_rkt", "vehicles", "vehicle", int(FW[b]), int(FH[b]), PIV[b], RKT,
			func(cv, k, f, o): apc(cv, k, f, o, b),
			ex.merged({"key_frames": RKT.duplicate(), "anim_strip": RKT.duplicate(), "frame_alias": RKT_ALIAS,
			"sequence": "idle -> rk_raise_0, rk_raise_1 -> rk_fire_0..5 (ripple, one tube per frame) -> rk_reload_0..3 (canister swap) -> rk_raise_1 ... -> rk_stow_0, rk_stow_1 -> idle"}))
