extends Node2D
## G7 (CINE7): world-space effects for the cinematics, drawn over the real map in canvas coordinates (a child of the
## match view, above the entities). Purely visual: it reads the shot's fx list (positions in world tiles) and the
## shot-local time, never the sim. Randomness is a local generator with a fixed seed (never w.rng).

const ViewUtil = preload("res://presentation/view/view_util.gd")
const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const CREEP := Color(0.30, 0.04, 0.10, 0.82)
const VEIN := Color(1.0, 0.25, 0.35, 0.9)
const AMBER := Color("e3a83a")
const CYANC := Color("4fc3d9")
const TPX := 45.2548   # one tile of radius on the ground ellipse (32 * sqrt 2) in canvas px (x axis)

var fx: Array = []
var t := 0.0          # shot-local seconds
var dur := 1.0
var hm: Dictionary = {}
var _font: Font = null


func _ready() -> void:
	name = "CineFx"
	z_index = 6
	_font = UiKit.font(true)


func set_shot(list: Array, d: float) -> void:
	fx = list
	dur = maxf(d, 0.001)
	t = 0.0
	queue_redraw()


func advance(time: float) -> void:
	t = time
	queue_redraw()


func P(tile: Vector2) -> Vector2:
	return ViewUtil.world_to_screen_h(hm, tile) if not hm.is_empty() else ViewUtil.iso(tile)


func _zoom() -> float:
	return maxf(get_viewport().get_canvas_transform().x.x, 0.01) if is_inside_tree() else 1.0


