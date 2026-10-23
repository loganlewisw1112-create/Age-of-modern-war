extends RefCounted
## G3a Human B (Industrial) art module (agent ART3-B): infantry, vehicles + wrecks, buildings
## (built + 3 construction stages) and 32x32 icons for every Human B unit, production item and
## building. Same manifest structures as units.gd / vehicles.gd / buildings.gd, icons in fx_ui.gd's
## format. Runs before fx_ui.gd. Sub-modules: faction_b_inf / _veh / _trk / _bld / _bdress.
const P = preload("res://tools/art/pix.gd")
const FX = preload("res://tools/art/fx_ui.gd")
const INF = preload("res://tools/art/faction_b_inf.gd")
const VEH = preload("res://tools/art/faction_b_veh.gd")
const TRK = preload("res://tools/art/faction_b_trk.gd")
const BLD = preload("res://tools/art/faction_b_bld.gd")

const FRAMES := ["idle", "move", "fire"]
const SPEC := {
	"b_carrier": {"fw": 62, "fh": 46, "pivot": [31, 30]},
	"b_rebuilt_mbt": {"fw": 84, "fh": 54, "pivot": [42, 34]},
	"b_artillery_truck": {"fw": 68, "fh": 58, "pivot": [34, 40]},
	"b_recovery_truck": {"fw": 68, "fh": 62, "pivot": [34, 44]},
}
const TRUCKS := ["b_artillery_truck", "b_recovery_truck"]
## production id -> [unit def shown, squad pips]
const SQUADS := {"b_militia_squad": ["b_militia", 5], "b_heavy_squad": ["b_heavy_rifle", 3]}


static func build(out: Dictionary) -> void:
	INF.build(out)
	_vehicles(out)
	BLD.build(out)
	_icons(out)


static func _vehicles(out: Dictionary) -> void:
	var man: Dictionary = out.manifest.get("vehicles", {})
	var wrecks: Dictionary = out.manifest.get("vehicle_wrecks", {})
	for def in SPEC:
		var sp: Dictionary = SPEC[def]
		var fw: int = sp.fw
		var fh: int = sp.fh
		var o := Vector2(sp.pivot[0], sp.pivot[1])
		var img := Image.create(fw * FRAMES.size(), fh * 8, false, Image.FORMAT_RGBA8)
		var msk := Image.create(fw * FRAMES.size(), fh * 8, false, Image.FORMAT_RGBA8)
		var wimg := Image.create(fw, fh * 8, false, Image.FORMAT_RGBA8)
		for k in 8:
			for f in FRAMES.size():
				var cv = P.Canvas.new(fw, fh)
				_draw(cv, def, k * PI / 4.0, f, false, o)
				img.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i(f * fw, k * fh))
				msk.blit_rect(cv.mask, Rect2i(0, 0, fw, fh), Vector2i(f * fw, k * fh))
			var wc = P.Canvas.new(fw, fh)
			_draw(wc, def, k * PI / 4.0, 0, true, o)
			wimg.blit_rect(wc.img, Rect2i(0, 0, fw, fh), Vector2i(0, k * fh))
		out.images["units/%s.png" % def] = img
		out.images["units/%s_mask.png" % def] = msk
		out.images["wrecks/%s_wreck.png" % def] = wimg
		man[def] = {"file": "units/%s.png" % def, "mask": "units/%s_mask.png" % def, "fw": fw, "fh": fh,
			"pivot": sp.pivot, "frames": FRAMES, "facings": 8}
		wrecks[def] = {"file": "wrecks/%s_wreck.png" % def, "fw": fw, "fh": fh, "pivot": sp.pivot,
			"frames": ["wreck"], "facings": 8}
	out.manifest["vehicles"] = man
	out.manifest["vehicle_wrecks"] = wrecks


static func _draw(cv, def: String, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	if def in TRUCKS:
		TRK.draw(cv, def, rot, f, wreck, o)
	else:
		VEH.draw(cv, def, rot, f, wreck, o)


static func _icons(out: Dictionary) -> void:
	var icons: Dictionary = out.manifest.get("icons", {})
	for def in INF.DEFS:
		icons[def] = _icon_unit(out, def, def, 0)
	for def in SPEC:
		icons[def] = _icon_unit(out, def, def, 0)
	for id in SQUADS:
		icons[id] = _icon_unit(out, id, SQUADS[id][0], SQUADS[id][1])
	for def in BLD.SIZES:
		var src: Image = out.images["buildings/%s_built.png" % def]
		var im := FX._panel()
		FX._fit(im, FX.tint(src, out.images["buildings/%s_built_mask.png" % def], FX.ICON_TEAM), 29)
		out.images["icons/%s.png" % def] = im
		icons[def] = "icons/%s.png" % def
	out.manifest["icons"] = icons


## Same look as fx_ui's unit icons: team-tinted idle frame (facing row 0) on the dark panel;
## infantry is a 2x close-up of the figure, vehicles are fitted; squads get size pips.
static func _icon_unit(out: Dictionary, id: String, def: String, count: int) -> String:
	var src: Image = out.images["units/%s.png" % def]
	var tinted := FX.tint(src, out.images["units/%s_mask.png" % def], FX.ICON_TEAM)
	var im := FX._panel()
	if def in SPEC:
		var sp: Dictionary = SPEC[def]
		FX._fit(im, tinted.get_region(Rect2i(0, 0, sp.fw, sp.fh)), 28)
	else:
		var crop := tinted.get_region(Rect2i(4, 3, 16, 16))
		crop.resize(32, 32, Image.INTERPOLATE_NEAREST)
		im.blend_rect(crop, Rect2i(0, 0, 32, 32), Vector2i(0, 2))
	for i in count:
		for yy in 3:
			im.set_pixel(27 - i * 3, 27 + yy, Color(0.85, 0.82, 0.6))
			im.set_pixel(28 - i * 3, 27 + yy, Color(0.85, 0.82, 0.6))
	var path := "icons/%s.png" % id
	out.images[path] = im
	return path
