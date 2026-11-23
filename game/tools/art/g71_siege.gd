extends SceneTree
## G7.1 SIEGE (C3): full art roll-out for the siege Machine defs (content/g71/defs_g71_siege.json).
## Clones suitable Machine bases and paints DISTINCT per-def marks so units stay readable at play zoom:
##   g71_m_brute         = g7 packhunter + heavy shoulder plate / knuckle pads (gorilla silhouette)
##   g71_m_brute_alpha   = packhunter + thicker plate + alpha crest spikes (mini-boss)
##   g71_m_siege_walker  = g6 colossus + long siege barrel (counter-battery bait)
##   g71_m_mega_walker   = colossus + long barrel + double armour chevrons (siege spike)
##   g71_m_lazarus       = colossus + rust weld-stitch seams (stitched from wrecks)
##   g71_m_turret_eater  = g6 mimic drone + latch mandibles + swarm dots (dive latch)
##   g71_m_sapper        = g7 burrower + dirt ring + drill tip (tunnel / breach)
## Overlay pixels are cleared from team masks (marks never take the team tint). Writes its own group
## assets/art/g71_siege/ (manifest.json) only. Deterministic: re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g71_siege.gd                 # writes assets/art/g71_siege/
##   godot --headless --path . -s tools/art/g71_siege.gd -- --out=<abs dir>
const GEN = preload("res://tools/gen_art.gd")
const GROUP := "g71_siege"

const SRC_THREAT := "res://assets/art/g7_threats/"
const SRC_THREAT2 := "res://assets/art/g7_threats2/"
const SRC_G6 := "res://assets/art/g6_units/"

## def -> [src_dir, base_id, mark]
const UNITS := {
	"g71_m_brute": [SRC_THREAT, "g7_m_packhunter", "brute"],
	"g71_m_brute_alpha": [SRC_THREAT, "g7_m_packhunter", "alpha"],
	"g71_m_siege_walker": [SRC_G6, "m_colossus", "siege"],
	"g71_m_mega_walker": [SRC_G6, "m_colossus", "mega"],
	"g71_m_lazarus": [SRC_G6, "m_colossus", "lazarus"],
	"g71_m_turret_eater": [SRC_G6, "m_mimic_drone", "eater"],
	"g71_m_sapper": [SRC_THREAT2, "g7_m_burrower", "sapper"],
}

const PLATE := Color8(72, 78, 84)
const PLATE_D := Color8(36, 40, 44)
const PLATE_H := Color8(140, 148, 156)
const CREST := Color8(210, 196, 72)
const BARREL := Color8(48, 52, 56)
const MUZZLE := Color8(210, 214, 200)
const RUST := Color8(148, 86, 48)
const WELD := Color8(190, 198, 204)
const SWARM := Color8(90, 220, 210)
const BITE := Color8(230, 80, 70)
const DIRT := Color8(96, 82, 64)
const DRILL := Color8(170, 178, 186)


func _init() -> void:
	var dir := "res://assets/art/%s/" % GROUP
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			dir = String(a).substr(6)
	var t0 := Time.get_ticks_msec()
	var out := build()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var n := GEN.save(out, dir)
	print("G71_SIEGE units=%d icons=%d files=%d ms=%d" % [(out.manifest.vehicles as Dictionary).size(), (out.manifest.icons as Dictionary).size(), n, Time.get_ticks_msec() - t0])
	quit()


