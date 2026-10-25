extends RefCounted
## G6 proposal ground vehicles (builder art-vehicles): 15 vehicles for Human A, Human B and the Machine,
## drawn only with the shipped art libraries and their conventions:
##   Human A  vehicles.gd olive hull, vdetail kit (tracks, hatches, cupola, vision blocks), tidy team bands.
##   Human B  faction_b_veh.gd khaki/rust, rivets, welded patches, streaks, soot; g4_units_b halftrack parts,
##            g3b_human_b truck chassis.
##   Machine  faction_m_lib graphite + light panels + cyan seams/eyes, faction_m_units legs, g3b_machine panels.
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const VH = preload("res://tools/art/vehicles.gd")
const V = preload("res://tools/art/faction_b_veh.gd")
const TRK = preload("res://tools/art/faction_b_trk.gd")
const HB = preload("res://tools/art/g3b_human_b.gd")
const G4B = preload("res://tools/art/g4_units_b.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const ML = preload("res://tools/art/faction_m_lib.gd")
const MV = preload("res://tools/art/faction_m_veh.gd")
const FMU = preload("res://tools/art/faction_m_units.gd")
const G3M = preload("res://tools/art/g3b_machine.gd")
const WK = preload("res://tools/art/faction_m_walker.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")
const FIG = preload("res://tools/art/g5_units_fig.gd")
const U = preload("res://tools/art/units.gd")

const OUTL := Color(0.09, 0.09, 0.07, 1)
const OUTL_B := Color(0.08, 0.07, 0.06, 1)
const OUTL_M := Color(0.07, 0.08, 0.09, 1)
const STEEL := Color8(156, 156, 146)
const OCHRE := Color8(150, 118, 56)
const B_COAT := Color8(116, 100, 68)
const B_HELM := Color8(76, 72, 56)
const RIFLEMAN := {"coat": U.UNIFORM, "trouser": U.TROUSER, "boot": U.BOOT, "skin": U.SKIN, "head": "helm_a", "weapon": "rifle"}

const SPEC := {
	"a_sp_howitzer": {"fw": 100, "fh": 68, "pivot": [50, 52]},
	"a_mlrs": {"fw": 84, "fh": 64, "pivot": [42, 43]},
	"a_mine_clearer": {"fw": 96, "fh": 66, "pivot": [48, 46]},
	"a_bridge_layer": {"fw": 166, "fh": 94, "pivot": [83, 48]},
	"a_command_vehicle": {"fw": 78, "fh": 69, "pivot": [39, 51]},
	"a_ugv": {"fw": 48, "fh": 38, "pivot": [24, 25]},
	"b_landship": {"fw": 112, "fh": 69, "pivot": [56, 46]},
	"b_flak_halftrack": {"fw": 70, "fh": 60, "pivot": [35, 41]},
	"b_armored_dozer": {"fw": 84, "fh": 60, "pivot": [42, 38]},
	"b_salvage_crane": {"fw": 84, "fh": 68, "pivot": [42, 48]},
	"b_moto_scouts": {"fw": 64, "fh": 50, "pivot": [32, 31]},
	"m_spider_layer": {"fw": 64, "fh": 52, "pivot": [32, 33]},
	"m_hover_tank": {"fw": 80, "fh": 60, "pivot": [40, 38]},
	"m_colossus": {"fw": 108, "fh": 92, "pivot": [54, 66]},
	"m_assimilator": {"fw": 84, "fh": 60, "pivot": [42, 38]},
}

const SHOW := {
	"a_sp_howitzer": {"row": 0, "frame": "fire", "ground": "dirt"},
	"a_mlrs": {"row": 0, "frame": "fire", "ground": "dirt"},
	"a_mine_clearer": {"row": 0, "frame": "fire", "ground": "dirt"},
	"a_bridge_layer": {"row": 0, "frame": "deployed", "ground": "grass"},
	"a_command_vehicle": {"row": 0, "frame": "deployed", "ground": "dirt"},
	"a_ugv": {"row": 0, "frame": "fire", "ground": "grass"},
	"b_landship": {"row": 0, "frame": "fire", "ground": "mud"},
	"b_flak_halftrack": {"row": 0, "frame": "fire", "ground": "dirt"},
	"b_armored_dozer": {"row": 0, "frame": "work", "ground": "dirt"},
	"b_salvage_crane": {"row": 0, "frame": "work", "ground": "dirt"},
	"b_moto_scouts": {"row": 0, "frame": "move", "ground": "dirt"},
	"m_spider_layer": {"row": 0, "frame": "lay", "ground": "grass"},
	"m_hover_tank": {"row": 0, "frame": "move", "ground": "water"},
	"m_colossus": {"row": 0, "frame": "scale", "ground": "grass"},
	"m_assimilator": {"row": 0, "frame": "work", "ground": "dirt"},
}


static func build(out: Dictionary) -> void:
	SL.veh_sheet(out, "a_sp_howitzer", SPEC.a_sp_howitzer, sp_howitzer, ["idle", "move", "fire"])
	SL.veh_sheet(out, "a_mlrs", SPEC.a_mlrs, mlrs, ["idle", "move", "fire"])
	SL.veh_sheet(out, "a_mine_clearer", SPEC.a_mine_clearer, mine_clearer, ["idle", "move", "fire"])
	SL.veh_sheet(out, "a_bridge_layer", SPEC.a_bridge_layer, bridge_layer, ["idle", "move", "deployed"])
	SL.veh_sheet(out, "a_command_vehicle", SPEC.a_command_vehicle, command_vehicle, ["idle", "move", "fire", "deployed"])
	SL.veh_sheet(out, "a_ugv", SPEC.a_ugv, ugv, ["idle", "move", "fire"])
	SL.veh_sheet(out, "b_landship", SPEC.b_landship, landship, ["idle", "move", "fire"])
	SL.veh_sheet(out, "b_flak_halftrack", SPEC.b_flak_halftrack, flak_halftrack, ["idle", "move", "fire"])
	SL.veh_sheet(out, "b_armored_dozer", SPEC.b_armored_dozer, armored_dozer, ["idle", "move", "work"])
	SL.veh_sheet(out, "b_salvage_crane", SPEC.b_salvage_crane, salvage_crane, ["idle", "move", "work"])
	SL.veh_sheet(out, "b_moto_scouts", SPEC.b_moto_scouts, moto_scouts, ["idle", "move", "fire"])
	SL.veh_sheet(out, "m_spider_layer", SPEC.m_spider_layer, spider_layer, ["idle", "walk_a", "walk_b", "lay"])
	SL.veh_sheet(out, "m_hover_tank", SPEC.m_hover_tank, hover_tank, ["idle", "move", "fire"])
	SL.veh_sheet(out, "m_colossus", SPEC.m_colossus, colossus, ["idle", "walk_a", "walk_b", "fire", "scale"])
	SL.veh_sheet(out, "m_assimilator", SPEC.m_assimilator, assimilator, ["idle", "move", "work"])


# ================================================================ shared helpers
static func _shadow(cv, o: Vector2, rot: float, parts: Array) -> void:
	for p: Array in parts:
		P.box_shadow(cv, o, D.w(rot, p[0], p[1], p[2]), p[3], p[4], p[5], rot)
	cv.flush_shadow()


## Forward component of a box side's normal (1 = front face, -1 = rear face, ~0 = long side).
static func _fw(sd: Dictionary, rot: float) -> float:
	return (sd.n as Vector2).dot(Vector2(cos(rot), sin(rot)))


## Sub-quad of a long side with u measured rear -> front on both sides.
static func _subf(sd: Dictionary, rot: float, u0: float, v0: float, u1: float, v1: float) -> PackedVector2Array:
	var q: PackedVector2Array = sd.quad
	if (sd.n as Vector2).dot(Vector2(-sin(rot), cos(rot))) > 0.0:
		return P.sub(q, 1.0 - u1, v0, 1.0 - u0, v1)
	return P.sub(q, u0, v0, u1, v1)


static func _team(cv, q: PackedVector2Array, u0: float, v0: float, u1: float, v1: float, lum := 0.62) -> void:
	cv.team = true
	cv.poly(P.sub(q, u0, v0, u1, v1), Color(lum, lum, lum))
	cv.team = false


## Tracked running gear (one pass: far or near side), Human-A style with mud.
static func _tracks(cv, o: Vector2, rot: float, f: int, wreck: bool, near: bool, fwd: float, off: float,
		hx: float, hy: float, hz: float, col: Color, nw: int, s: int, muddy := true) -> void:
	for side: float in [-1.0, 1.0]:
		if D.faces_cam(rot, 0.0, side) != near:
			continue
		var tr: Dictionary = P.box(cv, o, D.w(rot, fwd, off * side, 0), hx, hy, hz, rot, col, 0.05, s)
		for sd in tr.sides:
			if absf(_fw(sd, rot)) < 0.3:
				if muddy and not wreck:
					D.mud(cv, sd.quad, s + 4, 0.55)
				D.track_side(cv, sd.quad, f, wreck, nw)


## Shaded round tube between two screen points (th px thick, lit on top).
static func _tube(cv, a: Vector2, b: Vector2, c: Color, th := 3) -> void:
	for i in th:
		var k := 1.28 if i == 0 else (0.78 if i == th - 1 else 1.0)
		var off := Vector2(0, i - 1)
		cv.line_v(a + off, b + off, P.mul(c, k))


static func _hull_dress_a(cv, r: Dictionary, rot: float, hull: Color, s: int) -> void:
	D.box_edges(cv, r, hull, s)
	D.contact_ao(cv, r)
	for sd in r.sides:
		if _fw(sd, rot) > 0.7:
			D.tow_hooks(cv, sd.quad)


static func _dress_b(cv, sd: Dictionary, rot: float, hull: Color, s: int, nriv := 7) -> void:
	var q: PackedVector2Array = sd.quad
	V.patch(cv, q, 0.12, 0.25, 0.34, 0.75, V.RUST, s)
	V.patch(cv, q, 0.62, 0.3, 0.84, 0.8, V.PRIMER, s + 1)
	V.rivets(cv, q, 0.86, nriv, hull)
	V.streaks(cv, q, s + 2)


# ================================================================ a_sp_howitzer
## Tracked SP gun: long low hull, big rear-set boxy gun house with overhang, long 155 mm barrel with
## fume extractor + muzzle brake, travel lock on the glacis (barrel rests in it on the move).
static func sp_howitzer(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = VH.BURNT if wreck else VH.HULL
	_shadow(cv, o, rot, [[0.0, 0.0, 0.0, 0.64, 0.34, 9.0], [-0.15, 0.0, 12.0, 0.35, 0.3, 11.0]])
	_tracks(cv, o, rot, f, wreck, false, 0.0, 0.25, 0.64, 0.075, 6.0, VH.TRACK, 7, 901)
	var lo: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 4), 0.6, 0.17, 6.0, rot, P.mul(hull, 0.92), 0.08, 902)
	if wreck:
		VH._scorch(cv, lo)
	_tracks(cv, o, rot, f, wreck, true, 0.0, 0.25, 0.64, 0.075, 6.0, VH.TRACK, 7, 901)
	var hl: Dictionary = P.box(cv, o, D.w(rot, 0.02, 0.0, 9), 0.63, 0.33, 3.0, rot, hull, 0.08, 903)
	if wreck:
		VH._scorch(cv, hl)
	else:
		_hull_dress_a(cv, hl, rot, hull, 904)
		D.grille(cv, hl.top, 0.72, 0.1, 0.9, 0.42, hull, 4)
		D.hatch(cv, hl.top, 0.8, 0.62, 0.94, 0.86, hull)
		for sd in hl.sides:
			if _fw(sd, rot) > 0.7:
				for u in [0.14, 0.86]:
					var lp: Vector2 = (sd.quad as PackedVector2Array)[0].lerp(sd.quad[1], u).lerp((sd.quad as PackedVector2Array)[3].lerp(sd.quad[2], u), 0.6)
					cv.px(int(lp.x), int(lp.y), Color8(226, 214, 160))
		# travel lock (A-frame crutch on the glacis)
		var lt := D.sp(o, rot, 0.6, 0.0, 15.5 if f == 1 else 12.8)
		for s: float in [-1.0, 1.0]:
			cv.line_v(D.sp(o, rot, 0.6, 0.06 * s, 12), lt, VH.GUNMETAL)
	var front := D.faces_cam(rot, 1.0, 0.0)
	var rec := 0.07 if (f == 2 and not wreck) else 0.0
	var tipf := 1.04
	var tipz := 24.0
	if wreck:
		tipf = 0.84
		tipz = 12.0
	elif f == 1:
		tipz = 15.0
	elif f == 2:
		tipf = 0.97
		tipz = 29.0
	var base := D.sp(o, rot, 0.2 - rec, 0.0, 18)
	var tip := D.sp(o, rot, tipf - rec, 0.0, tipz)
	if not front:
		_sph_gun(cv, base, tip, wreck)
		P.box(cv, o, D.w(rot, 0.21 - rec * 0.5, 0.0, 14), 0.04, 0.12, 7.0, rot, P.mul(hull, 0.86), 0.05, 907)
	var tur: Dictionary = P.box(cv, o, D.w(rot, -0.15, 0.0, 12), 0.35, 0.3, 11.0, rot, hull, 0.08, 905)
	if wreck:
		VH._scorch(cv, tur)
	else:
		D.box_edges(cv, tur, hull, 906)
		for sd in tur.sides:
			var q: PackedVector2Array = sd.quad
			var d := _fw(sd, rot)
			if absf(d) < 0.3:
				_team(cv, _subf(sd, rot, 0.0, 0.0, 1.0, 1.0), 0.42, 0.4, 0.96, 0.66)
				cv.poly(_subf(sd, rot, 0.06, 0.12, 0.36, 0.58), P.mul(hull, 0.8))  # side stowage bin
				var ln := _subf(sd, rot, 0.06, 0.58, 0.36, 0.58)
				cv.line_v(ln[0], ln[1], P.mul(hull, 1.22))
				var jt := _subf(sd, rot, 0.39, 0.0, 0.39, 1.0)
				cv.line_v(jt[0], jt[3], P.mul(hull, 0.72))
			elif d < -0.7:  # rear ammo door
				var dq := P.sub(q, 0.28, 0.08, 0.72, 0.86)
				cv.poly(dq, P.mul(hull, 0.74))
				cv.line_v(dq[3], dq[2], P.mul(hull, 1.25))
				cv.px(int((dq[0].x + dq[2].x) * 0.5), int((dq[0].y + dq[2].y) * 0.5), D.DARK)
			else:
				for u in [0.18, 0.82]:
					var vp: Vector2 = q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), 0.78)
					cv.px(int(vp.x), int(vp.y), D.VISION)
		var rq := P.sub(tur.top, 0.42, 0.18, 0.86, 0.82)
		cv.poly(rq, P.mul(hull, 1.07))  # raised roof plate
		cv.line_v(rq[0], rq[3], P.mul(hull, 1.25))
		D.hatch(cv, tur.top, 0.1, 0.58, 0.32, 0.86, hull)
		D.cupola(cv, o, rot, -0.3, -0.15, 23, hull, false)
		cv.line_v(D.sp(o, rot, -0.28, -0.15, 26.5), D.sp(o, rot, -0.12, -0.15, 27), VH.GUNMETAL)  # cupola MG
		D.antenna(cv, D.sp(o, rot, -0.46, 0.22, 23), 13, false)
		D.antenna(cv, D.sp(o, rot, -0.46, -0.24, 23), 9, false)
		D.stowage(cv, o, rot, -0.53, 0.0, 13, 0.03, 0.22, 6.0, false, false)
	if front:
		P.box(cv, o, D.w(rot, 0.21 - rec * 0.5, 0.0, 14), 0.04, 0.12, 7.0, rot, P.mul(hull, 0.86), 0.05, 907)
		_sph_gun(cv, base, tip, wreck)
	cv.outline(OUTL)
	if wreck:
		V.soot(cv, D.sp(o, rot, -0.1, 0.0, 20), 6.0, 908)
	elif f == 2:
		L.flash(cv, tip, 1.6)
		L.puff(cv, tip + Vector2(2, -3), 3.0, 0.5)
		L.puff(cv, tip + Vector2(6, -5), 2.2, 0.35)
		L.puff(cv, D.sp(o, rot, 0.75, 0.25, 0), 2.6, 0.3, Color(0.7, 0.62, 0.5))
		L.puff(cv, D.sp(o, rot, 0.75, -0.25, 0), 2.6, 0.3, Color(0.7, 0.62, 0.5))


