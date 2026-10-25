extends RefCounted
## G6 proposal art, module g6_dronebld (agent art-dronebld): drones / drone support + industrial and
## Machine buildings, drawn only with the game's own art libraries (res://tools/art/*).
##   a_aerostat         Human A winch truck (truck.gd chassis) flying a tethered blimp with sensor pod
##   a_loiter_truck     Human A truck with a tilting 2x3 loitering-munition launcher (fire = drone leaves a cell)
##   a_drone_cc         Human A building: concrete ops block, lattice mast + dish, drone pad, drone rack container
##   b_fpv_workshop     Human B building: corrugated shed + brick lean-to, workbench with FPV frames, test drone
##   b_jammer_team      Human B 2-man squad, backpack jammers with whip antennas (jam = crouched, field rings)
##   b_scrap_aa         Human B 3-man squad with big-bore scrap shotguns (fire = pellet clouds upward)
##   m_hive_node        Machine building: honeycomb hex hive, glowing cells, micro-drones leaving it
##   m_swarm_queen      Machine air: big hexacopter with ducted rotors (fire = micro-drones released)
##   m_mimic_drone      Machine air: wears a Human A quad hologram with scan glitches (fire/dive = true form)
##   b_rail_yard        Human B building: two rail tracks, brick engine shed, water tower, wagon on the slip
##   b_armored_train    Human B: armored locomotive + gun/flak car on a short rail section (wide vehicle frame)
##   b_scrapyard        Human B building: portal gantry magnet crane over scrap piles, baler, bales
##   b_propaganda_tower Human B building: lattice tower, loudspeaker horns, team banner, brick hut
##   m_nanite_forge     Machine building: ribbed dome on a hex base, nanite cloud swirling above
##   m_overmind         Machine building: tall tapered uplink spire, halo rings, cyan uplink beam
##   m_relay_lattice    Machine building: three linked pylons with cyan power links
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const VH = preload("res://tools/art/vehicles.gd")
const T = preload("res://tools/art/truck.gd")
const V = preload("res://tools/art/faction_b_veh.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")
const SQ = preload("res://tools/art/g5_units_sq.gd")
const FIG = preload("res://tools/art/g5_units_fig.gd")
const BI = preload("res://tools/art/faction_b_inf.gd")
const M = preload("res://tools/art/faction_m_lib.gd")
const G = preload("res://tools/art/g3b_lib.gd")
const GM = preload("res://tools/art/g3b_machine.gd")
const DR = preload("res://tools/art/g5_units_drone.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")
const B = preload("res://tools/art/bdetail.gd")
const R = preload("res://tools/art/faction_b_bdress.gd")
const BD = preload("res://tools/art/faction_m_bdress.gd")
const FB = preload("res://tools/art/faction_b_bld.gd")
const H = preload("res://tools/art/g6_lib.gd")

const OUTL := Color(0.09, 0.09, 0.07, 1)
const MOUTL := Color(0.07, 0.08, 0.09, 1)
const ENV := Color8(178, 182, 170)      # aerostat envelope, light grey-olive
const CELL := Color8(78, 84, 62)        # launcher cell lids
const STEEL_LIT := Color8(150, 148, 140)
const BALLAST := Color8(96, 90, 80)
const TIE := Color8(70, 54, 40)
const WOOD := Color8(120, 90, 58)
const CRATE := Color8(128, 104, 70)
const ORANGE := Color8(176, 112, 48)
const ORANGE_D := Color8(132, 82, 40)
const AMBER := Color8(236, 196, 110)
const PACK := Color8(72, 74, 62)
const HORN := Color8(116, 118, 100)
const CONT_A := Color8(186, 186, 174)
const BS := {"coat": BI.DRILL, "trouser": BI.TROUSER, "boot": BI.BOOT, "skin": BI.SKIN, "head": "helm_b",
	"weapon": "rifle", "belt": BI.LEATHER}
const B_ROLES := ["brick", "shed", "sawtooth", "bunker", "plate", "sandbag"]
const CYL := ["stack", "boiler", "drum", "furnace"]

const SHOW := {
	"a_aerostat": {"row": 0, "frame": "deployed", "ground": "grass"},
	"a_loiter_truck": {"row": 2, "frame": "fire", "ground": "dirt"},
	"a_drone_cc": {"row": 0, "ground": "conc"},
	"b_fpv_workshop": {"row": 0, "ground": "dirt"},
	"b_jammer_team": {"row": 1, "frame": "jam", "ground": "grass"},
	"b_scrap_aa": {"row": 1, "frame": "fire", "ground": "grass"},
	"m_hive_node": {"row": 0, "ground": "grass"},
	"m_swarm_queen": {"row": 0, "frame": "fire", "ground": "grass", "alt": 22, "shadow": [18, 8]},
	"m_mimic_drone": {"row": 0, "frame": "idle", "ground": "grass", "alt": 16, "shadow": [6, 3]},
	"b_rail_yard": {"row": 0, "ground": "dirt"},
	"b_armored_train": {"row": 0, "frame": "fire", "ground": "dirt"},
	"b_scrapyard": {"row": 0, "ground": "dirt"},
	"b_propaganda_tower": {"row": 0, "ground": "grass"},
	"m_nanite_forge": {"row": 0, "ground": "grass"},
	"m_overmind": {"row": 0, "ground": "conc"},
	"m_relay_lattice": {"row": 0, "ground": "grass"},
}


static func build(out: Dictionary) -> void:
	SL.veh_sheet(out, "a_aerostat", {"fw": 76, "fh": 104, "pivot": [38, 84]}, aerostat, ["idle", "move", "fire", "deployed"])
	SL.veh_sheet(out, "a_loiter_truck", {"fw": 68, "fh": 58, "pivot": [34, 40]}, loiter_truck, ["idle", "move", "fire", "deployed"])
	H.bld(out, "a_drone_cc", 2, 64, drone_cc)
	H.bld(out, "b_fpv_workshop", 2, 56, fpv_workshop)
	SL.squad_sheet(out, "b_jammer_team", 2, jammer_team, JAM_FR)
	SL.squad_sheet(out, "b_scrap_aa", 3, scrap_aa, AA_FR)
	H.bld(out, "m_hive_node", 2, 64, hive_node)
	var shq := SL.drone_shadow(out, "g6_queen_shadow", 18.0, 8.0)
	SL.veh_sheet(out, "m_swarm_queen", {"fw": 76, "fh": 56, "pivot": [38, 36]}, swarm_queen, ["idle", "move", "fire"],
		{"air": true, "altitude": 22, "bob": 1, "shadow": shq})
	var shm := SL.drone_shadow(out, "g6_mimic_shadow", 6.0, 3.0)
	SL.veh_sheet(out, "m_mimic_drone", {"fw": 40, "fh": 34, "pivot": [20, 22]}, mimic, ["idle", "move", "fire", "dive"],
		{"air": true, "altitude": 16, "bob": 1, "shadow": shm})
	H.bld(out, "b_rail_yard", 3, 64, rail_yard)
	SL.veh_sheet(out, "b_armored_train", {"fw": 112, "fh": 68, "pivot": [56, 46]}, armored_train, ["idle", "move", "fire"])
	H.bld(out, "b_scrapyard", 3, 70, scrapyard)
	H.bld(out, "b_propaganda_tower", 1, 86, propaganda_tower)
	H.bld(out, "m_nanite_forge", 2, 72, nanite_forge)
	H.bld(out, "m_overmind", 2, 108, overmind)
	H.bld(out, "m_relay_lattice", 1, 44, relay_lattice)


# ================================================================ shared helpers
static func _kk(rot: float) -> int:
	return posmod(int(round(rot / (PI / 4.0))), 8)


## Box with yaw `rot` and nose-up `pitch` about its rear-bottom edge (1 tile = 32 px of z). Draws the
## visible faces (screen winding), returns {name: quad} for the drawn faces. Side quads follow P.box's
## [bottom-a, bottom-b, top-b, top-a] order (v = 0 bottom, 1 top).
static func _tbox(cv, o: Vector2, rot: float, fwd: float, right: float, z: float, hx: float, hy: float, hz: float,
		pitch: float, col: Color, s: int) -> Dictionary:
	var ca := cos(pitch)
	var sa := sin(pitch)
	var pts := {}
	for ia in [-1, 1]:
		for ib in [-1, 1]:
			for ic in [0, 1]:
				var la: float = (ia + 1) * hx
				var lc: float = ic * hz / 32.0
				var a: float = fwd - hx + la * ca - lc * sa
				var zz: float = z + (la * sa + lc * ca) * 32.0
				pts[Vector3i(ia, ib, ic)] = D.sp(o, rot, a, right + ib * hy, zz)
	var faces := {
		"top": [Vector3i(-1, -1, 1), Vector3i(1, -1, 1), Vector3i(1, 1, 1), Vector3i(-1, 1, 1)],
		"front": [Vector3i(1, -1, 0), Vector3i(1, 1, 0), Vector3i(1, 1, 1), Vector3i(1, -1, 1)],
		"back": [Vector3i(-1, 1, 0), Vector3i(-1, -1, 0), Vector3i(-1, -1, 1), Vector3i(-1, 1, 1)],
		"right": [Vector3i(1, 1, 0), Vector3i(-1, 1, 0), Vector3i(-1, 1, 1), Vector3i(1, 1, 1)],
		"left": [Vector3i(-1, -1, 0), Vector3i(1, -1, 0), Vector3i(1, -1, 1), Vector3i(-1, -1, 1)],
	}
	var fw := Vector2(cos(rot), sin(rot))
	var rt := Vector2(-sin(rot), cos(rot))
	var nrm := {"top": [fw * -sa, ca], "front": [fw * ca, sa], "back": [fw * -ca, -sa], "right": [rt, 0.0], "left": [-rt, 0.0]}
	var outq := {}
	for nm in faces:
		var q := PackedVector2Array()
		for key in faces[nm]:
			q.append(pts[key])
		var area := 0.0
		for i in 4:
			var a2: Vector2 = q[i]
			var b2: Vector2 = q[(i + 1) % 4]
			area += a2.x * b2.y - b2.x * a2.y
		if area <= 0.5:
			continue
		var nx: Vector2 = nrm[nm][0]
		var nz: float = nrm[nm][1]
		var sh: float = P.side_shade(nx) if nx.length() > 0.05 else 0.85
		sh = lerpf(sh, 1.0, clampf(nz, 0.0, 1.0))
		cv.poly(q, P.mul(col, sh), P.speckle(0.07, s + q.size()))
		outq[nm] = q
	return outq


## Human A truck (truck.gd chassis, wheels, cab, exhaust) with a custom bed drawn by bed(body).
static func _atruck(cv, o: Vector2, rot: float, f: int, wreck: bool, bed_hz: float, bed: Callable) -> void:
	var body: Color = T.BURNT if wreck else T.BODY
	P.box_shadow(cv, o, D.w(rot, 0.0, 0.0, 0), 0.52, 0.22, 4.0, rot)
	P.box_shadow(cv, o, D.w(rot, 0.36, 0.0, 4.5), 0.16, 0.22, 9.5, rot)
	P.box_shadow(cv, o, D.w(rot, -0.2, 0.0, 4.5), 0.34, 0.23, bed_hz, rot)
	cv.flush_shadow()
	T._wheels(cv, o, rot, f, wreck, false)
	var ch: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 2.0), 0.52, 0.16, 2.5, rot, T.CHASSIS if not wreck else T.CHAR, 0.08, 971)
	for sd in ch.sides:
		if absf((sd.n as Vector2).dot(Vector2(cos(rot), sin(rot)))) > 0.7:
			D.tow_hooks(cv, sd.quad)
	T._wheels(cv, o, rot, f, wreck, true)
	if D.faces_cam(rot, 1.0, 0.0):
		bed.call(body)
		T._exhaust(cv, o, rot, wreck)
		T._cab(cv, o, rot, body, wreck)
	else:
		T._cab(cv, o, rot, body, wreck)
		T._exhaust(cv, o, rot, wreck)
		bed.call(body)


## Open flatbed (truck.gd _bed style without cargo): boards, stakes, team stripe.
static func _abed(cv, o: Vector2, rot: float, body: Color, wreck: bool, hz := 3.0) -> Dictionary:
	var r: Dictionary = P.box(cv, o, D.w(rot, -0.2, 0.0, 4.5), 0.34, 0.23, hz, rot, body, 0.08, 19)
	cv.poly(P.sub(r.top, 0.04, 0.06, 0.96, 0.94), P.mul(body, 0.5) if not wreck else T.CHAR)
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		for u in [0.33, 0.66]:
			cv.line_v(q[0].lerp(q[1], u), q[3].lerp(q[2], u), P.mul(body, 0.8))
		if not wreck:
			cv.team = true
			cv.poly(P.sub(q, 0.04, 0.5, 0.96, 0.8), Color(0.64, 0.64, 0.64))
			cv.team = false
			D.mud(cv, q, 540 + int(q[0].x), 0.22)
	D.contact_ao(cv, r)
	if not wreck:
		D.box_edges(cv, r, body, 137)
	return r


