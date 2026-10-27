extends SceneTree
## G7 (FISSURE7) creep growths, drawn in the Machine's CURRENT style (faction_m_lib palette: graphite hulls, pale
## panels, dark joints, cyan seams and sensor glow). Deterministic: re-running writes byte-identical files.
##   godot --headless --path . -s tools/art/g7_growths.gd            # -> assets/art/g7_growths/
## Writes
##   growths.png        scenery atlas: 10 kinds (rows) x 3 sizes x 2 layers (cols: s base, s glow, m base, m glow,
##                      l base, l glow); cell CELL_W x CELL_H, foot at (CELL_W / 2, CELL_H - 4). The glow layer holds
##                      only the emissive pixels (the view pulses it additively).
##   buildings/g7_growth_spire_{built,damaged}.png (+ _mask), buildings/g7_growth_heart_{built,damaged}.png (+ _mask):
##                      the two destructible big growths (Machine buildings), manifest "buildings" section in the
##                      g6_bld schema (fw, fh, pivot, size, states) for the art catalog (CR: add "g7_growths" group).
##   manifest.json      {version, group, tile, kinds, cell, sizes, atlas, buildings, files}
## Prints "G7_GROWTHS files=<n> kinds=<n>".

const L = preload("res://tools/art/faction_m_lib.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")   # ART7B: 32x32 menu icons (C.icon)

const KINDS := ["spire", "lattice", "tendril", "rib_arch", "pod", "antenna", "shard_fan", "coil", "vent", "node_tree"]
const SIZES := [0.5, 0.75, 1.0]
const CELL_W := 48
const CELL_H := 96
const SLICK := Color8(36, 40, 44)
const VIOLET := Color8(120, 90, 170)


func _initialize() -> void:
	var out := "res://assets/art/g7_growths/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out + "buildings"))
	var files := []
	var atlas := Image.create(CELL_W * 6, CELL_H * KINDS.size(), false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	for ki in KINDS.size():
		for si in SIZES.size():
			var base := Image.create(CELL_W, CELL_H, false, Image.FORMAT_RGBA8)
			var glow := Image.create(CELL_W, CELL_H, false, Image.FORMAT_RGBA8)
			base.fill(Color(0, 0, 0, 0))
			glow.fill(Color(0, 0, 0, 0))
			draw_kind(String(KINDS[ki]), base, glow, Vector2(CELL_W / 2.0, CELL_H - 4.0), float(SIZES[si]), ki * 7 + si)
			atlas.blit_rect(base, Rect2i(0, 0, CELL_W, CELL_H), Vector2i(CELL_W * si * 2, CELL_H * ki))
			atlas.blit_rect(glow, Rect2i(0, 0, CELL_W, CELL_H), Vector2i(CELL_W * (si * 2 + 1), CELL_H * ki))
	atlas.save_png(ProjectSettings.globalize_path(out + "growths.png"))
	files.append("growths.png")
	var blds := {}
	var icons := {}
	for spec in [["g7_growth_spire", "spire", 96, 176, 1.75], ["g7_growth_heart", "pod", 112, 128, 2.0]]:
		var states := {}
		for state in ["built", "damaged", "build_0", "build_1", "build_2"]:
			var img := Image.create(int(spec[2]), int(spec[3]), false, Image.FORMAT_RGBA8)
			var gl := Image.create(int(spec[2]), int(spec[3]), false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			gl.fill(Color(0, 0, 0, 0))
			var foot := Vector2(float(spec[2]) / 2.0, float(spec[3]) - 10.0)
			# ART7B: build_<n> = the growth rising out of the ground (35 / 60 / 85 % of full size)
			var gk := {"build_0": 0.35, "build_1": 0.6, "build_2": 0.85}.get(state, 1.0) as float
			draw_kind(String(spec[1]), img, gl, foot, float(spec[4]) * gk, 91)
			if state == "damaged":
				_damage(img, gl, 17)
			_merge_glow(img, gl)
			var mask := _mask(img)
			var f := "buildings/%s_%s.png" % [spec[0], state]
			var fm := "buildings/%s_%s_mask.png" % [spec[0], state]
			img.save_png(ProjectSettings.globalize_path(out + f))
			mask.save_png(ProjectSettings.globalize_path(out + fm))
			files.append(f)
			files.append(fm)
			states[state] = {"file": f, "mask": fm}
		var io := {"images": {}, "manifest": {}}
		var bi := Image.load_from_file(ProjectSettings.globalize_path(out + String(states.built.file)))
		C.icon(io, String(spec[0]), bi, bi.get_width(), bi.get_height(), 0)
		var fi := "icons/%s.png" % spec[0]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out + "icons"))
		(io.images[fi] as Image).save_png(ProjectSettings.globalize_path(out + fi))
		files.append(fi)
		icons[spec[0]] = fi
		blds[spec[0]] = {"fw": int(spec[2]), "fh": int(spec[3]), "pivot": [int(spec[2]) / 2, int(spec[3]) - 10],
			"size": 1, "states": states, "g7": {"class": "building", "sample": "growth", "kind": spec[1]}}
	var man := {"version": 1, "group": "g7_growths", "tile": [64, 32], "kinds": KINDS, "cell": [CELL_W, CELL_H],
		"foot": [CELL_W / 2, CELL_H - 4], "sizes": SIZES, "atlas": "growths.png",
		"atlas_layout": "row = kind, col = size * 2 + layer (0 base, 1 glow)", "buildings": blds, "icons": icons, "files": files}
	var fh := FileAccess.open(ProjectSettings.globalize_path(out + "manifest.json"), FileAccess.WRITE)
	fh.store_string(JSON.stringify(man, " ", true))
	fh.close()
	print("G7_GROWTHS files=%d kinds=%d" % [files.size() + 1, KINDS.size()])
	quit(0)


