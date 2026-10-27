extends RefCounted
## DL7 sample Machine threats (owner: ARTCN7; G7_REFERENCE 8), drawn in the Machine's CURRENT style
## (faction_m_lib: graphite hulls, pale panels, dark joints, cyan seams / sensor glow) at the DL7 level.
##   g7_m_packhunter  wolf / spider gait walker, clawed talons (packs of 4-6)
##   g7_m_weaver      huge spider-mother: web spit, cocoon, hauls the cocoon to the creep
##   g7_m_living_core pulsing core growing plating, scream ring when hit; second phase tears out of the ground
##                    and walks
## Team mask: plating trim. 8 facings.
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const L = preload("res://tools/art/faction_m_lib.gd")

const HUNT_FRAMES := ["idle", "walk_0", "walk_1", "walk_2", "walk_3", "run_0", "run_1", "pounce", "claw_0", "claw_1", "die"]
const WEAVE_FRAMES := ["idle", "walk_0", "walk_1", "walk_2", "walk_3", "spit", "cocoon", "haul", "die"]
const CORE_FRAMES := ["pulse_0", "pulse_1", "pulse_2", "plated", "hit", "emerge_0", "emerge_1", "walk_0", "walk_1",
	"walk_2", "walk_3"]
const SILK := Color8(214, 220, 210)
const CREEP := Color8(36, 40, 44)
const TRIM := Color8(150, 150, 150)


static func _leg(cv, R: Dictionary, hip: Vector3, knee: Vector3, foot: Vector3, r: float, glow: bool, talon: bool) -> void:
	var a := C.fpt(R, hip.x, hip.y, hip.z)
	var b := C.fpt(R, knee.x, knee.y, knee.z)
	var c := C.fpt(R, foot.x, foot.y, foot.z)
	C.tube(cv, a, b, r, C.ramp(L.GRAPH))
	C.tube(cv, b, c, r * 0.8, C.ramp(L.GRAPH_D))
	C.blob(cv, b, r * 1.05, C.ramp(L.JOINT))
	if glow:
		cv.px(int(b.x), int(b.y), L.CYAN)
	if talon:
		var d := C.sdir(float(R.a))
		cv.line_v(c, c + d * 2.0 + Vector2(0, 1), C.ramp(L.PANEL)[3])
		cv.line_v(c, c - d * 1.0 + Vector2(1, 1), C.ramp(L.PANEL)[2])


## Legs list -> drawn back to front with the body parts (each part {d, fn}).
static func _draw_sorted(parts: Array) -> void:
	parts.sort_custom(func(x, y): return x.d < y.d)
	for q in parts:
		(q.fn as Callable).call()


