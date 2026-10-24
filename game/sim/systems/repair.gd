extends RefCounted
## Repair (owner: agent B2). `repair {unit_ids (engineers), target_id}` restores an own damaged
## vehicle (components, then hp), an own built building, or the ruined bridge.
## Contract: docs/CONTRACTS_G2.md section 3.
##
## Accounting is in milli-points (1000 = 1 hp / 1 component point) so it stays integer-safe.
## Work on units/buildings is paid per chunk of up to 100 points (rules.repair.salvage_per_100hp,
## rounded up for a short last chunk) through w.spend(..., "repair") BEFORE the points are
## restored; paid-but-unspent points wait in target.repair_pool (shared by all engineers).
## Job order for a vehicle: components below 50 up to 50 (lowest first, mobility first on ties),
## then hp, then remaining components up to 100.
## The bridge costs buildings.json bridge_span.repair_salvage in 10 equal chunks; progress
## e.repair_progress 0..1 over repair_time seconds for ONE engineer (several stack). At 1.0 it
## calls Bridges.on_repaired(w, e).
## G3a (S3-sim): repairers are units with `can_build` OR `can_repair`. A `can_repair` unit without
## `can_build` (b_recovery_truck) repairs vehicles only (units with components); builders such as
## the Machine m_repair_bot repair everything, like an engineer.

