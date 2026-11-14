extends SceneTree
## G7.1 ARTFIX71: Human A FARP art (a_g71_farp, content/g71/defs_g71_air.json, AIRFIX71 A2: forward arming and
## refuelling point, 4x4, 2 rotorcraft pads, hot-pit refuel + rearm). Same part renderer, palette, scaffold, stake,
## damage and icon pipeline as the G5 Human A air buildings (g5_bld_lib.gd, g5_bld_air.gd, bdetail.gd,
## g4_fort_lib.gd icon): a gravel / PSP field site with two pierced-steel landing pads (touchdown circle + H + pad
## number each, edge lamps, team band), two fuel bladders in a sandbag berm with a pump skid, drums and hoses run to
## a nozzle stand at each pad, ammo / rocket pallets, an ops container and a ridge tent under camouflage netting on
## poles, a generator, a radio mast and a windsock. Writes its own group assets/art/g71_farp/ (manifest.json), so it
## never touches another generator's files. Deterministic: re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g71_farp.gd                 # writes assets/art/g71_farp/
##   godot --headless --path . -s tools/art/g71_farp.gd -- --out=<abs dir>
## States: built, damaged (under 50% hp), build_0..2 (PSP laid pad by pad, props rising under scaffold poles).
## entity_layer draws the FARP as a flat pad (_flat_pad: farp true), so every prop stays low (net top 17 px).
## Pads: world (x, y) offsets from the footprint centre in manifest g71.pads; Air._pin_ground parks one craft at
## the centre and two side by side at x -0.45 / +0.45, inside the shared PSP landing strip.
const GEN = preload("res://tools/gen_art.gd")
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")
const FL = preload("res://tools/art/g4_fort_lib.gd")
const DA = preload("res://tools/art/g5_bld_air.gd")
const GROUP := "g71_farp"
const DEF := "a_g71_farp"
const SIZE := 4
const TOP := 36
const SEED := 7140
const PADS := [Vector2(-0.64, 0.28), Vector2(0.72, 0.28)]
const MAT := [-1.3, -0.42, 1.42, 0.98]   # shared PSP landing strip u0, v0, u1, v1 (local = world, f 0)

const GRAVEL := Color8(128, 118, 92)
const PSP := Color8(104, 110, 98)
const PSP_D := Color8(78, 84, 74)
const RUBBER := Color8(50, 54, 46)
const SAND := Color8(150, 134, 98)
const OLIVE := Color8(98, 100, 72)
const OLIVE_C := Color8(90, 98, 70)
const CANVAS := Color8(112, 116, 78)
const AMMO := Color8(86, 96, 62)
const AMMO_D := Color8(74, 82, 56)
const WOOD := Color8(128, 104, 70)
const DRUM_G := Color8(84, 96, 62)
const DRUM_R := Color8(132, 62, 46)
const MARK := Color8(226, 220, 196)
const NET_A := Color8(84, 92, 58)
const NET_B := Color8(108, 96, 64)
const NET_C := Color8(62, 70, 46)
const POLE_C := Color8(70, 66, 56)
const LAMP_G := Color8(120, 236, 120)
const LAMP_A := Color8(246, 200, 80)
const HOSE := Color8(30, 30, 28)
const STENCIL := Color8(214, 190, 96)


func _init() -> void:
	var dir := "res://assets/art/%s/" % GROUP
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			dir = String(a).substr(6)
	var t0 := Time.get_ticks_msec()
	var out := build()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var n := GEN.save(out, dir)
	var e: Dictionary = out.manifest.buildings[DEF]
	print("G71_FARP %s states=%d pivot=%s files=%d ms=%d" % [DEF, (e.states as Dictionary).size(), str(e.pivot), n, Time.get_ticks_msec() - t0])
	quit()


