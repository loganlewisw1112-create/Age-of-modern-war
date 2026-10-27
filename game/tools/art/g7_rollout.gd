extends SceneTree
## G7 art roll-out (ART7B): the counter-nanite kit units and the Last Protocol / CN facility buildings at the
## owner-approved rev3 look (DL7-3, G7_REFERENCE "Look checkpoint rev3 decision"). Everything is modelled in real
## metres and rasterised by ARTCN7's faceted renderer (g7_cn_mesh.gd) at the ONE real-world scale (fact art.scale:
## 4 m per 64x32 tile, 9.8 px per metre of height; an 18 px soldier is 1.8 m).
## Units (manifest "vehicles", 8 facings): g7_cn_sentry, g7_cn_barrier.
## Buildings (g6_lib rot schema via bld2 below): a_cn_facility, b_cn_facility (Human B: warm sand / rust),
## cn_tower, cn_checkpoint (+ open), cn_blast_wall, cn_popup (+ lowered, rising, aim_<k>, aim_<k>_fire).
## Deterministic.   godot --headless --path . -s tools/art/g7_rollout.gd   (writes assets/art/g7_rollout/)
## Prints "G7_ART <id> bytes=<n> budget=<n> ok|OVER" and "G7_ART group=g7_rollout files=<n> over=<n>".

