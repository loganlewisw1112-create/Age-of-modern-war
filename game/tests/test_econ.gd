extends "res://tests/test_base.gd"
## Economy / Construction / Production / Gather (agent A). Tests assert outcomes with generous
## tick budgets, so they pass with the stub movement and with real pathing.


# ---------------------------------------------------------------- helpers
func _hq(w: SimWorld, fid: int = 0) -> Dictionary:
	return w.buildings_of(fid, "hq")[0]


func _engineers(w: SimWorld, fid: int = 0) -> Array:
	var out := []
	for e in w.units_of(fid):
		if e.def == "engineer":
			out.append(int(e.id))
	return out


## First legal origin for def_id around the HQ (spiral outward), or (-1,-1).
func _site(w: SimWorld, fid: int, def_id: String) -> Vector2i:
	var c := Vector2i(_hq(w, fid).pos)
	for r in range(3, 15):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var o := c + Vector2i(dx, dy)
				if w.in_bounds(o) and Construction.placement_error(w, fid, def_id, o) == "":
					return o
	return Vector2i(-1, -1)


const Construction = preload("res://sim/systems/construction.gd")


## Steps until cond.call() is true or max_ticks passes. Events are appended to log[type] (Array).
func _run_until(w: SimWorld, max_ticks: int, cond: Callable, log: Dictionary = {}) -> bool:
	for i in max_ticks:
		w.step()
		for ev in w.events:
			if not log.has(ev.type):
				log[ev.type] = []
			log[ev.type].append(ev)
		if cond.call():
			return true
	return false


func _count(log: Dictionary, type: String) -> int:
	return log.get(type, []).size()


func _build_ready(w: SimWorld, fid: int, def_id: String) -> int:
	var o := _site(w, fid, def_id)
	check(o != Vector2i(-1, -1), "no site for " + def_id)
	return w.spawn_building(def_id, fid, o, true)


func _journal_sum(f: Dictionary, key: String) -> int:
	var s := 0
	for entry in f.journal:
		s += int(entry.get(key, 0))
	return s


func _balance(f: Dictionary) -> Dictionary:
	return {"credits": int(f.credits), "salvage": int(f.stock.salvage), "ore": int(f.stock.ore)}


# ---------------------------------------------------------------- Economy
func test_power_pop_and_stipend() -> void:
	var w := make_world()
	var f: Dictionary = w.factions[0]
	check_eq(int(f.power_prod), 30, "HQ produces 30 power")
	check_eq(int(f.power_use), 0, "no consumers yet")
	check_eq(int(f.pop), 6, "6 start units")
	check_eq(int(f.pop_cap), 20, "HQ pop cap")
	var c0 := int(f.credits)
	w.run_ticks(40)
	var stip := int(Content.rules().hq_stipend_credits_per_second)
	check_eq(int(f.credits), c0 + stip * 2, "HQ stipend per second for 2 seconds")
	# unfinished buildings contribute nothing
	var o := _site(w, 0, "generator")
	w.spawn_building("generator", 0, o, false)
	w.step()
	check_eq(int(f.power_prod), 30, "unfinished generator adds no power")
	var o2 := _site(w, 0, "barracks")
	w.spawn_building("barracks", 0, o2, true)
	w.step()
	check_eq(int(f.power_use), 20, "built barracks consumes 20")


# ---------------------------------------------------------------- ECON-01
func test_econ01_double_spend_impossible() -> void:
	var w := make_world()
	var f: Dictionary = w.factions[0]
	var hq := _hq(w)
	var eng_cr := int(Content.production("engineer").cost.credits)
	check(w.spend(0, {"credits": int(f.credits) - eng_cr}, "test_setup"), "setup spend")
	for i in 2:
		var r := w.submit({"type": "queue_unit", "issuer": 0, "building_id": hq.id, "item": "engineer"})
		check(r.ok, "submit")
	w.step()
	var applied := 0
	var rejected := 0
	var reason := ""
	for ev in w.events:
		if ev.type == "CommandApplied":
			applied += 1
		elif ev.type == "CommandRejected":
			rejected += 1
			reason = String(ev.reason)
	check_eq(applied, 1, "exactly one queue command applied")
	check_eq(rejected, 1, "exactly one rejected")
	check(reason.contains("Need") and reason.contains("credits"), "reject reason names the shortfall: " + reason)
	check_eq(hq.queue.size(), 1, "one item queued")
	check_eq(int(f.credits), 0, "credits spent exactly once")


