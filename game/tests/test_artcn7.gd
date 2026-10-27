extends "res://tests/test_base.gd"
## G7 ARTCN7: DL7 look-checkpoint samples (G7_REFERENCE master scope 0, 6.12, 7, 8). Every sample has its
## facings and key frames in its group manifest, masks are present (team colour lands somewhere), every sheet /
## building stays within the posted per-class memory budget (fact art.detail_level), shipped files match their
## md5s, and the generators are deterministic (same output twice, and byte-identical to the shipped files).

const C = preload("res://tools/art/g7_cn_lib.gd")
const SOL = preload("res://tools/art/g7_cn_soldiers.gd")
const GEN = preload("res://tools/gen_art.gd")
const G7GEN = preload("res://tools/art/g7_cn_gen.gd")

## Fixed here, independent of the generator tables: id -> group.
const SAMPLES := {
	"g7_cn_team_leader": "g7_cn", "g7_cn_radio": "g7_cn", "g7_cn_deploy": "g7_cn", "g7_cn_scanner": "g7_cn",
	"g7_cn_ew": "g7_cn", "g7_cn_gunner": "g7_cn", "g7_cn_medic": "g7_cn",
	"g7_op_leader": "g7_cn", "g7_op_marksman": "g7_cn", "g7_op_hunter": "g7_cn", "g7_op_emp": "g7_cn",
	"g7_op_antidrone": "g7_cn", "g7_op_purge": "g7_cn", "g7_op_medic": "g7_cn",
	"g7_cn_strike_apc": "g7_cn", "g7_op_tactical_apc": "g7_cn", "g7_cn_stealth_dropship": "g7_cn",
	"g7_a_vtol_dropship_xl": "g7_cn", "g7_cn_gate": "g7_cn", "g7_cn_decon": "g7_cn", "g7_cn_garage": "g7_cn",
	"g7_cn_helipad": "g7_cn", "g7_a_hmg_nest": "g7_turrets", "g7_a_rail_cannon": "g7_turrets",
	"g7_m_packhunter": "g7_threats", "g7_m_weaver": "g7_threats", "g7_m_living_core": "g7_threats",
	# rev4 (ARTCN7-5): weapon animation sheets and dropship load sheets
	"g7_cn_strike_apc_gun": "g7_cn", "g7_cn_strike_apc_rkt": "g7_cn", "g7_op_tactical_apc_gun": "g7_cn",
	"g7_op_tactical_apc_rkt": "g7_cn", "g7_cn_stealth_dropship_apcload": "g7_cn", "g7_cn_stealth_dropship_squadload": "g7_cn",
	"g7_cn_stealth_dropship_squadunload": "g7_cn", "g7_a_vtol_dropship_xl_apcload": "g7_cn",
	"g7_a_vtol_dropship_xl_squadload": "g7_cn", "g7_a_vtol_dropship_xl_squadunload": "g7_cn"}
const BLD_STATES := ["built", "damaged", "build_0", "build_1", "build_2", "rot_0", "rot_1", "rot_2", "rot_3",
	"rot_0_damaged", "rot_3_build_2"]


func _man(g: String) -> Dictionary:
	var p := "res://assets/art/%s/manifest.json" % g
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}


func _img(g: String, rel: String) -> Image:
	var p := "res://assets/art/%s/%s" % [g, rel]
	if not FileAccess.file_exists(p):
		return null
	var im := Image.load_from_file(p)
	im.convert(Image.FORMAT_RGBA8)
	return im


func _count(im: Image, r: Rect2i, a_min: float) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if im.get_pixel(x, y).a > a_min:
				n += 1
	return n


