extends SceneTree
## G7.1 FIRES71: functional art for the FIRES71 LP defs (content/g71/defs_g71_fires.json; roster 5A Q12 / Q16:
## new defs reuse existing art bases where that is exact; functional art at the G7 detail level now, the full roll-out
## waits for the wave-5 look checkpoint).
##   a_g71_fo_team  = the G6 JTAC sheet (assets/art/g6_units, every frame / facing / alive sheet) + a tripod laser
##                    designator set beside the spotter and a whip antenna on his pack: reads as "observer team".
##   a_g71_mlrs     = the G6 MLRS sheet + a yellow / black hazard band across the launcher pods (fuel-air / cluster /
##                    smart rounds) on every frame and facing; same wreck.
##   icons          = the G6 icons + a designator crosshair (FO) / the hazard band (MLRS).
## Overlay pixels are cleared from the team masks, so the marks never take the team tint. Writes its own group
## assets/art/g71_fires/ (manifest.json); never touches another generator's files. Deterministic: re-running
## reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g71_fires.gd                 # writes assets/art/g71_fires/
##   godot --headless --path . -s tools/art/g71_fires.gd -- --out=<abs dir>
const GEN = preload("res://tools/gen_art.gd")
const GROUP := "g71_fires"
const SRC := "res://assets/art/g6_units/"

const STEEL := Color8(52, 56, 54)
const STEEL_L := Color8(96, 102, 98)
const LENS := Color8(226, 70, 52)
const WHIP := Color8(40, 42, 40)
const TIP := Color8(220, 214, 180)
const HAZ_Y := Color8(232, 196, 58)
const HAZ_K := Color8(34, 32, 28)
const COND_K := Color8(30, 34, 38)
const SENSOR := Color8(90, 220, 240)
const WING_W := Color8(236, 238, 232)


func _init() -> void:
	var dir := "res://assets/art/%s/" % GROUP
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			dir = String(a).substr(6)
	var t0 := Time.get_ticks_msec()
	var out := build()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var n := GEN.save(out, dir)
	print("G71_FIRES units=%d icons=%d files=%d ms=%d" % [(out.manifest.infantry as Dictionary).size() + (out.manifest.vehicles as Dictionary).size(), (out.manifest.icons as Dictionary).size(), n, Time.get_ticks_msec() - t0])
	quit()


static func build() -> Dictionary:
	var src: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SRC + "manifest.json"))
	var man := {"version": 1, "tile": [64, 32], "group": GROUP, "infantry": {}, "vehicles": {}, "vehicle_wrecks": {}, "icons": {}}
	var out := {"images": {}, "manifest": man}
	# FO team: every sheet of the JTAC (main + alive-count sheets), designator + antenna on each cell
	var fo: Dictionary = (src.infantry.a_jtac as Dictionary).duplicate(true)
	var fw := int(fo.fw)
	var fh := int(fo.fh)
	_pair(out, fo, "units/a_g71_fo_team", fw, fh, "fo")
	var alive: Dictionary = fo.get("alive_sheets", {})
	for k in alive.keys():
		_pair(out, alive[k], "units/a_g71_fo_team_a%s" % str(k), fw, fh, "fo")
	fo["g71"] = {"base": "a_jtac", "mark": "tripod designator + whip antenna"}
	man.infantry["a_g71_fo_team"] = fo
	# MLRS: hazard band over the pods
	var ml: Dictionary = (src.vehicles.a_mlrs as Dictionary).duplicate(true)
	_pair(out, ml, "units/a_g71_mlrs", int(ml.fw), int(ml.fh), "mlrs")
	ml["g71"] = {"base": "a_mlrs", "mark": "hazard band on the launcher pods"}
	man.vehicles["a_g71_mlrs"] = ml
	var wr: Dictionary = (src.vehicle_wrecks.a_mlrs as Dictionary).duplicate(true)
	var wimg := _load(SRC + String(wr.file))
	out.images["wrecks/a_g71_mlrs_wreck.png"] = wimg
	wr.file = "wrecks/a_g71_mlrs_wreck.png"
	man.vehicle_wrecks["a_g71_mlrs"] = wr
	# CONDUCTOR (B6) = the G5 attack helicopter sheet + a dark command stripe and a cyan chin sensor ball (rotary rail
	# turret); loyal wingman = the G7 strike drone sheet + a white wing band. Shadows / wrecks copied as they are.
	var air_src := {"a_g71_conductor": ["res://assets/art/g5_air/", "a_attack_heli", "cond"], "a_g71_wingman": ["res://assets/art/drone7/", "g7_a_strike_drone", "wing"]}
	for id in ["a_g71_conductor", "a_g71_wingman"]:
		var sd := String(air_src[id][0])
		var sm: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(sd + "manifest.json"))
		var base := String(air_src[id][1])
		var spec: Dictionary = (sm.vehicles[base] as Dictionary).duplicate(true)
		_pair(out, spec, "units/" + id, int(spec.fw), int(spec.fh), String(air_src[id][2]), sd)
		for sk in ["shadow", "shadow_sheet"]:
			if spec.get(sk) is Dictionary and (spec[sk] as Dictionary).has("file"):
				var rel_s := "units/%s_%s.png" % [id, sk]
				out.images[rel_s] = _load(sd + String(spec[sk].file))
				spec[sk].file = rel_s
		spec["g71"] = {"base": base, "mark": String(air_src[id][2])}
		man.vehicles[id] = spec
		if (sm.get("vehicle_wrecks", {}) as Dictionary).has(base):
			var aw: Dictionary = (sm.vehicle_wrecks[base] as Dictionary).duplicate(true)
			out.images["wrecks/%s_wreck.png" % id] = _load(sd + String(aw.file))
			aw.file = "wrecks/%s_wreck.png" % id
			man.vehicle_wrecks[id] = aw
		var ic := _load(sd + String(sm.icons[base]))
		_mark_cell(ic, null, Rect2i(Vector2i.ZERO, ic.get_size()), String(air_src[id][2]))
		out.images["icons/%s.png" % id] = ic
		man.icons[id] = "icons/%s.png" % id
	# icons
	for pair in [["a_g71_fo_team", "a_jtac", "fo_icon"], ["a_g71_mlrs", "a_mlrs", "mlrs"]]:
		var img := _load(SRC + String(src.icons[pair[1]]))
		_mark_cell(img, null, Rect2i(Vector2i.ZERO, img.get_size()), String(pair[2]))
		var rel := "icons/%s.png" % pair[0]
		out.images[rel] = img
		man.icons[pair[0]] = rel
	return out


