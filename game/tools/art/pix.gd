extends RefCounted
## Shared pixel helpers for the procedural art generator (agent C-art).
## Deterministic: no global RNG, only integer hashes (hn) and explicitly seeded generators.

const OUTLINE := Color(0.10, 0.11, 0.09, 1.0)
const SHADOW := Color(0.04, 0.05, 0.03, 0.42)
# Iso projection: 1 world tile = (32, 16) half-diamond; z is in screen pixels.
const TW := 32.0
const TH := 16.0
# Light comes from the upper-left of the screen = world -x (slightly -y), and above.
const LIGHT := Vector2(-0.94, -0.33)


class Canvas:
	var img: Image
	var mask: Image
	var sh: Image
	var team := false
	var w: int
	var h: int

	func _init(width: int, height: int) -> void:
		w = width
		h = height
		img = Image.create(w, h, false, Image.FORMAT_RGBA8)
		mask = Image.create(w, h, false, Image.FORMAT_RGBA8)
		sh = Image.create(w, h, false, Image.FORMAT_RGBA8)

	func px(x: int, y: int, c: Color) -> void:
		if x < 0 or y < 0 or x >= w or y >= h:
			return
		if c.a < 0.995:
			c = img.get_pixel(x, y).blend(c)
		if team:
			var l := c.get_luminance()
			img.set_pixel(x, y, Color(l, l, l, c.a))
			mask.set_pixel(x, y, Color(1, 1, 1, 1))
		else:
			img.set_pixel(x, y, c)
			if c.a > 0.9:
				mask.set_pixel(x, y, Color(0, 0, 0, 0))

	func get_px(x: int, y: int) -> Color:
		if x < 0 or y < 0 or x >= w or y >= h:
			return Color(0, 0, 0, 0)
		return img.get_pixel(x, y)

	func rect(x: int, y: int, rw: int, rh: int, c: Color) -> void:
		for yy in range(y, y + rh):
			for xx in range(x, x + rw):
				px(xx, yy, c)

	func line(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
		var dx := absi(x1 - x0)
		var dy := -absi(y1 - y0)
		var sx := 1 if x0 < x1 else -1
		var sy := 1 if y0 < y1 else -1
		var err := dx + dy
		while true:
			px(x0, y0, c)
			if x0 == x1 and y0 == y1:
				break
			var e2 := 2 * err
			if e2 >= dy:
				err += dy
				x0 += sx
			if e2 <= dx:
				err += dx
				y0 += sy

	func line_v(a: Vector2, b: Vector2, c: Color) -> void:
		line(int(floor(a.x)), int(floor(a.y)), int(floor(b.x)), int(floor(b.y)), c)

	## Scanline fill. `shade` (optional Callable(x, y, base) -> Color) textures the polygon.
	func poly(pts: PackedVector2Array, c: Color, shade: Callable = Callable(), to_shadow := false) -> void:
		if pts.size() < 3:
			return
		var miny := INF
		var maxy := -INF
		for p in pts:
			miny = minf(miny, p.y)
			maxy = maxf(maxy, p.y)
		var n := pts.size()
		for y in range(int(floor(miny)), int(ceil(maxy)) + 1):
			var sy := y + 0.5
			var xs: Array = []
			for i in n:
				var a := pts[i]
				var b := pts[(i + 1) % n]
				if (a.y <= sy and b.y > sy) or (b.y <= sy and a.y > sy):
					xs.append(a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x))
			xs.sort()
			var k := 0
			while k + 1 < xs.size():
				for x in range(int(ceil(xs[k] - 0.5)), int(ceil(xs[k + 1] - 0.5))):
					if to_shadow:
						if x >= 0 and y >= 0 and x < w and y < h:
							sh.set_pixel(x, y, Color(1, 1, 1, 1))
					elif shade.is_valid():
						px(x, y, shade.call(x, y, c))
					else:
						px(x, y, c)
				k += 2

	func ellipse(cx: float, cy: float, rx: float, ry: float, c: Color, to_shadow := false) -> void:
		for y in range(int(floor(cy - ry)), int(ceil(cy + ry)) + 1):
			for x in range(int(floor(cx - rx)), int(ceil(cx + rx)) + 1):
				var dx := (x + 0.5 - cx) / rx
				var dy := (y + 0.5 - cy) / ry
				if dx * dx + dy * dy <= 1.0:
					if to_shadow:
						if x >= 0 and y >= 0 and x < w and y < h:
							sh.set_pixel(x, y, Color(1, 1, 1, 1))
					else:
						px(x, y, c)

	## Composite the accumulated shadow layer once (no alpha stacking), then clear it.
	func flush_shadow(col: Color = SHADOW) -> void:
		for y in h:
			for x in w:
				if sh.get_pixel(x, y).a > 0.5:
					img.set_pixel(x, y, img.get_pixel(x, y).blend(col))
		sh.fill(Color(0, 0, 0, 0))

	## 1-px dark outline around opaque pixels (shadows, alpha < 0.6, are ignored).
	func outline(col: Color = OUTLINE) -> void:
		var src: Image = img.duplicate()
		for y in h:
			for x in w:
				if src.get_pixel(x, y).a >= 0.6:
					continue
				var hit := false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var xx: int = x + d.x
					var yy: int = y + d.y
					if xx >= 0 and yy >= 0 and xx < w and yy < h and src.get_pixel(xx, yy).a >= 0.6:
						hit = true
						break
				if hit:
					img.set_pixel(x, y, src.get_pixel(x, y).blend(col))
					mask.set_pixel(x, y, Color(0, 0, 0, 0))