## Shaded ellipsoid in screen space: centre c, major half-vector ax, minor radius rmin. Lit from the upper
## left; optional team band ring around the middle. Returns the unit major axis.
static func _blob(cv, c: Vector2, ax: Vector2, rmin: float, col: Color, band := false, s := 7) -> Vector2:
	var a := maxf(ax.length(), rmin * 1.05)
	var u := ax.normalized() if ax.length() > 0.5 else Vector2(1, 0)
	var v := Vector2(-u.y, u.x)
	var ls := Vector2(-0.55, -0.83)
	var rr := int(ceil(a)) + 1
	for y in range(int(c.y) - rr, int(c.y) + rr + 1):
		for x in range(int(c.x) - rr, int(c.x) + rr + 1):
			var lp := Vector2(x + 0.5 - c.x, y + 0.5 - c.y)
			var su := lp.dot(u) / a
			var tv := lp.dot(v) / rmin
			var e := su * su + tv * tv
			if e > 1.0:
				continue
			var nv := u * su + v * tv
			var nz := sqrt(1.0 - e)
			var k := clampf(0.66 + nv.dot(ls) * 0.3 + nz * 0.2, 0.45, 1.22) * (1.0 + (P.hn(x, y, s) - 0.5) * 0.04)
			if absf(absf(su) - 0.45) < 0.035:
				k *= 0.88
			if band and absf(su - 0.08) < 0.09:
				cv.team = true
				cv.px(x, y, Color(0.72 * k, 0.72 * k, 0.72 * k))
				cv.team = false
			else:
				cv.px(x, y, P.mul(col, k))
	return u


# ================================================================ a_aerostat
static func aerostat(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	if wreck:  # deflated envelope draped beside the burnt truck
		var e := D.sp(o, rot, -0.45, 0.42, 0)
		cv.ellipse(e.x, e.y, 13.0, 4.5, P.mul(ENV, 0.36))
		cv.ellipse(e.x - 2, e.y - 1, 9.0, 3.0, P.mul(ENV, 0.46))
		cv.ellipse(e.x + 4, e.y, 2.5, 1.2, Color8(30, 28, 26))
		for i in 4:
			var a := e + Vector2(-8 + i * 5, -2 + (i % 2) * 2)
			cv.line_v(a, a + Vector2(3, 2), P.mul(ENV, 0.32))
	_atruck(cv, o, rot, f, wreck, 9.0, func(body: Color) -> void: _winch_bed(cv, o, rot, body, wreck))
	if wreck:
		cv.outline(OUTL)
		V.soot(cv, D.sp(o, rot, 0.0, 0.0, 12), 6.0, 1101)
		return
	var zb: float = [46.0, 32.0, 62.0, 62.0][f]
	var bc := D.sp(o, rot, -0.34, 0.03, zb)
	var ax := D.sp(o, rot, 0.42, 0.0, 0) - D.sp(o, rot, 0.0, 0.0, 0)
	var rmin := 8.0
	var a := maxf(ax.length(), rmin * 1.05)
	var u := ax.normalized() if ax.length() > 0.5 else Vector2(1, 0)
	var vv := Vector2(-u.y, u.x)
	var tail := bc - u * a * 0.82
	var finc := P.mul(ENV, 0.86)
	var away := u.y < -0.2  # nose away from camera: tail fins are in front of the body
	if not away:
		_fins(cv, tail, u, vv, a, rmin, finc)
	_blob(cv, bc, ax, rmin, ENV, true, 1103)
	if away:
		_fins(cv, tail, u, vv, a, rmin, finc)
	var pod := bc + Vector2(0, rmin + 2)
	cv.rect(int(pod.x) - 2, int(pod.y) - 2, 5, 2, P.mul(ENV, 0.7))  # pod pylon
	cv.ellipse(pod.x, pod.y + 1, 2.6, 2.2, VH.GUNMETAL)
	cv.px(int(pod.x) + (1 if u.x >= 0 else -1), int(pod.y) + 1, D.VISION)
	cv.outline(OUTL)
	var winch := D.sp(o, rot, -0.18, 0.0, 15)
	var bottom := pod + Vector2(0, 3)
	cv.line_v(winch, bottom, Color8(36, 36, 34))  # tether
	if f == 1:
		for s in [-1.0, 1.0]:  # lashed down on the move: guy lines to the bed corners
			cv.line_v(bc + vv * rmin * 0.7 * s, D.sp(o, rot, -0.2, 0.22 * s, 8), Color8(52, 52, 48))
	if f == 2 or f == 3:
		cv.px(int(pod.x) + (1 if u.x >= 0 else -1), int(pod.y) + 1, Color8(220, 255, 255))
	if f == 2:
		G.pulse(cv, pod + Vector2(0, 2), 9.0, Color8(200, 236, 240))


static func _fins(cv, tail: Vector2, u: Vector2, vv: Vector2, a: float, rmin: float, col: Color) -> void:
	var t0 := tail + u * 2.0
	var t1 := tail - u * a * 0.2
	cv.poly(PackedVector2Array([t0, t1, t1 + Vector2(0, -rmin * 0.95)]), P.mul(col, 1.08))  # top fin
	for s in [-1.0, 1.0]:
		cv.poly(PackedVector2Array([t0, t1, t1 + vv * rmin * 0.95 * s + Vector2(0, 1)]), P.mul(col, 0.9))


static func _winch_bed(cv, o: Vector2, rot: float, body: Color, wreck: bool) -> void:
	_abed(cv, o, rot, body, wreck)
	var steel: Color = VH.GUNMETAL if not wreck else T.CHAR
	var parts := [[-0.45, 0.07, 0.17, 5.0, P.mul(body, 0.9), "gen"], [-0.18, 0.09, 0.15, 6.0, steel, "winch"]]
	if not D.faces_cam(rot, 1.0, 0.0):
		parts.reverse()
	for p in parts:
		var r: Dictionary = P.box(cv, o, D.w(rot, p[0], 0.0, 7.5), p[1], p[2], p[3], rot, p[4], 0.07, 1111)
		if wreck:
			T._scorch(cv, r.top)
			continue
		D.box_edges(cv, r, p[4], 1112)
		if p[5] == "gen":
			D.grille(cv, r.top, 0.15, 0.2, 0.85, 0.8, p[4], 4)
		else:
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				for vb in [0.3, 0.7]:
					cv.line_v(q[0].lerp(q[3], vb), q[1].lerp(q[2], vb), P.mul(steel, 1.35))  # drum bands
			var t: PackedVector2Array = r.top
			cv.px(int((t[0].x + t[2].x) * 0.5), int((t[0].y + t[2].y) * 0.5), Color8(170, 168, 150))  # sheave


# ================================================================ a_loiter_truck
static func loiter_truck(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var pitch: float = 0.0 if (f <= 1 or wreck) else 0.42
	var info := {}
	_atruck(cv, o, rot, f, wreck, 12.0, func(body: Color) -> void:
		_abed(cv, o, rot, body, wreck)
		info.merge(_launcher(cv, o, rot, pitch, f, body, wreck), true))
	var k := _kk(rot)
	var d := L.sd(k)
	var rr := L.sd((k + 2) % 8)
	var cellp := Vector2.ZERO
	var has := false
	if info.has("front"):
		cellp = (info.front as PackedVector2Array)[2].lerp((info.front as PackedVector2Array)[3], 0.17) + Vector2(0, 2)
		has = true
	elif info.has("top"):
		var t: PackedVector2Array = info.top
		cellp = t[1].lerp(t[2], 0.5)
		has = true
	var mc := cellp + Vector2(d.x * 9.0, d.y * 4.5 - 9.0)
	if f == 2 and not wreck:
		DR._munition(cv, mc, d, rr, 2.0, f)
	cv.outline(OUTL)
	if wreck:
		V.soot(cv, D.sp(o, rot, -0.2, 0.0, 16), 6.0, 1121)
		L.puff(cv, D.sp(o, rot, -0.25, 0.05, 22), 3.0, 0.35, Color(0.3, 0.29, 0.27))
	elif f == 2 and has:
		cv.line_v(cellp, mc - Vector2(d.x * 4.0, d.y * 2.0), Color(0.92, 0.92, 0.88, 0.6))
		L.puff(cv, cellp + Vector2(0, -1), 3.0, 0.5)
		L.puff(cv, cellp - Vector2(d.x * 3.0, -1), 2.4, 0.35)
		L.flash(cv, cellp, 0.8)


static func _launcher(cv, o: Vector2, rot: float, pitch: float, f: int, body: Color, wreck: bool) -> Dictionary:
	var steel: Color = VH.GUNMETAL if not wreck else T.BURNT
	P.box(cv, o, D.w(rot, -0.44, 0, 7.5), 0.05, 0.12, 2.5, rot, steel, 0.06, 1131)  # hinge block
	if pitch > 0.0:
		for s in [-1.0, 1.0]:  # hydraulic rams
			var a := D.sp(o, rot, -0.06, 0.1 * s, 7.5)
			var b := D.sp(o, rot, -0.12, 0.1 * s, 8.0 + 0.36 * sin(pitch) * 32.0)
			cv.line_v(a, b, Color8(150, 150, 140))
			cv.line_v(a + Vector2(1, 0), b + Vector2(1, 0), steel)
	var col: Color = body if not wreck else T.BURNT
	var fq: Dictionary = _tbox(cv, o, rot, -0.2, 0.0, 9.0, 0.27, 0.17, 7.5, pitch, col, 1133)
	for nm in fq:
		var q: PackedVector2Array = fq[nm]
		if wreck:
			if nm == "top":
				T._scorch(cv, q)
			continue
		match nm:
			"front", "back":
				for yy in 2:
					for xx in 3:
						var c := P.sub(q, 0.07 + xx * 0.3, 0.1 + yy * 0.45, 0.31 + xx * 0.3, 0.45 + yy * 0.45)
						var open: bool = nm == "front" and f == 2 and xx == 2 and yy == 1
						cv.poly(c, Color8(24, 24, 22) if open else (CELL if nm == "front" else P.mul(CELL, 0.8)))
						if not open:
							cv.line_v(c[3], c[2], P.mul(CELL, 1.35))
							cv.px(int((c[0].x + c[2].x) * 0.5), int((c[0].y + c[2].y) * 0.5), Color8(196, 176, 90))
			"left", "right":
				cv.team = true
				cv.poly(P.sub(q, 0.08, 0.32, 0.92, 0.66), Color(0.64, 0.64, 0.64))
				cv.team = false
				cv.line_v(q[0].lerp(q[3], 0.12), q[1].lerp(q[2], 0.12), P.mul(col, 0.72))
				var st := P.sub(q, 0.1, 0.78, 0.22, 0.86)
				cv.poly(st, Color8(200, 184, 100))  # stencil
			"top":
				for vb in [0.33, 0.66]:
					var ln := P.sub(q, 0.0, vb, 1.0, vb)
					cv.line_v(ln[0], ln[1], P.mul(col, 0.74))
				var e := P.sub(q, 0.0, 0.0, 1.0, 0.0)
				cv.line_v(e[0], e[1], P.mul(col, 1.3))
	return fq


# ================================================================ a_drone_cc
static func drone_cc(cv, o: Vector2, f: int) -> void:
	var ps := [
		[0, 0, 0, 0.95, 0.95, 2, K.pal("a", "slab"), "slab"],
		[-0.3, -0.28, 2, 0.52, 0.48, 20, K.pal("a", "wall"), "hq"],
		[-0.4, -0.4, 22, 0.27, 0.24, 7, CONT_A, "ops"],
		[0.55, -0.48, 2, 0.32, 0.17, 10, Color8(98, 102, 76), "cont"],
		[-0.72, 0.62, 2, 0.15, 0.12, 7, K.pal("a", "metal"), "gen"],
		[0.85, 0.12, 2, 0.06, 0.06, 6, Color8(84, 96, 62), "cyl"],
	]
	K.render(cv, o, f, ps, 1.0, false, func(c, oo, ff, p, r): _cc_dress(c, oo, ff, p, r))
	# drone pad: dark tarmac square, white border, aiming cross
	var pu := 0.42
	var pv := 0.42
	K.gquad(cv, o, f, pu - 0.36, pv - 0.36, pu + 0.36, pv + 0.36, 2.2, K.pal("a", "tarmac"))
	var mk := K.pal("a", "mark")
	for e in [[-1, -1, 1, -1], [1, -1, 1, 1], [1, 1, -1, 1], [-1, 1, -1, -1]]:
		K.gline(cv, o, f, pu + e[0] * 0.31, pv + e[1] * 0.31, pu + e[2] * 0.31, pv + e[3] * 0.31, 2.3, mk)
	K.gline(cv, o, f, pu - 0.14, pv, pu + 0.14, pv, 2.3, mk)
	K.gline(cv, o, f, pu, pv - 0.14, pu, pv + 0.14, 2.3, mk)
	_quad_a(cv, K.pt(o, f, pu + 0.12, pv - 0.1, 4), 0.0, false)  # parked drone
	# lattice mast on the roof with antennas and a red lamp, dish beside the ops module
	var mb := K.pt(o, f, -0.68, -0.62, 22)
	var mt := mb + Vector2(0, -36)
	G.lattice(cv, mb, mt, 2.0, Color8(96, 98, 94))
	cv.line_v(mt + Vector2(-4, 6), mt + Vector2(4, 6), Color8(70, 72, 70))
	G.whip(cv, mt + Vector2(-4, 6), 7, Color8(220, 60, 50))
	G.whip(cv, mt + Vector2(4, 6), 5, Color8(200, 200, 190))
	cv.line_v(mt, mt + Vector2(0, -6), Color8(50, 52, 50))
	cv.px(int(mt.x), int(mt.y) - 7, Color8(236, 60, 50))
	var dc := K.wp(f, -0.08, -0.05)
	G.dish(cv, o, Vector3(dc.x, dc.y, 30), 0.6, 6.0, Color8(196, 196, 186))
	# team flag at the front corner
	var fb := K.pt(o, f, -0.82, 0.82, 2)
	cv.line_v(fb, fb + Vector2(0, -24), Color8(70, 70, 66))
	cv.team = true
	cv.rect(int(fb.x) + 1, int(fb.y) - 24, 8, 5, Color(0.82, 0.82, 0.82))
	cv.team = false
	# a drone lifting off the pad (soft shadow on the pad)
	var hp := K.pt(o, f, pu - 0.1, pv + 0.12, 2.3)
	cv.ellipse(hp.x, hp.y, 4.0, 1.6, Color(0, 0, 0, 0.28))
	_quad_a(cv, hp + Vector2(0, -20), 0.0, true)


## Small Human A quad (g5_units_drone A palette) at screen point c.
static func _quad_a(cv, c: Vector2, _p: float, spin: bool) -> void:
	var tips := [Vector2(-5, -1), Vector2(5, -1), Vector2(-4, 2), Vector2(4, 2)]
	for t: Vector2 in tips:
		cv.line_v(c, c + t, DR.A_DARK)
		if spin:
			cv.ellipse(c.x + t.x, c.y + t.y - 1, 2.6, 1.0, Color(0.84, 0.86, 0.86, 0.45))
		else:
			cv.line_v(c + t + Vector2(-2, -1), c + t + Vector2(2, -1), Color8(60, 62, 62))
	cv.ellipse(c.x, c.y, 2.4, 1.5, DR.A_BODY)
	cv.rect(int(c.x) - 1, int(c.y) - 2, 3, 1, P.mul(DR.A_BODY, 1.2))
	cv.team = true
	cv.px(int(c.x), int(c.y), Color(0.75, 0.75, 0.75))
	cv.team = false


static func _cc_dress(cv, o: Vector2, f: int, p: Array, r: Dictionary) -> void:
	var role := String(p[7])
	var col: Color = p[6]
	match role:
		"hq":
			var n := 0
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				var cnt := maxi(2, int(q[0].distance_to(q[1]) / 9.0))
				B.window_row(cv, q, 0.2, 0.36, cnt, col, 71 + n, 0.3)
				B.window_row(cv, q, 0.56, 0.72, cnt, col, 75 + n, 0.3)
				if n == 0:
					B.door(cv, q, 0.42, 0.56, 0.42, col)
				cv.team = true
				cv.poly(P.sub(q, 0.0, 0.88, 1.0, 0.95), Color(0.74, 0.74, 0.74))
				cv.team = false
				n += 1
			cv.poly(P.sub(r.top, 0.05, 0.05, 0.95, 0.95), K.pal("a", "roof"))
			var w := K.wp(f, float(p[0]) + 0.3, float(p[1]) + 0.25)
			B.hvac(cv, o, Vector3(w.x, w.y, 22), 0.1, 0.08, 77)
		"ops":
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				var g := P.sub(q, 0.06, 0.42, 0.94, 0.78)
				cv.poly(g, T.GLASS)
				cv.line_v(g[3] + Vector2(1, 1), g[3].lerp(g[2], 0.3) + Vector2(0, 1), T.GLASS_HI)
				for i in 3:
					var u := 0.06 + (i + 1) * 0.22
					cv.line_v(q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), 0.42), q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), 0.78), P.mul(col, 0.8))
				cv.team = true
				cv.poly(P.sub(q, 0.0, 0.1, 1.0, 0.26), Color(0.72, 0.72, 0.72))
				cv.team = false
		"cont":
			for sd in r.sides:
				for i in 6:
					var u := 0.08 + i * 0.17
					cv.line_v(P.sub(sd.quad, u, 0, u, 1)[0], P.sub(sd.quad, u, 0, u, 1)[3], P.mul(col, 0.82))
				cv.team = true
				cv.poly(P.sub(sd.quad, 0.0, 0.8, 1.0, 0.92), Color(0.74, 0.74, 0.74))
				cv.team = false
			for i in 3:  # drone racks: folded quads stacked on the container roof
				var q2 := P.sub(r.top, 0.15 + i * 0.28, 0.3, 0.3 + i * 0.28, 0.7)
				cv.poly(q2, DR.A_BODY)
				cv.px(int(q2[0].x), int(q2[0].y), DR.A_DARK)
		"gen":
			D.grille(cv, r.top, 0.15, 0.2, 0.85, 0.8, col, 3)
			cv.px(int(r.top[1].x), int(r.top[1].y) - 2, D.DARK)


