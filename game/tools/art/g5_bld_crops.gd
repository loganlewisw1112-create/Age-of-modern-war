extends RefCounted
## Self-check crops for the G5 building art (agent ART-BLD): zoomed contact sheets on a grass-and-water
## backdrop, written to .plan/shots/ART-BLD/. Not shipped; the generator calls compose() with --crops.
##   bld_<group>.png  each def: built, damaged, build_0..2 (+ variant states) at 2x, team-tinted
##   field_f<f>.png   apron + (f+1) strips laid out with airfield.gd strip_points, a crater + closed X
##   icons.png        every G5 icon at 3x
const P = preload("res://tools/art/pix.gd")
const FX = preload("res://tools/art/fx_ui.gd")
const M = preload("res://tools/art/g5_bld.gd")

const BG := Color8(84, 104, 62)
const BG_WATER := Color8(48, 86, 112)
const TEAMS := [Color(0.36, 0.52, 0.74), Color(0.78, 0.30, 0.26), Color(0.86, 0.72, 0.28)]
const GROUPS := {
	"air_a": ["a_airfield", "a_airstrip", "a_helipad", "a_air_tower", "a_forward_strip", "a_forward_helipad"],
	"air_b": ["b_aerodrome", "b_airstrip", "b_helipad", "b_air_tower", "b_forward_strip", "b_forward_helipad"],
	"hangars": ["a_hangar_light", "a_hangar_heavy", "b_hangar_light", "b_hangar_heavy", "m_drone_bay", "m_launch_rail"],
	"naval": ["a_shipyard", "b_shipyard", "m_shipyard", "a_supply_pier", "b_supply_pier", "m_supply_pier",
		"a_coastal_battery", "b_coastal_battery", "m_coastal_battery"],
	"medical": ["a_hospital", "a_field_hospital", "b_hospital", "b_field_hospital"],
}


static func _tinted(out: Dictionary, st: Dictionary, team: Color) -> Image:
	return FX.tint(out.images[st.file], out.images[st.mask], team)


static func _row_states(entry: Dictionary) -> Array:
	var v := String(entry.g5.variants)
	match v:
		"rot":
			return ["rot_0", "rot_1", "rot_2", "rot_3", "rot_1_damaged", "build_0", "build_1", "build_2"]
		"lvl":
			return ["lvl_0", "lvl_1", "lvl_2", "lvl_3", "lvl_0_damaged", "lvl_3_damaged", "build_1", "build_2"]
		"water":
			return ["water_0", "water_1", "water_2", "water_3", "water_0_damaged", "build_0", "build_1", "build_2"]
	return ["built", "damaged", "build_0", "build_1", "build_2"]


static func compose(out: Dictionary, dir: String) -> int:
	DirAccess.make_dir_recursive_absolute(dir)
	var n := 0
	var man: Dictionary = out.manifest.buildings
	for g in GROUPS:
		var rows: Array = []
		var wmax := 0
		var htot := 0
		for def in GROUPS[g]:
			var e: Dictionary = man[def]
			var imgs: Array = []
			var rw := 0
			var rh := 0
			var k := 0
			for st in _row_states(e):
				var im := _tinted(out, e.states[st], TEAMS[k % 3] if st.begins_with("build") == false else TEAMS[0])
				imgs.append(im)
				rw += im.get_width() + 4
				rh = maxi(rh, im.get_height())
				k += 1
			rows.append([imgs, rh, String(e.g5.variants) == "water"])
			wmax = maxi(wmax, rw)
			htot += rh + 4
		var sheet := Image.create(wmax + 4, htot + 4, false, Image.FORMAT_RGBA8)
		sheet.fill(BG)
		var y := 4
		for r in rows:
			var x := 4
			for im in r[0]:
				if r[2]:
					sheet.fill_rect(Rect2i(x, y, im.get_width(), r[1]), BG_WATER)
				P.paste(sheet, im, x, y + int(r[1]) - im.get_height())
				x += im.get_width() + 4
			y += int(r[1]) + 4
		sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
		sheet.save_png(dir.path_join("bld_%s.png" % g))
		n += 1
	for f in 4:
		_field(out, dir, "a_airfield" if f % 2 == 0 else "b_aerodrome", f, f + 1)
		n += 1
	_field(out, dir, "m_launch_rail", 1, 3, "field_rail.png")
	_field(out, dir, "a_forward_strip", 2, 1, "field_fwd.png")
	n += 2
	n += _icons(out, dir)
	n += _zoom(out, dir)
	return n


