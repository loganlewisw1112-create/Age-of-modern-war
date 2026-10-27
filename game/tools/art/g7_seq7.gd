extends SceneTree
## G7 SEQ7 (13.9c-7 "mission sequences on screen"): the art the facility sequence layer (presentation/view/fac_seq7.gd)
## draws on top of the ARTCN7 / ART7F art. Display only. Deterministic: re-running writes byte-identical files.
##   godot --headless --path . -s tools/art/g7_seq7.gd                 # writes assets/art/g7_seq7/
##   godot --headless --path . -s tools/art/g7_seq7.gd -- --out=<abs dir>
## Prints "G7_SEQ7 files=<n>".
## What it makes (rev3 scale, art.detail_level DL7-3: 4 m per 64x32 tile, 9.8 px per metre of height, light upper-left):
##  - crew/<id>_dirty.png: every ARTCN7 strike-crew / operator sheet (same 32x32 cells, same frame order and facings)
##    with field grime: nanite-grey mud caked on boots and legs, spatter on the torso, glints of dead nanite dust. The
##    decon sequence swaps a returning crew from this sheet to the clean ARTCN7 sheet when they leave the decon hall.
##  - props/stretcher.png: 8 facings x 2 rows (row 0 casualty aboard under a foil blanket with a field dressing,
##    row 1 empty litter), cell 48x32, pivot [24, 22] = the litter centre on the ground.
##  - props/cart.png: 8 facings x 3 rows (ammo tug + trailer: row 0 full = rocket-pod reload pack + special-round
##    crates, row 1 pod pack gone, row 2 empty bed), cell 72x52, pivot [36, 34] = the rig centre on the ground.
##  - props/podpack.png: 8 facings, the 6-tube rocket-pod reload pack on its own (lifted onto the APC), cell 32x26,
##    pivot [16, 18].
##  - props/crate.png: 8 facings, one special-round crate carried by a loader, cell 16x16, pivot [8, 11].
const GEN = preload("res://tools/gen_art.gd")
const GROUP := "g7_seq7"
const OUTLINE := Color(0.07, 0.08, 0.09, 1.0)
const PXM_X := 8.0      # screen px per metre along a ground axis (x component)
const PXM_Y := 4.0
const PXM_H := 9.8      # screen px per metre of height
const LIGHT := Vector2(-0.70710678, 0.70710678)   # world direction of the light (screen upper-left)
# 5-tone ramps [deep, shade, mid, lit, glint] (muted military)
const OD := [Color(0.16, 0.19, 0.12), Color(0.24, 0.28, 0.17), Color(0.33, 0.38, 0.24), Color(0.43, 0.48, 0.31), Color(0.55, 0.60, 0.42)]
const STEEL := [Color(0.16, 0.17, 0.19), Color(0.25, 0.27, 0.30), Color(0.38, 0.40, 0.43), Color(0.52, 0.55, 0.58), Color(0.70, 0.73, 0.76)]
const TUG := [Color(0.40, 0.30, 0.06), Color(0.58, 0.45, 0.10), Color(0.74, 0.60, 0.16), Color(0.86, 0.74, 0.28), Color(0.96, 0.88, 0.50)]
const RUBBER := [Color(0.06, 0.06, 0.07), Color(0.10, 0.10, 0.11), Color(0.15, 0.15, 0.16), Color(0.20, 0.20, 0.21), Color(0.28, 0.28, 0.29)]
const CANVAS := [Color(0.20, 0.22, 0.15), Color(0.29, 0.31, 0.21), Color(0.38, 0.40, 0.28), Color(0.47, 0.49, 0.35), Color(0.58, 0.60, 0.45)]
const FOIL := [Color(0.45, 0.42, 0.30), Color(0.62, 0.58, 0.40), Color(0.80, 0.74, 0.50), Color(0.92, 0.87, 0.62), Color(1.0, 0.97, 0.80)]
const SUIT := [Color(0.18, 0.21, 0.22), Color(0.27, 0.31, 0.32), Color(0.37, 0.42, 0.43), Color(0.48, 0.53, 0.54), Color(0.62, 0.67, 0.68)]
const BAND := Color(0.86, 0.70, 0.16)
const GRIME := Color(0.31, 0.28, 0.21)
const GRIME_D := Color(0.13, 0.12, 0.10)
const GLINT := Color(0.42, 0.62, 0.64)


