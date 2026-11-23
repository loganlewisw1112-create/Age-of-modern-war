extends "res://tests/test_base.gd"
## G6.1 (ANIMA61) render motion layer + infantry animation sets + split atlas upload.

const AC = preload("res://presentation/art/art_catalog.gd")
const BatchArt = preload("res://presentation/view/batch_art.gd")
const Motion = preload("res://presentation/view/motion.gd")
const EL = preload("res://presentation/view/entity_layer.gd")

const SET := ["walk_0", "walk_1", "walk_2", "walk_3", "walk_4", "walk_5", "run_0", "run_1", "run_2", "run_3",
	"run_4", "run_5", "crouch", "prone", "crawl_0", "crawl_1", "fire_s", "fire_c", "fire_p", "reload_0", "reload_1",
	"throw_0", "throw_1", "die_0", "die_1", "die_2", "wounded", "idle_0", "idle_1"]


class FakeMV:
	var _world
	func anim_time() -> float:
		return 0.0


func _sheets(spec: Dictionary) -> Array:
	var a: Array = [String(spec.file)]
	var al = spec.get("alive_sheets")
	if al is Dictionary:
		for k in al:
			a.append(String(al[k].file) if al[k] is Dictionary else String(al[k]))
	return a


func test_every_foot_unit_has_full_set() -> void:
	var inf: Dictionary = AC.manifest().get("infantry", {})
	check(inf.size() >= 40, "manifest infantry defs: %d" % inf.size())
	var bad := 0
	for def in inf:
		var spec: Dictionary = inf[def]
		var fr: Array = spec.get("frames", [])
		var miss: Array = []
		for n in SET:
			if not fr.has(n):
				miss.append(n)
		if not miss.is_empty() or BatchArt.inf_cols(fr).is_empty():
			bad += 1
			check(false, "%s lacks %s" % [def, str(miss)])
			continue
		for f in _sheets(spec):
			var img: Image = AC._image(f)
			if not check(img != null, "%s sheet %s loads" % [def, f]):
				continue
			check(img.get_width() == int(spec.fw) * fr.size() and img.get_height() == int(spec.fh) * 8,
				"%s %s is %dx%d, want %d frames x 8 facings" % [def, f, img.get_width(), img.get_height(), fr.size()])
	check_eq(bad, 0, "foot units without the full anim61 set")