static func _sph_gun(cv, a: Vector2, b: Vector2, wreck: bool) -> void:
	var c: Color = VH.GUNMETAL if not wreck else VH.BURNT
	_tube(cv, a, b, c, 3)
	var ev := a.lerp(b, 0.42)
	cv.rect(int(ev.x) - 2, int(ev.y) - 2, 4, 4, P.mul(c, 1.08))  # fume extractor
	cv.px(int(ev.x) - 2, int(ev.y) - 2, P.mul(c, 1.45))
	cv.rect(int(b.x) - 2, int(b.y) - 2, 4, 4, P.mul(c, 0.92))  # muzzle brake
	cv.px(int(b.x) - 2, int(b.y) - 2, P.mul(c, 1.4))
	cv.px(int(b.x) + 1, int(b.y) + 1, P.mul(c, 0.6))


# ================================================================ a_mlrs
## Tracked rocket launcher: armoured 3-man cab up front, traversing launcher with two 6-cell pods (12 tubes).
static func mlrs(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = VH.BURNT if wreck else VH.HULL
	_shadow(cv, o, rot, [[0.0, 0.0, 0.0, 0.6, 0.33, 9.0], [-0.17, 0.0, 14.0, 0.36, 0.27, 9.0], [0.42, 0.0, 12.0, 0.17, 0.31, 8.0]])
	_tracks(cv, o, rot, f, wreck, false, 0.0, 0.25, 0.6, 0.075, 6.0, VH.TRACK, 6, 911)
	P.box(cv, o, D.w(rot, 0.0, 0.0, 4), 0.57, 0.17, 6.0, rot, P.mul(hull, 0.92), 0.08, 912)
	_tracks(cv, o, rot, f, wreck, true, 0.0, 0.25, 0.6, 0.075, 6.0, VH.TRACK, 6, 911)
	var hl: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 9), 0.6, 0.33, 3.0, rot, hull, 0.08, 913)
	if wreck:
		VH._scorch(cv, hl)
	else:
		_hull_dress_a(cv, hl, rot, hull, 914)
		D.grille(cv, hl.top, 0.02, 0.15, 0.16, 0.85, hull, 5)
	var lift := 4.0 if (f == 2 and not wreck) else 0.0
	if D.faces_cam(rot, 1.0, 0.0):
		_mlrs_pod(cv, o, rot, hull, wreck, lift)
		_mlrs_cab(cv, o, rot, hull, wreck)
	else:
		_mlrs_cab(cv, o, rot, hull, wreck)
		_mlrs_pod(cv, o, rot, hull, wreck, lift)
	cv.outline(OUTL)
	if wreck:
		V.soot(cv, D.sp(o, rot, -0.15, 0.0, 22), 7.0, 919)
	elif f == 2:  # ripple salvo: rockets leaving the front cells, backblast behind the pods
		for i in 3:
			var a := D.sp(o, rot, 0.2, -0.2 + i * 0.2, 21 + lift)
			var b := D.sp(o, rot, 0.46 + i * 0.04, -0.2 + i * 0.2, 30 + i * 2)
			cv.line_v(a, b, Color(0.86, 0.84, 0.78, 0.6))
			L.flash(cv, b, 0.8)
		L.flash(cv, D.sp(o, rot, 0.2, 0.0, 19 + lift), 1.1)
		L.puff(cv, D.sp(o, rot, -0.62, 0.0, 14), 4.5, 0.5)
		L.puff(cv, D.sp(o, rot, -0.8, 0.12, 8), 3.5, 0.38)
		L.puff(cv, D.sp(o, rot, -0.75, -0.15, 4), 3.0, 0.3, Color(0.7, 0.62, 0.5))


static func _mlrs_pod(cv, o: Vector2, rot: float, hull: Color, wreck: bool, lift: float) -> void:
	var steel: Color = VH.GUNMETAL if not wreck else VH.BURNT
	P.box(cv, o, D.w(rot, -0.2, 0.0, 12), 0.13, 0.13, 2.5 + lift, rot, steel, 0.06, 915)  # turntable + lift arms
	var pc: Color = P.mul(hull, 1.04)
	for near in [false, true]:
		for s: float in [-1.0, 1.0]:
			if D.faces_cam(rot, 0.0, s) != near:
				continue
			var pr: Dictionary = P.box(cv, o, D.w(rot, -0.17, 0.135 * s, 14.5 + lift), 0.36, 0.125, 9.0, rot, pc, 0.07, 916)
			if wreck:
				V.scorch(cv, pr.top)
				continue
			for sd in pr.sides:
				var q: PackedVector2Array = sd.quad
				var d := _fw(sd, rot)
				if d > 0.7:  # 2 x 3 tube mouths per pod
					for yy in 2:
						for xx in 3:
							var c := P.sub(q, 0.08 + xx * 0.29, 0.12 + yy * 0.44, 0.33 + xx * 0.29, 0.48 + yy * 0.44)
							cv.poly(c, Color8(26, 26, 24))
							var m: Vector2 = (c[0] + c[2]) * 0.5
							cv.px(int(m.x), int(m.y), Color8(150, 128, 70))
				elif absf(d) < 0.3:
					_team(cv, q, 0.06, 0.52, 0.94, 0.78)
					cv.line_v(q[0].lerp(q[3], 0.3), q[1].lerp(q[2], 0.3), P.mul(pc, 0.78))
				else:
					cv.line_v(q[0].lerp(q[1], 0.5), q[3].lerp(q[2], 0.5), P.mul(pc, 0.75))
			D.box_edges(cv, pr, pc, 917)
			for u in [0.15, 0.85]:
				var lg: Vector2 = P.sub(pr.top, u, 0.5, u, 0.5)[0]
				cv.px(int(lg.x), int(lg.y), P.mul(pc, 0.6))
			var ln := P.sub(pr.top, 0.0, 0.5, 1.0, 0.5)
			cv.line_v(ln[0], ln[1], P.mul(pc, 0.86))


static func _mlrs_cab(cv, o: Vector2, rot: float, hull: Color, wreck: bool) -> void:
	var cb: Dictionary = P.box(cv, o, D.w(rot, 0.42, 0.0, 12), 0.17, 0.31, 8.0, rot, hull, 0.08, 918)
	if wreck:
		VH._scorch(cv, cb)
		return
	D.box_edges(cv, cb, hull, 920)
	for sd in cb.sides:
		var q: PackedVector2Array = sd.quad
		var d := _fw(sd, rot)
		if d > 0.7:  # armoured windscreens with louvred shutters
			for wq in [P.sub(q, 0.08, 0.48, 0.46, 0.82), P.sub(q, 0.54, 0.48, 0.92, 0.82)]:
				cv.poly(wq, P.mul(D.VISION, 0.72))
				cv.line_v(wq[3], wq[2], P.mul(D.VISION, 1.15))
				cv.line_v(wq[0].lerp(wq[3], 0.5), wq[1].lerp(wq[2], 0.5), P.mul(hull, 0.7))
			for u in [0.1, 0.9]:
				var lp: Vector2 = q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), 0.2)
				cv.px(int(lp.x), int(lp.y), Color8(226, 214, 160))
		elif absf(d) < 0.3:
			var wq2 := _subf(sd, rot, 0.55, 0.5, 0.85, 0.8)
			cv.poly(wq2, P.mul(D.VISION, 0.7))
			cv.line_v(_subf(sd, rot, 0.1, 0.25, 0.45, 0.25)[0], _subf(sd, rot, 0.1, 0.25, 0.45, 0.25)[1], P.mul(hull, 0.72))
	_team(cv, cb.top, 0.25, 0.22, 0.8, 0.78)
	D.antenna(cv, D.sp(o, rot, 0.32, -0.26, 20), 11, false)


# ================================================================ a_mine_clearer
## Tank chassis with a twin mine-roller rig on push arms and two rocket line-charge containers on the rear deck.
static func mine_clearer(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = VH.BURNT if wreck else VH.HULL
	_shadow(cv, o, rot, [[0.0, 0.0, 0.0, 0.6, 0.34, 9.0], [0.1, 0.0, 13.0, 0.24, 0.25, 6.0], [0.88, 0.0, 0.0, 0.08, 0.34, 6.0]])
	var front := D.faces_cam(rot, 1.0, 0.0)
	if not front:
		_rollers(cv, o, rot, f, wreck, hull)
	_tracks(cv, o, rot, f, wreck, false, 0.0, 0.25, 0.58, 0.075, 6.0, VH.TRACK, 6, 921)
	P.box(cv, o, D.w(rot, 0.0, 0.0, 4), 0.55, 0.17, 6.0, rot, P.mul(hull, 0.92), 0.08, 922)
	_tracks(cv, o, rot, f, wreck, true, 0.0, 0.25, 0.58, 0.075, 6.0, VH.TRACK, 6, 921)
	var hl: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 9), 0.58, 0.33, 4.0, rot, hull, 0.08, 923)
	if wreck:
		VH._scorch(cv, hl)
	else:
		_hull_dress_a(cv, hl, rot, hull, 924)
		D.grille(cv, hl.top, 0.02, 0.2, 0.14, 0.8, hull, 4)
		for sd in hl.sides:
			if absf(_fw(sd, rot)) < 0.3:
				_team(cv, _subf(sd, rot, 0.0, 0.0, 1.0, 1.0), 0.45, 0.3, 0.8, 0.8)
	if front:
		_lc_launchers(cv, o, rot, f, hull, wreck)
		_mc_casemate(cv, o, rot, hull, wreck)
	else:
		_mc_casemate(cv, o, rot, hull, wreck)
		_lc_launchers(cv, o, rot, f, hull, wreck)
	if front:
		_rollers(cv, o, rot, f, wreck, hull)
	cv.outline(OUTL)
	if wreck:
		V.soot(cv, D.sp(o, rot, 0.0, 0.0, 18), 6.0, 929)
	elif f == 2:  # line charge: rocket dragging the explosive hose out ahead of the vehicle
		var n := 22
		var prev := D.sp(o, rot, -0.34, 0.15, 19)
		for i in range(1, n + 1):
			var t := float(i) / n
			var p := D.sp(o, rot, lerpf(-0.34, 0.8, t), 0.15 * (1.0 - t), lerpf(19.0, 26.0, t) + sin(t * PI) * 9.0)
			cv.line_v(prev, p, Color8(46, 44, 36) if i % 2 == 0 else Color8(120, 112, 80))
			prev = p
		cv.rect(int(prev.x) - 1, int(prev.y) - 1, 3, 2, Color8(70, 74, 60))
		L.flash(cv, prev + Vector2(-1, 1), 0.8)
		L.puff(cv, D.sp(o, rot, -0.36, 0.15, 22), 3.5, 0.5)
		L.puff(cv, D.sp(o, rot, -0.5, 0.2, 18), 2.6, 0.35)
	elif f == 1:
		L.puff(cv, D.sp(o, rot, 0.95, 0.2, 1), 2.4, 0.3, Color(0.7, 0.62, 0.5))
		L.puff(cv, D.sp(o, rot, 0.95, -0.2, 1), 2.4, 0.3, Color(0.7, 0.62, 0.5))


