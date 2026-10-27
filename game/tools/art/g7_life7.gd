extends SceneTree
## G7 LIFE7 (13.9c-7 "a living facility"): art for the display-only facility life layer
## (presentation/view/fac_life7.gd). Drawn at the approved DL7-3 detail level with ARTCN7's own rigs, at the ONE
## real-world scale (4 m per 64x32 tile, 9.8 px per metre of height, 1.8 m soldier = 18 px):
##  - figures (g7_cn_fig rig, 32x32 cell, pivot 16,27, 8 facings): base technician (olive coverall, hi-vis vest,
##    cap, tool bag), gate / wall guard (helmet, plate carrier, carbine, red MP brassard patch), ops-room staff
##    (dark duty uniform, headset), each with walk / run / work frames;
##  - a Malinois-type guard dog (8 facings, trot cycle, sniff, sit);
##  - work vehicles modelled in metres with g7_cn_mesh (per-pixel depth, faceted shading, 8 facings): a 3 m
##    military forklift (empty / loaded with a pallet of ammo crates, amber beacon on / off), an 8 m fuel bowser
##    (beacons on / off), a low aircraft tow tractor (beacons on / off);
##  - a perimeter quadcopter (8 facings, 2 rotor-blur frames);
##  - moving parts: a surveillance radar antenna (16 rotation frames), a tower remote-weapon cupola (16 aim frames);
##  - range: a Machine-replica pop-up target (up / half / down, facing +x and +y).
## Deterministic (pure hashes, no RNG): re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g7_life7.gd                         # writes assets/art/g7_life7/
##   godot --headless --path . -s tools/art/g7_life7.gd -- --out=<abs dir> --preview=<abs png>
## Prints "G7_LIFE7 sheets=<n> files=<n>".
const GEN = preload("res://tools/gen_art.gd")
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const M = preload("res://tools/art/g7_cn_mesh.gd")
const FIG = preload("res://tools/art/g7_cn_fig.gd")
const GROUP := "g7_life7"

const FIG_FRAMES := ["idle", "idle_1", "walk_a", "walk_1", "walk_2", "walk_b", "walk_4", "walk_5",
	"run_0", "run_1", "run_2", "run_3", "run_4", "run_5", "act_0", "act_1", "crouch"]
const SKIN := Color8(206, 160, 122)
const BOOT := Color8(58, 52, 44)
const KITS := {
	"tech": {"role": "base technician", "suit": Color8(104, 108, 84), "plate": Color8(78, 82, 64), "helm": Color8(66, 72, 58),
		"visor": SKIN, "boot": BOOT, "web": Color8(82, 80, 66), "head": "cap", "bulk": 2.3, "weapon": "none", "pack": "small",
		"act": "treat", "act_pose": {"crouch": 0.5}},
	"guard": {"role": "security guard", "suit": Color8(86, 92, 70), "plate": Color8(98, 100, 76), "helm": Color8(92, 96, 74),
		"visor": SKIN, "boot": BOOT, "web": Color8(72, 68, 52), "head": "helmet", "bulk": 2.5, "weapon": "carbine", "wlen": 6.5,
		"pack": "small", "act": "signal", "rc": Color8(214, 52, 44)},
	"staff": {"role": "ops-room staff", "suit": Color8(70, 76, 86), "plate": Color8(64, 70, 80), "helm": Color8(58, 46, 38),
		"visor": SKIN, "boot": Color8(40, 40, 42), "web": Color8(56, 60, 66), "head": "bare", "bulk": 2.2, "weapon": "none",
		"pack": "small", "act": "handset"},
}
const DOG_FRAMES := ["idle", "trot_0", "trot_1", "trot_2", "trot_3", "sniff", "sit"]
const OD := Color8(92, 98, 66)
const OD_DK := Color8(70, 74, 50)
const STEEL := Color8(96, 100, 100)
const DARK := Color8(46, 50, 52)
const TIRE := Color8(40, 40, 38)
const HUB := Color8(110, 112, 104)
const GLASS := Color8(70, 120, 140)
const AMBER := Color8(255, 176, 40)
const AMBER_OFF := Color8(120, 82, 34)
const CRATE := Color8(98, 104, 70)
const PALLET := Color8(128, 104, 70)
const STENCIL := Color8(222, 196, 70)
const HAZ := Color8(226, 180, 40)
const CONC := Color8(150, 152, 144)
const GUNM := Color8(62, 66, 66)
const RADAR := Color8(196, 200, 194)
const REPLICA := Color8(44, 46, 50)
const EYE := Color8(255, 60, 40)
const VEST := Color8(204, 198, 66)