func test_every_sample_has_facings_key_frames_masks() -> void:
	for id in SAMPLES:
		var g: String = SAMPLES[id]
		var man := _man(g)
		var s: Dictionary = man.get("g7_samples", {}).get(id, {})
		check(not s.is_empty(), "%s listed in %s g7_samples" % [id, g])
		if s.is_empty():
			continue
		check(String(s.get("detail_level", "")) == C.VERSION, "%s detail level %s" % [id, s.get("detail_level")])
		var kf: Array = s.get("key_frames", [])
		check(kf.size() >= 2, "%s has key frames" % id)
		if String(s.section) == "buildings":
			var e: Dictionary = man.buildings[id]
			var states: Dictionary = e.states
			var mask_px := 0
			for st in BLD_STATES + kf:
				check(states.has(st), "%s state %s" % [id, st])
			for st in kf:
				if states.has(st):
					var im := _img(g, states[st].file)
					check(im != null and _count(im, Rect2i(0, 0, im.get_width(), im.get_height()), 0.6) > 50, "%s %s drawn" % [id, st])
					var mk := _img(g, states[st].mask)
					check(mk != null and mk.get_size() == im.get_size(), "%s %s mask file" % [id, st])
					if mk != null:
						mask_px += _count(mk, Rect2i(0, 0, mk.get_width(), mk.get_height()), 0.0)
			check(mask_px > 0, "%s team mask pixels %d" % [id, mask_px])
			if String(s.get("sample", "")) == "turret":
				for k in 8:
					check(states.has("aim_%d" % k) and states.has("aim_%d_fire" % k), "%s aim_%d (+fire)" % [id, k])
			continue
		var e: Dictionary = man[s.section][id]
		var fr: Array = e.frames
		var fw := int(e.fw)
		var fh := int(e.fh)
		check(int(e.facings) == 8, "%s 8 facings" % id)
		for n in kf:
			check(fr.has(n), "%s key frame %s in frames" % [id, n])
		if String(s.section) == "infantry":
			check(fr == C.FRAMES_INF and fw == C.INF_CELL.x and fh == C.INF_CELL.y, "%s DL7-3 infantry set (24 frames, 32x32)" % id)
			for n in ["idle", "walk_a", "walk_b", "fire"]:
				check(fr.has(n), "%s catalog frame %s" % [id, n])
		else:
			for n in ["idle", "move", "fire"] if String(s.get("sample", "")) == "vehicle" else []:
				check(fr.has(n), "%s catalog frame %s" % [id, n])
		var im := _img(g, e.file)
		var mk := _img(g, e.mask)
		check(im != null and im.get_size() == Vector2i(fw * fr.size(), fh * 8), "%s sheet size" % id)
		check(mk != null and im != null and mk.get_size() == im.get_size(), "%s mask size" % id)
		if im == null or mk == null:
			continue
		var empty := 0
		for k in 8:
			for n in kf:
				if _count(im, Rect2i(fr.find(n) * fw, k * fh, fw, fh), 0.6) < 12:
					empty += 1
		check(empty == 0, "%s key-frame cells drawn in every facing (empty %d)" % [id, empty])
		var mrow := 0
		for k in 8:
			if _count(mk, Rect2i(0, k * fh, fw * fr.size(), fh), 0.0) > 0:
				mrow += 1
		check(mrow >= 6, "%s team mask present in %d/8 facings" % [id, mrow])


func test_memory_within_posted_budget() -> void:
	for id in SAMPLES:
		var g: String = SAMPLES[id]
		var man := _man(g)
		var s: Dictionary = man.get("g7_samples", {}).get(id, {})
		if s.is_empty():
			check(false, "%s missing" % id)
			continue
		var budget := int(C.BUDGET[String(s["class"])])
		check(int(s.budget) == budget, "%s budget %d == posted %d" % [id, int(s.budget), budget])
		var bytes := 0
		if String(s.section) == "buildings":
			var seen := {}
			for st in man.buildings[id].states:
				var f: String = man.buildings[id].states[st].file
				if not seen.has(f):
					seen[f] = true
					var im := _img(g, f)
					bytes += im.get_width() * im.get_height() * 4
		else:
			var e: Dictionary = man[s.section][id]
			var im := _img(g, e.file)
			bytes = C.packed_bytes(im, int(e.fw), int(e.fh), int(s.get("mirror", 1)))
			check(im.get_width() * im.get_height() * 4 == int(s.get("raw_bytes", -1)), "%s raw bytes == manifest" % id)
			check(im.get_width() <= C.PAGE_W and im.get_height() <= C.PAGE_H, "%s fits one atlas page" % id)
		check(bytes == int(s.bytes), "%s measured %d == manifest %d" % [id, bytes, int(s.bytes)])
		check(bytes <= budget, "%s %d bytes <= budget %d" % [id, bytes, budget])


