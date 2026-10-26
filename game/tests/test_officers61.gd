extends "res://tests/test_base.gd"
## G6.1 OFF61: officers who fight like trained leaders. Battle drills driven through the chain-of-command
## order API (Doctrine.execute_order -> Ops.tick -> Doctrine.drive_orders), on open grass. The ordered
## company is side 1 (FID); enemies are side 0 units placed by each test (the world's AI is off).

const Doctrine = preload("res://sim/ai/doctrine/doctrine.gd")
const D = preload("res://sim/ai/doctrine/doc_util.gd")
const T = preload("res://sim/ai/doctrine/doc_tactical.gd")
const Op = preload("res://sim/ai/doctrine/doc_operational.gd")
const Companies = preload("res://sim/systems/companies.gd")
const Ops = preload("res://sim/systems/ops.gd")
const Garrison = preload("res://sim/systems/garrison.gd")
const Movement = preload("res://sim/systems/movement.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const FID := 1


# ---------------------------------------------------------------- helpers
func _world() -> SimWorld:
	var w := make_world()
	w.ai_state = {}
	var n := int(w.map.w) * int(w.map.h)
	var t: PackedByteArray = w.map.terrain
	for i in n:
		t[i] = Terrain.GRASS
	w.map.terrain = t
	Movement.rebuild_nav(w)
	return w


func _center(w: SimWorld) -> Vector2:
	return Vector2(float(w.map.w), float(w.map.h)) * 0.5


## A company of `plats` platoons (lieutenant + `per` riflemen each) and a captain, registered like ARMY6.
func _company(w: SimWorld, fid: int, at: Vector2, plats: int, per: int) -> Dictionary:
	var cst := Companies.state(w)
	var ost := Ops.state(w)
	var cid := int(cst.next_cid)
	cst.next_cid = cid + 1
	var cap := w.spawn_unit("officer", fid, at + Vector2(-2.0, 0.0))
	w.entities[cap].rank_role = "captain"
	w.entities[cap].company = cid
	var gids := []
	var elements := []
	for k in plats:
		var p0 := at + Vector2(0.0, float(k) * 4.0 - float(plats - 1) * 2.0)
		var lt := w.spawn_unit("officer", fid, p0 + Vector2(-1.0, 0.0))
		var gid := int(ost.next_gid)
		ost.next_gid = gid + 1
		w.entities[lt].rank_role = "lieutenant"
		w.entities[lt].company = cid
		w.entities[lt].platoon = gid
		var mem := []
		for j in per:
			var u := w.spawn_unit("rifleman", fid, p0 + Vector2(float(j / 2), float(j % 2) * 1.5 - 0.75))
			w.entities[u].company = cid
			w.entities[u].platoon = gid
			mem.append(u)
			elements.append({"id": elements.size() + 1, "item": "rifleman", "units": [u], "platoon": gid})
			w.entities[u].element = elements.size()
		ost.groups[gid] = {"id": gid, "owner": fid, "officer": lt, "members": mem, "mission": {}, "phase": "idle",
			"reason": "", "progress": 0.0, "history": [], "phase_tick": w.tick, "last_report": w.tick, "start": 0,
			"losses": 0, "secure_ticks": 0, "resume": "", "result": "", "parent_company": cid}
		gids.append(gid)
	cst.companies[cid] = {"id": cid, "owner": fid, "template": "test", "name": "Test Coy %d" % cid, "size": "company",
		"captain": cap, "platoons": gids, "refill": false, "army": -1, "losses": 0, "elements": elements,
		"next_eid": elements.size() + 1, "confused_until": 0, "hq": -1}
	return cst.companies[cid]


func _order(w: SimWorld, c: Dictionary, typ: String, tgt: Vector2) -> Dictionary:
	return Doctrine.execute_order(w, FID, int(c.id), {"type": typ, "target": tgt})


func _fs(w: SimWorld, c: Dictionary) -> Dictionary:
	return w.sys_state.get("ops", {}).get("orders61", {}).get("%d:c%d" % [FID, int(c.id)], {}).get("fs", {})


func _alive(w: SimWorld, ids: Array) -> Array:
	var out := []
	for id in ids:
		var e = w.entities.get(int(id))
		if e != null and e.kind == "unit":
			out.append(e)
	return out


func _men(w: SimWorld, c: Dictionary) -> Array:
	var ids := []
	for gid in c.platoons:
		ids.append_array(w.sys_state.ops.groups.get(int(gid), {}).get("members", []))
	return _alive(w, ids)


func _officers(w: SimWorld, c: Dictionary) -> Array:
	var ids := [int(c.captain)]
	for gid in c.platoons:
		var g: Dictionary = w.sys_state.ops.groups.get(int(gid), {})
		if not g.is_empty():
			ids.append(int(g.officer))
	return _alive(w, ids)


func _nearest_d(p: Vector2, foes: Array) -> float:
	var best := INF
	for f in foes:
		best = minf(best, p.distance_to(f.pos))
	return best


func _mean_d(us: Array, foes: Array) -> float:
	if us.is_empty() or foes.is_empty():
		return 0.0
	var s := 0.0
	for e in us:
		s += _nearest_d(e.pos, foes)
	return s / float(us.size())


# ---------------------------------------------------------------- tests
## Stack up and breach: before any member reaches the garrisoned building, >= 70% of the platoon
## members are within 4 tiles of the stack point; the stack completes on the ratio, not the timeout.
func test_stack_up_before_breach() -> void:
	var w := _world()
	var hc := _center(w)
	var bid := w.spawn_building("s_garrison_bld", 0, Vector2i(int(hc.x) + 6, int(hc.y) - 1), true)
	var bp: Vector2 = w.entities[bid].pos
	var gu := w.spawn_unit("rifleman", 0, bp + Vector2(0.0, 2.5))
	var why := Garrison.place_inside(w, bid, gu)
	check_eq(why, "", "enemy rifleman garrisons the building")
	var c := _company(w, FID, bp + Vector2(-30.0, 0.0), 2, 5)
	check(bool(_order(w, c, "take", bp).ok), "take order accepted")
	var track := {"sp": null, "ratio_at_go": -1.0, "entered_before": false, "max_before": 0.0}
	for i in 3600:
		w.step()
		var fs := _fs(w, c)
		var sk: Dictionary = fs.get("stack", {})
		var men := _men(w, c)
		if not sk.is_empty() and track.sp == null:
			track.sp = sk.sp
		var entered := false
		for e in men:
			if (e.pos as Vector2).distance_to(bp) <= 2.5:
				entered = true
		if track.sp != null:
			var r := float(D.near(men, track.sp, 4.0).size()) / float(maxi(men.size(), 1))
			if float(track.ratio_at_go) < 0.0:
				track.max_before = maxf(float(track.max_before), r)
				if bool(sk.get("ok", false)):
					track.ratio_at_go = r
			if entered and float(track.ratio_at_go) < 0.0:
				track.entered_before = true
		if float(track.ratio_at_go) >= 0.0 and i > 200:
			break
	check(track.sp != null, "the platoon stacks up beside the strongpoint (stack point %s)" % str(track.sp))
	check(not bool(track.entered_before), "no member reaches the building before the stack is complete")
	check(float(track.ratio_at_go) >= 0.7, "stack complete with >= 70%% within 4 tiles (%.2f, best %.2f)" % [float(track.ratio_at_go), float(track.max_before)])


## Bounding overwatch: while the formation believes it is in contact, the two groups never move at once,
## and the bounds still carry it forward phase line by phase line.
func test_bounding_never_both_moving_in_contact() -> void:
	var w := _world()
	var hc := _center(w)
	var c := _company(w, FID, hc + Vector2(-30.0, 0.0), 2, 4)
	_order(w, c, "take", hc + Vector2(25.0, 0.0))
	var both := 0
	var samples := 0
	var max_li := 0
	for i in 2400:
		var fs := _fs(w, c)
		if not fs.is_empty():
			fs.seen = w.tick  # contact believed all along (no enemy to drill on)
			fs.ccool = w.tick + 10000
		w.step()
		fs = _fs(w, c)
		if String(fs.get("drill", "")) != "bounding" or String(fs.get("phase", "")) != "advance":
			continue
		var form := Doctrine.node_form(w, FID, "c%d" % int(c.id))
		var g := Op.groups(w, FID, form)
		samples += 1
		if Op._moving(g.a) > 0.5 and Op._moving(g.b) > 0.5:
			both += 1
		max_li = maxi(max_li, int(fs.li))
	check(samples > 200, "bounding drill ran (%d samples)" % samples)
	check_eq(both, 0, "never both groups moving while in contact")
	check(max_li >= 2, "bounds advanced through phase lines (reached line %d)" % (max_li + 1))


## React to contact (weak enemy on the route): every member returns fire within 2 s, the leader decides
## by belief (assault: the enemy is weak), and officers stay behind their men.
func test_react_to_contact_and_officers_behind() -> void:
	var w := _world()
	var hc := _center(w)
	var c := _company(w, FID, hc + Vector2(-30.0, 0.0), 2, 5)
	var foes_ids := [w.spawn_unit("rifleman", 0, hc + Vector2(-10.0, -0.5)), w.spawn_unit("rifleman", 0, hc + Vector2(-10.0, 0.8))]
	_order(w, c, "take", hc + Vector2(25.0, 0.0))
	var t0 := -1
	var fired_ok := false
	var engaged := {}
	var dec := ""
	var off_sum := 0.0
	var men_sum := 0.0
	var n := 0
	for i in 2000:
		w.step()
		var fs := _fs(w, c)
		var ct: Dictionary = fs.get("contact", {})
		if t0 < 0 and not ct.is_empty():
			t0 = int(ct.t)
		if t0 >= 0 and w.tick <= t0 + 40:
			for e in _men(w, c) + _officers(w, c):
				if ["attack", "attack_move"].has(String(e.order.get("type", ""))) or int(e.get("target", -1)) >= 0:
					engaged[int(e.id)] = true
		if t0 >= 0 and w.tick == t0 + 40:
			fired_ok = true
			for e in _men(w, c) + _officers(w, c):
				if not engaged.has(int(e.id)):
					fired_ok = false
		if dec == "" and not ct.is_empty() and String(ct.get("dec", "")) != "":
			dec = String(ct.dec)
		var foes := _alive(w, foes_ids)
		if t0 >= 0 and not foes.is_empty() and w.tick <= t0 + 300:
			var om := _mean_d(_officers(w, c), foes)
			var mm := _mean_d(_men(w, c), foes)
			if om > 0.0 and mm > 0.0:
				off_sum += om
				men_sum += mm
				n += 1
		if t0 >= 0 and w.tick > t0 + 320:
			break
	check(t0 >= 0, "contact detected on the route")
	check(fired_ok, "every member returns fire within 2 s of contact")
	check_eq(dec, "assault", "weak enemy: the leader assaults")
	check(n > 10 and off_sum > men_sum, "officers' mean distance to the enemy (%.2f) > members' (%.2f) over %d samples" % [
		off_sum / maxf(float(n), 1.0), men_sum / maxf(float(n), 1.0), n])


## Fix and flank (enemy of equal strength): element 1 fixes, the other moves to a flank point at least
## 60 degrees off the axis, and the assault goes in on the signal.
func test_fix_and_flank_geometry() -> void:
	var w := _world()
	var hc := _center(w)
	var c := _company(w, FID, hc + Vector2(-30.0, 0.0), 2, 4)
	var own := 4 * 2 + 3
	for k in own:
		w.spawn_unit("rifleman", 0, hc + Vector2(-10.0 + float(k % 3), float(k / 3) - 1.5))
	_order(w, c, "take", hc + Vector2(25.0, 0.0))
	var ct := {}
	var sig_angle := -1.0
	for i in 2400:
		w.step()
		var fs := _fs(w, c)
		ct = fs.get("contact", {})
		if not ct.is_empty() and bool(ct.get("sig", false)) and sig_angle < 0.0:
			var form := Doctrine.node_form(w, FID, "c%d" % int(c.id))
			var g := Op.groups(w, FID, form)
			if (g.els as Array).size() >= 2:
				sig_angle = T.off_axis_deg(ct.from, ct.pos, D.centroid(g.els[1]))
		if sig_angle >= 0.0:
			break
	check_eq(String(ct.get("dec", "")), "fix_flank", "equal strength: fix and flank (odds %.2f)" % float(ct.get("ratio", -1.0)))
	var fp: Array = ct.get("fp", [])
	check(not fp.is_empty(), "a flank point was chosen")
	if not fp.is_empty():
		var a := T.off_axis_deg(ct.from, ct.pos, fp[0])
		check(a >= 60.0, "flank point is %.1f deg off the axis (>= 60)" % a)
	check(sig_angle >= 40.0, "the flank element attacks from the side (%.1f deg off the axis at the signal)" % sig_angle)


## A platoon whose lieutenant dies is leaderless for a while (keeps its last order), then the senior
## squad leader takes over and the platoon takes orders again.
func test_leaderless_gap_then_succession() -> void:
	var w := _world()
	var hc := _center(w)
	var c := _company(w, FID, hc + Vector2(-20.0, 0.0), 2, 4)
	var g1: Dictionary = w.sys_state.ops.groups[int(c.platoons[0])]
	var g2: Dictionary = w.sys_state.ops.groups[int(c.platoons[1])]
	var heir := int(g1.members[0])
	w.destroy(int(g1.officer), "killed", 0)
	w.step()
	check_eq(int(g1.officer), heir, "the senior squad leader is named")
	check(Ops.leaderless(w, g1), "the platoon is leaderless for a moment")
	var before := {}
	for m in g1.members:
		before[int(m)] = str(w.entities[int(m)].order)
	_order(w, c, "take", hc + Vector2(20.0, 0.0))
	w.run_ticks(40)
	var unchanged := true
	for m in g1.members:
		if w.entities.has(int(m)) and str(w.entities[int(m)].order) != String(before[int(m)]):
			unchanged = false
	check(unchanged, "leaderless platoon keeps its last order")
	var moved2 := false
	for m in g2.members:
		if String(w.entities[int(m)].order.get("type", "idle")) != "idle":
			moved2 = true
	check(moved2, "the other platoon takes the new order")
	var gap_end := {}
	for m in g1.members:
		if w.entities.has(int(m)):
			gap_end[int(m)] = (w.entities[int(m)].pos as Vector2)
	w.run_ticks(int(D.num("leaderless_ticks")) + 40)
	check(not Ops.leaderless(w, g1), "the new leader has taken over")
	var moved1 := false
	for m in g1.members:
		if w.entities.has(int(m)) and ((w.entities[int(m)].pos as Vector2).distance_to(gap_end[int(m)]) > 1.0 or str(w.entities[int(m)].order) != String(before[int(m)])):
			moved1 = true
	check(moved1, "the platoon takes orders again under its new leader")


## Movement across a battlefield: the route around a known minefield never crosses it.
func test_route_avoids_known_minefield() -> void:
	var w := _world()
	var hc := _center(w)
	var mines := {}
	for dy in range(-6, 7):
		for dx in range(0, 2):
			mines[Vector2i(int(hc.x) + dx, int(hc.y) + dy)] = true
	var a := hc + Vector2(-15.0, 0.3)
	var b := hc + Vector2(15.0, 0.3)
	check(not T.mines_on_leg(mines, a, b, 0).is_empty(), "the straight line crosses the field")
	var pts := T.route(w, a, b, mines, [])
	var prev := a
	var crossed := 0
	for p in pts:
		crossed += T.mines_on_leg(mines, prev, p, 0).size()
		prev = p
	check_eq(crossed, 0, "no route leg crosses a known mine (%d waypoints)" % pts.size())
	var lines := T.route_lines(w, a, b, mines, [])
	prev = a
	crossed = 0
	for p in lines:
		crossed += T.mines_on_leg(mines, prev, p, 0).size()
		prev = p
	check_eq(crossed, 0, "phase lines along the route avoid the field too (%d lines)" % lines.size())


## execute_order take / hold / cancel end to end, drill_state for the UI, bad input refused.
func test_execute_order_take_hold_end_to_end() -> void:
	var w := _world()
	var hc := _center(w)
	var c := _company(w, FID, hc + Vector2(-20.0, 0.0), 2, 4)
	check(not bool(Doctrine.execute_order(w, FID, 999, {"type": "take", "target": hc}).ok), "unknown node refused")
	check(not bool(_order(w, c, "dance", hc).ok), "unknown order type refused")
	var obj := hc + Vector2(10.0, 0.0)
	var r := _order(w, c, "take", obj)
	check(bool(r.ok), "take accepted: %s" % str(r))
	var done_at := -1
	var drills := {}
	for i in 4000:
		w.step()
		var fs := _fs(w, c)
		drills[String(fs.get("drill", ""))] = true
		if bool(fs.get("done", false)):
			done_at = w.tick
			break
	check(done_at > 0, "objective taken and consolidated (tick %d; drills %s)" % [done_at, str(drills.keys())])
	var ds := Doctrine.drill_state(w, FID, int(c.id))
	check_eq(String(ds.get("order", "")), "take", "drill_state names the order")
	check(String(ds.get("line", "")) != "", "drill_state has a readable line: %s" % String(ds.get("line", "")))
	check(D.centroid(_men(w, c)).distance_to(obj) < 8.0, "the company is on the objective")
	r = Doctrine.execute_order(w, FID, {"cid": int(c.id)}, {"type": "hold", "target": {"x": obj.x, "y": obj.y}})
	check(bool(r.ok), "hold accepted (dict node + dict target)")
	w.run_ticks(300)
	check_eq(String(Doctrine.drill_state(w, FID, "c%d" % int(c.id)).get("drill", "")), "defend", "holding company defends in depth")
	check(bool(Doctrine.execute_order(w, FID, int(c.id), {"type": "cancel"}).ok), "cancel accepted")
	check(not Doctrine.ordered(w, FID, "c%d" % int(c.id)), "cancel releases the company")


func _det_world() -> Array:
	var w := _world()
	var hc := _center(w)
	var c := _company(w, FID, hc + Vector2(-25.0, 0.0), 2, 4)
	for k in 4:
		w.spawn_unit("rifleman", 0, hc + Vector2(-6.0, float(k) - 1.5))
	_order(w, c, "take", hc + Vector2(15.0, 0.0))
	return [w, c]


## Same seed + orders = same hash; the drill state survives a save/load mid-drill.
func test_determinism_and_save_load() -> void:
	var a: SimWorld = _det_world()[0]
	var b: SimWorld = _det_world()[0]
	a.run_ticks(400)
	b.run_ticks(400)
	check_eq(a.state_hash(), b.state_hash(), "two identical runs hash equal after 400 ticks")
	var d := SaveSystem.decode_bytes(SaveSystem.encode_dict(a.to_dict()))
	if not check(d.ok, "decode ok"):
		return
	var l := SimWorld.from_dict(d.dict)
	check(l.sys_state.ops.has("orders61"), "orders survive load")
	a.run_ticks(400)
	l.run_ticks(400)
	check_eq(l.state_hash(), a.state_hash(), "hash equal 400 ticks after a mid-drill load")


# ---------------------------------------------------------------- G6.1 OFF61-2: REAL61 human factors
func _pin(us: Array, on: bool) -> void:
	for e in us:
		e.pinned = on
		e.supp = 100.0 if on else 0.0


## Pinned elements can't bound: with the bounding group pinned the bound is held (no phase line gained,
## drill bound_held) and the men stay put; once freed the bounds go on.
func test_pinned_cannot_bound() -> void:
	var w := _world()
	var hc := _center(w)
	var c := _company(w, FID, hc + Vector2(-30.0, 0.0), 2, 4)
	_order(w, c, "take", hc + Vector2(25.0, 0.0))
	var pin_li := -1
	var held := 0
	var moved := 0.0
	var pos0 := {}
	var li_after := -1
	var gained := 0
	for i in 2600:
		var fs := _fs(w, c)
		if not fs.is_empty():
			fs.seen = w.tick
			fs.ccool = w.tick + 10000
		var pinning := pin_li >= 0 and held < 400
		if pinning:
			_pin(_men(w, c), true)
		w.step()
		fs = _fs(w, c)
		if pin_li < 0 and String(fs.get("drill", "")) == "bounding" and int(fs.get("li", 0)) >= 1:
			pin_li = int(fs.li)
			for e in _men(w, c):
				pos0[int(e.id)] = e.pos
			continue
		if pinning:
			if String(fs.get("drill", "")) == "bound_held":
				held += 1
			if int(fs.get("li", 0)) != pin_li:
				gained += 1
			if held == 399:
				for e in _men(w, c):
					moved = maxf(moved, (e.pos as Vector2).distance_to(pos0.get(int(e.id), e.pos)))
				_pin(_men(w, c), false)
		elif pin_li >= 0 and held >= 400:
			li_after = maxi(li_after, int(fs.get("li", 0)))
	check(pin_li >= 1, "bounding reached phase line %d before the pin" % (pin_li + 1))
	check(held >= 400, "bound held while pinned (%d ticks)" % held)
	check_eq(gained, 0, "no phase line gained while pinned")
	check(moved < 4.0, "pinned men stayed put (max %.1f tiles)" % moved)
	check(li_after > pin_li, "bounds resume once the men are freed (line %d -> %d)" % [pin_li + 1, li_after + 1])


## Exhausted men don't assault: a weak enemy that a fresh platoon would assault gets a fix (base of fire)
## instead, and nobody is ordered onto the contact.
func test_exhausted_do_not_assault() -> void:
	var w := _world()
	var hc := _center(w)
	var c := _company(w, FID, hc + Vector2(-30.0, 0.0), 2, 5)
	var foes_ids := [w.spawn_unit("rifleman", 0, hc + Vector2(-10.0, -0.5)), w.spawn_unit("rifleman", 0, hc + Vector2(-10.0, 0.8))]
	_order(w, c, "take", hc + Vector2(25.0, 0.0))
	var dec := ""
	var dt := -1
	var onto := 0
	for i in 1600:
		for e in _men(w, c) + _officers(w, c):
			e.fat = 1.0
		w.step()
		var ct: Dictionary = _fs(w, c).get("contact", {})
		if dec == "" and not ct.is_empty() and String(ct.get("dec", "")) != "":
			dec = String(ct.dec)
			dt = w.tick
		if dt >= 0:
			var foes := _alive(w, foes_ids)
			if foes.is_empty():
				break
			var fc := Vector2.ZERO
			for f in foes:
				fc += f.pos
			fc /= float(foes.size())
			for e in _men(w, c):
				var o: Dictionary = e.order
				if ["move", "attack_move"].has(String(o.get("type", ""))) and o.has("target") and (o.target as Vector2).distance_to(fc) < 3.0:
					onto += 1
			if w.tick > dt + 200:
				break
	check_eq(dec, "fix", "exhausted platoon: the leader fixes instead of assaulting")
	check_eq(onto, 0, "nobody is ordered onto the contact while exhausted")


## A company order carried down the chain (CHAIN61 CommandNet) becomes a battle drill: the captain's inbox
## is consumed (take_orders) and the net's default executor never acts on it a second time.
func test_commandnet_order_becomes_drill() -> void:
	var net = load("res://sim/systems/command_net.gd")
	if not check(net != null, "CommandNet present"):
		return
	var w := _world()
	var hc := _center(w)
	var c := _company(w, FID, hc + Vector2(-30.0, 0.0), 2, 4)
	var oid: int = net.issue(w, FID, int(c.captain), {"company": int(c.id)}, {"type": "take", "target": hc + Vector2(25.0, 0.0)})
	check(oid > 0, "order issued on the net (%d)" % oid)
	var got := -1
	var by_net := 0
	var by_doc := 0
	for i in 600:
		w.step()
		for ev in w.events:
			if String(ev.type) == "OrderExecuted" and String(ev.get("node", "")) == "c:%d" % int(c.id):
				if String(ev.get("by", "")) == "doctrine":
					by_doc += 1
				elif String(ev.get("by", "")) == "net":
					by_net += 1  # (by "initiative" is CHAIN61's cut-off behaviour, not a second execution)
		if got < 0 and Doctrine.ordered(w, FID, "c%d" % int(c.id)):
			got = w.tick
		if got >= 0 and w.tick > got + 200:
			break
	check(got >= 0, "the delivered order became a drill (tick %d)" % got)
	check_eq(by_doc, 1, "the doctrine executed it once")
	check_eq(by_net, 0, "the net's default executor did not act on it")
	check(net.orders_for(w, int(c.captain)).is_empty(), "the captain's inbox is consumed")
	var ds := Doctrine.drill_state(w, FID, int(c.id))
	check(String(ds.get("drill", "")) != "", "a drill is running: %s" % str(ds))
