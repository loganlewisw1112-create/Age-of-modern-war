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

const G7Anim = preload("res://tools/art/g7_anim.gd")
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
	M.render_z(cv, S, o, seed)   # ART7C: per-pixel depth (fact art.mesh_render_z)


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
	var tops: Array = []
	var tilt := (1.0 - dep) * 1.45
	var Tc := M.sub(T, Vector3(0.15, 0, 0.22), 0.0, -tilt)
	M.box(pt, Tc, Vector3(0, 0, 0.7), Vector3(0.1, 0.6, 0.7), hull, Vector3.ZERO)
	for s3 in [-0.55, 0.0, 0.55]:   # ART7C: rear A-frame struts (read even when the screen is edge-on)
		var a3 := Vector3(-0.1, s3, 1.2)
		var b3 := Vector3(-0.75, s3, 0.0)
		M.cyl(pt, Tc, (a3 + b3) * 0.5, b3 - a3, 0.035, (b3 - a3).length() * 0.5, 4, dk, {"edge": false})
	M.dline(pt, Tc, Vector3(0.105, -0.58, 1.38), Vector3(0.105, 0.58, 1.38), C.ca(hull[4], 0.8), Vector3(1, 0, 0))
	M.dline(pt, Tc, Vector3(0.105, -0.58, 0.04), Vector3(0.105, 0.58, 0.04), C.ca(hull[0], 0.9), Vector3(1, 0, 0))
	M.dpx(pt, Tc, Vector3(0.11, 0.4, 1.1), AMBER, Vector3(1, 0, 0))
	TU.team_patch(pt, Tc, Vector3(0.065, 0, 1.25), Vector3(0.005, 0.3, 0.06), hull)
	M.dline(pt, Tc, Vector3(0.07, -0.25, 0.85), Vector3(0.07, 0.25, 0.85), Color8(24, 26, 26), Vector3(1, 0, 0))
	for s in [-1.0, 1.0]:
		var Tw := M.sub(Tc, Vector3(0, s * 0.6, 0), -s * ((1.0 - dep) * 2.6 + 0.5 * dep))   # ART7C: wings fold 29 deg forward (chevron): never a flat edge-on line
		var pw := M.part(S, 0)
		M.box(pw, Tw, Vector3(0, s * 0.5, 0.65), Vector3(0.09, 0.5, 0.65), hull)
		M.dline(pw, Tw, Vector3(0.095, s * 0.05, 0.05), Vector3(0.095, s * 0.05, 1.25), C.ca(hull[0], 0.9), Vector3(1, 0, 0))
		M.cyl(pw, Tw, Vector3(-0.35, s * 0.5, 0.55), Vector3(-0.6, 0, -1.0), 0.03, 0.6, 4, dk, {"edge": false})
		M.cyl(pw, Tw, Vector3(0.0, s * 1.02, 0.75), Vector3(0, 0, 1), 0.07, 0.78, 6, dk)   # emitter pylon
		tops.append(M.wm(Tw, Vector3(0.0, s * 1.02, 1.5)))
		M.dpx(pw, Tw, Vector3(0.0, s * 1.02, 1.56), CN_HOT if fname == "fire" else CN_BLUE)
	if dep >= 1.0:   # the counter-nanite field line between the pylons
		var a: Vector3 = tops[0]
		var b: Vector3 = tops[1]
		var fire := fname == "fire"
		var o2 := o
		M.sprite(S, (a + b) * 0.5 + Vector3(0.3, 0, 0), func(c2):
			var pa := M.scr_w(o2, a)
			var pb := M.scr_w(o2, b)
			for i in (5 if fire else 2):
				c2.line_v(pa + Vector2(0, i * 3), pb + Vector2(0, i * 3), Color(CN_BLUE, 0.55 if fire else 0.3))
			c2.line_v(pa, pb, Color(CN_HOT, 0.8 if fire else 0.45)), 4.0)
	_fin(cv, S, o, 83 + k)


# ------------------------------------------------------------------ facility detail helpers (ART7C)
const HESCO := Color8(150, 140, 112)
const SIGN := Color8(38, 42, 44)
const STENCIL := Color8(226, 226, 214)
const POOL := Color(1.0, 0.95, 0.78, 0.12)


## Flat quad decal centred at local c with half-vectors u, v on the surface with normal nl.
static func quad(pt: Dictionary, T: Dictionary, c: Vector3, u: Vector3, v: Vector3, col: Color, nl: Vector3) -> void:
	M.dpoly(pt, T, [c - u - v, c + u - v, c + u + v, c - u + v], col, nl)


## Unit vector along a wall with normal nl (x-wall runs along y, y-wall along x).
static func _along(nl: Vector3) -> Vector3:
	return Vector3(0, 1, 0) if absf(nl.x) > 0.5 else Vector3(1, 0, 0)


## Window on a wall: dark reveal, glass (lit warm or cold), sill highlight, frame mullion. p = point on the wall.
static func window(pt: Dictionary, T: Dictionary, p: Vector3, w: float, h: float, nl: Vector3, lit: bool, shut := false) -> void:
	var a := _along(nl)
	var c := p + nl * 0.012
	var up := Vector3(0, 0, 1)
	quad(pt, T, c, a * (w * 0.5 + 0.08), up * (h * 0.5 + 0.08), Color8(30, 33, 36), nl)
	if shut:   # armoured shutter, slatted
		quad(pt, T, c + nl * 0.004, a * w * 0.5, up * h * 0.5, Color8(86, 92, 96), nl)
		for i in 3:
			M.dline(pt, T, c + nl * 0.008 + up * (h * (i - 1) * 0.3) - a * w * 0.5, c + nl * 0.008 + up * (h * (i - 1) * 0.3) + a * w * 0.5, Color8(58, 62, 66), nl)
	else:
		quad(pt, T, c + nl * 0.004, a * w * 0.5, up * h * 0.5, LAMP_W if lit else GLASS, nl)
		M.dline(pt, T, c + nl * 0.008 + up * h * 0.45 - a * w * 0.45, c + nl * 0.008 + up * h * 0.45 + a * w * 0.1, Color(1, 1, 1, 0.55), nl)
		M.dline(pt, T, c + nl * 0.008 - up * h * 0.5, c + nl * 0.008 + up * h * 0.5, Color8(30, 33, 36), nl)
	M.dline(pt, T, c - up * (h * 0.5 + 0.1) - a * (w * 0.5 + 0.1), c - up * (h * 0.5 + 0.1) + a * (w * 0.5 + 0.1), C.ca(Color8(200, 198, 190), 0.8), nl)


## Wall floodlight: bracket + lamp + a soft light pool on the ground in front of the wall.
static func flood(pt: Dictionary, pg: Dictionary, T: Dictionary, p: Vector3, nl: Vector3) -> void:
	M.box(pt, T, p + nl * 0.15, Vector3(0.15, 0.15, 0.1), C.ramp(STEEL))
	M.dpx(pt, T, p + nl * 0.31 + Vector3(0, 0, -0.05), LAMP_W, nl)
	var g := Vector3(p.x, p.y, 0.2) + nl * 2.2
	var a := _along(nl)
	M.dpoly(pg, T, [g - a * 1.6 - nl * 1.4, g + a * 1.6 - nl * 1.4, g + a * 1.1 + nl * 1.2, g - a * 1.1 + nl * 1.2], POOL, Vector3(0, 0, 1))