static func _mc_casemate(cv, o: Vector2, rot: float, hull: Color, wreck: bool) -> void:
	var cm: Dictionary = P.box(cv, o, D.w(rot, 0.1, 0.0, 13), 0.24, 0.25, 6.0, rot, hull, 0.08, 925)
	if wreck:
		VH._scorch(cv, cm)
		return
	D.box_edges(cv, cm, hull, 926)
	for sd in cm.sides:
		var q: PackedVector2Array = sd.quad
		if _fw(sd, rot) > 0.7:
			for u in [0.2, 0.5, 0.8]:
				var vp: Vector2 = q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), 0.7)
				cv.px(int(vp.x), int(vp.y), D.VISION)
	_team(cv, cm.top, 0.55, 0.15, 0.9, 0.5)
	D.cupola(cv, o, rot, -0.02, -0.12, 19, hull, false)
	cv.line_v(D.sp(o, rot, 0.0, -0.12, 22.5), D.sp(o, rot, 0.16, -0.12, 23), VH.GUNMETAL)
	D.hatch(cv, cm.top, 0.62, 0.6, 0.88, 0.88, hull)
	D.antenna(cv, D.sp(o, rot, -0.1, 0.2, 19), 11, false)


static func _lc_launchers(cv, o: Vector2, rot: float, f: int, hull: Color, wreck: bool) -> void:
	var col: Color = P.mul(hull, 1.08) if not wreck else VH.BURNT
	for near in [false, true]:
		for s: float in [-1.0, 1.0]:
			if D.faces_cam(rot, 0.0, s) != near:
				continue
			var b: Dictionary = P.box(cv, o, D.w(rot, -0.36, 0.15 * s, 13), 0.14, 0.09, 5.0, rot, col, 0.07, 927)
			if wreck:
				V.scorch(cv, b.top)
				continue
			D.box_edges(cv, b, col, 928)
			for sd in b.sides:
				var q: PackedVector2Array = sd.quad
				var d := _fw(sd, rot)
				if d > 0.7:
					var m := P.sub(q, 0.2, 0.2, 0.8, 0.8)
					cv.poly(m, Color8(28, 28, 26))
					if not (f == 2 and s > 0):
						var c: Vector2 = (m[0] + m[2]) * 0.5
						cv.px(int(c.x), int(c.y), Color8(196, 170, 70))  # rocket nose
				elif absf(d) < 0.3:
					cv.line_v(q[0].lerp(q[3], 0.62), q[1].lerp(q[2], 0.62), Color8(184, 160, 60))  # hazard stencil band


static func _rollers(cv, o: Vector2, rot: float, f: int, wreck: bool, hull: Color) -> void:
	var steel: Color = VH.GUNMETAL if not wreck else VH.BURNT
	var arm: Color = P.mul(hull, 0.85) if not wreck else VH.BURNT
	for s: float in [-1.0, 1.0]:
		var a := D.sp(o, rot, 0.56, 0.2 * s, 9)
		var b := D.sp(o, rot, 0.86, 0.2 * s, 5)
		cv.line_v(a, b, arm)
		cv.line_v(a + Vector2(0, 1), b + Vector2(0, 1), P.mul(arm, 0.7))
	P.box(cv, o, D.w(rot, 0.8, 0.0, 6), 0.02, 0.3, 2.0, rot, arm, 0.05, 930)  # cross beam
	for near in [false, true]:
		for s: float in [-1.0, 1.0]:
			if D.faces_cam(rot, 0.0, s) != near:
				continue
			var r: Dictionary = P.box(cv, o, D.w(rot, 0.88, 0.2 * s, 0), 0.065, 0.12, 6.0, rot, steel, 0.06, 931)
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				if absf(_fw(sd, rot)) > 0.7:  # disc edges with teeth
					for i in 5:
						var u := (i + 0.5) / 5.0
						cv.line_v(q[0].lerp(q[1], u), q[3].lerp(q[2], u), P.mul(steel, 0.6))
						var tp: Vector2 = q[3].lerp(q[2], u)
						cv.px(int(tp.x), int(tp.y) - 1 + (i + f) % 2, P.mul(steel, 1.5))
				else:
					var c: Vector2 = (q[0] + q[2]) * 0.5
					cv.ellipse(c.x, c.y, 2.0, 2.2, P.mul(steel, 0.75))
					cv.px(int(c.x), int(c.y), P.mul(steel, 1.5))
			if not wreck:
				D.mud(cv, P.sub(r.top, 0, 0, 1, 1), 932, 0.3)


# ================================================================ a_bridge_layer
## Tank chassis carrying a folded scissor bridge; "deployed" lays the bridge flat ahead of the bow.
static func bridge_layer(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = VH.BURNT if wreck else VH.HULL
	var dep := f == 2 and not wreck
	var parts := [[0.0, 0.0, 0.0, 0.6, 0.34, 10.0]]
	if dep:
		parts.append([1.15, 0.0, 0.0, 0.64, 0.24, 3.0])
	else:
		parts.append([-0.1, 0.0, 13.0, 0.58, 0.3, 7.0])
	_shadow(cv, o, rot, parts)
	var front := D.faces_cam(rot, 1.0, 0.0)
	if dep and not front:
		_bridge_flat(cv, o, rot, hull)
	_tracks(cv, o, rot, f, wreck, false, 0.0, 0.25, 0.6, 0.075, 6.0, VH.TRACK, 6, 941)
	P.box(cv, o, D.w(rot, 0.0, 0.0, 4), 0.56, 0.17, 6.0, rot, P.mul(hull, 0.92), 0.08, 942)
	_tracks(cv, o, rot, f, wreck, true, 0.0, 0.25, 0.6, 0.075, 6.0, VH.TRACK, 6, 941)
	var hl: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 9), 0.58, 0.33, 4.0, rot, hull, 0.08, 943)
	if wreck:
		VH._scorch(cv, hl)
	else:
		_hull_dress_a(cv, hl, rot, hull, 944)
		D.hatch(cv, hl.top, 0.86, 0.15, 0.97, 0.4, hull)
		D.grille(cv, hl.top, 0.02, 0.2, 0.12, 0.8, hull, 3)
		for sd in hl.sides:
			var q: PackedVector2Array = sd.quad
			if absf(_fw(sd, rot)) < 0.3:
				_team(cv, _subf(sd, rot, 0.0, 0.0, 1.0, 1.0), 0.1, 0.3, 0.9, 0.75)
			elif _fw(sd, rot) > 0.7:
				for u in [0.3, 0.42]:
					var vp: Vector2 = q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), 0.8)
					cv.px(int(vp.x), int(vp.y), D.VISION)
	# launch beam pivot on the bow
	var steel: Color = VH.GUNMETAL if not wreck else VH.BURNT
	for s: float in [-1.0, 1.0]:
		var a := D.sp(o, rot, 0.5, 0.12 * s, 13)
		var b := D.sp(o, rot, 0.62, 0.12 * s, 4) if dep else D.sp(o, rot, 0.54, 0.12 * s, 16)
		_tube(cv, a, b, steel, 2)
	if dep:
		for s: float in [-1.0, 1.0]:  # empty cradle rails
			P.box(cv, o, D.w(rot, -0.08, 0.2 * s, 13), 0.46, 0.03, 2.0, rot, steel, 0.05, 945)
		D.stowage(cv, o, rot, -0.45, 0.0, 13, 0.06, 0.12, 3.0, false, false)
	else:
		_bridge_folded(cv, o, rot, hull, wreck)
	if dep and front:
		_bridge_flat(cv, o, rot, hull)
	cv.outline(OUTL)
	if wreck:
		V.soot(cv, D.sp(o, rot, -0.1, 0.0, 22), 7.0, 949)


static func _truss(cv, q: PackedVector2Array, n: int, col: Color) -> void:
	for i in n:
		var u0 := float(i) / n
		var u1 := float(i + 1) / n
		var a: Vector2 = q[0].lerp(q[1], u0).lerp(q[3].lerp(q[2], u0), 0.15 if i % 2 == 0 else 0.85)
		var b: Vector2 = q[0].lerp(q[1], u1).lerp(q[3].lerp(q[2], u1), 0.85 if i % 2 == 0 else 0.15)
		cv.line_v(a, b, col)


static func _treadways(cv, top: PackedVector2Array, bc: Color, ribs: int) -> void:
	for lane in [[0.08, 0.4], [0.6, 0.92]]:
		var lq := P.sub(top, 0.01, lane[0], 0.99, lane[1])
		cv.poly(lq, P.mul(bc, 0.8))
		for i in ribs:
			var u := (i + 0.5) / ribs
			cv.line_v(lq[0].lerp(lq[1], u), lq[3].lerp(lq[2], u), P.mul(bc, 0.66))
	var h := P.sub(top, 0.5, 0.0, 0.5, 1.0)
	cv.line_v(h[0], h[3], P.mul(bc, 1.3))  # scissor hinge


static func _bridge_folded(cv, o: Vector2, rot: float, hull: Color, wreck: bool) -> void:
	var bc: Color = P.mul(hull, 1.07) if not wreck else VH.BURNT
	for layer in 2:
		var b: Dictionary = P.box(cv, o, D.w(rot, -0.1, 0.0, 13.5 + layer * 3.5), 0.58, 0.3, 3.5, rot,
			bc if layer == 1 else P.mul(bc, 0.92), 0.07, 946 + layer)
		if wreck:
			V.scorch(cv, b.top)
			continue
		for sd in b.sides:
			var q: PackedVector2Array = sd.quad
			if absf(_fw(sd, rot)) < 0.3:
				_truss(cv, q, 12, P.mul(bc, 0.66))
			else:
				var c: Vector2 = (q[0] + q[2]) * 0.5
				cv.px(int(c.x), int(c.y), D.DARK)
		if layer == 1:
			D.box_edges(cv, b, bc, 948)
			_treadways(cv, b.top, bc, 10)
			_team(cv, b.top, 0.44, 0.42, 0.56, 0.58)


static func _bridge_flat(cv, o: Vector2, rot: float, hull: Color) -> void:
	var bc: Color = P.mul(hull, 1.07)
	for e in [0.49, 1.81]:  # end ramps
		P.box(cv, o, D.w(rot, e, 0.0, 0), 0.04, 0.24, 1.5, rot, P.mul(bc, 0.85), 0.05, 950)
	var b: Dictionary = P.box(cv, o, D.w(rot, 1.15, 0.0, 0.5), 0.62, 0.24, 3.0, rot, bc, 0.07, 951)
	for sd in b.sides:
		if absf(_fw(sd, rot)) < 0.3:
			_truss(cv, sd.quad, 20, P.mul(bc, 0.66))
	D.box_edges(cv, b, bc, 952)
	_treadways(cv, b.top, bc, 18)


# ================================================================ a_command_vehicle
## 8x8 armoured command post: raised rear compartment, RWS, folded mast + dish; "deployed" raises the
## telescopic mast and the satellite dish.
static func command_vehicle(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = VH.BURNT if wreck else VH.HULL
	var dep := f == 3 and not wreck
	_shadow(cv, o, rot, [[0.0, 0.0, 0.0, 0.58, 0.29, 9.0], [-0.14, 0.0, 9.0, 0.42, 0.27, 6.0]])
	var fwds := [-0.42, -0.2, 0.14, 0.36]
	_wheels8(cv, o, rot, f, wreck, false, fwds)
	var lo: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 3), 0.56, 0.26, 6.0, rot, hull, 0.08, 961)
	if wreck:
		VH._scorch(cv, lo)
	else:
		_hull_dress_a(cv, lo, rot, hull, 962)
		for sd in lo.sides:
			var q: PackedVector2Array = sd.quad
			if absf(_fw(sd, rot)) < 0.3:
				D.mud(cv, q, 963 + int(q[0].x), 0.4)
			elif _fw(sd, rot) > 0.7:
				for u in [0.12, 0.88]:
					var lp: Vector2 = q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), 0.6)
					cv.px(int(lp.x), int(lp.y), Color8(226, 214, 160))
		D.hatch(cv, lo.top, 0.84, 0.14, 0.96, 0.42, hull)
		cv.px(int(P.sub(lo.top, 0.97, 0.3, 0.97, 0.3)[0].x), int(P.sub(lo.top, 0.97, 0.3, 0.97, 0.3)[0].y), D.VISION)
	var up: Dictionary = P.box(cv, o, D.w(rot, -0.14, 0.0, 9), 0.42, 0.27, 6.0, rot, P.mul(hull, 1.02), 0.08, 964)
	if wreck:
		VH._scorch(cv, up)
	else:
		D.box_edges(cv, up, hull, 965)
		for sd in up.sides:
			var q: PackedVector2Array = sd.quad
			var d := _fw(sd, rot)
			if absf(d) < 0.3:
				_team(cv, _subf(sd, rot, 0.0, 0.0, 1.0, 1.0), 0.5, 0.42, 0.95, 0.72)
				cv.poly(_subf(sd, rot, 0.08, 0.15, 0.4, 0.62), P.mul(hull, 0.82))  # side stowage bin
				var ln := _subf(sd, rot, 0.08, 0.62, 0.4, 0.62)
				cv.line_v(ln[0], ln[1], P.mul(hull, 1.22))
			elif d < -0.7:  # rear ramp door
				var dq := P.sub(q, 0.2, 0.0, 0.8, 0.9)
				cv.poly(dq, P.mul(hull, 0.78))
				cv.line_v(dq[3], dq[2], P.mul(hull, 1.2))
		D.grille(cv, up.top, 0.08, 0.6, 0.28, 0.9, hull, 3)  # A/C + generator unit
		D.hatch(cv, up.top, 0.62, 0.55, 0.82, 0.85, hull)
	_wheels8(cv, o, rot, f, wreck, true, fwds)
	if wreck:
		cv.outline(OUTL)
		V.soot(cv, D.sp(o, rot, -0.1, 0.0, 16), 6.0, 969)
		return
	var steel := VH.GUNMETAL
	# remote weapon station (front of the roof)
	var rw := D.sp(o, rot, 0.16, 0.08, 15)
	var gtip := D.sp(o, rot, 0.4, 0.08, 17)
	if not D.faces_cam(rot, 1.0, 0.0):
		cv.line_v(D.sp(o, rot, 0.18, 0.08, 17), gtip, steel)
	P.box(cv, o, D.w(rot, 0.14, 0.08, 15), 0.045, 0.045, 3.0, rot, P.mul(hull, 0.95), 0.05, 966)
	cv.px(int(rw.x) + 1, int(rw.y) - 2, D.VISION)
	if D.faces_cam(rot, 1.0, 0.0):
		cv.line_v(D.sp(o, rot, 0.18, 0.08, 17), gtip, steel)
	var dish_c := D.w(rot, 0.0, -0.13, 15)
	var mast_b := D.sp(o, rot, -0.42, 0.12, 15)
	if dep:
		var mt := mast_b + Vector2(0, -24)
		for g in [D.sp(o, rot, -0.54, 0.26, 15), D.sp(o, rot, -0.3, -0.05, 15)]:
			cv.line_v(mt + Vector2(0, 8), g, Color(0.12, 0.12, 0.1, 0.5))  # guy lines
		cv.line_v(mast_b, mt, steel)
		cv.line_v(mast_b + Vector2(1, 0), mt + Vector2(1, 8), P.mul(steel, 0.75))
		for j in [8, 16]:
			cv.rect(int(mast_b.x) - 1, int(mast_b.y) - j, 3, 1, P.mul(steel, 1.3))
		cv.line_v(mt + Vector2(-3, 1), mt + Vector2(4, 1), steel)  # antenna head cross-arm
		cv.rect(int(mt.x) - 1, int(mt.y) - 2, 3, 3, Color8(70, 72, 66))
		cv.line_v(mt + Vector2(-3, 1), mt + Vector2(-3, -4), Color8(30, 31, 29))
		cv.line_v(mt + Vector2(4, 1), mt + Vector2(4, -4), Color8(30, 31, 29))
		var dp := P.proj(o, dish_c) + Vector2(0, -5)
		cv.line_v(P.proj(o, dish_c), dp, steel)
		cv.ellipse(dp.x, dp.y - 1, 4.2, 3.6, Color8(176, 178, 168))
		cv.ellipse(dp.x + 0.6, dp.y - 0.6, 2.6, 2.2, Color8(150, 152, 144))
		cv.px(int(dp.x) - 2, int(dp.y) - 3, Color8(214, 216, 206))
		cv.px(int(dp.x) + 1, int(dp.y), Color8(60, 60, 56))  # feed horn
	else:
		var mf := D.sp(o, rot, 0.06, 0.12, 16)
		_tube(cv, mast_b, mf, steel, 2)  # mast folded along the roof
		cv.rect(int(mf.x) - 1, int(mf.y) - 2, 3, 2, Color8(70, 72, 66))
		var dp := P.proj(o, dish_c)
		cv.ellipse(dp.x, dp.y - 1.5, 3.6, 1.8, Color8(160, 162, 152))  # dish stowed face-up
		cv.ellipse(dp.x, dp.y - 1.5, 2.0, 0.9, Color8(138, 140, 132))
	D.antenna(cv, D.sp(o, rot, -0.5, -0.22, 15), 14 if dep else 11, false)
	D.antenna(cv, D.sp(o, rot, -0.5, 0.24, 15), 12 if dep else 9, false)
	if dep:
		D.antenna(cv, D.sp(o, rot, 0.3, -0.22, 9), 10, false)
	cv.outline(OUTL)
	if f == 2:
		L.flash(cv, gtip, 0.9)


