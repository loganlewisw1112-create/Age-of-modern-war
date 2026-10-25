extends "res://tests/test_base.gd"
## G6 art (owners: ART-G6, then ART-G6b; CONTRACTS_G6 s3.1, s3.2, s17). Every s3.1 id has art in
## res://assets/art/g6_units/ (units: 8 facings x frames + team mask, wrecks for vehicles, squad sizes from
## the art kit, b_conscripts on its own 64x44 frame) or res://assets/art/g6_bld/ (buildings: rot_0..3, each
## damaged and build_0..2, built / damaged / build_<n> = rotation 0), a 32x32 icon, a lod class; shipped files
## match their manifest md5s; the generator reproduces two modules byte-identically; no deferred x_* id ships.
## new_pieces_* (s3.2) is ART-G6b's: it checks the same properties for the company / exo ids.

const M = preload("res://tools/art/g6_art.gd")
const H = preload("res://tools/art/g6_lib.gd")
const GEN = preload("res://tools/gen_art.gd")
const UBASE := "res://assets/art/g6_units/"
const BBASE := "res://assets/art/g6_bld/"
## CONTRACTS_G6 s3.1 U / S ids (fixed here, independent of the generator tables); value = squad size or 0.
const S31_UNITS := {"a_aerostat": 0, "a_loiter_truck": 0, "b_jammer_team": 2, "b_scrap_aa": 3, "m_swarm_queen": 0,
	"m_mimic_drone": 0, "a_sp_howitzer": 0, "a_mlrs": 0, "a_mine_clearer": 0, "a_bridge_layer": 0, "a_command_vehicle": 0,
	"a_ugv": 0, "b_landship": 0, "b_flak_halftrack": 0, "b_armored_dozer": 0, "b_salvage_crane": 0, "b_moto_scouts": 0,
	"m_spider_layer": 0, "m_hover_tank": 0, "m_colossus": 0, "m_assimilator": 0, "a_marines": 4, "a_paratroopers": 4,
	"a_eod": 2, "a_jtac": 2, "a_manpads": 2, "b_conscripts": 10, "b_satchel_sappers": 3, "b_marksman": 1,
	"b_propaganda_team": 2, "m_shield_drone": 0, "m_stalker_synth": 0, "m_repair_swarm2": 0, "m_breacher_crawler": 0,
	"a_awacs": 0, "a_airlift": 0, "b_recon_plane": 0, "m_stealth_drone": 0, "a_supply_ship_a": 0, "a_minesweeper": 0,
	"a_hovercraft": 0, "a_carrier": 0, "a_submarine": 0, "b_supply_ship_b": 0, "b_mine_barge": 0, "b_aa_barge": 0,
	"m_charge_tender": 0, "m_lance_cruiser": 0, "b_armored_train": 0, "a_laser_tank": 0, "a_exo_trooper": 0, "b_rhomboid": 0}
const S31_BLDS := ["a_atgm_bunker", "a_sam_site", "a_laser_ciws", "a_howitzer_pit", "a_popup_turret", "b_pak_nest",
	"b_flak_battery", "b_net_post", "b_mortar_pit", "b_pillbox", "m_arc_pylon", "m_pulse_spire2", "m_jammer_obelisk",
	"m_mass_driver", "m_sentry_mine", "m_nanite_wall", "m_phase_gate", "s_sandbags", "s_trench", "s_tank_traps",
	"s_barbed_wire", "s_minefield", "s_garrison_bld", "s_camo_decoy", "a_drone_cc", "b_fpv_workshop", "m_hive_node",
	"a_radar_station", "a_fob", "a_repair_bay", "a_cruise_battery", "b_rail_yard", "b_scrapyard", "b_propaganda_tower",
	"m_nanite_forge", "m_overmind", "m_relay_lattice"]
const S32_UNITS := ["a_commander", "b_commander", "m_commander", "a_captain", "a_lieutenant", "b_captain",
	"b_lieutenant", "m_captain", "m_lieutenant", "a_exo_rifle", "a_exo_missile", "a_exo_aa"]
const S32_BLDS := ["a_company_hq", "b_company_hq", "m_company_hq", "a_exo_garage"]
const LOD := ["infantry", "vehicle_light", "vehicle_heavy", "artillery", "air", "naval"]


func _json(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}


func _img(base: String, rel: String) -> Image:
	if rel == "" or not FileAccess.file_exists(base + rel):
		return null
	var im := Image.load_from_file(base + rel)
	im.convert(Image.FORMAT_RGBA8)
	return im


