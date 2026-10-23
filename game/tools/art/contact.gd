extends RefCounted
## Contact sheet: a sample battlefield scene composed ONLY through the public ArtCatalog API, plus a
## line-up of every sprite, and a 2x crop. Used for visual QA (tools/gen_art.gd -- --contact).
const AC = preload("res://presentation/art/art_catalog.gd")

const TEAM_A := Color("#4f7db0")
const TEAM_B := Color("#b5583a")
const N := 16
const BG := Color(0.13, 0.15, 0.11, 1)


static func code_at(x: int, y: int) -> int:
	var s := x + y
	var dxy := x - y
	if s == 15 or s == 16:
		if absi(dxy) <= 1:
			return 5
		if dxy >= 7 and dxy <= 9:
			return 6
		return 4
	if absi(dxy) <= 1:
		return 2
	if (x - 13) * (x - 13) + (y - 2) * (y - 2) <= 5:
		return 3
	if (x - 2) * (x - 2) + (y - 13) * (y - 13) <= 5:
		return 7
	if s < 9 and absi(dxy) <= 4:
		return 1
	return 0


static func compose(path: String) -> void:
	AC.load_all()
	var W := 1060
	var scene := Image.create(W, 640, false, Image.FORMAT_RGBA8)
	scene.fill(BG)
	var o := Vector2(530, 40)
	var iso := func(p: Vector2) -> Vector2: return o + Vector2((p.x - p.y) * 32.0, (p.x + p.y) * 16.0)
	for s in range(0, 2 * N - 1):
		for x in range(maxi(0, s - N + 1), mini(N, s + 1)):
			var y := s - x
			var c := code_at(x, y)
			var t: Texture2D = AC.terrain_texture(c, (x * 7 + y * 13) % maxi(1, AC.terrain_variants(c)))
			_put(scene, t, iso.call(Vector2(x, y)), Vector2(-32, 0))
	var items: Array = []  # [depth, tex, pos, offset]
	for y in N:
		for x in N:
			var d: Dictionary = AC.decor(code_at(x, y), Vector2i(x, y))
			if not d.is_empty():
				var p: Vector2 = iso.call(Vector2(x + 0.5, y + 0.5))
				items.append([p.y, d.texture, p, d.offset])
	var ents := [
		{"kind": "building", "def": "hq", "owner": 0, "pos": Vector2(3.5, 7.5), "built": true},
		{"kind": "building", "def": "generator", "owner": 0, "pos": Vector2(4, 3), "built": true},
		{"kind": "building", "def": "barracks", "owner": 0, "pos": Vector2(7.5, 2.5), "built": true},
		{"kind": "building", "def": "depot", "owner": 0, "pos": Vector2(1, 11), "built": true},
		{"kind": "building", "def": "motor_pool", "owner": 1, "pos": Vector2(11.5, 13.5), "built": true},
		{"kind": "building", "def": "guard_tower", "owner": 1, "pos": Vector2(14.5, 9.5), "built": true},
		{"kind": "building", "def": "barracks", "owner": 1, "pos": Vector2(6.5, 14.5), "built": false, "progress": 0.5},
		{"kind": "building", "def": "generator", "owner": 1, "pos": Vector2(15, 7), "built": false, "progress": 0.1},
		{"kind": "resource", "def": "salvage", "res": "salvage", "pos": Vector2(9.5, 4.5)},
		{"kind": "resource", "def": "ore", "res": "ore", "pos": Vector2(1.5, 2.5)},
		{"kind": "wreck", "def": "mbt", "from_owner": 1, "pos": Vector2(12.5, 5.5), "facing": 2.0, "size": 1},
		{"kind": "wreck", "def": "barracks", "from_owner": 1, "pos": Vector2(10.5, 9.5), "size": 2},
	]
	var k := 0
	for i in 8:  # squads of both teams in different facings, some moving / firing
		ents.append({"kind": "unit", "def": ["rifleman", "at_gunner", "recon", "engineer"][i % 4], "owner": 0, "id": i,
			"pos": Vector2(8.6 + (i % 4) * 0.55, 8.0 + (i / 4) * 0.7 - (i % 4) * 0.3), "facing": 0.8, "moving": i % 2 == 0, "firing": 1 if i == 1 else 0})
		ents.append({"kind": "unit", "def": ["rifleman", "at_gunner", "rifleman", "recon"][i % 4], "owner": 1, "id": 20 + i,
			"pos": Vector2(11.0 + (i % 4) * 0.5, 11.2 + (i / 4) * 0.6 - (i % 4) * 0.2), "facing": -2.4, "moving": false, "firing": 1 if i == 2 else 0})
	ents.append({"kind": "unit", "def": "engineer", "owner": 1, "pos": Vector2(7.6, 13.0), "facing": PI, "moving": true})
	ents.append({"kind": "unit", "def": "ifv", "owner": 0, "pos": Vector2(7.2, 7.2), "facing": PI / 4, "moving": true})
	ents.append({"kind": "unit", "def": "mbt", "owner": 0, "pos": Vector2(5.8, 9.4), "facing": 0.0})
	ents.append({"kind": "unit", "def": "mbt", "owner": 1, "pos": Vector2(12.6, 10.4), "facing": -3 * PI / 4, "firing": 1})
	ents.append({"kind": "unit", "def": "ifv", "owner": 1, "pos": Vector2(14.0, 12.0), "facing": PI})
	for e in ents:
		var col: Color = TEAM_A if int(e.get("owner", e.get("from_owner", 0))) == 0 else TEAM_B
		var d: Dictionary = AC.entity_sprite(e, col, 0.1 * k)
		k += 1
		var p: Vector2 = iso.call(e.pos)
		items.append([p.y, d.texture, p, d.offset])
	items.sort_custom(func(a, b): return a[0] < b[0])
	for it in items:
		_put(scene, it[1], it[2], it[3])
	# selection rings + effects on top
	_put(scene, AC.selection_ring(0.6), iso.call(Vector2(7.2, 7.2)), -AC.selection_ring(0.6).get_size() * 0.5)
	_put(scene, AC.selection_ring(3.0), iso.call(Vector2(3.5, 7.5)), -AC.selection_ring(3.0).get_size() * 0.5)
	var fx := [["explosion_large", Vector2(10.5, 6.5), 2], ["explosion_small", Vector2(9.5, 10.6), 1], ["smoke", Vector2(12.5, 5.2), 2], ["muzzle", Vector2(12.9, 10.0), 0]]
	for f in fx:
		var fr: Array = AC.effect_frames(f[0])
		var t: Texture2D = fr[mini(f[2], fr.size() - 1)]
		_put(scene, t, iso.call(f[1]) + Vector2(0, -10), -t.get_size() * 0.5)
	var line := _lineup(W)
	var crop := scene.get_region(Rect2i(470, 230, 380, 170))
	crop.resize(760, 340, Image.INTERPOLATE_NEAREST)
	var lcrop := line.get_region(Rect2i(0, 0, 300, 170))
	lcrop.resize(600, 340, Image.INTERPOLATE_NEAREST)
	var out := Image.create(W + 300, scene.get_height() + line.get_height() + 344, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.06, 0.06, 0.06, 1))
	out.blit_rect(scene, Rect2i(Vector2i.ZERO, scene.get_size()), Vector2i(0, 0))
	out.blit_rect(line, Rect2i(Vector2i.ZERO, line.get_size()), Vector2i(0, scene.get_height()))
	out.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i(0, scene.get_height() + line.get_height() + 4))
	out.blit_rect(lcrop, Rect2i(Vector2i.ZERO, lcrop.get_size()), Vector2i(764, scene.get_height() + line.get_height() + 4))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	out.save_png(path)


