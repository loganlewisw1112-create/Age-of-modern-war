extends SceneTree
## G7.1 BASTION71: functional art for the BASTION71 LP defs (content/g71/defs_g71_defences.json; roster 5A Q12 / Q16:
## new defs reuse existing art bases where that is exact; functional art at the G7 detail level now, the full roll-out
## waits for the wave-5 look checkpoint). Every state / rotation / frame of the base is copied and marked:
##   a_g71_rotary_rail  = a_t7_railgun (g7_turrets2) + a glowing rotary barrel cluster (hot orange rings)
##   a_g71_laser_ciws   = a_laser_ciws (g6_bld) + a cyan beam director lens and band
##   a_g71_hpm          = a_t7_microwave (g7_turrets2) + a yellow / black HPM horn band and spark zigzag
##   a_g71_flak         = a_t7_autocannon (g7_turrets2) + a black / white flak band and two burst puffs
##   a_g71_sonic_sensor = s_sandbags (g6_bld) + a seismic probe mast, listening disc and green status lamp
##   a_g71_berm         = s_sandbags (g6_bld) recoloured to packed earth with grass tufts
##   a_g71_siege_engineer = the G7 facility engineer sheet + a steel ballistic shield in front of the figure
##   a_g71_maint_drone  = the Machine maintenance swarm sheet in Human A drab + a green repair cross (foot frames)
##   a_g71_breacher     = the G6 armoured dozer sheet in Human A drab + a hazard band across the blade; same wreck
## Overlay pixels are cleared from the team masks, so the marks never take the team tint. Writes its own group
## assets/art/g71_defences/ (manifest.json); never touches another generator's files. Deterministic: re-running
## reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g71_defences.gd                 # writes assets/art/g71_defences/
##   godot --headless --path . -s tools/art/g71_defences.gd -- --out=<abs dir>
const GEN = preload("res://tools/gen_art.gd")
const GROUP := "g71_defences"
const ART := "res://assets/art/"

const HOT := Color8(255, 132, 40)
const HOT_L := Color8(255, 214, 120)
const STEEL := Color8(52, 56, 54)
const STEEL_L := Color8(112, 118, 112)
const CYAN := Color8(80, 220, 255)
const CYAN_L := Color8(210, 248, 255)
const HAZ_Y := Color8(232, 196, 58)
const HAZ_K := Color8(34, 32, 28)
const WHITE := Color8(226, 224, 214)
const PUFF := Color8(70, 68, 64)
const LAMP_G := Color8(120, 236, 120)
const GRASS := Color8(92, 116, 58)
const EARTH := Color8(122, 98, 66)

## def -> [source group, source def, mark]
const BLD := {
	"a_g71_rotary_rail": ["g7_turrets2", "a_t7_railgun", "rail"],
	"a_g71_laser_ciws": ["g6_bld", "a_laser_ciws", "laser"],
	"a_g71_hpm": ["g7_turrets2", "a_t7_microwave", "hpm"],
	"a_g71_flak": ["g7_turrets2", "a_t7_autocannon", "flak"],
	"a_g71_sonic_sensor": ["g6_bld", "s_sandbags", "sensor"],
	"a_g71_berm": ["g6_bld", "s_sandbags", "berm"],
}


func _init() -> void:
	var dir := ART + GROUP + "/"
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			dir = String(a).substr(6)
	var t0 := Time.get_ticks_msec()
	var out := build()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var n := GEN.save(out, dir)
	print("G71_DEFENCES buildings=%d units=%d icons=%d files=%d ms=%d" % [(out.manifest.buildings as Dictionary).size(),
		(out.manifest.infantry as Dictionary).size() + (out.manifest.vehicles as Dictionary).size(), (out.manifest.icons as Dictionary).size(), n, Time.get_ticks_msec() - t0])
	quit()


static func _man(group: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ART + group + "/manifest.json"))


static func _src(group: String, rel: String) -> String:
	return rel if rel.begins_with("res://") else ART + group + "/" + rel


