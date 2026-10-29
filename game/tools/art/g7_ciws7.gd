extends SceneTree
## G7 CIWS7 (spec G7_REFERENCE 13.9c-32; owner: "add in phalanx style turret(s) on top of main command building inside
## facility / future modified anti machine version of the us phlanx Gatling style turret belt fed"). Art for def
## cn_ciws7 "Thresher Rotary CIWS": the two rotary point-defence mounts on the command centre roof
## (sim/systems/ciws7.gd). An ORIGINAL design, not a copy of a real model: a squat octagonal roof plinth, an armoured
## training mount with a sloped electronics cabinet and two trunnion cheeks; the elevating mass carries a faceted
## ceramic track radome with a flat-panel search array on its crown, a 7-barrel rotary cannon in a ventilated shroud
## under the radome's chin, and an olive side ammo drum feeding the receiver through an armoured belt chute (brass
## links visible), with the spent-case chute on the right. Opaque throughout (13.9c-18): no translucent pixels.
##
## Modelled in real metres with ARTCN7's faceted renderer (tools/art/g7_cn_mesh.gd) at the ONE real-world scale
## (fact art.scale, DL7-3: 4 m per tile, 9.8 px per metre of height). Drawn round its roof base point o (z 0 = the
## command centre roof); the manifest pivot is lifted by the roof height and the view sort shift, so the catalog
## places the sprite on the roof although the sim entity stands below it (sim e.pos = mount point + 0.6 tiles):
##   pivot = [o.x, o.y + round(ROOF_Z * 9.8) + SORT_PX]   (ROOF_Z 15.52 m roof brim, SORT_PX 19 = 0.6 tile x 32 px)
##
## States (presentation/art/g5_art.gd building_state, cw branch, keyed on cw0_3; sim frame code facing_i = el*8 + ph):
## CIWS7-5 (13.9c-32a "shooting in a strait line wherever the barrel is point"): NY = 32 yaw frames (11.25 deg, was 8)
## x 6 elevation bands (was 3) so the drawn barrels point down the tracer stream; the bands are content
## defs_g7_ciws.json ciws7.elev.bands_deg (the sim picks the one nearest the real elevation to the target).
## CIWS7-6 (13.9c-32b, owner: "Realistic: ~25 deg limit"): the mount cannot aim lower than elev.depress_min_deg (-25), so
## the aim bands are re-picked inside the real span of engageable targets (-25, -21.5, -18, -14.5 deg) and the generator
## refuses (G7_ART ... DEPRESS_VIOLATION, exit 1) a band below the limit: no drawn barrel points lower.
##   cw<k>_<el>_s      barrels spinning (solid blur ring, streaks), mount trained to world bearing k * 11.25 deg
##                     (k 0..31), elevation band el: 0 -25, 1 -21.5, 2 -18, 3 -14.5 deg (ground / low drones),
##                     5 high +32 deg (shell / rocket / missile intercepts); band 4 (level +8, rest) has no _s / _fire
##   cw<k>_<el>_fire   spinning + muzzle flash at the barrel cluster + tracer start + brass from the case chute
##   cw<k>_4           idle at rest (level); the picker shows it for an idle mount in any band
##   cw<k>_r           (even k only) drum swap: side hatch open, empty drum on the roof, an engineer kneeling with the fresh drum
##   cw<k>_x           (even k only) dry: barrels parked low, red DRY lamp on the cabinet
##   built (full-canvas copy of cw28_4), build_0..2 (SUITART7: construction stages, cropped, own pivot), rot_0..3 / fire (aliases of cw0/8/16/24_4, cw28_2_fire),
##   damaged (cw28_4 + damage), destroyed (wrecked mount)
## Byte budget (C.BUDGET.turret): every frame is cropped to its opaque rect (a band's _s / _fire share ONE rect,
## so muzzle7 can diff them) and carries its own "pivot" (= entry pivot - crop origin; presentation/view/batch_art.gd
## draws a state at its own pivot). Barrel states also carry the analytic barrel from the 3D model: "mz" muzzle px from
## the state pivot, "ax" the barrel's screen direction, "mz3" / "ax3" the muzzle (m from the roof base point) and the
## bore direction in world metres (x, y tile axes, z up): tests / fx measure the barrel-vs-stream angle from them.
## Deterministic: re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g7_ciws7.gd [-- --out=<abs dir>]   (default assets/art/g7_ciws7/)
## Prints "G7_ART cn_ciws7 bytes=<n> budget=<n> states=<n> ok|OVER" and "G7_ART group=g7_ciws7 files=<n> over=<n>".