const Construction = preload("res://sim/systems/construction.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Bridges = preload("res://sim/systems/bridges.gd")
const Subsets = preload("res://sim/systems/unit_subsets.gd")  # G3b scale (PERF5): repairer units

const REACH := 1.5
const CHUNK_M := 100000
const COMP_KEYS := ["mobility", "weapon", "sensors"]
const COMP_FLOOR := 50.0
const BRIDGE_CHUNKS := 10


# ================================================================ target helpers
static func _is_bridge(t: Dictionary) -> bool:
	return String(t.def) == "bridge_span"


static func _bridge_ruined(t: Dictionary) -> bool:
	return _is_bridge(t) and String(t.get("state", "")) == "ruined"


## Next repair job for a unit/building target: {} when nothing is left, else
## {kind:"hp"|"comp", key, to:float (target value), rem_m:int}.
static func job_for(t: Dictionary) -> Dictionary:
	if t.kind == "building":
		if bool(t.built) and float(t.hp) < float(t.max_hp) - 0.0005:
			return {"kind": "hp", "key": "", "to": float(t.max_hp), "rem_m": int(round((float(t.max_hp) - float(t.hp)) * 1000.0))}
		return {}
	if t.kind != "unit":
		return {}
	var maxc: Dictionary = Content.unit(t.def).get("components", {})
	if t.has("comp"):
		var best := ""
		var best_v := COMP_FLOOR
		for k in COMP_KEYS:
			if t.comp.has(k) and float(t.comp[k]) < best_v:
				best_v = float(t.comp[k])
				best = k
		if best != "":
			return {"kind": "comp", "key": best, "to": COMP_FLOOR, "rem_m": int(round((COMP_FLOOR - best_v) * 1000.0))}
	if float(t.hp) < float(t.max_hp) - 0.0005:
		return {"kind": "hp", "key": "", "to": float(t.max_hp), "rem_m": int(round((float(t.max_hp) - float(t.hp)) * 1000.0))}
	if t.has("comp"):
		var worst := ""
		var worst_v := 1.0e9
		for k in COMP_KEYS:
			if t.comp.has(k) and float(t.comp[k]) < float(maxc.get(k, 100)) - 0.0005 and float(t.comp[k]) < worst_v:
				worst_v = float(t.comp[k])
				worst = k
		if worst != "":
			var to := float(maxc.get(worst, 100))
			return {"kind": "comp", "key": worst, "to": to, "rem_m": int(round((to - worst_v) * 1000.0))}
	return {}


static func _bridge_dist(pos: Vector2, t: Dictionary) -> float:
	var best := INF
	for c in t.get("cells", []):
		best = minf(best, Construction.footprint_dist(pos, Vector2i(c), 1))
	return best


static func _dist(pos: Vector2, t: Dictionary) -> float:
	if _is_bridge(t):
		return _bridge_dist(pos, t)
	if t.kind == "building":
		return Construction.footprint_dist(pos, t.cell, int(t.size))
	return (Vector2(t.pos) - pos).length()


## Passable bank cell next to the (ruined) bridge closest to the engineer.
static func _bridge_goal(w: SimWorld, e: Dictionary, t: Dictionary) -> Vector2:
	var mc := String(Content.unit(e.def).get("move_class", "foot"))
	var cellset := {}
	for c in t.get("cells", []):
		cellset[Vector2i(c)] = true
	var best := Vector2(t.pos)
	var best_d := INF
	for c in t.get("cells", []):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n := Vector2i(c) + Vector2i(dx, dy)
				if cellset.has(n) or not w.in_bounds(n) or not Movement.is_passable(w, n, mc):
					continue
				var p := Vector2(n) + Vector2(0.5, 0.5)
				var d := (p - Vector2(e.pos)).length_squared()
				if d < best_d:
					best_d = d
					best = p
	return best


# ================================================================ command
static func is_repairer(e: Dictionary) -> bool:
	if e.kind != "unit":
		return false
	var d := Content.unit(e.def)
	return bool(d.get("can_build", false)) or bool(d.get("can_repair", false))


## True if repairer e may work on target t (vehicle-only repairers need a unit with components).
static func can_repair_target(e: Dictionary, t: Dictionary) -> bool:
	if bool(Content.unit(e.def).get("can_build", false)):
		return true
	return t.kind == "unit" and t.has("comp")


static func _engineers(w: SimWorld, cmd: Dictionary) -> Array:
	var out := []
	for raw in cmd.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if e != null and is_repairer(e):
			out.append(int(raw))
	return out


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.issuer)
	var engs := _engineers(w, cmd)
	if engs.is_empty():
		return "Only engineers can repair."
	var tid := int(cmd.get("target_id", -1))
	var t = w.entities.get(tid)
	if t == null:
		return "Nothing to repair."
	if _is_bridge(t):
		if not w.is_visible(fid, t.pos):
			return "Target not visible."
		if not _bridge_ruined(t):
			return "Nothing to repair."
		for id in engs:
			if can_repair_target(w.entities[id], t):
				return ""
		return "Recovery vehicles can only repair vehicles."
	if t.kind != "unit" and t.kind != "building":
		return "Nothing to repair."
	if int(t.owner) != fid:
		return "Not your unit." if t.kind == "unit" else "Not your building."
	if job_for(t).is_empty():
		return "Nothing to repair."
	if engs.size() == 1 and engs[0] == tid:
		return "Nothing to repair."
	for id in engs:
		if id != tid and can_repair_target(w.entities[id], t):
			return ""
	return "Recovery vehicles can only repair vehicles."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var tid := int(cmd.target_id)
	var t: Dictionary = w.entities[tid]
	for id in _engineers(w, cmd):
		if id == tid or not can_repair_target(w.entities[id], t):
			continue
		var e: Dictionary = w.entities[id]
		e.order = {"type": "repair", "target_id": tid}
		e.target = -1
		e.nav_for = -1
		e.nav_wait = 0
		e.repair_goal = Vector2(-1000, -1000)
		if _dist(e.pos, t) <= REACH:
			Construction.stop_moving(e)
		else:
			_approach(w, e, t)


static func _approach(w: SimWorld, e: Dictionary, t: Dictionary) -> void:
	if t.kind == "building":
		Construction.approach(w, e, t)
		return
	var goal: Vector2 = _bridge_goal(w, e, t) if _is_bridge(t) else Vector2(t.pos)
	if (goal - Vector2(e.get("repair_goal", Vector2(-1000, -1000)))).length() > 2.0:
		e.nav_for = -1
		e.repair_goal = goal
	Construction.approach_point(w, e, int(t.id), goal)


# ================================================================ tick
static func _block(w: SimWorld, e: Dictionary, tid: int, reason: String) -> void:
	w.emit("RepairBlocked", {"unit_id": int(e.id), "target_id": tid, "reason": reason})
	Construction.make_idle(e)


