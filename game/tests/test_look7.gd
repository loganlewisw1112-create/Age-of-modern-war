extends "res://tests/test_base.gd"
## G7 (LOOK7) battlefield look: G7 pose frames on every human soldier sheet, armband masks, ground-mark and body caps,
## fading last-known markers, G7 pose selection, render snapshot fields, view on / off hash identical.

const AC = preload("res://presentation/art/art_catalog.gd")
const BatchArt = preload("res://presentation/view/batch_art.gd")
const Motion = preload("res://presentation/view/motion.gd")
const G61Anim = preload("res://tools/art/g61_anim.gd")
const Fx61Engine = preload("res://presentation/view/fx61_engine.gd")
const DecalLayer = preload("res://presentation/view/decal_layer.gd")
const FogLayer = preload("res://presentation/view/fog_layer.gd")
const RenderSnap = preload("res://sim/render_snap.gd")


func _sheets(spec: Dictionary) -> Array:
	var a: Array = [[String(spec.file), String(spec.get("mask", ""))]]
	var al = spec.get("alive_sheets")
	if al is Dictionary:
		for k in al:
			if al[k] is Dictionary:
				a.append([String(al[k].file), String(al[k].get("mask", ""))])
	return a


func test_every_human_soldier_has_g7_poses() -> void:
	var inf: Dictionary = AC.manifest().get("infantry", {})
	var humans := 0
	for def in inf:
		var spec: Dictionary = inf[def]
		if spec.has("g10") or not G61Anim.human(String(def), spec):
			continue
		humans += 1
		var fr: Array = spec.get("frames", [])
		var miss: Array = []
		for n in G61Anim.SET7:
			if not fr.has(n):
				miss.append(n)
		check(miss.is_empty(), "%s has every G7 pose (missing %s)" % [def, str(miss)])
		check(not BatchArt.g7_cols(fr).is_empty() and BatchArt.inf_cols(fr).has("g7_unc"), "%s G7 columns resolve" % def)
		for sh in _sheets(spec):
			var img: Image = AC._image(sh[0])
			if check(img != null, "%s sheet %s loads" % [def, sh[0]]):
				check(img.get_width() == int(spec.fw) * fr.size() and img.get_height() == int(spec.fh) * 8,
					"%s sheet %s is %d columns x 8 rows" % [def, sh[0], fr.size()])
	check(humans >= 35, "human soldier defs with the G7 set: %d" % humans)


## Mask pixels / opaque figure pixels over the base columns of a sheet (team-colour share of the figure).
func _mask_share(file: String, mask: String, fw: int, fh: int, ncols: int) -> float:
	var img: Image = AC._image(file)
	var m: Image = AC._image(mask)
	if img == null or m == null:
		return -1.0
	if img.is_compressed():
		img.decompress()
	if m.is_compressed():
		m.decompress()
	var fig := 0
	var msk := 0
	for y in fh * 8:
		for x in mini(img.get_width(), fw * ncols):
			if img.get_pixel(x, y).a >= 0.78:
				fig += 1
				if x < m.get_width() and y < m.get_height() and m.get_pixel(x, y).a > 0.0:
					msk += 1
	return float(msk) / maxf(1.0, float(fig))