static func packhunter(cv, k: int, fname: String, o: Vector2) -> void:
	var R := {"a": k * PI / 4.0, "o": o, "tilt": 0.0, "bob": 0.0, "sc": 1.45}
	var S := 1.45
	var ph := 0.0
	var sw := 0.0
	var lunge := 0.0
	var crouch := 0.0
	var dead := fname == "die"
	if fname.begins_with("walk_"):
		ph = TAU * float(int(fname.substr(5))) / 4.0
		sw = 2.4
	elif fname.begins_with("run_"):
		ph = PI * float(int(fname.substr(4)))
		sw = 4.0
		R.bob = 1.0 if fname == "run_0" else 0.0
	match fname:
		"pounce":
			R.bob = 6.0
			lunge = 3.0
		"claw_0":
			crouch = 2.0
		"claw_1":
			lunge = 2.0
	var bz := 8.0 - crouch - (5.0 if dead else 0.0)
	C.ground_shadow(cv, o + Vector2(0, 1), 16.0, 6.5)
	var parts: Array = []
	var i := 0
	for hp in [Vector2(4, -2.4), Vector2(4, 2.4), Vector2(-4, -2.4), Vector2(-4, 2.4)]:
		var diag := (i == 0 or i == 3)
		var sp: float = sw * sin(ph + (0.0 if diag else PI))
		var lift: float = maxf(0.0, cos(ph + (0.0 if diag else PI))) * sw * 0.4
		var s := signf(hp.y)
		var hip := Vector3(hp.x + lunge, hp.y, bz)
		var knee := Vector3(hp.x + lunge * 0.5 + (1.5 if hp.x > 0 else -1.5), s * 4.6, bz + 3.5 - (3.0 if dead else 0.0))
		var foot := Vector3(hp.x + sp + (lunge * 1.5 if hp.x > 0 else 0.0), s * 5.6, lift + (1.5 if fname == "pounce" else 0.0))
		if fname == "claw_1" and hp.x > 0 and s > 0:
			foot = Vector3(hp.x + 7.0, 2.0, bz + 3.0)
			knee = Vector3(hp.x + 4.0, 4.0, bz + 6.0)
		parts.append({"d": C.fdep(R, hp.x, s * 4.6), "fn": _leg.bind(cv, R, hip, knee, foot, 1.15 * S, true, true)})
		i += 1
	var body := func():
		C.tube(cv, C.fpt(R, -5.5 + lunge, 0, bz + 1.0), C.fpt(R, 4.5 + lunge, 0, bz + 1.6), 3.1 * S, C.ramp(L.GRAPH))
		C.tube(cv, C.fpt(R, -3.5 + lunge, 0, bz + 3.6), C.fpt(R, 3.0 + lunge, 0, bz + 4.0), 1.7 * S, C.ramp(L.PANEL))
		C.tube(cv, C.fpt(R, -3.0 + lunge, -1.4, bz + 3.0), C.fpt(R, 2.5 + lunge, -1.4, bz + 3.2), 0.5 * S, C.ramp(TRIM), true)
		C.tube(cv, C.fpt(R, -6.0 + lunge, 0, bz + 2.0), C.fpt(R, -9.5 + lunge, 0, bz + 4.0 - (3.0 if dead else 0.0)), 0.8 * S, C.ramp(L.GRAPH_D))
		var hc := C.fpt(R, 7.5 + lunge * 1.3, 0, bz + 2.6 - crouch)
		C.blob(cv, hc, 2.3 * S, C.ramp(L.GRAPH))
		C.tube(cv, hc, C.fpt(R, 10.0 + lunge * 1.4, 0, bz + 1.0 - crouch), 1.0 * S, C.ramp(L.PANEL))
		if C.depth(float(R.a), 1.0, 0.0) > -0.4 and not dead:
			var side := C.sdir(float(R.a) + PI / 2.0)
			cv.px(int(hc.x + side.x), int(hc.y + side.y - 1), L.CYAN_HOT)
			cv.px(int(hc.x - side.x), int(hc.y - side.y - 1), L.CYAN)
		for j in 3:
			var sc := C.fpt(R, -3.0 + j * 2.6 + lunge, 0, bz + 4.4)
			cv.px(int(sc.x), int(sc.y), L.DEAD_SEAM if dead else L.CYAN)
	parts.append({"d": C.fdep(R, 0.0, 0.0), "fn": body})
	_draw_sorted(parts)


