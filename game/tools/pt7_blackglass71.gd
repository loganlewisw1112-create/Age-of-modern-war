extends RefCounted
## G7.1 mockup flow blackglass71 (owner request 2026-10-31, J15 Site Blackglass, v4 engineered pass): the reverse-engineering
## complex in a live match. Display-only art from .plan/blackglass4/gen2.gd (drawn from the audited site.json) placed at world tiles through the game's
## own world_to_screen; real sim units on top. Two views: FULL (mountain intact) and CUT (mountain sliced open at the
## section plane, every interior level visible, the sliced-off rock as a see-through ghost). Day and night shots.
## Not a gameplay test: nothing here is wired into content.
##   godot --path . -- --ui-playtest=<shot dir> --ui-playtest-blackglass71

const H = preload("res://tests/test_machine_g6.gd")
const DIR := "res://.plan/blackglass4/art/"
const Elevation = preload("res://sim/systems/elevation.gd")

var sprites: Array = []   # [{node, view, glow}]
var O := Vector2.ZERO     # world tile of the art's metre origin (0, 0)


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


## Camera on a world point in metres (x, y, z): the ground point that projects to the same screen spot.
func _look(mv, x: float, y: float, z := 0.0) -> void:
	var k := z * 9.8 / 8.0
	mv.center_camera_on(O + Vector2(x - k, y - k) / 4.0)


func _tex(file: String) -> ImageTexture:
	return ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(DIR + file)))


func _place(mv) -> int:
	var meta = JSON.parse_string(FileAccess.get_file_as_string(DIR + "pieces.json"))
	var keys: Array = meta.keys()
	keys.sort_custom(func(a, b): return float(meta[a].ord) < float(meta[b].ord))
	var base: Vector2 = mv.world_to_screen(O)
	for k in keys:
		var m: Dictionary = meta[k]
		var org := Vector2(m.origin[0], m.origin[1])
		for gl in [false, true]:
			var sp := Sprite2D.new()
			sp.name = ("BG2G_" if gl else "BG2_") + String(k)
			sp.texture = _tex(String(m.glow if gl else m.file))
			sp.centered = false
			sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sp.position = base - org
			if gl:
				sp.z_index = 4
				var mat := CanvasItemMaterial.new()
				mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
				sp.material = mat
			else:
				sp.z_index = 1 if String(m.layer) == "under" else 2
			mv.add_child(sp)
			sprites.append({"node": sp, "view": String(m.get("view", "both")), "glow": gl})
	return keys.size()


func _view(view: String, night: bool) -> void:
	for s in sprites:
		var v: String = s.view
		var on := v == "both" or v == view or (view == "overlay" and v == "full")
		(s.node as Sprite2D).visible = on and (night or not bool(s.glow))


func _hide_panels(n: Node) -> void:
	for ch in n.get_children():
		var nm := String(ch.name).to_lower()
		var hide := nm.contains("objective") or nm.contains("victory")
		if ch is Label or ch is RichTextLabel or ch is Button:
			var t := String(ch.text).strip_edges()
			hide = hide or t.begins_with("OBJECTIVES") or t.contains("OBJECTIVES ") or t.begins_with("STAGE ") or t.begins_with("VICTORY")
		if ch is Label and String(ch.text).strip_edges() == "PAUSED":
			(ch as Control).modulate = Color(1, 1, 1, 0)   # the HUD re-shows it every frame; make it invisible instead
		if hide:
			var p: Node = ch
			while p != null and not (p is PanelContainer or p is Panel):
				p = p.get_parent()
			var c: Control = p if (p != null and p is Control) else (ch as Control)
			if c != null:
				c.modulate = Color(1, 1, 1, 0)
		_hide_panels(ch)