static func build() -> Dictionary:
	var man := {"version": 1, "tile": [64, 32], "group": GROUP, "buildings": {}, "infantry": {}, "vehicles": {}, "vehicle_wrecks": {}, "icons": {}}
	var out := {"images": {}, "manifest": man}
	var mans := {}
	for def in BLD:
		var g := String(BLD[def][0])
		if not mans.has(g):
			mans[g] = _man(g)
		var src: Dictionary = mans[g]
		var e: Dictionary = (src.buildings[BLD[def][1]] as Dictionary).duplicate(true)
		var names: Array = (e.states as Dictionary).keys()
		names.sort()
		for st in names:
			var s: Dictionary = e.states[st]
			var img := _load(_src(g, String(s.file)))
			var mask: Image = _load(_src(g, String(s.mask))) if s.has("mask") else null
			_mark(img, mask, Rect2i(Vector2i.ZERO, img.get_size()), String(BLD[def][2]))
			var f := "buildings/%s_%s.png" % [def, st]
			out.images[f] = img
			s.file = f
			if mask != null:
				var mk := "buildings/%s_%s_mask.png" % [def, st]
				out.images[mk] = mask
				s.mask = mk
		e["g71"] = {"base": BLD[def][1], "mark": BLD[def][2]}
		man.buildings[def] = e
		_icon(out, def, _src(g, String(src.icons[BLD[def][1]])), String(BLD[def][2]))
	# siege engineer: G7 facility engineer (every cell of its sheet) + shield
	var eng: Dictionary = (_man("g7_eng7").infantry.g7_fac_engineer as Dictionary).duplicate(true)
	_pair(out, eng, "g7_eng7", "units/a_g71_siege_engineer", int(eng.fw), int(eng.fh), "shield")
	eng["g71"] = {"base": "g7_fac_engineer", "mark": "steel ballistic shield"}
	man.infantry["a_g71_siege_engineer"] = eng
	_icon(out, "a_g71_siege_engineer", _src("g7_eng7", String(_man("g7_eng7").icons.g7_fac_engineer)), "shield_icon")
	# maintenance drone: swarm sheet re-laid as foot frames idle / walk_a / walk_b / fire / work
	var g5 := _man("g5_units")
	var sw: Dictionary = g5.vehicles.m_maint_swarm
	man.vehicles["a_g71_maint_drone"] = _relay(out, sw, "g5_units", "units/a_g71_maint_drone", ["idle", "move", "idle", "fire", "work"],
		["idle", "walk_a", "walk_b", "fire", "work"], "maint")
	man.vehicles["a_g71_maint_drone"]["g71"] = {"base": "m_maint_swarm", "mark": "Human A drab + green repair cross"}
	_icon(out, "a_g71_maint_drone", _src("g5_units", String(g5.icons.m_maint_swarm)), "maint")
	# breacher dozer: armoured dozer sheet, drab + blade hazard band; same wreck
	var g6 := _man("g6_units")
	# the dozer sheet has no "fire" column: the recoil column (blade shove) is the fire frame
	var dz := _relay(out, g6.vehicles.b_armored_dozer, "g6_units", "units/a_g71_breacher",
		["idle", "move", "recoil", "work", "track_1", "track_2", "recoil", "damaged"],
		["idle", "move", "fire", "work", "track_1", "track_2", "recoil", "damaged"], "dozer")
	dz["g71"] = {"base": "b_armored_dozer", "mark": "Human A drab + blade hazard band"}
	man.vehicles["a_g71_breacher"] = dz
	var wr: Dictionary = (g6.vehicle_wrecks.b_armored_dozer as Dictionary).duplicate(true)
	out.images["wrecks/a_g71_breacher_wreck.png"] = _load(_src("g6_units", String(wr.file)))
	wr.file = "wrecks/a_g71_breacher_wreck.png"
	man.vehicle_wrecks["a_g71_breacher"] = wr
	_icon(out, "a_g71_breacher", _src("g6_units", String(g6.icons.b_armored_dozer)), "dozer")
	return out


