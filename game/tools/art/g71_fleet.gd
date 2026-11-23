extends SceneTree
## G7.1 FLEET71: functional art for the robot fleet defs (content/g71/defs_g71_fleet.json; scope F1).
## Clones human / robot / vehicle bases from g5 / g6 / g7 with distinctive marks per role:
##   g71_wall_sentinel = G7 sent_gunner (upright wall fighter) + cyan optic + steel spine stripe
##   g71_robot_dog     = G7 packhunter quadruped + Human A drab + teal collar / ear tip
##   g71_ugv_mg        = G6 a_ugv + olive track band + hot MG tip
##   g71_robot_mule    = G5 ambulance + cargo crate band on the hull
##   g71_hunter_tank   = G6 laser tank + dark chassis band + red hunter optic
##   g71_ucav          = G7 strike drone + white wing band + hardpoint tip (air)
##   g71_ew_drone      = G5 EMP drone + violet EW dish / antenna
##   g71_purge_bot     = G5 maint swarm + drab + orange purge nozzle
## Overlay pixels are cleared from team masks (marks never take the team tint). Writes its own group
## assets/art/g71_fleet/ (manifest.json) only. Deterministic: re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g71_fleet.gd                 # writes assets/art/g71_fleet/
##   godot --headless --path . -s tools/art/g71_fleet.gd -- --out=<abs dir>
const GEN = preload("res://tools/gen_art.gd")
const GROUP := "g71_fleet"
const ART := "res://assets/art/"

const STEEL := Color8(52, 56, 54)
const STEEL_L := Color8(112, 118, 112)
const CYAN := Color8(80, 220, 255)
const CYAN_L := Color8(210, 248, 255)
const TEAL := Color8(48, 168, 150)
const TEAL_D := Color8(28, 96, 88)
const OLIVE := Color8(96, 118, 58)
const OLIVE_K := Color8(40, 46, 30)
const HOT := Color8(255, 214, 120)
const HOT_O := Color8(222, 110, 34)
const HUNT_K := Color8(28, 30, 34)
const HUNT_R := Color8(220, 48, 40)
const WING_W := Color8(236, 238, 232)
const EW_V := Color8(160, 96, 220)
const EW_L := Color8(210, 180, 255)
const CRATE := Color8(138, 112, 72)
const CRATE_K := Color8(60, 48, 32)
const PURGE := Color8(255, 150, 40)
const PURGE_L := Color8(255, 220, 120)

## def -> [source group, category, base id, mark, manifest bucket]
## bucket: infantry | vehicles (air units land in vehicles like conductor / wingman).
const FLEET := {
	"g71_wall_sentinel": ["g7_sentinels", "infantry", "g7_sent_gunner", "sentinel", "infantry"],
	"g71_robot_dog": ["g7_threats", "vehicles", "g7_m_packhunter", "dog", "vehicles"],
	"g71_ugv_mg": ["g6_units", "vehicles", "a_ugv", "ugv", "vehicles"],
	"g71_robot_mule": ["g5_units", "vehicles", "a_ambulance", "mule", "vehicles"],
	"g71_hunter_tank": ["g6_units", "vehicles", "a_laser_tank", "hunter", "vehicles"],
	"g71_ucav": ["drone7", "vehicles", "g7_a_strike_drone", "ucav", "vehicles"],
	"g71_ew_drone": ["g5_units", "vehicles", "a_drone_emp", "ew", "vehicles"],
	"g71_purge_bot": ["g5_units", "vehicles", "m_maint_swarm", "purge", "vehicles"],
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
	var u := (out.manifest.infantry as Dictionary).size() + (out.manifest.vehicles as Dictionary).size()
	print("G71_FLEET units=%d icons=%d files=%d ms=%d" % [u, (out.manifest.icons as Dictionary).size(), n, Time.get_ticks_msec() - t0])
	quit()


static func _man(group: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ART + group + "/manifest.json"))


static func _src(group: String, rel: String) -> String:
	return rel if rel.begins_with("res://") else ART + group + "/" + rel


