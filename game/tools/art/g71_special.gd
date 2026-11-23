extends SceneTree
## G7.1 C4 specials art (defs_g71_special.json; wave6 Phase 1B):
##   g71_m_reclaimer      = G6 m_assimilator (tracked harvester) + amber reclaim hopper / intake scoop / beam tip
##   g71_m_hive_conductor = generated m_walker (command walker) + violet sync ring + command mast
##   g71_m_glass_stalker  = generated m_coordinator (skulker) + translucent glass edge + cyan refraction stripe
## B6 CONDUCTOR gunship (a_g71_conductor) already ships under g71_fires — not this group.
## Overlay pixels are cleared from the team masks. Writes assets/art/g71_special/ only. Deterministic.
##   godot --headless --path . -s tools/art/g71_special.gd
##   godot --headless --path . -s tools/art/g71_special.gd -- --out=<abs dir>
const GEN = preload("res://tools/gen_art.gd")
const GROUP := "g71_special"
const SRC6 := "res://assets/art/g6_units/"
const SRC_GEN := "res://assets/generated/"

const AMBER := Color8(232, 168, 48)
const AMBER_H := Color8(255, 214, 120)
const AMBER_K := Color8(48, 36, 22)
const HIVE := Color8(168, 72, 214)
const HIVE_H := Color8(220, 150, 255)
const HIVE_K := Color8(42, 28, 52)
const GLASS := Color8(160, 220, 230)
const GLASS_H := Color8(210, 246, 255)
const GLASS_E := Color8(90, 140, 150)


func _init() -> void:
	var dir := "res://assets/art/%s/" % GROUP
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			dir = String(a).substr(6)
	var t0 := Time.get_ticks_msec()
	var out := build()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var n := GEN.save(out, dir)
	var u := (out.manifest.vehicles as Dictionary).size() + (out.manifest.infantry as Dictionary).size()
	print("G71_SPECIAL units=%d icons=%d files=%d ms=%d" % [u, (out.manifest.icons as Dictionary).size(), n, Time.get_ticks_msec() - t0])
	quit()


static func build() -> Dictionary:
	var man := {"version": 1, "tile": [64, 32], "group": GROUP, "infantry": {}, "vehicles": {}, "vehicle_wrecks": {}, "icons": {}}
	var out := {"images": {}, "manifest": man}
	var g6: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SRC6 + "manifest.json"))
	var gen: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SRC_GEN + "manifest.json"))

	# Reclaimer: tracked harvester (assimilator base) + amber reclaim marks
	var rec: Dictionary = (g6.vehicles.m_assimilator as Dictionary).duplicate(true)
	_pair(out, SRC6, rec, "units/g71_m_reclaimer", int(rec.fw), int(rec.fh), "reclaimer")
	rec["g71"] = {"base": "m_assimilator", "mark": "amber reclaim hopper + intake scoop + beam tip"}
	man.vehicles["g71_m_reclaimer"] = rec
	var rwr: Dictionary = (g6.vehicle_wrecks.m_assimilator as Dictionary).duplicate(true)
	out.images["wrecks/g71_m_reclaimer_wreck.png"] = _load(SRC6 + String(rwr.file))
	rwr.file = "wrecks/g71_m_reclaimer_wreck.png"
	man.vehicle_wrecks["g71_m_reclaimer"] = rwr
	var ric := _load(SRC6 + String(g6.icons.m_assimilator))
	_mark_cell(ric, null, Rect2i(Vector2i.ZERO, ric.get_size()), "reclaimer")
	out.images["icons/g71_m_reclaimer.png"] = ric
	man.icons["g71_m_reclaimer"] = "icons/g71_m_reclaimer.png"

	# Hive Conductor: heavy command walker + violet sync ring / mast (not the B6 gunship)
	var hive: Dictionary = (gen.infantry.m_walker as Dictionary).duplicate(true)
	_pair(out, SRC_GEN, hive, "units/g71_m_hive_conductor", int(hive.fw), int(hive.fh), "hive")
	hive["g71"] = {"base": "m_walker", "mark": "violet sync ring + command mast"}
	man.infantry["g71_m_hive_conductor"] = hive
	if (gen.get("vehicle_wrecks", {}) as Dictionary).has("m_walker"):
		var hwr: Dictionary = (gen.vehicle_wrecks.m_walker as Dictionary).duplicate(true)
		out.images["wrecks/g71_m_hive_conductor_wreck.png"] = _load(SRC_GEN + String(hwr.file))
		hwr.file = "wrecks/g71_m_hive_conductor_wreck.png"
		man.vehicle_wrecks["g71_m_hive_conductor"] = hwr
	var hic := _load(SRC_GEN + String(gen.icons.m_walker))
	_mark_cell(hic, null, Rect2i(Vector2i.ZERO, hic.get_size()), "hive")
	out.images["icons/g71_m_hive_conductor.png"] = hic
	man.icons["g71_m_hive_conductor"] = "icons/g71_m_hive_conductor.png"

	# Glass Stalker: skulker + translucent glass edge / cyan refraction (no wreck)
	var stalk: Dictionary = (gen.infantry.m_coordinator as Dictionary).duplicate(true)
	_pair(out, SRC_GEN, stalk, "units/g71_m_glass_stalker", int(stalk.fw), int(stalk.fh), "glass")
	stalk["g71"] = {"base": "m_coordinator", "mark": "translucent glass edge + cyan refraction stripe"}
	man.infantry["g71_m_glass_stalker"] = stalk
	var sic := _load(SRC_GEN + String(gen.icons.m_coordinator))
	_mark_cell(sic, null, Rect2i(Vector2i.ZERO, sic.get_size()), "glass")
	out.images["icons/g71_m_glass_stalker.png"] = sic
	man.icons["g71_m_glass_stalker"] = "icons/g71_m_glass_stalker.png"
	return out