func _opaque(im: Image) -> int:
	var n := 0
	for y in range(0, im.get_height(), 2):
		for x in range(0, im.get_width(), 2):
			if im.get_pixel(x, y).a > 0.6:
				n += 1
	return n


func _unit_ok(man: Dictionary, id: String, squad: int) -> void:
	var inf: Dictionary = man.get("infantry", {})
	var e: Dictionary = inf.get(id, man.get("vehicles", {}).get(id, {}))
	if not check(not e.is_empty(), "unit art for " + id):
		return
	var sheet := _img(UBASE, String(e.get("file", "")))
	var mask := _img(UBASE, String(e.get("mask", "")))
	if not check(sheet != null and mask != null, "%s sheet + mask load" % id):
		return
	var fw: int = e.fw
	var fh: int = e.fh
	var nf: int = (e.frames as Array).size()
	check_eq(sheet.get_size(), Vector2i(fw * nf, fh * 8), "%s sheet = %d frames x 8 facings" % [id, nf])
	check_eq(mask.get_size(), sheet.get_size(), "%s mask size" % id)
	check_eq(int(e.get("facings", 8)), 8, "%s facings" % id)
	var drawn := 0
	for k in 8:
		if _opaque(H.frame(sheet, fw, fh, 0, k)) > 3:
			drawn += 1
	check_eq(drawn, 8, "%s frame 0 drawn at all 8 facings" % id)
	check(mask.get_used_rect().size.x > 0, "%s has team pixels" % id)
	check(LOD.has(String(man.get("lod_class", {}).get(id, ""))), "%s lod class (%s)" % [id, man.get("lod_class", {}).get(id, "")])
	if inf.has(id):
		if squad > 0:
			check_eq(int(e.squad_size), squad, "%s squad size (art kit)" % id)
		var al: Dictionary = e.get("alive_sheets", {})
		check_eq(al.size(), int(e.squad_size) - 1, "%s alive sheets 1..n-1" % id)
		for a in al:
			var im := _img(UBASE, String(al[a].file))
			check(im != null and im.get_size() == sheet.get_size(), "%s alive %s sheet" % [id, a])
	else:
		var wr: Dictionary = man.get("vehicle_wrecks", {}).get(id, {})
		var wi := _img(UBASE, String(wr.get("file", "")))
		check(wi != null and _opaque(wi) > 3, "%s wreck sheet" % id)


func _bld_ok(man: Dictionary, id: String) -> void:
	var e: Dictionary = man.get("buildings", {}).get(id, {})
	if not check(not e.is_empty() and e.has("states"), "building art for " + id):
		return
	var st: Dictionary = e.states
	var built := _img(BBASE, String(st.get("built", {}).get("file", "")))
	var rots: Dictionary = {}
	for nm in H.state_names():
		if not check(st.has(nm), "%s has state %s" % [id, nm]):
			continue
		var im := _img(BBASE, String(st[nm].file))
		var mk := _img(BBASE, String(st[nm].get("mask", "")))
		if not check(im != null and mk != null, "%s %s image + mask load" % [id, nm]):
			continue
		check(built == null or im.get_size() == built.get_size(), "%s %s same canvas as built" % [id, nm])
		check_eq(mk.get_size(), im.get_size(), "%s %s mask size" % [id, nm])
		check(_opaque(im) > 6, "%s %s is drawn" % [id, nm])
		check(mk.get_used_rect().size.x > 0, "%s %s has team pixels" % [id, nm])
		var pv: Array = e.pivot
		check(int(pv[0]) > 0 and int(pv[0]) < im.get_width() and int(pv[1]) > 0 and int(pv[1]) < im.get_height(), "%s pivot inside %s" % [id, nm])
		if nm.begins_with("rot_") and nm.length() == 5:
			rots[nm] = im
	for f in 4:
		var r := "rot_%d" % f
		if not rots.has(r):
			continue
		var dm := _img(BBASE, String(st.get(r + "_damaged", {}).get("file", "")))
		check(dm != null and dm.get_data() != (rots[r] as Image).get_data(), "%s %s damaged differs from built" % [id, r])
		var b0 := _img(BBASE, String(st.get(r + "_build_0", {}).get("file", "")))
		var b2 := _img(BBASE, String(st.get(r + "_build_2", {}).get("file", "")))
		check(b0 != null and b2 != null and b0.get_data() != b2.get_data() and b2.get_data() != (rots[r] as Image).get_data(), "%s %s build stages differ" % [id, r])
	if rots.size() == 4:
		var distinct := {}
		for r in rots:
			distinct[(rots[r] as Image).get_data().hex_encode().md5_text()] = true
		check(distinct.size() >= 2, "%s rotations are rendered per facing (%d distinct)" % [id, distinct.size()])


