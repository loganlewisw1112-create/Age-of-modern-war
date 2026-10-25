extends RefCounted
## Self-check crops for the G5 aircraft art (agent ART-AIR), written to .plan/shots/ART-AIR/:
##   <def>.png        whole sheet, team-tinted (blue) on a grass backdrop, 2x nearest
##   <def>_zoom.png   facings 1 and 5, every frame, 4x (frame names readable by column order)
##   <def>_air.png    facing 1 cruise frame lifted by `altitude` over its shadow_sheet silhouette, 4x
##   wrecks.png / shadows.png / icons.png / fx.png
const FXU = preload("res://tools/art/fx_ui.gd")

const BG := Color8(92, 106, 66)
const TEAM := Color(0.31, 0.49, 0.69)


static func compose(out: Dictionary, dir: String) -> int:
	DirAccess.make_dir_recursive_absolute(dir)
	var n := 0
	var man: Dictionary = out.manifest.get("vehicles", {})
	var defs: Array = man.keys()
	defs.sort()
	var shadows: Array = []
	for def in defs:
		var e: Dictionary = man[def]
		var fw := int(e.fw)
		var fh := int(e.fh)
		var t := FXU.tint(out.images[e.file], out.images[e.mask], TEAM)
		_save(t, dir.path_join("%s.png" % def), 2)
		var nf: int = e.frames.size()
		_save(_stack([t.get_region(Rect2i(0, fh, fw * nf, fh)), t.get_region(Rect2i(0, fh * 5, fw * nf, fh))]),
			dir.path_join("%s_zoom.png" % def), 4)
		var alt := int(e.altitude)
		var sc := Image.create(fw, fh + alt, false, Image.FORMAT_RGBA8)
		var sh: Image = out.images[e.shadow_sheet.file]
		sc.blend_rect(sh, Rect2i(0, fh, fw, fh), Vector2i(0, alt))
		sc.blend_rect(t, Rect2i(0, fh, fw, fh), Vector2i(0, 0))
		_save(sc, dir.path_join("%s_air.png" % def), 4)
		var row := Image.create(fw * 8, fh, false, Image.FORMAT_RGBA8)
		for k in 8:
			row.blit_rect(sh, Rect2i(0, k * fh, fw, fh), Vector2i(k * fw, 0))
		shadows.append(row)
		n += 3
	var wr: Dictionary = out.manifest.get("vehicle_wrecks", {})
	var strips: Array = []
	for def in defs:
		if not wr.has(def):
			continue
		var img: Image = out.images[wr[def].file]
		var fw := int(wr[def].fw)
		var fh := int(wr[def].fh)
		var row := Image.create(fw * 8, fh, false, Image.FORMAT_RGBA8)
		for k in 8:
			row.blit_rect(img, Rect2i(0, k * fh, fw, fh), Vector2i(k * fw, 0))
		strips.append(row)
	if not strips.is_empty():
		_save(_stack(strips), dir.path_join("wrecks.png"), 2)
		_save(_stack(shadows), dir.path_join("shadows.png"), 2)
		n += 2
	var icons: Dictionary = out.manifest.get("icons", {})
	var ik: Array = icons.keys()
	ik.sort()
	if not ik.is_empty():
		var sheet := Image.create(34 * 7, 34 * int(ceil(ik.size() / 7.0)), false, Image.FORMAT_RGBA8)
		for i in ik.size():
			var ic: Image = out.images[icons[ik[i]]]
			sheet.blit_rect(ic, Rect2i(Vector2i.ZERO, ic.get_size()), Vector2i((i % 7) * 34, (i / 7) * 34))
		_save(sheet, dir.path_join("icons.png"), 3)
		n += 1
	var fx: Dictionary = out.manifest.get("effects", {})
	var fk: Array = fx.keys()
	fk.sort()
	var rows: Array = []
	for k in fk:
		rows.append(out.images[fx[k].file])
	if not rows.is_empty():
		_save(_stack(rows), dir.path_join("fx.png"), 4)
		n += 1
	return n


static func _stack(rows: Array) -> Image:
	var w := 0
	var h := 0
	for r: Image in rows:
		w = maxi(w, r.get_width())
		h += r.get_height() + 2
	var img := Image.create(maxi(1, w), maxi(1, h), false, Image.FORMAT_RGBA8)
	var y := 0
	for r: Image in rows:
		img.blit_rect(r, Rect2i(Vector2i.ZERO, r.get_size()), Vector2i(0, y))
		y += r.get_height() + 2
	return img


static func _save(src: Image, path: String, z: int) -> void:
	var bg := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	bg.fill(BG)
	bg.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i.ZERO)
	bg.resize(src.get_width() * z, src.get_height() * z, Image.INTERPOLATE_NEAREST)
	bg.save_png(path)