static func build() -> Dictionary:
	var man := {"version": 1, "tile": [64, 32], "group": GROUP, "infantry": {}, "vehicles": {}, "vehicle_wrecks": {}, "icons": {}}
	var out := {"images": {}, "manifest": man}
	var mans := {}
	var ids: Array = FLEET.keys()
	ids.sort()
	for def in ids:
		var row: Array = FLEET[def]
		var g := String(row[0])
		var cat := String(row[1])
		var base := String(row[2])
		var mk := String(row[3])
		var bucket := String(row[4])
		if not mans.has(g):
			mans[g] = _man(g)
		var src: Dictionary = mans[g]
		var spec: Dictionary = (src[cat][base] as Dictionary).duplicate(true)
		_pair(out, spec, g, "units/" + def, int(spec.fw), int(spec.fh), mk)
		for sk in ["shadow", "shadow_sheet"]:
			if spec.get(sk) is Dictionary and (spec[sk] as Dictionary).has("file"):
				var rel_s := "units/%s_%s.png" % [def, sk]
				out.images[rel_s] = _load(_src(g, String(spec[sk].file)))
				spec[sk].file = rel_s
		spec["g71"] = {"base": base, "mark": mk, "src_group": g}
		man[bucket][def] = spec
		# wreck: copy source wreck when present, else a single damaged / die cell (fleet leaves_wreck)
		var wr_src: Dictionary = (src.get("vehicle_wrecks", {}) as Dictionary)
		if wr_src.has(base):
			var wr: Dictionary = (wr_src[base] as Dictionary).duplicate(true)
			out.images["wrecks/%s_wreck.png" % def] = _load(_src(g, String(wr.file)))
			wr.file = "wrecks/%s_wreck.png" % def
			man.vehicle_wrecks[def] = wr
		else:
			man.vehicle_wrecks[def] = _wreck_from_sheet(out, spec, g, def, mk)
		var ic_path := String((src.icons as Dictionary).get(base, ""))
		if ic_path != "":
			var ic := _load(_src(g, ic_path))
			_mark_cell(ic, null, Rect2i(Vector2i.ZERO, ic.get_size()), mk)
			out.images["icons/%s.png" % def] = ic
			man.icons[def] = "icons/%s.png" % def
	return out


## Build a 1-cell wreck from the marked sheet's damaged / die / recoil column when the source has no wreck.
static func _wreck_from_sheet(out: Dictionary, spec: Dictionary, _group: String, def: String, _mark: String) -> Dictionary:
	var fw := int(spec.fw)
	var fh := int(spec.fh)
	var frames: Array = spec.get("frames", [])
	var col := 0
	for name in ["damaged", "die", "die_0", "die_1", "recoil"]:
		var i := frames.find(name)
		if i >= 0:
			col = i
			break
	var sheet: Image = out.images.get("units/%s.png" % def)
	if sheet == null:
		sheet = Image.create(fw, fh, false, Image.FORMAT_RGBA8)
	var wreck := Image.create(fw, fh, false, Image.FORMAT_RGBA8)
	wreck.blit_rect(sheet, Rect2i(col * fw, 0, fw, fh), Vector2i.ZERO)
	var rel := "wrecks/%s_wreck.png" % def
	out.images[rel] = wreck
	return {"file": rel, "fw": fw, "fh": fh, "pivot": spec.get("pivot", [fw / 2, fh - 4])}


static func _load(p: String) -> Image:
	var img := Image.load_from_file(p)
	if img == null:
		var tex = load(p)
		img = tex.get_image() if tex != null else Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	return img


static func _pair(out: Dictionary, spec: Dictionary, group: String, stem: String, fw: int, fh: int, mark: String) -> void:
	var img := _load(_src(group, String(spec.file)))
	var mask: Image = _load(_src(group, String(spec.mask))) if spec.has("mask") else null
	for cy in range(0, img.get_height() - fh + 1, fh):
		for cx in range(0, img.get_width() - fw + 1, fw):
			_mark_cell(img, mask, Rect2i(cx, cy, fw, fh), mark)
	out.images[stem + ".png"] = img
	spec.file = stem + ".png"
	if mask != null:
		out.images[stem + "_mask.png"] = mask
		spec.mask = stem + "_mask.png"
	spec.erase("alive_sheets")


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


static func _tint_drab(img: Image, mask: Image, bb: Rect2i) -> void:
	for y in range(bb.position.y, bb.end.y):
		for x in range(bb.position.x, bb.end.x):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			if mask != null and x < mask.get_width() and y < mask.get_height() and mask.get_pixel(x, y).a > 0.5:
				continue
			if c.r > c.g:
				img.set_pixel(x, y, Color(c.g * 0.92, c.r * 0.92, c.b * 0.85, c.a))


