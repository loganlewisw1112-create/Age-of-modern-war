extends SceneTree
## G7.1 ARMY71: functional art for the ARMY71 LP defs (content/g71/defs_g71_army.json; roster 5A Q12 / Q16: new defs
## reuse existing art bases where that is exact; functional art at the G7 detail level, full roll-out at wave 5).
##   a_g71_flame_tank = the G6 laser-tank sheet (assets/art/g6_units) + an orange / black thermite-fuel band low on the
##                      hull and a hot nozzle tip at the front of the silhouette, every frame / facing; same wreck.
##   icon             = the G6 laser-tank icon + the same band.
##   B3 crews         = the G5 team sheets (a_hmg_team / b_at_rocket_team / b_grenadiers, every alive sheet) + a
##                      crew-coloured webbing band: MG brass, AT red, .50 steel, grenadier green (icons too).
## Overlay pixels are cleared from the team masks (the marks never take the team tint). Writes its own group
## assets/art/g71_army/ (manifest.json) only. Deterministic: re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g71_army.gd                 # writes assets/art/g71_army/
##   godot --headless --path . -s tools/art/g71_army.gd -- --out=<abs dir>
const GEN = preload("res://tools/gen_art.gd")
const GROUP := "g71_army"
const SRC := "res://assets/art/g6_units/"

const FUEL_O := Color8(222, 110, 34)
const FUEL_K := Color8(36, 30, 26)
const HOT := Color8(255, 214, 120)
const SRC5 := "res://assets/art/g5_units/"
## B3 crews: def -> [G5 base sheet, mark]. Marks = a 1-px webbing band (cleared from the team mask) in the crew colour.
const CREWS := {"a_g71_mg_crew": ["a_hmg_team", "crew_brass"], "a_g71_at_team": ["b_at_rocket_team", "crew_red"],
	"a_g71_am_team": ["a_hmg_team", "crew_steel"], "a_g71_grenadier": ["b_grenadiers", "crew_green"]}
const CREW_C := {"crew_brass": Color8(214, 170, 64), "crew_red": Color8(196, 52, 40), "crew_steel": Color8(120, 150, 178), "crew_green": Color8(96, 170, 70)}


func _init() -> void:
	var dir := "res://assets/art/%s/" % GROUP
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			dir = String(a).substr(6)
	var t0 := Time.get_ticks_msec()
	var out := build()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var n := GEN.save(out, dir)
	print("G71_ARMY units=%d icons=%d files=%d ms=%d" % [(out.manifest.vehicles as Dictionary).size(), (out.manifest.icons as Dictionary).size(), n, Time.get_ticks_msec() - t0])
	quit()


static func build() -> Dictionary:
	var src: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SRC + "manifest.json"))
	var man := {"version": 1, "tile": [64, 32], "group": GROUP, "infantry": {}, "vehicles": {}, "vehicle_wrecks": {}, "icons": {}}
	var out := {"images": {}, "manifest": man}
	var ft: Dictionary = (src.vehicles.a_laser_tank as Dictionary).duplicate(true)
	_pair(out, ft, "units/a_g71_flame_tank", int(ft.fw), int(ft.fh), "flame")
	ft["g71"] = {"base": "a_laser_tank", "mark": "thermite fuel band + hot nozzle"}
	man.vehicles["a_g71_flame_tank"] = ft
	var wr: Dictionary = (src.vehicle_wrecks.a_laser_tank as Dictionary).duplicate(true)
	out.images["wrecks/a_g71_flame_tank_wreck.png"] = _load(SRC + String(wr.file))
	wr.file = "wrecks/a_g71_flame_tank_wreck.png"
	man.vehicle_wrecks["a_g71_flame_tank"] = wr
	var img := _load(SRC + String(src.icons.a_laser_tank))
	_mark_cell(img, null, Rect2i(Vector2i.ZERO, img.get_size()), "flame")
	out.images["icons/a_g71_flame_tank.png"] = img
	man.icons["a_g71_flame_tank"] = "icons/a_g71_flame_tank.png"
	# B3 crews: the G5 team sheets (every frame / facing / alive sheet) + a coloured webbing band per crew type
	var g5: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SRC5 + "manifest.json"))
	for def in CREWS:
		var base := String(CREWS[def][0])
		var sp: Dictionary = (g5.infantry[base] as Dictionary).duplicate(true)
		var mk := String(CREWS[def][1])
		_pair_from(out, SRC5, sp, "units/" + def, int(sp.fw), int(sp.fh), mk)
		var al = sp.get("alive_sheets")
		if al is Dictionary:
			for k in (al as Dictionary).keys():
				_pair_from(out, SRC5, al[k], "units/%s_a%s" % [def, k], int(sp.fw), int(sp.fh), mk)
		sp["g71"] = {"base": base, "mark": mk}
		man.infantry[def] = sp
		var ic := _load(SRC5 + String(g5.icons[base]))
		_chip(ic, CREW_C[mk])
		out.images["icons/%s.png" % def] = ic
		man.icons[def] = "icons/%s.png" % def
	return out