const GEN = preload("res://tools/gen_art.gd")
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const M = preload("res://tools/art/g7_cn_mesh.gd")
const GR = preload("res://tools/art/g7_cn_gear.gd")
const FIG = preload("res://tools/art/g7_cn_fig.gd")
const SO = preload("res://tools/art/g7_cn_soldiers.gd")
const H = preload("res://tools/art/g6_lib.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")

const ID := "cn_ciws7"
const GROUP := "g7_ciws7"
const ROOF_Z := 15.52          # command centre roof brim (fact facb7.zone_heights seq 4583)
const SORT_PX := 19            # sim e.pos = mount point + (0.6, 0.6) tiles = +19.2 px screen y
const TOP := 46                # px of canvas above the base diamond's top corner (radome, elevated barrels)
const PAD := [8, 6]            # extra px each side / below (barrels trained across the screen, kneeling engineer)
const NY := 32                 # CIWS7-5: yaw frames (11.25 deg); drum swap / dry frames every 2nd yaw (22.5 deg)
const EL_REST := 4             # level band (rest / idle frames only)
const EL_FALLBACK := [-25.0, -21.5, -18.0, -14.5, 8.0, 32.0]
const DEPRESS_FALLBACK := -25.0
static var depress_violation := false


## Elevation bands (deg) from content (defs_g7_ciws.json buildings.cn_ciws7.ciws7.elev.bands_deg), read as a file so
## the tool runs without autoloads.
static func bands() -> Array:
	var txt := FileAccess.get_file_as_string("res://content/g7/defs_g7_ciws.json")
	var j = JSON.parse_string(txt) if txt != "" else null
	if j is Dictionary:
		var e = j.get("buildings", {}).get(ID, {}).get("ciws7", {}).get("elev", {})
		if e is Dictionary and e.get("bands_deg") is Array and (e.bands_deg as Array).size() >= 5:
			return e.bands_deg
	return EL_FALLBACK


## Depression limit (deg) from content (elev.depress_min_deg), same file read as bands().
static func depress_min() -> float:
	var txt := FileAccess.get_file_as_string("res://content/g7/defs_g7_ciws.json")
	var j = JSON.parse_string(txt) if txt != "" else null
	if j is Dictionary:
		var e = j.get("buildings", {}).get(ID, {}).get("ciws7", {}).get("elev", {})
		if e is Dictionary and e.has("depress_min_deg"):
			return float(e.depress_min_deg)
	return DEPRESS_FALLBACK
const PIVOT_Z := 1.22          # elevation trunnion height above the turntable top (m)

const HULL := Color8(112, 120, 124)       # slate gunmetal armour
const HULL_D := Color8(84, 90, 96)
const DOME := Color8(196, 198, 188)       # ceramic radome
const DOME_D := Color8(150, 154, 146)
const STEEL := Color8(82, 86, 90)
const DARK := Color8(40, 43, 46)
const BARREL := Color8(80, 84, 88)
const BLUR := Color8(128, 132, 134)
const DRUM := Color8(112, 118, 78)        # olive ammo drum
const BRASS := Color8(196, 158, 72)
const BRASS_D := Color8(150, 116, 52)
const CONC := Color8(128, 128, 122)
const GLASS := Color8(64, 110, 132)
const RED := Color8(236, 52, 40)
const TRACER := Color8(255, 214, 120)


static func _ramp(c: Color, wreck: bool) -> Array:
	return C.ramp(c.darkened(0.45) if wreck else c)


## Team ID marking (mask pixels): thin plate + a flat team decal on both of its broad faces.
static func team_patch(pt: Dictionary, T: Dictionary, c: Vector3, h: Vector3, rp: Array) -> void:
	M.box(pt, T, c, h, rp)
	var ax := 2
	if h.x <= h.y and h.x <= h.z:
		ax = 0
	elif h.y <= h.x and h.y <= h.z:
		ax = 1
	var n := Vector3.ZERO
	n[ax] = 1.0
	var u := Vector3.ZERO
	var v := Vector3.ZERO
	u[(ax + 1) % 3] = h[(ax + 1) % 3]
	v[(ax + 2) % 3] = h[(ax + 2) % 3]
	for s in [1.0, -1.0]:
		var cc: Vector3 = c + n * (h[ax] + 0.004) * s
		M.dpoly(pt, T, [cc - u - v, cc + u - v, cc + u + v, cc - u + v], Color8(152, 152, 152), n * s, true)