func test_split_atlas_blocks() -> void:
	# G6.1 (ANIMC61): infantry AND vehicle anim61 columns upload packed: block A (original columns) + block B (anim61
	# cells cropped to their opaque rect, shelf-packed; rows 2 / 6 / 7 mirrored on symmetric sheets)
	var ba = BatchArt.new()
	var man: Dictionary = AC.manifest()
	var inf: Dictionary = man.get("infantry", {})
	var veh: Dictionary = man.get("vehicles", {})
	var mb := {"inf_base": 0, "inf_whole": 0, "inf_split5": 0, "inf_packed": 0, "veh_base": 0, "veh_whole": 0, "veh_packed": 0}
	var widest := 0
	var mirrored := 0
	var nveh := 0
	for grp in [["inf", inf], ["veh", veh]]:
		var g: String = grp[0]
		for def in (grp[1] as Dictionary):
			var s: Dictionary = ba._unit_spec(def)
			var blk: Dictionary = s.get("blk", {})
			if blk.is_empty():
				check(g == "veh", "%s uploads split" % def)
				continue
			var raw: Image = AC._image(String(s.file))
			if not check(raw != null, "%s sheet loads" % def):
				continue
			var fh := int(s.fh)
			var cell := int(s.fw) * fh * 8 * 4
			var lay: Dictionary = BatchArt.layout_of(String(s.file), raw, s)
			mb[g + "_base"] += int(blk.b) * cell
			mb[g + "_whole"] += int(s.n) * cell
			mb[g + "_packed"] += int(lay.w) * fh * 8 * 4
			if g == "inf":
				mb.inf_split5 += (int(blk.b) + int(blk.nb)) * cell
			else:
				nveh += 1
				mirrored += int(bool(lay.mirror))
			widest = maxi(widest, int(lay.w))
			# every selector column resolves to block A or to a stored block-B cell on all 8 rows
			for src in [s.a61, s.v61]:
				for k in src:
					if k == "turret":
						continue
					for v in (src[k] if src[k] is Array else [src[k]]):
						if int(v) >= int(blk.b):
							for row in 8:
								if (lay.tb as PackedVector2Array)[int(v) * 8 + row].x < 0.0:
									check(false, "%s %s col %d row %d stored" % [def, k, int(v), row])
	var nb0: float = float(mb.inf_split5 - mb.inf_base + mb.veh_whole - mb.veh_base)
	var nb1: float = float(mb.inf_packed - mb.inf_base + mb.veh_packed - mb.veh_base)
	print("ANIM61 atlas one tint (main sheets, MB=1e6): infantry base %.1f whole %.1f split5 %.1f packed %.1f | vehicles base %.1f whole %.1f packed %.1f | anim61 frames %.1f -> %.1f MB (-%.0f%%) | mirrored vehicle sheets %d/%d | widest %d px" % [
		mb.inf_base / 1e6, mb.inf_whole / 1e6, mb.inf_split5 / 1e6, mb.inf_packed / 1e6, mb.veh_base / 1e6, mb.veh_whole / 1e6,
		mb.veh_packed / 1e6, nb0 / 1e6, nb1 / 1e6, 100.0 * (1.0 - nb1 / maxf(1.0, nb0)), mirrored, nveh, widest])
	check(nb1 <= nb0 * 0.65, "anim61 frame memory at least 35% lower than the ANIMA61-2 / ANIMB61 upload")
	check(widest <= 2046, "no packed sheet needs a wide atlas page (%d px)" % widest)
	# pixel exactness: block B (untinted) holds the sheet's cropped frames; mirrored rows flip; nothing opaque cropped
	for def in ["rifleman", "a_hmg_team", "mbt", "a_attack_heli", "a_patrol_boat"]:
		if not (inf.has(def) or veh.has(def)):
			continue
		var s: Dictionary = ba._unit_spec(def)
		var simg: Image = BatchArt.split_image(String(s.file), "", Color.WHITE, s)
		if not check(simg != null, "%s packed image" % def):
			continue
		var raw: Image = AC._image(String(s.file))
		var fw := int(s.fw)
		var fh := int(s.fh)
		var pv: Vector2 = s.pivot
		var lay: Dictionary = BatchArt.layout_of(String(s.file), raw, s)
		var c: Array = [def, 0, 0, Vector2.ZERO, fw, fh, -pv]
		c.resize(41)
		c[33] = 0
		c[35] = int(s.blk.b)
		c[38] = lay.tb
		c[39] = lay.sz
		c[40] = lay.off
		var col := int((s.a61.walk as Array)[1]) if not (s.a61 as Dictionary).is_empty() else int(s.v61.get("damaged", s.blk.b))
		for row in 8:
			ba.frame_src(c, col, row)
			var stored: int = [0, 1, 0, 3, 4, 5, 4, 3][row] if bool(lay.mirror) else row
			check(ba.out_flip == (bool(lay.mirror) and row in [2, 6, 7]), "%s row %d mirror flag" % [def, row])
			var cx := int(round(ba.out_off.x + pv.x))
			var cy := int(round(ba.out_off.y + pv.y))
			var want := raw.get_region(Rect2i(col * fw + cx, stored * fh + cy, int(ba.out_src.size.x), int(ba.out_src.size.y)))
			var got: Image = simg.get_region(Rect2i(ba.out_src.position, ba.out_src.size))
			check(got.get_data() == want.get_data(), "%s col %d row %d = sheet row %d (cropped)" % [def, col, row, stored])
			var used := raw.get_region(Rect2i(col * fw, stored * fh, fw, fh)).get_used_rect()
			check(used.size == Vector2i(ba.out_src.size) or used.size.x == 0, "%s row %d crop keeps every opaque pixel" % [def, row])
		if (s.v61 as Dictionary).has("bank_l") and bool(lay.mirror):
			ba.frame_src(c, int(s.v61.bank_l), 2)
			var a: Rect2 = ba.out_src
			ba.frame_src(c, int(s.v61.bank_r), 0)
			check(a == ba.out_src, "%s mirrored bank_l row 2 = bank_r row 0 cell (roll flips)" % def)
		print("ANIM61 %s mirror overlap row0->row2 (col 0): %.2f mirrored=%s" % [def, BatchArt.mirror_iou(raw, fw, fh), str(lay.mirror)])


