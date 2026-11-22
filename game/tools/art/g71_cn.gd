extends SceneTree
## G7.1 CNOPS71 (J6 trauma + decon hospital, content/g71/defs_g71_cn.json): Human A hospital art, site A (ORCH
## 2026-11-22, PROVISIONAL): two 4x4 blocks astride the gate approach road north of the CN facility:
##   a_g71_hospital       trauma block: triage bay doors, surgery theatres + ICU under a flat roof with the rooftop
##                        medevac pad (H in a circle), red crosses, ambulance bay canopy, plant room
##   a_g71_hospital_wing  ward wing: recovery ward roof lights, decon shower bay (blue), scan gate arch, the sealed
##                        quarantine ward (hazard yellow / black band, sealed doors), prosthetics bay annex
## Same part renderer / scaffold / damage / icon pipeline as tools/art/g71_damage.gd (g5_bld_lib.gd, g4_fort_lib.gd),
## G7 detail level. Writes its own group assets/art/g71_cn/ (manifest.json). Deterministic.
##   godot --headless --path . -s tools/art/g71_cn.gd                 # writes assets/art/g71_cn/
##   godot --headless --path . -s tools/art/g71_cn.gd -- --out=<abs dir>
## States: built, damaged (under 50% hp), build_0..2.
const GEN = preload("res://tools/gen_art.gd")
const P = preload("res://tools/art/pix.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")
const FL = preload("res://tools/art/g4_fort_lib.gd")
const GROUP := "g71_cn"
const DEFS := ["a_g71_hospital", "a_g71_hospital_wing"]
const SIZE := 4
const SC := (SIZE * 0.5 - 0.04) / 1.46   # the part layout below was drawn at a 1.46 half-extent: scale it to the footprint
const TOP := 40
const SEED := 7177

const PAVE := Color8(118, 116, 108)
const CONC := Color8(196, 194, 184)
const CONC_D := Color8(150, 150, 142)
const ROOF := Color8(132, 134, 128)
const PAD := Color8(70, 74, 72)
const GLASS := Color8(96, 130, 150)
const PLANT := Color8(104, 108, 100)
const RED := Color8(196, 34, 30)
const WHITE := Color8(236, 234, 226)
const DECON := Color8(70, 120, 170)
const HAZ := Color8(214, 178, 40)
const BLACK := Color8(30, 30, 28)
const TEAM := Color8(200, 200, 200)
const STEEL := Color8(120, 124, 130)


func _init() -> void:
	var dir := "res://assets/art/%s/" % GROUP
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			dir = String(a).substr(6)
	var t0 := Time.get_ticks_msec()
	var out := build()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var n := GEN.save(out, dir)
	for d in DEFS:
		var e: Dictionary = out.manifest.buildings[d]
		print("G71_CN %s states=%d pivot=%s" % [d, (e.states as Dictionary).size(), str(e.pivot)])
	print("G71_CN vehicles=%s" % str((out.manifest.vehicles as Dictionary).keys()))
	print("G71_CN files=%d ms=%d" % [n, Time.get_ticks_msec() - t0])
	quit()


static func build() -> Dictionary:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": GROUP, "buildings": {}, "icons": {}}}
	var o: Vector2 = K.canvas(SIZE, TOP)[1]
	for d in DEFS:
		var wing := String(d).ends_with("_wing")
		var entry := {"size": SIZE, "pivot": [int(o.x), int(o.y)], "states": {},
			"g71": {"kind": "hospital_wing" if wing else "hospital", "faction": "a"},
			"fits": ("4x4 ward wing: recovery ward, decon showers, scan gate, sealed quarantine, prosthetics bay" if wing
				else "4x4 trauma block: triage bay, surgery theatres, ICU, rooftop medevac pad")}
		_put(out, entry, d, "built", _state(wing, -1, false))
		_put(out, entry, d, "damaged", _state(wing, -1, true))
		for st in 3:
			_put(out, entry, d, "build_%d" % st, _state(wing, st, false))
		out.manifest.buildings[d] = entry
		var s: Dictionary = entry.states.built
		out.manifest.icons[d] = FL.icon(out, d, String(s.file), String(s.mask), "")
	_vehicles(out)
	return out