static func build() -> Dictionary:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": GROUP, "buildings": {}, "icons": {}}}
	var o: Vector2 = K.canvas(SIZE, TOP)[1]
	var pads: Array = []
	for p in PADS:
		pads.append([p.x, p.y])
	var entry := {"size": SIZE, "pivot": [int(o.x), int(o.y)], "states": {}, "flat": true,
		"g71": {"kind": "farp", "pads": pads, "faction": "a"},
		"fits": "4x4 forward arming and refuelling point: 2 rotorcraft pads on one PSP strip (pads = world offsets from the centre)"}
	_put(out, entry, "built", _state(-1, false))
	_put(out, entry, "damaged", _state(-1, true))
	for st in 3:
		_put(out, entry, "build_%d" % st, _state(st, false))
	out.manifest.buildings[DEF] = entry
	var s: Dictionary = entry.states.built
	out.manifest.icons[DEF] = FL.icon(out, DEF, String(s.file), String(s.mask), "")
	return out


static func _put(out: Dictionary, entry: Dictionary, nm: String, cv) -> void:
	var f := "buildings/%s_%s.png" % [DEF, nm]
	var mk := "buildings/%s_%s_mask.png" % [DEF, nm]
	out.images[f] = cv.img
	out.images[mk] = cv.mask
	entry.states[nm] = {"file": f, "mask": mk}


## Part list [u, v, z, hu, hv, hz, colour, role] in the g5_bld_lib local frame (f 0: u = world x, v = world y).
## Index 0 is the gravel slab; the PSP mats follow; then the standing props.
static func parts() -> Array:
	var ps: Array = [[0, 0, 0, 1.96, 1.96, 1, GRAVEL, "slab"]]
	ps.append([(MAT[0] + MAT[2]) * 0.5, (MAT[1] + MAT[3]) * 0.5, 1, (MAT[2] - MAT[0]) * 0.5, (MAT[3] - MAT[1]) * 0.5, 0, PSP, "mat"])
	ps.append([1.05, -1.42, 1, 0.84, 0.46, 0, Color8(116, 106, 82), "mat"])   # bladder bed (scraped earth)
	# fuel point: two pillow bladders inside a sandbag berm, pump skid, drums
	ps.append_array([[0.62, -1.45, 1, 0.36, 0.27, 5, RUBBER, "bladder"], [1.46, -1.45, 1, 0.36, 0.27, 5, RUBBER, "bladder"],
		[1.05, -1.9, 1, 0.86, 0.06, 4, SAND, "bags"], [1.05, -0.98, 1, 0.62, 0.06, 3, SAND, "bags"],
		[1.9, -1.45, 1, 0.06, 0.4, 3, SAND, "bags"], [0.2, -1.45, 1, 0.06, 0.4, 3, SAND, "bags"],
		[1.66, -0.66, 1, 0.2, 0.15, 7, OLIVE, "pump"],
		[1.86, -0.24, 1, 0.07, 0.07, 6, DRUM_G, "cyl"], [1.7, -0.14, 1, 0.07, 0.07, 6, DRUM_G, "cyl"],
		[1.88, -0.02, 1, 0.07, 0.07, 6, DRUM_R, "cyl"]])
	# ops: container + ridge tent (under the net), generator, radio mast
	ps.append_array([[-1.64, -1.08, 1, 0.27, 0.7, 11, OLIVE_C, "cont"], [-1.66, 0.46, 1, 0.28, 0.36, 13, CANVAS, "tent"],
		[-0.86, -1.72, 1, 0.16, 0.12, 6, OLIVE, "gen"], [-1.88, -1.9, 1, 0.02, 0.02, 30, Color8(70, 72, 70), "pole"]])
	# arming point: ammo pallets, rocket pod crates, a pallet of 30 mm boxes on the front edge
	ps.append_array([[-1.12, 1.56, 1, 0.22, 0.2, 6, AMMO, "pallet"], [-0.56, 1.6, 1, 0.22, 0.2, 5, AMMO_D, "pallet"],
		[0.0, 1.62, 1, 0.22, 0.2, 4, AMMO, "pallet"], [0.62, 1.6, 1, 0.34, 0.14, 4, Color8(96, 102, 92), "rocket"],
		[1.3, 1.6, 1, 0.3, 0.14, 4, Color8(96, 102, 92), "rocket"]])
	return ps


