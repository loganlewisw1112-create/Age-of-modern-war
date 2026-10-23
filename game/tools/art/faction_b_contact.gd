extends SceneTree
## Human B contact sheet (agent ART3-B). Generates the faction_b module IN MEMORY (no files under
## assets/ are written, so no gen lock is needed) next to Human A references from the shipped files.
##   godot --headless --path . -s tools/art/faction_b_contact.gd [-- --out=<abs png>]
const FB = preload("res://tools/art/faction_b.gd")
const FX = preload("res://tools/art/fx_ui.gd")

const W := 1500
const BG := Color(0.24, 0.27, 0.19, 1)
const BLUE := Color("#4f7db0")
const RED := Color("#b5583a")

var img: Image
var x := 6
var y := 6
var row_h := 0


func _init() -> void:
	var path := ProjectSettings.globalize_path("res://.plan/shots/ART3-B/contact.png")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			path = a.substr(6)
	var t0 := Time.get_ticks_msec()
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32]}}
	FB.build(out)
	print("FB_CONTACT generated %d images in %d ms" % [out.images.size(), Time.get_ticks_msec() - t0])
	img = Image.create(W, 3600, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	var man: Dictionary = out.manifest
	# 1: infantry full sheets (blue), then idle row 0..7 at 3x (red)
	for def in man.infantry:
		_put(_tinted(out, man.infantry[def].file, man.infantry[def].mask, BLUE), 1)
	_nl()
	for def in man.infantry:
		var sp: Dictionary = man.infantry[def]
		var sheet := _tinted(out, sp.file, sp.mask, RED)
		for k in [1, 3, 6]:
			_put(sheet.get_region(Rect2i(0, k * sp.fh, sp.fw * 4, sp.fh)), 3)
	_nl()
	# 2: vehicles: facings 0..7 (idle) at 1x, then 2x of facing 1 and 6 incl. fire frame; wrecks
	for def in man.vehicles:
		var sp: Dictionary = man.vehicles[def]
		var sheet := _tinted(out, sp.file, sp.mask, BLUE if def != "b_rebuilt_mbt" else RED)
		for k in 8:
			_put(sheet.get_region(Rect2i(0, k * sp.fh, sp.fw, sp.fh)), 1)
		_nl()
	for def in man.vehicles:
		var sp: Dictionary = man.vehicles[def]
		var sheet := _tinted(out, sp.file, sp.mask, BLUE)
		_put(sheet.get_region(Rect2i(0, 1 * sp.fh, sp.fw, sp.fh)), 2)
		_put(sheet.get_region(Rect2i(sp.fw * 2, 6 * sp.fh, sp.fw, sp.fh)), 2)
	_nl()
	for def in man.vehicle_wrecks:
		var wr: Image = out.images[man.vehicle_wrecks[def].file]
		var sp: Dictionary = man.vehicle_wrecks[def]
		for k in [1, 4]:
			_put(wr.get_region(Rect2i(0, k * sp.fh, sp.fw, sp.fh)), 2)
	_nl()
	# 3: buildings, 4 states at 1x; built at 2x
	for def in man.buildings:
		for st in ["build_0", "build_1", "build_2", "built"]:
			var s: Dictionary = man.buildings[def].states[st]
			_put(_tinted(out, s.file, s.mask, BLUE), 1)
		x += 10
	_nl()
	for def in ["b_works", "b_smelter", "b_heavy_plant", "b_salvage_yard"]:
		var s: Dictionary = man.buildings[def].states.built
		_put(_tinted(out, s.file, s.mask, RED), 2)
	_nl()
	for def in ["b_boiler", "b_barracks", "b_bunker"]:
		var s: Dictionary = man.buildings[def].states.built
		_put(_tinted(out, s.file, s.mask, BLUE), 2)
	# Human A references from the shipped files, same scale
	for rel in ["buildings/hq_built.png", "buildings/barracks_built.png"]:
		var im := Image.load_from_file(ProjectSettings.globalize_path("res://assets/generated/" + rel))
		if im != null:
			_put(im, 2)
	_nl()
	# 4: icons at 2x
	for id in man.icons:
		_put(out.images[man.icons[id]], 2)
	_nl()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.get_region(Rect2i(0, 0, W, mini(y + 4, img.get_height()))).save_png(path)
	print("FB_CONTACT wrote " + path + " icons=" + str(man.icons.size()))
	# zoom panel: vehicles facing 1 (idle) + facing 6 (fire) and infantry facings 1/6 at 3x
	img = Image.create(W, 1400, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	x = 6
	y = 6
	row_h = 0
	for def in man.vehicles:
		var sp: Dictionary = man.vehicles[def]
		var sheet := _tinted(out, sp.file, sp.mask, BLUE)
		_put(sheet.get_region(Rect2i(0, 1 * sp.fh, sp.fw, sp.fh)), 3)
		_put(sheet.get_region(Rect2i(sp.fw * 2, 6 * sp.fh, sp.fw, sp.fh)), 3)
	_nl()
	for def in man.infantry:
		var sp: Dictionary = man.infantry[def]
		var sheet := _tinted(out, sp.file, sp.mask, BLUE)
		_put(sheet.get_region(Rect2i(0, 1 * sp.fh, sp.fw * 4, sp.fh)), 3)
		_put(sheet.get_region(Rect2i(0, 6 * sp.fh, sp.fw, sp.fh)), 3)
	_nl()
	img.get_region(Rect2i(0, 0, W, y + 4)).save_png(path.get_basename() + "_zoom.png")
	quit(0)


func _tinted(out: Dictionary, file: String, mask: String, col: Color) -> Image:
	return FX.tint(out.images[file], out.images[mask], col)


func _put(src: Image, scale: int) -> void:
	var im: Image = src.duplicate()
	if scale != 1:
		im.resize(im.get_width() * scale, im.get_height() * scale, Image.INTERPOLATE_NEAREST)
	if x + im.get_width() > W - 4:
		_nl()
	if y + im.get_height() >= img.get_height():
		return
	img.blend_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()), Vector2i(x, y))
	x += im.get_width() + 4
	row_h = maxi(row_h, im.get_height())


func _nl() -> void:
	if row_h == 0:
		return
	y += row_h + 8
	x = 6
	row_h = 0