static func _load(p: String) -> Image:
	var img := Image.load_from_file(p)
	if img == null:
		var tex = load(p)
		img = tex.get_image() if tex != null else Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	return img


static func _pair(out: Dictionary, src: String, spec: Dictionary, stem: String, fw: int, fh: int, mark: String) -> void:
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
	match mark:
		"reclaimer":
			# amber / dark hopper band across the upper hull (feedstock bay)
			var y0 := bb.position.y + int(bb.size.y * 0.28)
			for y in range(y0, y0 + 2):
				for x in range(bb.position.x, bb.end.x):
					if img.get_pixel(x, y).a > 0.5:
						_put(img, mask, cell, x, y, AMBER if ((x + y) / 2) % 2 == 0 else AMBER_K)
			# intake scoop: front-most opaque column mid-height gets an amber wedge
			var mid_y := bb.position.y + int(bb.size.y * 0.55)
			for x in range(bb.end.x - 1, bb.position.x, -1):
				if img.get_pixel(x, mid_y).a > 0.5:
					_put(img, mask, cell, x, mid_y, AMBER_H)
					_put(img, mask, cell, x - 1, mid_y, AMBER)
					_put(img, mask, cell, x, mid_y - 1, AMBER)
					_put(img, mask, cell, x, mid_y + 1, AMBER_K)
					break
			# reclaim beam tip on the lower-front silhouette
			var tip_y := bb.position.y + int(bb.size.y * 0.72)
			for x in range(bb.end.x - 1, bb.position.x, -1):
				if img.get_pixel(x, tip_y).a > 0.5:
					_put(img, mask, cell, x, tip_y, AMBER_H)
					break
		"hive":
			# violet sync ring around the torso (opaque mid-band row)
			var yr := bb.position.y + int(bb.size.y * 0.42)
			for x in range(bb.position.x, bb.end.x):
				if img.get_pixel(x, yr).a > 0.5:
					_put(img, mask, cell, x, yr, HIVE if x % 3 != 1 else HIVE_H)
			# dark command stripe one row below
			var ys := yr + 2
			if ys < bb.end.y:
				for x in range(bb.position.x, bb.end.x):
					if img.get_pixel(x, ys).a > 0.5:
						_put(img, mask, cell, x, ys, HIVE_K)
			# command mast rising from the upper centre
			var mx := bb.position.x + bb.size.x / 2
			var my := bb.position.y + int(bb.size.y * 0.18)
			for i in 6:
				_put(img, mask, cell, mx, my - i, HIVE_K if i % 2 == 0 else HIVE)
			_put(img, mask, cell, mx, my - 6, HIVE_H)
			_put(img, mask, cell, mx - 1, my - 5, HIVE)
			_put(img, mask, cell, mx + 1, my - 5, HIVE)
		"glass":
			# translucent edge: thin glass rim (semi-transparent cyan) on silhouette boundary
			for y in range(bb.position.y, bb.end.y):
				for x in range(bb.position.x, bb.end.x):
					var px := img.get_pixel(x, y)
					if px.a < 0.5:
						continue
					var edge := false
					for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var nx: int = x + d.x
						var ny: int = y + d.y
						if nx < cell.position.x or ny < cell.position.y or nx >= cell.end.x or ny >= cell.end.y \
								or img.get_pixel(nx, ny).a < 0.5:
							edge = true
							break
					if edge:
						_put(img, mask, cell, x, y, Color(GLASS_E.r, GLASS_E.g, GLASS_E.b, 0.55))
			# cyan refraction stripe across the mid body (opaque pixels only, cleared from mask)
			var yg := bb.position.y + int(bb.size.y * 0.45)
			for x in range(bb.position.x, bb.end.x):
				if img.get_pixel(x, yg).a > 0.4:
					_put(img, mask, cell, x, yg, GLASS_H if x % 2 == 0 else GLASS)
			# second thinner glass sheen one row above
			var yg2 := yg - 2
			if yg2 >= bb.position.y:
				for x in range(bb.position.x, bb.end.x):
					if img.get_pixel(x, yg2).a > 0.5 and x % 3 == 0:
						_put(img, mask, cell, x, yg2, GLASS)