static func weaver(cv, k: int, fname: String, o: Vector2) -> void:
	var R := {"a": k * PI / 4.0, "o": o, "tilt": 0.0, "bob": 0.0}
	var ph := 0.0
	if fname.begins_with("walk_"):
		ph = TAU * float(int(fname.substr(5))) / 4.0
	var dead := fname == "die"
	var bz := 20.0 - (14.0 if dead else 0.0)
	C.ground_shadow(cv, o + Vector2(0, 2), 40.0, 15.0, 0.30)
	var parts: Array = []
	for i in 8:
		var s := -1.0 if i < 4 else 1.0
		var j := i % 4
		var ang := 0.55 + j * 0.62
		var gait: float = sin(ph + j * PI * 0.5 + (0.0 if s > 0 else PI)) * (3.0 if fname.begins_with("walk") else 0.0)
		var hip := Vector3(6.0 - j * 2.0, s * 4.5, bz)
		var reach := 27.0 if not dead else 18.0
		var foot := Vector3(cos(ang) * reach - 2.0 + gait, s * sin(ang) * reach, 0.0)
		var knee := Vector3(hip.x + (foot.x - hip.x) * 0.45, hip.y + (foot.y - hip.y) * 0.55, bz + (16.0 if not dead else 3.0))
		parts.append({"d": C.fdep(R, knee.x, knee.y), "fn": _leg.bind(cv, R, hip, knee, foot, 1.6, j % 2 == 0, true)})
	var body := func():
		var ab := C.fpt(R, -13.0, 0, bz + 6.0)
		C.blob(cv, ab, 13.0, C.ramp(L.GRAPH))
		for j in 4:   # abdominal plating with team-mask trim and cyan seams
			var pc := C.fpt(R, -18.0 + j * 4.0, 0, bz + 15.0 - absf(j - 1.5) * 2.0)
			C.blob(cv, pc, 4.2 - absf(j - 1.5), C.ramp(L.PANEL))
			cv.line_v(pc + Vector2(-3, 2), pc + Vector2(3, 2), L.CYAN if not dead else L.DEAD_SEAM)
		C.tube(cv, C.fpt(R, -20.0, -5.0, bz + 9.0), C.fpt(R, -6.0, -5.0, bz + 12.0), 0.6, C.ramp(TRIM), true)
		C.tube(cv, C.fpt(R, -20.0, 5.0, bz + 9.0), C.fpt(R, -6.0, 5.0, bz + 12.0), 0.6, C.ramp(TRIM), true)
		C.blob(cv, C.fpt(R, -25.0, 0, bz + 3.0), 2.4, C.ramp(L.JOINT))   # spinnerets
		C.blob(cv, C.fpt(R, 4.0, 0, bz + 3.0), 7.5, C.ramp(L.GRAPH))
		C.blob(cv, C.fpt(R, 4.0, 0, bz + 7.0), 4.5, C.ramp(L.PANEL))
		var hc := C.fpt(R, 12.0, 0, bz + 2.0)
		C.blob(cv, hc, 4.6, C.ramp(L.GRAPH_D))
		if C.depth(float(R.a), 1.0, 0.0) > -0.5 and not dead:
			var side := C.sdir(float(R.a) + PI / 2.0)
			for e in [-1.6, -0.5, 0.5, 1.6]:
				var ep: Vector2 = hc + side * e + C.sdir(float(R.a)) * 2.5 + Vector2(0, -1.0 - absf(e) * 0.5)
				cv.px(int(ep.x), int(ep.y), L.CYAN_HOT if absf(e) < 1.0 else L.CYAN)
		_weaver_fx(cv, R, fname, bz)
	parts.append({"d": C.fdep(R, -4.0, 0.0), "fn": body})
	_draw_sorted(parts)


static func _weaver_fx(cv, R: Dictionary, fname: String, bz: float) -> void:
	var mouth := C.fpt(R, 16.0, 0, bz + 1.0)
	var fwd := C.sdir(float(R.a))
	match fname:
		"spit":
			for i in 7:
				var p := mouth + fwd * (4.0 + i * 3.0) + Vector2(0, i * 0.8)
				C.blob(cv, p, 1.4 - i * 0.12, C.ramp(SILK))
				cv.px(int(p.x) + 1, int(p.y) - 1, L.CYAN)
		"cocoon", "haul":
			var c := mouth + fwd * 8.0 + Vector2(0, bz * 0.6) if fname == "cocoon" else C.fpt(R, -30.0, 3.0, 2.0)
			C.tube(cv, c + Vector2(-4, 0), c + Vector2(4, -1), 2.6, C.ramp(SILK))
			for i in 4:
				cv.line_v(c + Vector2(-4 + i * 2.5, -2), c + Vector2(-3 + i * 2.5, 2), C.ramp(SILK)[1])
			cv.px(int(c.x) - 3, int(c.y) - 1, Color8(246, 178, 60))   # a trapped visor glint
			var anchor := C.fpt(R, -25.0, 0, bz + 3.0) if fname == "haul" else mouth
			cv.line_v(anchor, c, Color(SILK, 0.8))


