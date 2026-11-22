extends SceneTree
## G7.1 DAMAGE71 (G1 combat medics+): Human A field surgery tent art (a_g71_surgery_tent, content/g71/defs_g71_care.json):
## 3x3, a large ridge-roof surgical tent with red crosses on its front roof face, a white sterile module (red cross on
## its roof), stretchers and oxygen bottles at the receiving end, a generator, a sandbag berm on two sides, a team
## band and a red-cross flag pole. Same part renderer, palette, scaffold, stake, damage and icon pipeline as the FARP
## (tools/art/g71_farp.gd: g5_bld_lib.gd, bdetail.gd, g4_fort_lib.gd icon), at the G7 detail level (fact
## art.detail_level). Writes its own group assets/art/g71_damage/ (manifest.json), so it never touches another
## generator's files. Deterministic: re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g71_damage.gd                 # writes assets/art/g71_damage/
##   godot --headless --path . -s tools/art/g71_damage.gd -- --out=<abs dir>
## States: built, damaged (under 50% hp), build_0..2 (props rising under scaffold poles).
const GEN = preload("res://tools/gen_art.gd")
const P = preload("res://tools/art/pix.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")
const FL = preload("res://tools/art/g4_fort_lib.gd")
const GROUP := "g71_damage"
const DEF := "a_g71_surgery_tent"
const SIZE := 3
const TOP := 34
const SEED := 7171

const GRAVEL := Color8(124, 116, 92)
const FLOOR := Color8(104, 100, 80)
const CANVAS := Color8(196, 192, 168)
const CANVAS_D := Color8(150, 148, 126)
const MODULE := Color8(214, 214, 206)
const SAND := Color8(150, 134, 98)
const OLIVE := Color8(98, 100, 72)
const STRETCH := Color8(92, 104, 72)
const O2 := Color8(70, 140, 86)
const POLE_C := Color8(70, 66, 56)
const TEAM := Color8(200, 200, 200)
const RED := Color8(196, 34, 30)
const WHITE := Color8(236, 234, 226)
const BLOOD := Color8(110, 22, 18)


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
	print("G71_DAMAGE %s states=%d pivot=%s files=%d ms=%d" % [DEF, (e.states as Dictionary).size(), str(e.pivot), n, Time.get_ticks_msec() - t0])
	quit()


static func build() -> Dictionary:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": GROUP, "buildings": {}, "icons": {}}}
	var o: Vector2 = K.canvas(SIZE, TOP)[1]
	var entry := {"size": SIZE, "pivot": [int(o.x), int(o.y)], "states": {},
		"g71": {"kind": "surgery_tent", "faction": "a"},
		"fits": "3x3 field surgery tent: ridge tent + sterile module + stretchers behind a sandbag berm"}
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
static func parts() -> Array:
	var ps: Array = [[0, 0, 0, 1.46, 1.46, 1, GRAVEL, "slab"]]
	ps.append([-0.2, -0.15, 1, 1.0, 0.78, 0, FLOOR, "mat"])   # duckboard floor under the tent
	ps.append([-0.2, -0.15, 1, 0.92, 0.66, 18, CANVAS, "tent"])   # surgical tent (ridge along u)
	ps.append([1.02, -0.9, 1, 0.34, 0.4, 11, MODULE, "med"])   # sterile module, red cross on the roof
	ps.append_array([[0.05, 1.36, 1, 1.25, 0.07, 4, SAND, "bags"], [-1.36, 0.0, 1, 0.07, 1.2, 4, SAND, "bags"]])
	ps.append([-1.0, 1.36, 4.5, 0.2, 0.05, 2, TEAM, "team"])   # team band on the berm
	ps.append_array([[-0.62, 0.95, 1, 0.24, 0.08, 2, STRETCH, "stretch"], [0.02, 0.95, 1, 0.24, 0.08, 2, STRETCH, "stretch"],
		[0.66, 0.95, 1, 0.24, 0.08, 2, STRETCH, "stretch"]])
	ps.append_array([[1.22, 0.42, 1, 0.16, 0.12, 6, OLIVE, "gen"], [1.26, 0.86, 1, 0.05, 0.05, 7, O2, "cyl"],
		[1.14, 0.98, 1, 0.05, 0.05, 7, O2, "cyl"]])
	ps.append([-1.26, -1.26, 1, 0.02, 0.02, 26, POLE_C, "pole"])
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
	for p in ps.slice(1):
		if String(p[7]) == "mat":
			if not (raw and st == 0):
				K.part(cv, o, 0, p, 1.0, raw)
		else:
			up.append(p)
	K.render(cv, o, 0, up, hk, raw, func(c, oo, _ff, p, r): dress(c, oo, p, r))
	if raw:
		K.scaffold(cv, o, 0, ps, "a", hk)
		K.stake(cv, o, 0, -1.3, 1.3)
		K.stake(cv, o, 0, 1.3, -1.3)
	else:
		extras(cv, o)
	if dmg:
		K.damage(cv, o, SIZE, SEED)
	cv.outline()
	return cv


