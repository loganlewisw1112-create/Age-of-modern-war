extends "res://tests/test_base.gd"
## G7 acceptance (owner: SUPPLY8). G7_REFERENCE 13.9c-48: magazine / ammo + fuel bay card and the AIRDROP RETRIEVAL OP.
## order -> pod lands 4-6 tiles out in open ground -> 4 engineers + carrier + 2x7 GO teams dispatched -> retrieved ->
## stock added -> carrier parked in its garage; one at a time; cooldown; refused reasons; failed op = free retry;
## save / load mid-op exact; same seed same hash; priority + ammo mix options.

const Supply8 = preload("res://sim/systems/supply8.gd")
const S7 = preload("res://sim/systems/sentinels7.gd")
const E7 = preload("res://sim/systems/engineer7.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Movement = preload("res://sim/systems/movement.gd")

static var _base_dict: Dictionary = {}


func _ensure_g7() -> void:
	if Content.unit("g8_cargo_carrier").is_empty() or Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()


func _step(w: SimWorld) -> void:
	w.step()
	if not SimWorld.SYSTEM_ORDER.has(Supply8):
		Supply8.tick(w)


## A world with one raised facility (side 0, full Sentinel watch + crew) and its supply record ready.
func _world() -> SimWorld:
	if _base_dict.is_empty():
		var w := make_world()
		_ensure_g7()
		w.ai_state = {}
		var mw := int(w.map.w)
		var mh := int(w.map.h)
		var o := Vector2i(mw / 2 - 30, mh / 2 - 30)
		var r := Rect2i(o, Vector2i(60, 60))
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
		w.factions[0].credits = 5000
		var off: Array = CnFacility.conf().core_offset
		w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
		for i in 600:
			_step(w)
			if not _fac(w).is_empty() and w.tick > 200:
				break
		_base_dict = w.to_dict()
	_ensure_g7()
	return SimWorld.from_dict(_base_dict.duplicate(true))


func _fac(w: SimWorld) -> Dictionary:
	var l := Supply8.facs_of(w, 0)
	return Supply8.rec(w, int(l[0])) if not l.is_empty() else {}


func _order(w: SimWorld) -> String:
	var Rf := _fac(w)
	var cmd := {"type": "sup8_order", "issuer": 0, "building_id": int(Rf.mag)}
	var why := Supply8.validate_command(w, cmd)
	if why == "":
		Supply8.apply_command(w, cmd)
	return why


func _until(w: SimWorld, mx: int, cond: Callable) -> int:
	for i in mx:
		_step(w)
		if cond.call(w):
			return i + 1
	return -1


func _ev_until(w: SimWorld, mx: int, ty: String) -> Dictionary:
	for i in mx:
		_step(w)
		for ev in w.events:
			if String(ev.type) == ty:
				return ev.data if ev.has("data") else ev
	return {}


func test_garage_carrier_and_crew_ready() -> void:
	var w := _world()
	var Rf := _fac(w)
	if not check(not Rf.is_empty(), "supply record for the facility"):
		return
	check(w.entities.has(int(Rf.gar)) and String(w.entities[int(Rf.gar)].def) == "cn_carrier_garage", "carrier garage built")
	check(not w.entities.has(int(Rf.car)) and not (Rf.stored as Dictionary).is_empty(), "carrier parked inside its garage")
	var F := CnFacility.fac(w, int(Rf.fac))
	var gc := Vector2(w.entities[int(Rf.gar)].cell) + Vector2(0.5, 0.5)
	for r in Supply8._rects_of(F):
		check(not (r as Rect2).has_point(gc), "garage off every zone / lane / garage / approach (%s)" % str(r))
	check(Supply8._lane_cell(F, Vector2i(Vector2(Rf.door).floor())), "garage door opens onto a lane")
	check(gc.distance_to(CnFacility.zone(F, "magazine").get_center()) < 6.0, "garage beside the magazine (%.1f)" % gc.distance_to(CnFacility.zone(F, "magazine").get_center()))
	check(E7.engineers_of(w, int(Rf.fac)).size() >= 4, "crew topped up to 4 engineers")


func test_full_retrieval_op() -> void:
	var w := _world()
	var Rf := _fac(w)
	var fac := int(Rf.fac)
	var F := CnFacility.fac(w, fac)
	var cr0 := int(w.factions[0].credits)
	var am0 := int(w.factions[0].stock.ammo)
	var fu0 := int(w.factions[0].stock.fuel)
	if not check_eq(_order(w), "", "order accepted"):
		return
	check_eq(int(w.factions[0].credits), cr0 - 900, "delivery paid")
	var op: Dictionary = Rf.op
	check_eq((op.go as Array).size(), 14, "2 x 7 GO team Sentinels dispatched")
	check_eq((op.eng as Array).size(), 4, "4 Facility Engineers dispatched")
	var spot: Vector2 = op.spot
	var g := CnFacility.zone(F, "gate_outer")
	var dist := spot.y - g.end.y
	check(dist >= 3.5 and dist <= 6.0, "pod 4-6 tiles outside the gate (%.1f)" % dist)
	var ap: Array = CnFacility.conf().approach
	var apr := Rect2(Vector2(CnFacility.origin(F)) + Vector2(float(ap[0]), float(ap[1])), Vector2(float(ap[2]), float(ap[3])))
	check(not apr.has_point(spot), "pod never on the approach")
	var ci := w.cell_of(spot)
	check(int(w.map.terrain[ci.y * int(w.map.w) + ci.x]) != Terrain.ROAD, "pod not on a road")
	# GO teams move out first (carrier still parked while the pod falls)
	var landed := _ev_until(w, 400, "Supply8PodLanded")
	check(not landed.is_empty(), "pod landed")
	check(not w.entities.has(int(Rf.car)), "carrier waits in the garage until the pod is secured")
	var t_out := _until(w, 1200, func(ww): return String(Rf.op.get("ph", "")) == "out")
	check(t_out > 0, "GO teams secured the pod, carrier rolled out")
	var inpos := int(Rf.op.get("inpos", 0))
	check(inpos >= 7, "GO teams in defensive positions around the pod (%d)" % inpos)
	check(w.entities.has(int(Rf.car)), "carrier out of its garage")
	var t_load := _until(w, 2400, func(ww): return String(Rf.op.get("ph", "")) == "load")
	check(t_load > 0, "carrier + engineers loading the pod")
	var t_ret := _until(w, 600, func(ww): return String(Rf.op.get("ph", "")) == "return")
	check(t_ret > 0, "pod loaded, returning under escort")
	var t_done := _until(w, 3000, func(ww): return (Rf.op as Dictionary).is_empty())
	check(t_done > 0, "op finished")
	check_eq(String(Rf.last), "delivered", "delivered")
	check_eq(int(w.factions[0].stock.ammo) - am0 >= 600, true, "ammo stock added (%d)" % (int(w.factions[0].stock.ammo) - am0))
	check_eq(int(w.factions[0].stock.fuel) - fu0 >= 400 - 200, true, "fuel stock added")
	check(not w.entities.has(int(Rf.car)) and not (Rf.stored as Dictionary).is_empty(), "carrier parked in its garage")
	check((Supply8.state(w).m as Dictionary).is_empty(), "every GO man and engineer released")
	var back := 0
	for uid in op.go:
		if String(S7.job_of(w, int(uid)).get("j", "")).begins_with("sup8:"):
			back += 1
	check_eq(back, 0, "GO teams back on the watch")


func test_one_at_a_time_cooldown_and_reasons() -> void:
	var w := _world()
	var Rf := _fac(w)
	check_eq(_order(w), "", "first order")
	check_eq(_order(w), "A retrieval is already running (one drop at a time).", "one drop at a time")
	Supply8._end(w, Supply8.state(w), Rf, true, "test")
	check(_order(w).begins_with("Cooldown"), "cooldown after an op")
	Rf.cd = w.tick
	w.factions[0].credits = 10
	check_eq(_order(w), "Needs 900 credits.", "credits reason")
	w.factions[0].credits = 5000
	for uid in S7.sentinels_of(w, 0):
		if int(uid) % 2 == 0 or true:
			w.entities.erase(int(uid))
	w.cache.clear()
	check(_order(w).begins_with("Needs 14 Sentinels"), "GO team reason: %s" % _order(w))
	var w2 := make_world()
	check_eq(Supply8.validate_command(w2, {"type": "sup8_order", "issuer": 0}), "No magazine of yours.", "no facility")


func test_pod_destroyed_then_free_retry() -> void:
	var w := _world()
	var Rf := _fac(w)
	_order(w)
	var cr := int(w.factions[0].credits)
	_ev_until(w, 400, "Supply8PodLanded")
	w.entities.erase(int(Rf.op.pod))
	w.cache.clear()
	_until(w, 40, func(ww): return (Rf.op as Dictionary).is_empty())
	check_eq(String(Rf.last), "pod destroyed", "op failed with the pod")
	check(bool(Rf.retry), "drop owed")
	check((Supply8.state(w).m as Dictionary).is_empty(), "units released on failure")
	check(_order(w).begins_with("Cooldown"), "retry waits for the cooldown")
	Rf.cd = w.tick
	_until(w, 1200, func(ww): return not (Rf.stored as Dictionary).is_empty())
	var cr2 := int(w.factions[0].credits)
	check_eq(_order(w), "", "retry accepted after the cooldown")
	check_eq(int(w.factions[0].credits), cr2, "retry is free")
	check(cr2 >= cr, "nothing charged in between")


func _run_op(w: SimWorld, n: int) -> void:
	for i in n:
		_step(w)


func test_save_load_mid_op_and_same_hash() -> void:
	var a := _world()
	var b := _world()
	_order(a)
	_order(b)
	_until(a, 1500, func(ww): return String(_fac(ww).op.get("ph", "")) == "out")
	_run_op(b, a.tick - b.tick)
	check_eq(a.state_hash(), b.state_hash(), "same seed + commands = same hash mid-op")
	var c := SimWorld.from_dict(bytes_to_var(var_to_bytes(a.to_dict())))
	check_eq(c.state_hash(), a.state_hash(), "save / load mid-op: same hash")
	_run_op(a, 900)
	_run_op(c, 900)
	check_eq(c.state_hash(), a.state_hash(), "loaded world continues identically")
	check_eq(String(_fac(c).op.get("ph", "done")), String(_fac(a).op.get("ph", "done")), "same op phase after load")


func test_priority_and_mix_options() -> void:
	var w := _world()
	check_eq(Supply8.prio(w, 0, "walls"), 1.0, "no choice: neutral weight")
	check_eq(Supply8.round_share(w, 0, "ap"), -1.0, "no mix set: -1")
	var c := {"type": "sup8_prio", "issuer": 0, "first": "aircraft"}
	check_eq(Supply8.validate_command(w, c), "", "prio ok")
	Supply8.apply_command(w, c)
	check(Supply8.prio(w, 0, "aircraft") > 1.0 and Supply8.prio(w, 0, "walls") == 1.0, "aircraft first")
	check(Supply8.validate_command(w, {"type": "sup8_prio", "issuer": 0, "first": "boats"}) != "", "bad class refused")
	var m := {"type": "sup8_mix", "issuer": 0, "key": "cn", "delta": 10}
	check_eq(Supply8.validate_command(w, m), "", "mix ok")
	Supply8.apply_command(w, m)
	var sd: Dictionary = Supply8.state(w).sides["0"]
	var tot := 0
	for k in Supply8.MIX_KEYS:
		tot += int(sd.mix[k])
	check_eq(tot, 100, "mix totals 100")
	check_eq(int(sd.mix.cn), 25, "counter-nanite share up 10")
	check(absf(Supply8.round_share(w, 0, "cn") - 0.25) < 0.001, "round_share reads the mix")
