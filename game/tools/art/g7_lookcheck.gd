extends SceneTree
## G7 look checkpoint renderer (owner: ARTCN7; feeds Done-when 6). For every DL7 sample in assets/art/g7_*/
## it renders, on real game terrain (assets/generated/terrain grass tiles) at game zoom (1:1):
##   row 1  every facing (units: 8 facings of the first frame; buildings: rot_0..3, damaged, build_0..2)
##   row 2  the sample's 10-frame animation strip (manifest g7.anim_strip; units at facing 2, a 3/4 front view)
## team-tinted (player blue for human samples, enemy red for Machine), with a pixel-font label.
## Output: .plan/shots/ARTCN7/strip_<id>.png (1x) and strip_<id>_2x.png, plus contact_sheet.png (all samples,
## 1x game zoom) and contact_sheet_2x_<n>.png pages for close inspection, and contact_index.json.
##   godot --headless --path . -s tools/art/g7_lookcheck.gd [-- --out=<abs dir>]
const H = preload("res://tools/art/g6_lib.gd")
const GROUPS := ["g7_cn", "g7_turrets", "g7_threats"]
const PAD := 6
const LABEL_H := 9
const MAXW := 2300
const FONT := {"A": 0x7B6F, "B": 0x6BAE, "C": 0x7927, "D": 0x6B6E, "E": 0x79A7, "F": 0x79A4, "G": 0x796F,
	"H": 0x5BED, "I": 0x7497, "J": 0x126F, "K": 0x5BAD, "L": 0x4927, "M": 0x5FED, "N": 0x6B6D, "O": 0x7B6F,
	"P": 0x7BE4, "Q": 0x7B79, "R": 0x7BAD, "S": 0x79CF, "T": 0x7492, "U": 0x5B6F, "V": 0x5B6A, "W": 0x5BFD,
	"X": 0x5AAD, "Y": 0x5A92, "Z": 0x72A7, "0": 0x7B6F, "1": 0x2C97, "2": 0x73E7, "3": 0x73CF, "4": 0x5BC9,
	"5": 0x79CF, "6": 0x79EF, "7": 0x7249, "8": 0x7BEF, "9": 0x7BCF, "_": 0x0007, "-": 0x01C0, " ": 0}

var _tiles: Array = []


