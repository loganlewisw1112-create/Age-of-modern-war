extends RefCounted
## Per-role dressing for built buildings (agent E2): windows, doors, gates, team bands, roofs and
## rooftop clutter, props; plus a per-building post pass (cables, lamps, ladder, pipes, mast light).
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")

const GLASS := Color8(36, 42, 46)


static func _face(sd: Dictionary) -> String:
	var n: Vector2 = sd.n
	return "y" if n.y > 0.7 else ("x" if n.x > 0.7 else "")


static func dress(cv, o: Vector2, def: String, p: Array, r: Dictionary, col: Color) -> void:
	var role := String(p[7])
	var s := int(p[0] * 100 + p[1] * 37)
	match role:
		"main", "upper", "garage", "cabin":
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				var face := _face(sd)
				var flen: float = q[0].distance_to(q[1])
				if role == "garage":
					B.rollup(cv, q, 0.12, 0.45, 0.62, 0.55 if face == "y" else 0.0, s + 1)
					B.rollup(cv, q, 0.55, 0.88, 0.62, 0.0 if face == "y" else 0.4, s + 2)
					B.window_row(cv, q, 0.74, 0.8, 6, col, s + 3, 0.15)
					cv.team = true
					cv.poly(P.sub(q, 0.05, 0.86, 0.95, 0.93), Color(0.7, 0.7, 0.7))
					cv.team = false
					continue
				var n := maxi(2, int(flen / 10.0))
				match def:
					"hq":
						if role == "main":
							B.window_row(cv, q, 0.56, 0.7, n, col, s + 5)
							B.window_row(cv, q, 0.26, 0.4, n, col, s + 6)
							if face == "y":
								B.door(cv, q, 0.42, 0.58, 0.36, col)
						else:
							B.window_row(cv, q, 0.42, 0.66, n, col, s + 7, 0.35)
					"barracks":
						B.window_row(cv, q, 0.42, 0.64, n + 1, col, s + 8, 0.3)
						if face == "y":
							B.door(cv, q, 0.47, 0.57, 0.58, col)
						elif face == "x":
							B.door(cv, q, 0.42, 0.58, 0.58, col)
					"depot":
						B.window_row(cv, q, 0.66, 0.76, n, col, s + 9, 0.2)
						if face == "y":
							B.rollup(cv, q, 0.18, 0.62, 0.56, 0.0, s + 10)
						elif face == "x":
							B.door(cv, q, 0.68, 0.8, 0.5, col)
					"generator":
						for i in 3:  # louvred vents
							var u0 := 0.16 + i * 0.26
							var vq := P.sub(q, u0, 0.32, u0 + 0.16, 0.62)
							cv.poly(vq, P.mul(col, 0.6))
							for t in [0.3, 0.6, 0.9]:
								cv.line_v(vq[0].lerp(vq[3], t), vq[1].lerp(vq[2], t), P.mul(col, 1.05))
						cv.poly(P.sub(q, 0.1, 0.15, 0.9, 0.22), Color8(170, 140, 50))  # hazard band
						if face == "y":
							B.door(cv, q, 0.04, 0.13, 0.5, col)
					"refinery":
						B.window_row(cv, q, 0.5, 0.66, n, col, s + 11, 0.4)
						if face == "y":
							B.door(cv, q, 0.15, 0.26, 0.42, col)
					"guard_tower":
						cv.poly(P.sub(q, 0.12, 0.45, 0.88, 0.8), GLASS)  # observation slit
						cv.line_v(P.sub(q, 0.12, 0.45, 0.88, 0.8)[3], P.sub(q, 0.12, 0.45, 0.88, 0.8)[2], B.GLASS_HI)
				if role == "main" and def != "generator":
					cv.team = true
					cv.poly(P.sub(q, 0.0, 0.84, 1.0, 0.92), Color(0.68, 0.68, 0.68))
					cv.team = false
			B.edges(cv, r, col)
			# roof: parapet rim + per-building clutter
			cv.poly(P.sub(r.top, 0.08, 0.08, 0.92, 0.92), P.mul(col, 0.86), P.speckle(0.08, 7))
			if role == "main" and def == "barracks":
				cv.poly(P.sub(r.top, 0.0, 0.42, 1.0, 0.58), P.mul(col, 0.72))
			if role == "main" and def == "hq":
				cv.team = true
				cv.poly(P.sub(r.top, 0.65, 0.2, 0.85, 0.8), Color(0.74, 0.74, 0.74))
				cv.team = false
			_roof(cv, o, def, role, p)
		"stack":
			cv.poly(P.sub(r.top, 0.2, 0.2, 0.8, 0.8), Color8(24, 24, 22))
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				for v in [0.3, 0.7]:
					cv.line_v(q[0].lerp(q[3], v), q[1].lerp(q[2], v), P.mul(col, 0.75))  # bands
				cv.poly(P.sub(q, 0.0, 0.86, 1.0, 1.0), Color(0.05, 0.05, 0.04, 0.5))     # soot
			B.edges(cv, r, col)
		"crate":
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				cv.line_v(q[0], q[2], P.mul(col, 0.7))
				cv.line_v(q[0].lerp(q[3], 0.85), q[1].lerp(q[2], 0.85), P.mul(col, 0.72))
			B.edges(cv, r, col)
		"sandbag":
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				for v in [0.33, 0.66]:
					cv.line_v(q[0].lerp(q[3], v), q[1].lerp(q[2], v), P.mul(col, 0.75))
				var m := int(q[0].distance_to(q[1]) / 3.0)
				for i in m:  # individual bag bulges
					for v in [0.16, 0.5, 0.83]:
						var u := (i + (0.5 if v == 0.5 else 0.0)) / maxf(1.0, m)
						var b: Vector2 = q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), v)
						cv.px(int(b.x), int(b.y), P.mul(col, 1.18))
			B.edges(cv, r, col)
		"barrier":
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				for i in 4:
					var u := (i + 0.5) / 4.0
					cv.line_v(q[0].lerp(q[1], u - 0.08).lerp(q[3].lerp(q[2], u - 0.08), 0.3),
						q[0].lerp(q[1], u + 0.04).lerp(q[3].lerp(q[2], u + 0.04), 0.75), Color8(186, 150, 48))
			B.edges(cv, r, col)
		"transformer":
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				for i in 5:  # radiator fins
					var u := 0.12 + i * 0.19
					cv.line_v(q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), 0.1), q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), 0.8), P.mul(col, 0.7))
				cv.poly(P.sub(q, 0.35, 0.82, 0.65, 0.95), Color8(178, 148, 52))  # warning plate
			B.edges(cv, r, col)
			for v in [0.25, 0.5, 0.75]:  # insulators
				var t: Vector2 = P.sub(r.top, 0.45, v, 0.55, v)[0]
				cv.rect(int(t.x), int(t.y) - 3, 1, 3, Color8(196, 186, 160))
		"mast":
			B.edges(cv, r, col)
		"deck", "roof":
			B.edges(cv, r, col)