## Gravel texture, a worn path to the tent door, a few old blood stains at the receiving end.
static func _gravel(cv, o: Vector2) -> void:
	for i in 160:
		var u := (P.hn(i, SEED, 1) - 0.5) * 2.8
		var v := (P.hn(i, SEED, 2) - 0.5) * 2.8
		var q := K.pt(o, 0, u, v, 1.0)
		cv.px(int(q.x), int(q.y), P.mul(GRAVEL, 0.8 if P.hn(i, SEED, 3) < 0.5 else 1.14))
	K.gquad(cv, o, 0, -0.1, 0.62, 0.22, 1.3, 1.0, P.mul(GRAVEL, 0.86))
	for i in 7:
		var q := K.pt(o, 0, -0.7 + P.hn(i, SEED, 4) * 1.6, 1.08 + P.hn(i, SEED, 5) * 0.2, 1.0)
		cv.px(int(q.x), int(q.y), BLOOD)
		cv.px(int(q.x) + 1, int(q.y), P.mul(BLOOD, 0.8))


static func dress(cv, o: Vector2, p: Array, r: Dictionary) -> void:
	var col: Color = p[6]
	match String(p[7]):
		"med":
			K.cross(cv, r.top, 0.5, 0.5, 0.3)
			for sd in r.sides:
				cv.line_v(P.sub(sd.quad, 0, 0.35, 1, 0.35)[0], P.sub(sd.quad, 0, 0.35, 1, 0.35)[1], P.mul(col, 0.8))
		"bags":
			for sd in r.sides:
				for k in [0.33, 0.66]:
					var l := P.sub(sd.quad, 0, k, 1, k)
					cv.line_v(l[0], l[1], P.mul(col, 0.8))
		"stretch":   # olive canvas bed with two dark poles and a grey blanket roll
			var t: PackedVector2Array = r.top
			cv.poly(P.sub(t, 0.5, 0.1, 0.85, 0.9), P.mul(Color8(128, 128, 120), 1.0))
		"gen":
			var t2: PackedVector2Array = r.top
			cv.poly(P.sub(t2, 0.2, 0.25, 0.5, 0.75), P.mul(col, 0.7))


## Red crosses on the tent's front roof face and door, a red-cross flag on the pole.
static func extras(cv, o: Vector2) -> void:
	var u := -0.2
	var v := -0.15
	var hu := 0.92
	var hv := 0.66
	var e := 1.0 + 18.0 * 0.25
	var t := 1.0 + 18.0
	var face := PackedVector2Array([K.pt(o, 0, u - hu, v, t), K.pt(o, 0, u + hu, v, t), K.pt(o, 0, u + hu, v + hv, e), K.pt(o, 0, u - hu, v + hv, e)])
	K.cross(cv, face, 0.5, 0.5, 0.2)
	var door := PackedVector2Array([K.pt(o, 0, u - 0.18, v + hv, e), K.pt(o, 0, u + 0.18, v + hv, e), K.pt(o, 0, u + 0.18, v + hv, 1.0), K.pt(o, 0, u - 0.18, v + hv, 1.0)])
	cv.poly(door, P.mul(CANVAS_D, 0.7))
	var tip := K.pt(o, 0, -1.26, -1.26, 1.0 + 26.0)
	cv.rect(int(tip.x) + 1, int(tip.y), 8, 6, WHITE)
	cv.rect(int(tip.x) + 4, int(tip.y) + 1, 2, 4, RED)
	cv.rect(int(tip.x) + 3, int(tip.y) + 2, 4, 2, RED)
