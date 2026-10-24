extends SceneTree
## ART4 visual QA (not a gen_art module): builds the G3b modules in memory and writes 2x contact sheets
## to .plan/shots/ART4/. Run: godot --headless --path . -s tools/art/g3b_contact.gd [-- --manifest]
## With --manifest it reads the shipped assets/generated files instead (post-generation check).
const P = preload("res://tools/art/pix.gd")
const FX = preload("res://tools/art/fx_ui.gd")
const G3B = preload("res://tools/art/g3b.gd")

const BG := Color(0.27, 0.31, 0.2, 1)
const BLUE := Color("#4f7db0")
const RED := Color("#b5583a")
const UNIT_GROUPS := {
	"human_a": ["a_old_tank", "a_guided_arty", "a_ew_truck", "a_uav"],
	"human_b": ["b_field_gun", "b_radar_aa", "b_jammer_truck", "b_guided_battery"],
	"machine": ["m_siege_crawler", "m_swarm", "m_ew_node", "m_lancer"],
}


func _init() -> void:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32]}}
	G3B.build(out)
	var dir := ProjectSettings.globalize_path("res://.plan/shots/ART4/")
	DirAccess.make_dir_recursive_absolute(dir)
	for g in UNIT_GROUPS:
		var ids: Array = []
		for id in UNIT_GROUPS[g]:
			if out.manifest.get("vehicles", {}).has(id) or out.manifest.get("infantry", {}).has(id):
				ids.append(id)
		if not ids.is_empty():
			_units(out, ids).save_png(dir.path_join("units_%s.png" % g))
			print("CONTACT units_%s (%d)" % [g, ids.size()])
	if out.manifest.has("buildings"):
		_buildings(out).save_png(dir.path_join("buildings.png"))
		print("CONTACT buildings")
	if out.manifest.has("poi_decor"):
		_decor(out).save_png(dir.path_join("decor.png"))
		print("CONTACT decor")
	_icons(out).save_png(dir.path_join("icons_lod.png"))
	print("CONTACT icons_lod")
	quit(0)


static func _spec(out: Dictionary, id: String) -> Dictionary:
	return out.manifest.get("infantry", {}).get(id, out.manifest.get("vehicles", {}).get(id, {}))


static func _x2(img: Image) -> Image:
	var c: Image = img.duplicate()
	c.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	return c


## One row per unit: 8 idle facings (blue), then move/fire of facing 1, the red idle, the wreck,
## the air shadow (if any). 2x nearest.
static func _units(out: Dictionary, ids: Array) -> Image:
	var cw := 0
	var ch := 0
	for id in ids:
		cw = maxi(cw, int(_spec(out, id).fw))
		ch = maxi(ch, int(_spec(out, id).fh))
	var img := Image.create(cw * 2 * 13, ch * 2 * ids.size(), false, Image.FORMAT_RGBA8)
	img.fill(BG)
	for i in ids.size():
		var sp := _spec(out, ids[i])
		var fw: int = sp.fw
		var fh: int = sp.fh
		var blue: Image = FX.tint(out.images[sp.file], out.images[sp.mask], BLUE)
		var red: Image = FX.tint(out.images[sp.file], out.images[sp.mask], RED)
		var cells: Array = []
		for k in 8:
			cells.append(blue.get_region(Rect2i(0, k * fh, fw, fh)))
		for f in range(1, sp.frames.size()):
			cells.append(blue.get_region(Rect2i(f * fw, fh, fw, fh)))
		cells.append(red.get_region(Rect2i(0, fh, fw, fh)))
		var wr: Dictionary = out.manifest.get("vehicle_wrecks", {}).get(ids[i], {})
		if not wr.is_empty():
			cells.append((out.images[wr.file] as Image).get_region(Rect2i(0, fh, fw, fh)))
		if sp.has("shadow"):
			cells.append(out.images[sp.shadow.file])
		for c in cells.size():
			P.paste(img, _x2(cells[c]), c * cw * 2, i * ch * 2)
	return img


static func _buildings(out: Dictionary) -> Image:
	var ids: Array = out.manifest.buildings.keys()
	var cw := 0
	var ch := 0
	for id in ids:
		var b: Image = out.images[out.manifest.buildings[id].states.built.file]
		cw = maxi(cw, b.get_width())
		ch = maxi(ch, b.get_height())
	var img := Image.create(cw * 5, ch * ids.size(), false, Image.FORMAT_RGBA8)
	img.fill(BG)
	for i in ids.size():
		var st: Dictionary = out.manifest.buildings[ids[i]].states
		var n := 0
		for s in ["built", "build_0", "build_1", "build_2"]:
			P.paste(img, FX.tint(out.images[st[s].file], out.images[st[s].mask], BLUE), n * cw, i * ch)
			n += 1
		P.paste(img, FX.tint(out.images[st.built.file], out.images[st.built.mask], RED), n * cw, i * ch)
	return img


static func _decor(out: Dictionary) -> Image:
	var ids: Array = out.manifest.poi_decor.keys()
	var img := Image.create(1400, 900, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	var x := 0
	var y := 0
	var rowh := 0
	for id in ids:
		var d: Image = out.images[out.manifest.poi_decor[id].file]
		if x + d.get_width() > 1400:
			x = 0
			y += rowh + 4
			rowh = 0
		P.paste(img, d, x, y)
		x += d.get_width() + 4
		rowh = maxi(rowh, d.get_height())
	return img


static func _icons(out: Dictionary) -> Image:
	var img := Image.create(1100, 260, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	var n := 0
	for id in out.manifest.get("icons", {}):
		P.paste(img, _x2(out.images[out.manifest.icons[id]]), (n % 16) * 68, (n / 16) * 68)
		n += 1
	var lod: Dictionary = out.manifest.get("lod_icons", {}).get("*", {})
	var x := 0
	for id in lod:
		var li: Image = out.images[lod[id].file]
		for t in [BLUE, RED, Color.WHITE]:
			var c: Image = li.duplicate()
			for yy in c.get_height():
				for xx in c.get_width():
					var p := c.get_pixel(xx, yy)
					c.set_pixel(xx, yy, Color(p.r * t.r, p.g * t.g, p.b * t.b, p.a))
			P.paste(img, _x2(c), x, 210)
			x += c.get_width() * 2 + 4
	return img