func test_facing_turn_and_offset_bound() -> void:
	var m = Motion.new()
	var dt := 1.0 / 60.0
	for cls in 5:
		var id := 100 + cls
		var t := 0.0
		var pos := Vector2(10, 10)
		m.step(id, cls, pos, 0.0, 0, t)
		var prev: float = m.out_face
		var worst := 0.0
		var off := 0.0
		for k in 240:
			t += dt
			var target := PI if k < 120 else -PI * 0.5
			# jittery sim motion (start / stop / speed changes)
			pos += Vector2(0.06 if (k / 20) % 2 == 0 else 0.0, 0.03 * sin(k * 0.3))
			m.step(id, cls, pos, target, Motion.P_MOVING, t)
			worst = maxf(worst, absf(wrapf(m.out_face - prev, -PI, PI)) / (float(Motion.TURN[cls]) * dt))
			off = maxf(off, m.out_off.length())
			prev = m.out_face
		check(worst <= 1.0001, "class %d turn per frame <= TURN*dt (ratio %.3f)" % [cls, worst])
		check(off <= Motion.MAX_OFF + 0.0001, "class %d drawn offset %.3f <= 0.3 tile" % [cls, off])


## G7.1 ANIM71 E4-2.1: infantry lean into turns + feet plant on start/stop; aim facing leads a moving target.
func test_infantry_lean_plant_and_aim_lead() -> void:
	var m = Motion.new()
	var dt := 1.0 / 60.0
	var t := 0.0
	var pos := Vector2(5, 5)
	m.step(1, Motion.CLS_INF, pos, 0.0, 0, t)
	# hard right turn while moving: lean should leave the facing axis (out_lean / lateral out_px)
	var lean_peak := 0.0
	var lean_api := 0.0
	var px_lat := 0.0
	for k in 90:
		t += dt
		pos += Vector2(0.05, 0.0)
		m.step(1, Motion.CLS_INF, pos, PI * 0.5, Motion.P_MOVING | Motion.P_RUN, t)
		lean_peak = maxf(lean_peak, absf(m.out_lean))
		lean_api = maxf(lean_api, absf(m.lean(1)))
		px_lat = maxf(px_lat, absf(m.out_px.x) + absf(m.out_px.y))
	check(lean_peak > 0.4, "infantry lean into a hard turn (peak |out_lean|=%.3f)" % lean_peak)
	check(lean_api > 0.2, "lean(id) reports turn lean (peak %.3f)" % lean_api)
	check(px_lat > 0.5, "lean/bob produce a non-zero out_px while turning")
	check(m.out_off.length() <= Motion.MAX_OFF + 0.0001, "lean stays inside MAX_OFF via out_px not out_off")
	# feet plant on stop: after moving, halt -> suspension plant pushes out_px.y down
	m.step(1, Motion.CLS_INF, pos, m.out_face, Motion.P_MOVING, t)
	t += dt
	m.step(1, Motion.CLS_INF, pos, m.out_face, 0, t)
	check(m.out_px.y > 0.4, "feet plant on stop (out_px.y=%.3f)" % m.out_px.y)
	# aim lead: shooter looks ahead of a crossing target vs a static one
	var sh := 20
	var tg := 21
	var sp := Vector2(0, 0)
	var tp := Vector2(4, 0)
	t += 0.05
	m.step(sh, Motion.CLS_INF, sp, 0.0, 0, t)
	m.step(tg, Motion.CLS_INF, tp, 0.0, Motion.P_MOVING, t)
	m.mark_screen(sh, Vector2(0, 0))
	m.mark_screen(tg, Vector2(128, 64))
	m.on_shot(sh, tg)
	# static target facing
	t += dt
	m.step(sh, Motion.CLS_INF, sp, 0.0, Motion.P_FIRING, t)
	m.step(tg, Motion.CLS_INF, tp, 0.0, 0, t)
	var face_static: float = m.out_face
	var row_static: int = m.aim_row(sh, Vector2(0, 0), 0)
	# crossing target: move +y so lead pulls aim up (positive atan2)
	for k in 40:
		t += dt
		tp += Vector2(0.0, 0.08)
		m.step(tg, Motion.CLS_INF, tp, PI * 0.5, Motion.P_MOVING, t)
		m.mark_screen(tg, Vector2((tp.x - tp.y) * 32.0, (tp.x + tp.y) * 16.0))
		m.step(sh, Motion.CLS_INF, sp, 0.0, Motion.P_FIRING, t)
	var face_lead: float = m.out_face
	var row_lead: int = m.aim_row(sh, Vector2(0, 0), 0)
	check(absf(wrapf(face_lead - face_static, -PI, PI)) > 0.05 or row_lead != row_static,
		"aim lead moves drawn facing or aim_row vs static (face %.3f->%.3f row %d->%d)" % [face_static, face_lead, row_static, row_lead])
	check(face_lead > face_static - 0.01, "lead toward +y crossing is non-decreasing facing (%.3f vs %.3f)" % [face_lead, face_static])
	# determinism: same id + motion replay -> same lean peak (hash of id, no RNG)
	var m2 = Motion.new()
	var t2 := 0.0
	var p2 := Vector2(5, 5)
	var lean_peak2 := 0.0
	m2.step(1, Motion.CLS_INF, p2, 0.0, 0, t2)
	for k in 90:
		t2 += dt
		p2 += Vector2(0.05, 0.0)
		m2.step(1, Motion.CLS_INF, p2, PI * 0.5, Motion.P_MOVING | Motion.P_RUN, t2)
		lean_peak2 = maxf(lean_peak2, absf(m2.out_lean))
	check(is_equal_approx(lean_peak2, lean_peak),
		"lean is deterministic from id/motion (%.4f vs %.4f)" % [lean_peak2, lean_peak])