# ================================================================ Human B building renderer
## Part list in the local frame [u, v, z, hu, hv, hz, colour, role] (K.wp rotation); finished look of
## faction_b_bld.draw (slab + oil stains, brick / corrugated dressing, sooty stacks, scrap piles, team flag).
## Roles: B_ROLES (faction_b_bdress), CYL, "scrap", "tent", "x_*" (drawn only by dress), others = box + dress.
static func _bdraw(cv, o: Vector2, f: int, size: int, ps: Array, def: String, pre: Callable, dress: Callable,
		post: Callable, flag := true) -> void:
	var half := size * 0.5 - 0.05
	var rt := K.rot(f)
	var items: Array = ps.duplicate()
	items.sort_custom(func(a, b):
		var la := 1 if float(a[2]) > 4.0 else 0
		var lb := 1 if float(b[2]) > 4.0 else 0
		if la != lb:
			return la < lb
		var wa := K.wp(f, a[0], a[1])
		var wb := K.wp(f, b[0], b[1])
		return wa.x + wa.y + float(a[2]) * 0.001 < wb.x + wb.y + float(b[2]) * 0.001)
	for p in items:
		var c2 := K.wp(f, p[0], p[1])
		var role := String(p[7])
		if role in CYL or role.begins_with("x_"):
			P.box_shadow(cv, o, Vector3(c2.x, c2.y, p[2]), float(p[3]) * 0.85, float(p[3]) * 0.85, p[5], 0.0)
		else:
			P.box_shadow(cv, o, Vector3(c2.x, c2.y, p[2]), p[3], p[4], p[5], rt)
	cv.flush_shadow()
	var slab: Dictionary = P.box(cv, o, Vector3(0, 0, 0), half, half, 2.0, 0.0, FB.SLAB, 0.14, 805)
	B.edges(cv, slab, FB.SLAB)
	R.oil_stains(cv, slab.top, 806 + size)
	if pre.is_valid():
		pre.call(cv, o, f)
	for p in items:
		var c2 := K.wp(f, p[0], p[1])
		var c := Vector3(c2.x, c2.y, p[2])
		var col: Color = p[6]
		var role := String(p[7])
		var hz: float = p[5]
		if role.begins_with("x_"):
			dress.call(cv, o, f, p, {})
			continue
		if role in CYL:
			var band: float = 0.78 if role == "boiler" else -1.0
			var top := B.cyl(cv, o, c, p[3], hz, col, 850 + int(float(p[3]) * 100), band, 3 if role == "boiler" else 0)
			R.cyl_dress(cv, o, def, role, c, p[3], hz, top)
			continue
		if role == "scrap":
			R.scrap_pile(cv, o, c, p[3], p[4], hz, col, 860 + int(float(p[0]) * 10 + float(p[1]) * 7), false)
			continue
		if role == "tent":
			K.tent(cv, o, f, p[0], p[1], p[2], p[3], p[4], hz, col)
			continue
		var r: Dictionary = P.box(cv, o, c, p[3], p[4], hz, rt, col, 0.09, 870 + int(float(p[3]) * 10))
		B.wall_ao(cv, r, 0.3 if float(p[2]) <= 4.0 else 0.18)
		if role in B_ROLES:
			R.dress(cv, o, def, role, p, r, col)
		else:
			B.edges(cv, r, col)
			if dress.is_valid():
				dress.call(cv, o, f, p, r)
	if post.is_valid():
		post.call(cv, o, f)
	if flag:
		var base := P.proj(o, Vector3(-half + 0.12, half - 0.12, 2))
		cv.line(int(base.x), int(base.y), int(base.x), int(base.y) - 34, Color8(62, 56, 50))
		cv.team = true
		for yy in 6:
			for xx in 11:
				var wave := int(round(sin(xx * 0.7) * 0.8))
				cv.px(int(base.x) + 1 + xx, int(base.y) - 34 + yy + wave, Color(0.85, 0.85, 0.85) if yy > 0 else Color(1, 1, 1))
		cv.team = false


## Small hobby FPV quad (g5_units_drone B palette) at screen point c, top view-ish.
static func _fpv(cv, c: Vector2, spin: bool, seed: int) -> void:
	for t: Vector2 in [Vector2(-4, -1), Vector2(4, -1), Vector2(-3, 2), Vector2(3, 2)]:
		cv.line_v(c, c + t, Color8(40, 38, 34))
		if spin:
			cv.ellipse(c.x + t.x, c.y + t.y - 1, 2.4, 0.9, Color(0.84, 0.86, 0.86, 0.4))
		else:
			cv.px(int(c.x + t.x), int(c.y + t.y), Color8(90, 86, 80))
	cv.ellipse(c.x, c.y, 2.0, 1.3, DR.B_BODY)
	cv.px(int(c.x), int(c.y) - 1, DR.TAPE)
	cv.px(int(c.x) + 1, int(c.y), DR.WIRE_R if seed % 2 == 0 else DR.WIRE_Y)


# ================================================================ b_fpv_workshop
static func fpv_workshop(cv, o: Vector2, f: int) -> void:
	var ps := [
		[0.18, -0.22, 2, 0.6, 0.5, 15, FB.IRON, "shed"],
		[-0.62, -0.2, 2, 0.22, 0.42, 10, FB.BRICK, "brick"],
		[-0.66, -0.78, 2, 0.05, 0.05, 30, FB.STEEL, "stack"],
		[0.48, 0.64, 2, 0.32, 0.11, 6, WOOD, "p_bench"],
		[-0.5, 0.58, 2, 0.26, 0.22, 6, FB.RUSTY, "scrap"],
		[0.02, 0.62, 2, 0.09, 0.09, 6, CRATE, "crate"],
		[0.84, -0.8, 2, 0.06, 0.06, 7, FB.DRUM_R, "drum"],
		[0.84, -0.6, 2, 0.06, 0.06, 7, FB.DRUM_O, "drum"],
	]
	_bdraw(cv, o, f, 2, ps, "b_fpv_workshop", Callable(), _ws_dress, func(c, oo, ff) -> void:
		var m0 := K.pt(oo, ff, 0.38, -0.38, 17)  # antenna mast on the shed roof
		c.line_v(m0, m0 + Vector2(0, -20), Color8(60, 56, 50))
		c.line_v(m0 + Vector2(-3, -16), m0 + Vector2(3, -16), Color8(60, 56, 50))
		G.whip(c, m0 + Vector2(-3, -16), 6, Color8(220, 60, 50))
		G.whip(c, m0 + Vector2(3, -16), 4, Color8(226, 196, 60))
		B.cable(c, m0 + Vector2(0, -12), K.pt(oo, ff, -0.6, -0.2, 12), 2.0)
		var hv := K.pt(oo, ff, 0.05, 0.25, 2.2)  # test flight over the yard
		c.ellipse(hv.x, hv.y, 3.5, 1.4, Color(0, 0, 0, 0.28))
		_fpv(c, hv + Vector2(0, -18), true, 1)
		var rc := K.pt(oo, ff, 0.18, -0.22, 17.5)  # painted quadcopter emblem on the shed roof
		var mk := K.pal("b", "mark")
		for dv in [Vector2(-0.22, -0.22), Vector2(0.22, -0.22), Vector2(0.22, 0.22), Vector2(-0.22, 0.22)]:
			var e := K.pt(oo, ff, 0.18 + dv.x, -0.22 + dv.y, 17.5)
			c.line_v(rc, e, mk)
			c.ellipse(e.x, e.y, 3.6, 1.8, Color(mk.r, mk.g, mk.b, 0.85))
			c.ellipse(e.x, e.y, 2.2, 1.0, FB.IRON)
		c.rect(int(rc.x) - 2, int(rc.y) - 1, 5, 3, mk)
		var lp := K.pt(oo, ff, -0.1, 0.3, 15)
		B.lamp(c, lp + Vector2(0, -2)))