func test_econ01_journal_conservation() -> void:
	var w := make_world()
	var f: Dictionary = w.factions[0]
	var start := _balance(f)
	var eng := _engineers(w)
	var site := _site(w, 0, "barracks")
	w.submit({"type": "build", "issuer": 0, "unit_ids": eng, "def": "barracks", "origin": site})
	w.step()
	var bar: Array = w.buildings_of(0, "barracks")
	check_eq(bar.size(), 1, "barracks foundation placed")
	if bar.is_empty():
		return
	var bid: int = int(bar[0].id)
	check(_run_until(w, 2500, func(): return w.entities[bid].built), "barracks completes")
	do_cmd(w, 0, {"type": "queue_unit", "building_id": bid, "item": "rifle_squad"})
	do_cmd(w, 0, {"type": "queue_unit", "building_id": bid, "item": "recon"})
	do_cmd(w, 0, {"type": "cancel_unit", "building_id": bid, "index": 1})
	var salv: Array = []
	for r in w.entities.values():
		if r.kind == "resource" and r.res == "salvage":
			salv.append(r)
	salv.sort_custom(func(a, b): return Vector2(a.pos).distance_to(_hq(w).pos) < Vector2(b.pos).distance_to(_hq(w).pos))
	do_cmd(w, 0, {"type": "gather", "unit_ids": eng, "target_id": salv[0].id})
	w.run_ticks(900)
	var end := _balance(f)
	for k in ["credits", "salvage", "ore"]:
		check_eq(_journal_sum(f, k), int(end[k]) - int(start[k]), "journal sums equal balance delta for " + k)
	check(f.journal.size() > 5, "journal recorded entries")


# ---------------------------------------------------------------- Gather
func test_gather_cycle_delivers_salvage_and_conserves() -> void:
	var w := make_world()
	var f: Dictionary = w.factions[0]
	var hq := _hq(w)
	var salv: Array = []
	for r in w.entities.values():
		if r.kind == "resource" and r.res == "salvage":
			salv.append(r)
	check(salv.size() > 0, "map has salvage")
	salv.sort_custom(func(a, b): return Vector2(a.pos).distance_to(hq.pos) < Vector2(b.pos).distance_to(hq.pos))
	var total0 := 0
	for r in salv:
		total0 += int(r.amount)
	var s0 := int(f.stock.salvage)
	var eng := _engineers(w)
	var log := {}
	do_cmd(w, 0, {"type": "gather", "unit_ids": eng, "target_id": salv[0].id})
	var delivered := 0
	var rej := rejected_reason(w.events)
	check_eq(rej, "", "gather accepted")
	_run_until(w, 1500, func(): return false, log)
	for ev in log.get("Delivered", []):
		delivered += int(ev.amt)
	check(delivered > 0, "at least one delivery happened (got %d)" % delivered)
	check_eq(int(f.stock.salvage), s0 + delivered, "stock gained exactly the delivered amount")
	var left := 0
	for r in w.entities.values():
		if r.kind == "resource" and r.res == "salvage":
			left += int(r.amount)
	var carried := 0
	for id in eng:
		carried += int(w.entities[id].carry.amt)
	check_eq(total0 - left, delivered + carried, "removed == delivered + carried")