func _init() -> void:
	var dir := "res://assets/art/%s" % GROUP
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			dir = String(a).substr(6)
	var out := build()
	var n := GEN.save(out, dir)
	print("G7_SEQ7 files=%d" % n)
	quit()


static func build() -> Dictionary:
	var images := {}
	var crew := {}
	var cm = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/g7_cn/manifest.json"))
	var inf: Dictionary = (cm as Dictionary).get("infantry", {}) if cm is Dictionary else {}
	var ids: Array = inf.keys()
	ids.sort()
	for id in ids:
		var ent: Dictionary = inf[id]
		var src := "res://assets/art/g7_cn/%s" % String(ent.get("file", ""))
		if not FileAccess.file_exists(src):
			continue
		var img := Image.load_from_file(ProjectSettings.globalize_path(src))
		if img == null:
			continue
		img.convert(Image.FORMAT_RGBA8)
		var rel := "crew/%s_dirty.png" % String(id)
		images[rel] = dirty_sheet(img, int(ent.get("fw", 32)), int(ent.get("fh", 32)), hash(String(id)) & 0xffff)
		crew[String(id)] = rel
	images["props/stretcher.png"] = _sheet(48, 32, 8, 2, func(im, k, row): _stretcher(im, k, row))
	images["props/cart.png"] = _sheet(72, 52, 8, 3, func(im, k, row): _cart(im, k, row))
	images["props/podpack.png"] = _sheet(32, 26, 8, 1, func(im, k, _row): _podpack_only(im, k))
	images["props/crate.png"] = _sheet(16, 16, 8, 1, func(im, k, _row): _crate_only(im, k))
	var man := {"group": GROUP, "version": "SEQ7-1", "seq7": {
		"crew_dirty": crew,
		"stretcher": {"file": "props/stretcher.png", "fw": 48, "fh": 32, "pivot": [24, 22], "facings": 8, "rows": ["casualty", "empty"]},
		"cart": {"file": "props/cart.png", "fw": 72, "fh": 52, "pivot": [36, 34], "facings": 8, "rows": ["full", "pod_gone", "empty"]},
		"podpack": {"file": "props/podpack.png", "fw": 32, "fh": 26, "pivot": [16, 18], "facings": 8},
		"crate": {"file": "props/crate.png", "fw": 16, "fh": 16, "pivot": [8, 11], "facings": 8},
		"detail_level": "DL7-3", "scale": "4 m per tile, 9.8 px per metre of height"}}
	return {"images": images, "manifest": man}


# ================================================================ dirty crew
## Same sheet with field grime. Pure function of the source pixels and the seed (deterministic).
static func dirty_sheet(src: Image, fw: int, fh: int, seed: int) -> Image:
	var im: Image = src.duplicate()
	var w: int = im.get_width()
	var h: int = im.get_height()
	for y in h:
		for x in w:
			var c := src.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var lum := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			if lum < 0.10:
				continue   # keep the outline
			var fy: int = y % fh
			var fx: int = x % fw
			# clumped noise: 2x2 blocks + single pixels
			var blk: int = _h(seed, (x >> 1) + (fx >> 3) * 7, (y >> 1)) % 100
			var px: int = _h(seed + 17, x, y) % 100
			var legs: bool = fy >= int(fh * 0.66)       # boots / shins (cell 32: rows 21..)
			var thigh: bool = fy >= int(fh * 0.56)
			var rate := 82 if legs else (52 if thigh else 24)
			if blk < rate:
				var k := 0.78 if legs else 0.55
				var g := GRIME_D if px < 18 else GRIME
				c = Color(lerpf(c.r, g.r, k), lerpf(c.g, g.g, k), lerpf(c.b, g.b, k), c.a)
			elif px < 3:
				c = Color(lerpf(c.r, GLINT.r, 0.6), lerpf(c.g, GLINT.g, 0.6), lerpf(c.b, GLINT.b, 0.6), c.a)   # dead nanite dust
			else:
				c = Color(c.r * 0.80, c.g * 0.81, c.b * 0.76, c.a)   # dulled, dust-filmed suit
			im.set_pixel(x, y, c)
	return im


static func _h(s: int, x: int, y: int) -> int:
	var v := (s * 374761393 + x * 668265263 + y * 2147483647) & 0x7fffffff
	v = ((v ^ (v >> 13)) * 1274126177) & 0x7fffffff
	return v ^ (v >> 16)