var _preview := ""


func _init() -> void:
	var dir := "res://assets/art/%s" % GROUP
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			dir = String(a).substr(6)
		elif String(a).begins_with("--preview="):
			_preview = String(a).substr(10)
	var out := build()
	var n := GEN.save(out, dir)
	print("G7_LIFE7 sheets=%d files=%d" % [(out.manifest.life7 as Dictionary).size(), n])
	if _preview != "":
		_write_preview(out)
	quit()


# ------------------------------------------------------------------ sheets
## A sheet: frames across, facings (rows) down. draw = Callable(cv, k, fname, o).
static func _sheet(out: Dictionary, id: String, fw: int, fh: int, piv: Vector2i, frames: Array, rows: int, draw: Callable, sel := true, extra := {}) -> void:
	var img := Image.create(fw * frames.size(), fh * rows, false, Image.FORMAT_RGBA8)
	for k in rows:
		for i in frames.size():
			var cv = P.Canvas.new(fw, fh)
			draw.call(cv, k, String(frames[i]), Vector2(piv))
			if sel:
				C.selout(cv)
			img.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i(i * fw, k * fh))
	var f := "life7/%s.png" % id
	out.images[f] = img
	var e := {"file": f, "fw": fw, "fh": fh, "pivot": [piv.x, piv.y], "frames": frames.duplicate(), "rows": rows}
	e.merge(extra)
	out.manifest.life7[id] = e


static func build() -> Dictionary:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": GROUP, "life7": {},
		"life7_meta": {"detail_level": C.VERSION, "scale": C.DL.scale}}}
	for kid in ["tech", "guard", "staff"]:
		var kt: Dictionary = (KITS[kid] as Dictionary).duplicate(true)
		_sheet(out, "fig_" + kid, C.INF_CELL.x, C.INF_CELL.y, C.INF_PIVOT, FIG_FRAMES, 8,
			func(cv, k, fname, o): _figure(cv, kt, k, fname, o), true, {"kind": "figure", "role": kt.role})
	_sheet(out, "dog", 32, 24, Vector2i(16, 19), DOG_FRAMES, 8, func(cv, k, fname, o): _dog(cv, k, fname, o), true, {"kind": "dog"})
	_sheet(out, "forklift", 72, 60, Vector2i(36, 40), ["e0", "e1", "l0", "l1"], 8,
		func(cv, k, fname, o): _vehicle(cv, k, fname, o, "forklift"), true, {"kind": "vehicle", "len_m": 3.4})
	_sheet(out, "fuel_truck", 112, 84, Vector2i(56, 54), ["b0", "b1"], 8,
		func(cv, k, fname, o): _vehicle(cv, k, fname, o, "fuel"), true, {"kind": "vehicle", "len_m": 8.2})
	_sheet(out, "tow_tractor", 72, 52, Vector2i(36, 34), ["b0", "b1"], 8,
		func(cv, k, fname, o): _vehicle(cv, k, fname, o, "tug"), true, {"kind": "vehicle", "len_m": 3.6})
	_sheet(out, "drone", 28, 20, Vector2i(14, 12), ["r0", "r1"], 8,
		func(cv, k, fname, o): _vehicle(cv, k, fname, o, "drone"), true, {"kind": "air", "len_m": 0.9})
	var rot16 := []
	for i in 16:
		rot16.append("a%d" % i)
	_sheet(out, "radar", 56, 52, Vector2i(28, 40), rot16, 1, func(cv, _k, fname, o): _radar(cv, int(fname.substr(1)), o), true,
		{"kind": "part", "steps": 16})
	_sheet(out, "cupola", 44, 40, Vector2i(22, 28), rot16, 1, func(cv, _k, fname, o): _cupola(cv, int(fname.substr(1)), o), true,
		{"kind": "part", "steps": 16})
	_sheet(out, "target", 32, 32, Vector2i(16, 26), ["up", "half", "down"], 2, func(cv, k, fname, o): _target(cv, k, fname, o), true,
		{"kind": "part", "rows_face": ["+x", "+y"]})
	return out