func test_gather_rejects_non_gatherers_and_bad_targets() -> void:
	var w := make_world()
	var recon := 0
	for e in w.units_of(0):
		if e.def == "recon":
			recon = int(e.id)
	var res_id := 0
	for r in w.entities.values():
		if r.kind == "resource":
			res_id = int(r.id)
			break
	var evs := do_cmd(w, 0, {"type": "gather", "unit_ids": [recon], "target_id": res_id})
	check(rejected_reason(evs).contains("work crews"), "recon cannot gather: " + rejected_reason(evs))
	evs = do_cmd(w, 0, {"type": "gather", "unit_ids": _engineers(w), "target_id": _hq(w).id})
	check(rejected_reason(evs).contains("not a resource"), "HQ is not a resource: " + rejected_reason(evs))


func test_gather_depletes_resource_and_destroys_it() -> void:
	var w := make_world()
	var hq := _hq(w)
	var best: Dictionary = {}
	for r in w.entities.values():
		if r.kind == "resource" and (best.is_empty() or Vector2(r.pos).distance_to(hq.pos) < Vector2(best.pos).distance_to(hq.pos)):
			best = r
	best.amount = 12     # small deposit so it depletes quickly
	var rid := int(best.id)
	var rres := String(best.res)
	var f: Dictionary = w.factions[0]
	var r0 := int(f.stock[rres])
	var log := {}
	do_cmd(w, 0, {"type": "gather", "unit_ids": _engineers(w).slice(0, 2), "target_id": rid})
	_run_until(w, 1200, func(): return not w.entities.has(rid), log)
	check(not w.entities.has(rid), "depleted resource entity is destroyed")
	check_eq(_count(log, "ResourceDepleted"), 1, "ResourceDepleted emitted once")
	w.run_ticks(600)
	var carried := 0
	for id in _engineers(w):
		carried += int(w.entities[id].carry.amt)
	check_eq(int(f.stock[rres]) - r0 + carried >= 12, true, "all 12 units end up delivered or carried")


# ---------------------------------------------------------------- Production
func test_econ02_low_power_stall_and_recovery() -> void:
	var w := make_world()
	var f: Dictionary = w.factions[0]
	var b1 := _build_ready(w, 0, "barracks")
	var b2 := _build_ready(w, 0, "barracks")
	w.step()
	check_eq(int(f.power_use), 40, "two barracks use 40")
	check(int(f.power_use) > int(f.power_prod), "deficit")
	var log := {}
	for ev in do_cmd(w, 0, {"type": "queue_unit", "building_id": b1, "item": "rifle_squad"}):
		log[ev.type] = log.get(ev.type, []) + [ev]
	_run_until(w, 15, func(): return false, log)
	var bar: Dictionary = w.entities[b1]
	check_eq(String(bar.status), "LOW_POWER", "blocked reason shown on building")
	check_eq(float(bar.queue[0].progress), 0.0, "no progress while stalled")
	check_eq(_count(log, "ProductionBlocked"), 1, "ProductionBlocked emitted once, not every tick")
	check_eq(w.units_of(0).size(), 6, "no unit produced during stall")
	# build a generator: 100 power
	var site := _site(w, 0, "generator")
	var evs := do_cmd(w, 0, {"type": "build", "unit_ids": _engineers(w), "def": "generator", "origin": site})
	check_eq(rejected_reason(evs), "", "generator build accepted")
	var gens: Array = w.buildings_of(0, "generator")
	check_eq(gens.size(), 1, "generator foundation")
	if gens.is_empty():
		return
	var gid: int = int(gens[0].id)
	check(_run_until(w, 2500, func(): return w.entities[gid].built, log), "generator completes")
	check(_run_until(w, 700, func(): return bar.queue.is_empty(), log), "squad completes after power returns")
	var riflemen := 0
	for u in w.units_of(0):
		if u.def == "rifleman":
			riflemen += 1
	check_eq(riflemen, 4, "exactly one squad (4 riflemen) per paid item")
	check_eq(_count(log, "ProductionCompleted"), 1, "ProductionCompleted once")
	check_eq(String(bar.status), "", "status cleared after recovery")


