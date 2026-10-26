extends RefCounted
## G6.1 playtest flow anim61 (ANIMA61): zoomed-in infantry walk cycle (10-shot strip anim61_strip_*), a tank's
## smooth 180-degree turn, a squad pinned prone under fire, a firefight with a death (die_0..2 then a lingering
## corpse). Logs the entity layer's motion / anim61 counters and the atlas page stats.

const H = preload("res://tests/test_machine_g6.gd")
const Morale = preload("res://sim/systems/morale.gd")
const Motion = preload("res://presentation/view/motion.gd")


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func run(pt) -> void:
	var mv = pt._mv()
	var el = mv.entity_layer
	mv.join_sim()
	var w: SimWorld = pt._w()
	var h = H.new()
	var c: Vector2i = h._open(w, 8)
	var sq: Array = []
	for i in 4:
		sq.append(int(h._unit(w, "rifleman", 0, Vector2(c) + Vector2(-4.0, i * 0.7 - 1.0)).id))
	_zoom(mv, 2.4)
	mv.center_camera_on(Vector2(c) + Vector2(-2, 0))
	await pt._wait(0.6)
	# 1. walk cycle: march 7 tiles; 10-shot strip 0.3 s apart
	mv.issue({"type": "move", "unit_ids": sq.duplicate(), "target": Vector2(c) + Vector2(3.0, 0.0)})
	await pt._wait(0.5)
	var a0 := int(el.g61_counts.get("a61", 0))
	for i in 10:
		await pt._shot("anim61_strip_%02d" % i)
		await pt._wait(0.3)
	pt._log("anim_walk_cycle", int(el.g61_counts.get("a61", 0)) > 0 and int(el.g61_counts.get("motion", 0)) > 0,
		"g61 %s (a61 at start %d) motion_on %s" % [str(el.g61_counts), a0, str(el.motion_on)])
	await pt._shot("anim61_walk")
	# 2. smooth tank turn: an MBT reverses its heading; the drawn facing turns at the class rate, no 8-way pops
	mv.join_sim()
	var tk := int(h._unit(pt._w(), "mbt", 0, Vector2(c) + Vector2(0.0, 4.0)).id)
	mv.center_camera_on(Vector2(c) + Vector2(0, 4))
	await pt._wait(0.6)
	mv.issue({"type": "move", "unit_ids": [tk], "target": Vector2(c) + Vector2(-6.0, 4.0)})
	var worst := 0.0
	var prev := -100.0
	var turned := 0.0
	for k in 40:
		await pt._wait(0.05)
		var s = el.motion.vs.get(tk)
		if s == null:
			continue
		var f: float = float(s[Motion.S_FACE])
		if prev > -99.0:
			var d := absf(wrapf(f - prev, -PI, PI))
			worst = maxf(worst, d)
			turned += d
		prev = f
		if k == 12:
			await pt._shot("anim61_tank_turn")
	pt._log("anim_tank_smooth_turn", turned > 0.5 and worst < PI / 4.0 + 0.01,
		"turned %.2f rad, biggest step between samples %.3f rad (8-way pop = %.3f)" % [turned, worst, PI / 4.0])
	# 3. prone under fire: suppress the squad until pinned
	mv.center_camera_on(Vector2(c) + Vector2(2, 0))
	var per_hit := float((Content.rules().get("suppression", {}) as Dictionary).get("per_hit", 18))
	for k in 12:
		mv.join_sim()
		for id in sq:
			var e = pt._w().entities.get(id)
			if e != null:
				Morale.add_supp(pt._w(), e, per_hit, 2.0)
		await pt._wait(0.1)
	await pt._wait(0.4)
	var prone := 0
	for id in sq:
		prone += 1 if int(el._post.get(id, 0)) & Motion.P_PINNED else 0
	pt._log("anim_prone_under_fire", prone > 0, "%d / %d drawn pinned (prone / crawl / fire_p)" % [prone, sq.size()])
	await pt._shot("anim61_prone")
	# 4. firefight and a death: an enemy fire team close by, one of them nearly dead
	mv.join_sim()
	var foes: Array = []
	for i in 3:
		foes.append(int(h._unit(pt._w(), "rifleman", 1, Vector2(c) + Vector2(6.0, i * 0.8 - 0.8)).id))
	h._hp(pt._w(), pt._w().entities[foes[0]], 3.0)
	mv.center_camera_on(Vector2(c) + Vector2(4.5, 0))
	var died: bool = await pt._wait_until(func(): return not el.motion.corpses.is_empty(), 40.0)
	pt._log("anim_death_corpse", died, "corpses %d" % el.motion.corpses.size())
	if died:
		var cp: Array = el.motion.corpses[0]
		mv.center_camera_on(Vector2((cp[2] as Vector2).x / 64.0 + (cp[2] as Vector2).y / 32.0, (cp[2] as Vector2).y / 32.0 - (cp[2] as Vector2).x / 64.0))
		for i in 3:
			await pt._shot("anim61_death_%d" % i)
			await pt._wait(0.2)
		await pt._wait(1.0)
		pt._log("anim_corpse_lingers", int(el.g61_counts.get("corpses", 0)) >= 1, str(el.g61_counts))
		await pt._shot("anim61_corpse")
	pt._log("anim_atlas_stats", true, "atlas %s chevrons %d" % [str(el.art.atlas.stats()), int(el.g61_counts.get("chevrons", 0))])
	_zoom(mv, 1.0)