# ------------------------------------------------------------------ figures
static func _figure(cv, kit: Dictionary, k: int, fname: String, o: Vector2) -> void:
	FIG.draw(cv, kit, k, fname, o)
	var R := {"a": k * PI / 4.0, "o": o, "sc": 1.0, "tilt": 0.0, "lean": 0.0}
	var front := C.depth(float(R.a), 1.0, 0.0) > -0.35
	var crouch := 3.4 if fname == "crouch" or fname.begins_with("act") and String(kit.act) == "treat" else 0.0
	var hz := 7.4 - crouch
	match String(kit.role):
		"base technician":   # reflective bands across the hi-vis vest + a tool bag on the hip
			var fs := 2.0 if front else -1.9   # hi-vis vest bands across the chest (front) or the back
			for zz in [3.0, 4.3]:
				cv.line_v(C.fpt(R, fs, -1.9, hz + zz), C.fpt(R, fs, 1.9, hz + zz), VEST)
			cv.line_v(C.fpt(R, fs, -1.9, hz + 3.6), C.fpt(R, fs, 1.9, hz + 3.6), Color8(236, 236, 214))
			var tb := C.fpt(R, -0.2, 2.6, hz + 0.2)
			C.blob(cv, tb, 1.0, C.ramp(Color8(150, 40, 34)))
		"security guard":    # red MP brassard on the left upper arm (both facings show one side)
			var ba := C.fpt(R, 0.0, -2.9, hz + 3.6)
			cv.rect(int(ba.x) - 1, int(ba.y), 2, 1, Color8(214, 52, 44))
		"ops-room staff":    # headset band
			var hc := C.fpt(R, 0.3, 0, hz + 7.6)
			cv.line_v(hc + Vector2(-1.6, -1.2), hc + Vector2(1.6, -1.2), Color8(36, 38, 40))


## Guard dog (Malinois): fawn coat, black saddle and mask, harness. Rig units as the soldier rig (~1 px).
static func _dog(cv, k: int, fname: String, o: Vector2) -> void:
	var R := {"a": k * PI / 4.0, "o": o, "sc": 1.0, "tilt": 0.0}
	var coat: Array = C.ramp(Color8(176, 132, 82))
	var dark: Array = C.ramp(Color8(58, 46, 36))
	var harn: Array = C.ramp(Color8(60, 66, 54))
	var ph := 0.0
	var sw := 0.0
	var sit := fname == "sit"
	var nose_dn := 0.0
	if fname.begins_with("trot_"):
		ph = TAU * float(int(fname.substr(5))) / 4.0
		sw = 1.6
	elif fname == "sniff":
		nose_dn = 2.6
	C.ground_shadow(cv, o + Vector2(0, 0.5), 5.0, 1.8)
	var parts := []
	var hip_z := 4.2 if not sit else 2.2
	var sh_z := 5.6
	for s in [-1.0, 1.0]:
		for fr in [1, 0]:   # front / hind legs
			var lf := 3.2 if fr == 1 else -3.0
			var pz := sh_z if fr == 1 else hip_z
			var off: float = sw * sin(ph + (0.0 if (s > 0) == (fr == 1) else PI))
			var foot := Vector3(lf + off + (1.6 if sit and fr == 0 else 0.0), s * 0.9, 0.4)
			parts.append({"d": C.fdep(R, lf, s * 1.0), "k": "leg", "a": Vector3(lf, s * 0.8, pz - 0.6), "b": foot})
	parts.append({"d": C.fdep(R, 0, 0), "k": "body"})
	parts.append({"d": C.fdep(R, 4.6, 0) + 0.02, "k": "head"})
	parts.append({"d": C.fdep(R, -4.4, 0) - 0.02, "k": "tail"})
	parts.sort_custom(func(x, y): return x.d < y.d)
	for q in parts:
		match String(q.k):
			"leg":
				var a := C.fpt(R, q.a.x, q.a.y, q.a.z)
				var b := C.fpt(R, q.b.x, q.b.y, q.b.z)
				C.tube(cv, a, b, 0.62, coat)
				C.blob(cv, b, 0.6, dark)
			"body":
				var a := C.fpt(R, -2.8, 0, hip_z + 0.4)
				var b := C.fpt(R, 3.0, 0, sh_z + 0.3)
				C.tube(cv, a, b, 1.55, coat)
				C.tube(cv, C.fpt(R, -1.8, 0, hip_z + 1.4), C.fpt(R, 2.0, 0, sh_z + 1.2), 1.0, dark)   # black saddle
				C.tube(cv, C.fpt(R, 1.6, -0.9, sh_z + 0.6), C.fpt(R, 1.6, 0.9, sh_z + 0.6), 0.7, harn)  # harness
				var hd := C.fpt(R, 1.4, 0, sh_z + 1.9)
				cv.px(int(hd.x), int(hd.y), Color8(226, 182, 48))                                        # harness light
			"head":
				var nk := C.fpt(R, 3.6, 0, sh_z + 1.4 - nose_dn * 0.5)
				var hc := C.fpt(R, 4.7, 0, sh_z + 2.4 - nose_dn)
				C.tube(cv, nk, hc, 0.95, coat)
				C.tube(cv, hc, C.fpt(R, 6.4, 0, sh_z + 1.7 - nose_dn), 0.7, dark)                         # black muzzle
				for s in [-1.0, 1.0]:
					var e0 := C.fpt(R, 4.4, s * 0.7, sh_z + 3.2 - nose_dn)
					var e1 := C.fpt(R, 4.2, s * 0.9, sh_z + 4.6 - nose_dn)
					C.tube(cv, e0, e1, 0.45, dark)                                                       # ears up
			"tail":
				var t0 := C.fpt(R, -2.9, 0, hip_z + 0.9)
				var t1 := C.fpt(R, -5.2, 0, hip_z - 0.6 + sin(ph) * 0.5)
				C.tube(cv, t0, t1, 0.45, coat)