# ================================================================ iso cuboids
static func _sheet(fw: int, fh: int, cols: int, rows: int, fn: Callable) -> Image:
	var im := Image.create(fw * cols, fh * rows, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	for r in rows:
		for k in cols:
			var cell := Image.create(fw, fh, false, Image.FORMAT_RGBA8)
			cell.fill(Color(0, 0, 0, 0))
			fn.call(cell, k, r)
			_outline(cell)
			im.blit_rect(cell, Rect2i(0, 0, fw, fh), Vector2i(k * fw, r * fh))
	return im


## Local (u forward, v right, h up) in metres -> cell px, for facing k (world angle k * 45 deg) about pivot pv.
static func _p(k: int, pv: Vector2, u: float, v: float, hh: float) -> Vector2:
	var a := float(k) * PI / 4.0
	var x := u * cos(a) - v * sin(a)
	var y := u * sin(a) + v * cos(a)
	return pv + Vector2((x - y) * PXM_X, (x + y) * PXM_Y - hh * PXM_H)


## Shaded cuboid centred at (cu, cv), base height h0, size L (along u) x W (along v) x H. rp = 5-tone ramp.
static func _box(im: Image, k: int, pv: Vector2, cu: float, cv: float, h0: float, L: float, W: float, H: float, rp: Array, top_tone: int = 3) -> void:
	var a := float(k) * PI / 4.0
	var fu := Vector2(cos(a), sin(a))
	var fv := Vector2(-sin(a), cos(a))
	var sides := [[fu, [L * 0.5, -W * 0.5], [L * 0.5, W * 0.5]], [-fu, [-L * 0.5, W * 0.5], [-L * 0.5, -W * 0.5]],
		[fv, [L * 0.5, W * 0.5], [-L * 0.5, W * 0.5]], [-fv, [-L * 0.5, -W * 0.5], [L * 0.5, -W * 0.5]]]
	for s in sides:
		var n: Vector2 = s[0]
		if n.dot(Vector2(1, 1)) <= 0.001:
			continue   # faces away from the camera
		var b := n.dot(LIGHT)
		var tone := 2 if b > 0.3 else (1 if b > -0.3 else 0)
		var p0: Array = s[1]
		var p1: Array = s[2]
		var poly := PackedVector2Array([_p(k, pv, cu + p0[0], cv + p0[1], h0), _p(k, pv, cu + p1[0], cv + p1[1], h0),
			_p(k, pv, cu + p1[0], cv + p1[1], h0 + H), _p(k, pv, cu + p0[0], cv + p0[1], h0 + H)])
		_fill(im, poly, rp[tone])
	var top := PackedVector2Array([_p(k, pv, cu - L * 0.5, cv - W * 0.5, h0 + H), _p(k, pv, cu + L * 0.5, cv - W * 0.5, h0 + H),
		_p(k, pv, cu + L * 0.5, cv + W * 0.5, h0 + H), _p(k, pv, cu - L * 0.5, cv + W * 0.5, h0 + H)])
	_fill(im, top, rp[top_tone])
	# glint on the lit top edge (upper-left)
	var e0 := _p(k, pv, cu - L * 0.5, cv - W * 0.5, h0 + H)
	_px(im, e0, rp[4])


static func _fill(im: Image, poly: PackedVector2Array, c: Color) -> void:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	for y in range(maxi(0, floori(lo.y)), mini(im.get_height(), ceili(hi.y) + 1)):
		for x in range(maxi(0, floori(lo.x)), mini(im.get_width(), ceili(hi.x) + 1)):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
				im.set_pixel(x, y, c)


static func _px(im: Image, p: Vector2, c: Color) -> void:
	var x := floori(p.x)
	var y := floori(p.y)
	if x >= 0 and y >= 0 and x < im.get_width() and y < im.get_height():
		im.set_pixel(x, y, c)


static func _outline(im: Image) -> void:
	var src: Image = im.duplicate()
	for y in im.get_height():
		for x in im.get_width():
			if src.get_pixel(x, y).a > 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < im.get_width() and q.y < im.get_height() and src.get_pixel(q.x, q.y).a > 0.5:
					im.set_pixel(x, y, OUTLINE)
					break


## Ground shadow ellipse-ish (drawn first, under the object).
static func _shadow(im: Image, k: int, pv: Vector2, L: float, W: float) -> void:
	var poly := PackedVector2Array([_p(k, pv, -L * 0.5 - 0.1, -W * 0.5 + 0.15, 0.0), _p(k, pv, L * 0.5 + 0.2, -W * 0.5 + 0.15, 0.0),
		_p(k, pv, L * 0.5 + 0.2, W * 0.5 + 0.3, 0.0), _p(k, pv, -L * 0.5 - 0.1, W * 0.5 + 0.3, 0.0)])
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	for y in range(maxi(0, floori(lo.y)), mini(im.get_height(), ceili(hi.y) + 1)):
		for x in range(maxi(0, floori(lo.x)), mini(im.get_width(), ceili(hi.x) + 1)):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly) and im.get_pixel(x, y).a < 0.1:
				im.set_pixel(x, y, Color(0, 0, 0, 0.32))


