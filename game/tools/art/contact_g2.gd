extends RefCounted
## G2 contact-sheet panel (agent E2): BEFORE (git HEAD art, .plan/shots/E2-art/before/) vs AFTER (the
## current generator, read through the public ArtCatalog API) for MBT, IFV, HQ and barracks at 1x and 2x,
## then the new G2 sprites: officer, logistics_truck, refinery (+3 stages), bridge overlays, effects, icons.
## Layout: every pair is BEFORE on the left (grey bar under it) and AFTER on the right (green bar).
const AC = preload("res://presentation/art/art_catalog.gd")

const TEAM_A := Color("#4f7db0")
const TEAM_B := Color("#b5583a")
const BG := Color(0.24, 0.27, 0.19, 1)
const BEFORE := "res://.plan/shots/E2-art/before/"
const BAR_BEFORE := Color(0.55, 0.55, 0.55, 1)
const BAR_AFTER := Color(0.45, 0.85, 0.4, 1)


static func panel(W: int) -> Image:
	var img := Image.create(W, 1180, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	var pairs := _pairs()  # [[before, after], ...] mbt r1, mbt r6, ifv r1, ifv r6, hq, barracks
	# row 1: everything at 1x
	var x := 6
	var y := 8
	var row_h := 0
	for p in pairs:
		for i in 2:
			_blit(img, p[i], Vector2i(x, y))
			img.fill_rect(Rect2i(x, y + p[i].get_height() + 1, p[i].get_width(), 2), BAR_BEFORE if i == 0 else BAR_AFTER)
			x += p[i].get_width() + 2
			row_h = maxi(row_h, p[i].get_height())
		x += 10
	y += row_h + 10
	# row 2: vehicles + barracks at 2x
	x = 6
	row_h = 0
	for pi in [0, 1, 2, 3]:
		for i in 2:
			var im: Image = pairs[pi][i].duplicate()
			im.resize(im.get_width() * 2, im.get_height() * 2, Image.INTERPOLATE_NEAREST)
			_blit(img, im, Vector2i(x, y))
			img.fill_rect(Rect2i(x, y + im.get_height() + 1, im.get_width(), 3), BAR_BEFORE if i == 0 else BAR_AFTER)
			x += im.get_width() + 2
			row_h = maxi(row_h, im.get_height())
		x += 8
	y += row_h + 10
	img.get_region(Rect2i(0, 0, W, y)).save_png(ProjectSettings.globalize_path("res://.plan/shots/E2-art/before_after_vehicles.png"))
	var y_b := y
	# row 3: HQ at 2x
	x = 6
	for i in 2:
		var hq: Image = pairs[4][i].duplicate()
		hq.resize(hq.get_width() * 2, hq.get_height() * 2, Image.INTERPOLATE_NEAREST)
		_blit(img, hq, Vector2i(x, y))
		img.fill_rect(Rect2i(x, y + hq.get_height() + 1, hq.get_width(), 3), BAR_BEFORE if i == 0 else BAR_AFTER)
		x += hq.get_width() + 6
		row_h = hq.get_height()
	# right of the HQ: refinery built + 3 stages, then the bridge overlays
	var rx := x + 10
	var ry := y
	var rh := 0
	for st in [{"built": true}, {"built": false, "progress": 0.1}, {"built": false, "progress": 0.5}, {"built": false, "progress": 0.9}]:
		var e := {"kind": "building", "def": "refinery"}
		e.merge(st, true)
		var t: Texture2D = AC.entity_sprite(e, TEAM_B, 0.0).texture
		if rx + t.get_width() > W:
			rx = x + 10
			ry += rh + 6
			rh = 0
		_blit(img, t.get_image(), Vector2i(rx, ry))
		rx += t.get_width() + 4
		rh = maxi(rh, t.get_height())
	ry += rh + 10
	var hq_bottom := y + row_h + 10
	x = 6
	for i in 2:
		var bk: Image = pairs[5][i].duplicate()
		bk.resize(bk.get_width() * 2, bk.get_height() * 2, Image.INTERPOLATE_NEAREST)
		_blit(img, bk, Vector2i(x, hq_bottom))
		img.fill_rect(Rect2i(x, hq_bottom + bk.get_height() + 1, bk.get_width(), 3), BAR_BEFORE if i == 0 else BAR_AFTER)
		x += bk.get_width() + 6
		row_h = hq_bottom - y + bk.get_height()
	img.get_region(Rect2i(0, y_b, W, row_h + 6)).save_png(ProjectSettings.globalize_path("res://.plan/shots/E2-art/before_after_buildings.png"))
	ry = hq_bottom
	rx = x + 10
	for state in ["intact", "damaged", "ruined"]:
		for cell in [Vector2i(4, 5), Vector2i(4, 4), Vector2i(5, 4)]:
			var centre := Vector2i(rx + 32, ry + 40)
			var tc := 4 if state == "ruined" else 5
			_blit(img, AC.terrain_texture(tc, 0).get_image(), centre + Vector2i(-32, -16))
			var d: Dictionary = AC.bridge_overlay(state, cell)
			_blit(img, d.texture.get_image(), centre + Vector2i(d.offset))
			rx += 66
		rx += 8
		if rx + 200 > W:
			rx = x + 10
			ry += 62
	var bimg := img.get_region(Rect2i(x, hq_bottom, W - x, ry + 64 - hq_bottom))
	bimg.resize(bimg.get_width() * 2, bimg.get_height() * 2, Image.INTERPOLATE_NEAREST)
	bimg.save_png(ProjectSettings.globalize_path("res://.plan/shots/E2-art/bridge_2x.png"))
	y += maxi(row_h, ry + 62 - y) + 10
	var y_new := y
	# row 4: officer (8 facings x idle/walk_a/walk_b/fire), logistics trucks (8 facings), truck wreck
	x = 6
	for f in 8:
		for st in [{}, {"moving": true}, {"moving": true, "id": 3}, {"firing": 1}]:
			var e := {"kind": "unit", "def": "officer", "facing": f * PI / 4}
			e.merge(st, true)
			var d: Dictionary = AC.entity_sprite(e, TEAM_A if f % 2 == 0 else TEAM_B, 0.0)
			_blit(img, d.texture.get_image(), Vector2i(x, y + 30) + Vector2i(d.offset))
			x += 20
		x += 4
	y += 40
	x = 6
	for f in 8:
		var d: Dictionary = AC.entity_sprite({"kind": "unit", "def": "logistics_truck", "facing": f * PI / 4, "moving": f % 2 == 1}, TEAM_A if f < 4 else TEAM_B, 0.0)
		_blit(img, d.texture.get_image(), Vector2i(x + 32, y + 40) + Vector2i(d.offset))
		x += 66
	var wr: Dictionary = AC.entity_sprite({"kind": "wreck", "def": "logistics_truck", "facing": 1.0}, TEAM_A, 0.0)
	_blit(img, wr.texture.get_image(), Vector2i(x + 32, y + 40) + Vector2i(wr.offset))
	y += 60
	# row 5: G2 effects (all frames) and new icons
	x = 6
	for n in ["disabled_smoke", "pinned", "cover", "retreat"]:
		for t in AC.effect_frames(n):
			_blit(img, t.get_image(), Vector2i(x, y))
			x += t.get_width() + 2
		x += 8
	x += 10
	for id in ["officer", "logistics_truck", "refinery", "repair", "patrol", "guard", "formation_line", "formation_wedge",
			"formation_column", "mission_secure", "mission_hold", "mission_attack", "mission_patrol", "assign_officer"]:
		if x + 34 > W:
			x = 6
			y += 52
		_blit(img, AC.icon(id).get_image(), Vector2i(x, y))
		x += 35
	var nimg := img.get_region(Rect2i(0, y_new, 700, mini(img.get_height(), y + 56) - y_new))
	nimg.resize(nimg.get_width() * 2, nimg.get_height() * 2, Image.INTERPOLATE_NEAREST)
	nimg.save_png(ProjectSettings.globalize_path("res://.plan/shots/E2-art/new_sprites_2x.png"))
	return img.get_region(Rect2i(0, 0, W, mini(img.get_height(), y + 56)))


## [[before, after], ...]: mbt facing 1, mbt facing 6, ifv facing 1, ifv facing 6, hq, barracks.
static func _pairs() -> Array:
	var out: Array = []
	for v in [["mbt", 70, 50, TEAM_B], ["ifv", 60, 46, TEAM_A]]:
		var sheet := _tinted("units_%s" % v[0], v[3])
		for row in [1, 6]:
			var b: Image = sheet.get_region(Rect2i(0, row * v[2], v[1], v[2])) if sheet != null else Image.create(v[1], v[2], false, Image.FORMAT_RGBA8)
			var a: Image = AC.entity_sprite({"kind": "unit", "def": v[0], "facing": row * PI / 4}, v[3], 0.0).texture.get_image()
			out.append([b, a])
	for bdef in [["hq", TEAM_A], ["barracks", TEAM_B]]:
		var b2 := _tinted("buildings_%s_built" % bdef[0], bdef[1])
		var a2: Image = AC.entity_sprite({"kind": "building", "def": bdef[0], "built": true}, bdef[1], 0.0).texture.get_image()
		out.append([b2 if b2 != null else Image.create(8, 8, false, Image.FORMAT_RGBA8), a2])
	return out


## Same tint formula as ArtCatalog._sheet, applied to the archived BEFORE sheet + mask.
static func _tinted(base: String, col: Color) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(BEFORE + base + ".png"))
	var m := Image.load_from_file(ProjectSettings.globalize_path(BEFORE + base + "_mask.png"))
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	if m != null and not m.is_empty() and m.get_size() == img.get_size():
		m.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				if m.get_pixel(x, y).a > 0.0:
					var c := img.get_pixel(x, y)
					var k := 0.45 + c.r * 0.9
					img.set_pixel(x, y, Color(col.r * k, col.g * k, col.b * k, c.a).clamp())
	return img


static func _blit(dst: Image, im: Image, at: Vector2i) -> void:
	if im == null or im.is_empty():
		return
	if im.get_format() != Image.FORMAT_RGBA8:
		im.convert(Image.FORMAT_RGBA8)
	dst.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), at)