static func _ws_dress(cv, o: Vector2, f: int, p: Array, r: Dictionary) -> void:
	match String(p[7]):
		"p_bench":
			var col: Color = p[6]
			for su in [-0.8, 0.8]:
				for sv in [-0.6, 0.6]:
					var a := K.pt(o, f, float(p[0]) + float(p[3]) * su, float(p[1]) + float(p[4]) * sv, 2)
					cv.line_v(a, a + Vector2(0, -4), P.mul(col, 0.6))
			var c2 := K.wp(f, p[0], p[1])
			var t: Dictionary = P.box(cv, o, Vector3(c2.x, c2.y, 6), p[3], p[4], 1.5, K.rot(f), col, 0.1, 1201)
			B.edges(cv, t, col)
			for i in 3:  # FPV frames being soldered on the bench, a soldering lamp
				var q: Vector2 = t.top[0].lerp(t.top[1], 0.2 + i * 0.3).lerp(t.top[3].lerp(t.top[2], 0.2 + i * 0.3), 0.5)
				_fpv(cv, q, false, i)
			var lq: Vector2 = t.top[1].lerp(t.top[2], 0.5)
			cv.px(int(lq.x), int(lq.y) - 2, Color8(255, 220, 120))
		"crate":
			for sd in r.sides:
				cv.line_v(sd.quad[0], sd.quad[2], P.mul(p[6], 0.72))


# ================================================================ squads (G5 figure kit)
const JAM_FR := ["idle", "walk_a", "walk_b", "fire", "jam", "wounded"]
const AA_FR := ["idle", "walk_a", "walk_b", "fire", "wounded"]


## One figure plus an outlined overlay (pack or gun) on a 24x26 figure canvas. over(pc, tx, ty, d) draws
## the overlay; it sits in front of the torso when `front_facing` matches the facing. after(m, tx, ty, d)
## draws un-outlined extras (whips, flashes).
static func _compose(m, k: int, pose: String, st: Dictionary, over: Callable, front_facing: bool, after: Callable) -> void:
	var d := L.sd(k)
	var away := d.y < -0.2
	var low := 2 if pose.begins_with("crouch") else 0
	var bob := -1 if pose == "walk_a" else 0
	var ty := 10 + bob + low
	var tx := 10 + (int(d.x) if low > 0 else 0)
	var a = P.Canvas.new(24, 26)
	FIG.draw(a, k, pose, st)
	var pk = P.Canvas.new(24, 26)
	over.call(pk, tx, ty, d)
	pk.outline(OUTL)
	var in_front: bool = (not away) if front_facing else away
	if in_front:
		SL.stamp(m, a, 0, 0)
		SL.stamp(m, pk, 0, 0)
	else:
		SL.stamp(m, pk, 0, 0)
		SL.stamp(m, a, 0, 0)
	if after.is_valid():
		after.call(m, tx, ty, d)


static func _pose(fn: String, i: int) -> String:
	match fn:
		"walk_a":
			return "walk_a" if i % 2 == 0 else "walk_b"
		"walk_b":
			return "walk_b" if i % 2 == 0 else "walk_a"
		"fire":
			return "aim"
		"jam":
			return "crouch"
	return "stand"


# ---------------------------------------------------------------- b_jammer_team
static func jammer_team(cv, k: int, f: int, alive: int) -> void:
	var fn: String = JAM_FR[f]
	var styles := [SQ.m(BS, {"weapon": "smg", "head": "cap_b", "belt": BI.RUST}), SQ.m(BS, {"weapon": "pistol"})]
	if fn == "wounded":
		SQ.std(cv, k, fn, 2, alive, styles)
		return
	var jam := fn == "jam"
	SL.formation(cv, k, 0, 2, alive, func(c, kk: int, _f: int, i: int) -> void:
		_compose(c, kk, _pose(fn, i), SQ.m(styles[i], {"fire": fn == "fire"}),
			func(pc, tx: int, ty: int, d: Vector2) -> void: _jam_pack(pc, tx, ty, d), false,
			func(mc, tx: int, ty: int, d: Vector2) -> void: _jam_whips(mc, tx, ty, d, jam, i)))
	if jam:
		for i in mini(alive, 2):
			var s: Vector2i = SL.SLOTS[2][i]
			var p := SQ.PIV + Vector2(s) + Vector2(0, -9)
			G.pulse(cv, p, 9.0 + i * 2.0, AMBER)


static func _jam_pack(pc, tx: int, ty: int, d: Vector2) -> void:
	var bx := int(tx + 2 - d.x * 3.0) - 2
	pc.rect(bx - 1, ty - 1, 6, 6, PACK)
	pc.rect(bx - 1, ty - 1, 6, 1, P.mul(PACK, 1.3))
	pc.rect(bx, ty + 3, 2, 2, V.RUST)              # rust patch
	pc.px(bx + 3, ty + 1, Color8(200, 170, 80))     # dial
	pc.px(bx + 3, ty + 3, Color8(60, 200, 90))      # power lamp


static func _jam_whips(m, tx: int, ty: int, d: Vector2, jam: bool, i: int) -> void:
	var bx := int(tx + 2 - d.x * 3.0) - 2
	var dk := Color8(34, 34, 32)
	var b1 := Vector2(bx, ty - 2)
	var t1 := b1 + Vector2(-2.0 - d.x, -9.0 if not jam else -8.0)
	var b2 := Vector2(bx + 4, ty - 2)
	var t2 := b2 + Vector2(2.0, -7.0)
	m.line_v(b1, t1, dk)
	m.line_v(b2, t2, dk)
	m.line_v(Vector2(bx + 2, ty - 2), Vector2(bx + 2, ty - 4), dk)
	m.px(bx + 2, ty - 5, Color8(150, 150, 140))
	var tipc := AMBER if jam else Color8(220, 60, 50)
	m.px(int(t1.x), int(t1.y), tipc)
	m.px(int(t2.x), int(t2.y), Color8(226, 196, 60) if not jam else AMBER)
	if jam and (i % 2 == 0):
		m.px(int(t1.x) - 1, int(t1.y) - 1, Color(1, 0.9, 0.6, 0.7))
		m.px(int(t2.x) + 1, int(t2.y) - 1, Color(1, 0.9, 0.6, 0.7))


# ---------------------------------------------------------------- b_scrap_aa
static func scrap_aa(cv, k: int, f: int, alive: int) -> void:
	var fn: String = AA_FR[f]
	var base := SQ.m(BS, {"weapon": "none", "back": "ammo"})
	var styles := [SQ.m(base, {"head": "helm_b"}), SQ.m(base, {"head": "cap_b", "back": "pack"}), SQ.m(base, {"coat": BI.COAT, "belt": BI.RUST})]
	if fn == "wounded":
		SQ.std(cv, k, fn, 3, alive, styles)
		return
	var fire := fn == "fire"
	SL.formation(cv, k, 0, 3, alive, func(c, kk: int, _f: int, i: int) -> void:
		_compose(c, kk, _pose(fn, i), styles[i],
			func(pc, tx: int, ty: int, d: Vector2) -> void: _shotgun(pc, tx, ty, d, fire), true, Callable()))
	if fire:
		var d := L.sd(k)
		var slots: Array = SL.SLOTS[3]
		for i in mini(alive, 3):
			var s: Vector2i = slots[i]
			var tipf: Vector2 = _gun_tip(10, 10, d, true)
			var tp := SQ.PIV + Vector2(s) - Vector2(12, 21) + tipf
			var dirv := (tipf - _gun_sh(10, 10, d, true)).normalized()
			var pr := Vector2(-dirv.y, dirv.x)
			for j in 16:
				var t := P.hn(j, i, 1301)
				var q := tp + dirv * (2.0 + t * 10.0) + pr * (P.hn(j, i, 1302) - 0.5) * (2.0 + t * 8.0)
				cv.px(int(q.x), int(q.y), Color(0.96, 0.9, 0.62, 0.85 - t * 0.4))
			L.flash(cv, tp, 1.0)
			L.puff(cv, tp + dirv * 4.0, 2.4, 0.4)


static func _gun_sh(tx: int, ty: int, d: Vector2, aim: bool) -> Vector2:
	return Vector2(tx + 2 + d.x * 1.5, ty + (1 if aim else 3))


static func _gun_tip(tx: int, ty: int, d: Vector2, aim: bool) -> Vector2:
	var sh := _gun_sh(tx, ty, d, aim)
	return sh + (Vector2(d.x * 4.5, d.y * 1.5 - 6.5) if aim else Vector2(d.x * 3.5, -4.5))


static func _shotgun(pc, tx: int, ty: int, d: Vector2, aim: bool) -> void:
	var sh := _gun_sh(tx, ty, d, aim)
	var tip := _gun_tip(tx, ty, d, aim)
	var dirv := (tip - sh).normalized()
	pc.line_v(sh - dirv * 3.0, sh, BI.WOODSTOCK)
	pc.line_v(sh, tip, BI.GUN)
	pc.line_v(sh + Vector2(1, 0), tip + Vector2(1, 0), P.mul(BI.GUN, 1.35))
	pc.rect(int(tip.x), int(tip.y) - 1, 2, 2, Color8(120, 118, 110))  # flared muzzle
	var dm := sh + dirv * 1.5
	pc.rect(int(dm.x), int(dm.y) + 1, 2, 2, V.RUST)  # scrap drum magazine


# ================================================================ Machine building renderer
## Part list [kind ("hex"|"box"|other = drawn by dress), u, v, z, r|hx, sq|hy, hz, colour, role] in the local
## frame; finished look of faction_m_bld.draw. dress(cv, o, f, p_world, r) -> bool: true = fully handled.
static func _mdraw(cv, o: Vector2, f: int, size: int, ps: Array, dress: Callable, post: Callable) -> void:
	var half := size * 0.5 - 0.05
	var rt := K.rot(f)
	var items: Array = []
	for p in ps:
		var c2 := K.wp(f, p[1], p[2])
		var pw: Array = p.duplicate()
		pw[1] = c2.x
		pw[2] = c2.y
		items.append(pw)
	items.sort_custom(func(a, b):
		var la := 1 if float(a[3]) > 4.0 else 0
		var lb := 1 if float(b[3]) > 4.0 else 0
		if la != lb:
			return la < lb
		return float(a[1]) + float(a[2]) + float(a[3]) * 0.001 < float(b[1]) + float(b[2]) + float(b[3]) * 0.001)
	for p in items:
		var c := Vector3(p[1], p[2], p[3])
		if p[0] == "box":
			P.box_shadow(cv, o, c, p[4], p[5], p[6], rt)
		else:
			M.hex_shadow(cv, o, c, p[4], p[6], 0.0, 1.0 if p[0] != "hex" else float(p[5]))
	cv.flush_shadow()
	var slab: Dictionary = P.box(cv, o, Vector3(0, 0, 0), half, half, 2.0, 0.0, M.SLAB, 0.1, 5)
	BD.slab_pattern(cv, slab.top, size, false)
	B.edges(cv, slab, M.SLAB)
	for p in items:
		var c := Vector3(p[1], p[2], p[3])
		var col: Color = p[7]
		var r: Dictionary = {}
		if p[0] == "hex":
			r = M.hexp(cv, o, c, p[4], p[6], 0.0, col, 50 + int(float(p[4]) * 10), null, p[5])
		elif p[0] == "box":
			r = P.box(cv, o, c, p[4], p[5], p[6], rt, col, 0.07, 50 + int(float(p[4]) * 10))
		else:
			dress.call(cv, o, f, p, {})
			continue
		B.wall_ao(cv, r, 0.3 if float(p[3]) <= 4.0 else 0.18)
		var done := false
		if dress.is_valid():
			done = bool(dress.call(cv, o, f, p, r))
		if not done:
			BD.dress(cv, o, "", [p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8]], r)
	if post.is_valid():
		post.call(cv, o, f)
	BD.beacon(cv, o, half, false)


static func _cyan(a: float) -> Color:
	return Color(M.CYAN.r, M.CYAN.g, M.CYAN.b, a)


static func _hot(a: float) -> Color:
	return Color(M.CYAN_HOT.r, M.CYAN_HOT.g, M.CYAN_HOT.b, a)


