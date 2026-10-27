extends SceneTree
## G7 drones (defs: DRONE7 defs_g7_drones.json + CN kit / facility drones; art: ART7B roll-out of the owner-approved
## rev3 look, DL7-3). Every airframe is modelled in real metres and rasterised by ARTCN7's faceted renderer
## (tools/art/g7_cn_mesh.gd) at the ONE real-world scale (fact art.scale: 4 m per tile, 9.8 px per metre of height):
## a 1.5 m heavy hexacopter is ~16 px across, a 10-inch FPV with its warhead ~7 px, next to an 18 px soldier.
## Sheet layout unchanged from DRONE7 (38x34 cells, pivot (19, 21), frames FRAMES, air: true + altitude + a
## separate soft ground shadow drawn by the renderer), plus 32x32 menu icons for every id.
##   godot --headless --path . -s tools/art/g7_drones.gd   (writes assets/art/drone7/)
## Prints "G7_ART <id> bytes=<n> budget=<n> ok|OVER" and "DRONE7_ART wrote <n> files".

const GEN = preload("res://tools/gen_art.gd")
const P = preload("res://tools/art/pix.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const G7Anim = preload("res://tools/art/g7_anim.gd")
const M = preload("res://tools/art/g7_cn_mesh.gd")
const GR = preload("res://tools/art/g7_cn_gear.gd")

const OUT_DIR := "res://assets/art/drone7/"
const SPEC := {"fw": 38, "fh": 34, "pivot": [19, 21]}
## ART7D: catalog frames idle / move / fire first (G3/G4 art checks); the drawer still gets its original frame index.
const FRAMES := ["idle", "move", "fire", "bank_l", "bank_r", "release", "dive", "trail"]
const FRAMES_DRAW := ["idle", "move", "bank_l", "bank_r", "release", "dive", "fire", "trail"]
## id -> [faction look, kind]. kinds: strike (heavy hex, bomb rack), fpv (racing quad + warhead), gun (CN defence
## quad, MG under the nose), interceptor (CN dart with pusher prop and seeker).
const DEFS := {"g7_a_strike_drone": ["a", "strike"], "g7_b_strike_drone": ["b", "strike"],
	"g7_a_fpv": ["a", "fpv"], "g7_b_fpv": ["b", "fpv"], "cn_gun_drone": ["cn", "gun"],
	"g7_cn_interceptor_drone": ["cn", "interceptor"]}
const BODY := {"a": Color8(92, 98, 82), "b": Color8(118, 104, 74), "cn": Color8(104, 112, 108)}
const ARM := {"a": Color8(52, 56, 54), "b": Color8(60, 54, 44), "cn": Color8(70, 76, 80)}
const BOMB := Color8(70, 76, 58)
const BOMB_B := Color8(96, 104, 64)
const TAPE := Color8(150, 146, 120)
const FLASH := Color8(255, 236, 170)
const FIRE := Color8(255, 150, 60)
const SMOKE := Color8(150, 146, 136)
const PROP := Color(0.85, 0.88, 0.86, 0.38)
const LENS := Color8(255, 70, 50)


func _init() -> void:
	var out := generate()
	var dir := ProjectSettings.globalize_path(OUT_DIR)
	for sub in ["units", "wrecks", "icons"]:
		var d := DirAccess.open(dir.path_join(sub))
		if d != null:
			for fn in d.get_files():
				if fn.ends_with(".png"):
					d.remove(fn)
	var n := GEN.save(out, OUT_DIR)
	var man: Dictionary = out.manifest.vehicles
	var ids: Array = man.keys()
	ids.sort()
	for id in ids:
		var g7: Dictionary = man[id].g7
		print("G7_ART %s bytes=%d budget=%d %s" % [id, int(g7.bytes), int(g7.budget), "ok" if int(g7.bytes) <= int(g7.budget) else "OVER"])
	print("DRONE7_ART wrote %d files" % n)
	quit(0)


static func generate() -> Dictionary:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": "drone7",
		"g7_detail_level": C.DL.duplicate(true)}}
	var sh := SL.drone_shadow(out, "g7_drone_shadow", 5.5, 2.4)
	var shs := SL.drone_shadow(out, "g7_drone_shadow_s", 3.0, 1.4)
	var ids: Array = DEFS.keys()
	ids.sort()
	for def: String in ids:
		var fac: String = DEFS[def][0]
		var kind: String = DEFS[def][1]
		var small := kind == "fpv" or kind == "interceptor"
		SL.veh_sheet(out, def, SPEC, func(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
			draw(cv, rot, FRAMES_DRAW.find(FRAMES[f]) if f >= 0 and f < FRAMES.size() else f, wreck, o, fac, kind), FRAMES,
			{"air": true, "altitude": 16 if not small else 12, "bob": 1, "shadow": (shs if small else sh).duplicate()})
		var e: Dictionary = out.manifest.vehicles[def]
		var img: Image = out.images[String(e.file)]
		e["g7"] = {"detail_level": C.VERSION, "class": "air", "bytes": C.packed_bytes(img, 38, 34, -1),
			"raw_bytes": img.get_width() * img.get_height() * 4, "budget": int(C.BUDGET.air), "art": "ART7B",
			"scale": "4 m/tile, 9.8 px/m (fact art.scale)", "kind": kind}
		C.icon(out, def, img, 38, 34, 1)
	G7Anim.apply(out)   # ART7D: G6.1 air frames (damaged) + anim61 muzzle / smoke, re-measured bytes
	return out


## Rotor disc (translucent blur) + motor bell at local point p (metres) of pose T.
static func _rotor(pt: Dictionary, T: Dictionary, p: Vector3, r: float, motor: Array, spin: int) -> void:
	M.cyl(pt, T, p, Vector3(0, 0, 1), 0.05, 0.04, 6, motor, {"edge": false})
	var pts: Array = []
	for i in 10:
		var a := TAU * i / 10.0
		pts.append(p + Vector3(cos(a) * r, sin(a) * r, 0.05))
	M.dpoly(pt, T, pts, PROP)
	var a0 := float(spin) * 1.1
	M.dline(pt, T, p + Vector3(cos(a0) * r, sin(a0) * r, 0.06), p - Vector3(cos(a0) * r, sin(a0) * r, -0.06), Color(0.95, 0.95, 0.92, 0.6))


static func draw(cv, rot: float, f: int, wreck: bool, o: Vector2, fac: String, kind: String) -> void:
	var name: String = FRAMES[f]
	var body: Array = C.ramp(BODY[fac])
	var arm: Array = C.ramp(ARM[fac])
	var S: Array = []
	if wreck:   # crashed airframe: broken body + bent arms on the ground, smouldering
		var Tw := M.pose(o + Vector2(0, 3), rot + 0.4, Vector3.ZERO, 0.0, 0.5)
		var pw := M.part(S, 0)
		M.box(pw, Tw, Vector3(0, 0, 0.08), Vector3(0.2, 0.13, 0.07), C.ramp(Color8(50, 46, 42)))
		M.box(pw, Tw, Vector3(0.3, 0.2, 0.03), Vector3(0.25, 0.03, 0.02), arm)
		M.box(pw, Tw, Vector3(-0.25, -0.25, 0.03), Vector3(0.03, 0.22, 0.02), arm)
		M.render(cv, S, o + Vector2(0, 3), 5)
		cv.px(int(o.x), int(o.y) + 2, FIRE)
		cv.px(int(o.x) + 1, int(o.y) + 1, Color(0.5, 0.48, 0.44, 0.7))
		C.selout(cv)
		return
	var pitch := 0.0
	var roll := 0.0
	match name:
		"move", "trail", "release":
			pitch = -0.25
		"dive", "fire":
			pitch = -0.9 if kind == "fpv" or kind == "interceptor" else -0.4
		"bank_l":
			roll = -0.45
			pitch = -0.15
		"bank_r":
			roll = 0.45
			pitch = -0.15
	var T := M.pose(o, rot, Vector3(0, 0, 0.35), pitch, roll)
	var pt := M.part(S, 0)
	match kind:
		"strike":
			M.box(pt, T, Vector3(0, 0, 0), Vector3(0.24, 0.16, 0.08), body, Vector3(0.06, 0.04, 0.03))
			M.box(pt, T, Vector3(0, 0, 0.085), Vector3(0.1, 0.08, 0.008), body, Vector3.ZERO, {"team": true})
			for i in 6:
				var a := TAU * (i + 0.5) / 6.0
				var tip := Vector3(cos(a) * 0.68, sin(a) * 0.68, 0.03)
				M.box(pt, M.sub(T, tip * 0.5, a), Vector3.ZERO, Vector3(0.34, 0.025, 0.02), arm)
				_rotor(pt, T, tip + Vector3(0, 0, 0.04), 0.3, arm, f + i)
			M.dpx(pt, T, Vector3(0.25, 0, 0.0), LENS if fac == "b" else Color8(120, 255, 150), Vector3(1, 0, 0))
			var n := 2 if fac == "a" else 3
			for i in n:   # bomb rack: A grenades in a cradle, B taped mortar bombs
				if name == "release" and i == 0:
					continue
				var c := Vector3(0.0, (float(i) - (n - 1) * 0.5) * 0.14, -0.14)
				M.cyl(pt, T, c, Vector3(1, 0, 0), 0.045, 0.1, 6, C.ramp(BOMB if fac == "a" else BOMB_B), {"edge": false})
				if fac == "b":
					M.dpx(pt, T, c + Vector3(0, 0, 0.05), TAPE)
			M.box(pt, T, Vector3(0, 0, -0.08), Vector3(0.14, 0.2, 0.012), C.ramp(Color8(60, 60, 58)))
		"fpv":
			M.box(pt, T, Vector3(0, 0, 0), Vector3(0.09, 0.05, 0.035), body)
			M.box(pt, T, Vector3(-0.02, 0, 0.04), Vector3(0.05, 0.035, 0.005), body, Vector3.ZERO, {"team": true})
			for i in 4:
				var a := TAU * (i + 0.5) / 4.0
				var tip := Vector3(cos(a) * 0.16, sin(a) * 0.16, 0.0)
				M.box(pt, M.sub(T, tip * 0.5, a), Vector3.ZERO, Vector3(0.09, 0.015, 0.01), arm)
				_rotor(pt, T, tip + Vector3(0, 0, 0.02), 0.11, arm, f + i)
			var wh: Array = C.ramp(Color8(88, 92, 80) if fac == "a" else Color8(70, 80, 50))
			M.cyl(pt, T, Vector3(0.2, 0, -0.03), Vector3(1, 0, 0), 0.035, 0.12, 6, wh, {"edge": false})
			M.cyl(pt, T, Vector3(0.36, 0, -0.03), Vector3(1, 0, 0), 0.06, 0.05, 6, wh, {"edge": false}, 0.0, 0.02)
			if fac == "b":
				M.dpx(pt, T, Vector3(0.18, 0, 0.01), TAPE)
			M.dpx(pt, T, Vector3(0.1, 0, 0.03), LENS)
		"gun":
			M.box(pt, T, Vector3(0, 0, 0), Vector3(0.3, 0.2, 0.1), body, Vector3(0.1, 0.05, 0.04))
			M.box(pt, T, Vector3(-0.05, 0, 0.105), Vector3(0.12, 0.1, 0.008), body, Vector3.ZERO, {"team": true})
			for i in 4:
				var a := TAU * (i + 0.5) / 4.0
				var tip := Vector3(cos(a) * 0.62, sin(a) * 0.62, 0.04)
				M.box(pt, M.sub(T, tip * 0.5, a), Vector3.ZERO, Vector3(0.31, 0.035, 0.025), arm)
				_rotor(pt, T, tip + Vector3(0, 0, 0.05), 0.32, arm, f + i)
			var dk: Array = C.ramp(Color8(42, 45, 50))
			M.box(pt, T, Vector3(0.12, 0, -0.14), Vector3(0.16, 0.05, 0.05), dk)
			M.cyl(pt, T, Vector3(0.45, 0, -0.14), Vector3(1, 0, 0), 0.02, 0.18, 4, dk, {"edge": false})
			M.dpx(pt, T, Vector3(0.31, 0.0, 0.0), Color8(140, 200, 255), Vector3(1, 0, 0))
			if name == "fire":
				var m := M.wm(T, Vector3(0.66, 0, -0.14))
				pt.dec.append({"k": "px", "a": m, "col": FLASH, "n": Vector3.ZERO})
				pt.dec.append({"k": "line", "a": m, "b": M.wm(T, Vector3(1.6, 0, -0.2)), "col": Color(1.0, 0.86, 0.5, 0.8), "n": Vector3.ZERO})
		"interceptor":
			var hull := [[-0.45, V2([Vector2(0.03, -0.03), Vector2(0.06, 0.0), Vector2(0.03, 0.04)])],
				[-0.1, V2([Vector2(0.06, -0.06), Vector2(0.09, 0.0), Vector2(0.05, 0.07)])],
				[0.3, V2([Vector2(0.05, -0.05), Vector2(0.07, 0.0), Vector2(0.04, 0.05)])],
				[0.5, V2([Vector2(0.01, -0.01), Vector2(0.015, 0.0), Vector2(0.01, 0.01)])]]
			M.loft(pt, T, _mir(hull), body)
			M.prism(pt, T, [Vector3(0.05, 0, 0.0), Vector3(-0.3, 0.42, 0.0), Vector3(-0.38, 0.42, 0.0), Vector3(-0.3, 0, 0.0),
				Vector3(-0.38, -0.42, 0.0), Vector3(-0.3, -0.42, 0.0)], Vector3(0, 0, -0.015), body)
			M.box(pt, T, Vector3(-0.15, 0, 0.07), Vector3(0.1, 0.03, 0.005), body, Vector3.ZERO, {"team": true})
			_rotor(pt, M.sub(T, Vector3(-0.5, 0, 0), 0.0, PI / 2.0), Vector3.ZERO, 0.16, arm, f)
			M.dpx(pt, T, Vector3(0.48, 0, 0.0), LENS)
	# team ID patch on top, painted after the airframe (layer 2) so rotors / arms never cover the mask pixels
	var pteam := M.part(S, 2)
	var tp: Array = {"strike": [0.12, 0.1, 0.09], "fpv": [0.1, 0.06, 0.045], "gun": [0.16, 0.13, 0.115],
		"interceptor": [0.2, 0.06, 0.07]}[kind]
	var tz: float = tp[2]
	M.dpoly(pteam, T, [Vector3(-tp[0], -tp[1], tz), Vector3(tp[0], -tp[1], tz), Vector3(tp[0], tp[1], tz), Vector3(-tp[0], tp[1], tz)],
		Color8(152, 152, 152), Vector3.ZERO, true)
	match name:
		"dive", "trail":
			var b := M.wm(T, Vector3(-0.5, 0, 0.0))
			var d := M.wdir(T, Vector3(1, 0, 0))
			for i in (4 if name == "dive" else 2):
				var q := b - d * (0.4 + 0.35 * i) + Vector3(0, 0, 0.1 * (i % 2))
				pt.dec.append({"k": "line", "a": q, "b": q - d * 0.4, "col": Color(0.9, 0.9, 0.9, 0.35), "n": Vector3.ZERO})
		"release":
			if kind == "strike":   # the bomb falling clear + release puff
				var bw := M.wm(T, Vector3(0, -0.07, -0.5))
				M.sprite(S, bw, func(cv2):
					var c := M.scr_w(o, bw)
					cv2.ellipse(c.x, c.y, 0.9, 1.5, BOMB if fac == "a" else BOMB_B)
					cv2.px(int(c.x), int(c.y) - 2, Color8(200, 200, 190)), 2.0)
			else:
				pt.dec.append({"k": "px", "a": M.wm(T, Vector3(0.0, 0, 0.12)), "col": LENS, "n": Vector3.ZERO})
	M.render(cv, S, o, 9 + f)
	if name == "fire" and (kind == "fpv" or kind == "interceptor"):   # detonation / intercept burst
		var c := M.scr_w(o, M.wm(T, Vector3(0.4, 0, 0)))
		cv.ellipse(c.x, c.y, 4.5, 3.0, FIRE)
		cv.ellipse(c.x, c.y, 2.5, 1.6, FLASH)
		for i in 6:
			var a := TAU * i / 6.0
			cv.px(int(c.x + cos(a) * 6.0), int(c.y + sin(a) * 3.5), SMOKE)
	elif name == "fire" and kind == "strike":   # strike drone "fire" = the release puff cloud
		var c := M.scr_w(o, M.wm(T, Vector3(0, 0, -0.3)))
		for i in 5:
			cv.ellipse(c.x - 3.0 + i * 1.5, c.y + 1.0 + (i % 2), 1.4, 0.9, Color(0.86, 0.86, 0.82, 0.55))
	C.selout(cv)


static func V2(a: Array) -> PackedVector2Array:
	return PackedVector2Array(a)


## Right half sections (r >= 0) -> full sections mirrored about r = 0 (same as g7_cn_vehicles.mir).
static func _mir(secs: Array) -> Array:
	var out: Array = []
	for s in secs:
		var h: PackedVector2Array = s[1]
		var full := PackedVector2Array()
		for i in range(h.size() - 1, -1, -1):
			full.append(Vector2(-h[i].x, h[i].y))
		for q in h:
			full.append(q)
		out.append([s[0], full])
	return out
