extends RefCounted
## G5 runway strips (agent ART-BLD, CONTRACTS_G5 s7): strips are virtual (sim/systems/airfield.gd
## strip_points: beside the apron building, 3 tiles wide, 4 tiles apart, strip_len tiles long), so they
## are drawn by the renderer from 1 x 3-tile SEGMENT sprites laid along the strip axis, plus crater and
## "strip closed" overlays. One set per style (a = concrete + white marks, b = asphalt + yellow marks,
## m = Machine launch rail, fwd = steel matting) and per facing f (axis AX[f]):
##   start (threshold piano keys), mid (centre dash), end (far threshold), link (1 x 1 taxi connector
##   across the gap between neighbouring strips). Canvas 140 x 80, pivot (70, 40) = segment centre.
const P = preload("res://tools/art/pix.gd")
const L = preload("res://tools/art/faction_m_lib.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")

const W := 140
const H := 80
const PIV := Vector2(70, 40)
const STYLES := {
	"a": {"deck": Color8(122, 122, 116), "edge": Color8(232, 230, 220), "line": Color8(232, 230, 220)},
	"b": {"deck": Color8(76, 72, 66), "edge": Color8(230, 188, 70), "line": Color8(230, 188, 70)},
	"m": {"deck": Color8(58, 62, 66), "edge": Color8(86, 222, 216), "line": Color8(34, 120, 122)},
	"fwd": {"deck": Color8(104, 110, 98), "edge": Color8(236, 120, 40), "line": Color8(214, 210, 190)},
}
const KINDS := ["start", "mid", "end", "link"]


static func build(out: Dictionary) -> Dictionary:
	var sec := {"strip_width": 3, "strip_spacing": 4, "segment_len": 1, "segments": {}, "craters": [],
		"craters_repair": [], "closed": {}}
	for st in STYLES:
		var per := {}
		for f in 4:
			var kinds := {}
			for k in KINDS:
				var cv = P.Canvas.new(W, H)
				segment(cv, PIV, st, f, k)
				var file := "strips/%s_f%d_%s.png" % [st, f, k]
				out.images[file] = cv.img
				kinds[k] = {"file": file, "pivot": [int(PIV.x), int(PIV.y)]}
			per[str(f)] = kinds
		sec.segments[st] = per
	for i in 3:
		for rep in [false, true]:
			var cv = P.Canvas.new(W, H)
			crater(cv, PIV, i, rep)
			var file := "strips/crater_%d%s.png" % [i, "_repair" if rep else ""]
			out.images[file] = cv.img
			(sec.craters_repair if rep else sec.craters).append({"file": file, "pivot": [int(PIV.x), int(PIV.y)]})
	for f in 4:
		var cv = P.Canvas.new(W, H)
		closed(cv, PIV, f)
		var file := "strips/closed_f%d.png" % f
		out.images[file] = cv.img
		sec.closed[str(f)] = {"file": file, "pivot": [int(PIV.x), int(PIV.y)]}
	return sec


static func segment(cv, o: Vector2, st: String, f: int, kind: String) -> void:
	var s: Dictionary = STYLES[st]
	var deck: Color = s.deck
	var hv := 0.5 if kind == "link" else 1.5
	var hu := 0.5 if kind != "link" else 1.5
	if kind == "link":  # taxi link runs across the gap: along v, 1 tile wide along u
		hu = 0.5
		hv = 0.5
	cv.poly(PackedVector2Array([K.pt(o, f, -hu, -hv, 0), K.pt(o, f, hu, -hv, 0), K.pt(o, f, hu, hv, 0), K.pt(o, f, -hu, hv, 0)]),
		deck, P.speckle(0.07, 11 + f))
	if kind == "link":
		K.gquad(cv, o, f, -0.04, -0.5, 0.04, 0.5, 0, s.line)
		return
	K.gquad(cv, o, f, -0.5, -1.5, 0.5, -1.38, 0, s.edge)
	K.gquad(cv, o, f, -0.5, 1.38, 0.5, 1.5, 0, s.edge)
	match st:
		"m":
			for v in [-0.55, 0.55]:
				var r := P.box(cv, o, Vector3(K.wp(f, 0, v).x, K.wp(f, 0, v).y, 0), 0.5 if f % 2 == 0 else 0.07,
					0.07 if f % 2 == 0 else 0.5, 3, 0.0, L.PANEL_D, 0.03, 5)
				cv.line_v(r.top[0].lerp(r.top[3], 0.5), r.top[1].lerp(r.top[2], 0.5), L.CYAN if kind != "mid" else L.TEAL)
			K.lamp(cv, K.pt(o, f, 0, -1.44, 1), L.CYAN_HOT)
			K.lamp(cv, K.pt(o, f, 0, 1.44, 1), L.CYAN_HOT)
			if kind == "start":
				var c := K.wp(f, -0.1, 0)
				P.box(cv, o, Vector3(c.x, c.y, 0), 0.3 if f % 2 == 0 else 0.62, 0.62 if f % 2 == 0 else 0.3, 7, 0.0, L.GRAPH, 0.04, 9)
				K.lamp(cv, K.pt(o, f, -0.1, 0, 8), L.CYAN_HOT)
			elif kind == "end":
				for v in [-1.2, 1.2]:
					var c := K.wp(f, 0.3, v)
					cv.line_v(P.proj(o, Vector3(c.x, c.y, 0)), P.proj(o, Vector3(c.x, c.y, 14)), L.PANEL)
				cv.line_v(K.pt(o, f, 0.3, -1.2, 10), K.pt(o, f, 0.3, 1.2, 10), Color(L.CYAN.r, L.CYAN.g, L.CYAN.b, 0.6))
			return
		"fwd":
			for i in 6:
				var u := -0.42 + i * 0.17
				K.gline(cv, o, f, u, -1.35, u, 1.35, 0, P.mul(deck, 0.82))
			for v in [-0.9, -0.3, 0.3, 0.9]:
				K.gline(cv, o, f, -0.5, v, 0.5, v, 0, P.mul(deck, 0.88))
	match kind:
		"mid":
			K.gquad(cv, o, f, -0.35, -0.05, 0.1, 0.05, 0, s.line)
			if st != "fwd":
				K.lamp(cv, K.pt(o, f, 0, -1.44, 0), Color8(240, 236, 200))
				K.lamp(cv, K.pt(o, f, 0, 1.44, 0), Color8(240, 236, 200))
		"start", "end":
			var u0 := -0.42 if kind == "start" else 0.05
			K.gquad(cv, o, f, -0.48 if kind == "start" else 0.4, -1.35, -0.4 if kind == "start" else 0.48, 1.35, 0, s.line)
			for i in 8:
				var v := -1.22 + i * 0.32 + (0.08 if i >= 4 else 0.0)
				K.gquad(cv, o, f, u0, v, u0 + 0.36, v + 0.16, 0, s.line)
			for v in [-1.44, -0.7, 0.7, 1.44]:
				K.lamp(cv, K.pt(o, f, -0.46 if kind == "start" else 0.46, v, 0), Color8(120, 236, 120) if kind == "start" else Color8(238, 64, 48))