## Only repairers (can_build or can_repair) ever hold a "repair" order (_engineers), so walk that
## subset (PERF5), ascending id as before.
static func tick(w: SimWorld) -> void:
	for e in Subsets.units(w, Subsets.REPAIRER):
		var id := int(e.id)
		if not w.entities.has(id) or String(e.order.get("type", "")) != "repair":
			continue
		var tid := int(e.order.get("target_id", -1))
		var t = w.entities.get(tid)
		if t == null or tid == int(id) or not can_repair_target(e, t):
			Construction.make_idle(e)
			continue
		var bridge := _is_bridge(t)
		if bridge:
			if not _bridge_ruined(t):
				Construction.make_idle(e)
				continue
		elif int(t.owner) != int(e.owner) or job_for(t).is_empty():
			Construction.make_idle(e)
			continue
		if _dist(e.pos, t) > REACH:
			_approach(w, e, t)
			continue
		if e.moving:
			Construction.stop_moving(e)
		if bridge:
			_work_bridge(w, e, t)
		else:
			_work_unit(w, e, t)


static func _work_unit(w: SimWorld, e: Dictionary, t: Dictionary) -> void:
	var cfg: Dictionary = Content.rules().get("repair", {})
	var rate_m := int(round(float(cfg.get("hp_per_second", 0)) * 1000.0 * SimWorld.DT))
	var job := job_for(t)
	var rem: int = job.rem_m
	var pool := int(t.get("repair_pool", 0))
	var want := mini(rate_m, rem)
	if pool < want:
		var chunk := mini(CHUNK_M, rem - pool)
		var cost := (int(cfg.get("salvage_per_100hp", 0)) * chunk + CHUNK_M - 1) / CHUNK_M
		if cost > 0 and not w.spend(int(e.owner), {"salvage": cost}, "repair"):
			_block(w, e, int(t.id), "Not enough salvage to continue repairs.")
			return
		pool += chunk
	var take := mini(want, pool)
	t.repair_pool = pool - take
	var done: bool = take >= rem
	if job.kind == "hp":
		t.hp = float(t.max_hp) if done else minf(float(t.max_hp), float(t.hp) + float(take) / 1000.0)
	else:
		t.comp[job.key] = float(job.to) if done else minf(float(job.to), float(t.comp[job.key]) + float(take) / 1000.0)


static func _work_bridge(w: SimWorld, e: Dictionary, t: Dictionary) -> void:
	var bd := Content.building("bridge_span")
	var total := int(bd.get("repair_salvage", 0))
	var secs := maxf(float(bd.get("repair_time", 1)), 0.001)
	var inc := SimWorld.DT / secs
	var progress := float(t.get("repair_progress", 0.0))
	var paid := int(t.get("repair_paid", 0))
	while inc > 1.0e-9 and progress < 1.0 - 1.0e-9:
		var cap := float(paid) / float(BRIDGE_CHUNKS)
		if progress >= cap - 1.0e-9:
			if paid >= BRIDGE_CHUNKS:
				break
			var cost := total / BRIDGE_CHUNKS + (1 if paid < total % BRIDGE_CHUNKS else 0)
			if cost > 0 and not w.spend(int(e.owner), {"salvage": cost}, "repair"):
				t.repair_progress = progress
				t.repair_paid = paid
				_block(w, e, int(t.id), "Not enough salvage to continue repairs.")
				return
			paid += 1
			cap = float(paid) / float(BRIDGE_CHUNKS)
		var step := minf(inc, cap - progress)
		progress += step
		inc -= step
	t.repair_progress = progress
	t.repair_paid = paid
	if progress >= 1.0 - 1.0e-9:
		t.repair_progress = 0.0
		t.repair_paid = 0
		Bridges.on_repaired(w, t)
		for o in Subsets.units(w, Subsets.REPAIRER):
			if String(o.order.get("type", "")) == "repair" and int(o.order.get("target_id", -1)) == int(t.id):
				Construction.make_idle(o)