static func _icon(out: Dictionary, def: String, path: String, mark: String) -> void:
	var img := _load(path)
	if img.get_size() != Vector2i(32, 32):
		img.resize(32, 32, Image.INTERPOLATE_NEAREST)
	_mark(img, null, Rect2i(Vector2i.ZERO, img.get_size()), mark)
	var rel := "icons/%s.png" % def
	out.images[rel] = img
	out.manifest.icons[def] = rel


static func _load(p: String) -> Image:
	var img := Image.load_from_file(p)
	if img == null:
		var tex = load(p)
		img = tex.get_image() if tex != null else Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	return img


## Copies spec.file / spec.mask into `stem`.png / `stem`_mask.png with the mark drawn on every fw x fh cell.
static func _pair(out: Dictionary, spec: Dictionary, group: String, stem: String, fw: int, fh: int, mark: String) -> void:
	var img := _load(_src(group, String(spec.file)))
	var mask: Image = _load(_src(group, String(spec.mask))) if spec.has("mask") else null
	for cy in range(0, img.get_height() - fh + 1, fh):
		for cx in range(0, img.get_width() - fw + 1, fw):
			_mark(img, mask, Rect2i(cx, cy, fw, fh), mark)
	out.images[stem + ".png"] = img
	spec.file = stem + ".png"
	if mask != null:
		out.images[stem + "_mask.png"] = mask
		spec.mask = stem + "_mask.png"
	spec.erase("alive_sheets")   # alive-count sheets are not carried over (single figure)


## A new sheet whose columns are the source frames `from` (by name), named `names`, marked per cell.
static func _relay(out: Dictionary, spec: Dictionary, group: String, stem: String, from: Array, names: Array, mark: String) -> Dictionary:
	var fw := int(spec.fw)
	var fh := int(spec.fh)
	var fac := int(spec.facings)
	var src := _load(_src(group, String(spec.file)))
	var smask: Image = _load(_src(group, String(spec.mask))) if spec.has("mask") else null
	var img := Image.create(fw * names.size(), fh * fac, false, Image.FORMAT_RGBA8)
	var mask: Image = Image.create(fw * names.size(), fh * fac, false, Image.FORMAT_RGBA8) if smask != null else null
	var sf: Array = spec.frames
	for i in names.size():
		var col := maxi(0, sf.find(String(from[i])))
		for r in fac:
			img.blit_rect(src, Rect2i(col * fw, r * fh, fw, fh), Vector2i(i * fw, r * fh))
			if mask != null:
				mask.blit_rect(smask, Rect2i(col * fw, r * fh, fw, fh), Vector2i(i * fw, r * fh))
			_mark(img, mask, Rect2i(i * fw, r * fh, fw, fh), mark)
	out.images[stem + ".png"] = img
	var e := {"facings": fac, "fw": fw, "fh": fh, "pivot": spec.pivot, "frames": names, "file": stem + ".png"}
	if mask != null:
		out.images[stem + "_mask.png"] = mask
		e["mask"] = stem + "_mask.png"
	return e


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


## Recolour the opaque non-team pixels of a cell: drab = warm paint to olive, earth = packed soil.
static func _tint(img: Image, mask: Image, bb: Rect2i, kind: String) -> void:
	for y in range(bb.position.y, bb.end.y):
		for x in range(bb.position.x, bb.end.x):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			if mask != null and x < mask.get_width() and y < mask.get_height() and mask.get_pixel(x, y).a > 0.5:
				continue
			var l := c.get_luminance()
			if kind == "earth":
				img.set_pixel(x, y, Color(EARTH.r * (0.55 + l), EARTH.g * (0.55 + l), EARTH.b * (0.55 + l), c.a))
			elif c.r > c.g:
				img.set_pixel(x, y, Color(c.g * 0.92, c.r * 0.92, c.b * 0.85, c.a))


