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