func test_shipped_files_match_md5() -> void:
	for g in ["g7_cn", "g7_turrets", "g7_threats"]:
		var man := _man(g)
		var files: Dictionary = man.get("files", {})
		var n_samples := 0
		for id in SAMPLES:
			if SAMPLES[id] == g:
				n_samples += 1
		check(files.size() >= 2 * n_samples, "%s files listed: %d (>= sheet + mask per sample)" % [g, files.size()])
		var bad := 0
		for rel in files:
			var p := "res://assets/art/%s/%s" % [g, rel]
			if not FileAccess.file_exists(p) or GEN.md5(FileAccess.get_file_as_bytes(p)) != String(files[rel]):
				bad += 1
		check(bad == 0, "%s md5 mismatches: %d" % [g, bad])


func test_generators_deterministic() -> void:
	var a := {"images": {}, "manifest": {}}
	var b := {"images": {}, "manifest": {}}
	SOL.build(a, ["cn_gunner"])
	SOL.build(b, ["cn_gunner"])
	for rel in a.images:
		check((a.images[rel] as Image).get_data() == (b.images[rel] as Image).get_data(), "same output twice: %s" % rel)
	# the turret group regenerated in memory is byte-identical to the shipped files
	var r: Dictionary = G7GEN.generate("g7_turrets")
	var files: Dictionary = _man("g7_turrets").get("files", {})
	var bad := 0
	for rel in r.images:
		if GEN.md5((r.images[rel] as Image).save_png_to_buffer()) != String(files.get(rel, "")):
			bad += 1
	check(r.images.size() > 40 and bad == 0, "g7_turrets regenerated == shipped (%d images, %d differ)" % [r.images.size(), bad])
	var shipped: Dictionary = _man("g7_cn").get("files", {})
	for rel in a.images:
		check(GEN.md5((a.images[rel] as Image).save_png_to_buffer()) == String(shipped.get(rel, "")), "%s == shipped" % rel)


## Figure height in px of one cell: rows holding an opaque (a > 0.6) pixel, so the soft ground shadow is ignored.
func _fig_h(im: Image, r: Rect2i) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if im.get_pixel(x, y).a > 0.6:
				n += 1
				break
	return n