## One state: st = construction stage 0..2 (-1 = finished), dmg = the under-50%-hp look.
static func _state(st: int, dmg: bool):
	var cvo := K.canvas(SIZE, TOP)
	var cv = cvo[0]
	var o: Vector2 = cvo[1]
	var raw := st >= 0
	var hk: float = 1.0 if not raw else float([0.0, 0.45, 0.85][st])
	var ps := parts()
	K.part(cv, o, 0, ps[0], 1.0, raw)
	_gravel(cv, o)
	var up: Array = []
	var mats := 0
	for p in ps.slice(1):
		if String(p[7]) == "mat":
			# construction lays the PSP strip in stages: none at stage 0, the left half at 1, all at 2
			if raw and st == 0:
				continue
			if raw and st == 1 and mats == 0:
				var q: Array = (p as Array).duplicate()
				q[0] = (MAT[0] + 0.0) * 0.5
				q[3] = -MAT[0] * 0.5
				K.part(cv, o, 0, q, 1.0, raw)
			else:
				K.part(cv, o, 0, p, 1.0, raw)
			mats += 1
		else:
			up.append(p)
	if not raw:
		decals(cv, o)
	else:
		_survey(cv, o, st)
	if not raw:
		_hoses(cv, o)
	K.render(cv, o, 0, up, hk, raw, func(c, oo, _ff, p, r): dress(c, oo, p, r))
	if raw:
		K.scaffold(cv, o, 0, ps, "a", hk)
		K.stake(cv, o, 0, -1.7, 1.75)
		K.stake(cv, o, 0, 1.75, -1.75)
	else:
		extras(cv, o)
	if dmg:
		K.damage(cv, o, SIZE, SEED)
	cv.outline()
	return cv


## Gravel / earth texture and tyre ruts on the slab top.
static func _gravel(cv, o: Vector2) -> void:
	for i in 220:
		var u := (P.hn(i, SEED, 1) - 0.5) * 3.8
		var v := (P.hn(i, SEED, 2) - 0.5) * 3.8
		var q := K.pt(o, 0, u, v, 1.0)
		var k := P.hn(i, SEED, 3)
		cv.px(int(q.x), int(q.y), P.mul(GRAVEL, 0.78 if k < 0.5 else 1.16))
	for r in [-0.12, 0.12]:
		K.gline(cv, o, 0, -1.9, 1.15 + r, 1.9, 1.15 + r, 1.0, P.mul(GRAVEL, 0.8))


## PSP planking, touchdown circles, H marks, pad numbers and the team band (finished look only).
static func decals(cv, o: Vector2) -> void:
	var z := 1.0
	var n := int(round((MAT[3] - MAT[1]) / 0.14))
	for i in range(1, n):
		var v: float = MAT[1] + i * 0.14
		K.gline(cv, o, 0, MAT[0] + 0.02, v, MAT[2] - 0.02, v, z, PSP_D)
	for i in 64:   # pierced holes: dark dots on a staggered grid
		var u: float = MAT[0] + 0.1 + (i % 16) * 0.188 + (0.09 if (i / 16) % 2 == 1 else 0.0)
		var v: float = MAT[1] + 0.2 + (i / 16) * 0.35
		var q := K.pt(o, 0, u, v, z)
		cv.px(int(q.x), int(q.y), P.mul(PSP_D, 0.8))
	for pi in PADS.size():
		var c: Vector2 = PADS[pi]
		for i in 44:
			var a := i * TAU / 44.0
			var a2 := (i + 0.62) * TAU / 44.0
			K.gline(cv, o, 0, c.x + cos(a) * 0.57, c.y + sin(a) * 0.57, c.x + cos(a2) * 0.57, c.y + sin(a2) * 0.57, z, MARK)
		K.gquad(cv, o, 0, c.x - 0.26, c.y - 0.3, c.x - 0.16, c.y + 0.3, z, MARK)
		K.gquad(cv, o, 0, c.x + 0.16, c.y - 0.3, c.x + 0.26, c.y + 0.3, z, MARK)
		K.gquad(cv, o, 0, c.x - 0.16, c.y - 0.04, c.x + 0.16, c.y + 0.04, z, MARK)
		for k in pi + 1:   # pad number as bars beside the circle
			K.gquad(cv, o, 0, c.x - 0.1 + k * 0.12, c.y + 0.64, c.x - 0.04 + k * 0.12, c.y + 0.66 + 0.02, z, STENCIL)
	K.gquad(cv, o, 0, MAT[0], MAT[3] - 0.08, MAT[2], MAT[3], z, Color(0.85, 0.85, 0.85), true)
	K.gquad(cv, o, 0, MAT[0], MAT[1], MAT[0] + 0.06, MAT[3], z, P.mul(PSP_D, 0.9))


