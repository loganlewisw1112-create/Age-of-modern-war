extends SceneTree
## ICONS7: builds a 32x32 command-card / inspector icon from each def's own art for the defs that had none
## (ArtCatalog.icon returned the magenta placeholder). Same framed look as tools/art/g7_cn_lib.gd icon().
## Run: godot --headless --path . -s tools/art/g7_icons7.gd
## Writes assets/art/g7_icons7/icons/<id>.png and assets/art/g7_icons7/manifest.json (group g7_icons7, listed in
## ArtCatalog.G5_GROUPS). Only touches its own folder.

const OUT := "res://assets/art/g7_icons7/"
const ICON := 32
## id -> [source png, frame rect or null for the whole image]
const SRC := {
	"cn_armory": ["res://assets/art/g7_fac7f/buildings/g7_fac_armory_rot_0.png", null],
	"cn_magazine": ["res://assets/art/g7_fac7f/buildings/g7_fac_magazine_rot_0.png", null],
	"cn_ammo_locker": ["res://assets/art/g7_fac7f/buildings/cn_ammo_locker_built.png", null],
	"cn_link_wall": ["res://assets/art/g7_fac7f/buildings/g7_fac_linkwall_sheet.png", Rect2i(0, 0, 140, 140)],  # intact, side 0, N+S
	"cn_ecp_baffle": ["res://assets/art/g7_fac7f/buildings/g7_fac_baffle_sheet.png", Rect2i(10 * 76, 0, 76, 86)],  # intact, E+W run
	"a_g7_vtol_pad": ["res://assets/art/g7_fac7f/buildings/a_g7_vtol_pad_rot_0.png", null],
	"a_g7_camera": ["res://assets/art/g7_baseprops/buildings/a_g7_camera_built.png", null],
	"bridge_span": ["res://assets/generated/bridge/intact_c_1.png", null],
}


func _init() -> void:
	var icons := {}
	var files := {}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "icons"))
	var ids: Array = SRC.keys()
	ids.sort()
	for id in ids:
		var s: Array = SRC[id]
		var img := Image.new()
		var bytes := FileAccess.get_file_as_bytes(String(s[0]))
		if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
			printerr("ICONS7 cannot read ", s[0])
			continue
		img.convert(Image.FORMAT_RGBA8)
		var cell: Image = img if s[1] == null else img.get_region(s[1])
		var ic := _icon(cell)
		var rel := "icons/%s.png" % id
		ic.save_png(ProjectSettings.globalize_path(OUT + rel))
		icons[id] = rel
		files[rel] = ic.save_png_to_buffer().size()
		print("ICONS7 wrote ", id)
	_vanta_b()
	var man := {"group": "g7_icons7", "version": 1, "icons": icons}
	var f := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(man, " "))
	f.close()
	quit()


func _icon(cell: Image) -> Image:
	var u := cell.get_used_rect()
	var ic := Image.create(ICON, ICON, false, Image.FORMAT_RGBA8)
	ic.fill(Color8(30, 34, 30))
	for i in ICON:
		ic.set_pixel(i, 0, Color8(70, 78, 66))
		ic.set_pixel(0, i, Color8(70, 78, 66))
		ic.set_pixel(i, ICON - 1, Color8(14, 16, 14))
		ic.set_pixel(ICON - 1, i, Color8(14, 16, 14))
	if u.size.x > 0 and u.size.y > 0:
		var src := cell.get_region(u)
		var sc := minf(28.0 / u.size.x, 28.0 / u.size.y)
		if sc >= 1.0:
			sc = floorf(sc)
		var w := maxi(1, int(u.size.x * sc))
		var h := maxi(1, int(u.size.y * sc))
		src.resize(w, h, Image.INTERPOLATE_NEAREST if sc >= 1.0 else Image.INTERPOLATE_BILINEAR)
		ic.blend_rect(src, Rect2i(0, 0, w, h), Vector2i((ICON - w) / 2, (ICON - h) / 2))
	return ic


## cn_vanta_b: no separate Human B Vanta sprite exists (the "_b" frames are the fan-shimmer animation, not the faction), so
## the Human B variant's icon is the bare-airframe icon recoloured to its documented olive-sand finish
## (defs_g7_vanta.json cn_vanta_b _note). Written into g7_vanta's own icons folder and pointed to from its manifest.
func _vanta_b() -> void:
	var src := Image.new()
	if src.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/art/g7_vanta/icons/g7_vanta_bare.png")) != OK:
		printerr("ICONS7 cannot read vanta bare icon")
		return
	src.convert(Image.FORMAT_RGBA8)
	var tint := Color(0.80, 0.72, 0.42)
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			var l := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			var t := Color(minf(1.0, l * tint.r * 1.5), minf(1.0, l * tint.g * 1.5), minf(1.0, l * tint.b * 1.5), c.a)
			src.set_pixel(x, y, c.lerp(t, 0.85))
	src.save_png(ProjectSettings.globalize_path("res://assets/art/g7_vanta/icons/g7_vanta_bare_b.png"))
	print("ICONS7 wrote vanta b icon")
