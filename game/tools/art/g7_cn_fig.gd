extends RefCounted
## DL7-2 soldier rig (owner: ARTCN7): one soldier per 48x48 cell at FIG_S (~30 px), 8 facings, the 24 FRAMES_INF
## poses. Parts
## (legs, torso, plates, pack, arms, head, weapon) are posed in a local frame, projected through
## g7_cn_lib.fpt and drawn back to front by depth, so every facing gets the right overlap for free.
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const GR = preload("res://tools/art/g7_cn_gear.gd")


static func pose(fname: String) -> Dictionary:
	fname = String(C.POSE_ALIAS.get(fname, fname))
	var p := {"ph": 0.0, "sw": 0.0, "bob": 0.0, "crouch": 0.0, "lean": 0.0, "tilt": 0.0, "arms": "carry",
		"flash": false, "dark": 1.0, "act": -1, "breath": 0.0, "nade": -1}
	if fname.begins_with("walk_"):
		p.ph = TAU * float(int(fname.substr(5))) / 6.0
		p.sw = 2.3
		p.bob = absf(sin(p.ph)) * 0.6
	elif fname.begins_with("run_"):
		p.ph = TAU * float(int(fname.substr(4))) / 6.0   # ART7D: 6-frame run cycle (G6.1 run_0..5)
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
			"reload_1":   # ART7D: fresh magazine seated, weapon coming back up
				p.arms = "reload2"
				p.lean = 0.2
			"fire_p":   # ART7D: prone, aimed shot
				p.tilt = 1.5
				p.arms = "paim"
				p.flash = true
			"throw_0":   # ART7D: wind-up, weight on the back foot, grenade behind the head
				p.arms = "throw0"
				p.lean = -0.6
				p.ph = PI
				p.sw = 1.4
				p.nade = 0
			"throw_1":   # ART7D: release, stepping through, grenade leaving the hand
				p.arms = "throw1"
				p.lean = 1.1
				p.ph = 0.0
				p.sw = 1.8
				p.nade = 1
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


const WEB := Color8(60, 62, 52)
const SKIN := Color8(170, 128, 100)