# ------------------------------------------------------------------ vehicles (g7_cn_mesh, metres)
static func _wheel(S: Array, T: Dictionary, f: float, r: float, z: float, wr: float, wd: float) -> void:
	var pt := M.part(S, 0)
	var s := signf(r)
	M.cyl(pt, T, Vector3(f, r, z), Vector3(0, 1, 0), wr, wd, 10, C.ramp(TIRE), {"cap_t": 1, "edge": false})
	M.cyl(pt, T, Vector3(f, r + s * (wd + 0.01), z), Vector3(0, 1, 0), wr * 0.5, 0.012, 8, C.ramp(HUB), {"cap_t": 2})


static func _lamp(pt: Dictionary, T: Dictionary, at: Vector3, on: bool) -> void:
	M.cyl(pt, T, at, Vector3(0, 0, 1), 0.09, 0.07, 6, C.ramp(AMBER if on else AMBER_OFF), {"edge": false})
	if on:
		for nl in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, -1, 0)]:
			M.dpx(pt, T, at + Vector3(0, 0, 0.08), Color8(255, 236, 170), nl)


static func _vehicle(cv, k: int, fname: String, o: Vector2, kind: String) -> void:
	var S: Array = []
	var T := M.pose(o, k * PI / 4.0)
	var on := fname.ends_with("1")
	match kind:
		"forklift":
			_forklift(S, T, fname.begins_with("l"), on)
		"fuel":
			_fuel(S, T, on)
		"tug":
			_tug(S, T, on)
		"drone":
			T = M.pose(o, k * PI / 4.0, Vector3(0, 0, 0.0))
			_drone(S, T, fname == "r1")
	if kind != "drone":
		M.shadow(cv, S, o)
	M.render_z(cv, S, o, 71 + k)


