extends RefCounted
## Self-check crops for the G5 ground-unit art (agent ART-U5): every sheet team-tinted (blue) on a grass
## backdrop, scaled 3x nearest, one PNG per def (+ alive-sheet strips, wrecks, icons) in .plan/shots/ART-U5/.
const FX = preload("res://tools/art/fx_ui.gd")

const BG := Color8(92, 106, 66)
const TEAM := Color(0.31, 0.49, 0.69)
const Z := 3


static func compose(out: Dictionary, dir: String) -> int:
	DirAccess.make_dir_recursive_absolute(dir)
	var n := 0
	for sec in ["infantry", "vehicles"]:
		var man: Dictionary = out.manifest.get(sec, {})
		var defs: Array = man.keys()
		defs.sort()
		for def in defs:
			var e: Dictionary = man[def]
			_save(_tinted(out, String(e.file), String(e.mask)), dir.path_join("%s.png" % def))
			n += 1
			var al: Dictionary = e.get("alive_sheets", {})
			if not al.is_empty():
				var rows: Array = []
				for a in range(1, int(e.squad_size)):
					var s: Dictionary = al[str(a)]
					rows.append(_tinted(out, String(s.file), String(s.mask)).get_region(Rect2i(0, 0, int(e.fw) * 4, int(e.fh) * 2)))
				_save(_stack(rows), dir.path_join("%s_alive.png" % def))
				n += 1
	var wr: Dictionary = out.manifest.get("vehicle_wrecks", {})
	var wd: Array = wr.keys()
	wd.sort()
	var strips: Array = []
	for def in wd:
		var img: Image = out.images[wr[def].file]
		var fw := int(wr[def].fw)
		var fh := int(wr[def].fh)
		var row := Image.create(fw * 8, fh, false, Image.FORMAT_RGBA8)
		for k in 8:
			row.blit_rect(img, Rect2i(0, k * fh, fw, fh), Vector2i(k * fw, 0))
		strips.append(row)
	if not strips.is_empty():
		_save(_stack(strips), dir.path_join("wrecks.png"))
		n += 1
	var icons: Dictionary = out.manifest.get("icons", {})
	var ik: Array = icons.keys()
	ik.sort()
	if not ik.is_empty():
		var sheet := Image.create(34 * 8, 34 * int(ceil(ik.size() / 8.0)), false, Image.FORMAT_RGBA8)
		for i in ik.size():
			var ic: Image = out.images[icons[ik[i]]]
			sheet.blit_rect(ic, Rect2i(Vector2i.ZERO, ic.get_size()), Vector2i((i % 8) * 34, (i / 8) * 34))
		_save(sheet, dir.path_join("icons.png"))
		n += 1
	return n


static func _tinted(out: Dictionary, file: String, mask: String) -> Image:
	return FX.tint(out.images[file], out.images[mask], TEAM)


static func _stack(rows: Array) -> Image:
	var w := 0
	var h := 0
	for r: Image in rows:
		w = maxi(w, r.get_width())
		h += r.get_height() + 2
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var y := 0
	for r: Image in rows:
		img.blit_rect(r, Rect2i(Vector2i.ZERO, r.get_size()), Vector2i(0, y))
		y += r.get_height() + 2
	return img


static func _save(src: Image, path: String) -> void:
	var bg := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	bg.fill(BG)
	bg.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i.ZERO)
	bg.resize(src.get_width() * Z, src.get_height() * Z, Image.INTERPOLATE_NEAREST)
	bg.save_png(path)