## Owner rev2 decision (2026-10-26, G7_REFERENCE "Look checkpoint rev2 decision"; supersedes the rev1 "1.5x" size
## line): "the units are too big compared to the vehicles and tiles shrink them correctly but keep their high detail
## and quality" -> ONE real-world scale against the 64x32 tile grid (fact art.scale: 4 m per tile, 9.8 px per metre
## of height): a ~1.8 m soldier is ~18 px next to a ~8 m APC. Plus: icons for every sample unit (and the Human B /
## content aliases); wreck sheets for both APCs; the APC rocket pod frames; the dropship VTOL / bay / ramp frames.
func test_rework_owner_feedback() -> void:
	var man := _man("g7_cn")
	var px_m: float = C.SCALE.px_per_m_height
	for id in ["g7_cn_gunner", "g7_op_hunter", "g7_cn_team_leader", "g7_cn_medic"]:
		var e: Dictionary = man.infantry[id]
		var im := _img("g7_cn", e.file)
		var h := _fig_h(im, Rect2i(0, 0, int(e.fw), int(e.fh)))
		check(absf(float(h) - 1.8 * px_m) <= 2.5, "%s figure %d px ~= 1.8 m x %.1f px/m (owner: one real-world scale)" % [id, h, px_m])
	for pr in [["g7_cn_strike_apc", 8.0], ["g7_op_tactical_apc", 7.0]]:   # side-on facing (row 3): length on screen
		var e: Dictionary = man.vehicles[pr[0]]
		var im := _img("g7_cn", e.file)
		var x0 := 99999
		var x1 := -1
		for y in int(e.fh):   # opaque body only (the soft ground shadow is ignored)
			for x in int(e.fw):
				if im.get_pixel(x, 3 * int(e.fh) + y).a > 0.6:
					x0 = mini(x0, x)
					x1 = maxi(x1, x)
		var want: float = float(pr[1]) * C.SCALE.px_per_m_screen_x
		check(absf(float(x1 - x0 + 1) - want) <= 0.12 * want, "%s side-on length %d px ~= %.1f m x %.2f px/m" % [pr[0], x1 - x0 + 1, pr[1], C.SCALE.px_per_m_screen_x])
	for id in ["g7_cn_stealth_dropship", "g7_a_vtol_dropship_xl"]:   # the bay fits the 8 m strike APC (C-17 loading)
		var bay: Dictionary = man.g7_samples[id].get("bay", {})
		var bay_m := (float(bay.get("u0", 0.0)) - float(bay.get("u1", 0.0))) * float(C.SCALE.m_per_tile)
		check(bay_m >= 9.0, "%s bay %.1f m long fits the 8 m strike APC" % [id, bay_m])
		for n in ["flight", "transition", "hover"]:
			check((man.vehicles[id].frames as Array).has(n), "%s VTOL frame %s" % [id, n])
	var icons: Dictionary = man.get("icons", {})
	for id in SAMPLES:
		if SAMPLES[id] == "g7_cn" and String(man.g7_samples[id].section) != "buildings":
			var ids := [id]
			if not String(id).contains("dropship"):   # dropships get no Human B alias (the generator rule; B has its own)
				ids.append("g7_b_" + String(id).substr(3))
			for x in ids:
				var ic := _img("g7_cn", String(icons.get(x, "")))
				check(ic != null and ic.get_size() == Vector2i(32, 32) and _count(ic, Rect2i(1, 1, 30, 30), 0.6) > 100, "icon 32x32 for %s" % x)
				check(man.get("infantry", {}).has(x) or man.get("vehicles", {}).has(x), "sheet entry for %s" % x)
	check(icons.has("cn_stealth_dropship") and man.vehicles.has("cn_stealth_dropship"), "content id cn_stealth_dropship aliased")
	for id in ["g7_cn_strike_apc", "g7_op_tactical_apc", "g7_b_cn_strike_apc", "g7_b_op_tactical_apc"]:
		var w: Dictionary = man.get("vehicle_wrecks", {}).get(id, {})
		var wi := _img("g7_cn", String(w.get("file", "")))
		check(wi != null and wi.get_size() == Vector2i(int(w.fw), int(w.fh) * 8), "wreck sheet for %s" % id)
	for id in ["g7_cn_strike_apc", "g7_op_tactical_apc"]:
		var fr: Array = man.vehicles[id].frames
		check(fr.has("rockets_up") and fr.has("rockets_fire"), "%s rocket pod frames" % id)
	for id in ["g7_cn_stealth_dropship", "g7_a_vtol_dropship_xl"]:
		var fr: Array = man.vehicles[id].frames
		for n in ["landed", "ramp_down", "bay_open", "apc_ramp", "squad_in"]:
			check(fr.has(n), "%s frame %s" % [id, n])
		check(man.g7_samples[id].has("bay") and man.g7_samples[id].has("ramp"), "%s bay / ramp geometry in manifest" % id)