static func _forklift(S: Array, T: Dictionary, loaded: bool, on: bool) -> void:
	var body: Array = C.ramp(OD)
	var dk: Array = C.ramp(OD_DK)
	var st: Array = C.ramp(STEEL)
	for f in [0.62, -0.62]:
		for r in [-0.5, 0.5]:
			_wheel(S, T, f, r, 0.28, 0.28 if f > 0 else 0.24, 0.11)
	var pt := M.part(S, 1)
	M.box(pt, T, Vector3(0.0, 0, 0.5), Vector3(0.95, 0.5, 0.26), body, Vector3(0.0, 0.0, 0.04))      # chassis
	M.box(pt, T, Vector3(-0.78, 0, 0.82), Vector3(0.28, 0.5, 0.3), dk, Vector3(0.0, 0.08, 0.06))     # counterweight
	M.box(pt, T, Vector3(-0.15, 0, 0.86), Vector3(0.22, 0.26, 0.12), C.ramp(DARK))                    # seat
	for i in 5:   # hazard stripes on the counterweight back
		M.dline(pt, T, Vector3(-1.06, -0.45 + i * 0.22, 0.6), Vector3(-1.06, -0.35 + i * 0.22, 0.95), HAZ, Vector3(-1, 0, 0))
	var cage := M.part(S, 2)
	for q in [Vector3(0.45, -0.46, 0), Vector3(0.45, 0.46, 0), Vector3(-0.55, -0.46, 0), Vector3(-0.55, 0.46, 0)]:
		_rod(cage, T, q + Vector3(0, 0, 0.75), q + Vector3(0, 0, 2.05), 0.035, st)
	M.box(cage, T, Vector3(-0.05, 0, 2.08), Vector3(0.56, 0.5, 0.03), C.ramp(DARK))                   # overhead guard
	_lamp(cage, T, Vector3(-0.4, 0.0, 2.2), on)
	var drv := M.part(S, 2)   # driver: hi-vis vest, helmet
	M.box(drv, T, Vector3(-0.12, 0, 1.22), Vector3(0.14, 0.2, 0.26), C.ramp(VEST), Vector3(0.0, 0.0, 0.05))
	M.cyl(drv, T, Vector3(-0.08, 0, 1.6), Vector3(0, 0, 1), 0.12, 0.1, 8, C.ramp(Color8(66, 72, 58)), {"cap_t": 3})
	M.dpx(drv, T, Vector3(0.05, 0, 1.58), SKIN, Vector3(1, 0, 0))
	var mast := M.part(S, 2)
	for r in [-0.34, 0.34]:
		M.box(mast, T, Vector3(1.02, r, 1.25), Vector3(0.05, 0.05, 1.05), st)
	M.box(mast, T, Vector3(1.02, 0, 2.28), Vector3(0.05, 0.38, 0.04), st)
	var fz := 0.32 if loaded else 0.12
	M.box(mast, T, Vector3(1.1, 0, fz + 0.3), Vector3(0.04, 0.4, 0.3), C.ramp(DARK))                  # carriage
	for r in [-0.24, 0.24]:
		M.box(mast, T, Vector3(1.62, r, fz), Vector3(0.5, 0.05, 0.025), st)                               # forks
	if loaded:
		var ld := M.part(S, 3)
		M.box(ld, T, Vector3(1.62, 0, fz + 0.1), Vector3(0.52, 0.5, 0.07), C.ramp(PALLET))
		var cr: Array = C.ramp(CRATE)
		for i in 4:
			var f := 1.36 + float(i % 2) * 0.52
			var r := -0.25 + float(i / 2) * 0.5
			M.box(ld, T, Vector3(f, r, fz + 0.36), Vector3(0.24, 0.23, 0.18), cr)
			M.dline(ld, T, Vector3(f - 0.15, r - 0.24, fz + 0.4), Vector3(f + 0.15, r - 0.24, fz + 0.4), STENCIL, Vector3(0, -1, 0))
			M.dline(ld, T, Vector3(f - 0.15, r + 0.24, fz + 0.4), Vector3(f + 0.15, r + 0.24, fz + 0.4), STENCIL, Vector3(0, 1, 0))
		M.box(ld, T, Vector3(1.62, 0, fz + 0.74), Vector3(0.36, 0.34, 0.16), cr)
		M.dpx(ld, T, Vector3(1.62, 0, fz + 0.91), Color8(210, 60, 40), Vector3(0, 0, 1))                  # red hazard tag