static func _roof(cv, o: Vector2, def: String, role: String, p: Array) -> void:
	var z: float = p[2] + p[5]
	var cx: float = p[0]
	var cy: float = p[1]
	match def + ":" + role:
		"hq:main":
			B.hvac(cv, o, Vector3(0.85, 0.85, z), 0.15, 0.12, 301)
			B.vent(cv, o, Vector3(0.95, -0.72, z), 302)
			B.vent(cv, o, Vector3(-0.75, 0.78, z), 303)
		"hq:upper":
			B.vent(cv, o, Vector3(-0.6, 0.1, z), 304)
			var base := P.proj(o, Vector3(0.05, -0.45, z))  # satellite dish on a short post
			cv.line(int(base.x), int(base.y), int(base.x), int(base.y) - 4, Color8(70, 72, 70))
			cv.ellipse(base.x - 1, base.y - 6, 4.2, 2.6, Color8(196, 198, 192))
			cv.ellipse(base.x - 1.5, base.y - 6.5, 2.6, 1.4, Color8(160, 162, 158))
			cv.px(int(base.x) + 2, int(base.y) - 8, Color8(60, 60, 58))
			B.pipe(cv, o, Vector3(-0.6, 0.1, z + 1), Vector3(-0.6, 0.3, z + 1), B.STEEL_L)
		"barracks:main":
			B.vent(cv, o, Vector3(cx - 0.6, cy, z), 305 + int(cy * 10))
			B.vent(cv, o, Vector3(cx + 0.1, cy, z), 306 + int(cy * 10))
			if cy > 0:
				B.hvac(cv, o, Vector3(cx + 0.7, cy + 0.08, z), 0.12, 0.1, 307)
		"depot:main":
			B.hvac(cv, o, Vector3(cx + 0.35, cy - 0.3, z), 0.14, 0.11, 308)
			B.vent(cv, o, Vector3(cx - 0.4, cy + 0.3, z), 309)
		"motor_pool:garage":
			B.hvac(cv, o, Vector3(cx + 0.6, cy - 0.55, z), 0.16, 0.13, 310)
			B.hvac(cv, o, Vector3(cx - 0.5, cy + 0.6, z), 0.13, 0.11, 311)
			B.vent(cv, o, Vector3(cx + 0.7, cy + 0.6, z), 312)
			B.pipe(cv, o, Vector3(cx - 0.3, cy - 0.7, z + 1.5), Vector3(cx + 0.4, cy - 0.7, z + 1.5), B.STEEL_L)
		"refinery:main":
			B.vent(cv, o, Vector3(cx + 0.35, cy - 0.3, z), 313)
			B.hvac(cv, o, Vector3(cx - 0.2, cy + 0.25, z), 0.13, 0.11, 314)


