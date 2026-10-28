extends "res://tests/test_base.gd"
## G7 PATH7 acceptance (owner notes 13.9c-31 "NO units walk through buildings / walls / other units ... smooth
## movement at all times" and 13.9c-16a "CN APCs: smoother, crisp, realistic driving, not jumpy").
## Counters come from tools/path7_measure.gd (read-only: it replays the entity_layer lerp + motion.gd per frame).
## Thresholds are the measured AFTER values (PATH7 probes .plan/path7_apc.gd / path7_crowd.gd, 2026-10-27):
##   BEFORE (Movement driving the APC on open ground, LP map): 14 heading snaps (max 88 deg / tick), 3 instant
##   0 -> full-speed starts, 13 crab frames (hull up to 66 deg off its travel), 5 jerk frames.
##   AFTER (VehDrive7): 0 / 0 / 0 (max 13 deg) / 0. Facility (LP start + APC flows): 0 inside footprints, 0 body
##   penetration, 0 soldier overlaps, 0 hull overlaps, 0 jumps. These are hard checks; never loosen them.
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Movement = preload("res://sim/systems/movement.gd")
const VehDrive7 = preload("res://sim/systems/veh_drive7.gd")
const M = preload("res://tools/path7_measure.gd")
const APC := "g7_cn_strike_apc"
const CRAB_MAX := 20.0


func _ensure_g7() -> void:
	if Content.unit(APC).is_empty():
		Content._merge_fragment_dir("res://content/g7")


func _step(w: SimWorld) -> void:
	w.step()
	if not SimWorld.SYSTEM_ORDER.has(VehDrive7):
		VehDrive7.tick(w)