## Row of HESCO bastion cubes (wire-mesh sand walls) from a along d, n cubes of 1.05 m, height hz.
static func hesco(S: Array, T: Dictionary, a: Vector3, d: Vector3, n: int, hz := 1.1, seed := 3) -> void:
	var rp: Array = C.ramp(HESCO)
	for i in n:
		var pt := M.part(S, 0)
		var c := a + d * (1.05 * i + 0.52) + Vector3(0, 0, hz * 0.5)
		var sk := 0.96 + 0.06 * P.hn(i, seed, 9)
		M.box(pt, T, c, Vector3(0.52, 0.52, hz * 0.5 * sk), rp, Vector3(0.03, 0.03, 0.03))
		for nl in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, -1, 0)]:
			var al := _along(nl)
			var fc: Vector3 = c + nl * 0.525
			for j in 3:   # wire mesh grid
				M.dline(pt, T, fc + al * (-0.35 + j * 0.35) - Vector3(0, 0, hz * 0.45), fc + al * (-0.35 + j * 0.35) + Vector3(0, 0, hz * 0.45), C.ca(rp[1], 0.75), nl)
			M.dline(pt, T, fc - al * 0.5 + Vector3(0, 0, hz * 0.05), fc + al * 0.5 + Vector3(0, 0, hz * 0.05), C.ca(rp[1], 0.6), nl)
		M.dpx(pt, T, c + Vector3(0.1, 0.2, hz * 0.5 * sk + 0.01), C.ramp(Color8(150, 128, 92))[2], Vector3(0, 0, 1))


## Concertina wire along a -> b at height z (loops of dark + bright pixels).
static func wire(pt: Dictionary, T: Dictionary, a: Vector3, b: Vector3, z: float) -> void:
	var n := int(a.distance_to(b) / 0.22)
	for i in n:
		var p := a.lerp(b, float(i) / float(maxi(1, n - 1)))
		var q := p + Vector3(0, 0, z + 0.18 * sin(i * 1.9))
		M.dpx(pt, T, q, Color8(150, 156, 160) if i % 2 == 0 else Color8(60, 64, 66))