## 4x zoom of each def: built, damaged and its most detailed variant (lvl_3 / rot_1 / water_2).
static func _zoom(out: Dictionary, dir: String) -> int:
	var n := 0
	for def in out.manifest.buildings:
		var e: Dictionary = out.manifest.buildings[def]
		var sts := ["built", "damaged"]
		match String(e.g5.variants):
			"lvl":
				sts.append_array(["lvl_3", "lvl_3_damaged"])
			"rot":
				sts.append("rot_1")
			"water":
				sts.append("water_2")
		var ims: Array = []
		var w := 4
		var h := 0
		for st in sts:
			var im := _tinted(out, e.states[st], TEAMS[0])
			ims.append(im)
			w += im.get_width() + 4
			h = maxi(h, im.get_height())
		var sheet := Image.create(w, h + 8, false, Image.FORMAT_RGBA8)
		sheet.fill(BG_WATER if String(e.g5.variants) == "water" else BG)
		var x := 4
		for im in ims:
			P.paste(sheet, im, x, 4 + h - im.get_height())
			x += im.get_width() + 4
		var z := 4 if w < 700 else 2
		sheet.resize(sheet.get_width() * z, sheet.get_height() * z, Image.INTERPOLATE_NEAREST)
		sheet.save_png(dir.path_join("zoom_%s.png" % def))
		n += 1
	return n


## Apron + `strips` strips for facing f, composed exactly like the renderer should (manifest layout).
static func _field(out: Dictionary, dir: String, def: String, f: int, strips: int, name := "") -> void:
	var e: Dictionary = out.manifest.buildings[def]
	var size: int = e.size
	var air: Dictionary = out.manifest.airfield
	var style: String = air.styles[def]
	var segs: Dictionary = air.segments[style][str(f)]
	var lens := {"a_airfield": 26, "b_aerodrome": 26, "m_launch_rail": 12, "a_forward_strip": 10}
	var slen: int = lens[def]
	var sheet := Image.create(1900, 1100, false, Image.FORMAT_RGBA8)
	sheet.fill(BG)
	var axis: Vector2 = M.K.AX[f]
	var perp := Vector2(-axis.y, axis.x)
	var mid := axis * (slen * 0.5 - size * 0.5) + perp * (size * 0.5 + 2.0 * strips) * 0.5
	var org := Vector2(950, 560) - P.proj(Vector2.ZERO, Vector3(mid.x, mid.y, 0))
	var items: Array = []
	for k in strips:
		var start := perp * (size * 0.5 + 1.5 + 4.0 * k) - axis * size * 0.5
		for i in slen:
			var kind := "start" if i == 0 else ("end" if i == slen - 1 else "mid")
			items.append([start + axis * (i + 0.5), segs[kind]])
		if k > 0:
			for i in size:
				items.append([perp * (size * 0.5 + 4.0 * k - 0.5) - axis * (size * 0.5 - 0.5 - i), segs.link])
		if k == strips - 1 and strips > 1:
			items.append([start + axis * 6.5, air.craters[k % 3]])
			items.append([start + axis * 1.5, air.closed[str(f)]])
			items.append([start + axis * (slen - 1.5), air.closed[str(f)]])
		if k == 0:
			items.append([start + axis * 9.5, air.craters_repair[0]])
	for i in items.size():
		var ov := String(items[i][1].file).contains("crater") or String(items[i][1].file).contains("closed")
		items[i].append(float(items[i][0].x + items[i][0].y) + (100.0 if ov else 0.0))
	items.sort_custom(func(a, b): return float(a[2]) < float(b[2]))
	for it in items:
		var s: Vector2 = P.proj(org, Vector3(it[0].x, it[0].y, 0))
		var im: Image = out.images[it[1].file]
		P.paste(sheet, im, int(s.x) - int(it[1].pivot[0]), int(s.y) - int(it[1].pivot[1]))
	var st: Dictionary = e.states["rot_%d" % f]
	var bim := _tinted(out, st, TEAMS[f % 3])
	P.paste(sheet, bim, int(org.x) - int(e.pivot[0]), int(org.y) - int(e.pivot[1]))
	sheet.save_png(dir.path_join(name if name != "" else "field_f%d.png" % f))


static func _icons(out: Dictionary, dir: String) -> int:
	var ids: Array = out.manifest.icons.keys()
	ids.sort()
	var cols := 16
	var sheet := Image.create(cols * 34 + 2, (ids.size() / cols + 1) * 34 + 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(20, 20, 18))
	for i in ids.size():
		var im: Image = out.images[out.manifest.icons[ids[i]]]
		sheet.blit_rect(im, Rect2i(0, 0, 32, 32), Vector2i(2 + (i % cols) * 34, 2 + (i / cols) * 34))
	sheet.resize(sheet.get_width() * 3, sheet.get_height() * 3, Image.INTERPOLATE_NEAREST)
	sheet.save_png(dir.path_join("icons.png"))
	return 1