func test_supply_cap_blocks_and_recovers() -> void:
	var w := make_world()
	var f: Dictionary = w.factions[0]
	var hq := _hq(w)
	var fillers := []
	for i in 14:
		fillers.append(w.spawn_unit("rifleman", 0, Vector2(hq.pos) + Vector2(5.0 + i * 0.1, 0.0)))
	w.step()
	check_eq(int(f.pop), 20, "pop at cap")
	var log := {}
	for ev in do_cmd(w, 0, {"type": "queue_unit", "building_id": hq.id, "item": "engineer"}):
		log[ev.type] = log.get(ev.type, []) + [ev]
	_run_until(w, 10, func(): return false, log)
	check_eq(String(hq.status), "SUPPLY_CAP", "supply cap reason")
	check_eq(float(hq.queue[0].progress), 0.0, "no progress while capped")
	check_eq(_count(log, "ProductionBlocked"), 1, "blocked event once")
	w.destroy(fillers[0], "test")
	check(_run_until(w, 400, func(): return hq.queue.is_empty(), log), "item completes once supply frees up")
	check_eq(_engineers(w).size(), 6, "exactly one new engineer (5 + 1)")
	check_eq(String(hq.status), "", "status clears")


func test_cancel_unit_exact_refund() -> void:
	var w := make_world()
	var f: Dictionary = w.factions[0]
	var bid := _build_ready(w, 0, "barracks")
	var before := _balance(f)
	do_cmd(w, 0, {"type": "queue_unit", "building_id": bid, "item": "rifle_squad"})
	do_cmd(w, 0, {"type": "queue_unit", "building_id": bid, "item": "at_team"})
	var mid := _balance(f)
	var c_rs: Dictionary = Content.production("rifle_squad").cost
	var c_at: Dictionary = Content.production("at_team").cost
	check_eq(int(before.credits) - int(mid.credits), int(c_rs.credits) + int(c_at.credits), "both items paid at queue time")
	check_eq(int(before.salvage) - int(mid.salvage), int(c_rs.salvage) + int(c_at.salvage), "salvage paid at queue time")
	var evs := do_cmd(w, 0, {"type": "cancel_unit", "building_id": bid, "index": 1})
	check_eq(rejected_reason(evs), "", "cancel accepted")
	evs = do_cmd(w, 0, {"type": "cancel_unit", "building_id": bid, "index": 0})
	check_eq(rejected_reason(evs), "", "cancel accepted")
	check_eq(_balance(f), before, "exact refund of everything paid")
	check_eq(w.entities[bid].queue.size(), 0, "queue empty")
	evs = do_cmd(w, 0, {"type": "cancel_unit", "building_id": bid, "index": 0})
	check(rejected_reason(evs).contains("no queued item"), "cancelling an empty slot is rejected")
	w.run_ticks(60)
	var riflemen := 0
	for u in w.units_of(0):
		if u.def == "rifleman" or u.def == "at_gunner":
			riflemen += 1
	check_eq(riflemen, 0, "cancelled items never spawn")


func test_queue_validation() -> void:
	var w := make_world()
	var hq := _hq(w)
	var evs := do_cmd(w, 0, {"type": "queue_unit", "building_id": hq.id, "item": "rifle_squad"})
	check(rejected_reason(evs).contains("cannot produce"), "HQ cannot make rifle squads: " + rejected_reason(evs))
	evs = do_cmd(w, 0, {"type": "queue_unit", "building_id": hq.id, "item": "nonsense"})
	check(rejected_reason(evs).contains("Unknown"), "unknown item")
	for i in 5:
		evs = do_cmd(w, 0, {"type": "queue_unit", "building_id": hq.id, "item": "engineer"})
		check_eq(rejected_reason(evs), "", "queue slot %d accepted" % i)
	evs = do_cmd(w, 0, {"type": "queue_unit", "building_id": hq.id, "item": "engineer"})
	check(rejected_reason(evs).contains("full"), "6th item rejected: " + rejected_reason(evs))
	# unfinished building cannot produce
	var o := _site(w, 0, "barracks")
	var raw := w.spawn_building("barracks", 0, o, false)
	evs = do_cmd(w, 0, {"type": "queue_unit", "building_id": raw, "item": "recon"})
	check(rejected_reason(evs).contains("under construction"), "foundation cannot queue")
	# set_rally
	evs = do_cmd(w, 0, {"type": "set_rally", "building_id": hq.id, "target": Vector2(40.5, 40.5)})
	check_eq(rejected_reason(evs), "", "set_rally ok")
	check_eq(Vector2(hq.rally), Vector2(40.5, 40.5), "rally stored")
	evs = do_cmd(w, 0, {"type": "set_rally", "building_id": hq.id, "target": Vector2(-5, 3)})
	check(rejected_reason(evs).contains("outside"), "rally outside map rejected")