# ================================================================ props
## Litter carried at hand height (0.85 m): poles, canvas bed, casualty in a suit under a foil blanket, field dressing.
static func _stretcher(im: Image, k: int, row: int) -> void:
	var pv := Vector2(24, 22)
	_shadow(im, k, pv, 2.1, 0.6)
	var h := 0.85
	for v in [-0.29, 0.29]:
		_box(im, k, pv, 0.0, v, h, 2.30, 0.06, 0.05, STEEL)            # poles with handles past the bed
	_box(im, k, pv, 0.0, 0.0, h + 0.02, 1.95, 0.56, 0.04, CANVAS)       # canvas bed
	if row == 1:
		_box(im, k, pv, -0.85, 0.0, h + 0.06, 0.22, 0.50, 0.03, CANVAS, 2)   # folded strap roll
		return
	_box(im, k, pv, -0.20, 0.0, h + 0.06, 1.25, 0.44, 0.20, FOIL)        # foil blanket over legs + torso
	_box(im, k, pv, 0.58, 0.0, h + 0.06, 0.40, 0.40, 0.17, SUIT)         # shoulders / chest strap
	_box(im, k, pv, 0.86, 0.0, h + 0.07, 0.24, 0.24, 0.20, SUIT, 4)      # helmeted head (visor glint)
	_px(im, _p(k, pv, 0.62, -0.05, h + 0.24), Color(0.92, 0.92, 0.88))   # field dressing
	_px(im, _p(k, pv, 0.62, 0.05, h + 0.24), Color(0.92, 0.92, 0.88))
	_px(im, _p(k, pv, 0.62, 0.0, h + 0.25), Color(0.72, 0.10, 0.08))
	for s in [-0.6, 0.2]:   # restraint straps
		_px(im, _p(k, pv, s, 0.0, h + 0.27), Color(0.10, 0.10, 0.10))