## G7.1 ANIM71 E4-2.2: vehicle brake squat deeper than launch; suspension rocks while moving; recoil hull dip.
## E4-2.4: companion weight_for + dog/UGV rock amplify (presentation only, deterministic).
func test_vehicle_brake_suspension_and_companion_weight() -> void:
	var m = Motion.new()
	var dt := 1.0 / 60.0
	var t := 0.0
	var pos := Vector2(8, 8)
	m.step(50, Motion.CLS_VEH, pos, 0.0, 0, t)
	# accelerate: launch squat (negative y)
	t += dt
	pos += Vector2(0.08, 0.0)
	m.step(50, Motion.CLS_VEH, pos, 0.0, Motion.P_MOVING, t)
	var launch_y: float = m.out_px.y
	check(launch_y < -0.4, "vehicle launch squat lifts hull (out_px.y=%.3f)" % launch_y)
	# cruise: suspension rock non-zero while moving
	var rock_peak := 0.0
	for k in 90:
		t += dt
		pos += Vector2(0.07, 0.0)
		m.step(50, Motion.CLS_VEH, pos, 0.0, Motion.P_MOVING, t)
		rock_peak = maxf(rock_peak, absf(m.out_px.y))
	check(rock_peak > 0.3, "vehicle suspension rocks while moving (peak |y|=%.3f)" % rock_peak)
	# brake: stop dip deeper than launch magnitude
	m.step(50, Motion.CLS_VEH, pos, 0.0, Motion.P_MOVING, t)
	t += dt
	m.step(50, Motion.CLS_VEH, pos, 0.0, 0, t)
	var brake_y: float = m.out_px.y
	check(brake_y > 0.9, "brake squat plants hull (out_px.y=%.3f)" % brake_y)
	check(brake_y > absf(launch_y), "brake squat deeper than launch (|launch|=%.3f brake=%.3f)" % [absf(launch_y), brake_y])
	# recoil hull rock
	m.on_shot(50, -1)
	t += dt
	m.step(50, Motion.CLS_VEH, pos, 0.0, Motion.P_FIRING, t)
	check(m.recoil(50) > 0.5, "vehicle recoil(id) hot after on_shot")
	check(m.out_px.y > 0.5 or m.out_px.length() > 0.8, "hull rock on shot (out_px=%s)" % str(m.out_px))
	# veh_anim61: recoil column preferred; track phase advances
	var VehAnim61 = preload("res://presentation/view/veh_anim61.gd")
	var v := {"idle": 0, "recoil": 7, "track": [1, 2, 3], "bank_l": 4, "bank_r": 5}
	check_eq(VehAnim61.pick(v, 0, true, false, m, 50, 1.0, t), 7, "veh_anim61 picks recoil while kick hot")
	# companion weight kinds
	check_eq(Motion.weight_for("g71_robot_dog"), Motion.WT_DOG, "dog weight")
	check_eq(Motion.weight_for("g71_ugv_mg"), Motion.WT_UGV, "ugv weight")
	check_eq(Motion.weight_for("g71_wall_sentinel"), Motion.WT_SENT, "sentinel weight")
	check_eq(Motion.weight_for("rifleman"), Motion.WT_NONE, "human infantry is WT_NONE")
	# UGV rock louder than plain vehicle at same id/path (same seed, separate Motion instances)
	var m_ugv = Motion.new()
	var m_plain = Motion.new()
	var t2 := 0.0
	var p2 := Vector2(1, 1)
	var ugv_peak := 0.0
	var plain_peak := 0.0
	m_ugv.step(60, Motion.CLS_VEH, p2, 0.0, 0, t2, Motion.WT_UGV)
	m_plain.step(60, Motion.CLS_VEH, p2, 0.0, 0, t2, Motion.WT_NONE)
	for k in 60:
		t2 += dt
		p2 += Vector2(0.06, 0.0)
		m_ugv.step(60, Motion.CLS_VEH, p2, 0.0, Motion.P_MOVING, t2, Motion.WT_UGV)
		m_plain.step(60, Motion.CLS_VEH, p2, 0.0, Motion.P_MOVING, t2, Motion.WT_NONE)
		ugv_peak = maxf(ugv_peak, absf(m_ugv.out_px.y))
		plain_peak = maxf(plain_peak, absf(m_plain.out_px.y))
	check(ugv_peak > plain_peak * 1.05, "UGV track rock louder than plain veh (%.3f vs %.3f)" % [ugv_peak, plain_peak])
	# determinism replay
	var m3 = Motion.new()
	var t3 := 0.0
	var p3 := Vector2(8, 8)
	var brake2 := 0.0
	m3.step(50, Motion.CLS_VEH, p3, 0.0, 0, t3)
	t3 += dt
	p3 += Vector2(0.08, 0.0)
	m3.step(50, Motion.CLS_VEH, p3, 0.0, Motion.P_MOVING, t3)
	for k in 90:
		t3 += dt
		p3 += Vector2(0.07, 0.0)
		m3.step(50, Motion.CLS_VEH, p3, 0.0, Motion.P_MOVING, t3)
	m3.step(50, Motion.CLS_VEH, p3, 0.0, Motion.P_MOVING, t3)
	t3 += dt
	m3.step(50, Motion.CLS_VEH, p3, 0.0, 0, t3)
	brake2 = m3.out_px.y
	check(is_equal_approx(brake2, brake_y), "brake squat deterministic (%.4f vs %.4f)" % [brake2, brake_y])