# ================================================================ m_hive_node
static func hive_node(cv, o: Vector2, f: int) -> void:
	var ps := [
		["hex", 0.0, 0.0, 2, 0.72, 1.0, 7, M.GRAPH, "base"],
		["hex", 0.0, 0.0, 9, 0.5, 1.0, 17, M.PANEL, "hive"],
		["hex", 0.0, 0.0, 26, 0.32, 1.0, 7, M.GRAPH_D, "hcrown"],
		["hex", 0.66, -0.58, 2, 0.17, 1.0, 13, M.PANEL, "cell"],
		["hex", -0.6, 0.64, 2, 0.15, 1.0, 10, M.PANEL, "cell"],
		["hex", 0.64, 0.62, 2, 0.2, 1.0, 2, M.PANEL_D, "pad"],
	]
	_mdraw(cv, o, f, 2, ps, _hive_dress, func(c, oo, _ff) -> void:
		var top := P.proj(oo, Vector3(0, 0, 33))
		for i in 5:  # micro-drones leaving the crown ports
			var dz: Array = [[0.3, -0.25, 44], [-0.32, 0.18, 50], [0.18, 0.42, 38], [-0.5, -0.4, 34], [0.02, -0.04, 58]][i]
			GM._micro(c, oo, 0.6 * i, Vector3(dz[0], dz[1], dz[2]), i % 3, i)
			var tp := P.proj(oo, Vector3(dz[0], dz[1], dz[2] + 2.5))
			c.ellipse(tp.x, tp.y, 3.0, 1.2, Color(0.78, 0.82, 0.84, 0.22))
		c.ellipse(top.x, top.y, 5.0, 2.4, _cyan(0.25)))


static func _hive_dress(cv, o: Vector2, f: int, p: Array, r: Dictionary) -> bool:
	match String(p[8]):
		"hive":
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				for row in 3:
					var vv := 0.18 + row * 0.3
					for i in 3:
						var u := 0.2 + i * 0.3 + (0.15 if row % 2 == 1 else 0.0)
						if u > 0.92:
							continue
						var cc: Vector2 = q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), vv)
						var hexp := PackedVector2Array()
						for j in 6:
							var a := j * PI / 3.0
							hexp.append(cc + Vector2(cos(a) * 2.6, sin(a) * 2.0))
						cv.poly(hexp, Color8(30, 32, 35))
						cv.px(int(cc.x), int(cc.y), M.CYAN if (i + row) % 2 == 0 else M.TEAL)
				M.seam(cv, q, 0.97)
				M.team_panel(cv, q, 0.06, 0.02, 0.94, 0.08, 0.7)
			M.rims(cv, r, p[7])
			return true
		"hcrown":
			for sd in r.sides:
				M.seam(cv, sd.quad, 0.5)
			M.rims(cv, r, p[7])
			var t: PackedVector2Array = r.top
			var c: Vector2 = (t[0] + t[3]) * 0.5
			for j in 6:  # launch ports ringed around the crown
				var a := j * PI / 3.0
				var pp := c + Vector2(cos(a) * 7.0, sin(a) * 3.4)
				cv.rect(int(pp.x) - 1, int(pp.y), 3, 1, Color8(24, 26, 28))
				cv.px(int(pp.x), int(pp.y), M.CYAN)
			M.eye(cv, c, true)
			return true
		"cell":
			for sd in r.sides:
				M.team_panel(cv, sd.quad, 0.1, 0.55, 0.9, 0.75)
				M.seam(cv, sd.quad, 0.3)
			M.rims(cv, r, p[7])
			M.hex_plate(cv, r.top, 0.5, 0.5, 2.5, M.GRAPH_D, true)
			return true
	return false


# ================================================================ m_nanite_forge
static func nanite_forge(cv, o: Vector2, f: int) -> void:
	var ps := [
		["hex", 0.0, 0.0, 2, 0.74, 1.0, 6, M.GRAPH, "base"],
		["dome", 0.0, 0.0, 8, 0.5, 1.0, 26, M.PANEL, "dome"],
		["hex", -0.66, 0.56, 2, 0.15, 1.0, 14, M.PANEL, "tank"],
		["hex", 0.6, -0.62, 2, 0.13, 1.0, 20, M.PANEL, "coil"],
		["hex", 0.66, 0.58, 2, 0.12, 1.0, 6, M.GRAPH_D, "vent"],
	]
	_mdraw(cv, o, f, 2, ps, func(c, oo, ff, p, r) -> bool:
		if String(p[8]) == "dome":
			_dome(c, oo, Vector3(p[1], p[2], p[3]), p[4], p[6], p[7])
			return true
		return false, func(c, oo, _ff) -> void:
		var b := P.proj(oo, Vector3(0, 0, 8))
		var rx := 0.5 * 45.25
		for j in 110:  # nanite cloud swirling over the dome (translucent, below outline alpha)
			var a := j * 0.77 + P.hn(j, 1, 1401) * 0.6
			var rad := rx * (0.55 + 0.75 * P.hn(j, 2, 1401))
			var hy := 26.0 * (0.75 + 0.9 * P.hn(j, 3, 1401))
			var q := Vector2(b.x + cos(a) * rad, b.y - hy + sin(a) * rad * 0.32)
			var hot := P.hn(j, 4, 1401) > 0.75
			c.px(int(q.x), int(q.y), _hot(0.55) if hot else Color(0.62, 0.86, 0.86, 0.42))
		c.ellipse(b.x, b.y - 40, 20.0, 7.0, _cyan(0.1))
		c.ellipse(b.x, b.y - 36, 12.0, 4.0, _cyan(0.12)))


## Ribbed hemispherical dome built from stacked shaded ellipse layers (top layers overwrite lower ones).
static func _dome(cv, o: Vector2, c: Vector3, r: float, hz: float, col: Color) -> void:
	var b := P.proj(o, c)
	var rx := r * 45.25
	var n := int(hz)
	for i in n + 1:
		var t := float(i) / n
		var rr := rx * sqrt(maxf(0.0, 1.0 - t * t))
		if rr < 0.8:
			continue
		var cy := b.y - t * hz
		for y in range(int(floor(cy - rr * 0.5)), int(ceil(cy + rr * 0.5)) + 1):
			for x in range(int(floor(b.x - rr)), int(ceil(b.x + rr)) + 1):
				var dx := (x + 0.5 - b.x) / rr
				var dy := (y + 0.5 - cy) / (rr * 0.5)
				if dx * dx + dy * dy > 1.0:
					continue
				var az := atan2(dy, dx)
				var k := 0.8 - 0.24 * dx + 0.28 * t - 0.06 * dy
				var cc: Color = P.mul(col, k)
				var rib := fposmod(az + PI, PI / 4.0) < 0.13
				if rib and t < 0.9:
					cc = P.mul(M.GRAPH, k * 1.05)
				if absf(t - 0.42) < 0.03 and dy > 0.0:
					cc = M.CYAN
				if t > 0.9:
					cc = M.GRAPH_D if dx * dx + dy * dy > 0.3 else M.CYAN_HOT
				if t < 0.12 and dy > 0.0 and not rib:
					cv.team = true
					cv.px(x, y, Color(0.72 * k, 0.72 * k, 0.72 * k))
					cv.team = false
					continue
				cv.px(x, y, cc)


# ================================================================ m_overmind
static func overmind(cv, o: Vector2, f: int) -> void:
	var ps := [
		["hex", 0.0, 0.0, 2, 0.66, 1.0, 10, M.GRAPH, "main"],
		["hex", 0.0, 0.0, 12, 0.38, 1.0, 14, M.PANEL, "tower"],
		["hex", 0.0, 0.0, 26, 0.23, 1.0, 24, M.GRAPH, "spire"],
		["hex", 0.0, 0.0, 50, 0.14, 1.0, 22, M.PANEL, "spire"],
		["hex", 0.0, 0.0, 72, 0.08, 1.0, 10, M.GRAPH_D, "crown"],
		["box", 0.72, -0.72, 2, 0.06, 0.06, 30, M.GRAPH_D, "pylon"],
		["box", -0.72, 0.72, 2, 0.06, 0.06, 30, M.GRAPH_D, "pylon"],
		["box", 0.7, 0.45, 2, 0.12, 0.3, 4, M.GRAPH_D, "belt"],
	]
	_mdraw(cv, o, f, 2, ps, func(c, oo, ff, p, r) -> bool:
		match String(p[8]):
			"spire":
				for sd in r.sides:
					M.seam(c, sd.quad, 0.25)
					M.seam(c, sd.quad, 0.75)
					M.joints(c, sd.quad, [0.5], p[7])
				M.rims(c, r, p[7])
				return true
			"pylon":
				M.rims(c, r, p[7])
				var t: PackedVector2Array = r.top
				M.eye(c, t[0].lerp(t[2], 0.5) + Vector2(0, -1), false)
				return true
		return false, func(c, oo, _ff) -> void:
		var cx := P.proj(oo, Vector3(0, 0, 0)).x
		for hz in [44.0, 66.0]:  # halo rings around the spire (front half only where the spire hides the back)
			var cc := P.proj(oo, Vector3(0, 0, hz))
			var rr := 17.0 if hz < 50 else 12.0
			var sw := 9.0 if hz < 50 else 6.0
			for i in 48:
				var a := i * TAU / 48.0
				var q := cc + Vector2(cos(a) * rr, sin(a) * rr * 0.4)
				if sin(a) < 0.0 and absf(q.x - cx) < sw:
					continue
				c.px(int(q.x), int(q.y), _cyan(0.55) if sin(a) >= 0.0 else _cyan(0.32))
		var tp := P.proj(oo, Vector3(0, 0, 84))
		for y in range(0, int(tp.y)):  # uplink beam
			var fade := 0.3 + 0.25 * float(y) / maxf(1.0, tp.y)
			c.px(int(tp.x), y, _hot(fade))
			c.px(int(tp.x) - 1, y, _cyan(fade * 0.5))
			c.px(int(tp.x) + 1, y, _cyan(fade * 0.5))
		c.ellipse(tp.x, tp.y, 4.0, 2.5, _cyan(0.35))
		for s in [-1.0, 1.0]:  # pylon -> spire power arcs
			var a2 := P.proj(oo, Vector3(0.72 * s, -0.72 * s, 32))
			B.cable(c, a2, P.proj(oo, Vector3(0, 0, 40)), 1.0, _cyan(0.5)))


# ================================================================ m_relay_lattice
const RELAY := [[-0.22, -0.18], [0.24, -0.06], [-0.04, 0.24]]


static func relay_lattice(cv, o: Vector2, f: int) -> void:
	var ps: Array = []
	for pl in RELAY:
		ps.append(["hex", pl[0], pl[1], 2, 0.1, 1.0, 4, M.GRAPH, "base"])
		ps.append(["box", pl[0], pl[1], 6, 0.03, 0.03, 18, M.GRAPH_D, "mast"])
		ps.append(["hex", pl[0], pl[1], 24, 0.065, 1.0, 4, M.PANEL, "phead"])
	_mdraw(cv, o, f, 1, ps, func(c, oo, ff, p, r) -> bool:
		match String(p[8]):
			"phead":
				for sd in r.sides:
					M.seam(c, sd.quad, 0.5)
				c.team = true
				c.poly(P.sub(r.top, 0.2, 0.2, 0.8, 0.8), Color(0.75, 0.75, 0.75))
				c.team = false
				M.eye(c, P.proj(oo, Vector3(p[1], p[2], 30)), false)
				return true
			"mast":
				for sd in r.sides:
					c.px(int(sd.quad[3].x), int(sd.quad[3].y) + 4, M.CYAN)
				return true
		return false, func(c, oo, ff) -> void:
		var heads: Array = []
		for pl in RELAY:
			heads.append(K.pt(oo, ff, pl[0], pl[1], 31))
		for i in 3:
			var a: Vector2 = heads[i]
			var b: Vector2 = heads[(i + 1) % 3]
			c.line_v(a + Vector2(0, 1), b + Vector2(0, 1), _cyan(0.3))
			c.line_v(a, b, _hot(0.55))
		var ends := [[-0.48, -0.42], [0.48, -0.3]]  # chain continuing to the next lattice off-plate
		for i in 2:
			var a: Vector2 = heads[i]
			var e: Array = ends[i]
			var b := K.pt(oo, ff, e[0], e[1], 31)
			for j in 8:
				var q := a.lerp(b, j / 8.0)
				c.px(int(q.x), int(q.y), _hot(0.5 - j * 0.05)))