static func _put(out: Dictionary, entry: Dictionary, d: String, nm: String, cv) -> void:
	var f := "buildings/%s_%s.png" % [d, nm]
	var mk := "buildings/%s_%s_mask.png" % [d, nm]
	out.images[f] = cv.img
	out.images[mk] = cv.mask
	entry.states[nm] = {"file": f, "mask": mk}


## Part list [u, v, z, hu, hv, hz, colour, role] in the g5_bld_lib local frame (f 0: u = world x, v = world y).
static func parts(wing: bool) -> Array:
	var ps: Array = [[0, 0, 0, 1.46, 1.46, 1, PAVE, "slab"]]
	if not wing:
		ps.append([-0.15, -0.2, 1, 1.05, 0.95, 30, CONC, "block"])      # surgery + ICU block, flat roof
		ps.append([-0.15, -0.2, 31, 0.62, 0.62, 2, PAD, "pad"])         # rooftop medevac pad
		ps.append([0.0, 1.12, 1, 0.9, 0.26, 12, CONC_D, "canopy"])      # triage / ambulance bay canopy
		ps.append([1.2, -0.95, 1, 0.22, 0.4, 16, PLANT, "plant"])       # plant room (oxygen, power)
		ps.append([1.2, 0.3, 1, 0.08, 0.08, 9, Color8(70, 140, 86), "cyl"])
		ps.append([-1.25, 1.25, 1, 0.02, 0.02, 34, STEEL, "pole"])
	else:
		ps.append([-0.35, -0.35, 1, 0.95, 0.9, 20, CONC, "ward"])       # recovery ward
		ps.append([0.95, -0.55, 1, 0.42, 0.62, 18, CONC_D, "quar"])     # sealed quarantine ward
		ps.append([-0.6, 1.05, 1, 0.55, 0.3, 10, DECON, "decon"])       # decon shower bay
		ps.append([0.45, 1.1, 1, 0.08, 0.3, 14, STEEL, "gate"])         # scan gate posts
		ps.append([0.95, 1.1, 1, 0.08, 0.3, 14, STEEL, "gate"])
		ps.append([1.1, 0.45, 1, 0.3, 0.25, 9, CONC, "pros"])           # prosthetics bay annex
	for p in ps:   # plan coordinates scale with the footprint, heights stay
		p[0] = float(p[0]) * SC
		p[1] = float(p[1]) * SC
		p[3] = float(p[3]) * SC
		p[4] = float(p[4]) * SC
	return ps


static func _state(wing: bool, st: int, dmg: bool):
	var cvo := K.canvas(SIZE, TOP)
	var cv = cvo[0]
	var o: Vector2 = cvo[1]
	var raw := st >= 0
	var hk: float = 1.0 if not raw else float([0.0, 0.45, 0.85][st])
	var ps := parts(wing)
	K.part(cv, o, 0, ps[0], 1.0, raw)
	_pave(cv, o)
	K.render(cv, o, 0, ps.slice(1), hk, raw, func(c, oo, _ff, p, r): dress(c, oo, p, r))
	if raw:
		K.scaffold(cv, o, 0, ps, "a", hk)
		K.stake(cv, o, 0, -1.3 * SC, 1.3 * SC)
		K.stake(cv, o, 0, 1.3 * SC, -1.3 * SC)
	elif not wing:
		var tip := K.pt(o, 0, -1.25 * SC, 1.25 * SC, 1.0 + 34.0)
		cv.rect(int(tip.x) + 1, int(tip.y), 8, 6, WHITE)
		cv.rect(int(tip.x) + 4, int(tip.y) + 1, 2, 4, RED)
		cv.rect(int(tip.x) + 3, int(tip.y) + 2, 4, 2, RED)
	if dmg:
		K.damage(cv, o, SIZE, SEED + (1 if wing else 0))
	cv.outline()
	return cv