## G7.1 ANIM71 E4-2.5: Machine/walker terrain-adaptive gait, damage limp, scramble; E4-2.6 distinct wreck break-ups.
func test_machine_locomotion_and_death_variety() -> void:
	check_eq(Motion.weight_for("g71_m_siege_walker"), Motion.WT_WALKER, "siege walker weight")
	check_eq(Motion.weight_for("g71_m_mega_walker"), Motion.WT_WALKER, "mega walker weight")
	check_eq(Motion.weight_for("g71_m_brute"), Motion.WT_MACHINE, "brute is Machine weight")
	check_eq(Motion.weight_for("g71_m_sapper"), Motion.WT_MACHINE, "sapper is Machine weight")
	check_eq(Motion.weight_for("g71_m_reclaimer"), Motion.WT_MACHINE, "reclaimer is Machine weight")
	check_eq(Motion.death_kind_for("g71_m_siege_walker"), Motion.DK_WALKER, "walker death kind")
	check_eq(Motion.death_kind_for("g71_m_brute"), Motion.DK_BRUTE, "brute death kind")
	check_eq(Motion.death_kind_for("g71_m_turret_eater"), Motion.DK_SMALL, "small Machine death kind")
	check_eq(Motion.death_kind_for("g71_m_reclaimer"), Motion.DK_CELL, "cell blast death kind")
	check_eq(Motion.death_kind_for("rifleman"), Motion.DK_NONE, "human has no Machine death kind")
	var m = Motion.new()
	var dt := 1.0 / 60.0
	var t := 0.0
	var pos := Vector2(4, 4)
	# flat healthy walker vs raised-terrain walker: terrain plant louder
	var m_flat = Motion.new()
	var m_hill = Motion.new()
	var t1 := 0.0
	var p1 := Vector2(2, 2)
	var flat_peak := 0.0
	var hill_peak := 0.0
	m_flat.step(70, Motion.CLS_HEAVY, p1, 0.0, 0, t1, Motion.WT_WALKER, 1.0, 0.0)
	m_hill.step(70, Motion.CLS_HEAVY, p1, 0.0, 0, t1, Motion.WT_WALKER, 1.0, 36.0)
	for k in 80:
		t1 += dt
		p1 += Vector2(0.05, 0.0)
		m_flat.step(70, Motion.CLS_HEAVY, p1, 0.0, Motion.P_MOVING, t1, Motion.WT_WALKER, 1.0, 0.0)
		m_hill.step(70, Motion.CLS_HEAVY, p1, 0.0, Motion.P_MOVING, t1, Motion.WT_WALKER, 1.0, 36.0)
		flat_peak = maxf(flat_peak, absf(m_flat.out_px.y))
		hill_peak = maxf(hill_peak, absf(m_hill.out_px.y))
	check(hill_peak > flat_peak * 1.08, "terrain-adaptive gait louder on raised ground (%.3f vs %.3f)" % [hill_peak, flat_peak])
	# damage gait: damaged Machine lists / hitch more than healthy at same seed/path
	var m_ok = Motion.new()
	var m_hurt = Motion.new()
	var t2 := 0.0
	var p2 := Vector2(3, 3)
	var ok_lat := 0.0
	var hurt_lat := 0.0
	m_ok.step(71, Motion.CLS_VEH, p2, 0.0, 0, t2, Motion.WT_MACHINE, 1.0, 0.0)
	m_hurt.step(71, Motion.CLS_VEH, p2, 0.0, 0, t2, Motion.WT_MACHINE, 0.35, 0.0)
	for k in 70:
		t2 += dt
		p2 += Vector2(0.055, 0.0)
		m_ok.step(71, Motion.CLS_VEH, p2, 0.0, Motion.P_MOVING, t2, Motion.WT_MACHINE, 1.0, 0.0)
		m_hurt.step(71, Motion.CLS_VEH, p2, 0.0, Motion.P_MOVING, t2, Motion.WT_MACHINE, 0.35, 0.0)
		ok_lat = maxf(ok_lat, absf(m_ok.out_px.x) + absf(m_ok.out_px.y))
		hurt_lat = maxf(hurt_lat, absf(m_hurt.out_px.x) + absf(m_hurt.out_px.y))
	check(hurt_lat > ok_lat * 1.05, "damage gait amplifies motion (%.3f vs %.3f)" % [hurt_lat, ok_lat])
	# scramble: hard turn on raised terrain produces lean / lateral cue
	m.step(72, Motion.CLS_HEAVY, pos, 0.0, 0, t, Motion.WT_WALKER, 1.0, 36.0)
	var lean_scr := 0.0
	var px_scr := 0.0
	for k in 90:
		t += dt
		pos += Vector2(0.05, 0.0)
		m.step(72, Motion.CLS_HEAVY, pos, PI * 0.5, Motion.P_MOVING, t, Motion.WT_WALKER, 1.0, 36.0)
		lean_scr = maxf(lean_scr, absf(m.out_lean))
		px_scr = maxf(px_scr, m.out_px.length())
	check(lean_scr > 0.3 or px_scr > 1.2, "walker scramble/weight on raised turn (lean=%.3f px=%.3f)" % [lean_scr, px_scr])
	# E4-2.6: distinct break-up offsets by kind; deterministic; prune after BREAK_LIFE
	var ages := [0.1, 0.45, 0.8]
	var kinds := [Motion.DK_WALKER, Motion.DK_BRUTE, Motion.DK_SMALL, Motion.DK_CELL]
	var seen := {}
	for kind in kinds:
		var offs: Array = []
		for age in ages:
			var o: Vector2 = Motion.break_offset(age, kind, 0.31)
			offs.append(o)
			check(o != Vector2.ZERO, "break_offset kind %d age %.2f non-zero" % [kind, age])
		# kinds diverge at mid-break
		seen[str(offs[1])] = kind
		check(Motion.break_offset(0.45, kind, 0.31) == offs[1], "break_offset deterministic kind %d" % kind)
	check(seen.size() >= 3, "death variety: >=3 distinct mid-break offsets across kinds (%d)" % seen.size())
	var mw = Motion.new()
	mw.step(80, Motion.CLS_HEAVY, Vector2(6, 6), 0.0, 0, 1.0, Motion.WT_WALKER, 1.0, 0.0)
	mw.mark_screen(80, Vector2(100, 50))
	mw.kill_machine(80, 1.0, Motion.DK_WALKER)
	check_eq(mw.breaks.size(), 1, "kill_machine records break cue")
	check(not mw.vs.has(80), "kill_machine drops visual state")
	var bo: Vector2 = mw.break_at(Vector2(100, 50), 1.2)
	check(bo != Vector2.ZERO, "break_at finds nearby cue (off=%s)" % str(bo))
	check(mw.break_at(Vector2(400, 400), 1.2) == Vector2.ZERO, "break_at ignores far wrecks")
	mw.prune(1.0 + Motion.BREAK_LIFE + 0.1)
	check_eq(mw.breaks.size(), 0, "breaks pruned after BREAK_LIFE")
	# replay determinism for terrain gait
	var m3 = Motion.new()
	var t3 := 0.0
	var p3 := Vector2(2, 2)
	var hill2 := 0.0
	m3.step(70, Motion.CLS_HEAVY, p3, 0.0, 0, t3, Motion.WT_WALKER, 1.0, 36.0)
	for k in 80:
		t3 += dt
		p3 += Vector2(0.05, 0.0)
		m3.step(70, Motion.CLS_HEAVY, p3, 0.0, Motion.P_MOVING, t3, Motion.WT_WALKER, 1.0, 36.0)
		hill2 = maxf(hill2, absf(m3.out_px.y))
	check(is_equal_approx(hill2, hill_peak), "terrain gait deterministic (%.4f vs %.4f)" % [hill2, hill_peak])


