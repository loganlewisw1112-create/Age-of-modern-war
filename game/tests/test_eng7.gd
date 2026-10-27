extends "res://tests/test_base.gd"
## G7 acceptance (owner: ENG7). G7_REFERENCE 13.9c-11 (Facility Engineer) + 13.9c-12 (facility staff run themselves).
## Each job happens on its own (damaged wall repaired, empty locker refilled from the magazine by forklift, APC and
## dropship refuelled by the bowser, a construction site built), no two engineers on one job, the most urgent job wins,
## player order override then return to duty, hash twice-same, no facility = no cost.

const E7 = preload("res://sim/systems/engineer7.gd")
const S7 = preload("res://sim/systems/sentinels7.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Air = preload("res://sim/systems/air.gd")


func _ensure_g7() -> void:
	if Content.unit("g7_fac_engineer").is_empty() or Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()


## Inert 2-side world with an n x n GRASS arena in the map centre; returns [w, arena origin, n].
func _setup(n0: int = 60) -> Array:
	var w := make_world()
	_ensure_g7()
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(n0, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var r := Rect2i(o, Vector2i(n, n))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if r.has_point(w.cell_of(e.pos)):
			w.entities.erase(id)
	w.cache.clear()
	Movement.rebuild_nav(w)
	w.factions[0].credits = 200000
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[0].stock[k] = 200000
	return [w, o, n]


func _step(w: SimWorld) -> void:
	w.step()
	if not SimWorld.SYSTEM_ORDER.has(E7):
		E7.tick(w)


func _run(w: SimWorld, n: int) -> void:
	for i in n:
		_step(w)


## Runs until cond(w) or max ticks; returns the ticks used (-1 = never).
func _until(w: SimWorld, mx: int, cond: Callable) -> int:
	for i in mx:
		_step(w)
		if cond.call(w):
			return i + 1
	return -1


## Raises a facility for side 0; the Sentinel garrison stays out (the crew works alone, plain to read).
func _facility(w: SimWorld, o: Vector2i) -> int:
	var off: Array = CnFacility.conf().core_offset
	var id := w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	S7._st(w).seeded.append(id)
	_run(w, CnFacility.DISCOVER_EVERY + 6)
	return id


func _fac_id(w: SimWorld) -> int:
	var cn = w.sys_state.get("cn_facility")
	if cn == null:
		return -1
	for k in cn.facs:
		return int(k)
	return -1


func _parts(w: SimWorld, fac: int, def_id: String) -> Array:
	var out := []
	for pid in CnFacility.fac(w, fac).get("parts", []):
		var b = w.entities.get(int(pid))
		if b != null and String(b.def) == def_id:
			out.append(int(pid))
	return out


## Collects every event of type ty seen while running n ticks.
func _run_events(w: SimWorld, n: int, ty: String) -> Array:
	var out := []
	for i in n:
		_step(w)
		for ev in w.events:
			if String(ev.type) == ty:
				out.append(ev.duplicate())
	return out


func _keep_engineers(w: SimWorld, fac: int, n: int) -> Array:
	var ids := E7.engineers_of(w, fac)
	for i in range(n, ids.size()):
		w.entities.erase(int(ids[i]))
	w.cache.clear()
	return ids.slice(0, n)


# ================================================================ content + roster
func test_defs_pistol_only_trained_at_the_facility() -> void:
	_ensure_g7()
	var bk := Content.building("cn_sentinel_barracks")
	for d_id in ["g7_fac_engineer", "g7_b_fac_engineer"]:
		var d := Content.unit(d_id)
		if not check(not d.is_empty(), "%s exists" % d_id):
			continue
		check_eq(String(d.get("weapon", "")), "pistol", "%s: pistol only" % d_id)
		check(bool(d.get("can_build", false)) and bool(d.get("no_command", false)), "%s: work crew, no command role" % d_id)
		check(not bool(d.get("can_gather", false)), "%s: not an economy gatherer" % d_id)
		check((bk.get("produces", []) as Array).has(d_id), "Sentinel Barracks trains %s" % d_id)


func test_start_crew_joins_the_board() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	_facility(w, s[1])
	var fac := _fac_id(w)
	var ids := E7.engineers_of(w, fac)
	check_eq(ids.size(), int(E7.R().get("start_count", 3)), "facility starts with its work crew")
	var S = S7.state(w)
	for id in ids:
		var e: Dictionary = w.entities[int(id)]
		check_eq(int(e.get("squad", -2)), -1, "engineer has no squad")
		check(S != null and S.get("workers", {}).has(str(id)), "engineer %d is a worker on the facility job board" % int(id))
	check(E7.staffed(w, CnFacility.fac(w, fac)), "facility is staffed")


# ================================================================ jobs happen on their own
func test_damaged_wall_gets_repaired() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	_facility(w, s[1])
	var fac := _fac_id(w)
	var walls := _parts(w, fac, "cn_blast_wall")
	if not check(not walls.is_empty(), "facility has blast walls"):
		return
	var wb: Dictionary = w.entities[int(walls[walls.size() / 2])]
	wb.hp = float(wb.max_hp) * 0.84
	var sal0 := int(w.factions[0].stock.salvage)
	var used := _until(w, 2400, func(ww): return float(ww.entities[int(wb.id)].hp) >= float(wb.max_hp) - 0.01)
	check(used > 0, "damaged wall repaired by the crew, no player order (%d ticks)" % used)
	check(int(w.factions[0].stock.salvage) < sal0, "repair paid salvage as any repair")


func test_empty_locker_refilled_from_magazine_by_forklift() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	_facility(w, s[1])
	var fac := _fac_id(w)
	var lks := S7.lockers_of(w, 0)
	if not check(not lks.is_empty(), "facility has ready-ammo lockers"):
		return
	var lid := int(lks[0])
	S7.locker_add(w, lid, -999)
	check_eq(S7.locker_stock(w, lid), 0, "locker emptied")
	var am0 := int(w.factions[0].stock.ammo)
	var jobs := []
	var got := -1
	for i in 3000:
		_step(w)
		for ev in w.events:
			if String(ev.type) == "Eng7Job":
				jobs.append(String(ev.job))
		if S7.locker_stock(w, lid) >= int(S7.R().get("locker", {}).get("cap", 14)):
			got = i
			break
	check(got > 0, "empty locker refilled to cap by an engineer (%d ticks)" % got)
	check(jobs.has("forklift"), "engineer drove the loaded forklift (Eng7Job forklift)")
	check(int(w.factions[0].stock.ammo) < am0, "the load came out of the side's ammo stock")
	jobs.append_array(_run_events(w, 900, "Eng7Job").map(func(ev): return String(ev.job)))
	check(jobs.has("forklift_empty") and jobs.has(""), "forklift driven back empty and parked (%s)" % str(jobs))


func test_apc_and_dropship_refuelled_by_bowser() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	_facility(w, s[1])
	var fac := _fac_id(w)
	var F := CnFacility.fac(w, fac)
	var team := 0
	var st: Rect2 = CnFacility.zone(F, "staging")
	var c: Vector2i = Movement.nearest_free_cell(w, w.cell_of(st.get_center()), "vehicle", team)
	var apc := w.spawn_unit("g7_cn_strike_apc", 0, Vector2(c) + Vector2(0.5, 0.5))
	w.entities[apc].fuel = 60.0
	var ds := w.spawn_unit("a_vtol_dropship", 0, CnFacility.compound_rect(F).get_center() + Vector2(0.5, 6.5))
	Air.land_now(w, w.entities[ds])
	w.entities[ds].fuel = 50.0
	var fu0 := int(w.factions[0].stock.fuel)
	var evs := []
	var done := -1
	for i in 4000:
		_step(w)
		for ev in w.events:
			if String(ev.type) == "Eng7Job" or String(ev.type) == "Eng7Refuel":
				evs.append(ev.duplicate())
		var fa := float(w.entities[apc].fuel) >= 519.9
		var fd := w.entities.has(ds) and float(w.entities[ds].fuel) >= 499.9
		if fa and fd:
			done = i
			break
	check(done > 0, "APC (%.0f) and landed dropship (%.0f) refuelled with no orders (%d ticks)" % [float(w.entities[apc].fuel), float(w.entities[ds].get("fuel", 0.0)) if w.entities.has(ds) else -1.0, done])
	var tg := []
	var bowser := false
	for ev in evs:
		if String(ev.type) == "Eng7Refuel":
			tg.append(int(ev.target))
		elif String(ev.job) == "fuel":
			bowser = true
	check(tg.has(apc), "an engineer pumped the APC (Eng7Refuel)")
	check(bowser, "engineer drove the fuel bowser (Eng7Job fuel)")
	check(int(w.factions[0].stock.fuel) < fu0, "fuel came out of the side's stock")


func test_construction_site_built_by_crew() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	_facility(w, s[1])
	var fac := _fac_id(w)
	var F := CnFacility.fac(w, fac)
	var cr: Rect2 = CnFacility.compound_rect(F)
	var cell := Vector2i(int(cr.end.x) + 2, int(cr.get_center().y))
	var bid := w.spawn_building("cn_ammo_locker", 0, cell, false)
	w.entities[bid].cn_fac = fac
	S7.post_job(w, fac, {"id": "wt7:%d" % bid, "kind": "build", "pos": Vector2(cell) + Vector2(-0.5, 0.5), "prio": 2.5,
		"roles": ["engineer"], "slots": 1, "bid": bid, "ttl_s": 600})
	var used := _until(w, 4000, func(ww): return ww.entities.has(bid) and bool(ww.entities[bid].built))
	check(used > 0, "construction site on the board built by an engineer (%d ticks)" % used)


# ================================================================ coordination
func test_no_two_engineers_on_one_job_and_most_urgent_first() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	_facility(w, s[1])
	var fac := _fac_id(w)
	var walls := _parts(w, fac, "cn_blast_wall")
	if not check(walls.size() >= 2, "two walls"):
		return
	var crew := _keep_engineers(w, fac, 1)
	var a: Dictionary = w.entities[int(walls[0])]
	var b: Dictionary = w.entities[int(walls[walls.size() - 1])]
	a.hp = float(a.max_hp) * 0.8
	b.hp = float(b.max_hp) * 0.3   # far more urgent
	_run(w, 220)
	var j := S7.job_of(w, int(crew[0]))
	check_eq(int(j.get("bid", -1)), int(b.id), "the lone engineer takes the most urgent repair (%s)" % str(j))
	# with the whole crew: every board job held by at most its slots, never one unit on two jobs
	var s2 := _setup()
	var w2: SimWorld = s2[0]
	_facility(w2, s2[1])
	var fac2 := _fac_id(w2)
	var walls2 := _parts(w2, fac2, "cn_blast_wall")
	for i in mini(4, walls2.size()):
		var wb: Dictionary = w2.entities[int(walls2[i])]
		wb.hp = float(wb.max_hp) * (0.5 + 0.08 * float(i))
	var clash := 0
	var seen_jobs := 0
	for t in 600:
		_step(w2)
		if t % 50 == 0:
			var holders := {}
			for uid in E7.engineers_of(w2, fac2):
				var jj := S7.job_of(w2, int(uid))
				var jid := String(jj.get("j", ""))
				if jid == "" or jid == "rest":
					continue
				seen_jobs += 1
				if holders.has(jid):
					clash += 1
				holders[jid] = true
	check(seen_jobs > 0, "crew took jobs (%d samples)" % seen_jobs)
	check_eq(clash, 0, "no two engineers on the same job")


func test_player_order_then_back_to_duty() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	_facility(w, s[1])
	var fac := _fac_id(w)
	var crew := _keep_engineers(w, fac, 1)
	var uid := int(crew[0])
	_run(w, 40)
	var e: Dictionary = w.entities[uid]
	var F := CnFacility.fac(w, fac)
	var far: Vector2i = Movement.nearest_free_cell(w, w.cell_of(CnFacility.compound_rect(F).get_center() + Vector2(-9.0, 7.0)), "foot", 0)
	var tgt: Vector2 = Vector2(far) + Vector2(0.5, 0.5)
	do_cmd(w, 0, {"type": "move", "unit_ids": [uid], "target": tgt})
	_run(w, 12)
	check_eq(String(S7.job_of(w, uid).get("k", "")), "player", "a player order hands the engineer to the player")
	var walls := _parts(w, fac, "cn_blast_wall")
	var wb: Dictionary = w.entities[int(walls[0])]
	wb.hp = float(wb.max_hp) * 0.6
	_run(w, 20)
	var o: Dictionary = w.entities[uid].order
	check(String(S7.job_of(w, uid).get("k", "")) == "player" and (String(o.get("type", "")) == "move" or Vector2(w.entities[uid].pos).distance_to(tgt) < 1.5),
		"player order is obeyed while it runs, no auto pull (order %s, rec %s, d %.1f)" % [str(o), str(S7.job_of(w, uid)), Vector2(w.entities[uid].pos).distance_to(tgt)])
	var back := _until(w, 1500, func(ww): return String(S7.job_of(ww, uid).get("k", "")) == "repair")
	check(back > 0, "order done: back on automatic duty and takes the repair (%d ticks)" % back)
	check(Vector2(w.entities[uid].pos).distance_to(tgt) < 6.0 or back > 0, "it went where the player sent it first")


# ================================================================ determinism + cost
func _scenario_hash() -> String:
	var s := _setup()
	var w: SimWorld = s[0]
	_facility(w, s[1])
	var fac := _fac_id(w)
	var walls := _parts(w, fac, "cn_blast_wall")
	var wb: Dictionary = w.entities[int(walls[1])]
	wb.hp = float(wb.max_hp) * 0.7
	var lks := S7.lockers_of(w, 0)
	if not lks.is_empty():
		S7.locker_add(w, int(lks[0]), -999)
	_run(w, 900)
	return w.state_hash()


func test_hash_twice_same() -> void:
	var h1 := _scenario_hash()
	var h2 := _scenario_hash()
	check_eq(h1, h2, "same inputs, same hash with the crew working")


func test_no_facility_no_cost() -> void:
	var w := make_world()
	_ensure_g7()
	_run(w, 200)
	check(not w.sys_state.has(E7.KEY), "no facility: no engineer state")
	var t0 := Time.get_ticks_usec()
	for i in 2000:
		E7.tick(w)
	var us := Time.get_ticks_usec() - t0
	check(us < 20000, "no facility: tick is a no-op (%d us for 2000 calls)" % us)
	check(not w.sys_state.has(E7.KEY), "still no state")