## Paving texture and painted ambulance lanes.
static func _pave(cv, o: Vector2) -> void:
	for i in int(320 * SC * SC):
		var u := (P.hn(i, SEED, 1) - 0.5) * 2.8 * SC
		var v := (P.hn(i, SEED, 2) - 0.5) * 2.8 * SC
		var q := K.pt(o, 0, u, v, 1.0)
		cv.px(int(q.x), int(q.y), P.mul(PAVE, 0.86 if P.hn(i, SEED, 3) < 0.5 else 1.1))
	K.gquad(cv, o, 0, 0.0, 1.38 * SC, 1.2 * SC, 0.05 * SC, 1.0, WHITE)


static func dress(cv, o: Vector2, p: Array, r: Dictionary) -> void:
	var col: Color = p[6]
	match String(p[7]):
		"block", "ward", "canopy", "pros":
			for sd in r.sides:   # window bands
				for k in ([0.3, 0.62] if String(p[7]) == "block" else [0.45]):
					var l := P.sub(sd.quad, 0.08, k, 0.92, k)
					cv.line_v(l[0], l[1], GLASS)
			if String(p[7]) == "block" or String(p[7]) == "canopy":
				K.cross(cv, r.sides[0].quad if not (r.sides as Array).is_empty() else r.top, 0.5, 0.5, 0.18)
			if String(p[7]) == "ward":
				var t: PackedVector2Array = r.top
				for k in [0.25, 0.5, 0.75]:
					cv.poly(P.sub(t, k - 0.06, 0.2, k + 0.06, 0.8), GLASS)   # roof lights
		"pad":
			var t2: PackedVector2Array = r.top
			cv.poly(P.sub(t2, 0.08, 0.08, 0.92, 0.92), P.mul(col, 1.15))
			cv.poly(P.sub(t2, 0.34, 0.25, 0.42, 0.75), WHITE)   # H
			cv.poly(P.sub(t2, 0.58, 0.25, 0.66, 0.75), WHITE)
			cv.poly(P.sub(t2, 0.42, 0.46, 0.58, 0.54), WHITE)
			K.cross(cv, P.sub(t2, 0.72, 0.72, 0.95, 0.95), 0.5, 0.5, 0.4)
		"quar":
			for sd in r.sides:   # hazard band + sealed door
				var l1 := P.sub(sd.quad, 0, 0.2, 1, 0.2)
				cv.line_v(l1[0], l1[1], HAZ)
				var l2 := P.sub(sd.quad, 0, 0.26, 1, 0.26)
				cv.line_v(l2[0], l2[1], BLACK)
				cv.poly(P.sub(sd.quad, 0.4, 0.5, 0.6, 1.0), P.mul(STEEL, 0.8))
		"decon":
			var t3: PackedVector2Array = r.top
			for k in [0.2, 0.4, 0.6, 0.8]:
				cv.poly(P.sub(t3, k - 0.04, 0.3, k + 0.04, 0.7), WHITE)   # shower heads
		"gate":
			var t4: PackedVector2Array = r.top
			cv.poly(P.sub(t4, 0.1, 0.1, 0.9, 0.9), Color8(90, 200, 120))   # scan light
		"plant":
			var t5: PackedVector2Array = r.top
			cv.poly(P.sub(t5, 0.2, 0.2, 0.8, 0.8), P.mul(col, 0.7))


# ---------------------------------------------------------------- J6 hospital fleet (CNOPS71-7)
## a_g71_medevac_heli    = the G5 transport gunship sheet (every frame / facing, shadow, wreck) with a white roof
##                         panel and a red cross on the cabin: reads as "air ambulance" (team-tinted panels kept).
## a_g71_drone_ambulance = the G6 UGV sheet with a white roof box and a red cross: reads as "drone ambulance".
## Mark pixels are cleared from the team mask, so the cross never takes the team tint.
const VSRC := {"a_g71_medevac_heli": ["res://assets/art/g5_air/", "a_transport_gunship"],
	"a_g71_drone_ambulance": ["res://assets/art/g6_units/", "a_ugv"]}