## Construction: string lines and pegs where the strip and the berm go.
static func _survey(cv, o: Vector2, st: int) -> void:
	var col := Color8(232, 120, 60)
	for e in [[MAT[0], MAT[1], MAT[2], MAT[1]], [MAT[2], MAT[1], MAT[2], MAT[3]], [MAT[0], MAT[3], MAT[2], MAT[3]],
			[MAT[0], MAT[1], MAT[0], MAT[3]], [0.2, -1.9, 1.9, -1.9], [0.2, -0.98, 1.9, -0.98]]:
		K.gline(cv, o, 0, e[0], e[1], e[2], e[3], 2.0, col)
		for pe in [Vector2(e[0], e[1]), Vector2(e[2], e[3])]:
			var b := K.pt(o, 0, pe.x, pe.y, 0)
			cv.line_v(b, b + Vector2(0, -3), WOOD)
	if st < 2:   # PSP planks stacked by the strip, waiting to be laid
		for k in 3 - st:
			var r := P.box(cv, o, Vector3(0.9 + k * 0.32, 1.42, 1), 0.13, 0.32, 2 + k, 0.0, PSP, 0.06, 41 + k)
			B.edges(cv, r, PSP)


## Fuel hoses from the pump skid to a nozzle stand at each pad (drawn on the ground before the props).
static func _hoses(cv, o: Vector2) -> void:
	var pump := K.pt(o, 0, 1.5, -0.6, 2)
	for pi in PADS.size():
		var c: Vector2 = PADS[pi]
		var nz := K.pt(o, 0, c.x + 0.5, c.y - 0.62, 1.5)
		B.cable(cv, pump, nz, -1.0 if pi == 0 else -0.5, HOSE)
	for b in [Vector2(0.62, -1.45), Vector2(1.46, -1.45)]:
		B.cable(cv, K.pt(o, 0, b.x + 0.2, b.y + 0.24, 2), pump, -0.6, HOSE)
	B.cable(cv, K.pt(o, 0, -0.8, -1.6, 3), K.pt(o, 0, -1.3, -1.1, 4), -0.5, HOSE)   # generator -> container