func test_armband_masks_smaller_on_soldiers_only() -> void:
	var man: Dictionary = AC.manifest()
	var inf: Dictionary = man.get("infantry", {})
	var worst := 0.0
	var n := 0
	for def in inf:
		var spec: Dictionary = inf[def]
		if spec.has("g10") or not G61Anim.human(String(def), spec) or String(spec.get("mask", "")) == "":
			continue
		var base := int((spec.get("anim61", {}) as Dictionary).get("base", 4))
		var sh := _mask_share(String(spec.file), String(spec.mask), int(spec.fw), int(spec.fh), base)
		if sh < 0.0:
			continue
		n += 1
		worst = maxf(worst, sh)
		check(sh > 0.0 and sh <= 0.16, "%s team colour is an armband / helmet band (%.3f of the figure)" % [def, sh])
	check(n >= 35, "soldier masks measured: %d (worst share %.3f)" % [n, worst])
	# vehicles keep their full team colour
	var veh: Dictionary = man.get("vehicles", {})
	for def in ["mbt", "ifv"]:
		var vs = veh.get(def)
		if check(vs is Dictionary, "vehicle %s in the manifest" % def):
			var sh2 := _mask_share(String(vs.file), String(vs.get("mask", "")), int(vs.fw), int(vs.fh), 1)
			check(sh2 > 0.04 and not (vs as Dictionary).has("armband7"), "%s keeps its full team-colour mask (%.3f, not armbanded)" % [def, sh2])
	# the pure function: a figure fully masked before keeps only bands afterwards
	var img := Image.create(24, 26 * 8, false, Image.FORMAT_RGBA8)
	var mk := Image.create(24, 26 * 8, false, Image.FORMAT_RGBA8)
	for r in 8:
		for y in range(4, 24):
			for x in range(9, 15):
				img.set_pixel(x, r * 26 + y, Color(0.5, 0.5, 0.5, 1.0))
				mk.set_pixel(x, r * 26 + y, Color(1, 1, 1, 1))
	var res: Array = G61Anim.armband(img, mk, 24, 26, 1, G61Anim.CAMO_A)
	var before := 0
	var after := 0
	for y in 26 * 8:
		for x in 24:
			before += 1 if mk.get_pixel(x, y).a > 0.0 else 0
			after += 1 if (res[1] as Image).get_pixel(x, y).a > 0.0 else 0
	check(after > 0 and after * 4 < before, "armband() shrinks a full mask to bands (%d -> %d px)" % [before, after])
	check((res[0] as Image).get_pixel(11, 20).g > (res[0] as Image).get_pixel(11, 20).b, "unmasked uniform repainted in camo")


func test_ground_marks_and_bodies_capped() -> void:
	var e = Fx61Engine.new()
	e.set_quality("high")
	for i in 400:
		e.blood(Vector2(i, 0), 6.0, i % 2 == 0)
	for i in 300:
		e.debris(Vector2(i, 0), 10.0, 1)
	for i in 300:
		e.add_decal(Vector2(i, 0), 10.0, "crater")
	var lb := DecalLayer.live_count(e.decals, "blood")
	var ld := DecalLayer.live_count(e.decals, "debris")
	var lc := DecalLayer.live_count(e.decals, "crater")
	check(lb == int(DecalLayer.BLOOD_CAP.high), "blood marks capped (%d)" % lb)
	check(ld == int(DecalLayer.DEBRIS_CAP.high), "debris marks capped (%d)" % ld)
	check(lc <= int(DecalLayer.Core.DECAL_CAP.high), "craters capped (%d)" % lc)
	check(e.decals.size() > lb + ld + lc, "the oldest marks over a cap are fading, not popped")
	for k in 30:
		e.tick(0.1, Rect2(-1e6, -1e6, 2e6, 2e6))
	check(e.decals.size() == lb + ld + lc, "faded marks removed after FADE_S")
	check(float(e.decals[e.decals.size() - 1].fade) < 0.0, "the newest marks persist")
	# bodies: longer than G6.1 (14 s), capped, the oldest fade first
	check(Motion.CORPSE_LIFE > 14.0 and Motion.CORPSE_CAP >= 160, "bodies stay longer (%.0f s, cap %d)" % [Motion.CORPSE_LIFE, Motion.CORPSE_CAP])
	var m = Motion.new()
	for k in Motion.CORPSE_CAP + 40:
		m.step(1000 + k, Motion.CLS_INF, Vector2(1, 1), 0.0, 0, 20.0)
		m.kill(1000 + k, [], 20.0)
	check(m.corpses.size() <= Motion.CORPSE_CAP, "corpse cap holds (%d)" % m.corpses.size())
	# one second later the oldest are part-way through their fade, the newest are still solid
	check(Motion.corpse_alpha(21.0 - float(m.corpses[0][4])) < 1.0 and is_equal_approx(Motion.corpse_alpha(21.0 - float(m.corpses[m.corpses.size() - 1][4])), 1.0),
		"over the soft cap the oldest bodies fade first")
	m.prune(20.0 + Motion.CORPSE_LIFE + 1.0)
	check_eq(m.corpses.size(), 0, "bodies removed after their life")


