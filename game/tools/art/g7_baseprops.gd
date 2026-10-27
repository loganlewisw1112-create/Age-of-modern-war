extends SceneTree
## G7 BASE7 (13.9b): base props art - the security camera mast (a real building def, a_g7_camera: built + 3 build
## stages, team-colour mask) and the display-only light props baseprops_layer draws (street light, floodlight mast,
## warm / cold glow, pad light). Upgraded pixel art at the G7 detail level: hard 1-px outline, 3-tone lit-from-the-
## top-left volumes, 64x32 iso tile. Deterministic: re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g7_baseprops.gd                 # writes assets/art/g7_baseprops/
##   godot --headless --path . -s tools/art/g7_baseprops.gd -- --out=<abs dir>
## Prints "G7_BASEPROPS files=<n>".
const GEN = preload("res://tools/gen_art.gd")
const GROUP := "g7_baseprops"
const OUTLINE := Color(0.07, 0.08, 0.09, 1.0)
const STEEL := [Color(0.62, 0.65, 0.68), Color(0.45, 0.48, 0.52), Color(0.30, 0.32, 0.35)]
const CONC := [Color(0.70, 0.69, 0.65), Color(0.56, 0.55, 0.52), Color(0.40, 0.40, 0.38)]
const GLASS := Color(0.12, 0.16, 0.22)
const LENS := Color(0.55, 0.85, 1.0)


func _init() -> void:
	var dir := "res://assets/art/%s" % GROUP
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			dir = String(a).substr(6)
	var out := build()
	var n := GEN.save(out, dir)
	print("G7_BASEPROPS files=%d" % n)
	quit()


static func _img(w: int, h: int) -> Image:
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	return im


