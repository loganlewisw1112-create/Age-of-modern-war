extends RefCounted
## DL7 soldier rig (owner: ARTCN7): one soldier per 32x32 cell, 8 facings, the 24 FRAMES_INF poses. Parts
## (legs, torso, plates, pack, arms, head, weapon) are posed in a local frame, projected through
## g7_cn_lib.fpt and drawn back to front by depth, so every facing gets the right overlap for free.
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const GR = preload("res://tools/art/g7_cn_gear.gd")


static func pose(fname: String) -> Dictionary:
	var p := {"ph": 0.0, "sw": 0.0, "bob": 0.0, "crouch": 0.0, "lean": 0.0, "tilt": 0.0, "arms": "carry",
		"flash": false, "dark": 1.0, "act": -1, "breath": 0.0}
	if fname.begins_with("walk_"):
		p.ph = TAU * float(int(fname.substr(5))) / 6.0
		p.sw = 2.3
		p.bob = absf(sin(p.ph)) * 0.6
	elif fname.begins_with("run_"):
		p.ph = TAU * float(int(fname.substr(4))) / 3.0
		p.sw = 3.4
		p.lean = 1.4
		p.bob = absf(sin(p.ph)) * 0.9
	else:
		match fname:
			"idle_1":
				p.breath = 0.5
			"fire_s":
				p.arms = "aim"
				p.flash = true
			"fire_c":
				p.arms = "aim"
				p.flash = true
				p.crouch = 0.45
			"reload_0":
				p.arms = "reload"
			"crouch":
				p.crouch = 0.45
			"prone":
				p.tilt = 1.5
				p.arms = "paim"
			"crawl_0", "crawl_1":
				p.tilt = 1.5
				p.sw = 1.6
				p.ph = 0.0 if fname == "crawl_0" else PI
				p.arms = "crawl"
			"wounded":
				p.crouch = 0.35
				p.lean = -0.8
				p.arms = "clutch"
				p.dark = 0.88
			"die_0":
				p.tilt = -0.5
				p.arms = "limp"
				p.dark = 0.95
			"die_1":
				p.tilt = -1.05
				p.arms = "limp"
				p.dark = 0.88
			"die_2":
				p.tilt = -1.52
				p.arms = "limp"
				p.dark = 0.78
			"act_0", "act_1":
				p.arms = "act"
				p.act = 0 if fname == "act_0" else 1
	return p