# ---------------------------------------------------------------- hashing / noise
static func hn(x: int, y: int, s: int) -> float:
	var h := (x * 374761393 + y * 668265263 + s * 1442695041) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


static func hi(x: int, y: int, s: int, n: int) -> int:
	return int(hn(x, y, s) * 65535.0) % maxi(1, n)


static func vnoise(x: float, y: float, sc: float, s: int) -> float:
	var fx := x / sc
	var fy := y / sc
	var ix := int(floor(fx))
	var iy := int(floor(fy))
	var tx := fx - ix
	var ty := fy - iy
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := lerpf(hn(ix, iy, s), hn(ix + 1, iy, s), tx)
	var b := lerpf(hn(ix, iy + 1, s), hn(ix + 1, iy + 1, s), tx)
	return lerpf(a, b, ty)


static func mul(c: Color, k: float) -> Color:
	return Color(clampf(c.r * k, 0, 1), clampf(c.g * k, 0, 1), clampf(c.b * k, 0, 1), c.a)


static func mix(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, clampf(t, 0.0, 1.0))


## Per-pixel speckle texture for poly(): base colour jittered by a hash.
static func speckle(amt: float, s: int) -> Callable:
	return func(x: int, y: int, c: Color) -> Color:
		return mul(c, 1.0 + (hn(x, y, s) - 0.5) * amt)


# ---------------------------------------------------------------- iso diamond
## Half-width of row y of a 64x32 tile diamond (rows 15 and 16 are full width).
static func diamond_hw(y: int, th: int = 32) -> int:
	var half := th / 2
	if y < half:
		return (y + 1) * 2
	return (th - y) * 2


static func in_diamond(x: int, y: int, tw: int = 64, th: int = 32) -> bool:
	if y < 0 or y >= th:
		return false
	var hw := diamond_hw(y, th) * tw / 64
	return x >= tw / 2 - hw and x < tw / 2 + hw


# ---------------------------------------------------------------- iso 3D
static func proj(o: Vector2, p: Vector3) -> Vector2:
	return Vector2(o.x + (p.x - p.y) * TW, o.y + (p.x + p.y) * TH - p.z)


static func side_shade(n: Vector2) -> float:
	return 0.70 + 0.26 * n.normalized().dot(LIGHT)


## Box centred at c (x,y in tiles, z = bottom in px), half-extents hx,hy (tiles), height hz (px),
## rotated by `rot` (world radians). Draws visible faces, returns {top, sides:[{quad, n}]}.
## Quads: sides are [bottom-a, bottom-b, top-b, top-a]; top is [(-,-), (+,-), (+,+), (-,+)].
static func box(cv, o: Vector2, c: Vector3, hx: float, hy: float, hz: float, rot: float,
		col: Color, tex: float = 0.08, s: int = 1, top_col = null) -> Dictionary:
	var ax := Vector2(cos(rot), sin(rot))
	var ay := Vector2(-sin(rot), cos(rot))
	var loc := [Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)]
	var gb: Array = []
	var gt: Array = []
	for l in loc:
		var w2: Vector2 = Vector2(c.x, c.y) + ax * l.x + ay * l.y
		gb.append(proj(o, Vector3(w2.x, w2.y, c.z)))
		gt.append(proj(o, Vector3(w2.x, w2.y, c.z + hz)))
	var out := {"sides": [], "top": PackedVector2Array(gt)}
	var normals := [-ay, ax, ay, -ax]  # edge i -> i+1 outward normals
	for i in 4:
		var n: Vector2 = normals[i]
		if n.x + n.y <= 0.001 or hz <= 0.0:
			continue
		var j := (i + 1) % 4
		var q := PackedVector2Array([gb[i], gb[j], gt[j], gt[i]])
		cv.poly(q, mul(col, side_shade(n)), speckle(tex, s + i))
		out.sides.append({"quad": q, "n": n})
	var tc: Color = col if top_col == null else top_col
	cv.poly(out.top, mul(tc, 1.0), speckle(tex, s + 7))
	return out


## Shadow footprint of a box (cast toward world +x/+y, away from the light) into cv.sh.
static func box_shadow(cv, o: Vector2, c: Vector3, hx: float, hy: float, hz: float, rot: float) -> void:
	var ax := Vector2(cos(rot), sin(rot))
	var ay := Vector2(-sin(rot), cos(rot))
	var off := Vector2(0.9, 0.35) * (c.z + hz) / 32.0
	var pts := PackedVector2Array()
	for l in [Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)]:
		var w2: Vector2 = Vector2(c.x, c.y) + ax * l.x + ay * l.y
		pts.append(proj(o, Vector3(w2.x, w2.y, 0)))
		pts.append(proj(o, Vector3(w2.x + off.x, w2.y + off.y, 0)))
	cv.poly(Geometry2D.convex_hull(pts), Color.BLACK, Callable(), true)


## Bilinear sub-quad of a quad (u along 0->1, v along 0->3).
static func sub(q: PackedVector2Array, u0: float, v0: float, u1: float, v1: float) -> PackedVector2Array:
	var f := func(u: float, v: float) -> Vector2:
		var a: Vector2 = q[0].lerp(q[1], u)
		var b: Vector2 = q[3].lerp(q[2], u)
		return a.lerp(b, v)
	return PackedVector2Array([f.call(u0, v0), f.call(u1, v0), f.call(u1, v1), f.call(u0, v1)])


## Paste src onto dst at (x, y) with alpha blending.
static func paste(dst: Image, src: Image, x: int, y: int) -> void:
	dst.blend_rect(src, Rect2i(0, 0, src.get_width(), src.get_height()), Vector2i(x, y))
