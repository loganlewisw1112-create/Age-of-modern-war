extends RefCounted
## Self-check contact sheets for the G6 art (owner: ART-G6). One PNG per chunk of ids, team-tinted on a flat
## field colour, nearest-neighbour 2x where the row fits 1800 px:
##   units_<n>.png  per unit two rows: all 8 facings of frame 0 (+ the wreck at facing 0), then all 8 facings of
##                  the last frame (fire / work / special state)
##   bld_<n>.png    per building one row: built rot_0..3, rot_0 damaged, rot_1 damaged, rot_0 build_0..2
const H = preload("res://tools/art/g6_lib.gd")
const M = preload("res://tools/art/g6_art.gd")
const FIELD := Color8(84, 96, 70)
const CHUNK := 5
## Polish evidence (PLAN_G6 s3): zoom_<id>_<frame>.png = all 8 facings of one frame, 2 rows of 4, 2x.
const ZOOM := [["a_hovercraft", "loaded"], ["a_hovercraft", "unload"], ["a_supply_ship_a", "work"],
	["b_supply_ship_b", "move"], ["b_supply_ship_b", "idle"], ["b_conscripts", "charge"]]


static func compose(uo: Dictionary, bo: Dictionary, dir: String) -> int:
	DirAccess.make_dir_recursive_absolute(dir)
	var n := 0
	var ids: Array = []
	for id in M.UNITS:
		if _unit(uo, id).size() > 0:
			ids.append(id)
	for c in range(0, ids.size(), CHUNK):
		var rows: Array = []
		for id in ids.slice(c, c + CHUNK):
			rows.append_array(_unit_rows(uo, id))
		_sheet(rows).save_png(dir.path_join("units_%d.png" % (c / CHUNK)))
		n += 1
	var bids: Array = []
	for id in M.BLDS:
		if bo.manifest.get("buildings", {}).has(id):
			bids.append(id)
	for c in range(0, bids.size(), CHUNK):
		var rows: Array = []
		for id in bids.slice(c, c + CHUNK):
			var st: Dictionary = bo.manifest.buildings[id].states
			var row: Array = []
			for nm in ["rot_0", "rot_1", "rot_2", "rot_3", "rot_0_damaged", "rot_1_damaged", "rot_0_build_0", "rot_0_build_1", "rot_0_build_2"]:
				row.append(H.tint(bo.images[st[nm].file], bo.images[st[nm].mask], H.TEAM))
			rows.append(row)
		_sheet(rows).save_png(dir.path_join("bld_%d.png" % (c / CHUNK)))
		n += 1
	for z in ZOOM:
		var e := _unit(uo, z[0])
		var col: int = (e.get("frames", []) as Array).find(z[1])
		if col < 0:
			continue
		var r2: Array = [[], []]
		for k in 8:
			r2[k / 4].append(H.tint(H.frame(uo.images[e.file], e.fw, e.fh, col, k), H.frame(uo.images[e.mask], e.fw, e.fh, col, k), H.TEAM))
		var zi := _sheet(r2)
		if zi.get_width() <= 900:
			zi.resize(zi.get_width() * 2, zi.get_height() * 2, Image.INTERPOLATE_NEAREST)
		zi.save_png(dir.path_join("zoom_%s_%s.png" % [z[0], z[1]]))
		n += 1
	return n


static func _unit(uo: Dictionary, id: String) -> Dictionary:
	return uo.manifest.get("infantry", {}).get(id, uo.manifest.get("vehicles", {}).get(id, {}))


static func _unit_rows(uo: Dictionary, id: String) -> Array:
	var e := _unit(uo, id)
	var sheet: Image = uo.images[e.file]
	var mask: Image = uo.images[e.mask]
	var fw: int = e.fw
	var fh: int = e.fh
	var last: int = (e.frames as Array).size() - 1
	var a: Array = []
	var b: Array = []
	for k in 8:
		a.append(H.tint(H.frame(sheet, fw, fh, 0, k), H.frame(mask, fw, fh, 0, k), H.TEAM))
		b.append(H.tint(H.frame(sheet, fw, fh, last, k), H.frame(mask, fw, fh, last, k), H.TEAM))
	var wr: Dictionary = uo.manifest.get("vehicle_wrecks", {}).get(id, {})
	if not wr.is_empty():
		a.append(H.frame(uo.images[wr.file], int(wr.fw), int(wr.fh), 0, 0))
	return [a, b]


static func _sheet(rows: Array) -> Image:
	var cw := 1
	var ch := 1
	var ncol := 1
	for row in rows:
		ncol = maxi(ncol, (row as Array).size())
		for im: Image in row:
			cw = maxi(cw, im.get_width())
			ch = maxi(ch, im.get_height())
	var img := Image.create(ncol * (cw + 2), rows.size() * (ch + 2), false, Image.FORMAT_RGBA8)
	img.fill(FIELD)
	for r in rows.size():
		for c in (rows[r] as Array).size():
			var im: Image = rows[r][c]
			img.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(c * (cw + 2) + (cw - im.get_width()) / 2, r * (ch + 2) + ch - im.get_height()))
	if img.get_width() * 2 <= 1800:
		img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	return img
