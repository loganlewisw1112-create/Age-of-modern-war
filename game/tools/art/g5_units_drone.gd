extends RefCounted
## G5 launched drones (agent ART-U5), 4 types x 2 factions, short-lived air_low entities:
##   Human A "precision": clean light-grey airframes, team stripe, neat payloads.
##     a_drone_strike  tube-launched loitering munition (X wings, pusher prop, seeker nose)
##     a_drone_frag    quadcopter with a grenade pod slung underneath
##     a_drone_recon   bigger quad with a camera gimbal ball and landing skids
##     a_drone_emp     hexacopter with a glowing emitter dish on top
##   Human B "rigged": dark hobby FPV frames, taped payloads, loose coloured wires, rust.
##     b_drone_strike  FPV quad with an RPG warhead strapped on the nose
##     b_drone_frag    FPV quad with a frag tube zip-tied below
##     b_drone_recon   hobby quad with a long antenna whip and tape
##     b_drone_emp     quad carrying a coil jammer and a battery box
## Frames: idle (hover), move (cruise, nose down), fire (terminal effect: strike detonation / frag drop /
## recon scan / emp pulse), dive (steep terminal dive with speed lines), trail (cruise + exhaust trail).
## Pivot = the ground point under the drone; the renderer lifts it by `altitude` (faction_m_drone
## convention) and draws `shadow` at the ground point. Wreck = crashed debris on the ground.
const P = preload("res://tools/art/pix.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")

const SPEC := {"fw": 34, "fh": 30, "pivot": [17, 18]}
const FRAMES := ["idle", "move", "fire", "dive", "trail"]
const OUTL := Color(0.08, 0.08, 0.08, 1)
const A_BODY := Color8(176, 180, 176)
const A_DARK := Color8(92, 96, 96)
const B_BODY := Color8(66, 62, 54)
const B_RUST := Color8(146, 80, 42)
const TAPE := Color8(150, 146, 120)
const WIRE_R := Color8(206, 52, 40)
const WIRE_Y := Color8(226, 196, 60)
const EMP := Color8(110, 170, 255)
const KINDS := ["strike", "frag", "recon", "emp"]