## Draw one soldier of `kit` in facing k (0..7), frame fname, foot at o. Local units are DL7-1 units; the rig
## scales them (and every radius) by C.FIG_S * sc_mul (default 1 → ~18–30 px tall). Sample gates may pass sc_mul > 1.
static func draw(cv, kit: Dictionary, k: int, fname: String, o: Vector2, sc_mul: float = 1.0, modern_rig: bool = false) -> void:
	var p := pose(fname)
	if p.act >= 0:
		p.merge(kit.get("act_pose", {}), true)
	var Z: float = C.FIG_S * maxf(sc_mul, 0.01)
	var dk: float = p.dark
	var suit: Array = C.ramp(_dk(kit.suit, dk))
	var suit_d: Array = C.ramp(_dk(P.mul(kit.suit, 0.9), dk))
	var plate: Array = C.ramp(_dk(kit.plate, dk))
	var boot: Array = C.ramp(_dk(kit.boot, dk))
	var web: Array = C.ramp(_dk(kit.get("web", WEB), dk))
	var glove: Array = C.ramp(_dk(kit.get("glove", kit.boot), dk))
	var helm: Array = C.ramp(_dk(kit.get("helm", kit.plate), dk))
	var team: Array = C.ramp(Color8(152, 152, 152))
	var crouch: float = p.crouch
	var hz: float = 7.4 - crouch * 3.4
	var lean: float = p.lean
	var bulk: float = kit.get("bulk", 2.5)
	var R := {"a": k * PI / 4.0, "o": o, "tilt": p.tilt, "bob": float(p.bob) * Z, "lean": lean, "hip": hz, "sc": Z}
	var lying := absf(float(p.tilt)) > 1.2
	C.ground_shadow(cv, o + Vector2(0, 0.5), (7.8 if lying else 5.0) * Z, (2.6 if lying else 2.0) * Z)
	var parts: Array = []
	for s in [-1.0, 1.0]:
		var off: float = p.sw * sin(p.ph + (0.0 if s > 0 else PI))
		var lift: float = maxf(0.0, cos(p.ph + (0.0 if s > 0 else PI))) * p.sw * 0.22
		var foot := Vector3(off, s * 1.65, 0.6 + lift)
		var knee := Vector3(off * 0.5 + crouch * 2.8 + 0.3, s * 1.6, hz * 0.5 + lift * 0.5)
		parts.append({"d": C.fdep(R, knee.x, s * 1.2), "k": "leg", "s": s, "a": Vector3(0, s * 1.15, hz), "b": knee, "c": foot})
	parts.append({"d": C.fdep(R, 0, 0), "k": "torso"})
	parts.append({"d": C.fdep(R, lean * 0.7 + 1.2, 0), "k": "plate"})
	parts.append({"d": C.fdep(R, lean * 0.5 - 2.3, 0), "k": "pack"})
	parts.append({"d": C.fdep(R, lean + 0.3, 0) + 0.02, "k": "head"})
	var wl: float = kit.get("wlen", 7.0)
	var h := _hands(String(p.arms), lean, hz, wl, s_phase(p), modern_rig)
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
				var s: float = q.s
				var a := C.fpt(R, q.a.x, q.a.y, q.a.z)
				var b := C.fpt(R, q.b.x, q.b.y, q.b.z)
				var c := C.fpt(R, q.c.x, q.c.y, q.c.z)
				var toe := C.fpt(R, q.c.x + 1.3, q.c.y, q.c.z - 0.2)
				C.tube(cv, a, b, 1.08 * Z, suit)
				C.blob(cv, C.fpt(R, q.b.x * 0.45, s * 2.15, hz * 0.72), 0.62 * Z, suit_d)   # thigh pocket
				C.tube(cv, b, c, 0.88 * Z, suit)
				C.blob(cv, C.fpt(R, q.b.x + 0.25, q.b.y, q.b.z), 0.75 * Z, plate)            # knee pad
				C.tube(cv, c, toe, 0.8 * Z, boot)
				C.blob(cv, c, 0.85 * Z, boot)
			"torso":
				C.tube(cv, C.fpt(R, 0, 0, hz + 0.6), C.fpt(R, lean * 0.5, 0, hz + 2.2), 1.75 * Z, suit)      # pelvis
				C.tube(cv, C.fpt(R, lean * 0.6, 0, hz + 2.6), C.fpt(R, lean, 0, hz + 4.1), bulk * 0.88 * Z, suit)  # chest
				C.tube(cv, C.fpt(R, lean, -2.2, hz + 4.6), C.fpt(R, lean, 2.2, hz + 4.6), 1.05 * Z, suit)
				C.tube(cv, C.fpt(R, lean * 0.1, -1.8, hz + 0.7), C.fpt(R, lean * 0.1, 1.8, hz + 0.7), 0.62 * Z, web)  # belt
				for s in [-1.0, 1.0]:   # shoulder pads
					C.blob(cv, C.fpt(R, lean, s * 2.5, hz + 4.9), 0.8 * Z, plate)
			"plate":
				C.tube(cv, C.fpt(R, lean * 0.7 + 1.0, 0, hz + 2.0), C.fpt(R, lean * 0.9 + 1.0, 0, hz + 4.3), 1.55 * Z, plate)
				for r in [-1.25, 0.0, 1.25]:   # magazine / utility pouches on the carrier
					C.blob(cv, C.fpt(R, lean * 0.7 + 2.35, r, hz + 2.0), 0.6 * Z, web)
				GR.chest(cv, R, kit)
			"pack":
				GR.pack(cv, R, kit)
				if kit.has("rc") and C.depth(float(R.a), 1.0, 0.0) < 0.2:
					var pp := C.fpt(R, lean * 0.5 - 2.6, 0, hz + 4.4)
					cv.rect(int(pp.x) - 1, int(pp.y), 2, 2, kit.rc)
			"head":
				C.blob(cv, C.fpt(R, lean + 0.1, 0, hz + 5.7), 0.85 * Z, suit_d)  # neck / collar
				var hc := C.fpt(R, lean + 0.3, 0, hz + 7.6 + float(p.breath))
				if String(kit.get("head", "sealed")) == "sealed":
					C.blob(cv, hc + Vector2(0, 0.3 * Z), 2.2 * Z, suit)                 # sealed hood
					C.tube(cv, hc + Vector2(-0.6 * Z, -1.2 * Z), hc + Vector2(0.6 * Z, -1.2 * Z), 0.9 * Z, helm)  # hard shell cap
				else:
					C.blob(cv, hc, 2.1 * Z, helm)
					C.tube(cv, C.fpt(R, lean + 0.3, -2.0, hz + 6.6), C.fpt(R, lean + 0.3, 2.0, hz + 6.6), 0.5 * Z,
						C.ramp(_dk(P.mul(kit.get("helm", kit.plate), 0.72), dk)))   # helmet rim
				GR.head(cv, R, kit, hc, modern_rig)
			"arm":
				var s: float = q.s
				var sh := Vector3(lean, s * 2.8, hz + 4.5)
				var hd: Vector3 = q.hand
				var el := (sh + hd) * 0.5 + Vector3(-0.4, s * 0.7, -1.0)
				var a := C.fpt(R, sh.x, sh.y, sh.z)
				var e := C.fpt(R, el.x, el.y, el.z)
				var hp := C.fpt(R, hd.x, hd.y, hd.z)
				C.tube(cv, a, e, 0.92 * Z, suit)
				C.blob(cv, a.lerp(e, 0.4), 0.98 * Z, team, true)    # team armband (both arms, every facing)
				C.tube(cv, e, hp, 0.82 * Z, suit)
				C.blob(cv, e, 0.62 * Z, plate)                      # elbow pad
				C.blob(cv, hp, 0.8 * Z, glove)
			"weapon":
				var R2 := R
				if bool(q.ground):
					R2 = R.duplicate()
					R2.tilt = 0.0
				GR.weapon(cv, kit, C.fpt(R2, q.wb.x, q.wb.y, q.wb.z), C.fpt(R2, q.wt.x, q.wt.y, q.wt.z), bool(p.flash), Z)
	if p.act >= 0:
		act_fx(cv, R, kit, int(p.act), h)
	if int(p.nade) >= 0:   # ART7D: the grenade in / just out of the throwing hand
		var g: Vector3 = h.rh + (Vector3(1.6, 0.0, 0.6) if int(p.nade) == 1 else Vector3(-0.3, 0.0, 0.4))
		C.blob(cv, C.fpt(R, g.x, g.y, g.z), 0.75 * Z, C.ramp(Color8(78, 88, 64)))