func _files_ok(base: String, man: Dictionary) -> void:
	var files: Dictionary = man.get("files", {})
	check(files.size() > 0, base + " manifest lists its files")
	var bad := 0
	for rel in files:
		if not FileAccess.file_exists(base + rel) or GEN.md5(FileAccess.get_file_as_bytes(base + rel)) != String(files[rel]):
			bad += 1
	check_eq(bad, 0, base + " shipped files match their md5s")


func _no_x(man: Dictionary, label: String) -> void:
	var xs: Array = []
	for sec in ["infantry", "vehicles", "vehicle_wrecks", "buildings", "icons", "lod_class"]:
		for k in man.get(sec, {}):
			if String(k).begins_with("x_"):
				xs.append(k)
	check(xs.is_empty(), "%s ships no deferred x_* id %s" % [label, str(xs)])


func test_manifest_has_every_unit_id() -> void:
	var man := _json(UBASE + "manifest.json")
	if not check(not man.is_empty(), "assets/art/g6_units/manifest.json exists (run tools/art/g6_art_gen.gd)"):
		return
	check_eq(String(man.get("group", "")), "g6_units", "g6_units group name")
	check_eq(S31_UNITS.size(), 52, "52 s3.1 unit / squad ids")
	for id in S31_UNITS:
		check(M.UNITS.has(id), "%s in g6_art.UNITS" % id)
		_unit_ok(man, id, int(S31_UNITS[id]))
	_no_x(man, "g6_units")
	_files_ok(UBASE, man)


func test_manifest_has_every_building_id_4_rotations_damaged_build() -> void:
	var man := _json(BBASE + "manifest.json")
	if not check(not man.is_empty(), "assets/art/g6_bld/manifest.json exists (run tools/art/g6_art_gen.gd)"):
		return
	check_eq(String(man.get("group", "")), "g6_bld", "g6_bld group name")
	check_eq(S31_BLDS.size() + S31_UNITS.size(), 89, "89 s3.1 page assets")
	var content: Dictionary = _json("res://content/g6/defs_bld_g6.json").get("buildings", {})
	var sized := 0
	for id in S31_BLDS:
		check(M.BLDS.has(id), "%s in g6_art.BLDS" % id)
		_bld_ok(man, id)
		check_eq(String(man.get("g6_bld", {}).get("variants", {}).get(id, "")), "rot", "%s variant kind rot" % id)
		if content.has(id) and content[id].has("size"):
			sized += 1
			check_eq(int(man.buildings.get(id, {}).get("size", -1)), int(content[id].size), "%s footprint matches content/g6" % id)
	print("    g6_bld: %d of %d footprints cross-checked against content/g6/defs_bld_g6.json" % [sized, S31_BLDS.size()])
	_no_x(man, "g6_bld")
	_files_ok(BBASE, man)


func test_icon_for_every_id() -> void:
	var um := _json(UBASE + "manifest.json")
	var bm := _json(BBASE + "manifest.json")
	var ids: Array = S31_UNITS.keys()
	ids.append_array(S31_BLDS)
	for id in ids:
		var base := BBASE if S31_BLDS.has(id) else UBASE
		var rel := String((bm if base == BBASE else um).get("icons", {}).get(id, ""))
		var im := _img(base, rel)
		if not check(im != null, "icon for " + id):
			continue
		check_eq(im.get_size(), Vector2i(32, 32), "%s icon is 32x32" % id)
		check(_opaque(im) > 20, "%s icon is drawn" % id)


func test_new_pieces_company_hq_commanders_leaders_garage_suits() -> void:
	var um := _json(UBASE + "manifest.json")
	var bm := _json(BBASE + "manifest.json")
	for id in S32_UNITS:
		_unit_ok(um, id, 0)
		check(_img(UBASE, String(um.get("icons", {}).get(id, ""))) != null, "icon for " + id)
	for id in S32_BLDS:
		_bld_ok(bm, id)
		check(_img(BBASE, String(bm.get("icons", {}).get(id, ""))) != null, "icon for " + id)