# ================================================================ primitives
static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if c.a >= 0.999:
		img.set_pixel(x, y, c)
	else:
		var d := img.get_pixel(x, y)
		var a := c.a + d.a * (1.0 - c.a)
		if a <= 0.0:
			return
		img.set_pixel(x, y, Color((c.r * c.a + d.r * d.a * (1.0 - c.a)) / a, (c.g * c.a + d.g * d.a * (1.0 - c.a)) / a,
			(c.b * c.a + d.b * d.a * (1.0 - c.a)) / a, a))


static func _hn(a: int, b: int) -> float:
	var x := (a * 374761393 + b * 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return float(x % 1000) / 1000.0


## Tapered column from foot upward: lit left face (panel), dark right face (graphite), joint outline, cyan seam.
static func _column(img: Image, glow: Image, foot: Vector2, h: float, w0: float, w1: float, lean: float, seam: bool,
		sd: int) -> Vector2:
	var top := foot
	for t in int(h):
		var f := float(t) / maxf(h, 1.0)
		var hw := lerpf(w0, w1, f)
		var cx := foot.x + lean * f * h
		var y := int(foot.y) - t
		for xi in range(int(floor(cx - hw)), int(ceil(cx + hw)) + 1):
			var u := (float(xi) - cx) / maxf(hw, 0.5)
			var col: Color
			if absf(u) > 0.82:
				col = L.JOINT
			elif u < -0.25:
				col = L.PANEL if _hn(xi, y + sd) > 0.18 else L.PANEL_D
			elif u < 0.2:
				col = L.SLAB
			else:
				col = L.GRAPH if _hn(xi + 3, y) > 0.3 else L.GRAPH_D
			if (y + sd) % 9 == 0 and absf(u) < 0.82:
				col = L.JOINT
			_px(img, xi, y, col)
		if seam and absf(cx - floor(cx)) < 2.0 and (y + sd) % 5 != 0:
			_px(glow, int(round(cx + 0.3 * hw)), y, Color(L.CYAN, 0.95))
		top = Vector2(cx, y)
	return top


static func _blob(img: Image, c: Vector2, rx: float, ry: float, lit: Color, dark: Color, outline: bool = true) -> void:
	for y in range(int(c.y - ry) - 1, int(c.y + ry) + 2):
		for x in range(int(c.x - rx) - 1, int(c.x + rx) + 2):
			var dx := (float(x) - c.x) / maxf(rx, 0.5)
			var dy := (float(y) - c.y) / maxf(ry, 0.5)
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			var col := lit.lerp(dark, clampf(0.5 + 0.6 * (dx + dy * 0.6), 0.0, 1.0))
			if outline and d > 0.72:
				col = L.JOINT
			_px(img, x, y, col)


static func _line(img: Image, a: Vector2, b: Vector2, col: Color, th: float = 1.0) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		if th <= 1.0:
			_px(img, int(round(p.x)), int(round(p.y)), col)
		else:
			for oy in range(-int(th / 2.0), int(th / 2.0) + 1):
				for ox in range(-int(th / 2.0), int(th / 2.0) + 1):
					_px(img, int(round(p.x)) + ox, int(round(p.y)) + oy, col)


static func _glowdot(glow: Image, p: Vector2, r: float) -> void:
	for y in range(int(p.y - r - 1), int(p.y + r + 2)):
		for x in range(int(p.x - r - 1), int(p.x + r + 2)):
			var d := Vector2(x, y).distance_to(p)
			if d <= r + 0.5:
				_px(glow, x, y, L.CYAN_HOT if d < r * 0.5 else Color(L.CYAN, clampf(1.2 - d / (r + 1.0), 0.3, 1.0)))


static func _mound(img: Image, foot: Vector2, k: float) -> void:
	_blob(img, foot + Vector2(0, -1), 10.0 * k + 3.0, 3.5 * k + 1.5, Color(SLICK, 0.95), Color(L.JOINT, 0.95), false)


# ================================================================ kinds
static func draw_kind(kind: String, img: Image, glow: Image, foot: Vector2, k: float, sd: int) -> void:
	_mound(img, foot, k)
	match kind:
		"spire":
			var top := _column(img, glow, foot, 80.0 * k, 6.0 * k + 1.0, 0.6, 0.06, true, sd)
			_column(img, glow, foot + Vector2(-6.0 * k, 0), 34.0 * k, 3.0 * k + 0.8, 0.5, -0.25, false, sd + 3)
			_column(img, glow, foot + Vector2(5.0 * k, 0), 26.0 * k, 2.5 * k + 0.8, 0.5, 0.3, true, sd + 5)
			_glowdot(glow, top + Vector2(0, -1), 1.5 * k + 0.6)
		"lattice":
			for i in 5:
				var a := -1.2 + 0.6 * float(i) + (_hn(i, sd) - 0.5) * 0.3
				var h := (30.0 + 30.0 * _hn(i + 9, sd)) * k
				var b := foot + Vector2((float(i) - 2.0) * 3.0 * k, 0)
				var t := b + Vector2(sin(a) * h * 0.5, -cos(a * 0.4) * h)
				for s in range(-int(2.0 * k + 1.0), int(2.0 * k + 1.0) + 1):
					_line(img, b + Vector2(s, 0), t, L.PANEL if s < 0 else Color(L.TEAL, 0.95))
				_line(glow, b, t, Color(L.CYAN, 0.7))
				_glowdot(glow, t, 0.8 * k + 0.4)
		"tendril":
			for i in 3:
				var prev := foot + Vector2((float(i) - 1.0) * 4.0 * k, 0)
				var h := (50.0 + 20.0 * float(i % 2)) * k
				var ph := _hn(i, sd) * TAU
				for t in range(1, 24):
					var f := float(t) / 23.0
					var p := foot + Vector2((float(i) - 1.0) * 4.0 * k + sin(f * 4.0 + ph) * 6.0 * k * f, -f * h)
					_line(img, prev, p, L.GRAPH if f < 0.7 else L.GRAPH_D, maxf(3.0 * k * (1.0 - f) + 1.0, 1.0))
					if t % 6 == 0:
						_blob(img, p, 1.6 * k + 0.6, 1.6 * k + 0.6, L.JOINT, L.JOINT, false)
					prev = p
				_glowdot(glow, prev, 1.2 * k + 0.5)
		"rib_arch":
			for j in 4:
				var off := (float(j) - 1.5) * 3.0 * k
				var prev := Vector2.ZERO
				for t in 25:
					var a := PI * float(t) / 24.0
					var p := foot + Vector2(-cos(a) * 18.0 * k + off * 0.4, -sin(a) * (44.0 + 6.0 * float(j)) * k + off)
					if t > 0:
						_line(img, prev, p, L.PANEL if j < 2 else L.GRAPH, maxf(2.0 * k, 1.0))
					prev = p
				_glowdot(glow, foot + Vector2(0, -(44.0 + 6.0 * float(j)) * k + off), 0.7 * k + 0.3)
			_column(img, glow, foot + Vector2(-18.0 * k, 0), 10.0 * k, 3.0 * k, 2.0 * k, 0.0, false, sd)
			_column(img, glow, foot + Vector2(18.0 * k, 0), 10.0 * k, 3.0 * k, 2.0 * k, 0.0, false, sd + 1)
		"pod":
			var pods := [Vector2(-7, -9), Vector2(6, -11), Vector2(0, -21), Vector2(-3, -33), Vector2(9, -26)]
			for i in pods.size():
				var c: Vector2 = foot + pods[i] * k
				var r := (7.0 - float(i) * 0.6) * k + 1.0
				_blob(img, c, r, r * 1.2, Color8(70, 66, 92), Color8(28, 26, 36))
				_glowdot(glow, c + Vector2(-0.3 * r, -0.2 * r), r * 0.45)
		"antenna":
			var top := _column(img, glow, foot, 70.0 * k, 2.0 * k + 0.6, 0.6, 0.0, false, sd)
			for j in 3:
				var y := foot.y - (24.0 + 16.0 * float(j)) * k
				var hw := (11.0 - 3.0 * float(j)) * k
				_line(img, Vector2(foot.x - hw, y), Vector2(foot.x + hw, y + 2.0 * k), L.PANEL_D, maxf(k, 1.0))
				_px(glow, int(foot.x - hw), int(y), L.CYAN_HOT)
				_px(glow, int(foot.x + hw), int(y + 2.0 * k), L.CYAN_HOT)
			_blob(img, Vector2(foot.x + 6.0 * k, foot.y - 50.0 * k), 5.0 * k + 1.0, 2.5 * k + 1.0, L.PANEL, L.GRAPH)
			_glowdot(glow, top + Vector2(0, -1), 1.2 * k + 0.6)
		"shard_fan":
			for i in 7:
				var a := -0.9 + 0.3 * float(i)
				var h := (36.0 + 22.0 * (1.0 - absf(float(i) - 3.0) / 3.0)) * k
				var t := foot + Vector2(sin(a) * h * 0.6, -cos(a) * h)
				for s in range(-int(1.5 * k + 1.0), int(1.5 * k + 1.0) + 1):
					_line(img, foot + Vector2(s, 0), t, L.PANEL if (i + s) % 3 == 0 else L.SLAB)
				_line(img, foot, t, L.JOINT)
				_line(glow, foot.lerp(t, 0.5), t, Color(L.CYAN, 0.8))
		"coil":
			var h := 64.0 * k
			for t in int(h):
				var y := int(foot.y) - t
				var hw := 5.0 * k + 1.0
				for xi in range(int(foot.x - hw), int(foot.x + hw) + 1):
					var band := int(float(t) * 0.5 + (float(xi) - foot.x) * 0.8) % 4
					_px(img, xi, y, L.JOINT if absf(float(xi) - foot.x) >= hw - 0.5 else (L.PANEL if band == 0 else (L.GRAPH if band < 3 else L.GRAPH_D)))
				var hx := foot.x + sin(float(t) * 0.35) * (hw + 1.0)
				_px(img, int(hx), y, L.RAW)
				if t % 12 == 0:
					_line(glow, Vector2(foot.x - hw, y), Vector2(foot.x + hw, y), Color(L.CYAN, 0.9))
			_glowdot(glow, Vector2(foot.x, foot.y - h - 1.0), 2.0 * k + 0.5)
		"vent":
			_column(img, glow, foot, 30.0 * k, 9.0 * k + 1.0, 6.0 * k + 1.0, 0.0, false, sd)
			_blob(img, Vector2(foot.x, foot.y - 30.0 * k), 6.0 * k + 1.0, 2.5 * k + 1.0, L.JOINT, L.JOINT, false)
			for j in 5:
				var p := Vector2(foot.x + (_hn(j, sd) - 0.5) * 8.0 * k, foot.y - (32.0 + 7.0 * float(j)) * k)
				_blob(glow, p, (2.0 + float(j)) * k + 0.5, (1.5 + float(j) * 0.6) * k + 0.5, Color(VIOLET, 0.55 - 0.08 * j), Color(L.CYAN, 0.4 - 0.06 * j), false)
		"node_tree":
			_tree(img, glow, foot, -PI / 2.0, 21.0 * k, 3.0 * k + 1.0, 3, sd)


static func _tree(img: Image, glow: Image, p: Vector2, a: float, len: float, th: float, depth: int, sd: int) -> void:
	var q := p + Vector2(cos(a), sin(a)) * len
	_line(img, p, q, L.GRAPH if depth % 2 == 1 else L.PANEL_D, maxf(th, 1.0))
	if depth <= 0:
		_glowdot(glow, q, 1.2)
		return
	_blob(img, q, th * 0.8 + 0.6, th * 0.8 + 0.6, L.JOINT, L.JOINT, false)
	_px(glow, int(q.x), int(q.y), L.CYAN_HOT)
	var spread := 0.32 + 0.14 * _hn(depth, sd)
	_tree(img, glow, q, a - spread, len * 0.68, th * 0.7, depth - 1, sd + 1)
	_tree(img, glow, q, a + spread, len * 0.68, th * 0.7, depth - 1, sd + 2)


# ================================================================ building helpers
static func _damage(img: Image, glow: Image, sd: int) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				var f := 0.62 if _hn(x / 3, y / 3 + sd) > 0.25 else 0.4
				img.set_pixel(x, y, Color(c.r * f, c.g * f, c.b * f, c.a))
			var g := glow.get_pixel(x, y)
			if g.a > 0.0 and _hn(x, y + sd) > 0.4:
				glow.set_pixel(x, y, Color(0, 0, 0, 0))


static func _merge_glow(img: Image, glow: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var g := glow.get_pixel(x, y)
			if g.a > 0.0:
				_px(img, x, y, g)


## Team mask: the pale panel pixels (trim), white where the team colour shows.
static func _mask(img: Image) -> Image:
	var m := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	m.fill(Color(0, 0, 0, 0))
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and c.is_equal_approx(L.PANEL_D) and (x + y) % 2 == 0:
				m.set_pixel(x, y, Color(1, 1, 1, 1))
	return m