## A cleared grass square with an L of walls: the route from A to B has to turn round the wall's end.
func _course() -> Array:
	var w := make_world()
	_ensure_g7()
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(56, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var r := Rect2i(o, Vector2i(n, n))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		if r.has_point(w.cell_of(w.entities[id].pos)):
			w.entities.erase(id)
	w.cache.clear()
	Movement.rebuild_nav(w)
	for y in range(0, 30):
		w.spawn_building("a_wall", 0, o + Vector2i(24, y), true)
	for x in range(24, 40):
		w.spawn_building("a_wall", 0, o + Vector2i(x, 30), true)
	return [w, o]


func _drive(cn: bool, ticks: int = 1400) -> Dictionary:
	var c := _course()
	var w: SimWorld = c[0]
	var o: Vector2i = c[1]
	var id := w.spawn_unit(APC, 0, Vector2(o) + Vector2(8.5, 6.5))
	if cn:
		w.entities[id]["cn_fac"] = 1
	for i in 25:
		_step(w)   # parked a moment (the driver discovers facility APCs every VehDrive7.DISCOVER ticks)
	var goal := Vector2(o) + Vector2(36.5, 22.5)
	w.submit({"type": "move", "issuer": 0, "unit_ids": [id], "target": goal})
	var m := M.new()
	var arrived := -1
	for i in ticks:
		_step(w)
		m.sample(w, [id])
		if arrived < 0 and i > 5 and not bool(w.entities[id].moving):
			arrived = i
			break
	return {"w": w, "id": id, "m": m, "goal": goal, "arrived": arrived, "b": m.by.get("all", M._zero())}


func test_apc_open_ground_turns_on_a_radius() -> void:
	var nat := _drive(false)
	var vd := _drive(true)
	var a: Dictionary = nat.b
	var b: Dictionary = vd.b
	print("PATH7_APC native: %s" % (nat.m as M).report("native"))
	print("PATH7_APC vehdrive: %s" % (vd.m as M).report("vd"))
	check(int(a.snap) > 0, "the course makes Movement snap the heading (scenario exercises corners): %d" % int(a.snap))
	check_eq(int(b.snap), 0, "no heading snap > %.0f deg in one tick" % M.SNAP_DEG)
	check_eq(int(b.start), 0, "no 0 -> full speed start in one tick")
	check_eq(int(b.jump), 0, "no position pop")
	check_eq(int(b.jerk), 0, "no drawn-velocity jerk > %.1f px / frame" % M.JERK_PX)
	check(float(b.crab_max) <= CRAB_MAX, "hull stays within %.0f deg of its travel (max %.1f)" % [CRAB_MAX, float(b.crab_max)])
	check(int(vd.arrived) > 0, "arrived (%d ticks; Movement %d)" % [int(vd.arrived), int(nat.arrived)])
	var e: Dictionary = (vd.w as SimWorld).entities[int(vd.id)]
	check(Vector2(e.pos).distance_to(vd.goal) < 0.01, "stopped exactly on the goal (%s vs %s)" % [str(e.pos), str(vd.goal)])
	check_eq(String(e.order.type), "idle", "order idle on arrival, as Movement")
	check(int(vd.arrived) <= int(float(nat.arrived) * 1.8) + 40, "accel / corner braking costs a heavy APC some time, not a crawl (%d vs %d ticks)" % [int(vd.arrived), int(nat.arrived)])


## PATH7-2: two APCs re-ordered twice, once from a standstill and once while rolling. The windowed before / after run
## caught two defects the one-leg course above never showed: the hull snapped to the new path's first segment when an idle
## APC was captured (Movement had already turned it that tick), and a slow APC chasing a waypoint its turning radius could
## not reach circled it for 360 degrees. Hard checks: the heading never changes by more than the controller's own peak
## turn rate in one tick (turn rate = min(max(v / R_MIN, W_CRAWL), A_TURN / v), peak sqrt(A_TURN / R_MIN) = 1.155 rad/s =
## 3.31 deg per tick, +0.1 for the 1/1024 rad snap; a capture snap shows as tens of degrees, Movement's own 50), the total
## heading travelled stays below 540 deg (measured 389 / 454 over the three legs; a spin adds 360 per loop), both end at
## rest near the last goal.
func test_apc_reorders_no_snap_no_spin() -> void:
	var c := _course()
	var w: SimWorld = c[0]
	var o: Vector2i = c[1]
	var ids := []
	for k in 2:
		var id := w.spawn_unit(APC, 0, Vector2(o) + Vector2(6.5, 6.5 + 3.0 * float(k)))
		w.entities[id]["cn_fac"] = 1
		w.entities[id].facing = 0.0
		ids.append(id)
	for i in 25:
		_step(w)
	var legs := [Vector2(o) + Vector2(20.5, 16.5), Vector2(o) + Vector2(18.5, 38.5), Vector2(o) + Vector2(6.5, 30.5)]
	w.submit({"type": "move", "issuer": 0, "unit_ids": ids, "target": legs[0]})
	var last := {}
	var worst := 0.0
	var tot := {}
	var leg := 0
	var rolling_reorder := false
	var wait_since := -1
	var done := false
	for i in 3000:
		_step(w)
		var moving := false
		for id in ids:
			var e: Dictionary = w.entities[id]
			if last.has(id):
				var dh := absf(rad_to_deg(wrapf(float(e.facing) - float(last[id]), -PI, PI)))
				worst = maxf(worst, dh)
				tot[id] = float(tot.get(id, 0.0)) + dh
			last[id] = float(e.facing)
			moving = moving or bool(e.moving)
		var lead: Vector2 = w.entities[ids[0]].pos
		if leg == 0 and lead.distance_to(legs[0]) < 7.0:
			leg = 1
			rolling_reorder = bool(w.entities[ids[0]].moving)
			w.submit({"type": "move", "issuer": 0, "unit_ids": ids, "target": legs[1]})
		elif leg == 1 and not moving and i > 60:
			if wait_since < 0:
				wait_since = i
			if i - wait_since > 20:
				leg = 2
				w.submit({"type": "move", "issuer": 0, "unit_ids": ids, "target": legs[2]})
		elif leg == 2 and not moving and i > wait_since + 60 and wait_since > 0:
			done = true
			break
	print("PATH7_REORDER worst heading step %.2f deg/tick, total heading travelled %s deg, done %s at tick %d" % [worst, str(tot), str(done), w.tick])
	check(rolling_reorder, "the second order came while the lead APC was rolling")
	check(done, "both APCs came to rest after the third leg")
	var cap := rad_to_deg(sqrt(VehDrive7.A_TURN / VehDrive7.R_MIN) * SimWorld.DT) + 0.1
	check(worst <= cap, "heading never changes by more than %.2f deg in one tick, also at capture from a standstill (worst %.2f)" % [cap, worst])
	for id in ids:
		check(float(tot.get(id, 0.0)) <= 540.0, "APC %d does not spin: total heading travelled %.0f deg <= 540" % [id, float(tot.get(id, 0.0))])
		check(Vector2(w.entities[id].pos).distance_to(legs[2]) < 9.0, "APC %d ends near the last goal (%s)" % [id, str(w.entities[id].pos)])


func test_player_order_wins_at_once() -> void:
	var c := _course()
	var w: SimWorld = c[0]
	var o: Vector2i = c[1]
	var id := w.spawn_unit(APC, 0, Vector2(o) + Vector2(8.5, 6.5))
	w.entities[id]["cn_fac"] = 1
	for i in 25:
		_step(w)
	w.submit({"type": "move", "issuer": 0, "unit_ids": [id], "target": Vector2(o) + Vector2(20.5, 40.5)})
	for i in 60:
		_step(w)
	var S: Dictionary = w.sys_state.get(VehDrive7.KEY, {})
	check((S.get("v", {}) as Dictionary).has(str(id)), "the driver has the APC")
	w.submit({"type": "stop", "issuer": 0, "unit_ids": [id]})
	_step(w)
	check(not bool(w.entities[id].moving), "a stop order stops it on the next tick")
	check(not (S.get("v", {}) as Dictionary).has(str(id)), "and releases it")
	var g2 := Vector2(o) + Vector2(4.5, 40.5)
	w.submit({"type": "move", "issuer": 0, "unit_ids": [id], "target": g2})
	for i in 900:
		_step(w)
		if i > 5 and not bool(w.entities[id].moving):
			break
	check(Vector2(w.entities[id].pos).distance_to(g2) < 0.01, "a fresh order is driven to its own goal (%s)" % str(w.entities[id].pos))


func test_hash_twice_same_and_save_load() -> void:
	var h := []
	for k in 2:
		var r := _drive(true, 300)
		h.append((r.w as SimWorld).state_hash())
	check_eq(String(h[0]), String(h[1]), "same course twice -> same hash")
	var c := _course()
	var w: SimWorld = c[0]
	var o: Vector2i = c[1]
	var id := w.spawn_unit(APC, 0, Vector2(o) + Vector2(8.5, 6.5))
	w.entities[id]["cn_fac"] = 1
	w.submit({"type": "move", "issuer": 0, "unit_ids": [id], "target": Vector2(o) + Vector2(36.5, 22.5)})
	for i in 120:
		_step(w)
	var b := SimWorld.from_dict(w.to_dict().duplicate(true))
	for i in 200:
		_step(w)
		_step(b)
	check_eq(String(b.state_hash()), String(w.state_hash()), "save / load mid-drive -> same hash 200 ticks later")


func test_no_cn_vehicle_no_state() -> void:
	var c := _course()
	var w: SimWorld = c[0]
	var o: Vector2i = c[1]
	var id := w.spawn_unit(APC, 0, Vector2(o) + Vector2(8.5, 6.5))
	w.submit({"type": "move", "issuer": 0, "unit_ids": [id], "target": Vector2(o) + Vector2(36.5, 22.5)})
	for i in 100:
		_step(w)
	check(not w.sys_state.has(VehDrive7.KEY), "a match without a facility APC never creates driver state")


## The real Last Protocol map: two facility APCs ordered out to open ground, two to the bays; Sentinels, engineers,
## bearers and the base garrison going about their business. APCs: smooth inside (FacDrive7) and outside (VehDrive7).
## Everyone in and around the compound: nobody inside a footprint, no body into a wall, no overlaps, no pops.
func test_last_protocol_facility() -> void:
	if not preload("res://sim/map_gen.gd").has_map("last_protocol"):
		check(true, "last_protocol map not registered: skipped")
		return
	var w := SimWorld.new_match(LastProtocol.make_config(77, "last_protocol"))
	w.run_ticks(20)
	var fids := CnFacility.facilities(w, 0)
	if not check(not fids.is_empty(), "the facility exists"):
		return
	var cr: Rect2 = CnFacility.compound_rect(CnFacility.fac(w, int(fids[0])))
	var apcs := []
	for e in w.entities.values():
		if e.kind == "unit" and int(e.get("cn_fac", 0)) != 0 and Movement.udef(String(e.def)).mc == "vehicle" and int(e.owner) == 0:
			apcs.append(int(e.id))
	apcs.sort()
	if not check(apcs.size() >= 4, "facility APCs (%d)" % apcs.size()):
		return
	var out := apcs.slice(0, 2)
	w.submit({"type": "fd7_go", "issuer": 0, "ids": out, "to": "point", "target": Vector2(cr.get_center().x, cr.end.y + 30.0)})
	w.submit({"type": "fd7_go", "issuer": 0, "ids": apcs.slice(4, 6), "to": "bays"})
	var m := M.new()
	m.stride = 5
	var ma := M.new()
	var tag := func(e): return "facility" if cr.grow(2.0).has_point(e.pos) else "map"
	var tg2 := func(e): return "inside" if cr.grow(1.0).has_point(e.pos) else "outside"
	for i in 800:
		_step(w)
		ma.sample(w, out, tg2)
		if i % 5 == 0:
			m.crowd_sample(w, tag)
	print("PATH7_LP %s" % ma.report("apc"))
	print("PATH7_LP %s" % m.crowd_report("crowd"))
	for x in ma.ex:
		print("PATH7_LP_EX ", x)
	var ins: Dictionary = ma.by.get("inside", M._zero())
	var ous: Dictionary = ma.by.get("outside", M._zero())
	check(int(ous.mv_ticks) >= 200, "the APCs drove out onto open ground (%d moving ticks outside)" % int(ous.mv_ticks))
	for b in [ins, ous]:
		check_eq(int(b.jump), 0, "APC: no position pop")
		check_eq(int(b.snap), 0, "APC: no heading snap")
		check_eq(int(b.jerk), 0, "APC: no drawn jerk")
		check(float(b.crab_max) <= CRAB_MAX, "APC: hull within %.0f deg of its travel (%.1f)" % [CRAB_MAX, float(b.crab_max)])
	check_eq(int(ous.start), 0, "APC: no instant start on open ground")
	var f: Dictionary = m.cw.get("facility", M._czero())
	check(int(f.unit_ticks) > 1000, "facility units sampled (%d)" % int(f.unit_ticks))
	check_eq(int(f.in_fp), 0, "facility: nobody inside a building / wall / gate footprint")
	check_eq(int(f.pen), 0, "facility: no body reaching into a footprint (> %.2f tiles)" % M.PEN_TOL)
	check_eq(int(f.inf_ov), 0, "facility: no two soldiers closer than %.2f tiles" % M.INF_GAP)
	check_eq(int(f.veh_ov), 0, "facility: no hull overlapping another unit")
	check_eq(int(f.jump), 0, "facility: no position pop")
	var mp: Dictionary = m.cw.get("map", M._czero())
	check_eq(int(mp.in_fp), 0, "map: nobody inside a building / wall / gate footprint")
	check_eq(int(mp.jump), 0, "map: no position pop")