# ---------------------------------------------------------------- Construction
func test_cancel_building_refund_rule() -> void:
	var w := make_world()
	var f: Dictionary = w.factions[0]
	var eng := _engineers(w).slice(0, 1)
	var site := _site(w, 0, "generator")
	var before := _balance(f)
	do_cmd(w, 0, {"type": "build", "unit_ids": eng, "def": "generator", "origin": site})
	var after := _balance(f)
	var c_gen: Dictionary = Content.building("generator").cost
	check_eq(int(before.credits) - int(after.credits), int(c_gen.credits), "full cost spent at placement")
	check_eq(int(before.salvage) - int(after.salvage), int(c_gen.salvage), "salvage spent at placement")
	var gen: Dictionary = w.buildings_of(0, "generator")[0]
	var gid := int(gen.id)
	var evs := do_cmd(w, 0, {"type": "cancel_building", "building_id": gid})
	check_eq(rejected_reason(evs), "", "cancel accepted")
	check_eq(_balance(f), before, "progress < 5% refunds 100%")
	check(not w.entities.has(gid), "foundation removed")
	var wrecks := 0
	for e in w.entities.values():
		if e.kind == "wreck":
			wrecks += 1
	check_eq(wrecks, 0, "no wreck left by a cancelled foundation")
	# the footprint is free again
	check_eq(Construction.placement_error(w, 0, "generator", site), "", "site free after cancel")
	# 50% rule
	do_cmd(w, 0, {"type": "build", "unit_ids": eng, "def": "generator", "origin": site})
	var gen2: Dictionary = w.buildings_of(0, "generator")[0]
	gen2.progress = 0.5
	var mid := _balance(f)
	do_cmd(w, 0, {"type": "cancel_building", "building_id": int(gen2.id)})
	var fin := _balance(f)
	check_eq(int(fin.credits) - int(mid.credits), int(c_gen.credits) / 2, "progress >= 5% refunds 50% credits")
	check_eq(int(fin.salvage) - int(mid.salvage), int(c_gen.salvage) / 2, "progress >= 5% refunds 50% salvage")
	# a completed building cannot be cancelled
	var done := _build_ready(w, 0, "depot")
	evs = do_cmd(w, 0, {"type": "cancel_building", "building_id": done})
	check(rejected_reason(evs).contains("already complete"), "completed building not cancellable")