static func build() -> Dictionary:
	var man := {"version": 1, "tile": [64, 32], "group": GROUP, "infantry": {}, "vehicles": {}, "vehicle_wrecks": {}, "icons": {}}
	var out := {"images": {}, "manifest": man}
	var manifests: Dictionary = {}
	for def in UNITS.keys():
		var src_dir := String(UNITS[def][0])
		var base := String(UNITS[def][1])
		var mark := String(UNITS[def][2])
		if not manifests.has(src_dir):
			manifests[src_dir] = JSON.parse_string(FileAccess.get_file_as_string(src_dir + "manifest.json"))
		var sm: Dictionary = manifests[src_dir]
		var spec: Dictionary = (sm.vehicles[base] as Dictionary).duplicate(true)
		_pair(out, spec, "units/" + def, int(spec.fw), int(spec.fh), mark, src_dir)
		for sk in ["shadow", "shadow_sheet"]:
			if spec.get(sk) is Dictionary and (spec[sk] as Dictionary).has("file"):
				var rel_s := "units/%s_%s.png" % [def, sk]
				out.images[rel_s] = _load(src_dir + String(spec[sk].file))
				spec[sk].file = rel_s
		spec["g71"] = {"base": base, "mark": mark, "siege": true}
		man.vehicles[def] = spec
		# wreck: prefer same-base wreck; heavy brutes reuse the colossus wreck (packhunter has none)
		var wreck_src := src_dir
		var wreck_base := base
		var wreck_man: Dictionary = sm
		if not ((sm.get("vehicle_wrecks", {}) as Dictionary).has(base)):
			if String(def).begins_with("g71_m_brute"):
				wreck_src = SRC_G6
				wreck_base = "m_colossus"
				if not manifests.has(SRC_G6):
					manifests[SRC_G6] = JSON.parse_string(FileAccess.get_file_as_string(SRC_G6 + "manifest.json"))
				wreck_man = manifests[SRC_G6]
		if ((wreck_man.get("vehicle_wrecks", {}) as Dictionary).has(wreck_base)):
			var wr: Dictionary = (wreck_man.vehicle_wrecks[wreck_base] as Dictionary).duplicate(true)
			var wimg := _load(wreck_src + String(wr.file))
			_mark_cell(wimg, null, Rect2i(Vector2i.ZERO, wimg.get_size()), mark)
			out.images["wrecks/%s_wreck.png" % def] = wimg
			wr.file = "wrecks/%s_wreck.png" % def
			man.vehicle_wrecks[def] = wr
		var ic := _load(src_dir + String(sm.icons[base]))
		_mark_cell(ic, null, Rect2i(Vector2i.ZERO, ic.get_size()), mark)
		out.images["icons/%s.png" % def] = ic
		man.icons[def] = "icons/%s.png" % def
	return out


static func _load(p: String) -> Image:
	var img := Image.load_from_file(p)
	if img == null:
		var tex = load(p)
		img = tex.get_image() if tex != null else Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	return img


static func _pair(out: Dictionary, spec: Dictionary, stem: String, fw: int, fh: int, mark: String, sdir: String) -> void:
	var img := _load(sdir + String(spec.file))
	var mask: Image = _load(sdir + String(spec.mask)) if spec.has("mask") else null
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


static func _band(img: Image, mask: Image, cell: Rect2i, bb: Rect2i, y_frac: float, h: int, a: Color, b: Color) -> void:
	var y0 := bb.position.y + int(bb.size.y * y_frac)
	for y in range(y0, mini(y0 + h, cell.end.y)):
		for x in range(bb.position.x, bb.end.x):
			if img.get_pixel(x, y).a > 0.5:
				_put(img, mask, cell, x, y, a if ((x + y) / 2) % 2 == 0 else b)