## The mount. k = world bearing step (yaw k * 360 / NY deg); opt: el (band index), spin, fire, swap, dry, wreck, pitch
## (rad, overrides el). Writes the analytic barrel into opt: mz3 / ax3 (world m / unit dir), mz_px / ax_px (screen).
static func ciws(cv, o: Vector2, k: int, opt: Dictionary) -> void:
	var yaw := float(k) * TAU / float(NY)
	var wreck := bool(opt.get("wreck", false))
	var spin := bool(opt.get("spin", false)) or bool(opt.get("fire", false))
	var fire := bool(opt.get("fire", false))
	var swap := bool(opt.get("swap", false))
	var dry := bool(opt.get("dry", false))
	var bd: Array = opt.get("bands", EL_FALLBACK)
	var pitch: float = float(opt.get("pitch", deg_to_rad(float(bd[clampi(int(opt.get("el", EL_REST)), 0, bd.size() - 1)]))))
	var S: Array = []
	var hull: Array = _ramp(HULL, wreck)
	var hulld: Array = _ramp(HULL_D, wreck)
	var steel: Array = _ramp(STEEL, wreck)
	var dk: Array = _ramp(DARK, wreck)
	var dome: Array = _ramp(DOME, wreck)
	var domed: Array = _ramp(DOME_D, wreck)
	var drum: Array = _ramp(DRUM, wreck)
	var conc: Array = _ramp(CONC, false)

	# --- fixed roof plinth (does not train): octagonal concrete ring with a steel deck ring and bolts, cable duct
	var T0 := M.pose(o, 0.0)
	var pb := M.part(S, -1)
	M.cyl(pb, T0, Vector3(0, 0, 0.11), Vector3(0, 0, 1), 1.22, 0.11, 8, conc, {"cap_t": 2}, PI / 8.0)
	M.cyl(pb, T0, Vector3(0, 0, 0.27), Vector3(0, 0, 1), 1.04, 0.05, 16, steel, {"cap_t": 1})
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		M.dpx(pb, T0, Vector3(cos(a) * 1.12, sin(a) * 1.12, 0.225), Color8(70, 70, 66), Vector3(0, 0, 1))
	M.box(pb, T0, Vector3(-1.05, 0.62, 0.12), Vector3(0.34, 0.13, 0.1), steel)   # power / data duct to the roof hatch
	for i in 3:   # hazard chevrons on the duct
		M.dline(pb, T0, Vector3(-1.3 + i * 0.2, 0.75, 0.2), Vector3(-1.22 + i * 0.2, 0.75, 0.05), GR.HAZ if i % 2 == 0 else GR.HAZ_D, Vector3(0, 1, 0))

	# --- training mount: turntable, sloped armoured base, rear electronics cabinet, two trunnion cheeks
	var Tt := M.pose(o, yaw, Vector3(0, 0, 0.32))
	var pt := M.part(S, 0)
	M.cyl(pt, Tt, Vector3(0, 0, 0.07), Vector3(0, 0, 1), 0.96, 0.07, 12, dk, {"cap_t": 1})
	M.box(pt, Tt, Vector3(-0.12, 0, 0.42), Vector3(0.72, 0.6, 0.28), hull, Vector3(0.3, 0.12, 0.14))
	for s in [-1.0, 1.0]:   # panel seams + access panel on the base sides
		M.dline(pt, Tt, Vector3(-0.5, s * 0.605, 0.2), Vector3(-0.5, s * 0.605, 0.62), C.ca(hull[1], 1.0), Vector3(0, s, 0))
		M.dline(pt, Tt, Vector3(0.2, s * 0.605, 0.2), Vector3(0.2, s * 0.605, 0.62), C.ca(hull[1], 1.0), Vector3(0, s, 0))
		M.dline(pt, Tt, Vector3(-0.4, s * 0.605, 0.3), Vector3(0.1, s * 0.605, 0.3), C.ca(hull[4], 1.0), Vector3(0, s, 0))
	M.box(pt, Tt, Vector3(-0.72, 0, 0.78), Vector3(0.26, 0.46, 0.3), hulld, Vector3(0.0, 0.1, 0.06))   # cabinet
	for i in 4:   # cabinet louvres (rear face)
		M.dline(pt, Tt, Vector3(-0.99, -0.3, 0.62 + i * 0.09), Vector3(-0.99, 0.3, 0.62 + i * 0.09), C.ca(hulld[0], 1.0), Vector3(-1, 0, 0))
	team_patch(pt, Tt, Vector3(-0.66, 0.0, 1.085), Vector3(0.16, 0.3, 0.012), hulld)
	M.dpx(pt, Tt, Vector3(-0.47, 0.32, 1.0), RED if dry else GR.LED_G, Vector3(1, 0, 0))
	if dry:   # DRY lamp: a red beacon block on the cabinet roof
		M.box(pt, Tt, Vector3(-0.66, -0.28, 1.15), Vector3(0.07, 0.07, 0.07), C.ramp(RED))
		M.dpx(pt, Tt, Vector3(-0.66, -0.28, 1.23), Color8(255, 150, 130), Vector3.ZERO)
	for s in [-1.0, 1.0]:
		M.box(pt, Tt, Vector3(0.12, s * 0.5, 0.98), Vector3(0.3, 0.075, 0.36), hull, Vector3(0.12, 0.08, 0.0))
		M.cyl(pt, Tt, Vector3(0.14, s * 0.58, PIVOT_Z), Vector3(0, 1, 0), 0.12, 0.04, 8, steel)   # trunnion boss

	# --- elevating mass (pitch): receiver cradle, radome, search array, gun, drum + belt chute, case chute
	var Te := M.sub(Tt, Vector3(0.14, 0, PIVOT_Z), 0.0, pitch)
	var pe := M.part(S, 1)
	M.box(pe, Te, Vector3(-0.08, 0, -0.02), Vector3(0.44, 0.4, 0.22), hulld, Vector3(0.1, 0.08, 0.04))   # cradle
	M.box(pe, Te, Vector3(0.36, 0, -0.06), Vector3(0.1, 0.2, 0.15), steel)   # gun mount block
	# faceted ceramic track radome above the gun (8 facets, tapered, chamfered crown)
	var rd := M.part(S, 1, 0.02)
	if wreck:
		M.cyl(rd, Te, Vector3(-0.1, 0, 0.42), Vector3(0, 0, 1), 0.5, 0.2, 8, dome, {"cap_t": 0}, PI / 8.0, 0.46)
		for i in 5:
			var a := TAU * float(i) / 5.0
			M.dline(rd, Te, Vector3(-0.1 + cos(a) * 0.48, sin(a) * 0.48, 0.62), Vector3(-0.1 + cos(a) * 0.3, sin(a) * 0.3, 0.3), Color8(30, 28, 26))
	else:
		M.cyl(rd, Te, Vector3(-0.1, 0, 0.27), Vector3(0, 0, 1), 0.6, 0.05, 10, dk, {"cap_t": 1}, PI / 10.0)   # equator band
		M.cyl(rd, Te, Vector3(-0.1, 0, 0.56), Vector3(0, 0, 1), 0.6, 0.24, 10, dome, {"caps": false}, PI / 10.0, 0.56)
		M.cyl(rd, Te, Vector3(-0.1, 0, 0.92), Vector3(0, 0, 1), 0.56, 0.12, 10, dome, {"caps": false}, PI / 10.0, 0.42)
		M.cyl(rd, Te, Vector3(-0.1, 0, 1.1), Vector3(0, 0, 1), 0.42, 0.06, 10, domed, {"cap_t": 1}, PI / 10.0, 0.24)
		# dark track-antenna window on the front facet + facet seams + a maintenance strap
		M.dpoly(rd, Te, [Vector3(0.51, -0.16, 0.38), Vector3(0.51, 0.16, 0.38), Vector3(0.49, 0.14, 0.74), Vector3(0.49, -0.14, 0.74)],
			Color8(58, 66, 70), Vector3(1, 0, 0))
		M.dline(rd, Te, Vector3(0.51, -0.16, 0.38), Vector3(0.51, 0.16, 0.38), Color8(120, 126, 122), Vector3(1, 0, 0))
		for s in [-1.0, 1.0]:   # facet seams + lifting lugs on the flanks
			M.dline(rd, Te, Vector3(-0.1, s * 0.6, 0.36), Vector3(-0.1, s * 0.56, 0.8), C.ca(domed[1], 1.0), Vector3(0, s, 0))
			M.dpx(rd, Te, Vector3(-0.1, s * 0.5, 1.02), C.ca(domed[0], 1.0), Vector3(0, s, 1))
		# flat-panel search array on a short post (crown)
		M.cyl(rd, Te, Vector3(-0.12, 0, 1.19), Vector3(0, 0, 1), 0.08, 0.04, 6, steel, {"edge": false})
		var Ta := M.sub(Te, Vector3(-0.12, 0, 1.27), float(opt.get("sweep", 0.0)), -1.2)
		M.box(rd, Ta, Vector3(0, 0, 0.0), Vector3(0.03, 0.34, 0.16), steel)
		M.dpoly(rd, Ta, [Vector3(0.035, -0.3, -0.12), Vector3(0.035, 0.3, -0.12), Vector3(0.035, 0.3, 0.12), Vector3(0.035, -0.3, 0.12)],
			Color8(96, 112, 118), Vector3(1, 0, 0))
		for i in 3:
			var u := -0.15 + i * 0.15
			M.dline(rd, Ta, Vector3(0.036, u, -0.12), Vector3(0.036, u, 0.12), Color8(52, 60, 64), Vector3(1, 0, 0))
		# EO / IR sight pod on the radome's right cheek
		M.box(rd, Te, Vector3(0.3, 0.6, 0.5), Vector3(0.12, 0.08, 0.09), dk)
		M.dpx(rd, Te, Vector3(0.43, 0.6, 0.51), GLASS, Vector3(1, 0, 0))
		M.dpx(rd, Te, Vector3(0.43, 0.57, 0.53), C.ramp(GLASS)[4], Vector3(1, 0, 0))

	# rotary cannon under the radome chin: ventilated shroud, 7 barrels, mid clamp, muzzle ring
	var pg := M.part(S, 1, -0.01)
	var gz := -0.06
	M.cyl(pg, Te, Vector3(0.95, 0, gz), Vector3(1, 0, 0), 0.2, 0.5, 8, steel, {"cap_t": 1})   # shroud f 0.45..1.45
	if not wreck:
		for i in 5:   # vent slots along the shroud
			var f := 0.58 + i * 0.18
			for s in [-1.0, 1.0]:
				M.dline(pg, Te, Vector3(f, s * 0.14, gz + 0.14), Vector3(f + 0.09, s * 0.14, gz + 0.14), Color8(24, 26, 28), Vector3(0, s, 1))
	var bl := 1.05 if not wreck else 0.5
	var f0 := 1.45
	var f1 := f0 + bl
	var bar: Array = _ramp(BARREL, wreck)
	if spin and not wreck:
		var blur: Array = C.ramp(BLUR)
		M.cyl(pg, Te, Vector3((f0 + f1) * 0.5, 0, gz), Vector3(1, 0, 0), 0.12, bl * 0.5, 10, blur, {"edge": false})
		for i in 3:   # motion streaks on the blurred cluster
			var z := gz - 0.08 + i * 0.08
			M.dline(pg, Te, Vector3(f0 + 0.05, 0.125, z), Vector3(f1 - 0.05, 0.125, z), Color8(170, 174, 176), Vector3(0, 1, 0))
			M.dline(pg, Te, Vector3(f0 + 0.05, -0.125, z), Vector3(f1 - 0.05, -0.125, z), Color8(170, 174, 176), Vector3(0, -1, 0))
	else:
		var ph := 0.0 if not wreck else 0.3
		for i in 7:
			var a := ph + TAU * float(i) / 7.0
			M.cyl(pg, Te, Vector3((f0 + f1) * 0.5, cos(a) * 0.085, gz + sin(a) * 0.085), Vector3(1, 0, 0), 0.032, bl * 0.5, 5, bar, {"edge": false, "caps": false})
	M.cyl(pg, Te, Vector3(f0 + bl * 0.55, 0, gz), Vector3(1, 0, 0), 0.135, 0.035, 10, steel, {"cap_t": 1})   # mid clamp
	M.cyl(pg, Te, Vector3(f1 - 0.03, 0, gz), Vector3(1, 0, 0), 0.125, 0.03, 10, dk, {"cap_t": 0})   # muzzle ring
	var mz := Vector3(f1 + 0.04, 0, gz)

	# ammo drum on the left of the cradle + armoured belt chute up to the receiver (brass links showing), case chute right
	var pd := M.part(S, 1, 0.01)
	if not swap:
		M.cyl(pd, Te, Vector3(-0.18, -0.7, -0.12), Vector3(1, 0, 0), 0.31, 0.36, 12, drum, {"cap_t": 1})
		for i in 3:   # hoop ribs
			var f := -0.42 + i * 0.24
			M.cyl(pd, Te, Vector3(f, -0.7, -0.12), Vector3(1, 0, 0), 0.325, 0.018, 12, _ramp(DRUM.darkened(0.25), wreck), {"edge": false})
		M.dline(pd, Te, Vector3(0.19, -0.86, 0.02), Vector3(0.19, -0.54, 0.02), GR.HAZ, Vector3(1, 0, 0))
	M.box(pd, Te, Vector3(0.0, -0.44, 0.12), Vector3(0.16, 0.08, 0.07), steel)   # belt chute
	if not wreck:
		for i in 6:   # brass links riding up the open-topped chute
			M.dpx(pd, Te, Vector3(-0.16 + i * 0.065, -0.44 + i * 0.012, 0.2), BRASS if i % 2 == 0 else BRASS_D, Vector3(0, 0, 1))
	M.box(pd, Te, Vector3(0.05, 0.36, -0.2), Vector3(0.1, 0.06, 0.08), steel)   # spent-case chute (right)
	if swap:   # side hatch hinged open, empty drum on the roof, engineer kneeling with the fresh drum
		M.box(pd, Te, Vector3(-0.18, -0.52, -0.42), Vector3(0.3, 0.2, 0.02), hulld)
		var Tr := M.pose(o, 0.0)
		var pr := M.part(S, 0)
		M.cyl(pr, Tr, Vector3(0.3, 1.3, 0.31), Vector3(1, -0.4, 0), 0.26, 0.3, 12, C.ramp(DRUM.darkened(0.3)), {"cap_t": 1})   # empty
		M.cyl(pr, Tr, Vector3(1.3, -0.25, 0.31), Vector3(0.3, 1, 0), 0.26, 0.3, 12, drum, {"cap_t": 1})   # fresh
		M.dline(pr, Tr, Vector3(1.4, 0.06, 0.4), Vector3(1.2, 0.06, 0.4), GR.HAZ, Vector3(0, 1, 0))
		_crew(S, Tr, Vector3(1.15, 0.62, 0.0), atan2(-0.62, -1.15), "crouch")

	if wreck:   # scorched debris on the plinth
		for i in 7:
			var a := TAU * float(i) / 7.0 + 0.4
			var r := 0.7 + 0.35 * P.hn(i, 3, 77)
			M.dpx(pb, T0, Vector3(cos(a) * r, sin(a) * r, 0.33), Color8(34, 32, 30), Vector3(0, 0, 1))

	var bm := M.wm(Te, mz)
	var bdir := M.wdir(Te, Vector3(1, 0, 0))
	opt["mz3"] = bm
	opt["ax3"] = bdir
	opt["mz_px"] = M.scr_w(o, bm)
	opt["ax_px"] = (M.scr_w(o, bm + bdir) - M.scr_w(o, bm))
	if fire:
		var wmz := bm
		var wdir := bdir
		var wej := M.wm(Te, Vector3(0.05, 0.42, -0.26))
		M.sprite(S, wmz, func(c2): _flash_draw(c2, o, wmz, wdir), 3.0)
		M.sprite(S, wej, func(c2): _brass_draw(c2, o, wej, k), 3.0)
	M.render_z(cv, S, o, 97 + k)