func test_build01_placement_errors_distinct() -> void:
	var w := make_world()
	var hq := _hq(w)
	var reasons := {}
	# missing prerequisite
	var site := _site(w, 0, "generator")
	var e1 := Construction.placement_error(w, 0, "motor_pool", site)
	check(e1.contains("Requires"), "prereq: " + e1)
	reasons["prereq"] = e1
	# overlap with the HQ
	var e2 := Construction.placement_error(w, 0, "generator", hq.cell)
	check(e2.contains("another building"), "overlap: " + e2)
	reasons["overlap"] = e2
	# water
	var wo := Vector2i(-1, -1)
	for y in range(1, 94):
		for x in range(1, 94):
			var all_water := true
			for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				if w.terrain_at(Vector2i(x, y) + d) != Terrain.WATER:
					all_water = false
			if all_water and wo == Vector2i(-1, -1):
				wo = Vector2i(x, y)
	check(wo != Vector2i(-1, -1), "map has a 2x2 water patch")
	var e3 := Construction.placement_error(w, 0, "generator", wo)
	check(e3.contains("water"), "water: " + e3)
	reasons["water"] = e3
	# unexplored (manually zero an explored flag; fog stub is all-explored)
	var ex: PackedByteArray = w.fog[0].explored
	var idx := (site.y + 1) * int(w.map.w) + site.x + 1
	var saved := ex[idx]
	ex[idx] = 0
	w.fog[0].explored = ex
	var e4 := Construction.placement_error(w, 0, "generator", site)
	check(e4.contains("explored"), "unexplored: " + e4)
	reasons["fog"] = e4
	var prev := w.preview_command({"type": "build", "issuer": 0, "unit_ids": _engineers(w), "def": "generator", "origin": site})
	check_eq(prev, e4, "preview_command surfaces the same reason")
	ex[idx] = saved
	w.fog[0].explored = ex
	check_eq(Construction.placement_error(w, 0, "generator", site), "", "legal again once explored")
	# too far from any own building
	var far := Vector2i(-1, -1)
	for y in range(1, 94):
		for x in range(1, 94):
			if far != Vector2i(-1, -1):
				break
			var o := Vector2i(x, y)
			if (Vector2(o) + Vector2(1, 1)).distance_to(hq.pos) > 26.0:
				var ok := true
				for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
					if not Terrain.buildable(w.terrain_at(o + d)):
						ok = false
				if ok:
					far = o
	check(far != Vector2i(-1, -1), "found a far buildable site")
	# Real fog only explores sight circles; mark the map explored so the RANGE rule is what fires.
	var all_ex: PackedByteArray = w.fog[0].explored
	all_ex.fill(1)
	w.fog[0].explored = all_ex
	var e5 := Construction.placement_error(w, 0, "generator", far)
	check(e5.contains("Too far") or e5.contains("resource"), "range: " + e5)
	reasons["range"] = e5
	# resource cell
	var e6 := ""
	for r in w.entities.values():
		if r.kind != "resource" or e6 != "":
			continue
		var rc := w.cell_of(r.pos)
		for off in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
			var err := Construction.placement_error(w, 0, "generator", rc + off)
			if err.contains("resource"):
				e6 = err
				break
	check(e6 != "", "a placement over a resource cell reports the resource")
	reasons["resource"] = e6
	# out of the map
	var e7 := Construction.placement_error(w, 0, "generator", Vector2i(-1, -1))
	check(e7.contains("Outside"), "bounds: " + e7)
	reasons["bounds"] = e7
	# not constructible
	var e8 := Construction.placement_error(w, 0, "hq", site)
	check(e8.contains("cannot be constructed"), "hq not buildable: " + e8)
	reasons["hq"] = e8
	var uniq := {}
	for k in reasons:
		uniq[reasons[k]] = true
	check_eq(uniq.size(), reasons.size(), "every placement failure has a distinct reason")
	# a rejected build command must not mutate state
	var c0 := int(w.factions[0].credits)
	var n0 := w.entities.size()
	var evs := do_cmd(w, 0, {"type": "build", "unit_ids": _engineers(w), "def": "generator", "origin": hq.cell})
	check(rejected_reason(evs).contains("another building"), "build over HQ rejected")
	check_eq(int(w.factions[0].credits), c0, "no spend on rejected build")
	check_eq(w.entities.size(), n0, "no entity created on rejected build")


func test_build_requires_affordability_and_builders() -> void:
	var w := make_world()
	var f: Dictionary = w.factions[0]
	var site := _site(w, 0, "generator")
	var recon := 0
	for e in w.units_of(0):
		if e.def == "recon":
			recon = int(e.id)
	var evs := do_cmd(w, 0, {"type": "build", "unit_ids": [recon], "def": "generator", "origin": site})
	check(rejected_reason(evs).contains("engineers"), "recon cannot build: " + rejected_reason(evs))
	check(w.spend(0, {"credits": int(f.credits)}, "test_setup"), "drain credits")
	evs = do_cmd(w, 0, {"type": "build", "unit_ids": _engineers(w), "def": "generator", "origin": site})
	check(rejected_reason(evs).contains("Need"), "unaffordable: " + rejected_reason(evs))
	check_eq(w.buildings_of(0, "generator").size(), 0, "no foundation when unaffordable")


