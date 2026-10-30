extends SceneTree
## G7 SUPPLY8 art (13.9c-48; rev2 ART8C 2026-10-30): the airdrop retrieval op's tracked drone cargo carrier (Human A
## and Human B), the airdrop supply pod and the carrier garage, modelled in real metres on the ONE scale (fact
## art.scale: 4 m per 64x32 tile, 9.8 px per metre of height) through ARTCN7's faceted renderer (g7_cn_mesh.gd), the
## same pipeline as g7_rollout / g7_cn_vehicles:
##   g8_cargo_carrier / g8_b_cargo_carrier  3.4 x 2.1 m unmanned tracked drone cargo bed (THeMIS-class): two rubber
##       track pods with road wheels / sprocket / idler, an armoured hull with a sloped glacis, a flat cargo deck with
##       rails and tie-down cleats, a front sensor head (camera, lidar puck, headlights), the small ray-shield emitter
##       mast at the rear (cyan lens), a whip antenna. Team mask: sensor-head ID panel + track-skirt chevrons.
##       Frames idle, move, fire (the ray shield flares: emitter lens blazes, the small shield dome shows) + the G6.1 set drawn by the model itself (track_1 / track_2 = track link and wheel phases,
##       recoil = hull jolt, damaged = burnt hull, bent mast, dead lens); g7_anim adds anim61 (muzzle / smoke points).
##   g8_supply_pod  1.6 x 1.3 m airdrop pallet pod: skid pallet, crushed honeycomb pad, banded olive container, the
##       folded chute pack with risers, orange recovery beacon, stencils. Frames idle, recoil (landing jolt), damaged.
##   cn_carrier_garage (building, 1 tile, 4 rotations, g6_lib rot schema): armoured steel shed on a plinth, roll-up
##       door with hazard edge on +x, door-head housing, amber lamp, roof team stripe, vent, charging pylon.
## Icons for all four (g7_cn_lib.icon). Deterministic: pure functions, no rng.
##   godot --headless --path . -s tools/art/g8_supply.gd   (writes assets/art/g8_supply/)
## Prints "G7_ART <id> bytes=<n> budget=<n> ok|OVER" and "G7_ART group=g8_supply files=<n> over=<n>".

