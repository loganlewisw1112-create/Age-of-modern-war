extends SceneTree
## Machine contact sheet (agent ART3-M): generates all art IN MEMORY (no files written to assets/) and
## composes .plan/shots/ART3-M/contact.png: a small battlefield scene (Machine base vs a Human A tank
## for scale, drones lifted by manifest altitude over their separate shadows), every Machine sprite line-up,
## buildings in all 4 states, icons, and a 2x crop.
##   godot --headless --path . -s tools/art/faction_m_contact.gd
const FX = preload("res://tools/art/fx_ui.gd")
const FM = preload("res://tools/art/faction_m.gd")

const BLUE := Color("#4f7db0")
const RED := Color("#b5583a")
const BG := Color(0.13, 0.15, 0.11, 1)
var out: Dictionary


func _init() -> void:
	# own module list: independent of other agents' in-progress faction modules
	out = {"images": {}, "manifest": {"version": 1, "tile": [64, 32]}}
	for m in [preload("res://tools/art/terrain.gd"), preload("res://tools/art/units.gd"), preload("res://tools/art/vehicles.gd"), FM]:
		m.build(out)
	var sheet := Image.create(1400, 2300, false, Image.FORMAT_RGBA8)
	sheet.fill(BG)
	var scene := _scene()
	sheet.blit_rect(scene, Rect2i(0, 0, scene.get_width(), scene.get_height()), Vector2i(0, 0))
	var crop := scene.get_region(Rect2i(330, 150, 420, 260))
	crop.resize(840, 520, Image.INTERPOLATE_NEAREST)
	var y := 560
	for def in FM.UNITS:
		y = _lineup(sheet, def, y)
	var x := 10
	var by := y + 6
	var rowh := 0
	for def in FM.BL.SIZES:
		var b: Dictionary = out.manifest.buildings[def]
		for st in ["built", "build_0", "build_1", "build_2"]:
			var im := _tinted(b.states[st].file, b.states[st].mask, BLUE)
			if x + im.get_width() > 1400:
				x = 10
				by += rowh + 4
				rowh = 0
			sheet.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(x, by))
			x += im.get_width() + 2
			rowh = maxi(rowh, im.get_height())
	by += rowh + 8
	var ix := 10
	for id in out.manifest.icons:
		if not String(id).begins_with("m_"):
			continue
		var ic: Image = out.images[out.manifest.icons[id]].duplicate()
		ic.resize(64, 64, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(ic, Rect2i(0, 0, 64, 64), Vector2i(ix, by))
		ix += 68
	sheet.blit_rect(crop, Rect2i(0, 0, 840, 520), Vector2i(10, by + 76))
	var path := ProjectSettings.globalize_path("res://.plan/shots/ART3-M/contact.png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	sheet.save_png(path)
	print("FM_CONTACT %s icons=%d" % [path, (ix - 10) / 68])
	quit(0)


func _tinted(file: String, mask: String, col: Color) -> Image:
	return FX.tint(out.images[file], out.images.get(mask), col)


func _spec(def: String) -> Dictionary:
	return out.manifest.infantry.get(def, out.manifest.vehicles.get(def, {}))


## One strip: 8 facings of frame 0, then every frame of facing 1, then the wreck (if any).
func _lineup(sheet: Image, def: String, y: int) -> int:
	var sp := _spec(def)
	var fw: int = sp.fw
	var fh: int = sp.fh
	var im := _tinted(sp.file, sp.mask, BLUE if def != "m_tracked" else RED)
	var x := 10
	for k in 8:
		sheet.blend_rect(im, Rect2i(0, k * fh, fw, fh), Vector2i(x, y))
		x += fw
	x += 12
	for f in sp.frames.size():
		sheet.blend_rect(im, Rect2i(f * fw, fh, fw, fh), Vector2i(x, y))
		x += fw
	var wr: Dictionary = out.manifest.vehicle_wrecks.get(def, {})
	if not wr.is_empty():
		x += 12
		sheet.blend_rect(out.images[wr.file], Rect2i(0, fh, fw, fh), Vector2i(x, y))
	return y + fh + 2


func _iso(p: Vector2) -> Vector2:
	return Vector2(700, 60) + Vector2((p.x - p.y) * 32.0, (p.x + p.y) * 16.0)


func _put(dst: Image, src: Image, at: Vector2) -> void:
	dst.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i(int(at.x), int(at.y)))


func _scene() -> Image:
	var img := Image.create(1400, 560, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	var n := 15
	for s in range(0, 2 * n - 1):
		for x in range(maxi(0, s - n + 1), mini(n, s + 1)):
			var yy := s - x
			var code := 3 if (x - 13) * (x - 13) + (yy - 3) * (yy - 3) <= 4 else 0
			var t: Dictionary = out.manifest.terrain[str(code)]
			var tile: Image = out.images["terrain/%s_%d.png" % [t.name, (x * 7 + yy * 13) % int(t.variants)]]
			_put(img, tile, _iso(Vector2(x, yy)) + Vector2(-32, 0))
	var items: Array = []  # [depth, image, top-left]
	var blds := [["m_core", Vector2(3.5, 3.5), true], ["m_charging_hub", Vector2(7, 2), true], ["m_assembler", Vector2(3.5, 8.5), true],
		["m_crawler_works", Vector2(8.5, 6.5), false], ["m_reprocessor", Vector2(1.5, 12.5), true], ["m_sentry", Vector2(10.5, 10.5), true],
		["m_sensor_relay", Vector2(12.5, 7.5), true]]
	for b in blds:
		var e: Dictionary = out.manifest.buildings[b[0]]
		var st: Dictionary = e.states.built if b[2] else e.states.build_1
		items.append([b[1].x + b[1].y, _tinted(st.file, st.mask, BLUE), _iso(b[1]) - Vector2(e.pivot[0], e.pivot[1])])
	var units := [["m_walker", Vector2(9.5, 11.5), 0, 0], ["m_tracked", Vector2(7.5, 11.0), 1, 2], ["m_artillery_node", Vector2(6.0, 12.6), 1, 2],
		["m_scout_crawler", Vector2(11.4, 12.0), 0, 1], ["m_scout_crawler", Vector2(11.9, 12.6), 0, 3], ["m_repair_bot", Vector2(6.2, 5.6), 1, 3],
		["m_hauler", Vector2(4.6, 11.8), 2, 1], ["m_coordinator", Vector2(10.2, 12.8), 1, 0], ["m_repair_bot", Vector2(7.6, 9.4), 3, 1],
		["mbt", Vector2(13.0, 13.4), 5, 2], ["rifleman", Vector2(12.2, 13.8), 5, 0]]
	for u in units:
		var sp := _spec(u[0])
		var im := _tinted(sp.file, sp.mask, RED if u[0] in ["mbt", "rifleman"] else BLUE)
		var fr := im.get_region(Rect2i(u[3] * int(sp.fw), u[2] * int(sp.fh), sp.fw, sp.fh))
		items.append([u[1].x + u[1].y, fr, _iso(u[1]) - Vector2(sp.pivot[0], sp.pivot[1])])
	var wr: Dictionary = out.manifest.vehicle_wrecks.m_walker
	items.append([24.0, out.images[wr.file].get_region(Rect2i(0, 3 * int(wr.fh), wr.fw, wr.fh)), _iso(Vector2(12.0, 12.0)) - Vector2(wr.pivot[0], wr.pivot[1])])
	items.sort_custom(func(a, b): return a[0] < b[0])
	for it in items:
		_put(img, it[1], it[2])
	var d: Dictionary = out.manifest.vehicles.m_drone
	var shadow: Image = out.images[d.shadow.file]
	for i in 3:  # drones: shadow at the ground point, sprite lifted by altitude
		var gp := _iso(Vector2(10.6 + i * 0.7, 9.0 + i * 0.4))
		_put(img, shadow, gp - Vector2(d.shadow.pivot[0], d.shadow.pivot[1]))
		var fr := _tinted(d.file, d.mask, BLUE).get_region(Rect2i(i % 3 * int(d.fw), 1 * int(d.fh), d.fw, d.fh))
		_put(img, fr, gp - Vector2(d.pivot[0], d.pivot[1]) - Vector2(0, int(d.altitude) + i))
	return img