# ------------------------------------------------------------------ CN facility (4x4 tiles = 16 m)
## ART7C rework (owner bar: the rev4 APC / VTOL look). A hardened two-storey command / package-lab block with a
## dark plinth, precast panel joints, strip windows (lit / shuttered), a signage band with the CN stripe and unit
## stencil, wall floodlights with light pools, conduits and grime; a vehicle bay annex with a framed roll-up blast
## door, hazard jambs, bollards and a beacon; the airport-style decontamination walkway (canopy on posts, scan arches,
## blue spray heads, walkway lines) fed from the CN agent tanks in a bunded saddle frame; roof parapet, HVAC with fan
## grilles, hatch, satellite dish, lattice comms mast with an aviation light, roof ID panel; HESCO bastions and
## jersey barriers at the apron. b = Human B: sand-washed concrete, rust tanks, sandbagged entry.
static func facility(cv, o: Vector2, f: int, opt: Dictionary, b: bool) -> void:
	var S: Array = []
	var T := M.pose(o, float(f) * PI / 2.0)
	var base_c := B_CONC if b else CONC
	var conc: Array = C.ramp(base_c)
	var cd: Array = C.ramp(P.mul(B_CONC, 0.82) if b else CONC_D)
	var plinth: Array = C.ramp(P.mul(base_c, 0.7))
	var st: Array = C.ramp(STEEL)
	var dk: Array = C.ramp(DARK)
	var X := Vector3(1, 0, 0)
	var Y := Vector3(0, 1, 0)
	var Z := Vector3(0, 0, 1)
	# --- apron: slab, expansion joints, lane paint, drain grates, oil stains
	var pa := M.part(S, -2)
	M.box(pa, T, Vector3(0, 0, 0.08), Vector3(7.8, 7.8, 0.08), cd, Vector3(0.05, 0.05, 0.05))
	for i in range(1, 4):
		M.dline(pa, T, Vector3(-7.7 + i * 3.9, -7.7, 0.165), Vector3(-7.7 + i * 3.9, 7.7, 0.165), C.ca(cd[0], 0.55), Z)
		M.dline(pa, T, Vector3(-7.7, -7.7 + i * 3.9, 0.165), Vector3(7.7, -7.7 + i * 3.9, 0.165), C.ca(cd[0], 0.55), Z)
	for s in [-1.0, 1.0]:   # vehicle lane to the bay door
		M.dline(pa, T, Vector3(6.9, -3.9 + s * 2.2, 0.17), Vector3(7.7, -3.9 + s * 2.2, 0.17), AMBER, Z)
	for i in 5:   # stop bar chevrons
		M.dline(pa, T, Vector3(7.2, -5.6 + i * 0.8, 0.17), Vector3(7.5, -5.3 + i * 0.8, 0.17), GR.HAZ if i % 2 == 0 else GR.HAZ_D, Z)
	quad(pa, T, Vector3(7.3, -0.4, 0.17), Y * 0.5, X * 0.12, Color8(40, 42, 42), Z)   # drain grate
	for j in 5:
		var u := P.hn(j, f, 61)
		M.dpoly(pa, T, [Vector3(4.0 + u * 3.0, -6.0 + j * 0.8, 0.168), Vector3(4.6 + u * 3.0, -5.8 + j * 0.8, 0.168),
			Vector3(4.4 + u * 3.0, -5.4 + j * 0.8, 0.168)], Color(0.1, 0.1, 0.09, 0.22), Z)
	# --- main block (x -7.4..2.6, y -6.8..4.4, 6.6 m): plinth, panels, floor band, windows, signage
	var pm := M.part(S, 0)
	M.box(pm, T, Vector3(-2.4, -1.2, 3.3), Vector3(5.0, 5.6, 3.3), conc, Vector3(0.2, 0.2, 0.2))
	var faces := [[Vector3(2.6, -1.2, 0), Y, 11.2, X], [Vector3(-2.4, 4.4, 0), X, 10.0, Y],
		[Vector3(-7.4, -1.2, 0), Y, 11.2, -X], [Vector3(-2.4, -6.8, 0), X, 10.0, -Y]]   # all 4: half rotations show every side
	for fc in faces:
		var c0: Vector3 = fc[0]
		var al: Vector3 = fc[1]
		var ln: float = fc[2]
		var nl: Vector3 = fc[3]
		var c1 := c0 + nl * 0.012
		quad(pm, T, c1 + Z * 0.35, al * ln * 0.5, Z * 0.35, plinth[1], nl)   # dark plinth
		M.dline(pm, T, c1 + Z * 0.7 - al * ln * 0.5, c1 + Z * 0.7 + al * ln * 0.5, C.ca(plinth[3], 0.8), nl)
		for zz in [3.3, 6.2]:   # floor band + parapet coping joint
			M.dline(pm, T, c1 + Z * zz - al * ln * 0.5, c1 + Z * zz + al * ln * 0.5, C.ca(cd[1], 0.95), nl)
			M.dline(pm, T, c1 + Z * (zz + 0.1) - al * ln * 0.5, c1 + Z * (zz + 0.1) + al * ln * 0.5, C.ca(conc[4], 0.4), nl)
		var np := int(ln / 2.0)
		for i in range(1, np):   # precast panel joints
			var r := -ln * 0.5 + ln * float(i) / np
			M.dline(pm, T, c1 + al * r + Z * 0.75, c1 + al * r + Z * 6.5, C.ca(conc[1], 0.8), nl)
		for i in np:   # upper strip windows (some shuttered), lower windows (warm lit / dark)
			var r := -ln * 0.5 + ln * (float(i) + 0.5) / np
			window(pm, T, c0 + al * r + Z * 4.85, 1.1, 0.75, nl, false, (i + f) % 4 == 3)
			if i % 2 == 0:
				window(pm, T, c0 + al * r + Z * 1.95, 0.9, 0.7, nl, (i / 2 + f) % 2 == 0)
		for j in 90:   # weathering: rain streaks under the coping, chips, grime toward the ground
			var u := P.hn(j, f, 41) - 0.5
			var z := 0.8 + 5.4 * P.hn(j, 3, 43)
			if j % 3 == 0:
				M.dline(pm, T, c1 + al * u * ln + Z * 6.15, c1 + al * u * ln + Z * (6.15 - 0.6 - 1.2 * P.hn(j, 7, 3)), Color(0.22, 0.21, 0.18, 0.22), nl)
			else:
				var col := C.ca(conc[4], 0.5) if P.hn(j, 5, 47) < 0.3 else Color(0.2, 0.19, 0.16, 0.25 + 0.2 * (1.0 - z / 6.3))
				M.dpx(pm, T, c1 + al * u * ln + Z * z, col, nl)
	# signage band on the +y face: dark plate, CN stripe, unit stencil
	var sg := Vector3(-0.6, 4.415, 5.55)
	quad(pm, T, sg, X * 2.4, Z * 0.32, SIGN, Y)
	M.dline(pm, T, sg + Vector3(-2.3, 0.004, -0.2), sg + Vector3(2.3, 0.004, -0.2), CN_BLUE, Y)
	for i in 9:   # "CN-01" stencil blocks
		if i == 4:
			continue
		M.dline(pm, T, sg + Vector3(-1.9 + i * 0.42, 0.004, 0.18), sg + Vector3(-1.75 + i * 0.42, 0.004, 0.18), STENCIL, Y)
		M.dpx(pm, T, sg + Vector3(-1.9 + i * 0.42, 0.004, 0.02), STENCIL, Y)
	var sg2 := Vector3(-3.8, -6.815, 5.55)   # back signage band (seen in rot_1 / rot_3)
	quad(pm, T, sg2, X * 2.4, Z * 0.32, SIGN, -Y)
	M.dline(pm, T, sg2 + Vector3(-2.3, -0.004, -0.2), sg2 + Vector3(2.3, -0.004, -0.2), CN_BLUE, -Y)
	for i in 7:
		M.dline(pm, T, sg2 + Vector3(-1.5 + i * 0.42, -0.004, 0.18), sg2 + Vector3(-1.35 + i * 0.42, -0.004, 0.18), STENCIL, -Y)
	flood(pm, pa, T, Vector3(-7.4, -4.0, 5.9), -X)
	flood(pm, pa, T, Vector3(-6.0, -6.8, 5.9), -Y)
	quad(pm, T, Vector3(-7.415, 1.5, 1.05), Y * 0.55, Z * 1.05, st[1], -X)   # rear fire exit
	M.box(pm, T, Vector3(-7.75, 1.5, 2.4), Vector3(0.35, 0.8, 0.05), st)
	M.dpx(pm, T, Vector3(-7.42, 2.2, 2.3), LAMP_G, -X)
	for i in 6:   # hazard band over the personnel door
		M.dline(pm, T, Vector3(2.615, -0.5 + i * 0.25, 2.95), Vector3(2.615, -0.4 + i * 0.25, 2.75), GR.HAZ if i % 2 == 0 else GR.HAZ_D, X)
	# personnel entrance (+x face): steel door, canopy, steps, door light, keypad
	quad(pm, T, Vector3(2.615, 0.2, 1.05), Y * 0.55, Z * 1.05, st[1], X)
	M.dline(pm, T, Vector3(2.62, 0.2, 0.1), Vector3(2.62, 0.2, 2.1), Color8(30, 32, 34), X)
	M.dpx(pm, T, Vector3(2.62, 0.95, 1.2), GR.LED_G, X)
	var pd := M.part(S, 1)
	M.box(pd, T, Vector3(3.2, 0.2, 2.45), Vector3(0.6, 1.0, 0.06), st)   # canopy
	M.box(pd, T, Vector3(3.3, 0.2, 0.25), Vector3(0.7, 0.9, 0.1), conc)   # step
	M.dpx(pd, T, Vector3(3.6, 0.2, 2.36), LAMP_W)
	# conduits + junction boxes on the +y face
	for k in 2:
		var px := -6.6 + k * 4.5
		M.cyl(pm, T, Vector3(px, 4.48, 3.4), Z, 0.07, 3.1, 4, st, {"edge": false})
		M.box(pm, T, Vector3(px + 0.4, 4.55, 1.3), Vector3(0.3, 0.12, 0.4), st)
		M.dpx(pm, T, Vector3(px + 0.4, 4.68, 1.5), GR.HAZ, Y)
	flood(pm, pa, T, Vector3(2.6, 3.6, 5.9), X)
	flood(pm, pa, T, Vector3(1.6, 4.4, 5.9), Y)
	flood(pm, pa, T, Vector3(-6.4, 4.4, 5.9), Y)
	M.dpx(pm, T, Vector3(2.62, -6.6, 6.0), LAMP_G, X)
	M.dpx(pm, T, Vector3(2.62, 4.2, 6.0), LAMP_R, X)
	# --- roof: parapet rim, membrane seams, HVAC + fans, hatch, dish, ID panel, lattice comms mast
	var pr := M.part(S, 2)
	for e in [[Vector3(-2.4, -6.65, 6.85), Vector3(5.0, 0.12, 0.25)], [Vector3(-2.4, 4.25, 6.85), Vector3(5.0, 0.12, 0.25)],
			[Vector3(-7.25, -1.2, 6.85), Vector3(0.12, 5.4, 0.25)], [Vector3(2.45, -1.2, 6.85), Vector3(0.12, 5.4, 0.25)]]:
		M.box(pr, T, e[0], e[1], cd)
	var rf := M.part(S, 1)
	for i in range(1, 5):
		M.dline(rf, T, Vector3(-7.1 + i * 1.95, -6.5, 6.605), Vector3(-7.1 + i * 1.95, 4.1, 6.605), C.ca(cd[1], 0.7), Z)
	for j in 30:   # roof stains / ponding
		M.dpx(rf, T, Vector3(-7.0 + 9.4 * P.hn(j, f, 71), -6.4 + 10.6 * P.hn(j, f, 73), 6.605), Color(0.2, 0.2, 0.18, 0.25), Z)
	TU.team_patch(rf, T, Vector3(-4.4, 1.6, 6.62), Vector3(1.6, 1.6, 0.012), conc)   # roof ID panel
	for k in 2:   # HVAC units with fan grilles
		var hc := Vector3(-0.6, -5.0 + k * 2.6, 7.05)
		M.box(pr, T, hc, Vector3(1.1, 0.9, 0.45), st, Vector3(0.05, 0.05, 0.05))
		M.cyl(pr, T, hc + Vector3(-0.35, 0, 0.47), Z, 0.42, 0.03, 10, dk, {"cap_t": 0})
		M.cyl(pr, T, hc + Vector3(0.5, 0, 0.47), Z, 0.3, 0.03, 8, dk, {"cap_t": 0})
		for i in 3:
			M.dline(pr, T, hc + Vector3(1.11, -0.6 + i * 0.6, -0.3), hc + Vector3(1.11, -0.6 + i * 0.6, 0.3), C.ca(st[0], 0.9), X)
		M.cyl(pr, T, hc + Vector3(-1.4, 0.5, -0.2), X, 0.12, 0.35, 6, st, {"edge": false})   # duct
	M.box(pr, T, Vector3(-3.6, -4.8, 6.85), Vector3(0.5, 0.5, 0.25), st)   # roof hatch
	M.dline(pr, T, Vector3(-3.1, -5.2, 7.1), Vector3(-3.1, -4.4, 7.1), GR.HAZ, Z)
	M.cyl(pr, T, Vector3(0.9, 2.6, 7.15), Z, 0.06, 0.5, 4, dk, {"edge": false})   # satellite dish
	M.cyl(pr, T, Vector3(1.1, 2.75, 7.75), Vector3(-0.8, -0.5, 0.75), 0.5, 0.05, 10, C.ramp(Color8(150, 154, 152)), {"cap_t": 2})   # dish faces back-up (sky), reads as an ellipse, not a ball
	M.dline(pr, T, Vector3(1.1, 2.75, 7.8), Vector3(0.75, 2.53, 8.15), dk[1])   # feed arm
	M.dpx(pr, T, Vector3(0.75, 2.53, 8.15), dk[0])
	var mp := Vector3(-6.4, -5.8, 6.6)   # lattice comms mast (3 legs, cross bracing), aviation light, whips
	for i in 3:
		var a := TAU * i / 3.0
		var lb := mp + Vector3(cos(a) * 0.45, sin(a) * 0.45, 0)
		var lt := mp + Vector3(cos(a) * 0.12, sin(a) * 0.12, 5.2)
		M.cyl(pr, T, (lb + lt) * 0.5, lt - lb, 0.04, (lt - lb).length() * 0.5, 4, dk, {"edge": false})
	for k in 6:
		var z0 := 0.4 + k * 0.8
		var r0 := 0.45 - 0.33 * z0 / 5.2
		M.dline(pr, T, mp + Vector3(r0, 0, z0), mp + Vector3(-r0 * 0.5, r0 * 0.87, z0 + 0.4), C.ca(dk[2], 1.0))
		M.dline(pr, T, mp + Vector3(r0, 0, z0), mp + Vector3(-r0 * 0.5, -r0 * 0.87, z0 + 0.4), C.ca(dk[1], 1.0))
	M.cyl(pr, T, mp + Vector3(0.0, 0.0, 6.0), Z, 0.025, 0.8, 4, dk, {"edge": false})
	M.box(pr, T, mp + Vector3(0.25, 0.0, 4.3), Vector3(0.06, 0.3, 0.4), C.ramp(Color8(210, 210, 204)))   # panel antenna
	M.dpx(pr, T, mp + Vector3(0, 0, 6.85), LAMP_R)
	M.dpx(pr, T, mp + Vector3(0, 0, 3.5), LAMP_R)
	# --- vehicle bay annex (+x side): framed roll-up blast door, hazard jambs, beacon, bollards
	var pb := M.part(S, 1)
	M.box(pb, T, Vector3(4.7, -3.9, 2.4), Vector3(2.1, 2.9, 2.4), conc, Vector3(0.12, 0.0, 0.12))
	quad(pb, T, Vector3(6.812, -3.9, 0.35), Y * 2.9, Z * 0.35, plinth[1], X)
	quad(pb, T, Vector3(4.7, -0.988, 0.35), X * 2.1, Z * 0.35, plinth[1], Y)
	M.box(pb, T, Vector3(6.86, -3.9, 1.75), Vector3(0.06, 2.05, 1.75), st)   # door
	for i in 9:
		M.dline(pb, T, Vector3(6.93, -5.85, 0.25 + i * 0.38), Vector3(6.93, -1.95, 0.25 + i * 0.38), C.ca(st[1], 0.95), X)
		M.dline(pb, T, Vector3(6.93, -5.85, 0.33 + i * 0.38), Vector3(6.93, -1.95, 0.33 + i * 0.38), C.ca(st[3], 0.5), X)
	for s in [-1.0, 1.0]:   # jambs with hazard chevrons
		var jy: float = -3.9 + s * 2.25
		M.box(pb, T, Vector3(6.88, jy, 1.8), Vector3(0.1, 0.18, 1.8), cd)
		for i in 6:
			M.dline(pb, T, Vector3(6.985, jy - 0.15, 0.3 + i * 0.55), Vector3(6.985, jy + 0.15, 0.55 + i * 0.55), GR.HAZ if i % 2 == 0 else GR.HAZ_D, X)
	M.box(pb, T, Vector3(6.9, -3.9, 3.75), Vector3(0.12, 2.4, 0.18), cd)   # lintel
	quad(pb, T, Vector3(6.815, -3.9, 4.3), Y * 1.3, Z * 0.22, SIGN, X)
	M.dline(pb, T, Vector3(6.83, -5.0, 4.3), Vector3(6.83, -2.8, 4.3), CN_BLUE, X)
	M.dpx(pb, T, Vector3(6.95, -6.0, 4.0), AMBER, X)
	M.dpx(pb, T, Vector3(6.95, -1.8, 4.0), AMBER, X)
	flood(pb, pa, T, Vector3(6.8, -3.9, 4.65), X)
	TU.team_patch(pb, T, Vector3(4.5, -3.9, 4.82), Vector3(1.0, 1.4, 0.012), conc)
	for i in 3:   # annex side (-y): panel joints, louvre vents, side door
		M.dline(pb, T, Vector3(3.3 + i * 1.4, -6.812, 0.7), Vector3(3.3 + i * 1.4, -6.812, 4.6), C.ca(conc[1], 0.8), -Y)
	quad(pb, T, Vector3(4.7, -6.812, 0.35), X * 2.1, Z * 0.35, plinth[1], -Y)
	quad(pb, T, Vector3(3.6, -6.815, 3.6), X * 0.45, Z * 0.35, Color8(52, 56, 60), -Y)
	for k in 4:
		M.dline(pb, T, Vector3(3.2, -6.82, 3.35 + k * 0.17), Vector3(4.0, -6.82, 3.35 + k * 0.17), Color8(90, 96, 100), -Y)
	quad(pb, T, Vector3(5.8, -6.815, 1.05), X * 0.5, Z * 1.05, st[1], -Y)
	M.dpx(pb, T, Vector3(5.8, -6.82, 2.3), LAMP_W, -Y)
	for i in 2:   # roof vents on the bay
		M.cyl(pb, T, Vector3(3.6 + i * 1.6, -5.8, 5.0), Z, 0.22, 0.2, 6, st, {"cap_t": 1})
	for s in [-1.0, 1.0]:   # bollards
		var pbo := M.part(S, 1)
		M.cyl(pbo, T, Vector3(7.5, -3.9 + s * 2.6, 0.55), Z, 0.14, 0.45, 6, C.ramp(GR.HAZ), {"cap_t": 3})
		M.dline(pbo, T, Vector3(7.64, -3.9 + s * 2.6, 0.5), Vector3(7.64, -3.9 + s * 2.6, 0.7), Color8(30, 30, 28), X)
	# --- decontamination walkway along +y: canopy on posts, scan arches, spray heads, walkway lines
	var pw := M.part(S, -1)
	quad(pw, T, Vector3(-2.2, 5.9, 0.17), X * 4.4, Y * 1.0, Color8(84, 90, 92), Z)
	for s in [-1.0, 1.0]:
		M.dline(pw, T, Vector3(-6.4, 5.9 + s * 0.9, 0.172), Vector3(2.0, 5.9 + s * 0.9, 0.172), GR.HAZ, Z)
	for i in 4:   # foot-wash grates
		quad(pw, T, Vector3(-5.6 + i * 2.6, 5.9, 0.173), X * 0.35, Y * 0.7, Color8(46, 70, 84), Z)
	for i in 4:   # scan arches (frame + blue spray heads)
		var ax := -5.0 + i * 2.6
		var pq := M.part(S, 0)
		for s in [-1.0, 1.0]:
			M.box(pq, T, Vector3(ax, 5.9 + s * 0.95, 1.2), Vector3(0.1, 0.08, 1.1), st)
			for z in [0.6, 1.2, 1.8]:
				M.dpx(pq, T, Vector3(ax, 5.9 + s * 0.85, z), CN_BLUE)
		M.box(pq, T, Vector3(ax, 5.9, 2.35), Vector3(0.12, 1.05, 0.12), st)
		M.dpx(pq, T, Vector3(ax + 0.13, 5.9, 2.35), GR.LED_G if (i + f) % 3 != 0 else LAMP_R, X)
	var pcn := M.part(S, 1)   # canopy roof on posts
	M.box(pcn, T, Vector3(-2.2, 5.95, 2.75), Vector3(4.6, 1.25, 0.08), C.ramp(Color8(120, 128, 130)), Vector3(0, 0, 0))
	for i in 5:
		M.dline(pcn, T, Vector3(-6.6 + i * 2.2, 4.75, 2.84), Vector3(-6.6 + i * 2.2, 7.15, 2.84), C.ca(STEEL, 0.9), Z)
	M.dline(pcn, T, Vector3(-6.7, 7.21, 2.72), Vector3(2.3, 7.21, 2.72), CN_BLUE, Y)
	for i in 3:
		var pp := M.part(S, 0)
		M.cyl(pp, T, Vector3(-6.4 + i * 4.2, 7.05, 1.35), Z, 0.08, 1.35, 4, st, {"edge": false})
	# --- CN agent tanks in a bunded saddle frame, ladder, feed pipe to the walkway
	var pbund := M.part(S, -1)
	M.box(pbund, T, Vector3(5.4, 4.0, 0.3), Vector3(2.0, 2.9, 0.18), cd)
	for i in 2:
		var pt := M.part(S, 1)
		var tk: Array = C.ramp(B_RUST if b else Color8(196, 200, 196))
		var tc := Vector3(4.6 + i * 1.9, 3.2 + i * 1.4, 2.2)
		M.cyl(pt, T, tc, Z, 0.85, 1.8, 12, tk, {"cap_t": 3})
		M.cyl(pt, T, tc + Z * 1.85, Z, 0.55, 0.08, 10, tk, {"cap_t": 4}, 0.0, 0.3)   # domed head
		for zz in [0.7, 2.9]:   # saddle bands
			M.cyl(pt, T, Vector3(tc.x, tc.y, zz), Z, 0.88, 0.05, 12, st, {"caps": false})
		M.dline(pt, T, tc + Vector3(0.6, 0.6, -0.4), tc + Vector3(0.6, 0.6, 0.6), CN_BLUE, Vector3(0.7, 0.7, 0))
		M.dpx(pt, T, tc + Vector3(0.62, 0.62, 0.9), STENCIL, Vector3(0.7, 0.7, 0))
		for k in 7:   # ladder
			M.dline(pt, T, tc + Vector3(0.88, -0.2, -1.6 + k * 0.5), tc + Vector3(0.88, 0.2, -1.6 + k * 0.5), C.ca(st[0], 1.0), X)
	var pfp := M.part(S, 1)
	M.cyl(pfp, T, Vector3(3.4, 5.6, 0.55), X, 0.1, 1.0, 6, st, {"edge": false})
	M.cyl(pfp, T, Vector3(2.4, 5.6, 1.6), Z, 0.1, 1.1, 6, st, {"edge": false})
	M.cyl(pfp, T, Vector3(0.2, 5.6, 2.62), X, 0.09, 2.2, 6, st, {"edge": false})
	# --- perimeter: HESCO at the front corners, jersey barriers, Human B sandbagged entry
	hesco(S, T, Vector3(7.25, 0.4, 0.15), Y, 3, 1.0, 5 + f)
	hesco(S, T, Vector3(-7.4, 7.3, 0.15), X, 3, 1.0, 7 + f)
	for i in 2:
		var pj := M.part(S, 0)
		M.box(pj, T, Vector3(1.0 + i * 2.0, 7.4, 0.45), Vector3(0.9, 0.3, 0.45), conc, Vector3(0.0, 0.0, 0.18))
		M.dline(pj, T, Vector3(0.3 + i * 2.0, 7.71, 0.35), Vector3(1.7 + i * 2.0, 7.71, 0.35), GR.HAZ, Y)
	if b:   # sandbagged entry for Human B
		TU.sandbags(S, M.sub(T, Vector3(3.7, 0.2, 0.0)), 1.1, 2, 1.2, 5)
	_fin(cv, S, o, 91 + f)