const G7Anim = preload("res://tools/art/g7_anim.gd")
const GEN = preload("res://tools/gen_art.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const M = preload("res://tools/art/g7_cn_mesh.gd")
const V = preload("res://tools/art/g7_cn_vehicles.gd")
const R7 = preload("res://tools/art/g7_rollout.gd")
const TU = preload("res://tools/art/g7_turrets2.gd")

const OUT := "res://assets/art/g8_supply/"
const HULL := {false: Color8(104, 112, 100), true: Color8(150, 130, 96)}   # Human A CN grey-green / Human B sand
const ROOF := {false: Color8(86, 93, 82), true: Color8(124, 106, 78)}
const BURNT := Color8(56, 50, 46)
const DARK := Color8(46, 50, 52)
const TRACK := Color8(40, 40, 38)
const HUB := Color8(92, 96, 90)
const GLASS := Color8(70, 120, 140)
const LAMP := Color8(255, 236, 170)
const CN_BLUE := Color8(110, 180, 255)
const AMBER := Color8(246, 178, 60)
const ORANGE := Color8(255, 132, 36)
const OLIVE := Color8(98, 102, 64)
const HONEY := Color8(176, 150, 98)
const SKID := Color8(112, 92, 62)
const TARP := Color8(120, 110, 82)
const STRAP := Color8(196, 178, 112)
const STENCIL := Color8(214, 214, 200)
const CONC := Color8(150, 148, 138)
const STEEL := Color8(96, 102, 98)

const CAR_FRAMES := ["idle", "move", "fire", "track_1", "track_2", "recoil", "damaged"]
const POD_FRAMES := ["idle", "recoil", "damaged"]
const CL := 3.4    # carrier length (m)
const CW := 2.1    # carrier width
const TW := 0.46   # track width
const TH := 0.78   # track height
const WHEELS := [1.05, 0.35, -0.35, -1.05]


# ------------------------------------------------------------------ tracked drone cargo carrier
## One track pod (side s = -1 left / +1 right): looped rubber track, road wheels, sprocket and idler on the outer
## face, grouser links that advance with the phase (move 0, track_1 1, track_2 2).
static func track(S: Array, T: Dictionary, s: float, ph: int, dmg: bool, hull: Array) -> void:
	var pt := M.part(S, 0)
	var r0 := s * (CW * 0.5 - TW * 0.5)
	var hw := TW * 0.5
	var tr: Array = C.ramp(BURNT if dmg else TRACK)
	var hl := CL * 0.5
	var secs := []
	for q in [[-hl, 0.24, 0.58], [-hl + 0.3, 0.04, TH], [hl - 0.36, 0.04, TH], [hl, 0.28, 0.64]]:
		secs.append([float(q[0]), PackedVector2Array([Vector2(r0 - hw, q[1]), Vector2(r0 + hw, q[1]),
			Vector2(r0 + hw, q[2]), Vector2(r0 - hw, q[2])])])
	M.loft(pt, T, secs, tr, {"edge": true})
	var ro := r0 + s * (hw + 0.012)
	var hb: Array = C.ramp(Color8(50, 46, 42) if dmg else HUB)
	var spin := float(maxi(ph, 0)) * 0.7
	for f in WHEELS:
		M.cyl(pt, T, Vector3(f, ro, 0.3), Vector3(0, 1, 0), 0.22, 0.015, 10, hb, {"cap_t": 2, "edge": false}, spin)
		M.dpx(pt, T, Vector3(f, ro + s * 0.02, 0.3), hb[0], Vector3(0, s, 0))
	for e in [[hl - 0.3, 0.42, 0.24], [-hl + 0.3, 0.4, 0.2]]:   # sprocket (front, toothed) + idler (rear)
		M.cyl(pt, T, Vector3(e[0], ro, e[1]), Vector3(0, 1, 0), e[2], 0.015, 8, hb, {"cap_t": 3, "edge": false}, spin)
		for i in 6:
			var t := spin + TAU * i / 6.0
			M.dpx(pt, T, Vector3(float(e[0]) + cos(t) * float(e[2]) * 0.62, ro + s * 0.02, float(e[1]) + sin(t) * float(e[2]) * 0.62),
				hb[4] if i % 2 == 0 else hb[0], Vector3(0, s, 0))
	var step := 0.24
	var off := step * float(maxi(ph, 0)) / 3.0
	var n := int((CL - 0.7) / step)
	for i in n + 1:   # grousers on the top run (move one way) and on the bottom run (the other)
		var ft := -hl + 0.32 + fposmod(float(i) * step + off, CL - 0.68)
		M.dline(pt, T, Vector3(ft, r0 - hw + 0.03, TH + 0.005), Vector3(ft, r0 + hw - 0.03, TH + 0.005), tr[0], Vector3(0, 0, 1))
		var fb := -hl + 0.32 + fposmod(float(i) * step - off, CL - 0.68)
		M.dpx(pt, T, Vector3(fb, ro, 0.06), tr[0], Vector3(0, s, 0))
		M.dpx(pt, T, Vector3(ft, ro, TH - 0.04), tr[3], Vector3(0, s, 0))
	# track skirt over the top run, with the team chevron on its outer face
	var sk := M.part(S, 0.1)
	M.box(sk, T, Vector3(0.05, r0 + s * 0.04, TH + 0.06), Vector3(hl - 0.42, hw + 0.04, 0.06), hull)
	var cx := 0.35
	var zc := TH + 0.06
	var so := r0 + s * (hw + 0.085)
	M.dpoly(sk, T, [Vector3(cx - 0.24, so, zc + 0.05), Vector3(cx, so, zc - 0.05), Vector3(cx + 0.24, so, zc + 0.05),
		Vector3(cx + 0.24, so, zc), Vector3(cx, so, zc - 0.1), Vector3(cx - 0.24, so, zc)], Color8(152, 152, 152), Vector3(0, s, 0), true)


static func carrier(cv, k: int, fname: String, o: Vector2, b: bool) -> void:
	var S: Array = []
	var dmg := fname == "damaged"
	var ph := int({"move": 0, "track_1": 1, "track_2": 2}.get(fname, -1))
	var pitch := -0.045 if fname == "recoil" else (0.012 if ph == 1 else 0.0)
	var lift := 0.025 if ph == 2 else 0.0
	var T := M.pose(o, V.row_yaw(k), Vector3(0, 0, lift), pitch)
	var hull: Array = C.ramp(BURNT if dmg else HULL[b])
	var roof: Array = C.ramp(Color8(48, 44, 40) if dmg else ROOF[b])
	var dk: Array = C.ramp(DARK)
	for s in [-1.0, 1.0]:
		track(S, T, s, ph, dmg, hull)
	var pt := M.part(S, 0.2)
	var hl := CL * 0.5
	var iw := CW * 0.5 - TW - 0.02
	M.box(pt, T, Vector3(-0.05, 0, 0.5), Vector3(hl - 0.2, iw, 0.24), hull)                     # belly hull
	M.box(pt, T, Vector3(1.38, 0, 0.66), Vector3(0.24, iw + 0.1, 0.2), hull, Vector3(0.18, 0, 0))   # sloped glacis
	M.box(pt, T, Vector3(-0.12, 0, 0.88), Vector3(1.42, CW * 0.5 - 0.02, 0.07), hull)            # cargo deck plate
	var pd := M.part(S, 0.3)
	M.box(pd, T, Vector3(-0.2, 0, 0.955), Vector3(1.22, CW * 0.5 - 0.12, 0.005), roof)          # non-skid deck coat
	for i in 5:   # deck plate seams + tie-down cleats
		var f := -1.2 + float(i) * 0.5
		M.dline(pd, T, Vector3(f, -CW * 0.5 + 0.14, 0.962), Vector3(f, CW * 0.5 - 0.14, 0.962), roof[1], Vector3(0, 0, 1))
		for s in [-1.0, 1.0]:
			M.dpx(pd, T, Vector3(f + 0.25, s * (CW * 0.5 - 0.16), 0.965), dk[3], Vector3(0, 0, 1))
	for s in [-1.0, 1.0]:   # side rails (one torn off on the wreck)
		if dmg and s > 0.0:
			continue
		M.box(pd, T, Vector3(-0.3, s * (CW * 0.5 - 0.06), 1.06), Vector3(1.08, 0.04, 0.1), hull)
	M.box(pd, T, Vector3(-1.46, 0, 1.04), Vector3(0.04, CW * 0.5 - 0.1, 0.09), hull)            # tail rail
	# front sensor head: camera, lidar puck, headlights, team ID panel on its roof
	var ps := M.part(S, 0.4)
	M.box(ps, T, Vector3(1.22, 0, 1.1), Vector3(0.17, 0.46, 0.15), hull, Vector3(0, 0, 0.04))
	TU.team_patch(ps, T, Vector3(1.2, 0, 1.255), Vector3(0.12, 0.3, 0.006), hull)
	M.cyl(ps, T, Vector3(1.22, 0, 1.33), Vector3(0, 0, 1), 0.09, 0.05, 8, dk, {"cap_t": 3})
	for s in [-1.0, 1.0]:
		M.dpx(ps, T, Vector3(1.4, s * 0.24, 1.12), dk[0] if dmg else GLASS, Vector3(1, 0, 0))
		M.dpx(ps, T, Vector3(1.55, s * 0.72, 0.74), dk[0] if dmg else LAMP, Vector3(1, 0, 0))
	M.dpx(ps, T, Vector3(1.4, 0, 1.08), dk[0] if dmg else Color8(200, 230, 255), Vector3(1, 0, 0))
	# rear ray-shield emitter mast (bent on the wreck) + whip antenna
	var pm := M.part(S, 0.5)
	var Tm := M.sub(T, Vector3(-1.25, 0, 0.96), 0.0, 0.0, 0.5 if dmg else 0.0)
	M.box(pm, Tm, Vector3(0, 0, 0.06), Vector3(0.16, 0.16, 0.06), dk)
	M.cyl(pm, Tm, Vector3(0, 0, 0.36), Vector3(0, 0, 1), 0.05, 0.26, 6, dk, {"edge": false})
	M.cyl(pm, Tm, Vector3(0, 0, 0.66), Vector3(0, 0, 1), 0.17, 0.05, 10, C.ramp(STEEL), {"cap_t": 2})
	M.cyl(pm, Tm, Vector3(0, 0, 0.74), Vector3(0, 0, 1), 0.1, 0.03, 10, C.ramp(BURNT if dmg else CN_BLUE), {"cap_t": 4})
	if not dmg:
		M.dpx(pm, Tm, Vector3(0, 0, 0.78), Color8(220, 245, 255), Vector3(0, 0, 1))
	if fname == "fire":   # shield flare: lens blazes white-cyan
		M.cyl(pm, Tm, Vector3(0, 0, 0.8), Vector3(0, 0, 1), 0.13, 0.04, 10, C.ramp(Color8(190, 236, 255)), {"cap_t": 4})
	M.dline(pm, T, Vector3(-1.3, -0.78, 1.0), Vector3(-1.38 if not dmg else -1.0, -0.78, 1.95 if not dmg else 1.5), dk[1])
	if dmg:   # scorch and holes on the deck and glacis
		for q in [Vector3(0.4, 0.3, 0.965), Vector3(-0.6, -0.4, 0.965), Vector3(-0.1, 0.55, 0.965), Vector3(0.9, -0.2, 0.965)]:
			M.dpx(pd, T, q, Color8(24, 22, 20), Vector3(0, 0, 1))
	M.shadow(cv, S, o)
	M.render_z(cv, S, o, 131 + k)
	if fname == "fire":   # the small ray shield, shown while it absorbs a hit
		V.dome(cv, o + Vector2(0, -3), 29.0, 14.0, 24.0)


# ------------------------------------------------------------------ airdrop supply pod
static func pod(cv, k: int, fname: String, o: Vector2) -> void:
	var S: Array = []
	var dmg := fname == "damaged"
	var rc := fname == "recoil"
	var T := M.pose(o, k * PI / 4.0, Vector3(0, 0, -0.03 if rc else 0.0), 0.035 if rc else 0.0)
	var pt := M.part(S, 0)
	var sk: Array = C.ramp(BURNT if dmg else SKID)
	for s in [-0.55, 0.0, 0.55]:   # pallet skids + deck boards
		M.box(pt, T, Vector3(0, s, 0.06), Vector3(0.8, 0.07, 0.06), sk)
	M.box(pt, T, Vector3(0, 0, 0.14), Vector3(0.8, 0.65, 0.025), sk)
	M.box(pt, T, Vector3(0, 0, 0.24), Vector3(0.74, 0.6, 0.075), C.ramp(Color8(60, 54, 46) if dmg else HONEY))   # crushed pad
	var pc := M.part(S, 0.2)
	var body: Array = C.ramp(BURNT if dmg else OLIVE)
	M.box(pc, T, Vector3(0, 0, 0.71), Vector3(0.7, 0.56, 0.4), body, Vector3(0, 0, 0.08))   # banded container
	for s in [-1.0, 1.0]:   # owner ID panels on both long sides
		TU.team_patch(pc, T, Vector3(0, s * 0.565, 0.75), Vector3(0.3, 0.006, 0.1), body)
	TU.team_patch(pc, T, Vector3(0.705, 0, 0.42), Vector3(0.006, 0.3, 0.05), body)   # and a band on the +x end
	var stc: Color = Color8(70, 62, 50) if dmg else STRAP
	for f in [-0.4, 0.4]:   # cargo straps over the top and down both sides
		M.dline(pc, T, Vector3(f, -0.48, 1.115), Vector3(f, 0.48, 1.115), stc, Vector3(0, 0, 1))
		for s in [-1.0, 1.0]:
			M.dline(pc, T, Vector3(f, s * 0.565, 0.33), Vector3(f, s * 0.53, 1.1), stc, Vector3(0, s, 0))
	if not dmg:
		for i in 4:   # stencil block on the +x face
			M.dpx(pc, T, Vector3(0.705, -0.2 + float(i) * 0.12, 0.85), STENCIL, Vector3(1, 0, 0))
			M.dpx(pc, T, Vector3(0.705, -0.2 + float(i) * 0.12, 0.62), STENCIL, Vector3(1, 0, 0))
		var pp := M.part(S, 0.3)   # folded chute pack + risers
		M.box(pp, T, Vector3(-0.1, 0, 1.24), Vector3(0.36, 0.32, 0.12), C.ramp(TARP), Vector3(0.06, 0.06, 0.06))
		for c in [Vector3(0.6, 0.48, 1.12), Vector3(0.6, -0.48, 1.12), Vector3(-0.6, 0.48, 1.12), Vector3(-0.6, -0.48, 1.12)]:
			M.dline(pp, T, c, Vector3(c.x * 0.4 - 0.1, c.y * 0.5, 1.3), Color8(90, 84, 66))
	var pb := M.part(S, 0.4)   # recovery beacon on the +x/-y corner post
	M.cyl(pb, T, Vector3(0.6, -0.46, 1.22), Vector3(0, 0, 1), 0.025, 0.12, 4, C.ramp(DARK), {"edge": false})
	M.cyl(pb, T, Vector3(0.6, -0.46, 1.38), Vector3(0, 0, 1), 0.06, 0.05, 6, C.ramp(BURNT if dmg else ORANGE), {"cap_t": 4})
	if not dmg:
		M.dpx(pb, T, Vector3(0.6, -0.46, 1.44), Color8(255, 220, 150), Vector3(0, 0, 1))
	else:
		for q in [Vector3(0.2, 0.2, 1.115), Vector3(-0.3, -0.1, 1.115), Vector3(0.0, -0.3, 1.115)]:
			M.dpx(pc, T, q, Color8(24, 22, 20), Vector3(0, 0, 1))
	M.shadow(cv, S, o)
	M.render_z(cv, S, o, 171 + k)


# ------------------------------------------------------------------ carrier garage (building, 1 tile)
static func garage(cv, o: Vector2, f: int, _opt: Dictionary) -> void:
	var S: Array = []
	var T := M.pose(o, float(f) * PI / 2.0)
	var steel: Array = C.ramp(STEEL)
	var dk: Array = C.ramp(DARK)
	var pt := M.part(S, 0)
	M.box(pt, T, Vector3(0, 0, 0.08), Vector3(1.94, 1.94, 0.08), C.ramp(CONC))                   # plinth
	M.box(pt, T, Vector3(1.75, 0, 0.165), Vector3(0.2, 1.05, 0.005), C.ramp(Color8(118, 116, 108)))   # door apron
	var pw := M.part(S, 0.1)
	M.box(pw, T, Vector3(-0.12, 0, 1.5), Vector3(1.55, 1.5, 1.34), steel)                         # armoured shell
	R7.seams(pw, T, 1.5, -1.67, 1.43, 2.84, 0.62, steel, Vector3(0, 1, 0))
	R7.seams(pw, T, -1.5, -1.67, 1.43, 2.84, 0.62, steel, Vector3(0, -1, 0))
	R7.seams(pw, T, -1.67, -1.5, 1.5, 2.84, 0.6, steel, Vector3(-1, 0, 0))
	var pr := M.part(S, 0.2)
	var rf: Array = C.ramp(Color8(84, 90, 86))
	M.box(pr, T, Vector3(-0.12, 0, 2.92), Vector3(1.68, 1.62, 0.08), rf)                          # roof slab
	TU.team_patch(pr, T, Vector3(-0.3, 0, 3.005), Vector3(1.1, 0.16, 0.006), rf)
	M.box(pr, T, Vector3(-0.95, 0.85, 3.12), Vector3(0.26, 0.26, 0.12), steel)                    # roof vent
	M.dline(pr, T, Vector3(-1.2, 0.86, 3.245), Vector3(-0.7, 0.86, 3.245), dk[0], Vector3(0, 0, 1))
	var pd := M.part(S, 0.3)   # roll-up door on +x, door-head housing, hazard edge, lamp
	M.box(pd, T, Vector3(1.45, 0, 1.2), Vector3(0.02, 1.1, 1.04), dk)
	for i in 9:
		var z := 0.3 + float(i) * 0.22
		M.dline(pd, T, Vector3(1.475, -1.08, z), Vector3(1.475, 1.08, z), dk[3], Vector3(1, 0, 0))
	for i in 8:
		var y := -1.05 + float(i) * 0.3
		M.dline(pd, T, Vector3(1.48, y, 0.2), Vector3(1.48, y + 0.15, 0.2), AMBER, Vector3(1, 0, 0))
	M.box(pd, T, Vector3(1.5, 0, 2.38), Vector3(0.08, 1.24, 0.13), steel)
	M.dpx(pd, T, Vector3(1.59, 0.9, 2.55), AMBER, Vector3(1, 0, 0))
	M.dpx(pd, T, Vector3(1.59, 0.92, 2.55), Color8(255, 220, 150), Vector3(1, 0, 0))
	var pc := M.part(S, 0.4)   # charging pylon on the -y side with its cable and status light
	M.box(pc, T, Vector3(0.9, -1.78, 0.75), Vector3(0.14, 0.1, 0.6), steel)
	M.dpx(pc, T, Vector3(0.9, -1.885, 1.15), CN_BLUE, Vector3(0, -1, 0))
	M.dpx(pc, T, Vector3(0.9, -1.885, 1.05), AMBER, Vector3(0, -1, 0))
	M.dline(pc, T, Vector3(0.9, -1.885, 0.6), Vector3(1.3, -1.9, 0.18), dk[0], Vector3(0, -1, 0))
	M.shadow(cv, S, o)
	M.render_z(cv, S, o, 191 + f)


static func build(out: Dictionary) -> void:
	for b in [false, true]:
		var id := "g8_b_cargo_carrier" if b else "g8_cargo_carrier"
		var bb: bool = b
		C.unit_sheet(out, id, "vehicles", "vehicle", 64, 52, Vector2i(32, 33), CAR_FRAMES,
			func(cv, k, f, o): carrier(cv, k, f, o, bb),
			{"art": "ART8C", "size_m": [CL, CW, 1.95], "scale": "4 m/tile, 9.8 px/m (fact art.scale)",
			"faction": "human_b" if b else "human_a", "key_frames": CAR_FRAMES.duplicate()})
	C.unit_sheet(out, "g8_supply_pod", "vehicles", "vehicle", 48, 44, Vector2i(24, 30), POD_FRAMES,
		func(cv, k, f, o): pod(cv, k, f, o),
		{"art": "ART8C", "size_m": [1.6, 1.3, 1.45], "scale": "4 m/tile, 9.8 px/m (fact art.scale)",
		"key_frames": POD_FRAMES.duplicate()})
	R7.bld2(out, "cn_carrier_garage", 1, 40, func(cv, o, f, opt): garage(cv, o, f, opt), [],
		{"art": "ART8C", "size_m": [3.9, 3.9, 3.25]})


func _init() -> void:
	var out := {"images": {}, "manifest": {"version": 2, "tile": [64, 32], "group": "g8_supply",
		"_note": "SUPPLY8 (13.9c-48) art, rev2 ART8C: tracked drone cargo carrier (A + B), airdrop supply pod, carrier garage. Generated by tools/art/g8_supply.gd on the g7 mesh pipeline.",
		"g7_detail_level": C.DL.duplicate(true)}}
	build(out)
	G7Anim.apply(out)   # anim61 selectors + muzzle / smoke points (every G6.1 frame is drawn by the model), re-measured bytes
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
	print("G7_ART group=g8_supply files=%d over=%d" % [files, over])
	quit(0)