## Icon mark: a crew-coloured chip with a dark rim in the lower-right corner (inside the card frame).
static func _chip(img: Image, c: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var r := Rect2i(w - maxi(w / 4, 6) - 3, h - maxi(h / 6, 4) - 3, maxi(w / 4, 6), maxi(h / 6, 4))
	for y in range(r.position.y - 1, r.end.y + 1):
		for x in range(r.position.x - 1, r.end.x + 1):
			var edge := x < r.position.x or y < r.position.y or x >= r.end.x or y >= r.end.y
			img.set_pixel(x, y, Color8(24, 22, 20) if edge else c)


## _pair with an explicit source group directory.
static func _pair_from(out: Dictionary, src: String, spec: Dictionary, stem: String, fw: int, fh: int, mark: String) -> void:
	var img := _load(src + String(spec.file))
	var mask: Image = _load(src + String(spec.mask)) if spec.has("mask") else null
	for cy in range(0, img.get_height() - fh + 1, fh):
		for cx in range(0, img.get_width() - fw + 1, fw):
			_mark_cell(img, mask, Rect2i(cx, cy, fw, fh), mark)
	out.images[stem + ".png"] = img
	spec.file = stem + ".png"
	if mask != null:
		out.images[stem + "_mask.png"] = mask
		spec.mask = stem + "_mask.png"


static func _load(p: String) -> Image:
	var img := Image.load_from_file(p)
	if img == null:
		var tex = load(p)
		img = tex.get_image() if tex != null else Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	return img


## Copies spec.file / spec.mask from the source group into `stem`.png / `stem`_mask.png with the mark drawn on every
## fw x fh cell (and cleared from the mask), then re-points the spec at the new files.
static func _pair(out: Dictionary, spec: Dictionary, stem: String, fw: int, fh: int, mark: String) -> void:
	var img := _load(SRC + String(spec.file))
	var mask: Image = _load(SRC + String(spec.mask)) if spec.has("mask") else null
	for cy in range(0, img.get_height() - fh + 1, fh):
		for cx in range(0, img.get_width() - fw + 1, fw):
			_mark_cell(img, mask, Rect2i(cx, cy, fw, fh), mark)
	out.images[stem + ".png"] = img
	spec.file = stem + ".png"
	if mask != null:
		out.images[stem + "_mask.png"] = mask
		spec.mask = stem + "_mask.png"


static func _put(img: Image, mask: Image, cell: Rect2i, x: int, y: int, c: Color) -> void:
	if x < cell.position.x or y < cell.position.y or x >= cell.end.x or y >= cell.end.y:
		return
	img.set_pixel(x, y, c)
	if mask != null and x < mask.get_width() and y < mask.get_height():
		mask.set_pixel(x, y, Color(0, 0, 0, 0))


static func _bbox(img: Image, cell: Rect2i) -> Rect2i:
	var x0 := cell.end.x
	var y0 := cell.end.y
	var x1 := -1
	var y1 := -1
	for y in range(cell.position.y, cell.end.y):
		for x in range(cell.position.x, cell.end.x):
			if img.get_pixel(x, y).a > 0.5:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


static func _mark_cell(img: Image, mask: Image, cell: Rect2i, mark: String) -> void:
	var bb := _bbox(img, cell)
	if bb.size == Vector2i.ZERO:
		return
	if CREW_C.has(mark):
		# webbing / bandolier band across the upper body, opaque pixels only, alternating with a dark stitch
		var c: Color = CREW_C[mark]
		var yb := bb.position.y + int(bb.size.y * 0.42)
		for x in range(bb.position.x, bb.end.x):
			if img.get_pixel(x, yb).a > 0.5:
				_put(img, mask, cell, x, yb, c if x % 3 != 2 else c.darkened(0.45))
		return
	if mark == "flame":
		# the laser tank's cyan beam / muzzle glow becomes a flame jet (hot yellow core, orange edge)
		for y in range(cell.position.y, cell.end.y):
			for x in range(cell.position.x, cell.end.x):
				var px := img.get_pixel(x, y)
				if px.a > 0.1 and px.b > 0.55 and px.b > px.r + 0.15 and px.g > px.r:
					var hot := px.v > 0.85
					var c := Color(HOT.r, HOT.g, HOT.b, px.a) if hot else Color(FUEL_O.r, FUEL_O.g, FUEL_O.b, px.a)
					_put(img, mask, cell, x, y, c)
		# 2-px orange / black fuel band across the lower third of the hull, opaque pixels only
		var y0 := bb.position.y + int(bb.size.y * 0.62)
		for y in range(y0, y0 + 2):
			for x in range(bb.position.x, bb.end.x):
				if img.get_pixel(x, y).a > 0.5:
					_put(img, mask, cell, x, y, FUEL_O if ((x + y) / 2) % 2 == 0 else FUEL_K)
		# hot nozzle tip: the topmost opaque pixel row's middle (the gun end on most facings)
		var ty := bb.position.y + int(bb.size.y * 0.35)
		for x in range(bb.end.x - 1, bb.position.x, -1):
			if img.get_pixel(x, ty).a > 0.5:
				_put(img, mask, cell, x, ty, HOT)
				_put(img, mask, cell, x - 1, ty, FUEL_O)
				break