static func build(out: Dictionary) -> void:
	var sh_a := SL.drone_shadow(out, "g5_drone_shadow_s", 4.5, 2.0)
	var sh_b := SL.drone_shadow(out, "g5_drone_shadow_m", 6.0, 2.6)
	for fac in ["a", "b"]:
		for kind: String in KINDS:
			var def := "%s_drone_%s" % [fac, kind]
			var big := kind == "recon" or kind == "emp"
			SL.veh_sheet(out, def, SPEC, func(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
				draw(cv, rot, f, wreck, o, fac, kind), FRAMES,
				{"air": true, "altitude": 14 if kind != "recon" else 18, "bob": 1,
				"shadow": (sh_b if big else sh_a).duplicate()})


static func draw(cv, rot: float, f: int, wreck: bool, o: Vector2, fac: String, kind: String) -> void:
	var k := int(round(rot / (PI / 4.0))) % 8
	var d := L.sd(k)
	var r := L.sd((k + 2) % 8)
	var c := o + Vector2(0, -2)
	if wreck:
		_wreck(cv, c + Vector2(0, 4), d, r, fac, kind, k)
		return
	var pitch := 0.0 if f == 0 else (1.5 if f == 1 or f == 4 else 3.5)
	if f == 3:
		c += Vector2(0, 1)
	if f == 4:
		_trail(cv, c, d, fac, k)
	if f == 3:  # speed lines streaming back and up from a steep dive
		for i in 3:
			var off := r * float(i - 1) * 3.0
			cv.line_v(c - d * 4.0 + off + Vector2(0, -3), c - d * 10.0 + off + Vector2(0, -9), Color(0.92, 0.92, 0.88, 0.45))
	if fac == "a" and kind == "strike":
		_munition(cv, c, d, r, pitch, f)
	else:
		_copter(cv, c, d, r, pitch, f, fac, kind, k)
	cv.outline(OUTL)
	if f == 2:
		_effect(cv, c, d, fac, kind, k)


## Tube-launched loitering munition: slim body, front + rear X wings, seeker nose, pusher prop.
static func _munition(cv, c: Vector2, d: Vector2, r: Vector2, pitch: float, f: int) -> void:
	var nose := c + d * 6.0 + Vector2(0, pitch)
	var tail := c - d * 6.0 - Vector2(0, pitch)
	for wp: float in [0.3, 0.75]:  # wings across the body
		var a: Vector2 = tail.lerp(nose, wp)
		var span := 5.5 if wp > 0.5 else 4.0
		cv.line_v(a - r * span, a + r * span, A_DARK if wp > 0.5 else P.mul(A_BODY, 0.85))
	cv.line_v(tail, nose, A_BODY)
	cv.line_v(tail + Vector2(0, 1), nose + Vector2(0, 1), P.mul(A_BODY, 0.75))
	cv.px(int(nose.x), int(nose.y), Color8(40, 46, 52))
	cv.team = true
	var m: Vector2 = tail.lerp(nose, 0.5)
	cv.rect(int(m.x) - 1, int(m.y), 2, 1, Color(0.75, 0.75, 0.75))
	cv.team = false
	cv.ellipse(tail.x - d.x, tail.y - d.y * 0.5, 2.6, 2.6 if f % 2 == 0 else 1.6, Color(0.85, 0.85, 0.85, 0.3))


## Multirotor: 4 arms (6 for the A EMP hex) with rotor discs, body pod, per-type payload.
static func _copter(cv, c: Vector2, d: Vector2, r: Vector2, pitch: float, f: int, fac: String, kind: String, k: int) -> void:
	var a_side := fac == "a"
	var body: Color = A_BODY if a_side else B_BODY
	var arm_c: Color = A_DARK if a_side else Color8(40, 38, 34)
	var size := 6.5 if kind == "recon" or kind == "emp" else 5.0
	var arms := 6 if (a_side and kind == "emp") else 4
	var tips: Array = []
	for i in arms:
		var ang := (float(i) + 0.5) * TAU / arms
		var v := d * cos(ang) * size + r * sin(ang) * size
		var tilt := Vector2(0, pitch * cos(ang) * 0.5)  # nose (cos > 0) dips, tail lifts
		tips.append(c + v + tilt)
	var back: Array = []
	var front: Array = []
	for t: Vector2 in tips:
		(back if t.y < c.y else front).append(t)
	for t: Vector2 in back:
		_rotor(cv, c, t, arm_c, f, k)
	if kind == "recon" and a_side:  # landing skids under the pod
		cv.line_v(c + r * 3.0 + Vector2(0, 2), c + r * 3.0 + Vector2(0, 4), arm_c)
		cv.line_v(c - r * 3.0 + Vector2(0, 2), c - r * 3.0 + Vector2(0, 4), arm_c)
	_payload_under(cv, c, d, r, fac, kind)
	cv.ellipse(c.x, c.y, 2.8 if size > 6.0 else 2.2, 1.7, body)
	cv.rect(int(c.x) - 1, int(c.y) - 2, 3, 1, P.mul(body, 1.25))
	cv.team = true
	cv.px(int(c.x - d.x * 2.0), int(c.y - d.y * 2.0), Color(0.75, 0.75, 0.75))
	cv.px(int(c.x - d.x * 2.0) + 1, int(c.y - d.y * 2.0), Color(0.7, 0.7, 0.7))
	cv.team = false
	_payload_over(cv, c, d, r, pitch, fac, kind, k)
	for t: Vector2 in front:
		_rotor(cv, c, t, arm_c, f, k)


static func _rotor(cv, c: Vector2, t: Vector2, arm_c: Color, f: int, k: int) -> void:
	cv.line_v(c, t, arm_c)
	cv.px(int(t.x), int(t.y), P.mul(arm_c, 1.4))
	var ph := (f + k) % 2
	cv.ellipse(t.x, t.y - 1, 2.6, 1.0, Color(0.84, 0.86, 0.86, 0.35))
	cv.line_v(t + Vector2(-2, -1 + ph), t + Vector2(2, -1 - ph), Color(0.9, 0.9, 0.9, 0.5))


static func _payload_under(cv, c: Vector2, d: Vector2, r: Vector2, fac: String, kind: String) -> void:
	match fac + kind:
		"afrag":
			cv.rect(int(c.x) - 1, int(c.y) + 1, 3, 3, Color8(70, 78, 56))
			cv.px(int(c.x), int(c.y) + 4, Color8(40, 40, 36))
		"arecon":
			cv.ellipse(c.x + d.x * 1.5, c.y + 2.5, 1.6, 1.5, Color8(46, 50, 54))
			cv.px(int(c.x + d.x * 2.0), int(c.y + 2), Color8(120, 190, 220))
		"bfrag":
			cv.line_v(c - d * 3.0 + Vector2(0, 2), c + d * 3.0 + Vector2(0, 2), Color8(84, 96, 60))
			cv.line_v(c - d * 3.0 + Vector2(0, 3), c + d * 3.0 + Vector2(0, 3), Color8(66, 76, 48))
			cv.px(int(c.x), int(c.y) + 2, TAPE)
		"bemp":
			cv.rect(int(c.x) - 2, int(c.y) + 1, 4, 3, Color8(36, 36, 38))  # battery box
			cv.px(int(c.x) - 2, int(c.y) + 1, WIRE_R)
			cv.px(int(c.x) + 1, int(c.y) + 1, Color8(200, 200, 200))


static func _payload_over(cv, c: Vector2, d: Vector2, r: Vector2, pitch: float, fac: String, kind: String, k: int) -> void:
	match fac + kind:
		"aemp":  # emitter dish, glowing
			cv.ellipse(c.x, c.y - 3, 2.6, 1.2, Color8(200, 204, 200))
			cv.px(int(c.x), int(c.y) - 3, EMP)
			cv.px(int(c.x), int(c.y) - 4, Color8(200, 230, 255))
		"bstrike":  # RPG warhead strapped along the nose
			var h := c + d * 4.0 + Vector2(0, pitch * 0.5)
			cv.line_v(c, h, Color8(70, 74, 52))
			cv.ellipse(h.x, h.y, 1.8, 1.5, Color8(96, 102, 70))
			cv.px(int(h.x + d.x * 2.0), int(h.y + d.y), Color8(40, 40, 34))
			cv.px(int(c.x), int(c.y) - 1, TAPE)
			cv.px(int(c.x) + 1, int(c.y) + 1, WIRE_R)
			cv.px(int(c.x) - 1, int(c.y) + 1, WIRE_Y)
		"brecon":  # long whip antenna + tape
			cv.line_v(c - d * 1.0, c - d * 3.0 + Vector2(0, -8), Color8(40, 40, 36))
			cv.px(int(c.x - d.x * 3.0), int(c.y - d.y * 3.0) - 8, Color8(220, 60, 50))
			cv.px(int(c.x) + 1, int(c.y), TAPE)
		"bemp":  # coil on top, loose wires
			cv.ellipse(c.x, c.y - 3, 2.0, 1.0, Color8(176, 112, 52))
			cv.px(int(c.x), int(c.y) - 3, Color8(220, 150, 80))
			cv.px(int(c.x) - 2, int(c.y) - 1, WIRE_Y)
		"bfrag":
			cv.px(int(c.x) + 1, int(c.y) - 1, B_RUST)


## Exhaust / smoke trail behind the drone (clean faint streak for A, dirty puffs for B).
static func _trail(cv, c: Vector2, d: Vector2, fac: String, k: int) -> void:
	for i in 6:
		var p := c - d * (5.0 + i * 2.2) + Vector2(0, -float(i) * 0.6)
		if fac == "a":
			cv.ellipse(p.x, p.y, 1.2 + i * 0.15, 0.9, Color(0.95, 0.96, 0.93, 0.62 - i * 0.08))
		else:
			L.puff(cv, p, 1.4 + i * 0.3, 0.5 - i * 0.07, Color(0.32, 0.3, 0.27))


static func _effect(cv, c: Vector2, d: Vector2, fac: String, kind: String, k: int) -> void:
	match kind:
		"strike":
			var n := c + d * 6.0 + Vector2(0, 3)
			L.flash(cv, n, 1.4)
			L.puff(cv, n + Vector2(1, -2), 2.5, 0.45)
		"frag":  # payload released, falling
			var g := c + Vector2(0, 6)
			cv.rect(int(g.x), int(g.y), 2, 2, Color8(70, 78, 56) if fac == "a" else Color8(84, 96, 60))
			cv.px(int(g.x), int(g.y) - 2, Color(1, 1, 1, 0.4))
		"recon":  # scan cone to the ground
			for i in 8:
				var t := float(i) / 7.0
				var p := c + Vector2(0, 3) + Vector2(d.x * 2.0, 4.0) * t * 2.0
				cv.ellipse(p.x, p.y, 1.0 + t * 4.0, 0.5 + t * 1.5, Color(0.6, 0.95, 1.0, 0.12))
		"emp":
			for rr: float in [5.0, 8.0]:
				for i in 24:
					var a := i * TAU / 24.0
					cv.px(int(c.x + cos(a) * rr), int(c.y - 1 + sin(a) * rr * 0.5), Color(EMP.r, EMP.g, EMP.b, 0.85 if rr < 6 else 0.5))


## Crash debris on the ground: broken frame, scattered arms, scorch.
static func _wreck(cv, c: Vector2, d: Vector2, r: Vector2, fac: String, kind: String, k: int) -> void:
	cv.ellipse(c.x, c.y, 5.5, 2.2, Color8(40, 36, 32))
	var body: Color = P.mul(A_BODY, 0.55) if fac == "a" else P.mul(B_BODY, 0.8)
	cv.ellipse(c.x, c.y - 1, 2.0, 1.3, body)
	for i in 3:
		var a := c + (d * (2.0 - i * 2.0) + r * (3.0 - i * 2.5))
		cv.line_v(c, a, Color8(46, 44, 40))
	cv.px(int(c.x + r.x * 4.0), int(c.y + r.y * 4.0) + 1, Color8(70, 66, 60))
	cv.outline(OUTL)
	L.puff(cv, c + Vector2(1, -3), 2.0, 0.35, Color(0.3, 0.29, 0.27))