static func _wheels8(cv, o: Vector2, rot: float, f: int, wreck: bool, near: bool, fwds: Array) -> void:
	for s: float in [-1.0, 1.0]:
		if D.faces_cam(rot, 0.0, s) != near:
			continue
		for i in fwds.size():
			var c := D.sp(o, rot, fwds[i], 0.27 * s, 3)
			D.road_wheel(cv, c, 3.1, 3.0, f, wreck)
			if near and not wreck and P.hn(i, int(s), 967) > 0.4:
				cv.px(int(c.x) - 1, int(c.y) + 2, Color(D.MUD.r, D.MUD.g, D.MUD.b, 0.8))
				cv.px(int(c.x) + 1, int(c.y) + 2, Color(D.MUD_D.r, D.MUD_D.g, D.MUD_D.b, 0.7))


# ================================================================ a_ugv
## Small tracked robot: two track pods, flat cargo deck, remote weapon station with sensor head.
static func ugv(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = VH.BURNT if wreck else VH.HULL
	_shadow(cv, o, rot, [[0.0, 0.0, 0.0, 0.3, 0.22, 7.0], [-0.02, 0.0, 6.0, 0.08, 0.08, 6.0]])
	for near in [false, true]:
		for s: float in [-1.0, 1.0]:
			if D.faces_cam(rot, 0.0, s) != near:
				continue
			var tr: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.15 * s, 0), 0.3, 0.065, 5.0, rot, VH.TRACK, 0.05, 951)
			for sd in tr.sides:
				if absf(_fw(sd, rot)) < 0.3:
					D.track_side(cv, sd.quad, f, wreck, 3)
			var pl: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.15 * s, 5), 0.29, 0.07, 1.2, rot, hull, 0.06, 952)
			if not wreck:
				D.box_edges(cv, pl, hull, 953)
		if not near:
			var dk: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 2.5), 0.27, 0.09, 3.0, rot, P.mul(hull, 0.9), 0.06, 954)
			if not wreck:
				_team(cv, dk.top, 0.55, 0.15, 0.9, 0.85)
	var steel: Color = VH.GUNMETAL if not wreck else VH.BURNT
	var front := D.faces_cam(rot, 1.0, 0.0)
	var tip := D.sp(o, rot, 0.3, 0.0, 10)
	var base := D.sp(o, rot, 0.04, 0.0, 9.5)
	P.box(cv, o, D.w(rot, -0.06, 0.0, 6), 0.08, 0.07, 2.5, rot, steel, 0.05, 955)
	if not front:
		_tube(cv, base, tip, steel, 2)
	var cr: Dictionary = P.box(cv, o, D.w(rot, -0.04, 0.0, 8.5), 0.07, 0.045, 3.0, rot, hull, 0.06, 956)
	var sn: Dictionary = P.box(cv, o, D.w(rot, -0.02, -0.075, 8.5), 0.03, 0.025, 3.0, rot, steel, 0.05, 957)
	if not wreck:
		D.box_edges(cv, cr, hull, 958)
		for sd in sn.sides:
			if _fw(sd, rot) > 0.7:
				var c: Vector2 = ((sd.quad as PackedVector2Array)[0] + (sd.quad as PackedVector2Array)[2]) * 0.5
				cv.px(int(c.x), int(c.y), D.VISION)
		D.stowage(cv, o, rot, -0.22, 0.0, 5.5, 0.06, 0.08, 2.0, false, false)
	if front:
		_tube(cv, base, tip, steel, 2)
	if not wreck:
		D.antenna(cv, D.sp(o, rot, -0.26, 0.16, 6), 9, false)
		D.antenna(cv, D.sp(o, rot, -0.26, -0.16, 6), 6, false)
	cv.outline(OUTL)
	if f == 2 and not wreck:
		L.flash(cv, tip, 0.8)


# ================================================================ b_landship
## Human B super-heavy: rhomboid-tall tracks with riveted guards, sponson guns each side, casemate,
## main turret with a long gun, smokestack venting coal-black smoke.
static func landship(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = V.BURNT if wreck else V.HULL
	var trot := rot + (0.7 if wreck else 0.0)
	_shadow(cv, o, rot, [[0.0, 0.0, 0.0, 0.86, 0.45, 7.0], [-0.12, 0.0, 12.0, 0.5, 0.25, 5.0], [0.12, 0.0, 16.0, 0.22, 0.2, 5.0]])
	for near in [false, true]:
		if near:
			var hb: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 3), 0.8, 0.28, 11.0, rot, hull, 0.1, 1001)
			if wreck:
				V.scorch(cv, hb.top)
			else:
				for sd in hb.sides:
					var q: PackedVector2Array = sd.quad
					if _fw(sd, rot) > 0.7:  # bow: vision slits + ball MG
						cv.line_v(P.sub(q, 0.2, 0.72, 0.8, 0.72)[0], P.sub(q, 0.2, 0.72, 0.8, 0.72)[1], D.DARK)
						var bm: Vector2 = q[0].lerp(q[1], 0.3).lerp(q[3].lerp(q[2], 0.3), 0.45)
						cv.ellipse(bm.x, bm.y, 1.6, 1.4, P.mul(hull, 0.7))
						cv.px(int(bm.x), int(bm.y), V.GUNMETAL)
						D.tow_hooks(cv, q)
						V.rivets(cv, q, 0.9, 7, hull)
					else:
						_dress_b(cv, sd, rot, hull, 1002, 12)
				D.box_edges(cv, hb, hull, 1005)
				D.grille(cv, hb.top, 0.02, 0.25, 0.16, 0.75, hull, 5)
		for s: float in [-1.0, 1.0]:
			if D.faces_cam(rot, 0.0, s) != near:
				continue
			var tr: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.36 * s, 0), 0.86, 0.09, 9.0, rot, V.TRACK, 0.05, 1006)
			for sd in tr.sides:
				if absf(_fw(sd, rot)) < 0.3:
					if not wreck:
						D.mud(cv, sd.quad, 1007, 0.6)
					D.track_side(cv, sd.quad, f, wreck, 9)
			var gd: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.36 * s, 9), 0.84, 0.1, 2.0, rot, P.mul(hull, 0.95), 0.08, 1008)
			if wreck:
				V.scorch(cv, gd.top)
			else:
				for sd in gd.sides:
					V.rivets(cv, sd.quad, 0.5, 14, hull)
				D.box_edges(cv, gd, hull, 1009)
			_sponson(cv, o, rot, s, f, wreck, hull)
	var cm: Dictionary = P.box(cv, o, D.w(rot, -0.12, 0.0, 14), 0.5, 0.25, 5.0, rot, P.mul(hull, 1.03), 0.1, 1010)
	if wreck:
		V.scorch(cv, cm.top)
	else:
		for sd in cm.sides:
			var q: PackedVector2Array = sd.quad
			if absf(_fw(sd, rot)) < 0.3:
				V.patch(cv, q, 0.55, 0.2, 0.75, 0.7, V.PRIMER, 1011)
				for u in [0.18, 0.36, 0.82]:
					var sl := _subf(sd, rot, u, 0.55, u + 0.06, 0.55)
					cv.line_v(sl[0], sl[1], D.DARK)
			V.rivets(cv, q, 0.85, 9, hull)
			V.streaks(cv, q, 1012)
		D.box_edges(cv, cm, hull, 1013)
		D.hatch(cv, cm.top, 0.08, 0.2, 0.26, 0.45, hull)
		_team(cv, cm.top, 0.3, 0.55, 0.62, 0.85)
	# smokestack
	var stk: Dictionary = P.box(cv, o, D.w(rot, -0.48, 0.1, 19), 0.045, 0.045, 10.0, rot, P.mul(V.GUNMETAL, 1.15) if not wreck else V.BURNT, 0.06, 1014)
	var st_top := D.sp(o, rot, -0.48, 0.1, 29)
	if not wreck:
		for sd in stk.sides:
			cv.line_v((sd.quad as PackedVector2Array)[0].lerp(sd.quad[3], 0.6), (sd.quad as PackedVector2Array)[1].lerp(sd.quad[2], 0.6), V.RUST)
		cv.rect(int(st_top.x) - 1, int(st_top.y) - 1, 3, 2, V.SOOT)
	var toward := cos(trot) + sin(trot) > 0.0
	if not toward:
		_ls_barrel(cv, o, trot, hull, wreck)
	var tu: Dictionary = P.box(cv, o, D.w(trot, 0.12, 0.0, 19), 0.22, 0.2, 7.0, trot, hull, 0.1, 1015)
	if wreck:
		V.scorch(cv, tu.top)
	else:
		for sd in tu.sides:
			var q: PackedVector2Array = sd.quad
			_team(cv, q, 0.1, 0.14, 0.9, 0.66)
			V.rivets(cv, q, 0.84, 6, hull)
			V.streaks(cv, q, 1016)
		D.box_edges(cv, tu, hull, 1017)
		D.cupola(cv, o, trot, -0.04, 0.1, 26, hull, false)
		D.antenna(cv, D.sp(o, trot, -0.16, -0.14, 26), 10, false)
	if toward:
		_ls_barrel(cv, o, trot, hull, wreck)
	cv.outline(OUTL_B)
	if wreck:
		V.soot(cv, D.sp(o, rot, 0.0, 0.0, 22), 9.0, 1018)
		V.soot(cv, D.sp(o, rot, 0.5, 0.2, 12), 5.0, 1019)
		return
	V.soot(cv, st_top + Vector2(0, 2), 3.0, 1020)
	var puffs := 3 if f == 1 else 1
	for i in puffs:
		L.puff(cv, st_top + Vector2(2 + i * 3, -3 - i * 3), 2.2 + i * 0.6, 0.5 - i * 0.08, Color(0.24, 0.22, 0.2))
	if f == 2:
		var tip := D.sp(o, trot, 1.03, 0.0, 22)
		L.flash(cv, tip, 1.5)
		L.puff(cv, tip + Vector2(2, -3), 2.6, 0.45)
		for s: float in [-1.0, 1.0]:
			L.flash(cv, D.sp(o, rot, 0.4, 0.55 * s, 13), 0.7)


static func _sponson(cv, o: Vector2, rot: float, s: float, f: int, wreck: bool, hull: Color) -> void:
	var sp: Dictionary = P.box(cv, o, D.w(rot, 0.2, 0.38 * s, 11), 0.13, 0.08, 5.5, rot, P.mul(hull, 1.02), 0.1, 1021)
	if wreck:
		V.scorch(cv, sp.top)
		return
	for sd in sp.sides:
		V.rivets(cv, sd.quad, 0.82, 4, hull)
	D.box_edges(cv, sp, hull, 1022)
	var a := D.sp(o, rot, 0.24, 0.45 * s, 13.5)
	var b := D.sp(o, rot, 0.4, 0.55 * s, 13.5)
	_tube(cv, a, b, V.GUNMETAL, 2)
	cv.px(int(b.x), int(b.y) - 1, P.mul(V.GUNMETAL, 1.4))