## Overlays that span parts: cables, ladder, lamps, pipe runs, mast beacons.
static func post(cv, o: Vector2, def: String) -> void:
	match def:
		"generator":
			var tr := P.proj(o, Vector3(0.8, 0.02, 11))
			for e in [Vector3(0.75, -0.5, 20), Vector3(0.75, 0.55, 20)]:
				var pt := P.proj(o, e)
				B.cable(cv, tr + Vector2(0, -3), pt, 2.5)
				cv.rect(int(pt.x) - 2, int(pt.y), 5, 1, Color8(70, 72, 70))  # crossarm
				cv.px(int(pt.x) - 2, int(pt.y) - 1, Color8(196, 186, 160))
				cv.px(int(pt.x) + 2, int(pt.y) - 1, Color8(196, 186, 160))
			B.cable(cv, P.proj(o, Vector3(0.75, -0.5, 20)) + Vector2(2, -1), P.proj(o, Vector3(0.75, 0.55, 20)) + Vector2(2, -1), 3.0)
		"guard_tower":
			for i in 6:  # ladder rungs between the two front legs
				var z := 5.0 + i * 4.0
				cv.line_v(P.proj(o, Vector3(-0.25, 0.25, z)), P.proj(o, Vector3(0.25, 0.25, z)), Color8(150, 122, 84))
			for c in [Vector3(-0.34, 0.34, 42), Vector3(0.34, 0.34, 42), Vector3(0.34, -0.34, 42)]:
				B.lamp(cv, P.proj(o, c))
		"refinery":
			for zz in [8.0, 12.0]:
				B.pipe(cv, o, Vector3(-0.6, -0.5, zz), Vector3(-0.6, 0.1, zz), B.STEEL_L)
				B.pipe(cv, o, Vector3(-0.45, -0.65, zz + 2), Vector3(0.15, -0.65, zz + 2), Color8(150, 110, 70))
			B.pipe(cv, o, Vector3(0.05, -0.1, 10), Vector3(0.05, 0.4, 10), B.STEEL_L)
			B.pipe(cv, o, Vector3(-0.45, 0.45, 6), Vector3(-0.15, 0.45, 6), Color8(150, 110, 70))
			var tip := P.proj(o, Vector3(0.05, -0.1, 36))
			cv.px(int(tip.x), int(tip.y) - 1, Color8(255, 196, 96))  # flare pilot
		"hq":
			var t := P.proj(o, Vector3(0.55, -0.6, 56))
			cv.px(int(t.x), int(t.y), Color8(230, 60, 40))
			for zz in [36.0, 46.0]:
				var a := P.proj(o, Vector3(0.55, -0.6, zz))
				cv.rect(int(a.x) - 2, int(a.y), 5, 1, Color8(70, 74, 76))
		"motor_pool":
			var t := P.proj(o, Vector3(1.2, 0.95, 32))
			cv.px(int(t.x), int(t.y), Color8(230, 60, 40))
