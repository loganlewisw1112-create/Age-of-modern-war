extends RefCounted
## ART-U contact sheets for the G4b units (review only; never written into assets/). compose(out, dir)
## writes 4 zoomed PNGs into dir: inf.png (foot units, 3x), veh_a.png (APC + halftrack, 2x),
## veh_b.png (rocket truck + scrap mech, 2x), fx_icons.png (effects 3x + unit/editor icons 2x).
## Sheets are team-tinted blue (first half) on a grass-like ground so outlines and masks read.
const FX = preload("res://tools/art/fx_ui.gd")

const GROUND := Color8(92, 104, 70)
const BLUE := Color("#4f7db0")
const RED := Color("#b5583a")


static func compose(out: Dictionary, dir: String) -> Array:
	var made: Array = []
	made.append(_strip(out, dir.path_join("inf.png"),
		["a_sniper", "a_mortar", "a_combat_engineer", "b_flamer"], "infantry", 3))
	made.append(_strip(out, dir.path_join("veh_a.png"), ["a_apc", "b_halftrack"], "vehicles", 2))
	made.append(_strip(out, dir.path_join("veh_b.png"), ["b_rocket_truck", "b_scrap_mech"], "vehicles", 2))
	made.append(_fx_icons(out, dir.path_join("fx_icons.png")))
	return made


static func _sheet_img(out: Dictionary, sec: String, def: String, col: Color) -> Image:
	var sp: Dictionary = out.manifest[sec][def]
	return FX.tint(out.images[sp.file], out.images[sp.mask], col)


static func _strip(out: Dictionary, path: String, defs: Array, sec: String, z: int) -> String:
	var parts: Array = []
	var w := 0
	var h := 0
	for i in defs.size():
		var def: String = defs[i]
		var im := _sheet_img(out, sec, def, BLUE if i % 2 == 0 else RED)
		parts.append(im)
		w += im.get_width() + 6
		h = maxi(h, im.get_height())
		var wr: Dictionary = out.manifest.get("vehicle_wrecks", {}).get(def, {})
		if not wr.is_empty():
			var wi: Image = out.images[wr.file]
			parts.append(wi)
			w += wi.get_width() + 12
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(GROUND)
	var x := 0
	for im: Image in parts:
		img.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(x, 0))
		x += im.get_width() + 8
	img.resize(w * z, h * z, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
	return path


static func _fx_icons(out: Dictionary, path: String) -> String:
	var img := Image.create(640, 700, false, Image.FORMAT_RGBA8)
	img.fill(GROUND)
	var y := 4
	var x := 4
	var row_h := 0
	for n in ["fire_forest", "burnt_ground", "mine", "mine_detected", "charge", "flame_jet"]:
		var e: Dictionary = out.manifest.effects[n]
		var im: Image = out.images[e.file]
		if e.has("mask"):
			im = FX.tint(im, out.images[e.mask], BLUE)
		var s: Image = im.duplicate()
		var z := 3 if im.get_width() < 100 else 2
		s.resize(im.get_width() * z, im.get_height() * z, Image.INTERPOLATE_NEAREST)
		if x + s.get_width() > 636:
			x = 4
			y += row_h + 10
			row_h = 0
		img.blend_rect(s, Rect2i(Vector2i.ZERO, s.get_size()), Vector2i(x, y))
		x += s.get_width() + 10
		row_h = maxi(row_h, s.get_height())
	y += row_h + 16
	x = 4
	var ids: Array = ["a_apc", "a_sniper", "a_mortar", "a_combat_engineer", "b_flamer", "b_halftrack",
		"b_scrap_mech", "b_rocket_truck"]
	for id in out.manifest.get("editor_icons", {}):
		ids.append("ed_" + id)
	for id in ids:
		var ic: Image = (out.images[out.manifest.icons[id]] as Image).duplicate()
		ic.resize(64, 64, Image.INTERPOLATE_NEAREST)
		if x + 64 > 636:
			x = 4
			y += 68
		img.blit_rect(ic, Rect2i(0, 0, 64, 64), Vector2i(x, y))
		x += 66
	img.save_png(path)
	return path