static func _band(img: Image, mask: Image, cell: Rect2i, bb: Rect2i, y0: int, h: int, a: Color, b: Color, step: int) -> void:
	for y in range(y0, y0 + h):
		for x in range(bb.position.x, bb.end.x):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and img.get_pixel(x, y).a > 0.5:
				_put(img, mask, cell, x, y, a if ((x + y) / step) % 2 == 0 else b)


static func _mark_cell(img: Image, mask: Image, cell: Rect2i, mark: String) -> void:
	var bb := _bbox(img, cell)
	if bb.size == Vector2i.ZERO:
		return
	var cx := bb.position.x + bb.size.x / 2
	var top := bb.position.y
	match mark:
		"sentinel":
			# upright cue: steel spine stripe down the torso + cyan optic on the head
			var xs := cx
			for y in range(top + bb.size.y / 5, top + int(bb.size.y * 0.72)):
				if img.get_pixel(xs, y).a > 0.5:
					_put(img, mask, cell, xs, y, STEEL if y % 2 == 0 else STEEL_L)
			var ey := top + maxi(2, bb.size.y / 8)
			for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				_put(img, mask, cell, cx + d.x, ey + d.y, CYAN_L if d == Vector2i(0, 0) else CYAN)
		"dog":
			# quadruped already (packhunter); drab chrome + teal collar band + ear tip
			_tint_drab(img, mask, bb)
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.28), 2, TEAL, TEAL_D, 2)
			_put(img, mask, cell, bb.end.x - 2, top + 2, TEAL)
			_put(img, mask, cell, bb.end.x - 1, top + 1, TEAL)
		"ugv":
			# tracked cue: olive / black band across the lower hull + hot MG tip at the front
			_band(img, mask, cell, bb, bb.end.y - maxi(3, bb.size.y / 4), 2, OLIVE, OLIVE_K, 2)
			var ty := top + int(bb.size.y * 0.40)
			for x in range(bb.end.x - 1, bb.position.x, -1):
				if img.get_pixel(x, ty).a > 0.5:
					_put(img, mask, cell, x, ty, HOT)
					_put(img, mask, cell, x - 1, ty, HOT_O)
					break
		"mule":
			# cargo crate band across the upper hull
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.32), 3, CRATE, CRATE_K, 3)
			for dx in range(-2, 3):
				_put(img, mask, cell, cx + dx, top + int(bb.size.y * 0.22), CRATE_K)
		"hunter":
			# dark chassis band + red hunter optic (Terminator / Skynet cue on the laser-tank hull)
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.55), 2, HUNT_K, STEEL, 2)
			var hy := top + int(bb.size.y * 0.30)
			for d2 in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				_put(img, mask, cell, cx + d2.x, hy + d2.y, HUNT_R)
		"ucav":
			# air: white wing band + hardpoint tip mid-fuselage
			var yw := top + bb.size.y / 2
			for x in range(bb.position.x, bb.end.x):
				if img.get_pixel(x, yw).a > 0.5 and (mask == null or mask.get_pixel(x, yw).a < 0.1):
					_put(img, mask, cell, x, yw, WING_W)
			_put(img, mask, cell, cx, yw + 2, HOT_O)
			_put(img, mask, cell, cx + 1, yw + 2, HOT)
		"ew":
			# violet EW dish / antenna above the fuselage
			var ay := top + maxi(1, bb.size.y / 10)
			for i in 5:
				_put(img, mask, cell, cx, ay + i, STEEL)
			for dx in range(-3, 4):
				_put(img, mask, cell, cx + dx, ay, EW_V if absi(dx) < 2 else EW_L)
			_put(img, mask, cell, cx, ay - 1, EW_L)
		"purge":
			# drab swarm body + orange purge nozzle tip
			_tint_drab(img, mask, bb)
			var py := top + int(bb.size.y * 0.45)
			for x in range(bb.end.x - 1, bb.position.x, -1):
				if img.get_pixel(x, py).a > 0.5:
					_put(img, mask, cell, x, py, PURGE_L)
					_put(img, mask, cell, x - 1, py, PURGE)
					_put(img, mask, cell, x - 2, py + 1, PURGE)
					break