## Electric ammo tug + flatbed trailer. row 0: rocket-pod reload pack + special-round crates; 1: pod gone; 2: empty.
static func _cart(im: Image, k: int, row: int) -> void:
	var pv := Vector2(36, 34)
	_shadow(im, k, pv, 4.3, 1.3)
	var parts := []   # [depth key, callable]
	# trailer behind the tug: bed centre u -1.05; tug centre u +1.25
	for wu in [-1.75, -0.45, 0.75, 1.75]:
		for wv in [-0.55, 0.55]:
			parts.append([_dk(k, wu, wv, 0.0), [wu, wv, 0.0, 0.45, 0.18, 0.40, RUBBER, 2]])
	parts.append([_dk(k, -1.05, 0.0, 0.30), [-1.05, 0.0, 0.30, 2.10, 1.20, 0.14, STEEL, 3]])     # trailer bed
	parts.append([_dk(k, 0.15, 0.0, 0.32), [0.15, 0.0, 0.32, 0.30, 0.08, 0.06, STEEL, 2]])        # tow bar
	parts.append([_dk(k, 1.25, 0.0, 0.25), [1.25, 0.0, 0.25, 1.30, 1.10, 0.55, TUG, 3]])          # tug body (hi-vis)
	parts.append([_dk(k, 1.00, 0.0, 0.80), [1.00, 0.0, 0.80, 0.30, 0.80, 0.42, CANVAS, 3]])       # seat back
	parts.append([_dk(k, 1.62, 0.0, 0.80), [1.62, 0.0, 0.80, 0.18, 0.95, 0.30, STEEL, 3]])        # dash / bumper bar
	parts.append([_dk(k, 1.25, -0.45, 0.80), [1.25, -0.45, 0.80, 0.06, 0.06, 0.95, STEEL, 3]])    # roll bar posts
	parts.append([_dk(k, 1.25, 0.45, 0.80), [1.25, 0.45, 0.80, 0.06, 0.06, 0.95, STEEL, 3]])
	parts.append([_dk(k, 1.25, 0.0, 1.75), [1.25, 0.0, 1.75, 0.70, 1.00, 0.06, STEEL, 3]])        # roll-bar canopy
	if row == 0:
		parts.append([_dk(k, -1.30, 0.0, 0.44), [-1.30, 0.0, 0.44, 1.45, 0.62, 0.42, STEEL, 3]])   # rocket-pod reload pack
	if row <= 1:
		parts.append([_dk(k, -0.35, -0.30, 0.44), [-0.35, -0.30, 0.44, 0.55, 0.50, 0.40, OD, 3]])  # special-round crates
		parts.append([_dk(k, -0.35, 0.30, 0.44), [-0.35, 0.30, 0.44, 0.55, 0.50, 0.40, OD, 3]])
	parts.sort_custom(func(a, b): return a[0] < b[0])
	for p in parts:
		var q: Array = p[1]
		_box(im, k, pv, q[0], q[1], q[2], q[3], q[4], q[5], q[6], q[7])
	# details: amber beacon on the canopy, crate bands, tube mouths on the pod pack's rear face
	_px(im, _p(k, pv, 1.25, 0.0, 1.85), Color(1.0, 0.62, 0.10))
	if row <= 1:
		for cv in [-0.30, 0.30]:
			_px(im, _p(k, pv, -0.35, cv, 0.86), BAND)
			_px(im, _p(k, pv, -0.30, cv, 0.86), BAND)
	if row == 0:
		_tubes(im, k, pv, -1.30, 0.0, 0.44, 1.45, 0.62, 0.42)
	# driver (helmet + shoulders) on the seat
	_box(im, k, pv, 1.22, 0.0, 0.85, 0.30, 0.40, 0.38, SUIT)
	_box(im, k, pv, 1.25, 0.0, 1.23, 0.22, 0.22, 0.22, SUIT, 4)


## Depth key for painter's order inside one sprite (screen y of the part's base centre, height breaks ties).
static func _dk(k: int, u: float, v: float, hh: float) -> float:
	var a := float(k) * PI / 4.0
	var x := u * cos(a) - v * sin(a)
	var y := u * sin(a) + v * cos(a)
	return (x + y) * 10.0 + hh


## 2 x 3 tube mouths on whichever end face of the pack faces the camera.
static func _tubes(im: Image, k: int, pv: Vector2, cu: float, cv: float, h0: float, L: float, W: float, H: float) -> void:
	var a := float(k) * PI / 4.0
	var fu := Vector2(cos(a), sin(a))
	var end := L * 0.5 if fu.dot(Vector2(1, 1)) > 0.0 else -L * 0.5
	if absf(fu.dot(Vector2(1, 1))) < 0.2:
		return   # end faces edge-on
	for r in 2:
		for c in 3:
			var v := cv + (float(c) - 1.0) * W * 0.3
			var hh := h0 + H * (0.3 + 0.4 * float(r))
			_px(im, _p(k, pv, cu + end, v, hh), Color(0.04, 0.04, 0.05))


static func _podpack_only(im: Image, k: int) -> void:
	var pv := Vector2(16, 18)
	_box(im, k, pv, 0.0, 0.0, 0.0, 1.45, 0.62, 0.42, STEEL)
	for s in [-0.45, 0.45]:   # lifting straps
		_px(im, _p(k, pv, s, 0.0, 0.43), BAND)
	_tubes(im, k, pv, 0.0, 0.0, 0.0, 1.45, 0.62, 0.42)


static func _crate_only(im: Image, k: int) -> void:
	var pv := Vector2(8, 11)
	_box(im, k, pv, 0.0, 0.0, 0.0, 0.55, 0.45, 0.40, OD)
	_px(im, _p(k, pv, 0.0, 0.0, 0.41), BAND)
	_px(im, _p(k, pv, 0.05, 0.0, 0.41), BAND)