static func _band(img: Image, mask: Image, cell: Rect2i, bb: Rect2i, y0: int, h: int, a: Color, b: Color, step: int) -> void:
	for y in range(y0, y0 + h):
		for x in range(bb.position.x, bb.end.x):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and img.get_pixel(x, y).a > 0.5:
				_put(img, mask, cell, x, y, a if ((x + y) / step) % 2 == 0 else b)


static func _mark(img: Image, mask: Image, cell: Rect2i, mark: String) -> void:
	var bb := _bbox(img, cell)
	if bb.size == Vector2i.ZERO:
		return
	var cx := bb.position.x + bb.size.x / 2
	var top := bb.position.y
	var s := maxi(1, bb.size.y / 24)   # scale marks with the figure (icons / units ~1, buildings 2-3)
	match mark:
		"rail":
			# rotary cluster: three hot rings stacked on the upper body, bright core pixels
			for i in 3:
				var yy := top + bb.size.y / 5 + i * 3 * s
				for dx in range(-3 * s, 3 * s + 1):
					_put(img, mask, cell, cx + dx, yy, HOT if absi(dx) > s else HOT_L)
		"laser":
			for dy in range(-s, s + 1):
				for dx in range(-s, s + 1):
					_put(img, mask, cell, cx + dx, top + 2 * s + dy, CYAN_L if dx == 0 and dy == 0 else CYAN)
			_band(img, mask, cell, bb, top + bb.size.y * 2 / 5, s, CYAN, STEEL, 3)
		"hpm":
			_band(img, mask, cell, bb, top + bb.size.y / 3, maxi(2, s * 2), HAZ_Y, HAZ_K, 2)
			for i in 6 * s:
				_put(img, mask, cell, cx - 3 * s + i, top + s + (i % 2) * s, HAZ_Y)
		"flak":
			_band(img, mask, cell, bb, top + bb.size.y * 2 / 5, maxi(2, s * 2), WHITE, HAZ_K, 2)
			for p in [Vector2i(-4, 1), Vector2i(4, 3)]:
				for dy in range(-s, s + 1):
					for dx in range(-s, s + 1):
						_put(img, mask, cell, cx + p.x * s + dx, top + p.y * s + dy, PUFF)
		"sensor":
			var mt := maxi(cell.position.y, top - 10 * s)
			for y in range(mt, top + bb.size.y / 3):
				_put(img, mask, cell, cx, y, STEEL)
			for dx in range(-3 * s, 3 * s + 1):
				_put(img, mask, cell, cx + dx, mt + s, STEEL_L)
			_put(img, mask, cell, cx, mt, LAMP_G)
			_put(img, mask, cell, cx + 1, mt, LAMP_G)
		"berm":
			_tint(img, mask, bb, "earth")
			for i in range(0, bb.size.x, 4):
				var x := bb.position.x + i
				for y in range(bb.position.y, bb.end.y):
					if img.get_pixel(x, y).a > 0.5:
						_put(img, mask, cell, x, y, GRASS)
						_put(img, mask, cell, x, y - 1, GRASS)
						break
		"shield", "shield_icon":
			var sx := bb.end.x - 1 - (2 if mark == "shield" else 6)
			var sy := bb.position.y + bb.size.y / 3
			var sh := maxi(4, bb.size.y / 2)
			for y in range(sy, sy + sh):
				for dx in range(0, 3 if mark == "shield" else 5):
					_put(img, mask, cell, sx + dx, y, STEEL_L if dx == 0 else STEEL)
		"maint":
			_tint(img, mask, bb, "drab")
			var c := Vector2i(cx, top + bb.size.y / 3)
			for d in range(-2 * s, 2 * s + 1):
				_put(img, mask, cell, c.x + d, c.y, LAMP_G)
				_put(img, mask, cell, c.x, c.y + d, LAMP_G)
		"dozer":
			_tint(img, mask, bb, "drab")
			_band(img, mask, cell, bb, bb.end.y - maxi(3, bb.size.y / 4), 2, HAZ_Y, HAZ_K, 2)