static func _lineup(W: int) -> Image:
	var img := Image.create(W, 560, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.24, 0.27, 0.19, 1))
	var y := 4
	var x := 4
	for row in 2:
		x = 4
		for def in ["rifleman", "at_gunner", "recon", "engineer"]:
			for f in 8:
				var e := {"kind": "unit", "def": def, "facing": f * PI / 4, "moving": row == 1 and f % 2 == 0, "firing": 1 if row == 1 and f % 2 == 1 else 0}
				var d := AC.entity_sprite(e, TEAM_A if row == 0 else TEAM_B, 0.0)
				_put(img, d.texture, Vector2(x + 12, y + 22), d.offset)
				x += 26
			x += 6
		y += 30
	x = 4
	for def in ["ifv", "mbt"]:
		for f in 8:
			var d := AC.entity_sprite({"kind": "unit", "def": def, "facing": f * PI / 4}, TEAM_A if def == "ifv" else TEAM_B, 0.0)
			_put(img, d.texture, Vector2(x + 30, y + 32), d.offset)
			x += 64
	y += 56
	x = 4
	var bi := 0
	for def in ["hq", "generator", "depot", "barracks", "motor_pool", "guard_tower"]:
		var d := AC.entity_sprite({"kind": "building", "def": def, "built": true}, TEAM_A if bi % 2 == 0 else TEAM_B, 0.0)
		var t: Texture2D = d.texture
		_put(img, t, Vector2(x, y + 150) - Vector2(0, 0), Vector2(0, -t.get_height()))
		x += t.get_width() + 2
		bi += 1
	y += 156
	x = 4
	for st in [0.1, 0.5, 0.9]:
		var d := AC.entity_sprite({"kind": "building", "def": "barracks", "built": false, "progress": st}, TEAM_B, 0.0)
		var t: Texture2D = d.texture
		_put(img, t, Vector2(x, y + 130), Vector2(0, -t.get_height()))
		x += t.get_width() + 2
	for e in [{"kind": "wreck", "def": "ifv", "facing": 1.0}, {"kind": "wreck", "def": "mbt", "facing": 4.0},
			{"kind": "wreck", "def": "hq", "size": 3}, {"kind": "resource", "def": "salvage", "res": "salvage"}, {"kind": "resource", "def": "ore", "res": "ore"}]:
		var t: Texture2D = AC.entity_sprite(e, TEAM_A, 0.0).texture
		_put(img, t, Vector2(x, y + 130), Vector2(0, -t.get_height()))
		x += t.get_width() + 2
	y += 136
	x = 4
	for n in ["muzzle", "explosion_small", "explosion_large", "smoke"]:
		for t in AC.effect_frames(n):
			_put(img, t, Vector2(x, y), Vector2.ZERO)
			x += t.get_width() + 2
	y += 68
	x = 4
	for id in ["engineer", "rifle_squad", "at_team", "recon", "rifleman", "at_gunner", "ifv", "mbt", "hq", "generator", "depot", "barracks", "motor_pool", "guard_tower", "salvage", "ore"]:
		_put(img, AC.icon(id), Vector2(x, y), Vector2.ZERO)
		x += 35
	_put(img, AC.fog_tile("unexplored"), Vector2(x + 10, y), Vector2.ZERO)
	_put(img, AC.fog_tile("explored"), Vector2(x + 80, y), Vector2.ZERO)
	return img


static func _put(dst: Image, tex: Texture2D, pos: Vector2, offset: Vector2) -> void:
	if tex == null:
		return
	var im := tex.get_image()
	if im == null or im.is_empty():
		return
	if im.get_format() != Image.FORMAT_RGBA8:
		im.convert(Image.FORMAT_RGBA8)
	var at := Vector2i((pos + offset).round())
	dst.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), at)
