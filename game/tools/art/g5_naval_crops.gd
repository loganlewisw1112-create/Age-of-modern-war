extends RefCounted
## Self-check crops for the G5 naval art (agent ART-NAV): every ship sheet team-tinted (blue) on a sea
## backdrop, scaled 3x nearest, plus wake / sinking / wreck strips, icons, effects and coast decor,
## one PNG each in .plan/shots/ART-NAV/.
const FX = preload("res://tools/art/fx_ui.gd")

const SEA := Color8(46, 92, 118)
const SAND := Color8(176, 160, 116)
const TEAM := Color(0.31, 0.49, 0.69)
const Z := 3


static func compose(out: Dictionary, dir: String) -> int:
	DirAccess.make_dir_recursive_absolute(dir)
	var n := 0
	var man: Dictionary = out.manifest.get("vehicles", {})
	var defs: Array = man.keys()
	defs.sort()
	for def in defs:
		var e: Dictionary = man[def]
		_save(FX.tint(out.images[e.file], out.images[e.mask], TEAM), dir.path_join("%s.png" % def), SEA)
		var rows: Array = []
		var wk: Dictionary = e.wake
		rows.append(_row(out.images[wk.file], int(wk.fw), int(wk.fh), 0, 8))
		var sk: Dictionary = e.sink
		for c in 4:
			rows.append(_row(out.images[sk.file], int(sk.fw), int(sk.fh), c, 8))
		var wr: Dictionary = out.manifest.vehicle_wrecks[def]
		rows.append(_row(out.images[wr.file], int(wr.fw), int(wr.fh), 0, 8))
		_save(_stack(rows), dir.path_join("%s_wake_sink_wreck.png" % def), SEA)
		n += 2
	var icons: Dictionary = out.manifest.get("icons", {})
	var ik: Array = icons.keys()
	ik.sort()
	if not ik.is_empty():
		var sheet := Image.create(34 * 9, 34 * int(ceil(ik.size() / 9.0)), false, Image.FORMAT_RGBA8)
		for i in ik.size():
			var ic: Image = out.images[icons[ik[i]]]
			sheet.blit_rect(ic, Rect2i(Vector2i.ZERO, ic.get_size()), Vector2i((i % 9) * 34, (i / 9) * 34))
		_save(sheet, dir.path_join("icons.png"), SEA)
		n += 1
	var fx: Dictionary = out.manifest.get("effects", {})
	var fk: Array = fx.keys()
	fk.sort()
	if not fk.is_empty():
		var rows: Array = []
		for k in fk:
			rows.append(out.images[fx[k].file])
		_save(_stack(rows), dir.path_join("effects.png"), SEA)
		n += 1
	var pd: Dictionary = out.manifest.get("poi_decor", {})
	var pk: Array = pd.keys()
	pk.sort()
	if not pk.is_empty():
		var items: Array = []
		for k in pk:
			items.append(out.images[pd[k].file])
		var rows: Array = []
		for i in range(0, items.size(), 6):
			rows.append(_strip(items.slice(i, i + 6)))
		_save(_stack(rows), dir.path_join("coast_decor.png"), SAND)
		n += 1
	var dc: Dictionary = out.manifest.get("decor", {})
	if not dc.is_empty():
		var items: Array = []
		var kinds: Array = dc.keys()
		kinds.sort()
		for k in kinds:
			for v in dc[k]:
				items.append(out.images[v.file])
		_save(_strip(items), dir.path_join("coast_decor_small.png"), SAND)
		n += 1
	var tg: Dictionary = out.manifest.get("terrain_g5", {})
	for k in tg.get("trans", {}):
		_save(out.images[tg.trans[k]], dir.path_join("trans_%s.png" % k), SEA)
		n += 1
	return n


static func _row(img: Image, fw: int, fh: int, col: int, rows: int) -> Image:
	var r := Image.create(fw * rows, fh, false, Image.FORMAT_RGBA8)
	for k in rows:
		r.blit_rect(img, Rect2i(col * fw, k * fh, fw, fh), Vector2i(k * fw, 0))
	return r


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


static func _strip(items: Array) -> Image:
	var w := 0
	var h := 0
	for r: Image in items:
		w += r.get_width() + 2
		h = maxi(h, r.get_height())
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var x := 0
	for r: Image in items:
		img.blit_rect(r, Rect2i(Vector2i.ZERO, r.get_size()), Vector2i(x, h - r.get_height()))
		x += r.get_width() + 2
	return img


static func _save(src: Image, path: String, bgc: Color) -> void:
	var bg := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	bg.fill(bgc)
	bg.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i.ZERO)
	bg.resize(src.get_width() * Z, src.get_height() * Z, Image.INTERPOLATE_NEAREST)
	bg.save_png(path)