const GEN = preload("res://tools/gen_art.gd")
const P = preload("res://tools/art/pix.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")
const H = preload("res://tools/art/g6_lib.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const M = preload("res://tools/art/g7_cn_mesh.gd")
const GR = preload("res://tools/art/g7_cn_gear.gd")
const V = preload("res://tools/art/g7_cn_vehicles.gd")
const TU = preload("res://tools/art/g7_turrets2.gd")

const OUT := "res://assets/art/g7_rollout/"
const CONC := Color8(150, 148, 138)
const CONC_D := Color8(118, 116, 108)
const STEEL := Color8(84, 90, 96)
const SUIT := Color8(104, 112, 100)      # CN kit hull (strike APC grey-green)
const DARK := Color8(46, 50, 52)
const GLASS := Color8(70, 120, 140)
const CN_BLUE := Color8(110, 180, 255)
const CN_HOT := Color8(220, 240, 255)
const AMBER := Color8(246, 178, 60)
const LAMP_G := Color8(150, 255, 170)
const LAMP_R := Color8(255, 70, 50)
const LAMP_W := Color8(255, 244, 210)
const B_CONC := Color8(160, 138, 104)    # Human B: sand-washed concrete
const B_RUST := Color8(132, 82, 52)


static func _fin(cv, S: Array, o: Vector2, seed: int) -> void:
	M.shadow(cv, S, o)
	M.render(cv, S, o, seed)


## Vertical wall seams + a bevel line on face x = fx (normal +x) of a box spanning r0..r1, height 0..h.
static func seams(pt: Dictionary, T: Dictionary, fx: float, r0: float, r1: float, h: float, step: float, rp: Array, nl := Vector3(1, 0, 0)) -> void:
	var n := maxi(1, int(absf(r1 - r0) / step))
	for i in range(1, n):
		var r := lerpf(r0, r1, float(i) / n)
		var a := Vector3(fx, r, 0.15) if nl.x != 0.0 else Vector3(r, fx, 0.15)
		var b := Vector3(fx, r, h - 0.1) if nl.x != 0.0 else Vector3(r, fx, h - 0.1)
		M.dline(pt, T, a, b, C.ca(rp[1], 0.85), nl)


# ------------------------------------------------------------------ building sheet (half-rotation option)
## Like C.bld, but `half` draws rotations 0 and 1 only and reuses them for 2 and 3 (a 180-degree symmetric
## layout): keeps the 4x4 facility inside the building budget.
static func bld2(out: Dictionary, id: String, size: int, top: int, draw: Callable, extra: Array = [],
		g7x: Dictionary = {}, half := false) -> void:
	var man: Dictionary = out.manifest.get("buildings", {})
	var co0: Array = K.canvas(size, top)
	var o: Vector2 = co0[1]
	var entry := {"size": size, "pivot": [int(o.x), int(o.y)], "fw": int(co0[0].w), "fh": int(co0[0].h),
		"states": {}, "g6": {"variants": "rot", "faction": id.substr(0, 1)}}
	var seed := 7100 + absi(id.hash()) % 7919
	var bytes := 0
	for f in 4:
		if half and f >= 2:
			for nm in entry.states.keys():
				if String(nm).begins_with("rot_%d" % (f - 2)):
					entry.states[String(nm).replace("rot_%d" % (f - 2), "rot_%d" % f)] = (entry.states[nm] as Dictionary).duplicate()
			continue
		var cv = K.canvas(size, top)[0]
		draw.call(cv, o, f, {})
		var base = H.copy(cv)
		C.selout(cv)
		bytes += C._bput(out, entry, id, "rot_%d" % f, cv)
		var cf = K.canvas(size, top)[0]
		draw.call(cf, o, f, {"fire": true})
		C.selout(cf)
		if (cf.img as Image).get_data() != (cv.img as Image).get_data():
			bytes += C._bput(out, entry, id, "rot_%d_fire" % f, cf)
		var dm = H.copy(base)
		K.damage(dm, o, size, seed + f * 13)
		C.selout(dm)
		bytes += C._bput(out, entry, id, "rot_%d_damaged" % f, dm)
		for st in 3:
			bytes += C._bput(out, entry, id, "rot_%d_build_%d" % [f, st], H.stage(base, o, f, size, "a", st, seed + f))
	for e in extra:
		var cx = K.canvas(size, top)[0]
		draw.call(cx, o, 0, e[1])
		C.selout(cx)
		bytes += C._bput(out, entry, id, String(e[0]), cx)
	for nm in ["built:rot_0", "damaged:rot_0_damaged", "fire:rot_0_fire", "build_0:rot_0_build_0",
			"build_1:rot_0_build_1", "build_2:rot_0_build_2"]:
		var pr: PackedStringArray = nm.split(":")
		if entry.states.has(pr[1]):
			entry.states[pr[0]] = (entry.states[pr[1]] as Dictionary).duplicate()
	var g7 := {"detail_level": C.VERSION, "class": "building", "bytes": bytes, "budget": int(C.BUDGET.building),
		"art": "ART7B", "scale": "4 m/tile, 9.8 px/m (fact art.scale)"}
	g7.merge(g7x)
	entry["g7"] = g7
	man[id] = entry
	out.manifest["buildings"] = man
	var img: Image = out.images[String(entry.states.built.file)]
	C.icon(out, id, img, img.get_width(), img.get_height(), 0)


# ------------------------------------------------------------------ CN sentry turret (unit, tripod, ~1.4 m)
const SENTRY_FRAMES := ["idle", "move", "fire", "fire_1", "deploy_0", "deploy_1"]


static func sentry(cv, k: int, fname: String, o: Vector2) -> void:
	var S: Array = []
	var yaw := k * PI / 4.0
	var T := M.pose(o, yaw)
	var pt := M.part(S, 0)
	var hull: Array = C.ramp(SUIT)
	var dk: Array = C.ramp(DARK)
	var dep := {"move": 0.0, "deploy_0": 0.35, "deploy_1": 0.7}.get(fname, 1.0) as float
	var hz := 0.35 + 0.6 * dep
	for i in 3:   # tripod legs splay out as it deploys
		var a := PI + (float(i) - 1.0) * 1.9 * dep + (0.0 if i == 1 else 0.0)
		var foot := Vector3(cos(a) * (0.2 + 0.7 * dep), sin(a) * (0.2 + 0.7 * dep), 0.03)
		var top := Vector3(0, 0, hz)
		var mid := (foot + top) * 0.5
		M.cyl(pt, T, mid, top - foot, 0.035, (top - foot).length() * 0.5, 4, dk, {"edge": false})
	if dep < 0.1:   # carry dolly wheels
		for s in [-1.0, 1.0]:
			M.cyl(pt, T, Vector3(-0.3, s * 0.3, 0.12), Vector3(0, 1, 0), 0.12, 0.04, 8, C.ramp(Color8(40, 40, 38)), {"cap_t": 1})
	var Th := M.sub(T, Vector3(0, 0, hz))
	M.box(pt, Th, Vector3(0.0, 0, 0.16), Vector3(0.32, 0.16, 0.14), hull, Vector3(0.1, 0.03, 0.03))
	TU.team_patch(pt, Th, Vector3(-0.05, 0, 0.305), Vector3(0.14, 0.1, 0.006), hull)
	M.cyl(pt, Th, Vector3(-0.05, 0.24, 0.12), Vector3(0, 1, 0), 0.13, 0.07, 8, C.ramp(Color8(92, 98, 64)), {"cap_t": 2})
	M.box(pt, Th, Vector3(0.12, -0.19, 0.26), Vector3(0.08, 0.05, 0.06), dk)
	M.dpx(pt, Th, Vector3(0.21, -0.19, 0.27), AMBER, Vector3(1, 0, 0))
	var rc := 0.06 if fname.begins_with("fire") else 0.0
	M.cyl(pt, Th, Vector3(0.62 - rc, 0, 0.16), Vector3(1, 0, 0), 0.045, 0.32, 6, dk, {"edge": false})
	M.box(pt, Th, Vector3(0.92 - rc, 0, 0.16), Vector3(0.05, 0.045, 0.045), dk)
	if fname.begins_with("fire"):
		var pf := M.part(S, 3)
		V._flash(pf, Th, Vector3(1.0 - rc, 0, 0.16))
		if fname == "fire_1":
			pf.dec.append({"k": "px", "a": M.wm(Th, Vector3(-0.1, -0.35, 0.3)), "col": Color8(220, 190, 90), "n": Vector3.ZERO})
	_fin(cv, S, o, 81 + k)


# ------------------------------------------------------------------ CN portable barrier (unit, 3.2 m armoured screen)
const BARRIER_FRAMES := ["idle", "move", "fire", "deploy_0", "deploy_1"]


static func barrier(cv, k: int, fname: String, o: Vector2) -> void:
	var S: Array = []
	var T := M.pose(o, k * PI / 4.0)
	var hull: Array = C.ramp(SUIT)
	var dk: Array = C.ramp(DARK)
	var dep := {"move": 0.0, "deploy_0": 0.35, "deploy_1": 0.7}.get(fname, 1.0) as float
	var pt := M.part(S, 0)
	M.box(pt, T, Vector3(0, 0, 0.12), Vector3(0.45, 0.8, 0.1), dk)   # skid / base
	for u in [-0.3, 0.36]:   # team plates on the skid deck (seen from every facing)
		TU.team_patch(pt, T, Vector3(u, 0, 0.225), Vector3(0.08, 0.6, 0.004), hull)
	for s in [-1.0, 1.0]:
		M.cyl(pt, T, Vector3(-0.3, s * 0.82, 0.13), Vector3(0, 1, 0), 0.13, 0.04, 8, C.ramp(Color8(40, 40, 38)), {"cap_t": 1})
	# the screen: centre panel + two wing panels that unfold sideways and stand up as it deploys
	var tilt := (1.0 - dep) * 1.45
	var Tc := M.sub(T, Vector3(0.15, 0, 0.22), 0.0, -tilt)
	M.box(pt, Tc, Vector3(0, 0, 0.7), Vector3(0.06, 0.6, 0.7), hull, Vector3.ZERO)
	TU.team_patch(pt, Tc, Vector3(0.065, 0, 1.25), Vector3(0.005, 0.3, 0.06), hull)
	M.dline(pt, Tc, Vector3(0.07, -0.25, 0.85), Vector3(0.07, 0.25, 0.85), Color8(24, 26, 26), Vector3(1, 0, 0))
	for s in [-1.0, 1.0]:
		var Tw := M.sub(Tc, Vector3(0, s * 0.6, 0), s * (1.0 - dep) * 2.6 * -1.0)
		var pw := M.part(S, 0)
		M.box(pw, Tw, Vector3(0, s * 0.5, 0.65), Vector3(0.05, 0.5, 0.65), hull)
		M.cyl(pw, Tw, Vector3(0.0, s * 1.02, 0.75), Vector3(0, 0, 1), 0.07, 0.78, 6, dk)   # emitter pylon
		M.dpx(pw, Tw, Vector3(0.0, s * 1.02, 1.56), CN_HOT if fname == "fire" else CN_BLUE)
	if dep >= 1.0:   # the counter-nanite field line between the pylons
		var a := M.wm(T, Vector3(0.15, -1.62, 1.5))
		var b := M.wm(T, Vector3(0.15, 1.62, 1.5))
		var fire := fname == "fire"
		var o2 := o
		M.sprite(S, (a + b) * 0.5 + Vector3(0.3, 0, 0), func(c2):
			var pa := M.scr_w(o2, a)
			var pb := M.scr_w(o2, b)
			for i in (5 if fire else 2):
				c2.line_v(pa + Vector2(0, i * 3), pb + Vector2(0, i * 3), Color(CN_BLUE, 0.55 if fire else 0.3))
			c2.line_v(pa, pb, Color(CN_HOT, 0.8 if fire else 0.45)), 4.0)
	_fin(cv, S, o, 83 + k)


# ------------------------------------------------------------------ CN facility (4x4 tiles = 16 m)
## Hardened two-storey command / package-lab block, vehicle bay with a blast door, CN agent tanks, roof plant,
## comms mast and a big roof ID panel (team). b = Human B: sand-washed concrete, rust tanks, sandbagged entry.
static func facility(cv, o: Vector2, f: int, opt: Dictionary, b: bool) -> void:
	var S: Array = []
	var T := M.pose(o, float(f) * PI / 2.0)
	var conc: Array = C.ramp(B_CONC if b else CONC)
	var cd: Array = C.ramp(P.mul(B_CONC, 0.82) if b else CONC_D)
	var st: Array = C.ramp(STEEL)
	var dk: Array = C.ramp(DARK)
	var pa := M.part(S, -2)   # apron slab with painted lanes
	M.box(pa, T, Vector3(0, 0, 0.08), Vector3(7.7, 7.7, 0.08), cd, Vector3(0.05, 0.05, 0.05))
	for s in [-1.0, 1.0]:
		M.dline(pa, T, Vector3(3.2, s * 2.4, 0.17), Vector3(7.4, s * 2.4, 0.17), AMBER, Vector3(0, 0, 1))
	var pm := M.part(S, 0)   # main block
	M.box(pm, T, Vector3(-2.2, 0.6, 3.3), Vector3(5.0, 6.2, 3.3), conc, Vector3(0.25, 0.25, 0.25))
	M.box(pm, T, Vector3(-2.2, 0.6, 6.62), Vector3(5.1, 6.3, 0.05), cd)   # roof parapet cap
	TU.team_patch(pm, T, Vector3(-3.4, 1.4, 6.68), Vector3(1.8, 1.8, 0.012), conc)   # roof ID panel
	seams(pm, T, 2.8, -5.4, 6.6, 6.5, 2.0, conc)
	seams(pm, T, 6.8, -7.0, 2.6, 6.5, 2.0, conc, Vector3(0, 1, 0))
	for i in 5:   # window slits, upper floor
		var r := -4.6 + i * 2.2
		M.dline(pm, T, Vector3(2.81, r, 4.9), Vector3(2.81, r + 1.0, 4.9), C.ca(Color8(30, 34, 38), 1.0), Vector3(1, 0, 0))
		M.dpx(pm, T, Vector3(2.81, r + 0.3, 4.95), GLASS, Vector3(1, 0, 0))
	for i in 4:
		M.dline(pm, T, Vector3(-6.0 + i * 2.2, 6.81, 4.9), Vector3(-5.0 + i * 2.2, 6.81, 4.9), C.ca(Color8(30, 34, 38), 1.0), Vector3(0, 1, 0))
	for fc in [[Vector3(2.81, -5.5, 0), Vector3(0, 12.0, 0), Vector3(1, 0, 0)], [Vector3(-7.1, 6.81, 0), Vector3(9.8, 0, 0), Vector3(0, 1, 0)]]:
		var a0: Vector3 = fc[0]
		var ax: Vector3 = fc[1]
		var nl: Vector3 = fc[2]
		M.dline(pm, T, a0 + Vector3(0, 0, 3.3), a0 + ax + Vector3(0, 0, 3.3), C.ca(cd[1], 0.9), nl)   # floor band
		M.dline(pm, T, a0 + Vector3(0, 0, 3.4), a0 + ax + Vector3(0, 0, 3.4), C.ca(conc[4], 0.35), nl)
		for j in 70:   # weathering: rain streaks, chips, grime toward the ground
			var u := P.hn(j, f, 41)
			var z := 0.3 + 6.0 * P.hn(j, 3, 43)
			var col := C.ca(conc[4], 0.5) if P.hn(j, 5, 47) < 0.35 else Color(0.2, 0.19, 0.16, 0.3 + 0.2 * (1.0 - z / 6.3))
			M.dpx(pm, T, a0 + ax * u + Vector3(0, 0, z), col, nl)
		for j in 3:   # lit windows (warm) on the lower floor
			M.dpx(pm, T, a0 + ax * (0.2 + 0.25 * j) + Vector3(0, 0, 1.9), LAMP_W if (j + f) % 2 == 0 else GLASS, nl)
	for i in range(1, 5):   # roof membrane seams + drains
		M.dline(pm, T, Vector3(-7.1 + i * 1.95, -5.5, 6.68), Vector3(-7.1 + i * 1.95, 6.7, 6.68), C.ca(cd[1], 0.7), Vector3(0, 0, 1))
	M.dpx(pm, T, Vector3(2.82, -5.2, 6.0), LAMP_G, Vector3(1, 0, 0))
	M.dpx(pm, T, Vector3(2.82, 6.4, 6.0), LAMP_R, Vector3(1, 0, 0))
	var pb := M.part(S, 1)   # vehicle bay annex + blast door
	M.box(pb, T, Vector3(4.6, -2.6, 2.3), Vector3(2.2, 3.4, 2.3), conc, Vector3(0.2, 0.0, 0.2))
	M.box(pb, T, Vector3(6.75, -2.6, 1.7), Vector3(0.06, 2.0, 1.7), st)
	for i in 6:
		M.dline(pb, T, Vector3(6.82, -4.5, 0.3 + i * 0.55), Vector3(6.82, -0.7, 0.3 + i * 0.55), C.ca(st[1], 0.9), Vector3(1, 0, 0))
	for i in 8:
		var r := -4.6 + i * 0.5
		M.dline(pb, T, Vector3(6.82, r, 3.55), Vector3(6.82, r + 0.25, 3.35), GR.HAZ if i % 2 == 0 else GR.HAZ_D, Vector3(1, 0, 0))
	M.dpx(pb, T, Vector3(6.82, -4.8, 3.7), AMBER, Vector3(1, 0, 0))
	TU.team_patch(pb, T, Vector3(4.4, -2.6, 4.63), Vector3(1.0, 1.4, 0.012), conc)
	for i in 2:   # CN agent tanks (B: rust)
		var pt := M.part(S, 1)
		var tk: Array = C.ramp(B_RUST if b else Color8(196, 200, 196))
		M.cyl(pt, T, Vector3(4.4 + i * 2.2, 4.6, 2.0), Vector3(0, 0, 1), 0.95, 2.0, 10, tk, {"cap_t": 3})
		M.dline(pt, T, Vector3(4.4 + i * 2.2 + 0.95, 4.6, 2.6), Vector3(4.4 + i * 2.2 + 0.95, 4.6, 3.0), CN_BLUE, Vector3(1, 0, 0))
		M.cyl(pt, T, Vector3(4.4 + i * 2.2, 3.4, 0.5), Vector3(0, 1, 0), 0.12, 0.7, 6, st, {"edge": false})
	var pr := M.part(S, 2)   # roof plant + comms mast
	M.box(pr, T, Vector3(-0.8, -3.5, 7.15), Vector3(1.2, 0.9, 0.5), st, Vector3(0.05, 0.05, 0.05))
	M.cyl(pr, T, Vector3(-0.8, -3.5, 7.68), Vector3(0, 0, 1), 0.55, 0.04, 8, dk, {"cap_t": 0})
	M.box(pr, T, Vector3(-5.4, -3.8, 7.0), Vector3(0.8, 1.2, 0.35), st)
	M.cyl(pr, T, Vector3(-6.0, 5.4, 8.8), Vector3(0, 0, 1), 0.08, 2.2, 4, dk, {"edge": false})
	M.cyl(pr, T, Vector3(-5.6, 5.4, 9.0), Vector3(1, 0, 0.6), 0.55, 0.05, 8, st, {"cap_t": 3})
	M.dpx(pr, T, Vector3(-6.0, 5.4, 11.05), LAMP_R)
	if b:   # sandbagged entry for Human B
		TU.sandbags(S, M.sub(T, Vector3(6.9, 1.6, 0.0)), 1.1, 2, 1.2, 5)
	_fin(cv, S, o, 91 + f)


# ------------------------------------------------------------------ hardened tower (2x2 tiles, ~11 m)
static func tower(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	var S: Array = []
	var T := M.pose(o, float(f) * PI / 2.0)
	var conc: Array = C.ramp(CONC)
	var st: Array = C.ramp(STEEL)
	var pt := M.part(S, 0)
	M.box(pt, T, Vector3(0, 0, 0.2), Vector3(3.2, 3.2, 0.2), C.ramp(CONC_D), Vector3(0.1, 0.1, 0.1))
	M.box(pt, T, Vector3(0, 0, 4.4), Vector3(1.6, 1.6, 4.2), conc, Vector3(0.5, 0.5, 0.5))   # tapered shaft
	seams(pt, T, 1.35, -1.2, 1.2, 8.4, 0.8, conc)
	for i in 10:   # ladder rungs on the side
		M.dline(pt, T, Vector3(0.8, 1.42 - i * 0.02, 0.6 + i * 0.8), Vector3(0.4, 1.42 - i * 0.02, 0.6 + i * 0.8), C.ca(st[0], 0.9), Vector3(0, 1, 0))
	var pc := M.part(S, 1)   # armoured cab
	M.box(pc, T, Vector3(0, 0, 9.7), Vector3(2.0, 2.0, 1.1), st, Vector3(0.0, 0.0, -0.15))
	M.box(pc, T, Vector3(0, 0, 10.9), Vector3(2.3, 2.3, 0.1), conc)
	TU.team_patch(pc, T, Vector3(0, 0, 11.02), Vector3(0.9, 0.9, 0.012), conc)
	for s in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, -1, 0)]:
		var c: Vector3 = s * 2.02 + Vector3(0, 0, 10.0)
		var t := Vector3(-s.y, s.x, 0)
		M.dline(pc, T, c - t * 1.4, c + t * 1.4, Color8(24, 26, 28), s)
		M.dpx(pc, T, c + t * 0.6, GLASS, s)
	M.cyl(pc, T, Vector3(1.6, -1.6, 11.3), Vector3(1, -1, -0.3), 0.25, 0.25, 8, st, {"cap_t": 4})   # searchlight
	M.dpx(pc, T, Vector3(1.9, -1.9, 11.2), LAMP_W)
	M.cyl(pc, T, Vector3(-1.6, 1.6, 12.4), Vector3(0, 0, 1), 0.04, 1.4, 4, C.ramp(DARK), {"edge": false})
	M.dpx(pc, T, Vector3(-1.6, 1.6, 13.85), LAMP_R)
	if bool(opt.get("fire", false)):
		TU.flash(S, T, Vector3(2.15, -0.6, 10.0))
	_fin(cv, S, o, 93 + f)