func test_dust_blast_replaces_fireball() -> void:
	var e = Fx61Engine.new()
	e.set_quality("high")
	e.explosion(Vector2(0, 0), 16.0, "crater")
	check(int(e.made.get("dust_blast", 0)) == 1, "a ground blast is a dust blast")
	var dust := 0
	var flames := 0
	var longest := 0.0
	for p in e.parts:
		if String(p.tx) == "puff":
			dust += 1
			longest = maxf(longest, float(p.life))
		elif String(p.tx) == "flame":
			flames += 1
	check(dust >= 6 and longest >= 6.0, "brown dust columns linger (%d puffs, longest %.1f s)" % [dust, longest])
	check(flames <= 2, "no big fireball (%d flame parts)" % flames)
	var e2 = Fx61Engine.new()
	e2.destruction(Vector2.ZERO, true, 7, 5.0)
	check(int(e2.made.get("dust_blast", 0)) == 0 and DecalLayer.live_count(e2.decals, "debris") >= 1, "a vehicle cook-off keeps its fireball and leaves rubble")


func test_last_known_markers_fade() -> void:
	check(is_equal_approx(FogLayer.marker_alpha(1.0, 0.0), 1.0), "fresh, certain contact fully drawn")
	check(FogLayer.marker_alpha(1.0, 30.0) < FogLayer.marker_alpha(1.0, 5.0), "older markers fainter")
	check(FogLayer.marker_alpha(0.3, 5.0) < FogLayer.marker_alpha(0.9, 5.0), "less confident markers fainter")
	check(FogLayer.marker_alpha(1.0, FogLayer.MARK_LIFE) <= 0.0, "gone after MARK_LIFE")


func test_g7_pose_selection() -> void:
	var inf: Dictionary = AC.manifest().get("infantry", {})
	var spec: Dictionary = inf.get("rifleman", {})
	var a: Dictionary = BatchArt.inf_cols(spec.get("frames", []))
	if not check(a.has("g7_unc"), "rifleman has the G7 columns"):
		return
	var mv := Motion.P_MOVING
	check_eq(Motion.g7_col(a, {"unc": true}, 0, 1.0, 0.1, 100), int(a.g7_unc), "unconscious")
	check_eq(Motion.g7_col(a, {"cared": "drag"}, mv, 1.0, 0.1, 100), int(a.g7_unc), "dragged casualty lies limp")
	check((a.g7_drag as Array).has(Motion.g7_col(a, {"care": "drag"}, mv, 1.0, 0.1, 100)), "dragging")
	check((a.g7_carry as Array).has(Motion.g7_col(a, {"care": "carry"}, mv, 1.0, 0.1, 100)), "stretcher carry")
	check((a.g7_aid as Array).has(Motion.g7_col(a, {"care": "medic"}, 0, 1.0, 0.1, 100)), "medic treatment")
	check_eq(Motion.g7_col(a, {"kd": 95}, 0, 1.0, 0.1, 100), int(a.g7_kdown), "blast knock-down")
	check_eq(Motion.g7_col(a, {"hz": 16, "ht": 98}, mv, 1.0, 0.1, 100), int(a.g7_stumble), "leg hit stumbles")
	check_eq(Motion.g7_col(a, {"hz": 2, "ht": 98}, 0, 1.0, 0.1, 100), int(a.g7_knock), "torso hit knocks back")
	check((a.g7_limp as Array).has(Motion.g7_col(a, {"wz": 16}, mv, 1.0, 0.1, 100)), "one leg hit limps")
	check((a.crawl as Array).has(Motion.g7_col(a, {"wz": 48}, mv, 1.0, 0.1, 100)), "both legs hit crawls")
	check((a.g7_cwalk as Array).has(Motion.g7_col(a, {"gait": "crouch"}, mv, 1.0, 0.1, 100)), "crouch-walk")
	check((a.g7_duck as Array).has(Motion.g7_col(a, {"gait": "duck"}, mv, 1.0, 0.1, 100)), "duck-run")
	check((a.g7_back as Array).has(Motion.g7_col(a, {"back": true}, mv | Motion.P_FIRING, 1.0, 0.1, 100)), "backing off while firing")
	check_eq(Motion.g7_col(a, {"panic": "cower"}, 0, 1.0, 0.1, 100), int(a.g7_cower), "cower")
	check_eq(Motion.g7_col(a, {"panic": "drop"}, 0, 1.0, 0.1, 100), int(a.g7_drop), "drop weapon")
	check_eq(Motion.g7_col(a, {"lean": -1}, Motion.P_FIRING, 1.0, 0.1, 100), int(a.g7_peek_l), "peek left")
	check((a.throw as Array).has(Motion.g7_col(a, {"throw": 97}, 0, 1.0, 0.1, 100)), "grenade wind-up / throw")
	check((a.g7_duck as Array).has(Motion.g7_col(a, {"entry": true}, mv, 1.0, 0.1, 100)), "room entry")
	check_eq(Motion.g7_col(a, {}, mv, 1.0, 0.1, 100), -1, "no G7 state: the G6.1 choice stands")
	check(is_equal_approx(Motion.g7_facing({"herring": 0.5}, 1.0, false), 1.5), "halted vehicle angles into the herringbone")
	check(is_equal_approx(Motion.g7_facing({"herring": 0.5}, 1.0, true), 1.0), "moving vehicle keeps its travel facing")
	check(is_equal_approx(Motion.g7_facing({"sector": 2.0}, 1.0, false), 2.0), "halted soldier watches its sector")