static func s_phase(p: Dictionary) -> float:
	return sin(float(p.ph)) * float(p.sw)


## Default hand and weapon placement per arm mode (local coordinates).
## Coalition uses its own grip. Earlier art generators retain the original hand and weapon coordinates.
static func _hands(mode: String, L: float, hz: float, wl: float, sp: float, modern_rig: bool) -> Dictionary:
	match mode:
		"aim":
			if not modern_rig:
				return {"rh": Vector3(L + 2.0, 0.9, hz + 4.0), "lh": Vector3(L + 4.4, 0.0, hz + 4.1),
					"wb": Vector3(L, 0.8, hz + 4.6), "wt": Vector3(L + wl, 0.6, hz + 4.4)}
			## Braced fire: stock into shoulder pocket, RH on pistol grip, LH on foregrip along the bore.
			return {"rh": Vector3(L + 1.35, 0.85, hz + 4.45), "lh": Vector3(L + 4.55, 0.4, hz + 4.3),
				"wb": Vector3(L - 0.7, 0.9, hz + 4.75), "wt": Vector3(L + wl, 0.45, hz + 4.4)}
		"reload":
			return {"rh": Vector3(L + 2.0, 0.9, hz + 3.4), "lh": Vector3(L + 1.6, -0.4, hz + 2.2),
				"wb": Vector3(L + 0.6, 0.8, hz + 3.0), "wt": Vector3(L + 0.6 + wl * 0.8, 0.6, hz + 5.6)}
		"reload2":   # ART7D: left hand slaps the magazine home at the magwell, muzzle lowering toward the aim line
			return {"rh": Vector3(L + 2.0, 0.9, hz + 3.8), "lh": Vector3(L + 2.6, 0.1, hz + 3.0),
				"wb": Vector3(L + 0.6, 0.8, hz + 3.8), "wt": Vector3(L + 0.6 + wl * 0.9, 0.6, hz + 5.0)}
		"throw0":   # ART7D: throwing arm cocked behind the head, weapon slung muzzle-down on the other side
			return {"rh": Vector3(L - 2.0, 1.8, hz + 7.2), "lh": Vector3(L + 3.0, -1.0, hz + 5.2),
				"wb": Vector3(L + 0.4, -1.9, hz + 4.0), "wt": Vector3(L + 0.4 + wl * 0.75, -2.3, hz + 0.9)}
		"throw1":   # ART7D: arm whipped forward and high, off hand pulled back to the chest
			return {"rh": Vector3(L + 4.2, 0.9, hz + 6.6), "lh": Vector3(L + 0.6, -1.4, hz + 3.6),
				"wb": Vector3(L + 0.4, -1.9, hz + 4.0), "wt": Vector3(L + 0.4 + wl * 0.75, -2.3, hz + 0.9)}
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
	if not modern_rig:
		return {"rh": Vector3(L + 1.8, 1.4, hz + 2.6), "lh": Vector3(L + 3.4, -0.6, hz + 2.4),
			"wb": Vector3(L + 0.8, 1.6, hz + 3.4), "wt": Vector3(L + 0.8 + wl * 0.85, -1.2, hz + 1.4)}
	## Low-ready carry (idle/walk/run): both hands on the weapon, muzzle depressed, stock near hip.
	return {"rh": Vector3(L + 1.55, 1.2, hz + 3.05), "lh": Vector3(L + 3.95, -0.4, hz + 2.75),
		"wb": Vector3(L + 0.35, 1.3, hz + 3.55), "wt": Vector3(L + 0.35 + wl * 0.9, -0.45, hz + 1.95)}