static func _crew(S: Array, T: Dictionary, p: Vector3, yaw: float, fname: String) -> void:
	var w := M.wm(T, p)
	var fk := posmod(int(round(yaw / (PI / 4.0))), 8)
	var kit := SO.kit("cn_medic")   # "combat medic / engineer" figure, engineer kit (no medic cross)
	kit["pack"] = "small"
	kit["chest"] = "none"
	kit["stripe"] = false
	var o: Vector2 = T.o
	M.sprite(S, w, func(cv): FIG.draw(cv, kit, fk, fname, M.scr_w(o, w)), 0.0, 0.0)


## Opaque muzzle flash at the barrel cluster: hot core, petals along the bore, the first metres of the tracer stream.
static func _flash_draw(cv, o: Vector2, wmz: Vector3, wdir: Vector3) -> void:
	var c := M.scr_w(o, wmz)
	var d := M.scr_w(o, wmz + wdir) - c
	if d.length() < 0.01:
		d = Vector2(0, -1)
	d = d.normalized()
	var n := Vector2(-d.y, d.x)
	for i in 9:   # tracer stream start (opaque)
		var q := c + d * (4.0 + i * 1.0)
		cv.px(int(round(q.x)), int(round(q.y)), TRACER if i % 3 != 2 else GR.FLASH)
	for i in 5:   # flash petals along the bore and to the sides
		var q := c + d * float(i)
		cv.px(int(round(q.x)), int(round(q.y)), GR.FLASH if i < 3 else GR.FLASH_O)
		if i >= 1 and i <= 3:
			var s := 1.0 + (1.0 if i == 2 else 0.0)
			for sg in [-1.0, 1.0]:
				var e: Vector2 = q + n * s * sg
				cv.px(int(round(e.x)), int(round(e.y)), GR.FLASH_O)
	cv.px(int(round(c.x)), int(round(c.y)), Color8(255, 250, 230))
	var c1 := c + d
	cv.px(int(round(c1.x)), int(round(c1.y)), Color8(255, 250, 230))