static func dress(cv, o: Vector2, p: Array, r: Dictionary) -> void:
	var role := String(p[7])
	var col: Color = p[6]
	match role:
		"bladder":   # pillow tank: lighter crown, filler cap, seam
			var t: PackedVector2Array = r.top
			cv.poly(P.sub(t, 0.18, 0.2, 0.82, 0.8), P.mul(col, 1.22))
			cv.poly(P.sub(t, 0.34, 0.34, 0.66, 0.66), P.mul(col, 1.36))
			var cap: Vector2 = P.sub(t, 0.5, 0.5, 0.5, 0.5)[0]
			cv.rect(int(cap.x), int(cap.y) - 1, 2, 2, Color8(150, 150, 140))
			for sd in r.sides:
				cv.line_v(P.sub(sd.quad, 0, 0.5, 1, 0.5)[0], P.sub(sd.quad, 0, 0.5, 1, 0.5)[1], P.mul(col, 0.78))
		"bags":
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				cv.line_v(P.sub(q, 0, 0.5, 1, 0.5)[0], P.sub(q, 0, 0.5, 1, 0.5)[1], P.mul(col, 0.8))
				for i in 6:
					var a: Vector2 = P.sub(q, (i + 0.5) / 6.0, 0, 0, 0)[0]
					cv.px(int(a.x), int(a.y) - 1, P.mul(col, 0.76))
		"pump":
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				cv.poly(P.sub(q, 0.2, 0.35, 0.55, 0.8), Color8(40, 44, 40))
				var g: Vector2 = P.sub(q, 0.75, 0.6, 0.75, 0.6)[0]
				cv.px(int(g.x), int(g.y), Color8(230, 226, 200))
			var t: PackedVector2Array = r.top
			cv.line_v(t[0].lerp(t[2], 0.3), t[0].lerp(t[2], 0.7), Color8(150, 40, 34))
		"cont":   # ISO container: corrugation, end doors with lock bars, stencil
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				var long := absf(sd.n.x) > 0.5
				var ribs := 10 if long else 4
				for i in range(1, ribs):
					var u := float(i) / ribs
					cv.line_v(P.sub(q, u, 0.05, u, 0.05)[0], P.sub(q, u, 0.95, u, 0.95)[0], P.mul(col, 0.84 if i % 2 == 0 else 0.92))
				if not long:
					cv.line_v(P.sub(q, 0.5, 0.05, 0.5, 0.05)[0], P.sub(q, 0.5, 0.95, 0.5, 0.95)[0], P.mul(col, 0.62))
					for u in [0.3, 0.7]:
						cv.line_v(P.sub(q, u, 0.15, u, 0.15)[0], P.sub(q, u, 0.85, u, 0.85)[0], Color8(150, 150, 140))
				else:
					B.door(cv, q, 0.62, 0.8, 0.8, col)
					cv.poly(P.sub(q, 0.12, 0.4, 0.36, 0.55), STENCIL)
			var t: PackedVector2Array = r.top
			cv.poly(P.sub(t, 0.3, 0.2, 0.7, 0.4), Color8(120, 124, 120))   # roof AC unit
		"gen":
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				for i in 3:
					var v := 0.3 + i * 0.2
					cv.line_v(P.sub(q, 0.15, v, 0.85, v)[0], P.sub(q, 0.15, v, 0.85, v)[1], Color8(44, 48, 42))
			var ex: Vector2 = P.sub(r.top, 0.8, 0.2, 0.8, 0.2)[0]
			cv.line_v(ex, ex + Vector2(0, -3), Color8(54, 54, 50))
		"pallet":   # olive ammo boxes on a wooden pallet: box seams, latches, yellow stencil band
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				cv.poly(P.sub(q, 0, 0, 1, 0.22), WOOD)
				var rows := maxi(1, int(float(p[5]) / 3.0))
				for i in range(1, rows + 1):
					var v := 0.22 + (0.78 / (rows + 1)) * i
					cv.line_v(P.sub(q, 0, v, 1, v)[0], P.sub(q, 0, v, 1, v)[1], P.mul(col, 0.74))
				for u in [0.33, 0.66]:
					cv.line_v(P.sub(q, u, 0.22, u, 0.22)[0], P.sub(q, u, 1, u, 1)[0], P.mul(col, 0.8))
				var s: Vector2 = P.sub(q, 0.1, 0.72, 0.1, 0.72)[0]
				cv.rect(int(s.x), int(s.y), 3, 1, STENCIL)
			var t: PackedVector2Array = r.top
			cv.line_v(t[0].lerp(t[1], 0.5), t[3].lerp(t[2], 0.5), P.mul(col, 0.8))
		"rocket":   # rocket pod crates: long boxes with end caps
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				cv.poly(P.sub(q, 0, 0, 1, 0.25), WOOD)
				cv.line_v(P.sub(q, 0, 0.62, 1, 0.62)[0], P.sub(q, 0, 0.62, 1, 0.62)[1], P.mul(col, 0.76))
			var t: PackedVector2Array = r.top
			for u in [0.08, 0.92]:
				cv.line_v(t[0].lerp(t[1], u), t[3].lerp(t[2], u), STENCIL)