static func _fuel(S: Array, T: Dictionary, on: bool) -> void:
	var body: Array = C.ramp(OD)
	var dk: Array = C.ramp(OD_DK)
	for f in [2.55, -0.9, -2.3]:
		for r in [-1.02, 1.02]:
			_wheel(S, T, f, r, 0.5, 0.5, 0.16)
	var ch := M.part(S, 1)
	M.box(ch, T, Vector3(-0.2, 0, 0.78), Vector3(3.9, 1.0, 0.16), C.ramp(DARK))                       # frame rails
	var cab := M.part(S, 2)
	M.box(cab, T, Vector3(2.85, 0, 1.6), Vector3(0.95, 1.18, 0.78), body, Vector3(0.38, 0.0, 0.1))     # cab (sloped front)
	M.box(cab, T, Vector3(3.62, 0, 0.98), Vector3(0.24, 1.15, 0.22), dk)                               # bumper
	M.dpoly(cab, T, [Vector3(3.44, -0.95, 1.55), Vector3(3.44, 0.95, 1.55), Vector3(3.22, 0.9, 2.15), Vector3(3.22, -0.9, 2.15)], C.ramp(GLASS)[2], Vector3(1, 0, 0.4))
	for s in [-1.0, 1.0]:
		M.dpoly(cab, T, [Vector3(2.4, s * 1.19, 1.62), Vector3(3.1, s * 1.19, 1.62), Vector3(3.1, s * 1.19, 2.1), Vector3(2.4, s * 1.19, 2.1)], C.ramp(GLASS)[1], Vector3(0, s, 0))
		M.dpx(cab, T, Vector3(3.87, s * 0.85, 1.12), Color8(255, 240, 200), Vector3(1, 0, 0))            # headlights
	_lamp(cab, T, Vector3(2.7, -0.6, 2.42), on)
	_lamp(cab, T, Vector3(2.7, 0.6, 2.42), not on)
	var tk := M.part(S, 2)
	var tr: Array = C.ramp(Color8(108, 112, 84))
	M.cyl(tk, T, Vector3(-0.75, 0, 1.75), Vector3(1, 0, 0), 0.98, 2.15, 12, tr, {"cap_t": 2}, 0.26)   # tank
	M.box(tk, T, Vector3(-0.75, 0, 2.78), Vector3(1.8, 0.22, 0.06), C.ramp(DARK))                      # catwalk
	for i in 3:
		M.cyl(tk, T, Vector3(-1.9 + i * 1.15, 0, 2.8), Vector3(0, 0, 1), 0.2, 0.06, 8, C.ramp(STEEL), {"cap_t": 3})   # hatches
	for s in [-1.0, 1.0]:   # hazard placard + reflective stripe
		M.dpoly(tk, T, [Vector3(-0.2, s * 0.99, 1.75), Vector3(0.08, s * 0.99, 2.03), Vector3(0.36, s * 0.99, 1.75), Vector3(0.08, s * 0.99, 1.47)], Color8(206, 50, 40), Vector3(0, s, 0))
		M.dline(tk, T, Vector3(-2.8, s * 0.97, 1.32), Vector3(1.3, s * 0.97, 1.32), HAZ, Vector3(0, s, 0))
	var rr := M.part(S, 2)   # rear cabinet + hose reel
	M.box(rr, T, Vector3(-3.25, 0, 1.25), Vector3(0.32, 1.0, 0.45), dk)
	M.cyl(rr, T, Vector3(-3.3, 0, 1.25), Vector3(0, 1, 0), 0.3, 0.6, 10, C.ramp(Color8(40, 40, 40)), {"cap_t": 1})


static func _tug(S: Array, T: Dictionary, on: bool) -> void:
	var body: Array = C.ramp(Color8(196, 170, 60))   # flight-line yellow tug (OD drab would vanish on the apron)
	var dk: Array = C.ramp(Color8(58, 60, 56))
	for f in [1.0, -1.0]:
		for r in [-0.82, 0.82]:
			_wheel(S, T, f, r, 0.38, 0.38, 0.17)
	var pt := M.part(S, 1)
	M.box(pt, T, Vector3(0.1, 0, 0.62), Vector3(1.6, 0.92, 0.3), body, Vector3(0.5, 0.15, 0.06))      # low ballasted body
	M.box(pt, T, Vector3(1.78, 0, 0.5), Vector3(0.12, 0.7, 0.16), dk)                                  # tow hitch
	for i in 6:
		M.dline(pt, T, Vector3(1.66, -0.8 + i * 0.3, 0.4), Vector3(1.66, -0.68 + i * 0.3, 0.8), Color8(30, 30, 30), Vector3(1, 0, 0))
	var cb := M.part(S, 2)
	M.box(cb, T, Vector3(-0.95, 0, 1.15), Vector3(0.42, 0.55, 0.24), dk)                               # driver tub
	for q in [Vector3(-0.6, -0.5, 0), Vector3(-0.6, 0.5, 0), Vector3(-1.3, -0.5, 0), Vector3(-1.3, 0.5, 0)]:
		_rod(cb, T, q + Vector3(0, 0, 1.3), q + Vector3(0, 0, 2.15), 0.03, C.ramp(STEEL))
	M.box(cb, T, Vector3(-0.95, 0, 2.17), Vector3(0.42, 0.56, 0.03), dk)
	M.box(cb, T, Vector3(-0.95, 0, 1.55), Vector3(0.14, 0.2, 0.22), C.ramp(VEST))                     # driver
	M.cyl(cb, T, Vector3(-0.9, 0, 1.9), Vector3(0, 0, 1), 0.11, 0.09, 8, C.ramp(Color8(66, 72, 58)), {"cap_t": 3})
	_lamp(cb, T, Vector3(-0.95, 0, 2.27), on)