## Interior opaque (a > 0.9, all 4 neighbours opaque) pixels of cell A (sheet a, cell origin ao, pivot ap, size asz) whose colour differs in cell B
## (sheet b, origin bo, pivot bp, size bsz) when both cells are aligned on their pivots (the craft origin).
func _hull_changed(a: Image, ao: Vector2i, ap: Vector2i, asz: Vector2i, b: Image, bo: Vector2i, bp: Vector2i, bsz: Vector2i) -> int:
	var n := 0
	for y in asz.y:
		for x in asz.x:
			var ca := a.get_pixel(ao.x + x, ao.y + y)
			if ca.a <= 0.9 or x == 0 or y == 0 or x == asz.x - 1 or y == asz.y - 1:
				continue
			# the sheet's 1-px sel-out ring is drawn on empty space, so it is not hull: only interior hull pixels count
			if a.get_pixel(ao.x + x - 1, ao.y + y).a <= 0.9 or a.get_pixel(ao.x + x + 1, ao.y + y).a <= 0.9 					or a.get_pixel(ao.x + x, ao.y + y - 1).a <= 0.9 or a.get_pixel(ao.x + x, ao.y + y + 1).a <= 0.9:
				continue
			var q := Vector2i(x, y) - ap + bp
			if q.x < 0 or q.y < 0 or q.x >= bsz.x or q.y >= bsz.y:
				n += 1
				continue
			var cb := b.get_pixel(bo.x + q.x, bo.y + q.y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.03:
				n += 1
	return n


## Owner rev3 notes (G7_REFERENCE "Look checkpoint rev3 decision") -> rev4: no see-through cutaway; loading is shown
## only through the open rear door, with real depth: "dont show a person thats behind the dropship(s)". Facing 1 has
## the tail pointing away from the camera: cargo inside or behind the craft must never paint over the hull, so every
## opaque hull pixel of the empty ramp_down frame is unchanged in every load frame (APC driving in, parked, the
## boarding / leaving file) and in bay_open / squad_in. Facing 5 has the door toward the camera: there the APC and
## the file ARE seen through the door (the frames differ from the empty ramp_down). Plus the weapon sheets (rev4).
func test_rev4_loading_depth() -> void:
	var man := _man("g7_cn")
	for id in ["g7_cn_stealth_dropship", "g7_a_vtol_dropship_xl"]:
		var e: Dictionary = man.vehicles[id]
		var base := _img("g7_cn", e.file)
		var fr: Array = e.frames
		var bsz := Vector2i(int(e.fw), int(e.fh))
		var bp := Vector2i(int(e.pivot[0]), int(e.pivot[1]))
		var rd := fr.find("ramp_down")
		for n in ["bay_open", "squad_in"]:
			var bad := _hull_changed(base, Vector2i(rd * bsz.x, bsz.y), bp, bsz, base, Vector2i(fr.find(n) * bsz.x, bsz.y), bp, bsz)
			check(bad <= 3, "%s %s facing 1: %d hull pixels painted over by cargo behind it" % [id, n, bad])
		var ls: Dictionary = man.g7_samples[id].get("load_sheets", {})
		check(ls.size() == 3, "%s names its 3 load sheets" % id)
		for key in ls:
			var le: Dictionary = man.vehicles.get(String(ls[key]), {})
			check(not le.is_empty(), "%s load sheet %s present" % [id, ls[key]])
			if le.is_empty():
				continue
			var li := _img("g7_cn", le.file)
			var lsz := Vector2i(int(le.fw), int(le.fh))
			var lp := Vector2i(int(le.pivot[0]), int(le.pivot[1]))
			check(li != null and li.get_width() <= C.PAGE_W and li.get_height() <= C.PAGE_H, "%s fits one atlas page" % ls[key])
			var shown := 0
			for i in (le.frames as Array).size():
				var bad := _hull_changed(base, Vector2i(rd * bsz.x, bsz.y), bp, bsz, li, Vector2i(i * lsz.x, lsz.y), lp, lsz)
				check(bad <= 3, "%s %s facing 1: %d hull pixels painted over by cargo behind it" % [ls[key], le.frames[i], bad])
				shown = maxi(shown, _hull_changed(base, Vector2i(rd * bsz.x, 5 * bsz.y), bp, bsz, li, Vector2i(i * lsz.x, 5 * lsz.y), lp, lsz))
			check(shown >= 30, "%s facing 5: cargo seen through the open door (%d px)" % [ls[key], shown])
		var al: Dictionary = man.g7_samples[id + "_apcload"].get("frame_alias", {})
		check(String(al.get("apc_unload_0", "")) == "apc_load_5", "%s apc_unload aliases (reverse of apc_load)" % id)
	for id in ["g7_cn_strike_apc", "g7_op_tactical_apc"]:
		var g: Array = man.vehicles[id + "_gun"].frames
		for n in ["fire_0", "fire_1", "fire_2", "fire_3", "reload_0", "reload_1", "reload_2"]:
			check(g.has(n), "%s_gun frame %s" % [id, n])
		var r: Array = man.vehicles[id + "_rkt"].frames
		for n in ["rk_raise_0", "rk_raise_1", "rk_fire_0", "rk_fire_5", "rk_reload_0", "rk_reload_3"]:
			check(r.has(n), "%s_rkt frame %s" % [id, n])
		check((man.g7_samples[id + "_rkt"].get("frame_alias", {}) as Dictionary).has("rk_stow_0"), "%s_rkt stow aliases" % id)