static func _dk(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


## Draw one soldier of `kit` in facing k (0..7), frame fname, foot at o.
static func draw(cv, kit: Dictionary, k: int, fname: String, o: Vector2) -> void:
	var p := pose(fname)
	if p.act >= 0:
		p.merge(kit.get("act_pose", {}), true)
	var dk: float = p.dark
	var suit: Array = C.ramp(_dk(kit.suit, dk))
	var plate: Array = C.ramp(_dk(kit.plate, dk))
	var boot: Array = C.ramp(_dk(kit.boot, dk))
	var crouch: float = p.crouch
	var hz: float = 7.4 - crouch * 3.4
	var lean: float = p.lean
	var bulk: float = kit.get("bulk", 2.5)
	var R := {"a": k * PI / 4.0, "o": o, "tilt": p.tilt, "bob": p.bob, "lean": lean, "hip": hz}
	var lying := absf(float(p.tilt)) > 1.2
	C.ground_shadow(cv, o + Vector2(0, 0.5), 7.5 if lying else 4.6, 2.6 if lying else 1.9)
	var parts: Array = []
	# legs
	for s in [-1.0, 1.0]:
		var off: float = p.sw * sin(p.ph + (0.0 if s > 0 else PI))
		var lift: float = maxf(0.0, cos(p.ph + (0.0 if s > 0 else PI))) * p.sw * 0.22
		var foot := Vector3(off, s * 1.5, 0.6 + lift)
		var knee := Vector3(off * 0.5 + crouch * 2.8 + 0.3, s * 1.55, hz * 0.5 + lift * 0.5)
		parts.append({"d": C.fdep(R, knee.x, s * 1.2), "k": "leg", "a": Vector3(0, s * 1.3, hz), "b": knee, "c": foot})
	parts.append({"d": C.fdep(R, 0, 0), "k": "torso"})
	parts.append({"d": C.fdep(R, lean * 0.7 + 1.2, 0), "k": "plate"})
	parts.append({"d": C.fdep(R, lean * 0.5 - 2.3, 0), "k": "pack"})
	parts.append({"d": C.fdep(R, lean + 0.3, 0) + 0.02, "k": "head"})
	# arms + weapon
	var wl: float = kit.get("wlen", 7.0)
	var h := _hands(String(p.arms), lean, hz, wl, s_phase(p))
	if p.act >= 0:
		h.merge(GR.act_hands(kit, lean, hz, int(p.act), wl), true)
	for s in [-1.0, 1.0]:
		var hand: Vector3 = h.rh if s > 0 else h.lh
		parts.append({"d": C.fdep(R, (lean + hand.x) * 0.5, s * 2.3) + 0.01, "k": "arm", "s": s, "hand": hand})
	var wb: Vector3 = h.wb
	var wt: Vector3 = h.wt
	parts.append({"d": C.fdep(R, (wb.x + wt.x) * 0.5, wb.y) + 0.03, "k": "weapon", "wb": wb, "wt": wt,
		"ground": String(p.arms) == "limp"})
	parts.sort_custom(func(x, y): return x.d < y.d)
	for q in parts:
		match String(q.k):
			"leg":
				var a := C.fpt(R, q.a.x, q.a.y, q.a.z)
				var b := C.fpt(R, q.b.x, q.b.y, q.b.z)
				var c := C.fpt(R, q.c.x, q.c.y, q.c.z)
				C.tube(cv, a, b, 1.1, suit)
				C.tube(cv, b, c, 0.95, suit)
				C.blob(cv, b, 0.85, plate)
				C.blob(cv, c, 1.15, boot)
			"torso":
				C.tube(cv, C.fpt(R, 0, 0, hz + 0.6), C.fpt(R, lean, 0, hz + 4.0), bulk, suit)
				C.tube(cv, C.fpt(R, lean, -2.2, hz + 4.6), C.fpt(R, lean, 2.2, hz + 4.6), 1.25, plate)
				C.tube(cv, C.fpt(R, lean * 0.1, -1.6, hz + 0.6), C.fpt(R, lean * 0.1, 1.6, hz + 0.6), 0.8, plate)
			"plate":
				C.blob(cv, C.fpt(R, lean * 0.7 + 1.2, 0, hz + 3.0), 1.9, plate)
				GR.chest(cv, R, kit)
			"pack":
				GR.pack(cv, R, kit)
			"head":
				var hc := C.fpt(R, lean + 0.3, 0, hz + 7.5 + float(p.breath))
				C.blob(cv, hc, 2.1, C.ramp(_dk(kit.get("helm", kit.plate), dk)))
				GR.head(cv, R, kit, hc)
			"arm":
				var s: float = q.s
				var sh := Vector3(lean, s * 2.8, hz + 4.5)
				var hd: Vector3 = q.hand
				var el := (sh + hd) * 0.5 + Vector3(-0.4, s * 0.7, -1.0)
				var a := C.fpt(R, sh.x, sh.y, sh.z)
				var e := C.fpt(R, el.x, el.y, el.z)
				C.tube(cv, a, e, 1.05, suit)
				C.tube(cv, e, C.fpt(R, hd.x, hd.y, hd.z), 0.95, suit)
				C.blob(cv, C.fpt(R, hd.x, hd.y, hd.z), 0.8, boot)
				if s < 0:   # armband: the team mask on the left upper arm
					C.blob(cv, a.lerp(e, 0.45), 0.95, C.ramp(Color8(150, 150, 150)), true)
			"weapon":
				var R2 := R
				if bool(q.ground):
					R2 = R.duplicate()
					R2.tilt = 0.0
				GR.weapon(cv, kit, C.fpt(R2, q.wb.x, q.wb.y, q.wb.z), C.fpt(R2, q.wt.x, q.wt.y, q.wt.z), bool(p.flash))
	if p.act >= 0:
		act_fx(cv, R, kit, int(p.act), h)


static func s_phase(p: Dictionary) -> float:
	return sin(float(p.ph)) * float(p.sw)


## Default hand and weapon placement per arm mode (local coordinates).
static func _hands(mode: String, L: float, hz: float, wl: float, sp: float) -> Dictionary:
	match mode:
		"aim":
			return {"rh": Vector3(L + 2.0, 0.9, hz + 4.0), "lh": Vector3(L + 4.4, 0.0, hz + 4.1),
				"wb": Vector3(L, 0.8, hz + 4.6), "wt": Vector3(L + wl, 0.6, hz + 4.4)}
		"reload":
			return {"rh": Vector3(L + 2.0, 0.9, hz + 3.4), "lh": Vector3(L + 1.6, -0.4, hz + 2.2),
				"wb": Vector3(L + 0.6, 0.8, hz + 3.0), "wt": Vector3(L + 0.6 + wl * 0.8, 0.6, hz + 5.6)}
		"paim":
			return {"rh": Vector3(0.6, 1.0, hz + 6.8), "lh": Vector3(0.6, -0.8, hz + 9.0),
				"wb": Vector3(0.9, 0.8, hz + 5.6), "wt": Vector3(0.9, 0.6, hz + 5.6 + wl)}
		"crawl":
			return {"rh": Vector3(0.4, 2.0, hz + 8.6 + sp * 0.5), "lh": Vector3(0.4, -2.0, hz + 8.6 - sp * 0.5),
				"wb": Vector3(0.8, 1.4, hz + 2.0), "wt": Vector3(0.8, 1.4, hz + 2.0 + wl)}
		"clutch":
			return {"rh": Vector3(L + 1.6, 0.6, hz + 1.8), "lh": Vector3(L + 1.7, -0.6, hz + 2.0),
				"wb": Vector3(L - 1.0, 1.8, hz + 4.8), "wt": Vector3(L + 0.8, 2.2, hz - 1.0)}
		"limp":
			return {"rh": Vector3(L + 0.5, 3.4, hz + 3.0), "lh": Vector3(L + 0.5, -3.4, hz + 3.2),
				"wb": Vector3(3.0, 3.0, 0.6), "wt": Vector3(3.0 + wl * 0.8, 4.2, 0.6)}
	return {"rh": Vector3(L + 1.8, 1.4, hz + 2.6), "lh": Vector3(L + 3.4, -0.6, hz + 2.4),
		"wb": Vector3(L + 0.8, 1.6, hz + 3.4), "wt": Vector3(L + 0.8 + wl * 0.85, -1.2, hz + 1.4)}


## Act-frame effects drawn over the figure (scan cone, jam rings, arming lights, thrown grenade, ...).
static func act_fx(cv, R: Dictionary, kit: Dictionary, ph: int, h: Dictionary) -> void:
	var hz: float = R.hip
	var lean: float = R.lean
	var mz := C.fpt(R, h.wt.x, h.wt.y, h.wt.z) if h.has("wt") else C.fpt(R, lean + 4.0, 0, hz + 4.0)
	var fwd := C.sdir(float(R.a))
	match String(kit.get("act", "signal")):
		"scan":
			for i in 3 + ph * 2:
				var t := 2.0 + i * 1.6
				var side := C.sdir(float(R.a) + PI / 2.0) * (t * 0.45)
				cv.px(int(mz.x + fwd.x * t + side.x), int(mz.y + fwd.y * t + side.y), GR.SCAN)
				cv.px(int(mz.x + fwd.x * t - side.x), int(mz.y + fwd.y * t - side.y), GR.SCAN)
		"jam":
			var c := mz + fwd * 2.0
			for r in [1.5 + ph, 3.0 + ph]:
				for i in 8:
					var ang := TAU * i / 8.0
					cv.px(int(c.x + cos(ang) * r), int(c.y + sin(ang) * r * 0.6), Color(GR.JAM, 0.85))
		"arm":
			var g := C.fpt(R, lean + 4.4, 0, 0.8)
			C.blob(cv, g, 1.6, C.ramp(Color8(150, 146, 120)))
			cv.px(int(g.x), int(g.y) - 1, GR.LED_G if ph == 1 else GR.LED_R)
			cv.px(int(g.x) + 1, int(g.y) - 1, GR.HAZ)
		"treat", "place":
			var g := C.fpt(R, lean + 4.6, 0, 0.6)
			if String(kit.act) == "place":
				C.blob(cv, g, 1.1, C.ramp(Color8(96, 84, 64)))
				cv.px(int(g.x), int(g.y), GR.THERM if ph == 1 else GR.LED_R)
			else:
				cv.px(int(g.x), int(g.y), GR.WHITE)
				cv.px(int(g.x) + 1, int(g.y) - ph, Color8(255, 240, 160))
		"throw":
			if ph == 1:
				var g := C.fpt(R, lean + 7.5, 0.4, hz + 8.0)
				C.blob(cv, g, 0.9, C.ramp(GR.EMP))
		"harpoon":
			if ph == 1:
				cv.line_v(mz, mz + fwd * 9.0, Color(GR.NET, 0.9))
				cv.px(int(mz.x + fwd.x * 9.0), int(mz.y + fwd.y * 9.0), GR.WHITE)
		"launch", "scope":
			if ph == 1:
				C.blob(cv, mz + fwd * 2.0, 1.1, [GR.FLASH_O, GR.FLASH_O, GR.FLASH, GR.FLASH, GR.FLASH])
