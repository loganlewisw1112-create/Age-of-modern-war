extends RefCounted
## G5 air / naval unit build icons (agent ART-BLD): 32x32 pictograms in the team icon colour on the
## shared panel with the faction accent strip (g3b_lib.panel). Aircraft are drawn top-down (jets,
## VTOLs, drones) or in profile (helicopters); ships in profile on a waterline. IDs: CONTRACTS_G5 s3.2/3.3.
const P = preload("res://tools/art/pix.gd")
const FX = preload("res://tools/art/fx_ui.gd")
const G = preload("res://tools/art/g3b_lib.gd")

const BODY := Color(0.36, 0.52, 0.74)
const DARK := Color8(40, 44, 46)
const GLASS := Color8(150, 200, 214)
const ROTOR := Color8(196, 196, 186)
const WATER := Color8(52, 96, 128)
const CYAN := Color8(86, 222, 216)
const GUN := Color8(70, 72, 68)

const AIR := ["a_attack_heli", "a_transport_gunship", "a_strike_jet", "a_interceptor", "a_vtol_dropship",
	"b_gunship", "b_heavy_lift", "b_bomber", "b_vtol_dropship",
	"m_drone_carrier", "m_lifter_drone", "m_interceptor_swarm", "m_micro_drone"]
const NAVAL := ["a_patrol_boat", "a_landing_craft", "a_destroyer", "a_aa_frigate",
	"b_river_gunboat", "b_barge_carrier", "b_monitor", "m_hydro_skiff", "m_amphib_crawler"]


static func build(out: Dictionary) -> void:
	var icons: Dictionary = out.manifest.get("icons", {})
	for id in AIR + NAVAL:
		var cv = P.Canvas.new(32, 32)
		draw(cv, id)
		cv.outline(Color(0.05, 0.05, 0.04, 1))
		var acc := "b" if id.begins_with("b_") else ("m" if id.begins_with("m_") else "")
		var im: Image = G.panel(acc)
		im.blend_rect(cv.img, Rect2i(0, 0, 32, 32), Vector2i.ZERO)
		out.images["icons/%s.png" % id] = im
		icons[id] = "icons/%s.png" % id
	out.manifest["icons"] = icons


static func _q(cv, pts: Array, c: Color) -> void:
	cv.poly(PackedVector2Array(pts), c)


static func _shade(cv, x0: int, y0: int, x1: int, c: Color) -> void:
	cv.line(x0, y0, x1, y0, P.mul(c, 1.3))


## Profile helicopter: body from x0..x1 at centre y, tail to the left, rotor above.
static func _heli(cv, y: int, ln: int, tall: int, tandem := false) -> void:
	_q(cv, [Vector2(11, y - tall), Vector2(11 + ln, y - tall + 1), Vector2(13 + ln, y), Vector2(11 + ln, y + tall),
		Vector2(11, y + tall)], BODY)
	_q(cv, [Vector2(2, y - 2), Vector2(12, y - 2), Vector2(12, y + 1), Vector2(2, y)], P.mul(BODY, 0.85))
	cv.rect(2, y - 6, 2, 5, P.mul(BODY, 0.8))
	_q(cv, [Vector2(8 + ln, y - tall + 1), Vector2(12 + ln, y - tall + 2), Vector2(13 + ln, y - 1), Vector2(8 + ln, y - 1)], GLASS)
	_shade(cv, 11, y - tall, 10 + ln, BODY)
	cv.rect(3, y - 7, 1, 1, ROTOR)
	if tandem:
		cv.rect(11, y - tall - 2, 4, 2, DARK)
		cv.rect(7 + ln, y - tall - 2, 4, 2, DARK)
		cv.line(2, y - tall - 3, 20, y - tall - 3, ROTOR)
		cv.line(ln, y - tall - 3, 31, y - tall - 3, ROTOR)
	else:
		cv.rect(14 + ln / 4, y - tall - 2, 3, 2, DARK)
		cv.line(3, y - tall - 3, 30, y - tall - 3, ROTOR)
	cv.line(14, y + tall + 1, 11 + ln, y + tall + 1, DARK)