static func living_core(cv, k: int, fname: String, o: Vector2) -> void:
	var R := {"a": k * PI / 4.0, "o": o, "tilt": 0.0, "bob": 0.0}
	var walking := fname.begins_with("walk") or fname.begins_with("emerge")
	var rise := 0.0
	match fname:
		"emerge_0":
			rise = 6.0
		"emerge_1":
			rise = 14.0
	if fname.begins_with("walk"):
		rise = 18.0
	var pulse := 0
	if fname.begins_with("pulse_"):
		pulse = int(fname.substr(6))
	# creep crater + veins (only while rooted)
	if not fname.begins_with("walk"):
		cv.ellipse(o.x, o.y, 44.0, 19.0, Color(CREEP, 0.92))
		for i in 12:
			var t := TAU * i / 12.0 + 0.3
			var e := o + Vector2(cos(t) * 50.0, sin(t) * 22.0)
			cv.line_v(o + Vector2(cos(t) * 14.0, sin(t) * 6.0), e, CREEP)
			cv.px(int(lerpf(o.x, e.x, 0.6)), int(lerpf(o.y, e.y, 0.6)), L.CYAN if (i + pulse) % 3 == 0 else L.TEAL)
	else:
		C.ground_shadow(cv, o + Vector2(0, 2), 30.0, 12.0)
	var parts: Array = []
	if walking:
		var ph := TAU * float(int(fname.substr(5))) / 4.0 if fname.begins_with("walk") else 0.0
		for i in 4:
			var t := PI / 4.0 + i * PI / 2.0
			var g: float = sin(ph + i * PI) * (4.0 if fname.begins_with("walk") else 0.0)
			var hip := Vector3(cos(t) * 8.0, sin(t) * 8.0, rise + 10.0)
			var foot := Vector3(cos(t) * 22.0 + g, sin(t) * 22.0, 0.0)
			var knee := (hip + foot) * 0.5 + Vector3(0, 0, 14.0)
			parts.append({"d": C.fdep(R, knee.x, knee.y), "fn": _leg.bind(cv, R, hip, knee, foot, 2.4, true, true)})
	var body := func():
		var cz := 16.0 + rise
		var c := C.fpt(R, 0, 0, cz)
		C.blob(cv, c, 15.0, C.ramp(L.GRAPH_D))
		var glow := 6.0 + pulse * 1.5 + (3.0 if fname == "hit" else 0.0)
		C.blob(cv, c + Vector2(-1, -1), glow, [L.TEAL, L.TEAL, L.CYAN, L.CYAN_HOT, Color(1, 1, 1)])
		var plates := 5 if fname != "plated" and not walking else 9
		for i in plates:
			var t := TAU * i / float(plates) + 0.4
			var pp := c + Vector2(cos(t) * 11.0, sin(t) * 9.0)
			C.blob(cv, pp, 4.0, C.ramp(L.PANEL))
			cv.px(int(pp.x), int(pp.y) + 2, TRIM)
			cv.mask.set_pixel(clampi(int(pp.x), 0, cv.w - 1), clampi(int(pp.y) + 2, 0, cv.h - 1), Color(1, 1, 1, 1))
		if fname == "hit":
			for r in [20.0, 26.0]:
				for i in 32:
					var t := TAU * i / 32.0
					cv.px(int(c.x + cos(t) * r), int(c.y + sin(t) * r * 0.55), Color(L.CYAN_HOT, 0.8))
		if fname.begins_with("emerge"):
			for i in 6:
				var t := TAU * i / 6.0
				C.blob(cv, o + Vector2(cos(t) * (18.0 + rise), sin(t) * 7.0 - rise * 0.4), 2.5, C.ramp(Color8(96, 82, 64)))
	parts.append({"d": C.fdep(R, 0.0, 0.0), "fn": body})
	_draw_sorted(parts)


static func build(out: Dictionary) -> void:
	C.unit_sheet(out, "g7_m_packhunter", "vehicles", "threat", 56, 44, Vector2i(28, 32), HUNT_FRAMES,
		func(cv, k, f, o): packhunter(cv, k, f, o),
		{"sample": "threat", "line": "machine", "legged": true, "key_frames": HUNT_FRAMES.duplicate(),
		"anim_strip": ["walk_0", "walk_1", "walk_2", "walk_3", "run_0", "run_1", "pounce", "claw_0", "claw_1", "die"]})
	C.unit_sheet(out, "g7_m_weaver", "vehicles", "threat_big", 132, 104, Vector2i(66, 76), WEAVE_FRAMES,
		func(cv, k, f, o): weaver(cv, k, f, o),
		{"sample": "threat", "line": "machine", "legged": true, "key_frames": WEAVE_FRAMES.duplicate(),
		"anim_strip": ["idle", "walk_0", "walk_1", "walk_2", "walk_3", "spit", "cocoon", "haul", "walk_0", "die"]})
	C.unit_sheet(out, "g7_m_living_core", "vehicles", "threat_big", 108, 100, Vector2i(54, 70), CORE_FRAMES,
		func(cv, k, f, o): living_core(cv, k, f, o),
		{"sample": "threat", "line": "machine", "key_frames": CORE_FRAMES.duplicate(),
		"anim_strip": ["pulse_0", "pulse_1", "pulse_2", "plated", "hit", "emerge_0", "emerge_1", "walk_0", "walk_1", "walk_2"]})