func _init() -> void:
	var out := ProjectSettings.globalize_path("res://.plan/shots/ARTCN7")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	for i in 4:
		var t := Image.load_from_file(ProjectSettings.globalize_path("res://assets/generated/terrain/grass_%d.png" % i))
		t.convert(Image.FORMAT_RGBA8)
		_tiles.append(t)
	var strips: Array = []
	var index: Array = []
	for g in GROUPS:
		var base := "res://assets/art/%s/" % g
		var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "manifest.json"))
		var ids: Array = (man.g7_samples as Dictionary).keys()
		ids.sort()
		for id in ids:
			var s: Dictionary = man.g7_samples[id]
			var img := _strip(base, man, String(id), s)
			img.save_png(out.path_join("strip_%s.png" % id))
			var big := img.duplicate() as Image
			big.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
			big.save_png(out.path_join("strip_%s_2x.png" % id))
			strips.append([id, img])
	var sheet := _pack(strips, index)
	sheet.save_png(out.path_join("contact_sheet.png"))
	var pages := _pages_2x(strips, out)
	var f := FileAccess.open(out.path_join("contact_index.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"samples": index, "pages_2x": pages}, "  ", false))
	f.close()
	print("G7_LOOKCHECK samples=%d contact=%s pages_2x=%d" % [strips.size(), out.path_join("contact_sheet.png"), pages.size()])
	quit(0)


func _terrain(w: int, h: int) -> Image:
	var bg := Image.create(w, h, false, Image.FORMAT_RGBA8)
	bg.fill(Color8(70, 84, 52))
	for ty in range(-1, h / 16 + 2):
		for tx in range(-1, w / 64 + 2):
			var t: Image = _tiles[(tx * 7 + ty * 13 + (tx * ty) % 5 + 40) % 4]
			bg.blend_rect(t, Rect2i(0, 0, t.get_width(), t.get_height()), Vector2i(tx * 64 + (ty % 2) * 32 - 32, ty * 16 - 16))
	return bg


func _load(base: String, rel: String) -> Image:
	var im := Image.load_from_file(ProjectSettings.globalize_path(base + rel))
	im.convert(Image.FORMAT_RGBA8)
	return im


func _team(id: String) -> Color:
	return H.ENEMY if id.begins_with("g7_m_") else H.TEAM


## Cells for one sample: [row1 cells, row2 cells] (Images, same size).
func _cells(base: String, man: Dictionary, id: String, s: Dictionary) -> Array:
	var col := _team(id)
	var r1: Array = []
	var r2: Array = []
	if String(s.section) == "buildings":
		var e: Dictionary = man.buildings[id]
		for st in ["rot_0", "rot_1", "rot_2", "rot_3", "rot_0_damaged", "rot_0_build_0", "rot_0_build_1", "rot_0_build_2"]:
			r1.append(_bimg(base, e, st, col))
		for st in s.get("anim_strip", s.get("key_frames", ["built"])):
			r2.append(_bimg(base, e, String(st), col))
	else:
		var e: Dictionary = man[s.section][id]
		var sheet := H.tint(_load(base, e.file), _load(base, e.mask), col)
		var fr: Array = e.frames
		var fw := int(e.fw)
		var fh := int(e.fh)
		for k in 8:
			r1.append(H.frame(sheet, fw, fh, 0, k))
		for n in s.get("anim_strip", fr):
			r2.append(H.frame(sheet, fw, fh, maxi(0, fr.find(String(n))), 2))
	while r2.size() < 10:
		r2.append(r2[r2.size() % maxi(1, r2.size())])
	return [r1, r2.slice(0, 10)]


func _bimg(base: String, e: Dictionary, st: String, col: Color) -> Image:
	var d: Dictionary = e.states.get(st, e.states.built)
	return H.tint(_load(base, d.file), _load(base, d.mask), col)


func _strip(base: String, man: Dictionary, id: String, s: Dictionary) -> Image:
	var rows := _cells(base, man, id, s)
	var cw: int = (rows[0][0] as Image).get_width()
	var ch: int = (rows[0][0] as Image).get_height()
	var w := maxi(rows[0].size(), rows[1].size()) * (cw + 2) + PAD * 2
	var h := LABEL_H + (ch + 2) * 2 + PAD * 2
	var img := _terrain(w, h)
	for r in 2:
		for i in rows[r].size():
			var c: Image = rows[r][i]
			img.blend_rect(c, Rect2i(0, 0, c.get_width(), c.get_height()), Vector2i(PAD + i * (cw + 2), LABEL_H + PAD + r * (ch + 2)))
	img.fill_rect(Rect2i(0, 0, w, LABEL_H), Color(0, 0, 0, 0.75))
	_text(img, 3, 2, "%s  %s" % [id.to_upper(), String(s.get("role", s.get("sample", ""))).to_upper()])
	return img


func _text(img: Image, x: int, y: int, t: String) -> void:
	var cx := x
	for ch in t:
		var bits: int = FONT.get(ch, FONT.get(ch.to_upper(), 0))
		for i in 15:
			if bits & (1 << (14 - i)):
				var px := cx + i % 3
				var py := y + i / 3
				if px < img.get_width() and py < img.get_height():
					img.set_pixel(px, py, Color8(236, 232, 214))
		cx += 4


## Shelf-pack the 1x strips into one contact sheet.
func _pack(strips: Array, index: Array) -> Image:
	var x := 0
	var y := 0
	var row_h := 0
	var pos: Array = []
	var w := 0
	for s in strips:
		var im: Image = s[1]
		if x > 0 and x + im.get_width() > MAXW:
			x = 0
			y += row_h + 4
			row_h = 0
		pos.append(Vector2i(x, y))
		x += im.get_width() + 4
		row_h = maxi(row_h, im.get_height())
		w = maxi(w, x)
	var sheet := Image.create(w, y + row_h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(20, 22, 20))
	for i in strips.size():
		var im: Image = strips[i][1]
		sheet.blit_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()), pos[i])
		index.append({"id": strips[i][0], "x": pos[i].x, "y": pos[i].y, "w": im.get_width(), "h": im.get_height()})
	return sheet


## 2x pages (about 2300 px tall each) for close inspection.
func _pages_2x(strips: Array, out: String) -> Array:
	var pages: Array = []
	var cur: Array = []
	var hsum := 0
	for s in strips + [null]:
		if s == null or (hsum + (s[1] as Image).get_height() * 2 > 2300 and not cur.is_empty()):
			var w := 0
			for c in cur:
				w = maxi(w, (c[1] as Image).get_width() * 2)
			var pg := Image.create(w, hsum, false, Image.FORMAT_RGBA8)
			pg.fill(Color8(20, 22, 20))
			var y := 0
			for c in cur:
				var b := (c[1] as Image).duplicate() as Image
				b.resize(b.get_width() * 2, b.get_height() * 2, Image.INTERPOLATE_NEAREST)
				pg.blit_rect(b, Rect2i(0, 0, b.get_width(), b.get_height()), Vector2i(0, y))
				y += b.get_height()
			var p := out.path_join("contact_sheet_2x_%d.png" % pages.size())
			pg.save_png(p)
			pages.append(p)
			cur = []
			hsum = 0
		if s != null:
			cur.append(s)
			hsum += (s[1] as Image).get_height() * 2
	return pages
