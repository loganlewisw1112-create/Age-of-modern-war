extends RefCounted
## ART-F contact sheet (.plan/shots/ART-F/fort.png): per faction a drawn 7x5 wall ring with towers on
## the corners, a closed gate (north side), an open gate (south side) and one damaged segment, laid out
## exactly like the renderer places size-1 buildings (cell centre = world_to_screen(cell + 0.5)); under
## that, every conn_0..15 wall state, gate open/closed/damaged, construction stages and the icons.
## Works from an in-memory generator output (gen_art.generate or g4_fort.build), so no import needed.
const P = preload("res://tools/art/pix.gd")
const FX = preload("res://tools/art/fx_ui.gd")
const F4 = preload("res://tools/art/g4_fort.gd")

const FACTIONS := [["a_wall", "a_gate", "a_wall_tower", "#4f7db0"], ["b_wall", "b_gate", "b_wall_tower", "#b5583a"],
	["m_barrier", "m_field_gate", "m_spire", "#8a62c4"]]
const RW := 7
const RH := 5


## Ring layout: cell -> [def index 0 wall / 1 gate / 2 tower, variant suffix]
static func ring() -> Dictionary:
	var cells := {}
	for x in RW:
		for y in RH:
			if x != 0 and y != 0 and x != RW - 1 and y != RH - 1:
				continue
			cells[Vector2i(x, y)] = [0, ""]
	for c in [Vector2i(0, 0), Vector2i(RW - 1, 0), Vector2i(0, RH - 1), Vector2i(RW - 1, RH - 1)]:
		cells[c] = [2, ""]
	cells[Vector2i(3, 0)] = [1, ""]
	cells[Vector2i(3, RH - 1)] = [1, "_open"]
	cells[Vector2i(RW - 1, 2)] = [0, "_damaged"]
	cells[Vector2i(0, 2)] = [2, ""]
	return cells


static func mask_at(cells: Dictionary, c: Vector2i) -> int:
	var m := 0
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for i in 4:
		if cells.has(c + dirs[i]):
			m |= 1 << i
	return m


static func _state_img(out: Dictionary, def: String, st: String, col: Color) -> Image:
	var s: Dictionary = out.manifest.buildings[def].states[st]
	return FX.tint(out.images[String(s.file)], out.images[String(s.mask)], col)


static func _ground(img: Image, org: Vector2i, c: Vector2i, k: int) -> void:
	var g := Color8(86, 104, 62) if (c.x + c.y + k) % 2 == 0 else Color8(80, 98, 58)
	var sx := org.x + (c.x - c.y) * 32
	var sy := org.y + (c.x + c.y) * 16
	for y in 32:
		var hw := P.diamond_hw(y)
		for x in range(32 - hw, 32 + hw):
			var px := sx - 32 + x
			var py := sy + y
			if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
				img.set_pixel(px, py, g)


static func compose(out: Dictionary, path: String) -> void:
	var img := Image.create(1420, 760, false, Image.FORMAT_RGBA8)
	img.fill(Color8(38, 40, 38))
	var cells := ring()
	for f in 3:
		var fac: Array = FACTIONS[f]
		var col := Color(String(fac[3]))
		var org := Vector2i(30 + f * 420 + (RH - 1) * 32 + 8, 80)
		for x in range(-1, RW + 1):
			for y in range(-1, RH + 1):
				_ground(img, org, Vector2i(x, y), 0)
		var keys: Array = cells.keys()
		keys.sort_custom(func(a, b): return a.x + a.y < b.x + b.y or (a.x + a.y == b.x + b.y and a.x < b.x))
		for c in keys:
			var spec: Array = cells[c]
			var def: String = fac[spec[0]]
			var st := "conn_%d%s" % [mask_at(cells, c), spec[1]]
			var e: Dictionary = out.manifest.buildings[def]
			var si := _state_img(out, def, st, col)
			var cx: int = org.x + (c.x - c.y) * 32
			var cy: int = org.y + (c.x + c.y) * 16 + 16
			P.paste(img, si, cx - int(e.pivot[0]), cy - int(e.pivot[1]))
	var y0 := 330
	for f in 3:
		var fac: Array = FACTIONS[f]
		var col := Color(String(fac[3]))
		var row := y0 + f * 142
		for m in 16:
			_cellpaste(img, out, fac[0], "conn_%d" % m, col, 8 + m * 78, row)
		var extra := [[fac[1], "conn_10"], [fac[1], "conn_10_open"], [fac[1], "conn_5"], [fac[1], "conn_5_open"],
			[fac[1], "conn_10_damaged"], [fac[2], "conn_0"], [fac[2], "conn_15"], [fac[2], "conn_15_damaged"],
			[fac[0], "build_0"], [fac[0], "build_1"], [fac[0], "build_2"], [fac[2], "build_1"], [fac[1], "build_2"],
			[fac[0], "conn_5_damaged"]]
		for k in extra.size():
			_cellpaste(img, out, extra[k][0], extra[k][1], col, 8 + k * 78, row + 66)
		for k in 3:
			P.paste(img, out.images["icons/%s.png" % fac[k]], 8 + (extra.size() + k) * 78 + 20, row + 100)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)


static func _cellpaste(img: Image, out: Dictionary, def: String, st: String, col: Color, x: int, y: int) -> void:
	var si := _state_img(out, def, st, col)
	var e: Dictionary = out.manifest.buildings[def]
	# bottom-align on a shared ground line (pivot y differs per def)
	P.paste(img, si, x, y + 70 - int(e.pivot[1]) - 16)