func test_snapshot_fields() -> void:
	var w := make_world({}, true)
	w.step()
	var uid := -1
	var bid := -1
	var ids: Array = w.entities.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = w.entities[id]
		if uid < 0 and String(e.kind) == "unit":
			uid = int(id)
		if bid < 0 and String(e.kind) == "building":
			bid = int(id)
	w.sys_state["g7v"] = {uid: {"wz": 16, "gait": "crouch"}}
	if bid >= 0:
		w.entities[bid]["roof_open"] = true
	RenderSnap.build(w)
	var sn := RenderSnap.latest(w)
	check(sn.get("g7u", {}).has(uid) and int(sn.g7u[uid].wz) == 16, "g7u copies the sparse display table")
	sn.g7u[uid]["wz"] = 0
	check_eq(int(w.sys_state.g7v[uid].wz), 16, "the snapshot copy does not alias the sim table")
	if bid >= 0:
		check(bool((sn.statics[bid] as Dictionary).get("roof_open", false)), "building roof_open in the snapshot")
	check(sn.has("intel"), "intel markers field present")


func _run(view: bool) -> String:
	var w := make_world({}, true)
	var a: Dictionary = BatchArt.inf_cols((AC.manifest().get("infantry", {}).get("rifleman", {}) as Dictionary).get("frames", []))
	for k in 90:
		w.step()
		if view:
			RenderSnap.build(w)
			var sn := RenderSnap.latest(w)
			for id in (sn.get("g7u", {}) as Dictionary):
				Motion.g7_col(a, sn.g7u[id], Motion.P_MOVING, k / 20.0, 0.1, int(sn.tick))
			var fx = Fx61Engine.new()
			fx.explosion(Vector2.ZERO, 12.0, "crater")
			fx.blood(Vector2.ZERO, 6.0, false)
			for c in (sn.get("intel", {}) as Dictionary).values():
				for m in c:
					FogLayer.marker_alpha(float(m[1]), float(m[2]))
	return w.state_hash()


func test_view_never_writes_sim() -> void:
	var a := _run(false)
	var b := _run(true)
	check_eq(b, a, "state hash identical with the G7 view reads on / off")