func test_postures_pick_frames() -> void:
	var fr: Array = ["idle", "walk_a", "walk_b", "fire"] + SET
	var a := BatchArt.inf_cols(fr)
	check(not a.is_empty(), "inf_cols resolves the set")
	var sd := 0.3
	check_eq(Motion.inf_col(a, Motion.P_PINNED, 1.0, sd), fr.find("prone"), "pinned idle -> prone")
	check(int(a.crawl[0]) == Motion.inf_col(a, Motion.P_PINNED | Motion.P_MOVING, 0.0, 0.0) or int(a.crawl[1]) == Motion.inf_col(a, Motion.P_PINNED | Motion.P_MOVING, 0.0, 0.0), "pinned moving -> crawl")
	check_eq(Motion.inf_col(a, Motion.P_PINNED | Motion.P_FIRING, 1.0, sd), fr.find("fire_p"), "pinned firing -> fire_p")
	check_eq(Motion.inf_col(a, Motion.P_SUPPRESSED, 1.0, sd), fr.find("crouch"), "suppressed idle -> crouch")
	check_eq(Motion.inf_col(a, Motion.P_SUPPRESSED | Motion.P_FIRING, 1.0, sd), fr.find("fire_c"), "suppressed firing -> fire_c")
	check_eq(Motion.inf_col(a, Motion.P_WOUNDED, 1.0, sd), fr.find("wounded"), "wounded")
	# walk cycle covers all 6 frames; two soldiers are phase-offset
	var seen := {}
	for k in 60:
		seen[Motion.inf_col(a, Motion.P_MOVING, k * 0.05, sd)] = true
	check_eq(seen.size(), 6, "walk cycle uses 6 frames")
	var diff := 0
	for k in 20:
		diff += int(Motion.inf_col(a, Motion.P_MOVING, k * 0.05, Motion.seed_of(7)) != Motion.inf_col(a, Motion.P_MOVING, k * 0.05, Motion.seed_of(8)))
	check(diff > 0, "squad members walk out of step")