func test_happy_path_barracks_then_rifle_squad() -> void:
	var w := make_world()
	var f: Dictionary = w.factions[0]
	var eng := _engineers(w)
	var site := _site(w, 0, "barracks")
	var log := {}
	var evs := do_cmd(w, 0, {"type": "build", "unit_ids": eng, "def": "barracks", "origin": site})
	check_eq(rejected_reason(evs), "", "build accepted")
	var bar: Dictionary = w.buildings_of(0, "barracks")[0]
	var bid := int(bar.id)
	check_eq(bool(bar.built), false, "starts as a foundation")
	check(float(bar.hp) < float(bar.max_hp), "foundation has reduced hp")
	check_eq(int(bar.owner), 0, "owned by builder")
	var hp0 := float(bar.hp)
	check(_run_until(w, 3000, func(): return w.entities[bid].built, log), "barracks completes with 5 engineers")
	check_eq(_count(log, "ConstructionCompleted"), 1, "ConstructionCompleted once")
	check_eq(int(f.stats.built), 1, "stats.built")
	check(float(bar.hp) > hp0, "hp rose during construction")
	check_eq(float(bar.hp), float(bar.max_hp), "full hp when complete")
	w.run_ticks(5)
	for id in eng:
		check_eq(String(w.entities[id].order.type), "idle", "engineer released after completion")
	# production
	evs = do_cmd(w, 0, {"type": "queue_unit", "building_id": bid, "item": "rifle_squad"})
	check_eq(rejected_reason(evs), "", "queue accepted")
	check(_run_until(w, 800, func(): return _count(log, "ProductionCompleted") >= 1, log), "squad completes")
	var squads := {}
	var riflemen := 0
	for u in w.units_of(0):
		if u.def == "rifleman":
			riflemen += 1
			squads[int(u.squad)] = true
	check_eq(riflemen, 4, "4 riflemen spawned")
	check_eq(squads.size(), 1, "one shared squad id")
	check(not squads.has(-1), "squad id assigned")
	check_eq(int(f.stats.trained), 4, "stats.trained counts each unit")
	var ev: Dictionary = log.ProductionCompleted[0]
	check_eq(ev.unit_ids.size(), 4, "ProductionCompleted lists the 4 units")
	check_eq(int(f.pop), 10, "pop after squad")
	# spawned units start apart from each other
	var pts := []
	for u in w.units_of(0):
		if u.def == "rifleman":
			pts.append(Vector2(u.pos))
	var min_d := 999.0
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			min_d = minf(min_d, pts[i].distance_to(pts[j]))
	check(min_d >= 0.5, "squad members are spread out (min distance %.2f)" % min_d)


func test_assist_build_speeds_up_construction() -> void:
	var w := make_world()
	var eng := _engineers(w)
	var site := _site(w, 0, "depot")
	do_cmd(w, 0, {"type": "build", "unit_ids": [eng[0]], "def": "depot", "origin": site})
	var dep: Dictionary = w.buildings_of(0, "depot")[0]
	var did := int(dep.id)
	var evs := do_cmd(w, 0, {"type": "assist_build", "unit_ids": eng.slice(1, 3), "target_id": did})
	check_eq(rejected_reason(evs), "", "assist accepted")
	for id in eng.slice(1, 3):
		check_eq(String(w.entities[id].order.type), "build", "assisting engineer has build order")
	check(_run_until(w, 3000, func(): return w.entities[did].built), "depot completes")
	evs = do_cmd(w, 0, {"type": "assist_build", "unit_ids": [eng[0]], "target_id": did})
	check(rejected_reason(evs).contains("already complete"), "cannot assist a finished building")