static func _plane(cv, wing: float, sweep: float, lenf: float, c: Color) -> void:
	var nose := Vector2(16, 3)
	var tail := Vector2(16, 3 + 26 * lenf)
	_q(cv, [Vector2(16, 9), Vector2(16 + 14 * wing, 15 + sweep), Vector2(16 + 14 * wing, 18 + sweep),
		Vector2(16, 17), Vector2(16 - 14 * wing, 18 + sweep), Vector2(16 - 14 * wing, 15 + sweep)], P.mul(c, 0.9))
	_q(cv, [nose, Vector2(18, 8), Vector2(18, tail.y), Vector2(14, tail.y), Vector2(14, 8)], c)
	_q(cv, [Vector2(16, tail.y - 5), Vector2(21, tail.y), Vector2(11, tail.y)], P.mul(c, 0.85))
	cv.rect(15, 6, 2, 4, GLASS)
	cv.line(16, 4, 16, int(tail.y) - 1, P.mul(c, 1.25))


static func _hull(cv, x0: int, x1: int, y: int, h: int, bow := 4) -> void:
	_q(cv, [Vector2(x0, y - h), Vector2(x1 + bow, y - h - 1), Vector2(x1 - 1, y), Vector2(x0 + 1, y)], BODY)
	_shade(cv, x0, y - h, x1 + bow - 1, BODY)
	cv.rect(1, y + 1, 30, 2, WATER)
	cv.line(x0 + 2, y - 1, x1 - 2, y - 1, P.mul(BODY, 0.7))


static func draw(cv, id: String) -> void:
	match id:
		"a_attack_heli":
			_heli(cv, 18, 11, 3)
			cv.rect(14, 22, 6, 1, GUN)
			cv.rect(12, 21, 2, 3, GUN)
		"a_transport_gunship":
			_heli(cv, 18, 13, 5)
			cv.rect(17, 15, 4, 3, DARK)
		"b_gunship":
			_heli(cv, 18, 14, 5)
			cv.rect(16, 23, 9, 2, P.mul(BODY, 0.8))
			cv.rect(26, 19, 3, 1, GUN)
		"b_heavy_lift":
			_heli(cv, 19, 17, 5, true)
		"a_strike_jet":
			_plane(cv, 0.85, 4.0, 0.95, BODY)
		"a_interceptor":
			_plane(cv, 0.6, 7.0, 1.0, BODY)
			cv.rect(13, 9, 6, 1, P.mul(BODY, 0.8))
		"b_bomber":
			_plane(cv, 1.0, 0.0, 0.95, BODY)
			for x in [6, 10, 22, 26]:
				cv.rect(x - 1, 14, 2, 4, DARK)
		"a_vtol_dropship", "b_vtol_dropship":
			cv.rect(12, 5, 8, 23, BODY)
			cv.rect(12, 5, 8, 1, P.mul(BODY, 1.3))
			cv.rect(14, 6, 4, 3, GLASS)
			var fans := [Vector2(6, 12), Vector2(26, 12)] if id.begins_with("a_") else [Vector2(6, 9), Vector2(26, 9), Vector2(6, 22), Vector2(26, 22)]
			for f in fans:
				cv.line(16, int(f.y), int(f.x), int(f.y), P.mul(BODY, 0.8))
				cv.ellipse(f.x, f.y, 4.5, 4.5, DARK)
				cv.ellipse(f.x, f.y, 3.0, 3.0, ROTOR)
		"m_drone_carrier":
			var pts: Array = []
			for i in 6:
				var a := i * PI / 3.0
				pts.append(Vector2(16 + cos(a) * 12, 16 + sin(a) * 10))
			_q(cv, pts, BODY)
			cv.ellipse(16, 16, 4, 3.5, DARK)
			cv.ellipse(16, 16, 2, 2, CYAN)
			for i in 3:
				var a := i * TAU / 3.0 + 0.5
				cv.rect(int(16 + cos(a) * 8) - 1, int(16 + sin(a) * 7) - 1, 3, 3, CYAN)
		"m_lifter_drone", "m_micro_drone":
			var s := 1.0 if id == "m_lifter_drone" else 0.6
			cv.rect(int(16 - 4 * s), int(14 - 3 * s), int(8 * s) + 1, int(6 * s) + 1, BODY)
			for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var c: Vector2 = Vector2(16, 14) + d * Vector2(10, 8) * s
				cv.line_v(Vector2(16, 14), c, DARK)
				cv.ellipse(c.x, c.y, 4.0 * s, 2.0 * s, ROTOR)
			cv.px(16, 14, CYAN)
			if id == "m_lifter_drone":
				cv.line(13, 18, 11, 25, DARK)
				cv.line(19, 18, 21, 25, DARK)
				cv.rect(11, 25, 11, 3, P.mul(BODY, 0.7))
		"m_interceptor_swarm":
			for c in [Vector2(10, 11), Vector2(22, 13), Vector2(15, 23)]:
				_q(cv, [c + Vector2(0, -6), c + Vector2(5, 4), c + Vector2(0, 2), c + Vector2(-5, 4)], BODY)
				cv.px(int(c.x), int(c.y), CYAN)
		_:
			_ship(cv, id)