func test_death_plays_then_fades() -> void:
	check_eq([Motion.corpse_frame(0.0), Motion.corpse_frame(0.25), Motion.corpse_frame(0.45), Motion.corpse_frame(6.0)], [0, 1, 2, 2], "die_0..2")
	check(is_equal_approx(Motion.corpse_alpha(5.0), 1.0) and is_equal_approx(Motion.corpse_alpha(Motion.CORPSE_LIFE - Motion.FADE * 0.5), 0.5) and Motion.corpse_alpha(Motion.CORPSE_LIFE) <= 0.0, "corpse lingers then fades")  # G7 LOOK7 CR: life from Motion, not 14 s
	var m = Motion.new()
	m.step(5, Motion.CLS_INF, Vector2(3, 3), 0.0, 0, 1.0)
	m.mark_screen(5, Vector2(40, 50))
	m.kill(5, [], 1.0)
	check_eq(m.corpses.size(), 1, "corpse added")
	check(not m.vs.has(5), "dead id's visual state dropped")
	m.prune(1.0 + Motion.CORPSE_LIFE + 1.0)  # G7 LOOK7 CR
	check_eq(m.corpses.size(), 0, "corpse removed after its life")
	for k in Motion.CORPSE_CAP + 20:
		m.step(1000 + k, Motion.CLS_INF, Vector2(1, 1), 0.0, 0, 20.0)
		m.kill(1000 + k, [], 20.0)
	check_eq(m.corpses.size(), Motion.CORPSE_CAP, "corpse cap")


