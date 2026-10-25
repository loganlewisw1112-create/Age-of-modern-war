extends RefCounted
## Doctrine strategic layer (owner: AI7-DOC). CONTRACTS_G6 section 16 (D40): per AI side, the front and its
## key terrain, main effort vs fixing force, a reserve, attack timing, reserve commitment, retreat and
## regroup. It only sets each formation's task / objective / rally (fs.task, fs.obj, fs.rally, fs.role);
## the operational layer turns them into orders. Intel: own base, fog memory of enemy buildings and
## ctx.visible only (fair).

const D = preload("res://sim/ai/doctrine/doc_util.gd")
const T = preload("res://sim/ai/doctrine/doc_tactical.gd")
const Op = preload("res://sim/ai/doctrine/doc_operational.gd")
const U = preload("res://sim/ai/ai_util.gd")


## The front: {target (enemy position), obj (key terrain before it), hold (our defensive line), base}.
static func front(w: SimWorld, fid: int, st: Dictionary, d: Dictionary, intel: Dictionary) -> Dictionary:
	var base: Vector2 = intel.base
	var target := Vector2.INF
	var bd := INF
	for b in D.known_buildings(w, fid):
		var p: Vector2 = b.pos
		if p.distance_to(base) < bd:
			bd = p.distance_to(base)
			target = p
	if target == Vector2.INF:
		var seen: Array = intel.vis
		target = D.centroid(seen, U.enemy_spawn(w, fid)) if not seen.is_empty() else U.enemy_spawn(w, fid)
	if d.has("force_obj"):
		target = d.force_obj
	var fr: Dictionary = d.front
	if fr.is_empty() or (fr.target as Vector2).distance_to(target) > 4.0:
		var dist := base.distance_to(target)
		var near_t := T.short_of(base, target, minf(D.num("standoff"), dist * 0.5))
		var key := T.key_terrain(w, near_t, D.num("key_terrain_radius"), base)
		var obj: Vector2 = key.pos if int(key.level) >= 2 else target
		if d.has("force_obj"):
			obj = key.pos if int(key.level) >= 2 and (key.pos as Vector2).distance_to(target) <= D.num("key_terrain_radius") else target
		var hp: Vector2 = base + (target - base).normalized() * minf(dist * 0.3, 30.0) if dist > 1.0 else base
		var hk := T.key_terrain(w, hp, D.num("key_terrain_radius") * 0.6, base)
		fr = {"target": target, "obj": obj, "obj_level": int(key.level), "hold": T.clamp_map(w, hk.pos), "base": base}
		d.front = fr
	return fr


## Sets roles and tasks for every formation (forms sorted by key; d.forms holds their states).
static func plan(w: SimWorld, fid: int, st: Dictionary, d: Dictionary, forms: Array, intel: Dictionary) -> void:
	var fr := front(w, fid, st, d, intel)
	var ranked := forms.duplicate()
	ranked.sort_custom(func(a, b): return float(a.power) > float(b.power) or (float(a.power) == float(b.power) and String(a.key) < String(b.key)))
	for i in ranked.size():
		var fs: Dictionary = d.forms[String(ranked[i].key)]
		var role := "main" if i == 0 else ("fixing" if i == 1 and ranked.size() >= 2 else "reserve")
		if ranked.size() == 2 and i == 1:
			role = "fixing"
		if String(fs.role) != "committed" or not bool(d.get("launched", false)):
			fs.role = role
	# retreat and regroup come first: a broken formation is no use to any plan
	for form in ranked:
		var fs: Dictionary = d.forms[String(form.key)]
		var s := float(form.strength)
		if String(fs.task) != "retreat":
			var local := _local_ratio(form, intel, fs)
			if s < D.num("retreat_strength") or (String(fs.phase) == "assault" and local < D.num("retreat_ratio")):
				fs.task = "retreat"
				fs.rally = fr.hold if (fr.hold as Vector2).distance_to(fs.obj) > 6.0 else fr.base
				fs.task_tick = w.tick
				D.decide(w, fid, st, "retreat", form.units, "%s pulls back to (%d, %d): strength %d%%, local ratio %.1f." % [
					String(form.name), int(fs.rally.x), int(fs.rally.y), roundi(s * 100.0), local])
		elif String(fs.phase) == "regroup" and (s >= D.num("regroup_strength") or w.tick - int(fs.pt) >= D.ticks("regroup_ticks")):
			fs.task = "hold"
			fs.obj = fs.rally
			fs.start = int(form.alive)
			fs.task_tick = w.tick
			D.decide(w, fid, st, "regroup", form.units, "%s regrouped at (%d, %d) with %d units (%d%%); back in the line." % [
				String(form.name), int(fs.rally.x), int(fs.rally.y), int(form.alive), roundi(s * 100.0)])
	_timing(w, fid, st, d, ranked, intel, fr)