# ================================================================ m_swarm_queen
static func swarm_queen(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	if wreck:
		_queen_wreck(cv, rot, o)
		return
	var pitch := 3.0 if f == 1 else 0.0
	var arms: Array = []
	for i in 6:
		var a := rot + i * PI / 3.0 + PI / 6.0
		var dz := -pitch * cos(a - rot)
		var tip := Vector3(cos(a) * 0.42, sin(a) * 0.42, 9.0 + dz)
		arms.append([tip.x + tip.y, tip, a])
	arms.sort_custom(func(x, y): return x[0] < y[0])
	var back: Array = []
	var front: Array = []
	for it in arms:
		(back if float(it[0]) < 0.0 else front).append(it)
	for it in back:
		_duct(cv, o, it[1], f, int(it[2] * 10.0))
	M.hexp(cv, o, Vector3(0, 0, 0), 0.11, 4.0, rot, M.GRAPH_D, 1501)  # belly bay pod
	var hull: Dictionary = M.hexp(cv, o, Vector3(0, 0, 4), 0.21, 6.0, rot, M.GRAPH, 1502)
	for sd in hull.sides:
		M.seam(cv, sd.quad, 0.35)
		M.joints(cv, sd.quad, [0.5], M.GRAPH)
	M.rims(cv, hull, M.GRAPH)
	var deck: Dictionary = M.hexp(cv, o, Vector3(0, 0, 10), 0.15, 3.5, rot, M.PANEL, 1503)
	for sd in deck.sides:
		M.team_panel(cv, sd.quad, 0.1, 0.15, 0.9, 0.85)
	M.hex_plate(cv, deck.top, 0.5, 0.5, 4.0, M.GRAPH_D, false)
	M.eye(cv, P.proj(o, Vector3(0, 0, 14)), true)
	var fe := P.proj(o, M.w(rot, 0.2, 0.0, 7))
	cv.px(int(fe.x), int(fe.y), M.CYAN_HOT)  # forward sensor
	for it in front:
		_duct(cv, o, it[1], f, int(it[2] * 10.0))
	if f == 2:  # micro-drones released from the belly bay
		for i in 3:
			var dz: float = [-7.0, -13.0, -19.0][i]
			GM._micro(cv, o, rot, M.w(rot, -0.05 + i * 0.07, (i - 1) * 0.12, dz), 2, i)
	cv.outline(MOUTL)
	for it in arms:  # rotor blur after the outline
		var tp := P.proj(o, it[1] + Vector3(0, 0, 1.5))
		cv.ellipse(tp.x, tp.y, 5.2, 2.2, Color(0.8, 0.85, 0.86, 0.28))
		var ph := (f + int(it[2] * 3.0)) % 2
		cv.line_v(tp + Vector2(-4, ph), tp + Vector2(4, -ph), Color(0.92, 0.94, 0.94, 0.45))
	var bay := P.proj(o, Vector3(0, 0, -0.5))
	cv.ellipse(bay.x, bay.y + 1, 3.5, 1.6, _cyan(0.5 if f == 2 else 0.3))
	if f == 2:
		for i in 3:
			var dz: float = [-7.0, -13.0, -19.0][i]
			var p := P.proj(o, M.w(rot, -0.05 + i * 0.07, (i - 1) * 0.12, dz + 3.0))
			cv.line_v(p, p + Vector2(0, -5), _cyan(0.35))


## Ducted rotor at world point t: graphite ring, inner fan, cyan rim, short arm back to the hull.
static func _duct(cv, o: Vector2, t: Vector3, f: int, s: int) -> void:
	var p := P.proj(o, t)
	var h := P.proj(o, Vector3(t.x * 0.45, t.y * 0.45, t.z - 1.0))
	cv.line_v(h, p, M.GRAPH)
	cv.line_v(h + Vector2(0, 1), p + Vector2(0, 1), M.JOINT)
	cv.ellipse(p.x, p.y + 1, 6.4, 3.3, M.GRAPH_D)
	cv.ellipse(p.x, p.y, 6.0, 2.8, M.GRAPH)
	cv.ellipse(p.x, p.y, 4.6, 2.0, Color8(36, 39, 43))
	cv.ellipse(p.x, p.y, 3.4, 1.4, Color8(96, 104, 108))
	for i in 9:
		var a := i * PI / 8.0
		cv.px(int(p.x + cos(a) * 5.6), int(p.y + 0.5 + sin(a) * 2.6), M.CYAN if i % 2 == 0 else M.TEAL)
	cv.px(int(p.x), int(p.y), M.JOINT)


static func _queen_wreck(cv, rot: float, o: Vector2) -> void:
	cv.ellipse(o.x, o.y + 1, 13.0, 4.5, Color8(40, 36, 32))
	var hull: Dictionary = M.hexp(cv, o, Vector3(0, 0, 0), 0.2, 5.0, rot + 0.4, M.DEAD, 1511)
	for sd in hull.sides:
		M.seam(cv, sd.quad, 0.4, true)
	for i in 4:
		var a := rot + i * 1.4 + 0.3
		var t := P.proj(o, Vector3(cos(a) * 0.36, sin(a) * 0.36, 0))
		cv.line_v(P.proj(o, Vector3(cos(a) * 0.15, sin(a) * 0.15, 2)), t, M.DEAD_D)
		if i % 2 == 0:
			cv.ellipse(t.x, t.y, 5.0, 2.2, M.DEAD_D)
			cv.ellipse(t.x, t.y, 3.2, 1.2, M.DEAD)
	cv.outline(MOUTL)
	L.puff(cv, o + Vector2(2, -8), 3.0, 0.35, Color(0.3, 0.29, 0.27))


# ================================================================ m_mimic_drone
static func mimic(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var k := _kk(rot)
	var d := L.sd(k)
	var r := L.sd((k + 2) % 8)
	var c := o + Vector2(0, -2)
	if wreck:
		c += Vector2(0, 4)
		cv.ellipse(c.x, c.y, 5.5, 2.2, Color8(40, 36, 32))
		cv.ellipse(c.x, c.y - 1, 2.4, 1.4, M.DEAD)
		for i in 3:
			cv.line_v(c, c + d * (2.0 - i * 2.0) + r * (3.0 - i * 2.5), M.DEAD_D)
		cv.outline(MOUTL)
		L.puff(cv, c + Vector2(1, -3), 2.0, 0.35, Color(0.3, 0.29, 0.27))
		return
	var disguised := f <= 1
	var pitch := 0.0 if f == 0 else (1.5 if f == 1 else 3.5)
	if f == 3:
		c += Vector2(0, 1)
		for i in 3:
			var off := r * float(i - 1) * 3.0
			cv.line_v(c - d * 4.0 + off + Vector2(0, -3), c - d * 10.0 + off + Vector2(0, -9), Color(0.92, 0.92, 0.88, 0.45))
	if disguised:
		DR._copter(cv, c, d, r, pitch, f, "a", "recon", k)  # the Human A recon quad it impersonates
		for x in range(int(c.x) - 1, int(c.x) + 2):  # hologram tear: graphite hull showing through
			for y in range(int(c.y) - 2, int(c.y) + 2):
				cv.px(x, y, M.GRAPH)
		cv.px(int(c.x), int(c.y) - 1, M.CYAN)
		cv.px(int(c.x + d.x * 2.0), int(c.y + d.y * 2.0), M.CYAN_HOT)
	else:
		_mimic_true(cv, c, d, r, pitch, f, k)
	cv.outline(MOUTL)
	if disguised:  # scan-line flicker over the projected skin
		for y in range(int(c.y) - 8, int(c.y) + 6):
			if (y + f) % 3 != 0:
				continue
			for x in range(int(c.x) - 10, int(c.x) + 11):
				if cv.get_px(x, y).a > 0.6:
					cv.px(x, y, _cyan(0.24))
		var g := c + r * 7.0 + Vector2(0, -1)
		cv.line_v(g, g + Vector2(3, 0), _cyan(0.5))
		cv.px(int(c.x - r.x * 8.0), int(c.y - r.y * 8.0) + 1, _hot(0.5))
	elif f == 2:
		var n := c + d * 6.0 + Vector2(0, 3)
		L.flash(cv, n, 1.4)
		L.puff(cv, n + Vector2(1, -2), 2.5, 0.45)
		for i in 4:  # shed hologram fragments
			var q := c + r * (float(i) - 1.5) * 3.0 + Vector2(0, -4 - i)
			cv.px(int(q.x), int(q.y), Color(0.85, 0.9, 0.9, 0.5))


static func _mimic_true(cv, c: Vector2, d: Vector2, r: Vector2, pitch: float, f: int, k: int) -> void:
	var tips: Array = []
	for i in 4:
		var ang := (float(i) + 0.5) * TAU / 4.0
		tips.append(c + d * cos(ang) * 6.0 + r * sin(ang) * 6.0 + Vector2(0, pitch * cos(ang) * 0.5))
	var back: Array = []
	var front: Array = []
	for t: Vector2 in tips:
		(back if t.y < c.y else front).append(t)
	for t: Vector2 in back:
		_mpod(cv, c, t, f, k)
	var hexp := PackedVector2Array()
	for j in 6:
		var a := j * PI / 3.0
		hexp.append(c + Vector2(cos(a) * 3.2, sin(a) * 2.0))
	cv.poly(hexp, M.GRAPH)
	cv.rect(int(c.x) - 1, int(c.y) - 2, 3, 1, M.PANEL)
	cv.line_v(c + Vector2(-3, 1), c + Vector2(3, 1), M.CYAN)
	cv.team = true
	cv.px(int(c.x - d.x * 2.0), int(c.y - d.y * 2.0), Color(0.75, 0.75, 0.75))
	cv.team = false
	M.eye(cv, c + d * 2.5 + Vector2(0, -1), f == 3)
	for t: Vector2 in front:
		_mpod(cv, c, t, f, k)


static func _mpod(cv, c: Vector2, t: Vector2, f: int, k: int) -> void:
	cv.line_v(c, t, M.JOINT)
	cv.rect(int(t.x) - 1, int(t.y) - 1, 3, 2, M.GRAPH_D)
	cv.px(int(t.x), int(t.y), M.CYAN)
	var ph := (f + k) % 2
	cv.ellipse(t.x, t.y - 1, 2.6, 1.0, Color(0.84, 0.86, 0.86, 0.35))
	cv.line_v(t + Vector2(-2, -1 + ph), t + Vector2(2, -1 - ph), Color(0.9, 0.9, 0.9, 0.5))


# ================================================================ b_rail_yard
static func _track(cv, o: Vector2, f: int, v: float, u0: float, u1: float) -> void:
	K.gquad(cv, o, f, u0, v - 0.13, u1, v + 0.13, 2.1, BALLAST)
	var n := int((u1 - u0) / 0.11)
	for i in n:
		var u := u0 + 0.05 + i * 0.11
		K.gline(cv, o, f, u, v - 0.1, u, v + 0.1, 2.2, TIE)
	for s in [-1.0, 1.0]:
		K.gline(cv, o, f, u0, v + 0.055 * s, u1, v + 0.055 * s, 2.3, Color8(60, 58, 54))
		K.gline(cv, o, f, u0, v + 0.055 * s, u1, v + 0.055 * s, 3.3, STEEL_LIT)


static func rail_yard(cv, o: Vector2, f: int) -> void:
	var ps := [
		[-0.4, 0.2, 2, 0.82, 0.42, 22, FB.BRICK, "eshed"],
		[-0.4, 0.2, 24, 0.84, 0.45, 12, FB.IRON, "tent"],
		[-1.05, -0.6, 2, 0.08, 0.08, 46, FB.BRICK_D, "stack"],
		[1.0, -0.9, 2, 0.2, 0.2, 38, FB.IRON, "p_wtower"],
		[0.78, -0.3, 2, 0.32, 0.12, 5, TIE, "sleepers"],
		[0.1, -0.95, 2, 0.5, 0.07, 3, FB.STEEL, "railstack"],
		[0.42, 0.9, 2, 0.46, 0.12, 2.5, V.TRACK, "box"],
		[0.42, 0.9, 4.5, 0.5, 0.16, 9, V.HULL, "wagon"],
		[-0.95, -1.05, 2, 0.3, 0.26, 8, FB.SLAG, "scrap"],
	]
	_bdraw(cv, o, f, 3, ps, "b_rail_yard", func(c, oo, ff) -> void:
		_track(c, oo, ff, 0.2, -1.62, 1.62)
		_track(c, oo, ff, 0.9, -1.0, 1.62), _ry_dress, func(c, oo, ff) -> void:
		var sp := K.pt(oo, ff, 1.3, 0.5, 2)  # signal post
		c.line_v(sp, sp + Vector2(0, -18), Color8(60, 56, 50))
		c.rect(int(sp.x) - 1, int(sp.y) - 21, 3, 5, Color8(40, 38, 34))
		c.px(int(sp.x), int(sp.y) - 20, Color8(230, 60, 40))
		c.px(int(sp.x), int(sp.y) - 18, Color8(70, 200, 90))
		var w := K.pt(oo, ff, 0.3, 0.75, 16)  # welding sparks on the wagon
		for i in 5:
			c.px(int(w.x) + P.hi(i, 1, 1601, 7) - 3, int(w.y) - P.hi(i, 2, 1601, 4), Color8(255, 230, 140))
		B.lamp(c, K.pt(oo, ff, 0.45, 0.2, 30)))


static func _ry_dress(cv, o: Vector2, f: int, p: Array, r: Dictionary) -> void:
	var col: Color = p[6]
	match String(p[7]):
		"eshed":
			var ax: Vector2 = K.AX[f % 4]
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				R.brick_tex(cv, q, 1611)
				if absf((sd.n as Vector2).dot(ax)) > 0.7:  # gable end: arched track opening
					var op := P.sub(q, 0.3, 0.0, 0.7, 0.72)
					cv.poly(op, Color8(26, 24, 22))
					cv.poly(P.sub(q, 0.36, 0.72, 0.64, 0.8), Color8(26, 24, 22))
					cv.line_v(op[3], op[2], P.mul(col, 1.3))
				else:
					B.window_row(cv, q, 0.45, 0.72, maxi(2, int(q[0].distance_to(q[1]) / 10.0)), Color8(84, 80, 72), 1612, 0.25)
				cv.team = true
				cv.poly(P.sub(q, 0.0, 0.86, 1.0, 0.93), Color(0.7, 0.7, 0.7))
				cv.team = false
		"sleepers":
			for sd in r.sides:
				for vb in [0.33, 0.66]:
					cv.line_v(sd.quad[0].lerp(sd.quad[3], vb), sd.quad[1].lerp(sd.quad[2], vb), P.mul(col, 0.7))
		"railstack":
			for vb in [0.3, 0.6, 0.9]:
				var ln := P.sub(r.top, 0.0, vb, 1.0, vb)
				cv.line_v(ln[0], ln[1], STEEL_LIT)
		"wagon":
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				V.rivets(cv, q, 0.85, 8, col)
				V.streaks(cv, q, 1613)
				if q[0].distance_to(q[1]) > 18.0:
					V.patch(cv, q, 0.62, 0.15, 0.9, 0.6, V.PRIMER, 1614)
					cv.team = true
					cv.poly(P.sub(q, 0.08, 0.35, 0.55, 0.62), Color(0.64, 0.64, 0.64))
					cv.team = false
					for u in [0.15, 0.35, 0.65, 0.85]:
						var wc: Vector2 = q[0].lerp(q[1], u) + Vector2(0, 1)
						cv.ellipse(wc.x, wc.y, 2.0, 1.6, Color8(30, 28, 26))
			cv.poly(P.sub(r.top, 0.05, 0.1, 0.95, 0.9), P.mul(col, 0.55))
		"p_wtower":
			var c2 := K.wp(f, p[0], p[1])
			for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var a := P.proj(o, Vector3(c2.x + s.x * 0.15, c2.y + s.y * 0.15, 2))
				var b := P.proj(o, Vector3(c2.x + s.x * 0.12, c2.y + s.y * 0.12, 24))
				cv.line_v(a, b, Color8(70, 62, 54))
			var x0 := P.proj(o, Vector3(c2.x - 0.14, c2.y + 0.14, 8))
			var x1 := P.proj(o, Vector3(c2.x + 0.14, c2.y + 0.14, 18))
			cv.line_v(x0, x1, Color8(60, 54, 48))
			var top := B.cyl(cv, o, Vector3(c2.x, c2.y, 24), 0.2, 14, FB.RUSTY, 1615, 0.75, 2)
			cv.ellipse(top.x, top.y - 1, 6.0, 2.6, Color8(78, 74, 68))
			cv.px(int(top.x), int(top.y) - 3, Color8(110, 104, 96))
			var sp := P.proj(o, Vector3(c2.x - 0.2, c2.y + 0.1, 30))  # filling spout
			cv.line_v(sp, sp + Vector2(-6, 6), Color8(50, 46, 42))


# ================================================================ b_armored_train
static func _rails(cv, o: Vector2, rot: float, wreck: bool) -> void:
	var ln := 0.9
	var q := PackedVector2Array([D.sp(o, rot, -ln, -0.17, 0), D.sp(o, rot, ln, -0.17, 0), D.sp(o, rot, ln, 0.17, 0), D.sp(o, rot, -ln, 0.17, 0)])
	cv.poly(q, BALLAST, P.speckle(0.28, 1701))
	for i in 18:
		var a := -ln + 0.05 + i * 0.1
		cv.line_v(D.sp(o, rot, a, -0.13, 1), D.sp(o, rot, a, 0.13, 1), TIE)
	for s in [-1.0, 1.0]:
		var bend := 0.04 if wreck and s > 0 else 0.0
		cv.line_v(D.sp(o, rot, -ln, 0.065 * s, 1), D.sp(o, rot, ln, 0.065 * s + bend, 1), Color8(58, 56, 52))
		cv.line_v(D.sp(o, rot, -ln, 0.065 * s, 2), D.sp(o, rot, ln, 0.065 * s + bend, 2), STEEL_LIT)


static func armored_train(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	_rails(cv, o, rot, wreck)
	var lr := rot + (0.14 if wreck else 0.0)
	var cr := rot - (0.1 if wreck else 0.0)
	var loff := 0.07 if wreck else 0.0
	var lc := D.w(rot, 0.4, loff, 0)
	var cc := D.w(rot, -0.42, -loff, 0)
	P.box_shadow(cv, o, lc, 0.32, 0.13, 20.0, lr)
	P.box_shadow(cv, o, cc, 0.3, 0.13, 15.0, cr)
	cv.flush_shadow()
	var info := {}
	if D.faces_cam(rot, 1.0, 0.0):
		_car(cv, o, cc, cr, f, wreck, info)
		_coupler(cv, o, rot, wreck)
		_loco(cv, o, lc, lr, f, wreck, info)
	else:
		_loco(cv, o, lc, lr, f, wreck, info)
		_coupler(cv, o, rot, wreck)
		_car(cv, o, cc, cr, f, wreck, info)
	cv.outline(OUTL)
	if wreck:
		V.soot(cv, P.proj(o, lc + Vector3(0, 0, 14)), 7.0, 1711)
		V.soot(cv, P.proj(o, cc + Vector3(0, 0, 10)), 6.0, 1712)
		L.puff(cv, P.proj(o, lc + Vector3(0, 0, 22)), 3.5, 0.4, Color(0.3, 0.29, 0.27))
		return
	if info.has("stack"):
		R.dark_plume(cv, info.stack, 1713 + f, 6 if f != 1 else 7)
	if f == 2:
		if info.has("gun"):
			L.flash(cv, info.gun, 1.5)
			L.puff(cv, info.gun + Vector2(3, -3), 2.8, 0.5)
		if info.has("flak"):
			var fl: Vector2 = info.flak
			L.flash(cv, fl, 0.9)
			for i in 3:  # tracers and flak bursts overhead
				var t := fl + Vector2(2 + i * 3, -6 - i * 5)
				cv.line_v(t, t + Vector2(1, -3), Color(1.0, 0.86, 0.5, 0.85))
			L.puff(cv, fl + Vector2(9, -20), 2.5, 0.45, Color(0.28, 0.27, 0.25))


static func _coupler(cv, o: Vector2, rot: float, wreck: bool) -> void:
	P.box(cv, o, D.w(rot, -0.06, 0, 4), 0.05, 0.03, 2.0, rot, V.GUNMETAL if not wreck else V.BURNT, 0.05, 1721)


static func _skirt(cv, o: Vector2, c0: Vector3, rot: float, hx: float, wreck: bool) -> void:
	var r: Dictionary = P.box(cv, o, c0 + D.w(rot, 0, 0, 1), hx - 0.02, 0.1, 4.0, rot, V.TRACK if not wreck else V.BURNT, 0.06, 1722)
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		if q[0].distance_to(q[1]) < 12.0:
			continue
		for u in [0.12, 0.3, 0.7, 0.88]:
			var wc: Vector2 = q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), 0.45)
			cv.ellipse(wc.x, wc.y, 2.0, 1.7, Color8(28, 26, 24))
			cv.px(int(wc.x), int(wc.y), Color8(96, 92, 84))


static func _bplate(cv, r: Dictionary, col: Color, rot: float, wreck: bool, s: int, team := true) -> void:
	var ax := Vector2(cos(rot), sin(rot))
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		if wreck:
			V.scorch(cv, q)
			continue
		V.rivets(cv, q, 0.85, maxi(3, int(q[0].distance_to(q[1]) / 3.0)), col)
		V.streaks(cv, q, s)
		if absf((sd.n as Vector2).dot(ax)) < 0.3:
			V.patch(cv, q, 0.68, 0.12, 0.9, 0.55, V.PRIMER, s + 1)
			if team:
				cv.team = true
				cv.poly(P.sub(q, 0.06, 0.3, 0.6, 0.6), Color(0.62, 0.62, 0.62))
				cv.team = false
			for u in [0.2, 0.45]:  # firing slits
				cv.poly(P.sub(q, u, 0.7, u + 0.06, 0.76), Color8(20, 20, 18))
	if not wreck:
		D.box_edges(cv, r, col, s + 2)


static func _loco(cv, o: Vector2, c0: Vector3, rot: float, f: int, wreck: bool, info: Dictionary) -> void:
	var hull: Color = V.BURNT if wreck else V.HULL
	_skirt(cv, o, c0, rot, 0.32, wreck)
	var front := D.faces_cam(rot, 1.0, 0.0)
	var prow_c := c0 + D.w(rot, 0.32, 0, 2)
	if not front:
		P.box(cv, o, prow_c, 0.04, 0.11, 6.0, rot, P.mul(hull, 0.85), 0.06, 1731)
	var body: Dictionary = P.box(cv, o, c0 + D.w(rot, 0.0, 0, 5), 0.3, 0.13, 10.0, rot, hull, 0.08, 1732)
	_bplate(cv, body, hull, rot, wreck, 1733)
	if front:
		var pr: Dictionary = P.box(cv, o, prow_c, 0.04, 0.11, 6.0, rot, P.mul(hull, 0.85), 0.06, 1731)
		if not wreck:
			for sd in pr.sides:
				for vb in [0.3, 0.6]:  # cowcatcher bars
					cv.line_v(sd.quad[0].lerp(sd.quad[3], vb), sd.quad[1].lerp(sd.quad[2], vb), P.mul(hull, 0.6))
	var parts := [[-0.17, 0.11, 0.12, 6.0, "cab"], [0.1, 0.16, 0.08, 3.0, "eng"]]
	if not front:
		parts.reverse()
	for pt in parts:
		var r: Dictionary = P.box(cv, o, c0 + D.w(rot, pt[0], 0, 15), pt[1], pt[2], pt[3], rot, hull if pt[4] == "cab" else P.mul(hull, 0.9), 0.08, 1734)
		if wreck:
			V.scorch(cv, r.top)
			continue
		D.box_edges(cv, r, hull, 1735)
		if pt[4] == "cab":
			for sd in r.sides:
				cv.poly(P.sub(sd.quad, 0.2, 0.5, 0.8, 0.66), Color8(22, 22, 20))  # vision slit
			D.hatch(cv, r.top, 0.25, 0.25, 0.6, 0.6, hull)
		else:
			D.grille(cv, r.top, 0.1, 0.2, 0.9, 0.8, hull, 5)
			var sc := c0 + D.w(rot, 0.2, 0, 18)
			var top := B.cyl(cv, o, sc, 0.035, 7.0, V.GUNMETAL, 1736)
			cv.ellipse(top.x, top.y, 1.6, 0.8, V.SOOT)
			info["stack"] = top
	if wreck:
		var sc2 := c0 + D.w(rot, 0.2, 0, 18)
		B.cyl(cv, o, sc2, 0.035, 4.0, V.BURNT, 1736)


static func _car(cv, o: Vector2, c0: Vector3, rot: float, f: int, wreck: bool, info: Dictionary) -> void:
	var hull: Color = V.BURNT if wreck else V.HULL
	_skirt(cv, o, c0, rot, 0.3, wreck)
	var body: Dictionary = P.box(cv, o, c0 + D.w(rot, 0.0, 0, 5), 0.29, 0.13, 8.0, rot, hull, 0.08, 1741)
	_bplate(cv, body, hull, rot, wreck, 1742)
	cv.poly(P.sub(body.top, 0.06, 0.1, 0.94, 0.9), P.mul(hull, 0.55) if not wreck else V.SOOT)  # open deck
	var trot := rot + (0.7 if not wreck else 1.6)
	var items := [[0.12, "gun"], [-0.17, "flak"]]
	if not D.faces_cam(rot, 1.0, 0.0):
		items.reverse()
	for it in items:
		if it[1] == "gun":
			var tc := c0 + D.w(rot, 0.12, 0, 13)
			var tfront := D.faces_cam(trot, 1.0, 0.0)
			var bl := 0.3 if f != 2 else 0.26
			var bb := P.proj(o, tc + D.w(trot, 0.08, 0, 3.5))
			var bt := P.proj(o, tc + D.w(trot, 0.08 + bl, 0, 4.5 if not wreck else 1.0))
			if not tfront:
				_bbarrel(cv, bb, bt, wreck)
			var tr: Dictionary = P.box(cv, o, tc, 0.1, 0.09, 6.0, trot, hull, 0.08, 1743)
			if wreck:
				V.scorch(cv, tr.top)
			else:
				D.box_edges(cv, tr, hull, 1744)
				for sd in tr.sides:
					V.rivets(cv, sd.quad, 0.8, 4, hull)
				D.hatch(cv, tr.top, 0.2, 0.25, 0.5, 0.6, hull)
			if tfront:
				_bbarrel(cv, bb, bt, wreck)
			info["gun"] = bt
		else:
			var fc := c0 + D.w(rot, -0.17, 0, 13)
			P.box(cv, o, fc, 0.05, 0.05, 3.0, rot, V.GUNMETAL if not wreck else V.BURNT, 0.06, 1745)
			var sh: Dictionary = P.box(cv, o, fc + D.w(trot, 0.05, 0, 2), 0.02, 0.08, 5.0, trot, P.mul(hull, 0.9), 0.06, 1746)
			if wreck:
				continue
			var tip := Vector2.ZERO
			for s in [-0.03, 0.03]:
				var a := P.proj(o, fc + D.w(trot, 0.0, s, 6))
				var b := P.proj(o, fc + D.w(trot, 0.14, s, 16))
				cv.line_v(a, b, V.GUNMETAL)
				tip = b
			info["flak"] = tip


static func _bbarrel(cv, a: Vector2, b: Vector2, wreck: bool) -> void:
	var c: Color = V.GUNMETAL if not wreck else V.BURNT
	cv.line_v(a, b, c)
	cv.line_v(a + Vector2(0, 1), b + Vector2(0, 1), P.mul(c, 0.8))
	cv.rect(int(b.x) - 1, int(b.y) - 1, 2, 3, P.mul(c, 1.15))


# ================================================================ b_scrapyard
static func scrapyard(cv, o: Vector2, f: int) -> void:
	var ps: Array = []
	for u in [-1.12, 1.12]:
		for v in [-0.42, 0.42]:
			ps.append([u, v, 2, 0.045, 0.045, 40, ORANGE_D, "leg"])
		ps.append([u, 0.0, 40, 0.05, 0.47, 4, ORANGE, "girder"])
	ps.append([0.0, -0.14, 44, 1.2, 0.05, 5, ORANGE, "girder"])
	ps.append([0.0, 0.14, 44, 1.2, 0.05, 5, ORANGE, "girder"])
	ps.append_array([
		[-0.5, -0.62, 2, 0.4, 0.32, 9, FB.RUSTY, "scrap"],
		[0.42, 0.02, 2, 0.42, 0.36, 12, FB.RUSTY, "scrap"],
		[-0.48, 0.58, 2, 0.36, 0.3, 8, FB.SLAG, "scrap"],
		[0.95, 0.95, 2, 0.3, 0.22, 12, FB.STEEL, "press"],
		[0.32, 1.12, 2, 0.08, 0.08, 6, V.RUST, "bale"],
		[0.52, 1.12, 2, 0.08, 0.08, 6, Color8(110, 100, 86), "bale"],
		[0.42, 1.12, 8, 0.08, 0.08, 6, Color8(126, 84, 52), "bale"],
		[-1.05, 1.02, 2, 0.28, 0.26, 12, FB.IRON, "shed"],
		[1.2, -1.15, 2, 0.06, 0.06, 7, FB.DRUM_R, "drum"],
		[1.2, -0.97, 2, 0.06, 0.06, 7, FB.DRUM_O, "drum"],
	])
	_bdraw(cv, o, f, 3, ps, "b_scrapyard", Callable(), _sy_dress, func(c, oo, ff) -> void:
		var tw := K.wp(ff, 0.42, 0.0)
		var tr: Dictionary = P.box(c, oo, Vector3(tw.x, tw.y, 49), 0.12, 0.2, 4.0, K.rot(ff), ORANGE_D, 0.08, 1801)
		B.edges(c, tr, ORANGE_D)
		var cab: Dictionary = P.box(c, oo, Vector3(tw.x, tw.y, 41), 0.07, 0.07, 5.0, K.rot(ff), Color8(100, 96, 86), 0.08, 1802)
		c.team = true
		c.poly(cab.top, Color(0.8, 0.8, 0.8))
		c.team = false
		for sd in cab.sides:
			c.poly(P.sub(sd.quad, 0.2, 0.35, 0.8, 0.8), T.GLASS)
		var hk := P.proj(oo, Vector3(tw.x, tw.y, 48))
		var mg := P.proj(oo, Vector3(tw.x, tw.y, 22))
		c.line_v(hk, mg, Color8(36, 36, 32))
		c.line_v(hk + Vector2(1, 0), mg + Vector2(1, 0), Color8(56, 56, 52))
		P.box(c, oo, Vector3(tw.x, tw.y, 12), 0.13, 0.07, 6.0, 0.6, Color8(84, 92, 64), 0.16, 1803)  # held car shell
		c.ellipse(mg.x, mg.y + 1, 5.0, 2.3, Color8(54, 54, 50))
		c.ellipse(mg.x - 0.5, mg.y, 3.8, 1.6, Color8(98, 100, 96))
		B.lamp(c, P.proj(oo, Vector3(K.wp(ff, -1.12, 0.42).x, K.wp(ff, -1.12, 0.42).y, 38))))


static func _sy_dress(cv, o: Vector2, f: int, p: Array, r: Dictionary) -> void:
	var col: Color = p[6]
	match String(p[7]):
		"girder":
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				var n := maxi(2, int(q[0].distance_to(q[1]) / 5.0))
				for i in n:  # truss zig-zag
					var u0 := float(i) / n
					var u1 := float(i + 1) / n
					var a: Vector2 = q[0].lerp(q[1], u0).lerp(q[3].lerp(q[2], u0), 0.1 if i % 2 == 0 else 0.9)
					var b: Vector2 = q[0].lerp(q[1], u1).lerp(q[3].lerp(q[2], u1), 0.9 if i % 2 == 0 else 0.1)
					cv.line_v(a, b, P.mul(col, 0.6))
				V.streaks(cv, q, 1811)
		"leg":
			for sd in r.sides:
				for vb in [0.25, 0.5, 0.75]:
					cv.line_v(sd.quad[0].lerp(sd.quad[3], vb), sd.quad[1].lerp(sd.quad[2], vb), P.mul(col, 0.7))
		"press":
			for sd in r.sides:
				V.rivets(cv, sd.quad, 0.85, 6, col)
				V.rivets(cv, sd.quad, 0.15, 6, col)
				cv.poly(P.sub(sd.quad, 0.55, 0.15, 0.9, 0.55), Color8(26, 24, 22))  # bale chute
				cv.team = true
				cv.poly(P.sub(sd.quad, 0.08, 0.6, 0.45, 0.75), Color(0.66, 0.66, 0.66))
				cv.team = false
			var c2 := K.wp(f, p[0], p[1])
			var ram: Dictionary = P.box(cv, o, Vector3(c2.x, c2.y, 14), 0.08, 0.08, 9.0, K.rot(f), FB.STEEL, 0.06, 1812)
			B.edges(cv, ram, FB.STEEL)
			B.pipe(cv, o, Vector3(c2.x, c2.y, 22), Vector3(c2.x + 0.25, c2.y - 0.1, 12), Color8(90, 84, 76))
		"bale":
			V.streaks(cv, r.top, 1813, 0.5)
			for sd in r.sides:
				cv.line_v(sd.quad[0].lerp(sd.quad[3], 0.5), sd.quad[1].lerp(sd.quad[2], 0.5), P.mul(col, 0.7))


# ================================================================ b_propaganda_tower
static func propaganda_tower(cv, o: Vector2, f: int) -> void:
	var ps := [
		[0.2, 0.18, 2, 0.2, 0.18, 10, FB.BRICK, "brick"],
		[-0.3, 0.32, 2, 0.12, 0.06, 4, FB.SAND, "sandbag"],
		[0.32, -0.3, 2, 0.05, 0.05, 6, FB.DRUM_R, "drum"],
	]
	_bdraw(cv, o, f, 1, ps, "b_propaganda_tower", func(c, oo, ff) -> void: _tower(c, oo, ff), Callable(), func(c, oo, ff) -> void:
		B.cable(c, K.pt(oo, ff, -0.12, -0.12, 58), K.pt(oo, ff, 0.2, 0.05, 12), 3.0), false)


static func _tower(cv, o: Vector2, f: int) -> void:
	var cu := -0.12
	var cvv := -0.12
	var ztop := 70.0
	var steel := Color8(98, 72, 52)
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var leg: Array = []
	for s: Vector2 in corners:
		var bw := K.wp(f, cu + s.x * 0.15, cvv + s.y * 0.15)
		var tw := K.wp(f, cu + s.x * 0.045, cvv + s.y * 0.045)
		leg.append([Vector3(bw.x, bw.y, 2), Vector3(tw.x, tw.y, ztop)])
	# faces ordered back to front by world depth of their mid point
	var faces: Array = []
	for i in 4:
		var j := (i + 1) % 4
		var m: Vector3 = (leg[i][0] + leg[j][0]) * 0.5
		faces.append([m.x + m.y, i, j])
	faces.sort_custom(func(a, b): return a[0] < b[0])
	for fc in faces:
		var i: int = fc[1]
		var j: int = fc[2]
		var dim := 0.72 if fc[0] < 0.0 else 1.0
		var n := 7
		for kq in n:
			var t0 := float(kq) / n
			var t1 := float(kq + 1) / n
			var a0 := P.proj(o, (leg[i][0] as Vector3).lerp(leg[i][1], t0))
			var a1 := P.proj(o, (leg[i][0] as Vector3).lerp(leg[i][1], t1))
			var b0 := P.proj(o, (leg[j][0] as Vector3).lerp(leg[j][1], t0))
			var b1 := P.proj(o, (leg[j][0] as Vector3).lerp(leg[j][1], t1))
			cv.line_v(a0, b1, P.mul(steel, 0.8 * dim))
			cv.line_v(b0, a1, P.mul(steel, 0.8 * dim))
			cv.line_v(a1, b1, P.mul(steel, 0.9 * dim))
	for l in leg:
		cv.line_v(P.proj(o, l[0]), P.proj(o, l[1]), P.mul(steel, 1.15))
	var cw := K.wp(f, cu, cvv)
	var plat: Dictionary = P.box(cv, o, Vector3(cw.x, cw.y, ztop), 0.09, 0.09, 2.0, K.rot(f), Color8(84, 78, 70), 0.08, 1901)
	B.edges(cv, plat, Color8(84, 78, 70))
	# banner on the front face, hanging from a cross bar
	var ax: Vector2 = K.AX[f % 4]
	var pp := K.pp(f)
	var fu := cu + 0.0
	var b_tl := P.proj(o, Vector3(cw.x + ax.x * 0.07 - pp.x * 0.12, cw.y + ax.y * 0.07 - pp.y * 0.12, 58))
	var b_tr := P.proj(o, Vector3(cw.x + ax.x * 0.07 + pp.x * 0.12, cw.y + ax.y * 0.07 + pp.y * 0.12, 58))
	var b_br := P.proj(o, Vector3(cw.x + ax.x * 0.13 + pp.x * 0.16, cw.y + ax.y * 0.13 + pp.y * 0.16, 24))
	var b_bl := P.proj(o, Vector3(cw.x + ax.x * 0.13 - pp.x * 0.16, cw.y + ax.y * 0.13 - pp.y * 0.16, 24))
	var _u := fu
	var bq := PackedVector2Array([b_bl, b_br, b_tr, b_tl])
	cv.line_v(b_tl + Vector2(-2, -1), b_tr + Vector2(2, -1), Color8(60, 52, 44))
	cv.team = true
	cv.poly(bq, Color(0.8, 0.8, 0.8), P.speckle(0.08, 1902))
	cv.poly(P.sub(bq, 0.0, 0.0, 1.0, 0.08), Color(0.6, 0.6, 0.6))
	cv.poly(P.sub(bq, 0.0, 0.92, 1.0, 1.0), Color(0.6, 0.6, 0.6))
	cv.team = false
	var em: Vector2 = (b_bl + b_br + b_tr + b_tl) * 0.25
	var gold := Color8(230, 188, 70)
	for i in 12:  # cog emblem
		var a := i * TAU / 12.0
		var rr := 4.5 if i % 2 == 0 else 3.6
		cv.px(int(em.x + cos(a) * rr), int(em.y + sin(a) * rr), gold)
	cv.rect(int(em.x) - 1, int(em.y) - 1, 3, 3, gold)
	cv.px(int(em.x), int(em.y), Color8(120, 40, 30))
	# loudspeaker horns, two tiers, pointing out of each face
	for z in [ztop - 2.0, ztop - 12.0]:
		var hs: Array = []
		for dv in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
			var wd := K.wp(f, dv.x, dv.y)
			hs.append([wd.x + wd.y, wd])
		hs.sort_custom(func(a, b): return a[0] < b[0])
		for h in hs:
			var wd: Vector2 = h[1]
			var m0 := P.proj(o, Vector3(cw.x + wd.x * 0.03, cw.y + wd.y * 0.03, z))
			var m1 := P.proj(o, Vector3(cw.x + wd.x * 0.17, cw.y + wd.y * 0.17, z - 3.0))
			var dirv := (m1 - m0).normalized() if m1.distance_to(m0) > 0.1 else Vector2(0, 1)
			var pr := Vector2(-dirv.y, dirv.x)
			for t in 6:
				var q := m0.lerp(m1, t / 5.0)
				var wdt := 0.5 + t * 0.5
				cv.line_v(q - pr * wdt, q + pr * wdt, P.mul(HORN, 0.85 + t * 0.04))
			if float(h[0]) > 0.0:
				cv.ellipse(m1.x, m1.y, 2.2, 1.6, Color8(34, 34, 30))
	var tp := P.proj(o, Vector3(cw.x, cw.y, ztop + 2))
	cv.line_v(tp, tp + Vector2(0, -7), Color8(50, 46, 42))
	cv.px(int(tp.x), int(tp.y) - 8, Color8(236, 60, 50))