## Spent cases falling out of the right-hand case chute (opaque brass pixels, deterministic per k).
static func _brass_draw(cv, o: Vector2, wej: Vector3, k: int) -> void:
	var c := M.scr_w(o, wej)
	for i in 5:
		var dx := (P.hn(i, k, 31) - 0.5) * 6.0
		var dy := 1.0 + i * 1.6
		cv.px(int(round(c.x + dx)), int(round(c.y + dy)), BRASS if i % 2 == 0 else BRASS_D)


# ------------------------------------------------------------------ build + generator
static func _cv() -> Array:
	var w := 64 + 12 + 2 * int(PAD[0])
	var o := Vector2(w / 2, TOP + 16)
	return [P.Canvas.new(w, int(o.y) + 16 + 6 + int(PAD[1])), o]


static func _put(out: Dictionary, entry: Dictionary, nm: String, k: int, opt: Dictionary) -> int:
	return _group(out, entry, [[nm, k, opt]], false)


## Renders the states of one group [[name, k, opt], ...], crops them all to the union of their opaque rects and stores
## each with its own pivot (+ the analytic barrel for barrel states). full = keep the whole canvas (built family).
static func _group(out: Dictionary, entry: Dictionary, items: Array, full: bool) -> int:
	var cvs: Array = []
	var u := Rect2i()
	for it in items:
		var co: Array = _cv()
		ciws(co[0], co[1], int(it[1]), it[2])
		C.selout(co[0])
		cvs.append(co[0])
		var r: Rect2i = (co[0].img as Image).get_used_rect()
		if r.size.x > 0:
			u = r if u.size.x == 0 else u.merge(r)
	if full or u.size.x == 0:
		u = Rect2i(0, 0, int(cvs[0].w), int(cvs[0].h))
	var piv: Array = entry.pivot
	var pv := Vector2(float(piv[0]), float(piv[1]))
	var bytes := 0
	for i in items.size():
		var nm := String(items[i][0])
		var opt: Dictionary = items[i][2]
		var f := "buildings/%s_%s.png" % [ID, nm]
		var mk := "buildings/%s_%s_mask.png" % [ID, nm]
		out.images[f] = (cvs[i].img as Image).get_region(u)
		out.images[mk] = (cvs[i].mask as Image).get_region(u)
		var sd := {"file": f, "mask": mk}
		if not full:
			sd["pivot"] = [int(piv[0]) - u.position.x, int(piv[1]) - u.position.y]
		if opt.has("mz_px") and not bool(opt.get("wreck", false)):
			var mzp: Vector2 = Vector2(opt.mz_px) - pv   # px from the drawn pivot (the entity's ground point)
			var ax: Vector2 = opt.ax_px
			var m3: Vector3 = opt.mz3
			var a3: Vector3 = opt.ax3
			sd["mz"] = [snappedf(mzp.x, 0.01), snappedf(mzp.y, 0.01)]
			sd["ax"] = [snappedf(ax.x, 0.001), snappedf(ax.y, 0.001)]
			sd["mz3"] = [snappedf(m3.x, 0.001), snappedf(m3.y, 0.001), snappedf(m3.z, 0.001)]
			sd["ax3"] = [snappedf(a3.x, 0.0001), snappedf(a3.y, 0.0001), snappedf(a3.z, 0.0001)]
		entry.states[nm] = sd
		bytes += u.size.x * u.size.y * 4
	return bytes