static func _local_ratio(form: Dictionary, intel: Dictionary, fs: Dictionary) -> float:
	var foes := D.near(intel.vis, fs.obj, D.num("objective_radius") + D.num("contact_range"))
	var fp := D.power(foes)
	return 99.0 if fp <= 0.0 else float(form.power) / fp


## Launch, sequence and commit: the fixing force goes first and pins the enemy; the main effort follows on
## its own axis to the key terrain once the fixing force is in contact; the reserve holds the line and is
## committed when an assault stalls or bleeds.
static func _timing(w: SimWorld, fid: int, st: Dictionary, d: Dictionary, ranked: Array, intel: Dictionary, fr: Dictionary) -> void:
	var ready := true
	var power := 0.0
	for form in ranked:
		var fs: Dictionary = d.forms[String(form.key)]
		if String(fs.role) != "reserve" and (String(fs.task) == "retreat" or float(form.strength) < D.num("launch_strength")):
			ready = false
		if String(fs.task) != "retreat":
			power += float(form.power)
	var foes := D.power(D.near(intel.vis, fr.obj, D.num("key_terrain_radius") + D.num("contact_range")))
	var ratio := 99.0 if foes <= 0.0 else power / foes
	var launched := bool(d.get("launched", false))
	if not launched and ready and (ratio >= D.num("launch_ratio") or String(st.get("objective", "")) == "attack" or bool(d.get("force_attack", false))):
		d.launched = true
		d.launch_tick = w.tick
		launched = true
		U.log_line(st, w, "doctrine: attack launched on (%d, %d), ratio %.1f" % [int(fr.obj.x), int(fr.obj.y), ratio])
	var fixing_engaged := true
	for form in ranked:
		var fs: Dictionary = d.forms[String(form.key)]
		if String(fs.role) == "fixing" and String(fs.task) == "attack":
			fixing_engaged = ["recon", "suppress", "assault", "consolidate"].has(String(fs.phase))
	var all_done := launched
	for form in ranked:
		var fs: Dictionary = d.forms[String(form.key)]
		if String(fs.task) == "retreat":
			continue
		var role := String(fs.role)
		if not launched or role == "reserve":
			if String(fs.task) != "hold" or (role == "reserve" and (fs.obj as Vector2).distance_to(fr.hold) > 8.0 and not bool(fs.done)):
				fs.task = "hold"
				fs.obj = fr.hold if role == "reserve" or not bool(fs.done) else fs.obj
			continue
		if String(fs.task) == "hold" and not bool(fs.done):
			if role == "fixing":
				fs.task = "attack"
				fs.obj = fr.target if (fr.target as Vector2).distance_to(fr.obj) > 6.0 else fr.obj
			elif role == "main" or role == "committed":
				var solo := ranked.size() == 1 or not _has_role(d, ranked, "fixing")
				if solo or fixing_engaged or w.tick - int(d.launch_tick) > D.ticks("stall_ticks"):
					fs.task = "attack"
					fs.obj = fr.obj
			fs.task_tick = w.tick
		if not bool(fs.done):
			all_done = false
	_commit(w, fid, st, d, ranked)
	if launched and all_done:
		d.launched = false
		d.committed = false
		for form in ranked:
			d.forms[String(form.key)].done = false
		d.front = {}  # the next think picks the next objective


static func _has_role(d: Dictionary, ranked: Array, role: String) -> bool:
	for form in ranked:
		if String(d.forms[String(form.key)].role) == role:
			return true
	return false


static func _commit(w: SimWorld, fid: int, st: Dictionary, d: Dictionary, ranked: Array) -> void:
	if not bool(d.get("launched", false)) or bool(d.get("committed", false)):
		return
	for form in ranked:
		var fs: Dictionary = d.forms[String(form.key)]
		if String(fs.task) != "attack" or String(fs.phase) != "assault":
			continue
		var bleeding := float(form.strength) < D.num("commit_strength")
		var stalled := w.tick - int(fs.pt) > D.ticks("stall_ticks")
		if not (bleeding or stalled):
			continue
		for res in ranked:
			var rs: Dictionary = d.forms[String(res.key)]
			if String(rs.role) == "reserve" and String(rs.task) == "hold":
				rs.role = "committed"
				rs.task = "attack"
				rs.obj = fs.obj
				rs.done = false
				d.committed = true
				D.decide(w, fid, st, "reserve_commit", res.units, "Reserve %s committed to (%d, %d): %s is %s." % [
					String(res.name), int(fs.obj.x), int(fs.obj.y), String(form.name), "bleeding (%d%%)" % roundi(float(form.strength) * 100.0) if bleeding else "stalled"])
				return