## Ground ellipse (a circle of r tiles on the iso ground).
func _ell(c: Vector2, r_tiles: float, col: Color, filled: bool = true, width: float = 2.0) -> void:
	draw_set_transform(c, 0.0, Vector2(1.0, 0.5))
	if filled:
		draw_circle(Vector2.ZERO, r_tiles * TPX, col)
	else:
		draw_arc(Vector2.ZERO, r_tiles * TPX, 0.0, TAU, 64, col, width / 0.75, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _hash01(i: int, salt: int) -> float:
	var h := (i * 73856093) ^ (salt * 19349663)
	h = ((h >> 13) ^ h) * 1274126177
	return float((h >> 8) & 0xFFFF) / 65535.0


func _draw() -> void:
	var u := clampf(t / dur, 0.0, 1.0)
	for f in fx:
		match String(f.get("k", "")):
			"outbreak":
				_outbreak(f, u)
			"core_glow":
				_core_glow(f)
			"network":
				_network(f, u)
			"creep_field":
				_creep_field(f)
			"rings":
				_rings(f, u)
			"flood":
				_flood(f, u)
			"shock":
				_shock(f, u)
			"blasts":
				_blasts(f)
			"contain":
				_contain(f)
			"dawn":
				_dawn(f, u)
			"embers":
				_embers(f)
			"purge":
				_purge(f)


func _outbreak(f: Dictionary, u: float) -> void:
	var c: Vector2 = f.at
	var e := 1.0 - pow(1.0 - u, 2.0)
	var R := lerpf(float(f.get("r0", 1.0)), float(f.get("r1", 12.0)), e)
	var sd := int(c.x * 31.0 + c.y * 17.0)
	var z := _zoom()
	# the growth front: soft dark tide inside, three thin rings rolling outward
	for k in 5:
		_ell(P(c), R * (0.35 + 0.16 * float(k)), Color(CREEP, 0.10))
	for k in 3:
		var q := fmod(t * 0.35 + float(k) / 3.0, 1.0)
		_ell(P(c), R * q, Color(VEIN, 0.55 * (1.0 - q)), false, 1.6 / z)
	_ell(P(c), R, Color(VEIN, 0.75), false, 2.2 / z)
	# spores: small specks scattered inside the front
	for i in 90:
		var a := _hash01(i, sd) * TAU
		var dd := sqrt(_hash01(i, sd + 1)) * R
		if dd > R:
			continue
		var p := P(c + Vector2(cos(a), sin(a)) * dd)
		draw_circle(p, (1.5 + 2.5 * _hash01(i, sd + 2)) / z, Color(VEIN, 0.35 + 0.45 * _hash01(i, sd + 3)))
	# veins out from the source
	for i in 14:
		var a2 := _hash01(i, sd + 9) * TAU
		var pts := PackedVector2Array()
		for k in 7:
			var rr2 := R * float(k) / 6.0
			var wob := (_hash01(i * 7 + k, sd + 3) - 0.5) * 0.7
			pts.append(P(c + Vector2(cos(a2 + wob), sin(a2 + wob)) * rr2))
		var pulse := 0.5 + 0.5 * sin(t * 3.0 + float(i))
		draw_polyline(pts, Color(VEIN, 0.85 * pulse), 2.0 / z, true)
	_glow(P(c), 0.6 + 0.4 * sin(t * 4.0), Color(1.0, 0.3, 0.35))
	_reticle(P(c), 70.0 / z, Color(0.8, 1.0, 0.85, 0.85))


## Surveillance reticle: corner brackets and a centre tick (screen-constant size).
func _reticle(p: Vector2, half: float, col: Color) -> void:
	var z := _zoom()
	var L := half * 0.35
	var w := 2.0 / z
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := p + Vector2(sx * half, sy * half * 0.7)
			draw_line(corner, corner + Vector2(-sx * L, 0), col, w)
			draw_line(corner, corner + Vector2(0, -sy * L), col, w)
	draw_line(p + Vector2(-10, 0) / z, p + Vector2(-4, 0) / z, col, w)
	draw_line(p + Vector2(4, 0) / z, p + Vector2(10, 0) / z, col, w)
	_label(p + Vector2(half * 0.0, half * 0.7 + 18.0 / z), "TRACK 07  //  BIOMASS +%d%%" % int(40.0 + 300.0 * clampf(t / dur, 0.0, 1.0)), Color(col, col.a * 0.9), 13)


func _glow(p: Vector2, k: float, col: Color) -> void:
	var z := _zoom()
	for i in 6:
		var r := (8.0 + 9.0 * float(i)) / z * (0.8 + 0.2 * k)
		draw_circle(p, r, Color(col, 0.16 * (1.0 - float(i) / 6.0) * k))
	draw_circle(p, 4.0 / z, Color(1, 0.85, 0.85, 0.95))


func _core_glow(f: Dictionary) -> void:
	var dim := bool(f.get("dim", false))
	var i := 0
	for p in f.get("pts", []):
		var k := 0.65 + 0.35 * sin(t * 2.6 + float(i) * 1.7)
		_glow(P(p), k * (0.45 if dim else 1.0), Color(1.0, 0.2, 0.3))
		_ell(P(p), 3.0 + 1.5 * fmod(t * 0.8 + float(i) * 0.3, 1.0), Color(1.0, 0.3, 0.35, 0.6 * (1.0 - fmod(t * 0.8 + float(i) * 0.3, 1.0))), false, 2.0 / _zoom())
		i += 1


func _link(a: Vector2, b: Vector2, col: Color, prog: float, width: float, pulse_t: float) -> void:
	var pa := P(a)
	var pb := P(b)
	var pe := pa.lerp(pb, clampf(prog, 0.0, 1.0))
	draw_line(pa, pe, Color(col, col.a * 0.35), width * 2.4, true)
	draw_line(pa, pe, col, width, true)
	if prog >= 1.0:
		for k in 3:
			var q := fmod(pulse_t * 0.35 + float(k) / 3.0, 1.0)
			draw_circle(pa.lerp(pb, q), width * 2.2, Color(1.0, 0.75, 0.75, 0.9))


func _network(f: Dictionary, u: float) -> void:
	var cores: Array = f.get("cores", [])
	var nests: Array = f.get("nests", [])
	var dying := bool(f.get("dying", false))
	var z := _zoom()
	var w := 2.2 / z
	var k := 0
	for i in cores.size():
		for j in range(i + 1, cores.size()):
			var st := 0.08 + 0.12 * float(k)
			var prog := (u - st) / 0.18
			var a := 1.0
			if dying:
				prog = 1.0
				a = clampf(1.0 - (u - st) / 0.2, 0.0, 1.0)
			if a > 0.0:
				_link(cores[i], cores[j], Color(1.0, 0.2, 0.3, 0.85 * a), prog, w, t)
			k += 1
	for n in nests.size():
		var p: Vector2 = nests[n]
		var best: Vector2 = cores[0] if not cores.is_empty() else p
		for c in cores:
			if (c as Vector2).distance_to(p) < best.distance_to(p):
				best = c
		var st2 := 0.4 + 0.3 * float(n) / maxf(float(nests.size()), 1.0)
		var a2 := 1.0
		var prog2 := (u - st2) / 0.15
		if dying:
			prog2 = 1.0
			a2 = clampf(1.0 - (u - 0.05 - 0.4 * float(n) / maxf(float(nests.size()), 1.0)) / 0.15, 0.0, 1.0)
		if a2 > 0.0:
			_link(best, p, Color(0.95, 0.35, 0.5, 0.6 * a2), prog2, w * 0.6, t + float(n))
			if prog2 > 0.0:
				draw_circle(P(p), 5.0 / z, Color(1.0, 0.4, 0.5, 0.85 * a2))
	if f.has("base") and not dying and u > 0.72 and not cores.is_empty():
		var b: Vector2 = f.base
		var near: Vector2 = cores[0]
		for c in cores:
			if (c as Vector2).distance_to(b) < near.distance_to(b):
				near = c
		var pa := P(near)
		var pb := P(b)
		var n2 := 24
		for s in n2:
			if s % 2 == 0:
				var q0 := float(s) / float(n2) * clampf((u - 0.72) / 0.15, 0.0, 1.0)
				var q1 := float(s + 1) / float(n2) * clampf((u - 0.72) / 0.15, 0.0, 1.0)
				draw_line(pa.lerp(pb, q0), pa.lerp(pb, q1), Color(1.0, 0.85, 0.3, 0.8), w, true)
		if u > 0.85:
			_label(pb + Vector2(0, -26.0 / z), "BASTION", Color(1.0, 0.85, 0.3, clampf((u - 0.85) / 0.06, 0.0, 1.0)), 18)


func _creep_field(f: Dictionary) -> void:
	for v in f.get("field", []):
		var c := Vector2(v.x, v.y)
		_ell(P(c), 4.6 * float(v.z), Color(CREEP, 0.28 * float(v.z)))


func _rings(f: Dictionary, u: float) -> void:
	var rings: Array = f.get("rings", [])
	var hl := int(f.get("hl", -1))
	var labels: Array = f.get("labels", [])
	var z := _zoom()
	for i in rings.size():
		var r: Rect2 = rings[i]
		var pts := PackedVector2Array([P(r.position), P(Vector2(r.end.x, r.position.y)), P(r.end), P(Vector2(r.position.x, r.end.y)), P(r.position)])
		var on := i == hl
		var a := clampf(u * 4.0, 0.0, 1.0) * (1.0 if on else 0.35)
		draw_polyline(pts, Color(AMBER, 0.25 * a), ((6.0 if on else 0.0) + 4.0) / z, true)
		draw_polyline(pts, Color(AMBER if on else Color(0.9, 0.9, 0.85), 0.9 * a), (2.5 if on else 1.2) / z, true)
		if on:
			var per := 0.0
			for k in 4:
				per += pts[k].distance_to(pts[k + 1])
			var head := fmod(t * 0.22, 1.0) * per
			var acc := 0.0
			for k in 4:
				var seg := pts[k].distance_to(pts[k + 1])
				if head >= acc and head <= acc + seg:
					draw_circle(pts[k].lerp(pts[k + 1], (head - acc) / seg), 6.0 / z, Color(1, 0.95, 0.7, 0.95))
				acc += seg
			if i < labels.size():
				var top := pts[0]
				for k in 4:
					if pts[k].y < top.y:
						top = pts[k]
				_label(top + Vector2(0, -22.0 / z), String(labels[i]), Color(AMBER, clampf((u - 0.1) * 5.0, 0.0, 1.0)), 20)


func _label(p: Vector2, s: String, col: Color, px: int) -> void:
	if _font == null:
		return
	var z := _zoom()
	var fs := int(float(px))
	draw_set_transform(p, 0.0, Vector2.ONE / z)
	var wdt := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(-wdt * 0.5 + 2, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, col.a * 0.8))
	draw_string(_font, Vector2(-wdt * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _flood(f: Dictionary, u: float) -> void:
	var g := float(f.get("from", 0.0)) + float(f.get("grow", 10.0)) * (1.0 - pow(1.0 - u, 2.0))
	var field: Array = f.get("field", [])
	for v in field:
		var c := Vector2(v.x, v.y)
		_ell(P(c), 3.0 + g * (0.4 + 0.6 * float(v.z)), Color(CREEP, 0.55))
	if f.has("base"):
		var b: Vector2 = f.base
		_ell(P(b), g * 1.2, Color(CREEP, 0.5 * u))
	for v in field.slice(0, mini(field.size(), 60)):
		var p := P(Vector2(v.x, v.y))
		var k := 0.5 + 0.5 * sin(t * 3.0 + v.x)
		draw_circle(p, 3.0 / _zoom(), Color(VEIN, 0.6 * k))


func _shock(f: Dictionary, u: float) -> void:
	var r1 := float(f.get("r1", 100.0))
	for p in f.get("pts", []):
		for k in 3:
			var q := clampf(u * 1.25 - float(k) * 0.12, 0.0, 1.0)
			if q <= 0.0:
				continue
			_ell(P(p), r1 * q, Color(1, 1, 1, 0.75 * (1.0 - q)), false, 10.0 / _zoom())
			_ell(P(p), r1 * q * 0.98, Color(1, 0.9, 0.7, 0.25 * (1.0 - q)), true)


func _blasts(f: Dictionary) -> void:
	var c: Vector2 = f.at
	var r := float(f.get("r", 8.0))
	var n := int(f.get("n", 10))
	var z := _zoom()
	for i in n:
		var life := 1.4
		var start := _hash01(i, 5) * 2.5
		var lt := fmod(t + 10.0 - start, 2.5 + _hash01(i, 6) * 1.5)
		if lt > life:
			continue
		var q := lt / life
		var a := _hash01(i, 7) * TAU
		var p := P(c + Vector2(cos(a), sin(a)) * r * sqrt(_hash01(i, 8)))
		var size := (14.0 + 26.0 * _hash01(i, 9)) / z
		draw_circle(p + Vector2(0, -size * q * 0.6), size * (0.6 + q), Color(0.25, 0.22, 0.2, 0.55 * q * (1.0 - q) * 3.0))
		draw_circle(p, size * (0.4 + 0.6 * q), Color(1.0, 0.55, 0.15, 0.85 * (1.0 - q)))
		draw_circle(p, size * 0.5 * (1.0 - q), Color(1.0, 0.95, 0.75, 0.95 * (1.0 - q)))


func _contain(f: Dictionary) -> void:
	var c: Vector2 = f.at
	var z := _zoom()
	var pc := P(c)
	for k in 3:
		var rr := 3.0 + 1.6 * float(k)
		var rot := t * (0.6 - 0.35 * float(k)) * (1.0 if k % 2 == 0 else -1.0)
		draw_set_transform(pc, 0.0, Vector2(1.0, 0.5))
		for s in 12:
			var a0 := rot + TAU * float(s) / 12.0
			draw_arc(Vector2.ZERO, rr * TPX, a0, a0 + TAU / 24.0, 8, Color(CYANC, 0.85), 3.0 / z, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var py := []
	for s in 6:
		var a := TAU * float(s) / 6.0 + 0.3
		py.append(c + Vector2(cos(a), sin(a)) * 6.5)
	for i in py.size():
		var p := P(py[i])
		draw_rect(Rect2(p - Vector2(5, 14) / z, Vector2(10, 14) / z), Color(0.75, 0.85, 0.9))
		draw_circle(p - Vector2(0, 14) / z, 3.5 / z, Color(CYANC, 0.6 + 0.4 * sin(t * 6.0 + float(i))))
		if fmod(t * 2.0 + float(i) * 0.37, 1.0) < 0.35:   # EMP arc to the core
			var pts := PackedVector2Array()
			var a2 := p - Vector2(0, 14) / z
			for k2 in 7:
				var q := float(k2) / 6.0
				var j := (Vector2(_hash01(i * 13 + k2, int(t * 12.0)), _hash01(i * 17 + k2, int(t * 12.0) + 1)) - Vector2(0.5, 0.5)) * 22.0 / z
				pts.append(a2.lerp(pc, q) + (j if k2 > 0 and k2 < 6 else Vector2.ZERO))
			draw_polyline(pts, Color(0.8, 1.0, 1.0, 0.9), 2.0 / z, true)
	_glow(pc, 0.4 + 0.1 * sin(t * 1.5), Color(0.5, 0.9, 1.0))


func _dawn(f: Dictionary, u: float) -> void:
	var pc := P(f.at)
	var z := _zoom()
	for i in 10:
		var r := (120.0 + 110.0 * float(i)) / z * (0.8 + 0.25 * u)
		draw_circle(pc, r, Color(1.0, 0.85, 0.55, 0.035))


func _embers(f: Dictionary) -> void:
	var c: Vector2 = f.at
	var r := float(f.get("r", 20.0))
	var z := _zoom()
	var sd := int(c.x + c.y * 3.0)
	for i in 70:
		var a := _hash01(i, sd) * TAU
		var p := P(c + Vector2(cos(a), sin(a)) * r * sqrt(_hash01(i, sd + 1)))
		var sp := 18.0 + 30.0 * _hash01(i, sd + 2)
		var cyc := 3.0 + 3.0 * _hash01(i, sd + 3)
		var q := fmod(t + _hash01(i, sd + 4) * cyc, cyc) / cyc
		var off := Vector2(sin(t * 1.3 + float(i)) * 10.0, -sp * q * 6.0) / z
		draw_circle(p + off, (2.0 + 1.5 * _hash01(i, sd + 5)) / z, Color(1.0, 0.55 + 0.3 * _hash01(i, sd + 6), 0.2, 0.85 * sin(q * PI)))


func _purge(f: Dictionary) -> void:
	var z := _zoom()
	var i := 0
	for c in f.get("pts", []):
		for k in 28:
			var a := _hash01(k, i + 40) * TAU
			var p := P(Vector2(c) + Vector2(cos(a), sin(a)) * 14.0 * sqrt(_hash01(k, i + 41)))
			var q := fmod(t * 0.4 + _hash01(k, i + 42), 1.0)
			draw_circle(p + Vector2(0, -40.0 * q) / z, 2.5 / z, Color(0.85, 1.0, 0.85, 0.8 * sin(q * PI)))
		i += 1