static func _load(p: String) -> Image:
	var img := Image.load_from_file(p)
	if img == null:
		var tex = load(p)
		img = tex.get_image() if tex != null else Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	return img


## Copies spec.file / spec.mask from the source group into `stem`.png / `stem`_mask.png with the mark drawn on every
## fw x fh cell (and cleared from the mask), then re-points the spec at the new files.
static func _pair(out: Dictionary, spec: Dictionary, stem: String, fw: int, fh: int, mark: String, sdir: String = SRC) -> void:
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


static func _mark_cell(img: Image, mask: Image, cell: Rect2i, mark: String) -> void:
	var bb := _bbox(img, cell)
	if bb.size == Vector2i.ZERO:
		return
	match mark:
		"fo":
			# tripod laser designator right of the figure, feet on the figure's ground line
			var gx := bb.end.x + 2
			var gy := bb.end.y - 1
			for i in 5:
				_put(img, mask, cell, gx - 2 + int(i / 2.0), gy - i, STEEL)
				_put(img, mask, cell, gx + 2 - int(i / 2.0), gy - i, STEEL)
				_put(img, mask, cell, gx, gy - i, STEEL)
			for dx in range(-2, 3):
				for dy in range(-7, -4):
					_put(img, mask, cell, gx + dx, gy + dy, STEEL_L if dy == -7 else STEEL)
			_put(img, mask, cell, gx - 3, gy - 6, LENS)
			# whip antenna up from the pack (left shoulder)
			var ax := bb.position.x + 1
			var ay := bb.position.y + 3
			for i in 7:
				_put(img, mask, cell, ax, ay - i, WHIP)
			_put(img, mask, cell, ax, ay - 7, TIP)
		"fo_icon":
			var c := Vector2i(bb.end.x - 4, bb.position.y + 3)
			for d in range(-3, 4):
				_put(img, mask, cell, c.x + d, c.y, LENS)
				_put(img, mask, cell, c.x, c.y + d, LENS)
			_put(img, mask, cell, c.x, c.y, TIP)
		"mlrs":
			# 2-px hazard band across the upper third of the silhouette (the pods), opaque pixels only
			var y0 := bb.position.y + int(bb.size.y * 0.30)
			for y in range(y0, y0 + 2):
				for x in range(bb.position.x, bb.end.x):
					if img.get_pixel(x, y).a > 0.5:
						var c2 := HAZ_Y if ((x + y) / 2) % 2 == 0 else HAZ_K
						_put(img, mask, cell, x, y, c2)
		"cond":
			# dark command stripe along the body (opaque pixels of one row at 45 %) + cyan chin sensor ball
			var ys := bb.position.y + int(bb.size.y * 0.45)
			for x in range(bb.position.x, bb.end.x):
				if img.get_pixel(x, ys).a > 0.5:
					_put(img, mask, cell, x, ys, COND_K)
			var cx2 := bb.position.x + bb.size.x / 2
			var cy2 := bb.position.y + int(bb.size.y * 0.62)
			for d2 in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				if img.get_pixel(cx2 + d2.x, cy2 + d2.y).a > 0.5:
					_put(img, mask, cell, cx2 + d2.x, cy2 + d2.y, SENSOR)
		"wing":
			# white band across the wings (opaque pixels of one row at 50 %), never over team-colour pixels (the
			# strike drone's tint lives on that row)
			var yw := bb.position.y + bb.size.y / 2
			for x in range(bb.position.x, bb.end.x):
				if img.get_pixel(x, yw).a > 0.5 and (mask == null or mask.get_pixel(x, yw).a < 0.1):
					_put(img, mask, cell, x, yw, WING_W)