## Act-frame effects drawn over the figure (scan cone, jam rings, arming lights, thrown grenade, ...).
static func act_fx(cv, R: Dictionary, kit: Dictionary, ph: int, h: Dictionary) -> void:
	var Z: float = R.get("sc", 1.0)
	var hz: float = R.hip
	var lean: float = R.lean
	var mz := C.fpt(R, h.wt.x, h.wt.y, h.wt.z) if h.has("wt") else C.fpt(R, lean + 4.0, 0, hz + 4.0)
	var fwd := C.sdir(float(R.a))
	match String(kit.get("act", "signal")):
		"scan":
			for i in 4 + ph * 3:
				var t := (2.0 + i * 1.6) * Z
				var side := C.sdir(float(R.a) + PI / 2.0) * (t * 0.42)
				for sg in [-1.0, 1.0]:
					var pp: Vector2 = mz + fwd * t + side * sg
					cv.px(int(pp.x), int(pp.y), Color(GR.SCAN, 0.95 - i * 0.07))
			cv.px(int(mz.x), int(mz.y), GR.WHITE)
		"jam":
			var c := mz + fwd * 2.0 * Z
			for r in [1.5 + ph, 3.0 + ph, 4.6 + ph]:
				for i in 14:
					var ang := TAU * i / 14.0
					cv.px(int(c.x + cos(ang) * r * Z), int(c.y + sin(ang) * r * Z * 0.6), Color(GR.JAM, 0.9 - r * 0.08))
		"arm":
			var g := C.fpt(R, lean + 4.4, 0, 0.8)
			C.tube(cv, g + Vector2(-2.0 * Z, 0), g + Vector2(2.0 * Z, 0), 1.5 * Z, C.ramp(Color8(150, 146, 120)))
			cv.line_v(g + Vector2(-2.5 * Z, -0.5 * Z), g + Vector2(2.5 * Z, -0.5 * Z), GR.HAZ)
			cv.px(int(g.x), int(g.y - 1.6 * Z), GR.LED_G if ph == 1 else GR.LED_R)
			cv.px(int(g.x) + 2, int(g.y - 1.6 * Z), GR.HAZ)
		"treat", "place":
			var g := C.fpt(R, lean + 4.6, 0, 0.6)
			if String(kit.act) == "place":
				C.blob(cv, g, 1.4 * Z, C.ramp(Color8(96, 84, 64)))
				cv.px(int(g.x), int(g.y) - 1, GR.THERM if ph == 1 else GR.LED_R)
			else:
				C.tube(cv, g + Vector2(-2.5 * Z, 0), g + Vector2(2.5 * Z, 0), 0.9 * Z, C.ramp(Color8(84, 88, 72)))
				cv.px(int(g.x), int(g.y) - 2, GR.WHITE)
				cv.px(int(g.x) + 1, int(g.y) - 2 - ph, Color8(255, 240, 160))
		"throw":
			if ph == 1:
				var g := C.fpt(R, lean + 7.5, 0.4, hz + 8.0)
				C.blob(cv, g, 1.0 * Z, C.ramp(GR.EMP))
		"harpoon":
			if ph == 1:
				cv.line_v(mz, mz + fwd * 12.0 * Z, Color(GR.NET, 0.9))
				var tip: Vector2 = mz + fwd * 12.0 * Z
				cv.px(int(tip.x), int(tip.y), GR.WHITE)
				cv.px(int(tip.x) + 1, int(tip.y), GR.WHITE)
		"launch", "scope":
			if ph == 1:
				C.blob(cv, mz + fwd * 2.0 * Z, 1.2 * Z, [GR.FLASH_O, GR.FLASH_O, GR.FLASH, GR.FLASH, GR.FLASH])