static func build(out: Dictionary) -> void:
	var man: Dictionary = out.manifest.get("buildings", {})
	var co0: Array = _cv()
	var o: Vector2 = co0[1]
	var lift := roundi(ROOF_Z * M.ZP) + SORT_PX
	var entry := {"size": 1, "pivot": [int(o.x), int(o.y) + lift], "fw": int(co0[0].w), "fh": int(co0[0].h),
		"states": {}, "g6": {"variants": "rot", "faction": "c"}}
	var bd: Array = bands()
	var lim := depress_min()
	for i in bd.size():   # CIWS7-6: no drawn barrel below the depression limit (the parked dry frame is -12.6 deg, the wreck -24)
		if float(bd[i]) < lim - 0.001:
			print("G7_ART cn_ciws7 DEPRESS_VIOLATION band %d = %.1f deg < limit %.1f" % [i, float(bd[i]), lim])
			depress_violation = true
			return
	var bytes := 0
	for k in NY:
		var sw := 0.6 * float(k % 3 - 1)
		for el in bd.size():
			var g: Array = [["cw%d_%d_s" % [k, el], k, {"el": el, "spin": true, "bands": bd}],
				["cw%d_%d_fire" % [k, el], k, {"el": el, "fire": true, "bands": bd}]]
			if el == EL_REST:   # rest: the idle frame only (a mount spinning down keeps its firing band)
				g = [["cw%d_%d" % [k, el], k, {"el": el, "sweep": sw, "bands": bd}]]
			bytes += _group(out, entry, g, false)
		if k % 2 == 0:   # parked states (drum swap, dry): every 2nd yaw is enough (the mount is not tracking)
			bytes += _put(out, entry, "cw%d_r" % k, k, {"el": EL_REST, "pitch": 0.0, "swap": true, "bands": bd})
			bytes += _put(out, entry, "cw%d_x" % k, k, {"el": EL_REST, "pitch": -0.22, "dry": true, "bands": bd})
	var kb := NY * 7 / 8   # rest bearing of the built / icon frame (315 deg, as before)
	bytes += _group(out, entry, [["built", kb, {"el": EL_REST, "bands": bd}]], true)
	var dm: Array = _cv()
	ciws(dm[0], dm[1], kb, {"el": EL_REST, "bands": bd})
	K.damage(dm[0], o, 1, 7713)
	C.selout(dm[0])
	var du: Rect2i = (dm[0].img as Image).get_used_rect()
	out.images["buildings/%s_damaged.png" % ID] = (dm[0].img as Image).get_region(du)
	out.images["buildings/%s_damaged_mask.png" % ID] = (dm[0].mask as Image).get_region(du)
	entry.states["damaged"] = {"file": "buildings/%s_damaged.png" % ID, "mask": "buildings/%s_damaged_mask.png" % ID,
		"pivot": [int(entry.pivot[0]) - du.position.x, int(entry.pivot[1]) - du.position.y]}
	bytes += du.size.x * du.size.y * 4
	bytes += _put(out, entry, "destroyed", kb, {"el": 0, "pitch": -0.42, "wreck": true, "bands": bd})
	# SUITART7: real construction stages (were copies of built): H.stage of the rest frame's pre-outline drawing (the
	# same stage pass every facility part uses), cropped to the opaque rect with their own pivot like damaged.
	var bc: Array = _cv()
	ciws(bc[0], bc[1], kb, {"el": EL_REST, "bands": bd})
	var base = H.copy(bc[0])
	for st in 3:
		var sc = H.stage(base, o, 0, 1, "a", st, 7720)
		var su: Rect2i = (sc.img as Image).get_used_rect()
		var nm := "build_%d" % st
		out.images["buildings/%s_%s.png" % [ID, nm]] = (sc.img as Image).get_region(su)
		out.images["buildings/%s_%s_mask.png" % [ID, nm]] = (sc.mask as Image).get_region(su)
		entry.states[nm] = {"file": "buildings/%s_%s.png" % [ID, nm], "mask": "buildings/%s_%s_mask.png" % [ID, nm],
			"pivot": [int(entry.pivot[0]) - su.position.x, int(entry.pivot[1]) - su.position.y]}
		bytes += su.size.x * su.size.y * 4
	var q := NY / 4
	for pr in [["rot_0", "cw0_%d" % EL_REST], ["rot_1", "cw%d_%d" % [q, EL_REST]], ["rot_2", "cw%d_%d" % [2 * q, EL_REST]],
			["rot_3", "cw%d_%d" % [3 * q, EL_REST]], ["fire", "cw%d_2_fire" % kb]]:
		entry.states[pr[0]] = (entry.states[pr[1]] as Dictionary).duplicate()
	entry["g7"] = {"detail_level": C.VERSION, "class": "turret", "bytes": bytes, "budget": int(C.BUDGET.turret),
		"ciws7": "Thresher Rotary CIWS (original design)", "scale": "4 m/tile, 9.8 px/m (fact art.scale), DL7-3",
		"yaws": NY, "bands_deg": bd.duplicate(), "rest_band": EL_REST, "cropped": true,
		"pivot_rule": "drawn round the roof base point o; pivot = o + (0, round(%.2f m x 9.8) + %d px sort shift); every state but built is cropped to its opaque rect and carries its own pivot" % [ROOF_Z, SORT_PX],
		"key_frames": ["cw4_4", "cw4_5_fire", "cw12_0_fire", "cw4_r", "cw4_x"],
		"anim_strip": ["cw4_4", "cw4_3_s", "cw4_3_fire", "cw4_5_s", "cw4_5_fire", "cw4_1_fire", "cw4_0_fire", "cw4_x", "cw4_r"]}
	man[ID] = entry
	out.manifest["buildings"] = man
	var img: Image = out.images[String(entry.states.built.file)]
	C.icon(out, ID, img, img.get_width(), img.get_height(), 0)


static func generate() -> Dictionary:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": GROUP,
		"g7_detail_level": C.DL.duplicate(true)}}
	build(out)
	return out


func _init() -> void:
	var out_dir := "res://assets/art/%s/" % GROUP
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6).path_join(GROUP) + "/"
	var r := generate()
	if depress_violation:
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	for sub in ["buildings", "icons"]:
		var bd := DirAccess.open(ProjectSettings.globalize_path(out_dir).path_join(sub))
		if bd != null:
			for fn in bd.get_files():
				if fn.ends_with(".png"):
					bd.remove(fn)
	var files := int(GEN.save(r, out_dir))
	var over := 0
	var man: Dictionary = r.manifest.get("buildings", {})
	for id in man:
		var g7: Dictionary = man[id].g7
		var ok := int(g7.bytes) <= int(g7.budget)
		if not ok:
			over += 1
		print("G7_ART %s bytes=%d budget=%d states=%d %s" % [id, int(g7.bytes), int(g7.budget), (man[id].states as Dictionary).size(), "ok" if ok else "OVER"])
	print("G7_ART group=%s files=%d over=%d" % [GROUP, files, over])
	quit(0)
