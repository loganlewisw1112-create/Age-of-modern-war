extends RefCounted
## G7 playtest flow sentart7 (SENTART7; G7_REFERENCE 13.9c-10/-11/-13): the Sentinel art in the real game.
## 1) In the open: a pose board cut from the real sheets (display-only sprites, team-tinted like the live tint) with
##    every type x idle / aim / fire / reload / sidearm / crouch / drag, Human A and Human B, at zoom 1 / 1.75 / 2.5,
##    plus real Sentinel units of all 16 defs drawn by the live view next to it (sheets must resolve, not placeholder).
## 2) On the wall top: the player's counter-nanite facility rises with its self-running Sentinel garrison (SENT7);
##    shots of the wall-walk and towers at the same three zooms.

const H = preload("res://tests/test_machine_g6.gd")
const AC = preload("res://presentation/art/art_catalog.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const S7 = preload("res://sim/systems/sentinels7.gd")
const WallWalk7 = preload("res://sim/systems/wallwalk7.gd")
const TYPES := ["warden", "marksman", "gunner", "bulwark", "lancer", "arc", "mender", "bearer"]
const POSES := ["idle", "aim", "fire", "reload_0", "sa_fire", "crouch", "drag_0"]
const TEAM := Color("#4f7db0")
const ROOT := "res://assets/art/g7_sentinels/"

var _man: Dictionary = {}
var _img: Dictionary = {}


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _shots(pt, mv, at: Vector2, tag: String) -> void:
	for z in [1.0, 1.75, 2.5]:
		_zoom(mv, z)
		mv.center_camera_on(at)
		await pt._wait(0.8)
		await pt._shot("sentart7_%s_z%d" % [tag, int(z * 100)])


func _sheet(rel: String) -> Image:
	if not _img.has(rel):
		var im := Image.load_from_file(ProjectSettings.globalize_path(ROOT + rel))
		im.convert(Image.FORMAT_RGBA8)
		_img[rel] = im
	return _img[rel]


## Display-only sprite of sheet `id`, frame fname, facing row k at world tile `at` (team mask tinted), drawn just
## below the entity layer. Returns false when the sheet / frame is missing.
func _pose(mv, at: Vector2, id: String, fname: String, k: int) -> bool:
	var layer = mv.get("entity_layer")
	var e: Dictionary = (_man.get("infantry", {}) as Dictionary).get(id, {})
	if layer == null or e.is_empty() or not (e.frames as Array).has(fname):
		return false
	var col := (e.frames as Array).find(fname)
	var cell := _sheet(String(e.file)).get_region(Rect2i(col * 32, k * 32, 32, 32))
	var mc := _sheet(String(e.mask)).get_region(Rect2i(col * 32, k * 32, 32, 32))
	for y in 32:
		for x in 32:
			if mc.get_pixel(x, y).a > 0.0:
				var c := cell.get_pixel(x, y)
				var kk := 0.45 + c.r * 0.9
				cell.set_pixel(x, y, Color(TEAM.r * kk, TEAM.g * kk, TEAM.b * kk, c.a))
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
	if Content.building("a_cn_facility").is_empty() or Content.unit("g7_sent_warden").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()
	_man = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	# ---- every def resolves to its own sheet (not the placeholder)
	var ph := 0
	var ids: Array = []
	for pre in ["g7_sent_", "g7_b_sent_"]:
		for t in TYPES:
			ids.append(pre + t)
	for d in ids:
		var tx: Texture2D = AC.entity_sprite({"kind": "unit", "def": d, "facing": 0.0}, TEAM, 0).texture
		if tx == AC.placeholder_for({"kind": "unit", "def": d}, TEAM).texture:
			ph += 1
	pt._log("sentart7_sheets_resolve", ph == 0, "%d of %d Sentinel defs fall back to the placeholder" % [ph, ids.size()])
	# ---- 1) open ground: pose boards (A front, A three-quarter back, B front) + the real units
	var c: Vector2i = h._open(w, 14)
	var base := Vector2(c) + Vector2(-6.0, -6.0)
	var drawn := 0
	var want := 0
	for bi in 3:
		var pre := "g7_b_sent_" if bi == 2 else "g7_sent_"
		var k := 3 if bi == 1 else 1
		for ti in TYPES.size():
			for pi in POSES.size():
				want += 1
				# screen-aligned grid: +x on screen = (+1, -1) tiles, +y on screen = (+1, +1) tiles
				var at := base + Vector2(0.44, -0.44) * (pi + bi * 8) + Vector2(0.81, 0.81) * ti
				if _pose(mv, at, pre + String(TYPES[ti]), String(POSES[pi]), k):
					drawn += 1
	pt._log("sentart7_pose_board", drawn == want, "%d of %d pose sprites cut from the sheets (idle aim fire reload sidearm crouch drag; A f1, A f3, B f1)" % [drawn, want])
	var n0 := w.entities.size()
	for i in ids.size():
		var id := w.spawn_unit(String(ids[i]), me, base + Vector2(0.44, -0.44) * (i * 1.45) + Vector2(0.81, 0.81) * 9.0)
		if w.entities.has(id):
			w.entities[id].facing = PI * 0.25
	mv.join_sim()
	pt._log("sentart7_units_spawned", w.entities.size() - n0 == ids.size(), "%d live Sentinel units" % (w.entities.size() - n0))
	await _shots(pt, mv, base + Vector2(0.44, -0.44) * 7.0 + Vector2(0.81, 0.81) * 3.5, "board_a")
	await _shots(pt, mv, base + Vector2(0.44, -0.44) * 19.0 + Vector2(0.81, 0.81) * 3.5, "board_b")
	await _shots(pt, mv, base + Vector2(0.44, -0.44) * 6.0 + Vector2(0.81, 0.81) * 9.0, "live_open")
	# ---- 2) wall top: the facility and its self-running garrison
	var c2: Vector2i = h._open(w, 30)
	var off: Array = CnFacility.conf().core_offset
	var o := c2 - Vector2i(14, 14)
	var fid := w.spawn_building("a_cn_facility", me, o + Vector2i(int(off[0]), int(off[1])), true)
	var n7 := S7.sentinels_of(w, me).size()
	var raised: bool = await pt._wait_until(func(): mv.join_sim(); return S7.sentinels_of(pt._w(), me).size() >= n7 + 8, 15.0)
	mv.join_sim()
	pt._log("sentart7_garrison", raised, "facility %d, %d Sentinels" % [fid, S7.sentinels_of(w, me).size()])
	if not raised:
		return
	var fl: Array = CnFacility.facilities(w, me)
	var F: Dictionary = CnFacility.fac(w, fl[fl.size() - 1])
	var O: Vector2 = Vector2(CnFacility.origin(F))
	var cs := float(CnFacility.conf().get("compound", 28))
	await pt._wait(6.0)   # posts taken, patrols walking
	mv.join_sim()
	var onwall := 0
	for u in S7.sentinels_of(w, me):
		var e = w.entities.get(int(u))
		if e != null and WallWalk7.on_wall(w, e):
			onwall += 1
	pt._log("sentart7_wall_manned", onwall >= 2, "%d Sentinels on the wall top" % onwall)
	await _shots(pt, mv, O + Vector2(cs * 0.5, 1.5), "wall_top")
	await _shots(pt, mv, O + Vector2(1.5, cs * 0.5), "wall_side")
	await _shots(pt, mv, O + Vector2(cs * 0.5, cs * 0.5), "interior")