static func _ls_barrel(cv, o: Vector2, trot: float, hull: Color, wreck: bool) -> void:
	var col: Color = V.GUNMETAL if not wreck else V.BURNT
	var z := 20.5 if not wreck else 15.0
	P.box(cv, o, D.w(trot, 0.34, 0.0, z - 2.5), 0.04, 0.12, 5.5, trot, P.mul(hull, 0.9), 0.05, 1023)  # mantlet
	P.box(cv, o, D.w(trot, 0.66, 0.0, z), 0.31, 0.03, 2.2, trot, col, 0.04, 1024)
	P.box(cv, o, D.w(trot, 0.6, 0.0, z - 0.4), 0.04, 0.045, 3.0, trot, P.mul(col, 1.1), 0.04, 1025)  # bore evacuator
	P.box(cv, o, D.w(trot, 0.98, 0.0, z - 0.6), 0.04, 0.055, 3.2, trot, P.mul(col, 1.15), 0.04, 1026)  # muzzle brake


# ================================================================ b_flak_halftrack
## The shipped b_halftrack cab + running gear (g4_units_b) with a low open bed and a quad 20 mm flak mount.
static func flak_halftrack(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var col: Color = V.BURNT if wreck else V.HULL
	P.box_shadow(cv, o, D.w(rot, 0.0, 0.0, 2), 0.54, 0.22, 10.0, rot)
	P.box_shadow(cv, o, D.w(rot, -0.22, 0.0, 12), 0.12, 0.14, 8.0, rot)
	cv.flush_shadow()
	for s: float in [-1.0, 1.0]:
		if not D.faces_cam(rot, 0.0, s):
			G4B._running(cv, o, rot, s, f, wreck)
	if D.faces_cam(rot, 1.0, 0.0):
		_flak_bed(cv, o, rot, col, wreck)
		G4B._cab(cv, o, rot, col, wreck)
	else:
		G4B._cab(cv, o, rot, col, wreck)
		_flak_bed(cv, o, rot, col, wreck)
	var tips := _quad_mount(cv, o, rot, f, wreck)
	for s: float in [-1.0, 1.0]:
		if D.faces_cam(rot, 0.0, s):
			G4B._running(cv, o, rot, s, f, wreck)
	cv.outline(OUTL_B)
	if wreck:
		V.soot(cv, D.sp(o, rot, -0.15, 0.0, 12), 6.0, 1041)
	elif f == 2:
		for i in tips.size():
			var t: Vector2 = tips[i]
			if i % 2 == 0:
				L.flash(cv, t, 0.8)
			else:
				cv.px(int(t.x), int(t.y) - 2, Color8(255, 236, 160))
		L.puff(cv, (tips[0] as Vector2) + Vector2(1, -3), 2.2, 0.4)


static func _flak_bed(cv, o: Vector2, rot: float, col: Color, wreck: bool) -> void:
	var bay: Dictionary = P.box(cv, o, D.w(rot, -0.2, 0.0, 4), 0.32, 0.2, 5.0, rot, col, 0.08, 1042)
	for sd in bay.sides:
		var q: PackedVector2Array = sd.quad
		if wreck:
			V.scorch(cv, q)
		elif absf(_fw(sd, rot)) < 0.3:
			_team(cv, q, 0.08, 0.35, 0.92, 0.7)
			V.rivets(cv, q, 0.88, 7, col)
			V.patch(cv, q, 0.66, 0.08, 0.9, 0.3, V.RUST, 1043)
			V.streaks(cv, q, 1044)
		else:
			V.rivets(cv, q, 0.85, 4, col)
	cv.poly(P.sub(bay.top, 0.07, 0.1, 0.93, 0.9), P.mul(col, 0.45) if not wreck else Color8(30, 28, 26))
	if not wreck:
		for u in [0.12, 0.88]:  # ready-ammo boxes along the bed walls
			for v in [0.22, 0.78]:
				var p: Vector2 = P.sub(bay.top, u, v, u, v)[0]
				cv.rect(int(p.x) - 1, int(p.y) - 1, 3, 2, D.STOW)
				cv.px(int(p.x) - 1, int(p.y) - 1, P.mul(D.STOW, 1.3))


## Quad 20 mm mount on a pedestal: carriage, riveted gun shield, gunner, 2 x 2 barrels at high elevation.
static func _quad_mount(cv, o: Vector2, rot: float, f: int, wreck: bool) -> Array:
	var gun: Color = V.GUNMETAL if not wreck else V.BURNT
	var hull: Color = V.HULL if not wreck else V.BURNT
	var grot := rot + (0.9 if wreck else 0.3)
	var c := D.w(rot, -0.22, 0.0, 0)
	var toward := cos(grot) + sin(grot) > 0.0
	var rec := 0.03 if f == 2 else 0.0
	var tips: Array = []
	var guns := func() -> void:
		for zz in [15.0, 18.0]:
			for rr in [-0.045, 0.045]:
				var a := P.proj(o, c + D.w(grot, 0.04 - rec, rr, zz))
				var b := P.proj(o, c + D.w(grot, 0.34 - rec, rr, zz + (11.0 if not wreck else 3.0)))
				cv.line_v(a, b, gun)
				cv.line_v(a + Vector2(1, 0), b + Vector2(1, 0), P.mul(gun, 0.7))
				cv.px(int(b.x), int(b.y), P.mul(gun, 1.5))
				tips.append(b)
	P.box(cv, o, c + Vector3(0, 0, 9), 0.08, 0.08, 3.5, rot, gun, 0.06, 1045)
	if not toward:
		guns.call()
	var car: Dictionary = P.box(cv, o, c + D.w(grot, -0.03, 0.0, 12.5), 0.09, 0.1, 3.0, grot, hull, 0.08, 1046)
	if not wreck:
		D.box_edges(cv, car, hull, 1047)
		var hp := P.proj(o, c + D.w(grot, -0.08, 0.0, 17))  # gunner's helmet behind the shield
		cv.rect(int(hp.x) - 1, int(hp.y) - 1, 3, 2, B_HELM)
		cv.px(int(hp.x) - 1, int(hp.y) - 1, P.mul(B_HELM, 1.35))
	var sh: Dictionary = P.box(cv, o, c + D.w(grot, 0.07, 0.0, 12), 0.012, 0.14, 6.0, grot, P.mul(hull, 1.05), 0.06, 1048)
	if not wreck:
		for sd in sh.sides:
			V.rivets(cv, sd.quad, 0.8, 5, hull)
		D.box_edges(cv, sh, hull, 1049, 0.25)
	if toward:
		guns.call()
	return tips


# ================================================================ b_armored_dozer
## Tracked dozer: big riveted blade on push arms + rams, armoured engine hood, slit-window armoured cab,
## rear ripper, soot stack. "work": blade down, earth piling up ahead of it.
static func armored_dozer(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = V.BURNT if wreck else V.HULL
	var bz := 0.0 if (f == 2 or wreck) else (3.0 if f == 1 else 1.5)
	_shadow(cv, o, rot, [[0.0, 0.0, 0.0, 0.48, 0.34, 8.0], [-0.24, 0.0, 8.0, 0.17, 0.22, 9.0], [0.62, 0.0, 0.0, 0.04, 0.42, 8.0]])
	var front := D.faces_cam(rot, 1.0, 0.0)
	if not front:
		_blade(cv, o, rot, f, wreck, hull, bz, front)
	_tracks(cv, o, rot, f, wreck, false, 0.0, 0.24, 0.46, 0.1, 7.0, V.TRACK, 5, 1061)
	if front:
		_dozer_cab(cv, o, rot, hull, wreck)
		_dozer_hood(cv, o, rot, hull, wreck)
	else:
		_dozer_hood(cv, o, rot, hull, wreck)
		_dozer_cab(cv, o, rot, hull, wreck)
	_tracks(cv, o, rot, f, wreck, true, 0.0, 0.24, 0.46, 0.1, 7.0, V.TRACK, 5, 1061)
	var steel: Color = V.GUNMETAL if not wreck else V.BURNT
	_tube(cv, D.sp(o, rot, -0.46, 0.0, 7), D.sp(o, rot, -0.58, 0.0, 0), steel, 2)  # ripper shank
	var ep := D.sp(o, rot, 0.2, 0.1, 18)
	P.box(cv, o, D.w(rot, 0.2, 0.1, 12), 0.025, 0.025, 6.0, rot, steel, 0.05, 1062)
	if front:
		_blade(cv, o, rot, f, wreck, hull, bz, front)
	cv.outline(OUTL_B)
	if wreck:
		V.soot(cv, D.sp(o, rot, -0.2, 0.0, 16), 7.0, 1063)
	else:
		V.soot(cv, ep + Vector2(0, 1), 2.5, 1064)
		if f != 0:
			L.puff(cv, ep + Vector2(2, -4), 2.4, 0.45, Color(0.24, 0.22, 0.2))
		if f == 2:
			L.puff(cv, D.sp(o, rot, 0.8, 0.3, 2), 3.0, 0.35, Color(0.62, 0.52, 0.38))
			L.puff(cv, D.sp(o, rot, 0.8, -0.32, 2), 2.6, 0.3, Color(0.62, 0.52, 0.38))


static func _dozer_hood(cv, o: Vector2, rot: float, hull: Color, wreck: bool) -> void:
	var hd: Dictionary = P.box(cv, o, D.w(rot, 0.12, 0.0, 6), 0.3, 0.17, 6.0, rot, hull, 0.1, 1065)
	if wreck:
		V.scorch(cv, hd.top)
		return
	for sd in hd.sides:
		if absf(_fw(sd, rot)) < 0.3:
			_dress_b(cv, sd, rot, hull, 1066, 6)
			_team(cv, _subf(sd, rot, 0.0, 0.0, 1.0, 1.0), 0.05, 0.5, 0.45, 0.72)
		else:
			V.rivets(cv, sd.quad, 0.85, 4, hull)
	D.box_edges(cv, hd, hull, 1067)
	D.grille(cv, hd.top, 0.2, 0.2, 0.7, 0.8, hull, 5)


static func _dozer_cab(cv, o: Vector2, rot: float, hull: Color, wreck: bool) -> void:
	var cb: Dictionary = P.box(cv, o, D.w(rot, -0.25, 0.0, 7), 0.17, 0.22, 10.0, rot, P.mul(hull, 1.03), 0.1, 1068)
	if wreck:
		V.scorch(cv, cb.top)
		return
	for sd in cb.sides:
		var q: PackedVector2Array = sd.quad
		var sl := P.sub(q, 0.18, 0.68, 0.82, 0.68)  # armoured vision slit
		cv.line_v(sl[0], sl[1], Color8(22, 20, 18))
		cv.px(int(sl[0].x + 1), int(sl[0].y), Color8(120, 150, 150))
		V.rivets(cv, q, 0.92, 5, hull)
		V.rivets(cv, q, 0.12, 5, hull)
		V.streaks(cv, q, 1069)
		if absf(_fw(sd, rot)) < 0.3:
			V.patch(cv, q, 0.2, 0.15, 0.5, 0.5, V.RUST, 1070)
	D.box_edges(cv, cb, hull, 1071)
	_team(cv, cb.top, 0.2, 0.2, 0.8, 0.8)
	D.antenna(cv, D.sp(o, rot, -0.36, -0.16, 17), 8, false)


static func _blade(cv, o: Vector2, rot: float, f: int, wreck: bool, hull: Color, bz: float, front: bool) -> void:
	var steel: Color = V.GUNMETAL if not wreck else V.BURNT
	var bc: Color = P.mul(hull, 0.96)
	for s: float in [-1.0, 1.0]:
		_tube(cv, D.sp(o, rot, 0.05, 0.31 * s, 5), D.sp(o, rot, 0.58, 0.31 * s, bz + 3), P.mul(hull, 0.8), 2)  # push arms
		_tube(cv, D.sp(o, rot, 0.38, 0.12 * s, 12), D.sp(o, rot, 0.58, 0.14 * s, bz + 8), steel, 2)  # hydraulic rams
	var work := f == 2 and not wreck
	if work and not front:
		_mound(cv, o, rot)
	var lo: Dictionary = P.box(cv, o, D.w(rot, 0.6, 0.0, bz), 0.035, 0.42, 6.0, rot, bc, 0.1, 1072)
	var lip: Dictionary = P.box(cv, o, D.w(rot, 0.63, 0.0, bz + 6), 0.03, 0.42, 3.0, rot, P.mul(bc, 1.06), 0.1, 1073)
	if wreck:
		V.scorch(cv, lip.top)
	else:
		for r: Dictionary in [lo, lip]:
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				var d := _fw(sd, rot)
				if d > 0.7:  # concave mouldboard: shaded bands, worn steel cutting edge
					cv.line_v(q[0].lerp(q[3], 0.55), q[1].lerp(q[2], 0.55), P.mul(bc, 0.78))
					V.streaks(cv, q, 1074)
					if r == lo:
						cv.line_v(q[0] + Vector2(0, -1), q[1] + Vector2(0, -1), STEEL)
						V.patch(cv, q, 0.68, 0.3, 0.86, 0.8, V.RUST, 1075)
				elif d < -0.7:  # back: stiffener ribs
					for i in 5:
						var u := (i + 0.5) / 5.0
						cv.line_v(q[0].lerp(q[1], u), q[3].lerp(q[2], u), P.mul(bc, 0.7))
					V.rivets(cv, q, 0.8, 8, bc)
		D.box_edges(cv, lip, bc, 1076)
	if work and front:
		_mound(cv, o, rot)


static func _mound(cv, o: Vector2, rot: float) -> void:
	for i in 7:
		var r := -0.34 + i * 0.113
		var p := D.sp(o, rot, 0.74 + P.hn(i, 1, 1077) * 0.06, r, 0)
		var h := 2.0 + P.hn(i, 2, 1077) * 2.0
		cv.ellipse(p.x, p.y - h * 0.5, 3.6, 1.6 + h * 0.5, D.MUD_D)
		cv.ellipse(p.x - 0.6, p.y - h * 0.5 - 0.6, 2.8, 1.2 + h * 0.4, D.MUD)
		cv.px(int(p.x) - 1, int(p.y - h), P.mul(D.MUD, 1.3))


# ================================================================ b_salvage_crane
## Human B truck chassis (g3b_human_b._truck) with a flat bed, slewing crane house and a lattice boom;
## "work": outriggers down, boom swung out, a burnt wreck hanging from the hook.
static func salvage_crane(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var work := f == 2 and not wreck
	var crot := rot + (PI * 0.72 if work else (0.5 if wreck else 0.0))
	var cb := D.w(rot, -0.3, 0.0, 0)
	var bed_top := 4.5 + 2.5
	HB._truck(cv, o, rot, f, wreck, 10.0, func(body: Color) -> void:
		var r: Dictionary = TRK._bed_box(cv, o, rot, body, wreck, 2.5, 1081)
		cv.poly(P.sub(r.top, 0.04, 0.06, 0.96, 0.94), P.mul(body, 0.7))
		if not wreck:
			for v in [0.3, 0.7]:
				var ln := P.sub(r.top, 0.05, v, 0.55, v)
				cv.line_v(ln[0], ln[1], P.mul(body, 0.55))
		_crane_house(cv, o, cb, crot, body, wreck, bed_top))
	var boom_c: Color = P.mix(V.HULL, OCHRE, 0.55) if not wreck else V.BURNT
	if work:
		for s: float in [-1.0, 1.0]:  # outriggers
			for fwd in [-0.45, 0.05]:
				var a := D.sp(o, rot, fwd, 0.2 * s, 5)
				var b := D.sp(o, rot, fwd, 0.34 * s, 0)
				_tube(cv, a, b, V.GUNMETAL, 2)
				cv.rect(int(b.x) - 1, int(b.y), 3, 1, D.DARK)
	var piv := cb + D.w(crot, 0.04, 0.0, bed_top + 6)
	var tipw := cb + (D.w(crot, 0.6, 0.0, bed_top + 22) if work else D.w(crot, 0.68, 0.0, bed_top + 9))
	if wreck:
		tipw = cb + D.w(crot, 0.45, 0.0, bed_top + 3)
	_lattice(cv, P.proj(o, piv), P.proj(o, tipw), boom_c)
	var tp := P.proj(o, tipw)
	cv.rect(int(tp.x) - 1, int(tp.y) - 1, 3, 3, P.mul(boom_c, 0.8))  # sheave
	if work:
		var hook_w := Vector3(tipw.x, tipw.y, 13.0)
		var hp := P.proj(o, hook_w)
		cv.line_v(tp + Vector2(0, 1), hp, Color8(40, 38, 34))
		var lr: Dictionary = P.box(cv, o, Vector3(tipw.x, tipw.y, 4.0), 0.12, 0.1, 6.0, crot + 0.5, V.BURNT, 0.1, 1082)
		V.scorch(cv, lr.top)
		for sd in lr.sides:
			V.scorch(cv, sd.quad)
		var stub := P.proj(o, Vector3(tipw.x, tipw.y, 9.0))
		cv.line_v(stub, stub + Vector2(7, 2), Color8(48, 44, 40))  # bent gun stub
		for i in 4:
			var cp := hp.lerp(P.proj(o, Vector3(tipw.x, tipw.y, 10.0)) + Vector2(-3 + i * 2, 0), 1.0)
			cv.line_v(hp, cp, Color8(52, 50, 44))  # chain sling
		cv.px(int(hp.x), int(hp.y), Color8(150, 140, 110))
	elif not wreck:
		var hp2 := tp + Vector2(0, 4)
		cv.line_v(tp + Vector2(0, 1), hp2, Color8(40, 38, 34))
		cv.px(int(hp2.x), int(hp2.y), Color8(150, 140, 110))
	cv.outline(OUTL_B)
	if wreck:
		V.soot(cv, D.sp(o, rot, 0.0, 0.0, 12), 7.0, 1083)
	elif work:
		V.soot(cv, P.proj(o, Vector3(tipw.x, tipw.y, 8.0)), 3.0, 1084)


static func _crane_house(cv, o: Vector2, cb: Vector3, crot: float, body: Color, wreck: bool, bed_top: float) -> void:
	var col: Color = P.mul(V.HULL, 1.04) if not wreck else V.BURNT
	P.box(cv, o, cb + Vector3(0, 0, bed_top), 0.1, 0.1, 1.5, crot, V.GUNMETAL if not wreck else V.BURNT, 0.06, 1085)
	var hs: Dictionary = P.box(cv, o, cb + D.w(crot, -0.04, 0.0, bed_top + 1.5), 0.13, 0.1, 5.0, crot, col, 0.1, 1086)
	if wreck:
		V.scorch(cv, hs.top)
		return
	for sd in hs.sides:
		var q: PackedVector2Array = sd.quad
		V.rivets(cv, q, 0.85, 4, col)
		if absf((sd.n as Vector2).dot(Vector2(cos(crot), sin(crot)))) < 0.3:
			V.patch(cv, q, 0.15, 0.2, 0.45, 0.7, V.RUST, 1087)
			cv.line_v(q[0].lerp(q[3], 0.6).lerp(q[1].lerp(q[2], 0.6), 0.6), q[1].lerp(q[2], 0.6), Color8(22, 20, 18))
	D.box_edges(cv, hs, col, 1088)
	_team(cv, hs.top, 0.12, 0.18, 0.62, 0.82)
	V.soot(cv, P.proj(o, cb + D.w(crot, -0.12, 0.06, bed_top + 7)), 2.0, 1089)


static func _lattice(cv, a: Vector2, b: Vector2, col: Color) -> void:
	var n := (b - a).orthogonal().normalized()
	var a1 := a + n * 1.6
	var a2 := a - n * 1.6
	var b1 := b + n * 0.7
	var b2 := b - n * 0.7
	cv.line_v(a1, b1, P.mul(col, 1.2))
	cv.line_v(a2, b2, P.mul(col, 0.8))
	var seg := maxi(3, int(a.distance_to(b) / 3.0))
	for i in seg:
		var t0 := float(i) / seg
		var t1 := float(i + 1) / seg
		var p0: Vector2 = a1.lerp(b1, t0) if i % 2 == 0 else a2.lerp(b2, t0)
		var p1: Vector2 = a2.lerp(b2, t1) if i % 2 == 0 else a1.lerp(b1, t1)
		cv.line_v(p0, p1, col)


# ================================================================ b_moto_scouts
## Three B dispatch motorcycles in one frame: lead bike with a sidecar MG, two solo riders flanking.
const BIKES := [[0.2, -0.07, true], [-0.13, 0.27, false], [-0.18, -0.33, false]]


static func moto_scouts(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	for b: Array in BIKES:
		var sc: bool = b[2]
		P.box_shadow(cv, o, D.w(rot, b[0], b[1] + (0.05 if sc else 0.0), 0), 0.11, 0.1 if sc else 0.035, 9.0, rot)
	cv.flush_shadow()
	var order := [0, 1, 2]
	order.sort_custom(func(i: int, j: int) -> bool:
		var wi := D.w(rot, BIKES[i][0], BIKES[i][1])
		var wj := D.w(rot, BIKES[j][0], BIKES[j][1])
		return wi.x + wi.y < wj.x + wj.y)
	for i: int in order:
		_bike(cv, o, rot, f, wreck, BIKES[i][0], BIKES[i][1], BIKES[i][2], i)
	cv.outline(OUTL_B)
	if wreck:
		V.soot(cv, D.sp(o, rot, 0.2, 0.0, 4), 4.0, 1101)
		return
	if f == 1:
		for b: Array in BIKES:
			L.puff(cv, D.sp(o, rot, b[0] - 0.17, b[1], 2), 2.2, 0.3, Color(0.7, 0.62, 0.5))
			L.puff(cv, D.sp(o, rot, b[0] - 0.26, b[1] + 0.03, 3), 1.6, 0.22, Color(0.7, 0.62, 0.5))
	elif f == 2:
		L.flash(cv, D.sp(o, rot, 0.36, 0.03, 9.5), 0.8)


static func _bike(cv, o: Vector2, rot: float, f: int, wreck: bool, fw: float, rt: float, side: bool, i: int) -> void:
	var paint: Color = V.BURNT if wreck else P.mul(V.HULL, 0.82)
	if wreck:  # bikes on their sides, burnt, riders gone
		cv.ellipse(D.sp(o, rot, fw + 0.08, rt, 1).x, D.sp(o, rot, fw + 0.08, rt, 1).y, 2.0, 1.2, Color8(30, 26, 24))
		cv.ellipse(D.sp(o, rot, fw - 0.08, rt, 1).x, D.sp(o, rot, fw - 0.08, rt, 1).y, 2.0, 1.2, Color8(30, 26, 24))
		P.box(cv, o, D.w(rot + 0.3, fw, rt, 0), 0.07, 0.025, 2.0, rot + 0.3, paint, 0.08, 1102 + i)
		if side:
			P.box(cv, o, D.w(rot, fw, rt + 0.11, 0), 0.07, 0.035, 2.5, rot, paint, 0.08, 1105)
		return
	var sc_far := not D.faces_cam(rot, 0.0, 1.0)
	if side and sc_far:
		_sidecar(cv, o, rot, f, fw, rt + 0.1, paint)
	var fwh := D.sp(o, rot, fw + 0.085, rt, 2.2)
	var rwh := D.sp(o, rot, fw - 0.085, rt, 2.2)
	D.road_wheel(cv, rwh, 1.8, 2.1, f, false)
	D.road_wheel(cv, fwh, 1.8, 2.1, f, false)
	var fr: Dictionary = P.box(cv, o, D.w(rot, fw - 0.01, rt, 2.0), 0.06, 0.02, 2.5, rot, paint, 0.06, 1106 + i)
	D.box_edges(cv, fr, paint, 1109)
	cv.team = true  # fuel tank in team colour (recognition)
	P.box(cv, o, D.w(rot, fw + 0.02, rt, 4.5), 0.035, 0.024, 1.6, rot, Color(0.62, 0.62, 0.62), 0.04, 1110)
	cv.team = false
	cv.line_v(fwh, D.sp(o, rot, fw + 0.065, rt, 7.5), V.GUNMETAL)  # fork
	var hl := D.sp(o, rot, fw + 0.06, rt - 0.035, 8)
	var hr := D.sp(o, rot, fw + 0.06, rt + 0.035, 8)
	cv.line_v(hl, hr, Color8(34, 32, 30))
	cv.px(int(D.sp(o, rot, fw + 0.09, rt, 6).x), int(D.sp(o, rot, fw + 0.09, rt, 6).y), Color8(226, 214, 160))  # headlamp
	_rider(cv, o, rot, fw - 0.02, rt, 4.5, hl, hr, 1111 + i)
	if i == 1:  # pennant whip on a flank bike (team)
		var pb := D.sp(o, rot, fw - 0.09, rt, 5)
		cv.line_v(pb, pb + Vector2(0, -9), Color8(30, 31, 29))
		cv.team = true
		cv.rect(int(pb.x) + 1, int(pb.y) - 9, 3, 2, Color(0.66, 0.66, 0.66))
		cv.team = false
	if side and not sc_far:
		_sidecar(cv, o, rot, f, fw, rt + 0.1, paint)


static func _rider(cv, o: Vector2, rot: float, fw: float, rt: float, z: float, hl: Vector2, hr: Vector2, s: int) -> void:
	var t: Dictionary = P.box(cv, o, D.w(rot, fw, rt, z), 0.024, 0.028, 5.0, rot, B_COAT, 0.08, s)
	D.box_edges(cv, t, B_COAT, s + 1, 0.2)
	var sh := D.sp(o, rot, fw + 0.005, rt, z + 4.5)
	cv.line_v(sh + Vector2(-1, 0), hl, P.mul(B_COAT, 0.85))
	cv.line_v(sh + Vector2(1, 0), hr, P.mul(B_COAT, 0.85))
	var hp := D.sp(o, rot, fw + 0.01, rt, z + 7.5)
	if D.faces_cam(rot, 1.0, 0.0):
		cv.px(int(hp.x), int(hp.y) + 1, U.SKIN)
	cv.rect(int(hp.x) - 1, int(hp.y) - 1, 3, 2, B_HELM)
	cv.px(int(hp.x) - 1, int(hp.y) - 1, P.mul(B_HELM, 1.4))
	var rb := D.sp(o, rot, fw - 0.03, rt, z + 2)
	cv.line_v(rb, rb + Vector2(2, -5), Color8(64, 50, 36))  # slung carbine


static func _sidecar(cv, o: Vector2, rot: float, f: int, fw: float, sr: float, paint: Color) -> void:
	D.road_wheel(cv, D.sp(o, rot, fw - 0.01, sr + 0.035, 2.0), 1.7, 1.9, f, false)
	var tb: Dictionary = P.box(cv, o, D.w(rot, fw, sr, 2.0), 0.07, 0.035, 3.0, rot, paint, 0.06, 1115)
	P.box(cv, o, D.w(rot, fw + 0.075, sr, 2.5), 0.02, 0.025, 2.0, rot, P.mul(paint, 1.05), 0.05, 1116)
	for sd in tb.sides:
		V.rivets(cv, sd.quad, 0.75, 3, paint)
	D.box_edges(cv, tb, paint, 1117)
	var gt: Dictionary = P.box(cv, o, D.w(rot, fw - 0.02, sr, 4.0), 0.022, 0.025, 4.0, rot, B_COAT, 0.08, 1118)
	D.box_edges(cv, gt, B_COAT, 1119, 0.2)
	var hp := D.sp(o, rot, fw - 0.015, sr, 10)
	cv.rect(int(hp.x) - 1, int(hp.y) - 1, 3, 2, B_HELM)
	cv.px(int(hp.x) - 1, int(hp.y) - 1, P.mul(B_HELM, 1.4))
	var pa := D.sp(o, rot, fw + 0.03, sr, 5)
	cv.line_v(pa, pa + Vector2(0, -3), V.GUNMETAL)
	var a := D.sp(o, rot, fw + 0.02, sr, 9)
	var b := D.sp(o, rot, fw + 0.16, sr, 9.5)
	cv.line_v(a, b, Color8(40, 40, 38))
	cv.px(int(a.x), int(a.y) + 1, Color8(60, 58, 54))
	cv.px(int(b.x), int(b.y), Color8(70, 68, 62))


# ================================================================ m_spider_layer
## Six-legged Machine crawler with a mine hopper on its back and a rear chute; "lay" drops a Sentry Mine.
const SPIDER_LEGS := [[-0.12, 0.08, -0.28, 0.3, 0], [0.0, 0.09, 0.0, 0.34, 1], [0.12, 0.08, 0.28, 0.3, 0],
	[-0.12, -0.08, -0.28, -0.3, 1], [0.0, -0.09, 0.0, -0.34, 0], [0.12, -0.08, 0.28, -0.3, 1]]


static func spider_layer(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var bob := -1.0 if (f == 1 or f == 2) and not wreck else 0.0
	var hipz := 5.0 if wreck else 10.0 + bob
	var kup := 2.0 if wreck else 5.0
	var lcol: Color = ML.DEAD_D if wreck else ML.GRAPH
	cv.ellipse(o.x + 2, o.y + 0.5, 15.0, 6.5, Color.BLACK, true)
	cv.flush_shadow()
	var lay := f == 3 and not wreck
	var rear_cam := D.faces_cam(rot, -1.0, 0.0)
	if lay and not rear_cam:
		_laid_mines(cv, o, rot)
	FMU._legs(cv, o, rot, SPIDER_LEGS, hipz, f, false, lcol, 2, kup, 0.07, wreck, "m_spider")
	_spider_body(cv, o, rot, hipz - 3.0, f, wreck)
	FMU._legs(cv, o, rot, SPIDER_LEGS, hipz, f, true, lcol, 2, kup, 0.07, wreck, "m_spider")
	if lay and rear_cam:
		_laid_mines(cv, o, rot)
	cv.outline(OUTL_M)
	if lay:
		var mp := ML.sp(o, rot, -0.42, 0.0, 1)
		cv.ellipse(mp.x, mp.y, 4.0, 2.0, Color(ML.CYAN.r, ML.CYAN.g, ML.CYAN.b, 0.3))


static func _spider_body(cv, o: Vector2, rot: float, hz0: float, f: int, wreck: bool) -> void:
	var hullc: Color = ML.DEAD if wreck else ML.GRAPH
	var shell: Color = P.mul(ML.DEAD, 1.15) if wreck else ML.PANEL
	var front := D.faces_cam(rot, 1.0, 0.0)
	var head := func() -> void:
		var hd: Dictionary = ML.hexp(cv, o, ML.w(rot, 0.22, 0.0, hz0 + 1), 0.08, 4.0, rot, P.mul(hullc, 0.85), 1203, null, 0.9)
		ML.rims(cv, hd, hullc)
		if front:
			ML.eye(cv, ML.sp(o, rot, 0.29, -0.035, hz0 + 3.5), false, wreck)
			ML.eye(cv, ML.sp(o, rot, 0.29, 0.035, hz0 + 3.5), false, wreck)
	if not front:
		head.call()
	var b: Dictionary = ML.hexp(cv, o, Vector3(0, 0, hz0), 0.22, 6.0, rot, hullc, 1201, null, 0.72)
	for sd in b.sides:
		ML.seam(cv, sd.quad, 0.45, wreck, 0.08, 0.92)
	ML.rims(cv, b, hullc)
	if wreck:
		WK._scorch(cv, b.top)
	P.box(cv, o, ML.w(rot, -0.2, 0.0, hz0 - 1), 0.05, 0.05, 4.0, rot, ML.GRAPH_D if not wreck else ML.DEAD_D, 0.05, 1204)  # chute
	if f == 3 and not wreck:  # mine leaving the chute
		_mine(cv, o, rot, -0.24, 0.0, 2.0, true)
	var hp: Dictionary = P.box(cv, o, ML.w(rot, -0.05, 0.0, hz0 + 6), 0.13, 0.12, 5.0, rot, shell, 0.07, 1205)
	for sd in hp.sides:
		if not wreck and absf(_fw(sd, rot)) < 0.3:
			ML.team_panel(cv, sd.quad, 0.1, 0.25, 0.9, 0.7)
		ML.joints(cv, sd.quad, [0.5], shell)
		ML.seam(cv, sd.quad, 0.92, wreck)
	ML.rims(cv, hp, shell)
	var full := 4 if f != 3 else 3
	for k in 4:
		var u := 0.28 + (k % 2) * 0.44
		var v := 0.28 + (k / 2) * 0.44
		ML.hex_plate(cv, hp.top, u, v, 2.3, ML.GRAPH_D if k < full else Color8(28, 30, 32), not wreck and k < full)
	if front:
		head.call()
	var ant := ML.sp(o, rot, -0.12, -0.08, hz0 + 11)
	cv.line_v(ant, ant + Vector2(0, -6), ML.JOINT)
	if not wreck:
		cv.px(int(ant.x), int(ant.y) - 7, ML.CYAN)


static func _mine(cv, o: Vector2, rot: float, fwd: float, right: float, z: float, lit: bool) -> void:
	var m: Dictionary = ML.hexp(cv, o, ML.w(rot, fwd, right, z), 0.065, 2.0, rot, ML.GRAPH, 1210, null, 1.0)
	ML.rims(cv, m, ML.GRAPH)
	var c: Vector2 = ((m.top as PackedVector2Array)[0] + (m.top as PackedVector2Array)[3]) * 0.5
	ML.eye(cv, c, false, not lit)


static func _laid_mines(cv, o: Vector2, rot: float) -> void:
	_mine(cv, o, rot, -0.42, 0.0, 0.0, true)
	_mine(cv, o, rot, -0.62, 0.14, 0.0, true)


# ================================================================ m_hover_tank
## Machine hover tank: dark skirt over a cyan ground-effect cushion, elongated hex hull with team panels,
## side thruster pods, off-white hex turret with a twin rail cannon. Spray ring on water.
static func hover_tank(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var bob := -1.0 if f == 1 else 0.0
	var hz0 := 0.0 if wreck else 5.0 + bob
	var trot := rot + (0.6 if wreck else 0.0)
	var hullc: Color = ML.DEAD if wreck else ML.GRAPH
	var shell: Color = P.mul(ML.DEAD, 1.15) if wreck else ML.PANEL
	cv.ellipse(o.x + 2, o.y + 1, 19.0, 8.5, Color.BLACK, true)
	cv.flush_shadow(Color(0.04, 0.05, 0.03, 0.3))
	var sk: Dictionary = P.box(cv, o, Vector3(0, 0, hz0), 0.5, 0.3, 3.0, rot, ML.GRAPH_D if not wreck else ML.DEAD_D, 0.06, 1301)
	for sd in sk.sides:
		ML.seam(cv, sd.quad, 0.35, wreck, 0.1, 0.9)
	for near in [false, true]:
		for s: float in [-1.0, 1.0]:
			if D.faces_cam(rot, 0.0, s) != near:
				continue
			var pd: Dictionary = P.box(cv, o, ML.w(rot, -0.26, 0.33 * s, hz0 + 2), 0.15, 0.05, 4.0, rot, hullc, 0.06, 1302)
			for sd in pd.sides:
				if _fw(sd, rot) < -0.7 and not wreck:
					var c: Vector2 = ((sd.quad as PackedVector2Array)[0] + (sd.quad as PackedVector2Array)[2]) * 0.5
					ML.eye(cv, c, false)
				ML.seam(cv, sd.quad, 0.8, wreck)
			ML.rims(cv, pd, hullc)
		if not near:
			var h: Dictionary = ML.hexp(cv, o, Vector3(0, 0, hz0 + 3), 0.58, 6.0, rot, hullc, 1303, null, 0.55)
			for sd in h.sides:
				var long := absf((sd.n as Vector2).dot(Vector2(-sin(rot), cos(rot)))) > 0.85
				if long and not wreck:
					ML.team_panel(cv, sd.quad, 0.12, 0.25, 0.88, 0.62)
				ML.seam(cv, sd.quad, 0.8, wreck, 0.05, 0.95)
				ML.joints(cv, sd.quad, [0.5], hullc)
			ML.rims(cv, h, hullc)
			if wreck:
				WK._scorch(cv, h.top)
			else:
				ML.hex_plate(cv, h.top, 0.22, 0.35, 2.6, ML.GRAPH_D, true)
				ML.hex_plate(cv, h.top, 0.22, 0.65, 2.6, ML.GRAPH_D, true)
	var toward := cos(trot) + sin(trot) > 0.0
	var rc := ML.w(trot, 0.42, 0.0, hz0 + 12)
	if not toward:
		_rail2(cv, o, trot, rc, 0.26, f, wreck)
	var t: Dictionary = ML.hexp(cv, o, ML.w(trot, -0.06, 0.0, hz0 + 9), 0.22, 5.0, trot, shell, 1305, null, 0.85)
	for sd in t.sides:
		if not wreck:
			ML.team_panel(cv, sd.quad, 0.14, 0.3, 0.86, 0.75)
		ML.seam(cv, sd.quad, 0.9, wreck)
	if wreck:
		WK._scorch(cv, t.top)
	else:
		ML.hex_plate(cv, t.top, 0.35, 0.5, 2.6, ML.GRAPH_D, true)
		var ant := P.proj(o, ML.w(trot, -0.2, 0.1, hz0 + 14))
		cv.line_v(ant, ant + Vector2(0, -6), ML.JOINT)
		cv.px(int(ant.x), int(ant.y) - 7, ML.CYAN)
	if toward:
		if not wreck:
			ML.eye(cv, P.proj(o, ML.w(trot, 0.15, -0.08, hz0 + 12)), true)
		_rail2(cv, o, trot, rc, 0.26, f, wreck)
	cv.outline(OUTL_M)
	if wreck:
		return
	# ground effect: cyan cushion glow, spray ring on the water, wake when moving
	cv.ellipse(o.x, o.y + 0.5, 15.0, 6.5, Color(ML.CYAN.r, ML.CYAN.g, ML.CYAN.b, 0.18))
	var n := 36
	for i in n:
		var a := i * TAU / n
		if P.hn(i, f, 1306) < 0.4:
			continue
		var p := o + Vector2(cos(a) * 21.0, sin(a) * 9.5 + 0.5)
		cv.px(int(p.x), int(p.y), Color(0.9, 0.97, 0.97, 0.75))
		if P.hn(i, f, 1307) > 0.6:
			cv.px(int(p.x), int(p.y) - 1, Color(0.9, 0.97, 0.97, 0.4))
	if f == 1:
		for k in 3:
			L.puff(cv, ML.sp(o, rot, -0.62 - k * 0.12, 0.12 * (k - 1), 1), 2.6 - k * 0.5, 0.35, Color(0.9, 0.96, 0.96))
	for s: float in [-1.0, 1.0]:
		var th := ML.sp(o, rot, -0.42, 0.33 * s, hz0 + 4)
		cv.px(int(th.x), int(th.y), Color(ML.CYAN_HOT.r, ML.CYAN_HOT.g, ML.CYAN_HOT.b, 0.8))


static func _rail2(cv, o: Vector2, trot: float, c: Vector3, rl: float, f: int, wreck: bool) -> void:
	var col: Color = ML.DEAD_D if wreck else ML.GRAPH_D
	for s in [-1, 1]:
		P.box(cv, o, c + ML.w(trot, 0, 0.035 * s), rl, 0.02, 2.0, trot, col, 0.04, 1308)
	if wreck:
		return
	for i in 4:
		var p := P.proj(o, c + ML.w(trot, -rl + 0.08 + i * 0.12, 0, 1.5))
		cv.px(int(p.x), int(p.y), ML.CYAN)
		cv.px(int(p.x), int(p.y) + 1, ML.TEAL)
	if f == 2:
		var tip := P.proj(o, c + ML.w(trot, rl + 0.05, 0, 1.5))
		cv.ellipse(tip.x, tip.y, 3.5, 2.6, Color(ML.CYAN.r, ML.CYAN.g, ML.CYAN.b, 0.55))
		cv.ellipse(tip.x, tip.y, 1.8, 1.3, ML.CYAN_HOT)
		var far := P.proj(o, c + ML.w(trot, rl + 0.22, 0, 1.5))
		cv.line_v(tip, far, Color(ML.CYAN_HOT.r, ML.CYAN_HOT.g, ML.CYAN_HOT.b, 0.8))


# ================================================================ m_colossus
## Machine late-game siege walker: four heavy legs (faction_m_units leg kit, 4 px), armoured hull with
## shoulder missile pods, exposed reactor core, big hex turret with a coil-ringed core cannon.
## Extra column "scale": idle pose with a Human A rifleman beside it.
const COL_LEGS := [[0.24, 0.22, 0.56, 0.52, 0], [-0.24, -0.22, -0.56, -0.52, 0], [0.24, -0.22, 0.56, -0.52, 1], [-0.24, 0.22, -0.56, 0.52, 1]]


static func colossus(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var bob := -1.5 if (f == 1 or f == 2) and not wreck else 0.0
	var hipz := 6.0 if wreck else 30.0 + bob
	var kup := 4.0 if wreck else 12.0
	var lcol: Color = ML.DEAD_D if wreck else ML.GRAPH
	cv.ellipse(o.x + 3, o.y + 1, 30.0, 13.0, Color.BLACK, true)
	cv.flush_shadow()
	FMU._legs(cv, o, rot, COL_LEGS, hipz, f, false, lcol, 4, kup, 0.14, wreck, "m_walker")
	var hz0 := 4.0 if wreck else 26.0 + bob
	var hullc: Color = ML.DEAD if wreck else ML.GRAPH
	var shell: Color = P.mul(ML.DEAD, 1.15) if wreck else ML.PANEL
	for near in [false, true]:
		if near:
			_col_hull(cv, o, rot, hz0, hullc, shell, wreck)
		for s: float in [-1.0, 1.0]:
			if D.faces_cam(rot, 0.0, s) != near:
				continue
			var pd: Dictionary = P.box(cv, o, ML.w(rot, 0.0, 0.41 * s, hz0 + 4), 0.22, 0.07, 8.0, rot, shell, 0.07, 1402)
			for sd in pd.sides:
				ML.joints(cv, sd.quad, [0.5], shell)
				ML.seam(cv, sd.quad, 0.25, wreck, 0.05, 0.95)
			ML.rims(cv, pd, shell)
			for k in 3:
				ML.hex_plate(cv, pd.top, 0.22 + k * 0.28, 0.5, 2.0, ML.GRAPH_D, not wreck)
	var trot := rot + (0.6 if wreck else 0.0)
	var toward := cos(trot) + sin(trot) > 0.0
	var tz := hz0 + 11.0
	if not toward:
		_core_cannon(cv, o, trot, tz, f, wreck)
	var t: Dictionary = ML.hexp(cv, o, ML.w(trot, -0.06, 0.0, tz), 0.27, 8.0, trot, shell, 1403, null, 0.85)
	for sd in t.sides:
		if not wreck:
			ML.team_panel(cv, sd.quad, 0.12, 0.3, 0.88, 0.72)
		ML.seam(cv, sd.quad, 0.9, wreck)
	if wreck:
		WK._scorch(cv, t.top)
	else:
		var cc: Vector2 = P.sub(t.top, 0.3, 0.5, 0.3, 0.5)[0]  # exposed reactor core
		cv.ellipse(cc.x, cc.y, 4.5, 2.6, ML.GRAPH_D)
		cv.ellipse(cc.x, cc.y - 0.5, 3.2, 1.8, Color(ML.CYAN.r, ML.CYAN.g, ML.CYAN.b, 0.9))
		cv.ellipse(cc.x, cc.y - 0.6, 1.5, 0.9, ML.CYAN_HOT)
		ML.hex_plate(cv, t.top, 0.7, 0.3, 2.2, ML.GRAPH_D, true)
		var ant := P.proj(o, ML.w(trot, -0.24, 0.14, tz + 8))
		cv.line_v(ant, ant + Vector2(0, -8), ML.JOINT)
		cv.px(int(ant.x), int(ant.y) - 9, ML.CYAN)
	if toward:
		if not wreck:
			ML.eye(cv, P.proj(o, ML.w(trot, 0.22, -0.1, tz + 6)), true)
		_core_cannon(cv, o, trot, tz, f, wreck)
	FMU._legs(cv, o, rot, COL_LEGS, hipz, f, true, lcol, 4, kup, 0.14, wreck, "m_walker")
	cv.outline(OUTL_M)
	if f == 3 and not wreck:
		var tip := P.proj(o, ML.w(trot, 0.92, 0.0, tz + 3))
		cv.ellipse(tip.x, tip.y, 6.0, 4.5, Color(ML.CYAN.r, ML.CYAN.g, ML.CYAN.b, 0.45))
		cv.ellipse(tip.x, tip.y, 3.0, 2.2, ML.CYAN_HOT)
		var far := P.proj(o, ML.w(trot, 1.4, 0.0, tz + 2))
		cv.line_v(tip, far, Color(ML.CYAN_HOT.r, ML.CYAN_HOT.g, ML.CYAN_HOT.b, 0.85))
		cv.line_v(tip + Vector2(0, 1), far + Vector2(0, 1), Color(ML.CYAN.r, ML.CYAN.g, ML.CYAN.b, 0.5))
	if f == 4 and not wreck:
		var k := int(round(rot / (PI / 4.0))) % 8
		var fig = P.Canvas.new(24, 26)
		FIG.draw(fig, k, "stand", RIFLEMAN)
		fig.outline(OUTL)
		SL.stamp(cv, fig, int(o.x) - 46 - SL.FIG_PIV.x, int(o.y) + 14 - SL.FIG_PIV.y)


static func _col_hull(cv, o: Vector2, rot: float, hz0: float, hullc: Color, shell: Color, wreck: bool) -> void:
	var h: Dictionary = P.box(cv, o, Vector3(0, 0, hz0), 0.42, 0.34, 11.0, rot, hullc, 0.08, 1401)
	for sd in h.sides:
		var q: PackedVector2Array = sd.quad
		var d := _fw(sd, rot)
		ML.joints(cv, q, [0.25, 0.5, 0.75], hullc)
		ML.seam(cv, q, 0.3, wreck, 0.04, 0.96)
		if absf(d) < 0.3:
			cv.poly(P.sub(q, 0.06, 0.48, 0.46, 0.92), P.mul(shell, 0.9))
			if not wreck:
				ML.team_panel(cv, q, 0.54, 0.48, 0.94, 0.88)
		elif d > 0.7 and not wreck:
			var c: Vector2 = q[0].lerp(q[1], 0.5).lerp(q[3].lerp(q[2], 0.5), 0.6)
			cv.ellipse(c.x, c.y, 3.2, 2.6, ML.JOINT)
			ML.eye(cv, c, true)
		if not wreck:
			for i in 3:
				var a: Vector2 = q[0].lerp(q[1], 0.1 + i * 0.05).lerp(q[3].lerp(q[2], 0.1 + i * 0.05), 0.7)
				cv.px(int(a.x), int(a.y), ML.JOINT)
	ML.rims(cv, h, hullc)
	if wreck:
		WK._scorch(cv, h.top)


static func _core_cannon(cv, o: Vector2, trot: float, tz: float, f: int, wreck: bool) -> void:
	var col: Color = ML.DEAD_D if wreck else ML.GRAPH_D
	var ring: Color = P.mul(ML.DEAD, 1.1) if wreck else ML.PANEL_D
	var back := 0.04 if f == 3 else 0.0
	P.box(cv, o, ML.w(trot, 0.52 - back, 0.0, tz + 1.5), 0.34, 0.055, 4.0, trot, col, 0.04, 1404)
	for i in 4:
		var c := ML.w(trot, 0.3 + i * 0.13 - back, 0.0, tz + 0.8)
		P.box(cv, o, c, 0.025, 0.08, 5.4, trot, ring, 0.04, 1405 + i)
		if not wreck:
			var p := P.proj(o, c + Vector3(0, 0, 5.6))
			cv.px(int(p.x), int(p.y), ML.CYAN)
	P.box(cv, o, ML.w(trot, 0.88 - back, 0.0, tz + 0.6), 0.04, 0.075, 5.4, trot, col, 0.04, 1409)


# ================================================================ m_assimilator
## Machine tracked crawler with two claw arms up front and a fabricator bay on the back;
## "work": claws tear into a wreck, cyan disassembly arc, a part printing in a holo lattice over the bay.
static func assimilator(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var work := f == 2 and not wreck
	var hullc: Color = ML.DEAD if wreck else ML.GRAPH
	var shell: Color = P.mul(ML.DEAD, 1.15) if wreck else ML.PANEL
	var trk: Color = Color8(36, 32, 30) if wreck else Color8(40, 43, 46)
	var t := [0.5, 0.27, 6.0]
	for s in [-1, 1]:
		P.box_shadow(cv, o, ML.w(rot, 0, 0.27 * s), 0.5, 0.09, 6.0, rot)
	P.box_shadow(cv, o, Vector3(0, 0, 5), 0.48, 0.3, 13.0, rot)
	cv.flush_shadow()
	var front := D.faces_cam(rot, 1.0, 0.0)
	if not front:
		if work:
			_scrap(cv, o, rot)
		_claws(cv, o, rot, f, wreck)
	var near_s := 1 if D.faces_cam(rot, 0.0, 1.0) else -1
	MV._track(cv, o, rot, t, -near_s, f, trk, wreck)
	MV._track(cv, o, rot, t, near_s, f, trk, wreck)
	var h: Dictionary = P.box(cv, o, Vector3(0, 0, 5), 0.48, 0.3, 6.0, rot, hullc, 0.08, 1501)
	G3M._panels(cv, h, rot, hullc, wreck, true)
	var pr: Dictionary = P.box(cv, o, ML.w(rot, 0.44, 0.0, 5), 0.07, 0.24, 5.0, rot, P.mul(hullc, 0.85), 0.06, 1502)
	ML.rims(cv, pr, hullc)
	if front:
		for s: float in [-1.0, 1.0]:
			ML.eye(cv, ML.sp(o, rot, 0.52, 0.1 * s, 8), false, wreck)
	var bay: Dictionary = P.box(cv, o, ML.w(rot, -0.2, 0.0, 11), 0.24, 0.25, 7.0, rot, shell, 0.07, 1503)
	for sd in bay.sides:
		if not wreck:
			ML.team_panel(cv, sd.quad, 0.1, 0.28, 0.9, 0.62)
		ML.joints(cv, sd.quad, [0.5], shell)
		ML.seam(cv, sd.quad, 0.9, wreck)
	ML.rims(cv, bay, shell)
	var inner := P.sub(bay.top, 0.12, 0.12, 0.88, 0.88)
	cv.poly(inner, Color8(30, 32, 34))
	if wreck:
		WK._scorch(cv, bay.top)
	else:
		for g in [0.33, 0.66]:  # printer bed grid
			var a := P.sub(inner, g, 0.05, g, 0.95)
			cv.line_v(a[0], a[3], Color(ML.CYAN.r, ML.CYAN.g, ML.CYAN.b, 0.55))
			var b := P.sub(inner, 0.05, g, 0.95, g)
			cv.line_v(b[0], b[1], Color(ML.CYAN.r, ML.CYAN.g, ML.CYAN.b, 0.55))
		for i in 6:  # raw feedstock lumps
			var q := P.sub(inner, P.hn(i, 3, 1504) * 0.7 + 0.15, P.hn(i, 4, 1504) * 0.7 + 0.15, 0.0, 0.0)
			var cc: Color = [ML.RAW, Color8(120, 98, 70), Color8(104, 88, 70)][i % 3]
			cv.rect(int(q[0].x), int(q[0].y), 2, 1, cc)
		if work:  # part being printed
			P.box(cv, o, ML.w(rot, -0.2, 0.0, 13), 0.1, 0.09, 3.0, rot, ML.RAW, 0.05, 1505)
	var ant := ML.sp(o, rot, -0.38, -0.18, 18)
	cv.line_v(ant, ant + Vector2(0, -6), ML.JOINT)
	if not wreck:
		cv.px(int(ant.x), int(ant.y) - 7, ML.CYAN)
	if front:
		_claws(cv, o, rot, f, wreck)
		if work:
			_scrap(cv, o, rot)
	cv.outline(OUTL_M)
	if work:
		ML.holo_box(cv, o, ML.w(rot, -0.2, 0.0, 13), 0.12, 0.11, 9.0, 0.6)
		for s: float in [-1.0, 1.0]:
			var a := ML.sp(o, rot, 0.68, 0.1 * s, 6)
			var b := ML.sp(o, rot, 0.78, 0.02 * s, 3)
			cv.line_v(a, b, Color(ML.CYAN.r, ML.CYAN.g, ML.CYAN.b, 0.8))
			cv.px(int(b.x), int(b.y), ML.CYAN_HOT)
		for i in 5:
			var sp := ML.sp(o, rot, 0.74 + P.hn(i, 1, 1506) * 0.12, -0.12 + P.hn(i, 2, 1506) * 0.24, 4 + P.hn(i, 3, 1506) * 6)
			cv.px(int(sp.x), int(sp.y), ML.CYAN_HOT if i % 2 == 0 else Color8(255, 220, 140))


static func _claws(cv, o: Vector2, rot: float, f: int, wreck: bool) -> void:
	var col: Color = ML.DEAD_D if wreck else ML.GRAPH
	var work := f == 2 and not wreck
	for near in [false, true]:
		for s: float in [-1.0, 1.0]:
			if D.faces_cam(rot, 0.0, s) != near:
				continue
			var sh := ML.sp(o, rot, 0.36, 0.17 * s, 12)
			var el := ML.sp(o, rot, 0.56, 0.21 * s, 12.0 if work else 18.0)
			var tw := ML.w(rot, 0.72, 0.11 * s, 3.0 if work else (5.0 if not wreck else 1.0))
			var tp := P.proj(o, tw)
			for k in 3:
				cv.line_v(sh + Vector2(k - 1, 0), el + Vector2(k - 1, 0), P.mul(col, 1.15 if k == 0 else 0.85))
			for k in 2:
				cv.line_v(el + Vector2(k, 0), tp + Vector2(k, 0), P.mul(col, 1.0 if k == 0 else 0.75))
			cv.rect(int(sh.x) - 1, int(sh.y) - 1, 3, 3, ML.JOINT)
			cv.rect(int(el.x) - 1, int(el.y), 3, 2, ML.JOINT)
			if not wreck:
				cv.px(int(el.x), int(el.y) - 1, ML.CYAN)
			var open := 0.02 if work else 0.05
			for j: float in [-1.0, 1.0]:  # pincer jaws
				var jt := P.proj(o, tw + ML.w(rot, 0.07, open * j, -1.0))
				cv.line_v(tp, jt, ML.PANEL_D if not wreck else ML.DEAD)
				cv.px(int(jt.x), int(jt.y), ML.JOINT)


static func _scrap(cv, o: Vector2, rot: float) -> void:
	var r: Dictionary = P.box(cv, o, ML.w(rot, 0.8, 0.0, 0), 0.1, 0.13, 5.0, rot + 0.5, V.BURNT, 0.1, 1510)
	V.scorch(cv, r.top)
	for sd in r.sides:
		V.scorch(cv, sd.quad)
		V.patch(cv, sd.quad, 0.2, 0.3, 0.5, 0.8, P.mul(V.HULL, 0.7), 1511)
	var st := ML.sp(o, rot, 0.8, 0.0, 5)
	cv.line_v(st, st + Vector2(-6, -2), Color8(48, 44, 40))  # bent gun barrel
	var pl := ML.sp(o, rot, 0.86, 0.22, 0)
	cv.poly(PackedVector2Array([pl, pl + Vector2(5, 1), pl + Vector2(3, 3), pl + Vector2(-2, 2)]), P.mul(V.HULL, 0.6))