static func _rect(im: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(maxi(y0, 0), mini(y0 + h, im.get_height())):
		for x in range(maxi(x0, 0), mini(x0 + w, im.get_width())):
			im.set_pixel(x, y, c)


## Vertical cylinder-ish column: 3 tones left -> right.
static func _column(im: Image, cx: int, y0: int, y1: int, w: int, rp: Array) -> void:
	for y in range(y0, y1):
		for x in range(cx - w / 2, cx - w / 2 + w):
			var t := float(x - (cx - w / 2)) / float(maxi(w - 1, 1))
			im.set_pixel(x, y, rp[0] if t < 0.34 else (rp[1] if t < 0.67 else rp[2]))


## Flat iso diamond (footprint plate) centred at (cx, cy), half-width hw (half-height hw / 2).
static func _diamond(im: Image, cx: int, cy: int, hw: int, top: Color, edge: Color) -> void:
	for y in range(-hw / 2, hw / 2 + 1):
		var span := hw - absi(y) * 2
		for x in range(-span, span + 1):
			var px := cx + x
			var py := cy + y
			if px >= 0 and py >= 0 and px < im.get_width() and py < im.get_height():
				im.set_pixel(px, py, edge if absi(x) >= span - 1 or absi(y) == hw / 2 else top)


static func _outline(im: Image) -> void:
	var w := im.get_width()
	var h := im.get_height()
	var src := im.duplicate()
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and src.get_pixel(q.x, q.y).a > 0.5:
					im.set_pixel(x, y, OUTLINE)
					break


## The camera mast at construction progress p (0..3: 3 = built). Returns [image, mask].
static func _camera(stage: int) -> Array:
	var w := 64
	var h := 96
	var im := _img(w, h)
	var mk := _img(w, h)
	var cx := 32
	var gy := 80   # ground point (tile centre) in the frame
	_diamond(im, cx, gy, 14, CONC[1], CONC[2])            # concrete footing plate
	_rect(im, cx - 5, gy - 6, 10, 6, CONC[0])
	_rect(im, cx + 1, gy - 6, 4, 6, CONC[2])
	var top: int = gy - int([14, 30, 48, 62][clampi(stage, 0, 3)])
	_column(im, cx, top, gy - 6, 4, STEEL)               # mast
	if stage >= 1:
		_rect(im, cx - 3, gy - 22, 6, 3, STEEL[1])          # junction box (team colour band)
		_rect(mk, cx - 3, gy - 22, 6, 3, Color.WHITE)
		_rect(im, cx - 3, gy - 22, 6, 3, Color(0.75, 0.75, 0.75))
	if stage >= 3:
		# pan-tilt head on a short arm, lens toward the viewer's right (rotation is shown by the layer's sweep)
		_rect(im, cx - 1, top - 2, 9, 2, STEEL[1])
		_rect(im, cx + 3, top - 9, 13, 7, STEEL[0])
		_rect(im, cx + 3, top - 4, 13, 2, STEEL[2])
		_rect(im, cx + 14, top - 8, 3, 5, GLASS)
		im.set_pixel(cx + 15, top - 7, LENS)
		_rect(im, cx + 2, top - 11, 15, 2, STEEL[2])         # sun hood
		_rect(im, cx - 2, top - 16, 1, 8, STEEL[2])          # antenna
		im.set_pixel(cx - 2, top - 17, Color(1.0, 0.25, 0.2))  # status lamp
		_rect(im, cx - 4, top + 6, 3, 10, Color(0.2, 0.2, 0.22))  # IR illuminator
		_rect(mk, cx + 3, top - 9, 13, 2, Color.WHITE)
		_rect(im, cx + 3, top - 9, 13, 2, Color(0.8, 0.8, 0.8))
	elif stage == 2:
		_rect(im, cx - 6, top, 12, 2, Color(0.75, 0.62, 0.2))  # scaffold collar
	_outline(im)
	return [im, mk]


static func _street_light() -> Image:
	var im := _img(24, 56)
	_rect(im, 10, 52, 5, 3, CONC[1])
	_column(im, 12, 10, 52, 2, STEEL)
	_rect(im, 12, 8, 9, 2, STEEL[1])
	_rect(im, 16, 10, 6, 2, Color(0.25, 0.25, 0.27))
	_rect(im, 17, 12, 4, 1, Color(1.0, 0.92, 0.7))
	_outline(im)
	return im


static func _flood_mast() -> Image:
	var im := _img(32, 72)
	_rect(im, 12, 66, 8, 4, CONC[1])
	_column(im, 16, 14, 66, 3, STEEL)
	_rect(im, 7, 12, 18, 2, STEEL[2])
	for i in 3:
		var x := 7 + i * 6
		_rect(im, x, 6, 5, 6, Color(0.22, 0.23, 0.25))
		_rect(im, x + 1, 7, 3, 3, Color(0.95, 0.97, 1.0))
	_outline(im)
	return im


## Soft light pool on the ground (iso ellipse, 2:1), additive in the layer. warm = sodium street light.
static func _glow(w: int, warm: bool) -> Image:
	var h := w / 2
	var im := _img(w, h)
	var c := Color(1.0, 0.78, 0.45) if warm else Color(0.82, 0.9, 1.0)
	for y in h:
		for x in w:
			var dx := (float(x) + 0.5 - w * 0.5) / (w * 0.5)
			var dy := (float(y) + 0.5 - h * 0.5) / (h * 0.5)
			var r := sqrt(dx * dx + dy * dy)
			if r < 1.0:
				var a := pow(1.0 - r, 1.6) * 0.85
				a = floor(a * 6.0) / 6.0   # banded (pixel-art light pools, no smooth gradient)
				im.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return im


static func _pad_light() -> Image:
	var im := _img(8, 8)
	_rect(im, 2, 3, 4, 3, Color(0.3, 0.3, 0.32))
	_rect(im, 3, 2, 2, 2, Color(0.55, 1.0, 0.6))
	return im


static func build() -> Dictionary:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": GROUP, "buildings": {}, "props": {}}}
	var states := {}
	for st in [["build_0", 0], ["build_1", 1], ["build_2", 2], ["built", 3]]:
		var pair := _camera(int(st[1]))
		var f := "buildings/a_g7_camera_%s.png" % st[0]
		var m := "buildings/a_g7_camera_%s_mask.png" % st[0]
		out.images[f] = pair[0]
		out.images[m] = pair[1]
		states[st[0]] = {"file": f, "mask": m}
	out.manifest.buildings["a_g7_camera"] = {"fw": 64, "fh": 96, "pivot": [32, 80], "size": 1, "states": states}
	var props := {"street_light": [_street_light(), [12, 53]], "flood_mast": [_flood_mast(), [16, 68]],
		"glow_warm": [_glow(96, true), [48, 24]], "glow_cold": [_glow(160, false), [80, 40]], "pad_light": [_pad_light(), [4, 6]]}
	var keys := props.keys()
	keys.sort()
	for k in keys:
		var f := "props/%s.png" % k
		out.images[f] = props[k][0]
		out.manifest.props[k] = {"file": f, "pivot": props[k][1]}
	return out