func _u(h, w, def: String, mx: float, my: float) -> bool:
	if Content.unit(def).is_empty():
		return false
	h._unit(w, def, 0, O + Vector2(mx, my) / 4.0)
	return true


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	var w: SimWorld = pt._w()
	var h = H.new()
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	O = Vector2(clampi(32, 28, maxi(28, mw - 66)), clampi(24, 13, maxi(13, mh - 75)))
	var gone := 0
	for id in w.entities.keys():
		var e = w.entities[id]
		var p := Vector2(e.pos)
		if p.x > O.x - 30 and p.x < O.x + 67 and p.y > O.y - 18 and p.y < O.y + 76:
			if String(e.kind) != "building":
				w.destroy(int(id), "mockup")
				gone += 1
			elif bool(Content.building(String(e.def)).get("is_hq", false)):
				e.pos = Vector2(mw - 3, mh - 3)   # the map's HQ stands where the mockup is: park it in a far corner (keeps the side alive)
				gone += 1
			else:
				w.destroy(int(id), "mockup")
				gone += 1
	pt._log("bg2_site", true, "map %dx%d, art origin tile %s, cleared %d" % [mw, mh, str(O), gone])
	if mv.get("fog_layer") != null:
		mv.fog_layer.visible = false
	if mv.get("entity_layer") != null:
		for y in range(maxi(0, int(O.y) - 18), mini(mh, int(O.y) + 76)):
			for x in range(maxi(0, int(O.x) - 30), mini(mw, int(O.x) + 67)):
				mv.entity_layer.cleared[y * mw + x] = true
	_hide_panels(pt.get_tree().root)
	var n := _place(mv)
	pt._log("bg2_pieces", n >= 95, "%d pieces" % n)
	var ok := 0
	for e in [["g7_sent_warden", 176, 138], ["g7_sent_gunner", 165, 126], ["g7_sent_marksman", 120, 140], ["g7_sent_bulwark", 60, 128],
			["g7_sent_lancer", 40, 150], ["g7_sent_arc", 150, 200], ["g7_sent_warden", 96, 168], ["g7_sent_gunner", 30, 160],
			["g7_cns_purifier", 118, 76], ["g7_cns_purifier", 134, 77], ["g7_op_purge", 124, 52], ["g7_op_emp", 108, 52],
			["a_ugv", 158, 160], ["a_ugv", 158, 166], ["g6_ugv_gun", 100, 140], ["g6_ugv_gun", 36, 140],
			["g8_cargo_carrier", 75, 140], ["g8_cargo_carrier", 140, 132],
			["cn_gun_drone", 60, 60], ["cn_gun_drone", 150, 100], ["cn_gun_drone", 100, 200], ["cn_gun_drone", 170, 10],
			["g7_a_strike_drone", 244, 40], ["g7_a_strike_drone", 244, 150]]:
		if _u(h, w, String(e[0]), float(e[1]), float(e[2])):
			ok += 1
	pt._log("bg2_units", ok >= 18, "%d units" % ok)
	await pt._wait(1.0)
	mv.paused = true   # freeze the sim for the shoot (no alerts or fights moving things between shots)
	await pt._wait(0.3)
	_hide_panels(pt.get_tree().root)
	var shots := 0
	# ---- FULL view, day then night
	for night in [false, true]:
		_view("full", night)
		if mv.get("fac_atmo7") != null and mv.fac_atmo7.has_method("set_time_of_day"):
			mv.fac_atmo7.set_time_of_day("night" if night else "day")
		await pt._wait(3.0 if night else 0.5)
		var tag := "night" if night else "day"
		var list := [["overview", 0.34, Vector3(80, 110, 0)], ["gates_east", 0.9, Vector3(186, 80, 6)], ["capture_loop", 1.0, Vector3(118, 55, 0)],
			["intake_tube", 1.2, Vector3(40, 38, 4)], ["zone_line", 1.1, Vector3(70, 92, 0)], ["clean_band", 1.0, Vector3(80, 116, 0)],
			["garrison", 0.75, Vector3(90, 180, 0)], ["helipads", 1.1, Vector3(100, 182, 0)], ["magazines", 1.2, Vector3(22, 196, 0)],
			["motorpool_fuel", 1.0, Vector3(168, 185, 0)], ["perimeter_se", 0.75, Vector3(206, 236, 0)], ["rail_band", 1.0, Vector3(130, 8, 2)],
			["mountain_summit", 0.75, Vector3(-30, 90, 48)], ["pads_z2", 1.6, Vector3(-38, 112, 48)],
			["face_wide", 0.55, Vector3(0, 100, 20)], ["face_main_portal", 1.0, Vector3(6, 132, 12)], ["face_hazard_rail", 1.0, Vector3(6, 20, 10)],
			["face_galleries", 1.3, Vector3(0, 70, 22)], ["face_lift", 1.3, Vector3(2, 100, 28)], ["face_rampart", 1.2, Vector3(-6, 175, 46)],
			["face_bastion_sw", 1.2, Vector3(6, 196, 10)], ["cove_north", 0.7, Vector3(90, -46, 12)], ["cove_sw", 0.8, Vector3(-14, 248, 12)],
			["airfield_wide", 0.55, Vector3(-52, 100, 48)], ["airfield_stands", 1.1, Vector3(-48, 70, 48)], ["drone_station", 1.4, Vector3(-80, 92, 48)],
			["airfield_south", 1.0, Vector3(-50, 150, 48)], ["rail_portal", 1.1, Vector3(6, 2, 8)], ["wall_sponsons", 1.0, Vector3(190, 100, 8)], ["cargo_pad", 1.4, Vector3(126, 180, 2)], ["turrets_north", 0.75, Vector3(100, -10, 10)], ["turrets_south", 0.75, Vector3(100, 240, 10)], ["turrets_east", 0.6, Vector3(190, 115, 10)], ["corner_ne", 1.3, Vector3(190, -10, 12)], ["corner_se", 1.3, Vector3(190, 240, 12)],
			["atc", 1.2, Vector3(-35, 14, 60)], ["drone_factory", 1.4, Vector3(-85, 164, 51)], ["medevac_station", 1.4, Vector3(46, 188, 0)],
			["hauler_stands", 1.1, Vector3(-80, 45, 48)], ["apache_stand", 1.6, Vector3(-43, 68, 48)], ["obs_window", 1.1, Vector3(0, 135, 34)],
			["core_hall", 1.5, Vector3(-4, 95, 6)], ["staff_blocks", 1.0, Vector3(16, 195, 8)]]
		if night:
			list = [list[0], list[1], list[2], list[4], list[6], list[14], list[15]]
		for s in list:
			_zoom(mv, float(s[1]))
			var c: Vector3 = s[2]
			_look(mv, c.x, c.y, c.z)
			await pt._wait(0.7)
			await pt._shot("bg2_full_%s_%s" % [tag, String(s[0])])
			shots += 1
	# ---- CUT view (section), day then night
	for night in [false, true]:
		_view("cut", night)
		if mv.get("fac_atmo7") != null and mv.fac_atmo7.has_method("set_time_of_day"):
			mv.fac_atmo7.set_time_of_day("night" if night else "day")
		await pt._wait(3.0 if night else 0.5)
		var tag := "night" if night else "day"
		var list := [["overview", 0.4, Vector3(10, 120, 0)], ["section", 0.7, Vector3(-46, 152, 8)], ["levelA_z2", 1.4, Vector3(-46, 150, 38)],
			["levelB_z2", 1.4, Vector3(-46, 150, 22)], ["levelC_z2", 1.4, Vector3(-50, 150, 6)], ["freight_tunnel_z2", 1.6, Vector3(-14, 150, 5)],
			["levelD_z2", 1.4, Vector3(-60, 150, -8)], ["levelE_z2", 1.4, Vector3(-62, 150, -24)]]
		if night:
			list = [list[0], list[1], list[3]]
		for s in list:
			_zoom(mv, float(s[1]))
			var c: Vector3 = s[2]
			_look(mv, c.x, c.y, c.z)
			await pt._wait(0.7)
			await pt._shot("bg2_cut_%s_%s" % [tag, String(s[0])])
			shots += 1
	# ---- tactical / flow overlay over the full view
	_view("overlay", false)
	if mv.get("fac_atmo7") != null and mv.fac_atmo7.has_method("set_time_of_day"):
		mv.fac_atmo7.set_time_of_day("day")
	await pt._wait(2.5)
	for s in [["overview", 0.3, Vector3(100, 110, 0)], ["hazard", 0.7, Vector3(110, 50, 0)], ["garrison", 0.7, Vector3(100, 180, 0)]]:
		_zoom(mv, float(s[1]))
		var c: Vector3 = s[2]
		_look(mv, c.x, c.y, c.z)
		await pt._wait(0.7)
		await pt._shot("bg2_overlay_%s" % String(s[0]))
		shots += 1
	pt._log("bg2_shots", shots >= 20, "%d shots" % shots)