func _run(view: bool) -> String:
	var w := make_world({}, true)
	var el = EL.new()
	var mv := FakeMV.new()
	mv._world = w
	el.mv = mv
	for k in 90:
		w.step()
		if view:
			var ids: Array = w.entities.keys()
			ids.sort()
			for id in ids:
				var e: Dictionary = w.entities[id]
				if String(e.get("kind", "")) == "unit":
					el._refresh_post(int(id), e)
					el.motion.step(int(id), Motion.CLS_INF, e.get("pos", Vector2.ZERO), float(e.get("facing", 0.0)), int(el._post.get(id, 0)), k / 20.0)
			el.on_shot({"shooter": ids[0] if not ids.is_empty() else -1, "target": -1})
	var h := w.state_hash()
	el.free()
	return h


func test_view_never_writes_sim() -> void:
	var a := _run(false)
	var b := _run(true)
	check_eq(b, a, "state hash identical with the view reads on / off")


## Owner bug 2026-10-26 ("units flicker or don't show at all"): building the unit cache for several teams (and
## rebuilding it) must give every team the same in-page frame offsets and never shift the shared per-sheet layout.
## Before the fix cache_unit added the atlas origin to the shared layout table in place (packed arrays are shared),
## so each later build moved the anim61 frames further into empty atlas space.
func test_cache_for_many_teams_keeps_frames_in_place() -> void:
	var ba = BatchArt.new()
	var teams := [Color(0.2, 0.4, 1.0), Color(1.0, 0.3, 0.2), Color(0.3, 0.9, 0.3), Color(0.9, 0.9, 0.2)]
	var tested := 0
	for def in ["rifleman", "mbt"]:
		var s: Dictionary = ba._unit_spec(def)
		if (s.get("blk", {}) as Dictionary).is_empty():
			continue
		var first := PackedVector2Array()
		for ti in teams.size():
			for rep in 2:  # the same team twice = a cache rebuild
				var c: Array = ba.cache_unit({"def": def, "owner": ti, "id": 1}, teams[ti], "t%d_%d" % [ti, rep])
				var tb: PackedVector2Array = c[38]
				var org: Vector2 = c[34]
				var page: Image = (ba.atlas.pages[int(c[33])] as Dictionary).img
				var rel := PackedVector2Array()
				for k in tb.size():
					rel.append(tb[k] - org if tb[k].x >= 0.0 else tb[k])
					if tb[k].x >= 0.0:
						check(tb[k].x < page.get_width() and tb[k].y < page.get_height(), "%s team %d cell %d inside its atlas page" % [def, ti, k])
				if first.is_empty():
					first = rel
				else:
					check(rel == first, "%s team %d build %d: same in-page frame offsets as the first build" % [def, ti, rep])
		tested += 1
	check(tested >= 1, "at least one split sheet tested")