static func _ship(cv, id: String) -> void:
	match id:
		"a_patrol_boat":
			_hull(cv, 4, 24, 22, 4)
			cv.rect(10, 14, 7, 4, P.mul(BODY, 1.1))
			cv.rect(15, 15, 2, 2, GLASS)
			cv.rect(20, 16, 2, 2, GUN)
			cv.line(22, 16, 26, 15, GUN)
		"a_landing_craft":
			_hull(cv, 3, 25, 22, 5, 0)
			cv.line(25, 17, 29, 21, P.mul(BODY, 0.8))
			cv.rect(4, 11, 6, 6, P.mul(BODY, 1.1))
			cv.rect(6, 12, 3, 2, GLASS)
		"a_destroyer":
			_hull(cv, 1, 26, 22, 4)
			cv.rect(9, 13, 9, 5, P.mul(BODY, 1.1))
			cv.rect(12, 8, 3, 5, P.mul(BODY, 1.05))
			cv.line(13, 3, 13, 8, DARK)
			cv.rect(21, 15, 3, 3, GUN)
			cv.line(24, 16, 28, 15, GUN)
		"a_aa_frigate":
			_hull(cv, 2, 25, 22, 4)
			cv.rect(8, 13, 10, 5, P.mul(BODY, 1.1))
			cv.ellipse(13, 10, 3, 3, Color8(220, 220, 212))
			cv.rect(20, 14, 4, 4, DARK)
			cv.rect(4, 15, 3, 3, DARK)
		"b_river_gunboat":
			_hull(cv, 4, 23, 22, 4)
			cv.rect(8, 14, 6, 4, P.mul(BODY, 1.05))
			cv.rect(9, 9, 2, 5, DARK)
			cv.rect(17, 14, 5, 4, GUN)
			cv.line(22, 15, 27, 14, GUN)
		"b_barge_carrier":
			_hull(cv, 2, 27, 23, 3, 1)
			for k in 4:
				cv.rect(6 + k * 5, 15, 4, 5, Color8(170, 96, 48) if k % 2 == 0 else Color8(96, 120, 84))
			cv.rect(2, 13, 4, 7, P.mul(BODY, 1.1))
		"b_monitor":
			_hull(cv, 3, 26, 23, 3)
			cv.rect(10, 13, 10, 7, P.mul(BODY, 1.05))
			cv.rect(10, 13, 10, 1, P.mul(BODY, 1.35))
			cv.rect(19, 15, 10, 2, GUN)
		"m_hydro_skiff":
			_q(cv, [Vector2(4, 13), Vector2(28, 12), Vector2(25, 18), Vector2(6, 18)], BODY)
			cv.line(5, 13, 27, 12, P.mul(BODY, 1.3))
			cv.line(9, 18, 8, 24, DARK)
			cv.line(22, 18, 23, 24, DARK)
			cv.rect(1, 24, 30, 2, WATER)
			cv.line(8, 15, 24, 15, CYAN)
		"m_amphib_crawler":
			_q(cv, [Vector2(4, 12), Vector2(26, 12), Vector2(29, 17), Vector2(3, 17)], BODY)
			cv.rect(4, 17, 24, 5, DARK)
			for k in 6:
				cv.ellipse(6 + k * 4, 19.5, 1.5, 1.5, ROTOR)
			cv.rect(1, 21, 30, 2, Color(WATER.r, WATER.g, WATER.b, 0.8))
			cv.px(24, 14, CYAN)
