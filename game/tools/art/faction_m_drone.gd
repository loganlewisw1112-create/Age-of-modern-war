extends RefCounted
## Machine combat drone (agent ART3-M). The frame is drawn with the body resting on the pivot (the ground
## point under it); the renderer lifts it by ALTITUDE px (+ optional sin bob of BOB px) and draws the
## separate shadow image at the ground point. No shadow is baked into the frames.
const P = preload("res://tools/art/pix.gd")
const L = preload("res://tools/art/faction_m_lib.gd")

const ALTITUDE := 18
const BOB := 2
const SHADOW_PIVOT := [15, 7]


static func shadow_image() -> Image:
	var cv = P.Canvas.new(30, 14)
	cv.ellipse(15, 7, 11.0, 5.0, Color.BLACK, true)
	cv.flush_shadow(Color(0.04, 0.05, 0.03, 0.40))
	cv.ellipse(15, 7, 4.5, 2.2, Color(0.04, 0.05, 0.03, 0.18))
	return cv.img


static func draw(cv, rot: float, f: int, o: Vector2) -> void:
	var tilt := 1.0 if f == 1 else 0.0  # moving: nose dips toward travel
	var pods: Array = []
	for a in [[1, 1], [1, -1], [-1, 1], [-1, -1]]:
		var c := L.w(rot, 0.18 * a[0], 0.19 * a[1], 4.0 - tilt * a[0])
		pods.append([c, c.x + c.y])
	pods.sort_custom(func(x, y): return x[1] < y[1])
	var body_c := Vector3(0, 0, 3)
	# far pods + arms
	for i in 2:
		_pod(cv, o, rot, pods[i][0], f, i)
	var front := cos(rot) + sin(rot) > 0.0
	var gun_a := P.proj(o, L.w(rot, 0.1, 0, 3))
	var gun_b := P.proj(o, L.w(rot, 0.24, 0, 2 - tilt))
	if not front:
		cv.line_v(gun_a, gun_b, L.JOINT)
	var b: Dictionary = L.hexp(cv, o, body_c, 0.13, 4.0, rot, L.GRAPH, 181, null, 0.8)
	for sd in b.sides:
		L.seam(cv, sd.quad, 0.45)
	var sh: Dictionary = L.hexp(cv, o, Vector3(0, 0, 7), 0.09, 1.5, rot, L.PANEL, 183, null, 0.8)
	cv.team = true
	L.hexp(cv, o, Vector3(0, 0, 8.5), 0.055, 0.0, rot, Color(0.78, 0.78, 0.78), 185)
	cv.team = false
	if front:
		L.eye(cv, P.proj(o, L.w(rot, 0.12, 0, 5)), true)
		cv.line_v(gun_a, gun_b, L.JOINT)
	for i in range(2, 4):
		_pod(cv, o, rot, pods[i][0], f, i)
	if f == 2:
		cv.px(int(gun_b.x), int(gun_b.y), Color8(255, 236, 160))
		cv.ellipse(gun_b.x, gun_b.y, 1.6, 1.2, Color(1.0, 0.9, 0.6, 0.7))
	cv.outline(Color(0.07, 0.08, 0.09, 1))
	# rotor blur after the outline: translucent discs must not get an outline ring
	for p in pods:
		_blur(cv, o, p[0], f)


## Arm from the body to a rotor pod, plus the motor nacelle.
static func _pod(cv, o: Vector2, rot: float, c: Vector3, f: int, i: int) -> void:
	var a := P.proj(o, Vector3(c.x * 0.4, c.y * 0.4, 5))
	var p := P.proj(o, c)
	cv.line_v(a, p, L.GRAPH_D)
	cv.line_v(a + Vector2(0, 1), p + Vector2(0, 1), L.JOINT)
	cv.ellipse(p.x, p.y + 1, 2.2, 1.6, L.GRAPH_D)
	cv.px(int(p.x), int(p.y), L.CYAN if (f + i) % 2 == 0 else L.TEAL)


static func _blur(cv, o: Vector2, c: Vector3, f: int) -> void:
	var p := P.proj(o, c + Vector3(0, 0, 2))
	var rx := 5.0
	var ry := 2.4
	for y in range(int(floor(p.y - ry)), int(ceil(p.y + ry)) + 1):
		for x in range(int(floor(p.x - rx)), int(ceil(p.x + rx)) + 1):
			var dx := (x + 0.5 - p.x) / rx
			var dy := (y + 0.5 - p.y) / ry
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			var ang := atan2(dy, dx) + f * 0.9
			var blade := absf(sin(ang * 2.0)) > 0.92
			var a := 0.16 + (0.22 if blade else 0.0) + (0.18 if d > 0.72 else 0.0)
			cv.px(x, y, Color(0.78, 0.82, 0.84, a))
