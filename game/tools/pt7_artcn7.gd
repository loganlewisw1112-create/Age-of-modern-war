extends RefCounted
## G7 playtest flow artcn7 (ARTCN7-4, rev3): the owner's side-by-side in the real game at the ONE real-world scale
## (fact art.scale). Today's rifle squad + IFV on the left; the 7 DL7-3 strike-team kits standing next to the strike
## APC, the tactical APC with two operators, and the stealth VTOL dropship parked on its helipad (the pad is a
## display-only sprite here: it is not a building def yet). Shots at zoom 1, 2 and 3. Checks the sheets resolve to
## real art (not the placeholder).

const H = preload("res://tests/test_machine_g6.gd")
const AC = preload("res://presentation/art/art_catalog.gd")
const TEAM := ["g7_cn_team_leader", "g7_cn_radio", "g7_cn_deploy", "g7_cn_scanner", "g7_cn_ew", "g7_cn_gunner", "g7_cn_medic"]
const DEFS := ["g7_cn_strike_apc", "g7_op_tactical_apc", "g7_op_marksman", "g7_op_hunter", "cn_stealth_dropship"]
const PAD := "res://assets/art/g7_cn/buildings/g7_cn_helipad_lit.png"


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


## Display-only helipad under the parked dropship (drawn below the entity layer).
func _pad(mv, at: Vector2) -> bool:
	var layer = mv.get("entity_layer")
	if layer == null or not FileAccess.file_exists(PAD):
		return false
	var man = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/g7_cn/manifest.json"))
	var pv: Array = man.buildings.g7_cn_helipad.pivot
	var im := Image.load_from_file(ProjectSettings.globalize_path(PAD))
	var sp := Sprite2D.new()
	sp.texture = ImageTexture.create_from_image(im)
	sp.centered = false
	sp.offset = -Vector2(float(pv[0]), float(pv[1]))
	sp.position = mv.world_to_screen(at) + Vector2(0, -16)   # building pivots sit half a tile below a unit's tile-centre point
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var par: Node = layer.get_parent()
	par.add_child(sp)
	par.move_child(sp, layer.get_index())
	# the parked craft on the pad: the sim draws airborne units lifted, so the landed / ramp-down pose is shown as a
	# display-only sprite cut from the real sheet (frame ramp_down, facing row 0 = nose +x like the pad outline)
	var e: Dictionary = man.vehicles.g7_cn_stealth_dropship
	var fw := int(e.fw)
	var fh := int(e.fh)
	var col := (e.frames as Array).find("ramp_down")
	var sheet := Image.load_from_file(ProjectSettings.globalize_path("res://assets/art/g7_cn/" + String(e.file)))
	var msk := Image.load_from_file(ProjectSettings.globalize_path("res://assets/art/g7_cn/" + String(e.mask)))
	sheet.convert(Image.FORMAT_RGBA8)
	msk.convert(Image.FORMAT_RGBA8)
	var cell := sheet.get_region(Rect2i(col * fw, 0, fw, fh))
	var mc := msk.get_region(Rect2i(col * fw, 0, fw, fh))
	var team := Color("#4f7db0")
	for y in fh:
		for x in fw:
			if mc.get_pixel(x, y).a > 0.0:
				var c := cell.get_pixel(x, y)
				var k := 0.45 + c.r * 0.9
				cell.set_pixel(x, y, Color(team.r * k, team.g * k, team.b * k, c.a))
	var cs := Sprite2D.new()
	cs.texture = ImageTexture.create_from_image(cell)
	cs.centered = false
	cs.offset = -Vector2(float(e.pivot[0]), float(e.pivot[1]))
	cs.position = mv.world_to_screen(at)
	cs.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	par.add_child(cs)
	par.move_child(cs, layer.get_index())
	return true