# ------------------------------------------------------------------ armoured gate checkpoint (2x2 tiles)
static func checkpoint(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	var S: Array = []
	var T := M.pose(o, float(f) * PI / 2.0)
	var conc: Array = C.ramp(CONC)
	var st: Array = C.ramp(STEEL)
	var pg := M.part(S, -1)
	M.box(pg, T, Vector3(0, 0, 0.05), Vector3(3.9, 3.9, 0.05), C.ramp(Color8(96, 98, 96)))
	for i in 7:   # rumble strip / stop line
		M.dline(pg, T, Vector3(1.6, -3.0 + i, 0.11), Vector3(1.6, -2.6 + i, 0.11), Color8(230, 228, 220), Vector3(0, 0, 1))
	var pb := M.part(S, 0)   # guard booth
	M.box(pb, T, Vector3(-1.0, 2.6, 1.3), Vector3(1.1, 1.0, 1.3), conc, Vector3(0.05, 0.05, 0.05))
	M.box(pb, T, Vector3(-1.0, 2.6, 2.7), Vector3(1.3, 1.2, 0.1), st)
	TU.team_patch(pb, T, Vector3(-1.0, 2.6, 2.81), Vector3(0.6, 0.5, 0.012), st)
	M.dline(pb, T, Vector3(0.11, 1.9, 1.8), Vector3(0.11, 3.3, 1.8), GLASS, Vector3(1, 0, 0))
	M.dline(pb, T, Vector3(0.11, 1.9, 1.7), Vector3(0.11, 3.3, 1.7), C.ramp(GLASS)[3], Vector3(1, 0, 0))
	M.dline(pb, T, Vector3(-2.0, 1.59, 1.8), Vector3(0.0, 1.59, 1.8), GLASS, Vector3(0, -1, 0))
	for s in [-1.0, 1.0]:   # jersey barriers channelling the lane
		for i in 3:
			var pj := M.part(S, 0)
			M.box(pj, T, Vector3(-2.6 + i * 1.9, s * 3.4 if s < 0 else 3.9, 0.45), Vector3(0.9, 0.3, 0.45), conc, Vector3(0.0, 0.0, 0.18))
	var open := bool(opt.get("open", false))
	var pa := M.part(S, 1)   # boom barrier
	M.box(pa, T, Vector3(0.6, 1.4, 0.55), Vector3(0.25, 0.25, 0.55), st)
	var Tb := M.sub(T, Vector3(0.6, 1.3, 1.0), -PI / 2.0, 0.0, -1.35 if open else 0.0)
	for i in 6:
		M.box(pa, Tb, Vector3(0, 0.15 + i * 0.75, 0), Vector3(0.06, 0.37, 0.06), C.ramp(Color8(212, 52, 44) if i % 2 == 0 else Color8(232, 230, 222)))
	M.dpx(pa, Tb, Vector3(0, 4.5, 0.1), LAMP_R)
	var pl := M.part(S, 2)   # light pole
	M.cyl(pl, T, Vector3(-3.0, -3.3, 2.6), Vector3(0, 0, 1), 0.07, 2.6, 4, C.ramp(DARK), {"edge": false})
	M.box(pl, T, Vector3(-2.6, -3.3, 5.2), Vector3(0.45, 0.12, 0.07), st)
	M.dpx(pl, T, Vector3(-2.3, -3.3, 5.1), LAMP_W)
	M.dpx(pl, T, Vector3(-3.0, -3.3, 4.4), LAMP_G if open else LAMP_R)
	_fin(cv, S, o, 95 + f)


# ------------------------------------------------------------------ blast wall (2x2 tiles of T-walls)
static func blast_wall(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	var S: Array = []
	var T := M.pose(o, float(f) * PI / 2.0)
	var conc: Array = C.ramp(CONC)
	for i in 5:
		var r := -3.04 + i * 1.52
		var pt := M.part(S, 0)
		var sk := 0.97 + 0.03 * P.hn(i, f, 7)
		M.box(pt, T, Vector3(0, r, 0.3), Vector3(0.65, 0.74, 0.3), conc, Vector3(0.0, 0.0, 0.0))   # foot
		M.box(pt, T, Vector3(0, r, 2.1 * sk), Vector3(0.17, 0.74, 1.5 * sk), conc, Vector3(0.0, 0.0, 0.03))
		M.dpx(pt, T, Vector3(0.18, r, 3.3), C.ramp(CONC)[0], Vector3(1, 0, 0))   # lifting eye
		M.dline(pt, T, Vector3(0.18, r - 0.5, 1.4), Vector3(0.18, r + 0.5, 1.4), C.ca(conc[1], 0.6), Vector3(1, 0, 0))
		if i == 2:
			TU.team_patch(pt, T, Vector3(0.18, r, 2.4), Vector3(0.005, 0.45, 0.25), conc)
			TU.team_patch(pt, T, Vector3(-0.18, r, 2.4), Vector3(0.005, 0.45, 0.25), conc)
		for j in 3:   # grime streaks
			var rr := r - 0.5 + P.hn(i, j, 3)
			M.dline(pt, T, Vector3(0.18, rr, 3.4), Vector3(0.18, rr, 2.5 - P.hn(j, i, 5)), Color(0.25, 0.24, 0.2, 0.35), Vector3(1, 0, 0))
			M.dline(pt, T, Vector3(-0.18, rr, 3.4), Vector3(-0.18, rr, 2.5 - P.hn(j, i, 5)), Color(0.25, 0.24, 0.2, 0.35), Vector3(-1, 0, 0))
	_fin(cv, S, o, 97 + f)


# ------------------------------------------------------------------ lockdown pop-up turret (1 tile)
## opt: lowered (flush hatch), rising (half up), aim (head yaw k*45 deg), fire.
static func popup(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	var S: Array = []
	var T := M.pose(o, float(f) * PI / 2.0)
	var st: Array = C.ramp(STEEL)
	var dk: Array = C.ramp(DARK)
	TU.pad(S, T, 1.3, 1.3, 0.06, Color8(104, 106, 102), 2, true)
	var pr := M.part(S, -1)
	M.cyl(pr, T, Vector3(0, 0, 0.13), Vector3(0, 0, 1), 0.85, 0.02, 12, dk, {"cap_t": 1})
	var up := 0.0 if bool(opt.get("lowered", false)) else (0.5 if bool(opt.get("rising", false)) else 1.0)
	var yaw := float(opt.aim) * PI / 4.0 if opt.has("aim") else float(f) * PI / 2.0 + PI / 4.0
	if up <= 0.0:
		M.cyl(pr, T, Vector3(0, 0, 0.17), Vector3(0, 0, 1), 0.75, 0.03, 12, st, {"cap_t": 2})
		for i in 4:
			var a := TAU * i / 4.0 + PI / 4.0
			M.dline(pr, T, Vector3(cos(a) * 0.2, sin(a) * 0.2, 0.21), Vector3(cos(a) * 0.7, sin(a) * 0.7, 0.21), GR.HAZ, Vector3(0, 0, 1))
		_fin(cv, S, o, 99 + f)
		return
	var Tg := M.pose(o, yaw, Vector3(0, 0, 0.15))
	var pt := M.part(S, 0)
	M.cyl(pt, Tg, Vector3(0, 0, 0.55 * up), Vector3(0, 0, 1), 0.6, 0.55 * up, 10, st, {"cap_t": 2})
	M.box(pt, Tg, Vector3(0.0, 0, 1.1 * up + 0.22), Vector3(0.5, 0.42, 0.22), st, Vector3(0.22, 0.06, 0.08))
	TU.team_patch(pt, Tg, Vector3(-0.1, 0, 1.1 * up + 0.445), Vector3(0.2, 0.2, 0.008), st)
	M.dpx(pt, Tg, Vector3(0.36, -0.25, 1.1 * up + 0.3), AMBER, Vector3(1, 0, 0))
	var rc := 0.1 if bool(opt.get("fire", false)) else 0.0
	for s in [-0.14, 0.14]:
		var mz := TU.barrel(pt, Tg, 0.4, 1.3, s, 1.1 * up + 0.2, 0.04, rc, DARK, false)
		if bool(opt.get("fire", false)):
			TU.flash(S, Tg, mz)
	_fin(cv, S, o, 99 + f)


# ------------------------------------------------------------------ build + generator
static func build(out: Dictionary) -> void:
	bld2(out, "a_cn_facility", 4, 112, func(cv, o, f, opt): facility(cv, o, f, opt, false), [], {"faction": "human_a"}, true)
	bld2(out, "b_cn_facility", 4, 112, func(cv, o, f, opt): facility(cv, o, f, opt, true), [], {"faction": "human_b"}, true)
	bld2(out, "cn_tower", 2, 112, func(cv, o, f, opt): tower(cv, o, f, opt))
	bld2(out, "cn_checkpoint", 2, 40, func(cv, o, f, opt): checkpoint(cv, o, f, opt), [["open", {"open": true}]])
	bld2(out, "cn_blast_wall", 2, 36, func(cv, o, f, opt): blast_wall(cv, o, f, opt))
	var px: Array = [["lowered", {"lowered": true}], ["rising", {"rising": true}]]
	for k in 8:
		px.append(["aim_%d" % k, {"aim": k}])
		px.append(["aim_%d_fire" % k, {"aim": k, "fire": true}])
	bld2(out, "cn_popup", 1, 24, func(cv, o, f, opt): popup(cv, o, f, opt), px, {"anim_strip": ["lowered", "rising", "aim_0", "aim_1", "aim_1_fire", "aim_2"]})
	C.unit_sheet(out, "g7_cn_sentry", "vehicles", "vehicle", 40, 40, Vector2i(20, 27), SENTRY_FRAMES,
		func(cv, k, f, o): sentry(cv, k, f, o), {"art": "ART7B", "size_m": [1.9, 1.6, 1.3], "kit": "cn"})
	C.unit_sheet(out, "g7_cn_barrier", "vehicles", "vehicle", 56, 48, Vector2i(28, 32), BARRIER_FRAMES,
		func(cv, k, f, o): barrier(cv, k, f, o), {"art": "ART7B", "size_m": [0.9, 3.3, 1.6], "kit": "cn"})


func _init() -> void:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": "g7_rollout",
		"g7_detail_level": C.DL.duplicate(true)}}
	build(out)
	var dir := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	for sub in ["units", "buildings", "icons"]:
		var d := DirAccess.open(dir.path_join(sub))
		if d != null:
			for fn in d.get_files():
				if fn.ends_with(".png"):
					d.remove(fn)
	var files := int(GEN.save(out, OUT))
	var over := 0
	for sec in ["vehicles", "buildings"]:
		var man: Dictionary = out.manifest.get(sec, {})
		var ids: Array = man.keys()
		ids.sort()
		for id in ids:
			var g7: Dictionary = man[id].g7
			var ok := int(g7.bytes) <= int(g7.budget)
			over += 0 if ok else 1
			print("G7_ART %s bytes=%d budget=%d %s" % [id, int(g7.bytes), int(g7.budget), "ok" if ok else "OVER"])
	print("G7_ART group=g7_rollout files=%d over=%d" % [files, over])
	quit(0)