## Bomb crater overlay (round, axis-independent): dark pit, raised ejecta rim, scattered debris.
## repair = engineers' patch: gravel fill, a roller strip and two traffic cones.
static func crater(cv, o: Vector2, i: int, repair: bool) -> void:
	var r := 0.42 + i * 0.05
	var cx := (P.hn(i, 3, 1) - 0.5) * 0.3
	var cy := (P.hn(i, 3, 2) - 0.5) * 0.6
	for k in 26:
		var a := k * TAU / 26.0
		var rr := r * (1.15 + 0.25 * P.hn(k, i, 4))
		var p := P.proj(o, Vector3(cx + cos(a) * rr, cy + sin(a) * rr, 0))
		cv.rect(int(p.x) - 1, int(p.y) - 1, 3, 2, Color8(112, 100, 80) if k % 3 else Color8(86, 78, 64))
	var pts := PackedVector2Array()
	for k in 18:
		var a := k * TAU / 18.0
		var rr := r * (0.85 + 0.25 * P.hn(k, i, 5))
		pts.append(P.proj(o, Vector3(cx + cos(a) * rr, cy + sin(a) * rr, 0)))
	if repair:
		cv.poly(pts, Color8(118, 116, 108), P.speckle(0.25, 40 + i))
		cv.line_v(P.proj(o, Vector3(cx - r, cy, 0)), P.proj(o, Vector3(cx + r, cy, 0)), Color8(92, 90, 84))
		for s in [-1.0, 1.0]:
			var c := P.proj(o, Vector3(cx + s * r * 1.3, cy - s * r * 0.6, 0))
			cv.poly(PackedVector2Array([c + Vector2(-2, 0), c + Vector2(2, 0), c + Vector2(0, -6)]), Color8(240, 120, 40))
			cv.rect(int(c.x) - 1, int(c.y) - 3, 2, 1, Color8(236, 232, 220))
		return
	cv.poly(pts, Color8(44, 38, 32), P.speckle(0.2, 30 + i))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(p.lerp(P.proj(o, Vector3(cx, cy, 0)), 0.45) + Vector2(0, 1))
	cv.poly(inner, Color8(26, 22, 18))
	for k in 10:
		var a := P.hn(k, i, 7) * TAU
		var d := r * (1.4 + P.hn(k, i, 8) * 0.9)
		var p := P.proj(o, Vector3(cx + cos(a) * d, cy + sin(a) * d, 0))
		cv.rect(int(p.x), int(p.y), 2 if k % 2 else 1, 1, Color8(150, 146, 136) if k % 3 else Color8(70, 66, 60))


## "Strip closed" overlay: yellow X across the 3-wide strip.
static func closed(cv, o: Vector2, f: int) -> void:
	var c := Color8(246, 206, 60)
	for t in [-0.05, 0.0, 0.05]:
		cv.line_v(K.pt(o, f, -0.45 + t, -1.1, 0), K.pt(o, f, 0.45 + t, 1.1, 0), c)
		cv.line_v(K.pt(o, f, -0.45 + t, 1.1, 0), K.pt(o, f, 0.45 + t, -1.1, 0), c)