static func _mark_cell(img: Image, mask: Image, cell: Rect2i, mark: String) -> void:
	var bb := _bbox(img, cell)
	if bb.size == Vector2i.ZERO:
		return
	match mark:
		"brute":
			# heavy shoulder plate across the upper third + knuckle pads on the leading edge
			_band(img, mask, cell, bb, 0.28, 3, PLATE, PLATE_D)
			var ky := bb.position.y + int(bb.size.y * 0.55)
			for x in range(bb.end.x - 1, bb.position.x + bb.size.x / 2, -1):
				if img.get_pixel(x, ky).a > 0.5:
					_put(img, mask, cell, x, ky, PLATE_H)
					_put(img, mask, cell, x - 1, ky, PLATE)
					_put(img, mask, cell, x, ky + 1, PLATE_D)
					break
		"alpha":
			# thicker plate + gold crest spikes on the crown (mini-boss readable at zoom)
			_band(img, mask, cell, bb, 0.22, 4, PLATE, PLATE_D)
			_band(img, mask, cell, bb, 0.48, 2, PLATE_H, PLATE)
			var cx := bb.position.x + bb.size.x / 2
			var ty := bb.position.y + 1
			for dx in [-3, 0, 3]:
				for i in 4:
					_put(img, mask, cell, cx + dx, ty + i, CREST if i < 2 else PLATE_D)
		"siege":
			# long siege barrel protruding from the rightmost opaque edge at mid-height
			_band(img, mask, cell, bb, 0.38, 2, BARREL, PLATE_D)
			var by := bb.position.y + int(bb.size.y * 0.42)
			var tip_x := bb.end.x
			for x in range(bb.end.x - 1, bb.position.x, -1):
				if img.get_pixel(x, by).a > 0.5:
					tip_x = x
					break
			for i in 10:
				var x2 := tip_x + 1 + i
				if x2 >= cell.end.x:
					break
				_put(img, mask, cell, x2, by, BARREL if i < 8 else MUZZLE)
				_put(img, mask, cell, x2, by + 1, BARREL if i < 8 else MUZZLE)
		"mega":
			# siege barrel + double armour chevrons (heavier than the base walker)
			_band(img, mask, cell, bb, 0.30, 2, PLATE, PLATE_D)
			_band(img, mask, cell, bb, 0.55, 2, PLATE_H, PLATE)
			var by2 := bb.position.y + int(bb.size.y * 0.40)
			var tip2 := bb.end.x
			for x in range(bb.end.x - 1, bb.position.x, -1):
				if img.get_pixel(x, by2).a > 0.5:
					tip2 = x
					break
			for i in 12:
				var x3 := tip2 + 1 + i
				if x3 >= cell.end.x:
					break
				_put(img, mask, cell, x3, by2, BARREL if i < 10 else MUZZLE)
				_put(img, mask, cell, x3, by2 + 1, BARREL if i < 10 else MUZZLE)
			# chevron notches on the upper plate
			var cy := bb.position.y + int(bb.size.y * 0.30)
			for dx2 in range(0, bb.size.x, 6):
				_put(img, mask, cell, bb.position.x + dx2, cy, CREST)
				_put(img, mask, cell, bb.position.x + dx2 + 1, cy + 1, CREST)
		"lazarus":
			# rust weld-stitch seams: diagonal rust dashes + pale weld dots (stitched wreck look)
			for y in range(bb.position.y, bb.end.y):
				for x in range(bb.position.x, bb.end.x):
					if img.get_pixel(x, y).a <= 0.5:
						continue
					var k := (x + y * 3) % 11
					if k == 0:
						_put(img, mask, cell, x, y, RUST)
					elif k == 5:
						_put(img, mask, cell, x, y, WELD)
			_band(img, mask, cell, bb, 0.50, 1, RUST, WELD)
		"eater":
			# latch mandibles on the nose + cyan swarm dots along the hull
			var ny := bb.position.y + int(bb.size.y * 0.45)
			for x in range(bb.end.x - 1, bb.position.x + bb.size.x / 2, -1):
				if img.get_pixel(x, ny).a > 0.5:
					_put(img, mask, cell, x + 1, ny - 1, BITE)
					_put(img, mask, cell, x + 2, ny - 2, BITE)
					_put(img, mask, cell, x + 1, ny + 1, BITE)
					_put(img, mask, cell, x + 2, ny + 2, BITE)
					_put(img, mask, cell, x, ny, SWARM)
					break
			var n := 0
			for y in range(bb.position.y, bb.end.y):
				for x in range(bb.position.x, bb.end.x):
					if img.get_pixel(x, y).a > 0.5 and (x + y * 2) % 9 == 0:
						_put(img, mask, cell, x, y, SWARM)
						n += 1
						if n >= 8:
							break
				if n >= 8:
					break
		"sapper":
			# dirt ring under the hull + pale drill tip on the leading edge (burrower cue)
			var gy := bb.end.y - 1
			for x in range(bb.position.x - 1, bb.end.x + 1):
				_put(img, mask, cell, x, gy, DIRT)
				if (x + gy) % 2 == 0:
					_put(img, mask, cell, x, gy - 1, DIRT)
			var dy := bb.position.y + int(bb.size.y * 0.40)
			for x in range(bb.end.x - 1, bb.position.x, -1):
				if img.get_pixel(x, dy).a > 0.5:
					_put(img, mask, cell, x + 1, dy, DRILL)
					_put(img, mask, cell, x + 2, dy, DRILL)
					_put(img, mask, cell, x + 3, dy, PLATE_H)
					_put(img, mask, cell, x + 1, dy - 1, DRILL)
					_put(img, mask, cell, x + 1, dy + 1, DRILL)
					break
			_band(img, mask, cell, bb, 0.55, 1, DIRT, PLATE_D)