## rev4 (ARTCN7-5): a display-only craft sprite cut from any G7 sheet (main or load sheet), frame fname, facing row k,
## team-tinted like _pad's parked craft; drawn just below the entity layer at world tile `at`.
func _craft(mv, at: Vector2, id: String, fname: String, k: int) -> bool:
	var layer = mv.get("entity_layer")
	if layer == null:
		return false
	var man = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/g7_cn/manifest.json"))
	var e: Dictionary = man.vehicles.get(id, {})
	if e.is_empty() or not (e.frames as Array).has(fname):
		return false
	var fw := int(e.fw)
	var fh := int(e.fh)
	var col := (e.frames as Array).find(fname)
	var sheet := Image.load_from_file(ProjectSettings.globalize_path("res://assets/art/g7_cn/" + String(e.file)))
	var msk := Image.load_from_file(ProjectSettings.globalize_path("res://assets/art/g7_cn/" + String(e.mask)))
	sheet.convert(Image.FORMAT_RGBA8)
	msk.convert(Image.FORMAT_RGBA8)
	var cell := sheet.get_region(Rect2i(col * fw, k * fh, fw, fh))
	var mc := msk.get_region(Rect2i(col * fw, k * fh, fw, fh))
	var team := Color("#4f7db0")
	for y in fh:
		for x in fw:
			if mc.get_pixel(x, y).a > 0.0:
				var c := cell.get_pixel(x, y)
				var kk := 0.45 + c.r * 0.9
				cell.set_pixel(x, y, Color(team.r * kk, team.g * kk, team.b * kk, c.a))
	var cs := Sprite2D.new()
	cs.texture = ImageTexture.create_from_image(cell)
	cs.centered = false
	cs.offset = -Vector2(float(e.pivot[0]), float(e.pivot[1]))
	cs.position = mv.world_to_screen(at)
	cs.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var par: Node = layer.get_parent()
	par.add_child(cs)
	par.move_child(cs, layer.get_index())
	return true


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	var w: SimWorld = pt._w()
	var h = H.new()
	var c: Vector2i = h._open(w, 12)
	var base := Vector2(c)
	var n := 0
	for i in 4:   # today's rifle squad + IFV (left)
		h._unit(w, "rifleman", 0, base + Vector2(-6.0, -1.5 + i * 0.9))
		n += 1
	h._unit(w, "ifv", 0, base + Vector2(-7.0, 2.6))
	for i in TEAM.size():   # the G7 strike team standing next to its APC
		h._unit(w, TEAM[i], 0, base + Vector2(-3.0 + (i % 4) * 0.55, -0.6 + (i / 4) * 0.6))
	h._unit(w, "g7_cn_strike_apc", 0, base + Vector2(-1.2, 1.6))
	h._unit(w, "g7_op_tactical_apc", 0, base + Vector2(0.6, -1.4))
	h._unit(w, "g7_op_marksman", 0, base + Vector2(1.6, -0.3))
	h._unit(w, "g7_op_hunter", 0, base + Vector2(2.1, -0.1))
	var lz := base + Vector2(5.0, 1.0)
	var pad_ok := _pad(mv, lz)
	h._unit(w, "cn_stealth_dropship", 0, base + Vector2(1.5, 4.5))   # a second one airborne (sim unit, real catalog sprite)
	var ph := 0
	for d in TEAM + DEFS:
		var t: Texture2D = AC.entity_sprite({"kind": "unit", "def": d, "facing": 0.0}, Color("#4f7db0"), 0).texture
		if t == AC.placeholder_for({"kind": "unit", "def": d}, Color("#4f7db0")).texture:
			ph += 1
	pt._log("artcn7_sheets_resolve", ph == 0, "%d of %d G7 sample defs fall back to the placeholder" % [ph, TEAM.size() + DEFS.size()])
	pt._log("artcn7_helipad_shown", pad_ok, "display-only helipad + parked dropship (ramp_down frame) sprites")
	_zoom(mv, 1.0)
	mv.center_camera_on(base + Vector2(0.0, 0.6))
	await pt._wait(1.5)
	await pt._shot("artcn7_side_by_side_zoom1")
	_zoom(mv, 2.0)
	mv.center_camera_on(base + Vector2(0.5, 0.6))
	await pt._wait(1.0)
	await pt._shot("artcn7_side_by_side_zoom2")
	_zoom(mv, 3.0)
	mv.center_camera_on(base + Vector2(-1.6, 0.6))
	await pt._wait(1.0)
	await pt._shot("artcn7_side_by_side_zoom3")
	_zoom(mv, 3.0)
	mv.center_camera_on(lz + Vector2(-0.8, 0.0))
	await pt._wait(1.0)
	await pt._shot("artcn7_dropship_pad_zoom3")
	# rev4: loading through the open rear door, real depth (load sheets): APC driving up the ramp into the lit bay
	# (door toward the camera), a squad walking up behind a second craft (XL, side-on), and a craft whose door faces
	# away (the file behind it is hidden by the hull)
	var ld := base + Vector2(-2.0, 10.0)
	var ok1 := _craft(mv, ld, "g7_cn_stealth_dropship_apcload", "apc_load_3", 5)
	var ok2 := _craft(mv, ld + Vector2(7.0, -1.0), "g7_a_vtol_dropship_xl_squadload", "squad_load_1", 6)
	var ok3 := _craft(mv, ld + Vector2(1.0, -6.0), "g7_cn_stealth_dropship_squadload", "squad_load_2", 1)
	pt._log("artcn7_loading_shown", ok1 and ok2 and ok3, "display-only load-sheet sprites (apc_load_3 f5, XL squad_load_1 f6, squad_load_2 f1)")
	for z in [1.0, 2.0, 3.0]:
		_zoom(mv, z)
		mv.center_camera_on(ld + (Vector2(3.0, -2.5) if z < 2.5 else Vector2(0.3, -0.6)))
		await pt._wait(1.0)
		await pt._shot("artcn7_loading_zoom%d" % int(z))
	_zoom(mv, 3.0)
	mv.center_camera_on(ld + Vector2(6.0, -2.2))
	await pt._wait(1.0)
	await pt._shot("artcn7_loading_squad_zoom3")
	pt._log("artcn7_units_spawned", w.entities.size() > n, "entities %d" % w.entities.size())
