extends RefCounted
## G3a Machine (Autonomous Network) art module (owner: agent ART3-M). Sprites + masks + manifest entries
## (same structures as units.gd / vehicles.gd / buildings.gd) AND this faction's 32x32 icons (same format
## as fx_ui.gd). Runs before fx_ui.gd. Sub-modules: faction_m_units/_walker (legged), faction_m_veh/_drone,
## faction_m_bld/_bdress (buildings), faction_m_lib (palette + helpers).
## Icons go into out.manifest.icons via get-or-create; fx_ui.gd must merge rather than replace that map
## (CHANGE_REQUEST art.icons_clobber).
const P = preload("res://tools/art/pix.gd")
const U = preload("res://tools/art/faction_m_units.gd")
const V = preload("res://tools/art/faction_m_veh.gd")
const BL = preload("res://tools/art/faction_m_bld.gd")
const L = preload("res://tools/art/faction_m_lib.gd")
const FX = preload("res://tools/art/fx_ui.gd")

const UNITS := ["m_hauler", "m_repair_bot", "m_scout_crawler", "m_drone", "m_walker", "m_tracked", "m_artillery_node",
	"m_coordinator"]
## production id -> [sprite def, pip count]
const PRODUCTION := {"m_hauler": ["m_hauler", 0], "m_repair_bot": ["m_repair_bot", 0], "m_scout_crawler": ["m_scout_crawler", 0],
	"m_drone_pair": ["m_drone", 2], "m_coordinator": ["m_coordinator", 0], "m_walker": ["m_walker", 0],
	"m_tracked": ["m_tracked", 0], "m_artillery_node": ["m_artillery_node", 0]}


static func build(out: Dictionary) -> void:
	U.build(out)
	V.build(out)
	BL.build(out)
	var icons: Dictionary = out.manifest.get("icons", {})
	for id in UNITS:
		icons[id] = _icon_unit(out, id, id, 0)
	for id in PRODUCTION:
		if not icons.has(id):
			icons[id] = _icon_unit(out, id, PRODUCTION[id][0], PRODUCTION[id][1])
	for id in BL.SIZES:
		icons[id] = _icon_building(out, id)
	out.manifest["icons"] = icons


static func _spec(out: Dictionary, def: String) -> Dictionary:
	return out.manifest.get("infantry", {}).get(def, out.manifest.get("vehicles", {}).get(def, {}))


static func _panel() -> Image:
	var im: Image = FX._panel()
	for x in range(2, 8):  # faction accent: cyan status strip, top-left
		im.set_pixel(x, 2, L.CYAN if x < 7 else L.TEAL)
	return im


static func _icon_unit(out: Dictionary, id: String, def: String, count: int) -> String:
	var sp := _spec(out, def)
	var src: Image = out.images[sp.file]
	var msk: Image = out.images[sp.mask]
	var tinted: Image = FX.tint(src, msk, FX.ICON_TEAM)
	var fw: int = sp.fw
	var fh: int = sp.fh
	var frame := tinted.get_region(Rect2i(0, fh, fw, fh))  # idle, facing the camera (row 1)
	var im := _panel()
	FX._fit(im, frame, 28 if fw > 32 else 24)
	for i in count:  # count pips (drone pair)
		for yy in 3:
			im.set_pixel(27 - i * 3, 27 + yy, Color(0.85, 0.82, 0.6))
			im.set_pixel(28 - i * 3, 27 + yy, Color(0.85, 0.82, 0.6))
	var path := "icons/%s.png" % id
	out.images[path] = im
	return path


static func _icon_building(out: Dictionary, id: String) -> String:
	var src: Image = out.images["buildings/%s_built.png" % id]
	var msk: Image = out.images["buildings/%s_built_mask.png" % id]
	var im := _panel()
	FX._fit(im, FX.tint(src, msk, FX.ICON_TEAM), 29)
	var path := "icons/%s.png" % id
	out.images[path] = im
	return path