static func _drone(S: Array, T: Dictionary, alt: bool) -> void:
	var pt := M.part(S, 1)
	var bd: Array = C.ramp(Color8(78, 84, 80))
	M.box(pt, T, Vector3(0, 0, 0.0), Vector3(0.2, 0.13, 0.07), bd, Vector3(0.05, 0.05, 0.03))
	M.cyl(pt, T, Vector3(0.18, 0, -0.08), Vector3(0, 0, 1), 0.06, 0.04, 6, C.ramp(DARK), {"edge": false})   # camera ball
	for i in 4:
		var a := PI / 4.0 + i * PI / 2.0
		var tip := Vector3(cos(a) * 0.42, sin(a) * 0.42, 0.04)
		_rod(pt, T, Vector3(0, 0, 0.02), tip, 0.02, bd)
		var rp := M.part(S, 2)
		var disc: Array = []
		for j in 10:
			var t := TAU * j / 10.0
			disc.append(tip + Vector3(cos(t) * 0.2, sin(t) * 0.2, 0.06))
		M.dpoly(rp, T, disc, Color(0.72, 0.74, 0.72, 0.42 if (i % 2 == 0) == alt else 0.26), Vector3(0, 0, 1))
		M.dpx(rp, T, tip + Vector3(0, 0, 0.07), Color8(214, 52, 44) if i < 2 else Color8(80, 220, 110), Vector3(0, 0, 1))   # nav lights


static func _rod(pt: Dictionary, T: Dictionary, a: Vector3, b: Vector3, r: float, rp: Array) -> void:
	if a.distance_to(b) < 0.01:
		return
	M.cyl(pt, T, (a + b) * 0.5, b - a, r, a.distance_to(b) * 0.5, 4, rp, {"edge": false})


# ------------------------------------------------------------------ moving parts
## Air-surveillance radar: a slatted reflector on a turning yoke (step 0..15 = 0..337.5 deg), on a short plinth.
static func _radar(cv, step: int, o: Vector2) -> void:
	var S: Array = []
	var T0 := M.pose(o, 0.0)
	var base := M.part(S, 0)
	M.cyl(base, T0, Vector3(0, 0, 0.35), Vector3(0, 0, 1), 0.42, 0.35, 8, C.ramp(CONC), {"cap_t": 3})
	M.cyl(base, T0, Vector3(0, 0, 0.82), Vector3(0, 0, 1), 0.16, 0.14, 8, C.ramp(GUNM), {"cap_t": 3})
	var T := M.sub(T0, Vector3(0, 0, 0.95), step * TAU / 16.0)
	var ant := M.part(S, 1)
	_rod(ant, T, Vector3(0, 0, 0.0), Vector3(0.25, 0, 0.45), 0.05, C.ramp(GUNM))
	var rp: Array = C.ramp(RADAR)
	var secs: Array = []   # curved reflector: 5 vertical slats on an arc, tilted back
	for i in 5:
		var r := -1.3 + i * 0.65
		var f := 0.32 - absf(r) * 0.14
		secs.append(Vector3(f, r, 0.25))
	for i in 4:
		var a: Vector3 = secs[i]
		var b: Vector3 = secs[i + 1]
		M.face(ant, T, [a, b, b + Vector3(0.12, 0, 0.62), a + Vector3(0.12, 0, 0.62)], Vector3(-0.4, 0, 0.5), rp)
		M.face(ant, T, [a, b, b + Vector3(0.12, 0, 0.62), a + Vector3(0.12, 0, 0.62)], Vector3(0.8, 0, 0.5), rp)
		M.dline(ant, T, a + Vector3(0.06, 0, 0.3), b + Vector3(0.06, 0, 0.3), C.ramp(RADAR)[1], Vector3.ZERO)
	M.box(ant, T, Vector3(0.18, 0, 0.18), Vector3(0.1, 1.3, 0.05), C.ramp(GUNM))                       # feed bar
	M.render_z(cv, S, o, 7)