func test_conscripts_squad_frame_64x44() -> void:
	var man := _json(UBASE + "manifest.json")
	var e: Dictionary = man.get("infantry", {}).get("b_conscripts", {})
	if not check(not e.is_empty(), "b_conscripts squad art"):
		return
	check_eq([int(e.fw), int(e.fh)], [64, 44], "b_conscripts frame is 64x44")
	check_eq(int(e.squad_size), 10, "b_conscripts squad of 10")
	var sheet := _img(UBASE, String(e.file))
	check(sheet != null and sheet.get_size() == Vector2i(64 * (e.frames as Array).size(), 44 * 8), "b_conscripts sheet uses the 64x44 frame")
	check_eq((e.get("alive_sheets", {}) as Dictionary).size(), 9, "b_conscripts alive sheets 1..9")
	var m: Dictionary = man.get("infantry", {}).get("b_marksman", {})
	check_eq([int(m.get("fw", 0)), int(m.get("fh", 0))], [48, 36], "other squads keep the 48x36 frame")
	var sf: Array = man.get("g6_units", {}).get("squad_frames", {}).get("b_conscripts", [0, 0])
	check_eq([int(sf[0]), int(sf[1])], [64, 44], "manifest flags the per-def squad frame")


func test_generator_reproduces_modules_byte_identically() -> void:
	var r: Dictionary = M.generate(["g6_forts", "g6_horizon"])
	var um := _json(UBASE + "manifest.json")
	var bm := _json(BBASE + "manifest.json")
	var n := 0
	var bad: Array = []
	for pair in [[r.units, um], [r.bld, bm]]:
		var files: Dictionary = pair[1].get("files", {})
		for rel in pair[0].images:
			n += 1
			if GEN.md5((pair[0].images[rel] as Image).save_png_to_buffer()) != String(files.get(rel, "")):
				bad.append(rel)
	check(n > 200, "regenerated %d images (g6_forts + g6_horizon)" % n)
	check(bad.is_empty(), "regenerated images match the shipped md5s %s" % str(bad.slice(0, 5)))


## ART-G6b task 4 (PLAN_G6 s3): an icon for every CONTRACTS_G6 s4 command (fixed list here) in the g6_bld group,
## plus the mine marker / garrison pip / sonar ping effect sheets.
const S4_COMMANDS := ["market_trade", "train_company", "train_commander", "form_army", "disband_army",
	"set_company_refill", "set_loadout", "resuit", "lay_minefield", "sweep", "line_charge", "tow_wreck", "breach",
	"garrison", "ungarrison", "build_rail", "deploy_bridge", "pack_bridge", "airdrop", "designate", "aerostat",
	"strike", "assimilate", "cloak", "submerge", "set_ai_commander", "recall_ai_commander", "ally_request"]


func test_command_icons_and_fx_sheets() -> void:
	var bm := _json(BBASE + "manifest.json")
	var icons: Dictionary = bm.get("icons", {})
	for k in S4_COMMANDS:
		check(SimWorld.COMMANDS.has(k), "s4 command %s is registered" % k)
		var im := _img(BBASE, String(icons.get(k, "")))
		if not check(im != null and im.get_size() == Vector2i(32, 32), "32x32 icon for command " + k):
			continue
		var ink := 0
		for y in range(4, 28):
			for x in range(4, 28):
				var c := im.get_pixel(x, y)
				if c.r + c.g + c.b > 1.2:
					ink += 1
		check(ink > 12, "%s icon has a visible glyph (%d bright px)" % [k, ink])
	var fx: Dictionary = bm.get("fx_g6", {})
	for nm in ["mine_marker", "garrison_pip", "sonar_ping"]:
		var e: Dictionary = fx.get(nm, {})
		var im := _img(BBASE, String(e.get("file", "")))
		if not check(im != null, "fx sheet " + nm):
			continue
		check_eq(im.get_size(), Vector2i(int(e.fw) * int(e.frames), int(e.fh)), "%s sheet = %d frames" % [nm, int(e.frames)])
		for f in int(e.frames):
			check(H.frame(im, int(e.fw), int(e.fh), f, 0).get_used_rect().size.x > 2, "%s frame %d drawn" % [nm, f])
	var pm := _img(BBASE, String(fx.get("garrison_pip", {}).get("mask", "")))
	check(pm != null and pm.get_used_rect().size.x > 0, "garrison pip has team pixels")