static func _vehicles(out: Dictionary) -> void:
	var man: Dictionary = out.manifest
	man["vehicles"] = {}
	man["vehicle_wrecks"] = {}
	for id in ["a_g71_medevac_heli", "a_g71_drone_ambulance"]:
		var sd := String(VSRC[id][0])
		var base := String(VSRC[id][1])
		var sm: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(sd + "manifest.json"))
		var spec: Dictionary = (sm.vehicles[base] as Dictionary).duplicate(true)
		var heli := String(id).ends_with("heli")
		var img := _vload(sd + String(spec.file))
		var mask: Image = _vload(sd + String(spec.mask)) if spec.has("mask") else null
		var fw := int(spec.fw)
		var fh := int(spec.fh)
		for cy in range(0, img.get_height() - fh + 1, fh):
			for cx in range(0, img.get_width() - fw + 1, fw):
				_vmark(img, mask, Rect2i(cx, cy, fw, fh), heli)
		out.images["units/%s.png" % id] = img
		spec.file = "units/%s.png" % id
		if mask != null:
			out.images["units/%s_mask.png" % id] = mask
			spec.mask = "units/%s_mask.png" % id
		for sk in ["shadow", "shadow_sheet"]:
			if spec.get(sk) is Dictionary and (spec[sk] as Dictionary).has("file"):
				var rel := "units/%s_%s.png" % [id, sk]
				out.images[rel] = _vload(sd + String(spec[sk].file))
				spec[sk].file = rel
		spec["g71"] = {"base": base, "mark": "medevac white + red cross"}
		man.vehicles[id] = spec
		if (sm.get("vehicle_wrecks", {}) as Dictionary).has(base):
			var wrk: Dictionary = (sm.vehicle_wrecks[base] as Dictionary).duplicate(true)
			out.images["wrecks/%s_wreck.png" % id] = _vload(sd + String(wrk.file))
			wrk.file = "wrecks/%s_wreck.png" % id
			man.vehicle_wrecks[id] = wrk
		var ic := _vload(sd + String(sm.icons[base]))
		_vmark(ic, null, Rect2i(Vector2i.ZERO, ic.get_size()), heli)
		out.images["icons/%s.png" % id] = ic
		man.icons[id] = "icons/%s.png" % id


static func _vload(p: String) -> Image:
	var img := Image.load_from_file(p)
	if img == null:
		var tex = load(p)
		img = tex.get_image() if tex != null else Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	return img


static func _vput(img: Image, mask: Image, cell: Rect2i, x: int, y: int, c: Color) -> void:
	if x < cell.position.x or y < cell.position.y or x >= cell.end.x or y >= cell.end.y:
		return
	if img.get_pixel(x, y).a < 0.5:
		return   # only on the body, never into the air around it
	img.set_pixel(x, y, c)
	if mask != null and x < mask.get_width() and y < mask.get_height():
		mask.set_pixel(x, y, Color(0, 0, 0, 0))


## A white roof panel, then a red cross on it.
static func _vmark(img: Image, mask: Image, cell: Rect2i, heli: bool) -> void:
	var x0 := cell.end.x
	var y0 := cell.end.y
	var x1 := -1
	var y1 := -1
	for y in range(cell.position.y, cell.end.y):
		for x in range(cell.position.x, cell.end.x):
			if img.get_pixel(x, y).a > 0.5:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return
	var cx := (x0 + x1) / 2
	var cy := y0 + int(float(y1 - y0) * (0.42 if heli else 0.38))
	var r := 3 if (x1 - x0) >= 30 else 2
	if true:   # white backing for the cross (the team-tinted panels keep their tint: test_art team colour)
		for dy in range(-r - 1, r + 2):
			for dx in range(-r - 2, r + 3):
				_vput(img, mask, cell, cx + dx, cy + dy, WHITE)
	for d in range(-r, r + 1):
		_vput(img, mask, cell, cx + d, cy, RED)
		_vput(img, mask, cell, cx, cy + d, RED)