## Tower remote-weapon cupola: armoured ring, angled turret with a 12.7 mm gun and sight box (16 aim steps).
static func _cupola(cv, step: int, o: Vector2) -> void:
	var S: Array = []
	var T0 := M.pose(o, 0.0)
	var ring := M.part(S, 0)
	var arm: Array = C.ramp(Color8(116, 122, 112))
	M.cyl(ring, T0, Vector3(0, 0, 0.16), Vector3(0, 0, 1), 0.92, 0.16, 12, arm, {"cap_t": 3})
	var T := M.sub(T0, Vector3(0, 0, 0.32), step * TAU / 16.0)
	var tu := M.part(S, 1)
	M.box(tu, T, Vector3(-0.05, 0, 0.32), Vector3(0.62, 0.55, 0.32), arm, Vector3(0.28, 0.1, 0.12))
	M.box(tu, T, Vector3(0.1, 0.62, 0.42), Vector3(0.22, 0.12, 0.16), C.ramp(GUNM))                    # sight box
	M.dpx(tu, T, Vector3(0.33, 0.62, 0.45), Color8(120, 220, 255), Vector3(1, 0, 0))                    # lens
	var gp := M.part(S, 2)
	M.cyl(gp, T, Vector3(0.95, -0.12, 0.42), Vector3(1, 0, 0), 0.07, 0.55, 6, C.ramp(DARK), {"edge": false})
	M.cyl(gp, T, Vector3(0.5, -0.12, 0.42), Vector3(1, 0, 0), 0.13, 0.18, 6, C.ramp(GUNM), {"edge": false})
	M.box(gp, T, Vector3(-0.1, -0.45, 0.5), Vector3(0.18, 0.12, 0.1), C.ramp(Color8(86, 92, 62)))       # ammo can
	M.render_z(cv, S, o, 9)


## Machine-replica pop-up target on a hinged frame: up (vertical), half (45 deg) or down (flat). k 0 faces +x, 1 +y.
static func _target(cv, k: int, fname: String, o: Vector2) -> void:
	var S: Array = []
	var T0 := M.pose(o, 0.0 if k == 0 else PI / 2.0)
	var base := M.part(S, 0)
	M.box(base, T0, Vector3(0, 0, 0.09), Vector3(0.2, 0.55, 0.09), C.ramp(Color8(84, 86, 80)))
	var tilt := 0.0 if fname == "up" else (0.8 if fname == "half" else 1.45)
	var T := M.sub(T0, Vector3(0, 0, 0.18), 0.0, -tilt)
	var pl := M.part(S, 1)
	var rp: Array = C.ramp(REPLICA)
	# replica silhouette: wide shoulders, narrow waist, angular head (the Machine walker frame), on a plate
	M.box(pl, T, Vector3(0, 0, 0.45), Vector3(0.03, 0.22, 0.45), rp)
	M.box(pl, T, Vector3(0, 0, 1.0), Vector3(0.03, 0.42, 0.18), rp)
	M.box(pl, T, Vector3(0, 0, 1.32), Vector3(0.03, 0.16, 0.14), rp)
	M.dpx(pl, T, Vector3(0.04, 0.05, 1.33), EYE, Vector3(1, 0, 0))
	M.dpx(pl, T, Vector3(0.04, -0.05, 1.33), EYE, Vector3(1, 0, 0))
	M.dline(pl, T, Vector3(0.04, -0.1, 0.95), Vector3(0.04, 0.1, 0.95), Color8(232, 232, 220), Vector3(1, 0, 0))   # scoring ring
	M.render_z(cv, S, o, 11 + k)


# ------------------------------------------------------------------ preview (agent review only, not shipped)
func _write_preview(out: Dictionary) -> void:
	var ids: Array = (out.manifest.life7 as Dictionary).keys()
	ids.sort()
	var wmax := 0
	var htot := 0
	for id in ids:
		var im: Image = out.images[out.manifest.life7[id].file]
		wmax = maxi(wmax, im.get_width())
		htot += im.get_height() + 4
	var pv := Image.create(wmax, htot, false, Image.FORMAT_RGBA8)
	pv.fill(Color(0.40, 0.385, 0.35))
	var y := 0
	for id in ids:
		var im: Image = out.images[out.manifest.life7[id].file]
		pv.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(0, y))
		y += im.get_height() + 4
	pv.resize(pv.get_width() * 2, pv.get_height() * 2, Image.INTERPOLATE_NEAREST)
	pv.save_png(_preview)
	print("G7_LIFE7 preview %s" % _preview)