# ------------------------------------------------------------------ hardened tower (2x2 tiles, ~13 m)
## ART7C rework (6.2 "hardened tower with a remote weapon station, a counter-drone emitter, and interceptors"):
## blast-door bunker base with HESCO, panelled concrete shaft with a caged ladder and an external steel stair,
## overhanging armoured cab with a framed window band and catwalk; on the roof a remote weapon station (fires),
## a counter-drone emitter mast, an interceptor launcher pod, searchlight, whip antenna, ID panel.
static func tower(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	var S: Array = []
	var T := M.pose(o, float(f) * PI / 2.0)
	var conc: Array = C.ramp(CONC)
	var cd: Array = C.ramp(CONC_D)
	var st: Array = C.ramp(STEEL)
	var dk: Array = C.ramp(DARK)
	var X := Vector3(1, 0, 0)
	var Y := Vector3(0, 1, 0)
	var Z := Vector3(0, 0, 1)
	var pg := M.part(S, -1)
	M.box(pg, T, Vector3(0, 0, 0.1), Vector3(3.6, 3.6, 0.1), cd, Vector3(0.05, 0.05, 0.05))
	for i in 4:
		M.dline(pg, T, Vector3(3.3, -2.6 + i * 1.6, 0.21), Vector3(3.55, -2.4 + i * 1.6, 0.21), GR.HAZ, Z)
	var pb := M.part(S, 0)   # bunker base with blast door
	M.box(pb, T, Vector3(0, 0, 1.35), Vector3(1.8, 1.8, 1.15), conc, Vector3(0.15, 0.15, 0.15))
	for nl in [X, Y]:
		var al := _along(nl)
		var c1: Vector3 = nl * 1.812 + Z * 0.0
		quad(pb, T, c1 + Z * 0.5, al * 1.8, Z * 0.3, C.ramp(P.mul(CONC, 0.7))[1], nl)
		M.dline(pb, T, c1 + Z * 1.9 - al * 1.6, c1 + Z * 1.9 + al * 1.6, Color8(26, 28, 30), nl)   # firing slit
		for j in 20:
			M.dpx(pb, T, c1 + al * (P.hn(j, f, 3) * 3.4 - 1.7) + Z * (0.6 + 1.7 * P.hn(j, 2, 5)), Color(0.2, 0.19, 0.16, 0.3), nl)
	quad(pb, T, Vector3(0.4, 1.815, 1.0), X * 0.5, Z * 0.8, st[1], Y)   # blast door
	for i in 4:
		M.dline(pb, T, Vector3(-0.1 + i * 0.33, 1.82, 0.3), Vector3(0.1 + i * 0.33, 1.82, 1.7), GR.HAZ if i % 2 == 0 else GR.HAZ_D, Y)
	M.dpx(pb, T, Vector3(0.4, 1.83, 1.95), LAMP_W, Y)
	hesco(S, T, Vector3(2.4, -3.3, 0.2), Y, 3, 1.0, 11 + f)
	var ps := M.part(S, 0)   # shaft (z 2.5..8.6)
	M.box(ps, T, Vector3(-0.2, -0.2, 5.55), Vector3(1.0, 1.0, 3.05), conc)
	for nl in [X, Y]:
		var al := _along(nl)
		var c1: Vector3 = Vector3(-0.2, -0.2, 0) + nl * 1.012
		for i in 4:
			M.dline(ps, T, c1 + Z * (3.2 + i * 1.4) - al * 1.0, c1 + Z * (3.2 + i * 1.4) + al * 1.0, C.ca(conc[1], 0.9), nl)
		M.dline(ps, T, c1 + Z * 2.6, c1 + Z * 8.5, C.ca(conc[1], 0.7), nl)
		for j in 3:   # rain streaks
			var u := P.hn(j, f, 13) * 1.8 - 0.9
			M.dline(ps, T, c1 + al * u + Z * 8.5, c1 + al * u + Z * (7.0 - P.hn(j, 1, 7) * 2.0), Color(0.22, 0.21, 0.18, 0.28), nl)
	for k in 12:   # caged ladder on +y
		M.dline(ps, T, Vector3(-0.6, 0.83, 2.6 + k * 0.5), Vector3(0.0, 0.83, 2.6 + k * 0.5), C.ca(st[0], 1.0), Y)
	var pl := M.part(S, 1)
	for s in [-0.65, 0.05]:
		M.cyl(pl, T, Vector3(s, 1.05, 5.55), Z, 0.025, 3.0, 4, st, {"edge": false})
	for k in 7:
		M.dline(pl, T, Vector3(-0.68, 1.12, 3.4 + k * 0.8), Vector3(0.08, 1.12, 3.4 + k * 0.8), C.ca(st[2], 1.0))
	var pst := M.part(S, 1)   # external stair flights on +x
	for k in 3:
		var z0 := 2.6 + k * 2.0
		var y0 := -1.0 if k % 2 == 0 else 0.6
		var y1 := 0.6 if k % 2 == 0 else -1.0
		M.dline(pst, T, Vector3(0.95, y0, z0), Vector3(0.95, y1, z0 + 2.0), st[0])
		M.dline(pst, T, Vector3(1.15, y0, z0 + 0.9), Vector3(1.15, y1, z0 + 2.9), st[3])
		M.box(pst, T, Vector3(1.0, y1, z0 + 2.0), Vector3(0.22, 0.3, 0.04), st)
	var pc := M.part(S, 2)   # cab z 8.6..10.4, catwalk, overhanging roof
	M.box(pc, T, Vector3(0, 0, 8.65), Vector3(1.95, 1.95, 0.07), st)   # catwalk deck
	for nl in [X, Y]:
		var al := _along(nl)
		M.dline(pc, T, nl * 1.95 + Z * 9.5 - al * 1.95, nl * 1.95 + Z * 9.5 + al * 1.95, st[3], nl)
		M.dline(pc, T, nl * 1.95 + Z * 9.1 - al * 1.95, nl * 1.95 + Z * 9.1 + al * 1.95, st[1], nl)
	M.box(pc, T, Vector3(0, 0, 9.55), Vector3(1.55, 1.55, 0.85), st, Vector3(0.0, 0.0, -0.12))
	for nl in [X, Y]:
		var al := _along(nl)
		var c1: Vector3 = nl * 1.56
		quad(pc, T, c1 + Z * 9.75, al * 1.45, Z * 0.36, Color8(30, 34, 38), nl)
		for i in 4:
			var u := -1.08 + i * 0.72
			quad(pc, T, c1 + nl * 0.004 + al * u + Z * 9.75, al * 0.3, Z * 0.3, GLASS if (i + f) % 3 != 0 else LAMP_W, nl)
			M.dline(pc, T, c1 + nl * 0.008 + al * (u - 0.25) + Z * 10.0, c1 + nl * 0.008 + al * (u + 0.05) + Z * 10.0, Color(1, 1, 1, 0.5), nl)
	M.box(pc, T, Vector3(0, 0, 10.5), Vector3(1.9, 1.9, 0.1), conc)   # roof slab
	TU.team_patch(pc, T, Vector3(-0.8, 0.7, 10.61), Vector3(0.55, 0.55, 0.012), conc)
	var pq := M.part(S, 3)   # roof kit
	var Tr := M.sub(T, Vector3(0.75, -0.55, 10.6), 0.0)   # remote weapon station
	M.cyl(pq, Tr, Vector3(0, 0, 0.12), Z, 0.32, 0.12, 8, dk, {"cap_t": 1})
	M.box(pq, Tr, Vector3(0.0, 0, 0.42), Vector3(0.35, 0.25, 0.18), C.ramp(SUIT), Vector3(0.15, 0.0, 0.06))
	M.box(pq, Tr, Vector3(0.05, -0.3, 0.55), Vector3(0.1, 0.07, 0.08), dk)
	M.dpx(pq, Tr, Vector3(0.16, -0.3, 0.56), GLASS, X)
	var mz := TU.barrel(pq, Tr, 0.3, 1.45, 0.0, 0.42, 0.04, 0.0, DARK, true)
	if bool(opt.get("fire", false)):
		TU.flash(S, Tr, mz)
	M.cyl(pq, T, Vector3(-1.0, -1.0, 11.4), Z, 0.06, 0.8, 4, dk, {"edge": false})   # counter-drone emitter mast
	for i in 3:
		var a := TAU * i / 3.0 + PI / 6.0
		M.box(pq, M.sub(T, Vector3(-1.0 + cos(a) * 0.2, -1.0 + sin(a) * 0.2, 12.0), a), Vector3.ZERO, Vector3(0.04, 0.22, 0.28), C.ramp(Color8(150, 156, 158)))
	M.dpx(pq, T, Vector3(-1.0, -1.0, 12.4), CN_BLUE)
	M.box(pq, T, Vector3(-0.9, 1.15, 10.95), Vector3(0.45, 0.4, 0.35), C.ramp(SUIT), Vector3(0.0, 0.0, 0.0))   # interceptor pod
	for i in 3:
		for j in 2:
			M.dpx(pq, T, Vector3(-0.44, 0.95 + i * 0.2, 10.85 + j * 0.22), Color8(24, 26, 28), X)
	M.cyl(pq, T, Vector3(1.55, 1.3, 10.85), Vector3(1, 0.4, -0.3), 0.18, 0.18, 8, st, {"cap_t": 4})   # searchlight
	M.dpx(pq, T, Vector3(1.75, 1.38, 10.8), LAMP_W)
	M.cyl(pq, T, Vector3(1.6, -1.6, 11.6), Z, 0.025, 1.0, 4, dk, {"edge": false})
	M.dpx(pq, T, Vector3(1.6, -1.6, 12.65), LAMP_R)
	_fin(cv, S, o, 93 + f)


# ------------------------------------------------------------------ armoured gate checkpoint (2x2 tiles)
## ART7C rework: asphalt lane with stop line, rumble strip and tyre-shredder plate; guard booth with a concrete
## dado, framed glass band, overhanging roof with downlights, door, AC unit and a STOP sign; HESCO on one side of
## the lane, jersey barriers on the other; boom barrier (opens); light pole with floodlight + camera.
static func checkpoint(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	var S: Array = []
	var T := M.pose(o, float(f) * PI / 2.0)
	var conc: Array = C.ramp(CONC)
	var st: Array = C.ramp(STEEL)
	var X := Vector3(1, 0, 0)
	var Y := Vector3(0, 1, 0)
	var Z := Vector3(0, 0, 1)
	var pg := M.part(S, -1)
	M.box(pg, T, Vector3(0, 0, 0.05), Vector3(3.9, 3.9, 0.05), C.ramp(Color8(84, 86, 86)))
	for i in 7:   # rumble strip / stop line
		M.dline(pg, T, Vector3(1.6, -3.0 + i, 0.11), Vector3(1.6, -2.6 + i, 0.11), Color8(230, 228, 220), Z)
	M.dline(pg, T, Vector3(2.4, -3.2, 0.11), Vector3(2.4, 3.2, 0.11), Color8(230, 228, 220), Z)
	quad(pg, T, Vector3(3.1, 0.0, 0.105), X * 0.25, Y * 3.0, Color8(40, 42, 44), Z)   # tyre shredder
	for i in 12:
		M.dpx(pg, T, Vector3(3.1, -2.8 + i * 0.5, 0.11), Color8(190, 190, 184), Z)
	for i in 3:   # lane arrows
		M.dline(pg, T, Vector3(-2.5 + i * 1.6, -1.0, 0.11), Vector3(-1.9 + i * 1.6, -1.0, 0.11), Color8(220, 218, 210), Z)
	for j in 6:
		M.dpoly(pg, T, [Vector3(-3.0 + j, -2.0 + P.hn(j, f, 5), 0.106), Vector3(-2.5 + j, -1.8 + P.hn(j, f, 5), 0.106), Vector3(-2.7 + j, -1.4 + P.hn(j, f, 5), 0.106)], Color(0.08, 0.08, 0.07, 0.25), Z)
	var pb := M.part(S, 0)   # guard booth
	M.box(pb, T, Vector3(-1.0, 2.6, 1.3), Vector3(1.1, 1.0, 1.3), C.ramp(Color8(176, 178, 172)), Vector3(0.0, 0.0, 0.0))
	for nl in [X, Y]:
		var al := _along(nl)
		var c1: Vector3 = Vector3(-1.0, 2.6, 0) + nl * (1.112 if nl.x > 0.0 else 1.012)
		var hw: float = 0.95 if nl.x > 0.0 else 1.05
		quad(pb, T, c1 + Z * 0.5, al * hw, Z * 0.5, C.ramp(CONC)[1], nl)   # dado
		quad(pb, T, c1 + Z * 1.65, al * hw, Z * 0.5, Color8(32, 36, 40), nl)
		for i in 3:
			var u := -hw * 0.66 + i * hw * 0.66
			quad(pb, T, c1 + nl * 0.004 + al * u + Z * 1.65, al * hw * 0.28, Z * 0.42, GLASS if i != 1 else LAMP_W, nl)
		M.dline(pb, T, c1 + nl * 0.008 + Z * 2.0 - al * hw * 0.8, c1 + nl * 0.008 + Z * 2.0 - al * hw * 0.4, Color(1, 1, 1, 0.5), nl)
	quad(pb, T, Vector3(-1.6, 3.612, 0.9), X * 0.3, Z * 0.85, st[1], Y)   # door
	M.box(pb, T, Vector3(-1.0, 2.6, 2.7), Vector3(1.45, 1.3, 0.1), st)   # roof overhang
	TU.team_patch(pb, T, Vector3(-1.0, 2.6, 2.81), Vector3(0.6, 0.5, 0.012), st)
	M.dpx(pb, T, Vector3(0.3, 2.6, 2.58), LAMP_W)
	M.dpx(pb, T, Vector3(-1.0, 3.8, 2.58), LAMP_W)
	M.box(pb, T, Vector3(-1.8, 1.45, 2.1), Vector3(0.3, 0.12, 0.22), st)   # AC unit
	M.cyl(pb, T, Vector3(-1.8, 1.32, 2.1), Y, 0.16, 0.01, 8, C.ramp(DARK), {"cap_t": 0})
	var psn := M.part(S, 1)   # STOP sign on a post
	M.cyl(psn, T, Vector3(1.9, 3.3, 1.0), Z, 0.04, 1.0, 4, st, {"edge": false})
	M.cyl(psn, T, Vector3(1.94, 3.3, 2.15), X, 0.38, 0.02, 8, C.ramp(Color8(196, 40, 34)), {"cap_t": 2}, PI / 8.0)
	M.dline(psn, T, Vector3(1.97, 3.1, 2.15), Vector3(1.97, 3.5, 2.15), STENCIL, X)
	hesco(S, T, Vector3(-3.6, -3.45, 0.1), X, 5, 1.1, 21 + f)   # lane side walls
	for i in 2:
		var pj := M.part(S, 0)
		M.box(pj, T, Vector3(0.6 + i * 1.9, 3.75, 0.45), Vector3(0.9, 0.3, 0.45), conc, Vector3(0.0, 0.0, 0.18))
		M.dline(pj, T, Vector3(-0.1 + i * 1.9, 4.06, 0.3), Vector3(1.3 + i * 1.9, 4.06, 0.3), GR.HAZ, Y)
	var open := bool(opt.get("open", false))
	var pa := M.part(S, 1)   # boom barrier
	M.box(pa, T, Vector3(0.6, 1.4, 0.55), Vector3(0.25, 0.25, 0.55), st)
	M.dpx(pa, T, Vector3(0.86, 1.4, 0.9), LAMP_G if open else LAMP_R, X)
	var Tb := M.sub(T, Vector3(0.6, 1.3, 1.0), -PI / 2.0, 0.0, -1.35 if open else 0.0)
	for i in 6:
		M.box(pa, Tb, Vector3(0, 0.15 + i * 0.75, 0), Vector3(0.06, 0.37, 0.06), C.ramp(Color8(212, 52, 44) if i % 2 == 0 else Color8(232, 230, 222)))
	M.dpx(pa, Tb, Vector3(0, 4.5, 0.1), LAMP_R)
	var pl := M.part(S, 2)   # light pole + floodlight + camera
	M.cyl(pl, T, Vector3(-3.0, 3.3, 2.6), Z, 0.07, 2.6, 4, C.ramp(DARK), {"edge": false})
	M.box(pl, T, Vector3(-2.6, 3.3, 5.2), Vector3(0.45, 0.12, 0.07), st)
	M.dpx(pl, T, Vector3(-2.3, 3.3, 5.1), LAMP_W)
	M.box(pl, T, Vector3(-2.85, 3.3, 4.4), Vector3(0.18, 0.08, 0.08), C.ramp(Color8(210, 210, 204)))
	M.dpx(pl, T, Vector3(-2.66, 3.3, 4.4), LAMP_R if not open else LAMP_G, X)
	M.dpoly(pg, T, [Vector3(-3.0, 1.3, 0.106), Vector3(-1.0, 2.0, 0.106), Vector3(-1.4, 0.0, 0.106), Vector3(-3.2, -0.6, 0.106)], POOL, Z)
	_fin(cv, S, o, 95 + f)


# ------------------------------------------------------------------ blast wall (2x2 tiles of T-walls)
## ART7C: T-walls with chamfered tops, lifting eyes, stencilled panel numbers, rebar chips and grime, concertina
## wire along the top, a warning plate and a lamp post at one end.
static func blast_wall(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	var S: Array = []
	var T := M.pose(o, float(f) * PI / 2.0)
	var conc: Array = C.ramp(CONC)
	var X := Vector3(1, 0, 0)
	for i in 5:
		var r := -3.04 + i * 1.52
		var pt := M.part(S, 0)
		var sk := 0.97 + 0.03 * P.hn(i, f, 7)
		M.box(pt, T, Vector3(0, r, 0.3), Vector3(0.65, 0.74, 0.3), conc, Vector3(0.0, 0.0, 0.0))   # foot
		M.box(pt, T, Vector3(0, r, 2.1 * sk), Vector3(0.17, 0.74, 1.5 * sk), conc, Vector3(0.0, 0.0, 0.05))
		M.dline(pt, T, Vector3(0.18, r - 0.74, 0.62), Vector3(0.18, r + 0.74, 0.62), C.ca(conc[1], 0.8), X)
		M.dpx(pt, T, Vector3(0.18, r, 3.3), C.ramp(CONC)[0], X)   # lifting eye
		M.dline(pt, T, Vector3(0.18, r - 0.5, 1.4), Vector3(0.18, r + 0.5, 1.4), C.ca(conc[1], 0.6), X)
		for k in 2:   # stencilled panel number
			M.dline(pt, T, Vector3(0.18, r - 0.2 + k * 0.3, 2.55), Vector3(0.18, r - 0.2 + k * 0.3, 2.85), Color(0.12, 0.12, 0.1, 0.8), X)
		if i == 2:
			TU.team_patch(pt, T, Vector3(0.18, r, 2.0), Vector3(0.005, 0.45, 0.25), conc)
			TU.team_patch(pt, T, Vector3(-0.18, r, 2.0), Vector3(0.005, 0.45, 0.25), conc)
		if i == 1:   # warning plate
			quad(pt, T, Vector3(0.18, r, 1.6), Vector3(0, 0.3, 0), Vector3(0, 0, 0.2), Color8(226, 184, 40), X)
			M.dline(pt, T, Vector3(0.185, r - 0.1, 1.6), Vector3(0.185, r + 0.1, 1.6), Color8(30, 30, 28), X)
		for j in 3:   # grime streaks
			var rr := r - 0.5 + P.hn(i, j, 3)
			M.dline(pt, T, Vector3(0.18, rr, 3.4), Vector3(0.18, rr, 2.5 - P.hn(j, i, 5)), Color(0.25, 0.24, 0.2, 0.35), X)
			M.dline(pt, T, Vector3(-0.18, rr, 3.4), Vector3(-0.18, rr, 2.5 - P.hn(j, i, 5)), Color(0.25, 0.24, 0.2, 0.35), Vector3(-1, 0, 0))
		for j in 2:   # chips with rebar
			var cz := 0.9 + 2.0 * P.hn(i, j, 11)
			var cr := r - 0.6 + 1.2 * P.hn(j, i, 13)
			M.dpx(pt, T, Vector3(0.18, cr, cz), C.ramp(CONC)[0], X)
			M.dpx(pt, T, Vector3(0.18, cr + 0.08, cz), Color8(120, 70, 44), X)
	var pw := M.part(S, 1)
	wire(pw, T, Vector3(0, -3.7, 0), Vector3(0, 3.7, 0), 3.55)
	var pl := M.part(S, 1)
	M.cyl(pl, T, Vector3(0.6, 3.75, 1.8), Vector3(0, 0, 1), 0.05, 1.8, 4, C.ramp(DARK), {"edge": false})
	M.box(pl, T, Vector3(0.85, 3.75, 3.6), Vector3(0.25, 0.08, 0.06), C.ramp(STEEL))
	M.dpx(pl, T, Vector3(1.05, 3.75, 3.52), LAMP_W)
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
	for s2 in [-1.0, 1.0]:   # ART7C: the two armoured hatch leaves stand open on their hinges, hazard edges
		var ph := M.part(S, 0)
		var Th := M.sub(T, Vector3(0, s2 * 0.78, 0.17), 0.0, 0.0, -s2 * (1.25 * up + 0.2))
		M.box(ph, Th, Vector3(0, -s2 * 0.36, 0.03), Vector3(0.72, 0.36, 0.03), C.ramp(Color8(122, 126, 122)))
		for i in 5:   # hazard chevrons on both faces of the leaf
			for zf in [0.065, -0.005]:
				M.dline(ph, Th, Vector3(-0.6 + i * 0.3, -s2 * 0.55, zf), Vector3(-0.5 + i * 0.3, -s2 * 0.7, zf), GR.HAZ if i % 2 == 0 else GR.HAZ_D)
	M.cyl(pr, T, Vector3(0, 0, 0.12), Vector3(0, 0, 1), 0.76, 0.01, 12, C.ramp(Color8(20, 22, 24)), {"cap_t": 0})   # shaft
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
	G7Anim.apply(out)   # ART7D: G6.1 vehicle frames (track phases, recoil, damaged) + anim61, re-measured bytes
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