## Finished-look extras: camouflage net on poles over the ops corner, nozzle stands, lamps, mast, windsock, cones.
static func extras(cv, o: Vector2) -> void:
	_net(cv, o)
	for pi in PADS.size():
		var c: Vector2 = PADS[pi]
		var b := K.pt(o, 0, c.x + 0.5, c.y - 0.62, 1)
		cv.rect(int(b.x) - 1, int(b.y) - 6, 3, 6, Color8(150, 40, 34))   # nozzle stand (red), hose loop
		cv.px(int(b.x) + 2, int(b.y) - 4, HOSE)
		cv.px(int(b.x) + 3, int(b.y) - 3, HOSE)
		cv.px(int(b.x) + 3, int(b.y) - 2, HOSE)
		var ex := K.pt(o, 0, c.x - 0.5, c.y - 0.62, 1)   # extinguisher
		cv.rect(int(ex.x), int(ex.y) - 4, 2, 4, Color8(210, 44, 36))
		cv.px(int(ex.x), int(ex.y) - 5, Color8(40, 40, 40))
	for s in [Vector2(MAT[0], MAT[1]), Vector2(MAT[2], MAT[1]), Vector2(MAT[2], MAT[3]), Vector2(MAT[0], MAT[3])]:
		K.lamp(cv, K.pt(o, 0, s.x, s.y, 2.5), LAMP_G)
	for i in 5:
		K.lamp(cv, K.pt(o, 0, MAT[0] + 0.5 + i * 0.5, MAT[3] + 0.06, 2.5), LAMP_A if i % 2 == 0 else LAMP_G)
	var tip := K.pt(o, 0, -1.88, -1.9, 31)
	cv.line_v(tip, tip + Vector2(-4, 5), Color8(80, 80, 76))   # mast whip + guy
	cv.line_v(tip, tip + Vector2(4, 5), Color8(80, 80, 76))
	K.lamp(cv, tip + Vector2(0, -1), Color8(238, 64, 48))
	cv.team = true
	cv.poly(PackedVector2Array([tip + Vector2(0, 4), tip + Vector2(7, 6), tip + Vector2(0, 9)]), Color(0.8, 0.8, 0.8))
	cv.team = false
	DA._sock(cv, K.pt(o, 0, 1.9, 1.2, 1))
	for s in [Vector2(-1.9, 1.9), Vector2(1.9, 1.9), Vector2(-1.9, -0.3)]:
		var q := K.pt(o, 0, s.x, s.y, 1)
		cv.px(int(q.x), int(q.y) - 2, Color8(240, 120, 40))
		cv.rect(int(q.x) - 1, int(q.y) - 1, 3, 1, Color8(240, 120, 40))


## Camouflage net over the container + tent: a sagging sheet on 5 poles, broken into olive / brown / dark tufts with
## holes (things under it show through), hanging skirt on the camera side.
static func _net(cv, o: Vector2) -> void:
	var u0 := -1.97
	var u1 := -1.33
	var v0 := -1.86
	var v1 := 0.92
	var zt := 17.0
	var poles := [Vector2(u0 + 0.05, v0 + 0.05), Vector2(u1, v0 + 0.05), Vector2(u1, (v0 + v1) * 0.5), Vector2(u1, v1), Vector2(u0 + 0.05, v1)]
	for pp in poles:
		cv.line_v(K.pt(o, 0, pp.x, pp.y, 0), K.pt(o, 0, pp.x, pp.y, zt), POLE_C)
	var nu := 30
	var nv := 70
	for j in nv:
		for i in nu:
			var u := u0 + (u1 - u0) * (i + 0.5) / nu
			var v := v0 + (v1 - v0) * (j + 0.5) / nv
			var du := (u - (u0 + u1) * 0.5) / ((u1 - u0) * 0.5)
			var dv := (v - (v0 + v1) * 0.5) / ((v1 - v0) * 0.5)
			var z := zt - 3.0 * (1.0 - maxf(absf(du), absf(dv * 0.9)))   # sags between the poles
			var h := P.vnoise(u * 9.0, v * 9.0, 1.0, SEED + 3)
			var k := P.hn(i, j, SEED + 5)
			if h < 0.2 or k < 0.05:
				continue   # hole
			var c: Color = NET_A if h < 0.55 else (NET_B if h < 0.72 else NET_C)
			c = P.mul(c, 0.9 + 0.2 * k)
			var q := K.pt(o, 0, u, v, z)
			cv.px(int(q.x), int(q.y), c)
			cv.px(int(q.x) + 1, int(q.y), P.mul(c, 0.92))
			if k > 0.5:
				cv.px(int(q.x), int(q.y) + 1, P.mul(c, 0.86))
	for j in 24:   # skirt hanging from the +u (camera-side) edge
		var v := v0 + (v1 - v0) * (j + 0.5) / 24.0
		var q := K.pt(o, 0, u1, v, zt - 1.0)
		var dl := 3 + P.hi(j, 0, SEED + 7, 5)
		for d in dl:
			if P.hn(j, d, SEED + 9) > 0.3:
				cv.px(int(q.x), int(q.y) + d, NET_A if d % 2 == 0 else NET_C)
